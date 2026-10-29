"""Smoke test of Headstart as it is published: with no routes addon beside it. The window opens on every
page, with the routes on and off, and nothing errors - the names of the route planning's pages too (Next route,
All routes, the editor, Share: taken out 2026-10-29), which open another page.

    python tools/smoke_noroutes.py      (exit code 1 on any failure)

Uses smoke.py's fake game (everything above the line where it loads the addon).
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    src = open(os.path.join(ROOT, "tools", "smoke.py"), encoding="utf-8").read()
    env = {"__name__": "smoke_head", "__file__": os.path.join(ROOT, "tools", "smoke.py")}
    exec(compile(src.split("YR = lua.table()")[0], "smoke.py (head)", "exec"), env)
    lua = env["lua"]
    YR = lua.table()
    toc = [l.strip().replace(chr(92), "/") for l in open(os.path.join(ROOT, "Headstart.toc"), encoding="utf-8")
           if l.strip().endswith(".lua") and not l.startswith("#") and not l.startswith("Libs")]
    # and the window's addon (Headstart_Options, load on demand in the game), loaded after it
    for sub in ("Headstart_Setup", "Headstart_Options"):
        toc += [sub + "/" + l.strip().replace(chr(92), "/")
                for l in open(os.path.join(ROOT, sub, sub + ".toc"), encoding="utf-8")
                if l.strip().endswith(".lua") and not l.startswith("#") and not l.startswith("Libs")]
    for f in toc:
        lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)("Headstart", YR)
    g = lua.globals()
    lua.execute("C_Timer.After = function(_, fn) fn() end")
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    for routes in (True, False):
        g.YippRouteDB = lua.table(routes=routes)
        g.Fire("ADDON_LOADED", "Headstart")
        check(len(YR.shipped) == 0, f"routes {'on' if routes else 'off'}: no routes addon, nothing shipped")
        for page in ("run", "route", "settings", "instances", "where", "library", "routes", "share"):
            YR.ToggleWindow(YR, page)
        check(g.HeadstartWindow is not None and g.HeadstartWindow.hidden is False,
              "every page of the window opens with no routes, and the old pages' names open one")
        # Next route and All routes: only with a routes addon - without one, not in the menu, and This run in their place
        YR.ToggleWindow(YR, "where")
        want = "run" if routes else "routesoff"
        check(YR.WindowPage() == want and YR.TourTarget("levelling:where") is None and YR.TourTarget("levelling:library") is None,
              f"routes {'on' if routes else 'off'}, none installed: Next route and All routes not in the menu, {want} in their place ({YR.WindowPage()})")
        YR.ToggleWindow(YR)
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
