-- The Headstart window. Opened from the minimap button or /yroute. Four tabs at the top - QoL, Interface,
-- Levelling and Character setup - each with its own menu down the left:
--
--   Levelling  Next route (where it opens: the route to take, and the next ones), All routes, Talents, This run,
--              and Settings at the foot of the menu (the owner, 2026-10-21: "the levelling tab is very confusing
--              for new users" - the route list in the menu, the routes switch at its top). A route opens in the
--              editor from All routes (Edit) or Next route (See the steps): the steps on the left; the selected
--              step in full on the right, where every line of it can be changed, added or removed: places (with
--              "Here"), quests, targets, levels to farm to, gold to farm, classes that see it. Save hands it to
--              RestedXP. This run: what this character did; "Add to route" makes any of it a step of the open
--              route. Import a route and Share are at the foot of All routes.
--   QoL        the settings pages for what Headstart does for you (Find a setting at the top), Instances among them.
--   Interface  the settings pages for what it puts on your screen and does to Blizzard's: the same menu, its
--              own pages (CATEGORIES: each page's tab).
--
-- This file is the Headstart_Options addon: load on demand, loaded by Headstart the first time the
-- window is asked for (YR.LoadWindow, Core.lua), so none of it is in memory for someone who never
-- opens it. An addon of its own has a table of its own: Headstart's is handed over as HeadstartNS.
local YR = _G.HeadstartNS
local S = YR.Style

-- (1140 x 680 until 2026-10-20: "the window is too big" - the owner)
local W, H, HEAD = 980, 600, 48
-- Every tab's menu is as wide (Levelling's was 180, QoL's 190: the edge moved as you changed tabs); a page is what
-- is left beside it, under a heading.
local NAV_W, TITLE_H = 190, 66
local SIDE = NAV_W
local PW, PH = W - SIDE, H - HEAD          -- a Levelling page: what is left beside its menu
local CW, CH = W - NAV_W, PH - TITLE_H
local LIST_W, ROW = 370, 24
local win, pages, current
local edit = { key = nil, header = nil, steps = nil, parsed = {}, dirty = false, sel = nil, line = nil, filter = "" }
local ui = {}
-- What the tour (Welcome.lua) points at, by name: parts of this window, kept as they are made.
local tourAt = {}
--- A part of the window for the tour to point at ("search", "menu:general", "automation", "qol", "setup",
--- "levelling", "arrange"), or nil while it isn't made.
function YR.TourTarget(name) return tourAt[name] end

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
-- A scrolling list of fixed rows. build(row) makes a row's parts once; fill(row, index) fills it. quiet: the row
-- picked is raised, without the accent and its bar (This run: the accent is for switches and the tab you are on).
-- ---------------------------------------------------------------------------
local function List(parent, width, count, rowH, fill, total, build, quiet)
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
            if on then self.bg:SetColorTexture(unpack(quiet and S.C.raised or S.C.accentD))
            elseif self:IsMouseOver() then self.bg:SetColorTexture(unpack(S.C.hover))      -- drawn again under the mouse: still lit
            else self.bg:SetColorTexture(0, 0, 0, 0) end
            self.bar:SetShown(on and not quiet)
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

    -- a step's tags: checkboxes, their names ticking them too (they were switches: a switch is a feature's alone)
    local function TagCheck(label, tag, x)
        local box = S.Check(body, function() return edit.sel and YR.HasTag(Parsed(edit.sel), tag) ~= nil end,
            function(on) YR.SetTag(Parsed(edit.sel), tag, on, tag == "completewith" and "next" or nil) Commit() YR:RefreshWindow() end)
        box:SetPoint("TOPLEFT", x, -130)
        local name = CreateFrame("Button", nil, body)
        name.text = S.Text(name, 13, S.C.sub)
        name.text:SetPoint("LEFT")
        name.text:SetText(label)
        name:SetSize(name.text:GetStringWidth() + 4, 20)
        name:SetPoint("LEFT", box, "RIGHT", 8, 0)
        name:SetScript("OnClick", function() box:Click() end)
        return box
    end
    ui.optional = TagCheck("Optional", "optional", 14)
    ui.sticky = TagCheck("Sticky", "sticky", 120)
    ui.together = TagCheck("Ends with the next step", "completewith", 210)

    -- the step's lines
    local actions = S.Text(body, 11, S.C.muted)
    actions:SetPoint("TOPLEFT", 14, -164)
    actions:SetText("ACTIONS")
    ui.lines = List(body, CW - 28, 5, 24, function(r, i)
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

    -- add an action: on the line of the actions' heading, at the right (under the box it ran out of the card)
    ui.add = S.Dropdown(body, 160, AddChoices, function(choice)
        if not edit.sel then return end
        local lines = Parsed(edit.sel).lines
        local at = (edit.line or #lines) + 1
        table.insert(lines, at, NewLine(choice))
        edit.line = at
        Commit() YR:RefreshWindow()
    end)
    ui.add:SetValue("+  Add action")
    ui.add.label:SetTextColor(unpack(S.C.sub))
    ui.add:SetHeight(22)
    ui.add:SetPoint("BOTTOMRIGHT", ui.lines, "TOPRIGHT", 0, 4)
    ui.add:HookScript("OnEnter", function(self) S.Tip(self, "New places are where you stand; kill and talk use your target.") end)
    ui.add:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- the box under the actions down to the card's foot
    ed:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -14, 12)

    ui.raw = S.Button(body, "Edit as text", function() YR:EditRawStep() end, "ghost", 100)
    ui.raw:SetPoint("TOPRIGHT", -8, -9)
    ui.raw.tip = "The whole step as RestedXP text, for anything the fields don't cover"
    ui.raw:SetTextColour(S.C.sub)
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
        if YR.RouteProgressForget then YR.RouteProgressForget() end
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
    local export = S.Button(page, "Share...", function() YR:ShareOpen() end, nil, 90)
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
    RefreshInspector()
end

-- ---------------------------------------------------------------------------
-- A Levelling page's heading, as a QoL page's (PageHead): its icon, its name and what it is for, over a rule. A page
-- under another (the editor, Share: under All routes) has the way back before its name. head.right is where a page
-- puts what it shows at the top right (the middle of its right edge).
-- ---------------------------------------------------------------------------
local function LevelHead(page)
    local h = {}
    local frame = CreateFrame("Frame", nil, page)
    frame:SetSize(42, 42)
    frame:SetPoint("TOPLEFT", 20, -11)
    S.Border(frame, S.C.lineHi)
    h.icon = frame:CreateTexture(nil, "ARTWORK")
    h.icon:SetPoint("TOPLEFT", 1, -1)
    h.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    h.back = CreateFrame("Button", nil, page)
    h.back:SetHeight(20)
    h.back:SetPoint("TOPLEFT", frame, "TOPRIGHT", 12, 0)
    h.back.text = S.Text(h.back, 15, S.C.sub)
    h.back.text:SetPoint("LEFT")
    h.back:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(S.C.text)) end)
    h.back:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(S.C.sub)) end)
    h.back:Hide()
    h.slash = S.Text(page, 15, S.C.muted)
    h.slash:SetPoint("LEFT", h.back, "RIGHT", 6, 0)
    h.slash:SetText("/")
    h.slash:Hide()
    h.title = S.Text(page, 17)
    h.desc = S.Text(page, 12, S.C.muted)
    h.desc:SetPoint("TOPLEFT", frame, "TOPRIGHT", 12, -26)
    h.desc:SetJustifyH("LEFT")
    h.right = CreateFrame("Frame", nil, page)
    h.right:SetSize(1, 1)
    h.right:SetPoint("RIGHT", page, "TOPRIGHT", -24, -31)
    local strip = page:CreateTexture(nil, "BORDER")
    strip:SetPoint("TOPLEFT", 16, -TITLE_H + 4)
    strip:SetPoint("TOPRIGHT", -16, -TITLE_H + 4)
    S.Hair(strip, "h")
    S.Set(strip, S.C.line)
    --- o: icon, title, desc, back ({ its name, what it does }), right (how wide what stands at the top right is)
    function h:Set(o)
        self.icon:SetTexture(o.icon)
        self.title:SetText(o.title or "")
        self.title:ClearAllPoints()
        self.back:SetShown(o.back ~= nil)
        self.slash:SetShown(o.back ~= nil)
        if o.back then
            self.back.text:SetText(o.back[1])
            self.back:SetWidth(self.back.text:GetStringWidth() + 2)
            self.back:SetScript("OnClick", o.back[2])
            self.title:SetPoint("LEFT", self.slash, "RIGHT", 6, 0)
        else
            self.title:SetPoint("TOPLEFT", frame, "TOPRIGHT", 12, -2)
        end
        self.desc:SetText(o.desc or "")
        self.desc:SetPoint("RIGHT", page, "RIGHT", -24 - (o.right or 0), 0)
    end
    return h
end

-- A rounded panel (the settings list's look): the card's colour, a line round it, and a soft shadow under it when
-- it stands out from the page.
local function Panel(f, shadow, color)
    S.Rounded(f, "BACKGROUND", "round"):SetVertexColor(unpack(color or S.C.card))
    S.Rounded(f, "BORDER", "roundline"):SetVertexColor(unpack(S.C.line))
    if shadow then S.Shadow(f, 14, 3, 0.5) end
    return f
end

-- Two choices side by side in one rounded track, the one picked raised (All routes: this character's or every race's).
--   get() is true for the first; set(first) picks.
local function Segmented(parent, first, second, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(28)
    S.Rounded(f, "BACKGROUND", "round"):SetVertexColor(unpack(S.C.field))
    S.Rounded(f, "BORDER", "roundline"):SetVertexColor(unpack(S.C.line))
    local function Part(label, value)
        local p = CreateFrame("Button", nil, f)
        p:SetHeight(22)
        p.fill = S.Rounded(p, "BACKGROUND", "round")
        p.text = S.Text(p, 13, S.C.sub)
        p.text:SetPoint("CENTER")
        p:SetScript("OnClick", function() set(value) end)
        p:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(S.C.text)) end)
        p:SetScript("OnLeave", function() f:Refresh() end)
        function p:SetLabel(t)
            self.text:SetText(t)
            self:SetWidth(math.floor(self.text:GetStringWidth() + 24))
        end
        p:SetLabel(label)
        return p
    end
    f.first, f.second = Part(first, true), Part(second, false)
    f.first:SetPoint("LEFT", 3, 0)
    f.second:SetPoint("LEFT", f.first, "RIGHT", 0, 0)
    function f:Refresh()
        local on = get() and true or false
        for _, p in ipairs({ self.first, self.second }) do
            local picked = (p == self.first) == on
            p.fill:SetVertexColor(unpack(picked and S.C.raised or { 0, 0, 0, 0 }))
            p.text:SetTextColor(unpack(picked and S.C.text or S.C.muted))
        end
        self:SetWidth(self.first:GetWidth() + self.second:GetWidth() + 6)
    end
    f:Refresh()
    return f
end

-- Seconds as "2 h 12 m" (under an hour "12 m").
local function Clock(sec)
    sec = math.floor(sec or 0)
    local h, m = math.floor(sec / 3600), math.floor(sec / 60) % 60
    return h > 0 and ("%d h %02d m"):format(h, m) or ("%d m"):format(m)
end

-- A little round light (green: running), with words after it, at a point.
local function StateLight(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(10, 20)
    f.dot = f:CreateTexture(nil, "ARTWORK")
    f.dot:SetSize(7, 7)
    f.dot:SetPoint("LEFT")
    S.ArtTexture(f.dot, "dot")
    f.text = S.Text(f, 13, S.C.sub)
    f.text:SetPoint("LEFT", f.dot, "RIGHT", 7, 0)
    function f:Set(text, color)
        self.text:SetText(text)
        self.dot:SetVertexColor(unpack(color or S.C.muted))
        self:SetWidth(14 + self.text:GetStringWidth())
    end
    return f
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
local DETAIL_W = 258
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
    run.head = LevelHead(page)
    run.head:Set({ icon = 134376, title = "This run", desc = "What this character did, in order. Save it as a route of your own.",
        right = 190 })
    run.state = StateLight(page)
    run.state:SetPoint("RIGHT", run.head.right, "RIGHT", 0, 0)

    -- recording: the switch, and stopping the run (its clock and its log) here
    local top = -(TITLE_H + 12)
    local strip = CreateFrame("Frame", nil, page)
    strip:SetPoint("TOPLEFT", 16, top)
    strip:SetPoint("TOPRIGHT", -24, top)
    strip:SetHeight(54)
    Panel(strip, true)
    local name = S.Text(strip, 14)
    name:SetPoint("TOPLEFT", 16, -11)
    name:SetText("Record this run")
    run.name = name
    local note = S.Text(strip, 12, S.C.muted)
    note:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    note:SetText("Every quest, trainer, vendor, flight and death, as you play.")
    run.record = S.Switch(strip, function() return YR.Option("logging") end, function(on) YR:SetLogging(on) YR:RefreshWindow() end)
    run.record:SetPoint("RIGHT", -16, 0)
    -- Stop run: the splits clock and the log end here, so a run finished (or abandoned) is timed to
    -- that moment. A run with a mistake in it can be kept out of "vs best".
    run.stop = S.Button(strip, "Stop this run", function()
        if YR:RunStopped() then YR:ResumeRun() else YR:StopRun() end
        YR:RefreshWindow()
    end, "ghost", 124)
    run.stop:SetTextColour(S.C.sub)
    run.stop:SetPoint("RIGHT", run.record, "LEFT", -12, 0)

    -- what it did, and the one picked in full beside it
    local listTop = top - 54 - 12
    local h = PH + listTop - 58
    local listW = PW - 16 - 24 - DETAIL_W - 12
    local frame = CreateFrame("Frame", nil, page)
    frame:SetPoint("TOPLEFT", 16, listTop)
    frame:SetSize(listW, h)
    Panel(frame)
    run.list = List(frame, listW - 6, math.floor((h - 8) / 30), 30, function(r, i)
        local a = run.actions[i]
        r.action, r.index = a, i
        r:Select(run.sel == i)
        r.icon:SetTexture(ACTION_ICON[a.e[2]])
        r.label:SetText(a.label)
        r.label:SetTextColor(unpack(run.sel == i and S.C.text or S.C.sub))
        r.when:SetText(date("%H:%M", a.e[1]))
    end, function() return run.actions and #run.actions or 0 end, function(r)
        r.when = S.Text(r, 12, S.C.muted)
        r.when:SetPoint("LEFT", 10, 0)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", 50, 0)
        r.label = S.Text(r, 13, S.C.sub)
        r.label:SetPoint("LEFT", 74, 0)
        r.label:SetPoint("RIGHT", -118, 0)
        -- (on the row under the mouse and the one picked only: on every row it was a column of orange)
        local add = S.Button(r, "+  Add to route", function() if r.action.step then YR:InsertStep(r.action.step) end end,
            "ghost", 112)
        add:SetPoint("RIGHT", -2, 0)
        add:SetHeight(24)
        add:SetTextColour(S.C.sub)
        add.tip = "Put this in the open route as a step, after the selected step"
        add:Hide()
        add:HookScript("OnLeave", function() if not r.selected and not r:IsMouseOver() then r:Tools(false) end end)
        r.tools[#r.tools + 1] = add
        r:SetScript("OnClick", function(self)
            run.sel = self.index
            run.list:Refresh()
            ShowDetails()
        end)
    end, true)
    run.list:SetPoint("TOPLEFT", 4, -4)
    local panel = CreateFrame("Frame", nil, page)
    panel:SetPoint("TOPLEFT", frame, "TOPRIGHT", 12, 0)
    panel:SetSize(DETAIL_W, h)
    Panel(panel)
    run.detail = S.Text(panel, 13)
    run.detail:SetPoint("TOPLEFT", 16, -14)
    run.detail:SetPoint("RIGHT", -16, 0)
    run.detail:SetWordWrap(true)
    run.detail:SetSpacing(4)
    run.detail:SetJustifyV("TOP")
    run.link = S.Input(panel, { width = DETAIL_W - 32 })
    run.link:SetPoint("BOTTOMLEFT", 16, 14)
    run.link:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    run.linkLabel = S.Text(panel, 12, S.C.muted)
    run.linkLabel:SetPoint("BOTTOMLEFT", run.link, "TOPLEFT", 0, 6)
    run.where = S.Text(panel, 12, S.C.muted)
    run.where:SetPoint("BOTTOMLEFT", 16, 70)
    run.where:SetWidth(DETAIL_W - 32)
    run.where:SetWordWrap(true)

    -- the foot: whether this run is one to beat, and making it a route
    run.counts = S.Check(page, function() return YR:RunCounts() end, function(on) YR:SetRunCounts(on) end)
    run.counts:SetPoint("BOTTOMLEFT", 18, 21)
    local beat = CreateFrame("Button", nil, page)
    beat.text = S.Text(beat, 13, S.C.sub)
    beat.text:SetPoint("LEFT")
    beat.text:SetText("A run to beat")
    beat:SetSize(beat.text:GetStringWidth() + 4, 20)
    beat:SetPoint("LEFT", run.counts, "RIGHT", 8, 0)
    beat:SetScript("OnClick", function() run.counts:Click() end)
    local beatNote = S.Text(page, 12, S.C.muted)
    beatNote:SetPoint("LEFT", beat, "RIGHT", 8, 0)
    beatNote:SetText("other characters' splits compare against it")
    -- This character's whole run as a route of its own (MyRoutes.lua): every stop a step, to reorder and
    -- edit in Routes and to play in RestedXP. Saving again replaces it.
    run.save = S.Button(page, "Save as route", function() YR.AskSaveRunAsRoute() end, "primary", 120)
    run.save:SetPoint("BOTTOMRIGHT", -24, 16)
    run.save.tip = "Your run as your own route: every quest stop, trainer, vendor, flight, death skip and grind"
        .. " a step, in the order you played. Edit and reorder it under All routes; RestedXP lists it under My routes."
        .. " Saving again replaces it. Our routes stay as they are"
    run.delete = S.Button(page, "Delete my route...", function() YR.AskDeleteMyRoutes() end, "ghost", 130)
    run.delete:SetTextColour(S.C.sub)
    run.delete:SetPoint("RIGHT", run.save, "LEFT", -6, 0)
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
    run.where:SetText(edit.key and ("Add to route puts it in %s, after step %s."):format(YR.GuideName(edit.key), edit.sel or "-")
        or "Open a route under All routes to add to it.")
    -- follow the newest actions, but don't jump away from where you were reading
    if run.seen ~= #run.actions then
        run.seen = #run.actions
        run.list.offset = math.max(0, #run.actions - #run.list.rows)
    end
    run.list:Refresh()
    ShowDetails()
    run.record:Refresh()
    local on, stopped = YR.Option("logging"), YR:RunStopped()
    run.name:SetTextColor(unpack(on and S.C.text or S.C.sub))
    run.stop:SetLabel(stopped and "Resume this run" or "Stop this run")
    run.stop.tip = stopped and "Carry on with this run: the time it was stopped doesn't count"
        or "End this run now: the splits and the log stop here"
    run.counts:Refresh()
    local played = YR.SplitsPlayed and YR.SplitsPlayed()
    if not on then run.state:Set("Not recording")
    elseif stopped then run.state:Set("Stopped")
    else run.state:Set("Recording" .. (type(played) == "number" and ("  ·  " .. Clock(played)) or ""), S.C.green) end
end

-- ---------------------------------------------------------------------------
-- Share: a route as text, to send (Share, from All routes or the editor), or one pasted in (Import a route).
-- Under All routes: its heading leads back there.
-- ---------------------------------------------------------------------------
local share = { mode = "import" }

function YR:ExportOpen()
    if not (edit.key and share.box) then return end
    share.box:SetText(YR.JoinSteps(edit.header, edit.steps))
    share.box:SetFocus()
    share.box:HighlightText()
    share.hint:SetText("Selected: press Ctrl+C to copy.")
end

--- Share the route open in the editor ("export"), or paste one in ("import").
function YR:ShareOpen(mode)
    share.mode = mode or "export"
    YR:ToggleWindow("share")
    if share.mode == "export" then
        YR:ExportOpen()
    elseif share.box then
        share.box:SetText("")
        share.hint:SetText("")
        share.box:SetFocus()
    end
end

local function BuildShare(page)
    share.head = LevelHead(page)
    local top = -(TITLE_H + 12)
    local area = S.ScrollArea(page, PW - 40, PH - TITLE_H - 12 - 58)
    area:SetPoint("TOPLEFT", 16, top)
    S.Fill(area, S.C.field)
    S.Border(area)
    local box = CreateFrame("EditBox", nil, area)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFont(S.FONT, 12, "")
    box:SetTextColor(unpack(S.C.text))
    box:SetWidth(PW - 56)
    box:SetTextInsets(10, 10, 10, 10)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    area:SetScrollChild(box)
    area:SetScript("OnMouseDown", function() box:SetFocus() end)
    share.box = box
    share.hint = S.Text(page, 12, S.C.muted)
    share.hint:SetPoint("BOTTOMLEFT", 18, 24)
    share.hint:SetPoint("RIGHT", page, "RIGHT", -230, 0)
    share.go = S.Button(page, "Import", function()
        if share.mode == "export" then YR:ExportOpen() return end
        local done, why = YR:ImportGuide(box:GetText())
        share.hint:SetText(done and ("|cff66dd88Imported:|r " .. done .. ". Reload to use it.") or ("|cffff7070Not imported:|r " .. why))
        if done then
            if edit.key then Open(edit.key) end
            StaticPopup_Show("HEADSTART_RELOAD")
        end
    end, "primary", 110)
    share.go:SetPoint("BOTTOMRIGHT", -24, 16)
    local clear = S.Button(page, "Clear", function() box:SetText("") share.hint:SetText("") end, "ghost", 70)
    clear:SetTextColour(S.C.sub)
    clear:SetPoint("RIGHT", share.go, "LEFT", -6, 0)
end

local function RefreshShare()
    win.subtitle:SetText("")
    local export = share.mode == "export"
    share.head:Set({ icon = 237381, back = { "All routes", function() YR:ToggleWindow("library") end },
        title = export and ("Share " .. (edit.key and YR.GuideName(edit.key) or "a route")) or "Import a route",
        desc = export and "Copy this text and send it: whoever pastes it under Import a route has the route."
            or "Paste a route someone shared with you, then Import. You can open it and change it like your own." })
    share.go:SetLabel(export and "Select all" or "Import")
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
--   On a QoL page (fold: its key) the cards are a ledger (the owner, 2026-10-21, picking it of three designs:
--   "Quiet ledger"): one list down the page, each feature a card the page's width - its icon, its name, a line
--   on what it does and its switch in the head - and its options under it, one to a line, only while it is on.
--   Nothing folds by hand: a feature that is off is its head alone. The cards under one move as it opens or
--   shuts, and so does whatever a page put under its cards (L.Tail).
local ROW_H, ROW_TIP_H, CARD_HEAD = 34, 48, 40
local LEDGER_HEAD, INDENT, LEDGER_ROW = 54, 54, 38      -- a ledger card's head; where its name and settings start; a setting's row
-- Cards side by side (a QoL or Interface page): CARD_GAP between the two columns, STACK_H a row whose name doesn't fit
-- beside its control (the name above it, the control under it at the right).
local CARD_GAP, STACK_H = 12, 54
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
    ["Restore chat after reload"] = "chatRestore",
}
local CARD_OTHER = {
    ["Flight timer"] = "flightTimer", ["Instance tracker"] = "instanceTrack", ["Restock"] = "restock",
    ["XP bar"] = "xpbar", ["Trinket buttons"] = "trinketBar", ["Swing timer"] = "swing", ["Glimmer"] = "glimmer",
}

local function RowPage(page, controls, bottom, fold, side)
    local area = S.ScrollArea(page, CW - 24, CH - (bottom or 64))
    area:SetPoint("TOPLEFT", 16, -4)
    local c = area.content
    c:SetWidth(CW - 40)
    local L = { c = c, colW = CW - 40, y = -6, col = 0, rowIndex = 0, area = area, lift = 0 }
    -- (the settings pages: a ledger, one card under another; Character setup's (side): cards side by side, each half
    -- the page wide - see Lay, below)
    L.masonry = fold ~= nil or side == true
    L.ledger = fold ~= nil
    local HEAD = L.ledger and LEDGER_HEAD or CARD_HEAD
    L.half = math.floor((L.colW - CARD_GAP) / 2)
    local card       -- the card rows go into now: { frame, top, rows }
    local Lay        -- (a card's rows put in place as it ends: below)

    L.cards = {}        -- every card of the page, in the order it was built: { frame, top, span, items, entries, live }
    local function EndCard()
        L.col = 0                       -- the next card starts a row of its own
        if not card then return end
        if card.flow then L.y = Lay(card) end       -- (cards side by side: its rows go in now its width is known)
        card.height = card.top - L.y + (L.ledger and 0 or 6)
        card.frame:SetHeight(card.height)
        L.y = L.y - 6 - 14
        card.span = card.top - L.y      -- the room it takes, the gap under it included
        L.endY = L.y                    -- where the cards end, as built
        card = nil
    end

    --- On a ledger a feature's settings open and shut with a click on its row, and stay as you left them
    --- (YippRouteDB.cardsOpen["page:Card"] = true while open; shut to begin with, the page a list of features).
    local function IsOpen(cd)
        local kept = YippRouteDB.cardsOpen
        return type(kept) == "table" and kept[fold .. ":" .. cd.title] == true
    end
    function L.SetOpen(cd, open)
        local kept = type(YippRouteDB.cardsOpen) == "table" and YippRouteDB.cardsOpen or {}
        YippRouteDB.cardsOpen = kept
        kept[fold .. ":" .. cd.title] = open and true or nil
        L.Reflow()
    end
    --- Whether a card is its head alone: on a ledger, one whose settings are shut (or that has none).
    local function Shut(cd)
        return L.ledger and (not cd.options or not IsOpen(cd)) or false
    end
    --- How long the page is with every card open: Reflow takes off what the shut ones save.
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
    --- On a page whose cards stand side by side, each card goes where the two columns end higher (the left one
    --- when they end level); a card the page's width goes under both.
    function L.Reflow()
        local list = L.cards
        if L.ledger then
            -- one card under the other in one rounded panel, a line between them, a shadow under it
            local first = list[1] and list[1].top or L.y
            local top = first
            for i, cd in ipairs(list) do
                local shut = Shut(cd)
                local shift = top - cd.top
                if cd.divider then cd.divider:SetShown(i > 1) end
                if cd.arrow then
                    S.ArtTexture(cd.arrow, shut and "down" or "up")
                end
                if shift ~= (cd.shift or 0) or shut ~= (cd.shut or false) then
                    cd.shift, cd.shut, cd.x = shift, shut, 0
                    cd.frame:ClearAllPoints()
                    cd.frame:SetPoint("TOPLEFT", 0, cd.top + shift)
                    cd.frame:SetHeight(shut and HEAD or cd.height)
                    for _, it in ipairs(cd.items) do
                        it[1]:SetShown(not shut)
                        it[1]:ClearAllPoints()
                        it[1]:SetPoint("TOPLEFT", it[2], it[3] + shift)
                    end
                    for _, e in ipairs(cd.entries) do e.y = (shut and cd.top or e.y0) + shift end
                end
                top = top - (shut and HEAD or cd.height)
            end
            if #list > 0 then
                if not L.box then
                    L.box = CreateFrame("Frame", nil, c)
                    L.box:SetFrameLevel(c:GetFrameLevel() + 1)          -- (under the cards: Section)
                    S.Rounded(L.box, "BACKGROUND", "round"):SetVertexColor(unpack(S.C.card))
                    S.Rounded(L.box, "BORDER", "roundline"):SetVertexColor(unpack(S.C.line))
                    S.Shadow(L.box, 14, 3, 0.5)
                end
                L.box:ClearAllPoints()
                L.box:SetPoint("TOPLEFT", 0, first)
                L.box:SetSize(L.colW, first - top + 8)         -- (8 under the last: its band clear of the round corners)
                top = top - 8
            end
            L.bottom = top - 14
            local lift = L.endY and (L.bottom - L.endY) or 0
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
            return
        end
        if #list < 2 then
            -- one card alone on its page: the page's width (half of it, with nothing beside it, was a hole)
            local cd = list[1]
            if cd and cd.flow and not cd.full then
                cd.wide = true
                local bottom = Lay(cd)
                cd.height = cd.top - bottom + 6
                cd.frame:SetHeight(cd.height)
            end
            L.bottom = cd and (cd.top - cd.height - 14) or L.y
            return
        end
        local order, off = {}, {}
        for _, cd in ipairs(list) do
            if cd.isTop or not cd.live or cd.live() then order[#order + 1] = cd else off[#off + 1] = cd end
        end
        for _, cd in ipairs(off) do order[#order + 1] = cd end
        local ends = { list[1].top, list[1].top }       -- where each column ends (both, without cards side by side)
        for _, cd in ipairs(order) do
            local shut = Shut(cd)
            local span = shut and (HEAD + 14) or (cd.span or 0)
            local x, top
            if L.masonry and not cd.full then
                local k = ends[1] >= ends[2] and 1 or 2
                x, top = (k - 1) * (L.half + CARD_GAP), ends[k]
                ends[k] = top - span
            else
                x, top = 0, math.min(ends[1], ends[2])
                ends[1], ends[2] = top - span, top - span
            end
            local shift = top - cd.top
            if shift ~= (cd.shift or 0) or shut ~= (cd.shut or false) or x ~= (cd.x or 0) then
                cd.shift, cd.shut, cd.x = shift, shut, x
                cd.frame:ClearAllPoints()
                cd.frame:SetPoint("TOPLEFT", x, cd.top + shift)
                cd.frame:SetHeight(shut and HEAD or cd.height)
                for _, it in ipairs(cd.items) do
                    it[1]:SetShown(not shut)
                    it[1]:ClearAllPoints()
                    it[1]:SetPoint("TOPLEFT", x + it[2], it[3] + shift)
                end
                -- where the search and the page's links scroll to (a folded card's rows: its head)
                for _, e in ipairs(cd.entries) do e.y = (shut and cd.top or e.y0) + shift end
            end
        end
        local y = math.min(ends[1], ends[2])
        L.bottom = y                    -- (where the cards end as they stand now: a page that sets its own length)
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
    end
    function L.Break() EndCard() end

    --- Start a card. opts: icon (a texture or file ID), master = { get, set } for its one switch, find =
    --- other words the search box finds it by, free = its rows in use while the switch is off (a viewer),
    --- wide = the page's width though it is only settings.
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
        f:SetHeight(HEAD)
        f.note = note
        if L.ledger then
            -- (on the panel the list sits in, above it: a line above each but the first - Reflow)
            f:SetFrameLevel(c:GetFrameLevel() + 3)
            local line = f:CreateTexture(nil, "BORDER")
            line:SetPoint("TOPLEFT", 1, 0)
            line:SetPoint("TOPRIGHT", -1, 0)
            S.Hair(line, "h")
            S.Set(line, S.C.line)
            f.divider = line
        else
            S.Fill(f, S.C.card)
            S.Border(f, S.C.line)
        end
        if not L.ledger then
            local strip = f:CreateTexture(nil, "BACKGROUND", nil, 1)
            strip:SetPoint("TOPLEFT", 1, -1)
            strip:SetPoint("TOPRIGHT", -1, -1)
            strip:SetHeight(HEAD - 1)
            S.Set(strip, ZEBRA)
        end
        local x = 14
        if opts.icon then
            local ic = f:CreateTexture(nil, "ARTWORK")
            local size = L.ledger and 26 or 22
            ic:SetSize(size, size)
            ic:SetPoint("TOPLEFT", L.ledger and 16 or 12, L.ledger and -14 or -9)
            ic:SetTexture(opts.icon)
            ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            x = L.ledger and INDENT or 48
            f.icon = ic
            if L.ledger and f.CreateMaskTexture then
                -- (smaller, its corners rounded: a game icon at 32 read as the page zoomed in - the owner, 2026-10-21)
                local mask = f:CreateMaskTexture()
                mask:SetTexture(S.ART .. "iconmask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:SetAllPoints(ic)
                ic:AddMaskTexture(mask)
            end
        end
        local t = S.Text(f, 14)
        t:SetPoint("TOPLEFT", x, L.ledger and -11 or -12)
        t:SetText(title)
        f.name = t
        -- On a ledger, the line under the name says what the feature does (its note: the whole of it, with the
        -- details, as you rest on the head). Elsewhere only another addon doing the same is written there, after
        -- the name: that is to be seen before anything is switched on.
        if L.ledger and note then
            local n = S.Text(f, 12, other and S.C.gold or S.C.muted)
            n:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -3)
            n:SetPoint("RIGHT", f, "RIGHT", -170, 0)            -- (clear of "N settings" and the switch)
            f.noteText = n
            n:SetJustifyH("LEFT")
            n:SetWordWrap(false)
            n:SetText((note:gsub("^(%l)", string.upper)))
        elseif other then
            local n = S.Text(f, 11, S.C.muted)
            n:SetPoint("LEFT", t, "RIGHT", 10, 0)
            n:SetPoint("RIGHT", f, "TOPRIGHT", L.masonry and (opts.master and -64 or -16) or (opts.master and -170 or -124), -HEAD / 2)
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
            title = title, wide = opts.wide and true or false, free = opts.free and true or false, divider = f.divider }
        if L.masonry then card.flow = {} end         -- (its rows, sub-headings and drawings, in order: Lay puts them in place)
        if L.ledger then
            local mine = card
            card.open = function() if not IsOpen(mine) then L.SetOpen(mine, true) end end     -- (the search, to what it found)
        end
        L.cards[#L.cards + 1] = card
        if section then section.y0 = section.y section.of = card card.entries[#card.entries + 1] = section end
        if settings.index and settings.building then
            local e = settings.index[#settings.index]
            if e and e.row == f then e.y0 = e.y e.of = card card.entries[#card.entries + 1] = e end
        end
        card.head = L.HeadRow(f, title)
        if note then card.head.tip = note end
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
            block:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEAD)
            block:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT")
            block:SetFrameLevel(f:GetFrameLevel() + 40)
            block:EnableMouse(true)
            block:Hide()
            f.block = block
            local function Dim()
                local on = (opts.free or live()) and true or false      -- (free: its rows are in use either way)
                if L.ledger then
                    -- off: its icon and name quiet, and its settings (if open) quiet and asleep
                    if f.icon then f.icon:SetDesaturated(not live()) f.icon:SetAlpha(live() and 1 or 0.5) end
                    f.name:SetTextColor(unpack(live() and S.C.text or S.C.muted))
                    for _, r in ipairs(rowsHere) do r:SetAlpha(on and 1 or 0.45) end
                    block:SetShown(not on)
                    return
                end
                for _, r in ipairs(rowsHere) do r:SetAlpha(on and 1 or 0.40) end
                f:SetAlpha(on and 1 or 0.50)
                block:SetShown(not on)
            end
            if opts.master and not feats then
                local set = opts.master[2]
                local mine = card
                local sw = S.Switch(f, live, function(on)
                    set(on)
                    -- switched on: its settings open, to be seen as it starts (off leaves them as they are)
                    if on and L.ledger and mine.options and not IsOpen(mine) then L.SetOpen(mine, true) end
                    Dim()
                    YR:RefreshWindow()
                end)
                if L.ledger then sw:SetPoint("RIGHT", f, "TOPRIGHT", -16, -HEAD / 2) else sw:SetPoint("TOPRIGHT", -14, -11) end
                f.switch = sw
                controls[#controls + 1] = sw
            end
            controls[#controls + 1] = { Refresh = Dim }
        end
        L.y = L.y - HEAD
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
            if card.head then card.head.tip = (f.note and (f.note .. "\n\n") or "") .. f.about end
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
        if card and card.flow then return L.FlowRow(label, control, tip) end
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
            S.Hair(line, "h")
            S.Set(line, S.C.line)
            if left and not wide then
                local split = r:CreateTexture(nil, "BORDER")
                split:SetPoint("TOPRIGHT", 0, 0)
                split:SetPoint("BOTTOMRIGHT", 0, 0)
                S.Hair(split, "v")
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
    -- A row on a page of cards side by side: made now, put in place by Lay once its card is done and its width is
    -- known (half the page, or the whole of it). The same parts as a row above: the line over it, the split down
    -- the middle (in a card the page's width), the name, the control at the right, the details on resting.
    function L.FlowRow(label, control, tip)
        local r = CreateFrame("Frame", nil, c)
        r:SetSize(L.half, ROW_H)
        r:SetFrameLevel(card.frame:GetFrameLevel() + 2)
        r.line = r:CreateTexture(nil, "BORDER")
        S.Hair(r.line, "h")
        S.Set(r.line, S.C.line)
        r.split = r:CreateTexture(nil, "BORDER")
        S.Hair(r.split, "v")
        S.Set(r.split, S.C.lineHi)
        r.split:Hide()
        r.hl = S.Fill(r, S.C.hover, "BACKGROUND", 1)
        r.hl:Hide()
        r.flash = S.Fill(r, S.C.accentD, "BACKGROUND", 2)
        r.flash:Hide()
        r.label = S.Text(r, 13)
        r.label:SetText(label)
        r.label:SetJustifyH("LEFT")
        r.label:SetWordWrap(false)
        r.control, r.infoBtn, r.title, r.tip = control, false, label, tip
        rows[#rows + 1] = r
        Paint(r)
        control:SetParent(r)
        local cw = control.GetWidth and control:GetWidth() or 0
        r.wide = cw > WIDE
        -- every dropdown in half a row is one width
        if not r.wide and control.options and control.SetWidth then control:SetWidth(DROP_W) cw = DROP_W end
        r.cw = cw
        if control.isCheck then
            -- (its whole row ticks it, and lights its box under the mouse)
            r:EnableMouse(true)
            r:SetScript("OnMouseUp", function() if control:IsEnabled() then control:Click() end end)
            r:SetScript("OnEnter", function() control:Hover(true) end)
            r:SetScript("OnLeave", function() control:Hover(false) end)
        end
        controls[#controls + 1] = control
        card.rows[#card.rows + 1] = r
        local e
        if settings.index and settings.building then
            e = { key = settings.building, label = label, tip = tip, row = r, area = area, y = card.top, y0 = card.top, of = card }
            settings.index[#settings.index + 1] = e
            card.entries[#card.entries + 1] = e
        end
        card.flow[#card.flow + 1] = { kind = "row", r = r, e = e }
        L.rowIndex = L.rowIndex + 1
        return r
    end
    -- A row put in place: x, top and w in the card, mode "single" (alone in a card half the page wide), "left" or
    -- "right" (one of two in a card the page's width), "wide" (a control too wide for half: the whole row). Returns
    -- its height: a name that doesn't fit beside a wide control goes above it.
    local function PlaceRow(r, x, top, w, mode)
        local padL = mode == "right" and GUTTER or mode == "ledger" and INDENT - 1 or 16
        local padR = mode == "left" and GUTTER or 16
        local room = w - padL - padR - r.cw - 10
        local need = r.label.GetStringWidth and r.label:GetStringWidth()
        local stacked = (mode == "single" or mode == "ledger") and r.cw > 120 and type(need) == "number" and need > room
        local h = stacked and STACK_H or mode == "ledger" and LEDGER_ROW or ROW_H
        r:SetSize(w, h)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", x, top)
        r.line:ClearAllPoints()
        r.line:SetPoint("TOPLEFT", mode == "right" and GUTTER or 12, 0)
        r.line:SetPoint("TOPRIGHT", mode == "left" and -GUTTER or -12, 0)
        -- the two halves are two columns: a rule down the middle, also where the right half is empty
        r.split:ClearAllPoints()
        r.split:SetPoint("TOPRIGHT", 0, 0)
        r.split:SetPoint("BOTTOMRIGHT", 0, 0)
        r.split:SetShown(mode == "left")
        if mode == "ledger" then
            -- a line from the name's edge to the card's, between one setting and the next (Lay hides the first's)
            r.line:ClearAllPoints()
            r.line:SetPoint("TOPLEFT", INDENT - 1, 0)
            r.line:SetPoint("TOPRIGHT", 0, 0)
            r.label:SetTextColor(unpack(S.C.sub))
        end
        r.label:ClearAllPoints()
        r.control:ClearAllPoints()
        if stacked then
            r.label:SetPoint("TOPLEFT", padL, -9)
            r.label:SetWidth(w - padL - padR)
            r.control:SetPoint("BOTTOMRIGHT", -padR, 7)
        else
            r.label:SetPoint("LEFT", padL, 0)
            r.label:SetWidth(math.max(40, room))
            r.control:SetPoint("RIGHT", -padR, 0)
        end
        return h
    end
    -- A card's rows put in place as it ends. A card of settings alone: half the page wide, its rows one under the
    -- other. One with something drawn in it (L.Block: a preview, a tree), or asked to be (opts.wide), or alone on
    -- its page: the page's width, two settings to a row. Returns where the card's rows end.
    function Lay(cd)
        if L.ledger then
            -- The card's width. Its settings in a band under its row, a shade darker and the card's width (no box in a
            -- box), their names at the edge of the feature's name, rows of 40 with a line between, the controls
            -- under its switch; a sub-heading likewise, a drawing (a tree, a list) the band's width.
            cd.full = true
            local inner = L.colW - 2
            cd.frame:SetWidth(inner + 2)
            local top0 = cd.top - HEAD
            local y = top0
            cd.items = {}
            local rows, firstRow = 0, true
            for _, it in ipairs(cd.flow) do
                local r, x, top = it.r, 1, y
                if it.kind == "row" then
                    y = y - PlaceRow(r, x, top, inner, "ledger")
                    r.line:SetShown(not firstRow)
                    firstRow = false
                    rows = rows + 1
                else
                    if it.kind == "sub" then x = INDENT - 17 end
                    r:SetSize(inner - x + 1, it.h)
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", x, top)
                    if it.kind == "sub" and r.line then r.line:Hide() end
                    y = y - it.h
                    firstRow = true
                end
                cd.items[#cd.items + 1] = { r, x, top }
                if it.e then it.e.y, it.e.y0 = top, top end
            end
            cd.options = #cd.flow > 0
            if cd.options then
                y = y - 4
                if not cd.band then
                    cd.band = CreateFrame("Frame", nil, c)
                    cd.band:SetFrameLevel(cd.frame:GetFrameLevel() + 1)
                    S.Fill(cd.band, S.C.well)
                    local line = cd.band:CreateTexture(nil, "BORDER")
                    line:SetPoint("TOPLEFT") line:SetPoint("TOPRIGHT") S.Hair(line, "h")
                    S.Set(line, S.C.line)
                end
                cd.band:SetSize(inner, top0 - y)
                cd.band:ClearAllPoints()
                cd.band:SetPoint("TOPLEFT", 1, top0)            -- (where it is as built: Reflow moves it with the card)
                table.insert(cd.items, 1, { cd.band, 1, top0 })
                -- "N settings" and its arrow, before the switch: a click on the row opens or shuts them
                local f = cd.frame
                if not cd.more then
                    cd.more = S.Text(f, 12, S.C.muted)
                    cd.arrow = f:CreateTexture(nil, "ARTWORK")
                    cd.arrow:SetSize(10, 10)
                    cd.arrow:SetVertexColor(unpack(S.C.muted))
                    cd.arrow:SetPoint("RIGHT", f, "TOPRIGHT", f.switch and -68 or -16, -HEAD / 2)
                    cd.more:SetPoint("RIGHT", cd.arrow, "LEFT", -6, 0)
                    local head, mine = cd.head, cd
                    head:SetFrameLevel(f:GetFrameLevel())      -- (under its switch, which keeps its own clicks)
                    head:EnableMouse(true)
                    head:SetScript("OnMouseUp", function() L.SetOpen(mine, not IsOpen(mine)) end)
                end
                local n = rows > 0 and rows or 1
                cd.more:SetText(n == 1 and "1 setting" or (n .. " settings"))
            end
            return y
        end
        local full = cd.wide
        for _, it in ipairs(cd.flow) do if it.kind == "block" then full = true end end
        cd.full = full and true or false
        local inner = (full and L.colW or L.half) - 2
        cd.frame:SetWidth(inner + 2)
        local half = math.floor(inner / 2)
        local y, col, rowTop = cd.top - HEAD, 0, nil
        cd.items = {}
        for _, it in ipairs(cd.flow) do
            local r, x, top = it.r, 1, nil
            if it.kind == "row" and full and not r.wide and col == 1 then
                x, top = 1 + half, rowTop
                PlaceRow(r, x, top, inner - half, "right")
                col = 0
            elseif it.kind == "row" then
                top = y
                local h = PlaceRow(r, x, top, (not full or r.wide) and inner or half,
                    not full and "single" or r.wide and "wide" or "left")
                rowTop, y = top, y - h
                col = (full and not r.wide) and 1 or 0
            else
                -- a sub-heading or a drawing: the card's whole width
                top, col = y, 0
                r:SetSize(inner, it.h)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", x, top)
                y = y - it.h
            end
            cd.items[#cd.items + 1] = { r, x, top }
            if it.e then it.e.y, it.e.y0 = top, top end
        end
        return y
    end
    -- Something of its own in a card, the card's whole width and as tall as it needs: a preview.
    -- Refreshed with the page's controls when it has a Refresh.
    function L.Block(frame, h)
        if card and card.flow then
            frame:SetParent(c)
            frame:SetSize(L.colW - 2, h)
            frame:SetFrameLevel(card.frame:GetFrameLevel() + 2)
            card.flow[#card.flow + 1] = { kind = "block", r = frame, h = h }
            if frame.Refresh then controls[#controls + 1] = frame end
            return frame
        end
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
        if card and card.flow then
            r:SetFrameLevel(card.frame:GetFrameLevel() + 2)
            card.rows[#card.rows + 1] = r
            card.flow[#card.flow + 1] = { kind = "sub", r = r, h = h }
        else
            r:SetPoint("TOPLEFT", card and 1 or 0, L.y)
        end
        if card and not card.flow then
            r:SetFrameLevel(card.frame:GetFrameLevel() + 2)
            card.rows[#card.rows + 1] = r
            card.items[#card.items + 1] = { r, 1, L.y }
        end
        local line = r:CreateTexture(nil, "BORDER")
        line:SetPoint("TOPLEFT", 12, 0)
        line:SetPoint("TOPRIGHT", -12, 0)
        S.Hair(line, "h")
        S.Set(line, S.C.line)
        r.line = line
        local t = S.Text(r, 10, L.ledger and S.C.muted or S.C.accent)
        t:SetPoint("BOTTOMLEFT", 16, 5)
        t:SetText((text or ""):upper())
        if not (card and card.flow) then L.y = L.y - h end
        return r
    end
    -- a card's own details: shown when you rest on its head (the rows under it have theirs)
    function L.HeadRow(f, title)
        local hit = CreateFrame("Frame", nil, c)
        hit:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        hit:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)          -- (it takes no clicks: the link and the switch still do)
        hit:SetHeight(HEAD - 2)
        hit.hl = S.Fill(hit, S.C.hover, "BACKGROUND", 1)
        hit.hl:Hide()
        hit.title = title
        rows[#rows + 1] = hit
        return hit
    end
    return L
end

local function BuildRouteSettings(page)
    -- (one list in a rounded panel, as the QoL pages since 2026-10-21; it was two columns of cards. The minimap button
    -- is General's, on the QoL tab; where the level splits stand is Arrange on screen's, and their background and
    -- clock are what they always were: STYLE_SETTLED, Splits.lua.)
    local L = RowPage(page, settings.controls, 16, "route")
    settings.routeL = L
    local c = L.c
    local Section, Row = L.Section, L.Row
    local function Opt(key) return function() return YR.Option(key) end end
    local function SetOpt(key, after) return function(on) YippRouteDB[key] = on if after then after(on) end end end
    local st = function() return YR:SplitsStyle() end
    local function Style(field) return function(v) st()[field] = v YR:ApplySplitsStyle() end end

    Section("Routes", "Headstart's routes in RestedXP, and the items they need kept and bought. Takes a /reload.",
        { icon = 134269, find = "routes restedxp guide reload", master = { function() return YR.RoutesOn() end,
            function(on) YR.SetRoutesOn(on) YR:RefreshWindow() end } })
    Row("Keep the items a route needs", S.Check(c, Opt("sellGuard"), SetOpt("sellGuard")),
        "Marks items a route quest still needs on their tooltip, and warns you when you sell one so you"
        .. " can buy it back.")
    Row("Buy skipped items later", S.Check(c, Opt("buyLater"), SetOpt("buyLater")),
        "Reminds you of a purchase the route skipped because you were short on money. Once you can afford"
        .. " it and it is still an upgrade, chat tells you where, and a vendor who sells it asks whether to"
        .. " buy. Hold Shift as you open the vendor to skip.")
    Row("Abandon skipped quests", S.Check(c, Opt("skipQuests"), SetOpt("skipQuests")),
        "Abandons a quest the route skips when it is accepted within a second of its window opening, which is"
        .. " how another addon accepts it (a very quick click of yours looks the same). Only with a routes addon"
        .. " that lists such quests. Once a session: accept the quest again and it stays. Off until you turn it on.")
    Row("Skip quest", S.Check(c, Opt("questSkip"), SetOpt("questSkip")),
        "Adds Skip quest to the right-click menu of RestedXP's steps: every step of that quest is skipped, and"
        .. " the quest stays in your log. Right-click a skipped step to undo, or /headstart unskip. Off until you"
        .. " turn it on.")
    Row("Release at death skips", S.Check(c, Opt("deathSkipRelease"), SetOpt("deathSkipRelease")),
        "Releases your spirit at once when the current route step tells you to die and respawn, and"
        .. " accepts the Spirit Healer's resurrection without asking, at whatever that costs in the game. It goes by"
        .. " the step that is showing, so a death you didn't plan on such a step is released too. Off until you"
        .. " turn it on.")
    Row("Camping 101 reminder", S.Check(c, Opt("campReminder"), SetOpt("campReminder")),
        "Dun Morogh: tells you when your bags hold enough ore and stone to take Blacksmithing to 20 for"
        .. " Camping 101, and where to go. Repeats each time you enter Kharanos until it is done.")

    Section("Group play", "For a duo or trio on the same route: roles, and its quests shared.", { icon = 134149,
        find = "group party duo trio role" })
    local role = S.Dropdown(c, 190, YR.ROLES, function(v) YR:SetRole(v) YR:RefreshWindow() end)
    function role:Refresh()
        for _, r in ipairs(YR.ROLES) do if r[1] == YR:Role() then self:SetValue(r[2]) end end
    end
    Row("Role", role, "Routes with a group version give each role its own steps. Agree on roles with your group. Solo:"
        .. " the normal route.")
    Row("Share route quests", S.Check(c, Opt("groupShare"), SetOpt("groupShare")),
        "Shares a route quest with your party as soon as you accept it. Off until you turn it on.")
    Row("Accept shared route quests", S.Check(c, Opt("groupAccept"), SetOpt("groupAccept")),
        "Accepts quests and escorts on the route that your party shares, from anyone in the party. Other"
        .. " quests still ask. Hold Shift to decide yourself (an escort that has already started is taken"
        .. " either way). Off until you turn it on.")
    Row("Party steps", S.Check(c, Opt("groupPanel"), SetOpt("groupPanel", function() YR:RefreshParty() end)),
        "Shows a small list under the splits: each party member with Headstart, their role and their"
        .. " current step.")

    -- (the logs take room whether anything is recorded or not: their rows work with the switch off - free)
    Section("Record runs", "Every character's run kept, for This run and routes of your own.", { icon = 134328, free = true,
        find = "record runs log logs delete", master = { Opt("logging"), SetOpt("logging", function(on) YR:SetLogging(on) end) } })
    local function Ago(t)
        local d = math.floor((time() - t) / 86400)
        return d < 1 and "today" or d == 1 and "yesterday" or (d .. " days ago")
    end
    local total = CreateFrame("Frame", nil, c)
    total:SetSize(330, 24)
    total.text = S.Text(total, 13, S.C.sub)
    total.text:SetPoint("RIGHT")
    function total:Refresh()
        local n, kb = 0, 0
        for _, l in ipairs(YR.LogSummary()) do n, kb = n + 1, kb + l.kb end
        self.text:SetText(("%d character%s, about %s"):format(n, n == 1 and "" or "s",
            kb >= 1024 and ("%.1f MB"):format(kb / 1024) or (kb .. " KB")))
    end
    Row("On this account", total, "Each character's quests, levels, deaths and position samples, for This run,"
        .. " the level splits and the route analysis. All of them load on every character, so old ones are worth deleting")
    local pick = S.Dropdown(c, 240, function()
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
    Row("Delete a character's log", pick, "Asks first. This character's log starts again from now")
    Row("Delete logs not played for (days)", S.Stepper(c, YR.LogKeepDays,
        function(v) YippRouteDB.logKeepDays = math.max(0, v) end, 0, 365, 5, 110),
        "At login, the logs of characters you haven't played for this many days are deleted. Never this"
        .. " character's, a fastest run's (one the level splits compare with) or one a route of yours was"
        .. " saved from. 30 unless you set another number; 0 keeps them all")
    local scan = S.Button(c, "Delete", function()
        if YR.DeleteScan() then YR.Print("deleted the quest scan.") end
        YR:RefreshWindow()
    end, nil, 90)
    function scan:Refresh() self:SetEnabled(type(_G.HeadstartScanDB) == "table" and _G.HeadstartScanDB.scan ~= nil) end
    Row("The quest scan's results", scan, "What /headstart scan read (quest XP, objectives) for the route data."
        .. " Only needed until it's been taken out of the saved file")

    Section("Level splits", "Your time at each level, against your best run. Placed with Arrange on screen.", { icon = 236562,
        find = "splits time level best run compare", master = { Opt("showSplits"), SetOpt("showSplits", function(on) YR:ShowSplits(on) end) } })
    Row("XP per hour", S.Check(c, function() return st().rate end, Style("rate")))
    Row("Time to ding", S.Check(c, function() return st().ding end, Style("ding")))
    local COMPARE = { { "any", "Any run" }, { "class", "Same class" }, { "race", "Same class and race" },
        { "route", "Same class and start route" }, { "pin", "One run I pick" } }
    local compare
    compare = S.Dropdown(c, 190, COMPARE, function(v)
        YippRouteDB.splitsCompare = v ~= "any" and v or nil
        compare:Refresh()
        YR:ApplySplitsStyle()
    end)
    function compare:Refresh()
        for _, o in ipairs(COMPARE) do if o[1] == (YippRouteDB.splitsCompare or "any") then self:SetValue(o[2]) end end
    end
    Row("Compare with", compare, "Which of your runs the comparison columns use: any run, only your class, your class and race,"
        .. " or your class on the same start route (a Lean opener against Lean runs). Dwarf and Gnome count as one, since they share a start.")
    do      -- (a block of its own: this function is at Lua's 200-locals limit)
        local runPick = S.Dropdown(c, 240, function()
            local out = {}
            for _, r in ipairs(YR.SplitsRunList and YR.SplitsRunList() or {}) do out[#out + 1] = { r[1], r[2] } end
            if #out == 0 then out[1] = { false, "No timed runs", S.C.muted } end
            return out
        end, function(k)
            if not k then return end
            YippRouteDB.splitsPin, YippRouteDB.splitsCompare = k, "pin"
            compare:Refresh()
            YR:ApplySplitsStyle()
        end)
        function runPick:Refresh()
            local pin = YippRouteDB.splitsPin
            for _, r in ipairs(YR.SplitsRunList and YR.SplitsRunList() or {}) do
                if r[1] == pin then return self:SetValue(r[2]) end
            end
            self:SetValue("Pick a run...")
        end
        Row("The run to compare with", runPick, "For One run I pick: your splits against that run alone, say the stress"
            .. " test's run on launch day. Picking one turns it on")
    end
    Row("Level column", S.Check(c, function() return st().levelCol end, Style("levelCol")),
        "Shows how long each level took.")
    Row("Total column", S.Check(c, function() return st().totalCol end, Style("totalCol")),
        "Shows your played time from level 1 at each level.")
    Row("Vs best column", S.Check(c, function() return st().vs end, Style("vs")),
        "Shows your total against your best run at each level: ahead in green, behind in red.")
    Row("The ± level column", S.Check(c, function() return st().levelVs end, Style("levelVs")),
        "Shows what each level gained or lost against the same level of your best run: -0:40 is 40"
        .. " seconds faster.")
    Row("Text size", RowSlider(c, 10, 24, 1, function() return st().size end, Style("size")))
    Row("Levels listed", RowSlider(c, 1, 60, 1, function() return st().rows end, Style("rows")),
        "How many finished levels are listed below the current one.")

    Section("Level pace", "Under the RestedXP guide: the XP you still need, and the time to level at your pace.", { icon = 132307,
        find = "pace xp grind deaths", master = { Opt("paceWatch"), SetOpt("paceWatch") } })

    L.Break()
    L.Length(-L.y + 40)
    L.Reflow()
    settings.controls[#settings.controls + 1] = { Refresh = L.Reflow }
end

-- Quest rewards, on the QoL tab: a section of rows, the priority list, then the rewards you chose
-- by hand (as many as there are, so it goes last on its page).
local rew = {}

local function BuildRewards(L)
    local c, colW = L.c, L.colW
    local Section, Row = L.Section, L.Row
    Section("Quest rewards", "set per class", { icon = 134939, find = "pick quest rewards hand in",
        master = { function() return YR:RewardSettings(ViewClass()).on end, function(on) YR:RewardSettings(ViewClass()).on = on end } })
    Row("Class", ClassPicker(c), "The class whose reward settings you are viewing. Each class has its own.")
    Row("About quest rewards", S.Text(c, 12, S.C.muted),
        "Chooses a reward and hands the quest in when it offers a choice, up to the level below. The choice"
        .. " is final. Off until you turn it on. Hold Shift when handing in to choose yourself.")
    Row("Up to level", RowSlider(c, 1, 60, 1, function() return YR:RewardSettings(ViewClass()).maxLevel end,
        function(v) YR:RewardSettings(ViewClass()).maxLevel = v end))
    Row("Reuse my earlier choice", S.Check(c, function() return YR:RewardSettings(ViewClass()).remember end,
        function(on) YR:RewardSettings(ViewClass()).remember = on end), "Takes the reward you picked by hand for the same quest before.")
    Row("Ask when a green is offered", S.Check(c, function() return YR:RewardSettings(ViewClass()).greenStop end,
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
        r.switch = S.Check(r, function() local db = YR:RewardSettings(ViewClass()) return not db.off[db.order[i]] end,
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
end
function YR.RouteSettingsLayout() return settings.routeL end      -- (for the tests)

-- ---------------------------------------------------------------------------
-- Character setup: what a new character gets from your main, part by part
-- ---------------------------------------------------------------------------
local setup = { controls = {} }

-- A row in a menu down the left, as Quality of life's menu has them: its icon, its name, the one picked lit
-- in the accent with a bar at its edge.
local function SideItem(parent, icon, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(NAV_W - 16, 21)
    b.bg = S.Fill(b, { 0, 0, 0, 0 })
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("TOPLEFT") b.bar:SetPoint("BOTTOMLEFT") b.bar:SetWidth(2)
    S.Set(b.bar, S.C.accent)
    b.bar:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(20, 20)
    b.icon:SetPoint("LEFT", 10, 0)
    b.icon:SetTexture(icon)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.text = S.Text(b, 13, S.C.sub)
    b.text:SetPoint("LEFT", 38, 0)
    b.text:SetText(label)
    function b:Select(on)
        self.selected = on
        self.bg:SetColorTexture(unpack(on and S.C.accentD or { 0, 0, 0, 0 }))
        self.bar:SetShown(on)
        self.text:SetTextColor(unpack(on and S.C.text or S.C.sub))
        self.icon:SetDesaturated(not on)
        self.icon:SetAlpha(on and 1 or 0.8)
    end
    b:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(unpack(S.C.hover)) end end)
    b:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end end)
    b:SetScript("OnClick", onClick)
    b:Select(false)
    return b
end

local function BuildSetup(page)
    local YS = YR.Setup
    local o = function() return YS:Options(ViewClass()) end
    local function Mine() return ViewClass() == select(2, UnitClass("player")) end
    local function Said(ok, why) if not ok and why then YR.Print(why) end YR:RefreshWindow() end

    -- The top: what this character's bars and its interface are on, and what people come here to do -
    -- save them on the character they play, put them on a new one. One row for each. (Save interface
    -- was the third row of the Interface tab, and Save bars a row called "Copy" on the Profiles tab.)
    local card = CreateFrame("Frame", nil, page)
    card:SetPoint("TOPLEFT", 16, -14)
    card:SetPoint("TOPRIGHT", -16, -14)
    card:SetHeight(128)
    S.Fill(card, S.C.card)
    S.Border(card)
    setup.saved = S.Text(card, 14)
    setup.saved:SetPoint("TOPLEFT", 14, -12)
    setup.note = S.Text(card, 12, S.C.muted)
    setup.note:SetPoint("TOPLEFT", 14, -33)
    local rule = card:CreateTexture(nil, "BORDER")
    rule:SetPoint("TOPLEFT", 1, -64)
    rule:SetPoint("TOPRIGHT", -1, -64)
    S.Hair(rule, "h")
    rule:SetColorTexture(unpack(S.C.line))
    setup.ui = S.Text(card, 14)
    setup.ui:SetPoint("TOPLEFT", 14, -76)
    setup.uiNote = S.Text(card, 12, S.C.muted)
    setup.uiNote:SetPoint("TOPLEFT", 14, -97)
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
            text, gold = "Not on this character yet. Its own bars and macros are kept: Put back, Bars tab.", true
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
    -- The interface's line: which one, and whether it is on this character.
    function setup.UIPending()
        local text, gold
        if not YS:SharedUI() then
            text = "Nothing saved yet. Save interface on the character whose screen you want on the others."
        elseif YS.UISource() == YS.PlayerKey() then
            text = YS.UIFollows() and "Saved from this character, and kept up to date as you change it."
                or "Saved from this character. Save it again after a change."
        elseif YS.UIOn() and YS.UIBehind() then
            text, gold = "Saved again on another character since it was put on here. Apply to take the change.", true
        elseif YS.UIOn() then
            text = YS.UIFollows() and ("On this character. Changes saved on %s are put on here when you log in."):format(
                tostring(YS.UISource() or "the character it was saved on")) or "On this character."
        else
            text, gold = "Not on this character yet. Apply asks first; game settings and keys can be undone.", true
        end
        setup.uiNote:SetText(text)
        setup.uiNote:SetTextColor(unpack(gold and S.C.gold or S.C.muted))
    end
    -- (bars only, as it says: plain Apply put the interface on too - chat, Edit Mode, keys, game settings -
    -- and asked nothing on a new character; found 2026-10-14 going over what Headstart can change)
    local apply = S.Button(card, "Apply bars", function() YS:Apply(nil, nil, { barsOnly = true }) YR:RefreshWindow() end, "primary", 130)
    apply:SetPoint("TOPRIGHT", -12, -19)
    local save = S.Button(card, "Save bars", function() YS:Copy() YR:RefreshWindow() end, nil, 130)
    save:SetPoint("RIGHT", apply, "LEFT", -8, 0)
    save.tip = "Saves this character's bars, macros and items into the active profile. Asks before replacing one. With bar"
        .. " changes saved automatically (Profiles tab), rarely needed"
    local plan = S.Button(card, "Plan bars...", function() YR.OpenPlanner() end, nil, 120)
    plan:SetPoint("RIGHT", save, "LEFT", -8, 0)
    plan.tip = "Opens the bar planner: drag any spell your class can learn onto a button, also ones you don't know yet"
    local applyUI = S.Button(card, "Apply interface", function() YS:AskInterface() end, "primary", 130)
    applyUI:SetPoint("TOPRIGHT", -12, -83)
    applyUI.tip = "Puts the saved interface on this character, after asking. What it brings is chosen on the Interface tab."
        .. " Bars and macros are not touched. Game settings and keys can be undone; chat windows and the Edit Mode layout can't"
    local saveUI = S.Button(card, "Save interface", function() YS:SaveInterface() YR:RefreshWindow() end, nil, 130)
    saveUI:SetPoint("RIGHT", applyUI, "LEFT", -8, 0)
    saveUI.tip = "Saves this character's chat windows, Edit Mode layout, game settings, key bindings, graphics and sound, camera"
        .. " and RestedXP look as the interface it uses. Asks first when it was last saved on another character. Bars are not changed"
    setup.apply, setup.save, setup.plan, setup.applyUI, setup.saveUI = apply, save, plan, applyUI, saveUI
    for _, t in ipairs({ setup.saved, setup.note }) do
        t:SetPoint("RIGHT", plan, "LEFT", -16, 0)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(false)
    end
    for _, t in ipairs({ setup.ui, setup.uiNote }) do
        t:SetPoint("RIGHT", saveUI, "LEFT", -16, 0)
        t:SetJustifyH("LEFT")
        t:SetWordWrap(false)
    end

    -- Four short pages instead of one long one, picked in the menu on the left as Quality of life's pages are
    -- (they were chips above the page, and the menu side held a paragraph of text).
    local TABS = { { "profiles", "Profiles", 134166 }, { "bars", "Bars", 133742 }, { "interface", "Interface", 134063 },
        { "new", "New characters", 135955 } }
    local tabs, rows = {}, {}
    local function ShowTab(key)
        setup.tab = key
        for k, f in pairs(tabs) do f:SetShown(k == key) end
        for k, r in pairs(rows) do r:Select(k == key) end
    end
    setup.nav = CreateFrame("Frame", nil, ui.sideS)
    setup.nav:SetPoint("TOPLEFT", 0, -56)
    setup.nav:SetSize(NAV_W, #TABS * 23)
    for i, t in ipairs(TABS) do
        local key = t[1]
        rows[key] = SideItem(setup.nav, t[3], t[2], function() ShowTab(key) end)
        rows[key]:SetPoint("TOPLEFT", 8, -(i - 1) * 23)
        local f = CreateFrame("Frame", nil, page)
        f:SetPoint("TOPLEFT", 0, -152)
        f:SetPoint("BOTTOMRIGHT")
        tabs[key] = f
    end
    local L, Section, Row
    local need      -- the macro count further down: every choice it depends on asks it to count again
    local function Recount() if need then need:Refresh() end setup.Pending() end
    local function Sw(key) local b = S.Check(L.c, function() return o()[key] end, function(on) o()[key] = on Recount() end) return b end
    -- the rows that follow go on this tab
    local function Page(key)
        if L then
            L.Break()
            L.Reflow()
            L.c:SetHeight(-(L.bottom or L.y) + 20)
        end
        L = RowPage(tabs[key], setup.controls, 186, nil, true)
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
    local ownUI = S.Check(L.c, function() return Mine() and YS.ProfileOwnUI() end, function(on)
        if Mine() then YS.SetProfileOwnUI(on) end
        YR:RefreshWindow()
    end)
    Row("Include interface", ownUI, "Remembers which Edit Mode layout is on, which extra bars show and where RestedXP's windows"
        .. " are, and puts them back when you switch to this profile. It remembers which layout, not what is in it: give each"
        .. " profile its own layout in Edit Mode first. Off: switching profile only changes your bars.")
    Row("Save bar changes automatically", S.Check(L.c, function() return YS.Remembers() end, function(on)
        if on then YippSetupDB.remember = nil else YippSetupDB.remember = false end
        YR:RefreshWindow()
    end), "Saves a change to your bars into the active profile a few seconds after you make it. Buttons"
        .. " planned for later levels keep their place. Off: the profile only changes when you plan it or"
        .. " save into it (Save bars, at the top).")
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
    Row("Stop automatic spell placement", Sw("noAutoPush"), "Stops Blizzard from putting new spells on the first empty button, which creates duplicates on"
        .. " planned bars.")

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

    -- (the three ways back sat at the end of "Before applying", where nobody looked for them)
    Section("Put back", "undo what Headstart changed here", { find = "undo revert reset restore remove before headstart", icon = 134376 })
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
    Row("Bars before Headstart", before, "Puts this character's bars and macros back as they were the first time you opened"
        .. " Character setup on it, whatever was applied since. That copy is kept for good. Also /ysetup undo first")
    Row("Everything before Headstart", S.Button(L.c, "Put back...", function() YR.AskPutBack() end, nil, 110),
        "Puts back everything Headstart changed: this character's bars, macros, key bindings, game settings, Edit Mode layout"
        .. " and chat windows as they were before its first change, and turns quality of life and Character setup off. Asks"
        .. " first. Also on the General page, and /headstart putback")

    -- ------------------------------------------------------------------ Interface
    Page("interface")
    Section("Interface", "chat, Edit Mode and game settings, shared by every class", { icon = 134063 })
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
        .. " (at the top) puts it on.")
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
    Row("Keep it up to date", S.Check(L.c, function() return YS.UIFollows() end, function(on)
        if on then _G.YippSetupDB.uiFollow = nil else _G.YippSetupDB.uiFollow = false end
    end), "Saves the interface again when you change something on the character it was saved on: when you leave Edit"
        .. " Mode and when you log out. The other characters on it take the change at their next login and say so in chat."
        .. " To make another character's screen the saved one, use Save interface there. Off: each keeps what it has until"
        .. " you Apply interface there.")

    Section("What Apply interface brings", "for every character", { icon = 134063 })
    Row("Game settings", Sw("settings"), "What the Options window's own pages set: controls, mouse and camera, combat, names and nameplates,"
        .. " raid frames, social, map coordinates, accessibility. Not the language, the network or which help tips you have seen."
        .. " The resource display and the swing timer go on the first time only: after that they are the character's own.")
    Row("Key bindings", Sw("keys"), "Your keys as they were where the interface was saved, action by action - a default you took off"
        .. " stays off. Saved as the game saves them (the account's, unless you use character-specific bindings). /ysetup undo"
        .. " puts back the keys you had. An interface saved before this was added has none: press Save interface once.")
    Row("Graphics and sound", Sw("graphics"), "The Options window's Graphics and Audio settings: quality, effects, frame rate limits, volumes and"
        .. " which sounds play. The game keeps these per install, so this matters on another one - the live game after the beta."
        .. " Not the monitor, window, resolution or sound device. /ysetup undo puts back what you had. An interface saved before"
        .. " this was added has none: press Save interface once.")
    Row("Edit Mode layout", Sw("editMode"), "Skipped when a UI suite like ElvUI or EllesmereUI is loaded.")
    Row("Visible action bars", Sw("barVisibility"), "Skipped when a bar addon like Bartender or Dominos is loaded.")
    Row("Chat windows", Sw("chat"), "Chat tabs with their names, channels, font size, colours, and docked or floating position."
        .. " A chat tab the saved interface doesn't have is closed, and chat windows can't be put back by undo.")
    Row("Camera distance", Sw("camera"), "Zooms out as far as on the character you copied from. Also applied once to a new character after"
        .. " the intro.")
    Row("RestedXP guide for a new character", Sw("guide"), "A new character (level 5 or below) starts on the RestedXP guide set for"
        .. " its race below. Not set: Headstart's opener for the race where the routes are installed, or else RestedXP's"
        .. " own starter for the race.")
    -- which guide, race by race, for the account (the race shown first is this character's)
    local guideRace = select(2, UnitRace("player")) or "Human"
    local guidePick
    local racePick = S.Dropdown(L.c, 160, YS.GUIDE_RACES, function(r) guideRace = r if guidePick then guidePick:Refresh() end end)
    function racePick:Refresh() for _, x in ipairs(YS.GUIDE_RACES) do if x[1] == guideRace then self:SetValue(x[2]) end end end
    Row("Race", racePick, "The race whose starting guide is shown and set below. Each race has its own, for every character on the"
        .. " account.")
    guidePick = S.Dropdown(L.c, 300, function() return YS.StartGuideChoices(guideRace) end, function(v)
        YS.PickStartGuide(guideRace, v)
        guidePick:Refresh()
    end)
    function guidePick:Refresh() self:SetValue(YS.StartGuideLabel(guideRace)) end
    Row("New characters of that race start on", guidePick, "For every new character of the race above. Every guide RestedXP has"
        .. " loaded that begins at level 1; one for some classes only says so, and a character it isn't for starts on the"
        .. " default instead. Default: Headstart's opener for the race where the routes are installed (the first one that"
        .. " is for the character - the default shown is the one this character would get), or else RestedXP's own starter.")
    Row("RestedXP window positions", S.Check(L.c, function() return o().rxpFrames ~= false end,
        function(on) o().rxpFrames = on Recount() end),
        "Places RestedXP's guide window, arrow, and item and target buttons where they were on the"
        .. " character the interface was saved on.")

    -- ------------------------------------------------------------------ New characters
    Page("new")
    Section("New characters and levelling", nil, { icon = 132307 })
    Row("Setup window on new characters", Sw("popup"), "A new character's first login offers Apply both: your bars and your interface.")
    Row("Set up new characters by themselves", S.Check(L.c, function() return _G.YippSetupDB and _G.YippSetupDB.autoSetup == true end,
        function(on) _G.YippSetupDB.autoSetup = on or nil end),
        "A new character's first login puts your saved bars and interface on at once - Apply both, without the window. With no"
        .. " bars saved for its class the window opens instead; with no interface saved, the bars alone. It asks first where it"
        .. " would take something off, and the reload at the end is still asked. Every class, every character on this account.")
    local uiFirst = S.Dropdown(L.c, 200, UINames, function(name) Said(YS.UISetDefault(name)) end)
    function uiFirst:Refresh()
        self:SetValue(YS.UIRecord() and YS.UIDefault() or "none saved yet")
        self:SetEnabled(#YS.UINames() > 1)
    end
    Row("New characters get", uiFirst, "The interface offered on a new character's first login, when you have saved more than one.")
    Row("Place spells as I learn them", Sw("swap"), "Replaces a placeholder with the real spell, or fills the spell's planned button.")
    -- (The intro cinematic had a switch of its own here, beside Quality of life's Skip cinematics: two
    -- switches for one thing, and turning that one off did not stop this. It follows that one now.)
    L.Break()
    L.Reflow()
    L.c:SetHeight(-(L.bottom or L.y) + 20)
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
    setup.save:SetEnabled(view == class)
    setup.plan:SetEnabled(view == class)
    -- the interface is the account's: its row is the same whichever class is shown
    local from, at = YS.UISource(), YS.UIScanned()
    setup.ui:SetText(("Interface |cffffffff%s|r  |cff8a827a%s|r"):format(YS.UIName(),
        from and ("saved from " .. from .. (at and (", " .. date("%d %b %H:%M", at)) or "")) or "nothing saved"))
    setup.UIPending()
    setup.applyUI:SetEnabled(YS:SharedUI() ~= nil)
    setup.apply.tip = view ~= class and ("This character is not a " .. name .. ". Pick its class on the Profiles tab")
        or "Puts the profile's bars on this character, using the settings on the Bars tab. Asks first if the character was set up before"

    for _, ctl in ipairs(setup.controls) do if ctl.Refresh then ctl:Refresh() end end
end

-- ---------------------------------------------------------------------------
-- Settings, Trainer: the auto trainer (Trainer.lua) and, for this character's class, what it learns
-- ---------------------------------------------------------------------------
local trainer = { controls = {} }
-- The spells listed: every level there is. (It stopped at 30, the beta's cap: a spell first trained
-- later had no row, so it could not be set - and "All spells: Never" did not reach it, so it was bought.)
local TRAIN_TO = 60

local function ChoiceLabel(v)
    for _, c in ipairs(YR.TRAINER_CHOICES) do if c[1] == v then return c[2] end end
end

local function BuildTrainer(page)
    local L = RowPage(page, trainer.controls, 64)
    local c = L.c
    local Section, Row = L.Section, L.Row
    -- (its switch as it is set, not as it runs: with all of quality of life off this read "off" whatever it was, and
    -- a click then wrote "on")
    Section("Class trainer", "spells learned as the trainer opens", { icon = 133741, find = "auto-train auto train",
        master = { function() return YR.OptionSet("autoTrain") end, function(on) YippRouteDB.autoTrain = on YR:SyncRxpTrainer() end } })
    Row("About auto-train", S.Text(c, 12, S.C.muted),
        "Buys your class's spells the moment you open your class trainer: every spell below that isn't set to"
        .. " Never, up to the level you set, as far as your gold goes above what you keep. It is on for every character"
        .. " of the account, while the rest of this page is each class's. It doesn't ask: chat says what it learned"
        .. " and for how much. Weapon skills, riding and professions are never bought. Hold Shift as you open the"
        .. " trainer to do it yourself. RestedXP's trainer automation is turned off while this is on.")
    -- (These replace "Silver to keep", one sum whatever your level, and "Always up to level" with its
    -- "Set to Always" button - the owner found both confusing, 2026-10-14.)
    Row("Train spells up to level", S.Stepper(c, function() return YR.TrainerUpTo() end,
        function(v) YR.TrainerData().upTo = v < TRAIN_TO and v or nil trainer.refresh() end, 1, TRAIN_TO, 1, 110),
        "Spells the trainer teaches above this level are left for you to buy (chat names them). 60: every spell.")
    -- What "If I can afford it" spells leave you (Trainer.lua, TrainerKeep): a share of the money you came
    -- with, never less than a full repair, and a sum saved for something on top. What they left is one
    -- click away under the trainer's window. (A sum per level, then a full repair alone, came before it:
    -- the owner wanted gold left for everything else, and for the mace he buys at 7, 2026-10-14.)
    Row("Money kept (percent)", RowSlider(c, 0, 100, 10, function() return YR.TrainerShare() end,
        function(v) YR.TrainerData().share = v end),
        "Spells set to \"If I can afford it\" are only learned while you leave with this share of the money you came"
        .. " with, and never less than a full repair of your gear: 50 leaves half, so there is gold left for everything"
        .. " else, and more of it as you level. What they left is listed under the trainer's window with a Learn them"
        .. " button. 0: they are learned as far as your gold goes. \"Always\" spells are learned whenever you have the gold.")
    local save
    save = S.Input(c, { width = 110, placeholder = "1g 50s", onCommit = function(t)
        local copper = YR.ParseMoney(t)
        if copper then
            YR.TrainerData().save = copper
        else
            YR.Print(("\"%s\" isn't an amount: write it as 1g 50s, 75s or 2."):format(t))
        end
        save:Refresh()
    end })
    function save:Refresh()
        if not self:HasFocus() then
            local copper = YR.TrainerSave()
            self:SetValue(copper > 0 and YR.MoneyText(copper) or "")
        end
    end
    Row("Money to save", save,
        "Kept on top of that, for something you are saving up for: the weapon you mean to buy at level 7, your mount."
        .. " Write it as 1g 50s, 75s or 2 (gold); empty it once you have bought it.")
    Row("Save for the route's next buy", S.Check(c, function() return YR.TrainerRouteBuyOn() end,
        function(on) YippRouteDB.trainerRouteBuy = (not on) and false or nil end),
        "On one of Headstart's routes: the price of the next thing the route buys - a weapon at a vendor ahead - is kept"
        .. " back too, until you have it. Only \"If I can afford it\" spells wait for it; this never buys anything.")
    local _, class = UnitClass("player")
    -- What the class trainer teaches (Data/TrainerSpells.lua: every rank, by level), one row a spell, at
    -- the level of the first rank a trainer has for it. Sinister Strike is here at 6: you start with
    -- rank 1, and rank 2 is the first one you pay for. A talent's own ranks are not a trainer's.
    local levels, ranks, ids = {}, {}, {}
    local race = YR.RaceBit and YR.RaceBit() or 0
    for _, e in ipairs((YR.TrainerSpells or {})[class] or {}) do
        local name, lvl = e[3], e[2]
        if lvl <= TRAIN_TO and not name:find("%(Passive") and not name:find("%(DND%)") and (e[5] == 0 or race == 0 or bit.band(e[5], race) ~= 0) then
            if not levels[name] or lvl < levels[name] then levels[name], ids[name] = lvl, e[1] end
            ranks[name] = (ranks[name] or 0) + 1
        end
    end
    local list, names = {}, {}
    for name, lvl in pairs(levels) do list[#list + 1] = { name, lvl } end
    table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
    for _, e in ipairs(list) do names[#names + 1] = e[1] end

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
    Row("Set every spell to", every, "Sets the whole list below at once. If I can afford it: learned while you keep the money above."
        .. " First rank only: the spell is learned, its later ranks are not. Never: nothing is learned until you change a spell.")
    Section(("Spells: %s"):format(UnitClass("player") or class), "what the trainer teaches, from the first rank you pay for",
        { icon = 133742 })
    local icons = (YR.PlannerSpells or {})[class] or {}
    for _, e in ipairs(list) do
        local name, lvl = e[1], e[2]
        -- the spell's icon from the spell data, so spells not learned yet have theirs too (by its ID where the planner's
        -- data hasn't got it - Dual Wield, Mail: the game knows a spell by its name only once you have it)
        local d = icons[name]
        local icon = d and d[2] or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ids[name]))
        local dd = S.Dropdown(c, 150, YR.TRAINER_CHOICES, function(v)
            YR.SetTrainerChoice(name, v)
            trainer.refresh()
        end)
        local row
        function dd:Refresh()
            self:SetValue(ChoiceLabel(YR.TrainerChoice(name)))
            -- above Train spells up to level: dimmed, the trainer leaves it to you
            if row and row.SetAlpha then row:SetAlpha(lvl > YR.TrainerUpTo() and 0.45 or 1) end
        end
        row = Row(("%d  %s%s%s"):format(lvl, icon and ("|T" .. icon .. ":18:18:0:0:64:64:5:59:5:59|t ") or "", name,
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
-- ---------------------------------------------------------------------------
-- Main switches for the cards whose feature is several settings - choices, sliders, more than one switch - rather
-- than one (the owner, 2026-10-20: "settings without on/off? It shouldn't be like that: everything must be able to
-- be switched on and off, each with its own main switch"). Off puts the card's settings to what they are with the
-- feature off and keeps what you had chosen (YippRouteDB.kept[name]); on puts that back - or, the first time,
-- `first`. It reads as on while any of them isn't off, or since you switched it on.
--   parts: { { read, write, off }, ... }; first: { [part] = value } (or a function giving it); after(on); can(say):
--   whether it can be on at all (another addon it works on is loaded) - it reads off where it can't, and switched on
--   then it says why and stays off (say: true when switched on).
-- Returns { get, set }, as a card's master and an All features card take it.
-- ---------------------------------------------------------------------------
local function Kept(name, parts, first, after, can)
    local function Off(p)
        local v = p[1]()
        return v == p[3] or (p[3] == false and v == nil) or (p[3] == nil and v == false)
    end
    local function IsOn()
        if can and not can() then return false end
        if type(YippRouteDB.cardOn) == "table" and YippRouteDB.cardOn[name] then return true end
        for _, p in ipairs(parts) do if not Off(p) then return true end end
        return false
    end
    local function TurnTo(on)
        YippRouteDB.kept = type(YippRouteDB.kept) == "table" and YippRouteDB.kept or {}
        YippRouteDB.cardOn = type(YippRouteDB.cardOn) == "table" and YippRouteDB.cardOn or {}
        if on and can and not can(true) then return end
        if on then
            local was = YippRouteDB.kept[name] or (type(first) == "function" and first()) or first or {}
            for i, p in ipairs(parts) do if was[i] ~= nil then p[2](was[i]) end end
            YippRouteDB.kept[name], YippRouteDB.cardOn[name] = nil, true
        else
            local was = {}
            for i, p in ipairs(parts) do if not Off(p) then was[i] = p[1]() end end
            YippRouteDB.kept[name] = next(was) and was or nil
            for _, p in ipairs(parts) do p[2](p[3]) end
            YippRouteDB.cardOn[name] = nil
        end
        if after then after(on) end
    end
    return { IsOn, TurnTo }
end
-- a part that is one of Headstart's options (YR.Option: its default counts), or a field that is on only when true
local function OptPart(k, after)
    return { function() return YR.OptionSet(k) end, function(v) YippRouteDB[k] = v and true or false if after then after() end end, false }
end
local function TruePart(k) return { function() return YippRouteDB[k] == true end, function(v) YippRouteDB[k] = v and true or nil end, false } end
local MASTER = {
    invites = Kept("invites", {
        { function() return YR.AcceptInvitesSet() end, function(v) YippRouteDB.acceptInvites = v end, "off" },
        { function() return YR.WhisperInviteSet() end, function(v) YippRouteDB.whisperInvite = v end, "off" },
    }, { "friends", "friends" }),
    questShare = Kept("questShare", {
        { function() return YippRouteDB.shareAll == true end, function(v) YippRouteDB.shareAll = v and true or false end, false },
        { function() return YR.AcceptFromSet() end, function(v) YippRouteDB.acceptFrom = v end, "off" },
    }, { [2] = "friends" }),
    reminders = Kept("reminders", { OptPart("remindTrainer"), OptPart("remindTalents", function() YR.TalentNotice() end), OptPart("durability") },
        { true, true, true }),
    mountSwim = Kept("mountSwim", { TruePart("trinketMount"), TruePart("trinketSwim") }, { true }),
    dmgSkin = Kept("dmgSkin", { { function()
        local m = YippRouteDB.dmgSkin
        return (m == "headstart" or m == "blizzard") and m or "off"
    end, function(v) YR.SetDamageSkin(v) end, "off" } }, { "headstart" }),
    -- (without RestedXP there is nothing to skin: the switch read On and did nothing - the review, 2026-10-21)
    rxpSkin = Kept("rxpSkin", { { function() return YR.RXPSkinModeSet() end, function(v) YR.SetRXPSkin(v) end, "off" } }, { "headstart" },
        nil, function(say)
            if YR.RXPSkinAvailable() then return true end
            if say then YR.Print("RestedXP isn't loaded: nothing to skin.") end
            return false
        end),
    chatButtons = Kept("chatButtons", {
        { function() return YippRouteDB.chatStrip or "show" end, function(v) YippRouteDB.chatStrip = v ~= "show" and v or nil end, "show" },
        TruePart("chatTTSHide"), TruePart("chatSocialHide"),
    }, { "slim" }, function() YR.BarHideApply() end),
    whisperSound = Kept("whisperSound", { { function() return YippRouteDB.whisperSound or "off" end,
        function(v) YippRouteDB.whisperSound = v ~= "off" and v or nil end, "off" } }, function()
        local list = YR.WhisperSounds()
        for _, o in ipairs(list) do if o[1] ~= "off" and o[1] ~= "file" then return { o[1] } end end
        return {}
    end),
    bagBars = Kept("bagBars", {
        { function() return YippRouteDB.bagBar or "show" end, function(v) YR.SetBarHide("bagBar", v) end, "show" },
        { function() return YippRouteDB.microMenu or "show" end, function(v) YR.SetBarHide("microMenu", v) end, "show" },
    }, { "hover", "hover" }),
    windowScale = Kept("windowScale", {
        { function() return YR.WindowScale("social") end, function(v) YR.SetWindowScale("social", v) end, 100 },
        { function() return YR.WindowScale("lfg") end, function(v) YR.SetWindowScale("lfg", v) end, 100 },
    }),
    bagMove = Kept("bagMove", { TruePart("moveBag"), TruePart("moveReagentBag") }, { true }, function()
        YR.MoverPlace("bag")
        YR.MoverPlace("reagentBag")
    end),
    talentWin = Kept("talentWin", {
        { function() return YR.TalentFade() end, function(v) YR.SetTalentFade(v) end, 0 },
        OptPart("talentFadeSlider", function() YR.TalentFadeApply() end),
        { function() return YR.TalentScale() end, function(v) YR.SetTalentScale(v) end, 100 },
        OptPart("talentEarly", function() YR.ApplyParts() if YR.TalentEarlyApply then YR.TalentEarlyApply() end end),
        OptPart("talentMove", function() YR.TalentPlace() end),
    }, { [2] = true, [5] = true }),
}
--- The main switches of the cards that have several settings (for the tests): { name = { get, set } }.
function YR.CardMasters() return MASTER end

local function QoLPage(key, build)   -- (TOP_CARD: the card of switches every page begins with)
    qolPages[key] = { controls = {} }
    return function(page)
        local L = RowPage(page, qolPages[key].controls, 64, key)
        qolPages[key].L = L
        local c = L.c
        local Section, Row = L.Section, L.Row
        -- what you set, also while the main switch has it all off (it comes back as you left it)
        local function Opt(k) return function() return YR.OptionSet(k) end end
        build(L, c, Section, Row, Opt)
        if key ~= "quests" and key ~= "trinkets" then   -- those two end with a list of their own
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

-- Quest item buttons (QuestItems.lua): the items a quest gave you that you use, on screen. On the Journey page
-- with the other things of the road (the menu has no room for a page more).
local function QuestItemSections(L, c, Section, Row, Opt)
        Section("Quest item buttons", "the items quests gave you, a click away", { find = "quest items use active items rewards bag",
            icon = 133631, master = { Opt("questItems"), function(on) YippRouteDB.questItems = on YR.QuestItemsApply() end } })
        Row("About quest item buttons", S.Text(c, 12, S.C.muted),
            "A button for each item in your bags that a quest gave you as its reward and that you use, like Really Sticky"
            .. " Glue or a Sprouted Frond - not food and drink, potions, bandages or recipes. A click uses it, as from your bags; its"
            .. " cooldown and how many you have show on it. Shift+right-click takes one off. The buttons change out of combat.")
        Row("Quest items too", S.Check(c, function() return YippRouteDB.questItemsQuest == true end, function(on)
            YippRouteDB.questItemsQuest = on or nil
            YR.QuestItemsApply()
        end), "Also the items the game counts as quest items, with a use: a vial to fill, a sapling to plant.")
        Row("Size", RowSlider(c, 24, 56, 2, function() return tonumber(YippRouteDB.questItemsSize) or 36 end,
            function(v) YippRouteDB.questItemsSize = v ~= 36 and v or nil YR.QuestItemsApply() end))
        local DIRS = { { "row", "In a row" }, { "column", "In a column" } }
        local dir
        dir = S.Dropdown(c, 180, DIRS, function(v)
            YippRouteDB.questItemsVertical = v == "column" or nil
            YR.QuestItemsApply()
            dir:Refresh()
        end)
        function dir:Refresh() self:SetValue(YippRouteDB.questItemsVertical == true and "In a column" or "In a row") end
        Row("Buttons", dir)
        Row("Hidden buttons", S.Button(c, "Show again", function() YR.QuestItemsShowHidden() end, nil, 110),
            "Shift+right-click a button to hide it. This brings back every button you hid on this character.")
end

-- Quests on NPC tooltips (QuestTips.lua) and quest mob markers (NpcMarkers.lua): on the Journey page.
local function QuestTipSections(L, c, Section, Row, Opt)
        Section("Quests on NPC tooltips", "what an NPC has for you", { find = "quest tooltip npc available hand in giver",
            icon = 132049, master = { Opt("questTips"), function(on) YippRouteDB.questTips = on YR.ApplyParts() end } })
        Row("About quests on tooltips", S.Text(c, 12, S.C.muted),
            "An NPC's tooltip lists the quests it has for you: ! to take, ? to hand in. From your RestedXP route (the"
            .. " steps ahead that take or hand in a quest there, marked route), and from what each NPC offered when you"
            .. " talked to it - remembered for all your characters, and listed until you have done the quest. Not in combat."
            .. " With QuestieDB installed - the Questie team's quest database, which works without Questie - every quest an"
            .. " NPC has for you is listed, talked to or not. With Questie's own quests on NPC tooltips on, Questie's are"
            .. " shown and these are left out.")
end

local function NpcMarkerSections(L, c, Section, Row, Opt)
        Section("Quest mob markers", "enemies you need for a quest, on their nameplate", { find = "npc markers nameplate quest mob objective kill loot icon sword",
            icon = 131013, master = { Opt("npcMarkers"), function(on) YippRouteDB.npcMarkers = on YR.ApplyParts() end } })
        Row("About quest mob markers", S.Text(c, 12, S.C.muted),
            "A sword on the nameplate of an enemy you still need for a quest - one to kill, or one that drops what a quest"
            .. " wants - and on the mobs your RestedXP step names. Quest givers show their own ! and ?. With Questie's"
            .. " nameplate icons on, Questie's are shown and these are left out.")
end

-- The camp icon (Camp.lua), the flight timer (Flight.lua) and the boat timer: on the Journey page, the things of
-- the road. (They had a page of their own, two small cards - merged at the owner's asking, 2026-10-14. The world
-- marker and the quest helpers stood here too, until they had a Quests page of their own: 2026-10-20.)
local function RoadSections(L, c, Section, Row, Opt)
        Section("Flight timer", "time left while you fly", { icon = 132239,
            master = { Opt("flightTimer"), function(on) YippRouteDB.flightTimer = on YR:SetFlightTimer(on) end } })
        Row("About the timer", S.Text(c, 12, S.C.muted),
            "Shows where you fly to and from, the time left and the clock time you land. Land lands you at the next"
            .. " flight point on the way, and Blizzard's own Land button is hidden while the card shows. A flight is"
            .. " timed the first time you take it; before that the card uses RestedXP's time or an estimate. Move it"
            .. " with Arrange. /headstart flight shows a sample.")

        Section("Boat timer", "when the boat at your dock leaves", { find = "boat zeppelin ship ferry dock schedule nauticus",
            icon = 134440, master = { Opt("boatTimer"), function(on) YippRouteDB.boatTimer = on YR.BoatTimerApply() end } })
        Row("About the boat timer", S.Text(c, 12, S.C.muted),
            "At a dock or a zeppelin tower: when the boat there gets in and leaves, and on board when it arrives. The"
            .. " times are Headstart's own timetable, kept right by what Headstart players see as they ride: each tells"
            .. " the others in guild and group when a boat left or got in, whether they show this timer or not."
            .. " Shift-drag the timer to move it.")
        Row("On the world map", S.Check(c, function() return YippRouteDB.boatMap ~= false end, function(on)
            YippRouteDB.boatMap = (not on) and false or nil
            YR.BoatTimerApply()
        end), "Your side's boats and zeppelins on the world map, plus the Ratchet boat, each where it is now. Point"
            .. " at one for where it is bound and when it gets in.")

        Section("Camp icon", "lit near a camp, or while its buff runs", { find = "campfire", icon = 135805, master = { Opt("camp"), YR.SetCampIcon } })
        Row("Show the camp's buffs", S.Check(c, Opt("campList"), YR.SetCampList),
            "Lists the stat the camp gives and its shorter buffs with their time left. Buffs can't be read in"
            .. " combat, so the list dims and shows what it last saw.")
        Row("Always show", S.Check(c, Opt("campAlways"), YR.SetCampAlways),
            "Keeps a grey icon on screen away from camps. Off: the icon only shows near a camp or while its"
            .. " buff runs.")
end

-- The quest helpers (the world marker, Waypoint.lua; quest item buttons; quest mob markers; quests on NPC tooltips):
-- the first cards of the Quests page.
local function QuestSections(L, c, Section, Row, Opt)
        Section("World marker", "your map pin, shown in the world", { find = "waypoint map pin marker arrow tomtom navigation poi",
            icon = 132181, master = { Opt("waypoint"), function(on) YippRouteDB.waypoint = on YR.ApplyParts() end } })
        Row("About the world marker", S.Text(c, 12, S.C.muted),
            "Shows your map pin in the world: a mark and how far it is, seen from afar, with an arrow at the"
            .. " screen's edge while it is behind you. Forever doesn't show the game's own. Put a pin with Ctrl+click"
            .. " on the world map, or /headstart way 45 62 in the zone you're in; /headstart way alone takes it away.")
        Row("Follow RestedXP's arrow", S.Check(c, Opt("waypointRXP"), function(on) YippRouteDB.waypointRXP = on YR.ApplyParts() end),
            "Puts your map pin where RestedXP's arrow points, the spot of the step you're on, so the next stop stands in"
            .. " the world. Nothing on a hearth step. A pin of your own is moved when the step changes.")

        QuestItemSections(L, c, Section, Row, Opt)
        NpcMarkerSections(L, c, Section, Row, Opt)
        QuestTipSections(L, c, Section, Row, Opt)
end

local BuildBags = QoLPage("bags", function(L, c, Section, Row, Opt)
        Section("Bank deposit", "a Deposit button on the bank window", { find = "auto bank mats deposit", icon = 133639,
            master = { Opt("bankButton"), YR.SetBankButton } })
        Row("About the Deposit button", S.Text(c, 12, S.C.muted),
            "Adds a Deposit button under the bank window. A click moves the items chosen below from your bags to"
            .. " the bank and lists them in chat. Quest items, items for quests you can still do, and AutoFeed's food"
            .. " and water always stay. Nothing goes by itself when the bank opens. Where a bag addon hides the bank"
            .. " window, the button stands at the top of the screen. Also /headstart bank.")
        local MATS = { { "mine", "Not for my professions" }, { "all", "All of them" }, { "off", "None" } }
        local mats
        mats = S.Dropdown(c, 190, MATS, function(v) YippRouteDB.bankMats = v mats:Refresh() end)
        function mats:Refresh()
            for _, o in ipairs(MATS) do if o[1] == YR.BankMats() then self:SetValue(o[2]) end end
        end
        Row("Crafting mats", mats, "Which crafting materials to deposit. \"Not for my professions\" keeps what your own professions"
            .. " use: ore for a miner, linen for a tailor. Items you use rather than craft with, like dynamite,"
            .. " always stay.")
        Row("Recipes I can't learn yet", S.Check(c, Opt("bankRecipes"), function(on) YippRouteDB.bankRecipes = on end),
            "Deposits recipes for a profession you don't have, or that need more skill. A recipe you can"
            .. " learn now stays in your bags.")

        Section("Mail to alt", "mats and recipes sent to another character", { icon = 133471, find = "mail button send alt",
            master = { Opt("mailButton"), YR.SetMailButton } })
        Row("About mail to alt", S.Text(c, 12, S.C.muted),
            "Adds a \"Send to <alt>\" button under the mail window: a click mails the items chosen below to your alt. Also"
            .. " /headstart mail. Off until you turn it on.")
        local alt = CreateFrame("Frame", nil, c)
        alt:SetSize(190, 24)
        alt.input = S.Input(alt, { width = 190, placeholder = "Name Surname", onCommit = function(t)
            local full = YR.SetMailRecipient(t)
            local bare = YR.MailRecipientMissingSurname()
            if bare then
                YR.Print(("mail on Forever needs the full name: %s's surname too, as the character shows it."):format(bare))
            end         -- (a name that is right isn't said back: the field shows it)
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
        Row("Send when the mailbox opens", S.Check(c, function() return YippRouteDB.mailAuto == true end,
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
        Row("Recipes I can't learn yet", S.Check(c, Opt("mailRecipes"), function(on) YippRouteDB.mailRecipes = on end))
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

end)

local BuildAlts = QoLPage("alts", function(L, c, Section, Row, Opt)
        Section("Characters", "bags, bank and gold of your other characters", { icon = 133785, find = "alts altoholic gold",
            master = { Opt("alts"), function(on) YippRouteDB.alts = on end } })
        Row("Characters window", S.Button(c, "Open", function() YR.AltsToggle() end, nil, 90),
            "Shows each character's level, gold and last login. Pick one to see its bags and bank, or search"
            .. " all of them for an item. Also on the bag button, a key binding, the minimap button's"
            .. " right-click menu, and /headstart alts. A character is recorded when you play it with this on,"
            .. " and its bank when you open it. Soulbound items, quest items and the hearthstone are left out.")
        Row("Bag button", S.Check(c, function() return YippRouteDB.altsBagButton ~= false end, function(on)
            YippRouteDB.altsBagButton = on
            YR.AltsBagButtons()
        end), "Adds a small round mark at the left of the money on your bag. Hover it for every character's gold, click it for"
            .. " the Characters window.")
        Row("Include food, drink and grey items", S.Check(c, function() return YippRouteDB.altsAll == true end,
            function(on) YippRouteDB.altsAll = on end), "Shows food, drink and grey items in the window and in tooltips. Off by default: they are mostly"
            .. " clutter.")
        Row("Item tooltips", S.Check(c, function() return YippRouteDB.altsTooltip ~= false end,
            function(on) YippRouteDB.altsTooltip = on end), "Adds a line to item tooltips with the other characters that have the item: \"Duplo: 4x, bank"
            .. " 12x\".")
        Row("Gold tooltip", S.Check(c, function() return YippRouteDB.altsGold ~= false end,
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
        Section("Restock", "tops your bags up to the numbers you set; hold Shift at a vendor to skip it",
            { find = "vendor buy reagents ammo", icon = 133785,
            master = { Opt("restock"), function(on) YippRouteDB.restock = on end } })
        Row("Gold to keep", S.Stepper(c, function() return YippRouteDB.restockReserve or 0 end,
            function(v) YippRouteDB.restockReserve = v end, 0, 1000, 1, 110),
            "Restock never spends below this amount. It is 0 until you set it, and counts for every character.")
        if YR.RestockShoots() then
            Row("Ammo to keep", S.Stepper(c, function() return YR.RestockAmmo() end,
                function(v) YR.SetRestockAmmo(v) end, 0, 4000, 100, 110),
                "How many to have: with 400 in your bags and 1000 set, 600 are bought. The best arrows or bullets you can use"
                .. " for your ranged weapon, or more of your throwing weapon. Each class has its own number. 0: none.")
        end
        for _, r in ipairs(YR.RestockReagents()) do
            local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(r.item)
            if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(r.item) end
            local count = S.Stepper(c, function() return YR.RestockCount(r.item, r.default) end,
                function(v) YR.SetRestockCount(r.item, v) end, 0, 200, 1, 110)
            local row = Row(name or ("Reagent for " .. r.why), count,
                ("How many to have, for %s: topped up to it while you know it%s. 0: none (a usual number: %d)."):format(r.why,
                    #r.spells > 1 and " (of several ranks, only the top one you know)" or "", r.default or 0))
            -- (the item's name, once the game has it: before, the row says what it is for)
            if not name and row and rawget(row, "label") then
                local plain = count.Refresh
                function count:Refresh()
                    plain(self)
                    local now = C_Item.GetItemNameByID and C_Item.GetItemNameByID(r.item)
                    if now then row.label:SetText(now) end
                end
            end
        end
        local custom = CreateFrame("Frame", nil, c)
        custom:SetSize(200, 24)
        local input = S.Input(custom, { width = 200, placeholder = "Shift-click an item, then a count",
            onCommit = function(t)
                local item = YR.ItemFromText(t)
                local count = tonumber((t:gsub("|H.-|h.-|h", "")):match("(%d+)%s*$"))
                -- typed, not clicked: "6265 20" is item 6265 and 20 of it (it took no typed ID at all:
                -- two numbers were no item, and one number was its own count)
                local id, n = t:match("^%s*(%d+)%s+(%d+)%s*$")
                if id then item, count = tonumber(id), tonumber(n) end
                if item and count and (id or count ~= item) then
                    YR.SetRestockCustom(item, count)
                    YR:RefreshWindow()
                end
            end })
        input:SetPoint("RIGHT")
        custom.input = input
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if input:HasFocus() and IsShiftKeyDown() and link then input:Insert(link .. " ") end
        end)
        Row("Add an item", custom, "Shift-click an item into the box (or type its ID), then a space and the number to keep, then Enter. Enter"
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

-- Group: invites accepted and sent on a whisper, the Invite and Leave buttons, and the quest group finder.
local BuildGroup = QoLPage("group", function(L, c, Section, Row, Opt)
        Section("Invites", "accepted, and sent on a whisper", { find = "auto accept invite whisper inv keyword", icon = 134149,
            master = MASTER.invites })
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

        Section("Invite and Leave buttons", "group up for a kill, and leave again", { find = "quick group invite leave", icon = 134149,
            master = { Opt("groupBar"), YR.SetGroupBar } })
        Row("About the buttons", S.Text(c, 12, S.C.muted),
            "Shows a small bar with two buttons: Invite your target, and Leave group. Both have key bindings"
            .. " (Key Bindings, AddOns, Headstart), and /headstart inv and /headstart leave. Move it with Arrange.")
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
        Row("Watch for others", S.Check(c, function() return YippRouteDB.questLFGWatch ~= false end,
            function(on) YippRouteDB.questLFGWatch = on end),
            "Lists players who name one of your quests in chat, and tells you in one chat line. Off: chat is"
            .. " only read while your own request is up.")
        Row("Reset the eye's position", S.Button(c, "Reset", function() YR.QuestLFGResetPosition() end, nil, 90),
            "Moves the eye back to the left of the quest tracker.")
end)

-- The classes whose talent builds can be looked at (the Levelling tab's Talents page).
local TALENT_CLASSES = { { 1, "Warrior" }, { 2, "Paladin" }, { 3, "Hunter" }, { 4, "Rogue" }, { 5, "Priest" },
    { 7, "Shaman" }, { 8, "Mage" }, { 9, "Warlock" }, { 11, "Druid" } }

local BuildReminders = QoLPage("reminders", function(L, c, Section, Row, Opt)
        Section("Reminders", "said when something needs doing", { find = "ding level up trainer talents repair", icon = 134376,
            master = MASTER.reminders })
        Row("New at your trainer", S.Check(c, Opt("remindTrainer"), function(on) YippRouteDB.remindTrainer = on end),
            "A small window when you level: the spells your class trainer has new for you at that level, with about what"
            .. " they cost. Point at one for the spell; trained, it goes from the window. Prices are remembered from your"
            .. " trainer visits. Placed with Arrange on screen.")
        Row("Unspent talent points", S.Check(c, Opt("remindTalents"), function(on)
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
        Row("Durability warning", S.Check(c, Opt("durability"), function(on) YippRouteDB.durability = on end),
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
        Row("  Sharpening stones and weightstones", S.Check(c, Opt("craftStones"), function(on) YippRouteDB.craftStones = on end),
            "Blacksmithing. Only the kind your weapon takes: stones for blades, weights for blunt weapons.")
        Row("  Wizard and mana oil", S.Check(c, Opt("craftOils"), function(on) YippRouteDB.craftOils = on end), "Enchanting.")
        Row("  Bandages", S.Check(c, Opt("craftBandages"), function(on) YippRouteDB.craftBandages = on end), "First Aid.")
        Row("  Remind when I have fewer than", S.Stepper(c, function() return YippRouteDB.craftBelow or 1 end,
            function(v) YippRouteDB.craftBelow = v end, 1, 100, 1, 110), "1: only when you have none.")
        Section("Level-up screenshot", "a screenshot as you level", { find = "ding screenshots", icon = 134441,
            master = { Opt("levelShot"), function(on) YippRouteDB.levelShot = on end } })
        Row("About the screenshot", S.Text(c, 12, S.C.muted),
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
        Row("Killing blow in chat", S.Check(c, function() return YippRouteDB.deathChat == true end,
            function(on) YippRouteDB.deathChat = on end), "Also prints the killing blow as one chat line. Only you see it.")
        local last = S.Button(c, "Open", function()
            if not YR.RecapShow() then YR.Print("no death recorded for this character yet.") end
        end, nil, 90)
        Row("Your last death", last, "Opens the recap of this character's last death. Also /headstart death.")
end)

local BuildLoot = QoLPage("loot", function(L, c, Section, Row, Opt)
        local function Sw(key)
            return S.Check(c, function() return YippRouteDB[key] ~= false end, function(on) YippRouteDB[key] = on end)
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
        Row("Vendor price", S.Check(c, function()
            if YippRouteDB.lootPrice == nil then return YippRouteDB.lootStyle == "cards" end
            return YippRouteDB.lootPrice == true
        end, function(on)
            YippRouteDB.lootPrice = on
            YR.LootFeedApply()
        end), "Shows what the item sells for to a vendor at the right of its line, for the whole stack.")
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
        Row("Items shown", quality, "Items below this quality are left out of the feed. They are still in the loot log.")
        Row("Looted money", Sw("lootMoney"), "Shows looted money, and your share in a group.")
        Row("Experience", Sw("lootXP"), "Shows experience gained. Kills in a row add up on one line.")
        Row("Reputation", Sw("lootRep"), "Shows reputation gained.")

        -- (the log was a card of its own, with no switch: it is recorded while the loot feed is on - the feed's card)
        L.Sub("Loot log")
        Row("Loot log", S.Button(c, "Open", function() YR.LootLogToggle() end, nil, 90),
            "Opens the log of every item and reputation gain with its time. It also shows this session's"
            .. " totals and hourly rates for money, vendor value and experience. Recorded while the loot feed is"
            .. " on. Also /headstart loot.")
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

-- Glimmer (Glimmer.lua): the preview is the same effect the world gets, in the three states an object
-- can be in, drawn as the settings are now.
local function GlimmerPreview(c)
    local f = CreateFrame("Frame", nil, c)
    f:SetClipsChildren(true)
    S.Fill(f, S.C.field)
    f.title = S.Text(f, 11, S.C.muted)
    f.title:SetPoint("TOPRIGHT", -12, -10)
    f.title:SetText("PREVIEW")
    -- The object: the game's own Silverleaf (the file the client's GameObjectDisplayInfo gives display
    -- 270), the same in all three, each turned a different way, standing still. The camera is placed by
    -- hand once the model has loaded, as Blizzard's own model frames do (MakeCurrentCameraCustom): the
    -- frame's own camera stood so close a node filled it, and standing it back or shrinking the model
    -- only moved the plant out of the bottom of the frame (seen 2026-10-14). Where no model can be
    -- shown, a flat shape of Headstart's own.
    local ART = "Interface\\AddOns\\Headstart\\art\\glimmer\\"
    local HERB = 219487
    -- the plant's middle, and where the camera looks from (yards; 7.5 back drew it a speck, 2026-10-14)
    local TARGET_Z, CAMERA = 0.4, { 2.4, 0, 1.0 }
    -- What the settings are for is the colour, so the preview is the colours you will see: your chance of
    -- a skill-up, and too low. (It was out of reach, in reach and too low - the first two differ only in
    -- how bright, which you see by walking up to a node.)
    local SAMPLES = {
        { state = "ready", label = "Skill-up every time", skill = 10, need = 1, facing = 0.4 },
        { state = "ready", label = "Most times", skill = 30, need = 1, facing = 1.6 },
        { state = "ready", label = "Now and then", skill = 60, need = 1, facing = 2.8 },
        { state = "ready", label = "No skill-up", skill = 120, need = 1, facing = 4.0 },
        { state = "locked", label = "Too low", skill = 90, need = 125, facing = 5.2 },
    }
    local function Aim(model)
        pcall(model.MakeCurrentCameraCustom, model)
        pcall(model.SetCameraTarget, model, 0, 0, TARGET_Z)
        pcall(model.SetCameraPosition, model, CAMERA[1], CAMERA[2], CAMERA[3])
    end
    f.samples = {}
    for i, sm in ipairs(SAMPLES) do
        local cell = CreateFrame("Frame", nil, f)
        cell:SetSize(130, 150)
        cell:SetPoint("TOP", f, "TOP", (i - 3) * 136, 0)
        cell.label = S.Text(cell, 12, S.C.sub)
        cell.label:SetPoint("BOTTOM", 0, 8)
        cell.label:SetText(sm.label)
        -- the plant stands on its shadow above the label; the glimmer is at its middle
        local model = CreateFrame("Model", nil, cell)
        model:SetSize(126, 116)
        model:SetPoint("BOTTOM", 0, 26)
        cell.shadow = cell:CreateTexture(nil, "BORDER")
        cell.shadow:SetSize(60, 14)
        cell.shadow:SetPoint("BOTTOM", model, "BOTTOM", 0, 14)
        cell.shadow:SetTexture(ART .. "halo")
        cell.shadow:SetVertexColor(0, 0, 0, 0.7)
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetSize(44, 44)
        cell.icon:SetPoint("BOTTOM", cell.shadow, "CENTER", 0, -4)
        cell.icon:SetTexture(ART .. "herb")
        cell.icon:SetVertexColor(0.47, 0.6, 0.41)
        model:SetScript("OnModelLoaded", Aim)
        if pcall(model.SetModel, model, HERB) then
            Aim(model)
            pcall(model.SetFacing, model, sm.facing)
            cell.icon:Hide()
        else
            model:Hide()
        end
        cell.fx = YR.GlimmerEffect(cell)
        cell.fx:SetFrameLevel(model:GetFrameLevel() + 2)
        cell.fx:SetPoint("CENTER", cell.shadow, "CENTER", 0, 0)      -- (a look is drawn from the ground up)
        cell.sm = sm
        f.samples[i] = cell
    end
    function f:Refresh()
        for _, cell in ipairs(self.samples) do
            local sm = cell.sm
            cell.fx:SetStyle(YR.GlimmerStyle())
            cell.fx:SetLook(math.max(50, math.min(200, tonumber(YippRouteDB.glimmerSize) or 100)) / 100,
                math.max(20, math.min(100, tonumber(YippRouteDB.glimmerBright) or 100)) / 100)
            local mode = YR.GlimmerColorMode()
            local C = YR.GLIMMER_COLORS
            local col
            if mode == "white" then col = C.white
            elseif mode == "accent" then col = sm.state == "locked" and C.grey or C.accent
            elseif sm.state == "locked" then col = C.red
            else col = C[YR.GlimmerSkillColor(sm.skill, sm.need) or "orange"] end
            cell.fx:SetColor(col[1], col[2], col[3])
            cell.fx:SetState(sm.state)
            cell.fx:Show()
        end
    end
    return f
end

local BuildGlimmer = QoLPage("glimmer", function(L, c, Section, Row, Opt)
        local function Sub(key)
            return S.Check(c, function() return YippRouteDB[key] ~= false end, function(on) YippRouteDB[key] = on YR.SettingChanged() end)
        end
        Section("Glimmer", "quest givers, quest objects, herbs, ore and chests light up as you walk up", {
            find = "glimmer sparkle glow shine herbs herbalism ore mining vein node chest treasure quest object bobber fishing",
            icon = 136246, master = { Opt("glimmer"), function(on) YippRouteDB.glimmer = on YR.SettingChanged() end } })
        local preview = L.Block(GlimmerPreview(c), 150)
        -- (a change redraws the preview at once: it was drawn only as the page opened)
        local function Changed() YR.SettingChanged() preview:Refresh() end
        local look
        look = S.Dropdown(c, 180, YR.GLIMMER_LOOKS, function(v)
            YippRouteDB.glimmerStyle = v ~= "glint" and v or nil
            look:Refresh()
            Changed()
        end)
        function look:Refresh()
            for _, o in ipairs(YR.GLIMMER_LOOKS) do if o[1] == YR.GlimmerStyle() then self:SetValue(o[2]) end end
        end
        Row("Look", look, "Glints: twinkles around the object. Halo: a soft glow. Ripple: rings spreading on the ground."
            .. " Beam: a pillar of light. Marker: a diamond over it.")
        local COLOURS = { { "skill", "By chance of a skill-up" }, { "accent", "Headstart orange" }, { "white", "White" } }
        local colour
        colour = S.Dropdown(c, 200, COLOURS, function(v)
            YippRouteDB.glimmerColor = v ~= "skill" and v or nil
            colour:Refresh()
            Changed()
        end)
        function colour:Refresh()
            for _, o in ipairs(COLOURS) do if o[1] == YR.GlimmerColorMode() then self:SetValue(o[2]) end end
        end
        Row("Colour", colour, "By chance of a skill-up: herbs and ore in the trainer's colours (orange, yellow, green, grey) and"
            .. " red when your skill is too low; chests gold, quest objects yellow, the bobber blue.")
        L.Sub("What lights up")
        Row("Herbs", Sub("glimmerHerbs"), "With Herbalism.")
        Row("Ore", Sub("glimmerOre"), "With Mining.")
        Row("Chests", Sub("glimmerChests"))
        Row("Quest objects", Sub("glimmerQuest"), "Objects one of your quests needs: a crate to search, a plant to pick."
            .. " Orange sparkles fall over them, as over quest givers.")
        Row("Their quest line over them", Sub("glimmerQuestText"), "The quest's own line, with its count: \"Gnoll Paw: 3/8\".")
        Row("Quest givers", Sub("glimmerGivers"), "An NPC with a quest for you, to take or to hand in: orange sparkles over it, the"
            .. " game's own quest glimmer made large. With a RestedXP guide leading, only the NPC its step is at.")
        Row("Their quest's name over them", Sub("glimmerGiverText"), "The quest it has for you, and +1 for each more, over its"
            .. " name.")
        Row("Fishing bobber", Sub("glimmerFishing"))
        -- the game's interact key: Glimmer lights nothing without it, and it is yours to turn off (Glimmer.lua)
        local key = CreateFrame("Frame", nil, c)
        key:SetSize(260, 24)
        key.text = S.Text(key, 13, S.C.sub)
        key.text:SetPoint("RIGHT", -100, 0)
        key.button = S.Button(key, "Turn it on", function() YR.GlimmerInteractKeyOn() key:Refresh() end, nil, 90)
        key.button:SetPoint("RIGHT")
        function key:Refresh()
            local on = YR.GlimmerInteractKey and YR.GlimmerInteractKey()
            self.text:SetText(on and "On" or "|cffffb000Off: nothing lights up|r")
            self.text:ClearAllPoints()
            self.text:SetPoint("RIGHT", on and 0 or -100, 0)
            self.button:SetShown(not on)
        end
        Row("Interact key", key, "The game's Enable Interact Key (Options, Controls): Glimmer lights the object it would use."
            .. " Glimmer turns it on as you switch Glimmer on; turned off by you, it stays off until you turn it on here.")
        Row("In instances", S.Check(c, function() return YippRouteDB.glimmerInstances == true end,
            function(on) YippRouteDB.glimmerInstances = on or nil YR.SettingChanged() end),
            "Off: nothing lights up in dungeons and raids.")
        Row("About Glimmer", S.Text(c, 12, S.C.muted),
            "The object your interact key would use lights up: the game picks one, within some fifteen yards. Nothing in a"
            .. " fight. Glimmer turns on the game's soft targeting for objects, and shows the object's name plate while it is lit;"
            .. " both go back as they were when you turn Glimmer off.")
        L.Sub("Quest loot")
        Row("Quest loot sparkle", S.Check(c, function() return YippRouteDB.glimmerLoot == true end,
            function(on) YippRouteDB.glimmerLoot = on or nil YR.SettingChanged() end),
            "The game's own sparkle, on quest givers, quest objects and quest loot, seen from far off: the game draws it"
            .. " only while its outline effect is off, so this turns the outline off (two graphics settings). It is the"
            .. " game's look - Glimmer's looks and colours are for the one object in front of you, as near as the game"
            .. " picks it. Turning it off puts the outline back, but the sparkle stays until you restart the game.")
        -- (a "Put back" button for the game settings was here: the switch does it, and a login with
        -- Glimmer off puts back anything left over - the owner, 2026-10-14: "doesn't the toggle do?")
end)

-- Quests & invites: what answers for you in a group - invites accepted and sent on a whisper, quests shared
-- and accepted - and the quest rewards picked for you. Pages of their own under Automation since 2026-10-15
-- (they were rows of Group & invites and the end of Upgrades & rewards): everything that acts for you is
-- where All features has it, one grouping for the menu and that page alike.
-- Quests: the quest helpers, then quests shared in a party and the rewards picked for you. (It was "Quests & invites",
-- with the invites first; those are the Group page's now - the owner, 2026-10-20: better categories.)
local BuildQuests = QoLPage("quests", function(L, c, Section, Row, Opt)
        QuestSections(L, c, Section, Row, Opt)

        Section("Quest sharing", "share your quests, accept your party's", { find = "party quests auto accept", icon = 134327,
            master = MASTER.questShare })
        Row("Share quests I accept", S.Check(c, function() return YippRouteDB.shareAll == true end,
            function(on) YippRouteDB.shareAll = on end),
            "Shares every quest you accept from an NPC with your party. Off: only quests from a route are"
            .. " shared (Routes, Settings, Group play).")
        local FROM = { { "friends", "Guildies and friends" }, { "party", "Anyone in my party" }, { "off", "Nobody" } }
        local from
        from = S.Dropdown(c, 190, FROM, function(v) YippRouteDB.acceptFrom = v from:Refresh() end)
        function from:Refresh()
            for _, o in ipairs(FROM) do if o[1] == YR.AcceptFromSet() then self:SetValue(o[2]) end end
        end
        Row("Accept shared quests from", from, "Accepts quests and escorts shared by these players. Hold Shift as the quest opens to decide"
            .. " yourself. Leatrix Plus's \"Block shared quests\" declines them before Headstart can.")

        BuildRewards(L)   -- last: its list of hand-picked rewards grows
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
        Row("Equip window", S.Check(c, Opt("upgradeButton"), function(on) YippRouteDB.upgradeButton = on end),
            "Shows a small window with an Equip button. Off: a chat line only.")
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
            return S.Check(c, function()
                if offUnlessOn then return YippRouteDB[key] == true end
                return YippRouteDB[key] ~= false
            end, function(on)
                YippRouteDB[key] = on
                Applied()
            end)
        end
        Row("Size", RowSlider(c, 24, 64, 2, Num("trinketBarSize", 38), SetNum("trinketBarSize")))
        local DIRS = { { "side", "Side by side" }, { "stacked", "One above the other" } }
        local dir
        dir = S.Dropdown(c, 180, DIRS, function(v)
            YippRouteDB.trinketBarVertical = v == "stacked" or nil
            Applied()
            dir:Refresh()
        end)
        function dir:Refresh() self:SetValue(YippRouteDB.trinketBarVertical == true and "One above the other" or "Side by side") end
        Row("Buttons", dir)
        Row("When shown", Pick("trinketBarShow", { { "always", "Always" }, { "combat", "In combat" }, { "nocombat", "Out of combat" } }, "always"),
            "When the buttons are on screen.")
        Row("Left-click", Pick("trinketBarLeft", { { "list", "Lists your trinkets" }, { "use", "Uses the trinket" } }, "list"),
            "What a left-click on a button does. A right-click does the other. Changes out of combat.")
        Row("List on hover", Flag("trinketFlyHover", true), "Opens a button's list of trinkets when the mouse rests on it, and closes it when the"
            .. " mouse leaves. Off: the list opens on a click.")
        Row("About trinket buttons", S.Text(c, 12, S.C.muted),
            "Shows your trinket slots as buttons with their cooldowns. One click lists the trinkets in"
            .. " your bags, and a click on one equips it. In combat the swap waits until the fight ends."
            .. " The other click uses the trinket. Right-click a trinket in the list to add it to your"
            .. " swap order or remove it. The preview works: try the settings on it.")

        Section("Trinket auto-swap", "in the order you set below", { find = "swap trinkets", icon = 133437,
            master = { function() return YippRouteDB.trinketAuto == true end,
                function(on) YippRouteDB.trinketAuto = on if YR.TrinketPaint then YR.TrinketPaint() end end } })
        Row("About auto-swap", S.Text(c, 12, S.C.muted),
            "When the trinket you wear is on cooldown, the first ready trinket in your order is equipped. A"
            .. " higher one returns when it is ready again. A trinket you equip yourself that is not in the"
            .. " order is left alone. Swaps wait until you are out of combat. A green dot on a button means that"
            .. " slot is being swapped.")
        local function SlotSwitch(slot)
            return S.Check(c, function() return YR.TrinketDB().auto[slot] ~= false end,
                function(on) if on then YR.TrinketDB().auto[slot] = nil else YR.TrinketDB().auto[slot] = false end if YR.TrinketPaint then YR.TrinketPaint() end end)
        end
        Row("Top trinket slot", SlotSwitch(13))
        Row("Bottom trinket slot", SlotSwitch(14), "Off: this slot keeps what you equip in it.")
        Row("Pause while PvP flagged", S.Check(c, Opt("trinketPvpPause"), function(on) YippRouteDB.trinketPvpPause = on end),
            "Stops every automatic swap, here and under Mounted and swimming, while you are flagged for PvP. Your own"
            .. " clicks and equipment set keys still work.")

        Section("Mounted and swimming", "swap an item in while you ride or swim", { find = "swap rules carrot", icon = 132239,
            master = MASTER.mountSwim })
        local carrot = C_Item.GetItemNameByID and C_Item.GetItemNameByID(11122) or "Carrot on a Stick"
        Row("Mounted: " .. carrot, S.Check(c, function() return YippRouteDB.trinketMount == true end,
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
        Row("Swimming", S.Check(c, function() return YippRouteDB.trinketSwim == true end,
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
        Row("Hide Blizzard's bar", S.Check(c, Get("hideBlizz"), Set("hideBlizz")),
            "Hides Blizzard's experience and reputation bar while Headstart's bar is shown.")

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
            .. " your rested XP reaches.")
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
        Row("Show text on mouseover only", S.Check(c, Get("textHover"), Set("textHover")))

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
        Row("Text above the bar", S.Check(c, Get("over"), Set("over")), "Adds three more text slots just above the bar.")
        TextRow("Over, left", "left0")
        TextRow("Over, middle", "center0")
        TextRow("Over, right", "right0")
        Row("Text below the bar", S.Check(c, Get("under"), Set("under")), "Adds three more text slots just below the bar.")
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

        Section("Swing timer", "Blizzard's bars restyled, or Headstart's own", { icon = 132349,
            master = { function() return db().on == true end, Set("on") } })
        Row("Bars", Pick("style", { { "blizzard", "Blizzard's, restyled" }, { "own", "Headstart's own" } }, 180),
            "Blizzard's: the game's swing bars in this look, placed and sized in Edit Mode. Headstart's own: bars drawn by"
            .. " Headstart, placed and sized in Arrange; Blizzard's are made invisible while they show. The ranged bar"
            .. " stands in the main hand's place: the one swinging shows.")
        Row("When shown", Pick("show", { { "always", "Always" }, { "combat", "In combat" }, { "swing", "While swinging" },
            { "fade", "Faded between swings" } }, 180),
            "When Headstart's own swing bars show. Faded between swings: always there, see-through until they swing."
            .. " Blizzard's bars have their own setting in Edit Mode (Esc, Edit Mode: click a swing bar), with their size and place.")
        -- sample swings on the bars while this page is open, so a change is seen as it is made (it was a switch)
        local function SwingSamples() if db().on == true and not InCombatLockdown() then YR.SwingPreview(true) end end
        if c.HookScript then
            c:HookScript("OnShow", SwingSamples)
            c:HookScript("OnHide", function() if YR.SwingPreviewing() then YR.SwingPreview(false) end end)
        end
        -- (only if the page is seen: a search builds every page, and a page never shown is never hidden - the samples
        -- ran on your bars until the next fight; the review, 2026-10-21)
        if c.IsVisible and c:IsVisible() then SwingSamples() end
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
        Row("Text size", S.Stepper(c, Get("font"), Set("font"), 8, 24, 1, 110),
            "The bars' words; the range text is four sizes larger.")
        L.Sub("Range")
        Row("Range bar", S.Check(c, Get("rangeBar"), Set("rangeBar")),
            "A bar that says Melee range, Charge range (a spell with a least reach), Dead zone (too near for that, too far for"
            .. " melee), In range (within your spells' reach) or Out of range, in red, for the target you"
            .. " have, each in its own colour, with how far it is in steps of 5 yards. Made narrow, it shows the yards alone."
            .. " Shows while you have a living target you can attack. A hunter's says Melee range, In range, Dead zone or Out of range.")
        Row("Range text", S.Check(c, Get("rangeText"), Set("rangeText")),
            "How far your target is, in yards, as a line of text of its own that you can put anywhere with Arrange."
            .. " /headstart range says how it was told.")

        local function OwnBar(key)
            return S.Check(c, function() return db()[key] == true end, function(on)
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
        Row("Combo points", S.Check(c, function() return YR.ResourceBarWanted("combo") end, function(on)
            db().combo = on and true or false
            YR.ApplyParts()
            YR.SwingApply()
            YR:RefreshWindow()
        end), "Your combo points as a row of squares that fill, in the same look. On with the power bar unless you turn it"
            .. " off. Only on a class that has them.")
        Row("When shown", Pick("resShow", { { "always", "Always" }, { "combat", "In combat" } }, 180))
        Row("Health in class colour", S.Check(c, function() return db().healthClass == true end, Set("healthClass")))
        L.Sub("Look")
        Row("Text", Pick("resText", { { "all", "Percent and number" }, { "pct", "Percent" }, { "value", "Number" }, { "none", "None" } }, 180),
            "What the health and power bars say: the percent at the left, how much you have at the right.")
        Row("Colours", Pick("resTone", { { "bright", "Blizzard's" }, { "muted", "Darker" } }, 180),
            "Blizzard's: the game's own colours for health, energy, rage and mana. Darker takes them down a little."
            .. " The frame and texture are the swing timer's.")
        L.Sub("Blizzard's own resource bar")
        Row("Hide while Headstart's bars show", S.Check(c, function() return db().resHideBlizz ~= false end, function(on)
            if on then db().resHideBlizz = nil else db().resHideBlizz = false end
            YR.SwingApply()
        end), "Makes Blizzard's resource bar and its combo points invisible while Headstart's health or power bar is on, so"
            .. " you do not see both. It shows again in Edit Mode.")
        Row("Hide the spend flash", S.Check(c, function() return YippRouteDB.powerFlashOff == true end, function(on)
            YippRouteDB.powerFlashOff = on or nil
            YR.ApplyParts()
            YR.PowerFlashApply()
        end), "Removes the pale block Blizzard leaves where the resource you spent was. The bar drops to its new value at"
            .. " once and fills again from there. For the player frame, the personal resource display and the nameplate bar.")

        -- The cast bar: a bar of Headstart's own for your casts, in the swing timer's look.
        local function CastSwitch(key)
            return S.Check(c, function() return db()[key] ~= false end, function(on)
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
        -- where you stand now, and the runs in a window of their own
        local now = S.Text(c, 12, S.C.sub)
        function now:Refresh()
            local hour, day, wait = YR.InstanceCounts()
            local perHour, perDay = YR.InstanceLimits()
            self:SetText(("%d / %d this hour  ·  %d / %d today  ·  %s"):format(hour, perHour, day, perDay,
                wait and ("next free slot in " .. YR.InstanceClock(wait)) or "a slot is free now"))
            self:SetTextColor(unpack((hour >= perHour or day >= perDay) and S.C.danger or S.C.sub))
        end
        Row("Right now", now, "Counted from the runs in the log: new instances this hour and today, against the limits below.")
        Row("Instance log", S.Button(c, "Open", function() YR.InstanceLogShow() end, "primary", 90),
            "Your runs: when you went in, how long you were inside, the XP and gold, and the wait for a free slot. Also"
            .. " /headstart instances, and a click on the on-screen icon.")
        Row("Hourly limit", S.Stepper(c, function() return YippRouteDB.instanceHour or 5 end,
            function(v) YippRouteDB.instanceHour = v end, 1, 30, 1, 110),
            "How many new instances the game allows per hour. Forever's limit isn't known; 5 is Classic's. If"
            .. " the game refuses an entry, the log shows the count at that moment.")
        Row("Daily limit", S.Stepper(c, function() return YippRouteDB.instanceDay or 30 end,
            function(v) YippRouteDB.instanceDay = v end, 1, 100, 1, 110), "How many new instances the game allows per day. 30 on Classic.")
        Row("Account-wide count", S.Check(c, function() return YippRouteDB.instanceAccount == true end,
            function(on) YippRouteDB.instanceAccount = on end),
            "Counts all your characters toward one limit, as later expansions do. Off: each character has its"
            .. " own count, as in Classic.")
        Row("On-screen warning", S.Check(c, Opt("instanceWarn"), function(on) YippRouteDB.instanceWarn = on end),
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
        Row("On screen", hudMode, "Icon: this hour's count, coloured green, yellow or red, with the wait for a free slot. Hover it"
            .. " for today's count and your latest runs. Log: the same as text. Click either to open the instance log.")
        Row("Always show", S.Check(c, function() return YippRouteDB.instanceHudAlways == true end, function(on)
            YippRouteDB.instanceHudAlways = on
            YR.InstanceHudApply()
        end), "Off: shown only inside an instance, or when you have entered one this hour.")
end)

-- ---------------------------------------------------------------------------
-- Journey: the logging, and the window that tells it (Journey.lua, and Journey.lua here)
-- ---------------------------------------------------------------------------
local BuildJourney = QoLPage("journey", function(L, c, Section, Row, Opt)
        Section("Journey", "your road logged, and told as a story", { find = "journey wrapped stats log distance gold time played travelled",
            icon = 134939, master = { function() return YippRouteDB.journey ~= false end, function(on)
                if on then YippRouteDB.journey = nil else YippRouteDB.journey = false end
                YR.ApplyParts()
            end } })
        Row("Open your journey", S.Button(c, "Open", function() YR.JourneyOpen() end, "primary", 90),
            "Your latest chapter: how far you travelled, where the hours went, the gold you earned, your best find and more, a page"
            .. " at a time. A chapter is written when you reach level 20, 30, 40, 50 and 60, and at no other level - before the"
            .. " first, the window says when it comes. Also /hs journey")
        Row("Note when a chapter is written", S.Check(c, function() return YippRouteDB.journeyToast ~= false end, function(on)
            if on then YippRouteDB.journeyToast = nil else YippRouteDB.journeyToast = false end
        end), "A small note at the top of the screen for a few seconds when you reach level 20, 30, 40, 50 or 60. Click it to read the"
            .. " chapter. Off: the chapter is written all the same.")
        -- (asked first, as every other button that deletes: it went at one click, with the chapters written)
        StaticPopupDialogs["HEADSTART_JOURNEY_RESET"] = {
            text = "Headstart: forget this character's whole journey, the chapters already written too?",
            button1 = "Forget it",
            button2 = "Cancel",
            OnAccept = function() YR.JourneyReset() YR:RefreshWindow() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        Row("Start over", S.Button(c, "Reset", function() StaticPopup_Show("HEADSTART_JOURNEY_RESET") end, nil, 90),
            "Forgets everything logged for this character, the chapters too. It counts again from now. Asks first.")
        RoadSections(L, c, Section, Row, Opt)
end)

-- The instance log: a window of its own, as the chat log and the loot log are (it was the Instance tracker
-- page's first view, with the tracker's settings - its switch too - behind a Settings chip at the top right:
-- the owner, 2026-10-15, "you have to press Instance tracker and then Settings"). This hour's and today's
-- counts with the wait for a free slot, and the runs.
local LOG_W, LOG_ROWS = 900, 12
local logWin
local function InstanceLog()
    if logWin then return logWin end
    logWin = S.Window("HeadstartInstanceLog", LOG_W, 188 + LOG_ROWS * 26 + 60, "Instance log")
    local page = logWin
    inst.hint = S.Text(page, 12, S.C.muted)
    inst.hint:SetPoint("TOPLEFT", 16, -60)
    inst.hint:SetPoint("RIGHT", -16, 0)
    inst.hint:SetJustifyH("LEFT")
    inst.hint:SetWordWrap(false)
    inst.hour = Stat(page, 16, -84, "This hour")
    inst.next = Stat(page, 248, -84, "Next free slot")
    inst.day = Stat(page, 480, -84, "Today")
    -- what the columns are
    local heads = CreateFrame("Frame", nil, page)
    heads:SetPoint("TOPLEFT", 16, -166)
    heads:SetSize(LOG_W - 32, 20)
    for _, h in ipairs({ { 10, "ENTERED" }, { 140, "INSTANCE" }, { 440, "TIME INSIDE" }, { 550, "XP" }, { 650, "MONEY" } }) do
        local t = S.Text(heads, 10, S.C.muted)
        t:SetPoint("LEFT", h[1], 0)
        t:SetText(h[2])
    end
    local rule = heads:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT") rule:SetPoint("BOTTOMRIGHT", -8, 0) S.Hair(rule, "h")
    rule:SetColorTexture(unpack(S.C.line))
    inst.empty = S.Text(page, 13, S.C.muted)
    inst.empty:SetPoint("TOPLEFT", 26, -198)
    inst.empty:SetText("No runs yet. Dungeons and raids you enter are listed here.")
    inst.list = List(page, LOG_W - 32, LOG_ROWS, 26, function(r, i)
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
    inst.list:SetPoint("TOPLEFT", 16, -188)
    local reset = S.Button(page, "Mark as reset", function() YR.InstanceResetSeen() YR:RefreshWindow() end, nil, 150)
    reset:SetPoint("BOTTOMLEFT", 16, 14)
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
    -- the countdown runs while the window shows
    local wait = 0
    page:SetScript("OnUpdate", function(_, elapsed)
        wait = wait - elapsed
        if wait > 0 then return end
        wait = 1
        if inst.Refresh then inst.Refresh() end
    end)
    local settings = S.Button(page, "Settings", function() YR:ShowSettingsTab("instances") end, nil, 110)
    settings:SetPoint("BOTTOMRIGHT", -16, 14)
    settings.tip = "The tracker's switch, its limits and what it shows on screen"
    return logWin
end
--- The instance log, open (and drawn).
function YR.InstanceLogShow()
    local w = InstanceLog()
    w:Show()
    inst.Refresh()
end
--- The instance log, open or shut (/headstart instances, the on-screen icon).
function YR.InstanceLogToggle()
    local w = InstanceLog()
    if w:IsShown() then w:Hide() else YR.InstanceLogShow() end
end

function inst.Refresh()
    if not (inst.hour and logWin and logWin:IsShown()) then return end
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
        and "The instance tracker is off, so nothing is counted. Its switch is on its page (Settings, below)."
        or ("Each new dungeon or raid counts toward the hourly and daily limits.%s"):format(last and
        (" The game last refused an entry at %d this hour (%s)."):format(last.hour, date("%a %H:%M", last.at)) or
        " Limits and display: Settings, below."))
    inst.rows = InstanceRows()
    inst.empty:SetShown(#inst.rows == 0)
    inst.list:Refresh()
end

local function RefreshInstances()
    win.subtitle:SetText("")
    inst.Refresh()
    for _, ctl in ipairs(qolPages.instances.controls) do if ctl.Refresh then ctl:Refresh() end end
end

-- Skins: another look for the game's damage meter (DamageSkin.lua) and for RestedXP's guide window
-- (RXPSkin.lua) - which look, and the Headstart look's colours. One page for both since 2026-10-14 (each
-- had its own, two small pages in the menu).
local BuildSkins = QoLPage("skins", function(L, c, Section, Row, Opt)
        do
            Section("Damage meter skin", "a tidy top bar for the game's meter", { find = "dps details", icon = 132349,
                master = MASTER.dmgSkin })
            -- (Blizzard's own is the switch off: not a choice of look as well)
            local LOOKS = { { "headstart", "Headstart" }, { "blizzard", "Blizzard, tidied" } }
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
                set = (set == "headstart" or set == "blizzard") and set or "headstart"
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
            Row("Use class colour", S.Check(c, function() return YippRouteDB.dmgSkinClass == true end, function(on)
                YippRouteDB.dmgSkinClass = on
                YR.DamageSkinApply()
            end))
            Row("Background", Swatch(c, "frame", FrameColour, YR.DamageSkinApply), "The window's fill colour and opacity.")
            Row("Reset colours", S.Button(c, "Reset", function()
                YippRouteDB.dmgSkinAccent, YippRouteDB.dmgSkinFrame, YippRouteDB.dmgSkinClass = nil, nil, nil
                YR.DamageSkinApply()
                YR:RefreshWindow()
            end, nil, 90))
        end
        do
            Section("RestedXP skin", "another look for RestedXP's window", { find = "rxp guide", icon = 134939,
                master = MASTER.rxpSkin })
            -- (RestedXP's own is the switch off)
            local LOOKS = { { "headstart", "Headstart" }, { "blizzard", "Blizzard" } }
            local look
            look = S.Dropdown(c, 190, LOOKS, function(v)
                if not YR.SetRXPSkin(v) then YR.Print("RestedXP isn't loaded: nothing to skin.") end
                look:Refresh()
            end)
            function look:Refresh()
                local set = YR.RXPSkinModeSet()
                set = set ~= "off" and set or "headstart"
                for _, o in ipairs(LOOKS) do if o[1] == set then self:SetValue(o[2]) end end
            end
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
            Row("Use class colour", S.Check(c, function() return YippRouteDB.rxpSkinClass == true end, function(on)
                YippRouteDB.rxpSkinClass = on
                YR.RXPSkinApply()
            end), "Uses each character's class colour as the accent.")
            Row("Background", Swatch(c, "back", Back, YR.RXPSkinApply), "The window's fill colour and opacity.")
            Row("Reset colours", S.Button(c, "Reset", function()
                YippRouteDB.rxpSkinAccent, YippRouteDB.rxpSkinBack, YippRouteDB.rxpSkinClass = nil, nil, nil
                YR.RXPSkinApply()
                YR:RefreshWindow()
            end, nil, 90))
        end
end)

-- Chat: Blizzard's buttons beside the chat (BarHide.lua), and the whisper sound (Whisper.lua).
local BuildChat = QoLPage("chat", function(L, c, Section, Row, Opt)
        Section("Chat buttons", "slim or hide the buttons beside chat", { icon = "Interface\\Icons\\INV_Misc_Note_01",
            master = MASTER.chatButtons })
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
        Row("Hide the text-to-speech button", S.Check(c, function() return YippRouteDB.chatTTSHide == true end, function(on)
            YippRouteDB.chatTTSHide = on or nil
            YR.BarHideApply()
        end), "Hides the speaker button above the strip.")
        Row("Hide the social button", S.Check(c, function() return YippRouteDB.chatSocialHide == true end, function(on)
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
        Row("Button beside chat", S.Check(c, function() return YippRouteDB.chatLogButton ~= false end, function(on)
            YippRouteDB.chatLogButton = on
            YR.ChatLogApply()
        end), "Adds a small button beside chat that opens the log.")
        Row("Restore chat after reload", S.Check(c, function() return YippRouteDB.chatLogRestore ~= false end,
            function(on) YippRouteDB.chatLogRestore = on end),
            "Puts the last lines back into each chat window after a login or reload, so you can scroll up as"
            .. " before.")
        Row("Keep between sessions", S.Check(c, function() return YippRouteDB.chatLogKeep ~= false end,
            function(on) YippRouteDB.chatLogKeep = on end),
            "Keeps the log when you log out, with a marker where each session began. Off: the log starts"
            .. " empty at every login.")
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

        Section("Whisper sound", "your own sound for whispers", { icon = 133469, master = MASTER.whisperSound })
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
        Row("Battle.net whispers too", S.Check(c, Opt("whisperBNet"), function(on) YippRouteDB.whisperBNet = on end),
            "Plays the sound for a Battle.net whisper as well.")
end)

-- Blizzard's bars and windows: the bag bar and micro menu out of the way (BarHide.lua), Blizzard's windows scaled,
-- and the bag windows moved (Movers.lua). (The talent window is the Talents page's.)
local BuildWindows = QoLPage("windows", function(L, c, Section, Row, Opt)
        Section("Bag bar and micro menu", "hidden, or shown on mouseover", { find = "blizzard bars hide", icon = 133633,
            master = MASTER.bagBars })
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

        Section("Window scale", "100 is Blizzard's size", { find = "window sizes", icon = 134063, master = MASTER.windowScale })
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

        Section("Bag position", "move the bag windows", { icon = "Interface\\Icons\\INV_Misc_Bag_09", master = MASTER.bagMove })
        Row("Move the combined bag", S.Check(c, function() return YippRouteDB.moveBag == true end, function(on)
            YippRouteDB.moveBag = on
            YR.MoverPlace("bag")
        end), "Drag Blizzard's combined bag by its title bar. It opens there from then on. Not in combat.")
        Row("Move the reagent bag", S.Check(c, function() return YippRouteDB.moveReagentBag == true end, function(on)
            YippRouteDB.moveReagentBag = on
            YR.MoverPlace("reagentBag")
        end), "The same for the reagent bag.")
        Row("Reset positions", S.Button(c, "Reset", function()
            YR.MoverReset("bag")
            YR.MoverReset("reagentBag")
        end, nil, 90), "Both bags open where Blizzard puts them again.")
end)

-- Talents: the talent window (TalentFade.lua: see-through, size, moving it) and the talent builds (Talents.lua).
-- (Both were cards on Bars & windows, until the Interface tab gave them room: 2026-10-20.)
-- (the builds first: their card is the page's width, and a half card before it left a hole beside it)
-- The talent window (TalentFade.lua). Talent builds - what to take at each level - were a card here until 2026-10-21;
-- they are the Levelling tab's Talents page now ("the talent planner belongs somewhere else than Interface" - the owner).
local BuildTalents = QoLPage("talents", function(L, c, Section, Row, Opt)
        Section("Talent window", "see-through and movable", { find = "fade transparent", icon = 136243, master = MASTER.talentWin, wide = true })
        Row("Background transparency (percent)", RowSlider(c, 0, 100, 5, YR.TalentFade, YR.SetTalentFade, 260),
            "How much of the talent window's background is faded out. 0: Blizzard's own. Talents, text and"
            .. " buttons stay solid.")
        Row("Sliders on the talent window", S.Check(c, Opt("talentFadeSlider"), function(on)
            YippRouteDB.talentFadeSlider = on
            YR.TalentFadeApply()
        end), "Adds transparency and scale sliders to the bottom of the talent window.")
        Row("Scale (percent)", RowSlider(c, 50, 150, 1, YR.TalentScale, YR.SetTalentScale, 260),
            "Makes the talent window smaller or larger. 100: Blizzard's size; never larger than fits your screen. Not in combat.")
        Row("Talents before level 10", S.Check(c, Opt("talentEarly"), function(on)
            YippRouteDB.talentEarly = on
            YR.ApplyParts()
            if YR.TalentEarlyApply then YR.TalentEarlyApply() end
        end), "Your talent key (N) opens Headstart's Talents page before level 10: your class's trees and what to take"
            .. " at each level, to look at and plan. The points to spend come at 10.")
        Row("Move by dragging", S.Check(c, Opt("talentMove"), function(on)
            YippRouteDB.talentMove = on
            YR.TalentPlace()
        end), "Drag the talent window by its title bar or any empty area. It opens there from then on. The"
            .. " spellbook is the same window and moves with it. Not in combat.")
        Row("Reset position", S.Button(c, "Reset", function() YR.TalentResetPosition() end, nil, 90),
            "Moves the window back to the middle of the screen.")
end)

-- General: what is about no one thing you do - the game's cinematics, and Headstart itself (its minimap button,
-- the colour of its windows). The owner looked for Skip cinematics under Bars & windows and would never have
-- found it there (2026-10-14); Leatrix Plus keeps such things on pages of their own too ("System" and
-- "Settings"). First in the menu after All features, under no group: where you look for what fits nowhere.
local BuildGeneral = QoLPage("general", function(L, c, Section, Row, Opt)
        Section("Intro cinematic", "skipped on a new character", { find = "skip cinematic intro movie opening", icon = 133885,
            master = { Opt("skipCinematic"), function(on) YippRouteDB.skipCinematic = on end } })
        Row("About skipping it", S.Text(c, 12, S.C.muted),
            "Ends a new character's opening flight over its zone as it starts. Every other cinematic plays. Hold Shift as"
            .. " you enter the world to watch it. On unless you turn it off.")

        -- (its only switch was on the routes' settings page, which is not there while the routes are off -
        -- as on every new install)
        Section("Headstart's minimap button", "the button by the minimap", { find = "minimap icon button hide", icon = 134269,
            master = { function() return YR.OptionSet("minimapButton") end, function(on) YR:ShowMinimapButton(on) end } })
        Row("About the button", S.Text(c, 12, S.C.muted),
            "Headstart's own button by the minimap: left click opens this window, right click a menu of its windows. Off: /headstart"
            .. " and /hs still open them.")

        Section("Headstart's look", "the colour of Headstart's own windows", { find = "accent colour color theme", icon = 134123 })
        local options = {}
        for _, a in ipairs(S.ACCENTS) do options[#options + 1] = { a[1], a[2] } end
        local accent
        accent = S.Dropdown(c, 190, options, function(v)
            local was = YippRouteDB.accent
            YippRouteDB.accent = v ~= "ember" and v or nil
            -- (said once, in chat: a row kept for these words stood empty under the colour until one was picked)
            if YippRouteDB.accent ~= was then YR.Print("the new colour shows after Reload UI (the button at the bottom of this window).") end
            YR:RefreshWindow()
        end)
        function accent:Refresh()
            local now = YippRouteDB.accent or "ember"
            for _, a in ipairs(S.ACCENTS) do if a[1] == now then self:SetValue(a[2]) end end
        end
        Row("Accent colour", accent, "The colour of Headstart's windows: their edges, switches and buttons. A new one shows after"
            .. " Reload UI.")

        Section("Put back everything", "your screen as it was before Headstart", { find = "undo revert reset restore uninstall remove put back",
            icon = 134520 })
        Row("Put back everything Headstart changed", S.Button(c, "Put back...", function() YR.AskPutBack() end, nil, 110),
            "Turns quality of life and Character setup off, and puts this character's bars, macros, key bindings, game settings,"
            .. " Edit Mode layout and chat windows back as they were before Headstart first changed them. Asks first. Also"
            .. " /headstart putback")
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
    -- a setting on a card that holds other things too: not a switch for the whole card (see QoLPage)
    local function Plain(f) f.plain = true return f end
    local setup = F(134166, "Bar profiles & planner", "Your bars, macros and interface on every character.", nil, nil,
        function() return YR.SetupOn() end, YR.SetSetupOn)
    setup.go = function() YR:ShowSettingsTab("setup") end
    local talents = F(132222, "Talent builds", "What to take at each level, followed here.", nil, nil,
        function() return YR.TalentFollowed and YR.TalentFollowed() ~= nil end, function(on)
            if not on then YR.TalentFollow(nil) return end
            local list = YR.TalentBuildsOf and YR.TalentBuildsOf(YR.TalentClassID()) or {}
            if list[1] then YR.TalentFollow(list[1].key) end
        end)
    talents.go = function() YR:ShowSettingsTab("builds") end
    -- (General's two cards - the intro cinematic, the minimap button - stood first until 2026-10-20: "general
    -- settings don't need to be in All features" - the owner. They are on General, last in the menu.)
    local groups = {
        { "Levelling",
            F(132181, "World marker", "Your map pin, shown in the world.", "quests", "World marker",
                Toggle("waypoint", function() YR.ApplyParts() end)),
            F(133631, "Quest item buttons", "Quest items and rewards you use, a click away.", "quests", "Quest item buttons",
                Toggle("questItems", function() YR.QuestItemsApply() end)),
            F(131013, "Quest mob markers", "Enemies you need for a quest, marked.", "quests", "Quest mob markers",
                Toggle("npcMarkers", function() YR.ApplyParts() end)),
            F(132049, "Quests on NPC tooltips", "What an NPC has for you, when you hover it.", "quests",
                "Quests on NPC tooltips", Toggle("questTips", function() YR.ApplyParts() end)),
            F(134327, "Quest sharing", "Share your quests, accept your party's.", "quests", "Quest sharing",
                MASTER.questShare[1], MASTER.questShare[2]),
            F(132739, "Quest rewards", "A reward picked and the quest handed in, up to a level.", "quests", "Quest rewards",
                function() return YR:RewardSettings().on == true end, function(on) YR:RewardSettings().on = on end),
            F(134939, "Journey", "Your road logged: distance, time, gold, loot.", "journey", "Journey",
                function() return YippRouteDB.journey ~= false end,
                function(on) if on then YippRouteDB.journey = nil else YippRouteDB.journey = false end YR.ApplyParts() end),
            F(132239, "Flight timer", "Time left while you fly.", "journey", "Flight timer",
                Toggle("flightTimer", function(on) YR:SetFlightTimer(on) end)),
            F(134440, "Boat timer", "When the boat at your dock leaves.", "journey", "Boat timer",
                Toggle("boatTimer", function() YR.BoatTimerApply() end)),
            F(135805, "Camp icon", "Lit near a camp, or while its buff runs.", "journey", "Camp icon",
                Toggle("camp", function(on) YR.SetCampIcon(on) end)),
            F(134376, "Reminders", "Trainer, talent points and repairs, said in time.", "reminders", "Reminders",
                MASTER.reminders[1], MASTER.reminders[2]),
            F(133685, "Craftable items", "Says when you can make stones, oils or bandages.", "reminders", "Craftable items",
                Toggle("craftRemind")),
            F(134441, "Level-up screenshot", "A screenshot every time you level.", "reminders", "Level-up screenshot",
                Toggle("levelShot")),
            F(134237, "Instance tracker", "Dungeon entries counted against the limits.", "instances", "Instance tracker",
                Toggle("instanceTrack", function() if YR.InstanceHudApply then YR.InstanceHudApply() end end)),
            talents,
        },
        { "Automation",
            F(133741, "Auto-train", "Buys your class's spells as the trainer opens.", "trainer", "Class trainer",
                Toggle("autoTrain", function() YR:SyncRxpTrainer() end)),
            F(133785, "Restock", "Buys reagents, ammo and your list at vendors.", "vendors", "Restock", Toggle("restock")),
            F(133639, "Bank deposit", "A Deposit button that moves mats and recipes to the bank.", "bags", "Bank deposit", Toggle("bankButton", YR.SetBankButton)),
            F(133471, "Mail to alt", "Sends mats and recipes to another character.", "bags", "Mail to alt",
                function() return YR.OptionSet("mailButton") end, YR.SetMailButton),
        },
        { "Loot & gear",
            F(136246, "Glimmer", "Herbs, ore, chests and quest objects light up.", "glimmer", "Glimmer",
                Toggle("glimmer", function() YR.SettingChanged() end)),
            F(133784, "Loot feed", "Recent loot, in lines that fade.", "loot", "Loot feed",
                Toggle("lootFeed", function() YR.LootFeedApply() end)),
            F(132739, "Upgrade estimate", "DPS and toughness change on item tooltips.", "gear", "Upgrade estimate",
                Toggle("simTooltip")),
            F(133071, "Upgrade alerts", "Says when loot beats what you wear.", "gear", "Upgrade alerts", Toggle("upgrades")),
            F("Interface\\Icons\\INV_Misc_Bag_09", "Characters", "Bags, bank and gold of your other characters.", "alts",
                "Characters", Toggle("alts")),
        },
        { "Social",
            F("Interface\\Icons\\INV_Misc_Note_01", "Chat buttons", "Slim or hide the buttons beside chat.", "chat", "Chat buttons",
                MASTER.chatButtons[1], MASTER.chatButtons[2]),
            F(134939, "Chat log", "Search and copy chat, past sessions too.", "chat", "Chat log",
                Toggle("chatLog", function() YR.ChatLogApply() end)),
            F(133469, "Whisper sound", "Your own sound for whispers.", "chat", "Whisper sound",
                MASTER.whisperSound[1], MASTER.whisperSound[2]),
            F(134149, "Accept invites", "Group invites accepted, and who whispers \"inv\" invited.", "group", "Invites",
                MASTER.invites[1], MASTER.invites[2]),
            F(134149, "Invite & Leave buttons", "Group up for a kill, and leave again.", "group", "Invite and Leave buttons",
                Toggle("groupBar", function(on) YR.SetGroupBar(on) end)),
            F(133884, "Quest group finder", "Ask chat for a group, see who answers.", "group", "Quest group finder",
                Toggle("questLFG")),
        },
        { "On screen",
            F(236562, "XP bar", "Rested and quest XP on a bar of your own.", "xpbar", "XP bar",
                function() return YR.XPBarOn() end, function(on) YR.XPBarDB().on = on YR.XPBarApply() end),
            F(132349, "Swing timer", "Bars for your auto-attacks.", "swing", "Swing timer",
                function() return YR.SwingDB().on == true end, function(on) YR.SwingDB().on = on YR.SwingApply() end),
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
            F(133434, "Trinket buttons", "Your trinkets on screen. Click one to swap.", "trinkets", "Trinket buttons",
                Toggle("trinketBar", function(on) YR.ShowTrinketBar(on) end)),
            F(133437, "Trinket auto-swap", "Swaps trinkets in by your own rules.", "trinkets", "Trinket auto-swap",
                function() return YippRouteDB.trinketAuto == true end,
                function(on) YippRouteDB.trinketAuto = on if YR.TrinketPaint then YR.TrinketPaint() end end),
            F(237274, "Death recap", "What killed you, shown when you die.", "recap", "Death recap",
                Toggle("deathRecap", function() YR.RecapApply() end)),
        },
        { "Blizzard's UI",
            F(133633, "Bag bar and micro menu", "Hidden, or shown on mouseover.", "windows", "Bag bar and micro menu",
                MASTER.bagBars[1], MASTER.bagBars[2]),
            F(134063, "Window scale", "Blizzard's windows smaller or larger.", "windows", "Window scale",
                MASTER.windowScale[1], MASTER.windowScale[2]),
            F(136243, "Talent window", "See-through and movable.", "talents", "Talent window",
                MASTER.talentWin[1], MASTER.talentWin[2]),
            F(132349, "Damage meter skin", "A tidy top bar for the game's damage meter.", "skins", "Damage meter skin",
                MASTER.dmgSkin[1], MASTER.dmgSkin[2]),
            F(134939, "RestedXP skin", "Another look for RestedXP's window.", "skins", "RestedXP skin",
                MASTER.rxpSkin[1], MASTER.rxpSkin[2]),
        },
        { "Character setup", setup },
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
    desc:SetWidth(w - 46 - 62)
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
local NEWS_FOR = "0.10.0"
local NEWS = { ["World marker"] = true, ["Quest item buttons"] = true, ["Quest mob markers"] = true, ["Quests on NPC tooltips"] = true }
function YR.HomeNews() return NEWS_FOR, NEWS end

local function BuildHome(page)
    local area = S.ScrollArea(page, CW - 24, CH - 64)
    area:SetPoint("TOPLEFT", 16, -4)
    local c = area.content
    c:SetWidth(CW - 40)
    local gap = 8
    local w = math.floor((CW - 40 - 2 * gap) / 3)
    local groups = HomeFeatures()
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

    -- Each group folds to its heading: a click on it and its cards go, again and they are back; the heading says how
    -- many of its features are on, folded or not (the owner, 2026-10-20: "should there be some collapse here too?").
    -- Open is how a group starts, as a page's cards do; the ones you fold are remembered (YippRouteDB.homeFolded).
    local heads = {}
    local function LayBody()
        local folded = type(YippRouteDB.homeFolded) == "table" and YippRouteDB.homeFolded or {}
        local y = -4
        for _, h in ipairs(heads) do
            local top, shut = y, folded[h.name] == true
            h.shut = shut
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 0, y)
            h.arrow:SetRotation(shut and -math.pi / 2 or math.pi)     -- (the art points up: turned right, or down)
            h:Count()
            y = y - 26
            for i, card in ipairs(h.cards) do
                card:SetShown(not shut)
                if not shut then
                    local col = (i - 1) % 3
                    card:ClearAllPoints()
                    card:SetPoint("TOPLEFT", col * (w + gap), y)
                    if col == 2 or i == #h.cards then y = y - 58 - gap end
                end
            end
            y = y - 4
            if h.span then          -- (the group the tour points at: its heading and its cards)
                h.span:ClearAllPoints()
                h.span:SetPoint("TOPLEFT", 0, top)
                h.span:SetSize(CW - 40, math.max(22, top - y - 6))
            end
        end
        bodyH = -y
        body:SetHeight(bodyH)
    end
    for _, group in ipairs(groups) do
        local h = CreateFrame("Button", nil, body)
        h:SetSize(CW - 40, 22)
        h.name = group[1]
        h.arrow = h:CreateTexture(nil, "ARTWORK")
        h.arrow:SetSize(10, 10)
        h.arrow:SetPoint("LEFT", 2, -2)
        S.ArtTexture(h.arrow, "up")
        h.arrow:SetVertexColor(unpack(S.C.muted))
        h.text = S.Text(h, 11, S.C.muted)
        h.text:SetPoint("LEFT", 18, -2)
        h.text:SetText(group[1]:upper())
        h.count = S.Text(h, 11, S.C.muted)
        h.count:SetPoint("RIGHT", -2, -2)
        h.count:SetJustifyH("RIGHT")
        h.cards, h.span, h.shut = {}, false, false
        for i = 2, #group do
            local card = HomeCard(body, group[i], w)
            front.cards[#front.cards + 1] = card
            h.cards[#h.cards + 1] = card
        end
        function h:Count()
            local on = 0
            for i = 2, #group do
                local f = group[i]
                if f.get and f.get() then on = on + 1 end
            end
            self.count:SetText(("%d of %d on"):format(on, #group - 1))
        end
        h:SetScript("OnEnter", function(self) self.text:SetTextColor(unpack(S.C.text)) end)
        h:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(S.C.muted)) end)
        h:SetScript("OnClick", function(self)
            YippRouteDB.homeFolded = type(YippRouteDB.homeFolded) == "table" and YippRouteDB.homeFolded or {}
            YippRouteDB.homeFolded[self.name] = (not YippRouteDB.homeFolded[self.name]) or nil
            LayBody()
            Lay()
        end)
        if group[1] == "Automation" then
            h.span = CreateFrame("Frame", nil, body)
            tourAt.automation = h.span
        end
        heads[#heads + 1] = h
    end
    front.heads, front.layBody = heads, LayBody
    LayBody()
    Lay()
end

local function RefreshHome()
    for _, card in ipairs(front.cards) do card:Refresh() end
    if front.layBody then front.layBody() end   -- (each heading's count of what is on)
    if front.lay then front.lay() end           -- (the beta's banner: there, or hidden for now)
end
--- All features' group headings once the page is built (for the tests): each with its name, shut, cards.
function YR.HomeHeads() return front.heads end
--- The cards on the first page (for the tests): { { name, on or state }, ... } once it has been opened.
function YR.HomeFeatures() return HomeFeatures() end
function YR.SettingsIndex() return settings.index or {} end
--- A QoL page's layout once it is built: its cards, and Reflow (the tests).
function YR.SettingsLayout(key) return qolPages[key] and qolPages[key].L end
--- How far down QoL's menu reaches, and the room it has (for the tests).
function YR.SettingsMenuFits() return settings.navBottom, PH end

-- The menu, on two tabs - and the All features page has the same groups in the same order (the owner,
-- 2026-10-15: "All features has another grouping than the menu - what is best?"; one map to learn, not two).
-- Every page is named after the thing it is about, the name a player would look for, and one thing has one place.
-- QoL, what Headstart does for you:
--   Levelling       the quest helpers, sharing and rewards; the journey and its timers; reminders; instances
--   Automation      what acts for you: the class trainer, restock, the bank and mail
--                   (Leatrix Plus opens on its Automation page too; nothing on without the player knowing)
--   Loot & gear     Glimmer, the loot feed and log, upgrades, your other characters
--   Social          chat; invites, the Invite and Leave buttons and the quest group finder
--   Headstart       General: cinematics, Headstart's minimap button, the colour of its windows (last: not a feature)
-- Interface, what it puts on your screen and does to Blizzard's:
--   On screen       the XP bar, combat bars, trinkets, the death recap
--   Blizzard's UI   Blizzard's bars and windows, the talent window and builds, skins for the damage meter and RestedXP
-- (Regrouped 2026-10-14 at the owner's asking; the small pages merged and Quality of life's switch moved to All
-- features the same day; General, Automation and one grouping for both on 2026-10-15; the Interface tab, the
-- Quests and Talents pages, invites to Group and General last on 2026-10-20: "better sidebar groups".)
-- Each page says what is on it under its name (its sections, as links: PageHead).
local BuildLibrary, RefreshLibrary, BuildBuilds, RefreshBuilds          -- (made in a block of their own, below)
local CATEGORIES = {
    -- QoL: what Headstart does for you
    { key = "home", tab = "qol", label = "All features", build = BuildHome, refresh = RefreshHome, icon = "Interface\\AddOns\\Headstart\\art\\logo",
      scope = "Every character on this account",
      desc = "Everything Headstart does. Switch a feature on here; click its card for the settings." },
    { group = "Levelling", tab = "qol" },
    { key = "quests", label = "Quests", build = BuildQuests, refresh = QoLRefresh("quests", RefreshRewards), icon = 236664,
      status = function() return YR.Option("waypoint") or YR.Option("questItems") or YR.Option("npcMarkers") or YR.Option("questTips")
          or YippRouteDB.shareAll == true or YR.AcceptFromSet() ~= "off" or YR:RewardSettings().on == true end,
      scope = "Every character; quest rewards per class",
      desc = "Your map pin in the world, quest items a click away, quest mobs marked, quests on tooltips, sharing and rewards." },
    -- (a Levelling tab page for a day, 2026-10-21, then here: "keep Levelling, and move Talents in" - the owner)
    { key = "builds", label = "Talents", build = function(f) BuildBuilds(f) end, refresh = function() RefreshBuilds() end, icon = 132222,
      status = function() return YR.TalentFollowed and YR.TalentFollowed() ~= nil end,
      scope = "Every character; the build you follow per character",
      desc = "What to take at each level. Follow a build, and the talent points notice says which talent is next." },
    { key = "journey", label = "Journey", build = BuildJourney, refresh = QoLRefresh("journey"), icon = 134939,
      status = function() return YippRouteDB.journey ~= false or YR.Option("flightTimer") or YR.Option("camp") or YR.Option("boatTimer") end,
      scope = "Every character; each has its own journey",
      desc = "Your road as a story, the flight and boat timers, and the camp icon." },
    { key = "reminders", label = "Reminders", build = BuildReminders, refresh = QoLRefresh("reminders"), icon = 134376,
      status = function() return YR.Option("remindTrainer") or YR.Option("remindTalents") or YR.Option("durability") or YR.Option("craftRemind") or YR.Option("levelShot") end, scope = "Every character on this account",
      desc = "Said when something needs doing: the trainer, talent points to spend (on screen), repairs, items to craft." },
    { key = "instances", label = "Instance tracker", build = BuildInstanceSettings, refresh = RefreshInstances, icon = 134237,
      status = function() return YR.Option("instanceTrack") end, scope = "Every character on this account",
      desc = "The dungeons and raids you entered this hour and today, against the limits." },
    { group = "Automation" },
    { key = "trainer", label = "Class trainer", build = BuildTrainer, refresh = function() trainer.refresh() end, icon = 133741,
      status = function() return YR.Option("autoTrain") end, scope = function() return "Every " .. (UnitClass("player") or "character") .. " on this account" end,
      desc = "Buys your class's spells as the trainer opens, as far as your gold goes above what you keep." },
    { key = "vendors", label = "Vendors & restock", build = BuildVendors, refresh = QoLRefresh("vendors"), icon = 133785,
      status = function() return YR.Option("restock") end, scope = "Every character on this account",
      desc = "Reagents, ammo and your own list bought back up to the count you keep." },
    { key = "bags", label = "Bank & mail", build = BuildBags, refresh = QoLRefresh("bags"), icon = 133633,
      status = function() return YR.Option("bankButton") or YR.Option("mailButton") end, scope = "Every character on this account",
      desc = "Crafting mats and recipes moved to the bank, or mailed to another character." },
    { group = "Loot & gear" },
    { key = "glimmer", label = "Glimmer", build = BuildGlimmer, refresh = QoLRefresh("glimmer"), icon = 136246,
      status = function() return YR.Option("glimmer") end, scope = "Every character on this account",
      desc = "Herbs, ore, chests, quest objects and your bobber light up as you walk up to them." },
    { key = "loot", label = "Loot feed & log", build = BuildLoot, refresh = QoLRefresh("loot"), icon = 133784,
      status = function() return YR.Option("lootFeed") end, scope = "Every character; the log per character",
      desc = "Recent loot as lines on screen, and a log with session totals." },
    { key = "gear", label = "Upgrades", build = BuildGear, refresh = QoLRefresh("gear"), icon = 132739,
      status = function() return YR.Option("simTooltip") or YR.Option("upgrades") end, scope = "Every character on this account",
      desc = "Upgrades in your bags pointed out, and what an item would change for you." },
    { key = "alts", label = "Other characters", build = BuildAlts, refresh = QoLRefresh("alts"), icon = "Interface\\Icons\\INV_Misc_Bag_09",
      status = function() return YR.Option("alts") end, scope = "Every character on this account",
      desc = "The bags, bank and gold of your other characters." },
    { group = "Social" },
    { key = "chat", label = "Chat", build = BuildChat, refresh = QoLRefresh("chat"), icon = "Interface\\Icons\\INV_Misc_Note_01",
      status = function() return YippRouteDB.chatStrip ~= nil or YippRouteDB.chatTTSHide == true or YippRouteDB.chatSocialHide == true
          or YippRouteDB.whisperSound ~= nil or YR.Option("chatLog") end, scope = "Every character on this account",
      desc = "A chat log to search and copy from, a whisper sound, and fewer buttons beside chat." },
    { key = "group", label = "Group", build = BuildGroup, refresh = QoLRefresh("group"), icon = 134149,
      status = function() return YR.AcceptInvitesSet() ~= "off" or YR.WhisperInviteSet() ~= "off" or YR.Option("groupBar") or YR.QuestLFGOn() end,
      scope = "Every character on this account",
      desc = YR.QuestLFGAvailable and "Invites accepted and sent on a whisper, Invite and Leave buttons, and a group finder for your quests."
          or "Invites accepted and sent on a whisper, and Invite and Leave buttons." },
    { group = "Headstart" },
    { key = "general", label = "General", build = BuildGeneral, refresh = QoLRefresh("general"), icon = 134064,
      status = function() return YR.Option("skipCinematic") end, scope = "Every character on this account",
      desc = "The intro cinematic skipped, Headstart's minimap button, the colour of its windows, and putting everything back." },
    -- Interface: what Headstart puts on your screen, and what it does to Blizzard's
    { group = "On screen", tab = "interface" },
    { key = "xpbar", label = "XP bar", build = BuildXPBar, refresh = QoLRefresh("xpbar"), icon = 236562,
      status = function() return YR.XPBarOn() end, scope = "Every character on this account",
      desc = "Your own experience bar: size, position, colours and text." },
    { key = "swing", label = "Combat bars", build = BuildSwing, refresh = QoLRefresh("swing"), icon = "Interface\\Icons\\INV_Sword_04",
      status = function() return YR.SwingOn() or YippRouteDB.powerFlashOff == true end, scope = "Which bars show per character; the look for all",
      desc = "Swing timer, health, power, cast and range bars, and Blizzard's resource bar without the spend flash." },
    { key = "trinkets", label = "Trinkets & gear sets", build = BuildTrinkets, refresh = QoLRefresh("trinkets", RefreshTrinkets),
      icon = 133434, status = function() return YR.Option("trinketBar") or YippRouteDB.trinketAuto == true end,
      scope = "Every character; the swap order per character",
      desc = "Trinket buttons, automatic trinket swaps, and key bindings for equipment sets." },
    { key = "recap", label = "Death recap", build = BuildRecap, refresh = QoLRefresh("recap"), icon = 237274,
      status = function() return YR.Option("deathRecap") end, scope = "Every character on this account",
      desc = "What killed you and the hits before it, shown when you die." },
    { group = "Blizzard's UI" },
    { key = "windows", label = "Bars & windows", build = BuildWindows, refresh = QoLRefresh("windows"), icon = 136243,
      status = function() return YippRouteDB.moveBag == true or YippRouteDB.moveReagentBag == true
          or YippRouteDB.bagBar ~= nil or YippRouteDB.microMenu ~= nil
          or (type(YippRouteDB.windowScale) == "table" and next(YippRouteDB.windowScale) ~= nil) end,
      scope = "Every character on this account",
      desc = "Blizzard's bag bar and micro menu hidden, its windows scaled, and the bags moved." },
    { key = "talents", label = "Talent window", build = BuildTalents, refresh = QoLRefresh("talents"), icon = 136243,
      status = function() return YR.TalentFade() > 0 or YR.Option("talentMove") end,
      scope = "Every character on this account",
      desc = "The talent window see-through, larger or smaller, movable, and open before level 10." },
    { key = "skins", label = "Skins", build = BuildSkins, refresh = QoLRefresh("skins"), icon = 132906,
      status = function() return YR.DamageSkinMode() ~= "off" or YR.RXPSkinMode() ~= "off" end, scope = "Every character on this account",
      desc = "Another look for the game's damage meter and for RestedXP's guide window." },
}
-- each page is on the tab of the group it is under
do
    local tab = "qol"
    for _, t in ipairs(CATEGORIES) do
        if t.tab then tab = t.tab else t.tab = tab end
    end
end
--- Which top tab a QoL page is on: "qol" or "interface".
local function CategoryTab(key)
    for _, t in ipairs(CATEGORIES) do if t.key == key then return t.tab end end
    return "qol"
end
--- The menu's group of each page, for the tests: { [page key] = group name }, "General" for the pages above
--- the first group (All features).
function YR.SettingsMenuGroups()
    local out, group = {}, "General"
    for _, t in ipairs(CATEGORIES) do
        if t.group then group = t.group elseif t.key then out[t.key] = group end
    end
    return out
end
-- Older names for a page ("qol" was the one long page; the talent window had its own, the two skins and
-- the camps too).
local CATEGORY_ALIAS = { qol = "home", main = "home", start = "home", rxpskin = "skins", dmgskin = "skins", camps = "journey",
    rewards = "quests", invites = "group", waypoint = "quests", interface = "xpbar",
    talentwin = "talents", talentbuilds = "builds", death = "recap", characters = "alts" }

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
    settings.lastOn = settings.lastOn or {}
    settings.lastOn[CategoryTab(key)] = key          -- (the page each tab opens on, coming back to it)
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
    -- Quality of life's own switch - every feature on this tab on or off - on All features only, where
    -- the scope would be. (It was a row at the top of the menu; the menu was too full, 2026-10-14.)
    local master = CreateFrame("Frame", nil, page)
    master:SetSize(170, 26)
    master:SetPoint("TOPRIGHT", page, "TOPRIGHT", -20, -10)
    master.switch = S.Switch(master, function() return YR.QoLOn() end, function(on) YR.SetQoLOn(on) YR:RefreshWindow() end)
    master.switch:SetPoint("RIGHT")
    master.text = S.Text(master, 13)
    master.text:SetPoint("RIGHT", master.switch, "LEFT", -10, 0)
    master.text:SetText("Quality of life")
    master:EnableMouse(true)
    master:SetScript("OnEnter", function(self) S.Tip(self, "Turns every feature in this menu off at once. Your settings are kept and"
        .. " return when you turn it back on. Account-wide. Reload to finish. Also /headstart qol on|off.") end)
    master:SetScript("OnLeave", function() GameTooltip:Hide() end)
    master:Hide()
    ui.masters = ui.masters or {}
    ui.masters[#ui.masters + 1] = master.switch
    tourAt.qol = master
    local strip = page:CreateTexture(nil, "BORDER")
    strip:SetPoint("TOPLEFT", 16, -TITLE_H + 4)
    strip:SetPoint("TOPRIGHT", -16, -TITLE_H + 4)
    S.Hair(strip, "h")
    S.Set(strip, S.C.line)
    -- (A row of links to the page's sections stood under its description: a ledger is one short list, and the
    -- links were one more row of orange to read past - the owner, 2026-10-21.)
    return function(t)
        icon:SetTexture(t.icon)
        title:SetText(t.label)
        desc:SetText((t.key and not YR.QoLOn())
            and (t.key == "home" and "|cffffb000Quality of life is off, so none of this is running. Turn it on at the top right.|r"
                or "|cffffb000Quality of life is off, so nothing on this page is running. Turn it on at the top of All features.|r")
            or (t.desc or ""))
        local scope = type(t.scope) == "function" and t.scope() or t.scope
        scopeText:SetText(scope and ("Saved as you change it\n" .. scope) or "Saved as you change it")
        master:SetShown(t.key == "home")
        scopeText:SetShown(t.key ~= "home")
        desc:SetPoint("RIGHT", page, "RIGHT", t.key == "home" and -200 or -20, 0)     -- (clear of the switch)
    end
end

-- QoL: its menu is the window's left side on that tab (ui.sideQ); the page is what is beside it.
local function BuildSettings(page)
    settings.index = {}
    -- (what is on the Levelling tab but searched for with the settings: found here, opened there)
    settings.index[1] = { key = "builds", label = "Talent builds",
        tip = "What to take at each level, and a build followed on this character.",
        find = "talent build spec tree level points levelling follow planner", go = function() ShowTab("builds") end }
    settings.sections = {}          -- [page key] = { { title, y, area }, ... }, filled as a page is built
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
        if e.go then e.go() return end          -- (on another tab)
        ShowTab(e.key)
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
        -- what is named so comes first, then what only says it (a page's place in the menu is no rank: the
        -- minimap button's own card under a tip that mentions it on a page higher up)
        local found, said = {}, {}
        for _, e in ipairs(settings.index) do
            -- what a setting is found by is the same at every keystroke: put together once
            e.hay = e.hay or (e.label .. " " .. (e.tip or "") .. " " .. LabelOf(e.key) .. " " .. (e.find or "")):lower()
            e.name = e.name or (e.label .. " " .. (e.find or "")):lower()
            if e.name:find(text, 1, true) then found[#found + 1] = e
            elseif e.hay:find(text, 1, true) then said[#said + 1] = e end
        end
        for _, e in ipairs(said) do found[#found + 1] = e end
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
            b.where:SetText((e.where or LabelOf(e.key)) .. (e.tip and ("  ·  " .. FirstSentence(e.tip)) or ""))
            b:Show()
        end
        for i = math.min(#found, 12) + 1, #results.items do results.items[i]:Hide() end
        results:Show()
        return found
    end
    search = S.Input(nav, { width = NAV_W - 24, placeholder = "Search settings", onChange = Search })
    search:SetPoint("TOPLEFT", 12, -12)
    tourAt.search = search
    YR.SettingsSearch, YR.SettingsGo = Search, Go      -- for tests
    function YR.SettingsSearching() return results:IsShown() end
    -- A tab at the top clears it too, as a page picked in the menu does: QoL and Interface are one page, and the
    -- results stood over the other tab's pages (the review, 2026-10-21).
    function settings.ClearSearch()
        search:SetValue("")
        search:ClearFocus()
        results:Hide()
    end

    -- (Quality of life's own switch, everything on this tab on or off, was at the top of this menu; it is
    -- at the top of All features now - PageHead - and the menu is the pages alone.)
    -- The menu is the pages of the tab that shows - QoL's or Interface's - under their groups (LayNav).
    local items = {}
    for _, t in ipairs(CATEGORIES) do
        if t.group then
            local g = S.Text(nav, 11, S.C.muted)
            g:SetText(t.group:upper())
            items[#items + 1] = { tab = t.tab, label = g }
        else
            local b = CreateFrame("Button", nil, nav)
            -- (21 high, a group's name 22 with room above it)
            b:SetSize(NAV_W - 16, 21)
            items[#items + 1] = { tab = t.tab, button = b }
            b.bg = S.Fill(b, { 0, 0, 0, 0 })
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
                self.bg:SetColorTexture(unpack(on and S.C.raised or { 0, 0, 0, 0 }))
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
            tourAt["menu:" .. t.key] = b
        end
    end
    --- The menu of one tab: its groups and pages, top down; the other tab's hidden.
    settings.navBottoms = {}
    function settings.LayNav(tab)
        settings.navTab = tab
        local y = -48
        for _, it in ipairs(items) do
            local f = it.label or it.button
            f:SetShown(it.tab == tab)
            if it.tab == tab then
                f:ClearAllPoints()
                if it.label then
                    f:SetPoint("TOPLEFT", 18, y - 8)
                    y = y - 22
                else
                    f:SetPoint("TOPLEFT", 8, y)
                    y = y - 21
                end
            end
        end
        -- how far down the menu reaches (it has to end inside the window): the longer tab's
        settings.navBottoms[tab] = -y
        settings.navBottom = math.max(settings.navBottoms.qol or 0, settings.navBottoms.interface or 0)
    end
    settings.LayNav("interface")
    settings.LayNav("qol")
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
    -- The foot of the window: one button that looks like one, Arrange on screen (where every bar, button and icon of
    -- ours stands is set there and nowhere else); the rest quiet words. (Five buttons of one weight stood here, Close
    -- among them, with the window's own X above: the owner, 2026-10-21.)
    local reload = S.Button(page, "Reload UI", function() ReloadUI() end, "ghost", 90)
    reload:SetPoint("BOTTOMLEFT", 10, 14)
    reload:SetTextColour(S.C.sub)
    local arrange = S.Button(page, "Arrange on screen", function()
        if YR.ArrangeOpen() then win:Hide() end
    end, nil, 140)
    arrange:SetPoint("BOTTOMRIGHT", -16, 14)
    tourAt.arrange = arrange
    arrange.tip = "Move Headstart's bars, buttons and icons on a grid: drag them, or click one and use the arrow keys. Also /hs move"
    -- (a new install is shown around by the tour, hints over this window: Welcome.lua)
    local welcome = S.Button(page, "Tour", function() YR.WelcomeShow() end, "ghost", 70)
    welcome:SetPoint("RIGHT", arrange, "LEFT", -6, 0)     -- (pages have buttons of their own beside Reload UI)
    welcome:SetTextColour(S.C.sub)
    welcome.tip = "A quick look around this window: where everything is, a hint at a time"
    local move = S.Button(page, "Move settings", function() YR.TransferShow() end, "ghost", 110)
    move:SetPoint("RIGHT", welcome, "LEFT", -2, 0)
    move:SetTextColour(S.C.sub)
    move.tip = "Your settings, bar profiles and routes as a text, to take to another install: the live game, another computer, a friend. Also /headstart transfer"
    settings.tab = "home"
end

local function RefreshSettings()
    win.subtitle:SetText("")
    -- the tab of the page that shows (a card on All features, or the search, can lead to the other tab's)
    local tab = CategoryTab(settings.tab)
    if settings.navTab ~= tab then settings.LayNav(tab) end
    for name, b in pairs(ui.topTabs or {}) do b:Select(name == tab) end
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

-- (All routes and Talents: their own block, under Lua's two hundred names at a time in one file; their names are
-- declared above CATEGORIES)
do
-- ---------------------------------------------------------------------------
-- All routes: every route of this character's race and class (or every race's), by level, each with how far you are
-- in it and what it is to you; load it in RestedXP, or open it in the editor. Import and Share at its foot. (They were
-- a list folded by level in the menu beside the pages: the owner, 2026-10-21, "the sidebar is confusing".)
-- ---------------------------------------------------------------------------
local lib = { rows = {}, heads = {} }
local LIB_ROW, LIB_HEAD = 40, 28

-- "12-14 Loch Modan (Dwarf/Gnome)": "12-14", "Loch Modan", "Dwarf/Gnome", 12
local function RouteParts(key)
    local name = YR.GuideName(key)
    local range, zone = name:match("^(%d+%-%d+)%s+(.+)$")
    zone = (zone or name):gsub("%s*%(Launch%)", "")
    return range or "", (zone:gsub("%s*%b()", "")), zone:match("%((.-)%)"), tonumber(range and range:match("^%d+")) or 0
end

local function Hex(c) return ("%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end

local function LoadRoute(key, first)
    local ok, why = YR.LoadRouteAt(key, first)
    YR.Print(ok and ("loaded %s at step %d."):format(YR.GuideName(key), first or 1) or why)
    YR:RefreshWindow()
end

local function LibraryRow(c, w)
    local r = CreateFrame("Button", nil, c)
    r:SetSize(w, LIB_ROW)
    r.hl = S.Fill(r, S.C.hover)
    r.hl:Hide()
    r.line = r:CreateTexture(nil, "BORDER")
    r.line:SetPoint("TOPLEFT")
    r.line:SetPoint("TOPRIGHT")
    S.Hair(r.line, "h")
    S.Set(r.line, S.C.line)
    r.range = S.Text(r, 12, S.C.sub)
    r.range:SetPoint("LEFT", 14, 0)
    r.name = S.Text(r, 14)
    r.name:SetPoint("LEFT", 66, 0)
    r.name:SetPoint("RIGHT", r, "LEFT", w - 350, 0)
    r.quests = S.Text(r, 13, S.C.muted)
    r.quests:SetPoint("LEFT", w - 340, 0)
    r.state = StateLight(r)
    r.state:SetPoint("LEFT", w - 236, 0)
    r.edit = S.Button(r, "Edit", function() Open(r.key) YR:ToggleWindow("routes") end, "ghost", 44)
    r.edit:SetHeight(26)
    r.edit:SetTextColour(S.C.sub)
    r.edit:SetPoint("RIGHT", -8, 0)
    r.edit.tip = "Open it in the route editor: its steps, to change"
    r.load = S.Button(r, "Load", function() if r.first then LoadRoute(r.key, r.first) end end, nil, 56)
    r.load:SetHeight(26)
    r.load:SetPoint("RIGHT", r.edit, "LEFT", -6, 0)
    r.load.tip = "Load it in RestedXP, at the first step you haven't done"
    -- lit under the mouse, over its buttons too
    local function Leave() if not r:IsMouseOver() then r.hl:Hide() end end
    r:SetScript("OnEnter", function() r.hl:Show() end)
    r:SetScript("OnLeave", Leave)
    for _, b in ipairs({ r.edit, r.load }) do
        b:HookScript("OnEnter", function() r.hl:Show() end)
        b:HookScript("OnLeave", Leave)
    end
    return r
end

local function LibraryHead(c, w)
    local h = CreateFrame("Frame", nil, c)
    h:SetSize(w, LIB_HEAD)
    S.Fill(h, S.C.stripe)
    h.line = h:CreateTexture(nil, "BORDER")
    h.line:SetPoint("TOPLEFT")
    h.line:SetPoint("TOPRIGHT")
    S.Hair(h.line, "h")
    S.Set(h.line, S.C.line)
    h.text = S.Text(h, 11, S.C.muted)
    h.text:SetPoint("BOTTOMLEFT", 14, 6)
    return h
end

function BuildLibrary(page)
    lib.head = LevelHead(page)
    -- this character's routes, or every race's (YippRouteDB.allRoutes)
    lib.seg = Segmented(page, "Mine", "Every race", function() return not YippRouteDB.allRoutes end, function(mine)
        YippRouteDB.allRoutes = (not mine) or nil
        YR:RefreshWindow()
    end)
    lib.seg:SetPoint("RIGHT", page, "TOPRIGHT", -24, -31)
    local top = -(TITLE_H + 12)
    local h = PH - TITLE_H - 12 - 58
    local panel = CreateFrame("Frame", nil, page)
    panel:SetPoint("TOPLEFT", 16, top)
    panel:SetSize(PW - 40, h)
    Panel(panel, true)
    lib.area = S.ScrollArea(panel, PW - 42, h - 8)
    lib.area:SetPoint("TOPLEFT", 1, -4)
    lib.cw = PW - 42 - 14                       -- (its content's width: the scroll bar beside it)
    lib.none = S.Text(panel, 13, S.C.sub)
    lib.none:SetPoint("CENTER")
    lib.none:SetWidth(PW - 140)
    lib.none:SetWordWrap(true)
    lib.none:SetJustifyH("CENTER")
    lib.none:SetText("No routes yet. Play with This run recording and Save as route, or import a route someone shared.")
    -- the foot: making routes of your own, and moving them between players
    local hint = S.Text(page, 12, S.C.muted)
    hint:SetPoint("BOTTOMLEFT", 18, 24)
    hint:SetText("Your own: play with This run recording, then Save as route.")
    lib.share = S.Button(page, "Share...", function() YR:ShareOpen("export") end, nil, 120)
    lib.share:SetPoint("BOTTOMRIGHT", -24, 16)
    lib.share.tip = "The route open in the editor as text, to send to someone"
    local import = S.Button(page, "Import a route...", function() YR:ShareOpen("import") end, "ghost", 130)
    import:SetTextColour(S.C.sub)
    import:SetPoint("RIGHT", lib.share, "LEFT", -6, 0)
    import.tip = "Paste a route someone shared with you"
end

function RefreshLibrary()
    win.subtitle:SetText("")
    local race, class = UnitRace("player"), UnitClass("player")
    lib.seg.first:SetLabel(("%s %s"):format(race or "", class or ""))
    lib.seg:Refresh()
    local mine = YR.MyRoutes()
    local all = YippRouteDB.allRoutes or not next(mine)
    local list = {}
    for _, g in ipairs(YR.shipped or {}) do
        -- (the one open in the editor always: you are working on it)
        if all or mine[g.key] or g.key == edit.key then
            local range, short, qual, from = RouteParts(g.key)
            list[#list + 1] = { key = g.key, range = range, short = short, qual = qual, from = from }
        end
    end
    table.sort(list, function(a, b) if a.from ~= b.from then return a.from < b.from end return a.short < b.short end)
    lib.head:Set({ icon = 237381, title = "All routes", right = lib.seg:GetWidth() + 12,
        desc = all and ("%d routes for every race. Load one in RestedXP, or open it to change its steps."):format(#list)
            or ("%d routes for a %s %s. Load one in RestedXP, or open it to change its steps."):format(#list, race or "", class or "") })
    local best = YR.WhereNextBest and YR.WhereNextBest()
    local w = lib.cw
    local y, bracket, nr, nh = 0, nil, 0, 0
    local qualHex = Hex(S.C.muted)
    for _, e in ipairs(list) do
        local b = math.floor(e.from / 10) * 10
        if b ~= bracket then
            bracket, nh = b, nh + 1
            local hd = lib.heads[nh] or LibraryHead(lib.area.content, w)
            lib.heads[nh] = hd
            hd:ClearAllPoints()
            hd:SetPoint("TOPLEFT", 0, y)
            hd.line:SetShown(y ~= 0)
            hd.text:SetText(("LEVELS %d-%d"):format(math.max(b, 1), b + 10))
            hd:Show()
            y = y - LIB_HEAD
        end
        nr = nr + 1
        local r = lib.rows[nr] or LibraryRow(lib.area.content, w)
        lib.rows[nr] = r
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, y)
        r:Show()
        r.key = e.key
        local p = YR.RouteProgressKept and YR.RouteProgressKept(e.key) or { total = 0, done = 0, left = 0 }
        r.first = p.first
        local done = p.total > 0 and p.left == 0
        r.range:SetText(e.range)
        r.range:SetTextColor(unpack(done and S.C.muted or S.C.sub))
        r.name:SetText(e.short .. ((all and e.qual) and ("  |cff" .. qualHex .. e.qual .. "|r") or ""))
        r.name:SetTextColor(unpack(done and S.C.muted or S.C.text))
        r.quests:SetText(p.total == 0 and "" or done and ("All %d done"):format(p.total)
            or p.done > 0 and ("%d of %d done"):format(p.done, p.total) or ("%d quests"):format(p.total))
        local text, color
        if YR.RouteLoaded and YR.RouteLoaded(e.key) then text, color = "In RestedXP", S.C.green
        elseif YR:HasUpdate(e.key) then text, color = "Update waiting", S.C.accent
        elseif YR:IsCustom(e.key) then text, color = "Your version", S.C.gold
        elseif best and best.key == e.key then text, color = "Take this one", S.C.on
        elseif done then text = "Done" end
        r.state:Set(text or "", color)
        r.state.dot:SetShown(color ~= nil)
        r.load:SetEnabled(r.first ~= nil)
        r.canLoad = r.first ~= nil
        y = y - LIB_ROW
    end
    for i = nr + 1, #lib.rows do lib.rows[i]:Hide() end
    for i = nh + 1, #lib.heads do lib.heads[i]:Hide() end
    lib.area.content:SetHeight(math.max(10, -y + 4))
    if lib.area.UpdateBar then lib.area:UpdateBar() end
    lib.none:SetShown(#list == 0)
    local short = edit.key and select(2, RouteParts(edit.key))
    lib.share:SetLabel(short and ("Share " .. short .. "...") or "Share...")
    lib.share:SetWidth(math.floor(lib.share.text:GetStringWidth() + 32))
    lib.share:SetEnabled(edit.key ~= nil)
end
--- For the tests: All routes' rows as shown - { key, name, quests, state, load (it can be loaded) }.
function YR.LibraryShown()
    local out = {}
    for _, r in ipairs(lib.rows) do
        if r:IsShown() then
            out[#out + 1] = { key = r.key, name = r.name:GetText(), quests = r.quests:GetText(), state = r.state.text:GetText(), load = r.canLoad }
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Talents: Headstart's builds for a class (Talents.lua) - its three trees with each talent's points, and what to take
-- at each level beside them - and one followed on this character (the talent points notice then says what is next).
-- A card on Interface's Talents page until 2026-10-21; the talent window's own settings stay there (Talent window).
-- ---------------------------------------------------------------------------
local builds = { cells = {}, tabs = {}, rows = {} }
local CELL, CELL_GAP, TREE_GAP = 30, 8, 22     -- a talent's icon, the room between two, and between two trees
local ORDER_ROW = 26

local function BuildsOf(class) return YR.TalentBuildsOf and YR.TalentBuildsOf(class) or {} end
-- The build in view: the one picked, else the one followed (of your class), else the class's first.
local function BuildInView()
    local list = BuildsOf(builds.class)
    for _, b in ipairs(list) do if b.key == builds.key then return b end end
    local followed = builds.class == YR.TalentClassID() and YR.TalentFollowed and YR.TalentFollowed()
    builds.key = followed and followed.key or (list[1] and list[1].key)
    for _, b in ipairs(list) do if b.key == builds.key then return b end end
    return nil
end

function BuildBuilds(page)
    builds.class = YR.TalentClassID and YR.TalentClassID() or 1
    local top = -12             -- (under QoL's heading: the page is the frame beneath it)
    local classOpts = {}
    for _, o in ipairs(TALENT_CLASSES) do classOpts[#classOpts + 1] = { o[1], o[2] } end
    builds.classes = S.Dropdown(page, 140, classOpts, function(v) builds.class, builds.key = v, nil YR:RefreshWindow() end)
    builds.classes:SetPoint("TOPLEFT", 16, top - 3)
    local function Pick(v)
        builds.key = v
        -- (a build picked while one of your class is followed: that one is followed from now on)
        if builds.class == YR.TalentClassID() and YR.TalentFollowed and YR.TalentFollowed() then YR.TalentFollow(v) end
        YR:RefreshWindow()
    end
    builds.pick = S.Dropdown(page, 290, {}, Pick)
    builds.pick:SetPoint("LEFT", builds.classes, "RIGHT", 8, 0)
    -- (its list is made again as it opens, for the class shown)
    builds.pick:SetScript("OnClick", function(self)
        local opts = {}
        for _, b in ipairs(BuildsOf(builds.class)) do opts[#opts + 1] = { b.key, b.name } end
        S.OpenMenu(self, opts, Pick, 290)
    end)
    builds.follow = S.Switch(page, function() return YR.TalentFollowed and YR.TalentFollowed() ~= nil end, function(on)
        if not on then YR.TalentFollow(nil) YR:RefreshWindow() return end
        -- the build in view when it is your class's, else your class's first
        local own = YR.TalentClassID()
        local key = builds.class == own and builds.key or (BuildsOf(own)[1] and BuildsOf(own)[1].key)
        if key then YR.TalentFollow(key) end
        YR:RefreshWindow()
    end)
    builds.follow:SetPoint("TOPRIGHT", -24, top - 5)
    builds.followText = CreateFrame("Button", nil, page)
    builds.followText.text = S.Text(builds.followText, 13)
    builds.followText.text:SetPoint("RIGHT")
    builds.followText.text:SetText("Follow it on this character")
    builds.followText:SetSize(builds.followText.text:GetStringWidth() + 4, 20)
    builds.followText:SetPoint("RIGHT", builds.follow, "LEFT", -10, 0)
    builds.followText:SetScript("OnClick", function() builds.follow:Click() end)
    builds.followText:SetScript("OnEnter", function(self) S.Tip(self, "This character follows the build in view (of your own"
        .. " class): the talent points notice says which talent it takes next, and its tooltip the next ones. Pick another"
        .. " build and that one is followed.") end)
    builds.followText:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- the three trees
    local panelTop = top - 30 - 12
    local h = CH + panelTop - 56                -- (clear of the foot's buttons)
    local col = CELL + CELL_GAP
    local treeW = 4 * col - CELL_GAP
    local trees = CreateFrame("Frame", nil, page)
    trees:SetPoint("TOPLEFT", 16, panelTop)
    trees:SetSize(3 * treeW + 2 * TREE_GAP + 32, h)
    Panel(trees, true)
    for t = 1, 3 do
        local x = 16 + (t - 1) * (treeW + TREE_GAP)
        builds.tabs[t] = S.Text(trees, 14)
        builds.tabs[t]:SetPoint("TOPLEFT", x, -14)
        for row = 1, 7 do
            for c4 = 1, 4 do
                local b = CreateFrame("Button", nil, trees)
                b:SetSize(CELL, CELL)
                b:SetPoint("TOPLEFT", x + (c4 - 1) * col, -40 - (row - 1) * col)
                b.icon = b:CreateTexture(nil, "ARTWORK")
                b.icon:SetAllPoints()
                b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b.edge = S.Border(b, S.C.line)
                b.rank = S.Text(b, 11, S.C.text)
                b.rank:SetFont(S.FONT, 11, "OUTLINE")
                b.rank:SetPoint("BOTTOMRIGHT", 4, -4)
                b:SetScript("OnEnter", function(self)
                    if not self.spell then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(self.spell) end
                    if self.levels and #self.levels > 0 then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("This build: level " .. table.concat(self.levels, ", "), 1, 0.82, 0)
                    end
                    if self.mine then GameTooltip:AddLine(("You have %d of %d"):format(self.mine, self.max), 0.6, 0.9, 0.6) end
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                b:Hide()
                builds.cells[t .. ":" .. row .. ":" .. c4] = b
            end
        end
    end
    -- what the edges say: taken (yours), in the build
    local function Legend(x, color, label)
        local sq = CreateFrame("Frame", nil, trees)
        sq:SetSize(11, 11)
        sq:SetPoint("BOTTOMLEFT", x, 18)
        S.Fill(sq, S.C.field)
        S.Border(sq, color)
        local t = S.Text(trees, 12, S.C.muted)
        t:SetPoint("LEFT", sq, "RIGHT", 7, 0)
        t:SetText(label)
        return x + 18 + t:GetStringWidth() + 18
    end
    Legend(Legend(16, S.C.boxOn, "Taken"), S.C.boxLine, "In this build")
    -- (what follows a build says it in the talent points notice: its settings are QoL's, Reminders)
    local notice = S.Button(trees, "Talent points notice settings", function() YR:ShowSettingsTab("reminders") end, "ghost", 190)
    notice:SetTextColour(S.C.sub)
    notice:SetHeight(24)
    notice:SetPoint("BOTTOMRIGHT", -10, 10)
    notice.tip = "How the notice tells you of points to spend, and which talent is next: QoL, Reminders"
    builds.none = S.Text(trees, 13, S.C.sub)
    builds.none:SetPoint("CENTER")
    builds.none:SetText("No talent trees for this class yet.")

    -- the order, by level, beside them
    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", trees, "TOPRIGHT", 12, 0)
    list:SetPoint("TOPRIGHT", page, "TOPRIGHT", -24, panelTop)
    list:SetHeight(h)
    Panel(list)
    local cap = S.Text(list, 11, S.C.muted)
    cap:SetPoint("TOPLEFT", 14, -14)
    cap:SetText("BY LEVEL")
    local listW = PW - 40 - (3 * treeW + 2 * TREE_GAP + 32) - 12
    builds.area = S.ScrollArea(list, listW - 2, h - 40)
    builds.area:SetPoint("TOPLEFT", 1, -34)
    builds.cw = listW - 2 - 14
end

local function OrderRow(c, w)
    local r = CreateFrame("Frame", nil, c)
    r:SetSize(w, ORDER_ROW)
    r.bg = S.Fill(r, { 0, 0, 0, 0 })
    r.lvl = S.Text(r, 12, S.C.muted)
    r.lvl:SetPoint("LEFT", 14, 0)
    r.name = S.Text(r, 13, S.C.sub)
    r.name:SetPoint("LEFT", 58, 0)
    r.name:SetPoint("RIGHT", -40, 0)
    r.rank = S.Text(r, 12, S.C.muted)
    r.rank:SetPoint("RIGHT", -12, 0)
    return r
end

function RefreshBuilds()
    win.subtitle:SetText("")
    local class = builds.class
    local build = BuildInView()
    for _, o in ipairs(TALENT_CLASSES) do if o[1] == class then builds.classes:SetValue(o[2]) end end
    builds.pick:SetValue(build and build.name or "No builds for this class yet")
    builds.follow:Refresh()
    local tree = YR.TalentTrees and YR.TalentTrees[class]
    for _, b in pairs(builds.cells) do b:Hide() end
    for t = 1, 3 do builds.tabs[t]:SetText("") end
    builds.none:SetShown(tree == nil)
    for _, r in ipairs(builds.rows) do r:Hide() end
    if not tree then return end
    local want, levels, spent = {}, {}, { 0, 0, 0 }
    for i, node in ipairs(build and build.points or {}) do
        want[node] = (want[node] or 0) + 1
        levels[node] = levels[node] or {}
        levels[node][#levels[node] + 1] = 9 + i
        spent[tree.nodes[node][3]] = spent[tree.nodes[node][3]] + 1
    end
    local mine = class == YR.TalentClassID() and YR.TalentRanksNow() or nil
    for t = 1, 3 do
        builds.tabs[t]:SetText(("%s  |cff%s%d|r"):format(tree.tabs[t], Hex(S.C.muted), spent[t]))
        builds.tabs[t]:SetTextColor(unpack(spent[t] > 0 and S.C.text or S.C.muted))
    end
    for node, n in pairs(tree.nodes) do
        local b = builds.cells[n[3] .. ":" .. n[4] .. ":" .. n[5]]
        if b then
            local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(n[1])
            b.icon:SetTexture(tex or 134400)
            local got, have = want[node] or 0, mine and mine[node] or 0
            b.icon:SetDesaturated(got == 0 and have == 0)
            b.icon:SetAlpha((got == 0 and have == 0) and 0.4 or 1)
            b.rank:SetText(have > 0 and (have .. "/" .. n[2]) or got > 0 and (got .. "/" .. n[2]) or "")
            b.rank:SetTextColor(unpack(have > 0 and S.C.text or S.C.sub))
            b.edge:Color(have > 0 and S.C.boxOn or got > 0 and S.C.boxLine or S.C.line)
            b.spell, b.levels, b.max = n[1], levels[node], n[2]
            b.mine = mine and mine[node] or nil
            b:Show()
        end
    end
    -- the order: runs of points in one talent, as levels; the next one to take lit (your own class)
    local runs, run, count = {}, nil, {}
    for i, node in ipairs(build and build.points or {}) do
        count[node] = (count[node] or 0) + 1
        if run and run.node == node and run.to == 8 + i then
            run.to, run.rank = 9 + i, count[node]
        else
            run = { node = node, from = 9 + i, to = 9 + i, rank = count[node] }
            runs[#runs + 1] = run
        end
    end
    local w = builds.cw
    local lit = false
    builds.lit = nil
    for i, ru in ipairs(runs) do
        local r = builds.rows[i] or OrderRow(builds.area.content, w)
        builds.rows[i] = r
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, -(i - 1) * ORDER_ROW)
        r:Show()
        local have = mine and (mine[ru.node] or 0)
        local nextOne = have and not lit and have < ru.rank
        if nextOne then lit, builds.lit = true, i end
        local name = YR.TalentNodeName(class, ru.node)
        r.lvl:SetText(ru.from == ru.to and tostring(ru.from) or (ru.from .. "-" .. ru.to))
        r.name:SetText(name .. ((nextOne and have > 0) and ("  (%d of %d taken)"):format(have, ru.rank) or ""))
        r.name:SetTextColor(unpack(nextOne and S.C.text or S.C.sub))
        r.rank:SetText(("%d/%d"):format(ru.rank, tree.nodes[ru.node][2]))
        r.rank:SetTextColor(unpack(nextOne and S.C.text or S.C.muted))
        r.bg:SetColorTexture(unpack(nextOne and S.C.raised or { 0, 0, 0, 0 }))
    end
    builds.area.content:SetHeight(math.max(10, #runs * ORDER_ROW + 4))
    if builds.area.UpdateBar then builds.area:UpdateBar() end
end
--- For the tests: the Talents page as shown - { class, key, cells (talents drawn), rows (lines of the order), follow }.
function YR.BuildsShown()
    local cells, rows = 0, 0
    for _, b in pairs(builds.cells) do if b:IsShown() then cells = cells + 1 end end
    for _, r in ipairs(builds.rows) do if r:IsShown() then rows = rows + 1 end end
    return { class = builds.class, key = builds.key, cells = cells, rows = rows, follow = builds.follow, lit = builds.lit }
end

end

-- ---------------------------------------------------------------------------
-- Route settings: a Levelling page, under a heading like QoL's pages
-- ---------------------------------------------------------------------------
local ROUTE_PAGE = { icon = 134063, label = "Route settings", scope = "Every character on this account",
    desc = "Routes, group play, run recording and level splits." }

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
    routesOff = OffCard(page, { icon = "Interface\\Icons\\INV_Misc_Map_01", title = "Routes",
        text = "Records your runs and saves them as your own RestedXP routes. Includes a route editor, level"
            .. " splits, and help keeping and buying the items a route needs.\n\nWhile off, none of it runs and"
            .. " nothing is shown. Account-wide. Takes a /reload.",
        get = function() return YR.RoutesOn() end, set = YR.SetRoutesOn,
        state = function() return YR.RoutesOn() and "On - reload to load the routes" or "Off" end,
        reload = function() return YR.RoutesOn() ~= routesWere end })
end

-- Character setup: its own tab. On: the page. Off (or its addon not there): only the switch.
local SETUP_PAGE = { icon = 134166, label = "Character setup",
    scope = function() return "Bars: every " .. (CLASS_NAME[ViewClass()] or "character") .. "'s own. Interface: every character's" end,
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
    if setup.nav then setup.nav:SetShown(on) end
    setupTab.off:SetShown(not on)
    setupTab.off:Refresh()
    if on then
        -- this character's bars and macros kept for good, the first time Character setup is looked at here
        if YR.Setup and YR.Setup.KeepFirst then YR.Setup.KeepFirst() end
        RefreshSetup()
    end
end

-- ---------------------------------------------------------------------------
-- The window: four tabs at the top - QoL, Interface, Levelling, Character setup - each with its own menu down the left
-- ---------------------------------------------------------------------------
-- tab: which top tab a page is under ("settings" is QoL's and Interface's, as the page showing on it is: TabOf).
-- nav: in Levelling's menu (true: top down; "foot": at its foot); under: the menu's page it belongs to (the editor and
-- Share: All routes'); routes: the routes' own - while they are off, the page that switches them on in its place.
local PAGES = {
    { key = "where", tab = "levelling", nav = true, routes = true, label = "Next route", icon = 132181,
      build = function(page)
          YR.BuildWherePage(page, { head = LevelHead, panel = Panel, light = StateLight, clock = Clock, width = PW, top = TITLE_H,
              steps = function(key) Open(key) YR:ToggleWindow("routes") end })
      end, refresh = function() win.subtitle:SetText("") YR.RefreshWherePage() end },
    { key = "library", tab = "levelling", nav = true, routes = true, label = "All routes", icon = 237381,
      build = BuildLibrary, refresh = RefreshLibrary },
    { key = "run", tab = "levelling", nav = true, routes = true, label = "This run", icon = 134376, build = BuildRun, refresh = RefreshRun },
    -- (the menu says Settings: under the Levelling tab it can be no other's - the owner, 2026-10-15; the page's
    -- heading still says Route settings)
    { key = "route", tab = "levelling", nav = "foot", routes = true, label = "Settings", icon = 134063, build = BuildRoutePage,
      refresh = RefreshRoutePage },
    { key = "routes", tab = "levelling", under = "library", routes = true, build = BuildRoutes, refresh = RefreshRoutes },
    { key = "share", tab = "levelling", under = "library", routes = true, build = BuildShare, refresh = RefreshShare },
    { key = "routesoff", tab = "levelling", build = BuildRoutesOff, refresh = function() win.subtitle:SetText("") routesOff:Refresh() end },
    { key = "settings", tab = "qol", build = BuildSettings, refresh = RefreshSettings },
    { key = "setup", tab = "setup", build = BuildSetupPage, refresh = RefreshSetupPage },
}
local PAGE_TAB, PAGE_BY = {}, {}
for _, p in ipairs(PAGES) do PAGE_TAB[p.key], PAGE_BY[p.key] = p.tab, p end
local lastLevelling          -- the Levelling page last shown, for coming back to that tab
local function TabOf(key)
    if key == "settings" then return CategoryTab(settings.tab) end
    return PAGE_TAB[key]
end
function YR.WindowTab() return TabOf(current) end      -- for the tests
function YR.WindowPage() return current end
--- Whether the window is up on this page (a Levelling one, or a QoL or Interface page by its key).
function YR.WindowShowing(key)
    return (win and win:IsShown() and (current == key or (current == "settings" and settings.tab == key))) and true or false
end

local function Show(key)
    if key == "character" then key = "setup" end        -- its name while it was a QoL page
    if not PAGE_TAB[key] then           -- a QoL page by its own name ("instances", "camps", ...)
        ShowTab(key, true)
        key = "settings"
    end
    local p = PAGE_BY[key]
    local navKey = p.under or key       -- lit in the menu: the page, or the one it is under
    if p.tab == "levelling" and key ~= "routesoff" then lastLevelling = key end
    -- the routes' own pages, with the routes off: the page that switches them on (Talents is everyone's)
    if p.routes and not YR.RoutesOn() then key = "routesoff" end
    current = key
    local tab = TabOf(key)
    S.CloseMenu()
    ui.sideL:SetShown(tab == "levelling")
    ui.sideQ:SetShown(tab == "qol" or tab == "interface")
    ui.sideS:SetShown(tab == "setup")
    for name, b in pairs(ui.topTabs) do b:Select(name == tab) end
    for _, q in ipairs(PAGES) do
        -- a page is made the first time it is shown (the route editor and QoL with the window)
        if q.key == key and not q.built then
            q.built = true
            q.build(pages[q.key])
        end
        pages[q.key]:SetShown(q.key == key)
        if q.button then q.button:Select(q.key == navKey) end
    end
    YR:RefreshWindow()
end

-- Open QoL on one of its pages ("camps", "bags", ..., "character", "trainer"), or Route settings ("route").
function YR:ShowSettingsTab(key)
    settings.viewClass = nil          -- this character's class
    if key == "route" or key == "setup" or key == "character" then YR:ToggleWindow(key) return end
    YR:ToggleWindow(CATEGORY_ALIAS[key] or key or "settings")
end

-- The tabs: one switch in the middle of the title bar, the part that's showing filled in. Each part has its icon
-- and name; another lights up under the mouse.
local SEG_W, SEG_H = 128, 28
-- A tab: its icon and name, and under the one you are on a line of the accent (it was the whole tab filled with it:
-- the owner, 2026-10-21, "too much orange"; the icons stay: "I don't like that you removed the icons").
local function Segment(parent, label, icon)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SEG_W, SEG_H)
    b.text = S.Text(b, 14, S.C.sub)
    b.text:SetPoint("CENTER", 11, 0)
    b.text:SetText(label)
    b.icon = S.Icon(b, icon, 16)
    b.icon:SetPoint("RIGHT", b.text, "LEFT", -7, 0)
    b.line = b:CreateTexture(nil, "ARTWORK")
    b.line:SetHeight(2)
    b.line:SetPoint("TOPLEFT", b.icon, "BOTTOMLEFT", 0, -6)
    b.line:SetPoint("TOPRIGHT", b.text, "BOTTOMRIGHT", 2, -6)
    S.Set(b.line, S.C.accent)
    local function Paint(self, over)
        local on = self.selected
        self.line:SetShown(on and true or false)
        self.text:SetTextColor(unpack((on or over) and S.C.text or S.C.sub))
        self.icon:SetDesaturated(not on)
        self.icon:SetAlpha((on or over) and 1 or 0.7)
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

-- All four in their track, centred in the title bar (head). Returns { qol = , interface = , levelling = , setup = }.
local function TopTabs(head, onLevelling, onQoL, onSetup, onInterface)
    local track = CreateFrame("Frame", nil, head)
    track:SetSize(SEG_W * 4 + 6, SEG_H + 6)
    track:SetPoint("CENTER", head, "CENTER", 0, 0)
    track:SetFrameLevel(head:GetFrameLevel() + 2)      -- over the bar you drag the window by
    local qol = Segment(track, "QoL", "Interface\\Icons\\Trade_Engineering")
    qol:SetPoint("LEFT", 3, 0)
    qol:SetScript("OnClick", onQoL)
    local interface = Segment(track, "Interface", 134063)
    interface:SetPoint("LEFT", qol, "RIGHT", 0, 0)
    interface:SetScript("OnClick", onInterface)
    -- (called Levelling until 2026-10-21: with Talents on QoL it is the routes alone, and QoL has a Levelling group -
    -- "yes, call it Routes", the owner. Its key is still "levelling".)
    local levelling = Segment(track, "Routes", "Interface\\Icons\\INV_Misc_Map_01")
    levelling:SetPoint("LEFT", interface, "RIGHT", 0, 0)
    levelling:SetScript("OnClick", onLevelling)
    local setupSeg = Segment(track, "Character setup", 134166)
    setupSeg:SetPoint("RIGHT", -3, 0)
    setupSeg:SetScript("OnClick", onSetup)
    return { levelling = levelling, qol = qol, interface = interface, setup = setupSeg }, track
end

local function NavButton(parent, label, icon)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SIDE - 16, 32)
    b.bg = S.Fill(b, { 0, 0, 0, 0 })
    b.icon = S.Icon(b, icon, 18)
    b.icon:SetPoint("LEFT", 10, 0)
    b.text = S.Text(b, 14, S.C.sub)
    b.text:SetPoint("LEFT", 38, 0)
    b.text:SetPoint("RIGHT", -22, 0)
    b.text:SetText(label)
    -- (This run's: green while the run is recorded)
    b.dot = b:CreateTexture(nil, "OVERLAY")
    b.dot:SetSize(7, 7)
    b.dot:SetPoint("RIGHT", -10, 0)
    S.ArtTexture(b.dot, "dot")
    b.dot:SetVertexColor(unpack(S.C.green))
    b.dot:Hide()
    function b:Select(on)
        self.selected = on
        self.bg:SetColorTexture(unpack(on and S.C.raised or { 0, 0, 0, 0 }))
        self.text:SetTextColor(unpack(on and S.C.text or S.C.sub))
        self.icon:SetDesaturated(not on)
        self.icon:SetAlpha(on and 1 or 0.8)
    end
    b:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(unpack(S.C.hover)) end end)
    b:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end end)
    b:Select(false)
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

local function Build()
    win = S.Window("HeadstartWindow", W, H, "Headstart")
    -- The tabs in the middle of the title bar; what a page says about itself (win.subtitle) stays
    -- after the title, cut short where the tabs begin.
    local track
    local function Tab(go) return function() if settings.ClearSearch then settings.ClearSearch() end go() end end
    ui.topTabs, track = TopTabs(win.title:GetParent(),
        Tab(function() Show(lastLevelling or "where") end),
        Tab(function() Show(settings.lastOn and settings.lastOn.qol or "home") end), Tab(function() Show("setup") end),
        Tab(function() Show(settings.lastOn and settings.lastOn.interface or "xpbar") end))
    win.subtitle:SetPoint("RIGHT", track, "LEFT", -16, 0)
    tourAt.setup, tourAt.levelling, tourAt.interface = ui.topTabs.setup, ui.topTabs.levelling, ui.topTabs.interface
    win.subtitle:SetJustifyH("LEFT")
    win.subtitle:SetWordWrap(false)
    -- One menu down the left per tab: Levelling's (SIDE wide), QoL's and Interface's (one, NAV_W wide: BuildSettings
    -- fills it with the tab's pages), Character setup's.
    local function Side(width, color)
        local f = CreateFrame("Frame", nil, win)
        f:SetPoint("TOPLEFT", 1, -HEAD)
        f:SetPoint("BOTTOMLEFT", 1, 1)
        f:SetWidth(width)
        S.Fill(f, color)
        local rule = f:CreateTexture(nil, "BORDER")
        rule:SetPoint("TOPRIGHT") rule:SetPoint("BOTTOMRIGHT") S.Hair(rule, "v")
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
    -- (Whose each thing is - bars each class's, the interface everyone's - stood under the menu here as three entries
    -- with icons, which read as more settings (the owner, 2026-10-20: "a bit confusing that all of these are settings").
    -- It is said in the page's own corner now, where every page says whose its settings are: SETUP_PAGE's scope.)
    pages = {}
    -- Levelling's menu: its four pages top down, and Settings at its foot (the routes' switch is that page's first
    -- row). The routes are on All routes: the menu was the switch, the pages and a list of routes folded by level
    -- (the owner, 2026-10-21: "the sidebar is confusing, with so much in it").
    local y = -12
    for _, p in ipairs(PAGES) do
        if p.nav then
            p.button = NavButton(side, p.label, p.icon)
            p.button:SetScript("OnClick", function() Show(p.key) end)
            if p.nav == "foot" then
                p.button:SetPoint("BOTTOMLEFT", 8, 12)
                local rule = side:CreateTexture(nil, "BORDER")
                rule:SetPoint("BOTTOMLEFT", 12, 52)
                rule:SetPoint("BOTTOMRIGHT", -12, 52)
                S.Hair(rule, "h")
                S.Set(rule, S.C.line)
            else
                p.button:SetPoint("TOPLEFT", 8, y)
                y = y - 34
            end
            tourAt["levelling:" .. p.key] = p.button
        end
    end
    ui.runDot = PAGE_BY.run.button.dot
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
    if key then Open(key) end
end

function YR:RefreshWindow()
    if not (win and win:IsShown()) then return end
    for _, sw in ipairs(ui.masters or {}) do sw:Refresh() end
    if ui.runDot then ui.runDot:SetShown(YR.Option("logging") and not (YR.RunStopped and YR:RunStopped())) end
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
