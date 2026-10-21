-- "What happened": a panel under the Release button when you die.
--   Nothing is shown or said while a fight is on: the hits are only noted as they come, and looked at
--   when you're dead.
--   Where the numbers come from (the combat log itself is closed to addons on Forever):
--     UNIT_COMBAT for you: every hit as it lands - how much, whether it was a critical or a crushing
--     blow, its school. It doesn't say who hit or with what.
--     The game's damage meter (C_DamageMeter), once the fight is over (it's secret during one): what
--     you took by spell and by whom, and which one was the killing blow.
--     The game's own death recap (C_DeathRecap), where this client fills it in: the last hits with
--     attacker and spell. Used in place of our own list when it has them.
--   Where the game keeps a number secret (it may in instances and battlegrounds) the hit is counted
--   as hidden and not shown; nothing is ever compared with a secret value.
--   The panel: the killing blow at the top (its icon, name, who, how much); under it the last things
--   that happened to you, each a bar as long as the hit was hard (the hardest in large gold letters);
--   then what you took this fight by spell.
--   Account options (YippRouteDB; Headstart, QoL, Reminders): deathRecap (off until turned on),
--   deathChat (off). Per character: YippSetupCharDB.lastDeath, .deaths.
local ADDON, YR = ...

local RING = 24
local ring, head, count = nil, 0, 0         -- the last hits on you, newest at ring[head] (made when turned on)
local hidden = 0                            -- hits on you whose number the game kept secret, this fight
local fight = { taken = 0, start = 0 }
local death                                 -- the death on show (or the last one)
local diedAt = 0                            -- when (GetTime): who and what is only asked for just after
local panel
local f                                     -- our event frame (events only while the recap is on)

local SCHOOLS = { [1] = "Physical", [2] = "Holy", [4] = "Fire", [8] = "Nature", [16] = "Frost", [32] = "Shadow", [64] = "Arcane" }
local SCHOOL_COLOUR = { [1] = { 0.86, 0.80, 0.72 }, [2] = { 1, 0.9, 0.5 }, [4] = { 1, 0.5, 0.25 }, [8] = { 0.45, 0.9, 0.45 },
    [16] = { 0.5, 0.85, 1 }, [32] = { 0.7, 0.55, 1 }, [64] = { 1, 0.6, 1 } }
-- a picture for a hit nothing names: its school's
local SCHOOL_ICON = { [1] = "Interface\\Icons\\INV_Sword_04", [2] = "Interface\\Icons\\Spell_Holy_HolyBolt",
    [4] = "Interface\\Icons\\Spell_Fire_FlameBolt", [8] = "Interface\\Icons\\Spell_Nature_Lightning",
    [16] = "Interface\\Icons\\Spell_Frost_FrostBolt02", [32] = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
    [64] = "Interface\\Icons\\Spell_Nature_StarFall" }
local FLAG = { CRITICAL = "crit", CRUSHING = "crushing", GLANCING = "glancing" }
local AVOID = { MISS = "missed", DODGE = "dodged", PARRY = "parried", BLOCK = "blocked", RESIST = "resisted",
    IMMUNE = "immune", ABSORB = "absorbed", EVADE = "evaded", DEFLECT = "deflected" }
local HEAL, MUTED, GOLD, RED = { 0.4, 0.85, 0.55 }, { 0.5, 0.53, 0.58 }, { 1, 0.8, 0.3 }, { 0.92, 0.28, 0.26 }

local issecret = issecretvalue               -- asked several times a hit
local function Secret(v) return issecret ~= nil and issecret(v) end
local function CharDB() return _G.YippSetupCharDB end
local function Rows() return 8 end

function YR.RecapOn() return YR.Option("deathRecap") end

-- The first school of a mask: its bit (1, 2, 4...), or nil.
local function SchoolBit(mask)
    if type(mask) ~= "number" then return nil end
    for bit = 0, 6 do
        local s = 2 ^ bit
        if mask % (s * 2) >= s then return s end
    end
end

--- "Fire", "Physical"... and its colour: the first school of a mask (nil for none).
function YR.RecapSchool(mask)
    local s = SchoolBit(mask)
    if s then return SCHOOLS[s], SCHOOL_COLOUR[s] end
end

local function Short(n)
    if n >= 10000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end

-- ---------------------------------------------------------------------------
-- Noting the hits (this is every hit on you: no table is made here)
-- ---------------------------------------------------------------------------
local function Push(kind, amount, flag, school)
    head = head % RING + 1
    if count < RING then count = count + 1 end
    local h = ring[head]
    h.t, h.kind, h.amount, h.flag, h.school = GetTime(), kind, amount, flag, school
end

local function OnHit(unit, action, flag, amount, school)
    if Secret(unit) or Secret(action) or unit ~= "player" then return end
    if Secret(amount) or Secret(flag) or Secret(school) then
        hidden = hidden + 1
        return
    end
    if type(amount) ~= "number" then amount = 0 end
    if action == "WOUND" then
        Push("hit", amount, flag, school)
        fight.taken = fight.taken + amount
    elseif action == "HEAL" then
        if amount > 0 then Push("heal", amount, flag, school) end
    elseif AVOID[action] then
        Push(action, 0, flag, school)
    end
end

-- ---------------------------------------------------------------------------
-- After the fight: who and what, from the game's own numbers
-- ---------------------------------------------------------------------------
local function Words(v) return type(v) == "string" and not Secret(v) and v ~= "" and v or nil end
local function Number(v) return type(v) == "number" and not Secret(v) and v or nil end

-- What you took this fight by spell, biggest first: { { id, spell, who, total, overkill, deadly } } or nil.
local function MeterTaken()
    local meter = _G.C_DamageMeter
    if type(meter) ~= "table" or not meter.GetCombatSessionSourceFromType or InCombatLockdown() then return nil end
    local types, sessions = Enum and Enum.DamageMeterType, Enum and Enum.DamageMeterSessionType
    if not (types and sessions and types.DamageTaken and sessions.Current) then return nil end
    local ok, src = pcall(meter.GetCombatSessionSourceFromType, sessions.Current, types.DamageTaken, UnitGUID("player"))
    if not ok or type(src) ~= "table" or Secret(src) or type(src.combatSpells) ~= "table" then return nil end
    local out = {}
    for _, s in ipairs(src.combatSpells) do
        local id, total = Number(s.spellID), Number(s.totalAmount)
        if id and total and total > 0 then
            local details = s.combatSpellDetails
            local who = Words(s.creatureName) or (type(details) == "table" and Words(details.unitName)) or nil
            local name = C_Spell and C_Spell.GetSpellName and Words(C_Spell.GetSpellName(id)) or nil
            out[#out + 1] = { id = id, spell = name or "Melee", who = who, total = total, overkill = Number(s.overkillAmount) or 0,
                deadly = (not Secret(s.isDeadly) and s.isDeadly) and true or false }
        end
    end
    if #out == 0 then return nil end
    table.sort(out, function(a, b) return a.total > b.total end)
    return out
end

-- The game's own recap of this death: { { amount, id, spell, who, crit, school, ago } }, oldest
-- first, or nil where this client doesn't fill it in. Its fields are read as retail names them, each
-- one checked: a client that names them otherwise simply gives nothing here (see YR.RecapDebug).
local function GameRecap()
    local api = _G.C_DeathRecap
    if type(api) ~= "table" or not api.GetRecapEvents then return nil end
    local ok, events = pcall(api.GetRecapEvents)
    if not ok or type(events) ~= "table" or Secret(events) or #events == 0 then return nil end
    local out, last = {}, nil
    for _, e in ipairs(events) do
        if type(e) == "table" and not Secret(e) then
            local amount, when = Number(e.amount), Number(e.timestamp)
            if amount and amount > 0 then
                if when then last = math.max(last or when, when) end
                out[#out + 1] = { amount = amount, when = when, id = Number(e.spellId), spell = Words(e.spellName),
                    who = Words(e.sourceName), crit = (not Secret(e.critical) and e.critical) and true or false,
                    school = Number(e.school), overkill = Number(e.overkill) }
            end
        end
    end
    if #out == 0 then return nil end
    for _, h in ipairs(out) do h.ago = (h.when and last) and (last - h.when) or nil end
    table.sort(out, function(a, b) return (a.ago or 0) > (b.ago or 0) end)
    return out
end

-- ---------------------------------------------------------------------------
-- A death, and what it comes down to
-- ---------------------------------------------------------------------------
local function Snapshot()
    local now = GetTime()
    local d = { at = time(), zone = GetZoneText and GetZoneText() or nil, hits = {}, hidden = hidden, taken = fight.taken,
        lasted = fight.start > 0 and (now - fight.start) or nil }
    -- the hits on you in the last half minute, oldest first
    for i = count - 1, 0, -1 do
        local h = ring and ring[(head - 1 - i) % RING + 1] or {}
        if h.t and now - h.t <= 30 then
            d.hits[#d.hits + 1] = { ago = now - h.t, kind = h.kind, amount = h.amount, crit = FLAG[h.flag], school = h.school }
        end
    end
    return d
end

local function Picture(id, school)
    local tex = id and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    if tex and not Secret(tex) then return tex end
    return SCHOOL_ICON[SchoolBit(school) or 1]
end

--- What a death comes down to, for the panel and the chat line:
---   title    "Killed by Ambush from Stabby" (one line, for chat)
---   hero     { name, who, amount, crit, school, colour, icon, overkill }: the killing blow
---   lines    the last things that happened, oldest first: { time, words, text, kind, big, frac
---            (0..1 of the hardest hit), r, g, b }
---   sources  what you took by spell: { text, amount, frac, icon }   (spells: the same as plain texts)
---   foot     the sum, and what was hidden
function YR.RecapView(d, rows)
    local view = { lines = {}, spells = {}, sources = {} }
    local list = d.recap or d.hits or {}
    local biggest, killer
    for _, h in ipairs(list) do
        if (h.kind or "hit") == "hit" then
            if not biggest or h.amount > biggest.amount then biggest = h end
            killer = h              -- the last hit that landed
        end
    end
    local deadly
    for _, s in ipairs(d.spells or {}) do if s.deadly and not deadly then deadly = s end end

    -- the killing blow: named by the game where it does, else the last hit that landed
    local hero = {}
    if killer then
        hero.amount, hero.school = killer.amount, killer.school
        hero.crit = killer.crit and (killer.crit == true and "crit" or killer.crit) or nil
        hero.name, hero.who, hero.id, hero.overkill = killer.spell, killer.who, killer.id, killer.overkill
    end
    if deadly then
        hero.name, hero.who, hero.id = deadly.spell, deadly.who or hero.who, deadly.id
        if deadly.overkill > 0 then hero.overkill = deadly.overkill end
        hero.amount = hero.amount or deadly.total
    end
    local school, colour = YR.RecapSchool(hero.school)
    hero.schoolName, hero.colour = school, colour or SCHOOL_COLOUR[1]
    hero.icon = Picture(hero.id, hero.school)
    if hero.name then
        view.title = ("Killed by %s%s"):format(hero.name, hero.who and (" from " .. hero.who) or "")
    elseif hero.amount then
        local bits = {}
        bits[#bits + 1] = school
        bits[#bits + 1] = hero.crit
        view.title = ("Killed by a hit of %s%s"):format(Short(hero.amount), #bits > 0 and (" (" .. table.concat(bits, ", ") .. ")") or "")
    else
        view.title = (d.hidden or 0) > 0 and "The game kept this fight's numbers hidden" or "Nothing was seen to hit you"
        hero = nil
    end
    view.hero = hero

    local first = math.max(1, #list - (rows or 8) + 1)
    for i = first, #list do
        local h = list[i]
        local kind = h.kind or "hit"
        local line = { kind = kind, time = h.ago and ("-%.1fs"):format(h.ago) or "", big = h == biggest and #list > 1 }
        local words
        if kind == "hit" then
            local name, c = YR.RecapSchool(h.school)
            local crit = h.crit and (h.crit == true and "crit" or h.crit) or nil
            words = ("%s%s%s%s"):format(Short(h.amount), crit and ("  " .. crit:upper()) or "",
                h.spell and ("  " .. h.spell) or (name and ("  " .. name) or ""), h.who and ("  - " .. h.who) or "")
            c = c or SCHOOL_COLOUR[1]
            line.r, line.g, line.b = c[1], c[2], c[3]
            line.frac = (biggest and biggest.amount > 0) and h.amount / biggest.amount or 0
        elseif kind == "heal" then
            words = ("+%s healed"):format(Short(h.amount))
            line.r, line.g, line.b = HEAL[1], HEAL[2], HEAL[3]
            line.frac = (biggest and biggest.amount > 0) and math.min(1, h.amount / biggest.amount) or 0
        else
            words = AVOID[kind] or kind:lower()
            line.r, line.g, line.b = MUTED[1], MUTED[2], MUTED[3]
            line.frac = 0
        end
        line.words = words
        line.text = line.time .. "   " .. words
        view.lines[#view.lines + 1] = line
    end

    local top = d.spells and d.spells[1] and d.spells[1].total or 0
    local sum = 0
    for _, s in ipairs(d.spells or {}) do sum = sum + s.total end
    for i = 1, math.min(4, #(d.spells or {})) do
        local s = d.spells[i]
        local label = ("%s%s"):format(s.spell, s.who and (" (" .. s.who .. ")") or "")
        view.spells[i] = ("%s  %s"):format(label, Short(s.total))
        view.sources[i] = { text = label, amount = ("%s  %d%%"):format(Short(s.total), sum > 0 and math.floor(s.total / sum * 100 + 0.5) or 0),
            frac = top > 0 and s.total / top or 0, icon = Picture(s.id), deadly = s.deadly }
    end

    local foot = {}
    if (d.taken or 0) > 0 then
        foot[#foot + 1] = ("%s taken%s"):format(Short(d.taken), d.lasted and (" in %ds"):format(d.lasted) or "")
    end
    if (d.hidden or 0) > 0 then foot[#foot + 1] = ("%d hit%s the game kept hidden"):format(d.hidden, d.hidden == 1 and "" or "s") end
    view.foot = table.concat(foot, "  -  ")
    return view
end

-- ---------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------
local W, PAD, TIME_W = 400, 14, 44
local BAR_X = PAD + TIME_W + 8              -- where a hit's bar begins
local BAR_W = W - BAR_X - PAD

local function Build()
    if panel then return end
    local S = YR.Style
    panel = CreateFrame("Frame", "HeadstartDeathRecap", UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)                     -- (over Headstart's window when opened from it)
    panel:SetWidth(W)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    -- a dark rounded card with a thin light outline, and a red line across its top
    local card = S.Rounded(panel, "BACKGROUND", "round", -2)
    card:SetVertexColor(0.045, 0.05, 0.06, 0.96)
    local outline = S.Rounded(panel, "BORDER", "roundline", 1)
    outline:SetVertexColor(1, 1, 1, 0.14)
    local top = panel:CreateTexture(nil, "ARTWORK")
    top:SetPoint("TOPLEFT", 10, -1)
    top:SetPoint("TOPRIGHT", -10, -1)
    top:SetHeight(2)
    top:SetColorTexture(RED[1], RED[2], RED[3], 0.9)

    -- the head: a skull, what this is, where and when, and the way out
    panel.skull = panel:CreateTexture(nil, "ARTWORK")
    panel.skull:SetSize(16, 16)
    panel.skull:SetPoint("TOPLEFT", PAD, -11)
    panel.skull:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
    panel.head = S.Text(panel, 11, S.C.sub)
    panel.head:SetPoint("LEFT", panel.skull, "RIGHT", 6, 0)
    panel.head:SetText("DEATH RECAP")
    panel.close = S.IconButton(panel, "close", function() panel:Hide() end, "Close (it comes back with /headstart death)", nil, 20)
    panel.close:SetPoint("TOPRIGHT", -8, -8)
    panel.where = S.Text(panel, 11, S.C.muted)
    panel.where:SetPoint("RIGHT", panel.close, "LEFT", -6, 0)
    panel.where:SetJustifyH("RIGHT")

    -- the killing blow: its picture in a frame of its school's colour, its name and who, and how much
    local hero = CreateFrame("Frame", nil, panel)
    hero:SetPoint("TOPLEFT", PAD, -36)
    hero:SetPoint("TOPRIGHT", -PAD, -36)
    hero:SetHeight(58)
    hero.bg = S.Rounded(hero, "BACKGROUND", "round", -1)
    hero.edge = hero:CreateTexture(nil, "BORDER")
    hero.edge:SetSize(48, 48)
    hero.edge:SetPoint("LEFT", 5, 0)
    hero.icon = S.Icon(hero, nil, 44)
    hero.icon:SetPoint("CENTER", hero.edge, "CENTER")
    hero.label = S.Text(hero, 10, S.C.muted)
    hero.label:SetPoint("TOPLEFT", hero.edge, "TOPRIGHT", 10, -1)
    hero.label:SetText("KILLING BLOW")
    hero.amount = S.Text(hero, 26)
    hero.amount:SetPoint("TOPRIGHT", -10, -8)
    hero.amount:SetJustifyH("RIGHT")
    hero.tag = S.Text(hero, 11, S.C.gold)
    hero.tag:SetPoint("TOPRIGHT", hero.amount, "BOTTOMRIGHT", 0, -2)
    hero.tag:SetJustifyH("RIGHT")
    hero.name = S.Text(hero, 17, S.C.gold)
    hero.name:SetPoint("TOPLEFT", hero.label, "BOTTOMLEFT", 0, -3)
    hero.name:SetPoint("RIGHT", hero.amount, "LEFT", -8, 0)
    hero.who = S.Text(hero, 12, S.C.sub)
    hero.who:SetPoint("TOPLEFT", hero.name, "BOTTOMLEFT", 0, -3)
    hero.who:SetPoint("RIGHT", hero.amount, "LEFT", -8, 0)
    panel.hero = hero
    -- with nothing to name: one line in its place
    panel.none = S.Text(panel, 14, S.C.sub)
    panel.none:SetPoint("TOPLEFT", PAD, -44)
    panel.none:SetPoint("RIGHT", -PAD, 0)

    panel.listHead = S.Text(panel, 10, S.C.muted)
    panel.rows = {}
    for i = 1, 12 do
        local r = {}
        r.time = S.Text(panel, 11, S.C.muted)
        r.time:SetWidth(TIME_W)
        r.time:SetJustifyH("RIGHT")
        r.track = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
        r.track:SetColorTexture(1, 1, 1, 0.035)
        r.bar = panel:CreateTexture(nil, "BORDER", nil, 2)
        r.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
        r.text = S.Text(panel, 12)
        panel.rows[i] = r
    end
    panel.sourceHead = S.Text(panel, 10, S.C.muted)
    panel.sourceHead:SetText("DAMAGE TAKEN THIS FIGHT")
    panel.sources = {}
    for i = 1, 4 do
        local r = {}
        r.icon = S.Icon(panel, nil, 16)
        r.track = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
        r.track:SetColorTexture(1, 1, 1, 0.035)
        r.bar = panel:CreateTexture(nil, "BORDER", nil, 2)
        r.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
        r.text = S.Text(panel, 12, S.C.text)
        r.amount = S.Text(panel, 12, S.C.sub)
        r.amount:SetJustifyH("RIGHT")
        panel.sources[i] = r
    end
    panel.rule = panel:CreateTexture(nil, "ARTWORK")
    panel.rule:SetColorTexture(1, 1, 1, 0.07)
    panel.rule:SetHeight(1)
    panel.foot = S.Text(panel, 11, S.C.muted)

    -- it comes up softly: a death is abrupt enough
    local group = panel.CreateAnimationGroup and panel:CreateAnimationGroup()
    local fade = group and group.CreateAnimation and group:CreateAnimation("Alpha")
    if fade then
        fade:SetFromAlpha(0)
        fade:SetToAlpha(1)
        fade:SetDuration(0.3)
        if fade.SetSmoothing then fade:SetSmoothing("OUT") end
        panel.fade = group
    end
    panel:Hide()
end

-- Under the game's Release question when it's up (ours is only placed by it: nothing of the game's
-- is touched), else in the upper middle of the screen.
local function Place()
    panel:ClearAllPoints()
    local popup = StaticPopup_FindVisible and StaticPopup_FindVisible("DEATH")
    if type(popup) == "table" and popup.GetBottom and popup:GetBottom() then
        panel:SetPoint("TOP", popup, "BOTTOM", 0, -10)
    else
        panel:SetPoint("TOP", UIParent, "TOP", 0, -260)
    end
end

local function ShowRow(r, on)
    for _, piece in pairs(r) do piece:SetShown(on) end
end

--- The panel for a death (the last one when none is given). Returns false when there is none.
function YR.RecapShow(d)
    d = d or death or (CharDB() and CharDB().lastDeath)
    if type(d) ~= "table" then return false end
    Build()
    local S = YR.Style
    local view = YR.RecapView(d, Rows())
    local was = panel:IsShown()
    panel.where:SetText(("%s%s"):format(d.zone or "", (d.at and date) and ((d.zone and "  -  " or "") .. date("%H:%M", d.at)) or ""))

    local hero, h = panel.hero, view.hero
    hero:SetShown(h ~= nil)
    panel.none:SetShown(h == nil)
    local y = -36
    if h then
        local c = h.colour
        hero.bg:SetVertexColor(c[1], c[2], c[3], 0.10)
        hero.edge:SetColorTexture(c[1], c[2], c[3], 0.9)
        hero.icon:SetTexture(h.icon)
        hero.name:SetText(h.name or ((h.schoolName or "A") .. " hit"))
        hero.who:SetText(h.who and ("from " .. h.who) or (h.name and (h.schoolName or "") or "who and with what: once the fight is over"))
        hero.amount:SetText(h.amount and Short(h.amount) or "")
        hero.amount:SetTextColor(c[1], c[2], c[3])
        local tags = {}
        if h.crit then tags[#tags + 1] = h.crit:upper() end
        if (h.overkill or 0) > 0 then tags[#tags + 1] = Short(h.overkill) .. " overkill" end
        hero.tag:SetText(table.concat(tags, "  -  "))
        y = y - 58 - 12
    else
        panel.none:SetText(view.title)
        y = y - 34
    end

    -- the last things that happened: a bar as long as the hit was hard
    panel.listHead:SetShown(#view.lines > 0)
    if #view.lines > 0 then
        local span = tonumber(view.lines[1].time:match("[%d%.]+"))
        panel.listHead:SetText(span and span >= 1 and ("THE LAST %d SECONDS"):format(math.ceil(span)) or "THE LAST HITS")
        panel.listHead:ClearAllPoints()
        panel.listHead:SetPoint("TOPLEFT", PAD, y)
        y = y - 16
    end
    for i, r in ipairs(panel.rows) do
        local line = view.lines[i]
        ShowRow(r, line ~= nil)
        if line then
            local tall = line.big and 26 or 19
            r.time:SetText(line.time)
            r.time:ClearAllPoints()
            r.time:SetPoint("TOPLEFT", PAD, y - (tall - 14) / 2)
            r.track:ClearAllPoints()
            r.track:SetPoint("TOPLEFT", BAR_X, y)
            r.track:SetSize(BAR_W, tall - 3)
            local bar = line.frac > 0
            r.bar:SetShown(bar)
            if bar then
                r.bar:ClearAllPoints()
                r.bar:SetPoint("TOPLEFT", BAR_X, y)
                r.bar:SetSize(math.max(3, BAR_W * line.frac), tall - 3)
                if line.big then r.bar:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.32) else r.bar:SetVertexColor(line.r, line.g, line.b, 0.26) end
            end
            -- the hardest hit of the lot in larger letters, in gold
            r.text:SetFont(S.FONT, line.big and 15 or 12, line.big and "OUTLINE" or "")
            if line.big then r.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) else r.text:SetTextColor(line.r, line.g, line.b) end
            r.text:SetText(line.words)
            r.text:ClearAllPoints()
            r.text:SetPoint("LEFT", r.track, "LEFT", 7, 0)
            r.text:SetPoint("RIGHT", r.track, "RIGHT", -6, 0)
            y = y - tall
        end
    end

    -- what you took this fight, by spell
    panel.sourceHead:SetShown(#view.sources > 0)
    if #view.sources > 0 then
        y = y - 10
        panel.sourceHead:ClearAllPoints()
        panel.sourceHead:SetPoint("TOPLEFT", PAD, y)
        y = y - 16
    end
    for i, r in ipairs(panel.sources) do
        local s = view.sources[i]
        ShowRow(r, s ~= nil)
        if s then
            r.icon:SetTexture(s.icon)
            r.icon:ClearAllPoints()
            r.icon:SetPoint("TOPLEFT", PAD, y)
            r.track:ClearAllPoints()
            r.track:SetPoint("TOPLEFT", PAD + 22, y)
            r.track:SetSize(W - 2 * PAD - 22, 16)
            r.bar:ClearAllPoints()
            r.bar:SetPoint("TOPLEFT", PAD + 22, y)
            r.bar:SetSize(math.max(3, (W - 2 * PAD - 22) * s.frac), 16)
            if s.deadly then r.bar:SetVertexColor(RED[1], RED[2], RED[3], 0.42) else r.bar:SetVertexColor(RED[1], RED[2], RED[3], 0.20) end
            r.amount:SetText(s.amount)
            r.amount:ClearAllPoints()
            r.amount:SetPoint("RIGHT", r.track, "RIGHT", -6, 0)
            r.text:SetText(s.text)
            r.text:ClearAllPoints()
            r.text:SetPoint("LEFT", r.track, "LEFT", 7, 0)
            r.text:SetPoint("RIGHT", r.amount, "LEFT", -8, 0)
            y = y - 19
        end
    end

    local foot = view.foot ~= ""
    panel.rule:SetShown(foot)
    panel.foot:SetShown(foot)
    if foot then
        y = y - 8
        panel.rule:ClearAllPoints()
        panel.rule:SetPoint("TOPLEFT", PAD, y)
        panel.rule:SetPoint("TOPRIGHT", -PAD, y)
        y = y - 8
        panel.foot:SetText(view.foot)
        panel.foot:ClearAllPoints()
        panel.foot:SetPoint("TOPLEFT", PAD, y)
        y = y - 13
    end
    panel:SetHeight(-y + 12)
    Place()
    panel:Show()
    panel:Raise()
    local fade = rawget(panel, "fade")
    if not was and fade then fade:Play() end
    return true
end

-- Who and what, once the game lets them be read: asked for a few times after the death (the fight
-- may go on round your body), and drawn again when something new came of it. Only in the moments
-- after it: later the game's numbers are another fight's, not this death's.
local function Enrich(d)
    if d ~= death or GetTime() - diedAt > 12 then return end
    local changed = false
    if not d.spells then
        local spells = MeterTaken()
        if spells then d.spells, changed = spells, true end
    end
    if not d.recap then
        local recap = GameRecap()
        if recap then d.recap, changed = recap, true end
    end
    if changed then
        if CharDB() then CharDB().lastDeath = d end
        if panel and panel:IsShown() then YR.RecapShow(d) end
    end
end

local function Died()
    death = Snapshot()
    diedAt = GetTime()
    if CharDB() then
        CharDB().lastDeath = death
        CharDB().deaths = (CharDB().deaths or 0) + 1
    end
    YR.RecapShow(death)
    local d = death
    for _, wait in ipairs({ 0.5, 2, 6 }) do C_Timer.After(wait, function() Enrich(d) end) end
    if YippRouteDB.deathChat == true then YR.Print(YR.RecapView(d, 1).title:gsub("^Killed", "killed") .. ".") end
end

local function NewFight()
    fight.taken, fight.start = 0, GetTime()
    hidden = 0
end

-- ---------------------------------------------------------------------------
local function OnEvent(_, event, ...)
    if event == "UNIT_COMBAT" then
        OnHit(...)
    elseif event == "PLAYER_REGEN_DISABLED" then
        NewFight()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if death then Enrich(death) end
    elseif event == "PLAYER_DEAD" then
        Died()
    elseif panel and panel:IsShown() then
        -- alive again (not a ghost): the panel has said its piece
        local ok, ghost = pcall(UnitIsGhost, "player")
        if not (ok and not Secret(ghost) and ghost) then panel:Hide() end
    end
end

local EVENTS = { "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

--- After the setting changed: the hits are listened for only while the recap is on.
local listening = false
function YR.RecapApply()
    local on = YR.RecapOn()
    if on == listening then return end
    listening = on
    if on and not f then
        -- its frame is made the first time it is wanted: off, there is none
        f = CreateFrame("Frame")
        f:SetScript("OnEvent", OnEvent)
    end
    if not f then return end
    if on then
        if not ring then
            ring = {}
            for i = 1, RING do ring[i] = {} end
        end
        for _, e in ipairs(EVENTS) do pcall(f.RegisterEvent, f, e) end
        pcall(f.RegisterUnitEvent, f, "UNIT_COMBAT", "player")
    else
        f:UnregisterAllEvents()
        if panel then panel:Hide() end
    end
end

--- /headstart death debug: what the game's own recap and meter hold for the last death, by field
--- name - for telling us how this client fills them in.
function YR.RecapDebug()
    local ok, events = pcall(function() return _G.C_DeathRecap.GetRecapEvents() end)
    YR.Print(("game recap: %s, %s events"):format(tostring(ok), type(events) == "table" and #events or tostring(events)))
    local first = ok and type(events) == "table" and events[1]
    if type(first) == "table" then
        local keys = {}
        for k, v in pairs(first) do keys[#keys + 1] = tostring(k) .. "=" .. (Secret(v) and "SECRET" or tostring(v)) end
        table.sort(keys)
        print("  " .. table.concat(keys, ", "))
    end
    local spells = MeterTaken()
    YR.Print(("damage meter: %s"):format(spells and (#spells .. " spells taken") or "nothing readable now"))
    for i = 1, math.min(5, spells and #spells or 0) do
        local s = spells[i]
        print(("  %s (%s) %d over %d %s"):format(s.spell, tostring(s.who), s.total, s.overkill, s.deadly and "DEADLY" or ""))
    end
    YR.Print(("our own list: %d hits kept, %d hidden this fight"):format(count, hidden))
end

function YR.StartRecap()
    YR.Part(YR.RecapOn, nil, nil, { start = YR.RecapApply, stop = YR.RecapApply })
end
