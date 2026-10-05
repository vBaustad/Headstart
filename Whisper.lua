-- Whisper sound: a sound of your choice when someone whispers you, loud enough to notice. Off until you
-- pick one (Headstart, QoL, Reminders & sounds).
--   The sounds: a list of the game's own (alarms, bells, the raid warning, the ready check and the
--   like, each by its SOUNDKIT name - one this client doesn't have is left out of the list), and, when
--   another addon has LibSharedMedia loaded, every sound registered there too (sound packs, Details,
--   WeakAuras, boss mods). We ship no sound files and embed no library.
--   Which channel it plays on is a setting: Master is heard with the game's sound effects turned down.
--   The whisper itself isn't read (in an instance the game keeps it secret): the event alone is the cue.
--   The game still plays its own quiet "tell" sound; ours is on top of it.
--   Account options (YippRouteDB): whisperSound ("kit:NAME" or "lsm:Name"; nil is off), whisperChannel
--   ("Master", "SFX", "Dialog"; Master to begin with), whisperBNet (Battle.net whispers too, on unless
--   turned off), whisperGap (seconds between two sounds, 2).
local ADDON, YR = ...

-- The game's own, by SOUNDKIT name, with what we call each. In the order they're listed.
local KIT = {
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
    { "LOOT_WINDOW_COIN_SOUND", "Coins" },
    { "MONEY_FRAME_OPEN", "Money bag" },
    { "IG_QUEST_LIST_COMPLETE", "Quest complete" },
    { "IG_QUEST_LIST_OPEN", "Quest log" },
    { "IG_BACKPACK_OPEN", "Backpack" },
    { "IG_MAINMENU_OPEN", "Menu open" },
    { "IG_CHARACTER_INFO_TAB", "Page tab" },
    { "IG_ABILITY_PAGE_TURN", "Page turn" },
    { "ACHIEVEMENT_MENU_OPEN", "Achievement window" },
    { "UI_RAID_BOSS_WHISPER_WARNING", "Boss whisper" },
    { "RAID_BOSS_EMOTE_WARNING", "Boss emote" },
    { "UI_EPICLOOT_TOAST", "Epic loot" },
    { "UI_LEGENDARY_LOOT_TOAST", "Legendary loot" },
    { "UI_WORLDQUEST_COMPLETE", "World quest complete" },
    { "UI_GROUP_FINDER_RECEIVE_APPLICATION", "Group finder application" },
    { "UI_PROFESSIONS_NEW_RECIPE_LEARNED_TOAST", "Recipe learned" },
    { "UI_CLASS_TALENT_APPLY_CHANGES", "Talents applied" },
    { "GS_CHARACTER_SELECTION_CREATE_NEW", "Character screen chime" },
}

local CHANNELS = { Master = true, SFX = true, Dialog = true }

function YR.WhisperChannel()
    local c = YippRouteDB.whisperChannel
    return CHANNELS[c] and c or "Master"
end

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
        for _, e in ipairs(KIT) do
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
        for _, e in ipairs(KIT) do if e[1] == name then return e[2] end end
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
    local channel = YR.WhisperChannel()
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

function YR.StartWhisper()
    local f = CreateFrame("Frame")
    pcall(f.RegisterEvent, f, "CHAT_MSG_WHISPER")
    pcall(f.RegisterEvent, f, "CHAT_MSG_BN_WHISPER")
    local last = 0
    f:SetScript("OnEvent", function(_, event)
        local key = YippRouteDB.whisperSound
        if not key or not YR.QoLOn() then return end
        if event == "CHAT_MSG_BN_WHISPER" and YippRouteDB.whisperBNet == false then return end
        -- a burst of whispers is one sound
        local now = GetTime()
        if now - last < (tonumber(YippRouteDB.whisperGap) or 2) then return end
        last = now
        YR.PlayWhisperSound(key)
    end)
end
