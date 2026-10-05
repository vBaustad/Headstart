"""Smoke test of the swing timer (Swing.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_swing.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Off: nothing is built and Blizzard's bars are left alone. On: a swing fills its bar from the game's
event, with the time left and the swing's length on it; nothing is drawn between swings; the bar turns
the out-of-reach colour on the game's range event; a secret length falls back to the weapon's speed;
Blizzard's bars go see-through and come back as they were; Edit Mode shows Blizzard's and not ours.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r"""
FRAMES, BUILT = {}, 0
local F = {}
F.__index = function(t, k) return rawget(F, k) or function() end end
function F:RegisterEvent(e) local ev = rawget(self, "ev") or {} ev[e] = true rawset(self, "ev", ev) end
function F:SetScript(w, fn) rawset(self, "_" .. w, fn) end
function F:SetShown(on) rawset(self, "shown", on and true or false) end
function F:Show() rawset(self, "shown", true) end
function F:Hide() rawset(self, "shown", false) end
function F:IsShown() return rawget(self, "shown") ~= false end
function F:SetAlpha(a) rawset(self, "alpha", a) end
function F:GetAlpha() return rawget(self, "alpha") or 1 end
function F:SetValue(v) rawset(self, "value", v) end
function F:SetMinMaxValues(a, b) rawset(self, "max", b) end
function F:SetText(t) rawset(self, "words", t) rawset(self, "writes", (rawget(self, "writes") or 0) + 1) end
function F:SetStatusBarColor(r, g, b) rawset(self, "colour", { r, g, b }) end
function F:GetWidth() return 200 end
function F:GetLeft() return 0 end
function F:GetTop() return 0 end
function F:CreateTexture() return setmetatable({}, F) end
function F:CreateFontString() return setmetatable({}, F) end
function CreateFrame(kind, name)
    local f = setmetatable({}, F)
    BUILT = BUILT + 1
    if kind == "StatusBar" then BARS = BARS or {} BARS[#BARS + 1] = f end
    if name then _G[name] = f end
    table.insert(FRAMES, f)
    return f
end
UIParent = setmetatable({}, F)
function Fire(e, ...)
    for _, f in ipairs(FRAMES) do
        local ev, fn = rawget(f, "ev"), rawget(f, "_OnEvent")
        if ev and ev[e] and fn then fn(f, e, ...) end
    end
end
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
floor = math.floor
YippRouteDB = {}
function print() end
NOW = 100
function GetTime() return NOW end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitAffectingCombat() return false end
function InCombatLockdown() return false end
OFFHAND = nil
function UnitAttackSpeed() return 2.4, OFFHAND end
function UnitRangedDamage() return 0 end
function GetInventoryItemTexture() return 135274 end
SECRET = {}
function issecretvalue(v) return v == SECRET end
RANGE = {}
C_SwingTimer = { EnableRangeCheck = function(kind, on) RANGE[kind] = on end }
CALLBACKS = {}
EventRegistry = { RegisterCallback = function(_, name, fn) CALLBACKS[name] = fn end }
SwingTimerMainHandFrame = setmetatable({ alpha = 0.8 }, F)
function F:SetStatusBarTexture(t) rawset(self, "tex", t) end
function F:GetStatusBarTexture() return setmetatable({ GetAtlas = function() return "their-atlas" end }, F) end
function F:GetStatusBarColor() local c = rawget(self, "colour") or { 0, 0, 1 } return c[1], c[2], c[3], 1 end
function F:SetFont(file, size) rawset(self, "font", { file, size }) end
function F:GetFont() local f = rawget(self, "font") or { "their.ttf", 10 } return f[1], f[2], "" end
function F:GetHeight() return 24 end
function hooksecurefunc(t, name, fn)
    local old = t[name]
    rawset(t, name, function(...) old(...) fn(...) end)
end
do
    local f = SwingTimerMainHandFrame
    rawset(f, "StatusBar", setmetatable({}, F))
    rawset(f, "Border", setmetatable({}, F))
    rawset(f, "Background", setmetatable({}, F))
    TYPE_LABEL, TIME_LABEL = setmetatable({}, F), setmetatable({}, F)
    rawset(f, "GetTypeLabel", function() return TYPE_LABEL end)
    rawset(f, "GetTypeLabelShadow", function() return nil end)
    rawset(f, "GetTimeLabel", function() return TIME_LABEL end)
end
""")
    YR = lua.table()
    YR.Style = lua.eval('{ FONT = "Fonts/FRIZQT__.TTF" }')
    for f in ("Core.lua", "Swing.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    raw = lua.eval("rawget")
    YR.StartSwing()
    built = g.BUILT
    lua.execute("Fire('PLAYER_ENTERING_WORLD') Fire('PLAYER_SWING', 2.6, 0)")
    check(g.BUILT == built and g.HeadstartSwing is None and g.SwingTimerMainHandFrame.alpha == 0.8,
          "off: nothing built on a swing, Blizzard's bars left as they are")
    YR.SwingDB().on = True
    YR.SwingDB().style = "own"
    YR.SwingApply()
    main, off, ranged = g.BARS[1], g.BARS[2], g.BARS[3]
    holder = g.HeadstartSwing
    check(g.SwingTimerMainHandFrame.alpha == 0 and g.RANGE[0] is True,
          "on: Blizzard's bar see-through, and the game asked to tell us about reach")
    check(raw(holder, "shown") is False, "out of combat (shown in combat): no bars")
    lua.execute("Fire('PLAYER_REGEN_DISABLED')")
    check(raw(main, "shown") is True and raw(off, "shown") is False and raw(ranged, "shown") is False
          and raw(holder, "_OnUpdate") is None,
          "in combat: the main hand's bar alone (no off-hand weapon, not a hunter), and nothing drawn each frame")
    lua.execute("Fire('PLAYER_SWING', 2.6, 0)")
    check(raw(holder, "_OnUpdate") is not None and raw(main, "max") == 2.6 and raw(main, "value") == 0
          and raw(raw(main, "time"), "words") == "2.6 / 2.6", f"a swing: the bar starts, with the time left and its length ({raw(raw(main, 'time'), 'words')})")
    lua.execute("NOW = NOW + 1.8")
    raw(holder, "_OnUpdate")(holder, 0.016)
    check(abs(raw(main, "value") - 1.8) < 0.001 and raw(raw(main, "time"), "words") == "0.8 / 2.6",
          f"1.8 seconds on: filled that far, 0.8 left ({raw(raw(main, 'time'), 'words')})")
    writes = raw(raw(main, "time"), "writes")
    lua.execute("NOW = NOW + 0.01")
    raw(holder, "_OnUpdate")(holder, 0.016)
    check(raw(raw(main, "time"), "writes") == writes, "a frame later, the same tenth: the words aren't written again")
    lua.execute("Fire('PLAYER_SWING_RANGE_UPDATE', 0, false, true)")
    far = list(YR.SwingDB().farColor.values())[:3]
    check(list(raw(main, "colour").values()) == far, "the target out of reach: the out-of-reach colour")
    lua.execute("Fire('PLAYER_SWING_RANGE_UPDATE', 0, false, false)")
    check(list(raw(main, "colour").values()) == list(YR.SwingDB().mainColor.values())[:3],
          "no range check made (no target): the hand's own colour")
    lua.execute("NOW = NOW + 2")
    raw(holder, "_OnUpdate")(holder, 0.016)
    check(raw(holder, "_OnUpdate") is None and raw(main, "value") == 2.6, "the swing ran out: full, and nothing drawn each frame again")
    lua.execute("OFFHAND = 1.5 Fire('PLAYER_SWING', SECRET, 1)")
    check(raw(off, "shown") is True and raw(off, "max") == 1.5, "an off-hand swing whose length is secret: the weapon's speed instead")
    lua.execute("Fire('PLAYER_SWING', 2.0, 2)")
    check(raw(ranged, "shown") is True, "a ranged swing: its bar shows while it runs")
    lua.execute("CALLBACKS['EditMode.Enter']()")
    check(raw(holder, "shown") is False and g.SwingTimerMainHandFrame.alpha == 0.8, "Edit Mode: Blizzard's bars as they were, ours away")
    lua.execute("CALLBACKS['EditMode.Exit']()")
    check(raw(holder, "shown") is True and g.SwingTimerMainHandFrame.alpha == 0, "Edit Mode closed: ours again")
    YR.SwingDB().show = "swing"
    lua.execute("NOW = NOW + 10")
    YR.SwingApply()
    check(raw(holder, "shown") is False, "only while a swing runs, and none does: no bars")
    YR.SwingDB().lock = False
    YR.SwingApply()
    check(raw(main, "shown") is True and raw(off, "shown") is True and raw(ranged, "shown") is True,
          "unlocked: every bar shows, to place them")
    YR.SwingDB().lock = True
    g.YippRouteDB.qolOff = True
    YR.SwingApply()
    check(raw(holder, "shown") is False and g.SwingTimerMainHandFrame.alpha == 0.8 and g.RANGE[0] is True,
          "quality of life off: ours away, Blizzard's back - and the game's range check left on (Blizzard's bars read it too)")
    # Blizzard's bars, dressed
    g.YippRouteDB.qolOff = None
    their = g.SwingTimerMainHandFrame
    sb = their.StatusBar
    YR.SwingDB().style = "blizzard"
    YR.SwingApply()
    mine = list(YR.SwingDB().mainColor.values())[:3]
    check(their.alpha == 0.8 and raw(holder, "shown") is False, "Blizzard's bars, dressed: theirs shown, ours away")
    check("Raid-Bar-Hp-Fill" in raw(sb, "tex") and list(raw(sb, "colour").values()) == mine and raw(their.Border, "alpha") == 0
          and raw(g.TYPE_LABEL, "font")[2] == 12 and raw(g.TIME_LABEL, "font")[2] == 12,
          "our texture, your colour, its frame off, the text at your size")
    check(raw(their.Background, "alpha") == 0 and YR.SwingDB().icon is False and YR.SwingDB().outline is True,
          "Blizzard's own background cleared (ours goes round the bar itself), no weapon icon, an outline")
    lua.execute("SwingTimerMainHandFrame.StatusBar:SetStatusBarColor(1, 0, 0, 1)")
    check(list(raw(sb, "colour").values()) == mine, "Blizzard colours its bar again: yours goes back over it")
    lua.execute("Fire('PLAYER_SWING', 2.6, 0)")
    texts = [raw(t, "words") for t in g.FRAMES.values()] if False else None
    lua.execute("Fire('PLAYER_SWING_RANGE_UPDATE', 0, false, true)")
    check(list(raw(sb, "colour").values()) == list(YR.SwingDB().farColor.values())[:3], "out of reach: the out-of-reach colour on Blizzard's bar")
    lua.execute("Fire('PLAYER_SWING_RANGE_UPDATE', 0, true, true)")
    # the Test button on Blizzard's bars: shown and filled by us for a few seconds, then as they were
    lua.execute("SwingTimerMainHandFrame.shown = false")
    ok = YR.SwingTest()
    sampler = [f for f in g.FRAMES.values() if raw(f, "_OnUpdate") is not None and f != holder]
    check(ok is True and raw(their, "shown") is True and len(sampler) == 1, "Test on Blizzard's bars: shown, with something filling them")
    lua.execute("NOW = NOW + 1")
    raw(sampler[0], "_OnUpdate")(sampler[0], 0.016)
    check(abs(raw(sb, "value") - 1.0) < 0.001 and raw(g.TIME_LABEL, "words") == "1.2", f"a second in: filled that far, with the time left ({raw(g.TIME_LABEL, 'words')})")
    lua.execute("NOW = NOW + 4")
    raw(sampler[0], "_OnUpdate")(sampler[0], 0.016)
    check(raw(their, "shown") is False and raw(sampler[0], "_OnUpdate") is None, "four seconds on: hidden again as it was, and nothing left running")
    lua.execute("SwingTimerMainHandFrame.shown = true")
    YR.SwingDB().colors = False
    YR.SwingApply()
    check(list(raw(sb, "colour").values())[:3] == [1, 0, 0], "my colours off: the colour Blizzard last set")
    YR.SwingDB().on = False
    YR.SwingApply()
    check(raw(sb, "tex") == "their-atlas" and raw(their.Border, "alpha") == 1 and raw(g.TYPE_LABEL, "font")[1] == "their.ttf"
          and raw(g.TYPE_LABEL, "font")[2] == 10 and raw(their.Background, "alpha") == 1, "off: Blizzard's texture, frame, background and font back as they were")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
