-- Glimmer: herbs, ore, chests, quest objects and your fishing bobber light up as you walk up to them,
-- in a look of Headstart's own.
--   Where: the game's own soft target for objects - "softinteract", the one object your interact key
--   would use, the game's choice, within some fifteen yards - says which object; its nameplate, which
--   is switched on only while such an object is targeted, is where that object is on the screen, and
--   the effect hangs under it. One object at a time, as the game picks it.
--   What it is: herbs and ore by name (with the skill Classic asks for them, coloured by your chance
--   of a skill-up), chests by name, the bobber by its ID, quest objects by the game's own link to your
--   quests. A node you can't gather yet shows the game's "unable" cursor: that is read too, so a skill
--   Forever asks differently is still told right as "too low". On a client in another language the
--   names aren't known, and the cursor alone tells herb from ore.
--   Quest loot: the game draws a sparkle on lootable quest items only while its outline effect is off.
--   That is two graphics settings (glimmerLoot), put back when it goes off - but the sparkle stays
--   until the game is restarted, and it says so.
--   Rests in a fight (an open object plate there names every lootable corpse) and in instances, unless
--   you want it there. Every game setting it changes is written down first and put back when Glimmer
--   goes off; changes a fight holds back are made when it ends.
--   Free while off (YR.Part): nothing listened for, no setting touched, no frame made.
--   Account options (YippRouteDB): glimmer (off until turned on), glimmerHerbs, glimmerOre,
--   glimmerChests, glimmerQuest, glimmerFishing (on), glimmerLoot (off), glimmerStyle ("glint"),
--   glimmerColor ("skill"), glimmerSize (100), glimmerBright (100), glimmerInstances (off).
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
local KEY = { herb = "glimmerHerbs", ore = "glimmerOre", chest = "glimmerChests", quest = "glimmerQuest", bobber = "glimmerFishing" }

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
local GROUND = { herb = -100, ore = -100, chest = -80, quest = -72, bobber = -50 }
local LOOT = { outlineModeShowLootEffectWhenDisabled = "1", graphicsOutlineMode = "0", OutlineEngineMode = "0",
    raidGraphicsOutlineMode = "0", RAIDOutlineEngineMode = "0" }
-- a graphics preset sets the outline back: these, changed, put the loot settings on again
local LOOT_WATCH = { graphicsquality = true, raidgraphicsquality = true }
for k in pairs(LOOT) do LOOT_WATCH[k:lower()] = true end

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------
local function On() return YR.Option("glimmer") end
function YR.GlimmerOn() return On() end
local function Sub(key) return YippRouteDB[key] ~= false end         -- the kinds: on unless turned off
local STYLES = { glint = true, halo = true, ring = true, beam = true, marker = true }
function YR.GlimmerStyle() local s = YippRouteDB.glimmerStyle return STYLES[s] and s or "glint" end
function YR.GlimmerColorMode()
    local m = YippRouteDB.glimmerColor
    return (m == "accent" or m == "white") and m or "skill"
end
local function Size() return math.max(50, math.min(200, tonumber(YippRouteDB.glimmerSize) or 100)) / 100 end
local function Bright() return math.max(20, math.min(100, tonumber(YippRouteDB.glimmerBright) or 100)) / 100 end

-- ---------------------------------------------------------------------------
-- Colours: your chance of a skill-up, as the game colours it; chests, quests and the bobber their own
-- ---------------------------------------------------------------------------
local COLORS = {
    orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 }, grey = { 0.55, 0.55, 0.55 },
    red = { 1, 0.15, 0.1 }, chest = { 1, 0.78, 0.3 }, quest = { 1, 0.86, 0.1 }, bobber = { 0.45, 0.8, 1 },
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

-- Your herbalism and mining, read when they may have changed (SKILL_LINES_CHANGED, the login).
local skills = {}
local function ReadSkills()
    wipe(skills)
    if not (GetProfessions and GetProfessionInfo) then return end
    local ok, a, b = pcall(GetProfessions)
    if not ok then return end
    for _, index in ipairs({ a or false, b or false }) do
        if index then
            local got, _, _, rank, _, _, _, line = pcall(GetProfessionInfo, index)
            if got and type(rank) == "number" and type(line) == "number" and not (issecretvalue and (issecretvalue(rank) or issecretvalue(line))) then
                skills[line] = rank
            end
        end
    end
end
YR.GlimmerReadSkills = ReadSkills

-- ---------------------------------------------------------------------------
-- The effect: five looks of our own, drawn from Headstart's art, animated while shown
-- ---------------------------------------------------------------------------
local function Tex(fx, file)
    local t = fx:CreateTexture(nil, "ARTWORK")
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
YR.GLIMMER_LOOKS = { { "glint", "Glints" }, { "halo", "Halo" }, { "ring", "Ripple" }, { "beam", "Beam" }, { "marker", "Marker" } }

-- how each state is drawn: how bright, how fast
local STATES = { far = { 0.5, 0.7 }, ready = { 1, 1 }, locked = { 0.6, 0.5 } }

local function Step(fx, elapsed)
    elapsed = math.min(elapsed or 0, 0.1)
    local st = STATES[fx.state] or STATES.ready
    fx.t = fx.t + elapsed * st[2] * (fx.speed or 1)
    fx.fade = math.min(1, (fx.fade or 0) + elapsed / 0.3)
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
        t:SetVertexColor(self.r, self.g, self.b)
        t:Show()
    end
end
function Effect:SetColor(r, g, b)
    self.r, self.g, self.b = r, g, b
    for _, p in pairs(self.parts) do for _, t in pairs(p) do t:SetVertexColor(r, g, b) end end
    self.ring:SetVertexColor(r, g, b)
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
    for k, v in pairs(Effect) do fx[k] = v end
    fx:SetScript("OnShow", function(self)
        self.fade = 0
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
local function ApplySettings()
    held = false
    for name, v in pairs(SOFT) do Set(name, v) end
    ApplyLoot()
end

-- ---------------------------------------------------------------------------
-- The object targeted: what it is, and the effect on it
-- ---------------------------------------------------------------------------
local fx, plate, want, ticker
local probe                     -- a texture the game draws the object's cursor into (Kind, Locked)

local function Plain(v) return v ~= nil and not (issecretvalue and issecretvalue(v)) and v or nil end

-- The cursor the game would show over the object: herb, ore, and whether it is "unable" (too low).
local function Cursor()
    if not SetUnitCursorTexture then return nil end
    probe = probe or (fx or UIParent):CreateTexture(nil, "BACKGROUND")
    probe:Hide()
    local ok, has = pcall(SetUnitCursorTexture, probe, UNIT)
    if not ok or not Plain(has) then return nil end
    local what = Plain(probe.GetAtlas and probe:GetAtlas()) or Plain(probe:GetTexture())
    if type(what) == "number" and GetFileIDFromPath then
        for _, path in ipairs({ "UnableGatherHerbs", "UnableMine", "GatherHerbs", "Mine" }) do
            local okId, id = pcall(GetFileIDFromPath, "Interface\\Cursor\\" .. path)
            if okId and id == what then what = path break end
        end
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
local function ReadObjectives()
    objectivesStale = false
    wipe(objectives)
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
                if type(text) == "string" and text ~= "" and not Plain(o.finished) then objectives[#objectives + 1] = text:lower() end
            end
        end
    end
end
local function InObjectives(name)
    if type(name) ~= "string" or #name < 3 then return false end
    if objectivesStale then ReadObjectives() end
    name = name:lower()
    for _, text in ipairs(objectives) do
        if text:find(name, 1, true) then return true end
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
                return true, "tooltip"
            end
        end
    end
    if InObjectives(Plain(name)) then return true, "its name in an objective" end
    return false
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
local function Detach()
    if not (plate or ticker or seeking) then return end         -- (nothing hung: nothing to take down)
    if ticker then ticker:Cancel() ticker = nil end
    if seeking then seeking:Cancel() seeking = nil end
    if fx then
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
    fx:SetStyle(YR.GlimmerStyle())
    fx:SetLook(Size(), Bright())
    fx.state = nil
    Paint()
    fx:Show()
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
        if (okS and Plain(same)) or (okO and Plain(isObject)) then
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
    seeking = C_Timer.NewTicker(0.2, function()
        tries = tries + 1
        if want and not plate and tries <= 15 then
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
    if not (okG and Plain(isObject)) then Clear() return end
    local okN, name = pcall(UnitName, UNIT)
    local okU, guid = pcall(UnitGUID, UNIT)
    local kind, need, known = YR.GlimmerKind(okN and name or nil, okU and guid or nil, UNIT)
    if not (kind and Sub(KEY[kind])) then Clear() return end
    local g = okU and Plain(guid) or nil
    if want and want.guid == g and plate then Paint() return end
    Detach()
    want = { kind = kind, need = need, name = known, guid = g }
    Gate(true)
    Attach(FindPlate())             -- else when its plate comes (NAME_PLATE_UNIT_ADDED, and Seek)
    if not plate then Seek() end
end
YR.GlimmerLook = Look

local function OnEvent(_, event, unit, value)
    if event == "QUEST_LOG_UPDATE" then
        objectivesStale = true             -- (read again when an object is next looked at)
        Look()
    elseif event == "PLAYER_SOFT_INTERACT_CHANGED" then
        Look()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if type(unit) == "string" then platesSeen[unit] = true end
        if want and not plate then Attach(FindPlate()) end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if type(unit) == "string" then platesSeen[unit] = nil end
        -- the plate we hang on gone, or handed on to the next target (plates are reused): looked at again
        if plate and PlateOf(UNIT) ~= plate then
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
        if want then Paint() end
    elseif event == "CVAR_UPDATE" then
        if not writing and LootOn() and type(unit) == "string" and LOOT_WATCH[unit:lower()] then
            C_Timer.After(1, ApplyLoot)             -- a graphics preset turned the outline back on
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
        fx:SetStyle(YR.GlimmerStyle())
        fx:SetLook(Size(), Bright())
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
