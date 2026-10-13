"""Smoke test of the character setup (Setup.lua, was YippSetup): Copy this layout on a paladin main, then Set up layout on a fresh paladin, against a fake WoW API.

    python tools/smoke.py      (exit code 1 on any failure)

Runs the real Data/SpellLevels.lua and Core.lua in Lua 5.1 (lupa) with just enough API faked to drive them.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
-- Frames: any unknown field is another callable object, so w.TitleText:SetText() works; Show/Hide
-- keep state and a new frame starts SHOWN, like the game's.
local Obj
-- calling an unknown method returns another fake, so textures and font strings can be made and used
Obj = { __call = function() return setmetatable({}, Obj) end }
Obj.__index = function(t, k)
    local v = rawget(Obj, k)
    if v then return v end
    local child = setmetatable({}, Obj); rawset(t, k, child); return child
end
function Obj.Show(self) rawset(self, "_shown", true) end
function Obj.Hide(self) rawset(self, "_shown", false) end
function Obj.IsShown(self) return rawget(self, "_shown") ~= false end
function Obj.SetScript(self, what, fn) rawset(self, "_" .. what, fn) end
-- the few getters Headstart's style kit does arithmetic or tests on
for _, k in ipairs({ "GetStringWidth", "GetWidth", "GetHeight", "GetFrameLevel", "GetLeft", "GetTop",
    "GetVerticalScroll", "GetVerticalScrollRange" }) do Obj[k] = function() return 20 end end
function Obj.HasFocus() return false end
function Obj.IsMouseOver() return false end
function Obj.GetText(self) return rawget(self, "_text") or "" end
function Obj.SetText(self, t) rawset(self, "_text", t) end
function Obj.SetShown(self, on) rawset(self, "_shown", on and true or false) end
function Obj.HookScript(self, what, fn) rawset(self, "_hook" .. what, fn) end
function CreateFrame(_, name) local f = setmetatable({}, Obj) if name then _G[name] = f end FRAMES = FRAMES or {} table.insert(FRAMES, f) return f end
UIParent = CreateFrame()
StaticPopupDialogs, UISpecialFrames, SlashCmdList = {}, {}, {}
function StaticPopup_Show() end
C_Timer = { After = function(_, fn) fn() end }
-- the intro: a cinematic running, and what cancelling it does
function UnitLevel() return 1 end
IN_CINEMATIC = false
function CinematicFrame_CancelCinematic() IN_CINEMATIC = false; CANCELLED = (CANCELLED or 0) + 1 end
function StopCinematic() IN_CINEMATIC = false; CANCELLED = (CANCELLED or 0) + 1 end       -- (the game's own: what is called now)
strsplit = function(_, s) local a, b = s:match("^(%S*)%s*(.*)$") return a, b ~= "" and b or nil end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
tinsert = table.insert
Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 30 } }
function InCombatLockdown() return COMBAT == true end
function InCinematic() return IN_CINEMATIC end
GUID = "Player-1-0000MAIN"
function UnitGUID() return GUID end
function date() return ", 30 Sep 21:14" end
function time() return 1000 end
function GetRealmName() return "Realm" end
ME = { name = "Main", class = "PALADIN" }
function UnitFullName() return ME.name, "Realm" end
function UnitClass() return "Paladin", ME.class end
RACE = "Dwarf"
function UnitRace() return RACE, RACE end
-- other addons: LOADED = { name, ... }
LOADED = {}
C_AddOns = { GetNumAddOns = function() return #LOADED end, GetAddOnInfo = function(i) return LOADED[i] end,
             IsAddOnLoaded = function(i) return LOADED[i] ~= nil end }
BAR, MACROS, PRINTS = {}, {}, {}
local SPELLS = { [10329] = "Holy Light", [19943] = "Flash of Light", [1311649] = "Seal of Fury",
    [21082] = "Seal of the Crusader", [1152] = "Purify", [498] = "Divine Protection",
    [1022] = "Blessing of Protection", [2580] = "Find Minerals", [635] = "Holy Light", [20594] = "Stoneform",
    [3100] = "Blacksmithing", [2018] = "Blacksmithing", [1240944] = "Blacksmithing", [1278067] = "Bait and Tackle" }
-- Forever's hidden same-named "Blacksmithing" (1240944) has a purple gem; the real ranks have the anvil
ICONS = { [2580] = 136025, [3100] = 136241, [2018] = 136241, [1240944] = 134071, [1278067] = 466035 }
-- what the character knows: a fresh paladin knows Holy Light, Purify and Stoneform here
NAMEID = { ["Holy Light"] = 635, ["Seal of the Crusader"] = 21082, ["Purify"] = 1152, ["Stoneform"] = 20594,
    ["Seal of Fury"] = 1311649, ["Divine Protection"] = 498, ["Blessing of Protection"] = 1022, ["Find Minerals"] = 2580 }
KNOWN = { [635] = true, [20594] = true, [1152] = true }
C_Spell = { GetSpellName = function(id) return SPELLS[id] end,
    GetSpellInfo = function(name) local id = NAMEID[name] return id and { spellID = id } or nil end,
    PickupSpell = function(id) CURSOR_SPELL = id end,
    GetSpellTexture = function(id) return ICONS[id] end }
function IsPlayerSpell(id) return KNOWN[id] == true end
SPELLS_BY_ID = SPELLS
C_Item = { GetItemNameByID = function() return nil end }
function HasAction(s) return BAR[s] ~= nil end
function GetActionInfo(s) local b = BAR[s] return b.kind, b.id end
function GetActionText(s) local b = BAR[s] if not b then return nil end return b.kind == "macro" and (MACROS[b.id] or {})[1] or nil end
function GetMacroIndexByName(n) for i, m in pairs(MACROS) do if m[1] == n then return i end end return 0 end
-- as the game does: a macro's text comes back with a line break at its end that was never written
function GetMacroInfo(i) local m = MACROS[i] if m then return m[1], m[2], m[3] and (m[3] .. "\n") end end
function GetNumMacros() local a, c = 0, 0 for i in pairs(MACROS) do if i <= 120 then a = a + 1 else c = c + 1 end end return a, c end
function DeleteMacro(i)          -- the game shifts the later ones down
    local last = i
    while MACROS[last + 1] do last = last + 1 end
    for j = i, last - 1 do MACROS[j] = MACROS[j + 1] end
    MACROS[last] = nil
end
function CreateMacro(n, icon, body, perChar)
    local i = perChar and 121 or 1
    while MACROS[i] do i = i + 1 end
    MACROS[i] = { n, icon, body }
    return i
end
local cursor
function PickupAction(s) cursor = BAR[s]; BAR[s] = nil end
function PickupMacro(i) cursor = { kind = "macro", id = i } end
function PlaceAction(s)
    if CURSOR_SPELL then cursor = { kind = "spell", id = CURSOR_SPELL }; CURSOR_SPELL = nil end
    BAR[s] = cursor; cursor = nil
end
function ClearCursor() cursor = nil; CURSOR_SPELL = nil end
function print(m) table.insert(PRINTS, m) end
-- AutoFeed as it behaves in the game: Create(name) makes an empty "#showtooltip" macro, records it as
-- owned, and refuses when a macro it doesn't own already has the name.
AutoFeedCharDB = { owned = {} }
local maker = { Create = function(name)
    local idx = GetMacroIndexByName(name)
    if idx > 0 then return AutoFeedCharDB.owned[name] and idx or nil end
    idx = CreateMacro(name, 134400, "#showtooltip", true)
    AutoFeedCharDB.owned[name] = true
    return idx
end }
LibStub = function() return { GetData = function(what) return what == "AutoFeedMacros" and maker or nil end } end
-- Edit Mode, settings, CVars and RestedXP, as the main sees them
Enum = { EditModeLayoutType = { Preset = 0, Account = 1, Character = 2 } }
EDIT = { selected = nil, made = nil }
EditModeManagerFrame = { layoutInfo = { activeLayout = 3, layouts = {
    { layoutName = "Modern", layoutType = 0 }, { layoutName = "Classic", layoutType = 0 },
    { layoutName = "Main", layoutType = 1 } } } }
function EditModeManagerFrame:GetActiveLayoutInfo() return self.layoutInfo.layouts[self.layoutInfo.activeLayout] end
function EditModeManagerFrame:IsLayoutSelected(i) return i == self.layoutInfo.activeLayout end
function EditModeManagerFrame:SelectLayout(i) EDIT.selected = i; self.layoutInfo.activeLayout = i end
function EditModeManagerFrame:MakeNewLayout(info, kind, name) EDIT.made = { kind = kind, name = name } end
C_EditMode = { ConvertLayoutInfoToString = function(l) return "EXPORT:" .. l.layoutName end,
                ConvertStringToLayoutInfo = function() return {} end }
SETTINGS = { PROXY_SHOW_ACTIONBAR_2 = true, PROXY_SHOW_ACTIONBAR_3 = true, PROXY_SHOW_ACTIONBAR_4 = false }
Settings = { GetValue = function(k) return SETTINGS[k] end, SetValue = function(k, v) SETTINGS[k] = v end }
CVARS = { autoLootDefault = "1", showTutorials = "0" }
C_CVar = { GetCVar = function(k) return CVARS[k] end, SetCVar = function(k, v) CVARS[k] = v end }
RXP = { affix = function(a, b) return "0" .. a .. "-0" .. b end, loaded = nil }
function RXP.GetGuideTable(group, name) return group == "Headstart Launch (A)" and (name == "01-05 Coldridge Valley (Launch)" or name == "01-06 Northshire (Launch)") and {} or nil end
function RXP:LoadGuideTable(group, name) self.loaded = group .. "|" .. name end
''')
YS = lua.table()
lua.globals().HeadstartNS = YS            # the setup addon takes Headstart's table from this
for f in ("Style.lua", "Headstart_Setup/SpellLevels.lua", "Headstart_Setup/Setup.lua", "Headstart_Setup/Layouts.lua", "Headstart_Setup/SetupUI.lua"):
    chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
    chunk("Headstart", YS)
YS = YS.Setup          # the setup's own table inside Headstart

g = lua.globals()
SURE = lua.eval("{ sure = true }")      # Set up on a character in play asks first: the tests have answered
lua.execute(r'''
YippSetupDB, YippSetupCharDB = { remember = false }, {}     -- (remembering bars as they change has its own cases, at the end)
MACROS[121] = { "AutoFeed", 134400, "#showtooltip\n/use item:8950" }    -- the main's AutoFeed food macro
MACROS[122] = { "Heal", 134400, "#showtooltip Holy Light(Rank 9)\n/cast [@mouseover] Holy Light(Rank 9); Holy Light (Rank 9)" }
BAR = { [1] = {kind="spell", id=10329}, [2] = {kind="spell", id=19943}, [3] = {kind="spell", id=1311649},
        [4] = {kind="spell", id=21082}, [5] = {kind="spell", id=1152}, [6] = {kind="spell", id=498},
        [7] = {kind="spell", id=1022}, [8] = {kind="item", id=6948}, [9] = {kind="macro", id=121},
        [10] = {kind="spell", id=2580}, [11] = {kind="macro", id=122}, [13] = {kind="spell", id=20594},
        [14] = {kind="spell", id=3100}, [15] = {kind="spell", id=1278067} }
''')
YS.Copy(YS)
print(g.PRINTS[len(g.PRINTS)])

# A fresh paladin: another character with an old macro, its own AutoFeed macro, Blizzard's default bar.
lua.execute(r'''ME.name = "Alt"; GUID = "Player-1-0000ALT"
-- 122 is the AutoFeed macro AutoFeed already made on this character (with this character's food)
MACROS = { [121] = { "Old", 134400, "/say hi" }, [122] = { "AutoFeed", 134400, "#showtooltip\n/use item:4540" } }
AutoFeedCharDB = { owned = { AutoFeed = true } }
BAR = { [1] = {kind="spell", id=635}, [12] = {kind="spell", id=635} }
-- a fresh character: Blizzard's default layout, no extra bars, auto loot off
EditModeManagerFrame.layoutInfo.activeLayout = 1
SETTINGS = { PROXY_SHOW_ACTIONBAR_2 = false, PROXY_SHOW_ACTIONBAR_3 = false, PROXY_SHOW_ACTIONBAR_4 = false }
CVARS = { autoLootDefault = "0", showTutorials = "1", AutoPushSpellToActionBar = "1" }''')
# A brand-new class gets Only spells; these first cases are the question-mark mode an existing setup has.
ok = YS.SpellButtons(YS.Options(YS)) == "spells"
print(("ok  " if ok else "FAIL"), "a class set up for the first time: Only spells by default")
bad_default = not ok
YS.Options(YS).spellButtons = "placeholder"
YS.Apply(YS, None, None, SURE)
ok = g.CVARS.AutoPushSpellToActionBar == "0"
print(("ok  " if ok else "FAIL"), "Blizzard's auto-placing of new spells turned off")
bad_autopush = not ok
ui_line = g.PRINTS[len(g.PRINTS) - 1]
print(ui_line)


def slot(s):
    b = g.BAR[s]
    if not b:
        return None
    if b.kind == "spell":
        return ("spell", g.SPELLS_BY_ID[b.id])
    m = g.MACROS[b.id]
    return (m[1], m[3])


expect = {
    1: ("spell", "Holy Light"),                                        # known: the spell itself
    2: None,                                                           # Flash of Light is level 20
    3: ("Fury", "#showtooltip Seal of Fury\n/cast Seal of Fury"),      # all three seals kept
    4: ("Crusader", "#showtooltip Seal of the Crusader\n/cast Seal of the Crusader"),
    5: ("Purify", "#showtooltip Purify\n/cast [@mouseover,help,nodead][] Purify"),   # known, but mouseover stays a macro
    6: ("Divine", "#showtooltip Divine Protection\n/cast Divine Protection"),
    7: ("Protection", "#showtooltip Blessing of Protection\n/cast Blessing of Protection"),
    8: None,                                                           # Hearthstone: no items
    9: ("AutoFeed", "#showtooltip\n/use item:4540"),   # the one AutoFeed already made here, placed, not copied
    10: None,                                                          # Find Minerals: not learned yet, no placeholder
    11: ("Heal", "#showtooltip Holy Light\n/cast [@mouseover] Holy Light; Holy Light"),   # ranks stripped
    12: None,                                                          # cleared, not in the layout
    13: ("spell", "Stoneform"),                                        # a racial: kept, known
}
bad = (1 if bad_autopush else 0) + (1 if bad_default else 0)
for s, want in expect.items():
    got = slot(s)
    ok = got == want
    bad += not ok
    print(("ok  " if ok else "FAIL"), s, got if ok else f"{got!r} != {want!r}")

made = len([k for k in g.MACROS])
lua.execute("YS_before = 0 for _ in pairs(MACROS) do YS_before = YS_before + 1 end")
YS.Apply(YS, None, None, SURE)
lua.execute("YS_after = 0 for _ in pairs(MACROS) do YS_after = YS_after + 1 end")
again = g.YS_after - g.YS_before
print(("ok  " if again == 0 else "FAIL"), "applying twice creates", again, "new macros")
bad += again != 0
# Set up again later (the plan changed mid-levelling): a macro made on this character since stays;
# a question-mark macro for a spell taken off the layout goes.
lua.execute(r'''local last = 120 while MACROS[last + 1] do last = last + 1 end
    MACROS[last + 1] = { "MyOwn", 132089, "/cast [stealth] Ambush" }
    MACROS[last + 2] = { "Gone", 134400, "#showtooltip Retired Gone\n/cast Retired Gone" }
    MACROS[last + 3] = { "Keep", 134400, "#showtooltip Retired Gone\n/cast !Retired Gone" }''')
YS.Apply(YS, None, None, SURE)
left = [g.MACROS[k][1] for k in g.MACROS]
ok = "MyOwn" in left and "Gone" not in left and "Keep" in left
print(("ok  " if ok else "FAIL"), "set up again: your own macro stays, an unused question mark goes", left)
bad += not ok
lua.execute("for k = 200, 121, -1 do if MACROS[k] and MACROS[k][1] == 'MyOwn' then DeleteMacro(k) end end")
names = [g.MACROS[k][1] for k in g.MACROS]
for name, want in (("Old", 0), ("AutoFeed", 1)):
    n = names.count(name)
    print(("ok  " if n == want else "FAIL"), f"{n} macro(s) named {name}, want {want}")
    bad += n != want

# The window: the first /ysetup shows it (a new frame starts shown; Toggle used to hide it).
g.YippSetupFrame = None
YS.Toggle(YS)
shown = g.YippSetupFrame is not None and g.YippSetupFrame.IsShown(g.YippSetupFrame)
print(("ok  " if shown else "FAIL"), "first /ysetup shows the window")
bad += not shown
YS.Toggle(YS)

# A new character with the same name as a deleted one inherits its saved variables ("seen" = true):
# it still gets the window, because "seen" is kept per GUID.
lua.execute('''YippSetupCharDB.seen = true''')
events = g.FRAMES[2]      # [1] is UIParent, [2] the event frame
events._OnEvent(events, "PLAYER_ENTERING_WORLD", True, False)
shown = g.YippSetupFrame.IsShown(g.YippSetupFrame)
print(("ok  " if shown else "FAIL"), "popup on a new character whose old saved variables say seen")
bad += not shown
# Apply to this character: the window goes once it's applied; in a fight it stays (nothing can be placed)
w = g.YippSetupFrame
lua.execute("COMBAT = true")
w.setup._OnClick(w.setup)
ok = w.IsShown(w)
lua.execute("COMBAT = false")
w.setup._OnClick(w.setup)
ok = ok and not w.IsShown(w)
print(("ok  " if ok else "FAIL"), "Apply: the window stays in a fight, and goes once the layout is applied")
bad += not ok
# Apply interface alone doesn't mark the character done: after the reload it ends in, the window is back for the bars
lua.execute("YippSetupCharDB.seen = nil YippSetupCharDB.uiApplied = nil")
w.Show(w)
YS.Refresh(YS)
both = w.both.IsShown(w.both)
w.applyUI._OnClick(w.applyUI)
ok = (g.YippSetupCharDB.seen is None and g.YippSetupCharDB.uiApplied is not None and w.IsShown(w)
      and not w.both.IsShown(w.both) and "Interface applied" in w.ui.GetText(w.ui))
print(("ok  " if ok else "FAIL"), f"Apply interface: noted, the character not marked done, the window still there for the bars (both offered before: {both})")
bad += not ok
w.Hide(w)
# A character where AutoFeed hasn't made its macro yet: AutoFeed is asked to make it (so it owns and
# fills it), and it goes in its slot. Nothing is copied from the main.
lua.execute(r'''MACROS = {}; AutoFeedCharDB = { owned = {} }''')
YS.Apply(YS, None, None, SURE)
made = [k for k in g.MACROS if g.MACROS[k][1] == "AutoFeed"]
b9 = g.BAR[9]
ok = len(made) == 1 and bool(g.AutoFeedCharDB.owned.AutoFeed) and b9 is not None and b9.kind == "macro" and b9.id == made[0]
ok = ok and g.MACROS[made[0]][3] == "#showtooltip"    # AutoFeed's own body, not the main's copy
print(("ok  " if ok else "FAIL"), f"AutoFeed asked to make its macro on a new character, and it is placed in slot 9: {b9 and (b9.kind, b9.id)}")
bad += not ok

# Without AutoFeed loaded: nothing is made, the slot stays empty, and it says why.
lua.execute(r'''MACROS = {}; AutoFeedCharDB = { owned = {} }; SAVED_LIBSTUB = LibStub; LibStub = nil''')
YS.Apply(YS, None, None, SURE)
names = [g.MACROS[k][1] for k in g.MACROS]
ok = "AutoFeed" not in names and g.BAR[9] is None
said = any("AutoFeed isn't loaded" in str(g.PRINTS[i]) for i in range(1, len(g.PRINTS) + 1))
print(("ok  " if ok and said else "FAIL"), "without AutoFeed: no AutoFeed macro made, slot 9 empty and reported")
bad += not (ok and said)
lua.execute("LibStub = SAVED_LIBSTUB")

# Edit Mode, bars, settings and the RestedXP guide on the new character
ok = g.EDIT.selected == 3
print(("ok  " if ok else "FAIL"), "Edit Mode: the main's layout 'Main' selected")
bad += not ok
ok = g.SETTINGS.PROXY_SHOW_ACTIONBAR_2 is True and g.SETTINGS.PROXY_SHOW_ACTIONBAR_3 is True and g.SETTINGS.PROXY_SHOW_ACTIONBAR_4 is False
print(("ok  " if ok else "FAIL"), "action bars 2 and 3 shown, 4 left hidden")
bad += not ok
ok = g.CVARS.autoLootDefault == "1" and g.CVARS.showTutorials == "0"
print(("ok  " if ok else "FAIL"), "game settings: auto loot on, tutorials off")
bad += not ok
ok = g.RXP.loaded == "Headstart Launch (A)|01-05 Coldridge Valley (Launch)"
print(("ok  " if ok else "FAIL"), f"RestedXP guide loaded: {g.RXP.loaded}")
bad += not ok
# a layout the new character doesn't have (a character layout on the main) is imported as an account one
lua.execute(r'''EditModeManagerFrame.layoutInfo.layouts[3].layoutName = "Other"
YippSetupDB.ui.layout = { name = "MyChar", type = 2, export = "EXPORT:MyChar" }''')
YS.ApplyUI(YS, g.YippSetupDB.ui)
ok = g.EDIT.made is not None and g.EDIT.made.kind == 1 and g.EDIT.made.name == "MyChar"
print(("ok  " if ok else "FAIL"), "missing layout imported as an account layout")
bad += not ok

# A layout copied before bars and settings were saved: Set up layout still picks the guide, and
# logging in on the main fills the missing part in.
lua.execute(r'''YippSetupDB.ui = nil; RXP.loaded = nil''')
YS.Apply(YS, None, None, SURE)
ok = g.RXP.loaded is not None
print(("ok  " if ok else "FAIL"), "old layout without ui: RestedXP guide still loaded")
bad += not ok
# (one saved table stands in for both characters here: taken as the main's own, not as another character's left behind)
lua.execute(r'''ME.name = "Main"; GUID = "Player-1-0000MAIN"; YippSetupCharDB.guid = nil''')
events._OnEvent(events, "PLAYER_ENTERING_WORLD", True, False)
ok = g.YippSetupDB.ui is not None and g.YippSetupDB.ui.cvars is not None
print(("ok  " if ok else "FAIL"), "logging in on the main fills in the missing ui")
bad += not ok

# The interface is the account's: a rogue set up after the paladin main gets the same chat and Edit Mode,
# without copying anything on a rogue; the bars stay per class.
g.YR_SETUP = YS
same = lua.eval("function(a, b) return rawequal(a, b) end")
lua.execute("SHARED_UI = YippSetupDB.ui; ME.class = 'ROGUE'")
ok = same(YS.SharedUI(YS), g.SHARED_UI) and YS.Profile(YS) is None
print(("ok  " if ok else "FAIL"), "a rogue: the paladin main's interface, and no rogue bars until it has its own")
bad += not ok
lua.execute("ME.class = 'PALADIN'")
# a plan saves bars only: the interface it was planned on (a level-1 character's defaults) never replaces it
lua.execute("""SAVED_PROFILE = YippSetupDB.classes.PALADIN.profile
    YR_SETUP:SetProfile({ from = "Alt (plan)", class = "PALADIN", slots = {}, planned = true })""")
ok = same(g.YippSetupDB.ui, g.SHARED_UI)
print(("ok  " if ok else "FAIL"), "a saved plan leaves the account's interface alone")
bad += not ok
lua.execute("YippSetupDB.classes.PALADIN.profile = SAVED_PROFILE")
# from before: each class carried its own; the newest copied from a real character becomes the account's
lua.execute("""SAVED_UI, SAVED_CLASSES = YippSetupDB.ui, YippSetupDB.classes
    YippSetupDB.ui, YippSetupDB.uiMoved = nil, nil
    YippSetupDB.classes = {
        PALADIN = { options = {}, profile = { from = "Old", scanned = 10, slots = {}, ui = { camera = 10 } } },
        ROGUE = { options = {}, profile = { from = "New", scanned = 20, slots = {}, ui = { camera = 20 } } },
        MAGE = { options = {}, profile = { from = "Plan", scanned = 30, slots = {}, planned = true, ui = { camera = 30 } } },
    }""")
ui = YS.SharedUI(YS)
ok = ui is not None and ui.camera == 20 and g.YippSetupDB.uiFrom == "New"
print(("ok  " if ok else "FAIL"), "moved from before: the newest real copy (not a plan's) is the account's interface")
bad += not ok
lua.execute("YippSetupDB.ui, YippSetupDB.classes = SAVED_UI, SAVED_CLASSES")

# Raid frames: class colours and power bars on the main come along to the new character.
g.YR_SETUP = YS
lua.execute(r'''CVARS.raidFramesDisplayClassColor = "1"; CVARS.raidFramesDisplayPowerBars = "1"
RAID_UI = YR_SETUP:ScanUI()
CVARS.raidFramesDisplayClassColor = "0"; CVARS.raidFramesDisplayPowerBars = "0"
YR_SETUP:ApplyUI({ cvars = RAID_UI.cvars, bars = {} }, YR_SETUP:Options())''')
ok = g.RAID_UI.cvars.raidFramesDisplayClassColor == "1" and g.CVARS.raidFramesDisplayClassColor == "1"     and g.CVARS.raidFramesDisplayPowerBars == "1"
print(("ok  " if ok else "FAIL"), "raid frames: class colours and power bars copied from the main")
bad += not ok

# Training Seal of the Crusader swaps its placeholder macro for the spell and deletes the macro;
# in combat it waits until combat ends.
lua.execute(r'''ME.name = "Alt"; GUID = "Player-1-0000ALT"
KNOWN[21082] = true; COMBAT = true''')
events._OnEvent(events, "SPELLS_CHANGED")
ok = slot(4) == ("Crusader", "#showtooltip Seal of the Crusader\n/cast Seal of the Crusader")
print(("ok  " if ok else "FAIL"), "in combat: nothing swapped yet")
bad += not ok
lua.execute("COMBAT = false")
events._OnEvent(events, "PLAYER_REGEN_ENABLED")
ok = slot(4) == ("spell", "Seal of the Crusader") and "Crusader" not in [g.MACROS[k][1] for k in g.MACROS]
print(("ok  " if ok else "FAIL"), f"learned Seal of the Crusader: slot 4 is now {slot(4)}, placeholder macro deleted")
bad += not ok
ok = slot(3) == ("Fury", "#showtooltip Seal of Fury\n/cast Seal of Fury")
print(("ok  " if ok else "FAIL"), "an unlearned seal keeps its placeholder")
bad += not ok

# Training Mining puts Find Minerals into the main's slot for it
lua.execute("KNOWN[2580] = true")
events._OnEvent(events, "SPELLS_CHANGED")
ok = slot(10) == ("spell", "Find Minerals")
print(("ok  " if ok else "FAIL"), f"learned Mining: slot 10 is now {slot(10)}")
bad += not ok

# Blacksmithing: the main has Journeyman (3100); the new character knows Apprentice (2018) and Forever's
# hidden purple-gem "Blacksmithing" (1240944). The real one goes on the bar, not the gem.
lua.execute("KNOWN[2018] = true; KNOWN[1240944] = true")
events._OnEvent(events, "SPELLS_CHANGED")
ok = g.BAR[14] is not None and g.BAR[14].id == 2018
print(("ok  " if ok else "FAIL"), f"Blacksmithing placed as the anvil spell 2018, not the gem: {g.BAR[14] and g.BAR[14].id}")
bad += not ok
ok = g.BAR[15] is None and "Tackle" not in [g.MACROS[k][1] for k in g.MACROS]
print(("ok  " if ok else "FAIL"), "Bait and Tackle (a Fishing passive) gets no question-mark macro")
bad += not ok

# Holy Light Rank 2 from the trainer: slot 1 holds Rank 1 (635) and gets Rank 2 (639)
lua.execute("""KNOWN[639] = true; NAMEID["Holy Light"] = 639
local f = C_Spell.GetSpellName; C_Spell.GetSpellName = function(id) if id == 639 then return "Holy Light" end return f(id) end""")
ok = g.BAR[1].id == 635
# the main keeps Holy Light at Rank 1 on purpose (downranking): it stays Rank 1
lua.execute("""local e = YippSetupDB.classes.PALADIN.profile.slots[1]; e.down, e.id = true, 635
    local mine = YippSetupCharDB.layout and YippSetupCharDB.layout[1]      -- the layout as it went on this character
    if mine then mine.down, mine.id = true, 635 end""")
events._OnEvent(events, "SPELLS_CHANGED")
ok2 = g.BAR[1].id == 635
print(("ok  " if ok2 else "FAIL"), f"downranked on the main: slot 1 stays Rank 1 ({g.BAR[1].id})")
bad += not ok2
lua.execute("""local e = YippSetupDB.classes.PALADIN.profile.slots[1]; e.down, e.id = nil, nil
    local mine = YippSetupCharDB.layout and YippSetupCharDB.layout[1]
    if mine then mine.down, mine.id = nil, nil end""")
# a new rank always goes on the bar unless the spell is kept at a rank: there is no switch for it
YS.Options(YS).rankUp = False          # the switch there used to be: ignored now
events._OnEvent(events, "SPELLS_CHANGED")
ok = ok and g.BAR[1].id == 639
print(("ok  " if ok else "FAIL"), f"Holy Light Rank 2 trained: slot 1 now holds {g.BAR[1].id} (was Rank 1, 635)")
bad += not ok
# a rank you drag onto that slot yourself afterwards is a rank you chose: the next look leaves it
lua.execute("BAR[1] = { kind = 'spell', id = 635 }")
events._OnEvent(events, "SPELLS_CHANGED")
ok = g.BAR[1].id == 635
print(("ok  " if ok else "FAIL"), f"Rank 1 put back on its slot by hand: left there, not swapped for the highest again ({g.BAR[1].id})")
bad += not ok
lua.execute("BAR[1] = { kind = 'spell', id = 639 }")
lua.execute("""KNOWN[639] = nil; NAMEID["Holy Light"] = 635""")   # back to Rank 1 for the tests below

# Other UI addons: action slots are shared by every bar addon, so they are set as always; Edit Mode is
# left to a UI suite and the Blizzard bar settings to any bar addon, and without those no reload is asked.
lua.execute('''LOADED = { "Bartender4" }; EDIT.selected = nil; EditModeManagerFrame.layoutInfo.activeLayout = 1
SETTINGS = { PROXY_SHOW_ACTIONBAR_2 = false, PROXY_SHOW_ACTIONBAR_3 = false, PROXY_SHOW_ACTIONBAR_4 = false }
StaticPopup_Show = function(w) POPUP = w end; POPUP = nil''')
YS.ApplyUI(YS, g.YippSetupDB.ui or lua.eval("nil"))
ok = g.SETTINGS.PROXY_SHOW_ACTIONBAR_2 is False and g.EDIT.selected == 3
check_ok = ok
print(("ok  " if ok else "FAIL"), "Bartender4 loaded: Blizzard bars left alone, Edit Mode still set")
bad += not ok
# Without other UI addons: a reload is asked only when Edit Mode or the bars actually changed.
lua.execute('''LOADED = {}; EditModeManagerFrame.layoutInfo.activeLayout = 1; POPUP = nil''')
YS.ApplyUI(YS, g.YippSetupDB.ui)
first = g.POPUP
lua.execute("POPUP = nil")
YS.ApplyUI(YS, g.YippSetupDB.ui)
ok = first == "YIPPSETUP_RELOAD" and g.POPUP is None
print(("ok  " if ok else "FAIL"), f"reload asked when the layout and bars changed ({first}), not when set up again with nothing to change ({g.POPUP})")
bad += not ok
lua.execute('''LOADED = { "ElvUI", "ElvUI_Options" }; EDIT.selected = nil; EditModeManagerFrame.layoutInfo.activeLayout = 1
SETTINGS = { PROXY_SHOW_ACTIONBAR_2 = false, PROXY_SHOW_ACTIONBAR_3 = false, PROXY_SHOW_ACTIONBAR_4 = false }
POPUP = nil''')
YS.ApplyUI(YS, g.YippSetupDB.ui)
ok = g.EDIT.selected is None and g.SETTINGS.PROXY_SHOW_ACTIONBAR_2 is False and g.POPUP is None
print(("ok  " if ok else "FAIL"), "ElvUI loaded: Edit Mode and Blizzard bars left alone, no reload asked")
bad += not ok
said = g.PRINTS[len(g.PRINTS)]
ok = "left to ElvUI" in said
print(("ok  " if ok else "FAIL"), f"and it says so: {said}")
bad += not ok
lua.execute('''LOADED = { "EllesmereUI_ActionBars" }; EDIT.selected = nil; EditModeManagerFrame.layoutInfo.activeLayout = 1''')
YS.ApplyUI(YS, g.YippSetupDB.ui)
ok = g.EDIT.selected is None
print(("ok  " if ok else "FAIL"), "an EllesmereUI module counts as EllesmereUI")
bad += not ok
# the guide follows the race
lua.execute('''LOADED = {}; RACE = "Human"; RXP.loaded = nil''')
YS.ApplyUI(YS, g.YippSetupDB.ui)
ok = g.RXP.loaded == "Headstart Launch (A)|01-06 Northshire (Launch)"
print(("ok  " if ok else "FAIL"), f"a Human starts on the Northshire route: {g.RXP.loaded}")
bad += not ok
lua.execute("RACE = 'Dwarf'")

# The Character setup options. Start each case from a clean new character.
lua.execute('''
C_Item.PickupItem = function(id) CURSOR_ITEM = id end
local place = PlaceAction
function PlaceAction(s)
    if CURSOR_ITEM then BAR[s] = { kind = "item", id = CURSOR_ITEM } CURSOR_ITEM = nil return end
    place(s)
end
function Fresh(opts)
    ME.name = "Alt"; GUID = "Player-1-0000ALT"; RACE = "Dwarf"; LOADED = {}
    MACROS = {}; BAR = {}; KNOWN = { [635] = true, [20594] = true, [1152] = true }
    -- an existing setup's question marks, unless the case says otherwise
    YippSetupDB.classes[ME.class].options = { placeholders = true }
    local o = YR_SETUP:Options()
    if opts and (opts.spellButtons or opts.placeholders ~= nil) then o.spellButtons = nil end
    for k, v in pairs(opts or {}) do o[k] = v end
end
''')
g.YR_SETUP = YS
lua.execute("Fresh({ items = true })")
YS.Apply(YS, None, None, SURE)
ok = g.BAR[8] is not None and g.BAR[8].kind == "item" and g.BAR[8].id == 6948
print(("ok  " if ok else "FAIL"), "items on: the Hearthstone goes back on its slot")
bad += not ok

lua.execute("Fresh({ placeholders = false })")
YS.Apply(YS, None, None, SURE)
ok = g.BAR[4] is None and g.BAR[1] is not None and g.BAR[1].kind == "spell"
print(("ok  " if ok else "FAIL"), "placeholders off: an unlearned spell's slot stays empty, a known one is placed")
bad += not ok
lua.execute("KNOWN[21082] = true")
events._OnEvent(events, "SPELLS_CHANGED")
ok = g.BAR[4] is not None and g.BAR[4].kind == "spell" and g.BAR[4].id == 21082
print(("ok  " if ok else "FAIL"), "... and goes in when it is learned")
bad += not ok

lua.execute("Fresh({ professions = false }); KNOWN[2580] = true")
YS.Apply(YS, None, None, SURE)
events._OnEvent(events, "SPELLS_CHANGED")
ok = g.BAR[10] is None
print(("ok  " if ok else "FAIL"), "professions off: Find Minerals is not placed, even when known")
bad += not ok

lua.execute("Fresh(); OLD_LEVEL = UnitLevel UnitLevel = function() return 10 end")
YS.Apply(YS, None, None, SURE)
ok = g.BAR[2] is not None and g.BAR[2].kind == "macro"
print(("ok  " if ok else "FAIL"), "level 10: Flash of Light (level 20, ten levels ahead) gets its question mark")
bad += not ok
lua.execute("UnitLevel = OLD_LEVEL")

# the level limit is for a new character's question marks: it never drops a spell at or under your level
lua.execute("Fresh(); OLD_LEVEL = UnitLevel UnitLevel = function() return 30 end NAMEID['Flash of Light'] = 19750 KNOWN[19750] = true")
YS.Apply(YS, None, None, SURE)
ok = g.BAR[2] is not None and g.BAR[2].kind == "spell" and g.BAR[2].id == 19750
print(("ok  " if ok else "FAIL"), "level 30: a level 20 spell you know goes on its slot")
bad += not ok
# ... and a spell above the limit, left out when the layout went on, goes into its empty slot once learned
lua.execute("Fresh(); UnitLevel = function() return 1 end KNOWN[19750] = nil")
YS.Apply(YS, None, None, SURE)
ok = g.BAR[2] is None
print(("ok  " if ok else "FAIL"), "level 1: a level 20 spell is too far ahead for a button yet")
bad += not ok
lua.execute("UnitLevel = function() return 20 end KNOWN[19750] = true")
events._OnEvent(events, "SPELLS_CHANGED")
ok = g.BAR[2] is not None and g.BAR[2].kind == "spell" and g.BAR[2].id == 19750
print(("ok  " if ok else "FAIL"), "... and goes into its slot the moment it is learned")
bad += not ok
lua.execute("UnitLevel = OLD_LEVEL NAMEID['Flash of Light'] = nil KNOWN[19750] = nil")
# the planner's apply: only the slots it names - nothing else is cleared, no macro of yours is deleted
lua.execute("""Fresh(); BAR[30] = { kind = 'spell', id = 999 } BAR[1] = { kind = 'spell', id = 999 }
    MACROS[121] = { 'Mine', 1, '/dance' }""")
YS.Apply(YS, None, lua.eval("{ [1] = true, [40] = true }"))
ok = g.BAR[30] is not None and g.BAR[30].id == 999 and g.BAR[1] is not None and g.BAR[1].id == 635 and g.MACROS[121] is not None
print(("ok  " if ok else "FAIL"), "apply to named slots: slot 1 gets the saved spell, a button elsewhere and your macros stay")
bad += not ok
lua.execute("BAR[40] = { kind = 'spell', id = 999 }")
YS.Apply(YS, None, lua.eval("{ [40] = true }"))
ok = g.BAR[40] is None and g.BAR[30] is not None
print(("ok  " if ok else "FAIL"), "a named slot with nothing saved for it is emptied")
bad += not ok
# what the planner starts from: the bars, with the saved layout where they're empty; a question mark
# Headstart made for a saved spell is that spell
lua.execute("Fresh()")
YS.Apply(YS, None, None, SURE)
plan, now, differ, won = YS.PlanStart()
saved = YS.Profile(YS).slots
ok = all(plan[k] is not None for k in saved) and plan[4] is not None and plan[4].kind == "spell" and now[4] is not None and now[4].kind == "spell"
print(("ok  " if ok else "FAIL"), "the planner's start: every saved button, and a question-mark macro on the bar read as its spell")
bad += not ok
lua.execute("BAR[60] = { kind = 'spell', id = 635 }")
plan, now, differ, won = YS.PlanStart()
ok = plan[60] is not None and plan[60].name == "Holy Light"
print(("ok  " if ok else "FAIL"), "... and a button on the bars that isn't in the saved layout is in it too")
bad += not ok
# your bars against the saved layout, where both hold something different in a slot
check_was = YS.Profile(YS).slots[1].name
lua.execute("KEPT_BAR1 = BAR[1] BAR[1] = { kind = 'spell', id = 1152 }")
plan, now, differ, won = YS.PlanStart()
ok = won == "bars" and differ >= 1 and plan[1].name == "Purify"
print(("ok  " if ok else "FAIL"), f"a character set up from the layout: a button moved by hand since is what the plan shows ({won}, {differ} differ)")
bad += not ok
plan, now, differ, won = YS.PlanStart("profile")
ok = won == "profile" and plan[1].name == check_was and now[1].name == "Purify"
print(("ok  " if ok else "FAIL"), "asked for the saved plan instead: that button is the plan's")
bad += not ok
lua.execute("YS_APPLIED = YippSetupCharDB.applied YippSetupCharDB.applied = nil YS_FROM = YippSetupDB.classes.PALADIN.profile.from YippSetupDB.classes.PALADIN.profile.from = 'Main-Realm'")
plan, now, differ, won = YS.PlanStart()
ok = won == "profile" and plan[1].name == check_was and plan[60] is not None
print(("ok  " if ok else "FAIL"), "a character that never had the layout put on: the saved plan wins, and what only the bars have stays")
bad += not ok
lua.execute("KEPT_PROFILE = YippSetupDB.classes.PALADIN.profile YippSetupDB.classes.PALADIN.profile = nil")
plan, now, differ, won = YS.PlanStart()
ok = won == "bars" and differ == 0 and plan[1].name == "Purify"
print(("ok  " if ok else "FAIL"), "no saved layout for the class: the plan is your bars as they are")
bad += not ok
lua.execute("YippSetupDB.classes.PALADIN.profile = KEPT_PROFILE YippSetupDB.classes.PALADIN.profile.from = YS_FROM YippSetupCharDB.applied = YS_APPLIED BAR[1] = KEPT_BAR1")
# an old button at a lower rank is not a choice: read as behind (stale), never as kept at that rank
lua.execute("""Fresh(); KNOWN[639] = true; NAMEID["Holy Light"] = 639; BAR[1] = { kind = 'spell', id = 635 }""")
now, _ = YS.ReadBars()
ok = now[1] is not None and now[1].stale is True and now[1].rankID == 635 and now[1].down is None
print(("ok  " if ok else "FAIL"), "a Rank 1 button with Rank 2 known: behind, not downranked")
bad += not ok
lua.execute("""KEPT_SLOT = YippSetupDB.classes.PALADIN.profile.slots[1]
    YippSetupDB.classes.PALADIN.profile.slots[1] = { kind = 'spell', name = 'Holy Light', level = 1, down = true, id = 635, rank = 1 }""")
plan, *_ = YS.PlanStart()
ok = plan[1] is not None and plan[1].down is True and plan[1].id == 635
print(("ok  " if ok else "FAIL"), "... unless you set that rank in the planner: then it stays set")
bad += not ok
lua.execute("""KNOWN[639] = nil; NAMEID["Holy Light"] = 635; YippSetupDB.classes.PALADIN.profile.slots[1] = KEPT_SLOT""")
# Set up on a character in play: asked first, nothing touched until answered; Bars only keeps macros
# and the interface; undo puts the bars and macros back
lua.execute("""Fresh(); OLD_LEVEL = UnitLevel UnitLevel = function() return 30 end
    for i = 20, 40 do BAR[i] = { kind = 'spell', id = 635 } end
    MACROS[121] = { 'Mine', 1, '/dance' }
    YippSetupCharDB.applied = nil          -- never set up before: its macros would go
    YippSetupCharDB.backup, YippSetupCharDB.older, YippSetupCharDB.first = nil, nil, nil       -- and nothing of it written down yet
    ASKED = nil StaticPopup_Show = function(w, text) ASKED = { which = w, text = text } return ASKED end""")
YS.Apply(YS)
ok = g.ASKED is not None and g.ASKED.which == "YIPPSETUP_CONFIRM" and g.BAR[30] is not None and g.MACROS[121] is not None     and "21 buttons" in g.ASKED.text and "1 of this character's macros" in g.ASKED.text
print(("ok  " if ok else "FAIL"), f"Set up at level 30 with buttons and a macro: asked first, with what goes ({g.ASKED and g.ASKED.text})")
bad += not ok
lua.execute("CVARS_SET = 0 local old = C_CVar.SetCVar C_CVar.SetCVar = function(...) CVARS_SET = CVARS_SET + 1 return old(...) end")
lua.execute("StaticPopupDialogs.YIPPSETUP_CONFIRM.OnAlt(nil, nil)")
ok = g.BAR[30] is None and g.BAR[1] is not None and g.MACROS[121] is not None and g.CVARS_SET == 0
print(("ok  " if ok else "FAIL"), "Bars only: the saved bars go on, your macro stays, no game setting is touched")
bad += not ok
ok = g.YippSetupCharDB.backup is not None and g.YippSetupCharDB.first is not None and g.YippSetupCharDB.first.slots[30] is not None
print(("ok  " if ok else "FAIL"), "before it changes anything: the bars written down, and kept apart as this character's first")
bad += not ok
YS.Undo(YS)
ok = g.BAR[30] is not None and g.BAR[30].id == 635 and g.YippSetupCharDB.applied is None and g.YippSetupCharDB.backup is None
print(("ok  " if ok else "FAIL"), "/ysetup undo: the bars as they were before, and the character no longer counts as set up")
bad += not ok
# A second Set up used to overwrite the only copy: the bars built by hand were gone for good. Now each
# change has its own copy behind the last, and the first is kept whatever comes after.
def bars():          # (a macro by its name: its place in the macro list moves as macros come and go)
    return dict((k, (v.kind, g.MACROS[v.id][1] if v.kind == "macro" and g.MACROS[v.id] else v.id)) for k, v in g.BAR.items())
def mine():
    return any(m[1] == "Mine" for m in g.MACROS.values())
hand = bars()
YS.Apply(YS, None, None, SURE)
once = bars()
lua.execute("BAR[60] = { kind = 'spell', id = 635 }")       # something you put on yourself in between
between = bars()
YS.Apply(YS, None, None, SURE)
ok = once != hand and g.YippSetupCharDB.backup is not None and len(list(g.YippSetupCharDB.older.values())) == 1
print(("ok  " if ok else "FAIL"), "applied twice: the second copy does not replace the first one")
bad += not ok
YS.Undo(YS)
# (Headstart's own question-mark macros are not yours to get back: a spell you know stands where its
# question mark was, one you don't know yet leaves its slot empty)
now = bars()
ok = (now.get(60) == ("spell", 635) and all(now.get(k) == v for k, v in between.items() if v[0] != "macro")
      and g.YippSetupCharDB.applied is not None and g.YippSetupCharDB.backup is not None)
print(("ok  " if ok else "FAIL"), "undo: as it was before the second apply - the button you added in between too - and still set up (it was, then)")
bad += not ok
YS.Undo(YS)
ok = bars() == hand and mine() and g.YippSetupCharDB.applied is None and g.YippSetupCharDB.backup is None
print(("ok  " if ok else "FAIL"), f"undo again: the bars you built by hand, and your macro ({len(bars())} buttons)")
bad += not ok
YS.Undo(YS)
ok = bars() == hand
print(("ok  " if ok else "FAIL"), "and once more: nothing left to undo, nothing changed")
bad += not ok
# the first copy is kept for good: whatever was applied since, /ysetup undo first is the character as it was
for _ in range(7):
    YS.Apply(YS, None, None, SURE)
    lua.execute("BAR[70] = { kind = 'spell', id = 635 }")
ok = len(list(g.YippSetupCharDB.older.values())) == 4 and bars() != hand
print(("ok  " if ok else "FAIL"), "seven applies: five copies kept in all, the oldest of them dropped")
bad += not ok
YS.Undo(YS, True)
ok = bars() == hand and mine() and g.YippSetupCharDB.first is not None and g.YippSetupCharDB.backup is None and g.YippSetupCharDB.applied is None
print(("ok  " if ok else "FAIL"), "/ysetup undo first: the bars and the macro as they were before Headstart changed anything, and that copy stays")
bad += not ok
# the planner and a switch of profile change buttons too (only): they write a copy down as well
lua.execute("YippSetupCharDB.backup, YippSetupCharDB.older = nil, nil")
YS.Apply(YS, None, lua.eval("{ [1] = true }"), SURE)
ok = g.YippSetupCharDB.backup is not None and g.YippSetupCharDB.backup.slots[30] is not None
print(("ok  " if ok else "FAIL"), "the planner's Save and apply, and a switch of profile: a copy first, so they can be undone")
bad += not ok
YS.Undo(YS)
ok = bars() == hand
print(("ok  " if ok else "FAIL"), "and undone: the bars as they were")
bad += not ok
# Undo with no room for the macros it must make again: nothing is touched, and the copy is kept
YS.Apply(YS, None, None, SURE)
applied = bars()
# (the character's macro list filled since: every free place taken)
lua.execute("KEPT_M = {} for i = 121, 150 do KEPT_M[i] = MACROS[i] MACROS[i] = MACROS[i] or { 'Full' .. i, 1, '/sit' } end")
YS.Undo(YS)
ok = bars() == applied and g.YippSetupCharDB.backup is not None and g.MACROS[150] is not None
print(("ok  " if ok else "FAIL"), "undo with the macro list full: the bars are not cleared, nothing is deleted, the copy is kept")
bad += not ok
lua.execute("for i = 121, 150 do MACROS[i] = KEPT_M[i] end")
YS.Undo(YS)
ok = bars() == hand and mine()
print(("ok  " if ok else "FAIL"), "room made: the same undo now puts everything back")
bad += not ok
lua.execute("UnitLevel = OLD_LEVEL")
# a spell you took off a slot it was put on stays off
lua.execute("Fresh()")
YS.Apply(YS, None, None, SURE)
lua.execute("BAR[1] = nil")
events._OnEvent(events, "SPELLS_CHANGED")
ok = g.BAR[1] is None
print(("ok  " if ok else "FAIL"), "a spell you took off its slot after Set up isn't put back")
bad += not ok
# a button a layout can't hold is still a button: the planner's start has it, and never fills its slot
lua.execute("Fresh(); BAR[1] = { kind = 'mount', id = 77 }")
plan, now, differ, won = YS.PlanStart()
ok = plan[1] is not None and plan[1].kind == "other" and now[1] is not None and now[1].kind == "other"
print(("ok  " if ok else "FAIL"), "a mount on a slot the saved layout has a spell for: the planner keeps the mount there")
bad += not ok
# the interface alone: no button and no macro is touched, and its undo undoes only that
lua.execute("""Fresh(); BAR[50] = { kind = 'spell', id = 635 } MACROS[121] = { 'Mine', 1, '/dance' }
    YippSetupCharDB.backup, YippSetupCharDB.uiBackup = nil, nil""")
bars_before = dict((k, v.id) for k, v in g.BAR.items())
lua.execute("ASKED = nil StaticPopup_Show = function(w, text) ASKED = { which = w, text = text } return ASKED end")
YS.AskInterface(YS)
ok = g.ASKED is not None and g.ASKED.which == "YIPPSETUP_INTERFACE" and g.YippSetupCharDB.uiBackup is None
print(("ok  " if ok else "FAIL"), "Apply interface from the settings or /ysetup ui: asked first, nothing changed until answered")
bad += not ok
lua.execute("StaticPopupDialogs.YIPPSETUP_INTERFACE.OnAccept()")
ok = dict((k, v.id) for k, v in g.BAR.items()) == bars_before and g.MACROS[121] is not None and g.YippSetupCharDB.uiBackup is not None
print(("ok  " if ok else "FAIL"), "Apply interface: every button and macro is as it was, and a copy to undo is kept")
bad += not ok
YS.CopyInterface(YS)            # saves the interface, and says so, without reading a bar
YS.Undo(YS)
ok = dict((k, v.id) for k, v in g.BAR.items()) == bars_before and g.YippSetupCharDB.uiBackup is None
print(("ok  " if ok else "FAIL"), "its undo leaves the bars alone too")
bad += not ok
g.SlashCmdList.YIPPSETUP("debug")
print("ok  ", "/ysetup debug prints without an error")

lua.execute("Fresh({ clearBars = false }); BAR[20] = { kind = 'spell', id = 635 }")
YS.Apply(YS, None, None, SURE)
ok = g.BAR[20] is not None and g.BAR[20].id == 635
print(("ok  " if ok else "FAIL"), "clear bars off: a button the saved layout doesn't use is kept")
bad += not ok

# Spell buttons: only spells, macros for every spell, and a downranked button's macro casting its rank.
def chk(ok, what):
    global bad
    print(("ok  " if ok else "FAIL"), what)
    bad += not ok


lua.execute("Fresh({ spellButtons = 'spells' })")
YS.Apply(YS, None, None, SURE)
chk(g.BAR[4] is None and g.BAR[1] is not None and g.BAR[1].kind == "spell",
    "only spells: an unlearned spell's slot stays empty, a known one is the spell")
mo = g.BAR[5]
chk(mo is not None and mo.kind == "macro" and "@mouseover" in g.MACROS[mo.id][3],
    "only spells: a mouseover spell is still its macro (that is what makes it mouseover)")
lua.execute("Fresh({ spellButtons = 'macros' })")
YS.Apply(YS, None, None, SURE)
b = g.BAR[1]
m = b and b.kind == "macro" and g.MACROS[b.id]
chk(m and m[3] == "#showtooltip Holy Light\n/cast Holy Light", f"macros for every spell: known Holy Light is a macro too ({m and m[3]!r})")
lua.execute("KNOWN[21082] = true")
events._OnEvent(events, "SPELLS_CHANGED")
chk(g.BAR[4] is not None and g.BAR[4].kind == "macro", "... and a spell learned later stays its macro")
lua.execute("""Fresh({ spellButtons = 'macros' })
    local e = YippSetupDB.classes.PALADIN.profile.slots[1]
    SAVED_SLOT1 = { down = e.down, id = e.id, rank = e.rank }
    e.down, e.id, e.rank = true, 635, 1""")
YS.Apply(YS, None, None, SURE)
b = g.BAR[1]
m = b and b.kind == "macro" and g.MACROS[b.id]
chk(m and m[3] == "#showtooltip Holy Light(Rank 1)\n/cast Holy Light(Rank 1)",
    f"a downranked button's macro casts that rank ({m and m[3]!r})")
lua.execute("""YippSetupDB.classes.PALADIN.profile.slots[1].rank = nil
    C_Spell.GetSpellSubtext = function(id) return id == 635 and "Rank 1" or nil end   -- the game's own rank text
    Fresh({ spellButtons = 'macros' })""")
YS.Apply(YS, None, None, SURE)
b = g.BAR[1]
m = b and b.kind == "macro" and g.MACROS[b.id]
chk(m and "(Rank 1)" in m[3], f"saved before ranks were stored, it still gets its rank ({m and m[3]!r})")
lua.execute("""local e = YippSetupDB.classes.PALADIN.profile.slots[1]
    e.down, e.id, e.rank = SAVED_SLOT1.down, SAVED_SLOT1.id, SAVED_SLOT1.rank
    Fresh({ placeholders = false })""")
chk(YS.SpellButtons(YS.Options(YS)) == "spells", "an old 'placeholders off' reads as Only spells")
lua.execute("Fresh({ spellButtons = 'spells' }); KNOWN[2580] = true")
YS.Apply(YS, None, None, SURE)
events._OnEvent(events, "SPELLS_CHANGED")
chk(g.BAR[10] is not None and g.BAR[10].kind == "spell", "a profession spell goes on as the spell itself, never a macro")
counts = {}
for mode in ("spells", "placeholder", "macros"):
    lua.execute(f"Fresh({{ spellButtons = '{mode}' }})")
    n, limit = YS.MacrosNeeded(YS, None, YS.Options(YS))
    counts[mode] = n
chk(limit == 30 and 0 < counts["spells"] < counts["placeholder"] < counts["macros"],
    f"macros the layout takes, of the game's 30: only spells {counts['spells']} < question marks"
    f" {counts['placeholder']} < every spell {counts['macros']}")


lua.execute("Fresh({ classSpells = false, racials = false })")
YS.Apply(YS, None, None, SURE)
ok = g.BAR[1] is None and g.BAR[13] is None and g.BAR[11] is not None
print(("ok  " if ok else "FAIL"), "class spells and racials off: only macros go on (your Heal macro is there)")
bad += not ok

lua.execute("Fresh({ mouseover = 'Holy Light' })")
YS.Apply(YS, None, None, SURE)
lua.execute("KNOWN[635] = nil")
lua.execute("Fresh({ mouseover = 'Holy Light' }); KNOWN[635] = nil")
YS.Apply(YS, None, None, SURE)
m = g.MACROS[g.BAR[1].id] if g.BAR[1] and g.BAR[1].kind == "macro" else None
ok = m is not None and "@mouseover" in m[3]
print(("ok  " if ok else "FAIL"), f"mouseover list: Holy Light becomes a mouseover macro: {m and m[3]!r}")
bad += not ok
lua.execute("Fresh()")

# A friend's setup from before settings were per class: one set of options and one saved layout.
# Nothing of it is changed or lost: the layout's class gets both, other classes start from the options.
lua.execute(r'''
OLD_PROFILE = { from = "Friend-Realm", class = "PALADIN", scanned = 1, slots = {}, ui = { cvars = {}, bars = {} } }
YippSetupDB = { remember = false, options = { maxLevel = 14, items = true, clearBars = false }, profile = OLD_PROFILE }
''')
o = YS.Options(YS)
p = YS.Profile(YS)
ok = o.maxLevel == 14 and o["items"] is True and o.clearBars is False and p is not None and p["from"] == "Friend-Realm"
print(("ok  " if ok else "FAIL"), "old setup: this paladin keeps the friend's options and saved layout")
bad += not ok
o.maxLevel = 20
ok = g.YippSetupDB.options.maxLevel == 14 and lua.eval("YippSetupDB.profile == OLD_PROFILE and OLD_PROFILE.from == 'Friend-Realm'")
print(("ok  " if ok else "FAIL"), "and the old settings themselves are never changed (an older Headstart still reads them)")
bad += not ok
w = YS.Options(YS, "WARRIOR")
ok = w.maxLevel == 14 and w["items"] is True and YS.Profile(YS, "WARRIOR") is None
print(("ok  " if ok else "FAIL"), "a warrior starts from the same choices, with no layout (a paladin's bars aren't a warrior's)")
bad += not ok
w["items"] = False
ok = YS.Options(YS, "PALADIN")["items"] is True
print(("ok  " if ok else "FAIL"), "and changing the warrior's choices leaves the paladin's alone")
bad += not ok

# The intro cinematic a new character logs in to is cancelled while level 1 (an option, on by default)
lua.execute("IN_CINEMATIC = true; CANCELLED = 0")
YS.SkipIntro()
ok = g.CANCELLED == 1 and not g.IN_CINEMATIC
print(("ok  " if ok else "FAIL"), "the intro cinematic is cancelled on a level-1 character")
bad += not ok
lua.execute("IN_CINEMATIC = true; CANCELLED = 0; YR_SETUP:Options().skipIntro = false")
YS.SkipIntro()
ok = g.CANCELLED == 0
print(("ok  " if ok else "FAIL"), "... unless the option is off")
bad += not ok
lua.execute("YR_SETUP:Options().skipIntro = true; IN_CINEMATIC = false")


def report(ok, what):
    global bad
    print(("ok  " if ok else "FAIL"), what)
    bad += not ok


# Without a reload: the game's own functions switch Edit Mode and the bars; Blizzard's Edit Mode code
# (SelectLayout) and Settings are not touched, so no reload is asked. Checked a moment later.
lua.execute(r'''
LOADED = {}; RACE = "Dwarf"; EDIT.selected = nil; POPUP = nil
StaticPopup_Show = function(w) POPUP = w end
LATER = {}
C_Timer.After = function(_, fn) table.insert(LATER, fn) end
function RunLater() local l = LATER LATER = {} for _, fn in ipairs(l) do fn() end end
EditModeManagerFrame.layoutInfo.activeLayout = 1
EditModeManagerFrame.layoutInfo.layouts[3].layoutName = "Main"
TOGGLES = { false, false, false, false, false, false, false }
function GetActionBarToggles() return unpack(TOGGLES) end
function SetActionBarToggles(...) TOGGLES = { ... } end
for i, name in ipairs({ "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight" }) do
    _G[name] = { IsShown = function() return TOGGLES[i] end }
end
SETTINGS_TOUCHED = false
Settings.SetValue = function() SETTINGS_TOUCHED = true end
C_EditMode.SetActiveLayout = function(i) EditModeManagerFrame.layoutInfo.activeLayout = i end
C_EditMode.SaveLayouts = function(info) SAVED_LAYOUTS = info end
C_EditMode.OnLayoutAdded = function(i) EditModeManagerFrame.layoutInfo.activeLayout = i end
UI_TEST = { layout = { name = "Main", type = 1 }, bars = { [2] = true, [3] = true, [4] = false }, cvars = {} }
''')
YS.ApplyUI(YS, g.UI_TEST)
g.RunLater()
report(g.EditModeManagerFrame.layoutInfo.activeLayout == 3 and g.EDIT.selected is None,
       "Edit Mode switched through C_EditMode, not Blizzard's SelectLayout")
report(g.TOGGLES[1] is True and g.TOGGLES[2] is True and g.TOGGLES[3] is False and not g.SETTINGS_TOUCHED,
       "the bars switched through SetActionBarToggles, Settings untouched")
report(g.POPUP is None, f"no reload asked when both took ({g.POPUP})")
# the layout didn't take: the old way, and a reload
lua.execute('''EditModeManagerFrame.layoutInfo.activeLayout = 1; EDIT.selected = nil; POPUP = nil
C_EditMode.SetActiveLayout = function() end''')
YS.ApplyUI(YS, g.UI_TEST)
g.RunLater()
report(g.EDIT.selected == 3 and g.POPUP == "YIPPSETUP_RELOAD", "a layout that didn't switch: the old way, and the reload popup")
# a layout this account doesn't have: imported on our own copy of the list, made active
lua.execute('''EditModeManagerFrame.layoutInfo.activeLayout = 1; EDIT.selected = nil; EDIT.made = nil; POPUP = nil
C_EditMode.SetActiveLayout = function(i) EditModeManagerFrame.layoutInfo.activeLayout = i end
UI_NEW = { layout = { name = "Fresh", type = 1, export = "x" }, bars = {}, cvars = {} }''')
YS.ApplyUI(YS, g.UI_NEW)
report(g.SAVED_LAYOUTS is not None and g.SAVED_LAYOUTS.layouts[3].layoutName == "Fresh" and g.EDIT.made is None
       and len(g.EditModeManagerFrame.layoutInfo.layouts) == 3,
       "a new layout: saved on a copy of the list (Blizzard's own list untouched), no MakeNewLayout")
lua.execute("LATER = {}")

# Chat windows: the main's tabs, what they show, colour, transparency, size; a tab the new character
# has that the main doesn't, closed.
lua.execute(r'''
C_Timer.After = function(_, fn) fn() end
local function Chat(i, name, shown, docked)
    local f = { id = i, name = name, shown = shown, isDocked = docked, alpha = 0.25, size = 14,
        messageTypeList = { "SAY" }, channelList = {} }
    function f:GetPoint() return "BOTTOMLEFT", UIParent, "BOTTOMLEFT", 40, 60 end
    function f:GetWidth() return 400 end
    function f:GetHeight() return 180 end
    function f:RemoveAllMessageGroups() self.messageTypeList = {} end
    function f:AddMessageGroup(g) table.insert(self.messageTypeList, g) end
    function f:RemoveAllChannels() self.channelList = {} end
    function f:AddChannel(c) table.insert(self.channelList, c) end
    function f:ClearAllPoints() end
    function f:SetPoint(...) self.point = { ... } end
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:Show() self.shown = true end
    _G["ChatFrame" .. i] = f
    return f
end
NUM_CHAT_WINDOWS = 10
function ResetChats()
    for i = 1, 10 do Chat(i, i == 1 and "General" or i == 2 and "Combat Log" or "", i <= 2, i <= 2) end
end
ResetChats()
function GetChatWindowInfo(i) local f = _G["ChatFrame" .. i] return f.name, f.size, f.r or 0, f.g or 0, f.b or 0, f.alpha, f.shown, false, f.isDocked, f.noClick end
GENERAL_CHAT_DOCK = {}
function FCFDock_GetChatFrames() return {} end
function FCF_SetWindowName(f, n) f.name = n end
function FCF_SetWindowColor(f, r, g, b) f.r, f.g, f.b = r, g, b end
function FCF_SetUninteractable(f, on) f.noClick = on end
function FCF_SetWindowAlpha(f, a) f.alpha = a end
function FCF_SetChatWindowFontSize(_, f, s) f.size = s end
function FCF_SetLocked() end
function FCF_DockFrame(f) f.isDocked = true; f.shown = true end
function FCF_UnDockFrame(f) f.isDocked = false end
function FCF_SavePositionAndDimensions() end
function FCF_SelectDockFrame() end
function FCF_Close(f) f.shown = false; f.isDocked = false; f.name = "" end
function FCF_OpenNewWindow(name)
    for i = 3, 10 do local f = _G["ChatFrame" .. i] if not f.shown and not f.isDocked then f.name = name f.shown = true f.isDocked = true return f, i end end
end
-- the main: General at 20% with Say and Guild, a docked "Loot" tab, a floating "Whispers"
ChatFrame1.alpha = 0.2; ChatFrame1.messageTypeList = { "SAY", "GUILD" }
FCF_OpenNewWindow("Loot"); ChatFrame3.messageTypeList = { "LOOT", "MONEY" }; ChatFrame3.alpha = 0.5
ChatFrame3.r, ChatFrame3.g, ChatFrame3.b = 0.1, 0.3, 0.6; ChatFrame3.noClick = true
FCF_OpenNewWindow("Whispers"); ChatFrame4.isDocked = false; ChatFrame4.messageTypeList = { "WHISPER" }; ChatFrame4.size = 16
MAIN_CHAT = YR_SETUP.ScanChat()
ResetChats()
FCF_OpenNewWindow("Trade junk")       -- this character's own tab, not the main's
''')
said = YS.ApplyChat(g.MAIN_CHAT)
frames = [getattr(g, f"ChatFrame{i}") for i in range(3, 11)]
names = {f.name for f in frames if f.shown}
f1 = g.ChatFrame1
report(f1.alpha == 0.2 and list(f1.messageTypeList.values()) == ["SAY", "GUILD"], "General: the main's transparency and messages")
report(names == {"Loot", "Whispers"}, f"the main's tabs, and the new character's own tab closed: {names} ({said})")
loot = [f for f in frames if f.name == "Loot"][0]
whis = [f for f in frames if f.name == "Whispers"][0]
report(loot.alpha == 0.5 and loot.isDocked and list(loot.messageTypeList.values()) == ["LOOT", "MONEY"],
       "a docked tab: its transparency and messages")
report(abs(loot.r - 0.1) < 1e-6 and abs(loot.b - 0.6) < 1e-6, f"a tab's background colour: {loot.r}, {loot.g}, {loot.b}")
report(loot.noClick is True and not whis.noClick, "uninteractable where the main had it, and only there")
report(not whis.isDocked and whis.size == 16 and whis.w == 400 and whis.point is not None,
       "a floating window: undocked, its font size, size and position")

# A new character's first login: the main's bars are set while Headstart loads (Blizzard shows them
# at SETTINGS_LOADED), so Set up layout has no bars left to change and asks for no reload.
lua.execute('''TOGGLES = { false, false, false, false, false, false, false }
LOADED = {}
YippSetupDB.ui = YippSetupDB.ui or {}
YippSetupDB.ui.bars = { [2] = true, [3] = true, [4] = false }''')
n = YS.EarlyBars()
report(n == 2 and g.TOGGLES[1] is True and g.TOGGLES[2] is True, f"first login: the main's bars set before Blizzard shows the bars ({n} changed)")
lua.execute('''LOADED = { "Bartender4" }; TOGGLES = { false, false, false, false, false, false, false }''')
report(YS.EarlyBars() is None and g.TOGGLES[1] is False, "... not with a bar addon loaded")
lua.execute("LOADED = {}")

# Camera: out to the main's distance
lua.execute('''CAM = 3
function GetCameraZoom() return CAM end
function CameraZoomOut(d) CAM = CAM + d end
function CameraZoomIn(d) CAM = CAM - d end''')
YS.ApplyCamera(18)
report(abs(g.CAM - 18) < 0.01, f"camera out to the main's distance: {g.CAM}")
# Copy on a character still levelling, over a layout planned to 60: what it can't have yet stays saved
lua.execute('''UnitLevel = function() return 5 end
YippSetupDB.classes.PALADIN.profile = { from = "Plan", class = "PALADIN", slots = {
    [20] = { kind = "spell", name = "Hammer of Wrath", level = 44 },
    [21] = { kind = "spell", name = "Holy Light", level = 1 },
    [22] = { kind = "spell", name = "Exorcism", level = 20 } } }
MACROS = { [121] = { "Exorcism", 134400, select(3, YR_SETUP.MacroFor({ kind = "spell", name = "Exorcism", level = 20 })) } }
BAR = { [1] = { kind = "spell", id = 10329 }, [22] = { kind = "macro", id = 121 } }''')
YS.Scan(YS)
saved = g.YippSetupDB.classes.PALADIN.profile.slots
ok = saved[20] is not None and saved[20].name == "Hammer of Wrath"
report(ok, "level 5 copies over a 60 plan: Hammer of Wrath (44) keeps its slot")
report(saved[21] is None, "a spell you could have and took off the bar: gone, as you left it")
report(saved[22] is not None and saved[22].kind == "spell" and saved[22].name == "Exorcism",
       "the question-mark macro Headstart made for Exorcism is saved as the spell, not a macro of yours")
report(saved[1] is not None and saved[1].name == "Holy Light", "what's on the bars now is saved as usual")
# A spell not learned yet waits as a question-mark macro. (For a while it had the spell's own icon: those are put back.)
lua.execute("""HeadstartNS.PlannerSpells = { PALADIN = { ["Exorcism"] = { 879, 135903 }, ["Holy Light"] = { 635, 135920 } } }
    function EditMacro(i, name, icon, body) MACROS[i][2] = icon end
    MACROS = { [121] = { "Exorcism", 135903, "#showtooltip Exorcism\\n/cast Exorcism" }, [122] = { "Mine", 135903, "/say hi" },
        [123] = { "My own", 135903, "#showtooltip Exorcism\\n/cast Exorcism" } }""")
icon = lua.eval('(select(2, YR_SETUP.MacroFor({ kind = "spell", name = "Exorcism", level = 20 })))')
report(icon == 134400, f"a spell you haven't learned: its macro has the question mark ({icon})")
n = lua.eval("YR_SETUP.PlaceholderIcons()")
report(n == 1 and g.MACROS[121][2] == 134400 and g.MACROS[122][2] == 135903 and g.MACROS[123][2] == 135903,
       f"a waiting macro that was given the spell's icon gets its question mark back; macros of your own are left alone ({n})")
# A macro Headstart made for a spell is that spell wherever the bars are read - also with no saved layout to say so
lua.execute("""Fresh()
    KEPT_PROFILE2 = YippSetupDB.classes.PALADIN.profile
    YippSetupDB.classes.PALADIN.profile = nil
    MACROS = { [121] = { YR_SETUP.MacroFor({ kind = "spell", name = "Exorcism", level = 20 }) }, [122] = { "Exo", 134400, "#showtooltip Exorcism\\n/cast Exorcism" },
        [123] = { "Mine", 134400, "/say hi" } }
    BAR = { [5] = { kind = "macro", id = 121 }, [6] = { kind = "macro", id = 122 }, [7] = { kind = "macro", id = 123 } }""")
now, _ = YS.ReadBars()
report(now[5] is not None and now[5].kind == "spell" and now[5].name == "Exorcism" and now[5].level == 20,
       "a question-mark macro Headstart made, with no saved layout: read as its spell")
report(now[6].kind == "macro" and now[7].kind == "macro", "a macro of your own for the same spell (another name), and any other macro: macros")
lua.execute("""YippSetupDB.classes.PALADIN.profile = { class = "PALADIN", planned = true, slots = {
    [5] = { kind = "macro", name = MACROS[121][1], icon = 134400, body = MACROS[121][3] }, [7] = { kind = "macro", name = "Mine", icon = 134400, body = "/say hi" } } }""")
n = YS.RepairLayouts()
slots = YS.Profile(YS).slots
report(n == 1 and slots[5].kind == "spell" and slots[5].name == "Exorcism" and slots[7].kind == "macro",
       f"a plan saved with such a macro in it is put right: the spell, and your own macro left ({n})")
lua.execute("YippSetupDB.classes.PALADIN.profile = KEPT_PROFILE2")
# Copy this layout over a saved one asks first - a plan, another character's, or this one's own
lua.execute("""ASKED = nil StaticPopup_Show = function(w, text) ASKED = { which = w, text = text } end
    SCANNED_BEFORE = YippSetupDB.classes.PALADIN.profile.scanned""")
YS.Copy(YS)
report(g.ASKED is not None and g.ASKED.which == "YIPPSETUP_OVERWRITE" and "buttons" in g.ASKED.text
       and g.YippSetupDB.classes.PALADIN.profile.scanned == g.SCANNED_BEFORE,
       f"Copy this layout with a layout saved for the class: asked first, nothing replaced yet ({g.ASKED and g.ASKED.text})")
lua.execute("KEPT_PROFILE3 = YippSetupDB.classes.PALADIN.profile YippSetupDB.classes.PALADIN.profile = nil ASKED = nil")
YS.Copy(YS)
report(g.ASKED is None and g.YippSetupDB.classes.PALADIN.profile is not None, "with none saved: copied at once")
lua.execute("YippSetupDB.classes.PALADIN.profile = KEPT_PROFILE3")
# A spell a talent gives never waits as a question mark; how far ahead the others do is the class's choice
lua.execute("""KEPT_PROFILE4 = YippSetupDB.classes.PALADIN.profile
    YippSetupDB.classes.PALADIN.profile = { class = "PALADIN", from = "Main-Realm", slots = {
        [1] = { kind = "spell", name = "Holy Light", level = 1 }, [4] = { kind = "spell", name = "Seal of the Crusader", level = 6 } } }
    Fresh() YippSetupCharDB.layout = nil""")
YS.Apply(YS, None, None, SURE)
had = g.BAR[4] is not None and g.BAR[4].kind == "macro"
lua.execute("Fresh() YippSetupCharDB.layout = nil YippSetupCharDB.placed = nil YR_SETUP.TALENTS = { PALADIN = { ['Seal of the Crusader'] = 30 } }")
YS.Apply(YS, None, None, SURE)
report(had and g.BAR[4] is None and YS.IsTalent("Seal of the Crusader") and not YS.IsTalent("Holy Light"),
       "a spell a talent gives: no question mark for it, its button empty until you learn it")
lua.execute("KNOWN[21082] = true YippSetupCharDB.applied = YippSetupCharDB.applied or time()")
YS.Upgrade(YS)
report(g.BAR[4] is not None and g.BAR[4].kind == "spell", "learned: it goes into its button")
lua.execute("YR_SETUP.TALENTS = nil Fresh() YippSetupCharDB.layout = nil YR_SETUP:Options().ahead = 0")
YS.Apply(YS, None, None, SURE)
report(g.BAR[4] is None and YS.Ahead(YS.Options(YS)) == 0, "levels ahead set to 0: no question mark for a spell you can't train yet")
lua.execute("YR_SETUP:Options().ahead = nil")
report(YS.Ahead(YS.Options(YS)) == 10, "never set: ten levels ahead")
lua.execute("YippSetupDB.classes.PALADIN.profile = KEPT_PROFILE4")
# Choices changed since the layout was last put on this character: said so until it is applied again
lua.execute("Fresh() YippSetupCharDB.choices = nil")
YS.Apply(YS, None, None, SURE)
lua.execute("YippSetupCharDB.applied = YippSetupCharDB.applied or time()")
report(YS.ChoicesPending() is False, "just applied: the choices are on the bars")
lua.execute("YR_SETUP:Options().spellButtons = 'spells'")
report(YS.ChoicesPending() is True, "question marks changed to Only spells: not on the bars yet")
lua.execute("YR_SETUP:Options().spellButtons = 'placeholder'")
report(YS.ChoicesPending() is False, "changed back: nothing pending")
lua.execute("YR_SETUP:Options().ahead = 3")
report(YS.ChoicesPending() is True, "the levels ahead changed: pending")
YS.Apply(YS, None, None, SURE)
report(YS.ChoicesPending() is False, "applied again: up to date")
lua.execute("YR_SETUP:Options().ahead = nil YippSetupCharDB.choices = nil")
report(YS.ChoicesPending() is False and g.YippSetupCharDB.choices is not None, "a character set up before this was kept: taken as up to date, from now")
# RestedXP's windows: their places and sizes, from its own profile into the new character's
lua.execute("""SAVES, LOADS = 0, 0
    RXP = RXP or {}
    RXP.settings = { profile = { framePositions = { RXPFrame = { { "LEFT", nil, "LEFT", 40, 120 } }, arrowFrame = { { "TOP", "UIParent", "TOP", 0, -80 } },
        activeItemFrame = { { "CENTER", "UIParent", "CENTER", 200, 0 } } }, frameSizes = { RXPFrame = { 300, 400 } } },
        SaveFramePositions = function() SAVES = SAVES + 1 end, LoadFramePositions = function() LOADS = LOADS + 1 end }""")
saved = YS.ScanRXP()
report(saved is not None and saved.positions.RXPFrame[1][4] == 40 and saved.sizes.RXPFrame[1] == 300 and g.SAVES == 1,
       "RestedXP's windows are read from its profile, as they are this moment")
lua.execute("""RXP.settings.profile = { framePositions = { RXPFrame = { { "LEFT", nil, "LEFT", 0, 35 } }, other = { { "TOP" } } } }""")
said = YS.ApplyRXP(saved)
prof = lua.eval("RXP.settings.profile")
report(said == "3 placed" and prof.framePositions.RXPFrame[1][4] == 40 and prof.framePositions.arrowFrame[1][5] == -80
       and prof.frameSizes.RXPFrame[2] == 400 and prof.framePositions.other is not None and g.LOADS == 1,
       f"and put into this character's: three windows placed, RestedXP told to move them, nothing else of its settings touched ({said})")
saved.positions.RXPFrame[1][4] = 999
report(prof.framePositions.RXPFrame[1][4] == 40, "(a copy: the saved one and RestedXP's own don't share a table)")
report(YS.ApplyRXP(None) == "none saved", "nothing saved: said so")
# RestedXP's look goes along (it keeps its settings per character): theme, scales, font - not how a character plays
lua.execute("""RXP.settings.profile = { activeTheme = "Headstart", windowScale = 1.3, guideFontSize = 11, hardcore = true,
    framePositions = { RXPFrame = { { "LEFT", nil, "LEFT", 5, 5 } } } }""")
look = YS.ScanRXP()
report(look.look.activeTheme == "Headstart" and look.look.windowScale == 1.3 and look.look.hardcore is None,
       "RestedXP's look is read: its theme and scales, nothing a character plays by")
lua.execute("""THEMED = 0
    RXP.LoadActiveTheme = function() THEMED = THEMED + 1 end
    RXP.settings.profile = { activeTheme = "RXP Blue", windowScale = 1, hardcore = false, framePositions = {} }""")
said = YS.ApplyRXP(look)
prof = lua.eval("RXP.settings.profile")
report(said == "1 placed, look copied" and prof.activeTheme == "Headstart" and prof.windowScale == 1.3 and prof.hardcore is False
       and g.THEMED == 1, f"and put on: the theme and scale are this character's now, drawn at once ({said}, {g.THEMED})")
report(YS.UIStale(lua.eval("{}")) is True and YS.UIStale(lua.eval("{ v = YR_SETUP.UI_VERSION }")) is False,
       "an interface saved by an older Headstart is known as one")
lua.execute("KEPT_RXP = RXP.settings RXP.settings = nil")
report(YS.ScanRXP() is None and YS.ApplyRXP(saved) == "RestedXP not loaded", "RestedXP without its settings: nothing read, and said so")
lua.execute("RXP.settings = KEPT_RXP")
# Setting up again takes Headstart's own waiting macros off - and no macro of yours that only looks like one
lua.execute("""KEPT_PROFILE5 = YippSetupDB.classes.PALADIN.profile
    YippSetupDB.classes.PALADIN.profile = { class = "PALADIN", from = "Main-Realm", slots = {
        [1] = { kind = "spell", name = "Holy Light", level = 1 }, [4] = { kind = "spell", name = "Seal of the Crusader", level = 6 } } }
    Fresh() YippSetupCharDB.layout = nil YippSetupCharDB.placed = nil KNOWN[21082] = nil""")
YS.Apply(YS, None, None, SURE)
lua.execute("""YippSetupCharDB.applied = YippSetupCharDB.applied or time()
    CreateMacro("Crusader!", 134400, "#showtooltip Seal of the Crusader\\n/cast !Seal of the Crusader", true)
    CreateMacro("Mine", 134400, "#showtooltip Holy Light\\n/cast [@mouseover,help][] Holy Light", true)
    YR_SETUP:Options().spellButtons = "spells" """)
YS.Apply(YS, None, None, lua.eval("{ sure = true, barsOnly = true }"))
names = sorted(g.MACROS[k][1] for k in g.MACROS)
report("Crusader" not in names and "Crusader!" in names and "Mine" in names and g.BAR[4] is None,
       f"changed to Only spells and applied: the question mark is gone, macros of your own that begin the same way stay ({names})")
lua.execute("YR_SETUP:Options().spellButtons = nil YippSetupDB.classes.PALADIN.profile = KEPT_PROFILE5")
# Question marks your choices no longer ask for come off without setting the whole character up again
lua.execute("""KEPT_PROFILE6 = YippSetupDB.classes.PALADIN.profile
    YippSetupDB.classes.PALADIN.profile = { class = "PALADIN", from = "Main-Realm", slots = {
        [1] = { kind = "spell", name = "Holy Light", level = 1 }, [4] = { kind = "spell", name = "Seal of the Crusader", level = 6 } } }
    Fresh() YippSetupCharDB.layout = nil YippSetupCharDB.placed = nil KNOWN[21082] = nil YR_SETUP:Options().spellButtons = "placeholder" """)
YS.Apply(YS, None, None, SURE)
lua.execute("""local last = 120 while MACROS[last + 1] do last = last + 1 end
    MACROS[last + 1] = { "Mine", 134400, "/say hi" } BAR[9] = { kind = "macro", id = last + 1 }""")
had = g.BAR[4] is not None and g.BAR[4].kind == "macro"
report(had and YS.TidyPlaceholders() == 0 and g.BAR[4].kind == "macro", "question marks wanted: tidying takes nothing off")
lua.execute("YR_SETUP:Options().spellButtons = 'spells'")
n = YS.TidyPlaceholders()
names = sorted(g.MACROS[k][1] for k in g.MACROS)
report(n == 1 and g.BAR[4] is None and "Crusader" not in names and "Mine" in names and g.BAR[9] is not None and g.BAR[1] is not None,
       f"changed to Only spells: the question mark comes off its button and is deleted, your own macro and your spells stay ({n}, {names})")
report(YS.TidyPlaceholders() == 0, "and again: nothing more to take")
lua.execute("COMBAT = true")
report(YS.TidyPlaceholders() == 0, "in a fight: nothing is touched")
lua.execute("COMBAT = false YR_SETUP:Options().spellButtons = nil YippSetupDB.classes.PALADIN.profile = KEPT_PROFILE6")
# Bar layouts: more than one for a class, one click between them, and your two specs
lua.execute("""KEPT_PROFILE7 = YippSetupDB.classes.PALADIN.profile
    YippSetupDB.classes.PALADIN.layouts = nil YippSetupDB.classes.PALADIN.profileName = nil YippSetupDB.specAsk = nil
    YippSetupDB.classes.PALADIN.profile = { class = "PALADIN", from = "Main-Realm", slots = {
        [1] = { kind = "spell", name = "Holy Light", level = 1 }, [2] = { kind = "spell", name = "Stoneform", level = 1, racial = true } } }
    Fresh() YippSetupCharDB.layout = nil YippSetupCharDB.placed = nil YippSetupCharDB.layoutName = nil YippSetupCharDB.specLayouts = nil
    MYSPEC = 1 C_SpecializationInfo = { GetActiveSpecGroup = function() return MYSPEC end }
    YR_SETUP:Options().mouseover = "" """)
YS.Apply(YS, None, None, SURE)
lua.execute("YippSetupCharDB.applied = YippSetupCharDB.applied or time()")
names = lambda: list(YS.LayoutNames().values())
report(names() == ["Main"] and YS.LayoutName() == "Main", "a class starts with one bar layout, Main")
New = lua.eval("function(n) local ok, why = YR_SETUP.LayoutNew(n) return { ok = ok, why = why } end")
Switch = lua.eval("function(n) local ok, why = YR_SETUP.LayoutSwitch(n) return { ok = ok, why = why } end")
r = New("Tank")
report(r.ok is True and names() == ["Main", "Tank"] and YS.LayoutName() == "Tank" and g.BAR[1] is not None
       and YS.Profile(YS).slots[1].name == "Holy Light", "a new one: your bars as they are, under a name, and you are on it")
report(New("tank").ok is False and New("  ").ok is False, "a name taken (whatever its case) or none: not made")
# changed by hand on Tank, then back to Main: Tank remembers, Main is put on
lua.execute("BAR[2] = nil BAR[3] = { kind = 'spell', id = 20594 }")
r = Switch("Main")
report(r.ok is True and YS.LayoutName() == "Main" and g.BAR[2] is not None and g.BAR[2].id == 20594 and g.BAR[3] is None,
       "back to Main: its buttons are on the bars again")
tank = g.YippSetupDB.classes.PALADIN.layouts.Tank.slots
report(tank[3] is not None and tank[3].name == "Stoneform" and tank[2] is None, "and Tank was saved as the bars were when you left it")
lua.execute("BAR[40] = { kind = 'companion', id = 7 }")
r = Switch("Tank")
report(r.ok is True and g.BAR[3] is not None and g.BAR[3].id == 20594 and g.BAR[2] is None and g.BAR[40] is not None,
       "to Tank again: its buttons, and a button no layout holds (a mount) is left where it is")
report(Switch("Tank").ok is False and Switch("Nope").ok is False, "the one you're on, or one there isn't: nothing happens")
lua.execute("COMBAT = true")
report(Switch("Main").ok is False and YS.LayoutName() == "Tank", "in a fight: not switched")
lua.execute("COMBAT = false")
# two specs: the layout a spec was on is remembered, and asked about when you come back to it
lua.execute("ASKED = nil StaticPopup_Show = function(w, a, b, data) ASKED = { which = w, to = a, from = b, data = data } end")
lua.execute("MYSPEC = 2")
YS.OnSpecChanged(2, 1)
report(g.ASKED is None and g.YippSetupCharDB.specLayouts[1] == "Tank", "the other spec, which has had no layout yet: nothing asked; Tank is noted as the first spec's")
Switch("Main")
report(g.YippSetupCharDB.specLayouts[2] == "Main", "switched by hand in the second spec: Main is that spec's")
lua.execute("MYSPEC = 1")
YS.OnSpecChanged(1, 2)
report(g.ASKED is not None and g.ASKED.which == "YIPPSETUP_SPEC" and g.ASKED.to == "Tank" and g.ASKED.data == "Tank" and YS.LayoutName() == "Main",
       "back to the first spec: asked whether to switch to Tank, nothing switched yet")
lua.execute("StaticPopupDialogs.YIPPSETUP_SPEC.OnAccept(nil, ASKED.data)")
report(YS.LayoutName() == "Tank", "Switch: on Tank")
lua.execute("YippSetupDB.specAsk = 'auto' ASKED = nil MYSPEC = 2")
YS.OnSpecChanged(2, 1)
report(g.ASKED is None and YS.LayoutName() == "Main", "set to switch by itself: switched, not asked")
lua.execute("YippSetupDB.specAsk = 'off' MYSPEC = 1")
YS.OnSpecChanged(1, 2)
report(g.ASKED is None and YS.LayoutName() == "Main", "turned off: neither")
lua.execute("YippSetupDB.specAsk = nil StaticPopupDialogs.YIPPSETUP_SPEC.OnAlt()")
report(g.YippSetupDB.specAsk == "off", "'Don't ask again' turns it off")
# a profile's own interface: kept as you leave it, put back when you come to it - only where turned on
lua.execute("""YippSetupDB.specAsk = nil SCANS, PUT = 0, {}
    REAL_SCAN, REAL_PUT = YR_SETUP.ScanProfileUI, YR_SETUP.ApplyProfileUI
    YR_SETUP.ScanProfileUI = function() SCANS = SCANS + 1 return { layout = { name = "Screen " .. SCANS } } end
    YR_SETUP.ApplyProfileUI = function(ui) PUT[#PUT + 1] = ui.layout.name return "Edit Mode '" .. ui.layout.name .. "'" end""")
on_now = YS.LayoutName()
other = "Tank" if on_now == "Main" else "Main"
report(YS.ProfileOwnUI() is False, "a profile has no interface of its own until you say so")
Switch(other)
Switch(on_now)
report(g.SCANS == 0 and len(g.PUT) == 0, "switching between profiles without one: your interface isn't read or touched")
YS.SetProfileOwnUI(True)
report(YS.ProfileOwnUI() is True and g.SCANS == 1 and YS.Profile(YS).ui.layout.name == "Screen 1", "turned on: the interface as it is now is this profile's")
Switch(other)
report(g.SCANS == 2 and len(g.PUT) == 0, "leaving it: its interface is saved as you leave it; the profile you go to has none, so nothing is put on")
Switch(on_now)
report(list(g.PUT.values()) == ["Screen 2"] and YS.ProfileOwnUI() is True, "coming back: its interface is put on, as you left it")
YS.SetProfileOwnUI(False)
report(YS.ProfileOwnUI() is False and YS.Profile(YS).ui is None, "turned off: it holds your bars only again")
lua.execute("YR_SETUP.ScanProfileUI, YR_SETUP.ApplyProfileUI = REAL_SCAN, REAL_PUT YippSetupDB.specAsk = 'off' YippSetupCharDB.specLayouts[1] = 'Tank'")
# rename and delete
Rename = lua.eval("function(a, b) local ok, why = YR_SETUP.LayoutRename(a, b) return ok end")
report(Rename("Tank", "Prot") is True and names() == ["Main", "Prot"] and g.YippSetupCharDB.specLayouts[1] == "Prot"
       and Rename("Main", "Holy") is True and names() == ["Holy", "Prot"] and YS.LayoutName() == "Holy" and Rename("Prot", "Holy") is False,
       "renamed: the class's first too; not to a name that is taken")
Switch("Prot")
Delete = lua.eval("function(n) local ok, why = YR_SETUP.LayoutDelete(n) return ok end")
report(Delete("Holy") is False and Delete("Prot") is True and names() == ["Holy"] and YS.LayoutName() == "Holy" and g.BAR[3] is not None,
       "deleted: never the class's first; a character on the deleted one is on the first again, its bars as they are")
YS.OnSpecChanged(2, 1)
report(g.ASKED is None, "one layout left: a spec change asks nothing")
lua.execute("YR_SETUP:Options().mouseover = 'Purify'")
lua.execute("YippSetupDB.specAsk = nil YippSetupDB.classes.PALADIN.layouts = nil YippSetupDB.classes.PALADIN.profileName = nil YippSetupCharDB.layoutName = nil YippSetupCharDB.specLayouts = nil BAR[40] = nil YippSetupDB.classes.PALADIN.profile = KEPT_PROFILE7")
# A profile remembers your bars as you change them
lua.execute("""KEPT_PROFILE8 = YippSetupDB.classes.PALADIN.profile
    YippSetupDB.classes.PALADIN.profile = { class = "PALADIN", from = "Main-Realm", planned = true, slots = {
        [1] = { kind = "spell", name = "Holy Light", level = 1 }, [2] = { kind = "spell", name = "Stoneform", level = 1, racial = true },
        [30] = { kind = "spell", name = "Exorcism", level = 20 } } }
    Fresh() YippSetupCharDB.layout = nil YippSetupCharDB.placed = nil YippSetupCharDB.layoutName = nil YR_SETUP:Options().mouseover = ""
    YippSetupDB.remember = nil""")
YS.Apply(YS, None, None, SURE)
lua.execute("YippSetupCharDB.applied = YippSetupCharDB.applied or time() BAR[2] = nil BAR[5] = { kind = 'spell', id = 20594 } BAR[6] = { kind = 'item', id = 6948 }")
YS.RememberNow()
slots = YS.Profile(YS).slots
report(slots[5] is not None and slots[5].name == "Stoneform" and slots[2] is None and slots[6] is not None and slots[6].kind == "item",
       "a spell dragged to another button, an item put on one: in the profile")
report(slots[30] is not None and slots[30].name == "Exorcism" and slots[1].name == "Holy Light",
       "a spell planned for a later level keeps its button, and what you didn't touch is as it was")
report(g.YippSetupCharDB.layout[5] is not None, "and where spells learned later go follows it")
lua.execute("COMBAT = true BAR[7] = { kind = 'spell', id = 635 }")
YS.RememberNow()
report(YS.Profile(YS).slots[7] is None, "in a fight: not read")
lua.execute("COMBAT = false YippSetupDB.remember = false")
YS.RememberNow()
report(YS.Profile(YS).slots[7] is None and YS.Remembers() is False, "turned off: the profile only changes when you plan it or copy into it")
lua.execute("YippSetupDB.remember = nil YippSetupCharDB.applied = nil")
YS.RememberNow()
report(YS.Profile(YS).slots[7] is None, "a character that isn't on the profile: its bars are nobody's profile, and aren't written over one")
lua.execute("YR_SETUP:Options().mouseover = 'Purify' YippSetupDB.remember = false YippSetupDB.classes.PALADIN.profile = KEPT_PROFILE8")
# An item you put on a button yourself survives Apply, with "Items" off; and what you dragged a moment ago is saved first
lua.execute("""KEPT_PROFILE9 = YippSetupDB.classes.PALADIN.profile
    YippSetupDB.classes.PALADIN.profile = { class = "PALADIN", from = "Main-Realm", slots = {
        [1] = { kind = "spell", name = "Holy Light", level = 1 }, [9] = { kind = "item", id = 4444, name = "A main's potion" } } }
    Fresh() YippSetupCharDB.layout = nil YippSetupCharDB.placed = nil YR_SETUP:Options().mouseover = "" YR_SETUP:Options().items = false
    COUNTS = { [6948] = 1 } C_Item.GetItemCount = function(id) return COUNTS[id] or 0 end
    YippSetupDB.remember = nil""")
YS.Apply(YS, None, None, SURE)
report(g.BAR[9] is None and g.BAR[1] is not None, "Items off: an item this character hasn't got stays off its bars")
lua.execute("YippSetupCharDB.applied = YippSetupCharDB.applied or time() BAR[12] = { kind = 'item', id = 6948 } ASKED = nil StaticPopup_Show = function(w) ASKED = w end")
YS.Apply(YS)                # pressed straight after dragging the hearthstone out: asks (set up before) - and has saved it
report(g.ASKED == "YIPPSETUP_AGAIN" and YS.Profile(YS).slots[12] is not None and YS.Profile(YS).slots[12].id == 6948,
       "Apply pressed right after a button was dragged out: the bars are saved into the profile first")
report(YS.Profile(YS).slots[9] is not None, "and the main's potion this character hasn't got keeps its button in the profile")
YS.Apply(YS, None, None, lua.eval("{ sure = true, barsOnly = true }"))
report(g.BAR[12] is not None and g.BAR[12].kind == "item" and g.BAR[12].id == 6948 and g.BAR[9] is None,
       "applied: the hearthstone you carry is back on its button, with Items off")
lua.execute("YR_SETUP:Options().mouseover = 'Purify' YR_SETUP:Options().items = nil YippSetupDB.remember = false YippSetupDB.classes.PALADIN.profile = KEPT_PROFILE9")
# "A button changed" from the game for a button that holds what it held: the bars aren't read again
lua.execute("""YippSetupDB.remember = nil COMBAT = false
    SCANS = 0 local scan = YR_SETUP.ScanBars YR_SETUP.ScanBars = function(...) SCANS = SCANS + 1 return scan(...) end""")
YS.RememberNow()
first = g.SCANS
YS.RememberNow()
YS.RememberNow()
report(first <= 1 and g.SCANS == first, f"asked three times with no button changed: the bars are read once at most ({first}, {g.SCANS})")
lua.execute("BAR[40] = { kind = 'item', id = 6948 }")
YS.RememberNow()
report(g.SCANS == first + 1, f"a button really changed: read again ({g.SCANS})")
lua.execute("BAR[40] = nil YR_SETUP.RememberNow() YippSetupDB.remember = false")
report(YS.ProfessionIDs("Accurate Scope") == 3979 and 2580 in list(YS.ProfessionIDs("Find Minerals").values())
       and 2018 in list(YS.ProfessionIDs("Blacksmithing").values())
       and YS.ProfessionIDs("Holy Light") is None and YS.ProfessionIDs("Find Min") is None,
       "profession spells are found by name in the one text: one ID, several, and none for what isn't one")
# how a screen reads: the same whatever order a chat window lists its channels in, and whatever size
# RestedXP has made its item and target windows at this step; not the same when a setting differs
sig = lambda t: lua.eval("YR_SETUP.UISig(" + t + ")")
base = '{ cvars = { a = "1" }, chat = { { id = 1, channels = { "General", "Trade" } } }, rxp = { positions = { F = { { "LEFT", 4 } } }, sizes = { F = { 200, 80 } } }, camera = 12 }'
report(sig(base) == sig(base.replace('"General", "Trade"', '"Trade", "General"').replace("200, 80", "200, 140").replace("camera = 12", "camera = 30")),
       "a screen reads the same with its channels in another order, RestedXP's windows another size, the camera elsewhere")
report(sig(base) != sig(base.replace('a = "1"', 'a = "0"')) and sig(base) != sig(base.replace('"LEFT", 4', '"LEFT", 9'))
       and sig(base) != sig(base.replace('"General", "Trade"', '"General"')),
       "and differently with a setting changed, a RestedXP window moved, or a channel gone")
# Interfaces have names, and a character is on one. Saved on another character: this one doesn't save over it.
lua.execute("""KEPT_UI = { ui = YippSetupDB.ui, from = YippSetupDB.uiFrom, at = YippSetupDB.uiScanned, prev = YippSetupDB.uiPrev,
        iface = YippSetupCharDB.iface }
    OTHER_UI = { cvars = {}, bars = {} }
    YippSetupDB.ui, YippSetupDB.uiFrom, YippSetupDB.uiScanned, YippSetupDB.uiFollow = OTHER_UI, "Healer-Realm", 1, nil
    YippSetupCharDB.iface = nil
    NOW_T = 1000
    function time() NOW_T = NOW_T + 10 return NOW_T end
    COMBAT = false""")
me = YS.PlayerKey()
report(YS.UISource() == "Healer-Realm" and YS.UIName() == "Main" and YS.UIOn() is False and YS.FollowUI() is False
       and lua.eval("YippSetupDB.ui == OTHER_UI"),
       "an interface saved on another character, never put on here: this character isn't on it and doesn't change it")
YS.Scan(YS)
report(lua.eval("YippSetupDB.ui == OTHER_UI") and lua.eval("YippSetupDB.uiFrom") == "Healer-Realm",
       "saving this character's bars leaves the interface alone (it used to replace it)")
lua.execute("ASKED = nil StaticPopup_Show = function(w, a, b) ASKED = { which = w, text = tostring(a) .. ' / ' .. tostring(b) } return ASKED end")
YS.SaveInterface(YS)
report(lua.eval("YippSetupDB.ui == OTHER_UI") and g.ASKED is not None and "Healer-Realm" in str(g.ASKED.text),
       f"Save interface over one last saved elsewhere: asks first, nothing changed yet ({g.ASKED and g.ASKED.text})")
YS.SaveInterface(YS, None, True)
report(lua.eval("YippSetupDB.ui ~= OTHER_UI") and lua.eval("YippSetupDB.uiFrom") == me and YS.UIOn() is True
       and lua.eval("YippSetupDB.uiPrev.ui == OTHER_UI") and YS.UIBehind() is False,
       "answered: saved from this character, which is on it now, and the one before is kept")
lua.execute("MARK_UI = YippSetupDB.ui")
report(YS.FollowUI() is False and lua.eval("YippSetupDB.ui == MARK_UI"), "nothing changed on screen since: not saved again (no one is asked for nothing)")
lua.execute("CVARS_LIVE = CVARS_LIVE or {} local get = C_CVar.GetCVar C_CVar.GetCVar = function(n) if n == 'autoLootDefault' then return 'changed' end return get(n) end")
report(YS.FollowUI() is True and lua.eval("YippSetupDB.ui ~= MARK_UI") and lua.eval("YippSetupDB.uiFrom") == me and YS.UIBehind() is False,
       "a setting changed on this character: saved into the interface quietly")
lua.execute("MARK_UI = YippSetupDB.ui YippSetupDB.uiFollow = false local get = C_CVar.GetCVar C_CVar.GetCVar = function(n) if n == 'autoLootDefault' then return 'again' end return get(n) end")
report(YS.FollowUI() is False and lua.eval("YippSetupDB.ui == MARK_UI") and YS.UIFollows() is False, "turned off: it isn't")
lua.execute("YippSetupDB.uiFollow = nil COMBAT = true")
report(YS.FollowUI() is False and lua.eval("YippSetupDB.ui == MARK_UI"), "nor in a fight")
# saved on another character since: this one is behind, saves nothing over it, and the window asks
lua.execute("""COMBAT = false
    ELSE_UI = { cvars = { autoLootDefault = "1" }, bars = {}, v = YR_SETUP.UI_VERSION }
    YippSetupDB.ui, YippSetupDB.uiFrom, YippSetupDB.uiScanned = ELSE_UI, "Moray-Realm", time()""")
behind = lua.eval("{ YR_SETUP.UIBehind() }")
report(behind[1] is True and behind[2] == "Moray-Realm" and YS.FollowUI() is False and lua.eval("YippSetupDB.ui == ELSE_UI"),
       "the interface saved on another character since: this one is behind, and logging out saves nothing over it")
w = g.YippSetupFrame
w.Hide(w)
events = g.FRAMES[2]
lua.execute("AFTER_KEEP = {} local after = C_Timer.After C_Timer.After = function(t, fn) AFTER_KEEP[#AFTER_KEEP + 1] = fn end")
YS.Toggle(YS)
report(w.IsShown(w) and w.update.IsShown(w.update) and w.keep.IsShown(w.keep) and not w.both.IsShown(w.both)
       and not w.setup.IsShown(w.setup) and "Moray-Realm" in w.ui.GetText(w.ui) and "Main" in w.ui.GetText(w.ui),
       f"the window asks: changed on the other character, Update or keep this one's ({w.ui.GetText(w.ui)})")
w.update._OnClick(w.update)
report(lua.eval("YippSetupCharDB.iface.fresh") is True and YS.FollowUI() is False,
       "just put on: nothing of this character's is saved until its screen has been looked at once after the reload")
report(YS.UIBehind() is False and not w.IsShown(w) and lua.eval("YippSetupDB.ui == ELSE_UI") and lua.eval("YippSetupCharDB.iface.sig") is None,
       "Update: the changed interface is put on, this character has that save, and the saved one is untouched")
YS.UISettle()
report(lua.eval("YippSetupCharDB.iface.sig") is not None and lua.eval("YippSetupCharDB.iface.fresh") is None and lua.eval("YippSetupDB.ui == ELSE_UI") and YS.FollowUI() is False,
       "once it has settled, how the screen reads here is noted - and nothing is saved for that")
lua.execute("YippSetupDB.uiFrom, YippSetupDB.uiScanned = 'Moray-Realm', time()")
YS.Toggle(YS)
w.keep._OnClick(w.keep)
report(YS.UIBehind() is False and lua.eval("YippSetupDB.ui ~= ELSE_UI") and lua.eval("YippSetupDB.uiFrom") == me and not w.IsShown(w),
       "Keep this character's: saved over the change, from here")
# a second interface, by name
YS.SaveInterface(YS, " Healer ")
report(list(YS.UINames().values()) == ["Main", "Healer"] and YS.UIName() == "Healer" and lua.eval("YippSetupDB.uis.Healer.from") == me
       and lua.eval("YippSetupDB.ui ~= YippSetupDB.uis.Healer.ui"), f"Save as Healer: a second interface, and this character is on it ({list(YS.UINames().values())})")
report(YS.UISetDefault("Healer") is True and YS.UIDefault() == "Healer" and list(YS.UINames().values()) == ["Healer", "Main"]
       and lua.eval("YippSetupDB.uis.Main ~= nil and YippSetupDB.uis.Healer == nil") and YS.UIName() == "Healer" and YS.UIOn() is True,
       "new characters get Healer now: it is the one an older Headstart reads, and Main is kept beside it")
ok, why = YS.UIRename("Healer", "Main")
report(ok is False and "already" in why, f"a name that is taken isn't given twice ({why})")
report(YS.UIRename("Healer", "Heals") is True and YS.UIName() == "Heals" and YS.UIDefault() == "Heals", "renamed: this character is still on it")
lua.execute("YippSetupCharDB.iface.name = 'Healer'")
report(YS.UIName() == "Heals", "a character that was on it under the old name finds it again")
ok, why = YS.UIDelete("Heals")
report(ok is False and YS.UIDelete("Main") is True and list(YS.UINames().values()) == ["Heals"],
       f"the one new characters get can't be deleted; another can ({why})")
report(YS.UIPick("Nope")[0] is False and YS.UIPick("Heals") is True, "only a saved interface can be picked")
lua.execute("""C_Timer.After = function(t, fn) fn() end
    YippSetupDB.ui, YippSetupDB.uiFrom, YippSetupDB.uiScanned, YippSetupDB.uiPrev = KEPT_UI.ui, KEPT_UI.from, KEPT_UI.at, KEPT_UI.prev
    YippSetupDB.uis, YippSetupDB.uiName, YippSetupDB.uiRenamed, YippSetupCharDB.iface = nil, nil, nil, KEPT_UI.iface""")

# The Personal Resource Display's switch is the class's, not the account's.
lua.execute("""KEPT_CLASSES, KEPT_CLASS = YippSetupDB.classes, ME.class
    CVARS.nameplateShowSelf = "1"; ME.class = "ROGUE"; YippSetupDB.classes = {}""")
ui = YS.ScanUI(YS)
report(ui.cvars.nameplateShowSelf is None, "the Personal Resource Display's switch is not in the account's interface")
YS.ClassUINoted()
report(YS.FollowClassUI() is False and YS.ClassUI() is None, "a character that changed nothing saves nothing for its class")
lua.execute('CVARS.nameplateShowSelf = "0"')
report(YS.FollowClassUI() is True and YS.ClassUI().nameplateShowSelf == "0", "turned off on a rogue: saved for rogues")
lua.execute('CVARS.nameplateShowSelf = "1"')
YS.SaveClassUI()
report(YS.ClassUI().nameplateShowSelf == "1", "Save interface saves the class's switch as this character has it")
lua.execute('ME.class = "PALADIN"; CVARS.nameplateShowSelf = "0"')
YS.ClassUINoted()
YS.ApplyUI(YS, lua.eval('{ cvars = { nameplateShowSelf = "1" }, bars = {} }'), YS.Options(YS))
report(g.CVARS.nameplateShowSelf == "0", "a paladin doesn't get the rogues' switch (nor one from an account save)")
lua.execute('ME.class = "ROGUE"')
YS.ApplyUI(YS, lua.eval('{ cvars = {}, bars = {} }'), YS.Options(YS))
report(g.CVARS.nameplateShowSelf == "1", "a new rogue gets it on with Apply interface")
report(YS.FollowClassUI() is False, "being put on is not a change by the player")
lua.execute("YippSetupDB.classes, ME.class, CVARS.nameplateShowSelf = KEPT_CLASSES, KEPT_CLASS, nil")

# ---------------------------------------------------------------------------
# What a character with a setup of its own could lose (the sweep of 2026-10-13)
# ---------------------------------------------------------------------------
# a rank written into a macro of your own stays where this character knows that very rank
lua.execute("""KEPT_RANKS = HeadstartNS.PlannerRanks
    HeadstartNS.PlannerRanks = function(name)
        if name == "Holy Light" then return { { id = 635, rank = 1 }, { id = 639, rank = 2 } } end
        return {}
    end
    KNOWN[635] = true KNOWN[639] = nil""")
same, body = lua.eval("""(function()
    local nl = string.char(10)
    local _, _, body = YR_SETUP.MacroFor({ kind = "macro", name = "Heal",
        body = "#showtooltip Holy Light(Rank 1)" .. nl .. "/cast [@mouseover,help][] Holy Light(Rank 1); Holy Light(Rank 2)" })
    return body == "#showtooltip Holy Light(Rank 1)" .. nl .. "/cast [@mouseover,help][] Holy Light(Rank 1); Holy Light", body
end)()""")
report(same is True, f"a macro of your own: the rank you know stays as you wrote it, one this character hasn't got is taken out ({body!r})")
lua.execute("HeadstartNS.PlannerRanks = KEPT_RANKS")

# "Apply bars" on a character in play is asked as the bars alone
lua.execute("""Fresh(); OLD_LEVEL = UnitLevel UnitLevel = function() return 30 end
    for i = 20, 40 do BAR[i] = { kind = 'spell', id = 635 } end
    YippSetupCharDB.applied = nil
    ASKED = nil StaticPopup_Show = function(w, a, b, data) ASKED = { which = w, to = a, what = b, data = data } end""")
YS.Apply(YS, None, None, lua.eval("{ barsOnly = true }"))
report(g.ASKED is not None and g.ASKED.which == "YIPPSETUP_BARS" and g.BAR[30] is not None,
       "Apply bars on a character in play: asked as the bars alone, nothing changed until answered")
report(lua.eval("StaticPopupDialogs.YIPPSETUP_BARS.enterClicksFirstButton == true and StaticPopupDialogs.YIPPSETUP_AGAIN.enterClicksFirstButton == true"
                " and StaticPopupDialogs.YIPPSETUP_AGAIN.button1 == 'Bars only'"),
       "and Enter is the answer that changes least: the bars alone")
lua.execute("UnitLevel = OLD_LEVEL")

# a switch of profile on a character whose bars were never set up with Headstart: asked first, and a copy kept
lua.execute("Fresh()")
YS.Apply(YS, None, None, SURE)
r = New("Solo")
lua.execute("BAR[2] = nil BAR[3] = { kind = 'spell', id = 20594 }")       # Solo differs from Main
Switch("Main")
Switch("Solo")
Switch("Main")
lua.execute("""YippSetupCharDB.applied, YippSetupCharDB.backup, YippSetupCharDB.older = nil, nil, nil
    BAR[77] = { kind = 'spell', id = 20594 } ASKED = nil""")                # bars built by hand, never set up
before = dict((k, v.id) for k, v in g.BAR.items())
r = Switch("Solo")
report(r.ok is False and r.why is None and g.ASKED is not None and g.ASKED.which == "YIPPSETUP_SWITCH" and g.ASKED.data == "Solo"
       and YS.LayoutName() == "Main" and dict((k, v.id) for k, v in g.BAR.items()) == before and g.YippSetupCharDB.backup is None,
       f"a switch of profile on a character never set up: asked first, nothing changed ({g.ASKED and g.ASKED.what})")
lua.execute("StaticPopupDialogs.YIPPSETUP_SWITCH.OnAccept(nil, ASKED.data)")
report(YS.LayoutName() == "Solo" and g.YippSetupCharDB.backup is not None and g.YippSetupCharDB.backup.slots[77] is not None,
       "Switch: on the profile, with the bars as they were written down first")
YS.Undo(YS)
report(g.BAR[77] is not None and g.BAR[77].id == 20594, "and /ysetup undo puts the bars built by hand back")

# a class with nothing saved: bars arranged on Main are saved into it when you switch to it, not lost
lua.execute("""Fresh()""")
YS.Apply(YS, None, None, SURE)
lua.execute("YippSetupCharDB.applied = YippSetupCharDB.applied or time() YippSetupCharDB.layoutName = 'Solo'")
lua.execute("KEPT_PROFILE = YippSetupDB.classes.PALADIN.profile YippSetupDB.classes.PALADIN.profile = nil BAR[88] = { kind = 'spell', id = 20594 }")
r = Switch("Main")
main = g.YippSetupDB.classes.PALADIN.profile
report(r.ok is True and main is not None and main.slots is not None and main.slots[88] is not None and main.slots[88].name == "Stoneform",
       "switched to an empty Main: the bars you are on are saved into it then, as it says")
lua.execute("YippSetupDB.classes.PALADIN.profile = KEPT_PROFILE")

# a switch that can't make a macro the profile needs takes itself back, rather than leaving half of each
lua.execute("Fresh()")
YS.Apply(YS, None, None, SURE)
lua.execute("YippSetupCharDB.applied = YippSetupCharDB.applied or time() YippSetupCharDB.layoutName = nil")
Switch("Solo")
lua.execute("""local at = 121 while MACROS[at] do at = at + 1 end
    MACROS[at] = { 'Zed', 1, '/zed' } BAR[100] = { kind = 'macro', id = at } ZED = at""")
Switch("Main")                                                              # Solo saved with the macro Zed on a button
# (Zed gone, and no room to make it again: the game refuses a 31st macro, which this fake did not)
lua.execute("""BAR[100] = nil MACROS[ZED] = nil
    for i = 121, 150 do MACROS[i] = MACROS[i] or { 'Full' .. i, 1, '/sit' } end
    OLD_CREATE = CreateMacro
    CreateMacro = function(n, icon, body, perChar)
        local _, mine = GetNumMacros()
        if perChar and mine >= 30 then error("macro list full") end
        return OLD_CREATE(n, icon, body, perChar)
    end""")
before = dict((k, (v.kind, v.id)) for k, v in g.BAR.items())
r = Switch("Solo")
report(r.ok is False and r.why is not None and "macro list is full" in r.why and "Zed" in r.why and YS.LayoutName() == "Main"
       and dict((k, (v.kind, v.id)) for k, v in g.BAR.items()) == before,
       f"a switch with the macro list full: not switched, and the bars are as they were ({r.why and r.why[:50]})")
lua.execute("CreateMacro = OLD_CREATE for i = 121, 150 do if MACROS[i] and MACROS[i][1]:find('^Full') then MACROS[i] = nil end end")


# Key bindings are part of the saved interface: read action by action, put on, kept for undo
lua.execute("""
    BINDS = { { "MOVEFORWARD", "W", "UP" }, { "HEADER_MOVEMENT" }, { "JUMP", "SPACE" }, { "ACTIONBUTTON1", "1" }, { "ACTIONBUTTON2", "2" },
        { "TOGGLEBAG", "B" }, { "ONLYHERE", "F9" } }
    SAVED_SETS = 0
    function GetNumBindings() return #BINDS end
    function GetBinding(i) local b = BINDS[i] if b then return b[1], "cat", b[2], b[3] end end
    function GetBindingKey(action) for _, b in ipairs(BINDS) do if b[1] == action then return b[2], b[3] end end end
    function SetBinding(key, action)
        for _, b in ipairs(BINDS) do
            if b[2] == key then b[2], b[3] = b[3], nil elseif b[3] == key then b[3] = nil end
        end
        if action then
            for _, b in ipairs(BINDS) do
                if b[1] == action then if not b[2] then b[2] = key else b[3] = key end end
            end
        end
        return true
    end
    function SaveBindings() SAVED_SETS = SAVED_SETS + 1 end
    function GetCurrentBindingSet() return 1 end
    function KEYS() local t = {} for _, b in ipairs(BINDS) do t[b[1]] = (b[2] or "-") .. "," .. (b[3] or "-") end return t end
""")
mine = YS.ScanKeys()
report(mine is not None and mine.MOVEFORWARD[1] == "W" and mine.MOVEFORWARD[2] == "UP" and mine.JUMP[2] is False and mine.HEADER_MOVEMENT is None,
       "the keys are read action by action, both keys of each, a heading left out")
scanned = YS.ScanUI(YS)["keys"]            # (["keys"]: .keys on a Lua table is Python's own method here)
report(scanned is not None and scanned.ACTIONBUTTON1[1] == "1", "and are part of the interface that Save interface saves")
# the main's keys: E moves forward (W is strafe on the main, here nothing), 1 and 2 swapped, the bag key taken off
main = lua.eval('{ MOVEFORWARD = { "E", false }, JUMP = { "SPACE", false }, ACTIONBUTTON1 = { "2", false }, ACTIONBUTTON2 = { "1", "Q" }, TOGGLEBAG = { false, false } }')
lua.execute("YippSetupCharDB.uiBackup = { at = 1, last = 4000000000 } SAVED_SETS = 0")
n = YS.ApplyKeys(main, g.YippSetupCharDB.uiBackup)
now = g.KEYS()
report(n == 4 and now.MOVEFORWARD == "E,-" and now.ACTIONBUTTON1 == "2,-" and now.ACTIONBUTTON2 == "1,Q" and now.TOGGLEBAG == "-,-"
       and now.JUMP == "SPACE,-" and now.ONLYHERE == "F9,-" and g.SAVED_SETS == 1,
       f"put on: each action its saved keys (two keys swapped between two actions too), a key taken off stays off, an action the saved set doesn't name keeps its key ({n}: {dict(now.items())})")
report(YS.ApplyKeys(main) == 0 and g.SAVED_SETS == 1, "applied again: nothing to change, nothing saved")
was = g.YippSetupCharDB.uiBackup["keys"]
report(was is not None and was.MOVEFORWARD[1] == "W" and was.TOGGLEBAG[1] == "B", "the keys as they were are kept for undo")
YS.Undo(YS)
now = g.KEYS()
report(now.MOVEFORWARD == "W,UP" and now.ACTIONBUTTON1 == "1,-" and now.ACTIONBUTTON2 == "2,-" and now.TOGGLEBAG == "B,-",
       f"/ysetup undo after Apply interface: your own keys back ({dict(now.items())})")
lua.execute("COMBAT = true")
report(YS.ApplyKeys(main) is None and g.KEYS().MOVEFORWARD == "W,UP", "in a fight: no key is touched")
lua.execute("COMBAT = false")
# through Apply interface, by its switch
lua.execute("YippSetupCharDB.uiBackup = nil")
YS.ApplyUI(YS, lua.eval('{ cvars = {}, bars = {}, keys = { MOVEFORWARD = { "E", false } } }'), YS.Options(YS))
report(g.KEYS().MOVEFORWARD == "E,-", "Apply interface puts the saved keys on")
lua.execute('SetBinding("E") SetBinding("W", "MOVEFORWARD") SetBinding("UP", "MOVEFORWARD")')
YS.Options(YS).keys = False
YS.ApplyUI(YS, lua.eval('{ cvars = {}, bars = {}, keys = { MOVEFORWARD = { "E", false } } }'), YS.Options(YS))
report(g.KEYS().MOVEFORWARD == "W,UP", "with Key bindings switched off: yours are left alone")
YS.Options(YS).keys = True

# Graphics and sound: the machine's own settings, which matter on another install (the live game after
# the beta). Saved with the interface, put on by its switch, the quality preset before what is under it.
lua.execute("""CVARS.graphicsQuality = "7" CVARS.graphicsShadowQuality = "1" CVARS.graphicsViewDistance = "7"
    CVARS.Sound_MasterVolume = "0.15" CVARS.Sound_MusicVolume = "0" CVARS.maxFPS = "160" CVARS.GxMaximize = "1"
    CVARS.GxAdapter = "a card" CVARS.Sound_OutputDriverName = "a headset"
    SETS = {} local set = C_CVar.SetCVar
    C_CVar.SetCVar = function(k, v)
        SETS[#SETS + 1] = k
        -- (as the game does it: a quality preset sets what is under it)
        if k == "graphicsQuality" then CVARS.graphicsShadowQuality = "3" CVARS.graphicsViewDistance = v == "7" and "7" or "3" end
        return set(k, v)
    end""")
saved = YS.ScanUI(YS)
m = saved.machine
report(m is not None and m.graphicsQuality == "7" and m.graphicsShadowQuality == "1" and m.Sound_MasterVolume == "0.15" and m.maxFPS == "160",
       "Save interface saves graphics and sound: the quality, the volumes, the frame rate limit")
report(m.GxMaximize is None and m.GxAdapter is None and m.Sound_OutputDriverName is None and m.MSAAQuality is None,
       "not the window, the graphics card or the sound device - and not a setting this client hasn't got")
report(saved.v == 5 and not YS.UIStale(saved) and YS.UIStale(lua.eval("{ v = 4 }")), "an interface saved before this is known as an older one")
other = lua.eval("(function(ui) local c = {} for k, v in pairs(ui) do c[k] = v end c.machine = { Sound_MasterVolume = '1' } return c end)")(saved)
report(YS.UISig(saved) == YS.UISig(other) and other.machine.Sound_MasterVolume == "1",
       "a volume turned down is not a changed screen: the other characters are not asked to take it")
# another install: the game's own defaults, with one thing set by hand
g.MACHINE = m
lua.execute("""CVARS.graphicsQuality = "3" CVARS.graphicsShadowQuality = "2" CVARS.graphicsViewDistance = "3"
    CVARS.Sound_MasterVolume = "1" CVARS.Sound_MusicVolume = "0.4" SETS = {} SAID = {}
    YippSetupCharDB.uiBackup = { at = 1, last = 4000000000 }
    local p = YR_SETUP.Print YR_SETUP.Print = function(text) SAID[#SAID + 1] = text end""")
YS.ApplyUI(YS, lua.eval("{ cvars = {}, bars = {}, v = 5, machine = MACHINE }"), YS.Options(YS))
c = g.CVARS
report(c.graphicsQuality == "7" and c.graphicsShadowQuality == "1" and c.graphicsViewDistance == "7" and c.Sound_MasterVolume == "0.15" and c.Sound_MusicVolume == "0",
       f"Apply interface puts them on ({c.graphicsQuality}, {c.graphicsShadowQuality}, {c.graphicsViewDistance}, {c.Sound_MasterVolume}, {c.Sound_MusicVolume})")
sets = list(g.SETS.values())
report(sets[0] == "graphicsQuality" and "graphicsShadowQuality" in sets and "maxFPS" not in sets and "GxMaximize" not in sets,
       f"the quality preset first, then what is under it; what is the same already is not set ({sets})")
said = " ".join(g.SAID.values())
report("Graphics and sound: 5 changed" in said, f"and chat says how many ({said[:200]})")
kept = g.YippSetupCharDB.uiBackup.cvars
report(kept is not None and kept.graphicsQuality == "3" and kept.graphicsShadowQuality == "2" and kept.Sound_MasterVolume == "1" and kept.maxFPS == "160",
       "what you had is kept for undo - as it was before the preset touched it, and all of them")
YS.Undo(YS)
report(c.graphicsQuality == "3" and c.graphicsShadowQuality == "2" and c.graphicsViewDistance == "3" and c.Sound_MasterVolume == "1" and c.Sound_MusicVolume == "0.4",
       f"/ysetup undo: your own graphics and sound back, the setting under a preset too ({c.graphicsQuality}, {c.graphicsShadowQuality}, {c.Sound_MasterVolume})")
# applied where they are the same already: nothing set, nothing said to have changed
lua.execute('CVARS.graphicsQuality = "7" CVARS.graphicsShadowQuality = "1" CVARS.graphicsViewDistance = "7" CVARS.Sound_MasterVolume = "0.15" CVARS.Sound_MusicVolume = "0" SETS, SAID = {}, {}')
YS.ApplyUI(YS, lua.eval("{ cvars = {}, bars = {}, v = 5, machine = MACHINE }"), YS.Options(YS))
report(len(list(g.SETS.values())) == 0 and "Graphics and sound: 0 changed" in " ".join(g.SAID.values()), "on the install it was saved on: nothing to change")
# its switch off, and an interface that has none saved
lua.execute('CVARS.Sound_MasterVolume = "1" SETS, SAID = {}, {}')
YS.Options(YS).graphics = False
YS.ApplyUI(YS, lua.eval("{ cvars = {}, bars = {}, v = 5, machine = MACHINE }"), YS.Options(YS))
report(c.Sound_MasterVolume == "1" and "Graphics and sound: off" in " ".join(g.SAID.values()), "with Graphics and sound switched off: yours are left alone")
YS.Options(YS).graphics = True
lua.execute("SAID = {}")
YS.ApplyUI(YS, lua.eval("{ cvars = {}, bars = {}, v = 4 }"), YS.Options(YS))
said = " ".join(g.SAID.values())
report(c.Sound_MasterVolume == "1" and "Graphics and sound: none saved" in said and "graphics and sound are not in it" in said and "key bindings" not in said.split("older Headstart:")[1],
       f"an interface saved before this: nothing set, and it says what to do - naming only what that one lacks ({said[-170:]})")

# The automatic save holds off where the bars and the profile are known not to be the same thing (a
# profile deleted under the character, an undo, a plan saved and not applied): the profile had no
# other copy, and the bars were written over it four seconds later.
same = lua.eval("function(a, b) return rawequal(a, b) end")
lua.execute("YippSetupCharDB.applied = true YippSetupCharDB.hold = nil SAID = {}")
YS.Scan(YS)
before = YS.Profile(YS)
YS.Hold("the profile it was on was deleted")
YS.BarsStale()
YS.RememberNow()
report(g.YippSetupCharDB.hold == "the profile it was on was deleted" and same(YS.Profile(YS), before),
       "held: the bars are not saved over the profile by themselves")
YS.Hold("again")
report(g.YippSetupCharDB.hold == "the profile it was on was deleted", "said once: a second reason does not replace the first")
YS.Scan(YS)
report(g.YippSetupCharDB.hold is None and not same(YS.Profile(YS), before), "saved by hand: these bars are the profile, and the hold is off")
# Blizzard's own placing of new spells is stopped by a bars-only apply too
lua.execute('CVARS.AutoPushSpellToActionBar = "1"')
YS.Apply(YS, None, None, lua.eval("{ sure = true, barsOnly = true }"))
report(g.CVARS.AutoPushSpellToActionBar == "0", f"Bars only: Blizzard's own placing of new spells is stopped at once, not at the next login ({g.CVARS.AutoPushSpellToActionBar})")
sys.exit(1 if bad else 0)
