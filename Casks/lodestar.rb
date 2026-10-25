# frozen_string_literal: true

# Homebrew cask for Lodestar. This repository is the tap:
#
#   brew tap leoanimesh/lodestar https://github.com/leoAnimesh/lodestar
#   brew install --cask lodestar
#
# `version` and `sha256` are bumped by scripts/bump-homebrew.sh, which the
# release workflow runs in a pull request after every release
# (see docs/RELEASING.md). Until the first release is published, `sha256` is
# a placeholder and the cask can't be installed.
cask "lodestar" do
  version "0.1.2"
  sha256 "b676b82c87f361bea296ab8950546e7ba8d8ae64d8d9ad57fb0636dc451426e3"

  url "https://github.com/leoAnimesh/lodestar/releases/download/v#{version}/Lodestar-#{version}.dmg"
  name "Lodestar"
  desc "Keyboard launcher for apps, clipboard history, emoji and commands"
  homepage "https://github.com/leoAnimesh/lodestar"

  livecheck do
    url :url
    strategy :github_latest
  end

  # The app updates itself from GitHub Releases, so `brew upgrade` leaves it
  # alone unless you pass --greedy.
  auto_updates true
  depends_on macos: ">= :ventura"

  app "Lodestar.app"

  # Releases are ad-hoc signed (not notarized) until the project has a
  # Developer ID. Without this, macOS refuses to open the app the first time.
  # Remove this block once releases are notarized.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Lodestar.app"],
                   must_succeed: false
  end

  uninstall quit: "io.github.lodestar-launcher"

  # ~/.config/lodestar (your config, scripts and extensions) is deliberately
  # kept; delete it yourself if you no longer want it.
  zap trash: [
    "~/Library/Application Support/Lodestar",
    "~/Library/Preferences/io.github.lodestar-launcher.plist",
  ]
end
