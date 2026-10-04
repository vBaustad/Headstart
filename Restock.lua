-- Restock: at a vendor who sells them, buy your class reagents, your ammo and anything else you
-- listed back up to the number you keep. Hold Shift as you open the vendor to buy nothing.
--
--   Class reagents come from the game's own spell data (Data/Restock.lua): an item is wanted while
--   you know a spell that takes it, and of the ranks of one spell (Rebirth's seeds, Gift of the
--   Wild's berries) only the top rank you know - nobody wants Maple Seeds once they cast rank 5.
--   Ammo (hunters): the best arrows or bullets this vendor sells that fit your ranged weapon and
--   that you can use - the most expensive usable one, which is the best one on a vanilla vendor.
--
--   Account options in YippRouteDB (Settings, QoL):
--     restock          on unless turned off
--     restockCounts    [itemID] = how many to keep, for the class reagents; nil = the default
--     restockCustom    [itemID] = how many to keep, for items you added yourself
--     restockAmmo      how much ammo to keep (nil = 1000, 0 = none)
--     restockReserve   gold to keep: nothing is bought that would take you under it
local ADDON, YR = ...

local AMMO_DEFAULT = 1000
local AMMO_FOR = { [2] = 2, [18] = 2, [3] = 3 }   -- bow and crossbow take arrows, guns bullets
local AMMO_CLASS = 6

local function DB()
    YippRouteDB.restockCounts = YippRouteDB.restockCounts or {}
    YippRouteDB.restockCustom = YippRouteDB.restockCustom or {}
    return YippRouteDB
end

--- How many of a class reagent to keep: what you set, else the default from the data.
function YR.RestockCount(item, default)
    local v = DB().restockCounts[item]
    if v == nil then return default or 0 end
    return v
end

function YR.SetRestockCount(item, n)
    DB().restockCounts[item] = math.max(0, math.floor(n or 0))
end

function YR.RestockAmmo()
    local v = DB().restockAmmo
    if v == nil then return AMMO_DEFAULT end
    return v
end

--- This class's reagents from the data, with whether you can use any of them yet:
--- { { item, default, spells, wanted = bool, why = "Rebirth" }, ... }
function YR.RestockReagents()
    local _, class = UnitClass("player")
    local list = (YR.RestockData or {})[class] or {}
    -- The top known rank of every spell, by name.
    local top = {}
    for _, e in ipairs(list) do
        for _, sp in ipairs(e[3]) do
            local id, level, name = sp[1], sp[2], sp[3]
            if IsPlayerSpell and IsPlayerSpell(id) and (not top[name] or level > top[name].level) then
                top[name] = { level = level, item = e[1] }
            end
        end
    end
    local out = {}
    for _, e in ipairs(list) do
        local wanted, why = false, nil
        for _, sp in ipairs(e[3]) do
            local t = top[sp[3]]
            if t and t.item == e[1] then wanted, why = true, sp[3] break end
        end
        out[#out + 1] = { item = e[1], default = e[2], spells = e[3], wanted = wanted, why = why or e[3][1][3] }
    end
    return out
end

-- ---------------------------------------------------------------------------
-- At the vendor
-- ---------------------------------------------------------------------------
local function ItemInfo(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        if type(info) == "table" then
            return info.price or 0, math.max(1, info.stackCount or 1), info.numAvailable or -1,
                info.isUsable, info.hasExtendedCost
        end
    end
    local _, _, price, stack, avail, _, usable, extended = GetMerchantItemInfo(i)
    return price or 0, math.max(1, stack or 1), avail or -1, usable, extended and true or false
end

local function Count(item) return C_Item.GetItemCount(item) or 0 end

--- What this vendor sells, by item: [itemID] = { index, price per item, available, usable }.
local function Offer()
    local out = {}
    for i = 1, GetMerchantNumItems() do
        local id = GetMerchantItemID(i)
        if id then
            local price, stack, avail, usable, extended = ItemInfo(i)
            if not extended then
                out[id] = { index = i, each = price / stack, avail = avail, usable = usable }
            end
        end
    end
    return out
end

--- The ammo to buy here: the best usable arrows or bullets for your ranged weapon, and how many
--- you already have of the kinds this vendor sells for it. nil when there is none to buy.
local function Ammo(offer)
    local target = YR.RestockAmmo()
    if target <= 0 then return nil end
    local ranged = GetInventoryItemID("player", 18)
    if not ranged then return nil end
    local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(ranged)
    local kind = class == 2 and AMMO_FOR[subclass]
    if not kind then return nil end
    local best, have = nil, 0
    for id, o in pairs(offer) do
        local _, _, _, _, _, c, sc = C_Item.GetItemInfoInstant(id)
        if c == AMMO_CLASS and sc == kind then
            have = have + Count(id)
            if o.usable ~= false and (not best or o.each > offer[best].each) then best = id end
        end
    end
    if not best then return nil end
    return best, target, have
end

--- The shopping list at this vendor: { { item, index, want, each, why } } in the order to buy.
function YR.RestockPlan()
    local offer = Offer()
    local plan = {}
    local function Add(item, target, have, why)
        local o = offer[item]
        if not o or target <= 0 then return end
        local want = target - (have or Count(item))
        if o.avail >= 0 then want = math.min(want, o.avail) end
        if want > 0 then plan[#plan + 1] = { item = item, index = o.index, want = want, each = o.each, why = why } end
    end
    for _, r in ipairs(YR.RestockReagents()) do
        if r.wanted then Add(r.item, YR.RestockCount(r.item, r.default), nil, r.why) end
    end
    local ammo, target, have = Ammo(offer)
    if ammo then Add(ammo, target, have, "ammo") end
    for item, n in pairs(DB().restockCustom) do Add(item, n, nil, "your list") end
    return plan
end

local function Coins(c)
    return (GetCoinTextureString and GetCoinTextureString(math.floor(c + 0.5))) or (math.floor(c + 0.5) .. "c")
end

local function Name(item)
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(item)
    return name or ("item " .. item)
end

--- Buy the plan, as far as the money above the reserve goes.
function YR.Restock(loud)
    if InCombatLockdown() then return end
    local plan = YR.RestockPlan()
    if #plan == 0 then
        if loud then YR.Print("nothing to restock here.") end
        return
    end
    local floor = (DB().restockReserve or 0) * 10000
    local money = GetMoney()
    local bought, short, spent = {}, {}, 0
    for _, p in ipairs(plan) do
        local afford = p.each > 0 and math.floor((money - floor) / p.each) or p.want
        local n = math.min(p.want, math.max(0, afford))
        if n > 0 then
            local left = n
            local max = math.max(1, GetMerchantItemMaxStack(p.index) or 1)
            while left > 0 do
                local now = math.min(left, max)
                BuyMerchantItem(p.index, now)
                left = left - now
            end
            money = money - n * p.each
            spent = spent + n * p.each
            bought[#bought + 1] = n .. " " .. Name(p.item)
        end
        if n < p.want then short[#short + 1] = (p.want - n) .. " " .. Name(p.item) end
    end
    if #bought > 0 then
        YR.Print("restocked " .. table.concat(bought, ", ") .. " (" .. Coins(spent) .. ").")
    end
    if #short > 0 then
        YR.Print("not enough gold above what you keep for " .. table.concat(short, ", ") .. ".")
    end
end

--- Add an item to your own list (or change its count; 0 takes it off).
function YR.SetRestockCustom(item, n)
    item = tonumber(item)
    if not item then return end
    DB().restockCustom[item] = (n and n > 0) and math.floor(n) or nil
end

--- An item ID out of whatever was typed or shift-clicked in: "1234", "item:1234" or a full link.
function YR.ItemFromText(text)
    if type(text) ~= "string" then return nil end
    return tonumber(text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$"))
end

function YR.StartRestock()
    local f = CreateFrame("Frame")
    f:RegisterEvent("MERCHANT_SHOW")
    f:SetScript("OnEvent", function()
        if not YR.Option("restock") or IsShiftKeyDown() then return end
        -- A moment for the vendor's list to arrive; Shift was read above, while the key is down.
        C_Timer.After(0.3, function() YR.Restock(false) end)
    end)
end
