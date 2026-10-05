"""Smoke test of the instance tracker (Instances.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_instances.py      (exit code 1 on any failure; tools/smoke.py runs it too)

A new dungeon counts; going back into the one you just left counts once; a reset, another leader or a
long time away make it new; a reload inside carries the run on; the hour and the day count, and the
wait for the next slot at the limit; the game's "too many instances" is noted; XP and money are logged;
characters count apart unless the account counts together.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
FRAMES, AFTER = {}, {}
local F = {}
F.__index = F
function F:RegisterEvent(e) self.ev = self.ev or {} self.ev[e] = true end
function F:SetScript(_, fn) self.fn = fn end
function CreateFrame(kind, name)
    if kind == "Button" then
        local b = setmetatable({}, W)
        if name then _G[name] = b end
        return b
    end
    local f = setmetatable({}, F) table.insert(FRAMES, f) return f
end
function Fire(e, ...) for _, f in ipairs(FRAMES) do if f.ev and f.ev[e] and f.fn then f.fn(f, e, ...) end end end
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }
W = {}
W.__index = function(t, k) return rawget(W, k) or function() return setmetatable({}, W) end end
function W:SetShown(on) rawset(self, "shown", on and true or false) end
function W:Show() rawset(self, "shown", true) end
function W:Hide() rawset(self, "shown", false) end
function W:IsShown() return rawget(self, "shown") == true end
function W:SetText(t) rawset(self, "text", t) end
function W:SetScript() end
UIParent = setmetatable({}, W)
GameTooltip = setmetatable({}, W)
function GameTooltip:IsOwned() return false end
function IsShiftKeyDown() return false end
STYLE = { FONT = "x" }
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
floor = math.floor
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
YippRouteDB = {}
PRINTS, NOTICES = {}, {}
function print(m) table.insert(PRINTS, m) end
RaidWarningFrame, ChatTypeInfo = {}, { RAID_WARNING = {} }
function RaidNotice_AddMessage(_, m) table.insert(NOTICES, m) end
NOW, INSIDE, MAP, NAME, LEADER = 100000, false, 36, "The Deadmines", nil
XP, XPMAX, LEVEL, MONEY = 100, 1000, 18, 500
ME = "Tester"
function GetServerTime() return NOW end
function UnitFullName() return ME, "Realm" end
function GetRealmName() return "Realm" end
function IsInInstance() return INSIDE, INSIDE and "party" or "none" end
function GetInstanceInfo() return NAME, "party", 1, "Normal", 5, 0, false, MAP end
function IsInGroup() return LEADER ~= nil end
function UnitExists(u) return LEADER ~= nil and u == "party1" end
function UnitIsGroupLeader(u) return u == "party1" end
function UnitName() return LEADER end
function UnitXP() return XP end
function UnitXPMax() return XPMAX end
function UnitLevel() return LEVEL end
function GetMoney() return MONEY end
INSTANCE_RESET_SUCCESS = "%s has been reset."
TRANSFER_ABORT_TOO_MANY_INSTANCES = "You have entered too many instances recently."
''')
    YR = lua.table()
    for f in ("Core.lua", "Instances.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    YR.Style = lua.eval("STYLE")
    YR.StartInstances()
    g = lua.globals()
    g.YR_CHARKEY = YR.CharKey
    g.key_restore = YR.CharKey
    g.YR_SET = lambda fn: setattr(YR, "CharKey", fn)
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def go_in(name=None, mapid=None):
        if name:
            g.NAME, g.MAP = name, mapid
        lua.execute("INSIDE = true Fire('PLAYER_ENTERING_WORLD')")

    def go_out(after=60):
        lua.execute(f"NOW = NOW + {after} INSIDE = false Fire('PLAYER_ENTERING_WORLD')")

    def counts():
        h, d, w = YR.InstanceCounts()
        return h, d, w

    lua.execute("Fire('PLAYER_ENTERING_WORLD')")
    hud = lambda: g.HeadstartInstanceHud
    shown = lua.eval("function(o) return rawget(o, 'shown') == true end")
    text = lua.eval("function(o) return rawget(o, 'text') end")
    check(not shown(hud()), "on screen: nothing while you've no instance this hour")
    g.YippRouteDB.instanceHudAlways = True
    YR.InstanceHudApply()
    check(shown(hud()) and text(hud().count) == "0/5", f"'Show it always': the icon, 0/5 ({text(hud().count)})")
    g.YippRouteDB.instanceHudAlways = None
    go_in()
    check(counts()[0] == 1, "into the Deadmines: 1 this hour")
    check(shown(hud()) and text(hud().count) == "1/5" and shown(hud().icon), f"in an instance: the icon says 1/5 ({text(hud().count)})")
    s = YR.InstanceSummary(3)
    check(s.state == "ok" and s.runs[1].inside and s.runs[1].text.startswith("The Deadmines"), f"the summary: in the Deadmines now ({s.runs[1].text})")
    g.YippRouteDB.instanceHud = "log"
    YR.InstanceHudApply()
    check(not shown(hud().icon) and "1/5 this hour" in text(hud().head) and "The Deadmines" in text(hud().rows[1]),
          f"the small log: counts and the run ({text(hud().head)} | {text(hud().rows[1])})")
    g.YippRouteDB.instanceHud = "off"
    YR.InstanceHudApply()
    check(not shown(hud()), "'Nothing': not shown")
    g.YippRouteDB.instanceHud = None
    YR.InstanceHudApply()
    lua.execute("XP = 600 Fire('PLAYER_XP_UPDATE') MONEY = 2500")
    go_out(600)
    run1 = g.YippRouteDB.instanceRuns[1]
    check(run1.xp == 500 and run1.money == 2000 and run1.left - run1.entered == 600,
          f"the run logged: 500 XP, 20s, 10 minutes ({run1.xp}, {run1.money}, {run1.left - run1.entered})")
    lua.execute("NOW = NOW + 120")
    go_in()
    check(counts()[0] == 1, "back in two minutes later: the same instance, still 1")
    go_out(60)
    lua.execute("Fire('CHAT_MSG_SYSTEM', 'The Deadmines has been reset.') NOW = NOW + 30")
    go_in()
    check(counts()[0] == 2, "after a reset: a new one, 2")
    go_out(60)
    lua.execute("LEADER = 'Someone' NOW = NOW + 30")
    go_in()
    check(counts()[0] == 3, "another group leader: a new one, 3")
    # a reload inside: the same run carries on, nothing counted
    # a real /reload: the module loaded afresh, remembering nothing but the saved log
    YR2 = lua.table()
    chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, "Instances.lua"), encoding="utf-8").read(), "Instances.lua")
    chunk("Headstart", YR2)
    YR2.Print = YR.Print
    YR2.CharKey = YR.CharKey
    YR2.Option = YR.Option
    YR2.Style = YR.Style
    lua.execute("for i = #FRAMES, 1, -1 do FRAMES[i] = nil end")      # the old module's frame is gone too
    YR2.StartInstances()
    lua.execute("Fire('PLAYER_ENTERING_WORLD')")
    check(counts()[0] == 3, "a reload inside: the run carries on, not counted again")
    go_out(60)
    lua.execute("NOW = NOW + 3600")           # well past the 30 minutes
    go_in()
    check(counts()[0] == 1 and counts()[1] == 4, f"an hour on: 1 this hour, 4 today ({counts()})")
    go_out(60)
    # up to the limit: the wait for the next slot, and the warnings
    lua.execute("NOTICES = {}")
    for i, (n, m) in enumerate((("Wailing Caverns", 43), ("Shadowfang Keep", 33), ("Blackfathom Deeps", 48), ("Gnomeregan", 90))):
        lua.execute("NOW = NOW + 60")
        go_in(n, m)
        go_out(60)
    h, d, w = counts()
    check(h == 5 and w is not None and 0 < w <= 3600, f"5 of 5 this hour: the next slot in {w} s")
    s = YR.InstanceSummary(3)
    check(s.state == "full" and len(s.runs) == 3 and s.runs[1].text.startswith("Gnomeregan"),
          f"at the limit: the summary is 'full', the latest three runs, newest first ({s.runs[1].text})")
    YR.InstanceHudApply()
    check(shown(hud().wait) and text(hud().wait) not in (None, ""), f"the icon shows the wait under it ({text(hud().wait)})")
    check(len(g.NOTICES) >= 2, f"warned on screen at 4 and at 5 ({len(g.NOTICES)})")
    # asked every second: the week's log is walked once, then not again until the clock or the log says so
    lua.execute("WALKS = 0 local key = YR_CHARKEY YR_SET(function() WALKS = WALKS + 1 return key() end)")
    for _ in range(60):
        counts()
    # one look at who you are per ask; a walk of the log would add one more for every run in it
    check(g.WALKS == 60, f"asked sixty times in the same moment: the log isn't walked again ({g.WALKS} looks, 60 asks)")
    h0 = counts()[0]
    lua.execute("NOW = NOW + 3600")
    check(counts()[0] < h0, f"an hour on: counted again, and the hour is emptier ({h0} -> {counts()[0]})")
    lua.execute("NOW = NOW - 3600")
    check(counts()[0] == h0, "and back (the clock put back for the tests below)")
    lua.execute("YR_SET(key_restore)")
    # the game says too many: noted with the count
    lua.execute("Fire('UI_ERROR_MESSAGE', 1, 'You have entered too many instances recently.')")
    locks = g.YippRouteDB.instanceLocks
    check(locks is not None and locks[1].hour == 5, "the game's 'too many' is noted at 5 this hour")
    # another character: its own count, unless the account counts together
    lua.execute("ME = 'Alt'")
    check(counts()[0] == 0, "another character: its own count")
    g.YippRouteDB.instanceAccount = True
    check(counts()[0] == 5, "the account counted together: all five")
    g.YippRouteDB.instanceAccount = None
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
