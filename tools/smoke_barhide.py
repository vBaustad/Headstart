"""Smoke test of hiding Blizzard's bag bar and micro menu (BarHide.lua), in Lua 5.1 (lupa).

    python tools/smoke_barhide.py      (exit code 1 on any failure; tools/smoke.py runs it too)

As Blizzard has it nothing is touched. Hidden: see-through, and its buttons out of the mouse's way
(after a fight when in one). Under the mouse: see-through until the mouse is over it, looked at on a
ticker that only runs in that mode. Edit Mode shows both. Back to Blizzard's: everything as it was.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r"""
FRAMES = {}
local F = {}
F.__index = F
function F:RegisterEvent(e) self.ev = self.ev or {} self.ev[e] = true end
function F:SetScript(_, fn) self.fn = fn end
function F:SetAlpha(a) self.alpha = a self.sets = (self.sets or 0) + 1 end
function F:GetAlpha() return self.alpha or 1 end
function F:IsMouseOver() return self.over or false end
function F:IsMouseEnabled() return self.mouse ~= false end
function F:EnableMouse(on) self.mouse = on and true or false end
function F:GetChildren() return unpack(self.kids or {}) end
function New(kids) return setmetatable({ kids = kids }, F) end
function F:Show() self.shown = true if self.onShow then self.onShow(self) end end
function F:Hide() self.shown = false end
function F:IsShown() return self.shown ~= false end
function F:HookScript(w, fn)
    if w == "OnShow" then self.onShow = fn end
    self.hooks = self.hooks or {}
    self.hooks[w] = self.hooks[w] or {}
    table.insert(self.hooks[w], fn)
end
function Run(f, w) for _, fn in ipairs(f.hooks and f.hooks[w] or {}) do fn(f) end end
ChatFrame1ButtonFrame, ChatFrame2ButtonFrame, QuickJoinToastButton = New(), New(), New()
QuickJoinToastButton.shown = false
function F:GetLeft() return self.l end
function F:GetRight() return self.r end
function F:GetTop() return self.t end
function F:GetBottom() return self.b end
function F:SetClampRectInsets(l, r, t, b) self.clamp = { l, r, t, b } end
function F:UpdateClampOffsets() self.clamp = { -35, 0, 20, -10 } end
function hooksecurefunc(t, name, fn) local old = t[name] t[name] = function(...) old(...) fn(...) end end
ChatFrame1 = New()
ChatFrame1.l, ChatFrame1.r, ChatFrame1.t, ChatFrame1.b = 40, 440, 300, 100
ChatFrame1.Selection = New()
ChatFrame1.Selection.l, ChatFrame1.Selection.r, ChatFrame1.Selection.t, ChatFrame1.Selection.b = 5, 440, 320, 90
ChatFrame1.buttonSide = "left"
function F:SetWidth(w) self.width = w end
function F:SetSize(w, h) self.size = { w, h } end
function F:GetSize() local z = self.size or { 32, 32 } return z[1], z[2] end
function F:GetRegions() return unpack(self.regions or {}) end
function F:IsObjectType(kind) return kind == "Texture" end
function F:SetPoint() end
function F:SetVertexColor() end
function F:SetTexture() end
function F:SetTexCoord() end
ICONS = 0
function F:CreateTexture() ICONS = ICONS + 1 local t = New() self.regions = self.regions or {} table.insert(self.regions, t) return t end
ChatFrameMenuButton = New()
function F:SetScale(v) self.scale = v end
function F:GetScale() return self.scale or 1 end
MENU_ART = New()
ChatFrameMenuButton.regions = { MENU_ART }
function CreateFrame() local f = New() table.insert(FRAMES, f) return f end
function Fire(e, ...) for _, f in ipairs(FRAMES) do if f.ev and f.ev[e] and f.fn then f.fn(f, e, ...) end end end
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
floor = math.floor
YippRouteDB = {}
function print() end
COMBAT = false
function InCombatLockdown() return COMBAT end
TICKERS = 0
C_Timer = { NewTicker = function(_, fn) TICKERS = TICKERS + 1 TICK = fn return { Cancel = function() TICKERS = TICKERS - 1 TICK = nil end } end }
CALLBACKS = {}
EventRegistry = { RegisterCallback = function(_, name, fn) CALLBACKS[name] = fn end }
BAG1, BAG2, DEAD = New(), New(), New()
DEAD.mouse = false
BagsBar = New({ BAG1, BAG2, DEAD })
MICRO = New()
MicroMenuContainer = New({ New({ MICRO }) })
""")
    YR = lua.table()
    YR.Style = lua.eval("{ ArtTexture = function() end }")
    for f in ("Core.lua", "BarHide.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    YR.StartBarHide()
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    lua.execute("Fire('PLAYER_ENTERING_WORLD')")
    check(g.BagsBar.sets is None and g.MicroMenuContainer.sets is None and g.TICKERS == 0,
          "as Blizzard has them: neither bar is touched, and nothing runs")
    YR.SetBarHide("bagBar", "hide")
    check(g.BagsBar.alpha == 0 and g.BAG1.mouse is False and g.BAG2.mouse is False and g.TICKERS == 0,
          "bag bar hidden: see-through, its buttons out of the mouse's way, and still nothing running")
    check(g.MicroMenuContainer.sets is None, "the micro menu is left alone")
    YR.SetBarHide("bagBar", "show")
    check(g.BagsBar.alpha == 1 and g.BAG1.mouse is True and g.DEAD.mouse is False,
          "back to Blizzard's: shown, its buttons clickable again - and one that never took the mouse still doesn't")
    YR.SetBarHide("microMenu", "hover")
    check(g.MicroMenuContainer.alpha == 0 and g.MICRO.mouse is not False and g.TICKERS == 1,
          "micro menu under the mouse: see-through, its buttons still there, and one ticker running")
    lua.execute("MicroMenuContainer.over = true TICK()")
    check(g.MicroMenuContainer.alpha == 1, "the mouse over it: shown")
    sets = g.MicroMenuContainer.sets
    lua.execute("TICK() TICK()")
    check(g.MicroMenuContainer.sets == sets, "and not set again while nothing changes")
    lua.execute("MicroMenuContainer.over = false TICK()")
    check(g.MicroMenuContainer.alpha == 0, "the mouse off it: see-through again")
    lua.execute("CALLBACKS['EditMode.Enter']()")
    check(g.MicroMenuContainer.alpha == 1, "Edit Mode open: shown, to see what you place")
    lua.execute("CALLBACKS['EditMode.Exit']()")
    check(g.MicroMenuContainer.alpha == 0, "Edit Mode closed: as you picked")
    lua.execute("COMBAT = true")
    YR.SetBarHide("microMenu", "hide")
    check(g.MicroMenuContainer.alpha == 0 and g.MICRO.mouse is not False and g.TICKERS == 0,
          "hidden in a fight: see-through at once, the buttons' mouse left for after; the ticker stopped")
    lua.execute("COMBAT = false Fire('PLAYER_REGEN_ENABLED')")
    check(g.MICRO.mouse is False, "the fight over: its buttons out of the mouse's way")
    # the chat's buttons: the strip slim or hidden, the two buttons over it hidden
    check(g.ChatFrame1ButtonFrame.shown is not False and g.ChatFrame1ButtonFrame.width is None, "the chat's buttons are left alone until asked")
    g.YippRouteDB.chatStrip = "slim"
    YR.BarHideApply()
    check(g.ChatFrame1ButtonFrame.width == 18 and g.ChatFrame1ButtonFrame.shown is not False
          and list(g.ChatFrameMenuButton.size.values()) == [18, 18] and g.MENU_ART.alpha == 0 and g.ICONS >= 1,
          "slim: the strip at 18 wide, the chat menu button small with our icon in place of its art")
    lua.execute("PUSHED = New() table.insert(ChatFrameMenuButton.regions, PUSHED) Run(ChatFrameMenuButton, 'OnMouseDown')")
    check(g.PUSHED.alpha == 0, "pressed, and Blizzard makes its pressed picture: that one is cleared too")
    check(list(g.ChatFrame1.clamp.values()) == [-23, 0, 20, -10], f"and the chat window may go that much closer to the edge ({list(g.ChatFrame1.clamp.values())})")
    check(abs(g.QuickJoinToastButton.scale - 18 / 32) < 0.001, "and the social button over it is made small to fit")
    g.YippRouteDB.chatStrip = "hide"
    YR.BarHideApply()
    check(g.ChatFrame1ButtonFrame.shown is False and g.ChatFrame2ButtonFrame.shown is False and g.ChatFrame1ButtonFrame.width == 29
          and list(g.ChatFrameMenuButton.size.values()) == [32, 32] and g.MENU_ART.alpha == 1,
          "hidden: every window's strip is gone, and the button is as Blizzard had it")
    check(g.QuickJoinToastButton.scale == 1, "the social button at its own size again")
    check(list(g.ChatFrame1.clamp.values()) == [0, 0, 20, -10], "and the chat window may go to the edge on the buttons' side")
    lua.execute("ChatFrame1:UpdateClampOffsets()")
    check(list(g.ChatFrame1.clamp.values()) == [0, 0, 20, -10], "Edit Mode sets its limit again: ours goes back over it")
    lua.execute("ChatFrame1ButtonFrame:Show() QuickJoinToastButton:Show()")
    check(g.ChatFrame1ButtonFrame.shown is False and g.QuickJoinToastButton.shown is True,
          "the game shows the strip again: hidden again - the social button is its own switch")
    g.YippRouteDB.chatSocialHide = True
    YR.BarHideApply()
    check(g.QuickJoinToastButton.shown is False, "the social button hidden")
    g.YippRouteDB.chatStrip, g.YippRouteDB.chatSocialHide = None, None
    YR.BarHideApply()
    check(g.ChatFrame1ButtonFrame.shown is True and g.QuickJoinToastButton.shown is True and g.ChatFrame2ButtonFrame.shown is True,
          "off: the ones we hid are back")
    check(list(g.ChatFrame1.clamp.values()) == [-35, 0, 20, -10], "and the chat window's limit is Edit Mode's own again")
    g.YippRouteDB.qolOff = True
    YR.BarHideApply()
    check(g.MicroMenuContainer.alpha == 1 and g.MICRO.mouse is True, "quality of life off: Blizzard's own again")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
