"""Generate Data/Boats.lua (for Boats.lua): every boat and zeppelin's timetable, from rounds measured in the game.

    python tools/gen_boats.py [SavedVariables/Headstart.lua ...]   (default: every account under the beta's WTF, and
                                                                    the saved files backed up beside it)

The rounds are the owner's, timed with /headstart boats (YippRouteDB.boatTimes): a transport ridden from leaving
a dock to leaving it again. Each route's timetable is worked out by Boats.lua's own YR.BoatTimetable (run here
in Lua, so the names and offsets are the addon's): its period, when it left its first dock by the realm's clock
on the round measured, and for each dock where it lies and how many seconds into the round it arrives and
leaves. Rounds under two minutes are no rounds (a dock's creep taken for a departure); of the rest, the newest.
Where a route has two rounds far enough apart, the period is worked out between their departures from the same
dock: the whole number of rounds between them, and the time.
Its course is the game's own: the transport's taxi path (taxipathnode) whose stops (the nodes it waits at) are
the route's docks - every route measured has one, Forever's own too - so the timer can put each boat on the
map wherever it is in its round.
    YR.BoatData[route] = { period, ref, docks = { { name, map, x, y, arrive, leave, node }, ... },
                           path = { { continent, X, Y }, ... } }      (X, Y: the world's, as UnitPosition's first two)
"""
import glob
import math
import os
import sys

import duckdb
import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Data", "Boats.lua")
WTF = r"S:\Blizzard\World of Warcraft\_classic_beta_\WTF\Account\*\SavedVariables\Headstart.lua"
# the saved files moved out for a fresh-install test (2026-10-15): the rounds measured before are in them
BACKUPS = r"S:\Blizzard\World of Warcraft\_classic_beta_\HeadstartBackup_*\WTF\Account\*\SavedVariables\Headstart.lua"
DB = r"S:\forever-data\db\forever.duckdb"


def transport_paths():
    """{ path id: [ (continent, X, Y, delay), ... ] in order }: every taxi path that waits somewhere - a transport's."""
    c = duckdb.connect(DB, read_only=True)
    schema = c.sql("select schema_name from main.builds where schema_name like 'wow_classic_beta_%' order by schema_name desc limit 1").fetchone()[0]
    out = {}
    for pid, cont, x, y, delay in c.sql(f"""select cast(PathID as int), cast(ContinentID as int), cast("Loc[0]" as double),
            cast("Loc[1]" as double), cast(Delay as int) from {schema}.taxipathnode
            where PathID in (select PathID from {schema}.taxipathnode where cast(Delay as int) > 0)
            order by cast(PathID as int), cast(NodeIndex as int)""").fetchall():
        out.setdefault(pid, []).append((cont, x, y, delay))
    return out, schema


def course(paths, docks):
    """The path whose stops are these docks (map, x, y as measured: x the world's Y, y its X), and each dock's node."""
    best = None
    for pid, nodes in paths.items():
        total, at = 0, []
        for m, dx, dy in docks:
            near = min(((math.hypot(n[1] - dy, n[2] - dx), i) for i, n in enumerate(nodes) if n[0] == m and n[3] > 0),
                       default=(1e9, None))
            total += near[0]
            at.append(near[1])
        if all(a is not None for a in at) and total / len(docks) < 60 and (best is None or total < best[1]):
            best = (pid, total, at)
    return best


def main():
    paths = sys.argv[1:] or sorted(glob.glob(WTF)) + sorted(glob.glob(BACKUPS))
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        local F = {} F.__index = F
        function F:RegisterEvent() end function F:UnregisterEvent() end function F:SetScript() end function F:UnregisterAllEvents() end
        function CreateFrame() return setmetatable({}, F) end
        C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
        function GetTime() return 0 end function GetServerTime() return 0 end
        date = os.date SlashCmdList = {} strsplit = function() end strtrim = function(s) return s end
        function UnitClass() return "Paladin", "PALADIN" end function UnitLevel() return 1 end function UnitName() return "Me" end
        YippRouteDB = {}
    """)
    YR = lua.table()
    for name in ("Core.lua", "Boats.lua"):
        lua.eval("function(c, n) return assert(loadstring(c, n)) end")(open(os.path.join(ROOT, name), encoding="utf-8").read(), name)(
            "Headstart", YR)
    routes = {r[1]: r[2] for r in YR.BoatRoutes().values()}
    order = [r[1] for r in YR.BoatRoutes().values()]
    # each saved file read into this same Lua, in a table of its own (its YippRouteDB not over this one's)
    saved = lua.eval("""function(src)
        local f = assert(loadstring(src))
        local env = {}
        setfenv(f, env)
        f()
        return env.YippRouteDB and env.YippRouteDB.boatTimes
    end""")
    read, found = {}, {}
    for path in paths:
        times = saved(open(path, encoding="utf-8", errors="replace").read())
        if not times:
            continue
        read[path] = times
        for key, rounds in times.items():
            for i in range(1, len(rounds) + 1):
                found.setdefault(key, []).append((rounds[i].left or 0, path, i))

    def load(path):
        return read[path]

    lines = ["-- GENERATED by tools/gen_boats.py from rounds measured in the game (/headstart boats). Do not edit; regenerate.",
             "-- [route] = { period = seconds a round, ref = the realm's clock as it left its first dock on the round",
             "--   measured, docks = { { name, map (0 the Eastern Kingdoms, 1 Kalimdor), x, y (where it lies), arrive, leave",
             "--   (seconds into the round), node (its place on the path) }, ... }, path = its course, the game's own taxi",
             "--   path: { { continent, X, Y }, ... } (the world's X and Y, as UnitPosition's first two) }",
             "local _, YR = ...",
             "YR.BoatData = {"]
    made = 0
    tpaths, schema = transport_paths()
    lines[0] += " Courses: " + schema + "."
    for key in order:
        tts = []
        for left, path, i in sorted(found.get(key, [])):
            r = load(path)[key][i]
            tt = YR.BoatTimetable(r, routes[key])
            if tt:
                tts.append((tt, r))
        if not tts:
            continue
        tt, r = tts[-1]
        period, ref = tt.period, tt.left
        # two rounds: the period from their departures from the same first dock, a whole number of rounds apart
        if len(tts) > 1:
            a, b = tts[0][0], tts[-1][0]
            n = round((b.left - a.left) / period)
            if n >= 2 and abs((b.left - a.left) / n - period) < 0.5:
                period = (b.left - a.left) / n
        places = []
        for j in range(1, len(tt.docks) + 1):
            d = tt.docks[j]
            # where it lies: the departure's place on the round
            go = [e for e in (r.events[k] for k in range(1, len(r.events) + 1)) if e.kind == "go" and abs((e.t - tt.left) - d.leave) < 0.01]
            places.append((d, (go[0].x, go[0].y) if go else (0, 0)))
        found_course = course(tpaths, [(d.map, x, y) for d, (x, y) in places])
        docks = []
        for j, (d, (x, y)) in enumerate(places):
            arrive = "nil" if d.arrive is None else "%.2f" % d.arrive
            node = "nil" if not found_course else str(found_course[2][j] + 1)
            docks.append('{ "%s", %d, %.1f, %.1f, %s, %.2f, %s }' % (d.name.replace('"', '\\"'), d.map, x, y, arrive, d.leave, node))
        path = ""
        if found_course:
            nodes = tpaths[found_course[0]]
            path = ", path = { %s }" % ", ".join("{ %d, %.1f, %.1f }" % (n[0], n[1], n[2]) for n in nodes)
        lines.append("    %s = { period = %.3f, ref = %.2f, docks = { %s }%s }," % (key, period, ref, ", ".join(docks), path))
        made += 1
    lines += ["}", ""]
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print(f"{made} routes' timetables from {len(paths)} saved file(s)")


if __name__ == "__main__":
    main()
