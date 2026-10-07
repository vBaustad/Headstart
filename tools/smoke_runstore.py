"""Smoke test of where the run logs are kept (RunStore.lua), in Lua 5.1 (lupa).

    python tools/smoke_runstore.py           (exit code 1 on any failure; tools/smoke.py runs it too)
    python tools/smoke_runstore.py <saved file>   also packs every log of a real Headstart.lua and checks
                                                  each comes back the same, row for row

This character's log lives in its own saved file and is only lent to the account's table while you
play; another character's log still in the account's file is packed to text, checked, and comes back
the same when that character logs in.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r"""
ME = "Tester-Realm"
PARTS = {}
function time() return 5000 end
YR = { CharKey = function() return ME end, Part = function(want, events, handler) PARTS[#PARTS + 1] = { want = want, events = events, handler = handler } end }
-- two tables are the same thing: every key, every value, all the way down
function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
function Log(n, started)
    local r = { started = started, stopped = n == 3 and 77 or nil, track = {}, ev = {} }
    for i = 1, n do r.track[i] = { started + i * 2, 1426, 688.98 + i / 7, -6222.47, 12, 3400 + i, i % 3 } end
    for i = 1, math.floor(n / 4) do
        r.ev[i] = { started + i * 8, "accept", 179, 12, 3400, 1426, 0.5, 0.25, money = 1234 + i, npc = 'Talin "Keen" Keeneye',
            title = "A line\nand another \\ one", obj = i % 2 == 0 }
    end
    return r
end
"""


def run(real=None):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    YR = lua.eval("YR")
    lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, "RunStore.lua"), encoding="utf-8").read(), "RunStore.lua")("Headstart", YR)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    # packing: text for tables, checked, and the same log back
    lua.execute("BIG = Log(5000, 1000) STUB = YR.RunPack(BIG) BACK = YR.RunUnpack(STUB)")
    stub = g.STUB
    check(stub is not None and stub.samples == 5000 and stub.events == 1250 and stub.last == 11000 and stub.started == 1000,
          "a packed log says how big it was, when it began and when it was last played")
    check(len(stub.packed.track) == 3 and isinstance(stub.packed.track[1], str) and stub.track is None,
          f"its rows are text, a couple of thousand to a piece ({len(stub.packed.track)} pieces), and the tables are gone")
    check(lua.eval("Same(BIG, BACK)"), "unpacked it is the same log, every row and every field (quotes, line breaks, fractions and all)")
    check(lua.eval("YR.RunPack(STUB)") is None and lua.eval("YR.RunUnpack(BIG) == BIG"), "packing a packed log, or unpacking a whole one, changes nothing")
    lua.execute("""TEXT = 0
        for _, kind in ipairs({ "track", "ev" }) do for _, piece in ipairs(STUB.packed[kind]) do TEXT = TEXT + #piece / 1024 end end
        BACK = nil collectgarbage("collect") local a = collectgarbage("count") BIG = nil collectgarbage("collect")
        TABLES = a - collectgarbage("count")""")
    check(g.TEXT * 2 < g.TABLES, f"packed it takes well under half the memory ({g.TEXT:.0f} KB of text against {g.TABLES:.0f} KB of tables)")

    # a login: this character's log out of the account's file into its own; the others packed
    lua.execute("""YippRouteDB = { runs = { [ME] = Log(40, 100), ["Other-Realm"] = Log(3, 200), ["Third-Realm"] = Log(900, 300) } }
        MINE = YippRouteDB.runs[ME]
        PACKED = YR.RunsAttach()""")
    check(g.PACKED == 2 and lua.eval('YippRouteDB.runs["Other-Realm"].packed ~= nil and YippRouteDB.runs["Third-Realm"].samples == 900'),
          "the other characters' logs in the account's file are packed")
    check(lua.eval('YippRouteDB.runs["Other-Realm"].stopped == 77'), "what a log has beside its rows (stopped, here) is kept")
    check(lua.eval("HeadstartRunLog == MINE and YippRouteDB.runs[ME] == MINE"),
          "this character's log is its own file's now, and still reachable where it always was")
    check(g.YR.RunsAttach() == 0, "once a login")
    YR.StartRunStore()
    check(lua.eval("PARTS[1].want()") is True and list(lua.eval("PARTS[1].events").values()) == ["PLAYER_LOGOUT"],
          "the logout is listened for while this character has a log")
    lua.execute("PARTS[1].handler()")
    check(lua.eval("YippRouteDB.runs[ME] == nil and HeadstartRunLog == MINE"), "at logout the log is out of the account's file")

    # the other character logs in: its packed log comes back whole, in its own file
    lua.execute("""ORIGINAL = Log(900, 300)""")
    YR2 = lua.eval("{ CharKey = function() return 'Third-Realm' end, Part = YR.Part }")
    lua.execute("HeadstartRunLog = nil")
    lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, "RunStore.lua"), encoding="utf-8").read(), "RunStore.lua")("Headstart", YR2)
    YR2.RunsAttach()
    check(lua.eval('Same(HeadstartRunLog, ORIGINAL) and YippRouteDB.runs["Third-Realm"] == HeadstartRunLog'),
          "another character logs in: its packed log is whole again, in its own file")
    # a character with no log at all, and one whose own file is the newer
    YR3 = lua.eval("{ CharKey = function() return 'Nobody-Realm' end, Part = YR.Part }")
    lua.execute("HeadstartRunLog = nil")
    lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, "RunStore.lua"), encoding="utf-8").read(), "RunStore.lua")("Headstart", YR3)
    YR3.RunsAttach()
    YR3.StartRunStore()
    check(lua.eval('HeadstartRunLog == nil and YippRouteDB.runs["Nobody-Realm"] == nil') and lua.eval("PARTS[#PARTS].want()") is False,
          "a character with no log: nothing made, and its logout not listened for")

    if real:
        lua.globals().SRC = open(real, encoding="utf-8", errors="replace").read()
        report = lua.eval(r"""(function()
            assert(loadstring(SRC, "saved"))()
            SRC = nil
            local out, wrong = {}, 0
            for name, r in pairs(YippRouteDB.runs or {}) do
                if type(r) == "table" and not r.packed then
                    local stub = YR.RunPack(r)
                    local back = stub and YR.RunUnpack(stub)
                    local same = back ~= nil and Same(r, back)
                    if not same then wrong = wrong + 1 end
                    out[#out + 1] = ("  %-30s %6d rows, %5d events: %s"):format(name, #(r.track or {}), #(r.ev or {}), same and "the same back" or "NOT THE SAME")
                end
            end
            table.sort(out)
            return table.concat(out, "\n"), wrong
        end)()""")
        print(report[0])
        check(report[1] == 0, f"every log of the real saved file comes back the same ({report[1]} wrong)")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run(sys.argv[1] if len(sys.argv) > 1 else None) else 0)
