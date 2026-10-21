-- Instance tracker: how many instances you've gone into this hour and today, against the limit, so you
-- know before the game tells you "You have entered too many instances recently". Every run is logged:
-- where, when, how long, the XP and the money it brought.
--   What counts: going into a copy of a dungeon or raid you weren't just in. Which copy you are in is
--   in the ID of everything that lives there (a mob's, a chest's: "Creature-0-server-map-COPY-npc-spawn"),
--   which is how Nova Instance Tracker tells too. So while you're inside, the first such ID the game
--   lets us read - your target's, what the mouse is over, a nameplate's, what you loot - settles it:
--   the same copy as a run in the log is that run carried on (out and in again without a reset doesn't
--   count twice, however long you were out), another copy is a new instance (a reset nobody told us of).
--   The game keeps those IDs secret in a fight on Forever, and perhaps always in some places, so until
--   one is read - and where none ever is - it is told the old way: back into the same dungeon within
--   the minutes you set, with the same group leader and no reset seen, is the same instance; anything
--   else is a new one. A reset ("Deadmines has been reset.") makes the next entry a new one at once.
--   /headstart instances id says what could be read where you stand.
--   The limit: Forever's isn't known, so it's a setting (5 an hour and 30 a day, as on Classic). The
--   game saying "too many instances" is noted with the count at that moment, so you can see where it is.
--   Account options (YippRouteDB, Settings, QoL, Instances): instanceTrack (off until turned on, since
--   2026-10-14; an account from before keeps it as it was),
--   instanceWarn (on unless turned off), instanceAccount (off: each character on its own), instanceHour
--   (5), instanceDay (30). The log: YippRouteDB.instanceRuns (every
--   character's, a week of them), YippRouteDB.instanceLocks.
--   On screen: a small icon with the count on it (hover for the lot, click for the Instances page) or
--   a small log with the count and your latest runs; shown while you have an instance this hour or are
--   in one, or always. instanceHud ("icon", "log" or "off"), instanceHudAlways,
--   instanceHudPos. Shift-drag moves it.
local ADDON, YR = ...

local HOUR, DAY, WEEK = 3600, 86400, 7 * 86400
local cur                  -- the run you're in now
local xpLast, xpMaxLast, levelLast
local frame                -- the frame the tracker listens on, once it has been on (YR.Part)

-- XP only matters while you're inside: listened for from going in until coming out.
local function WatchXP(on)
    if not frame then return end
    if on then frame:RegisterEvent("PLAYER_XP_UPDATE") else frame:UnregisterEvent("PLAYER_XP_UPDATE") end
end

local function Now() return GetServerTime and GetServerTime() or time() end

-- Logging out matters only inside one (the run stays open): listened for from going in until coming out.
local function WatchOut(on)
    if not frame then return end
    if on then frame:RegisterEvent("PLAYER_LOGOUT") else frame:UnregisterEvent("PLAYER_LOGOUT") end
end

local function Runs()
    YippRouteDB.instanceRuns = YippRouteDB.instanceRuns or {}
    return YippRouteDB.instanceRuns
end

local function Limit(key, default) return tonumber(YippRouteDB[key]) or default end
local SAME_MINUTES = 30         -- (entering the same dungeon again within this, with the same leader: the same instance)
function YR.InstanceLimits() return Limit("instanceHour", 5), Limit("instanceDay", 30) end

local function Mine(r) return YippRouteDB.instanceAccount == true or r.char == YR.CharKey() end

-- The counts are asked for every second while the icon shows, and the log holds a week of runs. So
-- they're worked out once and kept until something that changes them: a run added or removed, whose
-- runs count (this character's or the account's), the hourly limit - or the clock reaching the
-- moment a counted run turns an hour or a day old (known when they're worked out).
local kept = {}
local inHour = {}

--- How many instances count now: this hour, today, and when the next slot frees (seconds, or nil
--- when you're under the hourly limit) - the hour's oldest entry turning an hour old.
function YR.InstanceCounts(now)
    now = now or Now()
    local runs = Runs()
    local perHour = YR.InstanceLimits()
    local who = YippRouteDB.instanceAccount == true and "*" or YR.CharKey()
    if kept.runs == runs and kept.n == #runs and kept.who == who and kept.perHour == perHour
        and now >= kept.at and now < kept.till then
        return kept.hour, kept.day, kept.waitTill and (kept.waitTill - now) or nil
    end
    local hour, day, till = 0, 0, math.huge
    for i = #inHour, 1, -1 do inHour[i] = nil end
    for _, r in ipairs(runs) do
        if r.counted and Mine(r) then
            local age = now - r.entered
            if age < HOUR then
                hour = hour + 1
                inHour[#inHour + 1] = r.entered
                till = math.min(till, r.entered + HOUR)
            end
            if age < DAY then
                day = day + 1
                till = math.min(till, r.entered + DAY)
            end
        end
    end
    local waitTill
    if hour >= perHour then
        table.sort(inHour)
        waitTill = inHour[hour - perHour + 1] + HOUR
    end
    kept.runs, kept.n, kept.who, kept.perHour, kept.at, kept.till = runs, #runs, who, perHour, now, till
    kept.hour, kept.day, kept.waitTill = hour, day, waitTill
    return hour, day, waitTill and (waitTill - now) or nil
end

-- A run taken out of the log without its length changing (pruned as one is added): count again
local function Recount() kept.runs = nil end

local function Clock(s)
    s = math.max(0, math.floor(s))
    if s >= HOUR then return ("%d:%02d:%02d"):format(s / HOUR, s % HOUR / 60, s % 60) end
    return ("%d:%02d"):format(s / 60, s % 60)
end
YR.InstanceClock = Clock

local function Leader()
    if not IsInGroup() then return YR.CharKey() end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and YR.Open(UnitIsGroupLeader(u)) then
            -- a name the game keeps secret can't be compared later: it's as good as no name
            local name = UnitName(u)
            if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then return name end
        end
    end
    return YR.Open(UnitIsGroupLeader("player")) and YR.CharKey() or "?"
end

local function Warn(msg)
    YR.Print(msg)
    -- On the game's own line for messages, mid-screen. (It went into Blizzard's raid warning frame
    -- through RaidNotice_AddMessage: code of Blizzard's run from here, which leaves what it writes on
    -- that frame ours - and a real raid warning, whose text the game keeps from addons in an instance,
    -- then failed in that same code with the blame on Headstart.)
    if YR.Option("instanceWarn") and UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage("Headstart: " .. msg, 1, 0.3, 0.2)
    end
end

--- Say where the count stands as you go in.
local function Announce()
    local hour, day, wait = YR.InstanceCounts()
    local perHour, perDay = YR.InstanceLimits()
    local text = ("instance %d of %d this hour, %d of %d today."):format(hour, perHour, day, perDay)
    if hour >= perHour then
        Warn(text .. (" That's the limit: the next one in %s."):format(Clock(wait or 0)))
    elseif hour == perHour - 1 then
        Warn(text .. " One more and you're at the limit for the hour.")
    end
    -- (an entry under the limits isn't said: the counter on screen has it - the owner, 2026-10-21, "nobody reads
    -- our chat lines")
end

-- XP while inside: added as it comes, across level-ups.
local function XPTick()
    if not cur then return end
    local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if xpLast then
        local gained = level > levelLast and (xpMaxLast - xpLast + xp) or (xp - xpLast)
        if gained > 0 then cur.xp = (cur.xp or 0) + gained end
    end
    xpLast, xpMaxLast, levelLast = xp, max, level
end

-- ---------------------------------------------------------------------------
-- The copy's ID (see the top of the file)
-- ---------------------------------------------------------------------------
local ID_EVENTS = { "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "LOOT_OPENED" }
local entry                 -- this time inside, until the copy's ID is known: { reused, at, left, again }

-- Listened for only from going in until the ID is read (or you leave).
local function WatchID(on)
    if not frame then return end
    for _, e in ipairs(ID_EVENTS) do
        if on then frame:RegisterEvent(e) else frame:UnregisterEvent(e) end
    end
end

--- The copy a GUID is of, when it is one of this map's creatures or objects and the game lets it be
--- read: "Creature-0-4379-36-1234-639-00001A2B3C" on map 36 is copy 1234. nil otherwise.
function YR.InstanceCopyID(guid, map)
    -- (whether it is one the game keeps from addons is asked first: nothing else may be asked of such a value)
    if (issecretvalue and issecretvalue(guid)) or type(guid) ~= "string" then return nil end
    local kind, m, copy = guid:match("^(%a+)%-%d+%-%d+%-(%d+)%-(%d+)%-")
    if kind ~= "Creature" and kind ~= "Vehicle" and kind ~= "GameObject" then return nil end
    if tonumber(m) ~= map then return nil end           -- a pet called out elsewhere carries that place's
    return tonumber(copy)
end

-- The ID of the copy you're in has been read: the run you're in is settled by it.
local function GotID(id)
    if not (cur and entry and id) then return end
    local e = entry
    entry = nil
    WatchID(false)
    local runs = YippRouteDB.instanceRuns
    if e.reused then
        if cur.id == nil or cur.id == id then cur.id = id return end
        -- told as the same instance, and it is another copy: the old run ended when you left it, and
        -- this is a new one, counted from when you came in
        local old, name = cur, cur.name
        old.left, old.again, old.money0 = e.left, e.again, nil
        cur = { char = old.char, name = name, map = old.map, difficulty = old.difficulty, entered = e.at, id = id,
            leader = old.leader, level = UnitLevel("player"), xp = 0, money = 0, money0 = GetMoney(), counted = true }
        runs[#runs + 1] = cur
        Recount()
        Announce()
        return
    end
    -- told as a new instance: a run in the log with this very ID is the one you're back in
    for i = #runs, 1, -1 do
        local r = runs[i]
        if r ~= cur and r.id == id and r.map == cur.map and r.char == cur.char then
            for k = #runs, 1, -1 do if runs[k] == cur then table.remove(runs, k) break end end
            r.xp, r.money = (r.xp or 0) + (cur.xp or 0), (r.money or 0) + (cur.money or 0)
            r.left, r.again, r.money0 = nil, (r.again or 0) + 1, cur.money0
            cur = r
            Recount()
            return
        end
    end
    cur.id = id
end

local function SeeGUID(guid)
    if not (cur and entry) then return end
    GotID(YR.InstanceCopyID(guid, cur.map))
end
local function SeeUnit(unit)
    if not (cur and entry) then return end
    local ok, guid = pcall(UnitGUID, unit)
    if ok then SeeGUID(guid) end
end

--- /headstart instances id: what the game lets be read where you stand.
function YR.InstanceIDDebug()
    local inside, kind = IsInInstance()
    local map = select(8, GetInstanceInfo())
    YR.Print(("instance ID: %s, map %s; this run's copy: %s."):format(inside and ("inside (" .. tostring(kind) .. ")") or "not in an instance",
        tostring(map), cur and cur.id and tostring(cur.id) or "not read yet"))
    for _, unit in ipairs({ "target", "mouseover" }) do
        local ok, guid = pcall(UnitGUID, unit)
        local what
        if not ok then what = "the game refused"
        elseif issecretvalue and issecretvalue(guid) then what = "kept secret by the game"
        elseif guid == nil then what = "nothing there"
        else what = guid .. " -> copy " .. tostring(YR.InstanceCopyID(guid, map)) end
        YR.Print(("  %s: %s"):format(unit, what))
    end
end

local function Leave()
    entry = nil
    WatchID(false)
    WatchOut(false)
    if not cur then return end
    XPTick()
    cur.left = Now()
    cur.money = (cur.money or 0) + (GetMoney() - (cur.money0 or GetMoney()))
    cur.money0, cur.seen = nil, nil
    cur = nil
    WatchXP(false)
end

-- Logging out or reloading inside one. The run isn't over (a login inside carries it on), but when
-- you were last in it is written down, and the money so far is counted in: what comes after the
-- login is counted from the purse as it is then. (Neither was done: the money of a run before a
-- reload was dropped, and a run you logged out of and never came back into never ended.)
local function Seen()
    if not cur then return end
    XPTick()
    local money = GetMoney()
    cur.money = (cur.money or 0) + (money - (cur.money0 or money))
    cur.money0, cur.seen = money, Now()
end

-- Outside, with a run of this character's still open: you logged out inside it and are not in it
-- now (it was reset, or the game put you at its door). It ended when you were last seen in it.
-- Once a session is enough: a run you walk out of is closed as you do.
local swept
local function CloseOpen()
    if swept then return end
    swept = true
    local me, closed = YR.CharKey(), false
    for _, r in ipairs(Runs()) do
        if r.char == me and not r.left then
            r.left, r.seen, r.money0 = r.seen or r.entered, nil, nil
            closed = true
        end
    end
    if closed then Recount() end
end

local function Prune()
    local runs, now = Runs(), Now()
    for i = #runs, 1, -1 do
        if now - (runs[i].entered or 0) > WEEK then table.remove(runs, i) end
    end
    local locks = YippRouteDB.instanceLocks
    if locks then
        for i = #locks, 1, -1 do
            if now - (locks[i].at or 0) > WEEK then table.remove(locks, i) end
        end
    end
    Recount()
end

local function Check()
    if not YR.Option("instanceTrack") then
        if YR.InstanceHudPaint then YR.InstanceHudPaint() end
        return
    end
    local inside, kind = IsInInstance()
    if inside and (kind == "party" or kind == "raid") then
        local name, _, difficulty, _, _, _, _, map = GetInstanceInfo()
        if cur and cur.map == map then return end                 -- moving about inside
        Leave()
        local now, leader = Now(), Leader()
        local runs = Runs()
        -- the same copy: the last run here, left a little while ago, same leader, no reset since
        local last
        for i = #runs, 1, -1 do
            local r = runs[i]
            if r.map == map and r.char == YR.CharKey() then last = r break end
        end
        local resets = YippRouteDB.instanceResets or {}
        -- or never left at all: a reload or a login inside it carries on with the same run (by when
        -- you were last seen in it, not when you first went in: a reload five hours into a long run
        -- was told as a new instance)
        local stillIn = last and not last.left and now - (last.seen or last.entered) < 4 * HOUR
        local same = last and (stillIn or (last.left and now - last.left < SAME_MINUTES * 60
            and last.leader == leader and not ((resets[map] or 0) >= last.left)))
        if same then
            entry = { reused = true, at = now, left = last.left, again = last.again }
            cur = last
            cur.left = nil
            cur.money0 = GetMoney()
            -- (a reload or a login inside it is not going back in: only having left and come back is)
            if not stillIn then cur.again = (cur.again or 0) + 1 end
        else
            cur = { char = YR.CharKey(), name = name, map = map, difficulty = difficulty, entered = now,
                leader = leader, level = UnitLevel("player"), xp = 0, money = 0, money0 = GetMoney(), counted = true }
            runs[#runs + 1] = cur
            Prune()
            Announce()
            entry = { reused = false, at = now }
        end
        -- which copy this is: off the first thing whose ID can be read (a target you came in with, now)
        WatchID(true)
        SeeUnit("target")
        xpLast, xpMaxLast, levelLast = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
        WatchXP(true)
        WatchOut(true)
    else
        Leave()
        CloseOpen()
    end
    if YR.RefreshWindow then YR:RefreshWindow() end
    if YR.InstanceHudPaint then YR.InstanceHudPaint() end
end
YR.InstanceCheck = Check

--- Reset by hand (the game's message was missed, or a reset from someone else): the next entry here is new.
function YR.InstanceResetSeen(map)
    YippRouteDB.instanceResets = YippRouteDB.instanceResets or {}
    local now = Now()
    if map then YippRouteDB.instanceResets[map] = now
    else
        for _, r in ipairs(Runs()) do YippRouteDB.instanceResets[r.map] = now end
    end
end

function YR.InstanceForget()
    wipe(Runs())
    YippRouteDB.instanceLocks = nil
    Recount()
end

-- "Deadmines has been reset." -> that instance (by its name in the log), and "You have entered too
-- many instances recently." -> noted with the count at that moment.
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local escaped = fmt:gsub("([%.%-%+%*%?%^%$%(%)%[%]])", "%%%1")       -- the dot and friends, literally
    return "^" .. escaped:gsub("%%s", "(.+)") .. "$"
end
local RESET = Pattern(INSTANCE_RESET_SUCCESS)
local TOO_MANY = TRANSFER_ABORT_TOO_MANY_INSTANCES

-- Every system message comes through here, and of the red error lines only the one sentence (the
-- listener lets no other through): nothing is done with tracking off.
local function OnMessage(msg, errorLine)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
    if not YR.Option("instanceTrack") then return end
    local name = not errorLine and RESET and msg:match(RESET)
    if name then
        YippRouteDB.instanceResets = YippRouteDB.instanceResets or {}
        for _, r in ipairs(Runs()) do
            if r.name == name then YippRouteDB.instanceResets[r.map] = Now() end
        end
        return
    end
    if TOO_MANY and msg == TOO_MANY then
        local hour, day = YR.InstanceCounts()
        local locks = YippRouteDB.instanceLocks or {}
        YippRouteDB.instanceLocks = locks
        -- the game repeats it for as long as you stand in the doorway: noted once
        local last = locks[#locks]
        if last and Now() - (last.at or 0) < 10 then return end
        table.insert(locks, { at = Now(), hour = hour, day = day, char = YR.CharKey() })
        local _, _, wait = YR.InstanceCounts()
        Warn(("the game says too many instances - at %d this hour and %d today by Headstart's count%s."):format(hour, day,
            wait and (", the next slot in " .. Clock(wait)) or ""))
    end
end
YR.InstanceMessage = OnMessage

-- ---------------------------------------------------------------------------
-- On screen: a small icon with the count, or a small log
-- ---------------------------------------------------------------------------
local hud
local ICON = 134237

--- "icon" (the default), "log" or "off".
function YR.InstanceHudMode()
    local m = YippRouteDB.instanceHud
    return (m == "off" or m == "log") and m or "icon"
end

local function Short(n)
    n = n or 0
    if n >= 1000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end

--- What the icon and the small log say: the counts against the limits, how near the limit that is
--- ("ok", "near", "full"), the wait for a slot, and the latest runs, newest first, as lines.
function YR.InstanceSummary(rows, now)
    now = now or Now()
    local hour, day, wait = YR.InstanceCounts(now)
    local perHour, perDay = YR.InstanceLimits()
    local s = { hour = hour, day = day, perHour = perHour, perDay = perDay, wait = wait, runs = {},
        state = (hour >= perHour or day >= perDay) and "full" or hour == perHour - 1 and "near" or "ok" }
    if rows == 0 then return s end
    local runs = Runs()
    for i = #runs, 1, -1 do
        local r = runs[i]
        if #s.runs >= (rows or 3) then break end
        if Mine(r) then
            local inside = not r.left and rawequal(r, cur)
            local line = ("%s  %s"):format(r.name or "?", Clock((r.left or now) - r.entered))
            if (r.xp or 0) > 0 then line = line .. ("  +%s XP"):format(Short(r.xp)) end
            s.runs[#s.runs + 1] = { text = line, inside = inside, ago = now - r.entered }
        end
    end
    return s
end

local COLOUR = { ok = { 0.5, 1, 0.5 }, near = { 1, 0.82, 0 }, full = { 1, 0.3, 0.3 } }

local function HudTooltip(self)
    local s = YR.InstanceSummary(8)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine("Instances")
    local c = COLOUR[s.state]
    GameTooltip:AddDoubleLine("This hour", ("%d of %d"):format(s.hour, s.perHour), 0.8, 0.8, 0.8, c[1], c[2], c[3])
    GameTooltip:AddDoubleLine("Today", ("%d of %d"):format(s.day, s.perDay), 0.8, 0.8, 0.8, 1, 1, 1)
    if s.wait then GameTooltip:AddDoubleLine("Next free slot in", Clock(s.wait), 0.8, 0.8, 0.8, 1, 0.3, 0.3) end
    if #s.runs > 0 then GameTooltip:AddLine(" ") end
    for _, r in ipairs(s.runs) do
        GameTooltip:AddDoubleLine(r.text, r.inside and "in it now" or (Clock(r.ago) .. " ago"), 1, 1, 1, 0.6, 0.6, 0.6)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: the Instances page. Shift-drag: move it", 0.4, 0.8, 1)
    GameTooltip:Show()
end

-- A text put on a font string only when it's a different one: this runs every second.
local function Put(fs, text)
    if rawget(fs, "said") == text then return end
    fs.said = text
    fs:SetText(text)
end

local function State(hour, day, perHour, perDay)
    return (hour >= perHour or day >= perDay) and "full" or hour == perHour - 1 and "near" or "ok"
end

local function Paint()
    if not hud then return end
    local mode = YR.InstanceHudMode()
    if mode == "off" or not YR.Option("instanceTrack") then hud:SetShown(false) return end
    local hour, day, wait = YR.InstanceCounts()
    local show = YippRouteDB.instanceHudAlways == true or hour > 0 or cur ~= nil
    hud:SetShown(show)
    if not show then return end
    local perHour, perDay = YR.InstanceLimits()
    local c = COLOUR[State(hour, day, perHour, perDay)]
    local count = ("%d/%d"):format(hour, perHour)
    local n = 0
    if mode == "icon" then
        Put(hud.count, count)
        hud.count:SetTextColor(c[1], c[2], c[3])
        Put(hud.wait, wait and Clock(wait) or "")
    else
        Put(hud.head, ("Instances  %s this hour  %d/%d today%s"):format(count, day, perDay,
            wait and ("  next in " .. Clock(wait)) or ""))
        hud.head:SetTextColor(c[1], c[2], c[3])
        local s = YR.InstanceSummary(3)
        for i, r in ipairs(s.runs) do
            local row = hud.rows[i]
            if row then
                n = n + 1
                Put(row, r.text .. (r.inside and "  (now)" or ""))
                local grey = r.inside and 1 or 0.75
                row:SetTextColor(grey, grey, grey)
            end
        end
    end
    -- what's shown and how big: only when the kind of display or the number of rows changes
    local laid = mode .. n .. (wait and "w" or "")
    if rawget(hud, "laid") ~= laid then
        hud.laid = laid
        hud.icon:SetShown(mode == "icon")
        hud.count:SetShown(mode == "icon")
        hud.wait:SetShown(mode == "icon" and wait ~= nil)
        hud.bg:SetShown(mode == "log")
        hud.head:SetShown(mode == "log")
        for i, row in ipairs(hud.rows) do row:SetShown(mode == "log" and i <= n) end
        if mode == "icon" then hud:SetSize(34, 34) else hud:SetSize(270, 20 + 14 * n) end
    end
    -- what on it moves with the clock: the wait for a slot, and the time in the run you're in
    hud.live = wait ~= nil or cur ~= nil
    if GameTooltip:IsOwned(hud) then HudTooltip(hud) end
end

-- The time in the run and the wait for a slot tick on without events, and so does the tooltip while
-- it's up ("12:40 ago"): a clock runs, once a second, only while one of those is on screen. With none
-- of them (the count alone, or the log of runs you've left) a second changes nothing: it's drawn
-- again once, when a counted run turns an hour or a day old.
local ticker, hovering, dueAt = nil, false, nil
local function Tick() YR.InstanceHudPaint() end
local function Due()
    if not dueAt or Now() < dueAt then return end          -- an older appointment: there's a later one
    dueAt = nil
    if hud and hud:IsShown() then YR.InstanceHudPaint() end
end
local function Pace()
    local shown = hud ~= nil and hud:IsShown()
    if shown and (rawget(hud, "live") == true or hovering) then
        if not ticker then ticker = C_Timer.NewTicker(1, Tick) end
        return
    end
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    local till = kept.till
    if shown and till and till < math.huge and dueAt ~= till then
        dueAt = till
        C_Timer.After(math.max(1, till - Now() + 1), Due)
    end
end

local function HudEnter(self)
    hovering = true
    HudTooltip(self)
    Pace()
end
local function HudLeave()
    hovering = false
    GameTooltip:Hide()
    Pace()
end

local function HudBuild()
    if hud then return end
    local S = YR.Style
    hud = CreateFrame("Button", "HeadstartInstanceHud", UIParent)
    hud:SetFrameStrata("LOW")
    hud:SetClampedToScreen(true)
    hud:SetMovable(true)
    hud:RegisterForDrag("LeftButton")
    hud:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        YippRouteDB.instanceHudPos = { math.floor(self:GetLeft() + 0.5), math.floor(self:GetTop() - UIParent:GetTop() + 0.5) }
    end)
    hud:SetScript("OnClick", function() if YR.LoadWindow and YR.LoadWindow() and YR.InstanceLogToggle then YR.InstanceLogToggle() end end)
    hud:SetScript("OnEnter", HudEnter)
    hud:SetScript("OnLeave", HudLeave)
    hud.icon = hud:CreateTexture(nil, "ARTWORK")
    hud.icon:SetAllPoints()
    hud.icon:SetTexture(ICON)
    hud.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    hud.count = hud:CreateFontString(nil, "OVERLAY")
    hud.count:SetFont(S.FONT, 13, "OUTLINE")
    hud.count:SetPoint("BOTTOMRIGHT", -1, 2)
    hud.wait = hud:CreateFontString(nil, "OVERLAY")
    hud.wait:SetFont(S.FONT, 11, "OUTLINE")
    hud.wait:SetPoint("TOP", hud, "BOTTOM", 0, -2)
    hud.wait:SetTextColor(1, 0.3, 0.3)
    hud.bg = hud:CreateTexture(nil, "BACKGROUND")
    hud.bg:SetAllPoints()
    hud.bg:SetColorTexture(0, 0, 0, 0.45)
    hud.head = hud:CreateFontString(nil, "OVERLAY")
    hud.head:SetFont(S.FONT, 11, "OUTLINE")
    hud.head:SetPoint("TOPLEFT", 5, -4)
    hud.rows = {}
    for i = 1, 8 do
        local row = hud:CreateFontString(nil, "OVERLAY")
        row:SetFont(S.FONT, 11, "OUTLINE")
        row:SetPoint("TOPLEFT", 5, -4 - 14 * i)
        hud.rows[i] = row
    end
    local pos = YippRouteDB.instanceHudPos
    if pos then hud:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos[1], pos[2])
    else hud:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -220) end
end

-- Is there anything for it to show? The frame isn't made before there is.
local function HudWanted()
    if YR.InstanceHudMode() == "off" or not YR.Option("instanceTrack") then return false end
    if YippRouteDB.instanceHudAlways == true or cur ~= nil then return true end
    return (YR.InstanceCounts()) > 0
end

local function HudPaint()
    if not hud and HudWanted() then HudBuild() end
    Paint()
    Pace()
end
YR.InstanceHudPaint = HudPaint

--- After a setting changed.
function YR.InstanceHudApply()
    HudPaint()
end

function YR.InstanceHudResetPosition()
    YippRouteDB.instanceHudPos = nil
    if hud then
        hud:ClearAllPoints()
        hud:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -220)
    end
end

-- Going somewhere: looked at half a second on, once (a loading screen and a new zone come together).
local soon = false
local function Look()
    soon = false
    Check()                                 -- Check paints the icon too
end
local function Soon()
    if soon then return end
    soon = true
    C_Timer.After(0.5, Look)
end

-- Red error lines pour in during a fight ("Not enough rage", "Out of range"...), and one of them is
-- the game refusing an instance. No narrower event says that here, so they are listened for - but
-- each costs one comparison with that sentence and nothing else, and where the client hasn't got
-- the sentence they aren't listened for at all.
local function OnEvent(_, event, a, b)
    if event == "UI_ERROR_MESSAGE" then
        if not (issecretvalue and issecretvalue(b)) and b == TOO_MANY then OnMessage(b, true) end
    elseif event == "PLAYER_XP_UPDATE" then XPTick()
    elseif event == "PLAYER_LOGOUT" then Seen()
    elseif event == "PLAYER_TARGET_CHANGED" then SeeUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then SeeUnit("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then SeeUnit(a)
    elseif event == "LOOT_OPENED" then
        if GetLootSourceInfo then
            local ok, guid = pcall(GetLootSourceInfo, 1)
            if ok then SeeGUID(guid) end
        end
    elseif event == "CHAT_MSG_SYSTEM" then OnMessage(a)
    else Soon()
    end
end

local EVENTS = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "CHAT_MSG_SYSTEM" }
if type(TOO_MANY) == "string" then EVENTS[#EVENTS + 1] = "UI_ERROR_MESSAGE" end

local function Wanted() return YR.Option("instanceTrack") end
-- Coming on: where you are is looked at (turned on while inside one, or the login - entering the
-- world looks again). Going off inside one ends the run there, as walking out would.
local function Begin(p)
    frame = p.frame
    Soon()
    HudPaint()
end
local function End()
    Leave()
    HudPaint()
end

-- Free while off (YR.Part, Core.lua): nothing is listened for and no icon is made with the tracker off.
local part
function YR.StartInstances()
    if part then return end
    part = YR.Part(Wanted, EVENTS, OnEvent, { start = Begin, stop = End, again = HudPaint })
end
