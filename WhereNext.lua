-- Next route: for a character that didn't follow our routes (levelled by hand, or on RestedXP's own):
-- which of its routes to pick up now, and at which step. From its level and the quests the game says
-- it has handed in (C_QuestLog.IsQuestFlaggedCompleted, there for every character, logged or not):
--   * each route this race and class follows, with how many of its quests are done and how many left;
--   * the one to take: its level range holds your level and it has the most quests left; with none
--     that holds it, the next one up; a route that ends at your level or below it only as a last
--     resort (what's left there is green or grey);
--   * where to start in it: the first step with a quest you haven't done, and the steps without a
--     quest right before it (the way there).
-- The Levelling tab's Next route page (where the tab opens; "Where next?" until 2026-10-21) shows it, with a button that
-- loads the route in RestedXP at that step; All routes (Editor.lua) shows every route's progress. The routes are whatever this install has: a routes addon's, your saved runs,
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
    -- "-ID": RestedXP's "skip when you don't have it" form of a hand-in or an objective
    return s:find("\n%s*%.accept%s+%d") or s:find("\n%s*%.turnin%s+%-?%d") or s:find("\n%s*%.complete%s+%-?%d")
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
        for kind, id in ("\n" .. step):gmatch("\n%s*%.(%a+)%s+%-?(%d+)") do
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

-- Each route's progress, kept: the window asks for it at every refresh (Next route, All routes), and walking a route's
-- steps is the costly part. Kept until something it rests on changes - a quest handed in, the routes there are -
-- and hand-ins are listened for only while something is kept.
local progress, progressFor, watch = {}, nil, nil
local function Forget(self)
    progress = {}
    if self and self.UnregisterEvent then self:UnregisterEvent("QUEST_TURNED_IN") end
end
--- A route's progress for this character (RouteProgress), kept.
function YR.RouteProgressKept(key)
    local stamp = #(YR.shipped or {})
    if progressFor ~= stamp then progress, progressFor = {}, stamp end
    local r = progress[key]
    if not r then
        r = YR.RouteProgress(key)
        progress[key] = r
        if not watch then
            watch = CreateFrame("Frame")
            watch:SetScript("OnEvent", Forget)
        end
        watch:RegisterEvent("QUEST_TURNED_IN")
    end
    return r
end
--- What is kept is forgotten (a route saved, or one imported).
function YR.RouteProgressForget() Forget(watch) end

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
        local r = done and YR.RouteProgress(key, done) or YR.RouteProgressKept(key)
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

--- Whether RestedXP has this route loaded now.
function YR.RouteLoaded(key)
    local g = type(RXP) == "table" and type(RXP.currentGuide) == "table" and RXP.currentGuide
    return (g and type(g.name) == "string" and Plain(g.name) == YR.GuideName(key)) or false
end

--- The route to take now (WhereNext's first, while it has quests left), or nil.
function YR.WhereNextBest()
    local best = YR.WhereNext(UnitLevel("player"))[1]
    return best and best.left > 0 and best or nil
end

--- Load a route in RestedXP at a step. Returns true, or nil and why not.
function YR.LoadRouteAt(key, step)
    if not YR.RoutesOn() then
        return nil, "Headstart's routes are off: switch them on under the Routes tab, Settings, then /reload."
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
-- The page (Levelling, Next route: where the tab opens). The route to take - its quests left, where to start, a button
-- that loads it in RestedXP - with what goes along the way beside it (your talent build, your trainer, this run), and the next few
-- routes under it. (It was "Where next?": the one to take over a list of every other route, which ran out of the
-- window - the owner, 2026-10-21: "where next's other routes extend the window".)
--   api: the window's parts (Editor.lua): head(page), panel(frame, shadow, colour), light(parent), clock(seconds),
--   width and top (the page's, and where under its heading it begins). (Its "See the steps" opened the route editor,
--   taken out 2026-10-29; the page itself shows only with a routes addon installed - Editor.lua's PAGES.)
-- ---------------------------------------------------------------------------
local ui = {}
local AFTER, AFTER_ROW, HERO_H, ALONG_W = 3, 40, 206, 236

local function Load(r)
    local ok, why = YR.LoadRouteAt(r.key, r.first)
    if ok then
        YR.Print(("loaded %s at step %d of %d."):format(r.name, r.first or 1, r.steps))
    else
        YR.Print(why)
    end
    YR:RefreshWindow()
end

-- "12-14 Loch Modan (Dwarf/Gnome)": "12-14", "Loch Modan"
local function Parts(name)
    local range, zone = name:match("^(%d+%-%d+)%s+(.+)$")
    zone = (zone or name):gsub("%s*%(Launch%)", "")
    return range, (zone:gsub("%s*%b()", ""))
end

function YR.BuildWherePage(page, api)
    ui.api = api
    ui.head = api.head(page)
    local width = api.width - 40
    local heroW = width - ALONG_W - 14
    local top = -(api.top + 12)

    -- the one to take
    local hero = CreateFrame("Frame", nil, page)
    hero:SetPoint("TOPLEFT", 16, top)
    hero:SetSize(heroW, HERO_H)
    api.panel(hero, true)
    ui.cap = S.Text(hero, 11, S.C.muted)
    ui.cap:SetPoint("TOPLEFT", 20, -18)
    ui.chip = CreateFrame("Frame", nil, hero)
    ui.chip:SetSize(44, 20)
    ui.chip:SetPoint("TOPLEFT", 20, -40)
    S.Rounded(ui.chip, "BACKGROUND", "round"):SetVertexColor(unpack(S.C.raised))
    ui.range = S.Text(ui.chip, 13, S.C.sub)
    ui.range:SetPoint("CENTER")
    ui.name = S.Text(hero, 22)
    ui.meta = S.Text(hero, 13, S.C.sub)
    ui.meta:SetPoint("TOPLEFT", 20, -72)
    ui.meta:SetPoint("RIGHT", -20, 0)
    ui.meta:SetWordWrap(true)
    ui.meta:SetJustifyV("TOP")
    ui.track = hero:CreateTexture(nil, "ARTWORK")
    ui.track:SetPoint("TOPLEFT", 20, -104)
    ui.track:SetSize(heroW - 40, 4)
    S.Set(ui.track, S.C.raised)
    ui.fill = hero:CreateTexture(nil, "OVERLAY")
    ui.fill:SetPoint("TOPLEFT", ui.track)
    ui.fill:SetHeight(4)
    S.Set(ui.fill, S.C.on)
    ui.barW = heroW - 40
    ui.progress = S.Text(hero, 12, S.C.muted)
    ui.progress:SetPoint("TOPLEFT", 20, -116)
    ui.load = S.Button(hero, "Load in RestedXP", function() if ui.best then Load(ui.best) end end, "primary", 150)
    ui.load:SetPoint("BOTTOMLEFT", 20, 18)

    -- what goes along the way: your talent build, your trainer, this run - each a click from its page
    local along = CreateFrame("Frame", nil, page)
    along:SetPoint("TOPLEFT", hero, "TOPRIGHT", 14, 0)
    along:SetSize(ALONG_W, HERO_H)
    api.panel(along, false, S.C.stripe)
    local cap = S.Text(along, 11, S.C.muted)
    cap:SetPoint("TOPLEFT", 16, -16)
    cap:SetText("ALONG THE WAY")
    local function Block(y, label, go)
        local b = CreateFrame("Button", nil, along)
        b:SetPoint("TOPLEFT", 1, y)
        b:SetPoint("RIGHT", along, "RIGHT", -1, 0)
        b:SetHeight(54)
        b.hl = S.Fill(b, S.C.hover)
        b.hl:Hide()
        b.label = S.Text(b, 12, S.C.muted)
        b.label:SetPoint("TOPLEFT", 15, -6)
        b.label:SetText(label)
        b.value = S.Text(b, 14)
        b.value:SetPoint("TOPLEFT", 15, -21)
        b.value:SetPoint("RIGHT", -15, 0)
        b.sub = S.Text(b, 12, S.C.sub)
        b.sub:SetPoint("TOPLEFT", 15, -38)
        b.sub:SetPoint("RIGHT", -15, 0)
        b:SetScript("OnEnter", function(self) self.hl:Show() end)
        b:SetScript("OnLeave", function(self) self.hl:Hide() end)
        b:SetScript("OnClick", go)
        return b
    end
    local function Rule(y)
        local rule = along:CreateTexture(nil, "BORDER")
        rule:SetPoint("TOPLEFT", 16, y)
        rule:SetPoint("TOPRIGHT", -16, y)
        S.Hair(rule, "h")
        S.Set(rule, S.C.line)
    end
    ui.talents = Block(-32, "Talents", function() YR:ToggleWindow("builds") end)
    Rule(-88)
    -- (what your class trainer has for you now: the spells you could learn and haven't, and about their price)
    ui.trainer = Block(-90, "Trainer", function() YR:ShowSettingsTab("trainer") end)
    Rule(-146)
    ui.run = Block(-148, "This run", function() YR:ToggleWindow("run") end)
    ui.runLight = api.light(ui.run)
    ui.runLight:SetPoint("TOPLEFT", 15, -19)
    ui.runLight.text:SetFont(S.FONT, 14, "")
    ui.runLight.text:SetTextColor(unpack(S.C.text))

    -- after that: the next routes, three of them (all of them are on All routes)
    local afterTop = top - HERO_H - 22
    ui.afterCap = S.Text(page, 11, S.C.muted)
    ui.afterCap:SetPoint("TOPLEFT", 18, afterTop)
    ui.afterCap:SetText("AFTER THAT")
    ui.all = S.Button(page, "All routes", function() YR:ToggleWindow("library") end, "ghost", 120)
    ui.all:SetTextColour(S.C.sub)
    ui.all:SetHeight(24)
    ui.all:SetPoint("RIGHT", page, "TOPRIGHT", -20, afterTop - 5)
    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", 16, afterTop - 20)
    list:SetSize(width, AFTER * AFTER_ROW + 2)
    api.panel(list)
    ui.list = list
    ui.rows = {}
    for i = 1, AFTER do
        local row = CreateFrame("Frame", nil, list)
        row:SetPoint("TOPLEFT", 1, -1 - (i - 1) * AFTER_ROW)
        row:SetSize(width - 2, AFTER_ROW)
        if i > 1 then
            local line = row:CreateTexture(nil, "BORDER")
            line:SetPoint("TOPLEFT")
            line:SetPoint("TOPRIGHT")
            S.Hair(line, "h")
            S.Set(line, S.C.line)
        end
        row.range = S.Text(row, 12, S.C.sub)
        row.range:SetPoint("LEFT", 14, 0)
        row.name = S.Text(row, 14)
        row.name:SetPoint("LEFT", 66, 0)
        row.name:SetPoint("RIGHT", row, "LEFT", width - 310, 0)
        row.counts = S.Text(row, 13, S.C.muted)
        row.counts:SetPoint("LEFT", width - 300, 0)
        row.note = S.Text(row, 12, S.C.muted)
        row.note:SetPoint("LEFT", width - 190, 0)
        row.load = S.Button(row, "Load", function() if row.r then Load(row.r) end end, nil, 56)
        row.load:SetHeight(26)
        row.load:SetPoint("RIGHT", -12, 0)
        row:Hide()
        ui.rows[i] = row
    end
end

function YR.RefreshWherePage()
    if not ui.head then return end
    local level = UnitLevel("player")
    local race, class = UnitRace("player"), UnitClass("player")
    local list = YR.WhereNext(level)
    local best = list[1]
    if best and best.left == 0 then best = nil end
    ui.best = best
    ui.head:Set({ icon = 132181, title = "Next route",
        desc = ("Level %d %s %s. Picked from the quests you have handed in, route or not."):format(level, race or "", class or "") })

    -- the one to take
    ui.name:ClearAllPoints()
    ui.chip:SetShown(best ~= nil)
    for _, part in ipairs({ ui.track, ui.progress, ui.load }) do part:SetShown(best ~= nil) end
    if best then
        local range, zone = Parts(best.name)
        ui.cap:SetText("TAKE THIS ONE")
        ui.range:SetText(range or "")
        ui.chip:SetWidth(math.floor(ui.range:GetStringWidth() + 16))
        ui.name:SetPoint("LEFT", ui.chip, "RIGHT", 10, 0)
        ui.name:SetText(zone)
        ui.meta:SetText(("%d quests left  ·  start at step %d of %d  ·  %s"):format(best.left, best.first or 1, best.steps, best.note))
        local part = best.total > 0 and best.done / best.total or 0
        ui.fill:SetShown(part > 0)
        ui.fill:SetWidth(math.max(1, ui.barW * part))
        ui.progress:SetText(("%d of %d quests done"):format(best.done, best.total))
        local loaded = YR.RouteLoaded(best.key)
        ui.load:SetLabel(loaded and "In RestedXP now" or "Load in RestedXP")
        ui.load:SetEnabled(not loaded)
    else
        ui.fill:Hide()
        ui.name:SetPoint("TOPLEFT", 20, -38)
        if #list == 0 then
            ui.cap:SetText("NO ROUTES YET")
            ui.name:SetText("Make or import one")
            ui.meta:SetText("Play with This run recording and Save as route, or import a route someone shared under All"
                .. " routes. Then this page says where to pick it up.")
        else
            ui.cap:SetText("ALL DONE")
            ui.name:SetText("Nothing left")
            ui.meta:SetText("Every quest in this character's routes is handed in.")
        end
    end

    -- along the way
    local build = YR.TalentFollowed and YR.TalentFollowed()
    if build then
        local nextOne = YR.TalentNextLines and YR.TalentNextLines(1)[1]
        local points = YR.UnspentTalents and YR.UnspentTalents() or 0
        ui.talents.value:SetText(build.name)
        ui.talents.sub:SetText(not nextOne and "Every talent of it taken"
            or ((type(points) == "number" and points > 0) and "A point to spend: " or "Next: ") .. nextOne)
    else
        ui.talents.value:SetText("No build followed")
        ui.talents.sub:SetText("What to take at each level")
    end
    local missing = YR.TrainerMissing and YR.TrainerMissing(level) or {}
    if #missing > 0 then
        local icons, total, priced = "", 0, 0
        for i, m in ipairs(missing) do
            local tex = i <= 3 and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(m.id)
            if tex then icons = icons .. "|T" .. tex .. ":16:16|t " end
            if m.cost then total, priced = total + m.cost, priced + 1 end
        end
        ui.trainer.value:SetText(("%s %d spell%s to learn"):format(icons, #missing, #missing == 1 and "" or "s"))
        ui.trainer.sub:SetText(priced > 0 and ("About %s%s"):format(YR.Money(total), priced < #missing and ", some not priced yet" or "")
            or "Prices are learned at your trainer")
    else
        local nextAt = YR.TrainerNextLevel and YR.TrainerNextLevel(level)
        ui.trainer.value:SetText("Nothing to learn now")
        ui.trainer.sub:SetText(nextAt and ("Something new at level %d"):format(nextAt) or "Every spell learned")
    end
    local on, stopped = YR.Option("logging"), YR.RunStopped and YR:RunStopped()
    local played = YR.SplitsPlayed and YR.SplitsPlayed()
    ui.runLight:Set(not on and "Not recording" or stopped and "Stopped" or "Recording", (on and not stopped) and S.C.green or nil)
    ui.run.value:SetText("")
    ui.run.sub:SetText(type(played) == "number" and ("%s played, level %d"):format(ui.api.clock(played), level)
        or on and "Every quest and level, as you play" or "Switch it on under This run")

    -- after that: the next ones with something left in them
    local shown = 0
    for i = 1, AFTER do
        local r = list[i + (best and 1 or 0)]
        if r and r.left == 0 then r = nil end
        local row = ui.rows[i]
        row.r = r
        row:SetShown(r ~= nil)
        if r then
            shown = shown + 1
            local range, zone = Parts(r.name)
            row.range:SetText(range or "")
            row.name:SetText(zone)
            row.counts:SetText(("%d quests"):format(r.left))
            row.note:SetText(r.note)
            row.name:SetTextColor(unpack(r.fit == 4 and S.C.muted or S.C.text))
            row.load:SetEnabled(r.first ~= nil)
        end
    end
    ui.afterCap:SetShown(shown > 0)
    ui.list:SetShown(shown > 0)
    ui.list:SetHeight(math.max(1, shown) * AFTER_ROW + 2)
    ui.all:SetLabel(("All %d routes"):format(#list))
    ui.all:SetShown(#list > 0)
    ui.shown = shown
end
--- For the tests: the page as shown - { best (its key), after (the next routes listed), load (its button's words) }.
function YR.WherePageShown()
    return { best = ui.best and ui.best.key, after = ui.shown or 0, load = ui.load and ui.load.text:GetText() }
end
