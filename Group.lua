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

local function Version()
    local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
    return v or "0"
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

local function Send(msg)
    if not (IsInGroup and IsInGroup()) then return end
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

function YR:SayHello()
    local guide, step = Current()
    Send(("H\t%s\t%s\t%s\t%s"):format(Version(), YR:Role(), guide or "", step or 0))
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
        Send(("S\t%s\t%s"):format(guide or "", step or 0))
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
        if a and Newer(a, Version()) and toldVersion ~= a then
            toldVersion = a
            YR.Print(("%s has Headstart %s; you have %s. Update when you can."):format(Ambiguate(sender, "short"), a, Version()))
        end
    elseif kind == "S" then
        p.guide, p.step = a, tonumber(b)
    end
    if YR.RefreshParty then YR:RefreshParty() end
end

function YR:Party()
    -- only who is still in the group
    for name in pairs(party) do
        if not (UnitInParty(Ambiguate(name, "none")) or UnitInRaid(Ambiguate(name, "none"))) then party[name] = nil end
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
        for t in text:gmatch("%.accept%s+%d+%s*>>%s*Accept ([^\n|<]+)") do routeTitles[strtrim(t)] = true end
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
    if not (IsInGroup and IsInGroup()) or sharedToMe[questID] then return end
    -- The route's quests (groupShare), or every quest (shareAll, PartyQuests.lua).
    if not ((YR.Option("groupShare") and YR.RouteQuest(questID)) or YR.ShareAll()) then return end
    if C_QuestLog.IsPushableQuest and not C_QuestLog.IsPushableQuest(questID) then return end
    pcall(C_QuestLog.SetSelectedQuest, questID)
    pcall(QuestLogPushQuest)
end

-- A quest offered by a player (shared), not an NPC.
local function FromPlayer()
    local ok, isPlayer = pcall(UnitIsPlayer, "npc")
    return ok and isPlayer or false
end

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, event, a, b, c, d)
    if event == "CHAT_MSG_ADDON" then
        if a == PREFIX and type(b) == "string" and type(d) == "string" then
            local ok, me = pcall(function() return d == UnitName("player") or Ambiguate(d, "short") == UnitName("player") end)
            if not (ok and me) then Heard(d, b) end
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        YR:SayHello()
        if YR.RefreshParty then YR:RefreshParty() end
    elseif event == "QUEST_DETAIL" then
        local id = GetQuestID and GetQuestID()
        if id and FromPlayer() then
            sharedToMe[id] = true
            if (YR.Option("groupAccept") and YR.RouteQuest(id) and not IsShiftKeyDown())
                or YR.AcceptSharedBy("npc") then
                AcceptQuest()
            end
        end
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        -- a party member started an escort: join it, if it's one of the route's
        if ConfirmAcceptQuest and ((YR.Option("groupAccept") and YR.RouteQuestTitle(b))
            or YR.AcceptSharedBy(nil, a)) then
            ConfirmAcceptQuest()
        end
    elseif event == "QUEST_ACCEPTED" then
        C_Timer.After(0.5, function() Share(a) end)
    end
end)

function YR:StartGroup()
    if C_ChatInfo then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
    for _, e in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "QUEST_DETAIL",
        "QUEST_ACCEPT_CONFIRM", "QUEST_ACCEPTED" }) do
        f:RegisterEvent(e)
    end
    C_Timer.NewTicker(3, WatchStep)
end

function YR:SetRole(role)
    YippSetupCharDB.role = role
    YR:RegisterRole(role)
    YR:SayHello()
    YR:LoadRoleGuide()
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
local panel
function YR:RefreshParty()
    local members = {}
    for name, p in pairs(YR:Party()) do members[#members + 1] = { name = name, p = p } end
    if #members == 0 or not YR.Option("groupPanel") then
        if panel then panel:Hide() end
        return
    end
    if not panel then
        panel = CreateFrame("Frame", "HeadstartParty", UIParent)
        panel:SetSize(260, 20)
        panel:SetPoint("TOPLEFT", HeadstartSplitsFrame or UIParent, "BOTTOMLEFT", 0, -8)
        panel.lines = {}
    end
    table.sort(members, function(a, b) return (a.p.role or "") < (b.p.role or "") end)
    local mine = { name = UnitName("player"), p = { role = YR:Role(), guide = lastGuide, step = lastStep } }
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
