-- Level splits: this character's playing time from level 1, level by level, against your best run.
--   YippRouteDB.splits.runs[key] = { name, class, race, elapsed, xp, levels = { [level] = seconds played } }
-- The time is the server's own /played: asked for at login and after every level, counted on locally
-- in between. So the clock never stops while you are logged in, and a crash or a disconnect can't lose
-- time. The server also says how long you have been at this level, which gives the level's start even
-- on a character the splits never saw before.
--
-- A part (Core.lua): a character is timed while the box is shown (showSplits) or the XP bar is on (it
-- shows XP an hour and time played from here). With neither, nothing here runs: no /played asked at
-- the login, no clock, no events, and no record made for the character.
--
--   XP/hr: 15.5k   1.2k / 2.8k        over the last 10 minutes of play; this level's XP of what it takes
--   Ding: 4 min                       at that rate
--   Time: 58:06                       total play time, green while the next level can still beat the best run
--               level  ± level   total  vs best
--   Level 8 ..   9:21    -0:40   58:06   -1:12   the level in progress, live
--   Level 7     17:37    +0:20   48:45   -0:32   each level reached: its own time, what that level won or
--                                                lost against the best run's, time from level 1, difference
-- Outlined text straight on the screen by default; size, lines shown, background and position are
-- settings (YippRouteDB.splitsStyle, YippRouteDB.splitsPos) changed from the Headstart window.
local _, YR = ...

local TICK = 0.5
local RATE_WINDOW = 600          -- XP/hour over the last 10 minutes of play
local FONT = "Fonts\\FRIZQT__.TTF"
local TOP, ROW_H = 56, 16        -- set by Layout from the text size
local key, rec, frame, last
local part                       -- the part: on while the box or the XP bar wants this character timed
local synced = false             -- the server has told us this character's /played
local lastXP, lastMax, lastLevel
local rate = {}                  -- { play seconds, XP since level 1 } every few seconds, for XP/hour

local GREEN, RED, WHITE, GREY, BLUE = "|cff40ff40", "|cffff5050", "|cffffffff", "|cff999999", "|cff66ccff"

local STYLE_DEFAULT = { size = 14, lock = false, rate = true, ding = true, vs = true, rows = 20, bg = 0,
    clock = "full", levelCol = true, totalCol = true, levelVs = true }
-- Taken out of the window (the owner, 2026-10-21, the Levelling tab made over: "fewer settings"): where the box
-- stands is set in Arrange alone, so it is locked - clicks go through it - and it has no background and the long
-- clock, whatever an older version stored.
local STYLE_SETTLED = { lock = true, bg = 0, clock = "full" }

-- What's missing is filled in once for a style table, not on every read: this is asked for some
-- two hundred times each time the box is drawn.
local styleFilled
function YR:SplitsStyle()
    local st = YippRouteDB.splitsStyle
    if st and styleFilled == st then return st end
    if not st then st = {} YippRouteDB.splitsStyle = st end
    for k, v in pairs(STYLE_DEFAULT) do if st[k] == nil then st[k] = v end end
    for k, v in pairs(STYLE_SETTLED) do st[k] = v end
    styleFilled = st
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

-- The runs, for reading: none is not a reason to start a saved table (the log's clean-up asks at every
-- login, splits on or not).
local NO_RUNS = {}
local function Runs()
    local db = YippRouteDB.splits
    return db and db.runs or NO_RUNS
end

-- This character's record: the one being timed, else the saved one if it has one (the splits may be
-- off: Stop run and Resume still mark it). Never makes one.
local function Guid() return UnitGUID("player") .. "" end       -- a secret GUID errors here: no record
local function Mine()
    if rec then return rec end
    local db = YippRouteDB.splits
    if not (db and db.runs) then return nil end
    local ok, guid = pcall(Guid)
    return ok and db.runs[guid] or nil
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
    for k, r in pairs(Runs()) do
        local top = Top(r)
        local t = r.levels[top] or r.elapsed
        local full = Complete(r)
        if k ~= key and top > 1 and not r.noBest and (not best or (full and not bestFull)
                or (full == bestFull and (top > bestTop or (top == bestTop and t < bestTime)))) then
            best, bestTop, bestTime, bestFull = k, top, t, full
        end
    end
    return best and Runs()[best]
end
YR.SplitsBest = Best   -- for the tests

-- What to beat, level by level: the fastest any other run (not this one, not one marked "not a run to
-- beat") reached each level, and the fastest any of them took over each single level (both ends timed).
-- Not one "best run": the run that got furthest isn't the fastest at every level - one that stopped at
-- 11 can have been six minutes quicker to 10 - and comparing with it showed a lead that wasn't there.
-- { levels = { [N] = seconds to reach N }, segs = { [N] = seconds from N-1 to N } }, or nil.
-- Which runs count (YippRouteDB.splitsCompare): "any" (nil, the default), "class" (your class), or
-- "race" (your class and race; Dwarves and Gnomes count as one, they share the start and the route).
-- A run from before races were recorded has its race looked up by its GUID when the game still knows
-- it; one it can't place is left out of "class and race".
local RACE_GROUP = { Gnome = "Dwarf" }
local function RaceGroup(race) return race and (RACE_GROUP[race] or race) or nil end

local function RunRace(k, r)
    if r.race then return r.race end
    if GetPlayerInfoByGUID and type(k) == "string" and k:find("^Player%-") then
        local ok, _, _, _, race = pcall(GetPlayerInfoByGUID, k)
        if ok and race then r.race = race return race end
    end
end

-- The route a run started on: the RestedXP guide it was on at level 6 or below (rec.route, kept from
-- the moment it is first seen), so practice on one opener is compared with practice on the same
-- opener: "class and start route" (the user, 2026-10-20: lean runs against lean runs, "ellers er jeg
-- alltid bak når jeg praccer"). Runs from before this have none; a routes addon may name theirs in
-- HeadstartRunRoutes ["Name-Realm"] = guide name. RestedXP writes "01-06" where a guide says "1-6".
local function Plain(name)
    return type(name) == "string" and (name:gsub("^0(%d)", "%1"):gsub("%-0(%d)", "-%1")) or nil
end
local function RouteOf(r)
    if r.route then return Plain(r.route) end
    local known = _G.HeadstartRunRoutes
    return type(known) == "table" and r.name and Plain(known[r.name]) or nil
end
YR.SplitsRouteOf = RouteOf   -- for the tests
-- The guide RestedXP has loaded, while you are still on an opener (level 6 or below), else nil.
local function StartNow()
    if (UnitLevel("player") or 99) > 6 then return nil end
    local guide = type(RXP) == "table" and RXP.currentGuide
    local name = type(guide) == "table" and (guide.name or guide.displayname)
    return type(name) == "string" and name ~= "" and name or nil
end
-- Past 6 with no route kept (a run begun before this was added): this character's own run log says
-- which opener it played most up to level 6 (its "step" rows, Log.lua). Asked once a login.
local fromLog
local function StartInLog()
    if fromLog ~= nil then return fromLog or nil end
    fromLog = false
    local key = YR.CharKey and YR.CharKey()
    local run = key and type(YippRouteDB.runs) == "table" and YippRouteDB.runs[key]
    if type(run) ~= "table" or type(run.ev) ~= "table" then return nil end
    local count, best, most = {}, nil, 0
    for _, e in ipairs(run.ev) do
        local g = e[2] == "step" and (e[4] or 99) <= 6 and e.guide
        if type(g) == "string" and (g:find("^01%-0") or g:find("^1%-")) then
            count[g] = (count[g] or 0) + 1
            if count[g] > most then best, most = g, count[g] end
        end
    end
    fromLog = best or false
    return best
end
YR.SplitsStartInLog = StartInLog   -- for the tests
local function NoteRoute()
    if rec and not rec.route then rec.route = StartNow() or StartInLog() end
end

local function Counts(k, r)
    local by = YippRouteDB.splitsCompare
    if not by or by == "any" then return true end
    -- one run picked by hand: on launch day the stress test's run, not the faster beta runs that came
    -- along when the settings were copied over (the user, 2026-10-22)
    if by == "pin" then return k == YippRouteDB.splitsPin end
    local _, myClass = UnitClass("player")
    local myRace = rec and rec.race or select(2, UnitRace("player"))
    if r.class ~= (rec and rec.class or myClass) then return false end
    if by == "race" then
        local race = RunRace(k, r)
        return race ~= nil and RaceGroup(race) == RaceGroup(myRace)
    end
    if by == "route" then
        local mine = rec and RouteOf(rec) or Plain(StartNow())
        return mine ~= nil and RouteOf(r) == mine
    end
    return true
end
YR.SplitsCounts = Counts   -- for the tests

local function Fastest()
    local levels, segs, any = {}, {}, false
    for k, r in pairs(Runs()) do
        if k ~= key and not r.noBest and type(r.levels) == "table" and Counts(k, r) then
            for lvl, t in pairs(r.levels) do
                if lvl > 1 then
                    any = true
                    if not levels[lvl] or t < levels[lvl] then levels[lvl] = t end
                    local before = r.levels[lvl - 1]
                    if before and (not segs[lvl] or t - before < segs[lvl]) then segs[lvl] = t - before end
                end
            end
        end
    end
    return any and { levels = levels, segs = segs } or nil
end
YR.SplitsFastest = Fastest   -- for the tests

--- The characters ("Name-Realm") whose run holds the best time to some level among the runs of their
--- class: the fastest runs, the ones the splits compare with whichever character you're on. Their
--- run logs are never cleared away as old (Log.lua).
function YR.SplitsBestRuns()
    local at, who, out = {}, {}, {}
    for _, r in pairs(Runs()) do
        if not r.noBest and type(r.levels) == "table" and r.name then
            for lvl, t in pairs(r.levels) do
                local slot = (r.class or "?") .. lvl
                if lvl > 1 and (not at[slot] or t < at[slot]) then at[slot], who[slot] = t, r.name end
            end
        end
    end
    for _, name in pairs(who) do out[name] = true end
    local pinned = YippRouteDB.splitsPin and Runs()[YippRouteDB.splitsPin]
    if pinned and pinned.name then out[pinned.name] = true end      -- the run picked to compare with
    return out
end

--- The timed runs to pick one from ("Compare with: One run I pick"): { key, label }, highest level
--- first. The label tells two characters of one name apart (a beta run and the same name on live).
function YR.SplitsRunList()
    local out = {}
    for k, r in pairs(Runs()) do
        local top, at = 0, 0
        for lvl, t in pairs(type(r.levels) == "table" and r.levels or {}) do
            if lvl > top then top, at = lvl, t end
        end
        if top > 1 and k ~= key then
            local name = (r.name or "?"):gsub("%-.*", "")
            local class = r.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[r.class] or r.class or "?"
            out[#out + 1] = { k, ("%s, %s: level %d at %d:%02d"):format(name, class, top, floor(at / 3600), floor(at % 3600 / 60)),
                top = top, at = at }
        end
    end
    table.sort(out, function(a, b) if a.top ~= b.top then return a.top > b.top end return a.at < b.at end)
    return out
end

--- A character's race as the splits know it (nil for one they never timed).
function YR.SplitsRaceOf(char)
    for _, r in pairs(Runs()) do
        if r.name == char and r.race then return r.race end
    end
end

-- What to beat changes when you ding, a run is deleted or "compare with" is set, not while the clock
-- runs (nobody else's run moves while you are logged in): the clock's own tick works from the copy,
-- and anything else that draws the box (a ding, a setting, the box shown, the server's answer) asks
-- afresh. The copy used to be thrown away every ten seconds, which laid the whole box out again each
-- time with nothing changed.
local best, bestKnown = nil, false
local function FastestKept(fresh)
    if fresh or not bestKnown then best, bestKnown = Fastest(), true end
    return best
end

local function XPRate()
    local a, b = rate[1], rate[#rate]
    if not (a and b) or b[1] - a[1] < 60 then return nil end
    return (b[2] - a[2]) / (b[1] - a[1]) * 3600
end

--- For the XP bar: XP an hour over the last 10 minutes of play (nil until there's enough), and this
--- character's played time, total and this level (from the server's /played, counted on since).
function YR.SplitsXPRate() return XPRate() end
function YR.SplitsPlayed()
    if not rec then return nil end
    local at = rec.levels and rec.levels[UnitLevel("player")]
    return rec.elapsed, at and (rec.elapsed - at) or nil
end

local function Short(n)
    return n >= 1000 and ("%.1fk"):format(n / 1000) or tostring(floor(n))
end

local function Row(i)
    local r = frame.rows[i]
    if r then return r end
    r = {}
    for c = 1, 5 do
        local fs = Text(i == 0 and "head" or "row")
        if c > 1 then fs:SetJustifyH("RIGHT") end
        r[c] = fs
    end
    frame.rows[i] = r
    return r
end

-- Which columns show: 1 the level, 2 its own time, 3 the time from level 1, 4 against the best run,
-- 5 what this level alone won or lost against the best run's. Left to right: 1, 2, 5, 3, 4.
local ORDER = { 1, 2, 5, 3, 4 }
local function Shown(c)
    local st = YR:SplitsStyle()
    return c == 1 or (c == 2 and st.levelCol) or (c == 3 and st.totalCol) or (c == 4 and st.vs)
        or (c == 5 and st.levelVs)
end

local function SetRow(i, a, b, c, d, e)
    local r = Row(i)
    r[1]:SetText(a) r[2]:SetText(b) r[3]:SetText(c) r[4]:SetText(d) r[5]:SetText(e or "")
    for col, fs in ipairs(r) do fs:SetShown(Shown(col)) end
end

-- Each column as wide as its widest text so far, so long times (hours, days of /played) never run
-- into the next column. Widths only grow until the style changes: a ticking clock doesn't make the
-- columns jitter. The level name hangs from the left edge, each time from its column's right edge.
local widths = {}
local function Arrange(n)
    local k = YR:SplitsStyle().size / 14
    local gap = 12 * k
    for c = 1, 5 do
        local w = widths[c] or 0
        for i = 0, n do
            local fs = frame.rows[i] and frame.rows[i][c]
            if fs and Shown(c) then w = math.max(w, fs:GetStringWidth() or 0) end
        end
        widths[c] = w
    end
    local right = 0
    for _, c in ipairs(ORDER) do
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
    SetRow(0, "", GREY .. "level|r", GREY .. "total|r", GREY .. "vs best|r", GREY .. "± level|r")
end

-- tick: the clock's own call. Then only what a clock changes is done: the three lines at the top and
-- the level in progress. The levels already reached, the columns' widths and the box's height are
-- worked out again when something else asked (a ding, a setting, the box shown).
-- shownSec: the second the box was last drawn for; stale: XP came in since. The clock (Tick) draws
-- again only when one of the two says the text would differ.
local listedRows = 0
local shownSec, stale = nil, false
local function Refresh(tick)
    if not (frame and frame:IsShown()) then return end
    local run = rec
    shownSec, stale = rec and floor(rec.elapsed + 0.5) or 0, false
    local pb = FastestKept(not tick)
    local full = not tick
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
        local seg = pb and pb.segs[level + 1]
        n = n + 1
        SetRow(n, BLUE .. ("Level %d|r"):format(level + 1) .. GREY .. " ..|r", Vs(run.elapsed - since, seg),
            Vs(run.elapsed, theirsNow), Delta(theirsNow and run.elapsed - theirsNow),
            Delta(seg and run.levels[level] and run.elapsed - since - seg))
    else
        frame.xph:SetText(BLUE .. "Best run|r")
        frame.ding:SetText(GREY .. "new characters are timed from level 1|r")
        local best = Best()                  -- no timed character here: show the best whole run
        frame.time:SetText(BLUE .. "Time:|r " .. (best and WHITE .. Clock(best.levels[Top(best)]) .. "|r" or "-"))
        run, pb = best, nil
    end
    if not full then
        -- the clock alone: if the level in progress has outgrown a column, the columns are laid again
        local live = frame.rows[1]
        for c = 1, 5 do
            if live and live[c]:IsShown() and (live[c]:GetStringWidth() or 0) > (widths[c] or 0) + 0.5 then
                Arrange(listedRows)
                break
            end
        end
        return
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
                local theirSeg = pb and pb.segs[lvl]
                n = n + 1
                SetRow(n, BLUE .. ("Level %d|r"):format(lvl), before and Vs(at - before, theirSeg) or GREY .. "-|r",
                    Vs(at, theirs), Delta(theirs and at - theirs), Delta(before and theirSeg and at - before - theirSeg))
            end
        end
    end
    for i = n + 1, #frame.rows do
        for _, fs in ipairs(frame.rows[i]) do fs:Hide() end
    end
    listedRows = n
    Arrange(n)
    frame:SetHeight(TOP + (n + 1) * ROW_H)
end

-- Twice a second: the time is counted on, and every five seconds of play a sample for XP/hour is
-- kept (the pair that falls out of the ten minutes is the one written next). The box shows whole
-- seconds, so it is drawn again only when the second it shows has changed, or XP came in - not at all
-- while it is hidden, the run is stopped or the server hasn't answered.
local spare
local function Tick()
    local now = GetTime()
    if rec and last and not rec.stopped then
        if not rec.route then NoteRoute() end
        rec.elapsed = rec.elapsed + (now - last)
        local newest = rate[#rate]
        if not newest or rec.elapsed - newest[1] >= 5 then
            local pair = spare or {}
            spare = nil
            pair[1], pair[2] = rec.elapsed, rec.xp or 0
            rate[#rate + 1] = pair
            while rate[1] and rec.elapsed - rate[1][1] > RATE_WINDOW do spare = table.remove(rate, 1) end
        end
    end
    last = now
    if not (frame and frame:IsShown()) then return end
    if stale or (rec and floor(rec.elapsed + 0.5) or 0) ~= shownSec then Refresh(true) end
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

-- The box as the setting says: built the first time it is shown.
local function SyncBox()
    if part and part.on and YR.Option("showSplits") then
        if not frame then Build() end
        frame:Show()
        Refresh()
    elseif frame then
        frame:Hide()
    end
end

-- Whether this character is to be timed: for the box, or for the XP bar's XP an hour and time played.
local function Wanted()
    return (YR.Option("showSplits") or (YR.XPBarOn ~= nil and YR.XPBarOn() and YR.QoLOn())) and true or false
end

function YR:ShowSplits(on)
    YippRouteDB.showSplits = on
    if not (part and YR.partsReady) then return end         -- before the login: it comes on there
    -- at once, not a frame later: the box alone when the timing stays as it is (the XP bar keeps it
    -- on, say), else the part comes on or goes off
    if part.on == Wanted() then SyncBox() else YR.ApplyParts() end
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
-- is in, then listen again. Only while the part is on: with it off nobody would hear the answer, and
-- the chat windows would stay deaf to /played.
local muted = {}
local function AskPlayed()
    if not (part and part.on) then return end
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

-- The part comes on (and YR:StartSplits again, for another character in the tests or after a reset):
-- a character seen before carries on, any other starts a record now.
local function Begin()
    if not (part and part.on) then return end
    ImportLogs()
    local name = UnitFullName("player")
    local ok, guid = pcall(Guid)
    if not name or name == UNKNOWNOBJECT or name == "Unknown" or not ok then
        C_Timer.After(2, Begin)
        return
    end
    key = guid
    rec = DB().runs[key]
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    if not rec then
        rec = { name = YR.CharKey(), class = class, race = race, elapsed = 0, xp = 0, levels = {} }
        DB().runs[key] = rec
    end
    rec.class, rec.race = rec.class or class, rec.race or race      -- runs from before races were kept
    synced = false
    AskPlayed()
    wipe(rate)
    lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    last = GetTime()
    SyncBox()
end

-- The part goes off: the box away, the chat windows hear /played again, and the character is let go
-- (its record stays saved; the server's /played sets the clock right when it is timed again).
local function End()
    Unmute()
    if frame then frame:Hide() end
    key, rec, last, synced = nil, nil, nil, false
    wipe(rate)
end

-- A setting changed and the part stays on: the box may have been turned on or off.
local function Again()
    if YR.Option("showSplits") ~= (frame ~= nil and frame:IsShown()) then SyncBox() end
end

local function OnEvent(_, event, level, atLevel)
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
        stale = true                         -- the box's XP line: drawn at the clock's next tick
        return
    end
    if rec and not rec.stopped then
        rec.levels[level] = rec.elapsed
        C_Timer.After(1, AskPlayed)          -- and check our count against the server's
        -- (the time at each level was said in chat as well: the splits on screen have it - the owner, 2026-10-21)
    end
    Refresh()
end

--- Called once as Headstart loads: says what the splits need. Nothing is made or asked until the
--- part comes on at the login - and never, for a character that has neither the box nor the XP bar.
function YR:StartSplits()
    if not part then
        part = YR.Part(Wanted, { "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "TIME_PLAYED_MSG" }, OnEvent,
            { start = Begin, stop = End, again = Again, tick = Tick, every = TICK })
    elseif part.on then
        Begin()
    end
end

-- Stop run: the clock and the levels stop here, and the run log ends (until Resume). A stopped run
-- still counts as a run to beat unless the player says it shouldn't (noBest: a missed quest, say).
-- These work on the character's saved record with the splits off too (Mine): the This run page stops
-- and resumes a run whether or not its time is on screen.
function YR:StopRun()
    local r = Mine()
    if r and not r.stopped then r.stopped = time() end
    if YR.StopLog then YR:StopLog() end
    Refresh()
end

function YR:ResumeRun()
    local r = Mine()
    if r and r.stopped then
        -- resuming: the server's next answer leaves out the time the run was stopped (asked now while
        -- the character is timed, else when it next is)
        r.stopped, r.resuming = nil, true
        last = GetTime()
        AskPlayed()
    end
    if YR.ResumeLog then YR:ResumeLog() end
    Refresh()
end

function YR:RunStopped()
    local r = Mine()
    if r then return r.stopped ~= nil end
    return YR.LogStopped ~= nil and YR.LogStopped() or false       -- never timed: the log knows
end
function YR:RunCounts()
    local r = Mine()
    return not (r and r.noBest)
end
function YR:SetRunCounts(on)
    local r = Mine()
    if r then r.noBest = not on or nil end
    Refresh()
end

function YR:ResetSplits()
    local ok, guid = pcall(Guid)
    local db = YippRouteDB.splits
    if ok and db and db.runs then db.runs[guid] = nil end
    rec = nil
    YR.Print("splits for this character cleared.")
    YR:StartSplits()
end
