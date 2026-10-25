# Releasing

Releases are cut by pushing a version tag. Everything else is automated.

## Cut a release

```bash
scripts/release.sh 0.2.0          # or: patch | minor | major | 0.3.0-beta.1
```

The script checks that you're on a clean `main` that matches `origin/main`, runs the tests, writes the
`VERSION` file, commits `chore(release): v0.2.0`, creates an annotated tag `v0.2.0`, asks for
confirmation, and pushes `main` and the tag. `--no-push` stops before pushing; `--yes` skips the
question. If `VERSION` already holds the version (as for the very first release), it tags the current
commit without a new commit.

Optional: write `docs/release-notes/0.2.0.md` before releasing; it's placed at the top of the release
notes, above GitHub's generated list of changes.

## What the workflow does

`.github/workflows/release.yml` runs on every `v*` tag (or manually, for an existing tag):

1. Checks the tag matches the `VERSION` file.
2. `swift build` and `swift test`.
3. Builds a universal (Apple silicon + Intel) `Lodestar.app` with `scripts/package-release.sh`, which
   produces in `build/release/`:
   - `Lodestar-X.Y.Z.zip` — the app, made with `ditto -c -k --keepParent`. The in-app updater installs this.
   - `Lodestar-X.Y.Z.dmg` — drag-to-Applications disk image (also used by the Homebrew cask).
   - `SHA256SUMS.txt` — SHA-256 of both. The updater refuses a zip that isn't listed or doesn't match.
4. Signs and notarizes, if the signing secrets are set (see below).
5. Checks the assets (`scripts/check-release-assets.sh`): checksums, the zip holds exactly
   `Lodestar.app` with the right version and bundle ID, valid signature, both architectures.
6. Publishes the GitHub release with the install notes (`scripts/release-notes.sh`) plus GitHub's
   generated notes. Tags with a suffix (`v1.0.0-beta.1`) become pre-releases, which the app offers
   only to people who turned on **Include pre-releases**.
7. Opens a pull request bumping `Casks/lodestar.rb` to the new version and DMG checksum (stable
   releases only). Merge it to update the Homebrew tap. This needs **Settings › Actions › General ›
   Allow GitHub Actions to create and approve pull requests**; if the job fails, run
   `scripts/bump-homebrew.sh X.Y.Z SHA256SUMS.txt` locally and commit the result.

`.github/workflows/ci.yml` runs the build, tests and a full unsigned packaging dry run on every push to
`main` and every pull request.

## Signing and notarization

Without secrets, releases are **ad-hoc signed**. They work, but macOS asks the user to approve the app
on first launch (the README explains how), and Accessibility may need to be re-granted after each
update because the signature changes.

To ship Developer ID-signed, notarized releases, add these repository secrets (all six, or none):

| Secret | What it is |
| --- | --- |
| `APPLE_TEAM_ID` | Your 10-character Team ID |
| `DEVELOPER_ID_P12` | Base64 of a `.p12` export of your "Developer ID Application" certificate and key (`base64 -i cert.p12 \| pbcopy`) |
| `DEVELOPER_ID_P12_PASSWORD` | The `.p12` export password |
| `APPLE_API_KEY_ID` | App Store Connect API key ID (for `notarytool`) |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID |
| `APPLE_API_KEY_P8` | Contents of the `AuthKey_XXXX.p8` file |

With them set, the workflow signs with the hardened runtime, notarizes and staples the app and the DMG,
and checks Gatekeeper accepts them. Once you're shipping notarized builds:

- remove the `postflight` quarantine block from `Casks/lodestar.rb`,
- drop the first-launch note from the README and `scripts/release-notes.sh` (it's printed only for
  unsigned builds already).

A Developer ID-signed Lodestar only accepts updates signed by the same team; an ad-hoc copy can
install a signed update (that's the upgrade path).

## Fixing a release

- **Build failed:** fix on `main`, delete the tag (`git push --delete origin vX.Y.Z && git tag -d vX.Y.Z`),
  and release again — or bump to the next patch version.
- **Assets need rebuilding:** run the workflow manually (Actions › Release › Run workflow) with the
  tag; it replaces the assets of the existing release.
- **Bad release published:** mark it as a pre-release or draft on GitHub (the updater ignores both
  unless pre-releases are enabled) and ship a fixed patch version.
