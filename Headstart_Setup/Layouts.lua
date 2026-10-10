-- Profiles: more than one for a class, and one click between them. (The word every addon uses for it.
-- In the code and the saved file a profile's bars are still a "layout": that is what it was first.)
--   A profile is your bars under a name - and, if you say so, the interface that goes with them: which
--   Edit Mode layout is active, which extra bars show, where RestedXP's windows are (its "own
--   interface", off unless you turn it on for that profile: a tank's and a damage dealer's bars usually
--   want the same screen; a healer's doesn't).
--   A warrior tanks and deals damage; a druid heals and claws. Each wants other spells on the same
--   buttons. So a class can have several bar layouts, each with a name ("Tank", "DPS"), and a
--   character is on one of them at a time:
--     New     the bars as they are now, kept under a name. You are on it at once (nothing moves).
--     Switch  the layout you leave is saved as your bars are this moment - what you moved by hand
--             since is remembered, as the game's own spec bars would - and the one you go to is put
--             on: only the buttons that differ change, a mount or a toy on a button no layout has is
--             left where it is, and the interface (Edit Mode, chat, settings) isn't touched.
--   The bar planner plans the layout you are on; Copy this layout copies into it.
--   Your two specs: the layout you were on in a spec is remembered for it. Change spec, and Headstart
--   asks whether to switch to that spec's layout ("specAsk": "ask", the default; "auto": switches
--   without asking; "off"). It never asks while you have one layout, or before a spec has had one.
--   Not in a fight: bars can't be changed there.
--   Saved: YippSetupDB.classes[CLASS].profile is the class's first layout (profileName, "Main"),
--   .layouts[name] the others; YippSetupCharDB.layoutName the one this character is on,
--   .specLayouts[spec] the one each spec was last on; YippSetupDB.specAsk.
-- (part of the Headstart_Setup addon)
local YR = _G.HeadstartNS
local YS = YR.Setup

local NAME_MAX = 20

local function Class() return YS.PlayerClass() end
local function Data(class) return YS.ClassData(class or Class()) end
local function MainName(class) return Data(class).profileName or "Main" end

--- The class's layouts by name, its first one first.
function YS.LayoutNames(class)
    local c = Data(class)
    local out = {}
    for name in pairs(c.layouts or {}) do out[#out + 1] = name end
    table.sort(out)
    table.insert(out, 1, MainName(class))
    return out
end

--- The layout this character is on, by name.
function YS.LayoutName()
    local c = Data()
    local name = YippSetupCharDB and YippSetupCharDB.layoutName
    if name and c.layouts and c.layouts[name] then return name end
    return MainName()
end

local function Exists(name, class)
    for _, n in ipairs(YS.LayoutNames(class)) do if n:lower() == name:lower() then return n end end
    return nil
end

local function Clean(name)
    name = strtrim(tostring(name or "")):gsub("|", "")
    return name:sub(1, NAME_MAX)
end

-- Your spec (1 or 2), or nil where the game has none.
local function Spec()
    local api = _G.C_SpecializationInfo
    if not (api and api.GetActiveSpecGroup) then return nil end
    local ok, group = pcall(api.GetActiveSpecGroup)
    return ok and tonumber(group) or nil
end
YS.SpecGroup = Spec

-- The layout this character is on now belongs to the spec it is in.
local function NoteSpec()
    local spec = Spec()
    if not (spec and YippSetupCharDB) then return end
    YippSetupCharDB.specLayouts = YippSetupCharDB.specLayouts or {}
    YippSetupCharDB.specLayouts[spec] = YS.LayoutName()
end

--- A new layout: your bars as they are now, under a name; this character is on it from now. Returns
--- true, or false and why not.
function YS.LayoutNew(name)
    if InCombatLockdown() then return false, "not in a fight." end
    name = Clean(name)
    if name == "" then return false, "it needs a name." end
    if Exists(name) then return false, ("there is a profile called %s already."):format(Exists(name)) end
    -- what you leave is saved as it stands, where there is something to save into
    if YS:Profile() and YippSetupCharDB.applied then YS:ScanBars() end
    local c = Data()
    c.layouts = c.layouts or {}
    c.layouts[name] = { class = Class(), from = YS.PlayerKey(), maxLevel = 60, scanned = time(), slots = {} }
    YippSetupCharDB.layoutName = name
    YS:ScanBars()                   -- the bars as they are are this layout
    YippSetupCharDB.applied = YippSetupCharDB.applied or time()
    YippSetupCharDB.layout = nil
    NoteSpec()
    return true
end

--- A layout deleted (never the class's first). A character on it is on the first again, its bars as they are.
function YS.LayoutDelete(name)
    local c = Data()
    if not (c.layouts and c.layouts[name]) then return false, "the class's first profile stays: rename it, or empty it in the planner." end
    c.layouts[name] = nil
    if YippSetupCharDB.layoutName == name then YippSetupCharDB.layoutName = nil end
    for spec, n in pairs(YippSetupCharDB.specLayouts or {}) do
        if n == name then YippSetupCharDB.specLayouts[spec] = nil end
    end
    return true
end

--- A layout renamed.
function YS.LayoutRename(old, new)
    new = Clean(new)
    if new == "" then return false, "it needs a name." end
    local c = Data()
    local taken = Exists(new)
    if taken and taken ~= old then return false, ("there is a profile called %s already."):format(taken) end
    if c.layouts and c.layouts[old] then
        c.layouts[new], c.layouts[old] = c.layouts[old], nil
        if old == new then c.layouts[new] = c.layouts[new] end
        if YippSetupCharDB.layoutName == old then YippSetupCharDB.layoutName = new end
    elseif old == MainName() then
        c.profileName = new
    else
        return false, "no such profile."
    end
    for spec, n in pairs(YippSetupCharDB.specLayouts or {}) do
        if n == old then YippSetupCharDB.specLayouts[spec] = new end
    end
    return true
end

local function Same(a, b)
    if a == nil or b == nil then return a == b end
    if a.kind ~= b.kind then return false end
    if a.kind == "item" then return a.id == b.id end
    return a.name == b.name and (a.down and a.id or 0) == (b.down and b.id or 0)
end

--- Switch this character to another of its class's layouts. Returns true, or false and why not.
function YS.LayoutSwitch(name)
    if InCombatLockdown() then return false, "not in a fight: bars can't be changed there." end
    local to = Exists(tostring(name or ""))
    if not to then return false, "no such profile." end
    if to == YS.LayoutName() then return false, ("you are on %s already."):format(to) end
    local c = Data()
    -- the one you leave, as your bars are this moment (a character never set up has bars that are
    -- nobody's layout: those aren't written over a saved one)
    if YS:Profile() and YippSetupCharDB.applied then
        YS:ScanBars()
        local leaving = YS:Profile()
        if leaving.ownUI and YS.ScanProfileUI then leaving.ui = YS.ScanProfileUI() end      -- and its interface
    end
    YippSetupCharDB.layoutName = (c.layouts and c.layouts[to]) and to or nil
    local target = YS:Profile()
    local slots = target and target.slots or {}
    if not next(slots) then
        -- nothing in it yet: your bars stay, and are what it holds when you next leave it
        YippSetupCharDB.applied = YippSetupCharDB.applied or time()
        NoteSpec()
        YS.Print(("switched to profile %s. It is empty, so your current bars are kept and saved to it."):format(to))
        return true
    end
    -- only the buttons that differ; a button no layout can hold (a mount, a toy) stays unless the
    -- layout has something for that button
    local now = YS.ReadBars(true)
    local only, n = {}, 0
    for slot = 1, 180 do
        local here, want = now[slot], slots[slot]
        if here and here.kind == "other" then
            if want then only[slot], n = true, n + 1 end
        elseif not Same(here, want) then
            only[slot], n = true, n + 1
        end
    end
    if n > 0 then YS:Apply(nil, only) end
    YippSetupCharDB.applied = YippSetupCharDB.applied or time()
    NoteSpec()
    local ui = target.ownUI and target.ui and YS.ApplyProfileUI and YS.ApplyProfileUI(target.ui) or ""
    YS.Print(("profile %s: %d button%s changed%s."):format(to, n, n == 1 and "" or "s", ui ~= "" and ("; " .. ui) or ""))
    if YR.RefreshWindow then YR:RefreshWindow() end
    return true
end

--- Whether the profile this character is on has an interface of its own; and turning that on or off.
--- On: the interface as it is this moment is the profile's (Edit Mode layout, bars shown, RestedXP's windows).
function YS.ProfileOwnUI()
    local p = YS:Profile()
    return p and p.ownUI == true or false
end
function YS.SetProfileOwnUI(on)
    local p = YS:Profile()
    if not p then return false end
    p.ownUI = on and true or nil
    if on then p.ui = YS.ScanProfileUI and YS.ScanProfileUI() or nil else p.ui = nil end
    return true
end

--- The next of the class's layouts (for a key).
function YS.LayoutNext()
    local names, cur = YS.LayoutNames(), YS.LayoutName()
    if #names < 2 then return false, "this class has one profile: make another in Headstart, Character setup." end
    for i, n in ipairs(names) do
        if n == cur then return YS.LayoutSwitch(names[i % #names + 1]) end
    end
    return YS.LayoutSwitch(names[1])
end

-- ---------------------------------------------------------------------------
-- Your two specs
-- ---------------------------------------------------------------------------
function YS.SpecAsk()
    local v = YippSetupDB and YippSetupDB.specAsk
    return (v == "auto" or v == "off") and v or "ask"
end

StaticPopupDialogs["YIPPSETUP_SPEC"] = {
    text = "Headstart: you changed spec. Switch to the profile %s?\n\nYour current bars are saved to %s first.",
    button1 = "Switch",
    button2 = "Not now",
    button3 = "Don't ask again",
    OnAccept = function(_, name)
        local ok, why = YS.LayoutSwitch(name)
        if not ok and why then YS.Print(why) end
    end,
    OnAlt = function()
        YippSetupDB.specAsk = "off"
        YS.Print("won't ask on spec change again. Change it in /hs, Character setup, Profiles.")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

--- Your spec changed (the game's event: the spec you're in now, and the one you were in).
function YS.OnSpecChanged(curr, prev)
    if not (YippSetupCharDB and YippSetupCharDB.applied) then return end
    local names = YS.LayoutNames()
    if #names < 2 then return end
    YippSetupCharDB.specLayouts = YippSetupCharDB.specLayouts or {}
    local by = YippSetupCharDB.specLayouts
    local cur = YS.LayoutName()
    -- the layout you were on belongs to the spec you came from, if it had none
    if prev and by[prev] == nil then by[prev] = cur end
    local want = curr and by[curr]
    if not want or want == cur or not Exists(want) then return end
    local mode = YS.SpecAsk()
    if mode == "off" then return end
    if mode == "auto" then
        local ok, why = YS.LayoutSwitch(want)
        if not ok and why then YS.Print(why) end
        return
    end
    -- the name goes in as an argument: a field written on Blizzard's popup would be ours (tainted)
    StaticPopup_Show("YIPPSETUP_SPEC", want, cur, want)
end
