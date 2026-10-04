-- Upgrades: "this is better than what you're wearing", for what you pick up while levelling - grey,
-- white and green gear mostly, where nobody wants to read every tooltip.
--
--   Better is a score per class: the stats on the item (from the game: C_Item.GetItemStats) times
--   a weight for your class, armor and, for weapons, damage per second. It is a levelling score, not
--   a raid sim: a warrior wants Strength and a weapon that hits harder, a mage Intellect.
--   Wearable is what the game says: an item whose tooltip has red text on it (too high a level, a
--   kind of armor or weapon you can't use) is never offered.
--   Two of a kind (rings, a second one-hander): it is measured against the weaker one you wear. A
--   two-hander against your main hand and off hand together.
--   Shown once per item: a chat line with both links, and a small window with an Equip button.
--
-- Account options (YippRouteDB, Settings, QoL): upgrades (on unless turned off), upgradeQuality
-- (highest quality to look at: 1 white, 2 green - the default, 3 blue, 5 everything),
-- upgradeMin (percent better before it's mentioned, default 2), upgradeButton (on unless turned off).
local ADDON, YR = ...

-- Weights per point. Armor is per point of armor, dps per point of damage per second.
local W = {
    WARRIOR = { STRENGTH = 1, AGILITY = 0.7, STAMINA = 0.6, ATTACK_POWER = 0.5, armor = 0.03, dps = 4 },
    PALADIN = { STRENGTH = 1, AGILITY = 0.4, STAMINA = 0.6, INTELLECT = 0.6, SPIRIT = 0.2, ATTACK_POWER = 0.5,
        SPELL_POWER = 0.5, armor = 0.03, dps = 3.5 },
    HUNTER = { AGILITY = 1, STRENGTH = 0.2, STAMINA = 0.5, INTELLECT = 0.3, ATTACK_POWER = 0.5,
        RANGED_ATTACK_POWER = 0.5, armor = 0.02, dps = 1, rangedDps = 4 },
    ROGUE = { AGILITY = 1, STRENGTH = 0.6, STAMINA = 0.5, ATTACK_POWER = 0.5, armor = 0.02, dps = 4 },
    PRIEST = { INTELLECT = 1, SPIRIT = 0.8, STAMINA = 0.5, SPELL_POWER = 0.9, armor = 0.01, dps = 0.3 },
    SHAMAN = { STRENGTH = 0.7, AGILITY = 0.5, STAMINA = 0.6, INTELLECT = 0.8, SPIRIT = 0.4, ATTACK_POWER = 0.4,
        SPELL_POWER = 0.6, armor = 0.02, dps = 3 },
    MAGE = { INTELLECT = 1, SPIRIT = 0.6, STAMINA = 0.5, SPELL_POWER = 0.9, armor = 0.01, dps = 0.3 },
    WARLOCK = { INTELLECT = 0.9, SPIRIT = 0.5, STAMINA = 0.7, SPELL_POWER = 0.9, armor = 0.01, dps = 0.3 },
    DRUID = { STRENGTH = 0.6, AGILITY = 0.6, STAMINA = 0.6, INTELLECT = 0.8, SPIRIT = 0.5, ATTACK_POWER = 0.4,
        SPELL_POWER = 0.6, armor = 0.02, dps = 1.5 },
}

-- Where each kind of item goes. Shirts, tabards, bags, ammo and trinkets (whose worth is in an effect
-- a score can't read) are left out.
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local told = {}        -- [link] = true: said once, this session
local queue = {}       -- upgrades waiting for the window
local win

local function Class() local _, c = UnitClass("player") return c end

--- The score of an item for this class (0 for nothing we can weigh).
function YR.UpgradeScore(link, slot)
    if not link then return 0 end
    local w = W[Class()] or W.WARRIOR
    local stats = C_Item.GetItemStats(link) or {}
    local score = 0
    for key, value in pairs(stats) do
        local stat = key:match("^ITEM_MOD_(.-)_SHORT$")
        if key == "RESISTANCE0_NAME" then
            score = score + value * (w.armor or 0)
        elseif stat == "DAMAGE_PER_SECOND" then
            score = score + value * ((slot == 18 and w.rangedDps) or w.dps or 0)
        elseif stat and w[stat] then
            score = score + value * w[stat]
        end
    end
    return score
end

local function Quality(link)
    local q = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(link)
    if q == nil then q = select(3, C_Item.GetItemInfo(link)) end
    return q
end

--- Red text anywhere on the item's tooltip: the game saying you can't wear it.
local function Unwearable(bag, slot)
    if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return false end
    local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
    if not (ok and data and data.lines) then return true end    -- can't tell: don't offer it
    for _, line in ipairs(data.lines) do
        for _, c in ipairs({ line.leftColor, line.rightColor }) do
            if type(c) == "table" and (c.r or 0) > 0.9 and (c.g or 1) < 0.3 and (c.b or 1) < 0.3 then return true end
        end
    end
    return false
end
YR.Unwearable = Unwearable      -- the gear sim asks it about off hands in your bags

--- The item you'd swap it for, with both scores, or nil when it's no upgrade.
--- Returns old link (nil for an empty slot), new score, old score, slot.
function YR.UpgradeOver(link, equipLoc)
    local slots = SLOTS[equipLoc]
    if not slots then return nil end
    local function Worn(s) return GetInventoryItemLink("player", s) end
    if equipLoc == "INVTYPE_2HWEAPON" then
        local main, off = Worn(16), Worn(17)
        local new = YR.UpgradeScore(link, 16)
        local old = YR.UpgradeScore(main, 16) + YR.UpgradeScore(off, 17)
        return main, new, old, 16
    end
    local pick, pickScore
    for _, s in ipairs(slots) do
        -- A one-hander only goes in the off hand where you already carry a weapon there.
        local worn = Worn(s)
        local usable = not (equipLoc == "INVTYPE_WEAPON" and s == 17 and not (worn and
            select(6, C_Item.GetItemInfoInstant(worn)) == 2))
        if usable then
            local sc = YR.UpgradeScore(worn, s)
            if not pick or sc < pickScore then pick, pickScore = s, sc end
        end
    end
    if not pick then return nil end
    return Worn(pick), YR.UpgradeScore(link, pick), pickScore, pick
end

--- Is the item in this bag slot worth mentioning? Returns old link, percent better, slot.
function YR.CheckUpgrade(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local link = type(info) == "table" and info.hyperlink
    if not link then return nil end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    if not SLOTS[equipLoc] then return nil end
    local q = Quality(link)
    if not q or q > (YippRouteDB.upgradeQuality or 2) then return nil end
    -- an off hand (a shield, a held item) where you wield a two-hander: never offered - the swap takes
    -- the two-hander off. The tooltip still says what it would do.
    local mainHand = GetInventoryItemLink("player", 16)
    if (equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" or equipLoc == "INVTYPE_WEAPONOFFHAND")
        and mainHand and select(4, C_Item.GetItemInfoInstant(mainHand)) == "INVTYPE_2HWEAPON" then
        return nil
    end
    if Unwearable(bag, slot) then return nil end
    -- The gear sim (Sim.lua) when it can answer: your own numbers, the item swapped in. What counts is the
    -- change for your role, with a quarter of the toughness change beside it (all of it for a tank), so
    -- an armor-only piece for an empty slot still counts for something.
    local c = YR.SimCompare and YR.SimCompare(link)
    if c then
        local gain = c.role == "tank" and c.tough or (c.pct + c.tough / 4)
        -- an empty slot: anything that gives something is worth wearing while levelling
        local fills = not c.old and (c.pct > 0 or c.tough > 0)
        -- better and nothing worse (more armor, the same DPS): free to wear, however small the gain
        local free = c.pct >= -0.05 and c.tough >= -0.05 and (c.pct > 0.05 or c.tough > 0.05)
        if gain < (YippRouteDB.upgradeMin or 2) and not fills and not free then return nil end
        return c.old, gain, c.slot, link, YR.SimLine(c)
    end
    -- Without it (your numbers can't be read yet): the class weights.
    local old, new, was, s = YR.UpgradeOver(link, equipLoc)
    if not new or new <= 0 then return nil end
    local better = was > 0 and (new - was) / was * 100 or 100
    if better < (YippRouteDB.upgradeMin or 2) then return nil end
    return old, better, s, link, ("about %d%% better"):format(math.floor(better + 0.5))
end

-- ---------------------------------------------------------------------------
-- Telling you
-- ---------------------------------------------------------------------------
--- Still an upgrade over what you wear now? Updated in place (what it replaces may have changed), or nil
--- when it's gone from your bags or no longer better - you equipped something else for that slot.
local function Recheck(u)
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if type(info) == "table" and info.hyperlink == u.link then
                local old, better, s, link, how = YR.CheckUpgrade(bag, slot)
                if not link then return nil end
                u.old, u.better, u.slot, u.how = old, better, s, how
                return u
            end
        end
    end
end

local function ShowNext()
    if not win or win:IsShown() or InCombatLockdown() then return end
    local u
    while #queue > 0 and not u do u = Recheck(table.remove(queue, 1)) end
    if not u then return end
    win.u = u
    win.link = u.link
    win.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(u.link) or select(5, C_Item.GetItemInfoInstant(u.link)))
    win.text:SetText(("%s\n|cff99ff99%s|r\nover %s"):format(u.link, u.how or "better", u.old or "an empty slot"))
    -- as tall as the text (a long "with ..." line wraps), with the buttons in their own row below it
    local h = tonumber(win.text.GetStringHeight and win.text:GetStringHeight()) or 36
    win:SetHeight(math.max(36, h) + 12 + 10 + 20 + 10)
    win:Show()
end

-- Equip pressed in a fight: put on when it ends.
local equipAfterFight

local function Worn(link)
    for slot = 1, 19 do
        if GetInventoryItemLink("player", slot) == link then return true end
    end
    return false
end

local function InBags(link)
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if type(info) == "table" and info.hyperlink == link then return true end
        end
    end
    return false
end

--- Put it on, and make sure it went: the game says no while you cast, eat, are dead or stunned, and then
--- the offer comes back instead of being lost.
local function Equip(u)
    if InCombatLockdown() then
        equipAfterFight = u
        YR.Print(u.link .. " goes on as soon as this fight ends.")
        return
    end
    local fn = (C_Item and C_Item.EquipItemByName) or EquipItemByName
    if fn then fn(u.link) end
    C_Timer.After(1, function()
        if not Worn(u.link) and InBags(u.link) then
            table.insert(queue, 1, u)
            ShowNext()
        end
    end)
end
YR.UpgradeEquip = Equip         -- for tests

local function Window()
    if win then return win end
    win = CreateFrame("Frame", "HeadstartUpgradeFrame", UIParent, "BackdropTemplate")
    win:SetSize(320, 90)
    win:SetPoint("TOP", UIParent, "TOP", 0, -180)
    win:SetFrameStrata("DIALOG")
    if win.SetBackdrop then
        win:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        win:SetBackdropColor(0, 0, 0, 0.85)
    end
    win.icon = win:CreateTexture(nil, "ARTWORK")
    win.icon:SetSize(36, 36)
    win.icon:SetPoint("TOPLEFT", 12, -12)
    win.text = win:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    win.text:SetPoint("TOPLEFT", win.icon, "TOPRIGHT", 8, 0)
    win.text:SetPoint("RIGHT", -12, 0)
    win.text:SetJustifyH("LEFT")
    win.text:SetJustifyV("TOP")
    win.text:SetWordWrap(true)
    local equip = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    equip:SetSize(80, 20)
    equip:SetPoint("BOTTOMRIGHT", -96, 8)
    equip:SetText("Equip")
    equip:SetScript("OnClick", function()
        local u = win.u
        win:Hide()
        if u then Equip(u) end
    end)
    local later = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    later:SetSize(80, 20)
    later:SetPoint("BOTTOMRIGHT", -12, 8)
    later:SetText("Not now")
    later:SetScript("OnClick", function() win:Hide() end)
    win:SetScript("OnHide", function() C_Timer.After(0.5, ShowNext) end)      -- your armor settles first
    win:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
    end)
    win:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if _G.UISpecialFrames then table.insert(UISpecialFrames, "HeadstartUpgradeFrame") end
    win:Hide()
    return win
end

-- Items looked at and found no upgrade, so a loot only looks at what's new. Forgotten when your gear,
-- level or talents change.
local checked = {}
local waiting = false      -- bags changed in a fight: looked through when it ends
--- Look at every item again (a setting that weighs them changed).
function YR.UpgradesForget() wipe(checked) end

--- Walk the bags; tell about each upgrade not told about yet.
function YR.ScanUpgrades()
    if not YR.Option("upgrades") then return end
    if InCombatLockdown() then waiting = true return end
    waiting = false
    local found = {}      -- [slot] = the best new upgrade for it
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local seen = type(info) == "table" and info.hyperlink
            local old, better, s, link, how
            if seen and not told[seen] and not checked[seen] then
                old, better, s, link, how = YR.CheckUpgrade(bag, slot)
                if not link then checked[seen] = true end
            end
            if link and not told[link] then
                -- two for one slot (two pairs of boots from one quest): only the better one is offered
                local at = found[s]
                if not at or better > at.better then found[s] = { link = link, old = old, better = better, how = how, slot = s } end
            end
        end
    end
    for _, u in pairs(found) do
        told[u.link] = true
        YR.Print(("%s for you, over %s: %s."):format(u.link, u.old or "the empty slot", u.how or ""))
        if YR.Option("upgradeButton") then
            Window()
            -- one waiting for the same slot already: the better of the two stays
            local same
            for i, q in ipairs(queue) do if q.slot == u.slot then same = i end end
            if not same then
                queue[#queue + 1] = u
            elseif u.better > queue[same].better then
                queue[same] = u
            end
        end
    end
    ShowNext()
end

function YR.StartUpgrades()
    local f = CreateFrame("Frame")
    local pending = false
    local function Later()
        if pending then return end
        pending = true
        C_Timer.After(0.5, function() pending = false YR.ScanUpgrades() end)
    end
    for _, e in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    for _, e in ipairs({ "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event)
        -- A ding can make an item you were told was too high a level wearable: look at all of them again.
        if event == "PLAYER_LEVEL_UP" then
            wipe(told)
            wipe(checked)
            C_Timer.After(1, Later)
        elseif event == "PLAYER_REGEN_ENABLED" then
            local u = equipAfterFight
            equipAfterFight = nil
            if u and InBags(u.link) then Equip(u) end
            ShowNext()
            if waiting then Later() end
        elseif event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_TALENT_UPDATE" then
            wipe(checked)       -- another role weighs the same items differently
        else
            if event == "PLAYER_EQUIPMENT_CHANGED" then
                wipe(checked)
                -- what the window offers may be what you just put on, or beaten by it: looked at again
                C_Timer.After(0.5, function()
                    if win and win:IsShown() and win.u and not Recheck(win.u) then win:Hide() end
                end)
            end
            Later()
        end
    end)
end
