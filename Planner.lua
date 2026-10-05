-- Bar planner: build your action bars for the whole class on a level-1 character. Every spell your class
-- will ever have, at any level, can be dragged onto your bars; nothing has to be learned first. Saved, it
-- IS the class's layout (YippSetupDB.classes[CLASS].profile, marked planned), and Set up layout uses it
-- like one copied from a main: known spells go on the bar, the rest go into their slot the moment they
-- are learned (or wait as question-mark macros).
--
--   On my bars (the default): the plan is drawn over your real action buttons, where Edit Mode put them,
--   so you see it exactly as you'll play it. It's a picture laid on top - the real buttons are untouched
--   until you Apply - and it goes when the planner closes or a fight starts. Which bars show, and where,
--   is the game's own setup (settings and Edit Mode): set up the UI first, then plan on it.
--   As a grid: all eight bars as rows, for bars you haven't switched on or a bar addon's own buttons.
--
--   Forms: a class whose forms swap the main bar (Stealth; Cat and Bear; the three stances - read from
--   the game's spellshapeshiftform.BonusActionBar) gets a "Bar 1" choice: each form's bar is its own
--   set of slots (72 + (bar - 1) * 12 + 1..12), planned like any other.
--
--   The list, in three tabs:
--     Spells       class spells you can put on a bar (passives left out), Attack and the weapon spells
--                  your class can have (Throw, Shoot ...), and your race's active racials
--     Professions  what a profession puts in the spellbook to cast: Mining, Find Minerals, Smelting,
--                  Cooking, Basic Campfire, Disenchant ... (placed once you've learned it)
--     Macros       this character's and the account's macros, and a button to open the macro window and
--                  make more (a stealth or shapeshift macro, say)
--
--   Drag from the list onto a button, or click and then click a button. Drag a button to move or swap
--   it, drop it off the bars to take it off, right-click to empty it. Right-click or Escape drops what
--   you're carrying.
--   Downranking: the mouse wheel over a placed spell steps its rank down (and back up to "highest"),
--   and Shift-click lists every rank. A button kept at a rank shows it (R3) and is saved the way a
--   copied main saves one (id = that rank, down = true).
-- The icons come from the game's data (Data/PlannerSpells.lua), so spells you don't know yet have one.
local ADDON, YR = ...
local YS = YR.Setup
local S = YR.Style

local SLOT, GAP, ROW_H, LIST_W, LIST_ROW = 36, 4, 44, 300, 28
-- The eight bars: the action slots behind each, Blizzard's buttons for them (ActionButtonUtil's names on
-- this client) and the key binding behind each button (commandNamePrefix in MultiActionBars.xml - note
-- Right is 3 and Left is 4). The slot is fixed per bar here, the same numbers Copy and Set up use.
local BARS = {
    { "Bar 1", 1, "ActionButton", "ACTIONBUTTON" },
    { "Bar 2", 61, "MultiBarBottomLeftButton", "MULTIACTIONBAR1BUTTON" },
    { "Bar 3", 49, "MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON" },
    { "Bar 4", 25, "MultiBarRightButton", "MULTIACTIONBAR3BUTTON" },
    { "Bar 5", 37, "MultiBarLeftButton", "MULTIACTIONBAR4BUTTON" },
    { "Bar 6", 145, "MultiBar5Button", "MULTIACTIONBAR5BUTTON" },
    { "Bar 7", 157, "MultiBar6Button", "MULTIACTIONBAR6BUTTON" },
    { "Bar 8", 169, "MultiBar7Button", "MULTIACTIONBAR7BUTTON" },
}
local LIST_ONLY_W = 16 + LIST_W + 16
local GRID_W = 16 + LIST_W + 20 + 86 + 12 * (SLOT + GAP) + 16
local WIN_H = 760

local win, plan, carry, cursor, menu
local slots, overlays, rows = {}, {}, {}
local filter = ""
local mode = "bars"                -- "bars" | "grid"
local listKind = "spells"          -- "spells" | "professions" | "macros"
local formBar = 0                  -- 0: bar 1 as normal; else the bonus bar of the form being planned
local reopenMain = false

local function Class() local _, c = UnitClass("player") return c or "WARRIOR" end

local function RaceBit()
    local _, _, id = UnitRace("player")
    return id and bit.lshift(1, id - 1) or 0
end

--- The forms whose bar can be planned: { { name, bar } }, empty for a class without.
function YR.PlannerForms_()
    return (YR.PlannerForms or {})[Class()] or {}
end

--- The first slot of a bar, bar 1 following the form being planned.
local function BarBase(bi)
    if bi == 1 and formBar > 0 then return 72 + (formBar - 1) * 12 + 1 end
    return BARS[bi][2]
end

-- ---------------------------------------------------------------------------
-- What can go on a bar
-- ---------------------------------------------------------------------------
--- The spells to offer: { { name, level, icon, id, racial, general } } by level then name.
function YR.PlannerList()
    local class, out = Class(), {}
    local data = (YR.PlannerSpells or {})[class] or {}
    local levels = (YS.SPELL_LEVELS or {})[class] or {}
    for name, d in pairs(data) do
        if d[3] == 0 and levels[name] then
            out[#out + 1] = { name = name, level = levels[name], icon = d[2], id = d[1] }
        end
    end
    for name, d in pairs((YR.PlannerGeneral or {})[class] or {}) do
        if not data[name] then out[#out + 1] = { name = name, level = 1, icon = d[2], id = d[1], general = true } end
    end
    local race = RaceBit()
    for name, d in pairs(YR.PlannerRacials or {}) do
        if d[3] == 0 and (d[4] == 0 or bit.band(d[4], race) ~= 0) then
            out[#out + 1] = { name = name, level = 1, icon = d[2], id = d[1], racial = true }
        end
    end
    table.sort(out, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.name < b.name
    end)
    return out
end

--- The professions' own spells: { { name, id, icon, profession, prof = true } }, by profession.
function YR.PlannerProfessionList()
    local out = {}
    for _, p in ipairs(YR.PlannerProfessions or {}) do
        out[#out + 1] = { name = p[1], id = p[2], icon = p[3], profession = p[4], prof = true }
    end
    return out
end

--- This character's and the account's macros: { { name, icon, body, account } }.
function YR.PlannerMacros()
    local out = {}
    if not (GetNumMacros and GetMacroInfo) then return out end
    local account, perChar = GetNumMacros()
    local ACCOUNT = MAX_ACCOUNT_MACROS or 120
    local function Add(i, isAccount)
        local name, icon, body = GetMacroInfo(i)
        if name then out[#out + 1] = { name = name, icon = icon, body = body, account = isAccount, macro = true } end
    end
    for i = 1, account or 0 do Add(i, true) end
    for i = ACCOUNT + 1, ACCOUNT + (perChar or 0) do Add(i, false) end
    return out
end

--- The icon for anything a layout can hold.
local function IconOf(e)
    if not e then return nil end
    if e.kind == "spell" then
        if e.prof and e.icon then return e.icon end
        local class = Class()
        local d = ((YR.PlannerSpells or {})[class] or {})[e.name] or ((YR.PlannerGeneral or {})[class] or {})[e.name]
            or (YR.PlannerRacials or {})[e.name]
        if d then return d[2] end
        return e.icon or (C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(e.id or e.name)) or 134400
    elseif e.kind == "macro" then
        return e.icon or 134400
    elseif e.kind == "item" then
        return (C_Item.GetItemIconByID and C_Item.GetItemIconByID(e.id)) or 134400
    end
    return 134400
end

--- What a list line puts on a bar: the same shape a copied main's button has. A profession spell keeps
--- its ID and icon, which is how Set up layout finds the right one of several same-named spells.
local function Entry(s)
    if s.macro then return { kind = "macro", name = s.name, icon = s.icon, body = s.body } end
    if s.prof then return { kind = "spell", name = s.name, prof = true, id = s.id, icon = s.icon } end
    return { kind = "spell", name = s.name, level = s.level, racial = s.racial or nil, general = s.general or nil }
end

-- ---------------------------------------------------------------------------
-- Ranks
-- ---------------------------------------------------------------------------
--- Every rank of a class spell: { { rank, id, level } } from rank 1 up, or an empty list for a spell
--- without ranks. Rank 2 and up come from the trainer data; rank 1 of a talent spell (which no trainer
--- teaches) from the planner data, which holds every spell's lowest rank.
function YR.PlannerRanks(name)
    local class, out, seen = Class(), {}, {}
    for _, e in ipairs((YR.TrainerSpells or {})[class] or {}) do
        if e[3] == name and e[4] > 0 and not seen[e[4]] then
            seen[e[4]] = true
            out[#out + 1] = { rank = e[4], id = e[1], level = e[2] }
        end
    end
    if #out == 0 then return out end
    if not seen[1] then
        local d = ((YR.PlannerSpells or {})[class] or {})[name]
        local lvl = ((YS.SPELL_LEVELS or {})[class] or {})[name]
        if d then out[#out + 1] = { rank = 1, id = d[1], level = lvl or 1 } end
    end
    table.sort(out, function(a, b) return a.rank < b.rank end)
    return out
end

--- The rank a button is kept at, or nil for "the highest you know".
local function RankOf(e)
    if not (e and e.kind == "spell" and e.down and e.id) then return nil end
    for _, r in ipairs(YR.PlannerRanks(e.name)) do
        if r.id == e.id then return r end
    end
end

--- Keep a button at this rank (a number), or back to the highest you know (nil).
local function SetRank(e, rank)
    e.id, e.down, e.rank = nil, nil, nil
    if not rank then return end
    local ranks = YR.PlannerRanks(e.name)
    -- the top rank IS "highest": pinning it would only stop a rank the game adds later
    if rank >= #ranks then return end
    for _, r in ipairs(ranks) do
        if r.rank == rank then e.id, e.down, e.rank = r.id, true, r.rank return end
    end
end

--- One step down (delta -1) or up (+1) from where the button is; up to the top rank is "highest".
local function StepRank(e, delta)
    if e.prof then return false end
    local ranks = YR.PlannerRanks(e.name)
    if #ranks < 2 then return false end
    local cur = RankOf(e)
    local now = cur and cur.rank or #ranks
    local want = math.max(1, math.min(#ranks, now + delta))
    SetRank(e, want < #ranks and want or nil)
    return true
end

-- ---------------------------------------------------------------------------
-- Carrying
-- ---------------------------------------------------------------------------
local Paint

local function Drop()
    carry = nil
    if cursor then cursor:Hide() end
end

local function Carry(e)
    carry = e
    if not cursor then
        cursor = CreateFrame("Frame", nil, UIParent)
        cursor:SetSize(SLOT, SLOT)
        cursor:SetFrameStrata("TOOLTIP")
        cursor.icon = cursor:CreateTexture(nil, "OVERLAY")
        cursor.icon:SetAllPoints()
        cursor:SetScript("OnUpdate", function(self)
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale + 14, y / scale - 14)
        end)
    end
    cursor.icon:SetTexture(IconOf(e))
    cursor:Show()
end

local function SlotUnderMouse()
    for _, b in ipairs(slots) do
        if b:IsVisible() and b:IsMouseOver() then return b end
    end
end

--- Put what you carry on this button. What was there comes along on the cursor, so two buttons swap
--- in two clicks; dragged from another button, the two swap at once.
local function PlaceIn(b)
    if not carry then return end
    local e, fromSlot = carry, carry.from
    e.from = nil
    local was = plan[b.slot]
    plan[b.slot] = e
    if was and fromSlot then
        plan[fromSlot] = was
        Drop()
    elseif was then
        Carry(was)
    else
        Drop()
    end
    Paint()
end

-- ---------------------------------------------------------------------------
-- A button: the same one in the grid and laid over a real action button
-- ---------------------------------------------------------------------------
-- Key names the game writes in full: shortened the way players write them, so they fit on a button.
local KEY_SHORT = {
    { "Mouse Button (%d+)", "M%1" }, { "Middle Mouse", "M3" }, { "Mouse Wheel Up", "MwU" },
    { "Mouse Wheel Down", "MwD" }, { "Num Pad ", "N" }, { "Spacebar", "Spc" }, { "Backspace", "Bs" },
    { "Page Up", "PU" }, { "Page Down", "PD" }, { "Insert", "Ins" }, { "Delete", "Del" },
}
function YR.PlannerShortKey(t)
    if not t then return nil end
    for _, r in ipairs(KEY_SHORT) do t = t:gsub(r[1], r[2]) end
    return t
end

--- The key bound to this button, as the game writes it on the button ("s-F", "Q"), or nil. Over a real
--- button: the text on its own HotKey, exactly what you see when the planner is closed. In the grid:
--- the binding for that bar position.
local function KeyText(b)
    local hk = type(b.real) == "table" and b.real.HotKey
    local t = type(hk) == "table" and type(hk.GetText) == "function" and hk:GetText()
    if t and t ~= "" and t ~= RANGE_INDICATOR then return YR.PlannerShortKey(t) end
    if b.command and GetBindingKey then
        local key = GetBindingKey(b.command)
        if key then return YR.PlannerShortKey(GetBindingText and GetBindingText(key, true) or key) end
    end
end

local function Tooltip(self)
    local e = plan[self.slot]
    if not e then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local class = Class()
    local d = e.kind == "spell" and not e.prof and (((YR.PlannerSpells or {})[class] or {})[e.name]
        or ((YR.PlannerGeneral or {})[class] or {})[e.name])
    local r = RankOf(e)
    if r then GameTooltip:SetSpellByID(r.id)
    elseif d then GameTooltip:SetSpellByID(d[1])
    elseif e.prof and e.id then GameTooltip:SetSpellByID(e.id)
    else
        GameTooltip:AddLine(e.name or "?")
        if e.kind == "macro" and e.body then GameTooltip:AddLine(e.body, 0.7, 0.7, 0.7, true) end
    end
    if r then
        GameTooltip:AddLine(("Kept at rank %d (learned at level %d): newer ranks don't replace it"):format(r.rank, r.level),
            0.4, 0.66, 1, true)
    elseif e.prof then
        GameTooltip:AddLine("Goes on the bar once you've learned it", 0.6, 0.6, 0.6)
    elseif e.kind == "spell" and e.level and not e.racial and not e.general then
        GameTooltip:AddLine(("Learned at level %d; the highest rank you know"):format(e.level), 0.6, 0.6, 0.6)
    end
    if e.kind == "spell" and not e.prof and #YR.PlannerRanks(e.name) > 1 then
        GameTooltip:AddLine("Mouse wheel: rank down or up. Shift-click: pick a rank.", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

local function MakeSlot(parent, bi, i)
    local b = CreateFrame("Button", nil, parent)
    b.bar, b.i = bi, i
    b.slot, b.command = BarBase(bi) + i - 1, BARS[bi][4] .. i
    b:SetSize(SLOT, SLOT)
    b.bg = S.Fill(b, S.C.field)
    S.Border(b, S.C.line)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.hl = S.Fill(b, S.C.hover, "OVERLAY")
    b.hl:Hide()
    -- The rank, where a button is kept at one: big, white, outlined, like a stack count.
    b.rank = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    b.rank:SetPoint("BOTTOMRIGHT", -2, 2)
    b.rank:SetTextColor(1, 1, 1)
    -- The key binding, top right like on the real button, cut at the button's edge.
    b.key = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
    b.key:SetPoint("TOPRIGHT", -2, -3)
    b.key:SetWidth(SLOT - 4)
    b.key:SetJustifyH("RIGHT")
    b.key:SetWordWrap(false)
    b.key:SetTextColor(0.9, 0.9, 0.9)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:EnableMouseWheel(true)
    b:SetScript("OnEnter", function(self) self.hl:Show() Tooltip(self) end)
    b:SetScript("OnLeave", function(self) self.hl:Hide() GameTooltip:Hide() end)
    b:SetScript("OnMouseWheel", function(self, delta)
        local e = plan[self.slot]
        if e and e.kind == "spell" and StepRank(e, delta > 0 and 1 or -1) then
            Paint()
            Tooltip(self)
        end
    end)
    b:SetScript("OnClick", function(self, button)
        if button == "LeftButton" and IsShiftKeyDown() and not carry and plan[self.slot] then
            YR.PlannerRankMenu(self)
            return
        end
        if button == "RightButton" then
            if carry then Drop() else plan[self.slot] = nil Paint() end
            return
        end
        if carry then
            PlaceIn(self)
        elseif plan[self.slot] then
            local e = plan[self.slot]
            plan[self.slot] = nil
            Carry(e)
            Paint()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        local e = plan[self.slot]
        if not e then return end
        plan[self.slot] = nil
        e.from = self.slot
        Carry(e)
        Paint()
    end)
    b:SetScript("OnDragStop", function()
        if not carry then return end
        local target = SlotUnderMouse()
        if target then PlaceIn(target) else carry.from = nil Drop() Paint() end   -- dropped off the bars: gone
    end)
    slots[#slots + 1] = b
    return b
end

--- Bar 1's buttons follow the form being planned.
local function Reslot()
    for _, b in ipairs(slots) do b.slot = BarBase(b.bar) + b.i - 1 end
end

-- ---------------------------------------------------------------------------
-- On my bars: one planner button over each real action button that's on screen
-- ---------------------------------------------------------------------------
--- Blizzard's button for this bar position, if the client has it and it's on screen.
local function RealButton(bar, i)
    local b = _G[bar[3] .. i]
    if b and b.IsVisible and b:IsVisible() then return b end
end

--- Which bars have their buttons on screen: { [bar index] = true }.
function YR.PlannerBarsShown()
    local out = {}
    for n, bar in ipairs(BARS) do
        if RealButton(bar, 1) then out[n] = true end
    end
    return out
end

local function LayOver()
    -- pairs, not ipairs: overlays are keyed by bar and button, and a bar that isn't on screen leaves a gap
    -- that ipairs stops at - which is how a bar's overlays stayed up after the planner closed.
    for _, o in pairs(overlays) do o:Hide() end
    if mode ~= "bars" or not (win and win:IsShown()) then return 0 end
    local n = 0
    for bi, bar in ipairs(BARS) do
        for i = 1, 12 do
            local real = RealButton(bar, i)
            local key = (bi - 1) * 12 + i
            local o = overlays[key]
            if real then
                if not o then
                    o = MakeSlot(UIParent, bi, i)
                    o:SetFrameStrata("HIGH")
                    -- dark enough that the real button's own icon doesn't show through the plan
                    o.bg:SetColorTexture(0.03, 0.035, 0.045, 0.92)
                    overlays[key] = o
                end
                o.real = real
                o:ClearAllPoints()
                o:SetAllPoints(real)
                o:Show()
                n = n + 1
            end
        end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------
local function OnBar()
    local set = {}
    for _, e in pairs(plan) do set[(e.kind or "") .. ":" .. (e.name or "")] = true end
    return set
end

local function ListRow(shown)
    local r = rows[shown]
    if r then return r end
    r = CreateFrame("Button", nil, win.list.content)
    r:SetSize(LIST_W - 18, LIST_ROW)
    r:SetPoint("TOPLEFT", 0, -(shown - 1) * LIST_ROW)
    r.hl = S.Fill(r, S.C.hover)
    r.hl:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(22, 22)
    r.icon:SetPoint("LEFT", 4, 0)
    r.lvl = S.Text(r, 12, S.C.muted)
    r.lvl:SetPoint("RIGHT", -6, 0)
    r.name = S.Text(r, 13)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", r.lvl, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r:RegisterForDrag("LeftButton")
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnEnter", function(self)
        self.hl:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.spell.id then GameTooltip:SetSpellByID(self.spell.id)
        else
            GameTooltip:AddLine(self.spell.name)
            if self.spell.body then GameTooltip:AddLine(self.spell.body, 0.7, 0.7, 0.7, true) end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) self.hl:Hide() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self, button)
        if button == "RightButton" then Drop() return end
        Carry(Entry(self.spell))
    end)
    r:SetScript("OnDragStart", function(self) Carry(Entry(self.spell)) end)
    r:SetScript("OnDragStop", function()
        local b = SlotUnderMouse()
        if b then PlaceIn(b) else Drop() end
    end)
    rows[shown] = r
    return r
end


local function Tag(s)
    if s.macro then return s.account and "account" or "character" end
    if s.prof then return s.profession end
    if s.racial then return "racial" end
    if s.general then return "general" end
    return "level " .. s.level
end

-- The lists don't change while the planner is open: read once per open (macros again on UPDATE_MACROS).
local lists = {}
local function ListOf(kind)
    if not lists[kind] then
        lists[kind] = kind == "macros" and YR.PlannerMacros()
            or kind == "professions" and YR.PlannerProfessionList() or YR.PlannerList()
    end
    return lists[kind]
end

--- Only the list (a search letter typed): the bars and the macro count stay as they are.
local function PaintList()
    local placed = OnBar()
    local shown = 0
    for _, s in ipairs(ListOf(listKind)) do
        if filter == "" or s.name:lower():find(filter, 1, true) then
            shown = shown + 1
            local r = ListRow(shown)
            r.spell = s
            r.icon:SetTexture(s.icon)
            r.name:SetText(s.name)
            r.name:SetTextColor(unpack(placed[(s.macro and "macro" or "spell") .. ":" .. s.name] and S.C.muted or S.C.text))
            r.lvl:SetText(Tag(s))
            r:Show()
        end
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    win.list.content:SetHeight(math.max(10, shown * LIST_ROW))
    win.newMacro:SetShown(listKind == "macros")
    win.empty:SetText(shown == 0 and (listKind == "macros" and "No macros yet: make one with the button below."
        or "Nothing matches.") or "")
end

function Paint()
    if not win then return end
    for _, b in ipairs(slots) do
        local e = plan[b.slot]
        b.key:SetText(KeyText(b) or "")
        if e then
            b.icon:SetTexture(IconOf(e))
            b.icon:Show()
            local r = RankOf(e)
            b.rank:SetText(r and ("R" .. r.rank) or "")
        else
            b.icon:Hide()
            b.rank:SetText("")
        end
    end
    PaintList()
    for k, t in pairs(win.kindTabs) do
        t.text:SetTextColor(unpack(k == listKind and S.C.text or S.C.muted))
        t.line:SetShown(k == listKind)
    end
    for _, t in ipairs(win.formTabs) do
        t.text:SetTextColor(unpack(t.bar == formBar and S.C.text or S.C.muted))
        t.line:SetShown(t.bar == formBar)
    end
    local n = 0
    for _ in pairs(plan) do n = n + 1 end
    local macros, limit = 0, 30
    if YS.MacrosNeeded then macros, limit = YS:MacrosNeeded({ slots = plan }, YS:Options()) end
    win.count:SetText(("%s: %d buttons, %s%d of %d macros|r"):format(Class():sub(1, 1) .. Class():sub(2):lower(), n,
        macros > limit and "|cffff6060" or "|cffb0b0b0", macros, limit))
    if mode == "bars" then
        local shownBars, hidden = YR.PlannerBarsShown(), {}
        for i = 1, #BARS do if not shownBars[i] then hidden[#hidden + 1] = i end end
        win.offscreen:SetText(#hidden > 0 and ("Bars %s aren't on screen: switch them on in the game's settings or Edit Mode, or plan them in the grid.")
            :format(table.concat(hidden, ", ")) or "")
    else
        win.offscreen:SetText("")
    end
    if win.gridLabel1 then
        local form
        for _, f in ipairs(YR.PlannerForms_()) do if f[2] == formBar then form = f[1] end end
        win.gridLabel1:SetText(form and ("Bar 1\n" .. form) or "Bar 1")
    end
end

-- ---------------------------------------------------------------------------
-- Saving
-- ---------------------------------------------------------------------------
local function Copy(t)
    local c = {}
    for k, v in pairs(t or {}) do c[k] = type(v) == "table" and Copy(v) or v end
    return c
end

local function Save(thenApply)
    YS:SetProfile({
        from = YS.PlayerKey() .. " (plan)", class = Class(), maxLevel = 60, scanned = time(),
        slots = Copy(plan), planned = true,        -- bars only: the interface is the account's (YS:SharedUI)
    })
    local n = 0
    for _ in pairs(plan) do n = n + 1 end
    YR.Print(("saved your %s plan: %d buttons. It's the %s layout now (Headstart, QoL, Character setup)."):format(
        Class():lower(), n, Class():lower()))
    if YS.Refresh then YS:Refresh() end
    if YR.RefreshWindow then YR:RefreshWindow() end
    if thenApply then
        if win then win:Hide() end          -- the overlays off the bars, so the real buttons show
        YS:Apply()
    end
end

StaticPopupDialogs["HEADSTART_PLAN_OVERWRITE"] = {
    text = "Headstart: replace the saved layout from %s with this plan?",
    button1 = "Replace",
    button2 = "Cancel",
    OnAccept = function(_, data) Save(data) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function AskSave(thenApply)
    if InCombatLockdown() and thenApply then YR.Print("not in combat.") return end
    local old = YS:Profile()
    if old and not old.planned then
        local d = StaticPopup_Show("HEADSTART_PLAN_OVERWRITE", old.from)
        if d then d.data = thenApply end
    else
        Save(thenApply)
    end
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
local function SetMode(m)
    mode = m
    if YippSetupDB then YippSetupDB.plannerMode = m end
    -- the Headstart window would cover the bars: out of the way while planning on them, back after
    if m == "bars" and HeadstartWindow and HeadstartWindow:IsShown() then
        reopenMain = true
        HeadstartWindow:Hide()
    end
    local grid = m == "grid"
    win.grid:SetShown(grid)
    win:SetWidth(grid and GRID_W or LIST_ONLY_W)
    win.modeBars.text:SetTextColor(unpack(grid and S.C.muted or S.C.text))
    win.modeBars.line:SetShown(not grid)
    win.modeGrid.text:SetTextColor(unpack(grid and S.C.text or S.C.muted))
    win.modeGrid.line:SetShown(grid)
    win:ClearAllPoints()
    if grid then
        win:SetPoint("CENTER")
    else
        win:SetPoint("LEFT", UIParent, "LEFT", 40, 40)     -- out of the way of the bars it's drawing on
    end
    LayOver()
    Drop()
    Paint()
end

local function SetForm(bar)
    formBar = bar
    Reslot()
    Drop()
    Paint()
end

local function Tab(parent, label, x, y, onClick, size)
    local b = CreateFrame("Button", nil, parent)
    b.text = S.Text(b, size or 13)
    b.text:SetPoint("CENTER", 0, 1)
    b.text:SetText(label)
    b:SetSize(b.text:GetStringWidth() + 20, 24)
    b:SetPoint("TOPLEFT", x, y)
    b.line = b:CreateTexture(nil, "OVERLAY")
    b.line:SetPoint("BOTTOMLEFT", 6, 0)
    b.line:SetPoint("BOTTOMRIGHT", -6, 0)
    b.line:SetHeight(2)
    S.Set(b.line, S.C.accent)
    b:SetScript("OnClick", onClick)
    return b
end

-- A form's short name for its tab: "Cat Form" -> "Cat", "Defensive Stance" -> "Defensive".
local function ShortForm(name)
    return (name:gsub(" Form$", ""):gsub(" Stance$", ""))
end

local function OpenMacros()
    if InCombatLockdown() then return end
    if not MacroFrame and C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_MacroUI") end
    if ShowMacroFrame then ShowMacroFrame() elseif MacroFrame then MacroFrame:Show() end
end

local function Build()
    win = S.Window("HeadstartPlanner", GRID_W, WIN_H, "Plan your bars")
    -- above the Headstart window it's opened from, so nothing of that one shows through
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win:HookScript("OnHide", function()
        Drop()
        if menu then menu:Hide() end
        for _, o in pairs(overlays) do o:Hide() end
        if reopenMain and HeadstartWindow then HeadstartWindow:Show() end
        reopenMain = false
    end)
    win:EnableMouse(true)
    win:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then Drop() end end)
    -- a fight: the overlays would sit on top of the buttons you need. New macros: the Macros tab.
    win:RegisterEvent("PLAYER_REGEN_DISABLED")
    win:RegisterEvent("UPDATE_MACROS")
    win:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then self:Hide()
        else lists.macros = nil if self:IsShown() then Paint() end end
    end)

    local y = -54
    win.modeBars = Tab(win, "On my bars", 12, y, function() SetMode("bars") end)
    win.modeGrid = Tab(win, "As a grid", 12 + win.modeBars:GetWidth() + 4, y, function() SetMode("grid") end)
    y = y - 32

    -- Bar 1 in each form: only for a class whose forms swap the main bar
    win.formTabs = {}
    local forms = YR.PlannerForms_()
    if #forms > 0 then
        local lab = S.Text(win, 12, S.C.sub)
        lab:SetPoint("TOPLEFT", 16, y - 6)
        lab:SetText("Bar 1:")
        local x = 58
        local list = { { "Normal", 0 } }
        for _, f in ipairs(forms) do list[#list + 1] = { ShortForm(f[1]), f[2] } end
        for _, f in ipairs(list) do
            local t = Tab(win, f[1], x, y, function() SetForm(f[2]) end, 12)
            t.bar = f[2]
            win.formTabs[#win.formTabs + 1] = t
            x = x + t:GetWidth() + 2
        end
        y = y - 30
    end

    -- the list: spells, professions or macros
    win.kindTabs = {}
    local x = 12
    for _, k in ipairs({ { "spells", "Spells" }, { "professions", "Professions" }, { "macros", "Macros" } }) do
        local t = Tab(win, k[2], x, y, function() listKind = k[1] Paint() end)
        win.kindTabs[k[1]] = t
        x = x + t:GetWidth() + 4
    end
    y = y - 30
    local search = S.Input(win, { width = LIST_W, placeholder = "Find", onChange = function(t)
        filter = strtrim(t or ""):lower()
        PaintList()
    end })
    search:SetPoint("TOPLEFT", 16, y)
    y = y - 32
    win.list = S.ScrollArea(win, LIST_W, 300)
    win.list:SetPoint("TOPLEFT", 16, y)
    win.empty = S.Text(win.list, 12, S.C.muted)
    win.empty:SetPoint("TOPLEFT", 6, -8)
    win.newMacro = S.Button(win, "New macro...", OpenMacros, nil, 130)
    win.newMacro:SetPoint("TOPLEFT", win.list, "BOTTOMLEFT", 0, -6)
    win.newMacro.tip = "Open the macro window: a stealth or shapeshift macro you make shows up in this list"

    win.count = S.Text(win, 13, S.C.sub)
    win.count:SetPoint("TOPLEFT", win.list, "BOTTOMLEFT", 0, -42)
    win.offscreen = S.Text(win, 12, S.C.gold)
    win.offscreen:SetPoint("TOPLEFT", win.count, "BOTTOMLEFT", 0, -6)
    win.offscreen:SetWidth(LIST_W)
    win.offscreen:SetJustifyH("LEFT")
    win.offscreen:SetWordWrap(true)
    local help = S.Text(win, 12, S.C.muted)
    help:SetPoint("TOPLEFT", win.offscreen, "BOTTOMLEFT", 0, -8)
    help:SetWidth(LIST_W)
    help:SetJustifyH("LEFT")
    help:SetWordWrap(true)
    help:SetText("Drag onto a button, or click and then a button. Drag a button to move it; drop it off the"
        .. " bars to take it off. Right-click empties it. Mouse wheel or Shift-click: the rank.")

    -- the grid: all eight bars as rows, beside the list
    win.grid = CreateFrame("Frame", nil, win)
    win.grid:SetPoint("TOPLEFT", 16 + LIST_W + 20, -92)
    win.grid:SetSize(86 + 12 * (SLOT + GAP), #BARS * ROW_H)
    for r, bar in ipairs(BARS) do
        local label = S.Text(win.grid, 12, S.C.sub)
        label:SetPoint("TOPLEFT", 0, -(r - 1) * ROW_H - 6)
        label:SetWidth(82)
        label:SetJustifyH("LEFT")
        label:SetText(bar[1])
        if r == 1 then win.gridLabel1 = label end
        for i = 1, 12 do
            local b = MakeSlot(win.grid, r, i)
            b:SetPoint("TOPLEFT", 86 + (i - 1) * (SLOT + GAP), -(r - 1) * ROW_H)
        end
    end

    -- 16 + 70 + gap + 70 + 6 + 140 + 16 fits the narrow window (332) with room between Empty and Save
    local save = S.Button(win, "Save and apply", function() AskSave(true) end, "primary", 140)
    save:SetPoint("BOTTOMRIGHT", -16, 14)
    local saveOnly = S.Button(win, "Save", function() AskSave(false) end, nil, 70)
    saveOnly:SetPoint("RIGHT", save, "LEFT", -6, 0)
    local clear = S.Button(win, "Empty", function() wipe(plan) Drop() Paint() end, nil, 70)
    clear:SetPoint("BOTTOMLEFT", 16, 14)
end

-- The rank menu: "Highest rank you know" and every rank with its level.
function YR.PlannerRankMenu(b)
    local e = plan[b.slot]
    if not (e and e.kind == "spell" and not e.prof) then return end
    local ranks = YR.PlannerRanks(e.name)
    if #ranks < 2 then return end
    if not menu then
        menu = CreateFrame("Frame", "HeadstartPlannerRankMenu", UIParent)
        menu:SetFrameStrata("TOOLTIP")
        S.Fill(menu, S.C.card)
        S.Border(menu, S.C.lineHi)
        menu.items = {}
        menu:EnableMouse(true)
        tinsert(UISpecialFrames, "HeadstartPlannerRankMenu")
    end
    for _, it in ipairs(menu.items) do it:Hide() end
    local choices = { { label = "Highest rank you know" } }
    for i = #ranks, 1, -1 do
        local r = ranks[i]
        choices[#choices + 1] = { label = ("Rank %d  (level %d)"):format(r.rank, r.level), rank = r.rank }
    end
    local cur = RankOf(e)
    for i, c in ipairs(choices) do
        local it = menu.items[i]
        if not it then
            it = CreateFrame("Button", nil, menu)
            it:SetSize(190, 22)
            it.hl = S.Fill(it, S.C.hover)
            it.hl:Hide()
            it.text = S.Text(it, 12)
            it.text:SetPoint("LEFT", 8, 0)
            it:SetScript("OnEnter", function(self) self.hl:Show() end)
            it:SetScript("OnLeave", function(self) self.hl:Hide() end)
            menu.items[i] = it
        end
        it:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 22)
        it.text:SetText(c.label)
        local picked = (c.rank == nil and cur == nil) or (cur ~= nil and c.rank == cur.rank)
        it.text:SetTextColor(unpack(picked and S.C.accent or S.C.text))
        it:SetScript("OnClick", function()
            SetRank(e, c.rank)
            menu:Hide()
            Paint()
        end)
        it:Show()
    end
    menu.choices = choices
    menu:SetSize(198, 8 + #choices * 22)
    menu:ClearAllPoints()
    -- above the button: an overlay on the bottom bar has no room below it
    menu:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 4)
    menu:Show()
end

--- Open the planner, starting from the class's saved layout. On your bars unless you last chose the grid,
--- or no Blizzard bar is on screen at all (a bar addon draws its own).
function YR.OpenPlanner()
    if InCombatLockdown() then YR.Print("not in combat.") return end
    if not win then Build() end
    local p = YS:Profile()
    plan = {}
    for slot, e in pairs(p and p.slots or {}) do plan[slot] = Copy(e) end
    wipe(lists)      -- spells learned or macros made since the last open
    win.subtitle:SetText("")
    formBar = 0
    Reslot()
    local want = (YippSetupDB and YippSetupDB.plannerMode) or "bars"
    if want == "bars" and not next(YR.PlannerBarsShown()) then want = "grid" end
    win:Show()
    SetMode(want)
end

--- For tests: the plan as it stands and every planner button; carrying a spell as a list click does; saving.
function YR.PlannerState() return plan, slots end
function YR.PlannerCarry(spell) Carry(Entry(spell)) end
function YR.PlannerSave(thenApply) Save(thenApply) end
function YR.PlannerAskSave(thenApply) AskSave(thenApply) end
function YR.PlannerCarrying() return carry ~= nil end
function YR.PlannerSetRank(slot, rank) if plan[slot] then SetRank(plan[slot], rank) Paint() end end
function YR.PlannerMenu() return menu end
function YR.PlannerSetMode(m) SetMode(m) end
function YR.PlannerOverlays() return overlays end
function YR.PlannerSetForm(bar) SetForm(bar) end
function YR.PlannerSetList(kind) listKind = kind Paint() end
function YR.PlannerWindow() return win end
