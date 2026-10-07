"""Build a zip of Headstart to send to someone: the addon as it runs, without the tools or git.

    python tools/package.py        -> dist/Headstart-<version>.zip (git-ignored); upload it to CurseForge
                                      or attach it to a GitHub release

The zip holds a folder named Headstart, so it unpacks straight into Interface/AddOns.
"""
import os
import re
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {"tools", ".git", "__pycache__", "dist"}
SKIP_FILES = {".gitignore", "CHANGELOG.md", "files.txt"}

version = re.search(r"## Version: (\S+)", open(os.path.join(ROOT, "Headstart.toc"), encoding="utf-8").read()).group(1)
out_dir = os.path.join(ROOT, "dist")
os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, f"Headstart-{version}.zip")
n = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for folder, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            if f in SKIP_FILES:
                continue
            full = os.path.join(folder, f)
            rel = os.path.relpath(full, ROOT)
            # the window's addon is a folder of its own beside Headstart's (as .pkgmeta's move-folders does)
            top = "" if rel.split(os.sep)[0] in ("Headstart_Options", "Headstart_Setup") else "Headstart"
            z.write(full, os.path.join(top, rel))
            n += 1
print(out, n, "files")
