"""Smoke test of the level-up workout (Workout.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_workout.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Off: nothing of it is made or listened for. On: a ding owes the level's push-ups (or the chosen exercise and count),
the window comes after the fight, Done counts them for the character and the account, the x keeps what is owed for
the next ding and the login, and Arrange places it with a sample that counts for nothing.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r'''
FRAMES, AFTER, PRINTS, ERRS = {}, {}, {}, {}
local Obj
Obj = { __call = function() return setmetatable({}, Obj) end }
Obj.__index = function(t, k)
    local v = rawget(Obj, k)
    if v then return v end
    -- only a method (a capital first letter) is made up: a field the addon never set is nil, as in the game
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    local child = setmetatable({}, Obj); rawset(t, k, child); return child
end
function Obj.Show(self) rawset(self, "_shown", true) end
function Obj.Hide(self) rawset(self, "_shown", false) local h = rawget(self, "_OnHide") if h then h(self) end end
function Obj.IsShown(self) return rawget(self, "_shown") == true end
function Obj.SetScript(self, what, fn) rawset(self, "_" .. what, fn) end
function Obj.RegisterEvent(self, e) rawset(self, "_ev", rawget(self, "_ev") or {}) self._ev[e] = true end
function Obj.UnregisterEvent(self, e) local ev = rawget(self, "_ev") if ev then ev[e] = nil end end
function Obj.UnregisterAllEvents(self) rawset(self, "_ev", nil) end
function Obj.SetText(self, t) rawset(self, "_text", t) end
function Obj.GetText(self) return rawget(self, "_text") end
function Obj.SetShown(self, on) if on then self:Show() else self:Hide() end end
function Obj.SetSize(self, w, h) rawset(self, "_w", w) rawset(self, "_h", h) end
function Obj.SetWidth(self, w) rawset(self, "_w", w) end
function Obj.GetLeft() return 100 end
function Obj.GetTop() return 700 end
function CreateFrame(_, name) local f = setmetatable({}, Obj) table.insert(FRAMES, f) if name then _G[name] = f end return f end
UIParent = CreateFrame()
GameTooltip = CreateFrame()
UIErrorsFrame = { AddMessage = function(_, m) table.insert(ERRS, m) end }
function Fire(event, ...) for _, f in ipairs(FRAMES) do if rawget(f, "_ev") and f._ev[event] and rawget(f, "_OnEvent") then f._OnEvent(f, event, ...) end end end
function Listening(event) local n = 0 for _, f in ipairs(FRAMES) do if rawget(f, "_ev") and f._ev[event] then n = n + 1 end end return n end
C_Timer = { After = function(_, fn) table.insert(AFTER, fn) end, NewTicker = function() return { Cancel = function() end } end }
function RunAfter() for _ = 1, 5 do local l = AFTER AFTER = {} for _, fn in ipairs(l) do fn() end end end
function GetTime() return 0 end
COMBAT, LEVEL = false, 23
function InCombatLockdown() return COMBAT end
function UnitLevel() return LEVEL end
function UnitClass() return "Rogue", "ROGUE" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
SECRET = {}
function issecretvalue(v) return SECRET[v] == true end
YippRouteDB, YippSetupCharDB = {}, {}
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function Click(b) local fn = rawget(b, "_OnClick") if fn then fn(b, "LeftButton") end end
function Up() return HeadstartWorkout ~= nil and rawget(HeadstartWorkout, "_shown") == true end
function Said() return HeadstartWorkout and rawget(HeadstartWorkout.what, "_text") end
function Head() return HeadstartWorkout and rawget(HeadstartWorkout.head, "_text") end
-- a ding as the game sends it: level, health, power, talents, pvp slots, strength, agility, stamina, intellect, spirit
function Ding(level, stamina) LEVEL = level Fire("PLAYER_LEVEL_UP", level, 20, 15, 1, 0, 1, 1, stamina or 2, 0, 1) end
'''


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    YR = lua.table()
    for f in ("Core.lua", "Style.lua", "Workout.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    g = lua.globals()
    lua.execute("function YR_PRINT(m) table.insert(PRINTS, m) end")
    YR.Print = g.YR_PRINT
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def mine():
        w = g.YippSetupCharDB.workout
        return w

    def counts(t):
        return {k: t[k] for k in ("pushups", "squats", "situps") if t is not None and t[k] is not None}

    # ---- off: nothing made, nothing listened for -------------------------------------------------------------
    YR.StartWorkout()
    YR.partsReady = True
    YR.ApplyParts()
    lua.execute("Ding(23) RunAfter()")
    check(YR.OptionDefault("workout") is False and g.Listening("PLAYER_LEVEL_UP") == 0 and g.HeadstartWorkout is None
          and g.YippSetupCharDB.workout is None, "off until turned on: no frame, no event, nothing owed at a ding")
    check(YR.WorkoutNow() is False and any("is off" in g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)),
          "/headstart workout while it is off: says where to turn it on, shows nothing")

    # ---- on: a ding owes the level's push-ups, and the window says so ---------------------------------------
    g.YippRouteDB.workout = True
    YR.ApplyParts()
    lua.execute("RunAfter()")
    check(g.Listening("PLAYER_LEVEL_UP") == 1 and not g.Up(), "turned on: it listens for the ding, and with nothing owed shows nothing")
    lua.execute("Ding(23) RunAfter()")
    check(g.Up() and g.Said() == "23 push-ups" and g.Head() == "LEVEL 23  ·  WORKOUT",
          f"level 23: the window, 23 push-ups ({g.Said()!r}, {g.Head()!r})")
    so = lua.eval("rawget(HeadstartWorkout.so, '_text')")
    check(so == "Your first one on this character", f"nothing done yet on this character: said so ({so!r})")
    # a second level before Done: it adds up
    lua.execute("Ding(24) RunAfter()")
    check(g.Said() == "47 push-ups" and g.Head() == "LEVELS 23-24  ·  WORKOUT", f"two levels: 23 + 24 = 47 ({g.Said()!r}, {g.Head()!r})")
    lua.execute("Click(HeadstartWorkout.done)")
    w = mine()
    check(not g.Up() and counts(w.done) == {"pushups": 47} and counts(g.YippRouteDB.workoutDone) == {"pushups": 47}
          and counts(w.owe) == {} and w["from"] is None,
          f"Done: counted for the character and the account, nothing owed ({counts(w.done)}, {counts(g.YippRouteDB.workoutDone)})")
    check(g.ERRS[1] is not None and "47 push-ups" in g.ERRS[1], f"and a line mid-screen, not in chat ({g.ERRS[1]!r})")

    # ---- in a fight: it waits ---------------------------------------------------------------------------------
    lua.execute("COMBAT = true Ding(25) RunAfter()")
    _during = g.Up()
    lua.execute("COMBAT = false Fire('PLAYER_REGEN_ENABLED')")
    check(not _during and g.Up() and g.Said() == "25 push-ups", "a ding in a fight: the window comes when the fight ends")
    so = lua.eval("rawget(HeadstartWorkout.so, '_text')")
    check(so == "Done so far: 47 push-ups", f"what is done so far, on the window ({so!r})")

    # ---- the x: put away, still owed, back at the next ding and at the login ----------------------------------
    lua.execute("Click(HeadstartWorkout.close)")
    check(not g.Up() and counts(mine().owe) == {"pushups": 25}, "the x: put away, the 25 still owed")
    lua.execute("Ding(26) RunAfter()")
    check(g.Up() and g.Said() == "51 push-ups", f"the next ding: what is owed adds up ({g.Said()!r})")
    lua.execute("Click(HeadstartWorkout.close)")
    # the login: the part comes on again (as at a reload) and shows what is owed
    g.YippRouteDB.workout = False
    YR.ApplyParts()
    check(not g.Up() and g.Listening("PLAYER_LEVEL_UP") == 0, "turned off: put away, nothing listened for")
    g.YippRouteDB.workout = True
    YR.ApplyParts()
    lua.execute("RunAfter()")
    check(g.Up() and g.Said() == "51 push-ups", "at the login (or turned on again): what is still owed comes back")
    lua.execute("Click(HeadstartWorkout.done)")

    # ---- the choices: exercise and how many -------------------------------------------------------------------
    g.YippRouteDB.workoutCount = "half"
    lua.execute("Ding(27) RunAfter()")
    check(g.Said() == "14 push-ups", f"half your level: 14 at 27 ({g.Said()!r})")
    lua.execute("Click(HeadstartWorkout.done)")
    g.YippRouteDB.workoutCount = "stamina"
    lua.execute("Ding(28, 3) RunAfter()")
    check(g.Said() == "30 push-ups", f"stamina: ten a point, 3 Stamina = 30 ({g.Said()!r})")
    lua.execute("Click(HeadstartWorkout.done)")
    lua.execute("SECRET[4] = true Ding(29, 4) RunAfter() SECRET[4] = nil")
    check(g.Said() == "29 push-ups", f"stamina the game won't tell (secret): the level instead ({g.Said()!r})")
    lua.execute("Click(HeadstartWorkout.done)")
    g.YippRouteDB.workoutCount = None
    g.YippRouteDB.workoutKind = "turns"
    lua.execute("Ding(30) RunAfter() Click(HeadstartWorkout.close) Ding(31) RunAfter() Click(HeadstartWorkout.close) Ding(32) RunAfter()")
    check(g.Said() == "30 push-ups + 31 squats + 32 sit-ups" and g.Head() == "LEVELS 30-32  ·  WORKOUT",
          f"in turn: push-ups, squats, sit-ups, one a level, named in that order ({g.Said()!r})")
    lua.execute("Click(HeadstartWorkout.done)")
    check(counts(mine().done) == {"pushups": 47 + 51 + 14 + 30 + 29 + 30, "squats": 31, "situps": 32},
          f"each exercise counted for itself ({counts(mine().done)})")
    check(YR.WorkoutDoneWords(mine().done) == "201 push-ups, 31 squats, 32 sit-ups", f"in words: {YR.WorkoutDoneWords(mine().done)!r}")
    g.YippRouteDB.workoutKind = "squats"
    lua.execute("Ding(33) RunAfter()")
    check(g.Said() == "33 squats", f"squats chosen: squats ({g.Said()!r})")
    lua.execute("Click(HeadstartWorkout.done)")
    g.YippRouteDB.workoutKind = None
    check(YR.WorkoutWords(1, "situps") == "1 sit-up" and YR.WorkoutWords(2, "pushups") == "2 push-ups", "one is one push-up, not one push-ups")

    # ---- the button and /headstart workout: what is owed, or one for your level ------------------------------
    lua.execute("LEVEL = 33")
    check(YR.WorkoutNow() is True and g.Up() and g.Said() == "33 push-ups", f"Work out now with nothing owed: one for your level ({g.Said()!r})")
    lua.execute("Click(HeadstartWorkout.close)")
    check(YR.WorkoutNow() is True and g.Said() == "33 push-ups", "Work out now with something owed: that, not more")
    lua.execute("Click(HeadstartWorkout.done)")

    # ---- Arrange: a sample to place, which counts for nothing ---------------------------------------------------
    before = counts(mine().done)
    f = YR.WorkoutFrame(True)
    check(f is not None and g.Up() and g.Said() == "20 push-ups", f"Arrange has it to place, with a sample on it ({g.Said()!r})")
    lua.execute("Click(HeadstartWorkout.done) Click(HeadstartWorkout.close)")
    check(g.Up() and counts(mine().done) == before, "the sample's Done and x do nothing")
    YR.WorkoutSave()
    YR.WorkoutFrame(False)
    check(not g.Up() and g.YippRouteDB.workoutPos is not None and g.YippRouteDB.workoutPos[1] == 100,
          "and it goes with the grid; where it was put is kept")
    YR.WorkoutReset()
    check(g.YippRouteDB.workoutPos is None, "Reset: back to its own place")

    # ---- what a saved file can hold: anything ------------------------------------------------------------------
    lua.execute("YippSetupCharDB.workout = 'x' YippRouteDB.workoutDone = 7")
    lua.execute("Ding(34) RunAfter()")
    check(g.Up() and g.Said() == "34 push-ups", "a saved value of the wrong shape: started again, no error")
    lua.execute("Click(HeadstartWorkout.done)")
    check(counts(g.YippRouteDB.workoutDone) == {"pushups": 34}, "and the account's count starts again from what is done")
    lua.execute("YippSetupCharDB.workout = { owe = { pushups = 'many', squats = -3 }, done = { pushups = {} } }")
    check(YR.WorkoutShow() is False and not g.Up(), "owed counts that are not numbers, or below one: nothing shown")
    check(g.YR_ERR is None and YR.partError is None, "no error along the way")

    g.YippRouteDB.workout = False
    YR.ApplyParts()
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
