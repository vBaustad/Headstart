"""Write RestedXP route text from a short list of what to do, with the positions, names and objectives
filled in from the data. For the routes we write ourselves (levels 21-30, the group dungeon blocks).

    from route_builder import build
    text = build(header, spec)

A spec is a list of lines; each line is one step (several actions on one line, split by " | ", are done
at the same NPC or place):

    accept 1008 1020            take quests (at their giver)
    turnin 1008                 hand in (at the quest's end NPC)
    do 1008 1020                do the objectives (the step goes to where their mobs or objects are)
    do 1008 : text              ... with our own line of text first
    goto 1440 36.6 49.8 : text  go somewhere (uiMapID, x, y)
    home Astranaar              set your hearthstone at the innkeeper (a note: which innkeeper)
    hs Astranaar                use the hearthstone
    fly Astranaar               take a flight
    xp 23 : text                grind to level 23 (or "xp 22+5000" for XP into a level)
    note text                   a reminder only
    raw ...                     a line of RestedXP text as it is

A line may end with "<< Warrior/Paladin" (only those classes) and start with "group:" (only the Duo and
Trio versions: dungeons) or "solo:" (only the solo version).

Data: Questie's Forever database (Era quests with Forever coordinates) for givers, NPCs, objects and
item drops; our server scan (research/leveling/data/scan_70009.json) for titles and objectives;
Wowhead's Forever pages (wh_details.json) for the quests Forever added, which Questie doesn't have.
"""
import json
import math
import os
import re

DATA = "S:/forever-data/research/leveling/data/"

# Questie zone id -> uiMapID (the map RestedXP's .goto takes)
UIMAP = {
    1: 1426, 12: 1429, 141: 1438, 38: 1432, 40: 1436, 148: 1439, 44: 1433, 10: 1431, 11: 1437, 331: 1440,
    406: 1442, 267: 1424, 45: 1417, 1537: 1455, 1519: 1453, 1657: 1457, 36: 1416, 130: 1421, 17: 1413,
    33: 1434, 400: 1441, 85: 1420,
}
ZONE_NAME = {v: k for k, v in {}.items()}

_db = {}


def _load():
    if _db:
        return
    for name in ("Quest", "Npc", "Object", "Item"):
        _db[name] = json.load(open(DATA + name + ".json", encoding="utf-8"))
    _db["scan"] = json.load(open(DATA + "scan_70009.json", encoding="utf-8"))["quests"]
    wh = DATA + "wh_details.json"
    _db["wh"] = json.load(open(wh, encoding="utf-8")) if os.path.exists(wh) else {}


def _first_spawn(spawns):
    """{zone: {i: {1: x, 2: y}}} -> (uiMap, x, y) of the first spawn in a zone we can map."""
    for zone, pts in (spawns or {}).items():
        if int(zone) in UIMAP:
            p = next(iter(pts.values()))
            return UIMAP[int(zone)], p["1"], p["2"]
    return None


def _spawns(spawns):
    out = []
    for zone, pts in (spawns or {}).items():
        if int(zone) in UIMAP:
            out += [(UIMAP[int(zone)], p["1"], p["2"]) for p in pts.values()]
    return out


def npc(nid):
    n = _db["Npc"].get(str(nid))
    return (n["1"], _first_spawn(n.get("7"))) if n else (None, None)


def obj(oid):
    o = _db["Object"].get(str(oid))
    return (o["1"], _first_spawn(o.get("4"))) if o else (None, None)


def title(q):
    s = _db["scan"].get(str(q))
    if s and s.get("t"):
        return s["t"]
    qq = _db["Quest"].get(str(q))
    return qq["1"] if qq else f"quest {q}"


def _ender(q, end):
    """(kind, name, (uiMap, x, y)) of the quest's giver (end False) or turn-in NPC/object."""
    qq = _db["Quest"].get(str(q))
    if qq:
        who = qq.get("3" if end else "2") or {}
        for nid in (who.get("1") or {}).values():
            name, pos = npc(nid)
            if name:
                return "npc", name, pos
        for oid in (who.get("2") or {}).values():
            name, pos = obj(oid)
            if name:
                return "obj", name, pos
    w = _db["wh"].get(str(q))
    if w:
        for p in w[1]:
            if p[0] == ("end" if end else "start") and p[5] and int(p[4]) in UIMAP:
                x, y = p[5][0]
                return ("npc" if p[1] == 1 else "obj"), p[3], (UIMAP[int(p[4])], x, y)
    return None, None, None


def _objective_points(q):
    """Where a quest's objectives are: (names of mobs to kill/loot, [(uiMap, x, y), ...])."""
    qq = _db["Quest"].get(str(q))
    names, pts = [], []
    if qq:
        o = qq.get("10") or {}
        for cid in (o.get("1") or {}).values():
            n = _db["Npc"].get(str(cid if not isinstance(cid, dict) else cid.get("1")))
            if n:
                names.append(n["1"])
                pts += _spawns(n.get("7"))
        for oid in (o.get("2") or {}).values():
            ob = _db["Object"].get(str(oid if not isinstance(oid, dict) else oid.get("1")))
            if ob:
                pts += _spawns(ob.get("4"))
        for iid in (o.get("3") or {}).values():
            it = _db["Item"].get(str(iid if not isinstance(iid, dict) else iid.get("1")))
            for nid in ((it or {}).get("2") or {}).values():
                n = _db["Npc"].get(str(nid))
                if n:
                    names.append(n["1"])
                    pts += _spawns(n.get("7"))
            for oid in ((it or {}).get("3") or {}).values():
                ob = _db["Object"].get(str(oid))
                if ob:
                    pts += _spawns(ob.get("4"))
    if not pts:
        w = _db["wh"].get(str(q))
        for p in (w[1] if w else []):
            if p[0] in ("requirement", "sourcerequirement") and int(p[4]) in UIMAP:
                if p[1] == 1:
                    names.append(p[3])
                pts += [(UIMAP[int(p[4])], x, y) for x, y in p[5]]
    return list(dict.fromkeys(names)), pts


def _centre(pts, near=None):
    """The densest spot among points (the mob camp), preferring the one nearest `near`."""
    if not pts:
        return None
    best, score = None, -1
    for p in pts:
        n = sum(1 for o in pts if o[0] == p[0] and math.hypot(o[1] - p[1], o[2] - p[2]) < 4)
        if near and near[0] == p[0]:
            n -= math.hypot(near[1] - p[1], near[2] - p[2]) / 20
        if n > score:
            best, score = p, n
    return best


def _goto(pos, radius=None):
    if not pos:
        return None
    r = f",{radius},0" if radius else ""
    return f"    .goto {pos[0]},{pos[1]:.2f},{pos[2]:.2f}{r}"


def _objective_names(q):
    """What each objective is, by type, in the quest's order: {"monster": [...], "item": [...], "object": [...]}."""
    qq = _db["Quest"].get(str(q)) or {}
    o = qq.get("10") or {}
    def names(table, entries):
        out = []
        for e in (entries or {}).values():
            eid = e if not isinstance(e, dict) else e.get("1")
            row = _db[table].get(str(eid))
            out.append(row["1"] if row else None)
        return out
    return {"monster": names("Npc", o.get("1")), "object": names("Object", o.get("2")), "item": names("Item", o.get("3"))}


def _objectives(q):
    """.complete lines, each with what it is: "--Collect Wrathtail Head (x20)", "--Kill Ruuzel (x1)"."""
    s = _db["scan"].get(str(q)) or {}
    names = _objective_names(q)
    used = {"monster": 0, "item": 0, "object": 0}
    out = []
    for i, o in sorted((s.get("obj") or {}).items(), key=lambda kv: int(kv[0])):
        kind, count = o.get("2") or "", o.get("3") or 0
        text = re.sub(r"^\d+/\d+\s*", "", (o.get("1") or "")).strip()
        if not text and kind in names and used[kind] < len(names[kind]):
            text = names[kind][used[kind]] or ""
        if kind in used:
            used[kind] += 1
        verb = {"item": "Collect", "monster": "Kill", "object": "Use"}.get(kind, "")
        label = f"{verb} {text} (x{count})".strip() if text else ""
        out.append(f"    .complete {q},{i}" + (f" --{label}" if label else ""))
    return out


def _do_text(qs, mob_names):
    """The instruction for an objectives step: kill these; loot those items; click those objects."""
    kills, loots, clicks = [], [], []
    for q in qs:
        n = _objective_names(q)
        kills += [x for x in n["monster"] if x]
        loots += [x for x in n["item"] if x]
        clicks += [x for x in n["object"] if x]
    parts = []
    enemies = [m for m in mob_names if m not in clicks]
    if enemies:
        parts.append("Kill " + ", ".join(f"|cRXP_ENEMY_{m}|r" for m in dict.fromkeys(enemies)))
    if loots:
        parts.append(("Loot them for " if enemies else "Loot ") + ", ".join(f"|cRXP_LOOT_{x}|r" for x in dict.fromkeys(loots)))
    if clicks:
        parts.append("Click " + ", ".join(f"|cRXP_PICK_{x}|r" for x in dict.fromkeys(clicks)))
    return ". ".join(parts) or "Do the objectives"


def _step(lines, cls=None, group=None):
    head = "step" + (f" << {cls}" if cls else "")
    tags = []
    if group == "group":
        tags.append("    #role A,B,C")
    elif group == "solo":
        tags.append("    #role solo")
    return "\n".join([head] + tags + lines)


def build(header, spec):
    _load()
    steps, last = [], None
    for raw_line in spec:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        group = None
        if line.startswith("group:"):
            group, line = "group", line[6:].strip()
        elif line.startswith("solo:"):
            group, line = "solo", line[5:].strip()
        cls = None
        if " << " in line:
            line, cls = line.rsplit(" << ", 1)
        lines = []
        for part in [p.strip() for p in line.split(" | ")]:
            verb, _, rest = part.partition(" ")
            text = None
            if " : " in rest:
                rest, text = rest.split(" : ", 1)
            if verb in ("accept", "turnin"):
                for q in rest.split():
                    kind, name, pos = _ender(int(q), verb == "turnin")
                    if pos and not any(l.startswith("    .goto") for l in lines):
                        lines.insert(0, _goto(pos))
                        last = pos
                    if name and not any(".target" in l or "Talk to" in l or "Click" in l for l in lines):
                        talk = ("Talk to |cRXP_FRIENDLY_" if kind == "npc" else "Click |cRXP_PICK_") + name + "|r"
                        lines.append("    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|t" + talk)
                        if kind == "npc":
                            lines.append(f"    .target {name}")
                    lines.append(f"    .{verb} {q} >> {'Accept' if verb == 'accept' else 'Turn in'} {title(int(q))}")
            elif verb == "do":
                qs = [int(q) for q in rest.split()]
                names, pts = [], []
                for q in qs:
                    n, p = _objective_points(q)
                    names += n
                    pts += p
                pos = _centre(pts, last)
                if pos:
                    lines.append(_goto(pos))
                    last = pos
                lines.append("    >>" + (text or _do_text(qs, names)))
                for q in qs:
                    lines += _objectives(q)
                for n in dict.fromkeys(names):
                    lines.append(f"    .mob {n}")
                text = None
            elif verb == "goto":
                m, x, y = rest.split()[:3]
                lines.append(f"    .goto {m},{x},{y}")
                last = (int(m), float(x), float(y))
            elif verb == "hs":
                lines.append(f"    .hs >> Hearth to {rest}")
            elif verb == "home":
                lines.append(f"    .home >> Set your Hearthstone to {rest}")
            elif verb == "fly":
                lines.append(f"    .fly {rest} >> Fly to {rest}")
            elif verb == "xp":
                lines.append(f"    .xp {rest} >> " + (text or f"Grind to {rest}"))
                text = None
            elif verb == "note":
                lines.append("    +" + rest + (" : " + text if text else ""))
                text = None
            elif verb == "raw":
                lines.append("    " + rest)
            else:
                raise ValueError("unknown step: " + part)
            if text:
                lines.insert(1 if lines and lines[0].startswith("    .goto") else 0, "    >>" + text)
        steps.append(_step(lines, cls, group))
    return header.rstrip("\n") + "\n" + "\n".join(steps) + "\n"
