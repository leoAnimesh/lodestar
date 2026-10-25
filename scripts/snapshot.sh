#!/bin/bash
# Captures screenshots of Lodestar's windows with sample data (developer aid).
#
#   scripts/snapshot.sh <output-dir> [name-filter]
#
# Runs the debug build with --snapshot, which steps through onboarding, Settings
# and launcher states and lists each window in <output-dir>/manifest.txt; this
# script captures each one with `screencapture -l` (needs Screen Recording
# permission for your terminal). Examples:
#   scripts/snapshot.sh /tmp/shots              every state
#   scripts/snapshot.sh /tmp/shots hero         just the hero-* states, then:
#   swift run Lodestar --render-hero /tmp/hero.png /tmp/shots  # then convert to docs/hero.jpg
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:?usage: scripts/snapshot.sh <output-dir> [name-filter]}"
filter="${2:-}"
mkdir -p "$out"
rm -f "$out/manifest.txt" "$out/done.txt"

swift build >/dev/null
bin="$(swift build --show-bin-path)/Lodestar"
args=(--snapshot "$out")
[ -n "$filter" ] && args+=(--snapshot-only "$filter")
"$bin" "${args[@]}" &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT

seen=0
for _ in $(seq 1 1200); do
  if [ -f "$out/manifest.txt" ]; then
    lines="$(wc -l < "$out/manifest.txt" | tr -d ' ')"
    while [ "$seen" -lt "$lines" ]; do
      seen=$((seen + 1))
      read -r name window rect <<< "$(sed -n "${seen}p" "$out/manifest.txt")"
      case "$name" in
        # The hero states sit on a gradient backdrop; a region capture keeps the
        # window's real translucency (a window-only capture renders it grey).
        hero-*) screencapture -o -x -R"$rect" "$out/$name.png" ;;
        *) screencapture -o -x -l "$window" "$out/$name.png" ;;
      esac
      echo "captured $name"
    done
  fi
  [ -f "$out/done.txt" ] && break
  sleep 0.25
done
