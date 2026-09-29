-- The run log: what the route model can't know from data. Per character, in YippRouteDB.runs:
--   ev     each with time, level, XP and position:
--            accept / complete / turnin (with the XP and money received)    a quest
--            level, death, release (to the Spirit Healer as a ghost), alive (back in the body)
--            kill (XP from anything but a quest), fight / peace (combat starts / ends)
--            step (RestedXP's current guide and step), hearth, zone, vendor / trainer / flight
--   track  a position sample every 2 seconds: { time, map, x, y, level, XP, flags }
--          flags: 1 in combat, 2 dead or a ghost, 4 casting or channelling (eating, crafting, hearth)
local _, YR = ...

local SAMPLE = 2
local HEARTHSTONE = 8690
local run, ticker
local complete = {}      -- questID -> true once its objectives were done (to log that moment once)
local lastXP, lastMax, lastLevel, turnedInAt
local lastGuide, lastStep

local function Add(kind, questID, extra)
    local map, x, y = YR.Position()
    local e = { time(), kind, questID or 0, UnitLevel("player"), UnitXP("player"), map or 0, x or 0, y or 0 }
    if extra then for k, v in pairs(extra) do e[k] = v end end
    run.ev[#run.ev + 1] = e
end

-- RestedXP's guide and step: logged when it changes, so a run can be timed step by step.
local function WatchStep()
    local rxp = RXP
    local guide = type(rxp) == "table" and rxp.currentGuide
    local step = type(RXPCData) == "table" and RXPCData.currentStep
    if type(guide) ~= "table" or not step then return end
    local name = guide.name or guide.displayname
    if name ~= lastGuide or step ~= lastStep then
        lastGuide, lastStep = name, step
        Add("step", nil, { guide = name, step = step })
    end
end

local function Flags()
    local f = 0
    if UnitAffectingCombat("player") then f = f + 1 end
    if UnitIsDeadOrGhost("player") then f = f + 2 end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then f = f + 4 end
    return f
end

local function Sample()
    local map, x, y = YR.Position()
    if map then
        run.track[#run.track + 1] = { time(), map, x, y, UnitLevel("player"), UnitXP("player"), Flags() }
    end
    WatchStep()
end

-- The NPC you are talking to while a quest window is open: the quest giver or the turn-in.
local function Npc()
    local ok, name = pcall(UnitName, "npc")
    return ok and name or nil
end

-- The first pass after login only records what is already complete: those were finished in an
-- earlier session, and logging them "now" would make the objective look instant.
local primed = false
local function ScanCompletions()
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        local id = info and not info.isHeader and info.questID
        if id and not complete[id] and C_QuestLog.IsComplete(id) then
            complete[id] = true
            if primed then Add("complete", id) end
        end
    end
    primed = true
end

-- XP that didn't come from a quest turn-in is a kill (or exploring, rarely). A level-up in between
-- adds what was left of the old level.
local function XPChanged()
    local xp, level = UnitXP("player"), UnitLevel("player")
    if lastXP then
        local gained = level > lastLevel and (lastMax - lastXP + xp) or (xp - lastXP)
        if gained > 0 and turnedInAt ~= time() then Add("kill", nil, { xp = gained }) end
    end
    lastXP, lastMax, lastLevel = xp, UnitXPMax("player"), level
end

local NPC_WINDOWS = { MERCHANT_SHOW = "vendor", TRAINER_SHOW = "trainer", TAXIMAP_OPENED = "flight" }

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, a, b, c)
    if event == "QUEST_ACCEPTED" then
        Add("accept", a, { npc = Npc(), title = C_QuestLog.GetTitleForQuestID(a) })
    elseif event == "QUEST_TURNED_IN" then
        complete[a] = nil
        turnedInAt = time()
        Add("turnin", a, { xp = b, money = c, npc = Npc() })
    elseif event == "QUEST_REMOVED" then
        complete[a] = nil
    elseif event == "QUEST_LOG_UPDATE" then
        ScanCompletions()
    elseif event == "PLAYER_XP_UPDATE" then
        XPChanged()
    elseif event == "PLAYER_LEVEL_UP" then
        Add("level", nil, { to = a })
    elseif event == "PLAYER_DEAD" then
        Add("death")
    elseif event == "PLAYER_ALIVE" then
        if UnitIsGhost("player") then Add("release") end
    elseif event == "PLAYER_UNGHOST" then
        Add("alive")
    elseif event == "PLAYER_REGEN_DISABLED" then
        Add("fight")
    elseif event == "PLAYER_REGEN_ENABLED" then
        Add("peace")
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if c == HEARTHSTONE then Add("hearth") end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        Add("zone", nil, { zone = GetZoneText() })
    elseif NPC_WINDOWS[event] then
        Add(NPC_WINDOWS[event], nil, { npc = Npc() })
    end
end)

local EVENTS = { "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_XP_UPDATE",
    "PLAYER_LEVEL_UP", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA", "MERCHANT_SHOW", "TRAINER_SHOW", "TAXIMAP_OPENED" }

function YR:StartLog()
    if not YippRouteDB.logging then return end
    -- a brand-new character is "Unknown" for its first moments: wait for the real name, or every new
    -- character's run lands under the same key
    local name = UnitFullName("player")
    if not name or name == UNKNOWNOBJECT or name == "Unknown" then
        C_Timer.After(2, function() YR:StartLog() end)
        return
    end
    local key = YR.CharKey()
    YippRouteDB.runs[key] = YippRouteDB.runs[key] or { started = time(), ev = {}, track = {} }
    run = YippRouteDB.runs[key]
    for _, e in ipairs(EVENTS) do events:RegisterEvent(e) end
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    ticker = ticker or C_Timer.NewTicker(SAMPLE, Sample)
end

function YR:SetLogging(on)
    YippRouteDB.logging = on
    if on then
        YR:StartLog()
    else
        events:UnregisterAllEvents()
        if ticker then ticker:Cancel() ticker = nil end
    end
    YR.Print("logging " .. (on and "on" or "off") .. ".")
end

function YR:LogStatus()
    local r = YippRouteDB.runs[YR.CharKey()]
    YR.Print(("logging %s; this character: %d events, %d position samples."):format(
        YippRouteDB.logging and "on" or "off", r and #r.ev or 0, r and #r.track or 0))
end
