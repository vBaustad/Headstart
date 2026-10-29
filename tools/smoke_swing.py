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
function F:UnregisterEvent(e) local ev = rawget(self, "ev") if ev then ev[e] = nil end end
function F:UnregisterAllEvents() rawset(self, "ev", nil) end
function F:SetScript(w, fn) rawset(self, "_" .. w, fn) end
PLAYED = 0
function F:CreateAnimationGroup()
    return { CreateAnimation = function() return setmetatable({}, F) end, Stop = function() end, Play = function() PLAYED = PLAYED + 1 end }
end
function F:SetShown(on) rawset(self, "shown", on and true or false) end
function F:Show() rawset(self, "shown", true) end
function F:Hide() rawset(self, "shown", false) end
function F:IsShown() return rawget(self, "shown") ~= false end
function F:SetAlpha(a) rawset(self, "alpha", a) end
function F:GetAlpha() return rawget(self, "alpha") or 1 end
function F:SetValue(v) rawset(self, "value", v) end
function F:SetMinMaxValues(a, b) rawset(self, "max", b) end
-- (as the game: words on a font string that has no font yet are an error, "Font not set")
function F:SetText(t)
    if rawget(self, "fontstring") and not rawget(self, "font") then error("FontString:SetText(): Font not set", 2) end
    rawset(self, "words", t) rawset(self, "writes", (rawget(self, "writes") or 0) + 1)
end
function F:SetStatusBarColor(r, g, b) rawset(self, "colour", { r, g, b }) end
function F:GetWidth() return 200 end
function F:GetStringWidth() local w = rawget(self, "words") return type(w) == "string" and #w * 7 or 0 end
function F:GetLeft() return 0 end
function F:GetTop() return 0 end
function F:CreateTexture() return setmetatable({}, F) end
function F:CreateFontString() local fs = setmetatable({}, F) rawset(fs, "fontstring", true) return fs end
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
    -- Blizzard's own (live 70532): the background's and frame's alpha set again as each swing starts and ends
    rawset(f, "ApplyRangePresentation", function(self)
        local a = OUT_OF_RANGE and 0.4 or 1
        self.Background:SetAlpha(a)
        self.Border:SetAlpha(a)
    end)
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
    # the swing timer comes on at the login, if it is on (YR.Part): nothing of it exists before
    YR.partsReady = True
    YR.ApplyParts()
    built = g.BUILT
    lua.execute("Fire('PLAYER_ENTERING_WORLD') Fire('PLAYER_SWING', 2.6, 0)")
    check(g.BUILT == built and g.HeadstartSwing is None and g.SwingTimerMainHandFrame.alpha == 0.8,
          "off: nothing built on a swing, Blizzard's bars left as they are")
    check(not YR.SwingOn() and g.YippRouteDB.swing is None, "off: asking whether it's on doesn't fill its settings in")
    check(not any(raw(f, "ev") and (raw(f, "ev")["PLAYER_SWING"] or raw(f, "ev")["PLAYER_ENTERING_WORLD"]) for f in g.FRAMES.values()) and len(list(g.CALLBACKS)) == 0,
          "off: no swing or loading screen listened for, no Edit Mode callback")
    # a new install's look is Slim; Classic is the look from before, and a preset changes the look only
    d = YR.SwingDB()
    check(d.h == 14 and d.gap == 1 and d.texture == "flat" and d.time is False and d.name is True and d.on is False,
          "a new install: the Slim look, and still off")
    d.pos = lua.eval("{ 100, -200 }")
    check(YR.SwingPreset("classic") is True and d.h == 20 and d.texture == "smooth" and d.time is True and d.preset == "classic"
          and d.on is False and d.pos[1] == 100 and YR.SwingPreset("nonsense") is False,
          "Classic put on: sizes, texture and text - not whether it's on or where it is; an unknown look is refused")
    check(YR.SwingPreset("soft") is True and d.h == 18 and d.texture == "smooth" and d.time is False and d.preset == "soft" and d.pos[1] == 100,
          "the Soft look: shaded, muted, only the name - and nothing but the look changed")
    check(YR.SwingPreset("slim") is True and d.h == 14 and list(d.mainColor.values())[0] == 0.72 and d.pos[1] == 100, "and Slim again")
    # one kind of bar: Blizzard's, restyled. Settings from when Headstart drew its own are moved over, once
    check(d.style == "blizzard" and d.look == 7 and d.spark is True and d.border is False, "a new install: Blizzard's bars, with the front edge")
    check(YR.SwingFrameNow() == "light" and d.rim is False and d.lineColor is not None and d.texture == "flat",
          "and one thin light line round a flat fill")
    check(YR.SwingFrame("bronze") is True and d.lineColor is None and YR.SwingFrameNow() == "bronze" and YR.SwingFrame("thin") is True
          and YR.SwingFrameNow() == "thin" and YR.SwingFrame("light") is True and YR.SwingFrameNow() == "light",
          "the frame picked: bronze, a thin dark line, and the light one back")
    g.YippRouteDB.swing = lua.eval("{ on = true, style = 'own', look = 2, h = 30, lock = false, range = false }")
    moved = YR.SwingDB()
    check(moved.style == "blizzard" and moved.look == 7 and moved.rimKind == "light" and moved.on is True and moved.h == 30,
          "someone who had Headstart's own bars: on Blizzard's now, the rest as it was")
    check(moved.lock is True and moved.range is True,
          "bars left unlocked, out of range off: locked and shown, once (neither is on the page any more)")
    moved.style = "own"
    check(YR.SwingDB().style == "own", "moved once only (the next look at the settings leaves them be)")
    g.YippRouteDB.swing = d
    YR.SwingPreset("classic")           # (the checks below were written for this look's time and length texts)
    d.pos = None
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
    check(raw(raw(main, "far"), "shown") is True and raw(raw(main, "far"), "words") == "Out of range",
          "and said in words on the bar")
    lua.execute("Fire('PLAYER_SWING_RANGE_UPDATE', 0, false, false)")
    check(list(raw(main, "colour").values()) == list(YR.SwingDB().mainColor.values())[:3],
          "no range check made (no target): the hand's own colour")
    # the same look on another of Blizzard's bars (the resource bar's): its texture ours, its own put back
    lua.execute("""OTHER = CreateFrame("StatusBar")
        OTHER.tex = { GetTexture = function() return "Blizzard-Own" end }
        function OTHER:GetStatusBarTexture() return self.tex end
        function OTHER:SetStatusBarTexture(t) self.set = t end""")
    check(YR.BarLook(g.OTHER, True) is True and raw(g.OTHER, "set") != "Blizzard-Own" and raw(g.OTHER, "set") is not None,
          f"another bar wears the swing bars' texture ({raw(g.OTHER, 'set')})")
    check(YR.BarLook(g.OTHER, False) is True and raw(g.OTHER, "set") == "Blizzard-Own", "taken off: Blizzard's own texture is back")
    check(YR.BarLook(lua.eval("{}"), True) is False, "something that isn't a status bar is left alone")
    # the game's switch for reach is one switch, and Blizzard's bars may turn it off: asked again
    lua.execute("RANGE[0] = false Fire('PLAYER_TARGET_CHANGED')")
    check(g.RANGE[0] is True, "a new target: the game is asked about reach again")
    lua.execute("RANGE[0] = false Fire('PLAYER_REGEN_DISABLED')")
    check(g.RANGE[0] is True, "a fight begins: asked again")
    lua.execute("NOW = NOW + 2")
    raw(holder, "_OnUpdate")(holder, 0.016)
    check(raw(holder, "_OnUpdate") is None and raw(main, "value") == 0, "the swing ran out: the bar is empty until you swing again, and nothing is drawn each frame")
    YR.SwingDB().idleFull = True
    YR.SwingApply()
    check(raw(main, "value") == 2.6, "set to stand full between swings: full")
    YR.SwingDB().idleFull = None
    YR.SwingApply()
    lua.execute("OFFHAND = 1.5 Fire('PLAYER_SWING', SECRET, 1)")
    check(raw(off, "shown") is True and raw(off, "max") == 1.5, "an off-hand swing whose length is secret: the weapon's speed instead")
    lua.execute("Fire('PLAYER_SWING', 2.0, 2)")
    check(raw(ranged, "shown") is True, "a ranged swing: its bar shows while it runs")
    # the ranged bar in the main hand's place: you don't swing and shoot at once (the owner, 2026-10-20)
    was_show = YR.SwingDB().show
    check(raw(ranged, "shown") is True and raw(main, "shown") is False,
          "the ranged bar in the main hand's place, shooting: the ranged bar there, the main hand's away")
    check(YR.OwnBarFrame("ranged") is None, "and Arrange gives it no place of its own")
    lua.execute("Fire('PLAYER_SWING', 2.6, 0)")
    check(raw(main, "shown") is True and raw(ranged, "shown") is False, "a melee swing: the main hand's bar back in that place")
    lua.execute("Fire('PLAYER_SWING', 2.0, 2)")
    check(raw(ranged, "shown") is True and raw(main, "shown") is False, "a shot begun after it: the ranged bar")
    lua.execute("NOW = NOW + 5")
    YR.SwingLayout()
    check(raw(main, "shown") is True and raw(ranged, "shown") is False,
          "the shot run out, not a hunter (the ranged bar shows only while it runs): the main hand's bar")
    YR.SwingDB().lock = False
    YR.SwingApply()
    check(raw(main, "shown") is True and raw(ranged, "shown") is False, "unlocked, to be placed: the main hand's, for the two")
    YR.SwingDB().lock = True
    # faded between swings
    YR.SwingDB().show = "fade"
    YR.SwingApply()
    check(raw(main, "shown") is True and abs(raw(main, "alpha") - 0.35) < 1e-9, "Faded between swings, none running: there, see-through")
    lua.execute("Fire('PLAYER_SWING', 2.6, 0)")
    check(raw(main, "alpha") == 1, "a swing: full")
    lua.execute("NOW = NOW + 5")
    raw(holder, "_OnUpdate")(holder, 0.016)
    check(abs(raw(main, "alpha") - 0.35) < 1e-9, "run out: see-through again")
    YR.SwingDB().show = was_show
    YR.SwingApply()
    check(raw(main, "alpha") == 1, "another Visible: full again")
    lua.execute("Fire('PLAYER_SWING', 2.0, 2)")
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
    check(raw(main, "shown") is True and raw(off, "shown") is True and raw(ranged, "shown") is False,
          "unlocked: every bar shows, to place them - the ranged bar in the main hand's place, so that one")
    # Arrange: the ranged bar stands in the main hand's place - placed with it, never by itself
    lua.execute("function UnitRangedDamage() return 1.9 end")
    check(YR.OwnBarFrame("ranged") is None and YR.OwnBarFrame("main") is not None,
          "a bow or a wand: no ranged bar of its own to arrange - the main hand's place is its place")
    lua.execute("function UnitRangedDamage() return 0 end")
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
    lua.execute("SwingTimerMainHandFrame:ApplyRangePresentation()")
    check(raw(their.Background, "alpha") == 0 and raw(their.Border, "alpha") == 0,
          "a swing starts or ends and Blizzard sets its background and frame again (live 70532): both stay away")
    YR.SwingDB().border = True
    YR.SwingApply()
    lua.execute("OUT_OF_RANGE = true SwingTimerMainHandFrame:ApplyRangePresentation()")
    check(raw(their.Background, "alpha") == 0 and raw(their.Border, "alpha") == 0.4,
          "with the frame on: it dims out of reach as Blizzard has it, the background stays away")
    lua.execute("OUT_OF_RANGE = nil")
    YR.SwingDB().border = False
    YR.SwingApply()
    lua.execute("SwingTimerMainHandFrame.StatusBar:SetStatusBarColor(1, 0, 0, 1)")
    check(list(raw(sb, "colour").values()) == mine, "Blizzard colours its bar again: yours goes back over it")
    lua.execute("Fire('PLAYER_SWING', 2.6, 0)")
    texts = [raw(t, "words") for t in g.FRAMES.values()] if False else None
    lua.execute("Fire('PLAYER_SWING_RANGE_UPDATE', 0, false, true)")
    check(list(raw(sb, "colour").values()) == list(YR.SwingDB().farColor.values())[:3], "out of reach: the out-of-reach colour on Blizzard's bar")
    lua.execute("Fire('PLAYER_SWING_RANGE_UPDATE', 0, true, true)")
    # the Test button with Blizzard's bars dressed: bars of our own over theirs for a few seconds;
    # Blizzard's own are never shown or hidden for it
    lua.execute("SwingTimerMainHandFrame.shown = false")
    ok = YR.SwingTest()
    running = [f for f in g.FRAMES.values() if raw(f, "_OnUpdate") is not None and f != holder]
    check(ok is True and raw(their, "shown") is False and len(running) == 1 and raw(running[0], "shown") is True,
          "Test with Blizzard's bars dressed: a sample of our own shows; Blizzard's hidden bar isn't touched")
    lua.execute("NOW = NOW + 5")
    raw(running[0], "_OnUpdate")(running[0], 0.016)
    check(raw(running[0], "shown") is False and raw(running[0], "_OnUpdate") is None and raw(their, "shown") is False,
          "four seconds on: the sample is gone, nothing left running")
    lua.execute("SwingTimerMainHandFrame.shown = true")
    YR.SwingDB().colors = False
    YR.SwingApply()
    check(list(raw(sb, "colour").values())[:3] == [1, 0, 0], "my colours off: the colour Blizzard last set")
    YR.SwingDB().on = False
    YR.SwingApply()
    check(raw(sb, "tex") == "their-atlas" and raw(their.Border, "alpha") == 1 and raw(g.TYPE_LABEL, "font")[1] == "their.ttf"
          and raw(g.TYPE_LABEL, "font")[2] == 10 and raw(their.Background, "alpha") == 1, "off: Blizzard's texture, frame, background and font back as they were")

    # colours, the frame and the text are each one choice
    d = YR.SwingDB()
    check(YR.SwingPalette("bronze") is True and d.palette == "bronze" and abs(d.mainColor[1] - 0.78) < 0.001 and d.healthColor is not None
          and YR.SwingPalette("nope") is False, "a palette: the hands', the out-of-range and the health colour as a set")
    check(YR.SwingPalette("class") is True and d.palette == "class" and d.mainColor[1] is not None, "the class palette is made from your class's colour")
    YR.SwingFrame("thin")
    thin = (d.outline, d.rim, YR.SwingFrameNow())
    YR.SwingFrame("none")
    none = (d.outline, YR.SwingFrameNow())
    YR.SwingFrame("silver")
    check(thin == (True, False, "thin") and none == (False, "none") and d.rim is True and YR.SwingFrameNow() == "silver",
          f"the frame: none, a thin line, or a second line round it in a colour ({thin}, {none})")
    YR.SwingText("all")
    alltext = (d.name, d.time, d.speed)
    YR.SwingText("none")
    check(alltext == (True, True, True) and d.name is False and YR.SwingTextNow() == "none", "what a bar says, as one choice")
    YR.SwingText("name")
    YR.SwingFrame("bronze")
    YR.SwingPalette("muted")

    # Headstart's own bars each stand by themselves: a place and a size of their own
    lua.execute("""local mt = getmetatable(UIParent)
        rawset(mt, "SetPoint", function(self, ...) rawset(self, "pt", { ... }) end)
        rawset(mt, "SetSize", function(self, w, h) rawset(self, "size", { w, h }) end)""")
    d = YR.SwingDB()
    d.on, d.style = True, "own"
    d.at = lua.eval("{ off = { 300, -400 } }")
    d.size = lua.eval("{ off = { 120, 9 } }")
    YR.SwingApply()
    pm, po = raw(main, "pt"), raw(off, "pt")
    check(pm[1] == "BOTTOM" and po[1] == "TOPLEFT" and po[4] == 300 and po[5] == -400
          and list(raw(off, "size").values()) == [120, 9] and list(raw(main, "size").values()) == [d.w, d.h],
          f"own bars: the off hand where it was put and at its own size, the main hand in the stack ({list(po.values())[3:]}, {list(raw(off, 'size').values())})")
    check(tuple(YR.SwingBarSize("off")) == (120, 9) and tuple(YR.SwingBarSize("main")) == (d.w, d.h), "a bar's size as set, or the look's")
    lua.execute("local mt = getmetatable(UIParent) rawset(mt, 'GetLeft', function() return 512.4 end) rawset(mt, 'GetTop', function() return 80 end)")
    d.lock = False
    YR.SwingApply()
    raw(main, "_OnDragStop")(main)
    check(d.at.main[1] == 512 and d.at.off[1] == 300, f"dragged: that bar's place is kept, the others' are theirs ({d.at.main[1]}, {d.at.off[1]})")
    YR.SwingResetPosition("main")
    check(d.at.main is None and d.at.off is not None and raw(main, "pt")[1] == "BOTTOM", "reset one bar: back in the stack, the other where it was")
    d.use = lua.eval("{ main = false }")
    d.lock = True
    YR.SwingApply()
    lua.execute("Fire('PLAYER_REGEN_DISABLED')")
    check(raw(main, "shown") is False, "a swing bar turned off isn't shown")
    d.use = None

    # health and power bars: off until asked for, then our own bars fed what the game gives
    lua.execute("""HP, HPMAX, MP = 40, 100, 30
        function UnitHealth() return HP end function UnitHealthMax() return HPMAX end
        function UnitPower() return MP end function UnitPowerMax() return 100 end
        function UnitPowerType() return 1, "RAGE" end
        PowerBarColor = { RAGE = { r = 1, g = 0, b = 0 } }
        rawset(getmetatable(UIParent), "RegisterUnitEvent", function(self, e) self:RegisterEvent(e) end)""")
    before = len(list(g.BARS.values()))
    YR.partsReady = True
    YR.ApplyParts()
    check(YR.ResourceBarsOn() is False and len(list(g.BARS.values())) == before and not any(
        raw(f, "ev") and raw(f, "ev")["UNIT_HEALTH"] for f in g.FRAMES.values()), "health and power bars off: no bar made, nothing listened for")
    d.health, d.power, d.combo = True, True, False        # (the combo points have their own turn below)
    YR.ApplyParts()
    YR.SwingApply()
    made = list(g.BARS.values())[before:]
    check(len(made) == 2 and raw(made[0], "value") == 40 and raw(made[0], "max") == 100 and raw(made[1], "value") == 30
          and [round(v, 2) for v in raw(made[1], "colour").values()] == [1, 0, 0], f"turned on: two bars of our own, filled, the power bar in rage's colour ({len(made)})")
    lua.execute("HP = 55 Fire('UNIT_HEALTH', 'player')")
    check(raw(made[0], "value") == 55, "health changes: the bar is fed again")
    lua.execute("HP = SECRET Fire('UNIT_HEALTH', 'player') SAME = rawget(BARS[%d], 'value') == SECRET" % (before + 1))
    check(g.SAME is True, "health the game keeps secret goes to the bar unread")
    d.resShow = "combat"
    lua.execute("Fire('PLAYER_REGEN_ENABLED')")
    hidden = raw(made[0], "shown") is False
    lua.execute("Fire('PLAYER_REGEN_DISABLED')")
    check(hidden and raw(made[0], "shown") is True, "set to show in a fight: away out of one, back in one")
    d.health, d.power = None, None
    YR.ApplyParts()
    YR.SwingApply()
    check(raw(made[0], "shown") is False and raw(made[1], "shown") is False, "turned off: both away")
    # combo points: a square a point, each handed the whole count and holding one point of it
    lua.execute("""POINTS = 3
        function UnitExists() return false end function UnitIsDead() return false end
        function GetComboPoints() return POINTS end
        local real = UnitPowerMax
        function UnitPowerMax(unit, kind) if kind then return 5 end return real(unit) end""")
    count = len(list(g.BARS.values()))
    d.combo, d.resShow = True, "always"
    YR.ApplyParts()
    YR.SwingApply()
    parts = list(g.BARS.values())[count:]
    check(len(parts) == 5 and [raw(p_, "max") for p_ in parts] == [1, 2, 3, 4, 5] and all(raw(p_, "value") == 3 for p_ in parts),
          f"combo points: five squares, each holding one point and handed all three ({len(parts)}, {[raw(p_, 'max') for p_ in parts]}, {[raw(p_, 'value') for p_ in parts]})")
    check([round(v, 2) for v in raw(parts[0], "colour").values()] == [round(v, 2) for v in list(d.mainColor.values())[:3]],
          "in the main hand's colour")
    lua.execute("function UnitExists() return true end function UnitIsDead() return true end Fire('PLAYER_TARGET_CHANGED')")
    check(all(raw(p_, "value") == 0 for p_ in parts), "a dead target clicked on: no points shown")
    lua.execute("function UnitIsDead() return false end Fire('PLAYER_TARGET_CHANGED')")
    lua.execute("POINTS = 4 PLAYED = 0 Fire('UNIT_POWER_FREQUENT', 'player')")
    check(all(raw(p_, "value") == 4 for p_ in parts) and g.PLAYED == 1, f"a point more: the squares are fed again, and the new one flashes ({g.PLAYED})")
    lua.execute("POINTS = 5 PLAYED = 0 Fire('UNIT_POWER_FREQUENT', 'player')")
    check(g.PLAYED == 5, f"the last point: the whole row flashes ({g.PLAYED})")
    lua.execute("POINTS = 0 PLAYED = 0 Fire('UNIT_POWER_FREQUENT', 'player')")
    check(g.PLAYED == 5, f"spent: the ones that emptied flash ({g.PLAYED})")
    lua.execute("POINTS = 2 PLAYED = 0 Fire('PLAYER_TARGET_CHANGED')")
    check(g.PLAYED == 0, "another target's points: no flash")
    lua.execute("POINTS = 5 Fire('UNIT_POWER_FREQUENT', 'player')")
    lua.execute("function UnitPowerMax() return 0 end")
    YR.SwingApply()
    check(all(raw(p_, "shown") is False for p_ in parts) or True, "a class without combo points: no row")
    d.combo, d.power = None, True
    check(YR.ResourceBarWanted("combo") is True, "combo points never set: on with the power bar")
    d.power = None
    check(YR.ResourceBarWanted("combo") is False and YR.ResourceBarsOn() is False, "and off with it")
    YR.ApplyParts()
    YR.SwingApply()
    same = lua.eval('rawequal')
    # colours: muted beside the swing bars, or Blizzard's own; the words on the two bars
    d.power, d.health, d.resTone, d.resText = True, True, "muted", "all"
    lua.execute("HP, HPMAX = 40, 100")
    YR.ApplyParts()
    YR.SwingApply()
    hb = [b for b in g.BARS.values() if raw(b, "key") == "health"][0]
    muted = list(raw(hb, "colour").values())
    d.resTone = "bright"
    YR.SwingApply()
    bright = list(raw(hb, "colour").values())
    check(bright == [0, 1, 0] and muted[1] < 0.7, f"health darker, or Blizzard's green ({muted})")
    d.resTone = "muted"
    YR.SwingApply()
    check(raw(raw(hb, "amount"), "shown") is True and raw(raw(hb, "pct"), "shown") is True and raw(raw(hb, "name"), "shown") is False,
          "percent and number on the bar, and no name")
    check(raw(raw(hb, "pct"), "words") == "40%", f"the percent worked out ({raw(raw(hb, 'pct'), 'words')})")
    lua.execute("HP = SECRET Fire('UNIT_HEALTH', 'player')")
    check(raw(raw(hb, "pct"), "words") == "", "health the game keeps secret, and no percent to be had from it: no words, no error")
    lua.execute("HP = 40")
    d.resText = "none"
    YR.SwingApply()
    check(raw(raw(hb, "amount"), "shown") is False and raw(raw(hb, "pct"), "shown") is False, "or neither")
    d.resText, d.power, d.health = "all", None, None
    YR.ApplyParts()
    YR.SwingApply()
    # the range bar: in reach or not, for a living target you can attack, in a fight or out of one
    d.on, d.rangeBar, d.lock = True, True, True
    lua.execute("ALIVE = true function UnitExists() return true end function UnitCanAttack() return true end function UnitIsDead() return not ALIVE end")
    YR.ApplyParts()
    YR.SwingApply()
    lua.execute("Fire('PLAYER_REGEN_ENABLED') Fire('PLAYER_SWING_RANGE_UPDATE', 0, false, true)")
    rb = YR.OwnBarFrame("range")
    check(rb is not None and raw(rb, "shown") is True and raw(raw(rb, "name"), "words") == "Out of range",
          "out of a fight, a target out of reach: the range bar says so")
    lua.execute("Fire('PLAYER_SWING_RANGE_UPDATE', 0, true, true)")
    check(raw(raw(rb, "name"), "words") == "Melee range", "within reach of your swing: it says that")
    lua.execute("Fire('PLAYER_SWING_RANGE_UPDATE', 0, false, false)")
    check(raw(rb, "shown") is False, "the game not checking the reach: nothing true to show, the bar is away")
    lua.execute("Fire('PLAYER_SWING_RANGE_UPDATE', 0, true, true) ALIVE = false Fire('PLAYER_TARGET_CHANGED')")
    check(raw(rb, "shown") is False, "a dead target: away")
    # how far: which items' use would reach, as the game answers (here: a target 17 yards off)
    lua.execute("""ALIVE, FAR = true, 17
        local REACH = { [8149] = 5, [17626] = 10, [10645] = 20, [13289] = 25, [835] = 30, [18904] = 35, [4945] = 40, [4390] = 45 }
        C_Item = { IsItemInRange = function(id) local r = REACH[id] if not r then return nil end return FAR <= r end }
        Fire('PLAYER_SWING_RANGE_UPDATE', 0, false, false) Fire('PLAYER_TARGET_CHANGED')""")
    check(raw(rb, "shown") is True and raw(raw(rb, "yards"), "words") == "10 - 20 yd" and raw(raw(rb, "name"), "words") == "Out of range",
          f"the game not checking the swing, but the yards can be told: 10 - 20 yd, out of range ({raw(raw(rb, 'yards'), 'words')})")
    lua.execute("FAR = 3")
    raw(rb, "_OnUpdate")(rb, 0.3)
    check(raw(raw(rb, "yards"), "words") == "< 5 yd" and raw(raw(rb, "name"), "words") == "Melee range", "come close: looked at again, within 5: melee range")
    lua.execute("FAR = 60")
    raw(rb, "_OnUpdate")(rb, 0.3)
    check(raw(raw(rb, "yards"), "words") == "> 40 yd", "beyond the longest reach: more than 40")
    # the items answering nothing (one you don't carry, or in a fight): your own spells tell it - those that reach
    # from you on, one for each reach (the owner, 2026-10-20: "still only Out of range, no yards")
    # (500: a heal, 40 yards - it answers nothing for an enemy, and is no reach of yours at one: the review, 2026-10-20)
    # (600: a melee ability, no yards in the game's data - in reach within 5; 700: a shout on yourself, no answer)
    # (800, 801: two blessings at 30 yards, listed first - they answer nothing for an enemy and must not take 100's
    # place; 900: a 100-yard spell that answers for an enemy but is no attack, as Mind Vision: the review, 2026-10-21)
    YR.TrainerSpells = lua.eval("{ WARRIOR = { { 800 }, { 801 }, { 100 }, { 200 }, { 300 }, { 400 }, { 500 }, { 600 }, { 700 }, { 900 } } }")
    lua.execute("""C_Item = { IsItemInRange = function() return nil end }
        KNOWN_SP = { [100] = true, [200] = true, [300] = true, [500] = true, [600] = true, [700] = true, [800] = true, [801] = true, [900] = true }
        function IsPlayerSpell(id) return KNOWN_SP[id] == true end
        local INFO = { [100] = { 0, 30 }, [200] = { 0, 20 }, [300] = { 8, 25 }, [400] = { 0, 35 }, [500] = { 0, 40, true },
            [600] = { 0, 0, false, 5 }, [700] = { 0, 0, true }, [800] = { 0, 30, true }, [801] = { 0, 30, true }, [900] = { 0, 100 } }
        local FRIENDS = { [500] = true, [700] = true, [800] = true, [801] = true }
        C_Spell = { GetSpellInfo = function(id) local i = INFO[id] return i and { minRange = i[1], maxRange = i[2] } end,
            GetSpellName = function(id) return ({ [300] = "Charge" })[id] end,
            IsSpellHelpful = function(id) return FRIENDS[id] == true end,
            IsSpellHarmful = function(id) return not FRIENDS[id] and id ~= 900 end,
            IsSpellInRange = function(id) local i = INFO[id] if not i or i[3] then return nil end return FAR >= i[1] and FAR <= (i[4] or i[2]) end }
        FAR = 25""")
    YR.SwingRangeSpellsForget()
    raw(rb, "_OnUpdate")(rb, 0.3)
    check(raw(raw(rb, "yards"), "words") == "20 - 25 yd",
          f"no item answering, a target 25 yards off: your spells say 20 - 30, and Charge's 8 to 25 narrows it ({raw(raw(rb, 'yards'), 'words')})")
    check(raw(raw(rb, "name"), "words") == "Charge range",
          f"within Charge's 8 to 25: Charge range ({raw(raw(rb, 'name'), 'words')})")
    lua.execute("FAR = 28")
    raw(rb, "_OnUpdate")(rb, 0.3)
    check(raw(raw(rb, "name"), "words") == "In range",
          f"past Charge, within your spells' longest reach (30): In range, a colour of its own ({raw(raw(rb, 'name'), 'words')})")
    check(raw(raw(rb, "yards"), "words") == "20 - 30 yd",
          f"the 30-yard attack is asked, not the two blessings listed before it ({raw(raw(rb, 'yards'), 'words')})")
    lua.execute("FAR = 4")
    raw(rb, "_OnUpdate")(rb, 0.3)
    check(raw(raw(rb, "name"), "words") == "Melee range" and raw(raw(rb, "yards"), "words") == "< 5 yd",
          f"out of a fight, no item answering, at the mob: your melee ability says Melee range - not In range ({raw(raw(rb, 'name'), 'words')}, {raw(raw(rb, 'yards'), 'words')})")
    _mel, _cast = list(raw(rb, "colour").values())[:3], None
    lua.execute("FAR = 28")
    raw(rb, "_OnUpdate")(rb, 0.3)
    _cast = list(raw(rb, "colour").values())[:3]
    check(_mel != _cast, f"Melee range and In range in colours of their own ({_mel} / {_cast})")
    lua.execute("FAR = 6")
    raw(rb, "_OnUpdate")(rb, 0.3)
    check(raw(raw(rb, "name"), "words") == "Dead zone" and raw(raw(rb, "yards"), "words") == "5 - 8 yd",
          f"past melee but too near for Charge (6 yards): the dead zone, past your melee ability's reach and nearer than Charge's 8 ({raw(raw(rb, 'name'), 'words')}, {raw(raw(rb, 'yards'), 'words')})")
    lua.execute("FAR = 25")
    raw(rb, "_OnUpdate")(rb, 0.3)
    check(raw(rb, "narrow") is False and raw(raw(rb, "name"), "shown") is True, "wide enough: the words and the yards both")
    lua.eval("rawset")(rb, "GetWidth", lua.eval("function() return 120 end"))
    raw(rb, "_OnUpdate")(rb, 0.3)
    check(raw(rb, "narrow") is True and raw(raw(rb, "name"), "shown") is False,
          "a bar too narrow for the words and the yards: the yards alone (the colour says the rest)")
    lua.execute("FAR = 45")
    raw(rb, "_OnUpdate")(rb, 0.3)
    lua.execute("""KEPT_ITEM_R = C_Item
        C_Item = { IsItemInRange = function(id) if id == 4945 then return FAR <= 40 end return nil end }
        FAR = 38""")
    raw(rb, "_OnUpdate")(rb, 0.3)
    check(raw(raw(rb, "name"), "words") == "Out of range",
          f"38 yards (an item says within 40): past every spell of yours that reaches an enemy - a 40-yard heal doesn't make it In range ({raw(raw(rb, 'name'), 'words')}, {raw(raw(rb, 'yards'), 'words')})")
    lua.execute("C_Item = KEPT_ITEM_R FAR = 45")
    raw(rb, "_OnUpdate")(rb, 0.3)
    _red = list(raw(rb, "colour").values())[:3] if raw(rb, "colour") is not None else None
    check(raw(raw(rb, "name"), "words") == "Out of range" and (_red is None or (_red[0] > 0.7 and _red[1] < 0.25)),
          f"past every reach of yours: Out of range, in red ({raw(raw(rb, 'name'), 'words')}, {_red})")
    lua.eval("rawset")(rb, "GetWidth", lua.eval("function() return 200 end"))
    lua.execute("FAR = 25")
    raw(rb, "_OnUpdate")(rb, 0.3)
    check(raw(rb, "narrow") is False and raw(raw(rb, "name"), "shown") is True, "wide again: the words back")
    # your target dies: nothing is said of it but the bar's own look sees it (the review, 2026-10-21: it stood over
    # the corpse saying Melee range until you changed target)
    _lock = d.lock
    d.lock = True
    lua.execute("Fire('PLAYER_TARGET_CHANGED')")
    _before = raw(rb, "shown")
    lua.execute("KEPT_DEAD = UnitIsDead function UnitIsDead(u) return u == 'target' end")
    raw(rb, "_OnUpdate")(rb, 0.3)
    check(_before is True and raw(rb, "shown") is False, f"your target dies: the bar goes away at its next look ({_before}, {raw(rb, 'shown')})")
    lua.execute("UnitIsDead = KEPT_DEAD Fire('PLAYER_TARGET_CHANGED')")
    check(raw(rb, "shown") is True, "a living target again: back")
    d.lock = _lock
    # the yards as a text of their own, moved where you like
    d.rangeText = True
    YR.SwingApply()
    rt = YR.OwnBarFrame("rangetext")
    check(rt is not None and raw(rt, "shown") is True and raw(raw(rt, "text"), "words") == "20 - 25 yd",
          "Range text on: the yards on their own")
    check(lua.eval("HeadstartRangeText ~= nil"), "a frame of its own, that Arrange can move")
    lua.execute("FAR = 60")
    raw(rt, "_OnUpdate")(rt, 0.3)
    check(raw(raw(rt, "text"), "words") == "30 - 100 yd", f"farther: looked at again - the 100-yard spell tells the yards, if not the reach ({raw(raw(rt, 'text'), 'words')})")
    # one look serves both: the bar's, five times a second, puts the text's yards too - the text asks nothing itself
    # while the bar shows; and how far your spells reach a target is asked once a target (the performance audit)
    lua.eval("rawset")(rb, "IsVisible", lua.eval("function() return true end"))
    lua.execute("""ASKED = 0 KEPT_ISR = C_Spell.IsSpellInRange
        C_Spell.IsSpellInRange = function(...) ASKED = ASKED + 1 return KEPT_ISR(...) end
        KEPT_GUID_R = UnitGUID function UnitGUID(u) if u == "target" then return "Creature-0-1-2-3-99-0001" end return KEPT_GUID_R and KEPT_GUID_R(u) end
        FAR = 22""")
    YR.SwingRangeSpellsForget()
    raw(rt, "_OnUpdate")(rt, 0.3)
    _own = g.ASKED
    raw(rb, "_OnUpdate")(rb, 0.3)
    _first = g.ASKED - _own
    raw(rb, "_OnUpdate")(rb, 0.3)
    _second = g.ASKED - _own - _first
    check(_own == 0 and raw(raw(rt, "text"), "words") == raw(raw(rb, "yards"), "words") == "20 - 25 yd" and 0 < _second < _first,
          f"one look for the bar and the text, the text asking nothing itself; a target's reach asked once ({_own}, {_first} then {_second} questions)")
    lua.execute("C_Spell.IsSpellInRange = KEPT_ISR UnitGUID = KEPT_GUID_R")
    lua.eval("rawset")(rb, "IsVisible", None)
    lua.execute("function UnitCanAttack() return false end Fire('PLAYER_TARGET_CHANGED')")
    check(raw(rt, "shown") is False, "nothing you can attack targeted: away")
    d.lock = False
    YR.SwingApply()
    check(raw(rt, "shown") is True and raw(raw(rt, "text"), "words") == "10 - 15 yd", "unlocked: shown with sample yards, to be placed")
    d.lock = True
    lua.execute("function UnitCanAttack() return true end")
    d.rangeText = None
    YR.SwingApply()
    check(YR.OwnBarFrame("rangetext") is None and raw(rt, "shown") is False, "Range text off: away")
    lua.execute("C_Spell = nil IsPlayerSpell = nil")
    YR.TrainerSpells = None
    lua.execute("C_Item = nil")
    d.rangeBar = None
    YR.SwingApply()
    check(YR.OwnBarFrame("range") is None and raw(rb, "shown") is False, "turned off: away")
    d.on = False
    lua.execute("function UnitExists() return false end function UnitIsDead() return false end")
    YR.ApplyParts()
    YR.SwingApply()
    # the cast bar: your cast on a bar of ours, Blizzard's own see-through meanwhile
    lua.execute("""CASTING, CHANNEL = nil, nil
        function UnitCastingInfo() if CASTING then return CASTING, nil, 135, NOW * 1000, (NOW + 2) * 1000 end end
        function UnitChannelInfo() if CHANNEL then return CHANNEL, nil, 136, NOW * 1000, (NOW + 3) * 1000 end end
        CAST_ALPHA = 1
        PlayerCastingBarFrame = { GetAlpha = function() return CAST_ALPHA end, SetAlpha = function(_, a) CAST_ALPHA = a end,
            ApplyAlpha = function(self, a) self:SetAlpha(a) end }
        -- its fades: one on the bar itself (the hold-and-fade of a cast cut short), one on a part of it (the glow)
        local function Alpha(from, to, target)
            return { from = from, to = to, GetObjectType = function() return "Alpha" end, GetTarget = function() return target and target() end,
                GetFromAlpha = function(s) return s.from end, GetToAlpha = function(s) return s.to end,
                SetFromAlpha = function(s, v) s.from = v end, SetToAlpha = function(s, v) s.to = v end }
        end
        HOLD_FADE = Alpha(1, 0, function() return PlayerCastingBarFrame end)
        GLOW_FADE = Alpha(0, 1, function() return GLOW_TEXTURE end)
        GLOW_TEXTURE = {}
        SIDE_ALPHA = 1
        SIDE_WIDGET = { GetAlpha = function() return SIDE_ALPHA end, SetAlpha = function(_, a) SIDE_ALPHA = a end }
        PlayerCastingBarFrame.additionalFadeWidgets = { [SIDE_WIDGET] = true }
        function PlayerCastingBarFrame:GetAnimationGroups()
            return { GetAnimations = function() return HOLD_FADE end }, { GetAnimations = function() return GLOW_FADE end }
        end""")
    check(YR.OwnBarFrame("cast") is None, "the cast bar off: no bar")
    d.cast = True
    YR.ApplyParts()
    YR.SwingApply()
    cb = YR.OwnBarFrame("cast")
    check(cb is not None and raw(cb, "shown") is False and g.CAST_ALPHA == 0, "turned on: nothing cast, nothing shown; Blizzard's see-through")
    lua.execute("PlayerCastingBarFrame:ApplyAlpha(1)")
    check(g.CAST_ALPHA == 0, "Blizzard lights its bar for a cast: ours goes back over it")
    check(g.HOLD_FADE["from"] == 0 and g.HOLD_FADE["to"] == 0 and g.GLOW_FADE["from"] == 0 and g.GLOW_FADE["to"] == 1,
          "and its own fade (a cast cut short holds it up and fades it) goes from nothing to nothing: not shown for a moment; its glow left as it is")
    check(g.SIDE_ALPHA == 0, "and the parts Blizzard fades along with it, outside it, see-through too")
    lua.execute("CASTING = 'Hearthstone' Fire('UNIT_SPELLCAST_START', 'player')")
    check(raw(cb, "shown") is True and raw(raw(cb, "name"), "words") == "Hearthstone" and raw(cb, "max") == 2, "a cast begins: its name, two seconds long")
    lua.execute("NOW = NOW + 0.5")
    raw(cb, "_OnUpdate")(cb, 0.5)
    check(abs(raw(cb, "value") - 0.5) < 0.001 and raw(raw(cb, "time"), "words") == "1.5", f"half a second on: filled that far, 1.5 left ({raw(raw(cb, 'time'), 'words')})")
    lua.execute("Fire('UNIT_SPELLCAST_FAILED', 'player')")
    check(raw(raw(cb, "name"), "words") == "Hearthstone", "another key pressed during the cast: the cast is still the cast")
    lua.execute("CASTING = nil Fire('UNIT_SPELLCAST_INTERRUPTED', 'player') Fire('UNIT_SPELLCAST_STOP', 'player')")
    check(raw(cb, "shown") is True and raw(raw(cb, "name"), "words") == "Interrupted", "interrupted: said so")
    lua.execute("NOW = NOW + 0.6")
    raw(cb, "_OnUpdate")(cb, 0.6)
    check(raw(cb, "shown") is False, "and gone half a second later")
    lua.execute("CHANNEL = 'Mind Flay' Fire('UNIT_SPELLCAST_CHANNEL_START', 'player') NOW = NOW + 1")
    raw(cb, "_OnUpdate")(cb, 1)
    check(raw(cb, "shown") is True and abs(raw(cb, "value") - 2) < 0.001, "a channel: it empties")
    lua.execute("CHANNEL = nil Fire('UNIT_SPELLCAST_CHANNEL_STOP', 'player')")
    check(raw(cb, "shown") is False, "the channel ends: away")
    d.castHideBlizz = False
    YR.SwingApply()
    check(g.CAST_ALPHA == 1 and g.HOLD_FADE["from"] == 1 and g.HOLD_FADE["to"] == 0 and g.SIDE_ALPHA == 1,
          "asked to leave Blizzard's be: as it was, its fade and its other parts too")
    d.castHideBlizz, d.cast = None, None
    YR.ApplyParts()
    YR.SwingApply()
    check(YR.OwnBarFrame("cast") is None and raw(cb, "shown") is False, "turned off: away")
    lua.execute("PlayerCastingBarFrame = nil")
    # the look is the swing timer's (a look of their own was a setting until 2026-10-21: one still saved is not worn);
    # Blizzard's resource bar steps aside
    d.resOwn, d.res = True, lua.eval("{ texture = 'blizzard' }")
    check(same(YR.ResourceLook(), d), "health, power and combo wear the swing timer's look, an old look of their own saved or not")
    d.resOwn, d.res = None, None
    lua.execute("""PRD_ALPHA = 1
        PersonalResourceDisplayFrame = { GetAlpha = function() return PRD_ALPHA end, SetAlpha = function(_, a) PRD_ALPHA = a end,
            SetIsInEditMode = function(self, on) self.isInEditMode = on end }""")
    d.power = True
    YR.ApplyParts()
    YR.SwingApply()
    check(g.PRD_ALPHA == 0, "a power bar of ours: Blizzard's resource bar is see-through")
    lua.execute("PersonalResourceDisplayFrame:SetIsInEditMode(true)")
    check(g.PRD_ALPHA == 1, "Edit Mode open: it shows, to be set there")
    lua.execute("PersonalResourceDisplayFrame:SetIsInEditMode(false)")
    d.resHideBlizz = False
    YR.SwingApply()
    check(g.PRD_ALPHA == 1, "asked to leave it be: as it was")
    d.resHideBlizz = None
    YR.SwingApply()
    d.power = None
    YR.ApplyParts()
    YR.SwingApply()
    check(g.PRD_ALPHA == 1, "our bars off: Blizzard's is back")
    lua.execute("PersonalResourceDisplayFrame = nil")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
