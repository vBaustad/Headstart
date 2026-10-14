-- Auto trainer: at your class trainer, the spells you chose are learned as the window opens.
-- Per class (YippRouteDB.trainer[CLASS]): for each spell (all its ranks) Always, If I can afford it,
-- First rank only (the spell itself is learned, like Always; no rank after the first is - for a spell
-- you start with, that is nothing) or Never; and what you keep: "If I can afford it" spells are only
-- bought while you'd keep a share of the money you came with and the sum you save (YR.TrainerKeep),
-- and what they left is a button under the trainer's window; "Always" spells whenever the gold is
-- there. And a level: spells taught above it are left for you (upTo).
-- Defaults (data version 2, 2026-10-02): "If I can afford it" and half your money kept (a 2 silver
-- reserve until 0.10.0-beta7), so a new character never trains itself down to nothing. A class's table from before keeps what it had -
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
--   It does not ask. On is on: for a while (0.10.0-beta6 as first tagged) it asked the first time on
--   each character, with the cost, and the user met that at his own trainer (2026-10-13): "hvis det er
--   på, så er det på, skal ikke få melding her når jeg prøver å trene". It starts off, is turned on by
--   you, and says in chat what it learned and for how much. Don't put a question back.
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
        d = { spells = {}, v = 2 }
        YippRouteDB.trainer[class] = d
    end
    return d
end

-- What it costs to repair everything you wear from broken, in copper: each item's durability at the
-- game's price for its kind, item level and quality (Data/RepairCosts.lua: the game's own tables).
-- A reputation discount is not counted: it is the most you would pay. It grows with your gear by
-- itself - about 11 silver in level 10 greens, 90 silver at 40, 3 gold at 60.
-- (lost: only the points lost now, what a vendor would ask today - for /headstart repair)
local function RepairCost(lost)
    local t = YR.RepairCosts
    if not t or not GetInventoryItemDurability then return 0 end
    local total = 0
    for slot = 1, 19 do
        local cur, max = GetInventoryItemDurability(slot)
        local link = max and max > 0 and GetInventoryItemLink("player", slot)
        if link then
            local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
            local list = t[classID == 2 and t.weapon[subclassID] or classID == 4 and t.armor[subclassID] or 0]
            local level = C_Item.GetDetailedItemLevelInfo(link)
            local factor = t.quality[GetInventoryItemQuality("player", slot) or 2]
            if list and level and factor then
                local points = lost and max - (cur or max) or max
                total = total + math.floor(points * list[math.min(math.max(math.floor(level), 1), #list)] * factor)
            end
        end
    end
    return total
end
function YR.RepairAllCost() return RepairCost(false) end

--- /headstart repair: the full repair counted, and at a vendor what it asks for today's wear beside
--- what Headstart counts for the same (they should agree, but for a reputation discount).
function YR.RepairDebug()
    local asks, can = GetRepairAllCost()
    YR.Print(("a full repair of what you wear: %s. Worn now, Headstart counts %s%s."):format(YR.Money(RepairCost(false)),
        YR.Money(RepairCost(true)), can and ("; this vendor asks " .. YR.Money(asks)) or " (at a vendor that repairs, it says what that one asks)"))
end

-- What "If I can afford it" spells leave you: a share of the money you came to the trainer with (half
-- unless set), never less than a full repair of your gear - so it grows with you, and there is gold
-- left for everything else - and on top a sum you save for something: the weapon you mean to buy at 7,
-- your mount. Whatever was left for that money is one click away on the trainer's window (Bar).
-- It was one fixed sum, 2 silver at level 5 and at level 50 alike ("at 50 you want to keep more than 2
-- silver"); a sum per level he had to work out himself, then a full repair alone, did not answer it
-- either ("you want gold left, and not only for repairs, for lots else ... I need money for a mace
-- around level 7" - the owner, 2026-10-14). A class that had a sum of its own (or none: the tables from
-- before v2) keeps exactly that: no share, the sum saved. The 2 silver every class started with is the
-- share now.
--- Percent of the money you came with that "If I can afford it" spells leave you (0: none).
function YR.TrainerShare(class)
    local d = YR.TrainerData(class)
    if d.share ~= nil then return tonumber(d.share) or 0 end
    local old = tonumber(d.reserve)
    return (old == nil or old == 200) and 50 or 0
end
--- Copper saved on top of the share.
function YR.TrainerSave(class)
    local d = YR.TrainerData(class)
    if d.save ~= nil then return tonumber(d.save) or 0 end
    local old = tonumber(d.reserve)
    return (old and old ~= 200) and old or 0
end
--- What "If I can afford it" spells leave you, in copper, when you come with `money`.
function YR.TrainerKeep(money, class)
    local share = YR.TrainerShare(class)
    local keep = share > 0 and math.max(math.floor((tonumber(money) or 0) * share / 100), YR.RepairAllCost()) or 0
    return keep + YR.TrainerSave(class)
end

--- "1g 20s", "75s", "2g 5c" or a bare number of gold ("1.5") in copper; 0 for nothing; nil for words
--- that aren't money.
function YR.ParseMoney(text)
    text = tostring(text or ""):lower():match("^%s*(.-)%s*$")
    if text == "" then return 0 end
    local bare = tonumber(text)
    if bare then return bare >= 0 and math.floor(bare * 10000 + 0.5) or nil end
    local total, any = 0, false
    for n, unit in text:gmatch("(%d+%.?%d*)%s*([gsc])") do
        total = total + math.floor(tonumber(n) * (unit == "g" and 10000 or unit == "s" and 100 or 1) + 0.5)
        any = true
    end
    local rest = text:gsub("%d+%.?%d*%s*[gsc]", ""):gsub("%s", "")
    if not any or rest ~= "" then return nil end
    return total
end
--- Copper as you would type it: "1g 20s", "75s", "0".
function YR.MoneyText(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. "g" end
    if s > 0 then out[#out + 1] = s .. "s" end
    if c > 0 then out[#out + 1] = c .. "c" end
    return #out > 0 and table.concat(out, " ") or "0"
end
--- Spells a trainer teaches above this level are left for you (60: every one).
function YR.TrainerUpTo(class)
    return tonumber(YR.TrainerData(class).upTo) or 60
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
-- all: nothing kept (the trainer window's button: you asked for them)
function YR.TrainerPlan(money, all)
    local upTo, keep = YR.TrainerUpTo(), all and 0 or YR.TrainerKeep(money)
    local wants, other, above, class = {}, {}, {}, ClassSpells()
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
            local level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 0
            if choice ~= "never" and type(level) == "number" and level > upTo then
                above[#above + 1] = name          -- (Train spells up to level: yours to buy)
            elseif choice ~= "never" and type(cost) == "number" then
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
        local floor = w.always and 0 or keep
        if money - w.cost >= floor then
            buy[#buy + 1] = w
            money = money - w.cost
        else
            short[#short + 1] = w
        end
    end
    return buy, short, other, above
end

local function Gold(c) return YR.Money(c) end

-- Learns `buy` (TrainerPlan's), from the bottom of the list up: a line learned leaves the list and moves
-- the ones below it. Returns what it cost and the names, with their ranks.
local function Learn(buy)
    local order = {}
    for _, w in ipairs(buy) do order[#order + 1] = w end
    table.sort(order, function(x, y) return x.index > y.index end)
    local spent, names = 0, {}
    for _, w in ipairs(order) do
        BuyTrainerService(w.index)
        spent = spent + w.cost
    end
    for _, w in ipairs(buy) do names[#names + 1] = w.name .. (w.rank and w.rank ~= "" and " (" .. w.rank .. ")" or "") end
    return spent, names
end

-- Under the trainer's window: what "If I can afford it" left for the money you keep, its price, and a
-- button that learns it now. The trainer can't know what your gold is for - you do: with the weapon
-- bought, one click. Made the first time something is left; it is the trainer window's (hidden with it).
local bar
local function Bar(short)
    if bar then bar:Hide() end
    local frame = ClassTrainerFrame
    if not frame or not short or #short == 0 then return end
    if not bar then
        local S = YR.Style
        bar = CreateFrame("Frame", nil, frame)
        bar:SetHeight(34)
        bar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
        bar:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -2)
        S.Fill(bar, S.C.window)
        S.Border(bar, S.C.line)
        bar.learn = S.Button(bar, "Learn them", function() YR.TrainerLearnLeft() end, "primary", 100)
        bar.learn:SetPoint("RIGHT", -6, 0)
        bar.text = S.Text(bar, 12, S.C.sub)
        bar.text:SetPoint("LEFT", 10, 0)
        bar.text:SetPoint("RIGHT", bar.learn, "LEFT", -8, 0)
        bar.text:SetJustifyH("LEFT")
        bar.text:SetWordWrap(false)
        bar:EnableMouse(true)
        bar:SetScript("OnEnter", function(self)
            S.Tip(self, "Headstart left these for the money you keep (Class trainer settings): " .. (self.names or "")
                .. ". Learn them buys them now, as far as your gold goes.")
        end)
        bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local cost, names = 0, {}
    for _, w in ipairs(short) do
        cost = cost + w.cost
        names[#names + 1] = w.name
    end
    bar.names = table.concat(names, ", ")
    bar.text:SetText(("Left for later: %s  |cff8a827a%s|r"):format(bar.names, Gold(cost)))
    bar:Show()
end

--- The trainer window's button: what was left for the money you keep, learned now, as far as your
--- gold goes - nothing kept, you asked.
function YR.TrainerLearnLeft()
    if bar then bar:Hide() end
    local buy, short = YR.TrainerPlan(GetMoney(), true)
    local msg = "learned nothing."
    if #buy > 0 then
        local spent, names = Learn(buy)
        msg = ("learned %s for %s."):format(table.concat(names, ", "), Gold(spent))
    end
    if #short > 0 then
        local left = {}
        for _, w in ipairs(short) do left[#left + 1] = w.name end
        msg = msg .. (" Not enough gold for: %s."):format(table.concat(left, ", "))
    end
    YR.Print(msg)
end

local function Train()
    if not YR.Option("autoTrain") or not GetNumTrainerServices then return end
    if IsTradeskillTrainer and IsTradeskillTrainer() then return end
    -- a Hunter's pet trainer is a trainer too, with the pet's name on it
    local title = ClassTrainerFrame and ClassTrainerFrame.TitleContainer and ClassTrainerFrame.TitleContainer.TitleText
    if title and UnitName("pet") and title:GetText() == UnitName("pet") then return end
    if SetTrainerServiceTypeFilter and GetTrainerServiceTypeFilter and not GetTrainerServiceTypeFilter("available") then
        SetTrainerServiceTypeFilter("available", 1)
    end
    local buy, short, other, above = YR.TrainerPlan(GetMoney())
    local spent, names = Learn(buy)
    Bar(short)
    if #buy > 0 or #short > 0 or #above > 0 then
        local msg = #buy > 0 and ("learned %s for %s."):format(table.concat(names, ", "), Gold(spent)) or "learned nothing."
        if #short > 0 then
            local left = {}
            for _, w in ipairs(short) do left[#left + 1] = w.name end
            msg = msg .. (" Left for the money you keep: %s (Learn them, under the trainer's window)."):format(table.concat(left, ", "))
        end
        if #above > 0 then
            msg = msg .. (" Yours to buy (above level %d): %s."):format(YR.TrainerUpTo(), table.concat(above, ", "))
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

YR.Part(Wanted, { "TRAINER_SHOW", "PLAYER_LOGOUT" }, function(_, event)
    -- Logging out (or a reload): RestedXP's own setting is given back before its settings are saved, and
    -- taken again at the next login - so with Headstart removed, RestedXP has its own setting as it was.
    if event == "PLAYER_LOGOUT" then
        local p = RxpProfile()
        if p and YippRouteDB.rxpTrainerWasOn then
            p.enableTrainerAutomation = true
            YippRouteDB.rxpTrainerWasOn = nil
        end
        return
    end
    Bar(nil)            -- (what the last trainer left is not this one's)
    -- Shift is read now, while the key is down for the click on the trainer: read a moment later, a
    -- key let go at once had not been held at all, and it does not ask - Shift is the one way to say no
    if IsShiftKeyDown() then return end
    -- the list fills a moment after the window opens
    C_Timer.After(0.2, Train)
end, { start = function() YR:SyncRxpTrainer() end, stop = function() Bar(nil) end })
