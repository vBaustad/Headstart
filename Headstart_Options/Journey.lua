-- The Journey window: what Journey.lua counted, told a page at a time, as a book of the game's own
-- kind: the quest log's parchment, a dialog's gold border, the game's icons and fonts, ink on paper.
-- /hs journey.
--   A page, top to bottom: its icon in the middle, a small line saying what the page is, one large
--   number or name, a line under it; then a boxed remark - the page's best line, the thing worth
--   reading out ("that is 1.4 marathons, in boots") - and under that up to six rows, each an icon, a
--   name, an amount, and a bar as long as its share of the largest. A row with no bar can have a
--   line of smaller words where the bar would be (row[5]): what won't fit beside the name goes
--   there, and a name is never wider than the room its amount leaves it. One page has a chart in
--   place of some rows (a column a level). The last page is the whole of it on one sheet, for a
--   screenshot.
--   It is told at level 20, 30, 40, 50 and 60 only: what is shown is a chapter, the journey as it
--   stood when that level was reached (Journey.lua writes it then). The latest one opens; the ones
--   before it are a click away (the numbers along the top). Between two of those levels there is
--   nothing new to read - that is the point: it comes rarely enough to be worth opening. Before the
--   first chapter the window says at which level it will be written. From the second chapter on, a
--   page sets the levels since the chapter before against the road up to then (gold, enemies,
--   quests and yards by the hour, deaths by how often).
--   Under 60 it is told as a pit stop on the way ("so far", how many levels are left); at 60 as a road
--   walked to its end. From level 40 the road page says when you learned to ride - or that you are
--   still on foot, and then the gold page says how far the purse is from it.
--   Feats (from level 10): six tallies, each with milestones - marathons on foot, enemies, quests,
--   gold, zones, flights. A row is how far you are to its next milestone; the page's number is the
--   milestones reached so far, and its remark the one closest to done.
--   A mob has its own face where the journey knows which creature it was (mobId): the game draws a
--   portrait from a creature's display, and a model frame that is told the creature says which
--   display that is - at once for a creature the client knows, when it has loaded otherwise. Until
--   then, and for a mob whose ID was never caught, a skull.
--   The remark's box is as tall as its words, and what is under it moves down (and closes up a
--   little) to make the room.
--   Pages are turned with the two buttons at the bottom (or the mouse wheel). Nothing turns by itself.
--   A page fades in, its number counts up and its bars grow, in under a second: one script on the
--   window does that, and it only runs while the window is open and a page is still arriving.
--   The art is the game's: the atlas "questbg-parchment" (the quest log's page), "book-line" (the rule
--   under a heading), the dialog box's border and the tooltip's status bar, and icons from Interface\Icons.
--   Part of Headstart_Options: none of it is in memory until it is first opened.
local YR = _G.HeadstartNS

local W, H = 440, 600
local FONT, TITLE = "Fonts\\FRIZQT__.TTF", "Fonts\\MORPHEUS.TTF"
local ICONS = "Interface\\Icons\\"
local INK, FAINT, HEAD = { 0.13, 0.08, 0.03 }, { 0.33, 0.24, 0.14 }, { 0.45, 0.09, 0.04 }
local ROWS, TILES, COLUMNS = 6, 8, 60

local win, pages, at, age, settled = nil, {}, 1, 0, false

-- ---------------------------------------------------------------------------
-- Words for amounts
-- ---------------------------------------------------------------------------
local function Num(n)
    local s = ("%d"):format(math.floor((n or 0) + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,")
    out = out:reverse()
    if out:sub(1, 1) == "," then out = out:sub(2) end
    return out
end
local function Dur(s)
    s = math.floor(s or 0)
    local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
    if d > 0 then return ("%dd %dh"):format(d, h) end
    if h > 0 then return ("%dh %dm"):format(h, m) end
    if m > 0 then return ("%dm"):format(m) end
    return ("%ds"):format(s)
end
local function Gold(c)
    c = math.floor(c or 0)
    local g, s, k = math.floor(c / 10000), math.floor(c % 10000 / 100), c % 100
    if g > 0 then return ("|cff7a4e00%sg|r |cff4a4a52%ds|r"):format(Num(g), s) end
    if s > 0 then return ("|cff4a4a52%ds|r |cff73390f%dc|r"):format(s, k) end
    return ("|cff73390f%dc|r"):format(k)
end
local function Sum(t, keys)
    local n = 0
    for _, k in ipairs(keys) do n = n + (t[k] or 0) end
    return n
end
-- The largest few of a table of counts: { { name, amount }, ... }
local function Top(t, most)
    local out = {}
    for k, v in pairs(t) do out[#out + 1] = { k, v } end
    table.sort(out, function(a, b) return a[2] > b[2] end)
    for i = #out, most + 1, -1 do out[i] = nil end
    return out
end
local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
-- Rows out of { name, amount, icon } entries, each bar its share of the largest. icon: one for an
-- entry that has none of its own.
local function Rows(list, words, icon)
    local most = 0
    for _, r in ipairs(list) do if r[2] > most then most = r[2] end end
    local out = {}
    for _, r in ipairs(list) do
        if r[2] > 0 then out[#out + 1] = { r[1], words(r[2]), most > 0 and r[2] / most or 0, r[3] or icon } end
    end
    return out
end
local function Plural(n, one, many) return n == 1 and one or many end
local WAYS = { "foot", "ride", "swim", "taxi", "ghost" }      -- every way a yard is travelled

-- ---------------------------------------------------------------------------
-- The pages: each a function of the journey that gives what the page says
-- ---------------------------------------------------------------------------
local told                       -- the level the story is told at: the chapter's (or the sample's)
local function Level() return told or UnitLevel("player") or 1 end
-- (a chapter keeps the days as a count; the running journey has them one by one)
local function Days(j) return type(j.days) == "table" and Count(j.days) or j.dayCount or 0 end
local function Who()
    local name = UnitName("player") or "You"
    local race, class = UnitRace("player"), UnitClass("player")
    return name, ("Level %d %s %s"):format(Level(), race or "", class or "")
end
local function I(name) return ICONS .. name end

local STORY = {
    function(j)
        local name, what = Who()
        local days = Days(j)
        local level = Level()
        local began, played = date("%d %B %Y", j.since or time()), Dur(j.t.all)
        local done = level >= 60
        return { icon = I("INV_Misc_Map_01"), accent = { 0.45, 0.30, 0.12 },
            kicker = done and "THE JOURNEY, COMPLETE" or "YOUR JOURNEY SO FAR", big = name, unit = what,
            quip = done and ("Sixty. The road that began on %s is walked: %s played over %d %s. This is all of it, start to finish."):format(
                    began, played, days, Plural(days, "day", "days"))
                or ("A pit stop at level %d, %d %s from the end. The road began on %s; since then %s played over %d %s. Here is how it has gone."):format(
                    level, 60 - level, Plural(60 - level, "level", "levels"), began, played, days, Plural(days, "day", "days")),
            rows = { { "Played", Dur(j.t.all), nil, I("INV_Misc_PocketWatch_01") },
                { "Travelled", Num(Sum(j.d, WAYS)) .. " yards", nil, I("INV_Boots_05") },
                { "Earned", Gold(Sum(j.gold, { "loot", "quest", "vendor", "mail", "other" })), nil, I("INV_Misc_Coin_01") },
                { "Enemies defeated", Num(j.kills), nil, I("Ability_DualWield") } } }
    end,
    function(j, prev)
        -- Since the chapter before: what these levels took, and how they went against the road up to
        -- then - by the hour, as the two stretches are not the same length.
        if not prev then return nil end
        local from, to = prev.level or (Level() - 10), Level()
        local hours, before = ((j.t.all or 0) - (prev.t.all or 0)) / 3600, (prev.t.all or 0) / 3600
        if hours <= 0 or before <= 0 then return nil end
        local EARNED = { "loot", "quest", "vendor", "mail", "other" }
        local function Pair(now, was) return (now or 0) - (was or 0), was or 0 end
        local gold, goldB = Pair(Sum(j.gold, EARNED), Sum(prev.gold, EARNED))
        local kills, killsB = Pair(j.kills, prev.kills)
        local yards, yardsB = Pair(Sum(j.d, WAYS), Sum(prev.d, WAYS))
        local quests, questsB = Pair(j.quests, prev.quests)
        local deaths, deathsB = Pair(j.deaths, prev.deaths)
        local was = ("before level %d: "):format(from)
        local function Every(n, h) return n > 0 and ("one every " .. Dur(h * 3600 / n)) or "none" end
        local rows = {
            { "Gold an hour", Gold(gold / hours), nil, I("INV_Misc_Coin_01"), was .. Gold(goldB / before) },
            { "Enemies an hour", Num(kills / hours), nil, I("Ability_DualWield"), was .. Num(killsB / before) },
            { "Quests", Num(quests), nil, I("INV_Scroll_03"), ("%.1f an hour  -  %s%.1f"):format(quests / hours, was, questsB / before) },
            { "Yards an hour", Num(yards / hours), nil, I("INV_Boots_05"), was .. Num(yardsB / before) },
            { "Deaths", Num(deaths), nil, I("Ability_Rogue_FeignDeath"), Every(deaths, hours) .. "  -  " .. was .. Every(deathsB, before) },
        }
        local fact
        if deaths == 0 then
            fact = ("Not one death from level %d to %d."):format(from, to)
        elseif deathsB > 0 and deaths / hours < deathsB / before * 0.8 then
            fact = ("You died less often than before level %d: %s, against %s."):format(from, Every(deaths, hours), Every(deathsB, before))
        elseif deathsB > 0 and deaths / hours > deathsB / before * 1.25 then
            fact = ("These levels bit back: a death %s, against %s before."):format(Every(deaths, hours), Every(deathsB, before))
        else
            fact = ("%s %s from level %d to %d."):format(Num(deaths), Plural(deaths, "death", "deaths"), from, to)
        end
        if goldB > 0 and gold > 0 then
            local times = (gold / hours) / (goldB / before)
            fact = fact .. (times >= 1.15 and (" Gold came in %.1f times as fast as before."):format(times)
                or times <= 0.85 and (" Gold came in slower than before: %d%% of the old pace."):format(times * 100)
                or " Gold came in at much the same pace.")
        end
        return { icon = I("INV_Misc_PocketWatch_01"), accent = { 0.40, 0.30, 0.56 },
            kicker = ("LEVEL %d TO %d"):format(from, to), big = hours * 3600, words = Dur, unit = "is what these levels took",
            quip = fact, rows = rows }
    end,
    function(j)
        local d = j.d
        local all = Sum(d, WAYS)
        local miles, foot = all / 1760, (d.foot or 0) / 1760
        local fact
        if foot >= 26.2 then
            fact = ("On foot alone you covered %.1f miles: that is %.1f marathons, in boots, with a full pack."):format(foot, foot / 26.2)
        elseif foot >= 1 then
            fact = ("On foot alone you covered %.1f miles. A marathon is 26.2: you are %d%% of the way to your first."):format(foot, foot / 26.2 * 100)
        else
            fact = "Barely out of the starting village. Every road begins with a few yards."
        end
        -- when you learned to ride, from the level it is sold at; before that, the ghost's share
        local level, ride = Level(), j.ride
        if ride and type(ride.level) == "number" then
            fact = fact .. ((ride.seen and " You were first in the saddle at level %d, %s in" or " You learned to ride at level %d, %s in"):format(
                ride.level, Dur(ride.t))) .. (ride.level <= 40 and ": right on time." or ride.level <= 44 and ": a few levels of extra walking."
                or ": the walk there built character.")
        elseif level > 40 and not ride then
            fact = fact .. (" Level %d, and every yard of it without a mount."):format(level)
        elseif (d.ghost or 0) > 1760 then
            fact = fact .. (" And %.1f miles as a ghost, running back."):format(d.ghost / 1760)
        end
        return { icon = I("INV_Boots_05"), accent = { 0.16, 0.48, 0.44 },
            kicker = "THE ROAD BEHIND YOU", big = all, words = function(v) return Num(v) end,
            unit = ("yards travelled  -  %.1f miles"):format(miles), quip = fact,
            rows = Rows({ { "On foot", d.foot or 0, I("INV_Boots_05") }, { "In the saddle", d.ride or 0, I("Ability_Mount_RidingHorse") },
                { "Flying", d.taxi or 0, I("Ability_Mount_Gryphon_01") },
                { "Swimming", d.swim or 0, I("Spell_Frost_SummonWaterElemental") }, { "As a ghost", d.ghost or 0, I("Ability_Vanish") } },
                function(v) return Num(v) .. " yd" end) }
    end,
    function(j)
        local t = j.t
        local all, afk = t.all or 0, t.afk or 0
        local fact = ("That is %.1f full working days, or %d films back to back."):format(all / 28800, all / 7200)
        if afk > 600 then
            fact = fact .. (" You were away for %s of it. Your character waited patiently."):format(Dur(afk))
        else
            fact = fact .. " Hardly a minute of it away from the keyboard."
        end
        return { icon = I("INV_Misc_PocketWatch_01"), accent = { 0.72, 0.42, 0.10 },
            kicker = "WHERE THE HOURS WENT", big = all, words = Dur, unit = "played while Journey was watching", quip = fact,
            rows = Rows({ { "On the road", t.road or 0, I("INV_Boots_05") }, { "In combat", t.combat or 0, I("Ability_DualWield") },
                { "In towns and inns", t.rest or 0, I("INV_Misc_Rune_01") }, { "Flying", t.taxi or 0, I("Ability_Mount_Gryphon_01") },
                { "Away from keyboard", afk, I("Spell_Nature_Sleep") }, { "Dead", t.dead or 0, I("Ability_Rogue_FeignDeath") } }, Dur) }
    end,
    function(j)
        -- A level's speed is its pace. Not its minutes: the first levels would always win, as they take
        -- the least XP. And not its XP an hour: the last levels would always win, as everything there
        -- gives more. So the XP is counted in monsters of that level - one gives 45 + 5 for each level
        -- - and the pace is how many monsters' worth of XP you made an hour, which is much the same
        -- yardstick at level 5 and at level 50. (Where what a level took isn't known - logged before
        -- that was kept - it has its time and no pace.)
        local reached = {}
        for level in pairs(j.levels) do reached[#reached + 1] = level end
        table.sort(reached)
        local need = j.need or {}
        local list, fastest, slowest, longest = {}, nil, nil, nil
        for i, level in ipairs(reached) do
            local before = j.levels[reached[i - 1] or 0]
            local took = (j.levels[level].t or 0) - (before and before.t or 0)
            if before and reached[i - 1] == level - 1 then
                local pace = need[level - 1] and took > 0 and need[level - 1] / (45 + 5 * (level - 1)) / took * 3600 or nil
                local l = { level, took, pace }
                list[#list + 1] = l
                if pace and (not fastest or pace > fastest[3]) then fastest = l end
                if pace and (not slowest or pace < slowest[3]) then slowest = l end
                if not longest or took > longest[2] then longest = l end
            end
        end
        -- the chart: a column a level, as tall as the level was long; the best pace gold, the slowest red
        local chart = {}
        for _, l in ipairs(list) do
            chart[#chart + 1] = { l[2], l == fastest and { 0.80, 0.60, 0.10 } or l == slowest and { 0.62, 0.16, 0.12 } or nil }
        end
        while #chart > COLUMNS do table.remove(chart, 1) end
        -- (what it is, and which level; the figures on the line under: all of it on one line ran together)
        local rows = {}
        local function Name(l) return "Level " .. (l[1] - 1) .. " to " .. l[1] end
        local function Pace(l) return ("%s kills' worth of XP an hour, done in %s"):format(Num(l[3]), Dur(l[2])) end
        if fastest then rows[#rows + 1] = { "Best pace", Name(fastest), nil, I("Spell_Nature_Lightning"), Pace(fastest) } end
        if slowest and slowest ~= fastest then
            rows[#rows + 1] = { "Slowest grind", Name(slowest), nil, I("Spell_Nature_Slow"), Pace(slowest) }
        end
        if longest then
            rows[#rows + 1] = { "Longest level", Name(longest), nil, I("INV_Misc_PocketWatch_01"), Dur(longest[2]) .. " from start to finish" }
        end
        local fact = "Reach a level and it is timed from here on."
        if fastest then
            fact = ("Your best pace was level %d to %d, done in %s: XP worth %s monsters of your level every hour."):format(
                fastest[1] - 1, fastest[1], Dur(fastest[2]), Num(fastest[3]))
            if slowest and slowest ~= fastest and slowest[3] > 0 then
                fact = fact .. (" That is %.1f times the pace of your slowest."):format(fastest[3] / slowest[3])
            end
        elseif longest then
            fact = ("Your longest level so far took %s."):format(Dur(longest[2]))
        end
        return { icon = I("Spell_Holy_WordFortitude"), accent = { 0.22, 0.52, 0.20 },
            kicker = "LEVEL BY LEVEL", big = Level(), words = function(v) return ("%d"):format(v) end,
            unit = #reached > 0 and (#reached .. Plural(#reached, " level", " levels") .. " reached since logging began") or "your level",
            quip = fact, chart = #chart > 1 and chart or nil, rows = rows }
    end,
    function(j)
        local g, s = j.gold, j.spent
        local earned = Sum(g, { "loot", "quest", "vendor", "mail", "other" })
        local spent = Sum(s, { "vendor", "repair", "train", "flight", "other" })
        -- (a first mount with its riding is 100 gold on Forever)
        local mounts = earned / 1000000
        local fact = mounts >= 1 and ("Enough to buy a first mount and its riding %.1f times over."):format(mounts)
            or ("That is %d%% of a first mount and its riding."):format(mounts * 100)
        fact = fact .. (" You spent %s of it, and the most you ever carried was %s."):format(Gold(spent), Gold(g.peak))
        -- old enough to ride and still on foot: how far the purse is from it
        local level = Level()
        if level >= 40 and not j.ride then
            fact = level == 40
                and ("Level 40: old enough to ride. Riding and a first mount come to 100 gold; the most you ever carried is %s, and you spent %s on the way here."):format(
                    Gold(g.peak), Gold(spent))
                or ("Level %d and still walking: riding and a first mount come to 100 gold. The most you ever carried was %s; you spent %s on the way."):format(
                    level, Gold(g.peak), Gold(spent))
        end
        return { from = 10, icon = I("INV_Misc_Coin_01"), accent = { 0.72, 0.54, 0.08 },
            kicker = "GOLD EARNED", big = earned, words = Gold, unit = "came your way", quip = fact,
            rows = Rows({ { "Sold to vendors", g.vendor or 0, I("INV_Misc_Coin_02") }, { "Quest rewards", g.quest or 0, I("INV_Scroll_03") },
                { "Looted", g.loot or 0, I("INV_Misc_Bag_08") }, { "Spent on training", s.train or 0, I("INV_Misc_Book_09") },
                { "Spent on repairs", s.repair or 0, I("Trade_BlackSmithing") }, { "Spent on flights", s.flight or 0, I("Ability_Mount_Gryphon_01") } },
                Gold) }
    end,
    function(j)
        local loot = j.loot
        local best, n = loot.best, loot.n or 0
        -- Green and better have the bars, measured against each other - and on a scale that lets one
        -- epic be seen beside six hundred greens (each bar is its count's logarithm: ten times as
        -- many is one step longer, not ten times as long). White and grey would dwarf them all, and
        -- say little: they are a number each, with no bar.
        local rows, most = {}, 0
        for q = 5, 2, -1 do most = math.max(most, loot.q[q] or 0) end
        for q = 5, 0, -1 do
            local c, count = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q], loot.q[q] or 0
            if count > 0 then
                rows[#rows + 1] = { _G["ITEM_QUALITY" .. q .. "_DESC"] or ("Quality " .. q), Num(count),
                    q >= 2 and (most > 1 and math.log(1 + count) / math.log(1 + most) or 1) or nil, c and { c.r, c.g, c.b } or { 0.6, 0.6, 0.6 } }
            end
        end
        local icon
        if best then
            local get = type(C_Item) == "table" and C_Item.GetItemInfo or GetItemInfo
            local ok, _, _, _, _, _, _, _, _, _, tex = pcall(get, best.link)
            icon = ok and tex or nil
        end
        local grey = n > 0 and (loot.q[0] or 0) / n * 100 or 0
        return { from = 10, icon = icon or I("INV_Misc_Bag_08"), accent = { 0.20, 0.36, 0.70 },
            kicker = "YOUR BEST FIND", big = best and (best.link:match("%[(.-)%]") or best.link) or "Nothing yet",
            unit = best and ("found in " .. (best.zone or "the world") .. " on " .. date("%d %B", best.at or time())) or "loot something and it shows here",
            quip = ("%s things went into your bags along the way. %d%% of them were grey - somebody has to carry the junk to a vendor."):format(Num(n), grey),
            rows = rows }
    end,
    function(j)
        local zones = Count(j.zone)
        local home = Top(j.zone, 1)[1]
        local jumps, all = j.jumps or 0, j.t.all or 0
        local fact = home and ("You spent the most time in %s: %s of it."):format(home[1], Dur(home[2])) or "The map is still mostly blank."
        if jumps > 0 and all > 0 then fact = fact .. (" And you jumped %s times - once every %d seconds."):format(Num(jumps), all / jumps) end
        return { icon = I("INV_Misc_Spyglass_03"), accent = { 0.18, 0.44, 0.62 },
            kicker = "THE WORLD YOU SAW", big = zones, words = Num, unit = Plural(zones, "zone visited", "zones visited")
                .. ("  -  %s flights, %s hearthstones"):format(Num(j.flights), Num(j.hearths)),
            quip = fact, rows = Rows(Top(j.zone, 6), Dur, I("INV_Misc_Map_01")) }
    end,
    function(j)
        local kills, deaths, hours = j.kills or 0, j.deaths or 0, (j.t.all or 0) / 3600
        local worst, nemesis = Top(j.deathZone, 1)[1], Top(j.mobs, 1)[1]
        local fact = nemesis and ("Your most frequent acquaintance: %s, %s times."):format(nemesis[1], Num(nemesis[2])) or "Nothing has crossed your path yet."
        if deaths == 0 then
            fact = fact .. " And not one death. Careful."
        else
            fact = fact .. (" You died %s %s"):format(Num(deaths), Plural(deaths, "time", "times"))
                .. (worst and (", mostly in " .. worst[1]) or "") .. (hours > 0 and (" - once every %.1f hours."):format(hours / deaths) or ".")
        end
        local ids, skull = j.mobId or {}, I("INV_Misc_Bone_HumanSkull_01")
        local list = Top(j.mobs, 6)
        for _, m in ipairs(list) do
            if ids[m[1]] then m[3] = { npc = ids[m[1]], icon = skull } end
        end
        return { icon = I("Ability_DualWield"), face = nemesis and ids[nemesis[1]] or nil, accent = { 0.62, 0.18, 0.16 },
            kicker = "ALONG THE WAY", big = kills, words = Num,
            unit = "enemies defeated  -  " .. Num(j.quests) .. " quests handed in", quip = fact,
            rows = Rows(list, Num, skull) }
    end,
    function(j)
        local hour, most = 0, 0
        for h, s in pairs(j.hours) do if s > most then hour, most = h, s end end
        local sessions = j.sessions or 0
        local fact = (hour < 5 and "A night owl: you play most between %02d:00 and %02d:00, when Azeroth is quiet."
            or hour < 12 and "An early bird: you play most between %02d:00 and %02d:00."
            or hour < 18 and "An afternoon adventurer: you play most between %02d:00 and %02d:00."
            or "An evening regular: you play most between %02d:00 and %02d:00."):format(hour, (hour + 1) % 24)
        if sessions > 0 then fact = fact .. (" An average session lasts %s."):format(Dur((j.t.all or 0) / sessions)) end
        return { from = 20, icon = I("INV_Misc_Book_09"), accent = { 0.52, 0.22, 0.48 },
            kicker = "YOUR HABITS", big = sessions, words = Num, unit = Plural(sessions, "session", "sessions"), quip = fact,
            rows = { { "Longest session", Dur(j.longest), nil, I("INV_Misc_PocketWatch_01") },
                { "Days played", Num(Days(j)), nil, I("INV_Misc_Note_01") },
                { "People grouped with", Num(j.mateCount), nil, I("INV_Misc_GroupLooking") },
                { "Groups joined", Num(j.groups), nil, I("INV_Misc_GroupNeedMore") } } }
    end,
    function(j)
        local chat = j.chat or {}
        local all = 0
        for _, n in pairs(chat) do all = all + n end
        if all == 0 then return nil end
        local NAMES = { GUILD = "Guild", PARTY = "Party", SAY = "Say", WHISPER = "Whispers", RAID = "Raid", YELL = "Yell",
            CHANNEL = "Channels", EMOTE = "Emotes", OFFICER = "Officer", INSTANCE_CHAT = "Instance" }
        local PICTURES = { GUILD = "INV_Shirt_GuildTabard_01", PARTY = "INV_Misc_GroupLooking", WHISPER = "INV_Letter_15", YELL = "Ability_Warrior_BattleShout" }
        local list = {}
        for kind, n in pairs(chat) do list[#list + 1] = { NAMES[kind] or kind, n, I(PICTURES[kind] or "INV_Misc_Note_01"), kind } end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        for i = #list, ROWS + 1, -1 do list[i] = nil end
        local hours = (j.t.all or 0) / 3600
        local most = list[1]
        local fact = ("Your favourite place to talk: %s, with %d%% of everything you wrote."):format(most[1], most[2] / all * 100)
        if hours > 0 then
            fact = fact .. (all / hours >= 20 and " %.0f messages an hour: a talker." or all / hours >= 4 and " %.0f messages an hour." or " %.1f messages an hour: the strong, silent type."):format(all / hours)
        end
        return { from = 20, icon = I("INV_Misc_Note_01"), accent = { 0.30, 0.50, 0.24 },
            kicker = "WORDS ON THE ROAD", big = all, words = Num, unit = Plural(all, "message written", "messages written"), quip = fact,
            rows = Rows(list, Num) }
    end,
    function(j)
        -- Feats: six tallies with milestones. A row is the tally against its next milestone (or its
        -- last, once all are reached); the page's number is the milestones reached in all.
        local FEATS = {
            { "Marathons on foot", I("INV_Boots_05"), (j.d.foot or 0) / 1760 / 26.2, { 1, 2, 5, 10, 20, 40 }, "%.1f" },
            { "Enemies defeated", I("Ability_DualWield"), j.kills or 0, { 100, 500, 1000, 2500, 5000, 10000 } },
            { "Quests handed in", I("INV_Scroll_03"), j.quests or 0, { 25, 100, 250, 500, 1000 } },
            { "Gold earned", I("INV_Misc_Coin_01"), Sum(j.gold, { "loot", "quest", "vendor", "mail", "other" }) / 10000, { 1, 10, 50, 100, 500, 1000 } },
            { "Zones visited", I("INV_Misc_Spyglass_03"), Count(j.zone), { 5, 10, 20, 30, 40 } },
            { "Flights taken", I("Ability_Mount_Gryphon_01"), j.flights or 0, { 10, 50, 100, 250, 500 } },
        }
        local rows, climbed, rungs, near = {}, 0, 0, nil
        for _, f in ipairs(FEATS) do
            local have, steps = f[3], f[4]
            local done = 0
            for _, s in ipairs(steps) do if have >= s then done = done + 1 end end
            climbed, rungs = climbed + done, rungs + #steps
            local to = steps[math.min(done + 1, #steps)]
            local share = math.min(1, have / to)
            local said = f[5] and (f[5]):format(have) or Num(math.floor(have))
            rows[#rows + 1] = { f[1], done >= #steps and (said .. "  -  all reached") or (said .. " of " .. Num(to)), share, f[2] }
            if done < #steps and (not near or share > near[2]) then near = { f[1]:lower(), share, to - have, f[5] } end
        end
        local fact
        if not near then
            fact = "Every milestone reached. There is nothing left on this page to chase."
        elseif climbed == 0 then
            fact = ("None yet - the road is young. Closest: %s, %d%% of the way to its first milestone."):format(near[1], near[2] * 100)
        else
            fact = ("Next milestone: %s, %d%% of the way there - %s to go."):format(near[1], near[2] * 100,
                near[4] and (near[4]):format(near[3]) or Num(math.ceil(near[3])))
        end
        return { from = 10, icon = I("INV_Misc_Ribbon_01"), accent = { 0.62, 0.44, 0.10 },
            kicker = "FEATS OF THE ROAD", big = climbed, words = Num,
            unit = ("of %d milestones reached"):format(rungs), quip = fact, rows = rows }
    end,
    function(j)
        local name, what = Who()
        return { icon = I("INV_Misc_Map_01"), accent = { 0.45, 0.30, 0.12 },
            kicker = Level() >= 60 and "THE WHOLE JOURNEY" or "THE JOURNEY SO FAR", big = name, unit = what,
            grid = { { "Played", Dur(j.t.all) }, { "Travelled", Num(Sum(j.d, WAYS)) .. " yd" },
                { "Gold earned", Gold(Sum(j.gold, { "loot", "quest", "vendor", "mail", "other" })) }, { "Enemies", Num(j.kills) },
                { "Quests", Num(j.quests) }, { "Deaths", Num(j.deaths) }, { "Zones", Num(Count(j.zone)) }, { "Flights", Num(j.flights) } } }
    end,
}

--- A made-up journey as it might stand at `level`, to see the window with something in it.
function YR.JourneySample(level)
    local hours = level * 1.6
    local all = hours * 3600
    local j = { level = level, since = time() - level * 86400 * 1.5, sessions = level * 2, longest = 5.4 * 3600, flights = level * 3, hearths = level * 2,
        jumps = level * 410, groups = level, mateCount = level * 3, kills = level * 95, quests = level * 14, deaths = math.floor(level / 3),
        t = { all = all, road = all * 0.46, combat = all * 0.24, rest = all * 0.12, taxi = all * 0.07, afk = all * 0.09, dead = all * 0.02 },
        d = { foot = level * 21000, ride = level >= 43 and (level - 42) * 30000 or nil, taxi = level * 26000, swim = level * 900, ghost = level * 1400 },
        zone = { ["Stranglethorn Vale"] = all * 0.22, ["The Barrens"] = all * 0.18, ["Tanaris"] = all * 0.15, ["Ashenvale"] = all * 0.12,
            ["Desolace"] = all * 0.09, ["Darnassus"] = all * 0.06, ["Dustwallow Marsh"] = all * 0.05 },
        hours = { [21] = all * 0.3, [20] = all * 0.25, [22] = all * 0.2 }, days = {},
        gold = { loot = level * 31000, quest = level * 42000, vendor = level * 55000, mail = level * 6000, other = level * 2500, peak = level * 68000 },
        spent = { train = level * 30000, repair = level * 9000, flight = level * 4000, vendor = level * 12000 },
        loot = { n = level * 160, q = { [0] = level * 70, [1] = level * 75, [2] = level * 13, [3] = math.floor(level / 6), [4] = level >= 45 and 1 or 0 },
            -- (an epic only once the tally above has one: before that the best is one of its rares)
            best = level >= 45 and { link = "|cffa335ee|Hitem:873::::::::|h[Staff of Jordan]|h|r", q = 4, ilvl = 40, zone = "Stranglethorn Vale", at = time() - 86400 * 4 }
                or { link = "|cff0070dd|Hitem:5191::::::::|h[Cruel Barb]|h|r", q = 3, ilvl = 24, zone = "The Deadmines", at = time() - 86400 * 4 } },
        mobId = { ["Bloodscalp Headhunter"] = 671, ["Venture Co. Geologist"] = 1096, ["Sandfury Axe Thrower"] = 5646,
            ["Kurzen Commando"] = 938, ["Dustwind Harpy"] = 3115 },
        mobs = { ["Bloodscalp Headhunter"] = level * 4, ["Venture Co. Geologist"] = level * 3, ["Sandfury Axe Thrower"] = level * 3,
            ["Kurzen Commando"] = level * 2, ["Dustwind Harpy"] = level * 2 },
        deathZone = { ["Stranglethorn Vale"] = math.floor(level / 5), ["Desolace"] = 2 }, levels = {}, mates = {}, need = {},
        chat = { GUILD = level * 46, PARTY = level * 21, SAY = level * 6, WHISPER = level * 14, YELL = math.floor(level / 4), CHANNEL = level * 3 },
        walked = true, ride = level >= 43 and { level = 43, at = time(), t = all * 0.8 } or nil }
    for i = 1, math.max(1, math.floor(level * 0.8)) do j.days[i] = true end
    -- each level as long as its size at a steady pace, and some a good deal slower or quicker than that
    local size, whole = {}, 0
    for l = 2, level do
        j.need[l - 1] = (l - 1) * (l - 1) * 55 + (l - 1) * 420
        size[l] = j.need[l - 1] / (45 + 5 * (l - 1)) * (0.65 + ((l * 37 + 3) % 10) / 10)
        whole = whole + size[l]
    end
    local at = 0
    for l = 2, level do
        at = at + all * size[l] / whole
        j.levels[l] = { at = time(), t = at, zone = "Stranglethorn Vale" }
    end
    return j
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
local function Ink(parent, font, size, colour, align)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(font, size, "")
    fs:SetTextColor(colour[1], colour[2], colour[3])
    fs:SetJustifyH(align or "LEFT")
    return fs
end

-- A creature's face on h.icon (h: the window, for its head, or a row). h.lens is a model frame, never
-- seen: told the creature, it knows its display, and the game draws a portrait from a display. For a
-- creature the client has to fetch first, the face comes when the model has loaded - if the page is
-- still showing that creature then. Until it does, whatever h.icon had (the skull) stays.
local function Face(h, npc)
    h.npc = npc
    local function Paint(lens)
        if h.npc ~= npc then return end
        local ok, display = pcall(lens.GetDisplayInfo, lens)
        if ok and type(display) == "number" and display > 0 and pcall(SetPortraitTextureFromCreatureDisplayID, h.icon, display) then
            h.icon:SetTexCoord(0, 1, 0, 1)
        end
    end
    h.lens:SetScript("OnModelLoaded", Paint)
    if pcall(h.lens.SetCreature, h.lens, npc) then Paint(h.lens) end
end
local MARKS = { 20, 30, 40, 50, 60 }       -- the levels a chapter is written at
local sampleTop                          -- showing the sample: the last chapter it has (nil: your own journey)
local function Lens(parent, icon)
    local lens = CreateFrame("PlayerModel", nil, parent)
    lens:SetSize(1, 1)
    lens:SetPoint("TOPLEFT", icon, "TOPLEFT")
    lens:SetAlpha(0)
    return lens
end

local function Build()
    win = CreateFrame("Frame", "HeadstartJourneyWindow", UIParent, "BackdropTemplate")
    win:SetSize(W, H)
    win:SetPoint("CENTER", 0, 20)
    -- over Headstart's own window, which it is opened from
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:EnableMouseWheel(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetScript("OnMouseWheel", function(_, delta) YR.JourneyTurn(delta > 0 and -1 or 1) end)
    tinsert(UISpecialFrames, "HeadstartJourneyWindow")
    win:Hide()

    -- the quest log's page, and a dialog's border round it
    win.paper = win:CreateTexture(nil, "BACKGROUND")
    win.paper:SetPoint("TOPLEFT", 8, -8)
    win.paper:SetPoint("BOTTOMRIGHT", -8, 8)
    win.paper:SetColorTexture(0.86, 0.78, 0.62, 1)          -- (the paper's colour, should the atlas not be there)
    win.paper:SetAtlas("questbg-parchment")
    win:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", edgeSize = 28,
        insets = { left = 8, right = 8, top = 8, bottom = 8 } })

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() win:Hide() end)

    -- the chapters there are, along the top: a click tells that one (the one being told can't be clicked)
    win.marks = {}
    for i, level in ipairs(MARKS) do
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        b:SetSize(28, 18)
        b:SetPoint("TOPLEFT", 26 + (i - 1) * 30, -16)
        b:SetText(tostring(level))
        b:SetScript("OnClick", function() YR.JourneyShow(sampleTop, level) end)
        win.marks[i] = b
    end

    -- everything on the page hangs on one frame, which fades in as the page comes
    local page = CreateFrame("Frame", nil, win)
    page:SetAllPoints()
    win.sheet = page

    -- the head, in the middle: the icon in a gold frame, what the page is, the number, a line under it
    win.icon = page:CreateTexture(nil, "ARTWORK")
    win.icon:SetSize(54, 54)
    win.icon:SetPoint("TOP", 0, -30)
    win.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    win.iconGold = page:CreateTexture(nil, "BORDER", nil, 1)
    win.iconGold:SetPoint("TOPLEFT", win.icon, -3, 3)
    win.iconGold:SetPoint("BOTTOMRIGHT", win.icon, 3, -3)
    win.iconGold:SetColorTexture(0.78, 0.60, 0.22, 1)
    win.iconDark = page:CreateTexture(nil, "BORDER", nil, 0)
    win.iconDark:SetPoint("TOPLEFT", win.icon, -5, 5)
    win.iconDark:SetPoint("BOTTOMRIGHT", win.icon, 5, -5)
    win.iconDark:SetColorTexture(0.16, 0.10, 0.04, 1)
    win.lens, win.npc = Lens(page, win.icon), false
    win.kicker = Ink(page, FONT, 12, FAINT, "CENTER")
    win.kicker:SetPoint("TOP", 0, -96)
    win.big = Ink(page, TITLE, 40, HEAD, "CENTER")
    win.big:SetPoint("TOP", 0, -112)
    win.big:SetWidth(W - 60)
    win.big:SetWordWrap(false)
    win.unit = Ink(page, FONT, 13, INK, "CENTER")
    win.unit:SetPoint("TOP", 0, -158)
    win.unit:SetWidth(W - 60)
    win.rule = page:CreateTexture(nil, "ARTWORK")
    win.rule:SetPoint("TOP", 0, -178)
    win.rule:SetSize(W - 70, 8)
    win.rule:SetColorTexture(0.20, 0.13, 0.06, 0.35)
    win.rule:SetAtlas("book-line")

    -- the remark: a darker band with a bar of the page's colour down its left
    win.note = CreateFrame("Frame", nil, page)
    win.note:SetPoint("TOPLEFT", 30, -194)
    win.note:SetSize(W - 60, 62)
    win.note.ground = win.note:CreateTexture(nil, "ARTWORK", nil, 0)
    win.note.ground:SetAllPoints()
    win.note.ground:SetColorTexture(0.16, 0.10, 0.04, 0.13)
    win.note.bar = win.note:CreateTexture(nil, "ARTWORK", nil, 1)
    win.note.bar:SetPoint("TOPLEFT")
    win.note.bar:SetPoint("BOTTOMLEFT")
    win.note.bar:SetWidth(4)
    win.quip = Ink(win.note, FONT, 13, INK)
    win.quip:SetPoint("LEFT", 14, 0)
    win.quip:SetWidth(W - 60 - 26)
    win.quip:SetWordWrap(true)
    win.quip:SetSpacing(3)

    -- the chart: a column a level
    win.chart = CreateFrame("Frame", nil, page)
    win.chart:SetPoint("TOPLEFT", 34, -270)
    win.chart:SetSize(W - 68, 96)
    win.chart.floor = win.chart:CreateTexture(nil, "ARTWORK")
    win.chart.floor:SetPoint("BOTTOMLEFT")
    win.chart.floor:SetPoint("BOTTOMRIGHT")
    win.chart.floor:SetHeight(1)
    win.chart.floor:SetColorTexture(0.16, 0.10, 0.04, 0.6)
    win.chart.columns = {}
    for i = 1, COLUMNS do
        local c = win.chart:CreateTexture(nil, "ARTWORK", nil, 1)
        c:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        win.chart.columns[i] = c
    end

    win.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, page)
        r:SetSize(W - 68, 40)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(24, 24)
        r.icon:SetPoint("TOPLEFT", 0, -2)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.iconEdge = r:CreateTexture(nil, "BORDER")
        r.iconEdge:SetPoint("TOPLEFT", r.icon, -1, 1)
        r.iconEdge:SetPoint("BOTTOMRIGHT", r.icon, 1, -1)
        r.iconEdge:SetColorTexture(0.16, 0.10, 0.04, 1)
        r.lens, r.npc = Lens(r, r.icon), false
        r.name = Ink(r, FONT, 13, INK)
        r.name:SetPoint("TOPLEFT", 34, -1)
        r.name:SetWordWrap(false)
        r.amount = Ink(r, FONT, 13, INK, "RIGHT")
        r.amount:SetPoint("TOPRIGHT", 0, -1)
        r.detail = Ink(r, FONT, 11, FAINT)
        r.detail:SetPoint("TOPLEFT", 34, -19)
        r.detail:SetWidth(W - 68 - 34)
        r.detail:SetWordWrap(false)
        r.track = r:CreateTexture(nil, "ARTWORK", nil, 1)
        r.track:SetColorTexture(0.16, 0.10, 0.04, 0.22)
        r.track:SetPoint("TOPLEFT", 34, -18)
        r.track:SetPoint("TOPRIGHT", 0, -18)
        r.track:SetHeight(9)
        r.fill = r:CreateTexture(nil, "ARTWORK", nil, 2)
        r.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
        r.fill:SetPoint("TOPLEFT", 35, -19)
        r.fill:SetHeight(7)
        win.rows[i] = r
    end

    -- the last page: two columns of four, an amount over its name
    win.tiles = {}
    for i = 1, TILES do
        local t = CreateFrame("Frame", nil, page)
        t:SetSize((W - 80) / 2, 78)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        t:SetPoint("TOPLEFT", 34 + col * ((W - 80) / 2 + 12), -196 - row * 86)
        t.ground = t:CreateTexture(nil, "ARTWORK")
        t.ground:SetAllPoints()
        t.ground:SetColorTexture(0.16, 0.10, 0.04, 0.12)
        t.amount = Ink(t, TITLE, 24, HEAD, "CENTER")
        t.amount:SetPoint("CENTER", 0, 9)
        t.name = Ink(t, FONT, 11, FAINT, "CENTER")
        t.name:SetPoint("BOTTOM", 0, 11)
        win.tiles[i] = t
    end

    win.back = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.back:SetSize(90, 22)
    win.back:SetPoint("BOTTOMLEFT", 30, 24)
    win.back:SetText("Previous")
    win.back:SetScript("OnClick", function() YR.JourneyTurn(-1) end)
    win.on = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.on:SetSize(90, 22)
    win.on:SetPoint("BOTTOMRIGHT", -30, 24)
    win.on:SetText("Next")
    win.on:SetScript("OnClick", function() YR.JourneyTurn(1) end)
    win.count = Ink(win, FONT, 12, FAINT, "CENTER")
    win.count:SetPoint("BOTTOM", 0, 29)
end

local function Ease(p) return 1 - (1 - p) ^ 3 end

-- One page put up: its icon, its words, its bars at nothing, ready to arrive.
local function Show(i)
    at, age, settled = i, 0, false
    local p = pages[i]
    win.page = p
    local accent = p.accent
    win.icon:SetTexture(p.icon)
    win.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    win.npc = false
    if p.face then Face(win, p.face) end       -- (the mob you met most, at the head of its page)
    win.kicker:SetText(p.kicker or "")
    local counted = type(p.big) == "number"
    -- a name is as long as it is: smaller letters for a long one
    local long = not counted and #tostring(p.big or "")
    win.big:SetFont(TITLE, (counted or long <= 12) and 40 or long <= 20 and 30 or 22, "")
    win.big:SetText(counted and p.words(0) or (p.big or ""))
    win.unit:SetText(p.unit or "")
    local noted = p.quip ~= nil
    win.note:SetShown(noted)
    win.note.bar:SetColorTexture(accent[1], accent[2], accent[3], 1)
    win.quip:SetText(p.quip or "")
    -- the box as tall as its words (three lines fit as it is; five at most)
    local tall = noted and win.quip:GetStringHeight()
    local noteH = math.max(62, math.min(104, (type(tall) == "number" and tall or 0) + 22))
    win.note:SetHeight(noteH)
    local under = -(194 + noteH + 14)
    -- the chart, and the rows under it (or under the remark where there is no chart)
    local charted = p.chart ~= nil
    win.chart:SetShown(charted)
    if charted then
        win.chart:ClearAllPoints()
        win.chart:SetPoint("TOPLEFT", 34, under)
        local most = 0
        for _, c in ipairs(p.chart) do if c[1] > most then most = c[1] end end
        local n = #p.chart
        local each = (W - 68) / n
        for k, column in ipairs(win.chart.columns) do
            local c = p.chart[k]
            column:SetShown(c ~= nil)
            if c then
                local colour = c[2] or accent
                column:SetVertexColor(colour[1], colour[2], colour[3], 1)
                column:ClearAllPoints()
                column:SetPoint("BOTTOMLEFT", (k - 1) * each, 1)
                column:SetWidth(math.max(1, each - 1))
                column.share = most > 0 and c[1] / most or 0
                column:SetHeight(0.001)
            end
        end
    end
    local top = charted and (under - 110) or (noted and under or -196)
    -- the rows a little closer together where the page would otherwise run into its buttons
    local count = p.rows and #p.rows or 0
    local step = count > 0 and math.max(34, math.min(44, math.floor((H - 56 + top) / count))) or 44
    for n, r in ipairs(win.rows) do
        local row = p.rows and p.rows[n]
        r:SetShown(row ~= nil)
        if row then
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 34, top - (n - 1) * step)
            r.name:SetText(row[1])
            r.amount:SetText(row[2])
            -- the name has the room its amount leaves it, and no more
            local wide = r.amount:GetStringWidth()
            r.name:SetWidth(math.max(60, W - 68 - 34 - (type(wide) == "number" and wide or 0) - 12))
            r.detail:SetText(row[3] == nil and row[5] or "")
            r.share = row[3] or false
            r.track:SetShown(row[3] ~= nil)
            r.fill:SetShown(row[3] ~= nil)
            -- its picture: an icon, a mob's face (over the icon it comes with, when the game has
            -- it), or (the loot's qualities) a square of the quality's colour
            local picture = row[4]
            r.npc = false
            if type(picture) == "table" and picture.npc then
                r.icon:SetTexture(picture.icon)
                r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                r.fill:SetVertexColor(accent[1], accent[2], accent[3], 1)
                Face(r, picture.npc)
            elseif type(picture) == "table" then
                r.icon:SetColorTexture(picture[1], picture[2], picture[3], 1)
                r.fill:SetVertexColor(picture[1] * 0.75, picture[2] * 0.75, picture[3] * 0.75, 1)
            else
                r.icon:SetTexture(picture or p.icon)
                r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                r.fill:SetVertexColor(accent[1], accent[2], accent[3], 1)
            end
            r.fill:SetWidth(0.001)
        end
    end
    for n, t in ipairs(win.tiles) do
        local tile = p.grid and p.grid[n]
        t:SetShown(tile ~= nil)
        if tile then
            t.amount:SetText(tile[2])
            t.name:SetText(tile[1]:upper())
        end
    end
    win.sheet:SetAlpha(0)
    win.back:SetEnabled(i > 1)
    win.on:SetEnabled(i < #pages)
    win.count:SetText(#pages > 1 and (i .. " / " .. #pages) or "")
end

-- The page arriving: faded in, its number counted up, its bars and columns grown. Then nothing is left to do.
local function OnUpdate(_, elapsed)
    if settled then return end
    age = age + elapsed
    local p = win.page
    win.sheet:SetAlpha(math.min(1, age / 0.25))
    local k = Ease(math.max(0, math.min(1, age / 0.9)))
    if type(p.big) == "number" then win.big:SetText(p.words(p.big * k)) end
    for _, r in ipairs(win.rows) do
        if r:IsShown() and r.share then r.fill:SetWidth(math.max(0.001, (W - 68 - 36) * r.share * k)) end
    end
    if p.chart then
        for n, column in ipairs(win.chart.columns) do
            if p.chart[n] then column:SetHeight(math.max(0.001, 92 * (column.share or 0) * k)) end
        end
    end
    settled = age >= 0.9
end

--- The next page (1) or the one before (-1).
function YR.JourneyTurn(by)
    if not win or not win:IsShown() then return end
    local to = at + by
    if to < 1 or to > #pages then return end
    Show(to)
end

--- The window opened on this character's journey: its latest chapter, from the first page.
---   which   another chapter's level (one that has been written); or "live", the running totals as
---           they stand this minute, told as if a chapter were written now (/hs journey live: for a
---           look under the bonnet, not part of the story)
---   sample  a level: a made-up journey instead, with a chapter at every milestone up to that level
---           (20 at least) - the "try it" list in the settings
function YR.JourneyShow(sample, which)
    if not win then Build() end
    local j, prev, have = nil, nil, {}
    told = nil
    if type(sample) == "number" then
        sampleTop = math.max(20, math.min(60, math.floor(sample / 10) * 10))
        local level = type(which) == "number" and math.max(20, math.min(sampleTop, math.floor(which / 10) * 10)) or sampleTop
        j, prev, told = YR.JourneySample(level), level > 20 and YR.JourneySample(level - 10) or nil, level
        for _, m in ipairs(MARKS) do have[m] = m <= sampleTop end
    else
        sampleTop = nil
        local live = YR.JourneyData()
        local chapters = live and type(live.chapters) == "table" and live.chapters or {}
        local last
        for _, m in ipairs(MARKS) do
            if type(chapters[m]) == "table" and type(chapters[m].t) == "table" then have[m], last = true, m end
        end
        if which == "live" and live then
            j, told, prev = live, UnitLevel("player") or 1, last and chapters[last] or nil
        else
            local pick = type(which) == "number" and have[which] and which or last
            if pick then
                j, told = chapters[pick], pick
                for _, m in ipairs(MARKS) do if m < pick and have[m] then prev = chapters[m] end end
            end
        end
    end
    pages = {}
    if j and (j.t.all or 0) > 0 then
        local level = Level()
        for _, make in ipairs(STORY) do
            local page = make(j, prev)
            if page and level >= (page.from or 1) then pages[#pages + 1] = page end
        end
    else
        -- no chapter yet: when the first (or the next) one is written
        local on, level = YR.JourneyOn(), UnitLevel("player") or 1
        local at = math.max(20, (math.floor(level / 10) + 1) * 10)
        local page = { icon = I("INV_Misc_Map_01"), accent = { 0.45, 0.30, 0.12 }, kicker = "YOUR JOURNEY" }
        if not on then
            page.big, page.unit = "Not being logged", "Journey is turned off."
            page.quip = "Turn it on in Headstart's settings (Journey), or type /hs journey on. It counts from then."
        elseif level >= 60 then
            page.big, page.unit = "Level 60", "was reached before anything was logged"
            page.quip = "A journey is told from what was counted on the way, at level 20, 30, 40, 50 and 60. This character was already there."
        else
            page.big, page.unit = ("Level %d"):format(at), level < 20 and "is where the first chapter is written" or "is where the next chapter is written"
            page.quip = ("It is being counted as you play - the road, the hours, the gold, the loot - and told at level 20, 30, 40, 50 and 60, not in between. %d %s to go."):format(
                at - level, Plural(at - level, "level", "levels"))
        end
        pages[1] = page
    end
    local several = 0
    for _, m in ipairs(MARKS) do if have[m] then several = several + 1 end end
    for i, m in ipairs(MARKS) do
        win.marks[i]:SetShown(have[m] == true and several > 1)
        win.marks[i]:SetEnabled(m ~= told)
    end
    win:SetScript("OnUpdate", OnUpdate)
    win:Show()
    win:Raise()
    Show(1)
end
