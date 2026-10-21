"""Glimmer (Glimmer.lua) outside the game: what lights up, in what colour, the game settings it changes
and puts back, and that it rests in a fight and in instances.

    python tools/smoke_glimmer.py

The soft target, its nameplate and the game's settings are faked; whether the game draws what this
asks for is in VERIFY.md."""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
FRAMES, LATER, TICKERS = {}, {}, {}
W = {}
-- a method the code calls that isn't here does nothing; a field never set is nil, as in the game
W.__index = function(t, k) local v = rawget(W, k) if v ~= nil then return v end if type(k) == 'string' and k:match('^%u') then return function() end end end
function W:RegisterEvent(e) self.ev = self.ev or {} self.ev[e] = true end
function W:UnregisterEvent(e) if self.ev then self.ev[e] = nil end end
function W:UnregisterAllEvents() self.ev = nil end
function W:SetScript(what, fn) self.scripts = self.scripts or {} self.scripts[what] = fn end
function W:GetScript(what) return self.scripts and self.scripts[what] end
function W:Show() local was = self.shown self.shown = true if not was and self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end end
function W:Hide() local was = self.shown self.shown = false if was and self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end end
function W:IsShown() return self.shown == true end
function W:SetParent(p) self.parent = p end
function W:GetParent() return self.parent end
function W:CreateTexture() return setmetatable({}, W) end
function W:CreateFontString() return setmetatable({}, W) end
function W:SetText(t) self.text = t end
function W:GetFrameLevel() return self.level or 5 end
function W:SetFrameLevel(l) self.level = l end
function W:SetVertexColor(r, g, b) self.r, self.g, self.b = r, g, b end
function W:GetAtlas() return CURSOR end
function W:GetTexture() return nil end
-- (a frame is shown when it is made, as in the game: a test that made them hidden missed that the
-- effect's OnShow never came, so nothing was ever drawn)
function CreateFrame(kind, name, parent)
    local f = setmetatable({ parent = parent, shown = true }, W)
    table.insert(FRAMES, f)
    if name then _G[name] = f end
    return f
end
function Fire(e, ...) for _, f in ipairs(FRAMES) do if f.ev and f.ev[e] and f.scripts and f.scripts.OnEvent then f.scripts.OnEvent(f, e, ...) end end end
function Listening(e) for _, f in ipairs(FRAMES) do if f.ev and f.ev[e] then return true end end return false end
C_Timer = { After = function(_, fn) table.insert(LATER, fn) end,
    NewTicker = function(_, fn) local t = { fn = fn } t.Cancel = function() t.dead = true end table.insert(TICKERS, t) return t end }
function RunLater() local l = LATER LATER = {} for _, fn in ipairs(l) do fn() end end
function Tick() for _, t in ipairs(TICKERS) do if not t.dead then t.fn() end end end
function LiveTickers() local n = 0 for _, t in ipairs(TICKERS) do if not t.dead then n = n + 1 end end return n end
UIParent = CreateFrame()
PRINTS = {}
function print(m) table.insert(PRINTS, m) end
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
YippRouteDB = {}
-- the game's settings
CVARS = { SoftTargetInteract = "0", SoftTargetInteractRange = "15", SoftTargetInteractArc = "1", SoftTargetInteractOnlyInRange = "1",
    SoftTargetNameplateInteract = "0", SoftTargetIconGameObject = "0", outlineModeShowLootEffectWhenDisabled = "0", graphicsOutlineMode = "2",
    OutlineEngineMode = "2", raidGraphicsOutlineMode = "2", RAIDOutlineEngineMode = "2" }
WRITES = 0
C_CVar = { GetCVar = function(n) return CVARS[n] end, SetCVar = function(n, v) WRITES = WRITES + 1 CVARS[n] = tostring(v) return true end }
COMBAT, INSIDE = false, false
function InCombatLockdown() return COMBAT end
function IsInInstance() return INSIDE, INSIDE and "party" or "none" end
SECRET = {}
function issecretvalue(v) return v == SECRET end
-- the soft target
OBJ = nil           -- { name, guid }
IN_RANGE = false
CURSOR = nil
QUEST = false
PLATES = {}
function UnitIsGameObject(u) if u == "softinteract" then return OBJ ~= nil end return false end
function UnitName(u) if u == "softinteract" and OBJ then return OBJ.name end end
function UnitGUID(u) if u == "softinteract" and OBJ then return OBJ.guid end end
function UnitIsInInteractRange() return IN_RANGE end
function SetUnitCursorTexture() return CURSOR ~= nil end
C_QuestLog = { UnitIsRelatedToActiveQuest = function() return QUEST end }
C_NamePlate = { GetNamePlateForUnit = function(u) return PLATES[u] end }
SKILL = { [186] = 30, [182] = 0 }
PROF1, PROF2 = 1, 2
function GetProfessions() return PROF1, PROF2 end
function GetProfessionInfo(i) local line = i == 1 and 186 or 182 return "x", 0, SKILL[line], 300, 0, 0, line end
function UnitFullName() return "Tester", "Realm" end
function GetRealmName() return "Realm" end
''')
    YR = lua.table()
    for f in ("Core.lua", "Glimmer.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    YR.StartGlimmer()
    YR.partsReady = True
    YR.ApplyParts()
    g = lua.globals()
    db = g.YippRouteDB
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def target(name, oid=1731, plate=True):
        g.OBJ = lua.table_from({"name": name, "guid": f"GameObject-0-1-2-3-4-{oid}-0000AB"}) if name else None
        g.PLATES.softinteract = g.PLATE if plate else None
        lua.execute("Fire('PLAYER_SOFT_INTERACT_CHANGED') RunLater()")

    def fx():
        return lua.eval("(function() for _, f in ipairs(FRAMES) do if f.ring and f.parts and not f.ghost then return f end end end)()")

    hung = lua.eval("function(f) return f ~= nil and f.shown == true and rawequal(f.parent, PLATE) end")

    drawing = lua.eval("function(f) return f ~= nil and f.scripts ~= nil and f.scripts.OnUpdate ~= nil end")

    def lit():
        return hung(fx()) is True and drawing(fx()) is True

    lua.execute("PLATE = CreateFrame('Frame')")

    # off: nothing listened for, nothing of the game's touched
    check(not g.Listening("PLAYER_SOFT_INTERACT_CHANGED") and g.WRITES == 0 and db.glimmerWas is None,
          "off (a new install): nothing listened for, no game setting touched")

    # on
    db.glimmer = True
    YR.ApplyParts()
    lua.execute("RunLater()")
    check(g.CVARS.SoftTargetInteract == "3" and g.CVARS.SoftTargetInteractArc == "2" and g.CVARS.SoftTargetInteractOnlyInRange == "0",
          "on: the game's soft target for objects is turned on")
    check(db.glimmerWas.SoftTargetInteract == "0" and db.glimmerWas.SoftTargetInteractRange == "15",
          "and what those settings were is written down first")
    check(g.CVARS.outlineModeShowLootEffectWhenDisabled == "0" and g.CVARS.graphicsOutlineMode == "2",
          "the quest loot sparkle is left alone until it is asked for")
    # logging out: the settings go back before the game saves them (Headstart removed: the game has its
    # own), and come again at the next login
    lua.execute("Fire('PLAYER_LOGOUT')")
    check(g.CVARS.SoftTargetInteract == "0" and g.CVARS.SoftTargetInteractRange == "15" and g.CVARS.SoftTargetInteractArc == "1"
          and db.glimmerWas is None, "logging out: the soft target settings put back, nothing of ours left written down")
    lua.execute("Fire('PLAYER_ENTERING_WORLD') RunLater()")
    check(g.CVARS.SoftTargetInteract == "3" and db.glimmerWas.SoftTargetInteract == "0",
          "the next login: made again, with what they were written down afresh")
    # the interact key turned off by you while Glimmer is on: off it stays, through the next login, until the card's
    # button turns it on (it was turned on again at every login until 2026-10-21)
    lua.execute("CVARS.SoftTargetInteract = '0' Fire('CVAR_UPDATE', 'SoftTargetInteract', '0')")
    lua.execute("Fire('PLAYER_LOGOUT') Fire('PLAYER_ENTERING_WORLD') RunLater()")
    check(db.glimmerKeyOff is True and g.CVARS.SoftTargetInteract == "0" and YR.GlimmerInteractKey() is False,
          "the interact key turned off by you: not turned on again at the next login")
    YR.GlimmerInteractKeyOn()
    check(db.glimmerKeyOff is None and g.CVARS.SoftTargetInteract == "3" and YR.GlimmerInteractKey() is True,
          "the card's button: on again, and Glimmer's to keep")

    # a copper vein, mining 30
    target("Copper Vein")
    e = fx()
    check(lit() and g.CVARS.SoftTargetNameplateInteract == "1" and g.CVARS.SoftTargetIconGameObject == "1",
          "a copper vein targeted: its plate and the object icon opened, the glimmer hung on it")
    c = YR.GLIMMER_COLORS.yellow
    check(e.r == c[1] and e.g == c[2] and e.b == c[3], f"mining 30 on a vein that needs 1: yellow ({e.r}, {e.g}, {e.b})")
    check(e.state == "ready" and g.LiveTickers() == 1, "out of reach: lit in full all the same (near or not is not drawn)")
    # the game's "unable" cursor out of reach is every node's, not a skill too low (a Peacebloom you can
    # pick was drawn red in the game, 2026-10-14)
    lua.execute("CURSOR = 'Cursor_UnableMine_32' Tick()")
    check(e.state == "ready" and e.r == c[1], "out of reach the game's 'unable' cursor: not too low, still its skill-up colour")
    lua.execute("IN_RANGE = true Tick()")
    check(e.state == "locked" and e.r == YR.GLIMMER_COLORS.red[1], "in reach the 'unable' cursor: too low, red")
    lua.execute("CURSOR = nil Tick()")
    check(e.state == "ready", "in reach and no 'unable': lit in its colour")
    # not one of ours
    target("Mailbox", 32349)
    check(not fx().shown and g.CVARS.SoftTargetNameplateInteract == "0" and g.CVARS.SoftTargetIconGameObject == "0" and g.LiveTickers() == 0,
          "a mailbox: nothing lit, the plate closed again and the object icon back as it was, nothing ticking")
    # the kinds
    # a herb with Mining and no Herbalism: not lit (the owner, 2026-10-16: no flowers for a miner)
    lua.execute("PROF2 = nil Fire('SKILL_LINES_CHANGED')")
    target("Peacebloom", 1618)
    check(not fx().shown, "a herb, with Mining and no Herbalism: not lit")
    target("Copper Vein")
    check(lit(), "a vein with Mining: lit")
    lua.execute("PROF1, PROF2 = nil, 2 Fire('SKILL_LINES_CHANGED')")
    check(not fx().shown, "Mining dropped while a vein is lit: no longer lit")
    lua.execute("KEPT_PROFS = GetProfessions GetProfessions = nil Fire('SKILL_LINES_CHANGED')")
    target("Copper Vein")
    check(lit(), "your professions can't be read: lit as before")
    lua.execute("GetProfessions = KEPT_PROFS PROF1, PROF2 = 1, 2 Fire('SKILL_LINES_CHANGED')")
    target("Peacebloom", 1618)
    check(lit() and fx().r == YR.GLIMMER_COLORS.red[1] and fx().state == "locked", "a herb with Herbalism at 0: lit red, too low")
    db.glimmerHerbs = False
    YR.ApplyParts()
    target("Silverleaf", 1617)
    check(not fx().shown, "herbs switched off: a herb isn't lit")
    db.glimmerHerbs = None
    target("Fishing Bobber", 35591)
    check(lit() and fx().b == YR.GLIMMER_COLORS.bobber[3], "the fishing bobber, by its ID: lit blue")
    target("Battered Chest", 2843)
    check(lit() and fx().r == YR.GLIMMER_COLORS.chest[1], "a chest: lit gold")
    lua.execute("QUEST = true")
    target("Gnomish Tools", 123456)
    check(lit() and fx().g == YR.GLIMMER_COLORS.quest[2], "an object one of your quests needs: lit quest yellow")
    lua.execute("QUEST = false")
    # the quest link says nothing, a quest objective line in its tooltip does
    lua.execute("C_TooltipInfo = { GetUnit = function() if TIP_QUEST then return { lines = { { type = 2 }, { type = 8 } } } end return { lines = {} } end } TIP_QUEST = true")
    target("Tribal Totem", 654321)
    check(lit() and fx().g == YR.GLIMMER_COLORS.quest[2], "a quest object the game's quest link says nothing of: told by its tooltip's objective line")
    lua.execute("TIP_QUEST = false PRINTS = {}")
    YR.GlimmerDebug()
    said = " ".join(str(p) for p in g.PRINTS.values())
    check("Tribal Totem" in said and "quest: no" in said and "the glimmer" in said,
          "/headstart glimmer says what the game says about the object, step by step")
    # neither says a thing (a Gnarlpine Totem in the game, 2026-10-14): its name in an open objective does
    lua.execute("""C_QuestLog.GetNumQuestLogEntries = function() return 2 end
        C_QuestLog.GetInfo = function(i) if i == 1 then return { isHeader = true } end return { questID = 77 } end
        C_QuestLog.GetQuestObjectives = function(id) return { { text = "Gnarlpine Totem destroyed: 0/1", finished = false },
            { text = "Strigid Owl Feather: 3/3", finished = true } } end
        Fire('QUEST_LOG_UPDATE')""")
    target("Gnarlpine Totem", 668493)
    check(lit() and fx().g == YR.GLIMMER_COLORS.quest[2], "a quest object only its name in an open objective tells: lit quest yellow")
    target("Strigid Owl Feather", 668494)
    check(not fx().shown, "a name in an objective that is done: not lit")
    lua.execute("C_QuestLog.GetNumQuestLogEntries = nil Fire('QUEST_LOG_UPDATE')")
    # too low: the game's cursor wins over Classic's number
    target("Mithril Deposit", 2040)
    check(fx().state == "locked", "mithril at mining 30: too low (Classic's 175)")
    lua.execute("CURSOR = 'Cursor_Mine_32' Tick()")
    check(fx().state != "locked", "the game's own cursor says you can mine it: not too low (Forever's number wins)")
    lua.execute("CURSOR = 'Cursor_UnableMine_32' Tick()")
    check(fx().state == "locked", "and its 'unable' cursor: too low")
    lua.execute("CURSOR = nil")
    # a name the tables don't have: the cursor tells herb from ore
    lua.execute("CURSOR = 'Cursor_GatherHerbs_32'")
    target("Silberblatt", 1617)
    check(lit(), "a herb by a name the tables don't have (another language): told by the cursor")
    lua.execute("CURSOR = nil")
    # what the game keeps from addons
    g.OBJ = lua.table_from({"name": g.SECRET, "guid": g.SECRET})
    lua.execute("Fire('PLAYER_SOFT_INTERACT_CHANGED')")
    check(not fx().shown, "a name and ID the game keeps secret: nothing lit, nothing asked of them")

    # the plate comes later, and goes
    target("Tin Vein", 1732, plate=False)
    check(not fx().shown and g.CVARS.SoftTargetNameplateInteract == "1", "no plate yet: the plate is asked for, nothing hung")
    lua.execute("PLATES.softinteract = PLATE Fire('NAME_PLATE_UNIT_ADDED', 'nameplate3')")
    check(lit(), "its plate comes: the glimmer is hung on it")
    lua.execute("PLATES.softinteract = nil Fire('NAME_PLATE_UNIT_REMOVED', 'nameplate3')")
    check(not fx().shown, "its plate goes: the glimmer goes with it")
    lua.execute("OBJ = nil Fire('PLAYER_SOFT_INTERACT_CHANGED')")
    check(g.LiveTickers() == 0, "nothing targeted: nothing ticking, no plate looked for")

    # the game won't hand the plate over by "softinteract": found among the plates on screen (as a herb
    # in the game showed nothing, 2026-10-14)
    lua.execute("function UnitIsUnit(a, b) return a == SOFTPLATE and b == 'softinteract' end SOFTPLATE = 'nameplate7'")
    target("Earthroot", 1619, plate=False)
    check(not fx().shown, "a herb whose plate 'softinteract' doesn't give: nothing hung yet")
    lua.execute("PLATES.nameplate7 = PLATE Fire('NAME_PLATE_UNIT_ADDED', 'nameplate7')")
    check(lit(), "its plate comes as another unit: found among the plates on screen, the glimmer hung on it")
    lua.execute("PLATES.nameplate7 = nil Fire('NAME_PLATE_UNIT_REMOVED', 'nameplate7') OBJ = nil Fire('PLAYER_SOFT_INTERACT_CHANGED') SOFTPLATE = nil")
    # a plate that comes with no word of it: looked for again a few times a second
    target("Earthroot", 1619, plate=False)
    check(not fx().shown and g.LiveTickers() == 1, "no plate yet: it is looked for again")
    lua.execute("PLATES.softinteract = PLATE Tick()")
    check(lit(), "and found when it is there, with no event for it")
    lua.execute("PLATES.softinteract = nil Fire('NAME_PLATE_UNIT_REMOVED', 'nameplate3') OBJ = nil Fire('PLAYER_SOFT_INTERACT_CHANGED')")

    # a fight
    target("Copper Vein")
    lua.execute("Fire('PLAYER_REGEN_DISABLED') COMBAT = true")
    check(not fx().shown and g.CVARS.SoftTargetNameplateInteract == "0", "a fight starts: nothing lit, the plate shut before the lockdown")
    lua.execute("Fire('PLAYER_SOFT_INTERACT_CHANGED')")
    check(not fx().shown, "nothing lights up in a fight")
    lua.execute("COMBAT = false Fire('PLAYER_REGEN_ENABLED')")
    check(lit(), "the fight over: the vein in front of you lights up again")

    # instances
    lua.execute("INSIDE = true Fire('PLAYER_SOFT_INTERACT_CHANGED')")
    check(not fx().shown, "in an instance: nothing, unless asked for")
    db.glimmerInstances = True
    YR.ApplyParts()
    check(lit(), "asked for in instances: lit there too")
    db.glimmerInstances = None
    lua.execute("INSIDE = false")
    YR.ApplyParts()

    # the look follows the settings
    db.glimmerStyle = "beam"
    YR.ApplyParts()
    check(fx().style == "beam" and fx().parts.beam is not None, "the look changed in the settings: the lit object in it at once")
    db.glimmerColor = "white"
    YR.ApplyParts()
    lua.execute("Tick()")
    check(fx().r == 1 and fx().g == 1 and fx().b == 1, "colour White: white")
    db.glimmerColor, db.glimmerStyle = None, None

    # a quest object: as large as a quest giver, in its sparkles (no longer half as large again, in a frame of its own -
    # the owner, 2026-10-21: "it should be the same as quest givers"); a vein the size set
    lua.execute("QUEST = true")
    target("Gnarlpine Totem", 9999)
    check(lit() and abs(fx().scale - 1) < 1e-9 and fx().style == "groundSparkle",
          f"a quest object: a quest giver's size, in sparkles ({fx().scale}, {fx().style})")
    lua.execute("QUEST = false")
    target("Copper Vein")
    check(abs(fx().scale - 1) < 1e-9, f"a vein: the size set ({fx().scale})")

    # the quest loot sparkle
    db.glimmerLoot = True
    YR.ApplyParts()
    check(g.CVARS.outlineModeShowLootEffectWhenDisabled == "1" and g.CVARS.graphicsOutlineMode == "0" and g.CVARS.RAIDOutlineEngineMode == "0",
          "the quest loot sparkle asked for: the outline effect off, the sparkle on")
    lua.execute("CVARS.graphicsOutlineMode = '2' Fire('CVAR_UPDATE', 'graphicsOutlineMode', '2') RunLater()")
    check(g.CVARS.graphicsOutlineMode == "0", "a graphics preset puts the outline back: turned off again a moment later")
    lua.execute("PRINTS = {}")
    db.glimmerLoot = None
    YR.ApplyParts()
    check(g.CVARS.outlineModeShowLootEffectWhenDisabled == "0" and g.CVARS.graphicsOutlineMode == "2"
          and any("restart" in str(p) for p in g.PRINTS.values()),
          "turned off again: the outline back as it was, and it says the sparkle stays until a restart")

    # off: everything as it was
    db.glimmer = None
    YR.ApplyParts()
    check(g.CVARS.SoftTargetInteract == "0" and g.CVARS.SoftTargetInteractRange == "15" and g.CVARS.SoftTargetInteractArc == "1"
          and g.CVARS.SoftTargetNameplateInteract == "0" and g.CVARS.SoftTargetIconGameObject == "0" and db.glimmerWas is None,
          "off: every game setting it changed is as it was, and nothing is kept written down")
    check(not g.Listening("PLAYER_SOFT_INTERACT_CHANGED") and not fx().shown and g.LiveTickers() == 0,
          "and nothing is listened for, shown or ticking")

    # switched off in a fight: put back when it ends
    db.glimmer = True
    YR.ApplyParts()
    lua.execute("COMBAT = true")
    db.glimmer = None
    YR.ApplyParts()
    check(g.CVARS.SoftTargetInteract == "3", "switched off in a fight: the settings wait for the fight to end")
    lua.execute("COMBAT = false Fire('PLAYER_REGEN_ENABLED')")
    check(g.CVARS.SoftTargetInteract == "0" and db.glimmerWas is None and not g.Listening("PLAYER_REGEN_ENABLED"),
          "the fight over: put back, and nothing more listened for")

    # skill-up colours
    sc = YR.GlimmerSkillColor
    check([sc(64, 65), sc(65, 65), sc(90, 65), sc(115, 65), sc(165, 65)] == ["red", "orange", "yellow", "green", "grey"],
          "skill-up colours: red below, orange, then yellow, green and grey at 25, 50 and 100 above")
    # Quest objects (2026-10-21: "I mainly mean quest NPCs and quest items"): the quest givers' sparkles - falling farther
    # down, to the object - and the quest's own line, with its count ("it should be the same as quest givers")
    lua.execute("""W.SetAlpha = function(self, a) self.alpha = a end
        C_TooltipInfo = { GetUnit = function() return { lines = { { type = 2 }, { type = 8, leftText = "Gnoll Paw: 3/8" } } } end }
        QUEST = true COMBAT = false INSIDE = false""")
    db.glimmer = True                # (on again: the tests above end with it off)
    YR.ApplyParts()
    lua.execute("RunLater()")
    target(None)
    target("Gnoll Paw", oid=2000)
    e = fx()
    check(e is not None and e.style == "groundSparkle" and e.line.text == "Gnoll Paw: 3/8" and e.line.shown is True
          and tuple(round(v, 2) for v in (e.r, e.g, e.b)) == (1, 0.5, 0.1),
          f"a quest object: orange sparkles falling over it, its quest's line ({e and e.style}, {e and e.line.text})")
    lua.execute("""C_TooltipInfo = { GetUnit = function() return { lines = { { type = 8, leftText = "Gnoll Paw: 4/8" } } } end }
        Fire('QUEST_LOG_UPDATE') RunLater() Tick()""")
    check(e.line.text == "Gnoll Paw: 4/8", f"one more looted: the count goes up ({e.line.text})")
    db.glimmerQuestText = False
    target(None)
    target("Gnoll Paw", oid=2001)
    check(hung(e) and e.style == "groundSparkle" and e.line.shown is False, "its line switched off on its own: the sparkles, no line")
    db.glimmerQuestText = None
    target(None)
    lua.execute("QUEST = false C_TooltipInfo = nil")
    # Quest givers: an NPC with a quest for you, its name on its plate lit, health bar and level away while it is
    lua.execute("""NPC = { name = "Mountaineer Stormpike", guid = "Creature-0-1-2-3-1343-0000AB" }
        local name, guid = UnitName, UnitGUID
        function UnitName(u) if u == "softinteract" and not OBJ and NPC then return NPC.name end return name(u) end
        function UnitGUID(u) if u == "softinteract" and not OBJ and NPC then return NPC.guid end return guid(u) end
        function UnitExists(u) return u == "softinteract" and (OBJ ~= nil or NPC ~= nil) end
        function UnitIsPlayer() return false end
        HeadstartNS_TIPS = { { 132049, "Stormpike's Delivery", 1, 0.82, 0, true }, { 132049, "Rat Catching", 1, 1, 0 } }
        PLATE.UnitFrame = setmetatable({ HealthBarsContainer = setmetatable({}, W), LevelFrame = setmetatable({}, W), name = setmetatable({}, W) }, W)
        function W:GetCenter() return 300, 400 end function W:GetEffectiveScale() return 1 end""")
    YR.QuestTipLines = lua.eval("function(npc, name) if npc == 1343 then return HeadstartNS_TIPS end return {} end")
    g.OBJ = None
    g.PLATES.softinteract = g.PLATE
    lua.execute("Fire('PLAYER_SOFT_INTERACT_CHANGED') RunLater()")
    e = fx()
    bars = lua.eval("function() return PLATE.UnitFrame.HealthBarsContainer.alpha, PLATE.UnitFrame.LevelFrame.alpha end")
    hb, lv = bars()
    # the NPC as it looks without a plate (the owner, 2026-10-21: "completely normal, with glimmer and marker over and
    # quest text in yellow"): the plate out of sight, its name drawn small and green, the quest's line over it
    uf = g.PLATE.UnitFrame
    check(e.style == "sparkle" and hung(e) and str(e.line.text).startswith("Stormpike's Delivery") and "+1" in str(e.line.text)
          and "|T" not in str(e.line.text) and uf.alpha == 0 and e.npc.text == "Mountaineer Stormpike" and e.npc.shown is True,
          f"a quest giver: sparkles over it, the plate out of sight, its name drawn ({e.npc.text}), the quest over it ({e.line.text})")
    # let go as the camera turns: the plate back only where it can't be seen - not at once (it flashed up as it went)
    g.NPC = None
    lua.execute("Fire('PLAYER_SOFT_INTERACT_CHANGED')")
    _early = uf.alpha
    lua.execute("PLATE.UnitFrame = nil RunLater()")
    check(_early == 0 and uf.alpha == 1, "let go: out of sight still for a moment, then given back to the frame itself (gone to the game's pool)")
    # and its light fades out where it was, not gone in a frame (the owner, 2026-10-22: "fade in/out instead of snapping")
    _ghost = lua.eval("(function() for _, f in ipairs(FRAMES) do if f.ghost then return f end end end)()")
    _was = _ghost is not None and _ghost.shown is True and lua.eval("function(f) return rawequal(f.parent, UIParent) end")(_ghost) and _ghost.out == 1
    _mid = None
    if _ghost is not None:
        lua.execute("local f = (function() for _, f in ipairs(FRAMES) do if f.ghost then return f end end end)() f.scripts.OnUpdate(f, 0.1) GHOST_MID = f.shown")
        _mid = g.GHOST_MID
        lua.execute("local f = (function() for _, f in ipairs(FRAMES) do if f.ghost then return f end end end)() for _ = 1, 4 do if f.scripts and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.1) end end")
    check(_was and _mid is True and _ghost.shown is False and not hung(e),
          "let go: its light fades out where it was (still there a tenth in, gone after a third of a second), the light itself free at once")
    g.PLATE.UnitFrame = uf
    g.NPC = lua.table_from({"name": "Mountaineer Stormpike", "guid": "Creature-0-1-2-3-1343-0000AB"})
    lua.execute("Fire('PLAYER_SOFT_INTERACT_CHANGED')")
    g.NPC = None
    lua.execute("Fire('PLAYER_SOFT_INTERACT_CHANGED') PLATES.nameplate9 = PLATE Fire('NAME_PLATE_UNIT_ADDED', 'nameplate9')")
    check(uf.alpha == 1, "its frame lent at once to another unit: that one shows")
    lua.execute("PLATES.nameplate9 = nil Fire('NAME_PLATE_UNIT_REMOVED', 'nameplate9') RunLater()")
    lua.execute("NOW = 100 function GetTime() return NOW end")
    g.NPC = lua.table_from({"name": "Mountaineer Stormpike", "guid": "Creature-0-1-2-3-1343-0000AB"})
    lua.execute("Fire('PLAYER_SOFT_INTERACT_CHANGED') RunLater()")
    lua.execute("NPC_WAS = NPC NPC = nil Fire('PLAYER_SOFT_INTERACT_CHANGED') NOW = 100.4 NPC = NPC_WAS Fire('PLAYER_SOFT_INTERACT_CHANGED')")
    quick = e.fade
    lua.execute("NPC = nil Fire('PLAYER_SOFT_INTERACT_CHANGED') NOW = 103 NPC = NPC_WAS Fire('PLAYER_SOFT_INTERACT_CHANGED') RunLater()")
    check(hung(e) and quick == 1 and e.fade == 0,
          "back on it within a second: shown as it was, not faded in again; after longer, faded in")
    lua.execute("GetTime = nil")
    db.glimmerGiverText = False
    g.NPC = None
    lua.execute("Fire('PLAYER_SOFT_INTERACT_CHANGED') RunLater()")
    g.NPC = lua.table_from({"name": "Mountaineer Stormpike", "guid": "Creature-0-1-2-3-1343-0000AB"})
    lua.execute("Fire('PLAYER_SOFT_INTERACT_CHANGED') RunLater()")
    check(hung(e) and e.line.shown is False, "its quest's name switched off on its own: the sparkles, no line")
    db.glimmerGiverText = None
    g.NPC = None
    lua.execute("Fire('PLAYER_SOFT_INTERACT_CHANGED') RunLater()")
    hb, lv = bars()
    check(not hung(e) and g.PLATE.UnitFrame.alpha == 1 and hb is None, "looked away: nothing lit, the plate as it was")
    db.glimmerGivers = False
    g.NPC = lua.table_from({"name": "Mountaineer Stormpike", "guid": "Creature-0-1-2-3-1343-0000AB"})
    lua.execute("Fire('PLAYER_SOFT_INTERACT_CHANGED') RunLater()")
    check(not hung(e), "quest givers switched off: nothing lit")
    db.glimmerGivers = None
    # a RestedXP guide leading: its step's NPC alone lights (the owner, 2026-10-21: "only for the current quest in RXP")
    YR.RouteStepNpc = lua.eval("function(unit) return ROUTE_NPC end")
    lua.execute("ROUTE_NPC = false Fire('PLAYER_SOFT_INTERACT_CHANGED') RunLater()")
    _other = hung(e)
    lua.execute("ROUTE_NPC = true HeadstartNS_TIPS = {} Fire('PLAYER_SOFT_INTERACT_CHANGED') RunLater()")
    check(not _other and hung(e) and e.line.shown is False,
          "a guide leading: another quest giver doesn't light; the step's NPC does, even with no quest the tips know of")
    _step = lua.eval("{ HeadstartNS.GlimmerLitGiver() }")
    check(_step[1] is True and _step[2] is True, "and it says the lit giver is the step's NPC (the world marker steps aside for it)")
    YR.RouteStepNpc = None
    lua.execute("HeadstartNS_TIPS = { { 132049, 'Stormpike', 1, 0.82, 0 } } NPC = nil Fire('PLAYER_SOFT_INTERACT_CHANGED') RunLater()")
    g.NPC = lua.table_from({"name": "Mountaineer Stormpike", "guid": "Creature-0-1-2-3-1343-0000AB"})
    lua.execute("Fire('PLAYER_SOFT_INTERACT_CHANGED') RunLater()")
    _free = lua.eval("{ HeadstartNS.GlimmerLitGiver() }")
    check(_free[1] is True and _free[2] is False, "no guide leading: a giver lit, not a step's NPC (the marker stays)")
    g.NPC = None
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
