-- Swing timer: your auto-attack bars - main hand, off hand, ranged - made to be seen, with more on
-- them. Off until you turn it on (Headstart, QoL, Swing timer). Two ways, picked there (style):
--   "blizzard" (to begin with): Blizzard's own swing bars, dressed - our texture, your colours, the
--   frame round each bar off, larger text, the weapon's icon beside the bar and the swing's whole
--   length after its name. Blizzard still runs them (their timing, their place and size in Edit Mode);
--   only how they look is changed, and it is all put back when this is off.
--   "own": Headstart's own bars, described below, with Blizzard's made see-through.
-- Headstart's own bars:
--   Each bar fills from one swing to the next. On it: the weapon's icon, the hand's name, the time
--   left and the swing's whole length ("0.8 / 2.6"), a bright line at the front; and it turns another
--   colour while your target is out of reach for that attack.
--   Where it comes from: the game's own PLAYER_SWING event (how long until the next swing, and which
--   hand) and its range check (C_SwingTimer, PLAYER_SWING_RANGE_UPDATE). Should the game keep a
--   swing's length secret, your weapon's attack speed is used instead.
--   Which bars: main hand; off hand while you hold a weapon there; ranged for a hunter, and for
--   anyone while a ranged swing runs. Shown always, in combat, or only while a swing runs.
--   Blizzard's own swing bars can be made invisible while ours show (only see-through: they are Edit
--   Mode frames, and hiding or moving them from an addon would taint Edit Mode). In Edit Mode they show.
--   Nothing runs between swings: the bars are only drawn while one is on its way (or while unlocked).
--   Account options (YippRouteDB.swing): on, hideBlizz, w, h, gap, pos, lock, texture, font, show
--   ("always" | "combat" | "swing"), name, time, speed, icon, spark, range, mainColor, offColor,
--   rangedColor, farColor, bgAlpha, outline (a thin dark line round each bar), style ("blizzard" | "own"), border (Blizzard's frame round a
--   dressed bar), colors (your colours on a dressed bar).
local ADDON, YR = ...

local MAIN, OFF, RANGED = 0, 1, 2
local DEFAULT = {
    on = false, hideBlizz = true, w = 260, h = 20, gap = 3, lock = true, texture = "smooth", font = 12,
    show = "combat", name = true, time = true, speed = true, icon = false, spark = true, range = true, outline = true,
    mainColor = { 0.20, 0.45, 1.00, 1 }, offColor = { 0.15, 0.75, 0.95, 1 }, rangedColor = { 0.95, 0.65, 0.15, 1 },
    farColor = { 0.85, 0.20, 0.20, 1 }, bgAlpha = 0.65, style = "blizzard", border = false, colors = true,
}
YR.SWING_DEFAULT = DEFAULT
local TEXTURES = {
    flat = "Interface\\Buttons\\WHITE8X8",
    blizzard = "Interface\\TargetingFrame\\UI-StatusBar",
    smooth = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}
local HANDS = {
    { type = MAIN, name = "Main hand", slot = 16, color = "mainColor" },
    { type = OFF, name = "Off hand", slot = 17, color = "offColor" },
    { type = RANGED, name = "Ranged", slot = 18, color = "rangedColor" },
}
local BLIZZARD = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }

local filled
function YR.SwingDB()
    local db = YippRouteDB.swing
    if db and filled == db then return db end
    if not db then db = {} YippRouteDB.swing = db end
    for k, v in pairs(DEFAULT) do
        if db[k] == nil then db[k] = type(v) == "table" and { unpack(v) } or v end
    end
    -- the weapon icon began switched on, and wasn't liked: off, once, for settings from before
    if (db.look or 1) < 2 then db.icon, db.look = false, 2 end
    filled = db
    return db
end

function YR.SwingOn() return YR.QoLOn() and YR.SwingDB().on == true end
-- Our own bars are the ones showing / Blizzard's are, dressed.
local function Own() return YR.SwingOn() and YR.SwingDB().style == "own" end
local function Dressed() return YR.SwingOn() and YR.SwingDB().style ~= "own" end

-- A thin dark line round `around`, drawn on `owner` (four textures). Returns them, to show and hide.
local function Outline(owner, around)
    local lines = {}
    for i, at in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = owner:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, 1)
        local out = 1
        t:SetPoint(at[1], around, at[1], (at[1]:find("LEFT") and -out or out), (at[1]:find("TOP") and out or -out))
        t:SetPoint(at[2], around, at[2], (at[2]:find("LEFT") and -out or out), (at[2]:find("TOP") and out or -out))
        if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
        lines[i] = t
    end
    return lines
end
local function ShowLines(lines, on) for _, t in ipairs(lines) do t:SetShown(on) end end

local holder
local bars = {}             -- [swing type] = the bar
local swings = {}           -- [swing type] = { start, length } of the swing on its way
local far = {}              -- [swing type] = true while the target is out of reach
local inCombat, editing, hunter = false, false, false
local hidden = {}           -- [a frame of Blizzard's] = the alpha it had
local Dress, DressTint, DressLength

-- How long a swing of this hand takes by your weapon's speed (when the game won't say), or nil.
local function Speed(kind)
    if kind == RANGED then
        local speed = UnitRangedDamage("player")
        return type(speed) == "number" and not issecretvalue(speed) and speed > 0 and speed or nil
    end
    local main, off = UnitAttackSpeed("player")
    local speed = main
    if kind == OFF then speed = off end
    return type(speed) == "number" and not issecretvalue(speed) and speed > 0 and speed or nil
end

-- Is there a bar for this hand now?
local function Wanted(hand, db, now)
    local s = swings[hand.type]
    local running = s and now - s.start < s.length
    if not db.lock then return true end
    if db.show == "swing" then return running or false end
    if db.show == "combat" and not inCombat then return false end
    if hand.type == MAIN then return true end
    if hand.type == OFF then return running or Speed(OFF) ~= nil end
    return running or hunter
end

local function Colour(bar, db)
    local c = (db.range and far[bar.hand.type]) and db.farColor or db[bar.hand.color]
    bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
end

-- One bar's fill, front line and time, for now. Returns true while its swing is still on its way.
local function Paint(bar, db, now)
    local s = swings[bar.hand.type]
    local length = s and s.length or 0
    local elapsed = s and (now - s.start) or 0
    local running = s ~= nil and elapsed < length
    if not running then elapsed = length end
    bar:SetMinMaxValues(0, length > 0 and length or 1)
    bar:SetValue(length > 0 and elapsed or 1)
    bar.spark:SetShown(db.spark and running)
    if running and db.spark then
        bar.spark:SetPoint("CENTER", bar, "LEFT", bar:GetWidth() * elapsed / length, 0)
    end
    -- the words change ten times a second at most: only written when they do
    local left = running and math.floor((length - elapsed) * 10 + 0.5) or -1
    if left ~= bar.left or length ~= bar.length then
        bar.left, bar.length = left, length
        local text = ""
        if length > 0 then
            if db.time and running then text = ("%.1f"):format(left / 10) end
            if db.speed then text = (text ~= "" and (text .. " / ") or "") .. ("%.1f"):format(length) end
        end
        bar.time:SetText(text)
    end
    return running
end

local function Tick()
    local db, now = YR.SwingDB(), GetTime()
    local running = false
    for _, hand in ipairs(HANDS) do
        local bar = bars[hand.type]
        if bar:IsShown() and Paint(bar, db, now) then running = true end
    end
    if not running then
        holder:SetScript("OnUpdate", nil)
        YR.SwingLayout()         -- the last swing ran out: which bars stay is decided again
    end
end

--- Which bars show, stacked from the top, and whether anything has to be drawn each frame.
function YR.SwingLayout()
    if not holder then return end
    local db, now = YR.SwingDB(), GetTime()
    local on = Own() and not editing
    local n, running = 0, false
    for _, hand in ipairs(HANDS) do
        local bar = bars[hand.type]
        local want = on and Wanted(hand, db, now)
        bar:SetShown(want)
        if want then
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", holder, "TOPLEFT", db.icon and db.h + 2 or 0, -n * (db.h + db.gap))
            bar:SetPoint("RIGHT", holder, "RIGHT")
            Colour(bar, db)
            if Paint(bar, db, now) then running = true end
            n = n + 1
        end
    end
    holder:SetShown(n > 0)
    holder:SetHeight(math.max(1, n) * (db.h + db.gap) - db.gap)
    holder:SetScript("OnUpdate", running and Tick or nil)
end

local function Icons()
    for _, hand in ipairs(HANDS) do
        local bar = bars[hand.type]
        local icon = GetInventoryItemTexture("player", hand.slot)
        bar.icon:SetTexture(icon or 134400)
    end
end

-- The look: what only a setting changes.
local function Look()
    local db = YR.SwingDB()
    holder:SetWidth(db.w)
    holder:ClearAllPoints()
    if db.pos then holder:SetPoint("TOPLEFT", UIParent, "TOPLEFT", db.pos[1], db.pos[2])
    else holder:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200) end
    holder:EnableMouse(not db.lock)
    holder.edge:SetShown(not db.lock)
    local tex = TEXTURES[db.texture] or TEXTURES.smooth
    for _, hand in ipairs(HANDS) do
        local bar = bars[hand.type]
        bar:SetHeight(db.h)
        bar:SetStatusBarTexture(tex)
        bar.bg:SetColorTexture(0, 0, 0, db.bgAlpha)
        ShowLines(bar.lines, db.outline)
        bar.icon:SetSize(db.h, db.h)
        bar.icon:SetShown(db.icon)
        bar.spark:SetSize(2, db.h)
        bar.name:SetFont(YR.Style.FONT, db.font, "OUTLINE")
        bar.time:SetFont(YR.Style.FONT, db.font, "OUTLINE")
        bar.name:SetShown(db.name)
        bar.left, bar.length = nil, nil          -- the words are written again
    end
    Icons()
end

local function Build()
    if holder then return end
    holder = CreateFrame("Frame", "HeadstartSwing", UIParent)
    holder:SetFrameStrata("LOW")
    holder:SetClampedToScreen(true)
    holder:SetMovable(true)
    holder:RegisterForDrag("LeftButton")
    holder:SetScript("OnDragStart", function(self) if not YR.SwingDB().lock then self:StartMoving() end end)
    holder:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        YR.SwingDB().pos = { math.floor(self:GetLeft() + 0.5), math.floor(self:GetTop() - UIParent:GetTop() + 0.5) }
    end)
    holder.edge = holder:CreateTexture(nil, "BACKGROUND")
    holder.edge:SetPoint("TOPLEFT", -3, 3)
    holder.edge:SetPoint("BOTTOMRIGHT", 3, -3)
    holder.edge:SetColorTexture(0.40, 0.66, 1.00, 0.25)
    for _, hand in ipairs(HANDS) do
        local bar = CreateFrame("StatusBar", nil, holder)
        bar.hand = hand
        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints()
        bar.lines = Outline(bar, bar)
        bar.icon = bar:CreateTexture(nil, "ARTWORK")
        bar.icon:SetPoint("RIGHT", bar, "LEFT", -2, 0)
        bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        bar.spark = bar:CreateTexture(nil, "OVERLAY")
        bar.spark:SetColorTexture(1, 1, 0.8, 0.95)
        bar.name = bar:CreateFontString(nil, "OVERLAY")
        bar.name:SetPoint("LEFT", 6, 0)
        bar.name:SetFont(YR.Style.FONT, 12, "OUTLINE")
        bar.name:SetText(hand.name)
        bar.time = bar:CreateFontString(nil, "OVERLAY")
        bar.time:SetPoint("RIGHT", -6, 0)
        bar.time:SetFont(YR.Style.FONT, 12, "OUTLINE")
        bars[hand.type] = bar
    end
    Look()
end

-- Blizzard's own bars: see-through while ours show, as they were otherwise.
local function TheirBars()
    local hide = Own() and YR.SwingDB().hideBlizz and not editing
    for _, name in ipairs(BLIZZARD) do
        local f = _G[name]
        if type(f) == "table" and f.SetAlpha then
            if hide then
                local a = f:GetAlpha()
                if hidden[f] == nil then hidden[f] = a end
                if a ~= 0 then f:SetAlpha(0) end
            elseif hidden[f] ~= nil then
                f:SetAlpha(hidden[f])
                hidden[f] = nil
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Blizzard's bars, dressed
-- ---------------------------------------------------------------------------
-- A bar of Blizzard's is a frame (SwingTimerMainHandFrame, ...) with .StatusBar, .Background and
-- .Border, and its labels behind GetTypeLabel / GetTypeLabelShadow / GetTimeLabel. What each had is
-- kept here, beside the two things of ours on it (the weapon's icon, the swing's length), and put
-- back when the dressing comes off. Nothing is written onto Blizzard's frames, moved or resized.
local kept = setmetatable({}, { __mode = "k" })     -- [Blizzard's frame] = what it had, and ours
local lengths = {}                                  -- [swing type] = the last swing's length

local function Labels(f)
    local out = {}
    for _, get in ipairs({ "GetTypeLabel", "GetTypeLabelShadow", "GetTimeLabel" }) do
        local ok, label = pcall(function() return f[get](f) end)
        if ok and type(label) == "table" and label.SetFont then out[#out + 1] = label end
    end
    return out
end

-- Your colour on the bar (or the out-of-reach one), over whatever Blizzard last set.
local function Tint(f, k)
    local db = YR.SwingDB()
    local c = (k.on and db.colors) and ((db.range and far[k.hand.type]) and db.farColor or db[k.hand.color]) or k.color
    if not c or not c[1] then return end
    k.painting = true
    f.StatusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    k.painting = false
end

function DressTint(kind)
    local f = _G[BLIZZARD[kind + 1]]
    local k = f and kept[f]
    if k and k.on then Tint(f, k) end
end

local function LengthText(k)
    local length = lengths[k.hand.type]
    local on = YR.SwingDB().speed and length ~= nil
    k.length:SetShown(on)
    if on then k.length:SetText(("%.1fs"):format(length)) end
end

-- A swing began: its whole length goes after the bar's name.
function DressLength(kind, length)
    if type(kind) ~= "number" or issecretvalue(kind) then return end
    if type(length) ~= "number" or issecretvalue(length) or length <= 0 then length = Speed(kind) end
    if not length or lengths[kind] == length then return end
    lengths[kind] = length
    local f = _G[BLIZZARD[kind + 1]]
    local k = f and kept[f]
    if k and k.on then LengthText(k) end
end

function Dress()
    local db = YR.SwingDB()
    local on = Dressed()
    for i, name in ipairs(BLIZZARD) do
        local f = _G[name]
        local sb = type(f) == "table" and f.StatusBar
        if type(sb) == "table" and sb.SetStatusBarTexture then
            local k = kept[f]
            if on and not k then
                k = { hand = HANDS[i], fonts = {} }
                kept[f] = k
                local t = sb:GetStatusBarTexture()
                k.atlas = type(t) == "table" and t.GetAtlas and t:GetAtlas() or nil
                k.file = type(t) == "table" and t.GetTexture and t:GetTexture() or nil
                k.color = { sb:GetStatusBarColor() }
                k.border = type(f.Border) == "table" and f.Border:GetAlpha() or nil
                k.bg = type(f.Background) == "table" and f.Background:GetAlpha() or nil
                k.labels = Labels(f)
                for n, label in ipairs(k.labels) do k.fonts[n] = { label:GetFont() } end
                -- Blizzard's bar sits a few pixels inside its frame, where its border was: our fill and
                -- our line go round the bar itself, so nothing is left hanging about it
                k.fill = f:CreateTexture(nil, "BACKGROUND")
                k.fill:SetAllPoints(sb)
                k.lines = Outline(f, sb)
                k.icon = f:CreateTexture(nil, "ARTWORK")
                k.icon:SetPoint("RIGHT", sb, "LEFT", -3, 0)
                k.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                k.length = sb:CreateFontString(nil, "OVERLAY")
                if k.labels[1] then k.length:SetPoint("LEFT", k.labels[1], "RIGHT", 6, 0)
                else k.length:SetPoint("CENTER") end
                k.length:SetTextColor(1, 1, 1, 0.75)
                -- Blizzard colours its bar as it goes: what it set is remembered, and ours goes back over it
                hooksecurefunc(sb, "SetStatusBarColor", function(_, r, g, b, a)
                    if k.painting then return end
                    k.color[1], k.color[2], k.color[3], k.color[4] = r, g, b, a      -- no new table: this can come often
                    if k.on then Tint(f, k) end
                end)
            end
            if on then
                k.on = true
                sb:SetStatusBarTexture(TEXTURES[db.texture] or TEXTURES.smooth)
                Tint(f, k)
                if k.border then f.Border:SetAlpha(db.border and k.border or 0) end
                if k.bg then f.Background:SetAlpha(0) end
                k.fill:SetColorTexture(0, 0, 0, db.bgAlpha)
                k.fill:Show()
                ShowLines(k.lines, db.outline)
                for _, label in ipairs(k.labels) do label:SetFont(YR.Style.FONT, db.font, "OUTLINE") end
                k.length:SetFont(YR.Style.FONT, math.max(8, db.font - 1), "OUTLINE")
                LengthText(k)
                local size = sb:GetHeight() or 0
                k.icon:SetSize(size > 0 and size or 20, size > 0 and size or 20)
                k.icon:SetTexture(GetInventoryItemTexture("player", k.hand.slot) or 134400)
                k.icon:SetShown(db.icon)
            elseif k and k.on then
                k.on = false
                if k.atlas then sb:SetStatusBarTexture(k.atlas) elseif k.file then sb:SetStatusBarTexture(k.file) end
                Tint(f, k)          -- colors off or not, k.on is false now: Blizzard's own colour
                if k.border then f.Border:SetAlpha(k.border) end
                if k.bg then f.Background:SetAlpha(k.bg) end
                for n, label in ipairs(k.labels) do
                    local font = k.fonts[n]
                    if font[1] then label:SetFont(font[1], font[2], font[3]) end
                end
                k.icon:Hide()
                k.length:Hide()
                k.fill:Hide()
                ShowLines(k.lines, false)
            end
        end
    end
end

-- The game tells us when the target goes in and out of reach, for the hands we ask about. Asked for
-- once, and never taken back: the switch is the game's one switch for that hand, and Blizzard's own
-- swing bars read the same one - turning it off for us would turn their colour off too.
local asked = {}
local function RangeChecks()
    local on = YR.SwingOn() and YR.SwingDB().range
    if not on then
        for _, hand in ipairs(HANDS) do far[hand.type] = nil end
        return
    end
    local swing = _G.C_SwingTimer
    if type(swing) ~= "table" or type(swing.EnableRangeCheck) ~= "function" then return end
    for _, hand in ipairs(HANDS) do
        if not asked[hand.type] then
            asked[hand.type] = true
            pcall(swing.EnableRangeCheck, hand.type, true)
        end
    end
end

--- After a setting changed (or the main switch): built, sized, placed and shown as it is now.
function YR.SwingApply()
    if Own() or holder then
        Build()
        Look()
    end
    TheirBars()
    Dress()
    RangeChecks()
    YR.SwingLayout()
end

function YR.SwingResetPosition()
    YR.SwingDB().pos = nil
    YR.SwingApply()
end

--- A swing of this hand began: `length` seconds to the next.
function YR.SwingStart(kind, length)
    if type(kind) ~= "number" or issecretvalue(kind) or not bars[kind] then return end
    if type(length) ~= "number" or issecretvalue(length) or length <= 0 then length = Speed(kind) end
    if not length then return end
    swings[kind] = swings[kind] or {}
    swings[kind].start, swings[kind].length = GetTime(), length
    YR.SwingLayout()
end

-- A sample on Blizzard's bars, dressed: each is shown and filled by us for a few seconds, then left
-- as it was (hidden again if it was hidden). Not in a fight: there the bars are Blizzard's to run.
local sampler
local function DressTest()
    if InCombatLockdown() then return false, "not in a fight: the bars are busy there." end
    Dress()
    local list = {}
    for i, name in ipairs(BLIZZARD) do
        local f = _G[name]
        local k = f and kept[f]
        if k and k.on then
            local length = 1.6 + i * 0.6
            list[#list + 1] = { f = f, k = k, length = length, was = f:IsShown() }
            f:Show()
            f.StatusBar:SetMinMaxValues(0, length)
            k.length:SetText(("%.1fs"):format(length))
            k.length:SetShown(YR.SwingDB().speed)
        end
    end
    if #list == 0 then return false, "Blizzard's swing bars aren't there to show (are they on in Edit Mode?)." end
    sampler = sampler or CreateFrame("Frame")
    local start, last = GetTime(), -1
    sampler:SetScript("OnUpdate", function(self)
        local elapsed = GetTime() - start
        local done = elapsed > 4 or InCombatLockdown()
        for _, e in ipairs(list) do
            local at = elapsed % e.length
            e.f.StatusBar:SetValue(at)
            local label = e.k.labels[#e.k.labels]
            local tenth = math.floor((e.length - at) * 10)
            if label and label.SetText and tenth ~= e.tenth then
                e.tenth = tenth
                label:SetText(("%.1f"):format(tenth / 10))
            end
            if done and not e.was then e.f:Hide() end
        end
        if done then
            self:SetScript("OnUpdate", nil)
            for _, e in ipairs(list) do LengthText(e.k) end
        end
    end)
    return true
end

--- A sample swing on every bar, to see the look (Settings). Returns false and why when it can't.
function YR.SwingTest()
    if Dressed() then return DressTest() end
    if not Own() then return false, "turn the swing timer on first." end
    Build()
    local was = YR.SwingDB().lock
    YR.SwingDB().lock = false          -- every bar shows for the sample
    for i, hand in ipairs(HANDS) do
        swings[hand.type] = { start = GetTime(), length = 1.6 + i * 0.6 }
    end
    YR.SwingLayout()
    YR.SwingDB().lock = was
    return true
end

function YR.StartSwing()
    local _, class = UnitClass("player")
    hunter = class == "HUNTER"
    local f = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED", "EDIT_MODE_LAYOUTS_UPDATED", "ADDON_LOADED" }) do
        pcall(f.RegisterEvent, f, event)
    end
    f:SetScript("OnEvent", function(_, event, a, b, c)
        if event == "PLAYER_SWING" then
            if holder and Own() then
                YR.SwingStart(b, a)
            elseif Dressed() then
                DressLength(b, a)
            end
        elseif event == "PLAYER_SWING_RANGE_UPDATE" then
            if not YR.SwingOn() or type(a) ~= "number" or issecretvalue(a) or a < MAIN or a > RANGED then return end
            local out = c == true and b == false
            if far[a] ~= out then
                far[a] = out
                if Dressed() then
                    DressTint(a)
                elseif holder and bars[a]:IsShown() then
                    Colour(bars[a], YR.SwingDB())
                end
            end
        elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            inCombat = event == "PLAYER_REGEN_DISABLED"
            YR.SwingLayout()
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            if holder then Icons() YR.SwingLayout() end
            if Dressed() then Dress() end
        elseif event == "ADDON_LOADED" then
            if a == "Blizzard_SwingTimer" then
                f:UnregisterEvent("ADDON_LOADED")
                YR.SwingApply()
            end
        else
            inCombat = UnitAffectingCombat("player") and true or false
            YR.SwingApply()
        end
    end)
    local registry = _G.EventRegistry
    if type(registry) == "table" and registry.RegisterCallback then
        registry:RegisterCallback("EditMode.Enter", function() editing = true TheirBars() YR.SwingLayout() end, f)
        registry:RegisterCallback("EditMode.Exit", function() editing = false TheirBars() Dress() YR.SwingLayout() end, f)
    end
end
