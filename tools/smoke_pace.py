"""Smoke test of Level pace (Pace.lua) in Lua 5.1 (lupa).

    python tools/smoke_pace.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Fake XP and kill events against a fake clock: the pace and the time to level, time away and dead left
out of it, the grind rate from kills near here (and not from kills far off), a step that trips the
watchdog, one that doesn't, two deaths on a step, the line said once, in chat only when the guide window
is hidden, a level gate ahead, and nothing made or left running while it is off.
"""
import os
import re
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r'''
NOW = 1000
AFK, DEAD, INSIDE = false, false, false
X, Y, WHERE, SUB = 0, 0, 1, "Lake Al'Ameth"
LEVEL, XP, XPMAX = 8, 0, 5000
function GetTime() return NOW end
function UnitIsAFK() return AFK end
function UnitIsDeadOrGhost() return DEAD end
function IsInInstance() return INSIDE end
function UnitPosition() return Y, X, 0, WHERE end
function GetSubZoneText() return SUB end
function UnitLevel() return LEVEL end
function UnitXP() return XP end
function UnitXPMax() return XPMAX end
function GetMaxPlayerLevel() return 60 end
function issecretvalue() return false end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
INLOG, REWARD, TITLE = {}, {}, {}
C_QuestLog = {
    GetLogIndexForQuestID = function(q) return INLOG[q] end,
    GetTitleForQuestID = function(q) return TITLE[q] end,
}
function GetQuestLogRewardXP(q) return REWARD[q] or 0 end
-- frames: what is set can be read back
local F = {}
F.__index = function(t, k) return rawget(F, k) or function() end end
function F:CreateFontString() return setmetatable({}, F) end
function F:Show() rawset(self, "shown", true) end
function F:Hide() rawset(self, "shown", false) end
function F:SetShown(on) rawset(self, "shown", on and true or false) end
function F:IsShown() return rawget(self, "shown") ~= false end
function F:SetText(t) rawset(self, "words", t) rawset(self, "sets", (rawget(self, "sets") or 0) + 1) end
function F:SetPoint(a, to) rawset(self, "anchor", to) end
MADE = 0
function CreateFrame(kind, name) MADE = MADE + 1 local f = setmetatable({}, F) if name then _G[name] = f end return f end
UIParent = setmetatable({}, F)
GUIDE = setmetatable({}, F)
RXP = { RXPFrame = GUIDE }
RXPCData = { currentStep = 1 }
SAID = {}
DB = {}
PART = nil
YR = {
    Open = function(v) return v end,
    Print = function(msg) SAID[#SAID + 1] = msg end,
    Option = function(key) return DB[key] == true end,
    Part = function(want, events, handler, opt) PART = { want = want, events = events, handler = handler, opt = opt } return PART end,
    JourneyData = function() return nil end,
}
function Second(n, xpEach)
    for _ = 1, n or 1 do
        NOW = NOW + 1
        if xpEach and xpEach > 0 then
            XP = XP + xpEach
            PART.handler(nil, "PLAYER_XP_UPDATE")
        end
        PART.opt.tick()
    end
end
function Kill(name, xp)
    XP = XP + xp
    PART.handler(nil, "PLAYER_XP_UPDATE")
    PART.handler(nil, "CHAT_MSG_COMBAT_XP_GAIN", ("%s dies, you gain %d experience."):format(name, xp))
end
function Line(i) local fs = HeadstartPaceFrame.lines[i] return fs.shown ~= false and fs.words or "" end
function Plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
'''


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok   " if ok else "FAIL ") + what)
        if not ok:
            bad += 1

    core = open(os.path.join(ROOT, "Core.lua"), encoding="utf-8").read()
    # The defaults, from Core.lua itself: off until turned on, and one of the routes' own
    starts_off = core[core.index("local STARTS_OFF = {"):core.index("YR.STARTS_OFF = STARTS_OFF")]
    routes_own = core[core.index("local ROUTES_OWN = {"):core.index("function YR.Option(key)")]
    check(re.search(r"\bpaceWatch = true", starts_off) is not None, "Core.lua: Level pace starts off (STARTS_OFF)")
    check(re.search(r"\bpaceWatch = true", routes_own) is not None, "Core.lua: it is one of the routes' own (ROUTES_OWN)")
    check("Start(YR.StartPace)" in core, "Core.lua starts it")
    toc = open(os.path.join(ROOT, "Headstart.toc"), encoding="utf-8").read()
    check(re.search(r"^Pace\.lua\s*$", toc, re.M) is not None, "Headstart.toc loads Pace.lua")
    editor = open(os.path.join(ROOT, "Headstart_Options", "Editor.lua"), encoding="utf-8").read()
    check('Opt("paceWatch")' in editor, "its switch is on Levelling's Settings page")

    lua.execute(core[core.index("--- A pattern from one of the game's own sentences"):core.index("--- Quality of life on or off")])
    load = lua.eval("function(src, name) local f = assert(loadstring(src, name)) f('Headstart', YR) end")
    load(open(os.path.join(ROOT, "Pace.lua"), encoding="utf-8").read(), "Pace.lua")
    YR = g.YR
    YR.StartPace()
    part = g.PART
    check(part.want() is False and g.MADE == 0 and g.HeadstartPaceFrame is None,
          "off: not wanted, and nothing made")
    events = [part.events[i] for i in range(1, len(part.events) + 1)]
    check(sorted(events) == ["CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_DEAD", "PLAYER_XP_UPDATE"],
          f"on, it listens for three events only ({', '.join(events)})")

    g.DB.paceWatch = True
    check(part.want() is True, "turned on: wanted")
    part.opt.start()
    f = g.HeadstartPaceFrame
    check(f is not None and f.shown is True and lua.eval("HeadstartPaceFrame.anchor == GUIDE"), "the box is made, shown, under the guide window")
    first = lua.eval("Plain(Line(1))")
    check(first == "Level 8: 5.0k XP to go", f"no pace yet: XP to go, no time ({first!r})")

    # -- the pace: 10 XP a second for two minutes
    g.Second(120, 10)
    pace = YR.PacePace()
    check(pace is not None and abs(pace - 10) < 0.01, f"pace: 10 XP a second ({pace})")
    left = g.XPMAX - g.XP                       # 3800
    line = lua.eval("Plain(Line(1))")
    check(line == "Level 8: 3.8k XP to go, 7 min at your pace", f"the level line: XP to go and the time ({line!r}, {left} left)")

    # -- away: five minutes of nothing, not counted
    g.AFK = True
    g.Second(300)
    g.AFK = False
    g.Second(1, 10)
    pace = YR.PacePace()
    check(pace is not None and abs(pace - 10) < 0.01, f"five minutes AFK leave the pace as it was ({pace})")
    # -- dead: the same
    g.DEAD = True
    g.Second(120)
    g.DEAD = False
    g.Second(1, 10)
    pace = YR.PacePace()
    check(pace is not None and abs(pace - 10) < 0.01, f"two minutes dead are not counted either ({pace})")
    # and only the last 10 minutes: an hour later at 2 XP a second, the old pace is gone
    g.Second(700, 2)
    pace = YR.PacePace()
    check(pace is not None and abs(pace - 2) < 0.01, f"the last 10 minutes only ({pace})")
    g.XP = 0
    g.LEVEL = 8
    lua.execute("PART.opt.stop() PART.opt.start()")      # a clean start for the kills

    # -- grinding here: no kills, no rate
    check(lua.eval("YR.PaceGrind() == nil") and lua.eval("Line(2)") == "", "no kills: no grind rate shown")
    # five harpies here, one every 30 seconds, 100 XP each
    for i in range(5):
        g.Kill("Bloodfeather Harpy", 100)
        if i < 4:
            g.Second(30)
    # and one far off, in another subzone: not here
    g.X, g.SUB = 900, "Wellspring Lake"
    g.Kill("Nightsaber", 500)
    g.X, g.SUB = 20, "Lake Al'Ameth"
    g.Second(1)
    rate, avg = YR.PaceGrind()
    check(rate is not None and abs(rate * 60 - 200) < 0.01 and abs(avg - 100) < 0.01,
          f"grind rate: four kills' XP over the two minutes from the first to the last, the far one left out ({rate and rate * 60} a minute, {avg} a kill)")
    line = lua.eval("Plain(Line(2))")
    check(line == "Grinding here: 200 XP a minute", f"the grind line ({line!r})")
    # walking off: 250 yards away, another subzone, the harpies are not here any more
    g.X, g.SUB = 270, "Starbreeze Village"
    check(lua.eval("YR.PaceGrind() == nil"), "250 yards off, in another subzone: not here")
    g.SUB = "Lake Al'Ameth"
    check(lua.eval("YR.PaceGrind() ~= nil"), "the same subzone counts, however far")
    g.X = 20

    # -- a step that trips: a quest worth 440 XP, six minutes of searching with no kills
    g.INLOG[101], g.REWARD[101], g.TITLE[101] = 1, 440, "Zenn's Bidding"
    g.RXP.currentGuide = lua.eval('''{ name = "6-11 Teldrassil", steps = {
        { elements = { { tag = "complete", questId = 101, obj = 1 } } },
        { elements = { { tag = "complete", questId = 102, obj = 1 } } },
        { elements = { { tag = "complete", questId = 103, obj = 1 } } },
        { elements = { { tag = "goto" } } },
        { elements = { { tag = "xp", level = 9, xp = 0 } } },
    } }''')
    g.RXPCData.currentStep = 1
    g.Second(1)
    g.Second(240)
    check(lua.eval("Line(4)") == "", "four minutes in: not judged yet")
    g.Second(60)
    line = lua.eval("Plain(Line(4))")
    check(line == "Zenn's Bidding: 5 min for 440 XP so far. Grinding here pays more: skip it?",
          f"five minutes for 440 XP, against 500 from grinding here at 200 a minute: one line ({line!r})")
    check(len(g.SAID) == 0, "the guide window is shown: in the box, not in chat")
    sets = lua.eval("HeadstartPaceFrame.lines[4].sets")
    g.Second(600)
    check(lua.eval("HeadstartPaceFrame.lines[4].sets") == sets, "said once: the line is not set again")

    # -- a step that doesn't: 2000 XP of reward in six minutes, with a kill on the way
    g.INLOG[102], g.REWARD[102] = 1, 2000
    for i in range(3):          # fresh kills here, so there is a rate to compare with
        g.Kill("Bloodfeather Harpy", 100)
        g.Second(30)
    g.RXPCData.currentStep = 2
    g.Second(400)
    rate = lua.eval("(YR.PaceGrind() or 0) * 60")
    check(lua.eval("Line(4)") == "" and len(g.SAID) == 0 and rate > 0,
          f"a step paying 2000 XP in seven minutes is not called slow (grind here {rate:.0f} a minute)")

    # -- two deaths on a step, guide window hidden: said in chat, once
    g.INLOG[103], g.REWARD[103] = 1, 5000
    g.GUIDE.shown = False
    g.RXPCData.currentStep = 3
    g.Second(5)
    lua.execute('PART.handler(nil, "PLAYER_DEAD")')
    g.Second(5)
    check(len(g.SAID) == 0, "one death: nothing")
    lua.execute('PART.handler(nil, "PLAYER_DEAD")')
    g.Second(5)
    g.Second(5)
    said = g.SAID[1] if len(g.SAID) else ""
    check(len(g.SAID) == 1 and said.endswith("2 deaths and 1 min for 5.0k XP so far. Grinding here may pay more: skip it?"),
          f"two deaths on one step, guide hidden: one line in chat ({said!r})")
    check(lua.eval("HeadstartPaceFrame.anchor == UIParent"), "with the guide hidden the box stands on its own")
    g.GUIDE.shown = True

    # -- a level gate ahead: step 5 wants level 9; at step 4 with 4200 of 5000 XP to go
    g.RXPCData.currentStep = 4
    g.XP = 800
    lua.execute('PART.handler(nil, "PLAYER_XP_UPDATE")')
    g.Second(1)
    line = lua.eval("Plain(Line(3))")
    check(line == "Next step needs level 9: 4.2k XP short, about 42 kills here",
          f"a level gate ahead: how far short, and in kills here ({line!r})")
    short = YR.PaceGateShort(lua.eval("{ level = 10, xp = 0 }"))
    check(short is None, "a gate two levels on, whose size nobody has seen: not guessed")
    lua.execute("YR.JourneyData = function() return { need = { [9] = 6000 } } end")
    short = YR.PaceGateShort(lua.eval("{ level = 10, xp = 0 }"))
    check(short == 4200 + 6000, f"with Journey's record of level 9's size it is counted ({short})")
    short = YR.PaceGateShort(lua.eval("{ level = 9, xp = -500 }"))
    check(short == 3700, f"'500 XP from level 9' ({short})")
    short = YR.PaceGateShort(lua.eval("{ level = 8, xp = 0 }"))
    check(short == 0, "a gate already passed: nothing short")

    # -- off again: hidden, nothing kept
    g.DB.paceWatch = False
    check(part.want() is False, "turned off: not wanted")
    part.opt.stop()
    check(f.shown is False and lua.eval("YR.PaceGrind() == nil and YR.PacePace() == nil"), "off: the box hidden, the kills and samples let go")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
