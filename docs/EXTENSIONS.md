# Extensions

An extension adds commands written in any language. Lodestar starts your program and talks to it with
**one JSON object per line** over stdin/stdout, so there's no SDK to install and no runtime bundled.

## Manifest

A folder in `~/.config/lodestar/extensions/<name>/` with a `manifest.json`:

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

`run` is the command line to start. Interpreters such as `node` and `python3` are found through `PATH`
(Homebrew paths included); `./relative` paths are resolved against the extension folder. stderr goes
to the system log.

## Messages

**Lodestar → extension**

```json
{"type":"run","command":"search","query":"","protocol":1}
{"type":"query","text":"rock"}
{"type":"callback","id":"refresh"}
```

**Extension → Lodestar**

```json
{"type":"items","items":[{"id":"1","title":"rocket","subtitle":"…","icon":"🚀","accessory":"…",
  "actions":[{"type":"paste","text":"🚀"},{"type":"copy","text":"🚀"},
             {"type":"open","url":"https://…"},{"type":"callback","id":"refresh"}]}]}
{"type":"detail","markdown":"long text"}
{"type":"toast","message":"Done"}
{"type":"close"}
{"type":"error","message":"…"}
```

Actions are **declarative**: Lodestar does the privileged work (pasting, opening) for the extension,
so extensions never need macOS permissions. The first action runs on Return; the rest are under ⌘K.
`callback` actions come back to your process so it can update the list.

- `list` commands stay running while the user is in them and get `query` messages as they type. The
  process receives SIGTERM when the user leaves.
- `no-view` commands run detached and can send a `toast`.

## Node helper

`sdk/js/lodestar.js` (no dependencies) handles the framing:

```js
const lodestar = require("./lodestar");
lodestar.command("search", {
  onQuery(text, ui) {
    ui.items([{ title: `You typed ${text}`, actions: [lodestar.copy(text)] }]);
  },
});
lodestar.start();
```

## Try the examples

```bash
mkdir -p ~/.config/lodestar/extensions ~/.config/lodestar/scripts
cp -R Examples/extensions/* ~/.config/lodestar/extensions/
cp sdk/js/lodestar.js ~/.config/lodestar/extensions/emoji-search/
cp Examples/scripts/*.sh ~/.config/lodestar/scripts/
```

Then run **Reload Scripts and Extensions**.

**Security:** extensions run with your user permissions and are not sandboxed. Only install ones you trust.
