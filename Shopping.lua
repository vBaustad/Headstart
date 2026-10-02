-- Buy later: the route's buys you couldn't afford when you passed (the Kharanos weapons and the
-- like) come back when you can. A RestedXP step with ".money <X" is skipped for good if you're short
-- as you reach it, so Headstart keeps the list instead:
--   * read from the routes this character follows: a step with ".money <price" and ".collect item,1"
--     (what to buy, for how much, from whom and where; ".itemStat 16,...DAMAGE_PER_SECOND..., <N":
--     only while your weapon is worse than that)
--   * once you have the money, don't have the item and it still beats your weapon, one line in chat
--     says what, how much and where
--   * at any vendor who sells it, a popup offers to buy it (hold Shift as you open the vendor to skip)
-- Account option buyLater (Settings, Route). Told about once per character and item (YippSetupCharDB).
local _, YR = ...

local list          -- { { item, price, npc, where, dps, name } }

local function Build()
    list = {}
    local seen = {}
    local _, race = UnitRace("player")
    local mine = YR:RoutesFor(race)
    for _, g in ipairs(YR.shipped) do
        local text = mine[g.key] and YR:GuideText(g.key) or ""
        local _, steps = YR.SplitSteps(text)
        for _, step in ipairs(steps) do
            local price = step:match("\n%s*%.money%s+<([%d%.]+)")
            local item = step:match("\n%s*%.collect%s+(%d+),1%s*[%-\n]") or step:match("\n%s*%.collect%s+(%d+),1$")
            if price and item and YR.Shows(step:match("^step%s*<<%s*([^\n%-]+)")) and not seen[item] then
                seen[item] = true
                local name = step:match("%[(.-)%]") or step:match("%-%-Collect ([^%(\n]+)")
                list[#list + 1] = {
                    item = tonumber(item),
                    price = math.floor(tonumber(price) * 10000 + 0.5),
                    npc = (step:match("\n%s*%.target%s+([^\n:]+)") or ""):gsub("%s+$", ""),
                    where = step:match("\n%s*%.goto%s+([^\n]+)"),
                    dps = tonumber(step:match("ITEM_MOD_DAMAGE_PER_SECOND_SHORT,%s*<%s*([%d%.]+)")),
                    name = name and name:gsub("%s+$", "") or ("item " .. item),
                }
            end
        end
    end
end

function YR:ForgetShopping() list = nil end

function YR.ShoppingList()
    if not list then Build() end
    return list
end

-- Your main hand's damage per second (0 with none).
local function WeaponDPS()
    local link = GetInventoryItemLink("player", 16)
    if not link then return 0 end
    local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
    local stats = getStats and getStats(link)
    return stats and stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT or 0
end

local function Have(item)
    local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(item)) or (GetItemCount and GetItemCount(item)) or 0
    return count > 0 or (IsEquippedItem and IsEquippedItem(item)) or false
end

-- Still worth buying: not had, and (for a weapon) better than the one you hold.
function YR.ShoppingWanted(e)
    if Have(e.item) then return false end
    if e.dps and WeaponDPS() >= e.dps then return false end
    return true
end

local function Coins(c)
    return GetCoinTextureString and GetCoinTextureString(c) or (("%dg %ds %dc"):format(c / 10000, (c / 100) % 100, c % 100))
end

local function Place(e)
    if not e.where then return "" end
    local map, x, y = e.where:match("^(%d+),([%d%.]+),([%d%.]+)")
    local zone = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(tonumber(map))
    if zone and x then return (" in %s (%.0f, %.0f)"):format(zone.name, tonumber(x), tonumber(y)) end
    return ""
end

local function Check()
    if not YR.Option("buyLater") or not YippSetupCharDB then return end
    YippSetupCharDB.toldBuy = YippSetupCharDB.toldBuy or {}
    local money = GetMoney()
    for _, e in ipairs(YR.ShoppingList()) do
        if not YippSetupCharDB.toldBuy[e.item] and money >= e.price and YR.ShoppingWanted(e) then
            YippSetupCharDB.toldBuy[e.item] = true
            YR.Print(("you can afford the %s now (%s): %s%s."):format(e.name, Coins(e.price),
                e.npc ~= "" and e.npc or "its vendor", Place(e)))
        end
    end
end

StaticPopupDialogs["HEADSTART_BUY_LATER"] = {
    text = "Headstart: buy the %s for %s?",
    button1 = "Buy",
    button2 = "Not now",
    OnAccept = function(_, data)
        if data and MerchantFrame and MerchantFrame:IsShown() and GetMerchantItemID(data.index) == data.item then
            BuyMerchantItem(data.index, 1)
        end
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
}

local function AtVendor()
    if not YR.Option("buyLater") or IsShiftKeyDown() or not GetMerchantNumItems then return end
    local money = GetMoney()
    for i = 1, GetMerchantNumItems() do
        local id = GetMerchantItemID(i)
        for _, e in ipairs(YR.ShoppingList()) do
            if id == e.item and YR.ShoppingWanted(e) then
                local cost = select(3, GetMerchantItemInfo(i)) or e.price
                if money >= cost then
                    local popup = StaticPopup_Show("HEADSTART_BUY_LATER", e.name, Coins(cost))
                    if popup then popup.data = { index = i, item = e.item } end
                    return
                end
            end
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_MONEY")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("MERCHANT_SHOW")
f:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        C_Timer.After(0.2, AtVendor)
    else
        Check()
    end
end)
