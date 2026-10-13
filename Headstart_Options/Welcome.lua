-- Welcome: a small window that finds out with you how much of Headstart you want, and turns that on.
--   Not everyone wants all of it, and what people want isn't one dial from "little" to "much": someone
--   wants every bar and nothing automated, someone else no bars (a UI suite draws those) and the
--   restocking. So it is four questions, each answered by itself:
--     Routes of your own      Off / On          your runs recorded as you level and saved as routes of your
--                             own, played back in RestedXP; level splits (a reload). Headstart ships no routes
--     On your screen          Nothing / Essentials / Everything
--                             Essentials: flight timer, camp icon, loot feed, chat log, death recap,
--                             instance tracker, better-gear notes. Everything: the XP bar (many have
--                             another addon draw theirs, so it is not among the essentials), the swing
--                             timer, trinket buttons, Invite and Leave buttons and the movable talent window
--     Does things for you     Nothing / For friends / Everything
--                             For friends: accepts invites and shared quests from guildies and friends, invites
--                             the ones who whisper "inv" - no gold, no items. Everything: also restock and
--                             training (spend gold), banking (moves items), a screenshot at every ding
--     New characters          Off / On          Character setup: the bar planner, a main's bars on an alt
--   Each answer is a card that says what it turns on; that is all the words on the window. A question
--   left unanswered (click the picked answer again) is left as it is. What another addon you have
--   already does (its feature on) is left off whatever you answer, and named.
--   Three quick picks answer all four at once: Minimal, Recommended, Everything.
--   Then: Before you play. Once the answers are applied (and any time, from its button) the window
--   lists what is now on that deserves a look before the first quest - what spends gold, what moves
--   your things, what stands where one of Blizzard's bars was, what Character setup can and can't put
--   back - each in two lines with a button that opens its settings. Only what is on is listed, so
--   with nothing risky on it is one line: installing changed nothing of yours.
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
        F("xpbar", "XP bar", "screen", 2, function() return YR.XPBarOn() end, function(on) YR.XPBarDB().on = on YR.XPBarApply() end),
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
        F("pickRewards", "quest rewards picked up to level 10", "acts", 2, function() return YR:RewardSettings().on == true end,
            function(on)
                YippRouteDB.pickRewards = on and true or false          -- (what a class starts with)
                YR:RewardSettings().on = on and true or false           -- and this class now
            end),
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
        { "Essentials", "Flight timer, camp icon, loot feed, chat log, death recap, instance tracker, upgrade alerts, and your other characters' bags and gold." },
        { "Everything", "Adds the XP bar (in place of Blizzard's), the swing timer, trinket buttons, and Invite and Leave buttons." } } },
    { key = "acts", title = "Automation", icon = 133784, choices = {
        { "Nothing", "Headstart buys, moves, accepts and picks nothing for you." },
        { "Friends only", "Accepts invites and shared quests from friends and guild members, and invites them when they whisper \"inv\". Never spends gold or moves items." },
        { "Everything", "Adds restock and auto-train (they spend gold), bank deposit (moves items), quest rewards picked, level-up screenshots." } } },
    { key = "setup", title = "New characters", icon = 134166, choices = {
        { "Off", "Nothing is placed on your bars. Right for a character you have already set up." },
        { "On", "Bar profiles and the planner, and your bars, macros and interface put on new characters. Nothing changes until you press Apply there." } } },
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
-- Before you play: what is on that deserves a look, with where to set it
-- ---------------------------------------------------------------------------
--- { { name, note, page, section }, ... }: only what is on now, what costs most first. page: the
--- settings page its button opens; section: the card on it (nil: the page). Six of these at most
--- (the window has eight lines), then two that are there whatever is on: what installing did not
--- touch, and what is new on your screen. A note is two lines of the window: some 220 letters.
local MOST = 6
function YR.WelcomeChecks()
    local list = {}
    local function Add(name, note, page, section) list[#list + 1] = { name = name, note = note, page = page, section = section } end
    if YR.Option("autoTrain") then
        Add("Class trainer spends gold", "Buys your class's spells as you open your class trainer, on every character (it asks the"
            .. " first time on each). Silver to keep starts at 2 silver and is per class: set it, or set spells to Never. Shift"
            .. " skips it.", "trainer", "Class trainer")
    end
    if YR.Option("restock") then
        Add("Restock spends gold", "Buys reagents, ammo and your own list at every vendor, on every character. Gold to keep is 0"
            .. " until you set it. Hold Shift as you open a vendor to skip it.", "vendors", "Restock")
    end
    if YippRouteDB.mailAuto == true then
        Add("Mail to alt sends without asking", "Every character on the realm mails its mats to the name you gave, at every"
            .. " mailbox. Check the name: mail to a wrong name is gone. Hold Shift as you open the mailbox to skip it.",
            "bags", "Mail to alt")
    end
    if YR.Option("bankAuto") then
        Add("Bank deposit moves your items", "Crafting mats and recipes you can't learn yet go into the bank when you open it."
            .. " Nothing is lost: look in the bank before you miss something. Which mats is set on its page; Shift skips it.",
            "bags", "Bank deposit")
    end
    if YR:RewardSettings().on == true then
        Add("Quest rewards are picked for you", "Up to the level on its page (10), a reward is chosen and the quest handed in."
            .. " The pick is final. It leaves the choice to you when a green is offered; hold Shift to choose yourself.",
            "gear", "Quest rewards")
    end
    if YR.AcceptInvitesSet() ~= "off" or YR.WhisperInviteSet() ~= "off" then
        Add("Invites are answered for you", "Group invites from friends and guild members are accepted, and one of them who"
            .. " whispers \"inv\" is invited. Keep both off Anyone on a character strangers can whisper.", "group", "Invites")
    end
    if YR.SetupOn() then
        Add("Character setup changes bars only when you say so", "Nothing changes until you press Apply, and a character in play"
            .. " is asked first. Bars and macros are kept before every change (/ysetup undo, /ysetup undo first). Chat and Edit"
            .. " Mode can't be put back: answer Bars only.", "character")
    end
    if YR.RoutesOn() then
        Add("Routes: what acts for you is still off", "Release at a death skip, abandoning skipped quests and sharing or accepting"
            .. " route quests each have their own switch on the route's settings, off until you turn them on.", "route")
    end
    if YR.XPBarOn() then
        Add("The XP bar stands in for Blizzard's", "Blizzard's XP bar is hidden while ours shows. If another addon already draws"
            .. " your XP bar, turn ours off. It moves in Arrange (/hs move).", "xpbar", "XP bar")
    end
    for i = #list, MOST + 1, -1 do list[i] = nil end
    if #list == 0 then
        Add("Nothing here needs setting", "Nothing that spends gold, moves your items or answers for you is on.")
    end
    Add("Installing changed nothing of yours", "No action bar, macro, key binding, Edit Mode layout, chat window or game setting was"
        .. " touched, and no other addon's settings. Character setup is the only part that changes those, and only when you"
        .. " press Apply there.")
    Add("New on your screen", "The camp icon, the instance counter and, while you fly, the flight timer (it stands in for"
        .. " RestedXP's). Drag them where you want them with /hs move, or turn each off on its page. Journey counts quietly.")
    return list
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

-- The welcome has been seen: asked for by hand, or a click in it. (Not for having been put up: a new
-- install's was put up under a new character's opening flight and closed unseen. Core.lua, WelcomeFirst.)
local function Seen() YippRouteDB.welcomeSeen = true end

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
    card:SetScript("OnClick", function(...) Seen() return onClick(...) end)
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

-- A check's button: its page opened, and the card on it (found as the search finds it, which opens
-- a folded card).
local function OpenCheck(check)
    if not check.page then return end
    win:Hide()
    YR:ShowSettingsTab(check.page)
    if not check.section then return end
    for _, e in ipairs(YR.SettingsIndex()) do
        if e.card and e.key == check.page and e.label == check.section then YR.SettingsGo(e) return end
    end
end

local ROWS, ROW_H = 8, 54
local view          -- the "Before you play" list, once it has been asked for
--- Before you play, over the questions: the list as it stands now.
local function ShowChecks()
    local S = YR.Style
    local v = view
    if not v then
        v = CreateFrame("Frame", nil, win)
        v:SetPoint("TOPLEFT", 1, -49)
        v:SetPoint("BOTTOMRIGHT", -1, 1)
        v:SetFrameLevel(win:GetFrameLevel() + 20)
        v:EnableMouse(true)
        S.Fill(v, S.C.window)
        v.title = S.Text(v, 17)
        v.title:SetPoint("TOPLEFT", 20, -14)
        v.title:SetText("Before you play")
        v.sub = S.Text(v, 12, S.C.muted)
        v.sub:SetPoint("LEFT", v.title, "RIGHT", 12, -1)
        v.sub:SetText("what is on now that is worth a look first - each with where to set it")
        v.rows = {}
        for i = 1, ROWS do
            local r = CreateFrame("Frame", nil, v)
            r:SetPoint("TOPLEFT", 20, -44 - (i - 1) * ROW_H)
            r:SetSize(W - 40, ROW_H - 6)
            S.Fill(r, S.C.card)
            S.Border(r, S.C.line)
            r.name = S.Text(r, 14)
            r.name:SetPoint("TOPLEFT", 14, -7)
            r.note = S.Text(r, 11, S.C.muted)
            r.note:SetPoint("TOPLEFT", 14, -25)
            r.note:SetWidth(W - 40 - 28 - 96)
            r.note:SetWordWrap(true)
            r.note:SetJustifyV("TOP")
            r.open = S.Button(r, "Open", function() OpenCheck(r.check) end, nil, 80)
            r.open:SetPoint("RIGHT", -10, 0)
            v.rows[i] = r
        end
        local done = S.Button(v, "Done", function() win:Hide() end, "primary", 110)
        done:SetPoint("BOTTOMRIGHT", -19, 15)
        local back = S.Button(v, "Back to the choices", function() v:Hide() end, nil, 160)
        back:SetPoint("RIGHT", done, "LEFT", -8, 0)
        view = v
    end
    local list = YR.WelcomeChecks()
    for i, r in ipairs(v.rows) do
        local check = list[i]
        r:SetShown(check ~= nil)
        if check then
            r.check = check
            r.name:SetText(check.name)
            r.note:SetText(check.note)
            r.open:SetShown(check.page ~= nil)
        end
    end
    v:Show()
end
YR.WelcomeShowChecks = function() if win then ShowChecks() end end

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

    -- its own Close button is an answer too (Escape and whatever else closes every window is not)
    win.close:HookScript("OnClick", Seen)
    win.apply = S.Button(win, "Apply and reload", function()
        Seen()
        local on, off, reload = YR.WelcomeApply(answers)
        YR.Print(("%d turned on, %d turned off. Change anything in /hs."):format(on, off))
        if reload and ReloadUI then
            YR.Print("after the reload, /headstart start has Before you play: what is on that is worth a look first.")
            win:Hide()
            ReloadUI()
            return
        end
        -- what is on now that deserves a look before the first quest
        ShowChecks()
    end, "primary", 170)
    win.apply:SetPoint("BOTTOMRIGHT", -20, 16)
    local each = S.Button(win, "All settings", function()
        Seen()
        win:Hide()
        if not (_G.HeadstartWindow and _G.HeadstartWindow:IsShown()) then YR:ToggleSettings() end
    end, nil, 120)
    each:SetPoint("RIGHT", win.apply, "LEFT", -8, 0)
    each.tip = "Headstart's window: a page for each of these, with every choice it has"
    local checks = S.Button(win, "Before you play", function() Seen() ShowChecks() end, nil, 150)
    checks:SetPoint("RIGHT", each, "LEFT", -8, 0)
    checks.tip = "What is on now that is worth a look first: what spends gold, what moves your things, what Character setup can and can't put back"
end

--- The welcome window. A new install (nothing answered yet) opens on Recommended; after that on what
--- you have now, a question whose things you set one by one left unanswered.
--- first: put up unasked, on a new install (Core.lua, YR.WelcomeFirst) - then it is not seen yet for
--- having been put up: that is said by a click in it (Seen) or by its staying up (WelcomeFirst).
function YR.WelcomeShow(first)
    Build()
    answers = YR.WelcomeNow()
    if YippRouteDB.welcome and not YippRouteDB.welcomeSeen then
        local q = YR.WelcomeQuick("recommended")
        for k, v in pairs(q) do answers[k] = v end
    end
    if not first then Seen() end
    if view then view:Hide() end
    Paint()
    win:Show()
    return true
end

function YR.WelcomeToggle()
    if win and win:IsShown() then win:Hide() return false end
    return YR.WelcomeShow()
end
