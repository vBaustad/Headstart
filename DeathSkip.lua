-- Death skips: when a RestedXP step you are on says to die (".deathskip"), release your spirit at once.
-- RestedXP itself picks the Spirit Healer's option and confirms the resurrection on such a step, so a
-- planned death is: die, (released), click the Spirit Healer (and Headstart accepts there too, below,
-- when RestedXP's step has already gone). Any other death is left alone, so an
-- unplanned one can still be a corpse run. Account option deathSkipRelease (Settings, Route): off, or
-- with the routes off, none of this listens to anything.
local _, YR = ...

-- Is a death skip on one of the steps RestedXP shows right now?
function YR.OnDeathSkip()
    local rxp = RXP
    local guide = type(rxp) == "table" and type(rxp.currentGuide) == "table" and rxp.currentGuide
    if not guide or type(guide.steps) ~= "table" then return false end
    for _, step in ipairs(guide.steps) do
        if type(step) == "table" and step.active and not step.completed and type(step.elements) == "table" then
            for _, element in ipairs(step.elements) do
                if type(element) == "table" and element.tag == "deathskip" and not element.completed then
                    return true
                end
            end
        end
    end
    return false
end

-- The Spirit Healer: RestedXP accepts the resurrection only while its death-skip step is the active
-- one, and several end themselves before you reach him (".subzoneskip" Kharanos: the healer stands in
-- Kharanos), so it sometimes didn't (the user, 2026-10-04). A death that was a death skip (released
-- here, on such a step) is remembered until you are alive again, and at the healer Headstart picks his
-- option and accepts, whatever step RestedXP is on by then. Any other death is left alone.
local planned = false

-- Nothing of this exists with the routes or the option off, and with them on only your death is
-- listened for: the healer's window and coming back to life matter only while a death skip is under
-- way, so those are listened for from such a death until it is over.
local part
local AFTER = { "PLAYER_UNGHOST", "PLAYER_ALIVE", "CONFIRM_XP_LOSS", "GOSSIP_SHOW" }
if C_PlayerInteractionManager then AFTER[#AFTER + 1] = "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" end

local function Plan(on)
    on = on and true or false
    if on == planned then return end
    planned = on
    local frame = part and part.frame
    if not frame then return end
    for _, e in ipairs(AFTER) do
        if on then frame:RegisterEvent(e) else frame:UnregisterEvent(e) end
    end
end

local function Confirm()
    C_PlayerInteractionManager.ConfirmationInteraction(Enum.PlayerInteractionType.SpiritHealer)
    C_PlayerInteractionManager.ClearInteraction(Enum.PlayerInteractionType.SpiritHealer)
end

local function AcceptAtHealer()
    if C_PlayerInteractionManager and Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.SpiritHealer then
        C_Timer.After(0, Confirm)
    elseif AcceptXPLoss then
        AcceptXPLoss()      -- the game closes its own popup as you come alive: hiding it from here would taint it
    end
end

local function Release()
    if UnitIsDead("player") and not UnitIsGhost("player") then RepopMe() end
end

local function OnEvent(_, event, arg1)
    if event == "PLAYER_DEAD" then
        Plan(YR.RoutesOn() and YR.Option("deathSkipRelease") and YR.OnDeathSkip())
        -- a moment for the death popup to appear first, so releasing also closes it
        if planned then C_Timer.After(0.3, Release) end
    elseif event == "PLAYER_UNGHOST" or (event == "PLAYER_ALIVE" and not UnitIsGhost("player")) then
        Plan(false)
    elseif planned and UnitIsGhost("player") then
        local types = Enum and Enum.PlayerInteractionType
        if event == "CONFIRM_XP_LOSS" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and types and arg1 == types.SpiritHealer) then
            Plan(false)
            AcceptAtHealer()
        elseif (event == "GOSSIP_SHOW" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and types and arg1 == types.Gossip))
                and type(RXP) == "table" and type(RXP.SelectGossipType) == "function" then
            RXP.SelectGossipType("healer")          -- RestedXP's own pick of the healer's option
        end
    end
end

part = YR.Part(function() return YR.RoutesOn() and YR.Option("deathSkipRelease") end, { "PLAYER_DEAD" }, OnEvent,
    { stop = function() planned = false end })      -- (its events are taken off with the part)
