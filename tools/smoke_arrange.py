"""Smoke test of Arrange (Arrange.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_arrange.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Nothing made until it is opened; a handle over each element that exists; an arrow key moves the picked
one a step (ten with Shift) and has the element keep its place by its own drag-stop script; a drag
snaps to the grid and to the other elements; not in a fight, and a fight closes it.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
MADE, COMBAT, SHIFT, SAID = 0, false, false, {}
local F = {}
F.__index = function(t, k) return rawget(F, k) or function() end end
function F:SetPoint(p, rel, rp, x, y)
    if type(x) == "number" then rawset(self, "l", x) rawset(self, "t", y) end
end
function F:GetLeft() return rawget(self, "l") end
function F:GetTop() return rawget(self, "t") end
function F:SetSize(w, h) rawset(self, "w", w) rawset(self, "h", h) end
function F:GetWidth() return rawget(self, "w") or 0 end
function F:GetHeight() return rawget(self, "h") or 0 end
function F:GetEffectiveScale() return rawget(self, "scale") or 1 end
function F:GetFrameLevel() return 1 end
function F:Show() rawset(self, "shown", true) end
function F:Hide() rawset(self, "shown", false) end
function F:IsShown() return rawget(self, "shown") == true end
function F:SetScript(w, fn) rawset(self, "_" .. w, fn) end
function F:GetScript(w) return rawget(self, "_" .. w) end
function F:RegisterEvent(e) rawset(self, "event", e) end
function F:UnregisterEvent() rawset(self, "event", nil) end
function F:SetPropagateKeyboardInput(on) rawset(self, "passes", on) end
function F:CreateTexture() return setmetatable({}, F) end
function F:CreateFontString() return setmetatable({}, F) end
function F:SetLabel(t) rawset(self, "label", t) end
function F:SetText(t) rawset(self, "words", t) end
function F:SetEnabled(on) rawset(self, "enabled", on) end
function CreateFrame(kind, name) MADE = MADE + 1 local f = setmetatable({}, F) if name then _G[name] = f end return f end
UIParent = setmetatable({ l = 0, t = 1000, w = 1600, h = 1000 }, F)
function InCombatLockdown() return COMBAT end
CURSOR = { 0, 0 }
function GetCursorPosition() return CURSOR[1], CURSOR[2] end
function IsShiftKeyDown() return SHIFT end
YippRouteDB = {}
YR = { Print = function(m) SAID[#SAID + 1] = m end, Style = { FONT = "f", C = { accent = { 1, 0.5, 0.2, 1 } },
    Fill = function() end, Border = function() return { Color = function() end } end,
    Text = function() return setmetatable({}, F) end,
    Button = function(_, _, fn) local b = setmetatable({}, F) rawset(b, "click", fn) return b end,
    Input = function(_, opts) local b = setmetatable({}, F) rawset(b, "opts", opts) return b end } }
function F:SetValue(v) rawset(self, "value", v) end
XP = { w = 200, h = 20 }
function YR.XPBarDB() return XP end
function YR.XPBarApply() HeadstartXPBar:SetSize(XP.w, XP.h) end
-- an element: the XP bar, which keeps its place (rounded) when a drag of its own ends
function Element(name, l, t, w, h)
    local f = setmetatable({ l = l, t = t, w = w, h = h }, F)
    f:SetScript("OnDragStop", function(self)
        rawset(self, "kept", { math.floor(self:GetLeft() + 0.5), math.floor(self:GetTop() + 0.5) })
    end)
    _G[name] = f
    return f
end
''')
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok   " if ok else "FAIL ") + what)
        if not ok:
            bad += 1

    src = open(os.path.join(ROOT, "Arrange.lua"), encoding="utf-8").read()
    lua.eval("function(src) local f = assert(loadstring(src, 'Arrange.lua')) f('Headstart', YR) end")(src)
    YR = g.YR
    raw = lua.eval("rawget")
    check(g.MADE == 0, "loaded: no frame made")
    check(YR.ArrangeOpen() is False and g.MADE > 0 and "Nothing to arrange" in g.SAID[1], "nothing on: said so, and not opened")
    xp = g.Element("HeadstartXPBar", 400, 300, 200, 20)
    loot = g.Element("HeadstartLootFeed", 900, 600, 100, 50)
    g.COMBAT = True
    check(YR.ArrangeOpen() is False and "fight" in g.SAID[2], "in a fight: not opened")
    g.COMBAT = False
    check(YR.ArrangeOpen() is True and raw(g.HeadstartArrange, "shown") is True and raw(g.HeadstartArrange, "event") == "PLAYER_REGEN_DISABLED",
          "opened: shown, and a fight is listened for")
    key = raw(g.HeadstartArrange, "_OnKeyDown")
    key(g.HeadstartArrange, "RIGHT")
    check(raw(xp, "l") == 400 and raw(g.HeadstartArrange, "passes") is True, "an arrow with nothing picked: the game's key, nothing moved")
    # the handles, out of Arrange.lua's own list
    find = lua.eval("""function()
        local found = {}
        local i = 1
        while true do
            local n, v = debug.getupvalue(YR.ArrangeOpen, i)
            if not n then break end
            if n == "handles" then for _, h in ipairs(v) do found[h.item[1]] = h end end
            i = i + 1
        end
        return found
    end""")()
    hx, hl = find["XP bar"], find["Loot feed"]
    check(hx is not None and raw(hx, "shown") is True and raw(hx, "l") == 400 and raw(hx, "w") == 200
          and raw(find["Camp icon"], "shown") is False, "a handle over each element that exists, none for one that doesn't")
    raw(hx, "_OnClick")(hx)
    key(g.HeadstartArrange, "RIGHT")
    check(raw(xp, "l") == 401 and raw(xp, "t") == 300 and list(raw(xp, "kept").values()) == [401, 300]
          and raw(g.HeadstartArrange, "passes") is False, "picked, arrow right: one step, kept by the element's own script")
    g.SHIFT = True
    key(g.HeadstartArrange, "UP")
    g.SHIFT = False
    check(raw(xp, "t") == 310 and raw(hx, "t") == 310, "Shift and arrow up: ten steps, the handle with it")
    # a drag let go: near nothing, so onto the grid (16, out from the middle of the screen: 800, 500)
    raw(hx, "_OnDragStart")(hx)
    lua.eval("function(h) rawset(h, 'l', 207) rawset(h, 't', 441) end")(hx)
    raw(hx, "_OnDragStop")(hx)
    check(raw(xp, "l") == 208 and raw(xp, "t") == 436, f"dropped: onto the grid ({raw(xp, 'l')}, {raw(xp, 't')})")
    # near another element's edge: to that, not the grid
    raw(hx, "_OnDragStart")(hx)
    lua.eval("function(h) rawset(h, 'l', 897) rawset(h, 't', 700) end")(hx)
    raw(hx, "_OnDragStop")(hx)
    check(raw(xp, "l") == 900, f"dropped near another element's left edge: lined up with it ({raw(xp, 'l')})")
    g.YippRouteDB.arrange.snap = False
    raw(hx, "_OnDragStart")(hx)
    lua.eval("function(h) rawset(h, 'l', 333) rawset(h, 't', 222) end")(hx)
    raw(hx, "_OnDragStop")(hx)
    check(raw(xp, "l") == 333 and raw(xp, "t") == 222, "snap off: where it was dropped")
    # the small window: where it is and how large, typed in
    panel = raw(g.HeadstartArrange, "panel")
    check(raw(panel, "shown") is True and raw(raw(panel, "x"), "value") == 333 and raw(raw(panel, "w"), "value") == 200,
          "picked: a window with its place and size")
    raw(raw(panel, "x"), "opts").onCommit("512")
    raw(raw(panel, "y"), "opts").onCommit("640")
    check(raw(xp, "l") == 512 and raw(xp, "t") == 640 and list(raw(xp, "kept").values()) == [512, 640], "x and y typed in: there, and kept")
    raw(raw(panel, "w"), "opts").onCommit("320")
    raw(raw(panel, "h"), "opts").onCommit("999")
    check(g.XP.w == 320 and g.XP.h == 40 and raw(hx, "w") == 320, f"width and height typed in: set, within what the bar allows ({g.XP.w}, {g.XP.h})")
    raw(raw(panel, "x"), "opts").onCommit("nonsense")
    check(raw(xp, "l") == 512, "not a number: nothing moved")
    raw(hl, "_OnClick")(hl)
    raw(raw(panel, "w"), "opts").onCommit("50")
    check(raw(loot, "w") == 100 and raw(raw(panel, "w"), "enabled") is False, "an element with no size to set: its size left alone")
    # anchors: the XP bar dragged over the loot feed and held there, then let go
    at = (raw(loot, "l"), raw(loot, "t"))
    raw(hx, "_OnDragStart")(hx)
    lua.eval("function(h, x, y) rawset(h, 'l', x - 10) rawset(h, 't', y + 5) CURSOR = { x + 5, y - 5 } end")(hx, at[0], at[1])
    raw(hx, "_OnUpdate")(hx, 0.1)
    check(g.YippRouteDB.arrange.anchor["XP bar"] is None, "held a moment over another: not yet")
    raw(hx, "_OnUpdate")(hx, 0.4)
    raw(hx, "_OnUpdate")(hx, 0.4)
    raw(hx, "_OnDragStop")(hx)
    check(g.YippRouteDB.arrange.anchor["XP bar"] == "Loot feed", "held over it, then let go: anchored to it")
    before = (raw(xp, "l"), raw(xp, "t"))
    raw(hl, "_OnClick")(hl)
    g.SHIFT = True
    key(g.HeadstartArrange, "LEFT")
    key(g.HeadstartArrange, "DOWN")
    g.SHIFT = False
    check(raw(loot, "l") == at[0] - 10 and raw(xp, "l") == before[0] - 10 and raw(xp, "t") == before[1] - 10
          and list(raw(xp, "kept").values()) == [before[0] - 10, before[1] - 10], "the one it hangs on moved: it goes along, and keeps its place")
    # the other way round would be a ring: not offered
    raw(hl, "_OnDragStart")(hl)
    lua.eval("function(x, y) CURSOR = { x + 5, y - 5 } end")(raw(xp, "l"), raw(xp, "t"))
    raw(hl, "_OnUpdate")(hl, 0.1)
    raw(hl, "_OnUpdate")(hl, 1.0)
    raw(hl, "_OnDragStop")(hl)
    check(g.YippRouteDB.arrange.anchor["Loot feed"] is None, "anchoring the one it hangs on back to it: not offered")
    raw(hx, "_OnClick")(hx)
    raw(raw(panel, "release"), "click")()
    spot = raw(xp, "l")
    raw(hl, "_OnClick")(hl)
    key(g.HeadstartArrange, "RIGHT")
    check(g.YippRouteDB.arrange.anchor["XP bar"] is None and raw(xp, "l") == spot, "released: it stays where it is when the other moves")
    raw(hx, "_OnClick")(hx)
    key(g.HeadstartArrange, "A")
    check(raw(g.HeadstartArrange, "passes") is True, "any other key is the game's")
    raw(g.HeadstartArrange, "_OnEvent")(g.HeadstartArrange, "PLAYER_REGEN_DISABLED")
    check(raw(g.HeadstartArrange, "shown") is False and raw(g.HeadstartArrange, "event") is None, "a fight begins: closed, nothing listened for")
    check(YR.ArrangeToggle() is True and YR.ArrangeToggle() is False and raw(g.HeadstartArrange, "shown") is False, "toggled open and shut")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
