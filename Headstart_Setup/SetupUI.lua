-- The rest of the UI that "Copy this layout" saves and "Set up layout" restores: the Edit Mode layout,
-- which extra action bars are shown, a list of game settings, and the RestedXP guide to start on.
-- Edit Mode and the action bars are switched through the game's own functions (C_EditMode,
-- SetActionBarToggles), not Blizzard's Lua around them: the game then announces the change and
-- Blizzard's code applies it untainted, so no /reload is needed. Each is checked a moment later; if
-- it didn't take, the old way (Blizzard's Edit Mode code, which taints until a reload) runs and the
-- reload popup asks for one. Also copied: the chat windows (tabs, channels, colours, transparency,
-- size, position) and the camera distance.
-- (part of the Headstart_Setup addon, loaded by Headstart while Character setup is on: an addon of its
-- own has a table of its own, so Headstart's is taken from HeadstartNS)
local YR = _G.HeadstartNS
YR.Setup = YR.Setup or {}
local YS = YR.Setup

-- Game settings (CVars) copied from the main when they exist in this client. Add names here.
local CVARS = {
    "autoLootDefault", "lootUnderMouse", "autoSelfCast", "interactOnLeftClick", "deselectOnClick",
    "autoQuestWatch", "autoQuestProgress", "ActionButtonUseKeyDown", "lockActionBars", "alwaysShowActionBars",
    "countdownForCooldowns", "showTargetOfTarget", "SoftTargetInteract", "autoDismountFlying",
    "UnitNameOwn", "UnitNameNPC", "nameplateShowEnemies", "nameplateShowFriends", "statusText",
    "statusTextDisplay", "cameraDistanceMaxZoomFactor", "showTutorials", "enableFloatingCombatText",
    "chatStyle", "chatMouseScroll", "chatClassColorOverride", "whisperMode", "showTimestamps", "removeChatDelay",
    -- Raid and party frames: every display option Blizzard's raid frames read (the CVar table in
    -- Blizzard_CompactUnitFrameProfiles.lua) - class colours, power bars, buffs and debuffs, dispel
    -- indicators, health text and colours, pets, main tanks. Their size, groups and sorting are Edit
    -- Mode's, which is copied with the layout.
    "raidFramesDisplayClassColor", "raidFramesDisplayPowerBars", "raidFramesDisplayOnlyHealerPowerBars",
    "raidFramesDisplayIncomingHeals", "raidFramesDisplayAggroHighlight", "raidFramesHealthBarColor",
    "raidFramesHealthBarColorBG", "raidFramesHealthText", "raidFramesDisplayBuffs", "raidFramesDisplayDebuffs",
    "raidFramesDisplayOnlyDispellableDebuffs", "raidFramesDisplayLargerRoleSpecificDebuffs",
    "raidFramesDispelIndicatorType", "raidFramesDispelIndicatorOverlay", "raidFramesDispelIndicatorOverlayAnimation",
    "raidFramesDispelIndicatorAnimatedBorder", "raidFramesCenterBigDefensive", "raidOptionDisplayPets",
    "raidOptionDisplayMainTankAndAssist", "raidOptionIsShown",
    -- The same for battleground frames.
    "pvpFramesDisplayClassColor", "pvpFramesDisplayPowerBars", "pvpFramesDisplayOnlyHealerPowerBars",
    "pvpFramesHealthText", "pvpOptionDisplayPets",
    -- Coordinates on the minimap and the world map (the same Interface settings page).
    "minimapShowPlayerCoords", "worldMapShowPlayerCoords", "worldMapShowCursorCoords", "coordsByTenths",
    -- The game's own damage meter: on or off, and whether it resets in a new instance (Options, Advanced).
    -- Where it sits and how large it is are Edit Mode's.
    "damageMeterEnabled", "damageMeterResetOnNewInstance",
    -- The other Edit Mode parts with their own on/off switch (shouldEnableCVarName in EditModeManager.xml).
    -- The game keeps these per character, so a new character starts with them off whatever the layout
    -- says: the swing timer, the cooldown viewer, encounter warnings, external defensives. Their size and
    -- place are Edit Mode's. (The Personal Resource Display's switch is the class's: CLASS_CVARS.)
    "cooldownViewerEnabled", "combatWarningsEnabled", "externalDefensivesEnabled",
}
-- Settings kept per class, not for the account (Setup.lua, YS.SaveClassUI): whether the Personal
-- Resource Display is on (the user, 2026-10-10: "vi lagrer basert på class"). Per character in the game.
local CLASS_CVARS = { "nameplateShowSelf", "showSwingTimer" }       -- and the swing timer (same day)
YS.CLASS_CVARS = CLASS_CVARS
local IS_CLASS_CVAR = {}
for _, name in ipairs(CLASS_CVARS) do IS_CLASS_CVAR[name] = true end

-- The RestedXP guide a new character starts on: Headstart's launch opener for its starting zone.
local GUIDE_GROUP = "Headstart Launch (A)"
local GUIDE_FOR_RACE = {
    Human = "1-6 Northshire (Launch)",
    NightElf = "1-6 Shadowglen (Launch)",
    Dwarf = "1-5 Coldridge Valley (Launch)",
    Gnome = "1-5 Coldridge Valley (Launch)",
}

-- Other UI addons. Action slots are the game's own and every bar addon (Bartender, Dominos, ElvUI,
-- EllesmereUI ...) draws from them, so spells and macros placed in slots show on their bars too.
-- What they own is the rest: a UI suite positions the frames itself (so Edit Mode is its business),
-- and a bar addon hides Blizzard's bars on purpose (so their show/hide settings are too).
local UI_SUITES = { "ElvUI", "EllesmereUI", "Tukui", "NDui", "ShestakUI", "RealUI", "AzeriteUI", "KkthnxUI",
    "GW2_UI", "SpartanUI", "LUI" }
local BAR_ADDONS = { "Bartender4", "Dominos", "ConsolePort" }

-- The first of these addons that is loaded (a name or any addon whose name starts with it, for
-- suites that come in modules like EllesmereUI_ActionBars).
local function FirstLoaded(names)
    local api = C_AddOns
    if not (api and api.GetNumAddOns and api.GetAddOnInfo and api.IsAddOnLoaded) then return nil end
    for i = 1, api.GetNumAddOns() do
        local name = api.GetAddOnInfo(i)
        if name and api.IsAddOnLoaded(i) then
            for _, want in ipairs(names) do
                if name == want or name:sub(1, #want) == want then return want end
            end
        end
    end
end

local function EditModeLayouts()
    local em = EditModeManagerFrame
    return em and em.layoutInfo and em.layoutInfo.layouts, em
end

--------------------------------------------------------------------------------
-- RestedXP's windows: where the guide window, the arrow, and the item and target buttons are, and
-- how big. RestedXP keeps them in its settings profile, and a profile is a character's own - so a new
-- character has them back in the middle of the screen. Copied from the profile of the character you
-- copy the interface from, and written into this one's (framePositions and frameSizes: RestedXP's
-- own tables, read back by its own LoadFramePositions). Nothing else of RestedXP's settings is touched.
--------------------------------------------------------------------------------
local function Deep(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = Deep(v) end
    return c
end

-- RestedXP keeps its settings per character. How its windows look goes along with where they are: the
-- theme (Headstart's RestedXP skin is one), the scales, the font size, the text colours, which way the
-- window grows. What a character plays by (hardcore, season, professions, quest choices, automation)
-- is that character's and is never copied.
local RXP_LOOK = { "activeTheme", "customTheme", "windowScale", "arrowScale", "arrowText", "guideFontSize",
    "activeItemsScale", "activeTargetScale", "anchorOrientation", "hideGuideWindow", "enableV2Interface", "enableV2MenuTheme",
    "activePartyStepsV2WindowScale", "worldMapPinScale", "levelSplitsFontSize", "levelSplitsOpacity",
    "textEnemyColor", "textFriendlyColor", "textLootColor", "textWarnColor", "textPickColor", "textBuyColor" }

local function RXPProfile()
    local rxp = _G.RXP
    local settings = type(rxp) == "table" and rxp.settings
    local profile = type(settings) == "table" and settings.profile
    if type(profile) ~= "table" then return nil end
    return profile, settings
end

--- RestedXP's window places and sizes as they are now, or nil (RestedXP not loaded, or nothing placed).
-- What a saved interface holds has grown. One saved by an older Headstart lacks the newer parts, and
-- only the character it came from can add them: YS.UIStale says so, for the window and for Apply.
-- 2: whether the damage meter is on, and RestedXP's look.
-- 3: the on/off switches of the swing timer, cooldown viewer, encounter warnings, external defensives.
YS.UI_VERSION = 3
function YS.UIStale(ui)
    return type(ui) == "table" and (ui.v or 1) < YS.UI_VERSION
end

function YS.ScanRXP()
    local profile, settings = RXPProfile()
    if not profile then return nil end
    if settings.SaveFramePositions then pcall(settings.SaveFramePositions, settings) end       -- as they are this moment
    local look = {}
    for _, key in ipairs(RXP_LOOK) do
        if profile[key] ~= nil then look[key] = Deep(profile[key]) end
    end
    local placed = type(profile.framePositions) == "table" and next(profile.framePositions) ~= nil
    if not placed and not next(look) then return nil end
    return { positions = placed and Deep(profile.framePositions) or nil, sizes = placed and Deep(profile.frameSizes or {}) or nil,
        look = look }
end

--- The saved places put on this character's RestedXP. Returns what happened, in words.
function YS.ApplyRXP(saved)
    if type(saved) ~= "table" or (type(saved.positions) ~= "table" and type(saved.look) ~= "table") then return "none saved" end
    local profile, settings = RXPProfile()
    if not profile then return "RestedXP not loaded" end
    -- the look first: the scales are put on with the places (LoadFramePositions ends with LoadScales)
    local theme = profile.activeTheme
    local looks = 0
    for _, key in ipairs(RXP_LOOK) do
        local v = saved.look and saved.look[key]
        if v ~= nil then profile[key] = Deep(v) looks = looks + 1 end
    end
    profile.framePositions = type(profile.framePositions) == "table" and profile.framePositions or {}
    profile.frameSizes = type(profile.frameSizes) == "table" and profile.frameSizes or {}
    local n = 0
    for name, points in pairs(saved.positions or {}) do
        profile.framePositions[name] = Deep(points)
        n = n + 1
    end
    for name, size in pairs(saved.sizes or {}) do profile.frameSizes[name] = Deep(size) end
    if settings.LoadFramePositions then pcall(settings.LoadFramePositions, settings) end
    -- another theme than this character had: drawn now (one of Headstart's two goes through its skin)
    if profile.activeTheme ~= theme then
        local mode = YR.RXPSkinMode and YR.RXPSkinMode() or "off"
        if mode ~= "off" and YR.SetRXPSkin then
            pcall(YR.SetRXPSkin, mode)
        else
            local rxp = _G.RXP
            if type(rxp.LoadActiveTheme) == "function" then pcall(rxp.LoadActiveTheme, rxp) end
            if type(rxp.ReloadGuide) == "function" then pcall(rxp.ReloadGuide, rxp, true) end
        end
    end
    return looks > 0 and ("%d placed, look copied"):format(n) or ("%d placed"):format(n)
end

function YS:ScanUI()
    local ui = { cvars = {}, bars = {}, rxp = YS.ScanRXP(), v = YS.UI_VERSION }
    local em = EditModeManagerFrame
    local active = em and em.GetActiveLayoutInfo and em:GetActiveLayoutInfo()
    if active then
        ui.layout = { name = active.layoutName, type = active.layoutType }
        local ok, s = pcall(C_EditMode.ConvertLayoutInfoToString, active)
        if ok then ui.layout.export = s end
    end
    for bar = 2, 8 do
        local ok, v = pcall(Settings.GetValue, "PROXY_SHOW_ACTIONBAR_" .. bar)
        if ok and v ~= nil then ui.bars[bar] = v and true or false end
    end
    for _, name in ipairs(CVARS) do
        local v = C_CVar.GetCVar(name)
        if v ~= nil then ui.cvars[name] = v end
    end
    if GetCameraZoom then ui.camera = GetCameraZoom() end
    ui.chat = YS.ScanChat()
    return ui
end

--------------------------------------------------------------------------------
-- Chat windows: name, font size, background colour, transparency, locked, uninteractable, docked or where it floats, and what it
-- shows (message groups and channels). Window 2 is the Combat Log: its look and dock, not its filters.
--------------------------------------------------------------------------------

local function ChatInfo(i)
    local f = FCF_GetChatWindowInfo or GetChatWindowInfo
    if f then return f(i) end
end

local function List(t)
    local out = {}
    for _, v in ipairs(type(t) == "table" and t or {}) do out[#out + 1] = v end
    return out
end

function YS.ScanChat()
    local chat = {}
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local name, size, r, g, b, a, shown, locked, docked, uninteractable = ChatInfo(i)
        local frame = _G["ChatFrame" .. i]
        if frame and name and name ~= "" and (shown or docked or i == 1) then
            -- r, g, b, a: the window's background (right-click its tab, Background), which the tab follows
            local w = { id = i, name = name, size = size, r = r, g = g, b = b, a = a, locked = locked and true or false,
                uninteractable = uninteractable and true or false,
                docked = (docked or i == 1) and true or false, groups = List(frame.messageTypeList),
                channels = List(frame.channelList) }
            if i == 1 or not docked then
                local point, _, relPoint, x, y = frame:GetPoint(1)
                if point then w.point = { point, relPoint, x, y } end
                w.width, w.height = frame:GetWidth(), frame:GetHeight()
            end
            chat[#chat + 1] = w
        end
    end
    return chat
end

local function AddAll(frame, list, add, clear)
    if frame[clear] then frame[clear](frame) end
    for _, v in ipairs(list or {}) do
        if frame[add] then frame[add](frame, v) end
    end
end

local function ChatWindow(w)
    if w.id <= 2 then return _G["ChatFrame" .. w.id] end
    for i = 3, NUM_CHAT_WINDOWS or 10 do        -- already there (set up before): the same window again
        local name, _, _, _, _, _, shown, _, docked = ChatInfo(i)
        if name == w.name and (shown or docked) then return _G["ChatFrame" .. i] end
    end
    return FCF_OpenNewWindow and (FCF_OpenNewWindow(w.name, true))
end

local function ApplyChatWindow(w)
    local frame = ChatWindow(w)
    if not frame then return false end
    FCF_SetWindowName(frame, w.name)
    if w.r then FCF_SetWindowColor(frame, w.r, w.g, w.b) end
    if w.a then FCF_SetWindowAlpha(frame, w.a) end
    if w.size and w.size > 0 then FCF_SetChatWindowFontSize(nil, frame, w.size) end
    if FCF_SetLocked then FCF_SetLocked(frame, w.locked) end
    if FCF_SetUninteractable and w.uninteractable ~= nil then FCF_SetUninteractable(frame, w.uninteractable) end
    if w.id ~= 2 then
        AddAll(frame, w.groups, "AddMessageGroup", "RemoveAllMessageGroups")
        AddAll(frame, w.channels, "AddChannel", "RemoveAllChannels")
    end
    if w.docked and w.id ~= 1 then
        if not frame.isDocked then FCF_DockFrame(frame, #FCFDock_GetChatFrames(GENERAL_CHAT_DOCK) + 1) end
    elseif w.id ~= 1 and frame.isDocked then
        FCF_UnDockFrame(frame)
        frame:Show()
    end
    if w.point and (w.id == 1 or not w.docked) then
        frame:ClearAllPoints()
        frame:SetPoint(w.point[1], UIParent, w.point[2], w.point[3], w.point[4])
        if w.width and w.height then frame:SetSize(w.width, w.height) end
        FCF_SavePositionAndDimensions(frame)
    end
    return true
end

-- The main's windows on this character; windows this character has that the main doesn't, closed.
function YS.ApplyChat(chat)
    if not (chat and #chat > 0 and FCF_SetWindowName and FCF_DockFrame) then return "nothing saved" end
    if InCombatLockdown() then return "not in combat" end
    local done, keep = 0, {}
    for _, w in ipairs(chat) do
        local ok, applied = pcall(ApplyChatWindow, w)
        if ok and applied then done = done + 1 end
        keep[w.name] = true
    end
    for i = 3, NUM_CHAT_WINDOWS or 10 do
        local name, _, _, _, _, _, shown, _, docked = ChatInfo(i)
        if name and name ~= "" and (shown or docked) and not keep[name] and FCF_Close then
            pcall(FCF_Close, _G["ChatFrame" .. i])
        end
    end
    if FCF_SelectDockFrame and DEFAULT_CHAT_FRAME then pcall(FCF_SelectDockFrame, DEFAULT_CHAT_FRAME) end
    return done .. " windows"
end

-- The camera as far out as on the main (a new character starts close in). GetCameraZoom is yards.
function YS.ApplyCamera(z)
    if not (z and GetCameraZoom and CameraZoomOut and CameraZoomIn) then return false end
    local cur = GetCameraZoom()
    if z > cur + 0.5 then CameraZoomOut(z - cur) elseif z < cur - 0.5 then CameraZoomIn(cur - z) end
    return true
end

-- Select the saved layout by name; if this account doesn't have it (a character layout on the main,
-- or a fresh install), import it as an account layout, as Edit Mode's own Import does.
local function ApplyLayout(layout)
    local layouts, em = EditModeLayouts()
    if not (layout and layouts) then return "no layout saved" end
    for index, info in ipairs(layouts) do
        if info.layoutName == layout.name and info.layoutType ~= Enum.EditModeLayoutType.Character then
            if em:IsLayoutSelected(index) then return "'" .. layout.name .. "' (already active)", false end
            em:SelectLayout(index)
            return "'" .. layout.name .. "'", true
        end
    end
    if layout.type == Enum.EditModeLayoutType.Preset then return "preset '" .. tostring(layout.name) .. "' not found" end
    local info = layout.export and C_EditMode.ConvertStringToLayoutInfo(layout.export)
    if not info then return "couldn't import '" .. tostring(layout.name) .. "'" end
    em:MakeNewLayout(info, Enum.EditModeLayoutType.Account, layout.name, true)
    return "'" .. layout.name .. "' (imported as an account layout)", true
end

-- The same through the game's own functions only (see the top of the file): selecting a layout is
-- C_EditMode.SetActiveLayout, importing is what Blizzard's MakeNewLayout does, on our own copy of the
-- layout list. Returns text, changed; nil when this client lacks the functions.
local function ApplyLayoutClean(layout)
    local layouts, em = EditModeLayouts()
    local api = C_EditMode
    if not (layout and layouts and api and api.SetActiveLayout and api.SaveLayouts and api.OnLayoutAdded) then return nil end
    for index, info in ipairs(layouts) do
        if info.layoutName == layout.name and info.layoutType ~= Enum.EditModeLayoutType.Character then
            if em.layoutInfo.activeLayout == index then return "'" .. layout.name .. "' (already active)", false end
            api.SetActiveLayout(index)
            return "'" .. layout.name .. "'", true
        end
    end
    if layout.type == Enum.EditModeLayoutType.Preset then return "preset '" .. tostring(layout.name) .. "' not found", false end
    -- what Blizzard's MakeNewLayout checks first: a name it takes, and room for one more account layout
    if api.IsValidLayoutName and not api.IsValidLayoutName(layout.name) then
        return "'" .. tostring(layout.name) .. "' isn't a name Edit Mode takes", false
    end
    if em.AreLayoutsOfTypeMaxed and em.numLayouts and em:AreLayoutsOfTypeMaxed(Enum.EditModeLayoutType.Account) then
        return "no room for '" .. tostring(layout.name) .. "': this account's Edit Mode layouts are full", false
    end
    local info = layout.export and api.ConvertStringToLayoutInfo(layout.export)
    if not info then return "couldn't import '" .. tostring(layout.name) .. "'", false end
    info.layoutType, info.layoutName = Enum.EditModeLayoutType.Account, layout.name
    local copy = { activeLayout = em.layoutInfo.activeLayout, layouts = {} }
    for i, l in ipairs(layouts) do copy.layouts[i] = l end
    local highest = em.highestLayoutIndexByType and em.highestLayoutIndexByType[Enum.EditModeLayoutType.Account]
    local presets = Enum.EditModePresetLayoutsMeta and Enum.EditModePresetLayoutsMeta.NumValues or 2
    local index = highest and highest + 1 or presets + 1
    table.insert(copy.layouts, index, info)
    api.SaveLayouts(copy)
    api.OnLayoutAdded(index, true, true)
    return "'" .. layout.name .. "' (imported as an account layout)", true
end

local BAR_FRAMES = { [2] = "MultiBarBottomLeft", [3] = "MultiBarBottomRight", [4] = "MultiBarRight", [5] = "MultiBarLeft",
    [6] = "MultiBar5", [7] = "MultiBar6", [8] = "MultiBar7" }

-- Which extra bars show, through the game's SetActionBarToggles (all seven at once, as Blizzard's own
-- setting does). Returns how many changed; nil when this client lacks the functions.
local function ApplyBarsClean(want)
    if not (GetActionBarToggles and SetActionBarToggles) then return nil end
    local cur, n = { GetActionBarToggles() }, 0
    for bar = 2, 8 do
        local v = want[bar]
        if v ~= nil and (cur[bar - 1] and true or false) ~= v then cur[bar - 1], n = v, n + 1 end
    end
    if n > 0 then
        local b = {}
        for i = 1, 7 do b[i] = cur[i] and true or false end
        SetActionBarToggles(b[1], b[2], b[3], b[4], b[5], b[6], b[7])
    end
    return n
end

-- A moment later: did the layout and the bars take? A layout that didn't gets the old way and a
-- reload; a bar frame not yet shown as wanted shows after a reload.
local function CheckLater(layout, want)
    local function Check()
        -- the old way moves the action bars: never in a fight, so it waits for the fight to end
        if InCombatLockdown() then
            local wait = CreateFrame("Frame")
            wait:RegisterEvent("PLAYER_REGEN_ENABLED")
            wait:SetScript("OnEvent", function(self) self:UnregisterAllEvents() Check() end)
            return
        end
        local em = EditModeManagerFrame
        local active = em and em.GetActiveLayoutInfo and em:GetActiveLayoutInfo()
        local reload = false
        if layout and active and active.layoutName ~= layout.name then
            local text, changed = ApplyLayout(layout)
            YS.Print("Edit Mode didn't switch by itself: " .. tostring(text) .. ".")
            reload = reload or changed
        end
        for bar, shown in pairs(want or {}) do
            local frame = _G[BAR_FRAMES[bar] or ""]
            if frame and frame.IsShown and frame:IsShown() ~= shown then reload = true end
        end
        if reload then
            YS.Print("reload to finish: until then the action bars can be blocked in combat.")
            StaticPopup_Show("YIPPSETUP_RELOAD")
        end
    end
    C_Timer.After(1.5, Check)
end

local function ApplyGuide()
    local rxp = RXP
    if not (rxp and rxp.LoadGuideTable and rxp.GetGuideTable) then return "RestedXP not loaded" end
    -- the opener is a level 1 route: a character past it keeps the guide it is on
    if (UnitLevel("player") or 1) > 5 then return "left as it is (not a new character)" end
    local _, race = UnitRace("player")
    local guide = GUIDE_FOR_RACE[race]
    if not guide then return "no Headstart opener for this race" end
    local name = rxp.affix and guide:gsub("^(%d)-(%d%d?)", rxp.affix) or guide
    if not rxp.GetGuideTable(GUIDE_GROUP, name) then return "guide '" .. guide .. "' not found" end
    local ok = pcall(rxp.LoadGuideTable, rxp, GUIDE_GROUP, name)
    return ok and ("'" .. guide .. "'") or "RestedXP refused the guide"
end

-- Changing Edit Mode and the bar settings from an addon taints the action bars until the next reload:
-- until then, hovering a button in combat trips ADDON_ACTION_BLOCKED. So Set up layout ends with a
-- Reload button rather than a line in chat that is easy to miss.
StaticPopupDialogs["YIPPSETUP_RELOAD"] = {
    text = "Headstart: reload the UI to finish applying the interface.",
    button1 = "Reload",
    button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

--------------------------------------------------------------------------------
-- A profile's own interface (Layouts.lua): which Edit Mode layout is active, which extra bars show and
-- where RestedXP's windows are. Not chat, game settings or the camera - those are the account's, for a
-- new character. Put on through the game's own functions only, so switching profile needs no reload.
--------------------------------------------------------------------------------
function YS.ScanProfileUI()
    local ui = { bars = {}, rxp = YS.ScanRXP() }
    local em = EditModeManagerFrame
    local active = em and em.GetActiveLayoutInfo and em:GetActiveLayoutInfo()
    if active then
        ui.layout = { name = active.layoutName, type = active.layoutType }
        local ok, s = pcall(C_EditMode.ConvertLayoutInfoToString, active)
        if ok then ui.layout.export = s end
    end
    for bar = 2, 8 do
        local ok, v = pcall(Settings.GetValue, "PROXY_SHOW_ACTIONBAR_" .. bar)
        if ok and v ~= nil then ui.bars[bar] = v and true or false end
    end
    return ui
end

--- Returns what was done, in words (nothing: an empty text).
function YS.ApplyProfileUI(ui)
    if type(ui) ~= "table" then return "" end
    local suite = FirstLoaded(UI_SUITES)
    local barAddon = suite or FirstLoaded(BAR_ADDONS)
    local said = {}
    if ui.layout and not suite then
        local text, changed = ApplyLayoutClean(ui.layout)
        if text == nil then said[#said + 1] = "Edit Mode can't be switched from an addon on this client: pick '" .. tostring(ui.layout.name) .. "' there"
        elseif changed then said[#said + 1] = "Edit Mode " .. text end
    end
    if ui.bars and not barAddon then
        local n = ApplyBarsClean(ui.bars)
        if n and n > 0 then said[#said + 1] = ("%d bar%s shown or hidden"):format(n, n == 1 and "" or "s") end
    end
    if ui.rxp then YS.ApplyRXP(ui.rxp) end
    return table.concat(said, "; ")
end

function YS:ApplyUI(ui, o)
    o = o or YS:Options()
    if not ui then
        YS.Print(("RestedXP guide: %s. No Edit Mode layout, bars or settings saved yet: log in on your main once.")
            :format(o.guide and ApplyGuide() or "off"))
        return
    end
    local set, bars = 0, 0
    local suite = FirstLoaded(UI_SUITES)
    local barAddon = suite or FirstLoaded(BAR_ADDONS)
    -- each game setting as it was, kept beside the bars' copy for /ysetup undo
    local char = _G.YippSetupCharDB          -- this character's saved table (Setup.lua fills it at login)
    local backup = type(char) == "table" and (char.uiBackup or char.backup) or nil
    -- the account's settings, and over them the class's own (the Personal Resource Display's switch)
    local cvars = {}
    if o.settings then
        for name, v in pairs(ui.cvars or {}) do if not IS_CLASS_CVAR[name] then cvars[name] = v end end
        for name, v in pairs(YS.ClassUI and YS.ClassUI() or {}) do cvars[name] = v end
    end
    for name, v in pairs(cvars) do
        local was = C_CVar.GetCVar(name)
        if was ~= nil and was ~= v and pcall(C_CVar.SetCVar, name, v) then
            set = set + 1
            if backup then
                backup.cvars = backup.cvars or {}
                -- the first value seen is the one to go back to (a second apply mustn't overwrite it)
                if backup.cvars[name] == nil then backup.cvars[name] = was end
            end
        end
    end
    if YS.ClassUINoted then YS.ClassUINoted() end        -- put on, not changed by the player
    local barsDone = not barAddon and o.barVisibility
    local taint = false            -- the old way ran: only a reload clears it
    local cleanBars = barsDone and ApplyBarsClean(ui.bars or {})
    if cleanBars then
        bars = cleanBars
    elseif barsDone then
        for bar, shown in pairs(ui.bars or {}) do
            local key = "PROXY_SHOW_ACTIONBAR_" .. bar
            local ok, cur = pcall(Settings.GetValue, key)
            if ok and cur ~= shown and pcall(Settings.SetValue, key, shown) then bars, taint = bars + 1, true end
        end
    end
    local layout, layoutChanged, clean = "off", false, false
    if suite then layout = "left to " .. suite
    elseif o.editMode then
        layout, layoutChanged = ApplyLayoutClean(ui.layout)
        if layout then clean = true else layout, layoutChanged = ApplyLayout(ui.layout) end
        if layoutChanged and not clean then taint = true end
    end
    local chat = o.chat and YS.ApplyChat(ui.chat) or "off"
    -- chat windows are set through Blizzard's own functions, called from here: what they write on the
    -- chat frames is ours until a reload, so it ends with the same Reload question
    if o.chat and type(chat) == "string" and chat:find("windows$") then taint = true end
    if o.camera then YS.ApplyCamera(ui.camera) end
    local barText = barAddon and ("left to " .. barAddon) or (o.barVisibility and (tostring(bars) .. " changed") or "off")
    YS.Print(("Edit Mode: %s. Blizzard action bars: %s. Chat: %s. Game settings changed: %d. RestedXP guide: %s. RestedXP windows: %s.")
        :format(layout, barText, chat, set, o.guide and ApplyGuide() or "off", o.rxpFrames ~= false and YS.ApplyRXP(ui.rxp) or "off"))
    if YS.UIStale(ui) then
        YS.Print(("this interface was saved by an older Headstart: whether the damage meter is on and RestedXP's look are not in it."
            .. " Save it again on %s (Character setup, Save interface), then Apply interface here."):format(tostring(YS.UISource() or "the character it came from")))
    end
    -- the old way taints until a reload; the game's own functions don't, but get checked a moment later
    if taint then
        YS.Print("reload to finish: until then the action bars can be blocked in combat.")
        StaticPopup_Show("YIPPSETUP_RELOAD")
    elseif (clean and layoutChanged) or cleanBars then
        -- the bars are checked even when nothing changed now: set at login (EarlyBars), they may not show yet
        CheckLater(clean and layoutChanged and ui.layout or nil, cleanBars and ui.bars or nil)
    end
end

-- SetActionBarToggles only saves which bars show; Blizzard shows them when its own setting changes (a
-- reload away, since calling that from an addon taints the bars) or once at login, at SETTINGS_LOADED.
-- So on a new character's first login the main's bars are set while Headstart loads, before that:
-- Blizzard then shows them itself, and Set up layout finds them right, with nothing to reload for.
function YS.EarlyBars()
    local ui, o = YS:SharedUI(), YS:Options()
    if not (ui and ui.bars and o.barVisibility) then return end
    if FirstLoaded(UI_SUITES) or FirstLoaded(BAR_ADDONS) then return end
    return ApplyBarsClean(ui.bars)
end
