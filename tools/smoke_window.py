"""Smoke test of the window as an addon of its own (Headstart_Options, load on demand): Headstart by
itself has no window in memory, the first thing that asks for it loads it, and with the window's addon
turned off or missing it says so once per ask and nothing errors.

    python tools/smoke_window.py      (exit code 1 on any failure)

Uses smoke.py's fake game (everything above the line where it loads the addon).
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
    lua.execute("C_Timer.After = function(_, fn) fn() end")
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    listed = [os.path.basename(f) for f in files(ROOT, "Headstart.toc")]
    check("Editor.lua" not in listed and "QuestIDs.lua" not in listed,
          "Headstart's own .toc loads neither the window nor the quest list")
    # a new install: character setup is off, and its addon is never asked for
    lua.execute("""LOADS = {} C_AddOns = C_AddOns or {}
        C_AddOns.LoadAddOn = function(name) LOADS[#LOADS + 1] = name return false, "MISSING" end
        YippRouteDB = nil""")
    g.Fire("ADDON_LOADED", "Headstart")
    check(not YR.SetupOn() and len(g.LOADS) == 0 and YR.Setup is None,
          "a new install: Character setup is off and nothing of it is loaded")
    check(g.YippSetupCharDB is not None and g.YippSetupDB is not None, "the saved tables are there without it (other parts use them)")
    g.SlashCmdList.HEADSTART("plan")
    check(len(g.LOADS) == 0, "/headstart plan with it off: says so, loads nothing")
    # an account that had Headstart before keeps it on (latched once)
    g.YippRouteDB = lua.table(quiet=1)
    YR.Latch(False)
    check(YR.SetupOn() and g.YippRouteDB.quiet == 5, "an account that had Headstart: Character setup stays on")
    g.YippRouteDB.setupOn = False
    YR.Latch(False)
    check(not YR.SetupOn(), "turned off after that: it stays off")
    # turned on: its addon is read in at once, started, and its tables trimmed to this class
    g.SETUP = lua.table(*[open(f, encoding="utf-8").read() for f in files(os.path.join(ROOT, "Headstart_Setup"), "Headstart_Setup.toc")])
    lua.execute("""C_AddOns.LoadAddOn = function(name)
            LOADS[#LOADS + 1] = name
            if name ~= "Headstart_Setup" then return false, "MISSING" end
            for _, code in ipairs(SETUP) do assert(loadstring(code, "Headstart_Setup"))("Headstart_Setup", {}) end
            return true
        end""")
    YR.SetSetupOn(True)
    check(list(g.LOADS.values()) == ["Headstart_Setup"] and YR.SetupLoaded() and YR.OpenPlanner is not None,
          "turned on: its addon is loaded there and then, no reload")
    classes = [k for k in YR.PlannerSpells.keys()]
    check(len(classes) == 1, f"its spell tables are trimmed to this character's class ({classes})")
    YR.SetSetupOn(True)
    YR.LoadSetup()
    check(len(g.LOADS) == 1, "and loaded once")
    lua.execute("C_AddOns.LoadAddOn = nil")
    check(YR.windowLoaded is None and YR.QUEST_IDS is None and g.HeadstartWindow is None,
          "after login: no window and no quest list in memory")
    YR.RefreshWindow(YR)
    check(g.HeadstartWindow is None, "asking the window to draw again loads nothing")

    # the window's addon turned off: said in chat, no error, and it isn't asked for in a loop
    lua.execute("""SAID, ASKS = {}, 0
        local was = print
        print = function(...) SAID[#SAID + 1] = table.concat({ ... }, " ") end
        C_AddOns = C_AddOns or {}
        C_AddOns.LoadAddOn = function(name) ASKS = ASKS + 1 return false, "DISABLED" end""")
    YR.ToggleWindow(YR)
    g.SlashCmdList.HEADSTARTSETTINGS()
    said = " ".join(lua.eval("SAID").values())
    check(g.ASKS == 2 and "turned off" in said and g.HeadstartWindow is None,
          f"the window's addon turned off: asked for once each time, and said so ({g.ASKS})")
    g.SlashCmdList.HEADSTART("scan")
    check(g.ASKS == 3 and YR.QUEST_IDS is None, "/headstart scan without it: asked for, nothing scanned, no error")

    # there: loaded by the first ask, then never asked for again
    g.OPTIONS = lua.table(*[open(f, encoding="utf-8").read() for f in files(os.path.join(ROOT, "Headstart_Options"),
                                                                             "Headstart_Options.toc")])
    lua.execute("""ASKS = 0
        C_AddOns.LoadAddOn = function(name)
            ASKS = ASKS + 1
            if name ~= "Headstart_Options" then return false, "MISSING" end
            -- an addon of its own: a name and a table of its own, not Headstart's
            for _, code in ipairs(OPTIONS) do assert(loadstring(code, "Headstart_Options"))("Headstart_Options", {}) end
            return true
        end""")
    g.SlashCmdList.HEADSTARTSETTINGS()
    check(g.ASKS == 1 and YR.windowLoaded is True and g.HeadstartWindow is not None and g.HeadstartWindow.hidden is False,
          "/hs loads the window's addon and opens the window")
    check(YR.QUEST_IDS is not None, "the quest list came with it")
    for page in ("routes", "where", "run", "share", "route", "settings", "instances", "trainer"):
        YR.ToggleWindow(YR, page)
    check(YR.WindowTab() == "qol", "QoL's pages are on the QoL tab")
    YR.ShowSettingsTab(YR, "character")
    check(YR.WindowTab() == "setup", "Character setup is a tab of its own (its old page name still leads there)")
    g.YippRouteDB.setupOn = False
    YR.ToggleWindow(YR, "setup")
    check(YR.WindowTab() == "setup", "off: the tab still opens (on its switch)")
    g.YippRouteDB.setupOn = True
    g.YippRouteDB.routes = False
    YR.ToggleWindow(YR, "run")
    check(YR.WindowTab() == "levelling", "Levelling with the routes off: the tab opens on its switch, no error")
    g.Headstart_OnAddonCompartmentClick()
    check(g.ASKS == 1, "every later ask goes straight to the window: its addon is loaded once")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
