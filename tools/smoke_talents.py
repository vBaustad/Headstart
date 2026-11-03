"""Smoke test of talent builds (Talents.lua, Data/TalentTrees.lua, Data/TalentBuilds.lua), in Lua 5.1 (lupa).

    python tools/smoke_talents.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Every class's tree and build as generated: 51 points, each a node of its class's tree, 5 points a row in a tab,
a needed talent at full rank first. Following a build: the next talent from the game's ranks (a point taken out of
the build's order still counts), and the talent points notice saying it. Uses smoke.py's fake game.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def files(folder, toc):
    return [os.path.join(folder, l.strip().replace(chr(92), "/"))
            for l in open(os.path.join(folder, toc), encoding="utf-8")
            if l.strip().endswith(".lua") and not l.startswith("#") and not l.startswith("Libs")]


def run():
    src = open(os.path.join(ROOT, "tools", "smoke.py"), encoding="utf-8").read()
    env = {"__name__": "smoke_head", "__file__": os.path.join(ROOT, "tools", "smoke.py")}
    exec(compile(src.split("YR = lua.table()")[0], "smoke.py (head)", "exec"), env)
    lua = env["lua"]
    lua.execute("""
        RANKS = {}
        C_ClassTalents = { GetActiveConfigID = function() return 7 end }
        C_Traits = { GetNodeInfo = function(config, node) return { ranksPurchased = RANKS[node] or 0 } end }
        C_Spell = C_Spell or {}
        NAMES = { [12282] = "Improved Heroic Strike", [12286] = "Improved Rend" }
        C_Spell.GetSpellName = function(id) return NAMES[id] or ("Spell " .. id) end
        function UnitClass() return "Warrior", "WARRIOR", 1 end
        YippRouteDB = nil YippSetupCharDB = nil""")
    YR = lua.table()
    load = lua.eval("function(c, n) return assert(loadstring(c, n)) end")
    for f in files(ROOT, "Headstart.toc"):
        load(open(f, encoding="utf-8").read(), os.path.basename(f))("Headstart", YR)
    g = lua.globals()
    g.Fire("ADDON_LOADED", "Headstart")
    g.Fire("PLAYER_LOGIN")
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    trees, builds = YR.TalentTrees, YR.TalentBuilds
    classes = [1, 2, 3, 4, 5, 7, 8, 9, 11]
    check(all(trees[c] is not None and builds[c] is not None for c in classes), "a tree and a build for each of the nine classes")
    for c in classes:
        tree = trees[c]
        for i in range(1, len(builds[c]) + 1):
            b = builds[c][i]
            pts = [b.points[j] for j in range(1, len(b.points) + 1)]
            ok, why = len(pts) == 51, f"{len(pts)} points"
            ranks, spent = {}, {1: 0, 2: 0, 3: 0}
            for j, node in enumerate(pts):
                n = tree.nodes[node]
                if n is None:
                    ok, why = False, f"node {node} isn't in the tree"
                    break
                tab, row, maxr, need = n[3], n[4], n[2], n[6]
                if spent[tab] < (row - 1) * 5:
                    ok, why = False, f"level {10 + j}: row {row} with {spent[tab]} points in the tab"
                    break
                if need and ranks.get(need, 0) < tree.nodes[need][2]:
                    ok, why = False, f"level {10 + j}: a talent before the one it needs is full"
                    break
                ranks[node] = ranks.get(node, 0) + 1
                if ranks[node] > maxr:
                    ok, why = False, "a talent past its ranks"
                    break
                spent[tab] += 1
            check(ok, f"class {c}, {b.name}: as the game's rules allow ({why})")

    # following the warrior's levelling build
    warrior = builds[1][1]
    first, second = warrior.points[1], warrior.points[4]
    check(YR.TalentFollowed() is None and len(YR.TalentNextLines(1)) == 0, "no build followed: nothing to say")
    YR.TalentFollow(warrior.key)
    check(g.YippSetupCharDB.talentBuild == warrior.key, "followed: written down for this character")
    lines = YR.TalentNextLines(2)
    check(len(lines) == 2 and lines[1] == "Improved Heroic Strike 1/3" and lines[2] == "Improved Heroic Strike 2/3",
          f"nothing taken: the first two points of the build ({list(lines.values())})")
    lua.execute(f"RANKS[{first}] = 3")
    lines = YR.TalentNextLines(1)
    check(lines[1] == "Improved Rend 1/3", f"three points in Improved Heroic Strike: Improved Rend next ({lines[1]})")
    lua.execute(f"RANKS[{first}] = 0 RANKS[{second}] = 1")
    lines = YR.TalentNextLines(1)
    check(lines[1] == "Improved Heroic Strike 1/3", f"a point taken out of the build's order counts; the first not taken is next ({lines[1]})")
    # the notice says it
    lua.execute("YippRouteDB.remindTalents = true function GetUnspentTalentPoints() return 2 end")
    YR.UnspentTalents = lua.eval("function() return 2 end")
    YR.TalentNotice()
    told = lua.eval("(function() local t = HeadstartTalentNotice.text return t.GetText and t:GetText() or rawget(t, 'words') or rawget(t, 'text') end)()")
    check(told is not None and "next:" in str(told) and "Improved Heroic Strike 1/3" in str(told),
          f"the talent points notice says which talent is next ({told})")
    YR.TalentFollow(None)

    # your own build: the rules, on a small tree made here (node = { spell, ranks, tab, row, column, the node it needs })
    YR.TalentTrees[99] = lua.eval("""{ tabs = { "Alpha", "Beta", "Gamma" }, nodes = {
        [1] = { 100, 2, 1, 1, 1 }, [2] = { 101, 3, 1, 1, 2 }, [3] = { 102, 1, 1, 2, 1, 1 }, [4] = { 103, 5, 1, 1, 3 },
        [5] = { 104, 60, 2, 1, 1 } } }""")
    add = lua.eval("function(YR, c, n) local ok, why = YR.TalentOwnAdd(c, n) return { ok = ok, why = why } end")
    rem = lua.eval("function(YR, c, n) local ok, why = YR.TalentOwnRemove(c, n) return { ok = ok, why = why } end")

    def pts():
        p = YR.TalentOwn(99).points
        return [p[i] for i in range(1, len(p) + 1)]

    own = YR.TalentBuildsOf(99)
    check(len(own) == 1 and own[1].key == "own" and len(own[1].points) == 0, "a class with a tree has your own build, empty at first")
    r = add(YR, 99, 3)
    check(not r.ok and "needs 5 points in Alpha (0 now)" in str(r.why), f"row 2 first: refused, 5 points in the tab before it ({r.why})")
    for n in (1, 2, 2, 2, 4):
        add(YR, 99, n)
    r = add(YR, 99, 3)
    check(pts() == [1, 2, 2, 2, 4] and not r.ok and "Spell 100 at full rank first" in str(r.why),
          f"5 points in the tab, but the talent it needs at 1 of 2: refused ({pts()}, {r.why})")
    add(YR, 99, 1)
    r = add(YR, 99, 3)
    check(r.ok and pts() == [1, 2, 2, 2, 4, 1, 3], f"the talent it needs full: taken ({pts()})")
    r = add(YR, 99, 1)
    check(not r.ok and "all its ranks" in str(r.why), f"a talent past its ranks: refused ({r.why})")
    r = rem(YR, 99, 1)
    check(not r.ok and "Spell 102 needs it" in str(r.why) and len(pts()) == 7, f"a point a later talent needs can't come off ({r.why})")
    r = rem(YR, 99, 3)
    r2 = rem(YR, 99, 1)
    check(r.ok and r2.ok and pts() == [1, 2, 2, 2, 4], f"the later one off first, then the one it needed ({pts()})")
    check(len(g.YippRouteDB.talentPlans[99]) == 5, "kept for the account, in YippRouteDB.talentPlans")
    YR.TalentOwnSet(99, lua.eval("{ 999, 4, 3, 4 }"))
    check(pts() == [4, 4], f"a talent not in the tree, and one the rules no longer allow there, are left out ({pts()})")
    YR.TalentOwnSet(99, lua.table(*([5] * 51)))
    r = add(YR, 99, 4)
    check(len(pts()) == 51 and not r.ok and "all 51 points" in str(r.why), f"51 points and no more ({r.why})")
    YR.TalentTrees[99] = None
    g.YippRouteDB.talentPlans[99] = None

    # ... followed like Headstart's: the notice's next talent is your own build's
    YR.TalentOwnSet(1, lua.table(warrior.points[1], warrior.points[2], warrior.points[3]))
    lua.execute("RANKS = {}")
    YR.TalentFollow("own")
    f = YR.TalentFollowed()
    lines = YR.TalentNextLines(1)
    check(f is not None and f.key == "own" and lines[1] == "Improved Heroic Strike 1/3", f"your own build followed: its first point is next ({lines[1]})")
    YR.TalentFollow(None)
    YR.TalentOwnSet(1, lua.table())
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
