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
-- The look a new install gets is Slim: low flat bars close together, a nearly black back, each hand in a
-- quiet colour of its own with a brighter line at the front of the fill, and the hand's name in small
-- letters. Classic is the look Headstart had before (taller, shaded, blue). YR.SwingPreset puts either on.
local PRESETS = {
    slim = { w = 230, h = 14, gap = 1, texture = "flat", font = 11, name = true, time = false, speed = false, icon = false,
        spark = true, outline = true, bgAlpha = 0.85, border = false, colors = true,
        mainColor = { 0.72, 0.24, 0.24, 1 }, offColor = { 0.80, 0.52, 0.20, 1 }, rangedColor = { 0.38, 0.66, 0.24, 1 },
        farColor = { 0.42, 0.42, 0.42, 1 } },
    classic = { w = 260, h = 20, gap = 3, texture = "smooth", font = 12, name = true, time = true, speed = true, icon = false,
        spark = false, outline = true, bgAlpha = 0.65, border = false, colors = true,
        mainColor = { 0.20, 0.45, 1.00, 1 }, offColor = { 0.15, 0.75, 0.95, 1 }, rangedColor = { 0.95, 0.65, 0.15, 1 },
        farColor = { 0.85, 0.20, 0.20, 1 } },
}
YR.SWING_PRESETS = PRESETS
-- place: where Headstart's own bars stand. "edit": exactly over Blizzard's swing bars, so Edit Mode is
-- the one place both kinds are moved and sized, and changing between the two looks moves nothing.
-- "own": where you drag them, at the size set here (what it was before; kept for whoever had moved them).
local DEFAULT = { on = false, hideBlizz = true, lock = true, show = "combat", range = true, style = "blizzard",
    border = false, colors = true, place = "edit" }
for k, v in pairs(PRESETS.slim) do DEFAULT[k] = v end
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
    -- bars you had dragged somewhere stay there: only settings from before "place" that never moved them follow Edit Mode
    if db.place == nil and db.pos then db.place = "own" end
    for k, v in pairs(DEFAULT) do
        if db[k] == nil then db[k] = type(v) == "table" and { unpack(v) } or v end
    end
    -- the weapon icon began switched on, and wasn't liked: off, once, for settings from before
    if (db.look or 1) < 2 then db.icon, db.look = false, 2 end
    -- One kind of bar (2026-10-09): Blizzard's own, restyled. Edit Mode already gives them a size, a
    -- place, a title, the time and when they show, and they are timed by the game itself - bars of
    -- ours beside them were a second set of every setting. The settings page no longer offers ours;
    -- whoever had them is moved over once. (The code for them is still below, unused by the page.)
    if db.look < 3 then db.style, db.look = "blizzard", 3 end
    filled = db
    return db
end

--- On or off, read as it is saved: asking must not fill the settings of a swing timer that is off
--- with its defaults (YR.SwingDB does that, for the bars themselves).
function YR.SwingOn()
    local db = YippRouteDB.swing
    return YR.QoLOn() and type(db) == "table" and db.on == true
end
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
local laid                  -- which bars the stack was last laid out for (nil: lay it out again)
local ticking = false       -- our OnUpdate is on the holder
local SET = { 1, 2, 4 }     -- a hand's place in `laid`
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
local preview = false           -- sample swings on every bar, kept going while you change the look (YR.SwingPreview)
local function Wanted(hand, db, now)
    local s = swings[hand.type]
    local running = s and now - s.start < s.length
    if preview then return true end
    if not db.lock then return true end
    if db.show == "swing" then return running or false end
    if db.show == "combat" and not inCombat then return false end
    if hand.type == MAIN then return true end
    if hand.type == OFF then return running or Speed(OFF) ~= nil end
    return running or hunter
end

-- The fill, and the line at its front: the fill's own colour, lighter - it reads as the edge of the bar
-- rather than as a mark laid over it.
local function Colour(bar, db)
    local c = (db.range and far[bar.hand.type]) and db.farColor or db[bar.hand.color]
    bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    if bar.spark then
        bar.spark:SetColorTexture(c[1] + (1 - c[1]) * 0.55, c[2] + (1 - c[2]) * 0.55, c[3] + (1 - c[3]) * 0.55, 1)
    end
end

-- One bar's fill, front line and time, for now. Returns true while its swing is still on its way.
local function Paint(bar, db, now)
    local s = swings[bar.hand.type]
    local length = s and s.length or 0
    local elapsed = s and (now - s.start) or 0
    local running = s ~= nil and elapsed < length
    if not running then elapsed = length end
    -- the swing's length is the same from frame to frame: told to the bar only when it's another
    if bar.span ~= length then
        bar.span = length
        bar:SetMinMaxValues(0, length > 0 and length or 1)
    end
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
        ticking = false
        holder:SetScript("OnUpdate", nil)
        YR.SwingLayout()         -- the last swing ran out: which bars stay is decided again
    end
end

--- Which bars show, stacked from the top, and whether anything has to be drawn each frame.
--- This runs at every swing, and almost every swing finds the same bars up as the one before: they
--- are anchored, coloured and the holder sized only when which bars show is different (a setting
--- that moves them says so through Look, the reach of your target colours its bar by itself).
function YR.SwingLayout()
    if not holder then return end
    local db, now = YR.SwingDB(), GetTime()
    local on = Own() and not editing
    local set = 0
    for i, hand in ipairs(HANDS) do
        local want = on and Wanted(hand, db, now) or false
        bars[hand.type].want = want
        if want then set = set + SET[i] end
    end
    if set ~= laid then
        laid = set
        local n = 0
        for _, hand in ipairs(HANDS) do
            local bar = bars[hand.type]
            bar:SetShown(bar.want)
            if bar.want then
                bar:ClearAllPoints()
                -- over Blizzard's bar for that hand, where it has a place; else stacked in our own holder
                local theirs = db.place == "edit" and _G[BLIZZARD[hand.type + 1]]
                local sb = type(theirs) == "table" and theirs.StatusBar
                if type(sb) == "table" and sb.GetLeft and sb:GetLeft() then
                    bar:SetAllPoints(sb)
                else
                    bar:SetPoint("TOPLEFT", holder, "TOPLEFT", db.icon and db.h + 2 or 0, -n * (db.h + db.gap))
                    bar:SetPoint("RIGHT", holder, "RIGHT")
                end
                Colour(bar, db)
                n = n + 1
            end
        end
        holder:SetShown(n > 0)
        holder:SetHeight(math.max(1, n) * (db.h + db.gap) - db.gap)
    end
    local running = false
    for _, hand in ipairs(HANDS) do
        local bar = bars[hand.type]
        if bar.want and Paint(bar, db, now) then running = true end
    end
    if running ~= ticking then
        ticking = running
        holder:SetScript("OnUpdate", running and Tick or nil)
    end
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
    laid = nil                      -- the bars' size and place may be different: stacked again
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
    local accent = YR.Style and YR.Style.C and YR.Style.C.accent or { 1.00, 0.56, 0.20 }
    holder.edge:SetColorTexture(accent[1], accent[2], accent[3], 0.25)
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

--- Put a ready look on ("slim" or "classic"): the sizes, texture, text and colours, and nothing else -
--- where the bars are, whether they are on and which kind they are stay as you have them.
function YR.SwingPreset(name)
    local p = PRESETS[name]
    if not p then return false end
    local db = YR.SwingDB()
    for k, v in pairs(p) do db[k] = type(v) == "table" and { unpack(v) } or v end
    db.preset = name
    YR.SwingApply()
    return true
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
    -- the line at the front of the fill: the fill's own colour, lighter
    if k.spark then
        k.spark:SetColorTexture(c[1] + (1 - c[1]) * 0.55, c[2] + (1 - c[2]) * 0.55, c[3] + (1 - c[3]) * 0.55, 1)
    end
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
                -- a bright line at the front of the fill. It hangs on the end of the fill's own texture, so
                -- where it is never has to be worked out from the swing's value (the game may keep that secret)
                k.spark = f:CreateTexture(nil, "OVERLAY")
                k.spark:SetWidth(2)
                k.length = sb:CreateFontString(nil, "OVERLAY")
                if k.labels[1] then k.length:SetPoint("LEFT", k.labels[1], "RIGHT", 6, 0)
                else k.length:SetPoint("CENTER") end
                k.length:SetTextColor(1, 1, 1, 0.75)
                -- Blizzard colours its bar as it goes: what it set is remembered, and ours goes back over it
                hooksecurefunc(sb, "SetStatusBarColor", function(_, r, g, b, a)
                    if k.painting then return end
                    if issecretvalue(r) or issecretvalue(g) or issecretvalue(b) then return end      -- nothing we can keep or lighten
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
                local front = sb:GetStatusBarTexture()
                k.spark:ClearAllPoints()
                if type(front) == "table" and front.GetObjectType then
                    k.spark:SetPoint("TOP", front, "TOPRIGHT")
                    k.spark:SetPoint("BOTTOM", front, "BOTTOMRIGHT")
                end
                k.spark:SetShown(db.spark and type(front) == "table" and front.GetObjectType ~= nil)
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
                k.spark:Hide()
                k.fill:Hide()
                ShowLines(k.lines, false)
            end
        end
    end
end

-- The game tells us when the target goes in and out of reach, for the hands we ask about. Never taken
-- back: the switch is the game's one switch for that hand, and Blizzard's own swing bars read the
-- same one - turning it off for us would turn their colour off too. Asked again as a fight begins and
-- as the target changes: it is one switch, and Blizzard's bars may have turned it off since.
local function RangeChecks()
    local on = YR.SwingOn() and YR.SwingDB().range
    if not on then
        for _, hand in ipairs(HANDS) do far[hand.type] = nil end
        return
    end
    local swing = _G.C_SwingTimer
    if type(swing) ~= "table" or type(swing.EnableRangeCheck) ~= "function" then return end
    for _, hand in ipairs(HANDS) do pcall(swing.EnableRangeCheck, hand.type, true) end
end

-- Built, sized, placed and shown as it is now - or, with the timer off, everything put back.
local function Apply()
    if holder then Look() elseif Own() then Build() end
    TheirBars()
    Dress()
    RangeChecks()
    YR.SwingLayout()
end

-- Free while off (YR.Part, Core.lua, declared in YR.StartSwing): `part.on` is whether it's on now.
local part, frame

--- After a setting changed (or the main switch). Turned on or off: every part is looked at, and
--- coming on or going off does the rest. Still on: as it is now. Still off: nothing to do, and the
--- settings of a timer that is off aren't read (reading fills them in).
local PreviewShow
function YR.SwingApply()
    local on = part and part.on or false
    if on ~= YR.SwingOn() then
        YR.ApplyParts()
    elseif on then
        Apply()
    end
    if preview then PreviewShow() end           -- the look changed under the preview: drawn again as it is now
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

-- A sample of Blizzard's bars, dressed. Blizzard's own bars are not touched for it (showing an Edit
-- Mode frame from an addon would run its code as ours, and hiding it again in a fight is blocked):
-- three bars of our own are laid exactly over where Blizzard's sit, in the same look, and filled for
-- a few seconds. Where a bar of Blizzard's has no place yet, its sample stands in the middle.
local sampler, samples
local function DressTest()
    if InCombatLockdown() then return false, "not in a fight." end
    local db = YR.SwingDB()
    sampler = sampler or CreateFrame("Frame", nil, UIParent)
    if not samples then
        samples = {}
        for i, hand in ipairs(HANDS) do
            local bar = CreateFrame("StatusBar", nil, sampler)
            bar:SetFrameStrata("HIGH")
            bar.bg = bar:CreateTexture(nil, "BACKGROUND")
            bar.bg:SetAllPoints()
            bar.lines = Outline(bar, bar)
            bar.name = bar:CreateFontString(nil, "OVERLAY")
            bar.name:SetPoint("LEFT", 6, 0)
            bar.len = bar:CreateFontString(nil, "OVERLAY")
            bar.len:SetPoint("LEFT", bar.name, "RIGHT", 6, 0)
            bar.len:SetTextColor(1, 1, 1, 0.75)
            bar.time = bar:CreateFontString(nil, "OVERLAY")
            bar.time:SetPoint("RIGHT", -6, 0)
            bar.hand = hand
            samples[i] = bar
        end
    end
    for i, bar in ipairs(samples) do
        local theirs = _G[BLIZZARD[i]]
        local sb = type(theirs) == "table" and theirs.StatusBar
        bar:ClearAllPoints()
        if type(sb) == "table" and sb.GetLeft and sb:GetLeft() then
            bar:SetAllPoints(sb)
        else
            bar:SetSize(260, 20)
            bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 260 - (i - 1) * 26)
        end
        bar.length = 1.6 + i * 0.6
        bar.tenth = nil
        bar:SetStatusBarTexture(TEXTURES[db.texture] or TEXTURES.smooth)
        local c = db[bar.hand.color]
        bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
        bar.bg:SetColorTexture(0, 0, 0, db.bgAlpha)
        ShowLines(bar.lines, db.outline)
        bar:SetMinMaxValues(0, bar.length)
        for _, fs in ipairs({ bar.name, bar.time }) do fs:SetFont(YR.Style.FONT, db.font, "OUTLINE") end
        bar.len:SetFont(YR.Style.FONT, math.max(8, db.font - 1), "OUTLINE")
        bar.name:SetText(bar.hand.name)
        bar.len:SetText(("%.1fs"):format(bar.length))
        bar.len:SetShown(db.speed)
        bar:Show()
    end
    sampler:Show()
    -- (a preview that is kept up runs on from where it was when the look is changed under it)
    local start = (preview and sampler.start) or GetTime()
    sampler.start = start
    sampler:SetScript("OnUpdate", function(self)
        local elapsed = GetTime() - start
        if (not preview and elapsed > 4) or InCombatLockdown() then
            preview = false
            self:SetScript("OnUpdate", nil)
            self:Hide()                 -- our own frame: allowed at any time
            return
        end
        for _, bar in ipairs(samples) do
            local at = elapsed % bar.length
            bar:SetValue(at)
            local tenth = math.floor((bar.length - at) * 10)
            if tenth ~= bar.tenth then
                bar.tenth = tenth
                bar.time:SetText(("%.1f"):format(tenth / 10))
            end
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

-- ---------------------------------------------------------------------------
-- Preview: sample swings on every bar, started and stopped by you, so the look can be changed while
-- you watch it. On Headstart's own bars each sample swing is begun again as it runs out; on Blizzard's
-- dressed bars the sample bars over them keep going. It stops when you stop it, when the settings
-- window closes, and when a fight begins.
-- ---------------------------------------------------------------------------
local previewer
local function PreviewSwings(now)
    local began = false
    for i, hand in ipairs(HANDS) do
        local s = swings[hand.type]
        if not s or now - s.start >= s.length then
            swings[hand.type] = { start = now, length = 1.6 + i * 0.6, sample = true }
            began = true
        end
    end
    return began
end
function PreviewShow()
    if Dressed() then
        if previewer then previewer:SetScript("OnUpdate", nil) end
        return DressTest()
    end
    if sampler then sampler:SetScript("OnUpdate", nil) sampler:Hide() end
    if not Own() then return false, "turn the swing timer on first." end
    Build()
    previewer = previewer or CreateFrame("Frame")
    previewer:SetScript("OnUpdate", function(self)
        if not preview or InCombatLockdown() then
            self:SetScript("OnUpdate", nil)
            return
        end
        if PreviewSwings(GetTime()) then YR.SwingLayout() end
    end)
    PreviewSwings(GetTime())
    laid = nil
    YR.SwingLayout()
    return true
end
function YR.SwingPreviewing() return preview end
--- Start or stop the preview. Returns whether it is running, and why not when it couldn't start.
function YR.SwingPreview(on)
    if on then
        if InCombatLockdown() then return false, "not in combat." end
        if not YR.SwingOn() then return false, "turn the swing timer on first." end
        preview = true
        local ok, why = PreviewShow()
        if not ok then preview = false end
        return preview, why
    end
    preview = false
    if previewer then previewer:SetScript("OnUpdate", nil) end
    if sampler then sampler:SetScript("OnUpdate", nil) sampler:Hide() sampler.start = nil end
    for _, hand in ipairs(HANDS) do
        if swings[hand.type] and swings[hand.type].sample then swings[hand.type] = nil end
    end
    if holder then laid = nil YR.SwingLayout() end
    return false
end

local function OnEvent(_, event, a, b, c)
    if event == "PLAYER_SWING" then
        if holder and Own() then
            YR.SwingStart(b, a)
        elseif Dressed() then
            DressLength(b, a)
        end
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        if not YR.SwingOn() or type(a) ~= "number" or issecretvalue(a) or a < MAIN or a > RANGED then return end
        if issecretvalue(b) or issecretvalue(c) then return end
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
        if inCombat then RangeChecks() end
        if inCombat and preview then YR.SwingPreview(false) end
        YR.SwingLayout()
    elseif event == "PLAYER_TARGET_CHANGED" then
        RangeChecks()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- a weapon slot (main hand, off hand, ranged): nothing else you put on changes a swing bar
        if type(a) == "number" and (a < 16 or a > 18) then return end
        if holder then Icons() YR.SwingLayout() end
        if Dressed() then Dress() end
    elseif event == "ADDON_LOADED" then
        if a == "Blizzard_SwingTimer" then
            frame:UnregisterEvent("ADDON_LOADED")
            Apply()
        end
    else
        inCombat = UnitAffectingCombat("player") and true or false
        Apply()
    end
end

local function EditModeEnter()
    editing = true
    TheirBars()
    YR.SwingLayout()
end
local function EditModeExit()
    editing = false
    TheirBars()
    Dress()
    YR.SwingLayout()
end

-- Coming on: what the events would have told us had we been listening (a fight, Edit Mode open),
-- Edit Mode's two callbacks, and Blizzard's swing bars loading - where they haven't yet.
local function Begin(p)
    frame = p.frame
    local _, class = UnitClass("player")
    hunter = class == "HUNTER"
    inCombat = UnitAffectingCombat("player") and true or false
    local manager = _G.EditModeManagerFrame
    editing = type(manager) == "table" and manager.IsShown ~= nil and manager:IsShown() and true or false
    local registry = _G.EventRegistry
    if type(registry) == "table" and registry.RegisterCallback then
        registry:RegisterCallback("EditMode.Enter", EditModeEnter, frame)
        registry:RegisterCallback("EditMode.Exit", EditModeExit, frame)
    end
    if _G[BLIZZARD[1]] == nil then frame:RegisterEvent("ADDON_LOADED") end
    Apply()
end

-- Going off: the callbacks taken back, and Apply (which finds the timer off) puts Blizzard's bars back
-- as they were and takes ours away.
local function End()
    local registry = _G.EventRegistry
    if type(registry) == "table" and registry.UnregisterCallback then
        registry:UnregisterCallback("EditMode.Enter", frame)
        registry:UnregisterCallback("EditMode.Exit", frame)
    end
    editing = false
    Apply()
end

local EVENTS = { "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED", "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_TARGET_CHANGED" }

function YR.StartSwing()
    if part then return end
    part = YR.Part(YR.SwingOn, EVENTS, OnEvent, { start = Begin, stop = End, again = Apply })
end
