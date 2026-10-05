-- Death skips: when a RestedXP step you are on says to die (".deathskip"), release your spirit at once.
-- RestedXP itself picks the Spirit Healer's option and confirms the resurrection on such a step, so a
-- planned death is: die, (released), click the Spirit Healer (and Headstart accepts there too, below,
-- when RestedXP's step has already gone). Any other death is left alone, so an
-- unplanned one can still be a corpse run. Account option deathSkipRelease (Settings, Route).
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

local function AcceptAtHealer()
    if C_PlayerInteractionManager and Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.SpiritHealer then
        C_Timer.After(0, function()
            C_PlayerInteractionManager.ConfirmationInteraction(Enum.PlayerInteractionType.SpiritHealer)
            C_PlayerInteractionManager.ClearInteraction(Enum.PlayerInteractionType.SpiritHealer)
        end)
    elseif AcceptXPLoss then
        AcceptXPLoss()      -- the game closes its own popup as you come alive: hiding it from here would taint it
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("PLAYER_UNGHOST")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("CONFIRM_XP_LOSS")
frame:RegisterEvent("GOSSIP_SHOW")
if C_PlayerInteractionManager then frame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW") end
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_DEAD" then
        planned = YR.RoutesOn() and YR.OnDeathSkip()
        if not planned or not YR.Option("deathSkipRelease") then return end
        -- a moment for the death popup to appear first, so releasing also closes it
        C_Timer.After(0.3, function()
            if UnitIsDead("player") and not UnitIsGhost("player") then RepopMe() end
        end)
    elseif event == "PLAYER_UNGHOST" or (event == "PLAYER_ALIVE" and not UnitIsGhost("player")) then
        planned = false
    elseif planned and UnitIsGhost("player") then
        local types = Enum and Enum.PlayerInteractionType
        if event == "CONFIRM_XP_LOSS" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and types and arg1 == types.SpiritHealer) then
            planned = false
            AcceptAtHealer()
        elseif (event == "GOSSIP_SHOW" or (event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" and types and arg1 == types.Gossip))
                and type(RXP) == "table" and type(RXP.SelectGossipType) == "function" then
            RXP.SelectGossipType("healer")          -- RestedXP's own pick of the healer's option
        end
    end
end)
