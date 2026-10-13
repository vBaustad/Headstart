-- Skip cinematics: a cinematic is ended as it starts - in this game that is a new character's opening
-- flight over its zone. On unless turned off: the one thing Headstart does for you without being asked
-- (the user, 2026-10-13: "svært få ser cinematic med mindre de er nye. og da bruker de ikke denne
-- addonen"). It costs nothing, changes nothing of yours, and says in chat that it did it and how to
-- watch: hold Shift as the cinematic starts (as you enter the world, for the opening one).
--   Account option skipCinematic. Free while off: one event, listened for only while it is on.
--   StopCinematic is the game's own (Blizzard_APIDocumentationGenerated, CinematicDocumentation.lua):
--   what Escape on a cinematic comes to. With none running it does nothing.
local _, YR = ...

local said          -- told once a login, not at every one
local function Stop()
    StopCinematic()
    if not said then
        said = true
        YR.Print("skipped the cinematic. To watch one, hold Shift as it starts; the switch is Skip cinematics in /hs.")
    end
end

--- Whether a cinematic that starts now would be skipped (for the settings and the tests).
function YR.SkipsCinematics() return YR.Option("skipCinematic") end

YR.Part(YR.SkipsCinematics, { "CINEMATIC_START" }, function(_, _, canBeCancelled)
    -- (false: not a cinematic of the game's but a ride it shows as one, which Escape does not end
    -- either - left alone)
    if canBeCancelled == false or IsShiftKeyDown() then return end
    -- A moment later, not now: Blizzard's own cinematic frame takes this same event to hide the
    -- interface, and must have had it before the stop arrives, or it would hide it for nothing.
    C_Timer.After(0, Stop)
end)
