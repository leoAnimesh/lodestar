#!/bin/bash
# Checks what scripts/package-release.sh left in build/release/ before it is published.
#
#   scripts/check-release-assets.sh VERSION                         any build
#   scripts/check-release-assets.sh VERSION --universal             also require arm64 + x86_64
#   scripts/check-release-assets.sh VERSION --team TEAMID           Developer ID build, notarized
#
# Always: the checksums match, the zip holds exactly Lodestar.app with VERSION and
# the right bundle ID, its signature verifies, and the DMG verifies.
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: check-release-assets.sh VERSION [--universal] [--team TEAMID]}"
shift
universal=0
team=""
while [ $# -gt 0 ]; do
  case "$1" in
    --universal) universal=1 ;;
    --team) team="${2:?--team needs a value}"; shift ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
  shift
done

fail() { echo "::error::$*" >&2; exit 1; }
release="build/release"
zip="$release/Lodestar-$version.zip"
dmg="$release/Lodestar-$version.dmg"

(cd "$release" && shasum -a 256 -c SHA256SUMS.txt)
grep -q " Lodestar-$version.zip\$" "$release/SHA256SUMS.txt" || fail "SHA256SUMS.txt doesn't list the zip"
hdiutil verify "$dmg" >/dev/null

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ditto -x -k "$zip" "$work"
entries="$(ls -A "$work")"
[ "$entries" = "Lodestar.app" ] || fail "the zip should contain only Lodestar.app, found: $entries"
app="$work/Lodestar.app"
plist="$app/Contents/Info.plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = "$version" ] || fail "the app is not version $version"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" = "io.github.lodestar-launcher" ] || fail "wrong bundle identifier"
[ -f "$app/Contents/Resources/Lodestar_LodestarCore.bundle/Contents/Resources/emoji.json" ] || fail "emoji data missing"
codesign --verify --deep --strict --verbose=1 "$app"

if [ "$universal" = 1 ]; then
  archs="$(lipo -archs "$app/Contents/MacOS/Lodestar")"
  echo "architectures: $archs"
  case " $archs " in *" arm64 "*) ;; *) fail "missing arm64" ;; esac
  case " $archs " in *" x86_64 "*) ;; *) fail "missing x86_64" ;; esac
fi

if [ -n "$team" ]; then
  codesign -dv "$app" 2>&1 | grep -q "TeamIdentifier=$team" || fail "the app is not signed by team $team"
  codesign -dv "$app" 2>&1 | grep -q 'flags=.*runtime' || fail "the app lacks the hardened runtime"
  xcrun stapler validate "$app"
  xcrun stapler validate "$dmg"
  spctl --assess --type execute --verbose=2 "$app" 2>&1 | grep -q 'source=Notarized Developer ID' || fail "Gatekeeper doesn't see the app as notarized"
fi
echo "release assets for $version look good"
