#!/bin/bash
# Builds a release binary and wraps it in a minimal .app bundle so macOS can
# attribute permissions (Accessibility, Automation) to "Lodestar" rather than
# to your terminal. Output: build/Lodestar.app
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Lodestar"
APP="build/Lodestar.app"
VERSION="${VERSION:-0.1.0}"

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
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Lodestar uses Apple Events for system commands such as Empty Trash, Sleep and Toggle Dark Mode.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature (no developer account needed). Re-granting Accessibility
# may be required after each rebuild because the signature changes.
codesign --force --sign - "$APP"
echo "Built $APP"
