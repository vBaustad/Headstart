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
