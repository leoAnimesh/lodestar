#!/bin/bash
# Tests for scripts/bump-homebrew.sh, on a temp copy of the cask.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/Casks"
cp "$root/Casks/lodestar.rb" "$tmp/Casks/"
sha="$(printf 'a%.0s' $(seq 64))"
printf '%s  Lodestar-9.8.7.zip\n%s  Lodestar-9.8.7.dmg\n' "$(printf 'b%.0s' $(seq 64))" "$sha" > "$tmp/SHA256SUMS.txt"

"$root/scripts/bump-homebrew.sh" 9.8.7 "$tmp/SHA256SUMS.txt" "$tmp" >/dev/null
grep -qx '  version "9.8.7"' "$tmp/Casks/lodestar.rb" || { echo "FAIL: version not bumped"; exit 1; }
grep -qx "  sha256 \"$sha\"" "$tmp/Casks/lodestar.rb" || { echo "FAIL: sha not bumped"; exit 1; }
if command -v ruby >/dev/null; then ruby -c "$tmp/Casks/lodestar.rb" >/dev/null || { echo "FAIL: cask syntax"; exit 1; }; fi

# Missing entry fails without touching the file.
cp "$tmp/Casks/lodestar.rb" "$tmp/before.rb"
if "$root/scripts/bump-homebrew.sh" 1.0.0 "$tmp/SHA256SUMS.txt" "$tmp" 2>/dev/null; then echo "FAIL: missing checksum accepted"; exit 1; fi
cmp -s "$tmp/before.rb" "$tmp/Casks/lodestar.rb" || { echo "FAIL: file changed on error"; exit 1; }
# Bad version fails.
if "$root/scripts/bump-homebrew.sh" v1 "$tmp/SHA256SUMS.txt" "$tmp" 2>/dev/null; then echo "FAIL: bad version accepted"; exit 1; fi
echo "bump-homebrew: all tests passed"
