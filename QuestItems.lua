-- Quest item buttons: the items a quest gave you that you use - Really Sticky Glue to throw, a Sprouted Frond to
-- heal with - as buttons on screen, so they needn't be dragged from your bags onto your bars (the owner,
-- 2026-10-16: "a little on-use window for the items you get from quests").
--   Which: an item in your bags that has a use (the game's own: C_Item.GetItemSpell) and is a quest's reward: one
--   the reward window offered as you handed a quest in (written down per character then, YippSetupCharDB.questUse)
--   - and only a consumable of the sorts that are things to use: Other (Really Sticky Glue, a Sprouted Frond),
--   Explosives, Devices, Scrolls. Not food or drink, a potion, elixir, flask or bandage, and never a recipe or a
--   piece of gear, which have a "Use:" too (the owner, 2026-10-20: "I don't want food and quest items: it's more
--   things like sticky glue"; then "not recipes either"). Quest items too - the game says so of the bag slot, or
--   its kind is Quest - only with their switch on (questItemsQuest, off until turned on).
--   Left out: one already on your action bars, and one you took off
--   with Shift+right-click (YippSetupCharDB.questUseHidden; "Show them again" on the settings page).
--   A click uses it, as from your bags (on your target where it needs one). Its cooldown and how many you
--   carry are on the button; the tooltip is the item's.
--   Secure buttons, the only way an addon may use an item: laid out out of a fight. What changed in one
--   (a new item, one used up) is put right as it ends.
--   Account options: questItems (off until turned on), questItemsQuest (off), questItemsSize (36),
--   questItemsVertical, questItemsPos (set in Arrange, /hs move). Free while off (YR.Part): nothing listens and nothing is made; on, the
--   bags, your action bars, the reward window and cooldowns are listened for (and a fight's end, while
--   something waits for it).
local _, YR = ...

local MAX = 12                  -- buttons at most
local CLASS_QUEST = 12          -- (an item's kind: Quest)
-- the rewards that get a button: a Consumable (kind 0) of these sorts - Explosives 0, Scrolls 4, Other 8 (Really
-- Sticky Glue, a Sprouted Frond), Devices 14. Not potions 1, elixirs 2, flasks 3, food and drink 5, item
-- enhancements 6, bandages 7 or draughts 13 (what you eat or keep on your bars anyway), and no other kind: a
-- recipe (9), gear (2, 4) and the rest have a "Use:" of their own.
local TO_USE = { [0] = true, [4] = true, [8] = true, [14] = true }
-- Of those, these get a button wherever they came from - the reward window seen or not: a Bogling Root, a Sprouted Frond
-- and a Severed Voodoo Claw had none on a character that got them before this listened, or with it off (the owner,
-- 2026-10-22, back in the beta: "root, frond and claw"). A scroll only as a quest's reward: they come from vendors and
-- drops too, many of them.
local ANY_TIME = { [0] = true, [8] = true, [14] = true }
local bar
local buttons = {}
local pending = false           -- laid out again as the fight ends

local function On() return YR.QoLOn() and YR.Option("questItems") end
local function CharDB()
    if type(YippSetupCharDB) ~= "table" then YippSetupCharDB = {} end
    local db = YippSetupCharDB
    if type(db.questUse) ~= "table" then db.questUse = {} end
    if type(db.questUseHidden) ~= "table" then db.questUseHidden = {} end
    return db
end

--- How the buttons look, as set (the bar here and the settings page).
function YR.QuestItemsLook()
    local db = YippRouteDB
    return {
        size = math.max(24, math.min(56, tonumber(db.questItemsSize) or 36)),
        vertical = db.questItemsVertical == true,
    }
end

-- ---------------------------------------------------------------------------
-- Which items
-- ---------------------------------------------------------------------------
local function HasUse(id) return C_Item.GetItemSpell and C_Item.GetItemSpell(id) ~= nil end

-- The items on your action bars (one there needs no button of ours): kept slot by slot, all read once, then a slot
-- again as the game says it changed (BarSlot). slotItem: [slot] = item; onBars: [item] = how many slots hold it.
local slotItem, onBars
local function BarSlot(slot)
    local kind, id = GetActionInfo(slot)
    local new = (kind == "item" and id) or nil
    local old = slotItem[slot]
    if old == new then return false end
    if old then onBars[old] = (onBars[old] or 1) > 1 and onBars[old] - 1 or nil end
    if new then onBars[new] = (onBars[new] or 0) + 1 end
    slotItem[slot] = new
    return true
end
local function OnBars()
    if not GetActionInfo then return {} end
    if not slotItem then
        slotItem, onBars = {}, {}
        for slot = 1, 180 do BarSlot(slot) end
    end
    return onBars
end

--- The items to have buttons, in bag order: { itemID, ... }.
function YR.QuestItemsWanted()
    local db = CharDB()
    local quest = YippRouteDB.questItemsQuest == true
    local bars = OnBars()
    local out, seen = {}, {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and not seen[id] and not db.questUseHidden[id] and not bars[id] and HasUse(id) then
                seen[id] = true
                local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
                local isQuest = false
                if quest then
                    local info = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
                    isQuest = (type(info) == "table" and info.isQuestItem == true) or classID == CLASS_QUEST
                end
                local reward = classID == 0 and TO_USE[subID] and (ANY_TIME[subID] or db.questUse[id])
                if isQuest or reward then
                    out[#out + 1] = id
                    if #out >= MAX then return out end
                end
            end
        end
    end
    return out
end

--- /headstart questitems: every item in your bags with a use, and why it has a button or not (the owner, 2026-10-22,
--- back in the beta: "the quest bar's items didn't work, I think" - and nothing could say why from outside the game).
function YR.QuestItemsDebug()
    local db = CharDB()
    local quest = YippRouteDB.questItemsQuest == true
    local bars = OnBars()
    YR.Print(("quest item buttons: %s; quest items too: %s; %d quest rewards known on this character."):format(
        On() and "on" or "off (QoL, Journey page)", quest and "on" or "off", (function() local n = 0 for _ in pairs(db.questUse) do n = n + 1 end return n end)()))
    local seen, shown = {}, 0
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and not seen[id] and HasUse(id) then
                seen[id] = true
                local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or ("item " .. id)
                local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
                local info = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
                local isQuest = (type(info) == "table" and info.isQuestItem == true) or classID == CLASS_QUEST
                local why
                if db.questUseHidden[id] then why = "taken off with Shift+right-click (Show them again, on the settings page)"
                elseif bars[id] then why = "on your action bars already"
                elseif isQuest then why = quest and "shown (a quest item)" or "a quest item - shown only with Quest items too on"
                elseif not (classID == 0 and TO_USE[subID]) then why = ("not a thing to use (kind %s, sort %s: food, a potion, a recipe...)"):format(tostring(classID), tostring(subID))
                elseif not (ANY_TIME[subID] or db.questUse[id]) then why = "a scroll that wasn't a quest's reward here"
                else why = "shown" end
                if why:find("^shown") then shown = shown + 1 end
                YR.Print(("  %s: %s"):format(tostring(name), why))
            end
        end
    end
    if next(seen) == nil then YR.Print("  no item in your bags has a use.") end
end

-- The reward window: what it offers is written down (only what you take reaches your bags).
local function Rewards()
    local db = CharDB()
    for _, kind in ipairs({ "reward", "choice" }) do
        local n = (kind == "reward" and GetNumQuestRewards or GetNumQuestChoices)() or 0
        for i = 1, n do
            local link = GetQuestItemLink(kind, i)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then db.questUse[id] = true end
        end
    end
end
YR.QuestItemsRewards = Rewards

-- ---------------------------------------------------------------------------
-- The buttons
-- ---------------------------------------------------------------------------
local function SavePos()
    if not bar or InCombatLockdown() then return false end
    local left, top = bar:GetLeft(), bar:GetTop()
    if not (left and top) then return false end
    YippRouteDB.questItemsPos = { math.floor(left + 0.5), math.floor(top - UIParent:GetTop() + 0.5) }
    return true
end
YR.QuestItemsSavePosition = SavePos
function YR.QuestItemsResetPosition()
    if InCombatLockdown() then YR.Print("the quest item buttons can't be moved in combat.") return false end
    YippRouteDB.questItemsPos = nil
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230)
    end
    return true
end

local function Paint(cooldownsOnly)
    if not (bar and bar:IsShown()) then return end
    for _, b in ipairs(buttons) do
        local id = b.id
        if id and b:IsShown() then
            if not cooldownsOnly then
                b.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(id))
                local n = C_Item.GetItemCount and C_Item.GetItemCount(id) or 0
                b.count:SetText(n > 1 and tostring(n) or "")
            end
            local start, duration = 0, 0
            if C_Container.GetItemCooldown then start, duration = C_Container.GetItemCooldown(id) end
            local secret = issecretvalue and (issecretvalue(start) or issecretvalue(duration))
            if not secret and b.cd.SetCooldown then
                local on = start and duration and duration > 1.5
                if not on then start, duration = 0, 0 end
                if rawget(b, "cdStart") ~= start or rawget(b, "cdLength") ~= duration then
                    b.cdStart, b.cdLength = start, duration
                    if on then b.cd:SetCooldown(start, duration) else b.cd:Clear() end
                end
            end
        end
    end
end
YR.QuestItemsPaint = Paint

local Layout
-- In a fight the secure buttons can't change: laid out as it ends (a listener of its own, made the first time
-- one is needed, and only until then).
local waiter
local function Wait()
    pending = true
    waiter = waiter or CreateFrame("Frame")
    waiter:RegisterEvent("PLAYER_REGEN_ENABLED")
    waiter:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pending then Layout() end
    end)
end

local function Button(i)
    local S = YR.Style
    -- secure: an addon may use an item no other way
    local b = CreateFrame("Button", "HeadstartQuestItem" .. i, bar, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false)          -- (it hears the release: see the trinket buttons)
    b:RegisterForDrag("LeftButton")
    -- Soft, not sharp: the icon's corners rounded and a dark rim under it, no bright line round it; the count large,
    -- outlined, over the cooldown's shade (the owner, 2026-10-22: "the boxes are a bit sharp, and the number in the corner
    -- hard to see").
    b.rim = b:CreateTexture(nil, "BACKGROUND")
    b.rim:SetTexture(S.ART .. "iconmask")
    b.rim:SetVertexColor(0, 0, 0, 0.75)
    b.rim:SetPoint("TOPLEFT", -1, 1)
    b.rim:SetPoint("BOTTOMRIGHT", 1, -1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if b.CreateMaskTexture and b.icon.AddMaskTexture then
        local mask = b:CreateMaskTexture()
        mask:SetTexture(S.ART .. "iconmask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(b.icon)
        b.icon:AddMaskTexture(mask)
    end
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints()
    top:SetFrameLevel((b.cd:GetFrameLevel() or b:GetFrameLevel()) + 1)
    b.count = top:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(S.FONT, 13, "OUTLINE")
    b.count:SetTextColor(1, 1, 1)
    b.count:SetShadowColor(0, 0, 0, 1)
    b.count:SetShadowOffset(1, -1)
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    -- Shift+right-click: off the bar for this character (out of a fight it goes at once)
    b:SetScript("PostClick", function(self, which)
        if which == "RightButton" and IsShiftKeyDown() and self.id then
            CharDB().questUseHidden[self.id] = true
            Layout()
        end
    end)
    b:SetScript("OnDragStart", function() if bar:GetScript("OnDragStart") then bar:GetScript("OnDragStart")(bar) end end)
    b:SetScript("OnDragStop", function() if bar:GetScript("OnDragStop") then bar:GetScript("OnDragStop")(bar) end end)
    b:SetScript("OnEnter", function(self)
        if not self.id then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetItemByID(self.id)
        GameTooltip:AddLine("Click: use  ·  Shift+right-click: off this bar", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function Build()
    if bar or InCombatLockdown() then return end
    bar = CreateFrame("Frame", "HeadstartQuestItemBar", UIParent)
    bar:SetSize(40, 40)
    local p = YippRouteDB.questItemsPos
    if p then bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", p[1], p[2]) else bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230) end
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)            -- (by Arrange, which saves where it stands: YR.QuestItemsSavePosition)
    bar:SetScript("OnShow", function() Paint() end)
    for i = 1, MAX do buttons[i] = Button(i) end
end

--- The buttons as things are now: which items, where, how large. Out of a fight only (secure); in one, as
--- it ends.
function Layout()
    if InCombatLockdown() then Wait() return end
    pending = false
    if not On() then
        if bar then bar:Hide() end
        return
    end
    local want = YR.QuestItemsWanted()
    if #want == 0 and not bar then return end
    Build()
    if not bar then return end
    local look = YR.QuestItemsLook()
    -- the same items in the same look as last time: the buttons are as they should be (only what they show is painted)
    local key = table.concat(want, ",") .. "|" .. tostring(look.size) .. "|" .. tostring(look.vertical)
    if key == bar.laid and bar:IsShown() == (#want > 0) then
        Paint()
        return
    end
    bar.laid = key
    local pitch = look.size + 4
    for i, b in ipairs(buttons) do
        local id = want[i]
        b.id = id
        b:SetSize(look.size, look.size)
        b:ClearAllPoints()
        if look.vertical then b:SetPoint("TOP", bar, "TOP", 0, -(i - 1) * pitch - 2)
        else b:SetPoint("LEFT", bar, "LEFT", (i - 1) * pitch + 2, 0) end
        b:SetAttribute("type1", id and "item" or nil)
        b:SetAttribute("item1", id and ("item:" .. id) or nil)
        b:SetShown(id ~= nil)
    end
    local long = math.max(1, #want) * pitch
    if look.vertical then bar:SetSize(look.size + 4, long) else bar:SetSize(long, look.size + 4) end
    bar:SetShown(#want > 0)
    Paint()
end
YR.QuestItemsLayout = Layout

--- After a setting changed: as it is now (in a fight: as it ends).
function YR.QuestItemsApply() Layout() end

--- The items taken off with Shift+right-click, back on.
function YR.QuestItemsShowHidden()
    CharDB().questUseHidden = {}
    Layout()
end
function YR.QuestItemsHiddenCount()
    local n = 0
    for _ in pairs(CharDB().questUseHidden) do n = n + 1 end
    return n
end

-- Bags change several times a loot: laid out once, a moment after they settle.
local later = false
local function Soon()
    if later then return end
    later = true
    C_Timer.After(0.2, function() later = false Layout() end)
end

YR.Part(On, { "BAG_UPDATE_DELAYED", "ACTIONBAR_SLOT_CHANGED", "QUEST_COMPLETE", "BAG_UPDATE_COOLDOWN",
    "SPELL_UPDATE_COOLDOWN", "PLAYER_ENTERING_WORLD" }, function(_, event, slot)
    if event == "QUEST_COMPLETE" then Rewards() return end
    if event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then Paint(true) return end
    if event == "ACTIONBAR_SLOT_CHANGED" and slotItem then
        -- (one slot: read alone, and nothing to do where it holds the same item as before; no slot said: all again)
        if type(slot) == "number" and slot >= 1 and slot <= 180 then
            if not BarSlot(slot) then return end
        else
            slotItem = nil
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        slotItem = nil              -- (a reload or another character's bars: read all again)
    end
    Soon()
end, {
    start = function() slotItem = nil Layout() end,
    stop = function() Layout() end,
})
