"""Write tools/forever_talents.json: every talent of every class, with the points it needs in lower tiers.

    python tools/fetch_talents.py

From foreverchanges.pro's talent calculator (one page a class). The client still carries Classic's
talent table, which is not Forever's trees: read from it, Holy Shock was a level-40 talent (it is 30)
and Blessing of Kings a talent at all (it is trained). The generators read this file instead:
a talent that needs N points in lower tiers can first be taken at level 10 + N (the first point comes
at 10, one a level). Run it again after a build that changes the trees, then the generators.
"""
import html
import json
import os
import re
import urllib.request

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "forever_talents.json")
CLASSES = ["warrior", "paladin", "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid"]


def main():
    out = {}
    build = None
    for c in CLASSES:
        req = urllib.request.Request("https://foreverchanges.pro/talents/" + c,
                                     headers={"User-Agent": "Mozilla/5.0 (Headstart tools/fetch_talents.py)"})
        text = urllib.request.urlopen(req, timeout=30).read().decode("utf-8")
        build = build or (re.search(r"1\.60\.\d+\.\d+", text) or [None])[0]
        talents = {}
        for m in re.finditer(r'<button data-talent-id="[^"]*"[^>]*?aria-label="([^"]*?), 0/(\d+) points?"([^>]*)>', text):
            name, points, rest = html.unescape(m.group(1)), int(m.group(2)), m.group(3)
            need = re.search(r"Requires (\d+) points in lower tiers", rest)
            talents[name] = {"needs": int(need.group(1)) if need else 0, "points": points}
        out[c.upper()] = talents
        print(c, len(talents))
    json.dump({"source": "foreverchanges.pro/talents", "build": build, "classes": out}, open(OUT, "w", encoding="utf-8"),
              indent=1, sort_keys=True)
    print("wrote", OUT, "build", build)


if __name__ == "__main__":
    main()
