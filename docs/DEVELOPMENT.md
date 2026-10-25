# Development

Requires macOS 13+ and a Swift 5.9+ toolchain (Xcode or the Command Line Tools).

```bash
swift build                      # debug build
swift test                       # unit tests (+ a Node protocol test if `node` is installed)
swift run Lodestar --show        # run and show the launcher immediately
swift run Lodestar --onboarding  # run and open the welcome window
swift run Lodestar --clipboard-selftest  # check clipboard capture on a private pasteboard

./scripts/bundle.sh              # release build wrapped as build/Lodestar.app (ad-hoc signed)
open build/Lodestar.app
```

Run the bundled app rather than the bare binary when testing permissions: otherwise macOS attributes
Accessibility and Automation to your terminal. Each rebuild changes the ad-hoc signature, so you may
need to remove and re-add Lodestar under Accessibility.

IDE "No such module" errors from SourceKit are noise; trust `swift build`.

## Version

The version lives in one place: the `VERSION` file. `scripts/bundle.sh` stamps it into the app's
`CFBundleShortVersionString` (and the commit count into `CFBundleVersion`); the app and the updater read
it from there. `scripts/release.sh` changes it. See [RELEASING.md](RELEASING.md).

## Project layout

```
Sources/
  LodestarCore/            pure Swift, no AppKit, unit tested
    FuzzyMatcher.swift     subsequence matcher + highlight indices
    Ranking.swift          ranker + frecency store
    Calculator.swift       expression evaluator
    HotkeySpec.swift       "cmd+shift+k" <-> Carbon key codes, recorder validation
    ScriptCommand.swift    script metadata parser
    ExtensionProtocol.swift manifest, wire messages, line framing
    Config.swift           config file (load + key-preserving save) + paths
    CommandPreferences.swift  enable/alias/hotkey model, conflicts
    ClipboardModel.swift   clipboard entries, link/color detection, sections, filters
    AppPreferences.swift   appearance, launcher position, onboarding decision
    Emoji/                 catalog, search, skin tones, recents/favorites, grid navigation
    Update/                updater logic: SemanticVersion, GitHub release parsing and asset
                           selection, SHA256SUMS parsing, host allowlist, release-notes blocks,
                           AppReplacer (install-location checks, bundle validation, atomic swap)
    Resources/emoji.json   generated emoji & symbol data (Unicode License v3)
  Lodestar/                the app
    main.swift, AppDelegate.swift   accessory app, status item, key routing
    Updates/               UpdateManager (schedule, ETag-cached check, install flow),
                           UpdateNetwork (allowlisted URLSession), UpdateInstaller, UpdateWindow
    GlobalHotKey.swift     Carbon RegisterEventHotKey wrapper
    Settings*.swift        settings window, tabs, command table
    Onboarding/            welcome window and tour
    UI/                    brand mark + icon renderer, hero banner, shared components
    SnapshotTour.swift     --snapshot: steps through every screen for screenshots
    LauncherPanel.swift    floating non-activating NSPanel
    LauncherViewModel.swift, LauncherView.swift, RootScreen.swift
    ExtensionHost.swift    extension registry + child processes
    Providers/             apps, clipboard, emoji, files, scripts, colors, caffeinate
```

Everything the user can navigate into is a `ListScreen`: the root search, clipboard history (a split
view), the emoji grid, file search, a script argument prompt or an extension session. The view model
keeps a stack of screens; the ⌘K popover floats over whichever is showing.

## Screenshots and the hero image

Never take README screenshots of your real Mac. Use the snapshot tour, which shows sample data:

```bash
scripts/snapshot.sh /tmp/shots              # every onboarding step, Settings tab and launcher state
scripts/snapshot.sh /tmp/shots clipboard    # only states whose name contains "clipboard"
```

The hero banner (`docs/hero.jpg`) is drawn in code (`Sources/Lodestar/UI/HeroArt.swift`) around real
launcher windows captured over the banner's own gradient:

```bash
scripts/snapshot.sh /tmp/shots hero
swift run Lodestar --render-hero /tmp/hero.png /tmp/shots
sips -s format jpeg -s formatOptions 88 /tmp/hero.png --out docs/hero.jpg
sips -s format jpeg -s formatOptions 85 -z 640 1280 /tmp/hero.png --out docs/social-preview.jpg
```

`docs/social-preview.jpg` is for the repository's social preview (Settings › General › Social preview
on GitHub; it can only be uploaded in the browser).

## Testing the updater locally

The updater normally talks only to GitHub over HTTPS. Two environment variables let you test the whole
flow against a local server, without publishing anything:

- `LODESTAR_UPDATE_URL` — the feed to read instead of `api.github.com/…/releases/latest` (a single
  release object or a list, in GitHub's JSON shape). Also allows plain HTTP to `127.0.0.1`/`localhost`.
- `LODESTAR_UPDATE_AUTOINSTALL=1` — only together with the above: installs a found update without
  showing the window.

```bash
E=$(mktemp -d)
./scripts/bundle.sh && ditto build/Lodestar.app "$E/Applications/Lodestar.app"   # the "installed" 0.1.0
VERSION=9.9.9 scripts/package-release.sh                                         # a newer build
mkdir "$E/server" && cp build/release/Lodestar-9.9.9.zip build/release/SHA256SUMS.txt "$E/server/"
cat > "$E/server/latest.json" <<JSON
{"tag_name":"v9.9.9","name":"Lodestar 9.9.9","body":"## Test\n- hello","assets":[
 {"name":"Lodestar-9.9.9.zip","browser_download_url":"http://127.0.0.1:8765/Lodestar-9.9.9.zip"},
 {"name":"SHA256SUMS.txt","browser_download_url":"http://127.0.0.1:8765/SHA256SUMS.txt"}]}
JSON
(cd "$E/server" && python3 -m http.server 8765 --bind 127.0.0.1) &
CFFIXED_USER_HOME="$E/home" LODESTAR_UPDATE_URL=http://127.0.0.1:8765/latest.json \
  "$E/Applications/Lodestar.app/Contents/MacOS/Lodestar" --check-for-updates
```

`--check-for-updates` checks right after launch. Quit your normal Lodestar first, and use a copy
outside the repository: a `build/Lodestar.app` next to `Package.swift` counts as a development build and
is never replaced (the updater offers the release page instead). `CFFIXED_USER_HOME` keeps the test
instance's preferences and clipboard history away from your real ones. Afterwards, rebuild your normal
app with `./scripts/bundle.sh` (packaging 9.9.9 replaced `build/Lodestar.app`) and empty
`previous-Lodestar.app` from the Trash.

Tamper with `SHA256SUMS.txt`, remove the zip's line, or change the tag to check that the install fails
closed and leaves the installed app untouched.
