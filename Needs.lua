-- What the route still needs from your bags, so it isn't sold by accident: meat and ribs sold at
-- the first vendor for money cost a run 14 minutes of grinding them again, and a quest.
--
-- It is read from the routes themselves: ".collect item,count,quest" names the item, how many, and
-- the quest it is for. An item stays needed until that quest is turned in, including before it is
-- accepted (Coldridge's boars drop the meat Dun Morogh's Stocking Jetsteam asks for later). Lines
-- for profession skill-ups (.collect with flags after the quest) are not a quest's need and are left out.
local _, YR = ...

local needs            -- itemID -> { { quest, count }, ... }
local titles           -- questID -> title, from the routes' accept and turn-in lines

-- Whether a step's "<< ..." filter lets this character see it: alternatives split by "/", each a
-- list of words that must all hold (Class, Race, Faction, or "!" before one for "not"). Words it
-- doesn't know (RestedXP's own, like "sod") count as true: better to keep an item than lose it.
-- Asked for every filtered step of every route (hundreds at a time): the words are one table, who you
-- are is read once it's known, and each filter's answer is kept. Once the game has said all three (class,
-- race, faction) they don't change, so a kept answer is given before any of them is asked for again.
local KNOWN = { warrior = 1, paladin = 1, hunter = 1, rogue = 1, priest = 1, shaman = 1, mage = 1, warlock = 1,
    druid = 1, human = 1, dwarf = 1, gnome = 1, nightelf = 1, orc = 1, troll = 1, tauren = 1, scourge = 1,
    undead = 1, alliance = 1, horde = 1 }
local mine, who, shown, settled = {}, nil, {}, false
local function Shows(filter)
    if not filter or filter:match("^%s*$") then return true end
    if settled then
        local known = shown[filter]
        if known ~= nil then return known end
    else
        local _, class = UnitClass("player")
        local _, race = UnitRace("player")
        local faction = UnitFactionGroup("player")
        local now = (class or "") .. "/" .. (race or "") .. "/" .. (faction or "")
        if now ~= who then              -- the first call, or before the game knew who you are
            who, shown = now, {}
            mine = { [(class or ""):lower()] = true, [(race or ""):lower()] = true, [(faction or ""):lower()] = true }
        end
        settled = class ~= nil and race ~= nil and faction ~= nil
        if shown[filter] ~= nil then return shown[filter] end
    end
    local answer = false
    for alt in filter:gmatch("[^/]+") do
        local ok = true
        for word in alt:gmatch("%S+") do
            local neg, w = word:match("^(!?)(.+)$")
            w = w:lower()
            if KNOWN[w] then
                local has = mine[w] or (w == "undead" and mine.scourge) or false
                if (neg == "!") == has then ok = false end
            end
        end
        if ok then answer = true break end
    end
    shown[filter] = answer
    return answer
end

YR.Shows = Shows

local function Build()
    needs, titles = {}, {}
    -- only the routes this character can follow (from its race's starting route on)
    local _, race = UnitRace("player")
    local mine = YR:RoutesFor(race)
    for _, g in ipairs(YR.shipped) do
        local text = mine[g.key] and YR:GuideText(g.key) or ""
        for q, t in text:gmatch("%.accept (%d+)[,%d]*%s*>>%s*Accept ([^\n|]+)") do titles[tonumber(q)] = titles[tonumber(q)] or t end
        for q, t in text:gmatch("%.turnin %-?(%d+)[^\n]->>%s*Turn in ([^\n|]+)") do titles[tonumber(q)] = titles[tonumber(q)] or t end
        local header, steps = YR.SplitSteps(text)
        for _, step in ipairs(steps) do
            if Shows(step:match("^step%s*<<%s*([^\n%-]+)")) then
                for line in step:gmatch("[^\n]+") do
                    local args = line:match("^%s*%.collect%s+([%d,]+)%s*$") or line:match("^%s*%.collect%s+([%d,]+)%s")
                        or line:match("^%s*%.collect%s+([%d,]+)%-%-")
                    -- item,count,quest[,objective] only: anything after is a profession skill-up line
                    local item, count, quest, rest = (args or ""):match("^(%d+),(%d+),(%d+),?(%d*)$")
                    local cond = line:match("<<%s*([^\n%-]+)")
                    if item and (not cond or Shows(cond)) then
                        item, count, quest = tonumber(item), tonumber(count), tonumber(quest)
                        needs[item] = needs[item] or {}
                        local found
                        for _, n in ipairs(needs[item]) do
                            if n.quest == quest then n.count = math.max(n.count, count) found = true end
                        end
                        if not found then needs[item][#needs[item] + 1] = { quest = quest, count = count } end
                    end
                end
            end
        end
    end
end

-- Camping 101: Blacksmithing and Mining are skill quests, not item quests: the ore, bars and stones
-- the route smelts and crafts to skill 20 are kept while you are on them (the route has no .collect).
local SKILL_UPS = {
    { item = 2770, quest = 96044, count = 20 },   -- Copper Ore: smelted for Mining, the bars for Blacksmithing
    { item = 2840, quest = 96044, count = 20 },   -- Copper Bar
    { item = 2835, quest = 96044, count = 10 },   -- Rough Stone: Rough Weightstones
}

local skillItems = {}
for _, n in ipairs(SKILL_UPS) do skillItems[n.item] = true end

-- Routes change when the player saves an edit: read them again next time.
function YR:ForgetNeeds() needs = nil end

local function Done(quest)
    return C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(quest) or false
end

local function OnQuest(quest)
    return C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(quest) or false
end

local function Title(quest)
    -- "Camping 101: Mining << Warrior/Paladin" in the route: the title is the part before the filter
    local t = titles[quest]
    if t then t = t:gsub("%s*<<.*$", "") end
    return t or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(quest)) or ("quest " .. quest)
end

-- How many of this item the route still needs, and for what ("Stocking Jetsteam"), or nil.
-- live (optional): function(quest) - only quests it says yes to count (the bank and the mail leave out
-- quests you've outlevelled, YR.QuestLive).
function YR.RouteNeed(item, live)
    if not item then return nil end
    if not needs then Build() end
    -- most items no route needs: said at once, before anything is made (this is every item tooltip)
    if not needs[item] and not skillItems[item] then return nil end
    local count, what = 0, {}
    for _, n in ipairs(needs[item] or {}) do
        if not Done(n.quest) and (not live or live(n.quest)) then
            count = count + n.count
            what[#what + 1] = Title(n.quest)
        end
    end
    for _, n in ipairs(SKILL_UPS) do
        if n.item == item and OnQuest(n.quest) and not C_QuestLog.IsComplete(n.quest) then
            count = count + n.count
            what[#what + 1] = Title(n.quest)
        end
    end
    if count == 0 then return nil end
    return count, table.concat(what, ", ")
end

-- The sell guard: a line on the item's tooltip, and a warning when you sell what the route needs.
-- Both are hooks on the game, which can't be taken off again, so: they are put on the first time the
-- guard is on (the routes on and its option, the part below) - never on an install without routes -
-- and each asks first thing whether the guard is on now.
local guard = false

-- A line on the item's tooltip: what the route needs it for, and how many you have.
local function AddLine(tooltip, item)
    local count, what = YR.RouteNeed(item)
    if not count then return end
    local have = C_Item.GetItemCount and C_Item.GetItemCount(item) or 0
    tooltip:AddLine(("Headstart: keep %d for %s (you have %d)"):format(count, what, have), 1, 0.8, 0.3, true)
end

local function OnTooltipData(tooltip, data)
    if not guard then return end
    if tooltip == GameTooltip and data and data.id then AddLine(tooltip, data.id) end
end

local function OnTooltipItem(tooltip)
    if not guard then return end
    local _, link = tooltip:GetItem()
    local item = link and tonumber(link:match("item:(%d+)"))
    if item then AddLine(tooltip, item) end
end

local tipped = false
local function HookTips()
    if tipped then return end
    tipped = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipData)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", OnTooltipItem)
    end
end

-- Selling at a vendor goes through UseContainerItem (right-click). It can't be stopped without
-- tainting the bags, so it is caught right after: the item is still in its slot (locked) then, and
-- the vendor's Buyback tab still has it. Who else wants to hear of a sale (the run log) says so with
-- YR:WatchSells, and with YR.SellsWatched whether it is listening now.
local watchers, watched, sells = {}, false, false

local function Sold(bag, slot)
    if not (guard or watched) then return end
    if not (MerchantFrame and MerchantFrame:IsShown()) then return end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not (info and info.itemID) then return end
    for i = 1, #watchers do watchers[i](info.itemID, info.stackCount or 1) end
    if not guard then return end
    local need, what = YR.RouteNeed(info.itemID)
    if need then
        local name = C_Item.GetItemNameByID(info.itemID) or ("item " .. info.itemID)
        local msg = ("sold %s, but the route still needs %d for %s. Buy it back on the vendor's Buyback tab.")
            :format(name, need, what)
        YR.Print("|cffff7070" .. msg .. "|r")
        if UIErrorsFrame then UIErrorsFrame:AddMessage("Headstart: the route still needs " .. name, 1, 0.3, 0.3) end
    end
end

local function HookSells()
    if sells then return end
    sells = true
    if C_Container and C_Container.UseContainerItem then
        hooksecurefunc(C_Container, "UseContainerItem", Sold)
    elseif UseContainerItem then
        hooksecurefunc("UseContainerItem", Sold)
    end
end

function YR:WatchSells(onSell)
    watchers[#watchers + 1] = onSell
end

--- A watcher is listening for sales now, or no longer is.
function YR.SellsWatched(on)
    watched = on and true or false
    if watched then HookSells() end
end

local part
function YR:HookTooltips()
    if part then return end
    part = YR.Part(function() return YR.RoutesOn() and YR.Option("sellGuard") end, nil, nil, {
        start = function()
            guard = true
            HookTips()
            HookSells()
        end,
        stop = function() guard = false end,
    })
end
