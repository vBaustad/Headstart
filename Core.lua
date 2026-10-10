-- Headstart: launch-day routes for RestedXP, plus the tools that measure what the routes need.
--   /headstart      the window (also /yroute)
--   /headstart scan   ask the server about every known quest ID (name, level, XP, money, objectives)
--   /headstart log    on/off: record quest accepts, completions and turn-ins with XP, time and position
local ADDON, YR = ...

function YR.Print(msg)
    print("|cffff9a40Headstart|r: " .. msg)
end

-- Where the player is, as uiMapID and 0-100 map coordinates, or nil where the game won't say
-- (instances, or a value Forever keeps secret: the arithmetic errors and pcall turns that into nil).
local function ReadPosition()        -- one function, not a new one each time this is asked (every two seconds)
    local m = C_Map.GetBestMapForUnit("player")
    local p = m and C_Map.GetPlayerMapPosition(m, "player")
    if not p then return nil end
    local px, py = p:GetXY()
    return m, floor(px * 10000 + 0.5) / 100, floor(py * 10000 + 0.5) / 100
end
function YR.Position()
    local ok, map, x, y = pcall(ReadPosition)
    if ok and map then return map, x, y end
end

--- A value the game may keep secret (who leads the group, whether a unit is you, what was cast -
--- where it restricts that): nil when it is, so a test on it is simply false instead of an error.
function YR.Open(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- The two main switches: the routes (YR.RoutesOn, Guides.lua) and all of quality of life, this one.
-- With quality of life off every QoL option answers "off" whatever it's set to (your settings are
-- kept for when it's back on); what belongs to the routes and the window itself still answers.
local LEVELLING = { minimapButton = true, logging = true, showSplits = true, deathSkipRelease = true, campReminder = true,
    buyLater = true, sellGuard = true, groupPanel = true, groupAccept = true, groupShare = true, skipQuests = true }

function YR.QoLOn()
    return YippRouteDB.qolOff ~= true
end

--- Quality of life on or off, for the whole account. What's on screen follows at once where it can;
--- the rest (hooks already made, bars already built) follows a /reload.
function YR.SetQoLOn(on)
    local was = YR.QoLOn()
    YippRouteDB.qolOff = (not on) and true or nil
    if (on and true or false) == was then return end
    for _, apply in ipairs({ "XPBarApply", "TalentFadeApply", "InstanceHudApply", "RXPSkinApply", "DamageSkinApply", "BarHideApply", "SwingApply", "WindowScaleApply", "RecapApply", "ChatLogApply", "LootFeedApply" }) do
        if YR[apply] then pcall(YR[apply]) end
    end
    for _, key in ipairs({ "bag", "reagentBag", "talents" }) do
        if YR.MoverPlace then pcall(YR.MoverPlace, key) end
    end
    YR.ApplyParts()
    YR.Print(on and "quality of life on: /reload to bring everything back."
        or "quality of life off: /reload to take everything off the screen.")
end

-- Other addons do some of the same things. Where one that is loaded has the same feature switched
-- on, ours starts OFF: an option you never set answers "off" (set it yourself, either way, and that's
-- what counts). Being loaded is not enough where the other addon's feature is itself a choice: its
-- own setting is read (through pcall: another addon's saved table may not be shaped as it was).
--   EllesmereUI (a module per folder), Leatrix Plus (every feature off until its owner turns it on),
--   Naowh Forever (its settings aren't known here: loaded counts), NovaInstanceTracker.
local function Loaded(name)
    if not (C_AddOns and C_AddOns.IsAddOnLoaded) then return false end
    local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
    return ok and loaded and true or false
end
local function Flat(db, key) return type(_G[db]) == "table" and _G[db][key] end
local function Leatrix(key) return Loaded("Leatrix_Plus") and Flat("LeaPlusDB", key) == "On" end
-- A value somewhere in one of an addon's profiles (EllesmereUI keeps profiles; which one is active
-- isn't read here: a value any profile has counts).
local function InProfiles(db, ...)
    local root = _G[db]
    if type(root) ~= "table" then return nil end
    local path = { ... }
    local function Walk(t)
        local v = t
        for _, k in ipairs(path) do
            if type(v) ~= "table" then return nil end
            v = v[k]
        end
        return v
    end
    local direct = Walk(root)
    if direct ~= nil then return direct end
    for _, group in pairs(root) do
        if type(group) == "table" then
            local v = Walk(group)
            if v ~= nil then return v end
            for _, profile in pairs(group) do
                if type(profile) == "table" then
                    v = Walk(profile)
                    if v ~= nil then return v end
                end
            end
        end
    end
    return nil
end
-- [option] = { { name shown, function: is its feature on now? }, ... }
local OTHERS = {
    flightTimer = {
        { "EllesmereUI", function() return Loaded("EllesmereUIForeverEssentials") and (type(Flat("EllesmereUIDB", "flightTimer")) ~= "table" or Flat("EllesmereUIDB", "flightTimer").enabled ~= false) end },
        { "Leatrix Plus", function() return Leatrix("ShowFlightTimes") end },
        { "Naowh Forever", function() return Loaded("NaowhForever") end },
    },
    durability = {
        { "EllesmereUI", function() return Loaded("EllesmereUIQoL") and Flat("EllesmereUIDB", "repairWarning") ~= false end },
        { "Naowh Forever", function() return Loaded("NaowhForever") end },
    },
    talentMove = {
        { "EllesmereUI", function() return Loaded("EllesmereUIQoL") and Flat("EllesmereUIDB", "shifterEnabled") == true end },
    },
    talentFadeSlider = {
        { "EllesmereUI", function() return Loaded("EllesmereUIBlizzardSkin") and Flat("EllesmereUIDB", "reskinPlayerSpells") ~= false end },
    },
    groupAccept = {
        { "EllesmereUI", function() return Loaded("EllesmereUIQuestTracker") and InProfiles("EllesmereUIQuestTrackerDB", "questTracker", "autoAccept") == true end },
        { "Leatrix Plus", function() return Leatrix("AutomateQuests") or Leatrix("NoSharedQuests") end },
    },
    xpbar = {
        { "EllesmereUI", function() return Loaded("EllesmereUIActionBars") and InProfiles("EllesmereUIActionBarsDB", "useBlizzardDataBars") == false end },
        { "Naowh Forever", function() return Loaded("NaowhForever") end },
    },
    instanceTrack = { { "NovaInstanceTracker", function() return Loaded("NovaInstanceTracker") end } },
    restock = { { "Naowh Forever", function() return Loaded("NaowhForever") end } },
    trinketBar = { { "Naowh Forever", function() return Loaded("NaowhForever") end } },
    campReminder = { { "Naowh Forever", function() return Loaded("NaowhForever") end } },
    remindTalents = { { "Naowh Forever", function() return Loaded("NaowhForever") end } },
    acceptInvites = {
        { "Leatrix Plus", function() return Leatrix("AcceptPartyFriends") or Leatrix("NoPartyInvites") end },
        { "EllesmereUI", function() return Loaded("EllesmereUIFriends") and (InProfiles("EllesmereUIFriendsDB", "autoAcceptFriendInvites") == true or InProfiles("EllesmereUIFriendsDB", "autoAcceptGuildInvites") == true) end },
    },
    whisperInvite = { { "Leatrix Plus", function() return Leatrix("InviteFromWhisper") end } },
    chatButtons = {
        { "EllesmereUI", function() return Loaded("EllesmereUIChat") end },
        { "Leatrix Plus", function() return Leatrix("NoChatButtons") or Leatrix("NoSocialButton") or Leatrix("UnclampChat") end },
    },
    blizzardBars = { { "EllesmereUI", function() return Loaded("EllesmereUIActionBars") end } },
    windowScale = { { "EllesmereUI", function() return Loaded("EllesmereUIQoL") and Flat("EllesmereUIDB", "shifterEnabled") == true end } },
    moveBag = {
        { "EllesmereUI", function() return Loaded("EllesmereUIBags") end },
        { "Baganator", function() return Loaded("Baganator") end },
    },
    swing = {
        { "EllesmereUI", function() return Loaded("EllesmereUIResourceBars") and InProfiles("EllesmereUIResourceBarsDB", "swingTimer", "enabled") == true end },
        { "Naowh Forever", function() return Loaded("NaowhForever") end },
    },
    whisperSound = { { "EllesmereUI", function() return Loaded("EllesmereUIChat") end } },
    lootFeed = { { "Naowh Forever", function() return Loaded("NaowhForever") end } },
}

--- The other addon that does what this option does, with that feature on (its name), else nil.
--- The answer is kept until another addon loads: this is asked on every read of such an option.
local others = {}
function YR.OtherHas(key)
    local list = OTHERS[key]
    if not list then return nil end
    local known = others[key]
    if known ~= nil then return known or nil end
    known = false
    for _, other in ipairs(list) do
        local ok, on = pcall(other[2])
        if ok and on then known = other[1] break end
    end
    others[key] = known
    return known or nil
end
YR.EllesmereHas = YR.OtherHas            -- its name while EllesmereUI was the only one looked for
function YR.EllesmereForget() for k in pairs(others) do others[k] = nil end end

-- Options that are off until you turn them on yourself: everything that spends gold, moves your
-- items, joins or forms a group for you, takes screenshots, puts a bar or buttons of ours on your
-- screen or changes one of Blizzard's windows. Nobody should find those out by installing Headstart.
-- What stays on is seen and harmless: tooltips, the flight timer, the camp icon, lines in chat.
local STARTS_OFF = { autoTrain = true, restock = true, bankAuto = true, levelShot = true, trinketBar = true,
    groupBar = true, upgrades = true, talentMove = true, talentFadeSlider = true, xpbar = true,
    deathRecap = true, chatLog = true, lootFeed = true, questLFG = true, alts = true }
YR.STARTS_OFF = STARTS_OFF

--- What an option is before you've set it: on, unless it starts off or another addon does the same.
function YR.OptionDefault(key)
    if STARTS_OFF[key] then return false end
    -- recording runs and the level splits box are for levelling by a route: on with the routes
    if key == "logging" or key == "showSplits" then return YR.RoutesOn ~= nil and YR.RoutesOn() or false end
    return YR.OtherHas(key) == nil
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

-- ---------------------------------------------------------------------------
-- Free while off. A part of Headstart (the camp icon, the swing timer, the loot feed...) listens for
-- the game's events only while it is wanted: its frame is not made, nothing is registered, no ticker
-- runs and no hook does work until its setting is on - and all of that is taken away again when it is
-- turned off. tools/smoke_idle.py counts it: a login with everything off leaves nothing running.
--   YR.Part(want, events, handler, opt) says what a part needs:
--     want()    whether it is wanted now (its options; cheap, asked only when a setting changes)
--     events    { "EVENT", { "UNIT_EVENT", "player" }, ... }
--     handler   function(frame, event, ...)
--     opt.start called when it comes on (after its events are registered): build, draw, read
--     opt.stop  called when it goes off: hide, cancel
--     opt.tick, opt.every   a function called every so many seconds, only while it is on
--   YR.ApplyParts() looks at every part: at login, and whenever a setting changed (every control of the
--   settings window says so through Style's Changed, and the slash commands that change a setting).
-- ---------------------------------------------------------------------------
local parts, partsSoon = {}, false
function YR.Part(want, events, handler, opt)
    local p = { want = want, events = events or {}, handler = handler, opt = opt or {}, on = false }
    parts[#parts + 1] = p
    return p
end

local function PartOn(p)
    if not p.frame and (p.handler or #p.events > 0) then
        p.frame = CreateFrame("Frame")
        p.frame:SetScript("OnEvent", p.handler)
    end
    for _, e in ipairs(p.events) do
        if type(e) == "table" then
            pcall(p.frame.RegisterUnitEvent, p.frame, unpack(e))
        else
            pcall(p.frame.RegisterEvent, p.frame, e)
        end
    end
    if p.opt.tick and not p.ticker then p.ticker = C_Timer.NewTicker(p.opt.every or 1, p.opt.tick) end
    if p.opt.start then p.opt.start(p) end
end

local function PartOff(p)
    if p.frame then p.frame:UnregisterAllEvents() end
    if p.ticker then
        p.ticker:Cancel()
        p.ticker = nil
    end
    if p.opt.stop then p.opt.stop(p) end
end

function YR.ApplyParts()
    partsSoon = false
    if not YR.partsReady then return end            -- before the login: nothing is on yet
    for _, p in ipairs(parts) do
        local want = p.want() and true or false
        if want ~= p.on then
            p.on = want
            if want then PartOn(p) else PartOff(p) end
        elseif want and p.opt.again then
            p.opt.again(p)                          -- still on, and a setting changed: as it is now
        end
    end
end

--- A setting changed: every part is looked at once this frame is done (a slider being dragged says so
--- many times).
function YR.SettingChanged()
    if partsSoon then return end
    partsSoon = true
    C_Timer.After(0, YR.ApplyParts)
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

-- The window (the settings and the route editor) is an addon of its own, Headstart_Options: load on
-- demand, so its two hundred kilobytes of code are read the first time the window is asked for and
-- not at every login. The list of quest IDs /headstart scan asks about is in it too. An addon of its
-- own has a table of its own: ours is handed over as HeadstartNS. Until it's loaded these stand in
-- for the window's functions; loading replaces them (and sets YR.windowLoaded).
HeadstartNS = YR
function YR.LoadWindow()
    if YR.windowLoaded then return true end
    local ok, why = false, nil
    if C_AddOns and C_AddOns.LoadAddOn then ok, why = C_AddOns.LoadAddOn("Headstart_Options") end
    if YR.windowLoaded then return true end
    YR.Print("the window is in the addon \"Headstart: window\" (the folder Headstart_Options), which "
        .. ((not ok and why == "DISABLED") and "is turned off: turn it on in the AddOns list and /reload."
            or "couldn't be loaded" .. (why and (" (" .. tostring(why) .. ")") or "") .. ": install Headstart again, both folders."))
    return false
end
function YR:RefreshWindow() end              -- no window yet: nothing to draw again

-- Character setup (the bar planner, a main's bars, macros and interface on a new character) is an
-- addon of its own too, Headstart_Setup: loaded at login while Character setup is on, and the moment
-- it is turned on. Off (a new install starts so) none of it is read, no first-login window comes up
-- and no button is ever placed for you. Account option setupOn.
function YR.SetupOn() return YippRouteDB.setupOn == true end
function YR.SetupLoaded() return type(YR.Setup) == "table" and YR.Setup.Start ~= nil end
--- The setup addon read in, and started. Returns whether it is there. say: tell in chat why not.
function YR.LoadSetup(say)
    if YR.setupStarted then return true end
    local ok, why = true, nil
    if not YR.SetupLoaded() then
        ok = false
        if C_AddOns and C_AddOns.LoadAddOn then ok, why = C_AddOns.LoadAddOn("Headstart_Setup") end
    end
    if not YR.SetupLoaded() then
        if say then
            YR.Print("Character setup is in the addon \"Headstart: character setup\" (the folder Headstart_Setup), which "
                .. ((not ok and why == "DISABLED") and "is turned off: turn it on in the AddOns list and /reload."
                    or "couldn't be loaded" .. (why and (" (" .. tostring(why) .. ")") or "") .. ": install Headstart again, every folder."))
        end
        return false
    end
    YR.setupStarted = true
    -- its spell tables hold all nine classes and only yours is read: the other eight are let go
    local _, class = UnitClass("player")
    for _, name in ipairs({ "PlannerSpells", "PlannerGeneral" }) do
        local t = YR[name]
        if class and type(t) == "table" and t[class] ~= nil then
            for other in pairs(t) do if other ~= class then t[other] = nil end end
        end
    end
    YR.Setup.Start(YR.freshChar)
    return true
end
function YR.SetSetupOn(on)
    local was = YR.SetupOn()
    YippRouteDB.setupOn = on and true or false
    if on then
        YR.LoadSetup(true)
    elseif was then
        YR.Print("Character setup off: /reload to take it out of memory. Nothing more is placed on your bars.")
    end
end
function YR:ToggleWindow(page) if YR.LoadWindow() then YR:ToggleWindow(page) end end
function YR:ToggleSettings() if YR.LoadWindow() then YR:ToggleSettings() end end
function YR:ShowSettingsTab(key) if YR.LoadWindow() then YR:ShowSettingsTab(key) end end
--- A new install is asked once how much of Headstart it wants: the welcome window, a few seconds
--- after the first login and not in a fight (the next login, then). Welcome.lua, in the window's addon.
function YR.WelcomeFirst()
    local db = YippRouteDB
    if not db.welcome or db.welcomeSeen then return end
    C_Timer.After(5, function()
        if db.welcomeSeen or InCombatLockdown() then return end
        if YR.LoadWindow() and YR.WelcomeShow then YR.WelcomeShow() end
    end)
end
function Headstart_OnAddonCompartmentClick(_, which, from)
    if which == "RightButton" then YR.WindowMenu(type(from) == "table" and from or nil) else YR:ToggleWindow() end
end
-- Keys for the windows (Bindings.xml; Key Bindings, AddOns, Headstart).
function Headstart_Open(what)
    if what == "alts" then YR.AltsToggle()
    elseif what == "lfg" then YR.QuestLFGToggle()
    elseif what == "chat" then YR.ChatLogToggle()
    elseif what == "loot" then YR.LootLogToggle()
    elseif what == "menu" then YR.WindowMenu()
    elseif what == "layout" then
        local YS = YR.Setup
        if YS and YS.LayoutNext then
            local ok, why = YS.LayoutNext()
            if not ok and why then YR.Print(why) end
        else
            YR.Print("profiles are part of Character setup: turn that on in /headstart, Character setup.")
        end
    else YR:ToggleWindow() end
end
BINDING_NAME_HEADSTART_WINDOW = "Headstart's window"
BINDING_NAME_HEADSTART_MENU = "Menu of every window"
BINDING_NAME_HEADSTART_LAYOUT = "Next profile"
BINDING_NAME_HEADSTART_ALTS = "Characters: bags, bank and gold"
BINDING_NAME_HEADSTART_LFG = "Quest group"
BINDING_NAME_HEADSTART_CHATLOG = "Chat log"
BINDING_NAME_HEADSTART_LOOTLOG = "Loot log"

SLASH_HEADSTART1 = "/headstart"
SLASH_HEADSTART2 = "/yroute"   -- its name before it was Headstart
SlashCmdList.HEADSTART = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
    if cmd == "scan" then
        -- the quest IDs it asks about are in the window's addon
        if arg == "stop" then YR:StopScan() elseif YR.LoadWindow() then YR:StartScan() end
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
        if YR.SetupOn() and YR.LoadSetup(true) then YR.OpenPlanner()
        elseif not YR.SetupOn() then YR.Print("Character setup is off: turn it on in /headstart, Character setup.") end
    elseif cmd == "profile" or cmd == "profiles" or cmd == "layout" or cmd == "layouts" then
        -- /headstart profile: the next of the class's profiles; /headstart profile Tank: that one
        local YS = YR.SetupOn() and YR.LoadSetup(true) and YR.Setup
        if not YS then
            YR.Print("profiles are part of Character setup: turn that on in /headstart, Character setup.")
        else
            local name = strtrim((msg or ""):match("^%S+%s+(.+)$") or "")
            local ok, why
            if name == "" then ok, why = YS.LayoutNext() else ok, why = YS.LayoutSwitch(name) end
            if not ok and why then YR.Print(why .. " Your profiles: " .. table.concat(YS.LayoutNames(), ", ") .. ".") end
        end
    elseif cmd == "macro" or cmd == "macros" then
        if YR.SetupOn() and YR.LoadSetup(true) then YR.MacroHelperToggle()
        elseif not YR.SetupOn() then YR.Print("the macro helper is part of Character setup: turn that on in /headstart, Character setup.") end
    elseif cmd == "inv" or cmd == "invite" then
        YR.InviteTarget()
    elseif cmd == "instances" or cmd == "inst" then
        if arg == "id" then YR.InstanceIDDebug() else YR:ToggleWindow("instances") end
    elseif cmd == "perf" then
        -- what Headstart costs, by the game's own count (the code for it is in the window's addon)
        if YR.LoadWindow() then YR.Perf() end
    elseif cmd == "start" or cmd == "welcome" then
        -- the welcome window: how much of Headstart you want (the code for it is in the window's addon)
        if YR.LoadWindow() then YR.WelcomeToggle() end
    elseif cmd == "menu" then
        YR.WindowMenu()
    elseif cmd == "alts" or cmd == "chars" or cmd == "characters" then
        YR.AltsToggle()
    elseif cmd == "gold" then
        YR.AltsGoldSay()
    elseif cmd == "lfg" or cmd == "group" then
        YR.QuestLFGToggle()
    elseif cmd == "loot" then
        YR.LootLogToggle()
    elseif cmd == "chat" then
        YR.ChatLogToggle()
    elseif cmd == "death" then
        if arg == "debug" then YR.RecapDebug()
        elseif not YR.RecapShow() then YR.Print("no death recorded for this character yet.") end
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
            .. " /headstart upgrades - look through your bags for better gear; /headstart death - what happened the last time you died; /headstart chat - the chat log; /headstart loot - the loot log; /headstart perf - what Headstart costs, measured by the game; /headstart alts - your other characters' bags, bank, gold and currencies (/headstart gold: just the gold); /headstart profile [name] - switch this character to another of the class's profiles; /headstart macro - the macro helper: your class's usual macros made by ticking boxes; /headstart start - the welcome window: pick how much of Headstart you want")
    else
        YR:ToggleWindow()
    end
    -- a command may have changed a setting: what listens only while wanted is looked at again
    if YR.partsReady then YR.SettingChanged() end
end

-- Defaults changed to "off until you turn it on" (see STARTS_OFF). An account that had Headstart
-- before that keeps everything as it was: once, each of those options you never touched is written
-- down as what it was then. A new install starts quiet, and is asked what it wants (the welcome window).
local WAS_ON = { "restock", "bankAuto", "levelShot", "trinketBar", "groupBar", "upgrades", "talentMove", "talentFadeSlider" }
function YR.Latch(fresh)
    local db = YippRouteDB
    local was = tonumber(db.quiet) or 0
    if was >= 2 then return end
    db.quiet = 2
    -- 2: Character setup became something you turn on. An account that had Headstart keeps it on.
    if not fresh and db.setupOn == nil then db.setupOn = true end
    if was >= 1 then return end
    if fresh then
        db.welcome = true
        return
    end
    for _, key in ipairs(WAS_ON) do
        if db[key] == nil then db[key] = YR.OtherHas(key) == nil end
    end
    for _, key in ipairs({ "acceptInvites", "whisperInvite", "acceptFrom" }) do
        if db[key] == nil then db[key] = "friends" end
    end
    if db.showSplits == nil then db.showSplits = true end
    if db.logging == nil then db.logging = true end
    if type(db.xpbar) ~= "table" then db.xpbar = {} end
    if db.xpbar.on == nil then db.xpbar.on = YR.OtherHas("xpbar") == nil end
end

SLASH_HEADSTARTSETTINGS1 = "/hs"
SlashCmdList.HEADSTARTSETTINGS = function() YR:ToggleSettings() end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
local started
f:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        f:UnregisterEvent("PLAYER_LOGIN")
        YR.partsReady = true
        YR.ApplyParts()
        YR.WelcomeFirst()
        return
    end
    -- The window's addon has just been read in, its saved file with it: what /headstart scan found
    -- lives there now (it was two megabytes in the account's file, read at every login).
    if name == "Headstart_Options" and type(YippRouteDB) == "table" and YippRouteDB.scan ~= nil then
        _G.HeadstartScanDB = type(_G.HeadstartScanDB) == "table" and _G.HeadstartScanDB or {}
        if _G.HeadstartScanDB.scan == nil then _G.HeadstartScanDB.scan = YippRouteDB.scan end
        YippRouteDB.scan = nil
    end
    YR.EllesmereForget()             -- an addon loaded: what EllesmereUI has may be different now
    if started and YR.partsReady then YR.SettingChanged() end      -- and so may what of ours is wanted
    if name ~= ADDON or started then return end
    started = true
    local fresh = YippRouteDB == nil
    YippRouteDB = YippRouteDB or {}
    YippRouteDB.runs = YippRouteDB.runs or {}
    if YR.Style and YR.Style.Theme then YR.Style.Theme() end       -- the accent you chose, before any window is made
    YR.Latch(fresh)
    -- the saved tables every part keeps this character's and the classes' things in
    YR.freshChar = YippSetupCharDB == nil        -- this character's first login with Headstart
    YippSetupDB = YippSetupDB or {}
    YippSetupCharDB = YippSetupCharDB or {}
    if YR.SetupOn() then YR.LoadSetup() end
    -- The spell tables hold all nine classes and only yours is ever read: the other eight are let go
    -- (some three thousand small tables). The setup addon's tables are trimmed where it is loaded (YR.LoadSetup).
    local _, class = UnitClass("player")
    for _, name in ipairs({ "TrainerSpells", "RestockData" }) do
        local t = YR[name]
        if class and type(t) == "table" and t[class] ~= nil then
            for other in pairs(t) do if other ~= class then t[other] = nil end end
        end
    end
    YR:RegisterGuides()
    YR:RegisterExtras()
    YR:StartLog()
    YR.StartRunStore()
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
    YR.StartPowerFlash()
    YR.StartSwing()
    YR.StartRecap()
    YR.StartChatLog()
    YR.StartLootFeed()
    YR.StartQuestLFG()
    YR.StartAlts()
    YR.StartCraftRemind()
    YR.StartQuickGroup()
    if YR.Style then YR.Style.Changed = YR.SettingChanged end
    YR:BuildMinimapButton()
    YR:BuildOptions()   -- last: Blizzard's options API is the part most likely to differ on this client
    -- every part that is wanted comes on at the login proper, when every other addon is in too (what
    -- another addon does decides some of our defaults) and the character can be asked about
    -- scan results still in the account's file: the window's addon is loaded once, a little after the
    -- login, so they move to its file (after that this never runs again)
    if YippRouteDB.scan ~= nil then
        C_Timer.After(10, function() if YippRouteDB.scan ~= nil and not InCombatLockdown() then YR.LoadWindow() end end)
    end
    if IsLoggedIn and IsLoggedIn() then
        YR.partsReady = true
        YR.ApplyParts()
    else
        f:RegisterEvent("PLAYER_LOGIN")
    end
end)
