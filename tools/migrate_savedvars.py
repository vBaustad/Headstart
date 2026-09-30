"""Carry saved data over from the addon's old name (YippRoute) to Headstart, once, with WoW closed.

    python tools/migrate_savedvars.py

WoW keeps an addon's saved data in a file named after the addon, per account and per character. The
variables inside keep their names (YippRouteDB, YippSetupDB, YippSetupCharDB), so copying the files is
all it takes. A Headstart file that already exists is never overwritten.
"""
import glob
import os
import shutil
import subprocess
import sys

WTF = "S:/Blizzard/World of Warcraft/_classic_beta_/WTF/Account"

running = subprocess.run(["tasklist"], capture_output=True, text=True).stdout.lower()
if "wowb.exe" in running or "wow.exe" in running or "wowclassic" in running:
    sys.exit("WoW is running: close it first (it rewrites saved data when it exits).")

copied = 0
for old in glob.glob(WTF + "/**/SavedVariables/YippRoute.lua", recursive=True):
    new = os.path.join(os.path.dirname(old), "Headstart.lua")
    if os.path.exists(new):
        print("kept (already there):", new)
        continue
    shutil.copy2(old, new)
    copied += 1
    print("copied:", new)
print(copied, "file(s) copied")
