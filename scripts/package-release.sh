#!/bin/bash
# Builds everything a GitHub release uploads into build/release/:
#   Lodestar-<version>.zip   the app (ditto, --keepParent); the in-app updater installs this
#   Lodestar-<version>.dmg   drag-to-Applications disk image (Homebrew cask, manual installs)
#   SHA256SUMS.txt           shasum -a 256 of both; the updater refuses a zip that isn't listed
#
#   scripts/package-release.sh               build the app (scripts/bundle.sh), then package it
#   scripts/package-release.sh --skip-build  package the existing build/Lodestar.app (after stapling)
#
# Uses the same environment as bundle.sh (VERSION, BUILD_NUMBER, ARCH_FLAGS, SIGN_IDENTITY).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Lodestar.app"
OUT="build/release"
ZIP="$OUT/Lodestar-$VERSION.zip"
DMG="$OUT/Lodestar-$VERSION.dmg"

if [ "${1:-}" != "--skip-build" ]; then
  VERSION="$VERSION" ./scripts/bundle.sh
fi
[ -d "$APP" ] || { echo "error: $APP is missing; run scripts/bundle.sh" >&2; exit 1; }
built="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "$built" = "$VERSION" ] || { echo "error: $APP is version $built, expected $VERSION" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"

# Zip: what the updater downloads. --keepParent puts Lodestar.app at the top.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# DMG: the app plus an /Applications shortcut. hdiutil sometimes fails with
# "Resource busy" on CI runners, so it is retried.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto "$APP" "$stage/Lodestar.app"
ln -s /Applications "$stage/Applications"
for attempt in 1 2 3; do
  hdiutil create -volname "Lodestar $VERSION" -srcfolder "$stage" -fs HFS+ -format UDZO \
    -imagekey zlib-level=9 -ov "$DMG" >/dev/null && break
  [ "$attempt" = 3 ] && exit 1
  echo "hdiutil failed, retrying" >&2
  sleep 5
done
if [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

./scripts/write-checksums.sh "$VERSION"
