"""Smoke test of Characters (Alts.lua): what your other characters carry, have banked and own.

    python tools/smoke_alts.py      (exit code 1 on any failure; tools/smoke.py runs it too)

In Lua 5.1 (lupa), against a small fake of the game: bags, a bank, money, currencies.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r"""
NOW, PARTS, SAID, LATER, READS, EVENTS = 5000, {}, {}, {}, 0, {}
ME, CLASS, LEVEL, MONEY = "Anna", "MAGE", 22, 123456
function time() return NOW end
function UnitFullName() return ME, "Realm" end
function GetRealmName() return "Realm" end
function UnitClass() return "x", CLASS end
function UnitLevel() return LEVEL end
function UnitFactionGroup() return "Alliance" end
function GetMoney() return MONEY end
function InCombatLockdown() return false end
BAGS = { [0] = { { 2589, 20 }, { 2589, 5 }, false, { 4306, 3 } },
    [1] = { { 6948, 1 }, { 5075, 4 }, { 2901, 1, true }, { 4540, 10 }, { 1210, 2 }, { 3300, 1 } } }
C_Container = {
    GetContainerNumSlots = function(bag) return BAGS[bag] and #BAGS[bag] or 0 end,
    GetContainerItemID = function(bag, slot) READS = READS + 1 local s = BAGS[bag] and BAGS[bag][slot] return s and s[1] or nil end,
    GetContainerItemInfo = function(bag, slot) local s = BAGS[bag][slot] return s and { stackCount = s[2], isBound = s[3] == true } end,
}
CURRENCIES = { { isHeader = true, name = "Misc" }, { currencyID = 77, name = "Honor", quantity = 300, iconFileID = 1 }, { currencyID = 78, name = "None", quantity = 0 } }
C_CurrencyInfo = { GetCurrencyListSize = function() return #CURRENCIES end, GetCurrencyListInfo = function(i) return CURRENCIES[i] end }
KINDS = { [2589] = { 7, 5 }, [4306] = { 7, 5 }, [2592] = { 7, 5 }, [4540] = { 0, 5 }, [5075] = { 12, 0 }, [2901] = { 2, 0 }, [1210] = { 7, 4 }, [3300] = { 15, 0 } }
QUALITY = { [3300] = 0, [1210] = 2 }
C_Item = {
    GetItemNameByID = function(id) return ({ [2589] = "Linen Cloth", [4306] = "Silk Cloth", [6948] = "Hearthstone", [2592] = "Wool Cloth",
        [4540] = "Tough Hunk of Bread", [2901] = "Mining Pick", [1210] = "Shadowgem", [3300] = "Rabbit's Foot" })[id] end,
    GetItemInfoInstant = function(id) local k = KINDS[id] or { 15, 0 } return id, "", "", "", 1, k[1], k[2] end,
    GetItemQualityByID = function(id) return QUALITY[id] or 1 end,
}
C_Timer = { After = function(s, fn) LATER[#LATER + 1] = fn end }
GameTooltip = { lines = {} }
function GameTooltip:AddDoubleLine(a, b) self.lines[#self.lines + 1] = a .. " = " .. b end
YippRouteDB = { alts = true }
local F = { RegisterEvent = function(self, e) EVENTS[e] = true end, UnregisterEvent = function(self, e) EVENTS[e] = nil end }
YR = {
    Option = function(k) return YippRouteDB[k] == true end,
    Print = function(s) SAID[#SAID + 1] = s end,
    CharKey = function() return ME .. "-Realm" end,
    Part = function(want, events, handler, opt) PARTS[#PARTS + 1] = { want = want, events = events, handler = handler, opt = opt, frame = F } end,
}
"""


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    YR = lua.eval("YR")
    # the one function of Core.lua this needs, as it is written there: how money is put into words
    core = open(os.path.join(ROOT, "Core.lua"), encoding="utf-8").read().replace("\r\n", "\n")
    at = core.index("function YR.Money(copper)")
    lua.execute(core[at:core.index("\nend\n", at) + 5])
    lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, "Alts.lua"), encoding="utf-8").read(), "Alts.lua")("Headstart", YR)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    lua.execute("""GameTooltip.said = {} function GameTooltip:AddLine(t) self.said[#self.said + 1] = t end
        TIP = nil TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) TIP = fn end }
        Enum = { TooltipDataType = { Item = 0 } }""")
    YR.StartAlts()
    part = g.PARTS[1]
    check("PLAYER_LOGOUT" not in list(part.events.values()) and "PLAYER_MONEY" in list(part.events.values()) and part.want() is True,
          "listened for: your gold, your bags, the bank's window - not the logout (the game has let go of it all by then)")
    g.YippRouteDB.alts = None
    check(part.want() is False and g.HeadstartAlts is None, "off: nothing listened for, nothing noted")
    g.YippRouteDB.alts = True
    part.opt.start(part)
    check(g.READS == 0 and len(g.LATER) == 1, "coming on: your bags aren't read at once - a little after the login")
    lua.execute("LATER[1]()")
    me = g.HeadstartAlts["Anna-Realm"]
    check(me.name == "Anna" and me["class"] == "MAGE" and me.level == 22 and me.money == 123456 and me.seen == 5000,
          "this character is noted: who, level, gold, when")
    check(me.bags[2589] == 25 and me.bags[4306] == 3 and me.bags[4540] == 10, "its bags as item and count, stacks of one item together")
    check(me.bags[6948] is None and me.bags[5075] is None and me.bags[2901] is None,
          "the hearthstone, a quest's item and what is bound to the character aren't noted")
    check(len(me.cur) == 1 and me.cur[1].name == "Honor" and me.cur[1].qty == 300, "its currencies, the ones it has any of")
    reads = g.READS
    check(reads == 10, f"one look at each slot ({reads})")

    # the bank, while its window is open
    lua.execute("BAGS[6] = { { 2592, 40 }, { 2589, 100 } } BAGS[15] = { { 4306, 7 } }")
    part.handler(None, "BANKFRAME_OPENED")
    check(me.bank[2592] is None, "the bank opens: looked at a moment on")
    lua.execute("LATER[#LATER]()")
    check(me.bank[2592] == 40 and me.bank[2589] == 100 and me.bankSeen == 5000, "the bank is noted")
    check(g.HeadstartAlts["*account"].bank[4306] == 7, "and the account's bank, as a character of its own")
    lua.execute("BAGS[6][1][2] = 60")
    part.handler(None, "BAG_UPDATE_DELAYED")
    lua.execute("LATER[#LATER]()")
    check(me.bank[2592] == 60, "something moved while it is open: noted again")
    part.handler(None, "BANKFRAME_CLOSED")
    lua.execute("BAGS[6] = nil")
    YR.AltsNoteBank()
    check(me.bank[2592] == 60, "the bank out of reach: what was noted of it stays")
    # as it happens: gold at once, bags a few seconds after the last change, not in a fight
    g.MONEY = 200000
    part.handler(None, "PLAYER_MONEY")
    check(me.money == 200000, "your gold changes: noted at once")
    lua.execute("LATER = {} BAGS[0][3] = { 1210, 5 }")
    reads = g.READS
    for _ in range(5):
        part.handler(None, "BAG_UPDATE_DELAYED")
    check(len(g.LATER) == 1 and g.READS == reads, "five changes to your bags: nothing read yet, one look to come")
    lua.execute("function InCombatLockdown() return true end LATER[1]()")
    check(g.READS == reads and g.EVENTS["PLAYER_REGEN_ENABLED"] is True, "in a fight when it comes: not read, the end of the fight waited for")
    lua.execute("function InCombatLockdown() return false end LATER = {}")
    part.handler(None, "PLAYER_REGEN_ENABLED")
    lua.execute("LATER[1]()")
    me = g.HeadstartAlts["Anna-Realm"]
    check(me.bags[1210] == 7 and g.EVENTS["PLAYER_REGEN_ENABLED"] is None, "after it: your bags as they are now")
    # the game not ready (no bag to look in, as at the logout): what was noted stays
    lua.execute("KEPT = BAGS BAGS = {}")
    YR.AltsNote()
    check(g.HeadstartAlts["Anna-Realm"].bags[2589] == 25, "no bag at all to look in: what was noted stays")
    lua.execute("BAGS = KEPT")

    # another character logs in
    lua.execute("ME, CLASS, LEVEL, MONEY = 'Bo', 'WARRIOR', 8, 5000 NOW = 9000 BAGS = { [0] = { { 2589, 2 } } } CURRENCIES = {}")
    YR.AltsNote()
    bo = g.HeadstartAlts["Bo-Realm"]
    check(bo.name == "Bo" and bo.bags[2589] == 2 and bo.cur is None, "another character plays: noted as it is")
    who = YR.AltsHave(2589)
    by = {e.key: (e.bags, e.bank) for e in who.values()}
    check(by == {"Anna-Realm": (25, 100)}, f"who else has an item: your other characters, bags and bank apart - not yourself ({by})")
    check({e.key: e.bank for e in YR.AltsHave(4306).values()} == {"Anna-Realm": 0, "*account": 7}, "the account's bank among them")
    check(YR.AltsHave(99999) is None, "an item none of them has: nothing")
    total, gold = YR.AltsGold()
    check(total == 205000 and [c.name for c in gold.values()] == ["Anna", "Bo"], f"your gold in all, the richest first ({total})")
    g.MONEY = 7000
    check(YR.AltsGold() and YR.AltsGold()[0] == 207000, "the one you're on by what it has now")
    names = [c.name for c in YR.AltsList().values()]
    check(names == ["Bo", "Anna"], f"your characters: the one you're on first ({names})")
    check(YR.AltsCoins(123456) == "12g 34s 56c" and YR.AltsCoins(250) == "2s 50c" and YR.AltsCoins(7) == "7c", "money in words")

    # what is worth showing
    check(YR.AltsUseful(2589) and not YR.AltsUseful(4540) and not YR.AltsUseful(3300), "food, drink and grey items aren't shown")
    lua.execute("TIP(GameTooltip, { id = 2589 }) TIP(GameTooltip, { id = 4540 }) TIP(GameTooltip, { id = 4306 })")
    said = list(g.GameTooltip.said.values())
    check(len(said) == 3 and said[0].endswith("Anna|r: 25x, bank 100x") and any(x.endswith("Account bank|r: 7x") for x in said),
          f"an item's tooltip: who has it and how many - nothing for food ({said})")
    g.YippRouteDB.altsAll = True
    check(YR.AltsUseful(4540) and YR.AltsUseful(3300), "'Everything': those too")
    g.YippRouteDB.altsAll = None
    # the window's lists
    items = list(YR.AltsItems("*all").values())
    check(items[0].item == 1210 and items[0].quality == 2 and items[0].cat == 1 and items[0].bags == 7 and items[1].item == 2589 and items[1].bags == 27
          and items[1].bank == 100 and items[1].who["Bo-Realm"] and items[1].who["Anna-Realm"],
          "all characters: each item once, summed, with who has it - by kind, the finest first, then the most of")
    check(not any(e.item in (4540, 3300) for e in items), "food and grey items left out of the window too")
    one = list(YR.AltsItems("Anna-Realm", "wool").values())
    check(len(one) == 1 and one[0].item == 2592 and one[0].bank == 60, "one character, searched by name")
    check(len(list(YR.AltsItems("*all", "no such thing").values())) == 0, "a search that finds nothing")

    YR.AltsForget("Anna-Realm")
    check(g.HeadstartAlts["Anna-Realm"] is None and YR.AltsHave(2592) is None, "a character forgotten: gone, and from what the tooltips say")
    YR.AltsForget()
    check(len(list(g.HeadstartAlts.keys())) == 0, "all of them forgotten")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
