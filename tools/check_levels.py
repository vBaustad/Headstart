"""Levels along the route: for every quest handed in, its colour in the quest log at the level you are
then; for every mob a step sends you to kill, its colour too.

The rule (the user's): never hand in a grey quest, green at worst, yellow or orange preferred. A grey
hand-in fails (exit 1). Listed for a look: green hand-ins, grey mobs (the kills give no XP; only the
quest wants them) and red mobs (5+ levels above you), and for our own quests pickups 5+ levels above.

Your level at each step comes from walking the route the way the character plays it: from the race's
first route, along #next (the first choice that applies; the other choices each start from where the
route before them ended), taking only the steps the race and class see at Forever's XP rate, adding the
XP of every quest handed in (our server scan, reduced for quests below you) and of the kills its
objectives need (research/leveling/model.py), and raising it to the route's grind steps (.xp). That is
a floor: kills off the quest's objectives aren't counted. Run after placing anything new: the Ruins of
Lordaeron went in at 27-30 (dungeon 15-20) before this existed. tools/smoke.py runs everyone().

    python tools/check_levels.py                     our quests and kill steps, for every race and class
    python tools/check_levels.py --all               every hand-in and kill step, ours and RestedXP's
    python tools/check_levels.py --as Dwarf Paladin  one character (with or without --all)
    python tools/check_levels.py --levels Dwarf Paladin    the level at the start of each route
"""
import copy
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, 'S:/forever-data/research/leveling')
_cwd = os.getcwd()
os.chdir('S:/forever-data/research/leveling')
from qdb import SCAN, XP, N, forever_mult  # noqa: E402
import model  # noqa: E402
os.chdir(_cwd)
import blocks  # noqa: E402
from check_deathskips import CLASSES, applies, lines_for, XP_RATE_1  # noqa: E402

G = os.path.join(os.path.dirname(HERE), 'Guides')
START = {"Dwarf": "1-5 Coldridge Valley (Launch)", "Gnome": "1-5 Coldridge Valley (Launch)",
         "Human": "1-6 Northshire (Launch)", "NightElf": "1-6 Shadowglen (Launch)"}

# Class quests done for what they give, whatever they pay: the Paladin's Tome of Divinity (Redemption,
# which RestedXP has Humans finish late) and Tome of Valor / The Test of Righteousness (Verigan's Fist)
SPELL_QUESTS = set(range(1641, 1649)) | set(range(1778, 1789)) | {2999} | set(range(1649, 1655))

# our quests: the ones in blocks.py's step specs (not the anchors, which name the route's own steps)
specs = [line for v in vars(blocks).values() if isinstance(v, list) for line in v if isinstance(line, str)]
specs += [line for lst in blocks.BLOCKS.values() for _, _, v in lst for line in v]
ours = set()
for line in specs:
    for m in re.finditer(r'\b(?:accept|turnin|do)\s+([\d ]+)', line):
        ours |= {int(x) for x in m.group(1).split()}
    ours |= {int(x) for x in re.findall(r'\.(?:accept|turnin|complete) (\d+)', line)}
dm = open(os.path.join(HERE, 'fork_dunmorogh.py'), encoding='utf-8').read()
ours |= {int(x) for x in re.findall(r'\.(?:accept|turnin) (\d+)', dm)}


def mult(ql, pl):
    """Share of its XP a quest pays on Forever: full up to 5 levels below you, 80% at 6, 60% at 7, then
    50% (research qdb.forever_mult, measured from a level-20 scan)."""
    return forever_mult(ql, pl)


def grey_level(pl):
    """The highest level that is grey to you (Classic's gray level, which the quest log uses too)."""
    if pl <= 5:
        return 0
    if pl <= 39:
        return pl - pl // 10 - 5
    return pl - pl // 5 - 1


def colour(lvl, pl):
    """Quest-log (and nameplate) colour of something of level lvl, to you at level pl."""
    d = lvl - pl
    if d >= 5:
        return "red"
    if d >= 3:
        return "orange"
    if d >= -2:
        return "yellow"
    return "grey" if lvl <= grey_level(pl) else "green"


MOB_LEVELS = {}
for _r in N.values():
    _name = _r.get('1') if isinstance(_r, dict) else None
    if _name and _r.get('4'):
        _lo, _hi = MOB_LEVELS.get(_name, (99, 0))
        MOB_LEVELS[_name] = (min(_lo, _r['4']), max(_hi, _r.get('5') or _r['4']))

GUIDES = {}      # name -> (header, [step text])
for _f in glob.glob(os.path.join(G, '**', '*.lua'), recursive=True):
    _t = open(_f, encoding='utf-8').read()
    _name = re.search(r'^#name\s+(.*)$', _t, re.M)
    if _name:
        GUIDES[_name.group(1).strip()] = (_t.split('\nstep')[0], re.split(r'\n(?=step\b)', _t)[1:])


def _sees(header, race, cls):
    return all(applies(x.strip(), race, cls) for x in re.findall(r'^<<(.*)$', header, re.M))


def _nexts(header, race, cls):
    out = []
    for names, flt in re.findall(r'^#next\s+([^<\n]*?)\s*(?:<<(.*))?$', header, re.M):
        if flt and not applies(flt.strip(), race, cls):
            continue
        for n in names.split(';'):
            n = n.strip().split('\\')[-1]
            if n in GUIDES and _sees(GUIDES[n][0], race, cls):
                out.append(n)
    return out


def walk(race, cls):
    """The character's way through the routes: [(route, step number, step text, level, events)], events
    being the hand-ins that really happen there [(quest, level before)] and the objectives worked
    [(quest, objective)]."""
    out, seen = [], set()
    todo = [(START[race], 0.0, set(), set(), set())]
    while todo:
        gname, xp, onq, done, worked = todo.pop(0)
        if gname in seen:
            continue
        seen.add(gname)
        header, steps = GUIDES[gname]
        n = 0
        for s in steps:
            m = re.match(r'step\s*<<\s*(.*)', s.split('\n')[0])
            if not (XP_RATE_1(s) and applies(m.group(1).strip() if m else '', race, cls)):
                continue
            s = '\n'.join(lines_for(s, race, cls))
            L = model.level_of(xp)
            hands, works = [], []
            for kind, q, i in re.findall(r'^\s*\.(accept|turnin|complete) (\d+)(?:,(\d+))?', s, re.M):
                q = int(q)
                if kind == 'accept' and q not in done:
                    onq.add(q)
                elif kind == 'turnin' and q in onq:
                    onq.discard(q)
                    done.add(q)
                    hands.append((q, L))
                    sc = SCAN.get(q) or {}
                    ql = sc.get('ql') or (XP.get(q) or (L,))[0]
                    xp += (sc.get('xp') or (XP.get(q) or (0, 0))[1]) * mult(ql, L)
                elif kind == 'complete' and q in onq and (q, int(i or 0)) not in worked:
                    worked.add((q, int(i or 0)))
                    works.append((q, int(i or 0)))
                    xp += model.objective(q, int(i or 0), L)[1]
            for arg in re.findall(r'^\s*\.xp\s+([^>\n]*)', s, re.M):
                floor = model.xp_floor(arg)
                if floor and floor > xp and '#optional' not in s:
                    xp = floor
            out.append((gname, n, s, L, hands, works))
            n += 1
        nexts = _nexts(header, race, cls)
        for k, nxt in enumerate(nexts):
            state = (onq, done, worked) if k == 0 else copy.deepcopy((onq, done, worked))
            todo.append((nxt, xp, *state))
    return out


_WALKS = {}


def walked(race, cls):
    if (race, cls) not in _WALKS:
        _WALKS[(race, cls)] = walk(race, cls)
    return _WALKS[(race, cls)]


def check(as_, all_=False):
    """(flagged, grey) for one character: hand-ins and kill steps worth a look, and the grey hand-ins."""
    flag = []
    for gname, n, s, L, hands, works in walked(*as_):
        group = '#role A,B,C' in s
        for q, lvl in hands:
            if q not in ours and not all_:
                continue
            sc = SCAN.get(q) or {}
            ql = sc.get('ql') or (XP.get(q) or (None,))[0]
            if ql is None:
                continue
            c, m = colour(ql, lvl), mult(ql, lvl)
            xp = sc.get('xp') or (XP.get(q) or (0, 0))[1]
            if c == 'grey' and q in SPELL_QUESTS:
                flag.append((gname, n, 'turnin', q, sc.get('t', '?'), ql, lvl, group, 'grey, a class quest (kept for what it gives)'))
            elif c in ('grey', 'green'):
                flag.append((gname, n, 'turnin', q, sc.get('t', '?'), ql, lvl, group,
                             f'{"GREY" if c == "grey" else c}, pays {int(m * 100)}% ({int(xp * m)} of {xp})'))
        if not works or (not all_ and not {q for q, _ in works} & ours):
            continue
        for mob in re.findall(r'^\s*\.mob\s+\+?([^\n<]+?)\s*$', s, re.M):
            lv = MOB_LEVELS.get(mob.strip())
            if not lv:
                continue
            if colour(lv[1], L) == 'grey':
                flag.append((gname, n, 'mob', 0, mob.strip(), lv[1], L, group, f'grey mob (level {lv[0]}-{lv[1]}): no XP'))
            elif colour(lv[0], L) == 'red' and not group:      # a group step: the dungeon's boss
                flag.append((gname, n, 'mob', 0, mob.strip(), lv[0], L, group, f'RED mob (level {lv[0]}-{lv[1]})'))
    return flag, [r for r in flag if 'GREY' in r[8]]


def red_mobs():
    """Red mobs (5+ levels above you) any step outside a dungeon sends anyone to kill: [(race, class, row)]."""
    return [(race, cls, r) for race, classes in CLASSES.items() for cls in classes
            for r in check((race, cls), True)[0] if 'RED mob' in r[8]]


def everyone(all_=True):
    """Grey hand-ins for every Alliance race and class: [(race, class, row)]."""
    return [(race, cls, r) for race, classes in CLASSES.items() for cls in classes
            for r in check((race, cls), all_)[1]]


if __name__ == '__main__':
    args = sys.argv[1:]
    if '--levels' in args:
        race, cls = args[args.index('--levels') + 1:args.index('--levels') + 3]
        last = None
        for gname, n, s, L, _, _ in walked(race, cls):
            if gname != last:
                print(f'{gname:40s} starts at level {L}')
                last = gname
        sys.exit(0)
    who = [tuple(args[args.index('--as') + 1:args.index('--as') + 3])] if '--as' in args else \
        [(r, c) for r, cs in CLASSES.items() for c in cs]
    rows, greys = {}, 0
    for w in who:
        flag, grey = check(w, '--all' in args)
        greys += len(grey)
        for r in flag:
            rows.setdefault(r[:5] + r[7:], (r, set()))[1].add(f'{w[0]} {w[1]}')
    for (r, chars) in sorted(rows.values(), key=lambda x: (x[0][0], x[0][1])):
        whom = 'everyone' if len(chars) == len(who) and len(who) > 1 else ', '.join(sorted(chars)) if len(chars) <= 3 \
            else f'{len(chars)} characters'
        print(f"{r[0][:28]:28s} step {r[1]:3d} {r[2]:6s} {r[3] or '':>6} {str(r[4])[:28]:28s} lvl {r[5]:2d} you {r[6]:2d} "
              f"{'GROUP ' if r[7] else ''}{r[8]}  [{whom}]")
    print(len(rows), 'flagged,', greys, 'grey hand-ins')
    sys.exit(1 if greys else 0)
