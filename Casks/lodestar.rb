# frozen_string_literal: true

# Homebrew cask for Lodestar. This repository is the tap:
#
#   brew tap leoanimesh/lodestar https://github.com/leoAnimesh/lodestar
#   brew install --cask lodestar
#
# `version` and `sha256` are bumped by scripts/bump-homebrew.sh, which the
# release workflow runs in a pull request after every release
# (see docs/RELEASING.md). Releases are signed with a Developer ID and
# notarized, so macOS opens the app without a Gatekeeper prompt.
cask "lodestar" do
  version "0.1.2"
  sha256 "b676b82c87f361bea296ab8950546e7ba8d8ae64d8d9ad57fb0636dc451426e3"

  url "https://github.com/leoAnimesh/lodestar/releases/download/v#{version}/Lodestar-#{version}.dmg"
  name "Lodestar"
  desc "Keyboard launcher for apps, clipboard history, emoji and commands"
  homepage "https://leoanimesh.github.io/lodestar/"

  livecheck do
    url :url
    strategy :github_latest
  end

  # The app updates itself from GitHub Releases, so `brew upgrade` leaves it
  # alone unless you pass --greedy.
  auto_updates true
  depends_on macos: ">= :ventura"

  app "Lodestar.app"

  uninstall quit: "io.github.lodestar-launcher"

  # ~/.config/lodestar (your config, scripts and extensions) is deliberately
  # kept; delete it yourself if you no longer want it.
  zap trash: [
    "~/Library/Application Support/Lodestar",
    "~/Library/Preferences/io.github.lodestar-launcher.plist",
  ]
end
