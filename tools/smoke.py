"""Smoke test: /yroute scan and the run log against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke.py      (exit code 1 on any failure)
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
FRAMES, TICKERS, NOW, CLOCK = {}, {}, 0, 1000
local Frame = {}
Frame.__index = Frame
function Frame:SetScript(_, fn) self.fn = fn end
function Frame:RegisterEvent(e) self.ev[e] = true end
function Frame:UnregisterEvent(e) self.ev[e] = nil end
function Frame:UnregisterAllEvents() self.ev = {} end
function CreateFrame() local f = setmetatable({ ev = {} }, Frame) table.insert(FRAMES, f) return f end
function Fire(event, ...) for _, f in ipairs(FRAMES) do if f.ev[event] and f.fn then f.fn(f, event, ...) end end end
C_Timer = { NewTicker = function(_, fn) local t = { fn = fn, Cancel = function(self) self.dead = true end } table.insert(TICKERS, t) return t end }
function RunTickers() for _, t in ipairs(TICKERS) do if not t.dead then t.fn() end end end
function GetTime() return NOW end
function time() return CLOCK end
function date() return "today" end
function floor(x) return math.floor(x) end
strsplit = function(_, s) local a, b = s:match("^(%S*)%s*(.*)$") return a, b ~= "" and b or nil end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
SlashCmdList = {}
PRINTS = {}
function print(m) table.insert(PRINTS, m) end
function UnitFullName() return "Tester", "Realm" end
function GetRealmName() return "Realm" end
function UnitClass() return "Paladin", "PALADIN" end
function UnitRace() return "Dwarf", "Dwarf" end
function UnitLevel() return 1 end
XP = 0
function UnitXP() return XP end
function GetBuildInfo() return "1.60.1", "70009" end
function UnitName() return "Sten Stoutarm" end
UnitFactionGroup = function() return "Alliance" end
C_Map = { GetBestMapForUnit = function() return 1426 end,
          GetPlayerMapPosition = function() return { GetXY = function() return 0.2993, 0.712 end } end }
-- the server: quest 179 and 96628 exist, 5 does not, 99999 never answers
local KNOWN = { [179] = { "Dwarven Outfitters", 1, 80, 35 }, [96628] = { "The Adventurer", 5, 450, 0 } }
LOG = {}          -- the quest log: { questID, complete }
C_QuestLog = {
    RequestLoadQuestByID = function(id) if id ~= 99999 then ASKED = ASKED or {} table.insert(ASKED, id) end end,
    GetTitleForQuestID = function(id) return KNOWN[id] and KNOWN[id][1] end,
    GetQuestDifficultyLevel = function(id) return KNOWN[id] and KNOWN[id][2] or 0 end,
    GetQuestTagInfo = function() return nil end,
    GetSuggestedGroupSize = function() return 0 end,
    GetQuestObjectives = function(id) return id == 179 and { { text = "Tough Wolf Meat: 0/8", type = "item", numRequired = 8 } } or {} end,
    IsQuestFlaggedCompleted = function() return false end,
    GetNumQuestLogEntries = function() return #LOG end,
    GetInfo = function(i) return { questID = LOG[i][1], isHeader = false } end,
    IsComplete = function(id) for _, q in ipairs(LOG) do if q[1] == id then return q[2] end end return false end,
}
function GetQuestLogRewardXP(id) return KNOWN[id] and KNOWN[id][3] or 0, KNOWN[id] and KNOWN[id][3] or 0 end
function GetQuestLogRewardMoney(id) return KNOWN[id] and KNOWN[id][4] or 0 end
function Answer() for _, id in ipairs(ASKED or {}) do Fire("QUEST_DATA_LOAD_RESULT", id, KNOWN[id] ~= nil) end ASKED = {} end
''')
YR = lua.table()
for f in ("Core.lua", "Scan.lua", "Log.lua", "Rewards.lua"):
    chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
    chunk("YippRoute", YR)
YR.QUEST_IDS = lua.eval("{ route = { 179 }, new = { 96628, 5 }, rest = { 99999 } }")
g = lua.globals()
g.Fire("ADDON_LOADED", "YippRoute")

bad = 0
def check(ok, what):
    global bad
    bad += not ok
    print(("ok  " if ok else "FAIL"), what)

# --- scan ---
g.SlashCmdList.YIPPROUTE("scan")
for _ in range(80):              # 8 seconds of ticks, answering whatever was asked
    g.RunTickers(); g.Answer(); g.NOW += 0.1
s = g.YippRouteDB.scan
check(s.quests[179] and s.quests[179].t == "Dwarven Outfitters" and s.quests[179].xp == 80 and s.quests[179].m == 35, "179: name, XP and money")
check(s.quests[179] and s.quests[179].obj[1][3] == 8, "179: objective count")
check(s.quests[96628] and s.quests[96628].xp == 450 and s.quests[96628].ql == 5, "96628 (new in Forever): XP and level")
check(s.failed[5] is True, "5: the server says no such quest")
check(s.noAnswer[99999] is True, "99999: no answer, timed out")
check(s.finished is not None, "scan finished")

# --- run log ---
run = g.YippRouteDB.runs["Tester-Realm"]
# at login a quest finished in an earlier session is already complete: not a completion "now"
g.LOG = lua.eval("{ { 783, true } }")
g.Fire("QUEST_LOG_UPDATE")
g.Fire("QUEST_ACCEPTED", 179)
g.LOG = lua.eval("{ { 179, false } }")
g.CLOCK += 300; g.XP = 380
g.LOG = lua.eval("{ { 179, true } }")
g.Fire("QUEST_LOG_UPDATE"); g.Fire("QUEST_LOG_UPDATE")     # completion must be logged once
g.CLOCK += 40
g.Fire("QUEST_TURNED_IN", 179, 80, 35)
g.RunTickers()                   # a position sample
kinds = [run.ev[i][2] for i in range(1, len(run.ev) + 1)]
check(kinds == ["accept", "complete", "turnin"], f"events in order, completion once: {kinds}")
acc, com, tin = run.ev[1], run.ev[2], run.ev[3]
check(acc.npc == "Sten Stoutarm" and acc.title == "Dwarven Outfitters", "accept: quest giver and title")
check(acc[6] == 1426 and acc[7] == 29.93 and acc[8] == 71.2, f"accept: position {acc[6]} {acc[7]} {acc[8]}")
check(com[1] - acc[1] == 300 and tin[1] - com[1] == 40, "times: 5 min objective, 40 s to turn in")
check(tin.xp == 80 and tin.money == 35, "turn-in: XP and money received")
check(len(run.track) >= 1, "position samples recorded")

# Reward choices: a two-handed weapon beats mail, mail beats water, water beats food; Shift or a level
# above 10 leaves the choice to you; nothing that fits, nothing chosen.
lua.execute(r'''
C_Timer.After = function(_, fn) fn() end
SHIFT, LEVEL = false, 5
function IsShiftKeyDown() return SHIFT end
function UnitLevel() return LEVEL end
-- id = { equipLoc, classID, subclassID, spell, sellPrice }
ITEMS = { [1] = { "INVTYPE_2HWEAPON", 2, 5, nil, 50 }, [2] = { "INVTYPE_CHEST", 4, 3, nil, 20 },
          [3] = { "INVTYPE_CHEST", 4, 2, nil, 99 }, [4] = { "", 0, 5, "Drink", 5 }, [5] = { "", 0, 5, "Food", 9 },
          [6] = { "INVTYPE_LEGS", 4, 3, nil, 40 }, [7] = { "INVTYPE_WEAPON", 2, 4, nil, 70 } }
C_Item = { GetItemInfoInstant = function(id) local i = ITEMS[id] return id, "", "", i[1], 0, i[2], i[3] end,
           GetItemSpell = function(id) return ITEMS[id][4] end,
           GetItemInfo = function(id) return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, ITEMS[id][5] end }
CHOICES = {}
function GetNumQuestChoices() return #CHOICES end
function GetQuestItemInfo(_, i) return "x", 0, 1, 1, true, CHOICES[i] end
function GetQuestItemLink(_, i) return "item" .. CHOICES[i] end
function GetQuestReward(i) PICKED = i end
function Pick(...) CHOICES = { ... } PICKED = nil Fire("QUEST_COMPLETE") return PICKED end
''')
check(g.Pick(3, 2, 1) == 3, "two-hander over mail and leather")
check(g.Pick(3, 2, 6) == 3, "of two mail pieces, the one that sells for more")
check(g.Pick(5, 4) == 2, "water over food")
check(g.Pick(3, 5, 7) is None, "nothing that fits: nothing chosen")
lua.execute("SHIFT = true")
check(g.Pick(1, 2) is None, "Shift held: you choose")
lua.execute("SHIFT = false; LEVEL = 11")
check(g.Pick(1, 2) is None, "above level 10: you choose")
sys.exit(1 if bad else 0)
