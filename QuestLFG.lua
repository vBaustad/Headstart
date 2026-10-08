-- Quest group: ask chat for a group for one of your quests, and see who answers - in one small window.
--   A small eye button sits left of the quest tracker (Shift-drag moves it). It opens a window with your
--   quests, the ones meant for a group first. "Ask" beside a quest says "LFG <quest>" in the chat
--   channel you chose (your click sends it: an addon can't talk in a channel by itself, and this one
--   never repeats it for you - "Ask again" is a click too, at most once every thirty seconds).
--   Then the window collects what belongs to that quest: anyone naming it in that kind of chat, and
--   whoever whispers you for the next quarter of an hour - each with an Invite and a Whisper button.
--   It also notes other players asking for a quest you have in your log ("Others looking"), so
--   you can join them instead. The eye shows how many you haven't looked at.
--   A line of chat is matched by the quest's name in it (whatever its case) or by a link to the quest.
--   Lines the game keeps secret (in an instance) are passed over.
--   Free while off; with it on, channel chat is read only while you are asking or "Others looking" is
--   on, and whispers only while you are asking.
--   Account options (YippRouteDB, Settings, QoL, Group): questLFG (off until you turn it on),
--   questLFGChannel (a channel's name; nil: LookingForGroup if you're in it, else channel 2, else 1),
--   questLFGText ("LFG {quest}"; {quest} and {level} are filled in), questLFGWatch (others looking for
--   your quests; on unless turned off), questLFGPos (where you dragged the eye).
local ADDON, YR = ...

local COOLDOWN = 30             -- seconds between two posts of yours
local LISTEN = 900              -- how long after a post whispers are taken as answers
local KEEP = 30                 -- answers kept

local asking = {}               -- [questID] = { id, title, at (when last said) }
local replies = {}              -- newest first: { who, text, quest, id, kind ("whisper", "channel", "other"), at }
local titles                    -- the quests in your log by name: { { lower, title, id }, ... }; nil: read again
local lastPost = 0
local unseen = 0
local button, win
local Draw                      -- (the window, further down)

local function Now() return GetTime() end
local function Secret(v) return issecretvalue and issecretvalue(v) end

function YR.QuestLFGOn() return YR.Option("questLFG") end
local function Watching() return YippRouteDB.questLFGWatch ~= false end
local function AnyAsking()
    local now = Now()
    for _, a in pairs(asking) do if now - a.at < LISTEN then return true end end
    return false
end

--- The quests in your log that aren't done: { { id, title, level, group (players it is meant for),
--- tracked }, ... }, the ones meant for a group first, then by level.
function YR.QuestLFGQuests()
    local out = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return out end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID and info.title and not C_QuestLog.IsComplete(info.questID) then
            out[#out + 1] = { id = info.questID, title = info.title, level = info.level or 0,
                group = (info.suggestedGroup or 0) > 1 and info.suggestedGroup or nil,
                tracked = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(info.questID) ~= nil or false }
        end
    end
    table.sort(out, function(a, b)
        if (a.group ~= nil) ~= (b.group ~= nil) then return a.group ~= nil end
        if a.level ~= b.level then return a.level > b.level end
        return a.title < b.title
    end)
    return out
end

local function Titles()
    if titles then return titles end
    titles = {}
    for _, q in ipairs(YR.QuestLFGQuests()) do
        -- a name of a letter or two would be found in every other line of chat
        if #q.title >= 4 then titles[#titles + 1] = { lower = q.title:lower(), title = q.title, id = q.id } end
    end
    return titles
end

--- The quest of yours a line of chat is about (its name in the line, or a link to it), or nil.
function YR.QuestLFGMatch(msg)
    if type(msg) ~= "string" or Secret(msg) then return nil end
    local list = Titles()
    if #list == 0 then return nil end
    local linked = tonumber(msg:match("|Hquest:(%d+)"))
    local lower = msg:lower()
    for _, t in ipairs(list) do
        if t.id == linked or lower:find(t.lower, 1, true) then return t end
    end
    return nil
end

--- The channel a post goes to: its number and name. The one you chose by name, while you're in it;
--- else LookingForGroup, else channel 2, else the first you're in. nil when you're in none.
function YR.QuestLFGChannel()
    if not GetChannelList then return nil end
    local list = { GetChannelList() }
    local want = YippRouteDB.questLFGChannel
    local lfg, two, first
    for i = 1, #list, 3 do
        local id, name = list[i], list[i + 1]
        if type(name) == "string" then
            if want and name == want then return id, name end
            if name:find("^LookingForGroup") then lfg = lfg or i end
            if id == 2 then two = i end
            first = first or i
        end
    end
    local i = lfg or two or first
    if i then return list[i], list[i + 1] end
    return nil
end

--- The channels you're in, for the settings: { { name or false (automatic), label }, ... }.
function YR.QuestLFGChannels()
    local out = { { false, "Automatic" } }
    if GetChannelList then
        local list = { GetChannelList() }
        for i = 1, #list, 3 do
            if type(list[i + 1]) == "string" then out[#out + 1] = { list[i + 1], list[i] .. ". " .. list[i + 1] } end
        end
    end
    return out
end

--- What is said for a quest: your words with {quest} and {level} filled in.
function YR.QuestLFGMessage(q)
    local text = YippRouteDB.questLFGText
    if type(text) ~= "string" or not text:find("{quest}", 1, true) then text = "LFG {quest}" end
    return (text:gsub("{quest}", (q.title:gsub("%%", "%%%%"))):gsub("{level}", tostring(q.level or "")))
end

--- Ask for a group for a quest ({ id, title, level }). Must come from a click of yours: the game sends
--- nothing to a channel otherwise. Returns true, or false and why.
function YR.QuestLFGAsk(q)
    local now = Now()
    if now - lastPost < COOLDOWN then
        return false, ("wait %d seconds: one post every half minute."):format(math.ceil(COOLDOWN - (now - lastPost)))
    end
    local id, name = YR.QuestLFGChannel()
    if not id then return false, "you're in no chat channel to ask in." end
    local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    local ok = pcall(send, YR.QuestLFGMessage(q), "CHANNEL", nil, id)
    if not ok then return false, "the game didn't let that be said." end
    lastPost = now
    asking[q.id] = { id = q.id, title = q.title, level = q.level, at = now, channel = name }
    YR.SettingChanged()             -- chat is listened to while you're asking
    if Draw then Draw() end
    return true
end

function YR.QuestLFGStop(id)
    asking[id] = nil
    YR.SettingChanged()
    if Draw then Draw() end
end
function YR.QuestLFGAsking() return asking end
function YR.QuestLFGReplies() return replies end
function YR.QuestLFGUnseen() return unseen end

local function Badge()
    if not button then return end
    button.count:SetText(unseen > 0 and tostring(unseen) or "")
    button.glow:SetShown(unseen > 0)
end

local function Short(name) return Ambiguate and Ambiguate(name, "short") or name end

local function AddReply(who, text, t, kind)
    local now = Now()
    -- the same player about the same quest again: their latest words, not another line
    for _, r in ipairs(replies) do
        if r.who == who and r.id == t.id and r.kind == kind then
            r.text, r.at = text, now
            if Draw then Draw() end
            return
        end
    end
    table.insert(replies, 1, { who = who, text = text, quest = t.title, id = t.id, kind = kind, at = now })
    while #replies > KEEP do replies[#replies] = nil end
    if not (win and win:IsShown()) then unseen = unseen + 1 end
    Badge()
    YR.Print(kind == "other" and ("%s is looking for a group for %s too. /headstart lfg"):format(Short(who), t.title)
        or ("%s answered about %s. /headstart lfg"):format(Short(who), t.title))
    if Draw then Draw() end
end

local function Me(sender)
    local me = UnitName("player")
    return sender == me or Short(sender) == me
end

-- A line in a channel: about a quest you're asking for (an answer), or one you have (someone else looking).
local function OnChannel(_, _, msg, sender)
    if Secret(msg) or Secret(sender) or type(sender) ~= "string" or Me(sender) then return end
    local t = YR.QuestLFGMatch(msg)
    if not t then return end
    local mine = asking[t.id] ~= nil
    if not mine and not Watching() then return end
    AddReply(sender, msg, t, mine and "channel" or "other")
end

-- A whisper while you're asking: an answer - to the quest it names, else to the one you asked for last.
local function OnWhisper(_, _, msg, sender)
    if Secret(msg) or Secret(sender) or type(sender) ~= "string" or type(msg) ~= "string" then return end
    local now, latest = Now(), nil
    for _, a in pairs(asking) do
        if now - a.at < LISTEN and (not latest or a.at > latest.at) then latest = a end
    end
    if not latest then
        YR.SettingChanged()         -- nothing asked for lately: whispers needn't be listened to
        return
    end
    local t = YR.QuestLFGMatch(msg)
    if not (t and asking[t.id]) then t = latest end
    AddReply(sender, msg, t, "whisper")
end

-- The log changed: the names are read again when next needed, and a quest gone from it isn't asked for.
local function OnQuests(_, event, id)
    titles = nil
    if event ~= "QUEST_ACCEPTED" then
        local have = {}
        for _, q in ipairs(YR.QuestLFGQuests()) do have[q.id] = true end
        local gone = false
        for qid in pairs(asking) do if not have[qid] then asking[qid] = nil gone = true end end
        if gone then YR.SettingChanged() end
    end
    if win and win:IsShown() and Draw then Draw() end
end

function YR.QuestLFGInvite(who)
    if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(who) end
end
function YR.QuestLFGWhisper(who)
    if ChatFrame_SendTell then ChatFrame_SendTell(who) end
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
local W, H, ROW = 440, 480, 30
local rows = {}

local function Row(i)
    local r = rows[i]
    if r then return r end
    local S = YR.Style
    r = CreateFrame("Frame", nil, win.area.content)
    r:SetSize(W - 46, ROW)
    r.head = S.Text(r, 11, S.C.muted)
    r.head:SetPoint("BOTTOMLEFT", 2, 5)
    r.text = S.Text(r, 13)
    r.text:SetPoint("TOPLEFT", 2, -2)
    r.text:SetWidth(W - 46 - 150)
    r.sub = S.Text(r, 11, S.C.muted)
    r.sub:SetPoint("TOPLEFT", 2, -16)
    r.sub:SetWidth(W - 46 - 150)
    r.b2 = S.Button(r, "", nil, nil, 66)
    r.b2:SetHeight(22)
    r.b2:SetPoint("RIGHT", 0, 0)
    r.b1 = S.Button(r, "", nil, "primary", 66)
    r.b1:SetHeight(22)
    r.b1:SetPoint("RIGHT", r.b2, "LEFT", -6, 0)
    rows[i] = r
    return r
end

-- One line of the window: a heading (text nil), or a text with a smaller line under it and up to two buttons.
local n
local function Line(head, text, sub, l1, f1, l2, f2)
    n = n + 1
    local r = Row(n)
    r:SetPoint("TOPLEFT", 0, -(n - 1) * ROW)
    r.head:SetText(head or "")
    r.text:SetText(text or "")
    r.sub:SetText(sub or "")
    r.b1:SetShown(l1 ~= nil)
    r.b2:SetShown(l2 ~= nil)
    if l1 then r.b1.text:SetText(l1) r.b1:SetScript("OnClick", f1) end
    if l2 then r.b2.text:SetText(l2) r.b2:SetScript("OnClick", f2) end
    r:Show()
end

local function Said(ok, why) if not ok and why then YR.Print(why) end end

function Draw()
    if not (win and win:IsShown()) then return end
    n = 0
    local any = false
    for _, a in pairs(asking) do
        if not any then Line("ASKING FOR") any = true end
        local q = a
        Line(nil, a.title, "said in " .. tostring(a.channel or "chat"), "Again", function() Said(YR.QuestLFGAsk(q)) end,
            "Stop", function() YR.QuestLFGStop(q.id) end)
    end
    for pass = 1, 2 do
        local first = true
        for _, r in ipairs(replies) do
            if (r.kind == "other") == (pass == 2) then
                if first then Line(pass == 1 and "ANSWERS" or "OTHERS LOOKING, FOR QUESTS YOU HAVE") first = false end
                local who = r.who
                Line(nil, Short(who) .. (r.kind == "whisper" and "  |cff7f8794whispered|r" or ""),
                    ("%s: %s"):format(r.quest, (r.text:gsub("|", "||"))),
                    "Invite", function() YR.QuestLFGInvite(who) end, "Whisper", function() YR.QuestLFGWhisper(who) end)
            end
        end
    end
    Line("YOUR QUESTS")
    local quests = YR.QuestLFGQuests()
    for _, q in ipairs(quests) do
        local quest = q
        Line(nil, ("|cff7f8794%d|r  %s"):format(q.level, q.title),
            (q.group and ("for %d players" .. (q.tracked and ", tracked" or "")):format(q.group)) or (q.tracked and "tracked" or nil),
            not asking[q.id] and "Ask" or nil, function() Said(YR.QuestLFGAsk(quest)) end)
    end
    if #quests == 0 then Line(nil, "|cff7f8794No quest in your log to ask for.|r") end
    for i = n + 1, #rows do rows[i]:Hide() end
    win.area.content:SetHeight(math.max(10, n * ROW))
    if win.area.UpdateBar then win.area:UpdateBar() end
    local id, name = YR.QuestLFGChannel()
    win.foot:SetText(id and ("Asks in %d. %s  (Settings, QoL, Group)"):format(id, name) or "You're in no chat channel to ask in.")
end

local function Build()
    if win then return end
    local S = YR.Style
    win = S.Window("HeadstartQuestLFGWindow", W, H, "Quest group")
    win:SetFrameStrata("HIGH")
    win.area = S.ScrollArea(win, W - 32, H - 48 - 16 - 40)
    win.area:SetPoint("TOPLEFT", 16, -60)
    win.foot = S.Text(win, 12, S.C.muted)
    win.foot:SetPoint("BOTTOMLEFT", 16, 14)
end

function YR.QuestLFGToggle()
    if not YR.QuestLFGOn() then
        YR.Print("Quest group is off: turn it on in Headstart, QoL, Group.")
        return false
    end
    Build()
    if win:IsShown() then win:Hide() return false end
    unseen = 0
    Badge()
    win:Show()
    Draw()
    return true
end

-- ---------------------------------------------------------------------------
-- The eye
-- ---------------------------------------------------------------------------
local function Place()
    local pos = YippRouteDB.questLFGPos
    button:ClearAllPoints()
    if type(pos) == "table" then
        button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos[1], pos[2])
    elseif _G.ObjectiveTrackerFrame then
        button:SetPoint("TOPRIGHT", _G.ObjectiveTrackerFrame, "TOPLEFT", -6, -2)
    else
        button:SetPoint("RIGHT", UIParent, "RIGHT", -260, 120)
    end
end

local function MakeButton()
    if button then return end
    local S = YR.Style
    button = CreateFrame("Button", "HeadstartQuestLFGButton", UIParent)
    button:SetSize(26, 26)
    button:SetFrameStrata("MEDIUM")
    button:SetClampedToScreen(true)
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexture(133884)                  -- an eye
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    S.Border(button, { 0, 0, 0, 0.9 })
    button.glow = button:CreateTexture(nil, "OVERLAY")
    button.glow:SetPoint("TOPLEFT", -2, 2)
    button.glow:SetPoint("BOTTOMRIGHT", 2, -2)
    button.glow:SetColorTexture(0.40, 0.66, 1.00, 0.35)
    button.glow:Hide()
    button.count = S.Text(button, 12, S.C.gold)
    button.count:SetPoint("BOTTOMRIGHT", 2, -2)
    button.count:SetFont(S.FONT, 12, "OUTLINE")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", function() YR.QuestLFGToggle() end)
    button:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        if x and y then YippRouteDB.questLFGPos = { math.floor(x + 0.5), math.floor(y + 0.5) } end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Quest group")
        GameTooltip:AddLine(unseen > 0 and (unseen .. " you haven't looked at") or "Ask chat for a group for one of your quests", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Shift-drag moves it", 0.5, 0.53, 0.58)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function YR.QuestLFGResetPosition()
    YippRouteDB.questLFGPos = nil
    if button then Place() end
end

local function Begin()
    MakeButton()
    Place()
    Badge()
    button:Show()
end
local function End()
    if button then button:Hide() end
    if win then win:Hide() end
    for id in pairs(asking) do asking[id] = nil end
end

local declared
function YR.StartQuestLFG()
    if declared then return end
    declared = true
    YR.Part(YR.QuestLFGOn, { "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }, OnQuests, { start = Begin, stop = End })
    YR.Part(function() return YR.QuestLFGOn() and (Watching() or AnyAsking()) end, { "CHAT_MSG_CHANNEL" }, OnChannel)
    YR.Part(function() return YR.QuestLFGOn() and AnyAsking() end, { "CHAT_MSG_WHISPER" }, OnWhisper)
end
