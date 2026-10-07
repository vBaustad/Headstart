-- Reminders: one quiet chat line when there is something to do about it.
--   * Trainer: at a ding (and once at login) - what your class trainer has for you now and about what
--     it costs. The ranks come from the game's data (Data/TrainerSpells.lua); the prices are only
--     shown at the trainer, so every visit remembers them (YippRouteDB.trainerCosts[CLASS]) and a
--     rank never seen there is counted as "price not known yet".
--   * Talents: at a ding (and once at login) - points you haven't spent.
--   * Durability: when your most worn piece drops under the warning line, once until you repair;
--     and when you come into a town or an inn while it's under the town line, "repair here".
--   * Screenshot at every ding.
-- Account options (YippRouteDB, Settings, QoL), all on unless turned off: remindTrainer,
-- remindTalents, durability, levelShot; durWarn (percent, default 25), durTown (default 50).
local ADDON, YR = ...

local DUR_WARN, DUR_TOWN = 25, 50

local function Class() local _, c = UnitClass("player") return c end

local function RaceBit()
    local _, _, id = UnitRace("player")
    return id and bit.lshift(1, id - 1) or 0
end

local function Coins(c) return (GetCoinTextureString and GetCoinTextureString(c)) or (c .. "c") end

-- ---------------------------------------------------------------------------
-- Trainer
-- ---------------------------------------------------------------------------
local function Costs()
    YippRouteDB.trainerCosts = YippRouteDB.trainerCosts or {}
    local c = Class()
    YippRouteDB.trainerCosts[c] = YippRouteDB.trainerCosts[c] or {}
    return YippRouteDB.trainerCosts[c]
end

local function Key(name, rank) return name .. "|" .. (rank or 0) end

--- What the class trainer would teach you at `level` that you don't know yet:
--- { { id, name, rank, level, cost (nil = not seen at a trainer yet) }, ... } by level.
--- A later rank only counts once you know the one before it - which is also what keeps talent
--- spells out until you have taken the talent.
function YR.TrainerMissing(level)
    level = level or UnitLevel("player")
    local race, costs, out = RaceBit(), Costs(), {}
    local list = (YR.TrainerSpells or {})[Class()] or {}
    -- The highest rank of each spell you know. Not "every rank you know": a client that drops the
    -- old rank when it teaches the new one would make rank 2 look missing to a player with rank 3.
    local top = {}
    for _, e in ipairs(list) do
        if IsPlayerSpell(e[1]) and (top[e[3]] or -1) < e[4] then   -- known is known, whatever the race mask says
            top[e[3]] = e[4]
        end
    end
    -- Which ranks the data has for your race at all. A first rank that is another race's copy (the
    -- data has Holy Light 1 for one race only; the others get theirs as a different spell) can't be
    -- checked, so it doesn't block rank 2 - except for a talent, where not knowing rank 1 is the point.
    local mine = {}
    for _, e in ipairs(list) do
        if e[5] == 0 or bit.band(e[5], race) ~= 0 then mine[Key(e[3], e[4])] = true end
    end
    local seen = {}
    for _, e in ipairs(list) do
        local id, lvl, name, rank, mask, talent = e[1], e[2], e[3], e[4], e[5], e[6] == 1
        local k = Key(name, rank)
        local have = top[name]
        local prevOk = rank <= 1 or (have or 0) >= rank - 1
            or (have == nil and not talent and not mine[Key(name, rank - 1)])
        if lvl <= level and (mask == 0 or bit.band(mask, race) ~= 0) and not seen[k]
            and (have == nil or rank > have) and prevOk then
            seen[k] = true
            out[#out + 1] = { id = id, name = name, rank = rank, level = lvl, cost = costs[k] }
        end
    end
    return out
end

--- "Holy Light 3, Seal of Fury" and the price, or nil when there is nothing to learn.
function YR.TrainerLine(level)
    local missing = YR.TrainerMissing(level)
    if #missing == 0 then return nil end
    local names, total, unknown = {}, 0, 0
    for _, m in ipairs(missing) do
        names[#names + 1] = m.rank > 0 and (m.name .. " " .. m.rank) or m.name
        if m.cost then total = total + m.cost else unknown = unknown + 1 end
    end
    local price
    if unknown == #missing then
        price = "prices not known yet"
    else
        price = "about " .. Coins(total) .. (unknown > 0 and (" + " .. unknown .. " not priced yet") or "")
        if GetMoney() < total then price = price .. ", you have " .. Coins(GetMoney()) end
    end
    return ("new at your class trainer: %s (%s)."):format(table.concat(names, ", "), price)
end

--- At a class trainer: remember the price of everything on the list, available or not.
local function ReadTrainer()
    if not (GetNumTrainerServices and YR.TrainerService) then return end
    if IsTradeskillTrainer and IsTradeskillTrainer() then return end
    local costs = Costs()
    for i = 1, GetNumTrainerServices() or 0 do
        local name, rank = YR.TrainerService(i)
        local cost = GetTrainerServiceCost(i)
        if name and cost then
            costs[Key(name, tonumber(type(rank) == "string" and rank:match("(%d+)") or "") or 0)] = cost
        end
    end
end

-- ---------------------------------------------------------------------------
-- Talents
-- ---------------------------------------------------------------------------
--- Talent points not spent yet, or nil when the game won't say. Our own talents are readable with no
--- secrecy gate on Forever: the active config's tree and its currency (what Blizzard's frame shows).
function YR.UnspentTalents()
    local ok, n = pcall(function()
        local config = C_ClassTalents.GetActiveConfigID()
        local info = config and C_Traits.GetConfigInfo(config)
        local tree = info and info.treeIDs and info.treeIDs[1]
        if not tree then return nil end
        local total = 0
        for _, cur in ipairs(C_Traits.GetTreeCurrencyInfo(config, tree, false) or {}) do
            total = total + (cur.quantity or 0)
        end
        return total
    end)
    if ok then return n end
end

local function Remind(level)
    if YR.Option("remindTrainer") then
        local line = YR.TrainerLine(level)
        if line then YR.Print(line) end
    end
    if YR.Option("remindTalents") then
        local n = YR.UnspentTalents()
        if n and n > 0 then YR.Print(("%d talent point%s to spend."):format(n, n == 1 and "" or "s")) end
    end
end

-- ---------------------------------------------------------------------------
-- Durability
-- ---------------------------------------------------------------------------
--- Your most worn piece, in percent (nil with nothing that wears).
function YR.LowestDurability()
    local low
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local p = cur / max * 100
            if not low or p < low then low = p end
        end
    end
    return low
end

local warned = false      -- told about the warning line; again only after it's back above it
local function Warn(text)
    YR.Print(text)
    if UIErrorsFrame then UIErrorsFrame:AddMessage("Headstart: " .. text, 1, 0.6, 0.2) end
end

local function CheckDurability(cameToTown)
    if not YR.Option("durability") then return end
    local low = YR.LowestDurability()
    if not low then return end
    local line = YippRouteDB.durWarn or DUR_WARN
    if low >= line then
        warned = false
    elseif not warned then
        warned = true
        Warn(("your gear is down to %d%% - repair soon."):format(math.floor(low)))
        return
    end
    if cameToTown and low < (YippRouteDB.durTown or DUR_TOWN) then
        YR.Print(("your gear is at %d%% - repair while you're here."):format(math.floor(low)))
    end
end

-- ---------------------------------------------------------------------------
-- Each reminder listens only while it is on: the ding for the screenshot and the two lines, your
-- gear's wear and coming into a town for the durability lines, the trainer's window for the prices.
local function Leveling()
    return YR.Option("levelShot") or YR.Option("remindTrainer") or YR.Option("remindTalents") or YR.Option("levelUpStats")
end

local DingLines              -- (the lines a ding used to write in chat: further down)
local dinged
local function Shot() Screenshot() end
local function Ding() Remind(dinged) end
local function OnLevel(_, _, level, ...)
    if DingLines and YR.Option("levelUpStats") then DingLines(...) end
    -- The new spells and talent point are in place a moment after the event, and the ding
    -- animation is worth waiting for in the screenshot.
    dinged = level
    if YR.Option("levelShot") then C_Timer.After(1.5, Shot) end
    C_Timer.After(2, Ding)
end

-- ---------------------------------------------------------------------------
-- A ding as chat used to tell it: "You have gained 19 hit points. Your Strength increases by 1." Forever
-- only says "Congratulations, you have reached Level 2!".
--   The ding's event carries what you gained (health, power, strength, agility, stamina, intellect).
--   Spirit isn't in it, and should a number come as nothing, what you had is remembered from the
--   login and from the ding before, and the difference said instead. The lines are written a moment
--   after the ding, in the yellow of the game's own, in the game's own words where it still has them.
--   Account option levelUpStats (on unless turned off): lines in chat, nothing else.
-- ---------------------------------------------------------------------------
local STAT_NAMES = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }
local had = {}                  -- what you had: [1..5] the five stats, hp, mp
local gain = {}                 -- what the ding's event said: [1..4], hp, mp

local function Readable(v) return type(v) == "number" and not (issecretvalue and issecretvalue(v)) and v or nil end

local function Have(into)
    for i = 1, 5 do
        local ok, base = pcall(UnitStat, "player", i)
        into[i] = ok and Readable(base) or nil
    end
    local ok, health = pcall(UnitHealthMax, "player")
    into.hp = ok and Readable(health) or nil
    local got, mana = pcall(UnitPowerMax, "player", 0)
    into.mp = got and Readable(mana) or nil
end

local now = {}
local function SayDing()
    Have(now)
    local chat = DEFAULT_CHAT_FRAME
    if not (chat and chat.AddMessage) then return end
    -- what the event said, else the difference from what you had
    local function Up(key)
        local said = gain[key]
        if said and said > 0 then return said end
        if now[key] and had[key] and now[key] > had[key] then return now[key] - had[key] end
        return 0
    end
    local hp, mp = Up("hp"), Up("mp")
    if hp > 0 and mp > 0 then
        chat:AddMessage((_G.LEVEL_UP_HEALTH_MANA or "You have gained %d hit points and %d mana."):format(hp, mp), 1, 1, 0)
    elseif hp > 0 then
        chat:AddMessage((_G.LEVEL_UP_HEALTH or "You have gained %d hit points."):format(hp), 1, 1, 0)
    end
    for i = 1, 5 do
        local up = Up(i)
        if up > 0 then
            chat:AddMessage((_G.LEVEL_UP_STAT or "Your %s increases by %d."):format(_G["SPELL_STAT" .. i .. "_NAME"] or STAT_NAMES[i], up), 1, 1, 0)
        end
    end
    for k, v in pairs(now) do had[k] = v end
end

local function OnDingStats(hp, mp, _, _, str, agi, sta, int)
    gain.hp, gain.mp, gain[1], gain[2], gain[3], gain[4] = Readable(hp), Readable(mp), Readable(str), Readable(agi), Readable(sta), Readable(int)
    C_Timer.After(0.4, SayDing)         -- your new numbers are in place a moment after the event
end
DingLines = OnDingStats
YR.LevelUpLines = SayDing               -- for the tests

local resting
-- wear comes a piece at a time (a death is eight of these at once): one look for the lot
local wearSoon = false
local function Wear() wearSoon = false CheckDurability(false) end
local function OnWear(_, event)
    if event == "UPDATE_INVENTORY_DURABILITY" then
        if wearSoon then return end
        wearSoon = true
        C_Timer.After(0.5, Wear)
    else
        local now = IsResting()
        if now and not resting then CheckDurability(true) end
        resting = now
    end
end

-- Once, eight seconds after the login - and only with a reminder on. This is asked the first time at
-- the login and never says yes again, so turning a reminder on later doesn't set it off.
local asked
local function AtLogin()
    if asked then return false end
    asked = true
    return Leveling() or YR.Option("durability")
end
local function Greet() Remind() CheckDurability(false) end

local declared
function YR.StartReminders()
    if declared then return end
    declared = true
    -- (what you have is noted as this comes on and whenever a setting changes: the lines need a "before")
    local function Note() if YR.Option("levelUpStats") then Have(had) end end
    YR.Part(Leveling, { "PLAYER_LEVEL_UP" }, OnLevel, { start = Note, again = Note })
    YR.Part(function() return YR.Option("durability") end, { "UPDATE_INVENTORY_DURABILITY", "PLAYER_UPDATE_RESTING" }, OnWear,
        { start = function() resting = IsResting and IsResting() end })
    YR.Part(function() return YR.Option("remindTrainer") end, { "TRAINER_SHOW" }, ReadTrainer)
    YR.Part(AtLogin, nil, nil, { start = function() C_Timer.After(8, Greet) end })
end
