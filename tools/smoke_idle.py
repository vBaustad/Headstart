"""What Headstart costs with nothing turned on: a new install's login, counted.

    python tools/smoke_idle.py           (exit code 1 when a budget is broken; tools/smoke.py runs it too)
    python tools/smoke_idle.py --list    (print what is registered, to see where a number comes from)

A new install has every feature that acts or draws off, the routes off and Character setup off. This
loads what Headstart.toc loads (not the load-on-demand addons), logs in, and counts what is left
running: the events listened for, the tickers, the frames made, the hooks put on the game. Then it
fires every event a thousand times and measures the memory that makes.

The budgets are a ratchet: they are what the addon does today, and a change that makes a new install
listen for more, tick more or allocate more fails here. Lower them when the addon gets leaner; never
raise one without saying in the commit why a new install has to pay for it.

Uses smoke.py's fake game (everything above the line where it loads the addon).
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Events that fire many times a minute in ordinary play. A new install listens for none of them.
HOT = {
    "UNIT_AURA", "UNIT_COMBAT", "UNIT_HEALTH", "UNIT_POWER_UPDATE", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_STATS",
    "COMBAT_LOG_EVENT_UNFILTERED", "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN",
    "PLAYER_XP_UPDATE", "PLAYER_MONEY", "PLAYER_TARGET_CHANGED", "PLAYER_SWING", "PLAYER_SWING_RANGE_UPDATE",
    "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "SPELLS_CHANGED", "UI_ERROR_MESSAGE", "UPDATE_INVENTORY_DURABILITY",
    "CHAT_MSG_LOOT", "CHAT_MSG_MONEY", "CHAT_MSG_SYSTEM", "CHAT_MSG_SKILL", "CHAT_MSG_COMBAT_XP_GAIN",
    "CHAT_MSG_COMBAT_FACTION_CHANGE", "CHAT_MSG_WHISPER", "CHAT_MSG_ADDON", "UPDATE_MOUSEOVER_UNIT", "CURSOR_CHANGED",
    "MODIFIER_STATE_CHANGED", "ACTIONBAR_SLOT_CHANGED", "GET_ITEM_INFO_RECEIVED", "PLAYER_EQUIPMENT_CHANGED",
    "UNIT_INVENTORY_CHANGED", "ZONE_CHANGED", "UPDATE_EXHAUSTION", "QUEST_DATA_LOAD_RESULT",
}

# The ratchet (see the top of the file). Two logins are counted:
#   "off"   everything switched off: quality of life off, routes off, Character setup off, no minimap
#           button. This is the proof that every part is free while off: only Headstart's own loader
#           listens (for addons loading), and nothing ticks, draws or allocates.
#   "new"   a new install as it comes: what is on by default (the camp icon, the flight timer, the
#           instance tracker, one-line reminders, tooltips) and nothing else.
BUDGET = {
    "off": {"hot": 0, "events": 1, "tickers": 0, "onupdate": 0, "frames": 1, "hooks": 0, "kb": 0},
    # frames stays 15. It went to 16 on 2026-10-09 for a child frame that gave the camp icon a
    # smaller mouse area; SetHitRectInsets does the same without being a frame, so the raise was
    # undone the same day rather than kept. Budgets only go down.
    # Raised on 2026-10-13 for Journey, which the owner asked to have on for a new install: a journey can
    # only be told if it was counted from the start, and it shows nothing while it counts. What it costs
    # is what the raise is: one ticker (a look a second), one frame, 17 events of which three are hot
    # (CHAT_MSG_LOOT, CHAT_MSG_COMBAT_XP_GAIN and the player's own UNIT_SPELLCAST_SUCCEEDED, each a short
    # handler), and two hooks (the jump, Repair all). Money is read at the look, not listened for, to
    # keep PLAYER_MONEY out of it. Before: hot 6, events 33, tickers 0, frames 15, hooks 2.
    # hooks 4 -> 5 the same day: the messages you send are counted by one hook on the game's send
    # function (the kind of chat only), which costs less than listening to every chat event would.
    # Down the same day: reward picking, the bank and mail buttons and the routes' automation start off
    # (a new install acts for you in nothing), so their events, frames and the reward hook are not there.
    # Was: events 50, frames 16, hooks 5, kb 2.
    # Raised later that day for Skip cinematics, which the owner asked to have on for a new install
    # ("svaert faa ser cinematic med mindre de er nye. og da bruker de ikke denne addonen"): one frame and
    # one event, CINEMATIC_START, which comes once on a new character and otherwise never. Before: events
    # 41, frames 13.
    "new": {"hot": 9, "events": 42, "tickers": 1, "onupdate": 0, "frames": 14, "hooks": 4, "kb": 1},
}
OFF = "{ qolOff = true, routes = false, setupOn = false, quiet = 2, minimapButton = false, logging = false, showSplits = false }"


def measure(saved="nil"):
    src = open(os.path.join(ROOT, "tools", "smoke.py"), encoding="utf-8").read()
    env = {"__name__": "smoke_head", "__file__": os.path.join(ROOT, "tools", "smoke.py")}
    exec(compile(src.split("YR = lua.table()")[0], "smoke.py (head)", "exec"), env)
    lua = env["lua"]
    # count what the fake game is asked for
    lua.execute("""
        HOOKN, ONUPDATE, LATER = 0, {}, {}
        local was = hooksecurefunc
        hooksecurefunc = function(...) HOOKN = HOOKN + 1 return was(...) end
        local meta = getmetatable(CreateFrame("Frame"))
        FRAMES = {}
        -- who made it: the file whose code asked (for --list)
        local function Who()
            for level = 3, 12 do
                local info = debug.getinfo(level, "S")
                if not info then break end
                if info.short_src:find("%.lua") then return info.short_src:match("([%w_]+%.lua)") end
            end
            return "?"
        end
        local make = CreateFrame
        CreateFrame = function(...) local f = make(...) rawset(f, "who", Who()) return f end
        local tick = C_Timer.NewTicker
        C_Timer.NewTicker = function(...) local t = tick(...) t.who = Who() return t end
        local set = rawget(meta, "SetScript")
        rawset(meta, "SetScript", function(self, what, fn)
            if what == "OnUpdate" then ONUPDATE[self] = fn or nil elseif what == "OnEvent" then set(self, what, fn) end
        end)
        rawset(meta, "HookScript", function() HOOKN = HOOKN + 1 end)
        C_Timer.After = function(_, fn) LATER[#LATER + 1] = fn end
        function RunLater() for _ = 1, 6 do local l = LATER LATER = {} for _, fn in ipairs(l) do pcall(fn) end end end
        YippRouteDB, YippSetupDB, YippSetupCharDB = SAVED, nil, nil
    """.replace("SAVED", saved))
    YR = lua.table()
    toc = [l.strip().replace(chr(92), "/") for l in open(os.path.join(ROOT, "Headstart.toc"), encoding="utf-8")
           if l.strip().endswith(".lua") and not l.startswith("#") and not l.startswith("Libs")]
    load = lua.eval("function(c, n) return assert(loadstring(c, n)) end")
    for f in toc:
        load(open(os.path.join(ROOT, f), encoding="utf-8").read(), f)("Headstart", YR)
    lua.execute("""Fire("ADDON_LOADED", "Headstart") Fire("PLAYER_LOGIN") Fire("PLAYER_ENTERING_WORLD", true, false) RunLater()""")
    g = lua.globals()
    events = lua.eval("""(function()
        local out = {}
        for _, f in ipairs(FRAMES) do for e in pairs(f.ev or {}) do out[#out + 1] = e end end
        table.sort(out)
        return out
    end)()""")
    events = list(events.values())
    got = {
        "events": len(events),
        "hot": len([e for e in events if e in HOT]),
        "tickers": lua.eval("(function() local n = 0 for _, t in ipairs(TICKERS) do if not t.dead then n = n + 1 end end return n end)()"),
        "onupdate": lua.eval("(function() local n = 0 for _ in pairs(ONUPDATE) do n = n + 1 end return n end)()"),
        "frames": lua.eval("#FRAMES"),
        "hooks": g.HOOKN,
    }
    # a thousand rounds of every event listened for, and of the tickers: what memory does that make?
    lua.execute("""
        local names, seen = {}, {}
        for _, f in ipairs(FRAMES) do for e in pairs(f.ev or {}) do if not seen[e] then seen[e] = true names[#names + 1] = e end end end
        local skip = { PLAYER_LOGOUT = true, ADDON_LOADED = true, PLAYER_ENTERING_WORLD = true, PLAYER_LOGIN = true }
        local function Round()
            for _, e in ipairs(names) do if not skip[e] then pcall(Fire, e, "player", "x", 1, 1) end end
            for _, t in ipairs(TICKERS) do if not t.dead then pcall(t.fn) end end
            for f, fn in pairs(ONUPDATE) do pcall(fn, f, 0.016) end
            for i = #LATER, 1, -1 do LATER[i] = nil end        -- (emptied, not made anew: that would be the test's own garbage)
        end
        for _ = 1, 20 do Round() end              -- whatever is made once (caches, lazily built tables)
        collectgarbage("collect") collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 1000 do Round() end
        IDLE_KB = collectgarbage("count") - before
        collectgarbage("restart")
    """)
    got["kb"] = round(g.IDLE_KB)
    by = lua.eval("""(function()
        local out = {}
        for _, f in ipairs(FRAMES) do
            local who = rawget(f, "who") or "?"
            out[who] = out[who] or {}
            for e in pairs(f.ev or {}) do table.insert(out[who], e) end
            if ONUPDATE[f] then table.insert(out[who], "<OnUpdate>") end
        end
        for _, t in ipairs(TICKERS) do if not t.dead then out[t.who or "?"] = out[t.who or "?"] or {} table.insert(out[t.who or "?"], "<ticker>") end end
        local lines = {}
        for who, list in pairs(out) do table.sort(list) lines[#lines + 1] = who .. ": " .. (#list > 0 and table.concat(list, ", ") or "(a frame, nothing on it)") end
        table.sort(lines)
        return table.concat(lines, string.char(10))
    end)()""")
    return got, events, by


def run(listing=False):
    bad = 0
    for name, saved, what in (("off", OFF, "everything switched off"), ("new", "nil", "a new install as it comes")):
        got, events, by = measure(saved)
        failed = False
        for key in ("hot", "events", "tickers", "onupdate", "frames", "hooks", "kb"):
            ok = got[key] <= BUDGET[name][key]
            failed = failed or not ok
            print(("ok  " if ok else "FAIL"), f"{what}: {key} = {got[key]} (budget {BUDGET[name][key]})")
        bad += failed
        if listing or failed:
            print(by)
    return bad


if __name__ == "__main__":
    sys.exit(1 if run("--list" in sys.argv) else 0)
