-- Gear sim: is this item better for you? A levelling estimate, not a raid sim.
--
--   It takes your own numbers from the game (attack power, crit, spell power, health, armor - read out of
--   combat and kept, since some are secret in a fight), swaps the item in for what it would replace, and
--   works out one figure for your role before and after:
--     melee   damage per second: (weapon DPS + attack power / 14) x (1 + crit); an off hand at half
--     ranged  the same with the ranged weapon and ranged attack power (hunters)
--     caster  (spell base + spell power) x (1 + crit / 2)
--     healer  (heal base + healing) x (1 + crit / 2), plus mana back (mp5 and Spirit)
--     tank    effective health: health / (1 - armor's reduction)
--   and, for every role, toughness: effective health, shown beside it so an armor-only piece isn't "0%".
--
--   The role comes from your talents (the tree with the most points), or your class's levelling role
--   before you have any; Settings, QoL, Gear & rewards can fix it. Stats come from the item: the game's
--   stat list (C_Item.GetItemStats) and the "Equip:" lines of its tooltip (spell power, healing, crit,
--   hit, attack power, mana per 5), plus the weapon's speed and damage per second.
--
--   Hybrids: a melee paladin's seals and Judgement and a melee shaman's shocks hit harder with spell power,
--   so for them spell power adds to melee DPS (a small share per point). A weapon's "Chance on hit: ...
--   N damage" counts at about one proc a minute. Against a two-hander you wield, a one-hander comes with
--   the best off hand in your bags (a shield, a held item), and an off hand with the best one-hander in
--   your bags (or an empty main hand) - the two-hander comes off either way, as in the game's own comparison.
--   What it leaves out: set bonuses, other on-hit effects, trinkets, talents that change the formulas,
--   hit and weapon skill caps. The conversions (attack power per Strength, crit per Agility or Intellect)
--   are vanilla's, scaled by level - Forever's own tables aren't in the client data.
local ADDON, YR = ...

-- Each class's three talent tabs, in tab order, as the role they play while levelling.
local TAB_ROLES = {
    WARRIOR = { "melee", "melee", "tank" },
    PALADIN = { "healer", "tank", "melee" },
    HUNTER = { "ranged", "ranged", "ranged" },
    ROGUE = { "melee", "melee", "melee" },
    PRIEST = { "healer", "healer", "caster" },
    SHAMAN = { "caster", "melee", "healer" },
    MAGE = { "caster", "caster", "caster" },
    WARLOCK = { "caster", "caster", "caster" },
    DRUID = { "caster", "melee", "healer" },
}
-- Before any talent points: what the class levels as.
local DEFAULT_ROLE = { WARRIOR = "melee", PALADIN = "melee", HUNTER = "ranged", ROGUE = "melee", PRIEST = "caster",
    SHAMAN = "melee", MAGE = "caster", WARLOCK = "caster", DRUID = "caster" }
-- Attack power from Strength and Agility (melee), ranged attack power from Agility.
local AP_STR = { WARRIOR = 2, PALADIN = 2, SHAMAN = 2, DRUID = 2, ROGUE = 1, HUNTER = 1, PRIEST = 1, MAGE = 1, WARLOCK = 1 }
local AP_AGI = { ROGUE = 1, HUNTER = 1, DRUID = 1, WARRIOR = 0, PALADIN = 0, SHAMAN = 0, PRIEST = 0, MAGE = 0, WARLOCK = 0 }
local RAP_AGI = { HUNTER = 2, WARRIOR = 1, ROGUE = 1 }
-- Agility for 1% melee crit, and Intellect for 1% spell crit, at level 60 (vanilla's tables).
local AGI_CRIT60 = { ROGUE = 29, HUNTER = 53, WARRIOR = 20, PALADIN = 20, SHAMAN = 20, DRUID = 20, PRIEST = 20, MAGE = 20, WARLOCK = 20 }
local INT_CRIT60 = { MAGE = 59.5, PRIEST = 59.2, WARLOCK = 60.6, PALADIN = 29.5, SHAMAN = 59.2, DRUID = 60, WARRIOR = 999,
    ROGUE = 999, HUNTER = 999 }
-- Melee DPS per point of spell power for the hybrids whose melee rotation is partly spells.
local HYBRID_SP = { PALADIN = 0.10, SHAMAN = 0.06 }
local ROLE_WORD = { melee = "DPS", ranged = "DPS", caster = "damage", healer = "healing", tank = "toughness" }

local function Class() local _, c = UnitClass("player") return c or "WARRIOR" end

local function Num(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return tonumber(v)
end

-- ---------------------------------------------------------------------------
-- Your role
-- ---------------------------------------------------------------------------
--- Points per talent tab, read the way BuffWarden reads them (the tree's three display groups are the
--- three old tabs). nil when nothing is spent or the game won't say.
local function TalentTabs()
    local ok, tabs = pcall(function()
        local config = C_ClassTalents.GetActiveConfigID()
        local info = config and C_Traits.GetConfigInfo(config)
        local tree = info and info.treeIDs and info.treeIDs[1]
        local groups = tree and C_Traits.GetGroupDisplayInfoByTreeID(tree)
        local nodes = tree and C_Traits.GetTreeNodes(tree)
        if not (groups and nodes) then return nil end
        local byGroup, out = {}, {}
        for _, g in ipairs(groups) do
            local t = { name = g.displayName, tab = (g.orderIndex or 0) + 1, points = 0 }
            byGroup[g.groupID] = t
            out[t.tab] = t
        end
        for _, node in ipairs(nodes) do
            local n = C_Traits.GetNodeInfo(config, node)
            local ranks = n and Num(n.ranksPurchased)
            if ranks and ranks > 0 and n.groupIDs then
                for _, id in ipairs(n.groupIDs) do
                    if byGroup[id] then byGroup[id].points = byGroup[id].points + ranks end
                end
            end
        end
        return out
    end)
    if ok then return tabs end
end

--- Your role and why: { role, spec (the tab's name, or nil), guessed (true unless set by hand) }.
function YR.SimRole()
    local class = Class()
    local set = YippRouteDB and YippRouteDB.simRole
    if set and ROLE_WORD[set] then return { role = set, guessed = false } end
    local tabs, top = TalentTabs(), nil
    for _, t in pairs(tabs or {}) do
        if t.points > 0 and (not top or t.points > top.points) then top = t end
    end
    if top then
        local role = (TAB_ROLES[class] or {})[top.tab]
        if role then return { role = role, spec = top.name, guessed = true } end
    end
    return { role = DEFAULT_ROLE[class] or "melee", guessed = true }
end

-- ---------------------------------------------------------------------------
-- An item's stats
-- ---------------------------------------------------------------------------
local STAT_KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", ITEM_MOD_ATTACK_POWER_SHORT = "ap",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap", ITEM_MOD_SPELL_POWER_SHORT = "sp",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
    ITEM_MOD_POWER_REGEN0_SHORT = "mp5", ITEM_MOD_MANA_REGENERATION_SHORT = "mp5",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps", RESISTANCE0_NAME = "armor",
    ITEM_MOD_CRIT_RATING_SHORT = "critRating", ITEM_MOD_HIT_RATING_SHORT = "hitRating",
}
-- "Equip:" lines, for stats the stat list doesn't carry on this client.
local EQUIP_LINES = {
    { "damage and healing done by magical spells and effects by up to (%d+)", "sp" },
    { "healing done by spells and effects by up to (%d+)", "heal" },
    { "chance to get a critical strike with spells by (%d+)%%", "scrit" },
    { "chance to get a critical strike by (%d+)%%", "crit" },
    { "chance to hit with spells by (%d+)%%", "shit" },
    { "chance to hit by (%d+)%%", "hit" },
    { "%+(%d+) ranged Attack Power", "rap" },
    { "%+(%d+) Attack Power", "ap" },
    { "(%d+) mana per 5 sec", "mp5" },
}

--- Everything about an item the sim weighs: str agi sta int spi ap rap sp heal mp5 crit scrit hit dps
--- speed armor (missing ones are 0). Read once per item and kept.
local cache = {}
function YR.SimItemStats(link)
    if not link then return {} end
    if cache[link] then return cache[link] end
    local s = setmetatable({}, { __index = function() return 0 end })
    for key, v in pairs(C_Item.GetItemStats(link) or {}) do
        local k = STAT_KEYS[key]
        if k and tonumber(v) then rawset(s, k, rawget(s, k) and rawget(s, k) + v or v) end
    end
    local ok, data = pcall(function() return C_TooltipInfo and C_TooltipInfo.GetHyperlink(link) end)
    for _, line in ipairs(ok and data and data.lines or {}) do
        for _, text in ipairs({ line.leftText, line.rightText }) do
            if type(text) == "string" then
                local speed = text:match("^Speed (%d+%.%d+)")
                if speed then rawset(s, "speed", tonumber(speed)) end
                -- "Chance on hit: Blasts a target for 42 Fire damage." - about one proc a minute
                local proc = text:find("^Chance on hit:") and text:match("(%d+) %a* ?damage")
                if proc then rawset(s, "procdps", (rawget(s, "procdps") or 0) + tonumber(proc) / 60) end
                if text:find("^Equip:") then
                    for _, rule in ipairs(EQUIP_LINES) do
                        local n = text:match(rule[1])
                        -- only where the stat list didn't already say it, so nothing counts twice
                        if n and not rawget(s, rule[2]) then rawset(s, rule[2], tonumber(n)) break end
                    end
                end
            end
        end
    end
    cache[link] = s
    return s
end

-- ---------------------------------------------------------------------------
-- Your numbers, and the value of a set of changes
-- ---------------------------------------------------------------------------
local me             -- the last snapshot that could be read (out of combat)

--- Your numbers now, from the game. Kept from the last time they could be read.
function YR.SimSnapshot()
    if InCombatLockdown() and me then return me end
    local ok, snap = pcall(function()
        local base, pos, neg = UnitAttackPower("player")
        local rbase, rpos, rneg = UnitRangedAttackPower("player")
        local sp, heal = 0, Num(GetSpellBonusHealing and GetSpellBonusHealing()) or 0
        local scrit = 0
        for school = 2, 7 do
            sp = math.max(sp, Num(GetSpellBonusDamage(school)) or 0)
            scrit = math.max(scrit, Num(GetSpellCritChance(school)) or 0)
        end
        local _, armor = UnitArmor("player")
        local s = {
            level = Num(UnitLevel("player")) or 1,
            ap = (Num(base) or 0) + (Num(pos) or 0) + (Num(neg) or 0),
            rap = (Num(rbase) or 0) + (Num(rpos) or 0) + (Num(rneg) or 0),
            crit = Num(GetCritChance()) or 0, rcrit = Num(GetRangedCritChance and GetRangedCritChance()) or 0,
            sp = sp, heal = heal, scrit = scrit,
            hp = Num(UnitHealthMax("player")) or 100, armor = Num(armor) or 0,
            spi = Num(select(2, UnitStat("player", 5))) or 0,
        }
        return s
    end)
    if ok and snap then me = snap end
    return me
end

--- Item stats summed over the equipped items in these slots.
local function Worn(slots)
    local t = setmetatable({}, { __index = function() return 0 end })
    for _, slot in ipairs(slots) do
        for k, v in pairs(YR.SimItemStats(GetInventoryItemLink("player", slot))) do t[k] = t[k] + v end
    end
    return t
end

--- The figure for a role, from your numbers with `d` (stat changes) and these weapons.
local function Value(role, s, d, mh, oh, ranged)
    local class, lvl = Class(), math.max(1, s.level)
    local agiCrit = math.max(1, (AGI_CRIT60[class] or 20) * lvl / 60)
    local intCrit = math.max(1, (INT_CRIT60[class] or 60) * lvl / 60)
    if role == "melee" then
        local ap = s.ap + d.ap + d.str * (AP_STR[class] or 1) + d.agi * (AP_AGI[class] or 0)
        local crit = math.min(100, s.crit + d.crit + d.agi / agiCrit) / 100
        local dps = (mh + ap / 14) * (1 + crit)
        if oh > 0 then dps = dps + 0.5 * (oh + ap / 14) * (1 + crit) end
        return dps + (s.sp + d.sp) * (HYBRID_SP[class] or 0)
    elseif role == "ranged" then
        local rap = s.rap + d.rap + d.agi * (RAP_AGI[class] or 1)
        local crit = math.min(100, s.rcrit + d.crit + d.agi / agiCrit) / 100
        return (ranged + rap / 14) * (1 + crit)
    elseif role == "caster" then
        local crit = math.min(100, s.scrit + d.scrit + d.int / intCrit) / 100
        return (lvl * 4 + s.sp + d.sp) * (1 + crit / 2)
    elseif role == "healer" then
        local crit = math.min(100, s.scrit + d.scrit + d.int / intCrit) / 100
        local throughput = (lvl * 4 + s.heal + d.heal + d.sp) * (1 + crit / 2)
        local regen = 5 + d.mp5 + (s.spi + d.spi) / 4 + d.int / 10
        return throughput + regen * 2
    end
    return nil
end

local function Toughness(s, d)
    local lvl = math.max(1, s.level)
    local hp = s.hp + d.sta * 10
    local armor = math.max(0, s.armor + d.armor + d.agi * 2)
    local reduction = math.min(0.75, armor / (armor + 400 + 85 * lvl))
    return hp / (1 - reduction)
end

-- Where each kind of item goes (the same as Upgrades.lua's).
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local function IsWeapon(link)
    if not link then return false end
    local _, _, _, _, _, class = C_Item.GetItemInfoInstant(link)
    return class == 2
end

local function Loc(link)
    if not link then return nil end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    return equipLoc
end

--- A weapon's damage per second with its procs.
local function WeaponDPS(link)
    if not link then return 0 end
    local st = YR.SimItemStats(link)
    return st.dps + st.procdps
end

--- Items in your bags of these kinds that you could wear (the game's red text rules out the rest).
local function BagItems(kinds)
    local out = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local link = type(info) == "table" and info.hyperlink
            if kinds[Loc(link) or ""] and not (YR.Unwearable and YR.Unwearable(bag, slot)) then
                out[#out + 1] = link
            end
        end
    end
    return out
end
local OFF_HANDS = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true }
local MAIN_HANDS = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }

--- What wearing this item would do: { pct = role change in %, tough = toughness change in %, role,
--- spec, word ("DPS", "healing" ...), slot, old = the link it replaces }, or nil for an item that isn't gear.
function YR.SimCompare(link, role)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    local slots = equipLoc and SLOTS[equipLoc]
    if not slots then return nil end
    local snap = YR.SimSnapshot()
    if not snap then return nil end
    local r = role or YR.SimRole()
    local new = YR.SimItemStats(link)
    local function Weapons(replace, with, offHand, mainHand)
        local mhL, ohL, rL = GetInventoryItemLink("player", 16), GetInventoryItemLink("player", 17), GetInventoryItemLink("player", 18)
        if replace[16] then mhL = with end
        if replace[17] ~= nil then ohL = replace[17] and with or nil end
        if offHand then ohL = offHand end
        if replace.mainHand ~= nil then mhL = mainHand end
        if replace[18] then rL = with end
        local oh = IsWeapon(ohL) and WeaponDPS(ohL) or 0
        return WeaponDPS(mhL), oh, WeaponDPS(rL)
    end
    local base = Value(r.role, snap, setmetatable({}, { __index = function() return 0 end }), Weapons({}))
    local baseTough = Toughness(snap, setmetatable({}, { __index = function() return 0 end }))
    local best
    local options = {}
    if equipLoc == "INVTYPE_2HWEAPON" then
        options[1] = { slots = { 16, 17 }, replace = { [16] = true, [17] = false } }
    else
        for _, s in ipairs(slots) do
            -- a one-hander only goes in the off hand where you already carry a weapon there
            if not (equipLoc == "INVTYPE_WEAPON" and s == 17 and not IsWeapon(GetInventoryItemLink("player", 17))) then
                options[#options + 1] = { slots = { s }, replace = { [s] = true } }
            end
        end
    end
    -- A one-hander where you wield a two-hander: with nothing in the off hand, or with each off hand from
    -- your bags you could wear - the best of them counts, as in the game's own comparison.
    local worn2H = Loc(GetInventoryItemLink("player", 16)) == "INVTYPE_2HWEAPON"
    if worn2H and MAIN_HANDS[equipLoc] then
        options = { { slots = { 16 }, replace = { [16] = true } } }
        for _, oh in ipairs(BagItems(OFF_HANDS)) do
            options[#options + 1] = { slots = { 16 }, replace = { [16] = true }, offHand = oh }
        end
    elseif worn2H and OFF_HANDS[equipLoc] then
        -- an off hand where a two-hander is: the two-hander comes off, so a main hand from your bags (or none)
        options = { { slots = { 16, 17 }, slot = 17, replace = { [17] = true, mainHand = false } } }
        for _, mh in ipairs(BagItems(MAIN_HANDS)) do
            options[#options + 1] = { slots = { 16, 17 }, slot = 17, replace = { [17] = true, mainHand = true }, mainHand = mh }
        end
    end
    for _, o in ipairs(options) do
        local old = Worn(o.slots)
        local d = setmetatable({}, { __index = function() return 0 end })
        for k, v in pairs(new) do d[k] = d[k] + v end
        for k, v in pairs(old) do d[k] = d[k] - v end
        local partner = o.offHand or o.mainHand
        if partner then
            for k, v in pairs(YR.SimItemStats(partner)) do if k ~= "dps" and k ~= "procdps" then d[k] = d[k] + v end end
        end
        local after = Value(r.role, snap, d, Weapons(o.replace, link, o.offHand, o.mainHand))
        local tough = Toughness(snap, d)
        local pct = (base and base > 0 and after) and (after - base) / base * 100 or 0
        local tpct = baseTough > 0 and (tough - baseTough) / baseTough * 100 or 0
        if r.role == "tank" then pct = tpct end
        if not best or pct > best.pct or (pct == best.pct and tpct > best.tough) then
            best = { pct = pct, tough = tpct, slot = o.slot or o.slots[1], old = GetInventoryItemLink("player", o.slots[1]),
                with = o.offHand or o.mainHand, bare = o.replace.mainHand == false }
        end
    end
    if not best then return nil end
    best.role, best.spec, best.word, best.guessed = r.role, r.spec, ROLE_WORD[r.role], r.guessed
    return best
end

--- The tooltip line: "+4.2% DPS, +1.0% toughness (Retribution)".
function YR.SimLine(c)
    local function Pct(v) return ("%s%.1f%%"):format(v >= 0 and "+" or "", v) end
    -- only what moves: armor bracers say "+4.0% toughness", not "+0.0% DPS" first
    local main
    if c.role == "tank" or (math.abs(c.pct) < 0.05 and math.abs(c.tough) >= 0.1) then
        main = Pct(c.tough) .. " toughness"
    else
        main = Pct(c.pct) .. " " .. c.word .. (math.abs(c.tough) >= 0.1 and (", " .. Pct(c.tough) .. " toughness") or "")
    end
    local with = c.with and C_Item.GetItemNameByID and C_Item.GetItemNameByID(c.with)
    return main .. (c.spec and (" (" .. c.spec .. ")") or "") .. (with and (", with " .. with)
        or c.bare and ", with no main hand" or "")
end

-- Answers kept until something they depend on changes (gear, bags, stats, level, talents, the role
-- setting): a tooltip refreshes five times a second while you point at an item, and the bags are looked
-- through after every loot. false = not gear, or your numbers can't be read.
-- Your role is read off the talent tree (every node of it), so it's kept on its own, for longer than
-- the answers: only talents, a level or the role setting change it - not every loot.
local memo, memoRole, roleKept = {}, nil, nil
function YR.SimCompareKept(link)
    local set = YippRouteDB and YippRouteDB.simRole
    if set ~= memoRole then wipe(memo) memoRole, roleKept = set, nil end
    local c = memo[link]
    if c == nil then
        roleKept = roleKept or YR.SimRole()
        c = YR.SimCompare(link, roleKept) or false
        memo[link] = c
    end
    return c or nil
end

-- What you wear, by link: the tooltip asks "is this one of them?" five times a second.
local worn
local function Wearing(link)
    if not worn then
        worn = {}
        for slot = 1, 18 do
            local l = GetInventoryItemLink("player", slot)
            if l then worn[l] = true end
        end
    end
    return worn[link] == true
end

local function OnTooltip(tooltip)
    if not YR.Option("simTooltip") or tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    if not (ok and link) then return end
    if Wearing(link) then return end           -- what you wear already
    local c = YR.SimCompareKept(link)
    if not c then return end
    c.line = c.line or YR.SimLine(c)           -- the same answer has the same words
    local r, g, b = 0.6, 0.6, 0.6
    local score = c.role == "tank" and c.tough or c.pct
    if score > 0.05 then r, g, b = 0.4, 1, 0.4 elseif score < -0.05 then r, g, b = 1, 0.45, 0.45 end
    tooltip:AddLine("Headstart: " .. c.line, r, g, b)
    tooltip:Show()
end

--- Drop the item stats kept (a new item's text arrives later than its link, and gear changes).
function YR.SimForget() wipe(cache) wipe(memo) worn = nil end

function YR.StartSim()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltip)
    end
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_LEVEL_UP",
        "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "BAG_UPDATE_DELAYED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    if not pcall(f.RegisterUnitEvent, f, "UNIT_STATS", "player") then pcall(f.RegisterEvent, f, "UNIT_STATS") end
    local pending = false
    f:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_STATS" and unit ~= "player" then return end
        if event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_ENTERING_WORLD" then worn = nil end
        if event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_LEVEL_UP"
            or event == "PLAYER_ENTERING_WORLD" then
            roleKept = nil
        end
        if event == "PLAYER_EQUIPMENT_CHANGED" then YR.SimForget() else wipe(memo) end
        if event == "BAG_UPDATE_DELAYED" or pending then return end   -- bags: only the off hands to pair with
        pending = true
        C_Timer.After(0.2, function() pending = false YR.SimSnapshot() wipe(memo) end)
    end)
end
