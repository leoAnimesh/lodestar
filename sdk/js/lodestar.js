// Lodestar extension SDK for Node.js (zero dependencies, CommonJS).
//
// The host spawns your extension and talks newline-delimited JSON over
// stdin/stdout. This helper hides the framing. Usage:
//
//   const lodestar = require("./lodestar");
//   lodestar.command("search", {
//     async onQuery(text, ui) { ui.items([{ title: "Hi", actions: [lodestar.copy("Hi")] }]); },
//     async onCallback(id, ui) { ... },
//   });
//   lodestar.start();
//
// IMPORTANT: stdout is the protocol channel. Use console.error() for logs.
"use strict";

const readline = require("node:readline");

const commands = new Map();

function send(message) {
  process.stdout.write(JSON.stringify(message) + "\n");
}

const ui = {
  /** Replace the visible list. */
  items(items, placeholder) { send({ type: "items", items, placeholder }); },
  /** Show a full-text detail view. */
  detail(markdown) { send({ type: "detail", markdown }); },
  /** Flash a short message in the launcher footer. */
  toast(message) { send({ type: "toast", message }); },
  /** Hide the launcher. */
  close() { send({ type: "close" }); },
  /** Show an error in a detail view. */
  error(message) { send({ type: "error", message: String(message) }); },
};

// Declarative actions; the first one runs on Return, others via Cmd+K.
const open = (url) => ({ type: "open", url });
const copy = (text) => ({ type: "copy", text });
const paste = (text) => ({ type: "paste", text });
const callback = (id) => ({ type: "callback", id });

/**
 * Register a command declared in manifest.json.
 * handlers: { onRun?(query, ui), onQuery?(text, ui), onCallback?(id, ui) }
 * For "no-view" commands implement onRun and call process.exit() when done
 * (or just let the event loop drain).
 */
function command(name, handlers) {
  commands.set(name, handlers);
}

function start() {
  let active = null;
  const rl = readline.createInterface({ input: process.stdin });
  const guard = (p) => Promise.resolve(p).catch((err) => ui.error(err && err.stack ? err.stack : err));

  rl.on("line", (line) => {
    if (!line.trim()) return;
    let msg;
    try { msg = JSON.parse(line); } catch { return; }
    switch (msg.type) {
      case "run":
        active = commands.get(msg.command);
        if (!active) { ui.error(`Unknown command: ${msg.command}`); return; }
        if (active.onRun) guard(active.onRun(msg.query || "", ui));
        else if (active.onQuery) guard(active.onQuery(msg.query || "", ui));
        break;
      case "query":
        if (active && active.onQuery) guard(active.onQuery(msg.text || "", ui));
        break;
      case "callback":
        if (active && active.onCallback) guard(active.onCallback(msg.id, ui));
        break;
    }
  });
  // Host closed stdin: the user left the command.
  rl.on("close", () => process.exit(0));
}

module.exports = { command, start, ui, open, copy, paste, callback };
