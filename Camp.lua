-- The camp HUD: a campfire icon while a camp is within reach, whether you are actually getting its
-- benefit, and - once you have it - what it is giving you, ticking down. Moved here from Campfire
-- (2026-10-02, before it ever shipped there) when Headstart became the YippYapp QoL addon.
--   Account options in YippRouteDB, all on unless turned off: camp, campList, campAlways, campLocked
--   (false = unlocked, a preview you can drag); campPos = { left, top } once dragged.
--
-- Every spell id below was read off a real camp in game with Campfire's research probe
-- (/headstart camp debug camp, 2026-09-23), not taken from a datamine. The client never tells an addon
-- WHERE a camp is - "Campfire Nearby" is an area aura with no direction and no distance - so this
-- says "near one", never "that way" or "40 yards".
local ADDON, YR = ...

-- 1283391 is the ONLY aura that means "a camp is within reach": duration 0, so it is there while
-- you are in range and gone when you leave. Every other camp aura is one you CARRY AWAY - Camp
-- Benefits runs an hour - so none of them can stand in for proximity, however tempting.
local NEARBY = 1283391      -- "Campfire Nearby": area aura, no duration, no source, ~100 yards
local BENEFITS = 1229741    -- "Camp Benefits": an hour, from the camp - the one you came for
-- "Welcoming Campfire": a minute, and the probe watched it REFRESH while sat at the fire. So having
-- it means settled in at a camp rather than walking past one. Whether sitting is required to gain
-- it or only to keep it is not something the probe pinned down, so nothing here depends on the
-- difference: worst case the line below shows whenever you are at a fire, which is still true.
local WELCOMING = { [1289723] = true, [1229739] = true }

-- What we track, in this order. Two ids for Welcoming Campfire because the probe saw 1289723 at the
-- game's own camp and the datamine also carries 1229739; only one is ever up.
local ORDER = {
    BENEFITS,
    1289723, 1229739,   -- "Welcoming Campfire": a minute, refreshed while you sit at the fire
    1229451,            -- "Recently rested"
    1278062,            -- gardening station
    1278068,            -- tanning station
    1278067,            -- bait and tackle station
}
local RANK = {}
for i, id in ipairs(ORDER) do RANK[id] = i end

local ICON = "Interface\\AddOns\\Headstart\\art\\camp"
local W, ICON_SIZE, PAD = 190, 46, 8
local LINE_H, BIG_H, STAT_H, ROW_H = 14, 20, 17, 16

local hud, statRows, buffRows

-- ---------------------------------------------------------------------------
-- Reading the auras
-- ---------------------------------------------------------------------------
-- Reading a secret aura is an error, not a secret value, so we ask first - and in combat every aura
-- is secret, measured on this client. That is the whole reason the state below has THREE values and
-- not two: yes, no, and "could not look". Treating "could not look" as "you have not got it" is how
-- a buff tracker starts shouting at you the moment a fight begins.
local function AurasBlocked()
    if InCombatLockdown() or UnitAffectingCombat("player") then return true end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return true end
    return false
end

local function IndexSecret(i)
    return C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret
        and C_Secrets.ShouldUnitAuraIndexBeSecret("player", i, "HELPFUL") or false
end

local function ReadAura(i)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local d = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not d then return nil end
        return d.spellId, d.name, d.icon, d.duration, d.expirationTime
    end
    local name, icon, _, _, duration, expires, _, _, _, spellId = UnitAura("player", i, "HELPFUL")
    if not name then return nil end
    return spellId, name, icon, duration, expires
end

-- What the buff actually does for you - "Sharpening Wheel: Strength increased by 6." - lives only in
-- its tooltip; the aura itself carries a name, an icon and a timer and nothing else. Read once per
-- application and kept, because UNIT_AURA fires far more often than a buff changes.
local statCache = {}

--- WoW's own markup out of a tooltip line. The pluralisation form "|4minute:minutes;" carries a
--- COLON, and the rule below uses a colon to recognise a stat - which is exactly how
--- "60 |4minute:minutes; remaining" arrived on screen as "minutes; remaining". Strip the markup
--- first and that line becomes "60 remaining", with no colon and no claim to be a benefit.
local function Clean(text)
    text = text:gsub("|4[^;]*;", " ")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|T.-|t", "")
    -- Spaces and tabs only. A newline in here is a line break in the game's own text: the camp's
    -- description arrives as ONE tooltip line holding "Gained the following camp benefits:", a
    -- blank line, and the benefit. Flattening that merged the header onto the stat, which put the
    -- station name on screen in front of the stat it was introducing.
    text = text:gsub("[ \t]+", " ")
    -- Anything pipe-shaped still left, now that we inline the stat's colour into a |cff..|r of our
    -- own: a stray bar in the game's text would swallow the rest of the line.
    text = text:gsub("|", "/")
    return (text:gsub("^%s*(.-)%s*$", "%1"))
end

--- Every line of a buff's tooltip, as it arrives. Separate from the picking-apart below because
--- when the HUD shows no stats, this is the only way to tell "the client never gave us the text"
--- from "we read it and kept the wrong part" - and we have now been on the wrong side of that.
--- Second return says why there is nothing, for /headstart camp debug.
function YR.CampTooltipLines(index)
    local out, rights = {}, {}
    if not (C_TooltipInfo and C_TooltipInfo.GetUnitAura) then
        return out, "this client has no C_TooltipInfo.GetUnitAura"
    end
    local ok, data = pcall(C_TooltipInfo.GetUnitAura, "player", index, "HELPFUL")
    if not ok then return out, "GetUnitAura errored" end
    if not data then return out, "GetUnitAura returned nothing" end
    if not data.lines then return out, "the tooltip data has no lines" end
    for i, line in ipairs(data.lines) do
        -- TooltipUtil only loads for game type "mainline", so on Forever the fields are already
        -- surfaced and there is nothing to call.
        if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(line) end
        out[i] = type(line.leftText) == "string" and line.leftText
            or ("<no leftText: " .. type(line.leftText) .. ">")
        -- A tooltip line has two columns, and everything above only reads the left one. Third return
        -- so the reader is untouched and only /headstart camp debug pays for it (as in Campfire).
        if type(line.rightText) == "string" and line.rightText ~= "" then
            rights[i] = line.rightText
        end
    end
    return out, nil, rights
end

--- The useful lines of a buff's tooltip: not the title (we show the name), not the "Gained the
--- following camp benefits:" header, not the time remaining (we show our own). What is left
--- is the benefit itself. One rule, once the markup is gone: a line counts when it has a colon with
--- something other than space after it.
local function ReadStats(index)
    local out
    for i, text in ipairs(YR.CampTooltipLines(index)) do
        if i > 1 then
            local clean = Clean(text)
            if clean:match(":%s*%S") then out = out and (out .. "\n" .. clean) or clean end
        end
    end
    return out
end

--- What the camp is giving us right now, or nil when the auras cannot be read at all.
local function Scan()
    if AurasBlocked() then return nil end
    local nearby, benefits, settled, buffs = false, false, false, {}
    for i = 1, 60 do
        if not IndexSecret(i) then
            local ok, id, name, icon, duration, expires = pcall(ReadAura, i)
            if not ok then return nil end
            if id == nil and name == nil then break end
            if id == NEARBY then
                nearby = true
            elseif RANK[id] then
                if id == BENEFITS then benefits = true end
                if WELCOMING[id] then settled = true end
                local timed = (duration and duration > 0) and expires or nil
                -- Kept per buff with the moment this application ends, so a refresh re-reads the
                -- tooltip and a redraw does not - and one entry per buff, not one per refresh.
                local was = statCache[id]
                if not was or was.expires ~= timed then
                    was = { expires = timed, stats = ReadStats(i) or false }
                    statCache[id] = was
                end
                buffs[#buffs + 1] = { id = id, name = name, icon = icon, duration = duration,
                    index = i, expires = timed, stats = was.stats or nil }
            end
        end
    end
    table.sort(buffs, function(l, r) return RANK[l.id] < RANK[r.id] end)
    -- carrying: the camp gave us something that is still running, wherever we have walked to since.
    return { nearby = nearby, benefits = benefits, settled = settled,
        carrying = #buffs > 0, buffs = buffs }
end

-- The last thing we managed to read, kept across a fight so the HUD does not vanish at the pull.
local state = { nearby = false, benefits = false, settled = false, carrying = false, buffs = {} }
local stale = true          -- true until the first successful read, and again while in combat

--- The camp state the HUD draws, plus whether it is what we can see or what we last saw.
--- Never returns nil: "we could not look" is `stale`, not an empty camp.
function YR.CampState()
    return state, stale
end

-- ---------------------------------------------------------------------------
-- Turning that into something worth looking at
-- ---------------------------------------------------------------------------
local function SpellName(id, fallback)
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
    if type(info) == "table" and info.name then return info.name end
    return fallback
end

--- The one line under the fire. Once you have the benefit there is none: the timer and the stats
--- say everything, and a label on top of them is noise. Otherwise it says where you stand - a fire
--- in reach, a fire you have settled at, or neither.
--- What it never says is "no campfire nearby". Only one aura means "a camp is in range", and it is
--- not on you at every camp, so its absence is not proof of anything. The resting line talks about
--- YOUR buff, which we can actually read, and leaves the world out of it.
function YR.CampLines(s)
    if s.benefits then return nil end
    if s.settled then return "Loading giga buffs..." end
    if s.nearby then return "Campfire nearby" end
    return "No camp benefit"
end

-- Looked up by ANY word in the label, not the first one: "Melee Attack Power" leads with "melee",
-- which is in no table anyone would think to write. Anything unknown is white (as in Campfire).
local STAT_COLOR = {
    strength  = { 0.95, 0.45, 0.35 },
    agility   = { 0.55, 0.88, 0.45 },
    stamina   = { 0.95, 0.72, 0.30 },
    intellect = { 0.45, 0.72, 0.98 },
    spirit    = { 0.82, 0.70, 0.98 },
    attack    = { 0.95, 0.60, 0.40 },
    spell     = { 0.60, 0.75, 0.98 },
    critical  = { 0.98, 0.88, 0.45 },
    crit      = { 0.98, 0.88, 0.45 },
    haste     = { 0.50, 0.90, 0.85 },
    armor     = { 0.75, 0.78, 0.85 },
    mana      = { 0.45, 0.72, 0.98 },
    rested    = { 0.70, 0.55, 0.98 },
    resistances = { 0.75, 0.78, 0.85 },
}

function YR.StatColor(label)
    if type(label) == "string" then
        for word in label:lower():gmatch("%a+") do
            local c = STAT_COLOR[word]
            if c then return c[1], c[2], c[3] end
        end
    end
    -- White, not grey: this sits on snow, sand and stone, where light grey is hard to read and looks
    -- like a stat that has run out. The shadow does the separating.
    return 1, 1, 1
end

-- Names the game writes out in full and nobody says out loud. The row is one line on a HUD, not a
-- tooltip, so it gets the word you would use.
local SHORT = {
    ["critical strike"] = "Crit",
    ["critical strike chance"] = "Crit",
    ["critical strike chance with all spells and attacks"] = "Crit",
    -- "Melee" is the one everybody means by attack power, so it is the word that can go.
    ["melee attack power"] = "Attack Power",
    ["ranged attack power"] = "Ranged AP",
    ["melee critical strike"] = "Crit",
    ["ranged critical strike"] = "Ranged Crit",
    ["all attributes"] = "All stats",
    ["all stats"] = "All stats",
    ["all resistances"] = "Resistances",
    ["versatility"] = "Vers",
}

local function Name(stat)
    stat = stat:gsub("^%s*and%s+", ""):gsub("%s+[Rr]ating$", "")
    local short = SHORT[stat:lower()]
    if short then return short end
    return (stat:gsub("^%l", string.upper))
end

--- The stats and numbers out of however the game phrased it. Only those reach the screen: the row is
--- narrow, and the whole line stays in the buff's own tooltip, so shortening it here loses nothing.
--- Every station's sentence, from Camp Benefits' own text in the game data: "Strength increased by 6",
--- "All stats increased by 5%", "Armor increased by 50, all attributes increased by 5, and all
--- resistances increased by 10" (three rows), "Restores 40 Mana every 5 seconds", "You received a
--- small amount of rest experience..." (which read as "You", and "All stats ... 5%" as "All").
--- Returns a list of { label, value }.
local function StatFrom(body)
    if body:lower():find("rest experience", 1, true) then return { { label = "Rested XP" } } end
    local mana, every = body:match("^Restores%s+([%d%.,]+)%s+Mana every%s+([%d%.]+)%s+sec")
    if mana then return { { label = "Mana", value = "+" .. mana .. "/" .. every .. "s" } } end
    local out = {}
    for stat, amount in (body .. ","):gmatch("%s*(.-)%s+increased by%s+([%d%.]+%%?)%s*,") do
        out[#out + 1] = { label = Name(stat), value = "+" .. amount }
    end
    if #out > 0 then return out end
    local stat, amount = body:match("^[Ii]ncreases?%s+your%s+(.-)%s+by%s+([%d%.]+%%?)$")
    if not stat then amount, stat = body:match("^%+([%d%.]+%%?)%s+(.+)$") end
    if stat and stat ~= "" then return { { label = Name(stat), value = "+" .. amount } } end
    -- A shape we do not know. Take the stat's NAME off the front rather than printing the
    -- sentence: two leading capitals catch "Attack Power", one catches "Strength increased...".
    return { { label = Name(body:match("^(%u%a*%s+%u%a*)") or body:match("^(%S+)") or body) } }
end

--- "Sharpening Wheel: Strength increased by 6." -> { label = "Strength", value = "+6" }.
--- The part before the colon is the station that gave it, which the fire already tells you.
function YR.CampStats(text)
    local out = {}
    if type(text) ~= "string" then return out end
    for raw in (text .. "\n"):gmatch("(.-)\n") do
        -- The same colon rule as the reader, so this is safe to call on anything: WoW's plural
        -- markup is gone by now, and a line with no colon left was never a benefit.
        local line = Clean(raw)
        if line ~= "" and line:match(":%s*%S") then
            -- The LAST colon, not the first. "Sharpening Wheel: Strength increased by 6." puts the
            -- station in front of the stat, and anything that got merged in front of that is a
            -- header - so what we want is always after the final one.
            local body = line:match(".*:%s*(.+)$") or line
            body = body:gsub("%s*%.%s*$", "")
            for _, st in ipairs(StatFrom(body)) do out[#out + 1] = st end
        end
    end
    return out
end

local function TimeText(expires)
    if not expires then return "" end
    local left = expires - GetTime()
    if left <= 0 then return "" end
    if left >= 60 then return ("%d:%02d"):format(math.floor(left / 60), math.floor(left % 60)) end
    return ("%ds"):format(math.floor(left))
end

--- How much of a buff is left, 0..1. Its own function because the whole look now hangs off it,
--- and a sign error here would read as a fire that relights itself.
function YR.CampFraction(b)
    if not (b and b.expires and b.duration and b.duration > 0) then return nil end
    local left = (b.expires - GetTime()) / b.duration
    if left < 0 then return 0 end
    if left > 1 then return 1 end
    return left
end

--- "Strength +6" as ONE string, with the stat's colour inlined rather than set on the fontstring.
--- Two fontstrings pinned to opposite edges spread the name and the number across the full width,
--- which is far wider than the fire they belong under; one centred line sits where it belongs.
function YR.StatText(st)
    if not (st and st.label) then return "" end
    local r, g, b = YR.StatColor(st.label)
    local label = ("|cff%02x%02x%02x%s|r"):format(
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), st.label)
    if not st.value then return label end
    return label .. " " .. st.value
end

--- The buff the fire burns down with: the long one you came to the camp for.
local function MainBuff(s)
    for _, b in ipairs(s.buffs) do
        if b.id == BENEFITS then return b end
    end
    return s.buffs[1]
end

--- A camp's worth of state, so the HUD can be placed while you are nowhere near one.
--- Only ever drawn while unlocked.
local function Preview()
    return { nearby = true, benefits = true, carrying = true, buffs = {
        { id = BENEFITS, name = SpellName(BENEFITS, "Camp Benefits"), duration = 3600,
          expires = GetTime() + 3590, stats = "Sharpening Wheel: Strength increased by 6." },
        { id = 1289723, name = SpellName(1289723, "Welcoming Campfire"), duration = 60,
          expires = GetTime() + 48 },
    } }
end

-- ---------------------------------------------------------------------------
-- The frame
-- ---------------------------------------------------------------------------
local function Shadowed(parent, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    -- These sit on the world, not on a panel, so they need a shadow to stay readable over snow,
    -- grass and stone - the same lesson BuffWarden's bar learned.
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1.5, -1.5)
    return fs
end

--- One stat, centred under the fire: name and number together on a single line.
local function StatRow(i)
    local fs = Shadowed(hud, "GameFontNormal")
    fs:SetWidth(W - PAD * 2)
    fs:SetJustifyH("CENTER")
    statRows[i] = fs
    return fs
end

--- One of the shorter camp buffs, under the stats: small, just enough to know it is running.
local function BuffRow(i)
    local r = CreateFrame("Frame", nil, hud)
    r:SetSize(W - PAD * 2, ROW_H)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ROW_H - 4, ROW_H - 4)
    r.icon:SetPoint("LEFT")
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- trim the border every spell icon carries
    r.time = Shadowed(r, "GameFontHighlightSmall")
    r.time:SetPoint("RIGHT")
    r.time:SetJustifyH("RIGHT")
    r.name = Shadowed(r, "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.name:SetPoint("RIGHT", r.time, "LEFT", -4, 0)
    buffRows[i] = r
    return r
end

--- The fire loses its colour from the top down as the hour goes: a grey copy of the icon
--- underneath, and the coloured one cropped to the slice still burning. Nothing is laid OVER the
--- art - a black wedge across a campfire reads as a broken icon, not as a timer.
local function SetBurn(left)
    if not (hud and hud.fill) then return end
    if not left or left <= 0 then hud.fill:Hide() return end
    if left > 1 then left = 1 end
    hud.fill:SetHeight(ICON_SIZE * left)
    -- Texture coordinates run from 0 at the TOP, so the bottom slice starts at 1 - left.
    hud.fill:SetTexCoord(0, 1, 1 - left, 1)
    hud.fill:Show()
end

-- The stats of a tooltip's text, worked out once per text: the HUD is drawn far more often than the
-- text changes, and reading it is a dozen pattern passes.
local NO_STATS, statsOf, statsKept = {}, {}, 0
local function StatsOf(text)
    if type(text) ~= "string" then return NO_STATS end
    local stats = statsOf[text]
    if not stats then
        if statsKept >= 40 then statsOf, statsKept = {}, 0 end
        stats = YR.CampStats(text)
        statsOf[text], statsKept = stats, statsKept + 1
    end
    return stats
end

--- Lay the frame out for the state we are showing. The timer tick only rewrites the numbers; this
--- runs when what is on screen actually changes.
--- Campfire (the addon) has a camp HUD of its own, and two campfires on screen is one too many. Ours
--- steps aside while Campfire is loaded with its HUD switched on; an older Campfire without one, or
--- one with it turned off, leaves ours on. CampfireDB.camp is its "Show a campfire icon" setting.
function YR.CampfireShowsCamp()
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Campfire")
    if not loaded then return false end
    local db = type(CampfireDB) == "table" and CampfireDB or nil
    if db and db.camp == false then return false end
    return _G.CampfireCampFrame ~= nil or (db ~= nil and db.camp == true)
end

local function Draw()
    if not hud then return end
    if YR.CampfireShowsCamp() then hud:Hide() return end
    local unlocked = not YR.Option("campLocked")
    local s = unlocked and Preview() or state

    -- An hour-long buff is exactly the thing you want to watch while you are miles from the camp
    -- that gave it, so proximity is never what decides whether this is on screen. With campAlways
    -- on, the grey fire is simply the resting state and the HUD never goes away.
    if not YR.Option("camp") or not (s.nearby or s.carrying or YR.Option("campAlways") or unlocked) then
        hud:Hide()
        return
    end

    local main = MainBuff(s)
    -- No benefit, no colour at all: the grey fire is the "you are getting nothing from this" state,
    -- and it is the same picture as an hour that has fully run down, which is the same fact.
    SetBurn(s.benefits and (YR.CampFraction(main) or 1) or 0)

    local y = ICON_SIZE + 4

    if main and main.expires then
        hud.big:SetText(TimeText(main.expires))
        hud.big:SetPoint("TOP", 0, -y)
        hud.big:Show()
        y = y + BIG_H
    else
        hud.big:Hide()
    end

    -- A glow while a fire is in reach: the icon over itself, added rather than laid on top, so the
    -- flames light up instead of gaining a ring around them.
    hud.glow:SetShown(s.nearby and true or false)

    local line = YR.CampLines(s)
    if line then
        hud.state:SetText(line)
        -- Green while a fire is in reach and there is something to walk to; muted when the line is
        -- only telling you what you are carrying, so the resting state stays quiet on screen.
        if s.nearby then hud.state:SetTextColor(0.6, 1, 0.6)
        else hud.state:SetTextColor(0.82, 0.82, 0.82) end
        hud.state:SetPoint("TOP", 0, -y)
        hud.state:Show()
        y = y + LINE_H
    else
        hud.state:Hide()
    end

    local stats = (YR.Option("campList") and main) and StatsOf(main.stats) or NO_STATS
    for i, st in ipairs(stats) do
        local fs = statRows[i] or StatRow(i)
        fs:SetPoint("TOP", 0, -y)
        fs:SetText(YR.StatText(st))
        fs:Show()
        y = y + STAT_H
    end
    for i = #stats + 1, #statRows do statRows[i]:Hide() end

    -- The shorter camp buffs, below the stats. The one driving the clock is already the headline.
    local shown = 0
    if YR.Option("campList") then
        for _, b in ipairs(s.buffs) do
            if b ~= main then
                shown = shown + 1
                local r = buffRows[shown] or BuffRow(shown)
                r:SetPoint("TOPLEFT", PAD, -y)
                r.icon:SetTexture(b.icon or ICON)
                r.name:SetText(b.name or tostring(b.id))
                r.time:SetText(TimeText(b.expires))
                r:Show()
                y = y + ROW_H
            end
        end
    end
    for i = shown + 1, #buffRows do buffRows[i]:Hide() end

    hud:SetHeight(y + PAD)
    -- Dimmed while we are going on what we last saw rather than what we can see. Enough to notice,
    -- not enough to stop reading: at 0.55 over snow the whole thing disappeared.
    hud:SetAlpha((stale and not unlocked) and 0.75 or 1)
    hud.handle:SetShown(unlocked)
    hud:Show()
end

--- Only the numbers, and only for a real camp: the preview's times are written once by Draw and
--- left alone, so an unlocked HUD does not count down to nothing while you are placing it.
local function Tick()
    if not (hud and hud:IsShown()) or not YR.Option("campLocked") then return end
    local main = MainBuff(state)
    if state.benefits then SetBurn(YR.CampFraction(main) or 1) end
    if main and main.expires and hud.big:IsShown() then
        hud.big:SetText(TimeText(main.expires))
        -- The last minute is the one worth noticing.
        if main.expires - GetTime() < 60 then hud.big:SetTextColor(1, 0.45, 0.35)
        else hud.big:SetTextColor(1, 0.82, 0.3) end
    end
    local i = 0
    for _, b in ipairs(state.buffs) do
        if b ~= main then
            i = i + 1
            local r = buffRows[i]
            if r and r:IsShown() then r.time:SetText(TimeText(b.expires)) end
        end
    end
end

local function OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Campfire")
    if not YR.Option("campLocked") then
        GameTooltip:AddLine("Preview - drag it where you want it, then /headstart camp lock.", 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    if state.benefits then
        GameTooltip:AddLine(state.nearby and "You're at a camp and have its benefit."
            or "You still have a camp's benefit.", 0.6, 1, 0.6, true)
    elseif state.nearby then
        GameTooltip:AddLine("A camp is within about 100 yards, but you don't have "
            .. SpellName(BENEFITS, "Camp Benefits") .. ".", 1, 0.6, 0.2, true)
    else
        GameTooltip:AddLine("You don't have " .. SpellName(BENEFITS, "Camp Benefits") .. ".",
            1, 0.6, 0.2, true)
    end
    -- What the client does NOT give us, said once here rather than guessed at in the HUD. Only one
    -- aura means "a camp is near", and it is not on you at every camp - so silence is not proof
    -- that there is no camp, and the HUD never pretends otherwise.
    GameTooltip:AddLine("The game doesn't tell addons where a camp is, only that one is near.",
        0.6, 0.6, 0.6, true)
    if stale then
        GameTooltip:AddLine("As of the pull - buffs can't be read in combat. Updates when combat ends.",
            0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function SavePosition()
    local l, t = hud:GetLeft(), hud:GetTop()
    if not (l and t) then return end
    hud:ClearAllPoints()
    hud:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    YippRouteDB.campPos = { l, t }
end

local function Build()
    hud = CreateFrame("Frame", "HeadstartCampFrame", UIParent)
    hud:SetSize(W, ICON_SIZE + BIG_H + PAD)
    hud:SetFrameStrata("MEDIUM")
    hud:SetClampedToScreen(true)
    hud:SetMovable(true)
    hud:EnableMouse(true)
    hud:SetScript("OnEnter", OnEnter)
    hud:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Two copies of the same art. The grey one is always there; the coloured one sits on top,
    -- cropped to what is left, so the flames go out from the tips down.
    hud.icon = hud:CreateTexture(nil, "ARTWORK")
    hud.icon:SetSize(ICON_SIZE, ICON_SIZE)
    hud.icon:SetPoint("TOP", 0, -2)
    hud.icon:SetTexture(ICON)
    hud.icon:SetDesaturated(true)

    hud.fill = hud:CreateTexture(nil, "OVERLAY")
    hud.fill:SetTexture(ICON)
    hud.fill:SetPoint("BOTTOMLEFT", hud.icon, "BOTTOMLEFT")
    hud.fill:SetPoint("BOTTOMRIGHT", hud.icon, "BOTTOMRIGHT")

    -- The glow is the same art again in ADD blend, a little larger: no new texture to draw and no
    -- ring around the icon - the fire itself just burns brighter while one is in reach.
    hud.glow = hud:CreateTexture(nil, "BACKGROUND")
    hud.glow:SetTexture(ICON)
    hud.glow:SetBlendMode("ADD")
    hud.glow:SetAlpha(0.45)
    hud.glow:SetPoint("TOPLEFT", hud.icon, "TOPLEFT", -5, 5)
    hud.glow:SetPoint("BOTTOMRIGHT", hud.icon, "BOTTOMRIGHT", 5, -5)
    hud.glow:Hide()

    hud.big = Shadowed(hud, "GameFontNormalLarge")
    hud.big:SetWidth(W - PAD * 2)
    hud.big:SetJustifyH("CENTER")
    hud.big:SetTextColor(1, 0.82, 0.3)

    hud.state = Shadowed(hud, "GameFontHighlightSmall")
    hud.state:SetWidth(W - PAD * 2)
    hud.state:SetJustifyH("CENTER")

    -- The drag handle, only while unlocked: the same blue edge BuffWarden's bar uses, so an
    -- unlocked YippYapp thing looks the same wherever you meet one.
    hud.handle = CreateFrame("Frame", nil, hud)
    hud.handle:SetAllPoints()
    local function Edge(p1, p2, w, h)
        local t = hud.handle:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0.3, 0.65, 1, 0.9)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if w then t:SetWidth(w) else t:SetHeight(h) end
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 2)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2)
    Edge("TOPLEFT", "BOTTOMLEFT", 2)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 2)
    hud.handle:Hide()

    -- No secure children here, so unlike BuffWarden's bar this one can be dragged in combat too.
    hud:RegisterForDrag("LeftButton")
    hud:SetScript("OnDragStart", function(self)
        if YR.Option("campLocked") then return end
        self:StartMoving()
    end)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    hud:ClearAllPoints()
    local p = YippRouteDB.campPos
    if p and p[1] and p[2] then
        hud:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else
        hud:SetPoint("CENTER", UIParent, "CENTER", 240, 40)
    end

    statRows, buffRows = {}, {}
    -- Nothing fires an event as time passes, so the numbers and the colour draining out of the
    -- fire both come from here - twice a second, and only while the HUD is actually up.
    local elapsed = 0
    hud:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.5 then return end
        elapsed = 0
        Tick()
    end)
    hud:Hide()
end

-- ---------------------------------------------------------------------------
-- Keeping it current
-- ---------------------------------------------------------------------------
--- Read the auras again and redraw. Safe to call as often as you like; the reading is debounced.
--- onAura: called for a change in your auras. In a fight they can't be read, and they change all the
--- time: once the HUD has said its reading is old, nothing new can be drawn until the fight ends.
function YR.RefreshCamp(onAura)
    if not (YippRouteDB and YR.Option("camp")) then
        if hud then hud:Hide() end
        return
    end
    if not hud then Build() end
    local fresh = Scan()
    if fresh then
        state, stale = fresh, false
    else
        if stale and onAura then return end
        stale = true        -- keep the last reading; say it is old rather than call it empty
    end
    Draw()
end

-- UNIT_AURA comes in bursts (a camp hands out several auras at once), so one read per burst.
local pending = false
local function Later()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        YR.RefreshCamp(true)
    end)
end

local function SetOption(key, on)
    YippRouteDB[key] = on and true or false
    YR.RefreshCamp()
end

--- Show the campfire icon, or never.
function YR.SetCampIcon(on) SetOption("camp", on) end

--- List what the camp has given you under the icon.
function YR.SetCampList(on) SetOption("campList", on) end

--- Keep the grey fire on screen away from camps too, as the resting state. Untick and the HUD
--- appears only when a camp or its buff is actually involved.
function YR.SetCampAlways(on) SetOption("campAlways", on) end

--- Unlocked shows a preview wherever you are, so it can be dragged into place.
function YR.SetCampLocked(locked) SetOption("campLocked", locked) end

--- /headstart camp debug: what the HUD read, and the raw tooltip lines behind each buff's stats.
--- The HUD reads our OWN auras, so when it shows nothing this is the only way to tell "no camp
--- near" apart from "a camp that gives no aura we can see".
function YR.CampDebug()
    local s, old = YR.CampState()
    YR.Print(("camp: nearby %s, benefits %s, carrying %s - reading is %s"):format(tostring(s.nearby),
        tostring(s.benefits), tostring(s.carrying), old and "STALE (auras are secret right now)" or "current"))
    for _, b in ipairs(s.buffs) do
        print(("  %d %s%s"):format(b.id, tostring(b.name),
            b.expires and (" - %ds left"):format(b.expires - GetTime()) or ""))
        if b.index then
            local lines, why, rights = YR.CampTooltipLines(b.index)
            if why then print("    tooltip: " .. why) end
            -- Clean: a tooltip line is full of |4 and |c markup that chat would try to render.
            for i, text in ipairs(lines) do
                local right = rights and rights[i]
                print(("    [%d] %s%s"):format(i, Clean(text), right and ("   >> " .. Clean(right)) or ""))
            end
        end
    end
end

function YR.StartCamp()
    local f = CreateFrame("Frame")
    f:RegisterUnitEvent("UNIT_AURA", "player")
    -- Both edges of a fight: one to dim it and stop trusting the reading, one to take a fresh one.
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", Later)
    YR.RefreshCamp()
end
