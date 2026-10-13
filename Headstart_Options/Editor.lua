-- The Headstart window. Opened from the minimap button or /yroute. Two tabs at the top, each with
-- its own menu down the left:
--
--   Levelling  This run, Share and Route settings, then the routes. A route opens in the editor: the
--              steps on the left; the selected step in full on the right, where every line of it can
--              be changed, added or removed: places (with "Here"), quests, targets, levels to farm
--              to, gold to farm, classes that see it. Save hands it to RestedXP.
--              This run: what this character did; "Add to route" makes any of it a step of the open
--              route. Share: the open route as text, or paste one in.
--   QoL        the settings pages (Find a setting at the top), Instances among them.
--
-- This file is the Headstart_Options addon: load on demand, loaded by Headstart the first time the
-- window is asked for (YR.LoadWindow, Core.lua), so none of it is in memory for someone who never
-- opens it. An addon of its own has a table of its own: Headstart's is handed over as HeadstartNS.
local YR = _G.HeadstartNS
local S = YR.Style

local W, H, SIDE, HEAD = 1140, 680, 180, 48
local PW, PH = W - SIDE, H - HEAD          -- a Levelling page: what is left beside its menu
-- QoL's menu is wider; its pages are what is left beside it, under a heading (as Route settings).
local NAV_W, TITLE_H = 210, 88
local CW, CH = W - NAV_W, PH - TITLE_H
local LIST_W, ROW = 480, 24
local win, pages, current
local edit = { key = nil, header = nil, steps = nil, parsed = {}, dirty = false, sel = nil, line = nil, filter = "" }
local ui = {}

StaticPopupDialogs["HEADSTART_DELETE_LOG"] = {
    text = "Headstart: delete the run log of %s? This can't be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(_, key) if YR.DeleteLog(key) then YR.Print("deleted the run log of " .. key .. ".") end YR:RefreshWindow() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Going back to the shipped route throws the player's edits away: ask first.
StaticPopupDialogs["HEADSTART_REVERT"] = {
    text = "Headstart: discard your edits to %s and use the original route?",
    button1 = "Use the shipped route",
    button2 = "Cancel",
    OnAccept = function(_, key) YR:RevertRoute(key) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_NAME = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
local CLASS_TEX = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local ZEBRA = S.C.stripe

-- ---------------------------------------------------------------------------
-- The route being edited
-- ---------------------------------------------------------------------------
local function Parsed(i)
    local p = edit.parsed[i]
    if not p then p = YR.ParseStep(edit.steps[i]) edit.parsed[i] = p end
    return p
end

-- The selected step was changed in the inspector: write it back to text.
local function Commit()
    if not edit.sel then return end
    edit.steps[edit.sel] = YR.WriteStep(Parsed(edit.sel))
    edit.dirty = true
end

local function Open(key)
    edit.key = key
    edit.header, edit.steps = YR.SplitSteps(YR:GuideText(key))
    edit.parsed, edit.dirty, edit.line = {}, false, nil
    edit.sel = #edit.steps > 0 and 1 or nil
end

local function Reparse() edit.parsed = {} end

local function Visible()
    local out = {}
    local f = edit.filter:lower()
    for i = 1, #edit.steps do
        if f == "" or edit.steps[i]:lower():find(f, 1, true) then out[#out + 1] = i end
    end
    return out
end

local function Insert(at, text)
    table.insert(edit.steps, at, text)
    Reparse()
    edit.sel, edit.line, edit.dirty = at, nil, true
end

function YR:InsertStep(text)
    if not edit.steps then return end
    Insert((edit.sel or #edit.steps) + 1, text)
    YR:RefreshWindow()
end

local function Move(from, to)
    if not (from and to) or from == to or to < 1 or to > #edit.steps then return end
    local s = table.remove(edit.steps, from)
    table.insert(edit.steps, to, s)
    Reparse()
    edit.sel, edit.dirty = to, true
    YR:RefreshWindow()
end

local function Template(kind)
    for _, t in ipairs(YR.StepTemplates()) do
        if t[1] == kind then return YR.WriteStep(t[3]) end
    end
end

-- ---------------------------------------------------------------------------
-- A scrolling list of fixed rows. build(row) makes a row's parts once; fill(row, index) fills it.
-- ---------------------------------------------------------------------------
local function List(parent, width, count, rowH, fill, total, build)
    local l = CreateFrame("Frame", nil, parent)
    l:SetSize(width, rowH * count)
    l.rows, l.offset = {}, 0
    for i = 1, count do
        local r = CreateFrame("Button", nil, l)
        r:SetSize(width - 8, rowH)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
        r.bg = S.Fill(r, { 0, 0, 0, 0 })
        r.bar = r:CreateTexture(nil, "ARTWORK")
        r.bar:SetPoint("TOPLEFT") r.bar:SetPoint("BOTTOMLEFT") r.bar:SetWidth(2)
        S.Set(r.bar, S.C.accent)
        r.bar:Hide()
        r:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(unpack(S.C.hover)) end end)
        r:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end end)
        function r:Select(on)
            self.selected = on
            if on then self.bg:SetColorTexture(unpack(S.C.accentD))
            elseif self:IsMouseOver() then self.bg:SetColorTexture(unpack(S.C.hover))      -- drawn again under the mouse: still lit
            else self.bg:SetColorTexture(0, 0, 0, 0) end
            self.bar:SetShown(on)
            self:Tools(on or self:IsMouseOver())
        end
        -- buttons made with r:Tool() show only while the row is hovered or selected
        r.tools = {}
        function r:Tools(on) for _, t in ipairs(self.tools) do t:SetShown(on) end end
        function r:Tool(icon, onClick, tip, color)
            local t = S.IconButton(self, icon, onClick, tip, color, 20)
            t:HookScript("OnLeave", function() if not self.selected and not self:IsMouseOver() then self:Tools(false) end end)
            t:Hide()
            self.tools[#self.tools + 1] = t
            return t
        end
        r:HookScript("OnEnter", function(self) self:Tools(true) end)
        r:HookScript("OnLeave", function(self) if not self.selected and not self:IsMouseOver() then self:Tools(false) end end)
        build(r)
        l.rows[i] = r
    end
    l.scroll = l:CreateTexture(nil, "OVERLAY")
    l.scroll:SetColorTexture(1, 1, 1, 0.16)
    l.scroll:SetWidth(3)
    function l:Refresh()
        local n = total()
        self.offset = math.max(0, math.min(self.offset, n - count))
        for i, r in ipairs(self.rows) do
            local index = self.offset + i
            if index <= n then r:Show() fill(r, index) else r:Hide() end
        end
        local h = rowH * count
        if n > count then
            self.scroll:Show()
            self.scroll:SetHeight(math.max(20, h * count / n))
            self.scroll:ClearAllPoints()
            self.scroll:SetPoint("TOPRIGHT", 0, -(h - self.scroll:GetHeight()) * self.offset / (n - count))
        else
            self.scroll:Hide()
        end
    end
    function l:ShowIndex(index)
        if index and (index <= self.offset or index > self.offset + count) then
            self.offset = math.max(0, index - math.floor(count / 2))
        end
    end
    l:EnableMouseWheel(true)
    l:SetScript("OnMouseWheel", function(self, delta) self.offset = self.offset - delta * 3 self:Refresh() end)
    return l
end

-- ---------------------------------------------------------------------------
-- Routes: the step list, and the buttons under it
-- ---------------------------------------------------------------------------
local function DeleteStep(i)
    if not (i and edit.steps[i]) then return end
    table.remove(edit.steps, i)
    Reparse()
    if edit.sel and edit.sel >= i then edit.sel = edit.sel > 1 and edit.sel - 1 or (#edit.steps > 0 and 1 or nil) end
    edit.dirty, edit.line = true, nil
    YR:RefreshWindow()
end

local function QuestMenu(anchor, onPick)
    local list = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local done = C_QuestLog.IsComplete(info.questID)
            list[#list + 1] = { info.questID, (done and "|cff66dd88Done|r  " or "") .. info.title }
        end
    end
    if #list == 0 then list[1] = { 0, "Your quest log is empty", S.C.muted } end
    S.OpenMenu(anchor, list, function(q) if q ~= 0 then onPick(q) end end, 280)
end

local function BuildStepList(page)
    local search = S.Input(page, { width = 260, placeholder = "Search steps", onChange = function(t)
        edit.filter = t
        ui.steps.offset = 0
        YR:RefreshWindow()
    end })
    search:SetPoint("TOPLEFT", 16, -14)
    ui.count = S.Text(page, 12, S.C.muted)
    ui.count:SetPoint("LEFT", search, "RIGHT", 12, 0)

    local rows = math.floor((PH - 48 - 106 - 60) / ROW)
    local visible = {}
    local dragFrom
    local marker = page:CreateTexture(nil, "OVERLAY")
    marker:SetSize(LIST_W - 8, 2)
    S.Set(marker, S.C.accent)
    marker:Hide()

    ui.steps = List(page, LIST_W, rows, ROW, function(r, i)
        local index = visible[i]
        r.index = index
        local info = YR.StepInfo(Parsed(index))
        r.num:SetText(index)
        r.icon:SetTexture(info.icon)
        r.label:SetText(info.text)
        r.cls:SetText(info.classes or "")
        -- the text runs to the edge unless there are classes to show there
        r.label:ClearAllPoints()
        r.label:SetPoint("LEFT", 68, 0)
        r.label:SetPoint("RIGHT", info.classes and -104 or -30, 0)
        r:Select(edit.sel == index)
    end, function() visible = Visible() return #visible end, function(r)
        local grip = r:Tool("grip", nil, "Drag to move")
        grip:SetPoint("LEFT", 0, 0)
        grip:EnableMouse(false)
        r.num = S.Text(r, 11, S.C.muted)
        r.num:SetPoint("LEFT", 16, 0)
        r.num:SetWidth(24)
        r.num:SetJustifyH("RIGHT")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", 46, 0)
        r.label = S.Text(r, 13)
        r.cls = S.Text(r, 11, { 0.55, 0.62, 0.72, 1 })
        r.cls:SetPoint("RIGHT", -28, 0)
        local del = r:Tool("close", function() DeleteStep(r.index) end, "Delete this step (Undo changes brings it back)", S.C.danger)
        del:SetPoint("RIGHT", -3, 0)
        r.cls:SetWidth(72)
        r.cls:SetJustifyH("RIGHT")
        r:RegisterForDrag("LeftButton")
        r:SetScript("OnClick", function(self) edit.sel, edit.line = self.index, nil YR:RefreshWindow() end)
        r:SetScript("OnDragStart", function(self)
            dragFrom = self.index
            page:SetScript("OnUpdate", function()
                for _, o in ipairs(ui.steps.rows) do
                    if o:IsShown() and o:IsMouseOver() then
                        marker:ClearAllPoints()
                        marker:SetPoint("BOTTOMLEFT", o, "TOPLEFT", 0, 0)
                        marker:Show()
                        return
                    end
                end
            end)
        end)
        r:SetScript("OnDragStop", function()
            page:SetScript("OnUpdate", nil)
            marker:Hide()
            for _, o in ipairs(ui.steps.rows) do
                if o:IsShown() and o:IsMouseOver() then Move(dragFrom, o.index) break end
            end
            dragFrom = nil
        end)
    end)
    ui.steps:SetPoint("TOPLEFT", 16, -48)
    local frame = CreateFrame("Frame", nil, page)
    frame:SetPoint("TOPLEFT", ui.steps, -1, 1)
    frame:SetPoint("BOTTOMRIGHT", ui.steps, 1, -1)
    S.Fill(frame, S.C.field)
    frame:SetFrameLevel(math.max(0, ui.steps:GetFrameLevel() - 1))
    S.Border(frame)

    local function AfterSel() return (edit.sel or #edit.steps) + 1 end
    local buttons = {
        { "New step", function(self)
            local list = {}
            for _, t in ipairs(YR.StepTemplates()) do list[#list + 1] = { t[1], t[2] } end
            S.OpenMenu(self, list, function(v)
                Insert(AfterSel(), Template(v))
                ui.steps:ShowIndex(edit.sel)
                YR:RefreshWindow()
            end, 200)
        end, "A new step after the selected one, filled in with where you stand and what you target" },
        { "Quick add quest", function(self)
            QuestMenu(self, function(q)
                local map, x, y = YR.Position()
                local done = C_QuestLog.IsComplete(q)
                local title = C_QuestLog.GetTitleForQuestID(q) or ("quest " .. q)
                local ok, npc = pcall(UnitName, "target")
                local step = { head = "", lines = {} }
                if map then step.lines[1] = { k = "cmd", cmd = "goto", args = ("%d,%.2f,%.2f"):format(map, x, y) } end
                step.lines[#step.lines + 1] = { k = "cmd", cmd = done and "turnin" or "accept", args = tostring(q),
                    text = (done and "Turn in " or "Accept ") .. title }
                if ok and npc then step.lines[#step.lines + 1] = { k = "cmd", cmd = "target", args = npc } end
                Insert(AfterSel(), YR.WriteStep(step))
                YR:RefreshWindow()
            end)
        end, "A step for a quest in your log, here: accept it, or turn it in if it's done" },
        { "Delete step", function() DeleteStep(edit.sel) end, "Delete the selected step (Undo changes brings it back)" },
        { "Move up", function() if edit.sel then Move(edit.sel, edit.sel - 1) end end },
        { "Move down", function() if edit.sel then Move(edit.sel, edit.sel + 1) end end },
        { "Merge up", function()
            if not edit.sel or edit.sel < 2 then return end
            local into, from = Parsed(edit.sel - 1), Parsed(edit.sel)
            for _, l in ipairs(from.lines) do into.lines[#into.lines + 1] = l end
            edit.steps[edit.sel - 1] = YR.WriteStep(into)
            table.remove(edit.steps, edit.sel)
            Reparse()
            edit.sel, edit.dirty = edit.sel - 1, true
            YR:RefreshWindow()
        end, "Put this step's lines into the step above it" },
        { "Duplicate", function() if edit.sel then Insert(edit.sel + 1, edit.steps[edit.sel]) YR:RefreshWindow() end end },
        { "Farm XP here", function() Insert(AfterSel(), Template("xp")) YR:RefreshWindow() end,
          "A step: grind here until the next level. Change the level on the right" },
        { "Farm gold here", function() Insert(AfterSel(), Template("gold")) YR:RefreshWindow() end,
          "A step: farm here until you have an amount of money. Change it on the right" },
    }
    local bw = (LIST_W - 12) / 3
    for i, b in ipairs(buttons) do
        local btn = S.Button(page, b[1], b[2], nil, bw)
        btn.tip = b[3]
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        btn:SetPoint("TOPLEFT", ui.steps, "BOTTOMLEFT", col * (bw + 6), -10 - row * 32)
    end
end

-- ---------------------------------------------------------------------------
-- Routes: the inspector - the selected step, line by line
-- ---------------------------------------------------------------------------
local LINE_ICON = { ["goto"] = YR.STEP_ICON.travel, accept = YR.STEP_ICON.accept, turnin = YR.STEP_ICON.turnin,
    complete = YR.STEP_ICON.kill, mob = YR.STEP_ICON.kill, xp = YR.STEP_ICON.xp, money = YR.STEP_ICON.gold,
    train = YR.STEP_ICON.train, collect = YR.STEP_ICON.buy, hs = YR.STEP_ICON.hearth, home = YR.STEP_ICON.hearth,
    deathskip = YR.STEP_ICON.death }
local DIM = "|cff8899aa"

local function LineLabel(l)
    if l.k == "tag" then return DIM .. "#" .. l.tag .. (l.val and (" " .. l.val) or "") .. "|r" end
    if l.k == "say" then return (l.pre == "+" and DIM .. "Reminder|r  " or DIM .. "Text|r  ") .. YR.Plain(l.text) end
    if l.k == "raw" then return DIM .. (l.raw or "") .. "|r" end
    local c = YR.COMMAND_BY_NAME[l.cmd]
    local what = c and c.label or ("." .. l.cmd)
    local args = (l.args or "") ~= "" and ("  " .. DIM .. l.args .. "|r") or ""
    if l.cmd == "goto" then args = "  " .. DIM .. (YR.PlaceText(YR.Args(l)) or l.args) .. "|r" end
    return what .. args .. (l.text and ("  " .. YR.Plain(l.text)) or "")
end

local function AddChoices()
    local list = {}
    for _, c in ipairs(YR.COMMANDS) do list[#list + 1] = { "cmd:" .. c.cmd, c.label } end
    list[#list + 1] = { "say:>>", "Instruction text" }
    list[#list + 1] = { "say:+", "Reminder text" }
    for _, t in ipairs(YR.TAGS) do list[#list + 1] = { "tag:" .. t.tag, t.label, S.C.sub } end
    return list
end

local function NewLine(choice)
    local kind, what = choice:match("^(%a+):(.*)$")
    if kind == "say" then return { k = "say", pre = what, text = "" } end
    if kind == "tag" then return { k = "tag", tag = what, val = (what == "completewith") and "next" or nil } end
    local l = { k = "cmd", cmd = what, args = "" }
    local map, x, y = YR.Position()
    local ok, target = pcall(UnitName, "target")
    if what == "goto" and map then l.args = ("%d,%.2f,%.2f"):format(map, x, y) end
    if (what == "target" or what == "mob") and ok and target then l.args = target end
    if what == "xp" then l.args = tostring(UnitLevel("player") + 1) l.text = "Grind to level " .. l.args end
    if what == "money" then l.args = ">0.10" l.text = "Farm until you have 10s" end
    return l
end

local function SelLine()
    return edit.sel and edit.line and Parsed(edit.sel).lines[edit.line]
end

local function BuildInspector(page)
    local X = 16 + LIST_W + 16
    local CW = PW - X - 16
    local card = CreateFrame("Frame", nil, page)
    card:SetPoint("TOPLEFT", X, -14)
    card:SetPoint("BOTTOMRIGHT", -16, 58)
    S.Fill(card, S.C.card)
    S.Border(card)
    ui.card = card
    local body = CreateFrame("Frame", nil, card)
    body:SetAllPoints()
    ui.body = body

    ui.stepIcon = body:CreateTexture(nil, "ARTWORK")
    ui.stepIcon:SetSize(22, 22)
    ui.stepIcon:SetPoint("TOPLEFT", 14, -12)
    ui.stepTitle = S.Text(body, 18)
    ui.stepTitle:SetPoint("LEFT", ui.stepIcon, "RIGHT", 8, 0)
    ui.where = S.Text(body, 12, S.C.sub)
    ui.where:SetPoint("TOPLEFT", 14, -40)
    ui.empty = S.Text(card, 13, S.C.muted)
    ui.empty:SetPoint("CENTER")
    ui.empty:SetText("Pick a step on the left, or make one with New step.")

    -- who sees it
    local shows = S.Text(body, 12, S.C.muted)
    shows:SetPoint("TOPLEFT", 14, -68)
    shows:SetText("Shows for")
    ui.chips = {}
    local cx = 76
    ui.everyone = S.Chip(body, "Everyone", function()
        Parsed(edit.sel).head = ""
        Commit() YR:RefreshWindow()
    end)
    ui.everyone:SetPoint("TOPLEFT", cx, -64)
    cx = cx + ui.everyone:GetWidth() + 4
    for _, class in ipairs(CLASSES) do
        local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        local chip = S.Chip(body, "", function()
            local p = Parsed(edit.sel)
            local list, found = {}, nil
            for token in ((p.head:match("<<%s*(.+)$") or "") .. "/"):gmatch("([^/%s]+)[/%s]*") do list[#list + 1] = token end
            for i, t in ipairs(list) do if t == CLASS_NAME[class] then found = i end end
            if found then table.remove(list, found) else list[#list + 1] = CLASS_NAME[class] end
            p.head = #list > 0 and ("<< " .. table.concat(list, "/")) or ""
            Commit() YR:RefreshWindow()
        end, CLASS_TEX, coords)
        chip:SetWidth(23)
        chip:SetPoint("TOPLEFT", cx, -64)
        chip:SetScript("OnEnter", function(self) S.Tip(self, CLASS_NAME[class] .. " (click to add or remove)") end)
        chip:SetScript("OnLeave", function() GameTooltip:Hide() end)
        chip.class = class
        ui.chips[#ui.chips + 1] = chip
        cx = cx + 26
    end
    ui.head = S.Input(body, { width = CW - 28, placeholder = "Or type who sees it, e.g. << Dwarf Paladin  or  << !Warrior", onCommit = function(t)
        if not edit.sel then return end
        local head = t:gsub("^%s*step%s*", "")
        if head ~= "" and not head:find("^<<") then head = "<< " .. head end
        Parsed(edit.sel).head = head
        Commit() YR:RefreshWindow()
    end })
    ui.head:SetPoint("TOPLEFT", 14, -94)

    -- step switches
    local function TagSwitch(label, tag, x, width)
        local t = S.Toggle(body, label, function() return edit.sel and YR.HasTag(Parsed(edit.sel), tag) ~= nil end,
            function(on) YR.SetTag(Parsed(edit.sel), tag, on, tag == "completewith" and "next" or nil) Commit() YR:RefreshWindow() end)
        t:SetPoint("TOPLEFT", x, -128)
        t:SetWidth(width)
        return t
    end
    ui.optional = TagSwitch("Optional", "optional", 14, 118)
    ui.sticky = TagSwitch("Sticky", "sticky", 136, 100)
    ui.together = TagSwitch("Ends with the next step", "completewith", 240, 220)

    -- the step's lines
    local actions = S.Text(body, 12, S.C.accent)
    actions:SetPoint("TOPLEFT", 14, -162)
    actions:SetText("ACTIONS")
    ui.lines = List(body, CW - 28, 6, 24, function(r, i)
        local l = Parsed(edit.sel).lines[i]
        r.i = i
        r.icon:SetTexture(l.k == "cmd" and LINE_ICON[l.cmd] or (l.k == "say" and YR.STEP_ICON.note) or nil)
        r.label:SetText(LineLabel(l))
        r:Select(edit.line == i)
    end, function() return edit.sel and #Parsed(edit.sel).lines or 0 end, function(r)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(14, 14)
        r.icon:SetPoint("LEFT", 8, 0)
        r.label = S.Text(r, 13)
        r.label:SetPoint("LEFT", 28, 0)
        r.label:SetPoint("RIGHT", -72, 0)
        r:SetScript("OnClick", function(self) edit.line = self.i YR:RefreshWindow() end)
        local function Swap(d)
            local lines = Parsed(edit.sel).lines
            local a, b = r.i, r.i + d
            if b < 1 or b > #lines then return end
            lines[a], lines[b] = lines[b], lines[a]
            edit.line = b
            Commit() YR:RefreshWindow()
        end
        local up = r:Tool("up", function() Swap(-1) end, "Move up")
        up:SetPoint("RIGHT", -46, 0)
        local down = r:Tool("down", function() Swap(1) end, "Move down")
        down:SetPoint("RIGHT", -24, 0)
        local x = r:Tool("close", function()
            table.remove(Parsed(edit.sel).lines, r.i)
            edit.line = nil
            Commit() YR:RefreshWindow()
        end, "Remove this action", S.C.danger)
        x:SetPoint("RIGHT", -2, 0)
    end)
    ui.lines:SetPoint("TOPLEFT", 14, -180)
    local lf = CreateFrame("Frame", nil, body)
    lf:SetPoint("TOPLEFT", ui.lines, -1, 1)
    lf:SetPoint("BOTTOMRIGHT", ui.lines, 1, -1)
    S.Border(lf)

    -- the selected action, field by field
    local ed = CreateFrame("Frame", nil, body)
    ed:SetPoint("TOPLEFT", ui.lines, "BOTTOMLEFT", 0, -12)
    ed:SetSize(CW - 28, 150)
    S.Fill(ed, S.C.field)
    S.Border(ed)
    ui.lineEd = ed
    ed.what = S.Text(ed, 13, S.C.sub)
    ed.what:SetPoint("TOPLEFT", 10, -11)
    ed.cmd = S.Dropdown(ed, 200, function()
        local list = {}
        for _, c in ipairs(YR.COMMANDS) do list[#list + 1] = { c.cmd, c.label } end
        return list
    end, function(cmd)
        local l = SelLine()
        if l and l.k == "cmd" then l.cmd = cmd Commit() YR:RefreshWindow() end
    end)
    ed.cmd:SetPoint("TOPRIGHT", -10, -6)
    ed.fields = {}
    for i = 1, 4 do
        local label = S.Text(ed, 11, S.C.muted)
        local input = S.Input(ed, { width = 90, onCommit = function(t)
            local l = SelLine()
            if not l then return end
            if l.k == "cmd" then
                if ed.single then l.args = t else YR.SetArg(l, i, t) end
            elseif l.k == "tag" then
                l.val = t ~= "" and t or nil
            end
            Commit() YR:RefreshWindow()
        end })
        ed.fields[i] = { label = label, input = input }
    end
    ed.textLabel = S.Text(ed, 11, S.C.muted)
    ed.textLabel:SetPoint("BOTTOMLEFT", 10, 58)
    ed.text = S.TextArea(ed, CW - 48, 44, { placeholder = "What the guide says for this action", onCommit = function(t)
        local l = SelLine()
        if not l then return end
        if l.k == "say" then l.text = t elseif l.k == "cmd" then l.text = t ~= "" and t or nil end
        Commit() YR:RefreshWindow()
    end })
    ed.text:SetPoint("BOTTOMLEFT", 10, 10)
    ed.here = S.Button(ed, "Here", function()
        local l = SelLine()
        local map, x, y = YR.Position()
        if l and map then
            local rest = YR.Args(l)
            l.args = ("%d,%.2f,%.2f"):format(map, x, y) .. (rest[4] and ("," .. table.concat(rest, ",", 4)) or "")
            Commit() YR:RefreshWindow()
        end
    end, nil, 60)
    ed.here.tip = "Put this point exactly where you are standing"
    ed.target = S.Button(ed, "My target", function()
        local l = SelLine()
        local ok, name = pcall(UnitName, "target")
        if l and ok and name then l.args = name Commit() YR:RefreshWindow() end
    end, nil, 84)
    ed.target.tip = "Use the name of what you have targeted"
    ed.quest = S.Button(ed, "From my log", function(self)
        QuestMenu(self, function(q)
            local l = SelLine()
            if not l then return end
            YR.SetArg(l, 1, tostring(q))
            local title = C_QuestLog.GetTitleForQuestID(q)
            if title and l.cmd ~= "complete" then l.text = (l.cmd == "turnin" and "Turn in " or "Accept ") .. title end
            Commit() YR:RefreshWindow()
        end)
    end, nil, 96)
    ed.quest.tip = "Pick the quest from your quest log"

    -- add an action
    ui.add = S.Dropdown(body, 200, AddChoices, function(choice)
        if not edit.sel then return end
        local lines = Parsed(edit.sel).lines
        local at = (edit.line or #lines) + 1
        table.insert(lines, at, NewLine(choice))
        edit.line = at
        Commit() YR:RefreshWindow()
    end)
    ui.add:SetValue("+  Add action")
    ui.add.label:SetTextColor(unpack(S.C.accent))
    ui.add:SetPoint("TOPLEFT", ed, "BOTTOMLEFT", 0, -12)
    local addNote = S.Text(body, 11, S.C.muted)
    -- kept inside the card: it wraps onto a second line rather than running past the edge
    addNote:SetPoint("LEFT", ui.add, "RIGHT", 10, 0)
    addNote:SetPoint("RIGHT", body, "RIGHT", -14, 0)
    addNote:SetWordWrap(true)
    addNote:SetText("New places are where you stand; kill and talk use your target.")

    ui.raw = S.Button(body, "Edit as text", function() YR:EditRawStep() end, "ghost", 100)
    ui.raw:SetPoint("BOTTOMRIGHT", -10, 10)
    ui.raw.tip = "The whole step as RestedXP text, for anything the fields don't cover"
    ui.raw:SetTextColour(S.C.accent)
end

-- The step as RestedXP text in a box over the inspector; Apply puts it back.
function YR:EditRawStep()
    if not edit.sel then return end
    if not ui.rawFrame then
        local f = CreateFrame("Frame", nil, ui.card)
        f:SetAllPoints()
        f:SetFrameLevel(ui.card:GetFrameLevel() + 30)
        f:EnableMouse(true)
        S.Fill(f, S.C.card)
        S.Border(f, S.C.accent)
        local t = S.Text(f, 15)
        t:SetPoint("TOPLEFT", 14, -12)
        t:SetText("Step as RestedXP text")
        local w, h = ui.card:GetWidth() - 28, ui.card:GetHeight() - 96
        local area = S.ScrollArea(f, w, h)
        area:SetPoint("TOPLEFT", 14, -40)
        S.Fill(area, S.C.field)
        local box = CreateFrame("EditBox", nil, area)
        box:SetMultiLine(true)
        box:SetAutoFocus(false)
        box:SetFont(S.FONT, 13, "")
        box:SetTextColor(unpack(S.C.text))
        box:SetWidth(w - 12)
        box:SetTextInsets(8, 8, 8, 8)
        box:SetScript("OnEscapePressed", box.ClearFocus)
        area:SetScrollChild(box)
        area:SetScript("OnMouseDown", function() box:SetFocus() end)
        local apply = S.Button(f, "Apply", function()
            edit.steps[edit.sel] = (box:GetText():gsub("%s+$", ""))
            edit.parsed[edit.sel], edit.line, edit.dirty = nil, nil, true
            f:Hide() YR:RefreshWindow()
        end, "primary", 90)
        apply:SetPoint("BOTTOMLEFT", 14, 12)
        local cancel = S.Button(f, "Cancel", function() f:Hide() end, nil, 90)
        cancel:SetPoint("LEFT", apply, "RIGHT", 8, 0)
        ui.rawBox, ui.rawFrame = box, f
    end
    ui.rawBox:SetText(edit.steps[edit.sel])
    ui.rawFrame:Show()
    ui.rawBox:SetFocus()
end

local function RefreshInspector()
    local has = edit.sel ~= nil and edit.steps[edit.sel] ~= nil
    ui.body:SetShown(has)
    ui.empty:SetShown(not has)
    if ui.rawFrame and not has then ui.rawFrame:Hide() end
    if not has then return end
    local p = Parsed(edit.sel)
    local info = YR.StepInfo(p)
    ui.stepIcon:SetTexture(info.icon)
    ui.stepTitle:SetText(("Step %d"):format(edit.sel))
    ui.where:SetText(info.where and ("Location  " .. (YR.PlaceText(info.where) or "?")) or "No location")
    local head = p.head:match("<<%s*(.+)$") or ""
    ui.everyone:SetOn(head == "")
    for _, chip in ipairs(ui.chips) do
        local on = false
        for token in (head .. "/"):gmatch("([^/%s]+)[/%s]*") do if token == CLASS_NAME[chip.class] then on = true end end
        chip:SetOn(on)
    end
    if not ui.head:HasFocus() then ui.head:SetValue(p.head) end
    ui.optional:Refresh() ui.sticky:Refresh() ui.together:Refresh()
    if edit.line and not p.lines[edit.line] then edit.line = nil end
    ui.lines:ShowIndex(edit.line)
    ui.lines:Refresh()

    local ed, l = ui.lineEd, SelLine()
    for _, f in ipairs(ed.fields) do f.label:Hide() f.input:Hide() end
    ed.cmd:Hide() ed.here:Hide() ed.target:Hide() ed.quest:Hide()
    ed.text:Show() ed.textLabel:Show()
    ed.textLabel:SetText("Guide text")
    if not l then
        ed.what:SetText("Click an action above to change it, or add one below.")
        ed.text:Hide() ed.textLabel:Hide()
        return
    end
    -- the text area takes whatever room is left under the fields, down to the bottom of the box
    local function TextFrom(top)
        ed.textLabel:ClearAllPoints()
        ed.textLabel:SetPoint("TOPLEFT", 10, top)
        ed.text:ClearAllPoints()
        ed.text:SetPoint("TOPLEFT", 10, top - 14)
        ed.text:SetPoint("BOTTOMRIGHT", -10, 10)
    end
    local function Field(i, name, x, w, value)
        local f = ed.fields[i]
        f.label:Show() f.input:Show()
        f.label:SetText(name)
        f.label:ClearAllPoints() f.label:SetPoint("TOPLEFT", x, -38)
        f.input:SetWidth(w)
        f.input:ClearAllPoints() f.input:SetPoint("TOPLEFT", x, -52)
        if not f.input:HasFocus() then f.input:SetValue(value) end
    end
    if l.k == "cmd" then
        local c = YR.COMMAND_BY_NAME[l.cmd]
        ed.what:SetText("Action")
        ed.cmd:Show()
        ed.cmd:SetValue(c and c.label or ("." .. l.cmd))
        local names = c and c.fields or { "Arguments" }
        ed.single = not c
        local args = YR.Args(l)
        local x, w = 10, (l.cmd == "goto") and 70 or (#names <= 1 and 200 or 120)
        for i, name in ipairs(names) do
            Field(i, name, x, w, ed.single and (l.args or "") or args[i])
            x = x + w + 8
        end
        local extra = l.cmd == "goto" and ed.here or ((l.cmd == "target" or l.cmd == "mob") and ed.target)
            or ((l.cmd == "accept" or l.cmd == "turnin" or l.cmd == "complete") and ed.quest)
        if extra then
            extra:Show()
            extra:ClearAllPoints()
            extra:SetPoint("TOPLEFT", x, -52)
        end
        TextFrom(#names > 0 and -86 or -38)
        if not ed.text:HasFocus() then ed.text:SetValue(l.text or "") end
    elseif l.k == "say" then
        ed.what:SetText(l.pre == "+" and "Reminder text" or "Instruction text")
        ed.textLabel:SetText("Text")
        TextFrom(-38)
        if not ed.text:HasFocus() then ed.text:SetValue(l.text) end
    elseif l.k == "tag" then
        ed.what:SetText("Tag  #" .. l.tag)
        ed.text:Hide() ed.textLabel:Hide()
        ed.single = false
        Field(1, "Value", 10, 220, l.val)
    else
        ed.what:SetText("A line Headstart doesn't know: use Edit as text.")
        ed.text:Hide() ed.textLabel:Hide()
    end
end

function YR:RevertRoute(key)
    YR:RevertGuide(key)
    if edit.key == key then Open(key) end
    YR:RefreshWindow()
    StaticPopup_Show("HEADSTART_RELOAD")
end

local function BuildRoutes(page)
    BuildStepList(page)
    BuildInspector(page)
    local save = S.Button(page, "Save", function()
        if not edit.key then return end
        YR:SaveCustom(edit.key, edit.header, edit.steps)
        edit.dirty = false
        YR:RefreshWindow()
        StaticPopup_Show("HEADSTART_RELOAD")
    end, "primary", 110)
    save:SetPoint("BOTTOMLEFT", 16, 16)
    save.tip = "Keep this as your version of the route (RestedXP gets it after a reload)"
    local undo = S.Button(page, "Undo changes", function() Open(edit.key) YR:RefreshWindow() end, nil, 120)
    undo:SetPoint("LEFT", save, "RIGHT", 8, 0)
    undo.tip = "Back to your last saved version"
    local revert = S.Button(page, "Back to the shipped route", function()
        if not YR:IsCustom(edit.key) then return end
        StaticPopup_Show("HEADSTART_REVERT", YR.GuideName(edit.key), nil, edit.key)
    end, nil, 190)
    revert:SetPoint("LEFT", undo, "RIGHT", 8, 0)
    ui.state = S.Text(page, 12, S.C.muted)
    ui.state:SetPoint("LEFT", revert, "RIGHT", 16, 0)

    -- A newer Headstart shipped a different version of this route than the one the edits started
    -- from: take it with the edits kept, or keep the route as it is. Right after taking it, undo.
    local function Merged(clashes)
        Open(edit.key)
        YR:RefreshWindow()
        YR.Print(clashes and clashes > 0
            and ("update taken. In %d place(s) we changed a step you had changed too: yours was kept."):format(clashes)
            or "update taken, with all your edits kept.")
        StaticPopup_Show("HEADSTART_RELOAD")
    end
    ui.take = S.Button(page, "Take the update", function() Merged(YR:MergeUpdate(edit.key)) end, "primary", 140)
    ui.take:SetPoint("LEFT", revert, "RIGHT", 16, 0)
    ui.take.tip = "This version of Headstart ships a newer route. Take it, with your own edits applied on top"
    ui.keep = S.Button(page, "Keep mine", function()
        YR:KeepMine(edit.key)
        YR:RefreshWindow()
    end, "ghost", 96)
    ui.keep:SetPoint("LEFT", ui.take, "RIGHT", 6, 0)
    ui.keep.tip = "Stay on your route as it is and stop offering this update"
    ui.undoMerge = S.Button(page, "Undo the update", function()
        YR:UndoMerge(edit.key)
        Open(edit.key)
        YR:RefreshWindow()
        StaticPopup_Show("HEADSTART_RELOAD")
    end, nil, 140)
    ui.undoMerge:SetPoint("LEFT", revert, "RIGHT", 16, 0)
    ui.undoMerge.tip = "Back to your route as it was before you took the update"
    local export = S.Button(page, "Export", function() YR:ToggleWindow("share") YR:ExportOpen() end, nil, 90)
    export:SetPoint("BOTTOMRIGHT", -16, 16)
    export.tip = "This route as text, to send to someone"
end

local function RefreshRoutes()
    if not edit.key then return end
    win.subtitle:SetText(YR.GuideName(edit.key))
    ui.count:SetText(("%d steps"):format(#edit.steps))
    local update = YR:HasUpdate(edit.key)
    local undoable = not update and YR:CanUndoMerge(edit.key)
    ui.take:SetShown(update)
    ui.keep:SetShown(update)
    ui.take:SetEnabled(not edit.dirty)
    ui.take.tip = edit.dirty and "Save or undo your changes first"
        or "This version of Headstart ships a newer route. Take it, with your own edits applied on top"
    ui.undoMerge:SetShown(undoable and not edit.dirty)
    ui.state:SetShown(not update and not (undoable and not edit.dirty))
    ui.state:SetText(edit.dirty and "|cffffd24aUnsaved changes|r" or (YR:IsCustom(edit.key) and "Your version" or "As shipped"))
    ui.steps:ShowIndex(edit.sel)
    ui.steps:Refresh()
    for _, t in ipairs(ui.routeTabs) do t:Mark() end
    RefreshInspector()
end

-- ---------------------------------------------------------------------------
-- This run
-- ---------------------------------------------------------------------------
local run = {}
local ACTION_ICON = { accept = YR.STEP_ICON.accept, turnin = YR.STEP_ICON.turnin, complete = YR.STEP_ICON.kill,
    buy = YR.STEP_ICON.buy, learn = YR.STEP_ICON.train, hearth = YR.STEP_ICON.hearth, death = YR.STEP_ICON.death,
    level = YR.STEP_ICON.xp }

-- The details of one logged action, for the panel beside the list: for a quest its whole story
-- (taken, done, handed in: when, where, from whom, what it gave), else what the log knows.
local DETAIL_W = 330
local KIND_NAME = { accept = "Took a quest", complete = "Finished a quest's objectives", turnin = "Handed in a quest",
    level = "Level up", death = "Died", buy = "Bought", learn = "Learned", hearth = "Hearthstone", sell = "Sold",
    loot = "Looted" }

local function Where(e)
    local map = e[6]
    local info = map and map ~= 0 and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    if not map or map == 0 then return "-" end
    return ("%s  %.1f, %.1f"):format(info and info.name or ("map " .. map), e[7] or 0, e[8] or 0)
end

-- 1234 copper as "12s 34c"
local function Coins(c)
    local g, sv, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    return ((g > 0 and g .. "g " or "") .. ((g > 0 or sv > 0) and sv .. "s " or "") .. cu .. "c")
end

local function Since(r, t)
    local start = r and r.started
    if not start then return "" end
    local d = t - start
    return ("  (%d:%02d into the run)"):format(math.floor(d / 60), d % 60)
end

local function Details(a)
    local e = a.e
    local r = YippRouteDB.runs and YippRouteDB.runs[YR.CharKey()]
    local GREY, WHITE, GOLD = "|cff8a8f99", "|cffeef0f5", "|cffffcc4d"
    local lines = {}
    local function Line(label, value) lines[#lines + 1] = GREY .. label .. "|r  " .. WHITE .. value .. "|r" end
    local link, linkWhat
    local q = e[3]
    if (e[2] == "accept" or e[2] == "complete" or e[2] == "turnin") and q and q ~= 0 then
        local acc, done, tin
        for _, x in ipairs(r and r.ev or {}) do
            if x[3] == q then
                if x[2] == "accept" then acc = x elseif x[2] == "complete" then done = done or x
                elseif x[2] == "turnin" then tin = x end
            end
        end
        local title = (acc and acc.title) or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q)) or "Quest"
        lines[1] = GOLD .. title .. "|r"
        Line("Quest ID", tostring(q))
        if acc then
            Line("Taken", date("%H:%M:%S", acc[1]) .. Since(r, acc[1]) .. " at level " .. acc[4])
            if acc.npc then Line("From", acc.npc) end
            Line("Where", Where(acc))
            if acc.obj then Line("Objectives", tostring(acc.obj)) end
        end
        if done then
            Line("Done", date("%H:%M:%S", done[1]) .. (acc and ("  (%d:%02d after taking it)"):format(
                math.floor((done[1] - acc[1]) / 60), (done[1] - acc[1]) % 60) or ""))
            Line("Where", Where(done))
        end
        if tin then
            Line("Handed in", date("%H:%M:%S", tin[1]) .. Since(r, tin[1]))
            if tin.npc then Line("To", tin.npc) end
            Line("Reward", ("%d XP%s"):format(tin.xp or 0, (tin.money or 0) > 0 and ("  " .. Coins(tin.money)) or ""))
        elseif not done then
            Line("Status", "not handed in yet")
        end
        link, linkWhat = "https://www.wowhead.com/forever/quest=" .. q, "quest"
    else
        lines[1] = GOLD .. a.label .. "|r"
        Line("What", KIND_NAME[e[2]] or e[2])
        Line("When", date("%H:%M:%S", e[1]) .. Since(r, e[1]))
        Line("Level", tostring(e[4]))
        Line("Where", Where(e))
        if e.npc then Line("NPC", e.npc) end
        if e.count then Line("Count", tostring(e.count)) end
        if e.to then Line("New level", tostring(e.to)) end
        if e.item then link, linkWhat = "https://www.wowhead.com/forever/item=" .. e.item, "item" end
        if e.spell then link, linkWhat = "https://www.wowhead.com/forever/spell=" .. e.spell, "spell" end
    end
    return table.concat(lines, "\n"), link, linkWhat
end

local function ShowDetails()
    local a = run.sel and run.actions and run.actions[run.sel]
    if not a then
        run.detail:SetText("|cff8a8f99Click an action to see its details.|r")
        run.link:Hide() run.linkLabel:Hide()
        return
    end
    local text, link, what = Details(a)
    run.detail:SetText(text)
    run.link:SetShown(link ~= nil)
    run.linkLabel:SetShown(link ~= nil)
    if link then
        run.linkLabel:SetText("This " .. what .. " on Wowhead (click, then Ctrl+C):")
        run.link:SetValue(link)
    end
end

local function BuildRun(page)
    local title = S.Text(page, 17)
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("What this character did")
    run.hint = S.Text(page, 12, S.C.muted)
    run.hint:SetPoint("TOPLEFT", 16, -40)
    run.list = List(page, PW - 32 - DETAIL_W - 12, math.floor((PH - 130) / 26), 26, function(r, i)
        local a = run.actions[i]
        r.action, r.index = a, i
        r:Select(run.sel == i)
        r.icon:SetTexture(ACTION_ICON[a.e[2]])
        r.label:SetText(a.label)
        r.when:SetText(date("%H:%M", a.e[1]))
    end, function() return run.actions and #run.actions or 0 end, function(r)
        r.when = S.Text(r, 11, S.C.muted)
        r.when:SetPoint("LEFT", 10, 0)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", 52, 0)
        r.label = S.Text(r, 13)
        r.label:SetPoint("LEFT", 76, 0)
        r.label:SetPoint("RIGHT", -150, 0)
        local add = S.Button(r, "+  Add to route", function() if r.action.step then YR:InsertStep(r.action.step) end end,
            "ghost", 124)
        add:SetPoint("RIGHT", -6, 0)
        add:SetHeight(22)
        add:SetTextColour(S.C.accent)
        add.tip = "Put this in the open route as a step, after the selected step"
        r:SetScript("OnClick", function(self)
            run.sel = self.index
            run.list:Refresh()
            ShowDetails()
        end)
    end)
    run.list:SetPoint("TOPLEFT", 16, -66)
    local frame = CreateFrame("Frame", nil, page)
    frame:SetPoint("TOPLEFT", run.list, -1, 1)
    frame:SetPoint("BOTTOMRIGHT", run.list, 1, -1)
    S.Border(frame)
    -- the details panel
    local panel = CreateFrame("Frame", nil, page)
    panel:SetPoint("TOPLEFT", run.list, "TOPRIGHT", 12, 1)
    panel:SetSize(DETAIL_W, run.list:GetHeight() + 2)
    S.Fill(panel, S.C.card)
    S.Border(panel)
    run.detail = S.Text(panel, 13)
    run.detail:SetPoint("TOPLEFT", 14, -14)
    run.detail:SetPoint("RIGHT", -14, 0)
    run.detail:SetWordWrap(true)
    run.detail:SetSpacing(4)
    run.detail:SetJustifyV("TOP")
    run.linkLabel = S.Text(panel, 11, S.C.muted)
    run.linkLabel:SetPoint("BOTTOMLEFT", 14, 44)
    run.link = S.Input(panel, { width = DETAIL_W - 28 })
    run.link:SetPoint("BOTTOMLEFT", 14, 14)
    run.link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    run.record = S.Toggle(page, "Record this run", function() return YR.Option("logging") end,
        function(on) YR:SetLogging(on) end)
    run.record:SetPoint("BOTTOMLEFT", 16, 20)
    -- Stop run: the splits clock and the log end here, so a run finished (or abandoned) is timed to
    -- that moment. A run with a mistake in it can be kept out of "vs best".
    run.stop = S.Button(page, "Stop this run", function()
        if YR:RunStopped() then YR:ResumeRun() else YR:StopRun() end
        YR:RefreshWindow()
    end, nil, 130)
    run.stop:SetPoint("BOTTOMRIGHT", -16, 16)
    run.counts = S.Toggle(page, "A run to beat", function() return YR:RunCounts() end,
        function(on) YR:SetRunCounts(on) end)
    run.counts:SetWidth(150)
    run.counts:SetPoint("RIGHT", run.stop, "LEFT", -20, -3)
    run.counts.tip = "Off: other characters' splits don't compare against this run (a missed quest, a test)"
    -- This character's whole run as a route of its own (MyRoutes.lua): every stop a step, to reorder and
    -- edit in Routes and to play in RestedXP. Saving again replaces it.
    run.save = S.Button(page, "Save as route", function() YR.AskSaveRunAsRoute() end, "primary", 130)
    run.save:SetPoint("RIGHT", run.counts, "LEFT", -20, 3)
    run.save.tip = "Your run as your own route: every quest stop, trainer, vendor, flight, death skip and grind"
        .. " a step, in the order you played. Edit and reorder it in Routes; RestedXP lists it under My routes."
        .. " Saving again replaces it. Our routes stay as they are"
    run.delete = S.Button(page, "Delete my route", function() YR.AskDeleteMyRoutes() end, nil, 130)
    run.delete:SetPoint("RIGHT", run.save, "LEFT", -10, 0)
    run.delete.tip = "Delete the route you saved for this race (asks first). Your run log stays, so you can save it again"
end

local function RefreshRun()
    win.subtitle:SetText("")
    -- the list is made from the whole log (a table and two texts an event): made again only when the
    -- log has another event in it, or is another log (deleted and begun again)
    local log = YippRouteDB.runs and YippRouteDB.runs[YR.CharKey()]
    local ev = log and log.ev
    if not run.actions or run.madeOf ~= ev or run.madeAt ~= (ev and #ev or 0) then
        run.madeOf, run.madeAt = ev, ev and #ev or 0
        run.actions = YR:RunActions()
    end
    run.hint:SetText(("%d actions. Click one for its details; Add to route puts it in %s, after step %s."):format(#run.actions,
        edit.key and YR.GuideName(edit.key) or "the open route", edit.sel or "-"))
    -- follow the newest actions, but don't jump away from where you were reading
    if run.seen ~= #run.actions then
        run.seen = #run.actions
        run.list.offset = math.max(0, #run.actions - #run.list.rows)
    end
    run.list:Refresh()
    ShowDetails()
    run.record:Refresh()
    local stopped = YR:RunStopped()
    run.stop:SetLabel(stopped and "Resume this run" or "Stop this run")
    run.stop.tip = stopped and "Carry on with this run: the time it was stopped doesn't count"
        or "End this run now: the splits and the log stop here"
    run.counts:Refresh()
end

-- ---------------------------------------------------------------------------
-- Share
-- ---------------------------------------------------------------------------
local share = {}

function YR:ExportOpen()
    if not (edit.key and share.box) then return end
    share.box:SetText(YR.JoinSteps(edit.header, edit.steps))
    share.box:SetFocus()
    share.box:HighlightText()
    share.hint:SetText("Selected: press Ctrl+C to copy.")
end

local function BuildShare(page)
    local title = S.Text(page, 17)
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Share a route")
    share.hint = S.Text(page, 12, S.C.muted)
    share.hint:SetPoint("TOPLEFT", 16, -40)
    share.hint:SetText("Export the open route and copy it, or paste someone's route here and import it.")
    local area = S.ScrollArea(page, PW - 32, PH - 132)
    area:SetPoint("TOPLEFT", 16, -64)
    S.Fill(area, S.C.field)
    S.Border(area)
    local box = CreateFrame("EditBox", nil, area)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFont(S.FONT, 12, "")
    box:SetTextColor(unpack(S.C.text))
    box:SetWidth(PW - 48)
    box:SetTextInsets(10, 10, 10, 10)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    area:SetScrollChild(box)
    area:SetScript("OnMouseDown", function() box:SetFocus() end)
    share.box = box
    local export = S.Button(page, "Export open route", function() YR:ExportOpen() end, "primary", 150)
    export:SetPoint("BOTTOMLEFT", 16, 16)
    local import = S.Button(page, "Import", function()
        local done, why = YR:ImportGuide(box:GetText())
        share.hint:SetText(done and ("|cff66dd88Imported:|r " .. done .. ". Reload to use it.") or ("|cffff7070Not imported:|r " .. why))
        if done then
            if edit.key then Open(edit.key) end
            StaticPopup_Show("HEADSTART_RELOAD")
        end
    end, nil, 100)
    import:SetPoint("LEFT", export, "RIGHT", 8, 0)
    local clear = S.Button(page, "Clear", function() box:SetText("") end, "ghost", 70)
    clear:SetPoint("LEFT", import, "RIGHT", 8, 0)
end

-- ---------------------------------------------------------------------------
-- Settings: sections of two-column rows, the label on the left and its control on the right
-- ---------------------------------------------------------------------------
local settings = { controls = {} }

-- The class whose settings the Route and Character tabs show: this character's, unless picked.
local function ViewClass()
    local _, class = UnitClass("player")
    return settings.viewClass or class or "WARRIOR"
end

-- "Settings for: Paladin" - every class keeps its own quest-reward and setup choices.
local function ClassPicker(parent)
    local options = {}
    for _, class in ipairs(CLASSES) do
        local _, mine = UnitClass("player")
        options[#options + 1] = { class, CLASS_NAME[class] .. (class == mine and "  (this character)" or "") }
    end
    local d = S.Dropdown(parent, 190, options, function(class)
        settings.viewClass = class
        YR:RefreshWindow()
    end)
    function d:Refresh()
        local _, mine = UnitClass("player")
        local class = ViewClass()
        self:SetValue(CLASS_NAME[class] .. (class == mine and "  (this character)" or ""))
    end
    return d
end
local KIND_LABEL = {}
for _, k in ipairs(YR.REWARD_KINDS) do KIND_LABEL[k.key] = k.label end

-- A scrolling page of cards. Section starts a card: an icon, its title and a note in a header strip,
-- and - for a feature with one switch - that switch in the header (a master: the rows under it dim
-- while it's off). Each Row is a line in the card: the label, its control on the right, and under the
-- label the first sentence of its details, so what a setting does can be read without pointing at
-- anything; the (i) after the label still shows the whole text. Every row goes into settings.index for
-- the search box. controls collects the controls (and the masters' dimmers) for Refresh.
--   On a QoL page (fold: its key) with more than one card, a card folds to its head: click the head
--   and its rows go, click again and they are back. Folded is how a card starts, so a page opens as a
--   short list of what is on it, each with its switch; which ones you opened is remembered
--   (YippRouteDB.cardsOpen["page:Card"]). The cards under a folded one move up, the page gets as much
--   shorter, and whatever a page put under its cards (L.Tail) moves with them. The search and a
--   page's links open the card they lead to.
local ROW_H, ROW_TIP_H, CARD_HEAD = 34, 48, 40
local TOP_CARD = "On this page"       -- the card of switches every QoL page begins with
-- A slider on a settings row: the compact kind, all one width, so it shares a row with another setting.
local function RowSlider(parent, min, max, step, get, set)
    return S.Slider(parent, min, max, step, get, set, 180, true)
end

--- The first sentence of a row's details (the line under its label).
local function FirstSentence(tip)
    return tip:match("^(.-[%.!?])%s+%S") or tip
end

-- Another addon doing the same thing is said where the setting is: on the row (in front of its text),
-- or on the card (in place of its note). Which of ours meets which of theirs is Core.lua's OTHERS;
-- here, by the row's or the card's name.
local ROW_OTHER = {
    ["Bag bar"] = "blizzardBars", ["Micro menu"] = "blizzardBars", ["Button strip"] = "chatButtons",
    ["Hide the social button"] = "chatButtons", ["Social window (percent)"] = "windowScale",
    ["Group finder (percent)"] = "windowScale", ["Move the combined bag"] = "moveBag",
    ["Move the reagent bag"] = "moveBag", ["Sound"] = "whisperSound", ["Bars"] = "swing",
    ["Accept invites from"] = "acceptInvites", ["Invite on whisper"] = "whisperInvite",
    ["Durability warning"] = "durability", ["Move by dragging"] = "talentMove",
    ["Sliders on the talent window"] = "talentFadeSlider", ["Unspent talent points"] = "remindTalents",
}
local CARD_OTHER = {
    ["Flight timer"] = "flightTimer", ["Instance tracker"] = "instanceTrack", ["Restock"] = "restock",
    ["XP bar"] = "xpbar", ["Trinket buttons"] = "trinketBar", ["Swing timer"] = "swing",
}

local function RowPage(page, controls, bottom, fold)
    local area = S.ScrollArea(page, CW - 24, CH - (bottom or 64))
    area:SetPoint("TOPLEFT", 16, -4)
    local c = area.content
    c:SetWidth(CW - 40)
    local L = { c = c, colW = CW - 40, y = -6, col = 0, rowIndex = 0, area = area, lift = 0 }
    local card       -- the card rows go into now: { frame, top, rows }

    L.cards = {}        -- every card of the page, in the order it was built: { frame, top, span, items, entries, live }
    local function EndCard()
        L.col = 0                       -- the next card starts a row of its own
        if not card then return end
        card.height = card.top - L.y + 6
        card.frame:SetHeight(card.height)
        L.y = L.y - 6 - 14
        card.span = card.top - L.y      -- the room it takes, the gap under it included
        L.endY = L.y                    -- where the cards end, as built
        card = nil
    end

    --- Whether a card is folded to its head.
    local function Shut(cd)
        if not fold or cd.isTop or #L.cards < 2 then return false end
        local open = YippRouteDB.cardsOpen
        return not (open and open[fold .. ":" .. cd.title])
    end
    --- A card folded or opened (open nil: the other way), and the page laid out again.
    function L.Fold(cd, open)
        if not fold or #L.cards < 2 then return end
        local kept = YippRouteDB.cardsOpen or {}
        YippRouteDB.cardsOpen = kept
        local key = fold .. ":" .. cd.title
        if open == nil then open = not kept[key] end
        kept[key] = open and true or nil
        L.Reflow()
    end
    --- Every card of the page opened, or folded.
    function L.FoldAll(open)
        if not fold or #L.cards < 2 then return end
        local kept = YippRouteDB.cardsOpen or {}
        YippRouteDB.cardsOpen = kept
        for _, cd in ipairs(L.cards) do kept[fold .. ":" .. cd.title] = open and true or nil end
        L.Reflow()
    end
    --- Whether any card of the page is folded (nil on a page whose cards don't fold).
    function L.AnyShut()
        if not fold or #L.cards < 2 then return nil end
        for _, cd in ipairs(L.cards) do if Shut(cd) then return true end end
        return false
    end
    --- How long the page is with every card open: Reflow takes off what the folded ones save.
    function L.Length(h)
        L.length = h
        c:SetHeight(math.max(10, h - L.lift))
    end
    --- What a page puts under its cards goes on this, so it follows them up as they fold.
    function L.Tail()
        if not L.tail then
            L.tail = CreateFrame("Frame", nil, c)
            L.tail:SetPoint("TOPLEFT", 0, 0)
            L.tail:SetSize(L.colW, 10)
        end
        return L.tail
    end

    --- The cards of features that are off go under the ones that are on (the first card, the page's
    --- switches, stays first), and a folded card is only its head. Called as the page is built and
    --- whenever it is refreshed, or a card is folded or opened.
    function L.Reflow()
        local list = L.cards
        if #list < 2 then return end
        local order, off = {}, {}
        for _, cd in ipairs(list) do
            if cd.isTop or not cd.live or cd.live() then order[#order + 1] = cd else off[#off + 1] = cd end
        end
        for _, cd in ipairs(off) do order[#order + 1] = cd end
        local y = list[1].top
        for _, cd in ipairs(order) do
            local shift, shut = y - cd.top, Shut(cd)
            if shift ~= (cd.shift or 0) or shut ~= (cd.shut or false) then
                cd.shift, cd.shut = shift, shut
                cd.frame:ClearAllPoints()
                cd.frame:SetPoint("TOPLEFT", 0, cd.top + shift)
                cd.frame:SetHeight(shut and CARD_HEAD or cd.height)
                for _, it in ipairs(cd.items) do
                    it[1]:SetShown(not shut)
                    it[1]:ClearAllPoints()
                    it[1]:SetPoint("TOPLEFT", it[2], it[3] + shift)
                end
                -- where the search and the page's links scroll to (a folded card's rows: its head)
                for _, e in ipairs(cd.entries) do e.y = (shut and cd.top or e.y0) + shift end
            end
            if cd.arrow then
                cd.arrow:Show()
                cd.arrow:SetRotation(shut and -math.pi / 2 or math.pi)      -- (the art points up: turned right, or down)
            end
            y = y - (shut and (CARD_HEAD + 14) or (cd.span or 0))
        end
        -- folded cards make the page that much shorter, and what stands under the cards comes up with them
        local lift = fold and L.endY and (y - L.endY) or 0
        if lift ~= L.lift then
            L.lift = lift
            if L.length then c:SetHeight(math.max(10, L.length - lift)) end
            if L.tail then
                L.tail:ClearAllPoints()
                L.tail:SetPoint("TOPLEFT", 0, lift)
            end
            if area.UpdateScrollChildRect then area:UpdateScrollChildRect() end
            local range = area.GetVerticalScrollRange and area:GetVerticalScrollRange() or 0
            local at = area.GetVerticalScroll and area:GetVerticalScroll() or 0
            if type(range) == "number" and type(at) == "number" and at > range and area.SetVerticalScroll then
                area:SetVerticalScroll(math.max(0, range))
            end
        end
        if L.onFold then L.onFold() end       -- (the page's "Open all" says the other thing once all are open)
    end
    function L.Break() EndCard() end

    --- Start a card. opts: icon (a texture or file ID), master = { get, set } for its one switch, find =
    --- other words the search box finds it by.
    function L.Section(title, note, opts)
        EndCard()
        opts = opts or {}
        local other = settings.building and CARD_OTHER[title] and YR.OtherHas(CARD_OTHER[title])
        if other then note = "|cffffb000" .. other .. " does this too|r" end
        -- a QoL page's sections are listed under its heading, as links that scroll here (PageHead)
        if settings.building and settings.sections and not opts.top then
            local list = settings.sections[settings.building] or {}
            settings.sections[settings.building] = list
            list[#list + 1] = { title = title, y = L.y, area = area }
        end
        local section = settings.building and settings.sections and settings.sections[settings.building]
        section = section and section[#section]
        local f = CreateFrame("Frame", nil, c)
        f:SetPoint("TOPLEFT", 0, L.y)
        f:SetWidth(L.colW)
        f:SetHeight(CARD_HEAD)
        S.Fill(f, S.C.card)
        S.Border(f, S.C.line)
        local strip = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        strip:SetPoint("TOPLEFT", 1, -1)
        strip:SetPoint("TOPRIGHT", -1, -1)
        strip:SetHeight(CARD_HEAD - 1)
        S.Set(strip, ZEBRA)
        -- on a page whose cards fold: an arrow before the icon, shown once the page turns out to
        -- have more than one card (Reflow)
        local folds = fold and not opts.top
        local arrow
        if folds then
            arrow = f:CreateTexture(nil, "ARTWORK")
            arrow:SetSize(10, 10)
            arrow:SetPoint("TOPLEFT", 11, -15)
            S.ArtTexture(arrow, "up")
            arrow:SetVertexColor(unpack(S.C.sub))
            arrow:Hide()
        end
        local x = folds and 30 or 14
        if opts.icon then
            local ic = f:CreateTexture(nil, "ARTWORK")
            ic:SetSize(22, 22)
            ic:SetPoint("TOPLEFT", folds and 28 or 12, -9)
            ic:SetTexture(opts.icon)
            ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            x = folds and 64 or 48
        end
        local t = S.Text(f, 14)
        t:SetPoint("TOPLEFT", x, -12)
        t:SetText(title)
        if note then
            local n = S.Text(f, 11, S.C.muted)
            n:SetPoint("LEFT", t, "RIGHT", 10, 0)
            n:SetPoint("RIGHT", f, "TOPRIGHT", opts.master and -170 or -124, -CARD_HEAD / 2)
            n:SetJustifyH("LEFT")
            n:SetWordWrap(false)
            n:SetText(note)
        end
        if section then section.frame = f end
        if settings.index and settings.building then
            -- found by the search box too: a card's name (and its note), not only the rows under it
            f.flash = S.Fill(f, S.C.accentD, "BORDER", 6)
            f.flash:Hide()
            settings.index[#settings.index + 1] = { key = settings.building, label = title, tip = note,
                row = f, area = area, y = L.y, card = true, find = opts.find }
        end
        local rowsHere = {}
        card = { frame = f, top = L.y, rows = rowsHere, items = {}, entries = {}, isTop = opts.top and true or false,
            title = title, arrow = arrow or false }
        local mine = card
        card.open = function() if mine.shut then L.Fold(mine, true) end end
        L.cards[#L.cards + 1] = card
        if section then section.y0 = section.y section.of = card card.entries[#card.entries + 1] = section end
        if settings.index and settings.building then
            local e = settings.index[#settings.index]
            if e and e.row == f then e.y0 = e.y e.of = card card.entries[#card.entries + 1] = e end
        end
        card.head = L.HeadRow(f, title)
        if folds then
            -- the head folds and opens the card (its switch, a child of the card, is over it and keeps its own clicks)
            card.head:EnableMouse(true)
            card.head:SetScript("OnMouseUp", function() L.Fold(mine) end)
        end
        -- Whether what this card is about is on: the page's switches at its top say (L.features, by
        -- the card's name - a card can stand for several, and is lit while any of them is on), or the
        -- card's own master, or opts.on for a card that follows something else. Off: the whole card
        -- is greyed, head and rows. The switch itself is at the top of the page; a card whose
        -- feature isn't there carries its own in its head.
        local feats = L.features and L.features[title]
        local live
        if feats then
            live = function()
                for _, feat in ipairs(feats) do if feat.get() then return true end end
                return false
            end
        else
            live = (opts.master and opts.master[1]) or opts.on
        end
        card.live = live
        if live then
            -- Off is off: greyed, and nothing in the card answers the mouse. A frame lies over the
            -- card's rows (not its head, where the switch is) and takes every click and hover while
            -- the feature is off - a setting that looks dead and still changes when clicked is worse
            -- than one that looks alive.
            local block = CreateFrame("Frame", nil, c)
            block:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -CARD_HEAD)
            block:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
            block:SetFrameLevel(f:GetFrameLevel() + 40)
            block:EnableMouse(true)
            block:Hide()
            f.block = block
            local function Dim()
                local on = live() and true or false
                for _, r in ipairs(rowsHere) do r:SetAlpha(on and 1 or 0.40) end
                f:SetAlpha(on and 1 or 0.50)
                block:SetShown(not on)
            end
            if opts.master and not feats then
                local set = opts.master[2]
                local sw = S.Switch(f, live, function(on) set(on) Dim() YR:RefreshWindow() end)
                sw:SetPoint("TOPRIGHT", -14, -11)
                controls[#controls + 1] = sw
            end
            controls[#controls + 1] = { Refresh = Dim }
        end
        L.y = L.y - CARD_HEAD
        L.rowIndex = 0
        return f
    end

    -- The whole row lights up under the mouse, the control included, and a row that has details shows
    -- them after the mouse has rested on it a moment: no mark on the row says so, every row has them.
    -- (A mark after every name was a column of marks at different places down the page.)
    local rows, hot = {}, nil
    local function Paint(r) r.hl:SetShown(r == hot) end
    local wait, atX, atY, atScroll = 0, nil, nil, nil
    local rested, told = 0, nil          -- how long the mouse has been on the hot row; the row whose details show
    local REST = 0.35
    local function Tell(r)
        if told == r then return end
        told = r
        if r and r.tip then S.ShowInfo(r, r.title, r.tip) else S.HideInfo() end
    end
    area:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - (elapsed or 1)          -- twenty looks a second are plenty for a highlight
        if wait > 0 then return end
        wait = 0.05
        if hot and told ~= hot then
            rested = rested + 0.05
            if rested >= REST then Tell(hot) end
        end
        -- the mouse where it was and the page where it was: the same row as last time
        local x, y = GetCursorPosition()
        local scroll = area.GetVerticalScroll and area:GetVerticalScroll() or 0
        if x == atX and y == atY and scroll == atScroll then return end
        atX, atY, atScroll = x, y, scroll
        local now
        if area:IsMouseOver() then
            for _, r in ipairs(rows) do
                if r:IsVisible() and r:IsMouseOver() then now = r break end
            end
        end
        if now ~= hot then
            local was = hot
            hot, rested = now, 0
            if was then Paint(was) end
            if now then Paint(now) end
            if told and told ~= now then Tell(nil) end
        end
    end)
    area:SetScript("OnHide", function()
        S.Unpin()
        hot, atX, told = nil, nil, nil
        for _, r in ipairs(rows) do Paint(r) end
    end)
    -- Two settings to a row: a name at the left of its half, its control at the right. Every control
    -- of a kind is the same width, so the right edges and the left edges of a column line up. What is
    -- too wide for half a row (a slider) has the whole row. A row that is only words about the card -
    -- no control - isn't a row: its words are the card's own details, shown when you point at its head.
    -- L.y is always under the row being filled, so whatever a page puts after its rows starts below
    -- them whether the last row was full or not.
    local WIDE, DROP_W, GUTTER = 240, 180, 28
    function L.Row(label, control, tip)
        local other = settings.building and ROW_OTHER[label] and YR.OtherHas(ROW_OTHER[label])
        if other then tip = other .. " does this too: leave ours off unless you want both. " .. (tip or "") end
        local words = control.GetObjectType and control:GetObjectType() == "FontString"
        if words and tip and card and (control:GetText() or "") == "" and rawget(control, "Refresh") == nil then
            -- about the card, not a setting
            local f = card.frame
            f.about = (f.about and (f.about .. "\n\n") or "") .. tip
            if card.head then card.head.tip = f.about end
            control:Hide()
            if settings.index and settings.building then
                local e = { key = settings.building, label = label, tip = tip,
                    row = f, area = area, y = card.top, y0 = card.top, card = true, of = card }
                settings.index[#settings.index + 1] = e
                card.entries[#card.entries + 1] = e         -- (it follows the card when cards change places)
            end
            return f
        end
        label = (label:gsub("^%s+", ""))              -- (an indented name was a sub-setting in the one-column page)
        local h = ROW_H
        local inset = card and 1 or 0
        local full = L.colW - 2 * inset
        local half = math.floor(full / 2)
        local cw = control.GetWidth and control:GetWidth() or 0
        local wide = cw > WIDE
        local x, top, w
        if wide or L.col == 0 then
            x, top, w = inset, L.y, wide and full or half
            L.rowTop = top
            L.y = L.y - h - (card and 0 or 2)
            L.col = wide and 0 or 1
        else
            x, top, w = inset + half, L.rowTop, full - half
            L.col = 0
        end
        local r = CreateFrame("Frame", nil, c)
        r:SetSize(w, h)
        r:SetPoint("TOPLEFT", x, top)
        if card then
            r:SetFrameLevel(card.frame:GetFrameLevel() + 2)
            -- The two halves are two columns: each row's rule stops short of the middle, and a rule
            -- runs down the middle the whole height of every two-setting row - also where the right
            -- half is empty, so the columns read as columns and not as one line with a hole in it.
            local left = x == inset
            local line = r:CreateTexture(nil, "BORDER")
            line:SetPoint("TOPLEFT", (wide or left) and 12 or GUTTER, 0)
            line:SetPoint("TOPRIGHT", (wide or not left) and -12 or -GUTTER, 0)
            line:SetHeight(1)
            S.Set(line, S.C.line)
            if left and not wide then
                local split = r:CreateTexture(nil, "BORDER")
                split:SetPoint("TOPRIGHT", 0, 0)
                split:SetPoint("BOTTOMRIGHT", 0, 0)
                split:SetWidth(1)
                S.Set(split, S.C.lineHi)
            end
            card.rows[#card.rows + 1] = r
            card.items[#card.items + 1] = { r, x, top }
        else
            S.Fill(r, (L.rowIndex % 2 == 0) and S.C.card or ZEBRA)
        end
        r.hl = S.Fill(r, S.C.hover, "BACKGROUND", 1)
        r.hl:Hide()
        r.flash = S.Fill(r, S.C.accentD, "BACKGROUND", 2)
        r.flash:Hide()
        -- a name starts well clear of the middle, and a control ends well short of it
        local padL = (x ~= inset and not wide) and GUTTER or 16
        local padR = (x == inset and not wide) and GUTTER or 16
        local l = S.Text(r, 13)
        l:SetPoint("LEFT", padL, 0)
        l:SetText(label)
        r.control, r.infoBtn, r.title, r.tip = control, false, label, tip
        rows[#rows + 1] = r
        Paint(r)
        control:SetParent(r)
        control:ClearAllPoints()
        -- every dropdown in half a row is one width
        if not wide and control.options and control.SetWidth then control:SetWidth(DROP_W) cw = DROP_W end
        control:SetPoint("RIGHT", -padR, 0)
        -- The name never runs under its control: it gets the room left of it, and is cut short with an
        -- ellipsis if it needs more.
        local room = w - padL - padR - cw - 10
        l:SetWidth(math.max(40, room))
        l:SetJustifyH("LEFT")
        l:SetWordWrap(false)
        controls[#controls + 1] = control
        if settings.index and settings.building then      -- QoL pages only (Route settings is Levelling's)
            local e = { key = settings.building, label = label, tip = tip, row = r, area = area, y = top, y0 = top, of = card }
            settings.index[#settings.index + 1] = e
            if card then card.entries[#card.entries + 1] = e end
        end
        L.rowIndex = L.rowIndex + 1
        return r
    end
    -- Something of its own in a card, the card's whole width and as tall as it needs: a preview.
    -- Refreshed with the page's controls when it has a Refresh.
    function L.Block(frame, h)
        local inset = card and 1 or 0
        L.col = 0
        frame:SetParent(c)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", inset, L.y)
        frame:SetSize(L.colW - 2 * inset, h)
        if card then
            frame:SetFrameLevel(card.frame:GetFrameLevel() + 2)
            card.items[#card.items + 1] = { frame, inset, L.y }
        end
        L.y = L.y - h
        if frame.Refresh then controls[#controls + 1] = frame end
        return frame
    end
    -- A small heading inside the card: the rows under it are still this card's - this feature's - and
    -- are only set apart. (A card of its own for "Look" or "Colours" left you guessing whose look.)
    function L.Sub(text)
        L.col = 0
        local h = 26
        local r = CreateFrame("Frame", nil, c)
        r:SetSize(L.colW - (card and 2 or 0), h)
        r:SetPoint("TOPLEFT", card and 1 or 0, L.y)
        if card then
            r:SetFrameLevel(card.frame:GetFrameLevel() + 2)
            card.rows[#card.rows + 1] = r
            card.items[#card.items + 1] = { r, 1, L.y }
        end
        local line = r:CreateTexture(nil, "BORDER")
        line:SetPoint("TOPLEFT", 12, 0)
        line:SetPoint("TOPRIGHT", -12, 0)
        line:SetHeight(1)
        S.Set(line, S.C.line)
        local t = S.Text(r, 10, S.C.accent)
        t:SetPoint("BOTTOMLEFT", 16, 5)
        t:SetText((text or ""):upper())
        L.y = L.y - h
        return r
    end
    -- a card's own details: shown when you rest on its head (the rows under it have theirs)
    function L.HeadRow(f, title)
        local hit = CreateFrame("Frame", nil, c)
        hit:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        hit:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)          -- (it takes no clicks: the link and the switch still do)
        hit:SetHeight(CARD_HEAD - 2)
        hit.hl = S.Fill(hit, S.C.hover, "BACKGROUND", 1)
        hit.hl:Hide()
        hit.title = title
        rows[#rows + 1] = hit
        return hit
    end
    return L
end

local function BuildRouteSettings(page)
    local L = RowPage(page, settings.controls, 106)
    local c = L.c
    local Section, Row = L.Section, L.Row
    local function Opt(key) return function() return YR.Option(key) end end
    local function SetOpt(key, after) return function(on) YippRouteDB[key] = on if after then after(on) end end end
    local st = function() return YR:SplitsStyle() end
    local function Style(field) return function(v) st()[field] = v YR:ApplySplitsStyle() end end

    Section("Routes", "off by default", { icon = 134269 })
    Row("Routes (account-wide)", S.Switch(c, function() return YR.RoutesOn() end,
        function(on) YR.SetRoutesOn(on) YR:RefreshWindow() end),
        "Loads your saved, imported and edited routes into RestedXP, and keeps and buys the items they"
        .. " need. Off: none of that runs, and the settings below are inactive. Takes a /reload. Also"
        .. " /headstart routes on|off.")

    Section("General", nil, { icon = 134063 })
    Row("Minimap button", S.Switch(c, Opt("minimapButton"), SetOpt("minimapButton", function(on) YR:ShowMinimapButton(on) end)))
    -- Everything after this is about the routes: dimmed while they're off (RefreshRouteSettings).
    settings.routeRows = {}
    local plainRow = Row
    Row = function(...)
        local r = plainRow(...)
        settings.routeRows[#settings.routeRows + 1] = r
        return r
    end
    Row("Record runs", S.Switch(c, Opt("logging"), SetOpt("logging", function(on) YR:SetLogging(on) end)),
        "Records quests, levels, deaths, purchases, sales, quest loot and your position every 2 seconds."
        .. " Used by This run and the route analysis.")
    Row("Protect route items", S.Switch(c, Opt("sellGuard"), SetOpt("sellGuard")),
        "Marks items a route quest still needs on their tooltip, and warns you when you sell one so you"
        .. " can buy it back.")
    Row("Buy skipped items later", S.Switch(c, Opt("buyLater"), SetOpt("buyLater")),
        "Reminds you of a purchase the route skipped because you were short on money. Once you can afford"
        .. " it and it is still an upgrade, chat tells you where, and a vendor who sells it asks whether to"
        .. " buy. Hold Shift as you open the vendor to skip.")
    Row("Camping 101 reminder", S.Switch(c, Opt("campReminder"), SetOpt("campReminder")),
        "Dun Morogh: tells you when your bags hold enough ore and stone to take Blacksmithing to 20 for"
        .. " Camping 101, and where to go. Repeats each time you enter Kharanos until it is done.")
    Row("Release at death skips", S.Switch(c, Opt("deathSkipRelease"), SetOpt("deathSkipRelease")),
        "Releases your spirit at once when the current route step tells you to die and respawn, and"
        .. " accepts the Spirit Healer's resurrection without asking, at whatever that costs in the game. It goes by"
        .. " the step that is showing, so a death you didn't plan on such a step is released too. Off until you"
        .. " turn it on.")
    Row("Abandon skipped quests", S.Switch(c, Opt("skipQuests"), SetOpt("skipQuests")),
        "Abandons a quest the route skips when it is accepted within a second of its window opening, which is"
        .. " how another addon accepts it (a very quick click of yours looks the same). Only with a routes addon"
        .. " that lists such quests. Once a session: accept the quest again and it stays. Off until you turn it on.")

    Section("Group play", "for a duo or trio on the same route", { icon = 134149 })
    local role = S.Dropdown(c, 190, YR.ROLES, function(v) YR:SetRole(v) YR:RefreshWindow() end)
    function role:Refresh()
        for _, r in ipairs(YR.ROLES) do if r[1] == YR:Role() then self:SetValue(r[2]) end end
    end
    Row("Role", role, "Routes with a group version give each role its own steps. Agree on roles with your group. Solo:"
        .. " the normal route.")
    Row("Share route quests", S.Switch(c, Opt("groupShare"), SetOpt("groupShare")),
        "Shares a route quest with your party as soon as you accept it. Off until you turn it on.")
    Row("Accept shared route quests", S.Switch(c, Opt("groupAccept"), SetOpt("groupAccept")),
        "Accepts quests and escorts on the route that your party shares, from anyone in the party. Other"
        .. " quests still ask. Hold Shift to decide yourself (an escort that has already started is taken"
        .. " either way). Off until you turn it on.")
    Row("Party steps", S.Switch(c, Opt("groupPanel"), SetOpt("groupPanel", function() YR:RefreshParty() end)),
        "Shows a small list under the splits: each party member with Headstart, their role and their"
        .. " current step.")

    Section("Level splits", nil, { icon = 236562 })
    Row("Show level splits", S.Switch(c, Opt("showSplits"), SetOpt("showSplits", function(on) YR:ShowSplits(on) end)))
    Row("Lock position", S.Switch(c, function() return st().lock end, Style("lock")),
        "Locked: the box can't be dragged, and clicks pass through it.")
    Row("Text size", RowSlider(c, 10, 24, 1, function() return st().size end, Style("size")))
    Row("Levels listed", RowSlider(c, 1, 60, 1, function() return st().rows end, Style("rows")),
        "How many finished levels are listed below the current one.")
    Row("Show XP per hour", S.Switch(c, function() return st().rate end, Style("rate")))
    Row("Show time to ding", S.Switch(c, function() return st().ding end, Style("ding")))
    local CLOCKS = { { "full", "1:50:19" }, { "short", "1h 50m" } }
    local clock
    clock = S.Dropdown(c, 120, CLOCKS, function(v) Style("clock")(v) clock:Refresh() end)
    function clock:Refresh()
        for _, o in ipairs(CLOCKS) do if o[1] == st().clock then self:SetValue(o[2]) end end
    end
    Row("Times over an hour", clock, "How times of an hour or more are written. The short form drops the seconds.")
    Row("Level column", S.Switch(c, function() return st().levelCol end, Style("levelCol")),
        "Shows how long each level took.")
    Row("Total column", S.Switch(c, function() return st().totalCol end, Style("totalCol")),
        "Shows your played time from level 1 at each level.")
    Row("Vs best column", S.Switch(c, function() return st().vs end, Style("vs")),
        "Shows your total against your best run at each level: ahead in green, behind in red.")
    local COMPARE = { { "any", "Any run" }, { "class", "Same class" }, { "race", "Same class and race" } }
    local compare
    compare = S.Dropdown(c, 190, COMPARE, function(v)
        YippRouteDB.splitsCompare = v ~= "any" and v or nil
        compare:Refresh()
        YR:ApplySplitsStyle()
    end)
    function compare:Refresh()
        for _, o in ipairs(COMPARE) do if o[1] == (YippRouteDB.splitsCompare or "any") then self:SetValue(o[2]) end end
    end
    Row("Compare with", compare, "Which of your runs the comparison columns use: any run, only your class, or your class and race."
        .. " Dwarf and Gnome count as one, since they share a start.")
    Row("Show the ± level column", S.Switch(c, function() return st().levelVs end, Style("levelVs")),
        "Shows what each level gained or lost against the same level of your best run: -0:40 is 40"
        .. " seconds faster.")
    Row("Background (percent)", RowSlider(c, 0, 100, 5, function() return st().bg end, Style("bg")),
        "How dark the box behind the splits is. 0: none.")
    Row("X position (pixels)", RowSlider(c, 0, 3000, 1, function() return YR:SplitsPosition()[1] end,
        function(v) YR:SetSplitsPosition(v, nil) end, 280))
    Row("Y position (pixels)", RowSlider(c, 0, 2000, 1, function() return YR:SplitsPosition()[2] end,
        function(v) YR:SetSplitsPosition(nil, v) end, 280))

    -- The logs take room whether the routes are on or not, so these rows are never dimmed.
    Section("Run logs", "all characters, stored account-wide", { icon = 134328 })
    local function Ago(t)
        local d = math.floor((time() - t) / 86400)
        return d < 1 and "today" or d == 1 and "yesterday" or (d .. " days ago")
    end
    local total = CreateFrame("Frame", nil, c)
    total:SetSize(330, 24)
    total.text = S.Text(total, 13)
    total.text:SetPoint("RIGHT")
    function total:Refresh()
        local n, kb = 0, 0
        for _, l in ipairs(YR.LogSummary()) do n, kb = n + 1, kb + l.kb end
        self.text:SetText(("%d character%s, about %s"):format(n, n == 1 and "" or "s",
            kb >= 1024 and ("%.1f MB"):format(kb / 1024) or (kb .. " KB")))
    end
    plainRow("On this account", total, "Each character's quests, levels, deaths and position samples, for This run,"
        .. " the level splits and the route analysis. All of them load on every character, so old ones are worth deleting")
    local pick = S.Dropdown(c, 330, function()
        local out = {}
        for _, l in ipairs(YR.LogSummary()) do
            out[#out + 1] = { l.key, ("%s  |cff999999%d KB, %s|r"):format(l.key, l.kb, Ago(l.last)) }
        end
        if #out == 0 then out[1] = { false, "No logs", S.C.muted } end
        return out
    end, function(key)
        if key then StaticPopup_Show("HEADSTART_DELETE_LOG", key, nil, key) end
    end)
    function pick:Refresh() self:SetValue("Pick a character...") end
    plainRow("Delete a character's log", pick, "Asks first. This character's log starts again from now")
    plainRow("Delete logs not played for (days)", S.Stepper(c, YR.LogKeepDays,
        function(v) YippRouteDB.logKeepDays = math.max(0, v) end, 0, 365, 5, 110),
        "At login, the logs of characters you haven't played for this many days are deleted. Never this"
        .. " character's, a fastest run's (one the level splits compare with) or one a route of yours was"
        .. " saved from. 30 unless you set another number; 0 keeps them all")
    local scan = S.Button(c, "Delete", function()
        if YR.DeleteScan() then YR.Print("deleted the quest scan.") end
        YR:RefreshWindow()
    end, nil, 90)
    function scan:Refresh() self:SetEnabled(type(_G.HeadstartScanDB) == "table" and _G.HeadstartScanDB.scan ~= nil) end
    plainRow("The quest scan's results", scan, "What /headstart scan read (quest XP, objectives) for the route data."
        .. " Only needed until it's been taken out of the saved file")

    L.Break()
    c:SetHeight(-L.y + 40)
end

-- Quest rewards, on the QoL tab: a section of rows, the priority list, then the rewards you chose
-- by hand (as many as there are, so it goes last on its page).
local rew = {}

local function BuildRewards(L)
    local c, colW = L.c, L.colW
    local Section, Row = L.Section, L.Row
    Section("Quest rewards", "set per class", { icon = 134939 })
    Row("Class", ClassPicker(c), "The class whose reward settings you are viewing. Each class has its own.")
    Row("Pick quest rewards", S.Switch(c, function() return YR:RewardSettings(ViewClass()).on end,
        function(on) YR:RewardSettings(ViewClass()).on = on end),
        "Chooses a reward and hands the quest in when it offers a choice, up to the level below. The choice"
        .. " is final. Off until you turn it on. Hold Shift when handing in to choose yourself.")
    Row("Up to level", RowSlider(c, 1, 60, 1, function() return YR:RewardSettings(ViewClass()).maxLevel end,
        function(v) YR:RewardSettings(ViewClass()).maxLevel = v end))
    Row("Reuse my earlier choice", S.Switch(c, function() return YR:RewardSettings(ViewClass()).remember end,
        function(on) YR:RewardSettings(ViewClass()).remember = on end), "Takes the reward you picked by hand for the same quest before.")
    Row("Ask when a green is offered", S.Switch(c, function() return YR:RewardSettings(ViewClass()).greenStop end,
        function(on) YR:RewardSettings(ViewClass()).greenStop = on end),
        "Leaves the choice to you when a green or better item is among the rewards. RestedXP's own picks"
        .. " wait too. Hold Shift when talking to an NPC to stop all quest automation for that window.")
    local fallback = S.Dropdown(c, 170, { { "value", "The most valuable" }, { "ask", "Let me choose" } }, function(v)
        YR:RewardSettings(ViewClass()).fallback = v
        YR:RefreshWindow()
    end)
    function fallback:Refresh() self:SetValue(YR:RewardSettings(ViewClass()).fallback == "value" and "The most valuable" or "Let me choose") end
    Row("If nothing on the list is offered", fallback)
    L.Break()
    local y = L.y
    local tail = L.Tail()       -- under the cards, and up with them as they fold

    y = y - 10
    local t = S.Text(tail, 12, S.C.muted)
    t:SetPoint("TOPLEFT", 4, y)
    t:SetText("Priority: the first kind on offer is taken. Switch off the kinds you never want.")
    y = y - 20
    rew.order = {}
    for i = 1, #YR.REWARD_KINDS do
        local r = CreateFrame("Frame", nil, tail)
        r:SetSize(colW, 30)
        r:SetPoint("TOPLEFT", 0, y)
        S.Fill(r, (i % 2 == 1) and S.C.card or ZEBRA)
        r.num = S.Text(r, 12, S.C.muted)
        r.num:SetPoint("LEFT", 12, 0)
        r.label = S.Text(r, 13)
        r.label:SetPoint("LEFT", 40, 0)
        r.switch = S.Switch(r, function() local db = YR:RewardSettings(ViewClass()) return not db.off[db.order[i]] end,
            function(on) local db = YR:RewardSettings(ViewClass()) db.off[db.order[i]] = (not on) or nil YR:RefreshWindow() end)
        r.switch:SetPoint("RIGHT", -72, 0)
        local function Swap(d)
            local db = YR:RewardSettings(ViewClass())
            local b = i + d
            if b < 1 or b > #db.order then return end
            db.order[i], db.order[b] = db.order[b], db.order[i]
            YR:RefreshWindow()
        end
        local up = S.IconButton(r, "up", function() Swap(-1) end, "Higher")
        up:SetPoint("RIGHT", -36, 0)
        local down = S.IconButton(r, "down", function() Swap(1) end, "Lower")
        down:SetPoint("RIGHT", -10, 0)
        rew.order[i] = r
        y = y - 30
    end

    y = y - 18
    local h = S.Text(tail, 12, S.C.accent)
    h:SetPoint("TOPLEFT", 4, y)
    h:SetText("REWARDS YOU CHOSE YOURSELF")
    y = y - 22
    rew.chosenY, rew.chosenRows, rew.content, rew.width, rew.L = y, {}, tail, colW, L
    L.Length(-y + 28 * 20)
end

local function RefreshRewards()
    local db = YR:RewardSettings(ViewClass())
    for i, r in ipairs(rew.order) do
        local kind = db.order[i]
        r.num:SetText(i)
        r.label:SetText(KIND_LABEL[kind] or kind)
        r.label:SetTextColor(unpack(db.off[kind] and S.C.muted or S.C.text))
        r.switch:Refresh()
    end
    local list = {}
    for quest, e in pairs(db.chosen) do list[#list + 1] = { quest = quest, e = e } end
    table.sort(list, function(a, b) return (a.e.title or "") < (b.e.title or "") end)
    for i = 1, math.max(#list, #rew.chosenRows) do
        local r = rew.chosenRows[i]
        if not r and list[i] then
            r = CreateFrame("Frame", nil, rew.content)
            r:SetSize(rew.width, 28)
            r:SetPoint("TOPLEFT", 0, rew.chosenY - (i - 1) * 28)
            S.Fill(r, (i % 2 == 1) and S.C.card or ZEBRA)
            r.label = S.Text(r, 13)
            r.label:SetPoint("LEFT", 12, 0)
            r.x = S.IconButton(r, "close", function() YR:RewardSettings(ViewClass()).chosen[r.quest] = nil YR:RefreshWindow() end,
                "Forget this choice", S.C.danger)
            r.x:SetPoint("RIGHT", -8, 0)
            rew.chosenRows[i] = r
        end
        if r then
            if list[i] then
                r:Show()
                r.quest = list[i].quest
                r.label:SetText((list[i].e.title or ("Quest " .. list[i].quest)) .. "   |cffffd24a" .. (list[i].e.name or "") .. "|r")
            else
                r:Hide()
            end
        end
    end
    -- as long as the list: more than twenty remembered choices could not be scrolled to
    if rew.L and rew.chosenY then rew.L.Length(-rew.chosenY + 28 * math.max(#list, 2) + 60) end
    if not rew.none then
        rew.none = S.Text(rew.content, 12, S.C.muted)
        rew.none:SetPoint("TOPLEFT", 12, rew.chosenY - 6)
        rew.none:SetText("None yet. Hold Shift when handing in a quest and pick a reward: it's remembered here.")
    end
    rew.none:SetShown(#list == 0)
end

local function RefreshRouteSettings()
    for _, ctl in ipairs(settings.controls) do if ctl.Refresh then ctl:Refresh() end end
    local on = YR.RoutesOn()
    for _, r in ipairs(settings.routeRows or {}) do r:SetAlpha(on and 1 or 0.4) end
end

-- ---------------------------------------------------------------------------
-- Character setup: what a new character gets from your main, part by part
-- ---------------------------------------------------------------------------
local setup = { controls = {} }

local function BuildSetup(page)
    local YS = YR.Setup
    local o = function() return YS:Options(ViewClass()) end
    local function Mine() return ViewClass() == select(2, UnitClass("player")) end
    local function Said(ok, why) if not ok and why then YR.Print(why) end YR:RefreshWindow() end

    -- The top: the profile this character is on, and the two things most people come here to do.
    local card = CreateFrame("Frame", nil, page)
    card:SetPoint("TOPLEFT", 16, -14)
    card:SetPoint("TOPRIGHT", -16, -14)
    card:SetHeight(72)
    S.Fill(card, S.C.card)
    S.Border(card)
    setup.saved = S.Text(card, 14)
    setup.saved:SetPoint("TOPLEFT", 14, -14)
    setup.note = S.Text(card, 12, S.C.muted)
    setup.note:SetPoint("TOPLEFT", 14, -36)
    -- the words under it: what a profile is - or, when you've changed a choice since the profile was
    -- last put on this character, that it isn't on your bars yet
    -- One line that says where this character stands, and the one thing to do next (if anything).
    function setup.Pending()
        local _, class = UnitClass("player")
        local p = YS:Profile(ViewClass())
        local char = _G.YippSetupCharDB
        local text, gold
        if ViewClass() ~= class then
            text = "You are viewing another class. Pick your own class to change this character."
        elseif not (p and p.slots and next(p.slots)) then
            text = "This profile is empty. Click Plan bars: it starts from your current bars."
        elseif not (char and char.applied) then
            text, gold = "Not applied to this character yet. Apply asks first, and can be undone.", true
        elseif YS.ChoicesPending and YS.ChoicesPending() then
            text, gold = "Settings changed since the last apply. Click Apply to update your bars.", true
        elseif YS.Remembers and not YS.Remembers() then
            text = "Applied. Bar changes are not saved automatically (Profiles tab)."
        else
            text = "Applied. Changes you make to your bars are saved to this profile."
        end
        setup.note:SetText(text)
        setup.note:SetTextColor(unpack(gold and S.C.gold or S.C.muted))
    end
    setup.Pending()
    local apply = S.Button(card, "Apply to this character", function() YS:Apply() YR:RefreshWindow() end, "primary")
    apply:SetPoint("RIGHT", -12, 0)
    local plan = S.Button(card, "Plan bars...", function() YR.OpenPlanner() end, nil, 120)
    plan:SetPoint("RIGHT", apply, "LEFT", -8, 0)
    plan.tip = "Opens the bar planner: drag any spell your class can learn onto a button, also ones you don't know yet"
    setup.apply, setup.plan = apply, plan
    for _, t in ipairs({ setup.saved, setup.note }) do
        t:SetPoint("RIGHT", plan, "LEFT", -16, 0)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(false)
    end

    -- Four short pages instead of one long one.
    local TABS = { { "profiles", "Profiles" }, { "bars", "Bars" }, { "interface", "Interface" }, { "new", "New characters" } }
    local tabs, chips = {}, {}
    local function ShowTab(key)
        setup.tab = key
        for k, f in pairs(tabs) do f:SetShown(k == key) end
        for k, c in pairs(chips) do c:SetOn(k == key) end
    end
    local prev
    for _, t in ipairs(TABS) do
        local key = t[1]
        local chip = S.Chip(page, t[2], function() ShowTab(key) end)
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", 16, -96) end
        prev = chip
        chips[key] = chip
        local f = CreateFrame("Frame", nil, page)
        f:SetPoint("TOPLEFT", 0, -124)
        f:SetPoint("BOTTOMRIGHT")
        tabs[key] = f
    end
    local L, Section, Row
    local need      -- the macro count further down: every choice it depends on asks it to count again
    local function Recount() if need then need:Refresh() end setup.Pending() end
    local function Sw(key) local b = S.Switch(L.c, function() return o()[key] end, function(on) o()[key] = on Recount() end) return b end
    -- the rows that follow go on this tab
    local function Page(key)
        if L then
            L.Break()
            L.c:SetHeight(-L.y + 20)
        end
        L = RowPage(tabs[key], setup.controls, 186)
        Section, Row = L.Section, L.Row
    end

    -- ------------------------------------------------------------------ Profiles
    Page("profiles")
    Section("Profiles", "named sets of bars, one per role", { icon = 134166 })
    Row("Class", ClassPicker(L.c), "The class whose profiles and settings you are viewing. Each class has its own.")
    local layout
    layout = S.Dropdown(L.c, 200, function()
        local out = {}
        for _, name in ipairs(YS.LayoutNames(ViewClass())) do out[#out + 1] = { name, name } end
        return out
    end, function(name)
        if Mine() and name ~= YS.LayoutName() then Said(YS.LayoutSwitch(name)) end      -- (a character never set up: asked first)
    end)
    function layout:Refresh()
        self:SetValue(Mine() and YS.LayoutName() or YS.LayoutNames(ViewClass())[1])
        self:SetEnabled(Mine() and not InCombatLockdown())
    end
    Row("Active profile", layout, "The profile this character uses. Pick another to switch: your current bars are saved to the old"
        .. " profile first, and only the buttons that differ change. Also on the minimap button's"
        .. " right-click menu, a key binding, and /headstart profile <name>.")
    local naming = CreateFrame("Frame", nil, L.c)
    naming:SetSize(330, 24)
    naming.input = S.Input(naming, { width = 150, placeholder = "A name: Tank, Healer..." })
    naming.input:SetPoint("LEFT")
    naming.add = S.Button(naming, "New", function()
        Said(YS.LayoutNew(naming.input:GetText()))
        naming.input:SetText("")
    end, nil, 80)
    naming.add:SetHeight(24)
    naming.add:SetPoint("LEFT", naming.input, "RIGHT", 6, 0)
    naming.add.tip = "Saves your current bars as a new profile with this name, and switches to it"
    naming.rename = S.Button(naming, "Rename", function()
        Said(YS.LayoutRename(YS.LayoutName(), naming.input:GetText()))
        naming.input:SetText("")
    end, nil, 80)
    naming.rename:SetHeight(24)
    naming.rename:SetPoint("LEFT", naming.add, "RIGHT", 6, 0)
    naming.rename.tip = "Give the profile you are on this name"
    function naming:Refresh()
        self.add:SetEnabled(Mine())
        self.rename:SetEnabled(Mine())
    end
    Row("New profile", naming, "Type a name and click New to save your current bars as a new profile and switch to it. Rename"
        .. " gives the active profile that name.")
    StaticPopupDialogs["HEADSTART_DELETE_LAYOUT"] = {
        text = "Headstart: delete the profile %s?\n\nYour bars stay as they are, and you switch to the class's first profile.",
        button1 = "Delete", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(_, name) Said(YS.LayoutDelete(name)) end,
    }
    local del = S.Button(L.c, "Delete", function()
        local name = YS.LayoutName()
        StaticPopup_Show("HEADSTART_DELETE_LAYOUT", name, nil, name)
    end, nil, 90)
    function del:Refresh() self:SetEnabled(Mine() and YS.LayoutName() ~= YS.LayoutNames()[1]) end
    Row("Delete profile", del, "Deletes the active profile. Asks first. A class's first profile can't be deleted.")

    Section("This profile", "what it saves besides bars", { icon = 134063 })
    local ownUI = S.Switch(L.c, function() return Mine() and YS.ProfileOwnUI() end, function(on)
        if Mine() then YS.SetProfileOwnUI(on) end
        YR:RefreshWindow()
    end)
    Row("Include interface", ownUI, "Also saves this profile's Edit Mode layout, which extra bars are shown, and RestedXP's window"
        .. " positions, and restores them when you switch to it. Off: switching profile only changes your"
        .. " bars. For a separate screen layout, create a layout in Edit Mode first, then turn this on.")
    Row("Save bar changes automatically", S.Switch(L.c, function() return YS.Remembers() end, function(on)
        if on then YippSetupDB.remember = nil else YippSetupDB.remember = false end
        YR:RefreshWindow()
    end), "Saves a change to your bars into the active profile a few seconds after you make it. Buttons"
        .. " planned for later levels keep their place. Off: the profile only changes when you plan it or"
        .. " save into it.")
    local copy = S.Button(L.c, "Copy", function() YS:Copy() YR:RefreshWindow() end, nil, 90)
    setup.copy = copy
    Row("Save bars now", copy, "Saves this character's bars, macros and items into the active profile. Asks before replacing"
        .. " one. Rarely needed with automatic saving on.")
    local SPEC = { { "ask", "Ask me" }, { "auto", "Switch by itself" }, { "off", "Nothing" } }
    local spec
    spec = S.Dropdown(L.c, 200, SPEC, function(v) YippSetupDB.specAsk = v ~= "ask" and v or nil spec:Refresh() end)
    function spec:Refresh() for _, x in ipairs(SPEC) do if x[1] == YS.SpecAsk() then self:SetValue(x[2]) end end end
    Row("On spec change", spec, "What happens when you change spec. Headstart remembers the profile you used in each spec, and"
        .. " can ask to switch, switch at once, or do nothing. Only applies when the class has more than one"
        .. " profile.")

    -- ------------------------------------------------------------------ Bars
    Page("bars")
    Section("Spells", nil, { icon = 133742 })
    Row("Class spells", Sw("classSpells"), "Places every spell you know on its planned button. Spells you learn later go on their button"
        .. " when you learn them.")
    Row("Placeholder range (levels)", S.Stepper(L.c, function() return YS.Ahead(o()) end, function(v) o().ahead = v Recount() end, 0, 60, 1, 110),
        "A spell you will learn within this many levels gets a question-mark placeholder on its button."
        .. " Later spells leave the button empty until learned. Each placeholder uses one of the character's"
        .. " 30 macros. Talent spells never get a placeholder.")
    local BUTTONS = {
        { "placeholder", "A ? until I learn it" },
        { "spells", "Empty until I learn it" },
        { "macros", "Always a macro" },
    }
    local buttons
    buttons = S.Dropdown(L.c, 200, BUTTONS, function(v) o().spellButtons = v buttons:Refresh() Recount() end)
    function buttons:Refresh()
        local cur = YS.SpellButtons(o())
        for _, b in ipairs(BUTTONS) do if b[1] == cur then self:SetValue(b[2]) end end
    end
    Row("Unlearned spells", buttons, "Placeholder: a question-mark macro holds the button and is replaced by the spell when you learn"
        .. " it. Empty: the button stays empty until you learn the spell, and no macros are made. Always a"
        .. " macro: every class spell is a \"#showtooltip /cast\" macro, which can reach the character's macro"
        .. " limit.")
    need = CreateFrame("Frame", nil, L.c)
    need:SetSize(220, 24)
    need.text = S.Text(need, 13)
    need.text:SetPoint("RIGHT")
    function need:Refresh()
        local n, limit = YS:MacrosNeeded(YS:Profile(ViewClass()), o(), ViewClass())
        self.text:SetText(("%d of %d"):format(n, limit))
        self.text:SetTextColor(unpack(n > limit and S.C.danger or n > limit - 5 and S.C.gold or S.C.text))
    end
    Row("Character macros needed", need, "How many of the character's 30 macro slots this profile and these settings need: your own"
        .. " macros, mouseover spells and placeholders. Apply stops at the limit. Account macros are not"
        .. " counted.")
    Row("Racial spells", Sw("racials"), "Stoneform, Shadowmeld and similar.")
    Row("Profession spells", Sw("professions"), "Find Minerals, Smelting, Cooking and similar. Each is placed when you learn the profession.")
    local mo = S.Input(L.c, { width = 200, placeholder = "e.g. Purify, Holy Light", onCommit = function(t) o().mouseover = t Recount() end })
    function mo:Refresh() if not self:HasFocus() then self:SetValue(o().mouseover) end end
    Row("Mouseover macros", mo, "Spells listed here are placed as /cast [@mouseover] macros: cast on the unit under your mouse,"
        .. " otherwise on yourself. Separate names with commas.")

    Section("Macros and items", nil, { icon = 134394 })
    Row("Your own macros", Sw("macros"))
    Row("AutoFeed's macros", Sw("autofeed"), "The AutoFeed macros on your main's bars. AutoFeed makes them on this"
        .. " character if it hasn't yet, and keeps them filled with your best food, water and potions."
        .. (YR.Setup:AutoFeedLoaded() and "" or "\n\nAutoFeed isn't loaded right now, so these slots stay empty."))
    Row("Items I don't carry", Sw("items"), "Places items from the profile that this character doesn't have yet. Items the character carries,"
        .. " like the hearthstone, are always placed.")

    Section("Before applying", nil, { icon = 134520 })
    Row("Clear bars first", Sw("clearBars"), "Empties every action bar before applying. Off: saved buttons replace what is there, and buttons"
        .. " that are empty in the profile leave yours alone.")
    Row("Delete old character macros", Sw("clearMacros"), "Deletes this character's own macros before applying. Account macros and AutoFeed's are never"
        .. " touched.")
    local undo = S.Button(L.c, "Undo", function() YS:Undo() end, nil, 90)
    function undo:Refresh()
        local char = _G.YippSetupCharDB          -- this character's saved table (Setup.lua fills it at login)
        self:SetEnabled(type(char) == "table" and (char.backup ~= nil or char.uiBackup ~= nil))
    end
    Row("Undo last change", undo, "Puts this character's bars, macros and game settings back as they were before the last change"
        .. " Headstart made to them: an apply, the planner or a switch of profile. Press again to go a step further back"
        .. " (five are kept). Mounts and toys on bars can't be placed by an addon. Also /ysetup undo")
    local before = S.Button(L.c, "Put back", function() YS:Undo(true) end, nil, 90)
    function before:Refresh()
        local char = _G.YippSetupCharDB
        self:SetEnabled(type(char) == "table" and char.first ~= nil)
    end
    Row("Bars before Headstart", before, "Puts this character's bars and macros back as they were before Headstart first changed"
        .. " anything on it, whatever was applied since. That copy is kept for good. Also /ysetup undo first")

    -- ------------------------------------------------------------------ Interface
    Page("interface")
    Section("Interface", "chat, Edit Mode and game settings, shared by all classes", { icon = 134063 })
    local function UINames()
        local out = {}
        for _, name in ipairs(YS.UINames()) do out[#out + 1] = { name, name } end
        return out
    end
    local uiPick = S.Dropdown(L.c, 200, UINames, function(name) Said(YS.UIPick(name)) end)
    function uiPick:Refresh()
        self:SetValue(YS:SharedUI() and YS.UIName() or "none saved yet")
        self:SetEnabled(#YS.UINames() > 0)
    end
    Row("This character uses", uiPick, "The saved interface this character is on. Picking another changes nothing on screen: Apply interface"
        .. " puts it on.")
    local uiSaved = S.Text(L.c, 12, S.C.sub)
    function uiSaved:Refresh()
        local from, at = YS.UISource(), YS.UIScanned()
        self:SetText(from and (from .. (at and ("  -  " .. date("%d %b %H:%M", at)) or "")) or "nothing saved yet")
    end
    Row("Last saved", uiSaved, "The character that last saved this interface, and when.")
    local saveUI = S.Button(L.c, "Save interface", function() YS:SaveInterface() end, nil, 130)
    Row("Save interface", saveUI, "Saves this character's chat windows, Edit Mode layout, game settings, visible bars, camera and"
        .. " RestedXP look into the interface it uses. Asks first when the interface was last saved on another character."
        .. " Bars are not changed.")
    local uiNaming = CreateFrame("Frame", nil, L.c)
    uiNaming:SetSize(330, 24)
    uiNaming.input = S.Input(uiNaming, { width = 150, placeholder = "A name: Main, Healer..." })
    uiNaming.input:SetPoint("LEFT")
    uiNaming.add = S.Button(uiNaming, "Save as", function()
        local name = strtrim(uiNaming.input:GetText() or "")
        if name == "" then Said(false, "it needs a name.") return end
        YS:SaveInterface(name)
        uiNaming.input:SetText("")
    end, nil, 80)
    uiNaming.add:SetHeight(24)
    uiNaming.add:SetPoint("LEFT", uiNaming.input, "RIGHT", 6, 0)
    uiNaming.add.tip = "Saves this character's interface under this name, and puts the character on it"
    uiNaming.rename = S.Button(uiNaming, "Rename", function()
        Said(YS.UIRename(YS.UIName(), uiNaming.input:GetText()))
        uiNaming.input:SetText("")
    end, nil, 80)
    uiNaming.rename:SetHeight(24)
    uiNaming.rename:SetPoint("LEFT", uiNaming.add, "RIGHT", 6, 0)
    uiNaming.rename.tip = "Give the interface this character uses this name"
    function uiNaming:Refresh() self.rename:SetEnabled(YS:SharedUI() ~= nil) end
    Row("New interface", uiNaming, "Type a name and click Save as to keep this character's interface as a second one, for a healer"
        .. " or a tank for example. Rename gives the one this character uses that name.")
    local uiFirst = S.Dropdown(L.c, 200, UINames, function(name) Said(YS.UISetDefault(name)) end)
    function uiFirst:Refresh()
        self:SetValue(YS.UIRecord() and YS.UIDefault() or "none saved yet")
        self:SetEnabled(#YS.UINames() > 1)
    end
    Row("New characters get", uiFirst, "The interface offered on a new character's first login.")
    StaticPopupDialogs["HEADSTART_DELETE_UI"] = {
        text = "Headstart: delete the saved interface %s?\n\nNothing on screen changes. Characters that used it go back to the one new characters get.",
        button1 = "Delete", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true,
        OnAccept = function(_, name) Said(YS.UIDelete(name)) end,
    }
    local uiDel = S.Button(L.c, "Delete", function()
        local name = YS.UIName()
        StaticPopup_Show("HEADSTART_DELETE_UI", name, nil, name)
    end, nil, 90)
    function uiDel:Refresh() self:SetEnabled(YS:SharedUI() ~= nil and YS.UIName() ~= YS.UIDefault()) end
    Row("Delete interface", uiDel, "Deletes the interface this character uses. Asks first. The one new characters get can't be deleted.")
    Row("Keep it up to date", S.Switch(L.c, function() return YS.UIFollows() end, function(on)
        if on then _G.YippSetupDB.uiFollow = nil else _G.YippSetupDB.uiFollow = false end
    end), "Saves the interface again when you change something on a character that uses it: when you leave Edit Mode"
        .. " and when you log out. The other characters on it are asked whether to take the change at their next login.")
    local applyUI = S.Button(L.c, "Apply interface", function() YS:AskInterface() end, "primary", 130)
    function applyUI:Refresh() self:SetEnabled(YS:SharedUI() ~= nil) end
    Row("Apply interface", applyUI, "Applies the saved interface to this character, limited by the switches below, after asking. Bars"
        .. " and macros are not touched. Game settings can be undone; chat windows and the Edit Mode layout can't, and a"
        .. " chat tab the saved interface doesn't have is closed.")
    Row("Game settings", Sw("settings"), "What the Options window's own pages set: controls, mouse and camera, combat, names and nameplates,"
        .. " raid frames, social, map coordinates, accessibility. Not the language, the network or which help tips you have seen.")
    Row("Key bindings", Sw("keys"), "Your keys as they were where the interface was saved, action by action - a default you took off"
        .. " stays off. Saved as the game saves them (the account's, unless you use character-specific bindings). /ysetup undo"
        .. " puts back the keys you had. An interface saved before this was added has none: press Save interface once.")
    Row("Graphics and sound", Sw("graphics"), "The Options window's Graphics and Audio settings: quality, effects, frame rate limits, volumes and"
        .. " which sounds play. The game keeps these per install, so this matters on another one - the live game after the beta."
        .. " Not the monitor, window, resolution or sound device. /ysetup undo puts back what you had. An interface saved before"
        .. " this was added has none: press Save interface once.")
    Row("Edit Mode layout", Sw("editMode"), "Skipped when a UI suite like ElvUI or EllesmereUI is loaded.")
    Row("Visible action bars", Sw("barVisibility"), "Skipped when a bar addon like Bartender or Dominos is loaded.")
    Row("Chat windows", Sw("chat"), "Chat tabs with their names, channels, font size, colours, and docked or floating position.")
    Row("Camera distance", Sw("camera"), "Zooms out as far as on the character you copied from. Also applied once to a new character after"
        .. " the intro.")
    Row("Pick my race's RestedXP route", Sw("guide"))
    Row("RestedXP window positions", S.Switch(L.c, function() return o().rxpFrames ~= false end,
        function(on) o().rxpFrames = on Recount() end),
        "Places RestedXP's guide window, arrow, and item and target buttons where they were on the"
        .. " character the interface was saved on.")
    Row("Stop automatic spell placement", Sw("noAutoPush"), "Stops Blizzard from putting new spells on the first empty button, which creates duplicates on"
        .. " planned bars.")

    -- ------------------------------------------------------------------ New characters
    Page("new")
    Section("New characters and levelling", nil, { icon = 132307 })
    Row("Place spells as I learn them", Sw("swap"), "Replaces a placeholder with the real spell, or fills the spell's planned button.")
    Row("Setup window on new characters", Sw("popup"))
    Row("Skip the intro cinematic", Sw("skipIntro"), "Cancels the cinematic when a level 1 character first logs in.")
    L.Break()
    L.c:SetHeight(-L.y + 20)
    ShowTab(setup.tab or "profiles")
end

local function RefreshSetup()
    local YS = YR.Setup
    local view = ViewClass()
    local p = YS:Profile(view)
    local _, class = UnitClass("player")
    local name = CLASS_NAME[view] or view
    local profile = view == class and YS.LayoutName() or YS.LayoutNames(view)[1]
    setup.saved:SetText(p and ("%s profile |cffffffff%s|r  |cff8a827a%s|r"):format(name, profile, YS:Describe(p))
        or ("%s profile |cffffffff%s|r  |cff8a827aempty|r"):format(name, profile))
    -- Copy and Set up act on this character, so only while its own class is shown
    setup.Pending()
    setup.apply:SetEnabled(p ~= nil and view == class)
    setup.copy:SetEnabled(view == class)
    setup.plan:SetEnabled(view == class)
    setup.apply.tip = view ~= class and ("This character is not a " .. name .. ". Pick its class on the Profiles tab")
        or "Puts the profile's bars on this character, using the settings on the Bars tab. Asks first if the character was set up before"

    for _, ctl in ipairs(setup.controls) do if ctl.Refresh then ctl:Refresh() end end
end

-- ---------------------------------------------------------------------------
-- Settings, Trainer: the auto trainer (Trainer.lua) and, for this character's class, what it learns
-- ---------------------------------------------------------------------------
local trainer = { controls = {} }
local TRAIN_TO = 30          -- the spells listed: up to Forever's level cap

local function ChoiceLabel(v)
    for _, c in ipairs(YR.TRAINER_CHOICES) do if c[1] == v then return c[2] end end
end

local function BuildTrainer(page)
    local L = RowPage(page, trainer.controls, 64)
    local c = L.c
    local Section, Row = L.Section, L.Row
    Section("Class trainer", "spells learned as the trainer opens", { icon = 133741 })
    Row("Auto-train", S.Switch(c, function() return YR.Option("autoTrain") end,
        function(on) YippRouteDB.autoTrain = on YR:SyncRxpTrainer() end),
        "Buys your class's spells the moment you open your class trainer: every spell below that isn't set to"
        .. " Never, as far as your gold goes above Silver to keep. It is on for every character of the account,"
        .. " while the choices and the amount to keep are each class's - so it asks the first time on each"
        .. " character. Weapon skills, riding and professions are never bought. Hold Shift as you open the"
        .. " trainer to do it yourself. RestedXP's trainer automation is turned off while this is on.")
    local reserve = S.Stepper(c, function() return math.floor((YR.TrainerData().reserve or 0) / 100) end,
        function(v) YR.TrainerData().reserve = v * 100 end, 0, 100000, 1, 120)
    Row("Silver to keep", reserve, "Spells set to \"If I can afford it\" are only learned while you keep at least this much. \"Always\""
        .. " spells are learned whenever you have the gold. It starts at 2 silver and is this class's alone: set it on"
        .. " every class you play (saving for a mount: put the whole sum here). Shift-click changes it by ten.")
    local _, class = UnitClass("player")
    -- What the class trainer teaches (Data/TrainerSpells.lua: every rank, by level), one row a spell, at
    -- the level of the first rank a trainer has for it. Sinister Strike is here at 6: you start with
    -- rank 1, and rank 2 is the first one you pay for. A talent's own ranks are not a trainer's.
    local levels, ranks = {}, {}
    local race = YR.RaceBit and YR.RaceBit() or 0
    for _, e in ipairs((YR.TrainerSpells or {})[class] or {}) do
        local name, lvl = e[3], e[2]
        if lvl <= TRAIN_TO and not name:find("%(Passive") and not name:find("%(DND%)") and (e[5] == 0 or race == 0 or bit.band(e[5], race) ~= 0) then
            if not levels[name] or lvl < levels[name] then levels[name] = lvl end
            ranks[name] = (ranks[name] or 0) + 1
        end
    end
    local list, names = {}, {}
    for name, lvl in pairs(levels) do list[#list + 1] = { name, lvl } end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
    for _, e in ipairs(list) do names[#names + 1] = e[1] end

    L.Sub("Set several at once")
    trainer.upTo = trainer.upTo or 10
    local upTo = S.Stepper(c, function() return trainer.upTo end, function(v) trainer.upTo = v end, 2, TRAIN_TO, 1, 110)
    Row("Always up to level", upTo, "The level used by the button below: every spell first learned at or below it is set to Always.")
    local always = S.Button(c, "Set to Always", function()
        YR.SetTrainerChoices(names, "always", nil, levels, trainer.upTo)
        trainer.refresh()
    end, "primary", 130)
    Row("Set spells up to that level", always)
    -- every spell to one choice: Always, If I can afford it, or Never. It shows what they all are now,
    -- or "Mixed" when they differ.
    local every
    every = S.Dropdown(c, 170, YR.TRAINER_CHOICES, function(v)
        YR.SetTrainerChoices(names, v)
        trainer.refresh()
    end)
    function every:Refresh()
        local first, mixed
        for _, name in ipairs(names) do
            local choice = YR.TrainerChoice(name)
            if first == nil then first = choice elseif choice ~= first then mixed = true break end
        end
        self:SetValue(mixed and "Mixed" or first and ChoiceLabel(first) or "")
    end
    Row("All spells", every, "Sets the whole list at once. If I can afford it: learned while you keep your reserve. First rank only:"
        .. " the spell is learned, its later ranks are not. Never:"
        .. " nothing is learned until you change a spell.")
    Section(("Spells: %s"):format(UnitClass("player") or class), "what the trainer teaches, from the first rank you pay for",
        { icon = 133742 })
    local icons = (YR.PlannerSpells or {})[class] or {}
    for _, e in ipairs(list) do
        local name, lvl = e[1], e[2]
        -- the spell's icon from the spell data, so spells not learned yet have theirs too
        local d = icons[name]
        local icon = d and d[2] or (C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(name))
        local dd = S.Dropdown(c, 150, YR.TRAINER_CHOICES, function(v)
            YR.SetTrainerChoice(name, v)
            trainer.refresh()
        end)
        function dd:Refresh() self:SetValue(ChoiceLabel(YR.TrainerChoice(name))) end
        Row(("%d  %s%s%s"):format(lvl, icon and ("|T" .. icon .. ":18:18:0:0:64:64:5:59:5:59|t ") or "", name,
            ranks[name] > 1 and ("  |cff8a827a%d ranks|r"):format(ranks[name]) or ""), dd)
    end
    L.Break()
    c:SetHeight(-L.y + 40)
end

function trainer.refresh()
    for _, ctl in ipairs(trainer.controls) do if ctl.Refresh then ctl:Refresh() end end
end

-- ---------------------------------------------------------------------------
-- Settings: QoL - the things that help on any character, route or not
-- ---------------------------------------------------------------------------

-- One page per kind of thing, so none of them is a wall of switches. Each keeps its own list of
-- controls to refresh.
local qolPages = {}
local function QoLPage(key, build)   -- (TOP_CARD: the card of switches every page begins with)
    qolPages[key] = { controls = {} }
    return function(page)
        local L = RowPage(page, qolPages[key].controls, key == "instances" and 94 or 64, key)
        qolPages[key].L = L
        local c = L.c
        local Section, Row = L.Section, L.Row
        -- what you set, also while the main switch has it all off (it comes back as you left it)
        local function Opt(k) return function() return YR.OptionSet(k) end end
        build(L, c, Section, Row, Opt)
        if key ~= "gear" and key ~= "trinkets" then     -- those two end with a list of their own
            L.Break()
            L.Length(-L.y + 40)
        end
        -- features that are off: their cards under the ones that are on, now and at every refresh
        L.Break()
        L.Reflow()
        local controls = qolPages[key].controls
        controls[#controls + 1] = { Refresh = L.Reflow }
    end
end

local BuildCamps = QoLPage("camps", function(L, c, Section, Row, Opt)
        Section("Camp icon", "lit near a camp, or while its buff runs", { find = "campfire", icon = 135805, master = { Opt("camp"), YR.SetCampIcon } })
        Row("Show the camp's buffs", S.Switch(c, Opt("campList"), YR.SetCampList),
            "Lists the stat the camp gives and its shorter buffs with their time left. Buffs can't be read in"
            .. " combat, so the list dims and shows what it last saw.")
        Row("Always show", S.Switch(c, Opt("campAlways"), YR.SetCampAlways),
            "Keeps a grey icon on screen away from camps. Off: the icon only shows near a camp or while its"
            .. " buff runs.")
        Row("Lock position", S.Switch(c, Opt("campLocked"), YR.SetCampLocked),
            "Turn off to drag the icon. A preview with a coloured edge shows while it is unlocked. Also"
            .. " /headstart camp unlock.")

        Section("Flight timer", "time left while you fly", { icon = 132239,
            master = { Opt("flightTimer"), function(on) YippRouteDB.flightTimer = on YR:SetFlightTimer(on) end } })
        Row("Portrait marker", S.Switch(c, Opt("flightFace"), function(on)
            YippRouteDB.flightFace = on
            if YR.FlightFace then YR.FlightFace() end
        end), "Marks your position on the bar with your character's portrait. Off: a lit dot.")
        Row("About the timer", S.Text(c, 12, S.C.muted),
            "Shows where you fly from and to, and the time left. A flight is timed the first time you take"
            .. " it. Before that the bar uses RestedXP's time or an estimate. Drag the bar to move it."
            .. " /headstart flight shows a sample.")
end)

local BuildBags = QoLPage("bags", function(L, c, Section, Row, Opt)
        Section("Bank deposit", "hold Shift at the bank to skip it", { find = "auto bank mats", icon = 133639 })
        Row("Deposit when the bank opens", S.Switch(c, Opt("bankAuto"), function(on) YippRouteDB.bankAuto = on end),
            "Moves the items chosen below from your bags to the bank, and lists them in chat. Quest items,"
            .. " items for quests you can still do, and AutoFeed's food and water always stay. Stops when the"
            .. " bank is full.")
        local MATS = { { "mine", "Not for my professions" }, { "all", "All of them" }, { "off", "None" } }
        local mats
        mats = S.Dropdown(c, 190, MATS, function(v) YippRouteDB.bankMats = v mats:Refresh() end)
        function mats:Refresh()
            for _, o in ipairs(MATS) do if o[1] == YR.BankMats() then self:SetValue(o[2]) end end
        end
        Row("Crafting mats", mats, "Which crafting materials to deposit. \"Not for my professions\" keeps what your own professions"
            .. " use: ore for a miner, linen for a tailor. Items you use rather than craft with, like dynamite,"
            .. " always stay.")
        Row("Recipes I can't learn yet", S.Switch(c, Opt("bankRecipes"), function(on) YippRouteDB.bankRecipes = on end),
            "Deposits recipes for a profession you don't have, or that need more skill. A recipe you can"
            .. " learn now stays in your bags.")
        Row("Bank window button", S.Switch(c, Opt("bankButton"), YR.SetBankButton),
            "Adds a \"Bank mats\" button under the bank window to deposit on a click (where a bag addon hides"
            .. " the bank window, it stands at the top of the screen while the bank is open). Off until you turn it"
            .. " on. Also /headstart bank.")

        Section("Mail to alt", "mats and recipes sent to another character", { icon = 133471 })
        local alt = CreateFrame("Frame", nil, c)
        alt:SetSize(190, 24)
        alt.input = S.Input(alt, { width = 190, placeholder = "Name Surname", onCommit = function(t)
            local full = YR.SetMailRecipient(t)
            local bare = YR.MailRecipientMissingSurname()
            if bare then
                YR.Print(("mail on Forever needs the full name: %s's surname too, as the character shows it."):format(bare))
            elseif full then
                YR.Print("mail goes to " .. full .. ".")
            end
            YR:RefreshWindow()
        end })
        alt.input:SetPoint("RIGHT")
        function alt:Refresh()
            if not self.input:HasFocus() then
                self.input:SetText(YR.MailRecipient() or YR.MailRecipientMissingSurname() or "")
            end
        end
        Row("Recipient", alt, "The character to mail to, on this realm and faction. Forever needs the full name: name and"
            .. " surname. Type only the name and Headstart adds the surname if it knows the character. Nothing"
            .. " is sent while you play the recipient.")
        Row("Send when the mailbox opens", S.Switch(c, function() return YippRouteDB.mailAuto == true end,
            function(on) YippRouteDB.mailAuto = on end),
            "Sends as soon as you open a mailbox, without asking, from every character on this realm except the"
            .. " recipient. Check the name: mail to a wrong name is gone. Hold Shift as you open the mailbox to"
            .. " skip it. Off: only when you click the button on the mail window, or use /headstart mail. You pay"
            .. " the game's postage for each stack.")
        local MMATS = { { "mine", "Not for my professions" }, { "all", "All of them" }, { "off", "None" } }
        local mmats
        mmats = S.Dropdown(c, 190, MMATS, function(v) YippRouteDB.mailMats = v mmats:Refresh() end)
        function mmats:Refresh()
            for _, o in ipairs(MMATS) do if o[1] == YR.MailMats() then self:SetValue(o[2]) end end
        end
        Row("Crafting mats", mmats, "Which crafting materials to send. Works like the bank setting.")
        Row("Recipes I can't learn yet", S.Switch(c, Opt("mailRecipes"), function(on) YippRouteDB.mailRecipes = on end))
        local mlist = CreateFrame("Frame", nil, c)
        mlist:SetSize(200, 24)
        local minput = S.Input(mlist, { width = 200, placeholder = "Shift-click an item to add it", onCommit = function(t)
            local item = YR.ItemFromText(t)
            if item then
                YR.SetMailCustom(item, not (YippRouteDB.mailCustom and YippRouteDB.mailCustom[item]))
                YR:RefreshWindow()
            end
            mlist.input:SetText("")
        end })
        minput:SetPoint("RIGHT")
        mlist.input = minput
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if minput:HasFocus() and IsShiftKeyDown() and link then minput:SetText(link) minput:ClearFocus() end
        end)
        Row("Always send", mlist, "Other items to send every time. Shift-click an item into the box. Add the same item again to"
            .. " remove it.")
        local mshow = CreateFrame("Frame", nil, c)
        mshow:SetSize(300, 24)
        mshow.text = S.Text(mshow, 12, S.C.muted)
        mshow.text:SetPoint("RIGHT")
        mshow.text:SetJustifyH("RIGHT")
        mshow.text:SetWidth(300)
        function mshow:Refresh()
            local parts = {}
            for item in pairs(YippRouteDB.mailCustom or {}) do
                parts[#parts + 1] = C_Item.GetItemNameByID and C_Item.GetItemNameByID(item) or ("item " .. item)
            end
            table.sort(parts)
            self.text:SetText(#parts > 0 and table.concat(parts, ", ") or "nothing yet")
        end
        Row("Always-send list", mshow)
        Row("Mail window button", S.Switch(c, Opt("mailButton"), YR.SetMailButton),
            "Adds a \"Send to <alt>\" button under the mail window. Off until you turn it on.")

end)

local BuildAlts = QoLPage("alts", function(L, c, Section, Row, Opt)
        Section("Characters", "bags, bank and gold of your other characters", { icon = 133785, find = "alts altoholic gold",
            master = { Opt("alts"), function(on) YippRouteDB.alts = on end } })
        Row("Characters window", S.Button(c, "Open", function() YR.AltsToggle() end, nil, 90),
            "Shows each character's level, gold and last login. Pick one to see its bags and bank, or search"
            .. " all of them for an item. Also on the bag button, a key binding, the minimap button's"
            .. " right-click menu, and /headstart alts. A character is recorded when you play it with this on,"
            .. " and its bank when you open it. Soulbound items, quest items and the hearthstone are left out.")
        Row("Bag button", S.Switch(c, function() return YippRouteDB.altsBagButton ~= false end, function(on)
            YippRouteDB.altsBagButton = on
            YR.AltsBagButtons()
        end), "Adds a small round mark at the left of the money on your bag. Hover it for every character's gold, click it for"
            .. " the Characters window.")
        Row("Include food, drink and grey items", S.Switch(c, function() return YippRouteDB.altsAll == true end,
            function(on) YippRouteDB.altsAll = on end), "Shows food, drink and grey items in the window and in tooltips. Off by default: they are mostly"
            .. " clutter.")
        Row("Item tooltips", S.Switch(c, function() return YippRouteDB.altsTooltip ~= false end,
            function(on) YippRouteDB.altsTooltip = on end), "Adds a line to item tooltips with the other characters that have the item: \"Duplo: 4x, bank"
            .. " 12x\".")
        Row("Gold tooltip", S.Switch(c, function() return YippRouteDB.altsGold ~= false end,
            function(on) YippRouteDB.altsGold = on end),
            "Hover the coins on your bag to see every character's gold and the total. /headstart gold prints"
            .. " it in chat.")
        StaticPopupDialogs["HEADSTART_FORGET_ALTS"] = {
            text = "Headstart: delete everything recorded about your characters?\n\nEach is recorded again the next time you play it.",
            button1 = "Forget", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true,
            OnAccept = function() YR.AltsForget() end,
        }
        Row("Forget all characters", S.Button(c, "Forget", function() StaticPopup_Show("HEADSTART_FORGET_ALTS") end, nil, 90),
            "Deletes everything recorded about your characters. Asks first. To forget one character, use"
            .. " Forget in the Characters window.")
end)

local BuildVendors = QoLPage("vendors", function(L, c, Section, Row, Opt)
        Section("Restock", "hold Shift at a vendor to skip it", { find = "vendor buy reagents ammo", icon = 133785,
            master = { Opt("restock"), function(on) YippRouteDB.restock = on end } })
        Row("Gold to keep", S.Stepper(c, function() return YippRouteDB.restockReserve or 0 end,
            function(v) YippRouteDB.restockReserve = v end, 0, 1000, 1, 110),
            "Restock never spends below this amount. It is 0 until you set it, and counts for every character.")
        if YR.RestockShoots() then
            Row("Ammo to keep", S.Stepper(c, function() return YR.RestockAmmo() end,
                function(v) YR.SetRestockAmmo(v) end, 0, 4000, 100, 110),
                "Buys the best arrows or bullets you can use for your ranged weapon, or more of your throwing"
                .. " weapon. Each class has its own number. 0: buy none.")
        end
        for _, r in ipairs(YR.RestockReagents()) do
            local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(r.item)
            if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(r.item) end
            Row(name or ("Reagent for " .. r.why), S.Stepper(c, function() return YR.RestockCount(r.item, r.default) end,
                function(v) YR.SetRestockCount(r.item, v) end, 0, 200, 1, 110),
                ("For %s. Bought only while you know it%s. 0: never"):format(r.why,
                    #r.spells > 1 and " (of several ranks, only the top one you know)" or ""))
        end
        local custom = CreateFrame("Frame", nil, c)
        custom:SetSize(200, 24)
        local input = S.Input(custom, { width = 200, placeholder = "Shift-click an item, then a count",
            onCommit = function(t)
                local item = YR.ItemFromText(t)
                local count = tonumber((t:gsub("|H.-|h.-|h", "")):match("(%d+)%s*$"))
                if item and count and count ~= item then
                    YR.SetRestockCustom(item, count)
                    YR:RefreshWindow()
                end
            end })
        input:SetPoint("RIGHT")
        custom.input = input
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if input:HasFocus() and IsShiftKeyDown() and link then input:Insert(link .. " ") end
        end)
        Row("Add an item", custom, "Shift-click an item into the box (or type its ID), then the number to keep, then Enter. Enter"
            .. " the same item with 0 to remove it.")
        local list = CreateFrame("Frame", nil, c)
        list:SetSize(300, 24)
        list.text = S.Text(list, 12, S.C.muted)
        list.text:SetPoint("RIGHT")
        list.text:SetJustifyH("RIGHT")
        list.text:SetWidth(300)
        function list:Refresh()
            local parts = {}
            for item, n in pairs(YippRouteDB.restockCustom or {}) do
                parts[#parts + 1] = ("%s %d"):format(C_Item.GetItemNameByID and C_Item.GetItemNameByID(item) or ("item " .. item), n)
            end
            table.sort(parts)
            self.text:SetText(#parts > 0 and table.concat(parts, ", ") or "nothing yet")
        end
        Row("Your list", list)
end)

local BuildGroup = QoLPage("group", function(L, c, Section, Row, Opt)
        Section("Quest sharing", "share your quests, accept your party's", { find = "party quests auto accept", icon = 134327 })
        Row("Share quests I accept", S.Switch(c, function() return YippRouteDB.shareAll == true end,
            function(on) YippRouteDB.shareAll = on end),
            "Shares every quest you accept from an NPC with your party. Off: only quests from a route are"
            .. " shared (Route settings, Group play).")
        local FROM = { { "friends", "Guildies and friends" }, { "party", "Anyone in my party" }, { "off", "Nobody" } }
        local from
        from = S.Dropdown(c, 190, FROM, function(v) YippRouteDB.acceptFrom = v from:Refresh() end)
        function from:Refresh()
            for _, o in ipairs(FROM) do if o[1] == YR.AcceptFromSet() then self:SetValue(o[2]) end end
        end
        Row("Accept shared quests from", from, "Accepts quests and escorts shared by these players. Hold Shift as the quest opens to decide"
            .. " yourself. Leatrix Plus's \"Block shared quests\" declines them before Headstart can.")

        Section("Invites", "invite, leave and accept in one click", { find = "quick group invite leave", icon = 134149 })
        Row("Invite and Leave buttons", S.Switch(c, Opt("groupBar"), YR.SetGroupBar),
            "Shows a small bar with two buttons: Invite your target, and Leave group. Both have key bindings"
            .. " (Key Bindings, AddOns, Headstart), and /headstart inv and /headstart leave.")
        Row("Lock position", S.Switch(c, Opt("groupBarLocked"), YR.SetGroupBarLocked),
            "Turn off to drag the bar.")
        local WHO = { { "friends", "Guildies and friends" }, { "anyone", "Anyone" }, { "off", "Nobody" } }
        local function WhoDrop(key, get)
            local d
            d = S.Dropdown(c, 190, WHO, function(v) YippRouteDB[key] = v d:Refresh() end)
            function d:Refresh() for _, o in ipairs(WHO) do if o[1] == get() then self:SetValue(o[2]) end end end
            return d
        end
        Row("Invite on whisper", WhoDrop("whisperInvite", YR.WhisperInviteSet),
            "Invites these players when they whisper you the keyword. Only while you are solo or lead a group"
            .. " with room.")
        local word = CreateFrame("Frame", nil, c)
        word:SetSize(110, 24)
        word.input = S.Input(word, { width = 110, placeholder = "inv", onCommit = function(t)
            YippRouteDB.whisperWord = strtrim(t or "") ~= "" and strtrim(t) or nil
        end })
        word.input:SetPoint("RIGHT")
        function word:Refresh() if not self.input:HasFocus() then self.input:SetText(YippRouteDB.whisperWord or "") end end
        Row("Keyword", word, "The whole whisper must be this word. Upper or lower case doesn't matter. Default: \"inv\".")
        Row("Accept invites from", WhoDrop("acceptInvites", YR.AcceptInvitesSet),
            "Accepts group invites from these players at once. Hold Shift as the invite arrives to decide"
            .. " yourself.")

        if not YR.QuestLFGAvailable then return end         -- (shelved: QuestLFG.lua)
        Section("Quest group finder", "ask chat for a group, see who answers", { find = "lfg looking for group", icon = 133884,
            master = { Opt("questLFG"), function(on) YippRouteDB.questLFG = on end } })
        Row("Group finder window", S.Button(c, "Open", function() YR.QuestLFGToggle() end, nil, 90),
            "Lists your quests, group quests first. Click Ask to post one request in chat; nothing is ever"
            .. " sent without your click. Players who name the quest in chat or whisper you are listed with"
            .. " Invite and Whisper buttons. Also opens from the eye left of the quest tracker (Shift-drag moves"
            .. " it) and /headstart lfg.")
        local chan
        chan = S.Dropdown(c, 220, YR.QuestLFGChannels, function(v)
            YippRouteDB.questLFGChannel = v or nil
            chan:Refresh()
        end)
        function chan:Refresh()
            local id, name = YR.QuestLFGChannel()
            self:SetValue(YippRouteDB.questLFGChannel and name == YippRouteDB.questLFGChannel and (id .. ". " .. name)
                or (id and ("Automatic (" .. id .. ". " .. name .. ")") or "Automatic"))
        end
        Row("Channel", chan, "The chat channel your request is posted in. Automatic: LookingForGroup if you are in it,"
            .. " otherwise channel 2, otherwise your first channel.")
        local words = S.Input(c, { width = 220, placeholder = "LFG {quest}", onCommit = function(t)
            t = strtrim(t or "")
            YippRouteDB.questLFGText = t ~= "" and t or nil
        end })
        function words:Refresh() if not self:HasFocus() then self:SetValue(YippRouteDB.questLFGText or "") end end
        Row("Message", words, "The text that is posted. {quest} is the quest's name and must be included; {level} is its level."
            .. " Default: \"LFG {quest}\".")
        Row("Watch for others", S.Switch(c, function() return YippRouteDB.questLFGWatch ~= false end,
            function(on) YippRouteDB.questLFGWatch = on end),
            "Lists players who name one of your quests in chat, and tells you in one chat line. Off: chat is"
            .. " only read while your own request is up.")
        Row("Reset the eye's position", S.Button(c, "Reset", function() YR.QuestLFGResetPosition() end, nil, 90),
            "Moves the eye back to the left of the quest tracker.")
end)

local BuildReminders = QoLPage("reminders", function(L, c, Section, Row, Opt)
        Section("Reminders", "said when something needs doing", { find = "ding level up trainer talents repair", icon = 134376 })
        Row("Trainer reminder", S.Switch(c, Opt("remindTrainer"), function(on) YippRouteDB.remindTrainer = on end),
            "Tells you when you level, and at login, which spells your class trainer has for you and roughly"
            .. " what they cost. Prices are remembered from your trainer visits (/headstart trainer).")
        Row("Level-up stats in chat", S.Switch(c, Opt("levelUpStats"), function(on) YippRouteDB.levelUpStats = on end),
            "Prints what you gained when you level, as Classic did: \"You have gained 19 hit points. Your"
            .. " Strength increases by 1.\"")
        Row("Unspent talent points", S.Switch(c, Opt("remindTalents"), function(on)
            YippRouteDB.remindTalents = on
            YR.TalentNotice()
        end), "Tells you while you have talent points to spend: a small icon and a line of words near the top of the"
            .. " screen, out of a fight, gone when the last point is spent. Click it to put it away until your next level.")
        local SHOWN = { { "both", "An icon and words on screen" }, { "text", "Words on screen" }, { "icon", "An icon on screen" },
            { "chat", "A line in chat" } }
        local shown
        shown = S.Dropdown(c, 190, SHOWN, function(v)
            if v == "both" then YippRouteDB.talentNotice = nil else YippRouteDB.talentNotice = v end
            shown:Refresh()
            YR.TalentNotice()
        end)
        function shown:Refresh()
            for _, o in ipairs(SHOWN) do if o[1] == YR.TalentNoticeMode() then self:SetValue(o[2]) end end
        end
        Row("Talent points shown as", shown, "On screen it stays while there are points to spend, and moves in Arrange (/hs move)."
            .. " A line in chat is said once, at the login and when you level.")
        Row("Durability warning", S.Switch(c, Opt("durability"), function(on) YippRouteDB.durability = on end),
            "Warns once when your most damaged item drops below the first number, and again when you enter a"
            .. " town or inn below the second.")
        Row("Warn below (percent)", S.Stepper(c, function() return YippRouteDB.durWarn or 25 end,
            function(v) YippRouteDB.durWarn = v end, 5, 95, 5, 110))
        Row("In town, remind below (percent)", S.Stepper(c, function() return YippRouteDB.durTown or 50 end,
            function(v) YippRouteDB.durTown = v end, 5, 100, 5, 110))
        Section("Craftable items", "you know the recipe and carry the mats", { find = "craft make sharpening stones oil bandages", icon = 133685,
            master = { Opt("craftRemind"), function(on) YippRouteDB.craftRemind = on end } })
        Row("About craftable items", S.Text(c, 12, S.C.muted),
            "Tells you in chat when you know a recipe, carry the mats, and have none of the item. Once, and"
            .. " again after you run out.")
        Row("  Sharpening stones and weightstones", S.Switch(c, Opt("craftStones"), function(on) YippRouteDB.craftStones = on end),
            "Blacksmithing. Only the kind your weapon takes: stones for blades, weights for blunt weapons.")
        Row("  Wizard and mana oil", S.Switch(c, Opt("craftOils"), function(on) YippRouteDB.craftOils = on end), "Enchanting.")
        Row("  Bandages", S.Switch(c, Opt("craftBandages"), function(on) YippRouteDB.craftBandages = on end), "First Aid.")
        Row("  Remind when I have fewer than", S.Stepper(c, function() return YippRouteDB.craftBelow or 1 end,
            function(v) YippRouteDB.craftBelow = v end, 1, 100, 1, 110), "1: only when you have none.")
        Section("Level-up screenshot", nil, { find = "ding screenshots", icon = 134441 })
        Row("Screenshot on level-up", S.Switch(c, Opt("levelShot"), function(on) YippRouteDB.levelShot = on end),
            "Takes a screenshot a moment after you level, so the animation is in it. Saved in your"
            .. " Screenshots folder.")
end)

local BuildRecap = QoLPage("recap", function(L, c, Section, Row, Opt)
        Section("Death recap", "what killed you, under the Release button", { icon = 237274, find = "die died death killed",
            master = { Opt("deathRecap"), function(on) YippRouteDB.deathRecap = on YR.RecapApply() end } })
        Row("About the recap", S.Text(c, 12, S.C.muted),
            "Shows the killing blow at the top: icon, name, source and amount. Below it are your last events"
            .. " as bars sized by damage, with crits and crushing blows marked, and the damage you took this"
            .. " fight by spell. Sources are filled in by the game after the fight. Nothing is shown during"
            .. " combat. Where the game hides the numbers, which it may do in instances and battlegrounds, the"
            .. " recap says how many hits were hidden.")
        Row("Events shown", S.Stepper(c, function() return math.max(3, math.min(12, tonumber(YippRouteDB.deathRows) or 8)) end,
            function(v) YippRouteDB.deathRows = v end, 3, 12, 1, 110), "How many of your last events the recap lists.")
        Row("Killing blow in chat", S.Switch(c, function() return YippRouteDB.deathChat == true end,
            function(on) YippRouteDB.deathChat = on end), "Also prints the killing blow as one chat line. Only you see it.")
        local last = S.Button(c, "Open", function()
            if not YR.RecapShow() then YR.Print("no death recorded for this character yet.") end
        end, nil, 90)
        Row("Last death", last, "Opens the recap of this character's last death. Also /headstart death.")
        Row("Preview", S.Button(c, "Preview", function() YR.RecapSample() end, nil, 90),
            "Shows the recap with sample data.")
end)

local BuildLoot = QoLPage("loot", function(L, c, Section, Row, Opt)
        local function Sw(key)
            return S.Switch(c, function() return YippRouteDB[key] ~= false end, function(on) YippRouteDB[key] = on end)
        end
        Section("Loot feed", "recent loot, in lines that fade", { icon = 133784,
            master = { Opt("lootFeed"), function(on) YippRouteDB.lootFeed = on YR.LootFeedApply() end } })
        local LOOKS = { { "lines", "Lines" }, { "cards", "Cards" } }
        local look
        look = S.Dropdown(c, 180, LOOKS, function(v)
            YippRouteDB.lootStyle = v == "cards" and "cards" or nil
            YR.LootFeedApply()
            look:Refresh()
        end)
        function look:Refresh() self:SetValue(YippRouteDB.lootStyle == "cards" and "Cards" or "Lines") end
        Row("Look", look, "Lines: plain text with a small icon. Cards: each line on a dark plate with a bigger icon.")
        Row("Vendor price", S.Switch(c, function()
            if YippRouteDB.lootPrice == nil then return YippRouteDB.lootStyle == "cards" end
            return YippRouteDB.lootPrice == true
        end, function(on)
            YippRouteDB.lootPrice = on
            YR.LootFeedApply()
        end), "Shows what the item sells for to a vendor at the right of its line, for the whole stack.")
        Row("Items", Sw("lootItems"), "Shows looted items with icon and name in their quality colour. The same item looted again adds"
            .. " to the count on its line.")
        local QUALITY = { { 0, "Everything" }, { 1, "Common (white) and better" }, { 2, "Uncommon (green) and better" },
            { 3, "Rare (blue) and better" } }
        local quality
        quality = S.Dropdown(c, 220, QUALITY, function(v)
            YippRouteDB.lootQuality = v > 0 and v or nil
            quality:Refresh()
        end)
        function quality:Refresh()
            local now = tonumber(YippRouteDB.lootQuality) or 0
            for _, o in ipairs(QUALITY) do if o[1] == now then self:SetValue(o[2]) end end
        end
        Row("  Lowest quality shown", quality, "Items below this are hidden from the feed. They are still in the loot log.")
        Row("Looted money", Sw("lootMoney"), "Shows looted money, and your share in a group.")
        Row("Experience", Sw("lootXP"), "Shows experience gained. Kills in a row add up on one line.")
        Row("Reputation", Sw("lootRep"))
        Row("Seconds on screen", S.Stepper(c, function() return math.max(2, math.min(15, tonumber(YippRouteDB.lootSeconds) or 4)) end,
            function(v) YippRouteDB.lootSeconds = v end, 2, 15, 1, 110))
        Row("Lock position", S.Switch(c, function() return YippRouteDB.lootLock ~= false end, function(on)
            YippRouteDB.lootLock = on
            YR.LootFeedApply()
        end), "Turn off to drag the feed. Its area is outlined while it is unlocked.")
        Row("Preview", S.Button(c, "Sample", function()
            if not YR.LootFeedSample() then YR.Print("turn the loot feed on first.") end
        end, nil, 90), "Shows a few sample lines on the feed.")
        Row("Reset position", S.Button(c, "Reset", function() YR.LootFeedResetPosition() end, nil, 90))

        Section("Loot log", "everything looted, and session totals", { find = "gold per hour session", icon = 133785 })
        Row("Loot log", S.Button(c, "Open", function() YR.LootLogToggle() end, nil, 90),
            "Opens the log of every item and reputation gain with its time. It also shows this session's"
            .. " totals and hourly rates for money, vendor value and experience. Recorded while the loot feed is"
            .. " on. Also /headstart loot.")
        local count = S.Text(c, 12, S.C.sub)
        function count:Refresh() self:SetText(("%d entries"):format(YR.LootLogCount())) end
        Row("Entries kept", count, "The newest 800 entries, per character.")
        StaticPopupDialogs["HEADSTART_CLEAR_LOOTLOG"] = {
            text = "Headstart: clear this character's loot log?",
            button1 = "Clear",
            button2 = "Cancel",
            OnAccept = function() YR.LootLogClear() YR:RefreshWindow() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        Row("Clear the log", S.Button(c, "Empty", function() StaticPopup_Show("HEADSTART_CLEAR_LOOTLOG") end, nil, 90), "Deletes every entry for this character. Asks first.")
end)

local BuildGear = QoLPage("gear", function(L, c, Section, Row, Opt)
        Section("Upgrade estimate", "DPS and toughness change on item tooltips", { find = "gear sim tooltip", icon = 132739,
            master = { Opt("simTooltip"), function(on) YippRouteDB.simTooltip = on end } })
        Row("About the estimate", S.Text(c, 12, S.C.muted),
            "Adds a line to gear tooltips with what the item would change for you: \"+4.2% DPS, +1.0%"
            .. " toughness\". Worked out from your own stats with the item swapped in. It is a levelling"
            .. " estimate: set bonuses, on-hit effects and trinkets are not counted.")
        local ROLES = { { "guess", "Guess from my talents" }, { "melee", "Melee damage" }, { "ranged", "Ranged damage" },
            { "caster", "Spell damage" }, { "healer", "Healing" }, { "tank", "Tanking" } }
        local roleDrop
        roleDrop = S.Dropdown(c, 200, ROLES, function(v)
            YippRouteDB.simRole = v ~= "guess" and v or nil
            if YR.UpgradesForget then YR.UpgradesForget() end
            roleDrop:Refresh()
        end)
        function roleDrop:Refresh()
            local cur = YippRouteDB.simRole or "guess"
            for _, r in ipairs(ROLES) do if r[1] == cur then self:SetValue(r[2]) end end
        end
        Row("Role", roleDrop, "The role items are rated for. Guess uses your talent tree with the most points, or your class's"
            .. " usual levelling role before you have talents.")
        Section("Upgrade alerts", "tells you when loot beats what you wear", { find = "better gear", icon = 133071,
            master = { Opt("upgrades"), function(on) YippRouteDB.upgrades = on end } })
        Row("About upgrade alerts", S.Text(c, 12, S.C.muted),
            "Tells you when an item in your bags rates better for your role than what you wear in that slot."
            .. " Only items you can equip. Once per item, and again after you level. /headstart upgrades checks"
            .. " now.")
        local QUAL = { { 1, "Grey and white" }, { 2, "Up to green" }, { 3, "Up to blue" }, { 5, "Everything" } }
        local qual
        qual = S.Dropdown(c, 170, QUAL, function(v) YippRouteDB.upgradeQuality = v YR.UpgradesForget() qual:Refresh() end)
        function qual:Refresh()
            for _, o in ipairs(QUAL) do if o[1] == (YippRouteDB.upgradeQuality or 2) then self:SetValue(o[2]) end end
        end
        Row("Highest quality", qual, "Items above this quality are not announced. Blues and better are usually worth judging yourself.")
        Row("Minimum gain (percent)", S.Stepper(c, function() return YippRouteDB.upgradeMin or 2 end,
            function(v) YippRouteDB.upgradeMin = v YR.UpgradesForget() end, 0, 100, 1, 110),
            "Applies when an item trades one thing for another, like less DPS for more armor. An item that is"
            .. " better with no loss, or fills an empty slot, is always announced.")
        Row("Equip window", S.Switch(c, Opt("upgradeButton"), function(on) YippRouteDB.upgradeButton = on end),
            "Shows a small window with an Equip button. Off: a chat line only.")

        BuildRewards(L)   -- last: its list of hand-picked rewards grows
end)

-- ---------------------------------------------------------------------------
-- Settings: a menu down the left, grouped, and one page at a time beside it under its own heading
-- ---------------------------------------------------------------------------
-- Trinkets & sets: the buttons, swap trinkets for me with its order, the swaps when mounted or
-- swimming, and the keys for the game's equipment sets. The order is a list of its own after the cards.
local trink = {}
local MAX_TRINKETS = 14

local function TrinketsHave()
    -- the order first (numbered), then the other trinkets you wear or carry
    local db, out, seen = YR.TrinketDB(), {}, {}
    for _, id in ipairs(db.order) do out[#out + 1] = { id = id, listed = true } seen[id] = true end
    local function Add(id)
        if id and not seen[id] then
            local _, _, _, loc = C_Item.GetItemInfoInstant(id)
            if loc == "INVTYPE_TRINKET" then out[#out + 1] = { id = id } seen[id] = true end
        end
    end
    Add(GetInventoryItemID("player", 13))
    Add(GetInventoryItemID("player", 14))
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do Add(C_Container.GetContainerItemID(bag, slot)) end
    end
    return out
end

local function RefreshTrinkets()
    if not trink.rows then return end
    local have = TrinketsHave()
    local n = 0
    for i, e in ipairs(have) do
        if i > MAX_TRINKETS then break end
        n = i
        local r = trink.rows[i]
        r.id = e.id
        r.num:SetText(e.listed and tostring(i) or "")
        r.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.id))
        local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(e.id)
        if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(e.id) end
        r.name:SetText(name or ("item " .. e.id))
        r.name:SetTextColor(unpack(e.listed and S.C.text or S.C.muted))
        r.up:SetShown(e.listed and i > 1)
        r.down:SetShown(e.listed and have[i + 1] ~= nil and have[i + 1].listed == true)
        r.toggle.text:SetText(e.listed and "Take off the list" or "Add to the list")
        r:Show()
    end
    for i = n + 1, #trink.rows do trink.rows[i]:Hide() end
    trink.none:SetShown(n == 0)
    if YR.TrinketPaint then YR.TrinketPaint() end
end

-- The trinket buttons as they will be, in the page: two buttons of our own (the real ones are secure,
-- and stand where you put them on screen) drawn from the same settings, and working - rest on one,
-- click it, pick from its list. Three states to look at: ready, on cooldown, and a swap waiting for
-- the fight to end.
local function TrinketPreview(c)
    local f = CreateFrame("Frame", nil, c)
    f:SetClipsChildren(true)
    S.Fill(f, S.C.field)
    f.state = "ready"
    f.chips = {}
    local x = 12
    for _, st in ipairs({ { "ready", "Ready" }, { "cooldown", "On cooldown" }, { "queued", "Swap waiting" } }) do
        local chip = S.Chip(f, st[2], function()
            f.state = st[1]
            f:Refresh()
        end)
        chip:SetPoint("TOPLEFT", x, -10)
        chip.key = st[1]
        x = x + chip:GetWidth() + 6
        f.chips[#f.chips + 1] = chip
    end
    f.title = S.Text(f, 11, S.C.muted)
    f.title:SetPoint("TOPRIGHT", -12, -14)
    f.title:SetText("PREVIEW")
    f.hint = S.Text(f, 11, S.C.muted)
    f.hint:SetPoint("BOTTOMLEFT", 12, 10)
    f.hint:SetPoint("BOTTOMRIGHT", -12, 10)
    f.hint:SetJustifyH("LEFT")
    f.hint:SetWordWrap(false)
    f.holder = CreateFrame("Frame", nil, f)
    f.holder:SetPoint("CENTER", 0, -6)
    local SAMPLE = { "Interface\\Icons\\INV_Jewelry_Talisman_07", "Interface\\Icons\\INV_Misc_Bone_ElfSkull_01",
        "Interface\\Icons\\INV_Jewelry_Necklace_13", "Interface\\Icons\\INV_Misc_Food_54", "Interface\\Icons\\INV_Misc_Orb_05" }
    local function Say(text) f.said = text f.hint:SetText(text) end
    -- the list a button opens
    local fly = CreateFrame("Frame", nil, f)
    fly:SetFrameLevel(f:GetFrameLevel() + 6)
    fly:SetSize(16 + 3 * 40 - 4, 52)
    S.Fill(fly, S.C.window)
    S.Border(fly, S.C.lineHi)
    fly.items = {}
    for i = 1, 3 do
        local b = CreateFrame("Button", nil, fly)
        b:SetSize(36, 36)
        b:SetPoint("LEFT", 8 + (i - 1) * 40, 0)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon:SetTexture(SAMPLE[i + 2])
        b:SetScript("OnClick", function(self)
            -- as on screen: it goes on now - or, in the "swap waiting" state, shows in the corner until the fight ends
            local owner = fly.owner
            if f.state == "queued" then
                owner.queued:SetTexture(self.icon:GetTexture())
                owner.queued:Show()
                Say("In a fight the trinket waits in the corner, and goes on when the fight ends.")
            else
                local was = owner.icon:GetTexture()
                owner.icon:SetTexture(self.icon:GetTexture())
                self.icon:SetTexture(was)
                Say("Equipped (in the preview only).")
            end
            fly:Hide()
        end)
        fly.items[i] = b
    end
    fly:Hide()
    f.fly = fly
    local function Open(b)
        local look = YR.TrinketLook()
        if fly:IsShown() and fly.owner == b then fly:Hide() return end
        fly.owner = b
        YR.TrinketFlyPlace(fly, b, look.dir)
        fly.away = 0
        fly:SetScript("OnUpdate", look.hover and function(self, elapsed)
            if self:IsMouseOver() or b:IsMouseOver() then self.away = 0 return end
            self.away = self.away + elapsed
            if self.away > 0.35 then self:Hide() end
        end or nil)
        fly:Show()
    end
    f.buttons = {}
    for i, slot in ipairs({ 13, 14 }) do
        local b = CreateFrame("Button", nil, f.holder)
        S.Border(b, S.C.lineHi)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 1, -1)
        b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cd:SetAllPoints(b.icon)
        b.queued = b:CreateTexture(nil, "OVERLAY", nil, 2)
        b.queued:SetPoint("BOTTOMLEFT", 2, 2)
        b.queued:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.queued:Hide()
        b.slot = slot
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnEnter", function(self)
            local look = YR.TrinketLook()
            if look.hover and not (fly:IsShown() and fly.owner == self) then Open(self) end
            if not look.tips then return end
            GameTooltip:SetOwner(self, look.dir == "up" and "ANCHOR_BOTTOM" or "ANCHOR_TOP")
            if GetInventoryItemID("player", slot) then GameTooltip:SetInventoryItem("player", slot)
            else GameTooltip:AddLine(i == 1 and "Top trinket slot" or "Bottom trinket slot") end
            GameTooltip:AddLine(look.left == "list" and "Click: your other trinkets  ·  Right-click: use"
                or "Click: use  ·  Right-click: your other trinkets", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("OnClick", function(self, which)
            local look = YR.TrinketLook()
            local lists = (which == "LeftButton") == (look.left == "list")
            if lists then
                Open(self)
            else
                -- used: its cooldown starts, as it would
                self.used = GetTime()
                if self.cd.SetCooldown then self.cd:SetCooldown(self.used, 120) end
                Say("Used (in the preview only): the cooldown starts.")
            end
        end)
        f.buttons[i] = b
    end
    function f:Refresh()
        local look = YR.TrinketLook()
        local pitch = look.size + look.gap
        local long = 2 * pitch - look.gap
        if look.vertical then self.holder:SetSize(look.size, long) else self.holder:SetSize(long, look.size) end
        self.holder:SetAlpha(look.alpha)
        for _, chip in ipairs(self.chips) do chip:SetOn(chip.key == self.state) end
        for i, b in ipairs(self.buttons) do
            b:SetSize(look.size, look.size)
            b:ClearAllPoints()
            if look.vertical then b:SetPoint("TOP", 0, -(i - 1) * pitch) else b:SetPoint("LEFT", (i - 1) * pitch, 0) end
            if self.drawn ~= self.state then
                b.icon:SetTexture(GetInventoryItemTexture("player", b.slot) or SAMPLE[i])
                b.used = nil
                b.queued:Hide()
            end
            if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(not look.numbers) end
            if b.cd.SetCooldown then
                if self.state == "cooldown" and i == 1 then
                    if self.drawn ~= self.state then b.cd:SetCooldown(GetTime() - 45, 120) end
                elseif not b.used then
                    b.cd:Clear()
                end
            end
            local q = math.floor(look.size * 0.47)
            b.queued:SetSize(q, q)
            if self.state == "queued" and i == 1 and self.drawn ~= self.state then
                b.queued:SetTexture(SAMPLE[3])
                b.queued:Show()
            end
        end
        if self.drawn ~= self.state then
            self.fly:Hide()
            self.said = nil
        end
        self.drawn = self.state
        if self.fly:IsShown() and self.fly.owner then YR.TrinketFlyPlace(self.fly, self.fly.owner, look.dir) end
        local when = look.show == "combat" and "On screen only in a fight. " or look.show == "nocombat" and "On screen only out of a fight. " or ""
        self.hint:SetText(self.said or (when .. (look.hover and "Rest the mouse on a button for its list" or "Click the buttons")
            .. ": they work here as they will on screen."))
    end
    return f
end

local BuildTrinkets = QoLPage("trinkets", function(L, c, Section, Row, Opt)
        Section("Trinket buttons", "click one to swap in another", { icon = 133434,
            master = { Opt("trinketBar"), function(on) YippRouteDB.trinketBar = on YR.ShowTrinketBar(on) end } })
        local preview = L.Block(TrinketPreview(c), 196)
        -- a setting of the buttons changed: the ones on screen and the preview are as it is now
        local function Applied()
            if YR.TrinketApply then YR.TrinketApply() end
            preview.said = nil
            preview:Refresh()
        end
        local function Num(key, fallback) return function() return tonumber(YippRouteDB[key]) or fallback end end
        local function SetNum(key) return function(v) YippRouteDB[key] = v Applied() end end
        local function Pick(key, choices, fallback)
            local dd
            dd = S.Dropdown(c, 180, choices, function(v)
                YippRouteDB[key] = v ~= fallback and v or nil
                Applied()
                dd:Refresh()
            end)
            function dd:Refresh()
                local now = YippRouteDB[key]
                local shown
                for _, o in ipairs(choices) do
                    if o[1] == now then shown = o[2] end
                end
                if not shown then for _, o in ipairs(choices) do if o[1] == fallback then shown = o[2] end end end
                self:SetValue(shown)
            end
            return dd
        end
        local function Flag(key, offUnlessOn)
            return S.Switch(c, function()
                if offUnlessOn then return YippRouteDB[key] == true end
                return YippRouteDB[key] ~= false
            end, function(on)
                YippRouteDB[key] = on
                Applied()
            end)
        end
        Row("Size", RowSlider(c, 24, 64, 2, Num("trinketBarSize", 38), SetNum("trinketBarSize")))
        Row("Layout", S.Switch(c, function() return YippRouteDB.trinketBarVertical == true end, function(on)
            YippRouteDB.trinketBarVertical = on or nil
            Applied()
        end), "On: the bottom trinket's button stands under the top one's. Off: side by side.")
        Row("Visible", Pick("trinketBarShow", { { "always", "Always" }, { "combat", "In combat" }, { "nocombat", "Out of combat" } }, "always"),
            "When the buttons are on screen. While the position is unlocked they always show, so you can drag them.")
        Row("Left-click", Pick("trinketBarLeft", { { "list", "Lists your trinkets" }, { "use", "Uses the trinket" } }, "list"),
            "What a left-click on a button does. A right-click does the other. Changes out of combat.")
        Row("List on hover", Flag("trinketFlyHover", true), "Opens a button's list of trinkets when the mouse rests on it, and closes it when the"
            .. " mouse leaves. Off: the list opens on a click.")
        Row("About trinket buttons", S.Text(c, 12, S.C.muted),
            "Shows your trinket slots as buttons with their cooldowns. One click lists the trinkets in"
            .. " your bags, and a click on one equips it. In combat the swap waits until the fight ends."
            .. " The other click uses the trinket. Right-click a trinket in the list to add it to your"
            .. " swap order or remove it. The preview works: try the settings on it.")
        Row("Lock position", S.Switch(c, Opt("trinketBarLocked"), function(on) YippRouteDB.trinketBarLocked = on Applied() end),
            "Turn off to drag the buttons.")
        Row("Reset position", S.Button(c, "Reset", function() if YR.TrinketResetPosition then YR.TrinketResetPosition() end end, nil, 90),
            "Puts the buttons back at the bottom middle of the screen. Out of combat.")

        Section("Trinket auto-swap", "in the order you set below", { find = "swap trinkets", icon = 133437,
            master = { function() return YippRouteDB.trinketAuto == true end,
                function(on) YippRouteDB.trinketAuto = on if YR.TrinketPaint then YR.TrinketPaint() end end } })
        Row("About auto-swap", S.Text(c, 12, S.C.muted),
            "When the trinket you wear is on cooldown, the first ready trinket in your order is equipped. A"
            .. " higher one returns when it is ready again. A trinket you equip yourself that is not in the"
            .. " order is left alone. Swaps wait until you are out of combat. A green dot on a button means that"
            .. " slot is being swapped.")
        local function SlotSwitch(slot)
            return S.Switch(c, function() return YR.TrinketDB().auto[slot] ~= false end,
                function(on) if on then YR.TrinketDB().auto[slot] = nil else YR.TrinketDB().auto[slot] = false end if YR.TrinketPaint then YR.TrinketPaint() end end)
        end
        Row("Top trinket slot", SlotSwitch(13))
        Row("Bottom trinket slot", SlotSwitch(14), "Off: this slot keeps what you equip in it.")
        Row("Pause while PvP flagged", S.Switch(c, Opt("trinketPvpPause"), function(on) YippRouteDB.trinketPvpPause = on end),
            "Stops every automatic swap, here and under Mounted and swimming, while you are flagged for PvP. Your own"
            .. " clicks and equipment set keys still work.")

        Section("Mounted and swimming", "swap an item in while you ride or swim", { find = "swap rules carrot", icon = 132239 })
        local carrot = C_Item.GetItemNameByID and C_Item.GetItemNameByID(11122) or "Carrot on a Stick"
        Row("Mounted: " .. carrot, S.Switch(c, function() return YippRouteDB.trinketMount == true end,
            function(on) YippRouteDB.trinketMount = on end),
            "Equips Carrot on a Stick in a trinket slot while you are mounted, and your trinket again when"
            .. " you dismount. Only if you carry one.")
        local SLOT_CHOICE = { { 13, "Top trinket slot" }, { 14, "Bottom trinket slot" } }
        local slotDrop
        slotDrop = S.Dropdown(c, 170, SLOT_CHOICE, function(v) YippRouteDB.trinketMountSlot = v slotDrop:Refresh() end)
        function slotDrop:Refresh()
            for _, o in ipairs(SLOT_CHOICE) do if o[1] == (YippRouteDB.trinketMountSlot or 14) then self:SetValue(o[2]) end end
        end
        Row("Slot", slotDrop)
        Row("Swimming", S.Switch(c, function() return YippRouteDB.trinketSwim == true end,
            function(on) YippRouteDB.trinketSwim = on end), "Equips an item of your choice while you swim, and what you wore again when you leave the water.")
        local swim = S.Input(c, { width = 200, placeholder = "Shift-click the item", onCommit = function(t)
            -- the box shows the item's name, which isn't an item to read back: only a link, an ID or an
            -- emptied box changes what is kept (leaving the box untouched used to wipe it)
            local item = YR.ItemFromText(t)
            if item or strtrim(t or "") == "" then YippRouteDB.trinketSwimItem = item end
            YR:RefreshWindow()
        end })
        function swim:Refresh()
            if self:HasFocus() then return end
            local id = YippRouteDB.trinketSwimItem
            self:SetValue(id and (C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or ("item " .. id)) or "")
        end
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if swim:HasFocus() and IsShiftKeyDown() and link then swim:SetValue(link) end
        end)
        Row("Swimming item", swim)

        Section("Equipment sets", "key bindings for the game's sets", { icon = 132739 })
        local sets = S.Text(c, 12)
        sets:SetJustifyH("RIGHT")
        sets:SetWidth(320)
        function sets:Refresh()
            local list = YR.GearSets()
            local parts = {}
            for i, s in ipairs(list) do if i <= 5 then parts[#parts + 1] = i .. ": " .. s.name end end
            self:SetText(#parts > 0 and table.concat(parts, "   ") or "none yet")
        end
        Row("Your sets", sets, "Create sets in the character window's equipment manager. The first five get key bindings (Key"
            .. " Bindings, AddOns, Headstart). Or use /headstart gear with the set's name or number. In combat"
            .. " the set is equipped when the fight ends.")

        L.Break()
        local y = L.y - 6
        local tail = L.Tail()       -- under the cards, and up with them as they fold
        local head = S.Text(tail, 14)
        head:SetPoint("TOPLEFT", 4, y)
        head:SetText("Your swap order")
        local sub = S.Text(tail, 11, S.C.muted)
        sub:SetPoint("LEFT", head, "RIGHT", 10, 0)
        sub:SetText("numbered: in the order, first is most wanted. Grey: not in it")
        y = y - 26
        trink.rows = {}
        for i = 1, MAX_TRINKETS do
            local r = CreateFrame("Frame", nil, tail)
            r:SetSize(L.colW, 32)
            r:SetPoint("TOPLEFT", 0, y - (i - 1) * 34)
            S.Fill(r, i % 2 == 1 and S.C.card or ZEBRA)
            r.num = S.Text(r, 13, S.C.accent)
            r.num:SetPoint("LEFT", 12, 0)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(24, 24)
            r.icon:SetPoint("LEFT", 34, 0)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.name = S.Text(r, 13)
            r.name:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
            r.toggle = S.Button(r, "Add to the list", function()
                YR.TrinketToggleList(r.id) RefreshTrinkets() end, nil, 140)
            r.toggle:SetPoint("RIGHT", -10, 0)
            r.down = S.IconButton(r, "down", function() YR.TrinketMove(r.id, 1) RefreshTrinkets() end, "Lower", S.C.text, 24)
            r.down:SetPoint("RIGHT", r.toggle, "LEFT", -6, 0)
            r.up = S.IconButton(r, "up", function() YR.TrinketMove(r.id, -1) RefreshTrinkets() end, "Higher", S.C.text, 24)
            r.up:SetPoint("RIGHT", r.down, "LEFT", -2, 0)
            r:Hide()
            trink.rows[i] = r
        end
        trink.none = S.Text(tail, 12, S.C.muted)
        trink.none:SetPoint("TOPLEFT", 12, y - 8)
        trink.none:SetText("No trinkets on you or in your bags yet.")
        L.Length(-y + MAX_TRINKETS * 34 + 40)
end)

-- XP bar (XPBar.lua): every setting applies at once, so the bar on screen is the preview.
local function Swatch(c, key, colour, apply)
    colour = colour or function() return YR.XPBarDB()[key] end
    apply = apply or function() YR.XPBarApply() end
    local b = CreateFrame("Button", nil, c)
    b:SetSize(46, 20)
    S.Border(b, S.C.lineHi)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetPoint("TOPLEFT", 1, -1)
    b.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    b.tex:SetColorTexture(1, 1, 1, 1)
    function b:Refresh() self.tex:SetVertexColor(unpack(colour())) end
    b:SetScript("OnClick", function()
        local col = colour(true)          -- true: about to be changed (a colour kept only once it is)
        local before = { col[1], col[2], col[3], col[4] }
        local function Set(r, g, bl, a)
            col[1], col[2], col[3] = r, g, bl
            if a and col[4] then col[4] = a end
            b:Refresh()
            apply()
        end
        if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = col[1], g = col[2], b = col[3], opacity = col[4], hasOpacity = col[4] ~= nil,
            swatchFunc = function()
                local r, g, bl = ColorPickerFrame:GetColorRGB()
                Set(r, g, bl, ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or nil)
            end,
            opacityFunc = function()
                local r, g, bl = ColorPickerFrame:GetColorRGB()
                Set(r, g, bl, ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or nil)
            end,
            cancelFunc = function() Set(before[1], before[2], before[3], before[4]) end,
        })
    end)
    return b
end

local BuildXPBar = QoLPage("xpbar", function(L, c, Section, Row, Opt)
        local db = YR.XPBarDB
        local function Set(key) return function(v) db()[key] = v YR.XPBarApply() end end
        local function Get(key) return function() return db()[key] end end
        Section("XP bar", "replaces Blizzard's", { find = "experience rested", icon = 236562,
            master = { function() return YR.XPBarOn() end, Set("on") } })
        Row("Hide Blizzard's bar", S.Switch(c, Get("hideBlizz"), Set("hideBlizz")),
            "Hides Blizzard's experience and reputation bar while Headstart's bar is shown.")
        Row("Lock position", S.Switch(c, Get("lock"), Set("lock")), "Turn off to drag the bar.")
        Row("Reset position", S.Button(c, "Reset", function() YR.XPBarResetPosition() end, nil, 90),
            "Moves the bar to the middle of the screen, above the action bars.")
        Row("Width", RowSlider(c, 150, 1800, 10, Get("w"), Set("w"), 260))
        Row("Height", RowSlider(c, 4, 40, 1, Get("h"), Set("h"), 260))
        local PREVIEW = { { "live", "Live" }, { "plain", "No rested XP" }, { "rested", "Rested" },
            { "quests", "Rested, with completed quests" } }
        local preview
        preview = S.Dropdown(c, 220, PREVIEW, function(v) YR.XPBarSample(v ~= "live" and v or nil) preview:Refresh() end)
        function preview:Refresh()
            local now = YR.XPBarSampleNow() or "live"
            for _, o in ipairs(PREVIEW) do if o[1] == now then self:SetValue(o[2]) end end
        end
        Row("Preview", preview, "Draws the bar in a sample state, so you can set the colours without waiting for rested XP."
            .. " The text keeps showing your real numbers. Back to Live when you leave this page.")
        if c.HookScript then c:HookScript("OnHide", function() if YR.XPBarSampleNow() then YR.XPBarSample(nil) end end) end

        L.Sub("Look")
        local TEX = { { "flat", "Flat" }, { "smooth", "Smooth" }, { "blizzard", "Blizzard's" } }
        local tex
        tex = S.Dropdown(c, 170, TEX, function(v) Set("texture")(v) tex:Refresh() end)
        function tex:Refresh() for _, o in ipairs(TEX) do if o[1] == db().texture then self:SetValue(o[2]) end end end
        Row("Texture", tex)
        local pal
        pal = S.Dropdown(c, 180, YR.XPBAR_PALETTES, function(v) YR.XPBarPalette(v) pal:Refresh() end)
        function pal:Refresh()
            local shown = "Your own"
            for _, o in ipairs(YR.XPBAR_PALETTES) do if o[1] == db().palette then shown = o[2] end end
            self:SetValue(shown)
        end
        Row("Colours", pal, "The bar's colours, as a set: your XP, the same while rested, the completed-quests part and how far"
            .. " your rested XP reaches. Use Preview above to see each state.")
        local TICKS = { { 0, "None" }, { 10, "Every tenth" }, { 20, "Every twentieth" }, { 4, "Quarters" } }
        local ticks
        ticks = S.Dropdown(c, 170, TICKS, function(v) Set("ticks")(v) ticks:Refresh() end)
        function ticks:Refresh() for _, o in ipairs(TICKS) do if o[1] == db().ticks then self:SetValue(o[2]) end end end
        Row("Ticks", ticks)
        Row("Text size", RowSlider(c, 8, 20, 1, Get("font"), Set("font"), 260))

        L.Sub("Text")
        local layout
        layout = S.Dropdown(c, 180, YR.XPBAR_LAYOUTS, function(v) YR.XPBarLayout(v) YR:RefreshWindow() end)
        function layout:Refresh()
            local now = YR.XPBarLayoutNow()
            for _, o in ipairs(YR.XPBAR_LAYOUTS) do if o[1] == now then self:SetValue(o[2]) end end
        end
        Row("Text", layout, "What is written on, over and under the bar, as a ready layout. Your own: you write it yourself in"
            .. " the card below.")
        Row("Show text on mouseover only", S.Switch(c, Get("textHover"), Set("textHover")))

        Section("XP bar: your own text", "used while Text is Your own", { icon = 134327, on = function() return YR.XPBarLayoutNow() == "own" end })
        local TOKENS = "{level} {xp} {max} {left} {pct} {pctq} {rested} {restedpct} {rate} {ding} {mobs} {kill} {played}"
            .. " {levelplayed} {session} {quest} {questpct} {quests}"
        local function TextRow(label, key)
            local box = S.Input(c, { width = 320, onCommit = function(t) Set(key)(t) end })
            function box:Refresh() if not self:HasFocus() then self:SetValue(db()[key] or "") end end
            Row(label, box, "Write anything, with these filled in: " .. TOKENS .. ". {rate} is XP an hour, {ding} the"
                .. " time to ding at that rate, {mobs} the kills to ding (by your last kills' XP), {played} and"
                .. " {levelplayed} your played time in all and this level, {session} since you logged in, {quest}"
                .. " {questpct} {quests} the XP, share of the level and number of your quests done and not handed in,"
                .. " {pctq} your percent once they are."
                .. " Empty: nothing")
        end
        TextRow("Left", "left")
        TextRow("Middle", "center")
        TextRow("Right", "right")
        Row("Text above the bar", S.Switch(c, Get("over"), Set("over")), "Adds three more text slots just above the bar.")
        TextRow("Over, left", "left0")
        TextRow("Over, middle", "center0")
        TextRow("Over, right", "right0")
        Row("Text below the bar", S.Switch(c, Get("under"), Set("under")), "Adds three more text slots just below the bar.")
        TextRow("Under, left", "left2")
        TextRow("Under, middle", "center2")
        TextRow("Under, right", "right2")
end)

-- Swing timer (Swing.lua): Blizzard's own swing bars, restyled. What is here is the look; a bar's size,
-- place, title, time and when it shows are Edit Mode's, and the first card says so.
local BuildSwing = QoLPage("swing", function(L, c, Section, Row, Opt)
        local db = YR.SwingDB
        local function Set(key) return function(v) db()[key] = v YR.SwingApply() end end
        local function Get(key) return function() return db()[key] end end
        local function Pick(key, options, width)
            local d
            d = S.Dropdown(c, width or 210, options, function(v) Set(key)(v) d:Refresh() end)
            function d:Refresh() for _, o in ipairs(options) do if o[1] == db()[key] then self:SetValue(o[2]) end end end
            return d
        end

        local function Choice(options, now, pick)
            local d
            d = S.Dropdown(c, 180, options, function(v) pick(v) d:Refresh() YR:RefreshWindow() end)
            function d:Refresh()
                local key = now()
                local shown = "Your own"
                for _, o in ipairs(options) do if o[1] == key then shown = o[2] end end
                self:SetValue(shown)
            end
            return d
        end
        -- One bar's place and size, for the bars a card is about: Move bars, which bar, width, height, reset.
        local function Placement(bars, unlocked, unlock, swing)
            Row("Move bars", S.Switch(c, unlocked, function(on) unlock(on) YR.SwingApply() end),
                "Shows these bars with their names, to be dragged where you want them. Each keeps its own place. Turn"
                .. " off when you are done.")
            local picked = bars[1][1]
            local which
            which = S.Dropdown(c, 180, bars, function(v) picked = v YR:RefreshWindow() end)
            function which:Refresh() for _, o in ipairs(bars) do if o[1] == picked then self:SetValue(o[2]) end end end
            Row("Bar", which, "The bar the rows below are for.")
            local function Resize(i, least, most)
                return function() return (select(i, YR.SwingBarSize(picked))) end, function(v)
                    local w, h = YR.SwingBarSize(picked)
                    local d = db()
                    d.size = d.size or {}
                    d.size[picked] = { i == 1 and math.max(least, math.min(most, v)) or w, i == 2 and math.max(least, math.min(most, v)) or h }
                    YR.SwingApply()
                end
            end
            local getW, setW = Resize(1, 60, 600)
            local getH, setH = Resize(2, 4, 60)
            Row("Width", RowSlider(c, 60, 600, 5, getW, setW))
            Row("Height", RowSlider(c, 4, 60, 1, getH, setH))
            if swing then
                Row("This bar on", S.Switch(c, function() return not (db().use and db().use[picked] == false) end, function(on)
                    local d = db()
                    d.use = d.use or {}
                    d.use[picked] = (not on) and false or nil
                    YR.SwingApply()
                end), "Off: this swing bar isn't shown.")
            end
            Row("Reset this bar", S.Button(c, "Reset", function()
                local d = db()
                if d.size then d.size[picked] = nil end
                YR.SwingResetPosition(picked)
                YR:RefreshWindow()
            end, nil, 90), "Puts this bar back in the stack at the bottom middle of the screen, at the size the look sets.")
        end

        Section("Swing timer", "Blizzard's bars restyled, or Headstart's own", { icon = 132349,
            master = { function() return db().on == true end, Set("on") } })
        Row("Bars", Pick("style", { { "blizzard", "Blizzard's, restyled" }, { "own", "Headstart's own" } }, 180),
            "Blizzard's: the game's swing bars in this look, placed and sized in Edit Mode, all moved as Edit Mode moves"
            .. " them. Headstart's own: bars drawn by Headstart, each moved and sized by itself further down this"
            .. " card; Blizzard's are made invisible while they show.")
        Row("Visible", Pick("show", { { "always", "Always" }, { "combat", "In combat" }, { "swing", "While swinging" } }, 180),
            "When Headstart's own swing bars show. Blizzard's bars have their own setting in Edit Mode (Esc, Edit Mode: click"
            .. " a swing bar), with their size and place.")
        Row("Preview", S.Switch(c, function() return YR.SwingPreviewing() end, function(on)
            local running, why = YR.SwingPreview(on)
            if on and not running then YR.Print(why or "turn the swing timer on first.") end
        end), "Keeps sample swings running on every bar while you change things. Stops when you turn it off, close this"
            .. " window or enter combat.")
        if c.HookScript then c:HookScript("OnHide", function() if YR.SwingPreviewing() then YR.SwingPreview(false) end end) end
        L.Sub("Look")
        local LOOKS = { { "soft", "Soft" }, { "slim", "Slim" }, { "classic", "Classic" } }
        local looks
        looks = S.Dropdown(c, 210, LOOKS, function(v) YR.SwingPreset(v) YR:RefreshWindow() end)
        function looks:Refresh()
            local now = db().preset
            self:SetValue(now == "soft" and "Soft" or now == "slim" and "Slim" or now == "classic" and "Classic" or "Pick a look...")
        end
        Row("Preset", looks, "Sets texture, text and colours in one go. Soft: softly shaded bars in muted colours on a half-clear"
            .. " back, with only the name on them. Slim: flat bars in quiet colours with a bright front edge."
            .. " Classic: shaded bars in blue and orange.")
        Row("Colours", Choice(YR.SWING_PALETTES, function() return db().palette end, YR.SwingPalette),
            "The bars' colours, as a set: the three hands, a hand out of range, and the health bar.")
        Row("Frame", Choice(YR.SWING_FRAMES, YR.SwingFrameNow, YR.SwingFrame),
            "The line round each bar. Bronze matches the frames of Blizzard's action buttons.")
        Row("Texture", Pick("texture", { { "smooth", "Soft" }, { "flat", "Flat" }, { "blizzard", "Glossy" } }, 180))
        Row("Text", Choice(YR.SWING_TEXTS, YR.SwingTextNow, YR.SwingText))
        Row("Text size", S.Stepper(c, Get("font"), Set("font"), 8, 24, 1, 110))
        Row("Font", Pick("fontFace", { { "blizzard", "Blizzard's" }, { "headstart", "Headstart's" } }, 180))
        Row("Show out of range", S.Switch(c, Get("range"), Set("range")),
            "Writes Out of range on a swing bar, and greys its fill, while your target is out of range for that attack.")
        Row("Range bar", S.Switch(c, Get("rangeBar"), Set("rangeBar")),
            "A bar that says In range or Out of range for the target you have, in combat and out of it, with how far it"
            .. " is in steps of 5 yards. Shows while you have a living target you can attack. A hunter's also says Melee range.")
        L.Sub("Place and size (Headstart's own bars)")
        Placement({ { "main", "Main hand" }, { "off", "Off hand" }, { "ranged", "Ranged" }, { "range", "Range bar" } },
            function() return db().lock == false end, function(on) db().lock = not on end, true)

        local function OwnBar(key)
            return S.Switch(c, function() return db()[key] == true end, function(on)
                db()[key] = on or nil
                YR.ApplyParts()
                YR.SwingApply()
                YR:RefreshWindow()
            end)
        end
        -- One card for everything about health and power: Headstart's own two bars, and the two changes
        -- to Blizzard's own resource bar. Its switch is all of it: off, none of the four is on (what
        -- was on is remembered, and comes back with the switch); on with nothing remembered, the two
        -- bars of ours.
        local function Parts()
            local d = db()
            return d.health == true, d.power == true, YippRouteDB.powerFlashOff == true, YippRouteDB.resourceLook == true,
                YR.ResourceBarWanted("combo")
        end
        Section("Health and power bars", "Headstart's own health, power and combo bars",
            { find = "health power mana rage energy resource bar own spend flash", icon = 136048,
              master = { function()
                  local health, power, flash, look, points = Parts()
                  return health or power or flash or look or points
              end, function(on)
                  local d = db()
                  if on then
                      local was = YippRouteDB.resBarsWere
                      if type(was) ~= "table" or not (was[1] or was[2] or was[3] or was[4] or was[5]) then
                          was = { true, true, false, false, true }
                      end
                      d.health, d.power, d.combo = was[1] or nil, was[2] or nil, was[5] or nil
                      YippRouteDB.powerFlashOff, YippRouteDB.resourceLook = was[3] or nil, was[4] or nil
                  else
                      YippRouteDB.resBarsWere = { Parts() }
                      d.health, d.power, d.combo = nil, nil, nil
                      YippRouteDB.powerFlashOff, YippRouteDB.resourceLook = nil, nil
                  end
                  YR.ApplyParts()
                  YR.SwingApply()
                  YR.PowerFlashApply()
                  YR.ResourceLookApply()
              end } })
        Row("Health bar", OwnBar("health"), "A bar of your health, drawn by Headstart.")
        Row("Power bar", OwnBar("power"), "A bar of your rage, energy or mana, in the game's colour for it.")
        Row("Combo points", S.Switch(c, function() return YR.ResourceBarWanted("combo") end, function(on)
            db().combo = on and true or false
            YR.ApplyParts()
            YR.SwingApply()
            YR:RefreshWindow()
        end), "Your combo points as a row of squares that fill, in the same look. On with the power bar unless you turn it"
            .. " off. Only on a class that has them.")
        Row("Combo points colour", Pick("comboColor", { { "swing", "Swing timer's" }, { "class", "Class colour" } }, 180),
            "Swing timer's: the colour of the main-hand swing bar, so they read as one set.")
        Row("Visible", Pick("resShow", { { "always", "Always" }, { "combat", "In combat" } }, 180))
        Row("Health in class colour", S.Switch(c, function() return db().healthClass == true end, Set("healthClass")))
        L.Sub("Look")
        -- These bars wear the swing timer's look until one is picked for them here.
        local function ResLook() return YR.ResourceLook() end
        local SAME = { "same", "Same as the swing timer" }
        local RES_FRAMES = { SAME }
        for _, o in ipairs(YR.SWING_FRAMES) do RES_FRAMES[#RES_FRAMES + 1] = o end
        Row("Frame", Choice(RES_FRAMES, function() return YR.ResourceLookOwn() and YR.SwingFrameNow(ResLook()) or "same" end,
            function(v)
                if v == "same" then
                    YR.ResourceLookOwn(false)
                    YR.SwingApply()
                else
                    YR.ResourceLookOwn(true)
                    YR.SwingFrame(v, ResLook())
                end
                YR:RefreshWindow()
            end), "The line round each bar. Same as the swing timer: these bars follow whatever look the swing timer has.")
        local RES_TEX = { SAME, { "smooth", "Soft" }, { "flat", "Flat" }, { "blizzard", "Glossy" } }
        local resTex
        resTex = S.Dropdown(c, 180, RES_TEX, function(v)
            if v == "same" then
                YR.ResourceLookOwn(false)
            else
                YR.ResourceLookOwn(true)
                ResLook().texture = v
            end
            YR.SwingApply()
            YR:RefreshWindow()
        end)
        function resTex:Refresh()
            local now = YR.ResourceLookOwn() and ResLook().texture or "same"
            for _, o in ipairs(RES_TEX) do if o[1] == now then self:SetValue(o[2]) end end
        end
        Row("Texture", resTex)
        Row("Text", Pick("resText", { { "all", "Percent and number" }, { "pct", "Percent" }, { "value", "Number" }, { "none", "None" } }, 180),
            "What the health and power bars say: the percent at the left, how much you have at the right.")
        Row("Colours", Pick("resTone", { { "bright", "Blizzard's" }, { "muted", "Darker" } }, 180),
            "Blizzard's: the game's own colours for health, energy, rage and mana. Darker takes them down a little.")
        L.Sub("Place and size")
        Placement({ { "health", "Health" }, { "power", "Power" }, { "combo", "Combo points" } },
            function() return db().resLock == false end, function(on) if on then db().resLock = false else db().resLock = nil end end, false)
        L.Sub("Blizzard's own resource bar")
        Row("Hide while Headstart's bars show", S.Switch(c, function() return db().resHideBlizz ~= false end, function(on)
            if on then db().resHideBlizz = nil else db().resHideBlizz = false end
            YR.SwingApply()
        end), "Makes Blizzard's resource bar and its combo points invisible while Headstart's health or power bar is on, so"
            .. " you do not see both. It shows again in Edit Mode.")
        Row("Hide the spend flash", S.Switch(c, function() return YippRouteDB.powerFlashOff == true end, function(on)
            YippRouteDB.powerFlashOff = on or nil
            YR.ApplyParts()
            YR.PowerFlashApply()
        end), "Removes the pale block Blizzard leaves where the resource you spent was. The bar drops to its new value at"
            .. " once and fills again from there. For the player frame, the personal resource display and the nameplate bar.")

        -- The cast bar: a bar of Headstart's own for your casts, in the swing timer's look.
        local function CastSwitch(key)
            return S.Switch(c, function() return db()[key] ~= false end, function(on)
                if on then db()[key] = nil else db()[key] = false end
                YR.SwingApply()
            end)
        end
        Section("Cast bar", "your casts and channels, in the swing timer's look",
            { find = "cast bar casting channel spell interrupt own", icon = 136048,
              master = { function() return db().cast == true end, function(on)
                  db().cast = on or nil
                  YR.ApplyParts()
                  YR.SwingApply()
              end } })
        Row("Spell icon", CastSwitch("castIcon"), "The spell's icon to the left of the bar.")
        Row("Time left", CastSwitch("castTime"), "The seconds left, at the right end of the bar.")
        Row("Hide Blizzard's cast bar", CastSwitch("castHideBlizz"),
            "Makes Blizzard's own cast bar invisible while Headstart's is on, so you do not see both.")
        L.Sub("Place and size")
        Placement({ { "cast", "Cast bar" } },
            function() return db().castLock == false end, function(on) if on then db().castLock = false else db().castLock = nil end end, false)
end)

-- ---------------------------------------------------------------------------
-- Instances: the count against the limit, and the log (Instances.lua)
-- ---------------------------------------------------------------------------
local inst = {}

local function Money(c)
    c = math.floor(c or 0)
    if c >= 10000 then return ("%dg %ds"):format(c / 10000, c % 10000 / 100) end
    if c >= 100 then return ("%ds %dc"):format(c / 100, c % 100) end
    return c .. "c"
end

local function InstanceRows()
    local out = {}
    local runs = YippRouteDB.instanceRuns or {}
    for i = #runs, 1, -1 do
        local r = runs[i]
        if YippRouteDB.instanceAccount == true or r.char == YR.CharKey() then out[#out + 1] = r end
    end
    return out
end

local function Stat(page, x, y, label)
    local box = CreateFrame("Frame", nil, page)
    box:SetSize(220, 70)
    box:SetPoint("TOPLEFT", x, y)
    S.Fill(box, S.C.card)
    S.Border(box, S.C.line)
    box.label = S.Text(box, 11, S.C.muted)
    box.label:SetPoint("TOPLEFT", 14, -12)
    box.label:SetText(label:upper())
    box.value = S.Text(box, 24)
    box.value:SetPoint("TOPLEFT", 14, -30)
    box.sub = S.Text(box, 11, S.C.sub)
    box.sub:SetPoint("LEFT", box.value, "RIGHT", 10, -2)
    return box
end

-- A QoL page, under its heading like the others. Two views, picked at the top right: the log (the hint,
-- the three counts, the runs) and the tracker's settings.
local BuildInstanceSettings = QoLPage("instances", function(L, c, Section, Row, Opt)
        Section("Instance tracker", "entries counted against the hourly and daily limits", { find = "lockout dungeon raid reset", icon = 134237,
            master = { Opt("instanceTrack"), function(on)
                YippRouteDB.instanceTrack = on
                if YR.InstanceHudApply then YR.InstanceHudApply() end
            end } })
        Row("Hourly limit", S.Stepper(c, function() return YippRouteDB.instanceHour or 5 end,
            function(v) YippRouteDB.instanceHour = v end, 1, 30, 1, 110),
            "How many new instances the game allows per hour. Forever's limit isn't known; 5 is Classic's. If"
            .. " the game refuses an entry, the log shows the count at that moment.")
        Row("Daily limit", S.Stepper(c, function() return YippRouteDB.instanceDay or 30 end,
            function(v) YippRouteDB.instanceDay = v end, 1, 100, 1, 110), "How many new instances the game allows per day. 30 on Classic.")
        Row("Re-entry window (minutes)", S.Stepper(c, function() return YippRouteDB.instanceSame or 30 end,
            function(v) YippRouteDB.instanceSame = v end, 1, 120, 5, 110),
            "Entering the same dungeon again within this time, with the same group leader and no reset,"
            .. " counts as the same instance. Used when the game doesn't reveal the instance's ID.")
        Row("Account-wide count", S.Switch(c, function() return YippRouteDB.instanceAccount == true end,
            function(on) YippRouteDB.instanceAccount = on end),
            "Counts all your characters toward one limit, as later expansions do. Off: each character has its"
            .. " own count, as in Classic.")
        Row("On-screen warning", S.Switch(c, Opt("instanceWarn"), function(on) YippRouteDB.instanceWarn = on end),
            "Shows a warning in the middle of the screen one instance before the limit, and at it. Chat"
            .. " always tells you.")
        local HUD = { { "icon", "A small icon" }, { "log", "A small log" }, { "off", "Nothing" } }
        local hudMode
        hudMode = S.Dropdown(c, 170, HUD, function(v)
            YippRouteDB.instanceHud = v
            YR.InstanceHudApply()
            hudMode:Refresh()
        end)
        function hudMode:Refresh() for _, o in ipairs(HUD) do if o[1] == YR.InstanceHudMode() then self:SetValue(o[2]) end end end
        Row("Display", hudMode, "Icon: this hour's count, coloured green, yellow or red, with the wait for a free slot. Hover it"
            .. " for today's count and your latest runs. Log: the same as text. Click either to open this page."
            .. " Shift-drag to move.")
        Row("Always show", S.Switch(c, function() return YippRouteDB.instanceHudAlways == true end, function(on)
            YippRouteDB.instanceHudAlways = on
            YR.InstanceHudApply()
        end), "Off: shown only inside an instance, or when you have entered one this hour.")
        Row("Runs in the on-screen log", S.Stepper(c, function() return YippRouteDB.instanceHudRows or 3 end, function(v)
            YippRouteDB.instanceHudRows = v
            YR.InstanceHudApply()
        end, 0, 8, 1, 110))
        Row("Reset position", S.Button(c, "Reset", function() YR.InstanceHudResetPosition() end, nil, 90),
            "Moves it back to the left of the screen.")
end)

-- ---------------------------------------------------------------------------
-- Journey: the logging, and the window that tells it (Journey.lua, and Journey.lua here)
-- ---------------------------------------------------------------------------
local BuildJourney = QoLPage("journey", function(L, c, Section, Row)
        Section("Journey", "your road logged, and told as a story", { find = "journey wrapped stats log distance gold time played travelled",
            icon = 134939, master = { function() return YippRouteDB.journey ~= false end, function(on)
                if on then YippRouteDB.journey = nil else YippRouteDB.journey = false end
                YR.ApplyParts()
            end } })
        Row("Open your journey", S.Button(c, "Open", function() YR.JourneyOpen() end, "primary", 90),
            "Your latest chapter: how far you travelled, where the hours went, the gold you earned, your best find and more, a page"
            .. " at a time. A chapter is written when you reach level 20, 30, 40, 50 and 60, and at no other level - before the"
            .. " first, the window says when it comes. Also /hs journey")
        -- a made-up journey at one of the levels a chapter is written at
        local TRY = { { 20, "Level 20" }, { 30, "Level 30" }, { 40, "Level 40" }, { 50, "Level 50" }, { 60, "Level 60" } }
        local try = S.Dropdown(c, 190, TRY, function(level)
            YR.JourneyToast(level)
            YR.JourneyShow(level)
        end)
        function try:Refresh() self:SetValue("Pick a level") end
        Row("Try it with a sample", try, "Shows the note and the window with a made-up journey at that level, the chapters before it"
            .. " included. A pit stop on the way, the whole road at 60. Nothing of yours is changed. Also /hs journey test 60")
        Row("Note when a chapter is written", S.Switch(c, function() return YippRouteDB.journeyToast ~= false end, function(on)
            if on then YippRouteDB.journeyToast = nil else YippRouteDB.journeyToast = false end
        end), "A small note at the top of the screen for a few seconds when you reach level 20, 30, 40, 50 or 60. Click it to read the"
            .. " chapter. Off: the chapter is written all the same.")
        Row("Start over", S.Button(c, "Reset", function() YR.JourneyReset() end, nil, 90),
            "Forgets everything logged for this character. It counts again from now.")
end)

local function BuildInstances(outer)
    local page = CreateFrame("Frame", nil, outer)
    page:SetAllPoints()
    local opts = CreateFrame("Frame", nil, outer)
    opts:SetPoint("TOPLEFT", 0, -30)
    opts:SetPoint("BOTTOMRIGHT")
    BuildInstanceSettings(opts)
    local chips = {}
    function inst.View(view)
        inst.view = view
        page:SetShown(view == "log")
        opts:SetShown(view == "settings")
        for name, chip in pairs(chips) do chip:SetOn(name == view) end
    end
    chips.settings = S.Chip(outer, "Settings", function() inst.View("settings") YR:RefreshWindow() end)
    chips.settings:SetPoint("TOPRIGHT", -16, -6)
    chips.log = S.Chip(outer, "Log", function() inst.View("log") YR:RefreshWindow() end)
    chips.log:SetPoint("RIGHT", chips.settings, "LEFT", -6, 0)
    for _, chip in pairs(chips) do chip:SetFrameLevel(outer:GetFrameLevel() + 10) end
    inst.View("log")
    inst.hint = S.Text(page, 12, S.C.muted)
    inst.hint:SetPoint("TOPLEFT", 16, -10)
    inst.hint:SetPoint("RIGHT", chips.log, "LEFT", -12, 0)
    inst.hint:SetJustifyH("LEFT")
    inst.hint:SetWordWrap(false)
    inst.hour = Stat(page, 16, -34, "This hour")
    inst.next = Stat(page, 248, -34, "Next free slot")
    inst.day = Stat(page, 480, -34, "Today")
    -- what the columns are
    local heads = CreateFrame("Frame", nil, page)
    heads:SetPoint("TOPLEFT", 16, -116)
    heads:SetSize(CW - 32, 20)
    for _, h in ipairs({ { 10, "ENTERED" }, { 140, "INSTANCE" }, { 440, "TIME INSIDE" }, { 550, "XP" }, { 650, "MONEY" } }) do
        local t = S.Text(heads, 10, S.C.muted)
        t:SetPoint("LEFT", h[1], 0)
        t:SetText(h[2])
    end
    local rule = heads:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT") rule:SetPoint("BOTTOMRIGHT", -8, 0) rule:SetHeight(1)
    rule:SetColorTexture(unpack(S.C.line))
    inst.empty = S.Text(page, 13, S.C.muted)
    inst.empty:SetPoint("TOPLEFT", 26, -148)
    inst.empty:SetText("No runs yet. Dungeons and raids you enter are listed here.")
    inst.list = List(page, CW - 32, math.floor((CH - 138 - 64) / 26), 26, function(r, i)
        local e = inst.rows[i]
        r:Select(false)
        r.when:SetText(date("%a %d %b  %H:%M", e.entered))
        r.name:SetText((e.name or "?") .. ((YippRouteDB.instanceAccount == true) and ("  |cff999999" .. tostring(e.char):match("^[^%-]+") .. "|r") or ""))
        local long = (e.left or (GetServerTime and GetServerTime() or time())) - e.entered
        r.time:SetText(YR.InstanceClock(long) .. (e.left and "" or "  |cff66ccffnow|r"))
        r.xp:SetText((e.xp or 0) > 0 and (BreakUpLargeNumbers and BreakUpLargeNumbers(e.xp) or tostring(e.xp)) .. " XP" or "")
        r.gold:SetText((e.money or 0) > 0 and Money(e.money) or "")
        -- left and gone back into the same copy: one instance against the limit, said so
        local back = e.again and (e.again == 1 and "went back in once" or ("went back in %d times"):format(e.again)) or nil
        -- the copy's ID, where the game let it be read: two runs with one ID are one instance
        local id = e.id and ("ID " .. e.id) or nil
        r.flag:SetText(back and id and (back .. "  ·  " .. id) or back or id or "")
    end, function() return inst.rows and #inst.rows or 0 end, function(r)
        r.when = S.Text(r, 11, S.C.muted)
        r.when:SetPoint("LEFT", 10, 0)
        r.name = S.Text(r, 13)
        r.name:SetPoint("LEFT", 140, 0)
        r.name:SetWidth(290)
        r.name:SetJustifyH("LEFT")
        r.time = S.Text(r, 12, S.C.sub)
        r.time:SetPoint("LEFT", 440, 0)
        r.xp = S.Text(r, 12, S.C.sub)
        r.xp:SetPoint("LEFT", 550, 0)
        r.gold = S.Text(r, 12, S.C.gold or S.C.sub)
        r.gold:SetPoint("LEFT", 650, 0)
        r.flag = S.Text(r, 11, S.C.muted)
        r.flag:SetPoint("RIGHT", -10, 0)
    end)
    inst.list:SetPoint("TOPLEFT", 16, -138)
    local reset = S.Button(page, "Mark as reset", function() YR.InstanceResetSeen() YR:RefreshWindow() end, nil, 150)
    reset:SetPoint("BOTTOMLEFT", 136, 14)           -- beside Reload UI
    reset.tip = "Use this if you reset your instances and Headstart missed it: your next entry counts as a new instance"
    StaticPopupDialogs["HEADSTART_CLEAR_INSTANCES"] = {
        text = "Headstart: clear the instance log?\n\nThe listed runs and the hourly and daily counts are reset.",
        button1 = "Clear",
        button2 = "Cancel",
        OnAccept = function() YR.InstanceForget() YR:RefreshWindow() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    local clear = S.Button(page, "Clear the log", function() StaticPopup_Show("HEADSTART_CLEAR_INSTANCES") end, nil, 130)
    clear:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    -- the countdown runs while the page shows
    local wait = 0
    page:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        wait = 1
        if inst.Refresh then inst.Refresh() end
    end)
end

function inst.Refresh()
    if not inst.hour then return end
    local hour, day, wait = YR.InstanceCounts()
    local perHour, perDay = YR.InstanceLimits()
    inst.hour.value:SetText(("%d / %d"):format(hour, perHour))
    inst.hour.value:SetTextColor(unpack(hour >= perHour and S.C.danger or hour == perHour - 1 and S.C.gold or S.C.text))
    inst.day.value:SetText(("%d / %d"):format(day, perDay))
    inst.day.value:SetTextColor(unpack(day >= perDay and S.C.danger or S.C.text))
    inst.next.value:SetText(wait and YR.InstanceClock(wait) or "now")
    inst.next.value:SetTextColor(unpack(wait and S.C.danger or S.C.green))
    inst.next.sub:SetText(wait and "until you can go in again" or "")
    local locks = YippRouteDB.instanceLocks
    local last = locks and locks[#locks]
    inst.hint:SetText(not YR.Option("instanceTrack")
        and "The instance tracker is off, so nothing is counted. Turn it on under Settings, top right."
        or ("Each new dungeon or raid counts toward the hourly and daily limits.%s"):format(last and
        (" The game last refused an entry at %d this hour (%s)."):format(last.hour, date("%a %H:%M", last.at)) or
        " Limits and display: Settings, top right."))
    inst.rows = InstanceRows()
    inst.empty:SetShown(#inst.rows == 0)
    inst.list:Refresh()
end

local function RefreshInstances()
    win.subtitle:SetText("")
    inst.Refresh()
    for _, ctl in ipairs(qolPages.instances.controls) do if ctl.Refresh then ctl:Refresh() end end
end

-- RestedXP's guide window (RXPSkin.lua): which look, and the Headstart look's colours.
local BuildRXPSkin = QoLPage("rxpskin", function(L, c, Section, Row, Opt)
        Section("RestedXP skin", "another look for RestedXP's window", { find = "rxp guide", icon = 134939 })
        local LOOKS = { { "off", "RestedXP's own" }, { "headstart", "Headstart" }, { "blizzard", "Blizzard" } }
        local look
        look = S.Dropdown(c, 190, LOOKS, function(v)
            if not YR.SetRXPSkin(v) then YR.Print("RestedXP isn't loaded: nothing to skin.") end
            look:Refresh()
        end)
        function look:Refresh() for _, o in ipairs(LOOKS) do if o[1] == YR.RXPSkinModeSet() then self:SetValue(o[2]) end end end
        Row("Look", look, "Headstart: flat and dark, a thin border and one accent colour. Blizzard: the game's own frame"
            .. " and gold titles. RestedXP's own: the theme you had before. Both looks are also in RestedXP's"
            .. " theme list.")

        L.Sub("Colours, for the Headstart look")
        local function Accent(change)
            if change then YippRouteDB.rxpSkinAccent = YippRouteDB.rxpSkinAccent or { unpack(YR.RXPSkinAccent()) } end
            return YippRouteDB.rxpSkinAccent or YR.RXPSkinAccent()
        end
        local function Back(change)
            if change then YippRouteDB.rxpSkinBack = YippRouteDB.rxpSkinBack or { unpack(YR.RXPSkinBack()) } end
            return YippRouteDB.rxpSkinBack or YR.RXPSkinBack()
        end
        Row("Accent colour", Swatch(c, "accent", Accent, YR.RXPSkinApply),
            "Colours the title, the current step, the scroll bar, map pins and tooltip links in the Headstart"
            .. " look.")
        Row("Use class colour", S.Switch(c, function() return YippRouteDB.rxpSkinClass == true end, function(on)
            YippRouteDB.rxpSkinClass = on
            YR.RXPSkinApply()
        end), "Uses each character's class colour as the accent.")
        Row("Background", Swatch(c, "back", Back, YR.RXPSkinApply), "The window's fill colour and opacity.")
        local PRESETS = {
            { { 0.40, 0.66, 1.00 }, "Blue" }, { { 0.25, 0.85, 0.75 }, "Teal" }, { { 0.40, 0.85, 0.45 }, "Green" },
            { { 1.00, 0.78, 0.25 }, "Gold" }, { { 1.00, 0.55, 0.20 }, "Orange" }, { { 0.95, 0.35, 0.35 }, "Red" },
            { { 0.95, 0.45, 0.75 }, "Pink" }, { { 0.65, 0.50, 1.00 }, "Purple" },
        }
        local preset = S.Dropdown(c, 190, PRESETS, function(v)
            YippRouteDB.rxpSkinAccent = { v[1], v[2], v[3] }
            YippRouteDB.rxpSkinClass = nil
            YR.RXPSkinApply()
            YR:RefreshWindow()
        end)
        preset:SetValue("Pick one")
        Row("Accent presets", preset)
        Row("Reset colours", S.Button(c, "Reset", function()
            YippRouteDB.rxpSkinAccent, YippRouteDB.rxpSkinBack, YippRouteDB.rxpSkinClass = nil, nil, nil
            YR.RXPSkinApply()
            YR:RefreshWindow()
        end, nil, 90))
end)

-- The game's damage meter (DamageSkin.lua): which look, and the Headstart look's colours.
local BuildDamageSkin = QoLPage("dmgskin", function(L, c, Section, Row, Opt)
        Section("Damage meter skin", "a tidy top bar for the game's meter", { find = "dps details", icon = 132349 })
        local LOOKS = { { "off", "Blizzard's own" }, { "headstart", "Headstart" }, { "blizzard", "Blizzard, tidied" } }
        local look
        look = S.Dropdown(c, 190, LOOKS, function(v)
            YR.SetDamageSkin(v)
            if v ~= "off" and not YR.DamageSkinAvailable() then
                YR.Print("the damage meter isn't on screen: turn it on in the game's options and the look is put on it.")
            end
            look:Refresh()
        end)
        function look:Refresh()
            local set = YippRouteDB.dmgSkin        -- as you picked it, also while quality of life is off
            set = (set == "headstart" or set == "blizzard") and set or "off"
            for _, o in ipairs(LOOKS) do if o[1] == set then self:SetValue(o[2]) end end
        end
        Row("Look", look, "Both looks tidy the top bar: the title on the left, the timer and buttons on the right."
            .. " Headstart: a flat dark card in your colours. Blizzard, tidied: the game's dark fill, thin frame"
            .. " and gold title. The bars themselves are set in Edit Mode.")

        L.Sub("Colours, for the Headstart look")
        local function Accent(change)
            if change then YippRouteDB.dmgSkinAccent = YippRouteDB.dmgSkinAccent or { unpack(YR.DamageSkinAccent()) } end
            return YippRouteDB.dmgSkinAccent or YR.DamageSkinAccent()
        end
        local function FrameColour(change)
            if change then YippRouteDB.dmgSkinFrame = YippRouteDB.dmgSkinFrame or { unpack(YR.DamageSkinFrame()) } end
            return YippRouteDB.dmgSkinFrame or YR.DamageSkinFrame()
        end
        Row("Accent colour", Swatch(c, "accent", Accent, YR.DamageSkinApply), "Colours the title and the line under the top bar.")
        Row("Use class colour", S.Switch(c, function() return YippRouteDB.dmgSkinClass == true end, function(on)
            YippRouteDB.dmgSkinClass = on
            YR.DamageSkinApply()
        end))
        Row("Background", Swatch(c, "frame", FrameColour, YR.DamageSkinApply), "The window's fill colour and opacity.")
        Row("Reset colours", S.Button(c, "Reset", function()
            YippRouteDB.dmgSkinAccent, YippRouteDB.dmgSkinFrame, YippRouteDB.dmgSkinClass = nil, nil, nil
            YR.DamageSkinApply()
            YR:RefreshWindow()
        end, nil, 90))
end)

-- Chat: Blizzard's buttons beside the chat (BarHide.lua), and the whisper sound (Whisper.lua).
local BuildChat = QoLPage("chat", function(L, c, Section, Row, Opt)
        Section("Chat buttons", "slim or hide the buttons beside chat", { icon = "Interface\\Icons\\INV_Misc_Note_01" })
        local STRIP = { { "show", "As Blizzard has it" }, { "slim", "Slim, with small icons" }, { "hide", "Hidden" } }
        local strip
        strip = S.Dropdown(c, 210, STRIP, function(v)
            YippRouteDB.chatStrip = v ~= "show" and v or nil
            YR.BarHideApply()
            strip:Refresh()
        end)
        function strip:Refresh()
            local now = YippRouteDB.chatStrip or "show"
            for _, o in ipairs(STRIP) do if o[1] == now then self:SetValue(o[2]) end end
        end
        Row("Button strip", strip, "Slim: the strip beside chat is a third narrower, with small plain buttons. Hidden: the strip and"
            .. " the chat menu are removed. Either way, the chat window can then sit closer to the screen edge"
            .. " in Edit Mode.")
        Row("Hide the text-to-speech button", S.Switch(c, function() return YippRouteDB.chatTTSHide == true end, function(on)
            YippRouteDB.chatTTSHide = on or nil
            YR.BarHideApply()
        end), "Hides the speaker button above the strip.")
        Row("Hide the social button", S.Switch(c, function() return YippRouteDB.chatSocialHide == true end, function(on)
            YippRouteDB.chatSocialHide = on or nil
            YR.BarHideApply()
        end), "Hides the friends button above chat. Your key binding for the social window still works.")

        Section("Chat log", "search and copy chat, past sessions too", { find = "copy chat history", icon = 134939,
            master = { Opt("chatLog"), function(on) YippRouteDB.chatLog = on YR.ChatLogApply() end } })
        Row("About the chat log", S.Text(c, 12, S.C.muted),
            "Records every line your chat windows show, per character. The combat log is not recorded. The"
            .. " log window shows the lines as text you can select and copy. Filter by chat window, and search."
            .. " Lines the game marks as secret are not recorded.")
        Row("Chat log window", S.Button(c, "Open", function() YR.ChatLogOpen() end, nil, 90), "Opens the log. Also /headstart chat, and the button beside chat.")
        Row("Chat button", S.Switch(c, function() return YippRouteDB.chatLogButton ~= false end, function(on)
            YippRouteDB.chatLogButton = on
            YR.ChatLogApply()
        end), "Adds a small button beside chat that opens the log.")
        Row("Restore chat after reload", S.Switch(c, function() return YippRouteDB.chatLogRestore ~= false end,
            function(on) YippRouteDB.chatLogRestore = on end),
            "Puts the last lines back into each chat window after a login or reload, so you can scroll up as"
            .. " before.")
        Row("  Lines restored per window", S.Stepper(c, YR.ChatLogRestoreLines, function(v) YippRouteDB.chatLogRestoreLines = v end,
            10, 500, 10, 110))
        Row("Lines kept", S.Stepper(c, YR.ChatLogMax, function(v) YippRouteDB.chatLogMax = v end, 200, 5000, 100, 110),
            "The log keeps this many of the newest lines. Shift-click changes it by a thousand.")
        Row("Keep between sessions", S.Switch(c, function() return YippRouteDB.chatLogKeep ~= false end,
            function(on) YippRouteDB.chatLogKeep = on end),
            "Keeps the log when you log out, with a marker where each session began. Off: the log starts"
            .. " empty at every login.")
        local count = S.Text(c, 12, S.C.sub)
        function count:Refresh() self:SetText(("%d lines"):format(YR.ChatLogCount())) end
        Row("Lines stored", count)
        StaticPopupDialogs["HEADSTART_CLEAR_CHATLOG"] = {
            text = "Headstart: clear this character's chat log?",
            button1 = "Clear",
            button2 = "Cancel",
            OnAccept = function() YR.ChatLogClear() YR:RefreshWindow() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        Row("Clear the log", S.Button(c, "Empty", function() StaticPopup_Show("HEADSTART_CLEAR_CHATLOG") end, nil, 90),
            "Deletes this character's chat log. Asks first.")

        Section("Whisper sound", "your own sound for whispers", { icon = 133469 })
        local sound
        sound = S.Dropdown(c, 240, YR.WhisperSounds, function(v)
            YippRouteDB.whisperSound = v ~= "off" and v or nil
            sound:Refresh()
        end, { icon = "sound", tip = "Listen", shows = function(v) return v ~= "off" end,
            onClick = function(v) YR.PlayWhisperSound(v) end })
        function sound:Refresh() self:SetValue(YR.WhisperSoundName()) end
        Row("Sound", sound, "The sound played when you are whispered. Click the speaker on a line to hear it. Sounds from"
            .. " LibSharedMedia addons such as Details and WeakAuras are listed too. The game's own whisper"
            .. " sound still plays.")
        local file
        file = S.Input(c, { width = 240, placeholder = "AddOns\\whisper.ogg", onCommit = function(t)
            t = (t or ""):gsub("^%s+", ""):gsub("%s+$", "")
            YippRouteDB.whisperFile = t ~= "" and t or nil
            if YR.WhisperFile() then
                YippRouteDB.whisperSound = "file"
                if not YR.PlayWhisperSound("file") then
                    YR.Print("the game can't play " .. YR.WhisperFile() .. ". A file put there while the game runs is found only after the game is started again.")
                end
            elseif YippRouteDB.whisperSound == "file" then
                YippRouteDB.whisperSound = nil
            end
            YR.SettingChanged()
            sound:Refresh()
        end })
        function file:Refresh() if not self:HasFocus() then self:SetValue(YippRouteDB.whisperFile or "") end end
        Row("Custom sound file", file, "An .ogg or .mp3 inside the game's Interface folder, as a path from there: AddOns\\whisper.ogg."
            .. " Press Enter to select and play it. A new file is only found after the game is restarted; a"
            .. " reload is not enough.")
        local CHANNEL = { { "Master", "Master (heard with effects turned down)" }, { "SFX", "Sound effects" }, { "Dialog", "Dialog" } }
        local channel
        channel = S.Dropdown(c, 240, CHANNEL, function(v) YippRouteDB.whisperChannel = v channel:Refresh() end)
        function channel:Refresh() for _, o in ipairs(CHANNEL) do if o[1] == YR.WhisperChannel() then self:SetValue(o[2]) end end end
        Row("Volume channel", channel, "Which of the game's volume sliders the sound follows.")
        Row("Battle.net whispers", S.Switch(c, Opt("whisperBNet"), function(on) YippRouteDB.whisperBNet = on end))
end)

-- Blizzard's bars and windows: the bag bar and micro menu out of the way (BarHide.lua), the talent
-- window (TalentFade.lua: see-through, size, moving it) and the bag windows moved (Movers.lua).
local BuildWindows = QoLPage("windows", function(L, c, Section, Row, Opt)
        Section("Bag bar and micro menu", "hidden, or shown on mouseover", { find = "blizzard bars hide", icon = 133633 })
        local BAR = { { "show", "As Blizzard has it" }, { "hover", "Only under the mouse" }, { "hide", "Hidden" } }
        local function BarDrop(key)
            local d
            d = S.Dropdown(c, 190, BAR, function(v) YR.SetBarHide(key, v) d:Refresh() end)
            function d:Refresh()
                local now = YippRouteDB[key] or "show"
                for _, o in ipairs(BAR) do if o[1] == now then self:SetValue(o[2]) end end
            end
            return d
        end
        Row("Bag bar", BarDrop("bagBar"), "The row of bags at the bottom right. On mouseover: invisible until you point at it. Hidden:"
            .. " removed, and B still opens your bags. It keeps its Edit Mode position and shows while Edit Mode"
            .. " is open.")
        Row("Micro menu", BarDrop("microMenu"), "The row of small menu buttons. Same choices as the bag bar. Your key bindings keep working.")

        Section("Talent window", "see-through and movable", { find = "fade transparent", icon = 136243 })
        Row("Background transparency (percent)", RowSlider(c, 0, 100, 5, YR.TalentFade, YR.SetTalentFade, 260),
            "How much of the talent window's background is faded out. 0: Blizzard's own. Talents, text and"
            .. " buttons stay solid.")
        Row("Sliders on the talent window", S.Switch(c, Opt("talentFadeSlider"), function(on)
            YippRouteDB.talentFadeSlider = on
            YR.TalentFadeApply()
        end), "Adds transparency and scale sliders to the bottom of the talent window.")
        Row("Scale (percent)", RowSlider(c, 50, 150, 1, YR.TalentScale, YR.SetTalentScale, 260),
            "Makes the talent window smaller or larger. 100: Blizzard's size. Not in combat.")
        Row("Move by dragging", S.Switch(c, Opt("talentMove"), function(on)
            YippRouteDB.talentMove = on
            YR.TalentPlace()
        end), "Drag the talent window by its title bar or any empty area. It opens there from then on. The"
            .. " spellbook is the same window and moves with it. Not in combat.")
        Row("Reset position", S.Button(c, "Reset", function() YR.TalentResetPosition() end, nil, 90),
            "Moves the window back to the middle of the screen.")

        Section("Window scale", "100 is Blizzard's size", { find = "window sizes", icon = 134063 })
        Row("Social window (percent)", RowSlider(c, 50, 150, 5, function() return YR.WindowScale("social") end,
            function(v) YR.SetWindowScale("social", v) end, 260),
            "Scale of the friends and guild window.")
        Row("Group finder (percent)", RowSlider(c, 50, 150, 5, function() return YR.WindowScale("lfg") end,
            function(v) YR.SetWindowScale("lfg", v) end, 260), "Scale of the group finder window.")
        Row("Reset scale", S.Button(c, "Reset", function()
            YR.SetWindowScale("social", 100)
            YR.SetWindowScale("lfg", 100)
            YR:RefreshWindow()
        end, nil, 90))

        Section("Bag position", "move the bag windows", { icon = "Interface\\Icons\\INV_Misc_Bag_09" })
        Row("Move the combined bag", S.Switch(c, function() return YippRouteDB.moveBag == true end, function(on)
            YippRouteDB.moveBag = on
            YR.MoverPlace("bag")
        end), "Drag Blizzard's combined bag by its title bar. It opens there from then on. Not in combat.")
        Row("Move the reagent bag", S.Switch(c, function() return YippRouteDB.moveReagentBag == true end, function(on)
            YippRouteDB.moveReagentBag = on
            YR.MoverPlace("reagentBag")
        end), "The same for the reagent bag.")
        Row("Reset positions", S.Button(c, "Reset", function()
            YR.MoverReset("bag")
            YR.MoverReset("reagentBag")
        end, nil, 90), "Both bags open where Blizzard puts them again.")

        Section("Cinematics", "skipped as they start", { find = "skip cinematic intro movie opening", icon = 133885 })
        Row("Skip cinematics", S.Switch(c, Opt("skipCinematic"), function(on) YippRouteDB.skipCinematic = on end),
            "Ends a cinematic as it starts: a new character's opening flight over its zone. Hold Shift as it"
            .. " starts (as you enter the world) to watch that one. On unless you turn it off.")
end)

local function QoLRefresh(key, extra)
    return function()
        for _, ctl in ipairs(qolPages[key].controls) do if ctl.Refresh then ctl:Refresh() end end
        if extra then extra() end
    end
end

-- ---------------------------------------------------------------------------
-- All features: the first page. Everything Headstart does as one card each - its name, one line, and
-- its switch - so nothing has to be found before it can be turned on. A click on a card opens its
-- settings. A feature with more than one switch (or a choice instead of a switch) says where it
-- stands in place of the switch.
--   f: icon, name, desc, page (a QoL page's key), section (the card on that page), get/set (its one
--   switch), state() (the words shown without a switch), go() (opens something else than a QoL page)
-- ---------------------------------------------------------------------------
local front = { cards = {} }
local function HomeFeatures()
    local function Toggle(key, after)
        return function() return YR.OptionSet(key) end, function(on)
            YippRouteDB[key] = on and true or false
            if after then after(on) end
        end
    end
    local function F(icon, name, desc, page, section, get, set)
        return { icon = icon, name = name, desc = desc, page = page, section = section, get = get, set = set }
    end
    local function State(f, state) f.state = state return f end
    -- a setting on a card that holds other things too: not a switch for the whole card (see QoLPage)
    local function Plain(f) f.plain = true return f end
    -- a switch at the top of its own page, and no card on All features
    local function PageOnly(f) f.pageOnly = true return f end
    local function OnOff(on) return on and "On" or "Off" end
    local function HowMany(keys)
        return function()
            local n = 0
            for _, k in ipairs(keys) do if YR.OptionSet(k) then n = n + 1 end end
            return ("%d of %d on"):format(n, #keys)
        end
    end
    local setup = F(134166, "Profiles and bar planner", "Your bars, macros and interface on every character.")
    setup.go = function() YR:ShowSettingsTab("setup") end
    setup.state = function() return OnOff(YR.SetupOn()) end
    local groups = {
        { "Combat",
            F(132349, "Swing timer", "Bars for your auto-attacks.", "swing", "Swing timer",
                function() return YR.SwingDB().on == true end, function(on) YR.SwingDB().on = on YR.SwingApply() end),
            F(237274, "Death recap", "What killed you, shown when you die.", "recap", "Death recap",
                Toggle("deathRecap", function() YR.RecapApply() end)),
            F(133434, "Trinket buttons", "Your trinkets on screen. Click one to swap.", "trinkets", "Trinket buttons",
                Toggle("trinketBar", function(on) YR.ShowTrinketBar(on) end)),
            -- (on its page only: beside "Trinket buttons" on the front page the two read as one thing twice)
            PageOnly(F(133437, "Trinket auto-swap", "Swaps trinkets in by your own rules.", "trinkets", "Trinket auto-swap",
                function() return YippRouteDB.trinketAuto == true end,
                function(on) YippRouteDB.trinketAuto = on if YR.TrinketPaint then YR.TrinketPaint() end end)),
            F(136048, "Health bar", "Your health on a bar of Headstart's own.", "swing", "Health and power bars",
                function() return YR.SwingDB().health == true end,
                function(on) YR.SwingDB().health = on or nil YR.ApplyParts() YR.SwingApply() end),
            F(136048, "Power bar", "Your rage, energy or mana on a bar of Headstart's own.", "swing", "Health and power bars",
                function() return YR.SwingDB().power == true end,
                function(on) YR.SwingDB().power = on or nil YR.ApplyParts() YR.SwingApply() end),
            Plain(F(136048, "Hide spend flash", "No pale block where you spent energy, rage or mana.", "swing", "Health and power bars",
                function() return YippRouteDB.powerFlashOff == true end,
                function(on) YippRouteDB.powerFlashOff = on or nil YR.PowerFlashApply() end)),
            F(136048, "Cast bar", "Your casts on a bar of Headstart's own.", "swing", "Cast bar",
                function() return YR.SwingDB().cast == true end,
                function(on) YR.SwingDB().cast = on or nil YR.ApplyParts() YR.SwingApply() end),
            State(F(132349, "Damage meter skin", "A tidy top bar for the game's damage meter.", "dmgskin", "Damage meter skin"),
                function() return OnOff(YR.DamageSkinMode() ~= "off") end),
        },
        { "Levelling",
            F(236562, "XP bar", "Rested and quest XP on a bar of your own.", "xpbar", "XP bar",
                function() return YR.XPBarOn() end, function(on) YR.XPBarDB().on = on YR.XPBarApply() end),
            F(135805, "Camp icon", "Lit near a camp, or while its buff runs.", "camps", "Camp icon",
                Toggle("camp", function(on) YR.SetCampIcon(on) end)),
            F(132239, "Flight timer", "Time left while you fly.", "camps", "Flight timer",
                Toggle("flightTimer", function(on) YR:SetFlightTimer(on) end)),
            F(134939, "Journey", "Your road logged: distance, time, gold, loot.", "journey", "Journey",
                function() return YippRouteDB.journey ~= false end,
                function(on) if on then YippRouteDB.journey = nil else YippRouteDB.journey = false end YR.ApplyParts() end),
            F(134237, "Instance tracker", "Dungeon entries counted against the limits.", "instances", "Instance tracker",
                Toggle("instanceTrack", function() if YR.InstanceHudApply then YR.InstanceHudApply() end end)),
            State(F(134376, "Reminders", "Trainer, talent points and repairs, said in time.", "reminders", "Reminders"),
                HowMany({ "remindTrainer", "remindTalents", "durability", "levelUpStats" })),
            F(133685, "Craftable items", "Says when you can make stones, oils or bandages.", "reminders", "Craftable items",
                Toggle("craftRemind")),
            F(134441, "Level-up screenshot", "A screenshot every time you level.", "reminders", "Level-up screenshot",
                Toggle("levelShot")),
            F(133741, "Auto-train", "Buys your class's spells as the trainer opens.", "trainer", "Class trainer",
                Toggle("autoTrain", function() YR:SyncRxpTrainer() end)),
        },
        { "Loot & bags",
            F(133784, "Loot feed", "Recent loot, in lines that fade.", "loot", "Loot feed",
                Toggle("lootFeed", function() YR.LootFeedApply() end)),
            F(132739, "Upgrade estimate", "DPS and toughness change on item tooltips.", "gear", "Upgrade estimate",
                Toggle("simTooltip")),
            F(133071, "Upgrade alerts", "Says when loot beats what you wear.", "gear", "Upgrade alerts", Toggle("upgrades")),
            F(133639, "Bank deposit", "Moves mats and recipes to the bank for you.", "bags", "Bank deposit", Toggle("bankAuto")),
            State(F(133471, "Mail to alt", "Sends mats and recipes to another character.", "bags", "Mail to alt"),
                function() return YR.MailRecipient() or "No recipient" end),
            F(133785, "Restock", "Buys reagents, ammo and your list at vendors.", "vendors", "Restock", Toggle("restock")),
            F("Interface\\Icons\\INV_Misc_Bag_09", "Characters", "Bags, bank and gold of your other characters.", "alts",
                "Characters", Toggle("alts")),
        },
        { "Social",
            F(134939, "Chat log", "Search and copy chat, past sessions too.", "chat", "Chat log",
                Toggle("chatLog", function() YR.ChatLogApply() end)),
            State(F(133469, "Whisper sound", "Your own sound for whispers.", "chat", "Whisper sound"),
                function() return OnOff(YippRouteDB.whisperSound ~= nil) end),
            State(F("Interface\\Icons\\INV_Misc_Note_01", "Chat buttons", "Slim or hide the buttons beside chat.", "chat", "Chat buttons"),
                function() return OnOff(YippRouteDB.chatStrip ~= nil or YippRouteDB.chatTTSHide == true or YippRouteDB.chatSocialHide == true) end),
            F(134149, "Invite and Leave buttons", "Group up for a kill, and leave again.", "group", "Invites",
                Toggle("groupBar", function(on) YR.SetGroupBar(on) end)),
            F(133884, "Quest group finder", "Ask chat for a group, see who answers.", "group", "Quest group finder",
                Toggle("questLFG")),
            State(F(134327, "Quest sharing", "Share your quests, accept your party's.", "group", "Quest sharing"),
                function() return OnOff(YippRouteDB.shareAll == true or YR.AcceptFromSet() ~= "off") end),
        },
        { "Interface",
            State(F(133633, "Bag bar and micro menu", "Hidden, or shown on mouseover.", "windows", "Bag bar and micro menu"),
                function() return OnOff(YippRouteDB.bagBar ~= nil or YippRouteDB.microMenu ~= nil) end),
            State(F(136243, "Talent window", "See-through and movable.", "windows", "Talent window"),
                function() return OnOff(YR.TalentFade() > 0 or YR.Option("talentMove")) end),
            State(F(134063, "Window scale", "Blizzard's windows smaller or larger.", "windows", "Window scale"),
                function() return OnOff(type(YippRouteDB.windowScale) == "table" and next(YippRouteDB.windowScale) ~= nil) end),
            State(F(134939, "RestedXP skin", "Another look for RestedXP's window.", "rxpskin", "RestedXP skin"),
                function() return OnOff(YR.RXPSkinMode() ~= "off") end),
            F(133885, "Skip cinematics", "A new character's opening flight, ended as it starts.", "windows", "Cinematics",
                Toggle("skipCinematic")),
            setup,
        },
    }
    -- a feature that is shelved has no card (QuestLFG.lua)
    for _, group in ipairs(groups) do
        for i = #group, 2, -1 do
            if group[i].name == "Quest group finder" and not YR.QuestLFGAvailable then table.remove(group, i) end
        end
    end
    return groups
end

local function HomeGo(f)
    if f.go then f.go() return end
    settings.ShowTab(f.page)
    for _, e in ipairs(settings.index) do
        if e.card and e.key == f.page and e.label == f.section then YR.SettingsGo(e) return end
    end
end

local function HomeCard(parent, f, w)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 58)
    S.Fill(b, S.C.card)
    local edge = S.Border(b, S.C.line)
    local hl = S.Fill(b, S.C.hover, "BACKGROUND", 1)
    hl:Hide()
    local icon = S.Icon(b, f.icon, 24)
    icon:SetPoint("TOPLEFT", 12, -10)
    local name = S.Text(b, 13)
    name:SetPoint("TOPLEFT", 46, -9)
    name:SetWidth(w - 46 - 62)
    name:SetText(f.name)
    local desc = S.Text(b, 11, S.C.muted)
    desc:SetPoint("TOPLEFT", 46, -27)
    desc:SetWidth(w - 46 - 10)
    desc:SetHeight(26)
    desc:SetWordWrap(true)
    desc:SetJustifyV("TOP")
    desc:SetText(f.desc)
    local sw, state
    if f.get then
        sw = S.Switch(b, f.get, function(on) f.set(on) YR:RefreshWindow() end)
        sw:SetPoint("TOPRIGHT", -12, -9)
    else
        state = S.Text(b, 11, S.C.muted)
        state:SetPoint("TOPRIGHT", -12, -11)
        state:SetJustifyH("RIGHT")
    end
    b:SetScript("OnEnter", function() hl:Show() edge:Color(S.C.lineHi) end)
    b:SetScript("OnLeave", function() hl:Hide() edge:Color(S.C.line) end)
    b:SetScript("OnClick", function() HomeGo(f) end)
    function b:Refresh()
        local on
        if sw then
            sw:Refresh()
            on = f.get() and true or false
        else
            local text = f.state()
            state:SetText(text)
            on = text ~= "Off" and text ~= "No recipient" and not text:find("^0 of")
            state:SetTextColor(unpack(on and S.C.accent or S.C.muted))
        end
        on = on and (f.go ~= nil or YR.QoLOn())
        icon:SetDesaturated(not on)
        icon:SetAlpha(on and 1 or 0.6)
        name:SetTextColor(unpack(on and S.C.text or S.C.sub))
    end
    return b
end

-- What is new in this version: the same cards, first on the page, until you hide them.
local NEWS_FOR = "0.10.0-beta6"
local NEWS = { ["Death recap"] = true, ["Characters"] = true, ["Chat log"] = true,
    ["Loot feed"] = true, ["Profiles and bar planner"] = true, ["Journey"] = true, ["Cast bar"] = true }
function YR.HomeNews() return NEWS_FOR, NEWS end

local function BuildHome(page)
    local area = S.ScrollArea(page, CW - 24, CH - 64)
    area:SetPoint("TOPLEFT", 16, -4)
    local c = area.content
    c:SetWidth(CW - 40)
    local gap = 8
    local w = math.floor((CW - 40 - 2 * gap) / 3)
    local groups = HomeFeatures()
    for _, group in ipairs(groups) do
        for i = #group, 2, -1 do if group[i].pageOnly then table.remove(group, i) end end
    end
    local function Grid(parent, list, y)
        for i, f in ipairs(list) do
            local col = (i - 1) % 3
            local card = HomeCard(parent, f, w)
            card:SetPoint("TOPLEFT", col * (w + gap), y)
            front.cards[#front.cards + 1] = card
            if col == 2 or i == #list then y = y - 58 - gap end
        end
        return y
    end
    local function Head(parent, text, y)
        local head = S.Text(parent, 11, S.C.muted)
        head:SetPoint("TOPLEFT", 2, y - 6)
        head:SetText(text:upper())
        return y - 26
    end

    -- everything under the news is one frame, so it moves up as one when the news is hidden
    local body = CreateFrame("Frame", nil, c)
    body:SetSize(CW - 40, 10)
    local newsH, bodyH = 0, 0
    local news
    local newsUp, Lay = false, nil
    -- In a test client (the beta): what you set up is kept in that client's own folder, which the
    -- live game never reads, and nothing moves it for you. Said at the top of this page, with the
    -- way to keep it one click away (Move settings). It is about something to do later, so hiding
    -- it is for a week at a time; on the live game it is never there.
    local BANNER_H = 62
    local banner = CreateFrame("Frame", "HeadstartBetaBanner", c)
    banner:SetSize(CW - 40, BANNER_H)
    S.Fill(banner, S.C.accentD)
    S.Border(banner, S.C.accent)
    local bannerTitle = S.Text(banner, 14)
    bannerTitle:SetPoint("TOPLEFT", 14, -10)
    bannerTitle:SetText("Your beta settings stay in the beta")
    local bannerNote = S.Text(banner, 12, S.C.sub)
    bannerNote:SetPoint("TOPLEFT", 14, -30)
    bannerNote:SetPoint("RIGHT", -300, 0)
    bannerNote:SetJustifyH("LEFT")
    bannerNote:SetWordWrap(true)
    bannerNote:SetText("The live game keeps its own settings, and nothing moves yours there. Before launch, copy one file into the"
        .. " live game's folder, or save your settings as a text.")
    local how = S.Button(banner, "Show me how", function() YR.TransferShow() end, "primary", 130)
    how:SetPoint("RIGHT", -150, 0)
    local later = S.Button(banner, "Hide for a week", function()
        YippRouteDB.betaNoteUntil = time() + 7 * 86400
        Lay()
    end, "ghost", 130)
    later:SetPoint("RIGHT", -12, 0)
    banner:Hide()
    function Lay()
        local up = YR.BetaClient() and time() >= (tonumber(YippRouteDB.betaNoteUntil) or 0)
        local y = 0
        banner:SetShown(up)
        if up then
            banner:ClearAllPoints()
            banner:SetPoint("TOPLEFT", 0, -2)
            y = y - BANNER_H - 10
        end
        if news and newsUp then
            news:ClearAllPoints()
            news:SetPoint("TOPLEFT", 0, y)
            y = y - newsH
        end
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", 0, y)
        c:SetHeight(-y + bodyH + 30)
        if area.UpdateScrollChildRect then area:UpdateScrollChildRect() end
    end
    front.lay = Lay
    if YippRouteDB.newsSeen ~= NEWS_FOR then
        news = CreateFrame("Frame", nil, c)
        news:SetPoint("TOPLEFT", 0, 0)
        news:SetSize(CW - 40, 10)
        local fresh = {}
        for _, group in ipairs(groups) do
            for i = 2, #group do if NEWS[group[i].name] then fresh[#fresh + 1] = group[i] end end
        end
        local y = Head(news, "New in this version", -4)
        local hide = S.Button(news, "Hide", function()
            YippRouteDB.newsSeen = NEWS_FOR
            news:Hide()
            newsUp = false
            Lay()
        end, "ghost", 60)
        hide:SetHeight(20)
        hide:SetPoint("TOPRIGHT", 0, -4)
        y = Grid(news, fresh, y)
        newsH = -y + 6
        news:SetHeight(newsH)
        newsUp = true
    end
    body:SetPoint("TOPLEFT", 0, -newsH)

    local y = -4
    for _, group in ipairs(groups) do
        y = Head(body, group[1], y)
        local list = {}
        for i = 2, #group do list[#list + 1] = group[i] end
        y = Grid(body, list, y) - 4
    end
    -- The look of Headstart's own windows.
    y = Head(body, "Headstart", y)
    local look = CreateFrame("Frame", nil, body)
    look:SetSize(w, 58)
    look:SetPoint("TOPLEFT", 0, y)
    S.Fill(look, S.C.card)
    S.Border(look, S.C.line)
    local name = S.Text(look, 13)
    name:SetPoint("TOPLEFT", 12, -9)
    name:SetText("Accent colour")
    local note = S.Text(look, 11, S.C.muted)
    note:SetPoint("TOPLEFT", 12, -27)
    local options = {}
    for _, a in ipairs(S.ACCENTS) do options[#options + 1] = { a[1], a[2] } end
    local accent
    accent = S.Dropdown(look, 150, options, function(v)
        YippRouteDB.accent = v ~= "ember" and v or nil
        YR:RefreshWindow()
    end)
    accent:SetPoint("TOPRIGHT", -12, -8)
    front.accentWas = YippRouteDB.accent
    function look:Refresh()
        local now = YippRouteDB.accent or "ember"
        for _, a in ipairs(S.ACCENTS) do if a[1] == now then accent:SetValue(a[2]) end end
        local changed = YippRouteDB.accent ~= front.accentWas
        note:SetText(changed and "Reload UI to see it." or "For Headstart's windows.")
        note:SetTextColor(unpack(changed and S.C.gold or S.C.muted))
    end
    front.cards[#front.cards + 1] = look
    bodyH = -y + 58
    body:SetHeight(bodyH)
    Lay()
end

local function RefreshHome()
    for _, card in ipairs(front.cards) do card:Refresh() end
    if front.lay then front.lay() end           -- (the beta's banner: there, or hidden for now)
end
--- The cards on the first page (for the tests): { { name, on or state }, ... } once it has been opened.
function YR.HomeFeatures() return HomeFeatures() end
function YR.SettingsIndex() return settings.index or {} end
--- A QoL page's layout once it is built: its cards, and Fold / FoldAll / AnyShut for them.
function YR.SettingsLayout(key) return qolPages[key] and qolPages[key].L end
--- How far down QoL's menu reaches, and the room it has (for the tests).
function YR.SettingsMenuFits() return settings.navBottom, PH end

-- QoL's menu: All features first, then the pages in five groups by what you are doing. Every page is
-- named after the thing it is about - the name a player would look for - and one thing has one place:
--   Combat        the swing timer, the death recap, trinkets, the damage meter's skin
--   Levelling     the XP bar, camps and flights, reminders, the trainer, the journey, instances
--   Loot & bags   loot, gear, the bank and the mail, vendors, your other characters
--   Social        chat and groups
--   Interface     Blizzard's bars and windows, RestedXP's window
-- Each page says what is on it under its name (its sections, as links: PageHead).
local CATEGORIES = {
    { key = "home", label = "All features", build = BuildHome, refresh = RefreshHome, icon = "Interface\\AddOns\\Headstart\\art\\logo",
      scope = "Every character on this account",
      desc = "Everything Headstart does. Switch a feature on here; click its card for the settings." },
    { group = "Combat" },
    { key = "swing", label = "Combat bars", build = BuildSwing, refresh = QoLRefresh("swing"), icon = "Interface\\Icons\\INV_Sword_04",
      status = function() return YR.SwingOn() or YippRouteDB.powerFlashOff == true end, scope = "Every character on this account",
      desc = "Blizzard's swing bars in a look of your own, and its resource bar without the spend flash." },
    { key = "recap", label = "Death recap", build = BuildRecap, refresh = QoLRefresh("recap"), icon = 237274,
      status = function() return YR.Option("deathRecap") end, scope = "Every character on this account",
      desc = "What killed you and the hits before it, shown when you die." },
    { key = "trinkets", label = "Trinkets & sets", build = BuildTrinkets, refresh = QoLRefresh("trinkets", RefreshTrinkets),
      icon = 133434, status = function() return YR.Option("trinketBar") or YippRouteDB.trinketAuto == true end,
      scope = "Every character; the swap order per character",
      desc = "Trinket buttons, automatic trinket swaps, and key bindings for equipment sets." },
    { key = "dmgskin", label = "Damage meter", build = BuildDamageSkin, refresh = QoLRefresh("dmgskin"), icon = 132349,
      status = function() return YR.DamageSkinMode() ~= "off" end, scope = "Every character on this account",
      desc = "A tidy top bar for the game's damage meter, in Headstart's look or Blizzard's." },
    { group = "Levelling" },
    { key = "xpbar", label = "XP bar", build = BuildXPBar, refresh = QoLRefresh("xpbar"), icon = 236562,
      status = function() return YR.XPBarOn() end, scope = "Every character on this account",
      desc = "Your own experience bar: size, position, colours and text." },
    { key = "camps", label = "Camps & flights", build = BuildCamps, refresh = QoLRefresh("camps"), icon = 135805,
      status = function() return YR.Option("camp") or YR.Option("flightTimer") end, scope = "Every character on this account",
      desc = "The camp icon, and a timer bar while you fly." },
    { key = "reminders", label = "Reminders", build = BuildReminders, refresh = QoLRefresh("reminders"), icon = 134327,
      status = function() return YR.Option("remindTrainer") or YR.Option("remindTalents") or YR.Option("durability") or YR.Option("craftRemind") or YR.Option("levelShot") or YR.Option("levelUpStats") end, scope = "Every character on this account",
      desc = "Said when something needs doing: the trainer, talent points to spend (on screen), repairs, items to craft." },
    { key = "trainer", label = "Trainer", build = BuildTrainer, refresh = function() trainer.refresh() end, icon = 133741,
      status = function() return YR.Option("autoTrain") end, scope = function() return "Every " .. (UnitClass("player") or "character") .. " on this account" end,
      desc = "Buys your class's spells as the trainer opens, as far as your gold goes above what you keep. Asks the first time on each character." },
    { key = "journey", label = "Journey", build = BuildJourney, refresh = QoLRefresh("journey"), icon = 134939,
      status = function() return YippRouteDB.journey ~= false end, scope = "Every character; each has its own journey",
      desc = "Your road logged as you play: distance, time, gold, loot, zones. Told as a story you click through." },
    { key = "instances", label = "Instances", build = BuildInstances, refresh = RefreshInstances, icon = 134237,
      status = function() return YR.Option("instanceTrack") end, scope = "Every character on this account",
      desc = "The dungeons and raids you entered this hour and today, against the limits." },
    { group = "Loot & bags" },
    { key = "loot", label = "Loot", build = BuildLoot, refresh = QoLRefresh("loot"), icon = 133784,
      status = function() return YR.Option("lootFeed") end, scope = "Every character; the log per character",
      desc = "Recent loot as lines on screen, and a log with session totals." },
    { key = "gear", label = "Gear & rewards", build = BuildGear, refresh = QoLRefresh("gear", RefreshRewards), icon = 132739,
      status = function() return YR.Option("simTooltip") or YR.Option("upgrades") end, scope = "Every character; quest rewards per class",
      desc = "Upgrades in your bags pointed out, and quest rewards picked for you." },
    { key = "bags", label = "Bank & mail", build = BuildBags, refresh = QoLRefresh("bags"), icon = 133633,
      status = function() return YR.Option("bankAuto") or YR.Option("bankButton") or YR.Option("mailButton") end, scope = "Every character on this account",
      desc = "Crafting mats and recipes moved to the bank, or mailed to another character." },
    { key = "vendors", label = "Vendors", build = BuildVendors, refresh = QoLRefresh("vendors"), icon = 133785,
      status = function() return YR.Option("restock") end, scope = "Every character on this account",
      desc = "Reagents, ammo and your own list bought back up to the count you keep." },
    { key = "alts", label = "Characters", build = BuildAlts, refresh = QoLRefresh("alts"), icon = "Interface\\Icons\\INV_Misc_Bag_09",
      status = function() return YR.Option("alts") end, scope = "Every character on this account",
      desc = "The bags, bank and gold of your other characters." },
    { group = "Social" },
    { key = "chat", label = "Chat", build = BuildChat, refresh = QoLRefresh("chat"), icon = "Interface\\Icons\\INV_Misc_Note_01",
      status = function() return YippRouteDB.chatStrip ~= nil or YippRouteDB.chatTTSHide == true or YippRouteDB.chatSocialHide == true
          or YippRouteDB.whisperSound ~= nil or YR.Option("chatLog") end, scope = "Every character on this account",
      desc = "A chat log to search and copy from, a whisper sound, and fewer buttons beside chat." },
    { key = "group", label = "Group", build = BuildGroup, refresh = QoLRefresh("group"), icon = 134149,
      status = function() return YR.Option("groupBar") or YR.QuestLFGOn() end, scope = "Every character on this account",
      desc = YR.QuestLFGAvailable and "Invites, quest sharing, and a group finder for your quests." or "Invites and quest sharing." },
    { group = "Interface" },
    { key = "windows", label = "Bars & windows", build = BuildWindows, refresh = QoLRefresh("windows"), icon = 136243,
      status = function() return YR.TalentFade() > 0 or YR.Option("talentMove") or YippRouteDB.moveBag == true or YippRouteDB.moveReagentBag == true
          or YippRouteDB.bagBar ~= nil or YippRouteDB.microMenu ~= nil or YR.Option("skipCinematic")
          or (type(YippRouteDB.windowScale) == "table" and next(YippRouteDB.windowScale) ~= nil) end,
      scope = "Every character on this account",
      desc = "Blizzard's bag bar and micro menu hidden, its windows moved, scaled or see-through, and cinematics skipped." },
    { key = "rxpskin", label = "RestedXP", build = BuildRXPSkin, refresh = QoLRefresh("rxpskin"), icon = 134939,
      status = function() return YR.RXPSkinMode() ~= "off" end, scope = "Every character on this account",
      desc = "Another look for RestedXP's guide window, with your own accent colour." },
}
-- Older names for a page ("qol" was the one long page; the skins and the talent window had their own).
local CATEGORY_ALIAS = { qol = "home", main = "home", start = "home", skins = "rxpskin", talentwin = "windows", death = "recap", characters = "alts" }

-- A main switch at the top of a side menu: its name, the switch at the right, and what it does when you
-- point at it. QoL's menu has Quality of life, Levelling's has Routes.
local function MasterRow(side, width, label, get, set, tip)
    local r = CreateFrame("Frame", nil, side)
    r:SetSize(width - 24, 30)
    S.Fill(r, S.C.card)
    S.Border(r, S.C.line)
    r.text = S.Text(r, 13)
    r.text:SetPoint("LEFT", 10, 0)
    r.text:SetText(label)
    local sw = S.Switch(r, get, function(on) set(on) YR:RefreshWindow() end)
    sw:SetPoint("RIGHT", -8, 0)
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self) S.Tip(self, tip) end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.masters = ui.masters or {}
    ui.masters[#ui.masters + 1] = sw
    return r
end

-- quiet: the caller draws the window itself afterwards
local function ShowTab(key, quiet)
    key = CATEGORY_ALIAS[key] or key
    settings.tab = key
    if quiet then return end
    for _, t in ipairs(CATEGORIES) do
        if t.key then
            t.frame:SetShown(t.key == key)
            t.button:Select(t.key == key)
            if t.key == key then settings.Header(t) end
        end
    end
    S.CloseMenu()
    YR:RefreshWindow()
end
settings.ShowTab = ShowTab

--- Build every page not built yet (the search looks through all of them).
local function BuildAllSettings()
    for _, t in ipairs(CATEGORIES) do
        if t.key and not t.built then
            settings.building = t.key
            t.build(t.frame)
            t.built = true
        end
    end
    settings.building = nil
end

local function LabelOf(key)
    for _, t in ipairs(CATEGORIES) do if t.key == key then return t.label end end
    return key
end

-- A page's header: its icon, name and what it's for, and who the settings on it are for, over a rule.
-- Returns the function that fills it in from a page's entry ({ icon, label, desc, scope }).
local function PageHead(page)
    local frame = CreateFrame("Frame", nil, page)
    frame:SetSize(42, 42)
    frame:SetPoint("TOPLEFT", 20, -11)
    S.Border(frame, S.C.lineHi)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = S.Text(page, 17)
    title:SetPoint("TOPLEFT", frame, "TOPRIGHT", 12, -2)
    local scopeText = S.Text(page, 11, S.C.muted)
    scopeText:SetPoint("TOPRIGHT", page, "TOPRIGHT", -20, -14)
    scopeText:SetJustifyH("RIGHT")
    local desc = S.Text(page, 12, S.C.muted)
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    desc:SetPoint("RIGHT", page, "RIGHT", -20, 0)
    desc:SetJustifyH("LEFT")
    local strip = page:CreateTexture(nil, "BORDER")
    strip:SetPoint("TOPLEFT", 16, -TITLE_H + 4)
    strip:SetPoint("TOPRIGHT", -16, -TITLE_H + 4)
    strip:SetHeight(1)
    S.Set(strip, S.C.line)
    -- The page's sections as a row of links under its description: what is on the page at a glance.
    -- A click scrolls to the section and lights it up for a moment; the link of the section at the
    -- top of the view is the one filled in, and follows as you scroll. Made once per page; only the
    -- page showing has its links up.
    local links = {}        -- [page key] = { chip, ... }
    local function Mark(row, index)
        for i, chip in ipairs(row) do chip:SetOn(i == index) end
    end
    -- At the right of the links, on a page whose cards fold: every card opened, or folded again.
    local allOf, all        -- the page it works on now (its RowPage), and the button
    local function AllPaint()
        local shut
        if allOf then shut = allOf.AnyShut() end
        all:SetShown(shut ~= nil)
        if shut ~= nil then all.text:SetText(shut and "Open all" or "Fold all") end
    end
    all = S.Chip(page, "Open all", function()
        if not allOf then return end
        allOf.FoldAll(allOf.AnyShut() and true or false)
    end)
    all:SetPoint("TOPRIGHT", -20, -54)
    all:Hide()
    -- Which section is at the top of the view now.
    local function AtTop(list)
        local area = list[1].area
        local scroll = area.GetVerticalScroll and area:GetVerticalScroll() or 0
        local range = area.GetVerticalScrollRange and area:GetVerticalScrollRange() or 0
        if range > 0 and scroll >= range - 1 then
            -- at the very bottom the last sections can't reach the top: the lowest one in view counts
            return #list
        end
        local at = 1
        for i, sec in ipairs(list) do if -sec.y <= scroll + 12 then at = i end end
        return at
    end
    local function Links(t)
        for _, row in pairs(links) do for _, chip in ipairs(row) do chip:Hide() end end
        allOf = t.key and qolPages[t.key] and qolPages[t.key].L or nil
        if allOf then allOf.onFold = AllPaint end
        AllPaint()
        local list = t.key and settings.sections and settings.sections[t.key]
        if not list or #list < 2 then return end
        local row = links[t.key]
        if not row then
            row = {}
            links[t.key] = row
            local x = 74
            local jumping
            for i, sec in ipairs(list) do
                local chip = S.Chip(page, sec.title, function()
                    if settings.onJump and settings.onJump[t.key] then settings.onJump[t.key]() end
                    if sec.of and sec.of.open then sec.of.open() end      -- a folded section: opened
                    -- room under the last section, so every section can be brought to the top (a
                    -- short page couldn't be scrolled to its lower sections at all)
                    local content, last = sec.area.content, list[#list]
                    local need = -last.y + (sec.area.GetHeight and sec.area:GetHeight() or 0) - 6
                    if content and content.GetHeight and (content:GetHeight() or 0) < need then content:SetHeight(need) end
                    if sec.area.UpdateScrollChildRect then sec.area:UpdateScrollChildRect() end
                    local range = sec.area.GetVerticalScrollRange and sec.area:GetVerticalScrollRange() or 0
                    jumping = true
                    if sec.area.SetVerticalScroll then sec.area:SetVerticalScroll(math.max(0, math.min(range, -sec.y - 6))) end
                    jumping = false
                    Mark(row, i)            -- the one you clicked, also where the page can't scroll that far
                    -- and the section itself lit for a moment, so the eye finds it
                    local f = sec.frame
                    if f then
                        if not f.jump then
                            f.jump = f:CreateTexture(nil, "BORDER", nil, 7)
                            f.jump:SetAllPoints()
                            S.Set(f.jump, S.C.accentD)
                            -- held a moment, then faded out gently rather than switched off
                            f.jumpFade = f.jump:CreateAnimationGroup()
                            local fade = f.jumpFade:CreateAnimation("Alpha")
                            fade:SetFromAlpha(1)
                            fade:SetToAlpha(0)
                            fade:SetStartDelay(0.35)
                            fade:SetDuration(1.1)
                            fade:SetSmoothing("OUT")
                            f.jumpFade:SetScript("OnFinished", function() f.jump:Hide() end)
                        end
                        f.jumpFade:Stop()
                        f.jump:SetAlpha(1)
                        f.jump:Show()
                        f.jumpFade:Play()
                    end
                end)
                chip:SetPoint("TOPLEFT", x, -54)
                x = x + chip:GetWidth() + 6
                row[i] = chip
            end
            -- scrolled by hand: the link follows
            local area = list[1].area
            if area.HookScript then
                area:HookScript("OnVerticalScroll", function() if not jumping then Mark(row, AtTop(list)) end end)
            end
        end
        for _, chip in ipairs(row) do chip:Show() end
        Mark(row, AtTop(list))
    end
    return function(t)
        icon:SetTexture(t.icon)
        title:SetText(t.label)
        desc:SetText((t.key and not YR.QoLOn())
            and "|cffffb000Quality of life is off, so nothing on this page is running. Turn it on at the top of the menu.|r"
            or (t.desc or ""))
        local scope = type(t.scope) == "function" and t.scope() or t.scope
        scopeText:SetText(scope and ("Saved as you change it\n" .. scope) or "Saved as you change it")
        Links(t)
    end
end

-- QoL: its menu is the window's left side on that tab (ui.sideQ); the page is what is beside it.
local function BuildSettings(page)
    settings.index = {}
    settings.sections = {}          -- [page key] = { { title, y, area }, ... }, filled as a page is built
    settings.onJump = { instances = function() if inst.View then inst.View("settings") end end }
    local nav = ui.sideQ

    -- Find a setting: every row's name and details, on every page.
    local results = CreateFrame("Frame", nil, page)
    results:SetPoint("TOPLEFT", 0, 0)
    results:SetPoint("BOTTOMRIGHT")
    results:SetFrameLevel(page:GetFrameLevel() + 40)
    S.Fill(results, S.C.window)
    results:EnableMouse(true)
    results:Hide()
    results.head = S.Text(results, 13, S.C.sub)
    results.head:SetPoint("TOPLEFT", 22, -18)
    results.items = {}
    local search
    local function Go(e)
        search:SetValue("")
        search:ClearFocus()             -- or the keys you move with would go on typing into it
        results:Hide()
        ShowTab(e.key)
        if e.key == "instances" and inst.View then inst.View("settings") end
        if e.of and e.of.open then e.of.open() end        -- a setting in a folded card: the card opened
        -- a page just built for the search has never been laid out: its length is worked out first
        if e.area.UpdateScrollChildRect then e.area:UpdateScrollChildRect() end
        local range = e.area.GetVerticalScrollRange and e.area:GetVerticalScrollRange() or 0
        if e.area.SetVerticalScroll then e.area:SetVerticalScroll(math.max(0, math.min(range, -e.y - 60))) end
        e.row.flash:Show()
        C_Timer.After(1.6, function() e.row.flash:Hide() end)
    end
    local function Search(text)
        text = strtrim(text or ""):lower()
        if text == "" then results:Hide() return end
        BuildAllSettings()
        local found = {}
        for _, e in ipairs(settings.index) do
            -- what a setting is found by is the same at every keystroke: put together once
            e.hay = e.hay or (e.label .. " " .. (e.tip or "") .. " " .. LabelOf(e.key) .. " " .. (e.find or "")):lower()
            if e.hay:find(text, 1, true) then found[#found + 1] = e end
        end
        results.head:SetText(#found == 0 and ("Nothing matches \"" .. text .. "\"")
            or ("%d setting%s"):format(#found, #found == 1 and "" or "s"))
        for i = 1, math.min(#found, 12) do
            local b = results.items[i]
            if not b then
                b = CreateFrame("Button", nil, results)
                b:SetSize(CW - 44, 40)
                b:SetPoint("TOPLEFT", 16, -44 - (i - 1) * 42)
                b.hl = S.Fill(b, S.C.hover)
                b.hl:Hide()
                b.name = S.Text(b, 13)
                b.name:SetPoint("TOPLEFT", 10, -5)
                b.where = S.Text(b, 11, S.C.muted)
                b.where:SetPoint("TOPLEFT", 10, -22)
                b.where:SetPoint("RIGHT", -10, 0)
                b.where:SetJustifyH("LEFT")
                b.where:SetWordWrap(false)
                b:SetScript("OnEnter", function(self) self.hl:Show() end)
                b:SetScript("OnLeave", function(self) self.hl:Hide() end)
                b:SetScript("OnClick", function(self) Go(self.e) end)
                results.items[i] = b
            end
            local e = found[i]
            b.e = e
            b.name:SetText(strtrim(e.label))
            b.where:SetText(LabelOf(e.key) .. (e.tip and ("  ·  " .. FirstSentence(e.tip)) or ""))
            b:Show()
        end
        for i = math.min(#found, 12) + 1, #results.items do results.items[i]:Hide() end
        results:Show()
        return found
    end
    search = S.Input(nav, { width = NAV_W - 24, placeholder = "Search settings", onChange = Search })
    search:SetPoint("TOPLEFT", 12, -12)
    YR.SettingsSearch, YR.SettingsGo = Search, Go      -- for tests

    -- everything on this tab on or off
    local master = MasterRow(nav, NAV_W, "Quality of life", function() return YR.QoLOn() end, YR.SetQoLOn,
        "Turns every feature in this menu off at once. Your settings are kept and return when you turn it"
        .. " back on. Account-wide. Reload to finish. Also /headstart qol on|off.")
    master:SetPoint("TOPLEFT", 12, -44)
    local y = -82
    for _, t in ipairs(CATEGORIES) do
        if t.group then
            local g = S.Text(nav, 11, S.C.muted)
            g:SetPoint("TOPLEFT", 18, y - 9)
            g:SetText(t.group:upper())
            y = y - 21
        else
            local b = CreateFrame("Button", nil, nav)
            b:SetSize(NAV_W - 16, 22)         -- (22 high: with the Journey page the menu would not end inside the window at 23)
            b:SetPoint("TOPLEFT", 8, y)
            b.bg = S.Fill(b, { 0, 0, 0, 0 })
            b.bar = b:CreateTexture(nil, "ARTWORK")
            b.bar:SetPoint("TOPLEFT") b.bar:SetPoint("BOTTOMLEFT") b.bar:SetWidth(2)
            S.Set(b.bar, S.C.accent)
            b.bar:Hide()
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetSize(20, 20)
            b.icon:SetPoint("LEFT", 10, 0)
            b.icon:SetTexture(t.icon)
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b.text = S.Text(b, 13, S.C.sub)
            b.text:SetPoint("LEFT", 38, 0)
            b.text:SetText(t.label)
            -- on or off at a glance: green while something on the page is switched on
            b.dot = b:CreateTexture(nil, "OVERLAY")
            b.dot:SetSize(7, 7)
            b.dot:SetPoint("RIGHT", -10, 0)
            S.ArtTexture(b.dot, "dot")
            function b:Select(on)
                self.selected = on
                self.bg:SetColorTexture(unpack(on and S.C.accentD or { 0, 0, 0, 0 }))
                self.bar:SetShown(on)
                self.text:SetTextColor(unpack(on and S.C.text or S.C.sub))
                self.icon:SetDesaturated(not on)
                self.icon:SetAlpha(on and 1 or 0.8)
                if t.status then
                    self.dot:Show()
                    -- green only while it is really running: nothing is, with quality of life off
                    self.dot:SetVertexColor(unpack((t.status() and YR.QoLOn()) and S.C.green or S.C.muted))
                else
                    self.dot:Hide()
                end
                -- a page with nothing switched on is dimmed, so what is running stands out
                self:SetAlpha((on or not t.status or (t.status() and YR.QoLOn())) and 1 or 0.6)
            end
            b:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(unpack(S.C.hover)) end end)
            b:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end end)
            b:SetScript("OnClick", function() search:SetValue("") search:ClearFocus() results:Hide() ShowTab(t.key) end)
            t.button = b
            y = y - 22
        end
    end

    settings.navBottom = -y          -- how far down the menu reaches (it has to end inside the window)
    settings.Header = PageHead(page)

    for _, t in ipairs(CATEGORIES) do
        if t.key then
            local f = CreateFrame("Frame", nil, page)
            f:SetPoint("TOPLEFT", 0, -TITLE_H)
            f:SetPoint("BOTTOMRIGHT")
            f:Hide()
            t.frame = f          -- built the first time it's shown (RefreshSettings): a fast first open
        end
    end
    local reload = S.Button(page, "Reload UI", function() ReloadUI() end, nil, 110)
    reload:SetPoint("BOTTOMLEFT", 16, 14)
    local close = S.Button(page, "Close", function() win:Hide() end, nil, 110)
    close:SetPoint("BOTTOMRIGHT", -16, 14)
    -- (how much of Headstart a new install wants is asked by the welcome window: Welcome.lua)
    local welcome = S.Button(page, "Welcome", function() YR.WelcomeShow() end, nil, 110)
    welcome:SetPoint("RIGHT", close, "LEFT", -8, 0)     -- (pages have buttons of their own beside Reload UI)
    welcome.tip = "Opens the welcome window: choose how much of Headstart you want in four questions"
    local arrange = S.Button(page, "Arrange", function()
        if YR.ArrangeOpen() then win:Hide() end
    end, nil, 110)
    arrange:SetPoint("RIGHT", welcome, "LEFT", -8, 0)
    arrange.tip = "Move Headstart's bars, buttons and icons on a grid: drag them, or click one and use the arrow keys. Also /hs move"
    local move = S.Button(page, "Move settings", function() YR.TransferShow() end, nil, 130)
    move:SetPoint("RIGHT", arrange, "LEFT", -8, 0)
    move.tip = "Your settings, bar profiles and routes as a text, to take to another install: the live game, another computer, a friend. Also /headstart transfer"
    settings.tab = "home"
end

local function RefreshSettings()
    win.subtitle:SetText("")
    for _, t in ipairs(CATEGORIES) do
        if t.key then
            t.frame:SetShown(t.key == settings.tab)
            t.button:Select(t.key == settings.tab)     -- and its on/off dot, as the settings are now
            if t.key == settings.tab then
                if not t.built then
                    settings.building = t.key
                    t.build(t.frame)
                    t.built = true
                    settings.building = nil
                end
                settings.Header(t)
                t.refresh()
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Route settings: a Levelling page, under a heading like QoL's pages
-- ---------------------------------------------------------------------------
local ROUTE_PAGE = { icon = 134269, label = "Route settings", scope = "Every character on this account",
    desc = "Routes, run recording, death skips, group play and level splits." }

local function BuildRoutePage(page)
    PageHead(page)(ROUTE_PAGE)
    local f = CreateFrame("Frame", nil, page)
    f:SetPoint("TOPLEFT", 0, -TITLE_H)
    f:SetPoint("BOTTOMRIGHT")
    BuildRouteSettings(f)
end

local function RefreshRoutePage()
    win.subtitle:SetText("")
    RefreshRouteSettings()
end

-- ---------------------------------------------------------------------------
-- A tab that is switched off: what it is, and its switch. Nothing else of the tab is shown.
--   o: icon, title, text, get(), set(on), state() (the line under the title), reload() (whether to
--   offer a reload now)
-- ---------------------------------------------------------------------------
local function OffCard(page, o)
    local f = CreateFrame("Frame", nil, page)
    f:SetSize(600, 250)
    f:SetPoint("CENTER", 0, 30)
    S.Rounded(f, "BACKGROUND", "round"):SetVertexColor(unpack(S.C.card))
    S.Rounded(f, "BORDER", "roundline"):SetVertexColor(unpack(S.C.lineHi))
    local icon = S.Icon(f, o.icon, 40)
    icon:SetPoint("TOPLEFT", 24, -24)
    local title = S.Text(f, 18)
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 14, -1)
    title:SetText(o.title)
    local state = S.Text(f, 12, S.C.muted)
    state:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    local sw = S.Switch(f, o.get, function(on) o.set(on) YR:RefreshWindow() end)
    sw:SetPoint("TOPRIGHT", -24, -32)
    local body = S.Text(f, 13, S.C.sub)
    body:SetPoint("TOPLEFT", 24, -86)
    body:SetPoint("RIGHT", -24, 0)
    body:SetWordWrap(true)
    body:SetJustifyV("TOP")
    body:SetSpacing(3)
    body:SetText(o.text)
    local reload = S.Button(f, "Reload UI", function() ReloadUI() end, "primary", 110)
    reload:SetPoint("BOTTOMRIGHT", -24, 20)
    function f:Refresh()
        sw:Refresh()
        state:SetText(o.state())
        reload:SetShown(o.reload ~= nil and o.reload() and true or false)
    end
    return f
end

-- Levelling with the routes off: only that.
local routesOff
local routesWere                -- the routes switch as it was when the window was made (a change takes a reload)
local function BuildRoutesOff(page)
    routesOff = OffCard(page, { icon = "Interface\\Icons\\INV_Misc_Map_01", title = "Levelling routes",
        text = "Records your runs and saves them as your own RestedXP routes. Includes a route editor, level"
            .. " splits, and help keeping and buying the items a route needs.\n\nWhile off, none of it runs and"
            .. " nothing is shown. Account-wide. Takes a /reload.",
        get = function() return YR.RoutesOn() end, set = YR.SetRoutesOn,
        state = function() return YR.RoutesOn() and "On - reload to load the routes" or "Off" end,
        reload = function() return YR.RoutesOn() ~= routesWere end })
end

-- Character setup: its own tab. On: the page. Off (or its addon not there): only the switch.
local SETUP_PAGE = { icon = 134166, label = "Character setup",
    scope = function() return "Every " .. (CLASS_NAME[ViewClass()] or "character") .. "; chat and Edit Mode for all" end,
    desc = "Profiles for your action bars, and your bars, macros and interface on every character." }
local setupTab = {}
local function BuildSetupPage(page)
    setupTab.head = PageHead(page)
    setupTab.inner = CreateFrame("Frame", nil, page)
    setupTab.inner:SetPoint("TOPLEFT", 0, -TITLE_H)
    setupTab.inner:SetPoint("BOTTOMRIGHT")
    setupTab.off = OffCard(page, { icon = 134166, title = "Character setup",
        text = "Profiles for your action bars. Plan every button ahead, including spells you haven't learned, and"
            .. " apply your bars, macros, key bindings, chat windows and Edit Mode layout to a new character in"
            .. " one click. Can be undone.\n\nWhile off, none of it is loaded and nothing is ever placed on your"
            .. " bars.",
        get = function() return YR.SetupOn() end, set = YR.SetSetupOn,
        state = function()
            if YR.SetupOn() and not YR.SetupLoaded() then return "On, but the Headstart_Setup addon is missing or disabled" end
            return YR.SetupOn() and "On" or "Off"
        end })
end

local function RefreshSetupPage()
    win.subtitle:SetText("")
    local on = YR.SetupOn() and YR.SetupLoaded()
    if on and not setupTab.built then
        setupTab.built = true
        BuildSetup(setupTab.inner)
    end
    setupTab.head(SETUP_PAGE)
    setupTab.inner:SetShown(on)
    setupTab.off:SetShown(not on)
    setupTab.off:Refresh()
    if on then RefreshSetup() end
end

-- ---------------------------------------------------------------------------
-- The window: two tabs at the top, QoL and Levelling, each with its own menu down the left
-- ---------------------------------------------------------------------------
-- tab: which top tab a page is under. nav: shown in Levelling's menu (the routes page is opened from
-- the route list under it instead).
local PAGES = {
    { key = "routes", tab = "levelling", build = BuildRoutes, refresh = RefreshRoutes },
    { key = "where", tab = "levelling", nav = true, label = "Where next?", icon = "Interface\\Icons\\Ability_Hunter_Pathfinding",
      build = YR.BuildWherePage, refresh = function() win.subtitle:SetText("") YR.RefreshWherePage() end },
    { key = "run", tab = "levelling", nav = true, label = "This run", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
      build = BuildRun, refresh = RefreshRun },
    { key = "share", tab = "levelling", nav = true, label = "Share", icon = "Interface\\Icons\\INV_Letter_15", build = BuildShare,
      refresh = function() win.subtitle:SetText("") end },
    { key = "route", tab = "levelling", nav = true, label = "Route settings", icon = 134269, build = BuildRoutePage,
      refresh = RefreshRoutePage },
    { key = "routesoff", tab = "levelling", build = BuildRoutesOff, refresh = function() win.subtitle:SetText("") routesOff:Refresh() end },
    { key = "settings", tab = "qol", build = BuildSettings, refresh = RefreshSettings },
    { key = "setup", tab = "setup", build = BuildSetupPage, refresh = RefreshSetupPage },
}
local PAGE_TAB = {}
for _, p in ipairs(PAGES) do PAGE_TAB[p.key] = p.tab end
local lastLevelling          -- the Levelling page last shown, for coming back to that tab
function YR.WindowTab() return PAGE_TAB[current] end      -- for the tests

local function Show(key)
    if key == "character" then key = "setup" end        -- its name while it was a QoL page
    -- Levelling with the routes off is one page: the switch
    if PAGE_TAB[key] == "levelling" and not YR.RoutesOn() then key = "routesoff" end
    if not PAGE_TAB[key] then           -- a QoL page by its own name ("instances", "camps", ...)
        ShowTab(key, true)
        key = "settings"
    end
    current = key
    local tab = PAGE_TAB[key]
    if tab == "levelling" and key ~= "routesoff" then lastLevelling = key end
    S.CloseMenu()
    ui.sideL:SetShown(tab == "levelling")
    ui.levelBody:SetShown(YR.RoutesOn())
    ui.sideQ:SetShown(tab == "qol")
    ui.sideS:SetShown(tab == "setup")
    for name, b in pairs(ui.topTabs) do b:Select(name == tab) end
    for _, p in ipairs(PAGES) do
        -- a page is made the first time it is shown (the route editor and QoL with the window)
        if p.key == key and not p.built then
            p.built = true
            p.build(pages[p.key])
        end
        pages[p.key]:SetShown(p.key == key)
        if p.button then p.button:Select(p.key == key) end
    end
    YR:RefreshWindow()
end

-- Open QoL on one of its pages ("camps", "bags", ..., "character", "trainer"), or Route settings ("route").
function YR:ShowSettingsTab(key)
    settings.viewClass = nil          -- this character's class
    if key == "route" or key == "setup" or key == "character" then YR:ToggleWindow(key) return end
    YR:ToggleWindow(CATEGORY_ALIAS[key] or key or "settings")
end

-- The two tabs: one switch in the middle of the title bar, the half that's showing filled in. Each
-- half has its icon and name; the other half lights up under the mouse.
local SEG_W, SEG_H = 140, 28
local function Segment(parent, label, icon)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SEG_W, SEG_H)
    b.bg = S.Rounded(b, "BACKGROUND", "round", 1)
    b.text = S.Text(b, 13, S.C.sub)
    b.text:SetPoint("CENTER", 12, 0)
    b.text:SetText(label)
    b.icon = S.Icon(b, icon, 16)
    b.icon:SetPoint("RIGHT", b.text, "LEFT", -8, 0)
    local function Paint(self, over)
        local on = self.selected
        if on then
            self.bg:SetVertexColor(unpack(S.C.accent))
        else
            self.bg:SetVertexColor(1, 1, 1, over and 0.08 or 0)
        end
        self.text:SetTextColor(unpack(on and S.C.onAccent or over and S.C.text or S.C.sub))
        self.icon:SetDesaturated(not on)
        self.icon:SetAlpha(on and 1 or 0.7)
    end
    function b:Select(on)
        self.selected = on
        Paint(self, false)
    end
    b:SetScript("OnEnter", function(self) Paint(self, true) end)
    b:SetScript("OnLeave", function(self) Paint(self, false) end)
    b:Select(false)
    return b
end

-- Both halves in their track, centred in the title bar (head). Returns { levelling = , qol = }.
local function TopTabs(head, onLevelling, onQoL, onSetup)
    local track = CreateFrame("Frame", nil, head)
    track:SetSize(SEG_W * 3 + 6, SEG_H + 6)
    track:SetPoint("CENTER", head, "CENTER", 0, 0)
    track:SetFrameLevel(head:GetFrameLevel() + 2)      -- over the bar you drag the window by
    S.Rounded(track, "BACKGROUND", "round"):SetVertexColor(unpack(S.C.field))
    S.Rounded(track, "BORDER", "roundline"):SetVertexColor(unpack(S.C.lineHi))
    local qol = Segment(track, "QoL", "Interface\\Icons\\Trade_Engineering")
    qol:SetPoint("LEFT", 3, 0)
    qol:SetScript("OnClick", onQoL)
    local levelling = Segment(track, "Levelling", "Interface\\Icons\\INV_Misc_Map_01")
    levelling:SetPoint("LEFT", qol, "RIGHT", 0, 0)
    levelling:SetScript("OnClick", onLevelling)
    local setupSeg = Segment(track, "Character setup", 134166)
    setupSeg:SetPoint("RIGHT", -3, 0)
    setupSeg:SetScript("OnClick", onSetup)
    return { levelling = levelling, qol = qol, setup = setupSeg }, track
end

local function NavButton(parent, label, icon, y, indent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SIDE - 16, indent and 22 or 30)
    b:SetPoint("TOPLEFT", 8, y)
    b.bg = S.Fill(b, { 0, 0, 0, 0 })
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("TOPLEFT") b.bar:SetPoint("BOTTOMLEFT") b.bar:SetWidth(2)
    S.Set(b.bar, S.C.accent)
    b.bar:Hide()
    local x = indent and 36 or 10
    if icon then
        local i = S.Icon(b, icon, 18)
        i:SetPoint("LEFT", 10, 0)
        x = 36
    end
    b.text = S.Text(b, indent and 12 or 14, indent and S.C.sub or S.C.text)
    b.text:SetPoint("LEFT", x, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetText(label)
    function b:Select(on)
        self.selected = on
        self.bg:SetColorTexture(unpack(on and (indent and S.C.hover or S.C.accentD) or { 0, 0, 0, 0 }))
        self.bar:SetShown(on and not indent)
        if indent then self.text:SetTextColor(unpack(on and S.C.accent or S.C.sub)) end
    end
    b:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(unpack(S.C.hover)) end end)
    b:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end end)
    return b
end

-- The routes this character follows: reachable from its race's start (Guides.lua) and not for
-- another class ("<< Alliance Hunter" in the header; "!Hunter" excludes).
local CLASS_WORDS = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true,
    MAGE = true, WARLOCK = true, DRUID = true }
local function ForClass(key, class)
    local head = ("\n" .. (YR:GuideText(key) or "")):match("\n<<%s*([^\n]+)")
    if not head then return true end
    local wanted = false
    for word in head:gmatch("[!%a]+") do
        local neg, name = word:match("^(!?)(%a+)$")
        name = name and name:upper()
        if name and CLASS_WORDS[name] then
            if neg == "!" then
                if name == class then return false end
            else
                wanted = wanted or {}
                wanted[name] = true
            end
        end
    end
    return not wanted or wanted[class] == true
end

function YR.MyRoutes()
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    local set = {}
    for key in pairs(YR:RoutesFor(race)) do
        if ForClass(key, class) then set[key] = true end
    end
    return set
end

local function RouteButton(parent, key, y)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SIDE - 16, 24)
    b:SetPoint("TOPLEFT", 8, y)
    b.bg = S.Fill(b, { 0, 0, 0, 0 })
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("TOPLEFT") b.bar:SetPoint("BOTTOMLEFT") b.bar:SetWidth(2)
    S.Set(b.bar, S.C.accent)
    b.bar:Hide()
    local name = YR.GuideName(key)
    local range, zone = name:match("^(%d+%-%d+)%s+(.+)$")
    zone = (zone or name):gsub("%s*%(Launch%)", "")
    b.from = tonumber(range and range:match("^%d+")) or 0
    b.full, b.short = zone, (zone:gsub("%s*%b()", ""))   -- "Loch Modan (Dwarf/Gnome)" -> "Loch Modan"
    local badge = CreateFrame("Frame", nil, b)
    badge:SetSize(38, 16)
    badge:SetPoint("LEFT", 12, 0)
    b.badgeBg = S.Fill(badge, S.C.accentD)
    b.badge = S.Text(badge, 12, S.C.accent)
    b.badge:SetPoint("CENTER")
    b.badge:SetText(range or "")
    b.text = S.Text(b, 12, S.C.sub)
    b.text:SetPoint("LEFT", badge, "RIGHT", 8, 0)
    b.text:SetPoint("RIGHT", -16, 0)
    b.text:SetText(zone)
    b.dot = b:CreateTexture(nil, "OVERLAY")
    b.dot:SetSize(10, 10)
    b.dot:SetPoint("RIGHT", -6, 0)
    S.ArtTexture(b.dot, "dot")
    b.dot:SetVertexColor(unpack(S.C.gold))
    b.key = key
    function b:Select(on)
        self.selected = on
        self.bg:SetColorTexture(unpack(on and S.C.accentD or { 0, 0, 0, 0 }))
        self.bar:SetShown(on)
        self.text:SetTextColor(unpack(on and S.C.text or S.C.sub))
    end
    -- gold: your edited version; blue: edited, and a newer shipped version is waiting
    function b:Mark()
        self.dot:SetShown(YR:IsCustom(self.key))
        self.dot:SetVertexColor(unpack(YR:HasUpdate(self.key) and S.C.accent or S.C.gold))
    end
    b:SetScript("OnEnter", function(self)
        if not self.selected then self.bg:SetColorTexture(unpack(S.C.hover)) end
        S.Tip(self, name .. (YR:HasUpdate(self.key) and "\nYour version (edited). A newer shipped version is waiting"
            or YR:IsCustom(self.key) and "\nYour version (edited)" or "\nAs shipped"))
    end)
    b:SetScript("OnLeave", function(self)
        if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end
        GameTooltip:Hide()
    end)
    b:Mark()
    return b
end

local function Build()
    win = S.Window("HeadstartWindow", W, H, "Headstart")
    -- The tabs in the middle of the title bar; what a page says about itself (win.subtitle) stays
    -- after the title, cut short where the tabs begin.
    local track
    ui.topTabs, track = TopTabs(win.title:GetParent(),
        function() Show(lastLevelling or ((YR.RoutesOn() and #YR.shipped > 0) and "routes" or "route")) end,
        function() Show("settings") end, function() Show("setup") end)
    win.subtitle:SetPoint("RIGHT", track, "LEFT", -16, 0)
    win.subtitle:SetJustifyH("LEFT")
    win.subtitle:SetWordWrap(false)
    -- One menu down the left per tab: Levelling's (SIDE wide), QoL's (NAV_W wide, BuildSettings fills it).
    local function Side(width, color)
        local f = CreateFrame("Frame", nil, win)
        f:SetPoint("TOPLEFT", 1, -HEAD)
        f:SetPoint("BOTTOMLEFT", 1, 1)
        f:SetWidth(width)
        S.Fill(f, color)
        local rule = f:CreateTexture(nil, "BORDER")
        rule:SetPoint("TOPRIGHT") rule:SetPoint("BOTTOMRIGHT") rule:SetWidth(1)
        S.Set(rule, S.C.line)
        f:Hide()
        return f
    end
    local side = Side(SIDE, S.C.side)
    ui.sideL, ui.sideQ, ui.sideS = side, Side(NAV_W, S.C.side), Side(NAV_W, S.C.side)
    routesWere = YR.RoutesOn()
    -- Character setup's side: its switch, and what the tab is
    local setupRow = MasterRow(ui.sideS, NAV_W, "Character setup", function() return YR.SetupOn() end, YR.SetSetupOn,
        "On: the bar planner, and a main's bars, macros and interface on a new character. Off: none of it is"
        .. " loaded, and nothing is ever placed on your bars for you. For the whole account")
    setupRow:SetPoint("TOPLEFT", 12, -12)
    local setupSays = S.Text(ui.sideS, 12, S.C.muted)
    setupSays:SetPoint("TOPLEFT", 16, -58)
    setupSays:SetWidth(NAV_W - 32)
    setupSays:SetWordWrap(true)
    setupSays:SetJustifyV("TOP")
    setupSays:SetSpacing(3)
    setupSays:SetText("Each class has its own bar profiles."
        .. "\n\nThe interface (chat windows, Edit Mode, game settings) is shared by all classes."
        .. "\n\n/headstart plan opens the bar planner.")
    pages = {}
    ui.routeTabs = {}
    -- The routes switch, Levelling's pages, then every route in a list that scrolls (more routes than room)
    local routes = MasterRow(side, SIDE, "Routes", function() return YR.RoutesOn() end, YR.SetRoutesOn,
        "On: your routes are loaded into RestedXP, and what they need is kept in your bags and bought for you."
        .. " Off: none of that. For the whole account; takes a /reload (/headstart routes on|off)")
    routes:SetPoint("TOPLEFT", 12, -12)
    local y = -50
    -- everything under the switch sits on a frame of its own: with the routes off only the switch shows
    side = CreateFrame("Frame", nil, side)
    side:SetAllPoints()
    ui.levelBody = side
    for _, p in ipairs(PAGES) do
        if p.nav then
            p.button = NavButton(side, p.label, p.icon, y)
            p.button:SetScript("OnClick", function() Show(p.key) end)
            y = y - 34
        end
    end
    local label = S.Text(side, 11, S.C.muted)
    label:SetPoint("TOPLEFT", 20, y - 8)
    local listTop = y - 26
    local list = S.ScrollArea(side, SIDE, H - HEAD + listTop - 40)
    list:SetPoint("TOPLEFT", 0, listTop)
    for _, g in ipairs(YR.shipped) do
        local sub = RouteButton(list.content, g.key, 0)
        sub:SetScript("OnClick", function()
            Open(g.key)
            for _, t in ipairs(ui.routeTabs) do t:Select(t == sub) end
            Show("routes")
        end)
        ui.routeTabs[#ui.routeTabs + 1] = sub
    end
    table.sort(ui.routeTabs, function(a, b) return a.from < b.from or (a.from == b.from and a.full < b.full) end)
    -- "Mine" (default): only the routes this character's race and class follow, without their
    -- "(Dwarf/Gnome)" qualifiers; "All": every route. The one open in the editor always shows.
    local toggle = CreateFrame("Button", nil, side)
    toggle:SetSize(60, 16)
    toggle:SetPoint("TOPRIGHT", side, "TOPRIGHT", -12, y - 6)
    toggle.text = S.Text(toggle, 11, S.C.accent)
    toggle.text:SetPoint("RIGHT")
    -- Level brackets (1-10, 10-20, 20-30 ...) that fold: a route sits in the bracket it starts in.
    -- Unless you opened or closed one yourself (YippRouteDB.routeBrackets[from] = true/false), only
    -- the bracket of the route open in the editor is open.
    local headers = {}
    local function Header(from)
        if headers[from] then return headers[from] end
        local h = CreateFrame("Button", nil, list.content)
        h:SetSize(SIDE - 16, 20)
        h.text = S.Text(h, 11, S.C.muted)
        h.text:SetPoint("LEFT", 26, 0)
        h.text:SetText(("LEVELS %d-%d"):format(math.max(from, 1), from + 10))
        h.arrow = h:CreateTexture(nil, "ARTWORK")
        h.arrow:SetSize(10, 10)
        h.arrow:SetPoint("LEFT", 10, 0)
        S.ArtTexture(h.arrow, "down")
        h.arrow:SetVertexColor(unpack(S.C.muted))
        h:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(S.C.text)) end)
        h:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(S.C.muted)) end)
        h:SetScript("OnClick", function(self)
            YippRouteDB.routeBrackets = YippRouteDB.routeBrackets or {}
            YippRouteDB.routeBrackets[from] = not self.open
            ui.LayoutRoutes()
        end)
        headers[from] = h
        return h
    end
    function ui.LayoutRoutes()
        local mine = YR.MyRoutes()
        local all = YippRouteDB.allRoutes or not next(mine)
        -- Headstart comes without routes: until you save a run as one or import one, say how
        local none = #ui.routeTabs == 0
        label:SetText(none and "NO ROUTES YET" or all and "ALL ROUTES" or "YOUR ROUTES")
        toggle.text:SetText(all and "Mine" or "Show all")
        toggle:SetShown(not none)
        if none and not ui.noRoutes then
            ui.noRoutes = S.Text(side, 12, S.C.muted)
            ui.noRoutes:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -10)
            ui.noRoutes:SetWidth(SIDE - 36)
            ui.noRoutes:SetJustifyH("LEFT")
            ui.noRoutes:SetText("Play with Record runs on, then Save as route under This run. Or paste a route in under Share.")
        end
        if ui.noRoutes then ui.noRoutes:SetShown(none) end
        local chosen = YippRouteDB.routeBrackets or {}
        local current
        for _, b in ipairs(ui.routeTabs) do
            if b.selected then current = math.floor(b.from / 10) * 10 end
        end
        for _, h in pairs(headers) do h:Hide() end
        local ry, bracket, open = 0, nil, true
        for _, b in ipairs(ui.routeTabs) do
            local on = all or mine[b.key] or b.selected
            if on then
                local from = math.floor(b.from / 10) * 10
                if from ~= bracket then
                    bracket = from
                    if chosen[from] ~= nil then open = chosen[from] else open = current == nil or current == from end
                    local h = Header(from)
                    h.open = open
                    h.arrow:SetRotation(open and 0 or math.pi / 2)
                    h:ClearAllPoints()
                    h:SetPoint("TOPLEFT", 8, ry)
                    h:Show()
                    ry = ry - 22
                end
                on = open
            end
            b:SetShown(on)
            if on then
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 8, ry)
                b.text:SetText(all and b.full or b.short)
                ry = ry - 26
            end
        end
        list.content:SetHeight(-ry + 8)
    end
    toggle:SetScript("OnClick", function()
        YippRouteDB.allRoutes = not YippRouteDB.allRoutes or nil
        ui.LayoutRoutes()
    end)
    ui.LayoutRoutes()
    for _, p in ipairs(PAGES) do
        local page = CreateFrame("Frame", nil, win)
        page:SetPoint("TOPLEFT", p.tab == "levelling" and SIDE or NAV_W, -HEAD)
        page:SetPoint("BOTTOMRIGHT")
        pages[p.key] = page
        -- the route editor (a route is opened in it below) and QoL (its menu) with the window; Where
        -- next, This run, Share and Route settings the first time each is shown
        if p.key == "routes" or p.key == "settings" then
            p.built = true
            p.build(page)
        end
    end
    local version = S.Text(win, 11, S.C.muted)
    version:SetPoint("RIGHT", win.close, "LEFT", -12, 0)
    local meta = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Headstart", "Version")
    version:SetText(meta and ("v" .. meta) or "")
    -- open on the route this character is on: the one RestedXP has loaded if it's ours, else the
    -- starting route for its race, else the first
    local key = YR.shipped[1] and YR.shipped[1].key
    local current = type(RXP) == "table" and type(RXP.currentGuide) == "table" and RXP.currentGuide.name
    local _, race = UnitRace("player")
    local byRace = ({ Human = "northshire", NightElf = "shadowglen", Dwarf = "coldridge", Gnome = "coldridge" })[race]
    for _, g in ipairs(YR.shipped) do
        if g.key == byRace then key = g.key end
    end
    -- RestedXP pads the level range ("01-05 Coldridge Valley"): compare without leading zeros
    local function Plain(s) return (s:gsub("%f[%d]0+(%d)", "%1")) end
    for _, g in ipairs(YR.shipped) do
        if type(current) == "string" and Plain(current) == Plain(YR.GuideName(g.key)) then key = g.key end
    end
    if key then
        Open(key)
        for _, t in ipairs(ui.routeTabs) do t:Select(t.key == key) end
        if ui.LayoutRoutes then ui.LayoutRoutes() end
    end
end

function YR:RefreshWindow()
    if not (win and win:IsShown()) then return end
    for _, sw in ipairs(ui.masters or {}) do sw:Refresh() end
    for _, p in ipairs(PAGES) do
        if p.key == current then p.refresh() end
    end
end

-- /hs: Settings, or closes the window when Settings is already open.
function YR:ToggleSettings()
    if win and win:IsShown() and current == "settings" then win:Hide() return end
    YR:ToggleWindow("settings")
end

function YR:ToggleWindow(page)
    if not win then Build() end
    if win:IsShown() and not page then win:Hide() return end
    win:Show()
    -- first open: QoL (Headstart is the QoL addon first; the routes are a tab away)
    Show(page or current or "settings")
end

YR.windowLoaded = true          -- the window's functions above have taken the place of Core.lua's stand-ins
