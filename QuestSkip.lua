-- Skip quest: "Skip quest" in the right-click menu of RestedXP's steps. At launch a quest can be hopeless
-- for the crowd (one spawn with a queue, its items looted bare), and skipping it in RestedXP meant ticking
-- every step of it on the way: the pick-up, the kill, the "Go to" steps, the hand-in (the owner, 2026-10-20).
-- What one click skips: the quests of the step you right-clicked, in every step of the guide whose quest
-- lines (.accept, .complete, .turnin) are all for those quests, and the "Go to" steps into one of those (a
-- "#completewith" step with a .goto and no quest of its own). A step that also has another quest's line
-- keeps going: only the skipped quest's lines there count as done.
-- How, in RestedXP's own terms (RXPGuides, read 2026-10-20):
--   the step you're on   its lines ticked as its own "Skip step" boxes tick them (ActiveStepElementPostClick):
--                        the step shows as skipped and RestedXP moves on by itself.
--   steps ahead          step.completed, the mark RestedXP puts on a step it skips itself ("part of a quest
--                        you don't have"): SetStep passes over them when it comes to them.
--   "Go to" steps        RXPCData.stepSkip[index], where RestedXP keeps the sticky (#completewith) steps it
--                        skipped. SetStep(n) clears n + 1 there, so it is set again before every SetStep.
--   the quest            RestedXP's disabledQuests: not accepted or handed in for you meanwhile.
-- RestedXP keeps none of that through a /reload but your step number (and stepSkip until another guide is
-- loaded), so the skips are Headstart's to keep and put on again: YippRouteDB.questSkips[character][guide
-- key] = { { quests = { id, ... }, name = "...", at = the step you were on }, ... }. The quest is never
-- abandoned: you may come back for it. Undo: the same menu on a skipped step, or /headstart unskip.
-- Off (the default), nothing of this is put on RestedXP; turned off again, every mark is taken back and
-- what was put on passes straight through.
local _, YR = ...

local QUEST = { accept = true, complete = true, turnin = true }
local KEEP = 30             -- skips kept per guide and character (the oldest goes)

local function Rxp()
    local r = _G.RXP
    return type(r) == "table" and type(r.SetStep) == "function" and r or nil
end

local on = false            -- the option, as the part last saw it
local marks                 -- what is put on the guide being shown (Mark)

local function GuideKey(guide)
    if type(guide) ~= "table" or guide.empty or type(guide.steps) ~= "table" then return nil end
    return guide.key or (guide.name and ((guide.group or "") .. "\\" .. guide.name))
end

--- This character's skips in a guide; made when make is set, else nil while there are none.
local function Skips(guide, make)
    local key = GuideKey(guide)
    if not key or type(YippRouteDB) ~= "table" then return nil end
    local path, at = { "questSkips", YR.CharKey(), key }, YippRouteDB
    for _, k in ipairs(path) do
        if type(at[k]) ~= "table" then
            if not make then return nil end
            at[k] = {}
        end
        at = at[k]
    end
    return at
end

local function Current(rxp)
    local n = type(rxp.GetGuideProgress) == "function" and tonumber((rxp.GetGuideProgress()))
    return n or (type(RXPCData) == "table" and tonumber(RXPCData.currentStep)) or 1
end

local function Elements(step)
    return type(step) == "table" and type(step.elements) == "table" and step.elements or {}
end

local function QuestOf(e)
    return type(e) == "table" and QUEST[e.tag] and tonumber(e.questId) or nil
end

--- The quests a step's quest lines are for, as a set; nil when it has none.
local function StepQuests(step)
    local out
    for _, e in ipairs(Elements(step)) do
        local id = QuestOf(e)
        if id then
            out = out or {}
            out[id] = true
        end
    end
    return out
end

local function HasGoto(step)
    for _, e in ipairs(Elements(step)) do
        if type(e) == "table" and e.tag == "goto" then return true end
    end
    return false
end

--- What skipping a set of quests ({ [id] = true }) does to a guide: whole[i] for a step that is only about
--- them (or a "Go to" into one), part[i] for a step with their lines beside another quest's.
local function Plan(guide, skip)
    local whole, part, steps = {}, {}, guide.steps
    for i, step in ipairs(steps) do
        local q = StepQuests(step)
        if q then
            local mine, other = false, false
            for id in pairs(q) do
                if skip[id] then mine = true else other = true end
            end
            if mine and not other then whole[i] = true elseif mine then part[i] = true end
        end
    end
    -- from the end, so a "Go to" into another "Go to" goes too
    for i = #steps, 1, -1 do
        local step, to = steps[i], nil
        local cw = type(steps[i]) == "table" and step.completewith
        if cw and not whole[i] and not StepQuests(step) and HasGoto(step) then
            if cw == "next" then to = i + 1
            elseif type(guide.labels) == "table" then to = guide.labels[cw] end
            if to and whole[to] then whole[i] = true end
        end
    end
    return whole, part
end

local function Set(list)
    local s = {}
    for _, id in ipairs(list) do s[id] = true end
    return s
end

-- A line ticked as its "Skip step" box ticks it: through the box where it has one (the step on show).
local function Tick(rxp, e, m)
    if e.skip or e.completed or e.textOnly then return end
    -- (RestedXP hands its line frames round: a frame that shows another line now isn't this one's box)
    local box = type(e.frame) == "table" and e.frame.element == e and e.frame.button
    if type(box) == "table" and box.SetChecked and type(rxp.ActiveStepElementPostClick) == "function" then
        box:SetChecked(true)
        rxp.ActiveStepElementPostClick(box)
    end
    if not e.skip then                       -- (no box, or one RestedXP wouldn't tick: an optional line)
        e.skip = true
        rxp.updateSteps = true
    end
    m.elements[e] = true
end

-- The lines a mark ticks in a step: all of them (whole), or the skipped quests' (part).
local function TickStep(rxp, step, skip, m)
    for _, e in ipairs(Elements(step)) do
        if type(e) == "table" and (not skip or (QuestOf(e) and skip[QuestOf(e)])) then Tick(rxp, e, m) end
    end
end

-- Everything put on the guide taken back off. A step ahead marked by us is RestedXP's again; a line we
-- ticked is unticked (unless RestedXP has since seen it done).
local function Unmark(rxp)
    local m = marks
    if not m then return end
    marks = nil
    for step in pairs(m.completed) do step.completed = nil end
    local stepSkip = type(RXPCData) == "table" and type(RXPCData.stepSkip) == "table" and RXPCData.stepSkip
    if stepSkip then
        for i in pairs(m.sticky) do stepSkip[i] = nil end
    end
    for e in pairs(m.elements) do
        e.skip = nil
        local box = type(e.frame) == "table" and e.frame.button
        if type(box) == "table" and box.SetChecked and not e.completed then box:SetChecked(false) end
    end
    if type(rxp.disabledQuests) == "table" then
        for id in pairs(m.disabled) do rxp.disabledQuests[id] = nil end
    end
    rxp.updateSteps = true
    rxp.updateBottomFrame = true
end

-- The sticky "Go to" steps skipped again (SetStep(n) clears n + 1 of RestedXP's list).
local function Sticky(m)
    local stepSkip = type(RXPCData) == "table" and type(RXPCData.stepSkip) == "table" and RXPCData.stepSkip
    if not stepSkip then return end
    for i in pairs(m.sticky) do stepSkip[i] = true end
end

-- The lines of the steps on show ticked again (RestedXP unticks a step's boxes as it lets it go).
local function Retick(rxp, m)
    local active = type(rxp.RXPFrame) == "table" and rxp.RXPFrame.activeSteps
    for _, step in ipairs(type(active) == "table" and active or {}) do
        local i = type(step) == "table" and step.index
        if i and m.whole[i] then TickStep(rxp, step, nil, m)
        elseif i and m.part[i] then TickStep(rxp, step, m.skip, m) end
    end
end

--- Every skip of this character in the guide on show, put on it (what was there before taken off first).
local function Mark(rxp)
    Unmark(rxp)
    local guide = rxp.currentGuide
    local m = { guide = guide, completed = {}, sticky = {}, elements = {}, disabled = {}, skip = {}, whole = {}, part = {} }
    marks = m
    local list = Skips(guide)
    if not list or #list == 0 then return end
    for _, s in ipairs(list) do
        for _, id in ipairs(type(s.quests) == "table" and s.quests or {}) do m.skip[id] = true end
    end
    m.whole, m.part = Plan(guide, m.skip)
    local stepSkip = type(RXPCData) == "table" and type(RXPCData.stepSkip) == "table" and RXPCData.stepSkip
    for i, step in ipairs(guide.steps) do
        if m.whole[i] then
            if step.sticky then
                if stepSkip and not stepSkip[i] then m.sticky[i] = true end
                if step.active then TickStep(rxp, step, nil, m) end     -- on show now: RestedXP lets it go
            elseif step.active then
                TickStep(rxp, step, nil, m)          -- the step you're on: RestedXP moves on from it
            elseif not step.completed then
                step.completed = true
                m.completed[step] = true
            end
        elseif m.part[i] then
            TickStep(rxp, step, m.skip, m)
        end
    end
    Sticky(m)
    if type(rxp.disabledQuests) == "table" then
        for id in pairs(m.skip) do
            if not rxp.disabledQuests[id] then
                rxp.disabledQuests[id] = true
                m.disabled[id] = true
            end
        end
    end
    rxp.updateSteps = true
    rxp.updateBottomFrame = true
end

local function QuestName(rxp, id, step)
    for _, e in ipairs(Elements(step)) do
        if QuestOf(e) == id and type(e.title) == "string" and e.title ~= "" then return e.title end
    end
    local ok, name = false, nil
    if type(rxp.GetQuestName) == "function" then ok, name = pcall(rxp.GetQuestName, id) end
    if not (ok and type(name) == "string" and name ~= "") and C_QuestLog and C_QuestLog.GetTitleForQuestID then
        ok, name = pcall(C_QuestLog.GetTitleForQuestID, id)
    end
    return ok and type(name) == "string" and name ~= "" and name or ("quest " .. id)
end

local function Steps(n) return n == 1 and "1 step" or (n .. " steps") end

--- Skip the quests of step n (the step you're on when n is nil). Returns whether it did.
function YR.QuestSkip(n)
    local rxp = Rxp()
    if not (on and rxp) then return false end
    local guide = rxp.currentGuide
    if not GuideKey(guide) then return false end
    local cur = Current(rxp)
    n = tonumber(n) or cur
    local step = guide.steps[n]
    local q = StepQuests(step)
    if not q then
        YR.Print("that step has no quest to skip.")
        return false
    end
    local list = Skips(guide, true)
    local ids, names = {}, {}
    for id in pairs(q) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do names[#names + 1] = QuestName(rxp, id, step) end
    local name = table.concat(names, " and ")
    -- what this skip takes, counted from the step you're on (and the "Go to" steps on show beside it)
    local whole, part = Plan(guide, Set(ids))
    local count, shared = 0, 0
    for i, s in ipairs(guide.steps) do
        if i >= cur or s.active then
            if whole[i] then count = count + 1 elseif part[i] then shared = shared + 1 end
        end
    end
    list[#list + 1] = { quests = ids, name = name, at = cur }
    while #list > KEEP do table.remove(list, 1) end
    Mark(rxp)
    if count > 0 and shared > 0 then
        YR.Print(("Skipped %s: %s, and its part of %d shared %s."):format(name, Steps(count), shared, shared == 1 and "step" or "steps"))
    elseif count > 0 then
        YR.Print(("Skipped %s: %s."):format(name, Steps(count)))
    else
        YR.Print(("Skipped %s: its part of %d shared %s."):format(name, shared, shared == 1 and "step" or "steps"))
    end
    return true
end

--- The skip that covers step n, newest first (the last skip when n is nil): its place in the list.
local function Covering(guide, list, n)
    for k = #list, 1, -1 do
        if not n then return k end
        local s = list[k]
        local whole, part = Plan(guide, Set(type(s.quests) == "table" and s.quests or {}))
        if whole[n] or part[n] then return k end
    end
end

--- Put a skip back: the one covering step n, or the last one. Back at the step you skipped from when
--- nothing but that quest's steps lies between it and the step you're on.
function YR.QuestUnskip(n)
    local rxp = Rxp()
    if not (on and rxp) then return false end
    local guide = rxp.currentGuide
    local list = Skips(guide)
    local k = list and Covering(guide, list, tonumber(n))
    if not k then
        YR.Print("no skipped quest to put back here.")
        return false
    end
    local s = table.remove(list, k)
    local whole = Plan(guide, Set(type(s.quests) == "table" and s.quests or {}))
    Mark(rxp)
    local cur, at = Current(rxp), tonumber(s.at)
    local back = at and at < cur and guide.steps[at] ~= nil
    for i = at or cur, cur - 1 do
        local step = guide.steps[i]
        if not (whole[i] or (type(step) == "table" and step.sticky)) then back = false end
    end
    if back then
        -- RestedXP marked them done when it passed them: theirs to look at again
        for i = at, cur - 1 do
            if whole[i] and type(guide.steps[i]) == "table" then guide.steps[i].completed = nil end
        end
        rxp.SetStep(at)
        YR.Print(("Put back %s: back at step %d."):format(s.name or "the quest", at))
    else
        YR.Print(("Put back %s."):format(s.name or "the quest"))
    end
    return true
end

-- The menu: "Skip quest: X" on a step with a quest, "Undo skip: X" on a step a skip covers, nothing on
-- the others. RestedXP's two windows open the one menu (RXPFrame.bottomMenu) with the step in its first
-- line's arg1. Ours goes in before its last line (Close), so the lines RestedXP finds by number stay put.
local entry = { notCheckable = 1, text = "Skip quest" }
local function Menu(rxp) return type(rxp.RXPFrame) == "table" and type(rxp.RXPFrame.bottomMenu) == "table" and rxp.RXPFrame.bottomMenu or nil end

local function TakeEntry(menu)
    for i = #menu, 1, -1 do
        if menu[i] == entry then table.remove(menu, i) end
    end
end

local function Ready(rxp, menu)
    TakeEntry(menu)
    local n = type(menu[1]) == "table" and tonumber(menu[1].arg1)
    local guide = rxp.currentGuide
    local step = n and GuideKey(guide) and guide.steps[n]
    if not step then return end
    local list = Skips(guide)
    local k = list and Covering(guide, list, n)
    if k then
        entry.text = "Undo skip: " .. (list[k].name or "quest")
        entry.func = function() YR.QuestUnskip(n) end
    elseif StepQuests(step) then
        local names = {}
        local q = StepQuests(step)
        local ids = {}
        for id in pairs(q) do ids[#ids + 1] = id end
        table.sort(ids)
        for _, id in ipairs(ids) do names[#names + 1] = QuestName(rxp, id, step) end
        entry.text = "Skip quest: " .. table.concat(names, " and ")
        entry.func = function() YR.QuestSkip(n) end
    else
        return
    end
    table.insert(menu, math.max(1, #menu), entry)
end

-- Put on RestedXP the first time the option is on, and from then on passing straight through while it
-- is off: SetStep (the "Go to" skips set again before and after it, the lines on show ticked again after)
-- and ShowMenu.
local wrapped
local function Wrap(rxp)
    if wrapped then return end
    wrapped = true
    local set = rxp.SetStep
    local function After(...)
        if on and marks and marks.guide == rxp.currentGuide then
            Sticky(marks)                       -- (SetStep(n) has just cleared n + 1)
            Retick(rxp, marks)
        end
        return ...
    end
    rxp.SetStep = function(...)
        if not on then return set(...) end
        if not marks or marks.guide ~= rxp.currentGuide then Mark(rxp) else Sticky(marks) end
        return After(set(...))
    end
    local show = rxp.ShowMenu
    if type(show) == "function" then
        rxp.ShowMenu = function(self, menu, ...)
            if on and menu ~= nil and menu == Menu(rxp) then Ready(rxp, menu) end
            return show(self, menu, ...)
        end
    end
end

local function Wanted() return YR.Option("questSkip") and Rxp() ~= nil end

YR.Part(Wanted, {}, nil, {
    start = function()
        local rxp = Rxp()
        Wrap(rxp)
        on = true
        if GuideKey(rxp.currentGuide) then Mark(rxp) end
    end,
    stop = function()
        on = false
        local rxp = Rxp()
        if not rxp then return end
        Unmark(rxp)
        local menu = Menu(rxp)
        if menu then TakeEntry(menu) end
    end,
})
