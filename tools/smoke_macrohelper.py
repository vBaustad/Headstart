"""Smoke test of the macro helper (Headstart_Setup/MacroHelper.lua): a macro's text from what its
button should do, the ready-made ones a class has, and making it.

    python tools/smoke_macrohelper.py      (exit code 1 on any failure; tools/smoke.py runs it too)
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r"""
CLASS, COMBAT, MACROS, SAID = "WARRIOR", false, {}, {}
function UnitClass() return "x", CLASS end
function InCombatLockdown() return COMBAT end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 30 } }
function GetNumMacros() return 0, #MACROS end
function GetMacroInfo(i) local m = MACROS[i - 120] if m then return m[1], m[2], m[3] end end
function CreateMacro(name, icon, body, perChar) MACROS[#MACROS + 1] = { name, icon, body, perChar } return 120 + #MACROS end
function EditMacro(i, name, icon, body) local m = MACROS[i - 120] if m then m[1], m[3] = name, body end return i end
function DeleteMacro(i) table.remove(MACROS, i - 120) end
StaticPopupDialogs = {}
HeadstartNS = { Setup = {}, Style = {}, Print = function(s) SAID[#SAID + 1] = s end,
    PlannerSpells = {
        WARRIOR = { ["Charge"] = { 100, 1 }, ["Intercept"] = { 20252, 1 }, ["Heroic Strike"] = { 78, 1 }, ["Taunt"] = { 355, 1 } },
        ROGUE = { ["Stealth"] = { 1784, 1 }, ["Pick Pocket"] = { 921, 1 }, ["Sap"] = { 6770, 1 }, ["Kick"] = { 1766, 1 } },
        DRUID = { ["Cat Form"] = { 768, 1 }, ["Healing Touch"] = { 5185, 1 } },
        PRIEST = { ["Flash Heal"] = { 2061, 1 } },
    },
    PlannerGeneral = { PRIEST = { ["Shoot"] = { 5019, 1 } } } }
"""


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, "Headstart_Setup", "MacroHelper.lua"), encoding="utf-8").read(), "MacroHelper.lua")()
    g = lua.globals()
    YS = g.HeadstartNS.Setup
    T = lua.eval("function(s) return loadstring('return ' .. s)() end")
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def build(spell, opts, cls=None):
        return YS.MacroBuild(spell, T(opts), cls)

    check(build("Stealth", "{ keep = true }") == "#showtooltip Stealth\n/cast !Stealth", "pressing again doesn't turn it off: !Stealth")
    check(build("Flash Heal", "{ mouse = 'help' }") == "#showtooltip Flash Heal\n/cast [@mouseover,help,nodead][] Flash Heal",
          "a friend under the mouse first, else your target")
    check(build("Flash Heal", "{ mouse = 'help', self = true }").endswith("/cast [mod:alt,@player][@mouseover,help,nodead][] Flash Heal"),
          "and Alt for yourself, before the mouse")
    check(build("Polymorph", "{ mouse = 'harm' }").endswith("[@mouseover,harm,nodead][] Polymorph"), "an enemy under the mouse")
    check(build("Kick", "{ stop = true }") == "#showtooltip Kick\n/stopcasting\n/cast Kick", "stop what you're casting first")
    check(build("Heroic Strike", "{ attack = true }") == "#showtooltip Heroic Strike\n/startattack\n/cast Heroic Strike", "start attacking too")
    check(build("Healing Touch", "{ leave = true }") == "#showtooltip Healing Touch\n/cancelform\n/cast Healing Touch", "leave your form first")
    check(build("Charge", "{ stance = 1 }", "WARRIOR") == "#showtooltip Charge\n/cast [nostance:1] Battle Stance; Charge",
          "a warrior's stance first: the first press changes stance, the next casts")
    check(build("Intercept", "{ stance = 3 }", "WARRIOR").endswith("[nostance:3] Berserker Stance; Intercept"), "the stance by its number")
    check(build("Charge", "{ stance = 1 }", "ROGUE") == "#showtooltip Charge\n/cast Charge", "a class without stances: no stance line")
    check(build("Charge", "{}") == "#showtooltip Charge\n/cast Charge", "nothing ticked: the spell")
    check(YS.MacroName("Hammer of Justice") == "Justice" and YS.MacroName("Sinister Strike") == "Strike" and len(YS.MacroName("X" * 40)) == 16,
          "a name: the spell's last word, as short as a macro's name may be")

    check(build("Charge", "{ tip = false }") == "/cast Charge", "no tooltip line: only the cast")
    # a line at a time: a spell, when, on whom, and whether it stays on
    def line(spell, opts="{}"):
        return YS.MacroLine(spell, T(opts))
    check(line("Sap") == "/cast Sap" and line("Sap", "{ when = 'stealth' }") == "/cast [stealth] Sap"
          and line("Stealth", "{ when = 'nostealth', keep = true }") == "/cast [nostealth] !Stealth",
          "a line: the spell, a condition in front of it, ! to keep it on")
    check(line("Charge", "{ when = 'stance:1' }") == "/cast [stance:1] Charge", "a warrior's stance as the condition")
    check(line("Renew", "{ target = 'help' }") == "/cast [@mouseover,help,nodead][] Renew"
          and line("Renew", "{ target = 'help', when = 'mod:shift' }") == "/cast [mod:shift,@mouseover,help,nodead][mod:shift] Renew",
          "the friend under the mouse first, else your target - and the condition on both")
    check(line("Renew", "{ target = 'help', altself = true }") == "/cast [mod:alt,@player][@mouseover,help,nodead][] Renew"
          and line("Renew", "{ target = 'self' }") == "/cast [@player] Renew" and line("Mend Pet", "{ target = 'pet' }") == "/cast [@pet] Mend Pet",
          "Alt for yourself before the mouse; yourself; your pet")
    two = YS.MacroAddLine(YS.MacroAddLine("", line("Stealth", "{ when = 'nostealth' }")), line("Sap", "{ when = 'stealth' }"))
    check(two == "/cast [nostealth] Stealth\n/cast [stealth] Sap", "two lines: into Stealth, and pressed again, Sap")
    check(YS.MacroDropLine(two) == "/cast [nostealth] Stealth" and YS.MacroDropLine("/cast Sap") == "" and YS.MacroDropLine("") == "",
          "the last line taken off again")
    one = YS.MacroAddElse(YS.MacroAddLine("#showtooltip", line("Sap", "{ when = 'stealth' }")), line("Stealth"))
    check(one == "#showtooltip\n/cast [stealth] Sap; Stealth", "or else: on the last /cast line, after a semicolon")
    check(YS.MacroAddElse("", line("Stealth")) == "/cast Stealth" and YS.MacroAddElse("#showtooltip", line("Stealth")) == "#showtooltip\n/cast Stealth"
          and YS.MacroAddElse("/cast [combat] Vanish", line("Stealth", "{ when = 'nostealth', keep = true }")) == "/cast [combat] Vanish; [nostealth] !Stealth",
          "with no /cast line to hang on it is a line of its own; its own condition comes along")
    tip = YS.MacroSetLine(two, "tip", True)
    check(tip == "#showtooltip\n" + two and YS.MacroHasLine(tip, "tip") and not YS.MacroHasLine(two, "tip"),
          "the icon and tooltip line goes on top")
    both = YS.MacroSetLine(YS.MacroSetLine(tip, "leave", True), "stop", True)
    check(both == "#showtooltip\n/stopcasting\n/cancelform\n" + two, "stop casting and leave form: under it, in that order whichever came first")
    check(YS.MacroSetLine(both, "tip", False) == "/stopcasting\n/cancelform\n" + two and YS.MacroSetLine("#showtooltip Sap\n/cast Sap", "tip", False) == "/cast Sap",
          "and out again, a named one too")
    whens = lambda cls: [w[1] for w in YS.MacroWhens(cls).values()]
    check("stealth" in whens("ROGUE") and "stance:3" in whens("WARRIOR") and "nostance:1" in whens("WARRIOR") and "stealth" not in whens("MAGE")
          and "noform" in whens("DRUID") and "pet" in whens("HUNTER") and "mod:shift" in whens("MAGE") and whens("MAGE")[0] is False,
          "when a line casts: what the class has (stealth, stances, forms, a pet) and what every class has")
    # the ready-made ones: only what the class has on this client
    w = [r.label for r in YS.MacroRecipes("WARRIOR").values()]
    check("Charge, from any stance" in w and "Charge out of combat, Intercept in combat" in w and "Taunt, from any stance" in w
          and "Taunt, from any stance, mouseover first" in w and "Pummel, from any stance" not in w
          and "Your stance's long cooldown" not in w, f"a warrior's: the ones whose spells it has ({len(w)})")
    r = {x.label: x for x in YS.MacroRecipes("ROGUE").values()}
    check(r["Stealth that stays on"].body == "#showtooltip Stealth\n/cast !Stealth"
          and r["Pick Pocket, then Sap"].body == "#showtooltip Sap\n/cast Pick Pocket\n/cast Sap" and "Pick Pocket, then Ambush" not in r
          and r["Pick Pocket, then Sap"].name == "PP Sap",
          "a rogue's: Stealth that stays, Pick Pocket with the opener it has, under a name of its own")
    check([x.label for x in YS.MacroRecipes("PRIEST").values()] == ["Flash Heal, mouseover first", "Wand that stays on", "Use both trinkets"],
          "a priest's: the heal it has, the wand (a general spell), and the one every class has")
    check(len(list(YS.MacroRecipes("NOBODY").values())) == 0, "a class there isn't: none")
    for cls in ("ROGUE", "WARRIOR", "DRUID", "HUNTER", "MAGE", "PRIEST", "PALADIN", "SHAMAN", "WARLOCK"):
        for x in YS.MacroRecipes(cls).values():
            if len(x.body) > 255 or (x.name and len(x.name) > 16):
                check(False, f"{cls}: {x.label} is longer than a macro or its name holds")
    for cls in ("WARRIOR", "ROGUE", "DRUID", "PRIEST"):
        for x in YS.MacroRecipes(cls).values():
            if len(x.body) > 255 or not x.body.startswith("#showtooltip"):
                check(False, f"{cls}: {x.label} is too long or has no #showtooltip")

    # your own macros: listed, written over, deleted
    lua.execute('MACROS = { { "Mine", 134400, "/cast Sap", true }, { "Other", 132320, "/say hi", true } }')
    own = list(YS.MacroOwn().values())
    check([m.name for m in own] == ["Mine", "Other"] and own[0].index == 121 and own[0].body == "/cast Sap" and not own[0].account,
          "your macros: this character's, with where each is")
    check(YS.MacroSave(121, "Mine2", "/cast [stealth] Sap") == 121 and lua.eval("MACROS[1][1] .. '|' .. MACROS[1][3]") == "Mine2|/cast [stealth] Sap",
          "saved over: the new name and text")
    check(YS.MacroSave(121, "", "/cast Sap")[0] is None and YS.MacroSave(121, "X", "y" * 256)[0] is None and YS.MacroSave(140, "X", "/cast Sap")[0] is None,
          "not without a name, not longer than a macro holds, not one that isn't there")
    check(YS.MacroDelete(121, "Mine")[0] is None and len(list(YS.MacroOwn().values())) == 2,
          "delete: not when the macro there has another name (they move when one is deleted)")
    check(YS.MacroDelete(121, "Mine2") is True and [m.name for m in YS.MacroOwn().values()] == ["Other"], "deleted by its place and name")
    lua.execute("COMBAT = true")
    check(YS.MacroDelete(121, "Other")[0] is None and YS.MacroSave(121, "Other", "/say x")[0] is None, "in a fight: neither")
    lua.execute("COMBAT = false MACROS = {}")

    # remembered for the class, on the account: a new character of the class is offered them
    lua.execute('YippSetupDB = {} CLASS = "ROGUE" MACROS = { { "Stl Sap", 134400, "/cast [stealth] Sap; Stealth", true } }')
    YS.MacroRemember("Stl Sap", "/cast [stealth] Sap; Stealth")
    YS.MacroRemember("Vanish", "/cast Vanish")
    YS.MacroRemember("Vanish", "/cast [combat] Vanish")          # the same name again: its text, not a second one
    own = list(YS.MacroOwn().values())
    check([(m.name, bool(m.saved)) for m in own] == [("Stl Sap", False), ("Vanish", True)] and own[1].body == "/cast [combat] Vanish",
          "one this character has, and one remembered that it hasn't: offered, marked as not made here")
    lua.execute('MACROS = {}')                                    # another rogue, with no macros of its own
    check([(m.name, bool(m.saved)) for m in YS.MacroOwn().values()] == [("Stl Sap", True), ("Vanish", True)],
          "a new character of the class: both offered")
    lua.execute('CLASS = "MAGE"')
    check(len(list(YS.MacroOwn().values())) == 0, "another class: none of them")
    lua.execute('CLASS = "ROGUE"')
    YS.MacroForget("Vanish")
    check([m.name for m in YS.MacroOwn().values()] == ["Stl Sap"], "forgotten: not offered again")
    lua.execute('MACROS = { { "Stl Sap", 134400, "x", true } }')
    YS.MacroSave(121, "Opener", "/cast Sap")
    check([m.name for m in YS.MacroOwn().values()] == ["Opener"] and lua.eval('YippSetupDB.macroLib.ROGUE[1].name') == "Opener",
          "renamed when saved: remembered under the new name only")
    YS.MacroDelete(121, "Opener")
    check(len(list(YS.MacroOwn().values())) == 0, "deleted: forgotten too")
    # sharing: out as text, and in again on another account
    lua.execute('YippSetupDB = {} CLASS = "ROGUE" MACROS = {}')
    YS.MacroRemember("Stl Sap", "#showtooltip\n/cast [stealth] Sap; Stealth")
    YS.MacroRemember("Vanish", "/cast Vanish")
    text = YS.MacroExport()[0]
    check(text == "Headstart macros: ROGUE\n== Stl Sap\n#showtooltip\n/cast [stealth] Sap; Stealth\n== Vanish\n/cast Vanish",
          "export: what it is and for which class, then each macro under its name")
    lua.execute('YippSetupDB = {} CLASS = "MAGE"')
    got = YS.MacroImport("someone said:\n" + text + "\n\n")
    check(got[0] == 2 and got[1] == "ROGUE" and len(list(YS.MacroOwn().values())) == 0
          and lua.eval('YippSetupDB.macroLib.ROGUE[1].body') == "#showtooltip\n/cast [stealth] Sap; Stealth",
          "import: both taken in for the class it names, whatever class you are on - and nothing made")
    check(YS.MacroImport("hello")[0] is None and YS.MacroImport("Headstart macros: NOBODY\n== x\n/cast y")[0] is None
          and YS.MacroImport("Headstart macros: ROGUE\nnothing here")[0] is None,
          "not an export, not a class, nothing in it: refused, with the reason")
    check(YS.MacroImport("Headstart macros: ROGUE\n== Long\n" + "y" * 300 + "\n== Fine\n/cast Sap")[0] == 1,
          "a macro longer than a macro holds is left out, the rest come in")
    lua.execute('YippSetupDB = nil CLASS = "WARRIOR" MACROS = {}')

    # making it (one answer when made, two when not or when it was there already)
    make = lua.eval("function(n, b) local i, why = HeadstartNS.Setup.MacroMake(n, b) return { i = i, why = why } end")

    class Made:
        def __init__(self, n, b):
            r = make(n, b)
            self.i, self.why = r.i, r.why

    m = Made("Stealth", "#showtooltip Stealth\n/cast !Stealth")
    check(m.i == 121 and m.why is None and list(g.MACROS[1].values()) == ["Stealth", 134400, "#showtooltip Stealth\n/cast !Stealth", True],
          "Make macro: this character's, with the question mark the game turns into the spell's icon")
    m = Made("Again", "#showtooltip Stealth\n/cast !Stealth")
    check(m.i == 121 and "already" in m.why and len(g.MACROS) == 1, "the very same text again: that macro, not another")
    check(Made("", "/cast X").i is None and Made("Long", "/cast " + "x" * 300).i is None,
          "no name, or more than a macro holds: not made, and why")
    g.COMBAT = True
    check(Made("Fight", "/cast Y").i is None, "in a fight: not made")
    g.COMBAT = False
    lua.execute("for i = 2, 30 do MACROS[i] = { 'm' .. i, 1, '/say ' .. i } end")
    m = Made("Full", "/cast Z")
    check(m.i is None and "30" in m.why, f"all thirty used: not made, and said so ({m.why})")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
