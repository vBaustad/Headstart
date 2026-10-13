-- Journey: the story of this character's road, counted as you play. Not a combat meter: where you went,
-- how far, how long, what you earned and what you found.
--   Kept per character (HeadstartJourney), as totals only - no row is written per event or per second,
--   so it stays a few kilobytes however long you play:
--     t      seconds: all, and of those afk, dead, taxi (flying), combat, rest (in a town or inn) and
--            road (everything else); swim, ride (mounted) and inst (in a dungeon) counted beside them
--     d      yards: foot, ride (on a mount), swim, taxi, ghost
--     zone   [zone name] = seconds there
--     hours  [0..23] = seconds played in that hour of the day;  days  [date] = true
--     gold   earned: loot, quest, vendor, mail, other;  spent: vendor, repair, train, flight, other;
--            peak (the most you ever carried)
--     loot   n, q = [quality] = count, best = { link, q, ilvl, zone, at }
--     kills, mobs = [name] = count, xpKill, xpQuest, quests, deaths, deathZone = [zone] = count
--     mobId  [name] = the creature's ID, read off your target when it is the one that died: the
--            window draws that creature's portrait from it
--     levels [level] = { at (the clock), t (seconds played here when you reached it), zone }
--     need   [level] = the XP that level takes (so a level's pace is XP an hour, not just its minutes)
--     flights, hearths, jumps, groups, mates = [name] = true
--     chat   [kind] = messages you sent (SAY, PARTY, GUILD, WHISPER, ...): how many, never what
--     ride   { level, at, t }: when you learned to ride (seen = true: not found as a skill, so it is
--            the first time you were seen mounted); { before = true }: could ride before logging began.
--            walked = true: this character has been seen unable to ride, so a later "can" is a moment
--     sessions, longest (seconds), since (first day logged), seen (last second logged)
--   How it is counted: once a second, where you are and what you are doing (one look, a handful of
--   reads); the rest from the game's own events - money by the window that was open when it changed,
--   loot and kills from the lines the game writes in chat. Distance is the straight line between two
--   looks a second apart; a jump too long to have been travelled (a hearth, a portal, a boat's loading
--   screen) is not counted. In a dungeon the game gives no position (and is not asked for one): time
--   is counted there, yards not.
--   On unless turned off (YippRouteDB.journey == false): it shows nothing and does nothing for you, and
--   a journey can only be told if it was counted from the start. What that costs a new install is a
--   look a second and the handful of events below; money is read at that look rather than listened
--   for. Off, nothing is listened for, counted or made.
--   The journey is told at level 20, 30, 40, 50 and 60 and at no other: reaching one writes a chapter
--   (chapters[level]), the totals as they stood that moment - a copy of the tables above, with only
--   the dozen mobs met most and the days as a count (a few kilobytes each, five at most). The window
--   tells the latest chapter, and the ones before it; what you did since is in the next. A small note
--   comes up for a few seconds as a chapter is written ("click to look back"): click it for the
--   window, right-click or leave it and it goes (journeyToast == false: no note; the chapter is
--   written all the same).
--   The window that tells it is in Headstart_Options (Journey.lua there): /hs journey.
local ADDON, YR = ...

local J                         -- this character's record, while it is on
local last, lastX, lastY, lastWhere
local money, session = nil, 0
local onTaxi, inGroup = false, false
local merchant, trainer, taxiMap, mail = false, false, false, false
local lootUntil, repairUntil, questOwed = 0, 0, 0
local jumpHooked, repairHooked, chatHooked
local hourAt, hourNow = 0, 0

local function Wanted() return YR.QoLOn() and YippRouteDB.journey ~= false end
YR.JourneyOn = Wanted

local function Record()
    local j = _G.HeadstartJourney
    if type(j) ~= "table" then
        j = {}
        _G.HeadstartJourney = j
    end
    for _, k in ipairs({ "t", "d", "zone", "hours", "days", "gold", "spent", "loot", "mobs", "deathZone", "levels", "mates", "need", "chat", "mobId", "chapters" }) do
        if type(j[k]) ~= "table" then j[k] = {} end
    end
    if type(j.loot.q) ~= "table" then j.loot.q = {} end
    j.since = j.since or time()
    return j
end

local function Add(t, key, by) t[key] = (t[key] or 0) + by end
local function Plain(v) return YR.Open(v) end
local function Zone()
    local z = GetRealZoneText()
    return type(z) == "string" and z ~= "" and z or "Unknown"
end

-- Money changed since the last look: named by what was open, or what had just happened.
local function Money()
    local now = GetMoney()
    if not Plain(now) or type(now) ~= "number" then return end
    local by = now - (money or now)
    money = now
    if now > (J.gold.peak or 0) then J.gold.peak = now end
    if by == 0 then return end
    local clock = GetTime()
    if by > 0 then
        if questOwed > 0 then
            local part = math.min(by, questOwed)
            questOwed = questOwed - part
            Add(J.gold, "quest", part)
            by = by - part
            if by <= 0 then return end
        end
        Add(J.gold, clock <= lootUntil and "loot" or merchant and "vendor" or mail and "mail" or "other", by)
    else
        by = -by
        Add(J.spent, trainer and "train" or taxiMap and "flight" or (merchant and clock <= repairUntil) and "repair"
            or merchant and "vendor" or "other", by)
    end
end

-- Riding: every spell of the client's Riding skill line (762 in its skill data - Apprentice and
-- Journeyman Riding, and the old one-per-animal skills). Knowing any of them is being able to ride.
local RIDING = { 33388, 33391, 824, 825, 826, 828, 10861, 10906, 10907, 18995, 1285849 }
local function Rides()
    if type(IsPlayerSpell) ~= "function" then return false end
    for _, id in ipairs(RIDING) do
        local ok, yes = pcall(IsPlayerSpell, id)
        if ok and Plain(yes) == true then return true end
    end
    return false
end
-- When this character learned to ride. Looked for as a session starts, at a new level and when a
-- trainer's window shuts (riding is bought from one); mounted: you are in the saddle right now, which
-- says the same should the skill not be found by its spells. Only a character seen unable to ride
-- first has a moment to tell: one that could ride before anything was logged has none (before) - and
-- being seen mounted proves nothing about when on a character first logged at 40 or over.
local function Saddle(mounted)
    if J.ride then return end
    local known = Rides()
    if not (known or mounted) then
        J.walked = true
    elseif J.walked and (known or (J.first or 1) < 40) then
        J.ride = { level = UnitLevel("player"), at = time(), t = J.t.all or 0, seen = (not known) or nil }
    else
        J.ride = { before = true }
    end
end

-- Once a second: what this second was, and how far you came in it.
local function Tick()
    if not J then return end
    local now = GetTime()
    local dt = now - (last or now)
    last = now
    if dt <= 0 then return end
    if dt > 5 then dt = 1 end           -- (a loading screen, a stall: not counted as five seconds of anything)
    local t = J.t
    Add(t, "all", dt)
    local afk, dead = Plain(UnitIsAFK("player")), Plain(UnitIsDeadOrGhost("player"))
    local taxi, combat = Plain(UnitOnTaxi("player")), Plain(UnitAffectingCombat("player"))
    local swim, rest, inst = IsSwimming(), IsResting(), IsInInstance()
    local mounted = not taxi and Plain(IsMounted()) and true or false
    Add(t, afk and "afk" or dead and "dead" or taxi and "taxi" or combat and "combat" or rest and "rest" or "road", dt)
    if swim then Add(t, "swim", dt) end
    if mounted then
        Add(t, "ride", dt)
        if not J.ride then Saddle(true) end
    end
    if inst then Add(t, "inst", dt) end
    Add(J.zone, Zone(), dt)
    if now - hourAt > 60 then hourAt, hourNow = now, tonumber(date("%H")) or 0 end
    Add(J.hours, hourNow, dt)
    -- what this level takes, so a level's time can be weighed against its size once it is done
    local level, most = UnitLevel("player"), UnitXPMax("player")
    if type(level) == "number" and type(most) == "number" and Plain(most) and most > 0 then J.need[level] = most end
    session = session + dt
    if session > (J.longest or 0) then J.longest = session end
    J.seen = time()
    Money()
    if taxi and not onTaxi then Add(J, "flights", 1) end
    onTaxi = taxi and true or false
    -- how far: the straight line from where you were a second ago
    local y, x, where, _
    if not inst then y, x, _, where = UnitPosition("player") end
    if Plain(x) and Plain(y) and type(x) == "number" then
        if lastX and lastWhere == where then
            local far = math.sqrt((x - lastX) ^ 2 + (y - lastY) ^ 2)
            if far > 0.05 and far < (taxi and 120 or 45) * math.max(dt, 1) then
                Add(J.d, taxi and "taxi" or dead and "ghost" or swim and "swim" or mounted and "ride" or "foot", far)
            end
        end
        lastX, lastY, lastWhere = x, y, where
    else
        lastX = nil
    end
end

local function Looted(msg)
    msg = Plain(msg)
    if type(msg) ~= "string" then return end
    local link, n = YR.LootFromText(msg)
    if not link then return end
    local loot = J.loot
    Add(loot, "n", n or 1)
    local get = type(C_Item) == "table" and C_Item.GetItemInfo or GetItemInfo
    local ok, _, _, quality, level = pcall(get, link)
    if not ok or type(quality) ~= "number" then return end      -- (an item the client has no data for yet: counted, not ranked)
    Add(loot.q, quality, n or 1)
    local best = loot.best
    if not best or quality > (best.q or -1) or (quality == best.q and (level or 0) > (best.ilvl or 0)) then
        loot.best = { link = link, q = quality, ilvl = level or 0, zone = Zone(), at = time() }
    end
end

local KILL
local function Killed(msg)
    msg = Plain(msg)
    if type(msg) ~= "string" then return end
    if KILL == nil then
        -- the game's own sentence ("%s dies, you gain %d experience."), made into a pattern for the name
        local fmt = _G.COMBATLOG_XPGAIN_FIRSTPERSON
        KILL = false
        if type(fmt) == "string" then
            local p = fmt:gsub("([%(%)%.%[%]%-%+%*%?%^%$])", "%%%1")
            KILL = "^" .. p:gsub("%%%d?%$?s", "(.+)"):gsub("%%%d?%$?d", "(%%d+)")
        end
    end
    local name, xp = msg:match(KILL or "^(.+) dies, you gain (%d+)")
    if not name then return end
    Add(J, "kills", 1)
    Add(J, "xpKill", tonumber(xp) or 0)
    -- (a few hundred names at most: a new one past that is counted as a kill, not by name)
    if J.mobs[name] or (J.mobCount or 0) < 400 then
        if not J.mobs[name] then J.mobCount = (J.mobCount or 0) + 1 end
        Add(J.mobs, name, 1)
        -- whose face that is: its creature ID, off your target if your target is the one that died
        -- (in a dungeon the game keeps a unit's identity to itself, and then there is none)
        if not J.mobId[name] then
            local who = Plain(UnitName("target"))
            local guid = who == name and Plain(UnitGUID("target"))
            if type(guid) == "string" then
                local kind, _, _, _, _, id = strsplit("-", guid)
                id = (kind == "Creature" or kind == "Vehicle") and tonumber(id)
                if id then J.mobId[name] = id end
            end
        end
    end
end

local function Group()
    local now = IsInGroup() and true or false
    if now and not inGroup then Add(J, "groups", 1) end
    inGroup = now
    if not now then return end
    local raid = IsInRaid()
    for i = 1, GetNumGroupMembers() do
        local name = Plain(UnitName((raid and "raid" or "party") .. i))
        if type(name) == "string" and not J.mates[name] and (J.mateCount or 0) < 1000 then
            J.mates[name] = true
            J.mateCount = (J.mateCount or 0) + 1
        end
    end
end

-- A chapter: the journey as it stands now, kept as it is told at a milestone. Everything the window
-- reads, copied - what is counted on after this must not change what was told.
local function Copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and Copy(v) or v end
    return out
end
local KEPT = { "since", "first", "sessions", "longest", "flights", "hearths", "jumps", "groups", "mateCount", "kills", "quests",
    "deaths", "xpKill", "xpQuest", "walked", "t", "d", "zone", "hours", "gold", "spent", "loot", "deathZone", "levels", "need", "chat", "ride" }
local function Chapter(level)
    local c = { level = level, at = time(), mobs = {}, mobId = {} }
    for _, k in ipairs(KEPT) do
        local v = J[k]
        if type(v) == "table" then c[k] = Copy(v) else c[k] = v end
    end
    local days = 0
    for _ in pairs(J.days) do days = days + 1 end
    c.dayCount = days
    -- the dozen mobs met most (the whole list is a few hundred names), each with its face if it is known
    local met = {}
    for name, n in pairs(J.mobs) do met[#met + 1] = { name, n } end
    table.sort(met, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    for i = 1, math.min(12, #met) do
        c.mobs[met[i][1]] = met[i][2]
        c.mobId[met[i][1]] = J.mobId[met[i][1]]
    end
    return c
end

-- The note at a milestone level: small, at the top of the screen, gone by itself.
local MILESTONES = { [20] = true, [30] = true, [40] = true, [50] = true, [60] = true }
local toast, toastTurn = nil, 0
function YR.JourneyToast(level)
    if YippRouteDB.journeyToast == false then return end
    if not toast then
        toast = CreateFrame("Button", "HeadstartJourneyToast", UIParent, "BackdropTemplate")
        toast:SetSize(336, 58)
        toast:SetPoint("TOP", 0, -150)
        toast:SetFrameStrata("HIGH")
        toast:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        toast:SetBackdropColor(0.07, 0.05, 0.03, 0.92)
        toast:SetBackdropBorderColor(0.85, 0.68, 0.30, 1)
        toast.icon = toast:CreateTexture(nil, "ARTWORK")
        toast.icon:SetSize(38, 38)
        toast.icon:SetPoint("LEFT", 10, 0)
        toast.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
        toast.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        toast.title = toast:CreateFontString(nil, "OVERLAY")
        toast.title:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
        toast.title:SetTextColor(1, 0.82, 0.25)
        toast.title:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 10, -2)
        toast.text = toast:CreateFontString(nil, "OVERLAY")
        toast.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
        toast.text:SetTextColor(0.90, 0.86, 0.78)
        toast.text:SetPoint("TOPLEFT", toast.title, "BOTTOMLEFT", 0, -4)
        toast.text:SetText("Curious how the road has been? Click to look back.")
        toast:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        toast:SetScript("OnClick", function(self, button)
            self:Hide()
            if button == "LeftButton" then YR.JourneyOpen() end
        end)
        toast.fade = toast:CreateAnimationGroup()
        local arrive = toast.fade:CreateAnimation("Alpha")
        arrive:SetFromAlpha(0)
        arrive:SetToAlpha(1)
        arrive:SetDuration(0.5)
    end
    toast.title:SetText(level >= 60 and "Level 60. You made it." or ("Level %d!"):format(level))
    toast.text:SetText(level >= 60 and "The road is walked. Click to see all of it." or "A new chapter of your journey. Click to look back.")
    toastTurn = toastTurn + 1
    local mine = toastTurn
    toast:Show()
    toast.fade:Play()
    C_Timer.After(15, function() if toastTurn == mine then toast:Hide() end end)
end

local function OnEvent(_, event, a, b, c)
    if not J then return end
    if event == "CHAT_MSG_LOOT" then
        Looted(a)
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        Killed(a)
    elseif event == "QUEST_TURNED_IN" then
        Add(J, "quests", 1)
        if type(b) == "number" and Plain(b) then Add(J, "xpQuest", b) end
        if type(c) == "number" and Plain(c) and c > 0 then questOwed = questOwed + c end
    elseif event == "PLAYER_DEAD" then
        Add(J, "deaths", 1)
        Add(J.deathZone, Zone(), 1)
    elseif event == "PLAYER_LEVEL_UP" then
        if type(a) == "number" and Plain(a) then
            J.levels[a] = { at = time(), t = J.t.all or 0, zone = Zone() }
            Saddle()
            if MILESTONES[a] then
                J.chapters[a] = Chapter(a)
                YR.JourneyToast(a)
            end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if Plain(c) == 8690 then Add(J, "hearths", 1) end
    elseif event == "GROUP_ROSTER_UPDATE" then
        Group()
    elseif event == "MERCHANT_SHOW" then merchant = true
    elseif event == "MERCHANT_CLOSED" then merchant = false
    elseif event == "TRAINER_SHOW" then trainer = true
    elseif event == "TRAINER_CLOSED" then
        trainer = false
        Saddle()
    elseif event == "TAXIMAP_OPENED" then taxiMap = true
    elseif event == "TAXIMAP_CLOSED" then taxiMap = false
    elseif event == "MAIL_SHOW" then mail = true
    elseif event == "MAIL_CLOSED" then mail = false
    elseif event == "LOOT_OPENED" then lootUntil = GetTime() + 600
    elseif event == "LOOT_CLOSED" then lootUntil = GetTime() + 1.5     -- (the coin can land just after the window shuts)
    end
end

local function Begin()
    J = Record()
    last, lastX, session = GetTime(), nil, 0
    money = Plain(GetMoney())
    if type(money) ~= "number" then money = nil end
    onTaxi = Plain(UnitOnTaxi("player")) and true or false
    inGroup = IsInGroup() and true or false
    -- a new session: the first time, or back after more than five minutes away (a /reload is not one)
    if not J.seen or time() - J.seen > 300 then Add(J, "sessions", 1) end
    J.seen = time()
    J.days[date("%Y-%m-%d")] = true
    -- the level you are when it starts, so the first level reached has something to be measured from
    local level = UnitLevel("player")
    if type(level) == "number" and not J.first then J.first = level end
    J.mount = nil               -- (an earlier build's guess at this: the first time 100 gold was carried)
    Saddle()
    if not jumpHooked then
        jumpHooked = true
        hooksecurefunc("JumpOrAscendStart", function() if J then Add(J, "jumps", 1) end end)
    end
    if not repairHooked then
        repairHooked = true
        hooksecurefunc("RepairAllItems", function() repairUntil = GetTime() + 2 end)
    end
    -- what you wrote, by where you wrote it: counted as it is sent (the kind only; never a word of it)
    if not chatHooked and type(C_ChatInfo) == "table" and type(C_ChatInfo.SendChatMessage) == "function" then
        chatHooked = true
        hooksecurefunc(C_ChatInfo, "SendChatMessage", function(_, kind)
            if not J then return end
            kind = Plain(kind)
            if kind == nil then kind = "SAY" end
            if type(kind) == "string" and kind ~= "AFK" and kind ~= "DND" then Add(J.chat, kind:upper(), 1) end
        end)
    end
end
local function End() J = nil end

--- This character's journey so far (nil while it is off and nothing was ever logged).
function YR.JourneyData()
    if J then return J end
    local j = _G.HeadstartJourney
    return type(j) == "table" and type(j.t) == "table" and j or nil
end
--- Everything logged for this character forgotten; it starts again from now if it is on.
function YR.JourneyReset()
    _G.HeadstartJourney = nil
    if J then Begin() end
end
--- Shown (the window is in Headstart_Options).
function YR.JourneyOpen()
    if YR.LoadWindow() and YR.JourneyShow then YR.JourneyShow() end
end

local declared
function YR.StartJourney()
    if declared then return end
    declared = true
    YR.Part(Wanted, { "CHAT_MSG_LOOT", "CHAT_MSG_COMBAT_XP_GAIN", "QUEST_TURNED_IN", "PLAYER_DEAD", "PLAYER_LEVEL_UP",
        { "UNIT_SPELLCAST_SUCCEEDED", "player" }, "GROUP_ROSTER_UPDATE", "MERCHANT_SHOW", "MERCHANT_CLOSED",
        "TRAINER_SHOW", "TRAINER_CLOSED", "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "LOOT_OPENED", "LOOT_CLOSED" },
        OnEvent, { start = Begin, stop = End, tick = Tick, every = 1 })
end
