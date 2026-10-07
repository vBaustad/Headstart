-- Where the run logs are kept. A run log is big (a row every two seconds of play), and the account's
-- saved file is read in whole at every login on every character: nineteen characters' logs were some
-- fourteen megabytes in memory on each of them. So:
--   This character's log is kept in the character's own saved file (HeadstartRunLog), which only this
--   character reads. While you play it is reachable as YippRouteDB.runs[you], as it always was - the
--   same table - and at logout it is taken out of the account's table again, so the account's file
--   doesn't hold it.
--   A log still in the account's file (from before this, of a character not logged in since) is packed:
--   its rows are written out as text, a couple of thousand to a piece, and the tables let go. Text is
--   a third of the size and costs the game nothing to keep. What is left in its place says how big it
--   was and when it was last played, which is all another character needs of it (the list of logs,
--   the clean-up). It is unpacked and moved to the character's own file the next time that character
--   logs in. Packing is checked before the tables are let go: unpacked again it must be the same log.
--   A packed log in the saved file: { packed = { track = { "return {...}", ... }, ev = { ... } },
--   started, stopped, last (time last played), samples, events }. Each piece is Lua: load it for its rows.
local ADDON, YR = ...

local PIECE = 2000              -- rows to a piece of text (a piece is one Lua chunk: it has a size limit)
local attached                  -- this character's key, once its log is hooked up

local function Write(v, out)
    local t = type(v)
    if t == "number" then
        if v % 1 == 0 and v > -1e15 and v < 1e15 then
            out[#out + 1] = ("%.0f"):format(v)
        else
            -- as short as reads back the very same number, else in full
            local short = tostring(v)
            out[#out + 1] = tonumber(short) == v and short or ("%.17g"):format(v)
        end
    elseif t == "string" then
        out[#out + 1] = ("%q"):format(v)
    elseif t == "boolean" then
        out[#out + 1] = v and "true" or "false"
    elseif t == "table" then
        out[#out + 1] = "{"
        local n = #v
        for i = 1, n do
            Write(v[i], out)
            out[#out + 1] = ","
        end
        for k, x in pairs(v) do
            if not (type(k) == "number" and k % 1 == 0 and k >= 1 and k <= n) then
                out[#out + 1] = "["
                Write(k, out)
                out[#out + 1] = "]="
                Write(x, out)
                out[#out + 1] = ","
            end
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "nil"
    end
end

-- Two values the same all the way down.
local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- A list of rows as pieces of text.
local function Pieces(rows)
    local pieces = {}
    for from = 1, #rows, PIECE do
        local out = { "return {" }
        for i = from, math.min(#rows, from + PIECE - 1) do
            Write(rows[i], out)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
        pieces[#pieces + 1] = table.concat(out)
    end
    return pieces
end

-- The rows back from their pieces (nil if a piece won't load).
local function Rows(pieces)
    local rows = {}
    for _, piece in ipairs(pieces or {}) do
        local chunk = loadstring(piece)
        local ok, part = pcall(chunk or error)
        if not ok or type(part) ~= "table" then return nil end
        for i = 1, #part do rows[#rows + 1] = part[i] end
    end
    return rows
end

local function Last(r)
    local t = r.started or 0
    local tr, ev = r.track, r.ev
    if type(tr) == "table" and type(tr[#tr]) == "table" then t = math.max(t, tr[#tr][1] or 0) end
    if type(ev) == "table" and type(ev[#ev]) == "table" then t = math.max(t, ev[#ev][1] or 0) end
    return t
end

--- A log packed: what goes in its place in the account's file. nil when the check fails (the log is
--- then left as it is).
function YR.RunPack(r)
    if type(r) ~= "table" or r.packed then return nil end
    local track, ev = type(r.track) == "table" and r.track or {}, type(r.ev) == "table" and r.ev or {}
    local packed = { track = Pieces(track), ev = Pieces(ev) }
    -- unpacked again it must be the same log: every row, every field, every value
    local t2, e2 = Rows(packed.track), Rows(packed.ev)
    if not t2 or not e2 or not Same(track, t2) or not Same(ev, e2) then return nil end
    local stub = { packed = packed, last = Last(r), samples = #track, events = #ev }
    -- what a log has beside its rows (when it began, whether it was stopped) stays as it is
    for k, v in pairs(r) do
        if k ~= "track" and k ~= "ev" and type(v) ~= "table" then stub[k] = v end
    end
    return stub
end

--- A packed log as the tables it was (nil if it won't load).
function YR.RunUnpack(stub)
    if type(stub) ~= "table" or not stub.packed then return stub end
    local track, ev = Rows(stub.packed.track), Rows(stub.packed.ev)
    if not track or not ev then return nil end
    local r = { track = track, ev = ev }
    for k, v in pairs(stub) do
        if k ~= "packed" and k ~= "last" and k ~= "samples" and k ~= "events" then r[k] = v end
    end
    return r
end

--- This character's log hooked up as YippRouteDB.runs[you], and every other log in the account's file
--- packed. Once a login, when the character's name is known (Log.lua asks). Returns how many were packed.
function YR.RunsAttach()
    if attached then return 0 end
    local key = YR.CharKey()
    attached = key
    local runs = YippRouteDB.runs
    local mine = runs[key]                      -- still in the account's file: from before the move
    if type(mine) == "table" and mine.packed then
        local whole = YR.RunUnpack(mine)
        if whole then
            mine = whole
        else
            -- it won't load: kept as it is beside the new log, not thrown away
            _G.HeadstartRunLogKept, mine = mine, nil
        end
    end
    local own = _G.HeadstartRunLog
    if type(own) ~= "table" or (type(mine) == "table" and Last(mine) > Last(own)) then own = mine end
    _G.HeadstartRunLog = own
    runs[key] = own                             -- nil when this character has no log
    local packed = 0
    for other, r in pairs(runs) do
        if other ~= key and type(r) == "table" and not r.packed then
            local stub = YR.RunPack(r)
            if stub then
                runs[other] = stub
                packed = packed + 1
            end
        end
    end
    return packed
end

--- At logout: this character's log goes to its own file and out of the account's.
function YR.RunsDetach()
    if not attached or not YippRouteDB or type(YippRouteDB.runs) ~= "table" then return end
    _G.HeadstartRunLog = YippRouteDB.runs[attached]
    YippRouteDB.runs[attached] = nil
end

function YR.StartRunStore()
    -- listened for only while this character has a log to move (declared after the log's own part, so
    -- a log begun in the same moment is seen)
    YR.Part(function()
        return attached ~= nil and (YippRouteDB.runs[attached] ~= nil or _G.HeadstartRunLog ~= nil)
    end, { "PLAYER_LOGOUT" }, YR.RunsDetach)
end
