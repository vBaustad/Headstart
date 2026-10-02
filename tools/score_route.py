"""Time along the Dwarf route: XP per minute for each route, and which quests are slower than grinding.

    python tools/score_route.py                      Dwarf Paladin, launch-day crowds
    python tools/score_route.py --class Warrior      another Dwarf class
    python tools/score_route.py --quiet              no crowds (a quiet realm, or weeks later)
    python tools/score_route.py --quests             plus every quest: minutes saved if left out
    python tools/score_route.py --from "12-14 Loch Modan (Dwarf/Gnome)" --compare "13-15 Westfall" "14-16 Darkshore"
                                                     the routes after one, each entered from it

The walk is check_levels.py's (the character's own steps, along #next, quest XP from our server scan
with Forever's rule for quests below you, the kills their objectives need). Each step is priced with
research/leveling/model.py, calibrated on our logged runs (calibrate.py, levels 1-9: running 6.9 yd/s,
a kill every 19.5 s at your level, 15 s a little below, 11 s well below):
  travel   straight-line yards to the step x 1.25 (paths aren't straight) / run speed; flights at
           32 yd/s plus 20 s; a boat or another continent 300 s; the tram 100 s; hearth 12 s
  work     each objective once: kills x kill time, drops x kills per drop (Questie's drop rates),
           objects x 10 s; times the zone's crowd factor (below)
  talk     4 s for a step that takes or hands in a quest
  grind    the route's own "grind to" steps: the missing XP at a same-level mob's XP per kill time
A quest is "slower than grinding" when leaving it out (and what only it needed: its accept, its
objectives, its hand-in, and the steps that served nothing else) saves more minutes than grinding its
XP back would cost at that level.

Crowds (an estimate until launch: one factor on objective time per zone and level, from who levels
where: Humans are the most played Alliance race, so Elwynn and Westfall fill most; every race meets in
Redridge; Loch Modan is mostly Dwarves and Gnomes; the factor is for the launch-day wave a fast
player levels with, about 1.0 for a quiet realm). See CROWD.
"""
import copy
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import check_levels as cl  # noqa: E402  (loads research model, qdb, the guides)

model = cl.model
GOTO = re.compile(r"^\.goto\s+(\d+)(/\d)?\s*,\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)")

# uiMap -> crowd factor on objective time at launch (guess; see the docstring)
CROWD = {1426: 1.8, 1429: 2.0, 1436: 1.8, 1432: 1.3, 1439: 1.5, 1438: 1.6, 1433: 1.6, 1431: 1.4,
         1440: 1.3, 1437: 1.3, 1424: 1.2, 1417: 1.1, 1442: 1.1, 1420: 1.0}
ZONES = {1426: "Dun Morogh", 1429: "Elwynn", 1436: "Westfall", 1432: "Loch Modan", 1439: "Darkshore",
         1438: "Teldrassil", 1433: "Redridge", 1431: "Duskwood", 1440: "Ashenvale", 1437: "Wetlands",
         1424: "Hillsbrad", 1453: "Stormwind", 1455: "Ironforge", 1457: "Darnassus"}


def gotos(s):
    """The step's places: [(uiMap, world position)]."""
    out = []
    for ln in s.split("\n"):
        m = GOTO.match(ln.strip().split(">>")[0].strip())
        if m:
            mapid = int(m.group(1))
            p = model.world(mapid, float(m.group(3)), float(m.group(4)), bool(m.group(2)))
            if p:
                out.append((mapid, p))
    return out


def walk(race, cls, crowd=True, skip=frozenset(), start=None, start_state=None, only=None):
    """[(route, step, seconds by kind, xp gained, level, zone, quests handed in)] along the route.
    skip: quests left out. start/start_state: begin at that route with (xp, pos, home); only: the routes
    to walk (the others are not followed)."""
    out = []
    seen = set()
    todo = [(start or cl.START[race], *(start_state or (0.0, None, None)), set(), set(), set())]
    while todo:
        gname, xp, pos, home, onq, done, worked = todo.pop(0)
        if gname in seen or (only and gname not in only):
            continue
        seen.add(gname)
        header, steps = cl.GUIDES[gname]
        n = 0
        flying = False
        for s in steps:
            m = re.match(r"step\s*<<\s*(.*)", s.split("\n")[0])
            if not (cl.XP_RATE_1(s) and cl.applies(m.group(1).strip() if m else "", race, cls)):
                continue
            s = "\n".join(cl.lines_for(s, race, cls))
            evs = [(k, int(q), int(i or 0)) for k, q, i in
                   re.findall(r"^\s*\.(accept|turnin|complete) (\d+)(?:,(\d+))?", s, re.M)]
            mine = [e for e in evs if e[1] not in skip]
            cmds = re.findall(r"^\s*\.(hs|fly|home|deathskip|zone)\b", s, re.M)
            if evs and not mine and not cmds:
                continue                                   # the step served only quests left out
            L = model.level_of(xp)
            t = {"travel": 0.0, "work": 0.0, "talk": 0.0, "grind": 0.0, "jump": 0.0}
            gained = 0.0
            places = gotos(s)
            target = zone = None
            if places:
                works = any(k == "complete" for k, _, _ in mine) or "#loop" in s
                pts = [p for _, p in places]
                if works:
                    same = [p for p in pts if pos is None or p[0] == pos[0]] or pts
                    target = (same[0][0], sum(p[1] for p in same) / len(same), sum(p[2] for p in same) / len(same))
                else:
                    target = pts[-1]
                zone = places[-1][0]
            if "hs" in cmds and home:
                t["jump"] += model.HEARTH
                pos = home
            if "deathskip" in cmds:
                t["jump"] += model.DEATHSKIP
                pos = None
            if target:
                if pos is not None:
                    d = model.dist(pos, target)
                    if pos[0] != target[0]:
                        t["jump"] += model.BOAT
                    elif flying:
                        t["jump"] += model.FLY_OVERHEAD + d / model.FLY_SPEED
                    elif d > 2500 and abs(pos[1] - target[1]) > 2500:
                        t["jump"] += model.TRAM                     # Ironforge <-> Stormwind
                    else:
                        t["travel"] += d * model.DETOUR / model.RUN
                pos = target
                flying = False
            if "home" in cmds and target:
                home = target
            if "fly" in cmds:
                flying = True
            talked = False
            hands = []
            for kind, q, i in mine:
                if kind == "accept" and q not in done:
                    onq.add(q)
                    talked = True
                elif kind == "turnin" and q in onq:
                    onq.discard(q)
                    done.add(q)
                    talked = True
                    sc = cl.SCAN.get(q) or {}
                    ql = sc.get("ql") or (cl.XP.get(q) or (L,))[0]
                    got = (sc.get("xp") or (cl.XP.get(q) or (0, 0))[1]) * cl.mult(ql, L)
                    xp += got
                    gained += got
                    hands.append(q)
                elif kind == "complete" and q in onq and (q, i) not in worked:
                    worked.add((q, i))
                    secs, kxp = model.objective(q, i, L)
                    t["work"] += secs * (CROWD.get(zone, 1.0) if crowd else 1.0)
                    xp += kxp
                    gained += kxp
            if talked:
                t["talk"] += model.TALK
            for arg in re.findall(r"^\s*\.xp\s+([^>\n]*)", s, re.M):
                floor = model.xp_floor(arg)
                if floor and floor > xp and "#optional" not in s:
                    rate = model.mob_xp(L, L) / model.kill_time(L, L)
                    # grinding is crowded too: the same factor as objectives in that zone
                    t["grind"] += (floor - xp) / rate * (CROWD.get(zone, 1.0) if crowd else 1.0)
                    gained += floor - xp
                    xp = floor
            out.append((gname, n, t, gained, L, zone, hands, (xp, pos, home)))
            n += 1
        nexts = cl._nexts(header, race, cls)
        for k, nxt in enumerate(nexts):
            state = (onq, done, worked) if k == 0 else copy.deepcopy((onq, done, worked))
            todo.append((nxt, xp, pos, home, *state))
    return out


def walk_path(race, cls, path, crowd=True, skip=frozenset()):
    """walk() along exactly these routes, in this order (one choice at every fork)."""
    rows, state = [], None
    for g in path:
        part = walk(race, cls, crowd, skip, start=g, start_state=state, only={g})
        rows += part
        if part:
            state = part[-1][7]
    return rows


# The Dwarf's ways from Coldridge to 30: one choice at each of the routes' forks
COMMON = ["1-5 Coldridge Valley (Launch)", "5-11 Dun Morogh (Launch)", "12-14 Loch Modan (Dwarf/Gnome)"]
LATE = ["21-23 Ashenvale", "23-24 Wetlands", "24-27 Redridge/Duskwood"]
PATHS = {
    "Westfall, Darkshore, Redridge": COMMON + ["13-15 Westfall", "14-16 Darkshore", "16-19 Darkshore",
                                               "19-20 Redridge", "20-21 Darkshore/Ashenvale"] + LATE,
    "Darkshore, Redridge (no Westfall)": COMMON + ["14-16 Darkshore", "16-19 Darkshore", "19-20 Redridge",
                                                   "20-21 Darkshore/Ashenvale"] + LATE,
    "Westfall, Darkshore (no Redridge at 19)": COMMON + ["13-15 Westfall", "14-16 Darkshore", "16-19 Darkshore",
                                                         "20-21 Darkshore/Ashenvale"] + LATE,
    "Darkshore only (no Westfall, no Redridge at 19)": COMMON + ["14-16 Darkshore", "16-19 Darkshore",
                                                                 "20-21 Darkshore/Ashenvale"] + LATE,
}
ENDS = {"then 27-30 Wetlands/Hillsbrad": ["27-30 Wetlands/Hillsbrad"], "then 28-30 Duskwood": ["28-30 Duskwood"]}


def minutes(t):
    return sum(t.values()) / 60


def by_route(rows):
    acc = {}
    for g, n, t, gained, L, zone, hands, _ in rows:
        a = acc.setdefault(g, {"t": dict.fromkeys(t, 0.0), "xp": 0.0, "from": L, "to": L})
        for k, v in t.items():
            a["t"][k] += v
        a["xp"] += gained
        a["to"] = L
    return acc


def report(rows, title):
    print(title)
    print(f"  {'route':34s} {'levels':>7s} {'travel':>6s} {'work':>6s} {'talk':>5s} {'grind':>6s} {'jumps':>6s} {'total':>6s}"
          f" {'XP':>7s} {'XP/min':>6s}")
    tot_m = tot_x = 0
    for g, a in by_route(rows).items():
        m = sum(a["t"].values()) / 60
        tot_m += m
        tot_x += a["xp"]
        t = {k: v / 60 for k, v in a["t"].items()}
        print(f"  {g[:34]:34s} {a['from']:>3d}-{a['to']:<3d} {t['travel']:6.1f} {t['work']:6.1f} {t['talk']:5.1f}"
              f" {t['grind']:6.1f} {t['jump']:6.1f} {m:6.1f} {a['xp']:7.0f} {a['xp'] / max(m, 0.1):6.0f}")
    print(f"  {'all':34s} {'':7s} {'':6s} {'':6s} {'':5s} {'':6s} {'':6s} {tot_m:6.1f} {tot_x:7.0f} {tot_x / max(tot_m, 0.1):6.0f}"
          f"   ({tot_m / 60:.1f} hours)")


def grind_rate(L):
    """XP per minute killing same-level mobs, the yardstick."""
    return model.mob_xp(L, L) / model.kill_time(L, L) * 60


if __name__ == "__main__":
    args = sys.argv[1:]
    cls = args[args.index("--class") + 1] if "--class" in args else "Paladin"
    crowd = "--quiet" not in args
    if "--paths" in args:
        print(f"Dwarf {cls}, {'launch-day crowds' if crowd else 'no crowds'}: hours from level 1 to the end of each way")
        for pname, path in PATHS.items():
            for ename, end in ENDS.items():
                rows = walk_path("Dwarf", cls, path + end, crowd)
                m = sum(minutes(r[2]) for r in rows)
                g = sum(r[2]["grind"] for r in rows) / 60
                xp = rows[-1][7][0]
                lvl = model.level_of(xp)
                frac = (xp - model.total_for(lvl)) / model.XP_TO_NEXT[lvl]
                print(f"  {pname + ', ' + ename:75s} {m / 60:5.1f} h  to level {lvl + frac:5.2f}"
                      f"  ({g:5.1f} min of it grinding)")
        sys.exit(0)
    rows = walk("Dwarf", cls, crowd)
    if "--compare" in args:
        frm = args[args.index("--from") + 1]
        state = next(r[7] for r in reversed(rows) if r[0] == frm)
        L = model.level_of(state[0])
        print(f"After {frm} (level {L}; grinding same-level mobs: {grind_rate(L):.0f} XP/min):")
        for g in args[args.index("--compare") + 1:]:
            if g.startswith("--"):
                break
            sub = walk("Dwarf", cls, crowd, start=g, start_state=state, only={g})
            report(sub, f"  {g}, entered at {L}:")
        sys.exit(0)
    report(rows, f"Dwarf {cls}, {'launch-day crowds' if crowd else 'no crowds'}"
                 f" (grinding: {grind_rate(10):.0f} XP/min at 10, {grind_rate(20):.0f} at 20, {grind_rate(28):.0f} at 28):")
    if "--quests" in args:
        base = sum(minutes(r[2]) for r in rows)
        final = rows[-1][7][0]
        handed = [(r[0], q, r[4]) for r in rows for q in r[6]]
        res = []
        for g, q, L in handed:
            chain = {q}
            alt = walk("Dwarf", cls, crowd, skip=frozenset(chain))
            m2 = sum(minutes(r[2]) for r in alt)
            lost = final - alt[-1][7][0]
            regrind = lost / grind_rate(model.level_of(alt[-1][7][0])) if lost > 0 else 0
            res.append((base - m2 - regrind, g, q, L, base - m2, regrind))
        print("\nquests slower than grinding (minutes saved by leaving one out, after grinding its XP back):")
        for saved, g, q, L, gone, regrind in sorted(res, reverse=True)[:40]:
            if saved <= 0:
                break
            title = (cl.SCAN.get(q) or {}).get("t", "?")
            print(f"  {saved:+5.1f} min  {q:6d} {title[:32]:32s} {g[:26]:26s} at {L:2d}  (-{gone:.1f} min, +{regrind:.1f} to grind)")
