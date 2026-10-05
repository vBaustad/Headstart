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
C_Timer = { After = function(_, fn) end, NewTicker = function() return {} end }
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
floor = math.floor
YippRouteDB = {}
NOW = 1000
function GetTime() return NOW end
XP, XPMAX, LEVEL, RESTED = 1000, 4000, 18, 600
function UnitXP() return XP end
function UnitXPMax() return XPMAX end
function UnitLevel() return LEVEL end
function GetXPExhaustion() return RESTED end
function GetMaxPlayerLevel() return 60 end
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
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    f = YR.XPBarFormat
    check(f("Level {level}: {xp} / {max} ({pct}%)") == "Level 18: 1000 / 4000 (25.0%)",
          f"tokens filled in: {f('Level {level}: {xp} / {max} ({pct}%)')}")
    check(f("{nonsense} stays") == "{nonsense} stays", "an unknown token is left as written")
    check(f("{ding}") == "30m 00s", f"time to ding: 3000 left at 6000 an hour ({f('{ding}')})")
    check(f("{played} / {levelplayed}") == "2h 00m / 15m 00s", f"played time: {f('{played} / {levelplayed}')}")
    check(f("{rested}") == "600 rested" and f("{restedpct}") == "15%", "rested, and as a share of the level")
    # kills: XP with no quest handed in just before; the quest's XP doesn't count
    lua.execute("Fire('PLAYER_ENTERING_WORLD')")
    lua.execute("XP = 1100 Fire('PLAYER_XP_UPDATE') XP = 1200 Fire('PLAYER_XP_UPDATE')")
    lua.execute("Fire('QUEST_TURNED_IN') XP = 2200 Fire('PLAYER_XP_UPDATE')")
    check(f("{kill} {mobs}") == "100 18", f"two kills of 100 (the quest's 1000 left out): 1800 left is 18 kills ({f('{kill} {mobs}')})")
    # Blizzard's bar: invisible while ours shows, back when ours is off
    check(g.MainStatusTrackingBarContainer.alpha == 0, "Blizzard's bar invisible while ours shows")
    YR.XPBarDB().on = False
    YR.XPBarApply()
    check(g.MainStatusTrackingBarContainer.alpha == 1, "ours off: Blizzard's is back")
    YR.XPBarDB().on = True
    YR.XPBarDB().hideBlizz = False
    YR.XPBarApply()
    check(g.MainStatusTrackingBarContainer.alpha == 1, "'Hide Blizzard's bar' off: both show")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
