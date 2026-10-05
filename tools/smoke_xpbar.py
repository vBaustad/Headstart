"""Smoke test of the XP bar (XPBar.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_xpbar.py      (exit code 1 on any failure; tools/smoke.py runs it too)

The words: {tokens} filled in, unknown ones left; the kills to ding from the last kills' XP, not from a
quest hand-in; time to ding from XP an hour. Blizzard's bar invisible while ours shows, and back.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
FRAMES = {}
local Obj = {}
Obj.__index = function(t, k)
    local v = rawget(Obj, k)
    if v then return v end
    return function() return setmetatable({}, Obj) end
end
function Obj:SetAlpha(a) rawset(self, "alpha", a) end
function Obj:GetAlpha() return rawget(self, "alpha") or 1 end
function Obj:SetShown(on) rawset(self, "shown", on) end
function Obj:IsShown() return rawget(self, "shown") ~= false end
function Obj:IsMouseOver() return false end
function Obj:SetText(t) rawset(self, "text", t) end
function Obj:RegisterEvent(e) rawset(self, "ev", rawget(self, "ev") or {}) self.ev[e] = true end
function Obj:SetScript(w, fn) rawset(self, "_" .. w, fn) end
function Obj:CreateTexture() return setmetatable({}, Obj) end
function Obj:CreateFontString() return setmetatable({}, Obj) end
function CreateFrame() local f = setmetatable({}, Obj) table.insert(FRAMES, f) return f end
function Fire(e, ...) for _, f in ipairs(FRAMES) do if rawget(f, "ev") and f.ev[e] and rawget(f, "_OnEvent") then f._OnEvent(f, e, ...) end end end
UIParent = CreateFrame()
MainStatusTrackingBarContainer = CreateFrame()
SecondaryStatusTrackingBarContainer = CreateFrame()
C_Timer = { After = function(_, fn) end, NewTicker = function(_, fn) TICK = fn return {} end }
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
floor = math.floor
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
YippRouteDB = {}
NOW = 1000
function GetTime() return NOW end
XP, XPMAX, LEVEL, RESTED = 1000, 4000, 18, 600
function UnitXP() return XP end
function UnitXPMax() return XPMAX end
function UnitLevel() return LEVEL end
function GetXPExhaustion() return RESTED end
function GetMaxPlayerLevel() return 60 end
QUESTS = { { questID = 11, done = true, xp = 400 }, { isHeader = true }, { questID = 12, done = false, xp = 900 },
    { questID = 13, done = true, xp = 200 } }
C_QuestLog = {
    GetNumQuestLogEntries = function() return #QUESTS end,
    GetInfo = function(i) return QUESTS[i] end,
    IsComplete = function(id) for _, q in ipairs(QUESTS) do if q.questID == id then return q.done end end end,
}
function GetQuestLogRewardXP(id) for _, q in ipairs(QUESTS) do if q.questID == id then return q.xp end end end
function InCombatLockdown() return false end
function print() end
''')
    YR = lua.table()
    lua.execute("STYLE = { FONT = 'x', C = {} } function STYLE.Border() end")
    YR.Style = lua.eval("STYLE")
    for f in ("Core.lua", "XPBar.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    YR.Style = lua.eval("STYLE")
    YR.SplitsXPRate = lua.eval("function() return 6000 end")
    YR.SplitsPlayed = lua.eval("function() return 7200, 900 end")
    YR.StartXPBar()
    g = lua.globals()
    g.XPBARVALUES = YR.XPBarValues
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    f = YR.XPBarFormat
    db = YR.XPBarDB()
    check(db.left == "Level {level}" and db.center == "{xp} / {max}" and db.right == "{pct}%" and db.under is True
          and db.left2 == "Time to Level: {ding}", "the first words: level, XP, percent, and a line under the bar")
    check(f("{quest} {questpct} {quests}") == "600 15.0 2",
          f"quests done and not handed in: 600 XP, 15.0% of the level, 2 of them ({f('{quest} {questpct} {quests}')})")
    check(f("{rate}") == "6.0k", f"XP an hour, short ({f('{rate}')})")
    check(f("Level {level}: {xp} / {max} ({pct}%)") == "Level 18: 1000 / 4000 (25.0%)",
          f"tokens filled in: {f('Level {level}: {xp} / {max} ({pct}%)')}")
    check(f("{nonsense} stays") == "{nonsense} stays", "an unknown token is left as written")
    check(f("{ding}") == "30m 00s", f"time to ding: 3000 left at 6000 an hour ({f('{ding}')})")
    check(f("{played} / {levelplayed}") == "2h 0m / 15m 00s", f"played time: {f('{played} / {levelplayed}')}")
    check(f("{rested}") == "600 rested" and f("{restedpct}") == "15%", "rested, and as a share of the level")
    # kills: XP with no quest handed in just before; the quest's XP doesn't count
    lua.execute("Fire('PLAYER_ENTERING_WORLD')")
    lua.execute("XP = 1100 Fire('PLAYER_XP_UPDATE') XP = 1200 Fire('PLAYER_XP_UPDATE')")
    lua.execute("Fire('QUEST_TURNED_IN') XP = 2200 Fire('PLAYER_XP_UPDATE')")
    check(f("{kill} {mobs}") == "100 18", f"two kills of 100 (the quest's 1000 left out): 1800 left is 18 kills ({f('{kill} {mobs}')})")
    # Blizzard's bar: invisible while ours shows, back when ours is off
    check(g.MainStatusTrackingBarContainer.alpha == 0, "Blizzard's bar invisible while ours shows")
    # Blizzard shows its bar again by itself (it does after a reload): out of sight again within a second
    lua.execute("MainStatusTrackingBarContainer:SetAlpha(1) TICK()")
    check(g.MainStatusTrackingBarContainer.alpha == 0, "Blizzard put its bar back: hidden again at the next tick")
    YR.XPBarDB().on = False
    YR.XPBarApply()
    check(g.MainStatusTrackingBarContainer.alpha == 1, "ours off: Blizzard's is back")
    YR.XPBarDB().on = True
    YR.XPBarDB().hideBlizz = False
    YR.XPBarApply()
    check(g.MainStatusTrackingBarContainer.alpha == 1, "'Hide Blizzard's bar' off: both show")
    # the quest log: a quest finished shows up at once; one the game hasn't loaded yet (0 XP) is asked
    # for and counted when its XP is there, with no event needed
    lua.execute("NOW = NOW + 0.6 QUESTS[3].done = true Fire('QUEST_LOG_UPDATE')")
    check(f("{quest} {quests}") == "1.5k 3", f"a third quest done: 1500 XP, 3 quests ({f('{quest} {quests}')})")
    lua.execute("ASKED = 0 C_QuestLog.RequestLoadQuestByID = function() ASKED = ASKED + 1 end QUESTS[1].xp = 0 NOW = NOW + 0.6 Fire('QUEST_LOG_UPDATE')")
    check(f("{quest}") == "1.1k" and g.ASKED == 1, f"a quest not loaded yet: left out for now, and asked for ({f('{quest}')})")
    lua.execute("QUESTS[1].xp = 400 NOW = NOW + 1.5")
    check(f("{quest}") == "1.5k", f"its XP arrives: counted a second later, without an event ({f('{quest}')})")
    lua.execute("QUESTS[3].done = false NOW = NOW + 3")
    check(f("{quest} {quests}") == "1.5k 3", "no event, three seconds on: the log isn't read again (it's not read every second)")
    lua.execute("NOW = NOW + 8")
    check(f("{quest} {quests}") == "600 2", "but a change the events missed is picked up by the ten-second net")
    lua.execute("READS = 0 local get = C_QuestLog.GetNumQuestLogEntries C_QuestLog.GetNumQuestLogEntries = function() READS = READS + 1 return get() end")
    lua.execute("for i = 1, 20 do Fire('QUEST_LOG_UPDATE') XPBARVALUES() end")
    check(g.READS <= 1, f"twenty log events in one moment: the log is read once, not twenty times ({g.READS})")
    check(f("{XP} {Level}") == f("{xp} {level}"), "a token is found whatever its case")
    # EllesmereUI: where it does the same job, ours starts off - until you set it yourself
    lua.execute("LOADED = {} ASKS = 0 C_AddOns = { IsAddOnLoaded = function(n) ASKS = ASKS + 1 return LOADED[n] == true end }")
    YR.EllesmereForget()
    g.YippRouteDB.xpbar.on = None
    check(YR.XPBarOn() and YR.Option("flightTimer") and YR.Option("durability"), "no EllesmereUI: ours on as always")
    asked = g.ASKS
    for _ in range(50):
        YR.XPBarOn()
    check(g.ASKS == asked, "asked fifty times more: the client isn't asked again until an addon loads")
    lua.execute("LOADED.EllesmereUIActionBars = true LOADED.EllesmereUIForeverEssentials = true")
    YR.EllesmereForget()
    check(not YR.XPBarOn() and not YR.Option("flightTimer"), "its Action Bars and Forever Essentials loaded: our XP bar and flight timer start off")
    check(YR.Option("durability") and YR.Option("camp"), "what it doesn't do here (its QoL isn't loaded; it has no camp HUD) stays on")
    g.YippRouteDB.flightTimer = True
    g.YippRouteDB.xpbar.on = True
    check(YR.XPBarOn() and YR.Option("flightTimer"), "turned on by you: on, EllesmereUI or not")
    g.YippRouteDB.flightTimer = None
    lua.execute("LOADED = {}")
    YR.EllesmereForget()
    # the main switch: quality of life off takes the bar away (and Blizzard's is back), on brings it back
    YR.XPBarDB().hideBlizz = True
    YR.SetQoLOn(False)
    check(g.MainStatusTrackingBarContainer.alpha == 1 and not YR.Option("camp") and YR.Option("minimapButton"),
          "quality of life off: our bar gone, Blizzard's back, QoL options answer off, the window's own still on")
    check(g.YippRouteDB.camp is None, "and your own settings aren't touched by it")
    YR.SetQoLOn(True)
    check(g.MainStatusTrackingBarContainer.alpha == 0 and YR.Option("camp"), "on again: all back")
    # the look before this one, untouched by you, takes the new one; what you changed stays
    g.YippRouteDB.xpbar = lua.eval("{ h = 14, font = 11, left = 'mine', xpColor = { 0.58, 0.0, 0.55, 1 } }")
    db = YR.XPBarDB()
    check(db.h == 22 and db.font == 13 and abs(db.xpColor[1] - 0.09) < 0.01, f"old first values take the new look ({db.h}, {db.font})")
    check(db.left == "mine", "words you wrote yourself are kept")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
