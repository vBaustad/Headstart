-- Damage meter skin: two looks for the game's own damage meter (Blizzard_DamageMeter), picked in
-- Headstart, QoL, Skins. Off until you pick one.
--   What's wrong with the meter as it comes: its top bar. The timer comes in at the left in a fight and
--   pushes the title onto two lines, the title sits in the middle of nowhere, and the three buttons are
--   three different things at three different sizes.
--   Both looks lay the top bar out the same way: the title (the kind of meter)
--   at the left on one line; at the right the fight's timer and one row of small plain icons, as
--   Details has them: what it shows, which fight, reset, settings, minimise.
--     Headstart: a flat dark card with a thin outline, the title in the accent with a line under the
--     bar. The frame's colour and the accent are yours to pick (or the accent is your class colour).
--     Blizzard: the game's dark frame fill, its thin panel round the window, the title in gold.
--   How: nothing of Blizzard's is replaced and no field is written on its frames. Its own pieces are
--   re-anchored (where each was is kept, and put back when the look is turned off), its header art is
--   made clear, and ours is drawn on textures of our own. The bars, their style, height and text are
--   left to the meter's own Edit Mode settings. What we keep per window lives in a table of ours.
--   The meter's window is laid out again by the game whenever it refreshes; we go over it after each.
--   Account options (YippRouteDB): dmgSkin ("headstart", "blizzard"; anything else is off),
--   dmgSkinAccent { r, g, b }, dmgSkinFrame { r, g, b, a }, dmgSkinClass (accent = class colour).
local ADDON, YR = ...

local GOLD = { 1, 0.82, 0 }
local BRONZE = { 0.64, 0.52, 0.30 }
local DEFAULT_ACCENT = { 0.40, 0.66, 1.00 }
local DEFAULT_FRAME = { 0.075, 0.08, 0.095, 0.92 }
local TITLE_SIZE, TIMER_SIZE = 11, 10       -- the title and the fight's timer, small enough to share the bar
local BUTTON, GAP, PAD = 14, 3, 8          -- the row of buttons: one size, close together, clear of the frame

--- "headstart", "blizzard" or "off".
function YR.DamageSkinMode()
    local m = YippRouteDB.dmgSkin
    if (m == "headstart" or m == "blizzard") and YR.QoLOn() then return m end
    return "off"
end

function YR.DamageSkinAccent()
    if YippRouteDB.dmgSkinClass == true then
        local _, class = UnitClass("player")
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then return { c.r, c.g, c.b } end
    end
    local a = YippRouteDB.dmgSkinAccent
    return type(a) == "table" and { a[1], a[2], a[3] } or { DEFAULT_ACCENT[1], DEFAULT_ACCENT[2], DEFAULT_ACCENT[3] }
end

function YR.DamageSkinFrame()
    local f = YippRouteDB.dmgSkinFrame
    f = type(f) == "table" and f or DEFAULT_FRAME
    return { f[1], f[2], f[3], f[4] or 1 }
end

local atlasKnown = {}
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

-- ---------------------------------------------------------------------------
-- The windows, and what we keep for each
-- ---------------------------------------------------------------------------
local kept = setmetatable({}, { __mode = "k" })     -- [window] = { points = {...}, sizes = {...}, art = {...} }

local function IsWindow(f)
    return type(f) == "table" and type(f.GetDamageMeterTypeDropdown) == "function" and type(f.GetMinimizeButton) == "function"
end

--- Every meter window there is now (the game can have more than one).
local function Windows()
    local found = {}
    local owner = _G.DamageMeter
    if type(owner) == "table" and owner.GetChildren then
        for _, child in ipairs({ owner:GetChildren() }) do
            if IsWindow(child) then found[#found + 1] = child end
        end
    end
    for i = 1, 5 do
        local named = _G["DamageMeterSessionWindow" .. i]
        if IsWindow(named) then
            local have
            for _, w in ipairs(found) do if rawequal(w, named) then have = true end end
            if not have then found[#found + 1] = named end
        end
    end
    return found
end

-- A piece's own place and size, kept the first time we move it, and put back when the look goes off.
local function Remember(k, piece)
    if type(piece) ~= "table" or k.points[piece] or not piece.GetNumPoints then return end
    local points = {}
    for i = 1, piece:GetNumPoints() do points[i] = { piece:GetPoint(i) } end
    k.points[piece] = points
    if piece.GetSize then k.sizes[piece] = { piece:GetSize() } end
end

-- A button with a face of ours. Blizzard's buttons each bring their own art at its own size (a boxed
-- letter, a small gear, a red square, a large yellow arrow box): sized alike they still look like four
-- different things. So their art is made clear (the button itself, and what a click on it does, is
-- untouched) and each gets one plain icon of ours in the look's colour, the way Details has its row:
--   "bars"  what the meter shows (damage, healing, ...): Blizzard's type dropdown
--   letter  which fight (C this one, O all of them): Blizzard's session dropdown, its own letter kept
--   "reset" clear the meter: a button of ours (Blizzard has this inside its settings menu)
--   "gear"  the meter's settings: Blizzard's settings dropdown
--   "minus" / "plus"  minimise and restore
-- Each lights up under the mouse.
local function Face(k, button, kind, c)
    if type(button) ~= "table" or not button.GetRegions then return end
    for _, region in ipairs({ button:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("Texture") then
            if not k.faces[region] then
                k.tinted[region] = true
                region:SetAlpha(0)
            end
        elseif region.IsObjectType and region:IsObjectType("FontString") and region.GetTextColor and kind == "letter" then
            if not k.letters[region] then k.letters[region] = { region:GetTextColor() } end
            region:SetTextColor(c[1], c[2], c[3])
        end
    end
    if kind == "letter" then return end
    local icon = k.face[button]
    if not icon and button.CreateTexture then
        icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("CENTER")
        icon:SetSize(BUTTON, BUTTON)
        k.faces[icon] = true
        k.face[button] = icon
        if button.HookScript then
            button:HookScript("OnEnter", function() if icon:IsShown() then icon:SetAlpha(1) end end)
            button:HookScript("OnLeave", function() if icon:IsShown() then icon:SetAlpha(0.75) end end)
        end
    end
    if not icon then return end
    if YR.Style and YR.Style.ArtTexture then YR.Style.ArtTexture(icon, kind) end
    icon:SetVertexColor(c[1], c[2], c[3])
    icon:SetAlpha(0.75)
    icon:Show()
end

-- Our own button in the row: clear the meter.
local function ResetButton(window, k)
    if k.reset then return k.reset end
    local b = CreateFrame("Button", nil, window)
    b:SetSize(BUTTON, BUTTON)
    b:SetFrameLevel((window.GetFrameLevel and window:GetFrameLevel() or 1) + 5)
    b:SetScript("OnClick", function()
        if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then C_DamageMeter.ResetAllCombatSessions() end
    end)
    b:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Reset")
        GameTooltip:AddLine("Clears every fight the meter has kept", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    k.reset = b
    return b
end

-- A text at a smaller size, in its own font: what it was is kept and put back.
local function Smaller(k, fs, size)
    if not (fs.GetFont and fs.SetFont) then return end
    if not k.fonts[fs] then k.fonts[fs] = { fs:GetFont() } end
    local was = k.fonts[fs]
    if was[1] then fs:SetFont(was[1], size, was[3]) end
end

local function PutBack(k)
    for fs, was in pairs(k.fonts) do
        if was[1] and was[2] then fs:SetFont(was[1], was[2], was[3]) end
    end
    k.fonts = {}
    for region in pairs(k.tinted) do region:SetAlpha(1) end
    for _, icon in pairs(k.face) do icon:Hide() end
    if k.reset then k.reset:Hide() end
    for region, was in pairs(k.letters) do region:SetTextColor(was[1] or 1, was[2] or 1, was[3] or 1) end
    k.tinted, k.letters = {}, {}
    for piece, points in pairs(k.points) do
        piece:ClearAllPoints()
        for _, p in ipairs(points) do piece:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        local size = k.sizes[piece]
        if size and piece.SetSize and (size[1] or 0) > 0 and (size[2] or 0) > 0 then piece:SetSize(size[1], size[2]) end
    end
    k.points, k.sizes = {}, {}
end

local function Pieces(window)
    local typeDrop, session = window:GetDamageMeterTypeDropdown(), window:GetSessionDropdown()
    return {
        header = window.GetHeader and window:GetHeader(),
        typeDrop = typeDrop,
        title = type(typeDrop) == "table" and typeDrop.TypeName or nil,
        session = session,
        settings = window.GetSettingsDropdown and window:GetSettingsDropdown(),
        minimize = window:GetMinimizeButton(),
        timer = window.GetSessionTimerFontString and window:GetSessionTimerFontString(),
        container = window.GetMinimizeContainer and window:GetMinimizeContainer(),
    }
end

-- Our own art on the window: a fill behind it, a frame round it, the top bar's fill and the line under it.
local function Art(window, k, p)
    if k.art then return k.art end
    local S = YR.Style
    local a = {}
    a.fill = window:CreateTexture(nil, "BACKGROUND", nil, -6)
    a.fill:SetAllPoints(window)
    a.card = S and S.Rounded and S.Rounded(window, "BACKGROUND", "round", -5) or nil
    a.outline = S and S.Rounded and S.Rounded(window, "BORDER", "roundline", 1) or nil
    a.panel = window:CreateTexture(nil, "BORDER", nil, 2)
    a.panel:SetPoint("TOPLEFT", -4, 4)
    a.panel:SetPoint("BOTTOMRIGHT", 4, -4)
    a.bar = window:CreateTexture(nil, "BACKGROUND", nil, -4)
    a.line = window:CreateTexture(nil, "ARTWORK")
    a.line:SetHeight(1)
    local over = type(p.header) == "table" and p.header.GetHeight and p.header or nil
    if over then
        a.bar:SetAllPoints(over)
        a.line:SetPoint("TOPLEFT", over, "BOTTOMLEFT", 0, 0)
        a.line:SetPoint("TOPRIGHT", over, "BOTTOMRIGHT", 0, 0)
    else
        a.bar:SetPoint("TOPLEFT") a.bar:SetPoint("TOPRIGHT") a.bar:SetHeight(24)
        a.line:SetPoint("TOPLEFT", 0, -24) a.line:SetPoint("TOPRIGHT", 0, -24)
    end
    k.art = a
    return a
end

local function ShowArt(a, on)
    for _, t in pairs(a) do if type(t) == "table" and t.SetShown then t:SetShown(on) end end
end

-- Blizzard's own header art out of sight (its textures only: whatever sits in it stays)
local function HeaderArt(header, alpha)
    if type(header) ~= "table" then return end
    if header.IsObjectType and header:IsObjectType("Texture") then
        header:SetAlpha(alpha)
    elseif header.GetRegions then
        for _, region in ipairs({ header:GetRegions() }) do
            if region.IsObjectType and region:IsObjectType("Texture") then region:SetAlpha(alpha) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- One window in one look
-- ---------------------------------------------------------------------------
local function Skin(window)
    local mode = YR.DamageSkinMode()
    local k = kept[window]
    if mode == "off" then
        if k and k.on then
            k.on = false
            PutBack(k)
            if k.art then ShowArt(k.art, false) end
            local p = Pieces(window)
            HeaderArt(p.header, 1)
            if type(p.title) == "table" and p.title.SetTextColor then p.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
        end
        return
    end
    if not k then
        k = { points = {}, sizes = {}, tinted = {}, letters = {}, face = {}, faces = {}, fonts = {} }
        kept[window] = k
    end
    k.on = true
    local p = Pieces(window)
    local over = type(p.header) == "table" and p.header.GetHeight and p.header or window
    local a = Art(window, k, p)

    -- the top bar: the title at the left; at the right one row, right to left: minimise, settings,
    -- reset, which fight, what it shows - and the fight's timer before them
    local reset = ResetButton(window, k)
    reset:Show()
    local at = -PAD
    for _, b in ipairs({ p.minimize, p.settings, reset, p.session, p.typeDrop }) do
        if type(b) == "table" and b.ClearAllPoints then
            if not rawequal(b, reset) then Remember(k, b) end
            b:ClearAllPoints()
            b:SetSize(BUTTON, BUTTON)
            b:SetPoint("RIGHT", over, "RIGHT", at, 0)
            at = at - BUTTON - GAP
        end
    end
    if type(p.timer) == "table" and p.timer.ClearAllPoints then
        Remember(k, p.timer)
        Smaller(k, p.timer, TIMER_SIZE)
        p.timer:ClearAllPoints()
        p.timer:SetPoint("RIGHT", over, "RIGHT", at - 3, 0)
        if p.timer.SetJustifyH then p.timer:SetJustifyH("RIGHT") end
    end
    -- the title is a font string of the type dropdown: it stays at the left when the dropdown moves
    if type(p.title) == "table" and p.title.ClearAllPoints then
        Remember(k, p.title)
        Smaller(k, p.title, TITLE_SIZE)
        p.title:ClearAllPoints()
        p.title:SetPoint("LEFT", over, "LEFT", PAD, 0)
        -- it ends where the timer begins (cut short there, not written over it)
        if type(p.timer) == "table" then p.title:SetPoint("RIGHT", p.timer, "LEFT", -4, 0) end
        if p.title.SetWordWrap then p.title:SetWordWrap(false) end
        if p.title.SetJustifyH then p.title:SetJustifyH("LEFT") end
    end

    HeaderArt(p.header, 0)
    ShowArt(a, true)
    local accent = mode == "headstart" and YR.DamageSkinAccent() or nil
    -- the three buttons in one flat colour: the accent, or the Blizzard look's bronze
    local flat = accent or BRONZE
    local small = window.IsMinimized and window:IsMinimized()
    Face(k, p.minimize, small and "plus" or "minus", flat)
    Face(k, p.settings, "gear", flat)
    Face(k, reset, "reset", flat)
    Face(k, p.session, "letter", flat)
    Face(k, p.typeDrop, "bars", flat)
    if accent then
        local f = YR.DamageSkinFrame()
        a.fill:Hide()
        a.panel:Hide()
        if a.card then a.card:SetVertexColor(f[1], f[2], f[3], f[4]) else a.fill:SetColorTexture(f[1], f[2], f[3], f[4]) a.fill:Show() end
        if a.outline then a.outline:SetVertexColor(1, 1, 1, 0.16) end
        a.bar:SetColorTexture(1, 1, 1, 0.04)
        a.line:SetColorTexture(accent[1], accent[2], accent[3], 0.55)
        if type(p.title) == "table" and p.title.SetTextColor then p.title:SetTextColor(accent[1], accent[2], accent[3]) end
        if type(p.timer) == "table" and p.timer.SetTextColor then p.timer:SetTextColor(0.6, 0.63, 0.68) end
    else
        if a.card then a.card:Hide() end
        if a.outline then a.outline:Hide() end
        if HasAtlas("heavybronze-frame-background") then a.fill:SetAtlas("heavybronze-frame-background")
        else a.fill:SetColorTexture(0.05, 0.045, 0.04, 0.92) end
        if HasAtlas("common-insideframe") then a.panel:SetAtlas("common-insideframe") else a.panel:Hide() end
        a.bar:SetColorTexture(0, 0, 0, 0.35)
        a.line:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.8)
        if type(p.title) == "table" and p.title.SetTextColor then p.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
        if type(p.timer) == "table" and p.timer.SetTextColor then p.timer:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) end
    end
end

-- The game lays a window out again when it refreshes: we go over it after. Hooked once per window.
local hooked = setmetatable({}, { __mode = "k" })
local busy, faulted

local function After(window)
    if busy then return end
    local k = kept[window]
    if YR.DamageSkinMode() == "off" and not (k and k.on) then return end
    busy = true
    local ok, err = pcall(Skin, window)
    busy = false
    -- a fault of ours must not break the meter, but it must not vanish either: said once
    if not ok and not faulted then
        faulted = true
        YR.Print("the damage meter skin hit an error and was left as it is: " .. tostring(err))
    end
end

--- Every window in the look that's picked (after a setting changed, a login, a new window).
function YR.DamageSkinApply()
    for _, window in ipairs(Windows()) do
        if not hooked[window] then
            hooked[window] = true
            for _, method in ipairs({ "RefreshLayout", "SetMinimized", "SetDamageMeterType" }) do
                if type(window[method]) == "function" then hooksecurefunc(window, method, After) end
            end
        end
        After(window)
    end
end

function YR.SetDamageSkin(mode)
    YippRouteDB.dmgSkin = (mode == "headstart" or mode == "blizzard") and mode or nil
    YR.DamageSkinApply()
end

--- Whether the game's damage meter is there to skin.
function YR.DamageSkinAvailable() return #Windows() > 0 end

function YR.StartDamageSkin()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED", "ADDON_LOADED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event, name)
        if event == "ADDON_LOADED" and name ~= "Blizzard_DamageMeter" then return end
        -- nothing to do, and nothing looked for, while no look is picked
        if YR.DamageSkinMode() == "off" then return end
        C_Timer.After(0.2, YR.DamageSkinApply)
    end)
end
