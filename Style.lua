-- Our own look, instead of Blizzard's frames. Every Headstart window is built from these pieces, so
-- the look lives in one place: flat layered panels, a thin border, one accent colour, clean narrow
-- text, and controls that say what they do.
local _, YR = ...

local S = {}
YR.Style = S

S.FONT = "Fonts\\ARIALN.TTF"
-- Warm charcoal with one ember accent: the surfaces lean a little brown rather than blue, the text is
-- a warm white. onAccent is what is written on something filled with the accent (dark: every accent
-- here is a light colour).
S.C = {
    window  = { 0.086, 0.078, 0.071, 0.98 },
    side    = { 0.063, 0.057, 0.052, 1 },
    card    = { 0.128, 0.117, 0.107, 1 },
    stripe  = { 0.108, 0.098, 0.089, 1 },       -- a card's head, and every other row of a list
    field   = { 0.050, 0.045, 0.041, 1 },
    line    = { 1, 0.96, 0.90, 0.075 },
    lineHi  = { 1, 0.96, 0.90, 0.17 },
    hover   = { 1, 0.96, 0.90, 0.05 },
    accent  = { 1.00, 0.56, 0.20, 1 },
    accentD = { 1.00, 0.56, 0.20, 0.16 },
    accentHi = { 1.00, 0.66, 0.34, 1 },
    accentLo = { 0.88, 0.47, 0.14, 1 },
    onAccent = { 0.10, 0.07, 0.04, 1 },
    text    = { 0.95, 0.93, 0.90, 1 },
    sub     = { 0.75, 0.72, 0.68, 1 },
    muted   = { 0.54, 0.51, 0.48, 1 },
    green   = { 0.45, 0.82, 0.50, 1 },
    -- a switch that is on, and a button that is the page's one thing to do: bone, not the accent (the owner,
    -- 2026-10-21: "too much orange"). The accent says where you are: the tab, the page.
    on      = { 0.82, 0.77, 0.68, 1 },
    swOn    = { 0.83, 0.50, 0.24, 1 },          -- a switch that is on: the accent toned a little into the card (Theme)
    swKnob  = { 0.98, 0.97, 0.94, 1 },
    swOff   = { 0.227, 0.208, 0.184, 1 },
    swOffHi = { 0.275, 0.251, 0.227, 1 },
    knobOff = { 0.604, 0.569, 0.518, 1 },
    knobOffHi = { 0.698, 0.663, 0.608, 1 },
    boxLine = { 0.373, 0.341, 0.302, 1 },       -- a checkbox not ticked: its edge
    boxLineHi = { 0.541, 0.506, 0.455, 1 },
    boxOn   = { 0.902, 0.867, 0.804, 1 },       -- ticked: light, a dark tick (no accent: a page of options stays quiet)
    tickInk = { 0.10, 0.09, 0.075, 1 },
    well    = { 0.104, 0.095, 0.086, 1 },       -- a feature's settings, under it: a shade under the card
    onHi    = { 0.92, 0.88, 0.80, 1 },
    onInk   = { 0.10, 0.09, 0.075, 1 },
    offTrack = { 0.20, 0.19, 0.165, 1 },
    offKnob = { 0.55, 0.52, 0.47, 1 },
    raised  = { 0.150, 0.135, 0.115, 1 },
    danger  = { 1.00, 0.45, 0.42, 1 },
    gold    = { 1.00, 0.82, 0.36, 1 },
}

-- The accents to choose from (Headstart page, Look). "class" is your class's colour. The surfaces are
-- the same for all but Frost, which is the cool grey and blue Headstart had before.
S.ACCENTS = {
    { "ember", "Ember", { 1.00, 0.56, 0.20 } },
    { "gold", "Gold", { 0.96, 0.78, 0.30 } },
    { "moss", "Moss", { 0.56, 0.80, 0.38 } },
    { "jade", "Jade", { 0.28, 0.82, 0.66 } },
    { "rose", "Rose", { 0.96, 0.48, 0.58 } },
    { "violet", "Violet", { 0.72, 0.58, 1.00 } },
    { "class", "My class's colour" },
    { "frost", "Frost (the old look)", { 0.40, 0.66, 1.00 } },
}
local FROST = {
    window = { 0.075, 0.08, 0.095, 0.98 }, side = { 0.055, 0.06, 0.07, 1 }, card = { 0.11, 0.12, 0.14, 1 },
    field = { 0.045, 0.05, 0.06, 1 }, stripe = { 0.095, 0.105, 0.125, 1 }, line = { 1, 1, 1, 0.07 }, lineHi = { 1, 1, 1, 0.16 }, hover = { 1, 1, 1, 0.045 },
    text = { 0.93, 0.94, 0.96, 1 }, sub = { 0.70, 0.73, 0.78, 1 }, muted = { 0.50, 0.53, 0.58, 1 },
}

local WARM = {}
for name in pairs(FROST) do WARM[name] = { unpack(S.C[name]) } end

local function Into(t, r, g, b, a)
    t[1], t[2], t[3], t[4] = r, g, b, a or t[4] or 1
end

--- The look's colours set from the accent chosen (YippRouteDB.accent, "ember" unless set). The colour
--- tables are changed in place, so everything made afterwards has them; what is already on screen keeps
--- its colours until a reload. Called once as Headstart starts, before any window of ours is made.
function S.Theme(key)
    key = key or (type(YippRouteDB) == "table" and YippRouteDB.accent) or "ember"
    local pick = S.ACCENTS[1]
    for _, a in ipairs(S.ACCENTS) do if a[1] == key then pick = a end end
    local c = pick[3]
    if pick[1] == "class" then
        local _, class = UnitClass("player")
        local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        c = cc and { cc.r, cc.g, cc.b } or S.ACCENTS[1][3]
    end
    for name, v in pairs(pick[1] == "frost" and FROST or WARM) do Into(S.C[name], v[1], v[2], v[3], v[4]) end
    local r, g, b = c[1], c[2], c[3]
    Into(S.C.accent, r, g, b, 1)
    Into(S.C.accentD, r, g, b, 0.16)
    Into(S.C.accentHi, r + (1 - r) * 0.22, g + (1 - g) * 0.22, b + (1 - b) * 0.22, 1)
    Into(S.C.accentLo, r * 0.86, g * 0.86, b * 0.86, 1)
    local card = S.C.card
    Into(S.C.swOn, r * 0.86 + card[1] * 0.14, g * 0.86 + card[2] * 0.14, b * 0.86 + card[3] * 0.14, 1)
    Into(S.C.well, card[1] * 0.82, card[2] * 0.82, card[3] * 0.82, 1)
    -- a dark accent (a shaman's blue, a death knight's red) is written on in white
    local light = 0.30 * r + 0.59 * g + 0.11 * b
    if light < 0.5 then Into(S.C.onAccent, 1, 1, 1, 1) else Into(S.C.onAccent, 0.10, 0.07, 0.04, 1) end
    return pick[1]
end

--- Called after any control of ours changed a setting (Core.lua puts YR.SettingChanged here: the parts
--- of Headstart that listen only while they are wanted are looked at again).
function S.Changed() end

local function Set(tex, color) tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1) end
S.Set = Set

function S.Fill(frame, color, layer, sub)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    t:SetAllPoints()
    Set(t, color)
    return t
end

--- A line one screen pixel thick, whatever the UI scale: axis "h" sets its height, "v" its width. (A line of one point
--- is 1.2 pixels at 2560 x 1440 and the game's own scale, and was drawn one pixel here and two there - the owner,
--- 2026-10-21: "think of the 1080 players too"; under one pixel to a point, as at 1080 with a small UI, it could
--- vanish.) Where the game can't say how large a pixel is: one point.
function S.Hair(tex, axis)
    local ppu = S.PixelsPerPoint and S.PixelsPerPoint(tex)
    local size = ppu and 1 / ppu or 1
    if axis == "v" then tex:SetWidth(size) else tex:SetHeight(size) end
    return tex
end

-- A one-pixel border from four textures; returns them so a focus state can recolour them.
function S.Border(frame, color)
    local edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = frame:CreateTexture(nil, "BORDER")
        Set(t, color or S.C.line)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT") t:SetPoint(side .. "RIGHT") S.Hair(t, "h")
        else
            t:SetPoint("TOP" .. side) t:SetPoint("BOTTOM" .. side) S.Hair(t, "v")
        end
        edges[#edges + 1] = t
    end
    function edges:Color(c) for _, t in ipairs(self) do Set(t, c) end end
    return edges
end

function S.Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(S.FONT, size or 13, "")
    fs:SetTextColor(unpack(color or S.C.text))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

function S.Icon(parent, texture, size)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size or 16, size or 16)
    t:SetTexture(texture)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return t
end

-- A rounded shape from art/round.tga (or roundline.tga, an outline), stretched in the middle with its
-- corners kept (9-slice), tinted with SetVertexColor. Without 9-slice support it falls back to flat.
local function Rounded(frame, layer, name, sublevel)
    local t = frame:CreateTexture(nil, layer, nil, sublevel)
    t:SetAllPoints()
    if t.SetTextureSliceMargins then
        t:SetTexture(S.ART .. name)
        t:SetTextureSliceMargins(8, 8, 8, 8)
        if t.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
            t:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        end
    else
        t:SetColorTexture(1, 1, 1, 1)
    end
    return t
end
S.Rounded = Rounded

--- A texture drawn where it falls, not snapped to the screen's pixel grid: a small shape scaled down from a larger
--- texture stays round and sharp (snapped, the switch and its knob were soft and uneven: the owner, 2026-10-21, "feels
--- so low resolution" - Naowh Forever draws its own so).
function S.Smooth(tex)
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    return tex
end

--- A soft shadow under a panel (art/shadow.tga, sliced in nine), spread out round it and dropped a little: what lifts
--- a window, a menu or the settings list off what is behind it. alpha: how dark (0.55).
function S.Shadow(frame, spread, drop, alpha)
    spread, drop = spread or 16, drop or 3
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    t:SetPoint("TOPLEFT", -spread, spread - drop)
    t:SetPoint("BOTTOMRIGHT", spread, -spread - drop)
    t:SetTexture(S.ART .. "shadow")
    if t.SetTextureSliceMargins then
        t:SetTextureSliceMargins(24, 24, 24, 24)
        if t.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then t:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched) end
    end
    t:SetVertexColor(0, 0, 0, alpha or 0.55)
    S.Smooth(t)
    return t
end

-- Colours per kind and state: { fill, outline or false, text }
local LOOK = {
    primary = { normal = { { 1, 1, 1, 0.09 }, { 1, 1, 1, 0.20 }, S.C.text },
                hover  = { { 1, 1, 1, 0.14 }, { 1, 1, 1, 0.30 }, S.C.text },
                down   = { { 1, 1, 1, 0.06 }, { 1, 1, 1, 0.24 }, S.C.text } },
    quiet   = { normal = { { 1, 1, 1, 0.06 }, { 1, 1, 1, 0.14 }, S.C.text },
                hover  = { { 1, 1, 1, 0.10 }, { 1, 1, 1, 0.24 }, S.C.text },
                down   = { { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.20 }, S.C.text } },
    danger  = { normal = { { 0.62, 0.20, 0.20, 1 }, false, { 1, 1, 1, 1 } },
                hover  = { { 0.72, 0.25, 0.25, 1 }, false, { 1, 1, 1, 1 } },
                down   = { { 0.55, 0.17, 0.17, 1 }, false, { 1, 1, 1, 1 } } },
    ghost   = { normal = { { 1, 1, 1, 0 }, false },
                hover  = { { 1, 1, 1, 0.07 }, false },
                down   = { { 1, 1, 1, 0.04 }, false } },
}
local DISABLED = { { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.07 }, S.C.muted }

-- Buttons. kind: "primary" (the one main action), "danger", "ghost" (text only until hovered), or nil.
-- Rounded, with hover and pressed states; a disabled button goes quiet and grey rather than faded.
function S.Button(parent, label, onClick, kind, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(28)
    local look = LOOK[kind] or LOOK.quiet
    local fill = Rounded(b, "BACKGROUND", "round")
    local line = Rounded(b, "BORDER", "roundline")
    b.text = S.Text(b, 13, (look.normal[3]) or S.C.text)
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(label)
    b:SetWidth(width or math.max(80, b.text:GetStringWidth() + 32))
    local hovering, pressed, textColor = false, false, nil
    local function Paint()
        local st = not b:IsEnabled() and DISABLED or look[pressed and "down" or hovering and "hover" or "normal"]
        fill:SetVertexColor(unpack(st[1]))
        line:SetShown(st[2] and true or false)
        if st[2] then line:SetVertexColor(unpack(st[2])) end
        -- a ghost button keeps the text colour it was given, except when disabled
        if st[3] then b.text:SetTextColor(unpack(st[3]))
        elseif textColor then b.text:SetTextColor(unpack(textColor)) end
    end
    b.Paint = Paint
    b:SetScript("OnEnter", function()
        hovering = true Paint()
        if b.tip then S.Tip(b, b.tip) end
    end)
    b:SetScript("OnLeave", function() hovering, pressed = false, false Paint() GameTooltip:Hide() end)
    b:SetScript("OnMouseDown", function() pressed = true Paint() end)
    b:SetScript("OnMouseUp", function() pressed = false Paint() end)
    b:SetScript("OnEnable", Paint)
    b:SetScript("OnDisable", Paint)
    b:SetScript("OnClick", onClick)
    function b:SetLabel(t) self.text:SetText(t) end
    -- for ghost buttons: the colour of their text
    function b:SetTextColour(c) textColor = c Paint() end
    Paint()
    return b
end

-- A square button showing an icon texture or a single character.
-- Our own icons (art/*.tga, white, tinted here). "down" is "up" turned over.
S.ART = "Interface\\AddOns\\Headstart\\art\\"

function S.ArtTexture(tex, name)
    tex:SetTexture(S.ART .. (name == "down" and "up" or name))
    if name == "down" then tex:SetTexCoord(0, 1, 1, 0) else tex:SetTexCoord(0, 1, 0, 1) end
end

-- A small square button with one of our icons (or, for anything else, a texture path).
function S.IconButton(parent, icon, onClick, tip, color, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 22, size or 22)
    local bg = S.Fill(b, { 1, 1, 1, 0 })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize((size or 22) - 8, (size or 22) - 8)
    b.icon:SetPoint("CENTER")
    if icon:find("[\\/]") then b.icon:SetTexture(icon) else S.ArtTexture(b.icon, icon) end
    local rest = color or S.C.muted
    b.icon:SetVertexColor(unpack(rest))
    b:SetScript("OnEnter", function()
        bg:SetColorTexture(1, 1, 1, 0.08)
        b.icon:SetVertexColor(unpack(color == S.C.danger and S.C.danger or S.C.text))
        if tip then S.Tip(b, tip) end
    end)
    b:SetScript("OnLeave", function()
        bg:SetColorTexture(1, 1, 1, 0)
        b.icon:SetVertexColor(unpack(rest))
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", onClick)
    return b
end

--- A small window's close button: a clear cross (art/x, bolder than the title bar's "close"), quiet at rest and white
--- under the mouse (the owner, 2026-10-21, of the trainer window's: "make the X better" - a speck before; then, at 14
--- and light: "a bit much", 2026-10-22 - 12, the muted grey).
function S.CloseX(parent, onClick, tip)
    return S.IconButton(parent, "x", onClick, tip, S.C.muted, 20)
end

function S.Tip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

-- A details card in our look, for the (i) on a settings row: the row's name, then its text wrapped.
-- S.ShowInfo shows it above owner; pin keeps it there after the mouse moves off, until S.Unpin or
-- another pin. S.HideInfo hides it unless it is pinned, then brings the pinned one back.
local info, pinned
local function InfoCard()
    if info then return info end
    info = CreateFrame("Frame", nil, UIParent)
    info:SetFrameStrata("TOOLTIP")
    info:SetClampedToScreen(true)
    info:SetWidth(300)
    local fill = Rounded(info, "BACKGROUND", "round")
    fill:SetVertexColor(0.13, 0.14, 0.17, 0.98)
    info.line = Rounded(info, "BORDER", "roundline")
    info.title = S.Text(info, 13, S.C.text)
    info.title:SetPoint("TOPLEFT", 12, -10)
    info.title:SetPoint("RIGHT", -12, 0)
    info.body = S.Text(info, 12, S.C.sub)
    info.body:SetPoint("TOPLEFT", info.title, "BOTTOMLEFT", 0, -6)
    info.body:SetPoint("RIGHT", -12, 0)
    info.body:SetWordWrap(true)
    info.body:SetSpacing(2)
    info.hint = S.Text(info, 11, S.C.muted)
    info.hint:SetPoint("TOPLEFT", info.body, "BOTTOMLEFT", 0, -8)
    return info
end

function S.ShowInfo(owner, title, text, pin)
    local f = InfoCard()
    if pin then pinned = { owner = owner, title = title, text = text } end
    local isPinned = pinned and pinned.owner == owner
    f.title:SetText(title)
    f.body:SetText(text)
    f.hint:SetText("")
    f.line:SetVertexColor(unpack(isPinned and S.C.accent or S.C.lineHi))
    f:SetHeight(10 + f.title:GetStringHeight() + 6 + f.body:GetStringHeight() + 8
        + f.hint:GetStringHeight() + 12)
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 4)
    f:Show()
end

function S.HideInfo()
    if not info then return end
    if pinned and pinned.owner:IsVisible() then
        S.ShowInfo(pinned.owner, pinned.title, pinned.text)
    else
        pinned = nil
        info:Hide()
    end
end


function S.Unpin()
    pinned = nil
    if info then info:Hide() end
end

-- On/off switch with its label to the right (and an optional grey note under it).
function S.Toggle(parent, label, get, set, note)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(300, note and 36 or 22)
    local track = b:CreateTexture(nil, "ARTWORK")
    track:SetSize(32, 16)
    track:SetPoint("TOPLEFT", 0, -3)
    local knob = b:CreateTexture(nil, "OVERLAY")
    knob:SetSize(12, 12)
    local text = S.Text(b, 13)
    text:SetPoint("TOPLEFT", track, "TOPRIGHT", 10, 1)
    text:SetText(label)
    if note then
        local n = S.Text(b, 11, S.C.muted)
        n:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -3)
        n:SetText(note)
    end
    function b:Refresh()
        local on = get()
        Set(track, on and S.C.on or S.C.offTrack)
        Set(knob, on and S.C.onInk or S.C.offKnob)
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", track, "LEFT", on and 18 or 2, 0)
    end
    b:SetScript("OnClick", function() set(not get()) b:Refresh() S.Changed() end)
    b:Refresh()
    return b
end

-- A one-line text input. opts: width, numeric, placeholder, onChange(text) (on every edit),
-- onCommit(text) (Enter or leaving the field).
function S.Input(parent, opts)
    opts = opts or {}
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(opts.width or 160, 24)
    box:SetAutoFocus(false)
    box:SetFont(S.FONT, 13, "")
    box:SetTextColor(unpack(S.C.text))
    box:SetTextInsets(7, 7, 0, 0)
    S.Fill(box, S.C.field)
    local border = S.Border(box)
    local hint = S.Text(box, 12, S.C.muted)
    hint:SetPoint("LEFT", 7, 0)
    hint:SetText(opts.placeholder or "")
    local function Hint() hint:SetShown(box:GetText() == "" and not box:HasFocus()) end
    box:SetScript("OnEditFocusGained", function() border:Color(S.C.accent) Hint() end)
    box:SetScript("OnEditFocusLost", function()
        border:Color(S.C.line) Hint()
        if opts.onCommit then opts.onCommit(box:GetText()) S.Changed() end
    end)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnTextChanged", function(_, user)
        Hint()
        if user and opts.onChange then opts.onChange(box:GetText()) end
    end)
    function box:SetValue(v)
        self:SetText(v == nil and "" or tostring(v))
        self:SetCursorPosition(0)
        Hint()
    end
    Hint()
    return box
end

-- A dropdown: shows the current choice; clicking opens a menu. options = { { value, label } } or a
-- function returning them. onPick(value). side (optional) puts a small icon button at the right of
-- every line that does something with that line's value without picking it or closing the menu (the
-- speaker that plays a sound): { icon = one of our art names, tip = , onClick = function(value),
-- shows = function(value) (optional: which lines have it) }.
local menu, catcher
local function CloseMenu() if menu then menu:Hide() end if catcher then catcher:Hide() end end
S.CloseMenu = CloseMenu

function S.OpenMenu(anchor, options, onPick, width, side)
    -- the same button again closes its menu
    if menu and menu:IsShown() and menu.anchor == anchor then CloseMenu() return end
    if not menu then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        -- over every window of ours, the ones in the topmost layer too (the planner, the macro helper):
        -- a menu in their own layer opened behind them
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetFrameLevel(9000)
        catcher:RegisterForClicks("AnyUp")          -- (the right button too: it was swallowed, and closed nothing)
        catcher:SetScript("OnClick", CloseMenu)
        -- a fight closes the menu: listened for only while it is up
        catcher:SetScript("OnShow", function(self) self:RegisterEvent("PLAYER_REGEN_DISABLED") end)
        catcher:SetScript("OnHide", function(self) self:UnregisterEvent("PLAYER_REGEN_DISABLED") end)
        catcher:SetScript("OnEvent", CloseMenu)
        menu = CreateFrame("Frame", "HeadstartDropMenu", UIParent)
        S.Shadow(menu, 14, 4, 0.6)
        menu:SetFrameStrata("TOOLTIP")
        menu:SetClampedToScreen(true)
        -- Three ways out besides picking something: the button again (above), Esc, and a click anywhere
        -- that isn't the menu. The click is heard from the game itself, whatever frame it lands on: the
        -- catcher alone could end up under a window and then nothing closed the menu.
        tinsert(UISpecialFrames, "HeadstartDropMenu")
        menu:SetScript("OnHide", function() if catcher then catcher:Hide() end end)
        menu:SetScript("OnEvent", function(self)
            if not self:IsShown() or self:IsMouseOver() then return end
            if self.anchor and self.anchor.IsMouseOver and self.anchor:IsMouseOver() then return end   -- (its own click closes it)
            CloseMenu()
        end)
        menu:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
        menu:HookScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
        S.Fill(menu, S.C.card)
        S.Border(menu, S.C.lineHi)
        menu.items = {}
        menu:EnableMouseWheel(true)
        menu:SetScript("OnMouseWheel", function(self, d)
            self.offset = math.max(0, math.min(#self.options - self.count, self.offset - d * 2))
            self:Fill()
        end)
        function menu:Fill()
            for i = 1, self.count do
                local item, o = self.items[i], self.options[i + self.offset]
                if o then
                    item:Show()
                    item.value = o[1]
                    item.label:SetText(o[2])
                    item.label:SetTextColor(unpack(o[3] or S.C.text))
                    local extra = rawget(self, "side")
                    local has = extra and (not extra.shows or extra.shows(o[1])) and true or false
                    item.label:SetPoint("RIGHT", has and -28 or -8, 0)
                    local button = rawget(item, "side")
                    if has and not button then
                        item.side = S.IconButton(item, extra.icon, function() menu.side.onClick(item.value) end, nil, nil, 20)
                        item.side:SetPoint("RIGHT", -4, 0)
                        item.side:HookScript("OnEnter", function(b) item.hi:SetColorTexture(unpack(S.C.accentD)) if menu.side.tip then S.Tip(b, menu.side.tip) end end)
                        item.side:HookScript("OnLeave", function() item.hi:SetColorTexture(1, 1, 1, 0) end)
                        button = item.side
                    end
                    if button then
                        button:SetShown(has)
                        if has then S.ArtTexture(button.icon, extra.icon) end
                    end
                else
                    item:Hide()
                end
            end
        end
    end
    local list = type(options) == "function" and options() or options
    local shown = math.min(#list, 14)
    menu.options, menu.offset, menu.onPick, menu.side, menu.anchor = list, 0, onPick, side, anchor
    for i = #menu.items + 1, shown do
        local item = CreateFrame("Button", nil, menu)
        item:SetHeight(22)
        item:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 22)
        item:SetPoint("RIGHT", -1, 0)
        local hi = S.Fill(item, { 1, 1, 1, 0 })
        item.hi = hi
        item.label = S.Text(item, 13)
        item.label:SetPoint("LEFT", 10, 0)
        item.label:SetPoint("RIGHT", -8, 0)
        item:SetScript("OnEnter", function() hi:SetColorTexture(unpack(S.C.accentD)) end)
        item:SetScript("OnLeave", function() hi:SetColorTexture(1, 1, 1, 0) end)
        item:SetScript("OnClick", function(self) CloseMenu() menu.onPick(self.value) S.Changed() end)
        menu.items[i] = item
    end
    -- rows past this menu's length stay in the pool, hidden, for the next long menu
    for i = shown + 1, #menu.items do menu.items[i]:Hide() end
    menu.count = shown
    menu:SetSize(width or (anchor and anchor:GetWidth()) or 220, shown * 22 + 2)
    menu:ClearAllPoints()
    if anchor then
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    else
        -- no button it belongs to (a key, a slash command): where the pointer is. (It was hung under
        -- the whole screen, so it opened below the bottom edge with the click catcher up: nothing to
        -- see, and the next click swallowed.)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end
    menu:Fill()
    catcher:Show()
    menu:Show()
end

function S.Dropdown(parent, width, options, onPick, side)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 24)
    S.Fill(b, S.C.field)
    local border = S.Border(b)
    b.label = S.Text(b, 13)
    b.label:SetPoint("LEFT", 8, 0)
    b.label:SetPoint("RIGHT", -20, 0)
    local arrow = b:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -7, 0)
    S.ArtTexture(arrow, "down")
    arrow:SetVertexColor(unpack(S.C.muted))
    b:SetScript("OnEnter", function() border:Color(S.C.lineHi) end)
    b:SetScript("OnLeave", function() border:Color(S.C.line) end)
    b:SetScript("OnClick", function(self)
        S.OpenMenu(self, options, function(v) onPick(v) end, math.max(width, 160), side)
    end)
    function b:SetValue(label) self.shown = label self.label:SetText(label or "") end
    b.options, b.onPick = options, onPick
    return b
end

-- A small pill that can be on or off (class filters and the like).
function S.Chip(parent, label, onClick, iconTex, coords)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    b.bg = S.Fill(b, { 1, 1, 1, 0.05 })
    b.border = S.Border(b)
    local x = 8
    if iconTex then
        local i = b:CreateTexture(nil, "ARTWORK")
        i:SetSize(14, 14)
        i:SetPoint("LEFT", 5, 0)
        i:SetTexture(iconTex)
        if coords then i:SetTexCoord(unpack(coords)) end
        x = 23
    end
    b.text = S.Text(b, 12, S.C.sub)
    b.text:SetPoint("LEFT", x, 0)
    b.text:SetText(label)
    b:SetWidth(x + b.text:GetStringWidth() + 8)
    function b:SetOn(on, color)
        self.on = on
        self.bg:SetColorTexture(unpack(on and (color or S.C.accentD) or { 1, 1, 1, 0.05 }))
        self.border:Color(on and S.C.accent or S.C.line)
        self.text:SetTextColor(unpack(on and S.C.text or S.C.sub))
    end
    b:SetScript("OnClick", onClick)
    b:SetOn(false)
    return b
end

-- A number with - and + either side and the value typed in the middle.
function S.Stepper(parent, get, set, min, max, step, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 110, 24)
    f.getValue, f.setValue = get, set
    local input
    local function Apply(v)
        v = tonumber(v)
        if v then set(math.max(min, math.min(max, v))) S.Changed() end
        input:SetValue(get())
    end
    -- Shift-click moves ten steps at a time
    local function Step() return (step or 1) * (IsShiftKeyDown and IsShiftKeyDown() and 10 or 1) end
    local minus = S.IconButton(f, "down", function() Apply(get() - Step()) end, nil, S.C.text, 24)
    minus:SetPoint("LEFT")
    local plus = S.IconButton(f, "up", function() Apply(get() + Step()) end, nil, S.C.text, 24)
    plus:SetPoint("RIGHT")
    input = S.Input(f, { width = (width or 110) - 52, onCommit = Apply })
    input:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    input:SetJustifyH("CENTER")
    function f:Refresh() input:SetValue(get()) end
    f:Refresh()
    return f
end

-- A titled card: a slightly lighter panel with a heading and a grey line of explanation.
function S.Card(parent, title, note)
    local c = CreateFrame("Frame", nil, parent)
    S.Fill(c, S.C.card)
    S.Border(c)
    c.title = S.Text(c, 15)
    c.title:SetPoint("TOPLEFT", 14, -12)
    c.title:SetText(title)
    if note then
        c.note = S.Text(c, 12, S.C.muted)
        c.note:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
        c.note:SetText(note)
    end
    return c
end

-- A vertical scroll area for content taller than its box: put things on area.content.
-- A scrolling area: the mouse wheel, and a bar down the right you can grab and drag, or click above or
-- below the handle to move a page. (It used to be a 3-pixel line you could only look at.)
function S.ScrollArea(parent, width, height)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetSize(width, height)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(width - 14, 10)
    sf:SetScrollChild(content)
    sf.content = content

    local track = CreateFrame("Button", nil, sf)
    track:SetPoint("TOPRIGHT")
    track:SetPoint("BOTTOMRIGHT")
    track:SetWidth(10)
    local groove = track:CreateTexture(nil, "BACKGROUND")
    groove:SetPoint("TOP") groove:SetPoint("BOTTOM")
    groove:SetWidth(4)
    groove:SetColorTexture(1, 1, 1, 0.05)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(10)
    thumb.tex = thumb:CreateTexture(nil, "OVERLAY")
    thumb.tex:SetPoint("TOP") thumb.tex:SetPoint("BOTTOM")
    thumb.tex:SetWidth(6)
    thumb.tex:SetColorTexture(1, 1, 1, 0.22)
    thumb:SetScript("OnEnter", function(self) self.tex:SetColorTexture(1, 1, 1, 0.4) end)
    thumb:SetScript("OnLeave", function(self) if not self.dragging then self.tex:SetColorTexture(1, 1, 1, 0.22) end end)
    sf.bar, sf.thumb = track, thumb

    local function Range() return sf:GetVerticalScrollRange() or 0 end
    local function ThumbH(range) return math.max(28, height * height / (height + range)) end
    local function Scroll(to)
        local range = Range()
        sf:SetVerticalScroll(math.max(0, math.min(range, to)))
        sf:UpdateBar()
    end
    function sf:UpdateBar()
        local range = Range()
        if range and range > 1 then
            track:Show()
            local h = ThumbH(range)
            thumb:SetHeight(h)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -(height - h) * self:GetVerticalScroll() / range)
        else
            track:Hide()
        end
    end
    -- Dragging: where the handle was grabbed stays under the cursor.
    local function CursorY()
        local _, y = GetCursorPosition()
        return y / (track:GetEffectiveScale() or 1)
    end
    thumb:RegisterForDrag("LeftButton")
    thumb:SetScript("OnDragStart", function(self)
        self.dragging = true
        self.fromY, self.fromScroll = CursorY(), sf:GetVerticalScroll()
        self:SetScript("OnUpdate", function()
            local range = Range()
            local room = height - ThumbH(range)
            if room > 0 then Scroll(self.fromScroll + (self.fromY - CursorY()) * range / room) end
        end)
    end)
    thumb:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:SetScript("OnUpdate", nil)
        if not self:IsMouseOver() then self.tex:SetColorTexture(1, 1, 1, 0.22) end
    end)
    -- A click in the groove: a page towards where you clicked.
    track:SetScript("OnClick", function()
        local top = thumb:GetTop() or 0
        Scroll(sf:GetVerticalScroll() + (CursorY() > top and -1 or 1) * (height - 24))
    end)

    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, d) Scroll(self:GetVerticalScroll() - d * 36) end)
    sf:SetScript("OnScrollRangeChanged", function(self) self:UpdateBar() end)
    -- scrolled by anything but the wheel or the bar (a link that jumps to a section, the search):
    -- the handle follows there too
    sf:SetScript("OnVerticalScroll", function(self) self:UpdateBar() end)
    return sf
end

-- The window: header with title and subtitle, close button, draggable, closes on Escape.
function S.Window(name, w, h, title)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    S.Fill(f, S.C.window)
    S.Border(f, S.C.lineHi)
    S.Shadow(f, 24, 6, 0.7)
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT") head:SetPoint("TOPRIGHT") head:SetHeight(48)
    local rule = head:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT") rule:SetPoint("BOTTOMRIGHT") S.Hair(rule, "h")
    Set(rule, S.C.line)
    local mark = head:CreateTexture(nil, "ARTWORK")
    mark:SetSize(4, 20)
    mark:SetPoint("LEFT", 18, 0)
    Set(mark, S.C.accent)
    f.title = S.Text(head, 17)
    f.title:SetPoint("LEFT", mark, "RIGHT", 10, 0)
    f.title:SetText(title)
    f.subtitle = S.Text(head, 13, S.C.muted)
    f.subtitle:SetPoint("LEFT", f.title, "RIGHT", 12, -1)
    local close = S.IconButton(head, "close", function() f:Hide() end, "Close (Esc)", S.C.sub, 30)
    close:SetPoint("RIGHT", -10, 0)
    f.close = close
    f:EnableMouse(true)
    f:SetMovable(true)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() f:StartMoving() end)
    head:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    tinsert(UISpecialFrames, name)
    f:SetScript("OnHide", CloseMenu)
    -- a window opened comes up over the others of ours (a loot log opened from the settings came up
    -- under them - the owner, 2026-10-14)
    f:SetScript("OnShow", f.Raise)
    f:Hide()
    return f
end

-- Pixel-exact controls (art/px_*.tga, tools/make_controls.py: the layout of each strip is the same there). A small
-- round shape scaled down from a larger texture falls between screen pixels and reads soft - at 2560 x 1440 and a
-- UI scale of 0.64 a point is 1.2 pixels, the switch 48 x 24 pixels drawn from 128 x 64, its knob 19.2 (the owner,
-- 2026-10-21: "feels so low resolution ... is it my video settings?"). So each is drawn again at every size in
-- pixels it is likely to be, and shown one texel to one pixel at a size in points that is whole pixels.
local PX_GAP = 2
local PX = {    -- { file, canvas width, canvas height, smallest, largest, width per pixel of height }
    pill = { "px_pill", 128, 1024, 16, 40, 2 },
    knob = { "px_knob", 64, 1024, 10, 36, 1 },
    boxLine = { "px_box_line", 64, 1024, 14, 36, 1 },
    boxFill = { "px_box_fill", 64, 1024, 14, 36, 1 },
    tick = { "px_tick", 64, 1024, 14, 36, 1 },
}
--- How many screen pixels one point of a region is (nil where the game can't say).
function S.PixelsPerPoint(region)
    local px = _G.PixelUtil
    local f = type(px) == "table" and px.GetPixelToUIUnitFactor and px.GetPixelToUIUnitFactor()
    local s = region and region.GetEffectiveScale and region:GetEffectiveScale()
    if type(f) ~= "number" or f <= 0 or type(s) ~= "number" or s <= 0 then return nil end
    return s / f
end
--- A texture set to one size, in pixels, of a pixel-exact strip. False where the strip has no such size.
local function PixelExact(tex, kind, size)
    local a = PX[kind]
    if not (a and size and size >= a[4] and size <= a[5]) then return false end
    local y = 0
    for k = a[4], size - 1 do y = y + k + PX_GAP end
    tex:SetTexture(S.ART .. a[1])
    tex:SetTexCoord(0, size * a[6] / a[2], y / a[3], (y + size) / a[3])
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(true) end         -- (one texel on one pixel)
    return true
end

-- A switch: a feature on or off - only a feature has one (its options have checkboxes). A pill of 40 x 20 and a round
-- knob 2 in from its ends, each drawn pixel-exact (above), or where the strips have no such size from the large
-- textures, smooth (art/pill, art/knob: tools/make_controls.py);
-- the knob slides across as it is clicked, and the track takes the accent, toned a little. Off: a dark track and a
-- grey knob, a little lighter under the mouse. (The owner, 2026-10-21, after three that were not good enough: "A,
-- refined".)
local SLIDE = 0.12
local function Mix(a, b, p, out)
    for i = 1, 4 do out[i] = (a[i] or 1) + ((b[i] or 1) - (a[i] or 1)) * p end
    return out
end
function S.Switch(parent, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(40, 20)
    b:SetHitRectInsets(-4, -4, -4, -4)             -- (a little more to hit than to see)
    local track = b:CreateTexture(nil, "ARTWORK")
    track:SetAllPoints()
    local knob = b:CreateTexture(nil, "OVERLAY")
    local p, target, sliding, over = 0, 0, false, false
    local col = {}
    local ppu, width, inset, kn = false, 40, 2, 16     -- (as last laid out: pixels to a point; its sizes, in points)
    -- Its size in whole pixels (20 points, rounded), the knob 2 points in, rounded too, each drawn from its own size
    -- of the pixel-exact strips; no strip that size (a very large UI): the large textures, drawn smooth.
    local function Lay()
        local now = S.PixelsPerPoint(b)
        if now == ppu then return end
        ppu = now
        local hpx = now and math.floor(20 * now + 0.5)
        local ipx = now and math.max(2, math.floor(2 * now + 0.5))
        if hpx and PixelExact(track, "pill", hpx) and PixelExact(knob, "knob", hpx - 2 * ipx) then
            width, inset, kn = 2 * hpx / now, ipx / now, (hpx - 2 * ipx) / now
            b:SetSize(width, hpx / now)
        else
            width, inset, kn = 40, 2, 16
            b:SetSize(40, 20)
            track:SetTexture(S.ART .. "pill")
            track:SetTexCoord(0, 1, 0, 1)
            S.Smooth(track)
            knob:SetTexture(S.ART .. "knob")
            knob:SetTexCoord(0, 1, 0, 1)
            S.Smooth(knob)
        end
        knob:SetSize(kn, kn)
    end
    local function Paint()
        track:SetVertexColor(unpack(Mix(over and S.C.swOffHi or S.C.swOff, S.C.swOn, p, col)))
        knob:SetVertexColor(unpack(Mix(over and S.C.knobOffHi or S.C.knobOff, S.C.swKnob, p, col)))
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", b, "LEFT", inset + (width - 2 * inset - kn) * p, 0)
    end
    local function Slide(self, elapsed)
        local step = (tonumber(elapsed) or SLIDE) / SLIDE
        if target > p then p = math.min(target, p + step) else p = math.max(target, p - step) end
        Paint()
        if p == target then
            sliding = false
            self:SetScript("OnUpdate", nil)         -- (still again: nothing runs while it rests)
        end
    end
    function b:Refresh()
        Lay()
        target = get() and 1 or 0
        if sliding then return end                  -- (on its way there)
        p = target
        Paint()
    end
    b:SetScript("OnShow", function() Lay() Paint() end)     -- (the UI scale may have changed while it was away)
    b:SetScript("OnClick", function(self)
        set(not get())
        target = get() and 1 or 0
        sliding = true
        self:SetScript("OnUpdate", Slide)
        S.Changed()
    end)
    b:SetScript("OnEnter", function() over = true Paint() end)
    b:SetScript("OnLeave", function() over = false Paint() end)
    b:Refresh()
    b.getValue, b.setValue = get, set          -- (what a settings row reads a default from, and resets with)
    return b
end

-- A checkbox: an option of a feature. 18 x 18, pixel-exact (above): not ticked an edge only (lighter under the mouse), ticked light with a
-- dark tick - no accent, so a page of options stays quiet (art/box_line, box_fill, tick). Its whole row ticks it too
-- (Editor.lua). The same calls as a switch.
function S.Check(parent, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    local line = b:CreateTexture(nil, "ARTWORK")
    line:SetAllPoints()
    local fill = b:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetAllPoints()
    local tick = b:CreateTexture(nil, "OVERLAY")
    tick:SetAllPoints()
    local over = false
    local ppu = false
    -- 18 points in whole pixels, from the pixel-exact strips (as the switch: S.Switch); else the large textures, smooth
    local function Lay()
        local now = S.PixelsPerPoint(b)
        if now == ppu then return end
        ppu = now
        local px = now and math.floor(18 * now + 0.5)
        if px and PixelExact(line, "boxLine", px) and PixelExact(fill, "boxFill", px) and PixelExact(tick, "tick", px) then
            b:SetSize(px / now, px / now)
        else
            b:SetSize(18, 18)
            for tex, name in pairs({ [line] = "box_line", [fill] = "box_fill", [tick] = "tick" }) do
                tex:SetTexture(S.ART .. name)
                tex:SetTexCoord(0, 1, 0, 1)
                S.Smooth(tex)
            end
        end
    end
    function b:Refresh()
        Lay()
        local on = get() and true or false
        fill:SetShown(on)
        tick:SetShown(on)
        line:SetShown(not on)
        fill:SetVertexColor(unpack(S.C.boxOn))
        tick:SetVertexColor(unpack(S.C.tickInk))
        line:SetVertexColor(unpack(over and S.C.boxLineHi or S.C.boxLine))
    end
    function b:Hover(on) over = on and true or false self:Refresh() end
    b.isCheck = true
    b:SetScript("OnShow", function(self) self:Refresh() end)          -- (the UI scale may have changed while it was away)
    b:SetScript("OnClick", function(self) set(not get()) self:Refresh() S.Changed() end)
    b:SetScript("OnEnter", function(self) self:Hover(true) end)
    b:SetScript("OnLeave", function(self) self:Hover(false) end)
    b:Refresh()
    b.getValue, b.setValue = get, set
    return b
end

-- A slider with - and + either side of its value box: drag for big moves, - and + for exact ones
-- (Shift-click moves ten steps), or type the number. Values are rounded to the step.
-- compact: a track and the value's box, no - and + (the mouse wheel over it moves a step, Shift ten;
-- or type the number) - narrow enough to share a settings row with another setting.
function S.Slider(parent, min, max, step, get, set, width, compact)
    step = step or 1
    width = width or 220
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, 24)
    f.getValue, f.setValue = get, set
    local function Round(v) return math.floor(v / step + 0.5) * step end
    local function Clamp(v) return math.max(min, math.min(max, Round(v))) end

    local s = CreateFrame("Slider", nil, f)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("LEFT")
    s:SetSize(compact and (width - 56) or (width - 104), 16)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT") track:SetPoint("RIGHT") track:SetHeight(4)
    Set(track, { 1, 1, 1, 0.14 })
    local fill = s:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT") fill:SetHeight(4)
    Set(fill, S.C.accent)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 16)
    thumb:SetColorTexture(1, 1, 1, 1)
    s:SetThumbTexture(thumb)

    local function Nudge(dir)
        local n = IsShiftKeyDown() and 10 or 1
        set(Clamp(get() + dir * n * step))
        S.Changed()
        f:Refresh()
    end
    local box = S.Input(f, { width = compact and 46 or 52, numeric = true, onCommit = function(t)
        local v = tonumber(t)
        if v then set(Clamp(v)) S.Changed() end
        f:Refresh()
    end })
    box:SetJustifyH("CENTER")
    if compact then
        box:SetPoint("RIGHT")
        s:EnableMouseWheel(true)
        s:SetScript("OnMouseWheel", function(_, d) Nudge(d > 0 and 1 or -1) end)
    else
        local plus = S.IconButton(f, "plus", function() Nudge(1) end, "+" .. step .. "  (Shift: +" .. step * 10 .. ")", S.C.sub, 22)
        plus:SetPoint("RIGHT")
        box:SetPoint("RIGHT", plus, "LEFT", -2, 0)
        local minus = S.IconButton(f, "minus", function() Nudge(-1) end, "-" .. step .. "  (Shift: -" .. step * 10 .. ")", S.C.sub, 22)
        minus:SetPoint("RIGHT", box, "LEFT", -2, 0)
    end

    local busy = false
    local function Show(v)
        box:SetValue(v)
        fill:SetWidth(math.max(1, (v - min) / (max - min) * s:GetWidth()))
    end
    s:SetScript("OnValueChanged", function(_, v)
        if busy then return end
        v = Clamp(v)
        set(v)
        S.Changed()
        Show(v)
    end)
    function f:Refresh()
        busy = true
        local v = Clamp(get())
        s:SetValue(v)
        Show(v)
        busy = false
    end
    f:Refresh()
    return f
end

-- Text that can be longer than a line: it wraps and shows all of itself. Enter or leaving it commits.
function S.TextArea(parent, width, height, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width, height)
    S.Fill(f, S.C.field)
    local border = S.Border(f)
    local box = CreateFrame("EditBox", nil, f)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFont(S.FONT, 13, "")
    box:SetTextColor(unpack(S.C.text))
    box:SetPoint("TOPLEFT", 7, -5)
    box:SetPoint("BOTTOMRIGHT", -7, 5)
    box:SetWidth(width - 14)
    local hint = S.Text(f, 12, S.C.muted)
    hint:SetPoint("TOPLEFT", 8, -6)
    hint:SetText(opts.placeholder or "")
    local function Hint() hint:SetShown(box:GetText() == "" and not box:HasFocus()) end
    box:SetScript("OnEditFocusGained", function() border:Color(S.C.accent) Hint() end)
    box:SetScript("OnEditFocusLost", function()
        border:Color(S.C.line) Hint()
        if opts.onCommit then opts.onCommit((box:GetText():gsub("\n", " "))) S.Changed() end
    end)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnTextChanged", Hint)
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function() box:SetFocus() end)
    f.box = box
    function f:SetValue(v) box:SetText(v == nil and "" or tostring(v)) box:SetCursorPosition(0) Hint() end
    function f:HasFocus() return box:HasFocus() end
    Hint()
    return f
end
