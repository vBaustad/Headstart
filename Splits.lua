-- Level splits: this character's playing time from level 1, level by level, against your best run.
--   YippRouteDB.splits.runs[key] = { name, class, elapsed, xp, levels = { [level] = seconds played } }
-- The time is the server's own /played: asked for at login and after every level, counted on locally
-- in between. So every character is timed, the clock never stops while you are logged in, and a crash
-- or a disconnect can't lose time. The server also says how long you have been at this level, which
-- gives the level's start even on a character the splits never saw before.
--
--   XP/hr: 15.5k   1.2k / 2.8k        over the last 10 minutes of play; this level's XP of what it takes
--   Ding: 4 min                       at that rate
--   Time: 58:06                       total play time, green while the next level can still beat the best run
--               level   total  vs best
--   Level 8 ..   9:21   58:06   -1:12   the level in progress, live
--   Level 7     17:37   48:45   +0:20   each level reached: its own time, time from level 1, difference
-- Outlined text straight on the screen by default; size, lines shown, background and position are
-- settings (YippRouteDB.splitsStyle, YippRouteDB.splitsPos) changed from the Headstart window.
local _, YR = ...

local TICK = 0.5
local RATE_WINDOW = 600          -- XP/hour over the last 10 minutes of play
local FONT = "Fonts\\FRIZQT__.TTF"
local TOP, ROW_H = 56, 16        -- set by Layout from the text size
local key, rec, frame, last, ticker
local synced = false             -- the server has told us this character's /played
local lastXP, lastMax, lastLevel
local rate = {}                  -- { play seconds, XP since level 1 } every few seconds, for XP/hour

local GREEN, RED, WHITE, GREY, BLUE = "|cff40ff40", "|cffff5050", "|cffffffff", "|cff999999", "|cff66ccff"

local STYLE_DEFAULT = { size = 14, lock = false, rate = true, ding = true, vs = true, rows = 20, bg = 0,
    clock = "full", levelCol = true, totalCol = true }

function YR:SplitsStyle()
    local st = YippRouteDB.splitsStyle
    if not st then st = {} YippRouteDB.splitsStyle = st end
    for k, v in pairs(STYLE_DEFAULT) do if st[k] == nil then st[k] = v end end
    return st
end

-- Every text the box draws, with its role, so a new text size reaches all of them.
local fonts = {}
local function Text(role)
    local fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetShadowOffset(1, -1)
    fonts[#fonts + 1] = { fs = fs, role = role }
    local size = YR:SplitsStyle().size
    fs:SetFont(FONT, role == "top" and size + 2 or role == "head" and math.max(9, size - 3) or size, "OUTLINE")
    return fs
end

-- A time: 1:50:19 ("full"), or past an hour without the seconds, 1h 50m ("short"). Under an hour
-- both are 27:57. Days stay hours (46:55:53, 46h 55m): /played on a main runs into days.
local function Clock(s)
    s = floor(s + 0.5)
    local h, m = floor(s / 3600), floor(s % 3600 / 60)
    if h == 0 then return ("%d:%02d"):format(m, s % 60) end
    if YR:SplitsStyle().clock == "short" then return ("%dh %02dm"):format(h, m) end
    return ("%d:%02d:%02d"):format(h, m, s % 60)
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

-- Whether a run has a time for every level up to its highest. A character the splits first saw
-- part-way (already level 8, say) has only that level's total: nothing to compare levels 2-7 with.
local function Complete(run)
    for lvl = 2, Top(run) do
        if not run.levels[lvl] then return false end
    end
    return true
end

-- The best other run: the one that got furthest, and of those the fastest to its top level. Runs
-- with every level timed come first; a partial one only when there is nothing else.
local function Best()
    local best, bestTop, bestTime, bestFull
    for k, r in pairs(DB().runs) do
        local top = Top(r)
        local t = r.levels[top] or r.elapsed
        local full = Complete(r)
        if k ~= key and top > 1 and not r.noBest and (not best or (full and not bestFull)
                or (full == bestFull and (top > bestTop or (top == bestTop and t < bestTime)))) then
            best, bestTop, bestTime, bestFull = k, top, t, full
        end
    end
    return best and DB().runs[best]
end
YR.SplitsBest = Best   -- for the tests

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
    for c = 1, 4 do
        local fs = Text(i == 0 and "head" or "row")
        if c > 1 then fs:SetJustifyH("RIGHT") end
        r[c] = fs
    end
    frame.rows[i] = r
    return r
end

-- Which columns show: 1 the level, 2 its own time, 3 the time from level 1, 4 against the best run.
local function Shown(c)
    local st = YR:SplitsStyle()
    return c == 1 or (c == 2 and st.levelCol) or (c == 3 and st.totalCol) or (c == 4 and st.vs)
end

local function SetRow(i, a, b, c, d)
    local r = Row(i)
    r[1]:SetText(a) r[2]:SetText(b) r[3]:SetText(c) r[4]:SetText(d)
    for col, fs in ipairs(r) do fs:SetShown(Shown(col)) end
end

-- Each column as wide as its widest text so far, so long times (hours, days of /played) never run
-- into the next column. Widths only grow until the style changes: a ticking clock doesn't make the
-- columns jitter. The level name hangs from the left edge, each time from its column's right edge.
local widths = {}
local function Arrange(n)
    local k = YR:SplitsStyle().size / 14
    local gap = 12 * k
    for c = 1, 4 do
        local w = widths[c] or 0
        for i = 0, n do
            local fs = frame.rows[i] and frame.rows[i][c]
            if fs and Shown(c) then w = math.max(w, fs:GetStringWidth() or 0) end
        end
        widths[c] = w
    end
    local right = 0
    for c = 1, 4 do
        if Shown(c) then right = right + (c > 1 and gap or 0) + widths[c] end
        for i = 0, n do
            local fs = frame.rows[i] and frame.rows[i][c]
            if fs then
                local y = -TOP - i * ROW_H + (i == 0 and 3 or 0)
                fs:ClearAllPoints()
                if c == 1 then fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
                else fs:SetPoint("TOPRIGHT", frame, "TOPLEFT", right, y) end
            end
        end
    end
    frame:SetWidth(math.max(right, 150 * k))
end

local function Layout()
    local st = YR:SplitsStyle()
    for _, f in ipairs(fonts) do
        f.fs:SetFont(FONT, f.role == "top" and st.size + 2 or f.role == "head" and math.max(9, st.size - 3) or st.size, "OUTLINE")
    end
    local lineH = st.size + 5
    local y = 0
    for _, line in ipairs({ { frame.xph, st.rate }, { frame.ding, st.ding }, { frame.time, true } }) do
        line[1]:SetShown(line[2])
        if line[2] then
            line[1]:ClearAllPoints()
            line[1]:SetPoint("TOPLEFT", 0, -y)
            y = y + lineH
        end
    end
    TOP, ROW_H = y + 6, st.size + 2
    widths = {}
    frame.bg:SetColorTexture(0, 0, 0, st.bg / 100)
    frame:EnableMouse(not st.lock)
    SetRow(0, "", GREY .. "level|r", GREY .. "total|r", GREY .. "vs best|r")
end

local function Refresh()
    if not (frame and frame:IsShown()) then return end
    local run, pb = rec, Best()
    local n = 0
    if run and not synced then
        frame.xph:SetText("")
        frame.ding:SetText("")
        frame.time:SetText(BLUE .. "Time:|r " .. GREY .. "asking the server...|r")
    elseif run and run.stopped then
        frame.xph:SetText(BLUE .. "Run stopped|r" .. (run.noBest and GREY .. "  (not a run to beat)|r" or ""))
        frame.ding:SetText(GREY .. "Resume it on the This run page|r")
        frame.time:SetText(BLUE .. "Time:|r " .. WHITE .. Clock(run.elapsed) .. "|r")
    elseif run then
        local level = UnitLevel("player")
        local theirsNow = pb and pb.levels[level + 1]
        -- green while you can still reach the next level before the best run did
        frame.time:SetText(BLUE .. "Time:|r " .. Vs(run.elapsed, theirsNow))
        local xph = XPRate()
        local xp, max = UnitXP("player"), UnitXPMax("player")
        local left = max - xp
        frame.xph:SetText(BLUE .. "XP/hr:|r " .. (xph and xph > 0 and Short(xph) or "-")
            .. (max > 0 and ("   " .. Short(xp) .. GREY .. " / " .. Short(max) .. "|r") or ""))
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
    -- every level reached, newest first, as many as the settings say
    if run then
        local listed, most = 0, YR:SplitsStyle().rows
        for lvl = Top(run), 2, -1 do
            local at, before = run.levels[lvl], run.levels[lvl - 1]
            if at and listed < most then
                listed = listed + 1
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
    Arrange(n)
    frame:SetHeight(TOP + (n + 1) * ROW_H)
end

local function Tick()
    local now = GetTime()
    if rec and last and not rec.stopped then
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

-- The position is kept as pixels from the screen's top-left corner, which the settings show and set.
local function Place()
    local p = YippRouteDB.splitsPos
    frame:ClearAllPoints()
    if p and p[1] == "TOPLEFT" then
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p[2], p[3])
    elseif p then
        frame:SetPoint(p[1], UIParent, p[1], p[2], p[3])     -- saved before positions were pixels
    else
        frame:SetPoint("TOP", 0, -120)
    end
end

local function Remember()
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top then
        YippRouteDB.splitsPos = { "TOPLEFT", floor(left + 0.5), floor(top - UIParent:GetTop() + 0.5) }
    end
end

function YR:SplitsPosition()
    local p = YippRouteDB.splitsPos
    if frame and (not p or p[1] ~= "TOPLEFT") then Remember() p = YippRouteDB.splitsPos end
    if p and p[1] == "TOPLEFT" then return { p[2], -p[3] } end
    return { 0, 0 }
end

function YR:SetSplitsPosition(left, top)
    local cur = YR:SplitsPosition()
    YippRouteDB.splitsPos = { "TOPLEFT", floor(left or cur[1]), -floor(top or cur[2]) }
    if frame then Place() end
end

function YR:ApplySplitsStyle()
    if not frame then return end
    Layout()
    Refresh()
end

local function Build()
    frame = CreateFrame("Frame", "HeadstartSplitsFrame", UIParent)
    -- the lowest layer, like RestedXP's guide window: bags, maps and other windows open over it
    frame:SetFrameStrata("BACKGROUND")
    frame:SetSize(246, TOP)
    frame.rows = {}
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetPoint("TOPLEFT", -6, 6)
    frame.bg:SetPoint("BOTTOMRIGHT", 6, -4)
    Place()
    frame.xph = Text("top")
    frame.ding = Text("top")
    frame.time = Text("top")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Remember()
        YR:RefreshWindow()
    end)
    Layout()
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

-- Stop run: the clock and the levels stop here, and the run log ends (until Resume). A stopped run
-- still counts as a run to beat unless the player says it shouldn't (noBest: a missed quest, say).
function YR:StopRun()
    if rec and not rec.stopped then rec.stopped = time() end
    if YR.StopLog then YR:StopLog() end
    Refresh()
end

function YR:ResumeRun()
    if rec and rec.stopped then
        rec.stopped, rec.resuming = nil, true
        last = GetTime()
        AskPlayed()
    end
    if YR.ResumeLog then YR:ResumeLog() end
    Refresh()
end

function YR:RunStopped() return rec and rec.stopped ~= nil or false end
function YR:RunCounts() return not (rec and rec.noBest) end
function YR:SetRunCounts(on) if rec then rec.noBest = not on or nil end Refresh() end

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
        if rec and type(level) == "number" and not rec.stopped then
            -- after a Resume, the time the run was stopped doesn't count
            if rec.resuming then rec.paused, rec.resuming = level - rec.elapsed, nil end
            local total = level - (rec.paused or 0)
            rec.elapsed = total
            last = GetTime()
            local lvl = UnitLevel("player")
            if not rec.levels[lvl] and type(atLevel) == "number" then rec.levels[lvl] = total - atLevel end
        end
        synced = true
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
    if rec and not rec.stopped then
        rec.levels[level] = rec.elapsed
        C_Timer.After(1, AskPlayed)          -- and check our count against the server's
        local pb = Best()
        local theirs = pb and pb.levels[level]
        YR.Print(("level %d at %s%s"):format(level, Clock(rec.elapsed), theirs and ("  " .. Delta(rec.elapsed - theirs)) or ""))
    end
    Refresh()
end)
