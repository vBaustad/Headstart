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
    elseif cmd == "flight" then
        YR:PreviewFlight()
    elseif cmd == "restock" then
        if MerchantFrame and MerchantFrame:IsShown() then YR.Restock(true) else YR.Print("open a vendor first.") end
    elseif cmd == "trainer" then
        YR.Print(YR.TrainerLine() or "nothing new at your class trainer.")
    elseif cmd == "upgrades" then
        YR.ScanUpgrades()
    elseif cmd == "routes" then
        if arg == "on" or arg == "off" then
            YR.SetRoutesOn(arg == "on")
        else
            YR.Print("Headstart routes are " .. (YR.RoutesOn() and "on" or "off")
                .. " for this account: /headstart routes on|off (then /reload).")
        end
        YR:RefreshWindow()
    elseif cmd == "plan" then
        YR.OpenPlanner()
    elseif cmd == "inv" or cmd == "invite" then
        YR.InviteTarget()
    elseif cmd == "instances" or cmd == "inst" then
        YR:ToggleWindow("instances")
    elseif cmd == "gear" then
        YR.UseGearSet(arg)
    elseif cmd == "trinkets" then
        YippRouteDB.trinketBar = not YR.Option("trinketBar")
        YR.ShowTrinketBar(YR.Option("trinketBar"))
    elseif cmd == "leave" then
        YR.LeaveGroup()
    elseif cmd == "mail" then
        if YR.MailIsOpen() then YR.MailToAlt(true) else YR.Print("open a mailbox first.") end
    elseif cmd == "bank" then
        YR.DepositToBank(true)
        if not YR.BankIsOpen() then YR.Print("open the bank first.") end
    elseif cmd == "camp" then
        if arg == "lock" or arg == "unlock" then
            YR.SetCampLocked(arg == "lock")
            YR.Print(arg == "lock" and "the campfire icon is locked."
                or "the campfire icon is unlocked - drag the preview where you want it, then /headstart camp lock.")
        elseif arg == "always" then
            YR.SetCampAlways(not YR.Option("campAlways"))
            YR.Print("the resting campfire icon is " .. (YR.Option("campAlways") and "on." or "off."))
        elseif arg == "debug" then
            YR.CampDebug()
        else
            YR.SetCampIcon(not YR.Option("camp"))
            YR.Print("the campfire icon is " .. (YR.Option("camp") and "on." or "off."))
        end
    elseif cmd == "status" then
        YR:ScanStatus()
        YR:LogStatus()
        YR.Print("/headstart - the window; /hs - Settings; /headstart scan (stop) - ask the server about every known quest;"
            .. " /headstart log on|off; /headstart splits on|off|reset; /headstart flight - a sample flight bar to move;"
            .. " /headstart camp (unlock|lock|always|debug) - the campfire icon; /headstart bank - bank mats now; /headstart mail - mail them to your alt;"
            .. " /headstart routes on|off - Headstart routes in RestedXP; /headstart inv - invite your target; /headstart leave - leave the group; /headstart plan - plan your bars;"
            .. " /headstart restock - buy what you keep at this vendor; /headstart trainer - what's new at the trainer;"
            .. " /headstart upgrades - look through your bags for better gear")
    else
        YR:ToggleWindow()
    end
end

SLASH_HEADSTARTSETTINGS1 = "/hs"
SlashCmdList.HEADSTARTSETTINGS = function() YR:ToggleSettings() end

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
    YR:StartGroup()
    YR.StartCamp()
    YR.StartBank()
    YR.StartMail()
    YR.StartRestock()
    YR.StartReminders()
    YR.StartSim()
    YR.StartUpgrades()
    YR.StartTrinkets()
    YR.StartInstances()
    YR.StartXPBar()
    YR.StartCraftRemind()
    YR.StartQuickGroup()
    YR:BuildMinimapButton()
    YR:BuildOptions()   -- last: Blizzard's options API is the part most likely to differ on this client
end)
