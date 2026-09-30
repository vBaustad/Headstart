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
local DEFAULT_MAX_LEVEL = 10
local MACRO_NAME_MAX = 16

local function Print(msg)
    print("|cff66ccffYippRoute|r: " .. msg)
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
function YS:Scan(maxLevel)
    local _, class = UnitClass("player")
    local levels = YS.SPELL_LEVELS[class] or {}
    local slots = {}
    local n = { spell = 0, macro = 0, later = 0, other = 0, prof = 0 }
    for slot = 1, MAX_SLOT do
        if HasAction(slot) then
            local kind, id = GetActionInfo(slot)
            local entry, lvl
            if kind == "spell" then
                local name = C_Spell.GetSpellName(id)
                lvl = name and (levels[name] or (YS.RACIALS[name] and 1))
                if lvl and lvl <= maxLevel then
                    entry = { kind = "spell", name = name }
                elseif lvl then
                    n.later = n.later + 1
                elseif name and YS.PROFESSIONS[name] then
                    -- the exact spell and its icon: one name can be several spells (see ProfessionSpellID)
                    entry = { kind = "spell", name = name, prof = true, id = id, icon = C_Spell.GetSpellTexture(id) }
                end
            elseif kind == "macro" then
                entry = ReadMacroSlot(slot, id)
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
    YippSetupDB.profile = { from = PlayerKey(), class = class, maxLevel = maxLevel, scanned = time(), slots = slots,
        ui = YS:ScanUI() }
    Print(("saved %s: %d spells (up to level %d), %d profession spells and %d macros. Left out %d higher-level spells and %d other buttons (items).")
        :format(PlayerKey(), n.spell, maxLevel, n.prof, n.macro, n.later, n.other))
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

-- Your choices for the new character.
local REPLACE = {}   -- e.g. ["Seal of Fury"] = "Seal of Righteousness": that spell goes in this one's slot
local MOUSEOVER = { ["Purify"] = true }                          -- cast on your mouseover target, else yourself/target
-- Macro names are the last part of the spell ("Crusader", "Might"); these would clash, so they get their own.
local SHORT = { ["Divine Protection"] = "Divine" }

local function ShortName(spell)
    local short = SHORT[spell] or spell:match(" of the (.+)$") or spell:match(" of (.+)$") or spell:match("(%S+)$")
    return short:sub(1, MACRO_NAME_MAX)
end

local function MacroFor(e)
    if e.kind == "spell" then
        local spell = REPLACE[e.name] or e.name
        local cast = MOUSEOVER[spell] and ("/cast [@mouseover,help,nodead][] " .. spell) or ("/cast " .. spell)
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
    return not MOUSEOVER[spell] and KnownSpellID(spell) or nil
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
    local p = YippSetupDB.profile
    if not p then
        Print("nothing saved yet. Log on to your main and type /ysetup scan")
        return
    end
    local _, class = UnitClass("player")
    if p.class ~= class and not force then
        Print(("the saved bars are from a %s. Type /ysetup apply force to use them anyway."):format(p.class))
        return
    end
    ClearBars()
    local autofeed = AutoFeedNames()
    local removed = ClearCharacterMacros(AutoFeedOwned())
    local levels = YS.SPELL_LEVELS[class] or {}
    local made, placed, full, noAutoFeed = 0, 0, nil, nil
    for slot = 1, MAX_SLOT do
        local e = p.slots[slot]
        local idx
        local spellID = e and (levels[e.name] or YS.RACIALS[e.name] or e.prof) and RealSpell(e)
        if spellID then
            PlaceSpell(slot, spellID)
            placed = placed + 1
        elseif e and e.kind == "macro" and autofeed[e.name] then
            -- AutoFeed's macros are never made here: only the ones AutoFeed already made on this
            -- character are placed; the slot stays empty otherwise
            local own = AutoFeedOwned()[e.name] and GetMacroIndexByName(e.name)
            if own and own > 0 then idx = own else noAutoFeed = e.name end
        -- a layout saved by an older version can still hold items and non-class spells
        elseif e and (e.kind == "macro" or (e.kind == "spell" and (levels[e.name] or YS.RACIALS[e.name]))) then
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
    if noAutoFeed then
        Print(("AutoFeed hasn't made '%s' on this character yet, so that slot is empty. Create it in AutoFeed and Set up layout again."):format(noAutoFeed))
    end
    if not NoAutoPush() then
        Print("this client has no setting for Blizzard placing new spells on the bars, so it may still add duplicates.")
    end
    YS:ApplyUI(p.ui)
end

-- A spell just learned: its placeholder macro is swapped for the spell itself and then deleted; a
-- profession spell (it has no placeholder) goes into its slot if that is still empty.
-- Only on a character that was set up, and never in combat (it waits for combat to end).
local waiting = false
function YS:Upgrade()
    local p = YippSetupDB.profile
    if not (p and YippSetupCharDB.applied) then return end
    if InCombatLockdown() then
        waiting = true
        return
    end
    waiting = false
    local swapped = {}
    for slot, e in pairs(p.slots) do
        local id = RealSpell(e)
        if id and e.prof and not HasAction(slot) then
            PlaceSpell(slot, id)      -- a profession spell just learned: into its empty slot
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
    text = "YippSetup: replace the saved layout from %s with this character's?",
    button1 = "Replace",
    button2 = "Cancel",
    OnAccept = function(_, maxLevel) YS:Scan(maxLevel) YS:Refresh() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function YS:Copy(maxLevel)
    maxLevel = maxLevel or DEFAULT_MAX_LEVEL
    local p = YippSetupDB.profile
    if p and p.from ~= PlayerKey() then
        StaticPopup_Show("YIPPSETUP_OVERWRITE", p.from, nil, maxLevel)
    else
        self:Scan(maxLevel)
        self:Refresh()
    end
end

local window

-- The first-time window: two choices, in YippRoute's own look.
local function BuildWindow()
    local w = S.Window("YippSetupFrame", 440, 200, "Set up this character")
    w:ClearAllPoints()
    w:SetPoint("CENTER", 0, 120)
    w.info = S.Text(w, 13, S.C.sub)
    w.info:SetPoint("TOPLEFT", 20, -66)
    w.info:SetWidth(400)
    w.info:SetWordWrap(true)
    w.info:SetSpacing(3)

    -- Only a deliberate click marks this character as done. Escape (which also skips the intro
    -- cinematic) just hides the window, so it comes back on the next login.
    local function Done() YippSetupCharDB.seen = CharacterID() or true end
    w.copy = S.Button(w, "Copy this layout", function() Done() YS:Copy() end, nil, 190)
    w.copy:SetPoint("BOTTOMLEFT", 20, 20)
    w.copy.tip = "On your main: save its bars, macros, Edit Mode layout and game settings"
    w.setup = S.Button(w, "Set up layout", function() Done() YS:Apply() YS:Refresh() end, "primary", 190)
    w.setup:SetPoint("BOTTOMRIGHT", -20, 20)
    w.setup.tip = "On a new character: put the saved layout on this one"
    w.close:HookScript("OnClick", Done)
    return w
end

function YS:Refresh()
    if not window then return end
    local p = YippSetupDB.profile
    local _, class = UnitClass("player")
    local can = false
    if not p then
        window.info:SetText("No layout saved yet. On your main, click Copy this layout.")
    else
        window.info:SetText(("Saved layout: |cffffffff%s|r, a %s, spells up to level %d.%s"):format(p.from,
            p.class:lower(), p.maxLevel,
            p.ui and "" or "\n|cffff8040No bars or settings saved: log in on " .. p.from .. " once.|r"))
        can = p.class == class and p.from ~= PlayerKey()
    end
    window.setup:SetEnabled(can)
    window.setup:SetAlpha(can and 1 or 0.35)
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
    if not id or YippSetupCharDB.seen == id or (window and window:IsShown()) then return end
    if InCinematic() or not UIParent:IsShown() then
        C_Timer.After(2, FirstTimeHere)
        return
    end
    YS:Toggle()
end

-- A layout copied before Edit Mode, bars and settings were saved has no ui part. Logging in on the
-- character it was copied from fills it in, so the bars aren't copied again just for that.
local function FillInUI()
    local p = YippSetupDB.profile
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
        YS:Copy(tonumber(arg))
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
        YippSetupDB = YippSetupDB or {}
        YippSetupCharDB = YippSetupCharDB or {}
    elseif event == "PLAYER_ENTERING_WORLD" and (arg1 or arg2) then   -- login or reload only
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        C_Timer.After(2, FirstTimeHere)
        C_Timer.After(3, FillInUI)
        if YippSetupCharDB.applied then NoAutoPush() end
    elseif event == "SPELLS_CHANGED" or (event == "PLAYER_REGEN_ENABLED" and waiting) then
        if YippSetupCharDB then YS:Upgrade() end
    end
end)
