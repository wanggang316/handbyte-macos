#!/usr/bin/env bash
# Optional comparison with a local Go CLI checkout. macOS rules and fixtures
# are maintained in this repository. This command never downloads or copies
# files, and is not part of CI or release builds.
# Usage: HANDBYTE_CLI_SRC=/path/to/handbyte make sync-check
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_catalog="$repo_root/Sources/HandbyteCore/Resources/catalog"
app_conformance="$repo_root/Tests/HandbyteCoreTests/Conformance"
if [[ $# -ne 0 || -z "${HANDBYTE_CLI_SRC:-}" ]]; then
    echo "usage: HANDBYTE_CLI_SRC=/path/to/handbyte make sync-check" >&2
    exit 2
fi
cli_src="$HANDBYTE_CLI_SRC"
cli_label="$cli_src"

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
trap 'rm -rf "$staged"' EXIT
cp "$cli_catalog"/*.json "$staged/"

status=0
diff -r "$staged" "$app_catalog" >&2 || status=1
diff -r "$cli_conformance" "$app_conformance" >&2 || status=1

if [ "$status" -eq 0 ]; then
    count="$(find "$app_catalog" "$app_conformance" -type f | wc -l | tr -d ' ')"
    echo "sync-check: OK, $count shared files match $cli_label"
    exit 0
fi

echo "sync-check: the shared files differ from $cli_label" >&2
echo "Review differences against the macOS requirements before changing local files." >&2
exit 1
