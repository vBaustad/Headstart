"""Smoke test of the welcome window's answers (Headstart_Options/Welcome.lua), in Lua 5.1 (lupa).

    python tools/smoke_welcome.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Four questions (routes, on your screen, does things for you, new characters), each answered by
itself: what the answers turn on is what the window says, and Apply sets exactly that. Uses smoke.py's fake game.
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

    T = lua.eval("function(r, s, a, u) return { routes = r, screen = s, acts = a, setup = u } end")

    def plan(answers):
        return {p.key: p for p in YR.WelcomePlan(answers).values()}

    def on(answers, q=None):
        return sorted(k for k, p in plan(answers).items() if p.on and (q is None or p.q == q))

    check([q.key for q in YR.WelcomeQuestions().values()] == ["routes", "screen", "acts", "setup"], "four questions")
    check(on(T(0, 0, 0, 0)) == [], "nothing to every question: nothing of ours on your screen, nothing done for you")
    ess = on(T(None, 1, None, None), "screen")
    check("xpbar" not in ess and "lootFeed" in ess and "chatLog" in ess and "deathRecap" in ess and "flightTimer" in ess and "swing" not in ess,
          f"on your screen, Essentials: what's good to see - not the XP bar, which many have another addon draw ({len(ess)})")
    every = on(T(None, 2, None, None), "screen")
    check(set(ess) < set(every) and "xpbar" in every and "swing" in every and "trinketBar" in every and "talentMove" in every,
          f"Everything: the XP bar, the swing timer and the buttons too ({len(every)})")
    check(on(T(None, None, 1, None), "acts") == ["acceptFrom", "acceptInvites", "whisperInvite"],
          "does things for you, For friends: invites and shared quests - nothing that spends gold or moves items")
    check(set(on(T(None, None, 2, None), "acts")) == {"acceptFrom", "acceptInvites", "whisperInvite", "restock", "autoTrain", "bankAuto", "levelShot",
                                                     "pickRewards"},
          "Everything: restock, training, banking, picked quest rewards and screenshots too")
    # a new install acts for you in nothing: "Nothing" is what it has, quest rewards included
    check(YR.WelcomeNow().acts == 0 and not YR.RewardSettings(YR).on,
          "a new install: Automation is at Nothing as it comes - no reward is picked for you either")
    names = [c.name for c in YR.WelcomeChecks().values()]
    check(names == ["Nothing here needs setting", "Installing changed nothing of yours", "New on your screen"],
          f"Before you play on a new install: nothing to set, and what installing did not touch ({names})")
    # the questions are answered each by itself: every bar and nothing automated, or the other way round
    mixed = plan(T(None, 2, 0, None))
    check(mixed["swing"].on and not mixed["restock"].on and not mixed["acceptInvites"].on, "every bar and nothing automated is an answer")
    mixed = plan(T(None, 0, 2, None))
    check(not mixed["xpbar"].on and not mixed["camp"].on and mixed["restock"].on, "and so is no bars and all the automation")
    # a question left unanswered: as it is
    before = {k: p.now for k, p in plan(T(None, None, None, None)).items()}
    check(all(p.on == before[k] for k, p in plan(T(None, None, None, None)).items()), "no answers: everything as it is")
    line = YR.WelcomeLine("acts", YR.WelcomePlan(T(None, None, 1, None)))
    check(line.startswith("On: accept friends' invites") and "restock" not in line, f"an answer in words ({line})")
    check(YR.WelcomeLine("acts", YR.WelcomePlan(T(None, None, 0, None))) == "Nothing of it on.", "and nothing in words")

    # the quick picks
    rec, mini, full = YR.WelcomeQuick("recommended"), YR.WelcomeQuick("minimal"), YR.WelcomeQuick("everything")
    check(rec.screen == 1 and rec.acts == 1 and rec.routes is None and rec.setup is None,
          "Recommended: essentials on screen, helpful for friends; routes and Character setup left as they are")
    check((mini.routes, mini.screen, mini.acts, mini.setup) == (0, 0, 0, 0) and (full.routes, full.screen, full.acts, full.setup) == (1, 2, 2, 1)
          and YR.WelcomeQuick("nonsense") is None, "Minimal and Everything answer all four")

    # applied: exactly the plan, and counted
    db = g.YippRouteDB
    turned = YR.WelcomeApply(rec)
    check(turned[0] > 0 and turned[2] is False and not YR.XPBarOn() and YR.Option("lootFeed") and YR.Option("chatLog") and YR.Option("deathRecap")
          and YR.AcceptInvitesSet() == "friends" and not YR.Option("restock") and not YR.Option("autoTrain") and not YR.SetupOn(),
          f"Recommended applied: its things on, nothing that spends ({turned[0]} on, {turned[1]} off), no reload")
    check(db.welcome is None, "answered: it isn't asked again")
    checks = {c.name: c for c in YR.WelcomeChecks().values()}
    check("Invites are answered for you" in checks and "The XP bar stands in for Blizzard's" not in checks
          and "Class trainer spends gold" not in checks and "Restock spends gold" not in checks and "Nothing here needs setting" not in checks
          and checks["Invites are answered for you"].page == "group",
          f"Before you play after Recommended: the invites, nothing about gold - and Blizzard's XP bar is still yours ({sorted(checks)})")
    check(YR.WelcomeApply(rec)[0:2] == (0, 0), "applied again: nothing left to change")
    now = YR.WelcomeNow()
    check(now.screen == 1 and now.acts == 1 and now.setup == 0, "what you have now is read back as those answers")
    kept = {k: db[k] for k in ("autoTrain", "restock", "bankAuto", "pickRewards", "levelShot")}
    YR.WelcomeApply(lua.eval("{ acts = 2 }"))
    names = [c.name for c in YR.WelcomeChecks().values()]
    check(names[:3] == ["Class trainer spends gold", "Restock spends gold", "Bank deposit moves your items"]
          and "Quest rewards are picked for you" in names and names[-2:] == ["Installing changed nothing of yours", "New on your screen"]
          and len(names) <= 8 and all(len(c.note) <= 235 for c in YR.WelcomeChecks().values()),
          f"Before you play with all the automation on: what spends gold first, then what moves items ({names})")
    check(YR.RewardSettings(YR).on is True and db.pickRewards is True, "quest reward picking turned on by its answer, for this class and the ones to come")
    YR.WelcomeApply(lua.eval("{ acts = 1 }"))
    check(not YR.RewardSettings(YR).on and not YR.Option("autoTrain"), "and off again with it")
    db.restock = True
    check(YR.WelcomeNow().acts is None, "one thing set by hand: that question matches no answer, and is left as it is unless you answer it")
    turned = YR.WelcomeApply(full)
    check(YR.Option("restock") and YR.Option("bankAuto") and YR.WhisperInviteSet() == "friends" and YR.AcceptFromSet() == "friends"
          and YR.Option("levelShot") and YR.SetupOn() and YR.RoutesOn() and turned[2] is True,
          "Everything applied: all of it, and the routes turned on take a reload")
    turned = YR.WelcomeApply(mini)
    check(not YR.XPBarOn() and not YR.Option("lootFeed") and not YR.Option("flightTimer") and not YR.Option("camp") and not YR.Option("restock")
          and YR.AcceptInvitesSet() == "off" and not YR.RoutesOn() and not YR.SetupOn()
          and turned[1] == len([k for k, f in plan(full).items() if not f.quiet]),
          f"Minimal applied: every one of them off ({turned[1]})")
    # "Nothing" is nothing: what no answer turns on but acts for you all the same goes off with it, and
    # stays as it is under the other answers; "Friends only" narrows a wider choice
    db.mailAuto, db.shareAll, db.trinketAuto = True, True, True
    check(plan(T(None, None, 2, None))["mailAuto"].on is True and plan(T(None, None, 1, None))["trinketAuto"].on is True
          and plan(T(None, None, 0, None))["mailAuto"].on is False,
          "mail to another character, sharing every quest, trinket swaps: left on by For friends and Everything, off with Nothing")
    check(YR.WelcomeNow().acts != 0, "and with one of them on, what you have is not read as Nothing")
    YR.WelcomeApply(T(None, None, 0, None))
    check(db.mailAuto is None and db.shareAll is None and db.trinketAuto is None and YR.WelcomeNow().acts == 0,
          "Nothing applied: all three off")
    db.acceptInvites, db.whisperInvite = "anyone", "party"
    YR.WelcomeApply(T(None, None, 1, None))
    check(db.acceptInvites == "friends" and db.whisperInvite == "friends", "Friends only applied over Anyone: narrowed to friends")
    YR.WelcomeApply(mini)
    check(YR.Option("durability") and YR.Option("remindTalents"), "what is seen and harmless (the durability line, the talent reminder) isn't touched")

    # another addon does it: left off whatever the answer, and named
    lua.execute("C_AddOns.IsAddOnLoaded = function(n) return n == 'NaowhForever' end")
    YR.EllesmereForget()
    p = plan(full)
    check(p["xpbar"].other == "Naowh Forever" and not p["xpbar"].on and not p["lootFeed"].on and p["chatLog"].on,
          "another addon of yours does it: ours is left off whatever the answer")
    check("XP bar (Naowh Forever does it)" in YR.WelcomeLine("screen", YR.WelcomePlan(full)), "and the addon is named")
    YR.WelcomeApply(full)
    check(not YR.XPBarOn() and YR.Option("chatLog") and YR.WelcomeNow().screen == 2, "Apply leaves it off, and that still reads back as Everything")
    lua.execute("C_AddOns.IsAddOnLoaded = function() return false end")
    YR.EllesmereForget()
    YR.WelcomeApply(mini)

    # the window itself: a new install opens on Recommended, after that on what you have
    lua.execute("getmetatable(UIParent).HookScript = function(self, _, fn) self.hook = fn end")     # (kept, to press below)
    db.welcome, db.welcomeSeen = True, None
    check(YR.WelcomeShow() is True and g.HeadstartWelcomeWindow is not None and db.welcomeSeen is True, "the window opens, and is marked as seen")
    check(YR.WelcomeToggle() is False and YR.WelcomeToggle() is True, "/headstart start: closed when open, open when closed")
    check(all(len(q.choices) in (2, 3) and all(c[2] for c in q.choices.values()) for q in YR.WelcomeQuestions().values()),
          "every answer says on its card what it does")
    # everything on at once: the list still fits the window's eight lines, the two standing ones last
    YR.WelcomeApply(lua.eval("{ routes = 1, screen = 2, acts = 2, setup = 1 }"))
    db.mailAuto = True
    names = [c.name for c in YR.WelcomeChecks().values()]
    check(len(names) == 8 and names[0] == "Class trainer spends gold" and "Mail to alt sends without asking" in names
          and names[-2:] == ["Installing changed nothing of yours", "New on your screen"],
          f"everything on: eight lines, what can cost you first ({names})")
    YR.WelcomeShowChecks()
    check(True, "and the list is put up in the window without an error")

    # The first, unasked showing (Core.lua, YR.WelcomeFirst). A new install's very first login is a new
    # character's, and that plays its flight over the zone with the interface hidden: the window was put
    # up under it, closed by the Escape that ended the flight, and written down as seen (2026-10-13).
    lua.execute("""UI_UP, IN_MOVIE, LATER = false, true, {}
        UIParent.IsVisible = function() return UI_UP end
        function InCinematic() return IN_MOVIE end
        WIN = HeadstartWelcomeWindow
        WIN.IsVisible = function(self) return UI_UP and self:IsShown() end
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
    # a click in it is an answer
    for name, press in (("a quick pick", "WIN.quick.minimal.fn(WIN.quick.minimal)"), ("a card", "WIN.blocks[1].cards[1].fn(WIN.blocks[1].cards[1])"),
                        ("its Close button", "WIN.close.hook(WIN.close)")):
        g.First()
        g.Tick()
        shown = not win.hidden and db.welcomeSeen is None
        lua.execute(press)
        check(shown and db.welcomeSeen is True, f"{name} pressed: seen")
        check(g.Tick() == 0, "and nothing looks any more")
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
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
