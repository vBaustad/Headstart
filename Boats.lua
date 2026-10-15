-- Boats and zeppelins, measured for a timetable of Headstart's own. TEMPORARY: the owner's tool for it.
--   /headstart boats opens a list of every boat and zeppelin on Forever, each with a button. Stand on one
--   while it lies at its dock, press its button, and stand still: it is timed as it leaves, at every stop
--   and start on the way, and as it leaves that same dock again - one round trip, to a few hundredths of a
--   second, and when by the realm's clock it left. Two rounds some days apart (one after a server restart)
--   give each cycle closely enough for a timetable that holds for weeks, and say whether the schedule
--   survives a restart. Written down in YippRouteDB.boatTimes, read off the saved file to make the
--   timetable. The owner's idea (2026-10-15: "stand on a boat, press the button for that boat, stand still
--   until I'm back at the exact same spot"). Nauticus does the same from many players' rides; it is neither
--   needed nor used here - nothing of its code or data. Nothing runs until a button is pressed, and
--   nothing once the round is done.
local _, YR = ...

-- Every boat and zeppelin on Forever, by its two ends (the Deeprun Tram's cycle is in the game's own
-- files: TransportAnimation, 143.333 seconds). The last four are Forever's own.
local ROUTES = {
    { "orgUC", "Orgrimmar - Undercity", "zeppelin" },
    { "orgGG", "Orgrimmar - Grom'gol", "zeppelin" },
    { "ucGG", "Undercity - Grom'gol", "zeppelin" },
    { "ratchetBB", "Ratchet - Booty Bay", "boat" },
    -- (on Forever it goes on to Southshore: Auberdine, Menethil Harbor, Southshore and back - a round of three
    -- stops, measured the same way: done when it leaves the dock you pressed the button at again)
    { "menethilAuberdine", "Auberdine - Menethil Harbor - Southshore", "boat" },
    { "menethilTheramore", "Menethil Harbor - Theramore", "boat" },
    { "ruttheranAuberdine", "Rut'theran Village - Auberdine", "boat" },
    { "feathermoon", "Feathermoon - Feralas coast", "boat" },
    { "stormwindAuberdine", "Stormwind Harbor - Auberdine", "boat" },
    { "zephrasMulgore", "Zephras Isle - Mulgore", "skycutter" },
    { "zephrasDalaran", "Zephras Isle - Dalaran", "skycutter" },
    { "rivergladesTanaris", "Riverglades - Tanaris", "boat" },
}
function YR.BoatRoutes() return ROUTES end

local STEP = 0.05               -- seconds between two looks at where you are
local STILL = 1.5               -- seconds without being carried: stopped
local HOME = 25                 -- yards: a departure this near the first is from the same dock
local NUDGE = 30                -- yards: a "departure" that stops this near where it began only shifted at the dock
local AWAY = 100                -- yards (or another continent): it has really been somewhere
local run                       -- the round being measured: { key, name, events, first }
local offset                    -- the realm's clock = GetTime() + offset (to a frame, once its second turns)
local last, moving, lastMove
local Paint

local function Plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end
local function Realm(t) return t + (offset or ((GetServerTime and GetServerTime() or 0) - GetTime())) end

--- Seconds as minutes, seconds and hundredths: "5:42.37".
function YR.BoatClock(s)
    s = tonumber(s) or 0
    return ("%d:%05.2f"):format(math.floor(s / 60), s % 60)
end

local function Store(r, period)
    YippRouteDB.boatTimes = YippRouteDB.boatTimes or {}
    local list = YippRouteDB.boatTimes[r.key] or {}
    YippRouteDB.boatTimes[r.key] = list
    list[#list + 1] = { period = period, left = r.first.t, at = time(), events = r.events,
        build = select(2, GetBuildInfo()) }
end

local function Stop(said)
    if not run then return end
    run = nil
    last, moving, lastMove = nil, nil, nil
    YR.ApplyParts()
    if said then YR.Print("boats: " .. said) end
    if Paint then Paint() end
end

local function Far(e, x, y, map) return map ~= e.map or math.sqrt((x - e.x) ^ 2 + (y - e.y) ^ 2) > AWAY end

local function Event(kind, t, x, y, map)
    local e = { kind = kind, t = Realm(t), x = math.floor(x * 10 + 0.5) / 10, y = math.floor(y * 10 + 0.5) / 10, map = map,
        place = GetSubZoneText and Plain(GetSubZoneText()) or nil }
    local before = run.events[#run.events]
    -- It only shifted at the dock (Ratchet, the first round of 2026-10-15: a yard's creep just after the button
    -- was pressed was taken for the departure, and the real one a minute later for the end of the round):
    -- a departure and its stop this close together are no departure at all.
    if kind == "stop" and before and before.kind == "go" and before.map == map
        and math.sqrt((x - before.x) ^ 2 + (y - before.y) ^ 2) < NUDGE then
        run.events[#run.events] = nil
        if run.first == before then run.first = nil end
        return
    end
    -- A stop just before a loading screen is your position held while the next continent loads, not a dock
    -- (held some 10 to 20 seconds; a boat lies a minute at a dock)
    if kind == "zone" and before and before.kind == "stop" and e.t - before.t < 25 then before.kind = "pause" end
    run.events[#run.events + 1] = e
    local where = e.place and e.place ~= "" and e.place or (GetRealZoneText and Plain(GetRealZoneText()) or "")
    if kind == "go" and not run.first then
        run.first = e
        YR.Print(("boats: %s left %s at %s. Stand still until it has come back here and left again."):format(run.name, where,
            date("%H:%M:%S", math.floor(e.t))))
    elseif kind == "go" and run.far and e.map == run.first.map and e.t - run.first.t > 60
        and math.sqrt((e.x - run.first.x) ^ 2 + (e.y - run.first.y) ^ 2) <= HOME then
        local period = e.t - run.first.t
        Store(run, period)
        Stop(("%s: round trip %s. Written down - you can get off."):format(run.name, YR.BoatClock(period)))
        return
    elseif kind == "stop" then
        -- said a moment later: a stop that turns out to be a loading screen's pause isn't said at all
        local r = run
        local said = run.first and ("boats: stopped at %s (%s in)."):format(where, YR.BoatClock(e.t - run.first.t))
            or ("boats: arrived at %s - the round starts as it leaves."):format(where)
        C_Timer.After(20, function() if run == r and e.kind == "stop" then YR.Print(said) end end)
    end
    if Paint then Paint() end
end

local function Tick()
    if not run then return end
    local y, x, _, map = UnitPosition("player")
    x, y, map = Plain(x), Plain(y), Plain(map)
    if not (x and y) then return end
    local now = GetTime()
    local walking = (IsPlayerMoving and IsPlayerMoving()) or (IsFalling and IsFalling())
    if walking and not run.warned then
        run.warned = true
        YR.Print("boats: you moved - stand still on the spot you pressed the button on, or the times are off.")
    end
    if last and last.map == map then
        if walking then
            if moving then lastMove = now end           -- (what moved you can't be told apart while you walk)
        else
            local carried = math.sqrt((x - last.x) ^ 2 + (y - last.y) ^ 2) > 0.02
            if carried then
                lastMove = now
                if run.first and not run.far and Far(run.first, x, y, map) then run.far = true end
                if moving == nil then
                    -- Under way when the button was pressed (boarded as it came in): that is no departure. A dock has
                    -- two moments, arriving and leaving, and the round runs from leaving to leaving - so it starts
                    -- when it next leaves a dock (the owner's rule, 2026-10-15, after a round cut short that way).
                    moving = true
                    YR.Print("boats: it is under way - the round starts as it next leaves a dock.")
                elseif not moving then
                    -- it left between the two looks
                    moving = true
                    Event("go", (last.t + now) / 2, last.x, last.y, map)
                end
            elseif moving == nil then
                -- seen standing since the button: its next move is a departure
                run.rest = run.rest or now
                if now - run.rest > STILL then moving = false end
            elseif moving and now - lastMove > STILL then
                moving = false
                Event("stop", lastMove, x, y, map)
            end
        end
    elseif last then
        Event("zone", now, x, y, map)                   -- a loading screen on the way: another continent
        if run then
            moving, lastMove = true, now
            if run.first then run.far = true end
        end
    end
    last = { x = x, y = y, map = map, t = now }
end

-- the realm's second watched until it turns: then its clock is known to a frame
local sync
local function Sync()
    local was = GetServerTime and GetServerTime()
    if not was then return end
    sync = sync or CreateFrame("Frame")
    sync:SetScript("OnUpdate", function(self)
        local now = GetServerTime()
        if now ~= was then
            offset = now - GetTime()
            self:SetScript("OnUpdate", nil)
        end
    end)
end

-- A loading screen on the way (another continent) closes every window, the list too: it comes back after
-- it if it was open, and chat says the round goes on - the measuring itself never stopped.
local win, wantOpen
local function OnEvent(_, event)
    if event ~= "PLAYER_ENTERING_WORLD" or not run then return end
    YR.Print(("boats: through the loading screen, still measuring %s - stand still."):format(run.name))
    if wantOpen and win and not win:IsShown() then
        win:Show()
        if Paint then Paint() end
    end
end

YR.Part(function() return run ~= nil end, { "PLAYER_ENTERING_WORLD" }, OnEvent, { tick = Tick, every = STEP, start = Sync })

--- Measure a route's round trip from now (its key in ROUTES); nil stops the one being measured.
function YR.BoatsMeasure(key)
    if not key then Stop("measuring stopped, nothing written down.") return end
    for _, r in ipairs(ROUTES) do
        if r[1] == key then
            run = { key = key, name = r[2], events = {} }
            last, moving, lastMove = nil, nil, nil
            YR.ApplyParts()
            YR.Print(("boats: measuring %s. Stand still: it is timed from when it leaves the dock."):format(r[2]))
            if Paint then Paint() end
            return true
        end
    end
end
function YR.BoatsMeasuring() return run and run.key end

-- ---------------------------------------------------------------------------
-- The list: a button for every route, and what was measured of it so far
-- ---------------------------------------------------------------------------
local function Build()
    local S = YR.Style
    win = S.Window("HeadstartBoats", 600, 118 + #ROUTES * 30, "Boats and zeppelins")
    win.subtitle:SetText("measured for a timetable")
    local hint = S.Text(win, 12, S.C.muted)
    hint:SetPoint("TOPLEFT", 16, -58)
    hint:SetWidth(568)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetText("Stand on one while it lies at its dock, press its button, and stand still until it has been across, come back"
        .. " and left again.")
    win.rows = {}
    for i, r in ipairs(ROUTES) do
        local row = CreateFrame("Frame", nil, win)
        row:SetPoint("TOPLEFT", 16, -92 - (i - 1) * 30)
        row:SetSize(568, 28)
        if i % 2 == 0 then S.Fill(row, S.C.stripe) end
        row.name = S.Text(row, 13)
        row.name:SetPoint("LEFT", 8, 0)
        row.name:SetText(r[2])
        row.state = S.Text(row, 12, S.C.muted)
        row.state:SetPoint("LEFT", 270, 0)
        row.button = S.Button(row, "Measure", function()
            if run and run.key == r[1] then YR.BoatsMeasure(nil) else YR.BoatsMeasure(r[1]) end
        end, nil, 90)
        row.button:SetHeight(22)
        row.button:SetPoint("RIGHT", -4, 0)
        row.key = r[1]
        win.rows[i] = row
    end
    win.close:HookScript("OnClick", function() wantOpen = false end)
end

function Paint()
    if not (win and win:IsShown()) then return end
    local S = YR.Style
    local times = YippRouteDB.boatTimes or {}
    for _, row in ipairs(win.rows) do
        local list = times[row.key]
        local now = run and run.key == row.key
        local text
        if now then
            text = run.first and ("left " .. date("%H:%M:%S", math.floor(run.first.t)) .. ", on its way") or "waiting for it to leave"
        elseif list and #list > 0 then
            text = ("%s  (%d round%s)"):format(YR.BoatClock(list[#list].period), #list, #list == 1 and "" or "s")
        else
            text = "not measured"
        end
        row.state:SetText(text)
        row.state:SetTextColor(unpack(now and S.C.accent or (list and #list > 0) and S.C.green or S.C.muted))
        row.button.text:SetText(now and "Stop" or "Measure")
        row.button:SetEnabled(now or not run)
    end
end

-- ---------------------------------------------------------------------------
-- The timetable a round gives: when the boat arrives at and leaves each dock, as seconds into the round
-- from its first departure - and from that, when it next does so. (/headstart boats next says it, to be
-- held against the boats themselves: now, and after a server restart.)
-- ---------------------------------------------------------------------------
-- Which continent an end of a route is on (1 Kalimdor, 0 the Eastern Kingdoms): a dock the game gives no
-- name of its own (a zeppelin tower) is named by it.
local CONTINENT = { Orgrimmar = 1, Ratchet = 1, Auberdine = 1, Theramore = 1, ["Rut'theran Village"] = 1, Feathermoon = 1,
    ["Feralas coast"] = 1, Mulgore = 1, Tanaris = 1, Undercity = 0, ["Grom'gol"] = 0, ["Booty Bay"] = 0,
    ["Menethil Harbor"] = 0, Southshore = 0, ["Stormwind Harbor"] = 0, Dalaran = 0 }

local function Ends(name)
    local out = {}
    for part in (name .. " - "):gmatch("(.-) %- ") do out[#out + 1] = part end
    return out
end

--- The timetable of a measured round, or nil for one that is no round (under two minutes: a dock's creep
--- taken for a departure, before that was caught). { period, left, docks = { { name, arrive, leave } } }
function YR.BoatTimetable(r, routeName)
    if not (type(r) == "table" and tonumber(r.period) and r.period >= 120 and type(r.events) == "table") then return nil end
    local first
    for _, e in ipairs(r.events) do if e.kind == "go" then first = e break end end
    if not first then return nil end
    local docks, arrived = {}, nil
    for _, e in ipairs(r.events) do
        if e.kind == "stop" and e.t >= first.t then
            arrived = e
        elseif e.kind == "go" and e.t >= first.t then
            if e.t - first.t >= r.period - 1 then
                -- the round's last departure is its first again: the home dock's arrival is the stop before it
                if docks[1] and arrived then docks[1].arrive = (arrived.t - first.t) % r.period end
            else
                docks[#docks + 1] = { leave = e.t - first.t, arrive = arrived and (arrived.t - first.t) or nil,
                    name = e.place ~= "" and e.place or nil, map = e.map }
            end
            arrived = nil
        end
    end
    -- The docks named by the route's ends - "Menethil Harbor", not the bay its pier stands in - which are in the
    -- order the boat calls at them: the turn of that order (either way round) that fits the continents each
    -- dock is on, and the names the game gave the docks, best. The game's own name where none fits.
    local ends = Ends(routeName or "")
    local function Word(t) return (t:lower():gsub("'", "")) end
    local n = #docks
    if #ends == n and n > 0 then
        local best, bestScore
        for dir = 1, 2 do
            for k = 0, n - 1 do
                local score, names = 0, {}
                for i = 1, n do
                    local j = dir == 1 and ((i - 1 + k) % n) + 1 or ((k - (i - 1)) % n) + 1
                    local part, d = ends[j], docks[i]
                    local c = CONTINENT[part]
                    score = score + ((c == nil or c == d.map) and 1 or -10)
                    if d.name and Word(d.name):find(Word(part):match("^%S+") or "", 1, true) then score = score + 5 end
                    names[i] = part
                end
                if not bestScore or score > bestScore then best, bestScore = names, score end
            end
        end
        if bestScore and bestScore >= n then
            for i, d in ipairs(docks) do d.name = best[i] end
        end
    end
    for i, d in ipairs(docks) do d.name = d.name or ("dock " .. i) end
    return { period = r.period, left = first.t, docks = docks }
end

--- When something `offset` seconds into the round next happens, by the realm's clock, from `now`.
function YR.BoatNext(tt, offset, now)
    local base = tt.left + offset
    return base + math.ceil((now - base) / tt.period) * tt.period
end

--- The next arrivals and departures of every route measured on this account, as lines.
function YR.BoatsNext()
    local now, lines = Realm(GetTime()), {}
    for _, route in ipairs(ROUTES) do
        local list = (YippRouteDB.boatTimes or {})[route[1]]
        local tt
        for i = #(list or {}), 1, -1 do
            tt = YR.BoatTimetable(list[i], route[2])
            if tt then break end
        end
        if tt then
            local parts = {}
            for _, d in ipairs(tt.docks) do
                local leave = YR.BoatNext(tt, d.leave, now)
                local arrive = d.arrive and YR.BoatNext(tt, d.arrive, now)
                -- lying at the dock now: it arrived before it leaves again
                local docked = arrive and arrive > leave
                parts[#parts + 1] = ("%s %s %s"):format(d.name, docked and "in, leaves" or "leaves", date("%H:%M:%S", math.floor(leave)))
            end
            lines[#lines + 1] = ("%s (%s): %s"):format(route[2], YR.BoatClock(tt.period), table.concat(parts, " · "))
        end
    end
    return lines
end

--- /headstart boats: the list, open or shut; /headstart boats next: when each measured boat next leaves;
--- /headstart boats seen: what was last seen of each, and how far off the timetable was then.
function YR.BoatsCommand(arg)
    if arg == "next" then
        local lines = YR.BoatsNext()
        if #lines == 0 then YR.Print("boats: nothing measured on this account yet.") end
        for _, line in ipairs(lines) do YR.Print("boats: " .. line) end
        return
    end
    if arg == "seen" then
        local lines = YR.BoatSeenLines and YR.BoatSeenLines() or {}
        if #lines == 0 then YR.Print("boats: no boat seen yet, by you or anyone you heard from.") end
        for _, line in ipairs(lines) do YR.Print("boats: " .. line) end
        return
    end
    YR.BoatsToggle()
end

--- /headstart boats: the list, open or shut.
function YR.BoatsToggle()
    if not win then Build() end
    if win:IsShown() then win:Hide() wantOpen = false return end
    wantOpen = true
    win:Show()
    Paint()
end
