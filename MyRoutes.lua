-- Your own route from what you played (the user, 2026-10-04): "Save as route" on This run turns this
-- character's recorded run into routes like ours, step by step, yours to change in the Routes page
-- (drag to reorder, edit any line, delete) and to play in RestedXP (Headstart Launch, My routes).
--
-- One part per zone you levelled in, chained like ours (#next), named by levels, zone and race
-- ("1-6 My route: Dun Morogh (Dwarf/Gnome)"), never by character: a route doesn't depend on who saved
-- it. A short visit somewhere else (a city, a few steps in a zone on the way) stays in the part around
-- it. One set per race, Dwarves and Gnomes sharing (they start in the same place): saving again from
-- any character of that race replaces the set, your edits to it too; other races' sets and the routes
-- we ship stay as they are.
--
-- A step is a stop: the quests taken and handed in at one NPC; an objective finished; a trainer (and
-- what you learned); a vendor (and what you bought); a flight; the hearthstone; a death skip (a death
-- you came back from somewhere else); a longer stretch of killing with no quest progress (a grind, to
-- the XP you had at its end); a new zone.
-- YippRouteDB.myRoutes[race group] = { parts = { { key, name, text } } }. (A first version kept one
-- route per character, { name, text } under the character's name: those still load as they were.)
local _, YR = ...

local KEY = "my_"
-- race -> the set it shares, and how RestedXP and people write it
local GROUP = {
    Dwarf = { slug = "dwarfgnome", label = "Dwarf/Gnome", filter = "Dwarf/Gnome" },
    Gnome = { slug = "dwarfgnome", label = "Dwarf/Gnome", filter = "Dwarf/Gnome" },
    Human = { slug = "human", label = "Human", filter = "Human" },
    NightElf = { slug = "nightelf", label = "Night Elf", filter = "NightElf" },
    Orc = { slug = "orctroll", label = "Orc/Troll", filter = "Orc/Troll" },
    Troll = { slug = "orctroll", label = "Orc/Troll", filter = "Orc/Troll" },
    Tauren = { slug = "tauren", label = "Tauren", filter = "Tauren" },
    Scourge = { slug = "undead", label = "Undead", filter = "Undead" },
}
-- never a part of their own: passed through on the way somewhere
local CITY = { ["Ironforge"] = true, ["Stormwind City"] = true, ["Darnassus"] = true, ["Deeprun Tram"] = true,
    ["Orgrimmar"] = true, ["Thunder Bluff"] = true, ["Undercity"] = true }
local MIN_STEPS, MIN_SECONDS = 6, 600      -- less than this in a zone is a visit, not a part

local function Mine()
    YippRouteDB.myRoutes = YippRouteDB.myRoutes or {}
    return YippRouteDB.myRoutes
end

local function Group(race)
    if not race then
        local _
        _, race = UnitRace("player")
    end
    return GROUP[race] or { slug = (race or "unknown"):lower(), label = race or "?", filter = race }
end

function YR.IsMyRoute(key) return type(key) == "string" and key:sub(1, #KEY) == KEY end

-- Is this own route one for this race? (A first-version one is the character's own.)
function YR.MyRouteFor(key, race)
    if not YR.IsMyRoute(key) then return false end
    local g = Group(race)
    return key:sub(1, #KEY + #g.slug + 1) == KEY .. g.slug .. "_" or key == KEY .. YR.CharKey()
end

-- Every saved own route becomes a route like ours (YR.shipped) before routes are handed to RestedXP,
-- so the editor, export and RestedXP treat it the same. Called by YR:RegisterGuides, and after a save
-- (the editor sees it at once, RestedXP after a reload).
local shipped = {}
local function Ship(key, text)
    if not shipped[key] then
        shipped[key] = true
        YR:ShipGuide(key, text)
    end
    for _, g in ipairs(YR.shipped or {}) do
        if g.key == key then g.text = text end
    end
end

function YR.ShipMyRoutes()
    for owner, r in pairs(Mine()) do
        if type(r) == "table" and type(r.parts) == "table" then
            for _, p in ipairs(r.parts) do Ship(p.key, p.text) end
        elseif type(r) == "table" and type(r.text) == "string" then
            Ship(KEY .. owner, r.text)
        end
    end
end

-- ---------------------------------------------------------------------------
-- The run -> steps: { { text, zone, level, t } }
-- ---------------------------------------------------------------------------
local function At(e)
    if not e[6] or e[6] == 0 or not e[7] then return "" end
    return ("\n    .goto %d,%.2f,%.2f"):format(e[6], e[7], e[8])
end

local function Near(a, b, pct)
    return a[6] and a[6] == b[6] and a[7] and b[7] and math.abs(a[7] - b[7]) <= pct and math.abs(a[8] - b[8]) <= pct
end

-- The death skips in a log: a death you came back from soon after somewhere else (the Spirit Healer),
-- { death = event, alive = event, zone = the zone you came back in }. Where you die decides which healer
-- you come back at, so a step says the exact spot you died at (the user, 2026-10-04: "say exactly
-- where to die, it's the only way to reach the right Spirit Healer").
local function DeathSkips(ev)
    local out, zone = {}, nil
    for i, e in ipairs(ev) do
        if e[2] == "zone" and e.zone and e.zone ~= "" then zone = e.zone end
        if e[2] == "death" then
            for j = i + 1, math.min(#ev, i + 12) do
                local a = ev[j]
                if a[2] == "zone" and a.zone and a.zone ~= "" then zone = a.zone end
                if a[2] == "alive" then
                    -- back alive where you died is a corpse run (~50 yards; the Grizzled Den's healer
                    -- in Kharanos is only ~250 away)
                    if a[1] - e[1] <= 90 and a[6] == e[6] and not (a[7] and e[7] and math.abs(a[7] - e[7]) <= 1
                            and math.abs(a[8] - e[8]) <= 1) then
                        out[#out + 1] = { death = e, alive = a, zone = zone }
                    end
                    break
                end
            end
        end
    end
    return out
end

local function DeathLines(d)
    local e, a = d.death, d.alive
    return ("\n    .goto %d,%.2f,%.2f,5"):format(e[6], e[7], e[8])
        .. ("\n    >>|cRXP_WARN_Die right here (%.1f, %.1f): dying here brought you back at the Spirit Healer at %.1f, %.1f%s|r")
            :format(e[7], e[8], a[7], a[8], d.zone and (" in " .. d.zone) or "")
end

local function Talk(npc)
    return npc and ("\n    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_%s|r"):format(npc) or ""
end

-- A grind: at least this many kills over this long, all in one small area (in map percent, ~250 x 165
-- yards in Dun Morogh). Killing your way along to the next stop is no step (the user, 2026-10-04: most
-- "grind here" steps were only the mobs on the way), nor are the kills an objective then finishes.
local GRIND_KILLS, GRIND_SECONDS, GRIND_AREA = 10, 180, 5

function YR.RunToSteps(char)
    local run = YippRouteDB.runs and YippRouteDB.runs[char or YR.CharKey()]
    local ev = run and run.ev or {}
    local titles, objectives = {}, {}
    for _, e in ipairs(ev) do
        if e[2] == "accept" and e[3] then
            titles[e[3]] = titles[e[3]] or e.title
            objectives[e[3]] = objectives[e[3]] or e.obj
        end
    end
    local function Title(q) return titles[q] or ("quest " .. tostring(q)) end

    -- the zone each event happened in (the last "zone" event before it); the log itself isn't touched
    local zoneOf, zone = {}, nil
    for _, e in ipairs(ev) do
        if e[2] == "zone" and e.zone and e.zone ~= "" then zone = e.zone end
        zoneOf[e] = zone
    end

    local steps, visit, lastMap, handedIn = {}, nil, nil, {}
    local killList = {}                      -- the kills since the last stop
    local cur = { zone = nil, level = 1, t = 0 }

    local function Push(text, e)
        if e then
            cur.zone = zoneOf[e] or cur.zone
            cur.level = e[4] or cur.level
            cur.t = e[1] or cur.t
        end
        if e and e[6] and e[6] ~= 0 and lastMap and e[6] ~= lastMap and zoneOf[e] then
            steps[#steps + 1] = { text = ("step\n    .zone %s >> Travel to %s"):format(zoneOf[e], zoneOf[e]),
                zone = cur.zone, level = cur.level, t = cur.t }
        end
        if e and e[6] and e[6] ~= 0 then lastMap = e[6] end
        steps[#steps + 1] = { text = text, zone = cur.zone, level = cur.level, t = cur.t }
    end
    -- a stop at one NPC: its lines gathered, written when the next thing happens elsewhere
    local function Flush()
        if not visit then return end
        local v = visit
        visit = nil
        local lines = {}
        for _, l in ipairs(v.turnins) do lines[#lines + 1] = l end
        for _, l in ipairs(v.accepts) do lines[#lines + 1] = l end
        if v.trainer then
            lines[#lines + 1] = "\n    .trainer >> Train"
                .. (#v.learned > 0 and (": " .. table.concat(v.learned, ", ")) or "")
        end
        if #v.bought > 0 then
            lines[#lines + 1] = "\n    >>|cRXP_BUY_Buy|r " .. table.concat(v.bought, ", ")
        elseif v.vendor and #lines == 0 then
            lines[#lines + 1] = "\n    .vendor >> Sell your junk"
        end
        if #lines == 0 then return end
        Push("step" .. At(v.e) .. Talk(v.npc) .. table.concat(lines)
            .. (v.npc and ("\n    .target " .. v.npc) or ""), v.e)
    end
    -- the same stop: the same NPC (or none noted: the log doesn't always have it for a pick-up), close
    -- by, and soon after
    local function Visit(e, npc)
        local same = visit and e[1] - visit.last <= 90 and (
            (npc and visit.npc == npc and Near(visit.e, e, 1.5))
            or ((npc == nil or visit.npc == nil) and Near(visit.e, e, 0.6)))     -- ~30 yards: the same NPC
        if visit and not same then Flush() end
        if not visit then
            visit = { e = e, npc = npc, turnins = {}, accepts = {}, learned = {}, bought = {}, seen = {} }
        end
        visit.npc = visit.npc or npc
        visit.last = e[1]
        return visit
    end
    -- a grind: the last kills before the next stop, gone back from it while they stay in one small area
    -- (what came before them is killing on the way), enough of them over long enough; to the XP after
    -- the last one, where the first of them was
    local function Grind()
        local n = #killList
        local last = killList[n]
        local x0, x1, y0, y1, first
        for k = n, 1, -1 do
            local e = killList[k]
            if not (e[6] and e[6] ~= 0 and e[7] and last[6] == e[6]) then break end
            local nx0, nx1 = math.min(x0 or e[7], e[7]), math.max(x1 or e[7], e[7])
            local ny0, ny1 = math.min(y0 or e[8], e[8]), math.max(y1 or e[8], e[8])
            if nx1 - nx0 > GRIND_AREA or ny1 - ny0 > GRIND_AREA then break end
            x0, x1, y0, y1, first = nx0, nx1, ny0, ny1, k
        end
        if first and n - first + 1 >= GRIND_KILLS and last[1] - killList[first][1] >= GRIND_SECONDS and last[4] then
            Flush()
            Push(("step%s\n    .xp %d+%d >> Grind here, to %d XP into level %d"):format(
                At(killList[first]), last[4], last[5] or 0, last[5] or 0, last[4]), killList[first])
        end
        killList = {}
    end

    for i, e in ipairs(ev) do
        local kind = e[2]
        if kind == "kill" then
            killList[#killList + 1] = e
        elseif kind == "accept" or kind == "turnin" then
            Grind()
            local v = Visit(e, e.npc)
            if kind == "accept" then
                v.accepts[#v.accepts + 1] = ("\n    .accept %d >> Accept %s"):format(e[3], Title(e[3]))
            else
                handedIn[e[3]] = true
                v.turnins[#v.turnins + 1] = ("\n    .turnin %d >> Turn in %s"):format(e[3], Title(e[3]))
            end
        elseif kind == "complete" and e[3] then
            -- no step for a quest complete the moment it's taken or handed in (a delivery), or noted again
            -- after its hand-in
            local noise = handedIn[e[3]]
            for j = math.max(1, i - 6), math.min(#ev, i + 6) do
                local o = ev[j]
                if j ~= i and (o[2] == "accept" or o[2] == "turnin") and o[3] == e[3] and math.abs(o[1] - e[1]) <= 5 then
                    noise = true
                end
            end
            if not noise then
                -- the kills before an objective finishes were for it: no grind step for them
                killList = {}
                Flush()
                local lines = {}
                for k = 1, math.max(1, tonumber(objectives[e[3]]) or 1) do
                    lines[#lines + 1] = ("\n    .complete %d,%d"):format(e[3], k)
                end
                Push("step" .. At(e) .. ("\n    >>%s: finish it here"):format(Title(e[3])) .. table.concat(lines), e)
                killList = {}
            end
        elseif kind == "trainer" then
            Grind()
            Visit(e, e.npc).trainer = true
        elseif kind == "learn" then
            local name = e.name or tostring(e.spell)
            if visit and visit.trainer and not visit.seen[name] then
                visit.seen[name] = true
                visit.learned[#visit.learned + 1] = name
            end
        elseif kind == "vendor" then
            Grind()
            Visit(e, e.npc).vendor = true
        elseif kind == "buy" then
            local v = Visit(e, e.npc)
            v.bought[#v.bought + 1] = (e.name or ("item " .. tostring(e.item))) .. ((e.count or 1) > 1 and (" x" .. e.count) or "")
        elseif kind == "flight" then
            Grind()
            Flush()
            local to
            for j = i + 1, math.min(#ev, i + 30) do
                if ev[j][2] == "zone" and ev[j].zone and ev[j].zone ~= "" then to = ev[j].zone break end
            end
            Push("step" .. At(e) .. Talk(e.npc) .. ("\n    .fly %s >> Fly to %s"):format(to or "your next stop", to or "your next stop")
                .. (e.npc and ("\n    .target " .. e.npc) or ""), e)
        elseif kind == "hearth" then
            Grind()
            Flush()
            local to
            for j = i + 1, math.min(#ev, i + 10) do
                if ev[j][2] == "zone" and ev[j].zone and ev[j].zone ~= "" then to = ev[j].zone break end
            end
            Push("step\n    .hs >> Hearth" .. (to and (" to " .. to) or ""), nil)
        elseif kind == "death" then
            -- a death skip: back alive soon after, somewhere else (the Spirit Healer)
            for j = i + 1, math.min(#ev, i + 12) do
                local a = ev[j]
                if a[2] == "alive" then
                    if a[1] - e[1] <= 90 and not Near(a, e, 1) then
                        Grind()
                        Flush()
                        Push("step\n    #completewith next" .. DeathLines({ death = e, alive = a, zone = zoneOf[a] })
                            .. "\n    .deathskip >> Die and respawn at the |cRXP_FRIENDLY_Spirit Healer|r", e)
                    end
                    break
                end
            end
        end
    end
    Flush()
    return steps
end

-- ---------------------------------------------------------------------------
-- A run that followed one of our routes: its steps, as we wrote them
-- ---------------------------------------------------------------------------
-- The log notes the route step you were on ("step": route name and number). A run made on our routes
-- becomes a route of our steps, as written (level gates, conditions, waypoints, notes), in the order
-- you did them (the user, 2026-10-04: "as good as the one we made"):
--   * a step with quests in it: kept when you took, finished or handed in one of them, at that moment;
--   * a step without (travel, trainer, a grind to a level, a death skip): kept when it lies within the
--     part of that route you played, after the step before it;
--   * a quest you did that no kept step has: a step of its own, made from the log as for any run.
-- Labels that point at a step that didn't make it: "#requires" goes, "#completewith" becomes "next".
local function Plain(s)
    s = s:gsub("%f[%d]0+(%d)", "%1")
    return (s:gsub(" %((%a+) [ABC]%)$", ""))          -- a role version ("(Duo B)") is its route
end

local function QuestsOf(step)
    local out = {}
    for kind, q in step:gmatch("\n%s*%.(%a+)%s+(%d+)") do
        if kind == "accept" or kind == "turnin" or kind == "complete" then out[#out + 1] = { kind, tonumber(q) } end
    end
    return out
end

function YR.RunToRouteSteps(char)
    local run = YippRouteDB.runs and YippRouteDB.runs[char or YR.CharKey()]
    local ev = run and run.ev or {}
    if not YR.CharSteps then return nil end
    local keyOf = {}
    for _, g in ipairs(YR.shipped or {}) do
        if not YR.IsMyRoute(g.key) then keyOf[YR.GuideName(g.key)] = g.key end
    end
    -- where you were on each route, and when you did what with each quest
    local visited, order, did, zone, level = {}, {}, {}, nil, 1
    local timeline = {}
    for _, e in ipairs(ev) do
        if e[2] == "zone" and e.zone and e.zone ~= "" then zone = e.zone end
        level = e[4] or level
        timeline[#timeline + 1] = { t = e[1], zone = zone, level = level }
        if e[2] == "step" and type(e.guide) == "string" and tonumber(e.step) then
            local key = keyOf[Plain(e.guide)]
            if key then
                if not visited[key] then visited[key] = {} order[#order + 1] = key end
                local v = visited[key]
                local n = tonumber(e.step)
                v[n] = v[n] or e[1]
                v.lo, v.hi = math.min(v.lo or n, n), math.max(v.hi or n, n)
            end
        elseif (e[2] == "accept" or e[2] == "turnin" or e[2] == "complete") and e[3] then
            did[e[2] .. e[3]] = did[e[2] .. e[3]] or e[1]
        end
    end
    if #order == 0 then return nil end
    local function At(t)
        local found = timeline[1] or { zone = nil, level = 1 }
        for _, p in ipairs(timeline) do
            if p.t > t then break end
            found = p
        end
        return found.zone, found.level
    end

    local kept, covered, labels = {}, {}, {}
    for r, key in ipairs(order) do
        local v = visited[key]
        local steps = YR.CharSteps(key)
        local lastT = nil
        for i = v.lo, math.min(v.hi, #steps) do
            local text = steps[i]
            local qs = QuestsOf("\n" .. text)
            local t
            if #qs > 0 then
                for _, a in ipairs(qs) do
                    local when = did[a[1] .. a[2]]
                    if when and (not t or when < t) then t = when end
                end
            else
                -- right after the step before it in the route (step numbers in an older log can be off
                -- by a few after an update; the step before it is where it belongs either way)
                t = lastT or v[v.lo]
            end
            if t then
                -- tie-break in route order, and routes in the order you came to them
                kept[#kept + 1] = { text = text, t = t, ord = r * 100000 + i }
                for _, a in ipairs(qs) do covered[a[2]] = true end
                for label in text:gmatch("#label%s+(%S+)") do labels[label] = true end
                lastT = t
            end
        end
    end
    -- what you did that our steps don't have
    for _, s in ipairs(YR.RunToSteps(char)) do
        local qs = QuestsOf("\n" .. s.text)
        local new = #qs > 0
        for _, a in ipairs(qs) do if covered[a[2]] then new = false end end
        if new then kept[#kept + 1] = { text = s.text, t = s.t, ord = 0 } end
    end
    table.sort(kept, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.ord < b.ord
    end)
    -- each of our death-skip steps gets the spot you actually died at for it: the first death skip in the
    -- log from a little before the step until the next death-skip step (you may have done the next stop
    -- first, as at Mountaineer Cornelius before the Grizzled Den's skip). Our own wording is general ("in
    -- the cave"); yours is exact, and the step moves to when you died.
    local deaths, used, skips = DeathSkips(ev), {}, {}
    for n, k in ipairs(kept) do
        if k.text:find("\n%s*%.deathskip") then skips[#skips + 1] = n end
    end
    for s, n in ipairs(skips) do
        local k = kept[n]
        local before = skips[s + 1] and kept[skips[s + 1]].t or math.huge
        local d
        for m, x in ipairs(deaths) do
            if not used[m] and x.death[1] >= k.t - 300 and x.death[1] <= before + 30 then
                used[m] = true
                d = x
                break
            end
        end
        if d and d.death[7] and d.alive[7] then
            local body = k.text:gsub("\n[ \t]*%.goto[^\n]*", ""):gsub("\n[ \t]*>>|cRXP_WARN_[^\n]*", "")
            -- after "step" and its # lines
            local head, rest = body:match("^(step[^\n]*\n?[ \t]*#[^\n]*)(.*)$")
            if not head then head, rest = body:match("^(step[^\n]*)(.*)$") end
            k.text = head .. DeathLines(d) .. rest
            k.t = d.death[1]
        end
    end
    table.sort(kept, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        return a.ord < b.ord
    end)
    local out = {}
    for _, k in ipairs(kept) do
        local text = k.text:gsub("\n[ \t]*#requires%s+(%S+)[^\n]*", function(l) return labels[l] and nil or "" end)
        text = text:gsub("(#completewith%s+)(%S+)", function(pre, l)
            if l == "next" or labels[l] then return nil end
            return pre .. "next"
        end)
        local z, l = At(k.t)
        out[#out + 1] = { text = text, zone = z, level = l, t = k.t }
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Steps -> one part per zone
-- ---------------------------------------------------------------------------
-- { { zone, steps = { step records } } }: runs of steps in one zone; a city, an unknown zone or a short
-- run (fewer than MIN_STEPS steps and under MIN_SECONDS) joins the part before it (the first: the next).
function YR.SplitByZone(steps)
    local runs = {}
    for _, s in ipairs(steps) do
        local last = runs[#runs]
        if last and last.zone == s.zone then
            last.steps[#last.steps + 1] = s
        else
            runs[#runs + 1] = { zone = s.zone, steps = { s } }
        end
    end
    local function Visit(r)
        return not r.zone or CITY[r.zone]
            or (#r.steps < MIN_STEPS and (r.steps[#r.steps].t or 0) - (r.steps[1].t or 0) < MIN_SECONDS)
    end
    local parts = {}
    for _, r in ipairs(runs) do
        local last = parts[#parts]
        if last and (Visit(r) or last.zone == r.zone) then
            for _, s in ipairs(r.steps) do last.steps[#last.steps + 1] = s end
        elseif not last and Visit(r) then
            parts[1] = { zone = nil, steps = r.steps, pending = true }
        elseif last and last.pending then
            -- what came before the first real part belongs to it
            for _, s in ipairs(r.steps) do last.steps[#last.steps + 1] = s end
            last.zone, last.pending = r.zone, nil
        else
            parts[#parts + 1] = { zone = r.zone, steps = r.steps }
        end
    end
    return parts
end

function YR.HasMyRoute(race) return Mine()[Group(race).slug] ~= nil end

-- This character's run as its race's routes: replaces that race's set saved before, and any edits to
-- it. Returns the number of steps and of parts, or nil and why not.
function YR.SaveRunAsRoute(char, race)
    char = char or YR.CharKey()
    local g = Group(race)
    -- our steps where you followed our routes; else made from the log
    local steps = YR.RunToRouteSteps(char)
    if not steps or #steps == 0 then steps = YR.RunToSteps(char) end
    if #steps == 0 then return nil, "nothing recorded for this character yet" end
    local parts = YR.SplitByZone(steps)
    local faction = UnitFactionGroup("player") or "Alliance"
    local groupName = faction == "Horde" and "Headstart Launch (H)" or "Headstart Launch (A)"
    -- names: levels, zone, race; the same twice gets a number
    local names, used = {}, {}
    for i, p in ipairs(parts) do
        local lo, hi = p.steps[1].level or 1, p.steps[#p.steps].level or 1
        local name = ("%d-%d My route: %s (%s)"):format(lo, hi, p.zone or "the start", g.label)
        if used[name] then name = name .. " " .. (used[name] + 1) end
        used[name] = (used[name] or 0) + 1
        names[i] = name
    end
    local saved = {}
    for i, p in ipairs(parts) do
        local lines = {}
        for _, s in ipairs(p.steps) do lines[#lines + 1] = s.text end
        local header = { "#forever", "#version 1", "<< " .. faction .. " " .. g.filter, "#group " .. groupName,
            "#subgroup My routes", "#name " .. names[i] }
        if names[i + 1] then header[#header + 1] = "#next " .. names[i + 1] end
        saved[i] = { key = ("%s%s_%d"):format(KEY, g.slug, i), name = names[i],
            text = table.concat(header, "\n") .. "\n" .. table.concat(lines, "\n") .. "\n" }
    end
    -- the old set and its edits go; parts it had beyond the new ones leave the editor's list too
    local keep = {}
    for _, p in ipairs(saved) do keep[p.key] = true end
    local prefix = KEY .. g.slug .. "_"
    for key in pairs(YippRouteDB.custom or {}) do
        if key:sub(1, #prefix) == prefix then YippRouteDB.custom[key] = nil end
    end
    for i = #(YR.shipped or {}), 1, -1 do
        local k = YR.shipped[i].key
        if k:sub(1, #prefix) == prefix and not keep[k] then
            table.remove(YR.shipped, i)
            shipped[k] = nil
        end
    end
    Mine()[g.slug] = { parts = saved }
    YR.ShipMyRoutes()
    return #steps, #saved, names[1], g.label
end

-- This race's own routes gone (and their edits); with a first-version one of this character's too.
-- Takes a reload to leave RestedXP. Returns how many parts went.
function YR.DeleteMyRoutes(race)
    local g = Group(race)
    local prefix = KEY .. g.slug .. "_"
    local mine, gone = Mine(), 0
    if mine[g.slug] and mine[g.slug].parts then gone = #mine[g.slug].parts end
    mine[g.slug] = nil
    if mine[YR.CharKey()] then mine[YR.CharKey()] = nil gone = gone + 1 end
    local function Ours(k) return k:sub(1, #prefix) == prefix or k == KEY .. YR.CharKey() end
    for key in pairs(YippRouteDB.custom or {}) do
        if Ours(key) then YippRouteDB.custom[key] = nil end
    end
    for i = #(YR.shipped or {}), 1, -1 do
        local k = YR.shipped[i].key
        if Ours(k) then
            table.remove(YR.shipped, i)
            shipped[k] = nil
        end
    end
    return gone
end

StaticPopupDialogs["HEADSTART_DELETE_MY_ROUTE"] = {
    text = "Headstart: delete your %s route? This can't be undone (your run log stays: you can save it again).",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function()
        local n = YR.DeleteMyRoutes()
        YR.Print(("deleted your route (%d part%s). Reload to take it out of RestedXP."):format(n, n == 1 and "" or "s"))
        StaticPopup_Show("HEADSTART_RELOAD")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function YR.AskDeleteMyRoutes()
    if not YR.HasMyRoute() and not Mine()[YR.CharKey()] then
        YR.Print("you have no route of your own for this race yet.")
        return
    end
    StaticPopup_Show("HEADSTART_DELETE_MY_ROUTE", Group().label)
end

StaticPopupDialogs["HEADSTART_SAVE_RUN_ROUTE"] = {
    text = "Headstart: save this run as your %s route?%s",
    button1 = "Save",
    button2 = "Cancel",
    OnAccept = function()
        local n, parts, first, label = YR.SaveRunAsRoute()
        if not n then YR.Print("couldn't save the route: " .. tostring(parts)) return end
        YR.Print(("saved your %s route: %d steps in %d part%s, from %s. Reload to play it in RestedXP"
            .. " (Headstart Launch, My routes); edit it in Routes."):format(label, n, parts, parts == 1 and "" or "s", first))
        StaticPopup_Show("HEADSTART_RELOAD")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function YR.AskSaveRunAsRoute()
    local g = Group()
    StaticPopup_Show("HEADSTART_SAVE_RUN_ROUTE", g.label,
        YR.HasMyRoute() and ("\n\nIt replaces the %s route you saved before, and your edits to it."):format(g.label) or "")
end
