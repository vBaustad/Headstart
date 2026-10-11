"""Compare Headstart's spell data with foreverchanges.pro's spellbook, class by class.

    python tools/check_spellbook.py            fetches the nine classes' pages
    python tools/check_spellbook.py <folder>   reads <class>.html (spells by level) and <class>_all.html
                                               (the whole spellbook) from a folder, and saves them there
                                               when they aren't in it yet

The site is built from the same client table as our generators (SkillLineAbility), by someone who has
checked it against the game: where the two disagree, ours is the one to look at. Not a gate: it needs
the network, and the site follows the newest beta build.

What it prints:
  the trainer list (Data/TrainerSpells.lua)  - a rank on the site that ours lacks, or at another level;
      a rank or a first rank of ours that the site doesn't have
  the planner's spells (Headstart_Setup/PlannerSpells.lua, the ones you can press) that the site's
      whole spellbook doesn't have
"""
import html
import os
import re
import sys
import urllib.request

import lupa.lua51 as lupa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLASSES = ["warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid"]
SITE = "https://foreverchanges.pro/spellbook/"
# On the site as trained, and left out of ours on purpose: mounts (not Headstart's business), and the
# secondary skills that are one class's - a rogue's poisons (the skill is a quest's), a mage's
# Comprehend Scroll and Study, a hunter's Beast Training. Whether a class trainer sells those isn't known.
LEFT_OUT = re.compile(r"Poison|^Blinding Powder$|^Summon (Warhorse|Charger|Felsteed|Dreadsteed)$|^Comprehend Scroll$|^Study$|^Beast Training$")


def page(folder, name, url):
    path = folder and os.path.join(folder, name + ".html")
    if path and os.path.exists(path):
        return open(path, encoding="utf-8").read()
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (Headstart tools/check_spellbook.py)"})
    text = urllib.request.urlopen(req, timeout=30).read().decode("utf-8")
    if path:
        open(path, "w", encoding="utf-8").write(text)
    return text


def by_level(text):
    """The spells-by-level page: { name: (level, tag) } for what is first learned, { (name, rank): level } for later ranks."""
    first, ranks = {}, {}
    for sec in re.split(r'<section class="tl-visit"', text)[1:]:
        level = int(re.search(r"<span>Level (\d+)</span>", sec).group(1))
        parts = sec.split('class="tl-ranks"')
        for m in re.finditer(r'<strong>(.*?)</strong>.*?<span class="v2-row-meta">(.*?)</span><span class="v2-chevron"', parts[0], re.S):
            first[html.unescape(m.group(1))] = (level, re.sub(r"<.*?>", "", m.group(2)).strip())
        if len(parts) > 1:
            for m in re.finditer(r"<span>([^<]*)</span><small>Rank (\d+)</small>", parts[1]):
                ranks[(html.unescape(m.group(1)), int(m.group(2)))] = level
    return first, ranks


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else None
    if folder:
        os.makedirs(folder, exist_ok=True)
    lua = lupa.LuaRuntime()
    lua.execute("HeadstartNS = {}")
    ns = lua.eval("HeadstartNS")
    for f in ("Data/TrainerSpells.lua", "Headstart_Setup/SpellLevels.lua", "Headstart_Setup/PlannerSpells.lua"):
        lua.eval("function(c) return assert(loadstring(c, 'f')) end")(open(os.path.join(ROOT, f), encoding="utf-8").read())("Headstart", ns)
    total = 0
    for c in CLASSES:
        token = c.upper()
        first, ranks = by_level(page(folder, c, SITE + c + "/levels"))
        everything = {html.unescape(m) for m in re.findall(r"<strong>(.*?)</strong>", page(folder, c + "_all", SITE + c))}
        ours_rank, ours_first = {}, {}
        for e in ns.TrainerSpells[token].values():
            if e[4] >= 2:
                ours_rank[(e[3], e[4])] = e[2]
            else:
                ours_first[e[3]] = e[2]
        out = []
        for k, lvl in sorted(ranks.items(), key=lambda x: (x[1], x[0])):
            if k not in ours_rank:
                out.append(f"  trainer: the site has {k[0]} rank {k[1]} at {lvl}, ours doesn't")
            elif ours_rank[k] != lvl:
                out.append(f"  trainer: {k[0]} rank {k[1]} is level {lvl} on the site, {ours_rank[k]} in ours")
        for k, lvl in sorted(ours_rank.items(), key=lambda x: (x[1], x[0])):
            if k not in ranks and k[0] not in first:        # (a poison's "II" is its own spell on the site)
                out.append(f"  trainer: ours has {k[0]} rank {k[1]} at {lvl}, the site doesn't")
        for name, lvl in sorted(ours_first.items(), key=lambda x: (x[1], x[0])):
            if name not in first:
                out.append(f"  trainer: ours has {name} at {lvl}, the site doesn't")
            elif first[name][0] != lvl and first[name][1] != "Talent":
                out.append(f"  trainer: {name} is level {first[name][0]} on the site, {lvl} in ours")
        for name, (lvl, tag) in sorted(first.items(), key=lambda x: (x[1][0], x[0])):
            taught = name in ours_first or any(k[0] == name for k in ours_rank)
            if tag != "Talent" and lvl > 1 and not taught and not LEFT_OUT.search(name):
                out.append(f"  trainer: the site has {name} at {lvl} (trained), ours doesn't")
        for name, d in sorted(dict(ns.PlannerSpells[token].items()).items()):
            if d[3] != 1 and name not in everything:
                out.append(f"  planner: {name} is not in the site's spellbook")
        print(f"{token}: {len(out)} to look at  (site: {len(first)} spells by level, {len(ranks)} later ranks, {len(everything)} in the spellbook)")
        for line in out:
            print(line)
        total += len(out)
    print(f"\n{total} in all")
    return 0


if __name__ == "__main__":
    sys.exit(main())
