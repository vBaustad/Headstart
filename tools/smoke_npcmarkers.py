"""Smoke test of quest mob markers (NpcMarkers.lua), in Lua 5.1 (lupa).

    python tools/smoke_npcmarkers.py      (exit code 1 on any failure; tools/smoke.py runs it too)

A sword on the nameplate of an enemy you still need for a quest (the game's objective lines on it, the RestedXP
step's .mob lines), never on a quest giver, a player, a dead enemy or a unit the game keeps secret; none while
Questie draws its own; the game's friendly NPC plates put back where an earlier version turned them on, and
never turned on now. Uses smoke.py's fake game.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOB = 131013


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

    check("npcMarkers" in YR.STARTS_OFF and g.CV.nameplateShowFriendlyNpcs == "0" and at("nameplate4") is None,
          "off on a new install: no icons, the game's friendly plates left as they are")
    # a real hook (the fake one only writes it down): RestedXP's step functions call ours after their own
    lua.execute("""function hooksecurefunc(t, k, fn) local was = t[k] t[k] = function(...) local r = was(...) fn(...) return r end end""")
    db.npcMarkers = True
    YR.ApplyParts()
    check(g.CV.nameplateShowFriendlyNpcs == "0" and g.CV_WRITES == 0, "on: the game's friendly plates never turned on")
    check(at("nameplate4") == MOB, "an enemy with a quest objective of yours not done: the sword")
    pt = g.NPCM_PT(g.PLATES.nameplate4)
    check(pt is not None and pt[1] == "RIGHT" and same(pt[2], g.PLATES.nameplate4.UnitFrame.healthBar),
          "beside the plate's health bar")
    check(at("nameplate1") is None, "the NPC the step says to talk to (a quest giver): nothing - the game shows its own ! and ?")
    check(at("nameplate2") is None, "a player: nothing")
    check(at("nameplate6") is None, "a unit the game keeps secret: nothing, and no error")
    check(at("nameplate9") is None, "an enemy whose name and GUID the game keeps secret: nothing, and no error")
    check(at("nameplate3") is None, "an enemy that counts for nothing: nothing")
    check(at("nameplate5") is None, "an enemy whose objective is done: nothing")

    # a step with a .mob line: that mob gets the sword; by its id in the guide too
    lua.execute("""table.insert(STEP.elements, { mobs = { "Small Crag Boar" }, textOnly = true }) RXP.SetStep(3)""")
    check(at("nameplate3") is None, "a step change is looked at a moment after, not at once")
    g.Later()
    check(at("nameplate3") == MOB, "the step's .mob: the sword")
    lua.execute("""U.nameplate3.guid = "Creature-0-1-2-3-1125-0000" STEP.elements[3].mobs = { "Someone Else::1125" } RXP.SetStep(3) Later()""")
    check(at("nameplate3") == MOB, '"Name::id" in the guide: matched by the id in its GUID')
    lua.execute("""U.nameplate3.dead = true RXP.SetStep(3) Later()""")
    check(at("nameplate3") is None, "a dead one: nothing")
    lua.execute("""U.nameplate3.dead = false RXP.RXPFrame.activeSteps = {} RXP.SetStep(4) Later()""")
    check(at("nameplate3") is None and at("nameplate4") == MOB, "the step over: its mob's sword goes, the objective's stays")
    lua.execute("""RXP.RXPFrame.activeSteps = { STEP } RXP.SetStep(3) Later()""")

    # the tooltip read once per kind of mob (its NPC id), not per plate per look, until the quest log changes
    lua.execute("""TIPS = 0 KEPT_TIP_GET = C_TooltipInfo.GetUnit
        C_TooltipInfo.GetUnit = function(u)
            if U[u] and type(U[u].guid) == "string" and U[u].guid:find("%-2000%-") then TIPS = TIPS + 1 end
            return KEPT_TIP_GET(u)
        end
        U.nameplate4.guid = "Creature-0-1-2-3-2000-0001"
        Plate("nameplate10", { name = "Rockjaw Trogg", enemy = true, objective = "todo", guid = "Creature-0-1-2-3-2000-0002" })""")
    g.Fire("NAME_PLATE_UNIT_ADDED", "nameplate10")
    YR.NpcMarkersMarkAll()
    YR.NpcMarkersMarkAll()
    check(at("nameplate10") == MOB and at("nameplate4") == MOB and g.TIPS == 1,
          f"two of a kind, looked at three times: the game's tooltip read once ({g.TIPS})")
    lua.execute("""U.nameplate4.objective, U.nameplate10.objective = "done", "done" Fire("QUEST_LOG_UPDATE") Later()""")
    check(at("nameplate10") is None and at("nameplate4") is None and g.TIPS == 2,
          f"the quest log changes (the objective done): read again, and the swords go ({g.TIPS})")
    # in a fight the game may keep the line's "done" secret: no sword, and not kept - asked again (the review, 2026-10-21)
    lua.execute("""U.nameplate4.objective, U.nameplate10.objective = "todo", "todo"
        SECRET_DONE = true
        local real = C_TooltipInfo.GetUnit
        C_TooltipInfo.GetUnit = function(u) local d = real(u) if SECRET_DONE and d.lines[2] then d.lines[2].completed = SECRET end return d end
        Fire("QUEST_LOG_UPDATE") Later()""")
    check(at("nameplate4") is None, "the objective's state kept secret: no sword, and no error")
    lua.execute("SECRET_DONE = false")
    YR.NpcMarkersMarkAll()
    check(at("nameplate4") == MOB, "the answer plain again: the sword, without waiting for the quest log to change")
    # turned off, the quest log changes unheard; turned on again: read anew, not what was read before
    db.npcMarkers = False
    YR.ApplyParts()
    lua.execute("""U.nameplate4.objective, U.nameplate10.objective = "done", "done" Fire("QUEST_LOG_UPDATE")""")
    db.npcMarkers = True
    YR.ApplyParts()
    lua.execute("Later()")
    check(at("nameplate4") is None, "off, an objective done meanwhile, on again: no sword left from before")
    lua.execute("""U.nameplate4.objective = "todo" U.nameplate4.guid = nil PLATES.nameplate10 = nil U.nameplate10 = nil
        Fire("NAME_PLATE_UNIT_REMOVED", "nameplate10") C_TooltipInfo.GetUnit = KEPT_TIP_GET Fire("QUEST_LOG_UPDATE") Later()""")
    # Questie draws its own quest icons on plates: none of ours while it does
    lua.execute("""Questie = { db = { profile = { nameplateEnabled = true } } }""")
    YR.ApplyParts()
    YR.NpcMarkersMarkAll()
    check(at("nameplate4") is None, "Questie's nameplate icons on: none of ours (no two icons)")
    lua.execute("""Questie.db.profile.nameplateEnabled = false""")
    YR.NpcMarkersMarkAll()
    check(at("nameplate4") == MOB, "Questie's off: ours back")
    lua.execute("""Questie = nil""")

    # plates that come and go; another addon's plate; one with no health bar
    g.Plate("nameplate7", lua.eval('{ name = "Rockjaw Trogg", enemy = true, objective = "todo" }'), "plater")
    g.Fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
    pt = g.NPCM_PT(g.PLATES.nameplate7)
    check(at("nameplate7") == MOB and same(pt[2], g.PLATES.nameplate7.unitFrame.healthBar),
          "a plate another addon draws (Plater, ElvUI): beside its own health bar")
    g.Plate("nameplate8", lua.eval('{ name = "Rockjaw Trogg", enemy = true, objective = "todo" }'), "nobar")
    g.Fire("NAME_PLATE_UNIT_ADDED", "nameplate8")
    pt = g.NPCM_PT(g.PLATES.nameplate8)
    check(pt is not None and pt[1] == "BOTTOM" and same(pt[2], g.PLATES.nameplate8.UnitFrame.name),
          "a plate with no health bar shown: over the name")
    g.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate8")
    check(at("nameplate8") is None, "a plate gone: its icon hidden")

    # friendly plates an earlier version turned on (what they were written down): put back as this comes on
    db.npcMarkers = False
    YR.ApplyParts()
    lua.execute('CV.nameplateShowFriendlyNpcs = "1" YippRouteDB.npcMarkersWas = "0"')
    db.npcMarkers = True
    YR.ApplyParts()
    check(g.CV.nameplateShowFriendlyNpcs == "0" and db.npcMarkersWas is None,
          "friendly plates an earlier version turned on: put back as they were")
    # in a fight it waits for the fight's end
    db.npcMarkers = False
    YR.ApplyParts()
    lua.execute('CV.nameplateShowFriendlyNpcs = "1" YippRouteDB.npcMarkersWas = "0" FIGHT = true')
    db.npcMarkers = True
    YR.ApplyParts()
    check(g.CV.nameplateShowFriendlyNpcs == "1" and db.npcMarkersWas == "0", "in a fight: it waits")
    lua.execute("FIGHT = false")
    g.Fire("PLAYER_REGEN_ENABLED")
    check(g.CV.nameplateShowFriendlyNpcs == "0" and db.npcMarkersWas is None, "the fight over: put back")
    # changed by you before it was put back: yours stands
    lua.execute('YippRouteDB.npcMarkersWas = "0" FIGHT = true')
    YR.ApplyParts()
    lua.execute('FIGHT = false')
    g.C_CVar.SetCVar("nameplateShowFriendlyNpcs", "1")
    check(db.npcMarkersWas is None, "you set friendly plates yourself meanwhile: yours stands")
    g.Fire("PLAYER_REGEN_ENABLED")
    check(g.CV.nameplateShowFriendlyNpcs == "1", "and nothing is put back over it")

    db.npcMarkers = False
    YR.ApplyParts()
    writes = g.CV_WRITES
    check(at("nameplate4") is None, "turned off: the icons go")
    g.Fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
    g.Fire("PLAYER_ENTERING_WORLD")
    check(at("nameplate4") is None and g.CV_WRITES == writes, "off: nothing listens, nothing is changed")
    lua.execute("CreateFrame = KEPT_CREATE")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
