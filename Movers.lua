-- Blizzard windows moved: the talent window (TalentFade.lua asks for that one), and - opt-in - the
-- combined bag and the reagent bag. Drag a window by its title bar; it opens where you left it.
--   Blizzard puts these windows in their place every time they open (and the bags again whenever one
--   opens or closes). We don't stop that: after each of Blizzard's SetPoint we put the window back
--   where you left it. Out of combat only, and nothing is touched on a window until its option is on.
--   The drag is on our own strip laid over the title bar, clear of the portrait and the close button.
--   A window can also be dragged by its own empty parts (the talent window is): those frames are
--   registered for a drag and hooked, nothing of theirs replaced. Buttons and talents are frames of
--   their own on top, so a click or a drag on one of them is still theirs.
--   Account options (YippRouteDB, Headstart, QoL, Windows): moveBag, moveReagentBag (both off unless
--   turned on); moved[key] = { left, top } is where each was left.
local ADDON, YR = ...

local movers = {}

local function Saved() YippRouteDB.moved = YippRouteDB.moved or {} return YippRouteDB.moved end

local function Place(m)
    local frame = m.frame()
    if m.placing then return end        -- our own SetPoint, come back through the hook
    local on = m.on()
    if m.handle then m.handle:SetShown(on) end
    if not frame or not on then return end
    if not m.handle then
        -- the first time it's on and the window exists: the strip to drag by, and the hooks
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        local h = CreateFrame("Frame", nil, frame)
        h:SetPoint("TOPLEFT", m.left, 0)
        h:SetPoint("TOPRIGHT", -m.right, 0)
        h:SetHeight(22)
        h:SetFrameLevel(frame:GetFrameLevel() + 600)
        h:EnableMouse(true)
        h:RegisterForDrag("LeftButton")
        local function Start() if m.on() and not InCombatLockdown() then frame:StartMoving() end end
        local function Stop()
            frame:StopMovingOrSizing()
            -- a moved frame is "user placed": the client would save where it is and put it there itself
            -- at the next login, before Blizzard or we do. Where it goes is ours to keep, not the client's.
            if frame.SetUserPlaced then frame:SetUserPlaced(false) end
            -- kept in the screen's measure, not the window's own: a window at another size (the
            -- talent window can be) still opens with its corner where you left it
            local left, top, scale = frame:GetLeft(), frame:GetTop(), frame:GetScale() or 1
            if m.on() and left and top then
                Saved()[m.key] = { math.floor(left * scale + 0.5), math.floor(top * scale + 0.5) }
            end
        end
        h:SetScript("OnDragStart", Start)
        h:SetScript("OnDragStop", Stop)
        m.handle = h
        for _, part in pairs(m.parts and m.parts(frame) or {}) do
            if type(part) == "table" and part.RegisterForDrag and part.HookScript then
                part:RegisterForDrag("LeftButton")
                part:HookScript("OnDragStart", Start)
                part:HookScript("OnDragStop", Stop)
            end
        end
        hooksecurefunc(frame, "SetPoint", function() Place(m) end)
        frame:HookScript("OnShow", function() Place(m) end)
    end
    local pos = Saved()[m.key]
    if m.placing or not pos or InCombatLockdown() then return end
    m.placing = true
    frame:ClearAllPoints()
    local scale = frame:GetScale() or 1
    if scale <= 0 then scale = 1 end
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1] / scale, pos[2] / scale)
    m.placing = false
end

--- A window that can be moved: frame() gives it (nil while it doesn't exist yet), on() says whether
--- its option is on, left and right keep the strip clear of what's in the title bar's corners,
--- back() has Blizzard put it in its own place again, and parts(frame) lists the window's own frames
--- it can be dragged by as well (its empty parts).
function YR.Mover(key, frame, on, left, right, back, parts)
    movers[key] = { key = key, frame = frame, on = on, left = left or 60, right = right or 30, back = back, parts = parts }
    return movers[key]
end

--- Put where you left it (after an option changed, or when the window first exists).
function YR.MoverPlace(key)
    if movers[key] then Place(movers[key]) end
end

--- Where a window is to open, in the screen's measure (the talent window's size change sets it).
function YR.MoverSet(key, left, top)
    Saved()[key] = { math.floor(left + 0.5), math.floor(top + 0.5) }
    YR.MoverPlace(key)
end

--- Forgotten: Blizzard's own place again.
function YR.MoverReset(key)
    Saved()[key] = nil
    local m = movers[key]
    local frame = m and m.frame()
    if frame and frame:IsShown() and not InCombatLockdown() and m.back then m.back(frame) end
end

-- The bags have no back(): after a reset Blizzard puts them in its own place the next time they open.
function YR.StartMovers()
    YR.Mover("bag", function() return _G.ContainerFrameCombinedBags end,
        function() return YippRouteDB.moveBag == true and YR.QoLOn() end, 50, 30)
    YR.Mover("reagentBag", function() return _G.ContainerFrame6 end,
        function() return YippRouteDB.moveReagentBag == true and YR.QoLOn() end, 50, 30)
    -- A window opened in a fight is left where Blizzard put it; when the fight ends every window of
    -- ours is put where you left it.
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function()
        for key in pairs(movers) do YR.MoverPlace(key) end
    end)
end
