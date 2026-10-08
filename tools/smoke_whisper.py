"""Smoke test of the whisper sound (Whisper.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_whisper.py      (exit code 1 on any failure; tools/smoke.py runs it too)

The list holds the game's sounds this client has and no others, and LibSharedMedia's when it's loaded;
a whisper plays the picked sound on the picked channel, once for a burst; nothing picked plays nothing;
Battle.net whispers can be left out; quality of life off plays nothing.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r"""
FRAMES = {}
local F = {}
F.__index = F
function F:RegisterEvent(e) self.ev = self.ev or {} self.ev[e] = true end
function F:UnregisterAllEvents() self.ev = nil end
function F:SetScript(_, fn) self.fn = fn end
function CreateFrame() local f = setmetatable({}, F) table.insert(FRAMES, f) return f end
function Fire(e, ...) for _, f in ipairs(FRAMES) do if f.ev and f.ev[e] and f.fn then f.fn(f, e, ...) end end end
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
floor = math.floor
YippRouteDB = {}
function print() end
NOW = 100
function GetTime() return NOW end
SOUNDKIT = { TELL_MESSAGE = 3081, RAID_WARNING = 8959, READY_CHECK = 8960 }
PLAYED = {}
function PlaySound(id, channel) PLAYED[#PLAYED + 1] = { "kit", id, channel } return true end
""")
    YR = lua.table()
    for f in ("Core.lua", "Whisper.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    YR.StartWhisper()
    # the login: from here on a part listens only while it is wanted, looked at again when a setting changes
    YR.partsReady = True
    YR.ApplyParts()
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    keys = lambda: [e[1] for e in YR.WhisperSounds().values()]
    check(keys() == ["off", "kit:TELL_MESSAGE", "kit:RAID_WARNING", "kit:READY_CHECK"],
          f"the list: None, then the game's sounds this client has and no others ({keys()})")
    lua.execute("Fire('CHAT_MSG_WHISPER', 'secret', 'someone')")
    check(len(g.PLAYED) == 0, "nothing picked: a whisper plays nothing")
    g.YippRouteDB.whisperSound = "kit:RAID_WARNING"
    YR.ApplyParts()            # as the settings window does after a change
    lua.execute("Fire('CHAT_MSG_WHISPER')")
    last = lambda: g.PLAYED[len(g.PLAYED)]
    check(len(g.PLAYED) == 1 and last()[2] == 8959 and last()[3] == "Master", "a whisper: the picked sound, on Master")
    lua.execute("Fire('CHAT_MSG_WHISPER') Fire('CHAT_MSG_WHISPER')")
    check(len(g.PLAYED) == 1, "two more in the same moment: one sound for the burst")
    lua.execute("NOW = NOW + 3 Fire('CHAT_MSG_BN_WHISPER')")
    check(len(g.PLAYED) == 2, "a Battle.net whisper three seconds on: played")
    g.YippRouteDB.whisperBNet = False
    YR.ApplyParts()            # as the settings window does after a change
    lua.execute("NOW = NOW + 3 Fire('CHAT_MSG_BN_WHISPER')")
    check(len(g.PLAYED) == 2, "Battle.net whispers turned off: not played")
    g.YippRouteDB.whisperChannel = "SFX"
    lua.execute("NOW = NOW + 3 Fire('CHAT_MSG_WHISPER')")
    check(last()[3] == "SFX", "another channel picked: played on it")
    # a sound file of your own
    lua.execute("FILES = {} function PlaySoundFile(f, ch) FILES[#FILES + 1] = f return f:find('whisper') ~= nil end")
    g.YippRouteDB.whisperFile = "AddOns/whisper.ogg"
    check(YR.WhisperFile() == "Interface\\AddOns\\whisper.ogg" and "file" in keys() and YR.WhisperSoundName("file") == "Your own file",
          f"a file of your own: written from Interface, slashes either way, and in the list ({YR.WhisperFile()})")
    check(YR.PlayWhisperSound("file") is True and g.FILES[1] == "Interface\\AddOns\\whisper.ogg", "and played")
    g.YippRouteDB.whisperFile = "Interface\\Sounds\\gone.ogg"
    check(YR.WhisperFile() == "Interface\\Sounds\\gone.ogg" and YR.PlayWhisperSound("file") is False, "a file the game hasn't: said so, not an error")
    g.YippRouteDB.whisperFile = None
    check("file" not in keys() and YR.PlayWhisperSound("file") is False, "none written: not in the list")
    lua.execute("PlaySoundFile = nil")
    g.YippRouteDB.whisperSound = "kit:NOT_A_SOUND"
    YR.ApplyParts()            # as the settings window does after a change
    check(YR.PlayWhisperSound() is False, "a sound this client doesn't have: not played, and says so")
    # LibSharedMedia loaded by another addon: its sounds are in the list and play as files
    lua.execute("""
LSM = { HashTable = function(self, kind) return kind == 'sound' and { Bell = 'Interface/Bell.ogg', None = 'x', Airhorn = 'Interface/Horn.ogg' } or {} end }
LibStub = setmetatable({}, { __call = function(_, name) return name == 'LibSharedMedia-3.0' and LSM or nil end })
function PlaySoundFile(file, channel) PLAYED[#PLAYED + 1] = { 'file', file, channel } return true end
""")
    check(keys()[-2:] == ["lsm:Airhorn", "lsm:Bell"], f"LibSharedMedia loaded: its sounds too, by name, without its 'None' ({keys()[-2:]})")
    g.YippRouteDB.whisperSound = "lsm:Bell"
    YR.ApplyParts()            # as the settings window does after a change
    check(YR.PlayWhisperSound() is True and last()[2] == "Interface/Bell.ogg" and YR.WhisperSoundName() == "Bell", "one of them picked: its file is played")
    g.YippRouteDB.qolOff = True
    YR.ApplyParts()            # as the settings window does after a change
    n = len(g.PLAYED)
    lua.execute("NOW = NOW + 3 Fire('CHAT_MSG_WHISPER')")
    check(len(g.PLAYED) == n, "quality of life off: nothing played")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
