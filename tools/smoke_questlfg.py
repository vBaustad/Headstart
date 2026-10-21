"""Smoke test of Quest group (QuestLFG.lua): asking chat for a group for a quest, and who answers.

    python tools/smoke_questlfg.py      (exit code 1 on any failure; tools/smoke.py runs it too)

In Lua 5.1 (lupa), against a small fake of the game: a quest log, chat channels, and what was sent.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r"""
NOW, SENT, SAID, PARTS, CHANGED, INVITED, SECRET = 1000, {}, {}, {}, 0, {}, {}
function GetTime() return NOW end
function issecretvalue(v) return v == SECRET end
function UnitName() return "Me" end
function Ambiguate(n) return (n:gsub("%-.*", "")) end
QUESTS = {
    { isHeader = true, title = "Westfall" },
    { questID = 11, title = "The Defias Brotherhood", level = 18, suggestedGroup = 5 },
    { questID = 12, title = "Red Silk Bandanas", level = 17, suggestedGroup = 0 },
    { questID = 13, title = "Hogger", level = 11, suggestedGroup = 3 },
    { questID = 14, title = "Done Already", level = 20, suggestedGroup = 0, done = true },
    { questID = 15, title = "Rat", level = 5, suggestedGroup = 0 },
}
C_QuestLog = {
    GetNumQuestLogEntries = function() return #QUESTS end,
    GetInfo = function(i) return QUESTS[i] end,
    IsComplete = function(id) for _, q in ipairs(QUESTS) do if q.questID == id then return q.done == true end end end,
    GetQuestWatchType = function(id) return id == 12 and 1 or nil end,
}
CHANNELS = { 1, "General - Westfall", false, 2, "Trade - City", false }
function GetChannelList() return unpack(CHANNELS) end
C_ChatInfo = { SendChatMessage = function(msg, kind, lang, target) SENT[#SENT + 1] = { msg, kind, target } end }
C_PartyInfo = { InviteUnit = function(n) INVITED[#INVITED + 1] = n end }
YippRouteDB = { questLFG = true }
YR = {
    Option = function(k) return YippRouteDB[k] == true end,
    Print = function(s) SAID[#SAID + 1] = s end,
    SettingChanged = function() CHANGED = CHANGED + 1 end,
    Part = function(want, events, handler, opt) PARTS[#PARTS + 1] = { want = want, events = events, handler = handler, opt = opt } end,
}
"""


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    YR = lua.eval("YR")
    lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, "QuestLFG.lua"), encoding="utf-8").read(), "QuestLFG.lua")("Headstart", YR)
    g = lua.globals()
    shelved = YR.QuestLFGAvailable is False and YR.QuestLFGOn() is False and YR.QuestLFGToggle() is False
    YR.QuestLFGAvailable = True          # the feature is shelved: its tests run with it brought back
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    check(shelved, "shelved: not available, never on, and its window doesn't open")
    quests = list(YR.QuestLFGQuests().values())
    check([q.id for q in quests] == [11, 13, 12, 15], f"your quests: the ones meant for a group first, then by level; a finished one left out ({[q.id for q in quests]})")
    check(quests[0].group == 5 and quests[2].tracked is True and quests[2].group is None, "with how many it is meant for, and whether you track it")
    check(YR.QuestLFGMatch("lfm the defias brotherhood, need healer").id == 11, "a line of chat naming a quest, whatever its case")
    check(YR.QuestLFGMatch("anyone for |cffffff00|Hquest:13:11|h[Hoger]|h|r ?").id == 13, "or linking it")
    check(YR.QuestLFGMatch("WTS [Red Silk] cheap") is None and YR.QuestLFGMatch("separate the rats") is None and YR.QuestLFGMatch(g.SECRET) is None,
          "a line about something else, a quest name too short to tell by, a secret line: nothing")
    cid = YR.QuestLFGChannel()
    check(cid == (2, "Trade - City"), f"where it asks: channel 2 when there's no LookingForGroup ({cid})")
    lua.execute('CHANNELS = { 1, "General - Westfall", false, 2, "Trade - City", false, 4, "LookingForGroup", false }')
    check(YR.QuestLFGChannel() == (4, "LookingForGroup"), "LookingForGroup while you're in it")
    g.YippRouteDB.questLFGChannel = "General - Westfall"
    check(YR.QuestLFGChannel() == (1, "General - Westfall"), "or the one you chose")
    g.YippRouteDB.questLFGChannel = "A Channel I Left"
    check(YR.QuestLFGChannel() == (4, "LookingForGroup"), "one you chose and left: the automatic one")
    g.YippRouteDB.questLFGChannel = None
    check(YR.QuestLFGMessage(quests[1]) == "LFG Hogger", "what is said: LFG and the quest")
    g.YippRouteDB.questLFGText = "LFM {quest} ({level}), anyone?"
    check(YR.QuestLFGMessage(quests[1]) == "LFM Hogger (11), anyone?", "or your own words")
    g.YippRouteDB.questLFGText = "no quest in this"
    check(YR.QuestLFGMessage(quests[1]) == "LFG Hogger", "words without the quest in them: the first ones")
    g.YippRouteDB.questLFGText = None

    # the parts: nothing of chat is read until there's a reason
    YR.StartQuestLFG()
    main, chan, whisp = g.PARTS[1], g.PARTS[2], g.PARTS[3]
    g.YippRouteDB.questLFGWatch = False
    check(main.want() and not chan.want() and not whisp.want(), "on, not asking, 'others looking' off: no chat is read")
    ok = YR.QuestLFGAsk(quests[1])
    check(ok is True and len(g.SENT) == 1 and list(g.SENT[1].values()) == ["LFG Hogger", "CHANNEL", 4],
          f"Ask: said once, in the channel ({list(g.SENT[1].values()) if len(g.SENT) else None})")
    check(chan.want() and whisp.want() and g.CHANGED >= 1, "asking: channel chat and whispers are read")
    ok, why = YR.QuestLFGAsk(quests[0])
    check(ok is False and "wait" in why and len(g.SENT) == 1, f"a second post at once: not sent ({why})")

    # answers
    chan.handler(None, "CHAT_MSG_CHANNEL", "I'll come for hogger", "Bo-Realm")
    chan.handler(None, "CHAT_MSG_CHANNEL", "LFG Hogger", "Me")
    chan.handler(None, "CHAT_MSG_CHANNEL", g.SECRET, "Zed")
    chan.handler(None, "CHAT_MSG_CHANNEL", "lfm the defias brotherhood", "Cy")
    r = list(YR.QuestLFGReplies().values())
    check(len(r) == 1 and r[0].who == "Bo-Realm" and r[0].kind == "channel" and r[0].id == 13,
          "someone naming your quest in chat is an answer; your own line, a secret one and (with 'others' off) another quest's aren't")
    whisp.handler(None, "CHAT_MSG_WHISPER", "inv pls", "Dee")
    r = list(YR.QuestLFGReplies().values())
    check(len(r) == 2 and r[0].who == "Dee" and r[0].kind == "whisper" and r[0].id == 13, "a whisper while you're asking: an answer to that quest")
    chan.handler(None, "CHAT_MSG_CHANNEL", "still up for Hogger?", "Bo-Realm")
    r = list(YR.QuestLFGReplies().values())
    check(len(r) == 2 and r[1].text == "still up for Hogger?", "the same player about the same quest again: their latest words, not another line")
    check(YR.QuestLFGUnseen() == 2 and not any("answered about" in s for s in g.SAID.values()),
          "counted as not looked at (the eye's number), and not said in chat")
    YR.QuestLFGInvite("Bo-Realm")
    check(list(g.INVITED.values()) == ["Bo-Realm"], "Invite invites them")

    # others looking for a quest you have
    g.YippRouteDB.questLFGWatch = None
    chan.handler(None, "CHAT_MSG_CHANNEL", "LFM The Defias Brotherhood", "Cy")
    r = list(YR.QuestLFGReplies().values())
    check(r[0].who == "Cy" and r[0].kind == "other" and r[0].id == 11, "'others looking' on: someone asking for a quest you have is noted")

    # half a minute on: asked again; a quarter of an hour on: whispers aren't answers any more
    g.NOW = g.NOW + 31
    check(YR.QuestLFGAsk(quests[0]) is True and len(g.SENT) == 2 and g.SENT[2][1] == "LFG The Defias Brotherhood", "half a minute on: the next post goes out")
    g.NOW = g.NOW + 1000
    n = len(list(YR.QuestLFGReplies().values()))
    whisp.handler(None, "CHAT_MSG_WHISPER", "hello", "Eve")
    check(len(list(YR.QuestLFGReplies().values())) == n and not whisp.want(), "a quarter of an hour after the last post: a whisper is just a whisper")
    # the quest handed in: no longer asked for
    g.NOW = g.NOW + 60
    YR.QuestLFGAsk(quests[1])
    lua.execute("table.remove(QUESTS, 4)")
    main.handler(None, "QUEST_REMOVED", 13)
    check(YR.QuestLFGAsking()[13] is None and YR.QuestLFGMatch("lfg hogger") is None, "the quest gone from your log: not asked for, and not matched")
    YR.QuestLFGStop(11)
    g.YippRouteDB.questLFGWatch = False
    check(not chan.want() and not whisp.want(), "Stop: chat is no longer read")
    # no channel at all
    lua.execute("CHANNELS = {}")
    g.NOW = g.NOW + 60
    ok, why = YR.QuestLFGAsk(quests[0])
    check(ok is False and "no chat channel" in why, "in no channel: said so, nothing sent")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
