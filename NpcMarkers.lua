-- Quest mob markers (NpcMarkers.lua): a sword on the nameplate of an enemy you still need for a quest - one to
-- kill, or one that drops what a quest wants: the game's own quest objective lines on the unit (in its tooltip
-- data) not yet done, and the .mob lines of the RestedXP steps you're on. Only enemies, alive.
--   It marked the NPC a step says to talk to as well ("!", "?", a speech bubble), and could turn the game's
--   friendly NPC plates on for it; the game shows a quest giver's "!" and "?" itself (the owner, 2026-10-20:
--   "nameplate quest objectives only need to be for enemies to kill or loot, not quest givers"). Friendly plates
--   it turned on are put back as they were (written down then: npcMarkersWas), in a fight as it ends.
--   The icon stands beside the plate's health bar where it shows one, else over its name (Blizzard's plates and
--   other addons' differ: Plater and ElvUI keep theirs in plate.unitFrame, Kui in plate.kui).
--   Questie draws its own quest icons on enemies' plates (Questie.db.profile.nameplateEnabled, on unless turned
--   off): while it does, none of ours, so nobody with both sees two.
--   Secret values (Forever can hand out a unit's GUID, name or tooltip as secret in combat): no marker, never an
--   error.
--   Account options: npcMarkers (off until turned on).
--   Free while off (YR.Part): nothing listens, nothing is made; RestedXP's step functions are hooked the first
--   time this is on, and do nothing while it is off.
local _, YR = ...

local MOB = 131013                          -- Cursor\Attack
local CVAR = "nameplateShowFriendlyNpcs"    -- (the game's friendly NPC plates: put back where this turned them on)
local OBJECTIVE = 8                         -- Enum.TooltipDataLineType.QuestObjective

local function On() return YR.QoLOn() and YR.Option("npcMarkers") end
local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

--- The icons' size, as set.
function YR.NpcMarkerSize() return 22 end

-- ---------------------------------------------------------------------------
-- Who: the active steps' .mob lines
-- ---------------------------------------------------------------------------
local mobName, mobId = {}, {}

-- A guide's name for a unit: "Name", "Name::123", "123", maybe with RestedXP's "*" or "+" in front.
local function Entry(raw)
    if type(raw) ~= "string" then return nil end
    raw = raw:gsub("^[%*%+]+", "")
    local name, id = raw:match("^(.-)::(%d+)$")
    if id then return name ~= "" and name or nil, tonumber(id) end
    if raw:match("^%d+$") then return nil, tonumber(raw) end
    return raw ~= "" and raw or nil, nil
end

local function Add(raw, rxp)
    local name, id = Entry(raw)
    if name and type(rxp.GetCreatureName) == "function" then
        local ok, local_ = pcall(rxp.GetCreatureName, name)          -- (its name in the client's language)
        if ok and type(local_) == "string" then name = local_ end
    end
    if name ~= nil then mobName[name] = true end
    if id ~= nil then mobId[id] = true end
end

local function ReadSteps()
    wipe(mobName) wipe(mobId)
    local rxp = _G.RXP
    local frame = type(rxp) == "table" and rxp.RXPFrame
    local steps = type(frame) == "table" and frame.activeSteps
    if type(steps) ~= "table" then return end
    for _, step in pairs(steps) do
        if type(step) == "table" and type(step.elements) == "table" then
            for _, e in ipairs(step.elements) do
                if type(e) == "table" and type(e.mobs) == "table" then
                    for _, raw in ipairs(e.mobs) do Add(raw, rxp) end
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

-- Whether the game's own tooltip for the unit has a quest objective of yours not yet done. Read once per kind of mob
-- (its NPC id) until your quest log changes: every plate of a pack, and every look again, had the tooltip built anew.
local objective = {}                            -- [npc id] = true / false
local function Objective(unit, id)
    if id and objective[id] ~= nil then return objective[id] end
    local found = false
    local tip = C_TooltipInfo
    local data = tip and Ask(tip.GetUnit, unit)
    local lines = type(data) == "table" and Plain(data.lines)
    if type(lines) ~= "table" then return false end         -- (no answer: asked again next time)
    for _, line in ipairs(lines) do
        if type(line) == "table" then
            -- a line the game keeps secret (in a fight): not known - no sword now, and not kept, so it is asked again
            -- (the review, 2026-10-21: kept as "no", a mob first seen in a fight stayed bare until the quest log changed)
            local kind, done = line.type, line.completed
            if issecretvalue and issecretvalue(kind) then return false end
            if kind == OBJECTIVE then
                if issecretvalue and issecretvalue(done) then return false end
                if done ~= true then found = true break end
            end
        end
    end
    if id then objective[id] = found end
    return found
end

-- Whether Questie is drawing its own quest icons on nameplates now (its settings: Questie.db.profile, AceDB's).
local function QuestieDraws()
    local questie = _G.Questie
    local db = type(questie) == "table" and questie.db
    local p = type(db) == "table" and db.profile
    return type(p) == "table" and p.nameplateEnabled ~= false
end

local function Want(unit)
    if Ask(UnitIsPlayer, unit) ~= false then return nil end         -- (a player, or not known: none)
    if Ask(UnitCanAttack, "player", unit) ~= true or Ask(UnitIsDead, unit) == true then return nil end
    if QuestieDraws() then return nil end
    local name, id = Ask(UnitName, unit), NpcId(unit)
    if (id and mobId[id]) or (name and mobName[name]) or Objective(unit, id) then return MOB end
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

-- The icon by the plate's health bar (or over its name, or the plate): placed again only where that has changed - the
-- plate's parts, the size - and not at every look.
local function Place(f, plate)
    local frame, bar = Parts(plate)
    local size = YR.NpcMarkerSize()
    local at = bar or (Shown(frame.name) and frame.name) or frame
    if f.at == at and f.size == size then return end
    f.at, f.size = at, size
    f:SetSize(size, size)
    f:ClearAllPoints()
    if at == bar then f:SetPoint("RIGHT", bar, "LEFT", -3, 0) else f:SetPoint("BOTTOM", at, "TOP", 0, 2) end
    local level = Plain(frame:GetFrameLevel())
    f:SetFrameLevel((level or 1) + 10)
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
    if not pcall(Place, f, plate) then
        f.at = nil
        f:Hide()
        return
    end
    if f.icon ~= icon then
        f.icon = icon
        f.tex:SetTexture(icon)
    end
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
-- The game's setting for friendly NPC plates, where this turned them on (it no longer does): put back
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
        PlatesBack()
    end)
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
        -- (what each kind of mob's tooltip says is read again; the route's steps are RestedXP's to change, and
        -- its own update - hooked above - says so)
        wipe(objective)
        Soon(false)
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(objective)
        Gather()
        Soon(true)
    elseif event == "CVAR_UPDATE" then
        -- changed by you before it was put back: yours stands
        if writing or type(arg) ~= "string" or arg:lower() ~= CVAR:lower() or YippRouteDB.npcMarkersWas == nil then return end
        YippRouteDB.npcMarkersWas = nil
    elseif event == "PLAYER_LOGOUT" then
        -- (put back before the game saves it, made again at the next login: removed, Headstart leaves yours)
        PlatesBack()
    end
end, {
    start = function()
        live = true
        -- (what was read before it was turned off: the quest log changed unheard since)
        wipe(objective)
        Hook()
        PlatesBack()
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
    again = function()                  -- still on, and a setting changed (the size)
        MarkAll()
    end,
})
