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
function YR.StartReminders()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_LOGIN", "TRAINER_SHOW", "UPDATE_INVENTORY_DURABILITY",
        "PLAYER_UPDATE_RESTING" }) do
        pcall(f.RegisterEvent, f, e)
    end
    local resting = IsResting and IsResting()
    f:SetScript("OnEvent", function(_, event, level)
        if event == "PLAYER_LEVEL_UP" then
            -- The new spells and talent point are in place a moment after the event, and the ding
            -- animation is worth waiting for in the screenshot.
            if YR.Option("levelShot") then C_Timer.After(1.5, function() Screenshot() end) end
            C_Timer.After(2, function() Remind(level) end)
        elseif event == "PLAYER_LOGIN" then
            C_Timer.After(8, function() Remind() CheckDurability(false) end)
        elseif event == "TRAINER_SHOW" then
            ReadTrainer()
        elseif event == "UPDATE_INVENTORY_DURABILITY" then
            CheckDurability(false)
        elseif event == "PLAYER_UPDATE_RESTING" then
            local now = IsResting()
            if now and not resting then CheckDurability(true) end
            resting = now
        end
    end)
end
