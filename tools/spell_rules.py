"""What the three spell generators (gen_trainer_spells.py, gen_spell_levels.py, gen_planner.py) leave out.

The client's SkillLineAbility table lists more than the game has: Season of Discovery runes that
were never taken out, procs and marks named like spells, a hunter's pet's abilities on lines of
their own. The rules here take out what can be told from the data; NOT_SPELLS is what is left, found
by comparing with foreverchanges.pro's spellbook (tools/check_spellbook.py; build 1.60.1.70707,
2026-11-02). Run that again after a new build before trusting this list.
"""

# spell IDs: in the tables as trained class spells, and not in the game
NOT_IN_GAME = {
    438040,     # Redirect (rogue)
    28271,      # Polymorph: Turtle, a drop - listed as a level-60 "Polymorph"
    28272,      # Polymorph: Pig, a quest - the same
}

# skill lines that are a class's in the tables and hold nothing a class trainer teaches or a player presses
NOT_CLASS_LINES = {"Engraving", "Runes", "Meditation", "Explorer Imp", "Companions", "Beast Training"}

# ... except the line's own spell, where it is something the player presses
LINE_SPELLS = {"Beast Training"}

HIDDEN = 0x80           # spellmisc.Attributes[0]: not shown in the spellbook


def newest_schema(c):
    """The newest live build WITH its hotfixes. (_nohotfix is the client files alone: 70707's still hold the old
    druid tree. _wagohotfix is nine talent tables and no spells.)"""
    return c.sql("""select schema_name from main.builds where schema_name like 'wowf_%' and schema_name not like '%hotfix'
        order by schema_name desc limit 1""").fetchone()[0]


def effect_halves(c, s):
    """One rank can be two spells in the tables: the spell, and what it does when it goes off (Immolation Trap 14302 /
    14298, Lightning Shield 324 / 26364, Holy Nova's heal). The spell is the half that costs something: the ID doesn't
    tell (the trap's is the higher one, the shield's the lower), and since Explosive Trap Effect lost the "Effect"
    neither does the name. Returns the other halves' IDs."""
    return {r[0] for r in c.sql(f"""
        with learned as (
            select distinct a.SkillLine, cast(a.Spell as int) as id, n.Name_lang as name,
                coalesce(sp.NameSubtext_lang, '') as sub, a.Spell in (select SpellID from {s}.spellpower) as paid
            from {s}.skilllineability a
            join {s}.spellname n on n.ID = a.Spell
            left join {s}.spell sp on sp.ID = a.Spell
            where a.AcquireMethod in ('0', '2'))
        select id from learned l where not paid and exists (select 1 from learned o
            where o.paid and o.SkillLine = l.SkillLine and o.name = l.name and o.sub = l.sub)""").fetchall()}


def other_line(line):
    """A hunter's pet's line (Pet - Raptor ...), or one of the lines above."""
    return line in NOT_CLASS_LINES or (line or "").startswith("Pet - ")


def not_a_spell(name, attr=0):
    """What a spell does rather than the spell (Explosive Trap Effect), or one the spellbook hides."""
    return name.endswith(" Effect") or "(Passive" in name or bool((attr or 0) & HIDDEN)


# (CLASS, name): what the rules above leave in, and the site's spellbook doesn't have
NOT_SPELLS = {
    ("WARRIOR", "Unbridled Wrath"),             # the talent's proc
    ("WARRIOR", "Weaponmaster"),
    ("PALADIN", "Sanctity Aura"),               # a Classic talent, not in Forever's trees
    ("HUNTER", "Aspect of the Viper"), ("HUNTER", "Heart of the Lion"), ("HUNTER", "Black Arrow"),
    ("HUNTER", "Enchanted Flare"), ("HUNTER", "Aspect of the Falcon"), ("HUNTER", "Improved Mend Pet"),
    ("ROGUE", "Hack and Slash"),
    ("ROGUE", "Occult Poison I"), ("ROGUE", "Occult Poison II"), ("ROGUE", "Atrophic Poison"),
    ("ROGUE", "Numbing Poison"), ("ROGUE", "Sebacious Poison"),             # Season of Discovery's
    ("PRIEST", "Shadowfiend"),
    ("MAGE", "Chilled"), ("MAGE", "Clearcasting"), ("MAGE", "Frostbite"), ("MAGE", "Impact"),
    ("MAGE", "Master of Elements"),
    ("WARLOCK", "Pyroclasm"), ("WARLOCK", "Metamorphosis : Demon Charge"), ("WARLOCK", "Explorer Imp"),
    ("DRUID", "Feral Charge (Bear)"),           # the site has Feral Charge
}

# (CLASS, name) or (CLASS, name, rank): in the game, and no trainer teaches it
NOT_TAUGHT = {
    ("HUNTER", "Tame Beast"),                   # the level-10 quest
    ("MAGE", "Conjure Water", 8),               # a book
    ("DRUID", "Frenzied Regeneration"),
}
