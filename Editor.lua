-- The YippRoute window: edit the routes, see what this character did, share a route, settings.
-- Opened from the minimap's addon menu or /yroute.
--
--   Routes     each shipped guide as a list of steps: drag a row (or use the arrows) to move it, x to
--              remove it, click to select it (new steps go in after the selected one). Save keeps your
--              version; Revert goes back to the shipped one. Either reaches RestedXP on /reload.
--   This run   what this character did (quests, purchases, spells learned, hearths, deaths): + turns
--              one into a step of the route open in Routes.
--   Share      the open route as text to copy, or paste someone's route and import it.
--   Settings   the same switches as the options page.
local _, YR = ...
local S = YR.Style

local W, H, SIDE, ROW, ROWS = 780, 540, 170, 22, 19
local win, pages, current
local edit = { key = nil, header = nil, steps = nil, dirty = false, sel = nil, offset = 0 }

StaticPopupDialogs["YIPPROUTE_RELOAD"] = {
    text = "YippRoute: reload so RestedXP gets the changed route?",
    button1 = "Reload",
    button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- ---------------------------------------------------------------------------
-- A scrolling list of rows, drawn by the caller: fill(row, index) sets a row up for item `index`.
-- ---------------------------------------------------------------------------
local function List(parent, width, count, fill, total)
    local l = CreateFrame("Frame", nil, parent)
    l:SetSize(width, ROW * count)
    l.rows, l.offset = {}, 0
    for i = 1, count do
        local r = CreateFrame("Button", nil, l)
        r:SetSize(width - 8, ROW)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
        r.bg = S.Fill(r, { 0, 0, 0, 0 })
        r.num = S.Text(r, 12, S.C.muted)
        r.num:SetPoint("LEFT", 6, 0)
        r.num:SetWidth(30)
        r.label = S.Text(r, 13)
        r.label:SetPoint("LEFT", 40, 0)
        r.label:SetPoint("RIGHT", -70, 0)
        r:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(unpack(S.C.hover)) end
            if self.OnHover then self:OnHover(true) end end)
        r:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end
            if self.OnHover then self:OnHover(false) end end)
        l.rows[i] = r
    end
    -- a thin bar on the right that shows where in the list you are
    l.bar = l:CreateTexture(nil, "OVERLAY")
    l.bar:SetColorTexture(1, 1, 1, 0.18)
    l.bar:SetWidth(3)
    function l:Refresh()
        local n = total()
        self.offset = math.max(0, math.min(self.offset, n - count))
        for i, r in ipairs(self.rows) do
            local index = self.offset + i
            if index <= n then r:Show() fill(r, index) else r:Hide() end
        end
        local h = ROW * count
        if n > count then
            self.bar:Show()
            self.bar:SetHeight(math.max(20, h * count / n))
            self.bar:ClearAllPoints()
            self.bar:SetPoint("TOPRIGHT", 0, -(h - self.bar:GetHeight()) * self.offset / (n - count))
        else
            self.bar:Hide()
        end
    end
    l:EnableMouseWheel(true)
    l:SetScript("OnMouseWheel", function(self, delta)
        self.offset = self.offset - delta * 3
        self:Refresh()
    end)
    return l
end

local function Select(r, on)
    r.selected = on
    r.bg:SetColorTexture(unpack(on and S.C.select or { 0, 0, 0, 0 }))
end

-- ---------------------------------------------------------------------------
-- Routes
-- ---------------------------------------------------------------------------
local routes = {}

local function Open(key)
    edit.key = key
    edit.header, edit.steps = YR.SplitSteps(YR:GuideText(key))
    edit.dirty, edit.sel = false, nil
    if routes.list then routes.list.offset = 0 end
end

local function Move(from, to)
    if not (from and to) or from == to or to < 1 or to > #edit.steps then return end
    local step = table.remove(edit.steps, from)
    table.insert(edit.steps, to, step)
    edit.sel, edit.dirty = to, true
    YR:RefreshWindow()
end

local function Remove(i)
    table.remove(edit.steps, i)
    if edit.sel and edit.sel >= i then edit.sel = edit.sel > 1 and edit.sel - 1 or nil end
    edit.dirty = true
    YR:RefreshWindow()
end

-- Put a step in after the selected one (or at the end) and select it.
function YR:InsertStep(text)
    if not edit.steps then return end
    local at = (edit.sel or #edit.steps) + 1
    table.insert(edit.steps, at, text)
    edit.sel, edit.dirty = at, true
    YR:RefreshWindow()
end

local function BuildRoutes(page)
    routes.name = S.Text(page, 15)
    routes.name:SetPoint("TOPLEFT", 0, 0)
    routes.state = S.Text(page, 12, S.C.muted)
    routes.state:SetPoint("LEFT", routes.name, "RIGHT", 10, 0)
    routes.hint = S.Text(page, 12, S.C.muted)
    routes.hint:SetPoint("TOPLEFT", 0, -22)
    routes.hint:SetText("Drag a step to move it. Click to select: new steps go in after it.")

    local dragFrom
    routes.list = List(page, W - SIDE - 40, ROWS, function(r, i)
        r.index = i
        r.num:SetText(i)
        r.label:SetText(YR.StepSummary(edit.steps[i]))
        Select(r, edit.sel == i)
    end, function() return edit.steps and #edit.steps or 0 end)
    routes.list:SetPoint("TOPLEFT", 0, -44)
    for _, r in ipairs(routes.list.rows) do
        r:RegisterForDrag("LeftButton")
        r:SetScript("OnClick", function(self) edit.sel = self.index YR:RefreshWindow() end)
        r:SetScript("OnDragStart", function(self) dragFrom = self.index end)
        r:SetScript("OnDragStop", function()
            for _, other in ipairs(routes.list.rows) do
                if other:IsShown() and other:IsMouseOver() then Move(dragFrom, other.index) break end
            end
            dragFrom = nil
        end)
        function r:OnHover(on)
            if not on then GameTooltip:Hide() return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local n = 0
            for line in (edit.steps[self.index] .. "\n"):gmatch("([^\n]*)\n") do
                n = n + 1
                if n > 16 then GameTooltip:AddLine("...", 0.6, 0.6, 0.6) break end
                GameTooltip:AddLine(line, 0.9, 0.9, 0.9)
            end
            GameTooltip:Show()
        end
        local up = S.Mini(r, "^", function() Move(r.index, r.index - 1) end)
        up:SetPoint("RIGHT", -44, 0)
        local down = S.Mini(r, "v", function() Move(r.index, r.index + 1) end)
        down:SetPoint("RIGHT", -24, 0)
        local x = S.Mini(r, "x", function() Remove(r.index) end, S.C.danger)
        x:SetPoint("RIGHT", -4, 0)
    end

    local save = S.Button(page, "Save", function()
        YR:SaveCustom(edit.key, edit.header, edit.steps)
        edit.dirty = false
        YR:RefreshWindow()
        StaticPopup_Show("YIPPROUTE_RELOAD")
    end, true)
    save:SetPoint("BOTTOMLEFT", 0, 0)
    local revert = S.Button(page, "Back to the shipped route", function()
        YR:RevertGuide(edit.key)
        Open(edit.key)
        YR:RefreshWindow()
        StaticPopup_Show("YIPPROUTE_RELOAD")
    end)
    revert:SetPoint("LEFT", save, "RIGHT", 8, 0)
    local undo = S.Button(page, "Undo changes", function() Open(edit.key) YR:RefreshWindow() end)
    undo:SetPoint("LEFT", revert, "RIGHT", 8, 0)
end

local function RefreshRoutes()
    if not edit.key then return end
    routes.name:SetText(YR.GuideName(edit.key))
    routes.state:SetText((edit.dirty and "unsaved changes" or (YR:IsCustom(edit.key) and "your version" or "as shipped"))
        .. "  -  " .. #edit.steps .. " steps")
    routes.list:Refresh()
end

-- ---------------------------------------------------------------------------
-- This run
-- ---------------------------------------------------------------------------
local run = {}

local function BuildRun(page)
    run.title = S.Text(page, 15)
    run.title:SetPoint("TOPLEFT", 0, 0)
    run.title:SetText("What this character did")
    run.hint = S.Text(page, 12, S.C.muted)
    run.hint:SetPoint("TOPLEFT", 0, -22)
    run.list = List(page, W - SIDE - 40, ROWS, function(r, i)
        local a = run.actions[i]
        r.action = a
        r.num:SetText(i)
        r.label:SetText(a.label)
    end, function() return run.actions and #run.actions or 0 end)
    run.list:SetPoint("TOPLEFT", 0, -44)
    for _, r in ipairs(run.list.rows) do
        local add = S.Mini(r, "+", function() if r.action.step then YR:InsertStep(r.action.step) end end, S.C.accent)
        add:SetPoint("RIGHT", -4, 0)
        function r:OnHover(on)
            if not on then GameTooltip:Hide() return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("+ adds this as a step to the route open in Routes:", 1, 1, 1)
            for line in ((self.action.step or "") .. "\n"):gmatch("([^\n]*)\n") do GameTooltip:AddLine(line, 0.8, 0.8, 0.8) end
            GameTooltip:Show()
        end
    end
    run.record = S.Toggle(page, "Record this run", function() return YippRouteDB.logging end,
        function(on) YR:SetLogging(on) end)
    run.record:SetPoint("BOTTOMLEFT", 0, 2)
end

local function RefreshRun()
    run.actions = YR:RunActions()
    run.hint:SetText(("%d actions. + adds one as a step after the step selected in Routes (%s)."):format(
        #run.actions, edit.key and YR.GuideName(edit.key) or "open a route first"))
    run.list.offset = math.max(0, #run.actions - ROWS)      -- newest at the bottom, in view
    run.list:Refresh()
    run.record:Refresh()
end

-- ---------------------------------------------------------------------------
-- Share
-- ---------------------------------------------------------------------------
local share = {}

local function BuildShare(page)
    local title = S.Text(page, 15)
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText("Share a route")
    share.hint = S.Text(page, 12, S.C.muted)
    share.hint:SetPoint("TOPLEFT", 0, -22)
    share.hint:SetText("Export puts the open route here: Ctrl+A, Ctrl+C. To import, paste a route and press Import.")

    local box = CreateFrame("ScrollFrame", nil, page)
    box:SetPoint("TOPLEFT", 0, -46)
    box:SetSize(W - SIDE - 40, ROW * ROWS - 30)
    S.Fill(box, { 0, 0, 0, 0.35 })
    S.Border(box)
    local text = CreateFrame("EditBox", nil, box)
    text:SetMultiLine(true)
    text:SetAutoFocus(false)
    text:SetFont(S.FONT, 12, "")
    text:SetTextColor(unpack(S.C.text))
    text:SetWidth(W - SIDE - 56)
    text:SetTextInsets(8, 8, 8, 8)
    text:SetScript("OnEscapePressed", text.ClearFocus)
    box:SetScrollChild(text)
    box:EnableMouseWheel(true)
    box:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 40)))
    end)
    box:SetScript("OnMouseDown", function() text:SetFocus() end)
    share.text = text

    local export = S.Button(page, "Export open route", function()
        if not edit.key then return end
        text:SetText(YR.JoinSteps(edit.header, edit.steps))
        text:SetFocus()
        text:HighlightText()
    end, true)
    export:SetPoint("BOTTOMLEFT", 0, 0)
    local import = S.Button(page, "Import", function()
        local done, why = YR:ImportGuide(text:GetText())
        share.hint:SetText(done and ("Imported: " .. done .. ". Reload to use it.") or ("Not imported: " .. why))
        if done then
            if edit.key then Open(edit.key) end
            StaticPopup_Show("YIPPROUTE_RELOAD")
        end
    end)
    import:SetPoint("LEFT", export, "RIGHT", 8, 0)
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
local settings = {}
local rewards = {}

local KIND_LABEL = {}
for _, k in ipairs(YR.REWARD_KINDS) do KIND_LABEL[k.key] = k.label end

local function Heading(page, text, x, y)
    local h = S.Text(page, 15)
    h:SetPoint("TOPLEFT", x, y)
    h:SetText(text)
    return h
end

local function BuildSettings(page)
    -- left: the general switches, then the rewards you chose yourself
    Heading(page, "Settings", 0, 0)
    local y = -34
    for _, o in ipairs({
        { "Show level splits", "showSplits", function(on) YR:ShowSplits(on) end },
        { "Pick quest rewards", "pickRewards" },
        { "Record runs", "logging", function(on) YR:SetLogging(on) end },
        { "Minimap button", "minimapButton", function(on) YR:ShowMinimapButton(on) end },
    }) do
        local t = S.Toggle(page, o[1], function() return YR.Option(o[2]) end, function(on)
            YippRouteDB[o[2]] = on
            if o[3] then o[3](on) end
        end)
        t:SetPoint("TOPLEFT", 0, y)
        settings[#settings + 1] = t
        y = y - 30
    end

    Heading(page, "Rewards you chose yourself", 0, y - 12)
    local hint = S.Text(page, 12, S.C.muted)
    hint:SetPoint("TOPLEFT", 0, y - 34)
    hint:SetText("Shift when handing in to choose; taken again next time.")
    rewards.chosen = List(page, 260, 8, function(r, i)
        local e = rewards.chosenList[i]
        r.quest = e.quest
        r.num:SetText("")
        r.label:SetPoint("LEFT", 6, 0)
        r.label:SetText((e.title or ("quest " .. e.quest)) .. ": " .. (e.name or e.item))
    end, function() return rewards.chosenList and #rewards.chosenList or 0 end)
    rewards.chosen:SetPoint("TOPLEFT", 0, y - 54)
    for _, r in ipairs(rewards.chosen.rows) do
        local x = S.Mini(r, "x", function()
            YR:RewardSettings().chosen[r.quest] = nil
            YR:RefreshWindow()
        end, S.C.danger)
        x:SetPoint("RIGHT", -4, 0)
    end

    -- right: how the picker chooses
    local X = 290
    Heading(page, "Quest rewards", X, 0)
    local level = S.Text(page, 13)
    level:SetPoint("TOPLEFT", X, -38)
    rewards.level = level
    local minus = S.Mini(page, "-", function()
        local db = YR:RewardSettings() db.maxLevel = math.max(1, db.maxLevel - 1) YR:RefreshWindow() end, S.C.text)
    minus:SetPoint("TOPLEFT", X + 170, -34)
    local plus = S.Mini(page, "+", function()
        local db = YR:RewardSettings() db.maxLevel = math.min(60, db.maxLevel + 1) YR:RefreshWindow() end, S.C.text)
    plus:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    local remember = S.Toggle(page, "Take the reward I chose before", function() return YR:RewardSettings().remember end,
        function(on) YR:RewardSettings().remember = on end)
    remember:SetPoint("TOPLEFT", X, -60)
    local value = S.Toggle(page, "Nothing below on offer: most valuable",
        function() return YR:RewardSettings().fallback == "value" end,
        function(on) YR:RewardSettings().fallback = on and "value" or "ask" end)
    value:SetPoint("TOPLEFT", X, -86)
    settings[#settings + 1] = remember
    settings[#settings + 1] = value
    local order = S.Text(page, 12, S.C.muted)
    order:SetPoint("TOPLEFT", X, -114)
    order:SetText("Take the first of these on offer. Click to turn one off.")
    rewards.order = List(page, W - SIDE - 40 - X, #YR.REWARD_KINDS, function(r, i)
        local db = YR:RewardSettings()
        local kind = db.order[i]
        r.index = i
        r.num:SetText(i)
        r.label:SetText(KIND_LABEL[kind] or kind)
        r.label:SetTextColor(unpack(db.off[kind] and S.C.muted or S.C.text))
    end, function() return #YR:RewardSettings().order end)
    rewards.order:SetPoint("TOPLEFT", X, -132)
    for _, r in ipairs(rewards.order.rows) do
        r:SetScript("OnClick", function(self)
            local db = YR:RewardSettings()
            local kind = db.order[self.index]
            db.off[kind] = not db.off[kind] or nil
            YR:RefreshWindow()
        end)
        local function Swap(d)
            local db = YR:RewardSettings()
            local a, b = r.index, r.index + d
            if b < 1 or b > #db.order then return end
            db.order[a], db.order[b] = db.order[b], db.order[a]
            YR:RefreshWindow()
        end
        local up = S.Mini(r, "^", function() Swap(-1) end)
        up:SetPoint("RIGHT", -24, 0)
        local down = S.Mini(r, "v", function() Swap(1) end)
        down:SetPoint("RIGHT", -4, 0)
    end
end

local function RefreshSettings()
    for _, t in ipairs(settings) do t:Refresh() end
    local db = YR:RewardSettings()
    rewards.level:SetText(("Up to level %d"):format(db.maxLevel))
    rewards.chosenList = {}
    for quest, e in pairs(db.chosen) do
        rewards.chosenList[#rewards.chosenList + 1] = { quest = quest, item = e.item, name = e.name, title = e.title }
    end
    table.sort(rewards.chosenList, function(a, b) return (a.title or "") < (b.title or "") end)
    rewards.chosen:Refresh()
    rewards.order:Refresh()
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
local PAGES = {
    { key = "routes", label = "Routes", build = BuildRoutes, refresh = RefreshRoutes },
    { key = "run", label = "This run", build = BuildRun, refresh = RefreshRun },
    { key = "share", label = "Share", build = BuildShare, refresh = function() end },
    { key = "settings", label = "Settings", build = BuildSettings,
      refresh = RefreshSettings },
}

local function Show(key)
    current = key
    for _, p in ipairs(PAGES) do
        pages[p.key]:SetShown(p.key == key)
        p.tab.bg:SetColorTexture(unpack(p.key == key and S.C.select or { 0, 0, 0, 0 }))
    end
    YR:RefreshWindow()
end

local function Build()
    win = S.Window("YippRouteWindow", W, H, "YippRoute")
    local side = CreateFrame("Frame", nil, win)
    side:SetPoint("TOPLEFT", 1, -44)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDE)
    S.Fill(side, S.C.side)
    pages = {}
    local y = -10
    for _, p in ipairs(PAGES) do
        local tab = CreateFrame("Button", nil, side)
        tab:SetSize(SIDE - 16, 26)
        tab:SetPoint("TOPLEFT", 8, y)
        tab.bg = S.Fill(tab, { 0, 0, 0, 0 })
        local t = S.Text(tab, 14)
        t:SetPoint("LEFT", 10, 0)
        t:SetText(p.label)
        tab:SetScript("OnClick", function() Show(p.key) end)
        p.tab = tab
        y = y - 30
        -- under Routes: one entry per route we ship
        if p.key == "routes" then
            for _, g in ipairs(YR.shipped) do
                local sub = CreateFrame("Button", nil, side)
                sub:SetSize(SIDE - 24, 20)
                sub:SetPoint("TOPLEFT", 16, y)
                local st = S.Text(sub, 12, S.C.muted)
                st:SetPoint("LEFT", 10, 0)
                st:SetPoint("RIGHT", 0, 0)
                st:SetText(YR.GuideName(g.key))
                sub:SetScript("OnClick", function() Open(g.key) Show("routes") end)
                sub:SetScript("OnEnter", function() st:SetTextColor(unpack(S.C.text)) end)
                sub:SetScript("OnLeave", function() st:SetTextColor(unpack(S.C.muted)) end)
                y = y - 22
            end
            y = y - 6
        end
        local page = CreateFrame("Frame", nil, win)
        page:SetPoint("TOPLEFT", SIDE + 20, -52)
        page:SetPoint("BOTTOMRIGHT", -20, 16)
        p.build(page)
        pages[p.key] = page
    end
    if YR.shipped[1] then Open(YR.shipped[1].key) end
end

function YR:RefreshWindow()
    if not (win and win:IsShown()) then return end
    for _, p in ipairs(PAGES) do
        if p.key == current then p.refresh() end
    end
end

function YR:ToggleWindow(page)
    if not win then Build() end
    if win:IsShown() and not page then win:Hide() return end
    win:Show()
    Show(page or current or "routes")
end

function YippRoute_OnAddonCompartmentClick()
    YR:ToggleWindow()
end
