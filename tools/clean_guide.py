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
    "too much map clutter for the boar meat step"). The step and its loot count stay."""
    parts = re.split(r"\n(?=[ \t]*step\b)", text)   # upstream has a " step" here and there
    for k, step in enumerate(parts):
        gotos = re.findall(r"^\s*\.goto [^\n]*$", step, re.M)
        if (gotos and all(re.search(r",0\s*(--.*)?$", g) for g in gotos)
                and re.search(r"^\s*#optional\b", step, re.M) and re.search(r"^\s*#completewith\b", step, re.M)
                and re.search(r"^\s*\.collect\b", step, re.M) and re.search(r"^\s*\.mob\b", step, re.M)):
            parts[k] = re.sub(r"\n[ \t]*\.goto [^\n]*", "", step)
    return "\n".join(parts)
