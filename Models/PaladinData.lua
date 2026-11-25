--[[ Holy Math - Models/PaladinData.lua  (GENERATED - do not edit by hand)
     Made by tools/gen_paladin_data.py from wowsims/forever, commit 57df2a7a5a2bb085bfce15890a33d655bb7fd66f 2026-11-23.
     The numbers are the game's own spell data as wowsims extracted it from the Forever client.

     Per rank, for ONE cast on ONE target: bp = base heal at the rank's base level bl,
     ppl = what it gains per level up to ml (its max level), coeff = share of healing power,
     cost = mana, lvl = level it is learned, cast = cast time in ms (0 = instant).
     Light's Vigil: the cast's cost and time, and the heal on each member of the party.

     wowsims licence (MIT):
     Copyright (c) 2022 wowsims team
     Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
     associated documentation files (the "Software"), to deal in the Software without restriction,
     including without limitation the rights to use, copy, modify, merge, publish, distribute,
     sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
     furnished to do so, subject to the following conditions: The above copyright notice and this
     permission notice shall be included in all copies or substantial portions of the Software.
     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
]]--

local _, ns = ...
local D = {
  source = "wowsims/forever 57df2a7a5a2bb085bfce15890a33d655bb7fd66f 2026-11-23",
  regen = { base = 6.25, perSpirit = 0.125 },  -- mana per second from spirit: base + spirit x perSpirit
  critPerInt60 = 0.0167,  -- spell crit (percent) per point of intellect at level 60
  baseMana60 = 1512,  -- base mana at level 60 (Oath of Light and Divine Favor cost a share of it)
  spells = {
    FLASH = { name = "Flash of Light", ranks = {
      { id = 19750, cost = 35, lvl = 20, bl = 20, ml = 25, bp = 46, ppl = 1, coeff = 0.429, cast = 1500 },
      { id = 19939, cost = 50, lvl = 26, bl = 26, ml = 31, bp = 66, ppl = 1.3, coeff = 0.429, cast = 1500 },
      { id = 19940, cost = 70, lvl = 34, bl = 34, ml = 39, bp = 101, ppl = 1.6, coeff = 0.429, cast = 1500 },
      { id = 19941, cost = 90, lvl = 42, bl = 42, ml = 47, bp = 151, ppl = 1.9, coeff = 0.429, cast = 1500 },
      { id = 19942, cost = 115, lvl = 50, bl = 50, ml = 55, bp = 223, ppl = 2.2, coeff = 0.429, cast = 1500 },
      { id = 19943, cost = 140, lvl = 58, bl = 58, ml = 63, bp = 303, ppl = 2.6, coeff = 0.429, cast = 1500 },
    } },
    HL = { name = "Holy Light", ranks = {
      { id = 635, cost = 35, lvl = 1, bl = 1, ml = 5, bp = 43, ppl = 0.8, coeff = 0.714, cast = 2500 },
      { id = 639, cost = 60, lvl = 6, bl = 6, ml = 11, bp = 83, ppl = 1.1, coeff = 0.714, cast = 2500 },
      { id = 647, cost = 110, lvl = 14, bl = 14, ml = 19, bp = 155, ppl = 1.7, coeff = 0.714, cast = 2500 },
      { id = 1026, cost = 190, lvl = 22, bl = 22, ml = 27, bp = 287, ppl = 2.4, coeff = 0.714, cast = 2500 },
      { id = 1042, cost = 275, lvl = 30, bl = 30, ml = 35, bp = 452, ppl = 3.1, coeff = 0.714, cast = 2500 },
      { id = 3472, cost = 365, lvl = 38, bl = 38, ml = 43, bp = 646, ppl = 3.8, coeff = 0.714, cast = 2500 },
      { id = 10328, cost = 465, lvl = 46, bl = 46, ml = 51, bp = 899, ppl = 4.6, coeff = 0.714, cast = 2500 },
      { id = 10329, cost = 580, lvl = 54, bl = 54, ml = 59, bp = 1217, ppl = 5.2, coeff = 0.714, cast = 2500 },
      { id = 25292, cost = 660, lvl = 60, bl = 60, ml = 65, bp = 1580, ppl = 5.8, coeff = 0.714, cast = 2500 },
    } },
    SHOCK = { name = "Holy Shock", ranks = {
      { id = 1311606, cost = 160, lvl = 30, bl = 30, ml = 37, bp = 114, ppl = 0, coeff = 0.429, cast = 0 },
      { id = 20473, cost = 225, lvl = 40, bl = 40, ml = 47, bp = 156, ppl = 0, coeff = 0.429, cast = 0 },
      { id = 20929, cost = 275, lvl = 48, bl = 48, ml = 55, bp = 230, ppl = 0, coeff = 0.429, cast = 0 },
      { id = 20930, cost = 325, lvl = 56, bl = 56, ml = 60, bp = 320, ppl = 0, coeff = 0.429, cast = 0 },
    } },
    VIGIL = { name = "Light's Vigil", ranks = {
      { id = 1310911, cost = 730, lvl = 40, bl = 40, ml = 49, bp = 324, ppl = 1.2, coeff = 0.143, cast = 1500 },
      { id = 1311590, cost = 1000, lvl = 50, bl = 50, ml = 59, bp = 487, ppl = 1.5, coeff = 0.143, cast = 1500 },
      { id = 1311595, cost = 1340, lvl = 60, bl = 60, ml = 69, bp = 704, ppl = 1.8, coeff = 0.143, cast = 1500 },
    } },
  },
  timing = {  -- seconds: cd = its own cooldown, dur = how long it lasts
    SHOCK = { cd = 10 },
    VIGIL = { cd = 6, dur = 30 },
    OATH = { dur = 300 },
    FAVOR = { cd = 120 },
    INFUSION = { dur = 15 },
  },
  -- Oath of Light on its target: healing added per paladin level (Holy Light, Flash of Light, Holy Shock)
  oathPerLevel = { HL = 6.66667, FLASH = 1.91667, SHOCK = 3.83333 },
  costPct = { OATH = 8, FAVOR = 4 },  -- percent of base mana
  talents = {  -- value per rank (percent; seconds: infusionOfLight)
    healingLight = { 4, 8, 12 },
    reverence = { 15, 30 },
    illumination = { 20, 40, 60, 80, 100 },
    infusionOfLight = { 0.5, 1 },
    holyPower = { 10, 20, 30, 40, 50 },
    divineIntellect = { 2, 4, 6, 8, 10 },
    benediction = { 2, 4, 6, 8, 10 },
    boundlessLight = { 15, 30 },
    conviction = { 2, 4, 6 },
    illuminationRefund = { 50 },
  },
}
if ns then ns.PaladinData = D end
return D
