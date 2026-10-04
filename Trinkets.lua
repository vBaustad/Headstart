-- Trinkets and gear sets: the useful half of ItemRack, for levelling.
--   * Two trinket buttons on screen. Click one for the trinkets in your bags and click one of those to
--     put it in that slot; right-click a button to use the trinket in it. A click, not a hover: a list
--     that opens whenever the mouse goes past is in the way.
--   * Swap trinkets for me: your trinkets in an order you choose. When the one you wear has been used
--     (on a cooldown longer than the 30 seconds every trinket gets as it goes on) the first ready one in
--     your list goes in instead, and a higher one goes back in as soon as it's ready. A trinket that
--     isn't on the list - one you put on yourself - is left alone, so a manual swap stays.
--   * Swap when...: Carrot on a Stick (or what you choose) while you're mounted, and an item of your
--     choice while you swim; what you wore goes back on after.
--   * Gear sets: the game's own equipment sets, on keys (Key Bindings > AddOns > Headstart) and on
--     /headstart gear <name or number>.
-- Trinkets and armor can't be changed in a fight (only weapons can): a swap asked for in one happens
-- the moment it ends. The swaps it makes by itself are off until you turn them on, and pause while
-- you're flagged for PvP: on a PvP realm a swap at the wrong moment (still on the Carrot when someone
-- jumps you) costs a fight, so by default every change is yours.
--   Account options (YippRouteDB, Settings, QoL, Trinkets & sets): trinketBar, trinketBarLocked,
--   trinketPvpPause (on unless turned off); trinketAuto, trinketMount, trinketSwim (off unless turned on),
--   trinketMountItem / trinketSwimItem (item IDs; nil = Carrot on a Stick / none), trinketMountSlot
--   (13 or 14, nil = 14), trinketBarPos. Per character (YippSetupCharDB.trinkets): order (item IDs,
--   first = most wanted), auto[13] / auto[14] (false = that slot is left alone), before (what the swap
--   when mounted or swimming took off).
local ADDON, YR = ...

local SLOTS = { 13, 14 }
local CARROT = 11122
local USED = 31                -- longer than the 30 s cooldown a trinket gets as it goes on: it was used
-- Where an item of each kind goes, for the swap while swimming (anything but trinkets and rings).
local EQUIP_SLOT = { INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CHEST = 5,
    INVTYPE_ROBE = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9,
    INVTYPE_HAND = 10, INVTYPE_CLOAK = 15, INVTYPE_TRINKET = 14 }

local pending = {}             -- [slot] = item ID to put on when the fight ends

--- The swaps it makes by itself: this one turned on, and not while you're flagged for PvP (unless allowed).
local function AutoOn(key)
    if YippRouteDB[key] ~= true then return false end
    if YR.Option("trinketPvpPause") and UnitIsPVP and UnitIsPVP("player") then return false end
    return true
end
YR.TrinketAutoOn = AutoOn
local held = {}                -- [slot] = "mount" / "swim": the swap-when has it, auto stays out

local function CharDB()
    YippSetupCharDB = YippSetupCharDB or {}
    local t = YippSetupCharDB.trinkets
    if not t then
        t = { order = {}, auto = {} }
        YippSetupCharDB.trinkets = t
    end
    t.order, t.auto = t.order or {}, t.auto or {}
    return t
end
YR.TrinketDB = CharDB

local function IDOf(link) return link and tonumber(tostring(link):match("item:(%d+)")) end
local function Worn(slot) return GetInventoryItemID("player", slot) end

local function IsTrinket(id)
    local _, _, _, loc = C_Item.GetItemInfoInstant(id)
    return loc == "INVTYPE_TRINKET"
end

local function OnUse(id) return C_Item.GetItemSpell and C_Item.GetItemSpell(id) ~= nil end

--- Where this item is in your bags (the first one), or nil.
local function InBags(id)
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if C_Container.GetContainerItemID(bag, slot) == id then return bag, slot end
        end
    end
end

local function WornIn(id)
    for _, s in ipairs(SLOTS) do if Worn(s) == id then return s end end
end

local function Left(start, duration)
    if not (start and duration) or start <= 0 or duration <= 0 then return 0 end
    return math.max(0, start + duration - GetTime())
end

--- Seconds left on an item's cooldown, worn (in that slot) or in your bags.
local function CooldownLeft(id)
    local s = WornIn(id)
    if s then return Left(GetInventoryItemCooldown("player", s)) end
    local bag, slot = InBags(id)
    if bag then return Left(C_Container.GetContainerItemCooldown(bag, slot)) end
    return 0
end

--- Ready to use: no cooldown (worn: none but the 30 s from going on). A trinket with no use is always ready.
local function Ready(id)
    if not OnUse(id) then return true end
    local left = CooldownLeft(id)
    if WornIn(id) then return left <= USED end
    return left <= 0.5
end
YR.TrinketReady = Ready

--- Can't change gear right now: a fight, a cast, dead, or something on the cursor.
local function Busy()
    return InCombatLockdown() or UnitIsDeadOrGhost("player") or (UnitCastingInfo and UnitCastingInfo("player"))
        or (UnitChannelInfo and UnitChannelInfo("player")) or (GetCursorInfo and GetCursorInfo())
end

--- Put this item in this slot: now, or when the fight ends.
function YR.TrinketEquip(id, slot)
    if not id then return end
    if Worn(slot) == id then pending[slot] = nil return end
    if InCombatLockdown() then
        pending[slot] = id
        return
    end
    if Busy() then
        pending[slot] = id
        C_Timer.After(1, function() if pending[slot] == id and not InCombatLockdown() then YR.TrinketEquip(id, slot) end end)
        return
    end
    pending[slot] = nil
    local fn = (C_Item and C_Item.EquipItemByName) or EquipItemByName
    if fn then fn(id, slot) end
end

-- ---------------------------------------------------------------------------
-- Swap trinkets for me
-- ---------------------------------------------------------------------------
--- One pass: at most one swap (the bags move under a swap). Returns the item it put on, and the slot.
function YR.TrinketAuto()
    if not AutoOn("trinketAuto") or Busy() then return nil end
    local db = CharDB()
    local order = db.order
    if #order == 0 then return nil end
    local rank = {}
    for i, id in ipairs(order) do rank[id] = i end
    for _, s in ipairs(SLOTS) do
        local cur = Worn(s)
        -- not a slot it looks after: turned off, held by a swap-when, or a trinket you put on yourself
        if db.auto[s] ~= false and not held[s] and not pending[s] and (not cur or rank[cur]) then
            local curReady = cur and Ready(cur)
            for _, id in ipairs(order) do
                if id == cur then
                    if curReady then break end            -- the best ready one is on already
                elseif not WornIn(id) and InBags(id) and Ready(id) then
                    YR.TrinketEquip(id, s)
                    return id, s
                end
            end
        end
    end
    return nil
end

--- In the list or not: at the end when added.
function YR.TrinketToggleList(id)
    local order = CharDB().order
    for i, v in ipairs(order) do
        if v == id then table.remove(order, i) return false end
    end
    order[#order + 1] = id
    return true
end

function YR.TrinketMove(id, by)
    local order = CharDB().order
    for i, v in ipairs(order) do
        if v == id then
            local j = math.max(1, math.min(#order, i + by))
            table.remove(order, i)
            table.insert(order, j, id)
            return
        end
    end
end

-- ---------------------------------------------------------------------------
-- Swap when mounted / swimming
-- ---------------------------------------------------------------------------
local WHEN = {
    { key = "mount", option = "trinketMount", test = function() return IsMounted and IsMounted() end,
      item = function() return YippRouteDB.trinketMountItem or CARROT end,
      slot = function() return YippRouteDB.trinketMountSlot or 14 end },
    { key = "swim", test = function() return IsSwimming and IsSwimming() end,
      option = "trinketSwim",
      item = function() return YippRouteDB.trinketSwimItem end,
      slot = function(id)
          local _, _, _, loc = C_Item.GetItemInfoInstant(id)
          return loc == "INVTYPE_TRINKET" and (YippRouteDB.trinketMountSlot or 14) or EQUIP_SLOT[loc]
      end },
}

function YR.TrinketWhen()
    local db = CharDB()
    db.before = db.before or {}
    for _, w in ipairs(WHEN) do
        local on = AutoOn(w.option)
        local id = on and w.item()
        local slot = id and w.slot(id)
        local was = db.before[w.key]
        if id and slot and w.test() then
            if not was and Worn(slot) ~= id and InBags(id) and not InCombatLockdown() then
                db.before[w.key] = { slot = slot, id = Worn(slot) or 0 }
                held[slot] = w.key
                YR.TrinketEquip(id, slot)
            end
        elseif was then
            -- off the mount / out of the water: what you wore goes back on
            if was.id ~= 0 and InBags(was.id) then YR.TrinketEquip(was.id, was.slot) end
            db.before[w.key] = nil
            held[was.slot] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- Gear sets: the game's own equipment sets
-- ---------------------------------------------------------------------------
local wantSet         -- a set asked for in a fight

--- The game's equipment sets, in its order: { { id, name } }.
function YR.GearSets()
    local out = {}
    local api = C_EquipmentSet
    if not (api and api.GetEquipmentSetIDs) then return out end
    for _, id in ipairs(api.GetEquipmentSetIDs() or {}) do
        local name = api.GetEquipmentSetInfo(id)
        if name then out[#out + 1] = { id = id, name = name } end
    end
    return out
end

--- Put on a set, by its number in the list or its name. In a fight: when it ends.
function YR.UseGearSet(which)
    local sets, pick = YR.GearSets(), nil
    local n = tonumber(which)
    if n then pick = sets[n] else
        for _, s in ipairs(sets) do if s.name:lower() == tostring(which or ""):lower() then pick = s end end
    end
    if not pick then
        YR.Print(#sets == 0 and "no equipment sets yet: make them in the character window's equipment manager."
            or ("no set %s. You have: %s."):format(tostring(which), (function()
                local names = {}
                for i, s in ipairs(sets) do names[#names + 1] = i .. " " .. s.name end
                return table.concat(names, ", ")
            end)()))
        return
    end
    if InCombatLockdown() then
        wantSet = pick.name
        YR.Print(("%s goes on as soon as this fight ends."):format(pick.name))
        return
    end
    wantSet = nil
    C_EquipmentSet.UseEquipmentSet(pick.id)
    YR.Print(("equipment set: %s."):format(pick.name))
end

function Headstart_GearSet(n) YR.UseGearSet(n) end
BINDING_NAME_HEADSTART_GEARSET1 = "Equipment set 1"
BINDING_NAME_HEADSTART_GEARSET2 = "Equipment set 2"
BINDING_NAME_HEADSTART_GEARSET3 = "Equipment set 3"
BINDING_NAME_HEADSTART_GEARSET4 = "Equipment set 4"
BINDING_NAME_HEADSTART_GEARSET5 = "Equipment set 5"

-- ---------------------------------------------------------------------------
-- The buttons
-- ---------------------------------------------------------------------------
local bar, flyout
local buttons = {}

local function Paint()
    if not bar then return end
    for _, s in ipairs(SLOTS) do
        local b = buttons[s]
        local tex = GetInventoryItemTexture("player", s)
        b.icon:SetTexture(tex or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket")
        b.icon:SetDesaturated(tex == nil)
        local start, duration = GetInventoryItemCooldown("player", s)
        if b.cd and b.cd.SetCooldown then
            if start and duration and duration > 1.5 then b.cd:SetCooldown(start, duration) else b.cd:Clear() end
        end
        -- a small mark while "swap trinkets for me" looks after this slot
        local id, db = Worn(s), CharDB()
        local auto = AutoOn("trinketAuto") and db.auto[s] ~= false and #db.order > 0
        local listed = not id
        for _, v in ipairs(db.order) do if v == id then listed = true end end
        b.auto:SetShown(auto and listed)
    end
end
YR.TrinketPaint = Paint

local function CloseFlyout() if flyout then flyout:Hide() end end

local function OpenFlyout(slot)
    if flyout and flyout:IsShown() and flyout.slot == slot then CloseFlyout() return end
    local S = YR.Style
    if not flyout then
        flyout = CreateFrame("Frame", "HeadstartTrinketFlyout", UIParent)
        flyout:SetFrameStrata("DIALOG")
        S.Fill(flyout, S.C.window)
        S.Border(flyout, S.C.lineHi)
        flyout.items = {}
        flyout.hint = S.Text(flyout, 11, S.C.muted)
        flyout.hint:SetPoint("BOTTOMLEFT", 8, 6)
        flyout.hint:SetText("Click: wear  ·  Right-click: in or out of your swap list")
        if _G.UISpecialFrames then table.insert(UISpecialFrames, "HeadstartTrinketFlyout") end
    end
    flyout.slot = slot
    local list = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for bs = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, bs)
            if id and IsTrinket(id) then
                local seen = false
                for _, v in ipairs(list) do if v == id then seen = true end end
                if not seen then list[#list + 1] = id end
            end
        end
    end
    local order = CharDB().order
    local rank = {}
    for i, id in ipairs(order) do rank[id] = i end
    for i, id in ipairs(list) do
        local b = flyout.items[i]
        if not b then
            b = CreateFrame("Button", nil, flyout)
            b:SetSize(36, 36)
            b:SetPoint("TOPLEFT", 8 + (i - 1) % 6 * 40, -8 - math.floor((i - 1) / 6) * 40)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetAllPoints()
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b.rank = S.Text(b, 12, S.C.gold or S.C.accent)
            b.rank:SetPoint("BOTTOMRIGHT", -2, 2)
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(self.id)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function(self, which)
                if which == "RightButton" then
                    YR.TrinketToggleList(self.id)
                    OpenFlyout(flyout.slot) OpenFlyout(flyout.slot)      -- shut and open: new numbers
                else
                    YR.TrinketEquip(self.id, flyout.slot)
                    CloseFlyout()
                end
                Paint()
            end)
            flyout.items[i] = b
        end
        b.id = id
        b.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(id))
        b.rank:SetText(rank[id] and tostring(rank[id]) or "")
        b:Show()
    end
    for i = #list + 1, #flyout.items do flyout.items[i]:Hide() end
    local cols = math.max(1, math.min(6, #list))
    flyout:SetSize(math.max(250, 16 + cols * 40), 30 + math.max(1, math.ceil(#list / 6)) * 40)
    if #list == 0 then flyout.hint:SetText("No other trinkets in your bags") else
        flyout.hint:SetText("Click: wear  ·  Right-click: in or out of your swap list") end
    flyout:ClearAllPoints()
    flyout:SetPoint("BOTTOMLEFT", buttons[slot], "TOPLEFT", 0, 6)
    flyout:Show()
end
YR.TrinketFlyout = OpenFlyout

local function Build()
    if bar or InCombatLockdown() then return end
    local S = YR.Style
    bar = CreateFrame("Frame", "HeadstartTrinketBar", UIParent)
    bar:SetSize(84, 40)
    local p = YippRouteDB.trinketBarPos
    if p then bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p[1], p[2]) else bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 180) end
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) if not YR.Option("trinketBarLocked") and not InCombatLockdown() then self:StartMoving() end end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        YippRouteDB.trinketBarPos = { math.floor(self:GetLeft() + 0.5), math.floor(self:GetTop() - UIParent:GetTop() + 0.5) }
    end)
    for i, s in ipairs(SLOTS) do
        -- secure, so right-click can use the trinket (an addon may not use items any other way)
        local b = CreateFrame("Button", "HeadstartTrinket" .. s, bar, "SecureActionButtonTemplate")
        b:SetSize(38, 38)
        b:SetPoint("LEFT", (i - 1) * 44 + 2, 0)
        b:RegisterForClicks("AnyUp")
        b:RegisterForDrag("LeftButton")
        b:SetAttribute("type2", "item")
        b:SetAttribute("item2", tostring(s))
        S.Border(b, S.C.lineHi)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 1, -1)
        b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cd:SetAllPoints(b.icon)
        b.auto = b:CreateTexture(nil, "OVERLAY")
        b.auto:SetSize(8, 8)
        b.auto:SetPoint("TOPRIGHT", -3, -3)
        S.ArtTexture(b.auto, "dot")
        b.auto:SetVertexColor(unpack(S.C.green))
        b:SetScript("PostClick", function(_, which)
            if which == "LeftButton" then OpenFlyout(s) end
        end)
        b:SetScript("OnDragStart", function() if not YR.Option("trinketBarLocked") and not InCombatLockdown() then bar:StartMoving() end end)
        b:SetScript("OnDragStop", function() bar:GetScript("OnDragStop")(bar) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if GetInventoryItemID("player", s) then GameTooltip:SetInventoryItem("player", s) else GameTooltip:AddLine("No trinket") end
            GameTooltip:AddLine("Click: your other trinkets  ·  Right-click: use", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        buttons[s] = b
    end
    Paint()
end

--- The buttons on screen or not (only out of a fight: they're secure).
function YR.ShowTrinketBar(on)
    if InCombatLockdown() then return end
    if on and not bar then Build() end
    if bar then bar:SetShown(on and true or false) end
    if not on then CloseFlyout() end
end

function YR.StartTrinkets()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE_COOLDOWN", "BAG_UPDATE_DELAYED",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "SPELL_UPDATE_COOLDOWN" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then CloseFlyout() return end
        if event == "PLAYER_ENTERING_WORLD" then YR.ShowTrinketBar(YR.Option("trinketBar")) end
        if event == "PLAYER_REGEN_ENABLED" then
            for slot, id in pairs(pending) do YR.TrinketEquip(id, slot) end
            if wantSet then YR.UseGearSet(wantSet) end
        end
        Paint()
    end)
    -- once a second: cooldowns run out without an event, mounting and swimming have none we can rely on
    C_Timer.NewTicker(1, function()
        if InCombatLockdown() then return end
        YR.TrinketWhen()
        YR.TrinketAuto()
    end)
end
