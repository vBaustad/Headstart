-- Auto trainer: at your class trainer, the spells you chose are learned as the window opens.
-- Per class (YippRouteDB.trainer[CLASS]): for each spell (all its ranks) Always, If I can afford it,
-- First rank only (the spell itself is learned, like Always; no rank after the first is - for a spell
-- you start with, that is nothing) or Never, and a reserve: "If I can afford it" spells are only bought while you'd keep at least that
-- much; "Always" spells whenever the gold is there.
-- Defaults (data version 2, 2026-10-02): "If I can afford it" and a 2 silver reserve, so a new
-- character never trains itself down to nothing. A class's table from before keeps what it had -
-- "Always" for every spell left alone, no reserve - because it was stored as "nothing chosen" and a
-- player may have relied on it; the Trainer page has buttons to switch a whole class at once. Always first, then the rest, each lowest level first. Hold Shift as you open the trainer to do
-- it yourself. Account option autoTrain (Settings, Trainer). RestedXP's own trainer automation (it
-- buys everything on its list) is switched off while ours is on, and back on when ours goes off.
--   Two things keep it from spending what you didn't mean to spend:
--   Only your class's spells are bought - the names in the client's list of what your class learns
--   from a trainer (Data/TrainerSpells.lua). A weapon master, a riding trainer and anything else
--   that opens this same window is not a profession trainer either, and "every spell you can afford"
--   there would be every weapon skill, or riding the moment the window opened. What isn't a class
--   spell is left to you, and named. With no list for your class, nothing is bought at all.
--   And the switch is the whole account's while the choices and the reserve are each class's: so the
--   first time it would buy on a character, it asks - how many spells, for how much, and what it
--   keeps (YippSetupCharDB.trainOK, per character). Not now: nothing is bought, and it asks again at
--   the next visit. After a yes it never asks on that character again.
local _, YR = ...

YR.TRAINER_CHOICES = { { "always", "Always" }, { "gold", "If I can afford it" }, { "first", "First rank only" }, { "never", "Never" } }

function YR.TrainerData(class)
    YippRouteDB.trainer = YippRouteDB.trainer or {}
    if not class then
        local _, c = UnitClass("player")
        class = c or "WARRIOR"
    end
    local d = YippRouteDB.trainer[class]
    if not d then
        d = { reserve = 200, spells = {}, v = 2 }
        YippRouteDB.trainer[class] = d
    end
    return d
end

--- What a spell nobody chose for gets: "If I can afford it", or "Always" in a table from before v2.
function YR.TrainerDefault(class)
    return YR.TrainerData(class).v == 2 and "gold" or "always"
end

function YR.TrainerChoice(name, class)
    return YR.TrainerData(class).spells[name] or YR.TrainerDefault(class)
end

function YR.SetTrainerChoice(name, choice, class)
    YR.TrainerData(class).spells[name] = choice ~= YR.TrainerDefault(class) and choice or nil
end

--- One choice for many spells: every one in `names` (a list), or only those learned up to `maxLevel`
--- when `levels` ([name] = level) is given.
function YR.SetTrainerChoices(names, choice, class, levels, maxLevel)
    for _, name in ipairs(names) do
        if not (levels and maxLevel) or (levels[name] or 0) <= maxLevel then
            YR.SetTrainerChoice(name, choice, class)
        end
    end
end

-- RestedXP's trainer automation: off while ours is on (remembering it was on), back when ours is off.
local function RxpProfile()
    local rxp = RXP
    return type(rxp) == "table" and type(rxp.settings) == "table" and type(rxp.settings.profile) == "table"
        and rxp.settings.profile
end

function YR:SyncRxpTrainer()
    local p = RxpProfile()
    if not p then return end
    if YR.Option("autoTrain") then
        if p.enableTrainerAutomation then
            p.enableTrainerAutomation = false
            YippRouteDB.rxpTrainerWasOn = true
        end
    elseif YippRouteDB.rxpTrainerWasOn then
        p.enableTrainerAutomation = true
        YippRouteDB.rxpTrainerWasOn = nil
    end
end

-- One line of the trainer's list: name, rank, "available" / "unavailable" / "used". The game's
-- function returns (name, rank, category) on this client, (name, category, icon, ..., rank) on others.
local function Service(i)
    local name, a, b, _, r = GetTrainerServiceInfo(i)
    if type(b) == "number" then return name, r, a end
    return name, a, b
end
YR.TrainerService = Service   -- the trainer reminder (Reminders.lua) reads the costs with it

-- Your class's spells by name (asked at every trainer visit: made once per class).
local mine, mineOf
local function ClassSpells()
    local _, class = UnitClass("player")
    if mineOf ~= class then
        mine, mineOf = {}, class
        for _, e in ipairs((YR.TrainerSpells or {})[class or ""] or {}) do mine[e[3]] = true end
    end
    return mine
end

-- What to buy now, in order: [{ index, name, rank, cost }], what was left for want of gold, and the
-- names of what the trainer offers that is not one of your class's spells (never bought).
function YR.TrainerPlan(money)
    local data = YR.TrainerData()
    local wants, other, class = {}, {}, ClassSpells()
    for i = 1, GetNumTrainerServices() or 0 do
        local name, rank, category = Service(i)
        if name and category == "available" and not class[name] then
            other[#other + 1] = name
        elseif name and category == "available" then
            local choice = YR.TrainerChoice(name)
            -- "Rank 2" and up is not the first rank; a spell without ranks is its own first
            local n = tonumber(tostring(rank or ""):match("%d+"))
            if choice == "first" then
                -- (the rank's text can be empty a moment after the window opens: a spell you already
                -- have any rank of is not its first rank, whatever the text says)
                local have = false
                if n == nil then
                    local _, class = UnitClass("player")
                    for _, e in ipairs((YR.TrainerSpells or {})[class] or {}) do
                        if e[3] == name and IsPlayerSpell and IsPlayerSpell(e[1]) then have = true break end
                    end
                end
                choice = (not have and (n == nil or n <= 1)) and "always" or "never"
            end
            -- (a price the game hasn't given yet is not a price of nothing: that line waits for the
            -- next visit, or it would be bought past the reserve)
            local cost = GetTrainerServiceCost(i)
            if choice ~= "never" and type(cost) == "number" then
                local level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0
                wants[#wants + 1] = { index = i, name = name, rank = rank, cost = cost, level = level,
                    always = choice == "always" }
            end
        end
    end
    table.sort(wants, function(x, y)
        if x.always ~= y.always then return x.always end
        if x.level ~= y.level then return x.level < y.level end
        return x.cost < y.cost
    end)
    local buy, short = {}, {}
    for _, w in ipairs(wants) do
        local floor = w.always and 0 or (data.reserve or 0)
        if money - w.cost >= floor then
            buy[#buy + 1] = w
            money = money - w.cost
        else
            short[#short + 1] = w
        end
    end
    return buy, short, other
end

local function Gold(c) return YR.Money(c) end

-- this character's own saved table (the one thing kept there: that it said yes)
local function Char() return type(YippSetupCharDB) == "table" and YippSetupCharDB or {} end

local Train
StaticPopupDialogs["HEADSTART_TRAIN_FIRST"] = {
    text = "%s", button1 = "Learn them", button2 = "Not now",
    OnAccept = function()
        Char().trainOK = true
        -- (planned again from what the trainer offers now: the window may have been shut meanwhile)
        C_Timer.After(0, function() Train(true) end)
    end,
    timeout = 0, whileDead = false, hideOnEscape = true, preferredIndex = 3,
}

function Train(agreed)
    if not YR.Option("autoTrain") or (IsShiftKeyDown() and not agreed) or not GetNumTrainerServices then return end
    if IsTradeskillTrainer and IsTradeskillTrainer() then return end
    -- a Hunter's pet trainer is a trainer too, with the pet's name on it
    local title = ClassTrainerFrame and ClassTrainerFrame.TitleContainer and ClassTrainerFrame.TitleContainer.TitleText
    if title and UnitName("pet") and title:GetText() == UnitName("pet") then return end
    if SetTrainerServiceTypeFilter and GetTrainerServiceTypeFilter and not GetTrainerServiceTypeFilter("available") then
        SetTrainerServiceTypeFilter("available", 1)
    end
    local buy, short, other = YR.TrainerPlan(GetMoney())
    -- the first time on this character: asked, with what it would cost and what is kept
    if #buy > 0 and not agreed and not Char().trainOK then
        local cost = 0
        for _, w in ipairs(buy) do cost = cost + w.cost end
        StaticPopup_Show("HEADSTART_TRAIN_FIRST", ("Headstart: learn %d %s here for %s?\n\nThe class trainer is switched on for every character of this account. It learns your class's spells as the trainer opens and keeps %s; what to learn and how much to keep are set per class in Headstart's settings (Trainer). It asks only this once on this character."):format(
            #buy, #buy == 1 and "spell" or "spells", Gold(cost), Gold(YR.TrainerData().reserve or 0)))
        return
    end
    -- bought from the bottom of the list up: a line learned leaves the list and moves the ones below it
    local order = {}
    for _, w in ipairs(buy) do order[#order + 1] = w end
    table.sort(order, function(x, y) return x.index > y.index end)
    local spent = 0
    for _, w in ipairs(order) do
        BuyTrainerService(w.index)
        spent = spent + w.cost
    end
    if #buy > 0 or #short > 0 then
        local names = {}
        for _, w in ipairs(buy) do names[#names + 1] = w.name .. (w.rank and w.rank ~= "" and " (" .. w.rank .. ")" or "") end
        local msg = #buy > 0 and ("learned %s for %s."):format(table.concat(names, ", "), Gold(spent)) or "learned nothing."
        if #short > 0 then
            local left = {}
            for _, w in ipairs(short) do left[#left + 1] = w.name end
            msg = msg .. (" Left for now (your reserve): %s."):format(table.concat(left, ", "))
        end
        YR.Print(msg)
    elseif #other > 0 then
        -- a weapon master, a riding trainer: nothing here is bought by itself, and it is said why
        YR.Print("nothing here is one of your class's spells, so nothing is learned by itself: that is yours to buy.")
    end
end

-- The trainer's window is listened for only while this is on. Coming on (the login, or the setting)
-- switches RestedXP's own off; and whenever the settings are looked at with ours off and RestedXP's
-- still switched off by us, RestedXP gets it back.
local function Wanted()
    local on = YR.Option("autoTrain")
    if not on and YippRouteDB.rxpTrainerWasOn then YR:SyncRxpTrainer() end
    return on
end

YR.Part(Wanted, { "TRAINER_SHOW" }, function()
    -- the list fills a moment after the window opens
    C_Timer.After(0.2, Train)
end, { start = function() YR:SyncRxpTrainer() end })
