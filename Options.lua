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
--   Made by LibDBIcon (Libs/, with LibDataBroker): the button every other addon's is, so it sits
--   right in the ring, and the addons that gather minimap buttons into one place take it too. Where
--   it stands and whether it shows is kept as LibDBIcon keeps it, in YippRouteDB.minimap
--   ({ hide, minimapPos }); the angle from before (YippRouteDB.minimapAngle) is carried over once.
--   Without the library (its folder gone) a button of our own is made instead, as it was.
-- ---------------------------------------------------------------------------
local button
local LOGO = "Interface\\AddOns\\Headstart\\art\\logo"       -- Headstart's own mark (tools/make_icons.py)
-- on the library's button: the H alone. That button brings its own dark disc and ring, and a rim of
-- ours inside that ring showed every pixel the two were apart.
local MARK = "Interface\\AddOns\\Headstart\\art\\logomark"
local icons            -- LibDBIcon, once our button is its

-- What the button says under the mouse: the same lines on LibDBIcon's tooltip and on our own button's.
local function Tip(tip)
    tip:AddLine("Headstart")
    if YR.InstanceCounts and YR.Option("instanceTrack") then
        local hour, day, wait = YR.InstanceCounts()
        local perHour, perDay = YR.InstanceLimits()
        -- nothing about instances for someone who hasn't been in one today
        if day > 0 then
            tip:AddLine(("Instances: %d/%d this hour, %d/%d today%s"):format(hour, perHour, day, perDay,
                wait and ("  (next in " .. YR.InstanceClock(wait) .. ")") or ""), 0.6, 0.8, 1)
        end
    end
    -- your gold in all (Characters): here too, for where another addon draws the bag and its coins
    if YR.AltsOn and YR.AltsOn() and YippRouteDB.altsGold ~= false then
        local sum, list = YR.AltsGold()
        if #list > 1 then
            tip:AddLine(("Gold on your %d characters: %s"):format(#list, YR.AltsCoins(sum)), 1, 0.82, 0)
        end
    end
    tip:AddLine("Click: the Headstart window", 0.8, 0.8, 0.8)
    tip:AddLine("Right-click: every window of ours (characters, chat log, loot log...)", 0.8, 0.8, 0.8)
    tip:AddLine("Drag: move round the minimap", 0.8, 0.8, 0.8)
end

local function Clicked(self, which)
    if which == "RightButton" then YR.WindowMenu(self) else YR:ToggleWindow() end
end

-- The library's button. Returns whether it was made.
local function BuildWithLibrary()
    local stub = _G.LibStub
    if type(stub) ~= "table" or type(stub.GetLibrary) ~= "function" then return false end
    local broker, lib = stub:GetLibrary("LibDataBroker-1.1", true), stub:GetLibrary("LibDBIcon-1.0", true)
    if not (broker and lib) then return false end
    local db = YippRouteDB.minimap
    if type(db) ~= "table" then
        db = { minimapPos = (tonumber(YippRouteDB.minimapAngle) or 225) % 360 }
        YippRouteDB.minimap = db
    end
    db.hide = not YR.Option("minimapButton")
    local ok, object = pcall(broker.NewDataObject, broker, "Headstart", {
        type = "launcher", text = "Headstart", icon = MARK, iconCoords = { 0, 1, 0, 1 },      -- (drawn to fit: not cropped)
        OnClick = Clicked, OnTooltipShow = Tip,
    })
    if not (ok and object) then return false end
    if not pcall(lib.Register, lib, "Headstart", object, db) then return false end
    icons = lib
    button = lib.GetMinimapButton and lib:GetMinimapButton("Headstart") or true
    return true
end

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
    if BuildWithLibrary() then return end
    button = CreateFrame("Button", "HeadstartMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(LOGO)
    -- The ring's hole is not in the middle of the button: the ring is a 53-pixel texture hung from the
    -- button's top left corner, and its hole is centred 17 across and 16 down from there (by eye, in game).
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", button, "TOPLEFT", 17, -16)
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
    button:SetScript("OnClick", Clicked)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        Tip(GameTooltip)
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
    -- this class's other profiles (Character setup, loaded): one click to each
    local YS = YR.Setup
    if YS and YS.LayoutNames and YR.SetupOn and YR.SetupOn() then
        local on = YS.LayoutName()
        for _, name in ipairs(YS.LayoutNames()) do
            local to = name
            Add(name ~= on, "Profile: " .. name, function()
                local ok, why = YS.LayoutSwitch(to)
                if not ok and why then YR.Print(why) end
            end)
        end
    end
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
    if icons then
        -- the library's: it shows and hides its button, and keeps which in the table it was given
        YippRouteDB.minimap.hide = not on
        if on then icons:Show("Headstart") else icons:Hide("Headstart") end
    elseif button then
        button:SetShown(on)
    end
end
