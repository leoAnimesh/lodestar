#!/bin/bash
# Writes build/release/SHA256SUMS.txt for the release's zip and dmg.
# The release workflow runs it again after stapling, which changes the DMG.
set -euo pipefail
cd "$(dirname "$0")/../build/release"
VERSION="${1:?usage: write-checksums.sh VERSION}"
shasum -a 256 "Lodestar-$VERSION.zip" "Lodestar-$VERSION.dmg" > SHA256SUMS.txt
cat SHA256SUMS.txt
