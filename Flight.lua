-- Flight timer: a bar from take-off to landing, with where from, where to and the time left.
-- The game doesn't say how long a flight takes, so each one is timed and remembered (account-wide, in
-- YippRouteDB.flights["From>To"] = seconds). A flight not timed yet takes RestedXP's time for it (its
-- Forever flight data, worked out in its own TakeTaxiNode hook, which runs before ours), else an
-- estimate: its length on the flight map (the hops it flies over) times the seconds per unit of length
-- the timed flights on that map averaged (YippRouteDB.flightPace[taxi map]). With none of these, the
-- bar counts up while it learns. RestedXP's own flight bar is hidden while ours shows.
-- Account option flightTimer (Settings, QoL); the bar is dragged where you want it while it shows.
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

-- The bar: a small dark card. Top row: where from > where to on the left, the time left on the right in
-- blue. Under it a thin blue bar that fills from the left, with a lit knob where you are now. Bottom row:
-- a quiet line for what's going on (timing a first flight, estimated, landing) and, on a flight with
-- stops on the way, a Land button for the next one. The stops themselves aren't drawn: the game doesn't
-- say how long each leg takes (tried in game, 2026-10-01). On a first flight, with no time to go by, a
-- light runs along the bar.
local W, H = 320, 62
local PAD = 12
local TRACK_Y, THICK, KNOB = -33, 5, 13
local BLUE, BLUE_DIM = { 0.40, 0.66, 1.00 }, { 0.18, 0.40, 0.80 }
local TRACK = { 0.17, 0.19, 0.23, 1 }
local SWEEP = 1.8                     -- seconds for the light to run the bar on a first flight

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

-- The fill: a deeper blue at the start to the bright blue at its front (made once; no per-frame colours).
local function Shade(tex)
    tex:SetColorTexture(1, 1, 1, 1)
    if tex.SetGradient and CreateColor then
        tex:SetGradient("HORIZONTAL", CreateColor(BLUE_DIM[1], BLUE_DIM[2], BLUE_DIM[3], 1),
            CreateColor(BLUE[1], BLUE[2], BLUE[3], 1))
    else
        tex:SetColorTexture(BLUE[1], BLUE[2], BLUE[3], 1)
    end
end

-- Whether the button can land you early: a flight with stops on the way, not already asked.
local function CanStop()
    return TaxiRequestEarlyLanding ~= nil and flight ~= nil and not flight.cut
        and type(flight.stops) == "table" and #flight.stops > 0
end

-- The game's own "request stop": the taxi lands at the next flight point on the way. Where that is
-- and when isn't known, so the bar counts up from then; a flight cut short is not the route's time,
-- so it is never learned (Landed).
local function StopAtNext()
    if not CanStop() then return end
    TaxiRequestEarlyLanding()
    flight.cut = true
    if YippRouteDB.flightNow then YippRouteDB.flightNow.cut = true end
    YR:RefreshFlight()
end

local function Build()
    local S = YR.Style
    frame = CreateFrame("Frame", "HeadstartFlightFrame", UIParent)
    frame:SetSize(W, H)
    frame:SetFrameStrata("MEDIUM")
    S.Fill(frame, { 0.055, 0.065, 0.085, 0.92 })
    S.Border(frame, S.C.lineHi)
    frame.len = W - 2 * PAD
    -- top row: from > to, and the time
    frame.from = S.Text(frame, 13, S.C.sub)
    frame.from:SetPoint("TOPLEFT", PAD, -11)
    frame.from:SetWordWrap(false)
    frame.arrow = S.Text(frame, 13, S.C.muted)
    frame.arrow:SetPoint("LEFT", frame.from, "RIGHT", 6, 0)
    frame.arrow:SetText(">")
    frame.to = S.Text(frame, 13, S.C.text)
    frame.to:SetPoint("LEFT", frame.arrow, "RIGHT", 6, 0)
    frame.to:SetWordWrap(false)
    frame.time = S.Text(frame, 17, BLUE)
    frame.time:SetPoint("TOPRIGHT", -PAD, -8)
    frame.time:SetJustifyH("RIGHT")
    -- the bar, its fill, the knob (a soft glow under a bright dot), and the light of a first flight
    frame.bar = Solid("BORDER", 0, TRACK)
    frame.bar:SetHeight(THICK)
    frame.bar:SetPoint("LEFT", frame, "TOPLEFT", PAD, TRACK_Y)
    frame.bar:SetWidth(frame.len)
    frame.fill = Solid("ARTWORK", 0, BLUE)
    frame.fill:SetHeight(THICK)
    frame.fill:SetPoint("LEFT", frame, "TOPLEFT", PAD, TRACK_Y)
    Shade(frame.fill)
    frame.glow = Circle("ARTWORK", 1, KNOB + 10, { BLUE[1], BLUE[2], BLUE[3], 0.35 })
    frame.head = Circle("ARTWORK", 2, KNOB, { 0.92, 0.96, 1, 1 })
    frame.core = Circle("ARTWORK", 3, KNOB - 6, BLUE)
    frame.sweep = Solid("ARTWORK", 0, { BLUE[1], BLUE[2], BLUE[3], 0.6 })
    frame.sweep:SetSize(36, THICK)
    -- bottom row: what's going on, and Land
    frame.note = S.Text(frame, 11, S.C.muted)
    frame.note:SetPoint("BOTTOMLEFT", PAD, 8)
    frame.note:SetJustifyH("LEFT")
    frame.stop = CreateFrame("Button", nil, frame)
    frame.stop:SetSize(46, 18)
    frame.stop:SetPoint("BOTTOMRIGHT", -PAD + 2, 6)
    local bg = S.Fill(frame.stop, S.C.field)
    local line = S.Border(frame.stop, S.C.line)
    frame.stop.text = S.Text(frame.stop, 11, S.C.sub)
    frame.stop.text:SetPoint("CENTER")
    frame.stop.text:SetText("Land")
    frame.stop:SetScript("OnClick", StopAtNext)
    frame.stop:SetScript("OnEnter", function(self)
        line:Color(S.C.lineHi)
        self.text:SetTextColor(unpack(S.C.text))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Land at the next stop")
        GameTooltip:AddLine("The next flight point on the way", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    frame.stop:SetScript("OnLeave", function(self)
        line:Color(S.C.line)
        self.text:SetTextColor(unpack(S.C.sub))
        GameTooltip:Hide()
    end)
    frame.stop:Hide()
    frame.markers = {}
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

local function Knob(x, shown)
    for _, t in ipairs({ frame.glow, frame.head, frame.core }) do
        t:ClearAllPoints()
        t:SetPoint("CENTER", frame, "TOPLEFT", PAD + x, TRACK_Y)
        t:SetShown(shown)
    end
end

function YR:AnimateFlight()
    if not (frame and flight) then return end
    if frame.laid ~= flight then frame.laid, frame.drawn = flight, nil end
    local p = Progress()
    local fillX = p and Round(p * frame.len)
    -- the fill only moves a whole pixel a few times a second: the frames between draw nothing
    if p and frame.drawn == fillX then return end
    if p then
        frame.fill:SetWidth(math.max(1, fillX))
        frame.fill:SetShown(fillX >= 1)
        Knob(fillX, true)
        frame.sweep:Hide()
    else
        frame.fill:Hide()
        Knob(0, false)
        local x = Round(((GetTime() - flight.started) % SWEEP) / SWEEP * (frame.len - 36))
        frame.sweep:ClearAllPoints()
        frame.sweep:SetPoint("LEFT", frame, "TOPLEFT", PAD + x, TRACK_Y)
        frame.sweep:Show()
    end
    frame.drawn = fillX or false
end

function YR:RefreshFlight()
    if not (frame and flight) then return end
    -- one bar is enough: RestedXP's (it shows a moment after take-off) goes while ours is up
    local rxpBar = type(RXP) == "table" and type(RXP.flightInfo) == "table" and RXP.flightInfo.flightBar
    if type(rxpBar) == "table" and rxpBar.IsShown and rxpBar:IsShown() then rxpBar:Hide() end
    local gone = GetTime() - flight.started
    local total, guess, cut = flight.total, flight.guess, flight.cut
    frame.from:SetText(Short(flight.from))
    frame.to:SetText(Short(flight.to))
    -- the two names share the row with the time: each gets what's left, cut with an ellipsis
    local room = W - 2 * PAD - 70 - 24
    frame.from:SetWidth(0)                       -- unconstrained, to measure it
    local fromW = math.min(tonumber(frame.from:GetStringWidth()) or room / 2, room / 2)
    frame.from:SetWidth(fromW)
    frame.to:SetWidth(math.max(40, room - fromW))
    if total and total > 0 and not cut then
        local left = total - gone
        frame.time:SetTextColor(BLUE[1], BLUE[2], BLUE[3])
        if left >= 0 then
            frame.time:SetText((guess and "~" or "") .. Clock(left))
            frame.note:SetText(guess and "about: estimated from the flight's length" or "")
        else
            frame.time:SetText("+" .. Clock(-left))
            frame.note:SetText("landing")
        end
    else
        frame.time:SetTextColor(unpack(YR.Style.C.sub))
        frame.time:SetText(Clock(gone))
        frame.note:SetText(cut and "landing at the next stop" or "first flight here: timing it")
    end
    frame.stop:SetShown(CanStop())
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
    -- that went through a reload is never learned (Landed), its start is only known to the second.
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

local function Landed()
    -- a flight landed early (the stop button) or carried over a reload is not the route's time
    if flight and not flight.resumed and not flight.cut then Learn(flight, GetTime() - flight.started) end
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
        Landed()
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
        if flight and not UnitOnTaxi("player") then Landed() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local now = YippRouteDB.flightNow
        if now and UnitOnTaxi("player") and not flight then
            -- back from a reload in the air: the bar carries on from when the flight started
            flight = { from = now.from, to = now.to, key = now.key, length = now.length, map = now.map,
                rxp = now.rxp, stops = now.stops, cut = now.cut, resumed = true }
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
