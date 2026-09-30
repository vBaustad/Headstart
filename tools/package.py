"""Build a zip of YippRoute to send to someone: the addon as it runs, without the tools or git.

    python tools/package.py        -> releases/YippRoute-<version>.zip (next to this repo)

The zip holds a folder named YippRoute, so it unpacks straight into Interface/AddOns.
"""
import os
import re
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {"tools", ".git", "__pycache__"}
SKIP_FILES = {".gitignore"}

version = re.search(r"## Version: (\S+)", open(os.path.join(ROOT, "YippRoute.toc"), encoding="utf-8").read()).group(1)
out_dir = os.path.join(os.path.dirname(ROOT), "releases")
os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, f"YippRoute-{version}.zip")
n = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for folder, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for f in files:
            if f in SKIP_FILES:
                continue
            full = os.path.join(folder, f)
            z.write(full, os.path.join("YippRoute", os.path.relpath(full, ROOT)))
            n += 1
print(out, n, "files")
