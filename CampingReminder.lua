-- Camping 101 (Dun Morogh, Warriors, Paladins and Rogues): the route has you mine on the way and make
-- the Blacksmithing skill-ups at the Kharanos forge, but it can't know when your bags are ready, and
-- on autopilot the forge stop goes by. So one line in chat and on screen says it when it's true:
--   * Blacksmithing: you're on Camping 101: Blacksmithing below 20 and carry the ore (or bars) and the
--     Rough Stone it takes from your skill to 20: Copper Rods to 10 (1 bar), Rough Weightstones to 15
--     (1 stone), Copper Bracers to 20 (2 bars); orange all the way on Forever, a point a craft. Where:
--     the forge and anvil by Tognus Flintfire in Kharanos. Not trained yet: train it from him first.
--   * Mining: Camping 101: Mining is complete: hand it in to Yarr Hammerstone in Kharanos.
-- Said once when it becomes true, and again each time you come into Kharanos with it still to do.
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
                out[#out + 1] = { "bs", ("you have the ore and stone for Blacksmithing 20 (Camping 101). At the forge by"
                    .. " Tognus Flintfire in Kharanos: %ssmelt your ore, then Copper Rods to 10, Rough Weightstones to 15,"
                    .. " Copper Bracers to 20."):format(s and "" or "train Blacksmithing from him, ") }
            end
        end
    end
    if OnQuest(MINING_QUEST) and Complete(MINING_QUEST) then
        out[#out + 1] = { "mining", "Camping 101: Mining is done: hand it in to Yarr Hammerstone in Kharanos (downstairs in Steelgrill's Depot)." }
    end
    return out
end

local told = {}            -- key -> true until it stops being true
local function Check(arriving)
    if not YR.Option("campReminder") then return end
    local now = {}
    for _, e in ipairs(YR.CampingNow()) do
        now[e[1]] = true
        if not told[e[1]] or arriving then Say(e[2]) end
        told[e[1]] = true
    end
    for k in pairs(told) do if not now[k] then told[k] = nil end end
end

local pending = false
local f = CreateFrame("Frame")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("QUEST_LOG_UPDATE")
f:RegisterEvent("SKILL_LINES_CHANGED")
f:RegisterEvent("ZONE_CHANGED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event)
    if event == "ZONE_CHANGED" then
        if GetSubZoneText and GetSubZoneText() == "Kharanos" then Check(true) end
        return
    end
    -- bags and the quest log fire in bursts: look once they settle
    if pending then return end
    pending = true
    C_Timer.After(1, function() pending = false Check(false) end)
end)
