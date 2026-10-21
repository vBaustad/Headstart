-- Chat log: everything your chat windows showed, kept - also from earlier sessions - in a window of
-- its own that is big enough to read, can be searched, and lets you mark text and copy it.
--   How it is kept: each chat window's AddMessage is hooked (hooksecurefunc: the line has already
--   gone to the window, nothing of the game's is changed). What the window was given - the finished
--   line, colours and links in it - is put in a list. A line the game keeps secret (chat can be,
--   where it restricts it) is not kept: it can't be stored or shown again. The combat log's window
--   is left out.
--   Free while off: no chat window is hooked, no frame is made and nothing is listened for until it
--   is turned on; and a log left over from when it was on is dropped at the next login, so it isn't
--   read in at every login for nothing.
--   The window is one box of text you can mark with the mouse and copy (Ctrl+C): the game only lets
--   text be marked in an edit box, so the lines are put in one - each in the colour chat gave it,
--   pictures left out, a link as the words it shows.
--   A small button on the chat's button strip opens it (/headstart chat does too).
--   The chat itself gets its old text back: at a login or a reload (both leave the chat windows
--   empty) the last lines each window showed are put into it again, so you can scroll up in chat as
--   if you had never left. The log's window is then for searching and copying.
--   Account options (YippRouteDB; Headstart, QoL, Chat): chatLog (off until turned on), chatLogMax
--   (lines kept, 1000), chatLogKeep (between sessions; on unless turned off), chatLogButton (on unless
--   turned off), chatLogRestore (old text back in the chat windows; on unless turned off),
--   chatLogRestoreLines (how many a window, 100). Per character: HeadstartChatLog = { text = { line, ... }, meta = { time * 16 +
--   window, ... }, col = { colour as one number, or -1, ... } }: three plain lists side by side, not
--   a table a line (this is every line of chat, and the file is read in at every login).
local ADDON, YR = ...

local on = false
local text, meta, col              -- this character's lines, oldest first (see above)
local n, max, cut = 0, 1000, 1200  -- how many are kept now; how many may be; when the list is cut back
local hooked = {}                  -- [chat frame] = its window number
local restoring = false            -- old lines are being put back in the chat: they aren't kept a second time
local win, button
local view = { window = 0, search = "" }
local SESSION = 0                  -- the "window" of a line that marks where a session began
local SHOWN_MAX = 600              -- lines put in the window at once (the newest that match)
local floor, issecret = math.floor, issecretvalue

function YR.ChatLogOn() return YR.Option("chatLog") end
function YR.ChatLogMax() return 1000 end

local function DB()
    local db = _G.HeadstartChatLog
    if type(db) ~= "table" or type(db.text) ~= "table" or type(db.meta) ~= "table" or type(db.col) ~= "table" then
        db = { text = {}, meta = {}, col = {} }
        _G.HeadstartChatLog = db
    end
    return db
end

local function Bind()
    local db = DB()
    text, meta, col = db.text, db.meta, db.col
    n = #text
    max = YR.ChatLogMax()
    cut = floor(max * 1.2)
end

-- Only the newest lines are kept. Taking one off the front for every line added would move the whole
-- list each time: it is cut back in one go when it has grown a fifth past what is kept.
local function Trim(exact)
    if n <= (exact and max or cut) then return end
    local from = n - max
    local t, m, c = {}, {}, {}
    for i = from + 1, n do
        local k = i - from
        t[k], m[k], c[k] = text[i], meta[i], col[i]
    end
    local db = DB()
    db.text, db.meta, db.col = t, m, c
    text, meta, col, n = t, m, c, max
end

-- A line a chat window was given. This is every line of chat: three numbers and the line itself are
-- put away, and no table is made.
local function Keep(frame, msg, r, g, b)
    if not on or restoring or type(msg) ~= "string" or (issecret and issecret(msg)) or msg == "" then return end
    n = n + 1
    text[n] = msg
    meta[n] = time() * 16 + (hooked[frame] or 1)
    if type(r) == "number" and type(g) == "number" and type(b) == "number"
            and not (issecret and (issecret(r) or issecret(g) or issecret(b))) then
        col[n] = floor(r * 255 + 0.5) * 65536 + floor(g * 255 + 0.5) * 256 + floor(b * 255 + 0.5)
    else
        col[n] = -1
    end
    if n > cut then Trim() end
end

local function Hook()
    for i = 1, tonumber(_G.NUM_CHAT_WINDOWS) or 10 do
        local frame = _G["ChatFrame" .. i]
        local combat = frame and (frame == _G.COMBATLOG or (IsCombatLog and IsCombatLog(frame)))
        if type(frame) == "table" and frame.AddMessage and not hooked[frame] and not combat then
            hooked[frame] = i
            hooksecurefunc(frame, "AddMessage", Keep)
        end
    end
end

--- A line as plain text: no colours, no pictures, a link as the words it shows.
function YR.ChatPlain(s)
    if not s:find("|", 1, true) then return s end           -- most lines have none of it
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|cn[^:|]*:", "")
    s = s:gsub("|r", "")
    s = s:gsub("|H[^|]*|h(.-)|h", "%1")
    s = s:gsub("|T[^|]*|t", "")
    s = s:gsub("|A[^|]*|a", "")
    s = s:gsub("|K[^|]*|k", "?")            -- a name the game keeps to itself (Battle.net)
    s = s:gsub("|n", "\n")
    s = s:gsub("||", "|")
    return s
end

--- Line i as { time, window, text, r, g, b } (for the window and the tests; not kept anywhere).
function YR.ChatLogLine(i)
    local m, c = meta[i], col[i] or -1
    if not m then return nil end
    local l = { floor(m / 16), m % 16, text[i] }
    if c >= 0 then l[4], l[5], l[6] = floor(c / 65536) / 255, floor(c / 256) % 256 / 255, c % 256 / 255 end
    return l
end

--- The chat windows to pick from: { { number, name } }, "All windows" (0) first, then every chat
--- window you have (its tab's name), the combat log's left out - whether or not it has said anything
--- since the log was turned on.
function YR.ChatLogWindows()
    local out = { { 0, "All windows" } }
    for i = 1, tonumber(_G.NUM_CHAT_WINDOWS) or 10 do
        local frame = _G["ChatFrame" .. i]
        if type(frame) == "table" and hooked[frame] then
            -- a window in use: shown, or one of the tabs docked with the first
            local name, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(i)
            if type(name) == "string" and name ~= "" and (i == 1 or shown or docked or frame.isDocked or (frame.IsShown and frame:IsShown())) then
                out[#out + 1] = { i, name }
            end
        end
    end
    return out
end

--- The lines to show, oldest first: of one window (0: all) that have these words in them, the
--- newest `limit` of them, each as YR.ChatLogLine gives it. Returns them and how many matched in all.
function YR.ChatLogLines(window, search, limit)
    local found, total = {}, 0
    search = search and search ~= "" and search:lower() or nil
    limit = limit or SHOWN_MAX
    -- all windows: a line two windows showed in the same second is one line (said twice in one
    -- window it is two)
    local all = window == 0 or window == nil
    local seen, seenAt = all and {} or nil, nil
    for i = n, 1, -1 do
        local w = meta[i] % 16
        local mark = w == SESSION
        local twice = false
        if all and not mark then
            local at = floor(meta[i] / 16)
            if at ~= seenAt then seenAt = at wipe(seen) end
            local first = seen[text[i]]
            if first and first ~= w then twice = true else seen[text[i]] = w end
        end
        if twice then
            -- shown already, from the other window
        elseif mark or all or w == window then
            if mark or not search or YR.ChatPlain(text[i]):lower():find(search, 1, true) then
                if not mark then total = total + 1 end
                if #found < limit then found[#found + 1] = i end
            end
        end
    end
    -- newest first was how they were found: turned round, and a session's mark with nothing after
    -- it (or two in a row) left out
    local out = {}
    for k = #found, 1, -1 do
        local i, after = found[k], found[k - 1]
        local mark = meta[i] % 16 == SESSION
        if not (mark and (after == nil or meta[after] % 16 == SESSION)) then out[#out + 1] = YR.ChatLogLine(i) end
    end
    return out, total
end

local function Stamp(t) return date and date("%H:%M", t) or "" end
local function Day(t) return date and date("%A %d %B", t) or "" end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
local W, H = 780, 540

-- A line for the box: the time, then what chat said without pictures and with links as words, in
-- the colour chat gave it (a colour inside the line - a name, an item - stays as it was).
local function BoxLine(l)
    local words = l[3]
    if words:find("|", 1, true) then
        words = words:gsub("|T[^|]*|t", "")
        words = words:gsub("|A[^|]*|a", "")
        words = words:gsub("|H[^|]*|h(.-)|h", "%1")
        words = words:gsub("|K[^|]*|k", "?")
        words = words:gsub("|n", "\n")
    end
    if l[4] then
        return ("|cff8a827a%s|r  |cff%02x%02x%02x%s|r"):format(Stamp(l[1]), l[4] * 255, l[5] * 255, l[6] * 255, words)
    end
    return ("|cff8a827a%s|r  %s"):format(Stamp(l[1]), words)
end

-- The newest lines are at the bottom: that is where the window opens. The box of text only has its
-- new height a frame after its text is set, so this is done when the text is set, again when the box
-- changes size, and once more a frame on - until then the view would sit at the top.
local toBottom = false
local function Bottom()
    if not win then return end
    local h = win.box.GetHeight and win.box:GetHeight() or 0
    win.area.content:SetHeight(math.max(10, h))
    if win.area.UpdateBar then win.area:UpdateBar() end
    if toBottom and win.area.SetVerticalScroll then
        -- how far down the bottom is, worked out here: what the scroll frame says its range is is still
        -- the range of the text before this one until it has been drawn once
        local shown = win.area.GetHeight and win.area:GetHeight() or 0
        win.area:SetVerticalScroll(math.max(0, h - shown))
        if win.area.UpdateBar then win.area:UpdateBar() end
    end
end

local function Fill()
    if not win then return end
    local list, total = YR.ChatLogLines(view.window, view.search)
    win.count:SetText(total > SHOWN_MAX and ("Showing the newest %d of %d lines. Search to find older ones."):format(SHOWN_MAX, total)
        or ("%d line%s"):format(total, total == 1 and "" or "s"))
    local out, day = {}, nil
    for _, l in ipairs(list) do
        local d = Day(l[1])
        if d ~= day then
            day = d
            out[#out + 1] = "|cff8a827a---- " .. d .. " ----|r"
        end
        if l[2] == SESSION then
            out[#out + 1] = "|cff8a827a---- logged in " .. Stamp(l[1]) .. " ----|r"
        else
            out[#out + 1] = BoxLine(l)
        end
    end
    -- (the box grows to its text; made small first, so a shorter text than the last leaves no empty
    -- stretch under it)
    if win.box.SetHeight then win.box:SetHeight(1) end
    win.box:SetText(table.concat(out, "\n"))
    win.box:ClearFocus()
    toBottom = true
    Bottom()
    C_Timer.After(0, function()
        Bottom()
        -- and a moment later it is yours to scroll: a change of size after that leaves the view alone
        C_Timer.After(0.3, function() Bottom() toBottom = false end)
    end)
end

local function Build()
    if win then return end
    local S = YR.Style
    win = S.Window("HeadstartChatLogWindow", W, H, "Chat log")
    -- (the windows' own layer, as Headstart's window: a layer under it, it opened under the settings)
    -- which window, a search, and the two ways to look at it
    local pick
    pick = S.Dropdown(win, 170, YR.ChatLogWindows, function(v)
        view.window = v
        pick:Refresh()
        Fill()
    end)
    pick:SetPoint("TOPLEFT", 16, -60)
    function pick:Refresh()
        local label = "All windows"
        for _, o in ipairs(YR.ChatLogWindows()) do if o[1] == view.window then label = o[2] end end
        self:SetValue(label)
    end
    win.pick = pick
    win.search = S.Input(win, { width = 240, placeholder = "Search the log", onChange = function(words)
        view.search = words or ""
        Fill()
    end })
    win.search:SetPoint("LEFT", pick, "RIGHT", 10, 0)
    win.all = S.Button(win, "Select all", function()
        win.box:SetFocus()
        win.box:HighlightText()
    end, nil, 100)
    win.all:SetPoint("TOPRIGHT", -16, -60)
    win.all.tip = "Selects every line shown. Press Ctrl+C to copy"
    local again = S.Button(win, "Newest", function() Fill() end, nil, 90)
    again:SetPoint("RIGHT", win.all, "LEFT", -8, 0)
    again.tip = "Loads new chat lines and jumps to the newest"
    win.count = S.Text(win, 12, S.C.muted)
    win.count:SetPoint("BOTTOMLEFT", 16, 12)
    win.hint = S.Text(win, 12, S.C.muted)
    win.hint:SetPoint("BOTTOMRIGHT", -16, 12)
    win.hint:SetJustifyH("RIGHT")
    win.hint:SetText("Select text with the mouse, then press Ctrl+C.")

    -- the lines sit on a darker field, in a box of text: the one thing the game lets you mark text in
    local field = CreateFrame("Frame", nil, win)
    field:SetPoint("TOPLEFT", 16, -94)
    field:SetPoint("BOTTOMRIGHT", -16, 34)
    S.Fill(field, S.C.field)
    S.Border(field)
    local area = S.ScrollArea(field, W - 32 - 12, H - 94 - 34 - 12)
    area:SetPoint("TOPLEFT", 8, -6)
    local box = CreateFrame("EditBox", nil, area.content)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFont(S.FONT, 13, "")
    box:SetTextColor(S.C.text[1], S.C.text[2], S.C.text[3])
    box:SetPoint("TOPLEFT")
    box:SetWidth(W - 32 - 12 - 24)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnSizeChanged", Bottom)
    win.area, win.box = area, box
end

--- The log's window, on one chat window's lines (0 or nothing: all of them).
function YR.ChatLogOpen(window)
    if not on then
        YR.Print("the chat log is off. Turn it on in /hs, Chat.")
        return false
    end
    Build()
    if window then view.window = window end
    win.pick:Refresh()
    win:Show()
    Fill()
    return true
end

function YR.ChatLogToggle()
    if win and win:IsShown() then win:Hide() return end
    YR.ChatLogOpen()
end

--- How many lines are kept.
function YR.ChatLogCount() return on and n or 0 end

--- Every kept line forgotten.
function YR.ChatLogClear()
    _G.HeadstartChatLog = nil
    if on then Bind() end
    if win and win:IsShown() then Fill() end
end

-- ---------------------------------------------------------------------------
-- The button by the chat
-- ---------------------------------------------------------------------------
local function Button()
    if button then return button end
    local S = YR.Style
    button = S.IconButton(UIParent, "copy", function() YR.ChatLogToggle() end,
        "Chat log: read back, search, and copy text (Headstart)", nil, 20)
    button:SetFrameStrata("LOW")
    -- the picture has a wide empty edge round its two sheets (they are half its width): cut to the
    -- sheets, so it is as big on the strip as the chat's own buttons, and in their colour
    button.icon:SetTexCoord(0.17, 0.83, 0.17, 0.83)
    button.icon:SetVertexColor(0.78, 0.80, 0.85)
    button:HookScript("OnLeave", function(self) self.icon:SetVertexColor(0.78, 0.80, 0.85) end)
    return button
end

-- On the chat's button strip, over the chat menu's button at its foot: it is the strip's own child
-- there, so it fades and hides with the strip as Blizzard's buttons do, and is the strip's width (it
-- is slim when the strip is). With the strip hidden (Headstart, QoL, Chat) or not there, it sits by
-- the chat window's lower left corner instead.
local function PlaceButton()
    local strip, menu, chat = _G.ChatFrame1ButtonFrame, _G.ChatFrameMenuButton, _G.ChatFrame1
    local hidden = YR.ChatStripMode and YR.ChatStripMode() == "hide"
    button:ClearAllPoints()
    if type(strip) == "table" and strip.GetWidth and not hidden then
        -- as big as the strip's own buttons: the strip's width, its icon nearly all of it
        local size = math.max(16, math.min(28, strip:GetWidth() or 22))
        button:SetParent(strip)
        button:SetSize(size, size)
        button.icon:SetSize(size - 2, size - 2)
        if type(menu) == "table" and menu.GetParent and menu:GetParent() == strip then
            button:SetPoint("BOTTOM", menu, "TOP", 0, 3)
        else
            button:SetPoint("BOTTOM", strip, "BOTTOM", 0, 30)
        end
    elseif type(chat) == "table" then
        button:SetParent(UIParent)
        button:SetSize(20, 20)
        button.icon:SetSize(16, 16)
        button:SetPoint("TOPRIGHT", chat, "BOTTOMLEFT", -4, -3)
    else
        button:SetParent(UIParent)
        button:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 6, 6)
    end
end

function YR.ChatLogRestoreLines() return 100 end

--- The old text back in the chat windows: the last lines each window showed, oldest first, as chat
--- showed them. Once, at a login or a reload, before anything new is said. Returns how many went in.
--- (Not while another addon puts chat back after a reload too - Leatrix Plus's "Restore chat messages":
--- every line would be there twice.)
function YR.ChatLogRestore()
    if not on or YippRouteDB.chatLogRestore == false or n == 0 or YR.OtherHas("chatRestore") then return 0 end
    local per = YR.ChatLogRestoreLines()
    local frames, from, count = {}, {}, {}
    for frame, w in pairs(hooked) do frames[w] = frame end
    -- from the newest back, until every window has its lines (or the log is at its beginning)
    local wanted = 0
    for w in pairs(frames) do
        count[w], from[w] = 0, n + 1
        wanted = wanted + 1
    end
    for i = n, 1, -1 do
        local w = meta[i] % 16
        if count[w] and count[w] < per then
            count[w], from[w] = count[w] + 1, i
            if count[w] == per then
                wanted = wanted - 1
                if wanted == 0 then break end
            end
        end
    end
    local first, put = n + 1, 0
    for _, i in pairs(from) do if i < first then first = i end end
    restoring = true
    for i = first, n do
        local w = meta[i] % 16
        local frame = frames[w]
        if frame and i >= from[w] then
            local c = col[i] or -1
            if c >= 0 then
                frame:AddMessage(text[i], floor(c / 65536) / 255, floor(c / 256) % 256 / 255, c % 256 / 255)
            else
                frame:AddMessage(text[i])
            end
            put = put + 1
        end
    end
    -- where the old text ends, in the windows that got some
    for w, frame in pairs(frames) do
        if count[w] > 0 then frame:AddMessage("---- earlier, from the chat log ----", 0.5, 0.53, 0.58) end
    end
    restoring = false
    return put
end

--- After a setting changed (and at login): kept or not, and the button there or not.
function YR.ChatLogApply()
    local was = on
    on = YR.ChatLogOn()
    if on then
        Bind()
        Hook()
    elseif win then
        win:Hide()
    end
    local show = on and YippRouteDB.chatLogButton ~= false
    if show then
        Button()
        PlaceButton()
        button:Show()
    elseif button then
        button:Hide()
    end
    return was ~= on
end

function YR.StartChatLog()
    -- Off (or not kept between sessions): what the saved file still holds goes now, so it isn't read
    -- in at every login for nothing. This runs as Headstart loads, when the saved file has just been read.
    -- (the log's own switch, not the main one: quality of life switched off for a while keeps your
    -- settings, and the log with them)
    if not YR.OptionSet("chatLog") or YippRouteDB.chatLogKeep == false then _G.HeadstartChatLog = nil end
    local began = false
    YR.Part(YR.ChatLogOn, { "PLAYER_LOGOUT" }, function()
        -- not kept between sessions: not written to the file at all (it was, and read in again at the
        -- next login only to be dropped)
        if YippRouteDB.chatLogKeep == false then _G.HeadstartChatLog = nil return end
        if on then Trim(true) end
    end, {
        start = function()
            YR.ChatLogApply()
            -- once a login: the old text back in the chat windows, then where this session begins
            if not began then
                began = true
                YR.ChatLogRestore()
                if n > 0 and meta[n] % 16 ~= SESSION then
                    n = n + 1
                    text[n], meta[n], col[n] = "", time() * 16 + SESSION, -1
                end
            end
        end,
        stop = YR.ChatLogApply,
        again = YR.ChatLogApply,
    })
end
