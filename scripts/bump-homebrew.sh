#!/bin/bash
# Points the Homebrew cask (Casks/lodestar.rb) at a release.
#
#   scripts/bump-homebrew.sh VERSION SHA256SUMS.txt [ROOT]
#
# Reads the SHA-256 of Lodestar-VERSION.dmg from the release's SHA256SUMS.txt
# and rewrites the cask's `version` and `sha256`. ROOT defaults to the
# repository root (the test passes a temp copy). Checks everything before
# writing, so a reshaped file fails loudly instead of half-bumping.
set -euo pipefail

[ $# -ge 2 ] || { echo "usage: $0 VERSION SHA256SUMS.txt [ROOT]" >&2; exit 64; }
version="$1"
sums="$2"
root="${3:-$(git rev-parse --show-toplevel)}"
cask="$root/Casks/lodestar.rb"
fail() { echo "bump-homebrew: $*" >&2; exit 1; }

printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "version must look like 1.2.3, got '$version'"
[ -f "$sums" ] || fail "no such file: $sums"
[ -f "$cask" ] || fail "no such file: $cask"

hashes="$(awk -v name="Lodestar-$version.dmg" '$2 == name || $2 == "*" name { print $1 }' "$sums")"
[ "$(printf '%s\n' "$hashes" | grep -c .)" = 1 ] || fail "expected one checksum for Lodestar-$version.dmg in $sums"
printf '%s' "$hashes" | grep -Eqx '[0-9a-f]{64}' || fail "malformed checksum for Lodestar-$version.dmg"

[ "$(grep -Ec '^  version "[^"]*"$' "$cask")" = 1 ] || fail "expected one version line in $cask"
[ "$(grep -Ec '^  sha256 ("[0-9a-f]*"|:no_check)$' "$cask")" = 1 ] || fail "expected one sha256 line in $cask"

tmp="$(mktemp "$cask.XXXXXX")"
awk -v v="  version \"$version\"" -v s="  sha256 \"$hashes\"" '
  /^  version "[^"]*"$/ { print v; next }
  /^  sha256 ("[0-9a-f]*"|:no_check)$/ { print s; next }
  { print }' "$cask" > "$tmp"
mv "$tmp" "$cask"
echo "Casks/lodestar.rb -> $version ($hashes)"
