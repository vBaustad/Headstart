-- Quests on NPC tooltips: an NPC's tooltip says which quests it has for you (the owner, 2026-10-20: "can't you put
-- the quests available on the tooltip when you hover?"). The game says what an NPC offers only once you talk to it,
-- so two things are told, under the game's own lines:
--   Your route: the RestedXP steps ahead (the guide you're on, from the step you're on, the next STEPS) that take
--   or hand in a quest at this NPC - their .target lines, by the NPC's id where the guide gives one, else its
--   name. Marked "route".
--   What it offered: each time you talk to an NPC, the quests it offers are written down for the account
--   (YippRouteDB.npcQuests[npc id][quest id] = { title, level }), and the NPC a quest is handed in to
--   (YippRouteDB.questEnds[quest id] = npc id). Its tooltip then lists the quests it offered that this character
--   hasn't done and isn't on, and the quests in your log that are done and handed in here.
--   QuestieDB, where it is loaded - the Questie team's quest database as an addon of its own, open for other
--   addons to read (github.com/Questie/QuestieDB; Questie itself reads it): every quest the NPC starts that this
--   character can take now (its level, race, class and the quests before it), and the done quests of yours it
--   takes in - talked to or not. Read through its public API (LibQuestieDB, contract 1) only; nothing of it is
--   copied here. With it, Questie itself can go (the owner, 2026-10-20: "is there no open source for this? I'd
--   like to drop Questie").
--   "!" before a quest to take (grey where it is too low to give much), "?" before one to hand in.
--   Not in a fight (a unit's GUID and name can be secret then), and never an error.
--   Questie lists an NPC's quests on its tooltip itself - every quest it starts or takes in, from Questie's own
--   database, talked to or not (its "showQuestsInNpcTooltip", on unless turned off): while Questie's are on, these
--   are left out, so nobody with both sees each quest twice (the owner, 2026-10-20: "let's not overlap with
--   Questie when people have both"). What NPCs offer is still written down, for when it isn't.
--   Account option questTips (off until turned on: it adds to the game's tooltips). Free while off (YR.Part):
--   nothing listens; the tooltip hook is put on the first time it is on (it can't be taken off) and does nothing
--   while it is off.
local _, YR = ...

local STEPS = 30                            -- how far ahead on the route
local TAKE, HANDIN = 132049, 132048         -- AvailableQuestIcon, ActiveQuestIcon (as NpcMarkers.lua)
local ROUTE = { 0.96, 0.62, 0.30 }          -- "route", in an accent

local function On() return YR.QoLOn() and YR.Option("questTips") end
local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

-- (an NPC's id is the sixth part of its GUID: Creature-0-1-2-3-<id>-<spawn>)
local function NpcOf(guid)
    guid = Plain(guid)
    if type(guid) ~= "string" then return nil end
    local kind, id = guid:match("^(%a+)%-[^%-]*%-[^%-]*%-[^%-]*%-[^%-]*%-(%d+)")
    if kind ~= "Creature" then return nil end
    return tonumber(id)
end

local function DB(key)
    local t = YippRouteDB[key]
    if type(t) ~= "table" then t = {} YippRouteDB[key] = t end
    return t
end

-- ---------------------------------------------------------------------------
-- What an NPC offered: written down as you talk to it
-- ---------------------------------------------------------------------------
local function Offered(npc, quest, title, level)
    quest = tonumber(Plain(quest))
    if not (npc and quest and quest > 0) then return end
    local all = DB("npcQuests")
    local mine = all[npc]
    if type(mine) ~= "table" then mine = {} all[npc] = mine end
    mine[quest] = { type(Plain(title)) == "string" and title or nil, tonumber(Plain(level)) }
end

-- The quests handed in at each NPC, from questEnds (quest -> NPC): made when first asked, and again after a change.
local endsBy
local function EndsAt(npc, quest)
    quest = tonumber(Plain(quest))
    if npc and quest and quest > 0 then
        local ends = DB("questEnds")
        if ends[quest] ~= npc then ends[quest], endsBy = npc, nil end
    end
end
local function EndsHere(npc)
    if not endsBy then
        endsBy = {}
        for quest, at in pairs(DB("questEnds")) do
            local list = endsBy[at]
            if not list then list = {} endsBy[at] = list end
            list[#list + 1] = quest
        end
    end
    return endsBy[npc]
end

local function Heard(event)
    local npc = NpcOf(UnitGUID and UnitGUID("npc"))
    if not npc then return end
    if event == "GOSSIP_SHOW" and C_GossipInfo then
        for _, q in ipairs(C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}) do
            if type(q) == "table" then Offered(npc, q.questID, q.title, q.questLevel) end
        end
        for _, q in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
            if type(q) == "table" then EndsAt(npc, q.questID) end
        end
    elseif event == "QUEST_GREETING" then
        for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
            local quest = GetAvailableQuestInfo and select(5, GetAvailableQuestInfo(i))
            Offered(npc, quest, GetAvailableTitle and GetAvailableTitle(i))
        end
        for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
            EndsAt(npc, GetActiveQuestID and GetActiveQuestID(i))
        end
    elseif event == "QUEST_DETAIL" then
        -- (a quest put to you straight away, or picked from the list: the NPC still offers it)
        local quest = GetQuestID and GetQuestID()
        if quest and not (C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(quest)) then
            Offered(npc, quest, GetTitleText and GetTitleText())
        end
    elseif event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then
        EndsAt(npc, GetQuestID and GetQuestID())
    end
end

-- ---------------------------------------------------------------------------
-- Your route: the steps ahead that take or hand in a quest at an NPC
-- ---------------------------------------------------------------------------
local route = { names = {}, ids = {} }      -- [npc name or id] = { { tag, quest } ... }
local routeKey

-- A guide's name for a unit: "Name", "Name::123", "123", maybe with RestedXP's "*" or "+" in front.
local function Entry(raw)
    if type(raw) ~= "string" then return nil end
    raw = raw:gsub("^[%*%+]+", "")
    local name, id = raw:match("^(.-)::(%d+)$")
    if id then return name ~= "" and name or nil, tonumber(id) end
    if raw:match("^%d+$") then return nil, tonumber(raw) end
    return raw ~= "" and raw or nil, nil
end

local function ReadRoute()
    local rxp = _G.RXP
    local guide = type(rxp) == "table" and rxp.currentGuide
    local n = type(RXPCData) == "table" and tonumber(RXPCData.currentStep)
    local steps = type(guide) == "table" and type(guide.steps) == "table" and guide.steps
    local key = steps and n and (tostring(guide.name) .. ":" .. n) or "none"
    if key == routeKey then return end
    routeKey = key
    wipe(route.names) wipe(route.ids)
    if not steps then return end
    for i = n, math.min(#steps, n + STEPS) do
        local step = steps[i]
        if type(step) == "table" and type(step.elements) == "table" and not step.completed then
            local who, quests = {}, {}
            for _, e in ipairs(step.elements) do
                if type(e) == "table" then
                    if type(e.targets) == "table" then
                        for _, raw in ipairs(e.targets) do who[#who + 1] = raw end
                    end
                    local q = tonumber(e.questId)
                    if q and (e.tag == "accept" or e.tag == "turnin") and not e.completed and not e.skip then
                        quests[#quests + 1] = { e.tag, q }
                    end
                end
            end
            if #quests > 0 then
                for _, raw in ipairs(who) do
                    local name, id = Entry(raw)
                    if name and type(rxp.GetCreatureName) == "function" then
                        local ok, here = pcall(rxp.GetCreatureName, name)        -- (in the client's language)
                        if ok and type(here) == "string" then name = here end
                    end
                    for _, t in ipairs({ { route.names, name }, { route.ids, id } }) do
                        if t[2] ~= nil then
                            local list = t[1][t[2]] or {}
                            t[1][t[2]] = list
                            for _, q in ipairs(quests) do list[#list + 1] = q end
                        end
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- The tooltip
-- ---------------------------------------------------------------------------
local function Title(quest, known)
    if type(known) == "string" then return known end
    local t = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(quest)
    if type(t) == "string" and t ~= "" then return t end
    -- (RestedXP's own names for quests it has seen: its saved RXPData, and the character's RXPCData)
    local saved, mine = _G.RXPData, _G.RXPCData
    local names = type(saved) == "table" and type(saved.questNames) == "table" and saved.questNames[quest]
        or type(mine) == "table" and type(mine.questNameCache) == "table" and mine.questNameCache[quest]
    return type(names) == "string" and names or ("Quest " .. quest)
end

--- A quest's name: the game's, else RestedXP's, else "Quest <id>" (the world marker's tooltip too).
function YR.QuestTitle(quest) return Title(quest) end

local function Done(quest) return C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(quest) end
local function Having(quest) return C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(quest) end
local function Ready(quest) return C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(quest) end

-- QuestieDB, where it is loaded and speaks the contract this was written for (1), else nil.
local qdbOk
local function QDB()
    local lib = _G.LibQuestieDB
    if type(lib) ~= "table" or type(lib.Npc) ~= "table" or type(lib.Quest) ~= "table" then return nil end
    if qdbOk == nil then
        local ok, fine = pcall(lib.RequireContract or function() return true end, 1)
        qdbOk = ok and fine and true or false
    end
    return qdbOk and lib or nil
end
local function Field(entity, id, key)
    local ok, v = pcall(entity.Get, id, key)
    return ok and v or nil
end
-- (a race or class mask: bit n - 1 for race or class n; none set, or 0, is anyone)
local function InMask(mask, n)
    if type(mask) ~= "number" or mask == 0 or type(n) ~= "number" then return true end
    return math.floor(mask / 2 ^ (n - 1)) % 2 == 1
end
local function AnyDone(list)
    if type(list) ~= "table" or #list == 0 then return true end
    for _, q in ipairs(list) do if Done(q) then return true end end
    return false
end
local function AllDone(list)
    for _, q in ipairs(type(list) == "table" and list or {}) do if not Done(q) then return false end end
    return true
end
-- Whether this character can take a quest now, as QuestieDB has it: not done and not on; its level reached (and not
-- past its last); its race and class; the quests before it done, and none it excludes. One that needs a
-- profession is left out (whether you have it isn't asked here).
local function CanTake(lib, quest)
    if Done(quest) or Having(quest) then return false end
    local Q = lib.Quest
    local level = UnitLevel and UnitLevel("player") or 0
    local need, last = Field(Q, quest, "requiredLevel"), Field(Q, quest, "requiredMaxLevel")
    if type(need) == "number" and need > level then return false end
    if type(last) == "number" and last > 0 and level > last then return false end
    if not InMask(Field(Q, quest, "requiredRaces"), select(3, UnitRace("player"))) then return false end
    if not InMask(Field(Q, quest, "requiredClasses"), select(3, UnitClass("player"))) then return false end
    if not AnyDone(Field(Q, quest, "preQuestSingle")) or not AllDone(Field(Q, quest, "preQuestGroup")) then return false end
    for _, q in ipairs(Field(Q, quest, "exclusiveTo") or {}) do
        if Done(q) or Having(q) then return false end
    end
    if Field(Q, quest, "requiredSkill") then return false end
    return true
end
YR.QuestTipsDB = function() qdbOk = nil return QDB() ~= nil end         -- (for the tests: looked at again)

-- The lines for an NPC: { icon, words, r, g, b, route } - quests to hand in first, then to take.
function YR.QuestTipLines(npc, name)
    local lines, seen = {}, {}
    local function Put(icon, quest, title, level, onRoute)
        local k = icon .. ":" .. quest
        if seen[k] then
            if onRoute then seen[k][6] = true end
            return
        end
        local r, g, b = 1, 0.82, 0
        if icon == TAKE and level and GetQuestDifficultyColor then
            local c = GetQuestDifficultyColor(level)
            if type(c) == "table" then r, g, b = c.r or r, c.g or g, c.b or b end
        end
        local line = { icon, Title(quest, title), r, g, b, onRoute and true or false }
        seen[k] = line
        lines[#lines + 1] = line
    end
    ReadRoute()
    local onRoute = {}
    for _, list in ipairs({ npc and route.ids[npc] or {}, name and route.names[name] or {} }) do
        for _, q in ipairs(list) do onRoute[#onRoute + 1] = q end
    end
    -- to hand in: done quests of yours that end here (as seen, or as the route says)
    for _, q in ipairs(onRoute) do
        if q[1] == "turnin" and Having(q[2]) and Ready(q[2]) then Put(HANDIN, q[2], nil, nil, true) end
    end
    for _, quest in ipairs(npc and EndsHere(npc) or {}) do
        if Having(quest) and Ready(quest) then Put(HANDIN, quest) end
    end
    local lib = npc and QDB()
    if lib then
        for _, quest in ipairs(Field(lib.Npc, npc, "questEnds") or {}) do
            if Having(quest) and Ready(quest) then Put(HANDIN, quest, Field(lib.Quest, quest, "name")) end
        end
    end
    -- to take: what it offered, not done and not on; and what the route takes here
    for _, q in ipairs(onRoute) do
        if q[1] == "accept" and not Done(q[2]) and not Having(q[2]) then Put(TAKE, q[2], nil, nil, true) end
    end
    if lib then
        for _, quest in ipairs(Field(lib.Npc, npc, "questStarts") or {}) do
            if CanTake(lib, quest) then
                Put(TAKE, quest, Field(lib.Quest, quest, "name"), Field(lib.Quest, quest, "questLevel"))
            end
        end
    end
    local offers = npc and DB("npcQuests")[npc]
    if type(offers) == "table" then
        for quest, info in pairs(offers) do
            if not Done(quest) and not Having(quest) then Put(TAKE, quest, info[1], info[2]) end
        end
    end
    return lines
end

-- Whether Questie is listing NPCs' quests on their tooltips now (its own settings: Questie.db.profile, AceDB's,
-- with its defaults filled in).
local function QuestieTells()
    local questie = _G.Questie
    local db = type(questie) == "table" and questie.db
    local p = type(db) == "table" and db.profile
    if type(p) ~= "table" then return false end
    return p.enableTooltips ~= false and p.showQuestsInNpcTooltip ~= false
end
YR.QuestieTells = QuestieTells

local hooked = false
local function OnUnitTip(tooltip, data)
    if not On() or tooltip ~= GameTooltip or InCombatLockdown() or QuestieTells() then return end
    local name, unit
    if tooltip.GetUnit then
        local ok, n, u = pcall(tooltip.GetUnit, tooltip)
        if ok then name, unit = Plain(n), Plain(u) end
    end
    -- (a hostile mob has no quest for you: left as it is at once - every mob's tooltip was read through. Hostile, not
    -- one you can attack: Booty Bay's, Ratchet's and Gadgetzan's quest givers are neutral, and can be attacked;
    -- the review, 2026-10-21)
    if unit then
        local okE, enemy = pcall(UnitIsEnemy, "player", unit)
        if okE and Plain(enemy) == true then return end
    end
    local guid = type(data) == "table" and Plain(data.guid) or (unit and UnitGUID and UnitGUID(unit))
    local npc = NpcOf(guid)
    if not npc then return end
    local ok, lines = pcall(YR.QuestTipLines, npc, name)
    if not ok or #lines == 0 then return end
    tooltip:AddLine(" ")
    for _, l in ipairs(lines) do
        local words = ("|T%d:14|t %s"):format(l[1], l[2])
        if l[6] then words = words .. ("  |cff%02x%02x%02xroute|r"):format(ROUTE[1] * 255, ROUTE[2] * 255, ROUTE[3] * 255) end
        tooltip:AddLine(words, l[3], l[4], l[5])
    end
    tooltip:Show()
end

local function Hook()
    if hooked then return end
    hooked = true
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTip)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip) OnUnitTip(tooltip) end)
    end
end

YR.Part(On, { "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }, function(_, event)
    pcall(Heard, event)
end, {
    start = function() Hook() end,
})
