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
function GetActionText(s) local b = BAR[s] if not b then return nil end return b.kind == "macro" and MACROS[b.id][1] or nil end
function GetMacroIndexByName(n) for i, m in pairs(MACROS) do if m[1] == n then return i end end return 0 end
function GetMacroInfo(i) local m = MACROS[i] if m then return m[1], m[2], m[3] end end
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
for f in ("Style.lua", "Data/SpellLevels.lua", "Setup.lua", "SetupUI.lua"):
    chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
    chunk("Headstart", YS)
YS = YS.Setup          # the setup's own table inside Headstart

g = lua.globals()
lua.execute(r'''
YippSetupDB, YippSetupCharDB = {}, {}
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
YS.Apply(YS)
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
YS.Apply(YS)
lua.execute("YS_after = 0 for _ in pairs(MACROS) do YS_after = YS_after + 1 end")
again = g.YS_after - g.YS_before
print(("ok  " if again == 0 else "FAIL"), "applying twice creates", again, "new macros")
bad += again != 0
# Set up again later (the plan changed mid-levelling): a macro made on this character since stays;
# a question-mark macro for a spell taken off the layout goes.
lua.execute(r'''local last = 120 while MACROS[last + 1] do last = last + 1 end
    MACROS[last + 1] = { "MyOwn", 132089, "/cast [stealth] Ambush" }
    MACROS[last + 2] = { "Gone", 134400, "#showtooltip Retired Spell\n/cast Retired Spell" }''')
YS.Apply(YS)
left = [g.MACROS[k][1] for k in g.MACROS]
ok = "MyOwn" in left and "Gone" not in left
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
# A character where AutoFeed hasn't made its macro yet: AutoFeed is asked to make it (so it owns and
# fills it), and it goes in its slot. Nothing is copied from the main.
lua.execute(r'''MACROS = {}; AutoFeedCharDB = { owned = {} }''')
YS.Apply(YS)
made = [k for k in g.MACROS if g.MACROS[k][1] == "AutoFeed"]
b9 = g.BAR[9]
ok = len(made) == 1 and bool(g.AutoFeedCharDB.owned.AutoFeed) and b9 is not None and b9.kind == "macro" and b9.id == made[0]
ok = ok and g.MACROS[made[0]][3] == "#showtooltip"    # AutoFeed's own body, not the main's copy
print(("ok  " if ok else "FAIL"), f"AutoFeed asked to make its macro on a new character, and it is placed in slot 9: {b9 and (b9.kind, b9.id)}")
bad += not ok

# Without AutoFeed loaded: nothing is made, the slot stays empty, and it says why.
lua.execute(r'''MACROS = {}; AutoFeedCharDB = { owned = {} }; SAVED_LIBSTUB = LibStub; LibStub = nil''')
YS.Apply(YS)
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
YS.Apply(YS)
ok = g.RXP.loaded is not None
print(("ok  " if ok else "FAIL"), "old layout without ui: RestedXP guide still loaded")
bad += not ok
lua.execute(r'''ME.name = "Main"; GUID = "Player-1-0000MAIN"''')
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
lua.execute("""local e = YippSetupDB.classes.PALADIN.profile.slots[1]; e.down, e.id = true, 635""")
events._OnEvent(events, "SPELLS_CHANGED")
ok2 = g.BAR[1].id == 635
print(("ok  " if ok2 else "FAIL"), f"downranked on the main: slot 1 stays Rank 1 ({g.BAR[1].id})")
bad += not ok2
lua.execute("""local e = YippSetupDB.classes.PALADIN.profile.slots[1]; e.down, e.id = nil, nil""")
# a new rank always goes on the bar unless the spell is kept at a rank: there is no switch for it
YS.Options(YS).rankUp = False          # the switch there used to be: ignored now
events._OnEvent(events, "SPELLS_CHANGED")
ok = ok and g.BAR[1].id == 639
print(("ok  " if ok else "FAIL"), f"Holy Light Rank 2 trained: slot 1 now holds {g.BAR[1].id} (was Rank 1, 635)")
bad += not ok
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
YS.Apply(YS)
ok = g.BAR[8] is not None and g.BAR[8].kind == "item" and g.BAR[8].id == 6948
print(("ok  " if ok else "FAIL"), "items on: the Hearthstone goes back on its slot")
bad += not ok

lua.execute("Fresh({ placeholders = false })")
YS.Apply(YS)
ok = g.BAR[4] is None and g.BAR[1] is not None and g.BAR[1].kind == "spell"
print(("ok  " if ok else "FAIL"), "placeholders off: an unlearned spell's slot stays empty, a known one is placed")
bad += not ok
lua.execute("KNOWN[21082] = true")
events._OnEvent(events, "SPELLS_CHANGED")
ok = g.BAR[4] is not None and g.BAR[4].kind == "spell" and g.BAR[4].id == 21082
print(("ok  " if ok else "FAIL"), "... and goes in when it is learned")
bad += not ok

lua.execute("Fresh({ professions = false }); KNOWN[2580] = true")
YS.Apply(YS)
events._OnEvent(events, "SPELLS_CHANGED")
ok = g.BAR[10] is None
print(("ok  " if ok else "FAIL"), "professions off: Find Minerals is not placed, even when known")
bad += not ok

lua.execute("Fresh(); OLD_LEVEL = UnitLevel UnitLevel = function() return 10 end")
YS.Apply(YS)
ok = g.BAR[2] is not None and g.BAR[2].kind == "macro"
print(("ok  " if ok else "FAIL"), "level 10: Flash of Light (level 20, ten levels ahead) gets its question mark")
bad += not ok
lua.execute("UnitLevel = OLD_LEVEL")

# the level limit is for a new character's question marks: it never drops a spell at or under your level
lua.execute("Fresh(); OLD_LEVEL = UnitLevel UnitLevel = function() return 30 end NAMEID['Flash of Light'] = 19750 KNOWN[19750] = true")
YS.Apply(YS)
ok = g.BAR[2] is not None and g.BAR[2].kind == "spell" and g.BAR[2].id == 19750
print(("ok  " if ok else "FAIL"), "level 30: a level 20 spell you know goes on its slot")
bad += not ok
# ... and a spell above the limit, left out when the layout went on, goes into its empty slot once learned
lua.execute("Fresh(); UnitLevel = function() return 1 end KNOWN[19750] = nil")
YS.Apply(YS)
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
YS.Apply(YS)
plan, now = YS.PlanStart()
saved = YS.Profile(YS).slots
ok = all(plan[k] is not None for k in saved) and plan[4] is not None and plan[4].kind == "spell" and now[4] is not None and now[4].kind == "macro"
print(("ok  " if ok else "FAIL"), "the planner's start: every saved button, and a question-mark macro on the bar read as its spell")
bad += not ok
lua.execute("BAR[60] = { kind = 'spell', id = 635 }")
plan, now = YS.PlanStart()
ok = plan[60] is not None and plan[60].name == "Holy Light"
print(("ok  " if ok else "FAIL"), "... and a button on the bars that isn't in the saved layout is in it too")
bad += not ok
# an old button at a lower rank is not a choice: read as behind (stale), never as kept at that rank
lua.execute("""Fresh(); KNOWN[639] = true; NAMEID["Holy Light"] = 639; BAR[1] = { kind = 'spell', id = 635 }""")
now, _ = YS.ReadBars()
ok = now[1] is not None and now[1].stale is True and now[1].rankID == 635 and now[1].down is None
print(("ok  " if ok else "FAIL"), "a Rank 1 button with Rank 2 known: behind, not downranked")
bad += not ok
lua.execute("""KEPT_SLOT = YippSetupDB.classes.PALADIN.profile.slots[1]
    YippSetupDB.classes.PALADIN.profile.slots[1] = { kind = 'spell', name = 'Holy Light', level = 1, down = true, id = 635, rank = 1 }""")
plan, _ = YS.PlanStart()
ok = plan[1] is not None and plan[1].down is True and plan[1].id == 635
print(("ok  " if ok else "FAIL"), "... unless you set that rank in the planner: then it stays set")
bad += not ok
lua.execute("""KNOWN[639] = nil; NAMEID["Holy Light"] = 635; YippSetupDB.classes.PALADIN.profile.slots[1] = KEPT_SLOT""")
g.SlashCmdList.YIPPSETUP("debug")
print("ok  ", "/ysetup debug prints without an error")

lua.execute("Fresh({ clearBars = false }); BAR[20] = { kind = 'spell', id = 635 }")
YS.Apply(YS)
ok = g.BAR[20] is not None and g.BAR[20].id == 635
print(("ok  " if ok else "FAIL"), "clear bars off: a button the saved layout doesn't use is kept")
bad += not ok

# Spell buttons: only spells, macros for every spell, and a downranked button's macro casting its rank.
def chk(ok, what):
    global bad
    print(("ok  " if ok else "FAIL"), what)
    bad += not ok


lua.execute("Fresh({ spellButtons = 'spells' })")
YS.Apply(YS)
chk(g.BAR[4] is None and g.BAR[1] is not None and g.BAR[1].kind == "spell",
    "only spells: an unlearned spell's slot stays empty, a known one is the spell")
mo = g.BAR[5]
chk(mo is not None and mo.kind == "macro" and "@mouseover" in g.MACROS[mo.id][3],
    "only spells: a mouseover spell is still its macro (that is what makes it mouseover)")
lua.execute("Fresh({ spellButtons = 'macros' })")
YS.Apply(YS)
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
YS.Apply(YS)
b = g.BAR[1]
m = b and b.kind == "macro" and g.MACROS[b.id]
chk(m and m[3] == "#showtooltip Holy Light(Rank 1)\n/cast Holy Light(Rank 1)",
    f"a downranked button's macro casts that rank ({m and m[3]!r})")
lua.execute("""YippSetupDB.classes.PALADIN.profile.slots[1].rank = nil
    C_Spell.GetSpellSubtext = function(id) return id == 635 and "Rank 1" or nil end   -- the game's own rank text
    Fresh({ spellButtons = 'macros' })""")
YS.Apply(YS)
b = g.BAR[1]
m = b and b.kind == "macro" and g.MACROS[b.id]
chk(m and "(Rank 1)" in m[3], f"saved before ranks were stored, it still gets its rank ({m and m[3]!r})")
lua.execute("""local e = YippSetupDB.classes.PALADIN.profile.slots[1]
    e.down, e.id, e.rank = SAVED_SLOT1.down, SAVED_SLOT1.id, SAVED_SLOT1.rank
    Fresh({ placeholders = false })""")
chk(YS.SpellButtons(YS.Options(YS)) == "spells", "an old 'placeholders off' reads as Only spells")
lua.execute("Fresh({ spellButtons = 'spells' }); KNOWN[2580] = true")
YS.Apply(YS)
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
YS.Apply(YS)
ok = g.BAR[1] is None and g.BAR[13] is None and g.BAR[11] is not None
print(("ok  " if ok else "FAIL"), "class spells and racials off: only macros go on (your Heal macro is there)")
bad += not ok

lua.execute("Fresh({ mouseover = 'Holy Light' })")
YS.Apply(YS)
lua.execute("KNOWN[635] = nil")
lua.execute("Fresh({ mouseover = 'Holy Light' }); KNOWN[635] = nil")
YS.Apply(YS)
m = g.MACROS[g.BAR[1].id] if g.BAR[1] and g.BAR[1].kind == "macro" else None
ok = m is not None and "@mouseover" in m[3]
print(("ok  " if ok else "FAIL"), f"mouseover list: Holy Light becomes a mouseover macro: {m and m[3]!r}")
bad += not ok
lua.execute("Fresh()")

# A friend's setup from before settings were per class: one set of options and one saved layout.
# Nothing of it is changed or lost: the layout's class gets both, other classes start from the options.
lua.execute(r'''
OLD_PROFILE = { from = "Friend-Realm", class = "PALADIN", scanned = 1, slots = {}, ui = { cvars = {}, bars = {} } }
YippSetupDB = { options = { maxLevel = 14, items = true, clearBars = false }, profile = OLD_PROFILE }
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
sys.exit(1 if bad else 0)
