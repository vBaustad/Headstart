-- Reminders: said when there is something to do about it.
--   * Trainer: at a ding - a small window with what your class trainer has new for you at that level and about
--     what it costs (it was a chat line, once at login too: see "New at your trainer" below). The ranks come from
--     the game's data (Data/TrainerSpells.lua); the prices are only shown at the trainer, so every visit
--     remembers them (YippRouteDB.trainerCosts[CLASS]) and a rank never seen there is "price not known yet".
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

--- The next level at which your class trainer has something new for you (nil: nothing more to 60).
function YR.TrainerNextLevel(level)
    level = level or UnitLevel("player")
    local race, best = RaceBit(), nil
    for _, e in ipairs((YR.TrainerSpells or {})[Class()] or {}) do
        if e[2] > level and (e[5] == 0 or bit.band(e[5], race) ~= 0) and e[6] ~= 1 and (not best or e[2] < best) then best = e[2] end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- New at your trainer: a small window as you level, when your class trainer has something new for you at that
-- level - each spell's icon and rank, the spell itself under the mouse - instead of a line in chat
-- (the owner, 2026-10-21: "nobody looks at our chat lines"; "a popup that comes every second level and says what is
-- available this level"; the line named every spell not trained yet, so one you skip - Pick Pocket - came back at
-- every ding). Only what came at the levels just gained, and only what you haven't trained: a spell trained while
-- it is up goes from it, and it goes when nothing is left. Its x puts it away. After a fight, not in one. Placed in
-- Arrange (trainerPos). Nothing of it is made until there is something to show; it listens only while it is up.
--   Thin: the heading and the icons, as wide as they are (the owner, 2026-10-21: "make it thinner. no need for price
--   etc and make the X better" - a line under them said the level and what it would cost, "prices not known yet").
-- ---------------------------------------------------------------------------
-- One row: the heading, the icons after it, the x at the end - as low as an icon (a heading over the icons made it twice
-- that: the owner, 2026-10-22, "the box is too big" and then "it's mostly the height"). More than POP_ROW icons go on in
-- rows under the first, from where the icons begin.
local POP_ICON, POP_GAP, POP_ROW, POP_PAD = 30, 5, 7, 8
local pop, popList, popSample, popWaiting = nil, {}, false, false

local function PopPlace()
    pop:ClearAllPoints()
    local p = YippRouteDB.trainerPos
    if type(p) == "table" and p[1] and p[2] then
        pop:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else
        pop:SetPoint("TOP", UIParent, "TOP", 0, -300)          -- (under where the better-gear window comes)
    end
end

local PopRefresh
local function PopBuild()
    local S = YR.Style
    pop = CreateFrame("Frame", "HeadstartTrainerPopup", UIParent)
    pop:SetFrameStrata("MEDIUM")
    pop:SetClampedToScreen(true)
    pop:SetMovable(true)
    pop:EnableMouse(true)
    S.Fill(pop, S.C.window)
    S.Border(pop, S.C.lineHi)
    S.Shadow(pop, 14, 4, 0.6)
    pop.head = S.Text(pop, 11, S.C.muted)
    pop.head:SetPoint("LEFT", pop, "TOPLEFT", POP_PAD, -(POP_PAD + POP_ICON / 2))
    pop.head:SetText("NEW AT YOUR TRAINER")
    local close = S.CloseX(pop, function()
        if popSample then return end
        pop:Hide()
    end, "Put away until your next level")
    close:SetPoint("RIGHT", pop, "TOPRIGHT", -4, -(POP_PAD + POP_ICON / 2))
    pop.icons = {}
    -- while it is up: a spell trained goes from it, and it waits out a fight
    pop:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            pop:UnregisterEvent("PLAYER_REGEN_ENABLED")
            if popWaiting then popWaiting = false PopRefresh(true) end
        else
            PopRefresh()
        end
    end)
    pop:SetScript("OnHide", function(self)
        if not popWaiting then self:UnregisterAllEvents() end
    end)
    pop:Hide()
    PopPlace()
end

local function PopIcon(i)
    local b = pop.icons[i]
    if b then return b end
    local S = YR.Style
    b = CreateFrame("Button", nil, pop)
    b:SetSize(POP_ICON, POP_ICON)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    S.Border(b, S.C.lineHi)
    b.rank = b:CreateFontString(nil, "OVERLAY")
    b.rank:SetFont(S.FONT, 12, "OUTLINE")
    b.rank:SetPoint("BOTTOMRIGHT", 2, -2)
    b:SetScript("OnEnter", function(self)
        if not self.m then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.m.id) else GameTooltip:SetText(self.m.name) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pop.icons[i] = b
    return b
end

-- What is still to learn of the list, drawn; gone when nothing is. show: up it comes (else as it is).
function PopRefresh(show)
    if not pop then return end
    local list = {}
    for _, m in ipairs(popList) do
        if popSample or not (IsPlayerSpell and IsPlayerSpell(m.id)) then list[#list + 1] = m end
    end
    if #list == 0 then
        pop:Hide()
        return
    end
    local headW = pop.head:GetStringWidth()
    if type(headW) ~= "number" then headW = 130 end
    local left = POP_PAD + headW + 10            -- (the icons begin after the heading)
    for i, m in ipairs(list) do
        local b = PopIcon(i)
        b.m = m
        local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(m.id)
        b.tex:SetTexture(tex or 134400)
        b.rank:SetText(m.rank > 0 and m.rank or "")
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", left + ((i - 1) % POP_ROW) * (POP_ICON + POP_GAP), -POP_PAD - math.floor((i - 1) / POP_ROW) * (POP_ICON + POP_GAP))
        b:Show()
    end
    for i = #list + 1, #pop.icons do pop.icons[i]:Hide() end
    local rows, cols = math.ceil(#list / POP_ROW), math.min(#list, POP_ROW)
    pop:SetSize(left + cols * (POP_ICON + POP_GAP) - POP_GAP + 30, POP_PAD * 2 + rows * (POP_ICON + POP_GAP) - POP_GAP)
    if show and not pop:IsShown() then pop:Show() end
    if pop:IsShown() and not popSample then pop:RegisterEvent("SPELLS_CHANGED") end
end

--- At a ding: what came at the levels from `from` up to `to` that you haven't trained, in the window.
function YR.TrainerPopup(from, to)
    if not YR.Option("remindTrainer") then return end
    to = to or UnitLevel("player")
    from = from or to
    local list = {}
    for _, m in ipairs(YR.TrainerMissing(to)) do
        if m.level >= from and m.level <= to then list[#list + 1] = m end
    end
    if #list == 0 then return end
    if not pop then PopBuild() end
    popList, popSample = list, false
    if InCombatLockdown() then
        popWaiting = true
        pop:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    PopRefresh(true)
end

--- For Arrange: the window, with spells of yours on it while it is being placed (sample).
function YR.TrainerPopupFrame(sample)
    if not YR.Option("remindTrainer") then return nil end
    if sample ~= nil then
        if sample then
            if not pop then PopBuild() end
            if not pop:IsShown() then
                local list, level = {}, UnitLevel("player")
                for _, e in ipairs((YR.TrainerSpells or {})[Class()] or {}) do
                    if #list < 3 and e[2] <= math.max(level, 2) then
                        list[#list + 1] = { id = e[1], name = e[3], rank = e[4], level = e[2] }
                    end
                end
                popList, popSample = list, true
                PopRefresh(true)
            end
        elseif popSample then
            popSample = false
            pop:Hide()
        end
    end
    return pop
end
function YR.TrainerPopupSave()
    if not pop then return end
    local l, t = pop:GetLeft(), pop:GetTop()
    if l and t then YippRouteDB.trainerPos = { l, t } end
end
function YR.TrainerPopupReset()
    YippRouteDB.trainerPos = nil
    if pop then PopPlace() end
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
--   With a talent build followed (Talents.lua), the words say which talent is next - "next: Deflection 2/5" - and
--   its tooltip the next as many as there are points.
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
    local nextOne = YR.TalentNextLines and YR.TalentNextLines(1)[1]
    notice.text:SetText(("%d talent point%s to spend"):format(n, n == 1 and "" or "s")
        .. (nextOne and ("  -  next: |cffffffff" .. nextOne .. "|r") or ""))
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
        local build = YR.TalentFollowed and YR.TalentFollowed()
        if build then
            GameTooltip:AddLine(build.name, 0.8, 0.8, 0.8)
            for _, line in ipairs(YR.TalentNextLines(math.max(1, noticeN))) do GameTooltip:AddLine(line, 1, 1, 1) end
        end
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

-- At a ding (from, to: the levels just gained) the trainer's window; at the login only the talents.
local function Remind(from, to)
    if to and YR.Option("remindTrainer") then YR.TrainerPopup(from, to) end
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
-- Mid-screen, on the game's own line for messages (it was in chat as well: the line nobody read - 2026-10-21).
local function Warn(text)
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
        Warn(("your gear is at %d%% - repair while you're here."):format(math.floor(low)))
    end
end

-- ---------------------------------------------------------------------------
-- Each reminder listens only while it is on: the ding for the screenshot and the two lines, your
-- gear's wear and coming into a town for the durability lines, the trainer's window for the prices.
local function Leveling()
    return YR.Option("levelShot") or YR.Option("remindTrainer") or YR.Option("remindTalents")
end

local dinged, dingedFrom          -- the level reached, and the first of the levels gained since the last Ding
local function Shot() Screenshot() end
local function Ding()
    if not dingedFrom then return end           -- (two dings close together: the first Ding told both)
    local from = dingedFrom
    dingedFrom = nil
    Remind(from, dinged)
end
local function OnLevel(_, _, level)
    -- The new spells and talent point are in place a moment after the event, and the ding
    -- animation is worth waiting for in the screenshot.
    dinged = level
    dingedFrom = dingedFrom or level
    if YR.Option("levelShot") then C_Timer.After(1.5, Shot) end
    C_Timer.After(2, Ding)
end

-- (Headstart's own level-up lines - "You have gained 19 hit points. Your Strength increases by 1." - are
-- gone: Forever said only "Congratulations, you have reached Level 2!", and from build 1.60.1.70425 its chat
-- writes them all itself again, Spirit and talent points too - Blizzard_ChatFrameBase's Camelot
-- ChatFrameUtilOverrides.lua, ChatFrameUtil.DisplayLevelUp. Ours would have said each twice. 2026-10-16.)

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
    YR.Part(Leveling, { "PLAYER_LEVEL_UP" }, OnLevel)
    YR.Part(function() return YR.Option("durability") end, { "UPDATE_INVENTORY_DURABILITY", "PLAYER_UPDATE_RESTING" }, OnWear,
        { start = function() resting = IsResting and IsResting() end })
    YR.Part(function() return YR.Option("remindTrainer") end, { "TRAINER_SHOW" }, ReadTrainer)
    -- (on a new install's first login, after the welcome is answered: YR.AfterWelcome, Core.lua)
    YR.Part(AtLogin, nil, nil, { start = function() C_Timer.After(8, function() YR.AfterWelcome(Greet) end) end })
end
