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
--          Standing still, the samples between the first and the last of the same are left out (with one
--          kept at least every HEARTBEAT seconds, so a gap over a minute still means logged out): about
--          half of all samples, measured on a real log. Moving samples stay 2 seconds apart.
local _, YR = ...

local SAMPLE = 2
local HEARTBEAT = 30
local HEARTHSTONE = 8690
local run               -- this character's log while recording is on; nil while it is off
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
    if YR.Open((UnitCastingInfo("player"))) or YR.Open((UnitChannelInfo("player"))) then f = f + 4 end
    return f
end

-- The last sample seen, the last one written, and the one held back while nothing changes (written
-- as soon as something does, so the move away from a spot starts 2 seconds after its last sample).
local lastRow, lastKept, held
local function Same(a, b)
    for i = 2, 7 do if a[i] ~= b[i] then return false end end
    return true
end

local function FlushHeld()
    if held and run then run.track[#run.track + 1] = held end
    held = nil
end

local ScanCompletions, questsDirty

local function Sample()
    if not run then return end          -- recording is on, but the character's name isn't known yet
    -- the quest log changed since the last sample: read once here, not on every one of a burst of
    -- its events (each objective tick, each loot, each zone line fires several)
    if questsDirty then
        questsDirty = false
        ScanCompletions()
    end
    if run.stopped then return end
    -- The position track is for working on routes (where the time went between events). With routes off
    -- nothing reads it, and it is nine tenths of the log: not written then. Events keep their own position.
    local map, x, y
    if YR.RoutesOn() then map, x, y = YR.Position() end
    if map then
        local now, level, xp, flags = time(), UnitLevel("player"), UnitXP("player"), Flags()
        -- standing still: the one held-back row is moved on in time, not made anew every two seconds
        if held and lastKept and held[2] == map and held[3] == x and held[4] == y and held[5] == level
                and held[6] == xp and held[7] == flags and now - lastKept[1] < HEARTBEAT then
            held[1] = now
            WatchStep()
            return
        end
        local row = { now, map, x, y, level, xp, flags }
        if lastRow and lastKept and Same(row, lastRow) and row[1] - lastKept[1] < HEARTBEAT then
            held = row
        else
            if held and (not Same(row, held) or row[1] - held[1] > HEARTBEAT) then FlushHeld() end
            held = nil
            run.track[#run.track + 1] = row
            lastKept = row
        end
        lastRow = row
    end
    WatchStep()
end
YR.LogSample = Sample           -- for tests

--- The same thinning on a log written before it: once, for every character's track. Returns rows left out.
function YR.SlimTrack(track)
    local out, prev, kept, heldRow = {}, nil, nil, nil
    for _, row in ipairs(track) do
        if prev and kept and Same(row, prev) and row[1] - kept[1] < HEARTBEAT then
            heldRow = row
        else
            -- written when something changed, or before a gap (a logout): the time up to it counts
            if heldRow and (not Same(row, heldRow) or row[1] - heldRow[1] > HEARTBEAT) then out[#out + 1] = heldRow end
            heldRow = nil
            out[#out + 1] = row
            kept = row
        end
        prev = row
    end
    if heldRow then out[#out + 1] = heldRow end       -- the end of the log: its last sample stays
    local dropped = #track - #out
    for i = 1, #out do track[i] = out[i] end
    for i = #track, #out + 1, -1 do track[i] = nil end
    return dropped
end

-- The NPC you are talking to while a quest window is open: the quest giver or the turn-in.
local function Npc()
    local ok, name = pcall(UnitName, "npc")
    return ok and YR.Open(name) or nil      -- (a name the game keeps from addons - in an instance - is no name, not an error)
end

-- The first pass after login only records what is already complete: those were finished in an
-- earlier session, and logging them "now" would make the objective look instant.
local primed = false
function ScanCompletions()
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

-- What was killed: your target, when it is a dead creature at the moment the XP comes. Its name, its
-- level and "elite" / "rare" / "rareelite" (nothing for a normal one). Forever changed mob levels and
-- no data we have says what they are now (the user, 2026-10-08: a "level 30 elite" was 35): the
-- routes are checked against what the logs saw. Nothing when the kill wasn't your target, or where the
-- game keeps unit values secret (dungeons and raids).
local function Mob(alive)
    if not UnitExists("target") or UnitIsPlayer("target") then return end
    if alive then
        if not UnitCanAttack("player", "target") then return end
    elseif not UnitIsDead("target") then
        return
    end
    local name, level, kind = UnitName("target"), UnitLevel("target"), UnitClassification("target")
    if issecretvalue and (issecretvalue(name) or issecretvalue(level) or issecretvalue(kind)) then return end
    if type(name) ~= "string" or type(level) ~= "number" then return end
    return name, level, kind ~= "normal" and type(kind) == "string" and kind or nil
end

-- The XP usually comes a moment after the game has cleared your dead target (a logged run, 2026-10-10:
-- 13 kills of 92 had a name). So what you were fighting is also noted when the fight starts, and the
-- first kill of that fight takes it when there is no dead target to read. Only the first: a second
-- mob in the same fight was never looked at.
local opener
local function NoteOpener()
    local ok, name, level, kind = pcall(Mob, true)
    opener = ok and name and { name, level, kind } or nil
end

-- XP that didn't come from a quest turn-in is a kill (or exploring, rarely). A level-up in between
-- adds what was left of the old level.
local function XPChanged()
    local xp, level = UnitXP("player"), UnitLevel("player")
    if lastXP then
        local gained = level > lastLevel and (lastMax - lastXP + xp) or (xp - lastXP)
        if gained > 0 and turnedInAt ~= time() then
            local ok, mob, mobLevel, kind = pcall(Mob)
            if not ok then mob, mobLevel, kind = nil, nil, nil end
            if not mob and opener then mob, mobLevel, kind = opener[1], opener[2], opener[3] end
            opener = nil
            Add("kill", nil, { xp = gained, mob = mob, mlvl = mobLevel, elite = kind })
        end
    end
    lastXP, lastMax, lastLevel = xp, UnitXPMax("player"), level
end

local NPC_WINDOWS = { MERCHANT_SHOW = "vendor", TRAINER_SHOW = "trainer", TAXIMAP_OPENED = "flight" }

-- Your own loot, from the chat line the game prints ("You receive loot: [item]x2."): the patterns
-- come from the game's own strings, so they work in any language. Made the first time recording is on.
local LOOT_PATTERNS, SKILL_UP, SKILL_ORDER = {}, nil, nil
-- (Core.lua's, which reads a sentence whose blanks are numbered too: a second value says their order)
local function Pattern(s) return YR.SentencePattern(s) end
local function MakePatterns()
    for _, s in ipairs({ LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF }) do
        if type(s) == "string" then LOOT_PATTERNS[#LOOT_PATTERNS + 1] = { Pattern(s) } end
    end
    -- "Your skill in %s has increased to %d."
    if type(ERR_SKILL_UP_SI) == "string" then SKILL_UP, SKILL_ORDER = Pattern(ERR_SKILL_UP_SI) end
end
local QUEST_ITEM = Enum and Enum.ItemClass and Enum.ItemClass.Questitem or 12

local function Looted(msg)
    for _, pat in ipairs(LOOT_PATTERNS) do
        local link, count = YR.SentenceMatch(msg, pat[1], pat[2])
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

-- Skill-ups: only professions (the ones a player can unlearn). Weapon and defense skill-ups come
-- every few swings and say nothing about the route.

local function Profession(name)
    for i = 1, GetNumSkillLines and GetNumSkillLines() or 0 do
        local skill, isHeader, _, _, _, _, _, isAbandonable = GetSkillLineInfo(i)
        if skill == name and not isHeader then return isAbandonable end
    end
end

local function SkillUp(msg)
    local name, rank = YR.SentenceMatch(msg, SKILL_UP, SKILL_ORDER)
    if name and Profession(name) then Add("skill", nil, { name = name, rank = tonumber(rank) }) end
end

local function OnEvent(_, event, a, b, c)
    if not run or run.stopped then return end
    if event == "PLAYER_LOGOUT" then FlushHeld() return end
    -- a quest event with the log still unread: read it first, so a completion is written before the
    -- turn-in it belongs to
    if questsDirty and event ~= "QUEST_LOG_UPDATE" and (event == "QUEST_TURNED_IN" or event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED") then
        questsDirty = false
        ScanCompletions()
    end
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
        questsDirty = true
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
        NoteOpener()
        Add("fight")
    elseif event == "PLAYER_REGEN_ENABLED" then
        opener = nil
        Add("peace")
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if YR.Open(c) == HEARTHSTONE then Add("hearth") end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        Add("zone", nil, { zone = GetZoneText() })
    elseif event == "TRAINER_CLOSED" then
        trainerOpen = false
    elseif event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "LEARNED_SPELL_IN_TAB" then
        -- only what a trainer taught: a level-up also "learns" passives nobody walks anywhere for
        if trainerOpen then Add("learn", nil, { spell = a, name = C_Spell.GetSpellName(a) }) end
    elseif event == "CHAT_MSG_LOOT" then
        -- like the skill text below: if it's secret in dungeons and raids, no loot is logged there
        if type(a) == "string" and not (issecretvalue and issecretvalue(a)) then Looted(a) end
    elseif event == "CHAT_MSG_SKILL" then
        -- the text is secret in dungeons and raids: no skill-ups logged there
        if SKILL_UP and type(a) == "string" and not (issecretvalue and issecretvalue(a)) then SkillUp(a) end
    elseif NPC_WINDOWS[event] then
        if event == "TRAINER_SHOW" then trainerOpen = true end
        Add(NPC_WINDOWS[event], nil, { npc = Npc() })
    end
end

-- What was bought, and from whom: the buy goes through BuyMerchantItem, which is not protected. A hook
-- can't be taken off again: it is put on the first time recording is on (Begin), and with recording
-- off (no run) it returns at once.
local function Bought(index, quantity)
    if not run or run.stopped then return end
    local link = GetMerchantItemLink(index)
    local item = link and tonumber(link:match("item:(%d+)"))
    if item then
        Add("buy", nil, { item = item, count = quantity or 1, name = C_Item.GetItemNameByID(item), npc = Npc() })
    end
end

-- Everything the log listens for, only while recording is on (the part below). PLAYER_LOGOUT: the spot
-- you logged out on, its last sample too. The "spell learned" event has a different name in the modern
-- and the Classic API: whichever exists is the one that registers.
local EVENTS = { "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_XP_UPDATE",
    "PLAYER_LEVEL_UP", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "ZONE_CHANGED_NEW_AREA", "MERCHANT_SHOW", "TRAINER_SHOW", "TRAINER_CLOSED",
    "TAXIMAP_OPENED", "CHAT_MSG_LOOT", "CHAT_MSG_SKILL", "PLAYER_LOGOUT",
    "LEARNED_SPELL_IN_SKILL_LINE", "LEARNED_SPELL_IN_TAB", { "UNIT_SPELLCAST_SUCCEEDED", "player" } }

-- What was sold, and whether the route still needed it (Needs.lua warns about that). Needs.lua's hook
-- calls this only while the log says it is listening (YR.SellsWatched, in Begin and End).
YR:WatchSells(function(item, count)
    if run and not run.stopped then
        Add("sell", nil, { item = item, count = count, name = C_Item.GetItemNameByID(item), need = YR.RouteNeed(item) })
    end
end)

-- Stop run: this character's log ends here (the analysis cuts the run at it), until Resume.
function YR:StopLog()
    if run and not run.stopped then
        FlushHeld()
        Add("stop")
        run.stopped = time()
    end
end

function YR:ResumeLog()
    if run and run.stopped then
        run.stopped = nil
        lastRow, lastKept, held = nil, nil, nil
        Add("resume")
    end
end

--- Whether this character's log was ended with Stop run (asked by the This run page, splits on or not).
function YR.LogStopped()
    local r = run or (YippRouteDB.runs and YippRouteDB.runs[YR.CharKey()])
    return r ~= nil and r.stopped ~= nil
end

-- ---------------------------------------------------------------------------
-- Cleaning up. This character's log is in its own saved file; another character's may still be in the
-- account's, packed (RunStore.lua): what is said of it here comes from what was noted when it was packed.
-- ---------------------------------------------------------------------------
local function LastActive(r)
    if r.packed then return r.last or r.started or 0 end      -- another character's, packed (RunStore.lua)
    local t = r.started or 0
    local tr, ev = r.track, r.ev
    if type(tr) == "table" and tr[#tr] then t = math.max(t, tr[#tr][1] or 0) end
    if type(ev) == "table" and ev[#ev] then t = math.max(t, ev[#ev][1] or 0) end
    return t
end

--- Every character's log: { { key, samples, events, last (time), kb (about, in the saved file) } },
--- the most recently played first.
function YR.LogSummary()
    local out = {}
    for key, r in pairs(YippRouteDB.runs or {}) do
        if type(r) == "table" then
            local samples = r.packed and (r.samples or 0) or (type(r.track) == "table" and #r.track or 0)
            local events = r.packed and (r.events or 0) or (type(r.ev) == "table" and #r.ev or 0)
            -- measured on a real saved file: about 60 bytes a sample, 100 an event
            out[#out + 1] = { key = key, samples = samples, events = events, last = LastActive(r),
                kb = math.floor((samples * 60 + events * 100) / 1024 + 0.5) }
        end
    end
    table.sort(out, function(a, b) return a.last > b.last end)
    return out
end

--- Delete one character's log. This character's starts again from now, so recording goes on.
function YR.DeleteLog(key)
    if not (YippRouteDB.runs and YippRouteDB.runs[key]) then return false end
    YippRouteDB.runs[key] = nil
    if run and key == YR.CharKey() then
        run = { started = time(), ev = {}, track = {} }
        YippRouteDB.runs[key] = run
        lastRow, lastKept, held = nil, nil, nil
    end
    return true
end

--- How old a run log may get, in days of its character not being played: 30 unless you set another
--- number, 0 for never (Headstart, Levelling, Settings).
function YR.LogKeepDays()
    local days = tonumber(YippRouteDB.logKeepDays)
    return days and math.max(0, days) or 30
end

--- Delete the logs of characters not played for this many days. Returns how many. Never deleted: this
--- character's, a fastest run's (one that holds the best time to some level in the splits) and a run
--- a route of your own was saved from. Those are the ones still used: to beat, and to save again.
function YR.PruneLogs(days)
    if not (days and days > 0) then return 0 end
    local cut, me, n = time() - days * 86400, YR.CharKey(), 0
    local best = YR.SplitsBestRuns and YR.SplitsBestRuns() or {}
    for key, r in pairs(YippRouteDB.runs or {}) do
        if key ~= me and type(r) == "table" and LastActive(r) < cut and not best[key]
                and not (YR.MyRouteFrom and YR.MyRouteFrom(key)) then
            YippRouteDB.runs[key] = nil
            n = n + 1
        end
    end
    return n
end

--- Keeping the log from growing without end, for an account that doesn't use routes: the position
--- samples (the track) of every character but this one are dropped; their events stay, and so does all
--- of this character's log. Never on an account that has had routes on (YippRouteDB.routesEver): its
--- tracks are what the route work is done from. Returns how many samples went.
function YR.DropIdleTracks()
    if YR.RoutesOn() then
        YippRouteDB.routesEver = true
        return 0
    end
    if YippRouteDB.routesEver then return 0 end
    local me, n = YR.CharKey(), 0
    for key, r in pairs(YippRouteDB.runs or {}) do
        if key ~= me and type(r) == "table" and type(r.track) == "table" and #r.track > 0 then
            n = n + #r.track
            r.track = {}
        end
    end
    return n
end

-- Looking after the saved logs, once a login, recording on or not (a log kept from when it was on
-- still takes the room). On an account with no logs there is nothing to do, and nothing is written.
local tidied = false
-- Whether this character's key can be made: its name and the second part of it both known. A brand-new
-- character is "Unknown" for its first moments. And with only the second part missing the key was made
-- from the realm's name as it is displayed - another key than the one made a moment later, so a log
-- could be attached under one and written under the other (a log under "Unknown-<realm>" was found in
-- a saved file, 2026-10-13). Waited for half a minute at most: a client that never gives the second
-- part gets the key it always got.
local waited = 0
local function Named()
    local name, second = UnitFullName("player")
    if not name or name == UNKNOWNOBJECT or name == "Unknown" then return false end
    if second and second ~= "" then return true end
    waited = waited + 1
    return waited > 15
end

local function Tidy()
    if tidied then return end
    -- wait for the real name, or the clean-up below can't tell which log is yours
    if not Named() then
        C_Timer.After(2, Tidy)
        return
    end
    tidied = true
    -- this character's log from its own file, and what the account's file still holds packed small
    local packed = YR.RunsAttach()
    if packed > 0 then
        YR.Print(("packed the run logs of %d other character%s: they take a third of the memory now, and each moves to its own character's file the next time that character logs in."):format(packed, packed == 1 and "" or "s"))
    end
    local pruned = YR.PruneLogs(YR.LogKeepDays())
    if pruned > 0 then
        YR.Print(("deleted the run logs of %d character%s not played for %d days (kept: the fastest runs and any a route of yours was saved from). Headstart, Levelling, Settings sets the days; 0 keeps them all."):format(pruned,
            pruned == 1 and "" or "s", YR.LogKeepDays()))
    end
    if not YippRouteDB.trackSlimmed and next(YippRouteDB.runs) then
        for _, r in pairs(YippRouteDB.runs) do if type(r.track) == "table" then YR.SlimTrack(r.track) end end
        YippRouteDB.trackSlimmed = 1
    end
    local dropped = YR.DropIdleTracks()
    if dropped > 0 then
        YR.Print(("routes are off: dropped %d old position samples of your other characters' run logs (their events stay; nothing of this character's)."):format(dropped))
    end
end

-- Recording is a part (Core.lua): its frame, its events and the sample every two seconds exist only
-- while "Record runs" is on, and go again the moment it is turned off.
local part, hooked

-- Recording comes on: this character's log, made now if it has none.
local function Begin()
    if not (part and part.on) or run then return end
    -- wait for the real name, or every new character's run lands under the same key
    if not Named() then
        C_Timer.After(2, Begin)
        return
    end
    if not hooked then
        hooked = true
        MakePatterns()
        hooksecurefunc("BuyMerchantItem", Bought)
    end
    YR.RunsAttach()
    local key = YR.CharKey()
    YippRouteDB.runs[key] = YippRouteDB.runs[key] or { started = time(), ev = {}, track = {} }
    run = YippRouteDB.runs[key]
    YR.SettingChanged()         -- (its file is written at logout only while there is a log: RunStore.lua)
    lastRow, lastKept, held = nil, nil, nil
    lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    YR.SellsWatched(true)
end

-- Recording goes off: the sample held back is written, and the hooks have no run to write to.
local function End()
    FlushHeld()
    run = nil
    YR.SellsWatched(false)
end

function YR:StartLog()
    Tidy()
    if part then return end
    part = YR.Part(function() return YR.Option("logging") end, EVENTS, OnEvent,
        { start = Begin, stop = End, tick = Sample, every = SAMPLE })
end

function YR:SetLogging(on)
    YippRouteDB.logging = on
    if YR.partsReady then YR.ApplyParts() end       -- now, not a frame later: it starts or stops at once
    YR.Print("logging " .. (on and "on" or "off") .. ".")
end

function YR:LogStatus()
    local r = YippRouteDB.runs[YR.CharKey()]
    YR.Print(("logging %s; this character: %d events, %d position samples."):format(
        YR.Option("logging") and "on" or "off", r and #r.ev or 0, r and #r.track or 0))
end
