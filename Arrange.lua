-- Arrange: every Headstart element that stands on the screen, moved from one place and to the point.
--   /hs move (or Arrange in the settings window) lays a grid over the screen and a handle over each
--   element that exists: an outline with the element's name in it and nothing else, so the element
--   itself is seen against the grid. Drag a handle, or click it and use the arrow keys: one step a
--   press, ten with Shift. A click also opens a small window beside the element with where it is and
--   how large, to type into (the size only for the elements that have one to set). Esc or Done ends it.
--   Snapping, as you drag: an edge or the middle of the element lines up with the same of another
--   element or of the screen, or it goes beside another with the gap set between (Gap: 0, 2, 4 or 8),
--   and otherwise onto the grid. What it lines up with is shown while you drag - a line along the edges
--   and that element outlined in blue - and the element stands where it will be when let go. A snap
--   that would lay it partly over another element isn't taken (wholly inside a larger one - a text on a
--   bar - is). Alt held: no snapping. (The owner, 2026-10-20: "snapping doesn't work well ... while
--   dragging it should highlight what it snaps to ... right now it snapped to something and overlapped".)
--   Anchors: drag an element over another and hold it there a moment (the other turns green), then
--   let go: a small window asks where it goes by that one - above, below, left or right of it, lined up
--   at either edge or the middle; on it, in its middle; or kept where it was - each shown as the mouse is
--   over it, and it is anchored there. Cancel or Esc: as it was. From then on, moving an element here
--   moves everything anchored to it along, and what is anchored to those. An anchor is a grouping for
--   arranging, kept in
--   YippRouteDB.arrange.anchor = { [element's name] = the name of the one it is anchored to }; the
--   elements themselves still each keep a place of their own, so outside Arrange nothing depends on it.
--   Nothing here knows how an element keeps its place. Each already keeps it when a drag of its own
--   ends, so a move here ends by running that same script: the element saves, in its own way, where
--   it now is. (The trinket buttons only keep a drag they started themselves: they are asked directly.)
--   An element's own lock is not looked at: this is the unlocking.
--   Not in a fight (the trinket buttons may not be moved in one): it won't open in one, and one that
--   begins closes it. Nothing is made until it is first opened, and nothing is listened for while shut.
--   Headstart's combat bars show while it is open, a sample on each that has nothing to show (a cast
--   bar with no cast), so every one is seen as it is (YR.SwingArranging).
--   The bar at the top (Grid, Snap, Done) is dragged where you like, and kept there; opened where it would
--   lie over an element - which then can't be taken hold of - it stands at the bottom of the screen instead,
--   else in the middle (the owner, 2026-10-20: "the elements under Arrange's bar can't be moved").
--   Account options (YippRouteDB.arrange): grid (0 = none, else its size), snap, gap (2), barAt (where you
--   dragged the bar: { left, top }).
local ADDON, YR = ...

local function Own(key) return function() return YR.OwnBarFrame and YR.OwnBarFrame(key) or nil end end
local function SwingReset(key) return function() YR.SwingResetPosition(key) end end
local function OwnSize(key)
    return function(w, h)
        local db = YR.SwingDB()
        local nowW, nowH = YR.SwingBarSize(key)
        db.size = db.size or {}
        db.size[key] = { math.max(40, math.min(800, w or nowW)), math.max(4, math.min(80, h or nowH)) }
        YR.SwingApply()
    end
end
local function XPSize(w, h)
    local db = YR.XPBarDB()
    if w then db.w = math.max(150, math.min(1800, w)) end
    if h then db.h = math.max(4, math.min(40, h)) end
    YR.XPBarApply()
end
-- { its name, the frame (a global's name, or a function giving it), reset, save, size(w, h) }
local ITEMS = {
    { "Swing: main hand", Own("main"), SwingReset("main"), nil, OwnSize("main") },
    { "Swing: off hand", Own("off"), SwingReset("off"), nil, OwnSize("off") },
    { "Cast bar", Own("cast"), SwingReset("cast"), nil, OwnSize("cast") },
    { "Range bar", Own("range"), SwingReset("range"), nil, OwnSize("range") },
    { "Range text", Own("rangetext"), SwingReset("rangetext") },
    { "Health bar", Own("health"), SwingReset("health"), nil, OwnSize("health") },
    { "Power bar", Own("power"), SwingReset("power"), nil, OwnSize("power") },
    { "Combo points", Own("combo"), SwingReset("combo"), nil, OwnSize("combo") },
    { "XP bar", "HeadstartXPBar", function() YR.XPBarResetPosition() end, nil, XPSize },
    { "Trinket buttons", "HeadstartTrinketBar", function() YR.TrinketResetPosition() end, function() YR.TrinketSavePosition() end },
    { "Quest item buttons", "HeadstartQuestItemBar", function() YR.QuestItemsResetPosition() end, function() YR.QuestItemsSavePosition() end },
    { "Loot feed", "HeadstartLootFeed", function() YR.LootFeedResetPosition() end },
    { "Camp icon", "HeadstartCampFrame" },
    -- (shown with two sample points while you arrange, so it can be placed before you have a point to spend)
    -- (shown with some of your class's spells while you arrange, so it can be placed before a ding)
    { "New at your trainer", function() return YR.TrainerPopupFrame and YR.TrainerPopupFrame(true) or nil end,
        function() YR.TrainerPopupReset() end, function() YR.TrainerPopupSave() end },
    { "Talent points notice", function() return YR.TalentNoticeFrame and YR.TalentNoticeFrame(true) or nil end,
        function() YR.TalentNoticeReset() end, function() YR.TalentNoticeSave() end },
    { "Flight timer", "HeadstartFlightFrame" },
    { "Instance counter", "HeadstartInstanceHud", function() YR.InstanceHudResetPosition() end },
    { "Quest group button", "HeadstartQuestLFGButton", function() YR.QuestLFGResetPosition() end },
    { "Group buttons", "HeadstartGroupBar" },
    { "Splits", "HeadstartSplitsFrame" },
}
local GRIDS = { 0, 8, 16, 32, 64 }
local GAPS = { 0, 2, 4, 8 }     -- the space between two elements set side by side
local NEAR = 8                  -- how close an edge has to come to a line to snap to it
local HOLD = 0.6                -- how long a dragged element is held over another before it offers to anchor
local SNAP = { 0.40, 0.80, 1.00, 1 }    -- what a dragged element lines up with: the line, and that one's outline
local ARMED = { 0.30, 1.00, 0.40, 1 }   -- the one it is to be anchored to
local HINT = "Drag an element, or click it and use the arrow keys (Shift: ten). Hold it over another to anchor it"
    .. " there. Alt while dragging: no snapping. This bar can be dragged too."
local DRAGGING = "Hold it over another element to anchor it there. Alt: no snapping."

local root, bar, panel, picked, armed
local chooser, pending          -- the window that asks where an anchored element goes; what it is asking about
local Unchoose
local handles, lines, guides = {}, {}, {}

local function DB()
    local db = YippRouteDB.arrange
    if type(db) ~= "table" then
        db = { grid = 16, snap = true }
        YippRouteDB.arrange = db
    end
    if type(db.anchor) ~= "table" then db.anchor = {} end
    if type(db.gap) ~= "number" then db.gap = 2 end
    return db
end

-- Whether `h` hangs on `on`, straight or through others.
local function HangsOn(h, on)
    local anchor = DB().anchor
    local name, steps = anchor[h.item[1]], 0
    while name and steps < 30 do
        if name == on.item[1] then return true end
        name, steps = anchor[name], steps + 1
    end
    return false
end

local function Target(item)
    local f = item[2]
    if type(f) == "string" then f = _G[f] else f = f() end
    if type(f) ~= "table" or not f.GetLeft then return nil end
    return f
end

-- Where an element is, in the screen's measure (an element can have a size of its own).
local function Rect(f)
    local l, t, w, h = f:GetLeft(), f:GetTop(), f:GetWidth(), f:GetHeight()
    if not (l and t and w and h) then return nil end
    local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if s <= 0 then s = 1 end
    return l * s, t * s, math.max(8, w * s), math.max(8, h * s), s
end

local function Readout()
    if not bar then return end
    local db = DB()
    bar.grid:SetLabel(db.grid > 0 and ("Grid: " .. db.grid) or "Grid: off")
    bar.snap:SetLabel(db.snap and "Snap: on" or "Snap: off")
    bar.gap:SetLabel("Gap: " .. db.gap)
    bar.reset:SetEnabled(picked ~= nil and picked.item[3] ~= nil)
    if not picked then panel:Hide() return end
    panel.title:SetText(picked.item[1])
    local to = db.anchor[picked.item[1]]
    panel.anchor:SetText(to and ("Anchored to " .. to) or "Not anchored")
    panel.release:SetShown(to ~= nil)
    local sized = picked.item[5] ~= nil
    for key, v in pairs({ x = picked.l, y = picked.t, w = picked.w, h = picked.h }) do
        local box = panel[key]
        if not box:HasFocus() then box:SetValue(math.floor(v + 0.5)) end
        if key == "w" or key == "h" then
            box:SetEnabled(sized)
            box:SetAlpha(sized and 1 or 0.4)
        end
    end
    panel:Show()
end

-- An outline and a name: nothing laid over the element, so it is seen against the grid as it is.
-- Green: the one it is to be anchored to; blue: what the dragged one lines up with now (and a faint fill, so
-- either is seen at a glance); white: the one picked.
local function Paint(h)
    local target = h == armed or (pending ~= nil and pending.o == h)
    local c = target and ARMED or h.lined == true and SNAP or h == picked and { 1, 1, 1, 1 } or YR.Style.C.accent
    h.edge:Color(c)
    if target or h.lined == true then h.glow:SetColorTexture(c[1], c[2], c[3], 0.16) end
    h.glow:SetShown(target or h.lined == true)
    local to = DB().anchor[h.item[1]]
    h.label:SetText(to and (h.item[1] .. "  >  " .. to) or h.item[1])
end

-- The handle put over its element, where and as large as that is now.
local function Sync(h)
    local f = Target(h.item)
    local l, t, w, hgt, s
    if f then l, t, w, hgt, s = Rect(f) end
    if not l then h:Hide() return false end
    h.l, h.t, h.w, h.h, h.scale = l, t, w, hgt, s
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    h:SetSize(w, hgt)
    h:Show()
    return true
end

-- The small window beside the element just picked: to its right, or its left where there is no room.
-- Once you have dragged it somewhere it stays there.
local function Beside(h)
    if panel.moved then return end
    panel:ClearAllPoints()
    if h.l + h.w + 12 + panel:GetWidth() <= UIParent:GetWidth() then
        panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", h.l + h.w + 12, h.t)
    else
        panel:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", h.l - 12, h.t)
    end
end

local function Pick(h)
    if pending then Unchoose(nil) end           -- (another element picked while the window asked: as it was)
    -- a number being typed belongs to the element it was typed for: the box is left (which writes it)
    -- before another element is the picked one - it went to whichever was picked when Enter came
    if panel and h ~= picked then
        for _, key in ipairs({ "x", "y", "w", "h" }) do
            local box = panel[key]
            if box and box.HasFocus and box:HasFocus() then box:ClearFocus() end
        end
    end
    local was = picked
    picked = h
    if was then Paint(was) end
    if h then
        Paint(h)
        Beside(h)
    end
    Readout()
end

-- The element put with its top left corner at l, t. kept: the move is done, and the element keeps it.
local function Move(h, l, t, kept)
    local f = Target(h.item)
    if not f or InCombatLockdown() then return end
    local s = h.scale or 1
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l / s, t / s)
    if kept then
        if h.item[4] then
            h.item[4]()
        else
            local stop = f.GetScript and f:GetScript("OnDragStop")
            if stop then stop(f) end
        end
        Sync(h)             -- (where the element says it is now: it may have rounded, or kept to the screen)
    else
        h.l, h.t = l, t
    end
    Readout()
end

-- The same, and everything anchored to it moved by as much (and what is anchored to those).
local function MoveTree(h, l, t, kept, depth)
    local dx, dy = l - h.l, t - h.t
    Move(h, l, t, kept)
    depth = depth or 0
    if depth > 30 then return end
    local anchor = DB().anchor
    for _, o in ipairs(handles) do
        if o ~= h and o:IsShown() and anchor[o.item[1]] == h.item[1] then
            MoveTree(o, o.l + dx, o.t + dy, kept, depth + 1)
            if not kept then Sync(o) end
        end
    end
end

-- A dragged element held over another: after a moment that one is armed, and letting go asks where it goes by it.
local function Arm(o, h)
    if armed == o then return end
    local was = armed
    armed = o
    if was then Paint(was) end
    if o then Paint(o) end
    bar.what:SetText(o and ("Let go to choose where " .. h.item[1] .. " goes by " .. o.item[1])
        or (h.dragging == true and DRAGGING or HINT))
end

local function Cursor()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

local function Hover(h, elapsed)
    local x, y = Cursor()
    local over
    for _, o in ipairs(handles) do
        -- (not one that already hangs on the dragged one: that would be a ring)
        if o ~= h and o:IsShown() and x >= o.l and x <= o.l + o.w and y <= o.t and y >= o.t - o.h and not HangsOn(o, h) then
            over = o
            break
        end
    end
    if over ~= h.over then h.over, h.held = over, 0 else h.held = (h.held or 0) + elapsed end
    Arm(over and h.held >= HOLD and over or nil, h)
end

-- The handles that go along with h as it moves (anchored to it, or to those): not lined up with, nor in its way.
local function Along(o, h) return o == h or HangsOn(o, h) end

-- One box wholly inside another that is larger (a text on a bar): meant, not in the way.
local function Inside(al, at, aw, ah, bl, bt, bw, bh)
    return al >= bl - 0.5 and al + aw <= bl + bw + 0.5 and at <= bt + 0.5 and at - ah >= bt - bh - 0.5
        and (aw < bw - 1 or ah < bh - 1)
end

-- Whether h, at l, t, would lie partly over another element.
local function Over(h, l, t)
    for _, o in ipairs(handles) do
        if o:IsShown() and not Along(o, h) then
            local ix = math.min(l + h.w, o.l + o.w) - math.max(l, o.l)
            local iy = math.min(t, o.t) - math.max(t - h.h, o.t - o.h)
            if ix > 0.5 and iy > 0.5 and not Inside(l, t, h.w, h.h, o.l, o.t, o.w, o.h)
                and not Inside(o.l, o.t, o.w, o.h, l, t, h.w, h.h) then
                return true
            end
        end
    end
    return false
end

-- l, t pulled to what is near, and the lines it was pulled to (each { at = where, o = the element, or nil for
-- the screen }; none where it went onto the grid). An edge or the middle lines up with the same of another
-- element or of the screen, or an edge goes beside another's with the gap between. The nearest pull that
-- doesn't lay it partly over another element is taken; where there is none, the grid. (It pulled any edge or
-- middle to any other's, one way and the other apart: let go near another, it went onto it.)
local function Snapped(h, l, t)
    local db = DB()
    if not db.snap or (IsAltKeyDown and IsAltKeyDown()) then return l, t end
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local gap = db.gap
    local xs, ys = {}, {}
    -- mine: 0 the left (top) edge, 0.5 the middle, 1 the right (bottom) edge - put on `at`
    local function X(mine, at, o)
        local d = at - (l + mine * h.w)
        if math.abs(d) < NEAR then xs[#xs + 1] = { d = d, at = at, o = o } end
    end
    local function Y(mine, at, o)
        local d = at - (t - mine * h.h)
        if math.abs(d) < NEAR then ys[#ys + 1] = { d = d, at = at, o = o } end
    end
    for _, m in ipairs({ 0, 0.5, 1 }) do
        X(m, W * m)
        Y(m, H * (1 - m))
    end
    for _, o in ipairs(handles) do
        if o:IsShown() and not Along(o, h) then
            for _, m in ipairs({ 0, 0.5, 1 }) do
                X(m, o.l + m * o.w, o)
                Y(m, o.t - m * o.h, o)
            end
            X(0, o.l + o.w + gap, o)        -- to its right
            X(1, o.l - gap, o)              -- to its left
            Y(0, o.t - o.h - gap, o)        -- under it
            Y(1, o.t + gap, o)              -- over it
        end
    end
    local function Nearest(a, b) return math.abs(a.d) < math.abs(b.d) end
    table.sort(xs, Nearest)
    table.sort(ys, Nearest)
    xs[#xs + 1], ys[#ys + 1] = false, false         -- (none on that side: the grid)
    local g = db.grid
    local function Grid(v, mid) return g > 0 and mid + math.floor((v - mid) / g + 0.5) * g or v end
    local best, cost
    for _, x in ipairs(xs) do
        for _, y in ipairs(ys) do
            local c = (x and math.abs(x.d) or NEAR) + (y and math.abs(y.d) or NEAR)
            if not cost or c < cost then
                local nl = x and l + x.d or Grid(l, W / 2)
                local nt = y and t + y.d or Grid(t, H / 2)
                if not (x or y) or not Over(h, nl, nt) then best, cost = { nl, nt, x, y }, c end
            end
        end
    end
    return best[1], best[2], best[3] or nil, best[4] or nil
end

-- A line along what the dragged element lines up with: from beyond the one end of the two to beyond the
-- other (the screen's: across it).
local function Guide(tex, line, vertical, h, l, t)
    if not line then tex:Hide() return end
    local o = line.o
    tex:ClearAllPoints()
    if vertical then
        local a, b = 0, UIParent:GetHeight()
        if o then a, b = math.min(t - h.h, o.t - o.h) - 10, math.max(t, o.t) + 10 end
        tex:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", line.at - 1, a)
        tex:SetSize(2, b - a)
    else
        local a, b = 0, UIParent:GetWidth()
        if o then a, b = math.min(l, o.l) - 10, math.max(l + h.w, o.l + o.w) + 10 end
        tex:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", a, line.at - 1)
        tex:SetSize(b - a, 2)
    end
    tex:Show()
end

-- What the dragged element lines up with now: the lines drawn, those elements outlined in blue, and said at
-- the top. Lines(nil): all of it away.
local function Lines(h, l, t, lx, ly)
    Guide(guides[1], lx, true, h, l, t)
    Guide(guides[2], ly, false, h, l, t)
    local now = {}
    if lx and lx.o then now[lx.o] = true end
    if ly and ly.o then now[ly.o] = true end
    for _, o in ipairs(handles) do
        local on = now[o] == true
        if (o.lined == true) ~= on then
            o.lined = on
            Paint(o)
        end
    end
    if not h or h.dragging ~= true or armed then return end
    local names = {}
    for _, line in ipairs({ lx or false, ly or false }) do
        if line then
            local name = line.o and line.o.item[1] or "the screen"
            if names[1] ~= name then names[#names + 1] = name end
        end
    end
    bar.what:SetText(#names > 0 and ("Lines up with " .. table.concat(names, " and ")) or DRAGGING)
end

-- The window's spots: { key, its column, its row, its words } - round a box that stands for the other
-- element, as they lie on the screen.
local SPOTS = {
    { "above-left", 1, 1, "Above, left" }, { "above", 2, 1, "Above" }, { "above-right", 3, 1, "Above, right" },
    { "left-top", 1, 2, "Left, top" }, { "right-top", 3, 2, "Right, top" },
    { "left", 1, 3, "Left" }, { "right", 3, 3, "Right" },
    { "left-bottom", 1, 4, "Left, bottom" }, { "right-bottom", 3, 4, "Right, bottom" },
    { "below-left", 1, 5, "Below, left" }, { "below", 2, 5, "Below" }, { "below-right", 3, 5, "Below, right" },
    { "on", 1, 6, "On it" }, { "keep", 2, 6, "Where it was" },
}
local TIPS = {
    ["above-left"] = "Above %s, left edges lined up", above = "Above %s, in the middle",
    ["above-right"] = "Above %s, right edges lined up",
    ["below-left"] = "Below %s, left edges lined up", below = "Below %s, in the middle",
    ["below-right"] = "Below %s, right edges lined up",
    ["left-top"] = "Left of %s, tops lined up", left = "Left of %s, in the middle",
    ["left-bottom"] = "Left of %s, bottoms lined up",
    ["right-top"] = "Right of %s, tops lined up", right = "Right of %s, in the middle",
    ["right-bottom"] = "Right of %s, bottoms lined up",
    on = "On %s, in its middle (a text on a bar)", keep = "Where it was before you dragged it, anchored to %s",
}

-- Where h goes by o for a spot: above it ("above-left": left edges lined up, "above": the middles,
-- "above-right"), below it, to its left or right ("left-top", "left", "left-bottom" ...) with the gap
-- between; "on": in its middle; "keep": where it was before the drag. On the screen, in whole pixels.
local function Spot(key, h, o)
    if key == "keep" then return pending.l, pending.t end
    local gap = DB().gap
    local side, along = key:match("^(%a+)%-?(%a*)$")
    local cx, cy = o.l + (o.w - h.w) / 2, o.t - (o.h - h.h) / 2
    local l, t = cx, cy
    if side == "above" or side == "below" then
        t = side == "above" and o.t + gap + h.h or o.t - o.h - gap
        l = along == "left" and o.l or along == "right" and o.l + o.w - h.w or cx
    elseif side == "left" or side == "right" then
        l = side == "left" and o.l - gap - h.w or o.l + o.w + gap
        t = along == "top" and o.t or along == "bottom" and o.t - o.h + h.h or cy
    end
    l = math.max(0, math.min(UIParent:GetWidth() - h.w, math.floor(l + 0.5)))
    t = math.max(h.h, math.min(UIParent:GetHeight(), math.floor(t + 0.5)))
    return l, t
end

-- The mouse over a spot: the element shown there (not kept); off it (nil), back where it was.
local function Preview(key)
    local p = pending
    if not p then return end
    local l, t = p.l, p.t
    if key then l, t = Spot(key, p.h, p.o) end
    MoveTree(p.h, l, t, false)
    Sync(p.h)
end

-- The window's answer: a spot - anchored, put there, kept - or nil: as it was, not anchored.
function Unchoose(key)
    local p = pending
    if not p then return end
    local l, t = p.l, p.t
    if key then l, t = Spot(key, p.h, p.o) end
    pending = nil
    chooser:Hide()
    if key then DB().anchor[p.h.item[1]] = p.o.item[1] end
    MoveTree(p.h, l, t, true)
    Paint(p.o)
    Paint(p.h)
    bar.what:SetText(HINT)
    Readout()
end

-- Let go over another: the window, beside that one and out of the way of where the element would go, and
-- the element back where it was until a spot is picked.
local function Choose(h, o)
    pending = { h = h, o = o, l = h.grab.l, t = h.grab.t }
    Preview(nil)
    chooser.title:SetText(("Anchor %s to %s"):format(h.item[1], o.item[1]))
    chooser.box.label:SetText(o.item[1])
    for key, b in pairs(chooser.spots) do b.tip = TIPS[key]:format(o.item[1]) end
    local room = h.w + DB().gap + 16
    local cw = chooser:GetWidth()
    chooser:ClearAllPoints()
    if o.l + o.w + room + cw <= UIParent:GetWidth() then
        chooser:SetPoint("LEFT", UIParent, "BOTTOMLEFT", o.l + o.w + room, o.t - o.h / 2)
    elseif o.l - room - cw >= 0 then
        chooser:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", o.l - room, o.t - o.h / 2)
    else
        chooser:SetPoint("CENTER")
    end
    chooser:Show()
    Paint(o)
    bar.what:SetText("Pick where " .. h.item[1] .. " goes by " .. o.item[1] .. " (Esc: as it was)")
end

-- Where the dragged element goes for the cursor now: as far as the cursor has come since the drag began,
-- kept on the screen, and lined up with what is near (not while it is held over one to anchor to). The
-- element stands there, and its outline with it.
local function Follow(h)
    local x, y = Cursor()
    local g = h.grab
    local l = math.max(0, math.min(UIParent:GetWidth() - h.w, g.l + x - g.x))
    local t = math.max(h.h, math.min(UIParent:GetHeight(), g.t + y - g.y))
    local lx, ly
    if not armed then l, t, lx, ly = Snapped(h, l, t) end
    Lines(h, l, t, lx, ly)
    if l ~= h.l or t ~= h.t then
        MoveTree(h, l, t, false)
        Sync(h)
    end
    return l, t
end

local function Drop(h)
    h.dragging = false
    h:SetFrameLevel(root:GetFrameLevel() + 1)
    local to = armed
    h.over, h.held = nil, nil
    Arm(nil, h)
    if to then
        Lines(nil)
        return Choose(h, to)
    end
    local l, t = Follow(h)
    Lines(nil)
    MoveTree(h, l, t, true)
end

local function Handle(item)
    local S = YR.Style
    local h = CreateFrame("Button", nil, root)
    h.item = item
    h.dragging, h.lined = false, false
    h.glow = h:CreateTexture(nil, "BACKGROUND")
    h.glow:SetAllPoints()
    h.glow:Hide()
    h.edge = S.Border(h, S.C.accent)
    h.label = S.Text(h, 11, { 1, 1, 1, 1 })
    h.label:SetFont(S.FONT, 11, "OUTLINE")
    h.label:SetPoint("CENTER")
    h.label:SetText(item[1])
    h:RegisterForDrag("LeftButton")
    h:SetScript("OnClick", function(self) Pick(self) end)
    -- moved by hand, not by the game's own moving: each frame the element goes where the cursor has come, lined
    -- up with what is near, and the outline with it - so where it will be let go is what is seen
    h:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        Pick(self)
        local x, y = Cursor()
        self.grab = { x = x, y = y, l = self.l, t = self.t }
        self.dragging = true
        self:SetFrameLevel(root:GetFrameLevel() + 20)       -- (over the others while it moves)
    end)
    h:SetScript("OnUpdate", function(self, elapsed)
        if self.dragging ~= true then return end
        -- (the button let go without a word from the game: the drag ends all the same)
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then return Drop(self) end
        Follow(self)
        Hover(self, elapsed or 0)
    end)
    h:SetScript("OnDragStop", function(self) if self.dragging == true then Drop(self) end end)
    Paint(h)
    return h
end

-- Where the top bar stands: where you dragged it, else at the top of the screen - but never over an element,
-- which couldn't be taken hold of there: then at the top, the bottom or the middle, the first that is clear.
local function BarSpot()
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local bw, bh = bar:GetWidth(), bar:GetHeight()
    local function Covers(l, t)
        for _, h in ipairs(handles) do
            if h:IsShown() and h.l < l + bw and h.l + h.w > l and h.t > t - bh and h.t - h.h < t then return true end
        end
        return false
    end
    local spots = {}
    local at = DB().barAt
    if type(at) == "table" and tonumber(at[1]) and tonumber(at[2]) then spots[1] = { at[1], at[2] } end
    spots[#spots + 1] = { (W - bw) / 2, H - 60 }
    spots[#spots + 1] = { (W - bw) / 2, 60 + bh }
    spots[#spots + 1] = { (W - bw) / 2, (H + bh) / 2 }
    local spot = spots[1]
    for _, s in ipairs(spots) do
        if not Covers(s[1], s[2]) then spot = s break end
    end
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", spot[1], spot[2])
end

-- The grid: lines out from the middle of the screen, the two through the middle in the accent.
local function Grid()
    local S = YR.Style
    local n = 0
    local function Line(vertical, at, strong)
        n = n + 1
        local t = lines[n]
        if not t then
            t = root:CreateTexture(nil, "BACKGROUND", nil, 1)
            lines[n] = t
        end
        local a = S.C.accent
        if strong then t:SetColorTexture(a[1], a[2], a[3], 0.55) else t:SetColorTexture(1, 1, 1, 0.09) end
        t:ClearAllPoints()
        if vertical then
            t:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", at, UIParent:GetHeight())
            t:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", at, 0)
            t:SetWidth(1)
        else
            t:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, at)
            t:SetPoint("TOPRIGHT", UIParent, "BOTTOMRIGHT", 0, at)
            t:SetHeight(1)
        end
        t:Show()
    end
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local g = DB().grid
    if g > 0 then
        for x = (W / 2) % g, W, g do if math.abs(x - W / 2) > 0.5 then Line(true, x) end end
        for y = (H / 2) % g, H, g do if math.abs(y - H / 2) > 0.5 then Line(false, y) end end
    end
    Line(true, W / 2, true)
    Line(false, H / 2, true)
    for i = n + 1, #lines do lines[i]:Hide() end
end

local function Close()
    if not root or not root:IsShown() then return end
    for _, h in ipairs(handles) do
        if h.dragging == true then
            h.dragging = false
            MoveTree(h, h.grab.l, h.grab.t, true)          -- (a drag cut short: back where it was)
        end
        h.over, h.held = nil, nil
    end
    if pending then Unchoose(nil) end
    if armed then Arm(nil, picked or handles[1]) end
    Lines(nil)
    Pick(nil)
    root:UnregisterEvent("PLAYER_REGEN_DISABLED")
    root:Hide()
    if YR.TalentNoticeFrame then YR.TalentNoticeFrame(false) end        -- (its sample points go with the grid)
    if YR.TrainerPopupFrame then YR.TrainerPopupFrame(false) end
    if YR.SwingArranging then YR.SwingArranging(false) end              -- (and the combat bars' samples)
end

local STEP = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
local function OnKey(self, key)
    local step = STEP[key]
    if key == "ESCAPE" then
        self:SetPropagateKeyboardInput(false)
        if pending then Unchoose(nil) else Close() end
    elseif step and picked and not pending then
        self:SetPropagateKeyboardInput(false)
        local by = IsShiftKeyDown() and 10 or 1
        MoveTree(picked, picked.l + step[1] * by, picked.t + step[2] * by, true)
    else
        self:SetPropagateKeyboardInput(true)            -- every other key is the game's, as ever
    end
end

local function Build()
    local S = YR.Style
    root = CreateFrame("Frame", "HeadstartArrange", UIParent)
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("FULLSCREEN")
    root:Hide()
    root:EnableKeyboard(true)
    root:SetScript("OnKeyDown", OnKey)
    root:SetScript("OnEvent", Close)                    -- (a fight began)

    bar = CreateFrame("Frame", nil, root)
    root.bar = bar
    bar:SetSize(840, 92)
    bar:SetPoint("TOP", 0, -60)
    bar:SetFrameLevel(root:GetFrameLevel() + 50)
    bar:EnableMouse(true)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) self:StartMoving() end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local l, t = self:GetLeft(), self:GetTop()
        if l and t then DB().barAt = { math.floor(l + 0.5), math.floor(t + 0.5) } end
    end)
    S.Fill(bar, S.C.bg or { 0.08, 0.08, 0.09, 0.96 })
    S.Border(bar, S.C.accent)
    bar.title = S.Text(bar, 14, S.C.accent)
    bar.title:SetPoint("TOPLEFT", 14, -10)
    bar.title:SetText("Arrange Headstart")
    bar.what = S.Text(bar, 12, S.C.muted)
    bar.what:SetPoint("TOPLEFT", 14, -32)
    bar.what:SetWidth(812)
    bar.what:SetText(HINT)
    bar.grid = S.Button(bar, "Grid", function()
        local db = DB()
        local at = 1
        for i, g in ipairs(GRIDS) do if g == db.grid then at = i end end
        db.grid = GRIDS[at % #GRIDS + 1]
        Grid()
        Readout()
    end, nil, 110)
    bar.grid:SetPoint("BOTTOMLEFT", 14, 10)
    bar.snap = S.Button(bar, "Snap", function()
        local db = DB()
        db.snap = not db.snap
        Readout()
    end, nil, 110)
    bar.snap:SetPoint("LEFT", bar.grid, "RIGHT", 8, 0)
    bar.gap = S.Button(bar, "Gap", function()
        local db = DB()
        local at = 1
        for i, v in ipairs(GAPS) do if v == db.gap then at = i end end
        db.gap = GAPS[at % #GAPS + 1]
        Readout()
    end, nil, 100)
    bar.gap:SetPoint("LEFT", bar.snap, "RIGHT", 8, 0)
    bar.gap.tip = "The space between two elements set side by side, by snapping or by anchoring"
    bar.reset = S.Button(bar, "Reset this one", function()
        if not picked or not picked.item[3] or InCombatLockdown() then return end
        picked.item[3]()
        Sync(picked)
        Readout()
    end, nil, 130)
    bar.reset:SetPoint("LEFT", bar.gap, "RIGHT", 8, 0)
    bar.done = S.Button(bar, "Done", Close, "primary", 110)
    bar.done:SetPoint("BOTTOMRIGHT", -14, 10)
    -- the picked element's place and size, to type into
    panel = CreateFrame("Frame", nil, root)
    root.panel = panel
    panel:SetSize(190, 128)
    panel:SetFrameLevel(root:GetFrameLevel() + 60)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self.moved = true self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    S.Fill(panel, S.C.bg or { 0.08, 0.08, 0.09, 0.96 })
    S.Border(panel, S.C.accent)
    panel.title = S.Text(panel, 13, S.C.accent)
    panel.title:SetPoint("TOPLEFT", 10, -8)
    local function Field(key, label, col, row, commit)
        local name = S.Text(panel, 12, S.C.muted)
        name:SetPoint("TOPLEFT", 10 + col * 90, -34 - row * 30)
        name:SetText(label)
        local box = S.Input(panel, { width = 58, onCommit = function(text)
            local v = tonumber(text)
            if v and picked and not InCombatLockdown() then commit(v) end
            Readout()
        end })
        box:SetPoint("LEFT", name, "LEFT", 18, 0)
        panel[key] = box
    end
    Field("x", "X", 0, 0, function(v) MoveTree(picked, v, picked.t, true) end)
    Field("y", "Y", 1, 0, function(v) MoveTree(picked, picked.l, v, true) end)
    local function Sized(w, h)
        if not picked.item[5] then return end
        local scale = picked.scale or 1
        picked.item[5](w and w / scale, h and h / scale)
        Sync(picked)
    end
    Field("w", "W", 0, 1, function(v) Sized(v, nil) end)
    Field("h", "H", 1, 1, function(v) Sized(nil, v) end)
    panel.anchor = S.Text(panel, 12, S.C.muted)
    panel.anchor:SetPoint("BOTTOMLEFT", 10, 14)
    panel.release = S.Button(panel, "Release", function()
        if not picked then return end
        DB().anchor[picked.item[1]] = nil
        Paint(picked)
        Readout()
    end, nil, 70)
    panel.release:SetPoint("BOTTOMRIGHT", -8, 8)
    panel.release.tip = "No longer moves along with the element it is anchored to"
    panel:Hide()
    -- the lines along what a dragged element lines up with
    for i = 1, 2 do
        local t = root:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(SNAP[1], SNAP[2], SNAP[3], 0.9)
        t:Hide()
        guides[i] = t
    end
    -- the window that asks where an element let go over another goes by it: the spots round a box that
    -- stands for that one
    chooser = CreateFrame("Frame", nil, root)
    root.chooser = chooser
    local BW, BH, PAD, GAP = 104, 24, 10, 6
    chooser:SetSize(PAD * 2 + BW * 3 + GAP * 2, 34 + 6 * (BH + GAP) - GAP + PAD)
    chooser:SetFrameLevel(root:GetFrameLevel() + 70)
    chooser:EnableMouse(true)
    chooser:SetClampedToScreen(true)
    S.Fill(chooser, S.C.bg or { 0.08, 0.08, 0.09, 0.96 })
    S.Border(chooser, S.C.accent)
    chooser.title = S.Text(chooser, 13, S.C.accent)
    chooser.title:SetPoint("TOPLEFT", PAD, -10)
    chooser.title:SetWidth(BW * 3 + GAP * 2)
    local function At(b, col, row) b:SetPoint("TOPLEFT", PAD + (col - 1) * (BW + GAP), -34 - (row - 1) * (BH + GAP)) end
    chooser.spots = {}
    for _, spot in ipairs(SPOTS) do
        local key = spot[1]
        local b = S.Button(chooser, spot[4], function() Unchoose(key) end, nil, BW)
        b:SetHeight(BH)
        At(b, spot[2], spot[3])
        b.preview = function() Preview(key) end
        b:HookScript("OnEnter", b.preview)
        b:HookScript("OnLeave", function() Preview(nil) end)
        chooser.spots[key] = b
    end
    chooser.cancel = S.Button(chooser, "Cancel", function() Unchoose(nil) end, nil, BW)
    chooser.cancel:SetHeight(BH)
    At(chooser.cancel, 3, 6)
    local box = CreateFrame("Frame", nil, chooser)
    box:SetSize(BW, 3 * BH + 2 * GAP)
    At(box, 2, 2)
    S.Fill(box, { ARMED[1], ARMED[2], ARMED[3], 0.14 })
    S.Border(box, ARMED)
    box.label = S.Text(box, 12, S.C.text)
    box.label:SetPoint("CENTER")
    box.label:SetWidth(BW - 8)
    box.label:SetJustifyH("CENTER")
    box.label:SetWordWrap(true)
    chooser.box = box
    chooser:Hide()
    for i, item in ipairs(ITEMS) do handles[i] = Handle(item) end
end

--- Arrange opened (true), or why not (false, and said in chat).
function YR.ArrangeOpen()
    if InCombatLockdown() then
        YR.Print("Arrange isn't opened in a fight.")
        return false
    end
    if not root then Build() end
    if YR.SwingArranging then YR.SwingArranging(true) end      -- (every combat bar shown as it is, to be placed)
    local n = 0
    for _, h in ipairs(handles) do if Sync(h) then n = n + 1 end end
    if n == 0 then
        if YR.SwingArranging then YR.SwingArranging(false) end
        YR.Print("Nothing to arrange: none of Headstart's movable elements is on.")
        return false
    end
    Pick(nil)
    BarSpot()
    Grid()
    root:RegisterEvent("PLAYER_REGEN_DISABLED")
    root:Show()
    return true
end
function YR.ArrangeClose() Close() end
function YR.ArrangeToggle()
    if root and root:IsShown() then Close() return false end
    return YR.ArrangeOpen()
end
