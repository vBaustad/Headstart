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

-- This runs a second after every change to your bags: the tables it fills are made once and emptied.
local WEAPONS = { 16, 17 }
local kinds, have, best, entries = {}, {}, {}, {}
local function Empty(t) for k in pairs(t) do t[k] = nil end end

--- The kinds worth thinking about for you right now.
local function Kinds()
    local out = kinds
    Empty(out)
    if not YR.Option("craftRemind") then return out end
    for _, slot in ipairs(WEAPONS) do
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

-- Whether you know a recipe: asked for every recipe after every change to your bags, and it only
-- changes when you learn something - so it's kept until then (YR.CraftForget).
local known = {}
local function Known(spell)
    local yes = known[spell]
    if yes == nil then
        yes = (IsPlayerSpell and IsPlayerSpell(spell)) and true or false
        if not yes and C_SpellBook and C_SpellBook.IsSpellKnown then
            local ok, book = pcall(C_SpellBook.IsSpellKnown, spell)
            yes = (ok and book) and true or false
        end
        known[spell] = yes
    end
    return yes
end
-- Whether you know any recipe of a kind (no First Aid: no bandages to count), kept as long.
local can = {}
local function Can(kind)
    local yes = can[kind]
    if yes == nil then
        yes = false
        for _, e in ipairs(YR.Consumables or {}) do
            if e[6] == kind and Known(e[1]) then yes = true break end
        end
        can[kind] = yes
    end
    return yes
end
function YR.CraftForget()
    for k in pairs(known) do known[k] = nil end
    for k in pairs(can) do can[k] = nil end
end

--- How many times the mats in your bags make this recipe.
local function Makes(e)
    local r, n = e[7], math.huge
    for i = 1, #r, 2 do n = math.min(n, math.floor(Count(r[i]) / r[i + 1])) end
    return n == math.huge and 0 or n
end

--- What you could make of each kind you have too few of:
--- [kind] = { item, times, total, have, profession }. The best recipe whose mats you carry.
--- (The table and its rows are used again by the next call: read them, don't keep them.)
function YR.CraftChances()
    Kinds()
    Empty(have)
    Empty(best)
    -- a kind you know no recipe of is nothing you could make: its items aren't counted at all
    for kind in pairs(kinds) do if not Can(kind) then kinds[kind] = nil end end
    if next(kinds) == nil then return best end          -- none of the three kinds is on: nothing to count
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
                local b = entries[kind]
                if not b then b = {} entries[kind] = b end
                b.item, b.times, b.total, b.have = e[4], times, times * e[5], have[kind] or 0
                b.rank, b.profession = e[3], PROFESSION[e[2]]
                best[kind] = b
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

-- One look a second after the last change, however many came.
local pending = false
local function Check() pending = false YR.CheckCrafts() end
local function Later()
    if pending then return end
    pending = true
    C_Timer.After(1, Check)
end

-- Your bags, your weapons and the end of a fight are only worth hearing about while there is something
-- you could make: a character with none of the recipes (most, at first) listens for none of them, until
-- a spell is learned.
local BAGS = { "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED" }
local watching = false
local function AnyCan()
    return (YR.Option("craftStones") and (Can("sharpening") or Can("weightstone")))
        or (YR.Option("craftOils") and Can("oil")) or (YR.Option("craftBandages") and Can("bandage")) or false
end
local function Watch(frame)
    local want = AnyCan()
    if want == watching then return end
    watching = want
    for _, e in ipairs(BAGS) do
        if want then pcall(frame.RegisterEvent, frame, e) else pcall(frame.UnregisterEvent, frame, e) end
    end
end

local function OnEvent(frame, event)
    if event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "PLAYER_ENTERING_WORLD" then
        YR.CraftForget()
        Watch(frame)
    end
    if watching then Later() end
end

local declared
function YR.StartCraftRemind()
    if declared then return end
    declared = true
    -- (the newer name of "learned a spell" is asked for too: a client has one or the other)
    YR.Part(function() return YR.Option("craftRemind") end,
        { "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_ENTERING_WORLD" }, OnEvent, {
            start = function(p) Watch(p.frame) end,
            again = function(p) Watch(p.frame) end,           -- one of the three kinds turned on or off
            stop = function() watching = false end,
        })
end
