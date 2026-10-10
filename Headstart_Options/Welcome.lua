-- Welcome: a small window that finds out with you how much of Headstart you want, and turns that on.
--   Not everyone wants all of it, and what people want isn't one dial from "little" to "much": someone
--   wants every bar and nothing automated, someone else no bars (a UI suite draws those) and the
--   restocking. So it is four questions, each answered by itself:
--     Routes of your own      Off / On          your runs recorded as you level and saved as routes of your
--                             own, played back in RestedXP; level splits (a reload). Headstart ships no routes
--     On your screen          Nothing / Essentials / Everything
--                             Essentials: XP bar, flight timer, camp icon, loot feed, chat log, death recap,
--                             instance tracker, better-gear notes. Everything: the swing timer, trinket
--                             buttons, Invite and Leave buttons and the movable talent window too
--     Does things for you     Nothing / For friends / Everything
--                             For friends: accepts invites and shared quests from guildies and friends, invites
--                             the ones who whisper "inv" - no gold, no items. Everything: also restock and
--                             training (spend gold), banking (moves items), a screenshot at every ding
--     New characters          Off / On          Character setup: the bar planner, a main's bars on an alt
--   Each answer is a card that says what it turns on; that is all the words on the window. A question
--   left unanswered (click the picked answer again) is left as it is. What another addon you have
--   already does (its feature on) is left off whatever you answer, and named.
--   Three quick picks answer all four at once: Minimal, Recommended, Everything.
--   Shown once on a new install, a few seconds after the first login (not in a fight), and any time
--   by /headstart start. Nothing is locked in: every one of these has its switch in the window.
--   Part of Headstart_Options (the load-on-demand window addon): none of it is in memory until then.
local YR = _G.HeadstartNS

-- What an answer decides. q: the question; level: the first answer (1, 2) it is on in.
local function Key(key, after)
    return function() return YR.OptionSet(key) end, function(on)
        YippRouteDB[key] = on and true or false
        if after then after(on) end
    end
end
local function Who(key, get)
    return function() return get() ~= "off" end, function(on) YippRouteDB[key] = on and "friends" or "off" end
end

local FEATURES
local function Features()
    if FEATURES then return FEATURES end
    local function F(key, label, q, level, get, set) return { key = key, label = label, q = q, level = level, get = get, set = set } end
    FEATURES = {
        F("routes", "run recording, routes of your own, level splits", "routes", 1, function() return YR.RoutesOn() end, function(on) YR.SetRoutesOn(on) end),
        F("xpbar", "XP bar", "screen", 1, function() return YR.XPBarOn() end, function(on) YR.XPBarDB().on = on YR.XPBarApply() end),
        F("flightTimer", "flight timer", "screen", 1, Key("flightTimer", function(on) YR:SetFlightTimer(on) end)),
        F("camp", "camp icon", "screen", 1, Key("camp", function(on) YR.SetCampIcon(on) end)),
        F("lootFeed", "loot feed", "screen", 1, Key("lootFeed", function() YR.LootFeedApply() end)),
        F("chatLog", "chat log", "screen", 1, Key("chatLog", function() YR.ChatLogApply() end)),
        F("deathRecap", "death recap", "screen", 1, Key("deathRecap", function() YR.RecapApply() end)),
        F("instanceTrack", "instance tracker", "screen", 1, Key("instanceTrack", function() if YR.InstanceHudApply then YR.InstanceHudApply() end end)),
        F("upgrades", "better-gear notes", "screen", 1, Key("upgrades")),
        F("alts", "your other characters' bags, bank and gold", "screen", 1, Key("alts")),
        F("swing", "swing timer", "screen", 2, function() return YR.SwingDB().on == true end, function(on) YR.SwingDB().on = on YR.SwingApply() end),
        F("trinketBar", "trinket buttons", "screen", 2, Key("trinketBar", function(on) YR.ShowTrinketBar(on) end)),
        F("groupBar", "Invite and Leave buttons", "screen", 2, Key("groupBar", function(on) YR.SetGroupBar(on) end)),
        F("talentMove", "movable talent window", "screen", 2, Key("talentMove", function() YR.TalentPlace() end)),
        F("questLFG", "quest group finder", "screen", 2, Key("questLFG")),
        F("acceptInvites", "accept friends' invites", "acts", 1, Who("acceptInvites", YR.AcceptInvitesSet)),
        F("whisperInvite", "invite friends who whisper \"inv\"", "acts", 1, Who("whisperInvite", YR.WhisperInviteSet)),
        F("acceptFrom", "accept quests friends share", "acts", 1, Who("acceptFrom", YR.AcceptFromSet)),
        F("restock", "vendor restock", "acts", 2, Key("restock")),
        F("autoTrain", "spells learned at the trainer", "acts", 2, Key("autoTrain", function() YR:SyncRxpTrainer() end)),
        F("bankAuto", "mats banked", "acts", 2, Key("bankAuto")),
        F("levelShot", "a screenshot at every ding", "acts", 2, Key("levelShot")),
        F("setupOn", "Character setup", "setup", 1, function() return YR.SetupOn() end, function(on) YR.SetSetupOn(on) end),
    }
    -- a feature that is shelved isn't asked about (QuestLFG.lua)
    for i = #FEATURES, 1, -1 do
        if FEATURES[i].key == "questLFG" and not YR.QuestLFGAvailable then table.remove(FEATURES, i) end
    end
    return FEATURES
end

-- The questions, in the order asked. An answer is a number: 0 the first choice (nothing of it), up.
local QUESTIONS = {
    { key = "routes", title = "Your own routes", icon = "Interface\\Icons\\INV_Misc_Map_01", choices = {
        { "Off", "No run recording and no level splits." },
        { "On", "Records your runs and saves them as your own routes for RestedXP. Takes a reload." } } },
    { key = "screen", title = "On screen", icon = 236562, choices = {
        { "Nothing", "No bars, buttons or panels from Headstart." },
        { "Essentials", "XP bar, flight timer, camp icon, loot feed, chat log, death recap, instance tracker, upgrade alerts, and your other characters' bags and gold." },
        { "Everything", "Adds the swing timer, trinket buttons, and Invite and Leave buttons." } } },
    { key = "acts", title = "Automation", icon = 133784, choices = {
        { "Nothing", "Headstart never acts on your behalf." },
        { "Friends only", "Accepts invites and shared quests from friends and guild members, and invites them when they whisper \"inv\". Never spends gold or moves items." },
        { "Everything", "Adds restock and auto-train (spend gold), bank deposit (moves items), and a screenshot on level-up." } } },
    { key = "setup", title = "New characters", icon = 134166, choices = {
        { "Off", "Nothing is placed on your bars." },
        { "On", "Bar profiles and the planner, and your bars, macros and interface applied to new characters." } } },
}
function YR.WelcomeQuestions() return QUESTIONS end

local QUICK = {
    minimal = { routes = 0, screen = 0, acts = 0, setup = 0 },
    recommended = { screen = 1, acts = 1 },          -- routes and Character setup as they are
    everything = { routes = 1, screen = 2, acts = 2, setup = 1 },
}
--- The answers of a quick pick ("minimal", "recommended", "everything"), a table of your own to change.
function YR.WelcomeQuick(name)
    local q = QUICK[name]
    if not q then return nil end
    return { routes = q.routes, screen = q.screen, acts = q.acts, setup = q.setup }
end

--- What the answers would do: { { key, label, q, on, now, other }, ... }. A question with no answer
--- leaves its things as they are (on = now). `other` is the addon you have that already does it:
--- that one is left off whatever the answer.
function YR.WelcomePlan(answers)
    answers = answers or {}
    local plan = {}
    for _, f in ipairs(Features()) do
        local now = f.get() and true or false
        local answer = answers[f.q]
        local other = YR.OtherHas(f.key)
        local on = now
        if answer ~= nil then on = f.level <= answer and not other end
        plan[#plan + 1] = { key = f.key, label = f.label, q = f.q, on = on, now = now, other = other }
    end
    return plan
end

--- The answers that are what you have now: a question whose things match none of its choices has none.
function YR.WelcomeNow()
    local answers = {}
    for _, q in ipairs(QUESTIONS) do
        for answer = 0, #q.choices - 1 do
            local same = true
            for _, f in ipairs(Features()) do
                if f.q == q.key then
                    local want = f.level <= answer and not YR.OtherHas(f.key)
                    if want ~= (f.get() and true or false) then same = false break end
                end
            end
            if same then answers[q.key] = answer break end
        end
    end
    return answers
end

--- The answers put in place. Returns how many things were turned on, how many off, and whether it
--- takes a reload (the routes changed).
function YR.WelcomeApply(answers)
    local plan = YR.WelcomePlan(answers)
    local on, off, reload = 0, 0, false
    for i, f in ipairs(Features()) do
        local want = plan[i].on
        if want ~= plan[i].now then
            f.set(want)
            if want then on = on + 1 else off = off + 1 end
            if f.key == "routes" then reload = true end
        end
    end
    YippRouteDB.welcome = nil               -- answered
    YR.SettingChanged()
    YR:RefreshWindow()
    return on, off, reload
end

--- A question's answer in words: what it turns on, and what is left to another addon.
function YR.WelcomeLine(q, plan)
    local on, left = {}, {}
    for _, p in ipairs(plan) do
        if p.q == q then
            if p.on then on[#on + 1] = p.label
            elseif p.other then left[#left + 1] = p.label .. " (" .. p.other .. " does it)" end
        end
    end
    local line = #on > 0 and ("On: " .. table.concat(on, ", ") .. ".") or "Nothing of it on."
    if #left > 0 then line = line .. " Left off: " .. table.concat(left, ", ") .. "." end
    return line
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
-- Each answer is a card that says what it does; nothing else is written on the window.
local LEFT_W, CARD_W, CARD_H, GAP = 200, 200, 86, 8
local W = 20 + LEFT_W + 3 * CARD_W + 2 * GAP + 20
local BLOCK_H = CARD_H + 14
local win, answers

-- Whether the answers are a quick pick's (what it doesn't answer may be anything).
local function IsQuick(name)
    for key, v in pairs(QUICK[name]) do if answers[key] ~= v then return false end end
    return true
end

-- What of a choice another addon of yours does already: "XP bar (Naowh Forever has it)".
local function Skipped(q, answer)
    local out
    for _, f in ipairs(Features()) do
        local other = f.q == q and f.level <= answer and YR.OtherHas(f.key)
        if other then out = (out and out .. ", " or "") .. f.label .. " (" .. other .. " has it)" end
    end
    return out
end

-- A card you pick: lit while it is the answer. A card that becomes the answer comes up out of the dim.
local function Lit(card, sel)
    local S = YR.Style
    card.edge:Color(sel and S.C.accent or S.C.line)
    card.fill:SetColorTexture(unpack(sel and S.C.accentD or S.C.card))
    card.mark:SetShown(sel)
    card.name:SetTextColor(unpack(sel and S.C.text or S.C.sub))
    if sel and card.sel == false and card.flash then
        card.flash:Stop()
        card.flash:Play()
    end
    card.sel = sel
end

local function Card(parent, w, h, name, onClick)
    local S = YR.Style
    local card = CreateFrame("Button", nil, parent)
    card:SetSize(w, h)
    card.fill = S.Fill(card, S.C.card)
    card.edge = S.Border(card, S.C.line)
    card.mark = card:CreateTexture(nil, "ARTWORK")
    card.mark:SetPoint("TOPLEFT", 1, -1)
    card.mark:SetPoint("BOTTOMLEFT", 1, 1)
    card.mark:SetWidth(3)
    card.mark:SetColorTexture(unpack(S.C.accent))
    card.name = S.Text(card, 14, S.C.sub)
    card.name:SetText(name)
    card.hover = S.Fill(card, S.C.hover, "HIGHLIGHT")
    card.sel = false
    card.flash = card:CreateAnimationGroup()
    local a = card.flash:CreateAnimation("Alpha")
    a:SetFromAlpha(0.35)
    a:SetToAlpha(1)
    a:SetDuration(0.22)
    a:SetSmoothing("OUT")
    card:SetScript("OnClick", onClick)
    return card
end

local function Paint()
    local plan = YR.WelcomePlan(answers)
    for _, block in ipairs(win.blocks) do
        for i, card in ipairs(block.cards) do
            Lit(card, answers[block.q.key] == i - 1)
            local skipped = Skipped(block.q.key, i - 1)
            card.blurb:SetText(skipped and (block.q.choices[i][2] .. " |cff8a827aNot " .. skipped .. ".|r") or block.q.choices[i][2])
        end
    end
    for name, pill in pairs(win.quick) do Lit(pill, IsQuick(name)) end
    local changes, reload = 0, false
    for _, p in ipairs(plan) do
        if p.on ~= p.now then
            changes = changes + 1
            if p.key == "routes" then reload = true end
        end
    end
    win.apply.text:SetText(changes == 0 and "Nothing to change" or reload and "Apply and reload" or "Apply")
    win.apply:SetEnabled(changes > 0)
end

local function Build()
    if win then return end
    local S = YR.Style
    local H = 48 + 62 + #QUESTIONS * BLOCK_H + 58
    win = S.Window("HeadstartWelcomeWindow", W, H, "Welcome to Headstart")
    win.subtitle:SetText("Choose what to turn on. You can change it any time with /hs.")

    -- the quick picks: all four answered at once
    win.quick = {}
    local x = 20 + LEFT_W
    for _, pick in ipairs({ { "minimal", "Minimal" }, { "recommended", "Recommended" }, { "everything", "Everything" } }) do
        local pill = Card(win, CARD_W, 32, pick[2], function()
            -- what a quick pick doesn't answer stays as you had it answered
            for key, v in pairs(QUICK[pick[1]]) do answers[key] = v end
            Paint()
        end)
        pill.name:SetPoint("CENTER")
        pill:SetPoint("TOPLEFT", x, -64)
        x = x + CARD_W + GAP
        win.quick[pick[1]] = pill
    end
    local quick = S.Text(win, 15)
    quick:SetPoint("TOPLEFT", 20, -72)
    quick:SetText("Quick pick")

    win.blocks = {}
    for n, q in ipairs(QUESTIONS) do
        local top = -110 - (n - 1) * BLOCK_H
        local rule = win:CreateTexture(nil, "BORDER")
        rule:SetPoint("TOPLEFT", 20, top)
        rule:SetPoint("TOPRIGHT", -20, top)
        rule:SetHeight(1)
        rule:SetColorTexture(unpack(S.C.line))
        local icon = S.Icon(win, q.icon, 22)
        icon:SetPoint("TOPLEFT", 20, top - 16)
        local title = S.Text(win, 15)
        title:SetPoint("LEFT", icon, "RIGHT", 10, 0)
        title:SetText(q.title)
        local block = { q = q, cards = {} }
        for i, choice in ipairs(q.choices) do
            local card = Card(win, CARD_W, CARD_H, choice[1], function()
                -- the picked one clicked again: this question is left as it is
                if answers[q.key] == i - 1 then answers[q.key] = nil else answers[q.key] = i - 1 end
                Paint()
            end)
            card:SetPoint("TOPLEFT", 20 + LEFT_W + (i - 1) * (CARD_W + GAP), top - 8)
            card.name:SetPoint("TOPLEFT", 14, -10)
            card.blurb = S.Text(card, 12, S.C.muted)
            card.blurb:SetPoint("TOPLEFT", 14, -32)
            card.blurb:SetWidth(CARD_W - 26)
            card.blurb:SetWordWrap(true)
            card.blurb:SetJustifyV("TOP")
            card.blurb:SetSpacing(2)
            block.cards[i] = card
        end
        win.blocks[n] = block
    end

    win.apply = S.Button(win, "Apply and reload", function()
        local on, off, reload = YR.WelcomeApply(answers)
        win:Hide()
        YR.Print(("%d turned on, %d turned off. Change anything in /hs."):format(on, off))
        if reload and ReloadUI then ReloadUI() end
    end, "primary", 170)
    win.apply:SetPoint("BOTTOMRIGHT", -20, 16)
    local each = S.Button(win, "All settings", function()
        win:Hide()
        if not (_G.HeadstartWindow and _G.HeadstartWindow:IsShown()) then YR:ToggleSettings() end
    end, nil, 120)
    each:SetPoint("RIGHT", win.apply, "LEFT", -8, 0)
    each.tip = "Headstart's window: a page for each of these, with every choice it has"
end

--- The welcome window. A new install (nothing answered yet) opens on Recommended; after that on what
--- you have now, a question whose things you set one by one left unanswered.
function YR.WelcomeShow()
    Build()
    answers = YR.WelcomeNow()
    if YippRouteDB.welcome and not YippRouteDB.welcomeSeen then
        local q = YR.WelcomeQuick("recommended")
        for k, v in pairs(q) do answers[k] = v end
    end
    YippRouteDB.welcomeSeen = true
    Paint()
    win:Show()
    return true
end

function YR.WelcomeToggle()
    if win and win:IsShown() then win:Hide() return false end
    return YR.WelcomeShow()
end
