-- World marker: your map pin, shown in the world - a mark and how far it is, seen from afar and kept at the
-- screen's edge with an arrow while it is behind you.
--   Why ours: the game has map pins (Ctrl+click on the world map) and tracks one, and it works out where the
--   tracked one is on your screen (C_Navigation.GetFrame, a region it moves there every frame), but Forever
--   doesn't draw its own marker on it (the owner, 2026-10-16: pin set, "vises ikke i verden"; the navigation
--   frame was there with its distance, Blizzard_QuestNavigation loaded). So this hangs a marker of Headstart's
--   on that region, as Glimmer hangs its light on an object's nameplate - only the spot is anywhere you put it.
--   One at a time: the game has one map pin, and tracks one thing (a quest you track takes it, and is shown).
--   Placing one: Ctrl+click on the world map (the game's own), or /headstart way 45 62 in the zone you're in;
--   /headstart way alone takes it away.
--   Follow RestedXP's arrow (waypointRXP): the next stop stands in the world - a map pin where RestedXP's arrow
--   points, as Naowh Forever does it (see below). A quest you track yourself is shown over its NPC.
--   Over the NPC: where the NPC the RestedXP step is at has a nameplate on the screen (friendly NPC plates on, in
--   the game's own settings - this doesn't turn them on), the marker stands over that plate - right over the NPC's
--   "?" or "!", as near or far as it is - and stays there while you stand at the NPC, where the game takes the pin
--   away. Elsewhere it stands on the game's spot for the pin, which has no height: in the air over the NPC's
--   feet, more or less (the owner, 2026-10-20: "the marker right over the NPC's quest marker would be best").
--   Under the mouse, the mark says what it stands for: the NPC of the RestedXP step it follows and the step's
--   quests (to take, to hand in, to do), the quest you track, or your own map pin - and how far. Only the mouse's
--   passing is caught: a click goes through to the world behind it (the owner, 2026-10-20: "a hover tooltip with
--   the quest's name").
--   Out of the way while Glimmer lights the step's NPC - its sparkles, its name and the quest over it say the same, right
--   there - and for a moment after, as the soft target goes and comes with the camera (the owner, 2026-10-22: "yes, add
--   that", to hiding it while the NPC is lit).
--   Shown only within 400 yards (RANGE; the owner, 2026-10-16: "only within a certain
--   distance, so it isn't awful"): farther off, nothing is drawn. The yards small, under the mark.
--   Account options waypoint, waypointRXP (both off until turned on). Free while off: nothing listens,
--   nothing is made; on, four events and, while a marker shows, a look ten times a second.
local _, YR = ...

local ART = "Interface\\AddOns\\Headstart\\art\\glimmer\\"
local marker                    -- the frame
local nav                       -- the game's navigation region we hang on, while there is one
local function On() return YR.QoLOn() and YR.Option("waypoint") end
local RANGE = 400
--- How near the pin must be before the marker shows, in yards.
function YR.WorldMarkerRange() return RANGE end

-- The mark floats this far over the game's spot, the yards under it. A quest's spot is at its NPC's name, over
-- its head (seen, 2026-10-16: 24 over the spot, the mark sat on the name under the quest's "?"); 92 puts it
-- over the "?", the yards between the two (the owner: "over the quest icon"). A map pin's the same, the mark
-- in the air over the spot. No beam down to the spot: it showed the ground leaving a map pin's spot in a jump
-- - the game keeps that spot at your height (measured: it stays put on the screen through a jump, UnitPosition's
-- height is 0 here and a height put in the pin is not used) - and over a quest's NPC it began in the air (the
-- owner, 2026-10-16: "the beam we can drop").
local LIFT = 92
local PLATE_GAP = 20            -- over a nameplate: the mark's middle this far over the plate's top
local StepLines                 -- (what the mark stands for, as tooltip lines; below, by the follow code it reads)
local OnUnitTip                 -- (an NPC's tooltip: the step's lines when it is the step's NPC; below)
local NpcPlate                  -- the plate of the NPC the step is at, where one shows (below, by the follow code)
local StepUnit                  -- whether a unit is the NPC the step is at (below, with NpcPlate)
local Place                     -- where the marker stands: over that plate, or on the game's spot
local onPlate                   -- the plate the marker stands over now (nil: on the game's spot)
local plates = {}               -- the unit of every nameplate on the screen
local plateUnit                 -- the unit whose plate it was

local function Build()
    local S = YR.Style
    marker = CreateFrame("Frame", "HeadstartWorldMarker", UIParent)
    marker:SetSize(64, 64)
    marker:SetFrameStrata("BACKGROUND")
    marker:EnableMouse(false)
    local function Tex(file, layer)
        local t = marker:CreateTexture(nil, layer or "ARTWORK")
        t:SetTexture(ART .. file)
        t:SetBlendMode("ADD")
        return t
    end
    local c = S.C.accent
    marker.glow = Tex("halo")
    marker.glow:SetSize(58, 58)
    marker.glow:SetPoint("CENTER", marker, "CENTER", 0, LIFT)
    marker.glow:SetVertexColor(c[1], c[2], c[3], 0.35)
    marker.mark = Tex("marker", "OVERLAY")
    marker.mark:SetSize(30, 30)
    marker.mark:SetPoint("CENTER", marker.glow, "CENTER")
    marker.mark:SetVertexColor(c[1], c[2], c[3], 1)
    marker.text = S.Text(marker, 11, S.C.sub)
    marker.text:SetPoint("TOP", marker.mark, "BOTTOM", 0, -2)
    marker.text:SetShadowOffset(1, -1)
    -- at the screen's edge: an arrow pointing out to where it is
    marker.arrow = marker:CreateTexture(nil, "OVERLAY")
    marker.arrow:SetSize(28, 28)
    marker.arrow:SetPoint("CENTER", marker, "CENTER")
    if S.ArtTexture then S.ArtTexture(marker.arrow, "down") end
    marker.arrow:SetVertexColor(c[1], c[2], c[3], 1)
    -- No part of it takes the mouse. It had a place that caught the mouse's passing, to say what it stands for: a
    -- frame under the mouse is what the game points at, so the NPC under the mark could not be clicked or picked
    -- (the owner, 2026-10-20: "I don't want the markers interactable, they're in the way of clicking the NPC").
    -- The NPC's own tooltip says it now (OnUnitTip, below).
    marker:Hide()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tip) if OnUnitTip then OnUnitTip(tip) end end)
    end
end

local function Yards(d)
    if type(d) ~= "number" or (issecretvalue and issecretvalue(d)) then return "" end
    return d >= 1000 and ("%.1f km"):format(d / 1000 * 0.9144) or ("%d yd"):format(math.floor(d + 0.5))
end

-- What the marker chose, and when it showed or hid and why: the last 15 for /headstart way log, and the last 200
-- in the saved file (YippRouteDB.markerLog), to be read after a /reload or a logout - the owner, 2026-10-20: the
-- marker "doesn't show up, blinks after a hand-in", and what it did can't be seen from outside the game. Only
-- while the marker is on; a line at each choice and each change, never every look.
local notes = {}
local function Note(text)
    local n = type(RXPCData) == "table" and RXPCData.currentStep
    local line = ("%s  step %s: %s"):format(date and date("%H:%M:%S") or "", tostring(n or "?"), text)
    notes[#notes + 1] = line
    if #notes > 15 then table.remove(notes, 1) end
    if type(YippRouteDB) == "table" then
        local kept = type(YippRouteDB.markerLog) == "table" and YippRouteDB.markerLog or {}
        YippRouteDB.markerLog = kept
        kept[#kept + 1] = (date and date("%m-%d ") or "") .. line
        while #kept > 200 do table.remove(kept, 1) end
    end
end
function YR.WorldMarkerNotes() return notes end

-- what the game shows the way to now, in words (for the log)
local KINDS = { [0] = "a quest", [1] = "a map pin", [2] = "your corpse", [6] = "a quest giver or a flight master", [7] = "a rare" }
local function WhatTracked()
    local st = C_SuperTrack
    local kind = st and st.GetHighestPrioritySuperTrackingType and st.GetHighestPrioritySuperTrackingType()
    if kind == nil then return "nothing" end
    local what = KINDS[kind] or ("kind " .. tostring(kind))
    if kind == 0 and st.GetSuperTrackedQuestID then what = what .. " (" .. tostring(st.GetSuperTrackedQuestID()) .. ")" end
    if kind == 6 and st.GetSuperTrackedMapPin then
        local t, id = st.GetSuperTrackedMapPin()
        what = what .. " (" .. tostring(t) .. ", " .. tostring(id) .. ")"
    end
    return what
end

local drawn                     -- what the last look did, in words: logged when it changes
local function Drawn(how)
    if drawn == how then return end
    drawn = how
    Note("on screen: " .. how)
end

-- The words under the mark, and where they stand ("mark": under it; "up"/"down": by the arrow at the screen's edge),
-- set only when they change.
local function Say(self, words)
    if self.said ~= words then
        self.said = words
        self.text:SetText(words)
    end
end
local function Under(self, where)
    if self.under == where then return end
    self.under = where
    self.text:ClearAllPoints()
    if where == "mark" then
        self.text:SetPoint("TOP", self.mark, "BOTTOM", 0, -2)
    else
        self.text:SetPoint("CENTER", self.arrow, "CENTER", 0, where == "up" and -24 or 24)
    end
end
local farFor, farWords          -- (the log's line for "farther than the range", made when the range changes)

local since, litAt, heldBack = 0, nil, false
-- How it should look is eased to over FADE seconds, every frame - in and out, never a snap (the owner, 2026-10-22: "fade
-- in/out instead of snapping, both ways"): the looks below set the goal (Goal), not the alpha.
local FADE = 0.3
local alphaNow, alphaGoal = 0, 0        -- (the one marker's: as it is, and as it is heading)
local function Goal(_, a) alphaGoal = a end
--- How it is heading to look (0 hidden, 1 shown; it eases there): for the tests.
function YR.WorldMarkerGoal() return alphaGoal end
-- what it should be now (ten times a second, from Look)
local function Decide(self)
    -- The same NPC: the marker over the very plate Glimmer lights (the marker found it the step's NPC), or Glimmer says
    -- it is the step's NPC. (Asking Glimmer alone failed in the game: RestedXP takes its arrow away near the NPC, and
    -- then Glimmer sees no guide leading - the marker, over that NPC's plate, stayed: "doesn't work", 2026-10-22.)
    -- Or, seen from here: the plate the marker stands over is the one the game gives the interact key's target - the NPC
    -- Glimmer lights, givers on. (Glimmer's own answer said "not lit" in the game while its sparkles showed, 2026-10-22.)
    if onPlate ~= nil and YR.GlimmerLightsGivers and YR.GlimmerLightsGivers() and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, "softinteract")
        if ok and p ~= nil and p == onPlate then litAt = GetTime() end
    end
    if YR.GlimmerLitGiver then
        local lit, step, on = YR.GlimmerLitGiver()
        if lit and (step or (onPlate ~= nil and on == onPlate)) then litAt = GetTime() end
    end
    heldBack = litAt ~= nil and GetTime() - litAt < 1.5
    if heldBack then
        Goal(self, 0)
        Drawn("nothing - Glimmer lights the step's NPC")
        return
    end
    local cn = C_Navigation
    if onPlate then
        -- over the NPC's plate while it is still the step's NPC's and shows; else placed again
        if NpcPlate() ~= onPlate then return Place() end
        Drawn("the marker, over the NPC's nameplate")
        self.glow:Show()
        self.mark:Show()
        self.arrow:Hide()
        Under(self, "mark")
        local d = nav and cn and cn.GetDistance and cn.GetDistance()
        Say(self, type(d) == "number" and not (issecretvalue and issecretvalue(d)) and Yards(d) or "")
        Goal(self, 1)
        return
    end
    local valid = nav and cn and (not cn.HasValidScreenPosition or cn.HasValidScreenPosition())
    if not valid then
        Goal(self, 0)
        Drawn("nothing - the game gives the spot no place on the screen")
        return
    end
    -- farther off than the range: nothing drawn
    local d = cn.GetDistance and cn.GetDistance()
    if type(d) ~= "number" or (issecretvalue and issecretvalue(d)) then d = nil end
    local range = YR.WorldMarkerRange()
    if d and d > range then
        Goal(self, 0)
        if farFor ~= range then farFor, farWords = range, ("nothing - farther than %d yd"):format(range) end
        Drawn(farWords)
        return
    end
    Drawn("the marker")
    local edge = cn.WasClampedToScreen and cn.WasClampedToScreen()
    self.glow:SetShown(not edge)
    self.mark:SetShown(not edge)
    self.arrow:SetShown(edge and true or false)
    if edge then
        -- (the art's arrow points down: turned to point from the screen's middle out to the marker)
        local x, y = self:GetCenter()
        local cx, cy = UIParent:GetCenter()
        if x and cx then self.arrow:SetRotation(math.atan2(y - cy, x - cx) + math.pi / 2) end
        Under(self, (y and cy and y > cy) and "up" or "down")
    else
        Under(self, "mark")
    end
    Say(self, Yards(d))
    -- behind something: dimmed, still there
    local state = cn.GetTargetState and cn.GetTargetState()
    local occluded = Enum and Enum.NavigationState and state == Enum.NavigationState.Occluded
    Goal(self, occluded and 0.55 or 1)
end
local function Look(self, elapsed)
    since = since + (elapsed or 0)
    if since >= 0.1 then
        since = 0
        Decide(self)
    end
    if alphaNow ~= alphaGoal then
        local step = (elapsed or 0) / FADE
        alphaNow = alphaGoal > alphaNow and math.min(alphaGoal, alphaNow + step) or math.max(alphaGoal, alphaNow - step)
        self:SetAlpha(alphaNow)
    end
end

-- Where the marker stands: over the plate of the NPC the step is at, where one shows; else on the game's spot;
-- else nowhere.
function Place()
    local plate = On() and NpcPlate() or nil
    if not (plate or (On() and nav)) then
        onPlate = nil
        if marker then marker:Hide() marker:SetScript("OnUpdate", nil) end
        return
    end
    if not marker then Build() end
    local at = plate or nav
    if marker.at ~= at or not marker:IsShown() then
        marker:ClearAllPoints()
        if plate then
            marker:SetPoint("CENTER", plate, "TOP", 0, PLATE_GAP - LIFT)
            Note("the step's NPC has a nameplate: the marker over it")
        else
            marker:SetPoint("CENTER", nav, "CENTER")
        end
        marker.at = at
    end
    onPlate = plate
    since = 1
    if not marker:IsShown() then
        alphaNow = 0
        marker:SetAlpha(0)
    end
    marker:SetScript("OnUpdate", Look)
    marker:Show()
    Look(marker, 0)
end

local function Attach(region)
    nav = region
    if On() and nav then
        drawn = nil
        Note("the game shows the way to " .. WhatTracked())
    end
    Place()
end

local function Detach()
    if nav and On() then Note(onPlate and "the game's spot is gone: the marker stays over the NPC" or "the game's spot is gone: hidden") end
    nav, drawn = nil, nil
    Place()
end

local function Current() return C_Navigation and C_Navigation.GetFrame and C_Navigation.GetFrame() end

-- A pin put with Ctrl+click on the world map is put untracked - the map's own code takes the tracking off right
-- after it - and only what the game tracks has a spot on the screen. So a new pin is tracked here: a frame
-- later with the map shut, or as the map shuts (tracking it with the map open would be ours inside the map's
-- code). One already tracked is left as it is. (Found in Naowh Forever's notes, 2026-10-16.)
local trackOnShut, mapHooked = false, false
local function TrackPin()
    trackOnShut = false
    local st = C_SuperTrack
    if not (On() and st and C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()) then return end
    if st.IsSuperTrackingUserWaypoint and st.IsSuperTrackingUserWaypoint() then return end
    if st.SetSuperTrackedUserWaypoint then st.SetSuperTrackedUserWaypoint(true) end
end
local function PinUpdated()
    local map = WorldMapFrame
    if map and map.IsShown and map:IsShown() then
        trackOnShut = true
        if not mapHooked and map.HookScript then
            mapHooked = true
            map:HookScript("OnHide", function() if trackOnShut then C_Timer.After(0, TrackPin) end end)
        end
        return
    end
    C_Timer.After(0, TrackPin)
end

-- Nameplates coming and going: only the one that comes is looked at (is it the step's NPC's?), and the one that
-- goes only if it was the marker's.
local function PlateCame(unit)
    if type(unit) ~= "string" then return end
    plates[unit] = true
    -- (this one alone: every plate on the screen was asked at each one that came)
    if not onPlate and StepUnit(unit) then Place() end
end
local function PlateWent(unit)
    if type(unit) ~= "string" then return end
    plates[unit] = nil
    if unit == plateUnit then
        plateUnit = nil
        Place()
    end
end
local function PlatesNow()
    wipe(plates)
    local np = C_NamePlate
    local ok, list = pcall(np and np.GetNamePlates or error)
    for _, p in ipairs(ok and type(list) == "table" and list or {}) do
        local unit = type(p) == "table" and p.namePlateUnitToken
        if type(unit) == "string" and not (issecretvalue and issecretvalue(unit)) then plates[unit] = true end
    end
end

YR.Part(On, { "NAVIGATION_FRAME_CREATED", "NAVIGATION_FRAME_DESTROYED", "SUPER_TRACKING_CHANGED", "USER_WAYPOINT_UPDATED",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }, function(_, event, region)
    if event == "NAME_PLATE_UNIT_ADDED" then return PlateCame(region) end
    if event == "NAME_PLATE_UNIT_REMOVED" then return PlateWent(region) end
    if event == "USER_WAYPOINT_UPDATED" then return PinUpdated() end
    if event == "SUPER_TRACKING_CHANGED" and YR.WorldMarkerGuard then YR.WorldMarkerGuard() end
    if event == "NAVIGATION_FRAME_DESTROYED" then return Detach() end
    Attach(event == "NAVIGATION_FRAME_CREATED" and region or Current())
end, {
    start = function() PlatesNow() Attach(Current()) end,
    stop = function() Detach() wipe(plates) plateUnit = nil end,
})

--- Whether the marker shows now (for the tests).
function YR.WorldMarkerShown() return marker ~= nil and marker:IsShown() end
--- Whether it is out of the way for Glimmer's light on the step's NPC (looked at again now: tests).
function YR.WorldMarkerHeldBack()
    if marker then since = 1 Look(marker, 0) end
    return heldBack
end
function YR.WorldMarkerText() return marker and marker.text:GetText() or "" end
function YR.WorldMarkerOnPlate() return onPlate end

-- ---------------------------------------------------------------------------
-- Placing a pin: /headstart way 45 62 (the zone you're in), /headstart way alone to take it away
-- ---------------------------------------------------------------------------
local function SetPin(map, x, y)
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then return false end
    local ok, set = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, x, y))
    if not (ok and set ~= false) then return false end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    return true
end
YR.WorldMarkerPin = SetPin

function YR.WaypointCommand(arg)
    arg = strtrim and strtrim(arg or "") or (arg or "")
    if arg == "log" then
        -- how it stands now, against Glimmer's light (2026-10-22: it stayed over a lit NPC through two fixes, and what it
        -- saw couldn't be told from outside the game)
        if YR.WorldMarkerNow then YR.Print(YR.WorldMarkerNow()) end
        local notes = YR.WorldMarkerNotes and YR.WorldMarkerNotes() or {}
        if #notes == 0 then YR.Print("the world marker has followed nothing yet (Follow RestedXP's arrow, Journey page).") return end
        YR.Print("what the world marker followed, and why (the last " .. #notes .. "):")
        for _, line in ipairs(notes) do print("  " .. line) end
        return
    end
    if arg == "" or arg == "clear" then
        if C_Map and C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
        YR.Print("map pin taken away.")
        return
    end
    local x, y = arg:match("^(%d+%.?%d*)[%s,]+(%d+%.?%d*)$")
    x, y = tonumber(x), tonumber(y)
    if not (x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100) then
        YR.Print("/headstart way 45 62 puts a map pin there in the zone you're in; /headstart way alone takes it away.")
        return
    end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not (map and SetPin(map, x / 100, y / 100)) then
        YR.Print("a map pin can't be put here.")
        return
    end
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    YR.Print(("map pin at %.1f, %.1f in %s.%s"):format(x, y, info and info.name or "this zone",
        On() and "" or " Turn World marker on (Journey page) to see it in the world."))
end

-- ---------------------------------------------------------------------------
-- Following RestedXP's arrow: a map pin where RestedXP's arrow points - the step you're on - set again when that
-- moves. One thing, done the same way every time, as Naowh Forever does it (the owner, 2026-10-20: "Naowh Forever
-- is very consistent", choosing that over a marker that stands still in a jump).
--   For a while (2026-10-16 to 10-20) a step at a quest giver had the step's quest tracked instead: the game's own
--   spot for a quest's NPC stays put in a jump, where a map pin's rises with you. But the game shows and hides
--   that spot by itself - gone as you came near the NPC, gone and back around a hand-in - and the marker went with
--   it ("markers over the NPC, and then they're just gone as I come near"). A quest you track yourself is still
--   shown over its NPC.
--   Nothing is shown where RestedXP has no spot: its arrow hidden (a hearth or an .xp step, an instance, another
--   continent), or the element done, skipped or on a step no longer active - it still held the step before's
--   spot, 200 yards off (the owner, 2026-10-16 and 10-19). What this put up is taken away there.
--   A pin the game took away while you're still on your way is put back, at most every three seconds; at the spot
--   (within 15 yards) you have arrived, and it stays away. A pin of your own stays until the step moves. The pin
--   stays while its step goes on (RestedXP ticks the spot off as you come within its radius), and wins over
--   RestedXP's own tracking of the step's quest (see YR.WorldMarkerGuard). Where the game has the step's NPC
--   within 60 yards of RestedXP's spot - the giver of a quest to take, the NPC a done quest is handed in to - the
--   pin is on the NPC instead (see GameSpot).
--   /headstart way log says what was chosen and why, the last fifteen times (the saved file keeps 200, with when
--   it showed and hid - see Note).
-- ---------------------------------------------------------------------------
local followHooked = false
local lastZone, lastX, lastY            -- the spot last followed (lastZone nil: look again)
local placed                            -- the map pin put here: { map, x, y }
local following                         -- RestedXP's arrow's element being followed (nil while there's nothing to)
local idle = false                      -- why nothing is shown now (what this put up was taken away, once)
local backAt = -10                      -- (when a pin the game took away was last put back)
local function FollowOn() return On() and YR.Option("waypointRXP") end
local function Forget() lastZone = nil end

-- Whether the step RestedXP has you on is a hearth not yet used (its .hs line). (RestedXP's own: the guide's
-- steps by number, RXPCData.currentStep the one you're on.)
local function Hearthing(rxp)
    local guide = rxp.currentGuide
    local n = type(RXPCData) == "table" and tonumber(RXPCData.currentStep)
    local step = n and type(guide) == "table" and type(guide.steps) == "table" and guide.steps[n]
    if type(step) ~= "table" or type(step.elements) ~= "table" then return false end
    for _, e in ipairs(step.elements) do
        if type(e) == "table" and e.tag == "hs" and not e.completed then return true end
    end
    return false
end

-- Why RestedXP's arrow stands for nothing now (nil: it points somewhere). RestedXP's own: hideArrow (no place to
-- go on the step, an instance, another continent), its guide hidden, the element or the line it serves done or
-- skipped, its step no longer active.
local function ArrowIdle(rxp, el)
    if Hearthing(rxp) then return "a hearth step" end
    if type(el) ~= "table" then return "no spot from RestedXP" end
    if rxp.hideArrow then return "RestedXP hides its arrow" end
    local p = type(rxp.settings) == "table" and type(rxp.settings.profile) == "table" and rxp.settings.profile
    if p and p.showEnabled == false then return "RestedXP's guide is hidden" end
    -- (a spot ticked off is done only once its step is: RestedXP ticks a step's spot off as you come within its
    -- radius, while the step - the NPC to talk to - still goes on; the pin went then, before you were there - the
    -- log, 2026-10-20: "its spot is done: nothing shown" on coming near)
    local step = el.step
    local going = type(step) == "table" and not step.completed and step.active ~= false
    if (el.completed or el.skip) and not going then return "its spot is done" end
    local parent = type(el.parent) == "table" and el.parent
    if parent and (parent.completed or parent.skip) and not going then return "its spot is done" end
    if type(step) == "table" and step.active == false then return "its step isn't active" end
    return nil
end

-- Whether the map pin put here is still the one on the map (one put since, of your own, is left alone).
local function OursOnMap()
    local p = placed and C_Map and C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
    local pos = type(p) == "table" and p.position
    return pos and p.uiMapID == placed[1] and math.abs(pos.x - placed[2]) < 1e-6 and math.abs(pos.y - placed[3]) < 1e-6
end

-- Nothing to show: what this put up taken away, once (and said why, for the log).
local function Idle(why)
    if following then
        following = nil
        Place()
    end
    if idle == why then return end
    idle = why
    if OursOnMap() and C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
    placed = nil
    Forget()
    Note(why .. ": nothing shown")
end

-- Your distance to RestedXP's spot, in yards: its element's world position (HereBeDragons', from the same
-- UnitPosition as yours). Nil where it can't be told (another instance, no position).
local function ToArrow(el)
    if not (UnitPosition and type(el.wx) == "number" and type(el.wy) == "number") then return nil end
    local y, x, _, instance = UnitPosition("player")
    if type(x) ~= "number" or type(y) ~= "number" or (issecretvalue and (issecretvalue(x) or issecretvalue(y))) then return nil end
    if el.instance and instance and el.instance ~= instance then return nil end
    return math.sqrt((x - el.wx) ^ 2 + (y - el.wy) ^ 2)
end

-- Where the game itself has the NPC of the arrow's step, on RestedXP's map (0 to 1), and who that is: the giver of
-- a quest to take (the "!" the world map shows: C_QuestLine.GetQuestLineInfo), or where a quest that is done is
-- handed in (its "?" on the map: C_QuestLog.GetQuestsOnMap). Nil where the game has no place for it there.
-- (The owner, 2026-10-20: "the marker is far from the NPC" - RestedXP's spot is the guide's, and on Forever the
-- NPC may stand a little beside it.)
local NPC_NEAR = 60                     -- yards: the game's NPC this near RestedXP's spot is the one it means
local function Plain(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) and v or nil end
local function GameSpot(el)
    local step, map = el.step, el.zone
    if type(step) ~= "table" or type(step.elements) ~= "table" then return nil end
    for _, e in ipairs(step.elements) do
        local q = type(e) == "table" and not e.completed and tonumber(e.questId)
        if q and e.tag == "accept" and C_QuestLine and C_QuestLine.GetQuestLineInfo then
            local ok, info = pcall(C_QuestLine.GetQuestLineInfo, q, map)
            local x, y = ok and type(info) == "table" and Plain(info.x), ok and type(info) == "table" and Plain(info.y)
            if x and y and x > 0 and y > 0 then return x, y, "the quest giver" end
        elseif q and e.tag == "turnin" and C_QuestLog and C_QuestLog.GetQuestsOnMap
            and C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(q) then
            local ok, list = pcall(C_QuestLog.GetQuestsOnMap, map)
            for _, p in ipairs(ok and type(list) == "table" and list or {}) do
                if type(p) == "table" and p.questID == q and Plain(p.x) and Plain(p.y) then
                    return p.x, p.y, "the NPC it is handed in to"
                end
            end
        end
    end
    return nil
end

-- Yards between two spots on one map, or nil where the map's size can't be had.
local function Apart(map, x1, y1, x2, y2)
    local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
    if not (ok and Plain(w) and Plain(h) and w > 0 and h > 0) then return nil end
    return math.sqrt(((x1 - x2) * w) ^ 2 + ((y1 - y2) * h) ^ 2)
end

-- Where the pin goes for RestedXP's spot: on the NPC where the game has it near the spot, else the spot. (Asked
-- at most once a second for one spot: RestedXP looks again often.)
local targetOf, targetAt, target = nil, -10, nil
local function Target(el)
    local now = GetTime()
    if el == targetOf and el.x == target[5] and el.y == target[6] and now - targetAt < 1 then return unpack(target, 1, 4) end
    local x, y = el.x / 100, el.y / 100
    local gx, gy, who = GameSpot(el)
    local off = gx and C_Map.GetMapWorldSize and Apart(el.zone, x, y, gx, gy)
    if off and off <= NPC_NEAR then x, y = gx, gy else who, off = nil, nil end
    targetOf, targetAt, target = el, now, { x, y, who, off, el.x, el.y }
    return x, y, who, off
end

local function Follow()
    if not FollowOn() then return end
    local rxp = _G.RXP
    if type(rxp) ~= "table" then return end
    local af = rxp.arrowFrame
    local el = type(af) == "table" and af.element or nil
    local why = ArrowIdle(rxp, el)
    if why then return Idle(why) end
    idle = false
    if el.hidden or not (el.zone and el.x and el.y) then return end
    if el ~= following then
        following = el
        Place()                         -- (another step: its NPC's plate, where one shows)
    end
    local x, y, who, off = Target(el)
    if el.zone == lastZone and x == lastX and y == lastY then
        -- (the same spot: nothing to do - RestedXP looks again often - unless the game took the pin away while
        -- you're still on your way)
        if not placed or not (C_Map and C_Map.HasUserWaypoint) or C_Map.HasUserWaypoint() then return end
        local yd = ToArrow(el)
        if (yd and yd < 15) or GetTime() - backAt < 3 then return end
        backAt = GetTime()
        Note(("the game took the pin away %s: put back"):format(yd and ("%d yd from the spot"):format(yd) or "on the way"))
    end
    lastZone, lastX, lastY = el.zone, x, y
    if SetPin(el.zone, x, y) then
        placed = { el.zone, x, y }
        if who then
            Note(("a map pin on %s, as the game has it (%.1f, %.1f): %d yd from RestedXP's spot (%.1f, %.1f)")
                :format(who, x * 100, y * 100, off, el.x, el.y))
        else
            Note(("a map pin where RestedXP points (%.1f, %.1f)"):format(el.x, el.y))
        end
    else
        lastZone = nil
    end
end
YR.WorldMarkerFollow = Follow

-- The tooltip under the mark. The step RestedXP's arrow is on, where the pin is the one put for it: the NPC its
-- .target line names (in the client's language, as RestedXP gives it), and its quests not done - to take, to hand
-- in, to do. Else the quest you track, or your own map pin. Then how far.
local TIP_DO = { accept = { "Take", "|T132049:14|t " }, turnin = { "Hand in", "|T132048:14|t " }, complete = { "Do", "" } }
local function QuestName(q)
    if YR.QuestTitle then return YR.QuestTitle(q) end
    local t = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q)
    return type(t) == "string" and t ~= "" and t or ("Quest " .. q)
end
-- A guide's name for an NPC - "Name", "Name::123", "123", maybe with RestedXP's "*" or "+" in front - as its name
-- (in the client's language, as RestedXP gives it) and its id.
local function TargetEntry(raw, rxp)
    if type(raw) ~= "string" then return nil end
    raw = raw:gsub("^[%*%+]+", "")
    local name, id = raw:match("^(.-)::(%d+)$")
    if not id then name = raw end
    if raw:match("^%d+$") then name, id = nil, raw end
    if name == "" then name = nil end
    if name and type(rxp) == "table" and type(rxp.GetCreatureName) == "function" then
        local ok, here = pcall(rxp.GetCreatureName, name)
        if ok and type(here) == "string" then name = here end
    end
    return name, tonumber(id)
end
local function TargetName(raw, rxp) return (TargetEntry(raw, rxp)) end

-- The NPC the step being followed says to go to (its .target lines), and its plate among those on the screen -
-- the one it was, else looked for. Only a plate that shows; never a player's.
local stepNpc, stepNpcOf = { names = {}, ids = {} }, nil
local function ReadStepNpc()
    local step = type(following) == "table" and following.step or nil
    if step == stepNpcOf then return end
    stepNpcOf = step
    wipe(stepNpc.names) wipe(stepNpc.ids)
    plateUnit = nil
    local rxp = _G.RXP
    for _, e in ipairs(type(step) == "table" and type(step.elements) == "table" and step.elements or {}) do
        if type(e) == "table" and type(e.targets) == "table" then
            for _, raw in ipairs(e.targets) do
                local name, id = TargetEntry(raw, rxp)
                if name then stepNpc.names[name] = true end
                if id then stepNpc.ids[id] = true end
            end
        end
    end
end
local function Known(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) and v or nil end

-- RestedXP's step as it stands now - its arrow's - for Glimmer, the world marker on or not: whose NPCs it is at.
local routeNpc, routeNpcOf = { names = {}, ids = {} }, false
--- Whether `unit` is an NPC the step RestedXP has you on is at: true or false; nil where no guide leads (no RestedXP,
--- or no step under its arrow) - Glimmer then lights every quest giver, and only the step's while one does (the
--- owner, 2026-10-21: "only for the current quest in RXP, not all").
function YR.RouteStepNpc(unit)
    local rxp = _G.RXP
    local el = type(rxp) == "table" and type(rxp.arrowFrame) == "table" and rxp.arrowFrame.element
    local step = type(el) == "table" and type(el.step) == "table" and el.step or nil
    if not step then return nil end
    if step ~= routeNpcOf then
        routeNpcOf = step
        wipe(routeNpc.names) wipe(routeNpc.ids)
        for _, e in ipairs(type(step.elements) == "table" and step.elements or {}) do
            if type(e) == "table" and type(e.targets) == "table" then
                for _, raw in ipairs(e.targets) do
                    local name, id = TargetEntry(raw, rxp)
                    if name then routeNpc.names[name] = true end
                    if id then routeNpc.ids[id] = true end
                end
            end
        end
    end
    local okP, player = pcall(UnitIsPlayer, unit)
    if not okP or player ~= false then return false end
    local okG, guid = pcall(UnitGUID, unit)
    guid = okG and Known(guid)
    local id = type(guid) == "string" and tonumber(guid:match("^Creature%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)"))
    if id and routeNpc.ids[id] then return true end
    local okN, name = pcall(UnitName, unit)
    name = okN and Known(name)
    return type(name) == "string" and routeNpc.names[name] == true
end

local function IsStepNpc(unit)
    local okP, player = pcall(UnitIsPlayer, unit)
    if not okP or player ~= false then return false end
    local okG, guid = pcall(UnitGUID, unit)
    guid = okG and Known(guid)
    local id = type(guid) == "string" and tonumber(guid:match("^Creature%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)"))
    if id and stepNpc.ids[id] then return true end
    local okN, name = pcall(UnitName, unit)
    name = okN and Known(name)
    return type(name) == "string" and stepNpc.names[name] == true
end
local function Shows(p) return type(p) == "table" and (not p.IsVisible or p:IsVisible() == true) end
StepUnit = function(unit)
    if not (FollowOn() and following) then return false end
    ReadStepNpc()
    return IsStepNpc(unit)
end
NpcPlate = function()
    if not (FollowOn() and following) then return nil end
    ReadStepNpc()
    if next(stepNpc.names) == nil and next(stepNpc.ids) == nil then return nil end
    local np = C_NamePlate
    if not (np and np.GetNamePlateForUnit) then return nil end
    if plateUnit and plates[plateUnit] and IsStepNpc(plateUnit) then
        local ok, p = pcall(np.GetNamePlateForUnit, plateUnit)
        if ok and Shows(p) then return p end
    end
    plateUnit = nil
    for unit in pairs(plates) do
        if IsStepNpc(unit) then
            local ok, p = pcall(np.GetNamePlateForUnit, unit)
            if ok and Shows(p) then
                plateUnit = unit
                return p
            end
        end
    end
    return nil
end
-- The step the mark stands for, as lines on a tooltip: its NPC (left out on that NPC's own tooltip: onNpc), the
-- quests to take and hand in there by name, and how far it is; without a step, your map pin or the quest tracked.
StepLines = function(tip, onNpc)
    local rxp = _G.RXP
    local el = FollowOn() and placed and OursOnMap() and type(rxp) == "table" and type(rxp.arrowFrame) == "table"
        and rxp.arrowFrame.element
    local step = type(el) == "table" and type(el.step) == "table" and el.step
    if step then
        local who, quests = nil, {}
        for _, e in ipairs(type(step.elements) == "table" and step.elements or {}) do
            if type(e) == "table" then
                if not who and type(e.targets) == "table" then who = TargetName(e.targets[1], rxp) end
                local q = tonumber(e.questId)
                if q and TIP_DO[e.tag] and not e.completed and not e.skip then quests[#quests + 1] = { TIP_DO[e.tag], q } end
            end
        end
        if not onNpc then tip:AddLine(who or "RestedXP's next stop", 1, 0.82, 0) end
        for _, q in ipairs(quests) do
            tip:AddLine(q[1][2] .. q[1][1] .. ": " .. QuestName(q[2]), 1, 1, 1)
        end
    elseif onNpc then
        return false
    else
        local st = C_SuperTrack
        local q = st and st.GetSuperTrackedQuestID and st.GetSuperTrackedQuestID()
        local pin = st and st.IsSuperTrackingUserWaypoint and st.IsSuperTrackingUserWaypoint()
        if type(q) == "number" and q > 0 and not pin then
            tip:AddLine(QuestName(q), 1, 0.82, 0)
        else
            tip:AddLine("Your map pin", 1, 0.82, 0)
        end
    end
    local d = not onNpc and C_Navigation and C_Navigation.GetDistance and C_Navigation.GetDistance()
    if type(d) == "number" and not (issecretvalue and issecretvalue(d)) then tip:AddLine(Yards(d), 0.7, 0.7, 0.7) end
    return true
end
-- The NPC the step is at, under the mouse: its tooltip says what the step wants there - unless Quests on NPC tooltips
-- is on, which says it already (marked "route").
OnUnitTip = function(tip)
    if tip ~= GameTooltip or not (FollowOn() and following) or YR.Option("questTips") then return end
    local ok, _, unit = pcall(tip.GetUnit, tip)
    if not ok or type(unit) ~= "string" or (issecretvalue and issecretvalue(unit)) then return end
    ReadStepNpc()
    if not IsStepNpc(unit) then return end
    if StepLines(tip, true) then tip:Show() end
end
YR.WorldMarkerTip = function() if marker then StepLines(GameTooltip) end end      -- (for the tests)
YR.WorldMarkerUnitTip = function(tip) if OnUnitTip then OnUnitTip(tip) end end

-- RestedXP tracks a step's quest itself - a hand-in, an objective (C_SuperTrack.SetSuperTrackedQuestID in its own
-- turnin and complete lines) - which took the game's way from the pin to the quest's spot, and back on its next
-- look: the marker jumped between the two (the log, 2026-10-20: "the game shows the way to a quest (488)", the
-- pin, the quest again two seconds on). Following RestedXP's arrow, the pin is what is shown: tracked again over a
-- quest of the arrow's step, a frame later, at most every two seconds. A quest of no step of the arrow's - one you
-- track yourself - is left as it is.
local guardedAt = -10
function YR.WorldMarkerGuard()
    if not (FollowOn() and placed and OursOnMap()) then return end
    local st = C_SuperTrack
    if not (st and st.GetSuperTrackedQuestID and st.SetSuperTrackedUserWaypoint) then return end
    if st.IsSuperTrackingUserWaypoint and st.IsSuperTrackingUserWaypoint() then return end
    local q = st.GetSuperTrackedQuestID()
    if type(q) ~= "number" or q == 0 then return end
    local rxp = _G.RXP
    local el = type(rxp) == "table" and type(rxp.arrowFrame) == "table" and rxp.arrowFrame.element
    local step = type(el) == "table" and el.step
    local ours = false
    for _, e in ipairs(type(step) == "table" and type(step.elements) == "table" and step.elements or {}) do
        if type(e) == "table" and tonumber(e.questId) == q then ours = true break end
    end
    if not ours or GetTime() - guardedAt < 2 then return end
    guardedAt = GetTime()
    C_Timer.After(0, function()
        if not (FollowOn() and OursOnMap()) then return end
        st.SetSuperTrackedUserWaypoint(true)
        Note(("RestedXP tracked the step's quest (%d): the pin shown again"):format(q))
    end)
end

YR.Part(function() return FollowOn() and type(_G.RXP) == "table" end, nil, nil, {
    start = function()
        local rxp = _G.RXP
        if not followHooked then
            -- (RestedXP's own: its arrow's spot is chosen in these two; hooked once, the first time this is on,
            -- and bailing out at once while it is off)
            for _, name in ipairs({ "UpdateMap", "UpdateGotoSteps" }) do
                if type(rxp[name]) == "function" then hooksecurefunc(rxp, name, Follow) followHooked = true end
            end
        end
        Forget()
        Follow()
    end,
})

--- The marker as it stands now, against Glimmer's light, in one line (/headstart way log).
function YR.WorldMarkerNow()
    local lit, step, on = false, false, nil
    if YR.GlimmerLitGiver then lit, step, on = YR.GlimmerLitGiver() end
    local np = NpcPlate and NpcPlate() or nil
    local okS, soft = false, nil
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then okS, soft = pcall(C_NamePlate.GetNamePlateForUnit, "softinteract") end
    soft = okS and soft or nil
    return ("now: marker %s, over a plate %s, the step's NPC has one %s; Glimmer lights a giver %s, the step's %s,"
        .. " on the marker's plate %s, on the step NPC's plate %s; the interact target's plate %s, the marker's %s; held back %s;"
        .. " following RestedXP %s, step NPC known %s; %s"):format(
        marker and marker:IsShown() and "shown" or "hidden", tostring(onPlate ~= nil), tostring(np ~= nil), tostring(lit),
        tostring(step), tostring(on ~= nil and on == onPlate), tostring(on ~= nil and on == np), tostring(soft ~= nil),
        tostring(soft ~= nil and soft == onPlate), tostring(heldBack),
        tostring(FollowOn() and following ~= nil), tostring(next(stepNpc.names) ~= nil or next(stepNpc.ids) ~= nil),
        YR.GlimmerNow and YR.GlimmerNow() or "Glimmer: not loaded")
end
