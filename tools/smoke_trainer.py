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
function CreateFrame() local f = setmetatable({}, F) table.insert(FRAMES, f) return f end
function Fire(e) for _, f in ipairs(FRAMES) do if f.ev and f.ev[e] and f.fn then f.fn(f, e) end end end
C_Timer = { After = function(_, fn) fn() end }
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
floor = math.floor
YippRouteDB = { autoTrain = true }       -- off until you turn it on (checked below)
function UnitClass() return "Paladin", "PALADIN" end
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
''')
    YR = lua.table()
    for f in ("Core.lua", "Trainer.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    g = lua.globals()
    g.YRT = YR
    lua.execute('YRT.Print = function(m) table.insert(PRINTS, m) end')
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
    lua.execute("Fire('PLAYER_LOGIN')")
    # a new class table: "If I can afford it" for everything, and a 2 silver reserve
    check(g.YRT.TrainerChoice("Holy Light") == "gold" and g.YRT.TrainerData().reserve == 200,
          "new defaults: If I can afford it, keep 2 silver")
    got = visit(1700)
    check(got == ["Seal of the Crusader Rank 1", "Seal of Righteousness Rank 2"],
          f"17s: the lower spells, then not under 2s (Holy Light would leave 1s): {got}")
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
    check(any("reserve" in g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)), "says what it left for the reserve")
    got = visit(2200)
    check(got == ["Holy Light Rank 3", "Seal of Righteousness Rank 2"], f"with 22s both: {got}")

    check(visit(10000, shift=True) == [], "Shift held: nothing learned")
    check(visit(10000, tradeskill=True) == [], "a profession trainer: nothing learned")

    lua.execute("YippRouteDB.autoTrain = false; YRT:SyncRxpTrainer()")
    check(g.RXP.settings.profile.enableTrainerAutomation is True, "ours off: RestedXP's back on")
    check(visit(10000) == [], "ours off: nothing learned")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
