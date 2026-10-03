-- Your own route from what you played (the user, 2026-10-04): "Save as route" on This run turns this
-- character's recorded run into a route like ours, step by step, and it is yours to change in the
-- Routes page (drag to reorder, edit any line, delete) and to play in RestedXP (Headstart Launch, My
-- routes). One per character: saving again replaces it, your edits to it too. The routes we ship stay
-- as they are.
--
-- A step is a stop: the quests taken and handed in at one NPC; an objective finished; a trainer (and
-- what you learned); a vendor (and what you bought); a flight; the hearthstone; a death skip (a death
-- you came back from somewhere else); a longer stretch of killing with no quest progress (a grind, to
-- the XP you had at its end); a new zone. YippRouteDB.myRoutes[character] = { name = ..., text = ... }.
local _, YR = ...

local KEY = "my_"

local function Mine()
    YippRouteDB.myRoutes = YippRouteDB.myRoutes or {}
    return YippRouteDB.myRoutes
end

function YR.MyRouteKey(char) return KEY .. (char or YR.CharKey()) end
function YR.IsMyRoute(key) return type(key) == "string" and key:sub(1, #KEY) == KEY end

-- Every saved own route becomes a route like ours (YR.shipped) before routes are handed to RestedXP,
-- so the editor, export and RestedXP treat it the same. Called by YR:RegisterGuides.
local shipped = {}
function YR.ShipMyRoutes()
    for char, r in pairs(Mine()) do
        local key = YR.MyRouteKey(char)
        if type(r) == "table" and type(r.text) == "string" then
            if not shipped[key] then
                shipped[key] = true
                YR:ShipGuide(key, r.text)
            end
            -- saved again this session: the editor shows the new one at once (RestedXP after a reload)
            for _, g in ipairs(YR.shipped or {}) do
                if g.key == key then g.text = r.text end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- The run -> steps
-- ---------------------------------------------------------------------------
local function At(e)
    if not e[6] or e[6] == 0 or not e[7] then return "" end
    return ("\n    .goto %d,%.2f,%.2f"):format(e[6], e[7], e[8])
end

local function Near(a, b, pct)
    return a[6] and a[6] == b[6] and a[7] and b[7] and math.abs(a[7] - b[7]) <= pct and math.abs(a[8] - b[8]) <= pct
end

local function Talk(npc)
    return npc and ("\n    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_%s|r"):format(npc) or ""
end

local GRIND_KILLS, GRIND_SECONDS = 8, 150

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
    local kills, killFrom, lastKill, killAt = 0, nil, nil, nil

    local function Push(text, e)
        if e and e[6] and e[6] ~= 0 and lastMap and e[6] ~= lastMap and zoneOf[e] then
            steps[#steps + 1] = ("step\n    .zone %s >> Travel to %s"):format(zoneOf[e], zoneOf[e])
        end
        if e and e[6] and e[6] ~= 0 then lastMap = e[6] end
        steps[#steps + 1] = text
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
        Push("step" .. (v.optional and "\n    #optional" or "") .. At(v.e) .. Talk(v.npc) .. table.concat(lines)
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
    -- a stretch of killing with nothing else: a grind, to the XP you had after its last kill
    local function Grind()
        if kills >= GRIND_KILLS and lastKill and lastKill[1] - killFrom >= GRIND_SECONDS and lastKill[4] then
            Flush()
            Push(("step%s\n    .xp %d+%d >> Grind here, to %d XP into level %d"):format(
                At(killAt), lastKill[4], lastKill[5] or 0, lastKill[5] or 0, lastKill[4]), killAt)
        end
        kills, killFrom, lastKill, killAt = 0, nil, nil, nil
    end

    for i, e in ipairs(ev) do
        local kind = e[2]
        if kind == "kill" then
            kills = kills + 1
            killFrom = killFrom or e[1]
            lastKill = e
            killAt = killAt or e
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
                Grind()
                Flush()
                local lines = {}
                for k = 1, math.max(1, tonumber(objectives[e[3]]) or 1) do
                    lines[#lines + 1] = ("\n    .complete %d,%d"):format(e[3], k)
                end
                Push("step" .. At(e) .. ("\n    >>%s: finish it here"):format(Title(e[3])) .. table.concat(lines), e)
                kills, killFrom, lastKill, killAt = 0, nil, nil, nil
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
                    if a[1] - e[1] <= 90 and not Near(a, e, 8) then
                        Grind()
                        Flush()
                        Push("step\n    #completewith next" .. At(e)
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
-- Saving
-- ---------------------------------------------------------------------------
local function Levels(char)
    local run = YippRouteDB.runs and YippRouteDB.runs[char]
    local lo, hi
    for _, e in ipairs(run and run.ev or {}) do
        if e[4] then lo = math.min(lo or e[4], e[4]) hi = math.max(hi or e[4], e[4]) end
    end
    return lo or 1, hi or 1
end

function YR.MyRouteName(char)
    char = char or YR.CharKey()
    local lo, hi = Levels(char)
    return ("%d-%d My route (%s)"):format(lo, hi, (char:match("^[^-]+")) or char)
end

function YR.HasMyRoute(char) return Mine()[char or YR.CharKey()] ~= nil end

-- This character's run as its route: replaces the one saved before, and any edits to it. Returns the
-- number of steps, or nil and why not.
function YR.SaveRunAsRoute(char)
    char = char or YR.CharKey()
    local steps = YR.RunToSteps(char)
    if #steps == 0 then return nil, "nothing recorded for this character yet" end
    local name = YR.MyRouteName(char)
    local header = table.concat({ "#forever", "#version 1", "<< " .. (UnitFactionGroup("player") or "Alliance"),
        "#group Headstart Launch (A)", "#subgroup My routes", "#name " .. name }, "\n")
    Mine()[char] = { name = name, text = header .. "\n" .. table.concat(steps, "\n") .. "\n" }
    if YippRouteDB.custom then YippRouteDB.custom[YR.MyRouteKey(char)] = nil end
    YR.ShipMyRoutes()
    return #steps, name
end

StaticPopupDialogs["HEADSTART_SAVE_RUN_ROUTE"] = {
    text = "Headstart: save this run as your route?%s",
    button1 = "Save",
    button2 = "Cancel",
    OnAccept = function()
        local n, name = YR.SaveRunAsRoute()
        if not n then YR.Print("couldn't save the route: " .. tostring(name)) return end
        YR.Print(("saved %s: %d steps. Reload to play it in RestedXP (Headstart Launch, My routes); edit it in Routes."):format(name, n))
        StaticPopup_Show("HEADSTART_RELOAD")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function YR.AskSaveRunAsRoute()
    StaticPopup_Show("HEADSTART_SAVE_RUN_ROUTE",
        YR.HasMyRoute() and "\n\nIt replaces the route you saved from this character before, and your edits to it." or "")
end
