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
    g.RXP.SetStep(4)                      # a non-Hunter's 4th step: hand in the troggs
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
    g.SAVED = 3
    g.TEXT = NEW.replace(".complete 6,1 --spies", ".complete 6,1 --the Dark Iron spies").replace("step\n    .accept 1 >> A\n", "step\n    .accept 1 >> A\nstep\n    .accept 9 >> new\n")
    g.RXP.LoadGuide(g.RXP, guide)
    check(g.RXPCData.currentStep == 4, f"reworded step found by its quests (3 -> 4): {g.RXPCData.currentStep}")
    g.YippRouteDB.routes = False
    g.SAVED = 1
    g.RXP.LoadGuide(g.RXP, guide)
    check(g.RXPCData.currentStep == 1, "routes off: RestedXP's own place, untouched")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
