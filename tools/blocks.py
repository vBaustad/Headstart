"""Our own steps inside the routes tools/fork_rxp.py builds: route name -> [(pattern, "before"/"after", spec)].
A block goes before or after the first step of the route that matches the pattern. Specs are
tools/route_builder.py lines; "group:" makes a step the Duo and Trio versions' only (dungeons).

Why dungeons for groups: on Forever, dungeon quests pay three to four times their Classic XP (our
server scan), the dungeon mobs almost nothing. The quests in these blocks, at Forever XP:
  Stockade: What Comes Around 6400, Crime and Punishment 6700, Quell the Uprising 8500,
            The Color of Blood 8500, The Stockade Riots 7500.
"""

BLOCKS = {
    # Stockade: picked up on the way (Guard Berton in Lakeshire, Councilman Millstipe in Darkshire,
    # Thelwater and Nikova in Stormwind), run at the end of the route in Stormwind (about level 27),
    # then the two out-of-town hand-ins by flight path.
    "24-27 Redridge/Duskwood": [
        (r"\.accept 244\b", "after", ["group: accept 386"]),
        (r"\.accept 163\b", "after", ["group: accept 377"]),
        (r"\.accept 1274\b", "after", [
            "group: turnin 389 | accept 391 387",
            "group: accept 388",
            "group: goto 1453 50.4 66.6 : Enter the Stockade in the Mage Quarter with your group",
            "group: do 386 377 387 388 391",
            "group: turnin 387 391",
            "group: turnin 388",
            "group: fly Lakeshire",
            "group: turnin 386",
            "group: fly Darkshire",
            "group: turnin 377",
        ]),
    ],
}
