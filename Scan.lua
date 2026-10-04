-- /yroute scan: ask the server about every quest ID in Data/QuestIDs.lua and keep what it answers.
-- RequestLoadQuestByID answers with QUEST_DATA_LOAD_RESULT; a few requests are kept in flight at a
-- time so the server isn't flooded. Results go to YippRouteDB.scan, which a /reload writes to disk.
local _, YR = ...

local IN_FLIGHT = 10
local TIMEOUT = 5          -- seconds before an unanswered request counts as "no answer"

local queue, pos, pending, ticker

local function Read(id)
    local r = { t = C_QuestLog.GetTitleForQuestID(id) }
    r.ql = C_QuestLog.GetQuestDifficultyLevel(id)
    local ok, xp, baseXP = pcall(GetQuestLogRewardXP, id)
    if ok then r.xp, r.bxp = xp, baseXP end
    local okm, money = pcall(GetQuestLogRewardMoney, id)
    if okm then r.m = money end
    local tag = C_QuestLog.GetQuestTagInfo(id)
    if tag and tag.tagName then r.tag = tag.tagName end
    local group = C_QuestLog.GetSuggestedGroupSize(id)
    if group and group > 0 then r.grp = group end
    local objectives = C_QuestLog.GetQuestObjectives(id)
    if objectives and #objectives > 0 then
        r.obj = {}
        for i, o in ipairs(objectives) do r.obj[i] = { o.text, o.type, o.numRequired } end
    end
    if C_QuestLog.IsQuestFlaggedCompleted(id) then r.done = true end
    return r
end

local function Finish()
    if ticker then ticker:Cancel() ticker = nil end
    local s = YippRouteDB.scan
    s.finished = time()
    local n, named = 0, 0
    for _, r in pairs(s.quests) do
        n = n + 1
        if r.t then named = named + 1 end
    end
    YR.Print(("scan done: %d answers, %d with a name. /reload to write them to disk."):format(n, named))
end

local function Tick()
    local now = GetTime()
    for id, asked in pairs(pending) do
        if now - asked > TIMEOUT then
            pending[id] = nil
            YippRouteDB.scan.noAnswer[id] = true
        end
    end
    local inFlight = 0
    for _ in pairs(pending) do inFlight = inFlight + 1 end
    while inFlight < IN_FLIGHT and pos <= #queue do
        local id = queue[pos]
        pos = pos + 1
        pending[id] = now
        inFlight = inFlight + 1
        C_QuestLog.RequestLoadQuestByID(id)
    end
    if pos % 500 < IN_FLIGHT and pos > 1 then
        YR.Print(("scanned %d of %d"):format(pos - 1, #queue))
    end
    if pos > #queue and inFlight == 0 then Finish() end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, _, id, success)
    if not (pending and pending[id]) then return end
    pending[id] = nil
    local s = YippRouteDB.scan
    if success then s.quests[id] = Read(id) else s.failed[id] = true end
end)

function YR:StartScan()
    if ticker then YR.Print("already scanning.") return end
    queue = {}
    for _, part in ipairs({ "route", "new", "rest" }) do
        for _, id in ipairs(YR.QUEST_IDS[part]) do queue[#queue + 1] = id end
    end
    pos, pending = 1, {}
    local _, class = UnitClass("player")
    local _, race = UnitRace("player")
    YippRouteDB.scan = {
        started = time(), build = select(2, GetBuildInfo()), char = YR.CharKey(),
        level = UnitLevel("player"), class = class, race = race,
        quests = {}, failed = {}, noAnswer = {},
    }
    events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
    ticker = C_Timer.NewTicker(0.1, Tick)
    YR.Print(("scanning %d quests (quest XP is as seen at level %d)."):format(#queue, UnitLevel("player")))
end

--- Delete the scan's results (they stay in the saved file until then). Not while one is running.
function YR.DeleteScan()
    if ticker or not YippRouteDB.scan then return false end
    YippRouteDB.scan = nil
    return true
end

function YR:StopScan()
    if not ticker then return end
    ticker:Cancel()
    ticker = nil
    YippRouteDB.scan.stopped = time()
    YR.Print(("scan stopped at %d of %d. /reload to write what we have."):format(pos - 1, #queue))
end

function YR:ScanStatus()
    local s = YippRouteDB.scan
    if not s then YR.Print("no scan yet.") return end
    local n = 0
    for _ in pairs(s.quests) do n = n + 1 end
    YR.Print(("last scan: %d answers, %s."):format(n, ticker and "still running" or date("%Y-%m-%d %H:%M", s.started)))
end
