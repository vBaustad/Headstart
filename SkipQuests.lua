-- Quests the route leaves out on purpose, dropped again when another addon (Leatrix Plus's quest
-- automation, say) takes one by itself. Taken that way, it's accepted the moment its window opens;
-- taken by hand, you've read it first, so a quest you accept yourself is kept. Dropped once a
-- session: take it again and it stays, whatever accepted it. Only with routes on.
local _, YR = ...

-- Which quests: the routes addon's list (the global HeadstartSkipQuests, { [questID] = name }, set
-- before Headstart loads). Headstart itself has none.
YR.SKIP_QUESTS = type(HeadstartSkipQuests) == "table" and HeadstartSkipQuests or {}

local AUTO = 1          -- seconds from the quest window opening to accepted: faster is an addon

local shown = {}        -- quest ID -> when its window opened
local dropped = {}      -- quest ID -> true once dropped this session
local frame = CreateFrame("Frame")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_ACCEPTED")
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    if not YR.RoutesOn() then return end
    if event == "QUEST_DETAIL" then
        local id = GetQuestID()
        if id and YR.SKIP_QUESTS[id] then shown[id] = GetTime() end
        return
    end
    local id = arg2 or arg1             -- (questID) on Mainline, (logIndex, questID) on Classic
    local at = shown[id]
    shown[id] = nil
    if not YR.SKIP_QUESTS[id] or dropped[id] or not at or GetTime() - at > AUTO then return end
    dropped[id] = true
    C_Timer.After(0, function()
        if not C_QuestLog.GetLogIndexForQuestID(id) then return end
        C_QuestLog.SetSelectedQuest(id)
        C_QuestLog.SetAbandonQuest()
        C_QuestLog.AbandonQuest()
        YR.Print("dropped " .. YR.SKIP_QUESTS[id] .. ", which another addon accepted: the route skips it. Want it after all? Take it again: Headstart leaves it then.")
    end)
end)
