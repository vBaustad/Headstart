"""Smoke test of the boat and zeppelin measuring (Boats.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_boats.py      (exit code 1 on any failure; tools/smoke.py runs it too)

A boat is ridden in the fake world: it lies at its dock, crosses, waits, comes back and leaves again; the
round trip it writes down is the time between its two departures from the same dock.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
FRAMES, TICKERS = {}, {}
local F = {}
F.__index = F
function F:RegisterEvent(e) self.ev = self.ev or {} self.ev[e] = true end
function F:SetScript(k, fn) self[k] = fn end
function F:UnregisterAllEvents() self.ev = nil end
function CreateFrame() local f = setmetatable({}, F) table.insert(FRAMES, f) return f end
C_Timer = { After = function(_, fn) fn() end,
    NewTicker = function(_, fn) local t = { fn = fn } function t:Cancel() self.dead = true end table.insert(TICKERS, t) return t end }
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
floor = math.floor
YippRouteDB = {}
function UnitClass() return "Paladin", "PALADIN" end
function UnitLevel() return 10 end
function UnitName() return "Me" end
NOW, SERVER = 1000, 1700000000
function GetTime() return NOW end
function GetServerTime() return SERVER + math.floor(NOW - 1000) end
POS = { 0, 0, 0, 0 }            -- y, x, z, map: UnitPosition's order
function UnitPosition() return POS[1], POS[2], POS[3], POS[4] end
WALKING = false
function IsPlayerMoving() return WALKING end
function IsFalling() return false end
function GetSubZoneText() return SUBZONE or "" end
function GetRealZoneText() return "Wetlands" end
function GetBuildInfo() return "1.60.1", "70338" end
date, time = os.date, os.time
-- the addon channel: what is sent is kept
SENT = {}
C_ChatInfo = { SendAddonMessage = function(p, m, ch) table.insert(SENT, { p, m, ch }) return 0 end,
    RegisterAddonMessagePrefix = function() return 0 end }
function IsInGuild() return true end
function IsInGroup() return false end
function Ambiguate(s) return s end
PRINTS = {}
-- the boat: at the dock (0, 0) until DEPART, 40 s across to (200, 0), 20 s there, 40 s back, 20 s at the
-- dock, and away again: a round trip of 120 s
DEPART = 1002
function Boat(t)
    local s = (t - DEPART) % 120
    if t < DEPART then return 0 end
    if s < 40 then return s * 5 elseif s < 60 then return 200 elseif s < 100 then return 200 - (s - 60) * 5 else return 0 end
end
function Live() local n = 0 for _, t in ipairs(TICKERS) do if not t.dead then n = n + 1 end end return n end
function Ride(til)
    while NOW < til do
        NOW = NOW + 0.05
        POS[2] = Boat(NOW)
        for _, f in ipairs(FRAMES) do if f.OnUpdate then f.OnUpdate(f) end end
        for _, t in ipairs(TICKERS) do if not t.dead then t.fn() end end
    end
end
''')
    YR = lua.table()
    for f in ("Core.lua", "Boats.lua", "Data/Boats.lua", "BoatTimer.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    g = lua.globals()
    g.YRB = YR
    lua.execute("YRB.Print = function(m) table.insert(PRINTS, m) end")
    # (the boat timer's own looks come later: for the measuring, no timetable - so no dock near, nothing it runs)
    lua.execute("SHIPPED = YRB.BoatData YRB.BoatData = {}")
    YR.partsReady = True
    YR.ApplyParts()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    check(g.Live() == 0 and len(g.YRB.BoatRoutes()) == 12, "nothing runs until a button is pressed; twelve routes to measure")
    check(YR.BoatsMeasure("menethilAuberdine") is True and YR.BoatsMeasuring() == "menethilAuberdine" and g.Live() == 1,
          "a route's button: measuring, a look at where you are every twentieth of a second")
    lua.execute("Ride(1010)")
    said = " ".join(g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1))
    check("left" in said and "Stand still until it has come back here" in said, "it left: said, with what to do")
    # a loading screen on the way: chat says the round goes on
    lua.execute("PRINTS = {} for _, f in ipairs(FRAMES) do if f.ev and f.ev.PLAYER_ENTERING_WORLD and f.OnEvent then f.OnEvent(f, 'PLAYER_ENTERING_WORLD') end end")
    check(any("still measuring" in g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)), "through a loading screen: still measuring, and said")
    lua.execute("Ride(1100)")
    check(YR.BoatsMeasuring() == "menethilAuberdine" and "stopped at" in " ".join(g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)),
          "the stop on the other side is noted, and it is still measuring")
    lua.execute("Ride(1130)")
    times = g.YippRouteDB.boatTimes and g.YippRouteDB.boatTimes.menethilAuberdine
    period = times and times[1].period
    check(period is not None and abs(period - 120) < 0.06, f"back at the dock and away again: a round trip of 120 seconds ({period})")
    check(YR.BoatsMeasuring() is None and g.Live() == 0, "done: nothing runs any more")
    ev = [times[1].events[i].kind for i in range(1, len(times[1].events) + 1)]
    check(ev == ["go", "stop", "go", "stop", "go"], f"every start and stop of the round written down ({ev})")
    check(abs(times[1].left - (g.SERVER + 2.025)) < 0.06, f"when it left, by the realm's clock ({times[1].left - g.SERVER})")
    check(YR.BoatClock(342.37) == "5:42.37", "a time as minutes, seconds and hundredths")
    # the timetable from that round: two docks, each with its arrival and departure; the next departure from
    # the home dock is a whole number of rounds after the measured one
    tt = YR.BoatTimetable(times[1], "Menethil Harbor - Auberdine")
    check(tt is not None and len(tt.docks) == 2 and abs(tt.docks[2].leave - 60) < 0.2 and tt.docks[1].arrive is not None,
          f"a round's timetable: two docks, each arriving and leaving ({tt and len(tt.docks)})")
    nxt = YR.BoatNext(tt, 0, tt.left + 1000)
    check(abs((nxt - tt.left) / 120 - round((nxt - tt.left) / 120)) < 0.001 and nxt >= tt.left + 1000,
          "the next departure: a whole number of rounds on, never in the past")
    lines = YR.BoatsNext()
    check(len(lines) == 1 and "leaves" in lines[1], f"/headstart boats next says it ({lines[1] if lines else None})")
    check(YR.BoatTimetable(lua.eval("{ period = 61.6, events = {} }")) is None, "a round under two minutes is no round")
    # a round of three stops (Auberdine, Menethil Harbor, Southshore and back), two loading screens on the way:
    # done only when it leaves the first dock again, not at the other two
    lua.execute("""
        DEPART, NOW = 1202, 1200
        function Boat(t)        -- 30 s a leg, 15 s at each dock: 135 s a round; legs 2 and 3 on the other continent
            local s = (t - DEPART) % 135
            if t < DEPART then return 0, 0 end
            if s < 30 then return s * 5, 0 elseif s < 45 then return 150, 1 elseif s < 75 then return 150 + (s - 45) * 2, 1
            elseif s < 90 then return 210, 1 elseif s < 100 then return 210 - (s - 90) * 7, 1
            elseif s < 120 then return 210 - (s - 90) * 7, 0 else return 0, 0 end
        end
        function Ride(til)
            while NOW < til do
                NOW = NOW + 0.05
                POS[2], POS[4] = Boat(NOW)
                for _, f in ipairs(FRAMES) do if f.OnUpdate then f.OnUpdate(f) end end
                for _, t in ipairs(TICKERS) do if not t.dead then t.fn() end end
            end
        end""")
    YR.BoatsMeasure("ruttheranAuberdine")
    lua.execute("Ride(1330)")
    check(YR.BoatsMeasuring() == "ruttheranAuberdine", "three stops on the way, two of them on another continent: still measuring")
    lua.execute("Ride(1345)")
    three = g.YippRouteDB.boatTimes.ruttheranAuberdine
    period = three and three[1].period
    kinds = [three[1].events[i].kind for i in range(1, len(three[1].events) + 1)] if three else []
    check(period is not None and abs(period - 135) < 0.06 and kinds.count("stop") == 3 and kinds.count("zone") == 2,
          f"a round of three stops: 135 seconds, every stop and both loading screens written down ({period}, {kinds})")
    # Ratchet, 2026-10-15: a yard's creep at the dock just after the button was taken for the departure, and the
    # real one a minute later for the end of the round. Now a "departure" that stops where it began is none, and a
    # round ends only after it has been far away. And a stop just before a loading screen (your place held while
    # the continent loads) is a pause, not a dock.
    lua.execute("""
        START = NOW
        DEPART = START + 62
        function Boat(t)        -- 140 s a round; a freeze of 3 s before the first loading screen
            if t < START + 1 then return 0, 0 elseif t < START + 1.5 then return (t - START - 1) * 2, 0 elseif t < DEPART then return 1, 0 end
            local s = (t - DEPART) % 140
            if s < 30 then return 1 + s * 5, 0 elseif s < 33 then return 151, 0 elseif s < 53 then return 151 + (s - 33) * 5, 1
            elseif s < 68 then return 251, 1 elseif s < 88 then return 251 - (s - 68) * 5, 1 elseif s < 118 then return 151 - (s - 88) * 5, 0
            else return 1, 0 end
        end""")
    YR.BoatsMeasure("feathermoon")
    lua.execute("Ride(START + 61)")
    check(YR.BoatsMeasuring() == "feathermoon" and g.YippRouteDB.boatTimes.feathermoon is None,
          "a yard's creep at the dock: not taken for the departure")
    lua.execute("Ride(DEPART + 141)")
    fm = g.YippRouteDB.boatTimes.feathermoon
    period = fm and fm[1].period
    kinds = [fm[1].events[i].kind for i in range(1, len(fm[1].events) + 1)] if fm else []
    check(period is not None and abs(period - 140) < 0.06, f"the round from its real departure: 140 seconds ({period})")
    # (from its departure: what came before it - the creep settling, an arrival - is no part of the round)
    kinds = kinds[kinds.index("go"):] if "go" in kinds else kinds
    check(kinds == ["go", "pause", "zone", "stop", "go", "zone", "stop", "go"],
          f"the stop before the loading screen written down as a pause, not a dock ({kinds})")
    # Boarded as it came in, 50 yards out (2026-10-15: the round was cut short - the boat still gliding in was
    # taken for a departure). A departure counts only once the boat has been seen standing: the round starts
    # when it next leaves the dock.
    lua.execute("""
        DEPART = NOW - 90               -- 90 s into a 120 s round: 50 yards out, coming in
        function Boat(t)
            local s = (t - DEPART) % 120
            if s < 40 then return s * 5, 0 elseif s < 60 then return 200, 0 elseif s < 100 then return 200 - (s - 60) * 5, 0 else return 0, 0 end
        end
        PRINTS = {}""")
    YR.BoatsMeasure("menethilTheramore")
    lua.execute("Ride(DEPART + 125)")
    said = " ".join(g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1))
    check("under way" in said and "arrived at" in said and g.YippRouteDB.boatTimes.menethilTheramore is None,
          "boarded as it came in: no departure taken, the arrival said, the round from its next departure")
    lua.execute("Ride(DEPART + 245)")
    mt = g.YippRouteDB.boatTimes.menethilTheramore
    period = mt and mt[1].period
    check(period is not None and abs(period - 120) < 0.06, f"and the whole round, departure to departure: 120 seconds ({period})")
    # standing on the boat after it left: the first departure is the next one, from wherever it is then
    lua.execute("PRINTS = {} WALKING = true")
    YR.BoatsMeasure("orgUC")
    lua.execute("Ride(NOW + 1) WALKING = false")
    check(any("you moved" in g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)), "walking about: told to stand still")
    YR.BoatsMeasure(None)
    check(YR.BoatsMeasuring() is None and g.Live() == 0 and g.YippRouteDB.boatTimes.orgUC is None,
          "stopped by hand: nothing written down, nothing runs")
    # ------------------------------------------------------------------ the boat timer and the sharing
    check(g.SHIPPED is not None and g.SHIPPED.ratchetBB is not None and len(g.SHIPPED.menethilAuberdine.docks) == 3,
          "the timetable Headstart ships: Ratchet - Booty Bay, and the round of three docks")
    # a timetable of our own for the fake boat: at its dock (0, 0) until it leaves, 40 s across to Beta (200, 0),
    # 20 s there, 40 s back, 20 s at home
    lua.execute("""
        REF = 5000
        YRB.BoatData = { test = { period = 120, ref = REF, docks = { { "Alpha", 0, 0, 0, 100, 0 }, { "Beta", 0, 200, 0, 40, 60 } } } }
        YippRouteDB.boatSeen = nil""")
    # its course: Alpha at the first node, Beta at the third, 200 yards along the world's Y
    lua.execute("""YRB.BoatData.test.path = { { 0, 0, 0 }, { 0, 0, 100 }, { 0, 0, 200 } }
        YRB.BoatData.test.docks[1][7], YRB.BoatData.test.docks[2][7] = 1, 3""")
    lua.execute("function WHERE(t) return { YRB.BoatWhere('test', t) } end")
    r = g.WHERE(5020)
    check(r[1] == 0 and abs(r[3] - 100) < 0.01 and r[5] == "to" and r[6] == 2 and abs(r[7] - 20) < 0.01 and abs(r[4] - 1.5708) < 0.01,
          f"under way, half the time to Beta gone: half the way along its course, heading there, in 20 s ({list(r.values())})")
    r = g.WHERE(5050)
    check(r[5] == "at" and r[6] == 2 and abs(r[3] - 200) < 0.01 and abs(r[7] - 10) < 0.01, "lying at Beta: there, leaving in 10 s")
    r = g.WHERE(5080)
    check(r[5] == "to" and r[6] == 1 and abs(r[3] - 100) < 0.01, "on the way back, round the end of its course: half way home")
    lua.execute("YRB.BoatData.test.path = nil")
    check(len(g.WHERE(5020)) == 0, "a route without a course: no place on the map")
    lua.execute("YRB.BoatData.test.path = { { 0, 0, 0 }, { 0, 0, 100 }, { 0, 0, 200 } }")
    lines = YR.BoatLines(0, 0, 0, 5010)
    check(lines[1][1] == "To Beta" and lines[1][2] == "in 1:30, leaves 1:50", f"at the dock it just left: back in 1:30, leaving in 1:50 ({lines[1][2]})")
    lines = YR.BoatLines(0, 0, 0, 5105)
    check(lines[1][2] == "in, leaves 0:15", f"lying at the dock: leaving in 0:15 ({lines[1][2]})")
    check(len(YR.BoatLines(0, 500, 0, 5010)) == 0, "away from the docks: nothing")
    # riding it: the departure is seen once it is away from the dock, told to the guild, and the arrival too
    lua.execute("""
        SENT = {}
        NOW, DEPART = 2000, 2003
        function Boat(t)
            local s = (t - DEPART) % 120
            if t < DEPART then return 0, 0 end
            if s < 40 then return s * 5, 0 elseif s < 60 then return 200, 0 elseif s < 100 then return 200 - (s - 60) * 5, 0 else return 0, 0 end
        end
        POS[1], POS[2], POS[4] = 0, 0, 0
        for _, f in ipairs(FRAMES) do if f.ev and f.ev.PLAYER_ENTERING_WORLD and f.ev.CHAT_MSG_ADDON then BOATS = f end end
        BOATS.OnEvent(BOATS, "ZONE_CHANGED_NEW_AREA")
        Ride(DEPART + 50)""")
    sent = [g.SENT[i][2] for i in range(1, len(g.SENT) + 1)]
    gos = [m for m in sent if m.startswith("1 O test 1 go")]
    ins = [m for m in sent if m.startswith("1 O test 2 in")]
    check(len(gos) == 2 and len(ins) == 2 and sorted(g.SENT[i][3] for i in range(1, 3)) == ["GUILD", "YELL"],
          f"a ride: its departure and its arrival told, to the guild (and nearby) ({sent})")
    seen = g.YippRouteDB.boatSeen.test
    check(seen is not None and seen["from"] == "you" and abs(seen.ref - (g.SERVER + (g.DEPART - 1000))) < 0.2,
          f"and kept: where in its round the boat is ({seen and seen.ref - g.SERVER})")
    # another player's: taken when newer, not when it can't be true, and never your own back
    t_new = seen.t + 5               # (between what was seen and now)
    _was_ref = seen.ref
    lua.execute(f"""BOATS.OnEvent(BOATS, "CHAT_MSG_ADDON", "HeadstartBoat", "1 O test 1 go {t_new:.2f}", "GUILD", "Other-Realm")""")
    check(abs(g.YippRouteDB.boatSeen.test.t - t_new) < 0.01 and g.YippRouteDB.boatSeen.test["from"] == "Other-Realm",
          "a guildmate's newer sighting: taken")
    _P = g.HeadstartNS.BoatData.test.period
    _want = ((g.YippRouteDB.boatSeen.test.ref - _was_ref + _P / 2) % _P) - _P / 2
    check(abs((g.YippRouteDB.boatSeen.test.shift or 999) - _want) < 0.05,
          f"and how far off the timetable was kept with it ({g.YippRouteDB.boatSeen.test.shift} s, {_want:.1f} wanted)")
    _seen = lua.eval("table.concat(HeadstartNS.BoatSeenLines(), ' / ')")
    check(("%+.1f s off the timetable" % _want) in _seen and "told by Other-Realm" in _seen,
          f"/headstart boats seen says it ({_seen})")
    lua.execute(f"""BOATS.OnEvent(BOATS, "CHAT_MSG_ADDON", "HeadstartBoat", "1 O test 1 go {t_new + 99999:.2f}", "GUILD", "Liar")""")
    check(g.YippRouteDB.boatSeen.test["from"] == "Other-Realm", "a time ahead of now: not taken")
    lua.execute(f"""BOATS.OnEvent(BOATS, "CHAT_MSG_ADDON", "HeadstartBoat", "1 O test 9 go {t_new + 5:.2f}", "GUILD", "Other")""")
    check(abs(g.YippRouteDB.boatSeen.test.t - t_new) < 0.01, "a dock the route hasn't: not taken")
    lua.execute(f"""BOATS.OnEvent(BOATS, "CHAT_MSG_ADDON", "HeadstartBoat", "1 O test 1 go {t_new + 5:.2f}", "WHISPER", "Other")""")
    check(abs(g.YippRouteDB.boatSeen.test.t - t_new) < 0.01, "a whisper: not taken (guild, group and nearby only)")
    # asked for the latest: answered (a few seconds later; at once here), and not again within a minute
    lua.execute("""SENT = {} BOATS.OnEvent(BOATS, "CHAT_MSG_ADDON", "HeadstartBoat", "1 Q", "GUILD", "Newcomer")""")
    sent = [g.SENT[i][2] for i in range(1, len(g.SENT) + 1)]
    check(any(m.startswith("1 O test 1 go") for m in sent), f"asked for the latest: answered with it ({sent})")
    lua.execute("""SENT = {} BOATS.OnEvent(BOATS, "CHAT_MSG_ADDON", "HeadstartBoat", "1 Q", "GUILD", "Newcomer2")""")
    check(len(g.SENT) == 0, "asked again within a minute: not answered twice")
    # logging in: the latest asked for, once
    lua.execute("""SENT = {} BOATS.OnEvent(BOATS, "PLAYER_ENTERING_WORLD", true, false)""")
    sent = [g.SENT[i][2] for i in range(1, len(g.SENT) + 1)]
    check(sent.count("1 Q") >= 1, f"a login: the latest asked for ({sent})")
    # quality of life off: none of it - not even the sharing
    g.YippRouteDB.qolOff = True
    YR.ApplyParts()
    lua.execute("SENT = {} BOATS.OnEvent = BOATS.OnEvent")
    check(not (g.BOATS.ev and g.BOATS.ev.CHAT_MSG_ADDON), "quality of life off: the addon channel is not listened to")
    g.YippRouteDB.qolOff = None
    YR.ApplyParts()
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
