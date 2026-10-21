"""Smoke test of moving your settings (Headstart_Options/Transfer.lua) in Lua 5.1 (lupa).

    python tools/smoke_transfer.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Settings written as a text and read back are the settings: every kind of value, the awkward letters
(| : % tab, line breaks, a space at a line's end), numbers that are not whole, keys that are numbers.
What must stay behind stays behind. A text cut short, a text that is something else and a text with a
line of code in it are told from a settings text, and no line is ever run. An import replaces what the
text holds and nothing else; macros that run code are left out unless asked for; Undo puts back what
was there.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r'''
RAN = 0
function time() return 1791849098 end
function date(f) return f == "%Y-%m-%d" and "2026-10-13" or "2026-10-13 12:00" end
function InCombatLockdown() return false end
YR = { CharKey = function() return "Flody-Stagheart" end, Print = function() end, Style = {} }
HeadstartNS = YR
NL = string.char(10)
YippRouteDB = {
    autoTrain = true, restock = false, quiet = 3, welcome = true, welcomeSeen = true, rxpTrainerWasOn = true,
    whisperSound = "bell|loud: one%two" .. string.char(9) .. "tab", trailing = "ends in spaces   ",
    campPos = { 1562.666870117188, 917.5001220703125 },
    trainer = { PALADIN = { reserve = 500000, v = 2, spells = { ["Holy Light"] = "always", ["Seal: of #1"] = "never" } } },
    runs = { ["Flody-Stagheart"] = { ev = { 1, 2, 3 } } }, place = { ["Flody-Stagheart"] = { n = 4 } }, instanceRuns = { 1 }, scan = { 1 },
    myRoutes = { ["My route"] = { text = "step" .. NL .. ".goto Teldrassil,55.5,60.1" .. NL .. "/run this is a route line, not a macro" } },
    emptyTable = {},
    ["#odd"] = 1, [7] = "seven", [2.5] = "two and a half",
}
YippSetupDB = {
    uiPrev = { big = "old copy nobody reads" },
    options = { swap = true },
    macroLib = { PALADIN = { { name = "Heal", body = "#showtooltip Holy Light" .. NL .. "/cast [@mouseover,help][] Holy Light" } } },
    classes = { PALADIN = { profile = { from = "Flody-Stagheart", slots = {
        [1] = { kind = "spell", name = "Holy Light", level = 1 },
        [2] = { kind = "macro", name = "Heal", icon = 134400, body = "#showtooltip Holy Light" .. NL .. "/cast Holy Light" },
        [3] = { kind = "macro", name = "Evil", icon = 134400, body = "/cast Holy Light" .. NL .. "/run RAN = RAN + 1" },
        [61] = { kind = "item", id = 6948 },
    } }, layouts = { Tank = { slots = { [1] = { kind = "spell", name = "Stoneform" } } } } } },
}
function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
function Copy(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and Copy(v) or v end return c end
'''


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok   " if ok else "FAIL ") + what)
        if not ok:
            bad += 1

    load = lua.eval("function(src, name) local f = assert(loadstring(src, name)) f('Headstart_Options', {}) end")
    load(open(os.path.join(ROOT, "Headstart_Options", "Transfer.lua"), encoding="utf-8").read(), "Transfer.lua")
    YR = g.YR
    both = lua.eval("function(t) local d, why = YR.TransferRead(t) return { d = d, why = why } end")

    def read(t):          # (one value when it reads, two when it doesn't: always a pair here)
        r = both(t)
        return r.d, r.why

    text = YR.TransferExport()
    lines = text.split("\n")
    check(lines[0] == "HEADSTART-SETTINGS 1" and lines[-1] == f"END:{len(lines)}" and lines[1] == "F:Flody-Stagheart:2026-10-13",
          f"exported: what it is, who wrote it and when, and a last line that counts the lines ({len(lines)})")
    check("|" not in text and "\t" not in text and not any(l.endswith(" ") for l in lines),
          "no | in it, no tab, no line that ends in a space: nothing a chat or a text box changes on the way")
    check(text == YR.TransferExport(), "the same settings give the same text")
    for gone in ("runs", "place", "instanceRuns", "scan", "welcome", "quiet", "rxpTrainerWasOn", "uiPrev", "old copy"):
        check(not any(l.startswith(("T:" + gone, "S:" + gone, "B:" + gone, "N:" + gone)) for l in lines) and "old copy" not in text,
              f"left behind: {gone}")
    data, why = read(text)
    lua.execute("""WANT_DB = Copy(YippRouteDB) for _, k in ipairs({ 'runs', 'place', 'instanceRuns', 'scan', 'welcome', 'welcomeSeen', 'quiet', 'rxpTrainerWasOn' }) do WANT_DB[k] = nil end
        WANT_SETUP = Copy(YippSetupDB) WANT_SETUP.uiPrev = nil""")
    check(data is not None and lua.eval("Same")(data.db, g.WANT_DB) and lua.eval("Same")(data.setup, g.WANT_SETUP),
          f"read back: the very settings that were written - every letter, number and name ({why})")
    check(data.db.campPos[1] == 1562.666870117188 and data.db[2.5] == "two and a half" and data.db[7] == "seven" and data.db["#odd"] == 1
          and data.db.whisperSound == "bell|loud: one%two\ttab" and data.db.trailing == "ends in spaces   " and data.db.emptyTable is not None,
          "numbers that are not whole, names that are numbers, and | : % tab and a space at the end, all as they were")
    check(data.settings >= 8 and data.profiles == 2 and data.macros == 3 and data.code == 1 and data.routes == 1 and data.__getitem__("from") == "Flody-Stagheart",
          f"and what is in it, counted: {data.settings} settings, {data.profiles} profiles, {data.macros} macros ({data.code} that runs code), {data.routes} route")
    check(g.RAN == 0, "reading runs nothing")

    # what is not a settings text is told from one
    for what, broken in (("cut short", "\n".join(lines[:len(lines) // 2])), ("its last line gone", "\n".join(lines[:-1])),
                         ("something else", "hello there"), ("empty", "   \n  "),
                         ("a line of code in it", "\n".join(lines[:5] + ["RAN = 99"] + lines[5:-1] + [f"END:{len(lines) + 1}"])),
                         ("closed once too often", "\n".join(lines[:2] + ["E"] + lines[2:-1] + [f"END:{len(lines) + 1}"]))):
        d, why = read(broken)
        check(d is None and isinstance(why, str) and g.RAN == 0, f"{what}: not read, and said why ({why[:48]})")
    # and what the copying does to a whole one does not break it: other line ends, blank lines, spaces before a line
    mangled = "\r\n\r\n".join("  " + l for l in lines) + "\r\n"
    d, why = read(mangled)
    check(d is not None and lua.eval("Same")(d.db, g.WANT_DB), f"Windows line ends, blank lines between and spaces in front: still read whole ({why})")

    # an import: what the text holds replaces what is here; the rest stays; code macros left out
    lua.execute("""THEIRS = { db = { autoTrain = false, newThing = "new", trainer = { MAGE = { reserve = 7 } }, runs = { evil = true }, quiet = 0 },
        setup = { classes = { MAGE = { profile = { slots = { [1] = { kind = "macro", name = "Bad", body = "/script RAN = RAN + 1" },
            [2] = { kind = "macro", name = "Fine", body = "/cast Frostbolt" } } } } }, macroLib = { MAGE = { "/run RAN = 5", "/cast Fireball" } } } }
        BEFORE_DB, BEFORE_SETUP = Copy(YippRouteDB), Copy(YippSetupDB)""")
    n, left, stayed = YR.TransferImport(g.THEIRS)
    db, setup = g.YippRouteDB, g.YippSetupDB
    check(db.newThing == "new" and db.restock is False and db.campPos is not None and db.runs["Flody-Stagheart"] is not None
          and db.runs.evil is None and db.quiet == 3,
          "imported: each thing the text holds is in place, what it doesn't hold is as it was, and it can't touch the run logs or where this install is at")
    check(db.autoTrain is True and db.trainer.MAGE is None and db.trainer.PALADIN is not None and stayed == 2,
          f"but what acts for you is not a stranger's to set: the class trainer and its choices stay as they are here ({stayed} left)")
    slots = setup.classes.MAGE.profile.slots
    check(left == 2 and slots[1] is None and slots[2] is not None and slots[2].body == "/cast Frostbolt"
          and setup.macroLib.MAGE[1] == "/cast Fireball" and setup.macroLib.MAGE[2] is None and setup.uiPrev is not None and g.RAN == 0,
          f"macros that run code are left out ({left}), the others come in - a list closed up behind the one taken out - and nothing ran")
    check(YR.TransferKept() == 1791849098 and YR.TransferUndo() is True and lua.eval("Same")(g.YippRouteDB, g.BEFORE_DB)
          and lua.eval("Same")(g.YippSetupDB, g.BEFORE_SETUP) and YR.TransferKept() is None and YR.TransferUndo() is False,
          "Undo: everything it replaced is as it was, what it added is gone, and there is nothing left to take back")
    lua.execute("""THEIRS = { db = { autoTrain = false, newThing = "new", trainer = { MAGE = { reserve = 7 } } },
        setup = { classes = { MAGE = { profile = { slots = { [1] = { kind = "macro", name = "Bad", body = "/script RAN = RAN + 1" } } } } } } }""")
    n, left, stayed = YR.TransferImport(g.THEIRS, True)
    db = g.YippRouteDB
    check(left == 0 and stayed == 0 and g.YippSetupDB.classes.MAGE.profile.slots[1] is not None and db.autoTrain is False
          and db.trainer.MAGE.reserve == 7 and db.trainer.PALADIN is None and g.RAN == 0,
          "All of it, for a text of your own: the code macros and what acts for you come in too (as text: still nothing is run)")
    YR.TransferUndo()

    # A text from a stranger: it would have your mailbox send your mats to its writer's character
    lua.execute("""THEFT = { db = { mailAuto = true, mailTo = { ["Realm-Alliance"] = "Their Alt" }, mailMats = "all", mailCustom = { [2589] = true },
        restock = true, restockReserve = 0, acceptInvites = "anyone", lootFeed = true, rewardClasses = { PALADIN = { on = true } },
        kept = { invites = { "anyone", "anyone" } }, cardOn = { invites = true } }, setup = {} }
        BEFORE_DB = Copy(YippRouteDB)""")
    lua.execute("local d = YR.TransferRead(YR.TransferExport()) SUMMED = d")
    theirs_text = lua.eval("""(function()
        local keep = YippRouteDB
        YippRouteDB = THEFT.db
        local text = YR.TransferExport()
        YippRouteDB = keep
        return text
    end)()""")
    d, why = read(theirs_text)
    said = ", ".join(d.acts.values()) if d else ""
    check(d is not None and "mail to Their Alt" in said and "restock" in said and "accepting invites" in said and "quest rewards picked" in said,
          f"read: what it would switch on is said, with who the mail would go to ({said})")
    n, left, stayed = YR.TransferImport(d)
    db = g.YippRouteDB
    check(db.mailAuto is None and db.mailTo is None and db.mailCustom is None and db.restock is False and db.acceptInvites is None
          and db.rewardClasses is None and db.lootFeed is True and stayed >= 7 and db.kept is None and db.cardOn is None,
          f"imported the plain way: none of it is switched on, nobody is named for your mail, and the rest comes in ({stayed} left as they were)")
    YR.TransferUndo()

    # A text that is not shaped as settings: where the addon reads a table it gets a table or nothing
    lua.execute("""ODD = { db = { custom = "x", myRoutes = { Fine = { text = "step" }, Broken = "not a route" }, swing = true, campPos = "nowhere",
        whisperSound = { "a table where a word was" }, lootFeed = true }, setup = {} }""")
    n, left, stayed = YR.TransferImport(g.ODD, True)
    db = g.YippRouteDB
    check(db.custom is None and db.swing is None and db.myRoutes.Fine is not None and db.myRoutes.Broken is None
          and db.campPos[1] == 1562.666870117188 and db.whisperSound == "bell|loud: one%two\ttab" and db.lootFeed is True,
          "the wrong shape under a name is not taken: no word where a table is read, no table where a word was, a route that is no route dropped")
    YR.TransferUndo()
    head = ["HEADSTART-SETTINGS 1", "F:x:2026-10-13", "T:db", "S:#nan:x", "E", "T:setup", "E", "END:8"]
    d, why = read("\n".join(head))
    check(d is None and isinstance(why, str), f"a name that is no number at all: not read, and no error ({why})")
    # a route's lines are not macros: a route that has "/run" in its words stays whole
    d, _ = read(text)
    YR.TransferImport(d)
    check("/run this is a route line" in g.YippRouteDB.myRoutes["My route"].text and g.YippSetupDB.classes.PALADIN.profile.slots[3] is None,
          "your own text move: the routes whole, and the one macro that runs code left out (the other button takes it)")
    YR.TransferUndo()
    # The game's own saved file, pasted whole: what is left of an install that can't be logged into
    # any more (the beta, closed a week before the live game opens).
    saved = r'''
YippRouteDB = {
["autoTrain"] = true,
["restock"] = false,
["whisperSound"] = "bell|loud \"quoted\" back\\slash\nsecond line",
["campPos"] = {
1562.666870117188, -- [1]
-917.5, -- [2]
},
["trainer"] = {
["PALADIN"] = {
["reserve"] = 5e+05,
["spells"] = {
["Holy Light"] = "always",
},
},
},
["runs"] = {
["Flody-Stagheart"] = {
["ev"] = {
1,
2,
},
},
},
[7] = "seven",
["quiet"] = 3,
}
YippSetupDB = {
["uiPrev"] = {
},
["classes"] = {
["PALADIN"] = {
["profile"] = {
["slots"] = {
{
["kind"] = "spell",
["name"] = "Holy Light",
}, -- [1]
{
["kind"] = "macro",
["name"] = "Evil",
["body"] = "/cast Holy Light\n/run RAN = RAN + 1",
}, -- [2]
},
},
},
},
}
HeadstartAlts = {
["Flody-Stagheart"] = {
["gold"] = 459,
},
}
'''
    d, why = read(saved)
    check(d is not None and d.db.autoTrain is True and d.db.restock is False and d.db.campPos[1] == 1562.666870117188 and d.db.campPos[2] == -917.5
          and d.db.trainer.PALADIN.reserve == 500000 and d.db[7] == "seven" and d.db.whisperSound == 'bell|loud "quoted" back\\slash\nsecond line',
          f"the saved file read as it stands: texts with their quotes, backslashes and line breaks, numbers, lists with the game's notes beside them ({why})")
    check(d.db.runs is None and d.db.quiet is None and d.setup.uiPrev is None and d.setup.classes.PALADIN.profile.slots[2].name == "Evil"
          and d.profiles == 1 and d.macros == 1 and d.code == 1 and d.__getitem__("from") == "a saved file" and g.RAN == 0,
          "what stays behind stays behind in a saved file too, its macros are counted, and nothing ran")
    n, left, stayed = YR.TransferImport(d)
    check(left == 1 and g.YippRouteDB.trainer.PALADIN.reserve == 500000 and g.YippSetupDB.classes.PALADIN.profile.slots[2] is None and g.RAN == 0,
          "and imported like any other: in place, the macro that runs code left out")
    YR.TransferUndo()
    for what, broken in (("cut short", saved[:len(saved) // 2]),
                         ("a call in it", saved.replace('["autoTrain"] = true,', '["autoTrain"] = (function() RAN = 7 end)(),')),
                         ("a word that is no value", saved.replace("= 3,", "= RAN,")),
                         ("a statement after it", saved + "\nos.exit()\n"),
                         ("a statement before it", "print(1)\n" + saved),
                         ("a text never closed", saved.replace('"seven"', '"seven'))):
        d, why = read(broken)
        check(d is None and isinstance(why, str) and g.RAN == 0, f"a saved file with {what}: not read at all, nothing run ({why[:60]})")
    # a line that sets some other name is another saved value to the reader, not something to do: it sets nothing here
    d, why = read("RAN = 8\n" + saved)
    check(d is not None and g.RAN == 0 and d.db.autoTrain is True, "a file that also names something else: read, and that name is not set in the game")
    d, why = read("SomethingElseDB = {\n}\n")
    check(d is None and "not a Headstart settings text" in why, "another addon's saved file: told it is not Headstart's")
    # without the routes: the short text
    short = YR.TransferExport(False)
    d, _ = read(short)
    check(d is not None and d.routes == 0 and d.db.myRoutes is None and len(short) < len(text), "exported without your routes: the rest, and shorter")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
