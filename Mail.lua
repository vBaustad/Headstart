-- Mail to your alt: at a mailbox, crafting mats, recipes you can't use yet and your own list go to
-- the character you name - a bank alt, or the one with the professions - twelve to a letter.
-- A button on the mail window does it ("Send to <alt>"), and if you like it happens as the mailbox
-- opens. Hold Shift as it opens to send nothing.
--
--   What goes is the bank's rule (Bank.lua, YR.StashReason) with its own settings, plus your list.
--   What never goes: quest items, soulbound items (the game won't), anything the route still needs,
--   and what AutoFeed keeps - and nothing at all to yourself, so the same settings work on the alt.
--
--   Account options (YippRouteDB, Settings, QoL):
--     mailTo[realm-faction] = "Name"   who gets it, per realm and faction (mail stays on one side)
--     mailMats      "mine" (default) | "all" | "off"
--     mailRecipes   on unless turned off
--     mailCustom    [itemID] = true: always sent
--     mailAuto      true: send as the mailbox opens (off unless turned on - postage is your money)
--     mailButton    on unless turned off
local ADDON, YR = ...

local PER_LETTER = ATTACHMENTS_MAX_SEND or 12
local mailOpen = false
local run
local button

local function Key()
    return (GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or "?")
end

local function Me() return (UnitName("player")) end

--- Who gets the mail on this realm and faction, or nil.
local KnownFullName     -- below
--- Who gets the mail: always a full name (name and surname - Forever's mail takes nothing less), or
--- nil. One saved before full names were kept ("Klistre") gets its surname when Headstart knows that
--- character, and otherwise counts as not set: a letter to a bare name only fails.
function YR.MailRecipient()
    local to = YippRouteDB.mailTo and YippRouteDB.mailTo[Key()]
    if type(to) ~= "string" or to == "" then return nil end
    if not to:find("[%s%-]") then return KnownFullName and KnownFullName(to) or nil end
    return to
end

--- What was typed, when it's only a name that can't be completed (for the settings to say so).
function YR.MailRecipientMissingSurname()
    local to = YippRouteDB.mailTo and YippRouteDB.mailTo[Key()]
    if type(to) == "string" and to ~= "" and not YR.MailRecipient() then return to end
end

-- On Forever a character's full name is its name and its surname ("Klistre Merke"), and mail needs the
-- full name: "Klistre" alone gets "Please enter a full character name". The game joins them with this.
local function Separator()
    local consts = Constants and Constants.CharacterNameSeparatorConsts
    local v = consts and consts.CHARACTERNAME_SURNAME_SEPARATOR
    return type(v) == "string" and v or " "
end

local function Cap(word) return word:sub(1, 1):upper() .. word:sub(2) end

--- The full name of one of your own characters with this first name, from what Headstart has seen of
--- them (the run log and the splits keep "Name-Surname"), or nil when it doesn't know exactly one.
function KnownFullName(first)
    local found, low = nil, first:lower()
    local function Look(key)
        local n, second = tostring(key):match("^([^%-%s]+)[%-%s](.+)$")
        if n and n:lower() == low and second and not second:find("[%(]") then
            local full = Cap(n) .. Separator() .. second
            if found and found ~= full then found = false elseif found == nil then found = full end
        end
    end
    for key in pairs(YippRouteDB.runs or {}) do Look(key) end
    for _, r in pairs((YippRouteDB.splits or {}).runs or {}) do if type(r) == "table" and r.name then Look(r.name) end end
    return found or nil
end
YR.MailKnownFullName = KnownFullName

--- Keep the full name as typed ("klistre merke" -> "Klistre Merke"; a dash between the two is the same).
--- Just a first name: the surname filled in when Headstart knows that character of yours.
local Refresh      -- the mail window's button (below): its label follows the name
function YR.SetMailRecipient(name)
    YippRouteDB.mailTo = YippRouteDB.mailTo or {}
    name = strtrim(name or ""):gsub("%s+", " ")
    local words = {}
    for w in name:gmatch("[^%s%-]+") do words[#words + 1] = Cap(w) end
    local full = table.concat(words, Separator())
    if #words == 1 then full = KnownFullName(words[1]) or full end
    YippRouteDB.mailTo[Key()] = full ~= "" and full or nil
    if Refresh then Refresh() end
    return YR.MailRecipient()
end

function YR.MailMats()
    local v = YippRouteDB.mailMats
    if v == "all" or v == "off" then return v end
    return "mine"
end

function YR.SetMailCustom(item, on)
    item = tonumber(item)
    if not item then return end
    YippRouteDB.mailCustom = YippRouteDB.mailCustom or {}
    YippRouteDB.mailCustom[item] = on and true or nil
end

--- Is this mail for somebody else? (Never mail yourself.)
local function ToOther(to)
    if not to then return false end
    local first = to:lower():match("^([^%s%-]+)")
    return first ~= (Me() or ""):lower()
end

-- ---------------------------------------------------------------------------
-- What goes
-- ---------------------------------------------------------------------------
--- Every stack to send: { { bag, slot, item, why } } in bag order.
function YR.MailPick()
    local have, list = YR.Professions(), {}
    local custom = YippRouteDB.mailCustom or {}
    local last = NUM_BAG_SLOTS or 4
    for bag = 0, last + 1 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local item = type(info) == "table" and info.itemID
            if item and not info.isBound and not info.isLocked then
                local why
                if custom[item] then
                    -- your list, but never a quest item or one a quest still needs (ours or RestedXP's)
                    local _, _, _, _, _, class = C_Item.GetItemInfoInstant(item)
                    if class ~= 12 and not YR.QuestNeeds(item) then why = "your list" end
                else
                    why = YR.StashReason(item, have, YR.MailMats(), YR.Option("mailRecipes"))
                end
                if why then list[#list + 1] = { bag = bag, slot = slot, item = item, why = why } end
            end
        end
    end
    return list
end

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------
local function Coins(c) return (GetCoinTextureString and GetCoinTextureString(c)) or (c .. "c") end

local function Finish(note)
    local r = run
    run = nil
    if not r then return end
    if r.sent > 0 then
        YR.Print(("mailed %d stack%s to %s (%d letter%s, %s postage)%s"):format(r.sent, r.sent == 1 and "" or "s",
            r.to, r.letters, r.letters == 1 and "" or "s", Coins(r.postage), note and (" - " .. note) or "."))
    elseif note then
        YR.Print(note)
    end
end

--- Empty the letter: a right-click on an attachment takes it back, which is what Blizzard's own
--- attachment buttons do. (This client's mail UI never calls a clear-all function, so we don't either.)
local function ClearLetter()
    for i = 1, PER_LETTER do
        if GetSendMailItem(i) then ClickSendMailItemButton(i, true) end
    end
end

--- Attach the next twelve and send them. The next letter waits for the game to say this one went.
local function NextLetter()
    local r = run
    if not r then return end
    if not mailOpen then return Finish("the mailbox closed before the rest went") end
    if InCombatLockdown() then return Finish("stopped for combat") end
    if r.i > #r.list then return Finish() end
    if MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, nil, 2) end
    ClearLetter()
    local slot, inLetter = 0, 0
    while r.i <= #r.list and slot < PER_LETTER do
        local s = r.list[r.i]
        r.i = r.i + 1
        local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
        if type(info) == "table" and info.itemID == s.item and not info.isLocked then
            slot = slot + 1
            C_Container.PickupContainerItem(s.bag, s.slot)
            ClickSendMailItemButton(slot)
            if CursorHasItem and CursorHasItem() then
                ClearCursor()                    -- the game refused it (bound after all): skip it
                slot = slot - 1
            else
                inLetter = inLetter + 1
            end
        end
    end
    if inLetter == 0 then return Finish() end
    local price = GetSendMailPrice() or 0
    if price > GetMoney() then
        ClearLetter()
        return Finish("not enough money for the postage")
    end
    r.pending = { count = inLetter, price = price }
    SendMail(r.to, ("Headstart: %d for you"):format(inLetter), "")
    -- the game doesn't always answer a refused letter (a name it won't take says so on screen, nothing
    -- more): no word in 10 seconds, and it stops instead of waiting for ever
    local this = r.pending
    C_Timer.After(10, function()
        if run == r and r.pending == this then
            ClearLetter()
            Finish("the letter didn't go - is " .. r.to .. " the full name (name and surname), on this realm and faction?")
        end
    end)
end

--- Send what the settings pick. `loud`: say so when there's nothing to send (the button).
function YR.MailToAlt(loud)
    if run or not mailOpen then return end
    if InCombatLockdown() then if loud then YR.Print("not in combat.") end return end
    local to = YR.MailRecipient()
    if not to then
        local bare = YR.MailRecipientMissingSurname()
        if loud then
            YR.Print(bare and ("mail needs the full name: %s's surname too. Set it in Settings, QoL, Bags (Mail to my alt)."):format(bare)
                or "name the alt to mail in Settings, QoL, Bags (Mail to my alt): name and surname.")
        end
        return
    end
    if not ToOther(to) then
        if loud then YR.Print("this is " .. to .. " - nothing to mail to yourself.") end
        return
    end
    local list = YR.MailPick()
    if #list == 0 then
        if loud then YR.Print("nothing to mail: no crafting mats, recipes or listed items your settings send.") end
        return
    end
    run = { list = list, i = 1, to = to, sent = 0, letters = 0, postage = 0 }
    NextLetter()
end

-- ---------------------------------------------------------------------------
-- The mail window
-- ---------------------------------------------------------------------------
local function Button()
    if button or not MailFrame then return button end
    button = CreateFrame("Button", "HeadstartMailButton", MailFrame, "UIPanelButtonTemplate")
    button:SetSize(140, 22)
    button:SetPoint("TOPRIGHT", MailFrame, "BOTTOMRIGHT", 0, -2)
    button:SetScript("OnClick", function() YR.MailToAlt(true) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Headstart: mail to " .. (YR.MailRecipient() or "your alt"))
        local m = YR.MailMats()
        GameTooltip:AddLine(m == "all" and "Crafting mats: all of them." or m == "mine"
            and "Crafting mats no profession of yours crafts with." or "Crafting mats: off.", 1, 1, 1, true)
        GameTooltip:AddLine(YR.Option("mailRecipes") and "Recipes you can't learn yet." or "Recipes: off.", 1, 1, 1, true)
        GameTooltip:AddLine("And your list. Never soulbound or quest items, or anything a quest still needs (the route's or RestedXP's); of the mats, no AutoFeed food."
            .. " 30 copper a stack in postage. Settings, QoL, Bags.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

function Refresh()
    local b = Button()
    if not b then return end
    local to = YR.MailRecipient()
    b:SetText(to and ("Send to " .. to) or (YR.MailRecipientMissingSurname() and "Alt's surname missing" or "Mail to my alt"))
    b:SetShown(YR.Option("mailButton") and mailOpen and ToOther(to or "?") and true or false)
end

function YR.SetMailButton(on)
    YippRouteDB.mailButton = on and true or false
    Refresh()
end

function YR.MailIsOpen() return mailOpen end

function YR.StartMail()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "UI_ERROR_MESSAGE" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "MAIL_SHOW" then
            if mailOpen then return end
            mailOpen = true
            Refresh()
            if YippRouteDB.mailAuto == true and not IsShiftKeyDown() then
                C_Timer.After(0.5, function() YR.MailToAlt(false) end)
            end
        elseif event == "MAIL_CLOSED" then
            mailOpen = false
            if run then Finish("the mailbox closed before the rest went") end
            if button then button:Hide() end
        elseif event == "MAIL_SEND_SUCCESS" and run and run.pending then
            run.sent = run.sent + run.pending.count
            run.letters = run.letters + 1
            run.postage = run.postage + run.pending.price
            run.pending = nil
            C_Timer.After(0.5, NextLetter)
        elseif (event == "MAIL_FAILED" or (event == "UI_ERROR_MESSAGE" and run and run.pending)) and run then
            local msg = select(2, ...)
            if event == "UI_ERROR_MESSAGE" and not (type(msg) == "string" and (msg == ERR_FULL_NAME_REQUIRED
                or msg:lower():find("mail") or msg:lower():find("name"))) then return end
            ClearLetter()
            Finish("the game refused the letter - " .. run.to .. " needs to be the full name (name and surname),"
                .. " on this realm and faction. Set it in Settings, QoL, Bags")
        end
    end)
end
