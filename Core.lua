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
    buyLater = true, sellGuard = true, groupPanel = true, groupAccept = true, groupShare = true, skipQuests = true, paceWatch = true }

function YR.QoLOn()
    return YippRouteDB.qolOff ~= true
end

--- Whether this is a test client - the beta. What is set up here is kept in that client's own
--- folder, which the live game never reads: the window says so while it is one (Editor.lua, the
--- banner on All features). The game says it is a beta build; a realm with "beta" in its name
--- says the same where it doesn't.
function YR.BetaClient()
    if type(IsBetaBuild) == "function" then
        local ok, yes = pcall(IsBetaBuild)
        if ok and yes then return true end
    end
    local realm = GetRealmName and GetRealmName()
    return type(realm) == "string" and realm:lower():find("beta", 1, true) ~= nil
end

--- Money as the game writes it (a number and a coin for gold, silver and copper), or in letters
--- ("1g 20s 40c") where it can't. The game's function is C_CurrencyInfo.GetCoinTextureString on this
--- client: the old global of that name is not there, and what asked for it by that name printed
--- "2134c" or "0.21g" instead.
function YR.Money(copper)
    copper = math.floor((tonumber(copper) or 0) + 0.5)
    local coins = (type(C_CurrencyInfo) == "table" and C_CurrencyInfo.GetCoinTextureString) or _G.GetCoinTextureString
    if type(coins) == "function" then
        local ok, text = pcall(coins, copper)
        if ok and type(text) == "string" then return text end
    end
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    if g > 0 then return ("%dg %ds %dc"):format(g, s, c) end
    if s > 0 then return ("%ds %dc"):format(s, c) end
    return c .. "c"
end

--- A pattern from one of the game's own sentences ("%s dies, you gain %d experience."): "%s" a text,
--- "%d" a number, the rest literal - so what is read works in any language. Other languages number
--- their blanks ("%1$s ... %2$d"), and may turn them round ("%2$d ... %1$s"): the number is taken out
--- first (escaped with the rest, its "$" left "%1" in the pattern, which is no pattern at all - every
--- such line raised an error in those languages), and the order the blanks stand in is the second
--- value where it is not 1, 2, 3 (YR.SentenceMatch puts what was read back in the blanks' own order).
--- loose: not anchored at either end.
function YR.SentencePattern(fmt, loose)
    if type(fmt) ~= "string" then return nil end
    local order, n, turned = {}, 0, false
    for pos in fmt:gmatch("%%(%d?)%$?[sd]") do
        n = n + 1
        order[n] = tonumber(pos) or n
        if order[n] ~= n then turned = true end
    end
    local p = fmt:gsub("%%%d%$", "%%")
    p = p:gsub("([%(%)%.%[%]%-%+%*%?%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return loose and p or ("^" .. p .. "$"), turned and order or nil
end

--- What a sentence's blanks hold in msg (up to three), in the blanks' own order.
function YR.SentenceMatch(msg, pattern, order)
    local a, b, c = msg:match(pattern)
    if not order or a == nil then return a, b, c end
    local got, out = { a, b, c }, {}
    for i = 1, 3 do if order[i] then out[order[i]] = got[i] end end
    return out[1], out[2], out[3]
end

--- Quality of life on or off, for the whole account. What's on screen follows at once where it can;
--- the rest (hooks already made, bars already built) follows a /reload.
function YR.SetQoLOn(on)
    local was = YR.QoLOn()
    YippRouteDB.qolOff = (not on) and true or nil
    if (on and true or false) == was then return end
    for _, apply in ipairs({ "XPBarApply", "TalentFadeApply", "InstanceHudApply", "RXPSkinApply", "DamageSkinApply", "BarHideApply", "SwingApply", "WindowScaleApply", "RecapApply", "ChatLogApply", "LootFeedApply", "TalentNotice" }) do
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
    -- chat put back in the windows after a reload (ChatLog.lua): two doing it is every line twice
    chatRestore = { { "Leatrix Plus", function() return Leatrix("RestoreChatMessages") end } },
    blizzardBars ={ { "EllesmereUI", function() return Loaded("EllesmereUIActionBars") end } },
    windowScale = { { "EllesmereUI", function() return Loaded("EllesmereUIQoL") and Flat("EllesmereUIDB", "shifterEnabled") == true end } },
    moveBag = {
        { "EllesmereUI", function() return Loaded("EllesmereUIBags") end },
        { "Baganator", function() return Loaded("Baganator") end },
    },
    swing = {
        { "EllesmereUI", function() return Loaded("EllesmereUIResourceBars") and InProfiles("EllesmereUIResourceBarsDB", "swingTimer", "enabled") == true end },
        { "Naowh Forever", function() return Loaded("NaowhForever") end },
        { "AppelSwingsForever", function() return Loaded("AppelSwingsForever") end },
    },
    whisperSound = { { "EllesmereUI", function() return Loaded("EllesmereUIChat") end } },
    lootFeed = { { "Naowh Forever", function() return Loaded("NaowhForever") end } },
    -- (Naowh Forever's Glimmer is an addon of its own beside it; the other two do nothing else)
    glimmer = {
        { "Naowh Forever", function() return Loaded("NaowhForever_Glimmer") end },
        { "Forever Loot Sparkles", function() return Loaded("ForeverLootSparkles") end },
        { "Lueur", function() return Loaded("Lueur") end },
    },
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
--   The one thing done for you unasked is a cinematic skipped (Cinematic.lua; the user's choice,
--   2026-10-13): it takes nothing and changes nothing of yours, and says in chat that it did.
--   The buttons under the bank and mail windows are ours on Blizzard's windows (and float on their own
--   where a bag addon hides the bank's). The routes' own automation - release at a death skip, abandon
--   a skipped quest, share and accept route quests - acts for you, so turning the routes on is not
--   enough to turn those on. (Quest rewards are picked per class, off the same way: Rewards.lua.)
local STARTS_OFF = { autoTrain = true, restock = true, bankAuto = true, levelShot = true, trinketBar = true,
    groupBar = true, upgrades = true, talentMove = true, talentFadeSlider = true, xpbar = true,
    deathRecap = true, chatLog = true, lootFeed = true, questLFG = true, alts = true, glimmer = true, instanceTrack = true,
    boatTimer = true,
    npcMarkers = true,                      -- (the nameplate markers, NpcMarkers.lua)
    paceWatch = true,                       -- (the level pace box under the guide, Pace.lua)
    bankButton = true, mailButton = true, deathSkipRelease = true, skipQuests = true, groupShare = true, groupAccept = true }
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
-- What is the routes' own: with the routes off none of it runs, whatever it is set to. (Recording and
-- the splits box ran on with the routes off on every account that had them written down as on - the
-- routes' page then says "none of it runs", and had no switch left to stop them.)
local ROUTES_OWN = { logging = true, showSplits = true, deathSkipRelease = true, campReminder = true, buyLater = true,
    sellGuard = true, groupPanel = true, groupAccept = true, groupShare = true, skipQuests = true, paceWatch = true }
function YR.Option(key)
    if YippRouteDB.qolOff == true and not LEVELLING[key] then return false end
    if ROUTES_OWN[key] and YR.RoutesOn and not YR.RoutesOn() then return false end
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

local function Look(p)
    local want = p.want() and true or false
    if want ~= p.on then
        p.on = want
        if want then PartOn(p) else PartOff(p) end
    elseif want and p.opt.again then
        p.opt.again(p)                          -- still on, and a setting changed: as it is now
    end
end

function YR.ApplyParts()
    partsSoon = false
    if not YR.partsReady then return end            -- before the login: nothing is on yet
    for _, p in ipairs(parts) do
        -- Each by itself: a part that fails (a frame of Blizzard's that another build hasn't got) must
        -- not leave every part declared after it as it was until a reload. The error is not lost: it
        -- is raised again a moment later, by itself, for the game and any error catcher to show.
        local ok, err = pcall(Look, p)
        if not ok then
            YR.partError = err                      -- (the last one, for the tests)
            C_Timer.After(0, function() error(err, 0) end)
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
-- Put back everything Headstart changed (General page, Character setup, /headstart putback), for whoever
-- fears for the screen they had (the owner, 2026-10-15): Character setup puts this character's bars, macros
-- and interface back as they were before its first change (Headstart_Setup, YS.PutBackEverything), then
-- quality of life and Character setup go off - each feature puts back what it changed as it goes off.
-- The levelling routes stay: they change nothing on the screen. Asked first.
function YR.PutBackEverything()
    if InCombatLockdown() then YR.Print("not in a fight: put it back when the fight is over.") return false end
    local c = YippSetupCharDB
    if type(c) == "table" and c.first then
        -- (Character setup may be off, and its addon not loaded: what it changed is still its to put back)
        if not (YR.LoadSetup(true) and YR.Setup.PutBackEverything) then return false end
        if YR.Setup.PutBackEverything() == false then return false end      -- (it said why; nothing is changed)
    end
    YR.SetSetupOn(false)
    YR.SetQoLOn(false)
    YR.Print("put back: quality of life and Character setup are off. The levelling routes stay (Levelling tab).")
    if YR.RefreshWindow then YR:RefreshWindow() end
    return true
end

-- (the question made the first time it is asked)
local PUTBACK = {
    text = "Headstart: put back everything it changed?\n\nQuality of life and Character setup go off, and each feature puts"
        .. " back what it changed. On this character, the bars, macros, key bindings, game settings, Edit Mode layout and"
        .. " chat windows go back to how they were before Headstart first changed them (an addon can't place mounts or"
        .. " toys on bars).\n\nOther characters: log in on each and put back there too. The levelling routes stay.",
    button1 = "Put back",
    button2 = "Cancel",
    OnAccept = function() YR.PutBackEverything() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}
function YR.AskPutBack()
    StaticPopupDialogs["HEADSTART_PUTBACK"] = StaticPopupDialogs["HEADSTART_PUTBACK"] or PUTBACK
    StaticPopup_Show("HEADSTART_PUTBACK")
end

function YR:ToggleWindow(page) if YR.LoadWindow() then YR:ToggleWindow(page) end end
function YR:ToggleSettings() if YR.LoadWindow() then YR:ToggleSettings() end end
function YR:ShowSettingsTab(key) if YR.LoadWindow() then YR:ShowSettingsTab(key) end end
--- A new install is shown around once: the tour (hints over Headstart's window), a few seconds after
--- the first login and not in a fight (the next login, then). Welcome.lua, in the window's addon.
--- It is put up when the screen is really there, and counts as seen only once it has stayed up for a
--- few seconds or been answered. (A new character's first login plays its flight over the zone with
--- the interface hidden: the window was put up under it, the Escape that ended the flight closed it
--- with every other window, and it was written down as seen without ever having been - the user,
--- 2026-10-13, a new install's very first login.) Closed before that, it is put up once more; still
--- not seen, the next login asks again.
--- What Headstart says by itself at a login (the reminders: trainer, talents, repairs, crafts) waits on
--- that login until the welcome is answered or closed: the first thing on a new install is the question
--- of what to turn on, not four lines from things nobody turned on yet (YR.AfterWelcome).
local welcomeLive, welcomeLooking, afterWelcome, welcomeHooked = false, false, nil, false
local function WelcomeDone()
    if not welcomeLive or welcomeLooking then return end
    local win = _G.HeadstartTour
    if win and win:IsVisible() then
        -- still up (seen, not yet answered): when it goes
        if not welcomeHooked then
            welcomeHooked = true
            win:HookScript("OnHide", function() C_Timer.After(0, WelcomeDone) end)
        end
        return
    end
    welcomeLive = false
    local list = afterWelcome
    afterWelcome = nil
    for _, fn in ipairs(list or {}) do C_Timer.After(3, fn) end
end
--- fn now, or a few seconds after the welcome of this login is answered or closed.
function YR.AfterWelcome(fn)
    if not welcomeLive then fn() return end
    afterWelcome = afterWelcome or {}
    afterWelcome[#afterWelcome + 1] = fn
end
--- Whether this login's welcome is still to be answered (what would speak up by itself waits).
function YR.WelcomeHolds() return welcomeLive end

function YR.WelcomeFirst()
    local db = YippRouteDB
    if not db.welcome or db.welcomeSeen then return end
    welcomeLive, welcomeLooking = true, true
    local looks, shows, up = 0, 0, 0
    local function Stop()
        welcomeLooking = false
        WelcomeDone()
    end
    local function Look()
        if db.welcomeSeen then return Stop() end
        looks = looks + 1
        local win = _G.HeadstartTour
        local showing = win and win:IsVisible() or false
        if showing then
            up = up + 1
            if up >= 2 then
                db.welcomeSeen = true
                return Stop()               -- (what waits: once it is closed or answered)
            end
        else
            up = 0
            local there = UIParent:IsVisible() and not (InCinematic and InCinematic()) and not InCombatLockdown()
            if there and shows < 2 then
                shows = shows + 1
                if YR.LoadWindow() and YR.WelcomeShow then
                    YR.WelcomeShow(true)
                    showing = true
                else
                    shows = 2           -- the window's addon isn't there (said once, in chat): not asked for again
                end
            end
        end
        -- (two minutes of looking at most, and none once it has been closed twice)
        if looks < 60 and (showing or shows < 2) then C_Timer.After(2, Look) else Stop() end
    end
    C_Timer.After(5, Look)
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
        if arg == "id" then YR.InstanceIDDebug() elseif YR.LoadWindow() then YR.InstanceLogToggle() end
    elseif cmd == "glimmer" then
        YR.GlimmerDebug()
    elseif cmd == "repair" then
        YR.RepairDebug()
    elseif cmd == "boats" then
        YR.BoatsCommand(arg)
    elseif cmd == "putback" then
        YR.AskPutBack()
    elseif cmd == "perf" then
        -- what Headstart costs, by the game's own count (the code for it is in the window's addon)
        if YR.LoadWindow() then YR.Perf() end
    elseif cmd == "transfer" or cmd == "export" or cmd == "import" then
        -- your settings as a text, to take to another install (the live game, another computer)
        if YR.LoadWindow() and YR.TransferShow then YR.TransferShow(cmd ~= "transfer" and cmd or nil) end
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
    elseif cmd == "move" or cmd == "arrange" then
        YR.ArrangeToggle()
    elseif cmd == "journey" then
        if arg == "toast" then
            YR.JourneyToast(UnitLevel("player") or 20)
        elseif arg and arg:find("^test") then
            -- a made-up journey, told at one of the levels a chapter is written at (50 unless one is
            -- given: /hs journey test 60)
            local level = math.max(20, math.min(60, math.floor((tonumber(arg:match("(%d+)")) or 50) / 10) * 10))
            YR.JourneyToast(level)
            if YR.LoadWindow() and YR.JourneyShow then YR.JourneyShow(level) end
        elseif arg == "live" then
            -- the running totals as they stand now, told as if a chapter were written this minute
            if YR.LoadWindow() and YR.JourneyShow then YR.JourneyShow(nil, "live") end
        elseif arg == "on" or arg == "off" then
            if arg == "on" then YippRouteDB.journey = nil else YippRouteDB.journey = false end
            YR.ApplyParts()
            YR.Print("Journey is " .. arg .. ".")
        else
            YR.JourneyOpen()
        end
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
            .. " /headstart upgrades - look through your bags for better gear; /headstart death - what happened the last time you died; /headstart chat - the chat log; /headstart loot - the loot log; /headstart perf - what Headstart costs, measured by the game; /headstart alts - your other characters' bags, bank, gold and currencies (/headstart gold: just the gold); /headstart profile [name] - switch this character to another of the class's profiles; /headstart macro - the macro helper: your class's usual macros made by ticking boxes; /headstart start - the welcome window: pick how much of Headstart you want; /headstart transfer - your settings as a text, to move them to another install; /headstart putback - put back everything Headstart changed (asks first)")
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
local WAS_ON_3 = { "bankButton", "mailButton", "deathSkipRelease", "skipQuests", "groupShare", "groupAccept" }
-- "On, unless another addon did it" cannot be answered as Headstart loads: the addons that sort after
-- it (Leatrix Plus, Naowh Forever, NovaInstanceTracker) are not in yet, and each of these was written
-- down as on whatever they did - for good, since the latch runs once. So those keys wait for the login
-- (YR.LatchOthers); until then they are unset, which reads as off, and no part is on before the login.
local latchLater = {}
function YR.LatchOthers()
    local db = YippRouteDB
    if #latchLater == 0 then return end
    YR.EllesmereForget()                            -- (what another addon has, asked afresh)
    for _, key in ipairs(latchLater) do
        if key == "xpbar" then
            if type(db.xpbar) ~= "table" then db.xpbar = {} end
            if db.xpbar.on == nil then db.xpbar.on = YR.OtherHas("xpbar") == nil end
        elseif db[key] == nil then
            db[key] = YR.OtherHas(key) == nil
        end
    end
    latchLater = {}
end
function YR.Latch(fresh)
    local db = YippRouteDB
    local was = tonumber(db.quiet) or 0
    if was >= 4 then return end
    db.quiet = 4
    -- 4: the instance tracker became something you turn on (the owner, 2026-10-14). An account that had
    -- Headstart keeps it as it was (on, unless another addon did it).
    if not fresh and db.instanceTrack == nil then latchLater[#latchLater + 1] = "instanceTrack" end
    if was >= 3 then return end
    -- 3: the bank and mail buttons, the routes' own automation and quest reward picking became things
    -- you turn on. An account that had Headstart keeps each as it was (on, unless another addon did it).
    if not fresh then
        for _, key in ipairs(WAS_ON_3) do
            if db[key] == nil then latchLater[#latchLater + 1] = key end
        end
        if db.pickRewards == nil then db.pickRewards = true end
    end
    if was >= 2 then return end
    -- 2: Character setup became something you turn on. An account that had Headstart keeps it on.
    if not fresh and db.setupOn == nil then db.setupOn = true end
    if was >= 1 then return end
    if fresh then
        db.welcome = true
        return
    end
    for _, key in ipairs(WAS_ON) do
        if db[key] == nil then latchLater[#latchLater + 1] = key end
    end
    for _, key in ipairs({ "acceptInvites", "whisperInvite", "acceptFrom" }) do
        if db[key] == nil then db[key] = "friends" end
    end
    if db.showSplits == nil then db.showSplits = true end
    if db.logging == nil then db.logging = true end
    if type(db.xpbar) ~= "table" then db.xpbar = {} end
    if db.xpbar.on == nil then latchLater[#latchLater + 1] = "xpbar" end
end

SLASH_HEADSTARTSETTINGS1 = "/hs"
SlashCmdList.HEADSTARTSETTINGS = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "move" or cmd == "arrange" then YR.ArrangeToggle() return end
    if cmd:find("^journey") then SlashCmdList.HEADSTART(cmd) return end
    YR:ToggleSettings()
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
local started
f:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        f:UnregisterEvent("PLAYER_LOGIN")
        YR.LatchOthers()
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
    if YR.TrainerSpellsOnly then YR.TrainerSpellsOnly(class) end       -- (made per class as asked for: Data/TrainerSpells.lua)
    for _, name in ipairs({ "TrainerSpells", "RestockData" }) do
        local t = YR[name]
        if class and type(t) == "table" and t[class] ~= nil then
            for other in pairs(t) do if other ~= class then t[other] = nil end end
        end
    end
    -- Each start by itself: one that fails (a saved value of the wrong shape, a frame of Blizzard's that
    -- another build hasn't got) must not keep everything after it from starting. The error is raised
    -- again a moment later, for the game and any error catcher to show.
    local function Start(fn, ...)
        if type(fn) ~= "function" then return end
        local ok, err = pcall(fn, ...)
        if not ok then
            YR.partError = err
            C_Timer.After(0, function() error(err, 0) end)
        end
    end
    Start(YR.RegisterGuides, YR)
    Start(YR.RegisterExtras, YR)
    Start(YR.StartLog, YR)
    Start(YR.StartRunStore)
    Start(YR.HookTooltips, YR)
    Start(YR.StartSplits, YR)
    Start(YR.StartPace)
    Start(YR.StartGroup, YR)
    Start(YR.StartCamp)
    Start(YR.StartBank)
    Start(YR.StartMail)
    Start(YR.StartRestock)
    Start(YR.StartReminders)
    Start(YR.StartWhisper)
    Start(YR.StartSim)
    Start(YR.StartUpgrades)
    Start(YR.StartTrinkets)
    Start(YR.StartInstances)
    Start(YR.StartXPBar)
    Start(YR.StartRXPSkin)
    Start(YR.StartDamageSkin)
    Start(YR.StartMovers)
    Start(YR.StartTalentFade)
    Start(YR.StartBarHide)
    Start(YR.StartPowerFlash)
    Start(YR.StartSwing)
    Start(YR.StartJourney)
    Start(YR.StartRecap)
    Start(YR.StartChatLog)
    Start(YR.StartLootFeed)
    Start(YR.StartQuestLFG)
    Start(YR.StartAlts)
    Start(YR.StartCraftRemind)
    Start(YR.StartGlimmer)
    Start(YR.StartQuickGroup)
    if YR.Style then YR.Style.Changed = YR.SettingChanged end
    Start(YR.BuildMinimapButton, YR)
    Start(YR.BuildOptions, YR)   -- last: Blizzard's options API is the part most likely to differ on this client
    -- every part that is wanted comes on at the login proper, when every other addon is in too (what
    -- another addon does decides some of our defaults) and the character can be asked about
    -- scan results still in the account's file: the window's addon is loaded once, a little after the
    -- login, so they move to its file (after that this never runs again)
    if YippRouteDB.scan ~= nil then
        C_Timer.After(10, function() if YippRouteDB.scan ~= nil and not InCombatLockdown() then YR.LoadWindow() end end)
    end
    if IsLoggedIn and IsLoggedIn() then
        YR.LatchOthers()
        YR.partsReady = true
        YR.ApplyParts()
    else
        f:RegisterEvent("PLAYER_LOGIN")
    end
end)
