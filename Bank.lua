-- Bank: crafting mats and recipes you can't use yet put in the bank on a click.
-- The Deposit button on the bank window walks the bags, and every stack the settings pick is
-- right-clicked into the bank, one at a time: with the bank open that is what a right-click does.
-- Nothing goes by itself as the bank opens (the owner, 2026-10-20: "instead of it sending everything
-- to the bank by itself, let it be a deposit button - now I can't open and close the bank and open it
-- again if I take things out, it always goes back in"). A stack is clicked only once nothing in the
-- bags is still on its way and nothing is on the cursor: a click into a move under way left an item
-- locked until a relog ("stuck on item is locked").
--
--   What goes (account options in YippRouteDB, Settings, QoL):
--     bankButton   off until turned on: the Deposit button (and /headstart bank at any open bank)
--     (bankAuto - depositing as the bank opened - is gone; one saved is not read)
--     bankMats     "mine" (default) | "all" | "off": crafting mats - "mine" keeps whatever a
--                  profession you have crafts with, and banks the rest
--     bankRecipes  on unless turned off: recipes for a profession you haven't got, or that need
--                  more skill than you have (one you already know is left for the vendor)
--   What never goes: quest items, anything a quest you'd still do needs (the route's, Needs.lua, or
--   RestedXP's; not a quest that's done or grey for your level), and what another
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
local STEP = 0.25                              -- seconds between two moves: one stack per tick
local TRIES = 4                                -- ticks a stack may sit unmoved before the bank is full
local WAIT = 40                                -- ticks to wait for the bags or the cursor before giving up

local bankOpen = false
local run                                      -- the deposit in progress, or nil
local button
local part                                     -- what listens for the bank (YR.StartBank)
local asked                                    -- a deposit asked for by hand while nothing listened

-- Blizzard's bank window on screen now (for when nobody was listening as it opened).
local function Showing()
    return BankFrame and BankFrame.IsShown and BankFrame:IsShown() and true or false
end

-- ---------------------------------------------------------------------------
-- What goes
-- ---------------------------------------------------------------------------
--- The bank-mats setting, read the same way everywhere: anything unknown is the default.
function YR.BankMats()
    local v = YippRouteDB and YippRouteDB.bankMats
    if v == "all" or v == "off" then return v end
    return "mine"
end

--- A recipe item's number (Data/Crafting.lua) taken apart: profession line, skill to learn it, its spell.
function YR.CraftRecipe(packed)
    return packed % 1000, math.floor(packed / 1000) % 1000, math.floor(packed / 1000000)
end

--- Whether one of the professions that use a reagent (its bits, Data/Crafting.lua) is among `have`
--- ([skill line] = rank): bit i stands for the i-th of YR.Crafting.professions.
function YR.CraftUsers(bits, have)
    local lines = YR.Crafting.professions
    for i = 1, #lines do
        if bits % 2 == 1 and have[lines[i]] then return true end
        bits = math.floor(bits / 2)
        if bits == 0 then return false end
    end
    return false
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
--- Is this quest one you'd still do? Yes while it's in your log. No once it's done, and no when it has
--- gone grey for your level (a quest from zones behind you: nobody keeps linen for it). A quest the
--- game can't tell the level of counts as live.
function YR.QuestLive(quest)
    if type(quest) ~= "number" then return true end
    if C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(quest) then return true end
    if C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(quest) then return false end
    local level = C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(quest)
    local range = type(_G.UnitQuestTrivialLevelRange) == "function" and _G.UnitQuestTrivialLevelRange("player")
    local mine = UnitLevel("player")
    if type(level) ~= "number" or level <= 0 or type(range) ~= "number" or type(mine) ~= "number" then return true end
    return mine - level <= range
end

--- Needed for a quest you'd still do (YR.QuestLive): one of our route's steps needs it, or RestedXP's
--- guides use it (what its tooltip calls "Item used in guide"). Such an item never leaves your bags -
--- not to the bank, not in the mail, whatever list it's on.
function YR.QuestNeeds(item)
    if not item then return false end
    if YR.RouteNeed and YR.RouteNeed(item, YR.QuestLive) then return true end
    local rxp = type(RXP) == "table" and RXP or nil
    local ok, quest = pcall(function() return rxp and rxp.questItemList and rxp.questItemList[item] end)
    if not ok then return true end
    return quest ~= nil and quest ~= false and YR.QuestLive(tonumber(quest))
end

function YR.StashReason(item, have, mats, recipes)
    if not item then return nil end
    local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(item)
    if not class or class == QUEST then return nil end
    if YR.QuestNeeds(item) then return nil end
    if KeptBy("AutoFeedConsumables", item) then return nil end
    local C = YR.Crafting

    local recipe = C.recipeItems[item]
    if class == RECIPE or recipe then
        if not recipes or not recipe then return nil end                    -- a recipe we know nothing of stays
        local line, skill, spell = YR.CraftRecipe(recipe)
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
        if users and YR.CraftUsers(users, have) then return nil end
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

-- Whether anything in the bags is still on its way somewhere (ours, or one you moved), or on the cursor.
local function Busy()
    if (CursorHasItem and CursorHasItem()) or (GetCursorInfo and GetCursorInfo() ~= nil) then return "cursor" end
    for _, bag in ipairs(Bags()) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local item, _, locked = Slot(bag, slot)
            if item and locked then return "locked" end
        end
    end
    return nil
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
    if locked then
        -- on its way; look again next tick - but not for ever, if it never lets go
        s.locked = (s.locked or 0) + 1
        if s.locked >= 40 then return Finish("an item stayed locked") end
        return
    end
    if s.clicked then
        s.tries = (s.tries or 0) + 1
        if s.tries >= TRIES then return Finish("the bank is full") end
        return
    end
    -- the last move, or one of yours, not done yet - or an item on the cursor: wait for it
    local busy = Busy()
    if busy then
        r.waited = (r.waited or 0) + 1
        if r.waited >= WAIT then
            return Finish(busy == "cursor" and "stopped: an item stayed on the cursor" or "stopped: an item stayed locked")
        end
        return
    end
    r.waited = 0
    -- the bank window still open, looked at right before the click: with it gone, the click would use
    -- the item. (Not the interaction manager's "Banker": on Forever the bank opens without it - seen in
    -- game - and that check stopped every move.)
    if BankFrame and BankFrame.IsShown and not BankFrame:IsShown() then
        return Finish("the bank closed before the rest went")
    end
    s.clicked = true
    C_Container.UseContainerItem(s.bag, s.slot)
end

--- Walk the bags and bank what the settings pick. `loud`: say so when there was nothing to move
--- (the button), rather than staying quiet (opening the bank).
function YR.DepositToBank(loud)
    -- asked for by hand (/headstart bank) with the button and the automation both off, at an open bank:
    -- the bank is listened for from here until it closes
    if not bankOpen and not run and part and not part.on and Showing() then
        asked = true
        YR.ApplyParts()
    end
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
    button:SetText("Deposit")
    button:SetPoint("TOPRIGHT", BankFrame, "BOTTOMRIGHT", 0, -2)
    button:SetScript("OnClick", function() YR.DepositToBank(true) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Headstart: deposit")
        local mats = YR.BankMats()
        GameTooltip:AddLine(mats == "all" and "Crafting mats: all of them." or mats == "mine"
            and "Crafting mats no profession of yours crafts with." or "Crafting mats: off.", 1, 1, 1, true)
        GameTooltip:AddLine(YR.Option("bankRecipes") and "Recipes you can't learn yet." or "Recipes: off.", 1, 1, 1, true)
        GameTooltip:AddLine("Quest items, what a quest you'd still do needs and AutoFeed's food stay. Headstart, QoL, Bank & mail.",
            0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

-- A bag addon that draws its own bank (Baganator, EllesmereUI Bags) keeps Blizzard's bank
-- window out of sight, and our button with it. Then the button stands by itself at the top
-- of the screen while the bank is open. Looked at a moment on: Blizzard shows its window
-- just after it says the bank opened.
local function Stand()
    local b = button
    if not b or not bankOpen then return end
    local own = BankFrame and BankFrame.IsVisible and BankFrame:IsVisible()
    b:SetParent(own and BankFrame or UIParent)
    b:ClearAllPoints()
    if own then
        b:SetPoint("TOPRIGHT", BankFrame, "BOTTOMRIGHT", 0, -2)
    else
        b:SetPoint("TOP", UIParent, "TOP", 0, -140)
        b:SetFrameStrata("HIGH")
    end
    b:SetShown(YR.Option("bankButton"))
end
-- The bank opened: the button. Nothing is sent off by itself.
local function Opened()
    if bankOpen then return end
    bankOpen = true
    local b = Button()
    if b then
        b:SetShown(YR.Option("bankButton"))
        C_Timer.After(0.2, Stand)
    end
end

local function Closed()
    bankOpen = false
    if button and button:GetParent() == UIParent then button:Hide() end      -- standing by itself: gone with the bank
    if run then Finish("the bank closed before the rest went") end
    if asked then
        asked = nil
        YR.SettingChanged()
    end
end

--- The bank window button on or off (Settings, QoL).
function YR.SetBankButton(on)
    YippRouteDB.bankButton = on and true or false
    if button then button:SetShown(on and bankOpen) end
    YR.SettingChanged()
end

-- The bank is listened for only while its button is on (or a deposit was asked for by hand, until that
-- bank closes).
local function Wanted() return asked or YR.Option("bankButton") or false end

local BANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
local function OnEvent(_, event, kind)
    if event == "BANKFRAME_OPENED" then Opened()
    elseif event == "BANKFRAME_CLOSED" then Closed()
    elseif BANKER and kind == BANKER then
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then Opened() else Closed() end
    end
end

function YR.StartBank()
    if part then return end
    -- The bank's own events and the newer interaction events: both, because which ones this
    -- client sends is not something to bet on, and Opened/Closed ignore a second telling.
    -- (An event the client doesn't know is passed over: YR.Part registers through pcall.)
    part = YR.Part(Wanted, { "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
        "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }, OnEvent, {
        -- turned on at an open bank: the button is there at once
        start = function() if Showing() then Opened() end end,
        -- the button follows its own switch while the bank stays listened for
        again = function() if button and bankOpen then button:SetShown(YR.Option("bankButton")) end end,
        stop = function()
            Closed()
            if button then button:Hide() end
        end,
    })
end

function YR.BankIsOpen() return bankOpen end
