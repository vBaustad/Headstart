"""Smoke test of the flight timer (Flight.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_flight.py      (exit code 1 on any failure; tools/smoke.py runs it too)

A first flight is timed and learned (with the pace per length), the next flight on the same route
counts down from the learned time, a new route is estimated from its length, RestedXP's time is used
when it has one, a reload in the air carries the bar on without learning, and the setting hides it.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
FRAMES, NOW, CLOCK = {}, 0, 1000
local Obj
Obj = { __call = function() return setmetatable({}, Obj) end }
Obj.__index = function(t, k)
    local v = rawget(Obj, k)
    if v then return v end
    local child = setmetatable({}, Obj); rawset(t, k, child); return child
end
function Obj.Show(self) rawset(self, "_shown", true) end
function Obj.Hide(self) rawset(self, "_shown", false) end
function Obj.IsShown(self) return rawget(self, "_shown") ~= false end
function Obj.SetShown(self, on) rawset(self, "_shown", on and true or false) end
function Obj.SetScript(self, what, fn) rawset(self, "_" .. what, fn) end
function Obj.RegisterEvent(self, e) rawset(self, "_ev", rawget(self, "_ev") or {}) self._ev[e] = true end
function Obj.SetText(self, t) rawset(self, "_text", t) end
function Obj.GetText(self) return rawget(self, "_text") or "" end
function Obj.SetValue(self, v) rawset(self, "_value", v) end
function Obj.GetLeft() return 100 end
function Obj.GetTop() return 600 end
function CreateFrame(_, name) local f = setmetatable({}, Obj) table.insert(FRAMES, f) if name then _G[name] = f end return f end
UIParent = CreateFrame()
function Fire(event) for _, f in ipairs(FRAMES) do if rawget(f, "_ev") and f._ev[event] and rawget(f, "_OnEvent") then f._OnEvent(f, event) end end end
function Tick(dt) NOW = NOW + dt; CLOCK = CLOCK + dt
    for _, f in ipairs(FRAMES) do local u = rawget(f, "_OnUpdate") if u then u(f, dt) end end end
function GetTime() return NOW end
function time() return math.floor(CLOCK) end
floor = math.floor
C_Timer = { After = function() end }
HOOKS = {}
function hooksecurefunc(name, fn) HOOKS[name] = fn end
ONTAXI = false
function UnitOnTaxi() return ONTAXI end
-- the flight map: node 1 is where you are, 2 and 3 are destinations; one hop each
NODES = { { "Ironforge, Dun Morogh", "CURRENT", 0.5, 0.5 }, { "Thelsamar, Loch Modan", "REACHABLE", 0.6, 0.5 },
    { "Menethil Harbor, Wetlands", "REACHABLE", 0.3, 0.3 }, { "Thandol Span, Arathi Highlands", "REACHABLE", 0.3, 0.5 } }
function TaxiNodePosition(i) return NODES[i][3], NODES[i][4] end
HOPS = { [2] = { { 0.5, 0.5, 0.6, 0.5 } }, [3] = { { 0.5, 0.5, 0.3, 0.5 }, { 0.3, 0.5, 0.3, 0.3 } } }
function NumTaxiNodes() return #NODES end
function TaxiNodeName(i) return NODES[i][1] end
function TaxiNodeGetType(i) return NODES[i][2] end
function GetNumRoutes(i) return #(HOPS[i] or {}) end
function TaxiGetSrcX(i, h) return HOPS[i][h][1] end
function TaxiGetSrcY(i, h) return HOPS[i][h][2] end
function TaxiGetDestX(i, h) return HOPS[i][h][3] end
function TaxiGetDestY(i, h) return HOPS[i][h][4] end
function GetTaxiMapID() return 1415 end
YippRouteDB = {}
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
''')
    YR = lua.table()
    for f in ("Core.lua", "Style.lua", "Flight.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def fly(i, seconds, rxp=None):
        if rxp:
            lua.execute(f"RXP = {{ flightInfo = {{ activeIndex = {i}, timer = {rxp} }} }}")
        else:
            lua.execute("RXP = nil")
        g.HOOKS.TakeTaxiNode(i)
        lua.execute("Tick(0.5); ONTAXI = true; Tick(0.5)")
        bar = g.HeadstartFlightFrame
        texts = (bar.time.GetText(bar.time), bar["from"].GetText(bar["from"]), bar.to.GetText(bar.to), bar.note.GetText(bar.note)) if bar else None
        lua.execute(f"Tick({seconds - 1})")
        mid = bar.time.GetText(bar.time) if bar else None
        lua.execute("Tick(1); ONTAXI = false; Fire('PLAYER_CONTROL_GAINED')")
        return texts, mid

    texts, _ = fly(2, 60)
    check(texts and texts[0] == "0:00" and "timing it" in texts[3], f"first flight counts up while it learns: {texts}")
    check(texts and texts[1] == "Ironforge" and texts[2] == "Thelsamar", f"from and to, without the zone: {texts}")
    check(not g.HeadstartFlightFrame.IsShown(g.HeadstartFlightFrame), "the bar goes on landing")
    learned = g.YippRouteDB.flights["Ironforge, Dun Morogh>Thelsamar, Loch Modan"]
    check(learned == 60, f"60-second flight learned: {learned}")

    texts, mid = fly(2, 60)
    check(texts[0] == "1:00" or texts[0] == "0:59", f"second time: counts down from the learned time: {texts[0]}")
    check(mid == "0:01", f"a second before landing: {mid}")

    # Menethil: never flown, two hops of 0.2 against Thelsamar's one of 0.1: four times the minute,
    # by way of Thandol Span, halfway
    texts, _ = fly(3, 235)
    check("Thandol Span in 2:00" in texts[3] or "Thandol Span in 1:59" in texts[3], f"the next stop on the way and when: {texts[3]}")
    marks = [m for m in g.HeadstartFlightFrame.markers.values() if m.at is not None]
    shown = [m for m in marks if m.ring.IsShown(m.ring)]
    check([round(m.at, 2) for m in shown] == [0.5], f"one hump, at the stop halfway: {[m.at for m in shown]}")
    check(texts[0] in ("about 4:00", "about 3:59"), f"a new route is estimated from its length: {texts[0]}")

    lua.execute('YippRouteDB.flights["Ironforge, Dun Morogh>Menethil Harbor, Wetlands"] = nil')
    texts, _ = fly(3, 170, rxp=170)
    check(texts[0] in ("2:50", "2:49"), f"RestedXP's time when it has one: {texts[0]}")

    # a reload in the air: the bar carries on, and the flight isn't learned
    lua.execute('YippRouteDB.flights["Ironforge, Dun Morogh>Thelsamar, Loch Modan"] = 60')
    g.HOOKS.TakeTaxiNode(2)
    lua.execute("Tick(0.5); ONTAXI = true; Tick(0.1); Tick(20)")
    YR2 = lua.table()
    lua.execute("for i = #FRAMES, 1, -1 do FRAMES[i] = nil end; HeadstartFlightFrame = nil; NOW = 5000")
    for f in ("Core.lua", "Style.lua", "Flight.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR2)
    lua.execute("Fire('PLAYER_ENTERING_WORLD'); Tick(0.2)")
    bar = g.HeadstartFlightFrame
    left = bar and bar.time.GetText(bar.time)
    check(left in ("0:40", "0:39"), f"after a reload in the air the bar carries on: {left}")
    lua.execute("Tick(15); ONTAXI = false; Fire('PLAYER_CONTROL_GAINED')")
    check(g.YippRouteDB.flights["Ironforge, Dun Morogh>Thelsamar, Loch Modan"] == 60, "a flight through a reload isn't learned")

    # landing seen in game: PLAYER_CONTROL_GAINED came while still on the taxi, then nothing; the bar
    # still goes when the game stops saying you're on a taxi
    g.HOOKS.TakeTaxiNode(2)
    lua.execute("Tick(0.5); ONTAXI = true; Tick(0.1); Tick(30); Fire('PLAYER_CONTROL_GAINED'); Tick(30); ONTAXI = false; Tick(0.3)")
    bar = g.HeadstartFlightFrame
    check(not bar.IsShown(bar), "landing without an event after it: the bar goes anyway")

    # the setting off: no bar
    lua.execute("YippRouteDB.flightTimer = false")
    g.HOOKS.TakeTaxiNode(2)
    lua.execute("Tick(0.5); ONTAXI = true; Tick(1)")
    check(not bar.IsShown(bar), "Flight timer off: no bar")
    lua.execute("ONTAXI = false; Fire('PLAYER_CONTROL_GAINED')")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
