-- Reminders: one quiet chat line when there is something to do about it.
--   * Trainer: at a ding (and once at login) - what your class trainer has for you now and about what
--     it costs. The ranks come from the game's data (Data/TrainerSpells.lua); the prices are only
--     shown at the trainer, so every visit remembers them (YippRouteDB.trainerCosts[CLASS]) and a
--     rank never seen there is counted as "price not known yet".
--   * Talents: at a ding (and once at login) - points you haven't spent.
--   * Durability: when your most worn piece drops under the warning line, once until you repair;
--     and when you come into a town or an inn while it's under the town line, "repair here".
--   * Screenshot at every ding.
-- Account options (YippRouteDB, Settings, QoL), all on unless turned off: remindTrainer,
-- remindTalents, durability, levelShot; durWarn (percent, default 25), durTown (default 50).
local ADDON, YR = ...

local DUR_WARN, DUR_TOWN = 25, 50

local function Class() local _, c = UnitClass("player") return c end

local function RaceBit()
    local _, _, id = UnitRace("player")
    return id and bit.lshift(1, id - 1) or 0
end
YR.RaceBit = RaceBit        -- the Trainer page lists what your race is taught

local function Coins(c) return YR.Money(c) end

-- ---------------------------------------------------------------------------
-- Trainer
-- ---------------------------------------------------------------------------
local function Costs()
    YippRouteDB.trainerCosts = YippRouteDB.trainerCosts or {}
    local c = Class()
    YippRouteDB.trainerCosts[c] = YippRouteDB.trainerCosts[c] or {}
    return YippRouteDB.trainerCosts[c]
end

local function Key(name, rank) return name .. "|" .. (rank or 0) end

--- What the class trainer would teach you at `level` that you don't know yet:
--- { { id, name, rank, level, cost (nil = not seen at a trainer yet) }, ... } by level.
--- A later rank only counts once you know the one before it - which is also what keeps talent
--- spells out until you have taken the talent.
function YR.TrainerMissing(level)
    level = level or UnitLevel("player")
    local race, costs, out = RaceBit(), Costs(), {}
    local list = (YR.TrainerSpells or {})[Class()] or {}
    -- The highest rank of each spell you know. Not "every rank you know": a client that drops the
    -- old rank when it teaches the new one would make rank 2 look missing to a player with rank 3.
    local top = {}
    for _, e in ipairs(list) do
        if IsPlayerSpell(e[1]) and (top[e[3]] or -1) < e[4] then   -- known is known, whatever the race mask says
            top[e[3]] = e[4]
        end
    end
    -- Which ranks the data has for your race at all. A first rank that is another race's copy (the
    -- data has Holy Light 1 for one race only; the others get theirs as a different spell) can't be
    -- checked, so it doesn't block rank 2 - except for a talent, where not knowing rank 1 is the point.
    local mine = {}
    for _, e in ipairs(list) do
        if e[5] == 0 or bit.band(e[5], race) ~= 0 then mine[Key(e[3], e[4])] = true end
    end
    local seen = {}
    for _, e in ipairs(list) do
        local id, lvl, name, rank, mask, talent = e[1], e[2], e[3], e[4], e[5], e[6] == 1
        local k = Key(name, rank)
        local have = top[name]
        local prevOk = rank <= 1 or (have or 0) >= rank - 1
            or (have == nil and not talent and not mine[Key(name, rank - 1)])
        if lvl <= level and (mask == 0 or bit.band(mask, race) ~= 0) and not seen[k]
            and (have == nil or rank > have) and prevOk then
            seen[k] = true
            out[#out + 1] = { id = id, name = name, rank = rank, level = lvl, cost = costs[k] }
        end
    end
    return out
end

--- "Holy Light 3, Seal of Fury" and the price, or nil when there is nothing to learn.
function YR.TrainerLine(level)
    local missing = YR.TrainerMissing(level)
    if #missing == 0 then return nil end
    local names, total, unknown = {}, 0, 0
    for _, m in ipairs(missing) do
        names[#names + 1] = m.rank > 0 and (m.name .. " " .. m.rank) or m.name
        if m.cost then total = total + m.cost else unknown = unknown + 1 end
    end
    local price
    if unknown == #missing then
        price = "prices not known yet"
    else
        price = "about " .. Coins(total) .. (unknown > 0 and (" + " .. unknown .. " not priced yet") or "")
        if GetMoney() < total then price = price .. ", you have " .. Coins(GetMoney()) end
    end
    return ("new at your class trainer: %s (%s)."):format(table.concat(names, ", "), price)
end

--- At a class trainer: remember the price of everything on the list, available or not.
local function ReadTrainer()
    if not (GetNumTrainerServices and YR.TrainerService) then return end
    if IsTradeskillTrainer and IsTradeskillTrainer() then return end
    local costs = Costs()
    for i = 1, GetNumTrainerServices() or 0 do
        local name, rank = YR.TrainerService(i)
        local cost = GetTrainerServiceCost(i)
        if name and cost then
            costs[Key(name, tonumber(type(rank) == "string" and rank:match("(%d+)") or "") or 0)] = cost
        end
    end
end

-- ---------------------------------------------------------------------------
-- Talents
-- ---------------------------------------------------------------------------
--- Talent points not spent yet, or nil when the game won't say. Our own talents are readable with no
--- secrecy gate on Forever: the active config's tree and its currency (what Blizzard's frame shows).
function YR.UnspentTalents()
    local ok, n = pcall(function()
        local config = C_ClassTalents.GetActiveConfigID()
        local info = config and C_Traits.GetConfigInfo(config)
        local tree = info and info.treeIDs and info.treeIDs[1]
        if not tree then return nil end
        local total = 0
        for _, cur in ipairs(C_Traits.GetTreeCurrencyInfo(config, tree, false) or {}) do
            total = total + (cur.quantity or 0)
        end
        return total
    end)
    if ok then return n end
end

-- ---------------------------------------------------------------------------
-- Talent points to spend: said on your screen, not in chat
-- ---------------------------------------------------------------------------
-- A small icon with a line of words beside it, near the top of the screen: no box round it, nothing
-- that takes a click away from the game. It is there while you have a point to spend and are out of
-- a fight, and goes the moment the last point is spent. A click on it puts it away until the number
-- changes (a new level).
--   YippRouteDB.talentNotice: "both" (the icon and the words; as it comes), "text", "icon", or "chat"
--   - the one line in chat this used to be. talentPos = { left, top } once you have moved it (Arrange).
--   Nothing of it is made until there is a point to tell of: its frame, and the three events it
--   listens to while it is up (the talents changing, a fight starting and ending).
local TALENT_ICON = "Interface\\Icons\\Ability_Marksmanship"
local notice, noticeN, noticeAway, noticeSample, noticeHears = nil, 0, nil, false, false

function YR.TalentNoticeMode()
    local m = YippRouteDB.talentNotice
    return (m == "text" or m == "icon" or m == "chat") and m or "both"
end

local function NoticePlace()
    notice:ClearAllPoints()
    local p = YippRouteDB.talentPos
    if type(p) == "table" and p[1] and p[2] then
        notice:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else
        notice:SetPoint("TOP", UIParent, "TOP", 0, -118)
    end
end

local function NoticePaint()
    local mode, n = YR.TalentNoticeMode(), noticeSample and 2 or noticeN
    local words = mode ~= "icon"
    notice.icon:SetShown(mode ~= "text")
    notice.count:SetShown(not words)
    notice.count:SetText(n)
    notice.text:SetShown(words)
    notice.text:SetText(("%d talent point%s to spend"):format(n, n == 1 and "" or "s"))
    notice.text:ClearAllPoints()
    notice.text:SetPoint("LEFT", mode == "text" and 2 or 30, 0)
    local wide = notice.text:GetStringWidth()
    notice:SetSize((mode == "text" and 4 or 32) + (words and (type(wide) == "number" and wide or 150) or 0), 26)
end

local function NoticeBuild()
    notice = CreateFrame("Button", "HeadstartTalentNotice", UIParent)
    notice:SetFrameStrata("MEDIUM")
    notice:SetClampedToScreen(true)
    notice:SetMovable(true)
    notice.icon = notice:CreateTexture(nil, "ARTWORK")
    notice.icon:SetSize(24, 24)
    notice.icon:SetPoint("LEFT", 1, 0)
    notice.icon:SetTexture(TALENT_ICON)
    notice.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    notice.count = notice:CreateFontString(nil, "OVERLAY")
    notice.count:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    notice.count:SetTextColor(1, 1, 1)
    notice.count:SetPoint("BOTTOMRIGHT", notice.icon, "BOTTOMRIGHT", 2, -2)
    notice.text = notice:CreateFontString(nil, "OVERLAY")
    notice.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    notice.text:SetTextColor(1, 0.82, 0.25)
    notice:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    notice:SetScript("OnClick", function(self)
        if noticeSample then return end
        noticeAway = noticeN                -- put away, until there is another number to tell
        self:Hide()
    end)
    notice:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(("%d talent point%s to spend"):format(noticeN, noticeN == 1 and "" or "s"), 1, 0.82, 0.25)
        GameTooltip:AddLine("Click to put this away until your next level. It moves in Arrange (/hs move).", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    notice:SetScript("OnLeave", function() GameTooltip:Hide() end)
    notice:Hide()
    notice.fade = notice:CreateAnimationGroup()
    local arrive = notice.fade:CreateAnimation("Alpha")
    arrive:SetFromAlpha(0)
    arrive:SetToAlpha(1)
    arrive:SetDuration(0.6)
    -- while it is up: gone when the last point is spent, and never over a fight
    notice:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if not noticeSample then notice:Hide() end
        else
            YR.TalentNotice()
        end
    end)
    NoticePlace()
end

local function NoticeListen(on)
    if not notice then return end
    if on and not noticeHears then
        noticeHears = true
        for _, e in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
            pcall(notice.RegisterEvent, notice, e)
        end
    elseif not on and noticeHears then
        noticeHears = false
        notice:UnregisterAllEvents()
    end
end

--- The notice as it should be now: up while there are points to spend (and it is wanted, on screen,
--- not put away, not in a fight), else gone. Called at the login and a new level, and by the notice
--- itself when the talents change.
function YR.TalentNotice()
    local wanted = YR.Option("remindTalents") and YR.TalentNoticeMode() ~= "chat"
    local n = wanted and YR.UnspentTalents() or 0
    noticeN = type(n) == "number" and n or 0
    if noticeAway and noticeAway ~= noticeN then noticeAway = nil end
    if noticeN <= 0 and not noticeSample then
        if notice then
            notice:Hide()
            NoticeListen(false)
        end
        return
    end
    if not notice then NoticeBuild() end
    NoticePaint()
    NoticeListen(noticeN > 0)
    local show = noticeSample or (noticeAway == nil and not InCombatLockdown())
    if show and not notice:IsShown() then
        notice:Show()
        notice.fade:Play()
    elseif not show then
        notice:Hide()
    end
end

--- For Arrange: the notice itself, with two sample points on it while it is being placed (sample).
function YR.TalentNoticeFrame(sample)
    if not (YR.Option("remindTalents") and YR.TalentNoticeMode() ~= "chat") then return nil end
    if sample ~= nil then
        noticeSample = sample and true or false
        if noticeSample or notice then YR.TalentNotice() end
    end
    return notice
end
function YR.TalentNoticeSave()
    if not notice then return end
    local l, t = notice:GetLeft(), notice:GetTop()
    if l and t then YippRouteDB.talentPos = { l, t } end
end
function YR.TalentNoticeReset()
    YippRouteDB.talentPos = nil
    if notice then NoticePlace() end
end

local function Remind(level)
    if YR.Option("remindTrainer") then
        local line = YR.TrainerLine(level)
        if line then YR.Print(line) end
    end
    if YR.Option("remindTalents") then
        if YR.TalentNoticeMode() == "chat" then
            local n = YR.UnspentTalents()
            if n and n > 0 then YR.Print(("%d talent point%s to spend."):format(n, n == 1 and "" or "s")) end
        else
            YR.TalentNotice()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Durability
-- ---------------------------------------------------------------------------
--- Your most worn piece, in percent (nil with nothing that wears).
function YR.LowestDurability()
    local low
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local p = cur / max * 100
            if not low or p < low then low = p end
        end
    end
    return low
end

local warned = false      -- told about the warning line; again only after it's back above it
local function Warn(text)
    YR.Print(text)
    if UIErrorsFrame then UIErrorsFrame:AddMessage("Headstart: " .. text, 1, 0.6, 0.2) end
end

local function CheckDurability(cameToTown)
    if not YR.Option("durability") then return end
    if YR.WelcomeHolds and YR.WelcomeHolds() then return end     -- (said once the welcome is answered: Greet)
    local low = YR.LowestDurability()
    if not low then return end
    local line = YippRouteDB.durWarn or DUR_WARN
    if low >= line then
        warned = false
    elseif not warned then
        warned = true
        Warn(("your gear is down to %d%% - repair soon."):format(math.floor(low)))
        return
    end
    if cameToTown and low < (YippRouteDB.durTown or DUR_TOWN) then
        YR.Print(("your gear is at %d%% - repair while you're here."):format(math.floor(low)))
    end
end

-- ---------------------------------------------------------------------------
-- Each reminder listens only while it is on: the ding for the screenshot and the two lines, your
-- gear's wear and coming into a town for the durability lines, the trainer's window for the prices.
local function Leveling()
    return YR.Option("levelShot") or YR.Option("remindTrainer") or YR.Option("remindTalents") or YR.Option("levelUpStats")
end

local DingLines              -- (the lines a ding used to write in chat: further down)
local dinged
local function Shot() Screenshot() end
local function Ding() Remind(dinged) end
local function OnLevel(_, _, level, ...)
    if DingLines and YR.Option("levelUpStats") then DingLines(...) end
    -- The new spells and talent point are in place a moment after the event, and the ding
    -- animation is worth waiting for in the screenshot.
    dinged = level
    if YR.Option("levelShot") then C_Timer.After(1.5, Shot) end
    C_Timer.After(2, Ding)
end

-- ---------------------------------------------------------------------------
-- A ding as chat used to tell it: "You have gained 19 hit points. Your Strength increases by 1." Forever
-- only says "Congratulations, you have reached Level 2!".
--   The ding's event carries what you gained (health, power, strength, agility, stamina, intellect).
--   Spirit isn't in it, and should a number come as nothing, what you had is remembered from the
--   login and from the ding before, and the difference said instead. The lines are written a moment
--   after the ding, in the yellow of the game's own, in the game's own words where it still has them.
--   Account option levelUpStats (on unless turned off): lines in chat, nothing else.
-- ---------------------------------------------------------------------------
local STAT_NAMES = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }
local had = {}                  -- what you had: [1..5] the five stats, hp, mp
local gain = {}                 -- what the ding's event said: [1..4], hp, mp

local function Readable(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) and v or nil end

local function Have(into)
    for i = 1, 5 do
        local ok, base = pcall(UnitStat, "player", i)
        into[i] = ok and Readable(base) or nil
    end
    local ok, health = pcall(UnitHealthMax, "player")
    into.hp = ok and Readable(health) or nil
    local got, mana = pcall(UnitPowerMax, "player", 0)
    into.mp = got and Readable(mana) or nil
end

local now = {}
local function SayDing()
    Have(now)
    local chat = DEFAULT_CHAT_FRAME
    if not (chat and chat.AddMessage) then return end
    -- what the event said, else the difference from what you had
    local function Up(key)
        local said = gain[key]
        if said and said > 0 then return said end
        if now[key] and had[key] and now[key] > had[key] then return now[key] - had[key] end
        return 0
    end
    local hp, mp = Up("hp"), Up("mp")
    if hp > 0 and mp > 0 then
        chat:AddMessage((_G.LEVEL_UP_HEALTH_MANA or "You have gained %d hit points and %d mana."):format(hp, mp), 1, 1, 0)
    elseif hp > 0 then
        chat:AddMessage((_G.LEVEL_UP_HEALTH or "You have gained %d hit points."):format(hp), 1, 1, 0)
    end
    for i = 1, 5 do
        local up = Up(i)
        if up > 0 then
            chat:AddMessage((_G.LEVEL_UP_STAT or "Your %s increases by %d."):format(_G["SPELL_STAT" .. i .. "_NAME"] or STAT_NAMES[i], up), 1, 1, 0)
        end
    end
    for k, v in pairs(now) do had[k] = v end
end

local function OnDingStats(hp, mp, _, _, str, agi, sta, int)
    gain.hp, gain.mp, gain[1], gain[2], gain[3], gain[4] = Readable(hp), Readable(mp), Readable(str), Readable(agi), Readable(sta), Readable(int)
    C_Timer.After(0.4, SayDing)         -- your new numbers are in place a moment after the event
end
DingLines = OnDingStats
YR.LevelUpLines = SayDing               -- for the tests

local resting
-- wear comes a piece at a time (a death is eight of these at once): one look for the lot
local wearSoon = false
local function Wear() wearSoon = false CheckDurability(false) end
local function OnWear(_, event)
    if event == "UPDATE_INVENTORY_DURABILITY" then
        if wearSoon then return end
        wearSoon = true
        C_Timer.After(0.5, Wear)
    else
        local now = IsResting()
        if now and not resting then CheckDurability(true) end
        resting = now
    end
end

-- Once, eight seconds after the login - and only with a reminder on. This is asked the first time at
-- the login and never says yes again, so turning a reminder on later doesn't set it off.
local asked
local function AtLogin()
    if asked then return false end
    asked = true
    return Leveling() or YR.Option("durability")
end
local function Greet() Remind() CheckDurability(false) end

local declared
function YR.StartReminders()
    if declared then return end
    declared = true
    -- (what you have is noted as this comes on and whenever a setting changes: the lines need a "before")
    local function Note() if YR.Option("levelUpStats") then Have(had) end end
    YR.Part(Leveling, { "PLAYER_LEVEL_UP" }, OnLevel, { start = Note, again = Note })
    YR.Part(function() return YR.Option("durability") end, { "UPDATE_INVENTORY_DURABILITY", "PLAYER_UPDATE_RESTING" }, OnWear,
        { start = function() resting = IsResting and IsResting() end })
    YR.Part(function() return YR.Option("remindTrainer") end, { "TRAINER_SHOW" }, ReadTrainer)
    -- (on a new install's first login, after the welcome is answered: YR.AfterWelcome, Core.lua)
    YR.Part(AtLogin, nil, nil, { start = function() C_Timer.After(8, function() YR.AfterWelcome(Greet) end) end })
end
