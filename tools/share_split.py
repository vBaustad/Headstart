"""Mark the quest pick-ups a duo or trio should split: "#share N" on a step (Guides.lua turns the marks
into Duo A/B and Trio A/B/C versions of the route, pick-ups taken in turns).

    from share_split import mark
    text, report = mark(text)

A step qualifies when all it does is take quests that can be shared (the party gets them at any distance
on Forever, Headstart accepts them), and its quest giver is off the path the others walk anyway: the
detour, from the step before to the giver to the step after, is at least MIN_DETOUR yards. Where the
others pass the giver anyway nothing is saved, so the step stays everyone's.

Positions are the quest givers' and turn-in NPCs' spawns from Questie's Forever data; "Sharable" is from
Wowhead's Forever quest pages (research/leveling/data/sharable.json).
"""
import json
import math
import re

DATA = "S:/forever-data/research/leveling/data/"
MIN_DETOUR = 60

# Questie zone id -> (width, height) in yards, for the zones the Alliance routes use
ZONE_YARDS = {
    1: (4925, 3283.33), 12: (3470.83, 2314.58), 141: (5091.67, 3393.75), 38: (2758.33, 1839.58),
    40: (3500, 2333.33), 148: (6550, 4366.67), 44: (2170.83, 1447.92), 10: (2700, 1800),
    11: (4135.42, 2756.25), 331: (5766.67, 3843.75), 406: (4883.33, 3256.25), 267: (3200, 2133.33),
    1537: (790.63, 527.6), 1519: (1737.5, 1158.33), 1657: (1058.33, 705.73), 45: (3600, 2400),
}

_quests = _npcs = _sharable = None


def _load():
    global _quests, _npcs, _sharable
    if _quests is None:
        _quests = json.load(open(DATA + "Quest.json", encoding="utf-8"))
        _npcs = json.load(open(DATA + "Npc.json", encoding="utf-8"))
        _sharable = json.load(open(DATA + "sharable.json", encoding="utf-8"))


def _npc_pos(npc):
    n = _npcs.get(str(npc))
    spawns = n and n.get("7")
    if not spawns:
        return None
    for zone, pts in spawns.items():
        p = next(iter(pts.values()))
        return int(zone), p["1"], p["2"]
    return None


def _quest_pos(quest, end):
    q = _quests.get(str(quest))
    who = q and q.get("3" if end else "2")
    npcs = who and who.get("1")
    if not npcs:
        return None
    return _npc_pos(next(iter(npcs.values())))


def _yards(a, b):
    if not a or not b or a[0] != b[0] or a[0] not in ZONE_YARDS:
        return None
    w, h = ZONE_YARDS[a[0]]
    return math.hypot((a[1] - b[1]) / 100 * w, (a[2] - b[2]) / 100 * h)


def _step_pos(step):
    for kind, q in re.findall(r"\n\s*\.(accept|turnin)\s+(\d+)", step):
        p = _quest_pos(q, kind == "turnin")
        if p:
            return p
    return None


def _candidate(step):
    if re.search(r"\n\s*#(share|role)\b", step):
        return False
    actions = [l.strip() for l in step.split("\n")[1:] if l.strip().startswith(".")]
    actions = [a for a in actions if not a.startswith((".goto", ".target"))]
    if not actions or not all(a.startswith(".accept") for a in actions):
        return False
    return all(_sharable.get(re.match(r"\.accept\s+(\d+)", a).group(1), ["?"])[0] == "yes" for a in actions)


def mark(text):
    """The route with #share marks added, and a report line per marked step."""
    _load()
    parts = re.split(r"\n(?=step\b)", text)
    head, steps = parts[0], parts[1:]
    pos = [_step_pos("\n" + s) for s in steps]
    cand = [_candidate("\n" + s) for s in steps]
    report, n = [], 0
    for i, s in enumerate(steps):
        if not cand[i] or not pos[i]:
            continue
        prev = next((pos[j] for j in range(i - 1, -1, -1) if pos[j] and not cand[j]), None)
        nxt = next((pos[j] for j in range(i + 1, len(steps)) if pos[j] and not cand[j]), None)
        a, b, c = _yards(prev, pos[i]), _yards(pos[i], nxt), _yards(prev, nxt)
        if None in (a, b, c):
            continue
        detour = a + b - c
        if detour < MIN_DETOUR:
            continue
        n += 1
        first, rest = s.split("\n", 1) if "\n" in s else (s, "")
        steps[i] = first + f"\n    #share {n}\n" + rest
        title = re.findall(r">>\s*Accept ([^\n|<]+)", s)
        report.append(f"#share {n}: {', '.join(t.strip() for t in title)} ({detour:.0f} yd saved)")
    return "\n".join([head] + steps), report
