#!/bin/bash
# Builds a release binary and wraps it in a minimal .app bundle so macOS can
# attribute permissions (Accessibility, Automation) to "Lodestar" rather than
# to your terminal. Output: build/Lodestar.app
#
# Environment (all optional):
#   VERSION        marketing version; defaults to the VERSION file (single source of truth)
#   BUILD_NUMBER   CFBundleVersion; defaults to the commit count, so it only grows along main
#   ARCH_FLAGS     extra swift build flags, e.g. "--arch arm64 --arch x86_64" for a universal app
#   SIGN_IDENTITY  "-" (default) signs ad hoc; a "Developer ID Application: … (TEAMID)" identity
#                  signs with the hardened runtime and a secure timestamp, ready for notarization
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
# shellcheck disable=SC2086  # ARCH_FLAGS is a list of flags
read -r -a ARCH <<< "${ARCH_FLAGS:-}"
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'; then
  echo "error: VERSION must look like 1.2.3 or 1.2.3-beta.1, got '$VERSION'" >&2
  exit 1
fi

swift build -c release ${ARCH[@]+"${ARCH[@]}"}
BIN="$(swift build -c release ${ARCH[@]+"${ARCH[@]}"} --show-bin-path)/Lodestar"
APP="build/Lodestar.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lodestar"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
# SwiftPM resource bundle (emoji data). LodestarCore looks for it in
# Contents/Resources; see EmojiCatalog.bundledDataURL().
RESOURCES="$(dirname "$BIN")/Lodestar_LodestarCore.bundle"
if [ ! -f "$RESOURCES/Contents/Resources/emoji.json" ]; then
  echo "error: $RESOURCES is missing emoji.json" >&2
  exit 1
fi
cp -R "$RESOURCES" "$APP/Contents/Resources/"

# App icon: the art is drawn in SwiftUI (Sources/Lodestar/UI/Brand.swift);
# the binary renders it to an .iconset, then iconutil packs the .icns.
ICONSET="$(mktemp -d)/AppIcon.iconset"
if "$BIN" --render-icon "$ICONSET" && iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"; then
  ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
  echo "warning: could not render the app icon; continuing without one" >&2
  ICON_KEY=""
fi
rm -rf "$(dirname "$ICONSET")"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.lodestar-launcher</string>
  <key>CFBundleName</key><string>Lodestar</string>
  <key>CFBundleDisplayName</key><string>Lodestar</string>
  <key>CFBundleExecutable</key><string>Lodestar</string>
  ${ICON_KEY}
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Lodestar uses Apple Events for system commands such as Empty Trash, Sleep and Toggle Dark Mode.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature by default (no developer account needed). Re-granting
# Accessibility may be required after each rebuild because the signature
# changes. The bundle has no nested code, so signing it signs the executable.
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict --verbose=1 "$APP"
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"
