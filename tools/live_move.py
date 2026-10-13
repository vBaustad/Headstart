"""The beta's settings into the live game's folder, for the day the live game opens.

    python tools/live_move.py backup
    python tools/live_move.py check <live client folder>
    python tools/live_move.py plan  <live client folder> [--account NAME] [--all-addons] [--game-files] [--addons]
    python tools/live_move.py go    <live client folder> [the same] [--replace]

The game keeps settings per installed client, under <client>/WTF/Account/<account>/. The beta is closed
a week before the live game opens, so the two are never open together: what is left of the beta is its
folder on the disk. This copies the account's saved files from there into the live client, so that the
first login there has every Headstart setting, bar profile and route - and a new character's first
login shows Character setup's window, where Apply both puts the bars, macros, key bindings and
interface on.

  backup   The beta's whole WTF folder copied to S:/forever-data/backup/wtf/classic_beta_<date>. Do this
           while the beta is still installed: an uninstall may take the folder with it. Never writes
           over an earlier copy.
  check    Looks at the live client as it stands and says what is ready: the version it runs and the
           interface number that makes (against the number in Headstart's TOC files: a mismatch lists
           the addon as out of date, which looks like lost settings and is not), the account folders it
           has, whether Headstart's saved file is in each and is the beta's, and whether the addon's
           folders are in its Interface/AddOns. Writes nothing. The live game is up some days before
           it opens, for reserving names: that is when this can be run, and everything it says can be
           put right before the first real login.
  plan     Says what `go` would copy where. Writes nothing.
  go       Copies. A file already there is left alone and said, unless --replace (the one that was
           there is then kept beside it as <name>.before-move).

  <live client folder>   e.g. "S:/Blizzard/World of Warcraft/_classic_forever_" - whatever the live
                         client's folder turns out to be called.
  --account NAME         The account folder in the live client. Not needed when the live client has
                         exactly one (start the game once, as far as the character list, and quit: that
                         makes it). The beta's is 101117295#1; the other live clients on this disk use
                         DONALD11, and the live game will most likely do the same.
  --all-addons           Every addon's saved file, not only Headstart's.
  --game-files           The game's own account files too: key bindings, account macros, settings and
                         Edit Mode layouts (bindings-cache.wtf, macros-cache.txt, config-cache.wtf,
                         edit-mode-cache-account.txt). The game may prefer what its servers hold over
                         these: Character setup's Apply both is the way that does not depend on that.
  --addons               Also links Headstart's folders into the live client's Interface/AddOns, as
                         they are linked in the beta's (directory junctions to the source).

The game must not be running: it writes its saved files when it closes, over whatever was put there.
(--another-client-is-running: the WoW that is open is not the one being copied into.)
"""
import datetime
import glob
import os
import shutil
import subprocess
import sys

BETA = "S:/Blizzard/World of Warcraft/_classic_beta_"
BACKUPS = "S:/forever-data/backup/wtf"
OURS = ("Headstart.lua", "Headstart_Options.lua")
GAME_FILES = ("bindings-cache.wtf", "macros-cache.txt", "config-cache.wtf", "edit-mode-cache-account.txt")
LINKS = ("Headstart", "Headstart_Options", "Headstart_Setup", "Headstart_Routes")


def source_wtf():
    """The beta's own folder while it is there (it has the last session in it); else the newest copy kept."""
    if glob.glob(BETA + "/WTF/Account/*/SavedVariables/Headstart.lua"):
        return BETA + "/WTF"
    kept = sorted(glob.glob(BACKUPS + "/classic_beta_*"))
    return kept[-1] if kept else BETA + "/WTF"


def source_account(wtf):
    """The account folder whose Headstart settings were saved last."""
    found = glob.glob(wtf + "/Account/*/SavedVariables/Headstart.lua")
    if not found:
        return None
    return os.path.dirname(os.path.dirname(max(found, key=os.path.getmtime)))


def running():
    try:
        out = subprocess.run(["tasklist"], capture_output=True, text=True, timeout=20).stdout.lower()
    except Exception:
        return False
    return any(name in out for name in ("wow.exe", "wowclassic.exe", "wowclassict.exe", "wowclassicb.exe", "wowb.exe", "wowt.exe"))


def interface_of(client):
    """The interface number the client's version makes (1.60.1 is 16001), with the version; None if not found."""
    try:
        flavor = open(client + "/.flavor.info", encoding="utf-8").read().split()[-1]
        rows = open(os.path.dirname(client) + "/.build.info", encoding="utf-8").read().splitlines()
    except OSError:
        return None, None, None
    head = [h.split("!")[0] for h in rows[0].split("|")]
    for row in rows[1:]:
        d = dict(zip(head, row.split("|")))
        if d.get("Product") == flavor and d.get("Version"):
            parts = d["Version"].split(".")
            try:
                return int(parts[0]) * 10000 + int(parts[1]) * 100 + int(parts[2]), d["Version"], flavor
            except (ValueError, IndexError):
                return None, d["Version"], flavor
    return None, None, flavor


def same_file(a, b):
    try:
        return os.path.getsize(a) == os.path.getsize(b) and open(a, "rb").read() == open(b, "rb").read()
    except OSError:
        return False


def check(args):
    rest = [a for a in args if not a.startswith("--")]
    if not rest:
        print("name the live client's folder.")
        return 1
    live = rest[0].rstrip("/\\")
    if not os.path.isdir(live):
        print(live, "is not there.")
        return 1
    ready = True
    number, version, flavor = interface_of(live)
    print(f"client   {live}  ({flavor or 'no .flavor.info'}{', version ' + version if version else ''})")
    # the interface number, against every TOC of ours (the ones in the client if they are there, else the source's)
    tocs = glob.glob(live + "/Interface/AddOns/Headstart*/*.toc") or glob.glob(BETA + "/Interface/AddOns/Headstart*/*.toc")
    for toc in sorted(tocs):
        said = [l.split(":", 1)[1] for l in open(toc, encoding="utf-8", errors="replace") if l.startswith("## Interface:")]
        have = [int(x) for x in said[0].replace(" ", "").strip().split(",") if x.isdigit()] if said else []
        if number is None:
            print(f"  ?      {os.path.basename(toc)} says {have}: the client's version could not be read, so this is not compared")
        elif number in have:
            print(f"  ok     {os.path.basename(toc)}: interface {number}, as the client's")
        else:
            ready = False
            print(f"  WRONG  {os.path.basename(toc)} says {have} and the client is {number}: the addon is listed as out of date"
                  f" until the TOC says {number} (or Load out of date AddOns is ticked on the character list)")
    # the addon's folders
    for name in LINKS:
        there = os.path.isdir(f"{live}/Interface/AddOns/{name}")
        if not there and name != "Headstart_Routes":
            ready = False
        print(f"  {'ok    ' if there else 'MISSING'} Interface/AddOns/{name}" + ("" if there else "  (`go --addons` links it)"))
    # the account folders, and the saved file in each
    src = source_account(source_wtf())
    there = [d for d in glob.glob(live + "/WTF/Account/*") if os.path.isdir(d) and os.path.basename(d) != "SavedVariables"]
    if not there:
        ready = False
        print("  NONE   no account folder yet: start the game once, as far as the character list, and quit")
    settled = False                 # one account folder with Headstart's settings in it is enough
    for d in sorted(there):
        f = d + "/SavedVariables/Headstart.lua"
        if not os.path.isfile(f):
            print(f"  EMPTY  {os.path.basename(d)}: no Headstart settings in it yet (`go` puts them there)")
        elif src and same_file(f, src + "/SavedVariables/Headstart.lua"):
            settled = True
            print(f"  ok     {os.path.basename(d)}: Headstart's settings are there, the same file as the beta's ({os.path.getsize(f):,} bytes)")
        else:
            when = datetime.datetime.fromtimestamp(os.path.getmtime(f)).strftime("%Y-%m-%d %H:%M")
            print(f"  DIFFERS {os.path.basename(d)}: Headstart settings are there but are not the beta's file (saved {when},"
                  f" {os.path.getsize(f):,} bytes): `go --replace` puts the beta's in, keeping this one beside it")
    if there and not settled:
        ready = False
    if len(there) > 1:
        print("         (more than one account folder: the one you log in with is the one that counts; name it with --account)")
    print("ready: log in, make the character, press Apply both." if ready else "not ready yet: see the lines above.")
    return 0 if ready else 2


def backup():
    src = BETA + "/WTF"
    if not os.path.isdir(src):
        print("no beta WTF folder at", src)
        return 1
    dst = f"{BACKUPS}/classic_beta_{datetime.date.today().isoformat()}"
    if os.path.exists(dst):
        print("already kept today:", dst, "(nothing written)")
        return 0
    os.makedirs(BACKUPS, exist_ok=True)
    shutil.copytree(src, dst)
    files = sum(len(f) for _, _, f in os.walk(dst))
    size = sum(os.path.getsize(os.path.join(b, f)) for b, _, fs in os.walk(dst) for f in fs)
    print(f"kept   {src}\n  as   {dst}  ({files} files, {size / 1e6:.0f} MB)")
    return 0


def move(args, write):
    flags = {a for a in args if a.startswith("--")}
    rest = [a for a in args if not a.startswith("--")]
    account = None
    if "--account" in args:
        account = args[args.index("--account") + 1]
        rest = [a for a in rest if a != account]
    if not rest:
        print("name the live client's folder.")
        return 1
    live = rest[0].rstrip("/\\")
    wtf = source_wtf()
    src = source_account(wtf)
    if not src:
        print("no Headstart settings found under", wtf)
        return 1
    print(f"from   {src}")
    if not os.path.isdir(live):
        print(f"       {live} is not there yet: nothing can be copied into it.")
        return 1
    if running():
        other = "--another-client-is-running" in flags
        print("       a WoW client is running: the game writes its saved files when it closes, over whatever is put there."
              + ("" if other else " Close it first (or, if it is another client than the one you copy into, say --another-client-is-running)."))
        if write and not other:
            return 1
    if not account:
        there = [d for d in glob.glob(live + "/WTF/Account/*") if os.path.isdir(d) and os.path.basename(d) != "SavedVariables"]
        if len(there) == 1:
            account = os.path.basename(there[0])
        else:
            print(f"       the live client has {len(there)} account folders ({', '.join(os.path.basename(d) for d in there) or 'none'}):"
                  " start the game once as far as the character list and quit, or name one with --account.")
            return 1
    dst = f"{live}/WTF/Account/{account}"
    print(f"to     {dst}")
    todo = []
    names = [os.path.basename(f) for f in glob.glob(src + "/SavedVariables/*.lua")] if "--all-addons" in flags else list(OURS)
    for name in sorted(names):
        if name.startswith("Blizzard_"):
            continue
        todo.append((f"{src}/SavedVariables/{name}", f"{dst}/SavedVariables/{name}"))
    if "--game-files" in flags:
        for name in GAME_FILES:
            todo.append((f"{src}/{name}", f"{dst}/{name}"))
    done = skipped = 0
    for a, b in todo:
        if not os.path.isfile(a):
            continue
        there = os.path.exists(b)
        size = os.path.getsize(a)
        if there and "--replace" not in flags:
            print(f"  left   {os.path.relpath(b, dst)}  (one is there already: --replace to put the beta's in its place)")
            skipped += 1
            continue
        print(f"  {'copy' if write else 'would copy'}   {os.path.relpath(b, dst)}  ({size:,} bytes){'  over the one there, kept as .before-move' if there else ''}")
        if write:
            os.makedirs(os.path.dirname(b), exist_ok=True)
            if there:
                shutil.copy2(b, b + ".before-move")
            shutil.copy2(a, b)
        done += 1
    if "--addons" in flags:
        for name in LINKS:
            link, here = f"{live}/Interface/AddOns/{name}", f"{BETA}/Interface/AddOns/{name}"
            target = os.path.realpath(here) if os.path.exists(here) else None
            if not target:
                continue
            if os.path.exists(link):
                print(f"  left   Interface/AddOns/{name}  (there already)")
                continue
            print(f"  {'link' if write else 'would link'}   Interface/AddOns/{name}  ->  {target}")
            if write:
                os.makedirs(os.path.dirname(link), exist_ok=True)
                subprocess.run(["cmd", "/c", "mklink", "/J", link.replace("/", "\\"), target], check=True, capture_output=True)
    print(f"{'copied' if write else 'to copy'}: {done}; left alone: {skipped}." + ("" if write else "  Nothing was written: `go` does it."))
    if write and done:
        print("Next: start the game, make your character, and on its first login press Apply both in Headstart's window.")
    return 0


def main(args):
    if not args or args[0] not in ("backup", "check", "plan", "go"):
        print(__doc__)
        return 1
    if args[0] == "backup":
        return backup()
    if args[0] == "check":
        return check(args[1:])
    return move(args[1:], args[0] == "go")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
