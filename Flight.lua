-- Flight timer: a card from take-off to landing - where to, where from, the time left and when you land, a ring
-- that fills as you fly, and Land for the next stop on the way.
-- The game doesn't say how long a flight takes, so each one is timed and remembered (account-wide, in
-- YippRouteDB.flights["From>To"] = seconds). A flight not timed yet takes RestedXP's time for it (its
-- Forever flight data, worked out in its own TakeTaxiNode hook, which runs before ours), else an
-- estimate: its length on the flight map (the hops it flies over) times the seconds per unit of length
-- the timed flights on that map averaged (YippRouteDB.flightPace[taxi map]). With none of these, the
-- bar counts up while it learns. RestedXP's own flight bar is hidden while ours shows.
-- Account option flightTimer (Settings, QoL); the bar is dragged where you want it while it shows.
-- With it off nothing here runs: a flight is not timed, not learned and not looked at (YR.Part).
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

-- The card (the owner, 2026-10-20: "it works very well, but it's very like Naowh Forever's - redesign it so it's
-- less copy-paste, and bring in the land button and hide Blizzard's"). Where you are going first, in large
-- letters, and where from under it; at the left a ring round your portrait (or your side's flight mount) that
-- fills as the flight goes - the game's own cooldown sweep, which draws itself: nothing is moved each frame; at
-- the right the time left and the clock time you land; and Land as a stub of its own at the card's right end,
-- after a dotted line, as a ticket's (two lines of words and a button beside them were cramped). What's going
-- on is said in short where the landing time stands (timing it, landing, next stop), and at length in the
-- card's tooltip.
--   Land: on a flight with stops on the way, the game's own "request stop" - the taxi lands at the next flight
--   point (named on it, as near as the time gone tells). On a direct flight it is there but quiet: there is
--   nothing to land at before the end. Blizzard's own Land button is see-through while this card shows.
--   A first flight, with no time to go by: the ring breathes, and the time counts up.
local W, H = 316, 54
local PAD = 10
local RING = 40                       -- the ring's size; the portrait inside it is RING - 10
local STUB = 50                       -- Land, at the right end
local ACCENT, ACCENT_DIM = { 0.96, 0.56, 0.20 }, { 0.48, 0.28, 0.10 }
local GRYPHON, WYVERN = 132239, 132268   -- Ability_Mount_Gryphon_01, Ability_Mount_Wyvern_01 (in the Forever build)

local function Circle(parent, layer, sub, size, color)
    local t = parent:CreateTexture(nil, layer, nil, sub)
    t:SetSize(size, size)
    YR.Style.ArtTexture(t, "circle")
    t:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
    return t
end

-- How far along: 0 to 1, or nil while a first flight is being timed.
local function Progress()
    local total = flight.total
    if not (total and total > 0) then return nil end
    return math.min(1, (GetTime() - flight.started) / total)
end

-- The next flight point on the way, as near as the time gone tells (the stops are placed by their share of
-- the route's length), or nil where none is left before the end.
local function NextStop()
    if not (flight and type(flight.stops) == "table") then return nil end
    local p = Progress() or 0
    for _, s in ipairs(flight.stops) do
        if (s.at or 0) > p then return s.name end
    end
    return nil
end

-- Whether Land can land you early: a stop still ahead, not already asked.
local function CanStop()
    return TaxiRequestEarlyLanding ~= nil and flight ~= nil and not flight.cut and NextStop() ~= nil
end

-- The game's own "request stop": the taxi lands at the next flight point on the way. When isn't known, so
-- the time counts up from then; a flight cut short is not the route's time, so it is never learned (Landed).
local function StopAtNext()
    if not CanStop() then return end
    TaxiRequestEarlyLanding()
    flight.cut = true
    if YippRouteDB.flightNow then YippRouteDB.flightNow.cut = true end
    YR:RefreshFlight()
end

-- Blizzard's own Land button (MainMenuBarVehicleLeaveButton, shown on a taxi): see-through while this card
-- shows, as the card's Land does the same - and let through to the world where the game lets an addon (a frame
-- that isn't protected). Only its look is touched: it is an Edit Mode frame, shown, hidden and placed by
-- Blizzard's code alone. Put back as the card goes.
local theirs = { hidden = false }
local function TheirLand(hide)
    local b = _G.MainMenuBarVehicleLeaveButton
    if type(b) ~= "table" or type(b.SetAlpha) ~= "function" then return end
    if hide then
        if not theirs.hooked and b.HookScript then
            theirs.hooked = true
            b:HookScript("OnShow", function(self) if theirs.hidden then self:SetAlpha(0) end end)
        end
        if theirs.hidden then return end
        theirs.hidden, theirs.alpha = true, b:GetAlpha()
        b:SetAlpha(0)
        if b.EnableMouse and not (b.IsProtected and b:IsProtected()) then
            theirs.mouse = true
            if b.IsMouseEnabled then theirs.mouse = b:IsMouseEnabled() and true or false end
            b:EnableMouse(false)
        end
    elseif theirs.hidden then
        theirs.hidden = false
        b:SetAlpha(theirs.alpha or 1)
        if theirs.mouse ~= nil and b.EnableMouse then b:EnableMouse(theirs.mouse) end
        theirs.mouse = nil
    end
end

-- What's going on, at length (the card's tooltip), or nil where it's just on its way.
local function Status()
    if not flight then return nil end
    if flight.cut then return "Landing at the next stop: the time counts up from when you asked" end
    local total = flight.total
    if not (total and total > 0) then return "First flight here: timing it, for the next time" end
    if GetTime() - flight.started > total then return "Landing" end
    if flight.guess then return "About: estimated from the flight's length" end
    return nil
end

local function CardTip(self)
    if not flight then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(Short(flight.from) .. " to " .. Short(flight.to))
    local why = Status()
    if why then GameTooltip:AddLine(why, 0.8, 0.8, 0.8, true) end
    GameTooltip:AddLine("Drag to move", 0.55, 0.55, 0.55)
    GameTooltip:Show()
end

-- Land as it stands: bright in the accent where it can land you, quiet where there's nothing to land at (or
-- it's asked already) - and lit under the mouse either way, darker while pressed.
local function StubPaint()
    local b = frame.stop
    local S = YR.Style
    local can, cut = CanStop(), flight and flight.cut
    local hover, down = b.hover == true, b.down == true
    if can then
        b.bg:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], down and 0.34 or hover and 0.22 or 0.08)
    else
        b.bg:SetVertexColor(1, 1, 1, down and 0.10 or hover and 0.07 or 0.03)
    end
    local t = can and (hover and S.C.accentHi or ACCENT) or cut and ACCENT_DIM or (hover and S.C.sub or S.C.muted)
    b.text:SetTextColor(t[1], t[2], t[3])
    b.icon:SetVertexColor(t[1], t[2], t[3])
    b.text:SetText(cut and "Landing" or "Land")
end

local function LandTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local stop = NextStop()
    if flight and flight.cut then
        GameTooltip:AddLine("Landing at the next stop")
    elseif CanStop() then
        GameTooltip:AddLine("Land at " .. Short(stop))
        GameTooltip:AddLine("The next flight point on the way", 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine("A direct flight")
        GameTooltip:AddLine("Nothing to land at before " .. Short(flight and flight.to), 0.8, 0.8, 0.8, true)
    end
    GameTooltip:Show()
end

local function Build()
    -- in the accent of Headstart's windows (Style.lua)
    local S = YR.Style
    local accent = S and S.C and S.C.accent
    if accent then
        ACCENT[1], ACCENT[2], ACCENT[3] = accent[1], accent[2], accent[3]
        ACCENT_DIM[1], ACCENT_DIM[2], ACCENT_DIM[3] = accent[1] * 0.5, accent[2] * 0.5, accent[3] * 0.5
    end
    frame = CreateFrame("Frame", "HeadstartFlightFrame", UIParent)
    frame:SetSize(W, H)
    frame:SetFrameStrata("MEDIUM")
    local fill = S.Rounded(frame, "BACKGROUND", "round")
    fill:SetVertexColor(S.C.side[1], S.C.side[2], S.C.side[3], 0.94)
    -- a thin line of the accent down the left edge: the card's mark
    frame.edge = frame:CreateTexture(nil, "BORDER")
    frame.edge:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
    frame.edge:SetPoint("TOPLEFT", 0, -8)
    frame.edge:SetPoint("BOTTOMLEFT", 0, 8)
    frame.edge:SetWidth(2)
    -- the ring: the accent, and over it the game's cooldown sweep in the card's colour covering what is still
    -- to fly - so the accent shows what is flown. In the middle, on a frame over the sweep, your portrait (or
    -- your side's flight mount) in a dark round.
    local cx = PAD + RING / 2 + 2
    frame.ringBase = Circle(frame, "ARTWORK", 0, RING, ACCENT)
    frame.ringBase:SetPoint("CENTER", frame, "LEFT", cx, 0)
    -- (a first flight: the ring breathes - an animation the game runs, not ours)
    frame.breath = frame.ringBase:CreateAnimationGroup()
    frame.breath:SetLooping("BOUNCE")
    local breathe = frame.breath:CreateAnimation("Alpha")
    breathe:SetFromAlpha(0.25)
    breathe:SetToAlpha(0.8)
    breathe:SetDuration(0.9)
    frame.sweep = CreateFrame("Cooldown", nil, frame)
    frame.sweep:SetSize(RING, RING)
    frame.sweep:SetPoint("CENTER", frame.ringBase, "CENTER")
    if frame.sweep.SetSwipeTexture then frame.sweep:SetSwipeTexture(S.ART .. "circle") end
    if frame.sweep.SetSwipeColor then frame.sweep:SetSwipeColor(S.C.side[1] * 0.6, S.C.side[2] * 0.6, S.C.side[3] * 0.6, 0.92) end
    if frame.sweep.SetDrawEdge then frame.sweep:SetDrawEdge(false) end
    if frame.sweep.SetDrawBling then frame.sweep:SetDrawBling(false) end
    if frame.sweep.SetHideCountdownNumbers then frame.sweep:SetHideCountdownNumbers(true) end
    frame.middle = CreateFrame("Frame", nil, frame)
    frame.middle:SetAllPoints(frame.sweep)
    frame.middle:SetFrameLevel(frame.sweep:GetFrameLevel() + 2)
    frame.disc = Circle(frame.middle, "ARTWORK", 0, RING - 6, { S.C.side[1], S.C.side[2], S.C.side[3], 1 })
    frame.disc:SetPoint("CENTER")
    frame.face = frame.middle:CreateTexture(nil, "ARTWORK", nil, 2)
    frame.face:SetSize(RING - 10, RING - 10)
    frame.face:SetPoint("CENTER")
    frame.face:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local mask = frame.middle:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(frame.face)
    frame.face:AddMaskTexture(mask)
    frame:HookScript("OnShow", function() YR.FlightFace() end)
    YR.FlightFace()
    -- the words, two lines: where to, large, and the time left; where from (and by way of what), and the clock
    -- time you land - or what's going on, in short
    local x = PAD + RING + 12
    local right = STUB + PAD            -- (from the card's right edge: Land and a gap)
    local SIDE = W - x - right - 64     -- (the words' room: what the time leaves)
    frame.to = S.Text(frame, 15, S.C.text)
    frame.to:SetPoint("TOPLEFT", x, -10)
    frame.to:SetWidth(SIDE)
    frame.from = S.Text(frame, 11, S.C.sub)
    frame.from:SetPoint("TOPLEFT", x, -31)
    frame.from:SetWidth(SIDE)
    frame.time = S.Text(frame, 17, ACCENT)
    frame.time:SetPoint("TOPRIGHT", -right, -9)
    frame.time:SetJustifyH("RIGHT")
    frame.eta = S.Text(frame, 10, S.C.muted)
    frame.eta:SetPoint("TOPRIGHT", -right, -32)
    frame.eta:SetJustifyH("RIGHT")
    -- Land: a stub at the right end, after a dotted line
    for i = 0, 5 do
        local dot = frame:CreateTexture(nil, "BORDER")
        dot:SetColorTexture(1, 1, 1, 0.22)
        dot:SetSize(1, 3)
        dot:SetPoint("TOP", frame, "TOPRIGHT", -STUB, -8 - i * 7)
    end
    frame.stop = CreateFrame("Button", nil, frame)
    frame.stop:SetPoint("TOPRIGHT", -3, -3)
    frame.stop:SetPoint("BOTTOMRIGHT", -3, 3)
    frame.stop:SetWidth(STUB - 6)
    frame.stop.bg = S.Rounded(frame.stop, "BACKGROUND", "round")
    frame.stop.icon = frame.stop:CreateTexture(nil, "ARTWORK")
    frame.stop.icon:SetSize(14, 14)
    frame.stop.icon:SetPoint("CENTER", 0, 7)
    S.ArtTexture(frame.stop.icon, "down")
    frame.stop.text = S.Text(frame.stop, 11, S.C.text)
    frame.stop.text:SetPoint("CENTER", 0, -9)
    frame.stop.text:SetJustifyH("CENTER")
    frame.stop.text:SetText("Land")
    frame.stop:SetScript("OnClick", StopAtNext)
    frame.stop:SetScript("OnEnter", function(self)
        self.hover = true
        StubPaint()
        LandTip(self)
    end)
    frame.stop:SetScript("OnLeave", function(self)
        self.hover, self.down = false, false
        StubPaint()
        GameTooltip:Hide()
    end)
    frame.stop:SetScript("OnMouseDown", function(self) self.down = true StubPaint() end)
    frame.stop:SetScript("OnMouseUp", function(self) self.down = false StubPaint() end)
    frame:SetScript("OnEnter", CardTip)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        YippRouteDB.flightPos = { floor(self:GetLeft() + 0.5), floor(self:GetTop() - UIParent:GetTop() + 0.5) }
    end)
    -- the ring draws itself; the words change once a second, looked at ten times a second
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

--- Your portrait in the ring, as it is now (taken when the card shows, and when the setting changes); with
--- the portrait off, your side's flight mount.
function YR.FlightFace()
    if not (frame and frame.face) then return end
    if YR.Option("flightFace") and SetPortraitTexture then
        SetPortraitTexture(frame.face, "player")
    else
        frame.face:SetTexture(UnitFactionGroup and UnitFactionGroup("player") == "Horde" and WYVERN or GRYPHON)
    end
end

-- The ring for the flight now: the sweep set once (the game draws it from then on), or breathing while there
-- is no time to go by (a first flight, or a stop asked for).
local function Ring()
    local total = flight.total
    local timed = total and total > 0 and not flight.cut
    local key = timed and (flight.started .. ":" .. total) or "none"
    if frame.ringFor == flight and frame.ringKey == key then return end
    frame.ringFor, frame.ringKey = flight, key
    if timed then
        frame.ringBase:SetAlpha(1)
        frame.breath:Stop()
        frame.sweep:Show()
        frame.sweep:SetCooldown(flight.started, total)
    else
        frame.sweep:Hide()
        frame.breath:Play()
    end
end

-- The clock time a flight lands, in the game clock's own way (24 hours unless it is set to 12).
local function LandsAt(seconds)
    if type(date) ~= "function" or type(time) ~= "function" then return "" end
    local twelve = GetCVar and GetCVar("timeMgrUseMilitaryTime") == "0"
    local at = time() + floor(seconds + 0.5)
    return "lands " .. (twelve and date("%I:%M %p", at):gsub("^0", "") or date("%H:%M", at))
end

function YR:RefreshFlight(force)
    if not (frame and flight) then return end
    -- one bar is enough: RestedXP's (it shows a moment after take-off) goes while ours is up
    local rxpBar = type(RXP) == "table" and type(RXP.flightInfo) == "table" and RXP.flightInfo.flightBar
    if type(rxpBar) == "table" and rxpBar.IsShown and rxpBar:IsShown() then rxpBar:Hide() end
    Ring()
    local gone = GetTime() - flight.started
    local total, guess, cut = flight.total, flight.guess, flight.cut
    -- the names don't change during a flight: written once for it (this runs ten times a second)
    if frame.named ~= flight then
        frame.named = flight
        frame.to:SetText(Short(flight.to))
        local via = ""
        if type(flight.stops) == "table" and #flight.stops > 0 then
            via = "  ·  via " .. Short(flight.stops[1].name) .. (#flight.stops > 1 and (" +" .. (#flight.stops - 1)) or "")
        end
        frame.from:SetText("from " .. Short(flight.from) .. via)
    end
    -- Land: drawn again when whether it can land you changes
    local can = CanStop()
    if force or frame.stopCan ~= can or frame.stopCut ~= cut then
        frame.stopCan, frame.stopCut = can, cut
        StubPaint()
    end
    -- the words change once a second: written only then (and when what they say about the flight does)
    local second = floor((total and total > 0 and not cut) and (total - gone) or gone)
    if frame.second == second and frame.secondOf == flight and frame.secondTotal == total and frame.secondCut == cut
            and frame.secondGuess == guess then
        return
    end
    frame.second, frame.secondOf, frame.secondTotal, frame.secondCut, frame.secondGuess = second, flight, total, cut, guess
    if total and total > 0 and not cut then
        local left = total - gone
        frame.time:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        if left >= 0 then
            frame.time:SetText((guess and "~" or "") .. Clock(left))
            frame.eta:SetText(LandsAt(left))
        else
            frame.time:SetText("+" .. Clock(-left))
            frame.eta:SetText("landing")
        end
    else
        frame.time:SetTextColor(unpack(YR.Style.C.sub))
        frame.time:SetText(Clock(gone))
        frame.eta:SetText(cut and "next stop" or "timing it")
    end
end

local function ShowBar(on)
    if on and not frame then Build() end
    if frame then frame:SetShown(on) end
    -- Blizzard's Land button goes while the card shows for a flight (not for the sample)
    TheirLand(on and flight ~= nil and flight.key ~= "")
    if on then YR:RefreshFlight(true) end
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

local watcher            -- the frame the timer listens on, once it has been on (YR.Part)
local flying             -- the look for the landing, a few times a second, while in the air
local waited = 0

-- On the ground again (or the timer turned off): nothing is watched between flights.
local function StopWatching()
    if flying then
        flying:Cancel()
        flying = nil
    end
    if watcher then
        watcher:SetScript("OnUpdate", nil)
        watcher:UnregisterEvent("PLAYER_CONTROL_GAINED")
    end
end

local function Landed()
    -- a flight landed early (the stop button) or carried over a reload is not the route's time
    if flight and not flight.resumed and not flight.cut then Learn(flight, GetTime() - flight.started) end
    flight = nil
    YippRouteDB.flightNow = nil
    StopWatching()
    ShowBar(false)
end

-- In the air: landing is when the game stops saying you are on a taxi. The game's own word for it
-- (PLAYER_CONTROL_GAINED) is listened for while flying, and it is checked a few times a second too:
-- that event can come while UnitOnTaxi still says yes, and then nothing else tells us (seen in game:
-- Ratchet to Theramore, the bar stayed up "landing"). A ticker, not a count kept on every frame.
local function Watch()
    if not flight then
        StopWatching()
    elseif not UnitOnTaxi("player") then
        Landed()
    end
end
local function InTheAir()
    watcher:RegisterEvent("PLAYER_CONTROL_GAINED")
    if not flying then flying = C_Timer.NewTicker(0.25, Watch) end
end

-- after the click the game takes a moment to put you on the taxi: wait for it (5 seconds at most).
-- Every frame, for that moment only: the flight is timed from the frame it starts on.
local function WaitForTaxi(self, elapsed)
    waited = waited + elapsed
    if UnitOnTaxi("player") then
        self:SetScript("OnUpdate", nil)
        TakeOff()
        InTheAir()
    elseif waited > 5 then
        self:SetScript("OnUpdate", nil)
        pending = nil
    end
end

local function Wanted() return YR.Option("flightTimer") end
local part

-- A flight asked for at the flight master. The hook can't be taken off again once it is on: it is
-- put on the first time the timer is on, and with the timer off it returns at once.
local function OnTakeTaxi(i)
    if not (part and part.on and watcher) or not YR.Option("flightTimer") then return end
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
end

local function OnEvent(_, event)
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
            InTheAir()
        elseif now and not UnitOnTaxi("player") then
            YippRouteDB.flightNow = nil
        end
    end
end

local hooked
local function Begin(p)
    watcher = p.frame
    if not hooked then
        hooked = true
        hooksecurefunc("TakeTaxiNode", OnTakeTaxi)
    end
end

-- Turned off in the air: the flight is let go, unlearned (half a flight is not the route's time).
-- The sample bar (/headstart flight) is not a flight of the timer's: it is left to run out.
local function End()
    StopWatching()
    pending = nil
    if flight and flight.key ~= "" then
        flight = nil
        YippRouteDB.flightNow = nil
        ShowBar(false)
    end
end

-- Free while off (YR.Part, Core.lua). On: only a loading screen is listened for (a reload in the air);
-- the rest is from the click at the flight master to the landing.
part = YR.Part(Wanted, { "PLAYER_ENTERING_WORLD" }, OnEvent, { start = Begin, stop = End })

-- The setting: off hides a bar that is showing; on shows it if you are in the air.
function YR:SetFlightTimer(on)
    YippRouteDB.flightTimer = on
    YR.ApplyParts()
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
