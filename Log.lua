-- The run log: what the route model can't know from data. Per character, in YippRouteDB.runs:
--   ev     every quest accepted, objective completed, turned in (with the XP and money actually
--          received), level up and death - each with time, level, XP and position
--   track  a position sample every 5 seconds, for real walking times over real terrain
local _, YR = ...

local SAMPLE = 5
local run, ticker
local complete = {}      -- questID -> true once its objectives were done (to log that moment once)

local function Add(kind, questID, extra)
    local map, x, y = YR.Position()
    local e = { time(), kind, questID or 0, UnitLevel("player"), UnitXP("player"), map or 0, x or 0, y or 0 }
    if extra then for k, v in pairs(extra) do e[k] = v end end
    run.ev[#run.ev + 1] = e
end

local function Sample()
    local map, x, y = YR.Position()
    if map then run.track[#run.track + 1] = { time(), map, x, y, UnitLevel("player"), UnitXP("player") } end
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

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, a, b, c)
    if event == "QUEST_ACCEPTED" then
        Add("accept", a, { npc = Npc(), title = C_QuestLog.GetTitleForQuestID(a) })
    elseif event == "QUEST_TURNED_IN" then
        complete[a] = nil
        Add("turnin", a, { xp = b, money = c, npc = Npc() })
    elseif event == "QUEST_REMOVED" then
        complete[a] = nil
    elseif event == "QUEST_LOG_UPDATE" then
        ScanCompletions()
    elseif event == "PLAYER_LEVEL_UP" then
        Add("level", nil, { to = a })
    elseif event == "PLAYER_DEAD" then
        Add("death")
    end
end)

function YR:StartLog()
    if not YippRouteDB.logging then return end
    local key = YR.CharKey()
    YippRouteDB.runs[key] = YippRouteDB.runs[key] or { started = time(), ev = {}, track = {} }
    run = YippRouteDB.runs[key]
    for _, e in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE",
                         "PLAYER_LEVEL_UP", "PLAYER_DEAD" }) do
        events:RegisterEvent(e)
    end
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
