-- Buy later: the route's buys you couldn't afford when you passed (the Kharanos weapons and the
-- like) come back when you can. A RestedXP step with ".money <X" is skipped for good if you're short
-- as you reach it, so Headstart keeps the list instead:
--   * read from the routes this character follows: a step with ".money <price" and ".collect item,1"
--     (what to buy, for how much, from whom and where; ".itemStat 16,...DAMAGE_PER_SECOND..., <N":
--     only while your weapon is worse than that). Or "#hsprice price" in place of ".money": RestedXP
--     only stores that line on the step, where ".money <" hides the step the moment you can't pay (the
--     route chat, 2026-10-16: the Rogue's Stiletto in Dolanaar vanished as Gouge was trained)
--   * the next one ahead of you on the route you're on is what the trainer keeps money back for
--     (YR.NextRouteBuy, Trainer.lua)
--   * once you have the money, don't have the item and it still beats your weapon, one line in chat
--     says what, how much and where
--   * at any vendor who sells it, a popup offers to buy it (hold Shift as you open the vendor to skip)
-- Account option buyLater (Settings, Route). Told about once per character and item (YippSetupCharDB).
local _, YR = ...

local list          -- { { item, price, npc, where, dps, name } }

-- A buy step's purchase: ".collect item,1" and its price (".money <" or "#hsprice", in gold); nil for any
-- other step.
local function BuyOf(step)
    local price = step:match("\n%s*%.money%s+<([%d%.]+)") or step:match("\n%s*#hsprice%s+([%d%.]+)")
    local item = step:match("\n%s*%.collect%s+(%d+),1%s*[%-\n]") or step:match("\n%s*%.collect%s+(%d+),1$")
    if not (price and item) then return nil end
    -- (its name: [Stiletto] in the text, else the collect line's own words: "--Collect Stiletto (1)",
    -- "-- Mining Pick (1)", "--Stiletto (1)")
    local name = step:match("%[(.-)%]")
    if not name then
        name = step:match("%.collect%s+%d+,1[^\n]-%-%-%s*([^%(\n]+)")
        name = name and (name:gsub("^Collect%s+", ""))
    end
    return {
        item = tonumber(item),
        price = math.floor(tonumber(price) * 10000 + 0.5),
        npc = (step:match("\n%s*%.target%s+([^\n:]+)") or ""):gsub("%s+$", ""),
        where = step:match("\n%s*%.goto%s+([^\n]+)"),
        dps = tonumber(step:match("ITEM_MOD_DAMAGE_PER_SECOND_SHORT,%s*<%s*([%d%.]+)")),
        name = name and name:gsub("%s+$", "") or ("item " .. item),
    }
end

local function Build()
    list = {}
    local seen = {}
    local _, race = UnitRace("player")
    local mine = YR:RoutesFor(race)
    for _, g in ipairs(YR.shipped) do
        local text = mine[g.key] and YR:GuideText(g.key) or ""
        local _, steps = YR.SplitSteps(text)
        for _, step in ipairs(steps) do
            local e = YR.Shows(step:match("^step%s*<<%s*([^\n%-]+)")) and BuyOf(step)
            if e and not seen[e.item] then
                seen[e.item] = true
                list[#list + 1] = e
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

--- The route's next buy ahead of you: on the route you're on (one of Headstart's, as RestedXP has it for
--- this character), from your step on, the first whose item you still want. Nil for none. The trainer keeps
--- its price back (Trainer.lua) - asked as a trainer opens, so the steps are read then and not kept.
function YR.NextRouteBuy()
    if not (YR.RoutesOn and YR.RoutesOn() and YR.RouteKeyOf and YR.CharSteps) then return nil end
    local key = YR.RouteKeyOf(type(RXP) == "table" and RXP.currentGuide)
    local n = type(RXPCData) == "table" and tonumber(RXPCData.currentStep)
    if not (key and n) then return nil end
    local steps = YR.CharSteps(key)
    for i = math.max(1, n), #steps do
        local e = BuyOf(steps[i])
        if e and YR.ShoppingWanted(e) then return e end
    end
    return nil
end

local function Coins(c) return YR.Money(c) end

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
    if not YR.Option("buyLater") or not GetMerchantNumItems then return end
    local wanted = YR.ShoppingList()
    if #wanted == 0 then return end             -- nothing on the list: the vendor's goods aren't read
    local money = GetMoney()
    for i = 1, GetMerchantNumItems() do
        local id = GetMerchantItemID(i)
        for _, e in ipairs(wanted) do
            if id == e.item and YR.ShoppingWanted(e) then
                local cost = YR.MerchantInfo(i) or e.price      -- Restock.lua: C_MerchantFrame on Forever
                if money >= cost then
                    -- the data as StaticPopup_Show's own argument: writing popup.data from here would taint
                    -- the popup frame, and the next Blizzard popup to use it (Delete item) could fail
                    StaticPopup_Show("HEADSTART_BUY_LATER", e.name, Coins(cost), { index = i, item = e.item })
                    return
                end
            end
        end
    end
end

-- Money changes once per item sold: look once it settles, not twenty times for twenty sales.
local pending = false
local function Settled()
    pending = false
    Check()
end

-- A part (Core.lua): only with the routes and the option on is money, gear or a vendor listened for.
-- And then nothing is done while the list is empty (a class or race the routes have no such buy for).
YR.Part(function() return YR.RoutesOn() and YR.Option("buyLater") end,
    { "PLAYER_MONEY", "PLAYER_EQUIPMENT_CHANGED", "MERCHANT_SHOW" },
    function(_, event)
        if #YR.ShoppingList() == 0 then return end
        if event == "MERCHANT_SHOW" then
            -- (Shift read now, while it is down for the click on the vendor - not a moment later)
            if not IsShiftKeyDown() then C_Timer.After(0.2, AtVendor) end
        elseif not pending then
            pending = true
            C_Timer.After(0.5, Settled)
        end
    end,
    { start = function() C_Timer.After(0.5, Check) end })       -- at the login: can you afford one already?
