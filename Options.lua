-- The Blizzard options entry (Esc > Options > AddOns > Headstart) only points at our own window,
-- where the settings live with the rest; and the minimap button that opens that window.
local _, YR = ...

function YR:BuildOptions()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local S = YR.Style
    local panel = CreateFrame("Frame")
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

function YR:BuildMinimapButton()
    if button or not Minimap then return end
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
    button:SetScript("OnClick", function(_, which) YR:ToggleWindow(which == "RightButton" and "settings" or nil) end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Headstart")
        if YR.InstanceCounts and YR.Option("instanceTrack") then
            local hour, day, wait = YR.InstanceCounts()
            local perHour, perDay = YR.InstanceLimits()
            GameTooltip:AddLine(("Instances: %d/%d this hour, %d/%d today%s"):format(hour, perHour, day, perDay,
                wait and ("  (next in " .. YR.InstanceClock(wait) .. ")") or ""), 0.6, 0.8, 1)
        end
        GameTooltip:AddLine("Click: the Headstart window", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: settings", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: move round the minimap", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Place()
    YR:ShowMinimapButton(YR.Option("minimapButton"))
end

function YR:ShowMinimapButton(on)
    YippRouteDB.minimapButton = on
    if button then button:SetShown(on) end
end
