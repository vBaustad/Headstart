-- Macro helper: the macros every class ends up wanting, made by ticking what the button should do.
--   Pick a spell of your class and what its button should do besides casting it:
--     Pressing again doesn't turn it off   "/cast !Stealth": Stealth, a form, Auto Shot, a wand's Shoot -
--                                           spammed, it stays on
--     Under the mouse first                "[@mouseover,help,nodead][]": the friend (or enemy) the mouse is
--                                           over, else your target
--     Alt casts it on yourself             "[mod:alt,@player]"
--     Stop what you're casting first       "/stopcasting": a kick or a counterspell that goes off now
--     Leave your form first                "/cancelform": a heal out of Cat Form in one press
--     Switch to a stance first (warrior)   "/cast [nostance:1] Battle Stance; Charge": the first press
--                                           changes stance, the next casts
--   The macro's text is shown as you tick, and Make macro makes it - a macro of this character, with
--   the question-mark icon (the game shows the spell's own). It is then in the planner's Macros list
--   to put on a bar. Nothing here casts or presses anything: it writes macros.
--   Ready-made: a short list for your class of the ones people make most (a rogue's Pick Pocket with
--   an opener, a warrior's Charge from any stance...), each of which fills the choices in, or is a
--   text of its own. One whose spell your class hasn't got on this client isn't listed.
--   /headstart macro opens it; so does "Macro helper..." on the planner's Macros tab.
-- (part of the Headstart_Setup addon)
local YR = _G.HeadstartNS
local YS = YR.Setup
local S = YR.Style

local MACRO_MAX, NAME_MAX = 255, 16
local STANCES = { WARRIOR = { "Battle Stance", "Defensive Stance", "Berserker Stance" } }
local FORMS = { DRUID = true, SHAMAN = true, PRIEST = true }

local function Class() return (select(2, UnitClass("player"))) end

--- Whether this class has a spell by that name on this client (the planner's data).
local function Has(spell, class)
    class = class or Class()
    return ((YR.PlannerSpells or {})[class] or {})[spell] ~= nil or ((YR.PlannerGeneral or {})[class] or {})[spell] ~= nil
        or (YR.PlannerRacials or {})[spell] ~= nil
end
YS.MacroHas = Has

--- A macro's text for a spell and what its button should do: { keep, mouse ("help" or "harm"), self,
--- stop, attack, leave, stance (1-3, a warrior's), tip (false: no #showtooltip line) }.
function YS.MacroBuild(spell, o, class)
    o = o or {}
    local lines = {}
    if o.tip ~= false then lines[1] = "#showtooltip " .. spell end       -- (tip = false: no icon and tooltip line)
    if o.stop then lines[#lines + 1] = "/stopcasting" end
    if o.attack then lines[#lines + 1] = "/startattack" end
    if o.leave then lines[#lines + 1] = "/cancelform" end
    local cast = "/cast "
    local stance = o.stance and (STANCES[class or Class()] or {})[o.stance]
    if stance then cast = cast .. ("[nostance:%d] %s; "):format(o.stance, stance) end
    local where = ""
    if o.self then where = where .. "[mod:alt,@player]" end
    if o.mouse == "help" or o.mouse == "harm" then where = where .. ("[@mouseover,%s,nodead]"):format(o.mouse) end
    if where ~= "" then where = where .. "[] " end
    lines[#lines + 1] = cast .. where .. (o.keep and "!" or "") .. spell
    return table.concat(lines, "\n")
end

-- The ones people make most, gathered from the Classic class guides that agree with each other (Zockify,
-- Almar's Guides, Brian Koponen, Icy Veins, Wowhead; October 2026) and written here in our own words.
-- { label, spell, options } builds its text from the choices; { label, body = text, needs = { spells },
-- name = "..." } is a text of its own. One is listed only for a class that has every spell it needs.
-- Left out on purpose: anything with /focus (not known to exist on this client), anything that names an
-- item you may not carry (bandages, poisons, potions, weapon swaps), two spells on the same global
-- cooldown in one press (only the first would cast), old /script tricks, a druid's forms by number
-- (the numbers move when a form isn't learned), and totem sequences (they waste a cast when the
-- totems' times differ).
local RECIPES = {
    ROGUE = {
        { "Stealth that stays on", "Stealth", { keep = true } },
        { "Stealth, then Sap (one button)", body = "#showtooltip\n/cast [stealth] Sap; Stealth", needs = { "Stealth", "Sap" }, name = "Stl Sap" },
        { "Stealth, then Cheap Shot (one button)", body = "#showtooltip\n/cast [stealth] Cheap Shot; Stealth", needs = { "Stealth", "Cheap Shot" }, name = "Stl Cheap" },
        { "Stealth, then Ambush (one button)", body = "#showtooltip\n/cast [stealth] Ambush; Stealth", needs = { "Stealth", "Ambush" }, name = "Stl Ambush" },
        { "Stealth, then Garrote (one button)", body = "#showtooltip\n/cast [stealth] Garrote; Stealth", needs = { "Stealth", "Garrote" }, name = "Stl Garrote" },
        { "Pick Pocket, then Cheap Shot", body = "#showtooltip Cheap Shot\n/cast Pick Pocket\n/cast Cheap Shot", needs = { "Pick Pocket", "Cheap Shot" }, name = "PP Cheap Shot" },
        { "Pick Pocket, then Ambush", body = "#showtooltip Ambush\n/cast Pick Pocket\n/cast Ambush", needs = { "Pick Pocket", "Ambush" }, name = "PP Ambush" },
        { "Pick Pocket, then Garrote", body = "#showtooltip Garrote\n/cast Pick Pocket\n/cast Garrote", needs = { "Pick Pocket", "Garrote" }, name = "PP Garrote" },
        { "Pick Pocket, then Sap", body = "#showtooltip Sap\n/cast Pick Pocket\n/cast Sap", needs = { "Pick Pocket", "Sap" }, name = "PP Sap" },
        { "Sap in Stealth, Gouge out of it", body = "#showtooltip\n/cast [stealth] Sap; Gouge", needs = { "Sap", "Gouge" }, name = "Sap Gouge" },
        { "Vanish in combat, Stealth out of it", body = "#showtooltip\n/stopattack\n/cast [combat] Vanish; [nostealth] Stealth", needs = { "Vanish", "Stealth" }, name = "Vanish" },
        { "Kick, mouseover first", "Kick", { mouse = "harm" } },
        { "Blind, mouseover first", "Blind", { mouse = "harm" } },
        { "Gouge, mouseover first", "Gouge", { mouse = "harm" } },
        { "Riposte when it is up, else Sinister Strike", body = "#showtooltip Sinister Strike\n/cast Riposte\n/cast Sinister Strike", needs = { "Riposte", "Sinister Strike" }, name = "Riposte SS" },
        { "Cold Blood, then Eviscerate", body = "#showtooltip Eviscerate\n/cast Cold Blood\n/cast Eviscerate", needs = { "Cold Blood", "Eviscerate" }, name = "CB Evis" },
        { "Sap the nearest enemy player", body = "#showtooltip Sap\n/cleartarget\n/targetenemyplayer\n/cast Sap", needs = { "Sap" }, name = "Sap Finder" },
    },
    WARRIOR = {
        { "Charge out of combat, Intercept in combat", body = "#showtooltip\n/cast [nocombat,nostance:1] Battle Stance; [nocombat] Charge; [combat,nostance:3] Berserker Stance; [combat] Intercept",
          needs = { "Charge", "Intercept" }, name = "Charge Int" },
        { "Charge, from any stance", "Charge", { stance = 1 } },
        { "Intercept, from any stance", "Intercept", { stance = 3 } },
        { "Overpower, from any stance", "Overpower", { stance = 1 } },
        { "Mocking Blow, from any stance", "Mocking Blow", { stance = 1 } },
        { "Berserker Rage, from any stance", "Berserker Rage", { stance = 3 } },
        { "Pummel, from any stance", "Pummel", { stance = 3 } },
        { "Pummel, from any stance, mouseover first", body = "#showtooltip Pummel\n/cast [nostance:3] Berserker Stance; [@mouseover,harm,nodead][] Pummel", needs = { "Pummel" }, name = "Pummel MO" },
        { "Shield Bash, from any stance", "Shield Bash", { stance = 2 } },
        { "Taunt, from any stance", "Taunt", { stance = 2 } },
        { "Taunt, from any stance, mouseover first", body = "#showtooltip Taunt\n/cast [nostance:2] Defensive Stance; [@mouseover,harm,nodead][] Taunt", needs = { "Taunt" }, name = "Taunt MO" },
        { "Your stance's long cooldown", body = "#showtooltip\n/cast [stance:1] Retaliation; [stance:2] Shield Wall; [stance:3] Recklessness",
          needs = { "Retaliation", "Shield Wall", "Recklessness" }, name = "Big CD" },
    },
    DRUID = {
        { "Cat Form that stays on", "Cat Form", { keep = true } },
        { "Bear Form that stays on", "Bear Form", { keep = true } },
        { "Dire Bear Form that stays on", "Dire Bear Form", { keep = true } },
        { "Travel Form that stays on", "Travel Form", { keep = true } },
        { "Powershift: leave Cat Form and go back in", body = "#showtooltip Cat Form\n/cancelform\n/cast Cat Form", needs = { "Cat Form" }, name = "Powershift" },
        { "Travel Form, Aquatic Form in water", body = "#showtooltip\n/cast [swimming] Aquatic Form; Travel Form", needs = { "Travel Form", "Aquatic Form" }, name = "Travel" },
        { "Prowl that stays on", "Prowl", { keep = true } },
        { "Ravage from stealth, else Shred", body = "#showtooltip\n/cast [stealth] Ravage; Shred", needs = { "Ravage", "Shred" }, name = "Opener" },
        { "Pounce from stealth, else Shred", body = "#showtooltip\n/cast [stealth] Pounce; Shred", needs = { "Pounce", "Shred" }, name = "Pounce" },
        { "Healing Touch, out of any form", "Healing Touch", { leave = true, mouse = "help" } },
        { "Regrowth, out of any form", "Regrowth", { leave = true, mouse = "help" } },
        { "Rejuvenation, out of any form", "Rejuvenation", { leave = true, mouse = "help" } },
        { "Nature's Swiftness, then Healing Touch", body = "#showtooltip Healing Touch\n/cancelform\n/cast Nature's Swiftness\n/cast [@mouseover,help,nodead][] Healing Touch",
          needs = { "Nature's Swiftness", "Healing Touch" }, name = "NS Heal" },
        { "Innervate, out of any form", "Innervate", { leave = true, mouse = "help" } },
        { "Rebirth on a dead friend, mouseover first", body = "#showtooltip Rebirth\n/cancelform\n/cast [@mouseover,help,dead][] Rebirth", needs = { "Rebirth" }, name = "Rebirth" },
        { "Remove Curse, out of any form", "Remove Curse", { leave = true, mouse = "help" } },
        { "Abolish Poison, out of any form", "Abolish Poison", { leave = true, mouse = "help" } },
        { "Growl, mouseover first", "Growl", { mouse = "harm" } },
    },
    HUNTER = {
        { "Auto Shot that stays on", body = "#showtooltip Auto Shot\n/targetenemy [noexists][dead][help]\n/cast !Auto Shot", needs = { "Auto Shot" }, name = "Auto Shot" },
        { "Hunter's Mark and send the pet", body = "#showtooltip Hunter's Mark\n/petattack\n/cast Hunter's Mark", needs = { "Hunter's Mark" }, name = "Mark" },
        { "Raptor Strike and Mongoose Bite", body = "#showtooltip Raptor Strike\n/cast Raptor Strike\n/cast Mongoose Bite", needs = { "Raptor Strike", "Mongoose Bite" }, name = "Melee" },
        { "Feign Death now (stops your shots)", body = "#showtooltip Feign Death\n/stopattack\n/stopcasting\n/cast Feign Death", needs = { "Feign Death" }, name = "Feign" },
        { "Feign Death in combat, Freezing Trap out of it", body = "#showtooltip\n/stopattack\n/cast [combat] Feign Death; Freezing Trap", needs = { "Feign Death", "Freezing Trap" }, name = "FD Trap" },
        { "Scatter Shot, pet set to passive", body = "#showtooltip Scatter Shot\n/petpassive\n/cast Scatter Shot", needs = { "Scatter Shot" }, name = "Scatter" },
        { "Pet attack, mouseover first", body = "/petattack [@mouseover,harm,nodead][]", needs = { "Call Pet" }, name = "Pet Attack" },
        { "Pet back and passive", body = "/petfollow\n/petpassive", needs = { "Call Pet" }, name = "Pet Back" },
        { "Pet care: revive, mend or call", body = "#showtooltip\n/cast [@pet,dead] Revive Pet; [@pet,exists] Mend Pet; Call Pet", needs = { "Revive Pet", "Mend Pet", "Call Pet" }, name = "Pet Care" },
        { "Aspect of the Hawk that stays on", "Aspect of the Hawk", { keep = true } },
        { "Aspect of the Cheetah, right-click for Pack", body = "#showtooltip\n/cast [button:2] Aspect of the Pack; Aspect of the Cheetah", needs = { "Aspect of the Cheetah", "Aspect of the Pack" }, name = "Cheetah" },
        { "Aspect of the Monkey and Deterrence", body = "#showtooltip Deterrence\n/cast Aspect of the Monkey\n/cast Deterrence", needs = { "Aspect of the Monkey", "Deterrence" }, name = "Deterrence" },
    },
    MAGE = {
        { "Counterspell now, mouseover first", body = "#showtooltip Counterspell\n/stopcasting\n/cast [@mouseover,harm,nodead][] Counterspell", needs = { "Counterspell" }, name = "Counterspell" },
        { "Polymorph, mouseover first", "Polymorph", { mouse = "harm" } },
        { "Ice Block, press again to leave it", body = "#showtooltip Ice Block\n/stopcasting\n/cancelaura Ice Block\n/cast Ice Block", needs = { "Ice Block" }, name = "Ice Block" },
        { "Blink now (stops your cast)", "Blink", { stop = true } },
        { "Frost Nova now (stops your cast)", "Frost Nova", { stop = true } },
        { "Cold Snap now (stops your cast)", "Cold Snap", { stop = true } },
        { "Frostbolt, Shift for rank 1", body = "#showtooltip\n/cast [mod:shift] Frostbolt(Rank 1); Frostbolt", needs = { "Frostbolt" }, name = "Frostbolt" },
        { "Arcane Explosion, rank 1 out of combat", body = "#showtooltip\n/cast [combat] Arcane Explosion; Arcane Explosion(Rank 1)", needs = { "Arcane Explosion" }, name = "Explosion" },
        { "Conjure Water, Shift for Food", body = "#showtooltip\n/cast [mod:shift] Conjure Food; Conjure Water", needs = { "Conjure Water", "Conjure Food" }, name = "Conjure" },
        { "Mana gem: the best you carry", body = "#showtooltip\n/use Mana Ruby\n/use Mana Citrine\n/use Mana Jade\n/use Mana Agate", needs = { "Conjure Mana Agate" }, name = "Mana Gem" },
        { "Presence of Mind, then Pyroblast", body = "#showtooltip Pyroblast\n/cast Presence of Mind\n/cast Pyroblast", needs = { "Presence of Mind", "Pyroblast" }, name = "PoM Pyro" },
        { "Remove Lesser Curse: mouseover, target, then you", body = "#showtooltip Remove Lesser Curse\n/cast [@mouseover,help,nodead][help,nodead][@player] Remove Lesser Curse", needs = { "Remove Lesser Curse" }, name = "Decurse" },
        { "Wand that stays on", "Shoot", { keep = true } },
    },
    PRIEST = {
        { "Flash Heal, mouseover first", "Flash Heal", { mouse = "help", self = true } },
        { "Greater Heal, mouseover first", "Greater Heal", { mouse = "help", self = true } },
        { "Heal, mouseover first", "Heal", { mouse = "help", self = true } },
        { "Lesser Heal, mouseover first", "Lesser Heal", { mouse = "help", self = true } },
        { "Renew, mouseover first", "Renew", { mouse = "help", self = true } },
        { "Power Word: Shield, mouseover first", "Power Word: Shield", { mouse = "help", self = true } },
        { "Inner Focus, then Greater Heal", body = "#showtooltip Greater Heal\n/cast Inner Focus\n/cast [@mouseover,help,nodead][] Greater Heal", needs = { "Inner Focus", "Greater Heal" }, name = "Focus Heal" },
        { "Dispel Magic: mouseover friend, target, then you", body = "#showtooltip Dispel Magic\n/cast [@mouseover,help,nodead][exists,nodead][@player] Dispel Magic", needs = { "Dispel Magic" }, name = "Dispel" },
        { "Abolish Disease, mouseover first", "Abolish Disease", { mouse = "help", self = true } },
        { "Cure Disease, mouseover first", "Cure Disease", { mouse = "help", self = true } },
        { "Fear Ward, mouseover first", "Fear Ward", { mouse = "help" } },
        { "Heal a friend, Smite an enemy", body = "#showtooltip\n/cast [@mouseover,help,nodead][help,nodead] Heal; [harm,nodead] Smite", needs = { "Heal", "Smite" }, name = "Heal Smite" },
        { "Psychic Scream now (stops your cast)", "Psychic Scream", { stop = true } },
        { "Mind Flay that doesn't cut itself short", body = "#showtooltip Mind Flay\n/cast [nochanneling:Mind Flay] Mind Flay", needs = { "Mind Flay" }, name = "Mind Flay" },
        { "Shadow Word: Pain, then wand", body = "#showtooltip\n/castsequence reset=target/combat Shadow Word: Pain, !Shoot", needs = { "Shadow Word: Pain", "Shoot" }, name = "Pain Wand" },
        { "Shadowform that stays on", "Shadowform", { keep = true } },
        { "Silence now, mouseover first", body = "#showtooltip Silence\n/stopcasting\n/cast [@mouseover,harm,nodead][] Silence", needs = { "Silence" }, name = "Silence" },
        { "Wand that stays on", "Shoot", { keep = true } },
    },
    PALADIN = {
        { "Holy Light, mouseover first", "Holy Light", { mouse = "help", self = true } },
        { "Flash of Light, mouseover first", "Flash of Light", { mouse = "help", self = true } },
        { "Flash of Light, lower ranks on Ctrl and Shift", body = "#showtooltip Flash of Light\n/cast [mod:ctrl] Flash of Light(Rank 1); [mod:shift] Flash of Light(Rank 3); Flash of Light", needs = { "Flash of Light" }, name = "Flash Ranks" },
        { "Divine Favor, then Holy Light", body = "#showtooltip Holy Light\n/cast Divine Favor\n/cast [@mouseover,help,nodead][] Holy Light", needs = { "Divine Favor", "Holy Light" }, name = "Favor Heal" },
        { "Lay on Hands, mouseover first", "Lay on Hands", { mouse = "help" } },
        { "Cleanse, mouseover first", "Cleanse", { mouse = "help", self = true } },
        { "Purify, mouseover first", "Purify", { mouse = "help", self = true } },
        { "Blessing of Might, Shift for Greater", body = "#showtooltip\n/cast [mod:shift] Greater Blessing of Might; [@mouseover,help,nodead][] Blessing of Might", needs = { "Blessing of Might", "Greater Blessing of Might" }, name = "Might" },
        { "Blessing of Wisdom, Shift for Greater", body = "#showtooltip\n/cast [mod:shift] Greater Blessing of Wisdom; [@mouseover,help,nodead][] Blessing of Wisdom", needs = { "Blessing of Wisdom", "Greater Blessing of Wisdom" }, name = "Wisdom" },
        { "Blessing of Protection, mouseover first", "Blessing of Protection", { mouse = "help", self = true } },
        { "Blessing of Freedom, mouseover first", "Blessing of Freedom", { mouse = "help", self = true } },
        { "Hammer of Justice now, mouseover first", body = "#showtooltip Hammer of Justice\n/stopcasting\n/cast [@mouseover,harm,nodead][] Hammer of Justice", needs = { "Hammer of Justice" }, name = "Hammer" },
        { "Judgement, then Seal of Righteousness", body = "#showtooltip Judgement\n/cast Judgement\n/cast Seal of Righteousness", needs = { "Judgement", "Seal of Righteousness" }, name = "Judge" },
        { "Judgement, then Seal of Command", body = "#showtooltip Judgement\n/cast Judgement\n/cast Seal of Command", needs = { "Judgement", "Seal of Command" }, name = "Judge SoC" },
        { "Divine Shield, press again to drop it", body = "#showtooltip Divine Shield\n/cancelaura Divine Shield\n/cast Divine Shield", needs = { "Divine Shield" }, name = "Bubble" },
        { "Redemption on a dead friend, mouseover first", body = "#showtooltip Redemption\n/cast [@mouseover,help,dead][] Redemption", needs = { "Redemption" }, name = "Redemption" },
        { "Cycle auras: Devotion, Retribution, Concentration", body = "#showtooltip\n/castsequence Devotion Aura, Retribution Aura, Concentration Aura", needs = { "Devotion Aura", "Retribution Aura", "Concentration Aura" }, name = "Auras" },
    },
    SHAMAN = {
        { "Earth Shock rank 1 now, mouseover first (interrupt)", body = "#showtooltip Earth Shock\n/stopcasting\n/cast [@mouseover,harm,nodead][] Earth Shock(Rank 1)", needs = { "Earth Shock" }, name = "Interrupt" },
        { "Earth Shock now (stops your cast)", "Earth Shock", { stop = true } },
        { "Flame Shock, then Earth Shock", body = "#showtooltip\n/castsequence reset=combat/target/12 Flame Shock, Earth Shock", needs = { "Flame Shock", "Earth Shock" }, name = "Shocks" },
        { "Healing Wave, mouseover first", "Healing Wave", { mouse = "help", self = true } },
        { "Lesser Healing Wave, mouseover first", "Lesser Healing Wave", { mouse = "help", self = true } },
        { "Chain Heal, mouseover first", "Chain Heal", { mouse = "help", self = true } },
        { "Lesser Healing Wave on your target's target", body = "#showtooltip Lesser Healing Wave\n/cast [@targettarget,help,nodead][help,nodead][@player] Lesser Healing Wave", needs = { "Lesser Healing Wave" }, name = "Tank Heal" },
        { "Nature's Swiftness, then Healing Wave", body = "#showtooltip Healing Wave\n/cast Nature's Swiftness\n/cast [@mouseover,help,nodead][] Healing Wave", needs = { "Nature's Swiftness", "Healing Wave" }, name = "NS Heal" },
        { "Elemental Mastery, trinkets, then Lightning Bolt", body = "#showtooltip Elemental Mastery\n/use 13\n/use 14\n/cast Elemental Mastery\n/cast Lightning Bolt", needs = { "Elemental Mastery", "Lightning Bolt" }, name = "EM Burst" },
        { "Purge an enemy, Cure Poison a friend", body = "#showtooltip\n/cast [@mouseover,help,nodead] Cure Poison; [@mouseover,harm,nodead][harm,nodead] Purge; [help,nodead] Cure Poison", needs = { "Purge", "Cure Poison" }, name = "Purge Cure" },
        { "Purge, mouseover first", "Purge", { mouse = "harm" } },
        { "Weapon imbue: Windfury, others on Alt, Ctrl, Shift", body = "#showtooltip\n/cast [mod:alt] Rockbiter Weapon; [mod:ctrl] Flametongue Weapon; [mod:shift] Frostbrand Weapon; Windfury Weapon",
          needs = { "Rockbiter Weapon", "Flametongue Weapon", "Frostbrand Weapon", "Windfury Weapon" }, name = "Imbue" },
        { "Ghost Wolf that stays on", "Ghost Wolf", { keep = true } },
    },
    WARLOCK = {
        { "Shadow Bolt and send the pet", body = "#showtooltip Shadow Bolt\n/petattack\n/cast Shadow Bolt", needs = { "Shadow Bolt" }, name = "Bolt" },
        { "Pet attack, mouseover first; Ctrl calls it back", body = "/petattack [nomod,@mouseover,harm,nodead][nomod]\n/petfollow [mod:ctrl]\n/petpassive [mod:ctrl]", needs = { "Summon Imp" }, name = "Pet Attack" },
        { "Your demon's special ability", body = "#showtooltip\n/cast [pet:Voidwalker] Sacrifice; [pet:Felhunter] Spell Lock; [pet:Succubus] Seduction", needs = { "Summon Voidwalker" }, name = "Pet Special" },
        { "Spell Lock, mouseover first", body = "#showtooltip Spell Lock\n/cast [@mouseover,harm,nodead][] Spell Lock", needs = { "Summon Felhunter" }, name = "Spell Lock" },
        { "Devour Magic, mouseover first; Shift for you", body = "#showtooltip Devour Magic\n/cast [mod:shift,@player][@mouseover,exists,nodead][] Devour Magic", needs = { "Summon Felhunter" }, name = "Devour" },
        { "Fear, mouseover first", "Fear", { mouse = "harm" } },
        { "Banish, mouseover first", "Banish", { mouse = "harm" } },
        { "Death Coil now, mouseover first", body = "#showtooltip Death Coil\n/stopcasting\n/cast [@mouseover,harm,nodead][] Death Coil", needs = { "Death Coil" }, name = "Death Coil" },
        { "Shadowburn now, mouseover first", body = "#showtooltip Shadowburn\n/stopcasting\n/cast [@mouseover,harm,nodead][] Shadowburn", needs = { "Shadowburn" }, name = "Shadowburn" },
        -- (on Forever, Curse of Agony is Bane of Agony, and there is no Curse of Shadow)
        { "Bane of Agony, curses on Shift, Ctrl, Alt", body = "#showtooltip\n/cast [mod:shift] Curse of the Elements; [mod:ctrl] Curse of Recklessness; [mod:alt] Curse of Tongues; Bane of Agony",
          needs = { "Bane of Agony", "Curse of the Elements", "Curse of Recklessness", "Curse of Tongues" }, name = "Curses" },
        { "Summon: Voidwalker, others on Shift, Ctrl, Alt", body = "#showtooltip\n/cast [mod:shift] Summon Imp; [mod:ctrl] Summon Succubus; [mod:alt] Summon Felhunter; Summon Voidwalker",
          needs = { "Summon Imp", "Summon Succubus", "Summon Felhunter", "Summon Voidwalker" }, name = "Summon" },
        { "Immolate, Bane of Agony, Corruption, then wand", body = "#showtooltip\n/petattack\n/castsequence reset=target Immolate, Bane of Agony, Corruption, !Shoot", needs = { "Immolate", "Bane of Agony", "Corruption", "Shoot" }, name = "Dots Wand" },
        { "Healthstone: the best you carry", body = "#showtooltip\n/use Major Healthstone\n/use Greater Healthstone\n/use Healthstone\n/use Lesser Healthstone\n/use Minor Healthstone", needs = { "Create Healthstone" }, name = "Healthstone" },
        { "Wand that stays on", "Shoot", { keep = true } },
    },
}
-- For every class.
local RECIPES_ALL = {
    { "Use both trinkets", body = "#showtooltip 13\n/use 13\n/use 14", needs = {}, name = "Trinkets" },
}

--- The ready-made macros for a class whose spells it has on this client: { { label, spell, options,
--- body }, ... }, each with its text.
function YS.MacroRecipes(class)
    class = class or Class()
    local out = {}
    local function Add(r)
        local ok = true
        for _, spell in ipairs(r.needs or { r[2] }) do if not Has(spell, class) then ok = false end end
        if ok then
            out[#out + 1] = { label = r[1], spell = r[2], options = r[3], name = r.name,
                body = r.body or YS.MacroBuild(r[2], r[3], class) }
        end
    end
    for _, r in ipairs(RECIPES[class] or {}) do Add(r) end
    if RECIPES[class] then for _, r in ipairs(RECIPES_ALL) do Add(r) end end
    return out
end

--- A name for a spell's macro: its last word, as short as a macro's name may be.
function YS.MacroName(spell)
    local short = spell:match(" of the (.+)$") or spell:match(" of (.+)$") or spell:match("(%S+)$") or spell
    return short:sub(1, NAME_MAX)
end

--- Make the macro (this character's). Returns its index, or nil and why not. One with that very text
--- already there is that one.
function YS.MacroMake(name, body)
    if InCombatLockdown() then return nil, "not in a fight." end
    name = strtrim(name or "")
    if name == "" then return nil, "it needs a name." end
    if #body > MACRO_MAX then return nil, ("that is %d characters, and a macro holds %d."):format(#body, MACRO_MAX) end
    local numAccount, numChar = GetNumMacros()
    local base = Constants.MacroConsts.MAX_ACCOUNT_MACROS
    for i = base + 1, base + (numChar or 0) do
        local _, _, has = GetMacroInfo(i)
        -- (the game gives a macro's text back with a line break at its end that wasn't written)
        if type(has) == "string" and has:gsub("%s+$", "") == body then return i, "you have that macro already." end
    end
    if (numChar or 0) >= Constants.MacroConsts.MAX_CHARACTER_MACROS then
        return nil, ("this character has all %d of its macros."):format(Constants.MacroConsts.MAX_CHARACTER_MACROS)
    end
    local ok, index = pcall(CreateMacro, name:sub(1, NAME_MAX), 134400, body, true)
    if not ok or not index then return nil, "the game wouldn't make it." end
    return index
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Lines. A macro is put together a line at a time: a spell, when it should cast, on whom, and whether
-- pressing again keeps it on. "/cast [stealth] Sap" under "/cast [nostealth] Stealth" is one button
-- that goes into Stealth and, pressed again, saps: each line is asked by itself at every press.
--   o: when (a condition, "stealth", "nostance:1", "mod:shift" ...), target ("help" or "harm": the unit
--   under the mouse first, else your target; "self"; "targettarget"; "pet"), altself (Alt casts it on
--   you), keep (pressing again doesn't turn it off)
-- ---------------------------------------------------------------------------
function YS.MacroLine(spell, o)
    o = o or {}
    local when = o.when and o.when ~= "" and o.when or nil
    local function Box(...)
        local parts = {}
        if when then parts[1] = when end
        for i = 1, select("#", ...) do parts[#parts + 1] = (select(i, ...)) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local where = ""
    if o.altself then where = where .. Box("mod:alt", "@player") end
    if o.target == "help" or o.target == "harm" then
        where = where .. Box("@mouseover", o.target, "nodead") .. Box()
    elseif o.target == "self" then
        where = where .. Box("@player")
    elseif o.target == "targettarget" then
        where = where .. Box("@targettarget")
    elseif o.target == "pet" then
        where = where .. Box("@pet")
    elseif when or o.altself then
        where = where .. Box()
    end
    return "/cast " .. (where ~= "" and (where .. " ") or "") .. (o.keep and "!" or "") .. spell
end

--- A line under the text there is.
function YS.MacroAddLine(text, line)
    text = tostring(text or ""):gsub("%s+$", "")
    return (text ~= "" and (text .. "\n") or "") .. line
end

--- The line as the "or else" of the last /cast line: "/cast [stealth] Sap" then Stealth gives
--- "/cast [stealth] Sap; Stealth" - one line, the first of its parts whose condition holds is cast.
--- With no /cast line to hang it on, it is a line of its own.
function YS.MacroAddElse(text, line)
    text = tostring(text or ""):gsub("%s+$", "")
    local head, last = text:match("^(.*\n)([^\n]*)$")
    if not head then head, last = "", text end
    if not last:find("^/cast ") then return YS.MacroAddLine(text, line) end
    return head .. last .. "; " .. (line:gsub("^/cast ", ""))
end

--- The text without its last line.
function YS.MacroDropLine(text)
    text = tostring(text or ""):gsub("%s+$", "")
    return (text:match("^(.*)\n[^\n]*$") or "")
end

-- The lines that are about the whole macro: its icon and tooltip, stopping your cast, leaving your form.
-- Each is in the text or isn't; switching one puts it in its place near the top or takes it out.
local WHOLE = {
    tip = { "#showtooltip", "^#showtooltip", 1 },
    stop = { "/stopcasting", "^/stopcasting%s*$", 2 },
    leave = { "/cancelform", "^/cancelform%s*$", 3 },
}
local function Lines(text)
    local out = {}
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
    while out[#out] == "" do out[#out] = nil end
    return out
end
function YS.MacroHasLine(text, kind)
    for _, line in ipairs(Lines(text)) do if line:find(WHOLE[kind][2]) then return true end end
    return false
end
function YS.MacroSetLine(text, kind, on)
    local kept = {}
    for _, line in ipairs(Lines(text)) do if not line:find(WHOLE[kind][2]) then kept[#kept + 1] = line end end
    if on then
        -- after the whole-macro lines that go before it, before everything else
        local at = 1
        for i, line in ipairs(kept) do
            for _, w in pairs(WHOLE) do
                if w[3] < WHOLE[kind][3] and line:find(w[2]) then at = i + 1 end
            end
        end
        table.insert(kept, at, WHOLE[kind][1])
    end
    return table.concat(kept, "\n")
end

--- When a line casts, for a class: { { condition or false, words } }.
function YS.MacroWhens(class)
    class = class or Class()
    local out = { { false, "Always" } }
    local function Add(c, words) out[#out + 1] = { c, words } end
    if class == "ROGUE" or class == "DRUID" then
        Add("stealth", "In stealth")
        Add("nostealth", "Not in stealth")
    end
    for i, name in ipairs(STANCES[class] or {}) do
        Add("stance:" .. i, "In " .. name)
        Add("nostance:" .. i, "Not in " .. name)
    end
    if FORMS[class] then
        Add("form", "In a form")
        Add("noform", "Not in a form")
    end
    if class == "DRUID" then Add("swimming", "Swimming") end
    if class == "HUNTER" or class == "WARLOCK" then
        Add("pet", "With a pet out")
        Add("nopet", "Without a pet")
    end
    Add("combat", "In combat")
    Add("nocombat", "Out of combat")
    Add("nomod", "No modifier held")
    Add("mod:shift", "Shift held")
    Add("mod:ctrl", "Ctrl held")
    Add("mod:alt", "Alt held")
    Add("button:2", "Right-click")
    return out
end
local TARGETS = { { false, "Your target" }, { "help", "Friend under the mouse" }, { "harm", "Enemy under the mouse" },
    { "self", "Yourself" }, { "targettarget", "Your target's target" }, { "pet", "Your pet" } }

-- ---------------------------------------------------------------------------
-- The window: the presets as a gallery on the left (an icon and a name each, four across), and on the
-- right the line you are putting together, the switches for the whole macro, and the macro's text.
-- The text is the macro: a preset fills it in, Add line puts a line under it, the switches put their
-- lines in and take them out, and you can write in it yourself.
-- ---------------------------------------------------------------------------
local W, H = 860, 740
local LEFT_W, TILE_W, TILE_H, TILE_GAP, PER_ROW = 404, 98, 94, 4, 4
local RIGHT_X = 20 + LEFT_W + 20
local win
local pick = { body = "", name = "", preset = nil, loaded = nil }     -- loaded: { index, name } of a macro of yours
local step = { spell = nil, when = false, target = false, keep = false, altself = false }

local function Text() return pick.body or "" end

--- The icon a macro's text would show on a bar: its spell's, from the planner's data (so a spell you
--- haven't learned has one), a trinket slot's, or the question mark.
function YS.MacroIcon(body)
    local class = Class()
    local what = YR.PlannerMacroShows and YR.PlannerMacroShows(body)
    if what then
        local slot = tonumber(what)
        if slot then return GetInventoryItemTexture and GetInventoryItemTexture("player", slot) or 134400 end
        local d = ((YR.PlannerSpells or {})[class] or {})[what] or ((YR.PlannerGeneral or {})[class] or {})[what]
            or (YR.PlannerRacials or {})[what]
        if d then return d[2] end
        local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(what)
        if icon then return icon end
    end
    return 134400
end

-- typed: the text in the box is what you just wrote, and is left as it is
local function Paint(typed)
    for _, c in ipairs(win.controls) do if c.Refresh then c:Refresh() end end
    for i, tile in ipairs(win.tiles) do tile:SetOn(pick.preset == i) end
    win.LayoutOwn()
    win.save:SetShown(pick.loaded ~= nil)
    local text = Text()
    if not typed and win.edit:GetText() ~= text then
        win.edit:SetText(text)
        win.edit:SetCursorPosition(#text)
    end
    win.hint:SetShown(text == "" and not win.edit:HasFocus())
    win.add:SetEnabled(step.spell ~= nil)
    win.orElse:SetEnabled(step.spell ~= nil)
    win.lineText:SetText(step.spell and YS.MacroLine(step.spell, step) or "")
    local _, numChar = GetNumMacros()
    win.count:SetText(("%d of %d characters  ·  %d of %d of this character's macros"):format(#text, MACRO_MAX, numChar or 0,
        Constants.MacroConsts.MAX_CHARACTER_MACROS))
    win.count:SetTextColor(unpack(#text > MACRO_MAX and S.C.danger or S.C.muted))
    win.make:SetEnabled(text ~= "" and #text <= MACRO_MAX)
    win.save:SetEnabled(text ~= "" and #text <= MACRO_MAX)
end

local function Spells()
    local class = Class()
    local out, seen = {}, {}
    for _, src in ipairs({ (YR.PlannerSpells or {})[class] or {}, (YR.PlannerGeneral or {})[class] or {} }) do
        for name, d in pairs(src) do
            -- (a passive is nothing to cast: the planner's data marks it in its third field)
            if not seen[name] and d[3] ~= 1 then seen[name] = true out[#out + 1] = { name, name } end
        end
    end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    return out
end

-- the text changed by a button or a switch (not by typing): no preset is the one showing any more
local function SetText(text)
    pick.body, pick.preset = text, nil
    Paint()
end

--- Take a preset: its text in the box, and its name.
local function TakePreset(i)
    local r = YS.MacroRecipes()[i]
    if not r then return end
    pick.preset, pick.body, pick.loaded = i, r.body, nil
    pick.name = (r.name or YS.MacroName(r.spell or r.label)):sub(1, NAME_MAX)
    win.name:SetValue(pick.name)
    Paint()
end

-- Your macros are remembered for the class, on the account: a character's own macros belong to that
-- character alone, so a new rogue would start with none of the ones your first rogue made. What is
-- remembered is a name and a text (YippSetupDB.macroLib[CLASS]); the new character sees them under its
-- own, to make with a click. Deleting a macro forgets it too.
local function Library(class)
    local db = _G.YippSetupDB
    if type(db) ~= "table" then return {} end
    db.macroLib = type(db.macroLib) == "table" and db.macroLib or {}
    class = class or Class()
    db.macroLib[class] = type(db.macroLib[class]) == "table" and db.macroLib[class] or {}
    return db.macroLib[class]
end
function YS.MacroRemember(name, body, class)
    if type(name) ~= "string" or name == "" or type(body) ~= "string" or body == "" then return end
    local lib = Library(class)
    for _, m in ipairs(lib) do
        if m.name == name then m.body = body return end
    end
    lib[#lib + 1] = { name = name, body = body }
end
function YS.MacroForget(name, class)
    local lib = Library(class)
    for i = #lib, 1, -1 do if lib[i].name == name then table.remove(lib, i) end end
end
function YS.MacroLibrary(class) return Library(class) end

-- Sharing. Your macros for a class as text anyone can read, paste in a chat or a forum post, and take in
-- again: a first line that says what it is and for which class, then each macro as "== its name" over
-- its own lines.
--     Headstart macros: ROGUE
--     == Stl Sap
--     #showtooltip
--     /cast [stealth] Sap; Stealth
-- Taking one in only remembers the macros for that class (they are then offered under Your macros, to
-- make with a click): nothing is made, and nothing a character has is changed.
local SHARE_HEAD = "Headstart macros: "
function YS.MacroExport(class)
    class = class or Class()
    local out = { SHARE_HEAD .. class }
    for _, m in ipairs(Library(class)) do
        out[#out + 1] = "== " .. m.name
        out[#out + 1] = m.body
    end
    return table.concat(out, "\n"), #Library(class)
end
--- Returns how many macros were taken in and the class they are for, or nil and why not.
function YS.MacroImport(text)
    text = tostring(text or ""):gsub("\r", "")
    local class = text:match(SHARE_HEAD .. "(%u+)")
    if not class then return nil, "that isn't a Headstart macro export (its first line is missing)." end
    if not RECIPES[class] then return nil, ("'%s' isn't a class."):format(class) end
    local n, name, body = 0, nil, {}
    local function Done()
        local b = table.concat(body, "\n"):gsub("%s+$", "")
        if name and b ~= "" and #b <= MACRO_MAX then
            YS.MacroRemember(name:sub(1, NAME_MAX), b, class)
            n = n + 1
        end
        name, body = nil, {}
    end
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local head = line:match("^==%s*(.-)%s*$")
        if head and head ~= "" then
            Done()
            name = head
        elseif name then
            body[#body + 1] = line
        end
    end
    Done()
    if n == 0 then return nil, "there are no macros in it." end
    return n, class
end

--- The macros you can change here: this character's. The helper makes character macros, so these are
--- the ones it made (and any you made for this character yourself); the account's - /laugh, a reload
--- button - are for every class and aren't its business. Not the question-mark macros Headstart keeps
--- for spells you haven't learned either: those are its own, and come and go by themselves.
function YS.MacroOwn()
    local out = {}
    local numAccount, numChar = GetNumMacros()
    local base = Constants.MacroConsts.MAX_ACCOUNT_MACROS
    local function Add(i, account)
        local name, icon, body = (YS.MacroInfo or GetMacroInfo)(i)
        if name and not (YS.OwnSpellOf and YS.OwnSpellOf({ kind = "macro", name = name, body = body })) then
            out[#out + 1] = { index = i, name = name, icon = icon, body = body or "", account = account }
        end
    end
    for i = base + 1, base + (numChar or 0) do Add(i, false) end
    -- and the ones remembered for the class that this character hasn't got: { name, body, saved = true }
    local have = {}
    for _, m in ipairs(out) do have[m.name] = true end
    for _, m in ipairs(Library()) do
        if not have[m.name] then out[#out + 1] = { name = m.name, body = m.body, saved = true } end
    end
    return out
end

--- Write a macro you have over with a new name and text. Returns its index, or nil and why not.
--- expect: the name it had when you opened it - the macro at that place must still be that one
--- (they move when one is made, deleted or renamed, and this would write over another).
function YS.MacroSave(index, name, body, expect)
    if InCombatLockdown() then return nil, "not in combat." end
    name = strtrim(name or "")
    if name == "" then return nil, "it needs a name." end
    if #body > MACRO_MAX then return nil, ("that is %d characters, and a macro holds %d."):format(#body, MACRO_MAX) end
    if not GetMacroInfo(index) then return nil, "that macro is gone." end
    local was = (GetMacroInfo(index))
    if expect and was ~= expect then return nil, "that macro has moved. Open the macro helper again." end
    EditMacro(index, name:sub(1, NAME_MAX), nil, body)
    if was and was ~= name:sub(1, NAME_MAX) then YS.MacroForget(was) end
    YS.MacroRemember(name:sub(1, NAME_MAX), body)
    return index
end

--- Delete a macro, if the one at that place still has that name (they move when one is deleted).
function YS.MacroDelete(index, name)
    if InCombatLockdown() then return nil, "not in combat." end
    if (GetMacroInfo(index)) ~= name then return nil, "that macro has moved. Open the macro helper again." end
    DeleteMacro(index)
    YS.MacroForget(name)
    return true
end

StaticPopupDialogs["HEADSTART_FORGET_MACRO"] = {
    text = "Headstart: forget the macro %s?\n\nIt is no longer offered to your characters of this class. Macros a character already has stay.",
    button1 = "Forget", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(_, act) if act then act() end end,
}
StaticPopupDialogs["HEADSTART_DELETE_MACRO"] = {
    text = "Headstart: delete the macro %s?\n\nIt is removed from your bars too. This can't be undone.",
    button1 = "Delete", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(_, act) if act then act() end end,
}

local function Tile(parent, i, r)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(TILE_W, TILE_H)
    b.bg = S.Fill(b, S.C.card)
    b.edge = S.Border(b, S.C.line)
    b.icon = S.Icon(b, YS.MacroIcon(r.body), 36)
    b.icon:SetPoint("TOP", 0, -8)
    b.label = S.Text(b, 11, S.C.sub)
    b.label:SetPoint("TOPLEFT", 4, -48)
    b.label:SetPoint("TOPRIGHT", -4, -48)
    b.label:SetHeight(42)
    b.label:SetJustifyH("CENTER")
    b.label:SetJustifyV("TOP")
    b.label:SetWordWrap(true)
    b.label:SetText(r.label)
    function b:SetOn(on)
        self.on = on
        self.bg:SetColorTexture(unpack(on and S.C.accentD or S.C.card))
        self.edge:Color(on and S.C.accent or S.C.line)
        self.label:SetTextColor(unpack(on and S.C.text or S.C.sub))
    end
    b:SetScript("OnEnter", function(self)
        if not self.on then self.edge:Color(S.C.lineHi) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(r.label)
        GameTooltip:AddLine(r.body, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        if not self.on then self.edge:Color(S.C.line) end
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function() TakePreset(i) end)
    return b
end

local function Build()
    if win then return end
    win = S.Window("HeadstartMacroHelper", W, H, "Macro helper")
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win.controls, win.tiles = {}, {}

    -- left: the presets
    local head = S.Text(win, 11, S.C.muted)
    head:SetPoint("TOPLEFT", 20, -64)
    head:SetText("PRESETS FOR YOUR CLASS")
    local list = S.ScrollArea(win, LEFT_W + 14, H - 64 - 26 - 20)
    list:SetPoint("TOPLEFT", 20, -86)
    local recipes = YS.MacroRecipes()
    for i, r in ipairs(recipes) do
        local tile = Tile(list.content, i, r)
        tile:SetPoint("TOPLEFT", ((i - 1) % PER_ROW) * (TILE_W + TILE_GAP), -math.floor((i - 1) / PER_ROW) * (TILE_H + TILE_GAP))
        win.tiles[i] = tile
    end
    -- under them: your own macros, to load into the box, change and save - or delete
    local presetsH = math.ceil(#recipes / PER_ROW) * (TILE_H + TILE_GAP)
    local ownHead = S.Text(list.content, 11, S.C.muted)
    ownHead:SetPoint("TOPLEFT", 0, -presetsH - 10)
    ownHead:SetText("YOUR MACROS FOR THIS CLASS")
    local ownNone = S.Text(list.content, 12, S.C.muted)
    ownNone:SetPoint("TOPLEFT", 0, -presetsH - 32)
    ownNone:SetText("None yet. Make macro puts yours here, for every character of your class.")
    -- export and import, beside the heading
    local share
    local function Share(mode)
        if not share then
            share = S.Window("HeadstartMacroShare", 460, 380, "Share macros")
            share:SetFrameStrata("FULLSCREEN_DIALOG")
            share:SetFrameLevel(win:GetFrameLevel() + 200)
            share.note = S.Text(share, 12, S.C.sub)
            share.note:SetPoint("TOPLEFT", 20, -62)
            share.note:SetPoint("RIGHT", -20, 0)
            share.note:SetJustifyH("LEFT")
            share.note:SetWordWrap(true)
            local field = CreateFrame("Frame", nil, share)
            field:SetPoint("TOPLEFT", 20, -100)
            field:SetPoint("BOTTOMRIGHT", -20, 60)
            S.Fill(field, S.C.field)
            S.Border(field)
            local scroll = CreateFrame("ScrollFrame", nil, field)
            scroll:SetPoint("TOPLEFT", 8, -6)
            scroll:SetPoint("BOTTOMRIGHT", -8, 6)
            scroll:EnableMouseWheel(true)
            scroll:SetScript("OnMouseWheel", function(self, d)
                local range = self:GetVerticalScrollRange() or 0
                self:SetVerticalScroll(math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - d * 40)))
            end)
            local box = CreateFrame("EditBox", nil, scroll)
            box:SetMultiLine(true)
            box:SetAutoFocus(false)
            box:SetFont(S.FONT, 12, "")
            box:SetTextColor(unpack(S.C.text))
            box:SetWidth(400)
            box:SetScript("OnEscapePressed", box.ClearFocus)
            scroll:SetScrollChild(box)
            field:EnableMouse(true)
            field:SetScript("OnMouseDown", function() box:SetFocus() end)
            share.box = box
            share.go = S.Button(share, "Import", function()
                local n, what = YS.MacroImport(share.box:GetText())
                if n then
                    YR.Print(("took in %d macro%s for %s. They are under Your macros on that class: click one, then Make macro.")
                        :format(n, n == 1 and "" or "s", what))
                    share:Hide()
                    Paint()
                else
                    YR.Print("not imported: " .. tostring(what))
                end
            end, "primary", 110)
            share.go:SetPoint("BOTTOMRIGHT", -20, 16)
        end
        share.go:SetShown(mode == "import")
        if mode == "export" then
            local text, n = YS.MacroExport()
            share.note:SetText(("Your %d macro%s for this class. Press Ctrl+C to copy, then paste it anywhere."):format(n, n == 1 and "" or "s"))
            share.box:SetText(text)
            share.box:SetFocus()
            share.box:HighlightText()
        else
            share.note:SetText("Paste an export here and press Import. The macros are added to Your macros; nothing is made until you click one.")
            share.box:SetText("")
            share.box:SetFocus()
        end
        share:Show()
    end
    local import = S.Button(list.content, "Import", function() Share("import") end, nil, 64)
    import:SetHeight(20)
    import:SetPoint("TOPRIGHT", list.content, "TOPLEFT", LEFT_W - 6, -presetsH - 5)
    local export = S.Button(list.content, "Export", function() Share("export") end, nil, 64)
    export:SetHeight(20)
    export:SetPoint("RIGHT", import, "LEFT", -4, 0)
    win.own = {}
    local function OwnTile(i)
        local b = Tile(list.content, 0, { label = "", body = "" })
        b:SetScript("OnClick", function(self)
            local m = self.macro
            pick.loaded, pick.preset = (not m.saved) and { index = m.index, name = m.name } or nil, nil
            pick.body, pick.name = m.body, m.name
            win.name:SetValue(m.name)
            Paint()
        end)
        b:SetScript("OnEnter", function(self)
            if not self.on then self.edge:Color(S.C.lineHi) end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.macro.name)
            GameTooltip:AddLine(self.macro.body, 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine(self.macro.saved and "From another character of your class. Click it, then Make macro."
                or "Click to change it.", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        local x = CreateFrame("Button", nil, b)
        x:SetSize(18, 18)
        x:SetPoint("TOPRIGHT", -1, -1)
        x.text = S.Text(x, 13, S.C.muted)
        x.text:SetPoint("CENTER")
        x.text:SetText("x")
        x:SetScript("OnEnter", function(self)
            self.text:SetTextColor(unpack(S.C.danger))
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(b.macro.saved and "Forget this macro" or "Delete this macro")
            GameTooltip:AddLine("Asks first", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        x:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(S.C.muted)) GameTooltip:Hide() end)
        x:SetScript("OnClick", function()
            local m = b.macro
            StaticPopup_Show(m.saved and "HEADSTART_FORGET_MACRO" or "HEADSTART_DELETE_MACRO", m.name, nil, function()
                if m.saved then
                    YS.MacroForget(m.name)
                else
                    local ok, why = YS.MacroDelete(m.index, m.name)
                    if not ok then YR.Print("not deleted: " .. tostring(why)) end
                end
                if pick.loaded and pick.loaded.name == m.name then pick.loaded = nil end
                if win:IsShown() then Paint() end
            end)
        end)
        b:SetPoint("TOPLEFT", ((i - 1) % PER_ROW) * (TILE_W + TILE_GAP), -presetsH - 32 - math.floor((i - 1) / PER_ROW) * (TILE_H + TILE_GAP))
        win.own[i] = b
        return b
    end
    function win.LayoutOwn()
        local mine = YS.MacroOwn()
        for i, m in ipairs(mine) do
            local b = win.own[i] or OwnTile(i)
            b.macro = m
            b.icon:SetTexture((m.icon and m.icon ~= 134400) and m.icon or YS.MacroIcon(m.body))
            b.label:SetText(m.name)
            b:SetOn(pick.loaded ~= nil and pick.loaded.index == m.index and pick.loaded.name == m.name)
            b.icon:SetDesaturated(m.saved and true or false)         -- not on this character yet: greyed
            b.icon:SetAlpha(m.saved and 0.6 or 1)
            b:Show()
        end
        for i = #mine + 1, #win.own do win.own[i]:Hide() end
        ownNone:SetShown(#mine == 0)
        list.content:SetSize(LEFT_W, presetsH + 32 + math.max(1, math.ceil(#mine / PER_ROW)) * (TILE_H + TILE_GAP))
        if list.UpdateScrollChildRect then list:UpdateScrollChildRect() end
        if list.UpdateBar then list:UpdateBar() end
    end
    if #recipes == 0 then
        local none = S.Text(win, 12, S.C.muted)
        none:SetPoint("TOPLEFT", 20, -90)
        none:SetText("No presets for this class yet.")
    end
    local rule = win:CreateTexture(nil, "BORDER")
    rule:SetPoint("TOPLEFT", RIGHT_X - 10, -60)
    rule:SetPoint("BOTTOMLEFT", RIGHT_X - 10, 16)
    rule:SetWidth(1)
    S.Set(rule, S.C.line)

    -- right: a line, the whole macro, the text
    local y = -64
    local function Head(text)
        local t = S.Text(win, 11, S.C.muted)
        t:SetPoint("TOPLEFT", RIGHT_X, y)
        t:SetText(text)
        y = y - 22
    end
    local function Row(label, control)
        local t = S.Text(win, 13)
        t:SetPoint("TOPLEFT", RIGHT_X, y - 4)
        t:SetText(label)
        control:SetParent(win)
        control:SetPoint("TOPRIGHT", -20, y)
        win.controls[#win.controls + 1] = control
        y = y - 30
    end
    local function Choice(key, options, width)
        local d
        d = S.Dropdown(win, width or 230, options, function(v) step[key] = v or false Paint() end)
        function d:Refresh()
            local list = type(options) == "function" and options() or options
            for _, o in ipairs(list) do if (step[key] or false) == o[1] then self:SetValue(o[2]) end end
        end
        return d
    end

    Head("A LINE")
    local spell
    spell = S.Dropdown(win, 230, Spells, function(name) step.spell = name Paint() end)
    function spell:Refresh() self:SetValue(step.spell or "Pick a spell...") end
    Row("Cast", spell)
    Row("When", Choice("when", YS.MacroWhens()))
    Row("On", Choice("target", TARGETS))
    Row("Stays on when pressed again", S.Switch(win, function() return step.keep end, function(on) step.keep = on Paint() end))
    Row("Alt casts it on yourself", S.Switch(win, function() return step.altself end, function(on) step.altself = on Paint() end))
    win.lineText = S.Text(win, 12, S.C.accent)
    win.lineText:SetPoint("TOPLEFT", RIGHT_X, y - 6)
    win.lineText:SetPoint("RIGHT", win, "RIGHT", -20, 0)
    win.lineText:SetJustifyH("LEFT")
    win.lineText:SetWordWrap(false)
    y = y - 26
    win.add = S.Button(win, "Add line", function()
        if not step.spell then return end
        -- the first line of a new macro: with the icon and tooltip line over it (its switch takes it off)
        local text = Text()
        if text:gsub("%s", "") == "" then text = "#showtooltip" end
        SetText(YS.MacroAddLine(text, YS.MacroLine(step.spell, step)))
    end, "primary", 100)
    win.add:SetPoint("TOPLEFT", RIGHT_X, y)
    win.orElse = S.Button(win, "Or else", function()
        if step.spell then SetText(YS.MacroAddElse(Text(), YS.MacroLine(step.spell, step))) end
    end, nil, 84)
    win.orElse:SetPoint("LEFT", win.add, "RIGHT", 6, 0)
    win.orElse.tip = "Adds it to the last /cast line after a semicolon: it casts when that line's condition doesn't hold."
        .. " [stealth] Sap, or else Stealth, is one button for both"
    local drop = S.Button(win, "Remove last", function() SetText(YS.MacroDropLine(Text())) end, nil, 104)
    drop:SetPoint("LEFT", win.orElse, "RIGHT", 6, 0)
    local clear = S.Button(win, "Clear", function() SetText("") end, nil, 70)
    clear:SetPoint("LEFT", drop, "RIGHT", 6, 0)
    y = y - 44

    Head("THE WHOLE MACRO")
    local function Whole(kind, label)
        Row(label, S.Switch(win, function() return YS.MacroHasLine(Text(), kind) end,
            function(on) SetText(YS.MacroSetLine(Text(), kind, on)) end))
    end
    Whole("tip", "Show the spell's icon and tooltip")
    Whole("stop", "Stop casting first (for interrupts)")
    if FORMS[Class()] then Whole("leave", "Leave your form first") end
    win.name = S.Input(win, { width = 230, placeholder = "Name", onChange = function(t) pick.name = t or "" end })
    Row("Name", win.name)

    -- the macro's text
    local field = CreateFrame("Frame", nil, win)
    field:SetPoint("TOPLEFT", RIGHT_X, y - 6)
    field:SetPoint("BOTTOMRIGHT", -20, 74)
    S.Fill(field, S.C.field)
    local edge = S.Border(field)
    local edit = CreateFrame("EditBox", nil, field)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFont(S.FONT, 13, "")
    edit:SetTextColor(unpack(S.C.text))
    edit:SetPoint("TOPLEFT", 10, -8)
    edit:SetPoint("TOPRIGHT", -10, -8)
    edit:SetHeight(40)
    edit:SetSpacing(3)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:SetScript("OnEditFocusGained", function() edge:Color(S.C.accent) win.hint:Hide() end)
    edit:SetScript("OnEditFocusLost", function() edge:Color(S.C.line) Paint(true) end)
    edit:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        pick.body, pick.preset = self:GetText(), nil
        Paint(true)
    end)
    field:EnableMouse(true)
    field:SetScript("OnMouseDown", function() edit:SetFocus() end)
    win.edit = edit
    win.hint = S.Text(field, 13, S.C.muted)
    win.hint:SetPoint("TOPLEFT", 10, -8)
    win.hint:SetText("Pick a preset, add lines, or click here and write your own.")
    win.count = S.Text(win, 11, S.C.muted)
    win.count:SetPoint("BOTTOMLEFT", RIGHT_X, 52)
    win.make = S.Button(win, "Make macro", function()
        local index, why = YS.MacroMake(pick.name ~= "" and pick.name or "Macro", Text())
        if index then
            pick.loaded = { index = index, name = (GetMacroInfo(index)) }
            YS.MacroRemember(pick.loaded.name, Text())
            YR.Print(why or ("made the macro '%s'. It is in the planner's Macros list, and in the game's macro window (/macro)."):format(
                (GetMacroInfo(index))))
        else
            YR.Print("no macro made: " .. tostring(why))
        end
        Paint()
    end, "primary", 130)
    win.make:SetPoint("BOTTOMRIGHT", -20, 16)
    -- a macro of yours is loaded: its text and name can be written over it (Make macro makes a new one)
    win.save = S.Button(win, "Save changes", function()
        local at = pick.loaded
        if not at then return end
        local ok, why = YS.MacroSave(at.index, pick.name ~= "" and pick.name or at.name, Text(), at.name)
        if ok then
            -- (renamed, it has a new place in the list: found again by its name)
            local now = GetMacroIndexByName((pick.name ~= "" and pick.name or at.name):sub(1, 16))
            if now and now > 0 then at.index = now end
            at.name = (GetMacroInfo(at.index))
            YR.Print(("saved the macro '%s'."):format(tostring(at.name)))
        else
            YR.Print("not saved: " .. tostring(why))
        end
        Paint()
    end, nil, 120)
    win.save:SetPoint("RIGHT", win.make, "LEFT", -6, 0)
    win.save.tip = "Writes this text and name over the macro you loaded. Make macro makes a new one instead"
    -- macros made or deleted elsewhere (the game's own macro window): the list follows
    win:RegisterEvent("UPDATE_MACROS")
    win:SetScript("OnEvent", function(self) if self:IsShown() then Paint() end end)
    -- (what Make macro makes is said when you point at it: a line here ran under Save changes)
    win.make.tip = "Makes a new macro for this character. It is then under Your macros, and in the planner's Macros list"
end

function YR.MacroHelperToggle()
    if InCombatLockdown() then YR.Print("not in combat.") return false end
    Build()
    if win:IsShown() then win:Hide() return false end
    for _, m in ipairs(YS.MacroOwn()) do
        if not m.saved then YS.MacroRemember(m.name, m.body) end
    end
    win:Show()
    Paint()
    return true
end
