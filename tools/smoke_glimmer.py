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
function GetProfessions() return 1, 2 end
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
        return lua.eval("(function() for _, f in ipairs(FRAMES) do if f.ring and f.parts then return f end end end)()")

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
    target("Peacebloom", 1618)
    check(lit() and fx().r == YR.GLIMMER_COLORS.red[1] and fx().state == "locked", "a herb with no herbalism: lit red, too low")
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
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
