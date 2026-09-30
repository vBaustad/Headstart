-- The routes Headstart ships, and each player's own edits of them.
--
-- A guide file doesn't register itself with RestedXP any more; it hands its text to YR:ShipGuide.
-- At login, RegisterGuides gives RestedXP either the player's edited version (saved by the route
-- editor in YippRouteDB.custom) or, if they never edited it, the shipped one. RestedXP reads guides
-- added after it has loaded straight away (RXPGuides.RegisterGuide), so nothing is written to disk:
-- an edit reaches RestedXP on the next /reload.
--
-- A guide is plain RestedXP text: a header, then steps that each start with a line "step". The
-- editor works on that split: the header is kept as it is, the steps can be moved, removed or added.
local _, YR = ...

YR.shipped = {}          -- { { key, text } } in load order
local byKey = {}

function YR:ShipGuide(key, text)
    local g = { key = key, text = text }
    YR.shipped[#YR.shipped + 1] = g
    byKey[key] = g
end

local function Custom()
    YippRouteDB.custom = YippRouteDB.custom or {}
    return YippRouteDB.custom
end

-- The text RestedXP gets for this guide: the player's version if they saved one.
function YR:GuideText(key)
    local c = Custom()[key]
    return c and c.text or (byKey[key] and byKey[key].text)
end

function YR:IsCustom(key)
    return Custom()[key] ~= nil
end

-- Routes edited or imported before the rename still name the old group: move them to the new one.
local OLD_GROUP = "YippRoute Launch %(A%)"
local function Renamed(text)
    return (text:gsub(OLD_GROUP, "Headstart Launch (A)"))
end

-- A new Headstart version never overwrites an edited route: RestedXP keeps getting the player's
-- version. Each edited route remembers the shipped text it started from (base), so when an update
-- ships a different route, the player is told and can merge: our new route with their edits on top.
local function Sum(s)
    local h = #s
    for i = 1, #s, 7 do h = (h * 31 + s:byte(i)) % 2147483647 end
    return h
end

function YR:HasUpdate(key)
    local c, g = Custom()[key], byKey[key]
    return c and g and c.base ~= nil and c.base ~= g.text or false
end

local function TellUpdates()
    for _, g in ipairs(YR.shipped) do
        local c = Custom()[g.key]
        if YR:HasUpdate(g.key) and c.told ~= Sum(g.text) then
            c.told = Sum(g.text)
            YR.Print(("this version ships a new %s route. You're still on your own edited one: open /headstart,"
                .. " Routes, to take the update with your edits kept."):format(YR.GuideName(g.key)))
        end
    end
end

function YR:RegisterGuides()
    for key, c in pairs(Custom()) do
        c.text = Renamed(c.text)
        -- edited before routes remembered their base: take today's shipped route as it
        if c.base == nil and byKey[key] then c.base = byKey[key].text end
    end
    TellUpdates()
    if UnitFactionGroup("player") == "Horde" or not (RXPGuides and RXPGuides.RegisterGuide) then return end
    YR:ScanGroupRoutes()
    for _, g in ipairs(YR.shipped) do
        for _, text in ipairs(YR.RoleVersions(YR:GuideText(g.key), "solo")) do
            local ok, err = pcall(RXPGuides.RegisterGuide, text)
            if not ok then YR.Print(("guide %s did not load: %s"):format(g.key, tostring(err))) end
        end
    end
    if YR.Role then YR:RegisterRole(YR:Role()) end
end

-- Group routes. Two marks in a step:
--   "#share N"  the Nth pick-up of quests the party can share, off the others' path (marked by
--               tools/share_split.py): one member takes it and shares it, the others skip the walk.
--               Pick-ups go round the group: a duo's A takes 1, 3, 5..., B 2, 4, 6...; a trio's A, B, C
--               take turns.
--   "#role X"   (or "#role A,B", or "#role solo") only that role does the step, or only a player alone.
-- Steps without a mark are everyone's. A route with #share marks gets Duo A/B and Trio A/B/C versions;
-- "#roles A,B" or "#roles A,B,C" in the header limits it to that group size. RestedXP gets one route
-- per role, "... (Duo A)" and so on, plus the solo route under the route's own name. Their #next points
-- to the same role's version of the next route where there is one.
local LETTERS = { "A", "B", "C" }

local function HasRole(step, role, size)
    local n = tonumber(step:match("\n%s*#share%s+(%d+)"))
    if n and size then return LETTERS[(n - 1) % size + 1] == role end
    local roles = step:match("\n%s*#role%s+([%w,]+)")
    if not roles then return true end
    for r in roles:gmatch("[^,]+") do if r == role then return true end end
    return false
end

-- The group sizes a route has versions for: { 2, 3 }, { 2 }, { 3 } or none.
local function Sizes(text)
    local roles = text:match("\n#roles%s+([%w,]+)")
    if roles then return { select(2, roles:gsub("[^,]+", "")) } end
    -- split pick-ups, group-only steps, or dungeon steps: a group plays it differently
    if text:find("\n%s*#share%s+%d") or text:find("\n%s*#role%s") or text:find("\n%s*%.dungeon%s") then
        return { 2, 3 }
    end
    return {}
end

local function Variant(text, role, suffix, size)
    local header, steps = YR.SplitSteps(text)
    local kept = {}
    for _, step in ipairs(steps) do
        -- a group runs the dungeons: RestedXP's dungeon steps (".dungeon DM", shown only when that
        -- dungeon is ticked in its settings) always show, and their no-dungeon versions (".dungeon !DM")
        -- go. Alone, RestedXP's own dungeon setting decides as usual.
        local skipIfGroup = size and step:find("\n%s*%.dungeon%s+!%a")
        if HasRole(step, role, size) and not skipIfGroup then
            step = step:gsub("\n%s*#role%s+[%w,]+", ""):gsub("\n%s*#share%s+%d+", "")
            if size then step = step:gsub("\n%s*%.dungeon%s+%a+[^\n]*", "") end
            kept[#kept + 1] = step
        end
    end
    header = ("\n" .. header):gsub("\n#roles[^\n]*", "")   -- a leading newline, so line 1 matches like the rest
    if suffix then
        header = header:gsub("\n#name ([^\n]+)", function(n) return "\n#name " .. n .. " (" .. suffix .. ")" end, 1)
        -- the next route, as this role, when it is one of ours with the same roles
        header = header:gsub("\n#next ([^\n]+)", function(list)
            local out = {}
            for entry in list:gmatch("[^;]+") do
                local group, name = entry:match("^(.-)\\(.+)$")
                local ours = group == "Headstart Launch (A)" and YR.GroupRouteNames and YR.GroupRouteNames[name]
                out[#out + 1] = (ours and ours[suffix]) and (entry .. " (" .. suffix .. ")") or entry
            end
            return "\n#next " .. table.concat(out, ";")
        end, 1)
    end
    return YR.JoinSteps(header:sub(2), kept)
end

-- The texts to register for one route: solo first, then one per role.
-- only: one role ("Duo A"), "solo" for the solo route alone, or nil for every version.
function YR.RoleVersions(text, only)
    text = text or ""
    local out = {}
    if only == nil or only == "solo" then out[1] = Variant(text, "solo") end
    for _, size in ipairs(Sizes("\n" .. text)) do
        local label = size == 2 and "Duo" or "Trio"
        for i = 1, size do
            local role = label .. " " .. LETTERS[i]
            if only == nil or only == role then out[#out + 1] = Variant(text, LETTERS[i], role, size) end
        end
    end
    return out
end

-- RestedXP parses every route it is given, and the group versions of the long routes are big: it gets
-- the solo routes and this character's role's versions; picking another role registers that role's.
local registered = {}
function YR:RegisterRole(role)
    if not (RXPGuides and RXPGuides.RegisterGuide) or not role or role == "solo" or registered[role] then return end
    registered[role] = true
    for _, g in ipairs(YR.shipped) do
        for _, text in ipairs(YR.RoleVersions(YR:GuideText(g.key), role)) do
            pcall(RXPGuides.RegisterGuide, text)
        end
    end
end

-- Which of our routes have group versions, by name: { [name] = { ["Duo A"] = true, ... } }, so a
-- role's route can hand over to the same role's next route.
function YR:ScanGroupRoutes()
    YR.GroupRouteNames = {}
    for _, g in ipairs(YR.shipped) do
        local text = "\n" .. (YR:GuideText(g.key) or "")
        local name = text:match("\n#name ([^\n]+)")
        local sizes = Sizes(text)
        if name and #sizes > 0 then
            local set = {}
            for _, size in ipairs(sizes) do
                for i = 1, size do set[(size == 2 and "Duo " or "Trio ") .. LETTERS[i]] = true end
            end
            YR.GroupRouteNames[name] = set
        end
    end
end

-- The routes a character of this race can follow: its starting route and every route its #next
-- lines lead to (ours only), as a set of keys. A Dwarf never plays Human Elwynn's quests.
local START = { Human = "northshire", NightElf = "shadowglen", Dwarf = "coldridge", Gnome = "coldridge" }
function YR:RoutesFor(race)
    local byName = {}
    for _, g in ipairs(YR.shipped) do
        local name = (("\n" .. (YR:GuideText(g.key) or "")):match("\n#name ([^\n]+)"))
        if name then byName[name] = g.key end
    end
    local set, todo = {}, { START[race] }
    while #todo > 0 do
        local key = table.remove(todo)
        if key and not set[key] then
            set[key] = true
            for line in ("\n" .. (YR:GuideText(key) or "")):gmatch("\n#next ([^\n]+)") do
                for entry in (line:gsub("%s*<<.*$", "")):gmatch("[^;]+") do
                    local name = strtrim(entry):gsub("^Headstart Launch %(A%)\\", "")
                    if byName[name] then todo[#todo + 1] = byName[name] end
                end
            end
        end
    end
    return set
end

-- header, { step texts } - each step text starts with "step" and has no trailing newline
function YR.SplitSteps(text)
    local first = text:find("\nstep[^\n]*\n") or text:find("\nstep[^\n]*$")
    if not first then return text, {} end
    local header, rest = text:sub(1, first), text:sub(first + 1)
    local steps, from = {}, 1
    while true do
        local nextStep = rest:find("\nstep[^\n]*\n", from) or rest:find("\nstep[^\n]*$", from)
        if not nextStep then
            steps[#steps + 1] = (rest:sub(from):gsub("%s+$", ""))
            break
        end
        steps[#steps + 1] = (rest:sub(from, nextStep - 1):gsub("%s+$", ""))
        from = nextStep + 1
    end
    return header, steps
end

function YR.JoinSteps(header, steps)
    return header .. table.concat(steps, "\n") .. "\n"
end

-- One line for the editor: what the step asks you to do, without colours and icons.
local function Plain(s)
    -- RestedXP's own colour tokens (|cRXP_ENEMY_ ...) as well as ordinary |cAARRGGBB colours
    return (s:gsub("|cRXP_%u+_", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|n", " "))
end

function YR.StepSummary(step)
    local classes = step:match("^step%s*<<%s*([^\n]+)")
    local parts = {}
    for verb, rest in step:gmatch("\n%s*%.(%a+)%s[^\n]->>%s*([^\n]+)") do
        if verb == "accept" or verb == "turnin" or verb == "complete" or verb == "train" or verb == "collect"
            or verb == "hs" or verb == "deathskip" or verb == "xp" or verb == "destroy" or verb == "cast" then
            parts[#parts + 1] = Plain(rest)
        end
    end
    if #parts == 0 then
        for text in step:gmatch("\n%s*>>%s*([^\n]+)") do parts[#parts + 1] = Plain(text) end
    end
    if #parts == 0 then
        local where = step:match("\n%s*%.goto[^\n]->>%s*([^\n]+)")
        parts[1] = where and Plain(where) or "(no text)"
    end
    local line = table.concat(parts, "; ")
    return classes and (line .. "  [" .. classes .. "]") or line
end

function YR:SaveCustom(key, header, steps)
    if YR.ForgetNeeds then YR:ForgetNeeds() end
    local old = Custom()[key]
    Custom()[key] = { text = YR.JoinSteps(header, steps), saved = time(),
        base = old and old.base or (byKey[key] and byKey[key].text) }
end

function YR:RevertGuide(key)
    if YR.ForgetNeeds then YR:ForgetNeeds() end
    Custom()[key] = nil
end

-- Which steps of a stay, in b's order: for each index of a, the index in b it matches (longest
-- common subsequence of whole step texts), or nil where a's step is gone.
local function Match(a, b)
    local n, m = #a, #b
    local L = {}
    for i = n + 1, 1, -1 do
        L[i] = {}
        for j = m + 1, 1, -1 do
            if i > n or j > m then L[i][j] = 0
            elseif a[i] == b[j] then L[i][j] = L[i + 1][j + 1] + 1
            else L[i][j] = math.max(L[i + 1][j], L[i][j + 1]) end
        end
    end
    local map, i, j = {}, 1, 1
    while i <= n and j <= m do
        if a[i] == b[j] then map[i] = j i = i + 1 j = j + 1
        elseif L[i + 1][j] >= L[i][j + 1] then i = i + 1
        else j = j + 1 end
    end
    return map
end

-- What one side did to base, as hunks: base steps s .. e-1 replaced by ins (s == e: ins put in
-- before base step s; ins empty: steps removed). In base order, never overlapping each other.
local function Hunks(base, side)
    local map = Match(base, side)
    local hunks = {}
    local i0, j0 = 0, 0
    local function Gap(i1, j1)
        if i1 - i0 > 1 or j1 - j0 > 1 then
            local ins = {}
            for j = j0 + 1, j1 - 1 do ins[#ins + 1] = side[j] end
            hunks[#hunks + 1] = { s = i0 + 1, e = i1, ins = ins }
        end
    end
    for i = 1, #base do
        if map[i] then Gap(i, map[i]) i0, j0 = i, map[i] end
    end
    Gap(#base + 1, #side + 1)
    return hunks
end

-- Whether two hunks touch the same part of base: overlapping removals, two insertions at one spot,
-- or an insertion inside what the other removes. (Next to each other is fine.)
local function Touch(a, b)
    if a.s == a.e and b.s == b.e then return a.s == b.s end
    if a.s == a.e then return b.s < a.s and a.s < b.e end
    if b.s == b.e then return a.s < b.s and b.s < a.e end
    return a.s < b.e and b.s < a.e
end

-- base steps s .. e-1 with one side's hunks (inside that range) applied
local function Apply(base, hunks, s, e)
    local out, p = {}, s
    for _, h in ipairs(hunks) do
        for i = p, h.s - 1 do out[#out + 1] = base[i] end
        for _, x in ipairs(h.ins) do out[#out + 1] = x end
        p = h.e
    end
    for i = p, e - 1 do out[#out + 1] = base[i] end
    return out
end

local function Same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end

-- Three-way merge of step lists (like diff3): theirs (the new shipped route) with mine (the
-- player's edits of base) applied. Changes to different parts of the route are all kept; where both
-- changed the same part differently, the player's version of that part wins. Returns the steps and
-- how many parts that happened in.
function YR.MergeSteps(base, mine, theirs)
    local all = {}
    for _, h in ipairs(Hunks(base, mine)) do h.mine = true all[#all + 1] = h end
    for _, h in ipairs(Hunks(base, theirs)) do all[#all + 1] = h end
    table.sort(all, function(a, b) if a.s ~= b.s then return a.s < b.s end return a.e < b.e end)
    local out, clashes, pos = {}, 0, 1
    local function Put(list) for _, x in ipairs(list) do out[#out + 1] = x end end
    local k = 1
    while k <= #all do
        -- a group: this hunk and every later one touching the part it has grown to
        local g = { all[k] }
        local gs, ge = all[k].s, all[k].e
        k = k + 1
        while k <= #all and Touch({ s = gs, e = ge }, all[k]) do
            g[#g + 1] = all[k]
            gs, ge = math.min(gs, all[k].s), math.max(ge, all[k].e)
            k = k + 1
        end
        for i = pos, gs - 1 do out[#out + 1] = base[i] end
        local m, t = {}, {}
        for _, h in ipairs(g) do if h.mine then m[#m + 1] = h else t[#t + 1] = h end end
        if #t == 0 then Put(Apply(base, m, gs, ge))
        elseif #m == 0 then Put(Apply(base, t, gs, ge))
        else
            local rm, rt = Apply(base, m, gs, ge), Apply(base, t, gs, ge)
            if not Same(rm, rt) then clashes = clashes + 1 end
            Put(rm)
        end
        pos = ge
    end
    for i = pos, #base do out[#out + 1] = base[i] end
    return out, clashes
end

-- Take the new shipped route into the player's edited one. Returns the number of clashes.
function YR:MergeUpdate(key)
    if YR.ForgetNeeds then YR:ForgetNeeds() end
    local c, g = Custom()[key], byKey[key]
    if not (c and g and c.base) then return end
    local bHead, bSteps = YR.SplitSteps(c.base)
    local mHead, mSteps = YR.SplitSteps(c.text)
    local tHead, tSteps = YR.SplitSteps(g.text)
    local steps, clashes = YR.MergeSteps(bSteps, mSteps, tSteps)
    local head = (mHead == bHead) and tHead or mHead
    Custom()[key] = { text = YR.JoinSteps(head, steps), saved = time(), base = g.text,
        told = c.told, before = { text = c.text, base = c.base } }
    return clashes
end

-- Right after a merge (until the next save): back to the route as it was before it.
function YR:CanUndoMerge(key)
    local c = Custom()[key]
    return c and c.before ~= nil or false
end

function YR:UndoMerge(key)
    if YR.ForgetNeeds then YR:ForgetNeeds() end
    local c = Custom()[key]
    if not (c and c.before) then return end
    Custom()[key] = { text = c.before.text, base = c.before.base, saved = time(), told = c.told }
end

-- Keep the edited route as it is and stop offering this update.
function YR:KeepMine(key)
    local c, g = Custom()[key], byKey[key]
    if c and g then c.base = g.text end
end

-- The guide's name as RestedXP shows it, from its header.
function YR.GuideName(key)
    local text = YR:GuideText(key) or ""
    return text:match("\n#name ([^\n]+)") or key
end

-- Guides pasted in with Import that don't replace one we ship: kept by name, registered like ours.
local function Extra()
    YippRouteDB.extra = YippRouteDB.extra or {}
    return YippRouteDB.extra
end

function YR:RegisterExtras()
    if UnitFactionGroup("player") == "Horde" or not (RXPGuides and RXPGuides.RegisterGuide) then return end
    for name, text in pairs(Extra()) do
        text = Renamed(text)
        Extra()[name] = text
        local ok, err = pcall(RXPGuides.RegisterGuide, text)
        if not ok then YR.Print(("imported guide %s did not load: %s"):format(name, tostring(err))) end
    end
end

-- Import: a guide whose #name is one we ship becomes this player's version of it; any other
-- guide is kept as an extra. Returns what happened, or nil and why not.
function YR:ImportGuide(text)
    text = (text or ""):gsub("\r\n", "\n")
    local name = text:match("#name ([^\n]+)")
    if not name or not text:find("\nstep") then return nil, "that isn't a RestedXP guide (no #name or no steps)" end
    for _, g in ipairs(YR.shipped) do
        if (g.text:match("\n#name ([^\n]+)")) == name then
            local header, steps = YR.SplitSteps(text)
            YR:SaveCustom(g.key, header, steps)
            return "replaced your " .. name
        end
    end
    Extra()[name] = text
    return "added " .. name
end

-- ---------------------------------------------------------------------------
-- Recorded actions -> guide steps
-- ---------------------------------------------------------------------------
local STEP_KINDS = { accept = true, complete = true, turnin = true, buy = true, learn = true,
    hearth = true, death = true, level = true }

local function Goto(e)
    if not e[6] or e[6] == 0 then return "" end
    return ("\n    .goto %d,%.2f,%.2f"):format(e[6], e[7], e[8])
end

local function Talk(npc)
    return npc and ("\n    >>Talk to |cRXP_FRIENDLY_%s|r"):format(npc) or ""
end

local function Target(npc)
    return npc and ("\n    .target %s"):format(npc) or ""
end

-- The RestedXP step for one recorded action. titles/objectives come from the accept of that quest.
function YR.ActionStep(e, titles, objectives)
    local kind, q = e[2], e[3]
    local title = titles[q] or e.title or ("quest " .. q)
    if kind == "accept" then
        return "step" .. Goto(e) .. Talk(e.npc) .. ("\n    .accept %d >>Accept %s"):format(q, title) .. Target(e.npc)
    elseif kind == "turnin" then
        return "step" .. Goto(e) .. Talk(e.npc) .. ("\n    .turnin %d >>Turn in %s"):format(q, title) .. Target(e.npc)
    elseif kind == "complete" then
        local lines = {}
        for i = 1, math.max(1, objectives[q] or 1) do lines[#lines + 1] = ("\n    .complete %d,%d"):format(q, i) end
        return "step" .. Goto(e) .. ("\n    >>Finish %s"):format(title) .. table.concat(lines)
    elseif kind == "buy" then
        return "step" .. Goto(e) .. Talk(e.npc) .. ("\n    >>Buy %s"):format(e.name or ("item " .. e.item))
            .. ("\n    .collect %d,%d"):format(e.item, e.count or 1) .. Target(e.npc)
    elseif kind == "learn" then
        return "step" .. Goto(e) .. ("\n    .train %d >>Train %s"):format(e.spell, e.name or ("spell " .. e.spell))
    elseif kind == "hearth" then
        return "step\n    .hs >>Hearth"
    elseif kind == "death" then
        return "step" .. Goto(e) .. "\n    .deathskip >>Die and respawn at the Spirit Healer"
    elseif kind == "level" then
        return ("step\n    .xp %d >>Reach level %d"):format(e.to or e[4], e.to or e[4])
    end
end

-- One line for the list of what this character did.
local LABEL = { accept = "Took", complete = "Finished", turnin = "Handed in", buy = "Bought", learn = "Learned",
    hearth = "Hearthed", death = "Died", level = "Reached level" }

function YR.ActionLabel(e, titles)
    local kind = e[2]
    if kind == "buy" then return ("Bought %s"):format(e.name or e.item) end
    if kind == "learn" then return ("Learned %s"):format(e.name or e.spell) end
    if kind == "level" then return ("Reached level %d"):format(e.to or e[4]) end
    if kind == "hearth" or kind == "death" then return LABEL[kind] end
    return ("%s %s"):format(LABEL[kind], titles[e[3]] or e.title or e[3])
end

-- This character's actions, oldest first: { { e = event, label = text, step = guide step } }
function YR:RunActions()
    local r = YippRouteDB.runs and YippRouteDB.runs[YR.CharKey()]
    local out, titles, objectives, touched = {}, {}, {}, {}
    for _, e in ipairs(r and r.ev or {}) do
        if e[2] == "accept" then titles[e[3]] = e.title; objectives[e[3]] = e.obj end
        -- a delivery quest is "complete" the moment it is taken, and the log can note it again at the
        -- turn-in: a completion within a few seconds of taking or handing in the quest is no step
        local noise = e[2] == "complete" and touched[e[3]] and e[1] - touched[e[3]] <= 3
        if e[2] == "accept" or e[2] == "turnin" then touched[e[3]] = e[1] end
        if STEP_KINDS[e[2]] and not noise then
            out[#out + 1] = { e = e, label = YR.ActionLabel(e, titles), step = YR.ActionStep(e, titles, objectives) }
        end
    end
    return out
end
