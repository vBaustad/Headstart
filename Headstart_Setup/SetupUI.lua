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
    -- The rest of what the Options window's own pages set (the user, 2026-10-13: "vi kan jo ta med alt"),
    -- by the names Blizzard's pages use (Blizzard_SettingsDefinitions_Frame). Not what says a help tip
    -- or a tutorial was seen, the language, the network, or the spoken combat alerts.
    -- Controls, mouse and camera:
    "autoClearAFK", "softTargettingInteractKeySound", "ClipCursor", "mouseInvertPitch", "cameraYawMoveSpeed",
    "cameraPitchMoveSpeed", "autointeract", "cameraSmoothStyle", "cameraWaterCollision", "combinedBags",
    -- Interface:
    "showInGameNavigation", "Outline", "chatBubbles", "chatBubblesParty", "chatBubblesRaid",
    "ReplaceOtherPlayerPortraits", "ReplaceMyPlayerPortrait",
    -- Combat:
    "doNotFlashLowHealthWarning", "lossOfControl", "enableMouseoverCast", "empowerTapControls",
    "spellActivationOverlayOpacity", "displaySpellActivationOverlays", "ActionButtonUseKeyHeldSpell", "softTargetEnemy",
    "findYourselfModeCircle", "findYourselfModeOutline", "findYourselfModeIcon", "findYourselfAnywhere",
    "occludedSilhouettePlayer", "assistedCombatHighlight", "assistedCombatReduceHighlights",
    -- Names and nameplates:
    "nameplateStyle", "UnitNameFriendlySpecialNPCName", "UnitNameHostleNPC", "UnitNameInteractiveNPC",
    "ShowQuestUnitCircles", "UnitNameNonCombatCreatureName", "UnitNameFriendlyPlayerName", "UnitNameFriendlyMinionName",
    "UnitNameEnemyPlayerName", "UnitNameEnemyMinionName", "nameplateShowAll", "nameplateShowEnemyMinions",
    "nameplateShowEnemyMinus", "nameplateShowFriendlyPlayers", "nameplateShowFriendlyPlayerMinions",
    "nameplateShowOnlyNameForFriendlyPlayerUnits", "nameplateUseClassColorForFriendlyPlayerUnitNames",
    "nameplateShowFriendlyRealmName", "nameplateShowFriendlyNpcs", "nameplateShowOffscreen", "nameplateStackingTypes",
    "nameplateSize", "nameplateAuraScale", "nameplateInfoDisplay", "nameplateCastBarDisplay", "nameplateThreatDisplay",
    "nameplateEnemyNpcAuraDisplay", "nameplateEnemyPlayerAuraDisplay", "nameplateFriendlyPlayerAuraDisplay",
    "nameplateDebuffPadding", "nameplateSimplifiedTypes", "nameplateShowFriendlyClassColor", "nameplateShowClassColor",
    -- Social:
    "profanityFilter", "guildMemberNotify", "blockTrades", "blockChannelInvites", "showToastOnline", "showToastOffline",
    "showToastBroadcast", "showToastFriendRequest", "showToastWindow", "autoAcceptQuickJoinRequests",
    -- Pings:
    "enablePings", "pingMode", "showPingsInChat", "showPingsOnRaidFrames",
    -- Accessibility and colour blindness, subtitles, quest text:
    "WorldTextMinSize", "enableMovePad", "CameraKeepCharacterCentered", "CameraReduceUnexpectedMovement",
    "ShakeStrengthCamera", "ShakeStrengthUI", "cursorSizePreferred", "SoftTargetTooltipEnemy", "SoftTargetTooltipInteract",
    "SoftTargetIconEnemy", "SoftTargetIconInteract", "SoftTargetIconGameObject", "SoftTargetLowPriorityIcons",
    "overrideScreenFlash", "colorblindMode", "colorblindSimulator", "colorblindWeaknessFactor",
    "movieSubtitle", "movieSubtitleBackground", "movieSubtitleBackgroundAlpha", "questTextContrast",
    -- Encounters (Options, Advanced):
    "encounterWarningsEnabled", "encounterTimelineEnabled", "encounterWarningsLevel",
    "encounterWarningsHideIfNotTargetingPlayer", "encounterTimelineHideLongCountdowns",
    "encounterTimelineHideQueuedCountdowns", "encounterTimelineHideForOtherRoles",
}
-- Settings kept per class, not for the account (Setup.lua, YS.SaveClassUI): whether the Personal
-- Resource Display is on (the user, 2026-10-10: "vi lagrer basert på class"). Per character in the game.
-- This machine's settings: graphics and sound, as the Options window has them (System: Graphics, Audio),
-- with the frame rate limits and the mouse. The game keeps them per installed client and not per
-- character, so where they were saved every character has them already; they matter on another install
-- - the live game after the beta (the user, 2026-10-13, after Apply both on a client made new: "eneste
-- jeg savner er nok graphic settings og audio settings"). Names this client hasn't got are passed over.
--   Not the monitor, the window and its resolution, the graphics card and its API, or the sound and
--   voice devices: those are the machine's own, and wrong on another.
--   In this order: the two quality presets first (setting a preset sets everything under it), then each.
--   The names are the ones Blizzard's own Graphics and Audio pages set (Blizzard_SettingsDefinitions_Shared,
--   Graphics.lua and Audio.lua), with the quality settings this client writes to its Config.wtf.
local MACHINE_CVARS = {
    "graphicsQuality", "raidGraphicsQuality", "RAIDsettingsEnabled",
    "graphicsShadowQuality", "graphicsLiquidDetail", "graphicsPBRLiquidDetail", "graphicsParticleDensity", "graphicsSSAO",
    "graphicsDepthEffects", "graphicsComputeEffects", "graphicsOutlineMode", "graphicsTextureResolution",
    "graphicsSpellDensity", "graphicsProjectedTextures", "graphicsViewDistance", "graphicsEnvironmentDetail",
    "graphicsGroundClutter", "graphicsLightMode", "graphicsBloomUserMult",
    "raidGraphicsShadowQuality", "raidGraphicsLiquidDetail", "raidGraphicsPBRLiquidDetail", "raidGraphicsParticleDensity",
    "raidGraphicsSSAO", "raidGraphicsDepthEffects", "raidGraphicsComputeEffects", "raidGraphicsOutlineMode",
    "raidGraphicsTextureResolution", "raidGraphicsSpellDensity", "raidGraphicsProjectedTextures", "raidGraphicsViewDistance",
    "raidGraphicsEnvironmentDetail", "raidGraphicsGroundClutter", "raidGraphicsLightMode", "raidGraphicsBloomUserMult",
    -- frame rate, sync, latency, anti-aliasing, render scale, sharpening, brightness, the field of view,
    -- and the size of the interface (Edit Mode's places are measured in it)
    "maxFPS", "useMaxFPS", "maxFPSBk", "useMaxFPSBk", "targetFPS", "useTargetFPS", "vsync", "LowLatencyMode",
    "ffxAntiAliasingMode", "MSAAQuality", "msaaAlphaTest", "RenderScale", "ResampleQuality", "ResampleSharpness",
    "textureFilteringMode", "shadowrt", "Gamma", "Brightness", "Contrast", "physicsLevel", "cameraFov",
    "useUiScale", "uiscale",
    -- sound: what is on, and how loud
    "Sound_EnableAllSound", "Sound_MasterVolume", "Sound_SFXVolume", "Sound_MusicVolume", "Sound_AmbienceVolume",
    "Sound_DialogVolume", "Sound_EnableSFX", "Sound_EnableMusic", "Sound_EnableAmbience", "Sound_EnableDialog",
    "Sound_EnableErrorSpeech", "Sound_EnableEmoteSounds", "Sound_EnablePetSounds", "Sound_ZoneMusicNoDelay",
    "Sound_EnableSoundWhenGameIsInBG", "Sound_EnableReverb", "Sound_EnablePositionalLowPassFilter",
    "Sound_NumChannels",
    -- the mouse
    "rawMouseEnable", "mouseSpeed", "enableMouseSpeed",
}
YS.MACHINE_CVARS = MACHINE_CVARS

local CLASS_CVARS = { "nameplateShowSelf", "showSwingTimer" }       -- and the swing timer (same day)
YS.CLASS_CVARS = CLASS_CVARS
local IS_CLASS_CVAR = {}
for _, name in ipairs(CLASS_CVARS) do IS_CLASS_CVAR[name] = true end

-- The RestedXP guide a new character starts on, by its race (YS.StartGuide): the one picked for that race
-- (YippSetupDB.raceGuide[race] = { group, name }, for the account: Character setup, Interface tab), or else
-- Headstart's opener for its starting zone where the routes are installed - the first of the race's list that
-- is for the character (the Lean ones first: the owner, 2026-10-16, "can we make Lean the default guide"; the
-- Shadowglen ones are for one class each: a Rogue's and a Druid's (the owner, 2026-10-31), so a Night Elf of
-- any other class gets the Launch one) - or else RestedXP's own free starter
-- for the race. Without one of them a new character's RestedXP was blank: RestedXP marks a default in its menu
-- (#defaultfor) but loads none by itself (the owner, 2026-10-16).
local GUIDE_GROUP = "Headstart Launch (A)"
local GUIDE_FOR_RACE = {
    Human = { "1-6 Northshire (Lean)", "1-6 Northshire (Launch)" },
    NightElf = { "1-6 Shadowglen (Lean)", "1-6 Shadowglen (Lean Druid)", "1-6 Shadowglen (Launch)" },
    Dwarf = { "1-5 Coldridge Valley (Launch)" },
    Gnome = { "1-5 Coldridge Valley (Launch)" },
}
local RXP_STARTER = {
    Human = { "RestedXP Forever Guide (A)", "1-6 Northshire" },
    NightElf = { "RestedXP Forever Guide (A)", "1-6 Shadowglen" },
    Dwarf = { "RestedXP Forever Guide (A)", "1-5 Coldridge Valley" },
    Gnome = { "RestedXP Forever Guide (A)", "1-5 Coldridge Valley" },
    Orc = { "RestedXP Forever Guide (H)", "1-6 Durotar" },
    Troll = { "RestedXP Forever Guide (H)", "1-6 Durotar" },
    Scourge = { "RestedXP Forever Guide (H)", "1-6 Tirisfal Glades" },
    Tauren = { "RestedXP Forever Guide (H)", "1-6 Mulgore" },
}
-- the races, as the game names them (UnitRace's second answer) and as the choice shows them
YS.GUIDE_RACES = { { "Human", "Human" }, { "Dwarf", "Dwarf" }, { "Gnome", "Gnome" }, { "NightElf", "Night Elf" },
    { "Orc", "Orc" }, { "Troll", "Troll" }, { "Tauren", "Tauren" }, { "Scourge", "Undead" } }
local HORDE_RACE = { Orc = true, Troll = true, Tauren = true, Scourge = true }

-- a guide RestedXP has, by its group and its name as written: the name it has there (RestedXP writes the
-- levels with its own affix, "01-06"), or nil
local function HaveGuide(group, name)
    local rxp = RXP
    if not (type(rxp) == "table" and rxp.GetGuideTable and type(group) == "string" and type(name) == "string") then return nil end
    local affixed = rxp.affix and (name:gsub("^(%d)-(%d%d?)", rxp.affix)) or name
    for _, n in ipairs({ affixed, name }) do
        local ok, guide = pcall(rxp.GetGuideTable, group, n)
        if ok and guide then return n end
    end
end

-- whether a guide RestedXP has is for the character you are on: its header's filter ("<< Alliance Rogue"),
-- read by RestedXP's own check. A guide for another class loads with every step filtered out - an empty
-- guide (the route chat, 2026-10-16: a Rogue's opener picked for Night Elves, on a Night Elf Druid).
local function ForThisCharacter(group, name)
    local rxp = RXP
    local ok, guide = pcall(rxp.GetGuideTable, group, name)
    local tag = ok and type(guide) == "table" and guide.enabledFor
    if type(tag) ~= "string" or type(rxp.applies) ~= "function" then return true end
    local fine, yes = pcall(rxp.applies, tag)
    return not fine or yes and true or false
end

--- The guide a new character of `race` starts on: its group, its name as RestedXP has it, and whose it is
--- ("picked", "headstart" or "restedxp"); nil when RestedXP has none of them. here: for the character you
--- are on - a guide that isn't for it (another class's) is passed over for the next, and the fourth answer
--- says so.
function YS.StartGuide(race, here)
    local skipped
    local function Take(group, name)
        local n = HaveGuide(group, name)
        if n and here and not ForThisCharacter(group, n) then skipped = skipped or n return nil end
        return n
    end
    local picked = YippSetupDB and type(YippSetupDB.raceGuide) == "table" and YippSetupDB.raceGuide[race]
    if type(picked) == "table" then
        local n = Take(picked[1], picked[2])
        if n then return picked[1], n, "picked" end
    end
    for _, name in ipairs(GUIDE_FOR_RACE[race] or {}) do
        local n = Take(GUIDE_GROUP, name)
        if n then return GUIDE_GROUP, n, "headstart", skipped end
    end
    local s = RXP_STARTER[race]
    local n = s and Take(s[1], s[2])
    if n then return s[1], n, "restedxp", skipped end
    return nil, nil, nil, skipped
end

-- The default for a race as the character you are on would get it: nothing picked, and a guide for other
-- classes passed over (a Rogue sees the Rogue's opener, anyone else the next).
local function DefaultGuide(race)
    local picks = YippSetupDB and type(YippSetupDB.raceGuide) == "table" and YippSetupDB.raceGuide or nil
    local was = picks and picks[race]
    if picks then picks[race] = nil end
    local g, n = YS.StartGuide(race, true)
    if picks then picks[race] = was end
    return g, n
end

--- The guides to pick from for a race: every guide RestedXP has loaded that starts at level 1, not the other
--- side's (its group says (A) or (H)), with "the default" first. { { value, label }, ... }; value
--- "group||name", or "" for the default.
function YS.StartGuideChoices(race)
    local out, seen = {}, {}
    local _, dn = DefaultGuide(race)
    out[1] = { "", dn and ("Default: " .. dn) or "Default (none loaded)" }
    local list = {}
    local rxp = RXP
    local other = HORDE_RACE[race] and "%(A%)$" or "%(H%)$"
    for _, guide in pairs(type(rxp) == "table" and type(rxp.guides) == "table" and rxp.guides or {}) do
        local group = type(guide) == "table" and type(guide.group) == "string" and guide.group:gsub("^%*", "")
        local name = type(guide) == "table" and guide.name
        if group and type(name) == "string" and name:match("^0?1%-") and not group:match(other) then
            local key = group .. "||" .. name
            if not seen[key] then
                seen[key] = true
                -- a guide for some characters only says for whom (its header's filter): it is passed over
                -- for any other, so a Rogue's opener picked for the race starts only the race's Rogues on it
                local only = type(guide.enabledFor) == "string" and guide.enabledFor:match("%S") and ("  (" .. guide.enabledFor .. " only)") or ""
                list[#list + 1] = { key, name .. only .. "  -  " .. group, group, name }
            end
        end
    end
    table.sort(list, function(a, b) if a[3] ~= b[3] then return a[3] < b[3] end return a[4] < b[4] end)
    for _, x in ipairs(list) do out[#out + 1] = { x[1], x[2] } end
    return out
end

--- One picked for a race ("" or nil: none, the default again).
function YS.PickStartGuide(race, value)
    if not (YippSetupDB and race) then return end
    YippSetupDB.raceGuide = type(YippSetupDB.raceGuide) == "table" and YippSetupDB.raceGuide or {}
    local group, name
    if type(value) == "string" then group, name = value:match("^(.-)||(.+)$") end
    YippSetupDB.raceGuide[race] = group and { group, name } or nil
end

--- What the choice shows for a race.
function YS.StartGuideLabel(race)
    local _, name, whose = YS.StartGuide(race)
    if whose == "picked" then return name end
    local _, dn = DefaultGuide(race)
    return dn and ("Default: " .. dn) or "None loaded"
end

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
-- 4: the key bindings are in it.
YS.UI_VERSION = 5          -- 5: graphics and sound are in it (ui.machine)
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

-- Key bindings: your keys as they are, action by action - keys[action] = { key1, key2 }, false where
-- it has none (a default you took off is part of how you play). Read with the game's own list of
-- actions, put on with its own SetBinding and saved as the game saves them (the set you are on: the
-- account's, unless you ticked character-specific bindings).
--   Put on in two passes: first every action that differs lets go of the keys it has, then each gets
--   the keys it should have - so a key moving from one action to another is free when it is asked for.
--   An action the saved set doesn't name (one this install has and the other hadn't) keeps its keys,
--   unless one of them is a key the saved set gives to something else.
function YS.ScanKeys()
    if not GetBinding then return nil end
    local keys, n = {}, 0
    -- (walked until the game has no more: how many there are is not asked for by a name of its own -
    -- GetBinding(index) is what this client's own settings page uses, and nothing else is leaned on)
    for i = 1, 3000 do
        local ok, action, _, k1, k2 = pcall(GetBinding, i)
        if not ok or action == nil then break end
        if type(action) == "string" and not action:find("^HEADER_") then
            keys[action] = { k1 or false, k2 or false }
            n = n + 1
        end
    end
    return n > 0 and keys or nil
end

--- The saved keys put on, a few at a time (each key set has the game tell every action button): YS.KeysJob
--- makes the job, YS.KeysStep sets at most `most` keys of it (an action at a time, so a little over) and is true
--- once it is all on and saved.
---   One action at a time: the keys it has let go and the ones it should have set together. A key set takes it from
---   whatever had it, so the order doesn't matter - and a fight between two frames leaves every action with keys,
---   old or new (the two passes - every key let go, then every key set - left them with none until it ended).
--- backup: where the keys as they were are kept for /ysetup undo (the first time only). KeysJob is nil where it
--- can't be done (a fight, no keys saved).
function YS.KeysJob(keys, backup)
    if type(keys) ~= "table" or not (SetBinding and GetBindingKey and SaveBindings) then return nil end
    if InCombatLockdown() then return nil end
    local k = { keys = keys, backup = backup, was = backup and backup.keys == nil and YS.ScanKeys() or nil,
        list = {}, i = 1, changed = 0, done = {} }
    for action, want in pairs(keys) do
        if type(action) == "string" and type(want) == "table" then k.list[#k.list + 1] = action end
    end
    return k
end
-- One action's keys put on: the ones it has let go, the ones it should have set. An action of the job a key is taken
-- from is put on at once too (two keys swapped: neither is left without one between two frames). Returns the keys set.
local function PutKeys(k, action)
    k.done[action] = true
    local want = k.keys[action]
    local k1, k2 = GetBindingKey(action)        -- (as it is now: a key taken by an action before is not its)
    if (k1 or false) == (want[1] or false) and (k2 or false) == (want[2] or false) then return 0 end
    local n, robbed = 0, {}
    if k1 then SetBinding(k1) n = n + 1 end
    if k2 then SetBinding(k2) n = n + 1 end
    for i = 1, 2 do
        local key = want[i]
        if type(key) == "string" then
            local had = GetBindingAction and GetBindingAction(key)
            if type(had) == "string" and had ~= action and k.keys[had] and not k.done[had] then robbed[#robbed + 1] = had end
            SetBinding(key, action)
            n = n + 1
        end
    end
    k.changed = k.changed + 1
    for _, other in ipairs(robbed) do
        if not k.done[other] then n = n + PutKeys(k, other) end
    end
    return n
end
function YS.KeysStep(k, most)
    local n = 0
    while k.i <= #k.list and n < most do
        local action = k.list[k.i]
        k.i = k.i + 1
        if not k.done[action] then n = n + PutKeys(k, action) end
    end
    if k.i <= #k.list then return false end
    if k.changed > 0 and not k.saved then
        k.saved = true
        pcall(SaveBindings, GetCurrentBindingSet and GetCurrentBindingSet() or 1)
        if k.backup and k.was then k.backup.keys = k.was end
    end
    return true
end
--- All of it at once. Returns how many actions changed, or nil where it can't be done.
function YS.ApplyKeys(keys, backup)
    local k = YS.KeysJob(keys, backup)
    if not k then return nil end
    while not YS.KeysStep(k, math.huge) do end
    return k.changed
end

function YS:ScanUI()
    local ui = { cvars = {}, bars = {}, rxp = YS.ScanRXP(), v = YS.UI_VERSION, keys = YS.ScanKeys() }
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
    ui.machine = {}
    for _, name in ipairs(MACHINE_CVARS) do
        local v = C_CVar.GetCVar(name)
        if v ~= nil then ui.machine[name] = v end
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

-- A chat window's list of groups or channels, whole. Blizzard takes a channel out by setting its
-- entry to nil (leaving a city takes Trade out), which leaves a hole: read to the first hole, the
-- channels after it were lost - and that was then saved, and put on every character. In order.
local function List(t)
    local out, keys = {}, {}
    for k, v in pairs(type(t) == "table" and t or {}) do
        if type(k) == "number" and v ~= nil then keys[#keys + 1] = k end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do out[#out + 1] = t[k] end
    return out
end

-- The channels a chat window shows. Its own list (frame.channelList) loses a channel as you leave it:
-- walk out of a city and Trade is gone from it, and saved there, Trade was taken out of the chat of
-- every character the interface was put on. The game keeps a list of its own for each window
-- (GetChatWindowChannels: name, zone, name, zone... - what Blizzard's chat frame fills its list from
-- at the login), so that is read too, and a channel in either is saved.
local function AddNames(out, has, ...)
    for k = 1, select("#", ...), 2 do
        local name = select(k, ...)
        if type(name) == "string" and name ~= "" and not has[name] then
            has[name] = true
            out[#out + 1] = name
        end
    end
end

local function Channels(frame, i)
    local out, has = {}, {}
    if GetChatWindowChannels then AddNames(out, has, GetChatWindowChannels(i)) end
    for _, name in ipairs(List(frame.channelList)) do AddNames(out, has, name) end
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
                channels = Channels(frame, i) }
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
            if YR.TaintNoted then YR.TaintNoted("Character setup changed which bars show (a reload clears it)") end
            StaticPopup_Show("YIPPSETUP_RELOAD")
        end
    end
    C_Timer.After(1.5, Check)
end

--- The levelling guide addon in use: "RestedXP" (its guides are started from here, Headstart's routes run in it),
--- "Polestar" (it opens with a guide for the race, class, level and zone by itself, so there is nothing to start), or
--- nil. Both loaded: RestedXP, the one this can start a guide in.
function YS.GuideAddon()
    local rxp = RXP
    if rxp and rxp.LoadGuideTable and rxp.GetGuideTable then return "RestedXP" end
    if FirstLoaded({ "Polestar" }) then return "Polestar" end
end

local function ApplyGuide()
    local rxp = RXP
    if YS.GuideAddon() ~= "RestedXP" then
        return YS.GuideAddon() == "Polestar" and "Polestar (it picks the guide itself)" or "no guide addon loaded (RestedXP or Polestar)"
    end
    -- the opener is a level 1 route: a character past it keeps the guide it is on
    if (UnitLevel("player") or 1) > 5 then return "left as it is (not a new character)" end
    local _, race = UnitRace("player")
    local group, name, _, skipped = YS.StartGuide(race, true)
    if not group then
        return skipped and ("'" .. skipped .. "' isn't for this class, and there is no other starting guide") or "no starting guide for this race in RestedXP"
    end
    local ok = pcall(rxp.LoadGuideTable, rxp, group, name)
    if not ok then return "RestedXP refused the guide" end
    return "RestedXP '" .. name .. "'" .. (skipped and (" (the one picked for the race, '" .. skipped .. "', isn't for this class)") or "")
end

--- A character's screen about to be saved into its interface: the parts Apply never put on this
--- character (its switch is off, or a UI suite or bar addon has that part) stay as they are saved.
--- Without this a character with Chat windows off saved its own chat as everybody's.
function YS.KeepUnapplied(ui, saved, o)
    if type(ui) ~= "table" or type(saved) ~= "table" then return ui end
    o = o or YS:Options()
    local suite = FirstLoaded(UI_SUITES)
    local barAddon = suite or FirstLoaded(BAR_ADDONS)
    if not o.settings then ui.cvars = saved.cvars end
    if not o.editMode or suite then ui.layout = saved.layout end
    if not o.barVisibility or barAddon then ui.bars = saved.bars end
    if not o.chat then ui.chat = saved.chat end
    if not o.camera then ui.camera = saved.camera end
    if o.rxpFrames == false then ui.rxp = saved.rxp end
    if o.graphics == false then ui.machine = saved.machine end
    if o.keys == false then ui.keys = saved.keys end        -- (its switch off: this character's keys are not everybody's)
    return ui
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

--- The interface put on, as steps (Setup.lua's job runner runs them a frame each): the game settings
--- CVAR_BATCH a frame, then graphics and sound, the bars that show, Edit Mode, chat and the camera, your keys
--- KEY_BATCH a frame, RestedXP, and what was done said in chat. YS:ApplyUI: all of them at once.
local CVAR_BATCH, KEY_BATCH = 25, 30
--- The interface's steps for a job (Setup.lua). login: a new character set up as it logs in - a part the game puts
--- its own on a moment in (chat windows, key bindings, Edit Mode's layouts) waits for that, or it would be written over.
function YS.UISteps(ui, o, login)
    o = o or YS:Options()
    if not ui then
        return { function()
            YS.Print(("Levelling guide: %s. No Edit Mode layout, bars or settings saved yet: log in on your main once.")
                :format(o.guide and ApplyGuide() or "off"))
            return true
        end }
    end
    local u = { set = 0, bars = 0, c = 1, layout = "off", chat = "off", keys = "off", taint = false }
    local suite = FirstLoaded(UI_SUITES)
    local barAddon = suite or FirstLoaded(BAR_ADDONS)
    -- each game setting as it was, kept beside the bars' copy for /ysetup undo
    local char = _G.YippSetupCharDB          -- this character's saved table (Setup.lua fills it at login)
    local backup = type(char) == "table" and (char.uiBackup or char.backup) or nil
    if type(char) == "table" then char.uiTouched = true end     -- (Put back everything: its own goes back on)
    -- the account's settings, and over them the class's own (the Personal Resource Display's switch, the
    -- swing timer) - those only the first time an interface goes on here: a new character starts from its
    -- class, and after that they are its own. The game keeps them per character, and the class's put on
    -- again at every change taken from elsewhere undid a choice made here (the owner, 2026-10-15).
    local cvars = {}
    if o.settings then
        for name, v in pairs(ui.cvars or {}) do if not IS_CLASS_CVAR[name] then cvars[name] = v end end
        if not (type(char) == "table" and char.classUI) then
            for name, v in pairs(YS.ClassUI and YS.ClassUI() or {}) do cvars[name] = v end
            if type(char) == "table" then char.classUI = true end
        end
    end
    local names = {}
    for name in pairs(cvars) do names[#names + 1] = name end
    local steps = {}
    steps[#steps + 1] = function()
        local n = 0
        while u.c <= #names and n < CVAR_BATCH do
            local name = names[u.c]
            local v = cvars[name]
            u.c = u.c + 1
            local was = C_CVar.GetCVar(name)
            if was ~= nil and was ~= v and pcall(C_CVar.SetCVar, name, v) then
                u.set, n = u.set + 1, n + 1
                if backup then
                    backup.cvars = backup.cvars or {}
                    -- the first value seen is the one to go back to (a second apply mustn't overwrite it)
                    if backup.cvars[name] == nil then backup.cvars[name] = was end
                end
            end
        end
        if u.c <= #names then return false end
        if YS.ClassUINoted then YS.ClassUINoted() end        -- put on, not changed by the player
        return true
    end
    -- Graphics and sound. What each is now is read before anything is set: a quality preset sets what
    -- is under it, and what undo goes back to is what you had, not what the preset made of it.
    steps[#steps + 1] = function()
        if not (o.graphics ~= false and type(ui.machine) == "table") then return true end
        u.machine = 0
        local had, touched = {}, false
        for _, name in ipairs(MACHINE_CVARS) do had[name] = C_CVar.GetCVar(name) end
        for _, name in ipairs(MACHINE_CVARS) do
            local v, was = ui.machine[name], had[name]
            if v ~= nil and was ~= nil then
                -- (asked again: a preset set a moment ago may have put it right already)
                local ok = C_CVar.GetCVar(name) == v
                if not ok then
                    ok = pcall(C_CVar.SetCVar, name, v)
                    touched = touched or ok
                end
                if ok and was ~= v then u.machine = u.machine + 1 end
            end
        end
        -- kept for /ysetup undo: all of them as they were, not only those that differ - a preset put
        -- back sets what is under it again, and each has to be put back after it (Setup.lua, PutBack)
        if touched and backup then
            backup.cvars = backup.cvars or {}
            for _, name in ipairs(MACHINE_CVARS) do
                if had[name] ~= nil and backup.cvars[name] == nil then backup.cvars[name] = had[name] end
            end
        end
        return true
    end
    local barsDone = not barAddon and o.barVisibility
    steps[#steps + 1] = function()
        u.cleanBars = barsDone and ApplyBarsClean(ui.bars or {})
        if u.cleanBars then
            u.bars = u.cleanBars
        elseif barsDone then
            for bar, shown in pairs(ui.bars or {}) do
                local key = "PROXY_SHOW_ACTIONBAR_" .. bar
                local ok, cur = pcall(Settings.GetValue, key)
                if ok and cur ~= shown and pcall(Settings.SetValue, key, shown) then u.bars, u.taint = u.bars + 1, true end
            end
        end
        return true
    end
    steps[#steps + 1] = function()
        if login and not suite and o.editMode and not EditModeLayouts() and not YS.Ready() then return "wait" end
        if suite then u.layout = "left to " .. suite
        elseif o.editMode then
            u.layout, u.layoutChanged = ApplyLayoutClean(ui.layout)
            if u.layout then u.clean = true else u.layout, u.layoutChanged = ApplyLayout(ui.layout) end
            if u.layoutChanged and not u.clean then u.taint = true end
        end
        return true
    end
    -- the windows as they are saved already (a change made elsewhere that wasn't to chat): left alone - put
    -- on again, they would ask for a reload for nothing
    steps[#steps + 1] = function()
        if login and o.chat and not YS.Ready("chat") then return "wait" end
        if o.chat then
            local same = type(ui.chat) == "table" and YS.UISig and YS.UISig(YS.ScanChat()) == YS.UISig(ui.chat)
            u.chat = same and "as saved" or YS.ApplyChat(ui.chat)
        end
        -- chat windows are set through Blizzard's own functions, called from here: what they write on the
        -- chat frames is ours until a reload, so it ends with the same Reload question
        if o.chat and type(u.chat) == "string" and u.chat:find("windows$") then u.taint = true end
        if o.camera then YS.ApplyCamera(ui.camera) end
        return true
    end
    -- your keys, as they were where the interface was saved (kept for /ysetup undo like the game settings)
    if o.keys ~= false then
        steps[#steps + 1] = function()
            if login and u.k == nil and not YS.Ready("keys") then return "wait" end
            if u.k == nil then u.k = YS.KeysJob(ui.keys, backup) or false end
            if not u.k then
                u.keys = ui.keys and "not now" or "none saved"
                return true
            end
            if not YS.KeysStep(u.k, KEY_BATCH) then return false end
            u.keys = u.k.changed .. " changed"
            return true
        end
    end
    steps[#steps + 1] = function()
        u.guide = o.guide and ApplyGuide() or "off"
        return true
    end
    steps[#steps + 1] = function()
        local barText = barAddon and ("left to " .. barAddon) or (o.barVisibility and (tostring(u.bars) .. " changed") or "off")
        local machineText = o.graphics == false and "off" or (u.machine and (u.machine .. " changed") or "none saved")
        -- A new character's own setup asks for no reload: everything works without one, and the player reloads when it
        -- suits them (the owner, 2026-10-21, a new character set up in the stress test: "you don't need to do the
        -- reload, everything works, and I take a reload when it suits me"). Said at the end of this line, not a line more.
        local later = u.taint and login and " A /reload when it suits you finishes it (until then a bar can be blocked in a fight)." or ""
        YS.Print(("Edit Mode: %s. Blizzard action bars: %s. Chat: %s. Game settings changed: %d. Key bindings: %s. Graphics and sound: %s. Levelling guide: %s. RestedXP windows: %s.%s")
            :format(u.layout, barText, u.chat, u.set, u.keys, machineText, u.guide, o.rxpFrames ~= false and YS.ApplyRXP(ui.rxp) or "off", later))
        if YS.UIStale(ui) then
            -- what an older save lacks, by the version it was saved with (the list above UI_VERSION)
            local v, lacks = ui.v or 1, {}
            if v < 2 then lacks[#lacks + 1] = "whether the damage meter is on and RestedXP's look" end
            if v < 4 then lacks[#lacks + 1] = "your key bindings" end
            if v < 5 then lacks[#lacks + 1] = "graphics and sound" end
            YS.Print(("this interface was saved by an older Headstart: %s are not in it."
                .. " Save it again on %s (Character setup, Save interface), then Apply interface here.")
                :format(table.concat(lacks, ", "), tostring(YS.UISource() or "the character it came from")))
        end
        -- the old way taints until a reload; the game's own functions don't, but get checked a moment later
        if u.taint and login then
            if YR.TaintNoted then YR.TaintNoted("Character setup changed the bars or Edit Mode the old way (a reload clears it)") end
            YS.reloadDue = true         -- (for /ysetup debug: left for the player to make)
        elseif u.taint then
            YS.Print("reload to finish: until then the action bars can be blocked in combat.")
            if YR.TaintNoted then YR.TaintNoted("Character setup changed the bars or Edit Mode the old way (a reload clears it)") end
            StaticPopup_Show("YIPPSETUP_RELOAD")
        elseif (u.clean and u.layoutChanged) or u.cleanBars then
            -- the bars are checked even when nothing changed now: set at login (EarlyBars), they may not show yet
            CheckLater(u.clean and u.layoutChanged and ui.layout or nil, u.cleanBars and ui.bars or nil)
        end
        return true
    end
    return steps
end

function YS:ApplyUI(ui, o)
    for _, step in ipairs(YS.UISteps(ui, o)) do
        while not step() do end
    end
end

-- Put back everything (Setup.lua): this character's own interface, as it was before Headstart first changed it
-- (the copy YS.KeepFirst kept): its game settings, graphics and sound, key bindings, which bars show, its Edit
-- Mode layout, its chat windows and RestedXP's windows. Not the camera. The layout is picked by its own name
-- and kind (a character layout too: it is this character's own), imported again only if it is gone.
local function PickLayout(layout)
    local layouts, em = EditModeLayouts()
    if not (layout and layouts) then return "not kept", false end
    for index, info in ipairs(layouts) do
        if info.layoutName == layout.name and (layout.type == nil or info.layoutType == layout.type) then
            local active = em.layoutInfo and em.layoutInfo.activeLayout
            if active == index or (em.IsLayoutSelected and em:IsLayoutSelected(index)) then return "'" .. layout.name .. "' (already on)", false, true end
            if C_EditMode and C_EditMode.SetActiveLayout then
                C_EditMode.SetActiveLayout(index)
                return "'" .. layout.name .. "'", true, true
            end
            em:SelectLayout(index)
            return "'" .. layout.name .. "'", true, false
        end
    end
    local text, changed = ApplyLayoutClean(layout)
    if text then return text, changed, true end
    text, changed = ApplyLayout(layout)
    return text, changed, false
end

function YS.PutBackUI(ui)
    if type(ui) ~= "table" or InCombatLockdown() then return nil end
    local cvars, differ = {}, 0
    for _, list in ipairs({ ui.cvars, ui.machine }) do
        for name, v in pairs(type(list) == "table" and list or {}) do cvars[name] = v end
    end
    for name, v in pairs(cvars) do if C_CVar.GetCVar(name) ~= v then differ = differ + 1 end end
    if YS.PutBackCVars then YS.PutBackCVars(cvars) end
    local keys = ui.keys and YS.ApplyKeys(ui.keys)
    local suite = FirstLoaded(UI_SUITES)
    local barAddon = suite or FirstLoaded(BAR_ADDONS)
    local taint, bars = false, 0
    if type(ui.bars) == "table" and not barAddon then
        local n = ApplyBarsClean(ui.bars)
        if n then
            bars = n
        else
            for bar, shown in pairs(ui.bars) do
                local key = "PROXY_SHOW_ACTIONBAR_" .. bar
                local ok, cur = pcall(Settings.GetValue, key)
                if ok and cur ~= shown and pcall(Settings.SetValue, key, shown) then bars, taint = bars + 1, true end
            end
        end
    end
    local layout, changed, clean = "left to " .. tostring(suite), false, true
    if not suite then layout, changed, clean = PickLayout(ui.layout) end
    if changed and not clean then taint = true end
    local chat = ui.chat and YS.ApplyChat(ui.chat) or "not kept"
    if type(chat) == "string" and chat:find("windows$") then taint = true end
    local rxp = ui.rxp and YS.ApplyRXP(ui.rxp) or "nothing kept"
    YS.Print(("put back as it was before Headstart: game settings %d changed, key bindings %s, bars shown or hidden %d, Edit Mode %s,"
        .. " chat %s, RestedXP windows %s."):format(differ, keys and (keys .. " changed") or "not kept", bars, tostring(layout),
        tostring(chat), tostring(rxp)))
    if taint then
        YS.Print("reload to finish: until then the action bars can be blocked in combat.")
        if YR.TaintNoted then YR.TaintNoted("Character setup changed the bars or Edit Mode the old way (a reload clears it)") end
        StaticPopup_Show("YIPPSETUP_RELOAD")
    end
    return true
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
