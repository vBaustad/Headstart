"""Smoke test of the damage meter skin (DamageSkin.lua) against a fake of the game's meter, in Lua 5.1 (lupa).

    python tools/smoke_dmgskin.py      (exit code 1 on any failure; tools/smoke.py runs it too)

No look picked: the meter isn't looked for or touched. A look picked: the three buttons at one size at
the right, the timer left of them, the title at the left on one line, Blizzard's header art clear; the
game lays the window out again and we go over it again; turned off, every piece is back where the game
had it. No field is written on the game's frames.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FAKE = r"""
local Obj = {}
Obj.__index = function(t, k) return rawget(Obj, k) or function() return setmetatable({}, Obj) end end
WRITES = {}
Obj.__newindex = function(t, k, v) if rawget(t, "blizzard") then WRITES[#WRITES + 1] = tostring(k) end rawset(t, k, v) end
function Obj:SetPoint(...) local p = rawget(self, "points") or {} p[#p + 1] = { ... } rawset(self, "points", p) end
function Obj:ClearAllPoints() rawset(self, "points", {}) end
function Obj:GetNumPoints() return #(rawget(self, "points") or {}) end
function Obj:GetPoint(i) local p = (rawget(self, "points") or {})[i] return p[1], p[2], p[3], p[4], p[5] end
function Obj:SetSize(w, h) rawset(self, "size", { w, h }) end
function Obj:GetSize() local s = rawget(self, "size") or { 30, 30 } return s[1], s[2] end
function Obj:GetHeight() return 24 end
function Obj:GetFrameLevel() return 3 end
function Obj:SetAlpha(a) rawset(self, "alpha", a) end
function Obj:SetShown(on) rawset(self, "shown", on and true or false) end
function Obj:Show() rawset(self, "shown", true) end
function Obj:Hide() rawset(self, "shown", false) end
function Obj:SetTextColor(r, g, b) rawset(self, "colour", { r, g, b }) end
function Obj:SetWordWrap(on) rawset(self, "wrap", on) end
function Obj:GetFont() local f = rawget(self, "font") or { "Fonts/FRIZQT__.TTF", 14, "" } return f[1], f[2], f[3] end
function Obj:SetFont(file, size, flags) rawset(self, "font", { file, size, flags }) end
function Obj:SetColorTexture(r, g, b, a) rawset(self, "fill", { r, g, b, a }) end
function Obj:SetVertexColor(r, g, b, a) rawset(self, "tint", { r, g, b, a }) end
function Obj:SetAtlas(n) rawset(self, "atlas", n) end
function Obj:IsObjectType(kind) return rawget(self, "kind") == kind end
function Obj:SetDesaturated(on) rawset(self, "grey", on and true or false) end
function Obj:GetTextColor() local c = rawget(self, "colour") or { 1, 0.82, 0 } return c[1], c[2], c[3] end
function Obj:GetRegions() local r = rawget(self, "regions") if r then return unpack(r) end end
function Obj:RegisterEvent() end
function Obj:SetScript(w, fn) rawset(self, "_" .. w, fn) end
function Obj:HookScript() end
function Obj:IsShown() return rawget(self, "shown") ~= false end
FACES = 0
function Obj:CreateTexture() FACES = FACES + 1 return New("Texture") end
function Obj:SetTexture(t) rawset(self, "file", t) end
function New(kind) local o = setmetatable({}, Obj) rawset(o, "kind", kind or "Frame") return o end
BUTTONS = {}
function CreateFrame(kind) local f = New() if kind == "Button" then BUTTONS[#BUTTONS + 1] = f end return f end
GameTooltip = New()
function Piece(kind, point, x)
    local o = New(kind)
    rawset(o, "points", { { point, nil, point, x, 0 } })
    rawset(o, "blizzard", true)
    return o
end
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
floor = math.floor
YippRouteDB = {}
SAID = {}
function print(m) SAID[#SAID + 1] = tostring(m) end
function UnitClass() return "Paladin", "PALADIN" end
RAID_CLASS_COLORS = { PALADIN = { r = 0.96, g = 0.55, b = 0.73 } }
C_Timer = { After = function(_, fn) fn() end }
C_Texture = { GetAtlasInfo = function() return nil end }
function hooksecurefunc(t, name, fn)
    local old = rawget(t, name)
    rawset(t, name, function(...) old(...) fn(...) end)
end
function MakeMeter()
    local w = New()
    local header = Piece("Texture", "TOP", 0)
    local typeDrop = Piece("Frame", "CENTER", 0)
    rawset(typeDrop, "TypeName", Piece("FontString", "LEFT", 0))
    local session, settings, minimize = Piece("Frame", "LEFT", 100), Piece("Frame", "LEFT", 130), Piece("Frame", "LEFT", 160)
    local timer = Piece("FontString", "LEFT", 4)
    GEAR, LETTER = New("Texture"), New("FontString")
    rawset(settings, "regions", { GEAR })
    rawset(session, "regions", { LETTER })
    PIECES = { header = header, typeDrop = typeDrop, session = session, settings = settings, minimize = minimize, timer = timer }
    rawset(w, "GetHeader", function() return header end)
    rawset(w, "GetDamageMeterTypeDropdown", function() return typeDrop end)
    rawset(w, "GetSessionDropdown", function() return session end)
    rawset(w, "GetSettingsDropdown", function() return settings end)
    rawset(w, "GetMinimizeButton", function() return minimize end)
    rawset(w, "GetSessionTimerFontString", function() return timer end)
    rawset(w, "GetMinimizeContainer", function() return New() end)
    -- the game's own layout: the session button back where the game has it
    rawset(w, "RefreshLayout", function() session:ClearAllPoints() session:SetPoint("LEFT", nil, "LEFT", 100, 0) end)
    rawset(w, "blizzard", true)
    WINDOW = w
    DamageMeter = New()
    rawset(DamageMeter, "GetChildren", function() return w end)
end
"""


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(FAKE)
    YR = lua.table()
    for f in ("Core.lua", "DamageSkin.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    g = lua.globals()
    raw = lua.eval("function(o, k) return rawget(o, k) end")
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    YR.StartDamageSkin()
    YR.DamageSkinApply()
    check(YR.DamageSkinMode() == "off" and not YR.DamageSkinAvailable(), "no meter and no look: nothing, no error")
    lua.execute("MakeMeter()")
    P = g.PIECES
    YR.DamageSkinApply()
    check(raw(P.session, "points")[1][1] == "LEFT" and raw(P.header, "alpha") is None, "no look picked: the meter isn't touched")

    YR.SetDamageSkin("headstart")
    pts = lambda piece: raw(piece, "points")[1]
    check(pts(P.minimize)[1] == "RIGHT" and pts(P.minimize)[4] == -8 and pts(P.settings)[4] == -25 and pts(P.session)[4] == -59 and pts(P.typeDrop)[4] == -76,
          f"Headstart: one row at the right, evenly spaced, with room for reset between settings and session ({pts(P.minimize)[4]}, {pts(P.settings)[4]}, {pts(P.session)[4]}, {pts(P.typeDrop)[4]})")
    check(all(raw(P[k], "size")[1] == 14 for k in ("minimize", "settings", "session", "typeDrop")), "and all at one size")
    check(pts(P.timer)[1] == "RIGHT" and pts(P.timer)[4] == -96, f"the timer left of them, not in front of the title ({pts(P.timer)[4]})")
    check(pts(P.typeDrop.TypeName)[1] == "LEFT" and pts(P.typeDrop.TypeName)[4] == 8 and raw(P.typeDrop.TypeName, "wrap") is False,
          "the title at the left, on one line, while its dropdown is a button in the row")
    lua.execute("RESETS = 0 C_DamageMeter = { ResetAllCombatSessions = function() RESETS = RESETS + 1 end }")
    lua.execute("for _, b in ipairs(BUTTONS) do local click = rawget(b, '_OnClick') if click then click(b) end end")
    check(g.RESETS == 1, "the reset button in the row clears the meter")
    check(raw(P.header, "alpha") == 0, "Blizzard's header art is clear")
    check(raw(P.typeDrop.TypeName, "font")[2] == 11 and raw(P.timer, "font")[2] == 10, "the title and the timer at a smaller size, in their own font")
    tp = raw(P.typeDrop.TypeName, "points")
    check(len(tp) == 2 and tp[2][1] == "RIGHT" and tp[2][3] == "LEFT", "the title ends where the timer begins: cut short, not written over it")
    check(raw(g.GEAR, "alpha") == 0 and abs(raw(g.LETTER, "colour")[1] - 0.40) < 0.01,
          "Blizzard's own button art is clear, the session's letter kept and in the accent")
    check(g.FACES >= 4, f"each button has one plain icon of ours ({g.FACES} textures)")
    title = raw(P.typeDrop.TypeName, "colour")
    check(abs(title[1] - 0.40) < 0.01, "the title in the accent")
    g.YippRouteDB.dmgSkinClass = True
    YR.DamageSkinApply()
    check(abs(raw(P.typeDrop.TypeName, "colour")[2] - 0.55) < 0.01, "the class colour as the accent")

    # the game lays the window out again: we go over it
    g.WINDOW.RefreshLayout(g.WINDOW)
    check(pts(P.session)[1] == "RIGHT" and pts(P.session)[4] == -59, "the game lays it out again: put in order again")

    YR.SetDamageSkin("blizzard")
    check(abs(raw(P.typeDrop.TypeName, "colour")[2] - 0.82) < 0.01 and pts(P.minimize)[1] == "RIGHT", "Blizzard, tidied: the same order, the title in gold")

    YR.SetDamageSkin("off")
    check(pts(P.session)[1] == "LEFT" and pts(P.session)[4] == 100 and pts(P.minimize)[4] == 160 and pts(P.timer)[4] == 4
          and pts(P.typeDrop)[1] == "CENTER" and pts(P.typeDrop.TypeName)[4] == 0, "off: every piece back where the game had it")
    check(raw(P.session, "size")[1] == 30 and raw(P.header, "alpha") == 1, "its own sizes, and Blizzard's header art back")
    check(raw(g.GEAR, "alpha") == 1 and abs(raw(g.LETTER, "colour")[2] - 0.82) < 0.01, "Blizzard's own button art back")
    check(raw(P.typeDrop.TypeName, "font")[2] == 14 and raw(P.timer, "font")[2] == 14, "the title and the timer their own size again")
    g.WINDOW.RefreshLayout(g.WINDOW)
    check(pts(P.session)[1] == "LEFT", "and left alone from then on")
    errors = [m for m in g.SAID.values() if "hit an error" in m]
    check(errors == [], f"the skin ran without a fault of its own ({errors})")
    writes = [w for w in g.WRITES.values()]
    check(writes == [], f"no field of ours written on the game's frames ({writes})")
    g.YippRouteDB.qolOff = True
    g.YippRouteDB.dmgSkin = "headstart"
    check(YR.DamageSkinMode() == "off", "quality of life switched off: no look")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
