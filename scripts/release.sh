#!/bin/bash
# Cuts a release: sets the VERSION file, commits, tags vX.Y.Z and pushes.
# Pushing the tag starts .github/workflows/release.yml, which builds, tests,
# packages and publishes the GitHub release.
#
#   scripts/release.sh 0.2.0            release exactly this version
#   scripts/release.sh patch|minor|major  bump the current VERSION
#   scripts/release.sh 0.2.0-beta.1     a pre-release (published as such)
#
# Options:
#   --yes       don't ask before pushing
#   --no-push   commit and tag locally only (push later with: git push origin main vX.Y.Z)
#
# Requires a clean working tree on main that is up to date with origin/main.
set -euo pipefail
cd "$(dirname "$0")/.."

assume_yes=0
push=1
target=""
for arg in "$@"; do
  case "$arg" in
    --yes|-y) assume_yes=1 ;;
    --no-push) push=0 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 64 ;;
    *) [ -z "$target" ] || { echo "only one version, please" >&2; exit 64; }; target="$arg" ;;
  esac
done
[ -n "$target" ] || { echo "usage: scripts/release.sh <X.Y.Z|patch|minor|major> [--yes] [--no-push]" >&2; exit 64; }

current="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  echo "VERSION file holds '$current', which isn't X.Y.Z" >&2; exit 1
fi
major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"; patch="${BASH_REMATCH[3]}"
case "$target" in
  patch) version="$major.$minor.$((patch + 1))" ;;
  minor) version="$major.$((minor + 1)).0" ;;
  major) version="$((major + 1)).0.0" ;;
  *) version="${target#v}" ;;
esac
if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'; then
  echo "'$version' isn't a version like 1.2.3 or 1.2.3-beta.1" >&2; exit 1
fi
tag="v$version"

branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "main" ] || { echo "switch to main first (on '$branch')" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "the working tree has uncommitted changes" >&2; exit 1; }
git fetch --quiet --tags origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "main differs from origin/main; pull or push first" >&2; exit 1; }
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "tag $tag already exists" >&2; exit 1
fi

echo "Running tests…"
swift test >/dev/null

if [ "$version" != "$current" ]; then
  printf '%s\n' "$version" > VERSION
  git add VERSION
  git commit -q -m "chore(release): $tag"
  echo "Committed VERSION $current -> $version"
else
  echo "VERSION is already $version; tagging the current commit"
fi
git tag -a "$tag" -m "Lodestar $version"
echo "Tagged $tag"

if [ "$push" = 0 ]; then
  echo "Not pushed. When ready: git push origin main $tag"
  exit 0
fi
if [ "$assume_yes" = 0 ]; then
  printf 'Push main and %s to origin? This publishes the release. [y/N] ' "$tag"
  read -r answer
  case "$answer" in
    y|Y|yes) ;;
    *) echo "Not pushed. Undo with: git tag -d $tag$([ "$version" != "$current" ] && echo " && git reset --hard HEAD~1")"; exit 1 ;;
  esac
fi
git push origin main
git push origin "$tag"
echo "Pushed. Follow the build at https://github.com/leoAnimesh/lodestar/actions"
