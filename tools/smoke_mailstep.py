"""Smoke test of the .mailalt route step (MailStep.lua) against a fake RestedXP and Mail.lua, in Lua 5.1 (lupa).

    python tools/smoke_mailstep.py      (exit code 1 on any failure)
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
RXP = { functions = { events = {} } }
ME = "Radaid"
function UnitName() return ME end
''')
    YR = lua.table()
    chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
        open(os.path.join(ROOT, "MailStep.lua"), encoding="utf-8").read(), "MailStep.lua")
    chunk("Headstart", YR)
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    f = g.RXP.functions.mailalt
    check(f is not None and g.RXP.functions.events.mailalt is not None, "RestedXP gets .mailalt and its events")
    el = f(".mailalt", "")
    check(el.textOnly, "parses to a text-only element")
    lua.execute("STEP = { active = true }")
    el.step = g.STEP
    frame = lua.table(element=el)

    f(frame)
    check(g.STEP.completed and g.RXP.updateSteps, "no Mail.lua: the step skips itself")
    lua.execute("STEP.completed = nil; RXP.updateSteps = nil; TO = nil; PICK = { 1, 2, 3 }")
    YR.MailRecipient = lua.eval("function() return TO end")
    YR.MailPick = lua.eval("function() return PICK end")
    f(frame)
    check(g.STEP.completed, "no alt set: skips")
    lua.execute("STEP.completed = nil; TO = 'Radaid'")
    f(frame)
    check(g.STEP.completed, "the alt is yourself: skips")
    lua.execute("STEP.completed = nil; TO = 'Bankalt'")
    f(frame)
    check(not g.STEP.completed and "3 stacks to Bankalt" in str(el.text), f"something to send: shows, with how much: {el.text}")
    lua.execute("PICK = {}")
    f(frame)
    check(g.STEP.completed, "sent: done")
    lua.execute("STEP.completed = nil; STEP.active = false; PICK = { 1 }")
    f(frame)
    check(not g.STEP.completed, "not the active step: left alone")
    lua.execute("STEP.active = true; MailPick_err = true")
    YR.MailPick = lua.eval("function() error('boom') end")
    f(frame)
    check(g.STEP.completed, "Mail.lua erroring: skips, no error")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
