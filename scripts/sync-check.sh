#!/usr/bin/env bash
# Fails when the rule ids in the Go CLI presets and the Swift catalog differ.
# Reads both sources with grep so no Go or Swift toolchain is needed.
#
# The CLI lives in wanggang316/handbyte. HANDBYTE_CLI_SRC names a local
# checkout of it; without one, presets.go is downloaded from GitHub at
# HANDBYTE_CLI_REF (default: main).
#
# Go ids:    every `Source: "<id>"` in presets.go, plus `artifact:<Name>` for
#            every row of ProjectArtifactPatterns.
# Swift ids: every `preset(id: "<id>"` in Catalog.swift, plus `artifact:<name>`
#            for every `artifact(name: "<name>"`.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
swift_catalog="$repo_root/Sources/HandbyteCore/Catalog.swift"
cli_ref="${HANDBYTE_CLI_REF:-main}"

if [ -n "${HANDBYTE_CLI_SRC:-}" ]; then
    go_presets="$HANDBYTE_CLI_SRC/internal/scanner/presets.go"
    go_label="$go_presets"
else
    go_presets="$(mktemp "${TMPDIR:-/tmp}/presets.XXXXXX")"
    trap 'rm -f "$go_presets"' EXIT
    go_label="handbyte@$cli_ref internal/scanner/presets.go"
    curl -fsSL "https://raw.githubusercontent.com/wanggang316/handbyte/$cli_ref/internal/scanner/presets.go" -o "$go_presets" \
        || { echo "sync-check: cannot download presets.go at ref $cli_ref" >&2; exit 2; }
fi

for f in "$go_presets" "$swift_catalog"; do
    if [ ! -f "$f" ]; then
        echo "sync-check: missing $f" >&2
        exit 2
    fi
done

go_ids() {
    grep -oE 'Source:[[:space:]]*"[^"]+"' "$go_presets" | sed -E 's/.*"([^"]+)"/\1/'
    sed -n '/^var ProjectArtifactPatterns/,/^}/p' "$go_presets" \
        | grep -oE '^[[:space:]]*\{"[^"]+"' | sed -E 's/.*"([^"]+)"/artifact:\1/'
}

swift_ids() {
    grep -oE 'preset\(id: "[^"]+"' "$swift_catalog" | sed -E 's/.*"([^"]+)"/\1/'
    grep -oE 'artifact\(name: "[^"]+"' "$swift_catalog" | sed -E 's/.*"([^"]+)"/artifact:\1/'
}

go_sorted="$(go_ids | sort -u)"
swift_sorted="$(swift_ids | sort -u)"

if [ -z "$go_sorted" ] || [ -z "$swift_sorted" ]; then
    echo "sync-check: extracted an empty id set; the source layout changed" >&2
    exit 2
fi

only_go="$(comm -23 <(printf '%s\n' "$go_sorted") <(printf '%s\n' "$swift_sorted"))"
only_swift="$(comm -13 <(printf '%s\n' "$go_sorted") <(printf '%s\n' "$swift_sorted"))"

if [ -z "$only_go" ] && [ -z "$only_swift" ]; then
    count="$(printf '%s\n' "$go_sorted" | wc -l | tr -d ' ')"
    echo "sync-check: OK, $count rule ids match"
    exit 0
fi

echo "sync-check: rule ids differ between the Go CLI and the Swift catalog" >&2
if [ -n "$only_go" ]; then
    echo "only in Go ($go_label):" >&2
    printf '  %s\n' $only_go >&2
fi
if [ -n "$only_swift" ]; then
    echo "only in Swift (Sources/HandbyteCore/Catalog.swift):" >&2
    printf '  %s\n' $only_swift >&2
fi
echo "Update the other side or record an intentional difference in SYNC.md." >&2
exit 1
