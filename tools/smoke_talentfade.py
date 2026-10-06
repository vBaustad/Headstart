"""Smoke test of the see-through talent window (TalentFade.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_talentfade.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Nothing happens before Blizzard's window is loaded; once it is, the background textures take the fade
and nothing else does; the window's own fill is faded only while the talent page is the one open; the
value is kept between 0 and 100; the slider on the window can be turned off.
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
function Obj:SetShown(on) rawset(self, "shown", on and true or false) end
function Obj:IsShown() return rawget(self, "shown") ~= false end
function Obj:GetFrameLevel() return 100 end
function Obj:SetScale(v) rawset(self, "scale", v) end
function Obj:GetScale() return rawget(self, "scale") or 1 end
function Obj:GetWidth() return 1000 end
function Obj:GetHeight() return 800 end
function Obj:GetEffectiveScale() return 1 end
CURSOR = { 5000, 5000 }
function GetCursorPosition() return CURSOR[1], CURSOR[2] end
function Obj:RegisterEvent(e) rawset(self, "ev", rawget(self, "ev") or {}) self.ev[e] = true end
function Obj:SetScript(w, fn) rawset(self, "_" .. w, fn) end
function Obj:HookScript(w, fn)
    local old = rawget(self, "hook" .. w)
    rawset(self, "hook" .. w, old and function(...) old(...) fn(...) end or fn)
end
function Obj:SetPoint(...) rawset(self, "point", { ... }) end
function Obj:ClearAllPoints() rawset(self, "point", nil) end
function Obj:GetLeft() return 321.4 end
function Obj:GetTop() return 777.6 end
COMBAT = false
function InCombatLockdown() return COMBAT end
function hooksecurefunc(o, name, fn)
    local old = Obj[name]
    rawset(o, name, function(...) old(...) fn(...) end)
end
UIParent = setmetatable({}, Obj)
function New() return setmetatable({}, Obj) end
function CreateFrame() local f = New() table.insert(FRAMES, f) return f end
function Fire(e, ...) for _, f in ipairs(FRAMES) do if rawget(f, "ev") and f.ev[e] and rawget(f, "_OnEvent") then f._OnEvent(f, e, ...) end end end
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
floor = math.floor
YippRouteDB = {}
function print() end
SLIDERS = 0
STYLE = { FONT = "x", C = { sub = { 1, 1, 1 } } }
function STYLE.Text() return New() end
BUTTONS, TAPS = 0, {}
function STYLE.Button(_, label, fn) BUTTONS = BUTTONS + 1 TAPS[label] = fn return New() end
function STYLE.Slider() SLIDERS = SLIDERS + 1 local f = New() rawset(f, "Refresh", function() end) return f end
function Window()
    PlayerSpellsFrame = New()
    for _, k in ipairs({ "Bg", "TopTileStreaks", "NineSlice" }) do rawset(PlayerSpellsFrame, k, New()) end
    local t = New()
    STOPS, PLAYS = 0, 0
    local group = { Stop = function() STOPS = STOPS + 1 PLAYING = false end, Play = function() PLAYS = PLAYS + 1 PLAYING = true end,
        IsPlaying = function() return PLAYING end }
    PLAYING = true
    rawset(t, "backgroundAnims", { group })
    rawset(t, "OverlayBackgroundMid", New())
    for _, k in ipairs({ "Background", "ClassBackground", "BackgroundBorder", "DividerVerticalLeft", "DividerVerticalRight", "DividerHorizontalLeft", "DividerHorizontalRight", "ApplyButton", "ButtonsParent" }) do rawset(t, k, New()) end
    rawset(PlayerSpellsFrame, "TalentsFrame", t)
end
''')
    YR = lua.table()
    for f in ("Core.lua", "Movers.lua", "TalentFade.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    YR.Style = lua.eval("STYLE")
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    g.YippRouteDB.talentFade = 60
    YR.StartTalentFade()
    YR.TalentFadeApply()
    check(g.SLIDERS == 0, "Blizzard's window not loaded yet: nothing built, no error")
    lua.execute("Window() Fire('ADDON_LOADED', 'Some_Other_Addon')")
    check(g.SLIDERS == 0, "another addon loading doesn't hook it")
    lua.execute("Fire('ADDON_LOADED', 'Blizzard_PlayerSpells')")
    w = g.PlayerSpellsFrame
    t = w.TalentsFrame

    raw_has = lua.eval("function(o, k) return rawget(o, k) ~= nil end")

    def near(a, b):
        return a is not None and abs(a - b) < 1e-6

    check(g.SLIDERS == 1 and g.BUTTONS == 4, "the window loaded: the slider and the four size taps are on it")
    check(near(t.Background.alpha, 0.4) and near(t.ClassBackground.alpha, 0.4),
          f"60% see-through: the page's backgrounds at 0.4 ({t.Background.alpha}, {t.ClassBackground.alpha})")
    check(near(w.Bg.alpha, 0.4), f"and the window's own fill ({w.Bg.alpha})")
    glow = lua.eval("function() return rawget(PlayerSpellsFrame.TalentsFrame.OverlayBackgroundMid, 'alpha') end")
    check(g.STOPS >= 1 and g.PLAYING is False and glow() == 0,
          "60% see-through: Blizzard's moving lights are stopped, so nothing glows up through it seconds later")
    YR.SetTalentFade(50)
    check(g.PLAYING is True, "50%: the lights are left to play")
    YR.SetTalentFade(55)
    check(g.PLAYING is False, "55%: stopped")
    YR.SetTalentFade(60)
    raw = lua.eval("function(o) return rawget(o, 'alpha') end")
    check(near(raw(t.BackgroundBorder), 0.4), "the inner frame art (the gold band, the shading) too")
    check(near(raw(t.DividerVerticalLeft), 0.4), "and the dividers")
    check(raw(t.ApplyButton) is None and raw(w.NineSlice) is None, "the buttons and the window's border are left alone")
    # the spellbook's turn: the talent page hidden, the window's fill back
    t.shown = False
    t.hookOnHide(t)
    check(near(w.Bg.alpha, 1), f"the talent page closed: the window's fill is back for the spellbook ({w.Bg.alpha})")
    t.shown = True
    t.hookOnShow(t)
    check(near(w.Bg.alpha, 0.4), "and faded again when the talent page is back")
    YR.SetTalentFade(250)
    check(YR.TalentFade() == 100 and near(t.Background.alpha, 0), f"a value past the end is held at 100 ({YR.TalentFade()})")
    YR.SetTalentFade(0)
    check(near(t.Background.alpha, 1) and near(w.Bg.alpha, 1), "0: Blizzard's own, all back")
    check(g.PLAYING is True and g.PLAYS >= 1, "and the lights play again")
    Lua_fire = lua.eval("function() Fire('PLAYER_ENTERING_WORLD') Fire('ADDON_LOADED', 'Blizzard_PlayerSpells') end")
    Lua_fire()
    check(g.SLIDERS == 1 and g.BUTTONS == 4, "hooked once, however often the events come")
    # size: the talent page's only, never touched at 100, not in combat
    scale = lua.eval("function() return rawget(PlayerSpellsFrame, 'scale') end")
    check(scale() is None, "size at 100: the window's scale is never touched")
    YR.SetTalentScale(80)
    check(near(scale(), 0.8), f"80 percent: the window at 0.8 ({scale()})")
    t.shown = False
    t.hookOnHide(t)
    check(near(scale(), 1), "the talent page closed: the spellbook has its own size back")
    t.shown = True
    lua.execute("COMBAT = true")
    t.hookOnShow(t)
    check(near(scale(), 1), "in combat: not touched")
    lua.execute("COMBAT = false")
    t.hookOnShow(t)
    check(near(scale(), 0.8), "and yours again out of combat")
    g.TAPS["-1"]()
    check(YR.TalentScale() == 79 and near(scale(), 0.79), f"a tap on -1: 79 percent ({YR.TalentScale()})")
    g.TAPS["+5"]()
    check(YR.TalentScale() == 84, "a tap on +5: 84")
    YR.SetTalentScale(400)
    check(YR.TalentScale() == 150, "held at 150 at most")
    YR.SetTalentScale(100)
    check(near(scale(), 1), "100: Blizzard's own again")
    # a new size keeps the window under the mouse: the spot the mouse is on stays put. The fake window
    # is 1000 by 800 with its corner at 321.4, 777.6 (in its own measure) at any size
    YR.SetTalentScale(100)
    lua.execute("CURSOR = { 1221.4, 77.6 }")          # 900 in from the left, 700 down: on the size buttons
    YR.SetTalentScale(50)
    pos = g.YippRouteDB.moved.talents
    check(abs(pos[1] - 771) <= 1 and abs(pos[2] - 428) <= 1,
          f"half the size, the mouse on the buttons: the corner moves so the buttons stay under it ({pos[1]}, {pos[2]})")
    point2 = lua.eval("function() local p = rawget(PlayerSpellsFrame, 'point') return p[4], p[5] end")
    check(abs(point2()[0] - pos[1] / 0.5) < 0.01, "and it's put there in the window's own measure (the screen's, over its size)")
    lua.execute("CURSOR = { 5000, 5000 }")            # the mouse elsewhere: the middle stays
    g.YippRouteDB.moved.talents = None
    YR.SetTalentScale(100)
    pos = g.YippRouteDB.moved.talents
    check(pos is not None, "the mouse off the window: it grows round its middle")
    g.YippRouteDB.moved.talents = None
    lua.execute("PlayerSpellsFrame:ClearAllPoints()")
    # moved: nothing saved, Blizzard's place is left; dragged, it's kept and put back after Blizzard centres it
    point = lua.eval("function() local p = rawget(PlayerSpellsFrame, 'point') return p and p[1], p and p[4], p and p[5] end")
    lua.execute("PlayerSpellsFrame:SetPoint('TOP', UIParent, 'TOP', 0, -41)")
    check(point()[0] == "TOP", "never moved: left where Blizzard puts it")
    handle = [f for f in g.FRAMES.values() if lua.eval("function(f) return rawget(f, '_OnDragStop') ~= nil end")(f)][0]
    lua.eval("function(h) rawget(h, '_OnDragStop')(h) end")(handle)
    pos = g.YippRouteDB.moved.talents
    check(pos[1] == 321 and pos[2] == 778, f"dragged: where you left it is kept ({pos[1]}, {pos[2]})")
    lua.execute("PlayerSpellsFrame:SetPoint('TOP', UIParent, 'TOP', 0, -41)")
    check(tuple(point()) == ("TOPLEFT", 321, 778), f"Blizzard centres it on opening: back to yours ({tuple(point())})")
    # dragged by the talent page itself (anywhere that isn't a button), not only the title bar
    g.YippRouteDB.moved.talents = None
    check(raw_has(t, "hookOnDragStop") and raw_has(w, "hookOnDragStop"), "the window and the talent page can be dragged by")
    lua.eval("function(t) rawget(t, 'hookOnDragStop')(t) end")(t)
    check(g.YippRouteDB.moved.talents is not None and g.YippRouteDB.moved.talents[1] == 321, "dragged by the talent page: kept")
    check(not raw_has(t.ApplyButton, "hookOnDragStop"), "a button is not something to drag by")
    lua.execute("COMBAT = true PlayerSpellsFrame:SetPoint('TOP', UIParent, 'TOP', 0, -41)")
    check(point()[0] == "TOP", "in combat: not touched")
    lua.execute("COMBAT = false")
    g.YippRouteDB.talentMove = False
    lua.execute("PlayerSpellsFrame:SetPoint('TOP', UIParent, 'TOP', 0, -41)")
    check(point()[0] == "TOP", "'Move it' off: Blizzard's place")
    g.YippRouteDB.talentMove = None
    YR.TalentResetPosition()
    check(g.YippRouteDB.moved.talents is None, "Reset: forgotten")
    # the bags: nothing at all until their option is on, then the same, each on its own
    lua.execute("ContainerFrameCombinedBags, ContainerFrame6 = New(), New()")
    YR.StartMovers()
    lua.execute("Fire('PLAYER_ENTERING_WORLD')")
    touched = lua.eval("function(f) return rawget(f, 'hookOnShow') ~= nil or rawget(f, 'SetPoint') ~= nil end")
    check(not touched(g.ContainerFrameCombinedBags) and not touched(g.ContainerFrame6), "bags, options off: neither window is touched")
    g.YippRouteDB.moveBag = True
    lua.execute("COMBAT = true")
    YR.MoverPlace("bag")
    check(not touched(g.ContainerFrameCombinedBags), "turned on in a fight: the window isn't made movable there (it would be blocked)")
    lua.execute("COMBAT = false Fire('PLAYER_REGEN_ENABLED')")
    check(touched(g.ContainerFrameCombinedBags) and not touched(g.ContainerFrame6), "the combined bag turned on: that one only")
    bagpoint = lua.eval("function() local p = rawget(ContainerFrameCombinedBags, 'point') return p and p[1], p and p[4], p and p[5] end")
    handles = [f for f in g.FRAMES.values() if lua.eval("function(f) return rawget(f, '_OnDragStop') ~= nil end")(f)]
    lua.eval("function(h) rawget(h, '_OnDragStop')(h) end")(handles[-1])
    lua.execute("ContainerFrameCombinedBags:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', -10, 90)")
    check(tuple(bagpoint()) == ("TOPLEFT", 321, 778), f"dragged, then Blizzard lays the bags out: back to yours ({tuple(bagpoint())})")
    g.YippRouteDB.moveBag = False
    lua.execute("ContainerFrameCombinedBags:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', -10, 90)")
    check(bagpoint()[0] == "BOTTOMRIGHT", "turned off again: Blizzard's place")
    g.YippRouteDB.moveBag = True
    YR.MoverReset("bag")
    lua.execute("ContainerFrameCombinedBags:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', -10, 90)")
    check(g.YippRouteDB.moved.bag is None and bagpoint()[0] == "BOTTOMRIGHT", "Reset: forgotten, Blizzard's place the next time it's laid out")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
