"""Smoke test of Quests on NPC tooltips (QuestTips.lua), in Lua 5.1 (lupa).

    python tools/smoke_questtips.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Off on a new install, with no hook; on, what an NPC offers is written down as you talk to it (gossip, a quest
greeting, a quest put to you, a hand-in), and its tooltip lists the quests to hand in and to take - not one you
have done or are on - and the quests your RestedXP route takes there, marked route. Nothing in a fight, nothing
while off. Uses smoke.py's fake game.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def files(folder, toc):
    return [os.path.join(folder, l.strip().replace(chr(92), "/"))
            for l in open(os.path.join(folder, toc), encoding="utf-8")
            if l.strip().endswith(".lua") and not l.startswith("#") and not l.startswith("Libs")]


def run():
    src = open(os.path.join(ROOT, "tools", "smoke.py"), encoding="utf-8").read()
    env = {"__name__": "smoke_head", "__file__": os.path.join(ROOT, "tools", "smoke.py")}
    exec(compile(src.split("YR = lua.table()")[0], "smoke.py (head)", "exec"), env)
    lua = env["lua"]
    lua.execute("""
        TIP_POST = {}
        TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) TIP_POST[kind] = fn end }
        Enum = Enum or {}
        Enum.TooltipDataType = Enum.TooltipDataType or { Item = 0, Unit = 2 }
        TIP_LINES = {}
        GameTooltip = { AddLine = function(self, t) TIP_LINES[#TIP_LINES + 1] = t end, Show = function() end,
            GetUnit = function() return TIP_NAME, "mouseover" end, SetOwner = function() end, Hide = function() end,
            HookScript = function() end }
        TIP_NAME = "Warden Thelwater"
        DONE, ONQUEST, READY, TITLES = {}, {}, {}, { [200] = "Report to Goldshire" }
        C_QuestLog = C_QuestLog or {}
        C_QuestLog.IsQuestFlaggedCompleted = function(q) return DONE[q] == true end
        C_QuestLog.IsOnQuest = function(q) return ONQUEST[q] == true end
        C_QuestLog.ReadyForTurnIn = function(q) return READY[q] == true end
        C_QuestLog.GetTitleForQuestID = function(q) return TITLES[q] end
        NPC_GUID = "Creature-0-1-2-3-1234-0001"
        KEPT_GUID = UnitGUID
        function UnitGUID(unit) if unit == "npc" or unit == "mouseover" then return NPC_GUID end return KEPT_GUID and KEPT_GUID(unit) end
        C_GossipInfo = {
            GetAvailableQuests = function() return { { questID = 100, title = "Wolves at the Gate", questLevel = 5 },
                { questID = 101, title = "Bear Hides", questLevel = 6 } } end,
            GetActiveQuests = function() return { { questID = 50 } } end }
        FIGHT = false
        function InCombatLockdown() return FIGHT end
        YippRouteDB = nil YippSetupCharDB = nil""")
    YR = lua.table()
    load = lua.eval("function(c, n) return assert(loadstring(c, n)) end")
    for f in files(ROOT, "Headstart.toc"):
        load(open(f, encoding="utf-8").read(), os.path.basename(f))("Headstart", YR)
    g = lua.globals()
    g.Fire("ADDON_LOADED", "Headstart")
    g.Fire("PLAYER_LOGIN")
    db = g.YippRouteDB
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def tip(guid="Creature-0-1-2-3-1234-0002"):
        lua.execute("TIP_LINES = {}")
        post = g.TIP_POST[g.Enum.TooltipDataType.Unit]
        if post is None:
            return []
        post(g.GameTooltip, lua.table_from({"guid": guid}))
        return [str(g.TIP_LINES[i]) for i in range(1, len(g.TIP_LINES) + 1)]

    check("questTips" in YR.STARTS_OFF and not YR.Option("questTips") and g.TIP_POST[g.Enum.TooltipDataType.Unit] is None,
          "off on a new install: the tooltips aren't hooked")
    db.questTips = True
    YR.ApplyParts()
    check(g.TIP_POST[g.Enum.TooltipDataType.Unit] is not None, "on: the unit tooltips hooked")
    check(tip() == [], "an NPC never talked to, not on the route: nothing added")

    # talking to it: what it offers, and the quest of yours it takes in, written down
    g.Fire("GOSSIP_SHOW")
    offers = db.npcQuests[1234]
    check(offers is not None and offers[100][1] == "Wolves at the Gate" and offers[101][2] == 6 and db.questEnds[50] == 1234,
          "talked to: its two quests and the one it takes in, written down for the account")
    lines = tip()
    check(len(lines) == 3 and lines[0] == " " and "132049" in lines[1] and any("Wolves at the Gate" in l for l in lines)
          and any("Bear Hides" in l for l in lines), f"hovered: its quests listed with ! ({lines})")
    lua.execute("ONQUEST[100] = true")
    lines = tip()
    check(not any("Wolves" in l for l in lines) and any("Bear Hides" in l for l in lines), "one taken: it goes from the list")
    lua.execute("ONQUEST[50] = true READY[50] = true TITLES[50] = 'Lost Necklace'")
    lines = tip()
    check(len(lines) >= 2 and "132048" in lines[1] and "Lost Necklace" in lines[1], f"a quest of yours done and handed in here: first, with ? ({lines})")
    lua.execute("DONE[101] = true ONQUEST[50] = false READY[50] = false")
    check(tip() == [], "the rest done: nothing left to say")

    # a quest greeting (an NPC with quests and no gossip), a quest put to you, a hand-in
    lua.execute("""NPC_GUID = "Creature-0-1-2-3-777-0001"
        function GetNumAvailableQuests() return 1 end
        function GetAvailableQuestInfo(i) return false, 0, false, false, 300 end
        function GetAvailableTitle(i) return "Kobold Candles" end
        function GetNumActiveQuests() return 0 end
        function GetQuestID() return 301 end
        function GetTitleText() return "Spider Silk" end""")
    g.Fire("QUEST_GREETING")
    g.Fire("QUEST_DETAIL")
    g.Fire("QUEST_COMPLETE")
    check(db.npcQuests[777][300][1] == "Kobold Candles" and db.npcQuests[777][301][1] == "Spider Silk" and db.questEnds[301] == 777,
          "a quest greeting, a quest put to you and a hand-in: each written down")

    # the route: a step ahead that takes a quest at this NPC (by its id on the .target line)
    lua.execute("""RXP = { currentGuide = { name = "Elwynn", steps = {
            { elements = { { targets = { "Marshal Dughan::240" } }, { tag = "accept", questId = 200 } } } } } }
        RXPCData = { currentStep = 1 }""")
    lines = tip("Creature-0-1-2-3-240-0009")
    check(any("Report to Goldshire" in l and "route" in l for l in lines), f"an NPC the route takes a quest from: listed, marked route ({lines})")
    lua.execute("FIGHT = true")
    check(tip("Creature-0-1-2-3-240-0009") == [], "in a fight: nothing (a unit can be secret then)")
    lua.execute("FIGHT = false")
    check(tip("Player-1-0001") == [], "a player: nothing")
    # QuestieDB: every quest the NPC starts that this character can take now, and the done ones it takes in
    lua.execute("""
        local Q = {
            [400] = { name = "Gnolls in the Fields", requiredLevel = 1, questLevel = 8 },
            [401] = { name = "Too High Yet", requiredLevel = 50, questLevel = 52 },
            [402] = { name = "Horde Only", requiredLevel = 1, requiredRaces = 2 },            -- (race 2: an orc)
            [403] = { name = "After the Gnolls", requiredLevel = 1, preQuestSingle = { 400 } },
            [404] = { name = "A Tailor's Task", requiredLevel = 1, requiredSkill = { 197, 50 } },
            [405] = { name = "Bring Back the Pelts", requiredLevel = 1 } }
        local N = { [555] = { questStarts = { 400, 401, 402, 403, 404 }, questEnds = { 405 } } }
        LibQuestieDB = { contractVersion = 2, RequireContract = function(v) return v >= 1 and v <= 2 end,
            Quest = { Get = function(id, key) return Q[id] and Q[id][key] end },
            Npc = { Get = function(id, key) return N[id] and N[id][key] end } }
        function UnitRace() return "Human", "Human", 1 end
        function UnitClass() return "Warrior", "WARRIOR", 1 end
        function UnitLevel() return 10 end""")
    YR.QuestTipsDB()
    lines = tip("Creature-0-1-2-3-555-0001")
    check(any("Gnolls in the Fields" in l for l in lines) and not any(w in l for l in lines for w in ("Too High", "Horde Only", "After the Gnolls", "Tailor")),
          f"QuestieDB: the quest this character can take now - not one too high, of the other side, after another, or a profession's ({lines})")
    lua.execute("ONQUEST[405] = true READY[405] = true")
    lines = tip("Creature-0-1-2-3-555-0001")
    check(len(lines) >= 2 and "132048" in lines[1] and "Bring Back the Pelts" in lines[1], f"QuestieDB: a done quest it takes in, first ({lines})")
    lua.execute("ONQUEST[405] = false READY[405] = false DONE[400] = true")
    lines = tip("Creature-0-1-2-3-555-0001")
    check(any("After the Gnolls" in l for l in lines) and not any("Gnolls in the Fields" in l for l in lines),
          f"the one before done: the next one listed, the done one gone ({lines})")
    lua.execute("LibQuestieDB.RequireContract = function(v) return false, 'too new' end")
    check(YR.QuestTipsDB() is False, "a QuestieDB that doesn't speak contract 1: not read")
    lua.execute("LibQuestieDB = nil")
    YR.QuestTipsDB()
    # a hostile mob gives no quest: its tooltip is left as it is, nothing looked through (the performance audit)
    lua.execute("KEPT_ENEMY, KEPT_CANATTACK = UnitIsEnemy, UnitCanAttack function UnitIsEnemy(_, u) return u == 'mouseover' end")
    check(tip("Creature-0-1-2-3-240-0009") == [], "a hostile mob: nothing added, nothing looked through")
    # a neutral quest giver (Booty Bay's) can be attacked but isn't hostile: its quests are listed (the review, 2026-10-21)
    lua.execute("function UnitIsEnemy() return false end function UnitCanAttack(_, u) return u == 'mouseover' end")
    check(any("Report to Goldshire" in l for l in tip("Creature-0-1-2-3-240-0009")), "a neutral NPC you could attack: its quest lines")
    lua.execute("UnitIsEnemy, UnitCanAttack = KEPT_ENEMY, KEPT_CANATTACK")
    check(any("Report to Goldshire" in l for l in tip("Creature-0-1-2-3-240-0009")), "the same NPC as a friendly one: its quest lines")
    # Questie lists an NPC's quests itself: with its quest lines on, ours are left out
    lua.execute("Questie = { db = { profile = { enableTooltips = true, showQuestsInNpcTooltip = true } } }")
    check(tip("Creature-0-1-2-3-240-0009") == [], "Questie listing NPCs' quests: nothing of ours (no quest twice)")
    lua.execute("Questie.db.profile.showQuestsInNpcTooltip = false")
    check(any("Report to Goldshire" in l for l in tip("Creature-0-1-2-3-240-0009")), "Questie's quest lines off: ours back")
    lua.execute("Questie = nil")
    db.questTips = False
    YR.ApplyParts()
    check(tip("Creature-0-1-2-3-240-0009") == [], "off: the hook stays (it can't come off), and adds nothing")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
