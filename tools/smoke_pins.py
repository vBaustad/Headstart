"""Smoke test of Guides.lua's YR.RxpPinsOnTop (RestedXP's world map pins above the game's quest markers), in Lua 5.1 (lupa).

    python tools/smoke_pins.py      (exit code 1 on any failure)
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
YippRouteDB = { routes = true }
RXP = {}
OTHER = {}
ADDED = {}
LIB = { AddWorldMapIconMap = function(self, ref, icon, map, x, y, flag, level) table.insert(ADDED, { ref = ref, level = level or "default" }) end }
LibStub = setmetatable({}, { __call = function(_, name) return name == "HereBeDragons-Pins-2.0" and LIB or nil end })
LAYERS = { { frameLevelType = "PIN_FRAME_LEVEL_AREA_POI" }, { frameLevelType = "PIN_FRAME_LEVEL_ACTIVE_QUEST" }, { frameLevelType = "PIN_FRAME_LEVEL_TOPMOST" } }
WorldMapFrame = { GetPinFrameLevelsManager = function() return { definitions = LAYERS } end }
function UnitFactionGroup() return "Alliance" end
''')
    YR = lua.table()
    lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, "Guides.lua"), encoding="utf-8").read(), "Guides.lua")("Headstart", YR)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def last():
        return str(g.ADDED[len(g.ADDED)].level)

    YR.RxpPinsOnTop()
    YR.RxpPinsOnTop()                                  # asked twice: wrapped once
    lua.execute("LIB:AddWorldMapIconMap(RXP, {}, 1, 0.5, 0.5)")
    check(len(g.ADDED) == 1 and last() == "PIN_FRAME_LEVEL_ACTIVE_QUEST",
          f"RestedXP's pin goes on the first layer of ours the map knows, above the area POIs: {last()}")
    lua.execute("LIB:AddWorldMapIconMap(OTHER, {}, 1, 0.5, 0.5)")
    check(last() == "default", "another addon's pin is passed on as it is")
    lua.execute('LIB:AddWorldMapIconMap(RXP, {}, 1, 0.5, 0.5, nil, "PIN_FRAME_LEVEL_AREA_POI")')
    check(last() == "PIN_FRAME_LEVEL_AREA_POI", "a layer RestedXP asked for itself is kept")
    lua.execute("YippRouteDB.routes = false; LIB:AddWorldMapIconMap(RXP, {}, 1, 0.5, 0.5)")
    check(last() == "default", "routes off: RestedXP's pins as they were")

    # RxpRewardGuard: RestedXP's own function errors on a hand-in with no reward choice
    lua.execute('''
RXP.questTurnIn = { [19] = { questId = 19 }, [20] = { questId = 20, reward = 2 } }
function RXP.GetStepQuestReward(id)
    local e = RXP.questTurnIn[id]
    if not e then return 0 end
    return (e.reward >= 0 and e.reward or 0), e
end
''')
    YR.RxpRewardGuard()
    YR.RxpRewardGuard()
    reward, element = lua.eval("RXP.GetStepQuestReward(19)")
    check(reward == 0 and element is not None, "a hand-in with no reward choice: 0 and its step, no error")
    check(lua.eval("RXP.GetStepQuestReward(20)")[0] == 2, "a hand-in with a choice is RestedXP's answer")
    check(lua.eval("RXP.GetStepQuestReward(7)") == 0 and lua.eval("RXP.GetStepQuestReward(nil)") == 0,
          "a quest no step hands in, and no quest: RestedXP's answer")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
