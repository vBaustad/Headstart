"""Smoke test of the death recap and records (Recap.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_recap.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Off: nothing is listened for. On: the hits on you are noted without a word during the fight, a death
says what killed you with the biggest hit marked, the game's own names are used once readable, a
secret number is counted as hidden and never compared, and hits on anything but you are not kept.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r"""
FRAMES, AFTER, SAID = {}, {}, {}
local F = {}
F.__index = function(t, k)
    if F[k] then return F[k] end
    return function() end                 -- any widget method: nothing
end
function F:RegisterEvent(e) local ev = rawget(self, "ev") or {} rawset(self, "ev", ev) ev[e] = true end
function F:RegisterUnitEvent(e, ...) local ev = rawget(self, "ev") or {} rawset(self, "ev", ev) ev[e] = { ... } end
function F:UnregisterAllEvents() self.ev = {} end
function F:SetScript(what, fn) if what == "OnEvent" then self.fn = fn end end
function F:Show() self.shown = true end
function F:Hide() self.shown = false end
function F:SetShown(on) self.shown = on and true or false end
function F:IsShown() return rawget(self, "shown") == true end
function F:CreateFontString() return setmetatable({}, F) end
function F:CreateTexture() return setmetatable({}, F) end
function CreateFrame(_, name) local f = setmetatable({}, F) table.insert(FRAMES, f) if name then _G[name] = f end return f end
function Fire(e, ...) for _, f in ipairs(FRAMES) do local ev, fn = rawget(f, "ev"), rawget(f, "fn") if ev and ev[e] and fn then fn(f, e, ...) end end end
function Listening(e) for _, f in ipairs(FRAMES) do local ev = rawget(f, "ev") if ev and ev[e] then return true end end return false end
UIParent = setmetatable({}, F)
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
function print(...) SAID[#SAID + 1] = table.concat({ ... }, " ") end
NOW, COMBAT, GHOST, GROUP = 100, false, false, false
function GetTime() return NOW end
function time() return 1000 end
function date() return "12:00" end
function GetZoneText() return "Duskwood" end
function InCombatLockdown() return COMBAT end
function IsInGroup() return GROUP end
function UnitCanAttack() return true end
function UnitName() return "Defias Bandit" end
function UnitGUID() return "Player-1" end
function UnitIsGhost() return GHOST end
C_Timer = { After = function(_, fn) AFTER[#AFTER + 1] = fn end }
function RunAfter() local l = AFTER AFTER = {} for _, fn in ipairs(l) do fn() end end
SECRET = {}
function issecretvalue(v) return v == SECRET end
YippRouteDB, YippSetupCharDB = {}, {}
Enum = { DamageMeterType = { DamageTaken = 7 }, DamageMeterSessionType = { Current = 1 } }
C_Spell = { GetSpellName = function(id) return ({ [8676] = "Ambush", [53] = "Backstab" })[id] end }
STYLE = { FONT = "f", C = { gold = { 1, 0.8, 0.3, 1 }, muted = { 1, 1, 1, 1 }, sub = { 1, 1, 1, 1 }, lineHi = { 1, 1, 1, 1 } } }
local function W() return setmetatable({}, F) end
STYLE.Text, STYLE.Fill, STYLE.Border, STYLE.Button, STYLE.Rounded, STYLE.Icon, STYLE.IconButton = W, W, W, W, W, W, W
"""

METER = r"""
C_DamageMeter = { GetCombatSessionSourceFromType = function(session, kind, guid)
    ASKED = { session, kind, guid }
    return { combatSpells = {
        { spellID = 53, totalAmount = 95, creatureName = "", combatSpellDetails = { unitName = "Stabby" }, overkillAmount = 0, isDeadly = false },
        { spellID = 8676, totalAmount = 412, creatureName = "", combatSpellDetails = { unitName = "Stabby" }, overkillAmount = 30, isDeadly = true },
        { spellID = SECRET, totalAmount = 9, creatureName = "x", overkillAmount = 0, isDeadly = false } } }
end }
RunAfter()
"""

GAME_RECAP = r"""
C_DeathRecap = { GetRecapEvents = function() return {
    { amount = 300, timestamp = 10, spellName = "Ambush", sourceName = "Stabby", critical = true, school = 1 },
    { amount = 80, timestamp = 12, spellName = "Backstab", sourceName = "Stabby", school = 1 } } end }
YippSetupCharDB.lastDeath.recap = nil
Fire("PLAYER_REGEN_ENABLED")
"""


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    YR = lua.table()
    for f in ("Core.lua", "Recap.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    YR.Style = lua.eval("STYLE")
    YR.StartRecap()
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def said():
        return list(lua.eval("SAID").values())

    check(not YR.RecapOn() and not g.Listening("UNIT_COMBAT") and not g.Listening("PLAYER_DEAD"),
          "never turned on: off, and not one event listened for")
    g.YippRouteDB.deathRecap = True
    YR.RecapApply()
    check(g.Listening("UNIT_COMBAT") and g.Listening("PLAYER_DEAD"), "turned on: the hits and the death are listened for")

    # a fight: hits on you, a dodge, a heal, a big crit, a secret one, the killing blow
    lua.execute("""COMBAT = true Fire("PLAYER_REGEN_DISABLED")
        Fire("UNIT_COMBAT", "player", "WOUND", "", 40, 1) NOW = NOW + 1
        Fire("UNIT_COMBAT", "player", "DODGE", "", 0, 1) NOW = NOW + 1
        Fire("UNIT_COMBAT", "player", "HEAL", "", 60, 2) NOW = NOW + 1
        Fire("UNIT_COMBAT", "player", "WOUND", "CRITICAL", 412, 1) NOW = NOW + 1
        Fire("UNIT_COMBAT", "player", "WOUND", "", SECRET, 1)
        Fire("UNIT_COMBAT", "player", "WOUND", "", 55, 4) NOW = NOW + 0.5""")
    check(len(said()) == 0 and not (g.HeadstartDeathRecap and lua.eval("rawget(HeadstartDeathRecap, 'shown')")),
          "during the fight: nothing said, nothing shown")
    lua.execute("""COMBAT = false Fire("PLAYER_DEAD") Fire("PLAYER_REGEN_ENABLED")""")
    def shown():
        return lua.eval("rawget(HeadstartDeathRecap, 'shown')")

    check(g.HeadstartDeathRecap is not None and shown() is True, "dead: the panel is up")
    d = g.YippSetupCharDB.lastDeath
    view = YR.RecapView(d, 8)
    check(view.title == "Killed by a hit of 55 (Fire)", f"the last hit that landed is what killed you ({view.title})")
    texts = [line.text for line in view.lines.values()]
    check(len(texts) == 5 and "dodged" in texts[1] and "+60 healed" in texts[2], f"the hits, the dodge and the heal in order ({texts})")
    big = [line for line in view.lines.values() if line.big]
    check(len(big) == 1 and "412" in big[0].text and "CRIT" in big[0].text, "the biggest hit is the one in large letters, marked as a crit")
    check("1 hit the game kept hidden" in view.foot and "507 taken" in view.foot,
          f"a secret number is counted as hidden and left out of the sum ({view.foot})")
    check(len(YR.RecapView(d, 3).lines) == 3, "'Lines shown' cuts the list to the last ones")

    # the game's own numbers, once readable: the killing blow by name
    lua.execute(METER)
    view = YR.RecapView(g.YippSetupCharDB.lastDeath, 8)
    check(list(g.ASKED.values()) == [1, 7, "Player-1"], "the damage meter is asked for what you took this fight")
    check(view.title == "Killed by Ambush from Stabby", f"the killing blow by name, from the game ({view.title})")
    spells = list(view.spells.values())
    check(len(spells) == 2 and spells[0].startswith("Ambush (Stabby)"), f"what you took by spell, biggest first, the secret one left out ({spells})")
    lua.execute("""COMBAT = true ASKED = nil""")
    YR.RecapDebug()
    check(g.ASKED is None, "in a fight the damage meter isn't asked at all")
    lua.execute("COMBAT = false")

    # the game's own recap where the client fills it in: used in place of our list
    lua.execute(GAME_RECAP)
    view = YR.RecapView(g.YippSetupCharDB.lastDeath, 8)
    texts = [line.text for line in view.lines.values()]
    check(len(texts) == 2 and "Ambush" in texts[0] and "Stabby" in texts[0] and "CRIT" in texts[0],
          f"the game's recap gives attacker and spell on every line ({texts})")

    # alive again: the panel goes; as a ghost it stays
    lua.execute("""GHOST = true Fire("PLAYER_ALIVE")""")
    check(shown() is True, "released (a ghost): the panel stays")
    lua.execute("""GHOST = false Fire("PLAYER_UNGHOST")""")
    check(shown() is False, "alive again: the panel goes")
    check(YR.RecapShow() is True and shown() is True, "/headstart death shows the last one again")

    # the pieces of the panel: the killing blow, a bar per hit, the sources, and a made-up one to look at
    view = YR.RecapView(g.YippSetupCharDB.lastDeath, 8)
    check(view.hero.name == "Ambush" and view.hero.who == "Stabby" and view.hero.overkill == 30,
          "the killing blow has its name, who, and the overkill")
    lua.execute("YippSetupCharDB.lastDeath.recap = nil")
    view = YR.RecapView(g.YippSetupCharDB.lastDeath, 8)
    fracs = [round(line.frac, 2) for line in view.lines.values()]
    check(fracs == [0.1, 0, 0.15, 1.0, 0.13], f"each hit's bar is as long as the hit was hard, the hardest full ({fracs})")
    src = list(view.sources.values())
    check(len(src) == 2 and src[0].frac == 1 and src[0].amount == "412  81%" and src[1].deadly is False and src[0].deadly is True,
          "what you took by spell: its share, and the deadly one marked")
    check(YR.RecapShow() is True and shown() is True and g.YippSetupCharDB.lastDeath.zone == "Duskwood",
          "Your last death (the settings' button, /headstart death): the recap of the real last one")
    lua.execute("""Fire("UNIT_COMBAT", "target", "WOUND", "CRITICAL", 999, 1)""")
    check(g.YippRouteDB.records is None and g.YippSetupCharDB.records is None, "hits on anything but you are not kept at all")

    # off again: nothing listened for, the panel away
    g.YippRouteDB.deathRecap = False
    YR.RecapApply()
    check(not g.Listening("UNIT_COMBAT") and shown() is False, "off: nothing listened for, the panel gone")
    g.YippRouteDB.deathRecap, g.YippRouteDB.qolOff = True, True
    YR.RecapApply()
    check(not g.Listening("UNIT_COMBAT"), "quality of life off: nothing listened for")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
