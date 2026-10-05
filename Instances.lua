-- Instance tracker: how many instances you've gone into this hour and today, against the limit, so you
-- know before the game tells you "You have entered too many instances recently". Every run is logged:
-- where, when, how long, the XP and the money it brought.
--   What counts: going into a dungeon or raid that isn't the one you were just in. On Forever the
--   game keeps mob IDs secret inside instances, so the copy can't be read off them (Nova Instance
--   Tracker does that elsewhere): going back into the same dungeon within the minutes you set, with the
--   same group leader and no reset seen, is the same instance; anything else is a new one. A reset
--   ("Deadmines has been reset.") makes the next entry a new one at once.
--   The limit: Forever's isn't known, so it's a setting (5 an hour and 30 a day, as on Classic). The
--   game saying "too many instances" is noted with the count at that moment, so you can see where it is.
--   Account options (YippRouteDB, Settings, QoL, Group): instanceTrack (on unless turned off),
--   instanceWarn (on unless turned off), instanceAccount (off: each character on its own), instanceHour
--   (5), instanceDay (30), instanceSame (minutes, 30). The log: YippRouteDB.instanceRuns (every
--   character's, a week of them), YippRouteDB.instanceLocks.
local ADDON, YR = ...

local HOUR, DAY, WEEK = 3600, 86400, 7 * 86400
local cur                  -- the run you're in now
local xpLast, xpMaxLast, levelLast

local function Now() return GetServerTime and GetServerTime() or time() end

local function Runs()
    YippRouteDB.instanceRuns = YippRouteDB.instanceRuns or {}
    return YippRouteDB.instanceRuns
end

local function Limit(key, default) return tonumber(YippRouteDB[key]) or default end
function YR.InstanceLimits() return Limit("instanceHour", 5), Limit("instanceDay", 30) end

local function Mine(r) return YippRouteDB.instanceAccount == true or r.char == YR.CharKey() end

--- How many instances count now: this hour, today, and when the next slot frees (seconds, or nil
--- when you're under the hourly limit) - the hour's oldest entry turning an hour old.
function YR.InstanceCounts(now)
    now = now or Now()
    local hour, day, inHour = 0, 0, {}
    for _, r in ipairs(Runs()) do
        if r.counted and Mine(r) then
            if now - r.entered < HOUR then hour = hour + 1 inHour[#inHour + 1] = r.entered end
            if now - r.entered < DAY then day = day + 1 end
        end
    end
    local perHour = YR.InstanceLimits()
    local wait
    if hour >= perHour then
        table.sort(inHour)
        wait = inHour[hour - perHour + 1] + HOUR - now
    end
    return hour, day, wait
end

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
        if UnitExists(u) and UnitIsGroupLeader(u) then
            local ok, name = pcall(function() return UnitName(u) .. "" end)
            if ok then return name end
        end
    end
    return UnitIsGroupLeader("player") and YR.CharKey() or "?"
end

local function Warn(msg)
    YR.Print(msg)
    if YR.Option("instanceWarn") and RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        RaidNotice_AddMessage(RaidWarningFrame, "Headstart: " .. msg, ChatTypeInfo["RAID_WARNING"])
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
    else
        YR.Print(text)
    end
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

local function Leave()
    if not cur then return end
    XPTick()
    cur.left = Now()
    cur.money = (cur.money or 0) + (GetMoney() - (cur.money0 or GetMoney()))
    cur.money0 = nil
    cur = nil
end

local function Prune()
    local runs, now = Runs(), Now()
    for i = #runs, 1, -1 do
        if now - (runs[i].entered or 0) > WEEK then table.remove(runs, i) end
    end
end

local function Check()
    if not YR.Option("instanceTrack") then return end
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
        -- or never left at all: a reload or a login inside it carries on with the same run
        local stillIn = last and not last.left and now - last.entered < 4 * HOUR
        local same = last and (stillIn or (last.left and now - last.left < Limit("instanceSame", 30) * 60
            and last.leader == leader and not ((resets[map] or 0) >= last.left)))
        if same then
            cur = last
            cur.left, cur.again = nil, (cur.again or 0) + 1
            cur.money0 = GetMoney()
            if not stillIn then
                YR.Print(("back in %s: the same instance, it doesn't count again."):format(name or "the instance"))
            end
        else
            cur = { char = YR.CharKey(), name = name, map = map, difficulty = difficulty, entered = now,
                leader = leader, level = UnitLevel("player"), xp = 0, money = 0, money0 = GetMoney(), counted = true }
            runs[#runs + 1] = cur
            Prune()
            Announce()
        end
        xpLast, xpMaxLast, levelLast = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    else
        Leave()
    end
    if YR.RefreshWindow then YR:RefreshWindow() end
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

local function OnMessage(msg)
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then return end
    local name = RESET and msg:match(RESET)
    if name then
        YippRouteDB.instanceResets = YippRouteDB.instanceResets or {}
        for _, r in ipairs(Runs()) do
            if r.name == name then YippRouteDB.instanceResets[r.map] = Now() end
        end
        return
    end
    if TOO_MANY and msg == TOO_MANY then
        local hour, day = YR.InstanceCounts()
        YippRouteDB.instanceLocks = YippRouteDB.instanceLocks or {}
        table.insert(YippRouteDB.instanceLocks, { at = Now(), hour = hour, day = day, char = YR.CharKey() })
        local _, _, wait = YR.InstanceCounts()
        Warn(("the game says too many instances - at %d this hour and %d today by Headstart's count%s."):format(hour, day,
            wait and (", the next slot in " .. Clock(wait)) or ""))
    end
end
YR.InstanceMessage = OnMessage

function YR.StartInstances()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_XP_UPDATE", "CHAT_MSG_SYSTEM",
        "UI_ERROR_MESSAGE" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event, a, b)
        if event == "PLAYER_XP_UPDATE" then XPTick()
        elseif event == "CHAT_MSG_SYSTEM" then OnMessage(a)
        elseif event == "UI_ERROR_MESSAGE" then OnMessage(b)
        else C_Timer.After(0.5, Check) end
    end)
end
