"""Quest colours at hand-in: the level you are at each step, against the quest's level, as the quest log
colours it. The rule (the user's): never hand in a grey quest, green at worst, yellow or orange
preferred. A grey hand-in fails (exit 1); green ones are listed, and (for our own quests) pickups 5+
levels above you. Your level is a straight line through the route's range by step ("16-19": 16 at the
first step, 19 at the last), so it is a rough guide. Run after placing anything new: the Ruins of
Lordaeron went in at 27-30 (dungeon 15-20) before this existed. tools/smoke.py runs everyone().

    python tools/check_levels.py          the quests Headstart added (blocks.py, the Dun Morogh fork)
    python tools/check_levels.py --all    every hand-in in every route (RestedXP's own too)
    python tools/check_levels.py --all --as Dwarf Paladin    only the steps that character sees
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, 'S:/forever-data/research/leveling')
_cwd = os.getcwd()
os.chdir('S:/forever-data/research/leveling')
from qdb import SCAN, XP  # noqa: E402
os.chdir(_cwd)
import blocks  # noqa: E402
from check_deathskips import CLASSES, applies, lines_for, XP_RATE_1  # noqa: E402

G = os.path.join(os.path.dirname(HERE), 'Guides')

# Class quests that teach a spell, done for the spell whatever they pay: the Paladin's Tome of
# Divinity (Redemption), which RestedXP has Humans finish late
SPELL_QUESTS = set(range(1641, 1649)) | set(range(1778, 1789)) | {2999}

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
    """Share of its XP a quest pays: full up to 5 levels below you, then 80/60/40/20, then 10%."""
    return max(1, min(10, 2 * (ql - pl) + 20)) / 10


def grey_level(pl):
    """The highest level that is grey to you (Classic's gray level, which the quest log uses too)."""
    if pl <= 5:
        return 0
    if pl <= 39:
        return pl - pl // 10 - 5
    return pl - pl // 5 - 1


def colour(ql, pl):
    d = ql - pl
    if d >= 5:
        return "red"
    if d >= 3:
        return "orange"
    if d >= -2:
        return "yellow"
    return "grey" if ql <= grey_level(pl) else "green"


def start_level(f):
    m = re.search(r'^#name\s+(\d+)-(\d+)', open(f, encoding='utf-8').read(), re.M)
    return (int(m.group(1)), int(m.group(2))) if m else (99, 99)


FILES = sorted(glob.glob(os.path.join(G, '**', '*.lua'), recursive=True), key=start_level)
TEXT = {f: open(f, encoding='utf-8').read() for f in FILES}


def check(as_=None, all_=False):
    """(rows, flagged, grey): every pickup and hand-in looked at, those worth a look, the grey hand-ins.
    as_: (race, class) to take only the steps that character sees, in route order, a quest handed in
    earlier on the way skipped later (a later copy is a catch-up)."""
    rows, done = [], set()
    for f in FILES:
        t = TEXT[f]
        name = re.search(r'^#name\s+(.*)$', t, re.M)
        rng = name and re.match(r'(\d+)-(\d+)', name.group(1))
        if not rng:
            continue
        lo, hi = int(rng.group(1)), int(rng.group(2))
        steps = re.split(r'\n(?=step\b)', t)[1:]
        if as_:
            race, cls = as_
            header = t.split('\nstep')[0]
            if not all(applies(x.strip(), race, cls)
                       for pair in re.findall(r'^#next.*?<<(.*)$|^<<(.*)$', header, re.M) for x in pair if x):
                continue
            mine = []
            for s in steps:
                m = re.match(r'step\s*<<\s*(.*)', s.split('\n')[0])
                if XP_RATE_1(s) and applies(m.group(1).strip() if m else '', race, cls):
                    mine.append('\n'.join(lines_for(s, race, cls)))
            steps = mine
        for i, s in enumerate(steps):
            pl = lo + (hi - lo) * i / max(1, len(steps) - 1)
            for kind, q in re.findall(r'\.(accept|turnin) (\d+)', s):
                q = int(q)
                if as_ and kind == 'turnin':
                    if q in done:
                        continue
                    done.add(q)
                if q not in ours and not all_:
                    continue
                sc = SCAN.get(q) or {}
                ql = sc.get('ql') or (XP.get(q) or (None,))[0]
                xp = sc.get('xp') or (XP.get(q) or (0, 0))[1]
                rows.append((name.group(1), i, kind, q, sc.get('t', '?'), ql, round(pl, 1), xp, '#role A,B,C' in s))
    flag = []
    for g, i, kind, q, t, ql, pl, xp, isg in rows:
        if ql is None:
            continue
        note = []
        if kind == 'turnin':
            c, m = colour(ql, round(pl)), mult(ql, pl)
            if c == 'grey' and q in SPELL_QUESTS:
                note.append(f'grey but a class spell quest, pays {int(m * 100)}%')
            elif c in ('grey', 'green'):
                note.append(f'{"GREY" if c == "grey" else c}, pays {int(m * 100)}% ({int(xp * m)} of {xp})')
        if kind == 'accept' and ql - pl >= 5 and not all_:
            note.append(f'{ql - pl:.0f} levels above you')
        if note:
            flag.append((g, i, kind, q, t, ql, pl, isg, '; '.join(note)))
    return rows, flag, [r for r in flag if 'GREY' in r[8]]


def everyone():
    """Grey hand-ins on the whole route for every Alliance race and class: [(race, class, row)]."""
    return [(race, cls, r) for race, classes in CLASSES.items() for cls in classes
            for r in check((race, cls), True)[2]]


if __name__ == '__main__':
    AS = sys.argv[sys.argv.index('--as') + 1:sys.argv.index('--as') + 3] if '--as' in sys.argv else None
    rows, flag, grey = check(AS, '--all' in sys.argv)
    for r in sorted(flag):
        print(f"{r[0][:28]:28s} step {r[1]:3d} {r[2]:6s} {r[3]:6d} {r[4][:30]:30s} ql {r[5]:2d} you ~{r[6]:4.1f} "
              f"{'GROUP ' if r[7] else ''}{r[8]}")
    print(len(rows), 'quest events checked,', len(flag), 'flagged,', len(grey), 'grey hand-ins')
    sys.exit(1 if grey else 0)
