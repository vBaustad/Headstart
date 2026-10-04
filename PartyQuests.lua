-- Party quests: share every quest you take with your party, and accept the ones your party shares -
-- not only the route's (Group.lua does those). On Forever a quest can be shared from any distance.
-- Group.lua runs both; this file only answers its two questions.
--
-- Account options (YippRouteDB, Settings, QoL):
--   shareAll      true: share every quest you take from an NPC (off unless turned on - in a group of
--                 strangers not everyone wants your whole quest log)
--   acceptFrom    "friends" (default): guildies and friends | "party": anyone in your party | "off"
-- Hold Shift as the quest window opens to be asked anyway.
local ADDON, YR = ...

function YR.ShareAll()
    return YippRouteDB and YippRouteDB.shareAll == true
end

function YR.AcceptFrom()
    local v = YippRouteDB and YippRouteDB.acceptFrom
    if v == "party" or v == "off" then return v end
    return "friends"
end

local function InParty(name)
    local ok, yes = pcall(function()
        local short = Ambiguate(name, "none")
        return UnitInParty(short) or UnitInRaid(short)
    end)
    return ok and yes or false
end

--- A guildie or a friend (in-game or Battle.net). `unit` when we have one ("npc" is the player who
--- shared, in the quest window), else just the name (the escort question only gives that).
local function Friendly(unit, name, guid)
    local ok, yes = pcall(function()
        if unit and UnitIsInMyGuild and UnitIsInMyGuild(unit) then return true end
        guid = guid or (unit and UnitGUID(unit))
        if guid and C_FriendList and C_FriendList.IsFriend and C_FriendList.IsFriend(guid) then return true end
        if guid and C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID
            and C_BattleNet.GetGameAccountInfoByGUID(guid) then return true end
        if name and C_FriendList and C_FriendList.GetFriendInfo and C_FriendList.GetFriendInfo(Ambiguate(name, "none")) then
            return true
        end
        -- The guild roster by name, for the escort question.
        if name and IsInGuild() then
            for i = 1, GetNumGuildMembers() do
                local full = GetGuildRosterInfo(i)
                if full and Ambiguate(full, "none") == Ambiguate(name, "none") then return true end
            end
        end
        return false
    end)
    return ok and yes or false
end

--- A guildie or a friend, for Quick group (QuickGroup.lua) too: by unit, name or GUID.
function YR.IsFriendly(unit, name, guid) return Friendly(unit, name, guid) end

--- Accept a quest this player shared? Only ever someone in your party.
function YR.AcceptSharedBy(unit, name)
    local from = YR.AcceptFrom()
    if from == "off" or IsShiftKeyDown() then return false end
    if not name and unit then
        local ok, n = pcall(UnitName, unit)
        name = ok and n or nil
    end
    if not name or not InParty(name) then return false end
    if from == "party" then return true end
    return Friendly(unit, name)
end
