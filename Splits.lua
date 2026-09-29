-- Level splits: a small timer that counts this character's playing time from level 1 and, at every
-- level, shows how far ahead of or behind your best run you are. Only the time you are logged in counts.
--   YippRouteDB.splits.runs[key] = { name, class, elapsed, levels = { [level] = seconds } }
--   YippRouteDB.splits.pb        = key of the best run: the furthest level, reached in the least time
-- A run starts on a character that logs in at level 1 with no XP; older characters are not timed.
local _, YR = ...

local TICK = 0.5
local key, rec, frame, last, ticker

local function Clock(s)
    s = floor(s + 0.5)
    local h, m = floor(s / 3600), floor(s % 3600 / 60)
    return h > 0 and ("%d:%02d:%02d"):format(h, m, s % 60) or ("%d:%02d"):format(m, s % 60)
end

local function Delta(d)
    local sign, color = d < 0 and "-" or "+", d < 0 and "|cff40ff40" or "|cffff5050"
    return color .. sign .. Clock(math.abs(d)) .. "|r"
end

local function DB()
    YippRouteDB.splits = YippRouteDB.splits or { runs = {} }
    return YippRouteDB.splits
end

-- The best other run: the one that got furthest, and of those the fastest to its top level.
local function Best()
    local best, bestTop, bestTime
    for k, r in pairs(DB().runs) do
        local top = 1
        for lvl in pairs(r.levels) do if lvl > top then top = lvl end end
        local t = r.levels[top] or r.elapsed
        if k ~= key and top > 1 and (not best or top > bestTop or (top == bestTop and t < bestTime)) then
            best, bestTop, bestTime = k, top, t
        end
    end
    return best and DB().runs[best]
end

local function Refresh()
    if not (frame and frame:IsShown()) then return end
    if not rec then
        frame.top:SetText("Level splits")
        frame.mid:SetText("|cff999999start a new character to time a run|r")
        frame.low:SetText("")
        return
    end
    local level = UnitLevel("player")
    local pb = Best()
    frame.top:SetText(("Level %d  |cffffffff%s|r"):format(level, Clock(rec.elapsed)))
    local target = pb and pb.levels[level + 1]
    frame.mid:SetText(target and ("to %d: best %s  %s"):format(level + 1, Clock(target), Delta(rec.elapsed - target))
        or ("to %d: no best yet"):format(level + 1))
    local reached = rec.levels[level]
    if reached and level > 1 then
        local since = rec.levels[level - 1] or 0
        local theirs = pb and pb.levels[level]
        frame.low:SetText(("%d in %s%s"):format(level, Clock(reached - since),
            theirs and ("  " .. Delta(reached - theirs)) or ""))
    else
        frame.low:SetText("")
    end
end

local function Tick()
    local now = GetTime()
    if rec and last then rec.elapsed = rec.elapsed + (now - last) end
    last = now
    Refresh()
end

local function Build()
    frame = CreateFrame("Frame", "YippRouteSplitsFrame", UIParent)
    frame:SetSize(190, 50)
    local p = YippRouteDB.splitsPos
    if p then frame:SetPoint(p[1], UIParent, p[1], p[2], p[3]) else frame:SetPoint("TOP", 0, -120) end
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    frame.top = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.top:SetPoint("TOPLEFT", 6, -5)
    frame.mid = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.mid:SetPoint("TOPLEFT", frame.top, "BOTTOMLEFT", 0, -3)
    frame.low = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.low:SetPoint("TOPLEFT", frame.mid, "BOTTOMLEFT", 0, -2)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        YippRouteDB.splitsPos = { point, x, y }
    end)
end

function YR:ShowSplits(on)
    YippRouteDB.showSplits = on
    if on then
        if not frame then Build() end
        frame:Show()
        Refresh()
    elseif frame then
        frame:Hide()
    end
end

-- A new character at level 1 starts a run; one already timed carries on; anyone else is not timed.
function YR:StartSplits()
    local name = UnitFullName("player")
    local ok, guid = pcall(function() return UnitGUID("player") .. "" end)
    if not name or name == UNKNOWNOBJECT or name == "Unknown" or not ok then
        C_Timer.After(2, function() YR:StartSplits() end)
        return
    end
    key = guid
    rec = DB().runs[key]
    if not rec and UnitLevel("player") == 1 and UnitXP("player") == 0 then
        local _, class = UnitClass("player")
        rec = { name = YR.CharKey(), class = class, elapsed = 0, levels = { [1] = 0 } }
        DB().runs[key] = rec
    end
    last = GetTime()
    ticker = ticker or C_Timer.NewTicker(TICK, Tick)
    if YippRouteDB.showSplits ~= false then YR:ShowSplits(true) end
end

function YR:ResetSplits()
    if key then DB().runs[key] = nil end
    rec = nil
    YR.Print("splits for this character cleared.")
    Refresh()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:SetScript("OnEvent", function(_, _, level)
    if rec then
        rec.levels[level] = rec.elapsed
        local pb = Best()
        local theirs = pb and pb.levels[level]
        YR.Print(("level %d at %s%s"):format(level, Clock(rec.elapsed), theirs and ("  " .. Delta(rec.elapsed - theirs)) or ""))
    end
    Refresh()
end)
