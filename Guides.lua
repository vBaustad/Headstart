-- The routes YippRoute ships, and each player's own edits of them.
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

function YR:RegisterGuides()
    if UnitFactionGroup("player") == "Horde" or not (RXPGuides and RXPGuides.RegisterGuide) then return end
    for _, g in ipairs(YR.shipped) do
        local ok, err = pcall(RXPGuides.RegisterGuide, YR:GuideText(g.key))
        if not ok then YR.Print(("guide %s did not load: %s"):format(g.key, tostring(err))) end
    end
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
    Custom()[key] = { text = YR.JoinSteps(header, steps), saved = time() }
end

function YR:RevertGuide(key)
    Custom()[key] = nil
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
