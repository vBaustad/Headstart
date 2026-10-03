"""Strip what only matters outside WoW: Forever from a RestedXP guide, so the route text is only our route.

    from clean_guide import clean
    text = clean(text)

RestedXP writes one guide for every ruleset and hides steps by tags. On Forever (season 0, not
hardcore, auction house on) these never show, so they are removed instead of carried along:

    #season N          dropped when N includes 0, the whole step when it does not
    #hardcore / #ssf   the whole step (hardcore-only and self-found-only steps)
    #softcore / #ah    the tag (their steps always show here)
    << sod, << skip    lines and steps only for Season of Discovery, or switched off upstream
    << !sod            the !sod part (always true here)
    .link              video links, and the "watch the video below" lines that point at them
    -- lines           upstream's commented-out lines (and --Season notes after a line)

Anything else it cannot decide raises, so an upstream change can't slip through unseen.
"""
import itertools
import re

# Filter words that are never true on Forever: RestedXP matches a game word only against the game it
# runs on ("FOREVER"), so older guides' TBC and Wrath lines never show here; "sod" is Season of
# Discovery, "skip" a step switched off upstream.
NEVER = {"sod", "skip", "tbc", "wotlk", "cata", "retail", "df", "mop",
         "draenei", "bloodelf"}   # (and no Draenei or Blood Elves on Forever)
ALWAYS = {"!" + w for w in NEVER}  # and their opposites, always true


def _filter(expr):
    """Evaluate a << class filter as far as Forever decides it.
    Returns None when it is never true, "" when always true, else the filter left over."""
    alts = []
    for alt in expr.split("/"):
        words = alt.split()
        if any(w.lower() in NEVER for w in words):
            continue
        words = [w for w in words if w.lower() not in ALWAYS]
        if not words:
            return ""
        alts.append(" ".join(words))
    if not alts:
        return None
    return "/".join(alts)


def _line(line):
    """The line with its filter settled, or None when it never shows."""
    body, sep, rest = line.rpartition(" << ")
    if not sep:
        return line
    expr, comment = rest, ""
    if " --" in rest:
        expr, comment = rest.split(" --", 1)
        comment = " --" + comment
    f = _filter(expr.strip())
    if f is None:
        return None
    if f == "":
        return body.rstrip() + comment
    if f == expr.strip():
        return line
    return body + " << " + f + comment


def _conditional(arg):
    """A hiding tag for some classes only ("... << Priest/Mage"): "drop" when that condition can never
    hold on Forever ("<< Rogue sod"), else ("exclude", the classes it hides the step from)."""
    f = _filter(arg.split("<<", 1)[1].strip())
    if f is None:
        return "drop"
    if f == "":
        return "kill"
    return ("exclude", f)


def _tag(line):
    """For a tag line: "drop" (the line), "kill" (the step) or None (keep)."""
    s = line.strip()
    m = re.match(r"#(\w+)\s*(.*)$", s)
    if not m:
        return None
    name, arg = m.group(1), m.group(2)
    cond = "<<" in arg
    if name == "season":
        seasons = re.split(r"[,;\s]+", arg.split("<<")[0].strip())
        if "0" in seasons:
            return "drop"
        if cond:
            return _conditional(arg)
        return "kill"
    if name in ("hardcore", "ssf"):
        if cond:
            return _conditional(arg)
        return "kill"
    if name in ("softcore", "ah"):
        return "drop"
    return None


def _goto(block):
    """A step's first .goto line, to tell where it happens."""
    return next((l.strip() for l in block if l.strip().startswith(".goto ")), None)


def _negate(expr):
    """not (a RestedXP filter), as a filter: "/" is or, a space is and, "!" is not.
    not (A B / C) = (!A or !B) and !C = "!A !C/!B !C"."""
    def neg(w):
        return w[1:] if w.startswith("!") else "!" + w
    choices = [[neg(w) for w in alt.split()] for alt in expr.split("/") if alt.strip()]
    alts = [" ".join(pick) for pick in itertools.product(*choices)]
    if len(alts) > 8:
        raise ValueError("can't leave out a class filter this complex: " + expr)
    return alts


def _exclude(step_line, expr):
    """step_line, shown only where expr (a filter like "Priest/Mage" or "NightElf !Druid") doesn't hold."""
    nots = _negate(expr)
    head, sep, filt = step_line.partition(" << ")
    comment = ""
    if " --" in filt:
        filt, comment = filt.split(" --", 1)
        comment = " --" + comment
    mine = [a.strip() for a in filt.split("/") if a.strip()] if sep else [""]
    alts = [(m + " " + n).strip() for m in mine for n in nots]
    return head.rstrip() + " << " + "/".join(alts) + comment


def clean(text):
    lines = text.split("\n")
    head, steps, cur = [], [], None
    for ln in lines:
        if re.match(r"step\b", ln):
            cur = [ln]
            steps.append(cur)
        elif cur is None:
            head.append(ln)
        else:
            cur.append(ln)

    out = []
    for ln in head:
        if _tag(ln) == "drop" or ln.strip().startswith("--"):
            continue
        ln = _line(ln)
        if ln is not None:
            out.append(ln)

    gone_labels = []
    last_kept = None
    pending = None           # a removed step that a "#completewith next" pointed at: its .goto, to check
    for block in steps:
        first = _line(block[0])
        dead = first is None
        filtered = dead          # a filter RestedXP settles at load (sod, skip): it never loads the step at all
        kept = [first]
        for ln in block[1:]:
            s = ln.strip()
            t = _tag(ln)
            if isinstance(t, tuple):
                # a tag for some classes only ("#season 2 << Priest/Mage"): on Forever those classes never
                # see the step, the rest always do -> the step's own filter leaves those classes out
                if not dead:
                    kept[0] = _exclude(kept[0], t[1])
                continue
            if t == "kill":
                dead = True
            if dead or t == "drop" or s.startswith("--") or s.startswith(".link ") or "the video below" in s:
                continue
            ln = re.sub(r" *--.*[Ss]eason.*$", "", ln)
            ln = _line(ln)
            if ln is not None:
                kept.append(ln)
        if dead:
            gone_labels += re.findall(r"#label (\S+)", "\n".join(block))
            # a step before it that ends "with the next step" would now end with a different one
            # (fine when the removed step itself ended with the next one: the chain just gets shorter)
            if (not filtered and last_kept and any(l.strip() == "#completewith next" for l in last_kept)
                    and not any(l.strip() == "#completewith next" for l in block)):
                # fine when the step after it is its twin at the same place (the self-found and the
                # auction-house versions of one purchase): the reminder now ends with that one
                pending = (block[0], _goto(block))
            continue
        def acts(ls):
            return any(l.strip() and not l.strip().startswith(("#", "--")) for l in ls)
        if acts(block[1:]) and not acts(kept[1:]):
            raise ValueError("step left with nothing to do: " + block[0])
        if pending:
            if not pending[1] or pending[1] != _goto(kept):
                raise ValueError("removed step follows a #completewith next: " + pending[0])
            pending = None
        out.extend(kept)
        last_kept = kept

    text = "\n".join(out)
    for label in gone_labels:
        if re.search(r"#label " + re.escape(label) + r"\b", text):
            continue        # a kept twin (the softcore version of a hardcore step) carries the same label
        # a step waiting for one that never shows here (self-found only) just doesn't wait
        text = re.sub(r"\n[ \t]*#requires " + re.escape(label) + r"[ \t]*(?=\n)", "", text)
        if re.search(r"\b" + re.escape(label) + r"\b", text):
            raise ValueError("removed step's label is still used: " + label)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text


SICK_FROM = 10


def no_sick_deathskips(text):
    """Every death skip step gets ".xp 10,1": RestedXP skips the step from level 10 on. On Forever the
    Spirit Healer gives 10 minutes of Resurrection Sickness (-75% stats and damage) from level 10, not
    from 11 at a minute a level as in Classic (github.com/ClassicWoWCommunity/forever-bugs/issues/25,
    open). Below 10 a death skip costs nothing but the durability; from 10 the route walks or hearths."""
    parts = re.split(r"\n(?=step\b)", text)
    for k, step in enumerate(parts):
        if re.search(r"^\s*\.deathskip\b", step, re.M) and not re.search(r"^\s*\.xp %d,1\b" % SICK_FROM, step, re.M):
            parts[k] = re.sub(r"^(\s*)(\.deathskip\b[^\n]*)$",
                              lambda m: f"{m.group(1)}{m.group(2)}\n{m.group(1)}.xp {SICK_FROM},1 -- none from level {SICK_FROM}: 10 min sickness on Forever",
                              step, count=1, flags=re.M)
    return "\n".join(parts)


def no_passing_pins(text):
    """Kill-as-you-pass steps (#optional and #completewith, loot from mobs, every .goto with radius 0:
    boar meat for Cooking and the like) lose their .goto lines. Each one was a pin with the step
    number on the map, six or more a step, for something you never walk to (the user, 2026-10-02:
    "too much map clutter for the boar meat step"). The step and its loot count stay.
    Their orange advice lines go too ("This will be used to level your Cooking later", "Don't go out of
    your way...", "You need 50 Cooking for..."): three or four lines a step on top of the kill line,
    in steps that sit in the window for half a zone (the user, same day: "litt voldsomt med
    tasks/info text"). Such a step with no .goto at all counts too."""
    parts = re.split(r"\n(?=[ \t]*step\b)", text)   # upstream has a " step" here and there
    for k, step in enumerate(parts):
        gotos = re.findall(r"^\s*\.goto [^\n]*$", step, re.M)
        if not (re.search(r"^\s*#optional\b", step, re.M) and re.search(r"^\s*#completewith\b", step, re.M)
                and re.search(r"^\s*\.mob\b", step, re.M) and re.search(r"^\s*>>(?!\|cRXP_WARN_)", step, re.M)):
            continue                                       # (and it keeps its kill line)
        if all(re.search(r",0\s*(--.*)?$", g) for g in gotos) and re.search(r"^\s*\.collect\b", step, re.M):
            step = re.sub(r"\n[ \t]*\.goto [^\n]*", "", step)
        if re.search(r"^\s*\.(collect|complete)\b", step, re.M):
            # the advice only: warnings about the mobs ("Be careful as they cast Rabies") stay
            step = re.sub(r"\n[ \t]*>>\|cRXP_WARN_(Don't go out of your way|This will be used|You need \d+|Save (any|all))[^\n]*",
                          "", step)
        parts[k] = step
    return "\n".join(parts)


MAIL_FROM = 10
MAIL_STEP = """step{cond}
    #optional
    >>|cRXP_WARN_At the mailbox by the inn: send your alt the mats and recipes Headstart picks, to clear bag space. Shows only when you have set an alt (Settings, QoL) and there's something to send|r
    .mailalt
    .xp <{lvl},1"""


def mail_stops(text):
    """A mailbox stop (.mailalt, MailStep.lua) after every hearthstone stop: the inn nearly always has
    a mailbox outside, and the route comes back to that town. From level 10 (bags fill with mats by
    then, and postage no longer competes with training); it skips itself with no alt set or nothing
    to send (the user, 2026-10-02: "in guide we can have steps to mail out some items so we clear space")."""
    parts = re.split(r"\n(?=step\b)", text)
    out = []
    for step in parts:
        out.append(step)
        if (re.match(r"step\b", step) and re.search(r"^\s*\.home\b", step, re.M) and ".mailalt" not in step
                and not re.search(r"^\s*#completewith\s+next\b", step, re.M)):   # "next" would become the mail stop
            first = step.split("\n", 1)[0]
            cond = first[len("step"):] if first.startswith("step <<") or first.startswith("step  <<") else ""
            out.append(MAIL_STEP.format(cond=cond.rstrip(), lvl=MAIL_FROM))
    return "\n".join(out)


def no_cooking_meat(text):
    """Steps whose only job is meat for Cooking skill (#optional, every .collect a skill-up line:
    ".collect 769,50,2178,1,0x20,cooking", no quest to take, hand in or work) go. They sat in the
    window across whole zones, two or three at once (to 10, then to 50), for meat you loot anyway
    (the user, 2026-10-02: "especially the chunk of boar meat"). Quest meat (Stocking Jetsteam) stays;
    the cooking itself is the Thelsamar stop and RestedXP's boat campfires. A label another kept step
    waits for (#requires) keeps its step."""
    parts = re.split(r"\n(?=[ \t]*step\b)", text)

    def meat_only(step):
        collects = re.findall(r"^\s*\.collect\s+([^\n]*)", step, re.M)
        return (re.search(r"^\s*#optional\b", step, re.M) and collects
                and all(",cooking" in c for c in collects)
                and re.search(r"^\s*\.mob\b", step, re.M)            # kill steps only: vendor stops (spices) stay
                and not re.search(r"^\s*\.(accept|turnin|complete)\b", step, re.M))

    drop = {k for k, s in enumerate(parts) if k and meat_only(s)}
    while True:
        needed = {lab for k, s in enumerate(parts) if k not in drop for lab in re.findall(r"#requires\s+(\S+)", s)}
        keep = {k for k in drop if set(re.findall(r"#label\s+(\S+)", parts[k])) & needed}
        if not keep:
            break
        drop -= keep
    return "\n".join(s for k, s in enumerate(parts) if k not in drop)


def short_ah(text):
    """RestedXP's auction house steps, shortened: optional, one line of what to buy and that the auction
    house can't be counted on at launch (the user, 2026-10-02: "auction house will NOT be reliable at
    launch, but we can mention it"), instead of five to ten lines; and no meat for Cooking skill (see
    no_cooking_meat). A step left with nothing to buy goes."""
    parts = re.split(r"\n(?=[ \t]*step\b)", text)
    out = [parts[0]]
    for step in parts[1:]:
        if not re.search(r"^\s*\.target Auctioneer\b", step, re.M):
            out.append(step)
            continue
        step = re.sub(r"\n[ \t]*\.collect [^\n]*,cooking[^\n]*(\n[ \t]*\.disablecheckbox)?", "", step)
        items = []
        for c in re.findall(r"^\s*\.collect [^\n]*?--\s*([^\n]+)$", step, re.M):
            name = re.sub(r"^Collect\s+", "", c.strip())
            name = re.sub(r"\s*\((x?\d+)\)$", lambda m: " x" + m.group(1).lstrip("x"), name)
            if name not in items:
                items.append(name)
        if not items:
            continue
        lines = step.split("\n")
        talk = next((l for l in lines if "Talk to" in l and l.strip().startswith(">>")), None)
        body = [l for l in lines if not l.strip().startswith(">>")]
        new = ([talk] if talk else []) + [
            "    >>|cRXP_BUY_Buy|r " + ", ".join(items),
            "    >>|cRXP_WARN_Only if it's on sale and cheap: don't count on the auction house at launch. Else skip this step|r"]
        at = next(i for i, l in enumerate(body) if l.strip().startswith(".")) if any(l.strip().startswith(".") for l in body) else len(body)
        # after the .goto lines, like RestedXP's own
        while at < len(body) and body[at].strip().startswith(".goto"):
            at += 1
        body[at:at] = new
        if not re.search(r"^\s*#optional\b", step, re.M):
            body.insert(1, "    #optional")
        out.append("\n".join(body))
    return "\n".join(out)


TRACKING = {2580, 2383, 2481}      # Find Minerals, Find Herbs, Find Treasure


def no_tracking_casts(text):
    """Steps that only say to cast a tracking spell (Find Minerals and the like) go: a buff/tracking
    addon keeps them up (the user, 2026-10-03: "dont recommend 'cast find minerals' i already have a
    buff addon"). A step that does anything else stays."""
    parts = re.split(r"\n(?=[ \t]*step\b)", text)
    out = [parts[0]]
    for step in parts[1:]:
        casts = {int(c) for c in re.findall(r"^\s*\.(?:cast|usespell)\s+(\d+)", step, re.M)}
        doing = re.search(r"^\s*\.(accept|turnin|complete|collect|goto|train \d+ >>|trainer|vendor|home|fp|fly)\b",
                          step, re.M)
        if casts and casts <= TRACKING and not doing:
            continue
        out.append(step)
    return "\n".join(out)
