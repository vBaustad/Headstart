"""Build our levelling routes after the starting zones from RestedXP's guides, as they are plus our changes.

    python tools/fork_rxp.py        (reads S:/forever-data/external/rxp; rerun after updating that clone)

Every guide in SOURCES becomes Guides/Levelling/<slug>.lua shipping one route (YR:ShipGuide) in our group:
  * cleaned of what never shows on WoW: Forever (tools/clean_guide.py);
  * quest pick-ups a duo or trio should split marked (tools/share_split.py);
  * its #next pointing at our copy where we ship one, else back into RestedXP's own group;
  * the per-route changes in EDITS (each must match RestedXP's text exactly, or the build fails).
Also writes Guides/Levelling/files.txt, the list the .toc needs (check_toc below keeps them in step).
"""
import json
import os
import re
import sys

from clean_guide import clean, no_sick_deathskips
from share_split import mark

RXP = "S:/forever-data/external/rxp/Guides/"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Guides", "Levelling")
GROUP = "Headstart Launch (A)"

# (file under RXP, RestedXP's group for #next entries without one, [guide names])
SOURCES = [
    ("Forever/Alliance-1-13_Human.lua", "RestedXP Forever Guide (A)", ["6-11 Elwynn Forest", "11-13 Loch Modan"]),
    ("Forever/Alliance-1-14_DwarfGnome.lua", "RestedXP Forever Guide (A)",
     ["11-12 Elwynn (Dwarf/Gnome)", "12-14 Loch Modan (Dwarf/Gnome)", "11-13 Loch Modan (Hunter)"]),
    ("Forever/Alliance-1-10_NightElf.lua", "RestedXP Forever Guide (A)", ["6-11 Teldrassil"]),
    ("Forever/Alliance-11-20.lua", "RestedXP Forever Guide (A)",
     ["13-15 Westfall", "14-16 Darkshore", "16-19 Darkshore", "19-20 Redridge", "19-21 Darkshore/Ashenvale",
      "20-21 Darkshore/Ashenvale"]),
]

SOURCES += [
    # 21-30: RestedXP's free route (their paid 20-30 isn't public); older, so cleaned of TBC/Wrath lines
    ("RestedXP Alliance 11-23.lua", "RestedXP Alliance 20-32", ["21-23 Ashenvale"]),
    ("RestedXP Alliance 23-30.lua", "RestedXP Alliance 20-32",
     ["23-24 Wetlands", "24-27 Redridge/Duskwood", "27-30 Wetlands/Hillsbrad", "28-30 Duskwood"]),
]

# At 30: the paid RestedXP 30-40 guide where it is installed, else the free one
AT_30 = "RestedXP Survival Guide (A)\\30-32 Duskwood;RestedXP Alliance 20-32\\{free}"

# Our changes per route: name -> [(old, new, why)]
EDITS = {
    "20-21 Darkshore/Ashenvale": [
        ("#next RestedXP Alliance 20-30\\21-23 Stonetalon/Ashenvale;RestedXP Alliance 20-30\\21-22 Ashenvale SoD\n",
         "#next 21-23 Ashenvale\n", "on to our 21-30"),
    ],
    "19-21 Darkshore/Ashenvale": [
        ("#next RestedXP Alliance 20-30\\21-23 Ashenvale/Stonetalon\n", "#next 21-23 Ashenvale\n", "on to our 21-30"),
    ],
    # the free route sent Warlocks another way (its Darkshore/Ashenvale); ours comes from our 20-21
    "21-23 Ashenvale": [
        ("<< Alliance !Warlock/Alliance wotlk\n", "<< Alliance\n", "every class goes this way from our 20-21"),
    ],
    # The grind to 13+9600 before the South Gate hand-ins filled the gap before Westfall; Stonesplinter
    # Valley and the east now come after it (blocks.py LM_*). The step stays (others end with its label).
    "12-14 Loch Modan (Dwarf/Gnome)": [
        ("    .xp 13+9600 >> Grind to 9600+/11400xp\n"
         "    >>|cRXP_WARN_If you're planning on running the Hall of Thanes dungeon in Ironforge later, skip this step|r\n",
         "    .xp 12 >> No grinding here: Stonesplinter Valley and the east of the lake come next\n",
         "no grind: the valley and the east follow"),
    ],
    # Warlocks kill Hogger here (Fear), but RestedXP's hand-in step is marked "skip": hand it in to
    # Marshal Dughan with Deliver Thomas' Report, the route's next visit to him
    "11-12 Elwynn (Dwarf/Gnome)": [
        ("    .turnin 39 >> Turn in Deliver Thomas' Report\n    .target Marshal Dughan\n",
         "    .turnin 39 >> Turn in Deliver Thomas' Report\n    .target Marshal Dughan\n"
         "step << Warlock\n    .goto 1429/0,74.02,-9465.52\n"
         "    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Marshal Dughan|r\n"
         "    .turnin 176,3 >> Turn in Wanted: \"Hogger\"\n    .target Marshal Dughan\n    .isQuestComplete 176\n",
         "Hogger's hand-in for Warlocks"),
    ],
    "27-30 Wetlands/Hillsbrad": [
        ("#next RestedXP Alliance 20-32\\30-32 Duskwood/STV\n", "#next " + AT_30.format(free="30-32 Duskwood/STV") + "\n", "hand over at 30"),
    ],
    "28-30 Duskwood": [
        ("#next RestedXP Alliance 20-32\\30-32 Hillsbrad\n", "#next " + AT_30.format(free="30-32 Hillsbrad") + "\n", "hand over at 30"),
    ],
}


def slug(name):
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")


def block(file, name):
    src = open(RXP + file, encoding="utf-8").read()
    for b in re.findall(r"RXPGuides\.RegisterGuide\(\[\[(.*?)\]\]\)", src, re.S):
        if f"\n#name {name}\n" in b:
            return b
    raise SystemExit(f"{name} not found in {file}")


def next_line(line, home, ours):
    """#next entries: ours stay plain (same group), RestedXP's get their group in front."""
    body, sep, cond = line.partition(" << ")
    out = []
    for entry in body.split(";"):
        entry = entry.strip()
        if "\\" in entry:
            out.append(entry)
        elif entry in ours:
            out.append(entry)
        else:
            out.append(home + "\\" + entry)
    return ";".join(out) + (sep + cond if sep else "")


def build(file, home, name, ours):
    text = block(file, name)
    text = re.sub(r"\n#group [^\n]*", "\n#group " + GROUP, text, count=1)
    text = re.sub(r"\n#subgroup [^\n]*", "\n#subgroup Levelling", text, count=1)
    text = re.sub(r"\n#defaultfor [^\n]*", "", text)
    # the game(s) a guide is for: the older free guides say #tbc / #wotlk, which Forever never is
    text = re.sub(r"\n#(tbc|wotlk|classic|era|som|cata|mop|retail)[ \t]*(?=\n)", "", text)
    if "\n#forever" not in text:
        text = "\n#forever" + text
    text = re.sub(r"\n#next ([^\n]*)", lambda m: "\n#next " + next_line(m.group(1), home, ours), text)
    for old, new, why in EDITS.get(name, []):
        n = text.count(old)
        assert n == 1, f"{name}: expected one match upstream, found {n}: {old[:70]!r} ({why})"
        text = text.replace(old, new)
    text = no_sick_deathskips(clean(text))
    text = map_ids(text)       # after cleaning: TBC/Wrath lines name maps Forever doesn't have
    text = forever_maps(text)  # Stormwind and Redridge are drawn differently on Forever
    text = insert_blocks(name, text)
    text, dropped = drop_missing(text)
    text, greyed = drop_grey(name, text)
    for d in dropped + [f"grey: {g}" for g in greyed]:
        print(f"    {name}: {d}")
    text, shared = mark(text)
    return text, shared


def insert_blocks(name, text):
    """Our own steps (tools/route_builder.py specs, in blocks.py) put into a route: each block names a
    step of the route by a pattern and goes before or after the first step that matches it."""
    from blocks import BLOCKS
    # a route named twice in BLOCKS keeps only its last list (a dict literal): fail instead
    import ast
    src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "blocks.py"), encoding="utf-8").read()
    for node in ast.walk(ast.parse(src)):
        if isinstance(node, ast.Dict):
            keys = [k.value for k in node.keys if isinstance(k, ast.Constant)]
            twice = sorted({k for k in keys if keys.count(k) > 1})
            assert not twice, f"blocks.py names a route twice: {twice}"
    from route_builder import build
    for anchor, where, spec in BLOCKS.get(name, []):
        parts = re.split(r"\n(?=step\b)", text)
        idx = next((i for i, p in enumerate(parts) if i > 0 and re.search(anchor, p)), None)
        assert idx, f"{name}: no step matches {anchor!r}"
        steps = build("", spec).strip("\n")
        at = idx + 1 if where == "after" else idx
        parts.insert(at, steps)
        text = "\n".join(parts)
    return text


# Map bounds (world Y min/max, world X min/max) of the maps Forever draws differently from Classic,
# from UiMapAssignment in both clients' data (research: db/forever.duckdb, era vs 1.60.1 build 70009).
# A zone percentage written for the Classic map lands 100-200 yards off on Forever's. World
# coordinates (".goto 1453/0,y,x") don't depend on the map and are left alone.
CHANGED_MAPS = {
    1453: {"classic": (36.70063, 1380.9714, -9175.205, -8278.851), "forever": (-14.584, 1722.92, -9154.17, -7995.83)},
    1433: {"classic": (-3741.6665, -1570.8333, -10022.916, -8575), "forever": (-3852.084, -1681.25, -10022.916, -8575)},
}


def to_forever(mapid, px, py):
    """A Classic-map percentage position -> the same spot as a Forever-map percentage."""
    cy0, cy1, cx0, cx1 = CHANGED_MAPS[mapid]["classic"]
    fy0, fy1, fx0, fx1 = CHANGED_MAPS[mapid]["forever"]
    wy = cy1 - px / 100 * (cy1 - cy0)
    wx = cx1 - py / 100 * (cx1 - cx0)
    return (fy1 - wy) / (fy1 - fy0) * 100, (fx1 - wx) / (fx1 - fx0) * 100


def forever_maps(text):
    def repl(m):
        mapid, px, py = int(m.group(2)), float(m.group(3)), float(m.group(4))
        fx, fy = to_forever(mapid, px, py)
        return f".{m.group(1)} {mapid},{fx:.3f},{fy:.3f}"
    return re.sub(r"\.(goto|waypoint) (1453|1433),(-?[\d.]+),(-?[\d.]+)", repl, text)


_maps = None


def map_ids(text):
    """".goto Duskwood,73.5,46.8" -> ".goto 1431,73.5,46.8": the older guides name zones, and RestedXP
    on Forever doesn't load its Classic name table (DB/classic/db.lua returns unless the game is
    CLASSIC). The names come from that table, plus TBC's "StormwindClassic"."""
    global _maps
    if _maps is None:
        src = open(RXP + "../DB/classic/db.lua", encoding="utf-8").read()
        _maps = {n: int(i) for n, i in re.findall(r'\["([^"]+)"\]\s*=\s*(\d{4})\b', src)}
        _maps["StormwindClassic"] = 1453
    def repl(m):
        name = m.group(2).strip()
        if name not in _maps:
            raise SystemExit(f"unknown zone name in .{m.group(1)}: {name!r}")
        return f".{m.group(1)} {_maps[name]},"
    return re.sub(r"\.(goto|waypoint) ([A-Za-z][A-Za-z' ]*),", repl, text)


_known = None


def known_quest(q):
    """Whether Forever has this quest: in Questie's Forever data (every Era quest), our server scan,
    or Wowhead's Forever zone lists. The older free guides still carry TBC quests, which it hasn't."""
    global _known
    if _known is None:
        d = "S:/forever-data/research/leveling/data/"
        _known = set(json.load(open(d + "Quest.json", encoding="utf-8")))
        _known |= set(json.load(open(d + "scan_70009.json", encoding="utf-8"))["quests"])
        _known |= {str(x[0]) for x in json.load(open(d + "wh_zone_quests.json", encoding="utf-8"))["quests"]}
    return str(q) in _known


# Quests that would be grey when handed in (tools/check_levels.py; the rule: never hand in a grey quest,
# green at worst), mostly because Dwarves and Gnomes reach these routes later now (our Loch Modan takes
# them from 11 to about 16): route -> {quest: who still does it (a RestedXP filter), or None for nobody}.
# A step left with nothing to do goes; a step whose quests are all kept for some goes to them only.
GREY = {
    "13-15 Westfall": {36: "!Dwarf !Gnome", 38: "!Dwarf !Gnome",          # Westfall Stew, both parts
                       95065: "!Warlock"},                                 # Fishin' Time
    "14-16 Darkshore": {958: "NightElf",           # Tools of the Highborne (Night Elves' Expanding Horizons follows)
                        983: "NightElf", 1001: "NightElf", 1002: "NightElf", 1003: "NightElf"},   # Buzzboxes
    "16-19 Darkshore": {1002: "NightElf", 1003: "NightElf"},
    "19-21 Darkshore/Ashenvale": {1003: "NightElf"},
    "20-21 Darkshore/Ashenvale": {1003: "NightElf"},
    "19-20 Redridge": {120: None, 121: None,                               # Messenger to Stormwind
                       129: None, 130: None, 131: None,                    # A Free Lunch and on
                       3741: None},                                        # Hilary's Necklace
    "24-27 Redridge/Duskwood": {244: None, 246: None},                     # Encroaching Gnolls, late copy
}


def drop_grey(name, text):
    """GREY's quests: their lines go, or carry its filter; a step with nothing else goes or is filtered."""
    grey = GREY.get(name)
    if not grey:
        return text, []
    parts = re.split(r"\n(?=step\b)", text)
    out, notes, hidden = [parts[0]], [], {}       # hidden: label -> the filter its step now has

    def only(step, keep):
        lines = step.split("\n")
        lines[0] = lines[0] + " " + keep if "<<" in lines[0] else "step << " + keep
        return "\n".join(lines)

    for step in parts[1:]:
        lines = step.split("\n")
        acts = [(i, re.match(r"\s*\.(accept|turnin|complete)\s+(\d+)", ln)) for i, ln in enumerate(lines)]
        acts = [(i, m) for i, m in acts if m]
        mine = [(i, int(m.group(2))) for i, m in acts if int(m.group(2)) in grey]
        if not mine:
            out.append(step)
            continue
        if len(mine) == len(acts):                    # the step is only about these quests
            filters = {grey[q] for _, q in mine}
            if filters == {None}:
                # a label others only end at (#completewith: they still end their own way) can go;
                # one a step waits for (#requires) can't
                for label in re.findall(r"#label\s+(\S+)", step):
                    assert not re.search(r"#requires\s+" + re.escape(label) + r"\b", text), \
                        f"{name}: a step waits for {label}, which would go"
                notes.append(f"dropped a step: {', '.join(str(q) for _, q in mine)}")
                continue
            keep = " ".join(sorted(f for f in filters if f))
            for label in re.findall(r"#label\s+(\S+)", step):
                hidden[label] = keep
            notes.append(f"kept for {keep} only: {', '.join(str(q) for _, q in mine)}")
            out.append(only(step, keep))
            continue
        for i, q in reversed(mine):                   # a shared step: just these lines
            if grey[q] is None:
                del lines[i]
            else:
                lines[i] = lines[i] + (" " + grey[q] if "<<" in lines[i] else " << " + grey[q])
        notes.append(f"lines only: {', '.join(str(q) for _, q in mine)}")
        out.append("\n".join(lines))
    # a step that only waits for a label now kept for some (#requires, nothing to do of its own) goes
    # to the same ones; a step that does something and needs it would be stuck: fail instead
    for k, step in enumerate(out[1:], 1):
        for label in re.findall(r"#requires\s+(\S+)", step):
            if label in hidden:
                acts = re.findall(r"^\s*\.(accept|turnin|complete)\s+(\d+)", step, re.M)
                assert all(int(q) in grey for _, q in acts), f"{name}: a step needs {label}, now {hidden[label]} only"
                if not step.split("\n")[0].endswith(hidden[label]):
                    out[k] = only(step, hidden[label])
                    notes.append(f"waits for {label}: kept for {hidden[label]} only")
    return "\n".join(out), notes


def drop_missing(text):
    """Lines for quests Forever doesn't have go; a step left with nothing to do goes too."""
    parts = re.split(r"\n(?=step\b)", text)
    out, dropped = [parts[0]], []
    for step in parts[1:]:
        lines = step.split("\n")
        keep = []
        for ln in lines:
            m = re.match(r"\s*\.(accept|turnin|complete)\s+(\d+)", ln)
            if m and not known_quest(m.group(2)):
                dropped.append(f"dropped {m.group(1)} {m.group(2)} (not on Forever)")
                continue
            keep.append(ln)
        acts = [l for l in keep[1:] if l.strip().startswith(".") and not l.strip().startswith((".goto", ".target"))]
        had = [l for l in lines[1:] if l.strip().startswith(".") and not l.strip().startswith((".goto", ".target"))]
        if had and not acts:
            dropped.append("dropped a step with only such quests: " + lines[0])
            continue
        out.append("\n".join(keep))
    return "\n".join(out), dropped


def main():
    os.makedirs(OUT, exist_ok=True)
    ours = {n for _, _, names in SOURCES for n in names}
    files = []
    for file, home, names in SOURCES:
        for name in names:
            text, shared = build(file, home, name, ours)
            key = slug(name)
            path = os.path.join(OUT, key + ".lua")
            head = (f"-- Headstart: {name}. GENERATED by tools/fork_rxp.py from RestedXP's guide ({file},\n"
                    "-- CC BY-NC-SA 4.0); only the changes in that script are ours. Do not edit by hand.\n"
                    "local _, YR = ...\n\n"
                    f'YR:ShipGuide("{key}", [[')
            open(path, "w", encoding="utf-8", newline="\n").write(head + text + "]])\n")
            files.append("Guides\\Levelling\\" + key + ".lua")
            print(f"{name:32s} {text.count(chr(10) + 'step'):4d} steps" + (f"   {'; '.join(shared)}" if shared else ""))
    open(os.path.join(OUT, "files.txt"), "w", encoding="utf-8", newline="\n").write("\n".join(files) + "\n")
    check_toc(files)


def check_toc(files):
    """The .toc must load every generated route, after the starting zones."""
    toc = open(os.path.join(ROOT, "Headstart.toc"), encoding="utf-8").read()
    missing = [f for f in files if f not in toc]
    if missing:
        print("add to Headstart.toc:\n" + "\n".join(missing))
        sys.exit(1)


if __name__ == "__main__":
    main()
