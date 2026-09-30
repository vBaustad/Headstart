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
import re

NEVER = {"sod", "skip"}          # filter words that are never true on Forever
ALWAYS = {"!sod"}                # and ones that always are


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


def _tag(line):
    """For a tag line: "drop" (the line), "kill" (the step) or None (keep)."""
    s = line.strip()
    m = re.match(r"#(\w+)\s*(.*)$", s)
    if not m:
        return None
    name, arg = m.group(1), m.group(2)
    cond = " << " in arg
    if name == "season":
        seasons = re.split(r"[,;\s]+", arg.split("<<")[0].strip())
        if "0" in seasons:
            return "drop"
        if cond:
            raise ValueError("conditional #season without season 0: " + s)
        return "kill"
    if name in ("hardcore", "ssf"):
        if cond:
            raise ValueError("conditional #" + name + ": " + s)
        return "kill"
    if name in ("softcore", "ah"):
        return "drop"
    return None


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
    for block in steps:
        first = _line(block[0])
        dead = first is None
        kept = [first]
        for ln in block[1:]:
            s = ln.strip()
            t = _tag(ln)
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
            if (last_kept and any(l.strip() == "#completewith next" for l in last_kept)
                    and not any(l.strip() == "#completewith next" for l in block)):
                raise ValueError("removed step follows a #completewith next: " + block[0])
            continue
        def acts(ls):
            return any(l.strip() and not l.strip().startswith(("#", "--")) for l in ls)
        if acts(block[1:]) and not acts(kept[1:]):
            raise ValueError("step left with nothing to do: " + block[0])
        out.extend(kept)
        last_kept = kept

    text = "\n".join(out)
    for label in gone_labels:
        if re.search(r"\b" + re.escape(label) + r"\b", text):
            raise ValueError("removed step's label is still used: " + label)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text
