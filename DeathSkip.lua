-- Death skips: when a RestedXP step you are on says to die (".deathskip"), release your spirit at once.
-- RestedXP itself picks the Spirit Healer's option and confirms the resurrection on such a step, so a
-- planned death is: die, (released), click the Spirit Healer. Any other death is left alone, so an
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

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_DEAD")
frame:SetScript("OnEvent", function()
    if not YR.RoutesOn() or not YR.Option("deathSkipRelease") or not YR.OnDeathSkip() then return end
    -- a moment for the death popup to appear first, so releasing also closes it
    C_Timer.After(0.3, function()
        if UnitIsDead("player") and not UnitIsGhost("player") then RepopMe() end
    end)
end)
