-- Character setup (was the YippSetup addon): copy your main's action bars to a fresh character.
-- "Copy this layout" on the main records every slot. On the new character "Set up layout" rebuilds them: a
-- class spell up to the scanned level that is already known goes on the bar as the spell itself; one not
-- trained yet holds its slot as a "#showtooltip /cast <spell>" macro (a question mark), which is swapped for
-- the real spell the moment it is learned. Nothing needs dragging while levelling.
local ADDON, YR = ...
YR.Setup = YR.Setup or {}
local YS = YR.Setup
local S = YR.Style

local DYNAMIC_ICON = 134400     -- the question mark; #showtooltip shows the real icon once the spell is known
local MAX_SLOT = 180
local SCAN_LEVEL = 60           -- Copy saves every spell; the level limit is a setup option

-- What Set up carries over. Every part has a switch in Settings, Character tab.
local OPTION_DEFAULTS = {
    classSpells = true, maxLevel = 10, placeholders = true, racials = true, professions = true,
    mouseover = "Purify",
    macros = true, autofeed = true, items = false,
    clearBars = true, clearMacros = true,
    settings = true, editMode = true, barVisibility = true, guide = true, noAutoPush = true,
    swap = true, popup = true, skipIntro = true, chat = true, camera = true,
}

-- Everything is kept per class: a warrior main's bars and choices don't land on a new paladin.
--   YippSetupDB.classes[CLASS] = { options = { ... }, profile = { ... saved layout ... } }
-- From before that, one set for all: YippSetupDB.options and YippSetupDB.profile. They are never
-- changed or removed (an older Headstart still reads them): a class's options start as a copy of
-- them, and the old layout becomes the layout of the class it was copied from.
local function PlayerClass()
    local _, class = UnitClass("player")
    return class or "WARRIOR"
end
YS.PlayerClass = PlayerClass

local function Copy(t)
    local c = {}
    for k, v in pairs(t or {}) do c[k] = type(v) == "table" and Copy(v) or v end
    return c
end

local function ClassData(class)
    YippSetupDB.classes = YippSetupDB.classes or {}
    local c = YippSetupDB.classes[class]
    if not c then
        c = { options = Copy(YippSetupDB.options) }
        local old = YippSetupDB.profile
        if old and old.class == class then c.profile = Copy(old) end
        YippSetupDB.classes[class] = c
    end
    return c
end

-- The saved layout for a class (this character's if none is given), or nil.
function YS:Profile(class)
    return YippSetupDB and ClassData(class or PlayerClass()).profile
end

function YS:Options(class)
    local o = ClassData(class or PlayerClass()).options
    for k, v in pairs(OPTION_DEFAULTS) do if o[k] == nil then o[k] = v end end
    return o
end
local MACRO_NAME_MAX = 16

local function Print(msg)
    print("|cff66ccffHeadstart|r: " .. msg)
end
YS.Print = Print

-- The character's GUID, or nil where Forever hides it (battlegrounds, arenas): the concatenation
-- errors on a secret value, and pcall turns that into nil.
local function CharacterID()
    local ok, guid = pcall(function() return UnitGUID("player") .. "" end)
    return ok and guid or nil
end

local function PlayerKey()
    local name, realm = UnitFullName("player")
    return (name or "?") .. "-" .. (realm or GetRealmName() or "?")
end

--------------------------------------------------------------------------------
-- Scan
--------------------------------------------------------------------------------

-- Macro actions: read the macro through its name, not GetActionInfo's id, which is not always the index.
local function ReadMacroSlot(slot, id)
    local mname = GetActionText(slot)
    local idx = (mname and GetMacroIndexByName(mname)) or id
    if not idx or idx == 0 then return nil end
    local name, icon, body = GetMacroInfo(idx)
    if not name then return nil end
    return { kind = "macro", name = name, icon = icon, body = body }
end

-- Class spells up to the level limit, racials (Stoneform: every character has them from level 1),
-- profession spells (placed on the new character once learned) and your own macros (AutoFeed's
-- included). Items are left out.
function YS:Scan()
    local maxLevel = SCAN_LEVEL
    local _, class = UnitClass("player")
    local levels = YS.SPELL_LEVELS[class] or {}
    local slots = {}
    local n = { spell = 0, macro = 0, later = 0, other = 0, prof = 0, item = 0 }
    for slot = 1, MAX_SLOT do
        if HasAction(slot) then
            local kind, id = GetActionInfo(slot)
            local entry, lvl
            if kind == "spell" then
                local name = C_Spell.GetSpellName(id)
                lvl = name and (levels[name] or (YS.RACIALS[name] and 1))
                if lvl and lvl <= maxLevel then
                    entry = { kind = "spell", name = name, level = lvl, racial = YS.RACIALS[name] or nil }
                elseif lvl then
                    n.later = n.later + 1
                elseif name and YS.PROFESSIONS[name] then
                    -- the exact spell and its icon: one name can be several spells (see ProfessionSpellID)
                    entry = { kind = "spell", name = name, prof = true, id = id, icon = C_Spell.GetSpellTexture(id) }
                end
            elseif kind == "macro" then
                entry = ReadMacroSlot(slot, id)
            elseif kind == "item" and id then
                entry = { kind = "item", id = id, name = C_Item.GetItemNameByID(id) }
            end
            if entry then
                slots[slot] = entry
                local key = entry.prof and "prof" or entry.kind
                n[key] = n[key] + 1
            elseif not (kind == "spell" and lvl) then
                n.other = n.other + 1
            end
        end
    end
    ClassData(class).profile = { from = PlayerKey(), class = class, maxLevel = maxLevel, scanned = time(), slots = slots,
        ui = YS:ScanUI() }
    Print(("saved %s: %d spells, %d profession spells, %d macros and %d items. What goes onto a new character is"
        .. " chosen in Settings, Character tab."):format(PlayerKey(), n.spell, n.prof, n.macro, n.item))
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

-- Your choices for the new character.
local REPLACE = {}   -- e.g. ["Seal of Fury"] = "Seal of Righteousness": that spell goes in this one's slot
-- Spells cast on your mouseover target (else yourself or your target): a list in the options.
local mouseoverText, mouseoverSet
local function MOUSEOVER_SET()
    local text = YS:Options().mouseover or ""
    if text ~= mouseoverText then
        mouseoverText, mouseoverSet = text, {}
        for name in (text .. ","):gmatch("%s*([^,]-)%s*,") do
            if name ~= "" then mouseoverSet[name] = true end
        end
    end
    return mouseoverSet
end
-- Macro names are the last part of the spell ("Crusader", "Might"); these would clash, so they get their own.
local SHORT = { ["Divine Protection"] = "Divine" }

local function ShortName(spell)
    local short = SHORT[spell] or spell:match(" of the (.+)$") or spell:match(" of (.+)$") or spell:match("(%S+)$")
    return short:sub(1, MACRO_NAME_MAX)
end

local function MacroFor(e)
    if e.kind == "spell" then
        local spell = REPLACE[e.name] or e.name
        local cast = MOUSEOVER_SET()[spell] and ("/cast [@mouseover,help,nodead][] " .. spell) or ("/cast " .. spell)
        return ShortName(spell), DYNAMIC_ICON, "#showtooltip " .. spell .. "\n" .. cast
    end
    -- your own macros: no "(Rank 3)", so a spell always casts its highest known rank
    local body = (e.body or ""):gsub("%s*%(Rank %d+%)", "")
    return e.name, e.icon or DYNAMIC_ICON, body
end

-- The spell's ID when this character knows it, else nil.
local function KnownSpellID(name)
    local info = C_Spell.GetSpellInfo(name)
    local id = info and info.spellID
    if id and IsPlayerSpell(id) then return id end
end

local function PlaceSpell(slot, id)
    local pickup = C_Spell.PickupSpell or PickupSpell
    pickup(id)
    PlaceAction(slot)
    ClearCursor()
end

-- A profession name can be several spells: its ranks, and Forever's hidden same-named ones (a purple-gem
-- "Blacksmithing" every blacksmith knows), which a lookup by name can land on. So: the main's exact spell
-- if known here, else a known one with the main's icon, else the lowest known ID (the real ranks come first).
local function ProfessionSpellID(e)
    if e.id and IsPlayerSpell(e.id) then return e.id end
    local ids = YS.PROFESSIONS[e.name]
    if type(ids) ~= "table" then return nil end
    local first
    for _, id in ipairs(ids) do
        if IsPlayerSpell(id) then
            if e.icon and C_Spell.GetSpellTexture(id) == e.icon then return id end
            first = first or id
        end
    end
    return first
end

-- A spell slot goes on the bar as the spell itself once it is known; a mouseover spell (Purify) stays a macro.
local function RealSpell(e)
    if e.kind ~= "spell" then return nil end
    if e.prof then return ProfessionSpellID(e) end
    local spell = REPLACE[e.name] or e.name
    return not MOUSEOVER_SET()[spell] and KnownSpellID(spell) or nil
end

-- Whether the options carry this saved button over. levels: this class's spell levels; autofeed:
-- AutoFeed's macro names.
local function Wanted(e, levels, autofeed, o)
    if not e then return false end
    if e.kind == "spell" then
        if e.prof then return o.professions end
        if e.racial or YS.RACIALS[e.name] then return o.racials end
        local lvl = e.level or levels[e.name]
        return lvl ~= nil and o.classSpells and lvl <= o.maxLevel
    elseif e.kind == "macro" then
        if autofeed[e.name] then return o.autofeed end
        return o.macros
    elseif e.kind == "item" then
        return o.items
    end
    return false
end

-- Everything off every bar, so the new character starts from exactly the saved layout.
local function ClearBars()
    for slot = 1, MAX_SLOT do
        if HasAction(slot) then
            PickupAction(slot)
            ClearCursor()
        end
    end
end

-- AutoFeed's macro names: its settings if it has run on this account, else its defaults.
local AUTOFEED = { macroName = "AutoFeed", drinkMacroName = "AutoDrink", healMacroName = "AutoHealPot",
    manaMacroName = "AutoManaPot", scrollMacroName = "AutoScroll", bandageMacroName = "AutoBandage" }
local function AutoFeedNames()
    local db = type(AutoFeedDB) == "table" and AutoFeedDB or {}
    local names = {}
    for key, default in pairs(AUTOFEED) do
        names[type(db[key]) == "string" and db[key] or default] = true
    end
    return names
end

-- The AutoFeed macros AutoFeed itself made on this character. A macro that only has AutoFeed's name
-- (a copy from an older YippSetup) is not one of them: AutoFeed would never fill it.
local function AutoFeedOwned()
    local char = type(AutoFeedCharDB) == "table" and AutoFeedCharDB or {}
    return type(char.owned) == "table" and char.owned or {}
end

-- AutoFeed's own "make this macro" (published through LibForever at login): it makes the macro
-- configured under that name exactly as its Create button does, owns it and fills it, and returns
-- the macro index. Nil when AutoFeed isn't loaded or couldn't make it (slots full, in combat,
-- or somebody else's macro has the name).
local function AutoFeedMaker()
    local lib = LibStub and LibStub("LibForever-1.0", true)
    local maker = lib and lib.GetData and lib.GetData("AutoFeedMacros")
    return maker and maker.Create
end

function YS:AutoFeedLoaded()
    return AutoFeedMaker() ~= nil
end


-- Delete this character's macros, except the ones AutoFeed owns. General (account) macros are left
-- alone: they are shared with every other character, your main included.
local function ClearCharacterMacros(keep)
    local _, numChar = GetNumMacros()
    local base = Constants.MacroConsts.MAX_ACCOUNT_MACROS
    local removed = 0
    for i = base + numChar, base + 1, -1 do      -- from the end: deleting shifts the ones after it
        local name = GetMacroInfo(i)
        if name and not keep[name] then
            DeleteMacro(i)
            removed = removed + 1
        end
    end
    return removed
end

-- An existing macro (account or character) with the same body is reused, so applying twice
-- doesn't duplicate anything and your general macros aren't copied into character slots.
local function FindMacro(body)
    local numAccount, numChar = GetNumMacros()
    local base = Constants.MacroConsts.MAX_ACCOUNT_MACROS
    for i = 1, numAccount do
        if select(3, GetMacroInfo(i)) == body then return i end
    end
    for i = base + 1, base + numChar do
        if select(3, GetMacroInfo(i)) == body then return i end
    end
end

-- Blizzard drops every newly learned spell onto the first empty bar slot; with the bars set up from the
-- main that only makes duplicates. Turned off on every set-up character (the setting may be per character).
local function NoAutoPush()
    local cur = C_CVar.GetCVar("AutoPushSpellToActionBar")
    if cur == nil then return false end
    if cur ~= "0" then C_CVar.SetCVar("AutoPushSpellToActionBar", "0") end
    return true
end

function YS:Apply(force)
    if InCombatLockdown() then
        Print("can't change action bars in combat.")
        return
    end
    local _, class = UnitClass("player")
    -- force: another class's layout (the last one saved before layouts were per class)
    local p = YS:Profile() or (force and YippSetupDB.profile)
    if not p then
        Print(("no layout saved for %s yet. On your %s main, click Copy this layout (Settings, Character tab)."
            .. " /ysetup apply force uses another class's."):format(class:lower(), class:lower()))
        return
    end
    local o = YS:Options()
    if o.clearBars then ClearBars() end
    local autofeed = AutoFeedNames()
    local removed = o.clearMacros and ClearCharacterMacros(AutoFeedOwned()) or 0
    local levels = YS.SPELL_LEVELS[class] or {}
    local made, placed, full, noAutoFeed, askedAutoFeed = 0, 0, nil, nil, 0
    for slot = 1, MAX_SLOT do
        local e = p.slots[slot]
        if not Wanted(e, levels, autofeed, o) then e = nil end
        local idx
        local spellID = e and (levels[e.name] or YS.RACIALS[e.name] or e.prof) and RealSpell(e)
        if spellID then
            PlaceSpell(slot, spellID)
            placed = placed + 1
        elseif e and e.kind == "item" then
            local pickup = (C_Item and C_Item.PickupItem) or PickupItem
            pickup(e.id)
            PlaceAction(slot)
            ClearCursor()
            placed = placed + 1
        elseif e and e.kind == "macro" and autofeed[e.name] then
            -- AutoFeed's macros are never copied: a copy is a macro AutoFeed doesn't own, so it would
            -- never fill it. One AutoFeed already made is placed; otherwise AutoFeed is asked to make it.
            local own = AutoFeedOwned()[e.name] and GetMacroIndexByName(e.name)
            if not (own and own > 0) then
                local create = AutoFeedMaker()
                local ok, res = false, nil
                if create then ok, res = pcall(create, e.name) end
                own = ok and res or nil
                if own then askedAutoFeed = askedAutoFeed + 1 end
            end
            if own and own > 0 then idx = own else noAutoFeed = e.name end
        -- a layout saved by an older version can still hold items and non-class spells
        elseif e and (e.kind == "macro" or (o.placeholders and e.kind == "spell" and (levels[e.name] or YS.RACIALS[e.name]))) then
            local name, icon, body = MacroFor(e)
            idx = FindMacro(body)
            if not idx then
                local ok, res = pcall(CreateMacro, name, icon, body, true)   -- per-character
                if ok and res then
                    idx, made = res, made + 1
                else
                    full = name
                    break
                end
            end
        end
        if idx then
            PickupMacro(idx)
            PlaceAction(slot)
            ClearCursor()
            placed = placed + 1
        end
    end
    YippSetupCharDB.applied = p.scanned
    Print(("placed %d buttons from %s (%d new macros for spells not trained yet or your own, %d old character macros removed).")
        :format(placed, p.from, made, removed))
    if full then
        Print(("stopped at '%s': your character macro slots are full (%d)."):format(full, Constants.MacroConsts.MAX_CHARACTER_MACROS))
    end
    if askedAutoFeed > 0 then
        Print(("AutoFeed made %d of its macros for this character; it keeps them filled."):format(askedAutoFeed))
    end
    if noAutoFeed then
        Print(AutoFeedMaker()
            and ("AutoFeed couldn't make '%s' (macro slots full, or another macro has that name), so that slot is empty."):format(noAutoFeed)
            or ("'%s' is AutoFeed's macro and AutoFeed isn't loaded, so that slot is empty."):format(noAutoFeed))
    end
    if o.noAutoPush and not NoAutoPush() then
        Print("this client has no setting for Blizzard placing new spells on the bars, so it may still add duplicates.")
    end
    YS:ApplyUI(p.ui, o)
end

-- A spell just learned: its placeholder macro is swapped for the spell itself and then deleted; a
-- profession spell (it has no placeholder) goes into its slot if that is still empty.
-- Only on a character that was set up, and never in combat (it waits for combat to end).
local waiting = false
function YS:Upgrade()
    local p = YS:Profile()
    local o = YS:Options()
    if not (p and YippSetupCharDB.applied and o.swap) then return end
    if InCombatLockdown() then
        waiting = true
        return
    end
    waiting = false
    local swapped = {}
    local _, class = UnitClass("player")
    local levels, autofeed = YS.SPELL_LEVELS[class] or {}, AutoFeedNames()
    for slot, e in pairs(p.slots) do
        local id = Wanted(e, levels, autofeed, o) and RealSpell(e)
        if id and (e.prof or not o.placeholders) and not HasAction(slot) then
            PlaceSpell(slot, id)      -- just learned, and no placeholder holds its slot: straight in
        elseif id and HasAction(slot) then
            local kind, actionID = GetActionInfo(slot)
            local m = kind == "macro" and ReadMacroSlot(slot, actionID)
            if m and m.body == select(3, MacroFor(e)) then
                PlaceSpell(slot, id)
                swapped[m.name] = m.body
            end
        end
    end
    for name, body in pairs(swapped) do
        local onBar = false
        for slot = 1, MAX_SLOT do
            if HasAction(slot) and GetActionText(slot) == name then onBar = true break end
        end
        local idx = GetMacroIndexByName(name)
        if not onBar and idx and idx > 0 and select(3, GetMacroInfo(idx)) == body then DeleteMacro(idx) end
    end
end

--------------------------------------------------------------------------------
-- The window: shown the first time each character logs in, and from the compartment or /ysetup
--------------------------------------------------------------------------------

StaticPopupDialogs["YIPPSETUP_OVERWRITE"] = {
    text = "Headstart: replace the saved layout from %s with this character's?",
    button1 = "Replace",
    button2 = "Cancel",
    OnAccept = function() YS:Scan() YS:Refresh() YR:RefreshWindow() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function YS:Copy()
    local p = YS:Profile()
    if p and p.from ~= PlayerKey() then
        StaticPopup_Show("YIPPSETUP_OVERWRITE", p.from)
    else
        self:Scan()
        self:Refresh()
    end
end

local window

-- The first-time window: two choices, in Headstart's own look.
local function BuildWindow()
    local w = S.Window("YippSetupFrame", 380, 146, "Set up this character")
    w:ClearAllPoints()
    w:SetPoint("CENTER", 0, 120)
    w.info = S.Text(w, 13, S.C.sub)
    w.info:SetPoint("TOPLEFT", 20, -62)
    w.info:SetWidth(340)
    w.info:SetWordWrap(true)
    w.info:SetSpacing(3)

    -- Only a deliberate click marks this character as done. Escape (which also skips the intro
    -- cinematic) just hides the window, so it comes back on the next login.
    local function Done() YippSetupCharDB.seen = CharacterID() or true end
    -- Set up is instant (a new character wants to get going); Copy first shows every choice of what
    -- carries over (Settings, Character tab), and is done from there
    w.setup = S.Button(w, "Set up layout", function() Done() YS:Apply() YS:Refresh() end, "primary")
    w.setup:SetPoint("BOTTOMRIGHT", -16, 16)
    w.setup.tip = "On a new character: put the saved layout on this one, now"
    w.copy = S.Button(w, "Copy this layout...", function()
        Done()
        w:Hide()
        YR:ShowSettingsTab("character")
    end)
    w.copy:SetPoint("RIGHT", w.setup, "LEFT", -8, 0)
    w.copy.tip = "On your main: see what a new character will get, then copy this one's bars, macros and settings"
    w.close:HookScript("OnClick", Done)
    return w
end

function YS:Refresh()
    if not window then return end
    local p = YS:Profile()
    local class = PlayerClass():lower()
    if not p then
        window.info:SetText(("No %s layout saved yet. On your %s main, click Copy this layout."):format(class, class))
    else
        window.info:SetText(("Saved %s layout: |cffffffff%s|r.%s"):format(class, YS:Describe(p) or p.from,
            p.ui and "" or "\n|cffff8040No bars or settings saved: log in on " .. p.from .. " once.|r"))
    end
    window.setup:SetEnabled(p ~= nil and p.from ~= PlayerKey())
end

-- "Duplo-Bonk, 30 Sep 21:14": who the saved layout is from and when it was copied.
function YS:Describe(p)
    p = p or YS:Profile()
    if not p then return nil end
    return p.from .. (p.scanned and date(", %d %b %H:%M", p.scanned) or "")
end

function YS:Toggle()
    window = window or BuildWindow()
    if window:IsShown() then window:Hide() else window:Show() self:Refresh() end
end

-- A new character logs in to the intro cinematic, which hides UIParent: wait until it's over.
-- "Seen" is kept per character GUID: a deleted character's saved variables survive, so a new
-- character with the same name would otherwise inherit it.
local function FirstTimeHere()
    local id = CharacterID()
    if not id or YippSetupCharDB.seen == id or (window and window:IsShown()) or not YS:Options().popup then return end
    if InCinematic() or not UIParent:IsShown() then
        C_Timer.After(2, FirstTimeHere)
        return
    end
    YS:Toggle()
end

-- The intro cinematic (or movie) a new character logs in to: cancelled at once while level 1, when the
-- option is on. It can start before we load, so the first login checks for one running too.
local function SkipIntro()
    if UnitLevel("player") > 1 or not (YippSetupDB and YS:Options().skipIntro) then return end
    if InCinematic and InCinematic() then
        if CinematicFrame_CancelCinematic then CinematicFrame_CancelCinematic() elseif StopCinematic then StopCinematic() end
    end
    if MovieFrame and MovieFrame:IsShown() then
        MovieFrame:StopMovie()
        if GameMovieFinished then GameMovieFinished() end
    end
end
YS.SkipIntro = SkipIntro

-- A new character comes out of the intro with the camera all the way in: once, at level 1, out to the
-- main's distance (from the saved layout), or a normal third-person distance without one.
local function FirstZoom()
    if UnitLevel("player") > 1 or not YippSetupDB or not YS:Options().camera or YippSetupCharDB.zoomed then return end
    if InCinematic and InCinematic() then return end        -- after it ends (CINEMATIC_STOP)
    YippSetupCharDB.zoomed = true
    local p = YS:Profile()
    C_Timer.After(1, function() YS.ApplyCamera(p and p.ui and p.ui.camera or 15) end)
end
YS.FirstZoom = FirstZoom

-- A layout copied before Edit Mode, bars and settings were saved has no ui part. Logging in on the
-- character it was copied from fills it in, so the bars aren't copied again just for that.
local function FillInUI()
    local p = YS:Profile()
    if p and not p.ui and p.from == PlayerKey() then
        p.ui = YS:ScanUI()
        YS:Refresh()
        Print("added this character's Edit Mode layout, action bars and game settings to the saved layout.")
    end
end

--------------------------------------------------------------------------------
-- Slash command and events
--------------------------------------------------------------------------------

SLASH_YIPPSETUP1 = "/ysetup"
SlashCmdList.YIPPSETUP = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
    if cmd == "scan" then
        YS:Copy()
    elseif cmd == "apply" then
        YS:Apply(arg == "force")
    else
        YS:Toggle()
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("SPELLS_CHANGED")        -- a spell learned (it also fires for much else; Upgrade is cheap)
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        local fresh = YippSetupCharDB == nil       -- this character's first login with Headstart
        YippSetupDB = YippSetupDB or {}
        YippSetupCharDB = YippSetupCharDB or {}
        -- a new character: the main's action bars now, so Blizzard shows them while logging in
        local level = UnitLevel("player") or 0
        if fresh and level <= 1 and YS.EarlyBars then
            YippSetupCharDB.earlyBars = YS.EarlyBars()
        end
    elseif event == "PLAYER_ENTERING_WORLD" and (arg1 or arg2) then   -- login or reload only
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        SkipIntro()
        C_Timer.After(0.5, FirstZoom)
        C_Timer.After(2, FirstTimeHere)
        C_Timer.After(3, FillInUI)
        if YippSetupCharDB.applied then NoAutoPush() end
    elseif event == "SPELLS_CHANGED" or (event == "PLAYER_REGEN_ENABLED" and waiting) then
        if YippSetupCharDB then YS:Upgrade() end
    end
end)

-- the intro starting while we are loaded (see SkipIntro)
local intro = CreateFrame("Frame")
intro:RegisterEvent("CINEMATIC_START")
intro:RegisterEvent("PLAY_MOVIE")
intro:RegisterEvent("CINEMATIC_STOP")
intro:SetScript("OnEvent", function(_, event)
    if event == "CINEMATIC_STOP" then C_Timer.After(0.5, FirstZoom) else C_Timer.After(0, SkipIntro) end
end)
