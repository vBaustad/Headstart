-- Quest rewards with a choice, picked and turned in without stopping: a two-handed weapon first, then
-- mail armour, then water. Only up to MAX_LEVEL, where the choice barely matters and speed does.
-- Hold Shift when the reward window opens to pick yourself. Nothing is chosen when none of them fits.
local _, YR = ...

local MAX_LEVEL = 10
local MAIL = 3              -- armour subclass
local ARMOR, WEAPON, CONSUMABLE = 4, 2, 0
local FOOD_AND_DRINK = 5    -- consumable subclass

-- Higher is better; nil means "not one we pick".
local function Score(itemID)
    local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if classID == WEAPON and equipLoc == "INVTYPE_2HWEAPON" then return 3 end
    if classID == ARMOR and subclassID == MAIL then return 2 end
    if classID == CONSUMABLE and subclassID == FOOD_AND_DRINK then
        local spell = C_Item.GetItemSpell(itemID)
        if spell == nil then return false end   -- not cached yet: ask again shortly
        if spell == "Drink" then return 1 end
    end
end

local function Choose(tries)
    local n = GetNumQuestChoices()
    if n < 2 or IsShiftKeyDown() or UnitLevel("player") > MAX_LEVEL then return end
    local best, bestScore, bestValue = nil, 0, -1
    for i = 1, n do
        local _, _, _, _, isUsable, itemID = GetQuestItemInfo("choice", i)
        if not itemID then return tries > 0 and C_Timer.After(0.2, function() Choose(tries - 1) end) end
        local score = Score(itemID)
        if score == false then return tries > 0 and C_Timer.After(0.2, function() Choose(tries - 1) end) end
        -- the same kind twice (two mail pieces): the one that sells for more is usually the better one
        local value = select(11, C_Item.GetItemInfo(itemID)) or 0
        if score and isUsable and (score > bestScore or (score == bestScore and value > bestValue)) then
            best, bestScore, bestValue = i, score, value
        end
    end
    if best then
        YR.Print("reward: " .. (GetQuestItemLink("choice", best) or "?"))
        GetQuestReward(best)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("QUEST_COMPLETE")
f:SetScript("OnEvent", function() Choose(10) end)
