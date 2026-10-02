-- ".mailalt" in our routes: a stop at the mailbox to send your alt what the mail rule picks (Mail.lua:
-- crafting mats, recipes you can't use yet, your own list), to clear bag space on the way. The routes
-- have one after each hearthstone stop from level 10 (tools/clean_guide.py mail_stops); the inn
-- nearly always has a mailbox outside. The sending is Mail.lua's button on the mail window (or its
-- auto-send); this only says when to stop.
--
-- The step skips itself (RestedXP's "missing pre-requisites" skip) with no alt set for this realm,
-- or nothing in your bags to send, and is done once the bags are clear of it.
local _, YR = ...

if type(RXP) ~= "table" or type(RXP.functions) ~= "table" or RXP.functions.mailalt then return end

--- How many stacks would go to the alt now, and to whom; 0 when there's no alt or no mail rule.
function YR.MailWaiting()
    if not (YR.MailRecipient and YR.MailPick) then return 0 end
    local to = YR.MailRecipient()
    local me = (UnitName("player") or ""):lower()
    if not to or to:lower() == me or to:lower():match("^" .. me .. "%-") then return 0 end
    local ok, list = pcall(YR.MailPick)
    return ok and type(list) == "table" and #list or 0, to
end

RXP.functions.events.mailalt = { "BAG_UPDATE_DELAYED", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS" }

function RXP.functions.mailalt(self, text)
    if type(self) == "string" then          -- on parse
        return { textOnly = true, text = (text and text ~= "") and text or nil }
    end
    local element = self.element
    local step = element and element.step
    if not (step and step.active) then return end
    local n, to = YR.MailWaiting()
    if n == 0 then
        if not step.completed then
            element.tooltipText = "Nothing to mail"
            step.completed = true
            RXP.updateSteps = true
        end
    else
        element.tooltipText = nil
        element.text = ("Send %d stack%s to %s (the button on the mail window)"):format(n, n == 1 and "" or "s", to)
    end
end
