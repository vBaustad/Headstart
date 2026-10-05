-- XP bar: Headstart's own experience bar in place of Blizzard's, laid out your way.
--   The bar: your XP, the rested XP ahead of it, ticks every tenth (or none), a spark at the front.
--   Size, place, colours, texture, ticks and font are settings; it's dragged where you want it while
--   unlocked. Blizzard's bar is made invisible and click-through while ours shows (only hidden from
--   view: it's an Edit Mode frame, and moving or hiding it from an addon would taint Edit Mode).
--   The words: three texts (left, middle, right), each a line you write with these in it:
--     {level} {xp} {max} {left} {pct} {rested} {restedpct} {rate} (XP an hour) {ding} (time to ding)
--     {mobs} (kills to ding) {kill} (XP a kill lately) {played} {levelplayed} {session}
--   Shown always or only while the mouse is over the bar.
--   XP an hour and played time come from the level splits (Splits.lua); a kill's XP is the XP that
--   comes without a quest handed in, the last ten of them averaged.
--   Account options (YippRouteDB.xpbar, Settings, QoL, XP bar): on, hideBlizz, w, h, pos, lock, ticks,
--   texture, font, textHover, xpColor, restColor, bgAlpha, left, center, right, maxHide.
local ADDON, YR = ...

local DEFAULT = {
    on = true, hideBlizz = true, w = 600, h = 14, lock = true, ticks = 10, texture = "flat", font = 11,
    textHover = false, xpColor = { 0.58, 0.0, 0.55, 1 }, restColor = { 0.0, 0.39, 0.88, 0.55 }, bgAlpha = 0.65,
    left = "Level {level}  {xp} / {max} ({pct}%)", center = "{rested}", right = "{rate}/hr  ·  {ding} to ding  ·  {mobs} kills",
    maxHide = true,
}
YR.XPBAR_DEFAULT = DEFAULT

local TEXTURES = {
    flat = "Interface\\Buttons\\WHITE8X8",
    blizzard = "Interface\\TargetingFrame\\UI-StatusBar",
    smooth = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}

function YR.XPBarDB()
    local db = YippRouteDB.xpbar
    if not db then db = {} YippRouteDB.xpbar = db end
    for k, v in pairs(DEFAULT) do
        if db[k] == nil then db[k] = type(v) == "table" and { v[1], v[2], v[3], v[4] } or v end
    end
    return db
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
    if n >= 10000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end

local function Clock(s)
    if not s or s ~= s or s == math.huge then return "-" end
    s = math.max(0, math.floor(s))
    local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
    if d > 0 then return ("%dd %dh"):format(d, h) end
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    return ("%dm %02ds"):format(m, s % 60)
end

local function KillXP()
    if #kills == 0 then return nil end
    local sum = 0
    for _, v in ipairs(kills) do sum = sum + v end
    return sum / #kills
end

--- Every value a text can show: { level = "18", xp = "2,340", ... }.
function YR.XPBarValues()
    local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    local left = math.max(0, max - xp)
    local rate = YR.SplitsXPRate and YR.SplitsXPRate()
    local kill = KillXP()
    local played, levelPlayed
    if YR.SplitsPlayed then played, levelPlayed = YR.SplitsPlayed() end
    local big = BreakUpLargeNumbers or tostring
    return {
        level = tostring(level), xp = big(xp), max = big(max), left = big(left),
        pct = max > 0 and ("%.1f"):format(xp / max * 100) or "0",
        rested = rested > 0 and ("%s rested"):format(Short(rested)) or "",
        restedpct = max > 0 and ("%d%%"):format(math.floor(rested / max * 100 + 0.5)) or "0%",
        rate = rate and rate > 0 and Short(rate) or "-",
        ding = rate and rate > 0 and Clock(left / rate * 3600) or "-",
        mobs = kill and kill > 0 and tostring(math.ceil(left / kill)) or "-",
        kill = kill and Short(kill) or "-",
        played = played and Clock(played) or "-",
        levelplayed = levelPlayed and Clock(levelPlayed) or "-",
        session = Clock(GetTime() - sessionStart),
    }
end

--- A text with its {tokens} filled in; unknown ones are left as written.
function YR.XPBarFormat(template, values)
    values = values or YR.XPBarValues()
    return (tostring(template or ""):gsub("{(%w+)}", function(k) return values[k:lower()] end))
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
local bar

local function BlizzBars()
    return { _G.MainStatusTrackingBarContainer, _G.SecondaryStatusTrackingBarContainer }
end

--- Blizzard's bar out of sight (and out of the way of the mouse) while ours shows, back when not.
local function HideBlizz(hide)
    for _, f in ipairs(BlizzBars()) do
        if f and f.SetAlpha then
            f:SetAlpha(hide and 0 or 1)
            if f.EnableMouse and not InCombatLockdown() then pcall(f.EnableMouse, f, not hide) end
        end
    end
end

local function Paint()
    if not bar then return end
    local db = YR.XPBarDB()
    local level, maxLevel = UnitLevel("player"), GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
    local show = db.on and not (db.maxHide and level >= maxLevel)
    bar:SetShown(show)
    HideBlizz(show and db.hideBlizz)
    if not show then return end
    local xp, max = UnitXP("player"), UnitXPMax("player")
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    local w = db.w
    local p = max > 0 and xp / max or 0
    local tex = TEXTURES[db.texture] or TEXTURES.flat
    bar.fill:SetTexture(tex)
    bar.rest:SetTexture(tex)
    bar.fill:SetVertexColor(unpack(db.xpColor))
    bar.rest:SetVertexColor(unpack(db.restColor))
    bar.fill:SetWidth(math.max(1, w * p))
    bar.fill:SetShown(p > 0)
    local restW = max > 0 and math.min(w - w * p, w * rested / max) or 0
    bar.rest:SetWidth(math.max(1, restW))
    bar.rest:SetShown(restW >= 1)
    bar.spark:SetShown(p > 0 and p < 1)
    bar.spark:ClearAllPoints()
    bar.spark:SetPoint("CENTER", bar, "LEFT", w * p, 0)
    bar.bg:SetColorTexture(0, 0, 0, db.bgAlpha)
    for i, t in ipairs(bar.ticks) do
        local n = db.ticks
        t:SetShown(n > 1 and i < n)
        if n > 1 and i < n then
            t:ClearAllPoints()
            t:SetPoint("TOP", bar, "TOPLEFT", w * i / n, 0)
            t:SetPoint("BOTTOM", bar, "BOTTOMLEFT", w * i / n, 0)
        end
    end
    local values = YR.XPBarValues()
    local showText = not db.textHover or bar:IsMouseOver()
    for _, side in ipairs({ "left", "center", "right" }) do
        local fs = bar.text[side]
        fs:SetFont(YR.Style.FONT, db.font, "OUTLINE")
        fs:SetText(showText and YR.XPBarFormat(db[side], values) or "")
    end
end
YR.XPBarPaint = Paint

local function Place()
    local db = YR.XPBarDB()
    bar:SetSize(db.w, db.h)
    bar:ClearAllPoints()
    if db.pos then bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", db.pos[1], db.pos[2])
    else bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 6) end
    bar:EnableMouse(true)
end

local function Build()
    if bar then return end
    local S = YR.Style
    bar = CreateFrame("Frame", "HeadstartXPBar", UIParent)
    bar:SetFrameStrata("LOW")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) if not YR.XPBarDB().lock then self:StartMoving() end end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        YR.XPBarDB().pos = { math.floor(self:GetLeft() + 0.5), math.floor(self:GetTop() - UIParent:GetTop() + 0.5) }
    end)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.rest = bar:CreateTexture(nil, "BORDER")
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT") bar.fill:SetPoint("BOTTOMLEFT")
    bar.rest:SetPoint("TOPLEFT", bar.fill, "TOPRIGHT") bar.rest:SetPoint("BOTTOMLEFT", bar.fill, "BOTTOMRIGHT")
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
    for _, side in ipairs({ "left", "center", "right" }) do
        local fs = bar:CreateFontString(nil, "OVERLAY")
        fs:SetFont(S.FONT, 11, "OUTLINE")
        fs:SetPoint(side == "left" and "LEFT" or side == "right" and "RIGHT" or "CENTER",
            side == "left" and 6 or side == "right" and -6 or 0, 0)
        bar.text[side] = fs
    end
    bar:SetScript("OnEnter", function(self)
        Paint()
        local v = YR.XPBarValues()
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(("Level %s: %s / %s (%s%%)"):format(v.level, v.xp, v.max, v.pct))
        GameTooltip:AddDoubleLine("To ding", v.left .. " XP", 0.8, 0.8, 0.8, 1, 1, 1)
        if v.rested ~= "" then GameTooltip:AddDoubleLine("Rested", v.rested:gsub(" rested", "") .. " (" .. v.restedpct .. ")", 0.8, 0.8, 0.8, 0.4, 0.6, 1) end
        GameTooltip:AddDoubleLine("XP an hour", v.rate, 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Time to ding", v.ding, 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Kills to ding", v.mobs .. (v.kill ~= "-" and ("  (" .. v.kill .. " a kill)") or ""), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Played, this level", v.levelplayed, 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("Played, in all", v.played, 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine("This session", v.session, 0.8, 0.8, 0.8, 1, 1, 1)
        if not YR.XPBarDB().lock then GameTooltip:AddLine("Unlocked: drag it where you want it", 0.4, 0.8, 1) end
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() Paint() end)
    Place()
end

--- After a setting changed: size, place and look again.
function YR.XPBarApply()
    if not bar then Build() end
    Place()
    Paint()
end

function YR.XPBarResetPosition()
    YR.XPBarDB().pos = nil
    YR.XPBarApply()
end

function YR.StartXPBar()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
        "QUEST_TURNED_IN", "EDIT_MODE_LAYOUTS_UPDATED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "QUEST_TURNED_IN" then questAt = GetTime() return end
        if event == "PLAYER_ENTERING_WORLD" then
            Build()
            lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
        elseif event == "PLAYER_XP_UPDATE" then
            OnXP()
        end
        Paint()
    end)
    -- Edit Mode puts Blizzard's bar back on show when it closes: hide it again then
    if EditModeManagerFrame and EditModeManagerFrame.HookScript then
        EditModeManagerFrame:HookScript("OnHide", function() C_Timer.After(0.1, Paint) end)
    end
    -- the time to ding and the session tick on without events
    C_Timer.NewTicker(1, function() if bar and bar:IsShown() then Paint() end end)
end
