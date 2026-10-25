#!/bin/bash
# Prints the top of a release's notes: the hand-written summary in
# docs/release-notes/VERSION.md (if any) and install instructions. GitHub's
# generated change list is appended after this by `gh release create --generate-notes`.
#
#   scripts/release-notes.sh VERSION [SIGNED=true|false]
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?usage: release-notes.sh VERSION [true|false]}"
signed="${2:-false}"

if [ -f "docs/release-notes/$version.md" ]; then
  cat "docs/release-notes/$version.md"
  echo
fi

cat <<NOTES
## Install

Download **Lodestar-$version.dmg**, open it and drag Lodestar to Applications. Needs macOS 13 or later; works on Apple silicon and Intel Macs.

Already using Lodestar? It updates itself: choose **Check for Updates…** from the menu bar icon.

NOTES

if [ "$signed" != "true" ]; then
cat <<'NOTES'
**First launch:** this build isn't notarized by Apple yet, so macOS blocks it the first time. Right-click Lodestar in Applications and choose **Open**, then **Open** again (on macOS 15 or later: try to open it once, then go to System Settings › Privacy & Security and click **Open Anyway**). Or run `xattr -dr com.apple.quarantine /Applications/Lodestar.app` in Terminal.

NOTES
fi

cat <<NOTES
**Homebrew:** \`brew tap leoanimesh/lodestar https://github.com/leoAnimesh/lodestar && brew install --cask lodestar\`

**Verify downloads:** \`shasum -a 256 -c SHA256SUMS.txt\` in the folder with the files.

NOTES
