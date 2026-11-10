#!/usr/bin/env bash
# Fails when the shared catalog or the conformance cases in this repository
# differ from the Go CLI. Both are byte-identical copies; the CLI is the
# source of truth.
#
#   CLI catalog/*.json          ->  Sources/HandbyteCore/Resources/catalog/
#   CLI testdata/conformance/   ->  Tests/HandbyteCoreTests/Conformance/
#
# The CLI lives in wanggang316/handbyte. HANDBYTE_CLI_SRC names a local
# checkout of it; without one, the repository is downloaded from GitHub at
# HANDBYTE_CLI_REF (default: main). `scripts/sync-check.sh --update` copies
# the CLI files into this repository instead of comparing them.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_catalog="$repo_root/Sources/HandbyteCore/Resources/catalog"
app_conformance="$repo_root/Tests/HandbyteCoreTests/Conformance"
cli_ref="${HANDBYTE_CLI_REF:-main}"
update=false
[ "${1:-}" = "--update" ] && update=true

if [ -n "${HANDBYTE_CLI_SRC:-}" ]; then
    cli_src="$HANDBYTE_CLI_SRC"
    cli_label="$cli_src"
else
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/handbyte-cli.XXXXXX")"
    trap 'rm -rf "$tmp"' EXIT
    cli_label="handbyte@$cli_ref"
    curl -fsSL "https://codeload.github.com/wanggang316/handbyte/tar.gz/$cli_ref" \
        | tar -xz -C "$tmp" --strip-components=1 \
        || { echo "sync-check: cannot download the CLI at ref $cli_ref" >&2; exit 2; }
    cli_src="$tmp"
fi

cli_catalog="$cli_src/catalog"
cli_conformance="$cli_src/testdata/conformance"
for d in "$cli_catalog" "$cli_conformance"; do
    if [ ! -d "$d" ]; then
        echo "sync-check: missing $d in $cli_label" >&2
        exit 2
    fi
done

# The CLI keeps Go sources beside the catalog; only the JSON files are shared.
staged="$(mktemp -d "${TMPDIR:-/tmp}/handbyte-catalog.XXXXXX")"
trap 'rm -rf "$staged" ${tmp:+"$tmp"}' EXIT
cp "$cli_catalog"/*.json "$staged/"

if $update; then
    rm -rf "$app_catalog" "$app_conformance"
    mkdir -p "$app_catalog"
    cp "$staged"/*.json "$app_catalog/"
    cp -R "$cli_conformance" "$app_conformance"
    echo "sync-check: copied the catalog and the conformance cases from $cli_label"
    exit 0
fi

status=0
diff -r "$staged" "$app_catalog" >&2 || status=1
diff -r "$cli_conformance" "$app_conformance" >&2 || status=1

if [ "$status" -eq 0 ]; then
    count="$(find "$app_catalog" "$app_conformance" -type f | wc -l | tr -d ' ')"
    echo "sync-check: OK, $count shared files match $cli_label"
    exit 0
fi

echo "sync-check: the shared files differ from $cli_label" >&2
echo "Change them in the CLI repository, then run scripts/sync-check.sh --update." >&2
exit 1
