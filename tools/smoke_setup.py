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
bad = 1 if bad_autopush else 0
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
YippSetupDB.classes.PALADIN.profile.ui.layout = { name = "MyChar", type = 2, export = "EXPORT:MyChar" }''')
YS.ApplyUI(YS, g.YippSetupDB.classes.PALADIN.profile.ui)
ok = g.EDIT.made is not None and g.EDIT.made.kind == 1 and g.EDIT.made.name == "MyChar"
print(("ok  " if ok else "FAIL"), "missing layout imported as an account layout")
bad += not ok

# A layout copied before bars and settings were saved: Set up layout still picks the guide, and
# logging in on the main fills the missing part in.
lua.execute(r'''YippSetupDB.classes.PALADIN.profile.ui = nil; RXP.loaded = nil''')
YS.Apply(YS)
ok = g.RXP.loaded is not None
print(("ok  " if ok else "FAIL"), "old layout without ui: RestedXP guide still loaded")
bad += not ok
lua.execute(r'''ME.name = "Main"; GUID = "Player-1-0000MAIN"''')
events._OnEvent(events, "PLAYER_ENTERING_WORLD", True, False)
ok = g.YippSetupDB.classes.PALADIN.profile.ui is not None and g.YippSetupDB.classes.PALADIN.profile.ui.cvars is not None
print(("ok  " if ok else "FAIL"), "logging in on the main fills in the missing ui")
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

# Other UI addons: action slots are shared by every bar addon, so they are set as always; Edit Mode is
# left to a UI suite and the Blizzard bar settings to any bar addon, and without those no reload is asked.
lua.execute('''LOADED = { "Bartender4" }; EDIT.selected = nil; EditModeManagerFrame.layoutInfo.activeLayout = 1
SETTINGS = { PROXY_SHOW_ACTIONBAR_2 = false, PROXY_SHOW_ACTIONBAR_3 = false, PROXY_SHOW_ACTIONBAR_4 = false }
StaticPopup_Show = function(w) POPUP = w end; POPUP = nil''')
YS.ApplyUI(YS, g.YippSetupDB.classes.PALADIN.profile.ui or lua.eval("nil"))
ok = g.SETTINGS.PROXY_SHOW_ACTIONBAR_2 is False and g.EDIT.selected == 3
check_ok = ok
print(("ok  " if ok else "FAIL"), "Bartender4 loaded: Blizzard bars left alone, Edit Mode still set")
bad += not ok
# Without other UI addons: a reload is asked only when Edit Mode or the bars actually changed.
lua.execute('''LOADED = {}; EditModeManagerFrame.layoutInfo.activeLayout = 1; POPUP = nil''')
YS.ApplyUI(YS, g.YippSetupDB.classes.PALADIN.profile.ui)
first = g.POPUP
lua.execute("POPUP = nil")
YS.ApplyUI(YS, g.YippSetupDB.classes.PALADIN.profile.ui)
ok = first == "YIPPSETUP_RELOAD" and g.POPUP is None
print(("ok  " if ok else "FAIL"), f"reload asked when the layout and bars changed ({first}), not when set up again with nothing to change ({g.POPUP})")
bad += not ok
lua.execute('''LOADED = { "ElvUI", "ElvUI_Options" }; EDIT.selected = nil; EditModeManagerFrame.layoutInfo.activeLayout = 1
SETTINGS = { PROXY_SHOW_ACTIONBAR_2 = false, PROXY_SHOW_ACTIONBAR_3 = false, PROXY_SHOW_ACTIONBAR_4 = false }
POPUP = nil''')
YS.ApplyUI(YS, g.YippSetupDB.classes.PALADIN.profile.ui)
ok = g.EDIT.selected is None and g.SETTINGS.PROXY_SHOW_ACTIONBAR_2 is False and g.POPUP is None
print(("ok  " if ok else "FAIL"), "ElvUI loaded: Edit Mode and Blizzard bars left alone, no reload asked")
bad += not ok
said = g.PRINTS[len(g.PRINTS)]
ok = "left to ElvUI" in said
print(("ok  " if ok else "FAIL"), f"and it says so: {said}")
bad += not ok
lua.execute('''LOADED = { "EllesmereUI_ActionBars" }; EDIT.selected = nil; EditModeManagerFrame.layoutInfo.activeLayout = 1''')
YS.ApplyUI(YS, g.YippSetupDB.classes.PALADIN.profile.ui)
ok = g.EDIT.selected is None
print(("ok  " if ok else "FAIL"), "an EllesmereUI module counts as EllesmereUI")
bad += not ok
# the guide follows the race
lua.execute('''LOADED = {}; RACE = "Human"; RXP.loaded = nil''')
YS.ApplyUI(YS, g.YippSetupDB.classes.PALADIN.profile.ui)
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
    YippSetupDB.classes[ME.class].options = {}
    local o = YR_SETUP:Options()
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

lua.execute("Fresh({ maxLevel = 20 })")
YS.Apply(YS)
ok = g.BAR[2] is not None and g.BAR[2].kind == "macro"
print(("ok  " if ok else "FAIL"), "level limit 20: Flash of Light (level 20) gets its placeholder")
bad += not ok

lua.execute("Fresh({ clearBars = false }); BAR[20] = { kind = 'spell', id = 635 }")
YS.Apply(YS)
ok = g.BAR[20] is not None and g.BAR[20].id == 635
print(("ok  " if ok else "FAIL"), "clear bars off: a button the saved layout doesn't use is kept")
bad += not ok

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
sys.exit(1 if bad else 0)
