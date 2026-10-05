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

-- The two main switches: the routes (YR.RoutesOn, Guides.lua) and all of quality of life, this one.
-- With quality of life off every QoL option answers "off" whatever it's set to (your settings are
-- kept for when it's back on); what belongs to the routes and the window itself still answers.
local LEVELLING = { minimapButton = true, logging = true, showSplits = true, deathSkipRelease = true, campReminder = true,
    buyLater = true, sellGuard = true, groupPanel = true, groupAccept = true, groupShare = true }

function YR.QoLOn()
    return YippRouteDB.qolOff ~= true
end

--- Quality of life on or off, for the whole account. What's on screen follows at once where it can;
--- the rest (hooks already made, bars already built) follows a /reload.
function YR.SetQoLOn(on)
    local was = YR.QoLOn()
    YippRouteDB.qolOff = (not on) and true or nil
    if (on and true or false) == was then return end
    for _, apply in ipairs({ "XPBarApply", "TalentFadeApply", "InstanceHudApply", "RXPSkinApply", "DamageSkinApply", "BarHideApply", "SwingApply" }) do
        if YR[apply] then pcall(YR[apply]) end
    end
    for _, key in ipairs({ "bag", "reagentBag", "talents" }) do
        if YR.MoverPlace then pcall(YR.MoverPlace, key) end
    end
    YR.Print(on and "quality of life on: /reload to bring everything back."
        or "quality of life off: /reload to take everything off the screen.")
end

-- EllesmereUI does some of the same things. Where one of its modules is loaded, ours starts OFF:
-- an option you never set answers "off" (set it yourself, either way, and that's what counts).
-- Which of ours meets which of its modules:
--   flightTimer   - Forever Essentials' flight timer
--   durability    - QoL's low durability warning
--   autoTrain     - QoL's Train All button
--   talentMove    - QoL's Shifter (moves and scales Blizzard's windows, the talent window among them)
--   talentFadeSlider - Blizz UI Enhanced reskins the talent window
--   groupAccept   - Quest Tracker's auto accept
--   xpbar         - Action Bars' and DataBars' XP bars
local ELLESMERE = {
    flightTimer = { "EllesmereUIForeverEssentials" }, durability = { "EllesmereUIQoL" }, autoTrain = { "EllesmereUIQoL" },
    talentMove = { "EllesmereUIQoL" }, talentFadeSlider = { "EllesmereUIBlizzardSkin" },
    groupAccept = { "EllesmereUIQuestTracker" }, xpbar = { "EllesmereUIActionBars", "EllesmereUIDataBars" },
}

--- The EllesmereUI module that does what this option does, if it's loaded (its name), else nil.
--- The answer is kept until another addon loads: this is asked on every read of such an option.
local ellesmere = {}
function YR.EllesmereHas(key)
    local mods = ELLESMERE[key]
    if not (mods and C_AddOns and C_AddOns.IsAddOnLoaded) then return nil end
    local known = ellesmere[key]
    if known ~= nil then return known or nil end
    known = false
    for _, name in ipairs(mods) do
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
        if ok and loaded then known = name break end
    end
    ellesmere[key] = known
    return known or nil
end
function YR.EllesmereForget() for k in pairs(ellesmere) do ellesmere[k] = nil end end

--- What an option is before you've set it: on, unless EllesmereUI does the same.
function YR.OptionDefault(key)
    return YR.EllesmereHas(key) == nil
end

--- An option as you set it (or its default), whatever the main switch says: what the settings show.
function YR.OptionSet(key)
    local v = YippRouteDB[key]
    if v == nil then return YR.OptionDefault(key) end
    return v ~= false
end

-- An option from the options page: on unless turned off (and off while its main switch is).
function YR.Option(key)
    if YippRouteDB.qolOff == true and not LEVELLING[key] then return false end
    return YR.OptionSet(key)
end

-- "Name-Realm". Asked for in loops (once per logged run, per bag item...), so the string is made
-- once and handed out again while the name and realm are the same.
local keyName, keyRealm, key
function YR.CharKey()
    local name, realm = UnitFullName("player")
    if key and name == keyName and realm == keyRealm then return key end
    local made = (name or "?") .. "-" .. (realm or GetRealmName() or "?")
    if name and realm then keyName, keyRealm, key = name, realm, made end
    return made
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
    elseif cmd == "qol" then
        if arg == "on" or arg == "off" then
            YR.SetQoLOn(arg == "on")
        else
            YR.Print("Headstart's quality of life is " .. (YR.QoLOn() and "on" or "off")
                .. " for this account: /headstart qol on|off (then /reload).")
        end
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
local started
f:SetScript("OnEvent", function(_, _, name)
    YR.EllesmereForget()             -- an addon loaded: what EllesmereUI has may be different now
    if name ~= ADDON or started then return end
    started = true
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
    YR.StartWhisper()
    YR.StartSim()
    YR.StartUpgrades()
    YR.StartTrinkets()
    YR.StartInstances()
    YR.StartXPBar()
    YR.StartRXPSkin()
    YR.StartDamageSkin()
    YR.StartMovers()
    YR.StartTalentFade()
    YR.StartBarHide()
    YR.StartSwing()
    YR.StartCraftRemind()
    YR.StartQuickGroup()
    YR:BuildMinimapButton()
    YR:BuildOptions()   -- last: Blizzard's options API is the part most likely to differ on this client
end)
