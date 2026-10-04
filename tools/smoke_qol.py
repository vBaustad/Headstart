"""Smoke test of the QoL modules Restock, Reminders, Upgrades and PartyQuests against a fake WoW API,
in Lua 5.1 (lupa).

    python tools/smoke_qol.py      (exit code 1 on any failure; tools/smoke.py runs it too)
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r'''
FRAMES, AFTER, PRINTS, NOW = {}, {}, {}, 0
local Obj
Obj = { __call = function() return setmetatable({}, Obj) end }
Obj.__index = function(t, k)
    local v = rawget(Obj, k)
    if v then return v end
    local child = setmetatable({}, Obj); rawset(t, k, child); return child
end
function Obj.Show(self) rawset(self, "_shown", true) end
function Obj.Hide(self) rawset(self, "_shown", false) local h = rawget(self, "_OnHide") if h then h(self) end end
function Obj.IsShown(self) return rawget(self, "_shown") ~= false end
function Obj.SetScript(self, what, fn) rawset(self, "_" .. what, fn) end
function Obj.RegisterEvent(self, e) rawset(self, "_ev", rawget(self, "_ev") or {}) self._ev[e] = true end
function Obj.SetText(self, t) rawset(self, "_text", t) end
function CreateFrame(_, name) local f = setmetatable({}, Obj) table.insert(FRAMES, f) if name then _G[name] = f end return f end
UIParent = CreateFrame()
GameTooltip = CreateFrame()
UIErrorsFrame = CreateFrame()
function Fire(event, ...) for _, f in ipairs(FRAMES) do if rawget(f, "_ev") and f._ev[event] and rawget(f, "_OnEvent") then f._OnEvent(f, event, ...) end end end
C_Timer = { After = function(_, fn) table.insert(AFTER, fn) end, NewTicker = function() return { Cancel = function() end } end }
function RunAfter() for _ = 1, 5 do local l = AFTER AFTER = {} for _, fn in ipairs(l) do fn() end end end
function GetTime() return NOW end
COMBAT, SHIFT = false, false
function InCombatLockdown() return COMBAT end
function IsShiftKeyDown() return SHIFT end
bit = {
    lshift = function(a, n) return a * 2 ^ n end,
    band = function(a, b)
        local r, p = 0, 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then r = r + p end
            a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
        end
        return r
    end,
}
CLASS, RACE, LEVEL, MONEY = "MAGE", 3, 20, 100000
function UnitClass() return "Mage", CLASS end
function UnitRace() return "Dwarf", "Dwarf", RACE end
function UnitLevel() return LEVEL end
function GetMoney() return MONEY end
function GetCoinTextureString(c) return c .. "c" end
KNOWN = {}
function IsPlayerSpell(id) return KNOWN[id] == true end
-- items: [id] = { class, subclass, equipLoc, quality, stats }
ITEMS = {}
COUNT = {}
C_Item = {
    GetItemInfoInstant = function(id)
        local n = tonumber(type(id) == "string" and id:match("item:(%d+)") or id)
        local i = ITEMS[n]
        if not i then return nil end
        return n, nil, nil, i[3], 1, i[1], i[2]
    end,
    GetItemCount = function(id) return COUNT[id] or 0 end,
    GetItemNameByID = function(id) return "Item" .. id end,
    GetItemStats = function(link)
        local n = tonumber(link:match("item:(%d+)"))
        return ITEMS[n] and ITEMS[n][5] or {}
    end,
    GetItemQualityByID = function(link)
        local n = tonumber(link:match("item:(%d+)"))
        return ITEMS[n] and ITEMS[n][4]
    end,
    GetItemIconByID = function() return 1 end,
}
-- the vendor: { { id, price, stackCount, usable } }
VENDOR, BOUGHT = {}, {}
function GetMerchantNumItems() return #VENDOR end
function GetMerchantItemID(i) return VENDOR[i][1] end
-- Forever has C_MerchantFrame.GetItemInfo only (the global GetMerchantItemInfo is Vanilla UI, not there)
C_MerchantFrame = { GetItemInfo = function(i) local v = VENDOR[i] return { name = "x", texture = 1, price = v[2], stackCount = v[3], numAvailable = -1, isPurchasable = true, isUsable = v[4] ~= false, hasExtendedCost = false } end }
function GetMerchantItemMaxStack() return 200 end
function BuyMerchantItem(i, n) table.insert(BOUGHT, { VENDOR[i][1], n }) COUNT[VENDOR[i][1]] = (COUNT[VENDOR[i][1]] or 0) + n end
-- equipment: [slot] = link; durability [slot] = { cur, max }
WORN, DUR = {}, {}
function GetInventoryItemLink(_, s) return WORN[s] end
function GetInventoryItemID(_, s) local l = WORN[s] return l and tonumber(l:match("item:(%d+)")) end
function GetInventoryItemDurability(s) local d = DUR[s] if d then return d[1], d[2] end end
-- bags: [bag*100+slot] = { link, red tooltip }
BAGS = {}
NUM_BAG_SLOTS = 4
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 4 or 0 end,
    GetContainerItemInfo = function(bag, slot) local b = BAGS[bag * 100 + slot] return b and { hyperlink = b[1] } end,
}
-- your numbers (the sim reads them), talents, and item tooltips by link
STATS = { ap = 100, rap = 20, crit = 5, rcrit = 5, sp = 0, heal = 0, scrit = 5, hp = 500, armor = 300, spi = 40 }
function UnitAttackPower() return STATS.ap, 0, 0 end
function UnitRangedAttackPower() return STATS.rap, 0, 0 end
function GetCritChance() return STATS.crit end
function GetRangedCritChance() return STATS.rcrit end
function GetSpellBonusDamage() return STATS.sp end
function GetSpellBonusHealing() return STATS.heal end
function GetSpellCritChance() return STATS.scrit end
function UnitHealthMax() return STATS.hp end
function UnitArmor() return STATS.armor, STATS.armor end
function UnitStat(_, i) return STATS.spi, STATS.spi end
TABS = nil          -- { points tab 1, tab 2, tab 3 }
C_ClassTalents = { GetActiveConfigID = function() return 1 end }
TIPS = {}
C_TooltipInfo = { GetHyperlink = function(link)
    local lines = { { leftText = "x" } }
    for _, t in ipairs(TIPS[link] or {}) do lines[#lines + 1] = { leftText = t } end
    return { lines = lines }
end }
POSTCALLS = {}
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) table.insert(POSTCALLS, fn) end }
Enum = { TooltipDataType = { Item = 0 } }
C_TooltipInfo.GetBagItem = function(bag, slot)
    local b = BAGS[bag * 100 + slot]
    return { lines = { { leftText = "x", leftColor = b and b[2] and { r = 1, g = 0.12, b = 0.12 } or { r = 1, g = 1, b = 1 } } } }
end
SHOTS = 0
function Screenshot() SHOTS = SHOTS + 1 end
RESTING = false
function IsResting() return RESTING end
-- talents
UNSPENT = 0
C_ClassTalents = { GetActiveConfigID = function() return 1 end }
C_Traits = { GetConfigInfo = function() return { treeIDs = { 9 } } end,
    GetTreeCurrencyInfo = function() return { { quantity = UNSPENT } } end,
    GetGroupDisplayInfoByTreeID = function() return { { groupID = 1, orderIndex = 0, displayName = "Holy" },
        { groupID = 2, orderIndex = 1, displayName = "Protection" }, { groupID = 3, orderIndex = 2, displayName = "Retribution" } } end,
    GetTreeNodes = function() return { 11, 12, 13 } end,
    GetNodeInfo = function(_, node) return { ranksPurchased = TABS and TABS[node - 10] or 0, groupIDs = { node - 10 } } end }
-- trainer window
SERVICES = {}
function GetNumTrainerServices() return #SERVICES end
function GetTrainerServiceInfo(i) local s = SERVICES[i] return s[1], s[2], "available" end
function GetTrainerServiceCost(i) return SERVICES[i][3] end
function IsTradeskillTrainer() return false end
-- party
PARTY, GUILD, FRIENDS, NPCNAME = {}, {}, {}, nil
function UnitName(u) if u == "npc" then return NPCNAME end return "Me" end
function Ambiguate(n) return n end
function UnitInParty(n) return PARTY[n] or false end
function UnitInRaid() return false end
function UnitIsInMyGuild(u) return u == "npc" and GUILD[NPCNAME] or false end
function UnitGUID(u) return u == "npc" and NPCNAME and ("Player-" .. NPCNAME) or nil end
C_FriendList = { IsFriend = function(guid) return FRIENDS[guid:gsub("^Player%-", "")] or false end,
    GetFriendInfo = function(n) return FRIENDS[n] and {} or nil end }
function IsInGuild() return false end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
YippRouteDB = {}
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
-- quick group
TARGET, INGROUP, LEADER, MEMBERS, INVITED, LEFT, ACCEPTED, POPUP = nil, false, false, 1, {}, 0, 0, nil
function UnitExists(u) return u == "target" and TARGET ~= nil end
function UnitIsPlayer(u) return u == "target" and TARGET ~= nil and TARGET.player end
function UnitIsUnit(a, b) return a == "target" and b == "player" and TARGET and TARGET.me or false end
function GetUnitName() return TARGET and TARGET.name end
function IsInGroup() return INGROUP end
function IsInRaid() return false end
function UnitIsGroupLeader() return LEADER end
function UnitIsGroupAssistant() return false end
function GetNumGroupMembers() return MEMBERS end
C_PartyInfo = { InviteUnit = function(n) table.insert(INVITED, n) end, LeaveParty = function() LEFT = LEFT + 1 end }
function AcceptGroup() ACCEPTED = ACCEPTED + 1 end
function StaticPopup_FindVisible(which) return which == "PARTY_INVITE" and POPUP or nil end
function StaticPopup_Hide() if POPUP and not POPUP.inviteAccepted then DECLINED = true end POPUP = nil end
SECRET = {}
function issecretvalue(v) return SECRET[v] == true end
'''


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    YR = lua.table()
    for f in ("Core.lua", "Style.lua", "Data/Restock.lua", "Restock.lua", "Data/TrainerSpells.lua", "Reminders.lua",
              "Sim.lua", "Upgrades.lua", "PartyQuests.lua", "Data/Consumables.lua", "CraftRemind.lua", "QuickGroup.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    g = lua.globals()
    lua.execute("function YR_PRINT(m) table.insert(PRINTS, m) end")
    YR.Print = g.YR_PRINT
    bad = 0

    def check(ok, what):
        nonlocal bad
        if not ok:
            bad += 1
            print("FAIL qol:", what)

    def YR_names(miss):
        return [(miss[i].name, miss[i].rank) for i in range(1, len(miss) + 1)]

    def prints():
        return [g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)]

    def bought():
        total = {}
        for i in range(1, len(g.BOUGHT) + 1):
            total[g.BOUGHT[i][1]] = total.get(g.BOUGHT[i][1], 0) + g.BOUGHT[i][2]
        return sorted(total.items())

    # ---- Restock -------------------------------------------------------------------------------
    YR.StartRestock()
    mage = YR.RestockData.MAGE
    rune = next(mage[i] for i in range(1, len(mage) + 1) if mage[i][1] == 17031)
    teleport = rune[3][1][1]
    druid = YR.RestockData.DRUID
    seeds = {druid[i][1]: druid[i][3][1][1] for i in range(1, len(druid) + 1) if druid[i][3][1][3] == "Rebirth"}
    check(len(seeds) == 5, f"Rebirth takes five seeds, one per rank: {seeds}")

    lua.execute("VENDOR = { { 17031, 1000, 1 }, { 17056, 30, 1 }, { 4540, 25, 1 } }")
    g.KNOWN[teleport] = True
    g.COUNT[17031] = 2
    g.Fire("MERCHANT_SHOW")
    lua.execute("RunAfter()")
    check(bought() == [(17031, 3)], f"a mage with a teleport tops the runes up to 5, no feathers without Slow Fall: {bought()}")
    check(any("restocked 3 Item17031" in p for p in prints()), f"chat says what was bought: {prints()}")

    lua.execute("BOUGHT = {} COUNT = {} SHIFT = true")
    g.Fire("MERCHANT_SHOW")
    lua.execute("RunAfter() SHIFT = false")
    check(bought() == [], "Shift as the vendor opens: nothing bought")

    lua.execute("BOUGHT = {} COUNT = {} MONEY = 3500 PRINTS = {}")
    g.YippRouteDB.restockReserve = 0
    YR.Restock(False)
    check(bought() == [(17031, 3)], f"only what the money pays for: {bought()}")
    check(any("not enough gold" in p for p in prints()), "and chat says what was left")
    lua.execute("BOUGHT = {} COUNT = {} MONEY = 100000")
    g.YippRouteDB.restockReserve = 9          # 90000 copper kept: 10000 to spend = 10 runes, wants 5
    YR.Restock(False)
    check(bought() == [(17031, 5)], f"the reserve is kept: {bought()}")
    g.YippRouteDB.restockReserve = 10
    lua.execute("BOUGHT = {} COUNT = {}")
    YR.Restock(False)
    check(bought() == [], "nothing that would go under the reserve")
    g.YippRouteDB.restockReserve = None

    YR.SetRestockCount(17031, 0)
    YR.SetRestockCustom(4540, 20)
    lua.execute("BOUGHT = {} COUNT = {}")
    YR.Restock(False)
    check(bought() == [(4540, 20)], f"a count of 0 buys none; your own list is bought: {bought()}")
    YR.SetRestockCustom(4540, 0)
    check(g.YippRouteDB.restockCustom[4540] is None, "0 takes it off your list")
    check(YR.ItemFromText("|cffffffff|Hitem:4540::::|h[Tough Hunk of Bread]|h|r 20") == 4540, "an item link reads as its ID")

    # druid: only the top Rebirth rank's seed
    lua.execute("CLASS = 'DRUID' KNOWN = {} BOUGHT = {} COUNT = {} VENDOR = { { 17034, 200, 1 }, { 17035, 400, 1 }, { 17036, 800, 1 } }")
    g.KNOWN[seeds[17034]] = True
    g.KNOWN[seeds[17035]] = True
    YR.Restock(False)
    check(bought() == [(17035, 3)], f"a druid with Rebirth 2 buys Stranglethorn Seeds, not Maple: {bought()}")

    # hunter ammo: the best usable arrows for a bow
    lua.execute('''CLASS = 'HUNTER' BOUGHT = {} COUNT = {}
        ITEMS[2504] = { 2, 2, "INVTYPE_RANGED", 1, {} }                 -- a bow
        ITEMS[2512] = { 6, 2, "INVTYPE_AMMO", 1, {} } ITEMS[2515] = { 6, 2, "INVTYPE_AMMO", 1, {} }
        ITEMS[3030] = { 6, 2, "INVTYPE_AMMO", 1, {} } ITEMS[2516] = { 6, 3, "INVTYPE_AMMO", 1, {} }
        WORN = { [18] = "|Hitem:2504|h" }
        VENDOR = { { 2512, 10, 200 }, { 2515, 50, 200 }, { 3030, 100, 200, false }, { 2516, 10, 200 } }
        COUNT[2512] = 300''')
    YR.Restock(False)
    check(bought() == [(2515, 700)], f"bow: Sharp Arrows (usable, best) up to 1000 counting the rough ones: {bought()}")
    # a warrior shoots too: 200 to begin with, and a number of its own
    lua.execute("CLASS = 'WARRIOR' BOUGHT = {} COUNT = { [2512] = 50 }")
    YR.Restock(False)
    check(bought() == [(2515, 150)], f"a warrior with a bow: up to 200, not a hunter's 1000: {bought()}")
    YR.SetRestockAmmo(100)
    check(YR.RestockAmmo("WARRIOR") == 100 and YR.RestockAmmo("HUNTER") == 1000, "each class keeps its own ammo number")
    check(not YR.RestockShoots("MAGE") and YR.RestockShoots("ROGUE"), "the ammo row: classes that shoot only")
    # a throwing weapon: more of the same one, counting the stack in your hand
    lua.execute('''CLASS = 'ROGUE' BOUGHT = {} COUNT = { [2947] = 20 }
        ITEMS[2947] = { 2, 16, "INVTYPE_THROWN", 1, {} }
        WORN = { [18] = "|Hitem:2947|h" }
        function GetInventoryItemCount(_, s) return s == 18 and 30 or 0 end
        VENDOR = { { 2947, 5, 1 }, { 2512, 10, 200 } }''')
    YR.Restock(False)
    check(bought() == [(2947, 150)], f"a rogue with throwing knives: the same knives up to 200, counting the 30 held: {bought()}")
    lua.execute("GetInventoryItemCount = nil WORN = {}")

    # ---- Reminders ---------------------------------------------------------------------------
    lua.execute("CLASS = 'PALADIN' KNOWN = {} PRINTS = {}")
    pal = YR.TrainerSpells.PALADIN
    by = {}
    for i in range(1, len(pal) + 1):
        e = pal[i]
        by.setdefault((e[3], e[4]), e[1])
    for key in (("Holy Light", 1), ("Devotion Aura", 1), ("Seal of Righteousness", 1), ("Blessing of Might", 1)):
        if key in by:
            g.KNOWN[by[key]] = True
    # a race variant of rank 1 the data may carry for another race: know every rank 1 of Holy Light
    for i in range(1, len(pal) + 1):
        if pal[i][3] == "Holy Light" and pal[i][4] == 1:
            g.KNOWN[pal[i][1]] = True
    miss = YR.TrainerMissing(6)
    names = sorted((miss[i].name, miss[i].rank) for i in range(1, len(miss) + 1))
    check(("Holy Light", 2) in names, f"level 6: Holy Light 2 is new: {names}")
    check(("Holy Light", 1) not in names and ("Blessing of Might", 1) not in names, "what you know isn't listed")
    check(not any(n == "Consecration" for n, _ in names), "a talent spell is never listed without the talent")
    # a client that forgets rank 1 once rank 2 is learned: rank 1 must not come back as missing
    for i in range(1, len(pal) + 1):
        if pal[i][3] == "Holy Light" and pal[i][4] == 1:
            g.KNOWN[pal[i][1]] = None
    g.KNOWN[by[("Holy Light", 2)]] = True
    miss = YR.TrainerMissing(6)
    names = sorted((miss[i].name, miss[i].rank) for i in range(1, len(miss) + 1))
    check(("Holy Light", 1) not in names and ("Holy Light", 2) not in names, f"rank 2 known, rank 1 dropped: neither listed: {names}")

    # a dwarf whose Holy Light 1 is a spell the data doesn't list for dwarves: rank 2 is still offered
    for i in range(1, len(pal) + 1):
        if pal[i][3] == "Holy Light":
            g.KNOWN[pal[i][1]] = None
    miss = YR.TrainerMissing(6)
    names = sorted((miss[i].name, miss[i].rank) for i in range(1, len(miss) + 1))
    check(("Holy Light", 2) in names, f"rank 1 another race's copy: rank 2 still offered: {names}")
    check(not any(n == "Holy Shock" for n, _ in YR_names(YR.TrainerMissing(60))), "talent: Holy Shock 2 not without rank 1")
    g.KNOWN[by[("Holy Light", 2)]] = True

    # prices from a trainer visit
    lua.execute("SERVICES = { { 'Holy Strike', 'Rank 1', 100 }, { 'Divine Protection', 'Rank 1', 150 } }")
    YR.TrainerService = lua.eval("function(i) return SERVICES[i][1], SERVICES[i][2], 'available' end")   # Trainer.lua's
    YR.StartReminders()
    g.Fire("TRAINER_SHOW")
    line = YR.TrainerLine(6)
    check(line and "Holy Strike 1" in line and "about" in line, f"the trainer line names spells and a price: {line}")

    lua.execute("PRINTS = {} UNSPENT = 2")
    g.Fire("PLAYER_LEVEL_UP", 12)
    lua.execute("RunAfter()")
    check(g.SHOTS == 1, "a screenshot at the ding")
    check(any("2 talent points to spend" in p for p in prints()), f"unspent talents are mentioned: {prints()}")
    check(any("new at your class trainer" in p for p in prints()), "and the trainer")
    g.YippRouteDB.levelShot = False
    g.YippRouteDB.remindTalents = False
    lua.execute("PRINTS = {}")
    g.Fire("PLAYER_LEVEL_UP", 13)
    lua.execute("RunAfter()")
    check(g.SHOTS == 1 and not any("talent" in p for p in prints()), "settings off: no screenshot, no talent line")

    # durability: once under the line, again only after a repair; "repair here" coming into town
    lua.execute("PRINTS = {} DUR = { [1] = { 50, 100 }, [5] = { 20, 100 } }")
    g.Fire("UPDATE_INVENTORY_DURABILITY")
    g.Fire("UPDATE_INVENTORY_DURABILITY")
    check(sum("down to 20%" in p for p in prints()) == 1, f"warned once at 20%: {prints()}")
    lua.execute("RESTING = true")
    g.Fire("PLAYER_UPDATE_RESTING")
    check(any("repair while you're here" in p for p in prints()), "coming into town under 50%: repair here")
    lua.execute("RESTING = false PRINTS = {} DUR = { [5] = { 100, 100 } }")
    g.Fire("UPDATE_INVENTORY_DURABILITY")
    lua.execute("DUR = { [5] = { 10, 100 } }")
    g.Fire("UPDATE_INVENTORY_DURABILITY")
    check(sum("down to 10%" in p for p in prints()) == 1, "after a repair it warns again")

    # ---- Upgrades ----------------------------------------------------------------------------
    lua.execute('''CLASS = 'WARRIOR' LEVEL = 10 PRINTS = {}
        ITEMS[100] = { 4, 3, "INVTYPE_CHEST", 1, { RESISTANCE0_NAME = 50 } }                    -- worn: white mail
        ITEMS[101] = { 4, 3, "INVTYPE_CHEST", 2, { RESISTANCE0_NAME = 60, ITEM_MOD_STRENGTH_SHORT = 3 } }   -- green: better
        ITEMS[102] = { 4, 1, "INVTYPE_CHEST", 2, { RESISTANCE0_NAME = 20, ITEM_MOD_INTELLECT_SHORT = 6 } }  -- cloth int: worse
        ITEMS[103] = { 4, 4, "INVTYPE_CHEST", 1, { RESISTANCE0_NAME = 200 } }                  -- plate: red text
        ITEMS[104] = { 4, 3, "INVTYPE_HEAD", 3, { RESISTANCE0_NAME = 40 } }                    -- blue helm: over the limit
        ITEMS[105] = { 2, 1, "INVTYPE_2HWEAPON", 1, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 9 } } -- 2H
        ITEMS[106] = { 2, 0, "INVTYPE_WEAPON", 1, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 5 } }   -- worn MH
        ITEMS[107] = { 4, 6, "INVTYPE_SHIELD", 1, { RESISTANCE0_NAME = 300 } }                 -- worn shield
        WORN = { [5] = "|Hitem:100|h", [16] = "|Hitem:106|h", [17] = "|Hitem:107|h" }
        BAGS = { [1] = { "|Hitem:101|h[Green Vest]|h" }, [2] = { "|Hitem:102|h" }, [3] = { "|Hitem:103|h", true },
                 [4] = { "|Hitem:104|h" } }''')
    YR.StartUpgrades()
    YR.ScanUpgrades()
    told = prints()
    check(any("Green Vest" in p for p in told), f"the better green vest is mentioned: {told}")
    check(len(told) == 1, f"only it: cloth scores lower, plate is red, the blue is over the limit: {told}")
    check(g.HeadstartUpgradeFrame is not None and g.HeadstartUpgradeFrame.IsShown(g.HeadstartUpgradeFrame),
          "the Equip window shows")
    YR.ScanUpgrades()
    check(len(prints()) == 1, "once per item")
    # an item found no upgrade isn't looked at again on the next loot
    lua.eval("function(YR) CHECKS = 0 local real = YR.CheckUpgrade YR.CheckUpgrade = function(...) CHECKS = CHECKS + 1 return real(...) end end")(YR)
    YR.ScanUpgrades()
    check(lua.eval("CHECKS") == 0, f"the next loot: items already looked at are skipped ({lua.eval('CHECKS')} looked at again)")
    g.YippRouteDB.upgradeQuality = 3
    YR.ScanUpgrades()
    check(not any("Hitem:104" in p for p in prints()), "a setting changed behind the window's back: still the kept answer")
    YR.UpgradesForget()          # what the Settings dropdown does
    YR.ScanUpgrades()
    check(any("Hitem:104" in p for p in prints()), "Up to blue: the blue helm (empty head slot) is mentioned")
    # a belt with 6 more armor and nothing less: a tiny gain, but free, so it's offered (not held to the 2%)
    sim = lua.eval("""function(YR, pct, tough)
        local real = YR.SimCompare
        YR.SimCompare = function() return { pct = pct, tough = tough, slot = 5, old = "|Hitem:9|h", role = "melee", word = "DPS" } end
        local old = YR.CheckUpgrade(0, 1)
        YR.SimCompare = real
        return old
    end""")
    check(sim(YR, 0, 0.7) is not None, "+0.0% DPS, +0.7% toughness: offered, nothing gets worse")
    check(sim(YR, -1, 3) is None, "-1% DPS for +3% toughness: under the 2%, not offered")
    check(sim(YR, 0, 0) is None, "no change at all: not offered")
    # a shield where you wield a two-hander: never offered, however the sim scores it
    lua.execute('''WORN = { [16] = "|Hitem:105|h" } BAGS = { [1] = { "|Hitem:107|h[Buckler]|h" } }''')
    check(sim(YR, 5, 10) is None and YR.CheckUpgrade(0, 1) is None, "a shield over the two-hander: not offered")
    lua.execute('''WORN = { [16] = "|Hitem:106|h" }''')
    check(sim(YR, 0, 3) is not None, "a shield beside a one-hander still is")
    lua.execute('''WORN = { [5] = "|Hitem:100|h", [16] = "|Hitem:106|h", [17] = "|Hitem:107|h" }
        BAGS = { [1] = { "|Hitem:101|h[Green Vest]|h" } }''')
    # two pairs of boots from one quest: one window, for the better pair
    win = g.HeadstartUpgradeFrame
    lua.execute('''ITEMS[120] = { 4, 1, "INVTYPE_FEET", 1, { RESISTANCE0_NAME = 10 } }
        ITEMS[121] = { 4, 3, "INVTYPE_FEET", 1, { RESISTANCE0_NAME = 34 } }
        ITEMS[122] = { 4, 1, "INVTYPE_FEET", 1, { RESISTANCE0_NAME = 20 } }
        ITEMS[123] = { 4, 1, "INVTYPE_FEET", 1, { RESISTANCE0_NAME = 30 } }
        WORN[8] = "|Hitem:120|h"
        BAGS = { [1] = { "|Hitem:122|h[Frayed Shoes]|h" }, [2] = { "|Hitem:121|h[Flimsy Chain Boots]|h" } }''')
    win.Hide(win)
    lua.execute("AFTER = {}")
    n0 = len(prints())
    YR.ScanUpgrades()
    said = prints()[n0:]
    check(len(said) == 1 and "Flimsy Chain Boots" in said[0], f"two boots for one slot: only the better pair is told ({said})")
    check(win.IsShown(win) and "121" in win.link, "and the window offers it")
    # a pair waiting behind the window, then better boots go on: the waiting pair is never shown
    lua.execute('''BAGS = { [1] = { "|Hitem:123|h[Old Boots]|h" } }''')
    YR.ScanUpgrades()
    prints()
    lua.execute('''WORN[8] = "|Hitem:121|h"''')    # you equip the chain boots
    win.Hide(win)
    lua.execute("RunAfter()")
    check(not win.IsShown(win), "the boots waiting behind it are worse than what you now wear: not shown")
    # Equip that doesn't go through (casting, eating, stunned): the offer comes back; in a fight: on after it
    lua.execute('''EQUIP_OK = false
        C_Item.EquipItemByName = function(link)
            if not EQUIP_OK then return end
            for k, v in pairs(BAGS) do if v[1] == link then BAGS[k] = nil end end
            WORN[8] = link
        end
        WORN[8] = "|Hitem:120|h"
        BAGS = { [1] = { "|Hitem:121|h[Flimsy Chain Boots]|h" } }''')
    boots = lua.eval('''{ link = "|Hitem:121|h[Flimsy Chain Boots]|h", slot = 8, better = 1 }''')
    win.Hide(win)
    lua.execute("AFTER = {}")
    YR.UpgradeEquip(boots)
    lua.execute("RunAfter()")
    check(win.IsShown(win) and "121" in win.link, "Equip didn't go through: the boots are offered again")
    win.Hide(win)
    lua.execute("AFTER = {} EQUIP_OK = true COMBAT = true")
    YR.UpgradeEquip(boots)
    check(lua.eval("WORN[8]") == "|Hitem:120|h", "Equip in a fight: nothing happens yet")
    lua.execute("COMBAT = false")
    g.Fire("PLAYER_REGEN_ENABLED")
    lua.execute("RunAfter()")
    check("121" in lua.eval("WORN[8]") and not win.IsShown(win), "the fight ends: the boots go on, and aren't offered again")
    lua.execute("WORN[8] = nil BAGS = {} EQUIP_OK = nil")
    lua.execute("WORN[8] = nil BAGS = {}")
    # a two-hander against main hand and shield together
    lua.execute('PRINTS = {} BAGS = { [1] = { "|Hitem:105|h" } }')
    YR.ScanUpgrades()
    c2 = YR.SimCompare("|Hitem:105|h")
    check(c2 is not None and c2.slot == 16 and (c2.pct + c2.tough / 4 >= 2) == any("Hitem:105" in p for p in prints()),
          f"2H weighed against main hand and shield together: {c2 and c2.pct}% DPS, {c2 and c2.tough}% toughness")
    g.YippRouteDB.upgrades = False
    lua.execute('PRINTS = {} BAGS = { [1] = { "|Hitem:101|h" } }')
    g.Fire("PLAYER_LEVEL_UP", 11)
    lua.execute("RunAfter()")
    check(not any("Hitem" in p for p in prints()), "upgrades off: nothing")
    g.YippRouteDB.upgrades = None

    # ---- Make it yourself ---------------------------------------------------------------------
    # a blacksmith with a sword, Rough and Coarse Sharpening Stone known, 3 Coarse Stone and 2 Rough Stone
    cons = {YR.Consumables[i][4]: YR.Consumables[i] for i in range(1, len(YR.Consumables) + 1)}
    lua.execute('''CLASS = 'WARRIOR' KNOWN = {} COUNT = {} PRINTS = {}
        ITEMS[2131] = { 2, 7, "INVTYPE_WEAPON", 1, {} }       -- a sword
        ITEMS[2132] = { 2, 4, "INVTYPE_WEAPON", 1, {} }       -- a mace
        WORN = { [16] = "|Hitem:2131|h" }''')
    g.KNOWN[cons[2862][1]] = True        # Rough Sharpening Stone
    g.KNOWN[cons[2863][1]] = True        # Coarse Sharpening Stone
    g.KNOWN[cons[3239][1]] = True        # Rough Weightstone
    g.COUNT[cons[2863][7][1]] = 3        # Coarse Stone
    g.COUNT[cons[2862][7][1]] = 2        # Rough Stone
    YR.StartCraftRemind()
    YR.CheckCrafts()
    said = prints()
    check(len(said) == 1 and "make 3 Item2863" in said[0] and "no sharpening stones" in said[0],
          f"a sword and mats: the best stone, how many, and no weightstone line: {said}")
    YR.CheckCrafts()
    check(len(prints()) == 1, "once")
    g.COUNT[2862] = 1                    # made a rough one: has a stone now
    YR.CheckCrafts()
    g.COUNT[2862] = 0                    # used it: tell again
    YR.CheckCrafts()
    check(len(prints()) == 2, f"after having one and running out, again: {prints()}")
    lua.execute("PRINTS = {} WORN = { [16] = '|Hitem:2132|h' }")
    YR.CheckCrafts()
    check(any("Item3239" in p for p in prints()), f"a mace: weightstones instead: {prints()}")
    def forget():                        # have a weightstone for a moment, so the next run-out tells again
        g.COUNT[3239] = 1
        YR.CheckCrafts()
        g.COUNT[3239] = 0
        lua.execute("PRINTS = {}")
    forget()
    g.COUNT[cons[3239][7][1]] = 0
    g.COUNT[2836] = 0
    g.COUNT[2835] = 0
    YR.CheckCrafts()
    check(prints() == [], "no mats: nothing")
    g.COUNT[2835] = 5
    g.KNOWN[cons[3239][1]] = None
    forget()
    YR.CheckCrafts()
    check(prints() == [], "mats but no recipe: nothing")
    g.KNOWN[cons[3239][1]] = True
    g.YippRouteDB.craftStones = False
    forget()
    YR.CheckCrafts()
    check(prints() == [], "stones off: nothing")
    g.YippRouteDB.craftStones = None
    forget()
    YR.CheckCrafts()
    check(any("Item3239" in p for p in prints()), "and with the recipe, mats and stones on, it does tell")
    g.YippRouteDB.craftStones = None
    lua.execute("WORN = {}")

    # ---- Quick group --------------------------------------------------------------------------
    YR.StartQuickGroup()
    gbar = g.HeadstartGroupBar
    check(gbar is not None and gbar.IsShown(gbar), "the Invite / Leave bar shows")
    def invited():
        return [g.INVITED[i] for i in range(1, len(g.INVITED) + 1)]
    lua.execute("TARGET = { player = true, name = 'Tagger' } INVITED = {} PARTY = {}")
    YR.InviteTarget()
    check(invited() == ["Tagger"], f"Invite asks the target: {invited()}")
    lua.execute("INVITED = {} INGROUP = true LEADER = false")
    YR.InviteTarget()
    check(invited() == [], "not the leader: no invite")
    lua.execute("LEADER = true MEMBERS = 5")
    YR.InviteTarget()
    check(invited() == [], "a full group: no invite")
    lua.execute("MEMBERS = 2 TARGET = { player = false, name = 'Boar' }")
    YR.InviteTarget()
    check(invited() == [], "a mob: no invite")
    YR.LeaveGroup()
    check(g.LEFT == 1, "Leave group leaves")
    lua.execute("INGROUP = false LEADER = false MEMBERS = 1")
    YR.LeaveGroup()
    check(g.LEFT == 1, "not in a group: nothing to leave")
    g.Headstart_InviteTarget()      # the key binding
    lua.execute("TARGET = { player = true, name = 'Tagger' } INVITED = {}")
    g.Headstart_InviteTarget()
    check(invited() == ["Tagger"], "the key binding invites too")

    # whispers: the word, from guildies and friends by default
    lua.execute("INVITED = {} GUILD = {} FRIENDS = { Friend = true }")
    def whisper(text, name):
        g.Fire("CHAT_MSG_WHISPER", text, name, "", "", "", "", 0, 0, "", 0, 1, "Player-" + name)
    whisper("inv", "Friend")
    whisper(" INV ", "Friend2")
    whisper("inv please", "Friend")
    whisper("inv", "Stranger")
    check(invited() == ["Friend"], f"only a friend's exact 'inv': {invited()}")
    g.YippRouteDB.whisperInvite = "anyone"
    lua.execute("INVITED = {}")
    whisper("inv", "Stranger")
    check(invited() == ["Stranger"], "anyone: the stranger too")
    g.YippRouteDB.whisperWord = "x"
    lua.execute("INVITED = {}")
    whisper("inv", "Stranger")
    whisper("X", "Stranger")
    check(invited() == ["Stranger"], "the word can be changed")
    g.YippRouteDB.whisperWord = None
    lua.execute("INVITED = {} SECRET['inv'] = true")
    whisper("inv", "Stranger")
    check(invited() == [], "a secret whisper (chat lockdown) is left alone")
    lua.execute("SECRET = {}")
    g.YippRouteDB.whisperInvite = None

    # invites: accepted from friends, the popup hidden as accepted (never declined)
    lua.execute("ACCEPTED = 0 POPUP = {} DECLINED = false")
    g.Fire("PARTY_INVITE_REQUEST", "Friend", False, False, True, True, False, "Player-Friend")
    check(g.ACCEPTED == 1 and g.POPUP is None and not g.DECLINED, "a friend's invite: joined, popup closed as accepted")
    lua.execute("ACCEPTED = 0 POPUP = {}")
    g.Fire("PARTY_INVITE_REQUEST", "Stranger", False, False, True, True, False, "Player-Stranger")
    check(g.ACCEPTED == 0 and g.POPUP is not None, "a stranger's invite: the game asks you")
    lua.execute("SHIFT = true")
    g.Fire("PARTY_INVITE_REQUEST", "Friend", False, False, True, True, False, "Player-Friend")
    lua.execute("SHIFT = false")
    check(g.ACCEPTED == 0, "Shift: asked anyway")
    g.YippRouteDB.acceptInvites = "anyone"
    g.Fire("PARTY_INVITE_REQUEST", "Stranger", False, False, True, True, False, "Player-Stranger")
    check(g.ACCEPTED == 1, "anyone: accepted")
    g.YippRouteDB.acceptInvites = None
    YR.SetGroupBar(False)
    check(not gbar.IsShown(gbar), "the bar can be turned off")
    lua.execute("TARGET = nil PARTY = {} GUILD = {} FRIENDS = {}")

    # ---- Gear sim --------------------------------------------------------------------------------
    lua.execute("CLASS = 'PALADIN' LEVEL = 20 TABS = nil YippRouteDB.simRole = nil")
    r = YR.SimRole()
    check(r.role == "melee" and r.spec is None, "no talents yet: a paladin levels as melee")
    lua.execute("TABS = { 11, 0, 2 }")
    r = YR.SimRole()
    check(r.role == "healer" and r.spec == "Holy", f"most points in Holy: healing ({r.role}, {r.spec})")
    lua.execute("TABS = { 0, 1, 14 }")
    r = YR.SimRole()
    check(r.role == "melee" and r.spec == "Retribution", "most points in Retribution: melee")
    lua.execute("YippRouteDB.simRole = 'tank'")
    check(YR.SimRole().role == "tank" and YR.SimRole().guessed is False, "set by hand: tanking")
    lua.execute("YippRouteDB.simRole = nil")
    lua.execute('''ITEMS[200] = { 4, 1, "INVTYPE_HEAD", 2, { RESISTANCE0_NAME = 10 } }
        TIPS["|Hitem:200|h"] = { "Equip: Increases damage and healing done by magical spells and effects by up to 12.",
            "Equip: Improves your chance to get a critical strike with spells by 1%." }
        ITEMS[201] = { 2, 7, "INVTYPE_WEAPONMAINHAND", 2, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 12 } }
        TIPS["|Hitem:201|h"] = { "Speed 2.60" }
        ITEMS[202] = { 2, 7, "INVTYPE_WEAPONMAINHAND", 1, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 6 } }
        ITEMS[203] = { 4, 4, "INVTYPE_CHEST", 2, { RESISTANCE0_NAME = 400, ITEM_MOD_STAMINA_SHORT = 10 } }
        ITEMS[204] = { 4, 4, "INVTYPE_CHEST", 1, { RESISTANCE0_NAME = 200 } }
        WORN = { [16] = "|Hitem:202|h", [5] = "|Hitem:204|h" }''')
    st = YR.SimItemStats("|Hitem:200|h")
    check(st.sp == 12 and st.scrit == 1 and st.armor == 10, f"Equip: lines read: spell power {st.sp}, spell crit {st.scrit}")
    check(YR.SimItemStats("|Hitem:201|h").speed == 2.6, "a weapon's speed from its tooltip")
    c = YR.SimCompare("|Hitem:201|h")
    check(c.role == "melee" and c.pct > 5 and c.slot == 16, f"Retribution: a 12 DPS sword over a 6 DPS one is a lot more DPS ({c.pct:.1f}%)")
    line = YR.SimLine(c)
    check(line.startswith("+") and "DPS" in line and "(Retribution)" in line, f"the tooltip line: {line}")
    c = YR.SimCompare("|Hitem:200|h")
    check(c.pct > 0, f"Retribution: spell power adds to a paladin's melee (seals, Judgement) ({c.pct:.1f}%)")
    lua.execute("CLASS = 'WARRIOR' TABS = nil")
    c = YR.SimCompare("|Hitem:200|h")
    check(abs(c.pct) < 0.01, f"a warrior: spell power does nothing for melee DPS ({c.pct})")
    lua.execute("CLASS = 'PALADIN' TABS = { 0, 1, 14 }")
    # a two-hander worn: a one-hander comes with the best off hand in your bags, as the game compares it
    lua.execute('''ITEMS[210] = { 2, 5, "INVTYPE_2HWEAPON", 2, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 18, ITEM_MOD_STAMINA_SHORT = 8 } }
        ITEMS[211] = { 2, 4, "INVTYPE_WEAPONMAINHAND", 2, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10 } }
        ITEMS[212] = { 4, 6, "INVTYPE_SHIELD", 2, { RESISTANCE0_NAME = 547 } }
        ITEMS[213] = { 2, 5, "INVTYPE_2HWEAPON", 2, { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 16 } }
        TIPS["|Hitem:213|h"] = { "Chance on hit: Blasts a target for 42 Fire damage." }
        WORN = { [16] = "|Hitem:210|h" }
        BAGS = { [1] = { "|Hitem:212|h[Seedcloud Buckler]|h" } }''')
    c = YR.SimCompare("|Hitem:211|h")
    check(c["with"] is not None and "212" in c["with"] and c.tough > 0,
          f"a one-hander over the two-hander: with the shield from your bags, so its armor counts ({c.tough:.1f}% toughness)")
    check(", with " in YR.SimLine(c), f"and the line says so: {YR.SimLine(c)}")
    # the shield itself, against the two-hander: the two-hander comes off, so the sword from your bags goes in
    lua.execute('''BAGS = { [1] = { "|Hitem:211|h[Scepter]|h" } }''')
    c = YR.SimCompare("|Hitem:212|h")
    check(c["with"] is not None and "211" in c["with"] and c.pct < 0,
          f"a shield over the two-hander: with the one-hander from your bags, and the two-hander's DPS gone ({c.pct:.1f}%)")
    lua.execute("BAGS = {}")
    c = YR.SimCompare("|Hitem:212|h")
    check(c["with"] is None and c.bare and c.pct < -50 and "no main hand" in YR.SimLine(c),
          f"no one-hander in your bags: with no main hand at all ({c.pct:.1f}%)")
    lua.execute('''BAGS = { [1] = { "|Hitem:212|h[Seedcloud Buckler]|h" } }''')
    lua.execute("BAGS[1][2] = true")      # the shield is red to you (can't use shields)
    c = YR.SimCompare("|Hitem:211|h")
    check(c["with"] is None, "a shield you can't use is left out")
    lua.execute("BAGS = {}")
    check(abs(YR.SimItemStats("|Hitem:213|h").procdps - 0.7) < 1e-6, "Chance on hit: 42 damage at about one proc a minute")
    c1 = YR.SimCompare("|Hitem:213|h")
    lua.execute("TIPS['|Hitem:213|h'] = nil")
    YR.SimForget()                           # drops the item stats the sim kept
    c2 = YR.SimCompare("|Hitem:213|h")
    check(c1.pct > c2.pct, f"a proc weapon is weighed with its proc ({c1.pct:.1f}% with, {c2.pct:.1f}% without)")
    lua.execute('''WORN = { [16] = "|Hitem:202|h", [5] = "|Hitem:204|h" }''')
    lua.execute("CLASS = 'MAGE' TABS = nil")
    c = YR.SimCompare("|Hitem:200|h")
    check(c.role == "caster" and c.pct > 0 and c.word == "damage", f"a mage: +12 spell power is more damage ({c.pct:.1f}%)")
    lua.execute("CLASS = 'WARRIOR' TABS = nil YippRouteDB.simRole = 'tank'")
    c = YR.SimCompare("|Hitem:203|h")
    check(c.role == "tank" and c.tough > 0 and "toughness" in YR.SimLine(c), f"a tank: more armor and stamina is toughness ({c.tough:.1f}%)")
    lua.execute("YippRouteDB.simRole = nil")
    # the tooltip line, and none on what you already wear
    tip = lua.eval('''function(link)
        local t = { lines = {} }
        function t.GetItem() return "x", link end
        function t.AddLine(self, text) table.insert(self.lines, text) end
        function t.Show() end
        return t
    end''')
    g.GameTooltip = tip("|Hitem:201|h")
    YR.StartSim()
    for i in range(1, len(g.POSTCALLS) + 1):
        g.POSTCALLS[i](g.GameTooltip)
    tl = [g.GameTooltip.lines[i] for i in range(1, len(g.GameTooltip.lines) + 1)]
    check(len(tl) == 1 and tl[0].startswith("Headstart: +") and "DPS" in tl[0], f"item tooltips get the line: {tl}")
    g.GameTooltip = tip("|Hitem:202|h")
    for i in range(1, len(g.POSTCALLS) + 1):
        g.POSTCALLS[i](g.GameTooltip)
    check(len(g.GameTooltip.lines) == 0, "not on what you wear already")
    g.YippRouteDB.simTooltip = False
    g.GameTooltip = tip("|Hitem:201|h")
    for i in range(1, len(g.POSTCALLS) + 1):
        g.POSTCALLS[i](g.GameTooltip)
    check(len(g.GameTooltip.lines) == 0, "tooltip line off: nothing")
    g.YippRouteDB.simTooltip = None
    line = YR.SimLine(lua.eval('{ pct = 0, tough = 4, role = "melee", word = "DPS" }'))
    check(line == "+4.0% toughness", f"armor only: no '+0.0% DPS' in front ({line})")
    line = YR.SimLine(lua.eval('{ pct = 0, tough = 0, role = "melee", word = "DPS" }'))
    check(line == "+0.0% DPS", f"nothing at all still says so ({line})")
    # the tooltip's kept answer: the same until something changes, then worked out again
    same = lua.eval("rawequal")
    YR.SimForget()
    k1 = YR.SimCompareKept("|Hitem:201|h")
    lua.execute("STATS.ap = STATS.ap + 500")
    check(same(YR.SimCompareKept("|Hitem:201|h"), k1), "a tooltip refresh: the kept answer, nothing worked out again")
    g.YippRouteDB.simRole = "tank"
    k3 = YR.SimCompareKept("|Hitem:201|h")
    check(not same(k3, k1) and k3.role == "tank", "the role set by hand: worked out again for it")
    g.YippRouteDB.simRole = None
    YR.SimForget()
    check(not same(YR.SimCompareKept("|Hitem:201|h"), k1), "gear changed: worked out again")
    lua.execute("STATS.ap = STATS.ap - 500")
    # in a fight the numbers are secret: the last ones read stand in
    lua.execute("YR_SNAP = nil")
    before = YR.SimSnapshot()
    lua.execute("COMBAT = true STATS.ap = 99999")
    check(YR.SimSnapshot().ap == before.ap, "in combat: the last numbers read out of combat")
    lua.execute("COMBAT = false STATS.ap = 100 WORN = {}")

    # ---- Party quests ------------------------------------------------------------------------
    lua.execute("PARTY = { Guildie = true, Friend = true, Stranger = true } GUILD = { Guildie = true } FRIENDS = { Friend = true }")
    def accepts(name):
        g.NPCNAME = name
        return bool(YR.AcceptSharedBy("npc"))
    check(accepts("Guildie") and accepts("Friend") and not accepts("Stranger"), "default: guildies and friends only")
    check(not accepts("Outsider"), "never someone outside the party")
    g.YippRouteDB.acceptFrom = "party"
    check(accepts("Stranger"), "anyone in my party")
    g.SHIFT = True
    check(not accepts("Stranger"), "Shift: asked anyway")
    g.SHIFT = False
    g.YippRouteDB.acceptFrom = "off"
    check(not accepts("Guildie"), "nobody")
    check(not YR.ShareAll(), "sharing every quest is off until turned on")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
