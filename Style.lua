-- Our own look, instead of Blizzard's frames. Every YippRoute window is built from these pieces, so
-- the look lives in one place: flat layered panels, a thin border, one accent colour, clean narrow
-- text, and controls that say what they do.
local _, YR = ...

local S = {}
YR.Style = S

S.FONT = "Fonts\\ARIALN.TTF"
S.C = {
    window  = { 0.075, 0.08, 0.095, 0.98 },
    side    = { 0.055, 0.06, 0.07, 1 },
    card    = { 0.11, 0.12, 0.14, 1 },
    field   = { 0.045, 0.05, 0.06, 1 },
    line    = { 1, 1, 1, 0.07 },
    lineHi  = { 1, 1, 1, 0.16 },
    hover   = { 1, 1, 1, 0.045 },
    accent  = { 0.40, 0.66, 1.00, 1 },
    accentD = { 0.40, 0.66, 1.00, 0.16 },
    text    = { 0.93, 0.94, 0.96, 1 },
    sub     = { 0.70, 0.73, 0.78, 1 },
    muted   = { 0.50, 0.53, 0.58, 1 },
    green   = { 0.40, 0.85, 0.55, 1 },
    danger  = { 1.00, 0.45, 0.45, 1 },
    gold    = { 1.00, 0.80, 0.30, 1 },
}

local function Set(tex, color) tex:SetColorTexture(color[1], color[2], color[3], color[4] or 1) end
S.Set = Set

function S.Fill(frame, color, layer, sub)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    t:SetAllPoints()
    Set(t, color)
    return t
end

-- A one-pixel border from four textures; returns them so a focus state can recolour them.
function S.Border(frame, color)
    local edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = frame:CreateTexture(nil, "BORDER")
        Set(t, color or S.C.line)
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT") t:SetPoint(side .. "RIGHT") t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side) t:SetPoint("BOTTOM" .. side) t:SetWidth(1)
        end
        edges[#edges + 1] = t
    end
    function edges:Color(c) for _, t in ipairs(self) do Set(t, c) end end
    return edges
end

function S.Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(S.FONT, size or 13, "")
    fs:SetTextColor(unpack(color or S.C.text))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

function S.Icon(parent, texture, size)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size or 16, size or 16)
    t:SetTexture(texture)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return t
end

-- Buttons. kind: "primary" (accent fill), "danger", "ghost" (no fill until hovered), or nil (quiet).
function S.Button(parent, label, onClick, kind, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(26)
    local fill = kind == "primary" and S.C.accent or kind == "danger" and { 0.55, 0.16, 0.16, 1 }
        or kind == "ghost" and { 1, 1, 1, 0 } or { 1, 1, 1, 0.06 }
    local bg = S.Fill(b, fill)
    if kind ~= "primary" and kind ~= "ghost" then S.Border(b, S.C.line) end
    b.text = S.Text(b, 13, kind == "primary" and { 0.04, 0.07, 0.12, 1 } or S.C.text)
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetWidth(width or math.max(70, b.text:GetStringWidth() + 26))
    b:SetScript("OnEnter", function()
        if kind == "ghost" then bg:SetColorTexture(1, 1, 1, 0.06) else bg:SetAlpha(0.8) end
        if b.tip then S.Tip(b, b.tip) end
    end)
    b:SetScript("OnLeave", function()
        if kind == "ghost" then bg:SetColorTexture(1, 1, 1, 0) else bg:SetAlpha(1) end
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", onClick)
    function b:SetLabel(t) self.text:SetText(t) end
    return b
end

-- A square button showing an icon texture or a single character.
function S.IconButton(parent, iconOrChar, onClick, tip, color, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 22, size or 22)
    local bg = S.Fill(b, { 1, 1, 1, 0 })
    if type(iconOrChar) == "string" and iconOrChar:find("[\\/]") then
        b.icon = S.Icon(b, iconOrChar, (size or 22) - 8)
        b.icon:SetPoint("CENTER")
    else
        b.text = S.Text(b, 15, color or S.C.sub)
        b.text:SetPoint("CENTER", 0, 1)
        b.text:SetText(iconOrChar)
    end
    b:SetScript("OnEnter", function() bg:SetColorTexture(1, 1, 1, 0.09) if tip then S.Tip(b, tip) end end)
    b:SetScript("OnLeave", function() bg:SetColorTexture(1, 1, 1, 0) GameTooltip:Hide() end)
    b:SetScript("OnClick", onClick)
    return b
end

function S.Tip(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

-- On/off switch with its label to the right (and an optional grey note under it).
function S.Toggle(parent, label, get, set, note)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(300, note and 36 or 22)
    local track = b:CreateTexture(nil, "ARTWORK")
    track:SetSize(32, 16)
    track:SetPoint("TOPLEFT", 0, -3)
    local knob = b:CreateTexture(nil, "OVERLAY")
    knob:SetSize(12, 12)
    local text = S.Text(b, 13)
    text:SetPoint("TOPLEFT", track, "TOPRIGHT", 10, 1)
    text:SetText(label)
    if note then
        local n = S.Text(b, 11, S.C.muted)
        n:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -3)
        n:SetText(note)
    end
    function b:Refresh()
        local on = get()
        Set(track, on and S.C.accent or { 1, 1, 1, 0.14 })
        knob:SetColorTexture(1, 1, 1, 1)
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", track, "LEFT", on and 18 or 2, 0)
    end
    b:SetScript("OnClick", function() set(not get()) b:Refresh() end)
    b:Refresh()
    return b
end

-- A one-line text input. opts: width, numeric, placeholder, onChange(text) (on every edit),
-- onCommit(text) (Enter or leaving the field).
function S.Input(parent, opts)
    opts = opts or {}
    local box = CreateFrame("EditBox", nil, parent)
    box:SetSize(opts.width or 160, 24)
    box:SetAutoFocus(false)
    box:SetFont(S.FONT, 13, "")
    box:SetTextColor(unpack(S.C.text))
    box:SetTextInsets(7, 7, 0, 0)
    S.Fill(box, S.C.field)
    local border = S.Border(box)
    local hint = S.Text(box, 12, S.C.muted)
    hint:SetPoint("LEFT", 7, 0)
    hint:SetText(opts.placeholder or "")
    local function Hint() hint:SetShown(box:GetText() == "" and not box:HasFocus()) end
    box:SetScript("OnEditFocusGained", function() border:Color(S.C.accent) Hint() end)
    box:SetScript("OnEditFocusLost", function()
        border:Color(S.C.line) Hint()
        if opts.onCommit then opts.onCommit(box:GetText()) end
    end)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnTextChanged", function(_, user)
        Hint()
        if user and opts.onChange then opts.onChange(box:GetText()) end
    end)
    function box:SetValue(v) self:SetText(v == nil and "" or tostring(v)) Hint() end
    Hint()
    return box
end

-- A dropdown: shows the current choice; clicking opens a menu. options = { { value, label } } or a
-- function returning them. onPick(value).
local menu, catcher
local function CloseMenu() if menu then menu:Hide() end if catcher then catcher:Hide() end end
S.CloseMenu = CloseMenu

function S.OpenMenu(anchor, options, onPick, width)
    if not menu then
        catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN")
        catcher:SetScript("OnClick", CloseMenu)
        menu = CreateFrame("Frame", nil, UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        S.Fill(menu, S.C.card)
        S.Border(menu, S.C.lineHi)
        menu.items = {}
        menu:EnableMouseWheel(true)
        menu:SetScript("OnMouseWheel", function(self, d)
            self.offset = math.max(0, math.min(#self.options - #self.items, self.offset - d * 2))
            self:Fill()
        end)
        function menu:Fill()
            for i, item in ipairs(self.items) do
                local o = self.options[i + self.offset]
                if o then
                    item:Show()
                    item.value = o[1]
                    item.label:SetText(o[2])
                    item.label:SetTextColor(unpack(o[3] or S.C.text))
                else
                    item:Hide()
                end
            end
        end
    end
    local list = type(options) == "function" and options() or options
    local shown = math.min(#list, 14)
    menu.options, menu.offset, menu.onPick = list, 0, onPick
    for i = #menu.items + 1, shown do
        local item = CreateFrame("Button", nil, menu)
        item:SetHeight(22)
        item:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 22)
        item:SetPoint("RIGHT", -1, 0)
        local hi = S.Fill(item, { 1, 1, 1, 0 })
        item.label = S.Text(item, 13)
        item.label:SetPoint("LEFT", 10, 0)
        item.label:SetPoint("RIGHT", -8, 0)
        item:SetScript("OnEnter", function() hi:SetColorTexture(unpack(S.C.accentD)) end)
        item:SetScript("OnLeave", function() hi:SetColorTexture(1, 1, 1, 0) end)
        item:SetScript("OnClick", function(self) CloseMenu() menu.onPick(self.value) end)
        menu.items[i] = item
    end
    for i = shown + 1, #menu.items do menu.items[i]:Hide() end
    local items = {}
    for i = 1, shown do items[i] = menu.items[i] end
    menu.items = items
    menu:SetSize(width or anchor:GetWidth(), shown * 22 + 2)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:Fill()
    catcher:Show()
    menu:Show()
end

function S.Dropdown(parent, width, options, onPick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 24)
    S.Fill(b, S.C.field)
    local border = S.Border(b)
    b.label = S.Text(b, 13)
    b.label:SetPoint("LEFT", 8, 0)
    b.label:SetPoint("RIGHT", -20, 0)
    local arrow = S.Text(b, 11, S.C.muted)
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetText("v")
    b:SetScript("OnEnter", function() border:Color(S.C.lineHi) end)
    b:SetScript("OnLeave", function() border:Color(S.C.line) end)
    b:SetScript("OnClick", function(self)
        S.OpenMenu(self, options, function(v) onPick(v) end, math.max(width, 160))
    end)
    function b:SetValue(label) self.label:SetText(label or "") end
    return b
end

-- A small pill that can be on or off (class filters and the like).
function S.Chip(parent, label, onClick, iconTex, coords)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    b.bg = S.Fill(b, { 1, 1, 1, 0.05 })
    b.border = S.Border(b)
    local x = 8
    if iconTex then
        local i = b:CreateTexture(nil, "ARTWORK")
        i:SetSize(14, 14)
        i:SetPoint("LEFT", 5, 0)
        i:SetTexture(iconTex)
        if coords then i:SetTexCoord(unpack(coords)) end
        x = 23
    end
    b.text = S.Text(b, 12, S.C.sub)
    b.text:SetPoint("LEFT", x, 0)
    b.text:SetText(label)
    b:SetWidth(x + b.text:GetStringWidth() + 8)
    function b:SetOn(on, color)
        self.on = on
        self.bg:SetColorTexture(unpack(on and (color or S.C.accentD) or { 1, 1, 1, 0.05 }))
        self.border:Color(on and S.C.accent or S.C.line)
        self.text:SetTextColor(unpack(on and S.C.text or S.C.sub))
    end
    b:SetScript("OnClick", onClick)
    b:SetOn(false)
    return b
end

-- A number with - and + either side and the value typed in the middle.
function S.Stepper(parent, get, set, min, max, step, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 110, 24)
    local input
    local function Apply(v)
        v = tonumber(v)
        if v then set(math.max(min, math.min(max, v))) end
        input:SetValue(get())
    end
    local minus = S.IconButton(f, "-", function() Apply(get() - (step or 1)) end, nil, S.C.text, 24)
    minus:SetPoint("LEFT")
    local plus = S.IconButton(f, "+", function() Apply(get() + (step or 1)) end, nil, S.C.text, 24)
    plus:SetPoint("RIGHT")
    input = S.Input(f, { width = (width or 110) - 52, onCommit = Apply })
    input:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    input:SetJustifyH("CENTER")
    function f:Refresh() input:SetValue(get()) end
    f:Refresh()
    return f
end

-- A titled card: a slightly lighter panel with a heading and a grey line of explanation.
function S.Card(parent, title, note)
    local c = CreateFrame("Frame", nil, parent)
    S.Fill(c, S.C.card)
    S.Border(c)
    c.title = S.Text(c, 15)
    c.title:SetPoint("TOPLEFT", 14, -12)
    c.title:SetText(title)
    if note then
        c.note = S.Text(c, 12, S.C.muted)
        c.note:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
        c.note:SetText(note)
    end
    return c
end

-- A vertical scroll area for content taller than its box: put things on area.content.
function S.ScrollArea(parent, width, height)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetSize(width, height)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(width - 10, 10)
    sf:SetScrollChild(content)
    sf.content = content
    local bar = sf:CreateTexture(nil, "OVERLAY")
    bar:SetColorTexture(1, 1, 1, 0.16)
    bar:SetWidth(3)
    function sf:UpdateBar()
        local range = self:GetVerticalScrollRange()
        if range and range > 1 then
            bar:Show()
            local h = math.max(24, height * height / (height + range))
            bar:SetHeight(h)
            bar:ClearAllPoints()
            bar:SetPoint("TOPRIGHT", 0, -(height - h) * self:GetVerticalScroll() / range)
        else
            bar:Hide()
        end
    end
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, d)
        local range = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - d * 36)))
        self:UpdateBar()
    end)
    sf:SetScript("OnScrollRangeChanged", function(self) self:UpdateBar() end)
    return sf
end

-- The window: header with title and subtitle, close button, draggable, closes on Escape.
function S.Window(name, w, h, title)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    S.Fill(f, S.C.window)
    S.Border(f, S.C.lineHi)
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT") head:SetPoint("TOPRIGHT") head:SetHeight(48)
    local rule = head:CreateTexture(nil, "BORDER")
    rule:SetPoint("BOTTOMLEFT") rule:SetPoint("BOTTOMRIGHT") rule:SetHeight(1)
    Set(rule, S.C.line)
    local mark = head:CreateTexture(nil, "ARTWORK")
    mark:SetSize(4, 20)
    mark:SetPoint("LEFT", 18, 0)
    Set(mark, S.C.accent)
    f.title = S.Text(head, 17)
    f.title:SetPoint("LEFT", mark, "RIGHT", 10, 0)
    f.title:SetText(title)
    f.subtitle = S.Text(head, 13, S.C.muted)
    f.subtitle:SetPoint("LEFT", f.title, "RIGHT", 12, -1)
    local close = S.IconButton(head, "\195\151", function() f:Hide() end, "Close (Esc)", S.C.sub, 28)
    close.text:SetFont(S.FONT, 20, "")
    close:SetPoint("RIGHT", -10, 0)
    f:EnableMouse(true)
    f:SetMovable(true)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() f:StartMoving() end)
    head:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    tinsert(UISpecialFrames, name)
    f:SetScript("OnHide", CloseMenu)
    f:Hide()
    return f
end

-- A switch on its own (for rows where the label sits elsewhere).
function S.Switch(parent, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(34, 18)
    local track = b:CreateTexture(nil, "ARTWORK")
    track:SetAllPoints()
    local knob = b:CreateTexture(nil, "OVERLAY")
    knob:SetSize(14, 14)
    function b:Refresh()
        local on = get()
        Set(track, on and S.C.accent or { 1, 1, 1, 0.14 })
        knob:SetColorTexture(1, 1, 1, 1)
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", on and 18 or 2, 0)
    end
    b:SetScript("OnClick", function() set(not get()) b:Refresh() end)
    b:Refresh()
    return b
end

-- A slider with its value in a box beside it; either can be used.
function S.Slider(parent, min, max, step, get, set, width)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(width or 170, 24)
    local s = CreateFrame("Slider", nil, f)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("LEFT")
    s:SetSize((width or 170) - 58, 16)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step or 1)
    s:SetObeyStepOnDrag(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT") track:SetPoint("RIGHT") track:SetHeight(4)
    Set(track, { 1, 1, 1, 0.14 })
    local fill = s:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT") fill:SetHeight(4)
    Set(fill, S.C.accent)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 16)
    thumb:SetColorTexture(1, 1, 1, 1)
    s:SetThumbTexture(thumb)
    local box = S.Input(f, { width = 48, numeric = true, onCommit = function(t)
        local v = tonumber(t)
        if v then set(math.max(min, math.min(max, v))) end
        f:Refresh()
    end })
    box:SetPoint("RIGHT")
    box:SetJustifyH("CENTER")
    local busy = false
    s:SetScript("OnValueChanged", function(_, v)
        if busy then return end
        set(v)
        box:SetValue(v)
        fill:SetWidth(math.max(1, (v - min) / (max - min) * s:GetWidth()))
    end)
    function f:Refresh()
        busy = true
        local v = get()
        s:SetValue(v)
        box:SetValue(v)
        fill:SetWidth(math.max(1, (v - min) / (max - min) * s:GetWidth()))
        busy = false
    end
    f:Refresh()
    return f
end
