-- Blizzard's bag bar and micro menu (the row of small buttons: character, talents, the game menu...)
-- out of the way: each as Blizzard has it, shown only under the mouse, or hidden (Headstart, QoL,
-- Windows). Both start as Blizzard has them.
--   Only how see-through the bar is changes (SetAlpha), and - for "hidden" - whether its buttons take
--   the mouse, so a hidden bar isn't clicked by accident. Nothing is moved, reparented or hidden with
--   Hide: Edit Mode keeps its hold on both, and nothing here is a protected call. The mouse part waits
--   for the end of a fight all the same.
--   "Under the mouse": the bar is looked at ten times a second while that mode is picked for either bar,
--   and not at all otherwise. In Edit Mode both show, so you can see what you place.
--   The chat's buttons (the strip beside each chat window with the chat menu and the voice buttons,
--   the text-to-speech button and the social button under it) can be taken away too. Blizzard fades
--   that strip in and out by itself, so see-through wouldn't hold: these are hidden, and hidden again
--   whenever the game shows them. They aren't Edit Mode frames or protected ones. The chat window
--   may then be moved all the way to the screen's edge on the side they were (ChatClamp).
--   Account options (YippRouteDB): bagBar, microMenu = "hover" | "hide" (nil: Blizzard's own);
--   chatStrip ("slim" | "hide"), chatTTSHide, chatSocialHide (see "The chat's buttons" below).
local ADDON, YR = ...

local BARS = {
    bagBar = function() return _G.BagsBar end,
    microMenu = function() return _G.MicroMenuContainer or _G.MicroMenu end,
}
local MODES = { hover = true, hide = true }
local quiet = {}        -- [bar key] = { button = true } whose mouse we turned off
local shown = {}        -- [bar key] = the alpha we last set (nil: never touched)
local editing = false
local ticker

function YR.BarHideMode(key)
    local v = YippRouteDB[key]
    return YR.QoLOn() and MODES[v] and v or "show"
end

local function Frame(key)
    local f = BARS[key] and BARS[key]()
    return type(f) == "table" and f.SetAlpha and f or nil
end

-- The bar's buttons take the mouse, or don't. Only the ones we turned off are turned on again.
local function Mouse(key, frame, on)
    if InCombatLockdown() then return false end
    local off = quiet[key]
    if on then
        if off then
            for button in pairs(off) do button:EnableMouse(true) end
            quiet[key] = nil
        end
        return true
    end
    if off then return true end          -- done already: the bar's buttons don't change
    off = {}
    quiet[key] = off
    local function Walk(f, depth)
        for _, child in ipairs({ f:GetChildren() }) do
            -- a protected button is never touched, in a fight or out of one
            if child.IsMouseEnabled and child:IsMouseEnabled() and not (child.IsProtected and child:IsProtected()) then
                child:EnableMouse(false)
                off[child] = true
            end
            if depth < 2 and child.GetChildren then Walk(child, depth + 1) end
        end
    end
    Walk(frame, 1)
    return true
end

local function Alpha(key, frame, a)
    if shown[key] == a and frame:GetAlpha() == a then return end
    shown[key] = a
    frame:SetAlpha(a)
end

local function Apply(key)
    local frame = Frame(key)
    if not frame then return end
    local mode = YR.BarHideMode(key)
    if mode == "show" or editing then
        if shown[key] then Alpha(key, frame, 1) end
        if quiet[key] then Mouse(key, frame, true) end
        if mode == "show" then shown[key] = nil end
    elseif mode == "hide" then
        Alpha(key, frame, 0)
        Mouse(key, frame, false)
    else
        if quiet[key] then Mouse(key, frame, true) end
        Alpha(key, frame, frame:IsMouseOver() and 1 or 0)
    end
end

-- The chat's buttons.
--   The strip beside each chat window (chatStrip): as Blizzard has it, "slim" or "hide".
--     slim: the strip at 18 wide in place of 29, and the buttons on it (the chat menu, channels, the
--     minimise button of a window of its own) small, with one plain icon of ours each in place of
--     Blizzard's round art. They are still Blizzard's buttons, clicked as before: only their size and
--     their art change, and both are put back. Blizzard still fades the strip in under the mouse.
--     hide: hidden, and hidden again whenever the game shows it.
--   The text-to-speech button and the social button over the strip: each can be hidden (chatTTSHide,
--   chatSocialHide).
local SLIM, STRIP = 18, 29
local gone, hooked = {}, {}          -- gone[frame] = true for the ones we hid that the game wanted shown
local slimmed = {}                   -- [strip] = true while it is slim
local sized = {}                     -- [frame] = the size or scale it had, while it is made small
local faces = setmetatable({}, { __mode = "k" })     -- [button] = { size, alphas, icon }

function YR.ChatStripMode()
    local v = YippRouteDB.chatStrip
    return YR.QoLOn() and (v == "slim" or v == "hide") and v or "show"
end
local function Hidden(key) return YR.QoLOn() and YippRouteDB[key] == true end

-- Hidden, and kept hidden; or shown again if it was us who hid it.
local function Keep(f, hide, still)
    if type(f) ~= "table" or not f.Hide or (f.IsProtected and f:IsProtected() and InCombatLockdown()) then return end
    if hide then
        if not hooked[f] and f.HookScript then
            hooked[f] = true
            f:HookScript("OnShow", function(self)
                if still() and not (self.IsProtected and self:IsProtected() and InCombatLockdown()) then gone[self] = true self:Hide() end
            end)
        end
        if f:IsShown() then gone[f] = true f:Hide() end
    elseif gone[f] then
        gone[f] = nil
        f:Show()
    end
end

-- Every piece of Blizzard's art on the button made clear. Its flashing light (something new in a
-- channel) is left to flash.
local function Sweep(button, k)
    for _, region in ipairs({ button:GetRegions() }) do
        if region ~= k.icon and region ~= button.Flash and region.IsObjectType and region:IsObjectType("Texture") then
            if k.alphas[region] == nil then k.alphas[region] = region:GetAlpha() end
            if region:GetAlpha() ~= 0 then region:SetAlpha(0) end
        end
    end
end

-- A button of Blizzard's with a small plain icon of ours in place of its art, or as it was.
-- Blizzard gives a button new art as it goes (its pressed and lit pictures are made the first time
-- they're needed, and its picture is set again when its state changes), so the sweep is done again
-- whenever the button is pointed at, pressed, let go or shown.
local function Face(button, kind, on)
    if type(button) ~= "table" or not button.GetRegions then return end
    local k = faces[button]
    if on then
        if not k then
            k = { size = { button:GetSize() }, alphas = {} }
            faces[button] = k
            k.icon = button:CreateTexture(nil, "OVERLAY")
            k.icon:SetPoint("CENTER")
            k.icon:SetSize(SLIM - 4, SLIM - 4)
            YR.Style.ArtTexture(k.icon, kind)
            k.icon:SetVertexColor(0.78, 0.80, 0.85)
            button:HookScript("OnEnter", function() k.icon:SetVertexColor(1, 1, 1) end)
            button:HookScript("OnLeave", function() k.icon:SetVertexColor(0.78, 0.80, 0.85) end)
            for _, script in ipairs({ "OnEnter", "OnLeave", "OnMouseDown", "OnMouseUp", "OnShow" }) do
                button:HookScript(script, function(self) if k.on then Sweep(self, k) end end)
            end
            -- and after a click has changed what the button stands for
            button:HookScript("OnClick", function(self)
                if k.on then C_Timer.After(0, function() if k.on then Sweep(self, k) end end) end
            end)
        end
        Sweep(button, k)
        button:SetSize(SLIM, SLIM)
        k.icon:Show()
        k.on = true
    elseif k and k.on then
        k.on = false
        for region, a in pairs(k.alphas) do region:SetAlpha(a) end
        k.alphas = {}
        if k.size[1] then button:SetSize(k.size[1], k.size[2]) end
        k.icon:Hide()
    end
end

-- Edit Mode keeps the chat window on screen by its selection box, which reaches out over the button
-- strip: with the strip gone or slim the window still stopped a whole strip's width short of the
-- screen's edge. So after Edit Mode has set how far the window may go, the side the buttons are on is
-- let go to the edge (hidden), or to the slim strip's width. The same sum as Blizzard's otherwise.
local clampHooked
local function ChatClamp()
    local chat = _G.ChatFrame1
    local box = type(chat) == "table" and chat.Selection
    if type(box) ~= "table" or not chat.SetClampRectInsets or not chat:GetLeft() or not box:GetLeft() then return end
    if not clampHooked and type(chat.UpdateClampOffsets) == "function" then
        clampHooked = true
        hooksecurefunc(chat, "UpdateClampOffsets", function() if YR.ChatStripMode() ~= "show" then ChatClamp() end end)
    end
    local left, right = box:GetLeft() - chat:GetLeft(), box:GetRight() - chat:GetRight()
    local mode = YR.ChatStripMode()
    if mode ~= "show" then
        local room = mode == "slim" and (SLIM + 5) or 0
        if chat.buttonSide == "right" then right = room else left = -room end
    end
    chat:SetClampRectInsets(left, right, box:GetTop() - chat:GetTop(), box:GetBottom() - chat:GetBottom())
end

local function StripHidden() return YR.ChatStripMode() == "hide" end
local function SpeechHidden() return Hidden("chatTTSHide") end
local function SocialHidden() return Hidden("chatSocialHide") end
local function ChatButtons()
    local mode = YR.ChatStripMode()
    if mode ~= "show" or clampHooked then ChatClamp() end
    local slim = mode == "slim"
    for i = 1, tonumber(_G.NUM_CHAT_WINDOWS) or 10 do
        local strip = _G["ChatFrame" .. i .. "ButtonFrame"]
        if type(strip) == "table" and strip.SetWidth then
            Keep(strip, mode == "hide", StripHidden)
            if slim or slimmed[strip] then
                slimmed[strip] = slim or nil
                strip:SetWidth(slim and SLIM or STRIP)
                Face(rawget(strip, "minimizeButton"), "minus", slim)
            end
        end
    end
    Face(_G.ChatFrameMenuButton, "bubble", slim)
    Face(_G.ChatFrameChannelButton, "people", slim)
    -- the two over the strip are 32 wide like the strip's own were: slim too, so they sit on an 18-wide
    -- strip without lying over their neighbours. The speaker gets our icon; the social button keeps its
    -- own art (its number of friends is on it) and is made smaller whole.
    Face(_G.TextToSpeechButton, "sound", slim)
    local holder, social = _G.TextToSpeechButtonFrame, _G.QuickJoinToastButton
    if type(holder) == "table" and holder.SetSize and (slim or sized[holder]) then
        if slim and not sized[holder] then sized[holder] = { holder:GetSize() } end
        if slim then holder:SetSize(SLIM, SLIM) else holder:SetSize(sized[holder][1], sized[holder][2]) sized[holder] = nil end
    end
    if type(social) == "table" and social.SetScale and (slim or sized[social]) then
        if slim and not sized[social] then sized[social] = { social:GetScale() } end
        if slim then social:SetScale(SLIM / 32) else social:SetScale(sized[social][1] or 1) sized[social] = nil end
    end
    Keep(_G.TextToSpeechButtonFrame, SpeechHidden(), SpeechHidden)
    Keep(_G.QuickJoinToastButton, SocialHidden(), SocialHidden)
end

--- As the options are now (after one changed, a reload, a fight, Edit Mode).
function YR.BarHideApply()
    ChatButtons()
    local hover = false
    for key in pairs(BARS) do
        Apply(key)
        if YR.BarHideMode(key) == "hover" then hover = true end
    end
    if hover and not ticker then
        ticker = C_Timer.NewTicker(0.1, function()
            for key in pairs(BARS) do
                if YR.BarHideMode(key) == "hover" then Apply(key) end
            end
        end)
    elseif not hover and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

function YR.SetBarHide(key, mode)
    if not BARS[key] then return end
    YippRouteDB[key] = MODES[mode] and mode or nil
    YR.BarHideApply()
end

function YR.StartBarHide()
    -- the one switch there was first: everything hidden
    if YippRouteDB.chatButtonsHide == true then
        YippRouteDB.chatStrip, YippRouteDB.chatTTSHide, YippRouteDB.chatSocialHide = "hide", true, true
    end
    YippRouteDB.chatButtonsHide = nil
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function() YR.BarHideApply() end)
    local registry = _G.EventRegistry
    if type(registry) == "table" and registry.RegisterCallback then
        registry:RegisterCallback("EditMode.Enter", function() editing = true YR.BarHideApply() end, f)
        registry:RegisterCallback("EditMode.Exit", function() editing = false YR.BarHideApply() end, f)
    end
end
