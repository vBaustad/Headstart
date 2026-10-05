-- RestedXP skins: two looks for RestedXP's guide window, picked in Headstart, QoL, RestedXP skin (or
-- in RestedXP's own theme list, where they show up as "Headstart" and "Blizzard").
--   Headstart: the flat dark look of Headstart's own window - a thin line for a border, one accent
--   colour on the header, the footer, the step you're on and the map pins. The accent and the
--   background are yours to pick (or the accent follows your class colour).
--   Blizzard: the game's own look - the dark frame fill, the game's border, gold titles.
--   How: both are themes handed to RestedXP through its own RegisterTheme, so the colours, the fonts
--   and RestedXP's new guide window (v2) follow by its own rules. A theme can't change the header
--   banner, the frame round the window or the scroll bar, so after RestedXP has drawn its (v1)
--   window we go over it: RestedXP's own fills and edges on the header, the list and the footer made
--   clear and one shell of ours put behind and round all three (Blizzard: Forever's bronze frame and
--   fill in Blizzard's settings-window frame, and Blizzard's inner panel round each step box; Headstart: flat fill, a thin line, the accent
--   as a line under the header); the scroll bar a slim thumb on a thin track with the end buttons out
--   of sight; the border's size on the steps set while one of ours is on (and put back when it isn't).
--   Only RestedXP's window is touched, and only while our theme is on.
--   The small art RestedXP needs from a theme's folder (logo, cog, arrow, tick boxes, scroll bar) is
--   RestedXP's own neutral "DarkMode" set.
--   Account options (YippRouteDB): rxpSkinAccent { r, g, b }, rxpSkinBack { r, g, b, a },
--   rxpSkinClass (the accent is your class colour), rxpSkinPrev (RestedXP's theme before ours).
local ADDON, YR = ...

local HEADSTART, BLIZZARD = "Headstart", "Blizzard"
local RXP_ART = "Interface/AddOns/RXPGuides/Textures/DarkMode/"
local WHITE = "Interface/BUTTONS/WHITE8X8"
local LINE = "Interface/AddOns/Headstart/art/line"
local GOLD = { 1, 0.82, 0 }

local DEFAULT_ACCENT = { 0.40, 0.66, 1.00 }
local DEFAULT_BACK = { 0.075, 0.08, 0.095, 0.95 }

local function Rxp()
    local rxp = _G.RXP
    return type(rxp) == "table" and type(rxp.RegisterTheme) == "function" and rxp or nil
end

--- The accent: your class colour while that's on, else the one you picked.
function YR.RXPSkinAccent()
    if YippRouteDB.rxpSkinClass == true then
        local _, class = UnitClass("player")
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then return { c.r, c.g, c.b } end
    end
    local a = YippRouteDB.rxpSkinAccent
    return type(a) == "table" and { a[1], a[2], a[3] } or { DEFAULT_ACCENT[1], DEFAULT_ACCENT[2], DEFAULT_ACCENT[3] }
end

function YR.RXPSkinBack()
    local b = YippRouteDB.rxpSkinBack
    b = type(b) == "table" and b or DEFAULT_BACK
    return { b[1], b[2], b[3], b[4] or 1 }
end

local function Hex(c)
    return ("|cFF%02X%02X%02X"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

local function Lighter(c, by)
    return { math.min(1, c[1] + by), math.min(1, c[2] + by), math.min(1, c[3] + by), c[4] or 1 }
end

--- The two themes as RestedXP wants them (its v1 shape; it makes the v2 one from it).
function YR.RXPSkinThemes()
    local accent, back = YR.RXPSkinAccent(), YR.RXPSkinBack()
    local font = GameFontNormal and GameFontNormal:GetFont() or "Fonts\\FRIZQT__.TTF"
    local headstart = {
        name = HEADSTART, displayName = HEADSTART, author = "YippYapp", applicable = true,
        background = back,
        bottomFrameBG = Lighter(back, 0.03),
        bottomFrameHighlight = { accent[1], accent[2], accent[3], 0.28 },
        mapPins = { accent[1], accent[2], accent[3], 1 },
        tooltip = Hex(accent),
        texturePath = RXP_ART, headerTexture = "rxp-banner",
        font = YR.Style and YR.Style.FONT or font,
        textColor = { 0.93, 0.94, 0.96 },
        bgTextures = { edge = WHITE, bottom = WHITE },
        edges = { edge = LINE, guideName = LINE },
    }
    local blizzard = {
        name = BLIZZARD, displayName = BLIZZARD, author = "YippYapp", applicable = true,
        background = { 0.05, 0.045, 0.04, 0.92 },
        bottomFrameBG = { 0, 0, 0, 0.28 },
        bottomFrameHighlight = { 1.0, 0.82, 0.0, 0.16 },
        mapPins = { GOLD[1], GOLD[2], GOLD[3], 1 },
        tooltip = Hex(GOLD),
        texturePath = RXP_ART, headerTexture = "rxp-banner",
        font = font,
        textColor = { 1, 1, 1 },
        bgTextures = { edge = WHITE, bottom = WHITE },
        edges = { edge = "Interface/Tooltips/UI-Tooltip-Border", guideName = "Interface/Tooltips/UI-Tooltip-Border" },
    }
    return headstart, blizzard
end

--- Which of ours is on: "headstart", "blizzard", or "off" (RestedXP's own, or RestedXP isn't there).
function YR.RXPSkinMode()
    local rxp = Rxp()
    local profile = rxp and rxp.settings and rxp.settings.profile
    local name = profile and profile.activeTheme
    if not YR.QoLOn() then return "off" end            -- our themes stay in RestedXP's list, undecorated by us
    return name == HEADSTART and "headstart" or name == BLIZZARD and "blizzard" or "off"
end

-- ---------------------------------------------------------------------------
-- Over RestedXP's own drawing (its v1 window)
-- ---------------------------------------------------------------------------
local original          -- the border sizes RestedXP had, to put back

local BORDER = {
    headstart = { edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } },
    blizzard = { edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } },
}

-- Before RestedXP draws: the border's size for our look, or RestedXP's own back
local function Borders()
    local rxp = Rxp()
    local backdrop = rxp and rxp.RXPFrame and rxp.RXPFrame.backdrop
    if type(backdrop) ~= "table" then return end
    local mode = YR.RXPSkinMode()
    for _, key in ipairs({ "edge", "guideName" }) do
        local b = backdrop[key]
        if type(b) == "table" then
            original = original or {}
            original[key] = original[key] or { edgeSize = b.edgeSize, insets = b.insets }
            local want = BORDER[mode] or original[key]
            b.edgeSize, b.insets = want.edgeSize, want.insets
        end
    end
end

-- Blizzard's own art by its atlas name, where this client has it (Forever swaps its bronze in behind
-- the names): nil when it doesn't, so the caller can fall back to a plain colour.
local atlasKnown = {}        -- the client's art doesn't change in a session: asked once per name
local function HasAtlas(name)
    local known = atlasKnown[name]
    if known == nil then
        known = false
        if C_Texture and C_Texture.GetAtlasInfo then
            local ok, info = pcall(C_Texture.GetAtlasInfo, name)
            known = ok and info ~= nil
        end
        atlasKnown[name] = known
    end
    return known
end
function YR.RXPSkinForgetArt() atlasKnown = {} end        -- for the tests, whose client changes
local function FirstAtlas(...)
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        if HasAtlas(name) then return name end
    end
end

-- What we add to RestedXP's window (made once, shown only while one of our looks is on): a shell
-- behind and round the header, the list and the footer; a line under the header and over the
-- footer; a track for the scroll bar. The shell stands OUTSIDE RestedXP's parts by the look's
-- margin, so its frame never lies over the title or the footer's text.
local extra
local MARGIN = { blizzard = 10, headstart = 5 }
local PANEL_COLOUR = { 0.64, 0.52, 0.30 }      -- the bronze of Blizzard's thin panel lines
local GAP = 8               -- between the boxes of the steps you're on and our frame (RestedXP's boxes hang a few pixels low)
local CLASS = 44            -- your class icon in the header, in both looks (RestedXP's is 24, on a 42 logo)
local STRIP = 20            -- the header's height inside Blizzard's window: its title strip (RestedXP's is 35)

-- Blizzard's own window, as Skillwright and Guildhall wear it: the settings window's frame (its
-- title strip across the top, the thin metal sides) with nothing of its own inside. The frame's
-- inside starts 7 in from the left, 18 down, 3 in from the right and 3 up - Skillwright's measure
-- of the same template - so the window stands out from RestedXP's parts by that much.
local WINDOW = { left = 7, top = 18, right = 3, bottom = 3 }
local function MetalFrame(parent)
    local made, f = pcall(CreateFrame, "Frame", nil, parent, "SettingsFrameTemplate")
    if not made or type(f) ~= "table" then return nil end
    if f.EnableMouse then f:EnableMouse(false) end
    for _, key in ipairs({ "ClosePanelButton", "CloseButton", "Bg" }) do
        if type(f[key]) == "table" and f[key].Hide then f[key]:Hide() end
    end
    if type(f.NineSlice) == "table" and type(f.NineSlice.Text) == "table" and f.NineSlice.Text.SetText then
        f.NineSlice.Text:SetText("")        -- RestedXP's own guide name goes in the strip
    end
    return f
end

local function Extras(frame)
    if extra then return extra end
    local head, list, foot = frame.GuideName, frame.BottomFrame, frame.Footer
    if not (type(head) == "table" and type(list) == "table" and type(foot) == "table") then return nil end
    extra = { head = head, foot = foot }
    -- the fill, behind everything of RestedXP's
    local back = CreateFrame("Frame", nil, frame)
    back:SetFrameLevel(math.max(0, (list.GetFrameLevel and list:GetFrameLevel() or 1) - 1))
    extra.back = back
    extra.fill = back:CreateTexture(nil, "BACKGROUND")
    extra.fill:SetAllPoints()
    -- Headstart's fill: the rounded card of its own window
    if YR.Style and YR.Style.Rounded then extra.card = YR.Style.Rounded(back, "BACKGROUND", "round", 1) end
    -- the frame round it (it takes no clicks)
    local rim = CreateFrame("Frame", nil, frame)
    rim:SetFrameLevel((head.GetFrameLevel and head:GetFrameLevel() or 6) + 3)
    extra.rim = rim
    extra.border = rim:CreateTexture(nil, "BORDER")
    extra.border:SetAllPoints()
    if YR.Style and YR.Style.Rounded then extra.outline = YR.Style.Rounded(rim, "BORDER", "roundline", 1) end
    extra.metal = MetalFrame(back)
    if extra.metal then extra.metal:Hide() end

    -- when the client has neither: four plain lines
    extra.lines = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = rim:CreateTexture(nil, "ARTWORK")
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT") t:SetPoint(side .. "RIGHT") t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side) t:SetPoint("BOTTOM" .. side) t:SetWidth(1)
        end
        t:Hide()
        extra.lines[#extra.lines + 1] = t
    end
    -- under the header, over the footer
    extra.headLine = rim:CreateTexture(nil, "ARTWORK")
    extra.headLine:SetPoint("BOTTOMLEFT", head, "BOTTOMLEFT", 2, 4)
    extra.headLine:SetPoint("BOTTOMRIGHT", head, "BOTTOMRIGHT", -2, 4)
    extra.footLine = rim:CreateTexture(nil, "ARTWORK")
    extra.footLine:SetPoint("TOPLEFT", foot, "TOPLEFT", 2, -1)
    extra.footLine:SetPoint("TOPRIGHT", foot, "TOPRIGHT", -2, -1)
    -- the scroll bar's track
    local bar = type(frame.ScrollFrame) == "table" and frame.ScrollFrame.ScrollBar
    if type(bar) == "table" and bar.CreateTexture then
        extra.track = bar:CreateTexture(nil, "BACKGROUND")
        extra.track:SetPoint("TOP", 0, 14)
        extra.track:SetPoint("BOTTOM", 0, -14)
        extra.track:SetWidth(4)
    end
    return extra
end

function YR.RXPSkinParts() return extra end       -- for the tests

local function ShowExtras(on)
    if not extra then return end
    extra.back:SetShown(on)
    extra.rim:SetShown(on)
    if extra.track then extra.track:SetShown(on) end
end

-- The shell round RestedXP's three parts, standing out from them by the look's margin
local function Margin(mode)
    if mode == "blizzard" and extra and extra.metal then return 1 end
    return MARGIN[mode] or 0
end

local function Shell(mode)
    local m = Margin(mode)
    for _, f in ipairs({ extra.back, extra.rim }) do
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", extra.head, "TOPLEFT", -m, m)
        f:SetPoint("BOTTOMRIGHT", extra.foot, "BOTTOMRIGHT", m, -m)
    end
    if extra.metal and mode == "blizzard" then
        -- the window round the three parts: the header is its title strip, the fill starts under it
        extra.metal:ClearAllPoints()
        extra.metal:SetPoint("TOPLEFT", extra.head, "TOPLEFT", -WINDOW.left, 1)
        extra.metal:SetPoint("BOTTOMRIGHT", extra.foot, "BOTTOMRIGHT", WINDOW.right, -WINDOW.bottom)
        extra.back:ClearAllPoints()
        extra.back:SetPoint("TOPLEFT", extra.head, "TOPLEFT", 0, 1 - WINDOW.top)
        extra.back:SetPoint("BOTTOMRIGHT", extra.foot, "BOTTOMRIGHT", 0, 0)
    end
end

-- The boxes of the steps you're on, clear of our frame. RestedXP puts them back in its own place
-- (two pixels over its header, or under its window if you've set them there) whenever it likes -
-- after a reload, when the window is moved, when a setting changes - so we also go after each of
-- its own placements (the hook below) and put them clear again.
local placingSteps
local function PlaceSteps(frame, mode)
    local steps, head = frame.CurrentStepFrame, frame.GuideName
    if placingSteps or type(steps) ~= "table" or not steps.ClearAllPoints or type(head) ~= "table" then return end
    local on = mode ~= "off"
    local out = on and (Margin(mode) + GAP) or 0
    placingSteps = true
    steps:ClearAllPoints()
    if rawget(steps, "anchor") == "BOTTOM" then
        steps:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 3, -out)
        steps:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -3, -out)
    else
        steps:SetPoint("BOTTOMLEFT", head, "TOPLEFT", 0, 2 + out)
        steps:SetPoint("BOTTOMRIGHT", head, "TOPRIGHT", 0, 2 + out)
    end
    placingSteps = false
    if not rawget(steps, "headstartHooked") and steps.SetPoint then
        steps.headstartHooked = true
        hooksecurefunc(steps, "SetPoint", function()
            if placingSteps then return end
            local now = YR.RXPSkinMode()
            local rxp = Rxp()
            local v2 = rxp and rxp.v2 and rxp.v2.IsGuideWindowEnabled and rxp.v2:IsGuideWindowEnabled()
            if now ~= "off" and not v2 then PlaceSteps(frame, now) end
        end)
    end
end

-- RestedXP's own places for the things we move, to put back: its logo is bigger than its header and
-- hangs out over the corner, which no frame of ours can go round - inside ours it's a small badge.
-- The steps you're on float over the header: they're lifted clear of our frame.
local function Layout(frame, mode)
    local head = frame.GuideName
    if type(head) ~= "table" then return end
    local on = mode ~= "off"
    local m = Margin(mode)
    local icon, class, text = head.icon, head.classIcon, head.text
    -- in Blizzard's frame the header is its title strip: lower, with the guide's name on one line
    local strip = mode == "blizzard" and extra and extra.metal
    if head.SetHeight then head:SetHeight(strip and STRIP or 35) end
    if type(text) == "table" and text.SetMaxLines then text:SetMaxLines(strip and 1 or 0) end
    -- In both looks RestedXP's logo is gone and your class icon stands alone in the header's left
    -- end - and is the menu button (what RestedXP's cog in the footer is; that one is put away).
    if type(icon) == "table" and icon.SetShown then icon:SetShown(not on) end
    if type(class) == "table" and class.SetSize then
        class:SetSize(on and CLASS or 24, on and CLASS or 24)
        class:ClearAllPoints()
        if on then
            class:SetPoint("CENTER", head, "LEFT", 18, 0)
        elseif type(icon) == "table" then
            class:SetPoint("CENTER", icon, "BOTTOMRIGHT", -4, 10)
        end
    end
    -- a rim round it in the look's colour: the accent, or the Blizzard look's bronze
    local rim = rawget(head, "headstartRim")
    if on and not rim and type(class) == "table" and head.CreateTexture and YR.Style and YR.Style.ArtTexture then
        rim = head:CreateTexture(nil, "ARTWORK")
        YR.Style.ArtTexture(rim, "circle")
        rim:SetPoint("CENTER", class, "CENTER")
        head.headstartRim = rim
    end
    if rim then
        rim:SetShown(on)
        if on then
            rim:SetSize(CLASS - 8, CLASS - 8)
            local c = mode == "headstart" and YR.RXPSkinAccent() or PANEL_COLOUR
            rim:SetVertexColor(c[1], c[2], c[3], 1)
        end
    end
    local menu = rawget(head, "headstartMenu")
    if on and not menu and type(class) == "table" then
        menu = CreateFrame("Button", nil, head)
        menu:SetPoint("CENTER", class, "CENTER")
        menu:SetSize(CLASS - 12, CLASS - 12)           -- the art has air round it: the button is the icon itself
        menu:SetFrameLevel((head.GetFrameLevel and head:GetFrameLevel() or 6) + 2)
        menu:SetScript("OnClick", function()
            local rxp = Rxp()
            if rxp and type(rxp.RXPFrame) == "table" and type(rxp.RXPFrame.DropDownMenu) == "function" then
                rxp.RXPFrame.DropDownMenu()
            end
        end)
        menu:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("RestedXP's menu")
            GameTooltip:AddLine("Guides, settings and the rest", 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        menu:SetScript("OnLeave", function() GameTooltip:Hide() end)
        head.headstartMenu = menu
    end
    if menu then menu:SetShown(on) end
    local cog = type(frame.Footer) == "table" and frame.Footer.cog
    if type(cog) == "table" and cog.SetShown then cog:SetShown(not on) end
    local foot = type(frame.Footer) == "table" and frame.Footer.text
    if type(foot) == "table" and foot.ClearAllPoints then
        foot:ClearAllPoints()
        foot:SetPoint("LEFT", frame.Footer, on and 10 or 40, 1)
        foot:SetPoint("RIGHT", frame.Footer, -16, 1)
    end
    if type(text) == "table" and text.ClearAllPoints then
        text:ClearAllPoints()
        text:SetPoint("LEFT", head, on and 40 or 29, on and 1 or 0)
        text:SetPoint("RIGHT", head, on and -6 or 0, on and 1 or 0)
    end
    local scroll, list = frame.ScrollFrame, frame.BottomFrame
    if type(scroll) == "table" and scroll.ClearAllPoints and type(list) == "table" then
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", list, 5, strip and -13 or -5)
        scroll:SetPoint("BOTTOMRIGHT", list, -20, strip and 9 or 7)
    end
    PlaceSteps(frame, mode)
end

-- The scroll bar. RestedXP's is Blizzard's old scroll bar wearing RestedXP's own art.
--   Blizzard look: Blizzard's own new slim scroll bar in its place where the client has that
--   template (SlimBar); else Blizzard's art on RestedXP's bar - the slim thumb and arrows by atlas,
--   or the classic scroll bar every client has.
--   Headstart look: a slim thumb in the accent on a thin track, the end buttons out of sight.
-- RestedXP sets its own art again each time it redraws, so leaving our look needs only the sizes
-- and the buttons put back.
local thumbSize
local CLASSIC = "Interface\\Buttons\\UI-ScrollBar-"

-- Blizzard's new slim scroll bar itself (the one in its Who list and collections), where the client
-- has the template: a real one, standing where RestedXP's is. RestedXP's own bar stays the one that
-- does the scrolling (its guide code sets and limits it); ours shows where that one is and, when
-- you drag or click ours, moves that one. So nothing of RestedXP's scrolling is replaced.
local slimBar           -- the bar, or false when this client can't make one

local function SlimBar(frame)
    if slimBar ~= nil then return slimBar or nil end
    slimBar = false
    local scroll = frame.ScrollFrame
    local old = type(scroll) == "table" and scroll.ScrollBar
    if type(old) ~= "table" or not (old.GetMinMaxValues and old.GetValue and old.HookScript) then return nil end
    if not (BaseScrollBoxEvents and BaseScrollBoxEvents.OnScroll and ScrollBoxConstants) then return nil end
    local made, bar = pcall(CreateFrame, "EventFrame", nil, old:GetParent(), "MinimalScrollBar")
    if not made or type(bar) ~= "table" or not (bar.SetScrollPercentage and bar.SetVisibleExtentPercentage and bar.RegisterCallback) then
        return nil
    end
    bar:SetPoint("TOP", old, "TOP", 0, 14)
    bar:SetPoint("BOTTOM", old, "BOTTOM", 0, -14)
    bar:SetFrameLevel((old.GetFrameLevel and old:GetFrameLevel() or 1) + 5)
    local busy
    local function FromTheirs()
        if busy then return end
        busy = true
        pcall(function()
            local lo, hi = old:GetMinMaxValues()
            local range, height = (hi or 0) - (lo or 0), scroll:GetHeight() or 0
            bar:SetVisibleExtentPercentage(height > 0 and height / (math.max(0, range) + height) or 1)
            if bar.SetPanExtentPercentage then bar:SetPanExtentPercentage(range > 0 and math.min(1, 30 / range) or 0) end
            bar:SetScrollPercentage(range > 0 and ((old:GetValue() or lo) - lo) / range or 0, ScrollBoxConstants.NoScrollInterpolation)
        end)
        busy = false
    end
    bar:RegisterCallback(BaseScrollBoxEvents.OnScroll, function(_, percent)
        if busy then return end
        busy = true
        pcall(function()
            local lo, hi = old:GetMinMaxValues()
            old:SetValue((lo or 0) + (percent or 0) * ((hi or 0) - (lo or 0)))
        end)
        busy = false
    end, bar)
    old:HookScript("OnValueChanged", FromTheirs)
    old:HookScript("OnMinMaxChanged", FromTheirs)
    bar.FromTheirs = FromTheirs
    bar:Hide()
    slimBar = bar
    return bar
end

local function ScrollBar(frame, mode, accent)
    local bar = type(frame.ScrollFrame) == "table" and frame.ScrollFrame.ScrollBar
    if type(bar) ~= "table" then return end
    -- Blizzard look, and the client can make Blizzard's own slim bar: that one, RestedXP's out of sight
    local real = mode == "blizzard" and SlimBar(frame) or nil
    if slimBar then
        slimBar:SetShown(real ~= nil)
        if real then real.FromTheirs() end
    end
    if bar.SetAlpha then bar:SetAlpha(real and 0 or 1) end
    for _, part in ipairs({ bar, bar.ScrollUpButton, bar.ScrollDownButton }) do
        if type(part) == "table" and part.EnableMouse then part:EnableMouse(not real) end
    end
    if real then
        if extra and extra.track then extra.track:Hide() end
        return
    end
    local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
    local slim = mode == "blizzard" and FirstAtlas("minimal-scrollbar-small-thumb-middle", "minimal-scrollbar-thumb-middle")
    local classic = mode == "blizzard" and not slim
    if thumb then
        if not thumbSize and thumb.GetSize then thumbSize = { thumb:GetSize() } end
        local w, h = thumbSize and thumbSize[1] or 18, thumbSize and thumbSize[2] or 24
        if mode == "off" then
            if thumb.SetSize then thumb:SetSize(w, h) end
        elseif slim and thumb.SetAtlas then
            thumb:SetAtlas(slim)
            thumb:SetSize(8, 36)
        elseif classic and thumb.SetTexture then
            thumb:SetTexture(CLASSIC .. "Knob")
            if thumb.SetTexCoord then thumb:SetTexCoord(0.20, 0.80, 0.125, 0.875) end
            thumb:SetSize(w, h)
        elseif thumb.SetColorTexture then
            local c = accent or GOLD
            thumb:SetColorTexture(c[1], c[2], c[3], 0.85)
            thumb:SetSize(4, 36)
        end
    end
    for key, name in pairs({ ScrollUpButton = "ScrollUpButton", ScrollDownButton = "ScrollDownButton" }) do
        local b = bar[key]
        if type(b) == "table" then
            if b.SetAlpha then b:SetAlpha((mode == "off" or mode == "blizzard") and 1 or 0) end
            if mode == "blizzard" then
                local arrow = slim and FirstAtlas(key == "ScrollUpButton" and "minimal-scrollbar-arrow-top" or "minimal-scrollbar-arrow-bottom")
                for state, suffix in pairs({ Normal = "Up", Pushed = "Down", Disabled = "Disabled", Highlight = "Highlight" }) do
                    local t = b[state]
                    if type(t) == "table" then
                        if arrow and t.SetAtlas then t:SetAtlas(arrow)
                        elseif t.SetTexture then
                            t:SetTexture(CLASSIC .. name .. "-" .. suffix)
                            if t.SetTexCoord then t:SetTexCoord(0.20, 0.80, 0.25, 0.75) end
                        end
                    end
                end
            end
        end
    end
    if extra and extra.track then
        extra.track:SetShown(mode ~= "off")
        if mode == "blizzard" then extra.track:SetColorTexture(0, 0, 0, 0.35)
        elseif accent then extra.track:SetColorTexture(1, 1, 1, 0.06) end
    end
end

local function Clear(part)
    if type(part) ~= "table" then return end
    if part.SetBackdropColor then part:SetBackdropColor(0, 0, 0, 0) end
    if part.SetBackdropBorderColor then part:SetBackdropBorderColor(0, 0, 0, 0) end
end

-- The boxes of the steps you're on, over the window. In the Blizzard look each gets Blizzard's inner
-- panel (the thin lines with the corner pieces, the one round Skillwright's pages) in place of its
-- own edge; the small tab with the step's number is too small for that art, so it keeps its plain
-- edge, in the panel's colour. RestedXP sets a box's backdrop again when the theme changes, which
-- brings its own edge back by itself; ours is only ever hidden.

local function StepBoxes()
    local rxp = Rxp()
    local steps = rxp and type(rxp.RXPFrame) == "table" and rxp.RXPFrame.CurrentStepFrame
    local pool = type(steps) == "table" and steps.framePool
    if type(pool) ~= "table" then return end
    local v2 = rxp.v2 and rxp.v2.IsGuideWindowEnabled and rxp.v2:IsGuideWindowEnabled()
    local on = YR.RXPSkinMode() == "blizzard" and not v2
    local panel = on and FirstAtlas("common-insideframe")
    for _, box in pairs(pool) do
        if type(box) == "table" then
            local ours = rawget(box, "headstartPanel")
            if panel and not ours and box.CreateTexture then
                ours = box:CreateTexture(nil, "BORDER")
                ours:SetAllPoints()
                box.headstartPanel = ours
            end
            if ours then
                if panel then ours:SetAtlas(panel) end
                ours:SetShown(panel and true or false)
            end
            local fill = rawget(box, "headstartFill")
            if panel and not fill and box.CreateTexture then
                fill = box:CreateTexture(nil, "BACKGROUND", nil, -1)
                fill:SetPoint("TOPLEFT", 2, -2)
                fill:SetPoint("BOTTOMRIGHT", -2, 2)
                box.headstartFill = fill
            end
            if fill then
                if panel then
                    local art = FirstAtlas("heavybronze-frame-background")
                    if art then fill:SetAtlas(art) else fill:SetColorTexture(0.05, 0.045, 0.04, 1) end
                end
                fill:SetShown(panel and true or false)
            end
            if panel and box.SetBackdropBorderColor then box:SetBackdropBorderColor(0, 0, 0, 0) end
            local tab = box.number
            if on and type(tab) == "table" and tab.SetBackdropBorderColor then
                tab:SetBackdropBorderColor(PANEL_COLOUR[1], PANEL_COLOUR[2], PANEL_COLOUR[3], 1)
            end
        end
    end
end
YR.RXPSkinStepBoxes = StepBoxes

-- After RestedXP has drawn: its own fills, edges and banners on the header, the list and the footer
-- made clear, and ours in their place.
local painted

local function Paint()
    local rxp = Rxp()
    local frame = rxp and rxp.RXPFrame
    if type(frame) ~= "table" then return end
    local mode = YR.RXPSkinMode()
    -- RestedXP's new window (v2) draws itself from the theme: nothing of ours goes over it
    local v2 = rxp.v2 and rxp.v2.IsGuideWindowEnabled and rxp.v2:IsGuideWindowEnabled()
    StepBoxes()
    if mode == "off" or v2 then
        if painted then
            painted = nil
            ShowExtras(false)
            ScrollBar(frame, "off")
            Layout(frame, "off")
        end
        return
    end
    painted = true
    local accent = mode == "headstart" and YR.RXPSkinAccent() or nil
    local e = Extras(frame)
    if not e then return end
    ShowExtras(true)
    Shell(mode)
    Layout(frame, mode)
    Clear(frame.GuideName)
    Clear(frame.Footer)
    Clear(frame.BottomFrame)
    for _, part in ipairs({ frame.GuideName, frame.Footer }) do
        local bg = type(part) == "table" and part.bg
        if bg and bg.SetColorTexture then bg:SetColorTexture(0, 0, 0, 0) end
    end
    local title = type(frame.GuideName) == "table" and frame.GuideName.text
    local foot = type(frame.Footer) == "table" and frame.Footer.text
    for _, t in ipairs(e.lines) do t:Hide() end
    if accent then
        -- Headstart: its own window's rounded card and thin outline, the title in the accent, quiet lines
        local back = YR.RXPSkinBack()
        if e.card then
            e.fill:Hide()
            e.card:SetVertexColor(back[1], back[2], back[3], back[4])
            e.card:Show()
        else
            e.fill:SetColorTexture(back[1], back[2], back[3], back[4])
            e.fill:Show()
        end
        e.border:Hide()
        if e.metal then e.metal:Hide() end
        if e.outline then
            e.outline:SetVertexColor(1, 1, 1, 0.16)
            e.outline:Show()
        else
            for _, t in ipairs(e.lines) do t:SetColorTexture(1, 1, 1, 0.12) t:Show() end
        end
        e.headLine:Show()
        e.footLine:Show()
        e.headLine:SetColorTexture(accent[1], accent[2], accent[3], 0.55)
        e.headLine:SetHeight(1)
        e.footLine:SetColorTexture(1, 1, 1, 0.07)
        e.footLine:SetHeight(1)
        if title and title.SetTextColor then title:SetTextColor(accent[1], accent[2], accent[3]) end
        if foot and foot.SetTextColor then foot:SetTextColor(0.50, 0.53, 0.58) end
    else
        -- Blizzard: the game's frame fill and frame, its divider under the header, gold titles
        if e.card then e.card:Hide() end
        if e.outline then e.outline:Hide() end
        local fill = FirstAtlas("heavybronze-frame-background")
        if fill then e.fill:SetAtlas(fill) else e.fill:SetColorTexture(0.05, 0.045, 0.04, 0.94) end
        e.fill:Show()
        local border = not e.metal and FirstAtlas("heavybronze-frame-basic")
        if e.metal then
            e.metal:Show()
            e.border:Hide()
        elseif border then
            e.border:SetAtlas(border)
            e.border:Show()
        else
            e.border:Hide()
            for _, t in ipairs(e.lines) do t:SetColorTexture(0.55, 0.42, 0.18, 0.9) t:Show() end
        end
        local divider = FirstAtlas("Options_HorizontalDivider")
        for _, line in ipairs({ e.headLine, e.footLine }) do
            if divider then line:SetAtlas(divider) else line:SetColorTexture(0.55, 0.42, 0.18, 0.7) end
            line:SetHeight(divider and 2 or 1)
            line:SetShown(not e.metal)          -- the window and its inner panel have their own lines
        end
        if title and title.SetTextColor then title:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
        if foot and foot.SetTextColor then foot:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
    end
    ScrollBar(frame, mode, accent)
end
YR.RXPSkinPaint = Paint

-- ---------------------------------------------------------------------------
-- Handing them to RestedXP, and switching
-- ---------------------------------------------------------------------------
local function Register()
    local rxp = Rxp()
    if not rxp then return false end
    local headstart, blizzard = YR.RXPSkinThemes()
    local ok = pcall(function()
        rxp:RegisterTheme(headstart)
        rxp:RegisterTheme(blizzard)
    end)
    return ok
end

local function Redraw()
    local rxp = Rxp()
    if not rxp then return end
    Borders()
    pcall(function()
        if type(rxp.RenderFrame) == "function" then rxp.RenderFrame("themeReload") end
        if rxp.v2 and rxp.v2.ConvertThemes then rxp.v2:ConvertThemes() end
        if rxp.v2 and rxp.v2.IsGuideWindowEnabled and rxp.v2:IsGuideWindowEnabled() and rxp.ReloadTheme then rxp:ReloadTheme() end
    end)
    Paint()
end

--- Pick a look: "headstart", "blizzard" or "off" (back to the RestedXP theme you had).
function YR.SetRXPSkin(mode)
    local rxp = Rxp()
    local profile = rxp and rxp.settings and rxp.settings.profile
    if not profile then return false end
    if profile.activeTheme ~= HEADSTART and profile.activeTheme ~= BLIZZARD then YippRouteDB.rxpSkinPrev = profile.activeTheme end
    Register()
    profile.activeTheme = mode == "headstart" and HEADSTART or mode == "blizzard" and BLIZZARD
        or YippRouteDB.rxpSkinPrev or "RXP Blue"
    Redraw()
    return true
end

--- After a colour changed: the themes made again with it, and the window drawn again.
function YR.RXPSkinApply()
    if not Register() then return end
    if YR.RXPSkinMode() ~= "off" then Redraw() end
end

function YR.RXPSkinAvailable() return Rxp() ~= nil end

function YR.StartRXPSkin()
    local rxp = Rxp()
    if not rxp then return end
    Register()
    -- RestedXP picks its theme, then draws: the border's size goes in between, our colours after
    if type(rxp.LoadActiveTheme) == "function" then hooksecurefunc(rxp, "LoadActiveTheme", Borders) end
    if type(rxp.RenderFrame) == "function" then hooksecurefunc(rxp, "RenderFrame", Paint) end
    if type(rxp.SetupGuideWindow) == "function" then hooksecurefunc(rxp, "SetupGuideWindow", Paint) end
    -- the boxes of the steps you're on are made (and their edges set) each time the step changes
    if type(rxp.SetStep) == "function" then hooksecurefunc(rxp, "SetStep", StepBoxes) end
    if type(rxp.RXPFrame) == "table" and type(rxp.RXPFrame.UpdateVisuals) == "function" then
        hooksecurefunc(rxp.RXPFrame, "UpdateVisuals", Paint)
    end
    if YR.RXPSkinMode() ~= "off" then Redraw() end
end
