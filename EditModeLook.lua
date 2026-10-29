-- Edit Mode outlines: in the game's Edit Mode every element is covered by a large blue sheet (yellow on the one
-- picked) with its name in large letters across the middle, so with the screen full of them you can't see what you
-- are placing or what it lines up with (the owner, 2026-10-29: "de svære blå overlays ... umulig å se hvor du
-- plasserer ting"). On, each element is a clean dark block instead, as EllesmereUI's unlock mode draws its own
-- (the owner pointed there; the idea is taken, not the code):
--   at rest     a dark slate block, a one-pixel edge in Headstart's accent, half strength, and the element's name
--               small in the middle - every element says what it is, and its edges are sharp against anything
--   the mouse   the edge white
--   picked      the edge in the full accent, two pixels, the block warmed toward it, the name in the accent, and
--               where it stands in the corner: pixels from the middle of the screen, counted live while you drag
-- Blizzard's sheet, its mouse-over glow and its large name are made clear. (Before, the same day: a blue line of a
-- pixel, "umulig å faktisk se"; then lines round a see-through block, "det ble ikke så bra".)
--   How: nothing of Blizzard's is replaced and no field is written on its frames. Blizzard's pieces are made clear
--   with SetAlpha and put back as they were when this is turned off; ours are textures and a text frame of our own
--   on each element's selection frame, kept in a table of ours. Each frame's ShowHighlighted and ShowSelected are
--   followed with hooksecurefunc (it runs after Blizzard's own and taints nothing of it); its mouse-over and its drag
--   with HookScript. The position is counted on every frame only while a drag lasts. The frames are taken as Edit
--   Mode opens: before that, nothing is touched.
--   Account option (YippRouteDB): editModeOutline (off until you turn it on).
local ADDON, YR = ...

-- Blizzard's: the sheet's nine pieces, and the names it writes across the middle
local PIECES = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }
local LABELS = { "Label", "HorizontalLabel", "VerticalLabel" }

local BLOCK = { 0.075, 0.105, 0.135, 0.88 }    -- dark slate: one colour on any ground
local WARM = { 0.16, 0.11, 0.07, 0.92 }        -- the block picked: warmed toward the accent
local HOVER = { 1, 1, 1, 0.9 }
local NAME = { 1, 1, 1, 0.78 }
local REST_EDGE = 0.55                         -- the accent's strength on an edge at rest

local seen = setmetatable({}, { __mode = "k" })     -- [selection frame] = what we drew on it, and Blizzard's alphas

function YR.EditModeOutlineOn() return YR.Option("editModeOutline") end

local function Accent()
    local st = YR.Style
    return st and st.C and st.C.accent or { 1, 0.56, 0.2, 1 }
end

-- One point of this frame in screen pixels (1 where the game can't say).
local function Px(sel)
    local st = YR.Style
    local ppu = st and st.PixelsPerPoint and st.PixelsPerPoint(sel)
    return ppu and 1 / ppu or 1
end

local function Colour(t, c) t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end

-- The edge: four textures along the inside of the frame's edges, `w` thick.
local function PlaceEdge(sel, r, w)
    local top, bottom, left, right = r[1], r[2], r[3], r[4]
    top:ClearAllPoints() top:SetPoint("TOPLEFT", sel, "TOPLEFT") top:SetPoint("TOPRIGHT", sel, "TOPRIGHT") top:SetHeight(w)
    bottom:ClearAllPoints() bottom:SetPoint("BOTTOMLEFT", sel, "BOTTOMLEFT") bottom:SetPoint("BOTTOMRIGHT", sel, "BOTTOMRIGHT")
    bottom:SetHeight(w)
    left:ClearAllPoints() left:SetPoint("TOPLEFT", sel, "TOPLEFT", 0, -w) left:SetPoint("BOTTOMLEFT", sel, "BOTTOMLEFT", 0, w)
    left:SetWidth(w)
    right:ClearAllPoints() right:SetPoint("TOPRIGHT", sel, "TOPRIGHT", 0, -w) right:SetPoint("BOTTOMRIGHT", sel, "BOTTOMRIGHT", 0, w)
    right:SetWidth(w)
end

local function Name(sel)
    local sys = sel.system
    if type(sys) == "table" and type(sys.GetSystemName) == "function" then
        local ok, name = pcall(sys.GetSystemName, sys)
        if ok and type(name) == "string" then return name end
    end
    return ""
end

-- Where it stands: its middle, in screen pixels from the middle of the screen ("-412, 180").
local function Where(sel)
    local x, y = sel:GetCenter()
    local s = sel:GetEffectiveScale()
    local px = _G.PixelUtil
    local f = type(px) == "table" and px.GetPixelToUIUnitFactor and px.GetPixelToUIUnitFactor()
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local us = UIParent:GetEffectiveScale()
    if type(x) ~= "number" or type(y) ~= "number" or type(s) ~= "number" or type(f) ~= "number" or f <= 0
        or type(sw) ~= "number" or type(sh) ~= "number" or type(us) ~= "number" then return nil end
    local cx, cy = sw * us / 2, sh * us / 2          -- the screen's middle, at scale 1
    return ("%d, %d"):format(math.floor((x * s - cx) / f + 0.5), math.floor((y * s - cy) / f + 0.5))
end

local function Coords(text)
    text.coords:SetText(Where(text.sel) or "")
end

-- As the switch says, after Blizzard has drawn its own: Blizzard's clear and ours on, or Blizzard's as it was.
local function Paint(sel)
    local k = seen[sel]
    if not k then return end
    local on = YR.EditModeOutlineOn()
    for _, name in ipairs(PIECES) do
        local t = sel[name]
        if type(t) == "table" and t.SetAlpha then t:SetAlpha(on and 0 or 1) end
    end
    for name, alpha in pairs(k.alphas) do
        local t = sel[name]
        if type(t) == "table" and t.SetAlpha then t:SetAlpha(on and 0 or alpha) end
    end
    if not on then
        for _, t in ipairs(k.edge) do t:Hide() end
        k.block:Hide() k.text:Hide()
        k.text:SetScript("OnUpdate", nil)
        k.state, k.ticking = "off", false
        return
    end
    local picked = sel.isSelected == true
    local state = picked and "picked" or (k.hover and "hover" or "rest")
    local a = Accent()
    local edge = picked and { a[1], a[2], a[3], 1 } or (k.hover and HOVER or { a[1], a[2], a[3], REST_EDGE })
    local block = picked and WARM or BLOCK
    local thick = (picked and 2 or 1) * Px(sel)
    PlaceEdge(sel, k.edge, thick)
    for _, t in ipairs(k.edge) do Colour(t, edge) t:Show() end
    Colour(k.block, block)
    k.block:Show()
    -- the name in the middle, wrapped to the block's width (a bar stood on end reads "Action / Bar 4")
    local name = k.text.name
    name:SetText(Name(sel))
    local w = sel:GetWidth()
    if type(w) == "number" then name:SetWidth(math.max(10, w - 6)) end
    if picked then name:SetTextColor(a[1], a[2], a[3], 1) else name:SetTextColor(NAME[1], NAME[2], NAME[3], NAME[4]) end
    -- where it stands: the one picked, if it has room for a line above its name
    local h = sel:GetHeight()
    local roomy = type(h) == "number" and h >= 24
    k.text.coords:SetShown(picked and roomy)
    if picked and roomy then Coords(k.text) end
    k.text:Show()
    k.state, k.colour, k.thick, k.fillColour = state, edge, thick, block
end

local function Enter(sel) local k = seen[sel] if k then k.hover = true Paint(sel) end end
local function Leave(sel) local k = seen[sel] if k then k.hover = false Paint(sel) end end
-- a drag: the position counted on every frame while it lasts, and only then
local function Tick(text)
    if not text:IsShown() then return end
    Coords(text)
end
local function DragStart(sel)
    local k = seen[sel]
    if not (k and YR.EditModeOutlineOn()) then return end
    k.ticking = true                    -- (the position shows where Paint found room for it)
    k.text:SetScript("OnUpdate", Tick)
end
local function DragStop(sel)
    local k = seen[sel]
    if not (k and k.ticking) then return end
    k.ticking = false
    k.text:SetScript("OnUpdate", nil)
    Paint(sel)
end

local function Take(sel)
    if type(sel) ~= "table" or seen[sel] or type(sel.CreateTexture) ~= "function" then return end
    -- Blizzard's that we make clear: their alphas as they are now, to put back
    local alphas = {}
    for _, name in ipairs(LABELS) do
        local t = sel[name]
        if type(t) == "table" and t.GetAlpha then alphas[name] = t:GetAlpha() end
    end
    local glow = sel.MouseOverHighlight
    if type(glow) == "table" and glow.GetAlpha then alphas.MouseOverHighlight = glow:GetAlpha() end
    local k = { alphas = alphas, edge = {} }
    k.block = sel:CreateTexture(nil, "BACKGROUND", nil, 7)
    k.block:SetAllPoints(sel)
    k.block:Hide()
    for i = 1, 4 do k.edge[i] = sel:CreateTexture(nil, "OVERLAY", nil, 7) k.edge[i]:Hide() end
    -- the texts, on a frame of their own over the block, cut at its edges
    local st = YR.Style
    local font = st and st.FONT or "Fonts\\ARIALN.TTF"
    local text = CreateFrame("Frame", nil, sel)
    text:SetAllPoints(sel)
    if text.SetClipsChildren then text:SetClipsChildren(true) end
    text.sel = sel
    local name = text:CreateFontString(nil, "OVERLAY")
    name:SetFont(font, 10, "")
    name:SetShadowOffset(1, -1)
    name:SetShadowColor(0, 0, 0, 1)
    name:SetJustifyH("CENTER")
    name:SetWordWrap(true)
    name:SetPoint("CENTER")
    text.name = name
    local coords = text:CreateFontString(nil, "OVERLAY")
    coords:SetFont(font, 9, "")
    coords:SetShadowOffset(1, -1)
    coords:SetShadowColor(0, 0, 0, 1)
    coords:SetTextColor(1, 1, 1, 0.7)
    coords:SetPoint("TOPLEFT", 4, -3)
    coords:Hide()
    text.coords = coords
    text:Hide()
    k.text = text
    seen[sel] = k
    if type(sel.ShowHighlighted) == "function" then hooksecurefunc(sel, "ShowHighlighted", Paint) end
    if type(sel.ShowSelected) == "function" then hooksecurefunc(sel, "ShowSelected", Paint) end
    sel:HookScript("OnEnter", Enter)
    sel:HookScript("OnLeave", Leave)
    sel:HookScript("OnDragStart", DragStart)
    sel:HookScript("OnDragStop", DragStop)
    sel:HookScript("OnHide", DragStop)
end

--- Every element Edit Mode knows taken and painted as the switch says. Returns how many there are.
function YR.EditModeLookApply()
    local mgr = _G.EditModeManagerFrame
    local list = type(mgr) == "table" and mgr.registeredSystemFrames
    if YR.EditModeOutlineOn() and type(list) == "table" then
        for _, f in ipairs(list) do
            if type(f) == "table" then Take(f.Selection) end
        end
    end
    local n = 0
    for sel in pairs(seen) do
        Paint(sel)
        n = n + 1
    end
    return n
end

--- For the tests: what an element shows - "off", "rest", "hover" or "picked", the edge's colour and thickness in
--- points, the block's colour, the name and the position (nil while each is hidden), and whether a drag is counted.
function YR.EditModeLookShown(sel)
    local k = seen[sel]
    if not k then return nil end
    local shown = k.text:IsShown()
    return { state = k.state, colour = k.colour, thick = k.thick, fill = k.block:IsShown() and k.fillColour or nil,
        name = shown and k.text.name:GetText() or nil, coords = shown and k.text.coords:IsShown() and k.text.coords:GetText() or nil,
        edge = k.edge[1]:IsShown(), ticking = k.ticking == true }
end

local declared
function YR.StartEditModeLook()
    if declared then return end
    declared = true
    YR.Part(YR.EditModeOutlineOn, nil, nil, {
        start = function(p)
            local registry = _G.EventRegistry
            if type(registry) == "table" and registry.RegisterCallback then
                p.owner = p.owner or {}
                registry:RegisterCallback("EditMode.Enter", YR.EditModeLookApply, p.owner)
            end
            YR.EditModeLookApply()
        end,
        -- off: Edit Mode is let go of, and Blizzard's put back as it was
        stop = function(p)
            local registry = _G.EventRegistry
            if p.owner and type(registry) == "table" and registry.UnregisterCallback then
                registry:UnregisterCallback("EditMode.Enter", p.owner)
            end
            YR.EditModeLookApply()
        end,
    })
end
