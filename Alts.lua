-- Characters: what your other characters carry, have banked and own - seen from the one you're on.
--   Each character's bags, bank, gold and currencies are noted as it plays, and any of them can be
--   looked at from any other:
--     Gold        hover the money in your bag: every character's gold and the sum (/headstart gold says
--                 it in chat).
--     Tooltips    an item's tooltip says which of your other characters has it: "Duplo: 4x, bank 12x".
--     The window  /headstart alts (a small button on your bag, a key, the minimap button's menu):
--                 your characters with level, gold and when last played; pick one for what it has -
--                 laid out as a bag is, icons with their count and their quality's colour, sorted
--                 into crafting materials, recipes, gear, consumables and the rest - and its
--                 currencies, or "All characters" to find who has a thing.
--   What is left out: what only that character can ever use isn't worth knowing from another -
--   soulbound items, quest items and the hearthstone are never noted. Food, drink and grey items
--   are noted but not shown (on tooltips or in the window) unless you ask for everything.
--   What is noted, and when: gold the moment it changes; your bags and currencies a few seconds after
--   the last change of them, however many came, and never in a fight; the bank while its window is
--   open. (Not at the logout: the game has let go of your bags and gold by then.) What one character
--   carries is a short list: item and count.
--   The account's bank (if the game has one) is kept as a character of its own, "Account bank".
--   Off (it starts so) nothing is noted, read or hooked. Turned off again, what was noted is kept
--   until you clear it.
--   Account options (YippRouteDB, Settings, QoL, Bank & mail): alts (off until you turn it on),
--   altsTooltip (on unless turned off), altsGold (the money tooltip; on unless turned off), altsAll
--   (food, drink and grey items shown too; off).
--   Saved: HeadstartAlts[character] = { name, realm, class, level, faction, money, seen, bags = {
--   [item] = count }, bank = { ... }, bankSeen, cur = { { id, name, qty, icon }, ... } }.
local ADDON, YR = ...

local ACCOUNT = "*account"      -- the account's bank, as a character of its own
local frame                     -- the part's frame, once on
local index                     -- [item] = { { key, bags, bank }, ... } of your other characters; nil: build again
local win
local Draw

function YR.AltsOn() return YR.Option("alts") end

local function DB()
    if type(_G.HeadstartAlts) ~= "table" then _G.HeadstartAlts = {} end
    return _G.HeadstartAlts
end
YR.AltsDB = DB

local function Me()
    local db, key = DB(), YR.CharKey()
    local c = db[key]
    if not c then c = { bags = {}, bank = {} } db[key] = c end
    return c, key
end

-- ---------------------------------------------------------------------------
-- Noting it
-- ---------------------------------------------------------------------------
-- An item's kind, as the game files it: its class and subclass (0 and 5 is food and drink, 12 a quest's).
local function Kind(item)
    if not (C_Item and C_Item.GetItemInfoInstant) then return nil end
    local _, _, _, _, _, class, sub = C_Item.GetItemInfoInstant(item)
    return class, sub
end
local HEARTHSTONE, QUEST_ITEM = 6948, 12

-- The items of some bags, as [item] = count. Not what is bound to the character, a quest's, or the hearthstone.
local function Read(bags, into)
    for k in pairs(into) do into[k] = nil end
    local any = false
    for _, bag in ipairs(bags) do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local item = C_Container.GetContainerItemID(bag, slot)
            if item and item ~= HEARTHSTONE then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if not (info and info.isBound) and Kind(item) ~= QUEST_ITEM then
                    into[item] = (into[item] or 0) + (info and info.stackCount or 1)
                end
            end
        end
        if slots > 0 then any = true end
    end
    return any
end

local function Bags(first, last)
    local out = {}
    for bag = first, last do out[#out + 1] = bag end
    return out
end
local CARRIED = Bags(0, 5)              -- the backpack, four bags, the reagent bag
local function Index(name, fallback)
    local e = Enum and Enum.BagIndex
    return e and e[name] or fallback
end
local function BankBags() return Bags(Index("CharacterBankTab_1", 6), Index("CharacterBankTab_9", 14)) end
local function AccountBags() return Bags(Index("AccountBankTab_1", 15), Index("AccountBankTab_5", 19)) end

--- This character as it is now: who, gold, bags, currencies. (The bank is noted while it is open.)
function YR.AltsNote()
    local c = Me()
    local name, realm = UnitFullName("player")
    local _, class = UnitClass("player")
    c.name, c.realm, c.class = name, realm or GetRealmName(), class
    c.level, c.faction = UnitLevel("player"), UnitFactionGroup("player")
    c.money, c.seen = GetMoney(), time()
    local now = {}
    if Read(CARRIED, now) then c.bags = now end         -- no bag at all to look in: what was noted stays
    c.cur = nil
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListInfo then
        local cur = {}
        for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
            local info = C_CurrencyInfo.GetCurrencyListInfo(i)
            if info and not info.isHeader and (info.quantity or 0) > 0 then
                cur[#cur + 1] = { id = info.currencyID, name = info.name, qty = info.quantity, icon = info.iconFileID }
            end
        end
        if #cur > 0 then c.cur = cur end
    end
end

--- The bank, while its window is open: this character's, and the account's.
function YR.AltsNoteBank()
    local c = Me()
    local mine = {}
    if Read(BankBags(), mine) then c.bank, c.bankSeen = mine, time() end
    local shared = {}
    if Read(AccountBags(), shared) and next(shared) then
        local db = DB()
        db[ACCOUNT] = db[ACCOUNT] or { name = "Account bank", bags = {} }
        db[ACCOUNT].bank, db[ACCOUNT].seen = shared, time()
    end
end

--- Forget a character (or, with no name, every one of them).
function YR.AltsForget(key)
    if key then DB()[key] = nil else _G.HeadstartAlts = {} end
    index = nil
    if Draw then Draw() end
end

-- ---------------------------------------------------------------------------
-- Reading it
-- ---------------------------------------------------------------------------
--- Your characters, the one played last first: { { key, name, class, level, money, seen, me }, ... }.
function YR.AltsList()
    local out, me = {}, YR.CharKey()
    for key, c in pairs(DB()) do
        if key ~= ACCOUNT then
            out[#out + 1] = { key = key, name = c.name or key, realm = c.realm, class = c.class, level = c.level or 0,
                money = (key == me and GetMoney()) or c.money or 0, seen = c.seen or 0, me = key == me }
        end
    end
    table.sort(out, function(a, b)
        if a.me ~= b.me then return a.me end
        if a.seen ~= b.seen then return a.seen > b.seen end
        return a.name < b.name
    end)
    return out
end

--- All your gold: the sum, and the list it is of.
function YR.AltsGold()
    local list, sum = YR.AltsList(), 0
    for _, c in ipairs(list) do sum = sum + c.money end
    table.sort(list, function(a, b) if a.money ~= b.money then return a.money > b.money end return a.name < b.name end)
    return sum, list
end

--- Who else has an item: { { key, bags, bank }, ... } of your other characters (and the account's bank), or nil.
function YR.AltsHave(item)
    if not index then
        index = {}
        local me = YR.CharKey()
        for key, c in pairs(DB()) do
            if key ~= me then
                for where, list in pairs({ bags = c.bags, bank = c.bank }) do
                    for id, count in pairs(list or {}) do
                        local who = index[id]
                        if not who then who = {} index[id] = who end
                        local e
                        for _, x in ipairs(who) do if x.key == key then e = x end end
                        if not e then e = { key = key, bags = 0, bank = 0 } who[#who + 1] = e end
                        e[where] = e[where] + count
                    end
                end
            end
        end
    end
    return index[item]
end

function YR.AltsCoins(c) return YR.Money(math.floor(c or 0)) end

local function Colour(class)
    local col = class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
    if col then return col.r, col.g, col.b end
    return 0.9, 0.9, 0.9
end
local function Named(key)
    local c = DB()[key] or {}
    local r, g, b = Colour(c.class)
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, c.name or key)
end
YR.AltsNamed = Named

--- Whether an item is worth showing: not food or drink, not grey - unless you asked for everything.
function YR.AltsUseful(item)
    if YippRouteDB.altsAll == true then return true end
    local class, sub = Kind(item)
    if class == 0 and sub == 5 then return false end
    local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(item)
    return quality ~= 0
end

-- An item's tooltip: who else has it.
local function OnTooltip(tooltip, data)
    if tooltip ~= GameTooltip or not data or not data.id then return end
    if not YR.AltsOn() or YippRouteDB.altsTooltip == false then return end
    local who = YR.AltsHave(data.id)
    if not who or not YR.AltsUseful(data.id) then return end
    for _, e in ipairs(who) do
        -- "Duplo: 4x", "Duplo: 4x, bank 12x", "Account bank: 20x"
        local what = e.bags > 0 and e.bank > 0 and ("%dx, bank %dx"):format(e.bags, e.bank)
            or e.bank > 0 and (e.key == ACCOUNT and ("%dx"):format(e.bank) or ("bank %dx"):format(e.bank)) or ("%dx"):format(e.bags)
        tooltip:AddLine(Named(e.key) .. ": " .. what, 0.75, 0.78, 0.82)
    end
end

-- The money in your bag, hovered: every character's gold.
-- more: a last grey line (the bag button says what a click does)
local function GoldTip(owner, more)
    if not YR.AltsOn() or (YippRouteDB.altsGold == false and not more) then return end
    local sum, list = YR.AltsGold()
    if #list == 0 and not more then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOPRIGHT")
    GameTooltip:AddLine("Your characters' gold")
    for _, c in ipairs(list) do
        local r, g, b = Colour(c.class)
        GameTooltip:AddDoubleLine(c.name .. (c.me and "  (you)" or ""), YR.AltsCoins(c.money), r, g, b, 1, 1, 1)
    end
    if #list > 1 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("In all", YR.AltsCoins(sum), 1, 0.82, 0, 1, 1, 1)
    else
        GameTooltip:AddLine("Your other characters are added as each of them logs in.", 0.5, 0.53, 0.58, true)
    end
    if more then GameTooltip:AddLine(more, 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end
local function GoldTipHide(self) if GameTooltip:GetOwner() == self then GameTooltip:Hide() end end

--- /headstart gold: the same in chat.
function YR.AltsGoldSay()
    local sum, list = YR.AltsGold()
    if #list == 0 then YR.Print("no characters recorded yet. Turn on Characters in /hs.") return end
    for _, c in ipairs(list) do YR.Print(("  %s: %s"):format(Named(c.key), YR.AltsCoins(c.money))) end
    YR.Print(("total: %s"):format(YR.AltsCoins(sum)))
end

-- The hooks (they can't be taken off again: each asks first whether Characters is on). Put on the
-- first time it is.
local hooked = false
local function Hook()
    if hooked then return end
    hooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltip)
    end
    -- the coins in the bag are three small buttons: the mouse is over one of them, not the frame
    for _, name in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1" }) do
        local bag = _G[name]
        local money = type(bag) == "table" and bag.MoneyFrame
        if type(money) == "table" then
            for _, part in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
                local b = money[part]
                if type(b) == "table" and b.HookScript then
                    b:HookScript("OnEnter", function(self) GoldTip(self) end)
                    b:HookScript("OnLeave", GoldTipHide)
                end
            end
        end
    end
end

-- A small button on your bag, left of its coins: the window, in one click.
local bagButtons = {}
local function BagButtons()
    for _, name in ipairs({ "ContainerFrameCombinedBags", "ContainerFrame1" }) do
        local bag = _G[name]
        local money = type(bag) == "table" and bag.MoneyFrame
        if type(money) == "table" and not bagButtons[name] and bag.GetObjectType then
            -- A small round mark at the left end of the money bar, quiet until the mouse is on it: it
            -- reads as part of the bar, not as an item's icon dropped on the bag.
            local b = CreateFrame("Button", nil, bag)
            b:SetSize(14, 14)
            b:SetPoint("LEFT", money, "LEFT", 7, 0)
            b:SetFrameLevel((bag:GetFrameLevel() or 1) + 5)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetAllPoints()
            b.icon:SetTexture(133785)
            b.icon:SetTexCoord(0.10, 0.90, 0.10, 0.90)
            if b.CreateMaskTexture and b.icon.AddMaskTexture then
                local mask = b:CreateMaskTexture()
                mask:SetAllPoints(b.icon)
                mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                b.icon:AddMaskTexture(mask)
            end
            b:SetAlpha(0.65)
            b:SetScript("OnClick", function() YR.AltsToggle() end)
            -- the mark is where the gold is read: every character's, the total, and what a click does
            b:SetScript("OnEnter", function(self)
                self:SetAlpha(1)
                GoldTip(self, "Click: bags and bank of your other characters")
            end)
            b:SetScript("OnLeave", function(self) self:SetAlpha(0.65) GameTooltip:Hide() end)
            bagButtons[name] = b
        end
    end
    local show = YR.AltsOn() and YippRouteDB.altsBagButton ~= false
    for _, b in pairs(bagButtons) do b:SetShown(show) end
end
YR.AltsBagButtons = BagButtons

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
local W, H, LEFT, ROW = 760, 520, 230, 24
local CELL, GAP = 36, 5
local COLS = math.floor((W - LEFT - 56) / (CELL + GAP))
local CATS = { "Crafting materials", "Recipes", "Gear", "Consumables", "Other" }
local cells, heads = {}, {}
local picked = "*all"           -- the character shown ("*all": every one)
local view = "items"            -- "items" or "cur"
local search = ""
local SHOWN = 400
local chars, lines = {}, {}

local function Ago(t)
    local s = time() - (t or 0)
    if s < 3600 then return "just now" end
    if s < 86400 then return ("%d h ago"):format(s / 3600) end
    return ("%d d ago"):format(s / 86400)
end

local function Cat(item)
    local class = Kind(item)
    if class == 7 or class == 5 then return 1 end
    if class == 9 then return 2 end
    if class == 2 or class == 4 then return 3 end
    if class == 0 then return 4 end
    return 5
end

--- What the window shows: { { item, name, bags, bank, who, cat (1-5, see CATS), quality }, ... } of one
--- character or all - by kind, the finest first, then the most of. Food, drink and grey items only
--- when you asked for everything.
function YR.AltsItems(key, words)
    local sums = {}
    for k, c in pairs(DB()) do
        if key == "*all" or key == k then
            for where, list in pairs({ bags = c.bags, bank = c.bank }) do
                for id, count in pairs(list or {}) do
                    local e = sums[id]
                    if not e then e = { item = id, bags = 0, bank = 0, who = {} } sums[id] = e end
                    e[where] = e[where] + count
                    e.who[k] = (e.who[k] or 0) + count
                end
            end
        end
    end
    words = words and words ~= "" and words:lower() or nil
    local out = {}
    for id, e in pairs(sums) do
        if YR.AltsUseful(id) then
            e.name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
            if not e.name and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
            e.cat = Cat(id)
            e.quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id) or 1
            if not words or (e.name and e.name:lower():find(words, 1, true)) then out[#out + 1] = e end
        end
    end
    table.sort(out, function(a, b)
        if a.cat ~= b.cat then return a.cat < b.cat end
        if a.quality ~= b.quality then return a.quality > b.quality end
        local x, y = a.bags + a.bank, b.bags + b.bank
        if x ~= y then return x > y end
        return a.item < b.item
    end)
    return out
end

local function Quality(q)
    local col = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[q or 1]
    if col then return col.r, col.g, col.b end
    return 1, 1, 1
end

-- An item as a bag shows it: its icon, a frame in its quality's colour, how many.
local function Cell(i)
    local c = cells[i]
    if c then return c end
    local S = YR.Style
    c = CreateFrame("Button", nil, win.right.content)
    c:SetSize(CELL, CELL)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 1, -1)
    c.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.edge = S.Border(c, S.C.line)
    c.count = S.Text(c, 11)
    c.count:SetFont(S.FONT, 11, "OUTLINE")
    c.count:SetPoint("BOTTOMRIGHT", -2, 2)
    c:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    c:SetScript("OnEnter", function(self)
        local e = self.e
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. e.item)
        -- who has it, of the ones shown (the tooltip itself names your other characters; this is all of them)
        GameTooltip:AddLine(" ")
        local keys = {}
        for k in pairs(e.who) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local of = DB()[k] or {}
            local bags, bank = of.bags and of.bags[e.item] or 0, of.bank and of.bank[e.item] or 0
            GameTooltip:AddDoubleLine(Named(k), bags > 0 and bank > 0 and ("%dx, bank %dx"):format(bags, bank)
                or bank > 0 and ("bank %dx"):format(bank) or ("%dx"):format(bags), 1, 1, 1, 0.75, 0.78, 0.82)
        end
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cells[i] = c
    return c
end

local function Head(i)
    local h = heads[i]
    if h then return h end
    h = YR.Style.Text(win.right.content, 11, YR.Style.C.muted)
    heads[i] = h
    return h
end

local function CharRow(i)
    local r = chars[i]
    if r then return r end
    local S = YR.Style
    r = CreateFrame("Button", nil, win.left.content)
    r:SetSize(LEFT - 20, 38)
    r.bg = S.Fill(r, { 0, 0, 0, 0 })
    r.name = S.Text(r, 13)
    r.name:SetPoint("TOPLEFT", 8, -4)
    r.sub = S.Text(r, 11, S.C.muted)
    r.sub:SetPoint("TOPLEFT", 8, -21)
    r.money = S.Text(r, 11, S.C.sub)
    r.money:SetPoint("TOPRIGHT", -6, -6)
    r:SetScript("OnClick", function(self) picked = self.key Draw() end)
    r:SetScript("OnEnter", function(self) if self.key ~= picked then self.bg:SetColorTexture(unpack(S.C.hover)) end end)
    r:SetScript("OnLeave", function(self) if self.key ~= picked then self.bg:SetColorTexture(0, 0, 0, 0) end end)
    chars[i] = r
    return r
end

local function LineRow(i)
    local r = lines[i]
    if r then return r end
    local S = YR.Style
    r = CreateFrame("Frame", nil, win.right.content)
    r:SetSize(W - LEFT - 60, ROW)
    r.icon = S.Icon(r, nil, 18)
    r.icon:SetPoint("LEFT", 2, 0)
    r.name = S.Text(r, 13)
    r.name:SetPoint("LEFT", 28, 0)
    r.name:SetWidth(250)
    r.count = S.Text(r, 12, S.C.sub)
    r.count:SetPoint("RIGHT", -2, 0)
    r.count:SetJustifyH("RIGHT")
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self)
        if not self.item then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. self.item)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    lines[i] = r
    return r
end

function Draw()
    if not (win and win:IsShown()) then return end
    local S = YR.Style
    local sum, _ = YR.AltsGold()
    local list = YR.AltsList()
    if picked ~= "*all" and not DB()[picked] then picked = "*all" end
    local n = 0
    local function Char(key, name, sub, money)
        n = n + 1
        local r = CharRow(n)
        r.key = key
        r:SetPoint("TOPLEFT", 0, -(n - 1) * 40)
        r.name:SetText(name)
        r.sub:SetText(sub)
        r.money:SetText(money)
        r.bg:SetColorTexture(unpack(key == picked and S.C.accentD or { 0, 0, 0, 0 }))
        r:Show()
    end
    Char("*all", "All characters", ("%d of them"):format(#list), YR.AltsCoins(sum))
    for _, c in ipairs(list) do
        Char(c.key, Named(c.key), ("level %d  ·  %s"):format(c.level, c.me and "you" or Ago(c.seen)), YR.AltsCoins(c.money))
    end
    if DB()[ACCOUNT] then Char(ACCOUNT, "Account bank", Ago(DB()[ACCOUNT].seen), "") end
    for i = n + 1, #chars do chars[i]:Hide() end
    win.left.content:SetHeight(math.max(10, n * 40))
    if win.left.UpdateBar then win.left:UpdateBar() end

    win.items:SetOn(view == "items")
    win.cur:SetOn(view == "cur")
    win.search:SetShown(view == "items")
    win.all:SetShown(view == "items")
    win.all:SetOn(YippRouteDB.altsAll == true)
    win.forget:SetShown(picked ~= "*all")
    local m = 0
    local function Line(icon, name, count, item)
        m = m + 1
        local r = LineRow(m)
        r:SetPoint("TOPLEFT", 0, -(m - 1) * ROW)
        r.icon:SetTexture(icon or 134400)
        r.name:SetText(name)
        r.count:SetText(count)
        r.item = item
        r:Show()
    end
    local note
    local nc, nh, y = 0, 0, 0
    if view == "items" then
        local items = YR.AltsItems(picked, search)
        local cat, col = nil, 0
        for i = 1, math.min(#items, SHOWN) do
            local e = items[i]
            if e.cat ~= cat then
                -- a new kind: its name over its own rows
                if cat then y = y + CELL + GAP + 8 end
                cat, col = e.cat, 0
                nh = nh + 1
                local h = Head(nh)
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", 2, -y)
                h:SetText(CATS[cat]:upper())
                h:Show()
                y = y + 18
            elseif col == COLS then
                col = 0
                y = y + CELL + GAP
            end
            nc = nc + 1
            local c = Cell(nc)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", col * (CELL + GAP), -y)
            c.e = e
            c.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.item) or 134400)
            local r, g, b = Quality(e.quality)
            c.edge:Color({ r, g, b, e.quality > 1 and 0.9 or 0.25 })
            local total = e.bags + e.bank
            c.count:SetText(total > 1 and (total >= 1000 and ("%.1fk"):format(total / 1000) or tostring(total)) or "")
            c:Show()
            col = col + 1
        end
        if cat then y = y + CELL + GAP end
        note = #items == 0 and (search ~= "" and "No item matches that name." or "Nothing recorded yet. Bags are recorded while you play a character, and its bank when you open it.")
            or #items > SHOWN and ("The first %d of %d: search for the rest."):format(SHOWN, #items)
            or ("%d different items. Soulbound and quest items aren't noted%s."):format(#items, YippRouteDB.altsAll == true and "" or "; food, drink and grey ones are hidden")
    else
        local any = false
        for k, c in pairs(DB()) do
            if (picked == "*all" or picked == k) and c.cur then
                for _, cur in ipairs(c.cur) do
                    any = true
                    Line(cur.icon, cur.name or ("currency " .. tostring(cur.id)), (picked == "*all" and (Named(k) .. "   ") or "") .. tostring(cur.qty))
                end
            end
        end
        note = any and "" or "No currencies noted."
        y = m * ROW
    end
    for i = nc + 1, #cells do cells[i]:Hide() end
    for i = nh + 1, #heads do heads[i]:Hide() end
    for i = m + 1, #lines do lines[i]:Hide() end
    win.right.content:SetHeight(math.max(10, y))
    if win.right.UpdateBar then win.right:UpdateBar() end
    win.note:SetText(note)
end

local function Build()
    if win then return end
    local S = YR.Style
    win = S.Window("HeadstartAltsWindow", W, H, "Characters")
    win:SetFrameStrata("HIGH")
    win.left = S.ScrollArea(win, LEFT, H - 48 - 28)
    win.left:SetPoint("TOPLEFT", 12, -60)
    local rule = win:CreateTexture(nil, "BORDER")
    rule:SetPoint("TOPLEFT", LEFT + 16, -56)
    rule:SetPoint("BOTTOMLEFT", LEFT + 16, 12)
    rule:SetWidth(1)
    rule:SetColorTexture(unpack(S.C.line))
    win.items = S.Chip(win, "Items", function() view = "items" Draw() end)
    win.items:SetPoint("TOPLEFT", LEFT + 30, -60)
    win.cur = S.Chip(win, "Currencies", function() view = "cur" Draw() end)
    win.cur:SetPoint("LEFT", win.items, "RIGHT", 6, 0)
    win.search = S.Input(win, { width = 220, placeholder = "Search by name", onChange = function(words)
        search = words or ""
        Draw()
    end })
    win.search:SetPoint("LEFT", win.cur, "RIGHT", 14, 0)
    win.all = S.Chip(win, "Everything", function()
        YippRouteDB.altsAll = YippRouteDB.altsAll ~= true or nil
        Draw()
    end)
    win.all:SetPoint("LEFT", win.search, "RIGHT", 10, 0)
    win.all.tip = "Include food, drink and grey items"
    StaticPopupDialogs["HEADSTART_FORGET_ALT"] = {
        text = "Headstart: delete everything recorded about %s?\n\nIts bags, bank and gold are recorded again the next time you play it.",
        button1 = "Forget", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function() YR.AltsForget(picked) end,
    }
    win.forget = S.Button(win, "Forget", function()
        local c = DB()[picked]
        StaticPopup_Show("HEADSTART_FORGET_ALT", c and c.name or picked)
    end, nil, 80)
    win.forget:SetHeight(22)
    win.forget:SetPoint("TOPRIGHT", -16, -60)
    win.forget.tip = "Deletes what is recorded about this character, for example one you deleted"
    win.right = S.ScrollArea(win, W - LEFT - 46, H - 48 - 46 - 40)
    win.right:SetPoint("TOPLEFT", LEFT + 30, -92)
    win.note = S.Text(win, 12, S.C.muted)
    win.note:SetPoint("BOTTOMLEFT", LEFT + 30, 14)
    win.note:SetWidth(W - LEFT - 50)
    -- item names come from the game a moment after they're first asked for: drawn again then
    win:SetScript("OnEvent", function() if win.again then return end win.again = true C_Timer.After(0.3, function() win.again = false Draw() end) end)
    win:HookScript("OnShow", function(self) self:RegisterEvent("GET_ITEM_INFO_RECEIVED") end)
    win:HookScript("OnHide", function(self) self:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end)
end

function YR.AltsToggle()
    if not YR.AltsOn() then
        YR.Print("Characters is off. Turn it on in /hs, Characters.")
        return false
    end
    Build()
    if win:IsShown() then win:Hide() return false end
    YR.AltsNote()                   -- this character as it is now
    win:Show()
    Draw()
    return true
end

-- ---------------------------------------------------------------------------
-- When
-- ---------------------------------------------------------------------------
-- As it happens, not at the logout: when you log out the game has already let go of your bags and
-- your gold (both read as nothing then - a character was noted with 0c and empty bags that way).
--   Gold: the moment it changes (the game says so; it is one number).
--   Bags and currencies: a few seconds after the last change, however many changes came, and never
--   in a fight - one look at your bags for a whole pull's worth of loot.
--   The bank: while its window is open, the same way.
local LATER = 4
local bankOpen, soon = false, false
local function Look()
    soon = false
    if not YR.AltsOn() then return end
    if InCombatLockdown() then
        -- after the fight (the end of it is listened for only while this waits)
        if frame then frame:RegisterEvent("PLAYER_REGEN_ENABLED") end
        return
    end
    YR.AltsNote()
    if bankOpen then YR.AltsNoteBank() end
    if Draw then Draw() end
end
local function Soon(after)
    if soon then return end
    soon = true
    C_Timer.After(after or LATER, Look)
end
local function Heard(_, event)
    if event == "PLAYER_MONEY" then
        Me().money = GetMoney()
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        Soon(0.5)
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
    elseif event == "PLAYER_REGEN_ENABLED" then
        frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        Soon(1)
    else
        Soon()                  -- your bags or your currencies changed
    end
end

local function Begin(p)
    frame = p.frame
    Hook()
    BagButtons()
    Soon(6)                     -- once, a little after the login
end
local function End()
    bankOpen = false
    BagButtons()
    if win then win:Hide() end
end

local declared
function YR.StartAlts()
    if declared then return end
    declared = true
    YR.Part(YR.AltsOn, { "PLAYER_MONEY", "BAG_UPDATE_DELAYED", "CURRENCY_DISPLAY_UPDATE", "BANKFRAME_OPENED", "BANKFRAME_CLOSED" },
        Heard, { start = Begin, stop = End, again = BagButtons })
end
