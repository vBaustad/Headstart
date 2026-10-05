"""Smoke test of the RestedXP skins (RXPSkin.lua) against a fake RestedXP, in Lua 5.1 (lupa).

    python tools/smoke_rxpskin.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Without RestedXP nothing happens. With it: both themes are handed over with every colour RestedXP
asks for; picking a look sets RestedXP's theme and remembers the one before; the border's size is
ours while a look is on and RestedXP's own again after; the banners take the accent; a new accent
(or the class colour) is in the theme at once.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r'''
local Obj = {}
Obj.__index = function(t, k) return rawget(Obj, k) or function() return setmetatable({}, Obj) end end
function Obj:SetColorTexture(r, g, b, a) rawset(self, "colour", { r, g, b, a }) rawset(self, "atlas", nil) end
function Obj:SetAtlas(name) rawset(self, "atlas", name) end
function Obj:SetTexture(path) rawset(self, "file", path) rawset(self, "atlas", nil) end
function Obj:SetShown(on) rawset(self, "shown", on and true or false) end
function Obj:Show() rawset(self, "shown", true) end
function Obj:Hide() rawset(self, "shown", false) end
function Obj:SetAlpha(a) rawset(self, "alpha", a) end
function Obj:SetSize(w, h) rawset(self, "size", { w, h }) end
function Obj:SetPoint(...) local p = rawget(self, "points") or {} p[#p + 1] = { ... } rawset(self, "points", p) end
function Obj:ClearAllPoints() rawset(self, "points", {}) end
function Obj:SetVertexColor(r, g, b, a) rawset(self, "tint", { r, g, b, a }) end
function Obj:GetSize() local s = rawget(self, "size") or { 18, 24 } return s[1], s[2] end
function Obj:GetFrameLevel() return 5 end
function Obj:SetBackdropColor(r, g, b, a) rawset(self, "fillAlpha", a) end
function Obj:SetBackdropBorderColor(r, g, b, a) rawset(self, "edgeAlpha", a) rawset(self, "edgeColour", { r, g, b }) end
ATLASES = { ["heavybronze-frame-background"] = true, ["heavybronze-frame-basic"] = true }
LAYOUT = { TopLeftCorner = { x = -8, y = 16 }, TopRightCorner = { x = 4, y = 16 }, BottomLeftCorner = { x = -8, y = -3 } }
NineSliceUtil = {
    GetLayout = function(name) return name == "ButtonFrameTemplateNoPortrait" and LAYOUT or nil end,
    ApplyLayoutByName = function(frame, name) rawset(frame, "layout", name) end,
}
function Obj:SetHeight(h) rawset(self, "height", h) end
function Obj:SetMaxLines(n) rawset(self, "maxLines", n) end
function Obj:GetMinMaxValues() return rawget(self, "lo") or 0, rawget(self, "hi") or 0 end
function Obj:GetValue() return rawget(self, "value") or 0 end
function Obj:SetValue(v) rawset(self, "value", v) local f = rawget(self, "hookOnValueChanged") if f then f(self, v) end end
function Obj:HookScript(w, fn) rawset(self, "hook" .. w, fn) end
function Obj:GetHeight() return 200 end
function Obj:GetParent() return New() end
function Obj:EnableMouse(on) rawset(self, "mouse", on and true or false) end
function Obj:SetScrollPercentage(p) rawset(self, "percent", p) end
function Obj:SetVisibleExtentPercentage(p) rawset(self, "extent", p) end
function Obj:RegisterCallback(_, fn) rawset(self, "onScroll", fn) end
C_Texture = { GetAtlasInfo = function(name) return ATLASES[name] and {} or nil end }
function Obj:SetTextColor(r, g, b) rawset(self, "text", { r, g, b }) end
function Obj:RegisterEvent() end
function Obj:SetScript(w, fn) rawset(self, "_" .. w, fn) end
function New() return setmetatable({}, Obj) end
function CreateFrame(_, _, _, template)
    if template == "MinimalScrollBar" and not SLIM_OK then error("no such template") end
    local f = New()
    if template == "SettingsFrameTemplate" then NINE = f end
    if template == "MinimalScrollBar" then SLIM = f end
    return f
end
BaseScrollBoxEvents = { OnScroll = "OnScroll" }
ScrollBoxConstants = { NoScrollInterpolation = true }
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
floor = math.floor
YippRouteDB = {}
function print() end
function UnitClass() return "Paladin", "PALADIN" end
RAID_CLASS_COLORS = { PALADIN = { r = 0.96, g = 0.55, b = 0.73 } }
GameFontNormal = { GetFont = function() return "Fonts\FRIZQT__.TTF" end }
function hooksecurefunc(t, name, fn)
    local old = t[name]
    t[name] = function(...) local a, b = old(...) fn(...) return a, b end
end
function MakeRXP()
    RENDERS = 0
    RXP = { themes = {}, settings = { profile = { activeTheme = "RXP Green" } }, v2 = {} }
    local frame = { backdrop = {
        edge = { edgeSize = 8, insets = { left = 4, right = 2, top = 2, bottom = 4 } },
        guideName = { edgeSize = 8, insets = { left = 4, right = 2, top = 2, bottom = 4 } } } }
    frame.GuideName, frame.Footer, frame.BottomFrame = New(), New(), New()
    for _, part in ipairs({ frame.GuideName, frame.Footer }) do rawset(part, "bg", New()) rawset(part, "text", New()) end
    rawset(frame.Footer, "cog", New())
    MENUS = 0
    function frame.DropDownMenu() MENUS = MENUS + 1 end
    rawset(frame.GuideName, "icon", New()) rawset(frame.GuideName, "classIcon", New())
    frame.CurrentStepFrame = New()
    local box = New()
    rawset(box, "number", New())
    rawset(frame.CurrentStepFrame, "framePool", { box })
    function RXP.SetStep() end
    THUMB = New()
    local bar = New()
    rawset(bar, "ScrollUpButton", New()) rawset(bar, "ScrollDownButton", New())
    rawset(bar, "GetThumbTexture", function() return THUMB end)
    frame.ScrollFrame = New()
    rawset(frame.ScrollFrame, "ScrollBar", bar)
    function frame:UpdateVisuals() end
    RXP.RXPFrame = frame
    function RXP:RegisterTheme(theme) self.themes[theme.name] = theme end
    function RXP:LoadActiveTheme() self.activeTheme = self.themes[self.settings.profile.activeTheme] end
    function RXP.RenderFrame() RENDERS = RENDERS + 1 RXP:LoadActiveTheme() RXP.RXPFrame:UpdateVisuals() end
    function RXP.SetupGuideWindow() end
end
'''


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    YR = lua.table()
    for f in ("Core.lua", "RXPSkin.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    YR.Style = lua.eval("{ FONT = 'x', ArtTexture = function(tex, name) rawset(tex, 'art', name) end }")
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    YR.StartRXPSkin()
    check(YR.RXPSkinMode() == "off" and not YR.SetRXPSkin("headstart") and not YR.RXPSkinAvailable(),
          "no RestedXP: nothing to skin, no error")
    lua.execute("MakeRXP()")
    YR.StartRXPSkin()
    themes = g.RXP.themes
    need = ("name", "author", "background", "bottomFrameBG", "bottomFrameHighlight", "mapPins", "tooltip", "texturePath",
            "headerTexture", "font", "textColor", "bgTextures", "edges")
    check(all(themes[n] is not None and all(themes[n][k] is not None for k in need) for n in ("Headstart", "Blizzard")),
          "both themes handed to RestedXP, with everything it asks of a theme")
    check(g.RENDERS == 0 and g.RXP.RXPFrame.backdrop.edge.edgeSize == 8, "RestedXP's own theme on: its window isn't touched")
    check(YR.SetRXPSkin("headstart") and g.RXP.settings.profile.activeTheme == "Headstart" and g.YippRouteDB.rxpSkinPrev == "RXP Green",
          "Headstart picked: RestedXP's theme set, the one before remembered")
    edge = g.RXP.RXPFrame.backdrop.edge
    check(edge.edgeSize == 1 and edge.insets.left == 1 and g.RENDERS >= 1, f"the border a thin line, and the window drawn again ({edge.edgeSize})")
    raw = lua.eval("function(o, k) return rawget(o, k) end")
    f = g.RXP.RXPFrame
    check(raw(f.GuideName, "fillAlpha") == 0 and raw(f.BottomFrame, "edgeAlpha") == 0 and raw(f.Footer, "edgeAlpha") == 0,
          "RestedXP's own fills and edges on the header, the list and the footer are clear")
    thumb = raw(g.THUMB, "colour")
    check(thumb is not None and abs(thumb[1] - 0.40) < 0.01 and raw(g.THUMB, "size")[1] == 4,
          "the scroll bar: a slim thumb in the accent")
    check(raw(f.ScrollFrame.ScrollBar.ScrollUpButton, "alpha") == 0, "and its end buttons out of sight")
    check(raw(f.GuideName.icon, "shown") is False and raw(f.GuideName.classIcon, "size")[1] == 44 and raw(f.CurrentStepFrame, "points")[1][5] == 15,
          "the logo a small badge inside the frame, and the steps you're on lifted clear of it")
    menu = raw(f.GuideName, "headstartMenu")
    raw(menu, "_OnClick")(menu)
    check(g.MENUS == 1 and raw(menu, "shown") is True and raw(f.Footer.cog, "shown") is False,
          "the class icon alone in the header is the menu button; RestedXP's logo and its cog are put away")
    # RestedXP puts the step boxes back in its own place (a reload, a moved window): we go after it
    lua.execute("local s = RXP.RXPFrame.CurrentStepFrame s:ClearAllPoints() s:SetPoint('BOTTOMLEFT', RXP.RXPFrame.GuideName, 'TOPLEFT', 0, 2) s:SetPoint('BOTTOMRIGHT', RXP.RXPFrame.GuideName, 'TOPRIGHT', 0, 2)")
    pts = raw(f.CurrentStepFrame, "points")
    check(len(pts) == 2 and pts[1][5] == 15 and pts[2][5] == 15, f"RestedXP places the step boxes itself: put clear of our frame again ({pts[1][5]}, {pts[2][5]})")
    lua.execute("rawset(RXP.RXPFrame.CurrentStepFrame, 'anchor', 'BOTTOM') RXP.RXPFrame.CurrentStepFrame:SetPoint('TOPLEFT', RXP.RXPFrame, 'BOTTOMLEFT', 3, 0)")
    pts = raw(f.CurrentStepFrame, "points")
    check(pts[1][1] == "TOPLEFT" and pts[1][5] == -13, f"set to sit under the window: clear of our frame there too ({pts[1][5]})")
    lua.execute("rawset(RXP.RXPFrame.CurrentStepFrame, 'anchor', nil)")
    YR.RXPSkinPaint()
    rim = raw(f.GuideName, "headstartRim")
    check(rim is not None and abs(raw(rim, "tint")[1] - 0.40) < 0.01, "the class icon's rim in the accent")
    banner = raw(f.GuideName.bg, "colour")
    check(banner is not None and banner[4] == 0, "RestedXP's banner is clear: no wash over the header")
    g.YippRouteDB.rxpSkinAccent = lua.eval("{ 1, 0.5, 0.2 }")
    YR.RXPSkinApply()
    pins = g.RXP.themes.Headstart.mapPins
    check(abs(pins[1] - 1) < 0.01 and abs(pins[2] - 0.5) < 0.01 and g.RXP.themes.Headstart.tooltip == "|cFFFF8033",
          f"a new accent: in the theme at once ({g.RXP.themes.Headstart.tooltip})")
    g.YippRouteDB.rxpSkinClass = True
    YR.RXPSkinApply()
    check(abs(g.RXP.themes.Headstart.mapPins[2] - 0.55) < 0.01, "the class colour as the accent")
    YR.SetRXPSkin("blizzard")
    check(YR.RXPSkinMode() == "blizzard" and edge.edgeSize == 12 and g.YippRouteDB.rxpSkinPrev == "RXP Green",
          "Blizzard picked: the game's border size, and the theme before is still RestedXP's")
    t = raw(f.GuideName.text, "text")
    check(t is not None and abs(t[2] - 0.82) < 0.01, "the title in gold")
    check(abs(raw(raw(f.GuideName, "headstartRim"), "tint")[1] - 0.64) < 0.01, "the class icon's rim in the Blizzard look's bronze")
    win = raw(g.NINE, "points")
    check(raw(g.NINE, "shown") is True and win[1][4] == -7 and win[1][5] == 1 and win[2][4] == 3 and win[2][5] == -3,
          "Blizzard's settings-window frame round it, out by its own border (7 left, 3 right and under)")
    check(raw(f.GuideName, "height") == 20 and raw(f.GuideName.text, "maxLines") == 1 and raw(f.GuideName.icon, "shown") is False and raw(f.GuideName.classIcon, "size")[1] == 44,
          "the header is the window's title strip: lower, the name on one line, the logo and class icon the same badge as in the Headstart look")
    check(raw(f.ScrollFrame, "points")[1][4] == -13, "the list starts under the title strip, not behind it")
    check(raw(f.CurrentStepFrame, "points")[1][5] == 11, "and the steps you're on just clear of it")
    lua.execute("ATLASES['common-insideframe'] = true")
    YR.RXPSkinForgetArt()
    YR.RXPSkinPaint()
    lua.execute("RXP.SetStep()")
    box = g.RXP.RXPFrame.CurrentStepFrame.framePool[1]
    check(raw(box.headstartPanel, "atlas") == "common-insideframe" and raw(box.headstartPanel, "shown") is True and raw(box, "edgeAlpha") == 0,
          "a step box: Blizzard's inner panel round it, its own edge clear")
    tab = raw(box.number, "edgeColour")
    check(tab is not None and abs(tab[1] - 0.64) < 0.01, "the small tab with the step's number: its plain edge, in the panel's colour")
    check(raw(g.THUMB, "atlas") is None and raw(g.THUMB, "file") == "Interface\\Buttons\\UI-ScrollBar-Knob"
          and raw(f.ScrollFrame.ScrollBar.ScrollUpButton, "alpha") == 1,
          "Blizzard's new scroll art isn't on this (fake) client: its classic scroll bar instead, buttons and all")
    lua.execute("ATLASES['minimal-scrollbar-small-thumb-middle'] = true")
    YR.RXPSkinForgetArt()
    YR.RXPSkinPaint()
    check(raw(g.THUMB, "atlas") == "minimal-scrollbar-small-thumb-middle", "where the client has it: Blizzard's own thumb")
    YR.SetRXPSkin("off")
    check(g.RXP.settings.profile.activeTheme == "RXP Green" and edge.edgeSize == 8 and edge.insets.left == 4,
          "back to RestedXP's own: its theme and its border size again")
    check(raw(f.ScrollFrame.ScrollBar.ScrollUpButton, "alpha") == 1 and raw(g.THUMB, "size")[1] == 18,
          "and its scroll bar: the end buttons back, the thumb its own size")
    check(raw(box.headstartPanel, "shown") is False and raw(box.headstartFill, "shown") is False, "and the step boxes: our panel and fill gone")
    check(raw(f.ScrollFrame, "points")[1][4] == -5, "and the list where RestedXP has it")
    check(raw(f.GuideName, "height") == 35 and raw(f.GuideName.text, "maxLines") == 0, "its header its own height again, both lines")
    check(raw(f.GuideName.icon, "shown") is True and raw(f.GuideName.classIcon, "size")[1] == 24 and raw(f.Footer.cog, "shown") is True and raw(f.CurrentStepFrame, "points")[1][5] == 2,
          "and its logo and the steps where RestedXP has them")
    return bad + slim()


def slim():
    """A client that can make Blizzard's slim scroll bar."""
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    lua.execute("SLIM_OK = true MakeRXP()")
    YR = lua.table()
    for f in ("Core.lua", "RXPSkin.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    YR.Style = lua.eval("{ FONT = 'x', ArtTexture = function(tex, name) rawset(tex, 'art', name) end }")
    g = lua.globals()
    raw = lua.eval("function(o, k) return rawget(o, k) end")
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    YR.StartRXPSkin()
    old = g.RXP.RXPFrame.ScrollFrame.ScrollBar
    lua.execute("local b = RXP.RXPFrame.ScrollFrame.ScrollBar rawset(b, 'lo', 100) rawset(b, 'hi', 500) rawset(b, 'value', 200)")
    YR.SetRXPSkin("blizzard")
    check(g.SLIM is not None and raw(g.SLIM, "shown") is True and raw(old, "alpha") == 0 and raw(old, "mouse") is False,
          "a client with Blizzard's slim scroll bar: that one shown, RestedXP's out of sight and out of the mouse's way")
    check(abs(raw(g.SLIM, "percent") - 0.25) < 0.001 and abs(raw(g.SLIM, "extent") - 200 / 600) < 0.001,
          f"it shows where RestedXP's bar is: a quarter down, a third of the list in view ({raw(g.SLIM, 'percent')})")
    raw(g.SLIM, "onScroll")(g.SLIM, 0.5)
    check(raw(old, "value") == 300, f"dragged to the middle: RestedXP's bar is set to its middle ({raw(old, 'value')})")
    lua.execute("RXP.RXPFrame.ScrollFrame.ScrollBar:SetValue(500)")
    check(raw(g.SLIM, "percent") == 1, "RestedXP scrolls its own (a new step): ours follows")
    YR.SetRXPSkin("headstart")
    check(raw(g.SLIM, "shown") is False and raw(old, "alpha") == 1 and raw(old, "mouse") is True,
          "another look: Blizzard's bar away, RestedXP's back")
    # RestedXP's two small windows (Active Items, Active Targets) take the step boxes' look
    lua.execute("""
function InCombatLockdown() return false end
ATLASES["common-insideframe"] = true
ITEMS, TARGETS = New(), New()
for _, f in ipairs({ ITEMS, TARGETS }) do
    local t = New() rawset(t, "text", New()) rawset(f, "title", t)
    rawset(f, "UpdateVisuals", function(self) rawset(self, "redrawn", (rawget(self, "redrawn") or 0) + 1) end)
end
RXP.activeItemFrame = ITEMS
RXP.targeting = { activeTargetFrame = TARGETS }
""")
    YR.RXPSkinForgetArt()
    YR.SetRXPSkin("blizzard")
    for name, f in (("Active Items", g.ITEMS), ("Active Targets", g.TARGETS)):
        panel = raw(f, "headstartPanel")
        check(panel is not None and raw(panel, "atlas") == "common-insideframe" and raw(panel, "shown") is True
              and raw(f, "edgeAlpha") == 0 and list(raw(f.title.text, "text").values()) == [1, 0.82, 0],
              f"Blizzard look, {name}: Blizzard's thin panel in place of its edge, the name in gold")
    YR.SetRXPSkin("headstart")
    accent = list(YR.RXPSkinAccent().values())
    check(raw(raw(g.ITEMS, "headstartPanel"), "shown") is False and raw(g.ITEMS, "edgeAlpha") == 0.16
          and list(raw(g.TARGETS.title.text, "text").values()) == accent,
          "Headstart look: a thin quiet line, the name in the accent")
    lua.execute("ITEMS:SetBackdropBorderColor(1, 1, 1, 1) ITEMS:UpdateVisuals()")
    check(raw(g.ITEMS, "edgeAlpha") == 0.16, "RestedXP draws the window again: our look goes back on")
    before = raw(g.ITEMS, "redrawn")
    YR.SetRXPSkin("off")
    check(raw(g.ITEMS, "redrawn") > before and raw(raw(g.ITEMS, "headstartPanel"), "shown") is False,
          "off: ours away, and RestedXP draws its own again")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
