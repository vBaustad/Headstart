-- Headstart: launch-day routes for RestedXP, plus the tools that measure what the routes need.
--   /headstart      the window (also /yroute)
--   /headstart scan   ask the server about every known quest ID (name, level, XP, money, objectives)
--   /headstart log    on/off: record quest accepts, completions and turn-ins with XP, time and position
local ADDON, YR = ...

function YR.Print(msg)
    print("|cff66ccffHeadstart|r: " .. msg)
end

-- Where the player is, as uiMapID and 0-100 map coordinates, or nil where the game won't say
-- (instances, or a value Forever keeps secret: the arithmetic errors and pcall turns that into nil).
function YR.Position()
    local ok, map, x, y = pcall(function()
        local m = C_Map.GetBestMapForUnit("player")
        local p = m and C_Map.GetPlayerMapPosition(m, "player")
        if not p then return nil end
        local px, py = p:GetXY()
        return m, floor(px * 10000 + 0.5) / 100, floor(py * 10000 + 0.5) / 100
    end)
    if ok and map then return map, x, y end
end

-- An option from the options page: on unless turned off.
function YR.Option(key)
    return YippRouteDB[key] ~= false
end

function YR.CharKey()
    local name, realm = UnitFullName("player")
    return (name or "?") .. "-" .. (realm or GetRealmName() or "?")
end

SLASH_HEADSTART1 = "/headstart"
SLASH_HEADSTART2 = "/yroute"   -- its name before it was Headstart
SlashCmdList.HEADSTART = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
    if cmd == "scan" then
        if arg == "stop" then YR:StopScan() else YR:StartScan() end
    elseif cmd == "log" then
        YR:SetLogging(arg ~= "off")
    elseif cmd == "splits" then
        if arg == "reset" then YR:ResetSplits() else YR:ShowSplits(arg ~= "off") end
    elseif cmd == "status" then
        YR:ScanStatus()
        YR:LogStatus()
        YR.Print("/yroute - the window; /yroute scan (stop) - ask the server about every known quest;"
            .. " /yroute log on|off; /yroute splits on|off|reset")
    else
        YR:ToggleWindow()
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    self:UnregisterEvent("ADDON_LOADED")
    YippRouteDB = YippRouteDB or {}
    YippRouteDB.runs = YippRouteDB.runs or {}
    if YippRouteDB.logging == nil then YippRouteDB.logging = true end   -- on by default: that's the point on the beta
    YR:RegisterGuides()
    YR:RegisterExtras()
    YR:StartLog()
    YR:HookTooltips()
    YR:StartSplits()
    YR:BuildMinimapButton()
    YR:BuildOptions()   -- last: Blizzard's options API is the part most likely to differ on this client
end)
