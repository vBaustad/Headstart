-- The tour: hints over Headstart's own window, one at a time - a bubble in the accent colour that points at
-- the part it is about, which a ring lights up - read through with Next and Back, or skipped. On a new
-- install it opens with the window a few seconds after the first login (Core.lua, YR.WelcomeFirst), and any
-- time from the window's Tour button and /headstart start.
--   It turns nothing on and asks nothing: it shows where things are, and you turn on what you want where it
--   is. "A hundred percent the most important thing is that nothing is turned on without the player knowing
--   what they turn on" (the owner, 2026-10-14) - and the hints of a new application, skipped or looked
--   through, standing over the program itself. It was a window of its own: four questions with an
--   Everything (until 0.10.0-beta7), then for a day a tour of four pages with Nothing / Minimal /
--   Recommended. Its buttons sent you into the settings and nothing brought you back to it, its colours
--   were dull, and what Recommended turned on was ours to choose, not the player's.
--   Part of Headstart_Options (the load-on-demand window addon). The parts pointed at are the window's,
--   found by name (Editor.lua, YR.TourTarget).
local YR = _G.HeadstartNS

-- The hints, in order. page: the QoL page the window shows for it (nil: as it is); at: what it points at
-- (YR.TourTarget; nil, or not on screen: the bubble stands in the middle of the window); side: where the
-- bubble stands from it.
local STEPS = {
    { page = "home", title = "Welcome to Headstart", next = "Show me around",
      text = "Nothing that acts for you is on, and nothing on your bars has changed. Here is where everything is,"
          .. " a hint at a time - or skip it, and come back with Tour at the bottom." },
    { page = "home", at = "search", side = "right", title = "Find any setting",
      text = "Type what you are after - cinematic, repair, trainer - and pick it from the list." },
    { page = "home", at = "menu:home", side = "right", title = "All features",
      text = "Every feature is a card on this page. Its switch turns it on; a click on the card opens its settings." },
    { page = "home", at = "automation", side = "below", title = "Automation",
      text = "What spends gold, moves your items or answers for you: the trainer, restock, the bank and mail."
          .. " Each is off until you turn it on here." },
    { page = "home", at = "menu:general", side = "right", title = "General",
      text = "The intro cinematic skipped, Headstart's minimap button, the colour of its windows - and Put back everything:"
          .. " your screen as it was before Headstart, any time you want it." },
    { at = "interface", side = "below", title = "Interface",
      text = "What Headstart puts on your screen - the XP bar, combat bars, trinkets - and what it does to Blizzard's"
          .. " bars, windows and talent window. Its own menu, and its cards are on All features too." },
    { at = "setup", side = "below", title = "Character setup",
      text = "Save your bars and interface on the character you play, plan bars from the ones you have, and put"
          .. " them on your other characters. A character's own bars are kept the first time you open it there." },
    { at = "levelling", side = "below", title = "Routes",
      text = "Your runs recorded (This run, and the level splits), and help with a RestedXP guide: skip a quest, release"
          .. " at a death skip, the level pace. Off until you turn it on there." },
    { at = "arrange", side = "above", title = "Arrange",
      text = "Move Headstart's bars and windows on your screen. Also /hs move." },
    { page = "home", at = "qol", side = "belowright", title = "Quality of life", next = "Done",
      text = "Everything on this tab off at once, and back as you left it." },
}
function YR.TourSteps() return STEPS end

local BUBBLE_W, PAD = 320, 14
local tour, ring, step

-- The tour has been seen: asked for by hand, or a click in it. (Not for having been put up: a new
-- install's was put up under a new character's opening flight and closed unseen. Core.lua, WelcomeFirst.)
local function Seen() YippRouteDB.welcomeSeen = true end

-- A button on the bubble: dark on the accent (filled), or words alone.
local function Button(parent, label, onClick, filled)
    local S = YR.Style
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(24)
    if filled then S.Rounded(b, "BACKGROUND", "round"):SetVertexColor(unpack(S.C.onAccent)) end
    b.text = S.Text(b, 12, filled and S.C.text or S.C.onAccent)
    b.text:SetPoint("CENTER")
    function b:SetLabel(t)
        self.text:SetText(t)
        self:SetWidth(math.max(filled and 70 or 40, (self.text:GetStringWidth() or 0) + (filled and 28 or 12)))
    end
    b:SetLabel(label)
    b:SetScript("OnEnter", function(self) self.text:SetAlpha(0.75) end)
    b:SetScript("OnLeave", function(self) self.text:SetAlpha(1) end)
    b:SetScript("OnClick", function(...) Seen() return onClick(...) end)
    return b
end

local Finish

-- Where the bubble stands: beside, under or over what it points at, with its point turned to it.
local function Place(target, side)
    local win = _G.HeadstartWindow or UIParent
    tour:ClearAllPoints()
    tour.point:ClearAllPoints()
    ring:ClearAllPoints()
    if not target then
        tour:SetPoint("CENTER", win, "CENTER", 0, 40)
        tour.point:Hide()
        ring:Hide()
        return
    end
    ring:SetPoint("TOPLEFT", target, "TOPLEFT", -5, 5)
    ring:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 5, -5)
    ring:Show()
    ring.pulse:Stop()
    ring.pulse:Play()
    tour.point:Show()
    if side == "right" then
        tour:SetPoint("LEFT", target, "RIGHT", 18, 0)
        tour.point:SetPoint("CENTER", tour, "LEFT", 0, 0)
    elseif side == "above" then
        tour:SetPoint("BOTTOM", target, "TOP", 0, 18)
        tour.point:SetPoint("CENTER", tour, "BOTTOM", 0, 0)
    elseif side == "belowright" then
        tour:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", 0, -18)
        tour.point:SetPoint("CENTER", tour, "TOPRIGHT", -40, 0)
    else
        tour:SetPoint("TOP", target, "BOTTOM", 0, -18)
        tour.point:SetPoint("CENTER", tour, "TOP", 0, 0)
    end
end

local function Show(i)
    step = i
    local s = STEPS[i]
    if s.page then YR:ShowSettingsTab(s.page) end
    local target = s.at and YR.TourTarget and YR.TourTarget(s.at)
    if target and not (target.IsVisible and target:IsVisible()) then target = nil end
    tour.title:SetText(s.title)
    tour.text:SetText(s.text)
    tour.count:SetText(("%d of %d"):format(i, #STEPS))
    tour.next:SetLabel(s.next or "Next")
    tour.back:SetShown(i > 1)
    tour.skip:SetShown(i < #STEPS)
    -- as tall as its words (and never less than they would need at 12px, some six pixels a letter: a height
    -- read before the text is laid out can come back short)
    local lines = math.ceil(#s.text * 6 / (BUBBLE_W - 2 * PAD))
    local textH = math.max(tonumber(tour.text:GetStringHeight()) or 0, lines * 15)
    tour:SetHeight(PAD + 18 + 6 + math.ceil(textH) + 18 + 24 + PAD - 4)
    Place(target, s.side)
end

function Finish()
    YippRouteDB.welcome = nil               -- (a new install's: looked at, or skipped)
    step = nil
    tour:Hide()
end

local function Build()
    local win = _G.HeadstartWindow or UIParent
    if tour then
        if tour:GetParent() ~= win then tour:SetParent(win) ring:SetParent(win) end
        return
    end
    local S = YR.Style
    tour = CreateFrame("Frame", "HeadstartTour", win)
    tour:SetSize(BUBBLE_W, 120)
    tour:SetFrameStrata("DIALOG")
    tour:SetFrameLevel((win.GetFrameLevel and win:GetFrameLevel() or 0) + 200)
    tour:EnableMouse(true)
    -- the bubble: the accent, and a point of the same colour turned to what it is about
    tour.point = tour:CreateTexture(nil, "BACKGROUND")
    tour.point:SetSize(16, 16)
    tour.point:SetTexture("Interface\\Buttons\\WHITE8X8")
    tour.point:SetVertexColor(unpack(S.C.accent))
    if tour.point.SetRotation then tour.point:SetRotation(math.rad(45)) end
    S.Rounded(tour, "BORDER", "round"):SetVertexColor(unpack(S.C.accent))
    tour.title = S.Text(tour, 15, S.C.onAccent)
    tour.title:SetPoint("TOPLEFT", PAD, -PAD)
    tour.count = S.Text(tour, 11, S.C.onAccent)
    tour.count:SetPoint("TOPRIGHT", -PAD, -PAD - 2)
    tour.count:SetAlpha(0.7)
    tour.text = S.Text(tour, 12, S.C.onAccent)
    tour.text:SetPoint("TOPLEFT", PAD, -PAD - 24)
    tour.text:SetWidth(BUBBLE_W - 2 * PAD)
    tour.text:SetJustifyH("LEFT")
    tour.text:SetJustifyV("TOP")
    tour.text:SetWordWrap(true)
    tour.text:SetSpacing(2)
    tour.next = Button(tour, "Next", function() if step == #STEPS then Finish() else Show(step + 1) end end, true)
    tour.next:SetPoint("BOTTOMRIGHT", -PAD + 4, PAD - 4)
    tour.back = Button(tour, "Back", function() Show(step - 1) end)
    tour.back:SetPoint("RIGHT", tour.next, "LEFT", -6, 0)
    tour.skip = Button(tour, "Skip", function() Finish() end)
    tour.skip:SetPoint("BOTTOMLEFT", PAD - 6, PAD - 4)
    -- the part it is about, ringed in the accent and breathing
    ring = CreateFrame("Frame", nil, win)
    ring:SetFrameStrata("DIALOG")
    ring:SetFrameLevel(tour:GetFrameLevel() - 1)
    S.Rounded(ring, "OVERLAY", "roundline"):SetVertexColor(unpack(S.C.accent))
    ring.pulse = ring:CreateAnimationGroup()
    ring.pulse:SetLooping("BOUNCE")
    local fade = ring.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.3)
    fade:SetDuration(0.7)
    fade:SetSmoothing("IN_OUT")
    ring:Hide()
    -- the window closed (Escape, its X): the tour with it, not back the next time the window opens
    tour:SetScript("OnHide", function(self)
        ring:Hide()
        if self:IsShown() then self:Hide() end
    end)
    tour:Hide()
end

--- The tour, from its first hint; Headstart's window opened on All features for it.
--- first: put up unasked, on a new install (Core.lua, YR.WelcomeFirst) - then it is not seen yet for
--- having been put up: that is said by a click in it (Seen) or by its staying up (WelcomeFirst).
function YR.WelcomeShow(first)
    YR:ShowSettingsTab("home")
    Build()
    if not first then Seen() end
    tour:Show()
    Show(1)
    return true
end

function YR.WelcomeToggle()
    if tour and tour:IsShown() then Finish() return false end
    return YR.WelcomeShow()
end

-- ---------------------------------------------------------------------------
-- The first login of a new install: a small card, not the whole window and the tour (the owner, 2026-10-29: "vi ikke
-- lar headstart åpne fullt når du logger inn for første gang. vi vil jo at de skal få den 'apply interface/
-- actionbars' typ"). What comes first on a new character is its bars, keys and interface: the card says nothing has
-- been changed and offers that, or the tour, or later. A button is an answer at once; its X and Escape only once it
-- has stood a few seconds (Core.lua, WelcomeFirst: the Escape that ends a new character's opening flight closes
-- every window, this one unseen).
-- An install made with YippYapp-oppsett gets it only with Classic and without Mango's settings: Headstart as new, and
-- the character's bars and keys from the tool already put on at its login (Headstart_Setup, AutoSetup). The card then
-- says so, and offers the tour or later. (With Mango's settings there is no "welcome" in the saved file.)
-- ---------------------------------------------------------------------------
local card
local FIRST = "Nothing that acts for you is on, and nothing on your bars has changed. Start with this character's bars,"
    .. " keys and interface - from a plan, or from a character you already have."
local DONE = "This character's bars and keys are on, from your setup. Everything else Headstart does is off until you"
    .. " turn it on: have a look around, or do it later."
-- whether Character setup has put this character's bars on (it notes when: YippSetupCharDB.applied)
local function SetUp()
    local c = _G.YippSetupCharDB            -- (Headstart's per-character saved table, from its TOC)
    return type(c) == "table" and c.applied ~= nil
end

local function Answered()
    Seen()
    YippRouteDB.welcome = nil
    if card then card:Hide() end
end

local function BuildCard()
    local S = YR.Style
    card = S.Window("HeadstartWelcomeCard", 520, 172, "Headstart is installed")
    card:ClearAllPoints()
    card:SetPoint("CENTER", 0, 140)
    card.text = S.Text(card, 13, S.C.sub)
    card.text:SetPoint("TOPLEFT", 20, -64)
    card.text:SetWidth(480)
    card.text:SetWordWrap(true)
    card.text:SetJustifyH("LEFT")
    card.text:SetSpacing(3)
    card.setup = S.Button(card, "Set up this character", function()
        Answered()
        if InCombatLockdown() then YR.Print("not in a fight: Character setup opens when you ask again (/headstart).") return end
        YR.SetSetupOn(true)
        YR:ToggleWindow("setup")
    end, "primary", 170)
    card.setup:SetPoint("BOTTOMLEFT", 16, 16)
    card.setup.tip = "Turns Character setup on and opens it: plan this class's bars, or save the bars, keys and"
        .. " interface of a character you like and put them on others"
    card.tour = S.Button(card, "Show me around", function()
        Answered()
        YR.WelcomeShow()
    end, nil, 130)
    card.tour.tip = "Headstart's window, with hints over it: where everything is"
    card.later = S.Button(card, "Later", Answered, "ghost", 80)
    card.later:SetPoint("BOTTOMRIGHT", -16, 16)
    card.later.tip = "/headstart or the minimap button open it any time"
end

--- The card a new install's first login gets (Core.lua, YR.WelcomeFirst).
function YR.WelcomeCard()
    if not card then BuildCard() end
    -- set up already: it says so, and Set up this character goes (Show me around takes its place)
    local done = SetUp()
    card.text:SetText(done and DONE or FIRST)
    card.setup:SetShown(not done)
    card.tour:ClearAllPoints()
    if done then card.tour:SetPoint("BOTTOMLEFT", 16, 16) else card.tour:SetPoint("LEFT", card.setup, "RIGHT", 8, 0) end
    card:Show()
    return true
end
