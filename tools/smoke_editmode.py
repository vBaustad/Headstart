"""Smoke test of Edit Mode outlines (EditModeLook.lua), in Lua 5.1 (lupa).

    python tools/smoke_editmode.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Off for a new install, and then nothing of Edit Mode is touched. On: as Edit Mode opens, each element's blue sheet
(its nine pieces), its mouse-over glow and the large name across it are made clear, and it is a clean dark block
instead (the idea of EllesmereUI's unlock mode): at rest a dark slate block, a one-pixel edge in the accent at half
strength, its name small in the middle; under the mouse the edge white; picked, the edge the full accent and two
pixels, the block warmed, the name in the accent and its position in pixels from the screen's middle, counted on
every frame only while it is dragged. All of it after Blizzard's own ShowHighlighted and ShowSelected (a post-hook:
Blizzard's runs first and is not replaced). Off again: Blizzard's as it was, ours hidden, Edit Mode let go of. Uses
smoke.py's fake game, with a fake Edit Mode of its own.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def files(folder, toc):
    return [os.path.join(folder, l.strip().replace(chr(92), "/"))
            for l in open(os.path.join(folder, toc), encoding="utf-8")
            if l.strip().endswith(".lua") and not l.startswith("#") and not l.startswith("Libs")]


def run():
    src = open(os.path.join(ROOT, "tools", "smoke.py"), encoding="utf-8").read()
    env = {"__name__": "smoke_head", "__file__": os.path.join(ROOT, "tools", "smoke.py")}
    exec(compile(src.split("YR = lua.table()")[0], "smoke.py (head)", "exec"), env)
    lua = env["lua"]
    # A real post-hook (smoke.py's only notes the hook), and a fake Edit Mode: two elements, each with a
    # selection frame that draws its sheet as Blizzard's does (pieces made on its first ShowHighlighted) and
    # writes its name across itself. The screen: 1920 by 1080 at scale 1, two pixels a point.
    lua.execute("""
        function hooksecurefunc(t, key, fn)
            local orig = t[key]
            t[key] = function(...) local r = { orig(...) } fn(...) return unpack(r) end
        end
        local function Tex()
            local t = { alpha = 1, shown = true }
            function t:SetAlpha(a) self.alpha = a end
            function t:GetAlpha() return self.alpha end
            function t:Show() self.shown = true end
            function t:Hide() self.shown = false end
            function t:SetShown(on) self.shown = on and true or false end
            function t:IsShown() return self.shown end
            function t:SetPoint(point, _, _, x, y) self.at = self.at or {} self.at[point] = { x or 0, y or 0 } end
            function t:ClearAllPoints() self.at = {} end
            function t:SetAllPoints() end
            function t:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
            function t:SetHeight(h) self.h = h end
            function t:SetWidth(w) self.w = w end
            function t:GetEffectiveScale() return 1 end
            return t
        end
        PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
            "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }
        local function Selection(name, cx, cy)
            local s = { made = {}, scripts = {}, cx = cx, cy = cy }
            s.system = { GetSystemName = function() return name end }
            s.MouseOverHighlight = Tex()
            s.MouseOverHighlight.alpha = 0.4
            s.Label = Tex()
            function s:CreateTexture() local t = Tex() self.made[#self.made + 1] = t return t end
            function s:GetEffectiveScale() return 1 end
            function s:GetWidth() return 300 end
            function s:GetHeight() return 30 end
            function s:GetCenter() return self.cx, self.cy end
            function s:HookScript(what, fn) local old = self.scripts[what]
                self.scripts[what] = function(...) if old then old(...) end fn(...) end end
            function s:ShowHighlighted()
                for _, p in ipairs(PIECES) do self[p] = self[p] or Tex() self[p].atlas = "highlight" end
                self.isSelected = false
                BLIZZ = (BLIZZ or 0) + 1
            end
            function s:ShowSelected()
                for _, p in ipairs(PIECES) do self[p] = self[p] or Tex() self[p].atlas = "selected" end
                self.isSelected = true
                BLIZZ = (BLIZZ or 0) + 1
            end
            return s
        end
        BAR, METER = { Selection = Selection("Action Bar 1", 960, 100) }, { Selection = Selection("Damage Meter", 1060, 590) }
        EditModeManagerFrame = { registeredSystemFrames = { BAR, METER } }
        CALLBACKS = {}
        EventRegistry = {
            RegisterCallback = function(_, ev, fn, owner) CALLBACKS[ev] = CALLBACKS[ev] or {} CALLBACKS[ev][owner] = fn end,
            UnregisterCallback = function(_, ev, owner) if CALLBACKS[ev] then CALLBACKS[ev][owner] = nil end end,
        }
        function Callbacks(ev) local n = 0 for _ in pairs(CALLBACKS[ev] or {}) do n = n + 1 end return n end
        function EnterEditMode()
            for _, f in ipairs(EditModeManagerFrame.registeredSystemFrames) do f.Selection:ShowHighlighted() end
            for owner, fn in pairs(CALLBACKS["EditMode.Enter"] or {}) do fn(owner) end
        end
        function Select(f)
            for _, o in ipairs(EditModeManagerFrame.registeredSystemFrames) do
                if o == f then o.Selection:ShowSelected() else o.Selection:ShowHighlighted() end
            end
        end
        function Alphas(sel) local a = {} for _, p in ipairs(PIECES) do a[#a + 1] = sel[p] and sel[p].alpha or -1 end return table.concat(a, ",") end
        function Shown(sel) local n = 0 for _, t in ipairs(sel.made) do if t.shown then n = n + 1 end end return n end
        PixelUtil = { GetPixelToUIUnitFactor = function() return 0.5 end }   -- two pixels a point at scale 1
        UIParent.GetWidth = function() return 1920 end
        UIParent.GetHeight = function() return 1080 end
        UIParent.GetEffectiveScale = function() return 1 end
    """)
    YR = lua.table()
    load = lua.eval("function(c, n) return assert(loadstring(c, n)) end")
    for f in files(ROOT, "Headstart.toc"):
        load(open(f, encoding="utf-8").read(), os.path.basename(f))("Headstart", YR)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def rgba(c):
        return tuple(round(c[i], 2) for i in (1, 2, 3, 4)) if c else None

    lua.execute("YippRouteDB = nil")
    g.Fire("ADDON_LOADED", "Headstart")
    g.Fire("PLAYER_LOGIN")
    bar, meter = g.BAR.Selection, g.METER.Selection
    ONES = ",".join(["1"] * 9)
    ZEROS = ",".join(["0"] * 9)
    acc = rgba(YR.Style.C.accent)[:3]

    check(g.YippRouteDB.editModeOutline is None and not YR.EditModeOutlineOn() and g.Callbacks("EditMode.Enter") == 0,
          "a new install: off, and nothing listens for Edit Mode")
    g.EnterEditMode()
    check(g.Alphas(bar) == ONES and len(bar.made) == 0 and bar.MouseOverHighlight.alpha == 0.4 and bar.Label.alpha == 1
          and YR.EditModeLookShown(bar) is None,
          f"off: Edit Mode as Blizzard has it - the sheet and its name, nothing of ours ({g.Alphas(bar)})")

    g.YippRouteDB.editModeOutline = True
    YR.ApplyParts()
    check(g.Callbacks("EditMode.Enter") == 1, "on: Edit Mode's opening listened for, by one callback")
    s = YR.EditModeLookShown(bar)
    check(g.Alphas(bar) == ZEROS and bar.MouseOverHighlight.alpha == 0 and bar.Label.alpha == 0,
          f"turned on while Edit Mode is open: the sheet, its glow and the name across it clear at once ({g.Alphas(bar)})")
    fill = rgba(s.fill)
    check(s.state == "rest" and fill is not None and max(fill[:3]) < 0.2 and fill[3] >= 0.8,
          f"at rest: a dark block, one colour on any ground ({fill})")
    edge = rgba(s.colour)
    check(s.edge and edge[:3] == acc and 0.4 <= edge[3] <= 0.7 and abs(s.thick - 0.5) < 1e-9,
          f"its edge one pixel, in the accent at half strength ({edge}, {s.thick} points at two pixels a point)")
    check(s.name == "Action Bar 1" and s.coords is None, f"and its name in the middle, no position ({s.name}, {s.coords})")
    left = bar.made[4].at["TOPLEFT"]          # made in this order: the block, then the edge's top, bottom, left, right
    check(left[1] == 0 and left[2] < 0, f"the edge inside the element's own edges: a neighbour's never lies over it ({list(left.values())})")

    blizz = g.BLIZZ
    g.Select(g.METER)
    s = YR.EditModeLookShown(meter)
    check(g.BLIZZ == blizz + 2 and meter.isSelected,
          "picking one: Blizzard's own ShowSelected and ShowHighlighted still run (hooked after, not replaced)")
    edge, fill = rgba(s.colour), rgba(s.fill)
    check(g.Alphas(meter) == ZEROS and s.state == "picked" and edge == acc + (1.0,) and abs(s.thick - 1) < 1e-9,
          f"the one picked: its selected sheet clear too; the edge the full accent, two pixels ({edge}, {s.thick})")
    check(fill[0] > fill[2] and s.name == "Damage Meter", f"the block warmed toward the accent, its name on it ({fill})")
    check(s.coords == "200, 100", f"and where it stands: its middle in pixels from the screen's middle ({s.coords})")
    check(YR.EditModeLookShown(bar).state == "rest", "the others stay at rest")

    bar.scripts.OnEnter(bar)
    s = YR.EditModeLookShown(bar)
    check(s.state == "hover" and rgba(s.colour)[:3] == (1, 1, 1) and bar.MouseOverHighlight.alpha == 0,
          f"under the mouse: the edge white; Blizzard's glow stays clear ({s.state})")
    bar.scripts.OnLeave(bar)
    check(YR.EditModeLookShown(bar).state == "rest", "the mouse gone: at rest again")

    meter.scripts.OnDragStart(meter)
    s = YR.EditModeLookShown(meter)
    check(s.ticking, "a drag: the position is counted while it lasts")
    meter.cx = 860
    ticked = lua.eval("""function(sel)
        for _, f in ipairs(FRAMES) do
            local sc = rawget(f, "scripts")
            if rawget(f, "sel") == sel and sc and sc.OnUpdate then sc.OnUpdate(f) return true end
        end
        return false end""")(meter)
    s = YR.EditModeLookShown(meter)
    check(ticked and s.coords == "-200, 100", f"and counted again as it moves ({s.coords})")
    meter.scripts.OnDragStop(meter)
    stopped = lua.eval("""function(sel)
        for _, f in ipairs(FRAMES) do
            local sc = rawget(f, "scripts")
            if rawget(f, "sel") == sel then return not (sc and sc.OnUpdate) end
        end
        return false end""")(meter)
    check(not YR.EditModeLookShown(meter).ticking and stopped, "let go: nothing counts any more")

    made = len(bar.made)
    g.EnterEditMode()
    check(len(bar.made) == made and made > 0, f"Edit Mode opened again: no element taken twice ({made} textures, as before)")

    g.YippRouteDB.editModeOutline = False
    YR.ApplyParts()
    s = YR.EditModeLookShown(bar)
    check(g.Alphas(bar) == ONES and g.Alphas(meter) == ONES and bar.MouseOverHighlight.alpha == 0.4 and bar.Label.alpha == 1
          and meter.Label.alpha == 1,
          f"off again: every sheet, glow and name as Blizzard had them ({g.Alphas(bar)}, glow {bar.MouseOverHighlight.alpha})")
    check(s.state == "off" and s.fill is None and s.name is None and g.Shown(bar) == 0 and g.Shown(meter) == 0,
          "and nothing of ours shows")
    check(g.Callbacks("EditMode.Enter") == 0, "and Edit Mode is let go of")
    g.Select(g.BAR)
    check(g.Alphas(bar) == ONES and g.Shown(bar) == 0 and bar.Label.alpha == 1,
          "off: a hook that stays (they can't be taken away) changes nothing")

    g.YippRouteDB.editModeOutline, g.YippRouteDB.qolOff = True, True
    YR.ApplyParts()
    check(not YR.EditModeOutlineOn() and g.Alphas(bar) == ONES, "quality of life off: off too")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
