#!/usr/bin/env python3
"""Generates Sources/LodestarCore/Resources/emoji.json for the
"Search Emoji & Symbols" command.

Inputs (all published by the Unicode Consortium under the Unicode License v3,
see THIRD_PARTY_NOTICES.md):

  * emoji-test.txt         https://www.unicode.org/Public/<ver>/emoji/emoji-test.txt
      the emoji set, CLDR short names, groups, order and emoji versions
  * annotations/en.xml     https://github.com/unicode-org/cldr  (common/annotations/en.xml)
  * annotationsDerived/en.xml (common/annotationsDerived/en.xml)
      English search keywords (and names for the symbols below)
  * UnicodeData.txt        https://www.unicode.org/Public/<ver>/ucd/UnicodeData.txt
      character names for symbols that CLDR doesn't annotate

The symbol sections (arrows, math, currency, ...) are curated by hand below.

Usage:
  scripts/generate-emoji-data.py                 # downloads the inputs to a temp dir
  scripts/generate-emoji-data.py --sources DIR   # uses DIR/{emoji-test.txt,annotations-en.xml,
                                                 #   annotationsDerived-en.xml,UnicodeData.txt}

The output is deterministic, so re-running with the same inputs produces an
identical file.
"""

import argparse
import json
import os
import re
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

UNICODE_VERSION = "17.0"
CLDR_RELEASE = "48"

SOURCES = {
    "emoji-test.txt": f"https://www.unicode.org/Public/{UNICODE_VERSION}.0/emoji/emoji-test.txt",
    "UnicodeData.txt": f"https://www.unicode.org/Public/{UNICODE_VERSION}.0/ucd/UnicodeData.txt",
    "annotations-en.xml": f"https://raw.githubusercontent.com/unicode-org/cldr/release-{CLDR_RELEASE}/common/annotations/en.xml",
    "annotationsDerived-en.xml": f"https://raw.githubusercontent.com/unicode-org/cldr/release-{CLDR_RELEASE}/common/annotationsDerived/en.xml",
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "Sources", "LodestarCore", "Resources", "emoji.json")

# Display categories. The emoji ones follow the familiar picker order;
# Unicode's two face/people groups are merged into one.
CATEGORIES = [
    ("people", "Smileys & People", "emoji"),
    ("nature", "Animals & Nature", "emoji"),
    ("food", "Food & Drink", "emoji"),
    ("activities", "Activities", "emoji"),
    ("travel", "Travel & Places", "emoji"),
    ("objects", "Objects", "emoji"),
    ("symbols", "Symbols", "emoji"),
    ("flags", "Flags", "emoji"),
    ("keyboard", "Keyboard", "symbol"),
    ("arrows", "Arrows", "symbol"),
    ("math", "Math", "symbol"),
    ("currency", "Currency", "symbol"),
    ("typography", "Punctuation & Typography", "symbol"),
    ("greek", "Greek Letters", "symbol"),
    ("shapes", "Stars & Shapes", "symbol"),
    ("box", "Box Drawing", "symbol"),
]
CATEGORY_INDEX = {cid: i for i, (cid, _, _) in enumerate(CATEGORIES)}

GROUP_TO_CATEGORY = {
    "Smileys & Emotion": "people",
    "People & Body": "people",
    "Animals & Nature": "nature",
    "Food & Drink": "food",
    "Activities": "activities",
    "Travel & Places": "travel",
    "Objects": "objects",
    "Symbols": "symbols",
    "Flags": "flags",
}

SKIN_TONES = [0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF]
FE0F = 0xFE0F
FE0E = 0xFE0E


def cps(s):
    return [int(x, 16) for x in s.split()]


def text(cp_list):
    return "".join(chr(c) for c in cp_list)


def seq_range(a, b, skip=()):
    return [c for c in range(a, b + 1) if c not in skip]


def chars(s):
    """Code points of a literal string of symbols (whitespace ignored)."""
    return [ord(ch) for ch in s if not ch.isspace()]


# --- Curated symbol sections -------------------------------------------------
# Keyboard symbols get friendly names (as printed in macOS menus); the rest
# use CLDR names when available, else Unicode character names.

KEYBOARD = [
    (0x2318, "command", ["cmd", "key", "modifier", "place of interest"]),
    (0x2325, "option", ["alt", "opt", "key", "modifier"]),
    (0x21E7, "shift", ["key", "modifier"]),
    (0x2303, "control", ["ctrl", "key", "modifier"]),
    (0x21EA, "caps lock", ["key", "capslock"]),
    (0x23CE, "return", ["enter", "key"]),
    (0x21A9, "return (arrow)", ["enter", "key"]),
    (0x2324, "enter", ["return", "key"]),
    (0x232B, "delete", ["backspace", "erase", "key"]),
    (0x2326, "forward delete", ["delete right", "erase", "key"]),
    (0x238B, "escape", ["esc", "key"]),
    (0x21E5, "tab", ["key", "indent"]),
    (0x21E4, "back tab", ["shift tab", "key", "outdent"]),
    (0x2423, "space", ["spacebar", "blank", "key"]),
    (0x21DE, "page up", ["pgup", "key"]),
    (0x21DF, "page down", ["pgdn", "key"]),
    (0x2196, "home", ["key", "north west arrow"]),
    (0x2198, "end", ["key", "south east arrow"]),
    (0x2191, "up arrow key", ["up", "key"]),
    (0x2193, "down arrow key", ["down", "key"]),
    (0x2190, "left arrow key", ["left", "key"]),
    (0x2192, "right arrow key", ["right", "key"]),
    (0x23CF, "eject", ["key", "media"]),
    (0x233D, "power", ["key", "on off"]),
    (0x2327, "clear", ["key", "x in a rectangle"]),
    (0x2384, "compose", ["key"]),
    (0x2380, "insert", ["key"]),
    (0x2388, "helm", ["key"]),
    (0x2756, "diamond (rotated)", ["key"]),
    (0x2328, "keyboard", ["key"]),
    (0x2399, "print screen", ["key", "print"]),
    (0x263C, "brightness", ["key", "sun", "display"]),
    (0x2600, "brightness up", ["key", "sun", "display"]),
    (0x1F310, "globe (fn)", ["fn", "function", "key", "language"]),
]

ARROWS = (seq_range(0x2190, 0x21FF, skip={0x21DE, 0x21DF})
          + seq_range(0x27F5, 0x27FF)
          + chars("➔➘➙➚➛➜➝➞➟➠➡➢➣➤➥➦➧➨➩➪➫➬➭➮➯➱➲➳➴➵➶➷➸➹➺➻➼➽➾")
          + chars("⤴⤵⤶⤷⤸⤹⤺⤻⤼⤽⤾⤿⥀⥁")
          + chars("⬅⬆⬇⬈⬉⬊⬋⬌⬍⬎⬏⬐⬑"))

MATH = chars(
    "+−±∓×÷=≠≈≃≅≡≢<>≤≥≪≫∝∞√∛∜∑∏∐∫∬∭∮∂∆∇′″‴∀∃∄∅∈∉∋∌∩∪⊂⊃⊄⊅⊆⊇⊊⊋"
    "∧∨¬⊕⊖⊗⊘⊙⊥∥∦∠∡∢∴∵∶∷∼∽≀∘∙⋅⋆⋯⋮⋰⋱⊢⊣⊤⊨⊩⌈⌉⌊⌋⟨⟩⟦⟧"
    "ℕℤℚℝℂℙℍℵℶ℘ℑℜ°‰‱µ¹²³⁴⁵⁶⁷⁸⁹⁰⁺⁻⁼⁽⁾ⁿⁱ₀₁₂₃₄₅₆₇₈₉₊₋₌"
    "½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞⅐⅑⅒↉"
)

CURRENCY = chars("$¢£¤¥€₹₽₩₪₫₴₦₱₺₸₿฿₡₲₵₼₾₭₮₨₳₠₣₤₥₧₯₰₶₷₻ƒ֏؋৳૱௹៛﷼")

TYPOGRAPHY = chars(
    "—–‐‑‒―…•‣⁃◦·¶§†‡©®™℠℗°′″«»‹›“”‘’„‚\"'¡¿‽⸘⁂※⁄¦‖№℅℆ℓ℮⸮⁊&@#~^`´¨ˆ˜¸¯"
    "‾_⁀⁐⁔⁗⁓⸺⸻〃⁒⁋☙❧❦✝✞✠"
)

GREEK = seq_range(0x0391, 0x03A9, skip={0x03A2}) + seq_range(0x03B1, 0x03C9) + chars("ϑϕϖϰϱϵϜϝ")

SHAPES = chars(
    "★☆✦✧✩✪✫✬✭✮✯✰⭑⭒✱✲✳✴✵✶✷✸✹✺✻✼✽✾✿❀❁❂❃❄❅❆❇❈❉❊❋"
    "●○◉◎◌◍◐◑◒◓◔◕◖◗◯⬤⚪⚫■□▢▣▤▥▦▧▨▩▪▫▬▭▮▯▰▱⬛⬜"
    "▲△▴▵▶▷▸▹►▻▼▽▾▿◀◁◂◃◄◅◆◇◈◊⬥⬦⬧⬨◢◣◤◥◸◹◺◿"
    "♠♣♥♦♤♧♡♢✓✔✕✖✗✘☐☑☒♩♪♫♬♭♮♯☀☁☂☃☾☽☮☯⚑⚐✂✎✏✐✉☎☏⌂⌘"
)

BOX = seq_range(0x2500, 0x257F) + seq_range(0x2580, 0x259F)

SYMBOL_SECTIONS = [
    ("arrows", ARROWS),
    ("math", MATH),
    ("currency", CURRENCY),
    ("typography", TYPOGRAPHY),
    ("greek", GREEK),
    ("shapes", SHAPES),
    ("box", BOX),
]


# --- Parsing -----------------------------------------------------------------

LINE = re.compile(r"^([0-9A-F ]+?)\s*;\s*([a-z-]+)\s*#\s*\S+\s+E(\d+)\.(\d+)\s+(.+)$")


def parse_emoji_test(path):
    """Returns (entries, status_by_sequence) where entries are
    (codepoints, group, version_tenths, name) for fully-qualified emoji."""
    entries, status = [], {}
    group = None
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if line.startswith("# group:"):
                group = line.split(":", 1)[1].strip()
                continue
            if not line or line.startswith("#"):
                continue
            m = LINE.match(line)
            if not m:
                raise SystemExit(f"unparsed line: {line!r}")
            seq = tuple(cps(m.group(1)))
            status[seq] = m.group(2)
            version = int(m.group(3)) * 10 + int(m.group(4))
            if m.group(2) == "fully-qualified":
                entries.append((seq, group, version, m.group(5).strip()))
    return entries, status


def parse_annotations(path):
    """cp (FE0F removed) -> (keywords, tts name)."""
    out = {}
    root = ET.parse(path).getroot()
    for node in root.iter("annotation"):
        cp = node.get("cp")
        value = (node.text or "").strip()
        keywords, name = out.get(cp, ([], None))
        if node.get("type") == "tts":
            name = value
        else:
            keywords = [k.strip() for k in value.split("|") if k.strip()]
        out[cp] = (keywords, name)
    return out


def parse_unicode_data(path):
    names = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            fields = line.split(";")
            if fields[1].startswith("<"):
                continue
            names[int(fields[0], 16)] = fields[1].lower()
    return names


# --- Building ----------------------------------------------------------------

def name_words(name):
    return set(re.findall(r"[\w+&#*-]+", name.lower()))


def clean_keywords(keywords, name, extra=()):
    """Lowercase, de-duplicate, drop keywords that are just a word of the name."""
    words = name_words(name)
    seen, out = set(), []
    for k in list(keywords) + list(extra):
        k = k.strip().lower()
        if not k or k in seen or k == name.lower() or k in words:
            continue
        seen.add(k)
        out.append(k)
    return out


ZWJ = 0x200D


def toned(seq, tone, modifier_bases):
    """Inserts `tone` after every modifier base (dropping a following FE0F),
    except a base joined on both sides by ZWJ, like the handshake in
    "people holding hands". EmojiSkinTone.apply in LodestarCore mirrors this."""
    out, skip_fe0f = [], False
    for i, c in enumerate(seq):
        if skip_fe0f and c == FE0F:
            skip_fe0f = False
            continue
        skip_fe0f = False
        out.append(c)
        interior = 0 < i < len(seq) - 1 and seq[i - 1] == ZWJ and seq[i + 1] == ZWJ
        if c in modifier_bases and not interior:
            out.append(tone)
            skip_fe0f = True
    return tuple(out)


def build(src):
    entries, status = parse_emoji_test(os.path.join(src, "emoji-test.txt"))
    ann = parse_annotations(os.path.join(src, "annotations-en.xml"))
    derived = parse_annotations(os.path.join(src, "annotationsDerived-en.xml"))
    unames = parse_unicode_data(os.path.join(src, "UnicodeData.txt"))
    version_of = {seq: v for seq, _, v, _ in entries}

    modifier_bases = set()
    for seq in status:
        for a, b in zip(seq, seq[1:]):
            if b in SKIN_TONES:
                modifier_bases.add(a)

    items = []
    emoji_scalars = set()  # single code points that have an emoji form
    for seq in status:
        core = [c for c in seq if c != FE0F]
        if len(core) == 1:
            emoji_scalars.add(core[0])

    toned_count = 0
    for seq, group, version, name in entries:
        if any(c in SKIN_TONES for c in seq):
            continue  # skin-tone variants are generated at runtime
        category = GROUP_TO_CATEGORY.get(group)
        if category is None:
            continue  # Component
        key = text([c for c in seq if c != FE0F])
        keywords, _ = ann.get(key) or derived.get(key) or ([], None)
        extra = []
        if len(seq) == 2 and all(0x1F1E6 <= c <= 0x1F1FF for c in seq):
            extra.append("".join(chr(c - 0x1F1E6 + ord("a")) for c in seq))  # ISO code, e.g. "jp"
        item = {
            "c": text(seq),
            "n": name,
            "k": clean_keywords(keywords, name, extra),
            "g": CATEGORY_INDEX[category],
            "v": version,
        }
        variants = [toned(seq, t, modifier_bases) for t in SKIN_TONES]
        if any(c in modifier_bases for c in seq) and all(status.get(v) == "fully-qualified" for v in variants):
            item["t"] = max(version_of[v] for v in variants)
            toned_count += 1
        items.append(item)

    items.sort(key=lambda it: it["g"])  # stable: keeps Unicode order inside a category

    seen_symbols = set()

    def symbol_item(cp, category, name=None, extra=()):
        ch = chr(cp)
        cldr_keywords, cldr_name = ann.get(ch, ([], None))
        uname = unames.get(cp)
        if uname is None:
            raise SystemExit(f"U+{cp:04X} has no Unicode name")
        display = name or cldr_name or uname
        kw = list(extra) + list(cldr_keywords)
        if uname != display:
            kw.append(uname)
        glyph = ch + (chr(FE0E) if cp in emoji_scalars else "")  # force text presentation
        return {"c": glyph, "n": display, "k": clean_keywords(kw, display), "g": CATEGORY_INDEX[category], "v": 0}

    for cp, name, extra in KEYBOARD:
        items.append(symbol_item(cp, "keyboard", name, extra))
    for category, cps_list in SYMBOL_SECTIONS:
        for cp in cps_list:
            if (category, cp) in seen_symbols:
                continue
            seen_symbols.add((category, cp))
            items.append(symbol_item(cp, category))

    data = {
        "about": ("Generated by scripts/generate-emoji-data.py from Unicode emoji-test.txt and UnicodeData.txt "
                  f"{UNICODE_VERSION} and CLDR {CLDR_RELEASE} English annotations. "
                  "Copyright (c) 1991-2025 Unicode, Inc. Unicode License v3; see THIRD_PARTY_NOTICES.md."),
        "unicodeVersion": UNICODE_VERSION,
        "cldrVersion": CLDR_RELEASE,
        "categories": [{"id": cid, "name": name, "kind": kind} for cid, name, kind in CATEGORIES],
        "modifierBases": sorted(modifier_bases),
        "items": items,
    }
    return data, toned_count


def fetch(dest):
    for filename, url in SOURCES.items():
        path = os.path.join(dest, filename)
        if not os.path.exists(path):
            print(f"downloading {url}", file=sys.stderr)
            urllib.request.urlretrieve(url, path)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sources", help="directory holding the input files (downloaded if missing)")
    parser.add_argument("--output", default=OUTPUT)
    args = parser.parse_args()

    src = args.sources or tempfile.mkdtemp(prefix="lodestar-unicode-")
    os.makedirs(src, exist_ok=True)
    fetch(src)
    data, toned_count = build(src)

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        # One item per line: compact, but still diff-friendly.
        head = {k: v for k, v in data.items() if k != "items"}
        body = json.dumps(head, ensure_ascii=False, separators=(",", ":"))[:-1]
        f.write(body + ',"items":[\n')
        f.write(",\n".join(json.dumps(it, ensure_ascii=False, separators=(",", ":")) for it in data["items"]))
        f.write("\n]}\n")

    emoji = sum(1 for it in data["items"] if CATEGORIES[it["g"]][2] == "emoji")
    print(f"wrote {args.output}: {emoji} emoji ({toned_count} with skin tones), "
          f"{len(data['items']) - emoji} symbols, {os.path.getsize(args.output) // 1024} KB", file=sys.stderr)


if __name__ == "__main__":
    main()
