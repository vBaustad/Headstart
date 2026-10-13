-- Arrange: every Headstart element that stands on the screen, moved from one place and to the point.
--   /hs move (or Arrange in the settings window) lays a grid over the screen and a handle over each
--   element that exists: an outline with the element's name in it and nothing else, so the element
--   itself is seen against the grid. Drag a handle, or click it and use the arrow keys: one step a
--   press, ten with Shift. A click also opens a small window beside the element with where it is and
--   how large, to type into (the size only for the elements that have one to set). While dragging, an
--   edge or the middle of the element snaps to the edges and middles of the others and of the screen,
--   and otherwise to the grid. Esc or Done ends it.
--   Anchors: drag an element over another and hold it there a moment (the other turns green), then
--   let go: it is anchored to that one. From then on, moving an element here moves everything anchored
--   to it along, and what is anchored to those. An anchor is a grouping for arranging, kept in
--   YippRouteDB.arrange.anchor = { [element's name] = the name of the one it is anchored to }; the
--   elements themselves still each keep a place of their own, so outside Arrange nothing depends on it.
--   Nothing here knows how an element keeps its place. Each already keeps it when a drag of its own
--   ends, so a move here ends by running that same script: the element saves, in its own way, where
--   it now is. (The trinket buttons only keep a drag they started themselves: they are asked directly.)
--   An element's own lock is not looked at: this is the unlocking.
--   Not in a fight (the trinket buttons may not be moved in one): it won't open in one, and one that
--   begins closes it. Nothing is made until it is first opened, and nothing is listened for while shut.
--   Account options (YippRouteDB.arrange): grid (0 = none, else its size), snap.
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
    { "Swing: ranged", Own("ranged"), SwingReset("ranged"), nil, OwnSize("ranged") },
    { "Cast bar", Own("cast"), SwingReset("cast"), nil, OwnSize("cast") },
    { "Range bar", Own("range"), SwingReset("range"), nil, OwnSize("range") },
    { "Health bar", Own("health"), SwingReset("health"), nil, OwnSize("health") },
    { "Power bar", Own("power"), SwingReset("power"), nil, OwnSize("power") },
    { "Combo points", Own("combo"), SwingReset("combo"), nil, OwnSize("combo") },
    { "XP bar", "HeadstartXPBar", function() YR.XPBarResetPosition() end, nil, XPSize },
    { "Trinket buttons", "HeadstartTrinketBar", function() YR.TrinketResetPosition() end, function() YR.TrinketSavePosition() end },
    { "Loot feed", "HeadstartLootFeed", function() YR.LootFeedResetPosition() end },
    { "Camp icon", "HeadstartCampFrame" },
    -- (shown with two sample points while you arrange, so it can be placed before you have a point to spend)
    { "Talent points notice", function() return YR.TalentNoticeFrame and YR.TalentNoticeFrame(true) or nil end,
        function() YR.TalentNoticeReset() end, function() YR.TalentNoticeSave() end },
    { "Flight timer", "HeadstartFlightFrame" },
    { "Instance counter", "HeadstartInstanceHud", function() YR.InstanceHudResetPosition() end },
    { "Quest group button", "HeadstartQuestLFGButton", function() YR.QuestLFGResetPosition() end },
    { "Group buttons", "HeadstartGroupBar" },
    { "Splits", "HeadstartSplitsFrame" },
}
local GRIDS = { 0, 8, 16, 32, 64 }
local NEAR = 6                  -- how close an edge has to come to another to snap to it
local HOLD = 0.6                -- how long a dragged element is held over another before it offers to anchor
local HINT = "Drag an element, or click it: arrow keys move it (Shift: ten). Hold one over another to anchor it."

local root, bar, panel, picked, armed
local handles, lines = {}, {}

local function DB()
    local db = YippRouteDB.arrange
    if type(db) ~= "table" then
        db = { grid = 16, snap = true }
        YippRouteDB.arrange = db
    end
    if type(db.anchor) ~= "table" then db.anchor = {} end
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
local function Paint(h)
    h.edge:Color(h == armed and { 0.30, 1, 0.40, 1 } or h == picked and { 1, 1, 1, 1 } or YR.Style.C.accent)
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

-- A dragged element held over another: after a moment that one is armed, and letting go anchors to it.
local function Arm(o, h)
    if armed == o then return end
    local was = armed
    armed = o
    if was then Paint(was) end
    if o then Paint(o) end
    bar.what:SetText(o and ("Let go to anchor " .. h.item[1] .. " to " .. o.item[1]) or HINT)
end
local function Hover(h, elapsed)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x, y = x / scale, y / scale
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

-- l, t pulled to what is near: another element's edge or middle, the screen's, or else the grid.
local function Snapped(h, l, t)
    local db = DB()
    if not db.snap then return l, t end
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local xs, ys = { 0, W / 2, W }, { 0, H / 2, H }
    for _, o in ipairs(handles) do
        if o ~= h and o:IsShown() then
            xs[#xs + 1], xs[#xs + 2], xs[#xs + 3] = o.l, o.l + o.w / 2, o.l + o.w
            ys[#ys + 1], ys[#ys + 2], ys[#ys + 3] = o.t, o.t - o.h / 2, o.t - o.h
        end
    end
    local function Pull(at, size, to, sign)
        local best, by = nil, NEAR
        for _, mine in ipairs({ 0, size / 2, size }) do
            for _, x in ipairs(to) do
                local d = x - (at + sign * mine)
                if math.abs(d) < by then best, by = d, math.abs(d) end
            end
        end
        return best
    end
    local dx, dy = Pull(l, h.w, xs, 1), Pull(t, h.h, ys, -1)
    local g = db.grid
    if dx then l = l + dx elseif g > 0 then l = W / 2 + math.floor((l - W / 2) / g + 0.5) * g end
    if dy then t = t + dy elseif g > 0 then t = H / 2 + math.floor((t - H / 2) / g + 0.5) * g end
    return l, t
end

local function Handle(item)
    local S = YR.Style
    local h = CreateFrame("Button", nil, root)
    h.item = item
    h.edge = S.Border(h, S.C.accent)
    h.label = S.Text(h, 11, { 1, 1, 1, 1 })
    h.label:SetFont(S.FONT, 11, "OUTLINE")
    h.label:SetPoint("CENTER")
    h.label:SetText(item[1])
    h:SetMovable(true)
    h:SetClampedToScreen(true)
    h:RegisterForDrag("LeftButton")
    h:SetScript("OnClick", function(self) Pick(self) end)
    h:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        Pick(self)
        self.dragging = true
        self:StartMoving()
    end)
    -- while it is dragged the element goes along, so what is being placed is what is seen
    h:SetScript("OnUpdate", function(self, elapsed)
        if not self.dragging then return end
        local l, t = self:GetLeft(), self:GetTop()
        if l and t and (l ~= self.l or t ~= self.t) then MoveTree(self, l, t, false) end
        Hover(self, elapsed or 0)
    end)
    h:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        self.dragging = nil
        self:StopMovingOrSizing()
        local to = armed
        self.over, self.held = nil, nil
        Arm(nil, self)
        if to then
            DB().anchor[self.item[1]] = to.item[1]
            Paint(self)
        end
        local l, t = self:GetLeft(), self:GetTop()
        if l and t then
            l, t = Snapped(self, l, t)
            MoveTree(self, l, t, true)
        end
    end)
    Paint(h)
    return h
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
        if h.dragging then
            h.dragging = nil
            h:StopMovingOrSizing()
        end
        h.over, h.held = nil, nil
    end
    if armed then Arm(nil, picked or handles[1]) end
    Pick(nil)
    root:UnregisterEvent("PLAYER_REGEN_DISABLED")
    root:Hide()
    if YR.TalentNoticeFrame then YR.TalentNoticeFrame(false) end        -- (its sample points go with the grid)
end

local STEP = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
local function OnKey(self, key)
    local step = STEP[key]
    if key == "ESCAPE" then
        self:SetPropagateKeyboardInput(false)
        Close()
    elseif step and picked then
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
    bar:SetSize(760, 74)
    bar:SetPoint("TOP", 0, -60)
    bar:SetFrameLevel(root:GetFrameLevel() + 50)
    bar:EnableMouse(true)
    S.Fill(bar, S.C.bg or { 0.08, 0.08, 0.09, 0.96 })
    S.Border(bar, S.C.accent)
    bar.title = S.Text(bar, 14, S.C.accent)
    bar.title:SetPoint("TOPLEFT", 14, -10)
    bar.title:SetText("Arrange Headstart")
    bar.what = S.Text(bar, 12, S.C.muted)
    bar.what:SetPoint("LEFT", bar.title, "RIGHT", 14, 0)
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
    bar.reset = S.Button(bar, "Reset this one", function()
        if not picked or not picked.item[3] or InCombatLockdown() then return end
        picked.item[3]()
        Sync(picked)
        Readout()
    end, nil, 130)
    bar.reset:SetPoint("LEFT", bar.snap, "RIGHT", 8, 0)
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
    for i, item in ipairs(ITEMS) do handles[i] = Handle(item) end
end

--- Arrange opened (true), or why not (false, and said in chat).
function YR.ArrangeOpen()
    if InCombatLockdown() then
        YR.Print("Arrange isn't opened in a fight.")
        return false
    end
    if not root then Build() end
    local n = 0
    for _, h in ipairs(handles) do if Sync(h) then n = n + 1 end end
    if n == 0 then
        YR.Print("Nothing to arrange: none of Headstart's movable elements is on.")
        return false
    end
    Pick(nil)
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
