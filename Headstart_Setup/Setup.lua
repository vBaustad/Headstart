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

-- A macro's text as the game gives it has a line break at its end that wasn't written: the two lines
-- of a Sap macro come back as three, the last one empty. Every macro Headstart made was told from one
-- of yours by its text, so none of them was ever recognised - not swapped for its spell when you
-- learned it, saved into a plan as a macro of yours, made a second time. Read without what trails it,
-- everywhere.
local function GetMacroInfo(i)
    local name, icon, body = _G.GetMacroInfo(i)
    if type(body) == "string" then body = body:gsub("%s+$", "") end
    return name, icon, body
end
YS.MacroInfo = GetMacroInfo

local DYNAMIC_ICON = 134400     -- the question mark; #showtooltip shows the real icon once the spell is known
-- A spell you haven't learned yet waits in its slot as a macro with the question mark: a red "?" until
-- the spell is known. (For a while such a macro was given the spell's own icon. A bar of real-looking
-- icons that do nothing when pressed is worse than a bar of question marks: you can't tell what you
-- have. Those are put back, YS.PlaceholderIcons. "Only spells" in the settings is the other choice:
-- no macro at all, the slot empty until the spell is learned.)
local MAX_SLOT = 180
local SCAN_LEVEL = 60           -- Copy saves every spell
-- How far ahead of your level a class spell gets its button now (a question-mark macro until it is
-- learned). Every spell at or under your level is placed, the next levels' wait as question marks,
-- and the rest keep their slot empty and go in when you learn them. How many levels ahead is the
-- class's option "ahead" (10; 0: no question marks beyond what you could train now) - counted from
-- your level, so it never takes a later spell off a character's bars (the absolute "Class spells up
-- to level" it once was did).
--   A spell a talent gives (YS.TALENTS, the game's data) is never a question mark: you may never
-- take it, and a button that does nothing for thirty levels - or for ever - is a macro wasted. It
-- keeps its slot and goes in when you learn it. Its level is where its row in the tree can be
-- reached, not what the game's spell data says (1, for most of them).
local AHEAD = 10
local function Ahead(o)
    local n = o and tonumber(o.ahead)
    return n and math.max(0, math.min(60, n)) or AHEAD
end
YS.Ahead = Ahead
local function Talent(name)
    local _, class = UnitClass("player")
    return ((YS.TALENTS or {})[class] or {})[name] ~= nil
end
YS.IsTalent = Talent

-- What Set up carries over. Every part has a switch in Settings, Character tab.
local OPTION_DEFAULTS = {
    classSpells = true, maxLevel = 10, placeholders = true, racials = true, professions = true,
    mouseover = "Purify",
    macros = true, autofeed = true, items = false,
    clearBars = true, clearMacros = true,
    settings = true, editMode = true, barVisibility = true, guide = true, noAutoPush = true,
    swap = true, rankUp = true, popup = true, skipIntro = true, chat = true, camera = true, keys = true,
    graphics = true,
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

YS.ClassData = ClassData

-- A class can have more bar layouts than one (Layouts.lua): a warrior's for tanking and one for damage.
-- The class's first is where it always was, classes[CLASS].profile (named by profileName, "Main");
-- the others are classes[CLASS].layouts[name]. Which one a character is on is the character's own
-- (YippSetupCharDB.layoutName; none: the first), so two warriors can be on different ones.
local function OwnLayout(class)
    if class ~= PlayerClass() then return nil end
    local name = YippSetupCharDB and YippSetupCharDB.layoutName
    local c = ClassData(class)
    if name and type(c.layouts) == "table" and c.layouts[name] then return name end
    return nil
end

--- The saved layout for a class (this character's if none is given) - the one this character is on - or nil.
function YS:Profile(class)
    if not YippSetupDB then return nil end
    class = class or PlayerClass()
    local c = ClassData(class)
    local name = OwnLayout(class)
    if name then return c.layouts[name] end
    return c.profile
end

-- The interface - chat windows and tabs, Edit Mode, game settings, raid frames, camera, which bars show -
-- is the account's, not a class's: set it up once on any character and every class gets it. Save
-- interface saves it; the bars stay per class. From before (2026-10-02) each class's layout carried
-- its own: the newest one copied from a real character (not a plan, which only ever held a level-1
-- character's defaults) becomes the account's, once.
--
-- An interface has a name ("Main", "Healer"), and a character is on one of them. Kept as:
--   YippSetupDB.ui, .uiFrom, .uiScanned   the one new characters get, named YippSetupDB.uiName ("Main"
--                                         unless renamed) - where an older Headstart reads it too
--   YippSetupDB.uis[name] = { ui, from, scanned }      the others
--   YippSetupCharDB.iface = { name, seen, sig }        the one this character is on; seen: the save of
--       it this character has (put on, or made here); sig: how this character's own screen read then
-- from: the character that saved it last. Every character on an interface saves into it when you
-- change something there (leaving Edit Mode, logging out; YippSetupDB.uiFollow, on unless turned off).
-- "Changed" is this character's screen reading differently from sig - not from the saved one, which
-- two characters never read quite alike. A character whose interface was saved somewhere else since
-- (seen is not the save's time) doesn't save over it: the window asks which of the two to keep.
local MAIN = "Main"
local function Legacy()
    if YippSetupDB.ui == nil and not YippSetupDB.uiMoved then
        YippSetupDB.uiMoved = true
        local best
        for _, c in pairs(YippSetupDB.classes or {}) do
            local p = c.profile
            if p and p.ui and not p.planned and (not best or (p.scanned or 0) > (best.scanned or 0)) then best = p end
        end
        if best then YippSetupDB.ui, YippSetupDB.uiFrom, YippSetupDB.uiScanned = best.ui, best.from, best.scanned end
    end
end

function YS.UIDefault() return YippSetupDB and YippSetupDB.uiName or MAIN end

--- An interface by name (none: the one new characters get): what is saved, who saved it, when.
function YS.UIRecord(name)
    if not YippSetupDB then return nil end
    Legacy()
    if name == nil or name == YS.UIDefault() then
        if YippSetupDB.ui == nil then return nil end
        return YippSetupDB.ui, YippSetupDB.uiFrom, YippSetupDB.uiScanned
    end
    local r = YippSetupDB.uis and YippSetupDB.uis[name]
    if r then return r.ui, r.from, r.scanned end
    return nil
end

local function UIPut(name, ui, from, scanned)
    -- a name given anew is not the one that was renamed away
    if YippSetupDB.uiRenamed then YippSetupDB.uiRenamed[name] = nil end
    -- the first one saved is the one new characters get, whatever it is called
    if YippSetupDB.ui == nil and not (YippSetupDB.uis and next(YippSetupDB.uis)) then YippSetupDB.uiName = name end
    if name == YS.UIDefault() then
        -- the one before is kept too: a save made on the wrong character doesn't lose the good one
        if YippSetupDB.ui then
            YippSetupDB.uiPrev = { ui = YippSetupDB.ui, from = YippSetupDB.uiFrom, scanned = YippSetupDB.uiScanned }
        end
        YippSetupDB.ui, YippSetupDB.uiFrom, YippSetupDB.uiScanned = ui, from, scanned
        YippSetupDB.uiMoved = true
    else
        YippSetupDB.uis = YippSetupDB.uis or {}
        YippSetupDB.uis[name] = { ui = ui, from = from, scanned = scanned }
    end
end

--- Every saved interface's name: the one new characters get first, the rest by name.
function YS.UINames()
    local out = {}
    if not YippSetupDB then return out end
    for name in pairs(YippSetupDB.uis or {}) do out[#out + 1] = name end
    table.sort(out)
    if YS.UIRecord() then table.insert(out, 1, YS.UIDefault()) end
    return out
end

-- This character's saved table, with the interface it is on. The character the account's one
-- interface came from, before interfaces had names, is on that one.
local function Char()
    local c = _G.YippSetupCharDB
    if type(c) ~= "table" or not YippSetupDB then return nil end
    if c.iface == nil and not c.ifaceAsked then
        c.ifaceAsked = true         -- once: a character that left its interface since is not put back on it
        if YippSetupDB.ui and YippSetupDB.uiFrom == YS.PlayerKey() then
            c.iface = { name = YS.UIDefault(), seen = YippSetupDB.uiScanned }
        end
    end
    -- renamed on another character since this one was here
    local to = c.iface and YippSetupDB.uiRenamed and YippSetupDB.uiRenamed[c.iface.name]
    if to and not YS.UIRecord(c.iface.name) then c.iface.name = to end
    return c
end

--- The interface this character uses: the one it is on, or the one new characters get.
function YS.UIName()
    local c = Char()
    if c and c.iface and YS.UIRecord(c.iface.name) then return c.iface.name end
    return YS.UIDefault()
end
--- Whether this character is on its interface: it has been put on here, or was saved here.
function YS.UIOn()
    local c = Char()
    return c ~= nil and c.iface ~= nil and c.iface.seen ~= nil and YS.UIRecord(c.iface.name) ~= nil
end
function YS:SharedUI() return (YS.UIRecord(YS.UIName())) end
function YS.UISource() return (select(2, YS.UIRecord(YS.UIName()))) end
function YS.UIScanned() return (select(3, YS.UIRecord(YS.UIName()))) end
function YS.UIFollows() return not (YippSetupDB and YippSetupDB.uiFollow == false) end

-- A few game settings are the class's, not the account's (YS.CLASS_CVARS, SetupUI.lua): whether the
-- Personal Resource Display is on - a rogue wants its energy and combo points under the character, a
-- paladin may not. Kept as YippSetupDB.classes[CLASS].cvars[name], beside the class's bars.
--   * Save interface writes them all, as this character has them.
--   * One you change on a character of the class is saved when you leave Edit Mode or log out. Only
--     what changed since login (or since they were last put on): a new character's defaults never
--     overwrite what the class has.
--   * Apply interface puts them on with the other game settings.
local classAt           -- how they read on this character when last looked at
function YS.ScanClassUI()
    local out = {}
    for _, name in ipairs(YS.CLASS_CVARS or {}) do
        local v = C_CVar.GetCVar(name)
        if v ~= nil then out[name] = v end
    end
    return out
end
--- The class's saved settings (this character's class if none is given), or nil.
function YS.ClassUI(class)
    if not YippSetupDB then return nil end
    return ClassData(class or PlayerClass()).cvars
end
function YS.SaveClassUI()
    if not YippSetupDB then return end
    classAt = YS.ScanClassUI()
    ClassData(PlayerClass()).cvars = Copy(classAt)
end
--- Noted as they are now (login, and after they were put on): the next change is counted from here.
function YS.ClassUINoted() classAt = YS.ScanClassUI() end
--- What changed on this character since they were noted, saved for the class. Returns whether any did.
function YS.FollowClassUI()
    if not YippSetupDB then return false end
    local now = YS.ScanClassUI()
    local was, changed = classAt, false
    classAt = now
    if not (was and YS.UIFollows()) then return false end
    for name, v in pairs(now) do
        if was[name] ~= nil and was[name] ~= v then
            local c = ClassData(PlayerClass())
            c.cvars = c.cvars or {}
            c.cvars[name] = v
            changed = true
        end
    end
    return changed
end

-- How a screen reads, as one number: everything saved but the camera (it moves all the time).
local function Sig(ui)
    local parts = {}
    local function Walk(v, depth, under)
        local t = type(v)
        if t == "table" then
            local keys, names = {}, true
            for k, item in pairs(v) do
                keys[#keys + 1] = k
                if type(k) ~= "number" or type(item) ~= "string" then names = false end
            end
            if names and #keys > 0 then
                -- a list of names (a chat window's groups and channels): the same whatever its order
                local list = {}
                for _, item in pairs(v) do list[#list + 1] = item end
                table.sort(list)
                parts[#parts + 1] = "[" .. table.concat(list, ",") .. "]"
                return
            end
            table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
            parts[#parts + 1] = "{"
            for _, k in ipairs(keys) do
                -- not the camera or the data's version; not RestedXP's window sizes, two of which it
                -- changes by itself at every step of a guide; not graphics and sound, which every
                -- character on this install has already (a volume turned down is not a changed screen)
                if not (depth == 0 and (k == "camera" or k == "v" or k == "machine")) and not (depth == 1 and under == "rxp" and k == "sizes") then
                    parts[#parts + 1] = tostring(k) .. "="
                    Walk(v[k], depth + 1, k)
                end
            end
            parts[#parts + 1] = "}"
        elseif t == "number" then
            parts[#parts + 1] = ("%.2f;"):format(v)
        else
            parts[#parts + 1] = tostring(v) .. ";"
        end
    end
    Walk(ui, 0)
    local text = table.concat(parts)
    local h = 5381
    for i = 1, #text do h = (h * 33 + text:byte(i)) % 4294967296 end
    return h
end
YS.UISig = Sig

--- Whether this character's interface was saved somewhere else since this character had it; and
--- then who saved it, and when.
function YS.UIBehind()
    local c = Char()
    if not (c and YS.UIOn()) then return false end
    local _, from, scanned = YS.UIRecord(c.iface.name)
    if scanned == c.iface.seen then return false end
    return true, from, scanned
end

--- This character's screen saved into its interface, quietly, when something on it changed. Returns
--- whether it was. The first look after an interface was put on only notes how the screen reads.
function YS.FollowUI()
    YS.FollowClassUI()
    local c = Char()
    if not (c and YS.UIOn() and YS.UIFollows()) or InCombatLockdown() then return false end
    if YS.UIBehind() then return false end
    -- just put on, and not looked at since: a reload usually comes first, and the screen as it is in
    -- between is not what the player made (noted at the next login, UISettle)
    if c.iface.fresh then return false end
    local ok, ui = pcall(YS.ScanUI, YS)
    if not ok or type(ui) ~= "table" then return false end
    if YS.KeepUnapplied then ui = YS.KeepUnapplied(ui, (YS.UIRecord(c.iface.name))) end
    local sig = Sig(ui)
    if c.iface.sig == nil then c.iface.sig = sig return false end
    if sig == c.iface.sig then return false end
    local now = time()
    UIPut(c.iface.name, ui, YS.PlayerKey(), now)
    c.iface.seen, c.iface.sig = now, sig
    return true
end

-- An interface was put on this character: it is on that one now, at that save. How the screen reads
-- is noted once it has settled (a reload usually comes first).
local function Settle()
    local c = Char()
    if not (c and c.iface and c.iface.seen ~= nil and (c.iface.fresh or c.iface.sig == nil)) or InCombatLockdown() then return end
    if not YS.UIRecord(c.iface.name) then return end
    local ok, ui = pcall(YS.ScanUI, YS)
    if not ok or type(ui) ~= "table" then return end
    if YS.KeepUnapplied then ui = YS.KeepUnapplied(ui, (YS.UIRecord(c.iface.name))) end
    c.iface.sig, c.iface.fresh = Sig(ui), nil
end
YS.UISettle = Settle
function YS.UIApplied()
    local c = Char()
    if not c then return end
    local name = YS.UIName()
    local _, _, scanned = YS.UIRecord(name)
    if scanned == nil then return end
    c.iface = { name = name, seen = scanned, fresh = true }
end

--- This character uses that interface from now on. Nothing is put on by it: Apply interface does that.
function YS.UIPick(name)
    local c = Char()
    if not (c and YS.UIRecord(name)) then return false, "no such interface." end
    if not (c.iface and c.iface.name == name) then c.iface = { name = name } end
    return true
end

local function CleanName(name)
    return (strtrim(tostring(name or "")):gsub("%s+", " ")):sub(1, 24)
end

--- New characters get that one from now on.
function YS.UISetDefault(name)
    local old = YS.UIDefault()
    if name == old then return true end
    local r = YippSetupDB.uis and YippSetupDB.uis[name]
    if not r then return false, "no such interface." end
    YippSetupDB.uis[name] = nil
    if YippSetupDB.ui then
        YippSetupDB.uis[old] = { ui = YippSetupDB.ui, from = YippSetupDB.uiFrom, scanned = YippSetupDB.uiScanned }
    end
    YippSetupDB.ui, YippSetupDB.uiFrom, YippSetupDB.uiScanned, YippSetupDB.uiName = r.ui, r.from, r.scanned, name
    return true
end

function YS.UIRename(old, new)
    new = CleanName(new)
    if new == "" then return false, "it needs a name." end
    if new == old then return true end
    if YS.UIRecord(new) then return false, ("there is an interface called %s already."):format(new) end
    if not YS.UIRecord(old) then return false, "no such interface." end
    if old == YS.UIDefault() then
        YippSetupDB.uiName = new
    else
        YippSetupDB.uis[new], YippSetupDB.uis[old] = YippSetupDB.uis[old], nil
    end
    -- the other characters on it find it again by this (their own tables can't be reached from here)
    YippSetupDB.uiRenamed = YippSetupDB.uiRenamed or {}
    for from, to in pairs(YippSetupDB.uiRenamed) do
        if to == old then YippSetupDB.uiRenamed[from] = new end
    end
    YippSetupDB.uiRenamed[old], YippSetupDB.uiRenamed[new] = new, nil
    local c = Char()
    if c and c.iface and c.iface.name == old then c.iface.name = new end
    return true
end

function YS.UIDelete(name)
    if name == YS.UIDefault() then return false, "new characters get this one: pick another for them first." end
    if not (YippSetupDB.uis and YippSetupDB.uis[name]) then return false, "no such interface." end
    YippSetupDB.uis[name] = nil
    local c = Char()
    if c and c.iface and c.iface.name == name then c.iface = nil end
    return true
end

StaticPopupDialogs["YIPPSETUP_UI_REPLACE"] = {
    text = "Headstart: the interface %s was last saved on %s.\n\nReplace it with this character's? Every character on it is"
        .. " asked whether to take the change. (To keep both, save this one under a new name instead.)",
    button1 = "Replace", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(_, name) YS:SaveInterface(name, true) end,
}

--- This character's interface saved under a name (none: the interface it uses): chat windows, Edit
--- Mode, game settings, which bars show, the camera, RestedXP's look. No action button or macro is
--- read. The character is on that interface from then on. Saving over one this character isn't on,
--- or one saved elsewhere since, asks first (sure: asked and answered).
function YS:SaveInterface(name, sure)
    name = CleanName(name)
    if name == "" then name = YS.UIName() end
    local c = Char()
    if not c then return end
    local has, from = YS.UIRecord(name)
    local mine = c.iface ~= nil and c.iface.name == name and c.iface.seen ~= nil and not YS.UIBehind()
    if has and not mine and from ~= YS.PlayerKey() and not sure then
        StaticPopup_Show("YIPPSETUP_UI_REPLACE", name, tostring(from or "another character"), name)
        return
    end
    local ui, now = YS:ScanUI(), time()
    UIPut(name, ui, YS.PlayerKey(), now)
    YS.SaveClassUI()
    c.iface = { name = name, seen = now, sig = Sig(ui) }
    YS.Print(("saved this character's interface as |cffffffff%s|r (chat windows, Edit Mode, game settings, which bars show, camera,"
        .. " RestedXP's look). It is kept up to date from every character that uses it."):format(name))
    if YR.RefreshWindow then YR:RefreshWindow() end
    YS:Refresh()
end
function YS:CopyInterface(sure) return YS:SaveInterface(nil, sure) end
function YS:SaveSharedUI()
    local c = Char()
    local ui, now = YS:ScanUI(), time()
    UIPut(YS.UIDefault(), ui, YS.PlayerKey(), now)
    YS.SaveClassUI()
    if c then c.iface = { name = YS.UIDefault(), seen = now, sig = Sig(ui) } end
end

--- The interface this character uses, put on it: chat windows, Edit Mode, game settings, which bars
--- show and the camera, each as its switch on Character setup says. No action button and no macro is
--- touched. The game settings it changes are kept for /ysetup undo; chat windows and the Edit Mode
--- layout are not something an addon can put back.
function YS:ApplyInterface()
    if InCombatLockdown() then YS.Print("not in combat.") return end
    local ui = YS:SharedUI()
    if not ui then
        YS.Print("no interface saved yet. Use Save interface on the character whose interface you want (/hs, Character setup).")
        return
    end
    -- its own copy to undo, apart from the bars' (an older Set up's bars are not what this undoes).
    -- One copy for however many times it is applied: a new one each time recorded what the last apply
    -- had already made of things, and what you had before the first was gone.
    local kept = YippSetupCharDB.uiBackup
    if type(kept) ~= "table" then
        kept = { at = time() }
        YippSetupCharDB.uiBackup = kept
    end
    kept.last = time()
    YS.UIApplied()
    YS:ApplyUI(ui, YS:Options())
    if YR.RefreshWindow then YR:RefreshWindow() end
    return true
end

-- Asked first, from the settings and the slash command: this is the one that can't all be put back.
-- (The first-login window and the "changed elsewhere" window are questions already.)
StaticPopupDialogs["YIPPSETUP_INTERFACE"] = {
    text = "Headstart: put the saved interface on this character?\n\nIt changes your chat windows (a chat tab the saved"
        .. " interface doesn't have is closed), the Edit Mode layout, which action bars show, your key bindings, game"
        .. " settings, and graphics and sound, each as its switch on this page says. No action button and no macro is"
        .. " touched.\n\nGame settings, graphics, sound and key bindings can be put back (/ysetup undo). Chat windows and the"
        .. " Edit Mode layout can't be put back by an addon.",
    button1 = "Apply interface",
    button2 = "Cancel",
    OnAccept = function() YS:ApplyInterface() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}
function YS:AskInterface()
    if InCombatLockdown() then YS.Print("not in combat.") return end
    if not YS:SharedUI() then return YS:ApplyInterface() end        -- (nothing saved: it says so)
    StaticPopup_Show("YIPPSETUP_INTERFACE")
end

-- Set the class's saved layout (the bar planner, Planner.lua).
function YS:SetProfile(profile, class)
    class = class or PlayerClass()
    local c = ClassData(class)
    local name = OwnLayout(class)
    if name then c.layouts[name] = profile else c.profile = profile end
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

-- The choices that decide what is on your bars. Changing one changes nothing on a character until
-- the layout is put on it again (a question mark already on a bar stays there when you choose "Only
-- spells"): so the choices as they were at the last Apply are kept with the character, and the page
-- says when they have changed since.
local BAR_CHOICES = { "classSpells", "spellButtons", "ahead", "racials", "professions", "macros", "mouseover", "autofeed", "items" }
local function Choices(o)
    local t = {}
    for _, k in ipairs(BAR_CHOICES) do t[k] = o[k] end
    t.spellButtons = YS.SpellButtons(o)
    t.ahead = YS.Ahead(o)
    return t
end
--- Note the choices as put on this character now (Apply does).
function YS.ChoicesApplied() YippSetupCharDB.choices = Choices(YS:Options()) end
--- Whether the choices have changed since the layout was last put on this character. (A character
--- set up before this was kept: taken as up to date, from now.)
function YS.ChoicesPending()
    local c = YippSetupCharDB
    if not (c and c.applied) then return false end
    local now = Choices(YS:Options())
    if type(c.choices) ~= "table" then
        c.choices = now
        return false
    end
    for _, k in ipairs(BAR_CHOICES) do if c.choices[k] ~= now[k] then return true end end
    return false
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
    print("|cffff9a40Headstart|r: " .. msg)
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

-- A macro Headstart made for a spell - the question mark that waits for a spell you haven't learned,
-- or the macro a mouseover spell is - IS that spell, wherever your bars are read: saved as a macro of
-- yours it would stay a macro for ever, never swapped for the spell when you learn it, and it would be
-- listed among your macros in the plan. (It was read as the spell only where the saved layout already
-- had that spell in that very slot: a plan saved from bars with such macros on them kept them as
-- macros.) Told by its shape: named and written exactly as MacroFor makes it for a spell of your class.
local OwnSpellOf        -- (below, with MacroFor)

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
                elseif name and YS.ProfessionIDs(name) then
                    -- the exact spell and its icon: one name can be several spells (see ProfessionSpellID)
                    entry = { kind = "spell", name = name, prof = true, id = id, icon = C_Spell.GetSpellTexture(id) }
                end
            elseif kind == "macro" then
                entry = ReadMacroSlot(slot, id)
                local spell = entry and OwnSpellOf(entry)
                if spell then entry = spell end
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

local Unavailable        -- (below, where a known spell is told from one that isn't)

--- This character's bars saved as the layout it is on. (Copy this layout does it, with the interface;
--- leaving a layout for another does it by itself, Layouts.lua.) Returns the counts and how many
--- later spells were kept.
function YS:ScanBars()
    local maxLevel = SCAN_LEVEL
    local _, class = UnitClass("player")
    local slots, n = YS.ReadBars()
    -- Saved on a character still levelling, over a layout saved for more (planned to 60, or copied from
    -- a main): what this one can't have yet stays as it was saved. A button that is empty here keeps what
    -- was saved for it while this character hasn't got that thing - a spell it hasn't learned (too low,
    -- not trained yet, a talent not taken), a profession's spell, an item it isn't carrying, a macro it
    -- hasn't made. Empty where it HAS the thing is you taking it off: that goes. A question-mark macro
    -- (or a spell macro) Headstart made for a saved spell is that spell, not a new macro of yours.
    -- Everything else is what's on the bars now.
    local old = YS:Profile()
    local kept = 0
    if old and old.slots then
        for slot = 1, MAX_SLOT do
            local was, now = old.slots[slot], slots[slot]
            if was and not now then
                if Unavailable(was) then slots[slot], kept = was, kept + 1 end
            elseif was and was.kind == "spell" and not was.prof and not was.general then
                if now.kind == "spell" and now.name == was.name and was.down then
                    slots[slot] = was          -- the rank you set for it in the planner stays set
                elseif now.kind == "macro" and now.body == select(3, MacroFor(was)) then
                    slots[slot] = was
                    n.macro, n.spell = n.macro - 1, n.spell + 1
                end
            end
        end
    end
    YS:SetProfile({ from = PlayerKey(), class = class, maxLevel = maxLevel, scanned = time(), slots = slots,
        ownUI = old and old.ownUI or nil, ui = old and old.ui or nil })      -- (a profile's own interface stays its own)
    return n, kept
end

function YS:Scan()
    if YippSetupCharDB then YippSetupCharDB.hold = nil end          -- (said by hand: these bars are the profile)
    local n, kept = YS:ScanBars()
    -- the bars are this class's; the interface is the account's, and only the character it comes from
    -- changes it (saving a healer's bars used to make every new character's screen the healer's)
    if not YS:SharedUI() then YS:SaveSharedUI() else YS.FollowUI() end
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
        return ShortName(spell), DYNAMIC_ICON, "#showtooltip " .. what .. "\n" .. cast
    end
    -- Your own macros. A "(Rank 3)" you wrote stays where this character knows that very rank: it is
    -- a downrank you meant (it used to be taken out of every macro, and a downrank macro on a bar was
    -- swapped for a twin without its rank). Where the character doesn't know that rank - an alt
    -- below it - the rank goes, so the spell casts the highest one it has.
    local body = (e.body or ""):gsub("([^%]\n;]-)%s*%(Rank (%d+)%)", function(before, n)
        local spell = strtrim((before:gsub("^%s*[#/]%a+%s+", "")))
        for _, r in ipairs(YR.PlannerRanks and YR.PlannerRanks(spell) or {}) do
            if r.rank == tonumber(n) and IsPlayerSpell(r.id) then return before .. "(Rank " .. n .. ")" end
        end
        return before
    end):gsub("%s+$", "")
    return e.name, e.icon or DYNAMIC_ICON, body
end
YS.MacroFor = MacroFor      -- for tests

--- The spell a macro entry stands for, as a layout's entry, when the macro is one Headstart made for
--- a spell of your class (see ReadMacroSlot); nil for a macro of your own.
function OwnSpellOf(e)
    if not (e and e.kind == "macro" and type(e.body) == "string" and e.name) then return nil end
    local what = e.body:match("^#showtooltip ([^\n]+)\n/cast ")
    if not what then return nil end
    local spell, rank = what:match("^(.-)%(Rank (%d+)%)$")
    spell, rank = spell or what, tonumber(rank)
    local _, class = UnitClass("player")
    local level = (YS.SPELL_LEVELS[class] or {})[spell] or (YS.RACIALS[spell] and 1)
    local general = not level and ((YR.PlannerGeneral or {})[class] or {})[spell] ~= nil
    if not (level or general) then return nil end
    local entry = { kind = "spell", name = spell, level = level, racial = YS.RACIALS[spell] or nil, general = general or nil,
        down = rank and true or nil, rank = rank }
    local name, _, body = MacroFor(entry)
    if name ~= e.name or body ~= e.body then return nil end
    return entry
end
YS.OwnSpellOf = function(e) return OwnSpellOf(e) end

--- A saved layout put right: every macro in it that is one of Headstart's own for a spell becomes that
--- spell. Returns how many. (This class's layout, and the layout as it went onto this character.)
function YS.RepairLayouts()
    local done = 0
    for _, slots in ipairs({ (YS:Profile() or {}).slots or false, YippSetupCharDB and YippSetupCharDB.layout or false }) do
        if type(slots) == "table" then
            for slot, e in pairs(slots) do
                local spell = type(e) == "table" and OwnSpellOf(e)
                if spell then slots[slot], done = spell, done + 1 end
            end
        end
    end
    return done
end

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
    local ids = YS.ProfessionIDs(e.name)
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

-- Whether this character hasn't got what a saved button holds (so an empty button isn't it taken off).
function Unavailable(e)
    if e.kind == "spell" then
        if e.prof then return not ProfessionSpellID(e) end
        return not KnownSpellID(REPLACE[e.name] or e.name)
    elseif e.kind == "item" then
        local count = C_Item and C_Item.GetItemCount and e.id and C_Item.GetItemCount(e.id)
        return not count or count == 0
    elseif e.kind == "macro" then
        local index = e.name and GetMacroIndexByName(e.name)
        return not index or index == 0
    end
    return false
end

-- Whether the options carry this saved button over. levels: this class's spell levels; autofeed:
-- AutoFeed's macro names.
local function Wanted(e, levels, autofeed, o, myLevel)
    if not e then return false end
    if e.kind == "spell" then
        if e.prof then return o.professions end
        if e.general or General(e.name) then return o.classSpells end
        if e.racial or YS.RACIALS[e.name] then return o.racials end
        -- (the game's data first: the level saved with a button may be from before a patch moved the spell)
        local lvl = levels[e.name] or e.level
        return lvl ~= nil and o.classSpells and lvl <= (myLevel or UnitLevel("player") or 1) + Ahead(o)
    elseif e.kind == "macro" then
        if autofeed[e.name] then return o.autofeed end
        return o.macros
    elseif e.kind == "item" then
        -- "Items" off keeps a main's items off a character that hasn't got them. One this character is
        -- carrying is on its bars because you put it there (your hearthstone): that one always goes back
        if o.items then return true end
        local count = C_Item and C_Item.GetItemCount and e.id and C_Item.GetItemCount(e.id)
        return (count or 0) > 0
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
--- The macros Headstart made for spells, brought in line with your choices as they are now - without
--- setting the whole character up again. One your choices no longer want (you chose "Only spells"; it
--- is a talent's spell; it is further ahead than you ask for; nothing on your bars uses it) comes off
--- its buttons - the spell itself goes in where you know it, else the button is left empty for it -
--- and is deleted. A macro of your own is never touched. Returns how many were deleted.
function YS.TidyPlaceholders()
    if InCombatLockdown() then return 0 end
    local o = YS:Options()
    local mode = YS.SpellButtons(o)
    local _, class = UnitClass("player")
    local levels = YS.SPELL_LEVELS[class] or {}
    local myLevel = UnitLevel("player") or 1
    -- which of our macros each button holds
    local onBar = {}
    for slot = 1, MAX_SLOT do
        if HasAction(slot) then
            local kind, id = GetActionInfo(slot)
            local m = kind == "macro" and ReadMacroSlot(slot, id)
            if m and OwnSpellOf(m) then
                onBar[m.body] = onBar[m.body] or {}
                table.insert(onBar[m.body], slot)
            end
        end
    end
    local _, numChar = GetNumMacros()
    local base = Constants.MacroConsts.MAX_ACCOUNT_MACROS
    local removed = 0
    for i = base + (numChar or 0), base + 1, -1 do
        local name, _, body = GetMacroInfo(i)
        local e = name and OwnSpellOf({ kind = "macro", name = name, body = body })
        if e then
            local spell = REPLACE[e.name] or e.name
            local known = KnownSpellID(spell)
            local slots = onBar[body]
            local lvl = levels[e.name]
            local want = slots ~= nil and o.classSpells and (MOUSEOVER_SET(o)[spell] or mode == "macros"
                or (mode == "placeholder" and not known and not Talent(e.name) and (lvl == nil or lvl <= myLevel + Ahead(o))))
            if not want then
                for _, slot in ipairs(slots or {}) do
                    PickupAction(slot)
                    ClearCursor()
                    if known and not e.down then PlaceSpell(slot, known) ClearCursor() end
                end
                DeleteMacro(i)
                removed = removed + 1
            end
        end
    end
    return removed
end

local function ClearPlaceholders()
    local _, numChar = GetNumMacros()
    local base = Constants.MacroConsts.MAX_ACCOUNT_MACROS
    local removed = 0
    for i = base + numChar, base + 1, -1 do
        local name, icon, body = GetMacroInfo(i)
        -- only a macro that is exactly what Headstart makes for a spell of your class, name and text: a
        -- macro of your own that begins the same way ("#showtooltip Stealth" and "/cast !Stealth", one
        -- from the macro helper) is yours
        local own = name and OwnSpellOf({ kind = "macro", name = name, body = body })
        if name and not own and icon == DYNAMIC_ICON and type(body) == "string" then
            -- or one for a spell the class no longer has (renamed in a patch): the plain two lines for
            -- one spell, under the name Headstart gives it
            local a, b = body:match("^#showtooltip ([^\n]+)\n/cast ([^\n]+)$")
            own = a and a == b and name == ShortName((a:gsub("%(Rank %d+%)$", "")))
        end
        if own then
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
                -- (a talent's spell you haven't got waits as nothing: see the top of the file)
                local known = RealSpell(e)
                if (mouseover or mode == "macros" or (mode == "placeholder" and not known)) and (known or not Talent(e.name)) then
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

-- Before anything of yours is changed - by Set up, the planner or a switch of profile - the bars and
-- this character's macros are written down as they are (YippSetupCharDB, per character):
--   backup   the newest: what /ysetup undo puts back
--   older    the ones before it, newest first (four at most): undo again goes a step further back
--   first    this character as it was before Headstart changed anything on it. Kept for good,
--            whatever is applied after: /ysetup undo first. (One copy was all there was once, and a
--            second Set up overwrote the only record of the bars you had built by hand.)
-- Each also says whether the character counted as set up then (was), which undo puts back with it.
local OLDER = 4
--- This character's bars and its profile are not the same thing any more, and must not be made so by
--- the automatic save: a profile deleted under it, an undo, a plan saved but not put on, an apply that
--- stopped halfway. (Each of those left the bars to be written over the saved profile four seconds
--- later - the profile there was no other copy of.) Until the profile is applied or the bars are saved
--- to it by hand, which is you saying which of the two it is to be. Said once.
function YS.Hold(why)
    local c = YippSetupCharDB
    if type(c) ~= "table" or c.hold or not c.applied then return end
    c.hold = why or true
    Print("this character's bars are no longer saved into its profile by themselves (" .. tostring(why or "they differ from it")
        .. "): apply the profile, or save the bars to it, and they are again.")
end

local function Backup()
    local c = YippSetupCharDB
    local b = { at = time(), slots = (YS.ReadBars(true)), macros = CharacterMacros(),
        was = { applied = c.applied, layout = c.layout, placed = c.placed and Copy(c.placed) or nil,
            onLayout = c.layoutName or false } }       -- (the profile it was on: an undo goes back onto it)
    if c.backup then
        c.older = type(c.older) == "table" and c.older or {}
        table.insert(c.older, 1, c.backup)
        for i = #c.older, OLDER + 1, -1 do c.older[i] = nil end
    end
    c.backup = b
    if not c.first then c.first = Copy(b) end
    return b
end

-- A character in play, not a new one: Set up asks first, and offers the bars alone.
local NEW_LEVEL, NEW_BUTTONS = 10, 12
StaticPopupDialogs["YIPPSETUP_CONFIRM"] = {
    text = "Headstart: applying this profile replaces what is on this character now.\n\n%s\n\nYour bars and macros"
        .. " as they are now are kept, and /ysetup undo puts them back (not a mount, toy or pet button: an addon can't"
        .. " place those). Chat windows and the Edit Mode layout can't be put back by an addon -"
        .. " |cffffffffBars only|r leaves them as they are.",
    button1 = "Bars and interface",
    button2 = "Cancel",
    button3 = "Bars only",
    OnAccept = function(_, force) YS:Apply(force, nil, { sure = true }) end,
    OnAlt = function(_, force) YS:Apply(force, nil, { sure = true, barsOnly = true }) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- A character that has been set up before: the bars are what you come back for (a changed plan, a new
-- choice). Its interface you have made your own since - Edit Mode, another bar switched on, chat - and
-- the saved one is older than that: putting it back takes those changes away. So it is asked every
-- time, "Bars only" is the answer the Enter key gives, and "Everything" says how old the saved
-- interface is.
StaticPopupDialogs["YIPPSETUP_AGAIN"] = {
    text = "Headstart: this character was set up before.\n\n%s\n\n|cffffffffBars only|r applies the saved bars and keeps your"
        .. " interface as it is now.\n|cffffffffBars and interface|r also restores the saved interface (Edit Mode, visible"
        .. " bars, chat windows, game settings) as it was %s.\n\n/ysetup undo restores your bars and macros.",
    button1 = "Bars only",
    button2 = "Cancel",
    button3 = "Bars and interface",
    OnAccept = function(_, force) YS:Apply(force, nil, { sure = true, barsOnly = true }) end,
    OnAlt = function(_, force) YS:Apply(force, nil, { sure = true }) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    enterClicksFirstButton = true,
}

-- "Apply bars" (the first-login window) on a character in play: asked as what was asked for - the
-- bars alone - and not with a dialog whose first button is the interface too.
StaticPopupDialogs["YIPPSETUP_BARS"] = {
    text = "Headstart: put the saved bars on this character?\n\n%s\n\nYour bars and macros as they are now are kept, and"
        .. " /ysetup undo puts them back. Your interface, chat windows and game settings are not touched, and no macro"
        .. " of yours is deleted.",
    button1 = "Apply bars",
    button2 = "Cancel",
    OnAccept = function(_, force) YS:Apply(force, nil, { sure = true, barsOnly = true }) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    enterClicksFirstButton = true,
}

local function Ago(t)
    local s = time() - (tonumber(t) or 0)
    if not t or s < 0 then return "some time ago" end
    if s < 3600 then return "less than an hour ago" end
    if s < 7200 then return "an hour ago" end
    if s < 86400 then return ("%d hours ago"):format(s / 3600) end
    if s < 172800 then return "a day ago" end
    return ("%d days ago"):format(s / 86400)
end

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
    -- What you changed on your bars a moment ago is the profile's before the profile is put on (a
    -- button dragged out five seconds before you press Apply must not be what Apply takes away).
    if not only and not how.sure and YS.RememberNow then
        if YS.BarsStale then YS.BarsStale() end
        YS.RememberNow()
    end
    -- A character in play has things to lose: asked first, with what goes.
    if not only and not how.sure then
        local buttons, macros = YS:ApplyCost(force)
        local level = UnitLevel("player") or 1
        local again = YippSetupCharDB.applied ~= nil
        if (YS:Profile() or (force and YippSetupDB.profile)) and (again or level > NEW_LEVEL or macros > 0 or buttons > NEW_BUTTONS) then
            local o = YS:Options()
            local lines = {}
            if buttons > 0 then lines[#lines + 1] = ("%d buttons come off your bars"):format(buttons) end
            if how.barsOnly then
                StaticPopup_Show("YIPPSETUP_BARS", #lines > 0 and (lines[1] .. ".") or "The saved bars go on.", nil, force)
                return
            end
            if macros > 0 then lines[#lines + 1] = ("%d of this character's macros are deleted"):format(macros) end
            if again then
                local from = YS.UISource() and ("on " .. tostring(YS.UISource()) .. ", " .. Ago(YS.UIScanned())) or "when it was saved"
                StaticPopup_Show("YIPPSETUP_AGAIN", #lines > 0 and (table.concat(lines, "; ") .. ".") or "The saved bars go on.", from, force)
                return
            end
            if o.settings or o.editMode or o.chat or o.barVisibility then
                lines[#lines + 1] = "game settings, key bindings, Edit Mode and chat windows change (Bars only leaves them)"
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
    -- before anything goes: the bars and this character's macros as they are, for /ysetup undo. Also
    -- for the planner and a switch of profile (only): those change buttons too, and had no way back.
    Backup()
    -- (an apply that puts the interface on itself takes its copy into the bars' own, below; one that
    -- leaves the interface alone - Bars only, after Apply interface - must not throw that copy away:
    -- it is what /ysetup undo was promised to put back)
    if not only and not how.barsOnly then YippSetupCharDB.uiBackup = nil end
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
                and (levels[e.name] or YS.RACIALS[e.name] or e.general)
                -- (a talent's spell you haven't got waits as nothing: see the top of the file)
                and (not Talent(e.name) or KnownSpellID(REPLACE[e.name] or e.name)))) then
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
    if not only then YS.ChoicesApplied() end
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
    -- Blizzard's own placing of new spells is stopped by every apply, the bars-only ones too: it stayed
    -- on until the next login there, and each spell trained in that first session was placed twice.
    if o.noAutoPush and not NoAutoPush() and not (only or how.barsOnly) then
        Print("this client has no setting for Blizzard placing new spells on the bars, so it may still add duplicates.")
    end
    YippSetupCharDB.hold = nil
    if full then YS.Hold("the macro list was full, so not every button is on") end
    if only or how.barsOnly then return true, full end
    YS.UIApplied()
    YS:ApplyUI(YS:SharedUI(), o)
    -- the copy kept for good was taken before the interface went on: the game settings and keys that
    -- changed are part of what "as it was before Headstart" means (undo first put back none of them)
    local c = YippSetupCharDB
    if type(c.first) == "table" and type(c.backup) == "table" and c.first.at == c.backup.at then
        if c.first.cvars == nil and c.backup.cvars then c.first.cvars = Copy(c.backup.cvars) end
        if c.first.keys == nil and c.backup.keys then c.first.keys = Copy(c.backup.keys) end
    end
    return true, full
end

--- /ysetup undo: the bars and this character's macros as they were before the last change Headstart
--- made to them; again, the change before that. first (/ysetup undo first): as they were before
--- Headstart changed anything on this character. Buttons a layout can't hold (a mount, a toy, a
--- pet's) can't be put back by an addon: those slots are said.
---   Nothing is touched unless every macro it has to make again fits: the bars are cleared to put the
---   old ones back, and with the macro list full that used to leave them empty and the copy gone.
-- Game settings put back as they were. The two graphics quality presets first: setting a preset sets
-- everything under it, so each of those has to come after it. Returns how many were set.
local PRESETS = { "graphicsQuality", "raidGraphicsQuality" }       -- (as SetupUI.lua's MACHINE_CVARS spells them)
local function PutBack(cvars)
    local n = 0
    for _, name in ipairs(PRESETS) do
        if cvars[name] ~= nil and pcall(C_CVar.SetCVar, name, cvars[name]) then n = n + 1 end
    end
    for name, v in pairs(cvars) do
        if name ~= PRESETS[1] and name ~= PRESETS[2] and pcall(C_CVar.SetCVar, name, v) then n = n + 1 end
    end
    return n
end

function YS:Undo(first, bars)
    if InCombatLockdown() then Print("can't change action bars in combat.") return end
    -- "Apply interface" was the last thing done: that alone is undone, and the bars stay as they are
    -- (bars: the bars are what is asked for - a switch of profile taking itself back)
    local uiOnly = not first and not bars and YippSetupCharDB.uiBackup
    -- (only where it is the later of the two: an interface applied last week is not what undo means
    -- after the bars were changed today)
    local barsAt = type(YippSetupCharDB.backup) == "table" and YippSetupCharDB.backup.at or 0
    if uiOnly and (uiOnly.last or uiOnly.at or 0) < barsAt then uiOnly = nil end
    if uiOnly then
        local settings = PutBack(uiOnly.cvars or {})
        if uiOnly.keys and YS.ApplyKeys then YS.ApplyKeys(uiOnly.keys) end           -- and your keys as they were
        YippSetupCharDB.uiBackup = nil
        -- taken back: this character's screen is its own again, and is not saved into the interface
        if YippSetupCharDB.iface then YippSetupCharDB.iface = { name = YippSetupCharDB.iface.name } end
        Print(("put back %d game settings%s as they were. Chat windows and the Edit Mode layout aren't something an addon can put back."):format(
            settings, uiOnly.keys and " and your key bindings" or ""))
        if YR.RefreshWindow then YR:RefreshWindow() end
        return
    end
    local c = YippSetupCharDB
    local b = first and c.first or c.backup
    if not b then
        Print(first and "nothing to put back: Headstart has not changed this character's bars."
            or "nothing to undo: nothing has been applied to this character since the backup.")
        return
    end
    -- the macros it would have to make again, and whether they fit
    local function Has(m)
        local idx = GetMacroIndexByName(m[1])
        return idx and idx > 0 and select(3, GetMacroInfo(idx)) == m[3]
    end
    local need = 0
    for _, m in ipairs(b.macros or {}) do if not Has(m) then need = need + 1 end end
    local _, numChar = GetNumMacros()
    local limit = Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_CHARACTER_MACROS or 30
    local room = limit - (numChar or 0)
    if need > room then
        Print(("can't undo yet: %d of your macros have to be made again and this character has room for %d. Delete %d of its"
            .. " macros and undo again. Nothing was changed, and the copy is kept."):format(need, math.max(0, room), need - math.max(0, room)))
        return
    end
    local made, missing = 0, 0
    for _, m in ipairs(b.macros or {}) do
        if not Has(m) then
            -- (made or not is read off the count: the game hands a macro's text back with a line
            -- break of its own at the end, so the text is not what to compare)
            -- (and that line break is taken off again, or the macro made here would carry two)
            local _, had = GetNumMacros()
            pcall(CreateMacro, m[1], m[2], ((m[3] or ""):gsub("\n$", "")), true)
            local _, have = GetNumMacros()
            if (have or 0) > (had or 0) then made = made + 1 else missing = missing + 1 end
        end
    end
    if missing > 0 then
        Print(("can't undo: %d of your macros couldn't be made again. Your bars were not changed, and the copy is kept."):format(missing))
        return
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
    local settings = PutBack(b.cvars or {})
    if b.keys and YS.ApplyKeys then YS.ApplyKeys(b.keys) end                         -- and your keys as they were
    -- the character is what it was then: set up or not, on the layout it was on
    local was = b.was or {}
    c.applied, c.layout, c.placed = was.applied, was.layout, was.placed and Copy(was.placed) or nil
    -- back on the profile these bars were of (a switch of profile undone left the character on the new
    -- one wearing the old one's bars, which were then saved over the new one)
    if was.onLayout ~= nil then c.layoutName = was.onLayout or nil end
    YS.Hold("after an undo")
    if first then
        c.backup, c.older = nil, nil            -- (the first stays: it can be put back again)
    else
        c.backup = type(c.older) == "table" and table.remove(c.older, 1) or nil
    end
    Print(("put back %d buttons, %d macros and %d game settings as they were before %s.%s%s"):format(back, made, settings,
        first and "Headstart first changed this character" or "the last change",
        lost > 0 and (" %d buttons couldn't be put back by an addon (mounts, toys, pet buttons and the like)."):format(lost) or "",
        c.backup and " /ysetup undo again goes a step further back." or (not first and c.first)
            and " /ysetup undo first puts the bars back as they were before Headstart changed anything." or ""))
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
            put[slot] = id
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
                put[slot] = id
                swapped[m.name] = m.body
            -- a new rank from the trainer: a spell on the bar is that rank only, so the slot gets the
            -- highest one, or for a downranked slot the main's rank (RealSpell). Only where the button
            -- is still what Headstart put there (put[slot]: the spell it placed; true from before that
            -- was kept, its rank not known): a rank you dragged onto that slot yourself afterwards is
            -- a rank you chose, and is left.
            elseif kind == "spell" and actionID ~= id and not e.prof and put[slot] and (put[slot] == true or put[slot] == actionID)
                    and C_Spell.GetSpellName(actionID) == C_Spell.GetSpellName(id) then
                PlaceSpell(slot, id)
                put[slot] = id
            end
        end
    end
    for name, body in pairs(swapped) do
        local onBar = false
        for slot = 1, MAX_SLOT do
            if HasAction(slot) and GetActionText(slot) == name then onBar = true break end
        end
        -- (only one of this character's own: an account-wide macro of yours that happens to read like
        -- a placeholder was used as one, and is yours - it stays)
        local idx = GetMacroIndexByName(name)
        if not onBar and idx and idx > Constants.MacroConsts.MAX_ACCOUNT_MACROS and select(3, GetMacroInfo(idx)) == body then DeleteMacro(idx) end
    end
end

--------------------------------------------------------------------------------
-- The window: shown the first time each character logs in, and from the compartment or /ysetup
--------------------------------------------------------------------------------

StaticPopupDialogs["YIPPSETUP_OVERWRITE"] = {
    text = "Headstart: this profile already has saved bars (%s).\n\nReplace them with this character's current bars?"
        .. " Buttons planned for spells you haven't learned are kept.",
    button1 = "Replace",
    button2 = "Cancel",
    OnAccept = function() YS:Scan() YS:Refresh() YR:RefreshWindow() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

--- Copy this layout. Asked first whenever the class has a saved layout with anything in it - a plan
--- you made, another character's bars, or this one's from before: it is replaced.
function YS:Copy()
    local p = YS:Profile()
    if p and type(p.slots) == "table" and next(p.slots) then
        local n = 0
        for _ in pairs(p.slots) do n = n + 1 end
        StaticPopup_Show("YIPPSETUP_OVERWRITE", ("%s, %d buttons"):format(p.planned and "a plan you made" or ("from " .. tostring(p.from or "?")), n))
    else
        self:Scan()
        self:Refresh()
    end
end

local window

-- The first-time window: two choices, in Headstart's own look.
local function BuildWindow()
    local w = S.Window("YippSetupFrame", 640, 176, "Set up this character")
    w:ClearAllPoints()
    w:SetPoint("CENTER", 0, 120)
    -- Two things, in the order you would do them: the interface (Edit Mode, chat, game settings - the
    -- same for every class), then this class's bars. Each has its line and its button.
    w.ui = S.Text(w, 13, S.C.sub)
    w.ui:SetPoint("TOPLEFT", 20, -62)
    w.ui:SetWidth(600)
    w.ui:SetWordWrap(false)
    w.info = S.Text(w, 13, S.C.sub)
    w.info:SetPoint("TOPLEFT", 20, -84)
    w.info:SetWidth(600)
    w.info:SetWordWrap(false)

    -- Only a deliberate click marks this character as done. Escape (which also skips the intro
    -- cinematic) just hides the window, so it comes back on the next login.
    local function Done() YippSetupCharDB.seen = CharacterID() or true end
    -- Both saved and both still to do: one click, and one reload at the end.
    w.both = S.Button(w, "Apply both", function()
        if InCombatLockdown() then YS:Apply() return end
        if YS:Apply() then
            Done()
            YippSetupCharDB.uiApplied = CharacterID() or true
        end
        w:Hide()            -- (asked first, on a character with things to lose: the question has the screen)
    end, "primary", 110)
    w.both:SetPoint("BOTTOMLEFT", 16, 16)
    w.both.tip = "Puts this class's saved bars and macros on this character, then the saved interface. One reload at the end"
    -- The interface alone. The character isn't marked done by it: applying it often ends in a reload,
    -- and the window is back after that with the bars still to do (YippSetupCharDB.uiApplied).
    w.applyUI = S.Button(w, "Apply interface", function()
        if InCombatLockdown() then YS:ApplyInterface() return end
        if YS:ApplyInterface() then
            YippSetupCharDB.uiApplied = CharacterID() or true
            -- nothing left for the window to offer (the bars saved for the class are this character's own)
            local p = YS:Profile()
            if p and p.from == PlayerKey() and not p.planned then Done() end
        end
        YS:Refresh()
    end, nil, 130)
    w.applyUI.tip = "Puts your saved Edit Mode layout, chat windows and game settings on this character. Bars are not touched"
    -- No main to copy from: build the bars here, with every spell of the class at any level.
    w.plan = S.Button(w, "Plan bars...", function()
        Done()
        w:Hide()
        YR.OpenPlanner()
    end, nil, 110)
    w.plan:SetPoint("LEFT", w.applyUI, "RIGHT", 8, 0)
    w.plan.tip = "Opens the bar planner: put any spell your class can learn on a button, and save it as this class's profile"
    -- applied: the window has done its job and goes. In a fight nothing can go on the bars yet, so it
    -- stays (Apply says why) and the character isn't marked done.
    w.setup = S.Button(w, "Apply bars", function()
        if InCombatLockdown() then YS:Apply(nil, nil, { barsOnly = true }) return end
        if YS:Apply(nil, nil, { barsOnly = true }) then Done() end
        w:Hide()
    end, nil, 110)
    w.setup:SetPoint("BOTTOMRIGHT", -16, 16)
    w.setup.tip = "Puts this class's saved bars and macros on this character"
    w.copy = S.Button(w, "Settings...", function()
        Done()
        w:Hide()
        YR:ShowSettingsTab("setup")
    end, nil, 100)
    w.copy:SetPoint("RIGHT", w.setup, "LEFT", -8, 0)
    w.copy.tip = "Character setup: profiles, what Apply brings along, and Save interface on the character you want it from"
    w.close:HookScript("OnClick", Done)
    -- more than one interface saved: which one this character gets
    w.pick = S.Dropdown(w, 150, function()
        local out = {}
        for _, name in ipairs(YS.UINames()) do out[#out + 1] = { name, name } end
        return out
    end, function(name)
        YS.UIPick(name)
        YS:Refresh()
    end)
    w.pick:SetPoint("TOPRIGHT", -20, -56)
    -- The window's other job: this character's interface was changed on another character. Two answers
    -- (the X is "not now": it asks again next login, and nothing is saved over until one is given).
    w.update = S.Button(w, "Update", function()
        if not InCombatLockdown() then w:Hide() end
        YS:ApplyInterface()
    end, "primary", 110)
    w.update:SetPoint("BOTTOMLEFT", 16, 16)
    w.update.tip = "Puts the changed interface on this character"
    w.keep = S.Button(w, "Keep this character's", function()
        w:Hide()
        YS:SaveInterface(YS.UIName(), true)
    end, nil, 170)
    w.keep:SetPoint("LEFT", w.update, "RIGHT", 8, 0)
    w.keep.tip = "Saves this character's interface over the change. The other characters on it are asked in turn"
    return w
end

function YS:Refresh()
    if not window then return end
    local p = YS:Profile()
    local class = PlayerClass():lower()
    local ui = YS:SharedUI()
    local name = YS.UIName()
    local behind, by, at = YS.UIBehind()
    window.behind = behind
    for _, b in ipairs({ window.both, window.applyUI, window.plan, window.setup, window.pick }) do b:SetShown(not behind) end
    window.update:SetShown(behind)
    window.keep:SetShown(behind)
    window.copy:ClearAllPoints()
    if behind then
        window.copy:SetPoint("BOTTOMRIGHT", -16, 16)
        window.ui:SetWidth(600)
        window.ui:SetText(("Interface |cffffffff%s|r was changed on |cffffffff%s|r, %s."):format(name, tostring(by or "another character"), Ago(at)))
        window.info:SetText("Update puts it on this character. Or keep this character's, and that becomes the saved one.")
        return
    end
    window.copy:SetPoint("RIGHT", window.setup, "LEFT", -8, 0)
    local id = CharacterID()
    local uiDone = id ~= nil and YippSetupCharDB.uiApplied == id
    local bars = p ~= nil and p.from ~= PlayerKey()             -- there are saved bars to put on
    local several = #YS.UINames() > 1 and not uiDone
    window.pick:SetShown(several)
    window.pick:SetValue(name)
    window.ui:SetWidth(several and 440 or 600)
    window.ui:SetText(uiDone and ("|cff73d17fInterface applied.|r " .. (bars and "Next: your bars." or "Next: plan your bars."))
        or ui and YS.UIStale and YS.UIStale(ui) and ("Interface: |cffffffff%s|r, saved %s. |cffffb040An older save:|r save it again once.")
            :format(name, Ago(YS.UIScanned()))
        or ui and ("Interface: |cffffffff%s|r, saved %s on %s."):format(name, Ago(YS.UIScanned()), tostring(YS.UISource() or "a character"))
        or "Interface: none saved yet. Use Save interface on a character set up the way you like (Settings).")
    if not p then
        window.info:SetText(("Bars: no %s profile yet. Plan bars lets you build one now."):format(class))
    else
        window.info:SetText(("Bars: %s profile |cffffffff%s|r."):format(class, YS:Describe(p) or p.from))
    end
    window.applyUI:SetEnabled(ui ~= nil and not uiDone)
    window.setup:SetEnabled(bars)
    -- one button for both while both are still to do; otherwise the two stand alone
    local both = ui ~= nil and not uiDone and bars
    window.both:SetShown(both)
    window.applyUI:ClearAllPoints()
    if both then window.applyUI:SetPoint("LEFT", window.both, "RIGHT", 8, 0)
    else window.applyUI:SetPoint("BOTTOMLEFT", 16, 16) end
    -- The planner is the way in when there's nothing saved; with a profile it's in Settings, Character setup.
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

-- A character on an interface that was saved on another character since: the window, asking which.
local function ChangedElsewhere()
    if not YS.UIFollows() or not YS.UIBehind() or (window and window:IsShown()) then return end
    if InCombatLockdown() or InCinematic() or not UIParent:IsShown() then
        C_Timer.After(5, ChangedElsewhere)
        return
    end
    YS:Toggle()
end

-- The intro cinematic (or movie) a new character logs in to: cancelled at once while level 1, when the
-- option is on. It can start before we load, so the first login checks for one running too.
local function SkipIntro()
    if UnitLevel("player") > 1 or not (YippSetupDB and YS:Options().skipIntro) then return end
    if InCinematic and InCinematic() then
        -- (the game's own function: seen to end the opening flight, 2026-10-13. Blizzard's frame code is not called from here.)
        if StopCinematic then StopCinematic() end
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
        tostring(class), UnitLevel("player") or 0, (UnitLevel("player") or 1) + Ahead(o), YS.SpellButtons(o), tostring(o.clearBars),
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
        YS:Undo(arg == "first")
    elseif cmd == "ui" or cmd == "interface" then
        if arg == "copy" then YS:CopyInterface() else YS:AskInterface() end
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
f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")       -- the other of your two specs (Layouts.lua)
f:RegisterEvent("ACTIONBAR_SLOT_CHANGED")            -- a button changed: the profile remembers (below)
f:RegisterEvent("PLAYER_LEAVING_WORLD")              -- logging out: the account's interface follows (YS.FollowUI)
f:RegisterEvent("UPDATE_MACROS")                     -- a macro edited: what a button holds reads the same, and isn't

-- A profile is your bars as you have them, not as they once were saved: a spell you drag somewhere
-- else while levelling, a potion you put on a button, is in the profile a few seconds later - so it
-- is there when you come back from another profile, and on your next character of the class. Only on
-- a character that is on the profile (set up from it, or the one it was made on), never in a fight,
-- and once for however many buttons changed (a login changes a hundred). The spells planned for
-- levels you haven't reached keep their buttons (YS:ScanBars). Account option "remember" (on unless
-- turned off).
local rememberSoon, rememberLate = false, false
function YS.Remembers() return not (YippSetupDB and YippSetupDB.remember == false) end
-- The game says "a button changed" for much that changes nothing we keep: a macro that shows another
-- spell for your target, a button going grey. What each button holds (its kind and what of) is noted,
-- and the bars are read - every button, with its spell's and its macro's details - only when that is
-- no longer so for one of them. The first look has nothing to compare with, and reads.
local held, heldAny = {}, false
local function ButtonsChanged()
    local changed = not heldAny
    heldAny = true
    for slot = 1, MAX_SLOT do
        local kind, id
        if HasAction(slot) then kind, id = GetActionInfo(slot) end
        -- a macro by its name: the number the game gives for one is on some clients the spell it shows
        -- now, which changes with your target (a macro edited in place: UPDATE_MACROS, below)
        if kind == "macro" then id = GetActionText(slot) end
        local now = kind and (tostring(kind) .. ":" .. tostring(id)) or false
        if held[slot] ~= now then
            held[slot] = now
            changed = true
        end
    end
    return changed
end
--- What the buttons held is forgotten: the next look reads the bars whatever they read like.
function YS.BarsStale() heldAny = false end
local function Remember()
    rememberSoon = false
    if not (YippSetupCharDB and YippSetupCharDB.applied and YS.Remembers() and YS:Profile()) then return end
    if YippSetupCharDB.hold then return end             -- (YS.Hold)
    if InCombatLockdown() then
        rememberLate = true         -- looked at again when the fight ends (its own flag: `waiting` sets
        return                      -- the whole pass that places new spells going, after every fight)
    end
    if GetCursorInfo and GetCursorInfo() then return end        -- mid-drag: the drop changes a button again
    if not ButtonsChanged() then return end
    YS:ScanBars()
    YippSetupCharDB.layout = Copy(YS:Profile().slots)           -- where spells learned later go, too
end
YS.RememberNow = Remember
local function RememberSoon()
    if rememberSoon or not (YippSetupCharDB and YippSetupCharDB.applied and YS.Remembers()) then return end
    rememberSoon = true
    C_Timer.After(4, Remember)
end
local upgradeSoon = false
local function UpgradeSoon()
    -- a character never set up has nothing to keep up: nothing is set going (this is every spell change)
    if upgradeSoon or not (YippSetupCharDB and YippSetupCharDB.applied) then return end
    upgradeSoon = true          -- a burst (training five spells, a login) costs one pass
    C_Timer.After(0.2, function() upgradeSoon = false if YippSetupCharDB then YS:Upgrade() end end)
end
f:SetScript("OnEvent", function(self, event, arg1, arg2)
    -- Character setup switched off since this was loaded: nothing more is placed, saved or followed
    -- (it said so, and went on doing all three until the reload)
    if YR.SetupOn and not YR.SetupOn() then return end
    if event == "PLAYER_ENTERING_WORLD" and (arg1 or arg2) then   -- login or reload only
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        -- A character made again under a deleted one's name is handed the old one's saved file: "set up
        -- already", on a profile, with the dead character's bars and macros to undo to - and the first
        -- automatic save wrote the new character's empty bars over its class's profile. What is kept
        -- here belongs to the character it was written for (emptied in place: the same table).
        local id, c = CharacterID(), YippSetupCharDB
        if id and type(c) == "table" then
            if c.guid and c.guid ~= id then
                for k in pairs(c) do c[k] = nil end
                Print("a new character under an old one's name: what was kept for the old one (set up, its bars to undo to) is let go.")
                if UnitLevel("player") == 1 then YS.earlyLater = true end
            end
            c.guid = id
        end
        if YS.earlyLater and UnitLevel("player") == 1 and YS.EarlyBars then YippSetupCharDB.earlyBars = YS.EarlyBars() end
        YS.earlyLater = nil
        SkipIntro()
        YS.ClassUINoted()
        C_Timer.After(0.5, FirstZoom)
        C_Timer.After(2, FirstTimeHere)
        C_Timer.After(3, FillInUI)
        C_Timer.After(4, ChangedElsewhere)
        C_Timer.After(6, YS.UISettle)
        if YippSetupCharDB.applied and YS:Options().noAutoPush and not InCombatLockdown() then NoAutoPush() end
    elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
        if YS.OnSpecChanged then YS.OnSpecChanged(arg1, arg2) end
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        RememberSoon()
    elseif event == "UPDATE_MACROS" then
        YS.BarsStale()
        RememberSoon()
    elseif event == "PLAYER_LEAVING_WORLD" then
        YS.FollowUI()
    elseif event == "SPELLS_CHANGED" or (event == "PLAYER_REGEN_ENABLED" and waiting) then
        UpgradeSoon()
        if event == "PLAYER_REGEN_ENABLED" then RememberSoon() end
    elseif event == "PLAYER_REGEN_ENABLED" and rememberLate then
        rememberLate = false
        RememberSoon()
    end
end)

--- Called by Headstart once this addon's files are in (Core.lua, YR.LoadSetup). fresh: this is the
--- character's first login with Headstart (the saved tables themselves are made by Headstart).
--- The macros waiting on your bars that were given a spell's icon (see the top of the file): back to
--- the question mark, which the game turns into the spell's icon by itself once you know the spell.
--- Once a login, out of a fight. Returns how many.
function YS.PlaceholderIcons()
    if InCombatLockdown() or not (GetNumMacros and EditMacro) then return 0 end
    local _, numChar = GetNumMacros()
    local base = Constants.MacroConsts.MAX_ACCOUNT_MACROS
    local done = 0
    for i = base + 1, base + (numChar or 0) do
        local name, icon, body = GetMacroInfo(i)
        local spell = name and icon ~= DYNAMIC_ICON and type(body) == "string" and body:match("^#showtooltip ([^\n]+)\n/cast ")
        spell = spell and spell:gsub("%(Rank %d+%)$", "")
        -- ours: named as we name it, with the very icon the plan has for that spell
        if spell and name == ShortName(spell) and icon == PlanIcon(spell) and pcall(EditMacro, i, nil, DYNAMIC_ICON, nil) then
            done = done + 1
        end
    end
    return done
end

function YS.Start(fresh)
    YS.RepairLayouts()
    -- leaving Edit Mode: what you changed there is the account's interface, on the character it comes from
    local registry = _G.EventRegistry
    if type(registry) == "table" and registry.RegisterCallback then
        registry:RegisterCallback("EditMode.Exit", function() if not YR.SetupOn or YR.SetupOn() then YS.FollowUI() end end, YS)
    end
    if YippSetupCharDB and YippSetupCharDB.applied then
        C_Timer.After(4, function() YS.PlaceholderIcons() end)
    end
    -- a new character: the main's action bars now, so Blizzard shows them while logging in
    -- (level 1 and nothing else: should the game not know the level this early and say 0, that must
    -- not read as "new" on a character's first login with Headstart - it is looked at again at the login)
    local level = UnitLevel("player") or 0
    if fresh and level == 1 and YS.EarlyBars then
        YippSetupCharDB.earlyBars = YS.EarlyBars()
    elseif fresh and level == 0 then
        YS.earlyLater = true
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
