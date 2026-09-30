"""Every death skip must be followed by a step the route hasn't already done.

RestedXP's death skips are "#completewith next": the death skip ends when the next step does. If the
next step is one the route did earlier (a quest taken or handed in before), it is done the moment it
comes up, and the death skip vanishes with it: the route says to walk instead (a logged run,
2026-10-01, after we moved The Reports to an earlier visit). Checked for every Alliance race and class,
with RestedXP's step and line filters (<< Hunter, << !NightElf, Warrior/Paladin ...).

    python tools/check_deathskips.py      exit 1 and a list when a death skip would vanish
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLASSES = {"Human": ["Warrior", "Paladin", "Rogue", "Priest", "Mage", "Warlock"],
           "Dwarf": ["Warrior", "Paladin", "Hunter", "Rogue", "Priest"],
           "Gnome": ["Warrior", "Rogue", "Mage", "Warlock"],
           "NightElf": ["Warrior", "Hunter", "Rogue", "Priest", "Druid"]}
KNOWN = {"Alliance", *CLASSES, *{c for cs in CLASSES.values() for c in cs}}


def applies(flt, race, cls):
    """RestedXP's filter: words separated by spaces must all hold, "/" is or, "!" is not."""
    if not flt:
        return True
    for word in flt.split():
        ok = False
        for alt in word.split("/"):
            neg = alt.startswith("!")
            name = alt.lstrip("!")
            if name in KNOWN:
                hit = name in (race, cls, "Alliance")
            else:
                hit = False          # a game or mode word (sod, skip, tbc): never Forever
            if hit != neg:
                ok = True
        if not ok:
            return False
    return True


def XP_RATE_1(step):
    """Whether a step shows at Forever's normal XP rate (RestedXP's #xprate >1.59 steps don't)."""
    for op, v in re.findall(r"#xprate\s*([<>])\s*([\d.]+)", step):
        if (op == ">" and not 1 > float(v)) or (op == "<" and not 1 < float(v)):
            return False
    return True


def lines_for(step, race, cls):
    out = []
    for line in step.split("\n"):
        m = re.search(r"<<\s*(.*)$", line)
        if line.startswith("step") or not m or applies(m.group(1).strip(), race, cls):
            out.append(line)
    return out


def check(path):
    text = open(path, encoding="utf-8").read()
    steps = re.split(r"\n(?=step\b)", text)[1:]
    problems = []
    for race, classes in CLASSES.items():
        for cls in classes:
            mine = []
            for s in steps:
                m = re.match(r"step\s*<<\s*(.*)", s.split("\n")[0])
                if XP_RATE_1(s) and applies(m.group(1).strip() if m else "", race, cls):
                    mine.append("\n".join(lines_for(s, race, cls)))
            done = set()
            for i, s in enumerate(mine):
                if ".deathskip" in s and "#completewith next" in s and i + 1 < len(mine):
                    nxt = re.findall(r"\.(accept|turnin) (\d+)", mine[i + 1])
                    if nxt and all(v_q in done for v_q in nxt):
                        problems.append(f"{os.path.relpath(path, ROOT)}: {race} {cls}: the death skip is followed by"
                                        f" {', '.join(v + ' ' + q for v, q in nxt)}, already done earlier")
                # only a step that always runs proves a quest done: an optional or conditional one is
                # one of two alternative orders (Northshire has them), so its twin later still counts
                if not re.search(r"#optional|\.isOnQuest|\.isQuest|\.isNotOnQuest", s):
                    done.update(re.findall(r"\.(accept|turnin) (\d+)", s))
    return problems


if __name__ == "__main__":
    found = []
    for f in sorted(glob.glob(os.path.join(ROOT, "Guides", "*.lua")) + glob.glob(os.path.join(ROOT, "Guides", "Levelling", "*.lua"))):
        found += check(f)
    for p in dict.fromkeys(found):
        print(p)
    print(f"death skips: {len(set(found))} would vanish")
    sys.exit(1 if found else 0)
