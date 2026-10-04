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
function YR.MailRecipient()
    local to = YippRouteDB.mailTo and YippRouteDB.mailTo[Key()]
    if type(to) == "string" and to ~= "" then return to end
end

function YR.SetMailRecipient(name)
    YippRouteDB.mailTo = YippRouteDB.mailTo or {}
    name = strtrim(name or "")
    -- A character name is one word; on Forever the display name adds a surname after a space
    -- ("Bankalt Smith"), which is not part of the name mail goes to. Keep the first word.
    name = name:match("^(%S*)") or ""
    -- "bankalt" -> "Bankalt": what the game would show. A realm part after a dash is left alone.
    if name ~= "" then name = name:sub(1, 1):upper() .. name:sub(2) end
    YippRouteDB.mailTo[Key()] = name ~= "" and name or nil
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
    return to and to:lower() ~= (Me() or ""):lower() and not to:lower():match("^" .. (Me() or ""):lower() .. "%-")
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
                    local _, _, _, _, _, class = C_Item.GetItemInfoInstant(item)
                    if class ~= 12 then why = "your list" end
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
end

--- Send what the settings pick. `loud`: say so when there's nothing to send (the button).
function YR.MailToAlt(loud)
    if run or not mailOpen then return end
    if InCombatLockdown() then if loud then YR.Print("not in combat.") end return end
    local to = YR.MailRecipient()
    if not to then
        if loud then YR.Print("name the alt to mail in Settings, QoL, Bags (Mail to my alt).") end
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
        GameTooltip:AddLine("And your list, as you made it. Never soulbound or quest items; of the mats, nothing the route needs or AutoFeed's food."
            .. " 30 copper a stack in postage. Settings, QoL, Bags.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function Refresh()
    local b = Button()
    if not b then return end
    local to = YR.MailRecipient()
    b:SetText(to and ("Send to " .. to) or "Mail to my alt")
    b:SetShown(YR.Option("mailButton") and mailOpen and ToOther(to or "?") and true or false)
end

function YR.SetMailButton(on)
    YippRouteDB.mailButton = on and true or false
    Refresh()
end

function YR.MailIsOpen() return mailOpen end

function YR.StartMail()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED" }) do pcall(f.RegisterEvent, f, e) end
    f:SetScript("OnEvent", function(_, event)
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
        elseif event == "MAIL_FAILED" and run then
            Finish("the game refused the letter - is " .. run.to .. " the right name, on this realm and faction?")
        end
    end)
end
