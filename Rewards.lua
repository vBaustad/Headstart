-- Quest rewards with a choice, picked and turned in without stopping.
--
--   1. A quest you chose a reward for yourself before: the same reward again (it learns from you).
--   2. Otherwise the first kind of reward in your priority list that is on offer, e.g. two-handed
--      weapon, then mail, then water. Of two of the same kind, the one that sells for more.
--   3. Nothing in the list on offer: the most valuable reward, or leave it to you (a setting).
-- Only up to the level limit, and never while Shift is held - that is how you choose yourself, and
-- a choice made by hand is remembered for that quest.
--   YippRouteDB.rewardClasses[CLASS] = { on, maxLevel, order = { kind, ... }, off = { [kind] = true },
--       remember, fallback = "value" | "ask", chosen = { [questID] = { item, name, title } } }
local _, YR = ...

local WEAPON, ARMOR, CONSUMABLE, CONTAINER = 2, 4, 0, 1

-- Every kind the picker knows, in the order the settings list them.
YR.REWARD_KINDS = {
    { key = "twohand",  label = "Two-handed weapon" },
    { key = "onehand",  label = "One-handed weapon" },
    { key = "ranged",   label = "Ranged weapon" },
    { key = "shield",   label = "Shield" },
    { key = "plate",    label = "Plate armour" },
    { key = "mail",     label = "Mail armour" },
    { key = "leather",  label = "Leather armour" },
    { key = "cloth",    label = "Cloth armour" },
    { key = "cloak",    label = "Cloak" },
    { key = "jewelry",  label = "Ring, neck or trinket" },
    { key = "water",    label = "Water" },
    { key = "food",     label = "Food" },
    { key = "potion",   label = "Potion" },
    { key = "bag",      label = "Bag" },
}

-- A sensible start per class; everyone can reorder it in the settings.
local DEFAULT_ORDER = {
    PALADIN = { "twohand", "mail", "shield", "water", "food" },
    WARRIOR = { "twohand", "mail", "onehand", "shield", "food" },
    HUNTER  = { "ranged", "twohand", "leather", "mail", "food" },
    ROGUE   = { "onehand", "leather", "food" },
    DRUID   = { "leather", "twohand", "water", "food" },
    SHAMAN  = { "twohand", "leather", "mail", "shield", "water" },
    PRIEST  = { "cloth", "water", "food" },
    MAGE    = { "cloth", "water", "food" },
    WARLOCK = { "cloth", "water", "food" },
}

local function Copy(t)
    local c = {}
    for k, v in pairs(t or {}) do c[k] = type(v) == "table" and Copy(v) or v end
    return c
end

-- Per class: YippRouteDB.rewardClasses[CLASS] (plus .on: pick at all). From before that, one set for
-- all in YippRouteDB.rewards: left as it is, and copied into the first class that asks (the player's
-- own, at the first quest or on opening the settings), which is the class it was made on. Other
-- classes start from their own priority list and the same limits, and take over the choices you
-- made that weren't gear (a profession book is the same pick for everyone).
function YR:RewardSettings(class)
    if not class then
        local _, mine = UnitClass("player")
        class = mine or "WARRIOR"
    end
    YippRouteDB.rewardClasses = YippRouteDB.rewardClasses or {}
    local db = YippRouteDB.rewardClasses[class]
    if not db then
        local old = YippRouteDB.rewards
        if old and not YippRouteDB.rewardsTakenBy then
            db = Copy(old)
            YippRouteDB.rewardsTakenBy = class
        else
            local order = {}
            for _, k in ipairs(DEFAULT_ORDER[class] or DEFAULT_ORDER.WARRIOR) do order[#order + 1] = k end
            db = { maxLevel = old and old.maxLevel or 10, order = order, off = {},
                remember = not old or old.remember ~= false, fallback = old and old.fallback or "value", chosen = {} }
            for quest, pick in pairs(old and old.chosen or {}) do
                if pick.item and YR.RewardKind(pick.item) == nil then db.chosen[quest] = Copy(pick) end
            end
        end
        db.on = YippRouteDB.pickRewards ~= false
        YippRouteDB.rewardClasses[class] = db
    end
    if db.on == nil then db.on = true end
    -- every kind is in the list once, so the settings can switch any of them on
    local seen = {}
    for _, k in ipairs(db.order) do seen[k] = true end
    for _, kind in ipairs(YR.REWARD_KINDS) do
        if not seen[kind.key] then
            db.order[#db.order + 1] = kind.key
            db.off[kind.key] = true
        end
    end
    return db
end

local SLOT = { INVTYPE_2HWEAPON = "twohand", INVTYPE_WEAPON = "onehand", INVTYPE_WEAPONMAINHAND = "onehand",
    INVTYPE_WEAPONOFFHAND = "onehand", INVTYPE_RANGED = "ranged", INVTYPE_RANGEDRIGHT = "ranged",
    INVTYPE_THROWN = "ranged", INVTYPE_CLOAK = "cloak", INVTYPE_FINGER = "jewelry", INVTYPE_NECK = "jewelry",
    INVTYPE_TRINKET = "jewelry", INVTYPE_SHIELD = "shield" }
local ARMOR_KIND = { [1] = "cloth", [2] = "leather", [3] = "mail", [4] = "plate", [6] = "shield" }

-- The kind of reward an item is; false while its spell isn't loaded yet (ask again shortly).
function YR.RewardKind(itemID)
    local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if SLOT[equipLoc] then return SLOT[equipLoc] end
    if classID == ARMOR then return ARMOR_KIND[subclassID] end
    -- a plain bag only: a mining pack or herb bag is a profession choice, not an upgrade
    if classID == CONTAINER then return subclassID == 0 and "bag" or nil end
    if classID == CONSUMABLE then
        if subclassID == 1 then return "potion" end
        if subclassID == 5 then
            local spell = C_Item.GetItemSpell(itemID)
            if spell == nil then return false end
            return spell == "Drink" and "water" or "food"
        end
    end
    return nil
end

local picking = false      -- our own GetQuestReward call, so it isn't remembered as the player's choice

local function Take(index)
    YR.Print("reward: " .. (GetQuestItemLink("choice", index) or "?"))
    picking = true
    GetQuestReward(index)
    picking = false
end

local function Choose(tries)
    local n = GetNumQuestChoices()
    local db = YR:RewardSettings()
    if n < 2 or IsShiftKeyDown() or UnitLevel("player") > db.maxLevel or not db.on then return end
    local items, values, kinds = {}, {}, {}
    for i = 1, n do
        local _, _, _, _, isUsable, itemID = GetQuestItemInfo("choice", i)
        local kind = itemID and YR.RewardKind(itemID)
        if not itemID or kind == false then
            return tries > 0 and C_Timer.After(0.2, function() Choose(tries - 1) end)
        end
        items[i], kinds[i] = isUsable and itemID, kind
        values[i] = select(11, C_Item.GetItemInfo(itemID)) or 0
    end
    -- 1. the reward you chose for this quest before
    local mine = db.remember and db.chosen[GetQuestID()]
    if mine then
        for i = 1, n do if items[i] == mine.item then return Take(i) end end
    end
    -- a choice that isn't gear or food (a profession to learn, a profession bag, a pet): yours, unless you chose
    -- it by hand on this quest before (above)
    for i = 1, n do
        if not kinds[i] then
            YR.Print("this quest's rewards aren't gear: pick the one you want.")
            return
        end
    end
    -- 2. your priority list; the more valuable of two of the same kind
    for _, kind in ipairs(db.order) do
        if not db.off[kind] then
            local best
            for i = 1, n do
                if items[i] and kinds[i] == kind and (not best or values[i] > values[best]) then best = i end
            end
            if best then return Take(best) end
        end
    end
    -- 3. nothing from the list on offer
    if db.fallback == "value" then
        local best
        for i = 1, n do if items[i] and (not best or values[i] > values[best]) then best = i end end
        if best then return Take(best) end
    end
end

-- A reward you picked by hand is remembered for that quest.
hooksecurefunc("GetQuestReward", function(index)
    if picking or not index or GetNumQuestChoices() < 2 then return end
    local name, _, _, _, _, itemID = GetQuestItemInfo("choice", index)
    local db = YR:RewardSettings()
    if itemID and db.remember then
        db.chosen[GetQuestID()] = { item = itemID, name = name, title = GetTitleText() }
    end
end)

local f = CreateFrame("Frame")
f:RegisterEvent("QUEST_COMPLETE")
f:SetScript("OnEvent", function() Choose(10) end)
