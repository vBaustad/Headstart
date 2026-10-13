-- Move your settings: everything you have set up in Headstart as a text, to take to another install -
-- from the beta to the live game, to another computer, to a friend. /headstart transfer.
--   The game keeps an addon's settings in its own WTF folder, one per installed client: the beta's
--   are not the live game's, and nothing carries them over. Copying the saved file by hand works for
--   one person who knows where it is; this works for anyone, and needs no folder to be known.
--   What goes into the text: your settings (every switch, look and position), what each class's
--   trainer may buy, your quest reward lists, your own routes, and Character setup's bar profiles,
--   macros and saved interface. What does not: the run logs (megabytes, and they name characters
--   that won't be there), each character's own records (its place in a route, its journey, its
--   undo copies), the other characters' bags, and what only says where this install is at (the
--   welcome answered, the defaults latched).
--   The text is plain lines - one value a line, a table opened and closed by a line of its own -
--   read back by a reader that only reads: no line of it is ever run as code. Every "|" and line
--   break inside a value is written as %7C, %0A, so a chat or a text box can't change it on the way,
--   and the last line counts the lines, so a text cut short in the copying is told from a whole one.
--   Importing replaces, key by key, what the text holds; what it doesn't hold stays as it is. What
--   was there before is kept (YippRouteDB.transferKept) until the next import: Undo puts it back.
--   An install you can no longer log into has no Export to press - the beta is closed a week before
--   the live game opens. What it leaves is its saved file, so that is read as well: open
--   WTF\Account\<your account>\SavedVariables\Headstart.lua in a text editor, copy all of it, paste
--   it here. It is read as a list of names and values and as nothing else (see Saved, below).
--   A macro in a bar profile whose text runs code (/run, /script, /console, /dump) is left out
--   unless you say otherwise: a text from someone else is theirs to have written anything into,
--   and a macro runs when you press it.
--   Part of Headstart_Options (load on demand): none of it is in memory until it is asked for.
local YR = _G.HeadstartNS

local HEAD = "HEADSTART-SETTINGS 1"
local DROP_DB = { runs = true, place = true, instanceRuns = true, scan = true, welcome = true, welcomeSeen = true, quiet = true,
    rxpTrainerWasOn = true, transferKept = true, splits = true }
-- What acts for you: spends gold, sends or moves your things, answers for you, or says who gets your
-- mail. A text from someone else must not be able to switch any of it on (with the mail ones it could
-- send your mats to its writer's character at the next mailbox): Import leaves each of these as it is
-- here, and only "All of it" - for a text of your own - takes them.
local ACTING = { mailAuto = true, mailTo = true, mailCustom = true, mailMats = true, mailButton = true,
    restock = true, restockCustom = true, restockCounts = true, restockReserve = true, restockAmmo = true, restockAmmoBy = true,
    autoTrain = true, trainer = true, bankAuto = true, bankMats = true, bankButton = true,
    deathSkipRelease = true, skipQuests = true, groupShare = true, groupAccept = true, shareAll = true,
    acceptInvites = true, whisperInvite = true, acceptFrom = true, levelShot = true, trinketAuto = true,
    pickRewards = true, rewardClasses = true, setupOn = true, routes = true }
-- The words for the ones that are switches, for the line that says what a text would turn on.
local ACTS = { { "mailAuto", "mail to another character" }, { "restock", "restock" }, { "autoTrain", "the class trainer" },
    { "bankAuto", "bank deposit" }, { "deathSkipRelease", "release at death skips" }, { "skipQuests", "abandoning skipped quests" },
    { "groupAccept", "accepting shared quests" }, { "groupShare", "sharing quests" }, { "shareAll", "sharing every quest" },
    { "acceptInvites", "accepting invites" }, { "whisperInvite", "inviting on a whisper" }, { "levelShot", "screenshots" },
    { "trinketAuto", "trinket swaps" } }
-- What the addon reads as a table: anything else under these names, and the login stopped at it.
local TABLES = { custom = true, myRoutes = true, extra = true, swing = true, xpbar = true, trainer = true, rewardClasses = true,
    mailTo = true, mailCustom = true, restockCustom = true, restockCounts = true, minimap = true, anchor = true,
    windowScale = true, trainerCosts = true }
local DROP_SETUP = { uiPrev = true }
local MAX_LINES, MAX_DEPTH = 400000, 40

-- ---------------------------------------------------------------------------
-- Written
-- ---------------------------------------------------------------------------
local function Esc(s, key)
    s = s:gsub(key and "[%%|:\t\n\r]" or "[%%|\t\n\r]", function(c) return ("%%%02X"):format(c:byte()) end)
    -- (a space at the end of a line is the first thing a chat or an editor takes off)
    return (s:gsub(" +$", function(sp) return ("%20"):rep(#sp) end))
end
local function Unesc(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

local function Number(n) return ("%.17g"):format(n) end
local function KeyText(k)
    if type(k) == "number" then return "#" .. Number(k) end
    local s = Esc(k, true)
    if s:sub(1, 1) == "#" then s = "%23" .. s:sub(2) end
    return s
end
local function KeyOf(text)
    if text:sub(1, 1) == "#" then
        local n = tonumber(text:sub(2))
        -- (not a number that is none: "nan" reads as one, and a table has no place for it)
        if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
        return n
    end
    return Unesc(text)
end

local function Sorted(t, drop)
    local keys = {}
    for k in pairs(t) do
        if (type(k) == "string" or type(k) == "number") and not (drop and drop[k]) then keys[#keys + 1] = k end
    end
    -- (a steady order, so the same settings give the same text)
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) == "number" end
        return a < b
    end)
    return keys
end

local function Write(out, key, v, depth, drop)
    local kind = type(v)
    if kind == "table" then
        if depth > MAX_DEPTH then return end
        out[#out + 1] = "T:" .. key
        for _, k in ipairs(Sorted(v, drop)) do Write(out, KeyText(k), v[k], depth + 1) end
        out[#out + 1] = "E"
    elseif kind == "string" then
        out[#out + 1] = "S:" .. key .. ":" .. Esc(v)
    elseif kind == "number" then
        if v == v and v ~= math.huge and v ~= -math.huge then out[#out + 1] = "N:" .. key .. ":" .. Number(v) end
    elseif kind == "boolean" then
        out[#out + 1] = "B:" .. key .. ":" .. (v and "1" or "0")
    end
end

--- Your settings as a text. routes == false: without your own routes (they are the long part).
function YR.TransferExport(routes)
    local out = { HEAD, "F:" .. Esc(YR.CharKey(), true) .. ":" .. date("%Y-%m-%d") }
    local drop = DROP_DB
    if routes == false then
        drop = { myRoutes = true, custom = true }
        for k in pairs(DROP_DB) do drop[k] = true end
    end
    Write(out, "db", YippRouteDB, 1, drop)
    Write(out, "setup", type(_G.YippSetupDB) == "table" and _G.YippSetupDB or {}, 1, DROP_SETUP)
    out[#out + 1] = "END:" .. (#out + 1)
    return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- Read back
-- ---------------------------------------------------------------------------
-- Whether a macro's text runs code when pressed.
local CODE = { run = true, script = true, console = true, dump = true }
local function Runs(body)
    body = body:gsub("\r", "\n")
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        local cmd = line:match("^%s*/(%a+)")
        if cmd and CODE[cmd:lower()] then return true end
    end
    return false
end
-- A route's text: RestedXP makes a button of a line like ".macro Name,Icon >>/run ...", so there the
-- command stands in the middle of a line.
local function RouteRuns(text)
    text = text:gsub("\r", "\n")
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local low = line:lower()
        if low:find(".macro", 1, true) then
            for cmd in pairs(CODE) do
                if low:find("/" .. cmd .. "%f[%A]") then return true end
            end
        end
    end
    return false
end
-- The macros that run code taken out of what was read (a table with such a body, or such a text by
-- itself): how many.
-- kind: "lib" for the table of remembered macros (a list per class), "list" for one of those lists -
-- the one place a hole must be closed up, since it is read in order and ends at a hole. (A bar's
-- slots are numbered places: taking one out moves nothing.)
local function Strip(t, depth, kind)
    local n = 0
    if depth > MAX_DEPTH then return 0 end
    local list, gone = kind == "list" and #t or 0, {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            if (type(v.body) == "string" and Runs(v.body)) or (type(v.text) == "string" and RouteRuns(v.text)) then
                gone[#gone + 1] = k
            else
                n = n + Strip(v, depth + 1, (kind == "lib" and "list") or (k == "macroLib" and "lib") or nil)
            end
        elseif type(v) == "string" and v:find("/", 1, true) and k ~= "text" and Runs(v) then
            gone[#gone + 1] = k
        end
    end
    -- from a list, the ones after it move up: a hole ends the list for whatever reads it in order
    table.sort(gone, function(a, b)
        if type(a) == "number" and type(b) == "number" then return a > b end
        return type(a) == "number"
    end)
    for _, k in ipairs(gone) do
        if type(k) == "number" and k >= 1 and k <= list and k % 1 == 0 then table.remove(t, k) else t[k] = nil end
        n = n + 1
    end
    return n
end
local function Count(t, want, depth)
    local n = 0
    if depth > MAX_DEPTH then return 0 end
    for _, v in pairs(t) do
        if type(v) == "table" then
            if want(v) then n = n + 1 end
            n = n + Count(v, want, depth + 1)
        end
    end
    return n
end

-- The game's own saved file, pasted whole: WTF\Account\<your account>\SavedVariables\Headstart.lua,
-- opened in a text editor. That file is what is left of an install that can no longer be logged
-- into (the beta, once it is closed), so it is read too - as what it is, a list of names and values
-- in the game's own writing ( ["name"] = value, in braces ), by a reader of its own: a name, an
-- equals sign, and a value that is a text in quotes, a number, true, false or braces holding more
-- of the same. Anything else in it - a call, a word that is none of those - and it is not read at
-- all. Nothing in it is run. Returns { [name] = value, ... } for every name set in it, or nil and why.
local function Saved(text)
    local pos, len, nodes = 1, #text, 0
    local function Stop(why) error(why, 0) end
    local function Skip()
        while true do
            local _, e = text:find("^%s+", pos)
            if e then pos = e + 1 end
            if text:sub(pos, pos + 1) == "--" then
                local _, c = text:find("^[^\n]*", pos)
                pos = (c or len) + 1
            elseif not e then
                return
            end
        end
    end
    local function Quoted()
        local out, i = {}, pos + 1
        while true do
            local a = text:find('[\\"]', i)
            if not a then Stop("a text in it is never closed: the file is cut short.") end
            out[#out + 1] = text:sub(i, a - 1)
            if text:sub(a, a) == '"' then
                pos = a + 1
                return table.concat(out)
            end
            local c = text:sub(a + 1, a + 1)
            if c == "n" then out[#out + 1], i = "\n", a + 2
            elseif c == "r" then out[#out + 1], i = "\r", a + 2
            elseif c == "t" then out[#out + 1], i = "\t", a + 2
            elseif c:find("%d") then
                local digits = text:match("^%d%d?%d?", a + 1)
                out[#out + 1], i = string.char(tonumber(digits) % 256), a + 1 + #digits
            elseif c == "" then
                Stop("a text in it is never closed: the file is cut short.")
            else
                out[#out + 1], i = c, a + 2          -- (\\ and \" and a line break written as itself)
            end
        end
    end
    local Value
    function Value(depth)
        Skip()
        nodes = nodes + 1
        if depth > MAX_DEPTH or nodes > 3000000 then Stop("that is too large or too deep to be a saved file.") end
        local c = text:sub(pos, pos)
        if c == '"' then return Quoted() end
        if c == "{" then
            pos = pos + 1
            local t, n = {}, 0
            while true do
                Skip()
                local d = text:sub(pos, pos)
                if d == "}" then
                    pos = pos + 1
                    return t
                elseif d == "" then
                    Stop("the file is cut short: something in it is never closed. Copy all of it.")
                elseif d == "[" then
                    pos = pos + 1
                    local key = Value(depth + 1)
                    Skip()
                    if text:sub(pos, pos) ~= "]" then Stop("a name in it is not closed.") end
                    pos = pos + 1
                    Skip()
                    if text:sub(pos, pos) ~= "=" then Stop("a name in it has no value.") end
                    pos = pos + 1
                    local v = Value(depth + 1)
                    if type(key) == "string" or type(key) == "number" then t[key] = v end
                else
                    n = n + 1
                    t[n] = Value(depth + 1)
                end
                Skip()
                local sep = text:sub(pos, pos)
                if sep == "," or sep == ";" then pos = pos + 1 end
            end
        end
        local word = text:match("^[%w%.%+%-]+", pos)
        if not word then Stop("there is something in it that is not a saved value.") end
        pos = pos + #word
        if word == "true" then return true end
        if word == "false" then return false end
        if word == "nil" then return nil end
        if word == "inf" then return math.huge end
        if word == "-inf" then return -math.huge end
        local n = tonumber(word)
        if not n then Stop("there is something in it that is not a saved value (" .. word:sub(1, 20) .. ").") end
        return n
    end
    local out = {}
    local ok, why = pcall(function()
        while true do
            Skip()
            if pos > len then return end
            local name, after = text:match("^([%a_][%w_]*)%s*=()", pos)
            if not name then Stop("there is something in it that is not a saved value.") end
            pos = after
            out[name] = Value(1)
        end
    end)
    if not ok then return nil, tostring(why) end
    return out
end

-- What was read, with what must stay behind taken out and what is in it counted.
local function Summed(data)
    for k in pairs(DROP_DB) do data.db[k] = nil end
    for k in pairs(DROP_SETUP) do data.setup[k] = nil end
    local settings = 0
    for _ in pairs(data.db) do settings = settings + 1 end
    data.settings = settings
    data.profiles = Count(data.setup, function(v) return type(v.slots) == "table" end, 1)
    data.macros = Count(data.setup, function(v) return type(v.body) == "string" end, 1)
    data.code = Count(data.setup, function(v) return type(v.body) == "string" and Runs(v.body) end, 1)
        + Count(data.db, function(v) return (type(v.body) == "string" and Runs(v.body)) or (type(v.text) == "string" and RouteRuns(v.text)) end, 1)
    -- what it would switch on that acts for you, in words (the mail's with who it goes to)
    local acts = {}
    for _, a in ipairs(ACTS) do
        local v = data.db[a[1]]
        if v ~= nil and v ~= false and v ~= "off" then
            local words = a[2]
            if a[1] == "mailAuto" and type(data.db.mailTo) == "table" then
                local to = {}
                for _, name in pairs(data.db.mailTo) do if type(name) == "string" and name ~= "" then to[#to + 1] = name end end
                table.sort(to)
                if #to > 0 then words = "mail to " .. table.concat(to, ", ") end
            end
            acts[#acts + 1] = words
        end
    end
    for _, r in pairs(type(data.db.rewardClasses) == "table" and data.db.rewardClasses or {}) do
        if type(r) == "table" and r.on == true then acts[#acts + 1] = "quest rewards picked" break end
    end
    data.acts = acts
    data.routes = 0
    for _ in pairs(type(data.db.myRoutes) == "table" and data.db.myRoutes or {}) do data.routes = data.routes + 1 end
    return data
end

--- A settings text read - one Export wrote, or the game's own saved file pasted whole:
--- { db, setup, from, date, settings, profiles, macros, code, routes }, or nil and why not.
--- Nothing is changed by reading, and nothing in the text is run.
function YR.TransferRead(text)
    if type(text) ~= "string" then return nil, "there is no text." end
    text = text:gsub("\r\n?", "\n")
    -- the saved file itself: it sets YippRouteDB, and does not begin as an exported text does
    if not text:find("^%s*" .. HEAD:gsub("%-", "%%-")) and text:find("YippRouteDB%s*=") then
        local saved, why = Saved(text)
        if not saved then return nil, "the saved file could not be read: " .. tostring(why) end
        if type(saved.YippRouteDB) ~= "table" then return nil, "the saved file holds no Headstart settings." end
        return Summed({ db = saved.YippRouteDB, setup = type(saved.YippSetupDB) == "table" and saved.YippSetupDB or {},
            from = "a saved file" })
    end
    local lines = {}
    for raw in text:gmatch("[^\n]+") do
        local line = (raw:gsub("^%s+", ""))
        if line ~= "" then
            lines[#lines + 1] = line
            if #lines > MAX_LINES then return nil, "that is too long to be a settings text." end
        end
    end
    if #lines == 0 then return nil, "there is no text. Paste a settings text here first." end
    if lines[1]:gsub("%s+$", "") ~= HEAD then
        return nil, "this is not a Headstart settings text (the first line should be \"" .. HEAD .. "\")."
    end
    local said = tonumber((lines[#lines]:match("^END:(%d+)%s*$")))
    if not said or said ~= #lines then
        return nil, ("the text is cut short: %d lines here%s. Copy all of it and paste again."):format(#lines,
            said and (", " .. said .. " when it was written") or ", and its last line is missing")
    end
    local root, from, day = {}, nil, nil
    local stack = { root }
    local ok, a, b = pcall(function()
    for i = 2, #lines - 1 do
        local line = lines[i]
        local kind, rest = line:sub(1, 1), line:sub(3)
        local top = stack[#stack]
        if line == "E" then
            if #stack == 1 then return nil, ("line %d closes something that was never opened."):format(i) end
            stack[#stack] = nil
        elseif line:sub(2, 2) ~= ":" then
            return nil, ("line %d is not part of a settings text."):format(i)
        elseif kind == "T" then
            if #stack >= MAX_DEPTH then return nil, "that is nested too deep to be a settings text." end
            local key = KeyOf(rest)
            if key == nil then return nil, ("line %d has no name."):format(i) end
            local t = {}
            top[key] = t
            stack[#stack + 1] = t
        elseif kind == "S" or kind == "N" or kind == "B" then
            local key, value = rest:match("^([^:]*):(.*)$")
            key = key and KeyOf(key)
            if key == nil then return nil, ("line %d has no name."):format(i) end
            if kind == "S" then
                top[key] = Unesc(value)
            elseif kind == "N" then
                local n = tonumber(value)
                if not n then return nil, ("line %d should be a number."):format(i) end
                top[key] = n
            else
                top[key] = value:sub(1, 1) == "1"
            end
        elseif kind == "F" then
            local who, when = rest:match("^([^:]*):(.*)$")
            from, day = who and Unesc(who), when
        else
            return nil, ("line %d is not part of a settings text."):format(i)
        end
    end
    if #stack ~= 1 then return nil, "the text is not whole: something in it is never closed." end
    if type(root.db) ~= "table" or type(root.setup) ~= "table" then return nil, "the text holds no settings." end
    return Summed({ db = root.db, setup = root.setup, from = from, date = day })
    end)
    if not ok then return nil, "the text could not be read (" .. tostring(a):sub(1, 80) .. ")." end
    return a, b
end

--- What was read put in place: each thing the text holds replaces what you had under that name; what
--- it doesn't hold stays. own: all of it, as a text of your own - the macros and routes that run code
--- and the settings that act for you too. Without it those are left out, and what acts for you stays
--- as it is here. Returns how many things were put in, how many macros and routes that run code were
--- left out, and how many settings that act for you. Takes a /reload to be what is running.
function YR.TransferImport(data, own)
    if type(data) ~= "table" or type(data.db) ~= "table" or type(data.setup) ~= "table" then return nil, "nothing was read." end
    local left, stayed = 0, 0
    if not own then
        left = Strip(data.setup, 1) + Strip(data.db, 1)
        for k in pairs(ACTING) do
            if data.db[k] ~= nil then data.db[k] = nil stayed = stayed + 1 end
        end
    end
    -- a thing of the wrong shape is not taken at all: a table where the addon reads a table, and no
    -- table put where there was none (one such line stopped the login for every part after it)
    for k, v in pairs(data.db) do
        local have = YippRouteDB[k]
        if (TABLES[k] and type(v) ~= "table") or (have ~= nil and (type(have) == "table") ~= (type(v) == "table")) then
            data.db[k] = nil
        end
    end
    for _, k in ipairs({ "custom", "myRoutes", "extra" }) do
        for name, route in pairs(type(data.db[k]) == "table" and data.db[k] or {}) do
            if type(route) ~= "table" then data.db[k][name] = nil end
        end
    end
    _G.YippSetupDB = type(_G.YippSetupDB) == "table" and _G.YippSetupDB or {}
    local kept = { at = time(), db = {}, setup = {}, noDb = {}, noSetup = {} }
    local n = 0
    local function Put(into, from, drop, was, none)
        for k, v in pairs(from) do
            if not drop[k] then
                if into[k] == nil then none[k] = true else was[k] = into[k] end
                into[k] = v
                n = n + 1
            end
        end
    end
    Put(YippRouteDB, data.db, DROP_DB, kept.db, kept.noDb)
    Put(_G.YippSetupDB, data.setup, DROP_SETUP, kept.setup, kept.noSetup)
    YippRouteDB.transferKept = kept
    return n, left, stayed
end

--- Whether there is an import to take back (when it was made), and taking it back: everything it
--- replaced is as it was, and what it added is gone. Takes a /reload too.
function YR.TransferKept()
    local kept = YippRouteDB.transferKept
    return type(kept) == "table" and kept.at or nil
end
function YR.TransferUndo()
    local kept = YippRouteDB.transferKept
    if type(kept) ~= "table" then return false end
    _G.YippSetupDB = type(_G.YippSetupDB) == "table" and _G.YippSetupDB or {}
    for k, v in pairs(kept.db or {}) do YippRouteDB[k] = v end
    for k in pairs(kept.noDb or {}) do YippRouteDB[k] = nil end
    for k, v in pairs(kept.setup or {}) do _G.YippSetupDB[k] = v end
    for k in pairs(kept.noSetup or {}) do _G.YippSetupDB[k] = nil end
    YippRouteDB.transferKept = nil
    return true
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
-- Two steps side by side in meaning, one under the other on the window, each a card with its number:
--   1  Copy the saved file - where it is, written so it can be marked and copied
--   2  Or carry them as a text - Export and Import
-- That is all the window is until Export or Import is pressed: only then does it grow a box for the
-- text under the cards (Export fills it and marks it; Import leaves it empty to paste into, with Read
-- and Import under it). Undo last import stands at the foot while there is an import to take back.
local win, read, mode
local W, H_SHUT, H_OPEN = 700, 372, 624
local SAVED_FILE = "WTF\\Account\\<your account>\\SavedVariables\\Headstart.lua"

local function Say(text, bad)
    win.status:SetText(text)
    win.status:SetTextColor(unpack(bad and { 1, 0.45, 0.4 } or YR.Style.C.sub))
end

local function Paint()
    local open, taking = mode ~= nil, mode == "import"
    win:SetHeight(open and H_OPEN or H_SHUT)
    win.area:SetShown(open)
    win.status:SetShown(open)
    win.readB:SetShown(taking)
    win.import:SetShown(taking)
    win.import:SetEnabled(read ~= nil)
    win.importAll:SetShown(taking and read ~= nil and (read.code > 0 or #read.acts > 0))
    win.undo:SetShown(YR.TransferKept() ~= nil)
end

-- A step: its number in the accent, its name, and what to do in plain lines under it.
local function Step(n, name, top, height)
    local S = YR.Style
    local card = CreateFrame("Frame", nil, win)
    card:SetPoint("TOPLEFT", 20, top)
    card:SetSize(W - 40, height)
    S.Fill(card, S.C.card)
    S.Border(card, S.C.line)
    local number = S.Text(card, 26, S.C.accent)
    number:SetPoint("TOPLEFT", 18, -12)
    number:SetText(n)
    local title = S.Text(card, 16)
    title:SetPoint("TOPLEFT", 54, -14)
    title:SetText(name)
    return card
end

local function Line(card, y, text, colour)
    local S = YR.Style
    local line = S.Text(card, 13, colour or S.C.sub)
    line:SetPoint("TOPLEFT", 54, y)
    line:SetWidth(W - 40 - 54 - 18)
    line:SetJustifyH("LEFT")
    line:SetWordWrap(true)
    line:SetText(text)
    return line
end

-- Export: the box, filled and marked. Import: the box, empty, to paste into.
local function Export()
    local text = YR.TransferExport()
    read, mode = nil, "export"
    Paint()
    win.box:SetText(text)
    win.box:SetFocus()
    win.box:HighlightText()
    Say(("Your settings, %d letters, are marked: press Ctrl+C to copy them, and paste them into a text file to keep."):format(#text))
end
local function Take()
    read, mode = nil, "import"
    Paint()
    win.box:SetText("")
    win.box:SetFocus()
    Say("Paste the text here (Ctrl+V), then press Read.")
end

local function Build()
    if win then return end
    local S = YR.Style
    win = S.Window("HeadstartTransferWindow", W, H_SHUT, "Move your settings")
    win.subtitle:SetText("to the live game, or another computer")
    local intro = S.Text(win, 13, S.C.sub)
    intro:SetPoint("TOPLEFT", 22, -62)
    intro:SetText("Every installed game keeps its own settings, and nothing moves them for you. Do one of these two:")

    -- 1: the file
    local one = Step("1", "Copy the saved file", -88, 136)
    Line(one, -42, "With the game closed, copy this file from this game's folder to the same place in the other game's folder:")
    local path = CreateFrame("EditBox", nil, one)
    path:SetPoint("TOPLEFT", 54, -80)
    path:SetSize(W - 40 - 54 - 18, 24)
    path:SetAutoFocus(false)
    path:SetFont(S.FONT, 13, "")
    path:SetTextColor(unpack(S.C.text))
    path:SetTextInsets(8, 8, 0, 0)
    S.Fill(path, S.C.field)
    S.Border(path)
    path:SetText(SAVED_FILE)
    path:SetCursorPosition(0)
    -- (it is there to be marked and copied, not written in)
    path:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    path:SetScript("OnTextChanged", function(self, user) if user then self:SetText(SAVED_FILE) self:HighlightText() end end)
    path:SetScript("OnEscapePressed", path.ClearFocus)
    Line(one, -110, "The next time you log in there, everything is in place.", S.C.muted)

    -- 2: the text
    local two = Step("2", "Or carry them as a text", -234, 106)
    Line(two, -42, "Export here and keep the text in a file. In the other game, press Import and paste it in.")
    local export = S.Button(two, "Export", Export, "primary", 120)
    export:SetPoint("BOTTOMLEFT", 54, 14)
    local take = S.Button(two, "Import", Take, nil, 120)
    take:SetPoint("LEFT", export, "RIGHT", 8, 0)

    -- the text itself: only once Export or Import is pressed
    local area = S.ScrollArea(win, W - 40, 150)
    area:SetPoint("TOPLEFT", 20, -352)
    S.Fill(area, S.C.field)
    S.Border(area)
    local box = CreateFrame("EditBox", nil, area)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetFont(S.FONT, 11, "")
    box:SetTextColor(unpack(S.C.text))
    box:SetWidth(W - 56)
    box:SetTextInsets(8, 8, 8, 8)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnTextChanged", function(_, user)
        if user and read then
            read = nil          -- (what is in the box is no longer what was read)
            Paint()
        end
    end)
    area:SetScrollChild(box)
    area:SetScript("OnMouseDown", function() box:SetFocus() end)
    win.area, win.box = area, box

    win.status = S.Text(win, 12, S.C.sub)
    win.status:SetPoint("TOPLEFT", 22, -512)
    win.status:SetWidth(W - 44)
    win.status:SetJustifyH("LEFT")
    win.status:SetWordWrap(true)

    win.readB = S.Button(win, "Read", function()
        local data, why = YR.TransferRead(box:GetText())
        read = data
        if not data then
            Say("Not read: " .. tostring(why), true)
        else
            local more = {}
            if #data.acts > 0 then more[#more + 1] = "it would switch on " .. table.concat(data.acts, ", ") end
            if data.code > 0 then more[#more + 1] = ("%d of its macros or routes run code (/run, /script)"):format(data.code) end
            Say(("Read: %d settings, %d bar %s, %d %s, %d of your own %s. Import puts them in place of what you have here (kept,"
                .. " to undo) and reloads.%s"):format(data.settings, data.profiles, data.profiles == 1 and "profile" or "profiles",
                data.macros, data.macros == 1 and "macro" or "macros", data.routes, data.routes == 1 and "route" or "routes",
                #more > 0 and (" But " .. table.concat(more, ", and ") .. ": Import leaves those out, and what acts for you stays"
                    .. " as it is here. The red button takes all of it - right only for a text of your own.") or ""), #data.acts > 0)
        end
        Paint()
    end, "primary", 90)
    win.readB:SetPoint("BOTTOMLEFT", 20, 16)
    local function Bring(own)
        if not read then return end
        if InCombatLockdown() then Say("Not in a fight.", true) return end
        local n, left, stayed = YR.TransferImport(read, own)
        read = nil
        YR.Print(("imported %d things%s%s. Reloading. To take it back: /headstart transfer, Undo last import."):format(n or 0,
            (left or 0) > 0 and (", %d macros or routes that run code left out"):format(left) or "",
            (stayed or 0) > 0 and (", %d settings that act for you left as they were"):format(stayed) or ""))
        if ReloadUI then ReloadUI() end
    end
    win.import = S.Button(win, "Import and reload", function() Bring(false) end, nil, 150)
    win.import:SetPoint("LEFT", win.readB, "RIGHT", 8, 0)
    win.importAll = S.Button(win, "All of it (my own text)", function() Bring(true) end, "danger", 190)
    win.importAll.tip = "Also what acts for you (mail, restock, trainer, invites...) and macros and routes that run code. Only for a text you exported yourself"
    win.importAll:SetPoint("LEFT", win.import, "RIGHT", 8, 0)
    win.undo = S.Button(win, "Undo last import", function()
        if InCombatLockdown() then return end
        if YR.TransferUndo() then
            YR.Print("the last import is taken back. Reloading.")
            if ReloadUI then ReloadUI() end
        end
    end, "ghost", 140)
    win.undo:SetPoint("BOTTOMRIGHT", -20, 16)
    win.undo.tip = "Puts back everything the last import replaced, and reloads"
end

--- The window (/headstart transfer; "Move settings" at the foot of Headstart's window): the two steps,
--- and nothing else until Export or Import is pressed. open: "export" or "import", as if that button
--- had been (/headstart export, /headstart import).
function YR.TransferShow(open)
    Build()
    read, mode = nil, nil
    Paint()
    win:Show()
    if open == "export" then Export() elseif open == "import" then Take() end
    return true
end
