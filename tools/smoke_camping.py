"""Smoke test of the Camping 101 reminder (CampingReminder.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_camping.py      (exit code 1 on any failure)
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
FRAMES = {}
local F = {}
F.__index = F
function F:RegisterEvent(e) self.ev = self.ev or {} self.ev[e] = true end
function F:SetScript(_, fn) self.fn = fn end
function CreateFrame() local f = setmetatable({}, F) table.insert(FRAMES, f) return f end
function Fire(e) for _, f in ipairs(FRAMES) do if f.ev and f.ev[e] and f.fn then f.fn(f, e) end end end
C_Timer = { After = function(_, fn) fn() end }
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
floor = math.floor
YippRouteDB = {}
PRINTS, NOTICES = {}, {}
function print(m) table.insert(PRINTS, m) end
RaidWarningFrame, ChatTypeInfo = {}, { RAID_WARNING = {} }
function RaidNotice_AddMessage(_, m) table.insert(NOTICES, m) end
ONQUEST, COMPLETE, BAGS, SKILLS, SUBZONE = {}, {}, {}, {}, ""
C_QuestLog = { IsOnQuest = function(q) return ONQUEST[q] == true end, IsComplete = function(q) return COMPLETE[q] == true end }
C_Item = { GetItemCount = function(i) return BAGS[i] or 0 end }
function GetNumSkillLines() return #SKILLS end
function GetSkillLineInfo(i) return SKILLS[i][1], false, false, SKILLS[i][2] end
function GetSubZoneText() return SUBZONE end
''')
    YR = lua.table()
    for f in ("Core.lua", "CampingReminder.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def said():
        return [str(g.PRINTS[i]) for i in range(1, len(g.PRINTS) + 1)]

    bars, stones = YR.CampingNeed(1)
    check((bars, stones) == (19, 5), f"from 1 to 20: 19 bars and 5 stones: {(bars, stones)}")
    check(tuple(YR.CampingNeed(12)) == (10, 3), f"from 12: no rods, 3 stones, 5 bracers: {tuple(YR.CampingNeed(12))}")

    lua.execute("ONQUEST[96044] = true; SKILLS = { { 'Blacksmithing', 5 } }; BAGS = { [2770] = 10, [2835] = 5 }")
    lua.execute("Fire('BAG_UPDATE_DELAYED')")
    check(len(said()) == 0, "10 ore at skill 5 (needs 15 bars): nothing said")
    lua.execute("BAGS[2840] = 5; Fire('BAG_UPDATE_DELAYED')")
    check(len(said()) == 1 and "Blacksmithing 20" in said()[0] and len(g.NOTICES) == 1,
          f"10 ore + 5 bars + 5 stones: told, in chat and on screen: {said()}")
    lua.execute("Fire('BAG_UPDATE_DELAYED')")
    check(len(said()) == 1, "told once")
    lua.execute("SUBZONE = 'Kharanos'; Fire('ZONE_CHANGED')")
    check(len(said()) == 2, "told again coming into Kharanos")
    lua.execute("PRINTS = {}; SUBZONE = 'Thelsamar'; Fire('ZONE_CHANGED')")
    check(len(said()) == 1 and "by the inn" in said()[0] and "Tognus Flintfire in Kharanos" in said()[0],
          f"in Thelsamar: the forge there, the hand-in in Kharanos: {said()}")
    lua.execute("SUBZONE = 'Kharanos'")
    lua.execute("SKILLS = {}; PRINTS = {}; BAGS[2840] = 10")      # untrained: from 1, 19 bars
    check("train Blacksmithing" in YR.CampingNow()[1][2], "not trained yet: says to train it first")
    lua.execute("ONQUEST[96044] = false; ONQUEST[96046] = true; COMPLETE[96046] = true; PRINTS = {}; Fire('QUEST_LOG_UPDATE')")
    check(any("Yarr Hammerstone" in x for x in said()), f"Mining done: told where to hand it in: {said()}")
    lua.execute("YippRouteDB.campReminder = false; PRINTS = {}; SUBZONE = 'Kharanos'; Fire('ZONE_CHANGED')")
    check(len(said()) == 0, "turned off: nothing")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
