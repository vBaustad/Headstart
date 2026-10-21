-- Skip intro cinematic: a new character's opening flight over its zone is ended as it starts - on a level 1
-- character, and nothing else: every other cinematic plays (the owner, 2026-10-16: "only the login cinematic,
-- no other cinematics in game"). It was every cinematic that could be cancelled, which in this game was only
-- ever that one. On unless turned off: the one thing Headstart does for you without being asked
-- (the user, 2026-10-13: "svært få ser cinematic med mindre de er nye. og da bruker de ikke denne
-- addonen"). It costs nothing, changes nothing of yours, and says in chat that it did it and how to
-- watch: hold Shift as the cinematic starts (as you enter the world, for the opening one).
--   Account option skipCinematic. Free while off: one event, listened for only while it is on.
--   StopCinematic is the game's own (Blizzard_APIDocumentationGenerated, CinematicDocumentation.lua):
--   what Escape on a cinematic comes to. With none running it does nothing.
local _, YR = ...

local said          -- told once a login, not at every one
local function Stop()
    if InCinematic and not InCinematic() then return end       -- (ended already: nothing to stop)
    StopCinematic()
    -- (it said so in chat once a session: nobody read it - the owner, 2026-10-21; Shift still lets it play, as General's
    -- page says)
    said = true
end

-- Ended now - unless Character setup is putting a new character's bars and interface on as it logs in: then the intro
-- plays on until that is done, hiding it (Headstart_Setup: YR.HoldIntro), and is ended then.
local function StopSoon()
    if YR.HoldIntro and YR.HoldIntro(Stop) then return end
    C_Timer.After(0, Stop)
end

--- Whether the intro cinematic is skipped: the setting (for the settings, Character setup and the tests).
function YR.SkipsCinematics() return YR.Option("skipCinematic") end
-- a new character: the only one an intro cinematic plays for. Anyone else has nothing listening at all.
local function NewCharacter() return (UnitLevel("player") or 1) <= 1 end

-- Not under the login's loading screen. A new character's opening flight starts while the login's loading
-- screen is still up; ended then, the world was loaded again behind a second loading screen (the user,
-- 2026-10-16: "Naowh Forever skips it without one"). So until that loading screen has gone
-- (LOADING_SCREEN_DISABLED - listened for until then, and no longer) a stop waits for it. Escape, Blizzard's
-- own way, comes to the same StopCinematic: it is when, not how.
local inWorld = false           -- the login's loading screen has gone
local waiting = false           -- a cinematic to end once it has
local sawStart = false          -- (one that started before Headstart was loaded has no start of its own here)
local listening = false

--- A cinematic to end: a moment from now, or once the login's loading screen has gone (Character setup's
--- level 1 skip comes here too).
function YR.SkipCinematicSoon()
    if listening and not inWorld then
        waiting = true
        return
    end
    -- A moment later, not now: Blizzard's own cinematic frame takes CINEMATIC_START to hide the interface,
    -- and must have had it before the stop arrives, or it would hide it for nothing.
    StopSoon()
end

local part
local function InWorld()
    inWorld = true
    if part and part.frame then part.frame:UnregisterEvent("LOADING_SCREEN_DISABLED") end
    local now = waiting or (not sawStart and InCinematic and InCinematic())
    waiting = false
    if now and NewCharacter() and not IsShiftKeyDown() then StopSoon() end
end

part = YR.Part(function() return YR.SkipsCinematics() and NewCharacter() end, { "CINEMATIC_START", "LOADING_SCREEN_DISABLED" },
    function(_, event, canBeCancelled)
    if event == "LOADING_SCREEN_DISABLED" then return InWorld() end
    sawStart = true
    -- (false: not a cinematic of the game's but a ride it shows as one, which Escape does not end
    -- either - left alone; past level 1 it is not the intro, until the parts are looked at again)
    if canBeCancelled == false or IsShiftKeyDown() or not NewCharacter() then return end
    YR.SkipCinematicSoon()
end, {
    start = function(p)
        listening = true
        if inWorld then
            p.frame:UnregisterEvent("LOADING_SCREEN_DISABLED")
        else
            -- (should the loading screen's end never be told, a minute is long enough to have waited)
            C_Timer.After(60, function() if not inWorld then InWorld() end end)
        end
    end,
    stop = function() listening = false waiting = false end,
})

--- For the tests: as if the login's loading screen were up again.
function YR.CinematicLoadingAgain()
    inWorld, waiting, sawStart = false, false, false
    if part and part.frame and listening then part.frame:RegisterEvent("LOADING_SCREEN_DISABLED") end
end
