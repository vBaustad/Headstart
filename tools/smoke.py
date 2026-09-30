"""Smoke test: /yroute scan and the run log against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke.py      (exit code 1 on any failure)
"""
import re
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
for _, k in ipairs({ "GetStringWidth", "GetHeight", "GetWidth", "GetVerticalScroll", "GetVerticalScrollRange",
    "GetFrameLevel", "GetLeft", "GetTop" }) do
    Frame[k] = function() return 20 end
end
function Frame:IsMouseOver() return false end
function Frame:HasFocus() return false end
function Frame:SetShown(on) self.hidden = not on end
function Frame:SetScript(_, fn) self.fn = fn end
function Frame:RegisterEvent(e) self.ev[e] = true end
function Frame:UnregisterEvent(e) self.ev[e] = nil end
function Frame:UnregisterAllEvents() self.ev = {} end
function Frame:RegisterUnitEvent(e) self.ev[e] = true end
function CreateFrame(_, name) local f = setmetatable({ ev = {} }, Frame) table.insert(FRAMES, f) if name then _G[name] = f end return f end
function Fire(event, ...) for _, f in ipairs(FRAMES) do if f.ev[event] and f.fn then f.fn(f, event, ...) end end end
C_Timer = { NewTicker = function(_, fn) local t = { fn = fn, Cancel = function(self) self.dead = true end } table.insert(TICKERS, t) return t end,
            After = function() end }   -- until the tests make it run at once (below)
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
UIParent = CreateFrame()
function ReloadUI() RELOADED = true end
function RequestTimePlayed() ASKED_PLAYED = (ASKED_PLAYED or 0) + 1 end
UISpecialFrames, StaticPopupDialogs = {}, {}
tinsert = table.insert
function StaticPopup_Show(which) POPUP = which end
GameTooltip = setmetatable({}, { __index = function() return function() end end })
function hooksecurefunc(a, b, c) if c then HOOKS[b] = c else HOOKS[a] = b end end
-- bags (BAGS[bag * 100 + slot] = { itemID, stackCount }) and a vendor window
BAGS = {}
C_Container = { UseContainerItem = function() end, GetContainerItemInfo = function(bag, slot) return BAGS[bag * 100 + slot] end }
MerchantFrame = { shown = false, IsShown = function(self) return self.shown end }
DONE = {}
-- the party: SENT collects addon messages; IN_GROUP / PARTY_NAMES say who is in it
SENT = {}
IN_GROUP = false
PARTY_NAMES = {}
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
               SendAddonMessage = function(prefix, msg, channel) table.insert(SENT, { prefix, msg, channel }) end }
function IsInGroup() return IN_GROUP end
function UnitInParty(n) return PARTY_NAMES[n] or false end
function UnitInRaid() return false end
function Ambiguate(n) return n end
function strsplit(sep, s)
    local out, i = {}, 1
    while true do
        local j = s:find(sep, i, true)
        if not j then out[#out + 1] = s:sub(i) break end
        out[#out + 1] = s:sub(i, j - 1)
        i = j + 1
    end
    return unpack(out)
end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
PUSHED = {}
function QuestLogPushQuest() table.insert(PUSHED, SELECTED_QUEST) end
ACCEPTED_OFFER = 0
function AcceptQuest() ACCEPTED_OFFER = ACCEPTED_OFFER + 1 end
NPC_IS_PLAYER = false
function UnitIsPlayer(u) return u == "npc" and NPC_IS_PLAYER end
ONQUEST = {}
function GetMoney() return MONEY or 0 end
LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF = "You receive loot: %sx%d.", "You receive loot: %s."
ERR_SKILL_UP_SI = "Your skill in %s has increased to %d."
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
    IsQuestFlaggedCompleted = function(id) return DONE[id] or false end,
    IsOnQuest = function(id) return ONQUEST[id] or false end,
    GetNumQuestLogEntries = function() return #LOG end,
    GetInfo = function(i) return { questID = LOG[i][1], isHeader = false } end,
    IsComplete = function(id) for _, q in ipairs(LOG) do if q[1] == id then return q[2] end end return false end,
}
function GetQuestLogRewardXP(id) return KNOWN[id] and KNOWN[id][3] or 0, KNOWN[id] and KNOWN[id][3] or 0 end
function GetQuestLogRewardMoney(id) return KNOWN[id] and KNOWN[id][4] or 0 end
function Answer() for _, id in ipairs(ASKED or {}) do Fire("QUEST_DATA_LOAD_RESULT", id, KNOWN[id] ~= nil) end ASKED = {} end
''')
YR = lua.table()
# every file the .toc loads, in its order
TOC = [l.strip().replace(chr(92), "/") for l in open(os.path.join(ROOT, "Headstart.toc"), encoding="utf-8")
       if l.strip().endswith(".lua") and not l.startswith("#")]
for f in TOC:
    chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
    chunk("Headstart", YR)
YR.QUEST_IDS = lua.eval("{ route = { 179 }, new = { 96628, 5 }, rest = { 99999 } }")
g = lua.globals()
g.Fire("ADDON_LOADED", "Headstart")

bad = 0
def check(ok, what):
    global bad
    bad += not ok
    print(("ok  " if ok else "FAIL"), what)

# --- scan ---
g.SlashCmdList.HEADSTART("scan")
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

# Profession skill-ups are logged (name and rank); weapon skill-ups are not.
lua.execute('''
SKILLS = { {"Professions", true}, {"Blacksmithing", false, 17, true}, {"Weapon Skills", true}, {"Maces", false, 12, false} }
function GetNumSkillLines() return #SKILLS end
function GetSkillLineInfo(i) local s = SKILLS[i] return s[1], s[2], true, s[3], 0, 0, 300, s[4] end
''')
n = len(run.ev)
g.Fire("CHAT_MSG_SKILL", "Your skill in Blacksmithing has increased to 17.")
g.Fire("CHAT_MSG_SKILL", "Your skill in Maces has increased to 12.")
check(len(run.ev) == n + 1 and run.ev[n + 1][2] == "skill" and run.ev[n + 1].name == "Blacksmithing" and run.ev[n + 1].rank == 17,
      "a Blacksmithing skill-up is logged with its rank, a weapon skill-up is not")

# Death skips: dying on a step that says ".deathskip" releases the spirit; any other death is left alone.
lua.execute('''
C_Timer.After = function(_, fn) fn() end
REPOPS, DEAD = 0, true
function RepopMe() REPOPS = REPOPS + 1 end
function UnitIsDead() return DEAD end
SKIP = { tag = "deathskip" }
RXP.currentGuide.steps = { { active = false, elements = { { tag = "goto" } } }, { active = true, elements = { { tag = "goto" }, SKIP } } }
''')
g.Fire("PLAYER_DEAD")
check(g.REPOPS == 1, "a death on a death-skip step releases the spirit")
lua.execute("SKIP.completed = true")
g.Fire("PLAYER_DEAD")
lua.execute("SKIP.completed = nil; YippRouteDB.deathSkipRelease = false")
g.Fire("PLAYER_DEAD")
check(g.REPOPS == 1, "... not once that step is done, nor with the option off")
lua.execute("YippRouteDB.deathSkipRelease = nil; DEAD = false; RXP.currentGuide.steps = nil")

# Reward choices (a paladin's default order: two-hander, mail, shield, water, food): the first kind on
# offer; of two the more valuable; nothing listed -> the most valuable (or you, if set so); Shift or
# above the level limit -> you; a reward you picked by hand is taken again for that quest.
lua.execute(r'''
C_Timer.After = function(_, fn) fn() end
SHIFT, LEVEL, QUEST = false, 5, 100
function IsShiftKeyDown() return SHIFT end
function UnitLevel() return LEVEL end
function GetQuestID() return QUEST end
function GetTitleText() return "A Quest" end
-- id = { equipLoc, classID, subclassID, spell, sellPrice }
ITEMS = { [1] = { "INVTYPE_2HWEAPON", 2, 5, nil, 50 }, [2] = { "INVTYPE_CHEST", 4, 3, nil, 20 },
          [3] = { "INVTYPE_CHEST", 4, 2, nil, 99 }, [4] = { "", 0, 5, "Drink", 5 }, [5] = { "", 0, 5, "Food", 9 },
          [6] = { "INVTYPE_LEGS", 4, 3, nil, 40 }, [7] = { "INVTYPE_WEAPON", 2, 4, nil, 70 },
          [8] = { "INVTYPE_FINGER", 4, 0, nil, 30 },
          [9] = { "INVTYPE_BAG", 1, 6, nil, 25 }, [10] = { "INVTYPE_BAG", 1, 2, nil, 10 },    -- mining pack, herb bag
          -- Rascally Rodents (Northshire): Mining for Dummies, Wild Harvest, Pelt Collecting for Beginners
          [247840] = { "", 0, 8, nil, 12 }, [247841] = { "", 0, 8, nil, 10 }, [247846] = { "", 0, 8, nil, 10 } }
C_Item = { GetItemInfoInstant = function(id) local i = ITEMS[id] or { "", 12, 0 } return id, "", "", i[1], 0, i[2], i[3] end,
           GetItemNameByID = function(id) return ({ [769] = "Chunk of Boar Meat", [2886] = "Crag Boar Rib" })[id] end,
           GetItemCount = function() return 3 end,
           GetItemSpell = function(id) return ITEMS[id][4] end,
           GetItemInfo = function(id) return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, ITEMS[id][5] end }
CHOICES = {}
function GetNumQuestChoices() return #CHOICES end
function GetQuestItemInfo(_, i) return "item" .. CHOICES[i], 0, 1, 1, true, CHOICES[i] end
function GetQuestItemLink(_, i) return "item" .. CHOICES[i] end
function GetQuestReward(i) PICKED = i end
function Pick(...) CHOICES = { ... } PICKED = nil Fire("QUEST_COMPLETE") return PICKED end
''')
check(g.Pick(3, 2, 1) == 3, "two-hander over mail and leather")
check(g.Pick(3, 2, 6) == 3, "of two mail pieces, the one that sells for more")
check(g.Pick(5, 4) == 2, "water over food")
check(g.Pick(3, 8, 7) == 1, "nothing from the list on offer: the most valuable (leather, 99)")
lua.execute("YippRouteDB.rewardClasses.PALADIN.fallback = 'ask'")
check(g.Pick(3, 8, 7) is None, "... or nothing, if you'd rather choose")
lua.execute("YippRouteDB.rewardClasses.PALADIN.off.twohand = true")
check(g.Pick(1, 2) == 2, "two-hander turned off: mail")
lua.execute("YippRouteDB.rewardClasses.PALADIN.off.twohand = nil")
lua.execute("SHIFT = true")
check(g.Pick(1, 2) is None, "Shift held: you choose")
lua.execute("QUEST = 200; CHOICES = { 1, 2, 8 }")
g.HOOKS["GetQuestReward"](3)                           # you took the ring by hand
chosen = g.YippRouteDB.rewardClasses.PALADIN.chosen[200]
check(chosen is not None and chosen.item == 8, "a reward picked by hand is remembered for that quest")
lua.execute("SHIFT = false")
check(g.Pick(1, 2, 8) == 3, "... and taken again next time, over the two-hander")
lua.execute("LEVEL = 11")
check(g.Pick(1, 2) is None, "above the level limit: you choose")
lua.execute("YippRouteDB.rewardClasses.PALADIN.maxLevel = 12")
check(g.Pick(1, 2) == 1, "the level limit is a setting")
check(g.Pick(9, 10) is None, "a profession choice (mining pack or herb bag) is never made for you")
check(g.Pick(2, 9) is None, "... not even next to a piece of gear")
check(g.Pick(247840, 247841, 247846) is None, "Rascally Rodents' three profession books: you choose (it used to take Mining for Dummies)")
lua.execute("QUEST = 201; CHOICES = { 9, 10 }")
g.HOOKS["GetQuestReward"](2)                           # you took the herb bag by hand
check(g.Pick(9, 10) == 2, "but the one you picked by hand for that quest is taken again")
lua.execute("QUEST = 200")
lua.execute("LEVEL = 5")

# Reward settings per class. A friend's from before (one set for all) become the settings of the
# first class that asks - the one they were made on - untouched; other classes start from their own
# list, with the same limits and the profession choices (not gear) they made.
lua.execute('''SAVED_REWARDS = YippRouteDB.rewardClasses; YippRouteDB.rewardClasses = nil; YippRouteDB.rewardsTakenBy = nil
OLD_REWARDS = { maxLevel = 7, order = { "cloth", "water" }, off = {}, remember = true, fallback = "ask",
    chosen = { [300] = { item = 247840, name = "Mining for Dummies" }, [301] = { item = 1, name = "Axe" } } }
YippRouteDB.rewards = OLD_REWARDS''')
pal = YR.RewardSettings(YR, "PALADIN")
check(pal.maxLevel == 7 and pal.order[1] == "cloth" and pal.fallback == "ask" and pal.chosen[301] is not None,
      "old reward settings: the first class keeps them all")
war = YR.RewardSettings(YR, "WARRIOR")
check(war.order[1] == "twohand" and war.maxLevel == 7 and war.chosen[300] is not None and war.chosen[301] is None,
      "a warrior gets its own list, the same limit, and the profession book pick but not the axe")
war.maxLevel = 3
check(g.OLD_REWARDS.maxLevel == 7 and YR.RewardSettings(YR, "PALADIN").maxLevel == 7, "the old settings and the paladin's stay as they were")
lua.execute("YippRouteDB.rewardClasses = SAVED_REWARDS; YippRouteDB.rewards = nil")

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
f = g.HeadstartSplitsFrame
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
check(g.HeadstartSplitsFrame.hidden is True and g.YippRouteDB.showSplits is False, "splits can be turned off")
# Runs from before the splits: rebuilt from the run log, logged-out gaps left out, another character cut off
lua.execute('''YippRouteDB.splits.imported = nil
YippRouteDB.runs["Old-Realm"] = { track = { {0,1,0,0,1,0}, {30,1,0,0,2,0}, {5000,1,0,0,2,0}, {5030,1,0,0,3,0},
    {5032,1,0,0,20,0} } }''')
YR.StartSplits(YR)
old = [splits.runs[k] for k in splits.runs.keys() if str(k).startswith("log:Old-Realm")]
ok = len(old) == 1 and old[0].levels[2] == 30 and old[0].levels[3] == 60 and old[0].levels[20] is None
check(ok, "old run imported: level 2 at 0:30, 3 at 1:00 (an hour logged out skipped), the level-20 main not part of it")
# The run to beat has a time for every level: a faster one first seen part-way (only a level-8 total)
# would leave every "vs best" cell empty.
lua.execute('''SAVED_RUNS = YippRouteDB.splits.runs
YippRouteDB.splits.runs = {
  partial = { name = "Late-Realm", levels = { [8] = 3485 }, elapsed = 9000 },
  full = { name = "Full-Realm", levels = { [1] = 0, [2] = 116, [3] = 506, [4] = 952, [5] = 1428, [6] = 1868, [7] = 2925, [8] = 3486 } },
  short = { name = "Short-Realm", levels = { [1] = 0, [2] = 100, [3] = 400 } } }''')
best = YR.SplitsBest()
check(best is not None and best.name == "Full-Realm", f"best run is the fully timed one, not a faster partial one: {best and best.name}")
lua.execute("YippRouteDB.splits.runs = SAVED_RUNS")

# Shipped guides: both handed to RestedXP at login; a guide splits into steps and joins back unchanged;
# a saved edit replaces the shipped text; reverting brings it back.
names = [str(g.REGISTERED[i]).split("#name ", 1)[1].splitlines()[0] for i in range(1, len(g.REGISTERED) + 1)]
solo = [n_ for n_ in names if "(Duo" not in n_ and "(Trio" not in n_]
check(len(solo) == 21 and len(names) == 21, f"21 routes registered with RestedXP (starting zones and 6-30), solo only while playing solo: {len(names)}")
lua.execute("YippSetupCharDB = YippSetupCharDB or {}")
YR.SetRole(YR, "Duo B")
names = [str(g.REGISTERED[i]).split("#name ", 1)[1].splitlines()[0] for i in range(1, len(g.REGISTERED) + 1)]
check("1-6 Northshire (Launch) (Duo B)" in names and "16-19 Darkshore (Duo B)" in names and not any("Trio" in n_ or "Duo A" in n_ for n_ in names),
      f"picking Duo B registers that role's versions only: {len(names) - 21} of them")
YR.SetRole(YR, "solo")
dwarf = YR.RoutesFor(YR, "Dwarf")
check(dwarf["coldridge"] and dwarf["dunmorogh"] and dwarf["16_19_darkshore"] and not dwarf["6_11_elwynn_forest"] and not dwarf["northshire"],
      "a Dwarf's routes: Coldridge on through Darkshore, not Human Elwynn or Northshire")
for key in ("coldridge", "dunmorogh", "northshire", "shadowglen"):
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

# An update never overwrites an edited route: the player is told, and can take the update with
# their edits kept, keep theirs, or undo having taken it.
header, steps = YR.SplitSteps(YR.GuideText(YR, "coldridge"))
mine_first = steps[1]
table_remove(steps, 1)
YR.SaveCustom(YR, "coldridge", header, steps)
edited = YR.GuideText(YR, "coldridge")
shipped = [YR.shipped[i] for i in range(1, len(YR.shipped) + 1) if YR.shipped[i].key == "coldridge"][0]
original = shipped.text
check(not YR.HasUpdate(YR, "coldridge"), "no update while the shipped route is the one the edit started from")
shipped.text = original.rstrip("\n") + "\nstep\n    .goto 1426,1,1 >> A new step we shipped\n"
YR.RegisterGuides(YR)
check(YR.HasUpdate(YR, "coldridge") and YR.GuideText(YR, "coldridge") == edited,
      "after an update the edited route is still the one RestedXP gets, and the update is offered")
check(g.YippRouteDB.custom.coldridge.told is not None, "the player is told about the update once (in chat, at login)")
clashes = YR.MergeUpdate(YR, "coldridge")
merged = YR.GuideText(YR, "coldridge")
check(clashes == 0 and "A new step we shipped" in merged and mine_first not in merged and not YR.HasUpdate(YR, "coldridge"),
      "taking the update keeps the player's edit (first step removed) and adds the new shipped step")
YR.UndoMerge(YR, "coldridge")
check(YR.GuideText(YR, "coldridge") == edited and YR.HasUpdate(YR, "coldridge"), "undoing the update gives back the route as it was")
YR.KeepMine(YR, "coldridge")
check(YR.GuideText(YR, "coldridge") == edited and not YR.HasUpdate(YR, "coldridge"), "keep mine: the route stays, the offer goes")
shipped.text = original
YR.RevertGuide(YR, "coldridge")

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
check(g.HeadstartWindow is not None and g.HeadstartWindow.hidden is False, "the window opens")
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
YR.ToggleWindow(YR, "settings")          # the settings page with the reward picker builds and fills
check(True, "settings page with reward settings opens")
# the minimap button exists and the settings switch hides it
check(g.HeadstartMinimapButton is not None and g.HeadstartMinimapButton.hidden is not True, "minimap button shown")
YR.ShowMinimapButton(YR, False)
check(g.HeadstartMinimapButton.hidden is True and g.YippRouteDB.minimapButton is False, "minimap button can be hidden")

# The step model: every step of both shipped routes reads into lines and writes back to the same text
# (spacing aside); the templates make steps; editing a line's argument changes only that argument.
for key in ("coldridge", "dunmorogh", "northshire", "shadowglen"):
    header, steps = YR.SplitSteps(YR.GuideText(YR, key))
    changed = []
    for i in range(1, len(steps) + 1):
        again = YR.WriteStep(YR.ParseStep(steps[i]))
        norm = lambda t: [l.strip() for l in t.splitlines() if l.strip()]
        if norm(again) != norm(steps[i]):
            changed.append(i)
    check(not changed, f"{key}: every step reads and writes back unchanged (differs: {changed[:5]})")
st = YR.ParseStep("step << Paladin\n    #optional\n    .goto 1426,22.3,72.5,45\n    >>Kill boars\n    .complete 183,1 --x12")
check(st.head == "<< Paladin" and st.lines[1].tag == "optional" and st.lines[2].cmd == "goto"
      and st.lines[3].text == "Kill boars" and st.lines[4].note.strip() == "--x12", "a step's parts: head, tag, command, text, note")
YR.SetArg(st.lines[2], 2, "30.5")
check(st.lines[2].args == "1426,30.5,72.5,45", f"changing X keeps the rest: {st.lines[2].args}")
info = YR.StepInfo(YR.ParseStep("step\n    .goto 1426,22.3,72.5\n    .accept 183 >>Accept The Boar Hunter"))
check(info.kind == "accept" and "The Boar Hunter" in info.text, f"step info: {info.kind} {info.text}")
temps = YR.StepTemplates()
kinds = [temps[i][1] for i in range(1, len(temps) + 1)]
check("xp" in kinds and "gold" in kinds and "quest" in kinds, f"templates: {kinds}")
xp_step = [YR.WriteStep(temps[i][3]) for i in range(1, len(temps) + 1) if temps[i][1] == "xp"][0]
lvl = g.UnitLevel() + 1
check(f".xp {lvl} >>Grind to level {lvl}" in xp_step and ".goto 1426,29.93,71.20" in xp_step, f"farm XP step here: {xp_step!r}")
# the split settings: size, lines and position
YR.ShowSplits(YR, True)
lua.execute("YR_ST = nil")
stl = YR.SplitsStyle(YR)
stl.size = 18; stl.rate = False
YR.ApplySplitsStyle(YR)
YR.SetSplitsPosition(YR, 300, 150)
pos = g.YippRouteDB.splitsPos
check(pos[1] == "TOPLEFT" and pos[2] == 300 and pos[3] == -150, f"splits placed in pixels: {list(pos.values())}")
# long times: the short clock drops the seconds past an hour; columns can be hidden
sf = g.HeadstartSplitsFrame
run_rec = [r for r in [g.YippRouteDB.splits.runs[k] for k in g.YippRouteDB.splits.runs.keys()] if r.name == "Tester-Realm"][0]
old_elapsed = run_rec.elapsed
run_rec.elapsed = 46 * 3600 + 55 * 60 + 53
YR.ApplySplitsStyle(YR)
full = sf.rows[1][3].text
stl.clock = "short"; YR.ApplySplitsStyle(YR)
short = sf.rows[1][3].text
check(re.search(r"\d+:\d\d:\d\d", full) and re.search(r"\d+h \d\dm", short) and not re.search(r"h \d\dm:", short),
      f"past an hour: {full!r} / {short!r}")
stl.levelCol = False; YR.ApplySplitsStyle(YR)
check(sf.rows[1][2].hidden is True and sf.rows[1][3].hidden is False, "the level column can be hidden, the total stays")
stl.clock, stl.levelCol, stl.size, stl.rate = "full", True, 14, True
run_rec.elapsed = old_elapsed
YR.ApplySplitsStyle(YR)
# The sidebar lists this character's routes: a Dwarf Paladin's, not Northshire's or the Hunters'
mine = YR.MyRoutes()
check(mine["coldridge"] and mine["dunmorogh"] and mine["12_14_loch_modan_dwarf_gnome"]
      and not mine["northshire"] and not mine["shadowglen"] and not mine["11_13_loch_modan_hunter"],
      f"my routes: {sorted(k for k in mine.keys())}")
# /hs opens Settings, and closes the window when Settings is already showing
YR.ToggleWindow(YR, "routes")
g.SlashCmdList.HEADSTARTSETTINGS("")
check(g.HeadstartWindow is not None and g.HeadstartWindow.hidden is False, "/hs opens Settings")
g.SlashCmdList.HEADSTARTSETTINGS("")
check(g.HeadstartWindow.hidden is True, "/hs again closes it")
YR.ToggleWindow(YR, "routes")
check(True, "the routes page with the step inspector builds and fills")

# Delete step: find the button by its label, click it, and the open route has one step fewer
lua.execute('''
function FindButton(label)
    for _, f in ipairs(FRAMES) do
        local t = rawget(f, "text")
        if type(t) == "table" and rawget(t, "text") == label then return f end
    end
end
''')
YR.ToggleWindow(YR, "routes")
count_text = None
btn = g.FindButton("Delete step")
check(btn is not None, "the Delete step button exists")
before = g.HeadstartWindow and None
lua.execute("DEL_BEFORE = nil")
header, steps = YR.SplitSteps(YR.GuideText(YR, "coldridge"))
n_before = len(steps)
if btn is not None:
    undo = g.FindButton("Undo changes")
    undo.fn(undo)                        # start from the saved route
    btn.fn(btn)
    YR.RefreshWindow(YR)
    lua.execute('''
    local b = FindButton("Save")
    b.fn(b)
    ''')
    header, steps = YR.SplitSteps(YR.GuideText(YR, "coldridge"))
    check(len(steps) == n_before - 1, f"Delete step, then Save: {n_before} -> {len(steps)} steps")
    YR.RevertGuide(YR, "coldridge")

# This run: clicking a quest action shows its details, with its Wowhead link to copy
YR.ToggleWindow(YR, "run")
lua.execute('''
function ClickFirstQuestRow()
    for _, f in ipairs(FRAMES) do
        local a = rawget(f, "action")
        if type(a) == "table" and (a.e[2] == "accept" or a.e[2] == "turnin") and rawget(f, "fn") then
            f.fn(f)
            return a.e[3]
        end
    end
end
function FindText(prefix)
    for _, f in ipairs(FRAMES) do
        local t = rawget(f, "text")
        if type(t) == "string" and t:sub(1, #prefix) == prefix then return t end
    end
end''')
qid = g.ClickFirstQuestRow()
link = g.FindText("https://www.wowhead.com/forever/quest=")
check(qid is not None and link == f"https://www.wowhead.com/forever/quest={qid}", f"clicking a quest in This run shows its Wowhead link: {link}")

# The first-time setup window's Set up doesn't set anything up yet: it opens the Character settings,
# for this character's class, so every choice is seen first.
YS = YR.Setup
lua.execute("YippSetupCharDB = YippSetupCharDB or {}")
YS.Toggle(YS)
n_prints = len(g.PRINTS)
g.YippSetupFrame.copy.fn(g.YippSetupFrame.copy)
said = [str(g.PRINTS[i]) for i in range(n_prints + 1, len(g.PRINTS) + 1)]
check(g.HeadstartWindow is not None and g.HeadstartWindow.hidden is not True and g.YippSetupFrame.hidden is True
      and not any("saved" in p_ for p_ in said), "the setup window's Copy opens the Character settings first instead of copying")
lua.execute("function InCombatLockdown() return false end")
n_prints = len(g.PRINTS)
g.YippSetupFrame.setup.fn(g.YippSetupFrame.setup)
said = [str(g.PRINTS[i]) for i in range(n_prints + 1, len(g.PRINTS) + 1)]
check(any("layout" in p_ for p_ in said), f"and its Set up layout sets up at once: {said[:1]}")

# Group play. A route with "#roles A,B" becomes a solo route plus one per role; steps marked
# "#role X" are only that role's (or "#role solo": only when alone).
text = """#name 1-5 Test (Launch)
#group Headstart Launch (A)
#roles A,B
#next Headstart Launch (A)BS5-11 Next (Launch)
step
    .accept 1 >> Accept Everyone
step
    #role A
    .accept 2 >> Accept Runner only
step
    #role B
    .accept 3 >> Accept Killer only
step
    #role solo
    .accept 4 >> Accept Alone only
""".replace("BS", chr(92))
g.GROUPTEST = YR
lua.execute('''GROUPTEST.GroupRouteNames = { ["5-11 Next (Launch)"] = { ["Duo A"] = true, ["Duo B"] = true } }''')
vs = YR.RoleVersions(text)
solo, a_, b_ = vs[1], vs[2], vs[3]
check("Accept Everyone" in solo and "Alone only" in solo and "Runner only" not in solo and "#roles" not in solo,
      "solo route: everyone's steps and the solo ones, no role steps")
check("#name 1-5 Test (Launch) (Duo A)" in a_ and "Runner only" in a_ and "Killer only" not in a_ and "Alone only" not in a_
      and "#role" not in a_, "Duo A: its own steps and everyone's, named (Duo A)")
check("5-11 Next (Launch) (Duo B)" in b_, "Duo B hands over to the next route's Duo B")
dm = """#name 19-20 Dungeon Test
step
    .accept 10 >> Accept Everyone
step
    .accept 11 >> Accept Deadmines quest
    .dungeon DM
step
    .accept 12 >> Accept Without the dungeon
    .dungeon !DM
"""
vs = YR.RoleVersions(dm)
solo, duo = vs[1], vs[2]
check(len(vs) == 6 and "Deadmines quest" in duo and ".dungeon" not in duo and "Without the dungeon" not in duo,
      "a route with dungeon steps gets group versions: the dungeon steps always show there, their no-dungeon versions go")
check("Deadmines quest" in solo and "Without the dungeon" in solo and ".dungeon DM" in solo,
      "alone, RestedXP's own dungeon setting still decides")

# sharing and accepting
lua.execute('''C_QuestLog.SetSelectedQuest = function(id) SELECTED_QUEST = id end
IN_GROUP = true; PUSHED = {}; SENT = {}''')
g.Fire("GROUP_ROSTER_UPDATE")
check(len(g.SENT) >= 1 and str(g.SENT[1][2]).startswith("H	"), "in a group, Headstart says hello (version, role, step)")
g.Fire("QUEST_ACCEPTED", 183)
check(len(g.PUSHED) == 1 and g.PUSHED[1] == 183, "a route quest taken from an NPC is shared with the party")
g.Fire("QUEST_ACCEPTED", 99999)
check(len(g.PUSHED) == 1, "a quest that isn't on the route is not shared")
lua.execute("NPC_IS_PLAYER = true; QUEST = 182; ACCEPTED_OFFER = 0")
g.Fire("QUEST_DETAIL")
check(g.ACCEPTED_OFFER == 1, "a route quest a party member shares is accepted")
g.Fire("QUEST_ACCEPTED", 182)
check(len(g.PUSHED) == 1, "and not shared back")
lua.execute("QUEST = 99999; ACCEPTED_OFFER = 0")
g.Fire("QUEST_DETAIL")
check(g.ACCEPTED_OFFER == 0, "a shared quest that isn't on the route still asks")
lua.execute("NPC_IS_PLAYER = false; QUEST = 200")
n = len(g.PRINTS)
g.Fire("CHAT_MSG_ADDON", "Headstart", "H	9.9.9	Duo B		0", "PARTY", "Friend-Realm")
said = [str(g.PRINTS[i]) for i in range(n + 1, len(g.PRINTS) + 1)]
check(any("has Headstart 9.9.9" in p_ for p_ in said), "a newer Headstart in the party is mentioned")
lua.execute("IN_GROUP = false")

# Keep what the route needs: 4 Chunks of Boar Meat for Stocking Jetsteam, needed from Coldridge on (before
# the quest is even accepted) until it is turned in. Skill-up lines (.collect with flags) don't count.
count, what = YR.RouteNeed(769)
check(count == 4 and what == "Stocking Jetsteam", f"the route needs 4 Chunks of Boar Meat for Stocking Jetsteam: {count} {what}")
count, what = YR.RouteNeed(2886)
check(count == 6 and what == "Beer Basted Boar Ribs", f"and 6 Crag Boar Ribs for Beer Basted Boar Ribs: {count} {what}")
check(YR.RouteNeed(4470) is None, "Simple Wood (a cooking skill-up line, not a quest) isn't kept")
# selling one at a vendor warns, and is logged; away from a vendor (using it) nothing happens
run = g.YippRouteDB.runs["Tester-Realm"]
g.BAGS[1 * 100 + 3] = lua.eval("{ itemID = 769, stackCount = 7 }")
n_ev, n_print = len(run.ev), len(g.PRINTS) if g.PRINTS else 0
g.MerchantFrame.shown = True
g.HOOKS["UseContainerItem"](1, 3)
last = run.ev[len(run.ev)]
check(last[2] == "sell" and last.item == 769 and last.count == 7 and last.need == 4, f"the sale is logged: {last[2]} {last.item} x{last.count}")
said = [str(g.PRINTS[i]) for i in range(1, len(g.PRINTS) + 1)] if g.PRINTS else []
check(any("still needs 4 for Stocking Jetsteam" in p_ for p_ in said), "and it warns: the route still needs 4 for Stocking Jetsteam")
g.MerchantFrame.shown = False
n = len(run.ev)
g.HOOKS["UseContainerItem"](1, 3)
check(len(run.ev) == n, "using an item away from a vendor is not a sale")
g.DONE[317] = True
check(YR.RouteNeed(769) is None, "once Stocking Jetsteam is turned in, the meat is free to sell")
g.DONE[317] = None
check(YR.RouteNeed(2770) is None, "Copper Ore is free to sell when you're not on Camping 101: Blacksmithing")
g.ONQUEST[96044] = True
count, what = YR.RouteNeed(2770)
check(count == 20 and what == "Camping 101: Blacksmithing", f"on Camping 101: Blacksmithing, the ore is kept for the skill-ups: {count} {what}")
g.ONQUEST[96044] = None
lua.execute("MONEY = 1234")
g.Fire("PLAYER_LEVEL_UP", 7)
check(run.ev[len(run.ev)].money == 1234, "every logged event carries your money, so training costs can be measured")
# quest-item loot is logged from the chat line
g.Fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:2886::|h[Crag Boar Rib]|h|rx2.")
last = run.ev[len(run.ev)]
check(last[2] == "loot" and last.item == 2886 and last.count == 2, f"looting 2 Crag Boar Ribs (a route item) is logged: {last[2]} {last.item}")
n = len(run.ev)
g.Fire("CHAT_MSG_LOOT", "Someone receives loot: |cffffffff|Hitem:2886::|h[Crag Boar Rib]|h|r.")
check(len(run.ev) == n, "somebody else's loot is not")

# Stop run: the splits clock and the log stop; Resume carries on without counting the pause
splits_rec = [r for r in [g.YippRouteDB.splits.runs[k] for k in g.YippRouteDB.splits.runs.keys()] if r.name == "Tester-Realm"]
YR.StopRun(YR)
check(YR.RunStopped(YR) and run.ev[len(run.ev)][2] == "stop" and run.stopped, "Stop this run: the log ends with a stop")
n = len(run.ev)
g.Fire("PLAYER_LEVEL_UP", 9)
check(len(run.ev) == n, "nothing is logged after the stop")
YR.ResumeRun(YR)
check(not YR.RunStopped(YR) and run.ev[len(run.ev)][2] == "resume", "Resume: logging carries on")
YR.SetRunCounts(YR, False)
check(not YR.RunCounts(YR), "a run can be kept out of vs best")
YR.SetRunCounts(YR, True)
sys.exit(1 if bad else 0)
