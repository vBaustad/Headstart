"""Smoke test of the bank deposit (Bank.lua) against a fake WoW API, in Lua 5.1 (lupa).

    python tools/smoke_bank.py      (exit code 1 on any failure; tools/smoke.py runs it too)

A Tailor with Mining opens the bank: what a profession of theirs crafts with stays, other mats go,
recipes go only when they can't be learned yet, and quest items, dynamite, what the route needs and
AutoFeed's food never go. Then: Shift as the bank opens, a full bank, the bank closing half way,
each setting, and the button.
"""
import os
import sys

import lupa.lua51 as lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# itemID: (class, subclass)
ITEMS = {
    2589: (7, 5),      # Linen Cloth: Tailoring uses it -> stays for a tailor
    2770: (7, 7),      # Copper Ore: Mining smelts it -> stays for a miner
    2449: (7, 9),      # Earthroot: Alchemy only -> goes
    2318: (7, 6),      # Light Leather: Tailoring uses it too -> stays
    4357: (7, 2),      # Rough Blasting Powder: Explosives -> never goes, even with "all"
    2672: (7, 8),      # Stringy Wolf Meat: Cooking only -> goes... unless the route needs it
    2406: (9, 1),      # Pattern for Leatherworking (65): no Leatherworking -> goes
    2598: (9, 2),      # Pattern: Tailoring at 25, a tailor at 50 -> stays (learnable)
    4292: (9, 2),      # Pattern: Tailoring above the tailor's skill -> goes
    5011: (12, 0),     # a quest item -> never goes
    4536: (0, 5),      # Shiny Red Apple: not a mat at all -> stays
    2835: (7, 7),      # Rough Stone: AutoFeed (pretend) keeps it
}


def run():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
FRAMES, TICKERS, AFTER, NOW = {}, {}, {}, 0
local Obj
Obj = { __call = function() return setmetatable({}, Obj) end }
Obj.__index = function(t, k)
    local v = rawget(Obj, k)
    if v then return v end
    local child = setmetatable({}, Obj); rawset(t, k, child); return child
end
function Obj.Show(self) rawset(self, "_shown", true) end
function Obj.Hide(self) rawset(self, "_shown", false) end
function Obj.IsShown(self) return rawget(self, "_shown") ~= false end
function Obj.SetShown(self, on) rawset(self, "_shown", on and true or false) end
function Obj.SetScript(self, what, fn) rawset(self, "_" .. what, fn) end
function Obj.SetText(self, t) rawset(self, "_text", t) end
function Obj.GetText(self) return rawget(self, "_text") end
function Obj.RegisterEvent(self, e) rawset(self, "_ev", rawget(self, "_ev") or {}) self._ev[e] = true end
function CreateFrame(_, name, parent) local f = setmetatable({}, Obj) table.insert(FRAMES, f) if name then _G[name] = f end return f end
UIParent = CreateFrame()
BankFrame = CreateFrame()
GameTooltip = CreateFrame()
function Fire(event, ...) for _, f in ipairs(FRAMES) do if rawget(f, "_ev") and f._ev[event] and rawget(f, "_OnEvent") then f._OnEvent(f, event, ...) end end end
C_Timer = {
    After = function(_, fn) table.insert(AFTER, fn) end,
    NewTicker = function(_, fn) local t = { fn = fn, Cancel = function(self) self.dead = true end } table.insert(TICKERS, t) return t end,
}
function RunAfter() local l = AFTER AFTER = {} for _, fn in ipairs(l) do fn() end end
function Tick(n) for _ = 1, n do for _, t in ipairs(TICKERS) do if not t.dead then t.fn() end end end end
COMBAT, SHIFT = false, false
function InCombatLockdown() return COMBAT end
function IsShiftKeyDown() return SHIFT end
NUM_BAG_SLOTS = 4
CLASS = {}
C_Item = { GetItemInfoInstant = function(id) local c = CLASS[id] if not c then return nil end return id, nil, nil, nil, nil, c[1], c[2] end }
-- bags[bag][slot] = itemID; the bank takes BANKROOM stacks
BAGS, BANK, BANKROOM = {}, {}, 99
C_Container = {
    GetContainerNumSlots = function(bag) return bag <= 4 and 16 or 0 end,
    GetContainerItemInfo = function(bag, slot)
        local id = BAGS[bag] and BAGS[bag][slot]
        if not id then return nil end
        return { itemID = id, stackCount = 5, isLocked = false }
    end,
    UseContainerItem = function(bag, slot)
        if #BANK >= BANKROOM then return end            -- the game says the bank is full; nothing moves
        table.insert(BANK, BAGS[bag][slot])
        BAGS[bag][slot] = nil
    end,
}
-- a Tailor (50) and Miner (30)
SKILLS = { [197] = 50, [186] = 30 }
C_SkillInfo = { GetSkillLineInfoByID = function(id)
    local r = SKILLS[id]
    return { name = "skill " .. id, isHeader = false, rank = r or 0, maxRank = 75 }
end }
KNOWN = {}
function IsPlayerSpell(id) return KNOWN[id] == true end
-- AutoFeed, as LibForever would carry it
local providers = { AutoFeedConsumables = { Keep = function(id) return id == 2835 and "AutoFeed: your macros use it" or nil end } }
function LibStub(name, silent) return { GetData = function(n) return providers[n] end } end
PRINTS = {}
-- the mailbox
MailFrame = CreateFrame()
CURSOR, LETTER, SENT, POSTAGE_EACH = nil, {}, {}, 30
ME = "Mainchar"
function UnitName() return ME end
function GetRealmName() return "Forever" end
function UnitFactionGroup() return "Alliance" end
C_Container.PickupContainerItem = function(bag, slot) CURSOR = { bag = bag, slot = slot } end
function ClickSendMailItemButton(i)
    if not CURSOR then return end
    LETTER[i] = BAGS[CURSOR.bag][CURSOR.slot]
    BAGS[CURSOR.bag][CURSOR.slot] = nil
    CURSOR = nil
end
local attach = ClickSendMailItemButton
function ClickSendMailItemButton(i, clear)
    if clear then LETTER[i] = nil return end   -- a right-click takes the attachment back
    attach(i)
end
function CursorHasItem() return CURSOR ~= nil end
function ClearCursor() CURSOR = nil end
function GetSendMailItem(i) return LETTER[i] and "x" or nil end
function GetSendMailPrice() local n = 0 for _ in pairs(LETTER) do n = n + 1 end return n * POSTAGE_EACH end
MONEY = 100000
function GetMoney() return MONEY end
function GetCoinTextureString(c) return c .. "c" end
function SendMail(to, subject) local l = {} for _, v in pairs(LETTER) do table.insert(l, v) end table.insert(SENT, { to = to, items = l }) LETTER = {} end
YippRouteDB = {}
SlashCmdList = {}
strsplit = function() end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
''')
    YR = lua.table()
    for f in ("Core.lua", "Data/Crafting.lua", "Bank.lua", "Mail.lua"):
        chunk = lua.eval("function(c, n) return assert(loadstring(c, n)) end")(
            open(os.path.join(ROOT, f), encoding="utf-8").read(), f)
        chunk("Headstart", YR)
    g = lua.globals()
    lua.execute("function YR_PRINT(m) table.insert(PRINTS, m) end")
    YR.Print = g.YR_PRINT
    # the route still needs the wolf meat (when NEED_MEAT)
    lua.execute("NEED_MEAT = false")
    YR.RouteNeed = lua.eval("function(id) if id == 2672 and NEED_MEAT then return 4, 'Stocking Jetsteam' end end")
    for item, (c, sc) in ITEMS.items():
        g.CLASS[item] = lua.table(c, sc)
    C = YR.Crafting
    bad = 0

    def check(ok, what):
        nonlocal bad
        if not ok:
            bad += 1
            print("FAIL bank:", what)

    # the data the rules stand on (from the game's tables via Guildhall)
    check(C.recipeItems[2406] is not None and C.recipeItems[2406][1] == 165, "2406 is a Leatherworking recipe")
    for item in (2598, 4292):
        check(C.recipeItems[item] is not None and C.recipeItems[item][1] == 197, f"{item} is a Tailoring recipe")
    check(C.recipeItems[2598][2] <= 50 < C.recipeItems[4292][2],
          f"2598 is learnable at Tailoring 50 and 4292 not ({C.recipeItems[2598][2]}, {C.recipeItems[4292][2]})")
    check(197 in list(C.reagents[2589].values()) and 186 in list(C.reagents[2770].values()),
          "linen is a Tailoring reagent and copper ore a Mining one")
    check(not any(p in (197, 186) for p in C.reagents[2449].values()), "earthroot is not for Tailoring or Mining")

    def fill():
        lua.execute("BAGS = { [0] = {}, [1] = {} } BANK = {} PRINTS = {} TICKERS = {}")
        for i, item in enumerate(ITEMS):
            g.BAGS[i // 16][i % 16 + 1] = item

    def banked():
        return sorted(g.BANK[i] for i in range(1, len(g.BANK) + 1))

    def visit(shift=False):
        g.SHIFT = shift
        g.Fire("BANKFRAME_OPENED")
        lua.execute("RunAfter()")
        lua.execute("Tick(40)")
        g.Fire("BANKFRAME_CLOSED")
        g.SHIFT = False

    YR.StartBank()
    fill()
    visit()
    check(banked() == [2406, 2449, 2672, 4292], f"a tailor-miner banks earthroot, wolf meat and the two recipes they can't learn: {banked()}")
    check(any("banked 2 stacks of crafting mats and 2 recipes" in g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)),
          f"chat says what went: {list(g.PRINTS.values())}")

    fill()
    lua.execute("NEED_MEAT = true")
    visit()
    check(2672 not in banked(), "meat the route still needs stays")
    lua.execute("NEED_MEAT = false")

    fill()
    visit(shift=True)
    check(banked() == [], "Shift as the bank opens: nothing goes")

    fill()
    lua.execute("KNOWN[%d] = true" % C.recipeItems[2406][3])
    visit()
    check(2406 not in banked(), "a recipe you already know is left alone")
    lua.execute("KNOWN = {}")

    fill()
    g.YippRouteDB.bankMats = "all"
    visit()
    check(banked() == [2318, 2406, 2449, 2589, 2672, 2770, 4292], f"all mats: your own go too, dynamite and AutoFeed's stone don't: {banked()}")
    g.YippRouteDB.bankMats = "off"
    g.YippRouteDB.bankRecipes = False
    fill()
    visit()
    check(banked() == [], "mats off and recipes off: nothing goes")
    g.YippRouteDB.bankMats = None
    g.YippRouteDB.bankRecipes = None

    fill()
    g.YippRouteDB.bankAuto = False
    visit()
    check(banked() == [], "not when I open the bank: nothing goes by itself")
    g.Fire("BANKFRAME_OPENED")
    g.HeadstartBankButton._OnClick()
    lua.execute("Tick(40)")
    check(banked() == [2406, 2449, 2672, 4292], "the button banks the same at any time")
    g.Fire("BANKFRAME_CLOSED")
    g.YippRouteDB.bankAuto = None

    # a bank with room for two stacks: two go, then it stops and says so
    fill()
    g.BANKROOM = 2
    visit()
    check(len(banked()) == 2, "a full bank: what fits goes")
    check(any("the bank is full" in g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)), "and chat says the bank is full")
    g.BANKROOM = 99

    # the bank closes after the first stack: no more clicks (a click away from the bank would USE the item)
    fill()
    g.Fire("BANKFRAME_OPENED")
    lua.execute("RunAfter() Tick(2)")
    g.Fire("BANKFRAME_CLOSED")
    n = len(banked())
    lua.execute("Tick(20)")
    check(len(banked()) == n and n >= 1, "nothing is clicked once the bank has closed")

    # Forever's bank (the Vanilla BankFrame) isn't a "Banker" to the interaction manager: moves still go
    lua.execute("C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function() return false end } Enum = Enum or {} Enum.PlayerInteractionType = { Banker = 8 }")
    fill()
    lua.execute("BankFrame:Show() PRINTS = {}")
    visit()
    check(len(banked()) >= 1 and not any("closed before" in g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)),
          f"the interaction manager says no banker: the bank window is open, so it banks anyway ({len(banked())})")
    # the bank window gone mid-way (closed before BANKFRAME_CLOSED reaches us): it stops at once
    fill()
    g.Fire("BANKFRAME_OPENED")
    lua.execute("RunAfter() BankFrame:Hide() Tick(20)")
    check(len(banked()) == 0, f"the bank window closed: nothing is clicked ({banked()})")
    g.Fire("BANKFRAME_CLOSED")
    lua.execute("BankFrame:Show() C_PlayerInteractionManager = nil")

    # the newer interaction event opens it too
    fill()
    g.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
    lua.execute("RunAfter() Tick(40)")
    g.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8)
    # ---- Mail to my alt -------------------------------------------------------------------------
    YR.StartMail()
    def mailed():
        out = []
        for i in range(1, len(g.SENT) + 1):
            items = g.SENT[i]["items"]
            out += [items[j] for j in range(1, len(items) + 1)]
        return sorted(out)

    fill()
    lua.execute("SENT = {} PRINTS = {}")
    g.Fire("MAIL_SHOW")
    lua.execute("RunAfter()")
    check(len(g.SENT) == 0, "no alt named, not sent by itself: nothing")
    g.HeadstartMailButton._OnClick()
    check(any("name the alt" in p for p in [g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)]), "the button asks for a name")
    # Forever mail needs the full name: name and surname ("Please enter a full character name" otherwise)
    YR.SetMailRecipient("bankalt smith")
    check(YR.MailRecipient() == "Bankalt Smith", f"the full name is kept, tidied: {YR.MailRecipient()}")
    YR.SetMailRecipient("Bankalt-Smith")
    check(YR.MailRecipient() == "Bankalt Smith", f"a dash between them is the same: {YR.MailRecipient()}")
    YR.SetMailRecipient("  bankalt ")
    check(YR.MailRecipient() is None and YR.MailRecipientMissingSurname() == "Bankalt",
          f"just a name Headstart can't complete: not used - the surname is missing ({YR.MailRecipient()})")
    lua.execute("SENT = {} PRINTS = {}")
    g.HeadstartMailButton._OnClick()
    said = [g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)]
    check(len(g.SENT) == 0 and any("surname too" in p for p in said), f"nothing sent, and chat says the surname is missing: {said}")
    lua.execute("YippRouteDB.runs = { ['Bankalt-Smith'] = {} }")
    check(YR.MailRecipient() == "Bankalt Smith", f"one of your characters it knows: the surname filled in: {YR.MailRecipient()}")
    YR.SetMailRecipient("bankalt")
    check(YR.MailRecipient() == "Bankalt Smith", "typed as just the name: saved with the surname")
    YR.SetMailRecipient("bankalt")
    lua.execute("HeadstartMailButton:SetText('old')")
    YR.SetMailRecipient("bankalt")
    lbl = g.HeadstartMailButton.GetText(g.HeadstartMailButton)
    check(lbl == "Send to Bankalt Smith", f"the button's label follows the name at once: {lbl}")
    # a letter the game refuses with only a message on screen: it stops, and the button works again
    g.HeadstartMailButton._OnClick()
    check(len(g.SENT) == 1, "a letter goes")
    g.Fire("UI_ERROR_MESSAGE", 1, "Please enter a full character name.")
    said = [g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)]
    check(any("full name" in p for p in said), f"the refusal stops it and says why: {said[-1:]}")
    fill()
    lua.execute("SENT = {}")
    g.HeadstartMailButton._OnClick()
    check(len(g.SENT) == 1, "and the button works again, not stuck waiting")
    lua.execute("RunAfter()")            # no answer at all: the 10 s give-up
    fill()
    lua.execute("SENT = {} PRINTS = {}")
    g.HeadstartMailButton._OnClick()
    check(len(g.SENT) == 1, "no answer from the game: it gave up, and a new try goes")
    lua.execute("RunAfter()")
    fill()
    lua.execute("SENT = {} PRINTS = {}")
    g.HeadstartMailButton._OnClick()
    check(len(g.SENT) == 1 and g.SENT[1]["to"] == "Bankalt Smith", "one letter to Bankalt Smith")
    g.Fire("MAIL_SEND_SUCCESS")
    lua.execute("RunAfter()")
    check(mailed() == [2406, 2449, 2672, 4292], f"the bank's rule: earthroot, wolf meat, the two recipes: {mailed()}")
    said = [g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)]
    check(any("mailed 4 stacks to Bankalt Smith (1 letter, 120c postage)" in p for p in said), f"chat says what went: {said}")
    g.Fire("MAIL_CLOSED")

    # more than twelve: two letters, the second only once the first went
    lua.execute("BAGS = { [0] = {}, [1] = {} } SENT = {} PRINTS = {}")
    for i in range(14):
        g.BAGS[i // 16][i % 16 + 1] = 2449
    g.Fire("MAIL_SHOW")
    g.HeadstartMailButton._OnClick()
    check(len(g.SENT) == 1 and len(g.SENT[1]["items"]) == 12, "twelve to a letter")
    g.Fire("MAIL_SEND_SUCCESS")
    lua.execute("RunAfter()")
    check(len(g.SENT) == 2 and len(g.SENT[2]["items"]) == 2, "the rest in a second letter, after the first went")
    g.Fire("MAIL_SEND_SUCCESS")
    lua.execute("RunAfter()")
    g.Fire("MAIL_CLOSED")

    # soulbound never, your list always, nothing to yourself, auto with Shift, postage
    lua.execute("BAGS = { [0] = {}, [1] = {} } SENT = {}")
    g.BAGS[0][1] = 2589            # linen: a tailor keeps it...
    g.BAGS[0][2] = 2449
    YR.SetMailCustom(2589, True)   # ...but it's on the list
    lua.execute("""local get = C_Container.GetContainerItemInfo
        C_Container.GetContainerItemInfo = function(bag, slot)
            local i = get(bag, slot)
            if i and bag == 0 and slot == 2 then i.isBound = true end
            return i
        end""")
    g.Fire("MAIL_SHOW")
    g.HeadstartMailButton._OnClick()
    g.Fire("MAIL_SEND_SUCCESS")
    lua.execute("RunAfter()")
    check(mailed() == [2589], f"the list sends linen; a soulbound stack stays: {mailed()}")
    g.Fire("MAIL_CLOSED")
    lua.execute("C_Container.GetContainerItemInfo = nil")
    lua.execute("""C_Container.GetContainerItemInfo = function(bag, slot)
        local id = BAGS[bag] and BAGS[bag][slot]
        if not id then return nil end
        return { itemID = id, stackCount = 5, isLocked = false }
    end""")
    YR.SetMailCustom(2589, False)

    fill()
    lua.execute("SENT = {} ME = 'Bankalt'")
    g.Fire("MAIL_SHOW")
    check(not g.HeadstartMailButton.IsShown(g.HeadstartMailButton), "on the alt itself: no button")
    g.HeadstartMailButton._OnClick()
    check(len(g.SENT) == 0, "and nothing mailed to yourself")
    g.Fire("MAIL_CLOSED")
    lua.execute("ME = 'Mainchar'")

    fill()
    g.YippRouteDB.mailAuto = True
    lua.execute("SENT = {} SHIFT = true")
    g.Fire("MAIL_SHOW")
    lua.execute("RunAfter() SHIFT = false")
    check(len(g.SENT) == 0, "sent as the mailbox opens, but not with Shift")
    g.Fire("MAIL_CLOSED")
    lua.execute("SENT = {}")
    g.Fire("MAIL_SHOW")
    lua.execute("RunAfter()")
    check(len(g.SENT) == 1, "and without Shift, it goes as the mailbox opens")
    g.Fire("MAIL_CLOSED")
    g.YippRouteDB.mailAuto = None

    fill()
    lua.execute("SENT = {} MONEY = 50 PRINTS = {}")
    g.Fire("MAIL_SHOW")
    g.HeadstartMailButton._OnClick()
    check(len(g.SENT) == 0 and any("postage" in g.PRINTS[i] for i in range(1, len(g.PRINTS) + 1)),
          "not enough for the postage: nothing sent, and chat says why")
    g.Fire("MAIL_CLOSED")
    lua.execute("MONEY = 100000")
    return bad


if __name__ == "__main__":
    sys.exit(1 if run() else 0)
