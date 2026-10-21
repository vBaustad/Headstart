"""Smoke test of the flight timer (Flight.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_flight.py      (exit code 1 on any failure; tools/smoke.py runs it too)

A first flight is timed and learned (with the pace per length), the next flight on the same route
counts down from the learned time, a new route is estimated from its length, RestedXP's time is used
when it has one, a reload in the air carries the bar on without learning, and the setting hides it.
The card: its ring set once a flight (the game draws it), Land quiet on a direct flight, and Blizzard's
own Land button see-through while it shows.
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
function Obj.UnregisterEvent(self, e) if rawget(self, "_ev") then self._ev[e] = nil end end
function Obj.UnregisterAllEvents(self) rawset(self, "_ev", nil) end
function Obj.SetText(self, t) rawset(self, "_text", t) end
function Obj.GetText(self) return rawget(self, "_text") or "" end
function Obj.SetValue(self, v) rawset(self, "_value", v) end
function Obj.SetWidth(self, w) rawset(self, "_w", w) rawset(self, "_wn", (rawget(self, "_wn") or 0) + 1) end
function Obj.GetLeft() return 100 end
function Obj.GetFrameLevel() return 1 end
function Obj.SetCooldown(self, start, length) rawset(self, "_cd", { start, length }) rawset(self, "_cdn", (rawget(self, "_cdn") or 0) + 1) end
-- Blizzard's own Land button, shown on a taxi
THEIRS = { alpha = 1, mouse = true }
MainMenuBarVehicleLeaveButton = { SetAlpha = function(self, a) THEIRS.alpha = a end, GetAlpha = function() return THEIRS.alpha end,
    EnableMouse = function(self, on) THEIRS.mouse = on end, IsMouseEnabled = function() return THEIRS.mouse end,
    IsProtected = function() return false end, HookScript = function(self, what, fn) THEIRS.onShow = fn end }
function Obj.GetTop() return 600 end
function CreateFrame(_, name) local f = setmetatable({}, Obj) table.insert(FRAMES, f) if name then _G[name] = f end return f end
UIParent = CreateFrame()
GameTooltip = CreateFrame()
function Fire(event) for _, f in ipairs(FRAMES) do if rawget(f, "_ev") and f._ev[event] and rawget(f, "_OnEvent") then f._OnEvent(f, event) end end end
-- A frame of dt seconds: the OnUpdates, then each ticker whose time has come (once a frame at most,
-- as in the game).
TICKERS = {}
function Tick(dt) NOW = NOW + dt; CLOCK = CLOCK + dt
    for _, f in ipairs(FRAMES) do local u = rawget(f, "_OnUpdate") if u then u(f, dt) end end
    local live = {}
    for _, t in ipairs(TICKERS) do if not t.dead then live[#live + 1] = t end end
    TICKERS = live
    for _, t in ipairs(live) do
        if not t.dead then
            t.acc = t.acc + dt
            if t.acc >= t.every then t.acc = 0 t.fn() end
        end
    end
end
function Ticking() local n = 0 for _, t in ipairs(TICKERS) do if not t.dead then n = n + 1 end end return n end
-- what still runs or listens besides the bar's own drawing: tickers, OnUpdates, PLAYER_CONTROL_GAINED
function Running()
    local n = Ticking()
    for _, f in ipairs(FRAMES) do
        if f ~= HeadstartFlightFrame and rawget(f, "_OnUpdate") then n = n + 1 end
        if rawget(f, "_ev") and f._ev.PLAYER_CONTROL_GAINED then n = n + 1 end
    end
    return n
end
function GetTime() return NOW end
function time() return math.floor(CLOCK) end
floor = math.floor
C_Timer = { After = function() end,
    NewTicker = function(every, fn)
        local t = { every = every, fn = fn, acc = 0, Cancel = function(self) self.dead = true end }
        table.insert(TICKERS, t)
        return t
    end }
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
    # the timer comes on at the login (YR.Part): nothing listens, and the taxi isn't hooked, before it
    g = lua.globals()
    hooked_before = g.HOOKS.TakeTaxiNode is not None
    YR.partsReady = True
    YR.ApplyParts()
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
        texts = (bar.time.GetText(bar.time), bar["from"].GetText(bar["from"]), bar.to.GetText(bar.to), bar.eta.GetText(bar.eta)) if bar else None
        lua.execute(f"Tick({seconds - 1})")
        mid = bar.time.GetText(bar.time) if bar else None
        lua.execute("Tick(1); ONTAXI = false; Fire('PLAYER_CONTROL_GAINED')")
        return texts, mid

    check(not hooked_before and g.HOOKS.TakeTaxiNode is not None, "the taxi is hooked when the timer comes on, not before")
    texts, _ = fly(2, 60)
    check(g.Running() == 0,
          "on the ground again: nothing ticks, nothing is counted each frame, losing control isn't listened for")
    check(texts and texts[0] == "0:00" and "timing it" in texts[3], f"first flight counts up while it learns: {texts}")
    check(texts and texts[1] == "from Ironforge" and texts[2] == "Thelsamar", f"where to, and where from under it, without the zone: {texts}")
    check(not g.HeadstartFlightFrame.IsShown(g.HeadstartFlightFrame), "the bar goes on landing")
    learned = g.YippRouteDB.flights["Ironforge, Dun Morogh>Thelsamar, Loch Modan"]
    check(learned == 60, f"60-second flight learned: {learned}")

    texts, mid = fly(2, 60)
    check(texts[0] == "1:00" or texts[0] == "0:59", f"second time: counts down from the learned time: {texts[0]}")
    check(mid == "0:01", f"a second before landing: {mid}")

    # the ring: the game's cooldown sweep, set once for the flight - nothing moved each frame
    g.HOOKS.TakeTaxiNode(2)
    lua.execute("Tick(0.5); ONTAXI = true; Tick(0.5); Tick(10)")
    sweep = g.HeadstartFlightFrame.sweep
    n0 = sweep._cdn
    check(sweep._cd[2] == 60, f"the ring set for the learned minute ({sweep._cd[2]})")
    lua.execute("for i = 1, 20 do Tick(0.05) end Tick(5)")
    check(sweep._cdn == n0, f"twenty frames and five seconds on: the ring isn't set again ({sweep._cdn - n0})")
    check(g.THEIRS.alpha == 0 and g.THEIRS.mouse is False, "in the air: Blizzard's own Land button see-through, and let through to the world")
    g.THEIRS.onShow(g.MainMenuBarVehicleLeaveButton)
    check(g.THEIRS.alpha == 0, "shown again by Blizzard's code meanwhile: still see-through")
    lua.execute("Tick(60); ONTAXI = false; Fire('PLAYER_CONTROL_GAINED')")
    check(g.THEIRS.alpha == 1 and g.THEIRS.mouse is True, "landed: Blizzard's Land button as it was")

    # Menethil: never flown, two hops of 0.2 against Thelsamar's one of 0.1: four times the minute,
    # by way of Thandol Span, halfway
    texts, _ = fly(3, 235)
    check(texts[0] in ("~4:00", "~3:59"), f"a new route is estimated from its length: {texts[0]}")

    lua.execute('YippRouteDB.flights["Ironforge, Dun Morogh>Menethil Harbor, Wetlands"] = nil')
    texts, _ = fly(3, 170, rxp=170)
    check(texts[0] in ("2:50", "2:49"), f"RestedXP's time when it has one: {texts[0]}")

    # a reload in the air: the bar carries on, and the flight isn't learned
    lua.execute('YippRouteDB.flights["Ironforge, Dun Morogh>Thelsamar, Loch Modan"] = 60')
    g.HOOKS.TakeTaxiNode(2)
    lua.execute("Tick(0.5); ONTAXI = true; Tick(0.1); Tick(20)")
    YR2 = lua.table()
    # (a reload: the UI, Blizzard's button with it, as new)
    lua.execute("for i = #FRAMES, 1, -1 do FRAMES[i] = nil end; TICKERS = {}; HeadstartFlightFrame = nil; NOW = 5000; THEIRS.alpha, THEIRS.mouse = 1, true")
    for f in ("Core.lua", "Style.lua", "Flight.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR2)
    YR2.partsReady = True
    YR2.ApplyParts()
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

    # the stop button: lands at the next stop; the bar retargets, and the cut flight isn't learned
    lua.execute("EARLY = 0; function TaxiRequestEarlyLanding() EARLY = EARLY + 1 end")
    lua.execute('YippRouteDB.flights["Ironforge, Dun Morogh>Menethil Harbor, Wetlands"] = 240')
    g.HOOKS.TakeTaxiNode(3)
    lua.execute("Tick(0.5); ONTAXI = true; Tick(0.1); Tick(30); Tick(0.2)")
    bar = g.HeadstartFlightFrame
    check(bar.stop.IsShown(bar.stop), "the stop button shows on a flight with a stop on the way")
    lua.execute("ONTAXI = false; Tick(0.3)")
    g.HOOKS.TakeTaxiNode(2)
    lua.execute("Tick(0.5); ONTAXI = true; Tick(0.1); Tick(1)")
    check(bar.stop.IsShown(bar.stop) and bar.stopCan is False,
          "a direct flight: Land is there, but quiet - nothing to land at before the end")
    lua.execute("ONTAXI = false; Tick(0.3)")
    lua.execute('YippRouteDB.flights["Ironforge, Dun Morogh>Thelsamar, Loch Modan"] = 60')
    lua.execute('YippRouteDB.flights["Ironforge, Dun Morogh>Menethil Harbor, Wetlands"] = 240')
    g.HOOKS.TakeTaxiNode(3)
    lua.execute("Tick(0.5); ONTAXI = true; Tick(0.1); Tick(30); Tick(0.2)")
    bar.stop._OnClick(bar.stop)
    lua.execute("Tick(0.2)")
    check(g.EARLY == 1 and bar.eta.GetText(bar.eta) == "next stop",
          f"stop pressed: the game asked, the card says {bar.eta.GetText(bar.eta)!r}")
    check(bar.stopCan is False and bar.stop.text.GetText(bar.stop.text) == "Landing", "pressed: it says Landing, and can't be pressed again")
    # under the mouse it lights, whether or not it can land you (it only had a tooltip)
    lua.execute("""COLOURS = {} local bg = HeadstartFlightFrame.stop.bg
        function bg.SetVertexColor(self, r, g, b, a) COLOURS[#COLOURS + 1] = a end""")
    bar.stop._OnLeave(bar.stop)
    quiet = g.COLOURS[len(g.COLOURS)]
    bar.stop._OnEnter(bar.stop)
    lit = g.COLOURS[len(g.COLOURS)]
    bar.stop._OnLeave(bar.stop)
    check(lit > quiet, f"Land under the mouse, landing asked already: lit all the same ({quiet} -> {lit})")
    lua.execute("Tick(90); ONTAXI = false; Tick(0.3)")
    check(g.YippRouteDB.flights["Ironforge, Dun Morogh>Menethil Harbor, Wetlands"] == 240, "a flight landed early isn't learned")

    # the sample bar (/headstart flight) leaves Blizzard's Land button be
    YR.PreviewFlight(YR)
    check(g.THEIRS.alpha == 1, "the sample card: Blizzard's Land button left as it is")
    # the setting off: no bar
    lua.execute("YippRouteDB.flightTimer = false")
    g.HOOKS.TakeTaxiNode(2)
    lua.execute("Tick(0.5); ONTAXI = true; Tick(1)")
    check(not bar.IsShown(bar), "Flight timer off: no bar")
    check(g.Running() == 0,
          "Flight timer off: nothing runs during the flight")
    lua.execute("ONTAXI = false; Fire('PLAYER_CONTROL_GAINED')")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
