"""Smoke test of Arrange (Arrange.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_arrange.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Nothing made until it is opened; a handle over each element that exists; an arrow key moves the picked
one a step (ten with Shift) and has the element keep its place by its own drag-stop script; a drag
snaps to the grid and to the other elements, shown as it is dragged, and never partly onto another; let go
over another, a window asks where it goes by it; not in a fight, and a fight closes it.
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
-- only a method (a capital first letter) is made up: a field the addon never set is nil, as in the game
F.__index = function(t, k) local v = rawget(F, k) if v ~= nil then return v end if type(k) == "string" and k:match("^%u") then return function() end end end
-- where a frame is and how big, kept where the addon can't write: Arrange's own fields are l, t, w, h and scale (a
-- handle's) and w, h (the panel's boxes to type into), and a fake sharing them answered GetWidth with a box
function F:SetPoint(p, rel, rp, x, y)
    if type(x) == "number" then rawset(self, "_l", x) rawset(self, "_t", y) end
end
function F:GetLeft() return rawget(self, "_l") end
function F:GetTop() return rawget(self, "_t") end
function F:SetSize(w, h) rawset(self, "_w", w) rawset(self, "_h", h) end
function F:GetWidth() return rawget(self, "_w") or 0 end
function F:GetHeight() return rawget(self, "_h") or 0 end
function F:GetEffectiveScale() return rawget(self, "_scale") or 1 end
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
UIParent = setmetatable({ _l = 0, _t = 1000, _w = 1600, _h = 1000 }, F)
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
ARRANGING = nil
function YR.SwingArranging(on) ARRANGING = on end
function YR.XPBarDB() return XP end
function YR.XPBarApply() HeadstartXPBar:SetSize(XP.w, XP.h) end
-- an element: the XP bar, which keeps its place (rounded) when a drag of its own ends
function Element(name, l, t, w, h)
    local f = setmetatable({ _l = l, _t = t, _w = w, _h = h }, F)
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
    check(raw(xp, "_l") == 400 and raw(g.HeadstartArrange, "passes") is True, "an arrow with nothing picked: the game's key, nothing moved")
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

    # a drag: the cursor taken from just inside the handle's corner to just inside where its corner is to be
    def drag(h, l, t, frames=()):
        lua.execute(f"CURSOR = {{ {raw(h, 'l') + 5}, {raw(h, 't') - 5} }}")
        raw(h, "_OnDragStart")(h)
        lua.execute(f"CURSOR = {{ {l + 5}, {t - 5} }}")
        for f in frames:
            raw(h, "_OnUpdate")(h, f)

    def drop(h):
        raw(h, "_OnDragStop")(h)
    check(hx is not None and raw(hx, "shown") is True and raw(hx, "l") == 400 and raw(hx, "w") == 200
          and raw(find["Camp icon"], "shown") is False, "a handle over each element that exists, none for one that doesn't")
    raw(hx, "_OnClick")(hx)
    box = raw(g.HeadstartArrange, "panel")
    check(raw(box, "_l") == 400 + 200 + 12 and raw(box, "_t") == 300,
          f"picked: the small window beside it, to its right ({raw(box, '_l')}, {raw(box, '_t')})")
    key(g.HeadstartArrange, "RIGHT")
    check(raw(xp, "_l") == 401 and raw(xp, "_t") == 300 and list(raw(xp, "kept").values()) == [401, 300]
          and raw(g.HeadstartArrange, "passes") is False, "picked, arrow right: one step, kept by the element's own script")
    g.SHIFT = True
    key(g.HeadstartArrange, "UP")
    g.SHIFT = False
    check(raw(xp, "_t") == 310 and raw(hx, "t") == 310, "Shift and arrow up: ten steps, the handle with it")
    # a drag let go: near nothing, so onto the grid (16, out from the middle of the screen: 800, 500)
    drag(hx, 207, 441)
    drop(hx)
    check(raw(xp, "_l") == 208 and raw(xp, "_t") == 436, f"dropped: onto the grid ({raw(xp, '_l')}, {raw(xp, '_t')})")
    # near another element's edge: to that, not the grid
    drag(hx, 897, 700, [0.016])
    what = raw(raw(g.HeadstartArrange, "bar"), "what") if False else None
    check(raw(xp, "_l") == 900 and raw(hx, "l") == 900 and raw(hl, "lined") is True,
          f"dragged near another element's left edge: shown lined up with it as it is dragged, that one outlined ({raw(xp, '_l')})")
    drop(hx)
    check(raw(xp, "_l") == 900 and raw(hl, "lined") is False, f"let go: there, and the outline gone ({raw(xp, '_l')})")
    # almost onto another: not pulled the rest of the way (it went onto it)
    drag(hx, raw(loot, "_l") + 3, raw(loot, "_t") - 3)
    drop(hx)
    check(not (raw(xp, "_l") == raw(loot, "_l") and raw(xp, "_t") == raw(loot, "_t")),
          f"dropped almost onto another: not pulled onto it ({raw(xp, '_l')}, {raw(xp, '_t')})")
    # beside another, the gap between (2)
    drag(hx, raw(loot, "_l") + raw(loot, "_w") + 5, raw(loot, "_t") + 1)
    drop(hx)
    check(raw(xp, "_l") == raw(loot, "_l") + raw(loot, "_w") + 2 and raw(xp, "_t") == raw(loot, "_t"),
          f"dropped to the right of another: beside it with the gap, tops lined up ({raw(xp, '_l')}, {raw(xp, '_t')})")
    g.YippRouteDB.arrange.snap = False
    drag(hx, 333, 222)
    drop(hx)
    check(raw(xp, "_l") == 333 and raw(xp, "_t") == 222, "snap off: where it was dropped")
    # the small window: where it is and how large, typed in
    panel = raw(g.HeadstartArrange, "panel")
    check(raw(panel, "shown") is True and raw(raw(panel, "x"), "value") == 333 and raw(raw(panel, "w"), "value") == 200,
          "picked: a window with its place and size")
    raw(raw(panel, "x"), "opts").onCommit("512")
    raw(raw(panel, "y"), "opts").onCommit("640")
    check(raw(xp, "_l") == 512 and raw(xp, "_t") == 640 and list(raw(xp, "kept").values()) == [512, 640], "x and y typed in: there, and kept")
    raw(raw(panel, "w"), "opts").onCommit("320")
    raw(raw(panel, "h"), "opts").onCommit("999")
    check(g.XP.w == 320 and g.XP.h == 40 and raw(hx, "w") == 320, f"width and height typed in: set, within what the bar allows ({g.XP.w}, {g.XP.h})")
    raw(raw(panel, "x"), "opts").onCommit("nonsense")
    check(raw(xp, "_l") == 512, "not a number: nothing moved")
    raw(hl, "_OnClick")(hl)
    raw(raw(panel, "w"), "opts").onCommit("50")
    check(raw(loot, "_w") == 100 and raw(raw(panel, "w"), "enabled") is False, "an element with no size to set: its size left alone")
    # anchors: the XP bar dragged over the loot feed and held there, then let go
    at = (raw(loot, "_l"), raw(loot, "_t"))
    was = (raw(xp, "_l"), raw(xp, "_t"))
    lua.execute(f"CURSOR = {{ {was[0] + 5}, {was[1] - 5} }}")
    raw(hx, "_OnDragStart")(hx)
    lua.execute(f"CURSOR = {{ {at[0] + 5}, {at[1] - 5} }}")
    raw(hx, "_OnUpdate")(hx, 0.1)
    check(g.YippRouteDB.arrange.anchor["XP bar"] is None, "held a moment over another: not yet")
    raw(hx, "_OnUpdate")(hx, 0.4)
    raw(hx, "_OnUpdate")(hx, 0.4)
    raw(hx, "_OnDragStop")(hx)
    chooser = raw(g.HeadstartArrange, "chooser")
    check(raw(chooser, "shown") is True and g.YippRouteDB.arrange.anchor["XP bar"] is None
          and (raw(xp, "_l"), raw(xp, "_t")) == was,
          "held over it, then let go: a window asks where it goes by it, and it is back where it was meanwhile")
    spots = raw(chooser, "spots")
    raw(spots["below"], "preview")()
    below = (at[0] + (100 - 320) // 2, at[1] - 50 - 2)
    check((raw(xp, "_l"), raw(xp, "_t")) == below and g.YippRouteDB.arrange.anchor["XP bar"] is None,
          f"the mouse over Below: shown there, under it in the middle with the gap ({raw(xp, '_l')}, {raw(xp, '_t')})")
    key(g.HeadstartArrange, "ESCAPE")
    check(raw(chooser, "shown") is False and raw(g.HeadstartArrange, "shown") is True
          and (raw(xp, "_l"), raw(xp, "_t")) == was and g.YippRouteDB.arrange.anchor["XP bar"] is None,
          "Esc: as it was, not anchored - and Arrange still open")
    lua.execute(f"CURSOR = {{ {was[0] + 5}, {was[1] - 5} }}")
    raw(hx, "_OnDragStart")(hx)
    lua.execute(f"CURSOR = {{ {at[0] + 5}, {at[1] - 5} }}")
    for f in (0.1, 0.4, 0.4):
        raw(hx, "_OnUpdate")(hx, f)
    raw(hx, "_OnDragStop")(hx)
    raw(spots["below"], "click")()
    check(raw(chooser, "shown") is False and g.YippRouteDB.arrange.anchor["XP bar"] == "Loot feed"
          and (raw(xp, "_l"), raw(xp, "_t")) == below and list(raw(xp, "kept").values()) == list(below),
          f"Below picked: anchored to it, put there and kept ({raw(xp, '_l')}, {raw(xp, '_t')})")
    before = (raw(xp, "_l"), raw(xp, "_t"))
    raw(hl, "_OnClick")(hl)
    g.SHIFT = True
    key(g.HeadstartArrange, "LEFT")
    key(g.HeadstartArrange, "DOWN")
    g.SHIFT = False
    check(raw(loot, "_l") == at[0] - 10 and raw(xp, "_l") == before[0] - 10 and raw(xp, "_t") == before[1] - 10
          and list(raw(xp, "kept").values()) == [before[0] - 10, before[1] - 10], "the one it hangs on moved: it goes along, and keeps its place")
    # the other way round would be a ring: not offered
    lua.execute(f"CURSOR = {{ {raw(loot, '_l') + 5}, {raw(loot, '_t') - 5} }}")
    raw(hl, "_OnDragStart")(hl)
    lua.eval("function(x, y) CURSOR = { x + 5, y - 5 } end")(raw(xp, "_l"), raw(xp, "_t"))
    raw(hl, "_OnUpdate")(hl, 0.1)
    raw(hl, "_OnUpdate")(hl, 1.0)
    raw(hl, "_OnDragStop")(hl)
    check(g.YippRouteDB.arrange.anchor["Loot feed"] is None, "anchoring the one it hangs on back to it: not offered")
    raw(hx, "_OnClick")(hx)
    raw(raw(panel, "release"), "click")()
    spot = raw(xp, "_l")
    raw(hl, "_OnClick")(hl)
    key(g.HeadstartArrange, "RIGHT")
    check(g.YippRouteDB.arrange.anchor["XP bar"] is None and raw(xp, "_l") == spot, "released: it stays where it is when the other moves")
    raw(hx, "_OnClick")(hx)
    key(g.HeadstartArrange, "A")
    check(raw(g.HeadstartArrange, "passes") is True, "any other key is the game's")
    raw(g.HeadstartArrange, "_OnEvent")(g.HeadstartArrange, "PLAYER_REGEN_DISABLED")
    check(raw(g.HeadstartArrange, "shown") is False and raw(g.HeadstartArrange, "event") is None, "a fight begins: closed, nothing listened for")
    check(YR.ArrangeToggle() is True and YR.ArrangeToggle() is False and raw(g.HeadstartArrange, "shown") is False, "toggled open and shut")
    # a small one in the middle of a larger: lined up there (a text on a bar is meant)
    g.YippRouteDB.arrange.snap = True
    camp = g.Element("HeadstartCampFrame", 50, 900, 20, 20)
    YR.ArrangeOpen()
    hc = find["Camp icon"]
    mid = (raw(xp, "_l") + (raw(xp, "_w") - 20) / 2, raw(xp, "_t") - (raw(xp, "_h") - 20) / 2)
    drag(hc, mid[0] - 1, mid[1] - 2)          # (the loot feed above has its middle a pixel further right: the nearer wins)
    drop(hc)
    check((raw(camp, "_l"), raw(camp, "_t")) == mid, f"a small one dropped near the middle of a larger: lined up in it ({raw(camp, '_l')}, {raw(camp, '_t')})")
    # the top bar never over an element on opening: one under it at the top, so at the bottom; dragged, kept there
    YR.ArrangeClose()
    g.Element("HeadstartFlightFrame", 780, 930, 120, 20)
    YR.ArrangeOpen()
    topbar = raw(g.HeadstartArrange, "bar")
    check(raw(topbar, "_t") == 60 + 92, f"an element under the bar's place at the top: the bar at the bottom ({raw(topbar, '_t')})")
    lua.eval("function(b) rawset(b, '_l', 100) rawset(b, '_t', 300) end")(topbar)
    raw(topbar, "_OnDragStop")(topbar)
    YR.ArrangeClose()
    YR.ArrangeOpen()
    check(raw(topbar, "_l") == 100 and raw(topbar, "_t") == 300, "dragged somewhere clear: kept there the next time")
    # the combat bars shown as they are while it is open, and back as it closes
    check(g.ARRANGING is True, "open: the combat bars asked to show")
    YR.ArrangeClose()
    check(g.ARRANGING is False, "closed: back as they were")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
