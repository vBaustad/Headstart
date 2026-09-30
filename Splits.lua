-- Level splits: this character's playing time from level 1, level by level, against your best run.
--   YippRouteDB.splits.runs[key] = { name, class, elapsed, xp, levels = { [level] = seconds played } }
-- The time is the server's own /played: asked for at login and after every level, counted on locally
-- in between. So every character is timed, the clock never stops while you are logged in, and a crash
-- or a disconnect can't lose time. The server also says how long you have been at this level, which
-- gives the level's start even on a character the splits never saw before.
--
--   XP/hr: 15.5k                      over the last 10 minutes of play
--   Ding: 4 min                       at that rate
--   Time: 58:06                       total play time, green while the next level can still beat the best run
--               level   total  vs best
--   Level 8 ..   9:21   58:06   -1:12   the level in progress, live
--   Level 7     17:37   48:45   +0:20   each level reached: its own time, time from level 1, difference
-- No background: outlined text straight on the screen.
local _, YR = ...

local TICK = 0.5
local RATE_WINDOW = 600          -- XP/hour over the last 10 minutes of play
local ROW_H = 16
local FONT = "Fonts\\FRIZQT__.TTF"
local TOP = 56                   -- the three lines above the table
local key, rec, frame, last, ticker
local synced = false             -- the server has told us this character's /played
local lastXP, lastMax, lastLevel
local rate = {}                  -- { play seconds, XP since level 1 } every few seconds, for XP/hour

local GREEN, RED, WHITE, GREY, BLUE = "|cff40ff40", "|cffff5050", "|cffffffff", "|cff999999", "|cff66ccff"

local function Text(size)
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, "OUTLINE")
    fs:SetShadowOffset(1, -1)
    return fs
end

local function Clock(s)
    s = floor(s + 0.5)
    local h, m = floor(s / 3600), floor(s % 3600 / 60)
    return h > 0 and ("%d:%02d:%02d"):format(h, m, s % 60) or ("%d:%02d"):format(m, s % 60)
end

-- A time coloured against the best run's: green when faster, red when slower, white with nothing to beat.
local function Vs(mine, theirs)
    if not theirs then return WHITE .. Clock(mine) .. "|r" end
    return (mine <= theirs and GREEN or RED) .. Clock(mine) .. "|r"
end

local function Delta(d)
    if not d then return "" end
    return (d <= 0 and GREEN .. "-" or RED .. "+") .. Clock(math.abs(d)) .. "|r"
end

local function DB()
    YippRouteDB.splits = YippRouteDB.splits or { runs = {} }
    return YippRouteDB.splits
end

local function Top(run)
    local top = 1
    for lvl in pairs(run.levels) do if lvl > top then top = lvl end end
    return top
end

-- The best other run: the one that got furthest, and of those the fastest to its top level.
local function Best()
    local best, bestTop, bestTime
    for k, r in pairs(DB().runs) do
        local top = Top(r)
        local t = r.levels[top] or r.elapsed
        if k ~= key and top > 1 and (not best or top > bestTop or (top == bestTop and t < bestTime)) then
            best, bestTop, bestTime = k, top, t
        end
    end
    return best and DB().runs[best]
end

local function XPRate()
    local a, b = rate[1], rate[#rate]
    if not (a and b) or b[1] - a[1] < 60 then return nil end
    return (b[2] - a[2]) / (b[1] - a[1]) * 3600
end

local function Short(n)
    return n >= 1000 and ("%.1fk"):format(n / 1000) or tostring(floor(n))
end

local function Row(i)
    local r = frame.rows[i]
    if r then return r end
    r = {}
    -- row 0 is the column headings; the level name hangs from its left edge, each time from its
    -- right edge, so headings and times line up whatever their font size
    local y = -TOP - i * ROW_H + (i == 0 and 3 or 0)
    for c, right in ipairs({ 0, 128, 186, 244 }) do
        local fs = Text(i == 0 and 11 or 14)
        if c == 1 then
            fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
        else
            fs:SetJustifyH("RIGHT")
            fs:SetPoint("TOPRIGHT", frame, "TOPLEFT", right, y)
        end
        r[c] = fs
    end
    frame.rows[i] = r
    return r
end

local function SetRow(i, a, b, c, d)
    local r = Row(i)
    r[1]:SetText(a) r[2]:SetText(b) r[3]:SetText(c) r[4]:SetText(d)
    for _, fs in ipairs(r) do fs:Show() end
end

local function Refresh()
    if not (frame and frame:IsShown()) then return end
    local run, pb = rec, Best()
    local n = 0
    if run and not synced then
        frame.xph:SetText(BLUE .. "Time:|r " .. GREY .. "asking the server...|r")
        frame.ding:SetText("")
        frame.time:SetText("")
    elseif run then
        local level = UnitLevel("player")
        local theirsNow = pb and pb.levels[level + 1]
        -- green while you can still reach the next level before the best run did
        frame.time:SetText(BLUE .. "Time:|r " .. Vs(run.elapsed, theirsNow))
        local xph = XPRate()
        local left = UnitXPMax("player") - UnitXP("player")
        frame.xph:SetText(BLUE .. "XP/hr:|r " .. (xph and xph > 0 and Short(xph) or "-"))
        frame.ding:SetText(BLUE .. "Ding:|r " .. (xph and xph > 0 and ("%d min"):format(math.ceil(left / xph * 60)) or "-"))
        -- the level in progress, live
        local since = run.levels[level] or 0
        local seg = pb and pb.levels[level + 1] and pb.levels[level] and pb.levels[level + 1] - pb.levels[level]
        n = n + 1
        SetRow(n, BLUE .. ("Level %d|r"):format(level + 1) .. GREY .. " ..|r", Vs(run.elapsed - since, seg),
            Vs(run.elapsed, theirsNow), Delta(theirsNow and run.elapsed - theirsNow))
    else
        frame.xph:SetText(BLUE .. "Best run|r")
        frame.ding:SetText(GREY .. "new characters are timed from level 1|r")
        frame.time:SetText(BLUE .. "Time:|r " .. (pb and WHITE .. Clock(pb.levels[Top(pb)]) .. "|r" or "-"))
        run, pb = pb, nil
    end
    -- every level reached, newest first
    if run then
        for lvl = Top(run), 2, -1 do
            local at, before = run.levels[lvl], run.levels[lvl - 1]
            if at then
                -- a level reached before the splits knew this character has a total but no own time
                local theirs = pb and pb.levels[lvl]
                local theirSeg = theirs and pb.levels[lvl - 1] and theirs - pb.levels[lvl - 1]
                n = n + 1
                SetRow(n, BLUE .. ("Level %d|r"):format(lvl), before and Vs(at - before, theirSeg) or GREY .. "-|r",
                    Vs(at, theirs), Delta(theirs and at - theirs))
            end
        end
    end
    for i = n + 1, #frame.rows do
        for _, fs in ipairs(frame.rows[i]) do fs:Hide() end
    end
    frame:SetHeight(TOP + (n + 1) * ROW_H)
end

local function Tick()
    local now = GetTime()
    if rec and last then
        rec.elapsed = rec.elapsed + (now - last)
        local newest = rate[#rate]
        if not newest or rec.elapsed - newest[1] >= 5 then
            rate[#rate + 1] = { rec.elapsed, rec.xp or 0 }
            while rate[1] and rec.elapsed - rate[1][1] > RATE_WINDOW do table.remove(rate, 1) end
        end
    end
    last = now
    Refresh()
end

local function Build()
    frame = CreateFrame("Frame", "YippRouteSplitsFrame", UIParent)
    frame:SetSize(246, TOP)
    frame.rows = {}
    local p = YippRouteDB.splitsPos
    if p then frame:SetPoint(p[1], UIParent, p[1], p[2], p[3]) else frame:SetPoint("TOP", 0, -120) end
    frame.xph = Text(16)
    frame.xph:SetPoint("TOPLEFT", 0, 0)
    frame.ding = Text(16)
    frame.ding:SetPoint("TOPLEFT", 0, -17)
    frame.time = Text(16)
    frame.time:SetPoint("TOPLEFT", 0, -34)
    SetRow(0, "", GREY .. "level|r", GREY .. "total|r", GREY .. "vs best|r")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        YippRouteDB.splitsPos = { point, x, y }
    end)
end

function YR:ShowSplits(on)
    YippRouteDB.showSplits = on
    if on then
        if not frame then Build() end
        frame:Show()
        Refresh()
    elseif frame then
        frame:Hide()
    end
end

-- Runs from before the splits existed, rebuilt once from the run log's position samples: play time
-- is the sum of the gaps between samples, leaving out any gap over a minute (logged out). The log
-- mixes characters under one name, so a level that drops or jumps by more than one is another
-- character and ends the run; only runs from level 1 count.
local LOGGED_OUT = 60
local function ImportLogs()
    local db = DB()
    if db.imported then return end
    db.imported = true
    local n = 0
    for char, r in pairs(YippRouteDB.runs or {}) do
        local cur, prev
        for _, p in ipairs(r.track or {}) do
            local t, level = p[1], p[5]
            if prev and (level < prev[5] or level > prev[5] + 1) then cur = nil end
            if not cur and level == 1 then
                cur = { name = char .. " (log)", elapsed = 0, levels = { [1] = 0 } }
                n = n + 1
                db.runs["log:" .. char .. ":" .. n] = cur
            elseif cur and prev then
                local dt = t - prev[1]
                if dt <= LOGGED_OUT then cur.elapsed = cur.elapsed + dt end
                for lvl = prev[5] + 1, level do cur.levels[lvl] = cur.elapsed end
            end
            prev = p
        end
    end
    -- a stretch that never left level 2 is a false start, not a run
    for k, run in pairs(db.runs) do
        if k:find("^log:") and not run.levels[3] then db.runs[k] = nil end
    end
end

-- /played without the two lines it prints in chat: the chat windows stop listening until the answer
-- is in, then listen again.
local muted = {}
local function AskPlayed()
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local cf = _G["ChatFrame" .. i]
        if cf and cf:IsEventRegistered("TIME_PLAYED_MSG") then
            cf:UnregisterEvent("TIME_PLAYED_MSG")
            muted[#muted + 1] = cf
        end
    end
    RequestTimePlayed()
end

local function Unmute()
    for _, cf in ipairs(muted) do cf:RegisterEvent("TIME_PLAYED_MSG") end
    wipe(muted)
end

-- Every character is timed: one seen before carries on, any other starts a record now.
function YR:StartSplits()
    ImportLogs()
    local name = UnitFullName("player")
    local ok, guid = pcall(function() return UnitGUID("player") .. "" end)
    if not name or name == UNKNOWNOBJECT or name == "Unknown" or not ok then
        C_Timer.After(2, function() YR:StartSplits() end)
        return
    end
    key = guid
    rec = DB().runs[key]
    if not rec then
        local _, class = UnitClass("player")
        rec = { name = YR.CharKey(), class = class, elapsed = 0, xp = 0, levels = {} }
        DB().runs[key] = rec
    end
    synced = false
    AskPlayed()
    wipe(rate)
    lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    last = GetTime()
    ticker = ticker or C_Timer.NewTicker(TICK, Tick)
    if YippRouteDB.showSplits ~= false then YR:ShowSplits(true) end
end

function YR:ResetSplits()
    if key then DB().runs[key] = nil end
    rec = nil
    YR.Print("splits for this character cleared.")
    YR:StartSplits()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("PLAYER_XP_UPDATE")
f:RegisterEvent("TIME_PLAYED_MSG")
f:SetScript("OnEvent", function(_, event, level, atLevel)
    if event == "TIME_PLAYED_MSG" then
        -- level is the total here, atLevel the time at this level: the server's word replaces our count
        Unmute()
        if rec and type(level) == "number" then
            rec.elapsed = level
            last = GetTime()
            local lvl = UnitLevel("player")
            if not rec.levels[lvl] and type(atLevel) == "number" then rec.levels[lvl] = level - atLevel end
            synced = true
        end
        Refresh()
        return
    end
    if event == "PLAYER_XP_UPDATE" then
        -- XP since level 1, for XP/hour; a level-up in between adds what was left of the old level
        local xp, lvl = UnitXP("player"), UnitLevel("player")
        if rec and lastXP then
            local gained = lvl > lastLevel and (lastMax - lastXP + xp) or (xp - lastXP)
            if gained > 0 then rec.xp = (rec.xp or 0) + gained end
        end
        lastXP, lastMax, lastLevel = xp, UnitXPMax("player"), lvl
        return
    end
    if rec then
        rec.levels[level] = rec.elapsed
        C_Timer.After(1, AskPlayed)          -- and check our count against the server's
        local pb = Best()
        local theirs = pb and pb.levels[level]
        YR.Print(("level %d at %s%s"):format(level, Clock(rec.elapsed), theirs and ("  " .. Delta(rec.elapsed - theirs)) or ""))
    end
    Refresh()
end)
