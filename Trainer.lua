-- Auto trainer: at your class trainer, the spells you chose are learned as the window opens.
-- Per class (YippRouteDB.trainer[CLASS]): for each spell (all its ranks) Always, If I can afford it,
-- or Never, and a reserve: "If I can afford it" spells are only bought while you'd keep at least that
-- much. Always first, then the rest, each lowest level first. Hold Shift as you open the trainer to do
-- it yourself. Account option autoTrain (Settings, Trainer). RestedXP's own trainer automation (it
-- buys everything on its list) is switched off while ours is on, and back on when ours goes off.
local _, YR = ...

YR.TRAINER_CHOICES = { { "always", "Always" }, { "gold", "If I can afford it" }, { "never", "Never" } }

function YR.TrainerData(class)
    YippRouteDB.trainer = YippRouteDB.trainer or {}
    if not class then
        local _, c = UnitClass("player")
        class = c or "WARRIOR"
    end
    local d = YippRouteDB.trainer[class]
    if not d then
        d = { reserve = 0, spells = {} }
        YippRouteDB.trainer[class] = d
    end
    return d
end

function YR.TrainerChoice(name, class)
    return YR.TrainerData(class).spells[name] or "always"
end

function YR.SetTrainerChoice(name, choice, class)
    YR.TrainerData(class).spells[name] = choice ~= "always" and choice or nil
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

-- What to buy now, in order: [{ index, name, rank, cost }], and what was left for want of gold.
function YR.TrainerPlan(money)
    local data = YR.TrainerData()
    local wants = {}
    for i = 1, GetNumTrainerServices() or 0 do
        local name, rank, category = Service(i)
        if name and category == "available" then
            local choice = YR.TrainerChoice(name)
            if choice ~= "never" then
                local cost = GetTrainerServiceCost(i) or 0
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
    return buy, short
end

local function Gold(c)
    return GetCoinTextureString and GetCoinTextureString(c) or (floor(c / 100) / 100 .. "g")
end

local function Train()
    if not YR.Option("autoTrain") or IsShiftKeyDown() or not GetNumTrainerServices then return end
    if IsTradeskillTrainer and IsTradeskillTrainer() then return end
    -- a Hunter's pet trainer is a trainer too, with the pet's name on it
    local title = ClassTrainerFrame and ClassTrainerFrame.TitleContainer and ClassTrainerFrame.TitleContainer.TitleText
    if title and UnitName("pet") and title:GetText() == UnitName("pet") then return end
    if SetTrainerServiceTypeFilter and GetTrainerServiceTypeFilter and not GetTrainerServiceTypeFilter("available") then
        SetTrainerServiceTypeFilter("available", 1)
    end
    local buy, short = YR.TrainerPlan(GetMoney())
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
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("TRAINER_SHOW")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        YR:SyncRxpTrainer()
    else
        -- the list fills a moment after the window opens
        C_Timer.After(0.2, Train)
    end
end)
