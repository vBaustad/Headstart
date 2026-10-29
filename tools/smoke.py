"""Smoke test: /yroute scan and the run log against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke.py      (exit code 1 on any failure)

Without the routes addon beside Headstart (Headstart_Routes, private) the tests in this file are skipped and the
suites with a fake game of their own run alone; SMOKE_NO_ROUTES=1 runs it that way with the routes there.
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
-- (fn: the last script set, for Fire; scripts: each by its name, for a test to call one)
function Frame:SetScript(name, fn) self.fn = fn local s = rawget(self, "scripts") or {} rawset(self, "scripts", s) s[name] = fn end
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
function UnitClass() return "Paladin", "PALADIN", 2 end       -- (and the class ID, as the game gives it)
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


def _apart():
    """What runs whether the routes are there or not: no frame named as a saved variable is, and the tests that are
    scripts of their own (Character setup's, the live move's). Returns how many failed."""
    import glob as _glob
    import subprocess as _sp
    n_bad = 0
    # A frame's name is a global, and so is a saved variable's: one name for both and the frame replaces
    # the saved table (or the game's Esc handling finds the table where it looks for the frame).
    saved, frames = set(), set()
    for toc in _glob.glob(os.path.join(ROOT, "**", "*.toc"), recursive=True):
        for line in open(toc, encoding="utf-8"):
            if line.startswith("## SavedVariables"):
                saved.update(n.strip() for n in line.split(":", 1)[1].split(","))
    for path in _glob.glob(os.path.join(ROOT, "**", "*.lua"), recursive=True):
        src = open(path, encoding="utf-8", errors="replace").read()
        frames.update(re.findall(r'S\.Window\("([^"]+)"', src))
        frames.update(re.findall(r'CreateFrame\("\w+",\s*"([^"]+)"', src))
    clash = sorted(saved & frames)
    print(("ok  " if not clash else "FAIL"), f"no frame is named as a saved variable is ({', '.join(clash) or 'none'})")
    n_bad += bool(clash)
    for script in ("smoke_setup.py", "smoke_live_move.py"):
        r = _sp.run([sys.executable, os.path.join(ROOT, "tools", script)], capture_output=True, text=True,
                    encoding="utf-8", errors="replace")
        fails = [l.strip() for l in r.stdout.splitlines() if l.strip().startswith("FAIL")]
        n = sum(1 for l in r.stdout.splitlines() if l.strip().startswith("ok"))
        print(("ok  " if r.returncode == 0 else "FAIL"), f"{script}: " + (f"{n} checks passed" if r.returncode == 0
              else ("; ".join(fails[:5]) or r.stderr.strip()[-300:])))
        n_bad += r.returncode != 0
    return n_bad


if not os.path.isdir(ROUTES) or os.environ.get("SMOKE_NO_ROUTES"):
    # Without it (a copy of the public repo) the tests in this file can't run - but every suite with a fake game of its
    # own (each "import smoke_..." below) and the scripts apart still do. (The test audit, 2026-10-21: everything was
    # skipped, and the run said it passed.) SMOKE_NO_ROUTES=1 takes this way with the routes there, to try it.
    print("SKIPPED: the tests in smoke.py itself need the routes addon in " + ROUTES + "; the suites of their own run")
    _bad = 0
    for _name in re.findall(r"^import (smoke_\w+)$", open(os.path.abspath(__file__), encoding="utf-8").read(), flags=re.M):
        _bad += __import__(_name).run()
    _bad += _apart()
    sys.exit(1 if _bad else 0)
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
check("level 2 at" not in said, f"the time at a level isn't said in chat: the splits have it (below) ({said})")
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
# old logs that are still used are kept: a fastest run's (a route of your own saved from one kept it too, until
# Save as route was taken out, 2026-10-29: such a log now goes like any other)
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
check(n == 2 and g.YippRouteDB.runs["Slow-Realm"] is None and g.YippRouteDB.runs["Source-Realm"] is None,
      f"the old logs nothing uses go ({n}), a route once saved from one with them (Save as route is gone)")
check(g.YippRouteDB.runs["Fast-Realm"] is not None, "the fastest run's log is kept, however old")
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
# Class and start route: a Lean opener against Lean runs only, the route from the run (RestedXP's
# "01-06" or "1-6") or, for a run from before, from a routes addon's HeadstartRunRoutes
lua.execute('''YippRouteDB.splits.runs = {
  lean = { name = "Lean-Realm", class = "PALADIN", route = "01-06 Shadowglen (Lean)", levels = { [1] = 0, [5] = 1600 } },
  oldlean = { name = "OldLean-Realm", class = "PALADIN", levels = { [1] = 0, [5] = 1500 } },
  full = { name = "Full-Realm", class = "PALADIN", route = "1-6 Shadowglen (Launch)", levels = { [1] = 0, [5] = 1200 } },
  other = { name = "Rogue-Realm", class = "ROGUE", route = "1-6 Shadowglen (Lean)", levels = { [1] = 0, [5] = 1000 } } }
  HeadstartRunRoutes = { ["OldLean-Realm"] = "1-6 Shadowglen (Lean)" }
  KEPT_RXP, KEPT_LEVEL = RXP, UnitLevel
  RXP = { currentGuide = { name = "1-6 Shadowglen (Lean)" } }
  UnitLevel = function() return 3 end''')
g.YippRouteDB.splitsCompare = "route"
check(YR.SplitsFastest().levels[5] == 1500,
      "class and start route: a Lean run and an older one the routes addon names; not the Launch run, not another class")
lua.execute("RXP, UnitLevel, HeadstartRunRoutes = KEPT_RXP, KEPT_LEVEL, nil")
# One run I pick: that run alone, though faster ones of the same class are there (the stress test's run
# on launch day, against the beta runs copied along); the list names it and the pick keeps its log
g.YippRouteDB.splitsCompare, g.YippRouteDB.splitsPin = "pin", "lean"
check(YR.SplitsFastest().levels[5] == 1600, "one run picked: that run's times, not the faster ones")
run_list = YR.SplitsRunList()
labels = [run_list[i][2] for i in range(1, len(run_list) + 1)]
check(any("Lean" in l and "level 5" in l for l in labels) and len(labels) == 4, f"the runs to pick from: {labels}")
check(YR.SplitsBestRuns()["Lean-Realm"], "the picked run's log is kept like a fastest run's")
g.YippRouteDB.splitsPin = "gone"
check(YR.SplitsFastest() is None, "a picked run that is gone: nothing to compare with, no error")
g.YippRouteDB.splitsPin = None
g.YippRouteDB.splitsCompare = None
check(YR.SplitsStartInLog is not None, "the start route can be read from this character's own log (a run past 6)")
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

# This run: what was done, one line each (the delivery quest's instant "complete" is not one)
acts = YR.RunActions(YR)
labels = [acts[i].label for i in range(1, len(acts) + 1)]
check("Took Dwarven Outfitters" in labels and "Bought Mining Pick" in labels and "Learned Mining" in labels,
      f"this run's actions: {labels}")
check(all(acts[i].step is None for i in range(1, len(acts) + 1)),
      "and no route step written for them (Add to route went with the route editor, 2026-10-29)")
# the window builds
lua.execute("""SEEN_ICONS = {}
local F = getmetatable(CreateFrame())
local set = F.SetText
F.SetText = function(self, t)
    if type(t) == "string" and t:find("|T%d+:18") then SEEN_ICONS[#SEEN_ICONS + 1] = t end
    set(self, t)
end""")
YR.ToggleWindow(YR)
check(g.HeadstartWindow is not None and g.HeadstartWindow.hidden is False, "the window opens")
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
# a page built unseen (a search builds every page) starts nothing of its own: the swing timer's sample swings ran on
# your bars after a search, until the next fight (the review, 2026-10-21)
lua.execute("""local YR = HeadstartNS
    SWING_WAS, QOL_WAS = YR.SwingDB().on, YippRouteDB.qolOff
    YR.SwingDB().on, YippRouteDB.qolOff = true, nil
    local F = getmetatable(CreateFrame())
    rawset(F, "IsVisible", function() return false end)
    SAMPLES_BEFORE = YR.SwingPreviewing()
    YR.SettingsSearch("zzz")
    SAMPLES_UNSEEN = YR.SwingPreviewing()
    YR.SettingsSearch("")
    rawset(F, "IsVisible", nil)
    YR.SwingPreview(false)
    YR.SwingDB().on, YippRouteDB.qolOff = SWING_WAS, QOL_WAS""")
check(g.SAMPLES_BEFORE is False and g.SAMPLES_UNSEEN is False,
      f"a search builds the Combat bars page unseen: no sample swings on your bars ({g.SAMPLES_BEFORE}, {g.SAMPLES_UNSEEN})")
for key in ("camps", "bags", "vendors", "group", "quests", "reminders", "gear", "trinkets", "xpbar", "character", "trainer", "route"):
    YR.ShowSettingsTab(YR, key)        # every page builds, and fills, without an error
icons = [g.SEEN_ICONS[i] for i in range(1, len(g.SEEN_ICONS) + 1)]
check(any("Seal of" in t or "Holy Light" in t for t in icons), f"trainer rows carry the spell's icon: {icons[:2]}")
YR.ShowSettingsTab(YR, "talents")         # (the talent window's page; talent builds are the Levelling tab's)
check(YR.WindowTab() == "interface", f"the Talent window page is on the Interface tab ({YR.WindowTab()})")
found = YR.SettingsSearch("talent build")
check(found is not None and len(found) >= 1 and found[1].key == "builds", "Talent builds is found by the settings search")
YR.SettingsGo(found[1])
check(YR.WindowTab() == "qol" and YR.WindowShowing("builds") and YR.SettingsSearching() is False,
      f"and picking it opens QoL's Talents page ({YR.WindowTab()})")
# Find a setting: by a word in its name or details, on any page; picking one opens its page
found = YR.SettingsSearch("durability")
labels = [found[i].label for i in range(1, len(found) + 1)] if found else []
check(any("Durability" in l for l in labels) and all(found[i].key for i in range(1, len(found) + 1)),
      f"the search finds Durability warning, and knows its page: {labels}")
_searching = YR.SettingsSearching()
YR.SettingsGo(found[1])
check(_searching is True and YR.SettingsSearching() is False and YR.SettingsLayout(found[1].key) is not None,
      "picking a result: the results go, and its page is there")
check(YR.SettingsSearch("") is None, "an empty search shows the page again")
# a tab at the top clears a search, as a page in the menu does (the review, 2026-10-21: QoL and Interface are one page,
# and the results stood over the other tab's)
YR.SettingsSearch("durability")
_searching = YR.SettingsSearching()
_tab = YR.TourTarget("interface")
_tab.scripts.OnClick(_tab)
check(_searching is True and YR.SettingsSearching() is False and YR.WindowTab() == "interface",
      f"searching on QoL, the Interface tab picked: its page, not the results ({YR.WindowTab()})")
check(len(YR.SettingsSearch("zzqqxx") or []) == 0, "nothing matches: an empty list, no error")
# A feature that is off is its head alone: its options are of no use while it is (the quiet ledger, 2026-10-21)
lua.execute("""local F = getmetatable(CreateFrame()) F.SetAlpha = function(self, a) self.alpha = a end""")
def _rows_shown(page, card):
    return [e.row.hidden is not True for e in YR.SettingsIndex().values() if e.key == page and not e.card and e.of and e.of.title == card]
g.YippRouteDB.restock, g.YippRouteDB.cardsOpen = False, None
YR.ShowSettingsTab(YR, "vendors")
YR.RefreshWindow(YR)
_shut = _rows_shown("vendors", "Restock")
_V = YR.SettingsLayout("vendors")
_restock = [cd for cd in _V.cards.values() if cd.title == "Restock"][0]
_restock.head.scripts.OnMouseUp(_restock.head)          # a click on its row
_open = _rows_shown("vendors", "Restock")
_quiet = all(e.row.alpha == 0.45 for e in YR.SettingsIndex().values() if e.key == "vendors" and not e.card and e.of and e.of.title == "Restock")
g.YippRouteDB.restock = True
YR.RefreshWindow(YR)
_awake = all(e.row.alpha == 1 for e in YR.SettingsIndex().values() if e.key == "vendors" and not e.card and e.of and e.of.title == "Restock")
check(len(_shut) > 0 and not any(_shut) and all(_open) and _quiet and _awake and g.YippRouteDB.cardsOpen["vendors:Restock"] is True,
      f"Restock: its settings shut to begin with; a click on its row opens them - quiet while it is off, awake on - and that is kept ({len(_shut)})")
_restock.head.scripts.OnMouseUp(_restock.head)
check(not any(_rows_shown("vendors", "Restock")) and g.YippRouteDB.cardsOpen["vendors:Restock"] is None, "clicked again: shut")
g.YippRouteDB.restock = None
YR.RefreshWindow(YR)
# A card whose feature is several settings has one main switch: off puts them to off and keeps them, on puts them
# back as they were - the first time, a start of its own (the owner, 2026-10-20: "everything can be switched on
# and off, each with its own main switch")
_kept = lua.eval("""(function()
    local M, out = HeadstartNS.CardMasters(), {}
    local inv = M.invites
    YippRouteDB.acceptInvites, YippRouteDB.whisperInvite, YippRouteDB.kept, YippRouteDB.cardOn = "anyone", "off", nil, nil
    if not inv[1]() then out[#out + 1] = "invites read as off with one of them on" end
    inv[2](false)
    if inv[1]() or YippRouteDB.acceptInvites ~= "off" then out[#out + 1] = "off: not off" end
    inv[2](true)
    if not inv[1]() or YippRouteDB.acceptInvites ~= "anyone" or YippRouteDB.whisperInvite ~= "off" then
        out[#out + 1] = "on again: not as it was (" .. tostring(YippRouteDB.acceptInvites) .. ")"
    end
    YippRouteDB.acceptInvites, YippRouteDB.whisperInvite, YippRouteDB.kept, YippRouteDB.cardOn = nil, nil, nil, nil
    inv[2](true)
    if YippRouteDB.acceptInvites ~= "friends" or YippRouteDB.whisperInvite ~= "friends" then out[#out + 1] = "first time on: no start" end
    inv[2](false)
    local ws = M.windowScale
    YippRouteDB.windowScale, YippRouteDB.kept, YippRouteDB.cardOn = nil, nil, nil
    ws[2](true)
    if not ws[1]() then out[#out + 1] = "window scale on, with nothing to change yet: reads off" end
    ws[2](false)
    if ws[1]() then out[#out + 1] = "window scale off: reads on" end
    YippRouteDB.acceptInvites, YippRouteDB.whisperInvite, YippRouteDB.kept, YippRouteDB.cardOn = nil, nil, nil, nil
    -- one that works on another addon, that addon not loaded: it says so and stays off (the review, 2026-10-21)
    local rs, KEPT_RXP = M.rxpSkin, RXP
    RXP, PRINTS = nil, {}
    rs[2](true)
    if rs[1]() or (YippRouteDB.cardOn and YippRouteDB.cardOn.rxpSkin) then out[#out + 1] = "RestedXP skin on without RestedXP: reads on" end
    if not (PRINTS[1] and PRINTS[1]:find("RestedXP isn't loaded")) then out[#out + 1] = "RestedXP skin on without RestedXP: nothing said" end
    RXP, YippRouteDB.kept, YippRouteDB.cardOn = KEPT_RXP, nil, nil
    return table.concat(out, "; ") end)()""")
check(_kept == "", f"a card of several settings: off keeps them, on puts them back, the first time a start of its own ({_kept})")
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
# One column, the cards in their place whether on or off (the quiet ledger: they moved under the ones that were on,
# and stood side by side)
def _heads_at(page):
    """{ card: (top, x) } of a page's cards as they stand."""
    return {e.of.title: (e.of.top + (e.of.shift or 0), e.of.x or 0) for e in YR.SettingsIndex().values()
            if e.key == page and e.card and e.of and e.label == e.of.title}
_sw = YR.SwingDB()
_was = (_sw.on, _sw.health, _sw.power, _sw.cast)
_sw.on, _sw.health, _sw.power, _sw.cast = True, None, None, None
YR.ShowSettingsTab(YR, "swing")
YR.RefreshWindow(YR)
_h1 = _heads_at("swing")
_sw.on, _sw.health = False, True
YR.RefreshWindow(YR)
_h2 = _heads_at("swing")
_order = lambda h: sorted(h, key=lambda k: -h[k][0])
check(_order(_h1) == _order(_h2) == ["Swing timer", "Health and power bars", "Cast bar"] and all(x == 0 for _, x in _h2.values()),
      f"Combat bars: one column, the cards in their own order whether on or off ({_order(_h2)})")
_L = YR.SettingsLayout("swing")
def _packed(L):
    """Every card right under the one before it: its top on that one's bottom edge (a card that is off: its head)."""
    cards = sorted(L.cards.values(), key=lambda cd: -(cd.top + (cd.shift or 0)))
    for a, b in zip(cards, cards[1:]):
        if b.top + (b.shift or 0) != a.top + (a.shift or 0) - (54 if a.shut else a.height):
            return False
    return True
check(_packed(_L), "one list: each card right under the one before it")
_health = [cd for cd in _L.cards.values() if cd.title == "Health and power bars"][0]
_health.head.scripts.OnMouseUp(_health.head)
_shut = {cd.title: cd.shut for cd in _L.cards.values()}
check(_shut == {"Swing timer": True, "Health and power bars": False, "Cast bar": True} and not any(_rows_shown("swing", "Swing timer"))
      and all(_rows_shown("swing", "Health and power bars")) and _packed(_L),
      f"one card opened: its settings under it, the cards under it moved down to make room ({_shut})")
_health.head.scripts.OnMouseUp(_health.head)
_sw.on, _sw.health, _sw.power, _sw.cast = _was
YR.RefreshWindow(YR)
# a feature's switch is in the head of its own card (a block of switches at the top of the page sent you looking)
_idx = [e for e in YR.SettingsIndex().values() if e.key == "trinkets"]
check(not any(e.label == "On this page" for e in _idx) and any(e.card and e.label == "Trinket auto-swap" for e in _idx),
      "no block of switches at the top of a page: each card has its own")
# Nothing folds by hand, and a page whose features are on has every setting in sight
_sw.on, _sw.cast = True, None
g.YippRouteDB.cardsOpen = None
YR.ShowSettingsTab(YR, "swing")
YR.RefreshWindow(YR)
_L = YR.SettingsLayout("swing")
_cast = [cd for cd in _L.cards.values() if cd.title == "Cast bar"][0]
_shut_before = not any(_rows_shown("swing", "Cast bar"))
_cast.frame.switch.scripts.OnClick(_cast.frame.switch)          # the cast bar switched on: its settings open
check(_shut_before and YR.SwingDB().cast is True and all(_rows_shown("swing", "Cast bar")) and len(_rows_shown("swing", "Cast bar")) >= 3
      and _packed(_L), f"a feature switched on: its settings open, to be seen as it starts ({len(_rows_shown('swing', 'Cast bar'))})")
found = YR.SettingsSearch("range text")
YR.SettingsGo(found[1])
check(found[1].row.hidden is not True and YR.SettingsSearching() is False, "the search leads to a setting of a feature that is on")
_sw.on, _sw.cast = _was[0], _was[3]
YR.SettingsSearch("")
YR.RefreshWindow(YR)
YR.ShowSettingsTab(YR, "recap")
check(all(_rows_shown("recap", "Death recap")) == bool(g.YippRouteDB.deathRecap) and len(_rows_shown("recap", "Death recap")) > 1,
      "a page with one card: its options there while the recap is on")
# Pixel-exact controls: at 2560 x 1440 and the game's own UI scale (0.64) a point is 1.2 screen pixels - the switch is
# then 48 x 24 pixels drawn from that size in its strip, the knob 20, the checkbox 22 (the owner, 2026-10-21: "feels so
# low resolution"). The strip's layout in Style.lua is read back from the TGA make_controls.py drew.
lua.execute("""
KEPT_PU = PixelUtil
PIXELS = 1440
PixelUtil = { GetPixelToUIUnitFactor = function() return 768 / PIXELS end }
local F = getmetatable(CreateFrame())
F.GetEffectiveScale = function() return 0.64 end
F.SetTexCoord = function(self, ...) self.tc = { ... } end
F.SetTexture = function(self, t) self.tex = t end
F.SetSize = function(self, w, h) self.w, self.h = w, h end
F.CreateTexture = function(self) local t = setmetatable({ ev = {} }, F) TEXTURES[#TEXTURES + 1] = t return t end
function PIXEL_CONTROLS()
    TEXTURES = {}
    local S = HeadstartNS.Style
    local sw = S.Switch(CreateFrame(), function() return true end, function() end)
    local ck = S.Check(CreateFrame(), function() return true end, function() end)
    return sw, TEXTURES[1], TEXTURES[2], ck, TEXTURES[3], TEXTURES[4], TEXTURES[5]
end
""")
_sw_b, _track, _knob, _ck_b, _line, _fill, _tick = lua.eval("{ PIXEL_CONTROLS() }").values()
_art = "Interface\\AddOns\\Headstart\\art\\"
def _strip_at(tex, name, size, wide, cw, ch, lo, edge=True):
    y = sum(k + 2 for k in range(lo, size))
    tc = list(tex.tc.values())
    ok = tex.tex == _art + name and all(abs(a - b) < 1e-9 for a, b in zip(tc, (0, size * wide / cw, y / ch, (y + size) / ch)))
    try:
        from PIL import Image
        img = Image.open(os.path.join(ROOT, "art", name + ".tga")).getchannel("A")
        row = lambda r: max(img.getpixel((x, r)) for x in range(cw))
        ok = ok and row(y - 1) == 0 and row(y + size) == 0 and max(row(r) for r in range(y, y + size)) > 0
        ok = ok and (not edge or (row(y) > 0 and row(y + size - 1) > 0))     # (a box or a pill: edge to edge)
    except ImportError:
        pass
    return ok
check(_strip_at(_track, "px_pill", 24, 2, 128, 1024, 16) and _strip_at(_knob, "px_knob", 20, 1, 64, 1024, 10)
      and round(_sw_b.w * 1.2, 6) == 48 and round(_sw_b.h * 1.2, 6) == 24 and round(_knob.w * 1.2, 6) == 20,
      f"1.2 pixels to a point: the switch 48 x 24 pixels and its knob 20, each its own size of its strip ({_sw_b.w}, {_knob.w})")
check(_strip_at(_line, "px_box_line", 22, 1, 64, 1024, 14) and _strip_at(_fill, "px_box_fill", 22, 1, 64, 1024, 14)
      and _strip_at(_tick, "px_tick", 22, 1, 64, 1024, 14, False) and round(_ck_b.w * 1.2, 6) == 22,
      f"and the checkbox 22 pixels ({_ck_b.w})")
lua.execute("PIXELS = 3800")       # (5.9 pixels to a point: no strip that size)
_sw_b, _track, _knob, _ck_b, _line, _fill, _tick = lua.eval("{ PIXEL_CONTROLS() }").values()
check(_track.tex == _art + "pill" and _knob.tex == _art + "knob" and _sw_b.w == 40 and _ck_b.w == 18 and _line.tex == _art + "box_line",
      "far more pixels to a point than the strips have: the large textures, 40 x 20 and 18")
lua.execute("""
PixelUtil = KEPT_PU
local F = getmetatable(CreateFrame())
F.GetEffectiveScale, F.SetTexCoord, F.SetTexture, F.SetSize, F.CreateTexture = nil, nil, nil, nil, nil
""")
# /hs journey: with nothing after it (the window), and a made-up journey at a level
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
_wm = [cd for cd in _G.cards.values() if cd.title == "World marker"][0]
_G.SetOpen(_wm, True)
_open = _G.lift
_G.SetOpen(_wm, False)
_lift = _G.lift
check(_lift > _open and _G.tail is not None, f"what a page keeps under its cards comes up as a card above it shuts ({_open} to {_lift})")
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
YR.ShowSettingsTab(YR, "quests")
check(YR.WindowTab() == "qol" and YR.SettingsLayout("quests") is not None,
      "the Quests page, the reward picker's, opens with a hand-picked reward on file")
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
# The Levelling tab: Next route and All routes (here, with the routes installed), This run, and Settings at its foot.
# Building routes went on 2026-10-29 - the editor, Save as route, Share, Import - and the two route pages came back the
# same day, shown only with a routes addon (the owner: "hent dem tilbake bare med rutene installert").
for _key in ("where", "library", "run", "route"):
    YR.ToggleWindow(YR, _key)
    check(YR.WindowTab() == "levelling" and YR.WindowPage() == _key, f"{_key}: on the Levelling tab, built and filled ({YR.WindowPage()})")
_menu = {k: YR.TourTarget(f"levelling:{k}") for k in ("where", "library", "run", "route")}
check(all(_menu.values()) and _menu["where"].text.text == "Next route" and _menu["library"].text.text == "All routes"
      and _menu["run"].text.text == "This run" and _menu["route"].text.text == "Settings" and YR.TourTarget("levelling:builds") is None,
      "the menu, with the routes installed: Next route, All routes, This run, and Settings (Talents is QoL's)")
check(YR.TourTarget("levelling").text.text == "Routes" and [t.title for t in YR.TourSteps().values() if t.at == "levelling"] == ["Routes"],
      "the tab is called Routes (Levelling until 2026-10-21), on the tab and in the tour")
check(YR.InsertStep is None and YR.ShareOpen is None and YR.AskSaveRunAsRoute is None, "nothing of building routes is left to call")
# Next route: the one to take, and at most three after it
YR.ToggleWindow(YR, "where")
_w = YR.WherePageShown()
check(_w.best is not None and 1 <= _w.after <= 3 and _w.load in ("Load in RestedXP", "In RestedXP now"),
      f"Next route: {_w.best} to take, and the next {_w.after}")
# All routes: this character's, or every race's; the one to take marked; Load, and no Edit
g.YippRouteDB.allRoutes = None
YR.ToggleWindow(YR, "library")
_mine = list(YR.LibraryShown().values())
g.YippRouteDB.allRoutes = True
YR.RefreshWindow(YR)
_every = list(YR.LibraryShown().values())
g.YippRouteDB.allRoutes = None
YR.RefreshWindow(YR)
_keys = [r.key for r in _mine]
check("coldridge" in _keys and "northshire" not in _keys and len(_every) > len(_mine),
      f"All routes: this character's ({len(_mine)}), every race's ({len(_every)})")
check(any(r.key == _w.best and r.state in ("Take this one", "In RestedXP", "Your version", "Update waiting") for r in _mine),
      f"the route to take is marked on All routes ({[(r.key, r.state) for r in _mine][:3]})")
lua.execute("""
function FindButton(label)
    for _, f in ipairs(FRAMES) do
        local t = rawget(f, "text")
        if type(t) == "table" and rawget(t, "text") == label then return f end
    end
end""")
check(g.FindButton("Edit") is None and g.FindButton("See the steps") is None and g.FindButton("Import a route...") is None
      and g.FindButton("Load") is not None, "All routes and Next route: Load, and no Edit, See the steps or Import")
# with the routes off: their pages are the switch that turns them on; Talents is everyone's
_was_routes = g.YippRouteDB.routes
g.YippRouteDB.routes = False
YR.ToggleWindow(YR, "library")
_off = YR.WindowPage()
_off_lit = _menu["library"].selected is True
YR.ToggleWindow(YR, "builds")
_talents = YR.WindowShowing("builds") and YR.WindowTab() == "qol"
g.YippRouteDB.routes = _was_routes
YR.ToggleWindow(YR, "where")
check(_off == "routesoff" and _off_lit and _talents,
      f"routes off: All routes is the switch that turns them on, lit in the menu; Talents (QoL) opens ({_off})")
# Talents (QoL, Levelling): the trees and the order by level of the build in view; its switch follows that build here
YR.ToggleWindow(YR, "builds")
check(YR.WindowTab() == "qol" and YR.SettingsMenuGroups()["builds"] == "Levelling", "Talents is a QoL page, in the Levelling group")
_b = YR.BuildsShown()
_kept_build = g.YippSetupCharDB and g.YippSetupCharDB.talentBuild
YR.TalentFollow(None)
YR.RefreshWindow(YR)
_b.follow.scripts.OnClick(_b.follow)
_followed = YR.TalentFollowed()
check(_b.cells > 0 and _b.rows > 0 and _followed is not None and _followed.key == YR.BuildsShown().key,
      f"Talents: {_b.cells} talents on the trees, {_b.rows} lines by level; switched on, the build in view is followed")
YR.TalentFollow(_kept_build)
# Route settings: one list - the routes, group play, recording, the splits and the pace - without what moved
YR.ToggleWindow(YR, "route")
_L = YR.RouteSettingsLayout()
_titles = [cd.title for cd in _L.cards.values()]
check(_titles == ["Routes", "Group play", "Record runs", "Level splits", "Level pace"] and _L.ledger is True,
      f"Route settings: one list of five ({_titles})")
_gone = lua.eval("""(function()
    local gone = { ["Lock position"] = true, ["X position (pixels)"] = true, ["Y position (pixels)"] = true,
        ["Times over an hour"] = true, ["Background (percent)"] = true, ["Minimap button"] = true, ["Show level splits"] = true }
    local found = {}
    for _, f in ipairs(FRAMES) do
        local t = rawget(f, "title")
        if type(t) == "string" and gone[t] then found[#found + 1] = t end
    end
    return table.concat(found, ", ") end)()""")
check(_gone == "", f"the splits' place, lock, background and clock, and the minimap button, are not on it ({_gone})")
_st = YR.SplitsStyle(YR)
check(_st.lock is True and _st.bg == 0 and _st.clock == "full", "the splits: locked (Arrange places them), no background, the long clock")
# One-pixel lines: at 1.2 pixels to a point, a border's edge is 1/1.2 of a point
lua.execute("""
KEPT_PU = PixelUtil
PixelUtil = { GetPixelToUIUnitFactor = function() return 768 / 1440 end }
local F = getmetatable(CreateFrame())
F.GetEffectiveScale = function() return 0.64 end
F.SetHeight = function(self, h) self.h = h end
F.SetWidth = function(self, w) self.w = w end
HAIR = HeadstartNS.Style.Border(CreateFrame())
PixelUtil = KEPT_PU
F.GetEffectiveScale, F.SetHeight, F.SetWidth = nil, nil, nil""")
check(abs(g.HAIR[1].h * 1.2 - 1) < 1e-9 and abs(g.HAIR[3].w * 1.2 - 1) < 1e-9, f"a border's edge is one screen pixel ({g.HAIR[1].h})")
YR.ShowSettingsTab(YR, "trainer")
check(YR.WindowTab() == "qol", "the Trainer page is on the QoL tab")
# the menu's pages by their names, old ones included (the skins and the talent window had their own)
for key in ("start", "xpbar", "swing", "chat", "windows", "instances", "main", "rxpskin", "dmgskin", "skins", "talentwin"):
    YR.ShowSettingsTab(YR, key)
check(True, "Chat, Bars & windows, the two skins and the pages' old names open")
check(lua.eval('HeadstartNS.WindowTab()') == "interface", "the old names of the merged pages (the skins, the camps) open their page"
      " - the talent window's on the Interface tab")
for key, tab in (("home", "qol"), ("quests", "qol"), ("group", "qol"), ("general", "qol"), ("xpbar", "interface"), ("swing", "interface"),
                 ("windows", "interface"), ("talents", "interface"), ("skins", "interface"), ("invites", "qol"), ("talentwin", "interface")):
    YR.ShowSettingsTab(YR, key)
    check(YR.WindowTab() == tab, f"{key} opens on the {tab} tab ({YR.WindowTab()})")
found = YR.SettingsSearch("hourly limit")
check(found is not None and len(found) == 1 and found[1].key == "instances",
      "the instance tracker's settings are found on the Instances page")
YR.SettingsGo(found[1])
check(YR.WindowTab() == "qol" and YR.SettingsLayout("instances") is not None, "and going to one opens that page, on its tab")
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
            -- (RestedXP skin can't be on with no RestedXP loaded, as here: that is tested with the main switches)
            if f.get and f.name == "RestedXP skin" and not YR.RXPSkinAvailable() then
                if f.get() then out[#out + 1] = f.name .. " reads on without RestedXP" end
            elseif f.get then
                local was = f.get() and true or false
                f.set(not was)
                if (f.get() and true or false) == was then out[#out + 1] = f.name .. " switch" end
                f.set(was)
            elseif type(f.state()) ~= "string" then out[#out + 1] = f.name .. " state" end
        end
    end
    return table.concat(out, ", ") end)()""")
check(missing == "", f"every card on All features opens a section that exists, and its switch works ({missing})")
# its groups fold to their heading, say how many are on, and stay as you left them (the owner, 2026-10-20: "should
# there be some collapse here too?")
g.YippRouteDB.homeFolded = None
YR.RefreshWindow(YR)
_heads = list(YR.HomeHeads().values())
_auto = [h for h in _heads if h.name == "Automation"][0]
_cards = list(_auto.cards.values())
_open = not _auto.shut and all(c.hidden is not True for c in _cards) and " of " in str(_auto.count.text)
_auto.fn(_auto)
_shut = _auto.shut is True and all(c.hidden is True for c in _cards) and g.YippRouteDB.homeFolded.Automation is True
_auto.fn(_auto)
check(_open and _shut and not _auto.shut and all(c.hidden is not True for c in _cards) and g.YippRouteDB.homeFolded.Automation is None,
      f"All features: a group starts open, a click on its heading folds it (remembered), again opens it ({_auto.count.text})")
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
    -- (a tenth of a second on at each frame's call: the map's every-frame call is looked at ten times a second)
    function BOAT_CALL(method) if method == 'OnUpdate' then NOW = NOW + 0.1 end for p in pairs(BOAT_PROVIDERS) do p[method](p) end end
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
# (the other side's too was a setting until 2026-10-21: one still saved shows nothing more)
lua.execute("YippRouteDB.boatMapOther = true BOAT_CALL('OnUpdate')")
check(YR.BoatMapPins() == 5, f"an old 'the other side's too' saved: still your own side's ({YR.BoatMapPins()})")
lua.execute("YippRouteDB.boatMapOther = nil BOAT_CALL('OnUpdate')")
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
# the map calls every frame; the boats are placed ten times a second (the performance audit, 2026-10-20)
lua.execute("""local p = HeadstartNS.BoatMapPinFor("ratchetBB")
    BOAT_PLACED = 0 function p:SetPoint(_, _, _, x) self.px = x BOAT_PLACED = BOAT_PLACED + 1 end
    for i = 1, 6 do BOAT_AT = 0.6 + i * 0.01 for p in pairs(BOAT_PROVIDERS) do p.OnUpdate(p) end NOW = NOW + 0.02 end""")
check(1 <= g.BOAT_PLACED <= 2, f"six frames in a tenth of a second: the boat placed once or twice, not six times ({g.BOAT_PLACED})")
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
    UnitClass = function() return "Warrior", "WARRIOR", 1 end
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

# World marker: the map pin in the world - the game works the spot out (its navigation region), Headstart draws on it
lua.execute("""KEPT_RXP_WP = RXP
    KEPT_MAP_WP = {}
    for k, v in pairs(C_Map or {}) do KEPT_MAP_WP[k] = v end
    WP = { set = nil, tracked = false, sets = 0 }
    NAV_REGION = CreateFrame("Frame") NAV_ON = false
    C_Navigation = { GetFrame = function() return NAV_ON and NAV_REGION or nil end, GetDistance = function() return 275.97 end,
        HasValidScreenPosition = function() return true end, WasClampedToScreen = function() return false end,
        GetTargetState = function() return 2 end }
    C_Map = C_Map or {}
    C_Map.SetUserWaypoint = function(p) WP.set = p WP.sets = WP.sets + 1 return true end
    C_Map.GetUserWaypoint = function() return WP.set end
    C_Map.ClearUserWaypoint = function() WP.set = nil end
    C_Map.CanSetUserWaypointOnMap = function() return true end
    C_Map.GetBestMapForUnit = function() return 1429 end
    C_Map.GetMapInfo = function() return { name = "Elwynn Forest" } end
    WP.quest = 0
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) WP.tracked = on end, IsSuperTrackingUserWaypoint = function() return WP.tracked end,
        SetSuperTrackedQuestID = function(q) WP.quest = q if q ~= 0 then WP.tracked = false WP.pin = nil end end,
        GetSuperTrackedQuestID = function() return WP.quest end,
        SetSuperTrackedMapPin = function(t, id) WP.pin = { t, id } WP.quest = 0 WP.tracked = false end,
        GetSuperTrackedMapPin = function() if WP.pin then return WP.pin[1], WP.pin[2] end end,
        ClearSuperTrackedMapPin = function() WP.pin = nil end,
        GetHighestPrioritySuperTrackingType = function() if WP.quest ~= 0 then return 0 end if WP.pin then return 6 end
            if WP.tracked then return 1 end return nil end }
    KEPT_ENUM_WP = Enum Enum = Enum or {} KEPT_STT_WP, KEPT_STMP_WP = Enum.SuperTrackingType, Enum.SuperTrackingMapPinType
    Enum.SuperTrackingType = { Quest = 0, UserWaypoint = 1, Corpse = 2, MapPin = 6 }
    Enum.SuperTrackingMapPinType = { AreaPOI = 0, QuestOffer = 1 }
    -- (as the game's: the map, a 2D position, and the height if given)
    UiMapPoint = { CreateFromCoordinates = function(map, x, y, z) return { uiMapID = map, position = { x = x, y = y }, z = z } end }""")
check(not YR.WorldMarkerShown(), "the world marker starts off: nothing drawn")
g.SlashCmdList.HEADSTART("way 45 62")
check(g.WP.set is not None and g.WP.set.uiMapID == 1429 and abs(g.WP.set.position.x - 0.45) < 1e-9 and abs(g.WP.set.position.y - 0.62) < 1e-9 and g.WP.tracked is True,
      "/headstart way 45 62: a map pin there, in the zone you're in, and tracked")
lua.execute("YippRouteDB.waypoint = true NAV_ON = true HeadstartNS.ApplyParts()")
check(YR.WorldMarkerShown() and "276 yd" in YR.WorldMarkerText(), f"turned on: the marker on the game's spot for it, with how far ({YR.WorldMarkerText()})")
lua.execute("""local m = HeadstartWorldMarker
    function m:SetAlpha(a) self.al = a end
    local near = C_Navigation.GetDistance
    C_Navigation.GetDistance = function() return 450 end m.fn(m, 1) WM_FAR = HeadstartNS.WorldMarkerGoal()
    C_Navigation.GetDistance = near
    YippRouteDB.waypointRange = 200 m.fn(m, 1) WM_NEAR = HeadstartNS.WorldMarkerGoal()        -- (a range of its own was a setting until 2026-10-21)
    YippRouteDB.waypointRange = nil""")
# a pin put on the map comes untracked (the map's own code): tracked here, a moment later
lua.execute("""KEPT_HAS_WP = C_Map.HasUserWaypoint C_Map.HasUserWaypoint = function() return WP.set ~= nil end
    KEPT_AFTER_WP = C_Timer.After C_Timer.After = function(_, fn) fn() end
    KEPT_MAPFRAME_WP = WorldMapFrame WorldMapFrame = nil              -- (the map shut)
    WP.tracked = false Fire('USER_WAYPOINT_UPDATED') WM_TRACKED = WP.tracked
    C_Map.HasUserWaypoint, C_Timer.After, WorldMapFrame = KEPT_HAS_WP, KEPT_AFTER_WP, KEPT_MAPFRAME_WP""")
check(g.WM_TRACKED is True, "a pin put with Ctrl+click on the map (untracked by the map): tracked, so the marker has a spot")
# one look for every spot: no beam, the mark over the spot (over a quest's "?"), the same in a jump
lua.execute("""local m = HeadstartWorldMarker
    WM_HAS_BEAM = rawget(m, 'beam') ~= nil
    WP.quest = 179 Fire('SUPER_TRACKING_CHANGED') m.fn(m, 1) WM_QUEST_MARK = m.mark:IsShown()
    WP.quest = 0 WP.tracked = true Fire('SUPER_TRACKING_CHANGED') m.fn(m, 1) WM_PIN_MARK = m.mark:IsShown()""")
check(not g.WM_HAS_BEAM and g.WM_QUEST_MARK is True and g.WM_PIN_MARK is True,
      "no beam: a quest's spot and a map pin's both a mark over the spot")
check(g.WM_FAR == 0 and g.WM_NEAR == 1 and YR.WorldMarkerRange() == 400,
      f"farther off than 400 yards: nothing drawn; within it (276 yards, an old range of 200 saved): drawn ({g.WM_FAR}, {g.WM_NEAR})")
lua.execute("WP.sets = 0 HeadstartWorldMarker.fn(HeadstartWorldMarker, 1)")
check(g.WP.sets == 0, "looking at the marker sets no pin (a height given to one was not used by the game)")
lua.execute("NAV_ON = false Fire('NAVIGATION_FRAME_DESTROYED')")
check(not YR.WorldMarkerShown(), "the game's spot gone (pin reached or taken away): the marker too")
lua.execute("NAV_ON = true Fire('NAVIGATION_FRAME_CREATED', NAV_REGION)")
check(YR.WorldMarkerShown(), "a new one: there again")
g.SlashCmdList.HEADSTART("way")
check(g.WP.set is None, "/headstart way alone: the pin taken away")
# following RestedXP's arrow: the pin on its step's spot, set again only when that moves
lua.execute("""RXP = { arrowFrame = { element = { zone = 1429, x = 40, y = 60 } } }
    function RXP.UpdateGotoSteps() end function RXP.UpdateMap() end
    YippRouteDB.waypointRXP = true HeadstartNS.ApplyParts()""")
check(g.WP.set is not None and abs(g.WP.set.position.x - 0.40) < 1e-9 and abs(g.WP.set.position.y - 0.60) < 1e-9, "Follow RestedXP's arrow: the pin on the arrow's spot")
lua.execute("WP.sets = 0 HOOKS.UpdateGotoSteps()")
check(g.WP.sets == 0, "RestedXP looking again at the same spot: not set again")
lua.execute("RXP.arrowFrame.element = { zone = 1429, x = 52, y = 47 } HOOKS.UpdateGotoSteps()")
check(g.WP.sets == 1 and abs(g.WP.set.position.x - 0.52) < 1e-9, "the next step's spot: moved there")
# a step at an NPC is a pin like any other, RestedXP's spot (the owner, 2026-10-20: "Naowh Forever is very
# consistent" - the game's own spot for a quest came and went near the NPC and around a hand-in)
lua.execute("""KEPT_LOG_WP, KEPT_LOGIDX_WP, KEPT_AFTER_FOLLOW = LOG, C_QuestLog.GetLogIndexForQuestID, C_Timer.After
    LOG = { { 179, true } }
    C_QuestLog.GetLogIndexForQuestID = function(id) for i, q in ipairs(LOG) do if q[1] == id then return i end end return nil end
    local step = { elements = {} }
    step.elements[1] = { tag = "turnin", questId = 179, step = step }
    step.elements[2] = { tag = "accept", questId = 18, step = step }
    RXP.arrowFrame.element = { zone = 1429, x = 30, y = 70, step = step }
    WP.sets = 0 HOOKS.UpdateGotoSteps()""")
check(g.WP.quest == 0 and g.WP.pin is None and g.WP.sets == 1 and abs(g.WP.set.position.x - 0.30) < 1e-9,
      "a step that hands in and takes quests: RestedXP's spot as a map pin, nothing else tracked")
# the game took the pin away: on the way, put back (at most every three seconds); at the spot, arrived
lua.execute("""KEPT_POS_FOLLOW = UnitPosition function UnitPosition() return 0, 0, 0, 1 end      -- you at (0, 0)
    local e = RXP.arrowFrame.element e.wx, e.wy, e.instance = 200, 0, 1                         -- 200 yards on
    KEPT_HAS_FOLLOW = C_Map.HasUserWaypoint C_Map.HasUserWaypoint = function() return WP.set ~= nil end
    WP.set = nil WP.sets = 0 NOW = NOW + 10 HOOKS.UpdateGotoSteps()""")
check(g.WP.sets == 1 and g.WP.set is not None, "the game took the pin away on the way (200 yards off): put back")
lua.execute("WP.set = nil WP.sets = 0 HOOKS.UpdateGotoSteps()")
check(g.WP.sets == 0, "and not again within three seconds")
lua.execute("RXP.arrowFrame.element.wx = 5 WP.set = nil WP.sets = 0 NOW = NOW + 10 HOOKS.UpdateGotoSteps()")
check(g.WP.sets == 0, "taken away at the spot (5 yards off): you've arrived, it stays away")
lua.execute("""C_Map.HasUserWaypoint = KEPT_HAS_FOLLOW
    RXP.arrowFrame.element = { zone = 1429, x = 38, y = 78, step = { elements = {} } } WP.sets = 0 HOOKS.UpdateGotoSteps()""")
check(g.WP.sets == 1 and abs(g.WP.set.position.x - 0.38) < 1e-9, "the next step: its pin")
# a hearth step (RestedXP's .hs, "Hearth to Dolanaar"): no marker - the step before's pin taken away (the owner,
# 2026-10-16: a mark 200 yards off on a hearth step, "only confusing")
lua.execute("""KEPT_RXPC = RXPCData RXPCData = { currentStep = 2 }
    RXP.currentGuide = { steps = { { elements = {} }, { elements = { { tag = "hs", text = "Hearth to Dolanaar" } } } } }
    WP.sets = 0 HOOKS.UpdateGotoSteps()""")
check(g.WP.set is None and g.WP.sets == 0 and g.WP.pin is None and g.WP.quest == 0,
      "a hearth step: no marker, the step before's pin taken away")
lua.execute("WP.sets = 0 HOOKS.UpdateGotoSteps()")
check(g.WP.sets == 0 and g.WP.set is None, "and nothing put up again while it lasts")
lua.execute("RXPCData.currentStep = 1 HOOKS.UpdateGotoSteps()")
check(g.WP.sets == 1 and abs(g.WP.set.position.x - 0.38) < 1e-9, "hearthed, on the next step: its pin")
# where RestedXP has no spot, its arrow still holds the step before's: nothing shown (the owner, 2026-10-19: "the
# wrong place - I think I'm going one place and should be going another")
lua.execute("RXP.hideArrow = true WP.sets = 0 HOOKS.UpdateGotoSteps()")
check(g.WP.set is None and g.WP.sets == 0, "RestedXP hides its arrow (an .xp step, an instance): nothing shown, the pin taken away")
lua.execute("RXP.hideArrow = false HOOKS.UpdateGotoSteps()")
check(g.WP.sets == 1 and abs(g.WP.set.position.x - 0.38) < 1e-9, "its arrow back: the pin back")
lua.execute("RXP.arrowFrame.element.completed = true WP.sets = 0 HOOKS.UpdateGotoSteps()")
check(g.WP.set is not None and g.WP.sets == 0,
      "its spot ticked off while its step goes on (come within RestedXP's radius of the NPC): the pin stays")
lua.execute("RXP.arrowFrame.element.step.completed = true HOOKS.UpdateGotoSteps()")
check(g.WP.set is None and g.WP.sets == 0, "the step done too (the arrow still holds it): nothing shown")
lua.execute("RXP.arrowFrame.element.completed = nil RXP.arrowFrame.element.step.completed = nil HOOKS.UpdateGotoSteps()")
# RestedXP tracks the arrow step's quest itself (a hand-in): the pin is shown again over it; a quest you track
# yourself (of no step of the arrow's) is left alone (the log, 2026-10-20: the marker jumped between the two)
lua.execute("""local step = RXP.arrowFrame.element.step
    step.elements = { { tag = "turnin", questId = 179, step = step } }
    KEPT_HAS_GUARD = C_Map.HasUserWaypoint C_Map.HasUserWaypoint = function() return WP.set ~= nil end
    NOW = NOW + 10 WP.tracked = false WP.quest = 179 Fire('SUPER_TRACKING_CHANGED')""")
check(g.WP.tracked is True, "RestedXP tracked the step's quest: the pin shown again")
lua.execute("NOW = NOW + 10 WP.tracked = false WP.quest = 4161 Fire('SUPER_TRACKING_CHANGED')")
check(g.WP.tracked is False, "a quest of no step of the arrow's (yours): left as it is")
lua.execute("WP.quest = 0 WP.tracked = true C_Map.HasUserWaypoint = KEPT_HAS_GUARD")
notes = YR.WorldMarkerNotes()
texts = [str(notes[i]) for i in range(1, len(notes) + 1)]
check(len(texts) <= 15 and any("hides its arrow" in t for t in texts) and any("the pin shown again" in t for t in texts)
      and any("a map pin where RestedXP points" in t for t in texts), f"/headstart way log: what was chosen and why, the last 15 ({texts[-3:]})")
g.SlashCmdList.HEADSTART("way log")
# the pin on the NPC where the game has it near RestedXP's spot: a quest to take (its giver on the world map), a
# quest that is done (where it is handed in); far off, RestedXP's spot (the owner, 2026-10-20: "the marker is far
# from the NPC")
lua.execute("""KEPT_QL, KEPT_SIZE, KEPT_ONMAP, KEPT_READY = C_QuestLine, C_Map.GetMapWorldSize, C_QuestLog.GetQuestsOnMap, C_QuestLog.ReadyForTurnIn
    GIVER = { x = 0.385, y = 0.785 }
    C_QuestLine = { GetQuestLineInfo = function(q, map) if q == 500 and map == 1429 then return GIVER end end }
    C_Map.GetMapWorldSize = function() return 4000, 4000 end
    local step = RXP.arrowFrame.element.step
    step.elements = { { tag = "accept", questId = 500, step = step } }
    NOW = NOW + 10 WP.sets = 0 RXP.arrowFrame.element.x = 38.01 HOOKS.UpdateGotoSteps()""")
check(g.WP.sets == 1 and abs(g.WP.set.position.x - 0.385) < 1e-9 and abs(g.WP.set.position.y - 0.785) < 1e-9,
      "a quest to take, its giver 28 yards from RestedXP's spot: the pin on the giver")
lua.execute("GIVER = { x = 0.45, y = 0.785 } NOW = NOW + 10 WP.sets = 0 RXP.arrowFrame.element.x = 38.02 HOOKS.UpdateGotoSteps()")
check(g.WP.sets == 1 and abs(g.WP.set.position.x - 0.3802) < 1e-9,
      "its giver 280 yards off (another of that name, or the guide means a spot on the way): RestedXP's spot")
lua.execute("""local step = RXP.arrowFrame.element.step
    step.elements = { { tag = "turnin", questId = 179, step = step } }
    READY = false
    C_QuestLog.ReadyForTurnIn = function(q) return READY end
    C_QuestLog.GetQuestsOnMap = function(map) return { { questID = 179, x = 0.379, y = 0.781 } } end
    NOW = NOW + 10 WP.sets = 0 RXP.arrowFrame.element.x = 38.03 HOOKS.UpdateGotoSteps()""")
check(abs(g.WP.set.position.x - 0.3803) < 1e-9, "a hand-in not done yet (its spot on the map is the objective): RestedXP's spot")
lua.execute("READY = true NOW = NOW + 10 WP.sets = 0 RXP.arrowFrame.element.x = 38.04 HOOKS.UpdateGotoSteps()")
check(g.WP.sets == 1 and abs(g.WP.set.position.x - 0.379) < 1e-9, "a hand-in that is done: the pin where the game has it handed in")
notes = YR.WorldMarkerNotes()
check("as the game has it" in str(notes[len(notes)]), f"and the log says so ({notes[len(notes)]})")
lua.execute("""C_QuestLine, C_Map.GetMapWorldSize, C_QuestLog.GetQuestsOnMap, C_QuestLog.ReadyForTurnIn = KEPT_QL, KEPT_SIZE, KEPT_ONMAP, KEPT_READY
    RXP.arrowFrame.element.x = 38 RXP.arrowFrame.element.step.elements = {} NOW = NOW + 10 HOOKS.UpdateGotoSteps()""")
# under the mouse the mark says what it stands for: the step's NPC and quests (the owner, 2026-10-20)
lua.execute("""TIP = {} GameTooltip = { SetOwner = function() end, AddLine = function(_, t) TIP[#TIP + 1] = t end, Show = function() end, Hide = function() end }
    KEPT_TITLE = C_QuestLog.GetTitleForQuestID C_QuestLog.GetTitleForQuestID = function(q) if q == 500 then return "Report to Goldshire" end end
    local step = { elements = {} }                  -- (a step of its own: RestedXP's steps don't change their lines)
    step.elements = { { targets = { "Marshal Dughan::240" } }, { tag = "accept", questId = 500, step = step }, { tag = "turnin", questId = 501, step = step } }
    KEPT_STEP_WM = RXP.arrowFrame.element.step RXP.arrowFrame.element.step = step
    NOW = NOW + 10 RXP.arrowFrame.element.x = 38.05 HOOKS.UpdateGotoSteps()
    KEPT_HAS_TIP = C_Map.HasUserWaypoint C_Map.HasUserWaypoint = function() return WP.set ~= nil end""")
YR.WorldMarkerTip()
tip = [str(g.TIP[i]) for i in range(1, len(g.TIP) + 1)]
check(len(tip) >= 3 and tip[0] == "Marshal Dughan" and "Take: Report to Goldshire" in tip[1] and "Hand in:" in tip[2],
      f"under the mouse: the step's NPC, the quest to take there by name, the one to hand in ({tip})")
check(lua.eval("rawget(HeadstartWorldMarker, 'hit')") is None and lua.eval("rawget(HeadstartWorldMarker, 'mouse')") is not True,
      "the mark takes no mouse: nothing of it stands between the mouse and the NPC (the owner: \"in the way of clicking the NPC\")")
# the NPC's own tooltip says it instead - unless Quests on NPC tooltips is on (it says it, marked route)
lua.execute("""TIP = {} KEPT_GT_WM = GameTooltip
    GameTooltip = { AddLine = function(_, t) TIP[#TIP + 1] = t end, Show = function() end,
        GetUnit = function() return "Marshal Dughan", "mouseover" end }
    KEPT_GUID_TIP, KEPT_ISPLAYER_TIP = UnitGUID, UnitIsPlayer
    function UnitGUID(u) if u == "mouseover" then return "Creature-0-1-2-3-240-0001" end return KEPT_GUID_TIP and KEPT_GUID_TIP(u) end
    function UnitIsPlayer(u) if u == "mouseover" then return false end return KEPT_ISPLAYER_TIP and KEPT_ISPLAYER_TIP(u) end
    KEPT_QT_WM = YippRouteDB.questTips YippRouteDB.questTips = false""")
YR.WorldMarkerUnitTip(g.GameTooltip)
tip = [str(g.TIP[i]) for i in range(1, len(g.TIP) + 1)]
check(len(tip) == 2 and "Take: Report to Goldshire" in tip[0] and "Hand in:" in tip[1],
      f"over the step's NPC itself: its tooltip has the quest to take there and the one to hand in, no second name ({tip})")
lua.execute("TIP = {} YippRouteDB.questTips = true")
YR.WorldMarkerUnitTip(g.GameTooltip)
check(len(g.TIP) == 0, "with Quests on NPC tooltips on: nothing added (it says it already, marked route)")
lua.execute("""TIP = {} YippRouteDB.questTips = false GameTooltip.GetUnit = function() return "Someone", "mouseover" end
    function UnitGUID(u) if u == "mouseover" then return "Creature-0-1-2-3-999-0001" end return KEPT_GUID_TIP and KEPT_GUID_TIP(u) end""")
YR.WorldMarkerUnitTip(g.GameTooltip)
check(len(g.TIP) == 0, "another NPC: its tooltip as it is")
lua.execute("""GameTooltip, UnitGUID, UnitIsPlayer = KEPT_GT_WM, KEPT_GUID_TIP, KEPT_ISPLAYER_TIP
    YippRouteDB.questTips = KEPT_QT_WM""")
# the step's NPC with a nameplate on the screen: the marker over the plate - right over its "?" - and it stays there
# as the game takes the pin away at the NPC (the owner, 2026-10-20)
lua.execute("""PLATE240 = CreateFrame("Frame") function PLATE240:IsVisible() return true end
    KEPT_NP = C_NamePlate C_NamePlate = { GetNamePlateForUnit = function(u) if u == "nameplate5" then return PLATE240 end end,
        GetNamePlates = function() return {} end }
    KEPT_GUID_WM, KEPT_ISPLAYER_WM = UnitGUID, UnitIsPlayer
    function UnitGUID(u) if u == "nameplate5" then return "Creature-0-1-2-3-240-0001" end return KEPT_GUID_WM and KEPT_GUID_WM(u) end
    function UnitIsPlayer(u) if u == "nameplate5" then return false end return KEPT_ISPLAYER_WM and KEPT_ISPLAYER_WM(u) end
    Fire('NAME_PLATE_UNIT_ADDED', 'nameplate5')""")
check(lua.eval("HeadstartNS.WorldMarkerOnPlate() == PLATE240") and YR.WorldMarkerShown(),
      "the step's NPC's nameplate comes: the marker over it (right over its quest icon)")
# Glimmer lights that NPC: the marker out of the way, and a moment after (the owner, 2026-10-22)
lua.execute("""KEPT_LIT = HeadstartNS.GlimmerLitGiver LIT = false function HeadstartNS.GlimmerLitGiver() return LIT, false, LIT and PLATE240 or nil end
    local guid, isPlayer = UnitGUID, UnitIsPlayer
    function UnitGUID(u) if u == "softinteract" then return "Creature-0-1-2-3-240-0001" end return guid(u) end
    function UnitIsPlayer(u) if u == "softinteract" then return false end return isPlayer(u) end""")
_before = YR.WorldMarkerHeldBack()
lua.execute("LIT = true")
_lit = YR.WorldMarkerHeldBack()
lua.execute("LIT = false NOW = NOW + 1")
_moment = YR.WorldMarkerHeldBack()
lua.execute("NOW = NOW + 1")
_after = YR.WorldMarkerHeldBack()
check(not _before and _lit and _moment and not _after,
      f"Glimmer lights the step's NPC: the marker out of the way, a moment more after, then back ({_before}, {_lit}, {_moment}, {_after})")
# and seen from the marker itself: its plate is the interact key's target's, Glimmer lighting givers - though Glimmer's
# own answer says not lit (as in the game, 2026-10-22)
lua.execute("""NOW = NOW + 5 SOFT = true KEPT_LIGHTS = HeadstartNS.GlimmerLightsGivers function HeadstartNS.GlimmerLightsGivers() return true end
    local gp = C_NamePlate.GetNamePlateForUnit KEPT_GP = gp
    C_NamePlate.GetNamePlateForUnit = function(u) if u == "softinteract" and SOFT then return PLATE240 end return gp(u) end""")
_seen = YR.WorldMarkerHeldBack()
lua.execute("SOFT = false NOW = NOW + 5")
_gone = YR.WorldMarkerHeldBack()
check(_seen and not _gone, f"its plate the interact target's, givers lit: out of the way, though Glimmer says not lit ({_seen}, {_gone})")
lua.execute("C_NamePlate.GetNamePlateForUnit = KEPT_GP HeadstartNS.GlimmerLightsGivers = KEPT_LIGHTS")
_now = str(YR.WorldMarkerNow())
check(_now.startswith("now: marker shown") and "the step's NPC has one true" in _now,
      f"/headstart way log says how it stands now, against Glimmer's light ({_now[:90]})")
lua.execute("HeadstartNS.GlimmerLitGiver = KEPT_LIT")
lua.execute("NAV_ON = false Fire('NAVIGATION_FRAME_DESTROYED')")
check(YR.WorldMarkerShown() and lua.eval("HeadstartNS.WorldMarkerOnPlate() == PLATE240"),
      "the game takes the pin away at the NPC: the marker stays over it")
lua.execute("Fire('NAME_PLATE_UNIT_REMOVED', 'nameplate5')")
check(not YR.WorldMarkerShown() and YR.WorldMarkerOnPlate() is None, "its plate gone, and no pin: nothing")
lua.execute("""NAV_ON = true Fire('NAVIGATION_FRAME_CREATED', NAV_REGION)
    C_NamePlate, UnitGUID, UnitIsPlayer = KEPT_NP, KEPT_GUID_WM, KEPT_ISPLAYER_WM""")
lua.execute("""C_QuestLog.GetTitleForQuestID = KEPT_TITLE C_Map.HasUserWaypoint = KEPT_HAS_TIP
    RXP.arrowFrame.element.x = 38 RXP.arrowFrame.element.step = KEPT_STEP_WM RXP.arrowFrame.element.step.elements = {}
    NOW = NOW + 10 HOOKS.UpdateGotoSteps()""")
# the taint log: what Headstart did to the action bars, with when (as BugGrabber keeps its errors); a burst is one
# line, counted; the last 40 kept (the owner, 2026-10-20: an "action blocked" on the bars, and nothing to tell why)
lua.execute("""KEPT_TAINT = YippRouteDB.taintLog YippRouteDB.taintLog = nil KEPT_TIME = time function time() return CLOCK_T end
    CLOCK_T = 1000 for _ = 1, 3 do HeadstartNS.TaintNoted("put an action on the bars") end
    CLOCK_T = 1100 HeadstartNS.TaintNoted("changed the bars the old way")
    TL = YippRouteDB.taintLog TL1, TL2 = TL[1], TL[2]""")
check(len(g.TL) == 2 and g.TL1.n == 3 and g.TL1.at == 1000 and g.TL2.at == 1100 and g.TL2.n is None,
      "the taint log: a burst of three in ten seconds is one line, counted; another thing later its own, each with when")
lua.execute("for i = 1, 45 do CLOCK_T = 2000 + i * 20 HeadstartNS.TaintNoted('thing ' .. i) end TLN = #YippRouteDB.taintLog")
check(g.TLN == 40, f"at most 40 kept ({g.TLN})")
lua.execute("YippRouteDB.taintLog = KEPT_TAINT time = KEPT_TIME")
kept = g.YippRouteDB.markerLog
kept = [str(kept[i]) for i in range(1, len(kept) + 1)] if kept else []
check(len(kept) >= len(texts) and any("hides its arrow" in t for t in kept) and any("the game shows the way to" in t for t in kept),
      f"and kept in the saved file, with when it showed and hid ({len(kept)} lines, at most 200)")
lua.execute("RXPCData = KEPT_RXPC RXP.currentGuide = nil UnitPosition = KEPT_POS_FOLLOW")
lua.execute("""LOG, C_QuestLog.GetLogIndexForQuestID, C_Timer.After = KEPT_LOG_WP, KEPT_LOGIDX_WP, KEPT_AFTER_FOLLOW
    YippRouteDB.waypointRXP = nil YippRouteDB.waypoint = nil NAV_ON = false HeadstartNS.ApplyParts()
    Enum.SuperTrackingType, Enum.SuperTrackingMapPinType = KEPT_STT_WP, KEPT_STMP_WP Enum = KEPT_ENUM_WP
    RXP = KEPT_RXP_WP
    for _, k in ipairs({ "SetUserWaypoint", "ClearUserWaypoint", "CanSetUserWaypointOnMap", "GetBestMapForUnit", "GetMapInfo" }) do
        C_Map[k] = KEPT_MAP_WP[k]
    end""")
check(not YR.WorldMarkerShown(), "turned off: nothing drawn")

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
lua.execute("local b = HeadstartTour.next for i = 1, 9 do b.fn(b) end")
check(g.HeadstartTour.title.text == "Quality of life" and YR.WindowTab() == "qol", "the tour runs through in the window, on the QoL tab")
lua.execute("local b = HeadstartTour.next b.fn(b)")
check(g.HeadstartTour.hidden, "and is gone at Done")
# The first login's card (Welcome.lua; Core.lua puts it up), against the real window: Show me around opens it on
# All features with the tour; Set up this character turns Character setup on and opens its tab.
_kept_welcome = (g.YippRouteDB.welcome, g.YippRouteDB.welcomeSeen, g.YippRouteDB.setupOn)
lua.execute("YippRouteDB.welcome, YippRouteDB.welcomeSeen = true, nil HeadstartWindow:Hide()")
YR.WelcomeCard()
lua.execute("local b = HeadstartWelcomeCard.tour b.fn(b)")
check(g.HeadstartWelcomeCard.hidden and not g.HeadstartTour.hidden and YR.WindowShowing("home") and g.YippRouteDB.welcomeSeen,
      "the first login's card: Show me around - the window on All features, with the tour")
lua.execute("local b = HeadstartTour.skip b.fn(b) HeadstartWindow:Hide()")
lua.execute("YippRouteDB.welcome, YippRouteDB.welcomeSeen = true, nil")
YR.WelcomeCard()
lua.execute("local b = HeadstartWelcomeCard.setup b.fn(b)")
check(g.HeadstartWelcomeCard.hidden and g.YippRouteDB.setupOn is True and YR.WindowPage() == "setup"
      and not g.HeadstartWindow.hidden and g.YippRouteDB.welcomeSeen,
      f"and Set up this character - Character setup on, its tab open ({YR.WindowPage()})")
g.YippRouteDB.welcome, g.YippRouteDB.welcomeSeen, g.YippRouteDB.setupOn = _kept_welcome
# the news on the first page names cards that exist; the XP bar's samples; the accents
news_missing = lua.eval("""(function()
    local YR = HeadstartNS
    local _, news = YR.HomeNews()
    local have, out = {}, {}
    for _, group in ipairs(YR.HomeFeatures()) do for i = 2, #group do have[group[i].name] = true end end
    for name in pairs(news) do if not have[name] then out[#out + 1] = name end end
    return table.concat(out, ", ") end)()""")
check(news_missing == "", f"every card under New in this version is a feature there is ({news_missing})")
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
found = YR.SettingsSearch("battle.net whispers")
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
# its right-click menu: every window of ours whose feature is on, and Settings and the tour always (the test audit,
# 2026-10-20: the menu had no test)
lua.execute("KEPT_RECAP_M, KEPT_LOOT_M = YippRouteDB.deathRecap, YippRouteDB.lootFeed YippRouteDB.deathRecap, YippRouteDB.lootFeed = false, false")
_menu = [str(e[2]) for e in YR.WindowList().values()]
check("Settings" in _menu and "Headstart tour" in _menu and "The last time you died" not in _menu and "Loot log" not in _menu,
      f"the minimap button's menu: Settings and the tour, and no window of a feature that is off ({_menu})")
lua.execute("YippRouteDB.deathRecap, YippRouteDB.lootFeed = true, true")
_menu = [str(e[2]) for e in YR.WindowList().values()]
check("The last time you died" in _menu and "Loot log" in _menu, f"a feature turned on: its window in the menu ({_menu})")
YR.WindowMenu(g.HeadstartMinimapButton)
_dm = g.HeadstartDropMenu
check(_dm is not None and _dm.IsShown(_dm) and len(_dm.options) == len(_menu),
      f"the menu opens by the button with every window in it ({len(_dm.options) if _dm else None} of {len(_menu)})")
YR.WindowMenu(g.HeadstartMinimapButton)
check(not _dm.IsShown(_dm), "and the button again closes it")
# the button itself: a click opens the window, a right-click the menu, and a drag carries it round the minimap
lua.execute("""local YR, b = HeadstartNS, HeadstartMinimapButton
    CLICKED = {}
    KEPT_TOGGLE, KEPT_MENU = YR.ToggleWindow, YR.WindowMenu
    YR.ToggleWindow = function() CLICKED[#CLICKED + 1] = "window" end
    YR.WindowMenu = function(at) CLICKED[#CLICKED + 1] = at == b and "menu" or "menu elsewhere" end
    b.scripts.OnClick(b, "LeftButton")
    b.scripts.OnClick(b, "RightButton")
    YR.ToggleWindow, YR.WindowMenu = KEPT_TOGGLE, KEPT_MENU
    KEPT_ANGLE = YippRouteDB.minimapAngle
    Minimap.GetCenter = function() return 100, 100 end
    Minimap.GetEffectiveScale = function() return 1 end
    function GetCursorPosition() return 100, 150 end          -- straight above the minimap's middle
    b.scripts.OnDragStart(b)
    DRAGGING = b.scripts.OnUpdate ~= nil
    b.scripts.OnUpdate(b)
    DRAGGED = YippRouteDB.minimapAngle
    b.scripts.OnDragStop(b)
    DROPPED = b.scripts.OnUpdate == nil
    YippRouteDB.minimapAngle = KEPT_ANGLE""")
check(list(g.CLICKED.values()) == ["window", "menu"], f"the minimap button: a click opens the window, a right-click the menu by it ({list(g.CLICKED.values())})")
check(g.DRAGGING and abs(g.DRAGGED - 90) < 0.001 and g.DROPPED,
      f"dragged: it follows the pointer round the minimap (90 degrees, straight up), and lets go at the drop ({g.DRAGGED})")

# The Characters window (/headstart alts; the test audit, 2026-10-20: its data had tests, the window none): your
# characters on the left, what the picked one has on the right as a bag shows it, its currencies, and Forget
lua.execute("""local YR = HeadstartNS
    KEPT_ALTS, KEPT_ALTS_ON, KEPT_BAGS_A, KEPT_NAME_A = HeadstartAlts, YippRouteDB.alts, BAGS, C_Item.GetItemNameByID
    BAGS = {}                                   -- (the one you're on carries nothing)
    C_Item.GetItemNameByID = function(id) return ({ [2589] = "Linen Cloth", [4306] = "Silk Cloth" })[id] end
    HeadstartAlts = { ["Bo-Realm"] = { name = "Bo", class = "WARRIOR", level = 8, money = 900, seen = CLOCK - 7200,
        bags = { [2589] = 5, [4306] = 3 }, bank = { [4306] = 10 }, cur = { { id = 77, name = "Honor", qty = 300, icon = 1 } } },
        ["Cy-Realm"] = { name = "Cy", class = "MAGE", level = 30, money = 100, seen = CLOCK - 86400 * 3, bags = { [2589] = 20 }, bank = {} } }
    ALT_FROM = #FRAMES
    local function T(f) return f and rawget(f, "text") or "" end
    function ALT_SHOWN(kind)
        local out = {}
        for i = ALT_FROM + 1, #FRAMES do
            local f = FRAMES[i]
            if rawget(f, "hidden") == false then
                if kind == "chars" and rawget(f, "money") and rawget(f, "sub") then out[#out + 1] = T(f.name) .. " / " .. T(f.sub)
                elseif kind == "cells" and rawget(f, "edge") and rawget(f, "e") then out[#out + 1] = f.e.item .. "=" .. T(f.count)
                elseif kind == "lines" and rawget(f, "count") and rawget(f, "icon") and not rawget(f, "edge") then out[#out + 1] = T(f.name) .. " " .. T(f.count) end
            end
        end
        table.sort(out)
        return out
    end
    function ALT_ROW(name)
        for i = ALT_FROM + 1, #FRAMES do
            local f = FRAMES[i]
            if rawget(f, "money") and rawget(f, "sub") and T(f.name):find(name, 1, true) then return f end
        end
    end
    YippRouteDB.alts = false
    PRINTS = {}
    ALT_OFF = YR.AltsToggle()
    ALT_OFF_SAID = PRINTS[1]
    YippRouteDB.alts = true
    ALT_OPEN = YR.AltsToggle()""")
_win = g.HeadstartAltsWindow
check(g.ALT_OFF is False and "Characters is off" in str(g.ALT_OFF_SAID),
      f"Characters off: no window, and says where to turn it on ({g.ALT_OFF_SAID})")
_chars = list(g.ALT_SHOWN("chars").values())
check(g.ALT_OPEN is True and _win is not None and _win.IsShown(_win) and len(_chars) == 4
      and any(c.startswith("All characters / 3 of them") for c in _chars) and any("Bo|r / level 8" in c and "2 h ago" in c for c in _chars)
      and any("Cy|r / level 30" in c and "3 d ago" in c for c in _chars) and any("/ level 1" in c and "you" in c for c in _chars),
      f"Characters on: the window opens, all of them and each with level and when last played - you too, as you are now ({_chars})")
_cells = list(g.ALT_SHOWN("cells").values())
check(_cells == ["2589=25", "4306=13"], f"all characters: each item once, its count summed over bags and banks ({_cells})")
check("2 different items" in str(_win.note.text), f"and says how many ({_win.note.text})")
_bo = g.ALT_ROW("Bo")
_bo.scripts.OnClick(_bo)
_cells = list(g.ALT_SHOWN("cells").values())
check(_cells == ["2589=5", "4306=13"] and _win.forget.hidden is False, f"Bo picked: Bo's alone, bags and bank, and Forget offered ({_cells})")
_win.cur.scripts.OnClick(_win.cur)
_lines = list(g.ALT_SHOWN("lines").values())
check(_lines == ["Honor 300"] and len(list(g.ALT_SHOWN("cells").values())) == 0 and _win.search.hidden is True,
      f"Currencies: Bo's, and no items or search ({_lines})")
_win["items"].scripts.OnClick(_win["items"])         # (.items: lupa's own, in Python)
lua.execute("POPUP = nil")
_win.forget.scripts.OnClick(_win.forget)
check(g.POPUP == "HEADSTART_FORGET_ALT", "Forget asks first")
g.StaticPopupDialogs.HEADSTART_FORGET_ALT.OnAccept()
_chars = list(g.ALT_SHOWN("chars").values())
check(g.HeadstartAlts["Bo-Realm"] is None and len(_chars) == 3 and any(c.startswith("All characters / 2 of them") for c in _chars)
      and list(g.ALT_SHOWN("cells").values()) == ["2589=20"] and _win.forget.hidden is True,
      f"forgotten: Bo is gone from the list and from what is shown, back on all characters ({_chars})")
check(YR.AltsToggle() is False and _win.hidden is True, "the same again closes it")
lua.execute("""HeadstartAlts, YippRouteDB.alts, BAGS, C_Item.GetItemNameByID = KEPT_ALTS, KEPT_ALTS_ON, KEPT_BAGS_A, KEPT_NAME_A""")

# Every key of ours (Bindings.xml, Key Bindings > AddOns): named in the list, and doing what its name says (the test
# audit, 2026-10-20: the keys had no test - one calling a function that isn't there fails only when pressed)
_bxml = re.sub(r"<!--.*?-->", "", open(os.path.join(ROOT, "Bindings.xml"), encoding="utf-8").read(), flags=re.S)
_binds = re.findall(r'<Binding name="(\w+)"([^>]*)>\s*(.*?)\s*</Binding>', _bxml, flags=re.S)
lua.execute("""local YR = HeadstartNS
    KEYS_DID = {}
    local function Did(what) return function(...) KEYS_DID[#KEYS_DID + 1] = what end end
    KEPT_KEYS = { YR.AltsToggle, YR.ChatLogToggle, YR.LootLogToggle, YR.WindowMenu, YR.ToggleWindow, YR.Setup, YR.InviteTarget, YR.LeaveGroup, YR.UseGearSet }
    YR.AltsToggle, YR.ChatLogToggle, YR.LootLogToggle = Did("alts"), Did("chat"), Did("loot")
    YR.WindowMenu = function(at) KEYS_DID[#KEYS_DID + 1] = at == nil and "menu at the pointer" or "menu elsewhere" end
    YR.ToggleWindow, YR.Setup = Did("window"), { LayoutNext = function() KEYS_DID[#KEYS_DID + 1] = "next profile" return true end }
    YR.InviteTarget, YR.LeaveGroup = Did("invite"), Did("leave")
    YR.UseGearSet = function(n) KEYS_DID[#KEYS_DID + 1] = "set " .. tostring(n) end""")
_want = {"HEADSTART_WINDOW": "window", "HEADSTART_MENU": "menu at the pointer", "HEADSTART_LAYOUT": "next profile",
         "HEADSTART_ALTS": "alts", "HEADSTART_CHATLOG": "chat", "HEADSTART_LOOTLOG": "loot", "HEADSTART_INVITE": "invite",
         "HEADSTART_LEAVE": "leave", **{f"HEADSTART_GEARSET{i}": f"set {i}" for i in range(1, 6)}}
_keys_bad = []
for _name, _attrs, _body in _binds:
    lua.execute("KEYS_DID = {}")
    _said = g["BINDING_NAME_" + _name]
    try:
        lua.execute(_body)
        _did = list(g.KEYS_DID.values())
    except Exception as e:      # (a function that isn't there)
        _did = [f"error: {e}"]
    if not (isinstance(_said, str) and _said) or _did != [_want.get(_name)]:
        _keys_bad.append(f"{_name}: {_said!r} {_did}")
    if 'header="HEADSTART"' in _attrs and not g.BINDING_HEADER_HEADSTART:
        _keys_bad.append("BINDING_HEADER_HEADSTART missing")
check(len(_binds) == len(_want) and not _keys_bad, f"every key: named in Key Bindings, and does what its name says ({len(_binds)} keys; {_keys_bad})")
lua.execute("""local YR, k = HeadstartNS, KEPT_KEYS
    YR.AltsToggle, YR.ChatLogToggle, YR.LootLogToggle, YR.WindowMenu, YR.ToggleWindow, YR.Setup, YR.InviteTarget, YR.LeaveGroup, YR.UseGearSet =
        k[1], k[2], k[3], k[4], k[5], k[6], k[7], k[8], k[9]""")
lua.execute("YippRouteDB.deathRecap, YippRouteDB.lootFeed = KEPT_RECAP_M, KEPT_LOOT_M")
# /headstart perf: Headstart's memory, and its time a frame where the game's profiler is on
if YR.PerfLines is not None:
    lua.execute("""KEPT_PROF = C_AddOnProfiler
        KEPT_ENUM = Enum
        Enum = Enum or {}
        -- (the client's numbers, AddOnProfilerConstantsDocumentation, 70425)
        Enum.AddOnProfilerMetric = Enum.AddOnProfilerMetric or { SessionAverageTime = 0, RecentAverageTime = 1, PeakTime = 4,
            CountTimeOver1Ms = 5, CountTimeOver5Ms = 6 }
        KEPT_MEM, KEPT_ADDONS = GetAddOnMemoryUsage, C_AddOns
        C_AddOns = { IsAddOnLoaded = function(name) return name == "Headstart" end }   -- (ours loaded: Headstart alone)
        GetAddOnMemoryUsage = function() return 1234 end
        C_AddOnProfiler = { IsEnabled = function() return true end, GetAddOnMetric = function(name, m) return m == 1 and 0.05 or 0.02 end,
            GetTopKAddOnsForMetric = function() return { { addOnName = "RXPGuides", metricValue = 0.4 }, { addOnName = "Headstart", metricValue = 0.05 } } end,
            GetOverallMetric = function() return 0.5 end }""")
    _perf = [str(l) for l in YR.PerfLines().values()]
    check(_perf and _perf[0].startswith("Headstart in all: 1234 KB, 0.050 ms a frame now")
          and any("The most time a frame now (ms): RXPGuides 0.400, Headstart 0.050" in l for l in _perf)
          and any("Every addon together: 0.500 ms a frame; Headstart is 10.0%" in l for l in _perf),
          f"/headstart perf: memory, time a frame, beside the addons that take the most and all together ({_perf})")
    lua.execute("C_AddOnProfiler = nil")
    _perf = [str(l) for l in YR.PerfLines().values()]
    check(_perf and "profiler is off" in _perf[0], f"the game's profiler off: memory alone, and says so ({_perf[0] if _perf else None})")
    lua.execute("C_AddOnProfiler, Enum, GetAddOnMemoryUsage, C_AddOns = KEPT_PROF, KEPT_ENUM, KEPT_MEM, KEPT_ADDONS")
else:
    check(False, "/headstart perf: YR.PerfLines is there (Headstart_Options loaded)")
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
# /hs opens Settings, and closes the window when Settings is already showing
YR.ToggleWindow(YR, "run")
g.SlashCmdList.HEADSTARTSETTINGS("")
check(g.HeadstartWindow is not None and g.HeadstartWindow.hidden is False, "/hs opens Settings")
g.SlashCmdList.HEADSTARTSETTINGS("")
check(g.HeadstartWindow.hidden is True, "/hs again closes it")
lua.execute('''
function FindButton(label)
    for _, f in ipairs(FRAMES) do
        local t = rawget(f, "text")
        if type(t) == "table" and rawget(t, "text") == label then return f end
    end
end
''')

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
check(not any("has Headstart 9.9.9" in p_ for p_ in said), "a newer Headstart in the party: not said in chat")
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
import smoke_questskip
bad += smoke_questskip.run()
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
import smoke_editmode
bad += smoke_editmode.run()
import smoke_skipquests
bad += smoke_skipquests.run()
import smoke_wherenext
bad += smoke_wherenext.run()
import smoke_noroutes
bad += smoke_noroutes.run()
import smoke_window
bad += smoke_window.run()
# Naowh Forever's Glimmer is a part of NaowhForever_QoL since its 1.1.13: asked there whether it is on (ours looked for an
# addon NaowhForever_Glimmer that is gone - the review, 2026-10-21)
lua.execute("""KEPT_AO = C_AddOns
C_AddOns = { IsAddOnLoaded = function(name) return name == "NaowhForever_QoL" end }
NaowhForever = { Glimmer = { On = function() return NAOWH_GLIMMER end } }
NAOWH_GLIMMER = true""")
YR.EllesmereForget()
_naowh_on = YR.OtherHas("glimmer")
lua.execute("NAOWH_GLIMMER = false")
YR.EllesmereForget()
_naowh_off = YR.OtherHas("glimmer")
lua.execute("C_AddOns = KEPT_AO NaowhForever = nil")
YR.EllesmereForget()
check(_naowh_on == "Naowh Forever" and _naowh_off is None,
      f"Naowh Forever's Glimmer, in its QoL addon: named while it is on, not while it is off ({_naowh_on}, {_naowh_off})")
# Glimmer's quest givers while a RestedXP guide leads: the NPCs of the step under its arrow, by name or by ID (2026-10-21)
_route = lua.eval("""function(YR)
    local kept = { RXP, UnitName, UnitGUID, UnitIsPlayer }
    RXP = { arrowFrame = { element = { step = { elements = { { targets = { "Mountaineer Stormpike" } }, { tag = "goto" } } } } } }
    UnitIsPlayer = function() return false end
    UnitName = function(u) return u == "a" and "Mountaineer Stormpike" or "Someone Else" end
    UnitGUID = function(u) return "Creature-0-1-2-3-" .. (u == "a" and "1343" or "77") .. "-0000AB" end
    local a, b = YR.RouteStepNpc("a"), YR.RouteStepNpc("b")
    RXP.arrowFrame.element = nil
    local none = YR.RouteStepNpc("a")
    RXP, UnitName, UnitGUID, UnitIsPlayer = kept[1], kept[2], kept[3], kept[4]
    return a, b, none
end""")
_a, _b, _none = _route(YR)
check(_a is True and _b is False and _none is None,
      f"RestedXP's step: its NPC is it, another isn't, and with no step under the arrow nothing is said ({_a}, {_b}, {_none})")
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
import smoke_questitems
bad += smoke_questitems.run()
import smoke_questtips
bad += smoke_questtips.run()
import smoke_talents
bad += smoke_talents.run()
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
# The tests that are scripts of their own - Character setup's (Setup.lua, SetupUI.lua and Layouts.lua have no other),
# the camping reminder's and the live move's - run here too, so one smoke run is all of it (the test audit,
# 2026-10-20: these three were run by hand only).
import smoke_camping
bad += smoke_camping.run()
bad += _apart()
sys.exit(1 if bad else 0)
