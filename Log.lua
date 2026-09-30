-- The run log: what the route model can't know from data. Per character, in YippRouteDB.runs:
--   ev     each with time, level, XP and position, and money (copper) as .money:
--            accept / complete / turnin (with the XP and money received)    a quest
--            level, death, release (to the Spirit Healer as a ghost), alive (back in the body)
--            kill (XP from anything but a quest), fight / peace (combat starts / ends)
--            step (RestedXP's current guide and step), hearth, zone, vendor / trainer / flight
--            buy (item and count, from a vendor), learn (a spell learned from a trainer)
--            sell (item and count, to a vendor), loot (a quest item, or one the route needs)
--            stop / resume (the player ended the run, or carried on after all)
--            skill (a profession or Cooking went up: name and new rank; weapon skills are left out)
--   track  a position sample every 2 seconds: { time, map, x, y, level, XP, flags }
--          flags: 1 in combat, 2 dead or a ghost, 4 casting or channelling (eating, crafting, hearth)
local _, YR = ...

local SAMPLE = 2
local HEARTHSTONE = 8690
local run, ticker
local complete = {}      -- questID -> true once its objectives were done (to log that moment once)
local lastXP, lastMax, lastLevel, turnedInAt
local lastGuide, lastStep
local trainerOpen = false

local function Add(kind, questID, extra)
    local map, x, y = YR.Position()
    local e = { time(), kind, questID or 0, UnitLevel("player"), UnitXP("player"), map or 0, x or 0, y or 0 }
    if extra then for k, v in pairs(extra) do e[k] = v end end
    -- money on every event: what training and vendors really cost is the difference across them
    e.money = e.money or GetMoney()
    run.ev[#run.ev + 1] = e
end

-- RestedXP's guide and step: logged when it changes, so a run can be timed step by step.
local function WatchStep()
    local rxp = RXP
    local guide = type(rxp) == "table" and rxp.currentGuide
    local step = type(RXPCData) == "table" and RXPCData.currentStep
    if type(guide) ~= "table" or not step then return end
    local name = guide.name or guide.displayname
    if name ~= lastGuide or step ~= lastStep then
        lastGuide, lastStep = name, step
        Add("step", nil, { guide = name, step = step })
    end
end

local function Flags()
    local f = 0
    if UnitAffectingCombat("player") then f = f + 1 end
    if UnitIsDeadOrGhost("player") then f = f + 2 end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then f = f + 4 end
    return f
end

local function Sample()
    if run.stopped then return end
    local map, x, y = YR.Position()
    if map then
        run.track[#run.track + 1] = { time(), map, x, y, UnitLevel("player"), UnitXP("player"), Flags() }
    end
    WatchStep()
end

-- The NPC you are talking to while a quest window is open: the quest giver or the turn-in.
local function Npc()
    local ok, name = pcall(UnitName, "npc")
    return ok and name or nil
end

-- The first pass after login only records what is already complete: those were finished in an
-- earlier session, and logging them "now" would make the objective look instant.
local primed = false
local function ScanCompletions()
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        local id = info and not info.isHeader and info.questID
        if id and not complete[id] and C_QuestLog.IsComplete(id) then
            complete[id] = true
            if primed then Add("complete", id) end
        end
    end
    primed = true
end

-- XP that didn't come from a quest turn-in is a kill (or exploring, rarely). A level-up in between
-- adds what was left of the old level.
local function XPChanged()
    local xp, level = UnitXP("player"), UnitLevel("player")
    if lastXP then
        local gained = level > lastLevel and (lastMax - lastXP + xp) or (xp - lastXP)
        if gained > 0 and turnedInAt ~= time() then Add("kill", nil, { xp = gained }) end
    end
    lastXP, lastMax, lastLevel = xp, UnitXPMax("player"), level
end

local NPC_WINDOWS = { MERCHANT_SHOW = "vendor", TRAINER_SHOW = "trainer", TAXIMAP_OPENED = "flight" }

local events = CreateFrame("Frame")
-- Your own loot, from the chat line the game prints ("You receive loot: [item]x2."): the patterns
-- come from the game's own strings, so they work in any language.
local LOOT_PATTERNS = {}
for _, s in ipairs({ LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF }) do
    if type(s) == "string" then
        LOOT_PATTERNS[#LOOT_PATTERNS + 1] = "^" .. s:gsub("([%(%)%.%[%]%-%+%*%?%^%$])", "%%%1")
            :gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$"
    end
end
local QUEST_ITEM = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12

local function Looted(msg)
    for _, pat in ipairs(LOOT_PATTERNS) do
        local link, count = msg:match(pat)
        local item = link and tonumber(link:match("item:(%d+)"))
        if item then
            local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(item)
            if classID == QUEST_ITEM or YR.RouteNeed(item) then
                Add("loot", nil, { item = item, count = tonumber(count) or 1, name = C_Item.GetItemNameByID(item) })
            end
            return
        end
    end
end

-- "Your skill in %s has increased to %d." Only professions (the ones a player can unlearn): weapon
-- and defense skill-ups come every few swings and say nothing about the route.
local SKILL_UP = type(ERR_SKILL_UP_SI) == "string" and ("^" .. ERR_SKILL_UP_SI:gsub("([%(%)%.%[%]%-%+%*%?%^%$])", "%%%1")
    :gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$")

local function Profession(name)
    for i = 1, GetNumSkillLines and GetNumSkillLines() or 0 do
        local skill, isHeader, _, _, _, _, _, isAbandonable = GetSkillLineInfo(i)
        if skill == name and not isHeader then return isAbandonable end
    end
end

local function SkillUp(msg)
    local name, rank = msg:match(SKILL_UP)
    if name and Profession(name) then Add("skill", nil, { name = name, rank = tonumber(rank) }) end
end

events:SetScript("OnEvent", function(_, event, a, b, c)
    if not run or run.stopped then return end
    if event == "QUEST_ACCEPTED" then
        local objectives = C_QuestLog.GetQuestObjectives(a)
        Add("accept", a, { npc = Npc(), title = C_QuestLog.GetTitleForQuestID(a),
            obj = type(objectives) == "table" and #objectives or 0 })
    elseif event == "QUEST_TURNED_IN" then
        complete[a] = nil
        turnedInAt = time()
        Add("turnin", a, { xp = b, money = c, npc = Npc() })
    elseif event == "QUEST_REMOVED" then
        complete[a] = nil
    elseif event == "QUEST_LOG_UPDATE" then
        ScanCompletions()
    elseif event == "PLAYER_XP_UPDATE" then
        XPChanged()
    elseif event == "PLAYER_LEVEL_UP" then
        Add("level", nil, { to = a })
    elseif event == "PLAYER_DEAD" then
        Add("death")
    elseif event == "PLAYER_ALIVE" then
        if UnitIsGhost("player") then Add("release") end
    elseif event == "PLAYER_UNGHOST" then
        Add("alive")
    elseif event == "PLAYER_REGEN_DISABLED" then
        Add("fight")
    elseif event == "PLAYER_REGEN_ENABLED" then
        Add("peace")
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if c == HEARTHSTONE then Add("hearth") end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        Add("zone", nil, { zone = GetZoneText() })
    elseif event == "TRAINER_CLOSED" then
        trainerOpen = false
    elseif event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "LEARNED_SPELL_IN_TAB" then
        -- only what a trainer taught: a level-up also "learns" passives nobody walks anywhere for
        if trainerOpen then Add("learn", nil, { spell = a, name = C_Spell.GetSpellName(a) }) end
    elseif event == "CHAT_MSG_LOOT" then
        if type(a) == "string" then Looted(a) end
    elseif event == "CHAT_MSG_SKILL" then
        if SKILL_UP and type(a) == "string" then SkillUp(a) end
    elseif NPC_WINDOWS[event] then
        if event == "TRAINER_SHOW" then trainerOpen = true end
        Add(NPC_WINDOWS[event], nil, { npc = Npc() })
    end
end)

-- What was bought, and from whom: the buy goes through BuyMerchantItem, which is not protected.
hooksecurefunc("BuyMerchantItem", function(index, quantity)
    if not run or run.stopped then return end
    local link = GetMerchantItemLink(index)
    local item = link and tonumber(link:match("item:(%d+)"))
    if item then
        Add("buy", nil, { item = item, count = quantity or 1, name = C_Item.GetItemNameByID(item), npc = Npc() })
    end
end)

local EVENTS = { "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_XP_UPDATE",
    "PLAYER_LEVEL_UP", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA", "MERCHANT_SHOW", "TRAINER_SHOW", "TRAINER_CLOSED",
    "TAXIMAP_OPENED", "CHAT_MSG_LOOT", "CHAT_MSG_SKILL" }

-- What was sold, and whether the route still needed it (Needs.lua warns about that).
YR:WatchSells(function(item, count)
    if run and not run.stopped then
        Add("sell", nil, { item = item, count = count, name = C_Item.GetItemNameByID(item), need = YR.RouteNeed(item) })
    end
end)

-- Stop run: this character's log ends here (the analysis cuts the run at it), until Resume.
function YR:StopLog()
    if run and not run.stopped then
        Add("stop")
        run.stopped = time()
    end
end

function YR:ResumeLog()
    if run and run.stopped then
        run.stopped = nil
        Add("resume")
    end
end
-- the "spell learned" event has a different name in the modern and the Classic API: whichever exists
local LEARNED = { "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB" }

function YR:StartLog()
    if not YippRouteDB.logging then return end
    -- a brand-new character is "Unknown" for its first moments: wait for the real name, or every new
    -- character's run lands under the same key
    local name = UnitFullName("player")
    if not name or name == UNKNOWNOBJECT or name == "Unknown" then
        C_Timer.After(2, function() YR:StartLog() end)
        return
    end
    local key = YR.CharKey()
    YippRouteDB.runs[key] = YippRouteDB.runs[key] or { started = time(), ev = {}, track = {} }
    run = YippRouteDB.runs[key]
    for _, e in ipairs(EVENTS) do events:RegisterEvent(e) end
    for _, e in ipairs(LEARNED) do pcall(events.RegisterEvent, events, e) end
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    ticker = ticker or C_Timer.NewTicker(SAMPLE, Sample)
end

function YR:SetLogging(on)
    YippRouteDB.logging = on
    if on then
        YR:StartLog()
    else
        events:UnregisterAllEvents()
        if ticker then ticker:Cancel() ticker = nil end
    end
    YR.Print("logging " .. (on and "on" or "off") .. ".")
end

function YR:LogStatus()
    local r = YippRouteDB.runs[YR.CharKey()]
    YR.Print(("logging %s; this character: %d events, %d position samples."):format(
        YippRouteDB.logging and "on" or "off", r and #r.ev or 0, r and #r.track or 0))
end
