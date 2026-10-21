"""Smoke test of Quest item buttons (QuestItems.lua), in Lua 5.1 (lupa).

    python tools/smoke_questitems.py      (exit code 1 on any failure; tools/smoke.py runs it too)

The items a quest gave you that you use, as secure buttons: quest items and rewards with a use, not what is on
your bars, not what you took off; laid out out of a fight only. Uses smoke.py's fake game.
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
    YR = lua.table()
    load = lua.eval("function(c, n) return assert(loadstring(c, n)) end")
    for f in files(ROOT, "Headstart.toc"):
        load(open(f, encoding="utf-8").read(), os.path.basename(f))("Headstart", YR)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    # the bags: a Sprouted Frond (a quest's reward, with a use), linen cloth (no use), a quest item with a use
    lua.execute("""
        local F = getmetatable(CreateFrame("Frame"))
        F.SetAttribute = function(self, k, v) local a = rawget(self, "attr") or {} rawset(self, "attr", a) a[k] = v end
        F.GetAttribute = function(self, k) local a = rawget(self, "attr") return a and a[k] end
        function QI_IDS() local t = {} for i = 1, 12 do local b = _G["HeadstartQuestItem" .. i]
            if b and not rawget(b, "hidden") and rawget(b, "id") then t[#t + 1] = rawget(b, "id") end end return t end
        function QI_HIDDEN(f) return rawget(f, "hidden") == true end
        LATER = {}
        C_Timer.After = function(_, fn) LATER[#LATER + 1] = fn end
        function Later() local l = LATER LATER = {} for _, fn in ipairs(l) do fn() end end
        QI_BAG = { 5205, 2589, 5185, 117, 6328 }  -- (and Tough Jerky: food, and a recipe: rewards too)
        C_Container = C_Container or {}
        C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 5 or 0 end
        C_Container.GetContainerItemID = function(bag, slot) return bag == 0 and QI_BAG[slot] or nil end
        C_Container.GetContainerItemQuestInfo = function(bag, slot) return { isQuestItem = bag == 0 and QI_BAG[slot] == 5185 } end
        C_Container.GetItemCooldown = function() return 0, 0, 1 end
        C_Item = C_Item or {}
        KEPT_INSTANT = C_Item.GetItemInfoInstant
        local SUB = { [5205] = 8, [117] = 5 }      -- Sprouted Frond: Other; Tough Jerky: Food & Drink
        local CLASS = { [5185] = 12, [6328] = 9 }  -- the quest item; the recipe (Recipe: Kaldorei Spider Kabob)
        C_Item.GetItemInfoInstant = function(id) return id, "", "", "", 0, CLASS[id] or 0, SUB[id] or 0 end
        C_Item.GetItemSpell = function(id) if id == 5205 or id == 5185 or id == 117 or id == 6328 then return "Use", 1 end end
        C_Item.GetItemCount = function(id) return id == 5205 and 3 or 1 end
        C_Item.GetItemIconByID = function() return 1 end
        ACTIONS = {}
        function GetActionInfo(slot) if ACTIONS[slot] then return "item", ACTIONS[slot] end end
        function GetNumQuestRewards() return 3 end
        function GetNumQuestChoices() return 0 end
        function GetQuestItemLink(kind, i)
            if i == 2 then return "|cffffffff|Hitem:117::::|h[Tough Jerky]|h|r" end
            if i == 3 then return "|cffffffff|Hitem:6328::::|h[Recipe: Kaldorei Spider Kabob]|h|r" end
            return "|cffffffff|Hitem:5205::::|h[Sprouted Frond]|h|r"
        end
        FIGHT = false
        function InCombatLockdown() return FIGHT end
        YippRouteDB = nil YippSetupCharDB = nil""")
    g.Fire("ADDON_LOADED", "Headstart")
    g.Fire("PLAYER_LOGIN")
    g.Later()
    db = g.YippRouteDB

    def ids():
        t = g.QI_IDS()
        return [t[i] for i in range(1, len(t) + 1)]

    check(g.HeadstartQuestItemBar is None and "questItems" in YR.STARTS_OFF, "off on a new install: no buttons made")
    db.questItems = True
    YR.ApplyParts()
    wanted = YR.QuestItemsWanted()
    check(len(wanted) == 0 and g.HeadstartQuestItemBar is None,
          "on, no reward known yet: nothing - quest items only with their switch (the owner, 2026-10-20)")
    db.questItemsQuest = True
    YR.QuestItemsLayout()
    check(g.HeadstartQuestItemBar is not None and ids() == [5185], f"Quest items too on: the quest item with a use gets a button ({ids()})")
    b = g.HeadstartQuestItem1
    check(b.GetAttribute(b, "type1") == "item" and b.GetAttribute(b, "item1") == "item:5185",
          "the button uses the item, as from your bags (a secure item button)")
    g.Fire("QUEST_COMPLETE")
    YR.QuestItemsLayout()
    check(ids() == [5205, 5185], f"a quest gave the Sprouted Frond, Tough Jerky and a recipe: the Frond gets one, in bag order - the food and the recipe don't ({ids()})")
    check(g.HeadstartQuestItem1.count.text == "3", "how many you carry, on the button")
    lua.execute("ACTIONS[7] = 5205 Fire('ACTIONBAR_SLOT_CHANGED', 7) Later()")
    YR.QuestItemsLayout()
    check(ids() == [5185], f"the Frond put on your action bars: no button of ours ({ids()})")
    # (both were switches until 2026-10-21: one still saved off changes nothing)
    db.questItemsBars, db.questItemsRewards = False, False
    YR.QuestItemsLayout()
    check(ids() == [5185], "an old 'leave out what's on your bars' saved off: still left out")
    lua.execute("ACTIONS = {} Fire('ACTIONBAR_SLOT_CHANGED', 7) Later()")
    YR.QuestItemsLayout()
    check(ids() == [5205, 5185], "an old 'quest rewards' saved off: the reward still has its button")
    db.questItemsBars, db.questItemsRewards = None, None
    db.questItemsQuest = False
    YR.QuestItemsLayout()
    check(ids() == [5205], "Quest items off: only the reward")
    db.questItemsQuest = True
    # taken off (Shift+right-click), and back
    g.YippSetupCharDB.questUseHidden[5185] = True
    YR.QuestItemsLayout()
    check(ids() == [5205] and YR.QuestItemsHiddenCount() == 1, "one taken off: no button for it on this character")
    YR.QuestItemsShowHidden()
    check(ids() == [5205, 5185], "Show them again: back")
    # in a fight the secure buttons don't change; they do as it ends
    lua.execute("FIGHT = true QI_BAG[1] = nil")
    YR.QuestItemsLayout()
    check(ids() == [5205, 5185], "the Frond used up in a fight: the buttons wait")
    lua.execute("FIGHT = false")
    g.Fire("PLAYER_REGEN_ENABLED")
    check(ids() == [5185], f"the fight over: laid out again ({ids()})")
    # a bag change is looked at once, a moment after the bags settle
    lua.execute("QI_BAG[1] = 5205 LATER = {}")
    g.Fire("BAG_UPDATE_DELAYED")
    g.Fire("BAG_UPDATE_DELAYED")
    check(len(g.LATER) == 1, "two bag changes in a row: looked at once")
    g.Later()
    check(ids() == [5205, 5185], "and then the buttons are as the bags are")
    # what is on the bars kept slot by slot: a slot that changed is read alone, and one that holds the same item as
    # before lays nothing out (the performance audit, 2026-10-20)
    lua.execute("""READS = 0 KEPT_GAI = GetActionInfo
        function GetActionInfo(slot) READS = READS + 1 return KEPT_GAI(slot) end
        LATER = {} Fire('ACTIONBAR_SLOT_CHANGED', 12)""")
    check(g.READS == 1 and len(g.LATER) == 0, f"an action bar slot changed, still no item in it: that slot read alone, nothing laid out ({g.READS})")
    lua.execute("ACTIONS[12] = 5185 Fire('ACTIONBAR_SLOT_CHANGED', 12) Later() GetActionInfo = KEPT_GAI")
    check(ids() == [5205], f"the quest item put on the bar there: its button goes ({ids()})")
    lua.execute("ACTIONS[12] = nil Fire('ACTIONBAR_SLOT_CHANGED', 12) Later()")
    check(ids() == [5205, 5185], f"and taken off: back ({ids()})")
    # off: gone, and nothing listened for
    db.questItems = False
    YR.ApplyParts()
    check(g.QI_HIDDEN(g.HeadstartQuestItemBar), "turned off: the buttons go")
    lua.execute("C_Item.GetItemInfoInstant = KEPT_INSTANT")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
