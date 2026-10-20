"""Smoke test of QuestSkip.lua (Skip quest in RestedXP's step menu) against a fake RestedXP, in Lua 5.1
(lupa).

    python tools/smoke_questskip.py      (exit code 1 on any failure)

The fake's SetStep and step completion follow RestedXP's own (GuideWindow.lua, read 2026-10-20) where it
matters here: SetStep(n) clears RXPCData.stepSkip[n + 1], passes over a sticky (#completewith) step and a
completed one, puts a sticky step behind you on show unless stepSkip has it, and lets go of the steps on
show by clearing their completed mark and their lines' ticks (its ClearFrameData). A step whose lines are
all done or ticked completes, and RestedXP moves on (its loadNextStep).
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r'''
PRINTS = {}
YippRouteDB = {}
RXPCData = { currentStep = 1, stepSkip = {} }
OPTION = false
PARTS = {}
C_QuestLog = { GetTitleForQuestID = function(id) return NAMES[id] end }
NAMES = { [100] = "Darkness in the Glade", [200] = "Boar Hunt", [300] = "Lost Letter" }

RXP = { disabledQuests = {}, RXPFrame = { activeSteps = {} } }
local active = RXP.RXPFrame.activeSteps
RXP.RXPFrame.bottomMenu = {
    { text = "Go to step 1", arg1 = 1 }, { text = "Select another guide" }, { text = "Reload Guide" },
    { text = "Options..." }, { text = "Give Feedback for step" }, { text = "Close" },
}
function RXP.GetGuideProgress() return RXPCData.currentStep end
function RXP:ShowMenu(menu) LASTMENU = menu end

-- a box for each line on show (RestedXP's element frames): RXP.ActiveStepElementPostClick is its click
local function Box(e)
    local frame = { element = e }
    frame.button = { checked = false, GetParent = function() return frame end }
    function frame.button:SetChecked(on) self.checked = on end
    function frame.button:GetChecked() return self.checked end
    e.frame = frame
end
function RXP.ActiveStepElementPostClick(button)
    local element = button:GetParent().element
    if element and not element.optional then element.skip = button:GetChecked() end
    RXP.updateSteps = true
    CLICKS = (CLICKS or 0) + 1
end

function RXP.SetStep(n, n2)
    if type(n) == "table" then n = n2 end
    local g = RXP.currentGuide
    if n > #g.steps then return end
    RXPCData.currentStep = n
    RXPCData.stepSkip[n + 1] = nil
    if g.steps[n].sticky and n < #g.steps then return RXP.SetStep(n + 1) end
    for _, s in ipairs(active) do
        s.active = nil
        if n < #g.steps then s.completed = nil end
        for _, e in ipairs(s.elements) do e.skip = nil if e.frame then e.frame.button.checked = false end end
    end
    for i = #active, 1, -1 do active[i] = nil end
    for i = 1, n - 1 do
        local s = g.steps[i]
        if s.sticky and not RXPCData.stepSkip[i] then active[#active + 1] = s s.active = true end
    end
    local s = g.steps[n]
    if s.completed and n < #g.steps then return RXP.SetStep(n + 1) end
    active[#active + 1] = s
    s.active = true
    for _, a in ipairs(active) do for _, e in ipairs(a.elements) do Box(e) end end
end

-- RestedXP's update: a step whose lines are done completes; the step you're on done, it moves on
function UPDATE()
    for _ = 1, 20 do
        local moved = false
        local g = RXP.currentGuide
        for _, s in ipairs(active) do
            local done = true
            for _, e in ipairs(s.elements) do
                if not (e.completed or e.skip or e.textOnly) then done = false end
            end
            local cw = s.completewith == "next" and s.index + 1
            if s.sticky and (done or (cw and RXPCData.currentStep > cw)) then
                RXPCData.stepSkip[s.index] = true
                RXP.SetStep(RXPCData.currentStep) moved = true break
            elseif done and not s.sticky and s.index >= RXPCData.currentStep then
                s.completed = true
                RXP.SetStep(RXPCData.currentStep + 1) moved = true break
            end
        end
        if not moved then return end
    end
end

-- A guide as RestedXP makes it when it loads one: fresh tables every time (a /reload, a load again)
local function L(tag, id, extra) local e = { tag = tag, questId = id } for k, v in pairs(extra or {}) do e[k] = v end return e end
function GUIDE()
    local steps = {
        { elements = { L("accept", 100), L("goto") } },                 -- 1  take Darkness in the Glade
        { elements = { L("accept", 200) } },                            -- 2  take Boar Hunt
        { completewith = "next", elements = { L("goto") } },            -- 3  Go to the glade
        { elements = { L("complete", 100), L("goto") } },               -- 4  kill the satyrs
        { elements = { L("complete", 200), L("complete", 100) } },      -- 5  boars, and more satyrs: shared
        { completewith = "next", elements = { L("goto") } },            -- 6  Go to town
        { elements = { L("turnin", 100) } },                            -- 7  hand in Darkness in the Glade
        { elements = { L("turnin", 200) } },                            -- 8  hand in Boar Hunt
        { elements = { L("goto") } },                                   -- 9  walk on (no quest)
        { elements = { L("accept", 300) } },                            -- 10 the next quest
    }
    for i, s in ipairs(steps) do
        s.index = i
        if s.completewith then s.sticky = true end
        for _, e in ipairs(s.elements) do e.step = s end
    end
    return { key = "Test\\10-12 Glade", name = "10-12 Glade", group = "Test", steps = steps, labels = {} }
end
function LOAD()
    RXP.currentGuide = GUIDE()
    for i = #active, 1, -1 do active[i] = nil end
    RXP.SetStep(RXPCData.currentStep)
end
function MENU(n)
    local m = RXP.RXPFrame.bottomMenu
    m[1].arg1 = n
    RXP:ShowMenu(m)
    for _, item in ipairs(m) do
        if item.text and (item.text:find("^Skip quest") or item.text:find("^Undo skip")) then return item end
    end
end
'''


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    lua.execute(r'''
function MAKE(YR)
    YR.Print = function(m) table.insert(PRINTS, m) end
    YR.CharKey = function() return "Tester-Realm" end
    YR.Option = function(key) return key == "questSkip" and OPTION end
    YR.Part = function(want, events, handler, opt) PARTS[#PARTS + 1] = { want = want, opt = opt, on = false } end
end
-- Core.lua's YR.ApplyParts, for the one part
function APPLY()
    for _, p in ipairs(PARTS) do
        local w = p.want() and true or false
        if w ~= p.on then p.on = w if w then p.opt.start(p) else p.opt.stop(p) end end
    end
end
''')
    YR = lua.table()
    lua.globals().MAKE(YR)
    g = lua.globals()
    lua.execute("ORIGINAL_SET = RXP.SetStep")
    g.LOAD()
    chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, "QuestSkip.lua"), encoding="utf-8").read(), "QuestSkip.lua")
    chunk("Headstart", YR)
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def steps():
        return g.RXP.currentGuide.steps

    def last():
        return str(g.PRINTS[len(g.PRINTS)]) if len(g.PRINTS) else ""

    # off (the default): nothing put on RestedXP, nothing in its menu
    g.APPLY()
    check(lua.eval("RXP.SetStep == ORIGINAL_SET"), "off: RestedXP's SetStep is its own")
    check(g.MENU(1) is None and len(g.RXP.RXPFrame.bottomMenu) == 6, "off: nothing of ours in the step menu")

    # on: the menu offers the quest of the clicked step; a step with no quest gets nothing
    g.OPTION = True
    g.APPLY()
    item = g.MENU(1)
    check(item is not None and item.text == "Skip quest: Darkness in the Glade", f"on: the menu says {item and item.text}")
    menu = g.RXP.RXPFrame.bottomMenu
    check(len(menu) == 7 and menu[5].text == "Give Feedback for step" and menu[7].text == "Close",
          "our line goes in before Close: the lines RestedXP finds by number stay put")
    check(g.MENU(9) is None and len(menu) == 6, "a step with no quest: no line")

    # skip: the pick-up (the step you're on), the kill, both "Go to" steps and the hand-in; the shared step stays
    g.MENU(1).func()
    check(last() == "Skipped Darkness in the Glade: 5 steps, and its part of 1 shared step.", f"one chat line: {last()}")
    s = steps()
    check(all(e.skip for e in s[1].elements.values()) and g.CLICKS == 2,
          f"the step you're on: every line ticked through its own box ({g.CLICKS} clicks)")
    check(s[4].completed and s[7].completed and g.RXPCData.stepSkip[3] and g.RXPCData.stepSkip[6],
          "ahead: kill and hand-in marked completed, the two Go to steps in RestedXP's stepSkip")
    check(not s[2].completed and not s[8].completed and not s[10].completed, "Boar Hunt's own steps and the next quest: untouched")
    check(not s[5].completed and s[5].elements[2].skip and not s[5].elements[1].skip,
          "the shared step stays; only Darkness in the Glade's line in it counts as done")
    check(g.RXP.disabledQuests[100] and not g.RXP.disabledQuests[200], "RestedXP won't take or hand in the skipped quest for you")
    check(not any("bandon" in str(p) for p in g.PRINTS.values()), "the quest is not abandoned")

    # RestedXP moves on by itself: to Boar Hunt's pick-up, then past every skipped step
    g.UPDATE()
    check(g.RXPCData.currentStep == 2, f"RestedXP moves on to the next step: {g.RXPCData.currentStep}")
    s[2].elements[1].completed = True                   # Boar Hunt taken
    g.UPDATE()
    check(g.RXPCData.currentStep == 5, f"past the Go to and the kill, onto the shared step: {g.RXPCData.currentStep}")
    shown = [st.index for st in g.RXP.RXPFrame.activeSteps.values()]
    check(shown == [5], f"the skipped Go to step is not on show beside it: {shown}")
    check(s[5].elements[2].skip, "the shared step's skipped line ticked again after RestedXP let its boxes go")
    s[5].elements[1].completed = True                   # the boars killed: the shared step is done
    g.UPDATE()
    check(g.RXPCData.currentStep == 8, f"past Go to town and the hand-in, onto Boar Hunt's hand-in: {g.RXPCData.currentStep}")

    # a /reload: RestedXP makes the guide again from nothing, at the saved step; the skips come back
    g.RXPCData.currentStep = 5
    g.RXPCData.stepSkip = lua.table()
    g.LOAD()
    s = steps()
    check(s[4].completed and s[7].completed and g.RXPCData.stepSkip[3] and g.RXPCData.stepSkip[6]
          and s[5].elements[2].skip and g.YippRouteDB.questSkips["Tester-Realm"]["Test\\10-12 Glade"][1].at == 1,
          "after a /reload: the same steps skipped, from what Headstart saved")

    # undo on a skipped step: the menu says so, and everything is put back where nothing else happened since
    item = g.MENU(4)
    check(item is not None and item.text == "Undo skip: Darkness in the Glade", f"a skipped step's menu: {item and item.text}")
    item = g.MENU(3)
    check(item is not None and item.text.startswith("Undo skip"), "a skipped Go to step's menu: undo too")
    g.MENU(4).func()
    s = steps()
    check(not s[4].completed and not s[7].completed and not g.RXPCData.stepSkip[3] and not g.RXPCData.stepSkip[6]
          and not s[5].elements[2].skip and not g.RXP.disabledQuests[100], "undo: every mark taken back")
    check(g.RXPCData.currentStep == 5 and last() == "Put back Darkness in the Glade.",
          f"undo with Boar Hunt's pick-up between (a step that isn't the quest's): you stay put: {g.RXPCData.currentStep}, {last()}")
    check(len(g.YippRouteDB.questSkips["Tester-Realm"]["Test\\10-12 Glade"]) == 0, "and it is gone from the saved skips")

    # skip and undo straight away: back at the step you skipped from (RestedXP had marked it done)
    g.RXPCData.currentStep = 1
    g.LOAD()
    g.MENU(1).func()
    g.UPDATE()
    check(g.RXPCData.currentStep == 2, "skipped again: on at step 2")
    lua.execute('SlashUnskip = function(YR) return YR.QuestUnskip() end')
    g.SlashUnskip(YR)
    check(g.RXPCData.currentStep == 1 and last() == "Put back Darkness in the Glade: back at step 1."
          and not steps()[1].completed, f"/headstart unskip: back at the pick-up: {g.RXPCData.currentStep}, {last()}")

    # the step you're on (no number): what /headstart skip does
    YR.QuestSkip()
    check(last().startswith("Skipped Darkness in the Glade"), f"/headstart skip: the step you're on: {last()}")
    YR.QuestUnskip()

    # a step that only shares the quest: skipped from there, the quest's own steps go, the step itself stays
    g.RXPCData.currentStep = 5
    g.LOAD()
    g.MENU(5).func()
    check("Darkness in the Glade and Boar Hunt" in last(), f"a step with two quests skips both: {last()}")
    YR.QuestUnskip()

    # turned off: every mark taken back, our menu line gone, and SetStep passes straight through
    g.RXPCData.currentStep = 1
    g.LOAD()
    g.MENU(1).func()
    g.OPTION = False
    g.APPLY()
    s = steps()
    check(not s[4].completed and not g.RXPCData.stepSkip[3] and not g.RXP.disabledQuests[100], "off again: every mark taken back")
    check(g.MENU(1) is None and len(g.RXP.RXPFrame.bottomMenu) == 6, "off again: our line gone from the menu")
    g.RXPCData.currentStep = 2
    g.LOAD()
    check(not steps()[4].completed, "off: a guide loaded again has no skips put on it (they wait, saved, for on)")
    check(len(g.YippRouteDB.questSkips["Tester-Realm"]["Test\\10-12 Glade"]) == 1, "the skip itself is kept")

    print(f"\n{bad} failure(s)" if bad else "\nall QuestSkip checks pass")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
