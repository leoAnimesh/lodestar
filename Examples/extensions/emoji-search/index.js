// Example list-mode extension. Copy this folder to
// ~/.config/lodestar/extensions/ along with sdk/js/lodestar.js.
const path = require("node:path");
const fs = require("node:fs");
// Use a local copy of the SDK if present, else the repo's copy.
const local = path.join(__dirname, "lodestar.js");
const lodestar = require(fs.existsSync(local) ? local : path.join(__dirname, "../../../sdk/js/lodestar.js"));

const EMOJI = [
  ["😀", "grinning face", "happy smile"], ["😂", "tears of joy", "laugh lol"],
  ["🥲", "smiling with tear", "bittersweet"], ["😍", "heart eyes", "love"],
  ["🤔", "thinking face", "hmm consider"], ["😴", "sleeping face", "tired zzz"],
  ["👍", "thumbs up", "yes ok approve"], ["👎", "thumbs down", "no disapprove"],
  ["🙏", "folded hands", "please thanks"], ["👏", "clapping hands", "applause bravo"],
  ["🔥", "fire", "hot lit"], ["✨", "sparkles", "magic new"], ["🎉", "party popper", "celebrate tada"],
  ["🚀", "rocket", "launch ship fast"], ["✅", "check mark", "done yes"], ["❌", "cross mark", "no wrong"],
  ["⚠️", "warning", "caution alert"], ["💡", "light bulb", "idea"], ["🐛", "bug", "insect defect"],
  ["❤️", "red heart", "love"], ["☕", "hot beverage", "coffee tea"], ["🍕", "pizza", "food"],
  ["🐱", "cat face", "kitty pet"], ["🐶", "dog face", "puppy pet"], ["🌍", "globe", "earth world"],
];

lodestar.command("search", {
  onQuery(text, ui) {
    const q = text.toLowerCase().trim();
    const hits = EMOJI.filter(([, name, kw]) => !q || name.includes(q) || kw.includes(q));
    ui.items(hits.map(([emoji, name]) => ({
      id: name,
      title: name,
      icon: emoji,
      accessory: emoji,
      actions: [lodestar.paste(emoji), lodestar.copy(emoji)],
    })));
  },
});

lodestar.start();
