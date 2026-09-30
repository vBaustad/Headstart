-- The rest of the UI that "Copy this layout" saves and "Set up layout" restores: the Edit Mode layout,
-- which extra action bars are shown, a list of game settings, and the RestedXP guide to start on.
-- Edit Mode and the action bar settings are Blizzard UI code called from an addon, which can taint
-- them until the next /reload - so Set up layout ends by asking for one.
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
}

-- The RestedXP guide a new character starts on: YippRoute's launch opener for its starting zone.
local GUIDE_GROUP = "YippRoute Launch (A)"
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
    return ui
end

-- Select the saved layout by name; if this account doesn't have it (a character layout on the main,
-- or a fresh install), import it as an account layout, as Edit Mode's own Import does.
local function ApplyLayout(layout)
    local layouts, em = EditModeLayouts()
    if not (layout and layouts) then return "no layout saved" end
    for index, info in ipairs(layouts) do
        if info.layoutName == layout.name and info.layoutType ~= Enum.EditModeLayoutType.Character then
            if em:IsLayoutSelected(index) then return "'" .. layout.name .. "' (already active)" end
            em:SelectLayout(index)
            return "'" .. layout.name .. "'"
        end
    end
    if layout.type == Enum.EditModeLayoutType.Preset then return "preset '" .. tostring(layout.name) .. "' not found" end
    local info = layout.export and C_EditMode.ConvertStringToLayoutInfo(layout.export)
    if not info then return "couldn't import '" .. tostring(layout.name) .. "'" end
    em:MakeNewLayout(info, Enum.EditModeLayoutType.Account, layout.name, true)
    return "'" .. layout.name .. "' (imported as an account layout)"
end

local function ApplyGuide()
    local rxp = RXP
    if not (rxp and rxp.LoadGuideTable and rxp.GetGuideTable) then return "RestedXP not loaded" end
    local _, race = UnitRace("player")
    local guide = GUIDE_FOR_RACE[race]
    if not guide then return "no YippRoute opener for this race" end
    local name = rxp.affix and guide:gsub("^(%d)-(%d%d?)", rxp.affix) or guide
    if not rxp.GetGuideTable(GUIDE_GROUP, name) then return "guide '" .. guide .. "' not found" end
    local ok = pcall(rxp.LoadGuideTable, rxp, GUIDE_GROUP, name)
    return ok and ("'" .. guide .. "'") or "RestedXP refused the guide"
end

-- Changing Edit Mode and the bar settings from an addon taints the action bars until the next reload:
-- until then, hovering a button in combat trips ADDON_ACTION_BLOCKED. So Set up layout ends with a
-- Reload button rather than a line in chat that is easy to miss.
StaticPopupDialogs["YIPPSETUP_RELOAD"] = {
    text = "YippRoute: reload the UI to finish setting up the layout.",
    button1 = "Reload",
    button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function YS:ApplyUI(ui)
    if not ui then
        YS.Print(("RestedXP guide: %s. No Edit Mode layout, bars or settings saved yet: log in on your main once.")
            :format(ApplyGuide()))
        return
    end
    local set, bars = 0, 0
    local suite = FirstLoaded(UI_SUITES)
    local barAddon = suite or FirstLoaded(BAR_ADDONS)
    for name, v in pairs(ui.cvars or {}) do
        if C_CVar.GetCVar(name) ~= nil and C_CVar.GetCVar(name) ~= v and pcall(C_CVar.SetCVar, name, v) then
            set = set + 1
        end
    end
    if not barAddon then
        for bar, shown in pairs(ui.bars or {}) do
            local key = "PROXY_SHOW_ACTIONBAR_" .. bar
            local ok, cur = pcall(Settings.GetValue, key)
            if ok and cur ~= shown and pcall(Settings.SetValue, key, shown) then bars = bars + 1 end
        end
    end
    local layout = suite and ("left to " .. suite) or ApplyLayout(ui.layout)
    local barText = barAddon and ("left to " .. barAddon) or tostring(bars) .. " changed"
    YS.Print(("Edit Mode: %s. Blizzard action bars: %s. Game settings changed: %d. RestedXP guide: %s.")
        :format(layout, barText, set, ApplyGuide()))
    -- only Edit Mode and the bar settings are Blizzard UI an addon can taint: no reload needed without them
    if not suite or not barAddon then
        YS.Print("reload to finish: until then the action bars can be blocked in combat.")
        StaticPopup_Show("YIPPSETUP_RELOAD")
    end
end
