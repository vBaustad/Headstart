-- Headstart: launch-day Coldridge Valley for Dwarves and Gnomes of every class.
-- Coordinates and step wording come from RestedXP's Forever guide (Guides/Forever/Alliance-1-14_DwarfGnome.lua,
-- CC BY-NC-SA 4.0); the order is ours. Why each change exists: S:/forever-data/research/leveling/findings.md
local _, YR = ...

YR:ShipGuide("coldridge", [[
#forever
#version 18
<< Alliance
#group Headstart Launch (A)
#subgroup Launch day
#name 1-5 Coldridge Valley (Launch)
#next Headstart Launch (A)\5-11 Dun Morogh (Launch)

step
    #optional
    #completewith Talin1
    .destroy 6948 >> Delete the |T134414:0|t[Hearthstone]
step
    #completewith next
    .goto 1426/0,688.98,-6222.47,30 >> Run to |cRXP_FRIENDLY_Talin Keeneye|r

step
    #label Talin1
    .goto 1426/0,688.98,-6222.47
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Talin Keeneye|r
    .accept 183 >> Accept The Boar Hunter
    .target Talin Keeneye
step
    #loop
    .goto 1426,22.276,72.549,0
    .goto 1426,20.924,70.393,0
    .goto 1426,22.662,69.331,0
    .goto 1426,24.358,72.591,0
    .goto 1426,22.276,72.549,45,0
    .goto 1426,21.209,72.266,45,0
    .goto 1426,20.880,71.470,45,0
    .goto 1426,20.924,70.393,45,0
    .goto 1426,21.330,69.261,45,0
    .goto 1426,22.035,69.231,45,0
    .goto 1426,22.662,69.331,45,0
    .goto 1426,24.317,68.026,45,0
    .goto 1426,24.754,69.257,45,0
    .goto 1426,24.878,71.191,45,0
    .goto 1426,24.358,72.591,45,0
    >>Kill |cRXP_ENEMY_Small Crag Boars|r
    .complete 183,1 --Kill Small Crag Boar (x12)
    .mob Small Crag Boar
step
    .goto 1426/0,688.98,-6222.47
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Talin Keeneye|r
    .turnin 183 >> Turn in The Boar Hunter
    .target Talin Keeneye
step
    .goto 1426,25.077,75.711
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Grelin Whitebeard|r
    .accept 182 >> Accept The Troll Cave
    .target Grelin Whitebeard

step
    #loop
    .goto 1426,25.861,78.197,0
    .goto 1426,23.716,80.257,0
    .goto 1426,20.671,75.838,0
    .goto 1426,25.861,78.197,45,0
    .goto 1426,26.382,78.409,45,0
    .goto 1426,26.031,79.854,45,0
    .goto 1426,23.716,80.257,45,0
    .goto 1426,22.836,79.962,45,0
    .goto 1426,22.684,78.888,45,0
    .goto 1426,21.029,76.459,45,0
    .goto 1426,20.671,75.838,45,0
    >>Kill |cRXP_ENEMY_Frostmane Troll Whelps|r
    .complete 182,1 --Kill Frostmane Troll Whelp (x14)
    .mob Frostmane Troll Whelp
step
    .goto 1426/0,567.09,-6362.99
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Grelin Whitebeard|r
    .turnin 182 >> Turn in The Troll Cave
    .accept 218 >> Accept The Stolen Journal
    .target Grelin Whitebeard
step
    .goto 1426/0,571.82,-6371.20
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Nori Pridedrift|r
    >>|cRXP_WARN_5 minute timer: kill Grik'nir, then die|r
    .accept 3364 >> Accept Scalding Mornbrew Delivery
    .target Nori Pridedrift
step
    #optional
    #label FrostMCave1
    #completewith Grelin
    .goto 1426,27.098,80.707,20 >> Enter the Frostmane Cave
step
    #optional
    #requires FrostMCave1
    #completewith Grelin
    .goto 1426,28.298,79.836,15,0
    .goto 1426,29.252,79.043,15,0
    .goto 1426,30.489,80.165,50 >> Run past the trolls to |cRXP_ENEMY_Grik'nir the Cold|r
step
    #label Grelin
    .goto 1426,30.489,80.165,0,0
    >>Kill |cRXP_ENEMY_Grik'nir the Cold|r. Loot his |cRXP_LOOT_Journal|r
    >>|cRXP_WARN_Group up with whoever is waiting|r
    .complete 218,1 --Collect Grelin Whitebeard's Journal (x1)
    .mob Grik'nir the Cold
step
    #completewith Durnan
    .deathskip >> Die in the cave and respawn at the Spirit Healer
    .target Spirit Healer
step
    #optional
    #completewith next
    .goto 1426,28.792,68.804,12,0
    .goto 1426,28.939,68.387,12 >> Enter Anvilmar
step
    #label Durnan
    .goto 1426/0,385.21,-6056.46
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Durnan Furcutter|r
    .turnin 3364 >> Turn in Scalding Mornbrew Delivery
    .accept 3365 >> Accept Bring Back the Mug
    .target Durnan Furcutter
step
    .goto 1426/0,390.000,-6093.800
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Grund Drokda::2756|r
    .accept 97277 >>Accept Grund and Gozwin
    .target Grund Drokda::2756
step
    .goto 1426,28.792,67.837
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Grundel Harkin|r
    .vendor >> Vendor trash
    .target Grundel Harkin
step << Paladin
    .goto 1426/0,382.06,-6120.65
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Bromos Grummner|r in Anvilmar
    .trainer >> Train your class spells
    .target Bromos Grummner
step << Warrior
    .goto 1426/0,382.11,-6084.86
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Thran Khorman|r in Anvilmar
    .trainer >> Train your class spells
    .target Thran Khorman
step << Hunter
    .goto 1426/0,365.21,-6091.86
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Thorgas Grimson|r
    .trainer >> Train your class spells
    .target Thorgas Grimson
step << Rogue
    .goto 1426/0,404.91,-6093.76
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Solm Hargrin|r
    .trainer >> Train your class spells
    .target Solm Hargrin
step << Priest
    .goto 1426/0,393.53,-6056.72
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Branstock Khalder|r upstairs
    .trainer >> Train your class spells
    .target Branstock Khalder
step << Mage
    .goto 1426/0,388.17,-6056.10
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Marryk Nurribit|r in Anvilmar
    .trainer >> Train your class spells
    .target Marryk Nurribit
step << Warlock
    .goto 1426/0,391.07,-6048.84
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Alamar Grimm|r upstairs
    .trainer >> Train your class spells
    .target Alamar Grimm
step << Shaman
    .goto 1426/0,384.000,-6050.200
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Teo Hammerstorm|r in Anvilmar
    .trainer >> Train your class spells
    .target Teo Hammerstorm
step
    #completewith next
    .goto 1426/0,497.300,-6118.500,20,0
    .goto 1426/0,467.700,-6012.800,20 >> Go to the northern hills
step
    >>Kill the |cRXP_ENEMY_Snow Leopard Prowler|r
    >>|cRXP_WARN_Group up with whoever is waiting|r
    >>Loot |cRXP_PICK_Gozwin's Mechanic's Log|r
    .complete 97277,2 --|1/1 Snow Leopard Prowler slain
    .mob +Snow Leopard Prowler::269075
    .goto 1426/0,447.800,-5942.000
    .complete 97277,1 --|1/1 Gozwin's Mechanic's Log
    .goto 1426/0,458.700,-5940.600
step
    .goto 1426/0,390.000,-6093.800
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Grund Drokda::2756|r
    .turnin 97277 >>Turn in Grund and Gozwin
    .target Grund Drokda::2756
step
    .goto 1426/0,567.14,-6363.06
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Grelin Whitebeard|r and |cRXP_FRIENDLY_Nori Pridedrift|r
    .turnin 218 >> Turn in The Stolen Journal
    .accept 282 >> Accept Senir's Observations
    .target +Grelin Whitebeard
    .turnin 3365 >> Turn in Bring Back the Mug
    .target +Nori Pridedrift
step
    .goto 1426/0,152.900,-6235.800
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Mountaineer Thalos::1965|r
    .turnin 282 >>Turn in Senir's Observations
    .accept 420 >>Accept Senir's Observations
    .accept 96628 >>Accept The Adventurer
    .target Mountaineer Thalos::1965
step
    .goto 1426/0,135.100,-6248.900
    >>|Tinterface/worldmap/chatbubble_64grey.blp:20|tTalk to |cRXP_FRIENDLY_Hands Springsprocket::6782|r
    .accept 2160 >>Accept Supplies to Tannok
    .target Hands Springsprocket::6782
step
    #label ThroughPass
    .goto 1426/0,111.82,-6206.61,15,0
    .goto 1426/0,46.32,-6037.19,15 >> Travel through Coldridge Pass
    .subzoneskip 800,1
    .isOnQuest 2160
]])
