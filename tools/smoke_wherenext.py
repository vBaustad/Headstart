"""Smoke test of WhereNext.lua (which route a hand-levelled character should pick up, and where), in Lua 5.1 (lupa).

    python tools/smoke_wherenext.py      (exit code 1 on any failure)
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
DONE = {}
LOADED, STEP, ROUTES = nil, nil, true
ROUTE = {
    low  = { name = "11-13 Loch Modan", steps = {
        "step\n    .accept 1 >> A", "step\n    .turnin 1 >> A", "step\n    .accept 2 >> B\n    .turnin 2 >> B" } },
    fits = { name = "19-21 Darkshore", steps = {
        "step\n    .fly Auberdine", "step\n    .accept 10 >> C", "step\n    .complete 10,1", "step\n    .turnin 10 >> C",
        "step\n    .vendor >> Sell", "step\n    .goto 1,2,3 >> Walk north", "step\n    .accept 11 >> D",
        "step\n    .turnin 11 >> D\n    .accept 12 >> E", "step\n    .turnin 12 >> E" } },
    alt  = { name = "19-20 Redridge", steps = {
        "step\n    .accept 20 >> F", "step\n    .turnin 20 >> F" } },
    wide = { name = "20-23 Ashenvale", steps = {
        "step\n    .accept 30 >> G", "step\n    .turnin 30 >> G", "step\n    .turnin 31 >> H", "step\n    .turnin 32 >> I",
        "step\n    .turnin 33 >> J" } },
    up   = { name = "23-24 Wetlands", steps = { "step\n    .accept 40 >> K", "step\n    .turnin 40 >> K" } },
    far  = { name = "27-30 Hillsbrad", steps = { "step\n    .accept 50 >> L", "step\n    .turnin 50 >> L" } },
}
RXP = { guides = {}, LoadGuide = function(self, g) LOADED = g.name end, SetStep = function(n) STEP = n end }
for key, r in pairs(ROUTE) do RXP.guides[key] = { name = r.name, group = "Headstart Launch (A)" } end
RXP.guides.other = { name = "19-21 Darkshore", group = "RestedXP Forever Guide (A)" }
RXP.guides.pad = { name = "05-11 Dun Morogh", group = "Headstart Launch (A)" }
ROUTE.pad = { name = "5-11 Dun Morogh", steps = { "step\n    .turnin 60 >> M" } }
function UnitLevel() return 20 end
function CreateFrame() return {} end
''')
    YR = lua.table()
    YR.Style = lua.table()
    YR.shipped = lua.eval('{ { key = "low" }, { key = "fits" }, { key = "alt" }, { key = "wide" }, { key = "up" }, { key = "far" } }')
    YR.GuideName = lua.eval("function(key) return ROUTE[key].name end")
    YR.GuideText = lua.eval(r'function(self, key) return "#group Headstart Launch (A)\n#name " .. ROUTE[key].name end')
    YR.CharSteps = lua.eval("function(key) return ROUTE[key].steps end")
    YR.RoutesOn = lua.eval("function() return ROUTES end")
    YR.Print = lua.eval("function() end")
    chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, "WhereNext.lua"), encoding="utf-8").read(), "WhereNext.lua")
    chunk("Headstart", YR)
    done = lua.eval("function(id) return DONE[id] == true end")
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def order(level):
        return [(str(r.key), r.left, r.first, str(r.note)) for r in YR.WhereNext(level, done).values()]

    # a level 20 that did the first Darkshore quest by hand, and all of Loch Modan
    lua.execute("for _, id in ipairs({ 1, 2, 10 }) do DONE[id] = true end")
    r = YR.RouteProgress("fits", done)
    check((r.total, r.done, r.left) == (3, 1, 2), f"a route's quests: 3, 1 done, 2 left: {r.total, r.done, r.left}")
    check(r.first == 5, f"start at the first quest not done, with the way there before it (vendor, walk): step {r.first}")
    got = order(20)
    check(got[0][0] == "wide" and got[1][0] == "fits",
          f"at 20: the routes that hold your level first, the one with the most left on top: {[g[0] for g in got]}")
    check([g[0] for g in got[2:]] == ["up", "far", "alt", "low"],
          f"then the next ones up (nearest first), one ending at your level, and last a finished one: {[g[0] for g in got[2:]]}")
    check(got[-1][3] == "all done" and got[-1][2] is None and got[2][3] == "next up" and got[4][3] == "ends at your level",
          f"each says how it sits: {[g[3] for g in got]}")
    check(order(26)[0][0] == "far" and order(26)[0][3] == "next up", "at 26, between routes: the next one up")
    check(order(40)[0][3] == "below your level", "past every route: what's left below, said so")
    untouched = YR.RouteProgress("wide", done)
    check(untouched.first == 1, "nothing done in a route: from its first step")

    ok = YR.LoadRouteAt("fits", 5)
    check(ok is True and str(lua.globals().LOADED) == "19-21 Darkshore" and lua.globals().STEP == 5,
          "loads our guide in RestedXP (not RestedXP's own of the same name) and goes to the step")
    check(YR.LoadRouteAt("pad", 1) is True and str(lua.globals().LOADED) == "05-11 Dun Morogh",
          "finds a route RestedXP lists with a padded level range")
    lua.execute("ROUTES = false")
    off = YR.LoadRouteAt("fits", 5)
    check(off[0] is None and "off" in str(off[1]), "routes off: not loaded, and why")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
