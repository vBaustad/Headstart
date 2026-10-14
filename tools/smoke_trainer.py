"""Smoke test of the auto trainer (Trainer.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_trainer.py      (exit code 1 on any failure; tools/smoke.py runs it too)
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
FRAMES = {}
local F = {}
F.__index = F
function F:RegisterEvent(e) self.ev = self.ev or {} self.ev[e] = true end
function F:SetScript(_, fn) self.fn = fn end
function F:UnregisterAllEvents() self.ev = nil end
function F:Show() self.shown = true end
function F:Hide() self.shown = false end
function F:SetText(t) self.label = t end
setmetatable(F, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
function CreateFrame() local f = setmetatable({}, F) table.insert(FRAMES, f) return f end
function Fire(e) for _, f in ipairs(FRAMES) do if f.ev and f.ev[e] and f.fn then f.fn(f, e) end end end
C_Timer = { After = function(_, fn) fn() end }
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
floor = math.floor
YippRouteDB = { autoTrain = true }       -- off until you turn it on (checked below)
function UnitClass() return "Paladin", "PALADIN" end
LEVEL = 1
function UnitLevel() return LEVEL end
function UnitName() return nil end
SHIFT, TRADESKILL, MONEY, BOUGHT, PRINTS = false, false, 0, {}, {}
function IsShiftKeyDown() return SHIFT end
function IsTradeskillTrainer() return TRADESKILL end
function GetMoney() return MONEY end
-- the trainer's list: name, rank, category, cost, level
LIST = {}
function GetNumTrainerServices() return #LIST end
function GetTrainerServiceInfo(i) local s = LIST[i] return s[1], s[2], s[3] end
function GetTrainerServiceCost(i) return LIST[i][4] end
function GetTrainerServiceLevelReq(i) return LIST[i][5] end
function BuyTrainerService(i) table.insert(BOUGHT, LIST[i][1] .. " " .. LIST[i][2]) end
function GetTrainerServiceTypeFilter() return true end
RXP = { settings = { profile = { enableTrainerAutomation = true } } }
YippSetupCharDB = {}     -- (a character it has never bought on: it does not ask, below)
StaticPopupDialogs, POPUP = {}, nil
function StaticPopup_Show(which, text) POPUP = { which = which, text = text } end
-- what you wear: [slot] = { max durability, classID, subclassID, item level, quality, durability now }
GEAR = { [5] = { 100, 4, 2, 10, 2 } }    -- a green leather chest, item level 10: 100 points at 2 copper
function GetInventoryItemDurability(slot) local g = GEAR[slot] if g then return g[6] or g[1], g[1] end end
VENDOR = { 0, false }
function GetRepairAllCost() return VENDOR[1], VENDOR[2] end
function GetInventoryItemLink(_, slot) return GEAR[slot] and ("item:" .. slot) end
local function Worn(link) return GEAR[tonumber(link:match("%d+"))] end
function GetInventoryItemQuality(_, slot) return GEAR[slot] and GEAR[slot][5] end
C_Item = { GetDetailedItemLevelInfo = function(link) return Worn(link)[4] end,
    GetItemInfoInstant = function(link) local g = Worn(link) return 1, "", "", "", 0, g[2], g[3] end }
''')
    YR = lua.table()
    for f in ("Core.lua", "Data/TrainerSpells.lua", "Data/RepairCosts.lua", "Trainer.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    g = lua.globals()
    g.YRT = YR
    lua.execute('YRT.Print = function(m) table.insert(PRINTS, m) end')
    # Headstart's look, as far as the bar under the trainer's window uses it (its button's click kept)
    lua.execute("""YRT.Style = { C = {}, Fill = function() end, Border = function() end, Tip = function() end,
        Text = function() return CreateFrame() end,
        Button = function(_, _, fn) LEARN = fn return CreateFrame() end }""")
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    g.YippRouteDB.autoTrain = None
    check(YR.Option("autoTrain") is False, "auto-train is off until you turn it on")
    g.YippRouteDB.autoTrain = True

    def visit(money, shift=False, tradeskill=False):
        lua.execute(f"BOUGHT = {{}}; PRINTS = {{}}; MONEY = {money}; SHIFT = {'true' if shift else 'false'};"
                    f" TRADESKILL = {'true' if tradeskill else 'false'}")
        lua.execute("Fire('TRAINER_SHOW')")
        return [g.BOUGHT[i] for i in range(1, len(g.BOUGHT) + 1)]

    lua.execute('''LIST = {
        { "Seal of Righteousness", "Rank 2", "available", 600, 10 },
        { "Holy Light", "Rank 3", "available", 1000, 12 },
        { "Seal of the Crusader", "Rank 1", "available", 500, 6 },
        { "Hammer of Justice", "Rank 2", "unavailable", 2000, 24 },
        { "Lay on Hands", "Rank 1", "used", 0, 10 },
    }''')
    # the login: what is wanted comes on (Core does this at PLAYER_LOGIN)
    YR.partsReady = True
    YR.ApplyParts()
    # a new class table: "If I can afford it" for everything, a full repair of your gear kept, every level
    check(g.YRT.TrainerChoice("Holy Light") == "gold" and g.YRT.TrainerShare() == 50 and g.YRT.TrainerSave() == 0
          and g.YRT.TrainerUpTo() == 60 and g.YRT.TrainerKeep(1000) == 500 and g.YRT.TrainerKeep(0) == 200,
          "new defaults: If I can afford it, keep half the money (never under the chest's 2s repair), nothing saved, every level")
    got = visit(1700)
    check(got == ["Seal of the Crusader Rank 1"],
          f"17s: half (8s 50c) kept - the first seal, the second would leave 6s: {got}")
    # "first spells always": Always up to level 10, the rest stay If I can afford it
    lua.execute("""YRT.SetTrainerChoices({ "Seal of the Crusader", "Seal of Righteousness", "Holy Light", "Hammer of Justice" },
        "always", nil, { ["Seal of the Crusader"] = 6, ["Seal of Righteousness"] = 10, ["Holy Light"] = 12,
        ["Hammer of Justice"] = 24 }, 10)""")
    check(g.YRT.TrainerChoice("Seal of Righteousness") == "always" and g.YRT.TrainerChoice("Holy Light") == "gold",
          "Always up to level 10: the level-10 seal yes, Holy Light (12) no")
    got = visit(1200)
    check(got == ["Seal of the Crusader Rank 1", "Seal of Righteousness Rank 2"],
          f"12s: both Always spells, though that leaves 1s - under the reserve, which Always ignores: {got}")
    lua.execute("""YRT.SetTrainerChoices({ "Seal of the Crusader", "Seal of Righteousness", "Holy Light" }, "gold")""")
    check(g.YRT.TrainerChoice("Holy Light") == "gold" and g.YRT.TrainerData().spells["Holy Light"] is None,
          "All: If I can afford it - back to the default, nothing stored")
    # a table from before v2 keeps Always for what was left alone, and no reserve
    lua.execute("YippRouteDB.trainer.PALADIN = { reserve = 0, spells = {} }")
    check(g.YRT.TrainerChoice("Holy Light") == "always", "an older table: Always stays Always")
    check(g.RXP.settings.profile.enableTrainerAutomation is False and g.YippRouteDB.rxpTrainerWasOn,
          "RestedXP's trainer automation is off while ours is on")
    # logging out: RestedXP's own setting given back before its settings are saved (Headstart removed:
    # RestedXP has it as it was), and taken again at the next login
    lua.execute("Fire('PLAYER_LOGOUT')")
    check(g.RXP.settings.profile.enableTrainerAutomation is True and g.YippRouteDB.rxpTrainerWasOn is None,
          "logging out: RestedXP's trainer automation given back")
    lua.execute("YRT:SyncRxpTrainer()")
    check(g.RXP.settings.profile.enableTrainerAutomation is False and g.YippRouteDB.rxpTrainerWasOn,
          "the next login: off again while ours is on")
    got = visit(10000)
    check(got == ["Seal of the Crusader Rank 1", "Holy Light Rank 3", "Seal of Righteousness Rank 2"],
          f"everything available learned, bottom of the list first: {got}")
    check(any("learned" in g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)), "says what it learned")

    lua.execute('YRT.SetTrainerChoice("Seal of the Crusader", "never")')
    got = visit(10000)
    check("Seal of the Crusader Rank 1" not in got and len(got) == 2, f"a spell set to Never is left: {got}")

    # 16s: Holy Light (10s, Always) first; Seal of Righteousness (6s, If I can afford it) only while
    # 5s would be left: 16 - 10 - 6 = 0, below the reserve, so it waits
    lua.execute('YRT.SetTrainerChoice("Seal of Righteousness", "gold"); YRT.TrainerData().reserve = 500')
    got = visit(1600)
    check(got == ["Holy Light Rank 3"], f"Always first, the rest only above the reserve: {got}")
    check(any("the money you keep" in g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)), "says what it left for the money you keep")
    # under the trainer's window: what was left, and Learn them buys it, whatever is kept
    lua.execute("ClassTrainerFrame = {}")
    got = visit(1600)
    bar = lua.eval("(function() for _, f in ipairs(FRAMES) do if f.label and f.label:find('Left for later') then return f end end end)()")
    check(bar is not None and "Seal of Righteousness" in bar.label, f"the bar names what was left ({bar.label if bar else None})")
    lua.execute('LIST[2][3] = "used" BOUGHT = {} PRINTS = {}')        # (Holy Light learned a moment ago)
    g.LEARN()
    got = [g.BOUGHT[i] for i in range(1, len(g.BOUGHT) + 1)]
    check(got == ["Seal of Righteousness Rank 2"] and "learned Seal of Righteousness" in (g.PRINTS[1] or ""),
          f"Learn them: what was left, learned now, past the money kept ({got})")
    lua.execute('MONEY = 100 BOUGHT = {} PRINTS = {}')
    g.LEARN()
    check(len(g.BOUGHT) == 0 and "Not enough gold for: Seal of Righteousness" in (g.PRINTS[1] or ""),
          f"with too little gold: nothing bought, and said ({g.PRINTS[1]})")
    lua.execute('LIST[2][3] = "available" ClassTrainerFrame = nil')
    got = visit(2200)
    check(got == ["Holy Light Rank 3", "Seal of Righteousness Rank 2"], f"with 22s both: {got}")

    # what is kept: a share of the money you came with, never under a full repair of what you wear (the
    # game's repair prices), and a sum saved on top. A class that had a sum of its own keeps exactly that;
    # the 2 silver every class started with is the share now
    lua.execute("""GEAR = {
        [5] = { 100, 4, 2, 10, 2 },     -- the chest: 100 points at 2 copper
        [16] = { 85, 2, 8, 40, 3 },     -- a blue two-handed sword, item level 40: 85 points at 28 copper, times 1.25
        [11] = { nil, 4, 0, 60, 4 },    -- a ring: no durability, nothing to repair
    }""")
    check(g.YRT.RepairAllCost() == 200 + 2975, f"a full repair of what you wear ({g.YRT.RepairAllCost()})")
    lua.execute("YRT.TrainerData().reserve = 200")
    check(g.YRT.TrainerShare() == 50 and g.YRT.TrainerSave() == 0 and g.YRT.TrainerKeep(4000) == 3175
          and g.YRT.TrainerKeep(10000) == 5000,
          "the 2 silver it started with: half the money now, never under the repair (31s 75c), nothing saved")
    got = visit(4200)
    check(got == ["Holy Light Rank 3"], f"42s: Holy Light (Always); Seal of Righteousness would leave 26s of the 31s 75c kept: {got}")
    got = visit(4800)
    check(got == ["Holy Light Rank 3", "Seal of Righteousness Rank 2"], f"48s: both: {got}")
    lua.execute("GEAR = {}")
    got = visit(2400)
    check(got == ["Holy Light Rank 3"], f"24s, nothing to repair: half (12s) kept, the seal would leave 8s: {got}")
    lua.execute("YRT.TrainerData().share = 0")
    got = visit(2400)
    check(got == ["Holy Light Rank 3", "Seal of Righteousness Rank 2"], f"share 0: as far as the gold goes: {got}")
    lua.execute("YRT.TrainerData().share = nil YRT.TrainerData().save = 1500")
    got = visit(4000)
    check(g.YRT.TrainerKeep(4000) == 3500 and got == ["Holy Light Rank 3"],
          f"15s saved for a weapon on top of half: 35s kept of 40s, the seal waits: {got}")
    lua.execute("YRT.TrainerData().save = nil YRT.TrainerData().reserve = 500")
    check(g.YRT.TrainerShare() == 0 and g.YRT.TrainerSave() == 500 and g.YRT.TrainerKeep(100000) == 500,
          "a sum of its own set before: kept as it was, no share on top")
    lua.execute("YRT.TrainerData().reserve = 0")
    check(g.YRT.TrainerShare() == 0 and g.YRT.TrainerKeep(100000) == 0, "none set before (the tables from before v2): none now")
    lua.execute("YRT.TrainerData().reserve = 500 YRT.TrainerData().share = 50")
    check(g.YRT.TrainerKeep(10000) == 5000 + 500, "a share turned on: half and the sum saved, both")
    lua.execute("YRT.TrainerData().save = 0 YRT.TrainerData().share = 0")
    check(g.YRT.TrainerKeep(10000) == 0, "both off: nothing kept")
    lua.execute("YRT.TrainerData().share = nil YRT.TrainerData().save = nil YRT.TrainerData().reserve = 500")
    # an amount as you write it
    for text, copper in (("1g 50s", 15000), ("75s", 7500), ("2", 20000), ("1.5", 15000), ("1g20s5c", 12005),
                         (" 3S ", 300), ("", 0), ("lots", None), ("5 apples", None), ("-1", None)):
        got = g.YRT.ParseMoney(text)
        check(got == copper, f"\"{text}\" is {copper} copper ({got})")
    check(g.YRT.MoneyText(15000) == "1g 50s" and g.YRT.MoneyText(7500) == "75s" and g.YRT.MoneyText(0) == "0",
          "and written back the same way")
    check(g.YRT.RepairAllCost() == 0, "nothing worn: nothing to repair")
    # /headstart repair: the full repair, and today's wear beside what a vendor asks for it
    lua.execute("GEAR = { [5] = { 100, 4, 2, 10, 2, 60 } } PRINTS = {}")
    g.YRT.RepairDebug()
    said = g.PRINTS[1] or ""
    check("full repair of what you wear: 2s 0c" in said and "counts 80c" in said and "vendor that repairs" in said,
          f"away from a vendor: the full repair, and 40 points lost counted as 80c ({said})")
    lua.execute("VENDOR = { 80, true } PRINTS = {}")
    g.YRT.RepairDebug()
    said = g.PRINTS[1] or ""
    check("this vendor asks 80c" in said, f"at a vendor: what it asks, beside Headstart's count ({said})")
    lua.execute("GEAR = {} VENDOR = { 0, false }")
    # Train spells up to level: what is taught above it is left, and named
    lua.execute("YRT.TrainerData().upTo = 10")
    got = visit(10000)
    check("Holy Light Rank 3" not in got and "Seal of Righteousness Rank 2" in got
          and any("above level 10" in g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)),
          f"up to level 10: Holy Light (12) left for you, and chat says so: {got}")
    lua.execute("YRT.TrainerData().upTo = nil")

    # First rank only: the spell itself is learned (as Always), its later ranks never
    lua.execute('YRT.SetTrainerChoices({ "Seal of the Crusader", "Seal of Righteousness", "Holy Light" }, "first")')
    got = visit(10000)
    check(got == ["Seal of the Crusader Rank 1"], f"First rank only: rank 1 learned, ranks 2 and 3 left: {got}")
    lua.execute('LIST[#LIST + 1] = { "Redemption", "", "available", 300, 12 }')
    lua.execute('YRT.SetTrainerChoice("Redemption", "first")')
    got = visit(900)
    check(sorted(got) == ["Redemption ", "Seal of the Crusader Rank 1"], f"a spell without ranks is its own first, and the reserve doesn't hold it back: {got}")
    lua.execute('LIST[#LIST] = nil YRT.SetTrainerChoices({ "Seal of the Crusader", "Holy Light" }, "always") YRT.SetTrainerChoice("Seal of Righteousness", "gold")')

    check(visit(10000, shift=True) == [], "Shift held: nothing learned")
    check(visit(10000, tradeskill=True) == [], "a profession trainer: nothing learned")

    # Only the class's own spells. A weapon master and a riding trainer open the same window and are
    # no profession trainers: what they offer is left alone, however much gold there is - and said.
    kept = lua.eval("LIST")
    lua.execute("""LIST = {
        { "Two-Handed Swords", "", "available", 1000, 1 },
        { "Polearms", "", "available", 1000, 20 },
        { "Apprentice Riding", "", "available", 800000, 40 },
    }""")
    got = visit(5000000)
    check(got == [] and any("nothing here is one of your class's spells" in g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)),
          f"a weapon master or a riding trainer: nothing bought with 500 gold in the bag, and it says why ({got})")
    lua.execute('LIST[#LIST + 1] = { "Holy Light", "Rank 3", "available", 1000, 12 }')
    got = visit(5000000)
    check(got == ["Holy Light Rank 3"], f"a list that mixes them: the class's spell, and none of the others ({got})")
    g.LIST = kept
    # no list of the class's spells at all: nothing is bought (it does not fall back to "everything")
    lua.execute("KEPT_SPELLS = YRT.TrainerSpells YRT.TrainerSpells = nil CLASS_WAS = UnitClass function UnitClass() return 'Monk', 'MONK' end")
    got = visit(5000000)
    lua.execute("YRT.TrainerSpells = KEPT_SPELLS UnitClass = CLASS_WAS")
    check(got == [], f"no spell list for the class: nothing bought ({got})")
    check(visit(10000) != [], "(and with the class back, it buys again)")

    # On is on: no question, on a character it has never bought on either (the user, 2026-10-13, at his own
    # trainer: "hvis det er paa, saa er det paa"). It asked the first time on each character for a while.
    lua.execute("YippSetupCharDB = {} POPUP = nil")
    got = visit(10000)
    check(len(got) == 3 and g.POPUP is None and g.YippSetupCharDB.trainOK is None,
          f"a character it has not bought on before: bought, and nothing asked ({got})")
    check(lua.eval("StaticPopupDialogs.HEADSTART_TRAIN_FIRST") is None, "there is no such question any more")
    check(visit(10000, shift=True) == [] and g.POPUP is None, "Shift held: nothing bought, nothing asked")

    lua.execute("YippRouteDB.autoTrain = false; YRT:SyncRxpTrainer()")
    check(g.RXP.settings.profile.enableTrainerAutomation is True, "ours off: RestedXP's back on")
    check(visit(10000) == [], "ours off: nothing learned")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
