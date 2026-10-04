-- Bank: crafting mats and recipes you can't use yet go to the bank by themselves.
-- When the bank opens (and with the button on the bank window) the bags are walked, and every stack
-- the settings pick is right-clicked into the bank, one at a time: with the bank open that is what a
-- right-click does. Hold Shift as the bank opens to keep everything.
--
--   What goes (account options in YippRouteDB, Settings, QoL):
--     bankAuto     on unless turned off: when the bank opens
--     bankButton   on unless turned off: a button on the bank window does the same at any time
--     bankMats     "mine" (default) | "all" | "off": crafting mats - "mine" keeps whatever a
--                  profession you have crafts with, and banks the rest
--     bankRecipes  on unless turned off: recipes for a profession you haven't got, or that need
--                  more skill than you have (one you already know is left for the vendor)
--   What never goes: quest items, anything the route still needs (Needs.lua), and what another
--   YippYapp addon says to keep - AutoFeed's food and water, and with "mine", Skillwright's reagents.
--
-- Which profession crafts with what, and what a recipe needs to learn, comes from Data/Crafting.lua.
local ADDON, YR = ...

local TRADE_GOODS, RECIPE, QUEST = 7, 9, 12    -- item classes
-- Besides trade goods, a crafting reagent counts as mats only in these classes: Reagent and
-- Miscellaneous. An apple is a cooking reagent too, but it is food first - and gear, potions and
-- the rest are things you use, whatever recipe also takes them.
local REAGENT_CLASS = { [5] = true, [15] = true }
-- Trade goods you use rather than craft with: dynamite, target dummies. Never banked as mats.
local IN_USE = { [2] = true, [3] = true }      -- Explosives, Devices
local STEP = 0.15                              -- seconds between two moves: one stack per tick
local TRIES = 4                                -- ticks a stack may sit unmoved before the bank is full

local bankOpen = false
local run                                      -- the deposit in progress, or nil
local button

-- ---------------------------------------------------------------------------
-- What goes
-- ---------------------------------------------------------------------------
--- The bank-mats setting, read the same way everywhere: anything unknown is the default.
function YR.BankMats()
    local v = YippRouteDB and YippRouteDB.bankMats
    if v == "all" or v == "off" then return v end
    return "mine"
end

--- This character's professions: [skill line] = rank. Asked per skill line, like Skillwright:
--- walking the skill list by index misses lines under a collapsed header.
local function Professions()
    local have = {}
    if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID) then return have end
    for _, line in ipairs(YR.Crafting.professions) do
        local ok, s = pcall(C_SkillInfo.GetSkillLineInfoByID, line)
        if ok and type(s) == "table" and not s.isHeader and (s.rank or 0) > 0 then have[line] = s.rank end
    end
    return have
end

--- What another YippYapp addon published, through LibForever if anything loaded it. Headstart
--- doesn't carry the library itself, so with no other YippYapp addon there is simply nobody to ask.
local function Provider(name)
    local lib = LibStub and LibStub("LibForever-1.0", true)
    local data = lib and lib.GetData and lib.GetData(name)
    return type(data) == "table" and type(data.Keep) == "function" and data or nil
end

--- A reason another addon gives for keeping the item, or nil. A provider that errors keeps it.
local function KeptBy(name, item)
    local data = Provider(name)
    if not data then return nil end
    local ok, reason = pcall(data.Keep, item)
    if not ok then return true end
    return (reason == true or (type(reason) == "string" and reason ~= "")) or nil
end

local function Known(spell)
    if not spell then return false end
    if IsPlayerSpell then
        local ok, yes = pcall(IsPlayerSpell, spell)
        if ok and yes then return true end
    end
    return false
end

--- Why this item goes to the bank ("mats" or "recipes"), or nil to keep it in the bags.
--- `have` is Professions(), passed in so one walk of the bags asks the game once.
--- The rule itself, shared with the mail to your alt (Mail.lua): `mats` is "mine" | "all" | "off",
--- `recipes` true to send recipes you can't learn yet.
function YR.StashReason(item, have, mats, recipes)
    if not item then return nil end
    local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(item)
    if not class or class == QUEST then return nil end
    if YR.RouteNeed and YR.RouteNeed(item) then return nil end
    if KeptBy("AutoFeedConsumables", item) then return nil end
    local C = YR.Crafting

    local recipe = C.recipeItems[item]
    if class == RECIPE or recipe then
        if not recipes or not recipe then return nil end                    -- a recipe we know nothing of stays
        local line, skill, spell = recipe[1], recipe[2], recipe[3]
        if Known(spell) then return nil end
        local rank = have[line]
        if not rank or rank < (skill or 0) then return "recipes" end
        return nil                                                          -- you can learn it now: keep it
    end

    local mode = mats
    local users = C.reagents[item]
    if mode == "off" or not (class == TRADE_GOODS or (users and REAGENT_CLASS[class])) then return nil end
    if class == TRADE_GOODS and IN_USE[subclass] then return nil end
    if mode == "mine" then
        for _, line in ipairs(users or {}) do
            if have[line] then return nil end
        end
        if KeptBy("SkillwrightReagents", item) then return nil end
    end
    return "mats"
end

function YR.BankReason(item, have)
    return YR.StashReason(item, have, YR.BankMats(), YR.Option("bankRecipes"))
end

--- This character's professions, for StashReason.
function YR.Professions() return Professions() end

-- ---------------------------------------------------------------------------
-- Moving it
-- ---------------------------------------------------------------------------
local function Bags()
    local last = NUM_BAG_SLOTS or 4
    local list = {}
    for bag = 0, last do list[#list + 1] = bag end
    -- The reagent bag, where the client has one.
    if C_Container.GetContainerNumSlots(last + 1) > 0 then list[#list + 1] = last + 1 end
    return list
end

local function Slot(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if type(info) ~= "table" then return nil end
    return info.itemID, info.stackCount or 1, info.isLocked
end

--- Everything that goes, as a list of stacks in bag order.
local function Pick()
    local have, list = Professions(), {}
    for _, bag in ipairs(Bags()) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local item, count = Slot(bag, slot)
            local why = item and YR.BankReason(item, have)
            if why then list[#list + 1] = { bag = bag, slot = slot, item = item, count = count, why = why } end
        end
    end
    return list
end

local function Plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

local function Finish(note)
    local r = run
    run = nil
    if not r then return end
    if r.ticker then r.ticker:Cancel() end
    local parts = {}
    if r.moved.mats > 0 then parts[#parts + 1] = Plural(r.moved.mats, "stack of crafting mats", "stacks of crafting mats") end
    if r.moved.recipes > 0 then parts[#parts + 1] = Plural(r.moved.recipes, "recipe", "recipes") end
    if #parts > 0 then
        YR.Print("banked " .. table.concat(parts, " and ") .. (note and (" - " .. note) or "."))
    elseif note and r.loud then
        YR.Print(note)
    end
end

local function Step()
    local r = run
    if not r then return end
    if not bankOpen then return Finish("the bank closed before the rest went") end
    if InCombatLockdown() then return Finish("stopped for combat") end
    local s = r.list[r.i]
    if not s then return Finish() end
    local item, _, locked = Slot(s.bag, s.slot)
    if item ~= s.item then
        -- Gone from the slot: moved by our last click, or by the player. Either way, next.
        if s.clicked then r.moved[s.why] = r.moved[s.why] + 1 end
        r.i = r.i + 1
        return
    end
    if locked then return end                                 -- on its way; look again next tick
    if s.clicked then
        s.tries = (s.tries or 0) + 1
        if s.tries >= TRIES then return Finish("the bank is full") end
        return
    end
    -- the game's own word that the banker is still open: with it gone, this click would use the item
    local pim = C_PlayerInteractionManager
    if pim and pim.IsInteractingWithNpcOfType and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
        and not pim.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.Banker) then
        return Finish("the bank closed before the rest went")
    end
    s.clicked = true
    C_Container.UseContainerItem(s.bag, s.slot)
end

--- Walk the bags and bank what the settings pick. `loud`: say so when there was nothing to move
--- (the button), rather than staying quiet (opening the bank).
function YR.DepositToBank(loud)
    if run or not bankOpen then return end
    if InCombatLockdown() then
        if loud then YR.Print("not in combat.") end
        return
    end
    local list = Pick()
    if #list == 0 then
        if loud then YR.Print("nothing to bank: no crafting mats or recipes your settings send there.") end
        return
    end
    run = { list = list, i = 1, moved = { mats = 0, recipes = 0 }, loud = loud }
    run.ticker = C_Timer.NewTicker(STEP, Step)
end

-- ---------------------------------------------------------------------------
-- The bank window
-- ---------------------------------------------------------------------------
local function Button()
    if button or not BankFrame then return button end
    button = CreateFrame("Button", "HeadstartBankButton", BankFrame, "UIPanelButtonTemplate")
    button:SetSize(110, 22)
    button:SetText("Bank mats")
    button:SetPoint("TOPRIGHT", BankFrame, "BOTTOMRIGHT", 0, -2)
    button:SetScript("OnClick", function() YR.DepositToBank(true) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Headstart: bank mats")
        local mats = YR.BankMats()
        GameTooltip:AddLine(mats == "all" and "Crafting mats: all of them." or mats == "mine"
            and "Crafting mats no profession of yours crafts with." or "Crafting mats: off.", 1, 1, 1, true)
        GameTooltip:AddLine(YR.Option("bankRecipes") and "Recipes you can't learn yet." or "Recipes: off.", 1, 1, 1, true)
        GameTooltip:AddLine("Quest items, what the route still needs and AutoFeed's food stay. Settings, QoL.",
            0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function Opened()
    if bankOpen then return end
    bankOpen = true
    local b = Button()
    if b then b:SetShown(YR.Option("bankButton")) end
    -- Shift as the bank opens: keep everything this time. Read now, not later: by the first tick
    -- the key may be up.
    if YR.Option("bankAuto") and not IsShiftKeyDown() then
        -- A moment for the bank's own slots to arrive, so a full bank is seen as full.
        C_Timer.After(0.3, function() YR.DepositToBank(false) end)
    end
end

local function Closed()
    bankOpen = false
    if run then Finish("the bank closed before the rest went") end
end

--- The bank window button on or off (Settings, QoL).
function YR.SetBankButton(on)
    YippRouteDB.bankButton = on and true or false
    if button then button:SetShown(on and bankOpen) end
end

function YR.StartBank()
    local f = CreateFrame("Frame")
    -- The bank's own events and the newer interaction events: both, because which ones this
    -- client sends is not something to bet on, and Opened/Closed ignore a second telling.
    -- RegisterEvent errors on an event the client doesn't know, hence the pcall.
    for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
        "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
        pcall(f.RegisterEvent, f, e)
    end
    local BANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
    f:SetScript("OnEvent", function(_, event, kind)
        if event == "BANKFRAME_OPENED" then Opened()
        elseif event == "BANKFRAME_CLOSED" then Closed()
        elseif BANKER and kind == BANKER then
            if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then Opened() else Closed() end
        end
    end)
end

function YR.BankIsOpen() return bankOpen end
