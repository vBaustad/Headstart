-- Playing the route as a duo or trio. On Forever a quest can be shared with the party from any
-- distance, so a group can split up: one takes the quests, the others are already killing.
--
--   * Roles: each character plays a role of a duo (A, B) or trio (A, B, C) route, or solo. Routes mark
--     the quest pick-ups one member does for all ("#share N", taken in turns); Guides.lua registers
--     a version of the route per role.
--   * Share: a route quest you take from an NPC is shared with your party straight away.
--   * Accept: a route quest a party member shares with you is accepted (never anything else),
--     and so is the "start this escort?" question for one.
--   * Party: Headstart tells the other Headstarts in the party its version, role and the route step
--     it's on, for the party panel; a newer version in the party is mentioned once.
--
-- Per character: YippSetupCharDB.role ("solo", "Duo A", "Duo B", "Trio A", "Trio B", "Trio C").
-- Account options (Settings, Route): groupShare, groupAccept, groupPanel, all on unless turned off.
--
-- Two parts (Core.lua), so that none of it costs anything while it isn't used:
--   * the party's steps (the hello, the step messages, the panel): only with the routes on. Alone, it
--     listens for the group changing and nothing else; the addon channel and the step check every few
--     seconds are there only while you are in a group (the check also while you play a group role, for
--     the route's version for that role).
--   * sharing and accepting quests: only while one of its options is on (the two for the route's
--     quests, with the routes on; PartyQuests.lua's two, for any quest).
local ADDON, YR = ...

local PREFIX = "Headstart"
local party = {}                -- sender -> { version, role, guide, step, seen }
local sharedToMe = {}           -- questID -> true: came from a party member, so don't share it back
local toldVersion

YR.ROLES = { { "solo", "Solo" }, { "Duo A", "Duo, role A" }, { "Duo B", "Duo, role B" },
    { "Trio A", "Trio, role A" }, { "Trio B", "Trio, role B" }, { "Trio C", "Trio, role C" } }

function YR:Role()
    return (YippSetupCharDB and YippSetupCharDB.role) or "solo"
end

local version               -- read from the .toc once: it is asked for with every hello, sent or heard
local function Version()
    if not version then
        version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "0"
    end
    return version
end

-- "0.9.0-beta2" -> comparable numbers; a release sorts after its betas
local function VersionKey(v)
    local a, b, c = v:match("(%d+)%.(%d+)%.?(%d*)")
    local beta = tonumber(v:match("beta(%d+)")) or 999
    return { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0, beta }
end

local function Newer(v, than)
    local x, y = VersionKey(v), VersionKey(than)
    for i = 1, 4 do
        if x[i] ~= y[i] then return x[i] > y[i] end
    end
    return false
end

local function Grouped()
    return IsInGroup ~= nil and IsInGroup() or false
end

local function Send(msg)
    if not Grouped() then return end
    local channel = (IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) and "INSTANCE_CHAT") or "PARTY"
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel)
end

local lastGuide, lastStep
local function Current()
    local rxp = RXP
    local guide = type(rxp) == "table" and type(rxp.currentGuide) == "table" and rxp.currentGuide.name
    local step = type(RXPCData) == "table" and RXPCData.currentStep
    return guide, step
end

local share, quests          -- the two parts (see the top of the file), declared by YR:StartGroup

-- The hello: version, role and step, to the party. Only with the routes on and in a group; the text
-- isn't made otherwise.
local helloSoon = false
local function Hello()
    helloSoon = false
    if not (share and share.on and Grouped()) then return end
    local guide, step = Current()
    Send(("H\t%s\t%s\t%s\t%s"):format(Version(), YR:Role(), guide or "", step or 0))
end
function YR:SayHello() Hello() end

-- A group forming fires the roster event several times in a second or two: one hello for all of them.
local function HelloSoon()
    if helloSoon or not Grouped() then return end
    helloSoon = true
    C_Timer.After(2, Hello)
end

-- the step each of you is on, when it changes (checked every few seconds)
local function WatchStep()
    local guide, step = Current()
    if guide ~= lastGuide or step ~= lastStep then
        -- RestedXP moved on to a new route: in a group role, take that route's version for the role
        -- (a route without one hands over to the solo version of the next)
        local newRoute = guide ~= lastGuide
        lastGuide, lastStep = guide, step
        if newRoute and YR.LoadRoleGuide and YR:Role() ~= "solo" then YR:LoadRoleGuide(true) end
        if Grouped() then Send(("S\t%s\t%s"):format(guide or "", step or 0)) end
    end
end

-- What is only needed in a group: the addon channel (it carries every addon's messages, all session)
-- and the step check. Looked at when the group changes, the role changes, and as the part comes on.
local stepTicker
local function Sync()
    local frame = share and share.on and share.frame
    local grouped = frame and Grouped() or false
    if frame then
        if grouped then frame:RegisterEvent("CHAT_MSG_ADDON") else frame:UnregisterEvent("CHAT_MSG_ADDON") end
    end
    local watch = grouped or (frame and YR:Role() ~= "solo") or false
    if watch and not stepTicker then
        stepTicker = C_Timer.NewTicker(3, WatchStep)
    elseif not watch and stepTicker then
        stepTicker:Cancel()
        stepTicker = nil
    end
end

-- Text from another player: no escape codes (|c, |T, |H: a link or texture could be forged), no
-- control characters, and short.
local function Sanitize(s, maxLen)
    if type(s) ~= "string" then return nil end
    s = s:gsub("|", ""):gsub("[%c]", "")
    return s:sub(1, maxLen)
end

local ROLE_OK = {}
for _, r in ipairs(YR.ROLES) do ROLE_OK[r[1]] = true end

local function Heard(sender, msg)
    if #msg > 255 then return end
    local kind, a, b, c, d = strsplit("\t", msg)
    -- every field checked for its shape: a version, a role, a route name, a step number
    a, b, c, d = Sanitize(a, 80), Sanitize(b, 80), Sanitize(c, 80), Sanitize(d, 8)
    if kind == "H" then
        if not (a and a:match("^[%w%.%-]+$")) or not ROLE_OK[b] then return end
    elseif kind == "S" then
        b = b and b:match("^%d+$") and b or "0"
    else
        return
    end
    local p = party[sender] or {}
    party[sender] = p
    p.seen = time()
    if kind == "H" then
        p.version, p.role, p.guide, p.step = a, b, c, tonumber(d)
        -- (a party member's newer Headstart was said in chat: CurseForge says it better - 2026-10-21)
        if a and Newer(a, Version()) then toldVersion = a end
    elseif kind == "S" then
        p.guide, p.step = a, tonumber(b)
    end
    if YR.RefreshParty then YR:RefreshParty() end
end

function YR:Party()
    -- only who is still in the group
    for name in pairs(party) do
        local short = Ambiguate(name, "none")
        local inParty, inRaid = UnitInParty(short), UnitInRaid(short)
        -- an answer the game keeps secret is no answer: they stay on the list
        local unknown = issecretvalue and (issecretvalue(inParty) or issecretvalue(inRaid))
        if not unknown and not (inParty or inRaid) then party[name] = nil end
    end
    return party
end

-- Every quest a route of ours takes (its .accept lines), for sharing and accepting, by ID and by
-- title (the escort question only says the title).
local routeQuests, routeTitles
function YR:ForgetRouteQuests() routeQuests, routeTitles = nil, nil end
local function Read()
    routeQuests, routeTitles = {}, {}
    for _, g in ipairs(YR.shipped) do
        local text = YR:GuideText(g.key) or ""
        for q in text:gmatch("%.accept%s+(%d+)") do routeQuests[tonumber(q)] = true end
        for t in text:gmatch("%.accept%s+%d+[,%d]*%s*>>%s*Accept ([^\n|<]+)") do routeTitles[strtrim(t)] = true end
    end
end
function YR.RouteQuest(questID)
    if not routeQuests then Read() end
    return questID and routeQuests[questID] or false
end
function YR.RouteQuestTitle(title)
    if not routeTitles then Read() end
    return title and routeTitles[title] or false
end

local function Share(questID)
    if not Grouped() or sharedToMe[questID] then return end
    -- The route's quests (groupShare, with the routes on), or every quest (shareAll, PartyQuests.lua).
    if not ((YR.RoutesOn() and YR.Option("groupShare") and YR.RouteQuest(questID)) or YR.ShareAll()) then return end
    if C_QuestLog.IsPushableQuest and not C_QuestLog.IsPushableQuest(questID) then return end
    pcall(C_QuestLog.SetSelectedQuest, questID)
    pcall(QuestLogPushQuest)
end

-- A quest offered by a player (shared), not an NPC.
local function FromPlayer()
    local ok, isPlayer = pcall(UnitIsPlayer, "npc")
    return ok and isPlayer or false
end

local function IsMe(sender)
    local me = UnitName("player")
    return sender == me or Ambiguate(sender, "short") == me
end

-- The party's steps: with the routes on.
local function OnShare(_, event, a, b, c, d)
    if event == "CHAT_MSG_ADDON" then
        -- the party's or the raid's channel only: a whisper or a guild message with our prefix is not a
        -- party member's hello (anyone could make chat say "X has Headstart 9.9" with one)
        if a == PREFIX and type(b) == "string" and type(d) == "string" and (c == "PARTY" or c == "RAID" or c == "INSTANCE_CHAT") then
            local ok, me = pcall(IsMe, d)
            if not (ok and me) then Heard(d, b) end
        end
    else        -- GROUP_ROSTER_UPDATE, PLAYER_ENTERING_WORLD
        Sync()
        HelloSoon()
        if YR.RefreshParty then YR:RefreshParty() end
    end
end

local panel         -- the party panel (below)

-- Sharing and accepting: while one of its options is on.
local function RouteAccept() return YR.RoutesOn() and YR.Option("groupAccept") end

local function OnQuest(_, event, a, b)
    if event == "QUEST_DETAIL" then
        local id = GetQuestID and GetQuestID()
        if id and FromPlayer() then
            sharedToMe[id] = true
            if (RouteAccept() and YR.RouteQuest(id) and not IsShiftKeyDown())
                or YR.AcceptSharedBy("npc") then
                AcceptQuest()
            end
        end
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        -- a party member started an escort: join it, if it's one of the route's
        if ConfirmAcceptQuest and ((RouteAccept() and YR.RouteQuestTitle(b))
            or YR.AcceptSharedBy(nil, a)) then
            ConfirmAcceptQuest()
        end
    elseif event == "QUEST_ACCEPTED" then
        -- alone there is nobody to share with: nothing is set up for later
        if Grouped() then C_Timer.After(0.5, function() Share(a) end) end
    end
end

function YR:StartGroup()
    if share then return end
    share = YR.Part(function() return YR.RoutesOn() end, { "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }, OnShare, {
        start = function()
            if C_ChatInfo then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
            Sync()
        end,
        stop = function()
            Sync()
            if panel then panel:Hide() end
        end,
    })
    quests = YR.Part(function()
        return YR.ShareAll() or YR.AcceptFrom() ~= "off"
            or (YR.RoutesOn() and (YR.Option("groupShare") or YR.Option("groupAccept"))) or false
    end, { "QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM", "QUEST_ACCEPTED" }, OnQuest)
end

function YR:SetRole(role)
    YippSetupCharDB.role = role
    YR:RegisterRole(role)
    YR:SayHello()
    YR:LoadRoleGuide()
    Sync()              -- a group role keeps the step check going outside a group too
end

-- Switch RestedXP to this role's version of the route it has open (or back to the solo one).
local function Plain(s) return (s:gsub("%f[%d]0+(%d)", "%1")) end
-- quiet: when switching by itself on a new route, say nothing if that route has no version for the role
function YR:LoadRoleGuide(quiet)
    local rxp = RXP
    local cur = type(rxp) == "table" and rxp.currentGuide
    if not (type(cur) == "table" and cur.name and rxp.GetGuideTable and rxp.LoadGuideTable) then return end
    local base = cur.name:gsub(" %(Duo %a%)$", ""):gsub(" %(Trio %a%)$", "")
    local role = YR:Role()
    local target = base
    if role ~= "solo" then
        local set
        for name, s in pairs(YR.GroupRouteNames or {}) do if Plain(name) == Plain(base) then set = s end end
        if not (set and set[role]) then
            if not quiet then YR.Print(("%s has no %s version: staying on the solo route."):format(base, role)) end
            return
        end
        target = base .. " (" .. role .. ")"
    end
    if target == cur.name or not rxp.GetGuideTable(cur.group, target) then return end
    if pcall(rxp.LoadGuideTable, rxp, cur.group, target) then YR.Print("route: " .. target) end
end

-- The party panel: who in the party runs Headstart, as which role, and the step each is on.
local function ByRole(a, b) return (a.p.role or "") < (b.p.role or "") end

function YR:RefreshParty()
    -- nobody heard from (every group change asks, alone too): nothing to list, nothing made
    if next(party) == nil then
        if panel then panel:Hide() end
        return
    end
    local members = {}
    for name, p in pairs(YR:Party()) do members[#members + 1] = { name = name, p = p } end
    if #members == 0 or not YR.Option("groupPanel") then
        if panel then panel:Hide() end
        return
    end
    if not panel then
        panel = CreateFrame("Frame", "HeadstartParty", UIParent)
        panel:SetSize(260, 20)
        panel.lines = {}
    end
    -- under the splits box where there is one, else a place of its own. (It was hung under the box or,
    -- with the box never shown, under the whole screen: below the bottom edge, never seen.) Looked at
    -- every time, so the box turned on later takes it along.
    local under = _G.HeadstartSplitsFrame or false
    if panel.under ~= under then
        panel.under = under
        panel:ClearAllPoints()
        if under then
            panel:SetPoint("TOPLEFT", under, "BOTTOMLEFT", 0, -8)
        else
            panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -260)
        end
    end
    table.sort(members, ByRole)
    local guide, step = Current()       -- as it is now: the step check may not have run since you joined
    local mine = { name = UnitName("player"), p = { role = YR:Role(), guide = guide, step = step } }
    table.insert(members, 1, mine)
    for i, m in ipairs(members) do
        local fs = panel.lines[i]
        if not fs then
            fs = panel:CreateFontString(nil, "OVERLAY")
            fs:SetFont(YR.Style.FONT, 12, "OUTLINE")
            fs:SetPoint("TOPLEFT", 0, -(i - 1) * 15)
            fs:SetJustifyH("LEFT")
            panel.lines[i] = fs
        end
        local role = m.p.role and m.p.role ~= "solo" and ("|cff66ccff" .. m.p.role .. "|r ") or ""
        local where = m.p.step and m.p.step > 0 and ("step " .. m.p.step) or "-"
        fs:SetText(role .. Ambiguate(m.name, "short") .. "  |cff999999" .. where .. "|r")
        fs:Show()
    end
    for i = #members + 1, #panel.lines do panel.lines[i]:Hide() end
    panel:SetHeight(#members * 15)
    panel:Show()
end
