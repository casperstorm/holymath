--[[ Holy Math - Models/PriestData.lua  (GENERATED - do not edit by hand)
     Made by tools/gen_priest_data.py from wowsims/forever, commit f95b7a5de4689445ea05d5ee3e8ead66db4f89e8 2026-11-20.
     The numbers are the game"s own spell data as wowsims extracted it from the Forever client.

     Per rank, for ONE cast on ONE target: bp = base heal at the rank"s base level bl,
     ppl = what it gains per level up to ml (its max level), coeff = share of healing power,
     cost = mana, lvl = level it is learned, cast = cast time in ms (0 = instant).
     Renew: all 5 ticks. Penance: all 3 bolts. Prayer of Healing / Holy Nova: per target.

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
  source = "wowsims/forever f95b7a5de4689445ea05d5ee3e8ead66db4f89e8 2026-11-20",
  regen = { base = 6.25, perSpirit = 0.125 },  -- mana per second from spirit: base + spirit x perSpirit
  critPerInt60 = 0.0168,  -- spell crit (percent) per point of intellect at level 60
  spells = {
    RENEW = { name = "Renew", ranks = {
      { id = 139, cost = 30, lvl = 8, bl = 8, ml = 13, bp = 45, ppl = 0, coeff = 1, cast = 0 },
      { id = 6074, cost = 65, lvl = 14, bl = 14, ml = 19, bp = 75, ppl = 0, coeff = 1, cast = 0 },
      { id = 6075, cost = 105, lvl = 20, bl = 20, ml = 25, bp = 125, ppl = 0, coeff = 1, cast = 0 },
      { id = 6076, cost = 140, lvl = 26, bl = 26, ml = 31, bp = 160, ppl = 0, coeff = 1, cast = 0 },
      { id = 6077, cost = 170, lvl = 32, bl = 32, ml = 37, bp = 205, ppl = 0, coeff = 1, cast = 0 },
      { id = 6078, cost = 205, lvl = 38, bl = 38, ml = 43, bp = 270, ppl = 0, coeff = 1, cast = 0 },
      { id = 10927, cost = 250, lvl = 44, bl = 44, ml = 49, bp = 370, ppl = 0, coeff = 1, cast = 0 },
      { id = 10928, cost = 305, lvl = 50, bl = 50, ml = 55, bp = 510, ppl = 0, coeff = 1, cast = 0 },
      { id = 10929, cost = 365, lvl = 56, bl = 56, ml = 61, bp = 670, ppl = 0, coeff = 1, cast = 0 },
      { id = 25315, cost = 410, lvl = 60, bl = 60, ml = 65, bp = 830, ppl = 0, coeff = 1, cast = 0 },
    } },
    GH = { name = "Greater Heal", ranks = {
      { id = 2060, cost = 370, lvl = 40, bl = 40, ml = 45, bp = 844, ppl = 5.1, coeff = 0.857, cast = 3000 },
      { id = 10963, cost = 455, lvl = 46, bl = 46, ml = 51, bp = 1099, ppl = 5.8, coeff = 0.857, cast = 3000 },
      { id = 10964, cost = 545, lvl = 52, bl = 52, ml = 57, bp = 1403, ppl = 6.6, coeff = 0.857, cast = 3000 },
      { id = 10965, cost = 655, lvl = 58, bl = 58, ml = 63, bp = 1782, ppl = 7.5, coeff = 0.857, cast = 3000 },
      { id = 25314, cost = 710, lvl = 60, bl = 60, ml = 65, bp = 1960, ppl = 8.1, coeff = 0.857, cast = 3000 },
    } },
    FLASH = { name = "Flash Heal", ranks = {
      { id = 2061, cost = 125, lvl = 20, bl = 20, ml = 25, bp = 194, ppl = 1.9, coeff = 0.429, cast = 1500 },
      { id = 9472, cost = 155, lvl = 26, bl = 26, ml = 31, bp = 249, ppl = 2.2, coeff = 0.429, cast = 1500 },
      { id = 9473, cost = 185, lvl = 32, bl = 32, ml = 37, bp = 312, ppl = 2.5, coeff = 0.429, cast = 1500 },
      { id = 9474, cost = 215, lvl = 38, bl = 38, ml = 43, bp = 383, ppl = 2.8, coeff = 0.429, cast = 1500 },
      { id = 10915, cost = 265, lvl = 44, bl = 44, ml = 49, bp = 507, ppl = 3.3, coeff = 0.429, cast = 1500 },
      { id = 10916, cost = 315, lvl = 50, bl = 50, ml = 55, bp = 644, ppl = 3.7, coeff = 0.429, cast = 1500 },
      { id = 10917, cost = 380, lvl = 56, bl = 56, ml = 61, bp = 825, ppl = 4.2, coeff = 0.429, cast = 1500 },
    } },
    HEAL = { name = "Heal", ranks = {
      { id = 2054, cost = 155, lvl = 16, bl = 16, ml = 21, bp = 270, ppl = 2, coeff = 0.857, cast = 3000 },
      { id = 2055, cost = 205, lvl = 22, bl = 22, ml = 27, bp = 375, ppl = 2.9, coeff = 0.857, cast = 3000 },
      { id = 6063, cost = 255, lvl = 28, bl = 28, ml = 33, bp = 523, ppl = 4, coeff = 0.857, cast = 3000 },
      { id = 6064, cost = 305, lvl = 34, bl = 34, ml = 39, bp = 651, ppl = 4.5, coeff = 0.857, cast = 3000 },
    } },
    LESSER = { name = "Lesser Heal", ranks = {
      { id = 2050, cost = 30, lvl = 1, bl = 1, ml = 3, bp = 51, ppl = 0.3, coeff = 0.429, cast = 1500 },
      { id = 2052, cost = 45, lvl = 4, bl = 4, ml = 9, bp = 94, ppl = 0.7, coeff = 0.571, cast = 2000 },
      { id = 2053, cost = 75, lvl = 10, bl = 10, ml = 15, bp = 163, ppl = 1.2, coeff = 0.714, cast = 2500 },
    } },
    POH = { name = "Prayer of Healing", ranks = {
      { id = 596, cost = 410, lvl = 30, bl = 30, ml = 39, bp = 178, ppl = 0.8, coeff = 0.286, cast = 3000 },
      { id = 996, cost = 560, lvl = 40, bl = 40, ml = 49, bp = 265, ppl = 1, coeff = 0.286, cast = 3000 },
      { id = 10960, cost = 770, lvl = 50, bl = 50, ml = 59, bp = 401, ppl = 1.3, coeff = 0.286, cast = 3000 },
      { id = 10961, cost = 1030, lvl = 60, bl = 60, ml = 69, bp = 583, ppl = 1.5, coeff = 0.286, cast = 3000 },
      { id = 25316, cost = 1070, lvl = 60, bl = 60, ml = 69, bp = 649, ppl = 1.6, coeff = 0.286, cast = 3000 },
    } },
    PWS = { name = "Power Word: Shield", ranks = {
      { id = 17, cost = 45, lvl = 6, bl = 6, ml = 11, bp = 44, ppl = 0.8, coeff = 0.1, cast = 0 },
      { id = 592, cost = 80, lvl = 12, bl = 12, ml = 17, bp = 86, ppl = 1.2, coeff = 0.1, cast = 0 },
      { id = 600, cost = 130, lvl = 18, bl = 18, ml = 23, bp = 154, ppl = 1.6, coeff = 0.1, cast = 0 },
      { id = 3747, cost = 175, lvl = 24, bl = 24, ml = 29, bp = 226, ppl = 2, coeff = 0.1, cast = 0 },
      { id = 6065, cost = 210, lvl = 30, bl = 30, ml = 35, bp = 291, ppl = 2.3, coeff = 0.1, cast = 0 },
      { id = 6066, cost = 250, lvl = 36, bl = 36, ml = 41, bp = 368, ppl = 2.6, coeff = 0.1, cast = 0 },
      { id = 10898, cost = 300, lvl = 42, bl = 42, ml = 47, bp = 470, ppl = 3, coeff = 0.1, cast = 0 },
      { id = 10899, cost = 355, lvl = 48, bl = 48, ml = 53, bp = 591, ppl = 3.4, coeff = 0.1, cast = 0 },
      { id = 10900, cost = 425, lvl = 54, bl = 54, ml = 59, bp = 749, ppl = 3.9, coeff = 0.1, cast = 0 },
      { id = 10901, cost = 500, lvl = 60, bl = 60, ml = 65, bp = 928, ppl = 4.3, coeff = 0.1, cast = 0 },
    } },
    POM = { name = "Prayer of Mending", ranks = {
      { id = 401859, cost = 210, lvl = 40, bl = 40, ml = 0, bp = 172, ppl = 0, coeff = 0.429, cast = 0 },
      { id = 1240826, cost = 305, lvl = 50, bl = 50, ml = 0, bp = 298, ppl = 0, coeff = 0.429, cast = 0 },
      { id = 1240827, cost = 390, lvl = 60, bl = 60, ml = 0, bp = 413, ppl = 0, coeff = 0.429, cast = 0 },
    } },
    NOVA = { name = "Holy Nova", ranks = {
      { id = 15237, cost = 185, lvl = 20, bl = 20, ml = 26, bp = 51, ppl = 0.4, coeff = 0.107, cast = 0 },
      { id = 15430, cost = 290, lvl = 28, bl = 28, ml = 34, bp = 82, ppl = 0.5, coeff = 0.107, cast = 0 },
      { id = 15431, cost = 400, lvl = 36, bl = 36, ml = 42, bp = 116, ppl = 0.6, coeff = 0.107, cast = 0 },
      { id = 27799, cost = 520, lvl = 44, bl = 44, ml = 50, bp = 159, ppl = 0.7, coeff = 0.107, cast = 0 },
      { id = 27800, cost = 635, lvl = 52, bl = 52, ml = 58, bp = 238, ppl = 0.8, coeff = 0.107, cast = 0 },
      { id = 27801, cost = 750, lvl = 60, bl = 60, ml = 66, bp = 311, ppl = 0.9, coeff = 0.107, cast = 0 },
    } },
    PENANCE = { name = "Penance", ranks = {
      { id = 402174, cost = 150, lvl = 30, bl = 30, ml = 39, bp = 378, ppl = 2.61, coeff = 0.57, cast = 2000 },
      { id = 1240720, cost = 220, lvl = 40, bl = 40, ml = 49, bp = 600, ppl = 2.94, coeff = 0.57, cast = 2000 },
      { id = 1240721, cost = 270, lvl = 50, bl = 50, ml = 59, bp = 804, ppl = 3.81, coeff = 0.57, cast = 2000 },
      { id = 1316995, cost = 385, lvl = 60, bl = 60, ml = 60, bp = 1275, ppl = 0, coeff = 0.57, cast = 2000 },
    } },
  },
  timing = {  -- seconds: cd = its own cooldown, dur = how long it lasts, lockout = Weakened Soul
    POM = { cd = 10 },
    PENANCE = { cd = 12 },
    PWS = { cd = 4, lockout = 15 },
    RENEW = { dur = 15 },
  },
  talents = {  -- value per rank (percent, except divineFury: seconds)
    twinDisciplines = { 1, 2, 3, 4, 5 },
    improvedPWS = { 7, 14, 20 },
    mentalAgility = { 3, 7, 10 },
    meditation = { 17, 33, 50 },
    mentalStrength = { 2, 4, 6, 8, 10 },
    divineAegis = { 5, 10, 15 },
    improvedRenew = { 5, 10, 15 },
    holySpecialization = { 1, 2, 3, 4, 5 },
    divineFury = { 0.1, 0.2, 0.3, 0.4, 0.5 },
    inspiration = { 8, 17, 25 },
    improvedHealing = { 5, 10, 15 },
    litanyOfLight = { 5, 10 },
    spiritualGuidance = { 5, 10, 15, 20, 25 },
    spiritualHealing = { 3, 7, 10 },
    renewedHope = { 2, 4, 6, 8, 10 },
    holyBinding = { 50 },
  },
}
if ns then ns.PriestData = D end
return D
