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

local function HopLength(i, h)
    local dx = (TaxiGetDestX(i, h) or 0) - (TaxiGetSrcX(i, h) or 0)
    local dy = (TaxiGetDestY(i, h) or 0) - (TaxiGetSrcY(i, h) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

-- The length of the route to node i on the flight map: the sum of its hops.
local function RouteLength(i)
    local hops = GetNumRoutes and GetNumRoutes(i) or 0
    local len = 0
    for h = 1, hops do len = len + HopLength(i, h) end
    return len > 0 and len or nil
end

-- The flight points a flight to node i passes on the way: { name, at = share of the route's length }.
-- The game gives each hop's end as a position on the flight map; the node there is the stop.
local function Stops(i, length)
    local hops = GetNumRoutes and GetNumRoutes(i) or 0
    if hops < 2 or not length then return nil end
    local stops, run = {}, 0
    for h = 1, hops - 1 do
        run = run + HopLength(i, h)
        local x, y = TaxiGetDestX(i, h), TaxiGetDestY(i, h)
        local name
        for j = 1, NumTaxiNodes() do
            local nx, ny = TaxiNodePosition(j)
            if nx and x and math.abs(nx - x) < 0.003 and math.abs(ny - y) < 0.003 then name = TaxiNodeName(j) break end
        end
        stops[#stops + 1] = { name = name or "?", at = run / length }
    end
    return stops
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

-- The route: no panel. A slim dark bar with a round node at the start, at every flight point the
-- flight passes (its name above it when there is room) and at the end, the bar swelling into each
-- node. The fill runs along it from the left, amber at take-off turning green as you get close, with
-- a round front, and flows into each node as you pass it. Every round shape is art/circle (a circle
-- edge to edge of its image) at its real size; the bar runs between the nodes, so the see-through
-- dark never overlaps itself; positions are whole pixels. On a first flight, with no time to measure
-- against, a light runs along the bar instead.
local W, H, PAD, TRACK_Y = 380, 60, 10, -30
local THICK, NODE = 8, 16
local FAR, NEAR = { 1.00, 0.62, 0.22 }, { 0.36, 0.86, 0.46 }
local DARK = { 0.06, 0.07, 0.09, 0.82 }
local SWEEP = 1.8                     -- seconds for the light to run the bar on a first flight

local function Mix(a, b, t)
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

local function Round(x) return floor(x + 0.5) end

local function Solid(layer, sub, color)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return t
end

local function Circle(layer, sub, size, color)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    t:SetSize(size, size)
    YR.Style.ArtTexture(t, "circle")
    t:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    return t
end

-- The fill: amber at the left edge to the colour of how far you are at its right edge.
local function Shade(tex, p)
    local r, g, b = Mix(FAR, NEAR, p)
    if tex.SetGradient and CreateColor then
        tex:SetColorTexture(1, 1, 1, 1)
        tex:SetGradient("HORIZONTAL", CreateColor(FAR[1], FAR[2], FAR[3], 1), CreateColor(r, g, b, 1))
    else
        tex:SetColorTexture(r, g, b, 1)
    end
end

-- Text over the game world needs its own shadow, with no panel behind it.
local function Shadowed(fs)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    return fs
end

-- A node: its dark circle, the part of it filled (cut off at the fill's front, so the colour flows in),
-- its name, and the piece of bar from it to the next node.
local function Marker()
    local m = {}
    m.dot = Circle("BORDER", 0, NODE, DARK)
    m.fill = Circle("ARTWORK", 1, NODE, NEAR)
    m.bar = Solid("BORDER", 0, DARK)
    m.bar:SetHeight(THICK)
    m.label = Shadowed(YR.Style.Text(frame, 12, YR.Style.C.sub))
    m.label:SetJustifyH("CENTER")
    function m:At(x, nextX)
        self.x = Round(x)
        self.dot:ClearAllPoints()
        self.dot:SetPoint("CENTER", frame, "TOPLEFT", PAD + self.x, TRACK_Y)
        self.fill:ClearAllPoints()
        self.fill:SetPoint("LEFT", frame, "TOPLEFT", PAD + self.x - NODE / 2, TRACK_Y)
        self.label:ClearAllPoints()
        self.label:SetPoint("BOTTOM", frame, "TOPLEFT", PAD + self.x, TRACK_Y + NODE / 2 + 3)
        -- the bar starts and ends where the circle is as wide as the bar is thick, so it meets the
        -- circle's edge without covering it
        local inset = floor(math.sqrt((NODE / 2) ^ 2 - (THICK / 2) ^ 2))
        if nextX and Round(nextX) - self.x > 2 * inset then
            self.bar:ClearAllPoints()
            self.bar:SetPoint("LEFT", frame, "TOPLEFT", PAD + self.x + inset, TRACK_Y)
            self.bar:SetWidth(Round(nextX) - self.x - 2 * inset)
            self.bar:Show()
        else
            self.bar:Hide()
        end
    end
    -- fillX: where the fill's front is (pixels from the start), or nil for none
    function m:Fill(fillX, r, g, b)
        local part = fillX and math.max(0, math.min(1, (fillX - (self.x - NODE / 2)) / NODE)) or 0
        local w = Round(part * NODE)
        if w < 1 then self.fill:Hide() return end
        self.fill:SetWidth(w)
        self.fill:SetTexCoord(0, w / NODE, 0, 1)
        self.fill:SetVertexColor(r, g, b, 1)
        self.fill:Show()
    end
    function m:Show(on)
        self.dot:SetShown(on)
        if not on then self.label:Hide() self.fill:Hide() self.bar:Hide() end
    end
    return m
end

local function Build()
    local S = YR.Style
    frame = CreateFrame("Frame", "HeadstartFlightFrame", UIParent)
    frame:SetSize(W, H)
    frame:SetFrameStrata("MEDIUM")
    frame.len = W - 2 * PAD
    frame.from = Shadowed(S.Text(frame, 13, S.C.text))
    frame.from:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", PAD - NODE / 2, TRACK_Y + NODE / 2 + 3)
    frame.from:SetWidth(W / 3)
    frame.to = Shadowed(S.Text(frame, 13, S.C.text))
    frame.to:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -(PAD - NODE / 2), TRACK_Y + NODE / 2 + 3)
    frame.to:SetWidth(W / 3)
    frame.to:SetJustifyH("RIGHT")
    -- the fill along the bar, its round front, and the light that runs a first flight
    frame.fill = Solid("ARTWORK", 0, NEAR)
    frame.fill:SetHeight(THICK)
    frame.fill:SetPoint("LEFT", frame, "TOPLEFT", PAD, TRACK_Y)
    frame.head = Circle("ARTWORK", 2, THICK, NEAR)
    frame.sweep = Solid("ARTWORK", 0, { NEAR[1], NEAR[2], NEAR[3], 0.6 })
    frame.sweep:SetSize(36, THICK)
    frame.markers = {}
    frame.time = Shadowed(S.Text(frame, 14, S.C.text))
    frame.time:SetPoint("TOP", frame, "TOPLEFT", W / 2 - 20, TRACK_Y - NODE / 2 - 4)
    frame.note = Shadowed(S.Text(frame, 12, S.C.sub))
    frame.note:SetPoint("LEFT", frame.time, "RIGHT", 6, -1)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        YippRouteDB.flightPos = { floor(self:GetLeft() + 0.5), floor(self:GetTop() - UIParent:GetTop() + 0.5) }
    end)
    -- the fill moves every frame; the words change ten times a second
    local tick = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        YR:AnimateFlight()
        tick = tick + elapsed
        if tick < 0.1 then return end
        tick = 0
        YR:RefreshFlight()
    end)
    Place()
    frame:Hide()
end

-- How far along: 0 to 1, or nil while a first flight is being timed.
local function Progress()
    local total = flight.total
    if not (total and total > 0) then return nil end
    return math.min(1, (GetTime() - flight.started) / total)
end

-- The nodes for this flight: the start, each stop on the way (at its share of the route's length)
-- and the end, each with the bar to the next. Names over the stops only where they don't crowd the
-- ends or each other.
local function LayOut()
    local points = { { at = 0 } }
    for _, s in ipairs(flight.stops or {}) do points[#points + 1] = { at = s.at, name = s.name } end
    points[#points + 1] = { at = 1 }
    local lastLabel = 70                   -- pixels kept clear of the start's name
    for n, pt in ipairs(points) do
        local m = frame.markers[n] or Marker()
        frame.markers[n] = m
        local x = pt.at * frame.len
        m:At(x, points[n + 1] and points[n + 1].at * frame.len)
        m:Show(true)
        m.at = pt.at
        if pt.name and x - lastLabel > 60 and frame.len - x > 70 then
            m.label:SetText(Short(pt.name))
            m.label:Show()
            lastLabel = x
        else
            m.label:Hide()
        end
    end
    for n = #points + 1, #frame.markers do frame.markers[n]:Show(false) frame.markers[n].at = nil end
    frame.laid = flight
end

function YR:AnimateFlight()
    if not (frame and flight) then return end
    if frame.laid ~= flight then LayOut() end
    local p = Progress()
    local fillX
    if p then
        fillX = Round(p * frame.len)
        frame.fill:SetWidth(math.max(1, fillX))
        frame.fill:SetShown(fillX >= 1)
        Shade(frame.fill, p)
        frame.head:ClearAllPoints()
        frame.head:SetPoint("CENTER", frame, "TOPLEFT", PAD + fillX, TRACK_Y)
        frame.head:SetVertexColor(Mix(FAR, NEAR, p))
        frame.head:SetShown(fillX >= 1 and fillX < frame.len)
        frame.sweep:Hide()
    else
        frame.fill:Hide()
        frame.head:Hide()
        local x = Round(((GetTime() - flight.started) % SWEEP) / SWEEP * (frame.len - 36))
        frame.sweep:ClearAllPoints()
        frame.sweep:SetPoint("LEFT", frame, "TOPLEFT", PAD + x, TRACK_Y)
        frame.sweep:Show()
    end
    -- each node fills as the fill reaches it, in the fill's colour where it is (the start's is full
    -- from take-off: you are there)
    local cur = { Mix(FAR, NEAR, p or 0) }
    for _, m in ipairs(frame.markers) do
        if m.at then
            local r, g, b = Mix(FAR, cur, (p and p > 0) and math.min(1, m.at / p) or 0)
            m:Fill(m.at == 0 and NODE or fillX, r, g, b)
        end
    end
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
        local left = total - gone
        if left >= 0 then
            frame.time:SetText((guess and "about " or "") .. Clock(left))
            -- the next stop on the way, and when you are there
            local nextStop
            for _, st in ipairs(flight.stops or {}) do
                if st.at * total > gone then nextStop = st break end
            end
            frame.note:SetText(nextStop and ("left, " .. Short(nextStop.name) .. " in " .. Clock(nextStop.at * total - gone)) or "left")
        else
            frame.time:SetText("landing")
            frame.note:SetText(Clock(-left) .. " over")
        end
    else
        frame.time:SetText(Clock(gone))
        frame.note:SetText("first time: timing it")
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
        map = flight.map, rxp = flight.rxp, stops = flight.stops, at = time() }
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

-- In the air: landing is when the game stops saying you are on a taxi. Checked a few times a second:
-- PLAYER_CONTROL_GAINED can come while UnitOnTaxi still says yes, and then nothing else tells us
-- (seen in game: Ratchet to Theramore, the bar stayed up "landing").
local function WhileFlying(self, elapsed)
    waited = waited + elapsed
    if waited < 0.25 then return end
    waited = 0
    if not flight then
        self:SetScript("OnUpdate", nil)
    elseif not UnitOnTaxi("player") then
        self:SetScript("OnUpdate", nil)
        Land()
    end
end
-- after the click the game takes a moment to put you on the taxi: wait for it (5 seconds at most)
local function WaitForTaxi(self, elapsed)
    waited = waited + elapsed
    if UnitOnTaxi("player") then
        TakeOff()
        waited = 0
        self:SetScript("OnUpdate", WhileFlying)
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
    local length = RouteLength(i)
    pending = { from = from, to = to, key = from .. ">" .. to, length = length, stops = Stops(i, length),
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
                rxp = now.rxp, stops = now.stops, resumed = true }
            flight.started = GetTime() - (time() - (now.at or time()))
            flight.total, flight.guess = Expected(flight)
            if YR.Option("flightTimer") then ShowBar(true) end
            waited = 0
            watcher:SetScript("OnUpdate", WhileFlying)
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
    flight = { from = "Ratchet, The Barrens", to = "Auberdine, Darkshore", key = "", started = GetTime(), total = 20,
        stops = { { name = "Astranaar, Ashenvale", at = 0.4 } } }
    ShowBar(true)
    C_Timer.After(20, function()
        if flight and flight.key == "" then flight = nil ShowBar(false) end
    end)
end
