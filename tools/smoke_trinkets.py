"""Smoke test of trinkets and gear sets (Trinkets.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_trinkets.py      (exit code 1 on any failure; tools/smoke.py runs it too)

Swap trinkets for me: a used trinket gives way to the next ready one in the order, a higher one comes
back once ready, the 30 s a trinket gets as it goes on doesn't count as used, a trinket put on by hand
that isn't in the order is left alone, a slot switched off is left alone, nothing changes in a fight
(it waits for the end). Swap when mounted: the Carrot goes in and the trinket comes back. Gear sets:
by number or name, after the fight when asked in one.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
FRAMES, AFTER, TICKS = {}, {}, {}
local F = {}
F.__index = F
function F:RegisterEvent(e) self.ev = self.ev or {} self.ev[e] = true end
function F:SetScript(_, fn) self.fn = fn end
function CreateFrame() local f = setmetatable({}, F) table.insert(FRAMES, f) return f end
function Fire(e) for _, f in ipairs(FRAMES) do if f.ev and f.ev[e] and f.fn then f.fn(f, e) end end end
C_Timer = { After = function(_, fn) table.insert(AFTER, fn) end,
            NewTicker = function(_, fn) table.insert(TICKS, fn) return { Cancel = function() end } end }
function Tick() for _, fn in ipairs(TICKS) do fn() end end
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return s end
floor = math.floor
YippRouteDB, YippSetupCharDB = {}, {}
PRINTS = {}
function print(m) table.insert(PRINTS, m) end
NOW, COMBAT, MOUNTED, SWIMMING = 1000, false, false, false
function GetTime() return NOW end
function InCombatLockdown() return COMBAT end
function UnitIsDeadOrGhost() return false end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function GetCursorInfo() return nil end
function IsMounted() return MOUNTED end
function IsSwimming() return SWIMMING end
NUM_BAG_SLOTS = 0
-- items: [id] = { equipLoc, on-use }
ITEMS = { [1] = { "INVTYPE_TRINKET", true }, [2] = { "INVTYPE_TRINKET", true }, [3] = { "INVTYPE_TRINKET", false },
          [4] = { "INVTYPE_TRINKET", true }, [11122] = { "INVTYPE_TRINKET", false } }
WORN, BAG, CD = { [13] = nil, [14] = nil }, {}, {}       -- CD[id] = { start, duration }
function GetInventoryItemID(_, s) return WORN[s] end
function GetInventoryItemCooldown(_, s) local c = WORN[s] and CD[WORN[s]] return c and c[1] or 0, c and c[2] or 0, 1 end
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 8 or 0 end,
    GetContainerItemID = function(bag, slot) return BAG[slot] end,
    GetContainerItemCooldown = function(bag, slot) local c = BAG[slot] and CD[BAG[slot]] return c and c[1] or 0, c and c[2] or 0, 1 end,
}
EQUIPS = 0
C_Item = {
    GetItemInfoInstant = function(id) local i = ITEMS[id] return id, nil, nil, i and i[1] end,
    GetItemSpell = function(id) return ITEMS[id] and ITEMS[id][2] and "Use" or nil end,
    EquipItemByName = function(id, slot)
        for k, v in pairs(BAG) do
            if v == id then
                BAG[k] = WORN[slot] WORN[slot] = id EQUIPS = EQUIPS + 1
                CD[id] = CD[id] or {}
                -- going on: 30 s cooldown, unless it has a longer one running
                local c = CD[id]
                if ITEMS[id][2] and not ((c[1] or 0) + (c[2] or 0) - NOW > 30) then CD[id] = { NOW, 30 } end
                return
            end
        end
    end,
}
SETS = { { 7, "Tank" }, { 9, "Fishing" } }
USED_SET = nil
C_EquipmentSet = {
    GetEquipmentSetIDs = function() local o = {} for _, s in ipairs(SETS) do o[#o + 1] = s[1] end return o end,
    GetEquipmentSetInfo = function(id) for _, s in ipairs(SETS) do if s[1] == id then return s[2] end end end,
    UseEquipmentSet = function(id) USED_SET = id end,
}
''')
    YR = lua.table()
    for f in ("Core.lua", "Trinkets.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    YR.StartTrinkets()
    g = lua.globals()
    bad = 0

    def check(ok, what):
        nonlocal bad
        print(("ok  " if ok else "FAIL"), what)
        bad += not ok

    def worn():
        return (g.WORN[13], g.WORN[14])

    # your order: 1 (best), 2, then 3 (no use: always ready). Wearing 1 and 2, 3 in the bag.
    lua.execute("WORN[13] = 1 WORN[14] = 2 BAG[1] = 3 BAG[2] = 4")
    order = YR.TrinketDB().order
    for i, v in enumerate((1, 2, 3), start=1):
        order[i] = v
    lua.execute("Tick()")
    check(worn() == (1, 2) and g.EQUIPS == 0, f"both of the best two ready: nothing changes {worn()}")
    # you use trinket 1: a 2-minute cooldown. The first ready one in the order, 3, goes in.
    lua.execute("CD[1] = { NOW, 120 } Tick()")
    check(worn() == (3, 2), f"1 used: 3 (next ready in the order) goes in its slot {worn()}")
    lua.execute("NOW = NOW + 5 Tick()")
    check(worn() == (3, 2), f"a pass later: no swapping back and forth while 1 cools down {worn()}")
    # 1 is ready again: back in (the 30 s it then gets for going on isn't "used")
    lua.execute("NOW = NOW + 120 Tick()")
    check(worn() == (1, 2), f"1 ready again: back in, over the lower 3 {worn()}")
    lua.execute("NOW = NOW + 2 Tick()")
    check(worn() == (1, 2), f"its 30 s for going on doesn't count as used: it stays {worn()}")
    # a trinket you put on by hand that isn't in the order: left alone
    lua.execute("BAG[2] = nil BAG[2] = 2 WORN[14] = 4 CD[2] = nil Tick()")
    check(worn() == (1, 4), f"your own choice (4, not in the order) stays {worn()}")
    # a slot switched off: left alone even when its trinket is used
    lua.execute("WORN[14] = 2 BAG[2] = 4")
    YR.TrinketDB().auto[13] = False
    lua.execute("CD[1] = { NOW, 120 } Tick()")
    check(worn()[0] == 1, f"top slot switched off: 1 stays though it's used {worn()}")
    YR.TrinketDB().auto[13] = None
    # in a fight: nothing; when it ends, the swap
    lua.execute("COMBAT = true Tick()")
    check(worn()[0] == 1, "in a fight: no swap")
    lua.execute("COMBAT = false Tick()")
    check(worn()[0] == 3, f"after it: the swap {worn()}")
    # a swap asked for by hand in a fight waits for the end
    lua.execute("COMBAT = true")
    YR.TrinketEquip(4, 14)
    check(g.WORN[14] == 2, "Equip from the list in a fight: not yet")
    lua.execute("COMBAT = false Fire('PLAYER_REGEN_ENABLED')")
    check(g.WORN[14] == 4, "the fight ends: on it goes")

    # order editing
    YR.TrinketToggleList(4)
    check(list(YR.TrinketDB().order.values())[-1] == 4, "added to the list: at the end")
    YR.TrinketMove(4, -1)
    check(list(YR.TrinketDB().order.values()) == [1, 2, 4, 3], f"moved up one: {list(YR.TrinketDB().order.values())}")
    YR.TrinketToggleList(4)
    check(4 not in list(YR.TrinketDB().order.values()), "toggled again: off the list")

    # swap when mounted: the Carrot in the bottom slot, and the trinket back after
    g.YippRouteDB.trinketAuto = False
    lua.execute("WORN[13] = 1 WORN[14] = 2 BAG = { 3, 11122 } MOUNTED = true Tick()")
    check(g.WORN[14] == 11122, f"mounted: Carrot on a Stick in the bottom slot ({g.WORN[14]})")
    lua.execute("MOUNTED = false Tick()")
    check(g.WORN[14] == 2, f"off the mount: the trinket you wore is back ({g.WORN[14]})")
    g.YippRouteDB.trinketMount = False
    lua.execute("MOUNTED = true Tick()")
    check(g.WORN[14] == 2, "turned off: no Carrot")
    lua.execute("MOUNTED = false")

    # gear sets: by number, by name, and after a fight
    YR.UseGearSet("2")
    check(g.USED_SET == 9, "set 2: Fishing")
    YR.UseGearSet("tank")
    check(g.USED_SET == 7, "by name, any case: Tank")
    lua.execute("USED_SET = nil COMBAT = true")
    YR.UseGearSet("1")
    check(g.USED_SET is None, "in a fight: not yet")
    lua.execute("COMBAT = false Fire('PLAYER_REGEN_ENABLED')")
    check(g.USED_SET == 7, "the fight ends: the set goes on")
    YR.UseGearSet("nothing")
    check(any("You have: 1 Tank, 2 Fishing" in str(g.PRINTS[i]) for i in range(1, len(g.PRINTS) + 1)),
          "an unknown set: chat lists the ones you have")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
