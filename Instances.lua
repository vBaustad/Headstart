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
--   Account options (YippRouteDB, Settings, QoL, Instances): instanceTrack (on unless turned off),
--   instanceWarn (on unless turned off), instanceAccount (off: each character on its own), instanceHour
--   (5), instanceDay (30), instanceSame (minutes, 30). The log: YippRouteDB.instanceRuns (every
--   character's, a week of them), YippRouteDB.instanceLocks.
--   On screen: a small icon with the count on it (hover for the lot, click for the Instances page) or
--   a small log with the count and your latest runs; shown while you have an instance this hour or are
--   in one, or always. instanceHud ("icon", "log" or "off"), instanceHudAlways, instanceHudRows (3),
--   instanceHudPos. Shift-drag moves it.
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
        if UnitExists(u) and UnitIsGroupLeader(u) then
            -- a name the game keeps secret can't be compared later: it's as good as no name
            local name = UnitName(u)
            if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then return name end
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

-- Every system message and every red error line comes through here (errors pour in during a fight):
-- nothing is done with tracking off, and an error line is only ever compared with the one sentence.
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

local function HudPaint()
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
        local s = YR.InstanceSummary(tonumber(YippRouteDB.instanceHudRows) or 3)
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
    if GameTooltip:IsOwned(hud) then HudTooltip(hud) end
end
YR.InstanceHudPaint = HudPaint

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
    hud:SetScript("OnClick", function() if YR.ToggleWindow then YR:ToggleWindow("instances") end end)
    hud:SetScript("OnEnter", HudTooltip)
    hud:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

--- After a setting changed.
function YR.InstanceHudApply()
    HudBuild()
    HudPaint()
end

function YR.InstanceHudResetPosition()
    YippRouteDB.instanceHudPos = nil
    if hud then
        hud:ClearAllPoints()
        hud:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -220)
    end
end

function YR.StartInstances()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_XP_UPDATE", "CHAT_MSG_SYSTEM",
        "UI_ERROR_MESSAGE" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event, a, b)
        if event == "PLAYER_XP_UPDATE" then XPTick()
        elseif event == "CHAT_MSG_SYSTEM" then OnMessage(a)
        elseif event == "UI_ERROR_MESSAGE" then OnMessage(b, true)
        else
            HudBuild()
            C_Timer.After(0.5, Check)           -- Check paints the icon too
        end
    end)
    -- the time in the run and the wait for a slot tick on without events
    C_Timer.NewTicker(1, function() if hud and (hud:IsShown() or cur) then HudPaint() end end)
end
