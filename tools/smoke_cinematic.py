"""Smoke test of Skip cinematics (Cinematic.lua), in Lua 5.1 (lupa).

    python tools/smoke_cinematic.py      (exit code 1 on any failure; tools/smoke.py runs it too)

A cinematic is ended as it starts, a moment after the game's own frame has had the event. On for a new
install (the one thing Headstart does unasked), off with its switch or the main one, not with Shift
held, not for a ride the game shows as a cinematic. Uses smoke.py's fake game.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def files(folder, toc):
    return [os.path.join(folder, l.strip().replace(chr(92), "/"))
            for l in open(os.path.join(folder, toc), encoding="utf-8")
            if l.strip().endswith(".lua") and not l.startswith("#") and not l.startswith("Libs")]


def run():
    src = open(os.path.join(ROOT, "tools", "smoke.py"), encoding="utf-8").read()
    env = {"__name__": "smoke_head", "__file__": os.path.join(ROOT, "tools", "smoke.py")}
    exec(compile(src.split("YR = lua.table()")[0], "smoke.py (head)", "exec"), env)
    lua = env["lua"]
    YR = lua.table()
    load = lua.eval("function(c, n) return assert(loadstring(c, n)) end")
    for f in files(ROOT, "Headstart.toc"):
        load(open(f, encoding="utf-8").read(), os.path.basename(f))("Headstart", YR)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    lua.execute("""STOPS, LATER, SAID, SHIFT = 0, {}, {}, false
        function StopCinematic() STOPS = STOPS + 1 end
        function IsShiftKeyDown() return SHIFT end
        C_Timer.After = function(s, fn) LATER[#LATER + 1] = { s, fn } end
        function Later() local l = LATER LATER = {} for _, w in ipairs(l) do w[2]() end end
        function Listening() local n = 0 for _, f in ipairs(FRAMES) do if f.ev.CINEMATIC_START then n = n + 1 end end return n end
        YippRouteDB = nil""")
    g.Fire("ADDON_LOADED", "Headstart")
    YR.Print = lua.eval("function(text) SAID[#SAID + 1] = text end")
    g.Fire("PLAYER_LOGIN")
    g.Later()                                    # (whatever the login put off)
    db = g.YippRouteDB

    check(db.skipCinematic is None and YR.SkipsCinematics() and g.Listening() == 1, "a new install: on, and listening for a cinematic's start with one frame")
    lua.execute("LATER, SAID = {}, {}")
    g.Fire("CINEMATIC_START", True)
    check(g.STOPS == 0 and len(g.LATER) == 1 and g.LATER[1][1] == 0,
          "a cinematic starts: not ended inside the event (the game's own frame must have it first), but a moment later")
    g.Later()
    check(g.STOPS == 1, "then it is ended")
    check(len(g.SAID) == 0, f"and nothing said in chat (it said so until 2026-10-21: nobody read it) ({list(g.SAID.values())})")
    g.Fire("CINEMATIC_START", True)
    g.Later()
    check(g.STOPS == 2 and len(g.SAID) == 0, "the next one is ended too")

    lua.execute("SHIFT = true")
    g.Fire("CINEMATIC_START", True)
    g.Later()
    check(g.STOPS == 2, "Shift held as it starts: left to play")
    lua.execute("SHIFT = false")
    g.Fire("CINEMATIC_START", False)
    g.Later()
    check(g.STOPS == 2, "a ride the game shows as a cinematic (one that can't be cancelled): left alone")
    g.Fire("CINEMATIC_START")
    g.Later()
    check(g.STOPS == 3, "started with nothing said about cancelling: ended")

    # off: nothing listens
    db.skipCinematic = False
    YR.ApplyParts()
    g.Fire("CINEMATIC_START", True)
    g.Later()
    check(g.Listening() == 0 and g.STOPS == 3 and not YR.SkipsCinematics(), "switched off: nothing listens, and a cinematic plays")
    db.skipCinematic = True
    YR.ApplyParts()
    g.Fire("CINEMATIC_START", True)
    g.Later()
    check(g.Listening() == 1 and g.STOPS == 4, "on again: ended again")
    db.skipCinematic = None
    db.qolOff = True
    YR.ApplyParts()
    g.Fire("CINEMATIC_START", True)
    g.Later()
    check(g.Listening() == 0 and g.STOPS == 4, "Quality of life switched off: this is off with it")
    db.qolOff = None
    YR.ApplyParts()
    check(g.Listening() == 1, "and on with it")
    check("skipCinematic" not in YR.STARTS_OFF, "it is not among what starts off")

    # Under the login's loading screen (a new character's opening flight starts while it is up): not ended until
    # it has gone - ended under it, the world was loaded again behind a second loading screen
    lua.execute("""STOPS, LATER = 0, {}
        function ScheduledNow() for _, w in ipairs(LATER) do if w[1] == 0 then return true end end return false end
        function ListeningLoad() local n = 0 for _, f in ipairs(FRAMES) do if f.ev.LOADING_SCREEN_DISABLED then n = n + 1 end end return n end""")
    YR.CinematicLoadingAgain()
    g.Fire("CINEMATIC_START", True)
    check(g.STOPS == 0 and not g.ScheduledNow(), "a cinematic under the login's loading screen: not ended yet")
    g.Fire("LOADING_SCREEN_DISABLED")
    g.Later()
    check(g.STOPS == 1 and g.ListeningLoad() == 0, "the loading screen gone: ended then, and the loading screen no longer listened for")
    # one that started before Headstart was loaded (no start of its own here): ended once the loading screen has gone
    lua.execute("STOPS, LATER = 0, {} KEPT_IN = InCinematic function InCinematic() return true end")
    YR.CinematicLoadingAgain()
    g.Fire("LOADING_SCREEN_DISABLED")
    g.Later()
    check(g.STOPS == 1, "one already running when Headstart loaded: ended once the loading screen has gone")
    lua.execute("function InCinematic() return false end STOPS, LATER = 0, {}")
    g.Fire("CINEMATIC_START", True)
    check(g.ScheduledNow(), "after the login, one that starts is ended a moment later as before")
    g.Later()
    check(g.STOPS == 0, "but not when it has already ended by then (nothing is stopped that isn't running)")
    lua.execute("InCinematic = KEPT_IN")

    # only the intro: past level 1 nothing listens, and a cinematic plays (the owner, 2026-10-16)
    lua.execute("KEPT_LEVEL = UnitLevel function UnitLevel() return 12 end STOPS, LATER = 0, {}")
    YR.ApplyParts()
    g.Fire("CINEMATIC_START", True)
    g.Later()
    check(g.Listening() == 0 and g.STOPS == 0 and YR.SkipsCinematics(),
          "a character past level 1: nothing listens, and a cinematic plays (the setting still on)")
    lua.execute("UnitLevel = KEPT_LEVEL")
    YR.ApplyParts()
    check(g.Listening() == 1, "back on a level 1 character: listening again")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
