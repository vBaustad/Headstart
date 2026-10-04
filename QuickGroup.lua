-- Quick group: get into a group for a kill and out again without typing. With 200 players on every
-- quest mob at launch, grouping up to share the tag is half the game.
--   * A small bar with Invite (your target) and Leave group, and key bindings for both (Key Bindings,
--     AddOns, Headstart). /headstart inv and /headstart leave do the same.
--   * Invite whoever whispers you "inv" (the word can be changed): guildies and friends, anyone, or nobody.
--   * Accept group invites: from guildies and friends, anyone, or nobody (the game asks as usual).
--     Hold Shift as the invite comes in to be asked anyway.
-- Account options (YippRouteDB, Settings, QoL): groupBar (on unless turned off), groupBarLocked (on
-- unless turned off), groupBarPos, whisperInvite ("friends" default | "anyone" | "off"), whisperWord
-- ("inv"), acceptInvites ("friends" default | "anyone" | "off").
local ADDON, YR = ...

local bar

local function Choice(key, default)
    local v = YippRouteDB[key]
    if v == "anyone" or v == "friends" or v == "off" then return v end
    return default
end
function YR.WhisperInvite() return Choice("whisperInvite", "friends") end
function YR.AcceptInvites() return Choice("acceptInvites", "friends") end
function YR.WhisperWord()
    local w = YippRouteDB.whisperWord
    return (type(w) == "string" and w ~= "") and w:lower() or "inv"
end

--- Can we invite at all: solo, or leading a group with room in it.
local function CanInvite()
    if not IsInGroup() then return true end
    if not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player") then return false, "you're not the leader" end
    if not IsInRaid() and GetNumGroupMembers() >= 5 then return false, "the group is full" end
    return true
end

--- Invite your target: a player, not you, not already with you.
function YR.InviteTarget()
    if not UnitExists("target") then YR.Print("target someone to invite.") return end
    if not UnitIsPlayer("target") or UnitIsUnit("target", "player") then YR.Print("that's not a player you can invite.") return end
    if UnitInParty("target") or UnitInRaid("target") then YR.Print("they're already in your group.") return end
    local ok, why = CanInvite()
    if not ok then YR.Print("can't invite: " .. why .. ".") return end
    local name = GetUnitName("target", true)
    if not name or (issecretvalue and issecretvalue(name)) then
        YR.Print("the game doesn't tell addons who that is here: invite them from their portrait.")
        return
    end
    C_PartyInfo.InviteUnit(name)
end

function YR.LeaveGroup()
    if not IsInGroup() then YR.Print("you're not in a group.") return end
    C_PartyInfo.LeaveParty()
end

-- ---------------------------------------------------------------------------
-- Whispers and invites
-- ---------------------------------------------------------------------------
local function Allowed(mode, unit, name, guid)
    if mode == "anyone" then return true end
    if mode == "friends" then return YR.IsFriendly(unit, name, guid) end
    return false
end

local function OnWhisper(text, sender, guid)
    local mode = YR.WhisperInvite()
    if mode == "off" or type(text) ~= "string" then return end
    if strtrim(text):lower() ~= YR.WhisperWord() then return end
    if not Allowed(mode, nil, sender, guid) then return end
    if not CanInvite() then return end
    if UnitInParty(Ambiguate(sender, "none")) or UnitInRaid(Ambiguate(sender, "none")) then return end
    C_PartyInfo.InviteUnit(sender)
end

local function OnInvite(name, guid)
    local mode = YR.AcceptInvites()
    if mode == "off" or IsShiftKeyDown() or IsInGroup() then return end
    if not Allowed(mode, nil, name, guid) then return end
    AcceptGroup()
    -- Hide the game's question the way its own Accept button does: marked accepted first, because
    -- the popup declines the invite when it is hidden without that mark.
    local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible("PARTY_INVITE")
    if dialog then
        dialog.inviteAccepted = 1
        StaticPopup_Hide("PARTY_INVITE")
    end
    YR.Print(("joined %s's group."):format(Ambiguate(name or "?", "short")))
end

-- ---------------------------------------------------------------------------
-- The bar
-- ---------------------------------------------------------------------------
local function Paint()
    if not bar then return end
    local canInv = UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player")
        and not (UnitInParty("target") or UnitInRaid("target")) and CanInvite()
    bar.invite:SetEnabled(canInv and true or false)
    bar.leave:SetEnabled(IsInGroup() and true or false)
end

local function Build()
    bar = CreateFrame("Frame", "HeadstartGroupBar", UIParent)
    bar:SetSize(176, 26)
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self) if not YR.Option("groupBarLocked") then self:StartMoving() end end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local l, t = self:GetLeft(), self:GetTop()
        if l and t then
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
            YippRouteDB.groupBarPos = { l, t }
        end
    end)
    local function Btn(text, fn, x)
        local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        b:SetSize(84, 22)
        b:SetPoint("LEFT", x, 0)
        b:SetText(text)
        b:SetScript("OnClick", fn)
        b:SetMotionScriptsWhileDisabled(true)
        return b
    end
    bar.invite = Btn("Invite", function() YR.InviteTarget() end, 2)
    bar.leave = Btn("Leave group", function() YR.LeaveGroup() end, 90)
    -- The drag edge, only while unlocked: the same blue as the campfire's.
    bar.edge = bar:CreateTexture(nil, "BACKGROUND")
    bar.edge:SetAllPoints()
    bar.edge:SetColorTexture(0.3, 0.65, 1, 0.35)
    bar:ClearAllPoints()
    local p = YippRouteDB.groupBarPos
    if p and p[1] and p[2] then bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 180) end
end

function YR.RefreshGroupBar()
    if not YR.Option("groupBar") then
        if bar then bar:Hide() end
        return
    end
    if not bar then Build() end
    bar.edge:SetShown(not YR.Option("groupBarLocked"))
    Paint()
    bar:Show()
end

function YR.SetGroupBar(on) YippRouteDB.groupBar = on and true or false YR.RefreshGroupBar() end
function YR.SetGroupBarLocked(on) YippRouteDB.groupBarLocked = on and true or false YR.RefreshGroupBar() end

function YR.StartQuickGroup()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "CHAT_MSG_WHISPER",
        "PARTY_INVITE_REQUEST" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event, a, b, ...)
        if event == "CHAT_MSG_WHISPER" then
            -- During chat lockdown whispers arrive as secret values, which can't be read: skip them.
            if issecretvalue and (issecretvalue(a) or issecretvalue(b)) then return end
            local guid = select(10, ...)          -- arg12: the sender's GUID
            pcall(OnWhisper, a, b, guid)
        elseif event == "PARTY_INVITE_REQUEST" then
            local guid = select(5, ...)           -- arg7: inviterGUID
            OnInvite(a, guid)
        else
            Paint()
        end
    end)
    YR.RefreshGroupBar()
end

-- Key bindings (Bindings.xml)
function Headstart_InviteTarget() YR.InviteTarget() end
function Headstart_LeaveGroup() YR.LeaveGroup() end
BINDING_HEADER_HEADSTART = "Headstart"
BINDING_NAME_HEADSTART_INVITE = "Invite target"
BINDING_NAME_HEADSTART_LEAVE = "Leave group"
