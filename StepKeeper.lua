-- Keep your place in a route through an update. RestedXP saves the step you're on as its number (and an
-- id that is the step's line number), so a route that gains or loses steps before yours puts you on
-- another step after a /reload: a logged run (2026-10-03) was moved four steps on, past the trogg
-- hand-ins, the Dark Iron spies and Farsen, when Treacherous Cold's steps came out. So Headstart
-- remembers the step itself (its text, and the quests it takes, hands in or works) per character, and
-- when one of our routes loads with something else at that number, moves you to the same step again,
-- the nearest one if it appears twice. YippRouteDB.place[character] = { key, n, text, quests }.
local _, YR = ...

if type(RXP) ~= "table" or type(RXP.SetStep) ~= "function" or type(RXP.LoadGuide) ~= "function" then return end

-- RestedXP pads the level range ("05-11 Dun Morogh") and adds " (Duo B)" and the like to role versions
local function Plain(s) return (s:gsub("%f[%d]0+(%d)", "%1")) end

-- Asked at every step change: the answer for a guide's name is kept (false: not one of ours) until
-- the routes are read again (cache, below, is emptied then too).
local keyOf = {}
local function OurKey(guide)
    local raw = type(guide) == "table" and type(guide.name) == "string" and guide.name
    if not raw then return nil end
    if keyOf[raw] ~= nil then return keyOf[raw] or nil end
    local name = Plain(raw)
    keyOf[raw] = false
    for _, g in ipairs(YR.shipped or {}) do
        if YR.GuideName(g.key) == name then keyOf[raw] = g.key break end
    end
    return keyOf[raw] or nil
end
YR.RouteKeyOf = OurKey          -- (Shopping.lua: the route you're on, for its next buy)

-- The steps RestedXP has for this character, in its order: the route's steps whose "step << ..." filter
-- is this character's (RestedXP leaves the others out when it loads the route).
local cache = {}
function YR.CharSteps(key)
    if cache[key] then return cache[key] end
    local list = {}
    local _, steps = YR.SplitSteps(YR:GuideText(key) or "")
    for _, step in ipairs(steps or {}) do
        if YR.Shows(step:match("^step%s*<<%s*([^\n%-]+)")) then list[#list + 1] = step end
    end
    cache[key] = list
    return list
end

local function Quests(step)
    local q = {}
    for kind, id in step:gmatch("\n%s*%.(%a+)%s+%-?(%d+)") do
        if kind == "accept" or kind == "turnin" or kind == "complete" then q[#q + 1] = kind .. id end
    end
    return table.concat(q, " ")
end

local function Place()
    YippRouteDB.place = YippRouteDB.place or {}
    return YippRouteDB.place
end

local function Remember()
    if type(YippRouteDB) ~= "table" then return end
    local guide = RXP.currentGuide
    local key = OurKey(guide)
    local n = type(RXPCData) == "table" and tonumber(RXPCData.currentStep)
    if not key or not n then return end
    local step = YR.CharSteps(key)[n]
    if not step then return end
    -- the same place as last time (a step set again, a route loaded again): nothing new to write down
    local places, me = Place(), YR.CharKey()
    local saved = places[me]
    if saved and saved.key == key and saved.n == n and saved.text == step then return end
    places[me] = { key = key, n = n, text = step, quests = Quests(step) }
end

-- Where the remembered step is in the route as it is now: the same text, else the same quests (a step
-- whose wording changed), the nearest to the old number either way; nil if it isn't there any more.
function YR.FindPlace(key, saved)
    local list = YR.CharSteps(key)
    if list[saved.n] == saved.text then return saved.n end
    local best
    for pass = 1, 2 do
        for i, step in ipairs(list) do
            local same = pass == 1 and step == saved.text
                or pass == 2 and saved.quests ~= "" and Quests(step) == saved.quests
            if same and (not best or math.abs(i - saved.n) < math.abs(best - saved.n)) then best = i end
        end
        if best then return best end
    end
end

local function Restore()
    if type(YippRouteDB) ~= "table" then return end
    local guide = RXP.currentGuide
    local key = OurKey(guide)
    local saved = key and YippRouteDB.place and YippRouteDB.place[YR.CharKey()]
    if not saved or saved.key ~= key then return end
    local now = type(RXPCData) == "table" and tonumber(RXPCData.currentStep)
    local at = YR.FindPlace(key, saved)
    if at and now and at ~= now and type(guide.steps) == "table" and guide.steps[at] then
        YR.Print(("the route changed since you were last on it: back at your step (%d, was %d)."):format(at, now))
        RXP.SetStep(at)
    end
end

-- RestedXP sets steps while it loads a route (the saved number first): nothing is remembered until it
-- is done and the place checked, or the old number would overwrite the step we're looking for.
-- RestedXP also sets a step for every one it skips on the way to yours (a chain of finished steps is
-- dozens of calls in one frame): the place is written down once, on the next frame, when it has settled.
-- With the routes off the hook does nothing but ask that, and the wrap is RestedXP's own function
-- called straight through: the same arguments, the same returns, its own errors with its own
-- traceback. (The hook and the wrap below are put on as the file loads, not at the login: RestedXP
-- may load its route before then, and that load is the one your place is checked on.)
local function Routes() return type(YippRouteDB) == "table" and YR.RoutesOn ~= nil and YR.RoutesOn() end
local loading, soon = false, false
local function RememberSoon()
    soon = false
    Remember()
end
hooksecurefunc(RXP, "SetStep", function()
    if loading or soon or not Routes() then return end
    soon = true
    C_Timer.After(0, RememberSoon)
end)
local load = RXP.LoadGuide
RXP.LoadGuide = function(...)
    if not Routes() then return load(...) end
    loading = true
    local results = { pcall(load, ...) }
    loading = false
    if not results[1] then error(results[2], 0) end
    cache, keyOf = {}, {}             -- the route may have been edited or updated since
    loading = true
    local ok, err = pcall(Restore)
    loading = false
    if not ok then YR.Print("couldn't check your place in the route: " .. tostring(err)) end
    Remember()
    return unpack(results, 2)
end
