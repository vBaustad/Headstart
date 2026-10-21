-- Glimmer: herbs, ore, chests, quest objects and your fishing bobber light up as you walk up to them,
-- in a look of Headstart's own.
--   Where: the game's own soft target for objects - "softinteract", the one object your interact key
--   would use, the game's choice, within some fifteen yards - says which object; its nameplate, which
--   is switched on only while such an object is targeted, is where that object is on the screen, and
--   the effect hangs under it. One object at a time, as the game picks it.
--   What it is: herbs and ore by name (with the skill Classic asks for them, coloured by your chance
--   of a skill-up; only with Herbalism or Mining - see Gathers), chests by name, the bobber by its ID, quest objects by the game's own link to your
--   quests. A node you can't gather yet shows the game's "unable" cursor: that is read too, so a skill
--   Forever asks differently is still told right as "too low". On a client in another language the
--   names aren't known, and the cursor alone tells herb from ore.
--   Quest objects in the quest givers' look (below): sparkles falling from the object's plate down over it, with the
--   quest's own line at the plate ("Gnoll Paw: 3/8"), as it counts (2026-10-21: "I mainly mean quest NPCs and quest
--   items, not nodes"). They had a look of their own for an evening - Corners, a frame half as large again as the
--   rest, hung a fixed way under the plate: on a sprout in the game the frame stood far over it, the sprout in its
--   bottom corner ("WHAT IS THIS" - "it should be the same as quest givers"). A column from the plate down meets the
--   object at any distance; a frame round it can't, with no API saying where it is on the screen.
--   Quest givers (glimmerGivers): an NPC with a quest for you - to take or to hand in, as Quests on NPC tooltips
--   knows it (QuestTipLines: the route, QuestieDB, what it offered before) - when it is the one the interact key
--   would use: sparkles over it, the game's own quest glimmer made large, falling from its plate (over its head) down
--   over it, and the quest's name in yellow over its own (glimmerGiverText). The NPC looks as it does without a plate:
--   the plate Glimmer turns on for it (the only way to know where it is on the screen) is out of sight, and its name is
--   drawn as the game draws an NPC's - small, green (yellow neutral). Left as it was, the game drew that plate one way
--   or another - empty, a full friendly plate with a green health bar and the level, the name large and white once
--   targeted (seen 2026-10-21: "completely normal, with glimmer and marker over and quest text in yellow"). (A glow behind the plate, a bar of light over the NPC, was there for an hour on 2026-10-21:
--   "the same style as Blizzard's glimmer, just blown up" - the owner. A glow by the ground, on 2026-10-14, floated off.)
--   The line under a quest object: glimmerQuestText. Both on unless turned off.
--   With a RestedXP guide leading (YR.RouteStepNpc, Waypoint.lua), only the NPC its step is at lights - the one the
--   world marker shows the way to; without one, every NPC with a quest for you. Smaller and lower than first made:
--   "a bit big, and a bit high" (2026-10-21), and again once seen in the game the same evening: "still too big and a
--   bit high" - the sparkles a little over half as large, the column shorter and lower, on the NPC's body. Both kinds a
--   little orange, not the yellow of the first ("a bit of orange and not yellow"); the lines quest yellow.
--   It fades in, and out where it was as it is let go - never in a frame, either way (2026-10-22).
--   Quest loot: the game draws a sparkle on lootable quest items only while its outline effect is off.
--   That is two graphics settings (glimmerLoot), put back when it goes off - but the sparkle stays
--   until the game is restarted, and it says so.
--   Rests in a fight (an open object plate there names every lootable corpse) and in instances, unless
--   you want it there. Every game setting it changes is written down first and put back when Glimmer
--   goes off; changes a fight holds back are made when it ends.
--   Free while off (YR.Part): nothing listened for, no setting touched, no frame made.
--   Account options (YippRouteDB): glimmer (off until turned on), glimmerHerbs, glimmerOre,
--   glimmerChests, glimmerQuest, glimmerFishing, glimmerGivers (on), glimmerLoot (off), glimmerStyle ("glint"),
--   glimmerColor ("skill"), glimmerInstances (off).
--   The game settings as they were: YippRouteDB.glimmerWas.
local ADDON, YR = ...

local ART = "Interface\\AddOns\\Headstart\\art\\glimmer\\"
local UNIT = "softinteract"
local BOBBER = 35591                -- the fishing bobber's object ID
local HERBALISM, MINING = 182, 186

-- Classic's skill for each node. Forever's is not known to differ; where it does, the game's "unable"
-- cursor still says a node is too low for you (read in Look).
local HERBS = {
    ["Peacebloom"] = 1, ["Silverleaf"] = 1, ["Earthroot"] = 15, ["Mageroyal"] = 50, ["Briarthorn"] = 70,
    ["Stranglekelp"] = 85, ["Bruiseweed"] = 100, ["Wild Steelbloom"] = 115, ["Grave Moss"] = 120, ["Kingsblood"] = 125,
    ["Liferoot"] = 150, ["Fadeleaf"] = 160, ["Goldthorn"] = 170, ["Khadgar's Whisker"] = 185, ["Wintersbite"] = 195,
    ["Firebloom"] = 205, ["Purple Lotus"] = 210, ["Arthas' Tears"] = 220, ["Sungrass"] = 230, ["Blindweed"] = 235,
    ["Ghost Mushroom"] = 245, ["Gromsblood"] = 250, ["Golden Sansam"] = 260, ["Dreamfoil"] = 270,
    ["Mountain Silversage"] = 280, ["Plaguebloom"] = 285, ["Icecap"] = 290, ["Black Lotus"] = 300,
}
local ORE = {
    ["Copper Vein"] = 1, ["Tin Vein"] = 65, ["Incendicite Mineral Vein"] = 65, ["Silver Vein"] = 75,
    ["Ooze Covered Silver Vein"] = 75, ["Lesser Bloodstone Deposit"] = 75, ["Iron Deposit"] = 125,
    ["Indurium Mineral Vein"] = 150, ["Gold Vein"] = 155, ["Ooze Covered Gold Vein"] = 155, ["Mithril Deposit"] = 175,
    ["Ooze Covered Mithril Deposit"] = 175, ["Truesilver Deposit"] = 230, ["Ooze Covered Truesilver Deposit"] = 230,
    ["Dark Iron Deposit"] = 230, ["Small Thorium Vein"] = 245, ["Ooze Covered Thorium Vein"] = 245,
    ["Rich Thorium Vein"] = 275, ["Ooze Covered Rich Thorium Vein"] = 275,
}
local CHEST_WORDS = { "Chest", "Footlocker", "Coffer", "Strongbox", "Lockbox" }
YR.GLIMMER_HERBS, YR.GLIMMER_ORE = HERBS, ORE           -- (for the tests)

-- What each kind is switched by.
local KEY = { herb = "glimmerHerbs", ore = "glimmerOre", chest = "glimmerChests", quest = "glimmerQuest", bobber = "glimmerFishing",
    giver = "glimmerGivers" }
-- Drawn larger than the rest, by kind (on top of the size set).
local BIG = { quest = 1, giver = 1 }

-- The game settings: the soft target for objects (always while on), its nameplate (only while an object
-- of ours is targeted), and the quest loot sparkle (glimmerLoot).
local SOFT = { SoftTargetInteract = "3", SoftTargetInteractRange = "60", SoftTargetInteractArc = "2",
    SoftTargetInteractOnlyInRange = "0" }
local PLATE = "SoftTargetNameplateInteract"
-- Where the ground is under the object's plate, at gathering distance: every look is drawn from there
-- up (it was the plant's middle, and the looks sat high - the owner, 2026-10-14: "keep it down, toward
-- the ground"). By kind: the plate stands over the object's top, so how far down its foot is goes by
-- how tall such objects are - at a herb's 100 a quest object's beam stood far under it (seen the same
-- day). No API says where an object is on the screen; these are measured by eye.
local GROUND = { herb = -100, ore = -100, chest = -80, quest = 2, bobber = -50, giver = 2 }     -- (quests': on the plate)
local LOOT = { outlineModeShowLootEffectWhenDisabled = "1", graphicsOutlineMode = "0", OutlineEngineMode = "0",
    raidGraphicsOutlineMode = "0", RAIDOutlineEngineMode = "0" }
-- a graphics preset sets the outline back: these, changed, put the loot settings on again
local LOOT_WATCH = { graphicsquality = true, raidgraphicsquality = true }
for k in pairs(LOOT) do LOOT_WATCH[k:lower()] = true end

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------
local function On() return YR.Option("glimmer") end
local function Sub(key) return YippRouteDB[key] ~= false end         -- the kinds: on unless turned off
local STYLES = { glint = true, halo = true, ring = true, beam = true, marker = true }
function YR.GlimmerStyle() local s = YippRouteDB.glimmerStyle return STYLES[s] and s or "glint" end
function YR.GlimmerColorMode()
    local m = YippRouteDB.glimmerColor
    return (m == "accent" or m == "white") and m or "skill"
end
local function Size() return 1 end
local function Bright() return 1 end

-- ---------------------------------------------------------------------------
-- Colours: your chance of a skill-up, as the game colours it; chests, quests and the bobber their own
-- ---------------------------------------------------------------------------
local COLORS = {
    orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 }, grey = { 0.55, 0.55, 0.55 },
    red = { 1, 0.15, 0.1 }, chest = { 1, 0.78, 0.3 }, quest = { 1, 0.5, 0.1 }, bobber = { 0.45, 0.8, 1 }, giver = { 1, 0.5, 0.1 },
    accent = { 1, 0.6, 0.15 }, white = { 1, 1, 1 },
}
YR.GLIMMER_COLORS = COLORS

--- The skill-up colour's name for a node needing `need` at skill `skill`: red below it, then orange,
--- yellow and green 25, 50 and 100 points above, grey from there.
function YR.GlimmerSkillColor(skill, need)
    if not (skill and need) then return nil end
    if skill < need then return "red" end
    if skill < need + 25 then return "orange" end
    if skill < need + 50 then return "yellow" end
    if skill < need + 100 then return "green" end
    return "grey"
end

-- Your herbalism and mining, read when they may have changed (SKILL_LINES_CHANGED, the login). skillsRead:
-- your professions were read in full (none of them held back), so one missing is one you don't have.
local skills, skillsRead = {}, false
local function ReadSkills()
    wipe(skills)
    skillsRead = false
    if not (GetProfessions and GetProfessionInfo) then return end
    local ok, a, b = pcall(GetProfessions)
    if not ok or (issecretvalue and (issecretvalue(a) or issecretvalue(b))) then return end
    for _, index in ipairs({ a or false, b or false }) do
        if index then
            local got, _, _, rank, _, _, _, line = pcall(GetProfessionInfo, index)
            if got and type(rank) == "number" and type(line) == "number" and not (issecretvalue and (issecretvalue(rank) or issecretvalue(line))) then
                skills[line] = rank
            else
                return                  -- (one that can't be read: which you have isn't known)
            end
        end
    end
    skillsRead = true
end
YR.GlimmerReadSkills = ReadSkills

--- Whether you gather this kind: a herb with Herbalism, ore with Mining (the owner, 2026-10-16: "I don't
--- want to see flowers if I have mining"). While your professions can't be read: yes, as before.
local function Gathers(kind)
    if kind ~= "herb" and kind ~= "ore" then return true end
    if not skillsRead then return true end
    return skills[kind == "herb" and HERBALISM or MINING] ~= nil
end

-- ---------------------------------------------------------------------------
-- The effect: five looks of our own, drawn from Headstart's art, animated while shown
-- ---------------------------------------------------------------------------
local function Tex(fx, file, white)
    local t = fx:CreateTexture(nil, "ARTWORK")
    t.white = white             -- (white over the colour: never tinted)
    t:SetTexture(ART .. file)
    t:SetBlendMode("ADD")
    if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) t:SetTexelSnappingBias(0) end
    t:Hide()
    return t
end

-- Each look: what it is made of, and how a moment of it is drawn (t: seconds; s: size in pixels; a:
-- how bright, 0..1, before the colour). The frame's centre is the ground at the object's foot.
local LOOKS = {}
LOOKS.glint = {
    build = function(fx)
        local p = { haze = Tex(fx, "halo") }
        for i = 1, 6 do p[i] = Tex(fx, "glint") end
        return p
    end,
    draw = function(p, t, s, a)
        p.haze:SetSize(s * 1.3, s * 0.55)
        p.haze:SetPoint("CENTER", 0, s * 0.1)
        p.haze:SetAlpha(a * 0.22)
        for i = 1, 6 do
            local phase = i * 1.7
            local tw = math.max(0, math.sin(t * 2.2 + phase)) ^ 2
            local ang = phase + t * 0.25
            local r = s * (0.22 + 0.1 * ((i % 3) + 1))
            local g = p[i]
            g:SetSize(s * (0.18 + 0.32 * tw), s * (0.18 + 0.32 * tw))
            g:SetPoint("CENTER", math.cos(ang) * r, math.sin(ang) * r * 0.35 + s * (0.16 + 0.06 * (i % 2)))
            g:SetRotation(t * 0.6 + i)
            g:SetAlpha(a * tw)
        end
    end,
}
LOOKS.halo = {
    build = function(fx) return { glow = Tex(fx, "halo"), core = Tex(fx, "halo") } end,
    draw = function(p, t, s, a)
        local pulse = math.sin(t * 2.4)
        p.glow:SetSize(s * (1.4 + 0.1 * pulse), s * (1.1 + 0.08 * pulse))
        p.glow:SetPoint("CENTER", 0, s * 0.22)
        p.glow:SetAlpha(a * (0.5 + 0.2 * pulse))
        p.core:SetSize(s * 0.4, s * 0.34)
        p.core:SetPoint("CENTER", 0, s * 0.16)
        p.core:SetAlpha(a * 0.75)
    end,
}
LOOKS.ring = {
    build = function(fx) return { Tex(fx, "ring"), Tex(fx, "ring"), dot = Tex(fx, "halo") } end,
    draw = function(p, t, s, a)
        for i = 1, 2 do
            local k = (t * 0.55 + (i - 1) * 0.5) % 1
            local w = s * (0.5 + 1.3 * k)
            p[i]:SetSize(w, w * 0.38)
            p[i]:SetPoint("CENTER", 0, 0)
            p[i]:SetAlpha(a * (1 - k) ^ 1.5)
        end
        p.dot:SetSize(s * 0.5, s * 0.22)
        p.dot:SetPoint("CENTER", 0, 0)
        p.dot:SetAlpha(a * 0.5)
    end,
}
LOOKS.beam = {
    build = function(fx) return { shaft = Tex(fx, "beam"), Tex(fx, "glint"), Tex(fx, "glint"), Tex(fx, "glint") } end,
    draw = function(p, t, s, a)
        p.shaft:SetSize(s * 0.55, s * 2.4)
        p.shaft:SetPoint("BOTTOM", 0, -s * 0.05)
        p.shaft:SetAlpha(a * (0.55 + 0.15 * math.sin(t * 1.8)))
        for i = 1, 3 do
            local k = (t * 0.45 + (i - 1) / 3) % 1
            p[i]:SetSize(s * 0.26, s * 0.26)
            p[i]:SetPoint("CENTER", math.sin(t + i * 2) * s * 0.08, k * s * 2)
            p[i]:SetAlpha(a * math.sin(math.pi * k))
        end
    end,
}
LOOKS.marker = {
    build = function(fx) return { mark = Tex(fx, "marker"), glow = Tex(fx, "halo") } end,
    draw = function(p, t, s, a)
        local bob = math.sin(t * 2.2) * s * 0.08
        p.mark:SetSize(s * 0.5, s * 0.5)
        p.mark:SetPoint("CENTER", 0, s * 1.0 + bob)
        p.mark:SetAlpha(a * 0.95)
        p.glow:SetSize(s * 0.9, s * 0.9)
        p.glow:SetPoint("CENTER", 0, s * 1.0 + bob)
        p.glow:SetAlpha(a * 0.3)
    end,
}
-- A quest giver's and a quest object's: sparkles, as the game's own quest glimmer twinkles but larger and more of them,
-- each coming and going somewhere else in a column that falls from the plate - over an NPC's head, over an object - down
-- over it (s: the size; top and span: where the column starts under the plate and how far it reaches, width: how wide,
-- in s). Each has a small white heart, so they read on any ground; an orange mist behind them, the column's size (wider
-- and more orange once seen in the game: "a bit wider maybe, and more orange mist - or just more orange"). (Naowh Forever's are silver, on a plate you can
-- see: ours are orange, and no friendly plate shows - the owner, 2026-10-21: "not the same as theirs".)
--   An NPC: from just under its plate, over its body. An object: from under its line, farther - a small one lies well
--   under its plate when near, and closer to it far off.
local SPARKS = 16
local function Hash(i, n) local v = math.sin(i * 12.9898 + n * 78.233) * 43758.5453 return v - math.floor(v) end
local function Sparkles(top, span, width)
  return {
    build = function(fx)
        local p = { haze = Tex(fx, "halo") }
        for i = 1, SPARKS do
            p[i] = Tex(fx, "glint")
            p[i + SPARKS] = Tex(fx, "glint", true)
        end
        return p
    end,
    draw = function(p, t, s, a)
        -- (a mist where it stands, so it stands out from what is behind it)
        p.haze:SetSize(s * width * 1.5, s * span * 1.1)
        p.haze:SetPoint("CENTER", 0, -s * (top + span * 0.5))
        p.haze:SetAlpha(a * (0.34 + 0.06 * math.sin(t * 1.7)))
        for i = 1, SPARKS do
            local cycle = 1.3 + (i % 5) * 0.22
            local life = (t + i * 0.61) / cycle
            local round = math.floor(life)
            local k = life - round                              -- (0..1: this sparkle's moment, then it comes elsewhere)
            local tw = math.sin(math.pi * k) ^ 1.2             -- (lit most of its moment: many at once)
            local x = (Hash(i, round) - 0.5) * s * width
            local y = -s * (top + Hash(i + 50, round) * span) - k * s * 0.06
            local size = s * (0.10 + 0.19 * tw) * (0.75 + 0.5 * Hash(i + 99, round))
            local gold, heart = p[i], p[i + SPARKS]
            gold:SetSize(size, size)
            gold:SetPoint("CENTER", x, y)
            gold:SetRotation(t * 0.7 + i)
            gold:SetAlpha(a * tw)
            heart:SetSize(size * 0.32, size * 0.32)
            heart:SetPoint("CENTER", x, y)
            heart:SetRotation(t * 0.7 + i)
            heart:SetAlpha(a * tw * 0.55)
        end
    end,
  }
end
LOOKS.sparkle = Sparkles(0.95, 0.85, 0.9)
-- (an object's column shortened once seen on a Timberling Sprout: the lower half fell on the ground under it)
LOOKS.groundSparkle = Sparkles(0.65, 1.25, 0.9)
YR.GLIMMER_LOOKS = { { "glint", "Glints" }, { "halo", "Halo" }, { "ring", "Ripple" }, { "beam", "Beam" }, { "marker", "Marker" } }
--- The look an object is drawn in: a quest object's and a quest giver's their own, the rest the one you chose.
local function StyleFor(kind)
    if kind == "quest" then return "groundSparkle" end
    if kind == "giver" then return "sparkle" end
    return YR.GlimmerStyle()
end
YR.GlimmerStyleFor = StyleFor

-- how each state is drawn: how bright, how fast
local STATES = { far = { 0.5, 0.7 }, ready = { 1, 1 }, locked = { 0.6, 0.5 } }

local function Step(fx, elapsed)
    elapsed = math.min(elapsed or 0, 0.1)
    -- (a light let go, fading out where it was: Detach's ghost)
    if fx.out then
        fx.out = fx.out - elapsed / 0.3
        if fx.out <= 0 then
            fx.out = nil
            fx:Hide()
            return
        end
        fx:SetAlpha(fx.out)
    end
    local st = STATES[fx.state] or STATES.ready
    fx.t = fx.t + elapsed * st[2] * (fx.speed or 1)
    if fx.fade < 1 then
        fx.fade = math.min(1, (fx.fade or 0) + elapsed / 0.3)
        -- its line and an NPC's name come in with it, not before it
        fx.line:SetAlpha(fx.fade)
        fx.npc:SetAlpha(fx.fade)
    end
    local s = 64 * (fx.scale or 1)
    local a = st[1] * (fx.bright or 1) * fx.fade
    local look = LOOKS[fx.style]
    if look and fx.parts[fx.style] then look.draw(fx.parts[fx.style], fx.t, s, a) end
    -- coming into reach: a ring opens once
    if fx.burst then
        fx.burst = fx.burst + elapsed
        local k = fx.burst / 0.5
        if k >= 1 then
            fx.burst = nil
            fx.ring:Hide()
        else
            fx.ring:SetSize(s * (0.4 + 1.8 * k), s * (0.4 + 1.8 * k) * 0.38)
            fx.ring:SetPoint("CENTER", 0, 0)
            fx.ring:SetAlpha((fx.bright or 1) * (1 - k))
            fx.ring:Show()
        end
    end
end

local Effect = {}
function Effect:SetStyle(style)
    style = LOOKS[style] and style or "glint"
    if self.style == style then return end
    for _, p in pairs(self.parts) do for _, t in pairs(p) do t:Hide() end end
    self.style = style
    if not self.parts[style] then self.parts[style] = LOOKS[style].build(self) end
    for _, t in pairs(self.parts[style]) do
        if not t.white then t:SetVertexColor(self.r, self.g, self.b) end
        t:Show()
    end
end
function Effect:SetColor(r, g, b)
    self.r, self.g, self.b = r, g, b
    for _, p in pairs(self.parts) do for _, t in pairs(p) do if not t.white then t:SetVertexColor(r, g, b) end end end
    self.ring:SetVertexColor(r, g, b)
end
--- An NPC's name, as the game draws one over an NPC without a plate (nil: none): on the effect's middle.
function Effect:SetName(text, r, g, b)
    self.nameSaid = text and { text, r, g, b } or nil          -- (for a ghost: Detach)
    if not text then self.npc:Hide() return end
    self.npc:SetText(text)
    self.npc:SetTextColor(r or 0, g or 1, b or 0)
    self.npc:ClearAllPoints()
    self.npc:SetPoint("CENTER", self, "CENTER", 0, 0)
    self.npc:Show()
end
--- The line under it (the quest, its count): nil for none. below: how far under the effect's middle it starts.
function Effect:SetLine(text, r, g, b, below)
    self.lineSaid = text and { text, r, g, b, below } or nil   -- (for a ghost: Detach)
    if not text then self.line:Hide() return end
    self.line:SetText(text)
    self.line:SetTextColor(r or 1, g or 0.82, b or 0)
    self.line:ClearAllPoints()
    self.line:SetPoint("TOP", self, "CENTER", 0, -(below or 8))
    self.line:Show()
end
function Effect:SetState(state)
    if state == "ready" and self.state ~= "ready" and self.state ~= nil then self.burst = 0 end
    self.state = state
end
function Effect:SetLook(scale, bright) self.scale, self.bright = scale, bright end

--- A Glimmer effect on `parent`, in the settings' look: the world's, and the settings page's preview.
function YR.GlimmerEffect(parent)
    local fx = CreateFrame("Frame", nil, parent)
    fx:SetSize(64, 64)
    fx.parts, fx.t, fx.fade = {}, math.random() * 10, 0
    fx.r, fx.g, fx.b = 1, 0.6, 0.15
    fx.ring = Tex(fx, "ring")
    fx.line = fx:CreateFontString(nil, "OVERLAY")
    fx.line:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    fx.line:SetShadowOffset(1, -1)
    fx.line:Hide()
    -- (the NPC's name: the size and look of the game's own over an NPC - measured off a screenshot, 2026-10-21)
    fx.npc = fx:CreateFontString(nil, "OVERLAY")
    fx.npc:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    fx.npc:SetShadowOffset(1, -1)
    fx.npc:Hide()
    for k, v in pairs(Effect) do fx[k] = v end
    fx:SetScript("OnShow", function(self)
        self.fade = 0
        self.line:SetAlpha(0)
        self.npc:SetAlpha(0)
        self:SetScript("OnUpdate", Step)
    end)
    fx:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    -- made hidden: a frame is shown when it is made, so its OnShow never came and nothing was ever drawn
    -- (seen 2026-10-14: no effect in the world nor in the preview). Show() is what starts it now.
    fx:Hide()
    fx:SetStyle(YR.GlimmerStyle())
    fx:SetLook(Size(), Bright())
    return fx
end

-- ---------------------------------------------------------------------------
-- Game settings: written down before the first change, put back when Glimmer goes off
-- ---------------------------------------------------------------------------
local writing = false            -- our own writes, which CVAR_UPDATE reports too
local held = false               -- a write a fight held back: made when it ends
local function Get(name)
    if not C_CVar then return nil end
    local ok, v = pcall(C_CVar.GetCVar, name)
    return ok and v or nil
end
local function Set(name, value)
    if not C_CVar or Get(name) == value then return true end
    if InCombatLockdown() then held = true return false end
    local was = YippRouteDB.glimmerWas or {}
    YippRouteDB.glimmerWas = was
    if was[name] == nil then was[name] = Get(name) or false end
    writing = true
    local ok = pcall(C_CVar.SetCVar, name, value)
    writing = false
    return ok
end
local function PutBack(list)
    local was = YippRouteDB.glimmerWas
    if not (was and C_CVar) then return 0 end
    local n = 0
    for name in pairs(list) do
        local v = was[name]
        if v ~= nil then
            if v and not InCombatLockdown() then
                writing = true
                if pcall(C_CVar.SetCVar, name, v) then n = n + 1 end
                writing = false
            end
            if not InCombatLockdown() then was[name] = nil end
        end
    end
    if next(was) == nil then YippRouteDB.glimmerWas = nil end
    return n
end

-- The object's plate, and the game's own icon for an object, opened together while an object of ours
-- is targeted. With the plate's setting alone the game made no plate for a herb (seen 2026-10-14:
-- Silverleaf targeted, in reach, "0 plates on screen"); the addon that works also turns the object
-- icon on. Shut, the icon goes back to how you had it, so doors and mailboxes don't get one.
local ICON = "SoftTargetIconGameObject"
-- (as it was last set: the soft target changes as you walk past every NPC and door, and the quest log
-- says it changed many times a minute - each would read two game settings to find them already shut)
local gateOpen
local function Gate(open)
    if open == gateOpen then return end
    if not Set(PLATE, open and "1" or "0") then return end           -- (held back by a fight: not known as set)
    if open then Set(ICON, "1") elseif not InCombatLockdown() then PutBack({ [ICON] = true }) end
    gateOpen = open
end

local function LootOn() return On() and YippRouteDB.glimmerLoot == true end
local function ApplyLoot()
    if not LootOn() then return end
    for name, v in pairs(LOOT) do Set(name, v) end
end
-- The interact key (SoftTargetInteract) is the game's "Enable Interact Key": turned off by you while Glimmer is on, it
-- stays off - written down (glimmerKeyOff) and not turned on again at the next login, as it was at every one until
-- 2026-10-21 (Naowh Forever found the same and stopped). Nothing lights while it is off; the card says so, with a
-- button that turns it on (YR.GlimmerInteractKeyOn).
local KEY_CVAR = "SoftTargetInteract"
local function ApplySettings()
    held = false
    for name, v in pairs(SOFT) do
        if not (name == KEY_CVAR and YippRouteDB.glimmerKeyOff) then Set(name, v) end
    end
    ApplyLoot()
end
--- Whether the game's interact key is on (Glimmer lights nothing without it).
function YR.GlimmerInteractKey() return Get(KEY_CVAR) == "3" or Get(KEY_CVAR) == "1" or Get(KEY_CVAR) == "2" end
--- The card's button: the interact key on again, and Glimmer's to keep on from now.
function YR.GlimmerInteractKeyOn()
    YippRouteDB.glimmerKeyOff = nil
    if On() then Set(KEY_CVAR, SOFT[KEY_CVAR]) else
        writing = true
        if C_CVar then pcall(C_CVar.SetCVar, KEY_CVAR, SOFT[KEY_CVAR]) end
        writing = false
    end
end

-- ---------------------------------------------------------------------------
-- The object targeted: what it is, and the effect on it
-- ---------------------------------------------------------------------------
local fx, plate, want, ticker
local probe                     -- a texture the game draws the object's cursor into (Kind, Locked)

local function Plain(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) and v or nil end

-- The cursor the game would show over the object: herb, ore, and whether it is "unable" (too low).
local cursorIds                 -- [file ID] = the cursor's name (made the first time one is asked for)
local function Cursor()
    if not SetUnitCursorTexture then return nil end
    probe = probe or (fx or UIParent):CreateTexture(nil, "BACKGROUND")
    probe:Hide()
    local ok, has = pcall(SetUnitCursorTexture, probe, UNIT)
    if not ok or not Plain(has) then return nil end
    local what = Plain(probe.GetAtlas and probe:GetAtlas()) or Plain(probe:GetTexture())
    if type(what) == "number" and GetFileIDFromPath then
        -- (the four cursors' file IDs asked of the game once: this runs several times a second over a node)
        if not cursorIds then
            cursorIds = {}
            for _, path in ipairs({ "UnableGatherHerbs", "UnableMine", "GatherHerbs", "Mine" }) do
                local okId, id = pcall(GetFileIDFromPath, "Interface\\Cursor\\" .. path)
                if okId and type(id) == "number" then cursorIds[id] = path end
            end
        end
        what = cursorIds[what] or what
    end
    if type(what) ~= "string" then return nil, nil, what end
    what = what:lower()
    local kind = what:find("herb") and "herb" or (what:find("mine") or what:find("mining")) and "ore"
        or what:find("quest") and "quest" or nil
    return kind, what:find("unable") ~= nil, what
end

-- The words of your quests' open objectives ("Gnarlpine Totem destroyed: 0/1"), read again when the
-- quest log has changed and an object is looked at.
local objectives, objectivesStale = {}, true
local objectivesAsWritten = {}          -- (the same, as the quest log writes them: the line under a quest object)
local function ReadObjectives()
    objectivesStale = false
    wipe(objectives)
    wipe(objectivesAsWritten)
    local Q = C_QuestLog
    if not (Q and Q.GetNumQuestLogEntries and Q.GetInfo and Q.GetQuestObjectives) then return end
    local okN, n = pcall(Q.GetNumQuestLogEntries)
    for i = 1, (okN and type(Plain(n)) == "number" and n or 0) do
        local ok, info = pcall(Q.GetInfo, i)
        info = ok and Plain(info) or nil
        if type(info) == "table" and not info.isHeader and Plain(info.questID) then
            local okO, list = pcall(Q.GetQuestObjectives, info.questID)
            for _, o in ipairs(okO and type(Plain(list)) == "table" and list or {}) do
                local text = Plain(o.text)
                if type(text) == "string" and text ~= "" and not Plain(o.finished) then
                    objectives[#objectives + 1] = text:lower()
                    objectivesAsWritten[#objectives] = text
                end
            end
        end
    end
end
local function InObjectives(name)
    if type(name) ~= "string" or #name < 3 then return false end
    if objectivesStale then ReadObjectives() end
    name = name:lower()
    for i, text in ipairs(objectives) do
        if text:find(name, 1, true) then return true, objectivesAsWritten[i] end
    end
    return false
end

-- One of your quests needs it: the game's link to your quests, else a quest objective line in its
-- tooltip, else its name in the words of an open objective. (The first two said nothing of a Gnarlpine
-- Totem the game itself put its quest sparkle on - seen 2026-10-14 with /headstart glimmer.)
local QUEST_LINE = 8                -- Enum.TooltipDataLineType.QuestObjective
local function QuestObject(unit, name)
    if C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest then
        local ok, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
        if ok and Plain(related) then return true, "quest link" end
    end
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
        data = ok and Plain(data) or nil
        for _, line in ipairs(type(data) == "table" and Plain(data.lines) or {}) do
            local kind = Plain(line.type)
            if kind == ((Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective) or QUEST_LINE) then
                return true, "tooltip", Plain(line.leftText)
            end
        end
    end
    local found, text = InObjectives(Plain(name))
    if found then return true, "its name in an objective", text end
    return false
end

--- A quest object's line: the quest's own words for it, with the count ("Gnoll Paw: 3/8"). (A quest object the game
--- links to your quests and the tooltip says nothing of: none.)
local function QuestLine(unit, name)
    local text
    if C_TooltipInfo and C_TooltipInfo.GetUnit then
        local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
        data = ok and Plain(data) or nil
        for _, line in ipairs(type(data) == "table" and Plain(data.lines) or {}) do
            if Plain(line.type) == ((Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective) or QUEST_LINE) then
                text = Plain(line.leftText)
                if text then break end
            end
        end
    end
    if not text then
        local _, written = InObjectives(Plain(name))
        text = written
    end
    if type(text) == "string" and text ~= "" then return (text:gsub("^%s*%-%s*", "")) end
    return nil
end

-- (an NPC's ID is the sixth part of its GUID: Creature-0-1-2-3-<id>-<spawn>)
local function NpcOf(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)")
    return kind == "Creature" and tonumber(id) or nil
end

--- The soft target as a quest giver: an NPC with a quest for you, to take or to hand in. Its GUID, name and the quest
--- lines (Quests on NPC tooltips: { icon, words, r, g, b, route }), else nil.
local function Giver()
    if not Sub(KEY.giver) then return nil end
    local okE, exists = pcall(UnitExists, UNIT)
    if not (okE and Plain(exists)) then return nil end
    local okP, isPlayer = pcall(UnitIsPlayer, UNIT)
    if okP and Plain(isPlayer) then return nil end
    local okU, guid = pcall(UnitGUID, UNIT)
    local okN, name = pcall(UnitName, UNIT)
    guid, name = okU and Plain(guid) or nil, okN and Plain(name) or nil
    local npc = NpcOf(guid)
    if not npc then return nil end
    -- a guide leading: its step's NPC alone (lit whatever the tips know of it); else any NPC with a quest for you
    local step = YR.RouteStepNpc and YR.RouteStepNpc(UNIT)
    if step == false then return nil end
    local ok, lines = false, nil
    if YR.QuestTipLines then ok, lines = pcall(YR.QuestTipLines, npc, name) end
    lines = ok and type(lines) == "table" and lines or {}
    if step ~= true and #lines == 0 then return nil end
    return guid, name, lines, step == true
end

--- A quest giver's line: its first quest's name, and how many more (no icon: the game has its own ! and ?).
local function GiverLine(lines)
    local first = lines[1]
    if not first then return nil end
    local text = first[2] or "?"
    if #lines > 1 then text = text .. ("  |cffcccccc+%d|r"):format(#lines - 1) end
    return text             -- (in the game's quest yellow: Effect:SetLine's own colour)
end

local function ObjectID(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return kind == "GameObject" and tonumber(id) or nil
end

--- What the targeted object is: kind ("herb", "ore", "chest", "quest", "bobber"), the skill it needs
--- (herbs and ore), its name. Nil for anything else, and for what the game keeps from addons.
function YR.GlimmerKind(name, guid, unit)
    name = Plain(name)
    if ObjectID(Plain(guid)) == BOBBER or name == "Fishing Bobber" then return "bobber", nil, name end
    if name then
        if HERBS[name] then return "herb", HERBS[name], name end
        if ORE[name] then return "ore", ORE[name], name end
        for _, w in ipairs(CHEST_WORDS) do
            if name:find(w, 1, true) then return "chest", nil, name end
        end
    end
    if unit and QuestObject(unit, name) then return "quest", nil, name end
    if unit then
        local kind = Cursor()
        if kind then return kind, nil, name end
        -- (a name the tables don't have, on a client in another language: a vein or deposit is ore)
        if name and (name:find("Vein", 1, true) or name:find("Deposit", 1, true)) then return "ore", nil, name end
    end
    return nil
end

-- The effect's size for a kind: the size set, and BIG's.
local function SizeFor(kind) return Size() * (BIG[kind] or 1) end

local function Color(w, locked)
    local mode = YR.GlimmerColorMode()
    if mode == "white" then return COLORS.white end
    if mode == "accent" then return locked and COLORS.grey or COLORS.accent end
    if w.kind == "herb" or w.kind == "ore" then
        if locked then return COLORS.red end
        local c = YR.GlimmerSkillColor(skills[w.kind == "herb" and HERBALISM or MINING], w.need)
        return COLORS[c or "orange"]
    end
    return COLORS[w.kind] or COLORS.accent
end
YR.GlimmerColor = Color

local function Rest()
    if InCombatLockdown() then return true end
    if YippRouteDB.glimmerInstances ~= true and IsInInstance then
        local inside = IsInInstance()
        if inside then return true end
    end
    return false
end

local seeking                   -- (Seek, below)
-- A lit quest giver's plate out of sight (its unit frame's alpha). The game lends each plate a unit frame from a pool and
-- takes it back as the plate goes (Blizzard_NamePlateBase.lua): what was put out of sight is kept by the frame, and given
-- back where no one sees it - when the frame is lent to another unit, or half a second after the NPC is let go (its plate
-- gone by then). Given back at once, the health bar flashed up as the camera turned off the NPC (seen the same evening).
local hidden, litFrame, backGen = {}, nil, 0        -- [unit frame] = true: out of sight; the lit giver's
local function FrameOf(p)
    local f = p and rawget(p, "UnitFrame")
    return type(f) == "table" and f.SetAlpha and f or nil
end
local function GiveBack(all)
    for f in pairs(hidden) do
        if all or f ~= litFrame then
            pcall(f.SetAlpha, f, 1)
            hidden[f] = nil
        end
    end
end
-- A light let go fades out where it was, not gone in a frame (the owner, 2026-10-22: "fade in/out instead of snapping,
-- both ways"): a second effect - the ghost - takes it over as it stands, off the plate that goes with it, and fades it
-- out over a third of a second; the light itself is free at once for the next thing lit.
local ghost
local function FadeAway(f)
    local x, y = f:GetCenter()
    if not (x and y) then return end
    ghost = ghost or YR.GlimmerEffect(UIParent)
    ghost.ghost = true
    ghost:Hide()
    ghost:SetParent(UIParent)
    ghost:SetFrameStrata("BACKGROUND")
    ghost:SetScale(f:GetEffectiveScale() / UIParent:GetEffectiveScale())
    ghost:ClearAllPoints()
    ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    ghost:SetStyle(f.style)
    ghost:SetLook(f.scale, f.bright)
    ghost:SetColor(f.r, f.g, f.b)
    ghost.state = f.state
    ghost:SetLine(unpack(f.lineSaid or {}))
    ghost:SetName(unpack(f.nameSaid or {}))
    ghost:SetAlpha(1)
    ghost:Show()
    ghost.t, ghost.fade, ghost.out = f.t, f.fade or 1, 1
    ghost.line:SetAlpha(ghost.fade)
    ghost.npc:SetAlpha(ghost.fade)
end
local function Detach()
    if fx and plate and fx:IsShown() and not fx.ghost then pcall(FadeAway, fx) end
    if litFrame then
        litFrame = nil
        backGen = backGen + 1
        local gen = backGen
        C_Timer.After(0.5, function() if gen == backGen then GiveBack() end end)
    end
    if not (plate or ticker or seeking) then return end         -- (nothing hung: nothing to take down)
    if ticker then ticker:Cancel() ticker = nil end
    if seeking then seeking:Cancel() seeking = nil end
    if fx then
        if fx:IsShown() then fx.goneAt = GetTime and GetTime() end
        fx:Hide()
        fx:ClearAllPoints()
        fx:SetParent(UIParent)
    end
    plate = nil
end

local function Clear()
    want = nil
    Detach()
    if On() then Gate(false) end
end

-- Too low for you, looked at while something is lit. Lit, it is lit in full: near or not is not drawn
-- (the owner, 2026-10-14). The game's "unable" cursor counts only within reach, where it can mean
-- nothing but too low - farther off the game shows it for every node, and a Peacebloom you can pick
-- was drawn red. Out of reach, Classic's number against your skill, where your skill is known.
local function Paint()
    if not (want and fx and plate) then return end
    local okR, near = pcall(UnitIsInInteractRange, UNIT)
    near = okR and Plain(near) and true or false
    local read, unable = Cursor()
    local skill = skills[want.kind == "herb" and HERBALISM or MINING]
    local locked
    if read and near then locked = unable and true or false
    elseif want.need and skill and (want.kind == "herb" or want.kind == "ore") then
        locked = skill < want.need          -- (your skill not known: not drawn as too low)
    else
        locked = false
    end
    local c = Color(want, locked)
    fx:SetColor(c[1], c[2], c[3])
    fx:SetState(locked and "locked" or "ready")
    -- a giver: its name where the game would draw it, the quest's line just over it
    if want.kind == "giver" then fx:SetName(want.name, want.nr, want.ng, want.nb) else fx:SetName(nil) end
    if want.line then
        fx:SetLine(want.line, want.lr, want.lg, want.lb, want.kind == "giver" and -22 or 16)
    else
        fx:SetLine(nil)
    end
end

local function Attach(to)
    if not (want and to) then return end
    fx = fx or YR.GlimmerEffect(UIParent)
    local ok = pcall(function()
        fx:SetParent(to)
        fx:ClearAllPoints()
        fx:SetPoint("CENTER", to, "CENTER", 0, GROUND[want.kind] or -80)
        local level = Plain(to:GetFrameLevel())
        fx:SetFrameLevel(math.max(0, (level or 1) - 1))
        if fx.SetIgnoreParentAlpha then fx:SetIgnoreParentAlpha(true) end
    end)
    if not ok then return end
    plate = to
    local f = want.kind == "giver" and FrameOf(to)
    if f then
        pcall(f.SetAlpha, f, 0)
        hidden[f], litFrame = true, f
    end
    fx:SetStyle(StyleFor(want.kind))
    fx:SetLook(SizeFor(want.kind), Bright())
    fx.state = nil
    Paint()
    fx:Show()
    -- the same one back within a second (the soft target let it go for a moment, as the camera turned): shown as it
    -- was, not faded in again - a pulse at every turn of the camera
    local now = GetTime and GetTime()
    if fx.litGuid == want.guid and now and fx.goneAt and now - fx.goneAt < 1 then fx.fade = 1 end
    fx.litGuid = want.guid
    ticker = ticker or C_Timer.NewTicker(0.15, Paint)
end

local function PlateOf(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    return ok and Plain(p) or nil
end

-- The object's plate: asked for by "softinteract"; where the game won't hand it over that way, the
-- plates on screen are looked through for the one that is the soft target, or an object. (It was found
-- only by the soft target's name, or a plate whose ID matched - which the game may keep back - and
-- only once, as the plate came: nothing showed on a herb in the game, 2026-10-14.)
local platesSeen = {}           -- the unit of every plate on screen (NAME_PLATE_UNIT_ADDED / _REMOVED)
local function FindPlate()
    local p = PlateOf(UNIT)
    if p then return p end
    for unit in pairs(platesSeen) do
        local okS, same = pcall(UnitIsUnit, unit, UNIT)
        local okO, isObject = pcall(UnitIsGameObject, unit)
        -- (or the unit lit: its GUID - the plate there before the game says it is the soft target's)
        local okG, guid = pcall(UnitGUID, unit)
        if (okS and Plain(same)) or (okO and Plain(isObject)) or (want and want.guid and okG and Plain(guid) == want.guid) then
            p = PlateOf(unit)
            if p then return p end
        end
    end
end

-- while an object of ours is targeted and its plate hasn't come: looked for again, a few times a
-- second, for some seconds
local function Seek()
    if seeking then return end
    local tries = 0
    seeking = C_Timer.NewTicker(0.1, function()
        tries = tries + 1
        if want and not plate and tries <= 30 then
            Attach(FindPlate())
            if not plate then return end
        end
        if seeking then seeking:Cancel() seeking = nil end
    end)
end

-- the soft target changed (or something it depends on): what it is now, and whether it is ours
local function Look()
    if Rest() then Clear() return end
    local okG, isObject = pcall(UnitIsGameObject, UNIT)
    local kind, need, known, g, line, lr, lg, lb, nr, ng, nb, isStep
    if okG and Plain(isObject) then
        local okN, name = pcall(UnitName, UNIT)
        local okU, guid = pcall(UnitGUID, UNIT)
        kind, need, known = YR.GlimmerKind(okN and name or nil, okU and guid or nil, UNIT)
        if not (kind and Sub(KEY[kind]) and Gathers(kind)) then Clear() return end
        g = okU and Plain(guid) or nil
        if kind == "quest" and YippRouteDB.glimmerQuestText ~= false then line = QuestLine(UNIT, known) end
    else
        local guid, name, lines, step = Giver()
        if not guid then Clear() return end
        isStep = step
        kind, known, g = "giver", name, guid
        if YippRouteDB.glimmerGiverText ~= false then line, lr, lg, lb = GiverLine(lines) end
        -- its name's colour as the game's: green friendly, yellow neutral, red hostile
        local okR, reaction = pcall(UnitReaction, UNIT, "player")
        reaction = okR and Plain(reaction) or 5
        nr, ng, nb = 0, 1, 0
        if reaction == 4 then nr, ng, nb = 1, 1, 0 elseif reaction < 4 then nr, ng, nb = 1, 0.25, 0.25 end
    end
    if want and want.guid == g and plate then
        want.line, want.lr, want.lg, want.lb = line, lr, lg, lb          -- (a count gone up: the line says so)
        Paint()
        return
    end
    Detach()
    want = { kind = kind, need = need, name = known, guid = g, line = line, lr = lr, lg = lg, lb = lb, nr = nr, ng = ng, nb = nb,
        step = isStep }
    Gate(true)
    Attach(FindPlate())             -- else when its plate comes (NAME_PLATE_UNIT_ADDED, and Seek)
    if not plate then Seek() end
end
YR.GlimmerLook = Look
--- Whether a quest giver is lit now; whether it is the NPC the RestedXP step is at; and the plate it is lit on (the world
--- marker steps aside for it: Waypoint.lua).
function YR.GlimmerLitGiver()
    local lit = want ~= nil and want.kind == "giver" and plate ~= nil and fx ~= nil and fx:IsShown()
    return lit, lit and want.step == true, lit and plate or nil
end
--- Whether Glimmer lights quest givers at all now (on, givers on, not resting): the one the interact key would use is lit.
function YR.GlimmerLightsGivers() return On() and Sub(KEY.giver) and not Rest() end
--- What Glimmer holds now, in words (/headstart way log).
function YR.GlimmerNow()
    return ("Glimmer: %s, wants %s, hung on a plate %s, shown %s"):format(On() and "on" or "off", want and tostring(want.kind) or "nothing",
        tostring(plate ~= nil), tostring(fx ~= nil and fx:IsShown()))
end

local function OnEvent(_, event, unit, value)
    if event == "QUEST_LOG_UPDATE" then
        objectivesStale = true             -- (read again when an object is next looked at)
        Look()
    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        Look()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if type(unit) == "string" then platesSeen[unit] = true end
        if want and not plate then Attach(FindPlate()) end
        -- a frame we put out of sight, lent now to another unit: in sight again at once
        local f = type(unit) == "string" and FrameOf(PlateOf(unit))
        if f and hidden[f] and f ~= litFrame then
            pcall(f.SetAlpha, f, 1)
            hidden[f] = nil
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if type(unit) == "string" then platesSeen[unit] = nil end
        -- the plate we hang on gone, or handed on to the next target (plates are reused): looked at again
        if plate and (PlateOf(unit) == plate or PlateOf(UNIT) ~= plate) then
            Detach()
            if want then C_Timer.After(0, Look) end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- (just before the lockdown: the plate's setting can still be written now)
        want = nil
        Detach()
        Gate(false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if held then ApplySettings() end
        Look()
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(platesSeen)                    -- (a loading screen takes every plate)
        -- the account's settings can come from the server after the login and overwrite ours
        ReadSkills()
        ApplySettings()
        Look()
    elseif event == "SKILL_LINES_CHANGED" then
        ReadSkills()
        if want then Look() end                 -- (a profession dropped: its node no longer lit)
    elseif event == "CVAR_UPDATE" then
        if not writing and LootOn() and type(unit) == "string" and LOOT_WATCH[unit:lower()] then
            C_Timer.After(1, ApplyLoot)             -- a graphics preset turned the outline back on
        end
        -- the interact key turned off (or on) by you, in the game's settings: kept as you set it
        if not writing and type(unit) == "string" and unit:lower() == KEY_CVAR:lower() then
            YippRouteDB.glimmerKeyOff = (tostring(value) == "0") or nil
            if YR.RefreshWindow then YR:RefreshWindow() end
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Logging out (or a reload): the soft target settings are put back before the game saves them, and
        -- made again at the next login (PLAYER_ENTERING_WORLD) - so with Headstart removed, the game has
        -- your own. (The loot sparkle's are left: putting those back only shows after a restart.)
        PutBack(SOFT)
        PutBack({ [PLATE] = true, [ICON] = true })
        gateOpen = nil
    end
end

local EVENTS = { "PLAYER_SOFT_INTERACT_CHANGED", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED", "QUEST_LOG_UPDATE", "CVAR_UPDATE", "PLAYER_LOGOUT" }

local lootWas = false
local function Begin()
    ReadSkills()
    ApplySettings()
    lootWas = LootOn()
    Look()
end
local function Again()
    -- a setting changed while on: the loot sparkle as set, and the lit object in the new look
    local loot = LootOn()
    if loot and not lootWas then
        ApplyLoot()
    elseif lootWas and not loot then
        PutBack(LOOT)
        YR.Print("the quest loot sparkle stays until the game is restarted (the outline effect is back on).")
    end
    lootWas = loot
    if fx then
        fx:SetStyle(StyleFor(want and want.kind))
        fx:SetLook(SizeFor(want and want.kind), Bright())
    end
    Look()
end
-- Switched off in a fight: what it changed goes back when the fight ends (a frame for that alone, made
-- the first time it is needed).
local late
local function Later()
    if not late then
        late = CreateFrame("Frame")
        late:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            if not On() then YR.GlimmerRestore() end
        end)
    end
    late:RegisterEvent("PLAYER_REGEN_ENABLED")
end
local function End()
    if InCombatLockdown() then Later() end
    want = nil
    Detach()
    GiveBack(true)
    wipe(platesSeen)
    local loot = YippRouteDB.glimmerWas and YippRouteDB.glimmerWas.outlineModeShowLootEffectWhenDisabled ~= nil
    PutBack(SOFT)
    PutBack({ [PLATE] = true, [ICON] = true })
    gateOpen = nil
    if loot then
        PutBack(LOOT)
        YR.Print("Glimmer off. The quest loot sparkle stays until the game is restarted.")
    end
    lootWas = false
end

--- /headstart glimmer: what the game says about the object in front of you, step by step, to see where
--- a glimmer that doesn't show stops.
function YR.GlimmerDebug()
    local function Say(label, v) YR.Print(("glimmer - %s: %s"):format(label, tostring(v))) end
    Say("switched on", On() and "yes" or "no (Loot page)")
    Say("game settings", ("SoftTargetInteract %s, its name plate %s, loot effect %s"):format(tostring(Get("SoftTargetInteract")),
        tostring(Get(PLATE)), tostring(Get("outlineModeShowLootEffectWhenDisabled"))))
    Say("resting", InCombatLockdown() and "in a fight" or (Rest() and "in an instance") or "no")
    local settings = {}
    for _, name in ipairs({ "SoftTargetInteractRange", "SoftTargetInteractArc", "SoftTargetInteractOnlyInRange",
        "SoftTargetIconGameObject", "SoftTargetIconInteract", "SoftTargetNameplateEnemy", "SoftTargetNameplateFriendly",
        "SoftTargetLowPriorityIcons", "SoftTargetNameplateSize", "nameplateShowAll", "nameplateShowEnemies",
        "nameplateShowFriends", "nameplateShowFriendlyNPCs" }) do
        settings[#settings + 1] = name:gsub("SoftTarget", "") .. " " .. tostring(Get(name))
    end
    Say("more settings", table.concat(settings, ", "))
    -- what each soft target token holds, whatever it is (an object, a friend, an enemy)
    for _, token in ipairs({ UNIT, "softfriend", "softenemy" }) do
        local okE, exists = pcall(UnitExists, token)
        local okU, guid = pcall(UnitGUID, token)
        local okN, name = pcall(UnitName, token)
        local okO, isObj = pcall(UnitIsGameObject, token)
        Say(token, ("exists %s, object %s, %s %s"):format(okE and tostring(Plain(exists)) or "?", okO and tostring(Plain(isObj)) or "?",
            okN and tostring(Plain(name)) or "?", okU and tostring(Plain(guid)) or "?"))
    end
    local okG, isObject = pcall(UnitIsGameObject, UNIT)
    if not okG then Say("soft target", "the game refused UnitIsGameObject") return end
    if issecretvalue and issecretvalue(isObject) then Say("soft target", "kept secret by the game") return end
    if not isObject then Say("soft target", "none - face the object, within some 15 yards") return end
    local okN, name = pcall(UnitName, UNIT)
    local okU, guid = pcall(UnitGUID, UNIT)
    name, guid = okN and Plain(name) or "?", okU and Plain(guid) or "?"
    Say("soft target", ("%s (object %s)"):format(tostring(name), tostring(ObjectID(guid))))
    objectivesStale = true
    local isQuest, how = QuestObject(UNIT, name)
    local kindC, unable, raw = Cursor()
    Say("quest", isQuest and ("yes, by " .. how) or "no")
    if not isQuest then
        -- what the quest log's open objectives say, to see why the name isn't in one
        Say("open objectives", #objectives == 0 and "none read" or table.concat(objectives, " | ", 1, math.min(#objectives, 8)))
    end
    Say("cursor", ("%s%s"):format(tostring(raw), unable and " (unable)" or ""))
    local kind, need = YR.GlimmerKind(name ~= "?" and name or nil, guid ~= "?" and guid or nil, UNIT)
    Say("read as", kind and (kind .. (need and (", needs " .. need) or "") .. (Sub(KEY[kind]) and "" or " - switched off"))
        or "nothing Glimmer lights")
    local okR, near = pcall(UnitIsInInteractRange, UNIT)
    Say("in reach", okR and tostring(Plain(near)) or "the game refused")
    local seen = 0
    for _ in pairs(platesSeen) do seen = seen + 1 end
    Say("its name plate", (PlateOf(UNIT) and "there" or FindPlate() and "found among the plates on screen" or "none")
        .. (" (%d plates on screen)"):format(seen))
    Say("the glimmer", (fx and fx:IsShown() and plate) and ("shown, " .. tostring(fx.style) .. ", " .. tostring(fx.state)) or "not shown")
end

--- The game settings Glimmer changed, put back now. Returns how many. (While it is on they are made
--- again at the next login or zone; this is for after it is off.)
function YR.GlimmerRestore()
    local n = PutBack(SOFT) + PutBack({ [PLATE] = true, [ICON] = true }) + PutBack(LOOT)
    gateOpen = nil
    return n
end

local declared
function YR.StartGlimmer()
    if declared then return end
    declared = true
    YR.Part(On, EVENTS, OnEvent, { start = Begin, again = Again, stop = End })
    -- off, with settings of ours still written down (the game closed while it was on, or it was switched
    -- off in a fight and the game closed before the fight ended): put back now
    if not On() and YippRouteDB.glimmerWas and not InCombatLockdown() then YR.GlimmerRestore() end
end
