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
local _, YR = ...
local S = YR.Style

local W, H, SIDE, HEAD = 1140, 680, 180, 48
local PW, PH = W - SIDE, H - HEAD          -- a Levelling page: what is left beside its menu
-- QoL's menu is wider; its pages are what is left beside it, under a heading (as Route settings).
local NAV_W, TITLE_H = 210, 64
local CW, CH = W - NAV_W, PH - TITLE_H
local LIST_W, ROW = 480, 24
local win, pages, current
local edit = { key = nil, header = nil, steps = nil, parsed = {}, dirty = false, sel = nil, line = nil, filter = "" }
local ui = {}

StaticPopupDialogs["HEADSTART_RELOAD"] = {
    text = "Headstart: reload so RestedXP gets the changed route?",
    button1 = "Reload",
    button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

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
    text = "Headstart: throw away your edits to %s and use the shipped route?",
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
local ZEBRA = { 0.095, 0.105, 0.125, 1 }

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
            self.bg:SetColorTexture(unpack(on and S.C.accentD or { 0, 0, 0, 0 }))
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
        local dialog = StaticPopup_Show("HEADSTART_REVERT", YR.GuideName(edit.key))
        if dialog then dialog.data = edit.key end
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
    run.record = S.Toggle(page, "Record this run", function() return YippRouteDB.logging end,
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
    run.actions = YR:RunActions()
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
local ROW_H, ROW_TIP_H, CARD_HEAD = 34, 48, 40

--- The first sentence of a row's details (the line under its label).
local function FirstSentence(tip)
    return tip:match("^(.-[%.!?])%s+%S") or tip
end

local function RowPage(page, controls, bottom)
    local area = S.ScrollArea(page, CW - 24, CH - (bottom or 64))
    area:SetPoint("TOPLEFT", 16, -4)
    local c = area.content
    c:SetWidth(CW - 40)
    local L = { c = c, colW = math.min(CW - 40, 680), y = -6, col = 0, rowIndex = 0, area = area }
    local card       -- the card rows go into now: { frame, top, rows }

    local function EndCard()
        if not card then return end
        card.frame:SetHeight(card.top - L.y + 6)
        L.y = L.y - 6 - 14
        card = nil
    end
    function L.Break() EndCard() end

    --- Start a card. opts: icon (a texture or file ID), master = { get, set } for its one switch.
    function L.Section(title, note, opts)
        EndCard()
        opts = opts or {}
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
        local x = 14
        if opts.icon then
            local ic = f:CreateTexture(nil, "ARTWORK")
            ic:SetSize(22, 22)
            ic:SetPoint("TOPLEFT", 12, -9)
            ic:SetTexture(opts.icon)
            ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            x = 44
        end
        local t = S.Text(f, 14)
        t:SetPoint("TOPLEFT", x, -12)
        t:SetText(title)
        if note then
            local n = S.Text(f, 11, S.C.muted)
            n:SetPoint("LEFT", t, "RIGHT", 10, 0)
            n:SetPoint("RIGHT", f, "RIGHT", opts.master and -60 or -14, 0)
            n:SetJustifyH("LEFT")
            n:SetWordWrap(false)
            n:SetText(note)
        end
        local rowsHere = {}
        card = { frame = f, top = L.y, rows = rowsHere }
        if opts.master then
            local get, set = opts.master[1], opts.master[2]
            local function Dim()
                local on = get() and true or false
                for _, r in ipairs(rowsHere) do r:SetAlpha(on and 1 or 0.45) end
            end
            local sw = S.Switch(f, get, function(on) set(on) Dim() end)
            sw:SetPoint("TOPRIGHT", -14, -11)
            controls[#controls + 1] = sw
            controls[#controls + 1] = { Refresh = Dim }
        end
        L.y = L.y - CARD_HEAD
        L.rowIndex = 0
        return f
    end

    -- The whole row lights up under the mouse, the control included. A row with details has an (i)
    -- after its name: pointing at the (i) shows them, and a click on it keeps them open.
    local rows, hot = {}, nil
    local function Paint(r)
        r.hl:SetShown(r == hot)
        if r.infoBtn then
            r.infoBtn.icon:SetVertexColor(unpack((r.infoBtn:IsMouseOver() or S.IsPinned(r)) and S.C.accent or S.C.muted))
        end
    end
    local wait = 0
    area:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - (elapsed or 1)          -- twenty looks a second are plenty for a highlight
        if wait > 0 then return end
        wait = 0.05
        local now
        if area:IsMouseOver() then
            for _, r in ipairs(rows) do
                if r:IsMouseOver() then now = r break end
            end
        end
        if now ~= hot then
            local was = hot
            hot = now
            if was then Paint(was) end
            if now then Paint(now) end
        end
    end)
    area:SetScript("OnHide", function()
        S.Unpin()
        hot = nil
        for _, r in ipairs(rows) do Paint(r) end
    end)
    function L.Row(label, control, tip)
        local h = tip and ROW_TIP_H or ROW_H
        local inset = card and 1 or 0
        local r = CreateFrame("Frame", nil, c)
        r:SetSize(L.colW - 2 * inset, h)
        r:SetPoint("TOPLEFT", inset, L.y)
        if card then
            r:SetFrameLevel(card.frame:GetFrameLevel() + 2)
            local line = r:CreateTexture(nil, "BORDER")
            line:SetPoint("TOPLEFT", 12, 0)
            line:SetPoint("TOPRIGHT", -12, 0)
            line:SetHeight(1)
            S.Set(line, S.C.line)
            card.rows[#card.rows + 1] = r
        else
            S.Fill(r, (L.rowIndex % 2 == 0) and S.C.card or ZEBRA)
        end
        r.hl = S.Fill(r, S.C.hover, "BACKGROUND", 1)
        r.hl:Hide()
        r.flash = S.Fill(r, S.C.accentD, "BACKGROUND", 2)
        r.flash:Hide()
        local l = S.Text(r, 13)
        if tip then l:SetPoint("TOPLEFT", 14, -9) else l:SetPoint("LEFT", 14, 0) end
        l:SetText(label)
        r.control, r.infoBtn = control, false
        if tip then
            local b = CreateFrame("Button", nil, r)
            b:SetSize(20, 20)
            b:SetPoint("LEFT", l, "RIGHT", 4, 0)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetSize(14, 14)
            b.icon:SetPoint("CENTER")
            S.ArtTexture(b.icon, "info")
            b:SetScript("OnEnter", function() S.ShowInfo(r, label, tip) Paint(r) end)
            b:SetScript("OnLeave", function() S.HideInfo() Paint(r) end)
            b:SetScript("OnClick", function()
                if S.IsPinned(r) then S.Unpin() S.ShowInfo(r, label, tip) else S.ShowInfo(r, label, tip, true) end
                for _, o in ipairs(rows) do Paint(o) end
            end)
            r.infoBtn = b
        end
        rows[#rows + 1] = r
        Paint(r)
        control:SetParent(r)
        control:ClearAllPoints()
        control:SetPoint("RIGHT", -14, 0)
        -- The label never runs under its control: it gets the room left of it (minus the (i)), and is
        -- cut short with an ellipsis if it needs more. The (i) sits right after the text it explains.
        local room = L.colW - 28 - (control:GetWidth() or 0) - (tip and 30 or 8)
        l:SetWidth(math.max(40, room))
        l:SetJustifyH("LEFT")
        l:SetWordWrap(false)
        if r.infoBtn then
            r.infoBtn:ClearAllPoints()
            r.infoBtn:SetPoint("LEFT", l, "LEFT", math.min(l:GetStringWidth() or 0, math.max(40, room)) + 4, 0)
        end
        if tip then
            local d = S.Text(r, 11, S.C.muted)
            d:SetPoint("TOPLEFT", 14, -28)
            d:SetWidth(math.max(40, room + 24))
            d:SetJustifyH("LEFT")
            d:SetWordWrap(false)
            d:SetText(FirstSentence(tip))
        end
        controls[#controls + 1] = control
        if settings.index and settings.building then      -- QoL pages only (Route settings is Levelling's)
            settings.index[#settings.index + 1] = { key = settings.building, label = label, tip = tip,
                row = r, area = area, y = L.y }
        end
        L.rowIndex = L.rowIndex + 1
        L.y = L.y - h - (card and 0 or 2)
        return r
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

    Section("Routes", "off by default: Headstart can be just the QoL addon", { icon = 134269 })
    Row("Routes in RestedXP (all characters on this account)", S.Switch(c, function() return YR.RoutesOn() end,
        function(on) YR.SetRoutesOn(on) YR:RefreshWindow() end),
        "On: your routes (the ones you saved, imported or edited) are loaded into RestedXP, and what they"
        .. " need is kept in your bags and bought for you. Off: none of that, and the options below wait until"
        .. " it's on. One switch for the whole account; takes a /reload (/headstart routes on|off)")

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
        "Quests, levels, deaths, purchases, sales, quest loot and your position every 2 seconds, for This run and the route analysis")
    Row("Keep what the route needs", S.Switch(c, Opt("sellGuard"), SetOpt("sellGuard")),
        "Items a route quest still needs (like the boar meat for Stocking Jetsteam) say so on their tooltip, and"
        .. " selling one to a vendor warns you, so you can buy it back from the Buyback tab")
    Row("Buy later what I couldn't afford", S.Switch(c, Opt("buyLater"), SetOpt("buyLater")),
        "A buy the route skipped because you were short (the weapons in Kharanos) comes back: once you have"
        .. " the money, don't have it yet and it still beats your weapon, chat says what and where, and at a"
        .. " vendor who sells it you're asked whether to buy it (hold Shift as you open the vendor to skip)")
    Row("Tell me when I can finish Camping 101", S.Switch(c, Opt("campReminder"), SetOpt("campReminder")),
        "Dun Morogh: when your bags hold the ore and stone to take Blacksmithing to 20 for Camping 101, or Mining is done,"
        .. " chat and the middle of the screen say so, and where (the Kharanos forge, Yarr Hammerstone). Again each time you"
        .. " come into Kharanos with it still to do")
    Row("Release at death skips", S.Switch(c, Opt("deathSkipRelease"), SetOpt("deathSkipRelease")),
        "When the route step you are on says to die and respawn at the Spirit Healer, your spirit is released"
        .. " at once, and RestedXP accepts the Spirit Healer for you. Any other death is left to you")

    Section("Group play", "a duo or trio sharing quests", { icon = 134149 })
    local role = S.Dropdown(c, 190, YR.ROLES, function(v) YR:SetRole(v) YR:RefreshWindow() end)
    function role:Refresh()
        for _, r in ipairs(YR.ROLES) do if r[1] == YR:Role() then self:SetValue(r[2]) end end
    end
    Row("This character plays", role, "Routes with a group version give each role its own steps: one takes the"
        .. " quests while the others start killing. Agree on roles with your group. Solo: the normal route")
    Row("Share route quests with my party", S.Switch(c, Opt("groupShare"), SetOpt("groupShare")),
        "A route quest you take from an NPC is shared with your party at once (on Forever, from any distance)")
    Row("Accept route quests my party shares", S.Switch(c, Opt("groupAccept"), SetOpt("groupAccept")),
        "Only quests on the route, and escorts on it; anything else still asks. Hold Shift to be asked anyway")
    Row("Show my party's steps", S.Switch(c, Opt("groupPanel"), SetOpt("groupPanel", function() YR:RefreshParty() end)),
        "A small list under the splits: each Headstart in your party, its role and the route step it is on")

    Section("Level splits", nil, { icon = 236562 })
    Row("Show level splits", S.Switch(c, Opt("showSplits"), SetOpt("showSplits", function(on) YR:ShowSplits(on) end)))
    Row("Lock in place", S.Switch(c, function() return st().lock end, Style("lock")),
        "Locked, it can't be dragged and clicks go through it")
    Row("Text size", S.Slider(c, 10, 24, 1, function() return st().size end, Style("size")))
    Row("Levels listed", S.Slider(c, 1, 60, 1, function() return st().rows end, Style("rows")),
        "How many finished levels are listed under the one in progress")
    Row("Show XP per hour", S.Switch(c, function() return st().rate end, Style("rate")))
    Row("Show time to ding", S.Switch(c, function() return st().ding end, Style("ding")))
    local CLOCKS = { { "full", "1:50:19" }, { "short", "1h 50m" } }
    local clock
    clock = S.Dropdown(c, 120, CLOCKS, function(v) Style("clock")(v) clock:Refresh() end)
    function clock:Refresh()
        for _, o in ipairs(CLOCKS) do if o[1] == st().clock then self:SetValue(o[2]) end end
    end
    Row("Times past an hour", clock, "Under an hour both read 27:57. The short form drops the seconds")
    Row("Show the level column", S.Switch(c, function() return st().levelCol end, Style("levelCol")),
        "How long each level took on its own")
    Row("Show the total column", S.Switch(c, function() return st().totalCol end, Style("totalCol")),
        "Your play time from level 1 when you reached each level")
    Row("Show the vs best column", S.Switch(c, function() return st().vs end, Style("vs")),
        "Your total against the best run's at each level: ahead (green, -) or behind (red, +)")
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
    Row("Compare with", compare, "Which of your runs \"vs best\" and \"± level\" use: any run, only your class, or"
        .. " your class and race (Dwarf and Gnome count as one: they share the start). A run from before races were"
        .. " kept counts under class and race only if the game can still tell its race")
    Row("Show the ± level column", S.Switch(c, function() return st().levelVs end, Style("levelVs")),
        "What each level alone won or lost against the best run's same level: -0:40 is 40 seconds faster")
    Row("Background", S.Slider(c, 0, 100, 5, function() return st().bg end, Style("bg")),
        "How dark the box behind the splits is, in percent. 0 is none")
    Row("From the left (pixels)", S.Slider(c, 0, 3000, 1, function() return YR:SplitsPosition()[1] end,
        function(v) YR:SetSplitsPosition(v, nil) end, 280))
    Row("From the top (pixels)", S.Slider(c, 0, 2000, 1, function() return YR:SplitsPosition()[2] end,
        function(v) YR:SetSplitsPosition(nil, v) end, 280))

    -- The logs take room whether the routes are on or not, so these rows are never dimmed.
    Section("Run logs", "every character's, in the account's saved file", { icon = 134328 })
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
    plainRow("Delete logs not played for (days)", S.Stepper(c, function() return YippRouteDB.logKeepDays or 0 end,
        function(v) YippRouteDB.logKeepDays = v > 0 and v or nil end, 0, 365, 5, 110),
        "At login, the logs of characters you haven't played for this many days are deleted (never this"
        .. " character's). 0 keeps them all")
    local scan = S.Button(c, "Delete", function()
        if YR.DeleteScan() then YR.Print("deleted the quest scan.") end
        YR:RefreshWindow()
    end, nil, 90)
    function scan:Refresh() self:SetEnabled(YippRouteDB.scan ~= nil) end
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
    Section("Quest rewards", "each class has its own", { icon = 134939 })
    Row("Settings for", ClassPicker(c), "Every class keeps its own reward choices: a warrior's list isn't a mage's")
    Row("Pick quest rewards", S.Switch(c, function() return YR:RewardSettings(ViewClass()).on end,
        function(on) YR:RewardSettings(ViewClass()).on = on end),
        "When a quest offers a choice, take one for you. Hold Shift when handing in to choose yourself")
    Row("Up to level", S.Slider(c, 1, 60, 1, function() return YR:RewardSettings(ViewClass()).maxLevel end,
        function(v) YR:RewardSettings(ViewClass()).maxLevel = v end))
    Row("Take the reward I chose before", S.Switch(c, function() return YR:RewardSettings(ViewClass()).remember end,
        function(on) YR:RewardSettings(ViewClass()).remember = on end), "A reward you picked by hand for a quest is taken again")
    Row("Let me pick when there's a green", S.Switch(c, function() return YR:RewardSettings(ViewClass()).greenStop end,
        function(on) YR:RewardSettings(ViewClass()).greenStop = on end),
        "A choice with a green (or better) among it waits for you, and RestedXP's built-in picks wait too."
        .. " Hold Shift when talking to an NPC to stop all quest automation, Headstart's and RestedXP's, for that window")
    local fallback = S.Dropdown(c, 170, { { "value", "The most valuable" }, { "ask", "Let me choose" } }, function(v)
        YR:RewardSettings(ViewClass()).fallback = v
        YR:RefreshWindow()
    end)
    function fallback:Refresh() self:SetValue(YR:RewardSettings(ViewClass()).fallback == "value" and "The most valuable" or "Let me choose") end
    Row("Nothing from the list on offer", fallback)
    L.Break()
    local y = L.y

    y = y - 10
    local t = S.Text(c, 12, S.C.muted)
    t:SetPoint("TOPLEFT", 4, y)
    t:SetText("Priority: the first kind on offer is taken. Switch off the kinds you never want.")
    y = y - 20
    rew.order = {}
    for i = 1, #YR.REWARD_KINDS do
        local r = CreateFrame("Frame", nil, c)
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
    local h = S.Text(c, 12, S.C.accent)
    h:SetPoint("TOPLEFT", 4, y)
    h:SetText("REWARDS YOU CHOSE YOURSELF")
    y = y - 22
    rew.chosenY, rew.chosenRows, rew.content, rew.width = y, {}, c, colW
    c:SetHeight(-y + 28 * 20)
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

    -- the saved layout and the two actions, above the options
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
    setup.note:SetText("Bars are per class: copy them on your main or plan them. The interface (chat, Edit Mode,"
        .. " settings) is shared by every class: the newest Copy this layout sets it.")
    local apply = S.Button(card, "Apply to this character", function() YS:Apply() YR:RefreshWindow() end, "primary")
    apply:SetPoint("RIGHT", -12, 0)
    apply.tip = "Put the saved layout on this character, with the choices below"
    local copy = S.Button(card, "Copy this layout", function() YS:Copy() YR:RefreshWindow() end)
    copy:SetPoint("RIGHT", apply, "LEFT", -8, 0)
    copy.tip = "Save this character's bars, macros and items for its class, and its chat, Edit Mode, game settings,"
        .. " raid frames and camera for every class"
    setup.apply, setup.copy = apply, copy
    setup.saved:SetPoint("RIGHT", copy, "LEFT", -16, 0)
    setup.saved:SetJustifyH("LEFT")
    setup.saved:SetWordWrap(false)
    setup.note:SetPoint("RIGHT", copy, "LEFT", -16, 0)
    setup.note:SetJustifyH("LEFT")
    setup.note:SetWordWrap(true)

    local rows = CreateFrame("Frame", nil, page)
    rows:SetPoint("TOPLEFT", 0, -92)
    rows:SetPoint("BOTTOMRIGHT")
    local L = RowPage(rows, setup.controls, 150)
    local Section, Row = L.Section, L.Row
    local need      -- the macro count further down: every choice it depends on asks it to count again
    local function Recount() if need then need:Refresh() end end
    local function Sw(key) local b = S.Switch(L.c, function() return o()[key] end, function(on) o()[key] = on Recount() end) return b end

    Section("Class", "each class has its own layout and choices", { icon = 134166 })
    Row("Settings for", ClassPicker(L.c), "Every class keeps its own saved layout and its own choices below")
    local planBtn = S.Button(L.c, "Plan bars...", function() YR.OpenPlanner() end, nil, 120)
    Row("Plan the bars here", planBtn, "No main to copy from? Drag every spell your class will ever have onto your"
        .. " bars, at any level, and save it as this class's layout. It opens on your current class")
    L.Break()

    Section("Spells", nil, { icon = 133742 })
    Row("Class spells", Sw("classSpells"))
    Row("Class spells up to level", S.Slider(L.c, 1, 60, 1, function() return o().maxLevel end,
        function(v) o().maxLevel = v Recount() end), "Spells your main has on its bars that are learned at this level or lower")
    local BUTTONS = {
        { "placeholder", "Spells; ? until learned" },
        { "spells", "Only spells" },
        { "macros", "Macros for every spell" },
    }
    local buttons
    buttons = S.Dropdown(L.c, 200, BUTTONS, function(v) o().spellButtons = v buttons:Refresh() Recount() end)
    function buttons:Refresh()
        local cur = YS.SpellButtons(o())
        for _, b in ipairs(BUTTONS) do if b[1] == cur then self:SetValue(b[2]) end end
    end
    Row("Spell buttons", buttons, "Spells; ? until learned: a spell you know goes on the bar as the spell, one you"
        .. " don't yet waits in its slot as a question-mark macro and is swapped for the spell when you learn it."
        .. " Only spells: no macros - the slot stays empty until you learn the spell, then it goes in."
        .. " Macros for every spell: each class spell is a \"#showtooltip /cast\" macro, learned or not, never"
        .. " swapped (a downranked one casts its rank). That takes a macro per button, so a full set can run into"
        .. " the character's macro limit")
    need = CreateFrame("Frame", nil, L.c)
    need:SetSize(220, 24)
    need.text = S.Text(need, 13)
    need.text:SetPoint("RIGHT")
    function need:Refresh()
        local n, limit = YS:MacrosNeeded(YS:Profile(ViewClass()), o(), ViewClass())
        self.text:SetText(("%d of %d"):format(n, limit))
        self.text:SetTextColor(unpack(n > limit and S.C.danger or n > limit - 5 and S.C.gold or S.C.text))
    end
    Row("Character macros it takes", need, "With the saved layout and the choices on this page: your own macros,"
        .. " mouseover spells and the spells your Spell buttons choice makes into macros. The game allows 30 a"
        .. " character; Apply stops at the limit. An account macro the layout uses costs nothing")
    Row("Racial spells", Sw("racials"), "Stoneform, Shadowmeld and the like")
    Row("Profession spells", Sw("professions"), "Find Minerals, Smelting, Cooking and the rest; each goes in when you learn the profession")
    local mo = S.Input(L.c, { width = 200, placeholder = "e.g. Purify, Holy Light", onCommit = function(t) o().mouseover = t Recount() end })
    function mo:Refresh() if not self:HasFocus() then self:SetValue(o().mouseover) end end
    Row("Mouseover macros for", mo, "These spells become /cast [@mouseover] macros: on who you point at, else yourself. Separate with commas")

    Section("Macros and items", nil, { icon = 134394 })
    Row("Your own macros", Sw("macros"))
    Row("AutoFeed's macros", Sw("autofeed"), "The AutoFeed macros on your main's bars. AutoFeed makes them on this"
        .. " character if it hasn't yet, and keeps them filled with your best food, water and potions."
        .. (YR.Setup:AutoFeedLoaded() and "" or "\n\nAutoFeed isn't loaded right now, so these slots stay empty."))
    Row("Items (Hearthstone, food, potions)", Sw("items"), "Items your main has on its bars. Copy this layout again if your saved copy is older than this option")

    Section("Before setting up", nil, { icon = 134520 })
    Row("Clear all action bars first", Sw("clearBars"), "Off: the saved buttons go over what is there; empty saved slots leave yours alone")
    Row("Remove this character's old macros", Sw("clearMacros"), "Character macros only; account macros and AutoFeed's are never touched")

    Section("Interface", nil, { icon = 134063 })
    Row("Game settings", Sw("settings"), "Auto loot, interact on click, nameplates, raid frames, map coordinates,"
        .. " camera distance and the rest of the list")
    Row("Edit Mode layout", Sw("editMode"), "Left alone anyway when a UI suite like ElvUI or EllesmereUI is loaded")
    Row("Which action bars are shown", Sw("barVisibility"), "Left alone anyway when a bar addon like Bartender or Dominos is loaded")
    Row("Chat windows", Sw("chat"), "Your main's chat tabs: names, what each shows (channels and messages), font size, colour, transparency, docked or where they float")
    Row("Camera distance", Sw("camera"), "As far out as on your main. A new character also gets it once after the intro, which leaves the camera all the way in")
    Row("Pick the RestedXP route for my race", Sw("guide"))
    Row("Stop Blizzard placing new spells", Sw("noAutoPush"), "Blizzard drops every new spell on the first empty slot; with a set-up layout that only makes duplicates")

    Section("While levelling", nil, { icon = 132307 })
    Row("Put spells on the bars as I learn them", Sw("swap"), "A placeholder becomes the real spell, or an empty saved slot gets it")
    Row("Put new ranks on the bars", Sw("rankUp"), "A new rank from the trainer replaces the old one in your main's slots. A spell your main keeps at a lower rank stays at that rank")
    Row("Show the setup window on new characters", Sw("popup"))
    Row("Skip the intro on new characters", Sw("skipIntro"), "The cinematic a level-1 character logs in to is cancelled as it starts")
    L.Break()
    L.c:SetHeight(-L.y + 20)
end

local function RefreshSetup()
    local YS = YR.Setup
    local view = ViewClass()
    local p = YS:Profile(view)
    local _, class = UnitClass("player")
    local name = CLASS_NAME[view] or view
    setup.saved:SetText(p and ("Saved " .. name .. " layout  |cffffffff" .. YS:Describe(p) .. "|r")
        or ("No " .. name .. " layout saved yet"))
    -- Copy and Set up act on this character, so only while its own class is shown
    setup.apply:SetEnabled(p ~= nil and view == class)
    setup.copy:SetEnabled(view == class)
    setup.apply.tip = view ~= class and ("This character isn't a " .. name .. ": pick its own class above")
        or "Put the saved layout on this character, with the choices below"
    setup.copy.tip = view ~= class and ("This character isn't a " .. name .. ": pick its own class above")
        or "Save this character's bars, macros and items for its class, and its chat, Edit Mode, game settings,"
        .. " raid frames and camera for every class"

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
    Section("Class trainer", "learned as the trainer opens", { icon = 133741 })
    Row("Learn my spells at the trainer", S.Switch(c, function() return YR.Option("autoTrain") end,
        function(on) YippRouteDB.autoTrain = on YR:SyncRxpTrainer() end),
        "When you open your class trainer, the spells below are learned at once, as you chose for each."
        .. " Hold Shift as you open it to train yourself. RestedXP's own trainer automation is switched off"
        .. " while this is on")
    local reserve = S.Stepper(c, function() return math.floor((YR.TrainerData().reserve or 0) / 100) end,
        function(v) YR.TrainerData().reserve = v * 100 end, 0, 100000, 1, 120)
    Row("Keep at least (silver)", reserve, "Spells set to \"If I can afford it\" are only learned while you"
        .. " would keep at least this much (2 silver for a new character). \"Always\" spells are learned"
        .. " whenever you have the gold. Shift-click - or + to move ten at a time")
    local _, class = UnitClass("player")
    local levels = (YR.Setup and YR.Setup.SPELL_LEVELS or {})[class] or {}
    local list, names = {}, {}
    for name, lvl in pairs(levels) do
        if lvl > 1 and lvl <= TRAIN_TO and not name:find("%(Passive") then list[#list + 1] = { name, lvl } end
    end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
    for _, e in ipairs(list) do names[#names + 1] = e[1] end

    Section("Set many at once", nil, { icon = 134327 })
    trainer.upTo = trainer.upTo or 10
    local upTo = S.Stepper(c, function() return trainer.upTo end, function(v) trainer.upTo = v end, 2, TRAIN_TO, 1, 110)
    Row("Always, up to level", upTo, "The level for the button below: every spell first learned at this level"
        .. " or lower is set to Always (the ones you want the moment you can, like your first heals)")
    local always = S.Button(c, "Set to Always", function()
        YR.SetTrainerChoices(names, "always", nil, levels, trainer.upTo)
        trainer.refresh()
    end, "primary", 130)
    Row("Spells up to that level", always)
    local afford = S.Button(c, "All: If I can afford it", function()
        YR.SetTrainerChoices(names, "gold")
        trainer.refresh()
    end, nil, 170)
    Row("Every spell", afford, "Back to the default for the whole list: learned when you'd keep your reserve")
    Section(("Spells: %s"):format(UnitClass("player") or class), "every rank of each; first learned at the level shown",
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
        Row(("%d  %s%s"):format(lvl, icon and ("|T" .. icon .. ":18:18:0:0:64:64:5:59:5:59|t ") or "", name), dd)
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
local function QoLPage(key, build)
    qolPages[key] = { controls = {} }
    return function(page)
        local L = RowPage(page, qolPages[key].controls, 64, 1)
        local c = L.c
        local Section, Row = L.Section, L.Row
        -- what you set, also while the main switch has it all off (it comes back as you left it)
        local function Opt(k) return function() return YR.OptionSet(k) end end
        build(L, c, Section, Row, Opt)
        if key ~= "gear" and key ~= "trinkets" then     -- those two end with a list of their own
            L.Break()
            c:SetHeight(-L.y + 40)
        end
    end
end

local BuildCamps = QoLPage("camps", function(L, c, Section, Row, Opt)
        Section("Campfire icon", "reads your own buffs", { icon = 135805, master = { Opt("camp"), YR.SetCampIcon } })
        Row("List what the camp gives you", S.Switch(c, Opt("campList"), YR.SetCampList),
            "Under the fire: the stat it gives (\"Strength +6\") and the camp's shorter buffs with their time."
            .. " Buffs can't be read in combat, so in a fight it dims to show what it last saw")
        Row("Keep it on screen away from camps", S.Switch(c, Opt("campAlways"), YR.SetCampAlways),
            "With nothing going on it's just the grey fire. Off: it only turns up near a camp or while its buff runs")
        Row("Lock in place", S.Switch(c, Opt("campLocked"), YR.SetCampLocked),
            "Off: a preview with a blue edge shows wherever you are, to drag where you want it (/headstart camp unlock)")

        Section("Flight timer", "a bar while you fly", { icon = 132239,
            master = { Opt("flightTimer"), function(on) YippRouteDB.flightTimer = on YR:SetFlightTimer(on) end } })
        Row("Your face on the bar", S.Switch(c, Opt("flightFace"), function(on)
            YippRouteDB.flightFace = on
            if YR.FlightFace then YR.FlightFace() end
        end), "Where you are on the bar is a small round portrait of your character. Off: a lit dot")
        Row("How it times a flight", S.Text(c, 12, S.C.muted),
            "A bar while you fly: where from, where to and the time left. Each flight is timed the first time you"
            .. " take it; until then RestedXP's time for it, an estimate from the flight's length, or it counts up. Drag the bar to move it"
            .. " (/headstart flight shows a sample)")
end)

local BuildBags = QoLPage("bags", function(L, c, Section, Row, Opt)
        Section("Bank", "hold Shift as you open the bank to keep everything", { icon = 133639 })
        Row("Bank when I open the bank", S.Switch(c, Opt("bankAuto"), function(on) YippRouteDB.bankAuto = on end),
            "What you choose below goes from your bags to the bank as it opens, one stack at a time, and chat"
            .. " says what went. Quest items, anything a quest you'd still do needs (not one that's done or grey for you) and AutoFeed's food and water"
            .. " always stay. It stops when the bank is full")
        local MATS = { { "mine", "Not for my professions" }, { "all", "All of them" }, { "off", "None" } }
        local mats
        mats = S.Dropdown(c, 190, MATS, function(v) YippRouteDB.bankMats = v mats:Refresh() end)
        function mats:Refresh()
            for _, o in ipairs(MATS) do if o[1] == YR.BankMats() then self:SetValue(o[2]) end end
        end
        Row("Crafting mats", mats, "Not for my professions: cloth, ore, herbs, leather and the like stay when a"
            .. " profession you have crafts with them (ore stays for a miner, linen for a tailor), and the rest go."
            .. " Dynamite and other things you use rather than craft with never go")
        Row("Recipes I can't learn yet", S.Switch(c, Opt("bankRecipes"), function(on) YippRouteDB.bankRecipes = on end),
            "A recipe for a profession you haven't got, or one that needs more skill than you have. One you can"
            .. " learn now stays in your bags, and one you already know is left for the vendor")
        Row("Button on the bank window", S.Switch(c, Opt("bankButton"), YR.SetBankButton),
            "\"Bank mats\" under the bank window does the same whenever you click it (also /headstart bank)")

        Section("Mail to my alt", "for bag space: what the bank would take", { icon = 133471 })
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
        Row("Send to", alt, "The character who gets it, on this realm and faction, by its full name: name and surname, as the character shows it (\"Klistre Merke\"). Type just the name and Headstart adds the surname of one of your characters it knows"
            .. ". On that character nothing is sent, so the same settings work there")
        Row("Send when I open the mailbox", S.Switch(c, function() return YippRouteDB.mailAuto == true end,
            function(on) YippRouteDB.mailAuto = on end),
            "Off: only when you click the button on the mail window (or /headstart mail). Postage is 30 copper a stack")
        local MMATS = { { "mine", "Not for my professions" }, { "all", "All of them" }, { "off", "None" } }
        local mmats
        mmats = S.Dropdown(c, 190, MMATS, function(v) YippRouteDB.mailMats = v mmats:Refresh() end)
        function mmats:Refresh()
            for _, o in ipairs(MMATS) do if o[1] == YR.MailMats() then self:SetValue(o[2]) end end
        end
        Row("Crafting mats", mmats, "The same choice as for the bank: what a profession of yours crafts with stays")
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
        Row("Always send", mlist, "Anything else that should go to your alt every time. The same item again takes it off")
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
        Row("On the list", mshow)
        Row("Button on the mail window", S.Switch(c, Opt("mailButton"), YR.SetMailButton),
            "\"Send to <alt>\" under the mail window")
end)

local BuildVendors = QoLPage("vendors", function(L, c, Section, Row, Opt)
        Section("Vendor restock", "Shift as you open a vendor buys nothing", { icon = 133785,
            master = { Opt("restock"), function(on) YippRouteDB.restock = on end } })
        Row("Keep at least (gold)", S.Stepper(c, function() return YippRouteDB.restockReserve or 0 end,
            function(v) YippRouteDB.restockReserve = v end, 0, 1000, 1, 110),
            "Nothing is bought that would take you under this")
        if YR.RestockShoots() then
            Row("Ammo to keep", S.Stepper(c, function() return YR.RestockAmmo() end,
                function(v) YR.SetRestockAmmo(v) end, 0, 4000, 100, 110),
                "The best arrows or bullets the vendor sells for your bow, crossbow or gun that you can use - or,"
                .. " with a throwing weapon, more of the same one. Each class keeps its own number (a hunter 1000,"
                .. " a warrior or rogue 200 to begin with). 0: none")
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
        Row("Add to my list", custom, "Anything else to keep a stack of: shift-click an item into the box (or type"
            .. " its ID) and the number to keep after it, then Enter. The same item with 0 takes it off")
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
        Row("My list", list)
end)

local BuildGroup = QoLPage("group", function(L, c, Section, Row, Opt)
        Section("Party quests", "on Forever a quest can be shared from any distance", { icon = 134327 })
        Row("Share every quest I take", S.Switch(c, function() return YR.ShareAll() end,
            function(on) YippRouteDB.shareAll = on end),
            "Each quest you take from an NPC is shared with your party at once. Off: only the route's quests"
            .. " (Route settings, Group play)")
        local FROM = { { "friends", "Guildies and friends" }, { "party", "Anyone in my party" }, { "off", "Nobody" } }
        local from
        from = S.Dropdown(c, 190, FROM, function(v) YippRouteDB.acceptFrom = v from:Refresh() end)
        function from:Refresh()
            for _, o in ipairs(FROM) do if o[1] == YR.AcceptFrom() then self:SetValue(o[2]) end end
        end
        Row("Accept quests shared by", from, "Quests and escorts someone in your party shares are accepted for"
            .. " you. Hold Shift as the quest opens to be asked. Leatrix Plus's \"Block shared quests\" would"
            .. " decline them before Headstart sees them")

        Section("Quick group", "into a group for a kill and out again", { icon = 134149 })
        Row("Invite and Leave buttons", S.Switch(c, Opt("groupBar"), YR.SetGroupBar),
            "A small bar: Invite asks your target into your group, Leave group leaves it. Both also have key"
            .. " bindings (Key Bindings, AddOns, Headstart) and /headstart inv, /headstart leave")
        Row("Lock the buttons in place", S.Switch(c, Opt("groupBarLocked"), YR.SetGroupBarLocked),
            "Off: drag the bar where you want it")
        local WHO = { { "friends", "Guildies and friends" }, { "anyone", "Anyone" }, { "off", "Nobody" } }
        local function WhoDrop(key, get)
            local d
            d = S.Dropdown(c, 190, WHO, function(v) YippRouteDB[key] = v d:Refresh() end)
            function d:Refresh() for _, o in ipairs(WHO) do if o[1] == get() then self:SetValue(o[2]) end end end
            return d
        end
        Row("Invite who whispers me the word", WhoDrop("whisperInvite", YR.WhisperInvite),
            "Someone whispers you the word below and gets an invite, if you're solo or lead a group with room")
        local word = CreateFrame("Frame", nil, c)
        word:SetSize(110, 24)
        word.input = S.Input(word, { width = 110, placeholder = "inv", onCommit = function(t)
            YippRouteDB.whisperWord = strtrim(t or "") ~= "" and strtrim(t) or nil
        end })
        word.input:SetPoint("RIGHT")
        function word:Refresh() if not self.input:HasFocus() then self.input:SetText(YippRouteDB.whisperWord or "") end end
        Row("The word", word, "The whole whisper must be this word, in any case: \"inv\" by default")
        Row("Accept group invites from", WhoDrop("acceptInvites", YR.AcceptInvites),
            "You join at once. Hold Shift as the invite comes in to be asked anyway")
end)

local BuildReminders = QoLPage("reminders", function(L, c, Section, Row, Opt)
        Section("Reminders", "one quiet line when there's something to do", { icon = 134376 })
        Row("New spells at the trainer", S.Switch(c, Opt("remindTrainer"), function(on) YippRouteDB.remindTrainer = on end),
            "At a ding (and at login): what your class trainer has for you now, and about what it costs. Prices"
            .. " are remembered from your trainer visits (/headstart trainer)")
        Row("Talent points to spend", S.Switch(c, Opt("remindTalents"), function(on) YippRouteDB.remindTalents = on end),
            "At a ding (and at login), when you have points you haven't spent")
        Row("Durability warning", S.Switch(c, Opt("durability"), function(on) YippRouteDB.durability = on end),
            "When your most worn piece drops under the warning line (once, until you repair), and when you come"
            .. " into a town or an inn under the town line")
        Row("Warn at (percent)", S.Stepper(c, function() return YippRouteDB.durWarn or 25 end,
            function(v) YippRouteDB.durWarn = v end, 5, 95, 5, 110))
        Row("In town, remind at (percent)", S.Stepper(c, function() return YippRouteDB.durTown or 50 end,
            function(v) YippRouteDB.durTown = v end, 5, 100, 5, 110))
        Section("Things I can make myself", "you have the recipe and the mats", { icon = 133685,
            master = { Opt("craftRemind"), function(on) YippRouteDB.craftRemind = on end } })
        Row("What it watches", S.Text(c, 12, S.C.muted),
            "You know the recipe and carry the mats, but have none in your bags: chat says what you can make and how"
            .. " many. Once, and again after you have run out")
        Row("  Sharpening stones and weightstones", S.Switch(c, Opt("craftStones"), function(on) YippRouteDB.craftStones = on end),
            "Blacksmithing. Only the kind your weapon takes: blades are sharpened, blunt weapons weighted")
        Row("  Wizard and mana oil", S.Switch(c, Opt("craftOils"), function(on) YippRouteDB.craftOils = on end), "Enchanting")
        Row("  Bandages", S.Switch(c, Opt("craftBandages"), function(on) YippRouteDB.craftBandages = on end), "First Aid")
        Row("  Remind when I have fewer than", S.Stepper(c, function() return YippRouteDB.craftBelow or 1 end,
            function(v) YippRouteDB.craftBelow = v end, 1, 100, 1, 110), "1: only when you have none at all")
        Section("Whisper sound", "a sound of your choice when someone whispers you", { icon = 133469 })
        local sound
        sound = S.Dropdown(c, 240, YR.WhisperSounds, function(v)
            YippRouteDB.whisperSound = v ~= "off" and v or nil
            sound:Refresh()
        end, { icon = "sound", tip = "Listen", shows = function(v) return v ~= "off" end,
            onClick = function(v) YR.PlayWhisperSound(v) end })
        function sound:Refresh() self:SetValue(YR.WhisperSoundName()) end
        Row("Sound", sound, "The speaker on each line plays it without picking it. The game's own sounds first; with a"
            .. " sound pack or another addon that brings LibSharedMedia (Details, WeakAuras, boss mods), every sound"
            .. " of theirs is in the list too - scroll it. The game's own quiet whisper sound still plays under it")
        local CHANNEL = { { "Master", "Master (heard with effects turned down)" }, { "SFX", "Sound effects" }, { "Dialog", "Dialog" } }
        local channel
        channel = S.Dropdown(c, 240, CHANNEL, function(v) YippRouteDB.whisperChannel = v channel:Refresh() end)
        function channel:Refresh() for _, o in ipairs(CHANNEL) do if o[1] == YR.WhisperChannel() then self:SetValue(o[2]) end end end
        Row("Volume follows", channel, "Which of the game's volume sliders it obeys")
        Row("Battle.net whispers too", S.Switch(c, Opt("whisperBNet"), function(on) YippRouteDB.whisperBNet = on end))

        Section("At every ding", nil, { icon = 134441 })
        Row("Screenshot at every ding", S.Switch(c, Opt("levelShot"), function(on) YippRouteDB.levelShot = on end),
            "Saved in your Screenshots folder, a moment after the ding so the animation is in it")
end)

local BuildGear = QoLPage("gear", function(L, c, Section, Row, Opt)
        Section("Gear sim", "what an item would do for you", { icon = 132739,
            master = { Opt("simTooltip"), function(on) YippRouteDB.simTooltip = on end } })
        Row("In item tooltips", S.Text(c, 12, S.C.muted),
            "Every piece of gear you point at gets a line: what wearing it would do for you - \"+4.2% DPS,"
            .. " +1.0% toughness\" - from your own attack power, crit, spell power, health and armor, with the item"
            .. " swapped in for what it replaces. A levelling estimate: set bonuses, on-hit effects and trinkets"
            .. " aren't in it")
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
        Row("Weigh it for", roleDrop, "Guess: the talent tree with the most points (Retribution is melee, Holy"
            .. " healing, Protection tanking ...), or what your class levels as before you have any")
        Section("Better gear", "what you pick up, against what you wear", { icon = 133071,
            master = { Opt("upgrades"), function(on) YippRouteDB.upgrades = on end } })
        Row("What counts", S.Text(c, 12, S.C.muted),
            "An item in your bags the gear sim says is better for you (your role, see Weigh it for) than what"
            .. " you wear in that slot: at least the % below, or any gain that costs you nothing, or anything for"
            .. " an empty slot. Only what you can wear - the game's red text says no. Once per item (again after"
            .. " a ding). /headstart upgrades looks now")
        local QUAL = { { 1, "Grey and white" }, { 2, "Up to green" }, { 3, "Up to blue" }, { 5, "Everything" } }
        local qual
        qual = S.Dropdown(c, 170, QUAL, function(v) YippRouteDB.upgradeQuality = v YR.UpgradesForget() qual:Refresh() end)
        function qual:Refresh()
            for _, o in ipairs(QUAL) do if o[1] == (YippRouteDB.upgradeQuality or 2) then self:SetValue(o[2]) end end
        end
        Row("Items up to", qual, "Blues and better are usually worth reading yourself")
        Row("At least this much better (%)", S.Stepper(c, function() return YippRouteDB.upgradeMin or 2 end,
            function(v) YippRouteDB.upgradeMin = v YR.UpgradesForget() end, 0, 100, 1, 110),
            "Only for a trade, like less DPS for more armor. A piece that is better and takes nothing from you,"
            .. " or goes in an empty slot, is mentioned whatever the gain")
        Row("A window with an Equip button", S.Switch(c, Opt("upgradeButton"), function(on) YippRouteDB.upgradeButton = on end),
            "Off: the chat line only")

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

local BuildTrinkets = QoLPage("trinkets", function(L, c, Section, Row, Opt)
        Section("Trinket buttons", "click one for your other trinkets", { icon = 133434,
            master = { Opt("trinketBar"), function(on) YippRouteDB.trinketBar = on YR.ShowTrinketBar(on) end } })
        Row("How they work", S.Text(c, 12, S.C.muted),
            "Trinket buttons on screen, each with its cooldown. Click one: the trinkets in your bags,"
            .. " and a click on one of those puts it in that slot (in a fight: as soon as it ends). Right-click a"
            .. " button to use the trinket in it. A right-click in the list puts a trinket in your swap order or"
            .. " takes it out. Nothing opens when the mouse only goes past")
        Row("Only as many as I have trinkets", S.Switch(c, Opt("trinketBarCount"), function(on)
            YippRouteDB.trinketBarCount = on if YR.TrinketLayout then YR.TrinketLayout() end end),
            "A button per trinket you have, worn or in your bags: none with no trinkets, one with one, both with two"
            .. " or more. Off: always both buttons. It changes after a fight, not during one")
        Row("Lock in place", S.Switch(c, Opt("trinketBarLocked"), function(on) YippRouteDB.trinketBarLocked = on end),
            "Unlocked, drag the buttons where you want them")

        Section("Swap trinkets for me", "your trinkets in the order below", { icon = 133437,
            master = { function() return YippRouteDB.trinketAuto == true end,
                function(on) YippRouteDB.trinketAuto = on if YR.TrinketPaint then YR.TrinketPaint() end end } })
        Row("How it swaps", S.Text(c, 12, S.C.muted),
            "When the trinket you wear has been used, the first ready one in your order goes in instead, and a"
            .. " higher one goes back as soon as it's ready again. A trinket you put on yourself that isn't in the"
            .. " order is left alone, so a swap by hand stays. Trinkets can't be changed in a fight: a swap waits"
            .. " for it to end. A green dot on a button: it looks after that slot")
        local function SlotSwitch(slot)
            return S.Switch(c, function() return YR.TrinketDB().auto[slot] ~= false end,
                function(on) YR.TrinketDB().auto[slot] = on and nil or false if YR.TrinketPaint then YR.TrinketPaint() end end)
        end
        Row("The top trinket slot", SlotSwitch(13))
        Row("The bottom trinket slot", SlotSwitch(14), "Off: that slot keeps what you put in it")
        Row("Not while I'm flagged for PvP", S.Switch(c, Opt("trinketPvpPause"), function(on) YippRouteDB.trinketPvpPause = on end),
            "On a PvP realm a swap at the wrong moment costs a fight: while you're flagged, nothing here or under"
            .. " Swap when changes your gear by itself. Your own clicks and gear-set keys always work")

        Section("Swap when...", "off until you turn one on; and back after", { icon = 132239 })
        local carrot = C_Item.GetItemNameByID and C_Item.GetItemNameByID(11122) or "Carrot on a Stick"
        Row("Mounted: " .. carrot, S.Switch(c, function() return YippRouteDB.trinketMount == true end,
            function(on) YippRouteDB.trinketMount = on end),
            "While you ride, Carrot on a Stick (faster mount) goes in a trinket slot, and the trinket you wore goes"
            .. " back when you get off. Only if you carry one")
        local SLOT_CHOICE = { { 13, "Top trinket slot" }, { 14, "Bottom trinket slot" } }
        local slotDrop
        slotDrop = S.Dropdown(c, 170, SLOT_CHOICE, function(v) YippRouteDB.trinketMountSlot = v slotDrop:Refresh() end)
        function slotDrop:Refresh()
            for _, o in ipairs(SLOT_CHOICE) do if o[1] == (YippRouteDB.trinketMountSlot or 14) then self:SetValue(o[2]) end end
        end
        Row("Into", slotDrop)
        Row("Swimming", S.Switch(c, function() return YippRouteDB.trinketSwim == true end,
            function(on) YippRouteDB.trinketSwim = on end), "An item of your choice while you swim (a trinket, boots, a helm"
            .. " ...), and what you wore goes back when you're out of the water")
        local swim = S.Input(c, { width = 200, placeholder = "Shift-click the item", onCommit = function(t)
            YippRouteDB.trinketSwimItem = YR.ItemFromText(t)
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
        Row("Item to swim in", swim)

        Section("Equipment sets", "the game's own, on keys", { icon = 132739 })
        local sets = S.Text(c, 12)
        sets:SetJustifyH("RIGHT")
        sets:SetWidth(320)
        function sets:Refresh()
            local list = YR.GearSets()
            local parts = {}
            for i, s in ipairs(list) do if i <= 5 then parts[#parts + 1] = i .. ": " .. s.name end end
            self:SetText(#parts > 0 and table.concat(parts, "   ") or "none yet")
        end
        Row("Your sets", sets, "Make sets in the character window's equipment manager. The first five get keys:"
            .. " Esc > Options > Key Bindings > AddOns > Headstart, \"Equipment set 1\" to 5. Or /headstart gear and the"
            .. " set's name or number. In a fight it goes on as soon as the fight ends")

        L.Break()
        local y = L.y - 6
        local head = S.Text(c, 14)
        head:SetPoint("TOPLEFT", 4, y)
        head:SetText("Your swap order")
        local sub = S.Text(c, 11, S.C.muted)
        sub:SetPoint("LEFT", head, "RIGHT", 10, 0)
        sub:SetText("numbered: in the order, first is most wanted. Grey: not in it")
        y = y - 26
        trink.rows = {}
        for i = 1, MAX_TRINKETS do
            local r = CreateFrame("Frame", nil, c)
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
        trink.none = S.Text(c, 12, S.C.muted)
        trink.none:SetPoint("TOPLEFT", 12, y - 8)
        trink.none:SetText("No trinkets on you or in your bags yet.")
        c:SetHeight(-y + MAX_TRINKETS * 34 + 40)
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
        local col = colour()
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
        Section("XP bar", "Headstart's own, in place of Blizzard's", { icon = 236562,
            master = { function() return YR.XPBarOn() end, Set("on") } })
        Row("Hide Blizzard's bar", S.Switch(c, Get("hideBlizz"), Set("hideBlizz")),
            "While ours shows, Blizzard's experience (and reputation) bar is made invisible and lets clicks through."
            .. " Off: both show")
        Row("Lock in place", S.Switch(c, Get("lock"), Set("lock")), "Unlocked: drag the bar where you want it")
        Row("Back to its place", S.Button(c, "Reset", function() YR.XPBarResetPosition() end, nil, 90),
            "The middle of the screen, above the action bars")
        Row("Width", S.Slider(c, 150, 1800, 10, Get("w"), Set("w"), 260))
        Row("Height", S.Slider(c, 4, 40, 1, Get("h"), Set("h"), 260))
        Row("Hide it at the level cap", S.Switch(c, Get("maxHide"), Set("maxHide")))

        Section("Look", nil, { icon = 133741 })
        local TEX = { { "flat", "Flat" }, { "smooth", "Smooth" }, { "blizzard", "Blizzard's" } }
        local tex
        tex = S.Dropdown(c, 170, TEX, function(v) Set("texture")(v) tex:Refresh() end)
        function tex:Refresh() for _, o in ipairs(TEX) do if o[1] == db().texture then self:SetValue(o[2]) end end end
        Row("Texture", tex)
        Row("XP colour", Swatch(c, "xpColor"))
        Row("Completed quests colour", Swatch(c, "questColor"), "After your XP: the XP of the quests in your log that are done"
            .. " and not handed in yet - where you'll be once you hand them in")
        Row("Rested colour", Swatch(c, "restColor"), "After that: the rested XP, double XP for kills until it's used")
        Row("Background", S.Slider(c, 0, 100, 5, function() return math.floor(db().bgAlpha * 100 + 0.5) end,
            function(v) Set("bgAlpha")(v / 100) end, 260), "How dark the empty part is, in percent")
        local TICKS = { { 0, "None" }, { 10, "Every tenth" }, { 20, "Every twentieth" }, { 4, "Quarters" } }
        local ticks
        ticks = S.Dropdown(c, 170, TICKS, function(v) Set("ticks")(v) ticks:Refresh() end)
        function ticks:Refresh() for _, o in ipairs(TICKS) do if o[1] == db().ticks then self:SetValue(o[2]) end end end
        Row("Ticks", ticks)
        Row("Text size", S.Slider(c, 8, 20, 1, Get("font"), Set("font"), 260))

        Section("Words", "what the bar says, written your way", { icon = 134327 })
        local TOKENS = "{level} {xp} {max} {left} {pct} {rested} {restedpct} {rate} {ding} {mobs} {kill} {played}"
            .. " {levelplayed} {session} {quest} {questpct} {quests}"
        local function TextRow(label, key)
            local box = S.Input(c, { width = 320, onCommit = function(t) Set(key)(t) end })
            function box:Refresh() if not self:HasFocus() then self:SetValue(db()[key] or "") end end
            Row(label, box, "Write anything, with these filled in: " .. TOKENS .. ". {rate} is XP an hour, {ding} the"
                .. " time to ding at that rate, {mobs} the kills to ding (by your last kills' XP), {played} and"
                .. " {levelplayed} your played time in all and this level, {session} since you logged in, {quest}"
                .. " {questpct} {quests} the XP, share of the level and number of your quests done and not handed in."
                .. " Empty: nothing")
        end
        TextRow("Left", "left")
        TextRow("Middle", "center")
        TextRow("Right", "right")
        Row("A line under the bar", S.Switch(c, Get("under"), Set("under")), "Three more texts, just under the bar")
        TextRow("Under, left", "left2")
        TextRow("Under, middle", "center2")
        TextRow("Under, right", "right2")
        Row("Only while the mouse is over it", S.Switch(c, Get("textHover"), Set("textHover")))
        Row("Back to the first words", S.Button(c, "Reset", function()
            local d = YR.XPBAR_DEFAULT
            for _, k in ipairs({ "left", "center", "right", "left2", "center2", "right2" }) do db()[k] = d[k] end
            db().under = true
            YR.XPBarApply()
            YR:RefreshWindow()
        end, nil, 90))
end)

-- Swing timer (Swing.lua): Blizzard's swing bars dressed, or our own bars.
local BuildSwing = QoLPage("swing", function(L, c, Section, Row, Opt)
        local db = YR.SwingDB
        local function Set(key) return function(v) db()[key] = v YR.SwingApply() end end
        local function Get(key) return function() return db()[key] end end
        Section("Swing timer", "your auto-attack bars, made to be seen", { icon = 132349,
            master = { function() return db().on == true end, Set("on") } })
        local STYLE = { { "blizzard", "Blizzard's bars, dressed" }, { "own", "Headstart's own bars" } }
        local style
        style = S.Dropdown(c, 210, STYLE, function(v) Set("style")(v) style:Refresh() end)
        function style:Refresh() for _, o in ipairs(STYLE) do if o[1] == db().style then self:SetValue(o[2]) end end end
        Row("Bars", style, "Blizzard's bars, dressed: the game's own swing bars with the look below - their timing, and"
            .. " their place, size and when they show stay in Edit Mode. Headstart's own bars: bars of ours in their"
            .. " place, with their own size, place and words further down")

        Row("Try it", S.Button(c, "Test", function()
            local ok, why = YR.SwingTest()
            if not ok then YR.Print(why or "turn the swing timer on first.") end
        end, nil, 90), "A few sample swings on every bar, to see the look as it is set now. Not in a fight")

        Section("On the bars", "both kinds", { icon = 134327 })
        Row("Weapon icon", S.Switch(c, Get("icon"), Set("icon")), "The weapon in that hand, left of its bar. Off to begin with")
        Row("Swing length", S.Switch(c, Get("speed"), Set("speed")),
            "How long the whole swing takes: after the name on Blizzard's bars (\"2.6s\"), after the time left on ours"
            .. " (\"0.8 / 2.6\"). It follows your haste and slows")
        Row("Another colour out of reach", S.Switch(c, Get("range"), Set("range")),
            "The bar turns the out-of-reach colour while your target is too far for that attack (the game's own check)")

        Section("Look", "both kinds", { icon = 133741 })
        local TEX = { { "smooth", "Smooth" }, { "flat", "Flat" }, { "blizzard", "Blizzard" } }
        local tex
        tex = S.Dropdown(c, 170, TEX, function(v) Set("texture")(v) tex:Refresh() end)
        function tex:Refresh() for _, o in ipairs(TEX) do if o[1] == db().texture then self:SetValue(o[2]) end end end
        Row("Texture", tex)
        Row("Text size", S.Stepper(c, Get("font"), Set("font"), 8, 24, 1, 110))
        Row("Outline", S.Switch(c, Get("outline"), Set("outline")), "A thin dark line round each bar")
        Row("Main hand", Swatch(c, "main", Get("mainColor"), YR.SwingApply))
        Row("Off hand", Swatch(c, "off", Get("offColor"), YR.SwingApply))
        Row("Ranged", Swatch(c, "ranged", Get("rangedColor"), YR.SwingApply))
        Row("Out of reach", Swatch(c, "far", Get("farColor"), YR.SwingApply))
        Row("Background (percent)", S.Slider(c, 0, 100, 5, function() return math.floor(db().bgAlpha * 100 + 0.5) end,
            function(v) Set("bgAlpha")(v / 100) end, 260), "How dark the empty part of a bar is")
        Row("Back to the first look", S.Button(c, "Reset", function()
            local keep = { on = db().on, pos = db().pos, lock = db().lock, style = db().style, look = db().look }
            YippRouteDB.swing = keep
            YR.SwingApply()
            YR:RefreshWindow()
        end, nil, 90))

        Section("Blizzard's bars only", "size, place, name and time: Edit Mode", { icon = 134063 })
        Row("My colours on them", S.Switch(c, Get("colors"), Set("colors")),
            "Off: Blizzard's own colours stay, with our texture and text")
        Row("Blizzard's frame round each bar", S.Switch(c, Get("border"), Set("border")), "Off: the bar without its frame")

        Section("Headstart's bars only", nil, { icon = 132349 })
        Row("Hide Blizzard's swing bars", S.Switch(c, Get("hideBlizz"), Set("hideBlizz")),
            "Made see-through while ours show, and back as they were when ours are off. They show in Edit Mode, where"
            .. " you can also turn them off for good")
        local SHOW = { { "combat", "In combat" }, { "always", "Always" }, { "swing", "Only while a swing runs" } }
        local show
        show = S.Dropdown(c, 190, SHOW, function(v) Set("show")(v) show:Refresh() end)
        function show:Refresh() for _, o in ipairs(SHOW) do if o[1] == db().show then self:SetValue(o[2]) end end end
        Row("When", show, "Main hand; off hand while you hold a weapon there; ranged for a hunter, and for anyone while"
            .. " a ranged swing runs")
        Row("Lock in place", S.Switch(c, Get("lock"), Set("lock")), "Off: every bar shows with a blue edge, to drag where you want it")
        Row("Back to its place", S.Button(c, "Reset", function() YR.SwingResetPosition() end, nil, 90),
            "Over the action bars, in the middle")
        Row("Name", S.Switch(c, Get("name"), Set("name")), "Main hand, Off hand, Ranged")
        Row("Time left", S.Switch(c, Get("time"), Set("time")), "Seconds to the next swing, in tenths")
        Row("Bright line at the front", S.Switch(c, Get("spark"), Set("spark")))
        Row("Width", S.Stepper(c, Get("w"), Set("w"), 80, 800, 10, 110))
        Row("Height of a bar", S.Stepper(c, Get("h"), Set("h"), 8, 60, 1, 110))
        Row("Space between bars", S.Stepper(c, Get("gap"), Set("gap"), 0, 30, 1, 110))
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
        Section("Instance tracker", "dungeons and raids against the hourly and daily limit", { icon = 134237,
            master = { Opt("instanceTrack"), function(on) YippRouteDB.instanceTrack = on end } })
        Row("Instances an hour", S.Stepper(c, function() return YippRouteDB.instanceHour or 5 end,
            function(v) YippRouteDB.instanceHour = v end, 1, 30, 1, 110),
            "The game's limit for new instances in an hour. Forever's isn't known: 5 is Classic's. When the game"
            .. " says too many, the log here shows the count it was at")
        Row("Instances a day", S.Stepper(c, function() return YippRouteDB.instanceDay or 30 end,
            function(v) YippRouteDB.instanceDay = v end, 1, 100, 1, 110), "30 on Classic")
        Row("Back in within (minutes)", S.Stepper(c, function() return YippRouteDB.instanceSame or 30 end,
            function(v) YippRouteDB.instanceSame = v end, 1, 120, 5, 110),
            "Going back into the dungeon you just left, with the same group leader and no reset seen, within this"
            .. " many minutes is the same instance and doesn't count again (the game keeps the copy's ID secret"
            .. " on Forever, so this is how Headstart tells)")
        Row("Count all my characters together", S.Switch(c, function() return YippRouteDB.instanceAccount == true end,
            function(on) YippRouteDB.instanceAccount = on end),
            "Off: each character has its own count (Classic's rule). On: every character on this account counts"
            .. " toward one limit (the rule in later expansions)")
        Row("Warn on screen near the limit", S.Switch(c, Opt("instanceWarn"), function(on) YippRouteDB.instanceWarn = on end),
            "One instance before the limit, and at it, the middle of the screen says so too. Chat always does")
        local HUD = { { "icon", "A small icon" }, { "log", "A small log" }, { "off", "Nothing" } }
        local hudMode
        hudMode = S.Dropdown(c, 170, HUD, function(v)
            YippRouteDB.instanceHud = v
            YR.InstanceHudApply()
            hudMode:Refresh()
        end)
        function hudMode:Refresh() for _, o in ipairs(HUD) do if o[1] == YR.InstanceHudMode() then self:SetValue(o[2]) end end end
        Row("On screen", hudMode, "The icon has this hour's count on it (green, yellow one before the limit, red at it,"
            .. " with the wait for a slot under it); hover it for today's count and your latest runs. The log shows"
            .. " the counts and your latest runs as text. Click either for this page; Shift-drag moves it")
        Row("Show it always", S.Switch(c, function() return YippRouteDB.instanceHudAlways == true end, function(on)
            YippRouteDB.instanceHudAlways = on
            YR.InstanceHudApply()
        end), "Off: only while you're in an instance or have gone into one this hour")
        Row("Runs in the small log", S.Stepper(c, function() return YippRouteDB.instanceHudRows or 3 end, function(v)
            YippRouteDB.instanceHudRows = v
            YR.InstanceHudApply()
        end, 0, 8, 1, 110))
        Row("Back to its place", S.Button(c, "Reset", function() YR.InstanceHudResetPosition() end, nil, 90),
            "The left of the screen, where it starts")
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
    inst.list = List(page, CW - 32, math.floor((CH - 120 - 64) / 26), 26, function(r, i)
        local e = inst.rows[i]
        r:Select(false)
        r.when:SetText(date("%a %H:%M", e.entered))
        r.name:SetText((e.name or "?") .. ((YippRouteDB.instanceAccount == true) and ("  |cff999999" .. tostring(e.char):match("^[^%-]+") .. "|r") or ""))
        local long = (e.left or (GetServerTime and GetServerTime() or time())) - e.entered
        r.time:SetText(YR.InstanceClock(long) .. (e.left and "" or "  |cff66ccffnow|r"))
        r.xp:SetText((e.xp or 0) > 0 and (BreakUpLargeNumbers and BreakUpLargeNumbers(e.xp) or tostring(e.xp)) .. " XP" or "")
        r.gold:SetText((e.money or 0) > 0 and Money(e.money) or "")
        r.flag:SetText(e.again and ("back in x" .. e.again) or "")
    end, function() return inst.rows and #inst.rows or 0 end, function(r)
        r.when = S.Text(r, 11, S.C.muted)
        r.when:SetPoint("LEFT", 10, 0)
        r.name = S.Text(r, 13)
        r.name:SetPoint("LEFT", 100, 0)
        r.name:SetWidth(300)
        r.name:SetJustifyH("LEFT")
        r.time = S.Text(r, 12, S.C.sub)
        r.time:SetPoint("LEFT", 420, 0)
        r.xp = S.Text(r, 12, S.C.sub)
        r.xp:SetPoint("LEFT", 530, 0)
        r.gold = S.Text(r, 12, S.C.gold or S.C.sub)
        r.gold:SetPoint("LEFT", 650, 0)
        r.flag = S.Text(r, 11, S.C.muted)
        r.flag:SetPoint("RIGHT", -10, 0)
    end)
    inst.list:SetPoint("TOPLEFT", 16, -120)
    local reset = S.Button(page, "A reset I missed", function() YR.InstanceResetSeen() YR:RefreshWindow() end, nil, 150)
    reset:SetPoint("BOTTOMLEFT", 136, 14)           -- beside Reload UI
    reset.tip = "The next time you go into any of these, it's a new instance (when the game's reset message didn't reach Headstart)"
    local clear = S.Button(page, "Clear the log", function() YR.InstanceForget() YR:RefreshWindow() end, nil, 130)
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
    inst.hint:SetText(("Each new dungeon or raid you go into counts for an hour and a day.%s"):format(last and
        (" The game last said too many at %d this hour (%s)."):format(last.hour, date("%a %H:%M", last.at)) or
        " Limits and what shows on screen: Settings, at the right."))
    inst.rows = InstanceRows()
    inst.list:Refresh()
end

local function RefreshInstances()
    win.subtitle:SetText("")
    inst.Refresh()
    for _, ctl in ipairs(qolPages.instances.controls) do if ctl.Refresh then ctl:Refresh() end end
end

-- Skins: RestedXP's guide window (RXPSkin.lua) and the game's damage meter (DamageSkin.lua). For each:
-- which look, and the Headstart look's colours.
local BuildSkins = QoLPage("skins", function(L, c, Section, Row, Opt)
    do
        Section("RestedXP guide window", "RestedXP's window in another look", { icon = 134939 })
        local LOOKS = { { "off", "RestedXP's own" }, { "headstart", "Headstart" }, { "blizzard", "Blizzard" } }
        local look
        look = S.Dropdown(c, 190, LOOKS, function(v)
            if not YR.SetRXPSkin(v) then YR.Print("RestedXP isn't loaded: nothing to skin.") end
            look:Refresh()
        end)
        function look:Refresh() for _, o in ipairs(LOOKS) do if o[1] == YR.RXPSkinMode() then self:SetValue(o[2]) end end end
        Row("Look", look, "Headstart: flat and dark like this window, a thin line for a border and one accent colour."
            .. " Blizzard: the game's own frame, fill and gold titles, with no colours to pick. RestedXP's own: the theme you had"
            .. " before. Both are also in RestedXP's own theme list")

        Section("RestedXP colours", "for its Headstart look; the Blizzard look has none", { icon = 133741 })
        local function Accent()
            YippRouteDB.rxpSkinAccent = YippRouteDB.rxpSkinAccent or YR.RXPSkinAccent()
            return YippRouteDB.rxpSkinAccent
        end
        local function Back()
            YippRouteDB.rxpSkinBack = YippRouteDB.rxpSkinBack or YR.RXPSkinBack()
            return YippRouteDB.rxpSkinBack
        end
        Row("Accent", Swatch(c, "accent", Accent, YR.RXPSkinApply),
            "The title and the line under it, the step you're on, the scroll bar, the map pins and the links in"
            .. " tooltips - in the Headstart look. The Blizzard look stays in the game's gold")
        Row("Accent in my class colour", S.Switch(c, function() return YippRouteDB.rxpSkinClass == true end, function(on)
            YippRouteDB.rxpSkinClass = on
            YR.RXPSkinApply()
        end), "Each character gets its class's colour, whatever is picked above")
        Row("Background", Swatch(c, "back", Back, YR.RXPSkinApply), "The window's fill, and how see-through it is")
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
        Row("A ready accent", preset)
        Row("Back to the first colours", S.Button(c, "Reset", function()
            YippRouteDB.rxpSkinAccent, YippRouteDB.rxpSkinBack, YippRouteDB.rxpSkinClass = nil, nil, nil
            YR.RXPSkinApply()
            YR:RefreshWindow()
        end, nil, 90))
    end
    do
        Section("Damage meter", "the game's own meter with a tidy top bar", { icon = 132349 })
        local LOOKS = { { "off", "Blizzard's own" }, { "headstart", "Headstart" }, { "blizzard", "Blizzard, tidied" } }
        local look
        look = S.Dropdown(c, 190, LOOKS, function(v)
            YR.SetDamageSkin(v)
            if v ~= "off" and not YR.DamageSkinAvailable() then
                YR.Print("the damage meter isn't on screen: turn it on in the game's options and the look is put on it.")
            end
            look:Refresh()
        end)
        function look:Refresh() for _, o in ipairs(LOOKS) do if o[1] == YR.DamageSkinMode() then self:SetValue(o[2]) end end end
        Row("Look", look, "Both looks put the top bar in order: the title on one line at the left; the fight's timer and"
            .. " the three buttons, at one size, at the right. Headstart: a flat dark card in colours you pick."
            .. " Blizzard, tidied: the game's dark fill and thin frame, the title in gold. The bars themselves stay"
            .. " with the meter's own settings in Edit Mode")

        Section("Damage meter colours", "for its Headstart look", { icon = 133741 })
        local function Accent()
            YippRouteDB.dmgSkinAccent = YippRouteDB.dmgSkinAccent or YR.DamageSkinAccent()
            return YippRouteDB.dmgSkinAccent
        end
        local function FrameColour()
            YippRouteDB.dmgSkinFrame = YippRouteDB.dmgSkinFrame or YR.DamageSkinFrame()
            return YippRouteDB.dmgSkinFrame
        end
        Row("Accent", Swatch(c, "accent", Accent, YR.DamageSkinApply), "The title and the line under the top bar")
        Row("Accent in my class colour", S.Switch(c, function() return YippRouteDB.dmgSkinClass == true end, function(on)
            YippRouteDB.dmgSkinClass = on
            YR.DamageSkinApply()
        end))
        Row("Frame", Swatch(c, "frame", FrameColour, YR.DamageSkinApply), "The window's fill, and how see-through it is")
        Row("Back to the first colours", S.Button(c, "Reset", function()
            YippRouteDB.dmgSkinAccent, YippRouteDB.dmgSkinFrame, YippRouteDB.dmgSkinClass = nil, nil, nil
            YR.DamageSkinApply()
            YR:RefreshWindow()
        end, nil, 90))
    end
end)

-- Blizzard's windows: the talent window (TalentFade.lua: how see-through its background is, its size,
-- moving it) and the bag windows (Movers.lua).
local BuildWindows = QoLPage("windows", function(L, c, Section, Row, Opt)
        Section("Talent window", "see where you're running with it open", { icon = 136243 })
        Row("See-through background (percent)", S.Slider(c, 0, 100, 5, YR.TalentFade, YR.SetTalentFade, 260),
            "How much of the talent window's background is faded away. 0: Blizzard's own. The talents, texts and"
            .. " buttons stay as they are")
        Row("Sliders on the talent window", S.Switch(c, Opt("talentFadeSlider"), function(on)
            YippRouteDB.talentFadeSlider = on
            YR.TalentFadeApply()
        end), "See-through at the bottom left of the talent window, and the size at the bottom right (5 or 1 percent a tap), to change them while you look at it")
        Row("Size (percent)", S.Slider(c, 50, 150, 1, YR.TalentScale, YR.SetTalentScale, 260),
            "The talent window smaller or larger. 100: Blizzard's own. The spellbook keeps its size. Not in combat")
        Row("Move it by dragging", S.Switch(c, Opt("talentMove"), function(on)
            YippRouteDB.talentMove = on
            YR.TalentPlace()
        end), "Drag the window by its title bar or anywhere that isn't a button or a talent; it opens there from"
            .. " then on. The spellbook is the same window,"
            .. " so it moves too. Not in combat")
        Row("Back to its place", S.Button(c, "Reset", function() YR.TalentResetPosition() end, nil, 90),
            "The middle of the screen, where Blizzard opens it")

        Section("Blizzard's bars", "out of the way until you want them", { icon = 133633 })
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
        Row("Bag bar", BarDrop("bagBar"), "The row of bags at the bottom right. Only under the mouse: it's see-through until"
            .. " you point where it is. Hidden: gone, and its buttons can't be clicked by accident (B still opens your bags)."
            .. " It keeps its place in Edit Mode, and shows while Edit Mode is open")
        Row("Micro menu", BarDrop("microMenu"), "The row of small buttons: character, talents, the game menu and the rest."
            .. " The same three choices; your keys for them work either way")

        Section("Chat buttons", "the strip beside the chat, and the two buttons over it", { icon = 133469 })
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
        Row("Button strip", strip, "Slim: the strip beside the chat a good third narrower, its buttons (the chat menu,"
            .. " channels) small with one plain icon each; they work as before, and the strip still fades in under the"
            .. " mouse. Hidden: gone, the chat menu with it. Either way the chat window can be moved closer to the"
            .. " screen's edge in Edit Mode")
        Row("Hide the text-to-speech button", S.Switch(c, function() return YippRouteDB.chatTTSHide == true end, function(on)
            YippRouteDB.chatTTSHide = on or nil
            YR.BarHideApply()
        end), "The speaker button over the strip")
        Row("Hide the social button", S.Switch(c, function() return YippRouteDB.chatSocialHide == true end, function(on)
            YippRouteDB.chatSocialHide = on or nil
            YR.BarHideApply()
        end), "The friends button over the chat, with the number of friends online. Your key for the social window still works")

        Section("Bag windows", "moved where you want them", { icon = 134400 })
        Row("Move the combined bag", S.Switch(c, function() return YippRouteDB.moveBag == true end, function(on)
            YippRouteDB.moveBag = on
            YR.MoverPlace("bag")
        end), "Drag Blizzard's combined bag by its title bar; it opens there from then on. Off: Blizzard's own"
            .. " place. Not in combat")
        Row("Move the reagent bag", S.Switch(c, function() return YippRouteDB.moveReagentBag == true end, function(on)
            YippRouteDB.moveReagentBag = on
            YR.MoverPlace("reagentBag")
        end), "The same for the reagent bag, on its own")
        Row("Back to their places", S.Button(c, "Reset", function()
            YR.MoverReset("bag")
            YR.MoverReset("reagentBag")
        end, nil, 90), "Both where Blizzard opens them, from the next time they open")
end)

local function QoLRefresh(key, extra)
    return function()
        for _, ctl in ipairs(qolPages[key].controls) do if ctl.Refresh then ctl:Refresh() end end
        if extra then extra() end
    end
end

-- QoL's menu, grouped by where you meet the thing in play: what Headstart puts on your screen, what it
-- does with your bags and gear, what it does around other players and tells you, and a new character.
local CATEGORIES = {
    { group = "On screen" },
    { key = "xpbar", label = "XP bar", build = BuildXPBar, refresh = QoLRefresh("xpbar"), icon = 236562,
      status = function() return YR.XPBarOn() end, scope = "Every character on this account",
      desc = "Your own experience bar: its size, place, colours and the words on it, with XP an hour, time and kills to ding." },
    { key = "camps", label = "Camps & flights", build = BuildCamps, refresh = QoLRefresh("camps"), icon = 135805,
      status = function() return YR.Option("camp") or YR.Option("flightTimer") end, scope = "Every character on this account",
      desc = "The campfire on screen while a camp is near or its buff runs, and the bar while you fly." },
    { key = "swing", label = "Swing timer", build = BuildSwing, refresh = QoLRefresh("swing"), icon = 132349,
      status = function() return YR.SwingOn() end, scope = "Every character on this account",
      desc = "Blizzard's swing bars dressed to be seen - your colours, larger text, the weapon's icon, the swing's length - or Headstart's own bars in their place." },
    { key = "skins", label = "Skins", build = BuildSkins, refresh = QoLRefresh("skins"), icon = 134939,
      status = function() return YR.RXPSkinMode() ~= "off" or YR.DamageSkinMode() ~= "off" end, scope = "Every character on this account",
      desc = "RestedXP's guide window and the game's damage meter in Headstart's flat look with your colours, or in Blizzard's." },
    { key = "windows", label = "Windows", build = BuildWindows, refresh = QoLRefresh("windows"), icon = 136243,
      status = function() return YR.TalentFade() > 0 or YR.Option("talentMove") or YippRouteDB.moveBag == true or YippRouteDB.moveReagentBag == true
          or YippRouteDB.bagBar ~= nil or YippRouteDB.microMenu ~= nil or YippRouteDB.chatStrip ~= nil end,
      scope = "Every character on this account",
      desc = "The talent window see-through, resized and moved, the bag bar and micro menu hidden or shown under the mouse, and the bag windows moved." },
    { group = "Bags & gear" },
    { key = "bags", label = "Bank & mail", build = BuildBags, refresh = QoLRefresh("bags"), icon = 133633,
      status = function() return YR.Option("bankAuto") or YR.Option("bankButton") or YR.Option("mailButton") end, scope = "Every character on this account",
      desc = "Crafting mats and recipes you can't use yet: into the bank, or in the mail to your alt." },
    { key = "vendors", label = "Vendors", build = BuildVendors, refresh = QoLRefresh("vendors"), icon = 133784,
      status = function() return YR.Option("restock") end, scope = "Every character on this account",
      desc = "Your reagents, ammo and own list bought back up to what you keep, at any vendor who sells them." },
    { key = "gear", label = "Gear & rewards", build = BuildGear, refresh = QoLRefresh("gear", RefreshRewards), icon = 132739,
      status = function() return YR.Option("simTooltip") or YR.Option("upgrades") end, scope = "Every character; quest rewards per class",
      desc = "Better gear in your bags pointed out, and quest rewards picked for you." },
    { key = "trinkets", label = "Trinkets & sets", build = BuildTrinkets, refresh = QoLRefresh("trinkets", RefreshTrinkets),
      icon = 133434, status = function() return YR.Option("trinketBar") or YippRouteDB.trinketAuto == true end,
      scope = "Every character; the swap order per character",
      desc = "Trinket buttons with your others a click away, trinkets swapped as they're used, and keys for your gear sets." },
    { group = "Group & alerts" },
    { key = "group", label = "Group", build = BuildGroup, refresh = QoLRefresh("group"), icon = 134149,
      status = function() return YR.Option("groupBar") end, scope = "Every character on this account",
      desc = "Into a group for a kill and out again, and quests shared and accepted without the clicking." },
    { key = "instances", label = "Instances", build = BuildInstances, refresh = RefreshInstances, icon = 134237,
      status = function() return YR.Option("instanceTrack") end, scope = "Every character on this account",
      desc = "The new dungeons and raids you went into this hour and today, against the limit, and the wait for a free slot." },
    { key = "reminders", label = "Reminders & sounds", build = BuildReminders, refresh = QoLRefresh("reminders"), icon = 134327,
      status = function() return YR.Option("remindTrainer") or YR.Option("remindTalents") or YR.Option("durability") or YR.Option("craftRemind") or YR.Option("levelShot") or YippRouteDB.whisperSound ~= nil end, scope = "Every character on this account",
      desc = "One quiet line when there is something to do - the trainer, talents, repairs, things to make - and a sound for whispers." },
    { group = "New character" },
    { key = "character", label = "Character setup", build = BuildSetup, refresh = RefreshSetup, icon = 134166,
      scope = function() return "Every " .. (CLASS_NAME[ViewClass()] or "character") .. "; chat and Edit Mode for all" end,
      desc = "Your main's bars, macros and settings on a new character - or plan the bars here." },
    { key = "trainer", label = "Trainer", build = BuildTrainer, refresh = function() trainer.refresh() end, icon = 133741,
      status = function() return YR.Option("autoTrain") end, scope = function() return "Every " .. (UnitClass("player") or "character") .. " on this account" end,
      desc = "Your class spells learned as the trainer opens, the ones you choose, as your gold allows." },
}
-- Older names for a page ("qol" was the one long page; the skins and the talent window had their own).
local CATEGORY_ALIAS = { qol = "xpbar", main = "xpbar", rxpskin = "skins", dmgskin = "skins", talentwin = "windows" }

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

local function ShowTab(key)
    key = CATEGORY_ALIAS[key] or key
    settings.tab = key
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
    return function(t)
        icon:SetTexture(t.icon)
        title:SetText(t.label)
        desc:SetText(t.desc or "")
        local scope = type(t.scope) == "function" and t.scope() or t.scope
        scopeText:SetText(scope and ("Saved as you change it\n" .. scope) or "Saved as you change it")
    end
end

-- QoL: its menu is the window's left side on that tab (ui.sideQ); the page is what is beside it.
local function BuildSettings(page)
    settings.index = {}
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
        results:Hide()
        ShowTab(e.key)
        if e.key == "instances" and inst.View then inst.View("settings") end
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
            local hay = (e.label .. " " .. (e.tip or "") .. " " .. LabelOf(e.key)):lower()
            if hay:find(text, 1, true) then found[#found + 1] = e end
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
    search = S.Input(nav, { width = NAV_W - 24, placeholder = "Find a setting", onChange = Search })
    search:SetPoint("TOPLEFT", 12, -12)
    YR.SettingsSearch, YR.SettingsGo = Search, Go      -- for tests

    -- everything on this tab on or off
    local master = MasterRow(nav, NAV_W, "Quality of life", function() return YR.QoLOn() end, YR.SetQoLOn,
        "Off: every page in this menu is off at once - bars, buttons, reminders, bank and mail help, gear advice,"
        .. " trinkets, the XP bar, the instance tracker, the skins. Your settings are kept and come back as you left"
        .. " them. For the whole account; finishes its work on a reload (/headstart qol on|off)")
    master:SetPoint("TOPLEFT", 12, -44)
    -- with EllesmereUI: which of ours start off, at the foot of the menu
    local with = {}
    for _, pair in ipairs({ { "flightTimer", "the flight timer" }, { "durability", "the durability warning" },
        { "autoTrain", "auto-train" }, { "talentMove", "moving the talent window" },
        { "talentFadeSlider", "the sliders on the talent window" }, { "groupAccept", "accepting shared quests" },
        { "xpbar", "the XP bar" } }) do
        if YR.EllesmereHas(pair[1]) then with[#with + 1] = pair[2] end
    end
    if #with > 0 then
        local note = CreateFrame("Frame", nil, nav)
        note:SetSize(NAV_W - 24, 16)
        note:SetPoint("BOTTOMLEFT", 12, 10)
        note.text = S.Text(note, 11, S.C.muted)
        note.text:SetPoint("LEFT")
        note.text:SetText(("With EllesmereUI: %d start off"):format(#with))
        note:EnableMouse(true)
        note:SetScript("OnEnter", function(self)
            S.Tip(self, "EllesmereUI does these too, so Headstart's start off until you turn them on yourself: "
                .. table.concat(with, ", ") .. ". Anything you've set yourself stays as you set it")
        end)
        note:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local y = -82
    for _, t in ipairs(CATEGORIES) do
        if t.group then
            local g = S.Text(nav, 11, S.C.muted)
            g:SetPoint("TOPLEFT", 18, y - 8)
            g:SetText(t.group:upper())
            y = y - 28
        else
            local b = CreateFrame("Button", nil, nav)
            b:SetSize(NAV_W - 16, 28)
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
                    self.dot:SetVertexColor(unpack(t.status() and S.C.green or S.C.muted))
                else
                    self.dot:Hide()
                end
            end
            b:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(unpack(S.C.hover)) end end)
            b:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end end)
            b:SetScript("OnClick", function() search:SetValue("") results:Hide() ShowTab(t.key) end)
            t.button = b
            y = y - 30
        end
    end

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
    settings.tab = "xpbar"
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
    desc = "Headstart's routes on or off, recording runs, death skips, group play and the level splits." }

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
    { key = "settings", tab = "qol", build = BuildSettings, refresh = RefreshSettings },
}
local PAGE_TAB = {}
for _, p in ipairs(PAGES) do PAGE_TAB[p.key] = p.tab end
local lastLevelling          -- the Levelling page last shown, for coming back to that tab
function YR.WindowTab() return PAGE_TAB[current] end      -- for the tests

local function Show(key)
    if not PAGE_TAB[key] then           -- a QoL page by its own name ("instances", "camps", ...)
        ShowTab(key)
        key = "settings"
    end
    current = key
    local tab = PAGE_TAB[key]
    if tab == "levelling" then lastLevelling = key end
    S.CloseMenu()
    ui.sideL:SetShown(tab == "levelling")
    ui.sideQ:SetShown(tab == "qol")
    for name, b in pairs(ui.topTabs) do b:Select(name == tab) end
    for _, p in ipairs(PAGES) do
        pages[p.key]:SetShown(p.key == key)
        if p.button then p.button:Select(p.key == key) end
    end
    YR:RefreshWindow()
end

-- Open QoL on one of its pages ("camps", "bags", ..., "character", "trainer"), or Route settings ("route").
function YR:ShowSettingsTab(key)
    settings.viewClass = nil          -- this character's class
    if key == "route" then YR:ToggleWindow("route") return end
    YR:ToggleWindow("settings")
    ShowTab(key)
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
        self.text:SetTextColor(unpack(on and { 1, 1, 1, 1 } or over and S.C.text or S.C.sub))
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
local function TopTabs(head, onLevelling, onQoL)
    local track = CreateFrame("Frame", nil, head)
    track:SetSize(SEG_W * 2 + 6, SEG_H + 6)
    track:SetPoint("CENTER", head, "CENTER", 0, 0)
    track:SetFrameLevel(head:GetFrameLevel() + 2)      -- over the bar you drag the window by
    S.Rounded(track, "BACKGROUND", "round"):SetVertexColor(unpack(S.C.field))
    S.Rounded(track, "BORDER", "roundline"):SetVertexColor(unpack(S.C.lineHi))
    local qol = Segment(track, "QoL", "Interface\\Icons\\Trade_Engineering")
    qol:SetPoint("LEFT", 3, 0)
    qol:SetScript("OnClick", onQoL)
    local levelling = Segment(track, "Levelling", "Interface\\Icons\\INV_Misc_Map_01")
    levelling:SetPoint("RIGHT", -3, 0)
    levelling:SetScript("OnClick", onLevelling)
    return { levelling = levelling, qol = qol }, track
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
        function() Show(lastLevelling or (YR.RoutesOn() and "routes" or "route")) end,
        function() Show("settings") end)
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
    ui.sideL, ui.sideQ = side, Side(NAV_W, S.C.side)
    pages = {}
    ui.routeTabs = {}
    -- The routes switch, Levelling's pages, then every route in a list that scrolls (more routes than room)
    local routes = MasterRow(side, SIDE, "Routes", function() return YR.RoutesOn() end, YR.SetRoutesOn,
        "On: your routes are loaded into RestedXP, and what they need is kept in your bags and bought for you."
        .. " Off: none of that. For the whole account; takes a /reload (/headstart routes on|off)")
    routes:SetPoint("TOPLEFT", 12, -12)
    local y = -50
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
        page:SetPoint("TOPLEFT", p.tab == "qol" and NAV_W or SIDE, -HEAD)
        page:SetPoint("BOTTOMRIGHT")
        p.build(page)
        pages[p.key] = page
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

function Headstart_OnAddonCompartmentClick()
    YR:ToggleWindow()
end
