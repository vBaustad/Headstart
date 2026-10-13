"""live_move.py on a stand-in client in a temp folder: the rehearsal moves the settings folder aside as it
is, the move then reads from there into the made-new one, and restore puts everything back byte for byte.

    python tools/smoke_live_move.py
"""
import contextlib
import hashlib
import io
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import live_move as lm  # noqa: E402

FAILS = []


def check(name, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + name + (("  " + str(detail)) if detail and not ok else ""))
    if not ok:
        FAILS.append(name)


def put(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def tree(root):
    """Every file under root with what is in it, as one comparable thing."""
    out = {}
    for base, _, files in os.walk(root):
        for f in files:
            p = os.path.join(base, f)
            out[os.path.relpath(p, root).replace(os.sep, "/")] = hashlib.sha1(open(p, "rb").read()).hexdigest()
    return out


def run(*args):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        code = lm.main(list(args))
    return code, buf.getvalue()


def main():
    tmp = tempfile.mkdtemp(prefix="live_move_")
    try:
        beta = (tmp + "/client").replace(os.sep, "/")
        lm.BETA, lm.BACKUPS = beta, (tmp + "/backups").replace(os.sep, "/")
        game = {"on": False}
        lm.running = lambda: game["on"]
        acct = beta + "/WTF/Account/101117295#1"
        put(acct + "/SavedVariables/Headstart.lua", 'YippRouteDB = {\n\t["real"] = true,\n}\n')
        put(acct + "/SavedVariables/Headstart_Options.lua", "HeadstartScanDB = {\n}\n")
        put(acct + "/SavedVariables/Other.lua", "OtherDB = {\n}\n")
        put(acct + "/bindings-cache.wtf", "bind SPACE JUMP\n")
        put(acct + "/edit-mode-cache-account.txt", "5 38 1 7 default\n")
        put(acct + "/Realm/Char/SavedVariables/Headstart.lua", "HeadstartJourney = {\n}\n")
        REAL = ['SET synchronizeSettings "0"', 'SET portal "EU"', 'SET agentUID "wow_classic_beta"', 'SET graphicsQuality "7"',
                'SET Sound_MasterVolume "0.15"', 'SET maxFPS "160"', 'SET GxMaximize "1"', 'SET CACHE-WQST-QuestV2RecordCount "7771"',
                'SET textLocale "enUS"', 'SET rawMouseEnable "1"']
        put(beta + "/WTF/Config.wtf", chr(10).join(REAL) + chr(10))
        before = tree(beta + "/WTF")

        print("rehearse")
        game["on"] = True
        code, out = run("rehearse")
        check("refused while the game runs", code == 1 and os.path.isdir(beta + "/WTF") and not os.path.isdir(lm.kept()), out)
        check("and kept no copy for a rehearsal that did not start", not os.path.isdir(lm.BACKUPS))
        game["on"] = False
        code, out = run("rehearse")
        check("moved the folder aside", code == 0 and not os.path.exists(beta + "/WTF") and os.path.isdir(lm.kept()), out)
        check("as it was, every file", tree(lm.kept()) == before)
        kept_copies = sorted(os.listdir(lm.BACKUPS))
        check("a copy was kept first", len(kept_copies) == 1 and tree(lm.BACKUPS + "/" + kept_copies[0]) == before, kept_copies)
        code, out = run("rehearse")
        check("a second rehearsal is refused, nothing moved", code == 1 and tree(lm.kept()) == before, out)

        print("the client as new")
        code, out = run("check", beta)
        check("check: no account folder yet", code == 2 and "no account folder yet" in out, out)
        code, out = run("go", beta)
        check("go: nothing to copy into before the first login", code == 1 and not os.path.exists(beta + "/WTF"), out)
        # the first login: the game makes the folders, and Headstart (installed) writes an empty saved file
        put(acct + "/SavedVariables/Headstart.lua", "YippRouteDB = {\n}\n")
        put(acct + "/bindings-cache.wtf", "")
        NEW = ['SET portal "US"', 'SET agentUID "wow_classic_forever"', 'SET graphicsQuality "3"', 'SET gxmaximize "0"',
               'SET CACHE-WQST-QuestV2RecordCount "1"', 'SET maxFPS "160"', 'SET hwDetect "1"']
        put(beta + "/WTF/Config.wtf", chr(10).join(NEW) + chr(10))
        code, out = run("check", beta)
        check("check: the new file is not the beta's", code == 2 and "DIFFERS" in out and "--replace" in out, out)
        code, out = run("plan", beta, "--replace")
        check("plan reads from the folder moved aside", "WTF.kept" in out and "a rehearsal is on" in out, out)
        check("plan writes nothing", open(acct + "/SavedVariables/Headstart.lua").read() == "YippRouteDB = {\n}\n")
        code, out = run("go", beta)
        check("go without --replace leaves the new file", "left" in out and open(acct + "/SavedVariables/Headstart.lua").read() == "YippRouteDB = {\n}\n", out)
        game["on"] = True
        code, out = run("go", beta, "--replace")
        check("go refused while the game runs", code == 1 and open(acct + "/SavedVariables/Headstart.lua").read() == "YippRouteDB = {\n}\n", out)
        game["on"] = False
        code, out = run("go", beta, "--replace")
        real = open(lm.kept() + "/Account/101117295#1/SavedVariables/Headstart.lua").read()
        check("go --replace puts the real settings in", code == 0 and open(acct + "/SavedVariables/Headstart.lua").read() == real and '["real"]' in real, out)
        check("the one that was there is kept beside it", os.path.isfile(acct + "/SavedVariables/Headstart.lua.before-move"))
        check("only Headstart's files: no other addon's, no game file",
              not os.path.exists(acct + "/SavedVariables/Other.lua") and open(acct + "/bindings-cache.wtf").read() == "")
        code, out = run("check", beta)
        check("check: the settings are the beta's now", "the same file as the beta's" in out, out)
        check("the folder moved aside is untouched by all of it", tree(lm.kept()) == before)

        print("the machine's own settings (--config)")
        cfg = beta + "/WTF/Config.wtf"
        code, out = run("plan", beta, "--config")
        check("plan says what it would do and writes nothing", "would merge" in out and open(cfg).read().splitlines() == NEW, out)
        check("counted: 2 changed, 2 added, 1 the same, 5 left as the client's own",
              "2 changed, 2 added, 1 the same already; 5 left" in out, out)
        code, out = run("go", beta, "--config")
        got = dict(l.split(" ", 2)[1:] for l in open(cfg).read().splitlines())
        check("graphics, sound, frame rate and mouse are the beta's",
              got.get("graphicsQuality") == '"7"' and got.get("Sound_MasterVolume") == '"0.15"' and got.get("rawMouseEnable") == '"1"'
              and got.get("maxFPS") == '"160"', got)
        check("a setting spelled another way in the client's file is that line changed, not a second one",
              got.get("GxMaximize") == '"1"' and "gxmaximize" not in got, got)
        check("which game and region it is, its caches and its measure of the machine stay the client's own",
              got.get("portal") == '"US"' and got.get("agentUID") == '"wow_classic_forever"' and got.get("hwDetect") == '"1"'
              and got.get("CACHE-WQST-QuestV2RecordCount") == '"1"', got)
        check("and it is not told to stop keeping settings on the servers", "synchronizeSettings" not in got and "textLocale" not in got, got)
        check("the file that was there is kept beside it", open(cfg + ".before-move").read().splitlines() == NEW)
        code, out = run("go", beta, "--config")
        check("a second time changes nothing", "0 changed, 0 added, 5 the same already" in out, out)

        print("backup while a rehearsal is on")
        code, out = run("backup")
        copies = sorted(os.listdir(lm.BACKUPS))
        check("a second copy the same day gets the time in its name", code == 0 and len(copies) == 2 and len(copies[1]) > len(copies[0]), copies)
        check("and is the real settings, not the made-new ones", tree(lm.BACKUPS + "/" + copies[1]) == before)

        print("restore")
        game["on"] = True
        code, out = run("restore")
        check("refused while the game runs", code == 1 and os.path.isdir(lm.kept()), out)
        game["on"] = False
        code, out = run("restore")
        check("the real folder is back", code == 0 and not os.path.exists(lm.kept()) and tree(beta + "/WTF") == before, out)
        aside = [d for d in os.listdir(beta) if d.startswith("WTF.rehearsal-")]
        check("the rehearsal's folder is kept aside, not deleted", len(aside) == 1 and os.path.isfile(f"{beta}/{aside[0]}/Config.wtf"), aside)
        check("the real Config.wtf is as it was", open(beta + "/WTF/Config.wtf").read().splitlines() == REAL)
        code, out = run("restore")
        check("restore with no rehearsal on does nothing", code == 1 and tree(beta + "/WTF") == before, out)
        check("with no rehearsal on, the move reads from the client's own folder again", lm.source_wtf() == beta + "/WTF")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("FAILED: " + ", ".join(FAILS) if FAILS else "all ok")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
