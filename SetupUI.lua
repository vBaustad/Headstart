-- The rest of the UI that "Copy this layout" saves and "Set up layout" restores: the Edit Mode layout,
-- which extra action bars are shown, a list of game settings, and the RestedXP guide to start on.
-- Edit Mode and the action bars are switched through the game's own functions (C_EditMode,
-- SetActionBarToggles), not Blizzard's Lua around them: the game then announces the change and
-- Blizzard's code applies it untainted, so no /reload is needed. Each is checked a moment later; if
-- it didn't take, the old way (Blizzard's Edit Mode code, which taints until a reload) runs and the
-- reload popup asks for one. Also copied: the chat windows (tabs, channels, colours, transparency,
-- size, position) and the camera distance.
local _, YR = ...
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
}

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

function YS:ScanUI()
    local ui = { cvars = {}, bars = {} }
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
-- Chat windows: name, font size, colour, transparency, locked, docked or where it floats, and what it
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
        local name, size, r, g, b, a, shown, locked, docked = ChatInfo(i)
        local frame = _G["ChatFrame" .. i]
        if frame and name and name ~= "" and (shown or docked or i == 1) then
            local w = { id = i, name = name, size = size, r = r, g = g, b = b, a = a, locked = locked and true or false,
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
    C_Timer.After(1.5, function()
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
    end)
end

local function ApplyGuide()
    local rxp = RXP
    if not (rxp and rxp.LoadGuideTable and rxp.GetGuideTable) then return "RestedXP not loaded" end
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
    text = "Headstart: reload the UI to finish setting up the layout.",
    button1 = "Reload",
    button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

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
    for name, v in pairs(o.settings and ui.cvars or {}) do
        if C_CVar.GetCVar(name) ~= nil and C_CVar.GetCVar(name) ~= v and pcall(C_CVar.SetCVar, name, v) then
            set = set + 1
        end
    end
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
    if o.camera then YS.ApplyCamera(ui.camera) end
    local barText = barAddon and ("left to " .. barAddon) or (o.barVisibility and (tostring(bars) .. " changed") or "off")
    YS.Print(("Edit Mode: %s. Blizzard action bars: %s. Chat: %s. Game settings changed: %d. RestedXP guide: %s.")
        :format(layout, barText, chat, set, o.guide and ApplyGuide() or "off"))
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
    local p, o = YS:Profile(), YS:Options()
    if not (p and p.ui and p.ui.bars and o.barVisibility) then return end
    if FirstLoaded(UI_SUITES) or FirstLoaded(BAR_ADDONS) then return end
    return ApplyBarsClean(p.ui.bars)
end
