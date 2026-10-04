"""Smoke test of MyRoutes.lua (a recorded run saved as the player's own route), in Lua 5.1 (lupa).

    python tools/smoke_myroutes.py      (exit code 1 on any failure)
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# a small run: { time, kind, quest, level, xp, map, x, y } plus named fields, as Log.lua writes them
RUN = r'''
local M = 1426
local function E(t, kind, q, lvl, xp, x, y, extra)
    local e = { t, kind, q, lvl, xp, M, x, y }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end
EV = {
    E(0, "zone", nil, 1, 0, 30, 72, { zone = "Dun Morogh" }),
    E(10, "accept", 183, 1, 0, 22.7, 71.3, { npc = "Talin Keeneye", title = "The Boar Hunter", obj = 1 }),
}
-- the boars for the quest, then its objective done: quest work, no grind
for i = 1, 10 do EV[#EV + 1] = E(20 + i * 20, "kill", nil, 2, 100 + i * 50, 23, 70) end
EV[#EV + 1] = E(240, "complete", 183, 2, 600, 22.6, 71.2)
EV[#EV + 1] = E(300, "turnin", 183, 2, 600, 22.6, 71.3, { npc = "Talin Keeneye", xp = 250 })
EV[#EV + 1] = E(301, "complete", 183, 2, 850, 22.6, 71.3)                       -- noted again: no step
EV[#EV + 1] = E(302, "accept", 182, 2, 850, 22.6, 71.3, { title = "The Troll Cave", obj = 1 })   -- no npc noted
-- killing along the way to the trainer: no step
for i = 1, 10 do EV[#EV + 1] = E(302 + i * 3, "kill", nil, 2, 850, 22 + i, 70 - i) end
-- a long stretch of kills in one spot, nothing else: a grind
for i = 1, 10 do EV[#EV + 1] = E(340 + i * 2, "kill", nil, 2, 850 + i * 10, 30, 70) end
for i = 1, 10 do EV[#EV + 1] = E(360 + i * 20, "kill", nil, 2, 950 + i * 10, 30.5, 70.5) end
EV[#EV + 1] = E(600, "trainer", nil, 2, 1050, 28.9, 68.3, { npc = "Bromos Grummner" })
EV[#EV + 1] = E(601, "learn", nil, 2, 850, 28.9, 68.3, { name = "Judgement" })
EV[#EV + 1] = E(601, "learn", nil, 2, 850, 28.9, 68.3, { name = "Judgement" })
EV[#EV + 1] = E(700, "death", nil, 3, 900, 30.2, 79.8)
EV[#EV + 1] = E(710, "alive", nil, 3, 900, 47.1, 55.0)
EV[#EV + 1] = E(800, "flight", nil, 3, 900, 33.9, 50.7, { npc = "Thorgrum Borrelson" })
EV[#EV + 1] = E(840, "zone", nil, 3, 900, 0, 0, { zone = "Ironforge" })
'''


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(RUN)
    lua.execute(r'''
YippRouteDB = { runs = { ["Tester-Realm"] = { ev = EV } }, custom = {} }
StaticPopupDialogs = {}
SHIPPED = {}
function UnitFactionGroup() return "Alliance" end
RACE = "Dwarf"
function UnitRace() return RACE, RACE end
''')
    YR = lua.table()
    YR.shipped = lua.table()
    YR.CharKey = lua.eval("function() return 'Tester-Realm' end")
    YR.ShipGuide = lua.eval("function(self, key, text) table.insert(SHIPPED, key) end")
    chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, "MyRoutes.lua"), encoding="utf-8").read(), "MyRoutes.lua")
    chunk("Headstart", YR)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    steps = [str(s.text) for s in YR.RunToSteps("Tester-Realm").values()]
    text = "\n".join(steps)
    check(steps[0].count(".accept 183") == 1 and "Talin Keeneye" in steps[0], "a quest taken: its step, at the NPC")
    grinds = [s for s in steps if "Grind here" in s]
    check(len(grinds) == 1 and ".xp 2+1050" in grinds[0] and "30.00,70.00" in grinds[0],
          f"only the stretch of kills in one spot is a grind (not the quest's boars, not those on the way): {grinds}")
    check(sum(".complete 183,1" in s for s in steps) == 1, "the objective finished once, not again after the hand-in")
    hand = next((s for s in steps if ".turnin 183" in s), "")
    check(".accept 182" in hand, "a quest taken right after a hand-in, no NPC noted: the same stop")
    check(any(".trainer >> Train: Judgement\n" in s + "\n" and s.count("Judgement") == 1 for s in steps),
          "a trainer: what you learned, once")
    check(any(".deathskip" in s for s in steps), "a death you came back from elsewhere: a death skip")
    check(any(".fly Ironforge" in s for s in steps), "a flight: to where you landed")
    check(".zone " not in text.split(".fly")[0], "no travel step inside one zone")

    n, parts, first, label = YR.SaveRunAsRoute(None)
    saved = g.YippRouteDB.myRoutes["dwarfgnome"]
    text = str(saved.parts[1].text)
    check(n == len(steps) and parts == 1 and "#subgroup My routes" in text and "<< Alliance Dwarf/Gnome" in text
          and "Tester" not in str(first) and "My route: Dun Morogh (Dwarf/Gnome)" in str(first),
          f"saved for the race, not the character: {first}, {n} steps")
    check(list(g.SHIPPED.values()) == ["my_dwarfgnome_1"], "and handed on like our routes")
    g.YippRouteDB.custom["my_dwarfgnome_1"] = lua.eval("{ text = 'edited' }")
    lua.execute('RACE = "Gnome"')
    YR.SaveRunAsRoute(None)
    check(g.YippRouteDB.custom["my_dwarfgnome_1"] is None and len(g.SHIPPED) == 1,
          "a Gnome saving again replaces the Dwarf/Gnome set and your edits to it (not listed twice)")
    lua.execute('RACE = "NightElf"')
    YR.SaveRunAsRoute(None)
    check(g.YippRouteDB.myRoutes["dwarfgnome"] is not None and g.YippRouteDB.myRoutes["nightelf"] is not None,
          "a Night Elf gets its own set; the Dwarf/Gnome one stays")
    check(YR.MyRouteFor("my_dwarfgnome_1", "Gnome") and not YR.MyRouteFor("my_nightelf_1", "Dwarf")
          and not YR.MyRouteFor("dunmorogh", "Dwarf"), "each race sees its own set")

    # one part per zone: a city on the way stays in the part around it, a short visit too
    recs = lua.eval("""{
        { zone = "Dun Morogh", t = 0, level = 1 }, { zone = "Dun Morogh", t = 100, level = 3 },
        { zone = "Dun Morogh", t = 200, level = 5 }, { zone = "Dun Morogh", t = 300, level = 6 },
        { zone = "Dun Morogh", t = 400, level = 7 }, { zone = "Dun Morogh", t = 500, level = 8 },
        { zone = "Ironforge", t = 600, level = 11 }, { zone = "Ironforge", t = 660, level = 11 },
        { zone = "Loch Modan", t = 900, level = 11 }, { zone = "Loch Modan", t = 1000, level = 12 },
        { zone = "Loch Modan", t = 1100, level = 12 }, { zone = "Loch Modan", t = 1200, level = 13 },
        { zone = "Loch Modan", t = 1300, level = 13 }, { zone = "Loch Modan", t = 1400, level = 14 },
        { zone = "Dun Morogh", t = 1500, level = 14 }, { zone = "Dun Morogh", t = 1520, level = 14 },
        { zone = "Loch Modan", t = 1600, level = 14 },
    }""")
    split = YR.SplitByZone(recs)
    zones = [(str(p.zone), len(p.steps)) for p in split.values()]
    check(zones == [("Dun Morogh", 8), ("Loch Modan", 9)],
          f"Dun Morogh (Ironforge in it), then Loch Modan (a short way back through Dun Morogh in it): {zones}")
    # a run that followed one of our routes: our steps as written, in the order played, without the
    # ones skipped; what our route doesn't have, made from the log
    lua.execute(r"""
ROUTE = { "step\n    .goto 1426,22.6,71.3\n    .accept 183 >> Accept The Boar Hunter",
          "step\n    #label Boars\n    .complete 183,1\n    .mob Small Crag Boar",
          "step\n    .xp 2+500 >> Grind to 500 XP",
          "step\n    #requires Gone\n    .accept 999 >> Accept something skipped",
          "step\n    #completewith Gone\n    .turnin 183 >> Turn in The Boar Hunter" }
YippRouteDB.runs["Follow-Realm"] = { ev = {
    { 0, "zone", nil, 1, 0, 1426, 22, 71, zone = "Dun Morogh" },
    { 1, "step", nil, 1, 0, 1426, 22, 71, guide = "01-05 Coldridge Valley (Launch)", step = 1 },
    { 10, "accept", 183, 1, 0, 1426, 22.6, 71.3, npc = "Talin Keeneye", title = "The Boar Hunter", obj = 1 },
    { 100, "step", nil, 2, 0, 1426, 23, 70, guide = "01-05 Coldridge Valley (Launch)", step = 5 },
    { 200, "complete", 183, 2, 600, 1426, 22.6, 71.2 },
    { 300, "turnin", 183, 2, 600, 1426, 22.6, 71.3, npc = "Talin Keeneye" },
    { 400, "accept", 182, 2, 850, 1426, 25, 75, npc = "Grelin Whitebeard", title = "The Troll Cave", obj = 1 },
} }
""")
    YR.shipped = lua.eval('{ { key = "coldridge", text = "" } }')
    YR.GuideName = lua.eval('function(key) return "1-5 Coldridge Valley (Launch)" end')
    YR.CharSteps = lua.eval('function(key) return ROUTE end')
    routed = [str(r.text) for r in YR.RunToRouteSteps("Follow-Realm").values()]
    check(len(routed) == 5 and routed[0] == str(g.ROUTE[1]) and routed[2] == str(g.ROUTE[3]),
          f"our steps as written, in order: {len(routed)}")
    check(not any("999" in t for t in routed), "a step whose quest you never did is left out")
    check("#completewith next" in routed[3] and "#requires" not in "".join(routed),
          "labels that point at a step left out: #completewith becomes next, #requires goes")
    check(".accept 182" in routed[4] and "Grelin Whitebeard" in routed[4], "a quest our route hasn't: made from the log")

    lua.execute('RACE = "Dwarf"')
    gone = YR.DeleteMyRoutes(None)
    check(gone == 1 and g.YippRouteDB.myRoutes["dwarfgnome"] is None and g.YippRouteDB.myRoutes["nightelf"] is not None,
          "delete: this race's route goes, the others stay")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
