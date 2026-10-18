"""Smoke test of NPC markers (NpcMarkers.lua), in Lua 5.1 (lupa).

    python tools/smoke_npcmarkers.py      (exit code 1 on any failure; tools/smoke.py runs it too)

An icon on the nameplate of the NPC the active RestedXP step's .target names ("!" to take a quest, "?" to hand one
in, a speech bubble else), a sword on quest mobs, never on a player or a unit the game keeps secret; the game's
friendly NPC plates on while it is on and put back after. Uses smoke.py's fake game.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TALK, OFFER, HANDIN, MOB = 132053, 132049, 132048, 131013


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

    lua.execute("""
        local F = getmetatable(CreateFrame("Frame"))
        F.SetPoint = function(self, a, rel, b, x, y) rawset(self, "pt", { a, rel, b, x, y }) end
        F.SetTexture = function(self, t) rawset(self, "texture", t) end
        LATER = {}
        C_Timer.After = function(_, fn) LATER[#LATER + 1] = fn end
        function Later() local l = LATER LATER = {} for _, fn in ipairs(l) do fn() end end
        FIGHT = false
        function InCombatLockdown() return FIGHT end
        -- the game's settings
        CV = { nameplateShowFriendlyNpcs = "0" } CV_WRITES = 0
        C_CVar = { GetCVar = function(k) return CV[k] end,
                   SetCVar = function(k, v) CV[k] = tostring(v) CV_WRITES = CV_WRITES + 1 Fire("CVAR_UPDATE", k, tostring(v)) end }
        -- units and their plates: a plate is Blizzard's (UnitFrame with a health bar) unless said
        -- a secret value: anything but asking whether it is one fails, as in the game
        SECRET = newproxy(true)
        do local m = getmetatable(SECRET) for _, k in ipairs({ "__index", "__eq", "__lt", "__le", "__concat", "__len", "__call" }) do
            m[k] = function() error("attempt to use a secret value") end end end
        function issecretvalue(v) return v == SECRET end
        U = {}
        PLATES = {}
        function Plate(unit, u, kind)
            U[unit] = u
            local p = CreateFrame("Frame")
            local uf = CreateFrame("Frame")
            uf.healthBar = CreateFrame("Frame")
            uf.name = CreateFrame("Frame")
            uf:Show() uf.healthBar:Show() uf.name:Show()           -- (the fake's frames start hidden)
            if kind == "nobar" then uf.healthBar:Hide() end
            if kind == "plater" then uf:Hide() p.unitFrame = CreateFrame("Frame") p.unitFrame.healthBar = CreateFrame("Frame")
                p.unitFrame:Show() p.unitFrame.healthBar:Show() end
            p.UnitFrame = uf
            p.namePlateUnitToken = unit
            PLATES[unit] = p
            return p
        end
        C_NamePlate = { GetNamePlateForUnit = function(unit) return PLATES[unit] end,
            GetNamePlates = function() local t = {} for _, p in pairs(PLATES) do t[#t + 1] = p end return t end }
        function UnitName(unit) return U[unit] and U[unit].name end
        function UnitGUID(unit) return U[unit] and U[unit].guid end
        function UnitIsPlayer(unit) if U[unit] and U[unit].player == SECRET then return SECRET end return U[unit] ~= nil and U[unit].player == true end
        function UnitCanAttack(_, unit) return U[unit] ~= nil and U[unit].enemy == true end
        function UnitIsDead(unit) return U[unit] ~= nil and U[unit].dead == true end
        C_TooltipInfo = { GetUnit = function(unit)
            local o = U[unit] and U[unit].objective
            if o == nil then return { lines = { { type = 0 } } } end
            return { lines = { { type = 17 }, { type = 8, completed = o == "done" } } }
        end }
        -- RestedXP: the step you're on (its lines are its elements)
        STEP = { elements = { { tag = "text" }, { targets = { "Talin Keeneye" }, textOnly = true } } }
        RXP = { RXPFrame = { activeSteps = { STEP } }, GetCreatureName = function(n) return n end,
                SetStep = function() end, UpdateStepCompletion = function() end }
        Plate("nameplate1", { name = "Talin Keeneye", guid = "Creature-0-1-2-3-714-0000" })
        Plate("nameplate2", { name = "Talin Keeneye", player = true })                 -- a player of that name
        Plate("nameplate3", { name = "Small Crag Boar", enemy = true })
        Plate("nameplate4", { name = "Rockjaw Trogg", enemy = true, objective = "todo" })
        Plate("nameplate5", { name = "Burly Rockjaw Trogg", enemy = true, objective = "done" })
        Plate("nameplate6", { name = SECRET, guid = SECRET, player = SECRET })
        Plate("nameplate9", { name = SECRET, guid = SECRET, enemy = true })            -- an NPC whose name and GUID are kept
        YippRouteDB = nil YippSetupCharDB = nil""")
    g.Fire("ADDON_LOADED", "Headstart")
    g.Fire("PLAYER_LOGIN")
    g.Later()
    db = g.YippRouteDB

    # the icon put on a plate: the one frame of ours made on it (parent ignored by the fake: found by its tex)
    lua.execute("""
        KEPT_CREATE = CreateFrame
        ON_PLATE = {}
        CreateFrame = function(kind, name, parent, ...)
            local f = KEPT_CREATE(kind, name, parent, ...)
            if parent then ON_PLATE[parent] = f end
            return f
        end
        function NPCM_ICON(p)
            local f = ON_PLATE[p]
            if not f or rawget(f, "hidden") then return nil end
            return rawget(f.tex, "texture")
        end
        function NPCM_PT(p) local f = ON_PLATE[p] return f and rawget(f, "pt") end""")

    same = lua.eval("function(a, b) return rawequal(a, b) end")

    def at(unit):
        return g.NPCM_ICON(g.PLATES[unit])

    check("npcMarkers" in YR.STARTS_OFF and g.CV.nameplateShowFriendlyNpcs == "0" and at("nameplate1") is None,
          "off on a new install: no icons, the game's friendly plates left as they are")
    # a real hook (the fake one only writes it down): RestedXP's step functions call ours after their own
    lua.execute("""function hooksecurefunc(t, k, fn) local was = t[k] t[k] = function(...) local r = was(...) fn(...) return r end end""")
    db.npcMarkers = True
    YR.ApplyParts()
    check(g.CV.nameplateShowFriendlyNpcs == "1" and db.npcMarkersWas == "0",
          "on: friendly NPC plates on, and what they were written down")
    check(at("nameplate1") == TALK, f"the step's .target NPC gets the speech bubble ({at('nameplate1')})")
    pt = g.NPCM_PT(g.PLATES.nameplate1)
    check(pt is not None and pt[1] == "RIGHT" and same(pt[2], g.PLATES.nameplate1.UnitFrame.healthBar),
          "beside the plate's health bar")
    check(at("nameplate2") is None, "a player of the same name: nothing")
    check(at("nameplate6") is None, "a unit the game keeps secret: nothing, and no error")
    check(at("nameplate9") is None, "an NPC whose name and GUID the game keeps secret: nothing, and no error")
    check(at("nameplate3") is None, "an enemy that counts for nothing: nothing")
    check(at("nameplate4") == MOB, "an enemy with a quest objective of yours not done: the sword")
    check(at("nameplate5") is None, "an enemy whose objective is done: nothing")

    # the step takes a quest, then hands one in: "!" then "?" (RestedXP moving on calls its SetStep)
    lua.execute("""table.insert(STEP.elements, { tag = "accept", questId = 1 }) RXP.SetStep(3)""")
    check(at("nameplate1") == TALK, "a step change is looked at a moment after, not at once")
    g.Later()
    check(at("nameplate1") == OFFER, f"a quest to take at the NPC: ! ({at('nameplate1')})")
    lua.execute("""table.insert(STEP.elements, { tag = "turnin", questId = 2 }) RXP.UpdateStepCompletion() Later()""")
    check(at("nameplate1") == HANDIN, "and one to hand in as well: ? first")
    lua.execute("""STEP.elements[4].completed = true STEP.elements[3].completed = true RXP.UpdateStepCompletion() Later()""")
    check(at("nameplate1") == TALK, "both done: the speech bubble again")

    # the guide's name with its id, and RestedXP holding only the id (a client in another language): by the id
    lua.execute("""STEP.elements[2].targets = { "714" } RXP.SetStep(3) Later()""")
    check(at("nameplate1") == TALK, "only the NPC's id in the guide: matched by the id in its GUID")
    lua.execute("""STEP.elements[2].targets = { "Someone Else::714" } RXP.SetStep(3) Later()""")
    check(at("nameplate1") == TALK, '"Name::id": matched by the id')
    # a step with a .mob line: that mob gets the sword
    lua.execute("""table.insert(STEP.elements, { mobs = { "Small Crag Boar" }, textOnly = true }) RXP.SetStep(3) Later()""")
    check(at("nameplate3") == MOB, "the step's .mob: the sword")
    db.npcMarkersMobs = False
    YR.ApplyParts()
    check(at("nameplate3") is None and at("nameplate4") is None and at("nameplate1") == TALK,
          "Quest mobs off: no swords, the NPC still marked")
    db.npcMarkersMobs = None
    # the step moves on: the NPC is no longer the one
    lua.execute("""RXP.RXPFrame.activeSteps = {} RXP.SetStep(4) Later()""")
    check(at("nameplate1") is None, "the step over: its NPC's icon goes")
    lua.execute("""RXP.RXPFrame.activeSteps = { STEP } RXP.SetStep(3) Later()""")

    # plates that come and go; another addon's plate; one with no health bar
    g.Plate("nameplate7", lua.eval('{ name = "Talin Keeneye", guid = "Creature-0-1-2-3-714-0001" }'), "plater")
    g.Fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
    pt = g.NPCM_PT(g.PLATES.nameplate7)
    check(at("nameplate7") == TALK and same(pt[2], g.PLATES.nameplate7.unitFrame.healthBar),
          "a plate another addon draws (Plater, ElvUI): beside its own health bar")
    g.Plate("nameplate8", lua.eval('{ name = "Talin Keeneye", guid = "Creature-0-1-2-3-714-0001" }'), "nobar")
    g.Fire("NAME_PLATE_UNIT_ADDED", "nameplate8")
    pt = g.NPCM_PT(g.PLATES.nameplate8)
    check(pt is not None and pt[1] == "BOTTOM" and same(pt[2], g.PLATES.nameplate8.UnitFrame.name),
          "a plate with no health bar shown: over the name")
    g.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate8")
    check(at("nameplate8") is None, "a plate gone: its icon hidden")

    # the friendly plates' setting: yours stands, a fight waits, off puts it back
    g.C_CVar.SetCVar("nameplateShowFriendlyNpcs", "0")
    check(db.npcMarkersWas is None and db.npcMarkersPlates is False,
          "you turn friendly plates off yourself: yours stands (and the switch for it goes off)")
    db.npcMarkersPlates = None
    YR.ApplyParts()
    check(g.CV.nameplateShowFriendlyNpcs == "1" and db.npcMarkersWas == "0", "turned on again: on, and written down")
    g.Fire("PLAYER_LOGOUT")
    check(g.CV.nameplateShowFriendlyNpcs == "0" and db.npcMarkersWas is None,
          "logging out: put back before the game saves it")
    g.Fire("PLAYER_ENTERING_WORLD")
    check(g.CV.nameplateShowFriendlyNpcs == "1" and db.npcMarkersWas == "0", "and made again at the next login")
    lua.execute("FIGHT = true")
    db.npcMarkers = False
    YR.ApplyParts()
    check(g.CV.nameplateShowFriendlyNpcs == "1" and at("nameplate1") is None,
          "turned off in a fight: the icons go at once, the setting waits")
    lua.execute("FIGHT = false")
    g.Fire("PLAYER_REGEN_ENABLED")
    check(g.CV.nameplateShowFriendlyNpcs == "0" and db.npcMarkersWas is None, "the fight over: put back as it was")
    writes = g.CV_WRITES
    g.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
    g.Fire("PLAYER_ENTERING_WORLD")
    check(at("nameplate1") is None and g.CV_WRITES == writes, "off: nothing listens, nothing is changed")
    # a player who had friendly plates on: nothing written down, nothing put back
    lua.execute('CV.nameplateShowFriendlyNpcs = "1"')
    db.npcMarkers = True
    YR.ApplyParts()
    db.npcMarkers = False
    YR.ApplyParts()
    check(g.CV.nameplateShowFriendlyNpcs == "1" and db.npcMarkersWas is None, "friendly plates already on: left on")
    lua.execute("CreateFrame = KEPT_CREATE")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
