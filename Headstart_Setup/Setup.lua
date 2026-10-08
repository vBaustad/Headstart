-- Character setup (was the YippSetup addon): copy your main's action bars to a fresh character.
-- "Copy this layout" on the main records every slot. On the new character "Set up layout" rebuilds them: a
-- class spell up to the scanned level that is already known goes on the bar as the spell itself; one not
-- trained yet holds its slot as a "#showtooltip /cast <spell>" macro (a question mark), which is swapped for
-- the real spell the moment it is learned. Nothing needs dragging while levelling.
-- (part of the Headstart_Setup addon, loaded by Headstart while Character setup is on: an addon of its
-- own has a table of its own, so Headstart's is taken from HeadstartNS)
local YR = _G.HeadstartNS
YR.Setup = YR.Setup or {}
local YS = YR.Setup
local S = YR.Style

local DYNAMIC_ICON = 134400     -- the question mark; #showtooltip shows the real icon once the spell is known
-- A spell you haven't learned yet waits in its slot as a macro. With the question mark the game shows
-- a red "?" until the spell is known - a bar of them tells you nothing. So such a macro is given the
-- spell's own icon (from the game's data, Data/PlannerSpells.lua): your bars look as you planned them
-- from level 1, and the same in the planner and out of it.
local MAX_SLOT = 180
local SCAN_LEVEL = 60           -- Copy saves every spell
-- How far ahead of your level a class spell gets its button now (a question-mark macro until it is
-- learned). There is no setting for it: every spell at or under your level is placed, the next ten
-- levels' wait as question marks, and the rest keep their slot empty and go in when you learn them.
-- (It was a setting, "Class spells up to level", 10 to begin with - and on a character past it, it
-- took every later spell off the bars.)
local AHEAD = 10

-- What Set up carries over. Every part has a switch in Settings, Character tab.
local OPTION_DEFAULTS = {
    classSpells = true, maxLevel = 10, placeholders = true, racials = true, professions = true,
    mouseover = "Purify",
    macros = true, autofeed = true, items = false,
    clearBars = true, clearMacros = true,
    settings = true, editMode = true, barVisibility = true, guide = true, noAutoPush = true,
    swap = true, rankUp = true, popup = true, skipIntro = true, chat = true, camera = true,
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

-- The interface - chat windows and tabs, Edit Mode, game settings, raid frames, camera, which bars show -
-- is the account's, not a class's: set it up once on any character and every class gets it. Copy this
-- layout saves it here (the newest copy wins); the bars stay per class. Kept as YippSetupDB.ui, with
-- who it came from. From before (2026-10-02) each class's layout carried its own: the newest one copied
-- from a real character (not a plan, which only ever held a level-1 character's defaults) becomes the
-- account's, once.
function YS:SharedUI()
    if not YippSetupDB then return nil end
    if YippSetupDB.ui == nil and not YippSetupDB.uiMoved then
        YippSetupDB.uiMoved = true
        local best
        for _, c in pairs(YippSetupDB.classes or {}) do
            local p = c.profile
            if p and p.ui and not p.planned and (not best or (p.scanned or 0) > (best.scanned or 0)) then best = p end
        end
        if best then YippSetupDB.ui, YippSetupDB.uiFrom, YippSetupDB.uiScanned = best.ui, best.from, best.scanned end
    end
    return YippSetupDB.ui
end

function YS:SaveSharedUI()
    -- the one before is kept too: a copy made on the wrong character doesn't lose the good one
    if YippSetupDB.ui then
        YippSetupDB.uiPrev = { ui = YippSetupDB.ui, from = YippSetupDB.uiFrom, scanned = YippSetupDB.uiScanned }
    end
    YippSetupDB.ui, YippSetupDB.uiFrom, YippSetupDB.uiScanned = YS:ScanUI(), YS.PlayerKey(), time()
    YippSetupDB.uiMoved = true
end

--- The interface alone, saved from this character: chat windows, Edit Mode, game settings, which bars
--- show, the camera. No action button or macro is read, and the class's saved bars are left as they are.
function YS:CopyInterface()
    YS:SaveSharedUI()
    YS.Print(("saved %s's interface (chat windows, Edit Mode, game settings, which bars show, camera). The bars"
        .. " saved for the class are untouched."):format(YS.PlayerKey()))
    if YR.RefreshWindow then YR:RefreshWindow() end
end

--- The saved interface alone, on this character: chat windows, Edit Mode, game settings, which bars
--- show and the camera, each as its switch on Character setup says. No action button and no macro is
--- touched. The game settings it changes are kept for /ysetup undo; chat windows and the Edit Mode
--- layout are not something an addon can put back.
function YS:ApplyInterface()
    if InCombatLockdown() then YS.Print("not in combat.") return end
    local ui = YS:SharedUI()
    if not ui then
        YS.Print("no interface saved yet: on the character whose interface you want, Copy interface (Headstart, Character setup).")
        return
    end
    -- its own copy to undo, apart from the bars' (an older Set up's bars are not what this undoes)
    YippSetupCharDB.uiBackup = { at = time() }
    YS:ApplyUI(ui, YS:Options())
    if YR.RefreshWindow then YR:RefreshWindow() end
end

-- Set the class's saved layout (the bar planner, Planner.lua).
function YS:SetProfile(profile, class)
    ClassData(class or PlayerClass()).profile = profile
end

function YS:Options(class)
    local o = ClassData(class or PlayerClass()).options
    -- A class set up for the first time gets "Only spells": no macros, so no text on the buttons and no
    -- macro limit to run into. One that already has options (the old placeholders switch was filled in
    -- the first time they were read) keeps the question marks it has been getting.
    if o.spellButtons == nil and o.placeholders == nil then o.spellButtons = "spells" end
    for k, v in pairs(OPTION_DEFAULTS) do if o[k] == nil then o[k] = v end end
    return o
end

-- What a class spell's button is (option spellButtons):
--   "placeholder"  the spell once known; until then a question-mark macro in its slot (the default)
--   "spells"       only the spell itself: the slot waits empty and the spell goes in when it is learned
--   "macros"       a "#showtooltip /cast" macro for every class spell, known or not, never swapped -
--                  one macro per button, so it runs into the character's macro limit sooner
-- Options saved before this have only the placeholders switch, which decides between the first two.
function YS.SpellButtons(o)
    local v = o.spellButtons
    if v == "placeholder" or v == "spells" or v == "macros" then return v end
    return o.placeholders == false and "spells" or "placeholder"
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
YS.PlayerKey = function() return PlayerKey() end

--------------------------------------------------------------------------------
-- Scan
--------------------------------------------------------------------------------

-- Macro actions: read the macro through its name, not GetActionInfo's id, which is not always the index.
local MacroFor       -- below, with Apply: Copy uses it to know the macros Headstart made for a spell

local function ReadMacroSlot(slot, id)
    local mname = GetActionText(slot)
    local idx = (mname and GetMacroIndexByName(mname)) or id
    if not idx or idx == 0 then return nil end
    local name, icon, body = GetMacroInfo(idx)
    if not name then return nil end
    return { kind = "macro", name = name, icon = icon, body = body }
end

-- Attack and the weapon spells (Throw, Shoot, Shoot Bow ...) this class can have: on no class skill line,
-- so they were dropped from a copied layout. From the game's data (Data/PlannerSpells.lua).
local function General(name)
    local _, class = UnitClass("player")
    return name and ((YR.PlannerGeneral or {})[class] or {})[name] ~= nil
end
YS.General = General

-- Class spells up to the level limit, racials (Stoneform: every character has them from level 1),
-- profession spells (placed on the new character once learned) and your own macros (AutoFeed's
-- included). Items are left out.
--- What is on this character's bars now, as a layout's slots: { [slot] = entry }, and the counts.
--- (Scan saves it; the bar planner starts from it and checks a plan against it.)
--- withOther (the planner): a button a layout can't hold - a mount, a toy, a pet's, an equipment set,
--- a spell from outside the class - is there too, as { kind = "other" }: it can't be saved or put on
--- another character, but it is on the bar, and nothing may take it for an empty slot.
function YS.ReadBars(withOther)
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
                    -- A lower rank than your best on the bar is an old button, not a choice: a spell is
                    -- kept at a rank only where you set one in the bar planner (down, kept from the
                    -- saved layout below). The bar's rank is noted so the planner can tell it's behind.
                    local best = C_Spell.GetSpellInfo(name)
                    if best and best.spellID ~= id then entry.stale, entry.rankID = true, id end
                elseif lvl then
                    n.later = n.later + 1
                elseif General(name) then
                    entry = { kind = "spell", name = name, general = true }
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
            else
                if not (kind == "spell" and lvl) then n.other = n.other + 1 end
                if withOther then
                    local texture = _G.C_ActionBar and _G.C_ActionBar.GetActionTexture or _G.GetActionTexture
                    slots[slot] = { kind = "other", name = tostring(kind or "?") .. ":" .. tostring(id or "?"),
                        icon = texture and texture(slot) or nil }
                end
            end
        end
    end
    return slots, n
end

--- Which wins where your bars and the class's saved layout hold different things in one slot:
---   "bars"     there is no saved layout (the plan is your bars, as they are); or this character was
---              set up from it, or it was copied from this character - then the bars ARE that layout,
---              lived in, and a button you moved by hand since is what you want
---   "profile"  there is a saved layout and this character never had it put on: what is on its bars
---              is what the game put there as you learned it, and the class's plan is the plan
function YS.PlanPrefers()
    local old = YS:Profile()
    if not (old and old.slots and next(old.slots)) then return "bars" end
    if YippSetupCharDB and YippSetupCharDB.applied then return "bars" end
    if old.from == PlayerKey() and not old.planned then return "bars" end
    return "profile"
end

local function SameButton(a, b)
    if a.kind ~= b.kind then return false end
    if a.kind == "item" then return a.id == b.id end
    return a.name == b.name
end

--- The bar planner's start: your bars and the saved layout laid over each other. Where only one of
--- them has something, that is it (the spells planned for later levels; a button the layout doesn't
--- know). Where both have something different, `prefer` wins ("bars" or "profile"; left out, see
--- YS.PlanPrefers). A question-mark macro Headstart made for a saved spell counts as that spell.
--- Returns the plan's slots, the slots as the bars alone have them (to tell what you take off), how
--- many slots the two disagree on, and which of them won.
function YS.PlanStart(prefer)
    if prefer ~= "bars" and prefer ~= "profile" then prefer = YS.PlanPrefers() end
    local now = YS.ReadBars(true)
    local plan, differ = {}, 0
    for slot, e in pairs(now) do plan[slot] = e end
    local old = YS:Profile()
    for slot, was in pairs(old and old.slots or {}) do
        local here = now[slot]
        if not here then
            plan[slot] = was
        elseif here.kind == "spell" and was.kind == "spell" and here.name == was.name and was.down then
            plan[slot] = was                -- the rank you set for it stays set
        elseif here.kind == "macro" and was.kind == "spell" and not was.prof and here.body == select(3, MacroFor(was)) then
            plan[slot] = was
        elseif not SameButton(here, was) then
            differ = differ + 1
            if prefer == "profile" then plan[slot] = was end
        end
    end
    return plan, now, differ, prefer
end

function YS:Scan()
    local maxLevel = SCAN_LEVEL
    local _, class = UnitClass("player")
    local slots, n = YS.ReadBars()
    -- Copied on a character still levelling, over a layout saved for more (planned to 60, or copied from
    -- a main): what this one can't have yet stays as it was saved. A slot that's empty here keeps a class
    -- spell above this level; a question-mark macro (or a spell macro) Headstart made for a saved spell is
    -- that spell, not a new macro of yours. Everything else is what's on the bars now.
    local old = ClassData(class).profile
    local myLevel = UnitLevel("player") or 1
    local kept = 0
    if old and old.slots then
        for slot = 1, MAX_SLOT do
            local was, now = old.slots[slot], slots[slot]
            if was and was.kind == "spell" and not was.prof and not was.general then
                if now and now.kind == "spell" and now.name == was.name and was.down then
                    slots[slot] = was          -- the rank you set for it in the planner stays set
                elseif not now and (was.level or 1) > myLevel then
                    slots[slot], kept = was, kept + 1
                elseif now and now.kind == "macro" and now.body == select(3, MacroFor(was)) then
                    slots[slot] = was
                    n.macro, n.spell = n.macro - 1, n.spell + 1
                end
            end
        end
    end
    ClassData(class).profile = { from = PlayerKey(), class = class, maxLevel = maxLevel, scanned = time(), slots = slots }
    YS:SaveSharedUI()
    Print(("saved %s: %d spells, %d profession spells, %d macros and %d items%s. What goes onto a new character is"
        .. " chosen in Headstart, Character setup."):format(PlayerKey(), n.spell, n.prof, n.macro, n.item,
        kept > 0 and (", and kept %d spells from the saved layout for levels you haven't reached"):format(kept) or ""))
end

--------------------------------------------------------------------------------
-- Apply
--------------------------------------------------------------------------------

-- Your choices for the new character.
local REPLACE = {}   -- e.g. ["Seal of Fury"] = "Seal of Righteousness": that spell goes in this one's slot
-- Spells cast on your mouseover target (else yourself or your target): a list in the options.
local mouseoverText, mouseoverSet
local function MOUSEOVER_SET(o)
    local text = (o or YS:Options()).mouseover or ""
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

--- The rank a downranked button is kept at (a number), or nil. Saved with it (e.rank); a button saved
--- before that has only the rank's spell ID, which the planner's rank list turns back into a number.
local function RankNumber(e)
    if not (e.down and e.id) then return nil end
    if e.rank then return e.rank end
    for _, r in ipairs(YR.PlannerRanks and YR.PlannerRanks(e.name) or {}) do
        if r.id == e.id then return r.rank end
    end
    local sub = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(e.id)
    return tonumber(type(sub) == "string" and sub:match("(%d+)") or "")
end
YS.RankNumber = RankNumber

-- The icon the plan has for a spell (the game's data: the spell needn't be known), or nil.
local function PlanIcon(spell)
    local _, class = UnitClass("player")
    local d = ((YR.PlannerSpells or {})[class] or {})[spell] or ((YR.PlannerGeneral or {})[class] or {})[spell]
        or (YR.PlannerRacials or {})[spell]
    return type(d) == "table" and d[2] or nil
end
YS.PlanIcon = PlanIcon
local Unlearned         -- (set below, where a known spell is told from one that isn't)

function MacroFor(e)
    if e.kind == "spell" then
        local spell = REPLACE[e.name] or e.name
        -- a downranked button casts that rank, as a macro too: "Holy Light(Rank 2)"
        local rank = spell == e.name and RankNumber(e)
        local what = rank and ("%s(Rank %d)"):format(spell, rank) or spell
        local cast = MOUSEOVER_SET()[spell] and ("/cast [@mouseover,help,nodead][] " .. what) or ("/cast " .. what)
        return ShortName(spell), (Unlearned(spell) and PlanIcon(spell)) or DYNAMIC_ICON, "#showtooltip " .. what .. "\n" .. cast
    end
    -- your own macros: no "(Rank 3)", so a spell always casts its highest known rank
    local body = (e.body or ""):gsub("%s*%(Rank %d+%)", "")
    return e.name, e.icon or DYNAMIC_ICON, body
end
YS.MacroFor = MacroFor      -- for tests

-- The spell's ID when this character knows it, else nil.
local function KnownSpellID(name)
    local info = C_Spell.GetSpellInfo(name)
    local id = info and info.spellID
    if id and IsPlayerSpell(id) then return id end
end

Unlearned = function(spell) return not KnownSpellID(spell) end

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
    if type(ids) == "number" then return IsPlayerSpell(ids) and ids or nil end       -- the one spell of that name
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
-- o: the options, when the caller has them (asked for once for a whole layout, not once a button).
local function RealSpell(e, o)
    if e.kind ~= "spell" then return nil end
    if e.prof then return ProfessionSpellID(e) end
    local spell = REPLACE[e.name] or e.name
    if MOUSEOVER_SET(o)[spell] then return nil end
    -- macros for everything: a class spell stays its macro, learned or not (racials and Attack too)
    if YS.SpellButtons(o or YS:Options()) == "macros" then return nil end
    -- a downranked slot: the main's rank once known; until then this character's best, which is lower
    if e.down and spell == e.name and IsPlayerSpell(e.id) then return e.id end
    return KnownSpellID(spell)
end

-- Whether the options carry this saved button over. levels: this class's spell levels; autofeed:
-- AutoFeed's macro names.
local function Wanted(e, levels, autofeed, o, myLevel)
    if not e then return false end
    if e.kind == "spell" then
        if e.prof then return o.professions end
        if e.general or General(e.name) then return o.classSpells end
        if e.racial or YS.RACIALS[e.name] then return o.racials end
        local lvl = e.level or levels[e.name]
        return lvl ~= nil and o.classSpells and lvl <= (myLevel or UnitLevel("player") or 1) + AHEAD
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

-- On a character that was set up before (changing the plan mid-levelling, say), only Headstart's own
-- question-mark macros go: "#showtooltip <spell>" + "/cast", with the question-mark icon - the ones still
-- needed are made again below. Every macro you made yourself on this character stays.
local function ClearPlaceholders()
    local _, numChar = GetNumMacros()
    local base = Constants.MacroConsts.MAX_ACCOUNT_MACROS
    local removed = 0
    for i = base + numChar, base + 1, -1 do
        local name, icon, body = GetMacroInfo(i)
        local spell = type(body) == "string" and body:match("^#showtooltip ([^\n]+)\n/cast ")
        if name and spell and (icon == DYNAMIC_ICON or icon == PlanIcon((spell:gsub("%(Rank %d+%)$", "")))) then
            DeleteMacro(i)
            removed = removed + 1
        end
    end
    return removed
end

-- An existing macro (account or character) with the same body is reused, so applying twice
-- doesn't duplicate anything and your general macros aren't copied into character slots.
--- Every macro's index by its body (an account macro wins over a character one), read in one pass.
local function MacroIndex()
    local numAccount, numChar = GetNumMacros()
    local base = Constants.MacroConsts.MAX_ACCOUNT_MACROS
    local index = {}
    for i = base + numChar, base + 1, -1 do
        local body = select(3, GetMacroInfo(i))
        if body then index[body] = i end
    end
    for i = numAccount, 1, -1 do
        local body = select(3, GetMacroInfo(i))
        if body then index[body] = i end
    end
    return index
end

-- Blizzard drops every newly learned spell onto the first empty bar slot; with the bars set up from the
-- main that only makes duplicates. Turned off on every set-up character (the setting may be per character).
local function NoAutoPush()
    local cur = C_CVar.GetCVar("AutoPushSpellToActionBar")
    if cur == nil then return false end
    if cur ~= "0" then C_CVar.SetCVar("AutoPushSpellToActionBar", "0") end
    return true
end

--- How many character macros a layout takes with these options, and the game's limit (30 a character on
--- Forever, MacroConstants). Each different macro counts once: your own macros, mouseover spells, and the
--- class spells your Spell buttons choice makes into macros (all of them, or only those not learned
--- yet). One that an account macro already is costs nothing: Set up uses that one.
function YS:MacrosNeeded(p, o, class)
    class = class or select(2, UnitClass("player"))
    p, o = p or YS:Profile(class), o or YS:Options(class)
    local limit = Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_CHARACTER_MACROS or 30
    if not (p and p.slots) then return 0, limit end
    local levels, autofeed = YS.SPELL_LEVELS[class] or {}, AutoFeedNames()
    local mode = YS.SpellButtons(o)
    local bodies = {}
    for _, e in pairs(p.slots) do
        if Wanted(e, levels, autofeed, o, 1) then        -- as a new character would get it
            local body
            if e.kind == "macro" then
                body = select(3, MacroFor(e))
            elseif e.kind == "spell" and not e.prof then
                local mouseover = MOUSEOVER_SET()[REPLACE[e.name] or e.name]
                if mouseover or mode == "macros" or (mode == "placeholder" and not RealSpell(e)) then
                    body = select(3, MacroFor(e))
                end
            end
            if body then bodies[body] = true end
        end
    end
    local n, accountMax = 0, Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS or 120
    local index = next(bodies) and MacroIndex() or {}
    for body in pairs(bodies) do
        local idx = index[body]
        if not (idx and idx <= accountMax) then n = n + 1 end
    end
    return n, limit
end

-- This character's own macros (not AutoFeed's): { { name, icon, body }, ... }.
local function CharacterMacros()
    local out, keep = {}, AutoFeedOwned()
    local _, numChar = GetNumMacros()
    local base = Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS or 120
    for i = base + 1, base + (numChar or 0) do
        local name, icon, body = GetMacroInfo(i)
        if name and not keep[name] then out[#out + 1] = { name, icon, body } end
    end
    return out
end

--- What a full Set up would take from this character as it is now: buttons on its bars, and macros of
--- its own that would be deleted. (0, 0 on a new character.)
function YS:ApplyCost(force)
    local p = YS:Profile() or (force and YippSetupDB.profile)
    if not p then return 0, 0 end
    local o = YS:Options()
    local buttons, macros = 0, 0
    if o.clearBars then
        for slot = 1, MAX_SLOT do if HasAction(slot) then buttons = buttons + 1 end end
    end
    local own = p and p.planned == true and type(p.from) == "string" and p.from:sub(1, #PlayerKey()) == PlayerKey()
    if o.clearMacros and YippSetupCharDB.applied == nil and not own then macros = #CharacterMacros() end
    return buttons, macros
end

-- A character in play, not a new one: Set up asks first, and offers the bars alone.
local NEW_LEVEL, NEW_BUTTONS = 10, 12
StaticPopupDialogs["YIPPSETUP_CONFIRM"] = {
    text = "Headstart: Set up layout on this character replaces what is on it now.\n\n%s\n\nA copy of your bars and"
        .. " macros is kept: /ysetup undo puts them back.",
    button1 = "Set up everything",
    button2 = "Cancel",
    button3 = "Bars only",
    OnAccept = function(_, force) YS:Apply(force, nil, { sure = true }) end,
    OnAlt = function(_, force) YS:Apply(force, nil, { sure = true, barsOnly = true }) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

--- Put the saved layout on the bars. force: another class's layout. only (the planner, on a character
--- in play): { [slot] = true } - nothing but these slots is touched: the bars aren't cleared, no macro
--- of yours is deleted, the interface is left alone, and one of these slots with nothing saved for it
--- is emptied. how: { sure = asked and answered, barsOnly = the bars and Headstart's own question
--- marks, but none of your macros deleted and no interface, chat or settings changed }.
function YS:Apply(force, only, how)
    if InCombatLockdown() then
        Print("can't change action bars in combat.")
        return
    end
    how = how or {}
    -- A character in play has things to lose: asked first, with what goes.
    if not only and not how.sure then
        local buttons, macros = YS:ApplyCost(force)
        local level = UnitLevel("player") or 1
        if (YS:Profile() or (force and YippSetupDB.profile)) and (level > NEW_LEVEL or macros > 0 or buttons > NEW_BUTTONS) then
            local o = YS:Options()
            local lines = {}
            if buttons > 0 then lines[#lines + 1] = ("%d buttons come off your bars"):format(buttons) end
            if macros > 0 then lines[#lines + 1] = ("%d of this character's macros are deleted"):format(macros) end
            if o.settings or o.editMode or o.chat or o.barVisibility then
                lines[#lines + 1] = "game settings, Edit Mode and chat windows change (Bars only leaves them)"
            end
            -- the data goes in as an argument: a field written on Blizzard's popup would be ours (tainted)
            StaticPopup_Show("YIPPSETUP_CONFIRM", table.concat(lines, "; ") .. ".", nil, force)
            return
        end
    end
    local _, class = UnitClass("player")
    -- force: another class's layout (the last one saved before layouts were per class)
    local p = YS:Profile() or (force and YippSetupDB.profile)
    if not p then
        Print(("no layout saved for %s yet. On your %s main, click Copy this layout (Headstart, Character setup)."
            .. " /ysetup apply force uses another class's."):format(class:lower(), class:lower()))
        return
    end
    local o = YS:Options()
    -- before anything goes: the bars and this character's macros as they are, for /ysetup undo
    if not only then
        YippSetupCharDB.backup = { at = time(), slots = (YS.ReadBars(true)), macros = CharacterMacros() }
        YippSetupCharDB.uiBackup = nil
    end
    if o.clearBars and not only then ClearBars() end
    -- which slots hold a spell we put there: a slot you empty yourself afterwards is left empty
    local placedSet = only and YippSetupCharDB.placed or {}
    YippSetupCharDB.placed = placedSet
    local autofeed = AutoFeedNames()
    local again = YippSetupCharDB.applied ~= nil
    local removed = 0
    -- A plan made on this very character is put on a character that has macros of its own: only the
    -- question-mark macros Headstart made go, never yours. (A layout from another character is for a
    -- new one, whose first Set up clears the character's macros to make room.)
    local own = p.planned == true and type(p.from) == "string" and p.from:sub(1, #PlayerKey()) == PlayerKey()
    -- (with `only`, the question marks stay too: the ones on the slots left alone are still in use)
    if o.clearMacros and not only then
        removed = (again or own or how.barsOnly) and ClearPlaceholders() or ClearCharacterMacros(AutoFeedOwned())
    end
    local levels = YS.SPELL_LEVELS[class] or {}
    local made, placed, full, noAutoFeed, askedAutoFeed = 0, 0, nil, nil, 0
    local macros      -- MacroIndex(), read again after each macro made
    for slot = 1, MAX_SLOT do
        local e = p.slots[slot]
        if not Wanted(e, levels, autofeed, o) then e = nil end
        if only and not only[slot] then
            e = nil                 -- not one of the slots to touch: left exactly as it is
        elseif only and HasAction(slot) then
            PickupAction(slot)      -- one of them: what was there goes, then what's saved (if anything) goes in
            ClearCursor()
        end
        if not only or only[slot] then placedSet[slot] = nil end
        local idx
        local spellID = e and (levels[e.name] or YS.RACIALS[e.name] or e.prof or e.general) and RealSpell(e)
        if spellID then
            PlaceSpell(slot, spellID)
            placedSet[slot] = true
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
                if own then askedAutoFeed, macros = askedAutoFeed + 1, nil end
            end
            if own and own > 0 then idx = own else noAutoFeed = e.name end
        -- a layout saved by an older version can still hold items and non-class spells
        -- a spell's macro: in the two macro modes, and always for a mouseover spell (that IS a macro)
        elseif e and (e.kind == "macro" or (e.kind == "spell" and not e.prof
                and (YS.SpellButtons(o) ~= "spells" or MOUSEOVER_SET()[REPLACE[e.name] or e.name])
                and (levels[e.name] or YS.RACIALS[e.name] or e.general))) then
            local name, icon, body = MacroFor(e)
            macros = macros or MacroIndex()
            idx = macros[body]
            if not idx then
                local ok, res = pcall(CreateMacro, name, icon, body, true)   -- per-character
                if ok and res then
                    idx, made = res, made + 1
                    macros = nil      -- character macros are kept sorted: their indexes just moved
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
    -- the layout as it went on, kept for this character: spells learned later go by it, whatever
    -- another character of the class saves afterwards
    YippSetupCharDB.layout = Copy(p.slots)
    Print(("placed %d buttons from %s (%d new macros, %d %s removed).")
        :format(placed, p.from, made, removed, again and "unused question-mark macros" or "old character macros"))
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
    -- The planner's apply and "Bars only" stop here: no game setting, Edit Mode, chat window, camera
    -- or RestedXP guide is touched on a character in play.
    if only or how.barsOnly then return end
    if o.noAutoPush and not NoAutoPush() then
        Print("this client has no setting for Blizzard placing new spells on the bars, so it may still add duplicates.")
    end
    YS:ApplyUI(YS:SharedUI(), o)
end

--- /ysetup undo: the bars and this character's macros as they were before the last Set up. Buttons a
--- layout can't hold (a mount, a toy, a pet's) can't be put back by an addon: those slots are said.
function YS:Undo()
    if InCombatLockdown() then Print("can't change action bars in combat.") return end
    -- "Apply interface" was the last thing done: that alone is undone, and the bars stay as they are
    local uiOnly = YippSetupCharDB.uiBackup
    if uiOnly then
        local settings = 0
        for name, v in pairs(uiOnly.cvars or {}) do if pcall(C_CVar.SetCVar, name, v) then settings = settings + 1 end end
        YippSetupCharDB.uiBackup = nil
        Print(("put back %d game settings as they were. Chat windows and the Edit Mode layout aren't something an addon can put back."):format(settings))
        if YR.RefreshWindow then YR:RefreshWindow() end
        return
    end
    local b = YippSetupCharDB.backup
    if not b then Print("nothing to undo: no Set up has been done on this character since the copy was kept.") return end
    local made = 0
    for _, m in ipairs(b.macros or {}) do
        local have
        local idx = GetMacroIndexByName(m[1])
        if idx and idx > 0 and select(3, GetMacroInfo(idx)) == m[3] then have = true end
        if not have and pcall(CreateMacro, m[1], m[2], m[3], true) then made = made + 1 end
    end
    ClearBars()
    local index = MacroIndex()
    local back, lost = 0, 0
    for slot = 1, MAX_SLOT do
        local e = b.slots and b.slots[slot]
        if e and e.kind == "spell" then
            local id = (e.stale and e.rankID and IsPlayerSpell(e.rankID) and e.rankID) or (e.prof and ProfessionSpellID(e))
                or KnownSpellID(e.name)
            if id then PlaceSpell(slot, id) back = back + 1 else lost = lost + 1 end
        elseif e and e.kind == "macro" then
            local idx = index[e.body]
            if idx then
                PickupMacro(idx)
                PlaceAction(slot)
                ClearCursor()
                back = back + 1
            else
                lost = lost + 1
            end
        elseif e and e.kind == "item" then
            local pickup = (C_Item and C_Item.PickupItem) or PickupItem
            pickup(e.id)
            PlaceAction(slot)
            ClearCursor()
            back = back + 1
        elseif e then
            lost = lost + 1
        end
    end
    local settings = 0
    for name, v in pairs(b.cvars or {}) do if pcall(C_CVar.SetCVar, name, v) then settings = settings + 1 end end
    YippSetupCharDB.applied, YippSetupCharDB.layout, YippSetupCharDB.placed, YippSetupCharDB.backup = nil, nil, nil, nil
    Print(("put back %d buttons, %d macros and %d game settings as they were before the last Set up.%s"):format(back, made, settings,
        lost > 0 and (" %d buttons couldn't be put back by an addon (mounts, toys, pet buttons and the like)."):format(lost) or ""))
    if YR.RefreshWindow then YR:RefreshWindow() end
end

-- A spell just learned: its placeholder macro is swapped for the spell itself and then deleted; a
-- profession spell (it has no placeholder) goes into its slot if that is still empty; a new rank
-- replaces the old rank in the main's slot for that spell.
-- Only on a character that was set up, and never in combat (it waits for combat to end).
local waiting = false
function YS:Upgrade()
    local o = YS:Options()
    if not (YippSetupCharDB.applied and o.swap) then return end
    -- the layout as it went on this character (kept since; before that, the class's saved layout)
    local slots = YippSetupCharDB.layout or (YS:Profile() or {}).slots
    if not slots then return end
    YippSetupCharDB.placed = YippSetupCharDB.placed or {}
    local put = YippSetupCharDB.placed
    if InCombatLockdown() then
        waiting = true
        return
    end
    if GetCursorInfo and GetCursorInfo() then
        C_Timer.After(2, function() YS:Upgrade() end)
        return
    end
    waiting = false
    local swapped = {}
    local _, class = UnitClass("player")
    local levels, autofeed = YS.SPELL_LEVELS[class] or {}, AutoFeedNames()
    for slot, e in pairs(slots) do
        local id = Wanted(e, levels, autofeed, o) and RealSpell(e, o)
        if put[slot] and not HasAction(slot) then
            -- it was there and you took it off: left off
        elseif id and not HasAction(slot) then
            -- just learned, and nothing holds its slot (it was too far ahead when the layout went on,
            -- or question-mark buttons are off): straight in
            PlaceSpell(slot, id)
            put[slot] = true
        elseif not id and not HasAction(slot) and e.kind == "spell" and not e.prof
                and Wanted(e, levels, autofeed, o) and KnownSpellID(REPLACE[e.name] or e.name) then
            -- learned, and its button is a macro by your choices (a mouseover spell, or macros for
            -- every spell): the macro, made now
            local name, icon, body = MacroFor(e)
            local idx = MacroIndex()[body]
            if not idx then
                local ok, res = pcall(CreateMacro, name, icon, body, true)
                idx = ok and res or nil
            end
            if idx then
                PickupMacro(idx)
                PlaceAction(slot)
                ClearCursor()
                put[slot] = true
            end
        elseif id and HasAction(slot) then
            local kind, actionID = GetActionInfo(slot)
            local m = kind == "macro" and ReadMacroSlot(slot, actionID)
            if m and m.body == select(3, MacroFor(e)) then
                PlaceSpell(slot, id)
                put[slot] = true
                swapped[m.name] = m.body
            -- a new rank from the trainer: a spell on the bar is that rank only, so the slot gets the
            -- highest one, or for a downranked slot the main's rank (RealSpell)
            elseif kind == "spell" and actionID ~= id and not e.prof
                    and C_Spell.GetSpellName(actionID) == C_Spell.GetSpellName(id) then
                PlaceSpell(slot, id)
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
    local w = S.Window("YippSetupFrame", 560, 146, "Set up this character")
    w:ClearAllPoints()
    w:SetPoint("CENTER", 0, 120)
    w.info = S.Text(w, 13, S.C.sub)
    w.info:SetPoint("TOPLEFT", 20, -62)
    w.info:SetWidth(520)
    w.info:SetWordWrap(true)
    w.info:SetSpacing(3)

    -- Only a deliberate click marks this character as done. Escape (which also skips the intro
    -- cinematic) just hides the window, so it comes back on the next login.
    local function Done() YippSetupCharDB.seen = CharacterID() or true end
    -- Set up is instant (a new character wants to get going); Copy first shows every choice of what
    -- carries over (Settings, Character tab), and is done from there
    -- applied: the window has done its job and goes. In a fight nothing can go on the bars yet, so it
    -- stays (Apply says why) and the character isn't marked done.
    w.setup = S.Button(w, "Apply to this character", function()
        if InCombatLockdown() then YS:Apply() return end
        Done()
        YS:Apply()
        w:Hide()
    end, "primary")
    w.setup:SetPoint("BOTTOMRIGHT", -16, 16)
    w.setup.tip = "On a new character: put the saved layout on this one, now"
    w.copy = S.Button(w, "Copy this layout...", function()
        Done()
        w:Hide()
        YR:ShowSettingsTab("setup")
    end)
    w.copy:SetPoint("RIGHT", w.setup, "LEFT", -8, 0)
    w.copy.tip = "On your main: see what a new character will get, then copy this one's bars, macros and settings"
    -- No main to copy from: build the bars here, with every spell of the class at any level.
    w.plan = S.Button(w, "Plan my bars...", function()
        Done()
        w:Hide()
        YR.OpenPlanner()
    end)
    w.plan:SetPoint("BOTTOMLEFT", 16, 16)
    w.plan.tip = "Drag every spell your class will have onto your bars now, and save it as this class's layout"
    w.close:HookScript("OnClick", Done)
    return w
end

function YS:Refresh()
    if not window then return end
    local p = YS:Profile()
    local class = PlayerClass():lower()
    if not p then
        window.info:SetText(("No %s layout saved yet. Plan one now with every %s spell, or on your %s main"
            .. " click Copy this layout."):format(class, class, class))
    else
        window.info:SetText(("Saved %s layout: |cffffffff%s|r.%s"):format(class, YS:Describe(p) or p.from,
            YS:SharedUI() and "" or "\n|cffff8040No interface saved yet: Copy this layout on a character set up the"
                .. " way you like it.|r"))
    end
    window.setup:SetEnabled(p ~= nil and p.from ~= PlayerKey())
    -- The planner is the way in when there's nothing saved; with a layout it's in Settings, Character.
    window.plan:SetShown(p == nil or p.planned == true)
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
    -- for a new character: one already in play isn't offered a layout over its own (it's in Settings)
    if (UnitLevel("player") or 1) > NEW_LEVEL then return end
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
    local ui = YS:SharedUI()
    C_Timer.After(1, function() YS.ApplyCamera(ui and ui.camera or 15) end)
end
YS.FirstZoom = FirstZoom

-- A layout copied before Edit Mode, bars and settings were saved has no ui part. Logging in on the
-- character it was copied from fills it in, so the bars aren't copied again just for that.
local function FillInUI()
    local p = YS:Profile()
    if p and not YS:SharedUI() and p.from == PlayerKey() then
        YS:SaveSharedUI()
        YS:Refresh()
        Print("saved this character's Edit Mode layout, chat, action bars and game settings as the account's interface.")
    end
end

--------------------------------------------------------------------------------
-- Slash command and events
--------------------------------------------------------------------------------

--- /ysetup debug: what a Set up layout would do on this character, in a few lines to copy from chat.
function YS:Debug()
    local _, class = UnitClass("player")
    local p, o = YS:Profile(), YS:Options()
    local levels, autofeed = YS.SPELL_LEVELS[class] or {}, AutoFeedNames()
    Print(("debug: %s level %d. Buttons are made up to level %d. Options: buttons %s, clear bars %s, clear macros %s, class spells %s."):format(
        tostring(class), UnitLevel("player") or 0, (UnitLevel("player") or 1) + AHEAD, YS.SpellButtons(o), tostring(o.clearBars),
        tostring(o.clearMacros), tostring(o.classSpells)))
    if not p then Print("debug: no layout saved for this class.") return end
    local saved, wanted, known, tooHigh = 0, 0, 0, 0
    for _, e in pairs(p.slots or {}) do
        saved = saved + 1
        if Wanted(e, levels, autofeed, o) then
            wanted = wanted + 1
            if e.kind == "spell" and RealSpell(e) then known = known + 1 end
        elseif e.kind == "spell" and (e.level or levels[e.name]) then
            tooHigh = tooHigh + 1
        end
    end
    local now = 0
    for slot = 1, MAX_SLOT do if HasAction(slot) then now = now + 1 end end
    Print(("debug: layout from %s%s: %d buttons saved; %d would go on (%d of them spells you know), %d class spells"
        .. " wait for a later level. On your bars now: %d buttons. Last applied: %s."):format(
        tostring(p.from), p.planned and " (planned)" or "", saved, wanted, known, tooHigh, now,
        YippSetupCharDB.applied and date("%d %b %H:%M", YippSetupCharDB.applied) or "never"))
end

SLASH_YIPPSETUP1 = "/ysetup"
SlashCmdList.YIPPSETUP = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
    if cmd == "scan" then
        YS:Copy()
    elseif cmd == "debug" then
        YS:Debug()
    elseif cmd == "undo" then
        YS:Undo()
    elseif cmd == "ui" or cmd == "interface" then
        if arg == "copy" then YS:CopyInterface() else YS:ApplyInterface() end
    elseif cmd == "apply" then
        YS:Apply(arg == "force")
    else
        YS:Toggle()
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("SPELLS_CHANGED")        -- a spell learned (it also fires for much else, in bursts)
f:RegisterEvent("PLAYER_REGEN_ENABLED")
local upgradeSoon = false
local function UpgradeSoon()
    -- a character never set up has nothing to keep up: nothing is set going (this is every spell change)
    if upgradeSoon or not (YippSetupCharDB and YippSetupCharDB.applied) then return end
    upgradeSoon = true          -- a burst (training five spells, a login) costs one pass
    C_Timer.After(0.2, function() upgradeSoon = false if YippSetupCharDB then YS:Upgrade() end end)
end
f:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "PLAYER_ENTERING_WORLD" and (arg1 or arg2) then   -- login or reload only
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        SkipIntro()
        C_Timer.After(0.5, FirstZoom)
        C_Timer.After(2, FirstTimeHere)
        C_Timer.After(3, FillInUI)
        if YippSetupCharDB.applied and YS:Options().noAutoPush and not InCombatLockdown() then NoAutoPush() end
    elseif event == "SPELLS_CHANGED" or (event == "PLAYER_REGEN_ENABLED" and waiting) then
        UpgradeSoon()
    end
end)

--- Called by Headstart once this addon's files are in (Core.lua, YR.LoadSetup). fresh: this is the
--- character's first login with Headstart (the saved tables themselves are made by Headstart).
--- The macros already waiting on your bars with a question mark, for spells you haven't learned:
--- given the spell's icon. Once a login, out of a fight. Returns how many.
function YS.PlaceholderIcons()
    if InCombatLockdown() or not (GetNumMacros and EditMacro) then return 0 end
    local _, numChar = GetNumMacros()
    local base = Constants.MacroConsts.MAX_ACCOUNT_MACROS
    local done = 0
    for i = base + 1, base + (numChar or 0) do
        local name, icon, body = GetMacroInfo(i)
        local spell = name and icon == DYNAMIC_ICON and type(body) == "string" and body:match("^#showtooltip ([^\n]+)\n/cast ")
        spell = spell and spell:gsub("%(Rank %d+%)$", "")
        local to = spell and Unlearned(spell) and PlanIcon(spell)
        -- (a macro's place in the list is by its name: giving it an icon doesn't move it)
        if to and pcall(EditMacro, i, nil, to, nil) then done = done + 1 end
    end
    return done
end

function YS.Start(fresh)
    if YippSetupCharDB and YippSetupCharDB.applied then
        C_Timer.After(4, function() YS.PlaceholderIcons() end)
    end
    -- a new character: the main's action bars now, so Blizzard shows them while logging in
    local level = UnitLevel("player") or 0
    if fresh and level <= 1 and YS.EarlyBars then
        YippSetupCharDB.earlyBars = YS.EarlyBars()
    end
end

-- the intro starting while we are loaded (see SkipIntro)
local intro = CreateFrame("Frame")
intro:RegisterEvent("CINEMATIC_START")
intro:RegisterEvent("PLAY_MOVIE")
intro:RegisterEvent("CINEMATIC_STOP")
intro:SetScript("OnEvent", function(_, event)
    if event == "CINEMATIC_STOP" then C_Timer.After(0.5, FirstZoom) else C_Timer.After(0, SkipIntro) end
end)
