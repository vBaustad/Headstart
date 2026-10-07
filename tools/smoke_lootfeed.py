"""Smoke test of the loot feed and loot log (LootFeed.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_lootfeed.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Off: nothing is listened for. On: your own loot, money, experience and reputation are read from the
game's sentences (not somebody else's loot, not a secret line), shown as lines that add up and run
out, logged, and summed for the session with what that is an hour.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r"""
FRAMES, SAID = {}, {}
local F = {}
F.__index = function(t, k)
    if F[k] then return F[k] end
    return function() end                 -- any widget method: nothing
end
function F:RegisterEvent(e) local ev = rawget(self, "ev") or {} rawset(self, "ev", ev) ev[e] = true end
function F:UnregisterAllEvents() rawset(self, "ev", {}) end
function F:SetScript(what, fn) if what == "OnUpdate" and fn then ONUPDATES = ONUPDATES + 1 end rawset(self, what == "OnEvent" and "fn" or what, fn) end
function F:Show() rawset(self, "shown", true) end
function F:Hide() rawset(self, "shown", false) end
function F:SetShown(on) rawset(self, "shown", on and true or false) end
function F:IsShown() return rawget(self, "shown") == true end
function F:SetText(t) rawset(self, "said", t) end
function F:CreateFontString() return setmetatable({}, F) end
function F:CreateTexture() return setmetatable({}, F) end
function CreateFrame(_, name) local f = setmetatable({}, F) table.insert(FRAMES, f) if name then _G[name] = f end return f end
function Fire(e, ...) for _, f in ipairs(FRAMES) do local ev, fn = rawget(f, "ev"), rawget(f, "fn") if ev and ev[e] and fn then fn(f, e, ...) end end end
function Listening(e) for _, f in ipairs(FRAMES) do local ev = rawget(f, "ev") if ev and ev[e] then return true end end return false end
AFTER, ONUPDATES = {}, 0
C_Timer = { After = function(_, fn) AFTER[#AFTER + 1] = fn end }
function Tick() for _ = 1, 4 do local l = AFTER AFTER = {} for _, fn in ipairs(l) do fn() end end end
UIParent = setmetatable({}, F)
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
function print(...) SAID[#SAID + 1] = table.concat({ ... }, " ") end
NOW, CLOCK, XP, XPMAX, LEVEL = 100, 50000, 100, 1000, 10
function GetTime() return NOW end
function time() return CLOCK end
function date() return "12:00" end
function UnitXP() return XP end
function UnitXPMax() return XPMAX end
function UnitLevel() return LEVEL end
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = "%d Gold", "%d Silver", "%d Copper"
FACTION_STANDING_INCREASED = "Reputation with %s increased by %d."
C_Item = { GetItemInfo = function(link) local q = link:find("Blade") and 2 or 0 return "n", link, q, 1, 1, "", "", 1, "", 1, q == 2 and 250 or 7 end,
    GetItemIconByID = function(id) return "icon" .. id end }
SECRET = {}
function issecretvalue(v) return v == SECRET end
YippRouteDB = {}
STYLE = { FONT = "f", C = { text = { 1, 1, 1, 1 }, muted = { 1, 1, 1, 1 }, sub = { 1, 1, 1, 1 }, field = { 0, 0, 0, 1 } } }
local function W() return setmetatable({}, F) end
for _, k in ipairs({ "Text", "Fill", "Border", "Button", "Icon", "Window" }) do STYLE[k] = W end
BLADE = "|cff1eff00|Hitem:111::::::::|h[Green Blade]|h|r"
JUNK = "|cff9d9d9d|Hitem:222::::::::|h[Broken Fang]|h|r"
"""


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    YR = lua.table()
    for f in ("Core.lua", "LootFeed.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    YR.Style = lua.eval("STYLE")
    YR.StartLootFeed()
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def feed():
        g.Tick()
        if not g.HeadstartLootFeed:
            return []
        return list(lua.eval("""(function() local out = {} for _, line in ipairs(HeadstartLootFeed.lines) do
            if rawget(line, "shown") then out[#out + 1] = rawget(line.text, "said") or "" end end return out end)()""").values())

    YR.partsReady = True
    YR.ApplyParts()
    check(not g.Listening("CHAT_MSG_LOOT") and g.HeadstartLootLog is None and len(g.FRAMES) == 1,
          "never turned on: nothing listened for, nothing kept, not a frame made (the one there is Core's own)")

    # the game's sentences
    link, n = YR.LootFromText("You receive loot: " + g.BLADE + "x3.")
    check(link == g.BLADE and n == 3, "your own loot, with how many")
    check(YR.LootFromText("You receive loot: " + g.BLADE + ".")[1] == 1, "one of it when the sentence gives no number")
    check(YR.LootFromText("Anna receives loot: " + g.BLADE + ".") is None, "somebody else's loot is not yours")
    check(YR.MoneyFromText("You loot 1 Gold, 5 Silver, 74 Copper") == 10574 and YR.MoneyFromText("Your share of the loot is 12 Copper.") == 12,
          "money from its sentence, coin by coin")
    check("1g" in YR.Coins(10574) and "5s" in YR.Coins(10574) and "74c" in YR.Coins(10574) and "g" not in YR.Coins(74).replace("|cffeda55f", ""),
          "copper written as gold, silver and copper")

    g.YippRouteDB.lootFeed = True
    YR.ApplyParts()
    check(g.Listening("CHAT_MSG_LOOT") and g.Listening("PLAYER_XP_UPDATE"), "turned on: loot, money, reputation and XP are listened for")
    lua.execute("""Fire("CHAT_MSG_LOOT", "You receive loot: " .. BLADE .. "x2.")
        Fire("CHAT_MSG_LOOT", SECRET)
        Fire("CHAT_MSG_LOOT", "Anna receives loot: " .. BLADE .. ".")
        Fire("CHAT_MSG_MONEY", "You loot 5 Silver, 74 Copper")
        XP = 420 Fire("PLAYER_XP_UPDATE")
        Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Stormwind increased by 25.")""")
    lines = feed()
    check(len(lines) == 4, f"an item, money, experience and reputation: a line each ({lines})")
    check(any("Green Blade" in l and "x2" in l for l in lines) and any("+320 XP" in l for l in lines) and any("+25 Stormwind" in l for l in lines),
          "each says what and how much")
    lua.execute("""Fire("CHAT_MSG_LOOT", "You receive loot: " .. BLADE .. ".") XP = 520 Fire("PLAYER_XP_UPDATE")""")
    lines = feed()
    check(len(lines) == 4 and any("x3" in l for l in lines) and any("+420 XP" in l for l in lines), f"the same thing again adds to its line ({lines})")
    lua.execute("""XP = 20 LEVEL = 11 Fire("PLAYER_XP_UPDATE")""")
    check(any("+920 XP" in l for l in feed()), "experience across a ding: what was left of the level, and the new level's")
    s = YR.LootSession()
    check(s.money == 574 and s.value == 750 and s["items"] == 3 and s.xp == 920, f"the session's sums ({s.money}, {s.value}, {s['items']}, {s.xp})")
    entries = g.HeadstartLootLog.entries
    check(len(entries) == 3 and entries[1][2] == "i" and entries[1][4] == 2 and entries[2][2] == "r" and entries[2][3] == "Stormwind",
          "the log has every item and reputation gain, with its time")

    # what an hour is worth; lines run out; the quality filter leaves the log alone
    lua.execute("CLOCK = CLOCK + 1800")
    s = YR.LootSession()
    check(abs(s.moneyHour - (574 + 750) * 2) < 1 and abs(s.xpHour - 1840) < 1, "half an hour in: money and value an hour, and XP an hour")
    lua.execute("NOW = NOW + 20")
    check(len(feed()) == 0 and lua.eval("rawget(HeadstartLootFeed, 'shown')") is False, "the lines run out, and the feed goes with the last")
    check(g.ONUPDATES == 0, "and none of it ran a frame at a time: a timer for the oldest line, the game's own fade")
    g.YippRouteDB.lootQuality = 2
    lua.execute("""Fire("CHAT_MSG_LOOT", "You receive loot: " .. JUNK .. ".")""")
    check(len(feed()) == 0 and len(g.HeadstartLootLog.entries) == 4, "an item under the quality shown: not on the feed, still in the log")
    g.YippRouteDB.lootMoney = False
    lua.execute("""Fire("CHAT_MSG_MONEY", "You loot 10 Copper")""")
    check(len(feed()) == 0 and YR.LootSession().money == 584, "money turned off the feed is still summed")

    # the window, a new session, and off
    YR.LootLogToggle()
    check(g.HeadstartLootLog is not None, "the log's window opens")
    YR.LootSessionReset()
    check(YR.LootSession().money == 0 and YR.LootLogCount() == 4, "a new session: the sums start again, the list stays")
    YR.LootLogClear()
    check(YR.LootLogCount() == 0, "Empty forgets the list")
    g.YippRouteDB.lootFeed = False
    YR.ApplyParts()
    check(not g.Listening("CHAT_MSG_LOOT"), "turned off: nothing listened for")
    lua.execute("""Fire("CHAT_MSG_LOOT", "You receive loot: " .. BLADE .. ".")""")
    check(len(feed()) == 0, "and nothing shown")
    YRB = lua.table()
    for f in ("Core.lua", "LootFeed.lua"):
        lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)("Headstart", YRB)
    YRB.StartLootFeed()
    check(g.HeadstartLootLog is None, "off at a login: what was left in the saved file is dropped")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
