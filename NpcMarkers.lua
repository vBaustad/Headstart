-- NPC markers: an icon on the nameplate of the NPC the RestedXP step you're on says to talk to (the owner,
-- 2026-10-16: "kan vi marke npc som vi skal snakke med kanskje?"). RestedXP's own marking puts a raid target on
-- the NPC, and SetRaidTarget is restricted on Forever: it needs a click or a macro there.
--   Who: the names on the active steps' .target lines (RestedXP's own: element.targets; a name may come as
--   "Name::id", or as the id alone until RestedXP has the name). Matched by the NPC's id where the guide gave one,
--   else by its name; another player is never marked. Only while that step is active.
--   Which icon: "?" while the step has a quest to hand in, "!" while it has one to take, else a speech bubble.
--   Quest mobs (npcMarkersMobs, on unless turned off): a sword on the plates of enemies that count for a quest in
--   your log - the game's own quest objective lines on the unit, and the step's .mob lines.
--   The icon stands beside the plate's health bar where it shows one, else over its name (Blizzard's plates and
--   other addons' differ: Plater and ElvUI keep theirs in plate.unitFrame, Kui in plate.kui).
--   Friendly NPC plates (npcMarkersPlates, on unless turned off): the game has them off unless you turned them
--   on, and a talk-to NPC with no plate has nowhere to show the icon. While this is on the game's setting is on;
--   what it was is written down first and put back when this goes off, as you log out (so with Headstart removed
--   the game has your own), and in a fight as it ends. Changed by you while this holds it: yours stands.
--   Secret values (Forever can hand out a unit's GUID, name or tooltip as secret in combat): no marker, never an
--   error.
--   Account options: npcMarkers (off until turned on), npcMarkersMobs, npcMarkersPlates, npcMarkersSize (22).
--   Free while off (YR.Part): nothing listens, nothing is made; RestedXP's step functions are hooked the first
--   time this is on, and do nothing while it is off.
local _, YR = ...

local TALK, OFFER, HANDIN, MOB = 132053, 132049, 132048, 131013    -- GossipGossipIcon, AvailableQuestIcon, ActiveQuestIcon, Cursor\Attack
local RANK = { [TALK] = 1, [OFFER] = 2, [HANDIN] = 3 }
local CVAR = "nameplateShowFriendlyNpcs"
local OBJECTIVE = 8                         -- Enum.TooltipDataLineType.QuestObjective

local function On() return YR.QoLOn() and YR.Option("npcMarkers") end
local function Flag(key) return YippRouteDB[key] ~= false end
local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

--- The icons' size, as set.
function YR.NpcMarkerSize() return math.max(14, math.min(40, tonumber(YippRouteDB.npcMarkersSize) or 22)) end

-- ---------------------------------------------------------------------------
-- Who: the active steps' .target and .mob lines
-- ---------------------------------------------------------------------------
local talkName, talkId, mobName, mobId = {}, {}, {}, {}

-- A guide's name for a unit: "Name", "Name::123", "123", maybe with RestedXP's "*" or "+" in front.
local function Entry(raw)
    if type(raw) ~= "string" then return nil end
    raw = raw:gsub("^[%*%+]+", "")
    local name, id = raw:match("^(.-)::(%d+)$")
    if id then return name ~= "" and name or nil, tonumber(id) end
    if raw:match("^%d+$") then return nil, tonumber(raw) end
    return raw ~= "" and raw or nil, nil
end

local function Add(names, ids, raw, value, rxp)
    local name, id = Entry(raw)
    if name and type(rxp.GetCreatureName) == "function" then
        local ok, local_ = pcall(rxp.GetCreatureName, name)          -- (its name in the client's language)
        if ok and type(local_) == "string" then name = local_ end
    end
    local function Put(t, k)
        if k ~= nil and (t[k] == nil or (RANK[value] or 0) > (RANK[t[k]] or 0)) then t[k] = value end
    end
    Put(names, name)
    Put(ids, id)
end

-- "?" while the step has a quest to hand in, "!" while it has one to take, else the speech bubble.
local function StepIcon(step)
    local take = false
    for _, e in ipairs(step.elements) do
        if type(e) == "table" and not e.completed and not e.skip then
            if e.tag == "turnin" then return HANDIN end
            if e.tag == "accept" then take = true end
        end
    end
    return take and OFFER or TALK
end

local function ReadSteps()
    wipe(talkName) wipe(talkId) wipe(mobName) wipe(mobId)
    local rxp = _G.RXP
    local frame = type(rxp) == "table" and rxp.RXPFrame
    local steps = type(frame) == "table" and frame.activeSteps
    if type(steps) ~= "table" then return end
    for _, step in pairs(steps) do
        if type(step) == "table" and type(step.elements) == "table" then
            local icon
            for _, e in ipairs(step.elements) do
                if type(e) == "table" then
                    if type(e.targets) == "table" then
                        icon = icon or StepIcon(step)
                        for _, raw in ipairs(e.targets) do Add(talkName, talkId, raw, icon, rxp) end
                    end
                    if type(e.mobs) == "table" then
                        for _, raw in ipairs(e.mobs) do Add(mobName, mobId, raw, MOB, rxp) end
                    end
                end
            end
        end
    end
end
YR.NpcMarkersRead = ReadSteps

-- ---------------------------------------------------------------------------
-- Which icon a unit gets
-- ---------------------------------------------------------------------------
local function Ask(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    return Plain(v)
end

-- (an NPC's id is the sixth part of its GUID: Creature-0-1-2-3-<id>-<spawn>)
local function NpcId(unit)
    local guid = Ask(UnitGUID, unit)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

-- Whether the game's own tooltip for the unit has a quest objective of yours not yet done.
local function Objective(unit)
    local tip = C_TooltipInfo
    local data = tip and Ask(tip.GetUnit, unit)
    local lines = type(data) == "table" and Plain(data.lines)
    if type(lines) ~= "table" then return false end
    for _, line in ipairs(lines) do
        if type(line) == "table" and Plain(line.type) == OBJECTIVE then
            local done = line.completed
            if issecretvalue and issecretvalue(done) then return false end
            if done ~= true then return true end
        end
    end
    return false
end

local function Want(unit)
    if Ask(UnitIsPlayer, unit) ~= false then return nil end         -- (a player, or not known: none)
    local name, id = Ask(UnitName, unit), NpcId(unit)
    local icon = (id and talkId[id]) or (name and talkName[name])
    if icon then return icon end
    if not Flag("npcMarkersMobs") or Ask(UnitCanAttack, "player", unit) ~= true or Ask(UnitIsDead, unit) == true then
        return nil
    end
    if (id and mobId[id]) or (name and mobName[name]) or Objective(unit) then return MOB end
    return nil
end
YR.NpcMarkerWant = Want

-- ---------------------------------------------------------------------------
-- The icons, on the plates
-- ---------------------------------------------------------------------------
local units = {}                                -- the unit of every plate on screen
local marked = {}                               -- unit -> the plate its icon is on
local icons = setmetatable({}, { __mode = "k" }) -- plate -> our icon on it (made once per plate)

local function PlateOf(unit)
    local np = C_NamePlate
    return np and Ask(np.GetNamePlateForUnit, unit) or nil
end

local function Shown(f) return type(f) == "table" and type(f.IsShown) == "function" and Ask(f.IsShown, f) == true end

-- The frame that draws the plate (another addon's, where one replaced Blizzard's), and its health bar if shown.
local function Parts(plate)
    local frame = (Shown(plate.unitFrame) and plate.unitFrame) or (Shown(plate.kui) and plate.kui)
        or (Shown(plate.UnitFrame) and plate.UnitFrame) or plate
    local box = frame.HealthBarsContainer
    local bar = frame.healthBar or frame.Health or frame.HealthBar or (type(box) == "table" and box.healthBar)
    return frame, Shown(bar) and bar or nil
end

local function Hide(plate)
    local f = plate and icons[plate]
    if f then f:Hide() end
end

local function Put(plate, icon)
    local f = icons[plate]
    if not f then
        f = CreateFrame("Frame", nil, plate)
        f:EnableMouse(false)
        f.tex = f:CreateTexture(nil, "OVERLAY")
        f.tex:SetAllPoints()
        icons[plate] = f
    end
    local ok = pcall(function()
        local frame, bar = Parts(plate)
        local size = YR.NpcMarkerSize()
        f:SetSize(size, size)
        f:ClearAllPoints()
        if bar then
            f:SetPoint("RIGHT", bar, "LEFT", -3, 0)
        elseif Shown(frame.name) then
            f:SetPoint("BOTTOM", frame.name, "TOP", 0, 2)
        else
            f:SetPoint("BOTTOM", frame, "TOP", 0, 2)
        end
        local level = Plain(frame:GetFrameLevel())
        f:SetFrameLevel((level or 1) + 10)
    end)
    if not ok then f:Hide() return end
    f.icon = icon
    f.tex:SetTexture(icon)
    f:Show()
end

local function Mark(unit)
    local plate = PlateOf(unit)
    local was = marked[unit]
    if was and was ~= plate then Hide(was) end
    marked[unit] = nil
    if not plate then return end
    local icon = Want(unit)
    if icon then
        Put(plate, icon)
        marked[unit] = plate
    else
        Hide(plate)
    end
end

local function MarkAll()
    for unit in pairs(units) do Mark(unit) end
end
YR.NpcMarkersMarkAll = MarkAll

local function Clear()
    for unit, plate in pairs(marked) do
        Hide(plate)
        marked[unit] = nil
    end
end

-- The plates already on screen, as this comes on.
local function Gather()
    wipe(units)
    local np = C_NamePlate
    local list = np and Ask(np.GetNamePlates)
    if type(list) ~= "table" then return end
    for _, plate in ipairs(list) do
        local unit = type(plate) == "table" and Plain(plate.namePlateUnitToken)
        if type(unit) == "string" then units[unit] = true end
    end
end

-- Steps, quests and plates change in bursts: looked at once, a moment after.
local live, soon, stepsStale = false, false, false
local function Soon(steps)
    if steps then stepsStale = true end
    if soon then return end
    soon = true
    C_Timer.After(0.2, function()
        soon = false
        if not live then return end
        if stepsStale then
            stepsStale = false
            ReadSteps()
        end
        MarkAll()
    end)
end

-- RestedXP moves to a step, or ticks off a line of one, in these two (hooked once, the first time this is on).
local hooked = false
local function Hook()
    local rxp = _G.RXP
    if hooked or type(rxp) ~= "table" then return end
    for _, name in ipairs({ "SetStep", "UpdateStepCompletion" }) do
        if type(rxp[name]) == "function" then
            hooksecurefunc(rxp, name, function() if live then Soon(true) end end)
            hooked = true
        end
    end
end

-- ---------------------------------------------------------------------------
-- The game's setting for friendly NPC plates: written down, then put back
-- ---------------------------------------------------------------------------
local writing = false            -- our own writes, which CVAR_UPDATE reports too
local function Get()
    if not C_CVar then return nil end
    local ok, v = pcall(C_CVar.GetCVar, CVAR)
    return ok and v or nil
end
local function Write(value)
    writing = true
    local ok = pcall(C_CVar.SetCVar, CVAR, value)
    writing = false
    return ok
end

local PlatesBack
-- In a fight the game won't change it: done as the fight ends (a listener of its own, made the first time one
-- is needed, so it still comes when this has gone off).
local waiter
local function Wait()
    waiter = waiter or CreateFrame("Frame")
    waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
    waiter:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if live and Flag("npcMarkersPlates") then YR.NpcMarkersPlates() else PlatesBack() end
    end)
end

--- Friendly NPC plates on, while this is (what the game had is written down first).
function YR.NpcMarkersPlates()
    if not (C_CVar and live and Flag("npcMarkersPlates")) then return end
    local now = Get()
    if now == nil or now == "1" then return end
    if InCombatLockdown() then Wait() return end
    if YippRouteDB.npcMarkersWas == nil then YippRouteDB.npcMarkersWas = now end
    Write("1")
end

--- The game's setting put back as it was before this changed it.
function PlatesBack()
    local was = YippRouteDB.npcMarkersWas
    if was == nil or not C_CVar then return end
    if InCombatLockdown() then Wait() return end
    if Get() ~= was then Write(was) end
    YippRouteDB.npcMarkersWas = nil
end
YR.NpcMarkersPlatesBack = PlatesBack

YR.Part(On, { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD",
    "CVAR_UPDATE", "PLAYER_LOGOUT" }, function(_, event, arg, value)
    if event == "NAME_PLATE_UNIT_ADDED" then
        if type(arg) ~= "string" then return end
        units[arg] = true
        Mark(arg)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if type(arg) ~= "string" then return end
        units[arg] = nil
        Hide(marked[arg])
        marked[arg] = nil
    elseif event == "QUEST_LOG_UPDATE" then
        Soon(true)
    elseif event == "PLAYER_ENTERING_WORLD" then
        YR.NpcMarkersPlates()
        Gather()
        Soon(true)
    elseif event == "CVAR_UPDATE" then
        -- changed by you while this holds it: yours stands (turned off, the switch for it goes off too)
        if writing or type(arg) ~= "string" or arg:lower() ~= CVAR:lower() or YippRouteDB.npcMarkersWas == nil then return end
        YippRouteDB.npcMarkersWas = nil
        if value ~= nil and tostring(value) == "0" then YippRouteDB.npcMarkersPlates = false end
    elseif event == "PLAYER_LOGOUT" then
        -- (put back before the game saves it, made again at the next login: removed, Headstart leaves yours)
        PlatesBack()
    end
end, {
    start = function()
        live = true
        Hook()
        YR.NpcMarkersPlates()
        ReadSteps()
        Gather()
        MarkAll()
    end,
    stop = function()
        live = false
        Clear()
        wipe(units)
        PlatesBack()
    end,
    again = function()                  -- still on, and a setting changed (the plates' switch, the size, mobs)
        if Flag("npcMarkersPlates") then YR.NpcMarkersPlates() else PlatesBack() end
        MarkAll()
    end,
})
