-- Loot feed and loot log: what you just got, as a short stack of lines on screen that fade - items
-- with their icon, money, experience, reputation - and a log of it with the session's sums and what
-- that is an hour.
--   Where it comes from: the game's own chat lines (CHAT_MSG_LOOT, CHAT_MSG_MONEY,
--   CHAT_MSG_COMBAT_FACTION_CHANGE), read with patterns made from the game's own sentences, so they
--   work in any language; experience from the change in your XP. A line the game keeps secret (chat
--   can be, in instances) is passed over: it can't be read.
--   The same item again within the feed's time is one line with a higher count, not two.
--   Free while off: nothing is listened for, no frame is made and the sentences' patterns aren't
--   built until it is turned on; a log left over from when it was on is dropped at the next login.
--   Nothing runs per frame while a line shows: a line's fading is the game's own animation, and one
--   timer wakes us when the oldest line has run out.
--   Account options (YippRouteDB; Headstart, QoL, Loot): lootFeed (off until turned on), lootItems,
--   lootMoney, lootXP, lootRep (each on unless turned off), lootQuality (lowest item quality shown, 0),
--   lootSeconds (4), lootLock (on unless turned off), lootFeedPos, lootStyle ("cards": each line a
--   dark card with a bigger icon; anything else: plain lines), lootPrice (what an item sells for, at
--   the right of its line: on in cards and off in lines unless set). Per character: HeadstartLootLog =
--   { entries = { { time, "i", link, count, value } | { time, "r", faction, amount } }, session = {
--   start, money, value, xp, items } }.
local ADDON, YR = ...

local ROWS, ROW_H, W = 6, 22, 280
local FADE = 0.6
local LOG_MAX = 800
local on = false
local holder, win
local rows = {}                 -- the lines on screen, newest first: { key, kind, what, count, icon, till }
local waking = false            -- a timer is set for when the oldest line runs out
local lastXP, lastMax, lastLevel
local LOOT, COIN, REP           -- the patterns, made when the feed is first on
local issecret = issecretvalue

function YR.LootFeedOn() return YR.Option("lootFeed") end
local function Shows(key) return YippRouteDB[key] ~= false end
local function Seconds() return math.max(2, math.min(15, tonumber(YippRouteDB.lootSeconds) or 4)) end
local function Cards() return YippRouteDB.lootStyle == "cards" end
local function Prices()
    if YippRouteDB.lootPrice == nil then return Cards() end
    return YippRouteDB.lootPrice == true
end
-- A line's height and the gap under it, and the feed's width, in the look that is on.
local CARD_H, CARD_GAP, CARD_W = 34, 3, 250
local function Pitch() return Cards() and (CARD_H + CARD_GAP) or ROW_H end

-- "4" and a copper coin, as the game writes money - or in letters where it has no such function.
local function Price(copper)
    local coins = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or _G.GetCoinTextureString
    if type(coins) == "function" then
        local ok, text = pcall(coins, copper)
        if ok and type(text) == "string" then return text end
    end
    return YR.Coins(copper)
end

local function DB()
    local db = _G.HeadstartLootLog
    if type(db) ~= "table" then
        db = {}
        _G.HeadstartLootLog = db
    end
    if type(db.entries) ~= "table" then db.entries = {} end
    if type(db.session) ~= "table" then db.session = { start = time(), money = 0, value = 0, xp = 0, items = 0 } end
    return db
end

--- "1g 20s 40c" from copper, in the coins' colours.
function YR.Coins(copper)
    copper = math.floor((copper or 0) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
    if g > 0 then return ("|cffffd100%dg|r |cffc7c7cf%ds|r |cffeda55f%dc|r"):format(g, s, c) end
    if s > 0 then return ("|cffc7c7cf%ds|r |cffeda55f%dc|r"):format(s, c) end
    return ("|cffeda55f%dc|r"):format(c)
end

-- ---------------------------------------------------------------------------
-- Reading the game's sentences
-- ---------------------------------------------------------------------------
-- A pattern from one of the game's sentences: "%s" a text, "%d" a number, the rest literal.
local function Pattern(fmt, loose)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%(%)%.%[%]%-%+%*%?%^%$])", "%%%1")
    p = p:gsub("%%%d?%$?s", "(.+)"):gsub("%%%d?%$?d", "(%%d+)")
    return loose and p or ("^" .. p .. "$")
end

local function Patterns()
    if LOOT then return end
    LOOT = {}
    for _, s in ipairs({ LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_PUSHED_SELF }) do
        LOOT[#LOOT + 1] = Pattern(s)
    end
    -- an amount's own words inside a longer sentence ("... 5 Silver, 74 Copper"): not anchored
    COIN = { { Pattern(GOLD_AMOUNT, true), 10000 }, { Pattern(SILVER_AMOUNT, true), 100 }, { Pattern(COPPER_AMOUNT, true), 1 } }
    REP = Pattern(FACTION_STANDING_INCREASED) or false
end

--- The item link and how many, from "You receive loot: [item]x2." (nil for anyone else's loot).
function YR.LootFromText(msg)
    Patterns()
    for i = 1, #LOOT do
        local link, n = msg:match(LOOT[i])
        if link and link:find("|Hitem:", 1, true) then return link, tonumber(n) or 1 end
    end
end

--- Copper from "You loot 5 Silver, 74 Copper" (0 for none).
function YR.MoneyFromText(msg)
    Patterns()
    local copper = 0
    for i = 1, 3 do
        local coin = COIN[i]
        local n = coin[1] and msg:match(coin[1])
        if n then copper = copper + (tonumber(n) or 0) * coin[2] end
    end
    return copper
end

-- ---------------------------------------------------------------------------
-- The feed
-- ---------------------------------------------------------------------------
-- What a line says: its kind, what it is of, and how many by now.
local function Words(r)
    if r.kind == "i" then return r.count > 1 and (r.what .. " x" .. r.count) or r.what end
    if r.kind == "m" then return "+ " .. YR.Coins(r.count) end
    if r.kind == "x" then return ("|cffb48cff+%d XP|r"):format(r.count) end
    if r.kind == "r" then return ("|cff66ccff+%d %s|r"):format(r.count, r.what) end
    return r.what
end

local function Place()
    holder:ClearAllPoints()
    local p = YippRouteDB.lootFeedPos
    if p and p[1] and p[2] then holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else holder:SetPoint("BOTTOM", UIParent, "BOTTOM", 320, 260) end
end

local Wake

-- The lines as they are now: what has run out goes, the rest move up, and each shown line's fade is
-- set going for the time it has left. Called when a line comes, and when the oldest has run out -
-- not per frame.
local function Layout()
    if not holder then return end
    local now, n, soonest = GetTime(), 0, nil
    for i = 1, ROWS do
        local r = rows[i]
        rows[i] = nil
        if r and r.till - now > 0.01 then
            n = n + 1
            rows[n] = r
            if not soonest or r.till < soonest then soonest = r.till end
        end
    end
    for i = 1, ROWS do
        local r, line = rows[i], holder.lines[i]
        if r then
            local words = Words(r)
            local worth = (r.value or 0) > 0 and Prices() and r.value or false
            if line.words ~= words or line.worth ~= worth then
                line.words, line.worth = words, worth
                line.text:SetText(words)
                line.value:SetText(worth and Price(worth) or "")
                line.icon:SetTexture(r.icon)
                line.icon:SetShown(r.icon ~= nil)
            end
            line:SetAlpha(1)
            line:Show()
            local fade = line.fade
            if fade then
                local left = r.till - now
                fade:Stop()
                fade.alpha:SetStartDelay(math.max(0, left - FADE))
                fade.alpha:SetDuration(math.min(FADE, left))
                fade:Play()
            end
        else
            line.words, line.worth = false, false
            if line.fade then line.fade:Stop() end
            line:Hide()
        end
    end
    local unlocked = YippRouteDB.lootLock == false
    holder.edge:SetShown(unlocked)
    holder:EnableMouse(unlocked)
    holder:SetShown(n > 0 or unlocked)
    if soonest and not waking then
        waking = true
        C_Timer.After(soonest - now + 0.02, Wake)
    end
end

function Wake()
    waking = false
    Layout()
end

-- The look that is on, put on the lines: plain lines, or cards (a dark plate with a thin edge, a
-- bigger icon with its own edge, and room at the right for what the item sells for).
local function Dress()
    if not holder then return end
    local cards = Cards()
    local h, pitch = cards and CARD_H or ROW_H, Pitch()
    local w = cards and CARD_W or W
    holder:SetSize(w, ROWS * pitch)
    for i = 1, ROWS do
        local line = holder.lines[i]
        line:SetSize(w, h)
        line:ClearAllPoints()
        line:SetPoint("BOTTOMLEFT", 0, (i - 1) * pitch)         -- the newest at the bottom
        line.plate:SetShown(cards)
        for _, t in ipairs(line.edges) do t:SetShown(cards) end
        for _, t in ipairs(line.iconEdge) do t:SetShown(cards) end
        local size = cards and (CARD_H - 8) or (ROW_H - 4)
        line.icon:SetSize(size, size)
        line.icon:ClearAllPoints()
        line.icon:SetPoint("LEFT", cards and 4 or 2, 0)
        line.text:SetFont(YR.Style.FONT, cards and 12 or 13, "OUTLINE")
        line.text:ClearAllPoints()
        line.text:SetPoint("LEFT", line.icon, "RIGHT", cards and 8 or 4, 0)
        line.text:SetPoint("RIGHT", line.value, "LEFT", -6, 0)
        line.value:ClearAllPoints()
        line.value:SetPoint("RIGHT", cards and -8 or -2, 0)
        line.value:SetFont(YR.Style.FONT, cards and 12 or 13, "OUTLINE")
    end
end

local function Build()
    if holder then return end
    local S = YR.Style
    holder = CreateFrame("Frame", "HeadstartLootFeed", UIParent)
    holder:SetSize(W, ROWS * ROW_H)
    holder:SetFrameStrata("MEDIUM")
    holder:SetClampedToScreen(true)
    holder:SetMovable(true)
    holder:RegisterForDrag("LeftButton")
    holder:SetScript("OnDragStart", function(self) if YippRouteDB.lootLock == false then self:StartMoving() end end)
    holder:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local l, b = self:GetLeft(), self:GetBottom()
        if l and b then YippRouteDB.lootFeedPos = { math.floor(l + 0.5), math.floor(b + 0.5) } end
        Place()
    end)
    holder.edge = holder:CreateTexture(nil, "BACKGROUND")
    holder.edge:SetAllPoints()
    holder.edge:SetColorTexture(0.3, 0.65, 1, 0.25)
    holder.lines = {}
    for i = 1, ROWS do
        local line = CreateFrame("Frame", nil, holder)
        line.plate = line:CreateTexture(nil, "BACKGROUND")
        line.plate:SetAllPoints()
        line.plate:SetColorTexture(0.05, 0.05, 0.06, 0.82)
        line.edges = S.Border(line, { 0, 0, 0, 0.9 })
        line.icon = S.Icon(line, nil, ROW_H - 4)
        -- a thin dark edge round the icon (cards)
        line.iconEdge = {}
        for n, at in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, -1 },
                { "TOPLEFT", "BOTTOMLEFT", -1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }) do
            local t = line:CreateTexture(nil, "BORDER")
            t:SetColorTexture(0, 0, 0, 1)
            t:SetPoint(at[1], line.icon, at[1], n > 2 and at[3] or -1, n > 2 and 1 or at[4])
            t:SetPoint(at[2], line.icon, at[2], n > 2 and at[3] or 1, n > 2 and -1 or at[4])
            if n > 2 then t:SetWidth(1) else t:SetHeight(1) end
            line.iconEdge[n] = t
        end
        line.text = line:CreateFontString(nil, "OVERLAY")
        line.text:SetJustifyH("LEFT")
        line.text:SetWordWrap(false)
        line.value = line:CreateFontString(nil, "OVERLAY")
        line.value:SetJustifyH("RIGHT")
        line.fade, line.words, line.worth = false, false, false
        -- its last moments it fades: the game's own animation, no code of ours a frame
        local group = line.CreateAnimationGroup and line:CreateAnimationGroup()
        local alpha = group and group.CreateAnimation and group:CreateAnimation("Alpha")
        if alpha then
            alpha:SetFromAlpha(1)
            alpha:SetToAlpha(0)
            if group.SetToFinalAlpha then group:SetToFinalAlpha(true) end
            group.alpha = alpha
            line.fade = group
        end
        line:Hide()
        holder.lines[i] = line
    end
    Dress()
    Place()
    holder:Hide()
end

-- A line on the feed. key: what it is the same thing as (the same item again adds to its count).
local function Feed(key, kind, what, count, icon, value)
    if not on then return end
    Build()
    local till = GetTime() + Seconds()
    for i = 1, ROWS do
        local r = rows[i]
        if r and r.key == key and kind then
            r.count, r.till, r.value = r.count + count, till, (r.value or 0) + (value or 0)
            Layout()
            return
        end
    end
    for i = ROWS, 2, -1 do rows[i] = rows[i - 1] end
    rows[1] = { key = key, kind = kind, what = what, count = count, icon = icon, till = till, value = value }
    for i = 1, ROWS do holder.lines[i].words = false end
    Layout()
end

local function Log(entry)
    local db = DB()
    db.entries[#db.entries + 1] = entry
    if #db.entries > LOG_MAX * 1.2 then
        local kept, from = {}, #db.entries - LOG_MAX
        for i = from + 1, #db.entries do kept[i - from] = db.entries[i] end
        db.entries = kept
    end
    if win and win:IsShown() then win.Fill() end
end

local function ItemText(link, count) return count > 1 and (link .. " x" .. count) or link end

local function GotItem(link, count)
    local id = tonumber(link:match("|Hitem:(%d+)"))
    local quality, price
    if C_Item and C_Item.GetItemInfo then
        local _, _, q, _, _, _, _, _, _, _, sell = C_Item.GetItemInfo(link)
        quality, price = q, sell
    end
    local value = (tonumber(price) or 0) * count
    local s = DB().session
    s.items, s.value, s.last = s.items + count, s.value + value, time()
    Log({ time(), "i", link, count, value })
    if Shows("lootItems") and (tonumber(quality) or 1) >= (tonumber(YippRouteDB.lootQuality) or 0) then
        Feed(id or link, "i", link, count, id and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) or nil, value)
    end
end

local function GotMoney(copper)
    local s = DB().session
    s.money, s.last = s.money + copper, time()
    if Shows("lootMoney") then Feed("money", "m", nil, copper, "Interface\\Icons\\INV_Misc_Coin_01") end
end

local function GotXP(xp)
    local s = DB().session
    s.xp, s.last = s.xp + xp, time()
    if Shows("lootXP") then Feed("xp", "x", nil, xp, "Interface\\Icons\\INV_Misc_Book_09") end
end

local function GotRep(faction, amount)
    Log({ time(), "r", faction, amount })
    if Shows("lootRep") then Feed(faction, "r", faction, amount, "Interface\\Icons\\INV_Misc_Ribbon_01") end
end

local function OnXP()
    local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
    if lastXP then
        local gained = level > lastLevel and (lastMax - lastXP + xp) or (xp - lastXP)
        if gained > 0 then GotXP(gained) end
    end
    lastXP, lastMax, lastLevel = xp, max, level
end

local function OnEvent(_, event, msg)
    if event == "PLAYER_XP_UPDATE" then return OnXP() end
    if type(msg) ~= "string" or (issecret and issecret(msg)) then return end
    if event == "CHAT_MSG_LOOT" then
        local link, count = YR.LootFromText(msg)
        if link then GotItem(link, count) end
    elseif event == "CHAT_MSG_MONEY" then
        local copper = YR.MoneyFromText(msg)
        if copper > 0 then GotMoney(copper) end
    elseif REP then
        local faction, amount = msg:match(REP)
        if faction and tonumber(amount) then GotRep(faction, tonumber(amount)) end
    end
end

-- ---------------------------------------------------------------------------
-- The log
-- ---------------------------------------------------------------------------
--- The session's sums and what they are an hour: { money, value, xp, items, hours, moneyHour, xpHour }.
function YR.LootSession()
    local s = DB().session
    local hours = math.max(1 / 60, (time() - (s.start or time())) / 3600)
    return { money = s.money, value = s.value, xp = s.xp, items = s.items, hours = hours,
        moneyHour = (s.money + s.value) / hours, xpHour = s.xp / hours }
end

function YR.LootSessionReset()
    DB().session = { start = time(), money = 0, value = 0, xp = 0, items = 0 }
    if win and win:IsShown() then win.Fill() end
end

function YR.LootLogClear()
    DB().entries = {}
    if win and win:IsShown() then win.Fill() end
end

function YR.LootLogCount() return #DB().entries end

local function BuildWindow()
    if win then return end
    local S = YR.Style
    win = S.Window("HeadstartLootLogWindow", 620, 500, "Loot log")
    win:SetFrameStrata("HIGH")
    win.sum = {}
    local labels = { "Money looted", "Vendor value of items", "Money and value an hour", "Experience", "Experience an hour", "Items" }
    for i, label in ipairs(labels) do
        local column, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local name = S.Text(win, 11, S.C.muted)
        name:SetPoint("TOPLEFT", 20 + column * 196, -62 - row * 40)
        name:SetText(label:upper())
        local value = S.Text(win, 15)
        value:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
        win.sum[i] = value
    end
    win.since = S.Text(win, 12, S.C.muted)
    win.since:SetPoint("BOTTOMLEFT", 16, 14)
    local reset = S.Button(win, "New session", function() YR.LootSessionReset() end, nil, 110)
    reset:SetPoint("BOTTOMRIGHT", -16, 10)
    reset.tip = "Restarts the session totals. The item list is kept"
    local field = CreateFrame("Frame", nil, win)
    field:SetPoint("TOPLEFT", 16, -148)
    field:SetPoint("BOTTOMRIGHT", -16, 44)
    S.Fill(field, S.C.field)
    S.Border(field)
    local list = CreateFrame("ScrollingMessageFrame", nil, field)
    list:SetPoint("TOPLEFT", 10, -8)
    list:SetPoint("BOTTOMRIGHT", -10, 8)
    list:SetFont(S.FONT, 13, "")
    list:SetJustifyH("LEFT")
    list:SetFading(false)
    list:SetMaxLines(LOG_MAX + 200)
    list:SetHyperlinksEnabled(true)
    list:SetScript("OnHyperlinkClick", function(self, link, words, mouse)
        if SetItemRef then pcall(SetItemRef, link, words, mouse, self) end
    end)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta)
        for _ = 1, IsShiftKeyDown() and 12 or 3 do
            if delta > 0 then self:ScrollUp() else self:ScrollDown() end
        end
    end)
    win.list = list
    function win.Fill()
        local s = YR.LootSession()
        win.sum[1]:SetText(YR.Coins(s.money))
        win.sum[2]:SetText(YR.Coins(s.value))
        win.sum[3]:SetText(YR.Coins(s.moneyHour))
        win.sum[4]:SetText(("%d"):format(s.xp))
        win.sum[5]:SetText(("%d"):format(s.xpHour))
        win.sum[6]:SetText(("%d"):format(s.items))
        win.since:SetText(("This session: %s%d min. Vendor value is the sell price, where the game provides it."):format(
            s.hours >= 1 and (math.floor(s.hours) .. " h ") or "", math.floor(s.hours * 60) % 60))
        list:Clear()
        local day
        for _, e in ipairs(DB().entries) do
            local d = date and date("%A %d %B", e[1]) or ""
            if d ~= day then day = d list:AddMessage("---- " .. d .. " ----", 0.5, 0.53, 0.58) end
            local stamp = date and date("%H:%M", e[1]) or ""
            if e[2] == "i" then
                list:AddMessage(("|cff8a827a%s|r  %s%s"):format(stamp, ItemText(e[3], e[4] or 1),
                    (e[5] or 0) > 0 and ("   " .. YR.Coins(e[5])) or ""))
            else
                list:AddMessage(("|cff8a827a%s|r  |cff66ccff+%d %s|r"):format(stamp, e[4] or 0, tostring(e[3])))
            end
        end
        if list.ScrollToBottom then list:ScrollToBottom() end
    end
end

function YR.LootLogToggle()
    if win and win:IsShown() then win:Hide() return end
    BuildWindow()
    win:Show()
    win.Fill()
end

-- ---------------------------------------------------------------------------
--- After a setting changed: as it is now (the feed shown to be moved while unlocked).
function YR.LootFeedApply()
    if not on then
        if holder then holder:Hide() end
        return
    end
    if YippRouteDB.lootLock == false then Build() end
    if holder then
        Dress()
        for i = 1, ROWS do holder.lines[i].words = false end
        Place()
        Layout()
    end
end

function YR.LootFeedResetPosition()
    YippRouteDB.lootFeedPos = nil
    if holder then Place() end
end

--- A few made-up lines, to see the feed and place it (Settings).
function YR.LootFeedSample()
    if not on then return false end
    Feed("sample0", nil, "|cff9d9d9d[Chipped Claw]|r", 0, "Interface\\Icons\\INV_Misc_MonsterClaw_04", 4)
    Feed("sample1", nil, "|cff1eff00[Sample Green Blade]|r x2", 0, "Interface\\Icons\\INV_Sword_04", 1240)
    Feed("sample2", nil, "+ " .. YR.Coins(1274), 0, "Interface\\Icons\\INV_Misc_Coin_01")
    Feed("sample3", nil, "|cffb48cff+320 XP|r", 0, "Interface\\Icons\\INV_Misc_Book_09")
    return true
end

function YR.StartLootFeed()
    -- Off: what the saved file still holds goes now, so it isn't read in at every login for nothing.
    -- (This runs as Headstart loads, when the saved file has just been read.)
    if not YR.LootFeedOn() then _G.HeadstartLootLog = nil end
    YR.Part(YR.LootFeedOn, { "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_COMBAT_FACTION_CHANGE", "PLAYER_XP_UPDATE" }, OnEvent, {
        start = function()
            on = true
            -- a session carries on over a reload or a short break; a quarter of an hour with nothing
            -- gained (you were logged out) and the next gain begins a new one
            local kept = type(_G.HeadstartLootLog) == "table" and _G.HeadstartLootLog.session
            if type(kept) == "table" and time() - (kept.last or kept.start or 0) > 900 then _G.HeadstartLootLog.session = nil end
            Patterns()
            lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
            YR.LootFeedApply()
        end,
        stop = function()
            on = false
            YR.LootFeedApply()
        end,
        again = YR.LootFeedApply,
    })
end
