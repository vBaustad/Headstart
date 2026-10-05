-- Camping 101 (Dun Morogh, Warriors, Paladins and Rogues): the route has you mine on the way and make
-- the Blacksmithing skill-ups at the Kharanos forge, but it can't know when your bags are ready, and
-- on autopilot the forge stop goes by. So one line in chat and on screen says it when it's true:
--   * Blacksmithing: you're on Camping 101: Blacksmithing below 20 and carry the ore (or bars) and the
--     Rough Stone it takes from your skill to 20: Copper Rods to 10 (1 bar), Rough Weightstones to 15
--     (1 stone), Copper Bracers to 20 (2 bars); orange all the way on Forever, a point a craft. Where:
--     the forge and anvil by Tognus Flintfire in Kharanos. Not trained yet: train it from him first.
--   * Mining: Camping 101: Mining is complete: hand it in to Yarr Hammerstone in Kharanos.
-- Said once when it becomes true, and again when you come into Kharanos with it still to do - at most
-- every two minutes. Once said it stays said for the session: the quest log answers "not complete" for
-- a moment during its own updates, and forgetting on that said it again at every loot.
-- Thelsamar too (the user, 2026-10-02: Loch Modan is a crafting stop): its forge and anvil by the inn
-- do for the crafting; the hand-ins stay in Kharanos, so there only the Blacksmithing line, saying so.
-- Account option campReminder (Settings, Route).
local _, YR = ...

local BS_QUEST, MINING_QUEST = 96044, 96046
local ORE, BAR, STONE = 2770, 2840, 2835

local function Skill(name)
    if not GetNumSkillLines then return nil end
    for i = 1, GetNumSkillLines() do
        local n, header, _, rank = GetSkillLineInfo(i)
        if not header and n == name then return rank end
    end
    return nil
end

local function Count(item)
    return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(item)) or 0
end

-- What it takes from skill s to 20: (bars, stones), each craft a point (orange on Forever).
function YR.CampingNeed(s)
    s = s or 1
    local rods = math.max(0, 10 - s)
    local stones = math.max(0, 15 - math.max(s, 10))
    local bracers = math.max(0, 20 - math.max(s, 15))
    return rods + 2 * bracers, stones
end

local function OnQuest(q) return C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(q) end
local function Complete(q) return C_QuestLog.IsComplete and C_QuestLog.IsComplete(q) end

local function Say(msg)
    YR.Print(msg)
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        RaidNotice_AddMessage(RaidWarningFrame, "Headstart: " .. msg, ChatTypeInfo["RAID_WARNING"])
    end
end

-- The things to say now: { key, message }.
function YR.CampingNow()
    local out = {}
    if OnQuest(BS_QUEST) and not Complete(BS_QUEST) then
        local s = Skill("Blacksmithing")
        if not s or s < 20 then
            local bars, stones = YR.CampingNeed(s or 1)
            if Count(ORE) + Count(BAR) >= bars and Count(STONE) >= stones then
                if s and GetSubZoneText and GetSubZoneText() == "Thelsamar" then
                    out[#out + 1] = { "bs", "you have the ore and stone for Blacksmithing 20 (Camping 101). At the forge and"
                        .. " anvil by the inn: smelt your ore, then Copper Rods to 10, Rough Weightstones to 15, Copper Bracers"
                        .. " to 20. The hand-in is Tognus Flintfire in Kharanos." }
                else
                    out[#out + 1] = { "bs", ("you have the ore and stone for Blacksmithing 20 (Camping 101). At the forge by"
                        .. " Tognus Flintfire in Kharanos: %ssmelt your ore, then Copper Rods to 10, Rough Weightstones to 15,"
                        .. " Copper Bracers to 20."):format(s and "" or "train Blacksmithing from him, ") }
                end
            end
        end
    end
    if OnQuest(MINING_QUEST) and Complete(MINING_QUEST) and not (GetSubZoneText and GetSubZoneText() == "Thelsamar") then
        out[#out + 1] = { "mining", "Camping 101: Mining is done: hand it in to Yarr Hammerstone in Kharanos (downstairs in Steelgrill's Depot)." }
    end
    return out
end

local AGAIN = 120          -- seconds before coming into Kharanos says it again
local told = {}            -- key -> GetTime() it was last said, this session
local function Check(arriving)
    if (YR.RoutesOn and not YR.RoutesOn()) or not YR.Option("campReminder") then return end
    for _, e in ipairs(YR.CampingNow()) do
        local last = told[e[1]]
        if not last or (arriving and GetTime() - last >= AGAIN) then
            Say(e[2])
            told[e[1]] = GetTime()
        end
    end
end
YR.CampingCheck = Check   -- for tests

-- Bags, the quest log and skills fire all the time: listened to only while this character is on one
-- of the two quests with the reminder on (looked at again on taking or losing a quest, a loading screen
-- and a new subzone), so every other character pays nothing for it.
local NOISY = { "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "SKILL_LINES_CHANGED" }
local pending, armed = false, false
local f = CreateFrame("Frame")
local function Arm()
    local want = (not YR.RoutesOn or YR.RoutesOn()) and YR.Option("campReminder")
        and (OnQuest(BS_QUEST) or OnQuest(MINING_QUEST)) or false
    if want == armed then return end
    armed = want
    for _, e in ipairs(NOISY) do
        if want then f:RegisterEvent(e) else f:UnregisterEvent(e) end
    end
end
f:RegisterEvent("ZONE_CHANGED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("QUEST_ACCEPTED")
f:RegisterEvent("QUEST_REMOVED")
f:SetScript("OnEvent", function(_, event)
    if event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED" then
        Arm()
        -- the quest log isn't there yet in the first moments after logging in
        if event == "PLAYER_ENTERING_WORLD" then C_Timer.After(5, Arm) end
    end
    if event == "ZONE_CHANGED" then
        local sub = GetSubZoneText and GetSubZoneText()
        if sub == "Kharanos" or sub == "Thelsamar" then Check(true) end
        return
    end
    if not armed then return end
    -- bags and the quest log fire in bursts: look once they settle
    if pending then return end
    pending = true
    C_Timer.After(1, function() pending = false Check(false) end)
end)
