-- Talent builds: Headstart's suggested builds for each class (Data/TalentBuilds.lua), on the trees as the game has
-- them (Data/TalentTrees.lua, both from the game's own data by tools/talents_gen.py), shown on the Talent builds
-- page - the three trees with each talent's points, and what to take at each level - and followed: with a build
-- picked for a character, the talent points notice says which talent is next (the owner, 2026-10-20: "a build
-- viewer, to see which builds to go for - levelling, tanking, damage - and what to take at each level"; "start - I
-- have no builds").
--   Your ranks: the game's own - the trait system Forever's talents are (C_ClassTalents' active config,
--   C_Traits.GetNodeInfo's ranksPurchased).
--   Per character: YippSetupCharDB.talentBuild, the key of the build followed (nil: none). Nothing listens for
--   anything here: the notice asks when it is drawn.
--   Your own build (the owner, 2026-11-03: "a talent planner, so you can plan your own talents"): one a class, for the
--   account, made on the same page by clicking talents and followed like Headstart's, under the key "own":
--   YippRouteDB.talentPlans[class] = { node, ... } in the order taken. The game's rules hold at every point, as
--   tools/talents_gen.py checks Headstart's: 5 points a row in the tab before a talent, a talent it needs at full rank
--   first, no talent past its ranks, 51 points.
local _, YR = ...

local function ClassID()
    local _, _, id = UnitClass("player")
    return id
end
YR.TalentClassID = ClassID

--- A class's builds: Headstart's in order, then your own (where the class has a tree).
function YR.TalentBuildsOf(class)
    local list = {}
    for _, b in ipairs(type(YR.TalentBuilds) == "table" and YR.TalentBuilds[class] or {}) do list[#list + 1] = b end
    if type(YR.TalentTrees) == "table" and YR.TalentTrees[class] then list[#list + 1] = YR.TalentOwn(class) end
    return list
end

local function Plans()
    if type(YippRouteDB) ~= "table" then return nil end
    YippRouteDB.talentPlans = type(YippRouteDB.talentPlans) == "table" and YippRouteDB.talentPlans or {}
    return YippRouteDB.talentPlans
end

--- Why `node` can't be the next point after `points`, in words; nil when it can.
function YR.TalentWhyNot(class, points, node)
    local tree = type(YR.TalentTrees) == "table" and YR.TalentTrees[class]
    local n = tree and tree.nodes[node]
    if not n then return "it isn't in this class's tree" end
    if #points >= 51 then return "all 51 points are spent" end
    local ranks, spent = {}, { 0, 0, 0 }
    for _, p in ipairs(points) do
        local t = tree.nodes[p]
        if t then
            ranks[p] = (ranks[p] or 0) + 1
            spent[t[3]] = spent[t[3]] + 1
        end
    end
    if (ranks[node] or 0) >= n[2] then return "it has all its ranks" end
    local need = (n[4] - 1) * 5
    if spent[n[3]] < need then return ("it needs %d points in %s (%d now)"):format(need, tree.tabs[n[3]], spent[n[3]]) end
    if n[6] and (ranks[n[6]] or 0) < tree.nodes[n[6]][2] then
        return ("it needs %s at full rank first"):format((YR.TalentNodeName(class, n[6])))
    end
    return nil
end

--- The points that hold, in order: one the rules don't allow at its place (a talent a patch took away) is left out.
function YR.TalentKeepValid(class, points)
    local out = {}
    for _, node in ipairs(points) do
        if not YR.TalentWhyNot(class, out, node) then out[#out + 1] = node end
    end
    return out
end

--- Your own build of a class, as a build: { key = "own", own = true, name, about, points }.
function YR.TalentOwn(class)
    local all = Plans()
    local saved = all and all[class]
    return { key = "own", own = true, name = "Your own build",
        about = "Click a talent to add a point, right-click to take one off.",
        points = YR.TalentKeepValid(class, type(saved) == "table" and saved or {}) }
end

--- Your own build written: the points kept as the rules allow.
function YR.TalentOwnSet(class, points)
    local all = Plans()
    if not all then return end
    all[class] = YR.TalentKeepValid(class, points or {})
    if YR.TalentNotice then YR.TalentNotice() end
end

--- A point added to a talent of your own build. Returns true, or false and why not.
function YR.TalentOwnAdd(class, node)
    local points = YR.TalentOwn(class).points
    local why = YR.TalentWhyNot(class, points, node)
    if why then return false, why end
    points[#points + 1] = node
    YR.TalentOwnSet(class, points)
    return true
end

--- A talent's last point taken off your own build. Returns true, or false and why not (a later point needs it).
function YR.TalentOwnRemove(class, node)
    local points = YR.TalentOwn(class).points
    local at
    for i = #points, 1, -1 do if points[i] == node then at = i break end end
    if not at then return false, "it has no point" end
    local rest = {}
    for i, p in ipairs(points) do
        if i ~= at then
            if YR.TalentWhyNot(class, rest, p) then return false, ("%s needs it"):format((YR.TalentNodeName(class, p))) end
            rest[#rest + 1] = p
        end
    end
    YR.TalentOwnSet(class, rest)
    return true
end

--- One build of a class by its key, or nil.
function YR.TalentBuild(class, key)
    for _, b in ipairs(YR.TalentBuildsOf(class)) do
        if b.key == key then return b end
    end
    return nil
end

--- The build this character follows, or nil.
function YR.TalentFollowed()
    local key = type(YippSetupCharDB) == "table" and YippSetupCharDB.talentBuild
    return key and YR.TalentBuild(ClassID(), key) or nil
end

--- Follow a build on this character (its key), or none (nil).
function YR.TalentFollow(key)
    if type(YippSetupCharDB) ~= "table" then return end
    YippSetupCharDB.talentBuild = key
    if YR.TalentNotice then YR.TalentNotice() end
end

--- Your ranks now, as the game has them: [node] = ranks; nil where it says nothing (no talents to read yet).
function YR.TalentRanksNow()
    local ct, tr = C_ClassTalents, C_Traits
    if not (ct and ct.GetActiveConfigID and tr and tr.GetNodeInfo) then return nil end
    local ok, config = pcall(ct.GetActiveConfigID)
    if not ok or type(config) ~= "number" or (issecretvalue and issecretvalue(config)) then return nil end
    local tree = type(YR.TalentTrees) == "table" and YR.TalentTrees[ClassID()]
    if not tree then return nil end
    local ranks = {}
    for node in pairs(tree.nodes) do
        local okN, info = pcall(tr.GetNodeInfo, config, node)
        local n = okN and type(info) == "table" and info.ranksPurchased
        ranks[node] = type(n) == "number" and not (issecretvalue and issecretvalue(n)) and n or 0
    end
    return ranks
end

--- The points of a build still to take, in its order (at most `n`): { node, the rank it brings, the level it is
--- for (10 for the first point) }. A point you have already - wherever in the build you took it - counts as taken.
function YR.TalentBuildNext(build, ranks, n)
    local want, out = {}, {}
    for i, node in ipairs(build.points) do
        want[node] = (want[node] or 0) + 1
        if (ranks[node] or 0) < want[node] then
            out[#out + 1] = { node = node, rank = want[node], level = 9 + i }
            if #out >= (n or 1) then break end
        end
    end
    return out
end

--- A node's name and its ranks, in this class's tree (the spell's name as the game gives it).
function YR.TalentNodeName(class, node)
    local tree = type(YR.TalentTrees) == "table" and YR.TalentTrees[class]
    local t = tree and tree.nodes[node]
    if not t then return "?", 0 end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(t[1])
    return type(name) == "string" and name or ("Talent " .. node), t[2]
end

--- The next talents of the build followed, as lines ("Deflection 2/5"), as many as `n`; empty where none is followed.
function YR.TalentNextLines(n)
    local build = YR.TalentFollowed()
    local ranks = build and YR.TalentRanksNow()
    if not ranks then return {} end
    local out = {}
    for _, p in ipairs(YR.TalentBuildNext(build, ranks, n)) do
        local name, max = YR.TalentNodeName(ClassID(), p.node)
        out[#out + 1] = ("%s %d/%d"):format(name, p.rank, max)
    end
    return out
end
