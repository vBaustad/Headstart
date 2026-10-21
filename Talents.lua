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
local _, YR = ...

local function ClassID()
    local _, _, id = UnitClass("player")
    return id
end
YR.TalentClassID = ClassID

--- A class's builds (Headstart's), in order.
function YR.TalentBuildsOf(class)
    return type(YR.TalentBuilds) == "table" and YR.TalentBuilds[class] or {}
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
