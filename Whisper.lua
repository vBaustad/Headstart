-- Whisper sound: a sound of your choice when someone whispers you, loud enough to notice. Off until you
-- pick one (Headstart, QoL, Chat).
--   The sounds: a list of the game's own (alarms, bells, the raid warning, the ready check and the
--   like, each by its SOUNDKIT name - one this client doesn't have is left out of the list), and, when
--   another addon has LibSharedMedia loaded, every sound registered there too (sound packs, Details,
--   WeakAuras, boss mods). We ship no sound files and embed no library.
--   It plays on the Master channel: heard with the game's sound effects turned down. (A file of your own and
--   the channel were settings until 2026-10-21: "a lot of settings I'll never touch".)
--   The whisper itself isn't read (in an instance the game keeps it secret): the event alone is the cue.
--   The game still plays its own quiet "tell" sound; ours is on top of it.
--   Account options (YippRouteDB): whisperSound ("kit:NAME" or "lsm:Name"; nil is off), whisperBNet (Battle.net
--   whispers too, on unless turned off), whisperGap (seconds between two sounds, 2).
local ADDON, YR = ...

-- The game's own, by SOUNDKIT name, with what we call each. In the order they're listed. Only the
-- settings' list and the name of the picked sound read it, so it is made the first time one of them asks.
local KIT
local function Kit()
    if KIT then return KIT end
    KIT = {
        { "TELL_MESSAGE", "Whisper (the game's own)" },
        { "RAID_WARNING", "Raid warning" },
        { "READY_CHECK", "Ready check" },
        { "ALARM_CLOCK_WARNING_1", "Alarm 1" },
        { "ALARM_CLOCK_WARNING_2", "Alarm 2" },
        { "ALARM_CLOCK_WARNING_3", "Alarm 3" },
        { "UI_BNET_TOAST", "Battle.net toast" },
        { "IG_PLAYER_INVITE", "Group invite" },
        { "PVP_THROUGH_QUEUE", "Queue ready" },
        { "LFG_ROLE_CHECK", "Role check" },
        { "LFG_REWARDS", "Dungeon reward" },
        { "MAP_PING", "Map ping" },
        { "AUCTION_WINDOW_OPEN", "Auction bell" },
        { "AUCTION_WINDOW_CLOSE", "Auction bell, closing" },
        { "IG_QUEST_LIST_COMPLETE", "Quest complete" },
        { "UI_RAID_BOSS_WHISPER_WARNING", "Boss whisper" },
        { "RAID_BOSS_EMOTE_WARNING", "Boss emote" },
        { "UI_EPICLOOT_TOAST", "Epic loot" },
    }
    -- (the clicks and rustles of the game's windows - backpack, menu, page turn, coins - were in this
    -- list: none of them is a sound you'd know a whisper by. One picked then still plays.)
    return KIT
end

local CHANNEL = "Master"

local function SharedMedia()
    local stub = _G.LibStub
    if type(stub) ~= "table" then return nil end
    local ok, lib = pcall(stub, "LibSharedMedia-3.0", true)
    return ok and type(lib) == "table" and type(lib.HashTable) == "function" and lib or nil
end

--- Every sound there is to pick: { { key, label }, ... }, "off" first. The game's own that this client
--- has, then (with LibSharedMedia loaded and files playable) what other addons registered, by name.
function YR.WhisperSounds()
    local list = { { "off", "None" } }
    local kit = _G.SOUNDKIT
    if type(kit) == "table" then
        for _, e in ipairs(Kit()) do
            if kit[e[1]] ~= nil then list[#list + 1] = { "kit:" .. e[1], e[2] } end
        end
    end
    local lsm = _G.PlaySoundFile and SharedMedia()
    if lsm then
        local ok, sounds = pcall(lsm.HashTable, lsm, "sound")
        if ok and type(sounds) == "table" then
            local names = {}
            for name in pairs(sounds) do if type(name) == "string" and name ~= "None" then names[#names + 1] = name end end
            table.sort(names)
            for _, name in ipairs(names) do list[#list + 1] = { "lsm:" .. name, name } end
        end
    end
    return list
end

--- What the picked sound is called (for the settings), or "None".
function YR.WhisperSoundName(key)
    key = key or YippRouteDB.whisperSound
    if type(key) ~= "string" then return "None" end
    local kind, name = key:match("^(%a+):(.+)$")
    if kind == "kit" then
        for _, e in ipairs(Kit()) do if e[1] == name then return e[2] end end
        if type(_G.SOUNDKIT) == "table" and _G.SOUNDKIT[name] then return name end
    elseif kind == "lsm" then
        return name
    end
    return "None"
end

--- Play a sound by its key. Returns true when the game took it.
function YR.PlayWhisperSound(key)
    key = key or YippRouteDB.whisperSound
    if type(key) ~= "string" then return false end
    local kind, name = key:match("^(%a+):(.+)$")
    local channel = CHANNEL
    if kind == "kit" then
        local id = type(_G.SOUNDKIT) == "table" and _G.SOUNDKIT[name]
        if not id then return false end
        local ok, played = pcall(PlaySound, id, channel)
        return ok and played ~= false
    elseif kind == "lsm" then
        local lsm, play = SharedMedia(), _G.PlaySoundFile
        local file = lsm and play and lsm.HashTable and lsm:HashTable("sound")[name]
        if not file then return false end
        local ok, played = pcall(play, file, channel)
        return ok and played ~= false
    end
    return false
end

-- A whisper came in. The two kinds of whisper are two parts, so each is listened for only while it
-- is to make a sound: none of it while no sound is picked.
local last = 0
local function Heard()
    local key = YippRouteDB.whisperSound
    if not key then return end
    -- a burst of whispers is one sound
    local now = GetTime()
    if now - last < (tonumber(YippRouteDB.whisperGap) or 2) then return end
    last = now
    YR.PlayWhisperSound(key)
end

local function Wanted() return YippRouteDB.whisperSound and YR.QoLOn() and true or false end
local function WantedBNet() return Wanted() and YippRouteDB.whisperBNet ~= false end

local declared
function YR.StartWhisper()
    if declared then return end
    declared = true
    YR.Part(Wanted, { "CHAT_MSG_WHISPER" }, Heard)
    YR.Part(WantedBNet, { "CHAT_MSG_BN_WHISPER" }, Heard)
end
