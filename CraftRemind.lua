-- Make it yourself: when you know the recipe and carry the mats for sharpening stones, weightstones,
-- wizard or mana oil or bandages, but have none of them in your bags, one chat line says so - with
-- the best one you can make and how many.
--   * Stones only for the weapon you carry: blades get sharpened, blunt weapons weighted (the same
--     split BuffWarden uses to put them on).
--   * "Have none" counts every rank of the kind: a Rough Sharpening Stone in the bags is a stone.
--   * Told once per kind; again after you've had some and run out.
-- The recipes come from the game's data (Data/Consumables.lua); a recipe counts as known when the
-- game says you know its spell.
-- Account options (YippRouteDB, Settings, QoL): craftRemind (on unless turned off), craftStones,
-- craftOils, craftBandages (each on unless turned off), craftBelow (remind under this many; default 1).
local ADDON, YR = ...

local KIND_BY_SUBCLASS = {
    [0] = "sharpening", [1] = "sharpening", [7] = "sharpening", [8] = "sharpening",
    [15] = "sharpening", [6] = "sharpening",
    [4] = "weightstone", [5] = "weightstone", [10] = "weightstone", [13] = "weightstone",
}
local OPTION = { sharpening = "craftStones", weightstone = "craftStones", oil = "craftOils", bandage = "craftBandages" }
local LABEL = { sharpening = "sharpening stones", weightstone = "weightstones", oil = "oils", bandage = "bandages" }
local PROFESSION = { [164] = "Blacksmithing", [333] = "Enchanting", [129] = "First Aid" }

local told = {}        -- [kind] = true until you have some again

local function Count(item) return C_Item.GetItemCount(item) or 0 end

--- The kinds worth thinking about for you right now.
local function Kinds()
    local out = {}
    if not YR.Option("craftRemind") then return out end
    for _, slot in ipairs({ 16, 17 }) do
        local id = GetInventoryItemID("player", slot)
        if id then
            local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(id)
            local kind = class == 2 and KIND_BY_SUBCLASS[subclass]
            if kind and YR.Option("craftStones") then out[kind] = true end
        end
    end
    if YR.Option("craftOils") then out.oil = true end
    if YR.Option("craftBandages") then out.bandage = true end
    return out
end

local function Known(spell)
    if IsPlayerSpell and IsPlayerSpell(spell) then return true end
    local ok, yes = pcall(function() return C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spell) end)
    return ok and yes or false
end

--- How many times the mats in your bags make this recipe.
local function Makes(e)
    local r, n = e[7], math.huge
    for i = 1, #r, 2 do n = math.min(n, math.floor(Count(r[i]) / r[i + 1])) end
    return n == math.huge and 0 or n
end

--- What you could make of each kind you have too few of:
--- [kind] = { item, times, total, have, profession }. The best recipe whose mats you carry.
function YR.CraftChances()
    local kinds, have, best = Kinds(), {}, {}
    for _, e in ipairs(YR.Consumables or {}) do
        local kind = e[6]
        if kinds[kind] then have[kind] = (have[kind] or 0) + Count(e[4]) end
    end
    local below = YippRouteDB.craftBelow or 1
    for _, e in ipairs(YR.Consumables or {}) do
        local kind = e[6]
        if kinds[kind] and (have[kind] or 0) < below and Known(e[1]) then
            local times = Makes(e)
            if times > 0 and (not best[kind] or e[3] > best[kind].rank) then
                best[kind] = { item = e[4], times = times, total = times * e[5], have = have[kind] or 0,
                    rank = e[3], profession = PROFESSION[e[2]] }
            end
        end
    end
    -- Back up to the line: tell again next time you run out.
    for kind in pairs(told) do
        if (have[kind] or 0) >= below then told[kind] = nil end
    end
    return best
end

local function Name(item) return C_Item.GetItemNameByID and C_Item.GetItemNameByID(item) or ("item " .. item) end

function YR.CheckCrafts()
    if InCombatLockdown() then return end
    for kind, c in pairs(YR.CraftChances()) do
        if not told[kind] then
            told[kind] = true
            YR.Print(("you can make %d %s from your bags, and you have %s %s - open %s."):format(c.total,
                Name(c.item), c.have == 0 and "no" or ("only " .. c.have), LABEL[kind], c.profession or "the profession"))
        end
    end
end

function YR.StartCraftRemind()
    local f = CreateFrame("Frame")
    local pending = false
    local function Later()
        if pending then return end
        pending = true
        C_Timer.After(1, function() pending = false YR.CheckCrafts() end)
    end
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED", "LEARNED_SPELL_IN_TAB",
        "PLAYER_ENTERING_WORLD" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", Later)
end
