-- Flight timer: a bar from take-off to landing, with where from, where to and the time left.
-- The game doesn't say how long a flight takes, so each one is timed and remembered (account-wide, in
-- YippRouteDB.flights["From>To"] = seconds). A flight not timed yet takes RestedXP's time for it (its
-- Forever flight data, worked out in its own TakeTaxiNode hook, which runs before ours), else an
-- estimate: its length on the flight map (the hops it flies over) times the seconds per unit of length
-- the timed flights on that map averaged (YippRouteDB.flightPace[taxi map]). With none of these, the
-- bar counts up while it learns. RestedXP's own flight bar is hidden while ours shows.
-- Account option flightTimer (Settings, Route); the bar is dragged where you want it while it shows.
local _, YR = ...

local frame
local pending        -- the flight just asked for at the flight master: { from, to, key, length, map }
local flight         -- the flight under way: pending plus started (GetTime) and total (seconds or nil)

local function Short(name)
    return name and (name:match("^([^,]+)") or name) or "?"
end

-- The length of the route to node i on the flight map: the sum of its hops.
local function RouteLength(i)
    local hops = GetNumRoutes and GetNumRoutes(i) or 0
    local len = 0
    for h = 1, hops do
        local dx = (TaxiGetDestX(i, h) or 0) - (TaxiGetSrcX(i, h) or 0)
        local dy = (TaxiGetDestY(i, h) or 0) - (TaxiGetSrcY(i, h) or 0)
        len = len + math.sqrt(dx * dx + dy * dy)
    end
    return len > 0 and len or nil
end

local function Expected(f)
    local known = YippRouteDB.flights and YippRouteDB.flights[f.key]
    if known then return known, false end
    if f.rxp then return f.rxp, false end
    local pace = f.length and YippRouteDB.flightPace and YippRouteDB.flightPace[f.map or 0]
    if pace then return floor(f.length * pace[1] / pace[2] + 0.5), true end
end

local function Clock(s)
    s = math.max(0, floor(s + 0.5))
    return ("%d:%02d"):format(floor(s / 60), s % 60)
end

-- ---------------------------------------------------------------------------
-- The bar
-- ---------------------------------------------------------------------------
local function Place()
    local p = YippRouteDB.flightPos
    frame:ClearAllPoints()
    if p then
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p[1], p[2])
    else
        frame:SetPoint("TOP", 0, -180)
    end
end

local function Build()
    local S = YR.Style
    frame = CreateFrame("Frame", "HeadstartFlightFrame", UIParent)
    frame:SetSize(280, 46)
    frame:SetFrameStrata("MEDIUM")
    S.Fill(frame, S.C.window)
    S.Border(frame, S.C.line)
    frame.from = S.Text(frame, 12, S.C.sub)
    frame.from:SetPoint("TOPLEFT", 8, -7)
    frame.from:SetWidth(118)
    frame.from:SetJustifyH("LEFT")
    frame.to = S.Text(frame, 12, S.C.text)
    frame.to:SetPoint("TOPRIGHT", -8, -7)
    frame.to:SetWidth(118)
    frame.to:SetJustifyH("RIGHT")
    frame.arrow = S.Text(frame, 12, S.C.muted)
    frame.arrow:SetPoint("TOP", 0, -7)
    frame.arrow:SetText("to")
    frame.bar = CreateFrame("StatusBar", nil, frame)
    frame.bar:SetPoint("BOTTOMLEFT", 8, 8)
    frame.bar:SetPoint("BOTTOMRIGHT", -8, 8)
    frame.bar:SetHeight(16)
    frame.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local a = S.C.accent
    frame.bar:SetStatusBarColor(a[1], a[2], a[3], 0.85)
    frame.bar:SetMinMaxValues(0, 1)
    S.Fill(frame.bar, S.C.field, "BACKGROUND")
    frame.time = S.Text(frame.bar, 12, S.C.text, "OVERLAY")
    frame.time:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        YippRouteDB.flightPos = { floor(self:GetLeft() + 0.5), floor(self:GetTop() - UIParent:GetTop() + 0.5) }
    end)
    local tick = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        tick = tick + elapsed
        if tick < 0.1 then return end
        tick = 0
        YR:RefreshFlight()
    end)
    Place()
    frame:Hide()
end

function YR:RefreshFlight()
    if not (frame and flight) then return end
    -- one bar is enough: RestedXP's (it shows a moment after take-off) goes while ours is up
    local rxpBar = type(RXP) == "table" and type(RXP.flightInfo) == "table" and RXP.flightInfo.flightBar
    if type(rxpBar) == "table" and rxpBar.IsShown and rxpBar:IsShown() then rxpBar:Hide() end
    local gone = GetTime() - flight.started
    local total, guess = flight.total, flight.guess
    frame.from:SetText(Short(flight.from))
    frame.to:SetText(Short(flight.to))
    if total and total > 0 then
        frame.bar:SetValue(math.min(1, gone / total))
        local left = total - gone
        if left >= 0 then
            frame.time:SetText((guess and "about " or "") .. Clock(left))
        else
            frame.time:SetText("landing (" .. Clock(-left) .. " over)")
        end
    else
        frame.bar:SetValue(0)
        frame.time:SetText(Clock(gone) .. "  (first time: timing it)")
    end
end

local function ShowBar(on)
    if on and not frame then Build() end
    if frame then frame:SetShown(on) end
    if on then YR:RefreshFlight() end
end

-- ---------------------------------------------------------------------------
-- Take-off and landing
-- ---------------------------------------------------------------------------
local function Learn(f, seconds)
    -- the latest time counts: a new flight path learned can change the way a flight goes. A flight
    -- that went through a reload is never learned (Land), its start is only known to the second.
    if seconds < 5 then return end
    YippRouteDB.flights = YippRouteDB.flights or {}
    local known = YippRouteDB.flights[f.key]
    YippRouteDB.flights[f.key] = floor(seconds + 0.5)
    if f.length and not known then
        YippRouteDB.flightPace = YippRouteDB.flightPace or {}
        local p = YippRouteDB.flightPace[f.map or 0] or { 0, 0 }
        YippRouteDB.flightPace[f.map or 0] = { p[1] + seconds, p[2] + f.length }
    end
end

local function TakeOff()
    flight, pending = pending, nil
    flight.started = GetTime()
    flight.total, flight.guess = Expected(flight)
    -- kept over a reload mid-flight, so the bar carries on
    YippRouteDB.flightNow = { from = flight.from, to = flight.to, key = flight.key, length = flight.length,
        map = flight.map, rxp = flight.rxp, at = time() }
    if YR.Option("flightTimer") then ShowBar(true) end
end

local function Land()
    if flight and not flight.resumed then Learn(flight, GetTime() - flight.started) end
    flight = nil
    YippRouteDB.flightNow = nil
    ShowBar(false)
end

local watcher = CreateFrame("Frame")
local waited = 0
-- after the click the game takes a moment to put you on the taxi: wait for it (5 seconds at most)
local function WaitForTaxi(self, elapsed)
    waited = waited + elapsed
    if UnitOnTaxi("player") then
        self:SetScript("OnUpdate", nil)
        TakeOff()
    elseif waited > 5 then
        self:SetScript("OnUpdate", nil)
        pending = nil
    end
end

hooksecurefunc("TakeTaxiNode", function(i)
    local from
    for j = 1, NumTaxiNodes() do
        if TaxiNodeGetType(j) == "CURRENT" then from = TaxiNodeName(j) end
    end
    local to = TaxiNodeName(i)
    if not (from and to) then return end
    local info = type(RXP) == "table" and type(RXP.flightInfo) == "table" and RXP.flightInfo
    local rxp = info and info.activeIndex == i and tonumber(info.timer) or nil
    pending = { from = from, to = to, key = from .. ">" .. to, length = RouteLength(i),
        map = GetTaxiMapID and GetTaxiMapID() or 0, rxp = rxp }
    waited = 0
    watcher:SetScript("OnUpdate", WaitForTaxi)
end)

watcher:RegisterEvent("PLAYER_CONTROL_GAINED")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_CONTROL_GAINED" then
        if flight and not UnitOnTaxi("player") then Land() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local now = YippRouteDB.flightNow
        if now and UnitOnTaxi("player") and not flight then
            -- back from a reload in the air: the bar carries on from when the flight started
            flight = { from = now.from, to = now.to, key = now.key, length = now.length, map = now.map,
                rxp = now.rxp, resumed = true }
            flight.started = GetTime() - (time() - (now.at or time()))
            flight.total, flight.guess = Expected(flight)
            if YR.Option("flightTimer") then ShowBar(true) end
        elseif now and not UnitOnTaxi("player") then
            YippRouteDB.flightNow = nil
        end
    end
end)

-- The setting: off hides a bar that is showing; on shows it if you are in the air.
function YR:SetFlightTimer(on)
    YippRouteDB.flightTimer = on
    ShowBar(on and flight ~= nil)
end

-- /headstart flight: a 20-second sample bar, to drag where you want it.
function YR:PreviewFlight()
    if flight then return end
    flight = { from = "Ironforge", to = "Thelsamar, Loch Modan", key = "", started = GetTime(), total = 20 }
    ShowBar(true)
    C_Timer.After(20, function()
        if flight and flight.key == "" then flight = nil ShowBar(false) end
    end)
end
