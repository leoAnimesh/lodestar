// Example no-view extension written against the raw protocol (no SDK),
// to show how little is required: read one JSON line, write JSON lines.
const { randomUUID } = require("node:crypto");
const readline = require("node:readline");

const rl = readline.createInterface({ input: process.stdin });
rl.once("line", (line) => {
  const msg = JSON.parse(line);
  if (msg.type !== "run") return;
  const id = randomUUID();
  // A no-view command shows no list, so there is no item for the host to
  // attach a "copy" action to; copy directly with pbcopy instead.
  require("node:child_process").execFileSync("/usr/bin/pbcopy", { input: id });
  process.stdout.write(JSON.stringify({ type: "toast", message: `Copied ${id}` }) + "\n");
  rl.close();
});
