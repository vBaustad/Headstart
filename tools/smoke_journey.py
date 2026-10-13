"""Smoke test of Journey (Journey.lua, and its window in Headstart_Options/Journey.lua) in Lua 5.1 (lupa).

    python tools/smoke_journey.py      (exit code 1 on any failure; tools/smoke.py runs it too)

The counting: a second on the road, in a fight, flying, away; yards from one look to the next, and a
jump too long to have been travelled left out; money named by what was open; loot and the best find;
kills by name; a level reached; a session. Then the window: every page made from that journey and put
up without an error, and the pages turned by hand only.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r'''
NOW, CLOCK, MONEY = 100, 1760000000, 1000
AFK, DEAD, TAXI, COMBAT, SWIM, REST, GROUPED = false, false, false, false, false, false, false
X, Y, WHERE, ZONE = 0, 0, 1, "Teldrassil"
function GetTime() return NOW end
function time() return CLOCK end
function date(f, t) if f == "%H" then return "21" end if f == "%Y-%m-%d" then return "2026-10-13" end return "13 October" end
function UnitIsAFK() return AFK end
function UnitIsDeadOrGhost() return DEAD end
function UnitOnTaxi() return TAXI end
function UnitAffectingCombat() return COMBAT end
function IsSwimming() return SWIM end
function IsResting() return REST end
function IsInInstance() return false end
function IsInGroup() return GROUPED end
function IsInRaid() return false end
function GetNumGroupMembers() return GROUPED and 2 or 0 end
TARGET, TARGET_GUID = nil, nil
function UnitName(u) if u == "player" then return "Fellia" end if u == "target" then return TARGET end return u == "party1" and "Duplo" or "Moray" end
function UnitGUID(u) return u == "target" and TARGET_GUID or nil end
function strsplit(sep, s)
    local out = {}
    for piece in (s .. sep):gmatch("(.-)%" .. sep) do out[#out + 1] = piece end
    return unpack(out)
end
function SetPortraitTextureFromCreatureDisplayID(tex, display) rawset(tex, "portrait", display) end
function UnitRace() return "Night Elf" end
function UnitClass() return "Rogue", "ROGUE" end
LEVEL, XPMAX = 6, 2800
function UnitLevel() return LEVEL end
function UnitXPMax() return XPMAX end
function GetRealZoneText() return ZONE end
function UnitPosition() return Y, X, 0, WHERE end
function GetMoney() return MONEY end
MOUNTED, KNOWN = false, {}
function IsMounted() return MOUNTED end
function IsPlayerSpell(id) return KNOWN[id] == true end
function GetItemInfo(link) return "Item", link, link:find("Blade") and 3 or 1, link:find("Blade") and 20 or 5, nil, nil, nil, nil, nil, 135 end
function issecretvalue() return false end
HOOKS = {}
COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
ITEM_QUALITY_COLORS = {}
UISpecialFrames = {}
function tinsert(t, v) t[#t + 1] = v end
function CreateColor(r, g, b, a) return { r, g, b, a } end
function GetCursorPosition() return 0, 0 end
YippRouteDB = {}
C_Timer = { After = function() end }
C_ChatInfo = { SendChatMessage = function() end }
function hooksecurefunc(a, b, c)
    if type(a) == "table" then local was = a[b] a[b] = function(...) was(...) c(...) end else HOOKS[a] = b end
end
PART = nil
YR = { QoLOn = function() return true end, Open = function(v) return v end, Print = function() end,
    LootFromText = function(msg) local link, n = msg:match("^You receive loot: (.-)x?(%d*)%.$") if link then return link, tonumber(n) or 1 end end,
    Part = function(want, events, handler, opt) PART = { want = want, handler = handler, opt = opt } return PART end,
    LoadWindow = function() return true end, ApplyParts = function() end }
HeadstartNS = YR
-- frames for the window: anything asked of them is there and does nothing, what is set can be read back
local F = {}
F.__index = function(t, k) return rawget(F, k) or function() end end
function F:CreateTexture() return setmetatable({}, F) end
function F:CreateFontString() return setmetatable({}, F) end
function F:CreateAnimationGroup() return setmetatable({}, F) end
function F:CreateAnimation() return setmetatable({}, F) end
function F:SetScript(w, fn) rawset(self, "_" .. w, fn) end
function F:Show() rawset(self, "shown", true) end
function F:Hide() rawset(self, "shown", false) end
function F:SetShown(on) rawset(self, "shown", on and true or false) end
function F:IsShown() return rawget(self, "shown") ~= false end
function F:SetText(t) rawset(self, "words", t) end
function F:SetWidth(w) rawset(self, "width", w) end
function F:GetFrameLevel() return 1 end
function F:SetEnabled(on) rawset(self, "enabled", on and true or false) end
function F:SetTexture(t) rawset(self, "portrait", nil) rawset(self, "tex", t) end
function F:SetCreature(id) rawset(self, "creature", id) end
function F:GetDisplayInfo() return rawget(self, "creature") and rawget(self, "creature") + 10000 or 0 end      -- (a display for every creature)
function F:GetEffectiveScale() return 1 end
function F:GetLeft() return 0 end
function F:IsMouseOver() return false end
function CreateFrame(kind, name) local f = setmetatable({}, F) if name then _G[name] = f end return f end
UIParent = setmetatable({}, F)
YR.Style = { Border = function() return {} end }
'''


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok   " if ok else "FAIL ") + what)
        if not ok:
            bad += 1

    load = lua.eval("function(src, name) local f = assert(loadstring(src, name)) f('Headstart', YR) end")
    # Core.lua's reader of the game's sentences (the kill line is read with it): those two functions alone
    core = open(os.path.join(ROOT, "Core.lua"), encoding="utf-8").read()
    lua.execute(core[core.index("--- A pattern from one of the game's own sentences"):core.index("--- Quality of life on or off")])
    load(open(os.path.join(ROOT, "Journey.lua"), encoding="utf-8").read(), "Journey.lua")
    YR = g.YR
    YR.StartJourney()
    part = g.PART
    check(part.want() is True and YR.JourneyData() is None, "a new install: on, and nothing kept before it has begun")
    g.YippRouteDB.journey = False
    check(part.want() is False, "turned off: not wanted")
    g.YippRouteDB.journey = None
    part.opt.start()
    j = YR.JourneyData()
    check(j is not None and j.sessions == 1 and j.days["2026-10-13"] is True, "begun: a session, a day")

    def second(n=1):
        for _ in range(n):
            lua.execute("NOW = NOW + 1")
            part.opt.tick()

    second()                                    # the first look: nowhere to have come from yet
    lua.execute("X = X + 7")
    second()
    check(abs(j.d.foot - 7) < 0.001 and j.t.road == 2 and j.t.all == 2, f"a second on the road: seven yards on foot ({j.d.foot})")
    lua.execute("X = X + 4000")
    second()
    check(abs(j.d.foot - 7) < 0.001, "a jump too long to have been travelled (a hearth): not counted")
    lua.execute("TAXI = true X = X + 60")
    second()
    check(j.flights == 1 and abs(j.d.taxi - 60) < 0.001 and j.t.taxi == 1, "flying: a flight, sixty yards in the air")
    lua.execute("TAXI = false COMBAT = true")
    second(3)
    lua.execute("COMBAT = false AFK = true")
    second(2)
    lua.execute("AFK = false REST = true")
    second()
    check(j.t.combat == 3 and j.t.afk == 2 and j.t.rest == 1 and j.zone.Teldrassil == j.t.all and j.hours[21] == j.t.all,
          "three seconds fighting, two away, one in town; all of it in the zone and the hour")
    lua.execute("NOW = NOW + 300")
    part.opt.tick()
    check(j.t.all == 11, f"a loading screen: one second, not three hundred ({j.t.all})")

    ev = part.handler
    lua.execute("MONEY = MONEY + 50")
    ev(None, "LOOT_OPENED")
    second()
    ev(None, "LOOT_CLOSED")
    ev(None, "QUEST_TURNED_IN", 7, 300, 120)
    lua.execute("MONEY = MONEY + 120 NOW = NOW + 10")
    second()
    ev(None, "MERCHANT_SHOW")
    lua.execute("MONEY = MONEY + 30")
    second()
    lua.execute("MONEY = MONEY - 20")
    second()
    g.HOOKS.RepairAllItems()
    lua.execute("MONEY = MONEY - 15")
    second()
    ev(None, "MERCHANT_CLOSED")
    ev(None, "TRAINER_SHOW")
    lua.execute("MONEY = MONEY - 100")
    second()
    ev(None, "TRAINER_CLOSED")
    check(j.gold.loot == 50 and j.gold.quest == 120 and j.gold.vendor == 30 and j.spent.vendor == 20 and j.spent.repair == 15
          and j.spent.train == 100 and j.gold.peak == 1200 and j.quests == 1 and j.xpQuest == 300,
          "money named by what was open: looted, a quest's, sold, bought, repaired, trained; the most ever carried")
    ev(None, "CHAT_MSG_LOOT", "You receive loot: [Linen Cloth]x3.")
    ev(None, "CHAT_MSG_LOOT", "You receive loot: [Blade of Something].")
    ev(None, "CHAT_MSG_LOOT", "You receive loot: [Linen Cloth].")
    check(j.loot.n == 5 and j.loot.q[1] == 4 and j.loot.q[3] == 1 and j.loot.best.link == "[Blade of Something]" and j.loot.best.zone == "Teldrassil",
          "loot counted by quality, and the best find kept")
    ev(None, "CHAT_MSG_COMBAT_XP_GAIN", "Young Nightsaber dies, you gain 45 experience.")
    check(j.mobId["Young Nightsaber"] is None, "a kill with something else targeted: no creature ID guessed for it")
    lua.execute('TARGET, TARGET_GUID = "Young Nightsaber", "Creature-0-4400-1-87-2031-0000A1B2C3"')
    ev(None, "CHAT_MSG_COMBAT_XP_GAIN", "Young Nightsaber dies, you gain 45 experience.")
    ev(None, "CHAT_MSG_COMBAT_XP_GAIN", "You gain 10 experience.")
    check(j.kills == 2 and j.mobs["Young Nightsaber"] == 2 and j.xpKill == 90, "kills by name; XP that wasn't a kill left out")
    check(j.mobId["Young Nightsaber"] == 2031, "the dead target's creature ID kept with its name, for its portrait")
    lua.execute('TARGET, TARGET_GUID = "Fellia", "Player-4400-0A1B2C3D"')
    ev(None, "CHAT_MSG_COMBAT_XP_GAIN", "Fellia dies, you gain 1 experience.")
    check(j.mobId["Fellia"] is None and j.kills == 3, "a target that is no creature: no ID")
    j.kills, j.xpKill, j.mobs["Fellia"], j.mobCount = 2, 90, None, 1
    lua.execute('TARGET, TARGET_GUID = nil, nil')
    ev(None, "PLAYER_DEAD")
    ev(None, "PLAYER_LEVEL_UP", 7)
    ev(None, "UNIT_SPELLCAST_SUCCEEDED", "player", "x", 8690)
    g.HOOKS.JumpOrAscendStart()
    lua.execute("GROUPED = true")
    ev(None, "GROUP_ROSTER_UPDATE")
    check(j.deaths == 1 and j.deathZone.Teldrassil == 1 and j.levels[7].zone == "Teldrassil" and j.hearths == 1 and j.jumps == 1
          and j.groups == 1 and j.mateCount == 2, "a death, a level, a hearth, a jump, a group and who was in it")
    check(g.HeadstartJourneyToast is None, "level 7: no note")
    # pace: level 7 takes 3,600 XP and an hour (45 monsters' worth: one gives 80); level 8 takes 4,500 and half an
    # hour (106 an hour: one gives 85) - the better pace
    lua.execute("LEVEL, XPMAX = 7, 3600")
    second()
    j.levels[7].t = 0
    j.t.all = 3600
    ev(None, "PLAYER_LEVEL_UP", 8)
    lua.execute("LEVEL, XPMAX = 8, 4500")
    second()
    j.t.all = 5400
    ev(None, "PLAYER_LEVEL_UP", 9)
    check(j.need[7] == 3600 and j.need[8] == 4500, "what each level takes is kept")
    lua.execute("C_ChatInfo.SendChatMessage('hello', 'GUILD') C_ChatInfo.SendChatMessage('hi') C_ChatInfo.SendChatMessage('x', 'guild') C_ChatInfo.SendChatMessage('away', 'AFK')")
    check(j.chat.GUILD == 2 and j.chat.SAY == 1 and j.chat.AFK is None, "what you wrote, counted by where: the kind, never the words")
    # riding: learned from a trainer (found by its spell as the trainer's window shuts), then yards in the saddle
    lua.execute("MONEY = 1000000")
    second()
    check(j.ride is None and j.walked is True and j.mount is None, "100 gold in the bag is not riding: on foot until it is learned")
    lua.execute("MONEY = 1200")
    second()
    ev(None, "TRAINER_SHOW")
    lua.execute("KNOWN[826] = true")
    ev(None, "TRAINER_CLOSED")
    check(j.ride is not None and j.ride.level == 8 and j.ride.seen is None and j.ride.before is None,
          "riding learned at a trainer: the moment kept, with the level")
    foot = j.d.foot
    lua.execute("MOUNTED = true")
    second()
    lua.execute("X = X + 12")
    second()
    lua.execute("MOUNTED = false")
    check(abs(j.d.ride - 12) < 0.001 and j.d.foot == foot and j.t.ride == 2, "mounted: twelve yards in the saddle, none of them on foot")
    # a character that can already ride when the logging starts has no moment to tell
    old = lua.eval("""function()
        local kept = HeadstartJourney
        HeadstartJourney = nil
        PART.opt.stop() PART.opt.start()
        local was = HeadstartJourney.ride
        HeadstartJourney = kept
        PART.opt.stop() PART.opt.start()
        return was end""")()
    check(old is not None and old.before is True and old.level is None, "could ride before anything was logged: no moment made up")
    j = YR.JourneyData()
    # the skill not found by its spells: the first time in the saddle says it (told as that, not as learning)
    saddle = lua.eval("""function()
        local kept, known = HeadstartJourney, KNOWN
        HeadstartJourney, KNOWN = nil, {}
        PART.opt.stop() PART.opt.start()
        local j = HeadstartJourney
        local walked = j.walked
        MOUNTED = true NOW = NOW + 1 PART.opt.tick() MOUNTED = false
        local ride = j.ride
        -- and on a character first logged at 40 or over, being mounted says nothing about when
        HeadstartJourney, LEVEL = nil, 45
        PART.opt.stop() PART.opt.start()
        MOUNTED = true NOW = NOW + 1 PART.opt.tick() MOUNTED = false
        local late = HeadstartJourney.ride
        HeadstartJourney, KNOWN, LEVEL = kept, known, 8
        PART.opt.stop() PART.opt.start()
        return walked, ride and ride.seen, ride and ride.level, late and late.before end""")
    w, seen, lvl, late = saddle()
    check(w is True and seen is True and lvl == 8 and late is True,
          f"riding not found as a spell: the first time mounted is the moment, unless logging began at 40 or over ({w}, {seen}, {lvl}, {late})")
    j = YR.JourneyData()
    ev(None, "PLAYER_LEVEL_UP", 20)
    check(g.HeadstartJourneyToast is not None and lua.eval("rawget(rawget(HeadstartJourneyToast, 'title'), 'words')") == "Level 20!",
          "level 20: a small note")
    lua.execute("""OPENED = 0 YR.JourneyShow = function() OPENED = OPENED + 1 end
        rawget(HeadstartJourneyToast, '_OnClick')(HeadstartJourneyToast, 'RightButton')""")
    check(g.OPENED == 0 and lua.eval("rawget(HeadstartJourneyToast, 'shown')") is False, "a right-click on the note: put away, nothing opened")
    lua.execute("HeadstartJourneyToast:Show() rawget(HeadstartJourneyToast, '_OnClick')(HeadstartJourneyToast, 'LeftButton') YR.JourneyShow = nil")
    check(g.OPENED == 1 and lua.eval("rawget(HeadstartJourneyToast, 'shown')") is False, "a click on the note: your journey opens, and the note goes")
    g.YippRouteDB.journeyToast = False
    lua.execute("HeadstartJourneyToast:Hide()")
    ev(None, "PLAYER_LEVEL_UP", 30)
    check(lua.eval("rawget(HeadstartJourneyToast, 'shown')") is False, "the note turned off: none at 30")
    part.opt.stop()
    part.opt.start()
    check(YR.JourneyData().sessions == 1, "a /reload: the same session")
    lua.execute("CLOCK = CLOCK + 4000")
    part.opt.stop()
    part.opt.start()
    check(YR.JourneyData().sessions == 2, "back after an hour: a new one")

    # chapters: reaching 20 and 30 (the note's test above) wrote one each, the journey as it stood
    j = YR.JourneyData()
    c20 = j.chapters[20]
    check(c20 is not None and j.chapters[30] is not None and j.chapters[7] is None and c20.level == 20 and c20.kills == 2
          and c20.mobs["Young Nightsaber"] == 2 and c20.mobId["Young Nightsaber"] == 2031 and c20.dayCount == 1 and c20.days is None,
          "reaching 20 and 30 wrote a chapter each (and 7, 8, 9 none): the totals, the mobs with their faces, the days as a count")
    ev(None, "CHAT_MSG_COMBAT_XP_GAIN", "Young Nightsaber dies, you gain 45 experience.")
    lua.execute("MONEY = MONEY + 77")
    second()
    check(c20.kills == 2 and c20.mobs["Young Nightsaber"] == 2 and j.kills == 3 and c20.gold.other != j.gold.other,
          "a chapter is a copy: what is counted after it does not change what it tells")

    # the window: the latest chapter, every page made and put up, the pages turned by hand only
    load2 = lua.eval("function(src, name) local f = assert(loadstring(src, name)) f('Headstart_Options', {}) end")
    load2(open(os.path.join(ROOT, "Headstart_Options", "Journey.lua"), encoding="utf-8").read(), "Options/Journey.lua")
    raw = lua.eval("rawget")

    def word(name):
        return raw(raw(win, name), "words")

    def row(i, part="name"):
        return raw(raw(raw(raw(win, "rows"), i), part), "words")

    def mark(i, what):
        return raw(raw(raw(win, "marks"), i), what)

    def page(kicker, *show):
        YR.JourneyShow(*show)
        for _ in range(16):
            if word("kicker") == kicker:
                return True
            YR.JourneyTurn(1)
        return False

    YR.JourneyShow()
    win = g.HeadstartJourneyWindow
    check(raw(win, "shown") is True and word("kicker") == "YOUR JOURNEY SO FAR" and word("big") == "Fellia" and "Level 30" in word("unit")
          and "pit stop at level 30" in word("quip"),
          f"the window opens on the latest chapter, told at its level whatever level you are now ({word('unit')})")
    check(mark(1, "shown") is True and mark(2, "shown") is True and mark(3, "shown") is False and mark(2, "enabled") is False and mark(1, "enabled") is True,
          "the chapters there are stand along the top; the one being told can't be clicked")
    tick = raw(win, "_OnUpdate")
    words = []
    for _ in range(14):
        YR.JourneyTurn(1)
        for _ in range(30):
            tick(win, 0.1)
        words.append(word("kicker"))
    seen = list(dict.fromkeys(words))
    check(seen == ["THE ROAD BEHIND YOU", "WHERE THE HOURS WENT", "LEVEL BY LEVEL", "GOLD EARNED", "YOUR BEST FIND", "THE WORLD YOU SAW",
                   "ALONG THE WAY", "YOUR HABITS", "WORDS ON THE ROAD", "FEATS OF THE ROAD", "THE JOURNEY SO FAR"],
          f"a chapter's pages, each put up without an error ({seen})")
    check(page("LEVEL BY LEVEL") and "level 8 to 9" in word("quip") and "worth 106 monsters" in word("quip"),
          f"the fastest level is the best pace, not the fewest minutes ({word('quip')})")
    names = [(row(i), row(i, "amount"), row(i, "detail")) for i in range(1, 4)]
    check(names[0][0] == "Best pace" and names[0][1] == "Level 8 to 9" and "106 kills' worth of XP an hour" in names[0][2]
          and all(len(n[0]) + len(n[1]) < 34 for n in names),
          f"a level row: what it is and which level on one line, its figures on the line under ({names[0]})")
    YR.JourneyTurn(-1)
    check(word("kicker") == "WHERE THE HOURS WENT", "the page before")
    for _ in range(14):
        YR.JourneyTurn(-1)
    check(word("kicker") == "YOUR JOURNEY SO FAR", "past the first page: nothing, it stays the first")
    for _ in range(140):
        tick(win, 0.1)
    check(word("kicker") == "YOUR JOURNEY SO FAR", "left alone, the page stays: nothing turns by itself")
    raw(raw(raw(win, "marks"), 1), "_OnClick")()
    check("Level 20" in word("unit") and mark(1, "enabled") is False and mark(2, "enabled") is True, "a click on an earlier chapter tells that one")
    found = page("ALONG THE WAY", None, 20)
    tick(win, 1)
    check(found and word("big") == "2" and YR.JourneyData().kills == 3, f"and it tells what it held, not what was counted since ({word('big')})")

    # the levels since the chapter before, against the road up to then (here: the running totals at 34 against chapter 30)
    c30 = j.chapters[30]
    lua.execute("LEVEL = 34")
    kept = (j.t.all, j.kills, j.deaths, j.quests)
    j.t.all, j.kills, j.deaths, j.quests = c30.t.all + 7200, c30.kills + 100, c30.deaths + 2, c30.quests + 9
    check(page("LEVEL 30 TO 34", None, "live") and word("unit") == "is what these levels took" and row(2) == "Enemies an hour"
          and row(2, "amount") == "50" and "before level 30" in row(2, "detail") and row(5) == "Deaths" and row(5, "amount") == "2"
          and "one every 1h 0m" in row(5, "detail"),
          f"since the chapter before: by the hour, with the road before it beside each ({row(2, 'amount')}, {row(5, 'detail')})")
    j.t.all, j.kills, j.deaths, j.quests = kept
    # old enough to ride and not riding: said from the level after 40
    ride = j.ride
    j.ride = None
    lua.execute("LEVEL = 45")
    check(page("THE ROAD BEHIND YOU", None, "live") and "Level 45, and every yard of it without a mount" in word("quip"),
          "past 40 and not riding: the road page says so")
    check(page("GOLD EARNED", None, "live") and "still walking" in word("quip"), "and the gold page says how far the purse is from a mount")
    j.ride = ride
    lua.execute("LEVEL = 8")

    # the sample: a chapter at every milestone up to the level picked, never a level between
    YR.JourneyShow(50)
    check("Level 50" in word("unit") and YR.JourneyData().kills == 3, "the sample at level 50: shown, and nothing of yours changed")
    check([mark(i, "shown") for i in range(1, 6)] == [True, True, True, True, False] and mark(4, "enabled") is False,
          "the sample has the chapters up to its level")
    best = lua.eval("""function()
        local j, top, at = HeadstartNS.JourneySample(50), 0, 0
        for l = 3, 50 do
            local pace = j.need[l - 1] / (45 + 5 * (l - 1)) / (j.levels[l].t - j.levels[l - 1].t)
            if pace > top then top, at = pace, l end
        end
        return at end""")()
    check(5 < best < 48, f"in the sample the best pace is neither the first level nor the last ({best})")
    kickers = []
    for _ in range(14):
        YR.JourneyTurn(1)
        tick(win, 1)
        kickers.append(word("kicker"))
        if kickers[-1] == "GOLD EARNED":
            gold = word("quip")
        if kickers[-1] == "FEATS OF THE ROAD":
            feats = (word("big"), word("unit"), word("quip"), row(2, "amount"))
    check(word("count") == "13 / 13" and "WORDS ON THE ROAD" in kickers and kickers[0] == "LEVEL 40 TO 50",
          f"every page of the sample put up, the second one the levels since the chapter before ({kickers[0]})")
    check("mount" not in gold.lower() or "times over" in gold, f"at 50, riding learned: the gold page has nothing to say of walking ({gold[:60]})")
    # feats at 50: 4,750 enemies is four milestones of six (100, 500, 1,000, 2,500), the fifth at 5,000
    check(feats[1] == "of 33 milestones reached" and "Next milestone" in feats[2] and "rung" not in feats[2],
          f"the feats page: milestones reached, and the closest next ({feats})")
    check(feats[3] == "4,750 of 5,000", f"a feat's row is the tally against its next milestone ({feats[3]})")
    raw(raw(raw(win, "marks"), 2), "_OnClick")()
    check("Level 30" in word("unit") and mark(4, "shown") is True, "a click on one of the sample's chapters tells that one, the others still there")
    for asked, got in ((47, "Level 40"), (8, "Level 20"), (99, "Level 60")):
        YR.JourneyShow(asked)
        check(got in word("unit"), f"a sample asked for at {asked} is told at a level a chapter is written at ({word('unit')})")
    # the mobs' own faces: the sample knows which creatures they were
    check(page("ALONG THE WAY", 50), "the sample's page of enemies")
    faces = [raw(raw(raw(raw(win, "rows"), i), "icon"), "portrait") for i in range(1, 6)]
    check(faces[0] == 10671 and all(f and f > 10000 for f in faces) and raw(raw(win, "icon"), "portrait") == 10671,
          f"the enemies you met most have their own faces, the one met most at the head of the page ({faces})")
    YR.JourneyTurn(1)
    check(raw(raw(win, "icon"), "portrait") is None and raw(raw(raw(raw(win, "rows"), 1), "icon"), "portrait") is None,
          "and the next page has its own pictures back")
    # the sample's best find is among what its tally says was looted; the rare kinds have the bars
    for lvl, name in ((40, "Cruel Barb"), (50, "Staff of Jordan")):
        check(page("YOUR BEST FIND", lvl) and word("big") == name, f"the sample at {lvl}: the best find is {name}, as its tally has it ({word('big')})")
    shares = [raw(raw(raw(win, "rows"), i), "share") for i in range(1, 6)]
    check([row(i, "amount") for i in range(1, 6)] == ["1", "8", "650", "3,750", "3,500"] and 0.08 < shares[0] < shares[1] < shares[2] == 1
          and shares[3] is False and shares[4] is False,
          f"loot: one epic has a bar that can be seen beside 650 greens; white and grey are a number each, no bar ({shares})")
    check(page("THE ROAD BEHIND YOU", 50) and "learned to ride at level 43" in word("quip") and "In the saddle" in [row(i) for i in range(1, 6)],
          f"at 50 the road page says when you learned to ride, and has the saddle's yards ({word('quip')[-70:]})")
    YR.JourneyShow(60)
    check(word("kicker") == "THE JOURNEY, COMPLETE" and "Sixty." in word("quip"), "at 60 it is told as a road walked to its end")
    check(page("THE ROAD BEHIND YOU", 40) and "without a mount" not in word("quip"), "at 40 itself nobody rides yet: the road page leaves it be")
    check(page("GOLD EARNED", 40) and "Level 40: old enough to ride" in word("quip"), "and the gold page says what riding and a mount come to")

    # no chapter yet: the window says when the first, or the next, is written
    YR.JourneyReset()
    YR.JourneyShow()
    check(word("big") == "Level 20" and "first chapter" in word("unit") and "12 levels to go" in word("quip") and mark(1, "shown") is False,
          f"started over at level 8: the first chapter comes at 20 ({word('quip')[-20:]})")
    lua.execute("LEVEL = 34")
    YR.JourneyShow()
    check(word("big") == "Level 40" and "next chapter" in word("unit"), "first logged at 34: the next one comes at 40")
    lua.execute("LEVEL = 60")
    YR.JourneyShow()
    check(word("big") == "Level 60" and "before anything was logged" in word("unit"), "already 60 when the logging began: said so")
    g.YippRouteDB.journey = False
    YR.JourneyShow()
    check(word("big") == "Not being logged", "turned off: the window says so")
    g.YippRouteDB.journey = None
    lua.execute("LEVEL = 8")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
