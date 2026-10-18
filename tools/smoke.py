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
function InCombatLockdown() return false end
function IsShiftKeyDown() return false end   -- (a part that asks it must not fail for want of it)
function StopCinematic() end
C_UnitAuras = { GetAuraDataByIndex = function() return nil end }   -- no buffs: the camp HUD rests
SHOTS = 0
function Screenshot() SHOTS = SHOTS + 1 end   -- the QoL screenshot at a ding
function GetInventoryItemDurability() return nil end
function GetInventoryItemID() return nil end
function GetInventoryItemTexture() return nil end
function UnitExists() return false end   -- Quick group's bar: no target
function UnitIsGroupLeader() return false end
function UnitIsGroupAssistant() return false end
function GetInventoryItemLink() return nil end
KNOWN_SPELLS = KNOWN_SPELLS or {}
function IsPlayerSpell(id) return KNOWN_SPELLS[id] == true end
-- WoW's bit library, which plain Lua 5.1 hasn't got
bit = bit or {
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
function UnitHealth() return 80 end
function UnitHealthMax() return 100 end
function UnitPower() return 40 end
function UnitPowerMax() return 100 end
function UnitPowerType() return 0, "MANA" end
function UnitRace() return "Dwarf", "Dwarf" end
function UnitLevel() return 1 end
GUID = "Player-A"
HOOKS = {}
Minimap = CreateFrame()
UIParent = CreateFrame()
function ReloadUI() RELOADED = true end
function RequestTimePlayed() ASKED_PLAYED = (ASKED_PLAYED or 0) + 1 end
UISpecialFrames, StaticPopupDialogs = {}, {}
function HasAction() return false end
function GetNumMacros() return 0, 0 end        -- (no macros: Character setup's first look keeps the bars, and none)
tinsert = table.insert
function StaticPopup_Show(which) POPUP = which end
GameTooltip = setmetatable({}, { __index = function() return function() end end })
function hooksecurefunc(a, b, c) if c then HOOKS[b] = c else HOOKS[a] = b end end
-- bags (BAGS[bag * 100 + slot] = { itemID, stackCount }) and a vendor window
BAGS = {}
C_Container = { UseContainerItem = function() end, GetContainerNumSlots = function() return 16 end, GetContainerItemInfo = function(bag, slot) return BAGS[bag * 100 + slot] end, GetContainerItemLink = function(bag, slot) local b = BAGS[bag * 100 + slot] return type(b) == "table" and b.hyperlink or nil end,
    GetContainerItemID = function(bag, slot) local i = BAGS[bag * 100 + slot] return i and i.itemID end }
MerchantFrame = { shown = false, IsShown = function(self) return self.shown end }
DONE = {}
-- the party: SENT collects addon messages; IN_GROUP / PARTY_NAMES say who is in it
SENT = {}
IN_GROUP = false
PARTY_NAMES = {}
C_ChatInfo = { SendChatMessage = function() end, RegisterAddonMessagePrefix = function() return true end,
               SendAddonMessage = function(prefix, msg, channel) table.insert(SENT, { prefix, msg, channel }) end }
function IsInGroup() return IN_GROUP end
function UnitInParty(n) return PARTY_NAMES[n] or false end
function UnitInRaid() return false end
function Ambiguate(n) return n end
function strsplit(sep, s, pieces)        -- pieces: at most that many, the last one the rest (as the game's does)
    local out, i = {}, 1
    while true do
        local j = s:find(sep, i, true)
        if not j or (pieces and #out + 1 >= pieces) then out[#out + 1] = s:sub(i) break end
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
UnitOnTaxi = UnitOnTaxi or function() return false end
UnitIsAFK = UnitIsAFK or function() return false end
IsSwimming = IsSwimming or function() return false end
IsResting = IsResting or function() return false end
IsMounted = IsMounted or function() return false end
IsInInstance = IsInInstance or function() return false end
UnitPosition = UnitPosition or function() return nil end
GetRealZoneText = GetRealZoneText or function() return "Teldrassil" end
IsInRaid = IsInRaid or function() return false end
GetNumGroupMembers = GetNumGroupMembers or function() return 0 end
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
# The routes are not part of Headstart: they are the routes addon beside it (Headstart_Routes, private),
# which loads first and queues its guides for Guides.lua. The route tests below need it.
ROUTES = os.path.join(os.path.dirname(ROOT), "Headstart_Routes")
if not os.path.isdir(ROUTES):
    print("SKIPPED: these tests need the routes addon in " + ROUTES)
    sys.exit(0)
sys.path.insert(0, os.path.join(ROUTES, "tools"))      # check_deathskips, check_levels
RNS = lua.table()
for l in open(os.path.join(ROUTES, "Headstart_Routes.toc"), encoding="utf-8"):
    f = l.strip().replace(chr(92), "/")
    if f.endswith(".lua") and not f.startswith("#"):
        lua.eval("function(c, n) return assert(loadstring(c, n)) end")(open(os.path.join(ROUTES, f), encoding="utf-8").read(), f)("Headstart_Routes", RNS)
# every file the .toc loads, in its order
# (not the libraries in Libs/: LibStub, LibDataBroker and LibDBIcon are other people's, and need the game)
TOC = [l.strip().replace(chr(92), "/") for l in open(os.path.join(ROOT, "Headstart.toc"), encoding="utf-8")
       if l.strip().endswith(".lua") and not l.startswith("#") and not l.startswith("Libs")]
# and the window's addon (Headstart_Options, load on demand in the game), loaded after it
for sub in ("Headstart_Setup", "Headstart_Options"):
    TOC += [sub + "/" + l.strip().replace(chr(92), "/")
            for l in open(os.path.join(ROOT, sub, sub + ".toc"), encoding="utf-8")
            if l.strip().endswith(".lua") and not l.startswith("#")]
for f in TOC:
    chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
    chunk("Headstart", YR)
YR.QUEST_IDS = lua.eval("{ route = { 179 }, new = { 96628, 5 }, rest = { 99999 } }")
g = lua.globals()
g.YippRouteDB = lua.table(routes=True)   # the routes switch on, as for anyone who turned it on
g.Fire("ADDON_LOADED", "Headstart")
g.Fire("PLAYER_LOGIN")           # the login: every part that is wanted comes on (the log, the splits, the group...)

bad = 0
def check(ok, what):
    global bad
    bad += not ok
    print(("ok  " if ok else "FAIL"), what)

# --- scan ---
g.SlashCmdList.HEADSTART("scan")
for _ in range(80):              # 8 seconds of ticks, answering whatever was asked
    g.RunTickers(); g.Answer(); g.NOW += 0.1
s = g.HeadstartScanDB.scan         # the window addon's own saved file, not the account's
check(g.YippRouteDB.scan is None, "what the scan found is not in the account's file (read at every login)")
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
YR.LogSample()                   # the log is read on the next sample (two seconds at most), not per event
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
check(run.track[1][7] == 0, f"position sample carries flags (not in combat): {run.track[1][7]}")

# standing still: the samples in between are left out, one kept every 30 s; moving off writes the last
# still one first, so the move starts 2 s after it
n0, clock0 = len(run.track), g.CLOCK
for _ in range(20):                      # 40 s on one spot, a sample every 2 s
    g.CLOCK += 2
    g.RunTickers()
still = [run.track[i][1] for i in range(n0 + 1, len(run.track) + 1)]
check(len(still) <= 2 and all(b - a <= 30 for a, b in zip([run.track[n0][1]] + still, still)),
      f"40 s standing still: {len(still)} samples written, none more than 30 s apart ({still})")
g.CLOCK += 2
lua.execute("C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.31, 0.712 end } end")
g.RunTickers()
last2 = [run.track[i] for i in (len(run.track) - 1, len(run.track))]
check(last2[1][1] - last2[0][1] == 2 and last2[1][3] != last2[0][3],
      f"moving off: the last still sample, then the move 2 s later ({last2[0][1]}, {last2[1][1]})")
g.CLOCK += 2
g.RunTickers()
check(run.track[len(run.track)][1] - run.track[len(run.track) - 1][1] == 2, "moving: every sample kept")
lua.execute("C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.2993, 0.712 end } end")
g.CLOCK = clock0                         # the tests below go on from the turn-in's second
# a log from before: thinned once by the same rule, every move and every gap over 30 s kept
old = lua.eval("""{ {0,1,5,5,1,0,0}, {2,1,5,5,1,0,0}, {4,1,5,5,1,0,0}, {6,1,5,5,1,0,0}, {8,1,6,5,1,0,0},
    {10,1,7,5,1,0,0}, {12,1,7,5,1,0,0}, {500,1,7,5,1,0,0}, {502,1,7,5,1,0,0} }""")
dropped = YR.SlimTrack(old)
times = [old[i][1] for i in range(1, len(old) + 1)]
check(times == [0, 6, 8, 10, 12, 500, 502], f"an old log thinned: {dropped} left out, kept {times}")

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
check(kill.mob is None and kill.mlvl is None, "a kill with no dead target: no mob written")
# a kill of your target: its name, level and kind go with it
lua.execute("""
KEPT = { UnitExists, UnitLevel, UnitIsDead, UnitClassification }
function UnitExists(u) return u == "target" end
function UnitLevel(u) return u == "target" and 35 or 1 end
function UnitIsDead() return true end
function UnitClassification() return "elite" end
""")
g.CLOCK += 10; g.XP = 480; g.Fire("PLAYER_XP_UPDATE")
kill = [run.ev[i] for i in range(1, len(run.ev) + 1) if run.ev[i][2] == "kill"][-1]
check(kill.mob == "Sten Stoutarm" and kill.mlvl == 35 and kill.elite == "elite",
      f"a kill of your target: {kill.mob}, level {kill.mlvl}, {kill.elite}")
lua.execute('function UnitClassification() return "normal" end')
g.CLOCK += 10; g.XP = 490; g.Fire("PLAYER_XP_UPDATE")
kill = [run.ev[i] for i in range(1, len(run.ev) + 1) if run.ev[i][2] == "kill"][-1]
check(kill.mlvl == 35 and kill.elite is None, "a normal mob: no kind written")
# the target is gone by the time the XP comes: the mob noted when the fight began is taken, once
lua.execute("""
function UnitIsDead() return false end
function UnitCanAttack() return true end
function UnitClassification() return "rare" end
""")
g.CLOCK += 10; g.COMBAT = True; g.Fire("PLAYER_REGEN_DISABLED")
lua.execute("function UnitExists() return false end")
g.XP = 500; g.Fire("PLAYER_XP_UPDATE")
kill = [run.ev[i] for i in range(1, len(run.ev) + 1) if run.ev[i][2] == "kill"][-1]
check(kill.mob == "Sten Stoutarm" and kill.mlvl == 35 and kill.elite == "rare",
      f"no dead target at the XP: the mob the fight began on ({kill.mob}, {kill.mlvl}, {kill.elite})")
g.XP = 510; g.Fire("PLAYER_XP_UPDATE")
kill = [run.ev[i] for i in range(1, len(run.ev) + 1) if run.ev[i][2] == "kill"][-1]
check(kill.mob is None, "a second kill in the same fight: no name guessed")
g.COMBAT = False; g.Fire("PLAYER_REGEN_ENABLED")
lua.execute("UnitExists, UnitLevel, UnitIsDead, UnitClassification = KEPT[1], KEPT[2], KEPT[3], KEPT[4]")

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
# ... and at the Spirit Healer, Headstart accepts the resurrection of a death skip even when RestedXP's
# step has already gone (it ends itself on entering Kharanos, where the healer is); never another death's
lua.execute('''
YippRouteDB.deathSkipRelease = true
GHOST, ACCEPTS = false, 0
function UnitIsGhost() return GHOST end
function AcceptXPLoss() ACCEPTS = ACCEPTS + 1 end
RXP.currentGuide.steps = { { active = true, elements = { { tag = "goto" }, SKIP } } }
''')
g.Fire("PLAYER_DEAD")
lua.execute('GHOST = true; RXP.currentGuide.steps = { { active = true, elements = { { tag = "goto" } } } }')
g.Fire("CONFIRM_XP_LOSS")
check(g.ACCEPTS == 1, "a death skip whose step has gone: accepted at the Spirit Healer all the same")
lua.execute('GHOST = false')
g.Fire("PLAYER_UNGHOST")
g.Fire("PLAYER_DEAD")
lua.execute('GHOST = true')
g.Fire("CONFIRM_XP_LOSS")
check(g.ACCEPTS == 1, "any other death: left to you at the healer")
lua.execute('GHOST = false; function UnitIsGhost() return false end')
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
QUALITY = {}
function GetQuestItemInfo(_, i) return "item" .. CHOICES[i], 0, 1, QUALITY[CHOICES[i]] or 1, true, CHOICES[i] end
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
lua.execute("QUEST = 202; QUALITY = { [3] = 2 }")
check(g.Pick(3, 2, 1) is None, "a green among the rewards: you choose")
lua.execute("QUEST = 200; QUALITY = { [8] = 2 }")
check(g.Pick(1, 2, 8) == 3, "... unless you picked for that quest by hand before")
lua.execute("QUEST = 202; QUALITY = { [3] = 2 }; YippRouteDB.rewardClasses.PALADIN.greenStop = false")
check(g.Pick(3, 2, 1) == 3, "the green stop is a setting")
lua.execute("YippRouteDB.rewardClasses.PALADIN.greenStop = true; QUALITY = {}")
# RestedXP's automation: Shift keeps it out of the window you open; a green keeps its built-in picks out
lua.execute('''
LATER = {}
local after = C_Timer.After
C_Timer.After = function(_, fn) table.insert(LATER, fn) end
local function Panel() local p = { hooks = {} } function p:HookScript(_, fn) table.insert(self.hooks, fn) end return p end
GossipFrame, QuestFrameDetailPanel, QuestFrameRewardPanel = Panel(), Panel(), Panel()
RXP = RXP or {}
RXP.settings = { profile = { enableQuestAutomation = true, enableQuestRewardAutomation = true } }
YR_HOOK = true
''')
YR.HookQuestWindows(YR)
lua.execute("SHIFT = true; for _, fn in ipairs(QuestFrameDetailPanel.hooks) do fn() end")
check(g.RXP.settings.profile.enableQuestAutomation is False, "Shift: RestedXP's quest automation is off for that window")
lua.execute("for _, fn in ipairs(LATER) do fn() end LATER = {}")
check(g.RXP.settings.profile.enableQuestAutomation is True, "... and back on right after")
lua.execute("SHIFT = false; CHOICES = { 3, 2 }; QUALITY = { [3] = 2 }; for _, fn in ipairs(QuestFrameRewardPanel.hooks) do fn() end")
check(g.RXP.settings.profile.enableQuestRewardAutomation is False and g.RXP.settings.profile.enableQuestAutomation is True,
      "a green: RestedXP's built-in reward pick waits, the rest of its automation doesn't")
lua.execute("for _, fn in ipairs(LATER) do fn() end LATER = {}; QUALITY = {}; C_Timer.After = function(_, fn) fn() end")
check(g.RXP.settings.profile.enableQuestRewardAutomation is True, "... and is back on right after")
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
# the last few lines: the ding also brings the QoL reminders (trainer, talents) after this one
said = " / ".join(g.PRINTS[i] for i in range(max(1, len(g.PRINTS) - 3), len(g.PRINTS) + 1))
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
check(f.rows[2][5].text == "|cff40ff40-0:50|r", f"± level: level 2 alone was 50 s faster than A's: {f.rows[2][5].text}")
check(f.rows[0][5].text == "|cff999999± level|r", f"and its heading: {f.rows[0][5].text}")
xp_now = lua.eval("UnitXP('player')")
check(f.xph.text.endswith(f"   {xp_now}|cff999999 / 400|r"), f"XP/hr line ends with this level's XP of what it takes: {f.xph.text}")
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
# Cleaning up the logs: a list by last played, one deleted (this character's starts again), old ones at login
lua.execute('''YippRouteDB.runs["Gone-Realm"] = { started = 10, ev = { { 20 } }, track = { { 30, 1, 0, 0, 5, 0, 0 } } }''')
summary = YR.LogSummary()
keys = [summary[i].key for i in range(1, len(summary) + 1)]
lasts = [summary[i].last for i in range(1, len(summary) + 1)]
check(set(keys) == {"Tester-Realm", "Gone-Realm", "Old-Realm"} and lasts == sorted(lasts, reverse=True)
      and keys[-1] == "Gone-Realm", f"every character's log, the one played last first: {keys}")
check(YR.DeleteLog("Gone-Realm") and g.YippRouteDB.runs["Gone-Realm"] is None, "a character's log deleted")
mine = g.YippRouteDB.runs["Tester-Realm"]
check(YR.DeleteLog("Tester-Realm") and g.YippRouteDB.runs["Tester-Realm"] is not None
      and len(g.YippRouteDB.runs["Tester-Realm"].track) == 0, "this character's: deleted, and a new log from now")
g.RunTickers()
check(len(g.YippRouteDB.runs["Tester-Realm"].track) == 1, "and recording goes on into the new one")
new = g.YippRouteDB.runs["Tester-Realm"]
new.ev, new.track = mine.ev, mine.track            # the tests below read this character's log
lua.execute('''YippRouteDB.runs["Gone-Realm"] = { started = 10, ev = {}, track = {} }''')
check(YR.PruneLogs(0) == 0 and g.YippRouteDB.runs["Gone-Realm"] is not None, "0 days: nothing deleted")
g.CLOCK += 40 * 86400                    # forty days on
n = YR.PruneLogs(30)
g.CLOCK -= 40 * 86400
check(g.YippRouteDB.runs["Gone-Realm"] is None and g.YippRouteDB.runs["Tester-Realm"] is not None,
      f"30 days: the old logs go ({n}), never this character's")
# old logs that are still used are kept: a fastest run's, and one a route of your own was saved from
lua.execute('''KEEP_SPLITS, KEEP_MINE, KEEP_DAYS = YippRouteDB.splits, YippRouteDB.myRoutes, YippRouteDB.logKeepDays
    YippRouteDB.runs["Fast-Realm"] = { started = 10, ev = {}, track = {} }
    YippRouteDB.runs["Slow-Realm"] = { started = 10, ev = {}, track = {} }
    YippRouteDB.runs["Source-Realm"] = { started = 10, ev = {}, track = {} }
    YippRouteDB.splits = { runs = {
        a = { name = "Fast-Realm", class = "MAGE", race = "Gnome", levels = { [2] = 100, [3] = 300 } },
        b = { name = "Slow-Realm", class = "MAGE", race = "Gnome", levels = { [2] = 200, [3] = 500 } },
        c = { name = "Source-Realm", class = "MAGE", race = "Human", levels = { [2] = 900 } } } }
    YippRouteDB.myRoutes = { human = { parts = {}, from = "Source-Realm" } }''')
check(YR.LogKeepDays() == 30, "never set: logs go after 30 days unplayed")
g.CLOCK += 40 * 86400
n = YR.PruneLogs(YR.LogKeepDays())
check(n == 1 and g.YippRouteDB.runs["Slow-Realm"] is None, f"an old log nothing uses goes ({n})")
check(g.YippRouteDB.runs["Fast-Realm"] is not None, "the fastest run's log is kept, however old")
check(g.YippRouteDB.runs["Source-Realm"] is not None, "and the log a route of your own was saved from")
lua.execute('''YippRouteDB.runs["Slow-Realm"] = { started = 10, ev = {}, track = {} }
    YippRouteDB.myRoutes = { dwarfgnome = { parts = {} } }''')
check(YR.PruneLogs(30) == 1 and g.YippRouteDB.runs["Slow-Realm"] is not None and g.YippRouteDB.runs["Source-Realm"] is None,
      "a route saved before its source was kept: every log of that race stays, the others go")
g.YippRouteDB.logKeepDays = 0
check(YR.LogKeepDays() == 0 and YR.PruneLogs(YR.LogKeepDays()) == 0, "0 days set: never deleted")
g.CLOCK -= 40 * 86400
lua.execute('''YippRouteDB.splits, YippRouteDB.myRoutes, YippRouteDB.logKeepDays = KEEP_SPLITS, KEEP_MINE, KEEP_DAYS
    for _, k in ipairs({ "Fast-Realm", "Slow-Realm", "Source-Realm" }) do YippRouteDB.runs[k] = nil end''')
lua.execute('''YippRouteDB.runs["Old-Realm"] = { track = { {0,1,0,0,1,0} } }''')
# The run to beat has a time for every level: a faster one first seen part-way (only a level-8 total)
# would leave every "vs best" cell empty.
lua.execute('''SAVED_RUNS = YippRouteDB.splits.runs
YippRouteDB.splits.runs = {
  partial = { name = "Late-Realm", levels = { [8] = 3485 }, elapsed = 9000 },
  full = { name = "Full-Realm", levels = { [1] = 0, [2] = 116, [3] = 506, [4] = 952, [5] = 1428, [6] = 1868, [7] = 2925, [8] = 3486 } },
  short = { name = "Short-Realm", levels = { [1] = 0, [2] = 100, [3] = 400 } } }''')
best = YR.SplitsBest()
check(best is not None and best.name == "Full-Realm", f"best run is the fully timed one, not a faster partial one: {best and best.name}")
# What to beat is the fastest at each level, not one run: a run that stopped at 11 was quicker to 10
lua.execute('''YippRouteDB.splits.runs = {
  far = { name = "Radaid", levels = { [1] = 0, [9] = 5000, [10] = 6137, [11] = 7000, [13] = 9000 } },
  quick = { name = "Munix", levels = { [1] = 0, [9] = 4800, [10] = 5337, [11] = 6900 } },
  skip = { name = "Missed a quest", noBest = true, levels = { [1] = 0, [10] = 100 } } }''')
fast = YR.SplitsFastest()
check(fast.levels[10] == 5337 and fast.levels[13] == 9000,
      f"level 10 against Munix's 5337, not the furthest run's 6137; 13 still Radaid's: {fast.levels[10]}, {fast.levels[13]}")
check(fast.segs[10] == 537 and fast.segs[11] == 863,
      f"± level: the fastest single level 9-10 (537) and 10-11 (Radaid's 863): {fast.segs[10]}, {fast.segs[11]}")
# Compare with: any run, your class, or your class and race (Dwarf and Gnome as one)
lua.execute('''YippRouteDB.splits.runs = {
  pal = { name = "Pal", class = "PALADIN", race = "Dwarf", levels = { [1] = 0, [10] = 6000 } },
  gnome = { name = "Gnome", class = "PALADIN", race = "Gnome", levels = { [1] = 0, [10] = 5900 } },
  rogue = { name = "Rogue", class = "ROGUE", race = "NightElf", levels = { [1] = 0, [10] = 4000 } },
  human = { name = "Human", class = "PALADIN", race = "Human", levels = { [1] = 0, [10] = 5000 } },
  old = { name = "Old", class = "PALADIN", levels = { [1] = 0, [10] = 3000 } } }
  UnitRace = function() return "Dwarf", "Dwarf" end''')
check(YR.SplitsFastest().levels[10] == 3000, "any run: the fastest of all (the default)")
g.YippRouteDB.splitsCompare = "class"
check(YR.SplitsFastest().levels[10] == 3000, "same class: the rogue is out, the old paladin run counts")
g.YippRouteDB.splitsCompare = "race"
check(YR.SplitsFastest().levels[10] == 5900, "class and race: a Gnome paladin counts for a Dwarf, a Human and an unplaced run don't")
g.YippRouteDB.splitsCompare = None
lua.execute("YippRouteDB.splits.runs = SAVED_RUNS")

# Shipped guides: both handed to RestedXP at login; a guide splits into steps and joins back unchanged;
# a saved edit replaces the shipped text; reverting brings it back.
names = [str(g.REGISTERED[i]).split("#name ", 1)[1].splitlines()[0] for i in range(1, len(g.REGISTERED) + 1)]
solo = [n_ for n_ in names if "(Duo" not in n_ and "(Trio" not in n_]
check(len(solo) == 51 and len(names) == 51, f"51 routes registered with RestedXP (starting zones, 6-30 and Polestar 12-60), solo only while playing solo: {len(names)}")
lua.execute("YippSetupCharDB = YippSetupCharDB or {}")
YR.SetRole(YR, "Duo B")
names = [str(g.REGISTERED[i]).split("#name ", 1)[1].splitlines()[0] for i in range(1, len(g.REGISTERED) + 1)]
check("1-6 Northshire (Launch) (Duo B)" in names and "16-19 Darkshore (Duo B)" in names and not any("Trio" in n_ or "Duo A" in n_ for n_ in names),
      f"picking Duo B registers that role's versions only: {len(names) - 23} of them")
YR.SetRole(YR, "solo")
dwarf = YR.RoutesFor(YR, "Dwarf")
check(dwarf["coldridge"] and dwarf["dunmorogh"] and dwarf["16_19_darkshore"] and not dwarf["6_11_elwynn_forest"] and not dwarf["northshire"],
      "a Dwarf's routes: Coldridge on through Darkshore, not Human Elwynn or Northshire")
# The routes switch: off for a new install (no runs, no edited routes), kept on for an account that played them
lua.execute("SAVED_ROUTES_DB = YippRouteDB; YippRouteDB = { runs = {}, custom = {} }")
check(not YR.RoutesOn(), "routes switch: off for a new install")
n_reg = len(g.REGISTERED)
YR.RegisterGuides(YR)
check(len(g.REGISTERED) == n_reg and len(list(YR.RoutesFor(YR, "Dwarf").keys())) == 0,
      "off: nothing handed to RestedXP, and no routes for a race (nothing kept or bought for one)")
lua.execute("YippRouteDB = { runs = { ['Old-Realm'] = {} } }")
check(YR.RoutesOn() and g.YippRouteDB.routes == True, "an account with run logs keeps its routes on (decided once, stored)")
lua.execute("YippRouteDB = { routes = false, runs = { ['Old-Realm'] = {} } }")
check(not YR.RoutesOn(), "turned off stays off")
YR.SetRoutesOn(True)
check(YR.RoutesOn(), "turned on: on for every character of the account")
lua.execute("YippRouteDB = SAVED_ROUTES_DB")
lua.execute("SAVED_RXP2 = RXP; RXP = { icons = { goto = 'smudge', explore = 'smudge', home = 'house' } }")
YR.RxpIcons()
check("Headstart" in str(g.RXP.icons["goto"]) and "pin:0:0" in str(g.RXP.icons["goto"]) and "pin" in str(g.RXP.icons["explore"]) and g.RXP.icons["home"] == "house",
      "RestedXP's go-to icon is our map pin (and nothing else is touched)")
lua.execute("RXP = SAVED_RXP2")
check(not dwarf["dunmorogh_elwynn"] and not dwarf["6_11_elwynn_dwarf_gnome"],
      "Coldridge's second way on (Elwynn at 6) is an option: not a Dwarf's route until RestedXP has it loaded")
lua.execute('SAVED_RXP = RXP; RXP = { currentGuide = { name = "6-11 Elwynn (Dwarf/Gnome)" } }')
dwarf = YR.RoutesFor(YR, "Dwarf")
check(dwarf["dunmorogh_elwynn"] and dwarf["6_11_elwynn_dwarf_gnome"] and dwarf["11_13_loch_modan"] and dwarf["dunmorogh"],
      "on it, its routes count too")
lua.execute("RXP = SAVED_RXP")
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
lua.execute("""SEEN_ICONS = {}
local F = getmetatable(CreateFrame())
local set = F.SetText
F.SetText = function(self, t)
    if type(t) == "string" and t:find("|T%d+:18") then SEEN_ICONS[#SEEN_ICONS + 1] = t end
    set(self, t)
end""")
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
YR.ToggleWindow(YR, "instances")         # the instances page builds and fills
# the tracker's page is its settings, the switch first; the runs are a window of their own
_inst = [e.label for e in YR.SettingsIndex().values() if e.key == "instances"]
check("Instance tracker" in _inst and "Instance log" in _inst and "Hourly limit" in _inst,
      f"the Instance tracker page: its switch, the log's button and the limits, nothing behind a Settings chip ({len(_inst)})")
YR.InstanceLogShow()
check(g.HeadstartInstanceLog is not None and g.HeadstartInstanceLog.hidden is False, "the instance log opens in a window of its own")
YR.InstanceLogToggle()
check(g.HeadstartInstanceLog.hidden is True, "and shuts again (/headstart instances, the on-screen icon)")
check(len(g.SEEN_ICONS) == 0, "Settings builds a page the first time it's opened: the trainer's isn't yet")
for key in ("camps", "bags", "vendors", "group", "quests", "reminders", "gear", "trinkets", "xpbar", "character", "trainer", "route"):
    YR.ShowSettingsTab(YR, key)        # every page builds, and fills, without an error
icons = [g.SEEN_ICONS[i] for i in range(1, len(g.SEEN_ICONS) + 1)]
check(any("Seal of" in t or "Holy Light" in t for t in icons), f"trainer rows carry the spell's icon: {icons[:2]}")
# Find a setting: by a word in its name or details, on any page; picking one opens its page
found = YR.SettingsSearch("durability")
labels = [found[i].label for i in range(1, len(found) + 1)] if found else []
check(any("Durability" in l for l in labels) and all(found[i].key for i in range(1, len(found) + 1)),
      f"the search finds Durability warning, and knows its page: {labels}")
YR.SettingsGo(found[1])
check(g.YippRouteDB is not None and lua.eval("true"), "picking a result opens its page without an error")
check(YR.SettingsSearch("") is None, "an empty search shows the page again")
check(len(YR.SettingsSearch("zzqqxx") or []) == 0, "nothing matches: an empty list, no error")
# A card's master switch: the rows under it dim while it's off
lua.execute("""local F = getmetatable(CreateFrame()) F.SetAlpha = function(self, a) self.alpha = a end""")
g.YippRouteDB.restock = False
YR.ShowSettingsTab(YR, "vendors")
dimmed = lua.eval("""(function()
    local n = 0
    for _, f in ipairs(FRAMES) do if f.alpha == 0.40 then n = n + 1 end end
    return n end)()""")
check(dimmed > 0, f"Vendor restock off: its rows are dimmed ({dimmed})")
# the features stand on All features in the order of their cards on the page - within a group (Automation
# stands first, whatever pages its features are on)
_order = {}
for e in YR.SettingsIndex().values():
    _order.setdefault(e.key, {"top": [], "cards": []})["cards" if e.card else "top"].append(e.label)
_feats = {}
for group in YR.HomeFeatures().values():
    for i in range(2, len(list(group.values())) + 1):
        f = group[i]
        if f.get and f.set and not f.plain and f.section != "On this page":
            _feats.setdefault((group[1], f.page), []).append(f.section)
_wrong = []
for (_group, page), sections in _feats.items():
    cards = [c for c in _order.get(page, {}).get("cards", []) if c in sections]
    seen = []
    for sec in sections:
        if sec not in seen:
            seen.append(sec)
    if cards and seen != cards:
        _wrong.append((page, seen, cards))
check(not _wrong, f"on every page the top switches are in the order of their cards: {_wrong}")
# the card of a feature that is off stands under the cards of the ones that are on
def _card_y(page, label):
    return [e.y for e in YR.SettingsIndex().values() if e.key == page and e.card and e.label == label][0]
_sw = YR.SwingDB()
_was = (_sw.on, _sw.health, _sw.power)
_sw.on, _sw.health, _sw.power = True, None, None
YR.ShowSettingsTab(YR, "swing")
YR.RefreshWindow(YR)
_first = _card_y("swing", "Swing timer") > _card_y("swing", "Health and power bars")
_sw.on, _sw.health = False, True
YR.RefreshWindow(YR)
check(_first and _card_y("swing", "Health and power bars") > _card_y("swing", "Swing timer")
,
      "Combat bars: the swing timer's card first while it is on; turned off with the health bar on, the health and power card goes above it")
# off is off: a frame over the card's rows takes the mouse, so nothing in it can be changed
def _blocked(label):
    row = [e.row for e in YR.SettingsIndex().values() if e.key == "swing" and e.card and e.label == label][0]
    return row.block is not None and row.block.hidden is not True
check(_blocked("Swing timer") and not _blocked("Health and power bars"),
      "a card whose feature is off answers no click (the swing timer's, off here); one that is on does")
_sw.on, _sw.health, _sw.power = _was
YR.RefreshWindow(YR)
# a feature's switch is in the head of its own card (a block of switches at the top of the page sent you looking)
_idx = [e for e in YR.SettingsIndex().values() if e.key == "trinkets"]
check(not any(e.label == "On this page" for e in _idx) and any(e.card and e.label == "Trinket auto-swap" for e in _idx),
      "no block of switches at the top of a page: each card has its own")
# Cards fold. A page of several cards opens with every card open (it opened as a list of heads, with an
# "Open all" at the right - the owner, 2026-10-14); a click on a head folds that card and it is
# remembered; the cards under it move, and so does what a page keeps under its cards.
g.YippRouteDB.cardsOpen = None
YR.ShowSettingsTab(YR, "swing")
YR.RefreshWindow(YR)
_L = YR.SettingsLayout("swing")
def _hidden(page, card):
    return [e.row.hidden is True for e in YR.SettingsIndex().values() if e.key == page and not e.card and e.of and e.of.title == card]
def _heads(page):
    return sorted([e.y for e in YR.SettingsIndex().values() if e.key == page and e.card and e.of and e.label == e.of.title], reverse=True)
check(_L.AnyShut() is False and len(_hidden("swing", "Cast bar")) > 3 and not any(_hidden("swing", "Cast bar")),
      f"a page of several cards starts open: every setting in sight, nothing to press first ({len(_hidden('swing', 'Cast bar'))})")
_L.FoldAll(False)
_ys = _heads("swing")
check(len(_ys) == 3 and all(a - b == 54 for a, b in zip(_ys, _ys[1:])), f"folded, each head stands right under the one before ({_ys})")
_cast = [cd for cd in _L.cards.values() if cd.title == "Cast bar"][0]
_cast.head.fn()                     # a click on the folded card's head
check(g.YippRouteDB.cardsOpen["swing:Cast bar"] is None and not any(_hidden("swing", "Cast bar")) and _cast.shut is False,
      "a click on a folded card's head opens it: its rows are back")
_cast.head.fn()
_first = max(_L.cards.values(), key=lambda cd: cd.top + (cd.shift or 0))       # the card at the top of the page
_first.head.fn()
_ys2 = _heads("swing")
check(_first.span > 54 and _ys2[0] == _ys[0] and _ys[1] - _ys2[1] == _first.span - 54 and _ys[2] - _ys2[2] == _first.span - 54,
      f"an open card takes its room: the heads under it move down by what it grew ({_ys} to {_ys2}, {_first.span})")
_first.head.fn()
check(_heads("swing") == _ys, "and back up when it is folded again")
check(g.YippRouteDB.cardsOpen["swing:Cast bar"] is False and all(_hidden("swing", "Cast bar")), "clicked again: folded, and that is remembered")
found = YR.SettingsSearch("show out of range")
YR.SettingsGo(found[1])
check(g.YippRouteDB.cardsOpen["swing:Swing timer"] is None and found[1].row.hidden is not True,
      "the search opens the card of the setting it leads to")
_L.FoldAll(True)
check(_L.AnyShut() is False and not any(_hidden("swing", "Health and power bars")) and g.YippRouteDB.cardsOpen["swing:Cast bar"] is None,
      "every card open again, and none kept as folded")
YR.SettingsSearch("")
YR.ShowSettingsTab(YR, "recap")
_J = YR.SettingsLayout("recap")
check(_J.AnyShut() is None and not any(_hidden("recap", "Death recap")) and len(_hidden("recap", "Death recap")) > 2,
      "a page with one card: it is all there is on it, and it does not fold")
# /hs journey: with nothing after it (the window), and a made-up journey at a level
UnitRace = g.UnitRace
if UnitRace is None:
    lua.execute('function UnitRace() return "Dwarf", "Dwarf" end')
for _words, _want in (("journey", None), ("journey test", "Level 50"), ("journey test 60", "Level 60"), ("journey test 999", "Level 60")):
    g.SlashCmdList.HEADSTART(_words)
    _unit = g.HeadstartJourneyWindow.unit.text
    check(g.HeadstartJourneyWindow.hidden is False and (_want is None or _want in _unit), f"/hs {_words}: the window, {_want or 'your own journey'} ({_unit})")
g.HeadstartJourneyWindow.Hide(g.HeadstartJourneyWindow)
# The beta's banner at the top of All features: there in a test client, hidden for a week when asked,
# never on the live game
YR.ShowSettingsTab(YR, "home")
check(YR.BetaClient() is False and g.HeadstartBetaBanner is not None and g.HeadstartBetaBanner.hidden is True,
      "the live game: no banner about the beta's settings")
lua.execute("function IsBetaBuild() return true end")
YR.RefreshWindow(YR)
check(YR.BetaClient() is True and g.HeadstartBetaBanner.hidden is False, "a beta client: the banner says its settings stay in the beta")
lua.execute("IsBetaBuild = nil KEPT_REALM = GetRealmName GetRealmName = function() return 'Classic Beta PvP 2' end")
check(YR.BetaClient() is True, "and a realm with Beta in its name says the same where the game doesn't")
lua.execute("GetRealmName = KEPT_REALM function IsBetaBuild() return true end YippRouteDB.betaNoteUntil = time() + 7 * 86400")
YR.RefreshWindow(YR)
check(g.HeadstartBetaBanner.hidden is True, "Hide for a week: gone for now")
lua.execute("YippRouteDB.betaNoteUntil = time() - 1")
YR.RefreshWindow(YR)
check(g.HeadstartBetaBanner.hidden is False, "and back when the week is over: it is about something still to do")
lua.execute("IsBetaBuild = nil YippRouteDB.betaNoteUntil = nil")
YR.RefreshWindow(YR)
# /headstart transfer: the window to move your settings with, and what this account's settings are as a text
g.SlashCmdList.HEADSTART("transfer")
_text = YR.TransferExport()
_back = lua.eval("function(t) local d, why = HeadstartNS.TransferRead(t) return { d = d, why = why } end")(_text)
check(g.HeadstartTransferWindow is not None and g.HeadstartTransferWindow.hidden is False and _text.startswith("HEADSTART-SETTINGS 1")
      and _back.d is not None and _back.d.settings > 3 and _back.d.db.runs is None and g.YippRouteDB.runs is not None,
      f"/headstart transfer: the window, and this account's settings written and read back ({len(_text)} letters, {_back.why})")
g.HeadstartTransferWindow.Hide(g.HeadstartTransferWindow)
YR.ShowSettingsTab(YR, "quests")
_G = YR.SettingsLayout("quests")
check(_G.lift == 0, "the page opens with its cards open: what it keeps under them stays where it is")
_G.FoldAll(False)
_lift = _G.lift
_G.FoldAll(True)
check(_lift > 0 and _G.tail is not None and _G.lift == 0, f"what a page keeps under its cards comes up with them as they fold ({_lift}), and goes back down")
g.YippRouteDB.restock = None
check(True, "settings page with reward settings opens")
YR.ShowSettingsTab(YR, "trainer")        # the Trainer tab: the class's spells with a choice each
check(True, "settings Trainer tab opens")
# the Trainer page lists what a trainer teaches: Sinister Strike from its second rank (level 6), no talent's own ranks
_ts = open(os.path.join(ROOT, "Data", "TrainerSpells.lua"), encoding="utf-8").read()
_rogue = _ts[_ts.index("    ROGUE = function()"):_ts.index("    SHAMAN = function()")]
check('{ 1757, 6, "Sinister Strike", 2,' in _rogue and "Fist Weapon Specialization" not in _rogue and '"Stealth", 1,' in _rogue,
      "trainer data: a rogue is taught Sinister Strike 2 at level 6 and Stealth, and no rank of a talent")
_priest = _ts[_ts.index("    PRIEST = function()"):_ts.index("    ROGUE = function()")]
_hunter = _ts[_ts.index("    HUNTER = function()"):_ts.index("    MAGE = function()")]
check('"Holy Nova", 1,' not in _priest and '"Holy Nova", 2,' in _priest and _hunter.count('"Immolation Trap", 1,') == 1 and '"Bite"' not in _hunter,
      "trainer data: no rank that comes with a talent point (Holy Nova 1), one spell a rank (Immolation Trap), no pet abilities")
# the QoL tab: the campfire icon, the flight timer, and the reward picker with a hand-picked reward listed
YR.RewardSettings(YR).chosen[123] = lua.eval('{ item = 1, name = "Sturdy Boots", title = "A Test Quest" }')
YR.ShowSettingsTab(YR, "qol")
check(True, "settings QoL tab opens with a hand-picked reward listed")
YR.RewardSettings(YR).chosen[123] = None
# the routes switch from chat and on the Route settings page (where the route options dim while it's off)
was_routes = g.YippRouteDB.routes
g.SlashCmdList.HEADSTART("routes off")
check(g.YippRouteDB.routes is False, "/headstart routes off")
YR.ShowSettingsTab(YR, "route")
g.SlashCmdList.HEADSTART("routes on")
check(g.YippRouteDB.routes is True, "/headstart routes on")
g.YippRouteDB.routes = was_routes
# every page of the settings menu opens and refreshes (an old tab name still finds its page)
for key in ("camps", "bags", "vendors", "group", "reminders", "gear", "character", "trainer", "route", "qol"):
    YR.ShowSettingsTab(YR, key)
check(True, "every settings page opens")
# two tabs, each with its own menu: QoL's pages (Instances among them) and Levelling's (Route settings)
YR.ToggleWindow(YR, "instances")
check(YR.WindowTab() == "qol", f"Instances is on the QoL tab: {YR.WindowTab()}")
YR.ShowSettingsTab(YR, "route")
check(YR.WindowTab() == "levelling", f"Route settings is on the Levelling tab: {YR.WindowTab()}")
YR.ToggleWindow(YR, "run")
check(YR.WindowTab() == "levelling", "This run is on the Levelling tab")
YR.ToggleWindow(YR, "where")              # Where next? builds and fills from the real routes
check(YR.WindowTab() == "levelling", "Where next? is on the Levelling tab, and fills without an error")
YR.ShowSettingsTab(YR, "trainer")
check(YR.WindowTab() == "qol", "the Trainer page is on the QoL tab")
# the menu's pages by their names, old ones included (the skins and the talent window had their own)
for key in ("start", "xpbar", "swing", "chat", "windows", "instances", "main", "rxpskin", "dmgskin", "skins", "talentwin"):
    YR.ShowSettingsTab(YR, key)
check(True, "Chat, Bars & windows, the two skins and the pages' old names open")
check(lua.eval('HeadstartNS.WindowTab()') == "qol", "the old names of the merged pages (the skins, the camps) open their page")
found = YR.SettingsSearch("hourly limit")
check(found is not None and len(found) == 1 and found[1].key == "instances",
      "the instance tracker's settings are found on the Instances page")
YR.SettingsGo(found[1])
check(True, "and going to one opens that page's settings")
found = YR.SettingsSearch("micro menu")
check(found is not None and len(found) >= 1 and all(found[i].key == "windows" for i in range(1, len(found) + 1)),
      "the bag bar and micro menu are on Bars & windows")
# a feature is found by the name a player would type, and by words that aren't in its name
for words, page in (("death recap", "recap"), ("died", "recap"), ("altoholic", "alts"), ("campfire", "journey"), ("flight timer", "journey"), ("rxp guide", "skins"), ("dps details", "skins"),
                    ("skip cinematic", "general"), ("minimap button", "general"), ("accent colour", "general")):
    found = YR.SettingsSearch(words)
    check(found is not None and len(found) >= 1 and found[1].key == page, f"searching \"{words}\" finds the {page} page")
# All features: the first page, a card for everything, each leading to a section that is there
YR.ShowSettingsTab(YR, "home")
YR.SettingsSearch("")
missing = lua.eval("""(function()
    local YR = HeadstartNS
    local have, out = {}, {}
    for _, e in ipairs(YR.SettingsIndex()) do if e.card then have[e.key .. "/" .. e.label] = true end end
    for _, group in ipairs(YR.HomeFeatures()) do
        for i = 2, #group do
            local f = group[i]
            if not f.go and not have[f.page .. "/" .. f.section] then out[#out + 1] = f.name end
            if f.get then
                local was = f.get() and true or false
                f.set(not was)
                if (f.get() and true or false) == was then out[#out + 1] = f.name .. " switch" end
                f.set(was)
            elseif type(f.state()) ~= "string" then out[#out + 1] = f.name .. " state" end
        end
    end
    return table.concat(out, ", ") end)()""")
check(missing == "", f"every card on All features opens a section that exists, and its switch works ({missing})")
# the boat timer: off as Headstart comes; on, at Ratchet's dock, it shows the boat there and when it leaves
check(not YR.Option("boatTimer"), "the boat timer starts off")
lua.execute("""KEPT_POS = UnitPosition
    local d = HeadstartNS.BoatData.ratchetBB.docks[2]
    function UnitPosition() return d[4], d[3], 0, d[2] end
    YippRouteDB.boatTimer = true
    HeadstartNS.BoatTimerApply()""")
_hud = g.HeadstartBoatTimer
check(_hud is not None and _hud.hidden is not True, "on, at Ratchet's dock: the timer shows the boat there")
lua.execute("YippRouteDB.boatTimer = nil HeadstartNS.BoatTimerApply() UnitPosition = KEPT_POS")
check(_hud.hidden is True, "and off again: gone")
# and the boats on the world map: each where it is, while the map is open
lua.execute("""
    WorldMapFrame = CreateFrame("Frame", "WorldMapFrame")
    WorldMapFrame.hidden = false
    BOAT_CANVAS = CreateFrame("Frame")
    function WorldMapFrame:GetMapID() return 1414 end
    function WorldMapFrame:GetCanvas() return BOAT_CANVAS end
    function WorldMapFrame:GetCanvasScale() return 1 end
    -- the map canvas's data providers, as the game keeps them
    MapCanvasDataProviderMixin = MapCanvasDataProviderMixin or {}
    CreateFromMixins = CreateFromMixins or function(...)
        local t = {}
        for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end
        return t
    end
    BOAT_PROVIDERS, BOAT_UPDATES = {}, {}
    function WorldMapFrame:AddDataProvider(p) BOAT_PROVIDERS[p] = true end
    function WorldMapFrame:RemoveDataProvider(p) p:RemoveAllData() BOAT_PROVIDERS[p] = nil end
    function WorldMapFrame:RegisterDataProviderOnUpdate(p) BOAT_UPDATES[p] = true end
    function WorldMapFrame:UnregisterDataProviderOnUpdate(p) BOAT_UPDATES[p] = nil end
    function BOAT_CALL(method) for p in pairs(BOAT_PROVIDERS) do p[method](p) end end
    function BOAT_COUNT(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
    C_Map = C_Map or {}
    KEPT_MAPPOS = C_Map.GetMapPosFromWorldPos
    BOAT_AT = 0.5
    C_Map.GetMapPosFromWorldPos = function(c, v, id)
        if id ~= 1414 then return id, { GetXY = function() return 1.5, 1.5 end } end
        return id, { GetXY = function() return BOAT_AT, 0.5 end }
    end
    CreateVector2D = CreateVector2D or function(x, y) return { x = x, y = y } end
    YippRouteDB.boatTimer = true
    HeadstartNS.BoatTimerApply()
    BOAT_CALL("OnShow")""")
check(YR.BoatMapPins() == 5,
      f"the boats on the world map: an Alliance player's four and Ratchet's, no zeppelins ({YR.BoatMapPins()})")
lua.execute("YippRouteDB.boatMapOther = true BOAT_CALL('OnUpdate')")
check(YR.BoatMapPins() == 8, f"Horde zeppelins too: every route with a course ({YR.BoatMapPins()})")
lua.execute("YippRouteDB.boatMapOther = nil BOAT_CALL('OnUpdate')")
check(YR.BoatMapPins() == 5, "and off again: back to your own side's")
lua.execute("UnitFactionGroup = function() return 'Horde' end BOAT_CALL('OnUpdate')")
check(YR.BoatMapPins() == 4, f"a Horde player's: the three zeppelins and Ratchet's, no Alliance boats ({YR.BoatMapPins()})")
lua.execute("UnitFactionGroup = function() return 'Alliance' end BOAT_CALL('OnUpdate')")
check(lua.eval("BOAT_COUNT(BOAT_PROVIDERS) == 1 and BOAT_COUNT(BOAT_UPDATES) == 1"),
      "kept on the map as the game keeps its own icons: a data provider, run every frame the map is open")
# the map turned to a zone with no boat on it: gone at once, not on a timer
lua.execute("function WorldMapFrame:GetMapID() return 1411 end BOAT_CALL('OnMapChanged')")
check(YR.BoatMapPins() == 0, "the map turned to a map without them: gone at once")
lua.execute("function WorldMapFrame:GetMapID() return 1414 end BOAT_CALL('OnMapChanged')")
check(YR.BoatMapPins() == 5, "and back: there at once")
# a frame later the boats have moved on, and the pins with them
lua.execute("""local p = HeadstartNS.BoatMapPinFor("ratchetBB")
    function p:SetPoint(_, _, _, x) self.px = x end
    BOAT_CALL("OnUpdate") BOAT_X0 = p.px
    BOAT_AT = 0.6 BOAT_CALL("OnUpdate") BOAT_X1 = p.px""")
_x0, _x1 = lua.eval("BOAT_X0"), lua.eval("BOAT_X1")
check(_x0 is not None and _x1 is not None and _x1 > _x0, f"the next frame: moved along with the boat ({_x0} -> {_x1})")
# how big: grows as the map comes closer (zoomed in, or a zone rather than its continent), within bounds
lua.execute("""C_Map.GetMapWorldSize = function(id) return id == 1414 and 36800 or 5300, 1 end
    BOAT_SCALE = 1
    function WorldMapFrame:GetCanvasScale() return BOAT_SCALE end
    function BOAT_CANVAS:GetWidth() return 1002 end
    local p = HeadstartNS.BoatMapPinFor("ratchetBB")
    local function OnScreen() BOAT_CALL("OnCanvasScaleChanged") return p.size * BOAT_SCALE end
    BOAT_S1 = OnScreen()
    BOAT_SCALE = 3 BOAT_S2 = OnScreen()
    BOAT_SCALE = 1000 BOAT_S3 = OnScreen()
    BOAT_SCALE = 0.001 BOAT_S4 = OnScreen()
    BOAT_SCALE = 1""")
_s = [lua.eval(f"BOAT_S{i}") for i in range(1, 5)]
check(_s[1] > _s[0], f"zoomed in: bigger on screen, not smaller ({_s[0]:.1f} -> {_s[1]:.1f})")
check(abs(_s[2] - 80) < 0.01 and abs(_s[3] - 32) < 0.01, f"and never past a hand nor too small to see ({_s[2]:.1f}, {_s[3]:.1f})")
lua.execute("BOAT_CANVAS.GetWidth = nil BOAT_CALL('OnUpdate') C_Map.GetMapWorldSize = nil")
lua.execute("YippRouteDB.boatMap = false HeadstartNS.BoatTimerApply()")
check(YR.BoatMapPins() == 0, "On the world map switched off: none")
check(lua.eval("BOAT_COUNT(BOAT_PROVIDERS) == 0 and BOAT_COUNT(BOAT_UPDATES) == 0"),
      "and taken off the map: nothing run while it is off")
lua.execute("YippRouteDB.boatMap = nil YippRouteDB.boatTimer = nil HeadstartNS.BoatTimerApply() C_Map.GetMapPosFromWorldPos = KEPT_MAPPOS")
check(YR.BoatMapPins() == 0, "the boat timer off: none")
# Which combat bars show is each character's own; one that hasn't chosen starts from its class's last choice
lua.execute("""KEPT_CHARDB, KEPT_CLASS = YippSetupCharDB, UnitClass
    YippRouteDB.swingClass = nil
    UnitClass = function() return "Warrior", "WARRIOR" end
    YippSetupCharDB = {}
    local s = HeadstartNS.SwingDB() s.on, s.power, s.cast = true, true, false
    WARRIOR_CHAR = YippSetupCharDB
    YippSetupCharDB = {}                                         -- another warrior, never chosen
    W2_ON, W2_POWER = HeadstartNS.SwingOwn("on"), HeadstartNS.SwingOwn("power")
    UnitClass = function() return "Mage", "MAGE" end
    YippSetupCharDB = {}                                         -- a mage, never chosen
    MAGE_ON = HeadstartNS.SwingOwn("on")
    local m = HeadstartNS.SwingDB() m.on, m.power = false, false
    YippSetupCharDB = WARRIOR_CHAR UnitClass = function() return "Warrior", "WARRIOR" end
    BACK_ON, BACK_POWER = HeadstartNS.SwingDB().on, HeadstartNS.SwingOwn("power")
    RAW_ON = rawget(YippRouteDB.swing, "on")""")
check(g.WARRIOR_CHAR.combatBars is not None and g.WARRIOR_CHAR.combatBars.on is True and g.RAW_ON is None,
      "the combat bars a character turns on are its own, not the account's")
check(g.W2_ON is True and g.W2_POWER is True, "another warrior that hasn't chosen: starts with the last warrior's choice")
check(g.MAGE_ON == lua.eval("YippRouteDB.swingShared and YippRouteDB.swingShared.on"),
      "a mage, no mage having chosen: starts from what the account had before")
check(g.BACK_ON is True and g.BACK_POWER is True, "and the mage turning them off leaves the warrior's as they were")
lua.execute("YippSetupCharDB, UnitClass = KEPT_CHARDB, KEPT_CLASS")

# Put back everything Headstart changed (General page, Character setup, /headstart putback): asked first, and
# answered, quality of life and Character setup go off (each feature puts back its own as it goes)
lua.execute("""PUTBACK_ASKED = nil KEPT_SHOW = StaticPopup_Show
    StaticPopup_Show = function(w, ...) if w == "HEADSTART_PUTBACK" then PUTBACK_ASKED = w end if KEPT_SHOW then return KEPT_SHOW(w, ...) end end
    YippSetupCharDB = YippSetupCharDB or {} KEPT_FIRST = YippSetupCharDB.first YippSetupCharDB.first = nil
    KEPT_SETUPON = YippRouteDB.setupOn YippRouteDB.setupOn = true""")
g.SlashCmdList.HEADSTART("putback")
check(g.PUTBACK_ASKED == "HEADSTART_PUTBACK" and YR.QoLOn(), "/headstart putback: asked first, nothing changed yet")
lua.execute("StaticPopupDialogs.HEADSTART_PUTBACK.OnAccept()")
check(not YR.QoLOn() and not YR.SetupOn(), "answered: quality of life and Character setup off")
lua.execute("""HeadstartNS.SetQoLOn(true) YippRouteDB.setupOn = KEPT_SETUPON YippSetupCharDB.first = KEPT_FIRST
    StaticPopup_Show = KEPT_SHOW""")
# /headstart boats: the list of every boat and zeppelin, a button each (a tool to measure them for a timetable)
g.SlashCmdList.HEADSTART("boats")
check(g.HeadstartBoats is not None and g.HeadstartBoats.hidden is not True, "/headstart boats: the list of boats and zeppelins opens")
g.SlashCmdList.HEADSTART("boats")
check(g.HeadstartBoats.hidden is True, "and shuts again")
# one grouping for All features and the menu: every card stands in the group its page is in
wrong = lua.eval("""(function()
    local YR, out = HeadstartNS, {}
    local of = YR.SettingsMenuGroups()
    for _, group in ipairs(YR.HomeFeatures()) do
        for i = 2, #group do
            local f = group[i]
            if f.page and of[f.page] ~= group[1] then out[#out + 1] = f.name .. " (" .. tostring(of[f.page]) .. ")" end
        end
    end
    return table.concat(out, ", ") end)()""")
check(wrong == "", f"All features and the menu have one grouping: every card stands in its page's group ({wrong})")
# the tour over the window: every hint finds the part it points at, and the window stays on All features for
# the ones on the QoL tab
missing = lua.eval("""(function()
    local YR, out = HeadstartNS, {}
    for i, st in ipairs(YR.TourSteps()) do
        if st.at and not YR.TourTarget(st.at) then out[#out + 1] = st.at end
    end
    return table.concat(out, ", ") end)()""")
check(missing == "", f"the tour: every hint has the part of the window it points at ({missing})")
YR.WelcomeShow()
lua.execute("local b = HeadstartTour.next for i = 1, 8 do b.fn(b) end")
check(g.HeadstartTour.title.text == "Quality of life" and YR.WindowTab() == "qol", "the tour runs through in the window, on the QoL tab")
lua.execute("local b = HeadstartTour.next b.fn(b)")
check(g.HeadstartTour.hidden, "and is gone at Done")
# the news on the first page names cards that exist; the XP bar's samples; the accents
news_missing = lua.eval("""(function()
    local YR = HeadstartNS
    local _, news = YR.HomeNews()
    local have, out = {}, {}
    for _, group in ipairs(YR.HomeFeatures()) do for i = 2, #group do have[group[i].name] = true end end
    for name in pairs(news) do if not have[name] then out[#out + 1] = name end end
    return table.concat(out, ", ") end)()""")
check(news_missing == "", f"every card under New in this version is a feature there is ({news_missing})")
check(YR.XPBarSample("rested") == "rested" and YR.XPBarSampleNow() == "rested" and YR.XPBarSample(None) is None,
      "the XP bar drawn as a sample, and as it really is again")
accents = lua.eval("""(function()
    local S = HeadstartNS.Style
    local accent, out = S.C.accent, {}
    for _, a in ipairs(S.ACCENTS) do
        local got = S.Theme(a[1])
        if got ~= a[1] or S.C.accent ~= accent or type(S.C.accent[1]) ~= "number" then out[#out + 1] = a[1] end
    end
    if S.Theme("nonsense") ~= "ember" then out[#out + 1] = "unknown name" end
    S.Theme("ember")
    return table.concat(out, ", ") end)()""")
check(accents == "", f"every accent sets the look's colours in place, and an unknown one is Ember ({accents})")
# Layout that can be worked out without the game: the menu ends inside the window, the words on a card
# and in a card's head fit the room they have (11px narrow type is about 5.2px a letter, 13px about 6.2)
bottom, room = YR.SettingsMenuFits()
check(bottom is not None and bottom <= room - 4, f"the menu's last row ends inside the window ({bottom} of {room})")
tight = lua.eval("""(function()
    local YR, out = HeadstartNS, {}
    local w = math.floor((1140 - 210 - 40 - 16) / 3)
    for _, group in ipairs(YR.HomeFeatures()) do
        for i = 2, #group do
            local f = group[i]
            if #f.name * 6.2 > w - 46 - 62 then out[#out + 1] = f.name end
            if #f.desc * 5.2 > 2 * (w - 56) then out[#out + 1] = f.name .. " (line)" end
        end
    end
    for _, e in ipairs(YR.SettingsIndex()) do
        -- a card's head: icon, name, note, then "N changed - Reset" and the switch
        if e.card and 44 + #e.label * 6.8 + 10 + #(e.tip or "") * 5.2 > 680 - 170 then out[#out + 1] = e.label .. " (note)" end
    end
    return table.concat(out, ", ") end)()""")
check(tight == "", f"every card's name, line and note fits its room ({tight})")
contrast = lua.eval("""(function()
    local S, out = HeadstartNS.Style, {}
    local function Lum(c)
        local function f(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
        return 0.2126 * f(c[1]) + 0.7152 * f(c[2]) + 0.0722 * f(c[3])
    end
    local function Ratio(a, b) local x, y = Lum(a), Lum(b) if x < y then x, y = y, x end return (x + 0.05) / (y + 0.05) end
    for _, a in ipairs(S.ACCENTS) do
        if a[3] then
            S.Theme(a[1])
            if Ratio(S.C.onAccent, S.C.accent) < 4.5 then out[#out + 1] = a[1] .. " button text" end
            if Ratio(S.C.accent, S.C.card) < 3 then out[#out + 1] = a[1] .. " on a card" end
            if Ratio(S.C.text, S.C.card) < 7 or Ratio(S.C.muted, S.C.card) < 3 then out[#out + 1] = a[1] .. " text" end
        end
    end
    S.Theme("ember")
    return table.concat(out, ", ") end)()""")
check(contrast == "", f"text on the accent, the accent on a card and the text colours are readable in every look ({contrast})")
found = YR.SettingsSearch("button strip")
check(found is not None and len(found) == 1 and found[1].key == "chat", "the chat's buttons are on Chat")
found = YR.SettingsSearch("volume channel")
check(found is not None and len(found) == 1 and found[1].key == "chat", "and so is the whisper sound")
YR.SettingsSearch("")
# a menu with a button on each line (the speaker on the whisper sounds): it acts on that line's value
# without picking it, and a line can go without one
heard = lua.eval("""function(YR)
    local heard, picked = {}, {}
    local list = { { "off", "None" }, { "a", "Bell" }, { "b", "Horn" } }
    YR.Style.OpenMenu(CreateFrame("Frame"), list, function(v) picked[#picked + 1] = v end, 200,
        { icon = "sound", tip = "Listen", shows = function(v) return v ~= "off" end, onClick = function(v) heard[#heard + 1] = v end })
    return heard, picked
end""")(YR)
check(heard is not None, "a menu with a speaker on its lines opens")
YR.Style.CloseMenu()
# the bar planner builds with the real Setup and Style, and the first-time window shows its button
YR.OpenPlanner()
check(g.HeadstartPlanner is not None and g.HeadstartPlanner.hidden is False, "the bar planner opens")
g.HeadstartPlanner.Hide(g.HeadstartPlanner)
YR.Setup.Toggle(YR.Setup)
check(g.YippSetupFrame is not None, "the first-time window builds with its Plan my bars button")
YR.Setup.Toggle(YR.Setup)
YR.ShowSettingsTab(YR, "route")
# the minimap button exists and the settings switch hides it
check(g.HeadstartMinimapButton is not None and g.HeadstartMinimapButton.hidden is not True, "minimap button shown")
YR.ShowMinimapButton(YR, False)
check(g.HeadstartMinimapButton.hidden is True and g.YippRouteDB.minimapButton is False, "minimap button can be hidden")
# with LibDBIcon there (it is, in the game: Libs/), the button is the library's - registered with
# where it stood before, and shown and hidden through the library
_opt = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(open(os.path.join(ROOT, "Options.lua"), encoding="utf-8").read(), "Options.lua")
lua.execute("""DBI = { calls = {} }
    local broker = { NewDataObject = function(self, name, o) DBI.object = o return o end }
    local icon = { Register = function(self, name, o, db) DBI.db = db DBI.calls[#DBI.calls + 1] = "register" end,
        Show = function(self, name) DBI.calls[#DBI.calls + 1] = "show" end, Hide = function(self, name) DBI.calls[#DBI.calls + 1] = "hide" end,
        GetMinimapButton = function() return { lib = true } end }
    KEPT_STUB = LibStub
    LibStub = { GetLibrary = function(self, name) return name == "LibDataBroker-1.1" and broker or name == "LibDBIcon-1.0" and icon or nil end }
    YippRouteDB.minimapAngle, YippRouteDB.minimap = 480, nil""")
_show, _build = YR.ShowMinimapButton, YR.BuildMinimapButton
_opt("Headstart", YR)             # the file read again: its button isn't made yet
YR.ShowMinimapButton(YR, True)
check(list(g.DBI.calls.values()) == ["register", "show"] and g.DBI.db.minimapPos == 120 and g.DBI.db.hide is False
      and g.DBI.object.icon.endswith("logomark") and g.DBI.object.OnClick is not None and g.DBI.object.OnTooltipShow is not None,
      f"with LibDBIcon: the button is registered with it, where ours stood (480 degrees is 120), and shown ({list(g.DBI.calls.values())}, {g.DBI.db.minimapPos})")
YR.ShowMinimapButton(YR, False)
check(list(g.DBI.calls.values())[-1] == "hide" and g.DBI.db.hide is True and g.YippRouteDB.minimapButton is False,
      "turned off: hidden through the library, and kept so")
lua.execute("LibStub = KEPT_STUB YippRouteDB.minimap, YippRouteDB.minimapAngle = nil, nil")
YR.ShowMinimapButton, YR.BuildMinimapButton = _show, _build

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

# Every death skip in the shipped routes is followed by a step not already done (else it vanishes)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_deathskips
import glob as _glob
vanish = []
for f in _glob.glob(os.path.join(check_deathskips.ROOT, "Guides", "*.lua")) + _glob.glob(os.path.join(check_deathskips.ROOT, "Guides", "Levelling", "*.lua")):
    vanish += check_deathskips.check(f)
check(not vanish, "every death skip is followed by a step still to do" + "".join("\n     " + v for v in dict.fromkeys(vanish)))

# No grey quest handed in anywhere on the route, for any Alliance race and class (tools/check_levels.py)
import check_levels
greys = check_levels.everyone()
check(not greys, "no grey hand-ins for any race and class" + "".join(
    f"\n     {race} {cls}: {r[0]} step {r[1]}: {r[3]} {r[4]} (quest {r[5]}, you ~{r[6]})" for race, cls, r in greys))

reds = check_levels.red_mobs()
check(not reds, "no red mobs to kill outside dungeons" + "".join(
    f"\n     {race} {cls}: {r[0]} step {r[1]}: {r[4]} (level {r[5]}, you ~{r[6]})" for race, cls, r in reds))

# The flight timer (its own fake API)
import smoke_flight
bad += smoke_flight.run()
import smoke_arrange
bad += smoke_arrange.run()
import smoke_journey
bad += smoke_journey.run()
import smoke_transfer
bad += smoke_transfer.run()

# The camp HUD (its own fake API)
import smoke_camp
bad += smoke_camp.run()

# The bank deposit (its own fake API)
import smoke_bank
bad += smoke_bank.run()

# Restock, reminders, upgrades and party quests (their own fake API)
import smoke_qol
bad += smoke_qol.run()

# The bar planner (its own fake API)
import smoke_planner
bad += smoke_planner.run()

# Buy later: the Paladin's Wooden Mallet (6s31 in Kharanos, skipped if you're short) comes back
lua.execute("""
C_Timer.After = function(_, fn) fn() end
EQUIPPED_LINK, BAGS, MERCHANT, BOUGHT_AT, POPUP = nil, {}, {}, nil, nil
function GetInventoryItemLink() return EQUIPPED_LINK end
C_Item = C_Item or {}
C_Item.GetItemCount = function(id) return BAGS[id] or 0 end
C_Item.GetItemStats = function() return { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 2.0 } end
function IsEquippedItem() return false end
function GetMerchantNumItems() return #MERCHANT end
function GetMerchantItemID(i) return MERCHANT[i] end
-- Forever has C_MerchantFrame.GetItemInfo only (the global GetMerchantItemInfo is Vanilla UI, not there)
C_MerchantFrame = { GetItemInfo = function(i) return { name = "x", price = 631, stackCount = 1, numAvailable = -1, isUsable = true, hasExtendedCost = false } end }
function BuyMerchantItem(i) BOUGHT_AT = i end
function IsShiftKeyDown() return false end
YippSetupCharDB = YippSetupCharDB or {}
YippSetupCharDB.toldBuy = nil
""")
shop = YR.ShoppingList()
mallet = [shop[i] for i in range(1, len(shop) + 1) if shop[i].item == 2493]
check(len(mallet) == 1 and mallet[0].price == 631 and mallet[0].npc == "Grawn Thromwyn",
      f"buy later reads the Wooden Mallet from the route: {[(e.name, e.price, e.npc) for e in mallet]}")
n_prints = len(g.PRINTS)
lua.execute("MONEY = 500; Fire('PLAYER_MONEY')")
check(len(g.PRINTS) == n_prints, "short of 6s31: nothing said")
lua.execute("MONEY = 700; Fire('PLAYER_MONEY')")
said = [str(g.PRINTS[i]) for i in range(n_prints + 1, len(g.PRINTS) + 1)]
check(any("Wooden Mallet" in x and "afford" in x for x in said), f"with 7s: told once where to buy it: {said}")
lua.execute("Fire('PLAYER_MONEY')")
check(len(g.PRINTS) == n_prints + 1, "told only once")
lua.execute("MERCHANT = { 2901, 2493 }; Fire('MERCHANT_SHOW')")
check(g.POPUP == "HEADSTART_BUY_LATER", "at a vendor who sells it: asked whether to buy it")
lua.execute("POPUP = nil; BAGS[2493] = 1; Fire('MERCHANT_SHOW')")
check(g.POPUP is None, "already have one: not asked")
lua.execute("BAGS[2493] = nil; EQUIPPED_LINK = 'x'; C_Item.GetItemStats = function() return { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 9.0 } end; Fire('MERCHANT_SHOW')")
check(g.POPUP is None, "your weapon is already better: not asked")

# The auto trainer (its own fake API)
import smoke_trainer
bad += smoke_trainer.run()
import smoke_mailstep
bad += smoke_mailstep.run()
# the log's position track on an account that doesn't use routes: other characters' samples go once
# (events stay, this character's log stays whole); never on an account that has had routes on
lua.execute("""
KEEP_ROUTES, KEEP_EVER = YippRouteDB.routes, YippRouteDB.routesEver
YippRouteDB.routes, YippRouteDB.routesEver = false, nil
YippRouteDB.runs["Other-Realm"] = { ev = { { 1, "accept" } }, track = { { 1 }, { 2 }, { 3 } } }
ME_TRACK = #YippRouteDB.runs[YR_KEY].track
""".replace("YR_KEY", '"' + YR.CharKey() + '"'))
check(YR.DropIdleTracks() >= 3 and len(g.YippRouteDB.runs["Other-Realm"].track) == 0 and len(g.YippRouteDB.runs["Other-Realm"].ev) == 1
      and len(g.YippRouteDB.runs[YR.CharKey()].track) == g.ME_TRACK, "routes never on: another character's position samples go, its events and this character's log stay")
lua.execute('YippRouteDB.runs["Other-Realm"].track = { { 1 } }; YippRouteDB.routesEver = true')
check(YR.DropIdleTracks() == 0 and len(g.YippRouteDB.runs["Other-Realm"].track) == 1, "an account that has had routes on: nothing is dropped, routes off or not")
lua.execute('YippRouteDB.routes = true; YippRouteDB.routesEver = nil')
check(YR.DropIdleTracks() == 0 and g.YippRouteDB.routesEver is True, "routes on: nothing dropped, and remembered")
lua.execute('YippRouteDB.runs["Other-Realm"] = nil; YippRouteDB.routes, YippRouteDB.routesEver = KEEP_ROUTES, KEEP_EVER')
import smoke_stepkeeper
bad += smoke_stepkeeper.run()
import smoke_myroutes
bad += smoke_myroutes.run()
import smoke_trinkets
bad += smoke_trinkets.run()
import smoke_instances
bad += smoke_instances.run()
import smoke_boats
bad += smoke_boats.run()
import smoke_xpbar
bad += smoke_xpbar.run()
import smoke_talentfade
bad += smoke_talentfade.run()
import smoke_rxpskin
bad += smoke_rxpskin.run()
import smoke_dmgskin
bad += smoke_dmgskin.run()
import smoke_whisper
bad += smoke_whisper.run()
import smoke_swing
bad += smoke_swing.run()
import smoke_barhide
bad += smoke_barhide.run()
import smoke_skipquests
bad += smoke_skipquests.run()
import smoke_wherenext
bad += smoke_wherenext.run()
import smoke_noroutes
bad += smoke_noroutes.run()
import smoke_window
bad += smoke_window.run()
import smoke_recap
bad += smoke_recap.run()
import smoke_chatlog
bad += smoke_chatlog.run()
import smoke_lootfeed
bad += smoke_lootfeed.run()
import smoke_runstore
bad += smoke_runstore.run()
import smoke_idle
bad += smoke_idle.run()
import smoke_pins
bad += smoke_pins.run()
import smoke_welcome
bad += smoke_welcome.run()
import smoke_cinematic
bad += smoke_cinematic.run()
import smoke_glimmer
bad += smoke_glimmer.run()
import smoke_npcmarkers
bad += smoke_npcmarkers.run()
import smoke_questlfg
bad += smoke_questlfg.run()
import smoke_alts
bad += smoke_alts.run()
import smoke_macrohelper
bad += smoke_macrohelper.run()
import smoke_pace
bad += smoke_pace.run()
# A frame's name is a global, and so is a saved variable's: one name for both and the frame replaces
# the saved table (or the game's Esc handling finds the table where it looks for the frame).
import glob as _glob, re as _re
_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_saved, _frames = set(), set()
for _toc in _glob.glob(os.path.join(_root, "**", "*.toc"), recursive=True):
    for _line in open(_toc, encoding="utf-8"):
        if _line.startswith("## SavedVariables"):
            _saved.update(n.strip() for n in _line.split(":", 1)[1].split(","))
for _lua in _glob.glob(os.path.join(_root, "**", "*.lua"), recursive=True):
    _src = open(_lua, encoding="utf-8", errors="replace").read()
    _frames.update(_re.findall(r'S\.Window\("([^"]+)"', _src))
    _frames.update(_re.findall(r'CreateFrame\("\w+",\s*"([^"]+)"', _src))
_clash = sorted(_saved & _frames)
print(("ok  " if not _clash else "FAIL"), f"no frame is named as a saved variable is ({', '.join(_clash) or 'none'})")
bad += bool(_clash)
sys.exit(1 if bad else 0)
