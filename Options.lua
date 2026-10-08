-- The Blizzard options entry (Esc > Options > AddOns > Headstart) only points at our own window,
-- where the settings live with the rest; and the minimap button that opens that window.
local _, YR = ...

function YR:BuildOptions()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    -- The game's list of addons needs a panel to name: a bare one. What's on it is made the first time
    -- it is shown - most sessions never open it.
    local panel = CreateFrame("Frame")
    local built
    panel:SetScript("OnShow", function()
        if built then return end
        built = true
        local S = YR.Style
        local title = S.Text(panel, 20)
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Headstart")
        local note = S.Text(panel, 13, S.C.muted)
        note:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        note:SetText("Quality of life, routes, this run, sharing and settings are in Headstart's own window.")
        -- Settings stays open (closing it from addon code is forbidden); our window sits above it
        local open = S.Button(panel, "Open Headstart", function()
            YR:ToggleWindow("settings")
        end, "primary")
        open:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -14)
    end)
    local category = Settings.RegisterCanvasLayoutCategory(panel, "Headstart")
    Settings.RegisterAddOnCategory(category)
end

-- ---------------------------------------------------------------------------
-- Minimap button: drag it round the minimap; left click opens the window, right click the settings.
-- ---------------------------------------------------------------------------
local button

local function Place()
    local angle = math.rad(YippRouteDB.minimapAngle or 225)
    local r = Minimap:GetWidth() / 2 + 8
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    YippRouteDB.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
    Place()
end

local function Build()
    button = CreateFrame("Button", "HeadstartMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local mask = button:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(53, 53)
    ring:SetPoint("TOPLEFT")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function(self, which)
        if which == "RightButton" then YR.WindowMenu(self) else YR:ToggleWindow() end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Headstart")
        if YR.InstanceCounts and YR.Option("instanceTrack") then
            local hour, day, wait = YR.InstanceCounts()
            local perHour, perDay = YR.InstanceLimits()
            -- nothing about instances for someone who hasn't been in one today
            if day > 0 then
                GameTooltip:AddLine(("Instances: %d/%d this hour, %d/%d today%s"):format(hour, perHour, day, perDay,
                    wait and ("  (next in " .. YR.InstanceClock(wait) .. ")") or ""), 0.6, 0.8, 1)
            end
        end
        -- your gold in all (Characters): here too, for where another addon draws the bag and its coins
        if YR.AltsOn and YR.AltsOn() and YippRouteDB.altsGold ~= false then
            local sum, list = YR.AltsGold()
            if #list > 1 then
                GameTooltip:AddLine(("Gold on your %d characters: %s"):format(#list, YR.AltsCoins(sum)), 1, 0.82, 0)
            end
        end
        GameTooltip:AddLine("Click: the Headstart window", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: every window of ours (characters, chat log, quest group...)", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: move round the minimap", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Place()
end

--- Every window of ours that can be opened now, as a menu's lines: { { function, label }, ... }. A
--- window whose feature is off isn't in it. This is the short way to each of them: the minimap
--- button's right-click, the addon list's, and /headstart menu.
function YR.WindowList()
    local out = {}
    local function Add(on, label, open) if on then out[#out + 1] = { open, label } end end
    Add(YR.AltsOn and YR.AltsOn(), "Characters: bags, bank and gold", function() YR.AltsToggle() end)
    Add(YR.QuestLFGOn and YR.QuestLFGOn(), "Quest group", function() YR.QuestLFGToggle() end)
    Add(YR.ChatLogOn and YR.ChatLogOn(), "Chat log", function() YR.ChatLogToggle() end)
    Add(YR.LootFeedOn and YR.LootFeedOn(), "Loot log", function() YR.LootLogToggle() end)
    Add(YR.Option("instanceTrack"), "Instances", function() YR:ShowSettingsTab("instances") end)
    Add(YR.Option("deathRecap"), "The last time you died", function() YR.RecapShow() end)
    Add(true, "Settings", function() YR:ToggleSettings() end)
    Add(true, "Welcome: what do you want of Headstart", function() if YR.LoadWindow() then YR.WelcomeShow() end end)
    return out
end

function YR.WindowMenu(anchor)
    YR.Style.OpenMenu(anchor or UIParent, YR.WindowList(), function(open) open() end, 260)
end

--- The button, at the login: made only when it is to be shown (turned off, there is no button at all
--- until it is turned on again).
function YR:BuildMinimapButton()
    if button or not Minimap or not YR.Option("minimapButton") then return end
    YR:ShowMinimapButton(true)
end

function YR:ShowMinimapButton(on)
    YippRouteDB.minimapButton = on
    if on and not button and Minimap then Build() end
    if button then button:SetShown(on) end
end
