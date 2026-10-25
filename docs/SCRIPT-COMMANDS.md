# Script commands

Any executable script in `~/.config/lodestar/scripts/` becomes a launcher command. Metadata lives in
comments (`#`, `//` or `--`):

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

Remember `chmod +x` on the script, then run **Reload Scripts and Extensions**.

| Mode | What happens |
| --- | --- |
| `silent` | Runs the script and hides the launcher. |
| `compact` | Shows the last line of output in the footer. |
| `fullOutput` | Shows all output in a detail view. |

A non-zero exit always shows the output.

For compatibility with the community script-command format, the `@raycast.` metadata prefix is also
accepted. See `Examples/scripts/` and the **Create Script Command** command.

Scripts run with your user permissions and are not sandboxed. Only install scripts you trust.
