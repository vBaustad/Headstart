-- Where next? For a character that didn't follow our routes (levelled by hand, or on RestedXP's own):
-- which of its routes to pick up now, and at which step. From its level and the quests the game says
-- it has handed in (C_QuestLog.IsQuestFlaggedCompleted, there for every character, logged or not):
--   * each route this race and class follows, with how many of its quests are done and how many left;
--   * the one to take: its level range holds your level and it has the most quests left; with none
--     that holds it, the next one up; a route that ends at your level or below it only as a last
--     resort (what's left there is green or grey);
--   * where to start in it: the first step with a quest you haven't done, and the steps without a
--     quest right before it (the way there).
-- The Levelling tab's "Where next?" page (Editor.lua) shows it, with a button that loads the route in
-- RestedXP at that step. The routes are whatever this install has: a routes addon's, your saved runs,
-- imported ones; with none, the page says how to get one.
local _, YR = ...
local S = YR.Style

-- The route's steps this character sees (StepKeeper's when it's loaded; it needs RestedXP).
local function Steps(key)
    if YR.CharSteps then return YR.CharSteps(key) end
    local list = {}
    local _, steps = YR.SplitSteps(YR:GuideText(key) or "")
    for _, step in ipairs(steps or {}) do
        if YR.Shows(step:match("^step%s*<<%s*([^\n%-]+)")) then list[#list + 1] = step end
    end
    return list
end

local function Completed(id)
    return C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) or false
end

local function HasQuest(step)
    local s = "\n" .. step
    return s:find("\n%s*%.accept%s+%d") or s:find("\n%s*%.turnin%s+%d") or s:find("\n%s*%.complete%s+%d")
end

--- One route against what the character has done. done(questID) -> true when handed in (the game's
--- answer when left out). { key, name, lo, hi, total, done, left, first, steps } - total/done/left
--- count the quests the route hands in; first is the step to start at (nil: nothing left in it).
function YR.RouteProgress(key, done)
    done = done or Completed
    local name = YR.GuideName(key)
    local lo, hi = name:match("^(%d+)%-(%d+)")
    local r = { key = key, name = name, lo = tonumber(lo) or 0, hi = tonumber(hi) or 0, total = 0, done = 0 }
    local steps = Steps(key)
    r.steps = #steps
    local seen, firstOpen = {}, nil
    for i, step in ipairs(steps) do
        local open = false
        for kind, id in ("\n" .. step):gmatch("\n%s*%.(%a+)%s+(%d+)") do
            if kind == "accept" or kind == "turnin" or kind == "complete" then
                id = tonumber(id)
                local was = done(id)
                if not was then open = true end
                if kind == "turnin" and not seen[id] then
                    seen[id] = true
                    r.total = r.total + 1
                    if was then r.done = r.done + 1 end
                end
            end
        end
        if open and not firstOpen then firstOpen = i end
    end
    r.left = r.total - r.done
    if firstOpen and r.left > 0 then
        -- the steps without a quest right before it are the way there: start with those
        local at = firstOpen
        while at > 1 and not HasQuest(steps[at - 1]) do at = at - 1 end
        r.first = at
    end
    return r
end

-- How a route's level range sits against your level: 1 it holds it (and goes on past it), 2 it starts
-- above it, 3 it ends at it, 4 it ends below it.
local function Fit(r, level)
    if r.lo <= level and level < r.hi then return 1 end
    if r.lo > level then return 2 end
    if r.hi == level then return 3 end
    return 4
end
local FIT_NOTE = { "for your level", "next up", "ends at your level", "below your level" }

--- This character's routes, the one to take first. level and done as RouteProgress; keys: the routes
--- to look at (this race and class's when left out). Each entry has fit (1-4) and note besides
--- RouteProgress's fields; entries with nothing left come last.
function YR.WhereNext(level, done, keys)
    level = level or UnitLevel("player")
    if not keys then
        keys = {}
        local mine = YR.MyRoutes and YR.MyRoutes()
        for _, g in ipairs(YR.shipped or {}) do
            if not mine or not next(mine) or mine[g.key] then keys[#keys + 1] = g.key end
        end
    end
    local out = {}
    for _, key in ipairs(keys) do
        local r = YR.RouteProgress(key, done)
        if r.total > 0 then
            r.fit = Fit(r, level)
            r.note = r.left == 0 and "all done" or FIT_NOTE[r.fit]
            out[#out + 1] = r
        end
    end
    table.sort(out, function(a, b)
        if (a.left == 0) ~= (b.left == 0) then return b.left == 0 end
        if a.fit ~= b.fit then return a.fit < b.fit end
        if a.fit == 1 and a.left ~= b.left then return a.left > b.left end      -- the most still to do
        if a.fit == 2 and a.lo ~= b.lo then return a.lo < b.lo end              -- the nearest above
        if a.hi ~= b.hi then return a.hi > b.hi end                             -- the nearest below
        return a.name < b.name
    end)
    return out
end

local function Plain(s) return (s:gsub("%f[%d]0+(%d)", "%1")) end

--- Load a route in RestedXP at a step. Returns true, or nil and why not.
function YR.LoadRouteAt(key, step)
    if not YR.RoutesOn() then
        return nil, "Headstart's routes are off: switch them on under Route settings, then /reload."
    end
    if type(RXP) ~= "table" or type(RXP.LoadGuide) ~= "function" or type(RXP.guides) ~= "table" then
        return nil, "RestedXP isn't loaded."
    end
    local name = YR.GuideName(key)
    local group = (("\n" .. (YR:GuideText(key) or "")):match("\n#group ([^\n]+)"))
    local guide
    for _, g in pairs(RXP.guides) do
        if type(g) == "table" and type(g.name) == "string" and Plain(g.name) == name
                and (not group or not g.group or g.group == group) then
            guide = g
            break
        end
    end
    if not guide then return nil, "RestedXP doesn't have " .. name .. " (a /reload after switching routes on?)." end
    RXP:LoadGuide(guide)
    if step and step > 1 and type(RXP.SetStep) == "function" then RXP.SetStep(step) end
    return true
end

-- ---------------------------------------------------------------------------
-- The page (Levelling, Where next?)
-- ---------------------------------------------------------------------------
local ui = {}
local ROW_H, ROWS = 34, 12

local function Load(r)
    local ok, why = YR.LoadRouteAt(r.key, r.first)
    if ok then
        YR.Print(("loaded %s at step %d of %d."):format(r.name, r.first or 1, r.steps))
    else
        YR.Print(why)
    end
end

local function Counts(r)
    return ("%d of %d quests done, %d left"):format(r.done, r.total, r.left)
end

function YR.BuildWherePage(page)
    local title = S.Text(page, 17)
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetText("Where next?")
    ui.who = S.Text(page, 12, S.C.muted)
    ui.who:SetPoint("TOPLEFT", 20, -42)
    ui.who:SetPoint("RIGHT", -20, 0)
    ui.who:SetJustifyH("LEFT")

    -- the one to take
    local card = CreateFrame("Frame", nil, page)
    card:SetPoint("TOPLEFT", 20, -72)
    card:SetPoint("RIGHT", -20, 0)
    card:SetHeight(92)
    S.Fill(card, S.C.card)
    S.Border(card, S.C.lineHi)
    local tag = S.Text(card, 11, S.C.accent)
    tag:SetPoint("TOPLEFT", 16, -12)
    tag:SetText("TAKE THIS ONE")
    ui.name = S.Text(card, 17)
    ui.name:SetPoint("TOPLEFT", 16, -30)
    ui.detail = S.Text(card, 12, S.C.sub)
    ui.detail:SetPoint("TOPLEFT", 16, -58)
    ui.load = S.Button(card, "Load in RestedXP", function() if ui.best then Load(ui.best) end end, "primary", 170)
    ui.load:SetPoint("RIGHT", -16, 0)

    local head = S.Text(page, 11, S.C.muted)
    head:SetPoint("TOPLEFT", 20, -184)
    head:SetText("YOUR OTHER ROUTES")
    ui.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, page)
        row:SetPoint("TOPLEFT", 20, -204 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", -20, 0)
        row:SetHeight(ROW_H - 2)
        S.Fill(row, i % 2 == 1 and S.C.card or S.C.field)
        row.name = S.Text(row, 13)
        row.name:SetPoint("LEFT", 14, 0)
        row.name:SetWidth(330)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.counts = S.Text(row, 12, S.C.sub)
        row.counts:SetPoint("LEFT", 360, 0)
        row.note = S.Text(row, 12, S.C.muted)
        row.note:SetPoint("LEFT", 590, 0)
        row.load = S.Button(row, "Load", function() if row.r then Load(row.r) end end, nil, 80)
        row.load:SetPoint("RIGHT", -8, 0)
        row:Hide()
        ui.rows[i] = row
    end
    ui.more = S.Text(page, 11, S.C.muted)
    ui.more:SetPoint("BOTTOMLEFT", 20, 16)
end

function YR.RefreshWherePage()
    if not ui.who then return end
    local level = UnitLevel("player")
    local race, class = UnitRace("player"), UnitClass("player")
    local list = YR.WhereNext(level)
    ui.who:SetText(("Level %d %s %s. From the quests the game says this character has handed in, whether or not it followed a route."):format(
        level, race or "", class or ""))
    local best = list[1]
    if best and best.left == 0 then best = nil end
    ui.best = best
    if best then
        ui.name:SetText(best.name)
        ui.detail:SetText(("Start at step %d of %d  ·  %s  ·  %s"):format(best.first or 1, best.steps, Counts(best), best.note))
    elseif not YR.RoutesOn() then
        ui.name:SetText("Headstart's routes are off")
        ui.detail:SetText("Switch them on under Route settings, then /reload.")
    elseif #list == 0 then
        ui.name:SetText("No routes yet")
        ui.detail:SetText("Save a run as a route under This run, or paste one in under Share: then this page says where to pick it up.")
    else
        ui.name:SetText("Nothing left")
        ui.detail:SetText("Every quest in this character's routes is handed in.")
    end
    ui.load:SetShown(best ~= nil)
    local shown = 0
    for i = 1, ROWS do
        local r = list[i + (best and 1 or 0)]
        local row = ui.rows[i]
        row.r = r
        row:SetShown(r ~= nil)
        if r then
            shown = shown + 1
            row.name:SetText(r.name)
            row.counts:SetText(Counts(r))
            row.note:SetText(r.note)
            row.name:SetTextColor(unpack((r.left == 0 or r.fit == 4) and S.C.muted or S.C.text))
            row.load:SetShown(r.first ~= nil)
        end
    end
    local rest = #list - (best and 1 or 0) - shown
    ui.more:SetText(rest > 0 and ("and %d more, further from your level"):format(rest) or "")
end
