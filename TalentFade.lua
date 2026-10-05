-- Talent window, see-through: the background of Blizzard's talent window faded so you can see where
-- you're running with it open. Only the background art fades (the window's own fill, the talent
-- page's two backdrops, its inner frame art and the dividers: the gold band along the top and the
-- lines down between the trees); the talents, texts, the window's border and the buttons stay.
--   And the window moved: drag it by its title bar or anywhere that isn't a button or a talent (the
--   spellbook is the same window, so it moves
--   too). Blizzard puts the window in the middle each time it opens; we put it back where you left it,
--   out of combat only (a caution: the window isn't protected on this client, but its size and place
--   are Blizzard's panel manager's too, and that is left alone in a fight).
--   A slider on the talent window itself (bottom left; the size's bottom right) and the same in the settings.
--   Blizzard's window loads when first opened (Blizzard_PlayerSpells), so we hook it then. On its
--   textures only alpha is set; nothing is hidden or re-parented.
--   Account options (YippRouteDB, Headstart, QoL, Talent window): talentFade (0-100, how see-through;
--   0 is Blizzard's own), talentFadeSlider (the slider on the window, on unless turned off), talentMove
--   (drag by the title bar, on unless turned off; where you left it is YippRouteDB.moved.talents),
--   talentScale (50-150 percent, 100 is Blizzard's own). The size is the talent page's only: the
--   spellbook is the same window and gets its own size back. Set out of combat.
local ADDON, YR = ...

local slider
local LIGHTS_UP_TO = 50      -- Blizzard's moving lights play up to this much see-through, and stop past it
local LIGHTS = { "Clouds1", "Clouds2", "AirParticlesClose", "AirParticlesFar", "OverlayBackgroundRight", "OverlayBackgroundMid" }

function YR.TalentFade()
    return math.max(0, math.min(100, tonumber(YippRouteDB.talentFade) or 0))
end

-- The textures that make the background: the talent page's, and the window's own behind it.
local function Parts()
    local frame = _G.PlayerSpellsFrame
    local talents = frame and frame.TalentsFrame
    if not talents then return nil end
    return { talents.Background, talents.ClassBackground, talents.BackgroundBorder, talents.DividerHorizontalLeft,
        talents.DividerHorizontalRight, talents.DividerVerticalLeft, talents.DividerVerticalRight },
        { frame.Bg, frame.TopTileStreaks }, talents
end

function YR.TalentScale()
    return math.max(50, math.min(150, tonumber(YippRouteDB.talentScale) or 100))
end

-- The window at your size while the talent page is the one open, at Blizzard's (1) otherwise. Never
-- touched while the setting is 100 and we haven't changed it.
local scaled
local function Scale()
    local frame = _G.PlayerSpellsFrame
    local talents = frame and frame.TalentsFrame
    if type(talents) ~= "table" or InCombatLockdown() then return end
    local want = talents:IsShown() and YR.QoLOn() and YR.TalentScale() / 100 or 1
    if want == 1 and not scaled then return end
    scaled = want ~= 1
    frame:SetScale(want)
end

-- The moving lights over the background: drifting clouds, floating specks, and the class art glowing
-- up and down again (to 70 percent over five seconds, round and round). Blizzard's animations set
-- their alpha themselves, so a fade of ours doesn't hold on them - the glow came up through a
-- see-through window seconds after it opened. Up to half see-through they're left to play (the
-- window still has a background for them to belong to); past that the animations are stopped,
-- which hides what they move, and they play again when you come back under it.
local quiet
local function Lights(talents, off)
    local anims = talents.backgroundAnims
    if type(anims) ~= "table" then return end
    off = off and true or false
    if not off and not quiet then return end           -- never stopped by us: Blizzard's to run
    quiet = off
    for _, group in ipairs(anims) do
        if type(group) == "table" then
            if off then
                if group.Stop then group:Stop() end
            elseif group.Play and not (group.IsPlaying and group:IsPlaying()) then
                group:Play()
            end
        end
    end
    if off then
        for _, key in ipairs(LIGHTS) do
            local t = talents[key]
            if type(t) == "table" and t.SetAlpha then t:SetAlpha(0) end
        end
    else
        -- the clouds have no alpha animation of their own: back to what Blizzard gives them
        for _, key in ipairs({ "Clouds1", "Clouds2" }) do
            local t = talents[key]
            if type(t) == "table" and t.SetAlpha then t:SetAlpha(0.05) end
        end
    end
end

--- The fade put on the window (and taken off the window's own fill when the talent page isn't the one open,
--- so the spellbook keeps its background).
function YR.TalentFadeApply()
    local page, window, talents = Parts()
    if not page then return end
    local alpha = YR.QoLOn() and 1 - YR.TalentFade() / 100 or 1
    for _, t in pairs(page) do if type(t) == "table" and t.SetAlpha then t:SetAlpha(alpha) end end
    Scale()
    YR.MoverPlace("talents")            -- the size changes with the page: the corner stays where you left it
    local open = talents.IsShown and talents:IsShown()
    for _, t in pairs(window) do if type(t) == "table" and t.SetAlpha then t:SetAlpha(open and alpha or 1) end end
    Lights(talents, open and alpha < 1 - LIGHTS_UP_TO / 100)
    if slider then
        slider:SetShown(YR.Option("talentFadeSlider"))
        slider:Refresh()
    end
end

-- A new size, with the window staying under the mouse: the spot the mouse is on (the size buttons,
-- when you tap them) stays where it is and the window grows or shrinks round it, so you can tap
-- again without chasing the button. With the mouse elsewhere (the settings page) it's the window's
-- middle that stays. That makes a place of its own for the window, so it's kept like a place you
-- dragged it to (only while moving the window is on, and out of combat).
function YR.SetTalentScale(v)
    local frame = _G.PlayerSpellsFrame
    local talents = type(frame) == "table" and frame.TalentsFrame
    local before
    if type(talents) == "table" and talents:IsShown() and YR.Option("talentMove") and not InCombatLockdown() then
        local s, left, top, w, h = frame:GetScale() or 1, frame:GetLeft(), frame:GetTop(), frame:GetWidth(), frame:GetHeight()
        if left and top and w and h and s > 0 then
            before = { s = s, left = left * s, top = top * s, w = w * s, h = h * s }
        end
    end
    YippRouteDB.talentScale = math.max(50, math.min(150, tonumber(v) or 100))
    Scale()
    local after = before and frame:GetScale() or nil
    if after and after ~= before.s then
        local ui = UIParent:GetEffectiveScale() or 1
        local x, y = GetCursorPosition()
        x, y = (x or 0) / ui, (y or 0) / ui
        local inside = x >= before.left and x <= before.left + before.w and y <= before.top and y >= before.top - before.h
        if not inside then x, y = before.left + before.w / 2, before.top - before.h / 2 end
        local k = after / before.s
        YR.MoverSet("talents", x - (x - before.left) * k, y + (before.top - y) * k)
    else
        YR.MoverPlace("talents")
    end
    if slider then slider:Refresh() end
end

function YR.SetTalentFade(v)
    YippRouteDB.talentFade = math.max(0, math.min(100, tonumber(v) or 0))
    YR.TalentFadeApply()
end

-- Moved by its title bar (Movers.lua does the moving)
function YR.TalentPlace() YR.MoverPlace("talents") end
function YR.TalentResetPosition() YR.MoverReset("talents") end

local hooked
local function Hook()
    local _, _, talents = Parts()
    if hooked or not talents then return end
    hooked = true
    if YippRouteDB.talentPos then          -- where it was kept before Movers.lua
        YippRouteDB.moved = YippRouteDB.moved or {}
        YippRouteDB.moved.talents, YippRouteDB.talentPos = YippRouteDB.talentPos, nil
    end
    YR.Mover("talents", function() return _G.PlayerSpellsFrame end, function() return YR.Option("talentMove") end,
        70, 70, function(frame) if HideUIPanel then HideUIPanel(frame) end end,
        -- anywhere on the window that isn't a button or a talent: the window, the talent page, and the
        -- sheet the talents sit on
        function(frame) return { frame, frame.TalentsFrame, frame.TalentsFrame and frame.TalentsFrame.ButtonsParent } end)
    YR.MoverPlace("talents")
    local S = YR.Style
    slider = CreateFrame("Frame", nil, talents)
    slider:SetSize(250, 24)
    slider:SetPoint("BOTTOMLEFT", talents, "BOTTOMLEFT", 16, 8)
    slider:SetFrameLevel(talents:GetFrameLevel() + 1000)
    local label = S.Text(slider, 11, S.C.sub)
    label:SetPoint("LEFT")
    label:SetText("See-through")
    local bar = S.Slider(slider, 0, 100, 5, YR.TalentFade, YR.SetTalentFade, 170)
    bar:SetPoint("LEFT", label, "RIGHT", 8, 0)
    -- and its size, bottom right: taps, not a slider (the window changes size under the mouse, so a
    -- knob would run from it). 5 at a time to go far, 1 at a time to get it just so.
    local size = CreateFrame("Frame", nil, slider)
    size:SetSize(230, 24)
    size:SetPoint("BOTTOMRIGHT", talents, "BOTTOMRIGHT", -16, 8)
    local sizeLabel = S.Text(size, 11, S.C.sub)
    sizeLabel:SetPoint("LEFT")
    sizeLabel:SetText("Size")
    local value = S.Text(size, 12, S.C.text)
    local prev = sizeLabel
    for _, step in ipairs({ -5, -1, 0, 1, 5 }) do
        if step == 0 then
            value:SetPoint("LEFT", prev, "RIGHT", 6, 0)
            value:SetWidth(40)
            value:SetJustifyH("CENTER")
            prev = value
        else
            local b = S.Button(size, (step > 0 and "+" or "") .. step, function()
                YR.SetTalentScale(YR.TalentScale() + step)
            end, nil, 30)
            b:SetHeight(20)
            b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
            prev = b
        end
    end
    function size:Refresh() value:SetText(YR.TalentScale() .. "%") end
    function slider:Refresh() bar:Refresh() size:Refresh() end
    talents:HookScript("OnShow", YR.TalentFadeApply)
    talents:HookScript("OnHide", YR.TalentFadeApply)
    YR.TalentFadeApply()
end

function YR.StartTalentFade()
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event, name)
        if event == "ADDON_LOADED" and name ~= "Blizzard_PlayerSpells" then return end
        -- the size isn't set in a fight: a window opened in one gets it when the fight ends
        if event == "PLAYER_REGEN_ENABLED" then YR.TalentFadeApply() return end
        Hook()
    end)
    Hook()
end
