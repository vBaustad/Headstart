"""For every quest Headstart added to a route (blocks.py, the Dun Morogh fork): the level you are at that
step, against the quest's level. Flags a hand-in that pays less than full XP and a pickup 5+ levels
above you. Your level is a straight line through the route's range by step ("16-19": 16 at the first
step, 19 at the last), so it is a rough guide. Run after placing anything new: the Ruins of Lordaeron
went in at 27-30 (dungeon 15-20) before this existed.

    python tools/check_levels.py
"""
import re, os, sys, glob, ast
sys.path.insert(0, 'S:/forever-data/research/leveling'); os.chdir('S:/forever-data/research/leveling')
from qdb import SCAN, XP
G = 'S:/forever-addons/Headstart/Guides/'
src = open('S:/forever-addons/Headstart/tools/blocks.py', encoding='utf-8').read()
ours = set()
for m in re.finditer(r'\b(?:accept|turnin|do)\s+([\d ]+)', src):
    ours |= {int(x) for x in m.group(1).split()}
ours |= {int(x) for x in re.findall(r'\.(?:accept|turnin|complete) (\d+)', src)}
dm = open('S:/forever-addons/Headstart/tools/fork_dunmorogh.py', encoding='utf-8').read()
ours |= {int(x) for x in re.findall(r'\.(?:accept|turnin) (\d+)', dm)}
def mult(ql, pl):
    return max(1, min(10, 2 * (ql - pl) + 20)) / 10
rows = []
for f in glob.glob(G + '**/*.lua', recursive=True):
    t = open(f, encoding='utf-8').read()
    name = re.search(r'^#name\s+(.*)$', t, re.M)
    if not name: continue
    rng = re.match(r'(\d+)-(\d+)', name.group(1))
    if not rng: continue
    lo, hi = int(rng.group(1)), int(rng.group(2))
    steps = re.split(r'\n(?=step\b)', t)[1:]
    grp = lambda s: '#role A,B,C' in s
    for i, s in enumerate(steps):
        pl = lo + (hi - lo) * i / max(1, len(steps) - 1)
        for kind, q in re.findall(r'\.(accept|turnin) (\d+)', s):
            q = int(q)
            if q not in ours: continue
            sc = SCAN.get(q) or {}
            ql = sc.get('ql') or (XP.get(q) or (None,))[0]
            xp = sc.get('xp') or (XP.get(q) or (0, 0))[1]
            rows.append((name.group(1), i, kind, q, sc.get('t', '?'), ql, round(pl, 1), xp, grp(s)))
flag = []
for g, i, kind, q, t, ql, pl, xp, isg in rows:
    if ql is None: continue
    note = []
    if kind == 'turnin':
        m = mult(ql, pl)
        if m < 1: note.append(f'pays {int(m*100)}% ({int(xp*m)} of {xp})')
    if kind == 'accept' and ql - pl >= 5: note.append(f'{ql - pl:.0f} levels above you')
    if note: flag.append((g, i, kind, q, t, ql, pl, isg, '; '.join(note)))
for r in sorted(flag): print(f"{r[0][:28]:28s} step {r[1]:3d} {r[2]:6s} {r[3]:6d} {r[4][:30]:30s} ql {r[5]:2d} you ~{r[6]:4.1f} {'GROUP ' if r[7] else ''}{r[8]}")
print(len(rows), 'quest events checked,', len(flag), 'flagged')
