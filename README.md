# Lodestar

An open-source, keyboard-driven launcher for macOS. Press **⌥Space**, type a few letters, hit Return.

> **Independent project.** Lodestar is not affiliated with, endorsed by, or derived from the source code of Raycast or Raycast Technologies Ltd. It is a clean-room implementation of a common app category (Spotlight, Alfred, LaunchBar and others are in the same space). No proprietary code, decompiled code, assets, icons, or text from any other product are included. "Raycast" is a trademark of its owner.

## Features

| Feature | Notes |
| --- | --- |
| Global hotkey | ⌥Space by default (Carbon `RegisterEventHotKey`; needs no permission). Change it in Settings with the shortcut recorder; it applies immediately, no restart. |
| Settings window | Shortcut recorder, launch at login (`SMAppService`), clipboard-history options. Open it from the menu-bar item or with ⌘, in the launcher. |
| Floating launcher panel | Non-activating `NSPanel`, so your current app stays frontmost and paste/window actions target it. |
| App search | Scans `/Applications`, `/System/Applications`, `~/Applications`, etc. |
| Fuzzy ranking | DP-based subsequence matcher with word-start/acronym/consecutive bonuses, blended with **frecency** (use count with a 7-day half-life). Matched letters are bolded. |
| Calculator | Inline results for expressions like `2^10 / 3`, `sqrt(2)*pi`, `5!`, `3 x 4`. Return copies, ⌘Return pastes. |
| Clipboard history | Text only, up to 300 entries, stored owner-only (0600) in `~/Library/Application Support/Lodestar/clipboard.json`. Skips items that password managers mark concealed or transient. |
| Window management | Halves, thirds, two-thirds, maximize, almost maximize, center, next display (Accessibility API). |
| System commands | Lock, Sleep, Sleep Displays, Restart, Shut Down, Log Out, Empty Trash, Toggle Dark Mode, Hide All Apps, Quit All Apps, Eject All Disks. Destructive ones ask for confirmation. |
| File search | Spotlight-backed (`NSMetadataQuery`), scoped to your home folder. |
| Script commands | Any executable script with `@lodestar.*` metadata comments. |
| Extensions | Any language; JSON over stdio. Includes a tiny Node SDK. |
| Fallbacks | Open the query as a URL, or search the web (DuckDuckGo). |

### Keyboard

| Key | Action |
| --- | --- |
| ↑ / ↓, ⌃P / ⌃N | Move the selection |
| Return | Primary action |
| ⌘Return | Secondary action |
| ⌘K | Show all actions for the selected item |
| ⌘, | Open Settings |
| Esc | Close the detail view, go back, clear the query, then hide |

## Build & run

Requires macOS 13+ and a Swift 5.9+ toolchain (Xcode or the Command Line Tools).

```bash
swift build                 # debug build
swift test                  # unit tests (+ a Node protocol test if `node` is installed)
swift run Lodestar --show   # run and show the panel immediately

./scripts/bundle.sh         # release build wrapped as build/Lodestar.app (ad-hoc signed)
open build/Lodestar.app
```

Lodestar runs as a menu-bar accessory: it has no Dock icon and shows a magnifying-glass status item.

**Permissions.** Window management, auto-paste (⌘V synthesis) and Lock Screen need **Accessibility** access. Grant it in System Settings › Privacy & Security › Accessibility, or use the status-bar menu item. Run the bundled `.app` rather than the bare binary, because otherwise macOS attributes the permission to your terminal. System commands that use Apple Events will prompt for **Automation** the first time.

**Hotkey conflicts.** If another app (for example another launcher) already owns ⌥Space, registration fails. At launch a message is logged. In Settings the recorder shows the error inline and keeps your previous shortcut. Pick a different one in **Settings…** from the menu-bar item.

## Configuration

`~/.config/lodestar/config.json` (every key is optional):

```json
{
  "hotkey": "cmd+shift+space",
  "appDirectories": ["~/Dev/Apps"],
  "clipboardHistoryLimit": 300,
  "clipboardHistoryEnabled": true
}
```

The Settings window reads and writes this same file. It rewrites only the keys it manages and leaves any other keys alone. If the file isn't valid JSON, Settings shows an error instead of overwriting it.

- `hotkey` changes from Settings take effect immediately. The default (⌥Space) is stored by omitting the key.
- Hand edits to the file, and the clipboard options, are read at launch, so restart Lodestar after changing them.
- Scripts and extensions can be reloaded live with the **Reload Scripts and Extensions** command.

## Settings

Open **Settings…** from the menu-bar item, or press **⌘,** while the launcher is open.

- **Shortcut.** Click the shortcut field, then press the new combo. It must include ⌘, ⌥ or ⌃ (Shift alone isn't enough). **Esc** cancels, and **Delete** restores ⌥Space. The new shortcut is registered right away and saved to `config.json` in the same `"option+space"` format the parser reads. While the field is recording, the global shortcut is paused so pressing the current combo doesn't toggle the launcher. If the combo can't be registered, an inline error appears and the previous shortcut stays active. macOS doesn't always report conflicts with other apps' shortcuts, so if the new combo does nothing, pick another.
- **Launch at login.** Uses `SMAppService.mainApp` (macOS 13+). **This only works when running the bundled `build/Lodestar.app`** from `./scripts/bundle.sh`. When run via `swift run`, the toggle is disabled. If macOS asks for approval, Settings links to System Settings › General › Login Items. Move the app to a stable location (for example `/Applications`) before enabling it, since the login item points at the app's current path.
- **Clipboard history.** Enable or disable it and set how many entries are kept. Applies on next launch.

## Script commands

Drop executable scripts into `~/.config/lodestar/scripts/`. Metadata lives in comments (`#`, `//` or `--`):

```bash
#!/bin/bash
# @lodestar.schemaVersion 1
# @lodestar.title Show Local IP Address
# @lodestar.mode compact          # silent | compact | fullOutput
# @lodestar.icon 🌐               # emoji, sf:<symbol-name>, or /absolute/path.png
# @lodestar.description Optional subtitle
# @lodestar.keywords network,ip
# @lodestar.argument1 { "type": "text", "placeholder": "Optional single argument" }
ipconfig getifaddr en0
```

- `silent`: runs the script and hides the launcher.
- `compact`: shows the last line of output in the footer.
- `fullOutput`: shows all output in a detail view.
- A non-zero exit always shows the output.

For compatibility with the community script-command format, the `@raycast.` metadata prefix is also accepted. See `Examples/scripts/` and the **Create Script Command** command.

## Extensions

An extension is a folder in `~/.config/lodestar/extensions/<name>/` that contains a `manifest.json`:

```json
{
  "name": "emoji-search",
  "title": "Emoji",
  "icon": "😀",
  "run": ["node", "index.js"],
  "commands": [
    { "name": "search", "title": "Search Emoji", "mode": "list", "keywords": ["emoji"] }
  ]
}
```

`run` is the argv to start. Interpreters such as `node` and `python3` are resolved through `PATH`, with Homebrew paths added. `./relative` paths are resolved against the extension folder. Each time a command is invoked, Lodestar spawns the process and exchanges **one JSON object per line** on stdin/stdout. stderr goes to the system log.

**Host → extension**

```json
{"type":"run","command":"search","query":"","protocol":1}
{"type":"query","text":"rock"}
{"type":"callback","id":"refresh"}
```

**Extension → host**

```json
{"type":"items","items":[{"id":"1","title":"rocket","subtitle":"…","icon":"🚀","accessory":"…",
  "actions":[{"type":"paste","text":"🚀"},{"type":"copy","text":"🚀"},
             {"type":"open","url":"https://…"},{"type":"callback","id":"refresh"}]}]}
{"type":"detail","markdown":"long text"}
{"type":"toast","message":"Done"}
{"type":"close"}
{"type":"error","message":"…"}
```

Actions are **declarative**, so the host performs privileged work (pasting, opening) on the extension's behalf, and extensions never need macOS permissions. The first action runs on Return and the rest are available via ⌘K. `callback` actions round-trip to your process so you can update the list.

- `list` commands stay alive while the user is in them and receive `query` messages as the user types. The process gets SIGTERM when the user leaves.
- `no-view` commands run detached and can send a `toast`.

For Node, `sdk/js/lodestar.js` (zero dependencies) handles the framing:

```js
const lodestar = require("./lodestar");
lodestar.command("search", {
  onQuery(text, ui) {
    ui.items([{ title: `You typed ${text}`, actions: [lodestar.copy(text)] }]);
  },
});
lodestar.start();
```

To try the examples:

```bash
mkdir -p ~/.config/lodestar/extensions ~/.config/lodestar/scripts
cp -R Examples/extensions/* ~/.config/lodestar/extensions/
cp sdk/js/lodestar.js ~/.config/lodestar/extensions/emoji-search/
cp Examples/scripts/*.sh ~/.config/lodestar/scripts/
```

**Security note.** Extensions and scripts run with your user privileges and are not sandboxed. Only install ones you trust.

## Architecture

```
Sources/
  LodestarCore/            pure Swift, no AppKit, unit tested
    FuzzyMatcher.swift     DP subsequence matcher + highlight indices
    Ranking.swift          Ranker + FrecencyStore (JSON persisted)
    Calculator.swift       recursive-descent evaluator
    HotkeySpec.swift       "cmd+shift+k" <-> Carbon key code / modifiers, ⌥Space display,
                           recorder validation
    ScriptCommand.swift    script metadata parser
    ExtensionProtocol.swift manifest + wire messages + line framing
    Config.swift           config file (load + key-preserving save) + paths
  Lodestar/                the app
    main.swift, AppDelegate.swift   accessory app, status item, key routing
    GlobalHotKey.swift     Carbon RegisterEventHotKey wrapper (live re-register, suspend)
    SettingsWindow.swift   settings model, hotkey recorder event monitor, window
    SettingsView.swift     SwiftUI settings form + recorder control
    LaunchAtLogin.swift    SMAppService.mainApp wrapper
    LauncherPanel.swift    floating non-activating NSPanel + vibrancy
    LauncherViewModel.swift screen stack, selection, ⌘K action panel
    LauncherView.swift     SwiftUI UI
    RootScreen.swift       apps + commands + calculator + fallbacks
    ExtensionHost.swift    registry + per-command child process sessions
    Providers/             AppIndex, ClipboardHistory, WindowManager,
                           FileSearch, ScriptCommands
```

Everything the user can navigate into is a `ListScreen`: root search, clipboard history, file search, a script argument prompt, an extension session, or the ⌘K action list. The view model keeps a stack of screens. Asynchronous sources such as Spotlight and extensions push results through `ScreenHost.setItems`.

### Design background

Before writing Lodestar, we statically inspected a commercial launcher's shipped app bundle to learn which macOS mechanisms this class of app relies on. We read its plist, linked frameworks, imported symbol names and bundle layout; no code was decompiled or copied. Findings that shaped the design:

- It runs as a menu-bar agent (`LSUIElement`) and registers its global shortcut with Carbon `RegisterEventHotKey`. It also imports `CGEventTapCreate`, presumably for text expansion.
- It uses AppKit panels and a `WKWebView` UI layer driven by a separate Node.js backend process.
- Extensions run in Node with a React reconciler, and helper processes handle accessibility and pasteboard work.
- It manipulates windows through the `AXUIElement` APIs and searches files through Spotlight `MDQuery`.

Lodestar deliberately takes a much simpler route. The UI is native SwiftUI, there is no bundled runtime, and extensions talk a language-agnostic stdio protocol instead of rendering React trees.

## Roadmap

- Snippets / text expansion (needs a `CGEventTap`, which requires Input Monitoring)
- Quicklinks with `{query}` placeholders
- Image clipboard entries; pinned entries
- Richer extension UI: forms, grids, markdown rendering, preferences
- Per-command hotkeys and aliases
- Unit conversions and currency in the calculator

## License

MIT. See [LICENSE](LICENSE).
