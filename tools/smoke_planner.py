"""Smoke test of the bar planner (Planner.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_planner.py      (exit code 1 on any failure; tools/smoke.py runs it too)

A level-1 Dwarf Paladin plans bars with spells of every level: click and place, drag and swap, drag off,
right-click, search; then saves it as the class layout (and is asked first when a copied layout would be
replaced). The list: no passives, the race's own active racials only, every name one Set up layout knows.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r'''
local Obj
Obj = { __call = function() return setmetatable({}, Obj) end }
Obj.__index = function(t, k)
    local v = rawget(Obj, k)
    if v then return v end
    local child = setmetatable({}, Obj); rawset(t, k, child); return child
end
function Obj.Show(self) rawset(self, "_shown", true) end
function Obj.Hide(self) rawset(self, "_shown", false) local h = rawget(self, "_hooks") if h then for _, f in ipairs(h) do f(self) end end end
function Obj.IsShown(self) return rawget(self, "_shown") ~= false end
function Obj.IsVisible(self) return rawget(self, "_shown") ~= false end
function Obj.SetShown(self, on) rawset(self, "_shown", on and true or false) end
function Obj.SetScript(self, what, fn) rawset(self, "_" .. what, fn) end
function Obj.HookScript(self, what, fn) if what == "OnHide" then rawset(self, "_hooks", rawget(self, "_hooks") or {}) table.insert(self._hooks, fn) end end
function Obj.SetText(self, t) rawset(self, "_text", t) end
function Obj.GetText(self) return rawget(self, "_text") or "" end
function Obj.SetTexture(self, t) rawset(self, "_tex", t) end
function Obj.IsMouseOver(self) return rawget(self, "_over") == true end
function Obj.GetStringWidth() return 20 end
function Obj.GetWidth() return 80 end
function Obj.GetEffectiveScale() return 1 end
function Obj.GetVerticalScrollRange() return 0 end
function Obj.GetVerticalScroll() return 0 end
function Obj.HasFocus() return false end
function CreateFrame(_, name) local f = setmetatable({}, Obj) if name then _G[name] = f end return f end
UIParent = CreateFrame()
GameTooltip = CreateFrame()
UISpecialFrames = {}
tinsert = table.insert
function GetCursorPosition() return 100, 100 end
bit = {
    lshift = function(a, n) return a * 2 ^ n end,
    band = function(a, b)
        local r, p = 0, 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then r = r + p end
            a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
        end
        return r
    end,
}
function UnitClass() return "Paladin", "PALADIN" end
function UnitRace() return "Dwarf", "Dwarf", 3 end
function UnitLevel() return 1 end
function time() return 1000 end
function InCombatLockdown() return false end
SHIFT = false
function IsShiftKeyDown() return SHIFT end
function Obj.EnableMouseWheel() end
function Obj.GetScript(self, what) return rawget(self, "_" .. what) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
C_Spell = { GetSpellTexture = function() return 1 end }
C_Item = {}
POPUP = nil
function StaticPopup_Show(which, a) POPUP = { which = which, a = a } return POPUP end
StaticPopupDialogs = {}
PRINTS = {}
'''


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    YR = lua.table()
    lua.globals().YR_T = YR
    load = lua.eval("function(c, n) return assert(loadstring(c, n)) end")
    for f in ("Style.lua", "Data/SpellLevels.lua"):
        load(open(os.path.join(ROOT, f), encoding="utf-8").read(), f)("Headstart", YR)
    # Setup.lua's side, as the planner uses it
    lua.execute('''
        local YR = YR_T
        local YS = YR.Setup
        PROFILE, APPLIED, OPTS = nil, 0, { placeholders = true, maxLevel = 10 }
        function YS:Profile() return PROFILE end
        function YS:SetProfile(p) PROFILE = p end
        function YS:Options() return OPTS end
        function YS:ScanUI() return { scanned = true } end
        function YS:Apply() APPLIED = APPLIED + 1 end
        YS.PlayerKey = function() return "Duplo-Forever" end
        function YR.Print(m) table.insert(PRINTS, m) end
    ''')
    lua.execute('''MACROS = { { "Food", 1, "/use Bread" }, [121] = { "Opener", 2, "/cast [stealth] Cheap Shot; Stealth" } }
        MAX_ACCOUNT_MACROS = 120
        function GetNumMacros() return 1, 1 end
        function GetMacroInfo(i) local m = MACROS[i] if m then return m[1], m[2], m[3] end end''')
    for f in ("Data/TrainerSpells.lua", "Data/PlannerSpells.lua", "Planner.lua"):
        load(open(os.path.join(ROOT, f), encoding="utf-8").read(), f)("Headstart", YR)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        if not ok:
            bad += 1
            print("FAIL planner:", what)

    # the list
    lst = YR.PlannerList()
    names = [lst[i].name for i in range(1, len(lst) + 1)]
    levels = YR.Setup.SPELL_LEVELS.PALADIN
    check("Holy Light" in names and "Devotion Aura" in names, "class spells are offered")
    check(any(lst[i].level >= 40 for i in range(1, len(lst) + 1)), "spells of every level, not just level 1")
    check("Anticipation" not in names and "Conviction" not in names, "passives are left out")
    check("Stoneform" in names and "Shadowmeld" not in names, "the Dwarf's racial, not the Night Elf's")
    check(all(levels[lst[i].name] is not None for i in range(1, len(lst) + 1) if not lst[i].racial and not lst[i].general),
          "every class spell is one Set up layout knows (YS.SPELL_LEVELS)")
    check("Attack" in names, "Attack is offered (a general spell, on no class skill line)")
    check(all(lst[i].level <= lst[i + 1].level for i in range(1, len(lst))), "sorted by level")

    YR.OpenPlanner()
    def state():
        p, s = YR.PlannerState()
        return p, s

    plan, slots = state()
    win = g.HeadstartPlanner
    check(win is not None and win.IsShown(win), "the planner opens")

    hl = next(i for i in range(1, len(lst) + 1) if lst[i].name == "Holy Light")
    seal = next(i for i in range(1, len(lst) + 1) if lst[i].name == "Seal of Righteousness")
    high = next(i for i in range(1, len(lst) + 1) if lst[i].level >= 40)

    def carry(i):
        YR.PlannerCarry(lst[i])

    def click(slot, button="LeftButton"):
        b = next(slots[j] for j in range(1, len(slots) + 1) if slots[j].slot == slot)
        b._OnClick(b, button)
        return b

    def drag(src, dst):
        a = next(slots[j] for j in range(1, len(slots) + 1) if slots[j].slot == src)
        a._OnDragStart(a)
        if dst:
            b = next(slots[j] for j in range(1, len(slots) + 1) if slots[j].slot == dst)
            b._over = True
        a._OnDragStop(a)
        if dst:
            b._over = None

    carry(hl)
    click(1)
    check(plan[1] is not None and plan[1].name == "Holy Light" and plan[1].level == levels["Holy Light"],
          "click a spell, click a slot: it's there, with its level")
    carry(high)
    click(61)
    check(plan[61] is not None and plan[61].name == lst[high].name, f"a level-{lst[high].level} spell on bar 2 at level 1")
    carry(seal)
    click(2)
    drag(2, 1)
    check(plan[1].name == "Seal of Righteousness" and plan[2].name == "Holy Light", "drag one slot onto another: they swap")
    check(plan[1]["from"] is None and plan[2]["from"] is None, "nothing extra is stored on a slot")
    drag(61, None)
    check(plan[61] is None, "dragged off the bars: gone")
    click(2, "RightButton")
    check(plan[2] is None, "right-click empties a slot")
    carry(hl)
    click(1)                   # onto Seal: Holy Light goes in, Seal comes along on the cursor
    check(plan[1].name == "Holy Light", "placed on a full slot: it goes in")
    click(3)
    check(plan[3] is not None and plan[3].name == "Seal of Righteousness", "and what was there is carried to the next click")

    # ---- downranking ---------------------------------------------------------------------------
    ranks = YR.PlannerRanks("Holy Light")
    rk = [(ranks[i].rank, ranks[i].id) for i in range(1, len(ranks) + 1)]
    check(len(rk) >= 7 and rk[0] == (1, 635) and [r for r, _ in rk] == list(range(1, len(rk) + 1)),
          f"Holy Light: every rank from 1, by ID: {rk[:3]}...")
    shock = YR.PlannerRanks("Holy Shock")
    check(shock[1].rank == 1 and shock[1].id == YR.PlannerSpells.PALADIN["Holy Shock"][1],
          "a talent spell's rank 1 comes from the planner data (no trainer teaches it)")
    check(len(YR.PlannerRanks("Purify")) == 0, "a spell without ranks has none to pick")
    top = len(rk)
    b1 = next(slots[j] for j in range(1, len(slots) + 1) if slots[j].slot == 1)
    b1._OnMouseWheel(b1, -1)
    check(plan[1].down is True and plan[1].id == rk[top - 2][1], "wheel down: one rank below the top, kept there")
    check(b1.rank._text == f"R{top - 1}", f"the slot shows the rank: {b1.rank._text}")
    check(lua.eval("function(t) return rawget(t, 'level') end")(b1) is None, "no learned-at level on the icons, only the rank")
    b1._OnMouseWheel(b1, -1)
    check(plan[1].id == rk[top - 3][1], "and another")
    b1._OnMouseWheel(b1, 1)
    b1._OnMouseWheel(b1, 1)
    check(plan[1].id is None and plan[1].down is None and b1.rank._text == "", "wheel up to the top: highest again, nothing pinned")
    b1._OnMouseWheel(b1, 1)
    check(plan[1].id is None, "up from highest stays highest")
    # Shift-click: the menu, with highest and every rank
    g.SHIFT = True
    b1._OnClick(b1, "LeftButton")
    g.SHIFT = False
    menu = YR.PlannerMenu()
    check(menu is not None and menu.IsShown(menu) and len(menu.choices) == top + 1, "Shift-click lists highest and every rank")
    pick2 = next(i for i in range(1, len(menu.choices) + 1) if menu.choices[i].rank == 2)
    it = menu["items"][pick2]; it._OnClick(it)
    check(plan[1].id == rk[1][1] and plan[1].down is True and not menu.IsShown(menu), "picking Rank 2 keeps the slot at rank 2")
    check(plan[1].name == "Holy Light", "still Holy Light, with its name for Set up")
    b3 = next(slots[j] for j in range(1, len(slots) + 1) if slots[j].slot == 3)
    YR.PlannerSetRank(3, 99)
    check(plan[3].id is None, "a rank past the top is just highest")

    # saving: a fresh class saves straight away as the planned layout
    YR.PlannerSave(False)
    p = g.PROFILE
    check(p is not None and p.planned and p["class"] == "PALADIN" and "(plan)" in p["from"], "saved as the planned class layout")
    check(p.slots[1].name == "Holy Light" and p.slots[3].name == "Seal of Righteousness", "with the slots as planned")
    check(p.slots[1].down is True and p.slots[1].id == rk[1][1], "a downranked slot is saved the way a copied main's is (id, down)")
    check(lua.eval("function(t) return rawget(t, 'ui') end")(p) is None,
          "bars only: the interface is the account's, never a level-1 character's defaults")
    check(g.APPLIED == 0, "Save alone doesn't set up")
    YR.PlannerSave(True)
    check(g.APPLIED == 1, "Save and set up does")

    # a layout copied from a main: asked first, and a plan's open starts from it
    lua.execute('PROFILE = { from = "Main-Forever", slots = { [5] = { kind = "macro", name = "Food", icon = 7 } } } POPUP = nil')
    YR.OpenPlanner()
    plan, slots = state()
    check(plan[5] is not None and plan[5].kind == "macro", "the planner starts from the saved layout, macros included")
    YR.PlannerAskSave(False)
    check(g.POPUP is not None and g.POPUP.which == "HEADSTART_PLAN_OVERWRITE", "replacing a copied layout asks first")
    check(g.PROFILE["from"] == "Main-Forever", "and doesn't replace it before you say so")
    win.Hide(win)
    YR.OpenPlanner()
    YR.PlannerCarry(lst[hl])
    win.Hide(win)
    check(not YR.PlannerCarrying(), "closing drops what you carry")

    # ---- general spells, professions, macros, forms ------------------------------------------------
    lua.execute("function UnitClass() return 'Rogue', 'ROGUE' end")
    rl = YR.PlannerList()
    rnames = [rl[i].name for i in range(1, len(rl) + 1)]
    check("Throw" in rnames and "Shoot Bow" in rnames, "a rogue gets Throw and the bow/gun/crossbow shots")
    check(len(YR.PlannerForms_()) == 1 and YR.PlannerForms_()[1][1] == "Stealth" and YR.PlannerForms_()[1][2] == 1,
          "a rogue's form bar: Stealth, bonus bar 1")
    lua.execute("function UnitClass() return 'Druid', 'DRUID' end")
    df = [(YR.PlannerForms_()[i][1], YR.PlannerForms_()[i][2]) for i in range(1, len(YR.PlannerForms_()) + 1)]
    check(df == [("Cat Form", 1), ("Bear Form", 3)], f"a druid's form bars from the game's data: {df}")
    lua.execute("function UnitClass() return 'Paladin', 'PALADIN' end")
    pl = YR.PlannerProfessionList()
    pnames = [pl[i].name for i in range(1, len(pl) + 1)]
    check("Find Minerals" in pnames and "Smelting" in pnames and "Basic Campfire" in pnames and "Disenchant" in pnames,
          "professions: the spells you cast")
    check("Weaponsmith" not in pnames and "Copper Bracers" not in pnames, "not specialisations or recipes")
    mac = YR.PlannerMacros()
    check([(mac[i].name, mac[i].account) for i in range(1, len(mac) + 1)] == [("Food", True), ("Opener", False)],
          "macros: the account's and this character's")
    YR.OpenPlanner()
    plan, slots = state()
    fm = next(i for i in range(1, len(pl) + 1) if pl[i].name == "Find Minerals")
    YR.PlannerCarry(pl[fm])
    click(7)
    check(plan[7].prof is True and plan[7].id == pl[fm].id and plan[7].icon == pl[fm].icon,
          "a profession spell is placed with its ID and icon (how Set up finds the right one)")
    YR.PlannerCarry(mac[2])
    click(8)
    check(plan[8].kind == "macro" and plan[8].body.startswith("/cast"), "a macro is placed with its body")
    # bar 1 in a form: its own slots (bonus bar 1 -> 73-84)
    YR.PlannerSetForm(1)
    b1 = next(slots[j] for j in range(1, len(slots) + 1) if slots[j].bar == 1 and slots[j].i == 1)
    check(b1.slot == 73, f"Bar 1 in the form shows slots 73-84: {b1.slot}")
    YR.PlannerCarry(lst[hl])
    b1._OnClick(b1, "LeftButton")
    check(plan[73] is not None and plan[73].name == "Holy Light", "placed in the form's bar (slot 73)")
    YR.PlannerSetForm(0)
    check(b1.slot == 1, "back to Normal: slots 1-12")
    check(YR.PlannerShortKey("Mouse Button 5") == "M5" and YR.PlannerShortKey("s-Num Pad 4") == "s-N4",
          "long key names are shortened to fit the button")
    win.Hide(win)

    # ---- on my bars ------------------------------------------------------------------------------
    # Bars 1 and 2 on screen (Blizzard's buttons), the rest switched off; the Headstart window open.
    lua.execute('''for i = 1, 12 do
            ActionButton = nil
            _G["ActionButton" .. i] = CreateFrame()
            _G["MultiBarBottomLeftButton" .. i] = CreateFrame()
            local hidden = CreateFrame() hidden:Hide()
            _G["MultiBarBottomRightButton" .. i] = hidden
        end
        HeadstartWindow = CreateFrame()
        PROFILE = nil
        YippSetupDB = {}''')
    lua.execute('''RANGE_INDICATOR = "\226\151\143"
        ActionButton3.HotKey = CreateFrame() ActionButton3.HotKey:SetText("Q")
        ActionButton4.HotKey = CreateFrame() ActionButton4.HotKey:SetText(RANGE_INDICATOR)
        BINDINGS = { MULTIACTIONBAR1BUTTON2 = "SHIFT-F" }
        function GetBindingKey(cmd) return BINDINGS[cmd] end
        function GetBindingText(key, short) return short and key:gsub("SHIFT%-", "s-") or key end''')
    YR.OpenPlanner()
    ov = YR.PlannerOverlays()
    shown = [ov[k] for k in ov if ov[k].IsShown(ov[k])]
    check(len(shown) == 24, f"one planner button over each real button on screen (bars 1 and 2): {len(shown)}")
    check(not g.HeadstartWindow.IsShown(g.HeadstartWindow), "the Headstart window steps out of the way of the bars")
    over3 = next(o for o in shown if o.slot == 3)
    over4 = next(o for o in shown if o.slot == 4)
    over62g = next(o for o in shown if o.slot == 62)
    check(over3.key._text == "Q", f"an empty button shows its key, as the real button writes it: {over3.key._text}")
    check(over4.key._text == "", "an unbound button (the game's dot) shows no key")
    check(over62g.key._text == "s-F", f"no HotKey text: the binding for that bar position: {over62g.key._text}")
    over5 = next(o for o in shown if o.slot == 5)
    over62 = next(o for o in shown if o.slot == 62)
    YR.PlannerCarry(lst[hl])
    over5._OnClick(over5, "LeftButton")
    plan, slots = state()
    YR.PlannerCarry(lst[hl])
    over3._OnClick(over3, "LeftButton")
    check(over3.key._text == "Q", "and keeps it once a spell is on it")
    over3._OnClick(over3, "RightButton")
    check(plan[5] is not None and plan[5].name == "Holy Light", "placed straight onto action button 5")
    over5._OnDragStart(over5)
    over62._over = True
    over5._OnDragStop(over5)
    over62._over = None
    check(plan[62] is not None and plan[62].name == "Holy Light" and plan[5] is None,
          "dragged from bar 1 to bar 2 (slot 62, where Edit Mode put it)")
    note = win.offscreen._text
    check("3" in note and "8" in note and "1," not in note, f"says which bars aren't on screen: {note}")
    YR.PlannerSetMode("grid")
    check(not over62.IsShown(over62) and win.grid.IsShown(win.grid), "the grid: overlays off, rows on")
    YR.PlannerSetMode("bars")
    check(g.YippSetupDB.plannerMode == "bars" and over62.IsShown(over62), "back on the bars, and remembered")
    win._OnEvent(win, "PLAYER_REGEN_DISABLED")
    check(not win.IsShown(win) and not over62.IsShown(over62), "a fight: the planner and its overlays go")
    check(g.HeadstartWindow.IsShown(g.HeadstartWindow), "and the Headstart window comes back")
    # a bar that isn't on screen between two that are: closing still takes every overlay off
    # bars 1, 2 and 4 on screen; bar 3 never was, so its overlays don't exist - a hole before bar 4's
    lua.execute('''for i = 1, 12 do _G["MultiBarRightButton" .. i] = CreateFrame() end''')
    YR.OpenPlanner()
    ov = YR.PlannerOverlays()
    up = [ov[k] for k in ov if ov[k].IsShown(ov[k])]
    check(len(up) == 36, f"bars 1, 2 and 4 on screen, 3 not: 36 overlays ({len(up)})")
    win.Hide(win)
    still = [k for k in ov if ov[k].IsShown(ov[k])]
    check(still == [], f"closed: no overlay left on the bars, past the gap either ({still})")
    lua.execute('''for i = 1, 12 do _G["MultiBarRightButton" .. i]:Hide() end''')
    # no Blizzard bar on screen (a bar addon): straight to the grid
    lua.execute('''for i = 1, 12 do _G["ActionButton" .. i]:Hide() _G["MultiBarBottomLeftButton" .. i]:Hide() end''')
    YR.OpenPlanner()
    check(win.grid.IsShown(win.grid), "no Blizzard bars on screen: the grid")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
