"""Smoke test of the chat log (ChatLog.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_chatlog.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Off: no chat window is hooked and nothing is kept. On: every line a chat window shows is kept with its
window and colour (not the combat log's, not a secret one), only the newest so many; the window shows
one chat window's lines or all, searched; the text to copy is plain; a session's beginning is marked;
and nothing is kept between sessions when that is turned off.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r"""
FRAMES, SAID, HOOKS = {}, {}, 0
local F = {}
F.__index = function(t, k)
    if F[k] then return F[k] end
    return function() end                 -- any widget method: nothing
end
function F:RegisterEvent(e) local ev = rawget(self, "ev") or {} rawset(self, "ev", ev) ev[e] = true end
function F:UnregisterEvent(e) local ev = rawget(self, "ev") if ev then ev[e] = nil end end
function F:SetScript(what, fn) if what == "OnEvent" then rawset(self, "fn", fn) end end
function F:Show() rawset(self, "shown", true) end
function F:Hide() rawset(self, "shown", false) end
function F:SetShown(on) rawset(self, "shown", on and true or false) end
function F:IsShown() return rawget(self, "shown") == true end
function F:SetText(t) rawset(self, "text", t) end
function F:GetText() return rawget(self, "text") or "" end
function F:Clear() rawset(self, "said", {}) end
function F:AddMessage(text, r, g, b) local said = rawget(self, "said") or {} rawset(self, "said", said) said[#said + 1] = text end
function F:CreateFontString() return setmetatable({}, F) end
function F:CreateTexture() return setmetatable({}, F) end
function CreateFrame(_, name) local f = setmetatable({}, F) table.insert(FRAMES, f) if name then _G[name] = f end return f end
function Fire(e, ...) for _, f in ipairs(FRAMES) do local ev, fn = rawget(f, "ev"), rawget(f, "fn") if ev and ev[e] and fn then fn(f, e, ...) end end end
function hooksecurefunc(t, name, hook)
    HOOKS = HOOKS + 1
    local was = t[name]
    rawset(t, name, function(...) was(...) hook(...) end)
end
UIParent = setmetatable({}, F)
SlashCmdList, UISpecialFrames = {}, {}
tinsert = table.insert
strsplit = function() end
strtrim = function(s) return s end
function print(...) SAID[#SAID + 1] = table.concat({ ... }, " ") end
CLOCK = 86400 * 10 + 3600 * 12
function time() return CLOCK end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer = { After = function(_, fn) fn() end }
function date(fmt, t) return os.date("!" .. fmt, t) end
function GetChatWindowInfo(i) return ({ "General", "Combat Log", "Guild" })[i] end
NUM_CHAT_WINDOWS = 3
for i = 1, 3 do _G["ChatFrame" .. i] = setmetatable({}, F) end
COMBATLOG = ChatFrame2
SECRET = {}
function issecretvalue(v) return v == SECRET end
YippRouteDB = {}
local function W() local w = setmetatable({}, F) rawset(w, "content", setmetatable({}, F)) rawset(w, "icon", setmetatable({}, F)) return w end
STYLE = { FONT = "f", C = { text = { 1, 1, 1, 1 }, muted = { 1, 1, 1, 1 }, sub = { 1, 1, 1, 1 }, field = { 0, 0, 0, 1 } } }
for _, k in ipairs({ "Text", "Fill", "Border", "Button", "Rounded", "Icon", "IconButton", "Window", "Dropdown", "Input", "ScrollArea" }) do STYLE[k] = W end
STYLE.Window = function(name) local w = W() _G[name] = w return w end
"""


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    YR = lua.table()
    for f in ("Core.lua", "ChatLog.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    YR.Style = lua.eval("STYLE")
    YR.StartChatLog()
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def texts(window=0, search=""):
        return [l[3] for l in YR.ChatLogLines(window, search)[0].values() if l[2] != 0]

    YR.partsReady = True
    YR.ApplyParts()
    lua.execute("""ChatFrame1:AddMessage("before it was on")""")
    check(g.HOOKS == 0 and YR.ChatLogCount() == 0 and g.HeadstartChatLog is None,
          "never turned on: no chat window hooked, nothing kept, nothing saved")
    check(YR.ChatLogOpen() is False, "and its window says it is off instead of opening")

    g.YippRouteDB.chatLog = True
    YR.ApplyParts()
    check(g.HOOKS == 2, f"turned on: the chat windows are hooked, the combat log's left out ({g.HOOKS})")
    lua.execute("""ChatFrame1:AddMessage("|cffffff00[Guild] |Hplayer:Anna|h[Anna]|h: hi there|r", 0.25, 1, 0.25)
        ChatFrame2:AddMessage("You hit Boar for 12.")
        ChatFrame3:AddMessage("Bo whispers: got a |cff0070dd|Hitem:123|h[Blue Sword]|h|r for you")
        ChatFrame1:AddMessage(SECRET)
        ChatFrame1:AddMessage("")""")
    check(YR.ChatLogCount() == 2, f"each line shown is kept; the combat log's, a secret one and an empty one are not ({YR.ChatLogCount()})")
    first = YR.ChatLogLine(1)
    check(first[2] == 1 and abs(first[4] - 0.25) < 0.01 and first[5] == 1 and first[1] == g.CLOCK, "with its window, its colour and the time")
    check(g.HeadstartChatLog.text[1] == first[3] and isinstance(g.HeadstartChatLog.meta[1], (int, float)) and g.HeadstartChatLog.lines is None,
          "kept as three plain lists side by side, not a table a line")
    check(YR.ChatPlain(first[3]) == "[Guild] [Anna]: hi there", f"as plain text: no colour codes, a link as its words ({YR.ChatPlain(first[3])})")
    check(texts(3) == [YR.ChatLogLine(2)[3]] and len(texts(0)) == 2, "one chat window's lines, or all of them")
    check(len(texts(0, "blue sword")) == 1 and len(texts(0, "nothing like it")) == 0, "searched by the words in it, whatever their case")
    before = YR.ChatLogCount()
    lua.execute("""ChatFrame1:AddMessage("Zed says: twice") ChatFrame3:AddMessage("Zed says: twice") ChatFrame1:AddMessage("Zed says: twice")""")
    check(YR.ChatLogCount() == before + 3 and len(texts(0, "twice")) == 2 and len(texts(1, "twice")) == 2 and len(texts(3, "twice")) == 1,
          "all windows: a line two windows showed is one line there; said twice in one window it is two")
    names = [w[2] for w in YR.ChatLogWindows().values()]
    check(names == ["All windows", "General", "Guild"], f"the windows to pick from are the ones with lines ({names})")

    # the window: read as chat shows it, or as text to mark and copy
    check(YR.ChatLogOpen() is True and g.HeadstartChatLog is not None, "the window opens")
    lua.execute("""ChatFrame1:AddMessage("said while the window is open")""")
    check(YR.ChatLogCount() == 6, "a line said while it is open is kept too")

    # only the newest are kept
    g.YippRouteDB.chatLogMax = 200
    YR.ApplyParts()             # (the settings window says so itself when a setting changes)
    lua.execute("""for i = 1, 400 do ChatFrame1:AddMessage("line " .. i) end""")
    n = YR.ChatLogCount()
    check(200 <= n <= 240, f"past a fifth over the limit it is cut back to the limit ({n})")
    lua.execute("""Fire("PLAYER_LOGOUT")""")
    check(YR.ChatLogCount() == 200 and YR.ChatLogLine(200)[3] == "line 400" and len(g.HeadstartChatLog.text) == 200,
          "at logout exactly the newest so many are saved")
    shown, total = YR.ChatLogLines(0, "", 50)
    check(len(shown) == 50 and total == 200 and shown[50][3] == "line 400", "the window takes the newest of what matches, and says how many there are")

    # the next session: what was kept is there, with a mark where the session began
    # (a new session has new chat windows: the first session's hooks are not on them)
    fresh = """for i = 1, 3 do _G["ChatFrame" .. i] = setmetatable({}, getmetatable(UIParent)) end COMBATLOG = ChatFrame2 """
    lua.execute(fresh + """CLOCK = CLOCK + 86400""")
    YR2 = lua.table()
    for f in ("Core.lua", "ChatLog.lua"):
        lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)("Headstart", YR2)
    YR2.Style = lua.eval("STYLE")
    YR2.StartChatLog()
    YR2.partsReady = True
    g.YippRouteDB.chatLogRestoreLines = 20
    YR2.ApplyParts()
    back = list(lua.eval("rawget(ChatFrame1, 'said')").values())
    check(len(back) == 21 and back[19] == "line 400" and back[0] == "line 381" and back[20].startswith("---- earlier"),
          f"the chat window gets its last lines back, oldest first, and a line where the old text ends ({len(back)})")
    check(lua.eval("rawget(ChatFrame3, 'said')") is None and YR2.ChatLogCount() == 201,
          "a window with nothing kept gets nothing, and what was put back isn't kept a second time")
    # Leatrix Plus puts chat back after a reload too: ours doesn't, or every line would be there twice
    lua.execute("""LeaPlusDB = { RestoreChatMessages = 'On' } C_AddOns = C_AddOns or {}
        KEPT_LOADED = C_AddOns.IsAddOnLoaded C_AddOns.IsAddOnLoaded = function(n) return n == 'Leatrix_Plus' end""")
    YR2.EllesmereForget()
    check(YR2.ChatLogRestore() == 0 and YR2.OtherHas("chatRestore") == "Leatrix Plus",
          "Leatrix Plus's Restore chat messages on: ours puts nothing back (every line would be there twice)")
    lua.execute("LeaPlusDB = nil C_AddOns.IsAddOnLoaded = KEPT_LOADED")
    YR2.EllesmereForget()
    lua.execute("""ChatFrame1:AddMessage("hello again")""")
    kinds = [YR2.ChatLogLine(i)[2] for i in (200, 201, 202)]
    check(YR2.ChatLogCount() == 202 and kinds == [1, 0, 1], f"the next session: the old lines, a mark where it began, then the new ({kinds})")
    YR2.ApplyParts()
    YR2.ChatLogApply()
    check(YR2.ChatLogCount() == 202, "a setting changing later in the session is not a new session")
    YR2.ChatLogClear()
    check(YR2.ChatLogCount() == 0 and len(g.HeadstartChatLog.text) == 0, "Empty forgets every line")

    # not kept between sessions when that is turned off; off again keeps nothing
    lua.execute("""ChatFrame1:AddMessage("to be forgotten")""")
    g.YippRouteDB.chatLogKeep = False
    lua.execute(fresh)
    YR3 = lua.table()
    for f in ("Core.lua", "ChatLog.lua"):
        lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)("Headstart", YR3)
    YR3.Style = lua.eval("STYLE")
    YR3.StartChatLog()
    YR3.partsReady = True
    YR3.ApplyParts()
    check(YR3.ChatLogCount() == 0, "'Keep it between sessions' off: the log starts empty")
    lua.execute("""ChatFrame1:AddMessage("kept for now")""")
    g.YippRouteDB.chatLog = False
    YR3.ApplyParts()
    lua.execute("""ChatFrame1:AddMessage("off now")""")
    check(YR3.ChatLogCount() == 0 and len(g.HeadstartChatLog.text) == 1, "turned off: nothing more is kept")
    lua.execute(fresh)
    YR4 = lua.table()
    for f in ("Core.lua", "ChatLog.lua"):
        lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)("Headstart", YR4)
    YR4.StartChatLog()
    check(g.HeadstartChatLog is None, "off at a login: what was left in the saved file is dropped, not read in every time")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
