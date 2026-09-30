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
-- frames: any method this fake doesn't define is a no-op that returns another fake (textures, font strings)
local Frame = {}
Frame.__index = function(_, k) return rawget(Frame, k) or function() return setmetatable({ ev = {} }, Frame) end end
function Frame:Show() self.hidden = false end
function Frame:Hide() self.hidden = true end
function Frame:IsShown() return not self.hidden end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text or "" end
for _, k in ipairs({ "GetStringWidth", "GetHeight", "GetWidth", "GetVerticalScroll", "GetVerticalScrollRange" }) do
    Frame[k] = function() return 20 end
end
function Frame:IsMouseOver() return false end
function Frame:SetShown(on) self.hidden = not on end
function Frame:SetScript(_, fn) self.fn = fn end
function Frame:RegisterEvent(e) self.ev[e] = true end
function Frame:UnregisterEvent(e) self.ev[e] = nil end
function Frame:UnregisterAllEvents() self.ev = {} end
function Frame:RegisterUnitEvent(e) self.ev[e] = true end
function CreateFrame(_, name) local f = setmetatable({ ev = {} }, Frame) table.insert(FRAMES, f) if name then _G[name] = f end return f end
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
GUID = "Player-A"
HOOKS = {}
Minimap = CreateFrame()
function RequestTimePlayed() ASKED_PLAYED = (ASKED_PLAYED or 0) + 1 end
UISpecialFrames, StaticPopupDialogs = {}, {}
tinsert = table.insert
function StaticPopup_Show(which) POPUP = which end
GameTooltip = setmetatable({}, { __index = function() return function() end end })
function hooksecurefunc(name, fn) HOOKS[name] = fn end
function GetMerchantItemLink(i) return "|cffffffff|Hitem:2901::::|h[Mining Pick]|h|r" end
REGISTERED = {}
RXPGuides = { RegisterGuide = function(text) table.insert(REGISTERED, text) end }
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function UnitGUID() return GUID end
XP = 0
function UnitXP() return XP end
function UnitXPMax() return 400 end
COMBAT = false
function UnitAffectingCombat() return COMBAT end
function UnitIsDeadOrGhost() return false end
function UnitIsGhost() return false end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function GetZoneText() return "Dun Morogh" end
UNKNOWNOBJECT = "Unknown"
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
for f in ("Core.lua", "Scan.lua", "Log.lua", "Rewards.lua", "Splits.lua", "Options.lua", "Guides.lua",
          "Style.lua", "Editor.lua",
          "Guides/Coldridge.lua", "Guides/DunMorogh.lua"):
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
check(run.track[1][7] == 0, "position sample carries flags (not in combat)")

# XP from the turn-in above is not a kill; XP after it, in a fight, is. RestedXP's step is logged when it changes.
g.XP = 460; g.Fire("PLAYER_XP_UPDATE")          # the turn-in's 80 XP, same second as QUEST_TURNED_IN
g.CLOCK += 10; g.COMBAT = True; g.Fire("PLAYER_REGEN_DISABLED")
g.XP = 470; g.Fire("PLAYER_XP_UPDATE")          # a kill, 10 XP
g.COMBAT = False; g.Fire("PLAYER_REGEN_ENABLED")
lua.execute('''RXP = { currentGuide = { name = "1-5 Coldridge Valley (Launch)" } }; RXPCData = { currentStep = 7 }''')
g.RunTickers(); g.RunTickers()
lua.execute("RXPCData.currentStep = 8")
g.RunTickers()
kinds = [run.ev[i][2] for i in range(4, len(run.ev) + 1)]
check(kinds == ["fight", "kill", "peace", "step", "step"], f"fight, one kill, peace, two steps: {kinds}")
kill = [run.ev[i] for i in range(1, len(run.ev) + 1) if run.ev[i][2] == "kill"][0]
check(kill.xp == 10, f"kill XP 10: {kill.xp}")
steps = [run.ev[i].step for i in range(1, len(run.ev) + 1) if run.ev[i][2] == "step"]
check(list(steps) == [7, 8], f"steps 7 then 8: {list(steps)}")

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

# Level splits: the time is the server's /played. A reaches level 2 after 100 s of play; B, a new
# character, after 50 s - 50 s ahead; C, already level 12, is timed from what the server says.
lua.execute("LVL = 1; function UnitLevel() return LVL end")
splits = g.YippRouteDB.splits
a = splits.runs["Player-A"]
check(a is not None and (g.ASKED_PLAYED or 0) >= 1, "login asks the server for /played")
g.Fire("TIME_PLAYED_MSG", 0, 0)
check(a.levels[1] == 0 and a.elapsed == 0, "the server's answer sets the clock and the level's start")
for _ in range(10):
    g.NOW += 10; g.RunTickers()
lua.execute("LVL = 2"); g.Fire("PLAYER_LEVEL_UP", 2)
check(abs(a.levels[2] - 100) < 1, f"A: level 2 at {a.levels[2]:.0f} s of play")
lua.execute('''GUID = "Player-B"; XP = 0; LVL = 1''')
YR.StartSplits(YR)
g.Fire("TIME_PLAYED_MSG", 0, 0)
for _ in range(5):
    g.NOW += 10; g.RunTickers()
lua.execute("LVL = 2"); g.Fire("PLAYER_LEVEL_UP", 2)
b = splits.runs["Player-B"]
check(abs(b.levels[2] - 50) < 1, f"B: level 2 at {b.levels[2]:.0f} s of play")
said = g.PRINTS[len(g.PRINTS)]
check("|cff40ff40-0:50" in said, f"B is told it is 50 s ahead of A: {said}")
# the table: the live row for level 3 on top, then level 2 - its own time 0:50 and total 0:50, green against A's 1:40
YR.ShowSplits(YR, True)
g.NOW += 1; g.RunTickers()
f = g.YippRouteSplitsFrame
row = lambda i: [f.rows[i][c].text for c in (1, 2, 3, 4)]
check("Level 3" in row(1)[0], f"live row: {row(1)}")
check(row(2)[0] == "|cff66ccffLevel 2|r" and row(2)[1] == "|cff40ff400:50|r" and row(2)[2] == "|cff40ff400:50|r"
      and row(2)[3] == "|cff40ff40-0:50|r", f"level 2 row, green: {row(2)}")
check(f.time.text.startswith("|cff66ccffTime:|r "), f"total time: {f.time.text}")
lua.execute('''GUID = "Player-C"; XP = 900; LVL = 12''')
YR.StartSplits(YR)
g.Fire("TIME_PLAYED_MSG", 36000, 600)
c = splits.runs["Player-C"]
check(c is not None and c.elapsed == 36000 and c.levels[12] == 35400,
      "a levelled character is timed too: 10 h played, level 12 reached 10 min ago")
for _ in range(3):
    g.NOW += 10; g.RunTickers()
g.Fire("TIME_PLAYED_MSG", 36100, 700)
check(c.elapsed == 36100, "the server's /played wins over our own count (nothing lost to a crash)")
YR.ShowSplits(YR, False)
check(g.YippRouteSplitsFrame.hidden is True and g.YippRouteDB.showSplits is False, "splits can be turned off")
# Runs from before the splits: rebuilt from the run log, logged-out gaps left out, another character cut off
lua.execute('''YippRouteDB.splits.imported = nil
YippRouteDB.runs["Old-Realm"] = { track = { {0,1,0,0,1,0}, {30,1,0,0,2,0}, {5000,1,0,0,2,0}, {5030,1,0,0,3,0},
    {5032,1,0,0,20,0} } }''')
YR.StartSplits(YR)
old = [splits.runs[k] for k in splits.runs.keys() if str(k).startswith("log:Old-Realm")]
ok = len(old) == 1 and old[0].levels[2] == 30 and old[0].levels[3] == 60 and old[0].levels[20] is None
check(ok, "old run imported: level 2 at 0:30, 3 at 1:00 (an hour logged out skipped), the level-20 main not part of it")

# Shipped guides: both handed to RestedXP at login; a guide splits into steps and joins back unchanged;
# a saved edit replaces the shipped text; reverting brings it back.
check(len(g.REGISTERED) == 2, f"two guides registered with RestedXP: {len(g.REGISTERED)}")
for key in ("coldridge", "dunmorogh"):
    text = YR.GuideText(YR, key)
    header, steps = YR.SplitSteps(text)
    joined = YR.JoinSteps(header, steps)
    squash = lambda t: [l.rstrip() for l in t.strip().splitlines() if l.strip()]
    check(squash(joined) == squash(text) and len(steps) > 20, f"{key}: {len(steps)} steps, split and joined back unchanged")
header, steps = YR.SplitSteps(YR.GuideText(YR, "coldridge"))
summaries = [YR.StepSummary(steps[i]) for i in range(1, len(steps) + 1)]
check(any(s_ == "Accept The Boar Hunter" for s_ in summaries), f"step summary reads like the guide: {summaries[2]!r}")
first = steps[1]
table_remove = lua.eval("function(t, i) return table.remove(t, i) end")
table_remove(steps, 1)
YR.SaveCustom(YR, "coldridge", header, steps)
check(YR.IsCustom(YR, "coldridge") and first not in YR.GuideText(YR, "coldridge"), "an edit (first step removed) is what RestedXP gets")
YR.RevertGuide(YR, "coldridge")
check(not YR.IsCustom(YR, "coldridge") and first in YR.GuideText(YR, "coldridge"), "revert gives back the shipped guide")

# Purchases and trainer spells are logged; a spell learned away from a trainer (a level-up) is not
run = g.YippRouteDB.runs["Tester-Realm"]
lua.execute('''C_Item.GetItemNameByID = function() return "Mining Pick" end
C_Spell = { GetSpellName = function() return "Mining" end }''')
g.HOOKS["BuyMerchantItem"](3, 1)
g.Fire("TRAINER_SHOW"); g.Fire("LEARNED_SPELL_IN_SKILL_LINE", 2575); g.Fire("TRAINER_CLOSED")
g.Fire("LEARNED_SPELL_IN_SKILL_LINE", 20271)
tail = [run.ev[i] for i in range(1, len(run.ev) + 1)][-3:]
check(tail[0][2] == "buy" and tail[0].item == 2901, f"bought item logged: {tail[0][2]} {tail[0].item}")
check(tail[2][2] == "learn" and tail[2].spell == 2575, "Mining learned at the trainer logged, the level-up spell not")

# The route editor: recorded actions become guide steps (the delivery quest's instant "complete" is no step)
acts = YR.RunActions(YR)
labels = [acts[i].label for i in range(1, len(acts) + 1)]
check("Took Dwarven Outfitters" in labels and "Bought Mining Pick" in labels and "Learned Mining" in labels,
      f"this run's actions: {labels}")
steps_ = {acts[i].label: acts[i].step for i in range(1, len(acts) + 1)}
check(".accept 179 >>Accept Dwarven Outfitters" in steps_["Took Dwarven Outfitters"]
      and ".goto 1426,29.93,71.20" in steps_["Took Dwarven Outfitters"], "taking a quest becomes an accept step with its place")
check(".collect 2901,1" in steps_["Bought Mining Pick"] and ".train 2575" in steps_["Learned Mining"], "buy and learn steps")
# the window builds, and a recorded step can be put into the open route
YR.ToggleWindow(YR)
check(g.YippRouteWindow is not None and g.YippRouteWindow.hidden is False, "the window opens")
header, steps = YR.SplitSteps(YR.GuideText(YR, "coldridge"))
before = len(steps)
YR.InsertStep(YR, steps_["Bought Mining Pick"])
YR.ToggleWindow(YR, "share")
# import: a route with our Coldridge name replaces the player's; any other name is kept as an extra
own = YR.GuideText(YR, "coldridge").replace("Talin Keeneye", "Talin Keeneye (edited)")
done = YR.ImportGuide(YR, own)
check(done == "replaced your 1-5 Coldridge Valley (Launch)" and "(edited)" in YR.GuideText(YR, "coldridge"), f"import replaces: {done}")
other = "#name 1-6 Somewhere Else\n#group Friends\nstep\n    .accept 1 >>Accept Something\n"
done = YR.ImportGuide(YR, other)
check(done == "added 1-6 Somewhere Else" and g.YippRouteDB.extra["1-6 Somewhere Else"] is not None, f"import adds: {done}")
bad_import = YR.ImportGuide(YR, "hello")
check(bad_import[0] is None and "no #name" in bad_import[1], "text that isn't a guide is refused, with the reason")
YR.RevertGuide(YR, "coldridge")
# the minimap button exists and the settings switch hides it
check(g.YippRouteMinimapButton is not None and g.YippRouteMinimapButton.hidden is not True, "minimap button shown")
YR.ShowMinimapButton(YR, False)
check(g.YippRouteMinimapButton.hidden is True and g.YippRouteDB.minimapButton is False, "minimap button can be hidden")
sys.exit(1 if bad else 0)
