-- Our own look, instead of Blizzard's frames: flat panels, a thin border, one accent colour, narrow
-- clean text. Everything YippRoute draws goes through these few builders, so the look can change in
-- one place.
local _, YR = ...

local S = {}
YR.Style = S

S.FONT = "Fonts\\ARIALN.TTF"
S.C = {
    bg      = { 0.09, 0.10, 0.12, 0.97 },
    side    = { 0.06, 0.07, 0.08, 1 },
    line    = { 1, 1, 1, 0.08 },
    hover   = { 1, 1, 1, 0.05 },
    accent  = { 0.36, 0.62, 1.00, 1 },
    select  = { 0.36, 0.62, 1.00, 0.22 },
    text    = { 0.92, 0.93, 0.95, 1 },
    muted   = { 0.58, 0.61, 0.66, 1 },
    danger  = { 1.00, 0.42, 0.42, 1 },
}

function S.Fill(frame, color, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(unpack(color))
    return t
end

-- A one-pixel border drawn with four textures (no backdrop template needed).
function S.Border(frame, color)
    color = color or S.C.line
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(unpack(color))
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT") t:SetPoint(side .. "RIGHT") t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side) t:SetPoint("BOTTOM" .. side) t:SetWidth(1)
        end
    end
end

function S.Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(S.FONT, size or 13, "")
    fs:SetTextColor(unpack(color or S.C.text))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- A flat button: text on a faint fill, lighter on hover; primary ones are filled with the accent.
function S.Button(parent, label, onClick, primary)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(24)
    local bg = S.Fill(b, primary and S.C.accent or { 1, 1, 1, 0.07 })
    S.Border(b, primary and { 0, 0, 0, 0 } or S.C.line)
    b.text = S.Text(b, 13, primary and { 0.05, 0.08, 0.12, 1 } or S.C.text)
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetWidth(math.max(64, b.text:GetStringWidth() + 24))
    b:SetScript("OnEnter", function() bg:SetAlpha(0.75) end)
    b:SetScript("OnLeave", function() bg:SetAlpha(1) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- A small square icon-like button with a single character (arrows, x).
function S.Mini(parent, char, onClick, color)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    local bg = S.Fill(b, { 1, 1, 1, 0 })
    b.text = S.Text(b, 14, color or S.C.muted)
    b.text:SetPoint("CENTER")
    b.text:SetText(char)
    b:SetScript("OnEnter", function() bg:SetColorTexture(1, 1, 1, 0.08) end)
    b:SetScript("OnLeave", function() bg:SetColorTexture(1, 1, 1, 0) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- An on/off switch with a label to its right.
function S.Toggle(parent, label, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(260, 22)
    local track = b:CreateTexture(nil, "ARTWORK")
    track:SetSize(30, 14)
    track:SetPoint("LEFT")
    local knob = b:CreateTexture(nil, "OVERLAY")
    knob:SetSize(10, 10)
    local text = S.Text(b, 13)
    text:SetPoint("LEFT", track, "RIGHT", 10, 0)
    text:SetText(label)
    function b:Refresh()
        local on = get()
        track:SetColorTexture(unpack(on and S.C.accent or { 1, 1, 1, 0.15 }))
        knob:SetColorTexture(1, 1, 1, 1)
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", track, "LEFT", on and 18 or 2, 0)
    end
    b:SetScript("OnClick", function() set(not get()) b:Refresh() end)
    b:Refresh()
    return b
end

-- The window: title bar, close cross, draggable, closes on Escape.
function S.Window(name, w, h, title)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    S.Fill(f, S.C.bg)
    S.Border(f)
    f.title = S.Text(f, 16)
    f.title:SetPoint("TOPLEFT", 16, -12)
    f.title:SetText(title)
    local close = S.Mini(f, "x", function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, name)
    f:Hide()
    return f
end
