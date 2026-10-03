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
-- a long stretch of kills: a grind
for i = 1, 10 do EV[#EV + 1] = E(20 + i * 20, "kill", nil, 2, 100 + i * 50, 23, 70) end
EV[#EV + 1] = E(240, "complete", 183, 2, 600, 22.6, 71.2)
EV[#EV + 1] = E(300, "turnin", 183, 2, 600, 22.6, 71.3, { npc = "Talin Keeneye", xp = 250 })
EV[#EV + 1] = E(301, "complete", 183, 2, 850, 22.6, 71.3)                       -- noted again: no step
EV[#EV + 1] = E(302, "accept", 182, 2, 850, 22.6, 71.3, { title = "The Troll Cave", obj = 1 })   -- no npc noted
EV[#EV + 1] = E(400, "trainer", nil, 2, 850, 28.9, 68.3, { npc = "Bromos Grummner" })
EV[#EV + 1] = E(401, "learn", nil, 2, 850, 28.9, 68.3, { name = "Judgement" })
EV[#EV + 1] = E(401, "learn", nil, 2, 850, 28.9, 68.3, { name = "Judgement" })
EV[#EV + 1] = E(500, "death", nil, 3, 900, 30.2, 79.8)
EV[#EV + 1] = E(510, "alive", nil, 3, 900, 47.1, 55.0)
EV[#EV + 1] = E(600, "flight", nil, 3, 900, 33.9, 50.7, { npc = "Thorgrum Borrelson" })
EV[#EV + 1] = E(640, "zone", nil, 3, 900, 0, 0, { zone = "Ironforge" })
'''


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(RUN)
    lua.execute(r'''
YippRouteDB = { runs = { ["Tester-Realm"] = { ev = EV } }, custom = {} }
StaticPopupDialogs = {}
SHIPPED = {}
function UnitFactionGroup() return "Alliance" end
''')
    YR = lua.table()
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

    steps = [str(s) for s in YR.RunToSteps("Tester-Realm").values()]
    text = "\n".join(steps)
    check(steps[0].count(".accept 183") == 1 and "Talin Keeneye" in steps[0], "a quest taken: its step, at the NPC")
    check(any(".xp 2+600 >> Grind here" in s for s in steps), "ten kills over three minutes: a grind step, to the XP after them")
    check(sum(".complete 183,1" in s for s in steps) == 1, "the objective finished once, not again after the hand-in")
    hand = next((s for s in steps if ".turnin 183" in s), "")
    check(".accept 182" in hand, "a quest taken right after a hand-in, no NPC noted: the same stop")
    check(any(".trainer >> Train: Judgement\n" in s + "\n" and s.count("Judgement") == 1 for s in steps),
          "a trainer: what you learned, once")
    check(any(".deathskip" in s for s in steps), "a death you came back from elsewhere: a death skip")
    check(any(".fly Ironforge" in s for s in steps), "a flight: to where you landed")
    check(".zone " not in text.split(".fly")[0], "no travel step inside one zone")

    n, name = YR.SaveRunAsRoute(None)
    saved = g.YippRouteDB.myRoutes["Tester-Realm"]
    check(n == len(steps) and "#subgroup My routes" in str(saved.text) and "My route (Tester)" in str(name),
          f"saved as the character's own route: {name}, {n} steps")
    check(list(g.SHIPPED.values()) == ["my_Tester-Realm"], "and handed on like our routes")
    g.YippRouteDB.custom["my_Tester-Realm"] = lua.eval("{ text = 'edited' }")
    YR.SaveRunAsRoute(None)
    check(g.YippRouteDB.custom["my_Tester-Realm"] is None and len(g.SHIPPED) == 1,
          "saving again replaces it and your edits to it (and it isn't listed twice)")
    check(YR.IsMyRoute("my_Tester-Realm") and not YR.IsMyRoute("dunmorogh"), "own routes are told apart from ours")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
