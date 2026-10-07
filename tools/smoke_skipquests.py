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
-- frames that hear only what they registered for: SkipQuests is a part (Core.lua's YR.Part), with a
-- frame and events only while the routes and its option are on
FRAMES = {}
local F = {}
F.__index = F
function F:RegisterEvent(e) self.ev = self.ev or {} self.ev[e] = true end
function F:UnregisterEvent(e) if self.ev then self.ev[e] = nil end end
function F:UnregisterAllEvents() self.ev = nil end
function F:SetScript(_, fn) self.fn = fn end
function CreateFrame() local f = setmetatable({}, F) table.insert(FRAMES, f) return f end
function FIRE(event, a, b) for _, f in ipairs(FRAMES) do if f.ev and f.ev[event] and f.fn then f.fn(f, event, a, b) end end end
SlashCmdList = {}
YippRouteDB = {}
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
    load = lua.eval("function(c, n) return assert(loadstring(c, n)) end")
    load(open(os.path.join(ROOT, "Core.lua"), encoding="utf-8").read(), "Core.lua")("Headstart", YR)
    YR.RoutesOn = lua.eval("function() return ROUTES end")
    YR.Print = lua.eval("function(msg) table.insert(PRINTS, msg) end")
    lua.execute("OPTION = true")
    YR.Option = lua.eval("function(key) return key == 'skipQuests' and OPTION end")
    source = load(open(os.path.join(ROOT, "SkipQuests.lua"), encoding="utf-8").read(), "SkipQuests.lua")
    YR.partsReady = True             # the login: what is wanted comes on

    def chunk(*args):                # the file loaded (again), and the login after it
        source(*args)
        YR.ApplyParts()

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
    lua.execute("ROUTES = true; OPTION = false")
    chunk("Headstart", YR)
    g.OFFER(99162, 0)
    check(len(g.ABANDONED) == 0, "the option off: left alone")
    lua.execute("HeadstartSkipQuests = nil; FRAMES_MADE = 0; local make = CreateFrame; CreateFrame = function(...) FRAMES_MADE = FRAMES_MADE + 1 return make(...) end")
    chunk("Headstart", YR)
    check(g.FRAMES_MADE == 0, "no routes addon, no list: it listens to nothing")
    listening = lua.eval("function() local n = 0 for _, f in ipairs(FRAMES) do if f.ev and (f.ev.QUEST_DETAIL or f.ev.QUEST_ACCEPTED) then n = n + 1 end end return n end")
    check(listening() == 0, "and with the routes or the option off, no quest event is listened for")
    lua.execute("OPTION = true")
    YR.ApplyParts()
    check(listening() > 0, "the option back on: listening again, without a /reload")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
