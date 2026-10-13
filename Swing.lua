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
--   Headstart's own bars each stand where you put them and have their own size: at[key] = { left,
--   top } from the screen's top left, size[key] = { w, h } (w and h until set); keys main, off, ranged,
--   health, power. use[key] = false: that swing bar isn't made. With lock off they all show and can
--   be dragged one by one.
--   Health and power bars (health = true, power = true; Headstart's own, whichever swing bars you
--   use): the same look, fed with your health and power as the game gives them - in a fight those are
--   kept from addons, and go to the bar unread. combo = true: your combo points as a row of squares
--   that fill, in the same look. comboColor ("swing": the main hand's colour; "class": your class's). resText (all, pct, value, none): the words on the two bars.
--   resTone ("muted": the game's colours taken down to sit beside the swing bars'; "bright": Blizzard's own, as they are). resShow ("combat": only in a fight), healthClass (the
--   bar in your class's colour), healthColor.
--   Account options (YippRouteDB.swing): on, hideBlizz, w, h, gap, pos, lock, texture, font, show
--   ("always" | "combat" | "swing"), name, time, speed, icon, spark, range, mainColor, offColor,
--   rangedColor, farColor, bgAlpha, outline (a thin dark line round each bar), style ("blizzard" | "own"), border (Blizzard's frame round a
--   dressed bar), colors (your colours on a dressed bar).
local ADDON, YR = ...

local MAIN, OFF, RANGED = 0, 1, 2
-- The "light" frame's line. Near white and solid: a greyer one was lost against a filled bar's own
-- colour (a full energy bar is as light as it was), and only read round an empty one.
local LINE_LIGHT = { 0.92, 0.92, 0.94, 1 }
local RIM_BRONZE = { 0.54, 0.45, 0.35, 1 }      -- the frames round Blizzard's action buttons, read off one
-- The look a new install gets is Slim: low flat bars close together, a nearly black back, each hand in a
-- quiet colour of its own with a brighter line at the front of the fill, and the hand's name in small
-- letters. Classic is the look Headstart had before (taller, shaded, blue). YR.SwingPreset puts either on.
-- Soft: quiet, mid-bright colours on a softly shaded fill over a half-clear dark back - nothing on it
-- but the hand's name. The colours are muted on purpose: a swing bar is looked at all fight long.
local PRESETS = {
    soft = { w = 240, h = 18, gap = 4, texture = "smooth", font = 12, name = true, time = false, speed = false, icon = false,
        spark = true, outline = true, rim = true, labelLeft = true, bgAlpha = 0.5, border = false, colors = true,
        mainColor = { 0.82, 0.34, 0.32, 1 }, offColor = { 0.84, 0.56, 0.28, 1 }, rangedColor = { 0.42, 0.70, 0.26, 1 },
        farColor = { 0.46, 0.46, 0.48, 1 }, healthColor = { 0.36, 0.70, 0.38, 1 }, palette = "muted", rimKind = "bronze" },
    slim = { w = 230, h = 14, gap = 1, texture = "flat", font = 11, name = true, time = false, speed = false, icon = false,
        spark = true, outline = true, rim = false, labelLeft = true, bgAlpha = 0.6, border = false, colors = true,
        mainColor = { 0.72, 0.24, 0.24, 1 }, offColor = { 0.80, 0.52, 0.20, 1 }, rangedColor = { 0.38, 0.66, 0.24, 1 },
        farColor = { 0.42, 0.42, 0.42, 1 }, palette = "deep", rimKind = "light" },
    classic = { w = 260, h = 20, gap = 3, texture = "smooth", font = 12, name = true, time = true, speed = true, icon = false,
        spark = false, outline = true, rim = false, labelLeft = false, bgAlpha = 0.65, border = false, colors = true,
        mainColor = { 0.20, 0.45, 1.00, 1 }, offColor = { 0.15, 0.75, 0.95, 1 }, rangedColor = { 0.95, 0.65, 0.15, 1 },
        farColor = { 0.85, 0.20, 0.20, 1 }, palette = "blue", rimKind = "thin" },
}
YR.SWING_PRESETS = PRESETS

-- Colours are picked as a set, not one by one: a palette is the three hands' colours, the colour of
-- a hand out of reach, and the health bar's. "class" is made from your class's colour when picked.
local PALETTES = {
    muted = { mainColor = { 0.82, 0.34, 0.32, 1 }, offColor = { 0.84, 0.56, 0.28, 1 }, rangedColor = { 0.42, 0.70, 0.26, 1 },
        farColor = { 0.46, 0.46, 0.48, 1 }, healthColor = { 0.36, 0.70, 0.38, 1 } },
    deep = { mainColor = { 0.72, 0.24, 0.24, 1 }, offColor = { 0.80, 0.52, 0.20, 1 }, rangedColor = { 0.38, 0.66, 0.24, 1 },
        farColor = { 0.42, 0.42, 0.42, 1 }, healthColor = { 0.28, 0.62, 0.30, 1 } },
    blue = { mainColor = { 0.20, 0.45, 1.00, 1 }, offColor = { 0.15, 0.75, 0.95, 1 }, rangedColor = { 0.95, 0.65, 0.15, 1 },
        farColor = { 0.85, 0.20, 0.20, 1 }, healthColor = { 0.30, 0.78, 0.36, 1 } },
    bronze = { mainColor = { 0.78, 0.60, 0.34, 1 }, offColor = { 0.62, 0.48, 0.30, 1 }, rangedColor = { 0.86, 0.74, 0.46, 1 },
        farColor = { 0.40, 0.36, 0.32, 1 }, healthColor = { 0.60, 0.68, 0.36, 1 } },
    grey = { mainColor = { 0.78, 0.78, 0.80, 1 }, offColor = { 0.58, 0.58, 0.62, 1 }, rangedColor = { 0.90, 0.90, 0.92, 1 },
        farColor = { 0.34, 0.34, 0.36, 1 }, healthColor = { 0.70, 0.74, 0.70, 1 } },
}
YR.SWING_PALETTES = { { "muted", "Muted" }, { "deep", "Deep" }, { "blue", "Blue and orange" }, { "bronze", "Bronze" },
    { "grey", "Grey" }, { "class", "Class colour" } }
-- The frame round a bar, as one choice: none, a thin dark line, or the dark line with a second one
-- round it in bronze (the frames of Blizzard's action buttons), silver, or your class's colour.
YR.SWING_FRAMES = { { "light", "Thin light line" }, { "bronze", "Bronze" }, { "silver", "Silver" }, { "class", "Class colour" }, { "thin", "Thin dark line" },
    { "none", "None" } }
-- What a bar says, as one choice.
YR.SWING_TEXTS = { { "name", "Name" }, { "time", "Name and time left" }, { "all", "Name, time left and swing length" },
    { "none", "Nothing" } }

local function ClassColour()
    local _, class = UnitClass("player")
    local c = RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]
    if type(c) == "table" and c.r then return c.r, c.g, c.b end
    return 0.82, 0.34, 0.32
end
-- place: where Headstart's own bars stand. "edit": exactly over Blizzard's swing bars, so Edit Mode is
-- the one place both kinds are moved and sized, and changing between the two looks moves nothing.
-- "own": where you drag them, at the size set here (what it was before; kept for whoever had moved them).
local DEFAULT = { on = false, hideBlizz = true, lock = true, show = "combat", range = true, style = "blizzard",
    border = false, colors = true, place = "edit", resShow = "always", healthColor = { 0.30, 0.78, 0.36, 1 },
    rimColor = { 0.54, 0.45, 0.35, 1 }, fontFace = "blizzard", resText = "all", resTone = "bright", comboColor = "swing" }
for k, v in pairs(PRESETS.slim) do DEFAULT[k] = v end
YR.SWING_DEFAULT = DEFAULT
local TEXTURES = {
    flat = "Interface\\Buttons\\WHITE8X8",
    blizzard = "Interface\\TargetingFrame\\UI-StatusBar",
    smooth = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}
local HANDS = {
    { type = MAIN, key = "main", name = "Main hand", slot = 16, color = "mainColor" },
    { type = OFF, key = "off", name = "Off hand", slot = 17, color = "offColor" },
    { type = RANGED, key = "ranged", name = "Ranged", slot = 18, color = "rangedColor" },
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
    -- One thin light line and a flat fill (2026-10-12): the double bronze frame read as thick and hard
    -- beside other addons' bars. Everyone starts from it once; the other frames are still to pick.
    if db.look < 4 then
        db.outline, db.rim, db.rimKind, db.lineColor = true, false, "light", { unpack(LINE_LIGHT) }
        db.texture, db.resOwn, db.res, db.look = "flat", nil, nil, 4
    end
    -- "Move bars" for health, power and combo could be turned on and never off again (a fault in its
    -- switch), which left them unlocked, with their names and the band they are dragged by: locked, once.
    if db.look < 5 then db.resLock, db.look = nil, 5 end
    -- Blizzard's own colours for health and power, now that the fill is shaded as Blizzard's is: the
    -- muted ones under that shade came out grey and dirty. Once; Muted is still to pick.
    if db.look < 6 then db.resTone, db.look = "bright", 6 end
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
-- out: how far outside the bar the line runs (1: against it; 2: round that one). colour: black unless given.
-- cut: the line stops one pixel short of each corner, so the corner pixel is left out and the frame
-- reads as rounded rather than as a hard box.
-- Everything is in whole screen pixels (one of the screen's own, whatever the UI's scale): a line
-- "1" wide at another scale is drawn across two pixels, grey and thick.
-- The line round the dark one, in the bronze of the frames round Blizzard's action buttons (read off
-- one), so our bars sit among them as theirs do; yours to pick (rimColor).
local RIM = RIM_BRONZE
local BLACK = { 0, 0, 0, 1 }
local function Outline(owner, around, out, colour, cut)
    local lines = {}
    local px = 1
    if PixelUtil and PixelUtil.GetNearestPixelSize and owner.GetEffectiveScale then
        local scale = owner:GetEffectiveScale()
        if type(scale) == "number" and scale > 0 then px = PixelUtil.GetNearestPixelSize(1, scale, 1) end
    end
    out = (out or 1) * px
    local short = cut and px or 0
    for i, at in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = owner:CreateTexture(nil, "BORDER")
        if colour then t:SetColorTexture(colour[1], colour[2], colour[3], colour[4]) else t:SetColorTexture(0, 0, 0, 1) end
        -- along the line it is pulled in by `short`; across it, it stands `out` from the bar
        local alongX, alongY = (i <= 2) and short or 0, (i > 2) and short or 0
        t:SetPoint(at[1], around, at[1], (at[1]:find("LEFT") and (-out + alongX) or (out - alongX)), (at[1]:find("TOP") and (out - alongY) or (-out + alongY)))
        t:SetPoint(at[2], around, at[2], (at[2]:find("LEFT") and (-out + alongX) or (out - alongX)), (at[2]:find("TOP") and (out - alongY) or (-out + alongY)))
        if i <= 2 then t:SetHeight(px) else t:SetWidth(px) end
        lines[i] = t
    end
    return lines
end
local function ShowLines(lines, on) for _, t in ipairs(lines) do t:SetShown(on) end end
-- The line against the bar: black, or the look's own (lineColor: the "light" frame, whose line is two
-- pixels of the one colour - this line and the one round it, which has the corner pixel left out).
local function Inner(lines, look)
    local c = look.lineColor and LINE_LIGHT or BLACK      -- (lineColor only says "the light frame": its colour is the one here)
    for _, t in ipairs(lines) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end
local function Tone(lines, c)
    c = (type(c) == "table" and c[1]) and c or RIM
    for _, t in ipairs(lines) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end
-- The bars' letters: the game's own (what Blizzard writes its frames in), or Headstart's narrow one.
local function Face(look)
    look = look or YippRouteDB.swing
    if type(look) == "table" and look.fontFace == "headstart" then return YR.Style.FONT end
    local game = _G.GameFontNormal
    local file = type(game) == "table" and game.GetFont and game:GetFont()
    return type(file) == "string" and file or "Fonts\\FRIZQT__.TTF"
end

-- Headstart's own bars: each stands where you put it, at its own size. Until moved they stand in a
-- stack at the bottom middle of the screen (rows up from the base: off hand, main hand, ranged, then
-- power and health).
local ROW = { off = 0, main = 1, ranged = 2, combo = 3, power = 4, health = 5, range = 6, cast = 7 }
local function BarSize(db, key)
    local size = db.size and db.size[key]
    local w, h = size and size[1] or db.w, size and size[2] or db.h
    return math.max(40, tonumber(w) or 230), math.max(4, tonumber(h) or 14)
end
--- A bar's width and height as set (its key: main, off, ranged, health, power).
function YR.SwingBarSize(key) return BarSize(YR.SwingDB(), key) end
local function PlaceBar(bar, db, key)
    local w, h = BarSize(db, key)
    bar:SetSize(w, h)
    bar:ClearAllPoints()
    local at = db.at and db.at[key]
    if at and at[1] and at[2] then
        bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", at[1], at[2])
    else
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200 + (ROW[key] or 0) * (db.h + db.gap + 3))
    end
end
-- The swing bars are unlocked by one switch (lock), the health and power bars by another (resLock):
-- they are two things, each with its own settings.
local function Unlocked(key)
    local db = YR.SwingDB()
    if key == "health" or key == "power" or key == "combo" then return db.resLock == false end
    if key == "cast" then return db.castLock == false end
    return not db.lock
end
-- Dragged while the bars are unlocked; where it is let go is kept for that bar alone.
local function Draggable(bar, key)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) if Unlocked(key) then self:StartMoving() end end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db = YR.SwingDB()
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then
            db.at = db.at or {}
            db.at[key] = { math.floor(left + 0.5), math.floor(top - UIParent:GetTop() + 0.5) }
        end
        PlaceBar(self, db, key)
    end)
    -- what says "this can be dragged" while unlocked
    bar.edge = bar:CreateTexture(nil, "BACKGROUND", nil, -2)
    bar.edge:SetPoint("TOPLEFT", -4, 4)
    bar.edge:SetPoint("BOTTOMRIGHT", 4, -4)
    local accent = YR.Style and YR.Style.C and YR.Style.C.accent or { 1.00, 0.56, 0.20 }
    bar.edge:SetColorTexture(accent[1], accent[2], accent[3], 0.30)
    bar.edge:Hide()
end

local holder
local bars = {}             -- [swing type] = the bar
local swings = {}           -- [swing type] = { start, length } of the swing on its way
local far = {}              -- [swing type] = true while the target is out of reach
local checks = {}           -- [swing type] = true while the game is checking that hand's reach at all
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
    if db.use and db.use[hand.key] == false then return false end
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
-- Out of reach is also said in words, where the time is: a bar between swings is empty, and an empty
-- bar has no colour to change.
local FAR_WORDS, FAR_COLOUR = "Out of range", { 1, 0.36, 0.30 }
local function Colour(bar, db)
    local out = (db.range and far[bar.hand.type]) and true or false
    local c = out and db.farColor or db[bar.hand.color]
    bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
    if bar.far then
        bar.far:SetShown(out)
        bar.time:SetAlpha(out and 0 or 1)
    end
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
    -- between swings the bar is empty (or full, where you asked for that): a full bright bar standing
    -- there all fight long is the loudest thing on the screen
    if not running then elapsed = db.idleFull == true and length or 0 end
    -- the swing's length is the same from frame to frame: told to the bar only when it's another
    if bar.span ~= length then
        bar.span = length
        bar:SetMinMaxValues(0, length > 0 and length or 1)
    end
    bar:SetValue(length > 0 and elapsed or (db.idleFull == true and 1 or 0))
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
                Colour(bar, db)
                n = n + 1
            end
        end
        holder:SetShown(n > 0)
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

-- What every bar of ours wears: the texture, the dark back, the dark line and the light one round it.
local function StyleBar(bar, look)
    bar:SetStatusBarTexture(TEXTURES[look.texture] or TEXTURES.smooth)
    bar.bg:SetColorTexture(0, 0, 0, look.bgAlpha or 0.5)
    ShowLines(bar.lines, look.outline)
    Inner(bar.lines, look)
    ShowLines(bar.rim, look.outline and (look.rim ~= false or look.lineColor ~= nil))
    Tone(bar.rim, look.lineColor and LINE_LIGHT or look.rimColor)
    local unlocked = Unlocked(bar.key)
    bar:EnableMouse(unlocked)
    bar.edge:SetShown(unlocked)
end

-- The health, power and combo bars' look: the frame, the texture, the dark back and the font. It is
-- the swing bars' look, so every bar of ours reads as one set, until you pick one for these alone
-- (resOwn = true): then it is YippRouteDB.swing.res, which starts as the swing bars' look was then.
local LOOK_KEYS = { "texture", "outline", "rim", "rimColor", "rimKind", "lineColor", "bgAlpha", "font", "fontFace" }
function YR.ResourceLook()
    local db = YR.SwingDB()
    if db.resOwn ~= true then return db end
    local look = db.res
    if type(look) ~= "table" then look = {} db.res = look end
    for _, k in ipairs(LOOK_KEYS) do
        if look[k] == nil then
            local v = db[k]
            look[k] = type(v) == "table" and { unpack(v) } or v
        end
    end
    return look
end
--- Whether the health, power and combo bars wear a look of their own (true), or the swing bars' (false).
--- Turned on, it starts from the swing bars' look as it is now.
function YR.ResourceLookOwn(own)
    local db = YR.SwingDB()
    if own == nil then return db.resOwn == true end
    if own and db.resOwn ~= true then db.res = nil end
    db.resOwn = own and true or nil
    return db.resOwn == true
end
local function NewBar(parent, key)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar.key = key
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.lines = Outline(bar, bar)
    bar.rim = Outline(bar, bar, 2, RIM, true)
    Draggable(bar, key)
    return bar
end

-- The look: what only a setting changes.
local function Look()
    local db = YR.SwingDB()
    laid = nil                      -- which bars show, and their colours: gone over again
    for _, hand in ipairs(HANDS) do
        local bar = bars[hand.type]
        PlaceBar(bar, db, hand.key)
        StyleBar(bar, db)
        local _, h = BarSize(db, hand.key)
        bar.icon:SetSize(h, h)
        bar.icon:SetShown(db.icon)
        bar.spark:SetSize(2, h)
        bar.name:SetFont(Face(), db.font, "OUTLINE")
        bar.time:SetFont(Face(), db.font, "OUTLINE")
        bar.far:SetFont(Face(), db.font, "OUTLINE")
        bar.name:SetShown(db.name)
        bar.left, bar.length = nil, nil          -- the words are written again
    end
    Icons()
end

local function Build()
    if holder then return end
    -- the bars' parent: it shows and hides them together and carries the one OnUpdate; where each
    -- bar stands is its own (PlaceBar)
    holder = CreateFrame("Frame", "HeadstartSwing", UIParent)
    holder:SetFrameStrata("LOW")
    holder:SetSize(1, 1)
    holder:SetPoint("CENTER")
    for _, hand in ipairs(HANDS) do
        local bar = NewBar(holder, hand.key)
        bar.hand = hand
        bar.icon = bar:CreateTexture(nil, "ARTWORK")
        bar.icon:SetPoint("RIGHT", bar, "LEFT", -2, 0)
        bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        bar.spark = bar:CreateTexture(nil, "OVERLAY")
        bar.spark:SetColorTexture(1, 1, 0.8, 0.95)
        bar.name = bar:CreateFontString(nil, "OVERLAY")
        bar.name:SetPoint("LEFT", 6, 0)
        bar.name:SetFont(Face(), 12, "OUTLINE")
        bar.name:SetText(hand.name)
        bar.time = bar:CreateFontString(nil, "OVERLAY")
        bar.time:SetPoint("RIGHT", -6, 0)
        bar.time:SetFont(Face(), 12, "OUTLINE")
        bar.far = bar:CreateFontString(nil, "OVERLAY")
        bar.far:SetPoint("RIGHT", -6, 0)
        bar.far:SetFont(Face(), 12, "OUTLINE")
        bar.far:SetText(FAR_WORDS)
        bar.far:SetTextColor(FAR_COLOUR[1], FAR_COLOUR[2], FAR_COLOUR[3])
        bar.far:Hide()
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
    db.lineColor = p.rimKind == "light" and { unpack(LINE_LIGHT) } or nil
    YR.SwingApply()
    return true
end

--- A set of colours put on (one of YR.SWING_PALETTES). Nothing else of the look changes.
function YR.SwingPalette(key)
    local db = YR.SwingDB()
    local set = PALETTES[key]
    if key == "class" then
        local r, g, b = ClassColour()
        set = { mainColor = { r, g, b, 1 }, offColor = { r * 0.72, g * 0.72, b * 0.72, 1 },
            rangedColor = { r + (1 - r) * 0.35, g + (1 - g) * 0.35, b + (1 - b) * 0.35, 1 },
            farColor = { 0.42, 0.42, 0.44, 1 }, healthColor = { r, g, b, 1 } }
    end
    if not set then return false end
    for k, v in pairs(set) do db[k] = { unpack(v) } end
    db.palette, db.colors = key, true
    YR.SwingApply()
    return true
end

--- The frame round every bar (one of YR.SWING_FRAMES).
function YR.SwingFrame(key, look)       -- look: the health and power bars' own (YR.ResourceLook), not the swing bars'
    local db = look or YR.SwingDB()
    db.lineColor = nil
    if key == "none" then
        db.outline, db.rim = false, false
    elseif key == "light" then
        db.outline, db.rim, db.lineColor = true, false, { unpack(LINE_LIGHT) }
    elseif key == "thin" then
        db.outline, db.rim = true, false
    elseif key == "silver" then
        db.outline, db.rim, db.rimColor = true, true, { 0.62, 0.62, 0.66, 0.90 }
    elseif key == "class" then
        local r, g, b = ClassColour()
        db.outline, db.rim, db.rimColor = true, true, { r, g, b, 1 }
    else
        key = "bronze"
        db.outline, db.rim, db.rimColor = true, true, { unpack(RIM_BRONZE) }
    end
    db.rimKind = key
    YR.SwingApply()
    return true
end
--- Which frame is on, by how the look is set (a preset or an older setting may have set it).
function YR.SwingFrameNow(look)
    local db = look or YR.SwingDB()
    if not db.outline then return "none" end
    if db.rim == false then return db.lineColor and "light" or "thin" end
    return db.rimKind == "silver" and "silver" or db.rimKind == "class" and "class" or "bronze"
end

--- What a bar says (one of YR.SWING_TEXTS).
function YR.SwingText(key)
    local db = YR.SwingDB()
    db.name = key ~= "none"
    db.time = key == "time" or key == "all"
    db.speed = key == "all"
    YR.SwingApply()
    return true
end
function YR.SwingTextNow()
    local db = YR.SwingDB()
    if not db.name then return "none" end
    if db.time and db.speed then return "all" end
    return db.time and "time" or "name"
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
    local out = (k.on and db.range and far[k.hand.type]) and true or false
    if k.far then
        -- the words, where Blizzard's time is (that made see-through meanwhile, and given back after)
        k.far:SetShown(out)
        if k.timeLabel and k.farOn ~= out then
            k.farOn = out
            k.timeLabel:SetAlpha(out and 0 or 1)
        end
    end
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
                -- a light line round the dark one: the bar's edge reads on a dark screen and on snow
                k.rim = Outline(f, sb, 2, RIM, true)
                -- where Blizzard has the bar's name (for putting it back)
                k.points, k.justify = {}, {}
                for n, label in ipairs(k.labels) do
                    local kept = {}
                    for p = 1, (label.GetNumPoints and label:GetNumPoints() or 0) do kept[p] = { pcall(label.GetPoint, label, p) } end
                    k.points[n] = kept
                    k.justify[n] = label.GetJustifyH and label:GetJustifyH() or nil
                end
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
                k.far = sb:CreateFontString(nil, "OVERLAY")
                k.far:SetPoint("RIGHT", sb, "RIGHT", -5, 0)
                k.far:SetFont(Face(), db.font or 12, "OUTLINE")
                k.far:SetText(FAR_WORDS)
                k.far:SetTextColor(FAR_COLOUR[1], FAR_COLOUR[2], FAR_COLOUR[3])
                k.far:Hide()
                local got, timeLabel = pcall(function() return f:GetTimeLabel() end)
                k.timeLabel = got and type(timeLabel) == "table" and timeLabel.SetAlpha and timeLabel or nil
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
                Inner(k.lines, db)
                ShowLines(k.rim, db.outline and (db.rim ~= false or db.lineColor ~= nil))
                Tone(k.rim, db.lineColor and LINE_LIGHT or db.rimColor)
                for _, label in ipairs(k.labels) do label:SetFont(Face(), db.font, "OUTLINE") end
                -- the bar's name at its left end (its shadow with it), or where Blizzard has it
                for n = 1, math.min(2, #k.labels) do
                    local label = k.labels[n]
                    if db.labelLeft ~= false and label ~= (f.GetTimeLabel and select(2, pcall(f.GetTimeLabel, f)) or nil) then
                        label:ClearAllPoints()
                        label:SetPoint("LEFT", sb, "LEFT", 5 + (n == 2 and 1 or 0), n == 2 and -1 or 0)
                        if label.SetJustifyH then label:SetJustifyH("LEFT") end
                        k.moved = true
                    elseif k.moved then
                        label:ClearAllPoints()
                        for _, pt in ipairs(k.points[n] or {}) do if pt[1] then label:SetPoint(pt[2], pt[3], pt[4], pt[5], pt[6]) end end
                        if k.justify[n] and label.SetJustifyH then label:SetJustifyH(k.justify[n]) end
                    end
                end
                if db.labelLeft == false then k.moved = false end
                k.length:SetFont(Face(), math.max(8, db.font - 1), "OUTLINE")
                k.far:SetFont(Face(), db.font, "OUTLINE")
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
                k.far:Hide()
                if k.timeLabel and k.farOn then k.timeLabel:SetAlpha(1) end
                k.farOn = nil
                k.spark:Hide()
                k.fill:Hide()
                ShowLines(k.lines, false)
                ShowLines(k.rim, false)
                if k.moved then
                    k.moved = false
                    for n = 1, math.min(2, #k.labels) do
                        local label = k.labels[n]
                        label:ClearAllPoints()
                        for _, pt in ipairs(k.points[n] or {}) do if pt[1] then label:SetPoint(pt[2], pt[3], pt[4], pt[5], pt[6]) end end
                        if k.justify[n] and label.SetJustifyH then label:SetJustifyH(k.justify[n]) end
                    end
                end
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
        for _, hand in ipairs(HANDS) do far[hand.type], checks[hand.type] = nil, nil end
        return
    end
    local swing = _G.C_SwingTimer
    if type(swing) ~= "table" or type(swing.EnableRangeCheck) ~= "function" then return end
    for _, hand in ipairs(HANDS) do pcall(swing.EnableRangeCheck, hand.type, true) end
end

-- The range bar (rangeBar = true): a bar of ours that says whether what you have targeted is within
-- reach - in a fight and out of one, where the swing bars are mostly out of sight or empty. It shows
-- while you have something alive you can attack targeted and the game is checking the reach (it says
-- when it is not: then there is nothing true to show, and the bar is away). A hunter's says which reach:
-- melee, ranged, or neither. At its right end, how far the target is, as a span of yards. Placed, sized
-- and dressed as the other bars of ours are (its key: "range").
local rangeBar
local RANGE_IN, RANGE_MELEE, RANGE_OUT = { 0.28, 0.60, 0.34 }, { 0.80, 0.56, 0.24 }, { 0.62, 0.20, 0.20 }
local function Truly(v) return not (issecretvalue and issecretvalue(v)) and v and true or false end
-- How far the target is, as near as an addon can tell. The game gives no distance, but it does say
-- whether an item's use would reach a target, and that for an item you do not have: so one item of each
-- reach (5 yards, 10, 15 ... 40) is asked about, and the answer is a span: farther than the longest
-- that falls short, within the shortest that reaches. Several items a reach, as an item only answers
-- for a target its use could be put on - the first that answers is taken, and a reach where none does
-- is left out (the span is then wider there). The reaches are the items' own, from the game's data
-- (build 70334: item, its use spell, that spell's range): 5 to 40 yards.
local YARDS = {
    { 5, { 8149 } }, { 10, { 17626, 17689 } }, { 15, { 273643 } }, { 20, { 10645, 4388 } }, { 25, { 13289 } },
    { 30, { 835, 7734 } }, { 35, { 18904, 1399 } }, { 40, { 4945, 8348 } },
}
-- (Each of these answered for a hostile target in the game, 2026-10-12; the ones tried at 45 yards did
-- not, so 40 is the longest. An item answers nothing until the client has its data: asked for once.)
local yardsAsked
local function YardsLoad()
    if yardsAsked then return end
    yardsAsked = true
    local load = type(C_Item) == "table" and C_Item.RequestLoadItemDataByID
    if not load then return end
    for _, step in ipairs(YARDS) do
        for _, id in ipairs(step[2]) do pcall(load, id) end
    end
end
local function Reaches(ids)
    local ask = type(C_Item) == "table" and C_Item.IsItemInRange
    if not ask then return nil end
    for _, id in ipairs(ids) do
        local ok, r = pcall(ask, id, "target")
        if ok and not (issecretvalue and issecretvalue(r)) and r ~= nil then return r and true or false end
    end
    return nil
end
-- more than `least` yards, at most `most` (either nil where it could not be told)
local function Yards()
    -- Only of something you can attack. Asked about a friend in a fight, the game takes the question
    -- for an action an addon may not take (it is allowed of an enemy, or out of a fight) - and with a
    -- party member clicked on in a fight that was thirteen of them, five times a second.
    if not (Truly(UnitExists("target")) and Truly(UnitCanAttack("player", "target"))) then return nil, nil end
    local least, most
    for _, step in ipairs(YARDS) do
        local r = Reaches(step[2])
        if r == true then most = step[1] break end
        if r == false then least = step[1] end
    end
    return least, most
end

-- What the range bar says now: its words, its colour, the yards. The swing's own check where the
-- game is making it (it is the truth of whether a swing lands); else what the yards say.
local function RangePaint()
    local bar = rangeBar
    local least, most = Yards()
    local melee, ranged                 -- true / false, or nil where it isn't known
    if checks[MAIN] then melee = not far[MAIN]
    elseif most then melee = most <= 5
    elseif least then melee = false end
    if checks[RANGED] then ranged = not far[RANGED]
    elseif most then ranged = most <= 35
    elseif least then ranged = least < 35 and nil or false end
    local words, c
    if hunter and (melee ~= nil or ranged ~= nil) then
        if melee then words, c = "Melee range", RANGE_MELEE
        elseif ranged then words, c = "In range", RANGE_IN
        else words, c = "Out of range", RANGE_OUT end
    elseif melee ~= nil then
        if melee then words, c = "In range", RANGE_IN else words, c = "Out of range", RANGE_OUT end
    end
    bar.known = words ~= nil
    if not words then words, c = "Range", RANGE_IN end        -- (only seen while the bars are being placed)
    local yards = ""
    if least and most then yards = least .. " - " .. most .. " yd"
    elseif most then yards = "< " .. most .. " yd"
    elseif least then yards = "> " .. least .. " yd" end
    if bar.said ~= words then
        bar.said = words
        bar.name:SetText(words)
        bar:SetStatusBarColor(c[1], c[2], c[3], 1)
    end
    if bar.told ~= yards then
        bar.told = yards
        bar.yards:SetText(yards)
    end
end

local function RangeBarApply()
    local db = YippRouteDB.swing
    if not (YR.SwingOn() and type(db) == "table" and db.rangeBar == true) then
        if rangeBar then rangeBar:Hide() end
        return
    end
    db = YR.SwingDB()
    if not rangeBar then
        rangeBar = NewBar(UIParent, "range")
        rangeBar:SetFrameStrata("LOW")
        rangeBar.name = rangeBar:CreateFontString(nil, "OVERLAY")
        rangeBar.name:SetPoint("LEFT", 6, 0)
        rangeBar.name:SetFont(Face(), db.font or 12, "OUTLINE")
        rangeBar.yards = rangeBar:CreateFontString(nil, "OVERLAY")
        rangeBar.yards:SetPoint("RIGHT", -6, 0)
        rangeBar.yards:SetFont(Face(), db.font or 12, "OUTLINE")
        rangeBar:SetMinMaxValues(0, 1)
        rangeBar:SetValue(1)
        YardsLoad()
        -- nothing tells an addon that the target came nearer: looked at five times a second, and only
        -- while the bar shows (a hidden frame's OnUpdate does not run)
        local since = 0
        rangeBar:SetScript("OnUpdate", function(_, elapsed)
            since = since + (elapsed or 0)
            if since < 0.2 then return end
            since = 0
            RangePaint()
        end)
    end
    PlaceBar(rangeBar, db, "range")
    StyleBar(rangeBar, db)
    rangeBar.name:SetFont(Face(), db.font or 12, "OUTLINE")
    rangeBar.yards:SetFont(Face(), db.font or 12, "OUTLINE")
    local target = Truly(UnitExists("target")) and Truly(UnitCanAttack("player", "target")) and not Truly(UnitIsDead("target"))
    rangeBar.said, rangeBar.told = nil, nil
    RangePaint()
    rangeBar:SetShown(not db.lock or (target and rangeBar.known) and true or false)
end

-- The range bar's words and whether it shows, as things are now: what a target changing or the range
-- flipping asks for. (All of RangeBarApply - placed, dressed, its fonts set - is for a setting changing;
-- at the edge of melee range it ran several times a second.)
local function RangeBarNow()
    local db = YippRouteDB.swing
    if not (rangeBar and YR.SwingOn() and type(db) == "table" and db.rangeBar == true) then return RangeBarApply() end
    db = YR.SwingDB()
    local target = Truly(UnitExists("target")) and Truly(UnitCanAttack("player", "target")) and not Truly(UnitIsDead("target"))
    RangePaint()
    rangeBar:SetShown(not db.lock or (target and rangeBar.known) and true or false)
end

-- Built, sized, placed and shown as it is now - or, with the timer off, everything put back.
local function Apply()
    if holder then Look() elseif Own() then Build() end
    TheirBars()
    Dress()
    RangeChecks()
    YR.SwingLayout()
    RangeBarApply()
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
    if YR.ResourceLookApply then YR.ResourceLookApply() end      -- the bars that wear the same look (BarHide.lua)
    if YR.ResourceBarsApply then YR.ResourceBarsApply() end      -- (off, and never made: nothing to do there)
    if YR.CastBarApply then YR.CastBarApply() end
end

-- ---------------------------------------------------------------------------
-- The same look on another of Blizzard's bars
-- ---------------------------------------------------------------------------
-- The swing bars' texture, dark back, outline and light edge, put on any status bar of Blizzard's that
-- colours itself with a plain colour (the personal resource display's health and power bars do: their
-- colour is Blizzard's still, only what it is painted on is ours). What the bar had is kept beside ours
-- and put back when the look comes off. Nothing is written onto the bar, moved or resized.
local looked = setmetatable({}, { __mode = "k" })       -- [a status bar of Blizzard's] = what it had, and ours
--- on: wear the look as it is set now; off: as Blizzard has it. Returns whether the bar is one we can dress.
function YR.BarLook(sb, on)
    if type(sb) ~= "table" or type(sb.SetStatusBarTexture) ~= "function" or type(sb.GetStatusBarTexture) ~= "function" then return false end
    local k = looked[sb]
    if on and not k then
        local t = sb:GetStatusBarTexture()
        k = {}
        looked[sb] = k
        k.atlas = type(t) == "table" and t.GetAtlas and t:GetAtlas() or nil
        k.file = type(t) == "table" and t.GetTexture and t:GetTexture() or nil
        k.fill = sb:CreateTexture(nil, "BACKGROUND")
        k.fill:SetAllPoints(sb)
        k.lines = Outline(sb, sb)
        k.rim = Outline(sb, sb, 2, RIM, true)
    end
    if not k then return true end
    if on then
        local db = YR.ResourceLook()
        k.on = true
        sb:SetStatusBarTexture(TEXTURES[db.texture] or TEXTURES.smooth)
        k.fill:SetColorTexture(0, 0, 0, db.bgAlpha)
        k.fill:Show()
        ShowLines(k.lines, db.outline)
        Inner(k.lines, db)
        ShowLines(k.rim, db.outline and (db.rim ~= false or db.lineColor ~= nil))
        Tone(k.rim, db.lineColor and LINE_LIGHT or db.rimColor)
    elseif k.on then
        k.on = false
        if k.atlas then sb:SetStatusBarTexture(k.atlas) elseif k.file then sb:SetStatusBarTexture(k.file) end
        k.fill:Hide()
        ShowLines(k.lines, false)
        ShowLines(k.rim, false)
    end
    return true
end

--- One bar of ours back where it stands on a new install (its key), or all of them (no key).
function YR.SwingResetPosition(key)
    local db = YR.SwingDB()
    db.pos = nil
    if key then
        if db.at then db.at[key] = nil end
    else
        db.at = nil
    end
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
        Inner(bar.lines, db)
        bar:SetMinMaxValues(0, bar.length)
        for _, fs in ipairs({ bar.name, bar.time }) do fs:SetFont(Face(), db.font, "OUTLINE") end
        bar.len:SetFont(Face(), math.max(8, db.font - 1), "OUTLINE")
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
    if not Own() then
        -- (the timer switched off under a running preview: it ran on, a frame at a time, with nothing to show)
        if previewer then previewer:SetScript("OnUpdate", nil) end
        return false, "turn the swing timer on first."
    end
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
        local checked = c == true
        local changed = far[a] ~= out or checks[a] ~= checked
        checks[a] = checked
        if far[a] ~= out then
            far[a] = out
            if Dressed() then
                DressTint(a)
            elseif holder and bars[a]:IsShown() then
                Colour(bars[a], YR.SwingDB())
            end
        end
        if changed then RangeBarNow() end
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        inCombat = event == "PLAYER_REGEN_DISABLED"
        if inCombat then RangeChecks() end
        if inCombat and preview then YR.SwingPreview(false) end
        YR.SwingLayout()
    elseif event == "PLAYER_TARGET_CHANGED" then
        RangeChecks()
        RangeBarNow()
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

-- ---------------------------------------------------------------------------
-- Health and power bars
-- ---------------------------------------------------------------------------
-- Two bars of our own in the same look, each where you put it. They are plain status bars handed your
-- health and your power as the game gives them: in a fight those numbers are kept from addons, and a
-- status bar draws them all the same - so nothing here reads, compares or writes a number. The power
-- bar takes the colour the game has for what you spend (rage, energy, mana).
local RESOURCES = { "health", "power" }
local res = {}                  -- [key] = the bar
local resCombat = false
local EASE = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut or nil

local function ResWant(key)
    local db = YippRouteDB.swing
    if type(db) ~= "table" then return false end
    -- combo points come with the power bar unless turned off (or on, by themselves): a rogue who turns
    -- the power bar on means the points too
    if key == "combo" and db.combo == nil then return db.power == true end
    return db[key] == true
end
YR.ResourceBarWanted = ResWant
function YR.ResourceBarsOn() return YR.QoLOn() and (ResWant("health") or ResWant("power") or ResWant("combo")) end

local function Feed(bar, value, most)
    -- (through pcall: what the game hands over in a fight is not ours to look at, and a client that
    -- won't take it from an addon must not break the bar)
    pcall(bar.SetMinMaxValues, bar, 0, most)
    if EASE then pcall(bar.SetValue, bar, value, EASE) else pcall(bar.SetValue, bar, value) end
end
-- What a bar says (resText): the percent at its left end, the number at its right. The number goes to
-- the text unread, as it goes to the bar. The percent is worked out here where the game lets the
-- numbers be read; where it keeps them secret, the game is asked for the percent itself (already out
-- of a hundred, by its own curve) and that goes to the text unread too. Neither to be had: no words.
local function Plain(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) end
local function Say(bar, value, most, ask)
    if bar.amount:IsShown() then
        if not pcall(bar.amount.SetText, bar.amount, value) then bar.amount:SetText("") end
    end
    if not bar.pct:IsShown() then return end
    if Plain(value) and Plain(most) then
        bar.pct:SetText(most > 0 and (math.floor(value / most * 100 + 0.5) .. "%") or "")
        return
    end
    -- (two plain calls, not a function made for the purpose: this runs at every change of health or
    -- power in a fight, which is when the numbers are kept from addons)
    local curve = type(CurveConstants) == "table" and CurveConstants.ScaleTo100 or nil
    if curve and ask then
        local ok, pct = pcall(ask, curve)
        if ok and pcall(bar.pct.SetFormattedText, bar.pct, "%.0f%%", pct) then return end
    end
    bar.pct:SetText("")
end
local function AskHealth(curve) return UnitHealthPercent("player", true, curve) end
local function AskPower(curve) return UnitPowerPercent("player", nil, false, curve) end
local function ResHealth()
    local bar = res.health
    if bar and bar:IsShown() then
        local now, most = UnitHealth("player"), UnitHealthMax("player")
        Feed(bar, now, most)
        Say(bar, now, most, UnitHealthPercent and AskHealth)
    end
end
local function ResPower()
    local bar = res.power
    if bar and bar:IsShown() then
        local now, most = UnitPower("player"), UnitPowerMax("player")
        Feed(bar, now, most)
        Say(bar, now, most, UnitPowerPercent and AskPower)
    end
end
-- Light and shade on the fill, as Blizzard's own resource bar has: dark at the left end running out to
-- the full colour at the right, and over that a little light at the top and dark at the bottom. Flat,
-- the fill is one block of colour and reads as a different kind of bar beside Blizzard's. Two sheets
-- over the fill's own texture, so they follow it as it shrinks and grows and nothing is worked out here.
local shades = setmetatable({}, { __mode = "k" })       -- [a bar] = { along, across }
local function Shade(bar)
    local fill = bar:GetStatusBarTexture()
    local shade = shades[bar]
    if type(fill) ~= "table" or not fill.GetObjectType then
        if shade then shade[1]:Hide() shade[2]:Hide() end
        return
    end
    if not shade then
        shade = { bar:CreateTexture(nil, "ARTWORK", nil, 6), bar:CreateTexture(nil, "ARTWORK", nil, 7) }
        for _, t in ipairs(shade) do t:SetColorTexture(1, 1, 1, 1) end
        if CreateColor then
            shade[1]:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.50), CreateColor(0, 0, 0, 0))
            shade[2]:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.22), CreateColor(1, 1, 1, 0.05))
        else
            shade[1]:SetAlpha(0)
            shade[2]:SetAlpha(0)
        end
        shades[bar] = shade
    end
    for _, t in ipairs(shade) do
        t:ClearAllPoints()
        t:SetAllPoints(fill)
        t:Show()
    end
end
-- The game's colours for health, energy and the rest are full and bright; the swing bars' are not. So
-- they can be taken down to sit beside those (resTone = "muted"): a fifth darker.
local function Toned(r, g, b)
    local db = YippRouteDB.swing
    if type(db) == "table" and db.resTone == "bright" then return r, g, b end
    return r * 0.80, g * 0.80, b * 0.80      -- (darker only: greyed as well, it went dirty under the shade)
end
local function ResColours()
    local db = YR.SwingDB()
    local bar = res.health
    if bar then
        local c = db.healthColor or { 0.30, 0.78, 0.36, 1 }
        local class = db.healthClass == true and RAID_CLASS_COLORS and RAID_CLASS_COLORS[select(2, UnitClass("player")) or ""]
        local r, g, b = c[1], c[2], c[3]
        if db.resTone == "bright" then r, g, b = 0, 1, 0 end       -- (Blizzard's own green for health)
        if class then r, g, b = class.r, class.g, class.b end
        r, g, b = Toned(r, g, b)
        bar:SetStatusBarColor(r, g, b, 1)
    end
    bar = res.power
    if bar then
        local _, token = UnitPowerType("player")
        local c = type(PowerBarColor) == "table" and token and PowerBarColor[token] or nil
        local r, g, b = 0.25, 0.45, 0.95
        if type(c) == "table" and c.r then r, g, b = c.r, c.g, c.b end
        r, g, b = Toned(r, g, b)
        bar:SetStatusBarColor(r, g, b, 1)
    end
end

-- Combo points (combo = true): a row of squares, one a point, that fill as you build them - in the
-- bars' own look, where Blizzard draws round gems. Each square is a status bar of its own that holds
-- one point (from i - 1 to i) and is handed the whole count: under its point it stays empty, at or
-- over it it is full. So the count is never read here either, and may be one the game keeps secret.
-- Only for a class that has combo points (a rogue, a druid): for any other it is never made.
local COMBO = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
local combo                     -- the row's holder, with .parts = the squares
local function ComboMost()
    local most = UnitPowerMax("player", COMBO)
    if type(most) ~= "number" or (issecretvalue and issecretvalue(most)) then return 0 end
    return math.max(0, math.min(10, most))
end
-- A square that gains its point flashes white as it fills; the ones that are spent flash in their own
-- colour as they empty; the last point makes the whole row flash. For that the count has to be read,
-- so it is only done where the game lets it be (not a secret one), and not when the count changed
-- because the target did (quiet).
local comboHad
local pops = setmetatable({}, { __mode = "k" })     -- [a square] = the fade of its flash
local function ComboFlash(part, r, g, b)
    local pop = pops[part]
    if not pop then return end
    part.glow:SetColorTexture(r, g, b, 1)
    pop:Stop()
    pop:Play()
end
local function ComboFeed(quiet)
    if not (combo and combo:IsShown()) then return end
    -- (the count may be one the game keeps from addons: it is not asked whether it is there by testing
    -- it, only what kind of thing it is)
    local points = GetComboPoints and GetComboPoints("player", "target")
    if type(points) ~= "number" then points = UnitPower("player", COMBO) end
    -- (the points you had on something stay on its corpse: clicked on, a dead target shows none)
    local dead = UnitExists("target") and UnitIsDead("target")
    if not (issecretvalue and issecretvalue(dead)) and dead then points = 0 end
    for _, part in ipairs(combo.parts) do
        if part:IsShown() then
            if EASE then pcall(part.SetValue, part, points, EASE) else pcall(part.SetValue, part, points) end
        end
    end
    if type(points) ~= "number" or (issecretvalue and issecretvalue(points)) then comboHad = nil return end
    local had = comboHad
    comboHad = points
    if quiet or not had or had == points then return end
    local most = combo.most or #combo.parts
    if points > had then
        local first = (points >= most) and 1 or had + 1
        for i = first, math.min(points, #combo.parts) do ComboFlash(combo.parts[i], 1, 1, 1) end
    else
        for i = points + 1, math.min(had, #combo.parts) do
            local part = combo.parts[i]
            ComboFlash(part, part.r or 1, part.g or 1, part.b or 1)
        end
    end
end
local function ComboApply(on, db)
    local most = on and ResWant("combo") and ComboMost() or 0
    if most <= 0 then
        if combo then combo:Hide() end
        return
    end
    if not combo then
        combo = CreateFrame("Frame", nil, UIParent)
        combo:SetFrameStrata("LOW")
        combo.key = "combo"
        combo.parts = {}
        Draggable(combo, "combo")
    end
    local look = YR.ResourceLook()
    PlaceBar(combo, db, "combo")
    local w, h = BarSize(db, "combo")
    -- three pixels apart: the frames of two neighbours then meet in one line, so the row reads as one
    -- bar of the swing bars' kind, divided into its points
    local gap = (look.outline and (look.rim ~= false or look.lineColor ~= nil)) and 3 or 1
    local each = (w - (most - 1) * gap) / most
    -- their colour (comboColor): the swing timer's main-hand colour, so they sit with those bars, or your class's
    local c = db.mainColor
    local cr, cg, cb = 0.72, 0.24, 0.24
    if type(c) == "table" and c[1] then cr, cg, cb = c[1], c[2], c[3] end
    if db.comboColor == "class" then cr, cg, cb = ClassColour() end
    for i = 1, most do
        local part = combo.parts[i]
        if not part then
            part = CreateFrame("StatusBar", nil, combo)
            part.bg = part:CreateTexture(nil, "BACKGROUND")
            part.bg:SetAllPoints()
            part.lines = Outline(part, part)
            part.rim = Outline(part, part, 2, RIM, true)
            -- the flash: a sheet over the square, unseen but for the third of a second it fades in
            part.glow = part:CreateTexture(nil, "OVERLAY")
            part.glow:SetAllPoints()
            part.glow:SetColorTexture(1, 1, 1, 1)
            part.glow:SetAlpha(0)
            local pop = part.glow.CreateAnimationGroup and part.glow:CreateAnimationGroup()
            if type(pop) == "table" and pop.CreateAnimation then
                local fade = pop:CreateAnimation("Alpha")
                fade:SetFromAlpha(0.85)
                fade:SetToAlpha(0)
                fade:SetDuration(0.35)
                fade:SetSmoothing("OUT")
                pops[part] = pop
            end
            combo.parts[i] = part
        end
        part:ClearAllPoints()
        part:SetPoint("TOPLEFT", combo, "TOPLEFT", (i - 1) * (each + gap), 0)
        part:SetSize(each, h)
        part:SetStatusBarTexture(TEXTURES[look.texture] or TEXTURES.smooth)
        local r, g, b = cr, cg, cb
        part.r, part.g, part.b = r, g, b
        part:SetStatusBarColor(r, g, b, 1)
        part.bg:SetColorTexture(0, 0, 0, look.bgAlpha or 0.5)
        ShowLines(part.lines, look.outline)
        Inner(part.lines, look)
        ShowLines(part.rim, look.outline and (look.rim ~= false or look.lineColor ~= nil))
        Tone(part.rim, look.lineColor and LINE_LIGHT or look.rimColor)
        part:SetMinMaxValues(i - 1, i)
        Shade(part)
        part:Show()
    end
    for i = most + 1, #combo.parts do combo.parts[i]:Hide() end
    combo.most = most
    local unlocked = db.resLock == false
    combo:EnableMouse(unlocked)
    combo.edge:SetShown(unlocked)
    combo:SetShown(unlocked or db.resShow ~= "combat" or resCombat)
    ComboFeed(true)
end

-- Blizzard's own resource bar (the personal resource display, with its combo points): see-through
-- while a health or power bar of ours shows, as ours are there in its stead; as it was otherwise, and
-- while Edit Mode is open, so it can still be found and set there. Only its alpha is touched: the
-- game never sets that itself, and shows and hides the frame as before. resHideBlizz = false: left be.
local prdWas, prdHooked
local function TheirResource()
    local prd = _G.PersonalResourceDisplayFrame
    if type(prd) ~= "table" or not prd.SetAlpha then return end
    local db = YippRouteDB.swing
    local hide = YR.ResourceBarsOn() and type(db) == "table" and db.resHideBlizz ~= false
        and (ResWant("health") or ResWant("power")) and not prd.isInEditMode
    if hide then
        if prdWas == nil then prdWas = prd:GetAlpha() end
        if not prdHooked and type(prd.SetIsInEditMode) == "function" then
            prdHooked = true
            hooksecurefunc(prd, "SetIsInEditMode", function() YR.ResourceBarsHideTheirs() end)
        end
        prd:SetAlpha(0)
    elseif prdWas ~= nil then
        prd:SetAlpha(prdWas)
        prdWas = nil
    end
end
YR.ResourceBarsHideTheirs = TheirResource

--- The two bars as they are set now: made, placed, dressed, shown or not, and filled.
function YR.ResourceBarsApply()
    local on = YR.ResourceBarsOn()
    local db = on and YR.SwingDB() or nil
    for _, key in ipairs(RESOURCES) do
        local bar = res[key]
        local want = on and ResWant(key)
        if want and not bar then
            bar = NewBar(UIParent, key)
            bar:SetFrameStrata("LOW")
            bar.name = bar:CreateFontString(nil, "OVERLAY")
            bar.name:SetPoint("LEFT", 6, 0)
            bar.name:SetFont(Face(YR.ResourceLook()), db.font or 12, "OUTLINE")       -- (a font before any words: the game refuses text without one)
            bar.name:SetText(key == "health" and "Health" or "Power")
            bar.pct = bar:CreateFontString(nil, "OVERLAY")
            bar.pct:SetPoint("LEFT", 6, 0)
            bar.pct:SetFont(Face(YR.ResourceLook()), db.font or 12, "OUTLINE")
            bar.amount = bar:CreateFontString(nil, "OVERLAY")
            bar.amount:SetPoint("RIGHT", -6, 0)
            bar.amount:SetFont(Face(YR.ResourceLook()), db.font or 12, "OUTLINE")
            res[key] = bar
        end
        if bar then
            if want then
                PlaceBar(bar, db, key)
                local look = YR.ResourceLook()
                StyleBar(bar, look)
                bar.name:SetFont(Face(look), look.font or 12, "OUTLINE")
                bar.amount:SetFont(Face(look), look.font or 12, "OUTLINE")
                bar.pct:SetFont(Face(look), look.font or 12, "OUTLINE")
                -- what it says (resText): the percent, the number, both or neither. Its name only while it
                -- is being placed, where the percent otherwise is ("name": a setting from before, the percent now)
                local unlocked = db.resLock == false
                local says = db.resText or "all"
                bar.name:SetShown(unlocked)
                bar.pct:SetShown(not unlocked and (says == "all" or says == "pct" or says == "name"))
                bar.amount:SetShown(says == "all" or says == "value")
                Shade(bar)
                bar:SetShown(unlocked or db.resShow ~= "combat" or resCombat)
            else
                bar:Hide()
            end
        end
    end
    ComboApply(on, db)
    TheirResource()
    if on then
        ResColours()
        ResHealth()
        ResPower()
    end
end

local function OnResEvent(_, event, unit)
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        ResHealth()
    elseif event == "UNIT_POWER_FREQUENT" then
        ResPower()
        ComboFeed()
    elseif event == "UNIT_MAXPOWER" then
        ResPower()
        if ResWant("combo") then YR.ResourceBarsApply() end      -- (how many points there are can change: a druid's form)
    elseif event == "PLAYER_TARGET_CHANGED" then
        ComboFeed(true)
    elseif event == "ADDON_LOADED" then
        TheirResource()             -- (Blizzard's resource bar loads when it is first shown)
    elseif event == "UNIT_DISPLAYPOWER" then
        ResColours()
        ResPower()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        resCombat = event == "PLAYER_REGEN_DISABLED"
        YR.ResourceBarsApply()
    else
        resCombat = UnitAffectingCombat("player") and true or false
        YR.ResourceBarsApply()
    end
end
local RES_EVENTS = { { "UNIT_HEALTH", "player" }, { "UNIT_MAXHEALTH", "player" }, { "UNIT_POWER_FREQUENT", "player" },
    { "UNIT_MAXPOWER", "player" }, { "UNIT_DISPLAYPOWER", "player" }, "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "ADDON_LOADED" }

local EVENTS = { "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED", "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_TARGET_CHANGED" }

-- ---------------------------------------------------------------------------
-- Cast bar
-- ---------------------------------------------------------------------------
-- Your own casts and channels on a bar of ours, in the swing bars' look: the spell's name at the left,
-- the time left at the right, its icon beside the bar, a line at the front of the fill. A cast fills,
-- a channel empties. Stopped short, it says so in red for half a second. Its times are the game's
-- (UnitCastingInfo, UnitChannelInfo); should the game keep them from addons, the bar shows the name on
-- a full bar and no time, rather than a guess.
--   Blizzard's own cast bar is made see-through meanwhile (castHideBlizz ~= false). Blizzard sets that
--   bar's alpha itself at the start of every cast, through one function of the bar's: ours goes back
--   over it after each call, and as the bar is then at nought its own fade-out never starts (it only
--   fades a bar that can be seen). Nothing of Blizzard's is replaced, unregistered or moved.
--   Account options (YippRouteDB.swing): cast = true (on), castIcon, castTime (both on unless false),
--   castLock = false (being placed), castHideBlizz; its place and size as the other bars' (key "cast").
local cast                      -- the bar
local castState                 -- nil, "cast", "channel", or "hold" (stopped short, said for a moment)
local CAST_COLOUR, CHANNEL_COLOUR, STOPPED_COLOUR = { 0.80, 0.62, 0.24 }, { 0.30, 0.62, 0.36 }, { 0.70, 0.22, 0.22 }
local function CastWanted()
    local db = YippRouteDB.swing
    return YR.QoLOn() and type(db) == "table" and db.cast == true
end
YR.CastBarOn = CastWanted

local theirCastHooked, theirCastHidden
local function TheirCast()
    local f = _G.PlayerCastingBarFrame
    if type(f) ~= "table" or not f.SetAlpha then return end
    local hide = CastWanted() and YippRouteDB.swing.castHideBlizz ~= false and not f.isInEditMode
    if hide then
        if not theirCastHooked and type(f.ApplyAlpha) == "function" then
            theirCastHooked = true
            hooksecurefunc(f, "ApplyAlpha", function() YR.CastBarHideTheirs() end)
        end
        theirCastHidden = true
        if f:GetAlpha() ~= 0 then f:SetAlpha(0) end
    elseif theirCastHidden then
        theirCastHidden = nil
        f:SetAlpha(1)
    end
end
YR.CastBarHideTheirs = TheirCast

local function CastStop()
    castState = nil
    if cast then cast:Hide() end
end
-- The cast (or channel) under way put on the bar. false when there is none.
local function CastBegin(channel)
    local name, _, texture, startMS, endMS
    if channel then
        name, _, texture, startMS, endMS = UnitChannelInfo("player")
    else
        name, _, texture, startMS, endMS = UnitCastingInfo("player")
    end
    if not name then return false end
    local bar = cast
    castState = channel and "channel" or "cast"
    local c = channel and CHANNEL_COLOUR or CAST_COLOUR
    bar:SetStatusBarColor(c[1], c[2], c[3], 1)
    if not pcall(bar.name.SetText, bar.name, name) then bar.name:SetText("") end
    pcall(bar.icon.SetTexture, bar.icon, texture)
    bar.tenth = nil
    if Plain(startMS) and Plain(endMS) and endMS > startMS then
        bar.from, bar.to = startMS / 1000, endMS / 1000
        bar:SetMinMaxValues(0, bar.to - bar.from)
    else
        bar.from, bar.to = nil, nil
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar.time:SetText("")
    end
    bar:Show()
    return true
end
-- Stopped short: said on the bar in red, and the bar gone half a second later.
local function CastHold(words)
    if not cast or not castState or castState == "hold" then return end
    castState = "hold"
    cast.gone = GetTime() + 0.5
    cast:SetStatusBarColor(STOPPED_COLOUR[1], STOPPED_COLOUR[2], STOPPED_COLOUR[3], 1)
    cast:SetMinMaxValues(0, 1)
    cast:SetValue(1)
    cast.name:SetText(words)
    cast.time:SetText("")
end
local function CastTick(bar)
    local now = GetTime()
    if castState == "hold" then
        if now >= (bar.gone or 0) then
            CastStop()
            YR.CastBarApply()           -- (being placed: its sample back)
        end
        return
    end
    if not castState or not bar.from then return end
    local left = bar.to - now
    if left < -0.5 then CastStop() return end       -- (its end never told: not left up)
    if left < 0 then left = 0 end
    bar:SetValue(castState == "channel" and left or (now - bar.from))
    local tenth = math.floor(left * 10 + 0.5)
    if tenth ~= bar.tenth then
        bar.tenth = tenth
        bar.time:SetText(("%.1f"):format(tenth / 10))
    end
end

--- The cast bar as it is set now: made, placed, dressed, and showing what is being cast.
function YR.CastBarApply()
    TheirCast()
    if not CastWanted() then
        castState = nil
        if cast then cast:Hide() end
        return
    end
    local db = YR.SwingDB()
    if not cast then
        cast = NewBar(UIParent, "cast")
        cast:SetFrameStrata("MEDIUM")
        cast.name = cast:CreateFontString(nil, "OVERLAY")
        cast.name:SetPoint("LEFT", 6, 0)
        cast.name:SetFont(Face(), db.font or 12, "OUTLINE")
        cast.time = cast:CreateFontString(nil, "OVERLAY")
        cast.time:SetPoint("RIGHT", -6, 0)
        cast.time:SetFont(Face(), db.font or 12, "OUTLINE")
        cast.icon = cast:CreateTexture(nil, "ARTWORK")
        cast.icon:SetPoint("RIGHT", cast, "LEFT", -4, 0)
        cast.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        cast.spark = cast:CreateTexture(nil, "OVERLAY")
        cast.spark:SetWidth(2)
        cast.spark:SetColorTexture(1, 1, 1, 0.80)
        cast:SetScript("OnUpdate", CastTick)
    end
    PlaceBar(cast, db, "cast")
    StyleBar(cast, db)
    cast.name:SetFont(Face(), db.font or 12, "OUTLINE")
    cast.time:SetFont(Face(), db.font or 12, "OUTLINE")
    local _, h = BarSize(db, "cast")
    cast.icon:SetSize(h, h)
    cast.icon:SetShown(db.castIcon ~= false)
    cast.time:SetShown(db.castTime ~= false)
    local fill = cast:GetStatusBarTexture()
    cast.spark:ClearAllPoints()
    if type(fill) == "table" and fill.GetObjectType then
        cast.spark:SetPoint("TOP", fill, "TOPRIGHT")
        cast.spark:SetPoint("BOTTOM", fill, "BOTTOMRIGHT")
        cast.spark:SetShown(db.spark and true or false)
    else
        cast.spark:Hide()
    end
    if castState == "hold" then return end
    if CastBegin(false) or CastBegin(true) then return end
    castState = nil
    if db.castLock == false then
        -- being placed: a sample, so there is something to see and drag
        cast:SetStatusBarColor(CAST_COLOUR[1], CAST_COLOUR[2], CAST_COLOUR[3], 1)
        cast:SetMinMaxValues(0, 1)
        cast:SetValue(0.6)
        cast.name:SetText("Cast bar")
        cast.time:SetText("1.2")
        cast.icon:SetTexture(136243)
        cast:Show()
    else
        cast:Hide()
    end
end

local function OnCastEvent(_, event)
    if not cast then return end
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
        CastBegin(false)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        CastBegin(true)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        CastHold("Interrupted")
    elseif event == "UNIT_SPELLCAST_FAILED" then
        -- (this also comes for a key pressed during a cast: only when nothing is being cast any more)
        if not UnitCastingInfo("player") and not UnitChannelInfo("player") then CastHold("Failed") end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if castState ~= "hold" and not UnitCastingInfo("player") and not UnitChannelInfo("player") then
            CastStop()
            YR.CastBarApply()
        end
    else
        YR.CastBarApply()
    end
end
local CAST_EVENTS = { { "UNIT_SPELLCAST_START", "player" }, { "UNIT_SPELLCAST_DELAYED", "player" }, { "UNIT_SPELLCAST_STOP", "player" },
    { "UNIT_SPELLCAST_FAILED", "player" }, { "UNIT_SPELLCAST_INTERRUPTED", "player" }, { "UNIT_SPELLCAST_CHANNEL_START", "player" },
    { "UNIT_SPELLCAST_CHANNEL_UPDATE", "player" }, { "UNIT_SPELLCAST_CHANNEL_STOP", "player" }, "PLAYER_ENTERING_WORLD" }

function YR.StartSwing()
    if part then return end
    part = YR.Part(YR.SwingOn, EVENTS, OnEvent, { start = Begin, stop = End, again = Apply })
    YR.Part(YR.ResourceBarsOn, RES_EVENTS, OnResEvent, {
        start = function()
            resCombat = UnitAffectingCombat("player") and true or false
            YR.ResourceBarsApply()
        end,
        stop = function() YR.ResourceBarsApply() end,
        again = function() YR.ResourceBarsApply() end,
    })
    YR.Part(CastWanted, CAST_EVENTS, OnCastEvent, {
        start = function() YR.CastBarApply() end,
        stop = function() YR.CastBarApply() end,
        again = function() YR.CastBarApply() end,
    })
end

--- A bar of Headstart's own by its key (main, off, ranged, health, power, combo), while it is in use:
--- nil for one that is turned off or was never made. For Arrange.lua, which moves them.
function YR.OwnBarFrame(key)
    if key == "cast" then return CastWanted() and cast or nil end
    if key == "range" then return YR.SwingOn() and YR.SwingDB().rangeBar == true and rangeBar or nil end
    if key == "combo" then return ResWant("combo") and YR.ResourceBarsOn() and combo or nil end
    if key == "health" or key == "power" then return ResWant(key) and YR.ResourceBarsOn() and res[key] or nil end
    if not Own() then return nil end
    local db = YR.SwingDB()
    if db.use and db.use[key] == false then return nil end
    -- (a hand you have nothing in has no bar to place: no off-hand weapon, or no ranged swing to time)
    if key == "off" and Speed(OFF) == nil then return nil end
    if key == "ranged" and not hunter then return nil end
    for _, hand in ipairs(HANDS) do
        if hand.key == key then return bars[hand.type] end
    end
    return nil
end
