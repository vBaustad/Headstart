-- Level pace: one small box under RestedXP's guide that says what is happening, not what might.
--   Level 8: 1.3k XP to go, 12 min at your pace          the level line
--   Grinding here: 95 XP a minute                         your own kills near here
--   Next step needs level 10: 480 XP short, about 8 kills here     a level gate ahead
--   Harpies: 14 min for 440 XP so far. Grinding here pays more: skip it?    the step watchdog
--
-- Why (the route session, 2026-10-18): in the owner's logged runs the expensive mistakes were single
-- route steps that dragged on and paid little - 26 minutes and two deaths on Bloodfeather harpies at
-- level 8 for one 440 XP quest. A forecast of quest times would be guesswork; this watches what is
-- actually happening and says so once.
--
-- What is counted, and over which clock:
--   * Pace: XP gained over the last 10 minutes of play, not counting time away (AFK) or dead. Every five
--     seconds of that clock a sample (seconds, XP since the part came on) is kept; the time to level is
--     the XP still missing at that rate. The splits' XP/hr (Splits.lua) counts the server's /played and
--     so goes on through AFK and deaths: this one stops for both.
--   * Grinding here: the last 10 of your kills within 200 yards of where you stand (or in this subzone),
--     from the last 10 minutes: their XP (after the first) over the time from the first to the last.
--     Fewer than three: no rate. The kill line is the game's own sentence, read as Journey.lua reads it.
--     This clock leaves out time away but not time dead: a death while grinding is part of what
--     grinding costs, and a step is timed the same way.
--   * The step watchdog: a RestedXP step with a .complete line for a quest in your log is timed from
--     the moment it became the current step. What it pays is the quests' reward XP (the game's
--     GetQuestLogRewardXP) and the kill XP you got meanwhile. Once it has run five minutes and pays
--     under half of what grinding here would have paid in that time - or you died twice on it - one
--     line says so. Once per step; it never acts and never pops anything up. When the guide window is
--     not shown, the line goes to chat instead.
--     What it can and can't see: a step spent killing for its quest at a steady clip pays its kills
--     plus the reward, and grinding the same mobs would pay only the kills - so that step is never
--     called slow, rightly. What trips it is time that wasn't killing: searching, waiting on spawns,
--     running back, dying.
--   * A level gate: the next .xp line within 20 steps (not one that only skips its step: that is no
--     gate). How far short you are is worked out for this level and the next from the game, further
--     only with what Journey.lua wrote down of what those levels take; kills from what a kill here
--     paid on average.
--
-- A part (Core.lua): off until turned on (paceWatch, Levelling's Settings), and one of the routes' own
-- (with the routes off it doesn't run). Off: no frame, no event, no ticker, nothing kept.
local _, YR = ...

local WINDOW = 600          -- pace: the last 10 minutes of play
local SAMPLE = 5
local KILLS = 10            -- grinding here: the last 10 kills ...
local NEAR = 200            -- ... within 200 yards (or in this subzone) ...
local RECENT = 600          -- ... from the last 10 minutes
local KEPT = 40             -- kills remembered at most
local SLOW_AFTER = 300      -- a step is judged once it has run 5 minutes
local SLOW_SHARE = 0.5      -- and called slow under half what grinding here pays
local DEATHS = 2
local AHEAD = 20            -- steps looked through for a level gate
local FONT = "Fonts\\FRIZQT__.TTF"
local BLUE, GREY, WHITE, WARN = "|cff66ccff", "|cff999999", "|cffffffff", "|cffffb040"

local part, frame
local last                          -- GetTime() at the last tick
local played, active = 0, 0         -- seconds: not away; not away and not dead
local xpTotal, lastXP, lastMax, lastLevel = 0, nil, nil, nil
local samples, spare = {}, nil      -- { active seconds, xpTotal }, oldest first
local kills = {}                    -- { t (played), xp, name, x, y, where, sub }, oldest first
local killXP, deaths = 0, 0         -- since the part came on
local step                          -- the RestedXP step being watched (NewStep)
local anchoredTo                    -- what the box hangs from now
local shown = {}                    -- the text each line shows now
local KILL, KILL_ORDER

local function Open(v) return YR.Open(v) end

local function Short(n)
    return n >= 1000 and ("%.1fk"):format(n / 1000) or tostring(math.floor(n + 0.5))
end

-- Where you are, in yards, and the subzone's name. No position in a dungeon (and none asked for).
local function Here()
    local sub = GetSubZoneText and Open(GetSubZoneText()) or nil
    if type(sub) ~= "string" then sub = "" end
    if IsInInstance() then return nil, nil, nil, sub end
    local ok, y, x, _, where = pcall(UnitPosition, "player")
    x, y, where = ok and Open(x), ok and Open(y), ok and Open(where)
    if type(x) ~= "number" or type(y) ~= "number" then return nil, nil, nil, sub end
    return x, y, where, sub
end

-- The kills that count as "here": newest first, the last KILLS of the last RECENT seconds.
local near = {}
local function KillsHere()
    wipe(near)
    local x, y, where, sub = Here()
    for i = #kills, 1, -1 do
        local k = kills[i]
        if played - k.t > RECENT or #near >= KILLS then break end
        local close = x and k.x and k.where == where and (k.x - x) ^ 2 + (k.y - y) ^ 2 <= NEAR * NEAR
        if close or (sub ~= "" and k.sub == sub) then near[#near + 1] = k end
    end
    return near
end

--- Grinding here: XP a second from your own kills near here (nil with fewer than three, or under half
--- a minute between the first and the last), and what one of them paid on average.
local function GrindRate()
    local list = KillsHere()
    if #list == 0 then return nil, nil end
    local sum = 0
    for _, k in ipairs(list) do sum = sum + k.xp end
    local avg = sum / #list
    local span = list[1].t - list[#list].t
    if #list < 3 or span < 30 then return nil, avg end
    return (sum - list[#list].xp) / span, avg
end
YR.PaceGrind = GrindRate        -- for the tests

--- Pace: XP a second over the last 10 minutes of play, away and dead left out (nil until a minute).
local function Pace()
    local a, b = samples[1], samples[#samples]
    if not (a and b) or b[1] - a[1] < 60 then return nil end
    return (b[2] - a[2]) / (b[1] - a[1])
end
YR.PacePace = Pace

-- ---------------------------------------------------------------------------
-- The step: RestedXP's current guide and step number (RXP.currentGuide, RXPCData.currentStep), its
-- lines its elements - each with a tag (the command: "complete", "xp"), a questId, completed.
-- ---------------------------------------------------------------------------
local function InLog(q)
    local log = C_QuestLog
    return log and log.GetLogIndexForQuestID and log.GetLogIndexForQuestID(q) ~= nil
end

local function Elements(s)
    return type(s) == "table" and type(s.elements) == "table" and s.elements or nil
end

-- The next level gate from step n on: { level, xp, at } (xp as the .xp line has it: 0 the level, below 0
-- that far from it, 1 and up that much into it, under 1 that share of it), or false.
local function FindGate(guide, n)
    local steps = type(guide.steps) == "table" and guide.steps
    if not steps then return false end
    for i = n, n + AHEAD do
        for _, e in ipairs(Elements(steps[i]) or {}) do
            if type(e) == "table" and e.tag == "xp" and not e.completed and not e.reverseLogic and not e.skipstep
                    and tonumber(e.level) then
                return { level = tonumber(e.level), xp = tonumber(e.xp) or 0, at = i - n }
            end
        end
    end
    return false
end

local function NewStep(guide, n, key)
    local s = { key = key, at = played, kxp = killXP, deaths = deaths, quests = {}, mobs = {}, told = nil }
    local seen = {}
    for _, e in ipairs(Elements(type(guide.steps) == "table" and guide.steps[n]) or {}) do
        local q = type(e) == "table" and e.tag == "complete" and not e.completed and tonumber(e.questId)
        if q and q > 0 and not seen[q] and InLog(q) then
            seen[q] = true
            s.quests[#s.quests + 1] = q
        end
    end
    s.gate = FindGate(guide, n)
    return s
end

-- What the step's quests pay when handed in (asked each time: the game may know it only later).
local function Reward(s)
    local sum = 0
    for _, q in ipairs(s.quests) do
        local ok, xp = pcall(GetQuestLogRewardXP, q)
        xp = ok and Open(xp)
        if type(xp) == "number" and xp > 0 then sum = sum + xp end
    end
    return sum
end

-- What the step is called in the line: the mob you killed most on it, else its first quest's title.
local function StepName(s)
    local best, most = nil, 0
    for name, n in pairs(s.mobs) do
        if n > most or (n == most and best and name < best) then best, most = name, n end
    end
    if best then return best end
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and Open(C_QuestLog.GetTitleForQuestID(s.quests[1]))
    return type(title) == "string" and title ~= "" and title or "This step"
end

local function GuideShown()
    local f = type(RXP) == "table" and RXP.RXPFrame
    return type(f) == "table" and f.IsShown and f:IsShown() and f or nil
end

-- The watchdog's look at the step: says it once, when it has run long and paid little or cost two deaths.
local function Judge(s)
    if s.told or #s.quests == 0 then return end
    local t = played - s.at
    local pays = Reward(s) + (killXP - s.kxp)
    local died = deaths - s.deaths
    local mins = math.max(1, math.floor(t / 60 + 0.5))
    local text
    if died >= DEATHS then
        text = ("%s: %d deaths and %d min for %s XP so far. Grinding here may pay more: skip it?"):format(
            StepName(s), died, mins, Short(pays))
    elseif t >= SLOW_AFTER then
        local rate = GrindRate()
        if rate and pays < SLOW_SHARE * rate * t then
            text = ("%s: %d min for %s XP so far. Grinding here pays more: skip it?"):format(StepName(s), mins, Short(pays))
        end
    end
    if not text then return end
    s.told = text
    if not GuideShown() then YR.Print(text) end
end

local function WatchStep()
    local rxp = RXP
    local guide = type(rxp) == "table" and rxp.currentGuide
    local n = type(RXPCData) == "table" and tonumber(RXPCData.currentStep)
    if type(guide) ~= "table" or not n then
        step = nil
        return
    end
    local key = tostring(guide.name or guide.displayname) .. "#" .. n
    if not step or step.key ~= key then step = NewStep(guide, n, key) end
    Judge(step)
end

-- XP still missing to reach a gate, or nil where it can't be known (a level further on whose size
-- nobody has seen). 0: already there.
local function Need(level)
    if level == UnitLevel("player") then return UnitXPMax("player") end
    local j = YR.JourneyData and YR.JourneyData()
    local n = j and type(j.need) == "table" and j.need[level]
    return type(n) == "number" and n > 0 and n or nil
end

local function GateShort(gate)
    local level, cur = UnitLevel("player"), UnitXP("player")
    local L, x = gate.level, gate.xp
    local atLevel, into = L, 0                          -- the gate as "this far into that level"
    if x < 0 then
        atLevel = L - 1
        local size = Need(atLevel)
        if not size then return nil end
        into = size + x
    elseif x >= 1 then
        into = x
    elseif x > 0 then
        local size = Need(L)
        if not size then return nil end
        into = math.floor(size * x)
    end
    if atLevel < level or (atLevel == level and cur >= into) then return 0 end
    if atLevel == level then return into - cur end
    local short = UnitXPMax("player") - cur
    for l = level + 1, atLevel - 1 do
        local size = Need(l)
        if not size then return nil end
        short = short + size
    end
    return short + into
end
YR.PaceGateShort = GateShort

-- ---------------------------------------------------------------------------
-- The box
-- ---------------------------------------------------------------------------
local function Lines()
    local level, xp, max = UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
    local out1, out2, out3, out4 = "", "", "", ""
    local grind, avg = GrindRate()
    if type(max) == "number" and max > 0 and level < (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60) then
        local left = max - xp
        local pace = Pace()
        out1 = BLUE .. ("Level %d:|r "):format(level) .. WHITE .. Short(left) .. "|r XP to go"
            .. (pace and pace > 0 and (", " .. WHITE .. ("%d min|r at your pace"):format(math.ceil(left / pace / 60))) or "")
    end
    if grind and grind > 0 then
        out2 = BLUE .. "Grinding here:|r " .. WHITE .. Short(grind * 60) .. "|r XP a minute"
    end
    local gate = step and step.gate
    local short = gate and GateShort(gate)
    if short and short > 0 then
        out3 = GREY .. (gate.at == 0 and "This step" or "Next step") .. (" needs level %d:|r "):format(gate.level)
            .. WHITE .. Short(short) .. "|r XP short"
            .. (avg and avg > 0 and (", about " .. WHITE .. math.ceil(short / avg) .. "|r kills here") or "")
    end
    if step and step.told then out4 = WARN .. step.told .. "|r" end
    return out1, out2, out3, out4
end
YR.PaceLines = Lines

local function Anchor()
    local under = GuideShown() or false
    if under == anchoredTo then return end
    anchoredTo = under
    frame:ClearAllPoints()
    if under then
        frame:SetPoint("TOPLEFT", under, "BOTTOMLEFT", 4, -4)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -90)
    end
end

-- Once a second: a line's text is set only when it changed, and the lines are laid out again only
-- when one came or went.
local texts = {}
local function Draw()
    if not frame then return end
    Anchor()
    texts[1], texts[2], texts[3], texts[4] = Lines()
    local moved = false
    for i = 1, 4 do
        local text = texts[i]
        if shown[i] ~= text then
            if (shown[i] or "") == "" or text == "" then moved = true end
            shown[i] = text
            frame.lines[i]:SetText(text)
        end
    end
    if not moved then return end
    local y = 0
    for i = 1, 4 do
        local fs = frame.lines[i]
        fs:SetShown(texts[i] ~= "")
        if texts[i] ~= "" then
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 0, -y)
            y = y + 15
        end
    end
    frame:SetHeight(math.max(1, y))
end

local function Build()
    frame = CreateFrame("Frame", "HeadstartPaceFrame", UIParent)
    frame:SetFrameStrata("BACKGROUND")      -- like the guide window: everything else opens over it
    frame:SetSize(340, 15)
    frame:EnableMouse(false)
    frame.lines = {}
    for i = 1, 4 do
        local fs = frame:CreateFontString(nil, "OVERLAY")
        fs:SetFont(FONT, 12, "OUTLINE")
        fs:SetShadowOffset(1, -1)
        fs:SetJustifyH("LEFT")
        frame.lines[i] = fs
    end
end

-- ---------------------------------------------------------------------------
-- Counting
-- ---------------------------------------------------------------------------
local function Tick()
    local now = GetTime()
    local dt = now - (last or now)
    last = now
    if dt > 0 then
        if dt > 5 then dt = 1 end                   -- (a loading screen, a stall: not five seconds of anything)
        if not Open(UnitIsAFK("player")) then
            played = played + dt
            if not Open(UnitIsDeadOrGhost("player")) then active = active + dt end
        end
        local newest = samples[#samples]
        if not newest or active - newest[1] >= SAMPLE then
            local pair = spare or {}
            spare = nil
            pair[1], pair[2] = active, xpTotal
            samples[#samples + 1] = pair
            while samples[1] and active - samples[1][1] > WINDOW do spare = table.remove(samples, 1) end
        end
    end
    WatchStep()
    Draw()
end
YR.PaceTick = Tick

local function Killed(msg)
    msg = Open(msg)
    if type(msg) ~= "string" then return end
    if KILL == nil then
        -- the game's own sentence ("%s dies, you gain %d experience."), from its start (the longer ones,
        -- with a rested or a group bonus, begin the same)
        local fmt = _G.COMBATLOG_XPGAIN_FIRSTPERSON
        KILL = false
        if type(fmt) == "string" then
            local p, order = YR.SentencePattern(fmt, true)
            KILL, KILL_ORDER = "^" .. p, order
        end
    end
    local name, xp
    if KILL then name, xp = YR.SentenceMatch(msg, KILL, KILL_ORDER) else name, xp = msg:match("^(.+) dies, you gain (%d+)") end
    xp = tonumber(xp)
    if not (name and xp) then return end
    local x, y, where, sub = Here()
    kills[#kills + 1] = { t = played, xp = xp, name = name, x = x, y = y, where = where, sub = sub }
    if #kills > KEPT then table.remove(kills, 1) end
    killXP = killXP + xp
    if step then step.mobs[name] = (step.mobs[name] or 0) + 1 end
end

local function OnEvent(_, event, msg)
    if event == "PLAYER_XP_UPDATE" then
        -- XP since the part came on; a level-up in between adds what was left of the old level
        local xp, lvl = UnitXP("player"), UnitLevel("player")
        if lastXP then
            local gained = lvl > lastLevel and (lastMax - lastXP + xp) or (xp - lastXP)
            if gained > 0 then xpTotal = xpTotal + gained end
        end
        lastXP, lastMax, lastLevel = xp, UnitXPMax("player"), lvl
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        Killed(msg)
    elseif event == "PLAYER_DEAD" then
        deaths = deaths + 1
    end
end

local function Begin()
    played, active, xpTotal, killXP, deaths = 0, 0, 0, 0, 0
    wipe(samples)
    wipe(kills)
    wipe(shown)
    spare, step, anchoredTo = nil, nil, nil
    last = GetTime()
    lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if not frame then Build() end
    frame:Show()
    Tick()
end

local function End()
    if frame then frame:Hide() end
    wipe(samples)
    wipe(kills)
    step, anchoredTo, spare = nil, nil, nil
end

--- Called once as Headstart loads: says what the box needs. Nothing is made until it is turned on.
function YR.StartPace()
    if part then return end
    part = YR.Part(function() return YR.Option("paceWatch") end,
        { "PLAYER_XP_UPDATE", "CHAT_MSG_COMBAT_XP_GAIN", "PLAYER_DEAD" }, OnEvent,
        { start = Begin, stop = End, tick = Tick, every = 1 })
end
