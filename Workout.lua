-- Level-up workout (the owner, 2026-11-04: a training section you turn on - "when you level, you have to do x push-ups,
-- either the level you reach or the stamina you get or something like that. Meant to help get a little exercise, and
-- for fun"). At a ding a small window says how many: push-ups, squats or sit-ups, or the three in turn, one a level -
-- as many as your new level, half of it, or ten for each point of Stamina the level gave you. Done counts them; the x
-- puts the window away until your next level, and what you owe adds up: it is there again at the next ding and at the
-- login. Never in a fight: it waits for the fight to end. Placed in Arrange (workoutPos).
--   Off until you turn it on (Core.lua STARTS_OFF): before that nothing of it is made and nothing is listened for.
--   This character's (YippSetupCharDB.workout): owe = { [kind] = count } until Done, from/to = the levels it is for,
--   done = { [kind] = count }. Every character's together: YippRouteDB.workoutDone = { [kind] = count }.
local _, YR = ...

local KINDS = { pushups = { "push-up", "push-ups" }, squats = { "squat", "squats" }, situps = { "sit-up", "sit-ups" } }
local TURNS = { "pushups", "squats", "situps" }          -- (also the order they are named in)
local STAMINA_TIMES = 10                                 -- (a level gives 1 to 4 Stamina: about 10 to 40 at a time)
local ICON = 136101                                      -- (Interface\Icons\Spell_Nature_Strength)
local W, PAD, ICON_SIZE = 260, 10, 36

local function Num(v)
    if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) or v ~= v then return nil end
    return v
end

--- The exercise for a level: the one chosen, or with "In turn" the three one after another.
function YR.WorkoutKind(level)
    local k = YippRouteDB.workoutKind
    if k == "turns" then return TURNS[((Num(level) or UnitLevel("player") or 1) % #TURNS) + 1] end
    return KINDS[k] and k or "pushups"
end

--- How many for a level: the level itself, half of it, or ten a point of the Stamina it gave (the level, where the game
--- doesn't say). 0: nothing that level.
function YR.WorkoutCount(level, stamina)
    level = Num(level) or 0
    local how = YippRouteDB.workoutCount
    if how == "half" then return math.ceil(level / 2) end
    if how == "stamina" then
        stamina = Num(stamina)
        if stamina then return math.max(0, math.floor(stamina)) * STAMINA_TIMES end
    end
    return math.floor(level)
end

--- "1 push-up", "23 push-ups".
function YR.WorkoutWords(n, kind)
    local w = KINDS[kind] or KINDS.pushups
    return n .. " " .. (n == 1 and w[1] or w[2])
end

-- this character's: what is owed and what is done, made whole whatever an older or edited file holds
local function Mine()
    if type(YippSetupCharDB) ~= "table" then return nil end
    local w = YippSetupCharDB.workout
    if type(w) ~= "table" then
        w = {}
        YippSetupCharDB.workout = w
    end
    if type(w.owe) ~= "table" then w.owe = {} end
    if type(w.done) ~= "table" then w.done = {} end
    return w
end
local function Everyone()
    if type(YippRouteDB.workoutDone) ~= "table" then YippRouteDB.workoutDone = {} end
    return YippRouteDB.workoutDone
end

-- what is owed, in TURNS order: { { kind, count }, ... }
local function Owed(w)
    local list = {}
    for _, kind in ipairs(TURNS) do
        local n = Num(w and w.owe[kind])
        if n and n > 0 then list[#list + 1] = { kind, math.floor(n) } end
    end
    return list
end

--- This character's, and every character's, done so far: { [kind] = count } each.
function YR.WorkoutDone()
    local w = Mine()
    return w and w.done or {}, Everyone()
end

--- A done-so-far table in words: "412 push-ups, 120 squats", or nil when nothing is done.
function YR.WorkoutDoneWords(done)
    local parts = {}
    for _, kind in ipairs(TURNS) do
        local n = Num(done and done[kind])
        if n and n > 0 then parts[#parts + 1] = YR.WorkoutWords(math.floor(n), kind) end
    end
    return #parts > 0 and table.concat(parts, ", ") or nil
end

-- ---------------------------------------------------------------------------
-- The window: the heading, how many in large letters, what this character has done, and Done
-- ---------------------------------------------------------------------------
local card, sample, waiting = nil, false, false
local Show

local function Place()
    card:ClearAllPoints()
    local p = YippRouteDB.workoutPos
    if type(p) == "table" and Num(p[1]) and Num(p[2]) then
        card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else
        card:SetPoint("TOP", UIParent, "TOP", 0, -370)         -- (under where the trainer's window comes)
    end
end

local function Done()
    if sample then return end
    local w = Mine()
    if not w then return end
    local all = Everyone()
    local list = Owed(w)
    for _, o in ipairs(list) do
        w.done[o[1]] = (Num(w.done[o[1]]) or 0) + o[2]
        all[o[1]] = (Num(all[o[1]]) or 0) + o[2]
    end
    w.owe, w.from, w.to = {}, nil, nil
    card:Hide()
    if #list > 0 and UIErrorsFrame and UIErrorsFrame.AddMessage then
        local so = YR.WorkoutDoneWords(w.done)
        UIErrorsFrame:AddMessage("Workout done" .. (so and (" - so far: " .. so) or "") .. ".", 0.45, 0.82, 0.50)
    end
end

local function Later()
    if sample then return end
    card:Hide()                    -- (what is owed stays: it adds up, and comes back at the next ding and the login)
end

local function Build()
    local S = YR.Style
    card = CreateFrame("Frame", "HeadstartWorkout", UIParent)
    card:SetFrameStrata("MEDIUM")
    card:SetClampedToScreen(true)
    card:SetMovable(true)
    card:EnableMouse(true)
    S.Fill(card, S.C.window)
    S.Border(card, S.C.lineHi)
    S.Shadow(card, 14, 4, 0.6)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(ICON_SIZE, ICON_SIZE)
    card.icon:SetPoint("TOPLEFT", PAD, -PAD)
    card.icon:SetTexture(ICON)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    card.head = S.Text(card, 11, S.C.muted)
    card.head:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, 0)
    card.what = S.Text(card, 18, S.C.text)
    card.what:SetPoint("BOTTOMLEFT", card.icon, "BOTTOMRIGHT", 10, 0)
    card.so = S.Text(card, 11, S.C.sub)
    card.so:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", PAD, PAD + 6)
    card.done = S.Button(card, "Done", Done, "primary", 76)
    card.done:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -PAD, PAD)
    card.close = S.CloseX(card, Later, "Later: put away until your next level. What you owe adds up.")
    card.close:SetPoint("TOPRIGHT", card, "TOPRIGHT", -4, -4)
    -- a ding in a fight: it comes when the fight ends
    card:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            if waiting then
                waiting = false
                Show()
            end
        end
    end)
    card:Hide()
    Place()
end

local function Width(fs, fallback)
    local w = fs:GetStringWidth()
    return type(w) == "number" and w or fallback
end

-- what is owed, drawn: the levels it is for, and each exercise's count
local function Paint(list, from, to)
    local S = YR.Style
    local levels = (from and to and from ~= to) and ("LEVELS " .. from .. "-" .. to) or ("LEVEL " .. (to or from or UnitLevel("player")))
    card.head:SetText(levels .. "  ·  WORKOUT")
    local words = {}
    for _, o in ipairs(list) do words[#words + 1] = YR.WorkoutWords(o[2], o[1]) end
    card.what:SetText(table.concat(words, " + "))
    local w = Mine()
    local done = {}
    for _, o in ipairs(list) do done[o[1]] = w and w.done[o[1]] end
    local so = YR.WorkoutDoneWords(done)
    card.so:SetText(so and ("Done so far: " .. so) or "Your first one on this character")
    card.so:SetTextColor(unpack(so and S.C.sub or S.C.muted))
    local inner = math.max(Width(card.head, 150), Width(card.what, 120)) + ICON_SIZE + 10
    local foot = Width(card.so, 150) + 12 + 76
    card:SetSize(math.max(W, math.ceil(math.max(inner + 24, foot)) + 2 * PAD), PAD * 2 + ICON_SIZE + 12 + 28)
end

--- The window, with what this character owes; nothing owed: put away. In a fight it waits for the fight to end.
function Show()
    if not YR.Option("workout") then return false end
    local w = Mine()
    local list = Owed(w)
    if #list == 0 then
        if card and not sample then card:Hide() end
        return false
    end
    if not card then Build() end
    if InCombatLockdown() then
        waiting = true
        card:RegisterEvent("PLAYER_REGEN_ENABLED")
        return true
    end
    sample = false
    Paint(list, Num(w.from), Num(w.to))
    card:Show()
    return true
end
YR.WorkoutShow = Show

--- A level reached: what it asks for is owed, and the window comes (after the ding's own animation).
function YR.WorkoutOwe(level, stamina)
    level = Num(level)
    if not level or level < 1 or not YR.Option("workout") then return end
    local n = YR.WorkoutCount(level, stamina)
    local w = Mine()
    if n <= 0 or not w then return end
    local kind = YR.WorkoutKind(level)
    w.owe[kind] = (Num(w.owe[kind]) or 0) + n
    local had = Num(w.from)
    w.from = had and math.min(had, level) or level
    w.to = math.max(Num(w.to) or level, level)
    C_Timer.After(2, Show)
end

--- The button on the settings page and /headstart workout: what you owe, or else one for your level now.
function YR.WorkoutNow()
    if not YR.Option("workout") then
        YR.Print("the level-up workout is off: turn it on under Reminders (/headstart).")
        return false
    end
    local w = Mine()
    if w and #Owed(w) == 0 then
        local level = UnitLevel("player") or 1
        local kind = YR.WorkoutKind(level)
        w.owe[kind] = YR.WorkoutCount(level, nil)
        if (w.owe[kind] or 0) <= 0 then w.owe[kind] = math.max(1, level) end
        w.from, w.to = level, level
    end
    return Show()
end

--- For Arrange: the window, with a sample on it while it is being placed (sample).
function YR.WorkoutFrame(placing)
    if not YR.Option("workout") then return nil end
    if placing ~= nil then
        if placing then
            if not card then Build() end
            if not card:IsShown() then
                sample = true
                Paint({ { YR.WorkoutKind(UnitLevel("player")), 20 } }, 20, 20)
                card:Show()
            end
        elseif sample then
            sample = false
            card:Hide()
            Show()                  -- (what was owed before Arrange opened comes back)
        end
    end
    return card
end
function YR.WorkoutSave()
    if not card then return end
    local l, t = card:GetLeft(), card:GetTop()
    if l and t then YippRouteDB.workoutPos = { l, t } end
end
function YR.WorkoutReset()
    YippRouteDB.workoutPos = nil
    if card then Place() end
end

-- ---------------------------------------------------------------------------
-- Listening: the ding, while it is on. At the login (or as it is turned on), what is still owed comes back.
-- ---------------------------------------------------------------------------
local function OnLevel(_, event, level, _, _, _, _, _, _, stamina)
    if event == "PLAYER_LEVEL_UP" then YR.WorkoutOwe(level, stamina) end
end

local declared
function YR.StartWorkout()
    if declared then return end
    declared = true
    YR.Part(function() return YR.Option("workout") end, { "PLAYER_LEVEL_UP" }, OnLevel, {
        start = function()
            C_Timer.After(8, function()
                if YR.AfterWelcome then YR.AfterWelcome(Show) else Show() end
            end)
        end,
        stop = function()
            waiting = false
            if card then
                card:UnregisterAllEvents()
                card:Hide()
            end
        end,
    })
end
