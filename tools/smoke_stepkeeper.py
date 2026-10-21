"""Smoke test of StepKeeper.lua (your place in a route kept through an update) against a fake RestedXP,
in Lua 5.1 (lupa).

    python tools/smoke_stepkeeper.py      (exit code 1 on any failure)
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

OLD = """#name 5-11 Test
step
    .accept 1 >> A
step << Hunter
    .accept 2 >> hunters only
step
    .accept 3 >> Treacherous Cold
step
    .collect 4,1 --a rifle
step
    .turnin 5 >> the troggs
step
    .complete 6,1 --spies
step
    .turnin 6 >> Farsen
step
    >>Walk to Loch Modan
"""
# the update takes out Treacherous Cold and the rifle (two steps before the place)
NEW = OLD.replace("step\n    .accept 3 >> Treacherous Cold\nstep\n    .collect 4,1 --a rifle\n", "")


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
PRINTS = {}
YippRouteDB = { routes = true }
RXPCData = { currentStep = 1 }
SAVED = 1
RXP = { currentGuide = nil }
function RXP.SetStep(n, n2) if type(n) == "table" then n = n2 end RXPCData.currentStep = n end
function RXP:LoadGuide(guide)
    self.currentGuide = guide
    RXPCData.currentStep = SAVED          -- RestedXP goes back to the saved number
    RXP.SetStep(SAVED)
end
function hooksecurefunc(t, k, f) local o = t[k] t[k] = function(...) local r = { o(...) } f(...) return unpack(r) end end
-- the place is written down on the frame after a step is set: NextFrame() is that frame
LATER = {}
C_Timer = { After = function(_, fn) LATER[#LATER + 1] = fn end }
function NextFrame() local l = LATER LATER = {} for _, fn in ipairs(l) do fn() end end
''')
    YR = lua.table()
    lua.execute(r'''
TEXT = ""
function MAKE(YR)
    YR.shipped = { { key = "test" } }
    YR.GuideName = function(key) return "5-11 Test" end
    YR.GuideText = function(self, key) return TEXT end
    YR.Shows = function(f) return not f or not f:find("Hunter") end
    YR.Print = function(m) table.insert(PRINTS, m) end
    YR.CharKey = function() return "Tester-Realm" end
    YR.RoutesOn = function() return YippRouteDB.routes == true end
    function YR.SplitSteps(text)
        local first = text:find("\nstep[^\n]*\n") or text:find("\nstep[^\n]*$")
        if not first then return text, {} end
        local header, rest = text:sub(1, first), text:sub(first + 1)
        local steps, from = {}, 1
        while true do
            local nextStep = rest:find("\nstep[^\n]*\n", from) or rest:find("\nstep[^\n]*$", from)
            if not nextStep then steps[#steps + 1] = (rest:sub(from):gsub("%s+$", "")) break end
            steps[#steps + 1] = (rest:sub(from, nextStep - 1):gsub("%s+$", ""))
            from = nextStep + 1
        end
        return header, steps
    end
end
''')
    lua.globals().MAKE(YR)
    chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, "StepKeeper.lua"), encoding="utf-8").read(), "StepKeeper.lua")
    chunk("Headstart", YR)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    guide = lua.eval('{ name = "05-11 Test", steps = { {}, {}, {}, {}, {}, {}, {}, {} } }')
    g.TEXT = OLD
    g.RXP.LoadGuide(g.RXP, guide)
    for n in (2, 3, 4):                   # RestedXP skips on to the 4th step: a set for each on the way
        g.RXP.SetStep(n)                  # a non-Hunter's 4th step: hand in the troggs
    check(len(g.LATER) == 1, f"a chain of steps set in one frame is written down once, after it: {len(g.LATER)}")
    g.NextFrame()
    place = g.YippRouteDB.place["Tester-Realm"]
    check(place and place.n == 4 and "the troggs" in place.text, f"remembers the step itself: {place and place.n}")
    g.SAVED = 4
    g.TEXT = NEW                          # /reload with the update: two steps fewer before it
    g.RXP.LoadGuide(g.RXP, guide)
    check(g.RXPCData.currentStep == 2, f"after the update: back on the same step (2, not 4): {g.RXPCData.currentStep}")
    check(len(g.PRINTS) == 1 and "back at your step" in str(g.PRINTS[1]), f"and says so: {list(g.PRINTS.values())}")
    check(g.YippRouteDB.place["Tester-Realm"].n == 2, "the new number is remembered")
    g.SAVED = 2
    g.RXP.LoadGuide(g.RXP, guide)
    check(g.RXPCData.currentStep == 2 and len(g.PRINTS) == 1, "nothing changed: left alone, nothing said")
    # a step whose wording changed is found by its quests
    g.RXP.SetStep(3)
    g.NextFrame()
    g.SAVED = 3
    g.TEXT = NEW.replace(".complete 6,1 --spies", ".complete 6,1 --the Dark Iron spies").replace("step\n    .accept 1 >> A\n", "step\n    .accept 1 >> A\nstep\n    .accept 9 >> new\n")
    g.RXP.LoadGuide(g.RXP, guide)
    check(g.RXPCData.currentStep == 4, f"reworded step found by its quests (3 -> 4): {g.RXPCData.currentStep}")
    g.YippRouteDB.routes = False
    g.SAVED = 1
    g.RXP.LoadGuide(g.RXP, guide)
    check(g.RXPCData.currentStep == 1, "routes off: RestedXP's own place, untouched")

    # the route's next buy ahead (Shopping.lua): from your step on, a step with ".collect item,1" and its price,
    # ".money <" or "#hsprice" (RestedXP hides a step with ".money <" while you're short; "#hsprice" it only
    # stores) - the trainer keeps that much back
    lua.execute(r'''
BUY_TEXT = "#name 6-11 Buy\nstep\n    .accept 1 >> A\nstep << Rogue\n    .goto 1438,55.6,57.2\n    .collect 2494,1 --Collect Stiletto (4s 1c)\n    #hsprice 0.0401\n    .target Aldia\nstep\n    .turnin 1 >> A\n"
HAVE = {}
StaticPopupDialogs = StaticPopupDialogs or {}
function GetInventoryItemLink() return nil end
function IsEquippedItem() return false end
C_Item = { GetItemCount = function(id) return HAVE[id] or 0 end }
function MAKE_BUY(YR)
    YR.shipped[#YR.shipped + 1] = { key = "buy" }
    YR.shipped[#YR.shipped + 1] = { key = "buy2" }
    local name, text = YR.GuideName, YR.GuideText
    YR.GuideName = function(key) if key == "buy" then return "6-11 Buy" elseif key == "buy2" then return "6-11 Buy Two" end return name(key) end
    YR.GuideText = function(self, key)
        if key == "buy" then return BUY_TEXT end
        if key == "buy2" then return (BUY_TEXT:gsub("#hsprice 0.0401", ".money <0.0401")) end
        return text(self, key)
    end
    YR.Part = function() end
    YR.Option = function() return false end
end''')
    g.MAKE_BUY(YR)
    chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, "Shopping.lua"), encoding="utf-8").read(), "Shopping.lua")
    chunk("Headstart", YR)
    g.YippRouteDB.routes = True
    lua.execute('RXP.currentGuide = { name = "06-11 Buy" } RXPCData.currentStep = 1')
    e = YR.NextRouteBuy()
    check(e is not None and e.item == 2494 and e.price == 401 and e.name == "Stiletto" and e.npc == "Aldia",
          f"on step 1: the Stiletto ahead, 4s 1c, from #hsprice ({e and (e.name, e.price, e.npc)})")
    lua.execute("RXPCData.currentStep = 3")
    check(YR.NextRouteBuy() is None, "past its step: nothing ahead")
    lua.execute("RXPCData.currentStep = 1 HAVE[2494] = 1")
    check(YR.NextRouteBuy() is None, "one in the bags already: nothing to save for")
    lua.execute('HAVE = {} RXP.currentGuide = { name = "06-11 Buy Two" }')
    e = YR.NextRouteBuy()
    check(e is not None and e.price == 401, "with .money <0.0401 in place of #hsprice: the same")
    lua.execute('RXP.currentGuide = { name = "Someone Else\'s Guide" }')
    check(YR.NextRouteBuy() is None, "a guide that isn't one of Headstart's: nothing")
    # the Dolanaar step as the route writes it (2026-10-16): [Stiletto] in the text; and without it, the
    # collect line's own words
    lua.execute(r'''
DOLANAAR = [[#name 6-11 Buy
step << Rogue
    #hsprice 0.0401
    .goto 1438/1,947.57,9812.38
    >>|cRXP_BUY_Buy and equip a|r |T135641:0|t[Stiletto] (4s 1c)
    .collect 2494,1 --Stiletto (1)
    .target Shalomon
]]
BUY_TEXT = DOLANAAR''')
    lua.execute('RXP.currentGuide = { name = "06-11 Buy" } RXPCData.currentStep = 1 RXP.LoadGuide(RXP, { name = "06-11 Buy", steps = { {} } })')
    lua.execute('RXP.currentGuide = { name = "06-11 Buy" } RXPCData.currentStep = 1')
    e = YR.NextRouteBuy()
    check(e is not None and e.name == "Stiletto" and e.price == 401 and e.npc == "Shalomon",
          f"the Dolanaar step as written: Stiletto, 4s 1c, Shalomon ({e and (e.name, e.price, e.npc)})")
    lua.execute('BUY_TEXT = DOLANAAR:gsub("%[Stiletto%]", "a dagger") RXP.LoadGuide(RXP, { name = "06-11 Buy", steps = { {} } })')
    lua.execute('RXP.currentGuide = { name = "06-11 Buy" } RXPCData.currentStep = 1')
    e = YR.NextRouteBuy()
    check(e is not None and e.name == "Stiletto", f"no [name] in the text: the collect line's '--Stiletto (1)' ({e and e.name})")
    g.YippRouteDB.routes = False
    lua.execute('RXP.currentGuide = { name = "06-11 Buy" }')
    check(YR.NextRouteBuy() is None, "routes off: nothing")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
