-- A RestedXP step as something the editor can work with, and back to text without losing a thing.
--
--   step << Paladin              head: who sees the step ("<< Paladin", "<< !Warrior", "" for everyone)
--       #completewith next       tag lines
--       .goto 1426,22.3,72.5,45  command lines: command, its arguments, the text after >>, a -- note
--       >>Kill the boars         text lines (">>" instructions, "+" reminders)
--
-- Anything the parser doesn't recognise is kept as a raw line and written back exactly.
local _, YR = ...

-- What each command's arguments are, for the editor's labelled fields. Commands not listed get one
-- "Arguments" field with the whole argument text.
YR.COMMANDS = {
    { cmd = "goto",       label = "Go to a place",           fields = { "Map", "X", "Y", "Radius" } },
    { cmd = "accept",     label = "Accept a quest",          fields = { "Quest ID" } },
    { cmd = "turnin",     label = "Turn in a quest",         fields = { "Quest ID" } },
    { cmd = "complete",   label = "Complete an objective",   fields = { "Quest ID", "Objective" } },
    { cmd = "mob",        label = "Kill (mob to target)",    fields = { "Mob name" } },
    { cmd = "target",     label = "Talk to (NPC to target)", fields = { "NPC name" } },
    { cmd = "xp",         label = "Farm XP to a level",      fields = { "Level" } },
    { cmd = "money",      label = "Farm gold",               fields = { "Amount" } },
    { cmd = "train",      label = "Train a spell",           fields = { "Spell ID" } },
    { cmd = "collect",    label = "Buy or collect an item",  fields = { "Item ID", "Count" } },
    { cmd = "use",        label = "Use an item",             fields = { "Item ID" } },
    { cmd = "cast",       label = "Cast a spell",            fields = { "Spell ID" } },
    { cmd = "hs",         label = "Hearth",                  fields = {} },
    { cmd = "home",       label = "Set hearth here",         fields = {} },
    { cmd = "deathskip",  label = "Death skip",              fields = {} },
    { cmd = "vendor",     label = "Sell junk",               fields = {} },
    { cmd = "fly",        label = "Take a flight",           fields = { "Destination" } },
    { cmd = "destroy",    label = "Delete an item",          fields = { "Item ID" } },
    { cmd = "isOnQuest",  label = "Only while on a quest",   fields = { "Quest ID" } },
    { cmd = "subzoneskip", label = "Skip in a subzone",      fields = { "Area ID", "Flags" } },
    { cmd = "aura",       label = "Done while an aura is on", fields = { "Aura ID" } },
}
local BY_CMD = {}
for _, c in ipairs(YR.COMMANDS) do BY_CMD[c.cmd] = c end
YR.COMMAND_BY_NAME = BY_CMD

YR.TAGS = {
    { tag = "optional",     label = "Optional (can be skipped)" },
    { tag = "sticky",       label = "Sticky (stays on screen)" },
    { tag = "completewith", label = "Done together with (label)", value = true },
    { tag = "label",        label = "Label (name to point at)",   value = true },
    { tag = "requires",     label = "Needs step (label) first",   value = true },
}

local function Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function ParseLine(line)
    local tag, val = line:match("^%s*#(%w+)%s*(.-)%s*$")
    if tag then return { k = "tag", tag = tag, val = val ~= "" and val or nil } end
    local pre, text = line:match("^%s*(>>)%s*(.-)%s*$")
    if not pre then pre, text = line:match("^%s*(%+)(.-)%s*$") end
    if pre then return { k = "say", pre = pre, text = text } end
    local cmd, rest = line:match("^%s*%.(%a+)%s*(.-)%s*$")
    if cmd then
        -- sp keeps the spaces after >> as they were, so a line nobody edits comes back unchanged
        local args, sp, text2 = rest:match("^(.-)%s*>>(%s*)(.*)$")
        args = args or rest
        local note
        local a, n = args:match("^(.-)(%s*%-%-.*)$")      -- the note keeps its own leading spaces
        if a then args, note = a, n end
        return { k = "cmd", cmd = cmd, args = Trim(args), text = text2, sp = sp, note = note }
    end
    return { k = "raw", raw = line }
end

function YR.ParseStep(text)
    local first, rest = text:match("^([^\n]*)\n?(.*)$")
    local step = { head = Trim((first or ""):gsub("^%s*step", "")), lines = {} }
    for line in (rest .. "\n"):gmatch("([^\n]*)\n") do
        if line:find("%S") then step.lines[#step.lines + 1] = ParseLine(line) end
    end
    return step
end

function YR.LineText(l)
    if l.k == "tag" then return "    #" .. l.tag .. (l.val and (" " .. l.val) or "") end
    if l.k == "say" then return "    " .. l.pre .. (l.text or "") end
    if l.k == "cmd" then
        return "    ." .. l.cmd .. ((l.args or "") ~= "" and (" " .. l.args) or "")
            .. (l.text and (" >>" .. (l.sp or "") .. l.text) or "") .. (l.note or "")
    end
    return l.raw or ""
end

function YR.WriteStep(step)
    local out = { "step" .. (step.head ~= "" and (" " .. step.head) or "") }
    for _, l in ipairs(step.lines) do out[#out + 1] = YR.LineText(l) end
    return table.concat(out, "\n")
end

-- The arguments of a command line as a list, and back.
function YR.Args(l)
    local t = {}
    for a in ((l.args or "") .. ","):gmatch("([^,]*),") do t[#t + 1] = a end
    if l.args == "" or not l.args then t = {} end
    return t
end

function YR.SetArg(l, i, value)
    local t = YR.Args(l)
    for j = #t + 1, i do t[j] = "" end
    t[i] = value
    while #t > 0 and t[#t] == "" do t[#t] = nil end
    l.args = table.concat(t, ",")
end

function YR.HasTag(step, tag)
    for i, l in ipairs(step.lines) do if l.k == "tag" and l.tag == tag then return i, l end end
end

function YR.SetTag(step, tag, on, value)
    local i, l = YR.HasTag(step, tag)
    if on and not i then
        table.insert(step.lines, 1, { k = "tag", tag = tag, val = value })
    elseif on and value ~= nil then
        l.val = value
    elseif not on and i then
        table.remove(step.lines, i)
    end
end

-- ---------------------------------------------------------------------------
-- What a step is, for the list: an icon, a line of text, where it is
-- ---------------------------------------------------------------------------
local ICON = {
    accept = "Interface\\GossipFrame\\AvailableQuestIcon",
    turnin = "Interface\\GossipFrame\\ActiveQuestIcon",
    kill   = "Interface\\Icons\\INV_Sword_04",
    travel = "Interface\\Icons\\Ability_Tracking",
    xp     = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    gold   = "Interface\\Icons\\INV_Misc_Coin_02",
    train  = "Interface\\Icons\\INV_Misc_Book_11",
    buy    = "Interface\\Icons\\INV_Misc_Bag_08",
    hearth = "Interface\\Icons\\INV_Misc_Rune_01",
    death  = "Interface\\Icons\\Ability_Rogue_FeignDeath",
    note   = "Interface\\Icons\\INV_Misc_Note_01",
}
YR.STEP_ICON = ICON

local KIND_OF = { accept = "accept", turnin = "turnin", complete = "kill", mob = "kill", xp = "xp", money = "gold",
    train = "train", collect = "buy", vendor = "buy", hs = "hearth", home = "hearth", deathskip = "death" }
local ORDER = { "accept", "turnin", "kill", "xp", "gold", "train", "buy", "hearth", "death" }

local function Plain(s)
    return ((s or ""):gsub("|cRXP_%u+_", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):gsub("|n", " "):gsub("%s+<<.*$", ""))
end
YR.Plain = Plain

local GOLD = "|cffffd24a"

-- A quest name in the text ("Accept The Boar Hunter") is shown in gold.
local function Colour(text)
    for _, verb in ipairs({ "Accept ", "Turn in ", "Complete ", "Kill ", "Finish " }) do
        if text:sub(1, #verb) == verb then return verb .. GOLD .. text:sub(#verb + 1) .. "|r" end
    end
    return text
end

function YR.StepInfo(step)
    local kinds, texts, where = {}, {}, nil
    for _, l in ipairs(step.lines) do
        if l.k == "cmd" then
            if KIND_OF[l.cmd] then kinds[KIND_OF[l.cmd]] = true end
            if l.cmd == "goto" and not where then where = YR.Args(l) end
            if l.text and l.text ~= "" and l.cmd ~= "goto" then texts[#texts + 1] = Colour(Plain(l.text)) end
        elseif l.k == "say" then
            texts[#texts + 1] = Plain(l.text)
        end
    end
    if #texts == 0 then
        for _, l in ipairs(step.lines) do
            if l.k == "cmd" and l.text then texts[#texts + 1] = Plain(l.text) break end
        end
    end
    local kind = "note"
    for _, k in ipairs(ORDER) do if kinds[k] then kind = k break end end
    if kind == "note" and where then kind = "travel" end
    return {
        icon = ICON[kind], kind = kind,
        text = #texts > 0 and table.concat(texts, "  ·  ") or "(empty step)",
        where = where, classes = step.head:match("<<%s*(.+)$"),
    }
end

-- "Dun Morogh 22.3, 72.5" for a goto's arguments (map, x, y); world coordinates ("1426/0") as they are.
function YR.PlaceText(args)
    if not args or not args[1] then return nil end
    local map, x, y = args[1], args[2], args[3]
    local id = tonumber(map)
    local info = id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    local zone = info and info.name or ("map " .. map)
    if map:find("/") then return ("%s  world %s, %s"):format(zone, x or "?", y or "?") end
    local nx, ny = tonumber(x), tonumber(y)
    return nx and ny and ("%s  %.1f, %.1f"):format(zone, nx, ny) or zone
end

-- Templates for a new step, filled in with where you are standing and what you are targeting.
function YR.StepTemplates()
    local map, x, y = YR.Position()
    local here = map and ("%d,%.2f,%.2f"):format(map, x, y) or "1426,50,50"
    local ok, target = pcall(UnitName, "target")
    target = ok and target or nil
    local level = UnitLevel("player")
    return {
        { "quest",  "Accept a quest here",  { head = "", lines = { { k = "cmd", cmd = "goto", args = here },
            { k = "say", pre = ">>", text = "Talk to " .. (target or "the quest giver") },
            { k = "cmd", cmd = "accept", args = "", text = "Accept " },
            target and { k = "cmd", cmd = "target", args = target } or nil } } },
        { "turnin", "Turn in a quest here", { head = "", lines = { { k = "cmd", cmd = "goto", args = here },
            { k = "cmd", cmd = "turnin", args = "", text = "Turn in " },
            target and { k = "cmd", cmd = "target", args = target } or nil } } },
        { "kill",   "Kill mobs here",       { head = "", lines = { { k = "cmd", cmd = "goto", args = here },
            { k = "say", pre = ">>", text = "Kill " .. (target or "the mobs") },
            { k = "cmd", cmd = "complete", args = "" },
            target and { k = "cmd", cmd = "mob", args = target } or nil } } },
        { "goto",   "Go to this spot",      { head = "", lines = { { k = "cmd", cmd = "goto", args = here, text = "Go here" } } } },
        { "xp",     "Farm XP to a level",   { head = "", lines = { { k = "cmd", cmd = "goto", args = here },
            { k = "cmd", cmd = "xp", args = tostring(level + 1), text = "Grind to level " .. (level + 1) } } } },
        { "gold",   "Farm gold",            { head = "", lines = { { k = "cmd", cmd = "goto", args = here },
            { k = "cmd", cmd = "money", args = ">0.10", text = "Farm until you have 10s" } } } },
        { "train",  "Train at a trainer",   { head = "", lines = { { k = "cmd", cmd = "goto", args = here },
            { k = "cmd", cmd = "train", args = "", text = "Train " },
            target and { k = "cmd", cmd = "target", args = target } or nil } } },
        { "buy",    "Buy an item",          { head = "", lines = { { k = "cmd", cmd = "goto", args = here },
            { k = "cmd", cmd = "collect", args = "", text = "Buy " },
            target and { k = "cmd", cmd = "target", args = target } or nil } } },
        { "hearth", "Hearth",               { head = "", lines = { { k = "cmd", cmd = "hs", args = "", text = "Hearth" } } } },
        { "death",  "Death skip",           { head = "", lines = { { k = "cmd", cmd = "deathskip", args = "", text = "Die and respawn at the Spirit Healer" } } } },
        { "note",   "Just a note",          { head = "", lines = { { k = "say", pre = ">>", text = "" } } } },
    }
end
