-- Boat timer: when the boat or zeppelin at your dock arrives and leaves, and on board when it gets in.
--   The timetable is Headstart's own (Data/Boats.lua: each route's round and its docks, measured in the game
--   with /headstart boats). Where each boat is in its round is kept right by what Headstart players see: a
--   player who rides one tells the others - in guild, in a group, and to those nearby where the game lets an
--   addon - when it left or got in, and a player who logs in asks for the latest. That is the only way the
--   timetable survives a server restart that moves the boats, so it is done by every Headstart player,
--   whether they show the timer or not (the owner, 2026-10-15: "sending to the others is straight up needed
--   for it to work for those who want to see the boats leave"). It shows them nothing and costs next to
--   nothing: away from a dock's zone it only listens for the zone changing and for the messages; in one, a
--   look every two seconds; within a few hundred yards of a dock, ten looks a second, to see a ride begin.
--   The timer itself (on screen at a dock) starts off: YippRouteDB.boatTimer. What was seen:
--   YippRouteDB.boatSeen[route] = { ref, t, dock, kind, at, from } - ref the realm's clock as it left its
--   first dock in that round, t what was seen (dock's arrival "in" or departure "go") and when.
--   Quality of life switched off: none of it, the sharing neither.
local _, YR = ...

local PREFIX = "HeadstartBoat"
local ZONE = 6000               -- yards: a dock this near on the same continent - looked at every two seconds
local NEAR = 400                -- yards: looked at ten times a second (a ride can begin)
local AT = 60                   -- yards: a departure or an arrival this near a dock is that dock's
local SHOW = 120                -- yards: the timer shows the boats of the docks this near
local AWAY = 100                -- yards: a departure counts once it is this far from where it began
local STILL = 1.5               -- seconds without being carried: stopped
local SLOW, FAST = 2, 0.1

local offset                    -- the realm's clock = GetTime() + offset
local function Plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local function Realm(t) return t + (offset or ((GetServerTime and GetServerTime() or 0) - GetTime())) end
local function Now() return Realm(GetTime()) end

-- ---------------------------------------------------------------------------
-- The timetable, put right by what was seen
-- ---------------------------------------------------------------------------
local function Seen()
    YippRouteDB.boatSeen = YippRouteDB.boatSeen or {}
    return YippRouteDB.boatSeen
end

--- A route's timetable: { period, ref, docks }, ref from the latest thing seen of it (a restart may have
--- moved it) or else from the round measured.
function YR.BoatTable(key)
    local data = YR.BoatData and YR.BoatData[key]
    if not data then return nil end
    local seen = YippRouteDB.boatSeen and YippRouteDB.boatSeen[key]
    return { period = data.period, docks = data.docks, ref = (seen and tonumber(seen.ref)) or data.ref, seen = seen }
end

local function NextAt(tt, offsetIn, now)
    local base = tt.ref + offsetIn
    return base + math.ceil((now - base) / tt.period) * tt.period
end

-- Something seen of a route: it left (go) or got in at (in) its dock `i` at `t` by the realm's clock. Kept
-- when it is newer than what is kept; returns whether it was. `shift` is how far off the timetable was until
-- then, in seconds (+ the boat later than it said): near nought across a server restart would mean the boats
-- keep the clock's own times, not the realm's uptime - what is not known yet (/headstart boats seen).
local function Learn(key, i, kind, t, from)
    local data = YR.BoatData and YR.BoatData[key]
    local d = data and data.docks[i]
    local off = d and (kind == "go" and d[6] or kind == "in" and d[5])
    if not off then return false end
    local seen = Seen()
    local was = seen[key]
    if was and (tonumber(was.t) or 0) >= t then return false end
    local P, ref = data.period, t - off
    local before = (was and tonumber(was.ref)) or data.ref
    local shift = ((ref - before + P / 2) % P) - P / 2
    seen[key] = { ref = ref, t = t, dock = i, kind = kind, at = time(), from = from, shift = shift }
    return true
end

--- What was last seen of each route, and how far off the timetable was then (/headstart boats seen), as lines.
function YR.BoatSeenLines()
    local lines, now, names, keys = {}, time(), {}, {}
    for _, r in ipairs(YR.BoatRoutes and YR.BoatRoutes() or {}) do names[r[1]] = r[2] end
    for key in pairs(YippRouteDB.boatSeen or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local s = YippRouteDB.boatSeen[key]
        local data = YR.BoatData and YR.BoatData[key]
        local dock = s and data and data.docks[tonumber(s.dock) or 0]
        if dock then
            local ago = math.max(0, now - (tonumber(s.at) or now))
            local when = ago < 3600 and ("%d min ago"):format(ago / 60) or ago < 172800 and ("%.1f h ago"):format(ago / 3600)
                or ("%d days ago"):format(ago / 86400)
            local shift = tonumber(s.shift)
            lines[#lines + 1] = ("%s: %s at %s, %s, told by %s%s"):format(names[key] or key, s.kind == "in" and "got in" or "left", dock[1],
                when, tostring(s.from or "?"), shift and (", %+.1f s off the timetable"):format(shift) or "")
        end
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- Telling the others, and hearing them
-- ---------------------------------------------------------------------------
local yell = true               -- (the game may refuse an addon's yell outside instances: then not tried again)
local function Send(msg)
    local chat = C_ChatInfo
    if not (chat and chat.SendAddonMessage) then return end
    if IsInGuild and IsInGuild() then pcall(chat.SendAddonMessage, PREFIX, msg, "GUILD") end
    if IsInGroup and IsInGroup() then
        local to = (IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) and "INSTANCE_CHAT") or (IsInRaid and IsInRaid() and "RAID") or "PARTY"
        pcall(chat.SendAddonMessage, PREFIX, msg, to)
    end
    if yell then
        local ok, result = pcall(chat.SendAddonMessage, PREFIX, msg, "YELL")
        if not ok or not (result == nil or result == true or result == 0) then yell = false end
    end
end

local function Tell(key, i, kind, t) Send(("1 O %s %d %s %.2f"):format(key, i, kind, t)) end

-- Asked for the latest (a player logging in): answered a few seconds later, unless another answered the same
-- or newer first - so a guild of Headstart players answers once, not all at once.
local answering, answeredAt, heardSince = false, 0, {}
local function Answer()
    answering = false
    answeredAt = GetTime()
    local now = Now()
    for key, s in pairs(Seen()) do
        local t = tonumber(s.t)
        if t and now - t < 86400 and not (heardSince[key] and heardSince[key] >= t - 1) and YR.BoatData and YR.BoatData[key] then
            Tell(key, tonumber(s.dock) or 1, s.kind == "in" and "in" or "go", t)
        end
    end
end

local function IsMe(sender)
    local me = UnitName("player")
    return sender == me or (Ambiguate and Ambiguate(sender, "short") == me)
end

local CHANNELS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true, YELL = true, SAY = true }
-- What another player's addon sent is text from a stranger: no escape codes (|c, |T, |H), no control
-- characters, and no longer than a message of ours can be, before anything is read from it.
local function Sanitise(text, most)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|", ""):gsub("[%c]", "")
    return text:sub(1, most)
end

local function Heard(msg, channel, sender)
    msg, sender = Sanitise(msg, 80), Sanitise(sender, 64)
    if not CHANNELS[channel] or not msg then return end
    local ok, me = pcall(IsMe, sender or "")
    if ok and me then return end
    if msg == "1 Q" then
        if not answering and GetTime() - answeredAt > 60 then
            answering, heardSince = true, {}
            C_Timer.After(2 + math.random() * 6, Answer)
        end
        return
    end
    local key, i, kind, t = msg:match("^1 O (%w+) (%d+) (%a+) ([%d%.]+)$")
    t, i = tonumber(t), tonumber(i)
    if not (key and t and i and (kind == "go" or kind == "in")) then return end
    -- what can't be true is not taken: a time ahead of now, or days old
    local now = Now()
    if t > now + 10 or t < now - 3 * 86400 then return end
    if answering then heardSince[key] = math.max(heardSince[key] or 0, t) end
    Learn(key, i, kind, t, Plain(sender) or "?")
end

-- ---------------------------------------------------------------------------
-- Seeing it yourself: a ride's departure and arrival at a dock
-- ---------------------------------------------------------------------------
local function DocksNear(x, y, map, within)
    local out = {}
    for key, data in pairs(YR.BoatData or {}) do
        for i, d in ipairs(data.docks) do
            if d[2] == map then
                local dist = math.sqrt((x - d[3]) ^ 2 + (y - d[4]) ^ 2)
                if dist <= within then out[#out + 1] = { key = key, i = i, dist = dist } end
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end
YR.BoatDocksNear = DocksNear

-- the dock nearest (x, y) on continent `map`, within `within` yards: its route, its place in the round and
-- how far (nil when none) - for the look, ten times a second near a dock, so it makes nothing new
local function Nearest(x, y, map, within)
    local bestKey, bestI, best
    for key, data in pairs(YR.BoatData or {}) do
        for i, d in ipairs(data.docks) do
            if d[2] == map then
                local dist = math.sqrt((x - d[3]) ^ 2 + (y - d[4]) ^ 2)
                if dist <= within and (not best or dist < best) then bestKey, bestI, best = key, i, dist end
            end
        end
    end
    return bestKey, bestI, best
end

local last, moving, lastMove, pending
local board                     -- { key, i }: on board, left from that dock
local Paint                     -- the timer on screen (below)

local function Seen1(kind, t, x, y, map)
    local key, i = Nearest(x, y, map, AT)
    if not key then return nil end         -- at sea: a loading screen's pause, not a dock
    local realm = Realm(t)
    if Learn(key, i, kind, realm, "you") then Tell(key, i, kind, realm) end
    return { key = key, i = i }
end

local ticker, every
local Look
local function Every(s)
    if every == s then return end
    if ticker then ticker:Cancel() ticker = nil end
    every = s
    if s then ticker = C_Timer.NewTicker(s, Look) end
end

function Look()
    local y, x, _, map = UnitPosition("player")
    x, y, map = Plain(x), Plain(y), Plain(map)
    if not (x and y) then Every(nil) return end
    local now = GetTime()
    if every == FAST and last then
        local walking = (IsPlayerMoving and IsPlayerMoving()) or (IsFalling and IsFalling())
        if last.map ~= map then
            moving, lastMove = true, now                -- a loading screen on the way: another continent
            if pending then                             -- (and a departure waiting to be counted is one)
                local dock = Seen1("go", pending.t, pending.x, pending.y, pending.map)
                board = dock and { key = dock.key, i = dock.i } or board
                pending = nil
            end
        elseif walking then
            if moving then lastMove = now end
        else
            local carried = math.sqrt((x - last.x) ^ 2 + (y - last.y) ^ 2) > 0.02
            if carried then
                lastMove = now
                if moving == false then
                    -- it may be leaving: counted once it is away from where it began (a dock's creep is not)
                    pending = { t = (last.t + now) / 2, x = last.x, y = last.y, map = map }
                end
                moving = true
                if pending and (pending.map ~= map or math.sqrt((x - pending.x) ^ 2 + (y - pending.y) ^ 2) > AWAY) then
                    local dock = Seen1("go", pending.t, pending.x, pending.y, pending.map)
                    board = dock and { key = dock.key, i = dock.i } or board
                    pending = nil
                end
            elseif moving == nil then
                moving = false                          -- standing: its next move is a departure
            elseif moving and now - lastMove > STILL then
                moving = false
                pending = nil
                if Seen1("in", lastMove, x, y, map) then board = nil end
            end
        end
    end
    last = last or {}                           -- (one table, kept: this runs ten times a second)
    last.x, last.y, last.map, last.t = x, y, map, now
    local nearest, _, dist = Nearest(x, y, map, ZONE)
    local riding = moving and lastMove and now - lastMove < 10
    if riding or (nearest and dist <= NEAR) then
        Every(FAST)
    elseif nearest then
        Every(SLOW)
        moving, board = nil, nil
    else
        Every(nil)
        moving, board = nil, nil
    end
    if Paint then Paint(x, y, map) end
end

local loginAsked = false
local function OnEvent(_, event, a, b, c, d)
    if event == "CHAT_MSG_ADDON" then
        if a == PREFIX then Heard(b, c, d) end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        last, moving, pending = nil, nil, nil
        if YR.BoatTimerApply then C_Timer.After(1, YR.BoatTimerApply) end
        if (a or b) and not loginAsked then        -- the login or a reload: the latest, asked for once
            loginAsked = true
            C_Timer.After(15, function() Send("1 Q") end)
        end
    end
    Look()
end

-- the realm's second watched until it turns: then its clock is known to a frame
local function Sync()
    local was = GetServerTime and GetServerTime()
    if not was then return end
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self)
        local now = GetServerTime()
        if now ~= was then
            offset = now - GetTime()
            self:SetScript("OnUpdate", nil)
        end
    end)
end

YR.Part(function() return YR.QoLOn() end, { "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "CHAT_MSG_ADDON" }, OnEvent, {
    start = function()
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
        if not offset then Sync() end
        Look()
    end,
    stop = function()
        Every(nil)
        last, moving, pending, board = nil, nil, nil, nil
        if Paint then Paint() end
    end,
})

-- ---------------------------------------------------------------------------
-- The timer on screen: at a dock, its boats; on board, where it gets in next
-- ---------------------------------------------------------------------------
local function Clock(s)
    s = math.max(0, math.floor(s + 0.5))
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

--- What the timer says at (x, y, map) at the realm's time `now` (lines of { left, right }), and whether you
--- are on board - for the timer, and the tests.
function YR.BoatLines(x, y, map, now)
    local lines = {}
    if board then
        local tt = YR.BoatTable(board.key)
        if tt then
            local j = board.i % #tt.docks + 1
            local d = tt.docks[j]
            if d[5] then lines[1] = { "Arriving at " .. d[1], Clock(NextAt(tt, d[5], now) - now) } end
        end
        return lines, true
    end
    if not (x and y and map) then return lines end
    for _, near in ipairs(DocksNear(x, y, map, SHOW)) do
        local tt = YR.BoatTable(near.key)
        local d = tt and tt.docks[near.i]
        if d then
            local to = tt.docks[near.i % #tt.docks + 1][1]
            local leave = NextAt(tt, d[6], now)
            local arrive = d[5] and NextAt(tt, d[5], now)
            if arrive and arrive > leave then
                lines[#lines + 1] = { "To " .. to, "in, leaves " .. Clock(leave - now) }
            elseif arrive then
                lines[#lines + 1] = { "To " .. to, "in " .. Clock(arrive - now) .. ", leaves " .. Clock(leave - now) }
            else
                lines[#lines + 1] = { "To " .. to, "leaves " .. Clock(leave - now) }
            end
        end
    end
    return lines
end

local hud
local function Build()
    local S = YR.Style
    hud = CreateFrame("Frame", "HeadstartBoatTimer", UIParent)
    hud:SetSize(280, 28)
    hud:SetFrameStrata("MEDIUM")
    S.Fill(hud, S.C.window)
    S.Border(hud, S.C.line)
    hud.rows = {}
    for i = 1, 4 do
        local l = S.Text(hud, 12)
        l:SetPoint("TOPLEFT", 10, -7 - (i - 1) * 18)
        local r = S.Text(hud, 12, S.C.accent)
        r:SetPoint("TOPRIGHT", -10, -7 - (i - 1) * 18)
        hud.rows[i] = { l, r }
    end
    local p = YippRouteDB.boatPos
    hud:SetPoint("TOP", UIParent, "TOP", p and p[1] or 0, p and p[2] or -150)
    hud:SetMovable(true)
    hud:EnableMouse(true)
    hud:RegisterForDrag("LeftButton")
    hud:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx = self:GetCenter()
        YippRouteDB.boatPos = { math.floor(cx - UIParent:GetWidth() / 2 + 0.5), math.floor(self:GetTop() - UIParent:GetTop() + 0.5) }
    end)
    hud:SetScript("OnEnter", function(self)
        S.Tip(self, "Headstart's boat timetable, kept right by what Headstart players see as they ride. Shift-drag to move.")
    end)
    hud:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hud:Hide()
end

-- what the timer last showed: drawn again only when that can have changed - the realm's second, the dock
-- nearest, getting on or off - not at every look (ten a second near a dock)
local shown = {}
function Paint(x, y, map)
    if not (YR.Option("boatTimer") and YR.BoatData) then
        if hud then hud:Hide() end
        shown.sec = nil
        return
    end
    local now = Now()
    local sec, key, i = math.floor(now), nil, nil
    if x and y and map then key, i = Nearest(x, y, map, SHOW) end
    if sec == shown.sec and key == shown.key and i == shown.i and board == shown.board then return end
    shown.sec, shown.key, shown.i, shown.board = sec, key, i, board
    local lines = YR.BoatLines(x, y, map, now)
    if #lines == 0 then
        if hud then hud:Hide() end
        return
    end
    if not hud then Build() end
    for i, row in ipairs(hud.rows) do
        local l = lines[i]
        row[1]:SetText(l and l[1] or "")
        row[2]:SetText(l and l[2] or "")
    end
    hud:SetHeight(14 + math.min(#lines, 4) * 18)
    hud:Show()
end

-- ---------------------------------------------------------------------------
-- The boats on the world map: each where it is in its round, along its course - the game's own path for it
-- (Data/Boats.lua) - turned the way it is heading. Between two docks it is put at the share of the way that
-- the share of the time gone says (a boat slows into a dock, so near one it may be a boat's length off).
-- ---------------------------------------------------------------------------
local function Heading(a, b) return math.atan2(b[3] - a[3], b[2] - a[2]) end

-- The course from node `from` to node `to` (round the end of the path if need be; a step to another continent
-- is the loading screen, no way at all), worked out once: the nodes in turn and the way gone at each.
local legs = {}
local function Leg(path, from, to)
    local byPath = legs[path] or {}
    legs[path] = byPath
    local id = from * 100000 + to
    if byPath[id] then return byPath[id] end
    local seq, i = { from }, from
    while i ~= to and #seq <= #path do
        i = i % #path + 1
        seq[#seq + 1] = i
    end
    local gone = { 0 }
    for k = 1, #seq - 1 do
        local a, b = path[seq[k]], path[seq[k + 1]]
        gone[k + 1] = gone[k] + (a[1] == b[1] and math.sqrt((b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2) or 0)
    end
    byPath[id] = { seq = seq, gone = gone, total = gone[#gone] }
    return byPath[id]
end

-- the share `f` of the way along that course: continent, X, Y, heading
local function Along(path, from, to, f)
    local leg = Leg(path, from, to)
    local seq, gone = leg.seq, leg.gone
    local want = f * leg.total
    for k = 1, #seq - 1 do
        local len = gone[k + 1] - gone[k]
        if len > 0 and want <= gone[k + 1] then
            local a, b = path[seq[k]], path[seq[k + 1]]
            local t = (want - gone[k]) / len
            return a[1], a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, Heading(a, b)
        end
    end
    local z = path[to]
    return z[1], z[2], z[3], Heading(z, path[to % #path + 1])
end

--- Where a route's boat is at the realm's time `now`: continent, X, Y, heading (radians: 0 north, turning
--- west), then "at" and the dock it lies at, or "to" and the dock it is bound for, and the seconds until it
--- leaves or gets in. Nil for a route without a course. (Asked every frame while the map is open, so it
--- makes nothing new: the timetable is read straight, not through YR.BoatTable.)
function YR.BoatWhere(key, now)
    local data = YR.BoatData and YR.BoatData[key]
    local path = data and data.path
    if not (path and #path > 1) then return nil end
    local seen = YippRouteDB.boatSeen and YippRouteDB.boatSeen[key]
    local P, docks = data.period, data.docks
    local tau = (now - ((seen and tonumber(seen.ref)) or data.ref)) % P
    for i, d in ipairs(docks) do
        if d[5] and d[7] and (tau - d[5]) % P <= (d[6] - d[5]) % P then
            local node = path[d[7]]
            return node[1], node[2], node[3], Heading(node, path[d[7] % #path + 1]), "at", i, (d[6] - tau) % P
        end
    end
    for i, d in ipairs(docks) do
        local nxt = docks[i % #docks + 1]
        local leg = ((nxt[5] or nxt[6]) - d[6]) % P
        local into = (tau - d[6]) % P
        if into <= leg and d[7] and nxt[7] then
            local c, x, y, h = Along(path, d[7], nxt[7], leg > 0 and into / leg or 0)
            return c, x, y, h, "to", i % #docks + 1, leg - into
        end
    end
end

-- whose a route is: the Alliance's boats, the Horde's zeppelins; the rest (Ratchet - Booty Bay, and the routes
-- not yet known) take both
local ALLIANCE = { menethilAuberdine = true, menethilTheramore = true, ruttheranAuberdine = true, stormwindAuberdine = true,
    feathermoon = true }
local HORDE = { orgUC = true, orgGG = true, ucGG = true }
local ROUTE = {}
for _, r in ipairs(YR.BoatRoutes and YR.BoatRoutes() or {}) do ROUTE[r[1]] = r end

local pins, provider, pinLevel, vec = {}, nil, nil, nil
-- How big a boat is drawn, on screen: bigger the closer the map shows the world - a zone more than its
-- continent, zoomed in more than out - as the map's own art grows, but never too small to see on a continent
-- nor bigger than a hand when zoomed right in (the owner, 2026-10-15: one size whatever the zoom looked as
-- if it shrank). It goes with the square root of the map's size on screen per yard, so it grows slower than
-- the map. A zeppelin, wider, a fifth smaller.
local SMALL, BIG, GROW = 32, 80, 130
local worldWide = {}            -- uiMapID -> the yards the map is wide (false: not known)
local function PinSize(id, w, scale)
    local yards = worldWide[id]
    if yards == nil and C_Map.GetMapWorldSize then
        local ok, wide = pcall(C_Map.GetMapWorldSize, id)
        yards = ok and tonumber(wide) and wide > 0 and wide or false
        worldWide[id] = yards
    end
    local screen = SMALL
    if yards then screen = math.min(BIG, math.max(SMALL, GROW * math.sqrt(w * scale / yards))) end
    return screen / scale       -- (the pin is on the canvas, which the zoom scales)
end
local function MapOn() return YR.QoLOn() and YR.Option("boatTimer") and YippRouteDB.boatMap ~= false end

-- Only your own side's boats and the ones both take: an Alliance player has no use for the zeppelins, nor a
-- Horde player for the Alliance's boats (the owner, 2026-10-15).
local function Mine(key, side)
    if ALLIANCE[key] then return side ~= "Horde" end
    if HORDE[key] then return side ~= "Alliance" end
    return true
end

local function Tip(pin)
    local i = pin.info
    if not i.key then return end
    local data = YR.BoatData and YR.BoatData[i.key]
    local dock = data and data.docks[i.dock]
    local what = i.what == "at" and ("At %s, leaves in %s"):format(dock and dock[1] or "?", Clock(i.left))
        or ("To %s, in %s"):format(dock and dock[1] or "?", Clock(i.left))
    YR.Style.Tip(pin, (ROUTE[i.key] and ROUTE[i.key][2] or i.key) .. "\n" .. what)
end

local function NewPin(canvas, key)
    local S = YR.Style
    local pin = CreateFrame("Frame", nil, canvas)
    pin.info = {}
    pin.icon = pin:CreateTexture(nil, "OVERLAY")
    pin.icon:SetAllPoints()
    local kind = ROUTE[key] and ROUTE[key][3]
    -- The game's own, seen from above and from one sheet of map icons: a boat is the Island Expeditions' (the
    -- Alliance's blue for the Alliance's routes, the red for the rest), a zeppelin the Horde's airship from
    -- the battlegrounds' maps, its two balloons either side. Headstart's own drawing only if the game lacks one.
    local atlas = kind == "zeppelin" and "Vehicle-Air-Horde" or (ALLIANCE[key] and "Islands-AllianceBoat" or "Islands-HordeBoat")
    if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) and pin.icon.SetAtlas) then atlas = nil end
    if atlas then pin.icon:SetAtlas(atlas) else pin.icon:SetTexture(S.ART .. (kind == "zeppelin" and "map_zeppelin" or "map_boat")) end
    pin.grow = kind == "zeppelin" and 0.8 or 1
    -- pointed at for the tooltip, but a click goes on to the map (to zoom, to go in or out of a zone)
    pin:EnableMouse(true)
    if pin.SetMouseClickEnabled then pcall(pin.SetMouseClickEnabled, pin, false) end
    pin:SetScript("OnEnter", Tip)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return pin
end

-- the layer the map keeps for things that move (below the group's arrows), or well above its art
local function Level(map, canvas)
    if pinLevel then return pinLevel end
    local m = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
    local ok, level = false, nil
    if m and m.GetValidFrameLevel then ok, level = pcall(m.GetValidFrameLevel, m, "PIN_FRAME_LEVEL_VEHICLE_BELOW_GROUP_MEMBER") end
    pinLevel = ok and tonumber(level) or canvas:GetFrameLevel() + 200
    return pinLevel
end

-- where a boat is on map `id`: x, y (0 to 1 across it), then what YR.BoatWhere says; nil when not on it
local function OnMap(key, id, now)
    local c, x, y, heading, what, dock, left = YR.BoatWhere(key, now)
    if not c then return nil end
    vec = vec or CreateVector2D(0, 0)
    if vec.SetXY then vec:SetXY(x, y) else vec.x, vec.y = x, y end
    local ok, _, v = pcall(C_Map.GetMapPosFromWorldPos, c, vec, id)
    if not (ok and v) then return nil end
    local mx, my = v:GetXY()
    if not (mx and my) or mx < 0 or mx > 1 or my < 0 or my > 1 then return nil end
    return mx, my, heading, what, dock, left
end

--- The boats put where they are on the map shown now: ten times a second while the map is open (a boat moves a
--- few pixels in that: every frame made new map positions by the hundred - the performance audit, 2026-10-20), and
--- at once when it turns to another map, zooms or changes size (the map tells its data providers, Headstart's among
--- them).
function YR.BoatMapRefresh()
    local map = WorldMapFrame
    local on = MapOn() and map and map:IsShown() and map.GetMapID and map.GetCanvas and C_Map and C_Map.GetMapPosFromWorldPos
    local id = on and map:GetMapID()
    local canvas = on and map:GetCanvas()
    local w, h = canvas and canvas:GetWidth(), canvas and canvas:GetHeight()
    local scale = on and map.GetCanvasScale and map:GetCanvasScale() or 1
    local size = id and w and w > 0 and PinSize(id, w, scale)
    local now, side = Now(), id and UnitFactionGroup("player")
    for key in pairs(YR.BoatData or {}) do
        local mx, my, heading, what, dock, left
        if id and w and w > 0 and Mine(key, side) then mx, my, heading, what, dock, left = OnMap(key, id, now) end
        local pin = pins[key]
        if mx then
            if not pin then
                pin = NewPin(canvas, key)
                pins[key] = pin
            end
            local level = Level(map, canvas)
            if pin.level ~= level then
                pin:SetFrameLevel(level)
                pin.level = level
            end
            if pin.size ~= size then
                pin:SetSize(size * pin.grow, size * pin.grow)
                pin.size = size
            end
            local px, py = mx * w, -my * h
            if pin.px ~= px or pin.py ~= py then           -- (where it was a moment ago: not placed again)
                pin.px, pin.py = px, py
                pin:ClearAllPoints()
                pin:SetPoint("CENTER", canvas, "TOPLEFT", px, py)
            end
            if pin.icon.SetRotation then pin.icon:SetRotation(heading or 0) end
            local i, whole = pin.info, math.floor(left or 0)
            i.key, i.what, i.dock, i.left = key, what, dock, left
            pin:Show()
            -- the tooltip of the boat pointed at counts down with it
            if i.whole ~= whole and GameTooltip.IsOwned and GameTooltip:IsOwned(pin) then Tip(pin) end
            i.whole = whole
        elseif pin then
            pin:Hide()
        end
    end
end

--- How many boats are on the map now (for the tests).
function YR.BoatMapPins()
    local n = 0
    for _, pin in pairs(pins) do if pin:IsShown() then n = n + 1 end end
    return n
end
function YR.BoatMapPinFor(key) return pins[key] end

-- Headstart's data provider on the world map, the way the game's own map icons are kept: told when the map
-- opens, turns to another map, zooms or changes size, and run every frame the map is open. Added while the
-- boats are on the map, taken off when they are not (then it costs nothing at all).
local function Provider()
    if provider or not MapCanvasDataProviderMixin then return provider end
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    local function Refresh() YR.BoatMapRefresh() end
    provider.RefreshAllData = Refresh
    provider.OnShow = Refresh
    provider.OnMapChanged = Refresh
    provider.OnCanvasScaleChanged = Refresh
    provider.OnCanvasSizeChanged = Refresh
    -- (the map calls this every frame it is open, and says nothing of the time: ten times a second is plenty)
    local at = -1
    provider.OnUpdate = function()
        local now = GetTime()
        if now and now - at < 0.09 and now >= at then return end     -- (0.09: a tenth, give or take a frame)
        at = now or 0
        Refresh()
    end
    provider.RemoveAllData = function() for _, pin in pairs(pins) do pin:Hide() end end
    return provider
end

local added = false
local function MapProvider(on)
    local map = WorldMapFrame
    if not (map and map.AddDataProvider and Provider()) or on == added then return end
    added = on
    if on then
        map:AddDataProvider(provider)
        if map.RegisterDataProviderOnUpdate then map:RegisterDataProviderOnUpdate(provider) end
    else
        if map.UnregisterDataProviderOnUpdate then map:UnregisterDataProviderOnUpdate(provider) end
        map:RemoveDataProvider(provider)
    end
end

--- The timer switched on or off (the settings).
function YR.BoatTimerApply()
    if YR.QoLOn() then Look() elseif hud then hud:Hide() end
    if not YR.Option("boatTimer") and hud then hud:Hide() end
    MapProvider(MapOn() and true or false)
    YR.BoatMapRefresh()
end
