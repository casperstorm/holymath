--[[ Holy Math - Models/ConsumableData.lua  (GENERATED - do not edit by hand)
     Made by tools/gen_consumable_data.py from wowsims/forever, commit 57df2a7a5a2bb085bfce15890a33d655bb7fd66f 2026-11-23.
     The flasks, elixirs, scrolls, food, drinks, weapon oils and other buffs a healing priest gets
     something from in WoW: Forever, each in the row of what doesn't stack with it. What another item
     of its row beats in every stat at the same or a lower level is hidden (kept to see you have it).
     Potions and runes
     are the model's (E.POTIONS). The game's own data as wowsims extracted it from the Forever client.
     wowsims licence (MIT): Copyright (c) 2022 wowsims team. THE SOFTWARE IS PROVIDED "AS IS".
]]--

local _, ns = ...
local D = {
  source = "wowsims/forever 57df2a7a5a2bb085bfce15890a33d655bb7fd66f 2026-11-23",
  -- the rows, in order: one of each can be up at once
  rows = { "flask", "elixir", "food", "oil" },
  -- id, name, required level, row, then healing, intellect, spirit, MP5, spell crit %, maximum mana, the
  -- buff's spell id (an oil: its weapon enchant's id) for seeing which one you have, and for food and
  -- drink the buff's amount (many
  -- share one Well Fed buff), the profession it needs (wowsims' number, 0 for none), and 1 when hidden
  items = {
    {13511,"Flask of Distilled Wisdom",50,"flask",0,0,0,0,0,2000,17627,0,0,0},
    {250330,"Minor Cleric's Elixir",5,"elixir",10,0,0,0,0,0,1250922,0,0,0},
    {250339,"Minor Mageblood Elixir",5,"elixir",0,0,0,3,0,0,1250942,0,0,0},
    {250344,"Elixir of Minor Spirit",5,"elixir",0,0,3,0,0,0,1250974,0,0,0},
    {3383,"Elixir of Wisdom",10,"elixir",0,3,0,0,0,0,3166,0,0,0},
    {250331,"Lesser Cleric's Elixir",25,"elixir",20,0,0,0,0,0,1250924,0,0,0},
    {250340,"Lesser Mageblood Elixir",25,"elixir",0,0,0,6,0,0,1250944,0,0,0},
    {250345,"Elixir of Lesser Spirit",25,"elixir",0,0,6,0,0,0,1250976,0,0,0},
    {250353,"Elixir of Lesser Intellect",25,"elixir",0,6,0,0,0,0,1250988,0,0,0},
    {9179,"Elixir of Greater Intellect",37,"elixir",0,25,0,0,0,0,11396,0,0,0},
    {13447,"Elixir of the Sages",38,"elixir",0,18,18,0,0,0,17535,0,0,0},
    {20007,"Mageblood Elixir",40,"elixir",0,0,0,12,0,0,24363,0,0,0},
    {250332,"Cleric's Elixir",45,"elixir",30,0,0,0,0,0,1250925,0,0,0},
    {250346,"Elixir of Spirit",45,"elixir",0,0,10,0,0,0,1250978,0,0,1},
    {250354,"Elixir of Intellect",45,"elixir",0,10,0,0,0,0,1250989,0,0,1},
    {13452,"Elixir of the Mongoose",46,"elixir",0,0,0,0,2,0,17538,0,0,0},
    {250328,"Elixir of Cunning",55,"elixir",0,25,0,0,0,0,1250918,0,0,1},
    {250333,"Greater Cleric's Elixir",55,"elixir",40,0,0,0,0,0,1250926,0,0,0},
    {250337,"Elixir of the Owl",55,"elixir",0,25,0,0,2,0,1250940,0,0,0},
    {250338,"Elixir of Sages",55,"elixir",0,0,25,0,2,0,1250941,0,0,0},
    {250341,"Greater Mageblood Elixir",55,"elixir",0,0,0,20,0,0,1250948,0,0,0},
    {250347,"Elixir of Greater Spirit",55,"elixir",0,0,18,0,0,0,1250979,0,0,1},
    {250348,"Elixir of the Whale",55,"elixir",0,0,25,0,2,0,1250981,0,0,1},
    {250351,"Elixir of the Grizzly",55,"elixir",0,0,0,0,2,0,1250986,0,0,1},
    {1082,"Redridge Goulash",5,"food",0,3,0,0,0,0,1248421,3,0,0},
    {2683,"Crab Cake",5,"food",0,3,0,0,0,0,1248421,3,0,1},
    {7806,"Lollipop",5,"food",0,0,2,0,0,0,19705,0,0,1},
    {7807,"Candy Bar",5,"food",0,0,2,0,0,0,19705,0,0,1},
    {7808,"Chocolate Square",5,"food",0,0,2,0,0,0,19705,0,0,1},
    {11584,"Cactus Apple Surprise",5,"food",0,0,2,0,0,0,19705,0,0,1},
    {249865,"Peace Tea",5,"food",2,0,0,0,0,0,1249927,2,0,1},
    {249866,"Royal Tea",5,"food",7,0,0,0,0,0,1249927,7,0,0},
    {249871,"Venomous Smoothie",5,"food",0,0,1,0,0,0,1249926,1,0,1},
    {249872,"Slimy Smoothie",5,"food",0,0,3,0,0,0,1249926,3,0,0},
    {250077,"Twice-Spiced Raptor Slice",5,"food",0,3,0,0,0,0,1248421,3,0,1},
    {263512,"Pincer Bites",5,"food",0,1,0,0,0,0,1248421,1,0,1},
    {2682,"Cooked Crab Claw",10,"food",0,1,0,0,0,0,1248421,1,0,1},
    {5477,"Strider Stew",10,"food",0,1,0,0,0,0,1248421,1,0,1},
    {12224,"Crispy Bat Wing",10,"food",0,1,0,0,0,0,1248421,1,0,1},
    {17197,"Gingerbread Cookie",10,"food",0,0,2,0,0,0,19705,0,0,1},
    {17198,"Egg Nog",10,"food",0,0,2,0,0,0,19705,0,0,1},
    {250079,"Tasty Raptor Bites",10,"food",0,1,0,0,0,0,1248421,1,0,1},
    {12210,"Roast Raptor",15,"food",0,5,0,0,0,0,1248421,5,0,0},
    {249867,"Root Tea",15,"food",11,0,0,0,0,0,1249927,11,0,0},
    {249873,"Mrrggl Smrrthle",15,"food",0,0,5,0,0,0,1249926,5,0,0},
    {5342,"Raptor Punch",18,"food",0,4,0,0,0,0,6114,0,0,1},
    {4457,"Barbecued Buzzard Wing",25,"food",0,10,0,0,0,0,1248421,10,0,0},
    {12216,"Spiced Chili Crab",25,"food",0,10,0,0,0,0,1248421,10,0,1},
    {249868,"Triage Tea",25,"food",22,0,0,0,0,0,1249927,22,0,0},
    {249874,"Calcified Smoothie",25,"food",0,0,10,0,0,0,1249926,10,0,0},
    {250073,"Raging Raptor Ribs",25,"food",0,10,0,0,0,0,1248421,10,0,1},
    {18254,"Runn Tum Tuber Surprise",35,"food",0,15,0,0,0,0,1248421,15,0,0},
    {249869,"Sunny Tea",35,"food",33,0,0,0,0,0,1249927,33,0,0},
    {249875,"Spicy Smoothie",35,"food",0,0,15,0,0,0,1249926,15,0,0},
    {250076,"Raptor Rouladen",35,"food",0,15,0,0,0,0,1248421,15,0,1},
    {16971,"Clamlette Surprise",40,"food",0,0,12,0,0,0,19710,0,0,1},
    {249870,"Sage's Tea",45,"food",44,0,0,0,0,0,1249927,44,0,0},
    {249876,"Wicked Smoothie",45,"food",0,0,20,0,0,0,1249926,20,0,0},
    {250066,"Soaring Pamplona",45,"food",0,20,0,0,0,0,1248421,20,0,0},
    {250067,"Bat Hachee",45,"food",0,20,0,0,0,0,1248421,20,0,1},
    {250075,"Prehistoric Pulled Raptor",45,"food",0,20,0,0,0,0,1248421,20,0,1},
    {20744,"Minor Wizard Oil",5,"oil",8,0,0,0,0,0,2623,0,0,0},
    {20745,"Minor Mana Oil",20,"oil",10,0,0,5,0,0,2624,0,0,0},
    {20746,"Lesser Wizard Oil",30,"oil",16,0,0,0,0,0,2626,0,0,0},
    {20747,"Lesser Mana Oil",40,"oil",20,0,0,10,0,0,2625,0,0,0},
    {20750,"Wizard Oil",40,"oil",24,0,0,0,0,0,2627,0,0,0},
    {20748,"Brilliant Mana Oil",45,"oil",30,0,0,15,0,0,2629,0,0,0},
    {20749,"Brilliant Wizard Oil",45,"oil",36,0,0,0,1,0,2628,0,0,0},
  },
  -- enchants: the slot rows, in order, then each: enchant (effect) id, the item that teaches or puts it on
  -- (0: none), its spell, name, row, healing, intellect, spirit, MP5, spell crit %, maximum mana, its proc
  -- ("insight", "revelation" or ""), and 1 when another of its row beats it in every stat
  enchantRows = { "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "legs", "feet", "weapon", "twohand", "offhand", "shield" },
  enchants = {
    {1483,11622,15345,"Lesser Arcane Amalgamation (+150 mana)","head",0,0,0,0,0,150,"",0},
    {1509,11648,15403,"Lesser Arcane Amalgamation (+8 intellect)","head",0,8,0,0,0,0,"",0},
    {1510,11649,15405,"Lesser Arcane Amalgamation (+8 spirit)","head",0,0,8,0,0,0,"",0},
    {2544,18330,22843,"Arcanum of Focus","head",8,0,0,0,0,0,"",0},
    {8218,249502,1249057,"Enchant Necklace - Spell Power","neck",6,0,0,0,0,0,"",1},
    {8219,249503,1249058,"Enchant Necklace - Healing Power","neck",11,0,0,0,0,0,"",0},
    {24,6342,7442,"Enchant Chest - Minor Intellect","chest",0,2,0,0,0,0,"",1},
    {246,6346,7773,"Enchant Chest - Lesser Intellect","chest",0,3,0,0,0,0,"",1},
    {843,273492,13606,"Enchant Chest - Intellect","chest",0,4,0,0,0,0,"",1},
    {847,273497,13624,"Enchant Chest - Minor Stats","chest",0,1,1,0,0,0,"",1},
    {857,273511,13664,"Enchant Chest - Greater Intellect","chest",0,6,0,0,0,0,"",1},
    {866,273517,13625,"Enchant Chest - Lesser Stats","chest",0,2,2,0,0,0,"",1},
    {913,273534,13918,"Enchant Chest - Superior Intellect","chest",0,8,0,0,0,0,"",1},
    {928,273540,13824,"Enchant Chest - Stats","chest",0,3,3,0,0,0,"",1},
    {1891,16253,19988,"Enchant Chest - Greater Stats","chest",0,4,4,0,0,0,"",0},
    {1893,16242,19991,"Enchant Chest - Major Intellect","chest",0,10,0,0,0,0,"",0},
    {8482,252436,1254742,"Mystic Medium Armor Kit","chest",2,0,0,0,0,0,"",1},
    {8485,252452,1254750,"Mystic Heavy Armor Kit","chest",4,0,0,0,0,0,"",1},
    {8489,252462,1254767,"Mystic Thick Armor Kit","chest",5,0,0,0,0,0,"",1},
    {8492,252487,1254770,"Mystic Rugged Armor Kit","chest",6,0,0,0,0,0,"",0},
    {243,6344,7456,"Enchant Bracer - Minor Spirit","wrist",0,0,3,0,0,0,"",1},
    {246,249474,7773,"Enchant Bracer - Minor Intellect","wrist",0,3,0,0,0,0,"",1},
    {851,273502,13368,"Enchant Bracer - Spirit","wrist",0,0,5,0,0,0,"",1},
    {905,273522,13366,"Enchant Bracer - Intellect","wrist",0,5,0,0,0,0,"",1},
    {907,11204,13826,"Enchant Bracer - Greater Spirit","wrist",0,0,7,0,0,0,"",1},
    {1883,16214,13825,"Enchant Bracer - Greater Intellect","wrist",0,7,0,0,0,0,"",1},
    {1884,16218,19986,"Enchant Bracer - Superior Spirit","wrist",0,0,9,0,0,0,"",0},
    {1901,249538,19987,"Enchant Bracer - Superior Intellect","wrist",0,9,0,0,0,0,"",0},
    {2565,19446,23795,"Enchant Bracer - Mana Regeneration","wrist",0,0,0,4,0,0,"",0},
    {2566,19447,23796,"Enchant Bracer - Healing Power","wrist",24,0,0,0,0,0,"",0},
    {7665,273606,1220624,"Enchant Bracer - Greater Spellpower","wrist",16,0,0,0,0,0,"",1},
    {8203,6375,7859,"Enchant Bracer - Lesser Spirit","wrist",0,0,4,0,0,0,"",1},
    {8208,249475,1248459,"Enchant Bracer - Minor Healing Power","wrist",8,0,0,0,0,0,"",1},
    {8209,249489,1248498,"Enchant Bracer - Lesser Healing Power","wrist",16,0,0,0,0,0,"",1},
    {8734,273496,13622,"Enchant Bracer - Lesser Intellect","wrist",0,3,0,0,0,0,"",1},
    {8482,252436,1254742,"Mystic Medium Armor Kit","hands",2,0,0,0,0,0,"",1},
    {8485,252452,1254750,"Mystic Heavy Armor Kit","hands",4,0,0,0,0,0,"",1},
    {8489,252462,1254767,"Mystic Thick Armor Kit","hands",5,0,0,0,0,0,"",1},
    {8492,252487,1254770,"Mystic Rugged Armor Kit","hands",6,0,0,0,0,0,"",0},
    {1483,11622,15345,"Lesser Arcane Amalgamation (+150 mana)","legs",0,0,0,0,0,150,"",0},
    {1509,11648,15403,"Lesser Arcane Amalgamation (+8 intellect)","legs",0,8,0,0,0,0,"",0},
    {1510,11649,15405,"Lesser Arcane Amalgamation (+8 spirit)","legs",0,0,8,0,0,0,"",0},
    {2544,18330,22843,"Arcanum of Focus","legs",8,0,0,0,0,0,"",0},
    {8482,252436,1254742,"Mystic Medium Armor Kit","legs",2,0,0,0,0,0,"",1},
    {8485,252452,1254750,"Mystic Heavy Armor Kit","legs",4,0,0,0,0,0,"",1},
    {8489,252462,1254767,"Mystic Thick Armor Kit","legs",5,0,0,0,0,0,"",1},
    {8492,252487,1254770,"Mystic Rugged Armor Kit","legs",6,0,0,0,0,0,"",1},
    {851,16220,13368,"Enchant Boots - Spirit","feet",0,0,5,0,0,0,"",0},
    {8203,11167,13687,"Enchant Boots - Lesser Spirit","feet",0,0,4,0,0,0,"",1},
    {8482,252436,1254742,"Mystic Medium Armor Kit","feet",2,0,0,0,0,0,"",1},
    {8485,252452,1254750,"Mystic Heavy Armor Kit","feet",4,0,0,0,0,0,"",1},
    {8489,252462,1254767,"Mystic Thick Armor Kit","feet",5,0,0,0,0,0,"",1},
    {8492,252487,1254770,"Mystic Rugged Armor Kit","feet",6,0,0,0,0,0,"",0},
    {2567,19448,23797,"Enchant Weapon - Mighty Spirit","weapon",0,0,22,0,0,0,"",0},
    {2568,19449,23798,"Enchant Weapon - Mighty Intellect","weapon",0,22,0,0,0,0,"",0},
    {8216,249479,1248758,"Enchant Weapon - Insight","weapon",0,0,0,0,0,0,"insight",0},
    {8217,249481,1248806,"Enchant Weapon - Revelation","weapon",0,0,0,0,0,0,"revelation",0},
    {723,6349,7793,"Enchant 2H Weapon - Lesser Intellect","twohand",0,5,0,0,0,0,"",1},
    {851,11038,13368,"Enchant 2H Weapon - Lesser Spirit","twohand",0,0,5,0,0,0,"",1},
    {1903,16255,19986,"Enchant 2H Weapon - Major Spirit","twohand",0,0,9,0,0,0,"",1},
    {1904,16249,19987,"Enchant 2H Weapon - Major Intellect","twohand",0,9,0,0,0,0,"",1},
    {2567,19448,23797,"Enchant Weapon - Mighty Spirit","twohand",0,0,22,0,0,0,"",0},
    {2568,19449,23798,"Enchant Weapon - Mighty Intellect","twohand",0,22,0,0,0,0,"",0},
    {7662,273601,1219580,"Enchant 2H Weapon - Spellblasting","twohand",65,0,0,0,0,0,"",1},
    {8211,249525,1248607,"Enchant 2H Weapon - Mighty Spell Power","twohand",55,0,0,0,0,0,"",1},
    {8212,249526,1248636,"Enchant 2H Weapon - Mighty Healing Power","twohand",100,0,0,0,0,0,"",0},
    {8216,249479,1248758,"Enchant Weapon - Insight","twohand",0,0,0,0,0,0,"insight",0},
    {8217,249481,1248806,"Enchant Weapon - Revelation","twohand",0,0,0,0,0,0,"revelation",0},
    {7661,273600,1219579,"Enchant Off-Hand - Wisdom","offhand",0,6,5,0,0,0,"",0},
    {255,273485,7851,"Enchant Shield - Lesser Spirit","shield",0,0,3,0,0,0,"",1},
    {851,273509,13368,"Enchant Shield - Spirit","shield",0,0,5,0,0,0,"",1},
    {907,273532,13826,"Enchant Shield - Greater Spirit","shield",0,0,7,0,0,0,"",1},
    {1890,16222,19986,"Enchant Shield - Superior Spirit","shield",0,0,9,0,0,0,"",0},
  },
}
-- Holy Math is for priests only: another class leaves the rows unread
local class = UnitClass and select(2, UnitClass("player"))
if ns and class and class ~= "PRIEST" then D.items, D.enchants = {}, {}; return D end
for i, r in ipairs(D.items) do
  local st = {}
  for j, k in ipairs({ "healing", "int", "spirit", "mp5", "crit", "mana" }) do
    if r[4 + j] ~= 0 then st[k] = r[4 + j] end
  end
  D.items[i] = { id = r[1], name = r[2], lvl = r[3], row = r[4], stats = st, aura = r[11], amount = r[12], prof = r[13],
    hidden = r[14] == 1 }
end
D.byRow = {}
for _, it in ipairs(D.items) do
  D.byRow[it.row] = D.byRow[it.row] or {}
  if not it.hidden then table.insert(D.byRow[it.row], it) end
end
for i, r in ipairs(D.enchants) do
  local st = {}
  for j, k in ipairs({ "healing", "int", "spirit", "mp5", "crit", "mana" }) do
    if r[5 + j] ~= 0 then st[k] = r[5 + j] end
  end
  D.enchants[i] = { id = r[1], item = r[2], spell = r[3], name = r[4], row = r[5], stats = st,
    proc = r[12] ~= "" and r[12] or nil, hidden = r[13] == 1, enchant = true }
end
D.enchantByRow = {}
for _, e in ipairs(D.enchants) do
  D.enchantByRow[e.row] = D.enchantByRow[e.row] or {}
  if not e.hidden then table.insert(D.enchantByRow[e.row], e) end
end
if ns then ns.ConsumableData = D end
return D
