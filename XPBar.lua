-- XP bar: Headstart's own experience bar in place of Blizzard's, laid out your way.
--   The bar: your XP, then the XP of the quests done and not yet handed in, then the rested XP ahead
--   of that; ticks every tenth (or none), a spark at the front.
--   Size, place, colours, texture, ticks and font are settings; it's dragged where you want it while
--   unlocked. Blizzard's bar is made invisible and click-through while ours shows (only hidden from
--   view: it's an Edit Mode frame, and moving or hiding it from an addon would taint Edit Mode).
--   The words: three texts on the bar (left, middle, right) and three under it (left2, center2,
--   right2, shown while "under" is on), each a line you write with these in it:
--     {level} {xp} {max} {left} {pct} {rested} {restedpct} {rate} (XP an hour) {ding} (time to ding)
--     {mobs} (kills to ding) {kill} (XP a kill lately) {played} {levelplayed} {session}
--     {quest} {questpct} {quests} (the XP, share of the level and number of the quests done, not handed in)
--   Shown always or only while the mouse is over the bar.
--   XP an hour and played time come from the level splits (Splits.lua); a kill's XP is the XP that
--   comes without a quest handed in, the last ten of them averaged.
--   Account options (YippRouteDB.xpbar, Settings, QoL, XP bar): on, hideBlizz, w, h, pos, lock, ticks,
--   texture, font, textHover, xpColor, questColor, restColor, bgAlpha, left, center, right, under,
--   left2, center2, right2, maxHide.
local ADDON, YR = ...

local DEFAULT = {
    on = true, hideBlizz = true, w = 600, h = 22, lock = true, ticks = 0, texture = "smooth", font = 13,
    textHover = false, xpColor = { 0.09, 0.47, 0.85, 1 }, questColor = { 1.0, 0.69, 0.0, 0.9 },
    restColor = { 0.55, 0.3, 0.9, 0.6 }, bgAlpha = 0.75,
    left = "Level {level}", center = "{xp} / {max}", right = "{pct}%",
    under = true, left2 = "Time to Level: {ding}", center2 = "Completed Quests: |cffffb000{questpct}%|r", right2 = "XP/Hour: {rate}",
    maxHide = true,
}
YR.XPBAR_DEFAULT = DEFAULT

-- The first look (before the line under the bar): a value still as it was then takes the new one.
local FIRST = {
    h = 14, ticks = 10, texture = "flat", font = 11, bgAlpha = 0.65,
    xpColor = { 0.58, 0.0, 0.55, 1 }, restColor = { 0.0, 0.39, 0.88, 0.55 },
    left = "Level {level}  {xp} / {max} ({pct}%)", center = "{rested}", right = "{rate}/hr  ·  {ding} to ding  ·  {mobs} kills",
}
local function Same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for i = 1, 4 do if math.abs((a[i] or 0) - (b[i] or 0)) > 0.001 then return false end end
    return true
end

local TEXTURES = {
    flat = "Interface\\Buttons\\WHITE8X8",
    blizzard = "Interface\\TargetingFrame\\UI-StatusBar",
    smooth = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}

-- The settings, with what's missing filled in. The filling-in is done once for a settings table, not
-- on every read: this is asked for on every repaint.
local filled
function YR.XPBarDB()
    local db = YippRouteDB.xpbar
    if db and filled == db then return db end
    if not db then db = {} YippRouteDB.xpbar = db end
    if (db.look or 1) < 2 then
        for k, v in pairs(FIRST) do if Same(db[k], v) then db[k] = nil end end
        db.look = 2
    end
    for k, v in pairs(DEFAULT) do
        -- "on" is left unset until you set it: its default depends on what else is loaded (YR.XPBarOn)
        if db[k] == nil and k ~= "on" then db[k] = type(v) == "table" and { v[1], v[2], v[3], v[4] } or v end
    end
    filled = db
    return db
end

--- The bar on or off as you set it; never set, it's on unless EllesmereUI's XP bars are loaded.
function YR.XPBarOn()
    local on = YR.XPBarDB().on
    if on == nil then return YR.OptionDefault("xpbar") end
    return on and true or false
end

-- ---------------------------------------------------------------------------
-- The numbers
-- ---------------------------------------------------------------------------
local kills, questAt = {}, 0          -- the last kills' XP; when a quest was last handed in
local lastXP, lastMax, lastLevel
local sessionStart = GetTime()

local function Short(n)
    n = n or 0
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 1000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end

local function Clock(s)
    if not s or s ~= s or s == math.huge then return "-" end
    s = math.max(0, math.floor(s))
    local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
    if d > 0 then return ("%dd %dh"):format(d, h) end
    if h > 0 then return ("%dh %dm"):format(h, m) end
    return ("%dm %02ds"):format(m, s % 60)
end

local function KillXP()
    if #kills == 0 then return nil end
    local sum = 0
    for _, v in ipairs(kills) do sum = sum + v end
    return sum / #kills
end

-- The quests in the log that are done and not handed in: their XP and how many. The log is read
-- again only when the game says it changed (at most twice a second), and every ten seconds as a
-- net under that. The game answers 0 XP for a quest it hasn't loaded yet (right after login): such a
-- quest is asked for, and the log is read again a second later until it has its XP.
local QUEST_GAP, QUEST_NET = 0.5, 10
local questXP, questN, questDirty, questRead, questAgain = 0, 0, true, -1, 0
local function QuestsDone()
    local now = GetTime()
    if now < questAgain and not (questDirty and now - questRead >= QUEST_GAP) then return questXP, questN end
    questDirty = false
    questRead = now
    questAgain = now + QUEST_NET
    questXP, questN = 0, 0
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return 0, 0 end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        local id = info and not info.isHeader and info.questID
        if id and C_QuestLog.IsComplete(id) then
            local ok, xp = pcall(GetQuestLogRewardXP, id)
            if ok and type(xp) == "number" and xp > 0 then
                questXP = questXP + xp
            else
                if C_QuestLog.RequestLoadQuestByID then pcall(C_QuestLog.RequestLoadQuestByID, id) end
                questAgain = now + 1
            end
            questN = questN + 1
        end
    end
    return questXP, questN
end
YR.XPBarQuests = QuestsDone

-- One table for the values, filled anew each time (not a new table each second). A token is found
-- whatever its case: {XP} is {xp}.
local V = setmetatable({}, { __index = function(t, k)
    local lower = type(k) == "string" and k:lower()
    if lower and lower ~= k then return rawget(t, lower) end
end })

--- Every value a text can show: { level = "18", xp = "2340", ... }. The same table each time: read it,
--- don't keep it.
function YR.XPBarValues()
    local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    local left = math.max(0, max - xp)
    local rate = YR.SplitsXPRate and YR.SplitsXPRate()
    local kill = KillXP()
    local played, levelPlayed
    if YR.SplitsPlayed then played, levelPlayed = YR.SplitsPlayed() end
    local qxp, qn = QuestsDone()
    V.level, V.xp, V.max, V.left = tostring(level), tostring(xp), tostring(max), tostring(left)
    V.quest, V.quests = Short(qxp), tostring(qn)
    V.questpct = max > 0 and ("%.1f"):format(qxp / max * 100) or "0"
    V.pct = max > 0 and ("%.1f"):format(xp / max * 100) or "0"
    V.rested = rested > 0 and ("%s rested"):format(Short(rested)) or ""
    V.restedpct = max > 0 and ("%d%%"):format(math.floor(rested / max * 100 + 0.5)) or "0%"
    V.rate = rate and rate > 0 and Short(rate) or "-"
    V.ding = rate and rate > 0 and Clock(left / rate * 3600) or "-"
    V.mobs = kill and kill > 0 and tostring(math.ceil(left / kill)) or "-"
    V.kill = kill and Short(kill) or "-"
    V.played = played and Clock(played) or "-"
    V.levelplayed = levelPlayed and Clock(levelPlayed) or "-"
    V.session = Clock(GetTime() - sessionStart)
    return V
end

--- A text with its {tokens} filled in; unknown ones are left as written.
function YR.XPBarFormat(template, values)
    return (tostring(template or ""):gsub("{(%w+)}", values or YR.XPBarValues()))
end

local function OnXP()
    local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if lastXP then
        local gained = level > lastLevel and (lastMax - lastXP + xp) or (xp - lastXP)
        -- XP with no quest handed in just now: a kill (or exploring - rare, and small)
        if gained > 0 and GetTime() - questAt > 1.5 then
            kills[#kills + 1] = gained
            if #kills > 10 then table.remove(kills, 1) end
        end
    end
    lastXP, lastMax, lastLevel = xp, max, level
end
YR.XPBarOnXP = OnXP

-- ---------------------------------------------------------------------------
-- The bar
-- ---------------------------------------------------------------------------
-- Three kinds of work, each done only when its cause changes:
--   the look (texture, colours, fonts, ticks, size) - when a setting changes;
--   the bar (shown or not, the three widths) - when XP, rested XP or the quest log changes;
--   the words - once a second while they show, and only the ones whose text is different now.
local bar
local SIDES = { "left", "center", "right" }
local UNDER = { left = "left2", center = "center2", right = "right2" }
local shownText = {}            -- [side] = the text on screen now
local blizzHidden               -- what we last did to Blizzard's bars (nil: nothing yet)
local mouseLater                -- their mouse couldn't be changed in a fight: done when it ends
local restAfter                 -- what the rested part is anchored after now

--- Blizzard's bar out of sight (and out of the way of the mouse) while ours shows, back when not.
--- Touched only when that changes: with our bar off we leave Blizzard's (and anyone else's hold on
--- it) alone.
local function HideBlizz(hide)
    hide = hide and true or false
    if blizzHidden == hide or (blizzHidden == nil and not hide) then return end
    blizzHidden = hide
    local main, second = _G.MainStatusTrackingBarContainer, _G.SecondaryStatusTrackingBarContainer
    for i = 1, 2 do
        local f = i == 1 and main or second
        if f and f.SetAlpha then
            f:SetAlpha(hide and 0 or 1)
            if f.EnableMouse then
                if InCombatLockdown() then mouseLater = true else f:EnableMouse(not hide) end
            end
        end
    end
end

local function SetWords(key, text)
    if shownText[key] == text then return end
    shownText[key] = text
    bar.text[key]:SetText(text)
end

-- The words. While they're hidden (shown on hover only, and the mouse is elsewhere) nothing is worked out.
local function Words()
    if not bar then return end
    local db = YR.XPBarDB()
    local show = not db.textHover or bar:IsMouseOver()
    local values = show and YR.XPBarValues() or nil
    for i = 1, 3 do
        local side = SIDES[i]
        local under = UNDER[side]
        SetWords(side, show and YR.XPBarFormat(db[side], values) or "")
        SetWords(under, show and db.under and YR.XPBarFormat(db[under], values) or "")
    end
end

-- The bar itself: shown or not, your XP, the quests' part, the rested part.
local function Paint()
    if not bar then return end
    local db = YR.XPBarDB()
    local level, maxLevel = UnitLevel("player"), GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    local show = YR.XPBarOn() and YR.QoLOn() and not (db.maxHide and level >= maxLevel)
    bar:SetShown(show)
    HideBlizz(show and db.hideBlizz)
    if not show then return end
    local xp, max = UnitXP("player"), UnitXPMax("player")
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    local w = db.w
    local p = max > 0 and xp / max or 0
    bar.fill:SetWidth(math.max(1, w * p))
    bar.fill:SetShown(p > 0)
    local qxp = QuestsDone()
    local questW = max > 0 and math.min(w - w * p, w * qxp / max) or 0
    bar.quest:SetWidth(math.max(1, questW))
    bar.quest:SetShown(questW >= 1)
    -- the rested part starts where the quests' part ends (or your XP, or the bar)
    local after = questW >= 1 and bar.quest or p > 0 and bar.fill or bar
    if restAfter ~= after then
        restAfter = after
        bar.rest:ClearAllPoints()
        if after ~= bar then
            bar.rest:SetPoint("TOPLEFT", after, "TOPRIGHT") bar.rest:SetPoint("BOTTOMLEFT", after, "BOTTOMRIGHT")
        else
            bar.rest:SetPoint("TOPLEFT") bar.rest:SetPoint("BOTTOMLEFT")
        end
    end
    local restW = max > 0 and math.min(w - w * p - questW, w * rested / max) or 0
    bar.rest:SetWidth(math.max(1, restW))
    bar.rest:SetShown(restW >= 1)
    bar.spark:SetShown(p > 0 and p < 1)
    bar.spark:SetPoint("CENTER", bar, "LEFT", w * p, 0)
    Words()
end
YR.XPBarPaint = Paint

-- The look: what only a setting changes.
local function Look()
    local db = YR.XPBarDB()
    local w = db.w
    bar:SetSize(w, db.h)
    bar:ClearAllPoints()
    if db.pos then bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", db.pos[1], db.pos[2])
    else bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 260) end      -- above the action bars and the unit frames
    local tex = TEXTURES[db.texture] or TEXTURES.flat
    bar.fill:SetTexture(tex)
    bar.quest:SetTexture(tex)
    bar.rest:SetTexture(tex)
    bar.fill:SetVertexColor(unpack(db.xpColor))
    bar.quest:SetVertexColor(unpack(db.questColor))
    bar.rest:SetVertexColor(unpack(db.restColor))
    bar.bg:SetColorTexture(0, 0, 0, db.bgAlpha)
    local n = db.ticks
    for i, t in ipairs(bar.ticks) do
        local on = n > 1 and i < n
        t:SetShown(on)
        if on then
            t:ClearAllPoints()
            t:SetPoint("TOP", bar, "TOPLEFT", w * i / n, 0)
            t:SetPoint("BOTTOM", bar, "BOTTOMLEFT", w * i / n, 0)
        end
    end
    for i = 1, 3 do
        local side = SIDES[i]
        bar.text[side]:SetFont(YR.Style.FONT, db.font, "OUTLINE")
        bar.text[UNDER[side]]:SetFont(YR.Style.FONT, math.max(8, db.font - 2), "OUTLINE")
    end
end

local function Build()
    if bar then return end
    local S = YR.Style
    bar = CreateFrame("Frame", "HeadstartXPBar", UIParent)
    bar:SetFrameStrata("LOW")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) if not YR.XPBarDB().lock then self:StartMoving() end end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        YR.XPBarDB().pos = { math.floor(self:GetLeft() + 0.5), math.floor(self:GetTop() - UIParent:GetTop() + 0.5) }
    end)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.rest = bar:CreateTexture(nil, "BORDER")
    bar.quest = bar:CreateTexture(nil, "BORDER")
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT") bar.fill:SetPoint("BOTTOMLEFT")
    bar.quest:SetPoint("TOPLEFT", bar.fill, "TOPRIGHT") bar.quest:SetPoint("BOTTOMLEFT", bar.fill, "BOTTOMRIGHT")
    bar.spark = bar:CreateTexture(nil, "OVERLAY")
    bar.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    bar.spark:SetBlendMode("ADD")
    bar.spark:SetSize(16, 32)
    bar.ticks = {}
    for i = 1, 19 do
        local t = bar:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 0.5)
        t:SetWidth(1)
        bar.ticks[i] = t
    end
    S.Border(bar, { 0, 0, 0, 0.9 })
    bar.text = {}
    for i = 1, 3 do
        local side = SIDES[i]
        local fs = bar:CreateFontString(nil, "OVERLAY")
        fs:SetFont(S.FONT, 11, "OUTLINE")
        fs:SetPoint(side == "left" and "LEFT" or side == "right" and "RIGHT" or "CENTER",
            side == "left" and 6 or side == "right" and -6 or 0, 0)
        bar.text[side] = fs
        -- the line under the bar, lined up with the text above it
        local under = bar:CreateFontString(nil, "OVERLAY")
        under:SetFont(S.FONT, 11, "OUTLINE")
        under:SetTextColor(0.85, 0.85, 0.85)
        local at = side == "left" and "TOPLEFT" or side == "right" and "TOPRIGHT" or "TOP"
        local to = side == "left" and "BOTTOMLEFT" or side == "right" and "BOTTOMRIGHT" or "BOTTOM"
        under:SetPoint(at, bar, to, side == "left" and 2 or side == "right" and -2 or 0, -4)
        bar.text[UNDER[side]] = under
    end
    bar:SetScript("OnEnter", function(self)
        Words()
        local v = YR.XPBarValues()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(("Level %s: %s / %s (%s%%)"):format(v.level, v.xp, v.max, v.pct))
        GameTooltip:AddDoubleLine("To ding", v.left .. " XP", 0.8, 0.8, 0.8, 1, 1, 1)
        if v.rested ~= "" then GameTooltip:AddDoubleLine("Rested", v.rested:gsub(" rested", "") .. " (" .. v.restedpct .. ")", 0.8, 0.8, 0.8, 0.4, 0.6, 1) end
        if v.quests ~= "0" then
            GameTooltip:AddDoubleLine("Quests done, not handed in", ("%s: %s XP (%s%%)"):format(v.quests, v.quest, v.questpct),
                0.8, 0.8, 0.8, 1, 0.69, 0)
        end
        GameTooltip:AddDoubleLine("XP an hour", v.rate, 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Time to ding", v.ding, 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Kills to ding", v.mobs .. (v.kill ~= "-" and ("  (" .. v.kill .. " a kill)") or ""), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Played, this level", v.levelplayed, 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Played, in all", v.played, 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("This session", v.session, 0.8, 0.8, 0.8, 1, 1, 1)
        if not YR.XPBarDB().lock then GameTooltip:AddLine("Unlocked: drag it where you want it", 0.4, 0.8, 1) end
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() Words() end)
    Look()
end

--- After a setting changed: size, place and look again.
function YR.XPBarApply()
    if not bar then Build() else Look() end
    Paint()
end

function YR.XPBarResetPosition()
    YR.XPBarDB().pos = nil
    YR.XPBarApply()
end

local QUEST_EVENTS = { QUEST_LOG_UPDATE = true, QUEST_DATA_LOAD_RESULT = true, QUEST_ACCEPTED = true, QUEST_REMOVED = true,
    UNIT_QUEST_LOG_CHANGED = true }

function YR.StartXPBar()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
        "QUEST_TURNED_IN", "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_REGEN_ENABLED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    for e in pairs(QUEST_EVENTS) do pcall(f.RegisterEvent, f, e) end
    local drawn = 0             -- the quest XP the bar was last drawn with
    f:SetScript("OnEvent", function(_, event)
        if QUEST_EVENTS[event] then questDirty = true return end
        if event == "QUEST_TURNED_IN" then questAt = GetTime() questDirty = true return end
        if event == "PLAYER_REGEN_ENABLED" then
            if not mouseLater then return end
            mouseLater = false
            local hide = blizzHidden
            blizzHidden = not hide      -- so it's done again in full, the mouse with it
            HideBlizz(hide)
            return
        end
        if event == "PLAYER_ENTERING_WORLD" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
            if blizzHidden then blizzHidden = false end        -- Blizzard lays its bars out afresh: ours to hide again
        end
        if event == "PLAYER_ENTERING_WORLD" then
            Build()
            lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
        elseif event == "PLAYER_XP_UPDATE" then
            OnXP()
        end
        Paint()
        drawn = questXP
    end)
    -- Edit Mode puts Blizzard's bar back on show when it closes: hide it again then
    if EditModeManagerFrame and EditModeManagerFrame.HookScript then
        EditModeManagerFrame:HookScript("OnHide", function() C_Timer.After(0.1, function() blizzHidden = nil Paint() end) end)
    end
    -- Once a second while the bar shows: the words (the time to ding and the session tick on without
    -- events), and the bar itself only when the quests' XP is different from what it was drawn with.
    C_Timer.NewTicker(1, function()
        if not (bar and bar:IsShown()) then return end
        -- Blizzard shows its own bar again when it likes (after a login, a layout, a new level): one look
        -- a second at whether it's still out of sight, and out it goes again if not.
        if blizzHidden then
            local main, second = _G.MainStatusTrackingBarContainer, _G.SecondaryStatusTrackingBarContainer
            if (main and main.GetAlpha and main:GetAlpha() > 0) or (second and second.GetAlpha and second:GetAlpha() > 0) then
                blizzHidden = false
                HideBlizz(true)
            end
        end
        if QuestsDone() ~= drawn then
            Paint()
            drawn = questXP
        else
            Words()
        end
    end)
end
