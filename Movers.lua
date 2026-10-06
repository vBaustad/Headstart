-- Blizzard windows moved: the talent window (TalentFade.lua asks for that one), and - opt-in - the
-- combined bag and the reagent bag. Drag a window by its title bar; it opens where you left it.
--   Blizzard puts these windows in their place every time they open (and the bags again whenever one
--   opens or closes). We don't stop that: after each of Blizzard's SetPoint we put the window back
--   where you left it. Out of combat only, and nothing is touched on a window until its option is on.
--   The drag is on our own strip laid over the title bar, clear of the portrait and the close button.
--   A window can also be dragged by its own empty parts (the talent window is): those frames are
--   registered for a drag and hooked, nothing of theirs replaced. Buttons and talents are frames of
--   their own on top, so a click or a drag on one of them is still theirs.
--   Account options (YippRouteDB, Headstart, QoL, Bars & windows): moveBag, moveReagentBag (both off unless
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
        -- the first time it's on and the window exists: the strip to drag by, and the hooks. Not in a
        -- fight: the talent window is protected there, and making it movable would be blocked (the
        -- window can first exist in a fight - its addon loads when you press the key). The end of
        -- the fight comes back here.
        if InCombatLockdown() then return end
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        local h = CreateFrame("Frame", nil, frame)
        h:SetPoint("TOPLEFT", m.left, 0)
        h:SetPoint("TOPRIGHT", -m.right, 0)
        h:SetHeight(22)
        h:SetFrameLevel(frame:GetFrameLevel() + 600)
        h:EnableMouse(true)
        h:RegisterForDrag("LeftButton")
        local function Start()
            if m.on() and not InCombatLockdown() then
                m.moving = true
                frame:StartMoving()
            end
        end
        local function Stop()
            -- a fight that began mid-drag ended the drag itself (StartMovers, PLAYER_REGEN_DISABLED)
            if not m.moving then return end
            m.moving = nil
            if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then return end
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
        m.handle, m.stop = h, Stop
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
-- ---------------------------------------------------------------------------
-- Window sizes: the social window and the group finder smaller or larger (Settings only: nothing is
-- added to the windows themselves). A window is sized when it shows, out of combat; 100 leaves it
-- as Blizzard has it, and a window is only ever touched once you've set a size for it.
--   Account options (YippRouteDB.windowScale): social, lfg = percent (50-150).
-- ---------------------------------------------------------------------------
local SIZED = {
    social = function() return _G.SocialUIFrame end,
    lfg = function() return _G.LFGParentFrame end,
}
local sizeHooked, sizeSet = {}, {}

function YR.WindowScale(key)
    local v = type(YippRouteDB.windowScale) == "table" and tonumber(YippRouteDB.windowScale[key])
    return v and math.max(50, math.min(150, v)) or 100
end

local function Size(key)
    local frame = SIZED[key] and SIZED[key]()
    if type(frame) ~= "table" or not frame.SetScale then return false end
    if not sizeHooked[key] and frame.HookScript then
        sizeHooked[key] = true
        frame:HookScript("OnShow", function() Size(key) end)
    end
    local want = YR.QoLOn() and YR.WindowScale(key) / 100 or 1
    if want == 1 and not sizeSet[key] then return true end          -- never asked for: never touched
    if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then return true end
    if math.abs((frame:GetScale() or 1) - want) > 0.001 then frame:SetScale(want) end
    sizeSet[key] = want ~= 1 or nil
    return true
end

function YR.SetWindowScale(key, percent)
    if not SIZED[key] then return end
    YippRouteDB.windowScale = type(YippRouteDB.windowScale) == "table" and YippRouteDB.windowScale or {}
    percent = math.max(50, math.min(150, math.floor((tonumber(percent) or 100) + 0.5)))
    YippRouteDB.windowScale[key] = percent ~= 100 and percent or nil
    sizeSet[key] = sizeSet[key] or true          -- back to 100 puts Blizzard's size on again
    Size(key)
end

--- Every sized window as its setting says (login, the end of a fight, the main switch).
function YR.WindowScaleApply()
    for key in pairs(SIZED) do Size(key) end
end

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
    f:RegisterEvent("ADDON_LOADED")          -- the social window and the group finder load when first opened
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            -- a fight begins with a window on the cursor: let go of it now, while that's still allowed
            -- (this comes just before the lockdown), or it would stay on the cursor through the fight
            for _, m in pairs(movers) do if m.moving and m.stop then m.stop() end end
            return
        end
        if event == "ADDON_LOADED" then
            local all = true
            for key in pairs(SIZED) do if not Size(key) then all = false end end
            if all then self:UnregisterEvent("ADDON_LOADED") end
            return
        end
        for key in pairs(movers) do YR.MoverPlace(key) end
        YR.WindowScaleApply()
    end)
end
