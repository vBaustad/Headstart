"""Smoke test of the tour (Headstart_Options/Welcome.lua), in Lua 5.1 (lupa).

    python tools/smoke_welcome.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Hints over Headstart's window, read through or skipped, that turn nothing on; when it is first put up on
a new install, and what waits for it. Uses smoke.py's fake game (smoke.py has the tour in the real window).
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

    # a new install; the welcome is asked for a few seconds after the login, and the window's addon loaded for it
    lua.execute("""LOADS, LATER = {}, {} C_AddOns = C_AddOns or {}
        C_AddOns.LoadAddOn = function(name) LOADS[#LOADS + 1] = name return false, "MISSING" end
        C_Timer.After = function(s, fn) LATER[#LATER + 1] = { s, fn } end
        YippRouteDB = nil""")
    g.Fire("ADDON_LOADED", "Headstart")
    g.Fire("PLAYER_LOGIN")
    waits = [w[1] for w in g.LATER.values()]
    check(g.YippRouteDB.welcome is True and 5 in waits and len(g.LOADS) == 0, "a new install: the welcome is due five seconds after the login, nothing loaded yet")
    g.YippRouteDB.welcomeSeen = True
    lua.execute("for _, w in ipairs(LATER) do if w[1] == 5 then w[2]() end end")
    check(len(g.LOADS) == 0, "seen already: the window's addon isn't loaded for it again")
    g.YippRouteDB.welcomeSeen = None
    g.HeadstartNS = YR
    load(open(os.path.join(ROOT, "Headstart_Options", "Welcome.lua"), encoding="utf-8").read(), "Welcome.lua")()

    db = g.YippRouteDB
    lua.execute("HeadstartNS.ShowSettingsTab = function() end")      # (the window's own: not loaded here)
    lua.execute("getmetatable(UIParent).HookScript = function(self, _, fn) self.hook = fn end")     # (kept, to press below)
    steps = YR.TourSteps()
    check(len(steps) == 10 and steps[1].next == "Show me around" and steps[10].next == "Done"
          and all(st.title and st.text for st in steps.values()) and all(st.at for i, st in steps.items() if i > 1),
          f"ten hints: a welcome, then each pointing at a part of the window ({len(steps)})")
    before = {k: db[k] for k in ("autoTrain", "restock", "bankAuto", "lootFeed", "chatLog", "flightTimer", "camp", "setupOn", "routes")}
    db.welcome, db.welcomeSeen = True, None
    check(YR.WelcomeShow() is True and g.HeadstartTour is not None and not g.HeadstartTour.hidden and db.welcomeSeen is True,
          "the tour opens, and is marked as seen")
    w = g.HeadstartTour
    check(w.title.text == "Welcome to Headstart" and w.back.hidden and not w.skip.hidden and w.next.text.text == "Show me around",
          "the first hint: the welcome, Show me around, Skip, no Back")
    lua.execute("local b = HeadstartTour.next b.fn(b)")
    check(w.title.text == "Find any setting" and w.count.text == "2 of 10" and not w.back.hidden, "Next: the second hint")
    lua.execute("local b = HeadstartTour.back b.fn(b)")
    check(w.title.text == "Welcome to Headstart", "Back: the first again")
    lua.execute("local b = HeadstartTour.next for i = 1, 9 do b.fn(b) end")
    check(w.title.text == "Quality of life" and w.next.text.text == "Done" and w.skip.hidden, "the last hint: Done, no Skip")
    lua.execute("local b = HeadstartTour.next b.fn(b)")
    check(w.hidden and db.welcome is None, "Done: the tour goes, a new install's welcome looked at")
    check({k: db[k] for k in before} == before, "and nothing was turned on or off by it")
    check(YR.WelcomeToggle() is True and not w.hidden and YR.WelcomeToggle() is False and w.hidden,
          "/headstart start: open when closed, closed when open")
    YR.WelcomeShow()
    lua.execute("local b = HeadstartTour.skip b.fn(b)")
    check(w.hidden, "Skip: gone at any hint")
    YR.WelcomeShow()
    lua.execute("HeadstartTour:GetParent():Hide()")
    lua.execute("HeadstartTour.fn(HeadstartTour)")          # (its OnHide, as the window closes)
    check(w.hidden, "the window closed under it: the tour is not back the next time the window opens")
    lua.execute("HeadstartTour:GetParent():Show()")

    # The first, unasked showing (Core.lua, YR.WelcomeFirst): a small card since 2026-10-29, not the window and
    # its tour ("vi ikke lar headstart åpne fullt når du logger inn for første gang" - the owner). A new install's
    # very first login is a new character's, and that plays its flight over the zone with the interface hidden:
    # the tour was put up under it, closed by the Escape that ended the flight, and written down as seen
    # (2026-10-13). The same rules hold for the card.
    lua.execute("""UI_UP, IN_MOVIE, LATER = false, true, {}
        UIParent.IsVisible = function() return UI_UP end
        function InCinematic() return IN_MOVIE end
        HeadstartNS.WelcomeCard()
        if HeadstartWindow then HeadstartWindow:Hide() end
        HeadstartTour:Hide()
        WIN = HeadstartWelcomeCard
        WIN.IsVisible = function(self) return UI_UP and self:IsShown() end
        HeadstartTour.IsVisible = WIN.IsVisible
        function Tick() local l = LATER LATER = {} for _, w in ipairs(l) do w[2]() end return #LATER end
        function First() WIN:Hide() LATER = {} YippRouteDB.welcome, YippRouteDB.welcomeSeen = true, nil
            HeadstartNS.WelcomeFirst() end""")
    was, YR.windowLoaded = YR.windowLoaded, True
    win = g.WIN
    g.First()
    check(len(g.LATER) == 1 and g.LATER[1][1] == 5, "a new install: looked for five seconds after the login")
    left = g.Tick()
    check(win.hidden and db.welcomeSeen is None and left == 1 and g.LATER[1][1] == 2,
          "the interface is hidden (a new character's opening flight): not put up under it, looked for again in two seconds")
    lua.execute("UI_UP = true")
    g.Tick()
    check(win.hidden and db.welcomeSeen is None, "nor over a cinematic that leaves the interface up")
    lua.execute("IN_MOVIE = false")
    g.Tick()
    check(not win.hidden and db.welcomeSeen is None, "the screen is there: put up - and not counted as seen for that")
    check(g.HeadstartTour.hidden and (g.HeadstartWindow is None or g.HeadstartWindow.hidden),
          "the card alone: not Headstart's window, not the tour")
    lua.execute("WIN:Hide()")                   # Escape, or whatever closes every window
    g.Tick()
    check(not win.hidden and db.welcomeSeen is None, "closed before it could be read: put up once more")
    g.Tick()
    check(db.welcomeSeen is None, "up at one look: not yet")
    left = g.Tick()
    check(db.welcomeSeen is True and left == 0, "up at two: seen, and nothing looks any more")
    # closed twice: left alone for now, and the next login asks again
    g.First()
    g.Tick()
    lua.execute("WIN:Hide()")
    g.Tick()
    lua.execute("WIN:Hide()")
    left = g.Tick()
    check(win.hidden and db.welcomeSeen is None and left == 0, "closed twice: not put up a third time, still not seen (the next login asks)")
    # a click in it is an answer, and it goes (the window's functions are stand-ins here, as ShowSettingsTab is:
    # what each button asks for is said, and smoke.py presses them against the real window)
    lua.execute("""OPENED, SETUP_ON = nil, nil
        HeadstartNS.ToggleWindow = function(_, page) OPENED = page or "window" end
        HeadstartNS.SetSetupOn = function(on) SETUP_ON = on end""")
    for name, press in (("Later", "WIN.later.fn(WIN.later)"), ("Show me around", "WIN.tour.fn(WIN.tour)"),
                        ("Set up this character", "WIN.setup.fn(WIN.setup)")):
        lua.execute("if HeadstartWindow then HeadstartWindow:Hide() end HeadstartTour:Hide()")
        g.First()
        g.Tick()
        shown = not win.hidden and db.welcomeSeen is None
        lua.execute(press)
        check(shown and db.welcomeSeen is True and db.welcome is None and win.hidden, f"{name} pressed: seen, and the card goes")
        check(g.Tick() == 0, "and nothing looks any more")
        if name == "Later":
            check(g.HeadstartWindow is None or g.HeadstartWindow.hidden, "Later: nothing else opens")
        elif name == "Show me around":
            check(not g.HeadstartTour.hidden and g.SETUP_ON is None, "Show me around: the tour")
        else:
            check(g.SETUP_ON is True and g.OPENED == "setup",
                  f"Set up this character: Character setup turned on, and its tab asked for ({g.SETUP_ON}, {g.OPENED})")
    # what it says: a new install - nothing changed, set up this character; a character Character setup has put its bars
    # on already (a YippYapp-oppsett install's Classic, Headstart as new) - its bars and keys are on, and no Set up
    lua.execute("YippSetupCharDB = nil")
    YR.WelcomeCard()
    first = (win.text.text, win.setup.hidden)
    lua.execute("YippSetupCharDB = { applied = 1761700000 }")
    YR.WelcomeCard()
    done = (win.text.text, win.setup.hidden)
    lua.execute("YippSetupCharDB = nil WIN:Hide()")
    check(first[0].startswith("Nothing that acts for you is on") and not first[1],
          "a new install's card: nothing changed yet, Set up this character offered")
    check(done[0].startswith("This character's bars and keys are on") and done[1] is True,
          "a character already set up from YippYapp-oppsett: its bars and keys are on, and no Set up button")
    # asked for by hand (/headstart start, the button in the settings): seen at once, as before
    g.First()
    YR.WelcomeShow()
    check(db.welcomeSeen is True, "asked for by hand: seen")
    # in a fight at the login: not then, and looked for again
    lua.execute("function InCombatLockdown() return true end")
    g.First()
    left = g.Tick()
    check(win.hidden and left == 1, "in a fight: not put up, looked for again")
    lua.execute("function InCombatLockdown() return false end")
    g.Tick()
    check(not win.hidden, "the fight over: put up")
    # the window's addon is not there: said once, and not asked for every two seconds
    lua.execute("SAID = 0 local p = HeadstartNS.Print HeadstartNS.Print = function(...) SAID = SAID + 1 end WIN:Hide()")
    YR.windowLoaded = None
    g.First()
    left = g.Tick()
    check(g.SAID == 1 and left == 0 and db.welcomeSeen is None, "the window's addon missing: said once, not asked for again this login")
    YR.windowLoaded = was

    # What speaks up by itself at a login (the reminders) waits until the welcome is answered or closed
    YR.windowLoaded = True
    lua.execute("SAIDLIST = {} WIN:Hide() HeadstartTour:Hide()")
    g.First()
    lua.execute("HeadstartNS.AfterWelcome(function() SAIDLIST[#SAIDLIST + 1] = 'reminders' end)")
    check(len(g.SAIDLIST) == 0 and YR.WelcomeHolds(), "a new install's first login: the reminders wait for the welcome")
    g.Tick()
    check(not win.hidden and len(g.SAIDLIST) == 0, "the welcome up: still waiting")
    g.Tick()
    g.Tick()
    check(db.welcomeSeen is True and YR.WelcomeHolds() and len(g.SAIDLIST) == 0 and len(g.LATER) == 0,
          "seen, not answered (still up): still waiting, and nothing ticks for it")
    lua.execute("WIN:Hide() WIN.hook(WIN)")             # closed: its OnHide
    g.Tick()
    g.Tick()
    check(list(g.SAIDLIST.values()) == ["reminders"] and not YR.WelcomeHolds(), "closed: the reminders are said, a few seconds on")
    lua.execute("HeadstartNS.AfterWelcome(function() SAIDLIST[#SAIDLIST + 1] = 'later' end)")
    check(len(g.SAIDLIST) == 2, "and anything after that is said at once")
    # no welcome this login (an account that has answered it): nothing waits
    lua.execute("YippRouteDB.welcomeSeen = true HeadstartNS.WelcomeFirst() HeadstartNS.AfterWelcome(function() SAIDLIST[#SAIDLIST + 1] = 'at once' end)")
    check(len(g.SAIDLIST) == 3 and not YR.WelcomeHolds(), "no welcome at this login: nothing waits")
    YR.windowLoaded = was
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
