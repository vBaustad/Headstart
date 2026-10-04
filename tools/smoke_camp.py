"""Smoke test of the camp HUD (Camp.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_camp.py      (exit code 1 on any failure; tools/smoke.py runs it too)

The cases came with the HUD from Campfire's in-game self-test: the one line under the fire, the stat
read out of the buff's tooltip in every shape seen, how much of the hour is left, and a reading that
cannot happen in combat kept as "stale" rather than turned into "no camp".
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
FRAMES, NOW, AFTER = {}, 1000, {}
local Obj
Obj = { __call = function() return setmetatable({}, Obj) end }
Obj.__index = function(t, k)
    local v = rawget(Obj, k)
    if v then return v end
    local child = setmetatable({}, Obj); rawset(t, k, child); return child
end
function Obj.Show(self) rawset(self, "_shown", true) end
function Obj.Hide(self) rawset(self, "_shown", false) end
function Obj.IsShown(self) return rawget(self, "_shown") ~= false end
function Obj.SetShown(self, on) rawset(self, "_shown", on and true or false) end
function Obj.SetScript(self, what, fn) rawset(self, "_" .. what, fn) end
function Obj.RegisterEvent(self, e) rawset(self, "_ev", rawget(self, "_ev") or {}) self._ev[e] = true end
function Obj.RegisterUnitEvent(self, e) Obj.RegisterEvent(self, e) end
function Obj.SetText(self, t) rawset(self, "_text", t) end
function Obj.GetText(self) return rawget(self, "_text") or "" end
function Obj.SetAlpha(self, a) rawset(self, "_alpha", a) end
function Obj.GetLeft() return 100 end
function Obj.GetTop() return 600 end
function CreateFrame(_, name) local f = setmetatable({}, Obj) table.insert(FRAMES, f) if name then _G[name] = f end return f end
UIParent = CreateFrame()
function Fire(event, ...) for _, f in ipairs(FRAMES) do if rawget(f, "_ev") and f._ev[event] and rawget(f, "_OnEvent") then f._OnEvent(f, event, ...) end end end
function GetTime() return NOW end
C_Timer = { After = function(_, fn) table.insert(AFTER, fn) end }
function RunAfter() local list = AFTER AFTER = {} for _, fn in ipairs(list) do fn() end end
COMBAT = false
function InCombatLockdown() return COMBAT end
function UnitAffectingCombat() return COMBAT end
-- the player's buffs: { spellId, name, duration, expirationTime, tooltip lines }
AURAS = {}
C_UnitAuras = { GetAuraDataByIndex = function(_, i)
    local a = AURAS[i]
    if not a then return nil end
    return { spellId = a[1], name = a[2], icon = 1, duration = a[3], expirationTime = a[4] }
end }
C_TooltipInfo = { GetUnitAura = function(_, i)
    local a = AURAS[i]
    if not a then return nil end
    local lines = { { leftText = a[2] } }
    for _, t in ipairs(a[5] or {}) do lines[#lines + 1] = { leftText = t } end
    return { lines = lines }
end }
C_Spell = { GetSpellInfo = function(id) return { name = "Spell " .. id } end }
GameTooltip = CreateFrame()
ADDONS = {}
C_AddOns = { IsAddOnLoaded = function(name) return ADDONS[name] == true end }
YippRouteDB = {}
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
''')
    YR = lua.table()
    for f in ("Core.lua", "Camp.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        if not ok:
            bad += 1
            print("FAIL camp:", what)

    def line(**t):
        return YR.CampLines(lua.table(**t)) or "-"

    # One line, and only when there is something to do about it.
    check(line(nearby=True, benefits=False, settled=False) == "Campfire nearby", "says a camp is near when one is")
    check(line(nearby=True, benefits=False, settled=True) != "Campfire nearby",
          "settled at a fire reads differently from walking past one")
    check(line(nearby=True, benefits=True, settled=True) == "-", "no line once you have the benefit")
    resting = line(nearby=False, benefits=False, settled=False)
    check(resting != "-", "the resting state has a line")
    check("nearby" not in resting.lower(), "the resting line claims nothing about camps nearby")

    # The stat, out of whatever sentence the game wrapped it in.
    def stats(text):
        out = YR.CampStats(text)
        return [(out[i].label, out[i].value) for i in range(1, len(out) + 1)]

    check(stats("Sharpening Wheel: Strength increased by 6.") == [("Strength", "+6")], "the real camp line")
    for text, label, value in (
        ("Camp: Increases your Stamina by 12.", "Stamina", "+12"),
        ("Camp: +9 Agility", "Agility", "+9"),
        ("Camp: Attack Power increased by 20.", "Attack Power", "+20"),
        ("Camp: Critical Strike increased by 3.", "Crit", "+3"),
        ("Camp: Haste Rating increased by 5.", "Haste", "+5"),
    ):
        check(stats(text) == [(label, value)], f"reads {text!r} as {label} {value} (got {stats(text)})")
    check(stats("Gained the following camp benefits:\n\nSharpening Wheel: Strength increased by 6.")
          == [("Strength", "+6")], "the header sharing the benefit's line is dropped")
    # every station in Camp Benefits' own text (the game data), numbers filled in
    for text, want in (
        ("Tent: You received a small amount of rest experience. You can only receive this effect once per 1 hr.",
         [("Rested XP", None)]),
        ("Mana Well: Restores 40 Mana every 5 seconds.", [("Mana", "+40/5s")]),
        ("Enchanted Lute: Armor increased by 50, all attributes increased by 5, and all resistances increased by 10.",
         [("Armor", "+50"), ("All stats", "+5"), ("Resistances", "+10")]),
        ("First Aid Kit: Stamina increased by 8.", [("Stamina", "+8")]),
        ("Fish Bowl: All stats increased by 5%.", [("All stats", "+5%")]),
        ("Incense Candle: Intellect increased by 8.", [("Intellect", "+8")]),
        ("Lodestone: Melee Attack Power increased by 12.", [("Attack Power", "+12")]),
        ("Camp Chair: Critical strike chance with all spells and attacks increased by 1%.", [("Crit", "+1%")]),
        ("Faction Banner: Spirit increased by 8.", [("Spirit", "+8")]),
    ):
        check(stats(text) == want, f"{text.split(':')[0]}: {want} (got {stats(text)})")
    odd = stats("Some Station: Dodge goes up a bit somehow")
    check(len(odd) == 1 and odd[0][0] == "Dodge", "an unknown shape still shows the stat's name")
    check(stats(None) == [], "no stats out of nothing")
    check(stats("60 |4minute:minutes; remaining") == [], "WoW's plural markup is not a stat")
    check(YR.StatColor("Strength") != YR.StatColor("Intellect"), "stats have their own colours")
    check(YR.StatColor("Melee Attack Power") == YR.StatColor("Attack Power"), "colour from any word: Melee Attack Power is attack's")
    check(YR.StatColor("Dodge") == (1, 1, 1), "an unknown stat is white, not a faded grey")
    src = open(os.path.join(ROOT, "Camp.lua"), encoding="utf-8").read()
    check("AddOns\\Campfire" not in src, "the campfire icon is Headstart's own (Campfire may not be installed)")

    # How much of the hour is left.
    frac = lambda **b: YR.CampFraction(lua.table(**b))
    check(frac(expires=1000 + 1800, duration=3600) <= 0.6, "a half-spent buff is about half left")
    check(frac(expires=1000 - 10, duration=3600) == 0, "a finished buff has nothing left")
    check(frac(expires=1000 + 7200, duration=3600) == 1, "never over a full bar")
    check(YR.CampFraction(None) is None and frac(duration=0) is None, "no fraction for a buff with no timer")

    # Reading the real auras: at a camp with the benefit, then the same in combat.
    lua.execute('''AURAS = {
        { 1283391, "Campfire Nearby", 0, 0 },
        { 1229741, "Camp Benefits", 3600, NOW + 3000,
          { "Gained the following camp benefits:\\n\\nSharpening Wheel: Strength increased by 6.", "50 |4minute:minutes; remaining" } },
        { 1289723, "Welcoming Campfire", 60, NOW + 40 },
        { 12345, "Somebody's Blessing", 600, NOW + 300 },
    }''')
    YR.StartCamp()
    s, stale = YR.CampState()
    check(not stale, "out of combat the reading is current")
    check(s.nearby and s.benefits and s.settled and s.carrying, "nearby, benefits, settled and carrying all read")
    check(len(s.buffs) == 2 and s.buffs[1].id == 1229741, "two camp buffs, Camp Benefits first, the blessing left out")
    check(stats(s.buffs[1].stats) == [("Strength", "+6")], "the stat comes from the buff's tooltip")
    hud = g.HeadstartCampFrame
    check(hud is not None and hud.IsShown(hud), "the HUD is up at a camp")

    lua.execute("COMBAT = true")
    g.Fire("PLAYER_REGEN_DISABLED")
    lua.execute("RunAfter()")
    s, stale = YR.CampState()
    check(stale, "in combat the reading says it is stale")
    check(s.benefits, "in combat the last reading is kept, not emptied")
    check(hud._alpha < 1, "the HUD dims while it is going on what it last saw")
    lua.execute("COMBAT = false")

    # Walked away: the hour-long buff keeps it up; with it gone and campAlways off, it goes.
    lua.execute("table.remove(AURAS, 1)")
    g.Fire("UNIT_AURA", "player")
    g.Fire("UNIT_AURA", "player")
    check(len(g.AFTER) == 1, "a burst of UNIT_AURA is one read")
    lua.execute("RunAfter()")
    s, _ = YR.CampState()
    check(not s.nearby and s.carrying and hud.IsShown(hud), "away from the fire the buff keeps the HUD up")
    lua.execute("AURAS = {}")
    YR.SetCampAlways(False)
    check(not hud.IsShown(hud), "no camp, no buff, campAlways off: hidden")
    YR.SetCampAlways(True)
    check(hud.IsShown(hud), "campAlways on: the grey fire stays")

    # The Campfire addon showing its own campfire: ours steps aside; with Campfire's off, ours is back.
    lua.execute("ADDONS = { Campfire = true } CampfireDB = { camp = true }")
    YR.RefreshCamp()
    check(not hud.IsShown(hud), "Campfire loaded with its campfire on: ours hidden")
    lua.execute("CampfireDB.camp = false")
    YR.RefreshCamp()
    check(hud.IsShown(hud), "Campfire's campfire turned off: ours shows")
    lua.execute("CampfireDB = { hidden = false }")
    YR.RefreshCamp()
    check(hud.IsShown(hud), "a Campfire without a camp HUD: ours shows")
    lua.execute("CampfireCampFrame = CreateFrame()")
    YR.RefreshCamp()
    check(not hud.IsShown(hud), "Campfire's camp frame exists: ours hidden")
    lua.execute("CampfireCampFrame = nil ADDONS = {} CampfireDB = nil")
    YR.RefreshCamp()

    # Unlocked shows the preview anywhere; the setting off hides it.
    YR.SetCampLocked(False)
    check(hud.IsShown(hud) and hud.handle.IsShown(hud.handle), "unlocked: a preview with its drag edge")
    YR.SetCampLocked(True)
    YR.SetCampIcon(False)
    check(not hud.IsShown(hud), "the campfire icon off: hidden")
    check(g.YippRouteDB.camp is False, "the setting is saved")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
