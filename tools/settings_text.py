"""Your Headstart settings as a text, made from a saved file - without the game.

    python tools/settings_text.py [saved file] [text to write]

The saved file is WTF/Account/<your account>/SavedVariables/Headstart.lua in a client's folder (the
live client's, unless another is named; the beta's last one is kept in forever-data/backup/wtf). The text is the same one "Move settings" (/headstart transfer) writes
with Export, and is read back by its Import on any install: the live game, another computer.

For when the install the settings are in can no longer be logged into - the beta is closed a week
before the live game opens, so there is no moment at which both can be opened. The saved file is still
on the disk (keep a copy of the whole WTF folder: an uninstall may take it).

It runs the addon's own code (Headstart_Options/Transfer.lua) in Lua 5.1: the file is read by the
reader the game will use, and written by the writer the game uses, so what this makes is what Import
expects. Nothing is written but the text file. It then reads its own text back and says whether that
is the settings the file holds.
"""
import glob
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIVE = "S:/Blizzard/World of Warcraft/_forever_/WTF/Account/*/SavedVariables/Headstart.lua"


def main(args):
    source = args[0] if args else None
    if not source:
        found = sorted(glob.glob(LIVE), key=os.path.getmtime)
        if not found:
            print("no saved file found at", LIVE, "- name one.")
            return 1
        source = found[-1]
    target = args[1] if len(args) > 1 else os.path.join(os.path.dirname(os.path.abspath(source)), "headstart-settings.txt")
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        function time() return os.time() end
        function date(f, t) return os.date(f, t) end
        function InCombatLockdown() return false end
        WHO = "a saved file"
        YR = { CharKey = function() return WHO end, Print = function() end, Style = {} }
        HeadstartNS = YR
        YippRouteDB = {}
        function Same(a, b)
            if type(a) ~= type(b) then return false end
            if type(a) ~= "table" then return a == b end
            for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
            for k in pairs(b) do if a[k] == nil then return false end end
            return true
        end''')
    src = open(os.path.join(ROOT, "Headstart_Options", "Transfer.lua"), encoding="utf-8").read()
    lua.eval("function(src) local f = assert(loadstring(src, 'Transfer.lua')) f('Headstart_Options', {}) end")(src)
    both = lua.eval("function(t) local d, why = YR.TransferRead(t) return { d = d, why = why } end")
    saved = both(open(source, encoding="utf-8", errors="replace").read())
    if saved.d is None:
        print("not read:", saved.why)
        return 1
    g = lua.globals()
    g.YippRouteDB, g.YippSetupDB = saved.d.db, saved.d.setup
    text = g.YR.TransferExport()
    back = both(text)
    whole = back.d is not None and lua.eval("Same")(back.d.db, saved.d.db) and lua.eval("Same")(back.d.setup, saved.d.setup)
    if not whole:
        print("the text does not read back as the settings in the file: nothing written.", back.why or "")
        return 1
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    d = back.d
    print(f"read   {source}")
    print(f"wrote  {target}  ({len(text):,} letters)")
    print(f"       {d.settings} settings, {d.profiles} bar profiles, {d.macros} macros ({d.code} run code), {d.routes} of your own routes")
    print("       read back and compared: the same settings. Paste it into Headstart's Move settings on the other install.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
