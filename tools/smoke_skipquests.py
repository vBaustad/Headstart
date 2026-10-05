"""Smoke test of SkipQuests.lua (a quest the route skips, dropped when another addon accepted it), in Lua 5.1 (lupa).

    python tools/smoke_skipquests.py      (exit code 1 on any failure)
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
NOW, QID, ROUTES = 0, 0, true
HeadstartSkipQuests = { [99162] = "Treacherous Cold" }      -- the routes addon's list
LOG, ABANDONED, PRINTS = {}, {}, {}
function GetTime() return NOW end
function GetQuestID() return QID end
C_Timer = { After = function(_, f) f() end }
local selected
C_QuestLog = {
    GetLogIndexForQuestID = function(id) return LOG[id] end,
    SetSelectedQuest = function(id) selected = id end,
    SetAbandonQuest = function() end,
    AbandonQuest = function() table.insert(ABANDONED, selected); LOG[selected] = nil end,
}
local handler
function CreateFrame()
    return { RegisterEvent = function() end, SetScript = function(_, _, f) handler = f end }
end
function FIRE(event, a, b) handler(nil, event, a, b) end
function OFFER(id, wait)                 -- the quest window opens; accepted `wait` seconds later
    QID = id
    FIRE("QUEST_DETAIL")
    NOW = NOW + wait
    LOG[id] = 1
    FIRE("QUEST_ACCEPTED", id)
    NOW = NOW + 60
end
''')
    YR = lua.table()
    YR.RoutesOn = lua.eval("function() return ROUTES end")
    YR.Print = lua.eval("function(msg) table.insert(PRINTS, msg) end")
    chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, "SkipQuests.lua"), encoding="utf-8").read(), "SkipQuests.lua")
    chunk("Headstart", YR)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def dropped():
        return list(g.ABANDONED.values())

    g.OFFER(99160, 0)
    check(dropped() == [], "a route quest accepted at once is kept")
    g.OFFER(99162, 3)
    check(dropped() == [], "Treacherous Cold read and accepted by hand is kept")
    g.LOG[99162] = None
    g.OFFER(99162, 0)
    check(dropped() == [99162] and "Treacherous Cold" in str(g.PRINTS[1]),
          "Treacherous Cold accepted the moment it opened (another addon) is dropped, and said so")
    g.OFFER(99162, 0)
    check(dropped() == [99162], "taken again: kept, whatever accepted it")
    lua.execute("ROUTES = false")
    lua.execute("ABANDONED = {}")
    chunk("Headstart", YR)
    g.OFFER(99162, 0)
    check(len(g.ABANDONED) == 0, "routes off: left alone")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
