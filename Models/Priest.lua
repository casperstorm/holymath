--[[ Holy Math - Models/Priest.lua
     The healing-priest model, in plain Lua with no game calls, so it runs in the
     game AND under a desktop Lua (tests/run_tests.lua checks it against the sheet).

     Ported from the community healer-priest sheet (tabs "Profile", "Spells", "Sim").
     The sheet's spell table is the default; stats, talent ranks and known spell
     ranks come from the game (Game.lua).

     Where the sheet has a formula slip, this model does the intended thing and the
     test file names the slip and the size of the difference.

     WHAT A CLASS MODEL PROVIDES (so another healer can be added as Models/<Class>.lua):
       SPELLS, SHEET_SPELLS, SPELL_KEYS (spell name -> key), TALENT_NAMES (key -> name),
       OVERHEAL_ALIASES, DEFAULTS.settings, DEFAULT_ROTATION, ROTATIONS, WEIGHT_STATS,
       EVENTS_PER_CAST, Talents, AdjustTalents, CritTalent, CastingRegenShare,
       Multipliers, StatDelta, Spell, MaxRank, Downrank, ManaBudget, Rotation,
       Weights, Score, Compare, copy
]]--

local _, ns = ...
ns = ns or {}
local E = {}
ns.Models = ns.Models or {}
ns.Models.PRIEST = E

-- Game spell names (English client) -> keys below
E.SPELL_KEYS = {
  ["Renew"] = "RENEW", ["Greater Heal"] = "GH", ["Flash Heal"] = "FLASH",
  ["Heal"] = "HEAL", ["Prayer of Healing"] = "POH", ["Penance"] = "PENANCE",
  ["Prayer of Mending"] = "POM", ["Holy Nova"] = "NOVA", ["Power Word: Shield"] = "PWS",
  ["Lesser Heal"] = "LESSER",
}

-- Talents the model uses: key -> name in Forever's talent tree
E.TALENT_NAMES = {
  twinDisciplines = "Twin Disciplines", improvedPWS = "Improved Power Word: Shield",
  mentalAgility = "Mental Agility", innerFocus = "Inner Focus", meditation = "Meditation",
  mentalStrength = "Mental Strength", soulWarding = "Soul Warding", penance = "Penance",
  divineAegis = "Divine Aegis", improvedRenew = "Improved Renew",
  holySpecialization = "Holy Specialization", divineFury = "Divine Fury",
  inspiration = "Inspiration", improvedHealing = "Improved Healing",
  litanyOfLight = "Litany of Light", spiritualGuidance = "Spiritual Guidance",
  spiritualHealing = "Spiritual Healing", prayerOfMending = "Prayer of Mending",
  renewedHope = "Renewed Hope", holyBinding = "Holy Binding",
}

-- Short names for /hm set oh <spell> <percent>
E.OVERHEAL_ALIASES = { renew = "RENEW", pws = "PWS", gh = "GH", poh = "POH", penance = "PENANCE",
                       flash = "FLASH", nova = "NOVA", pom = "POM", lesser = "LESSER", heal = "HEAL" }

E.DEFAULT_ROTATION = "renew"

-- What a priest can wear and wield (item class/subclass ids are the game's own,
-- the same in every language). Weapon list as StatCap uses it: a BAN list, so a
-- weapon type missing here is shown, never hidden.
--   priests use: one-handed maces (4), staves (10), daggers (15), wands (19)
E.EQUIP = {
  armorRank = 1,                 -- 1 cloth, 2 leather, 3 mail, 4 plate
  noShield = true,
  noWeapon = { [0] = true, [1] = true, [2] = true, [3] = true, [5] = true, [6] = true, [7] = true,
               [8] = true, [9] = true, [13] = true, [16] = true, [18] = true },
  -- 0 1H axe, 1 2H axe, 2 bow, 3 gun, 5 2H mace, 6 polearm, 7 1H sword, 8 2H sword,
  -- 9 warglaive, 13 fist weapon, 16 thrown, 18 crossbow
}

-- Some talents only matter as "do you have the spell": Prayer of Mending,
-- Penance and Inner Focus are talents that teach a spell. Forever has no Binding
-- Heal spell: the Holy Binding talent makes Flash Heal on someone else also heal
-- you for 50% as much, which is what the sheet's "Binding Heal" stands for.
function E.AdjustTalents(ranks, known, byName)
  ranks.prayerOfMending = known.POM and 1 or 0
  ranks.penance = known.PENANCE and 1 or 0
  ranks.bindingHeal = (ranks.holyBinding or 0) > 0 and known.FLASH and 1 or 0
  ranks.innerFocus = (byName["Inner Focus"] and byName["Inner Focus"].rank or 0) > 0 and 1 or 0
  return ranks
end

-- The talent that adds crit to this class's healing school only (Holy
-- Specialization: +1% per rank to Holy spells), the school the heals are in,
-- and another school to compare against, to see if the client already counts it.
function E.CritTalent(ranks)
  return ranks.holySpecialization or 0, 2, 6, "Holy Spec"
end

-- Share of spirit regen that continues while casting (Meditation: 1/6 per rank).
function E.CastingRegenShare(ranks)
  return (ranks.meditation or 0) * (0.5 / 3)
end

local max, min, ceil, exp = math.max, math.min, math.ceil, math.exp

---------------------------------------------------------------------------
-- Spell data (sheet "Spells" tab). base = total heal over the whole spell
-- (Renew: whole HoT; PoH/Nova: per target; Penance: all 3 ticks; PoM: per hit).
-- coeff = healing-power coefficient before talents and downranking.
---------------------------------------------------------------------------
local function R(cost, base, lvl) return { cost = cost, base = base, lvl = lvl } end

-- THE SHEET'S spell table, kept only so tests/run_tests.lua can still check that
-- the sheet's own numbers are reproduced (rules.table = "sheet"). The game uses
-- E.SPELLS, built below from the game's data.
E.SHEET_SPELLS = {
  PWS = { name = "Power Word: Shield", coeff = 0.1, cast = "gcd", shield = true,
    ranks = { R(45,48,6), R(80,92,12), R(130,162,18), R(175,236,24), R(210,303,30),
              R(250,381,36), R(300,485,42), R(355,608,48), R(425,769,54), R(500,950,60) } },
  RENEW = { name = "Renew", coeff = 1.0, cast = "gcd",
    ranks = { R(30,45,8), R(65,75,14), R(105,125,20), R(140,160,26), R(170,205,32),
              R(205,270,38), R(250,370,44), R(305,510,50), R(365,670,56) } },
  GH = { name = "Greater Heal", coeff = 3 / 3.5, cast = "gh",
    -- In the client rank 1 costs 370 (sheet 360) and rank 2 heals ~1% less than
    -- the sheet's base; ApplyClientData corrects both from the game at runtime.
    ranks = { R(360,869.5,40), R(455,1128,46), R(545,1436,52), R(655,1782,58) } },
  FLASH = { name = "Flash Heal", coeff = 1.5 / 3.5, cast = 1.5,
    ranks = { R(125,203,20), R(155,260,26), R(185,324,32), R(215,397,38),
              R(265,523,44), R(315,662,50), R(380,846,56) } },
  BH = { name = "Binding Heal", coeff = 1.5 / 3.5, cast = 1.5, bodies = 1.5,
    ranks = { R(155,260,26), R(185,324,32), R(215,397,38), R(265,523,44),
              R(315,662,50), R(380,846,56) } },
  POH = { name = "Prayer of Healing", coeff = 0.2887, cast = 3, targets = 5,
    ranks = { R(410,185,30), R(560,273.5,40), R(770,412.5,50), R(1030,596,60) } },
  PENANCE = { name = "Penance", coeff = 2 / 3.5, cast = 2,
    ranks = { R(150,402,30), R(220,627,40), R(270,837,50), R(385,1275,60) } },
  POM = { name = "Prayer of Mending", coeff = 1.5 / 3.5, cast = "gcd", targets = "pomhits",
    ranks = { R(210,172,40), R(305,298,50), R(390,413,60) } },
  NOVA = { name = "Holy Nova", coeff = 0.24, cast = "gcd", targets = 5,
    ranks = { R(185,54,20), R(290,85,28), R(400,120,36), R(520,163,44), R(635,243,52), R(750,314,60) } },
  LESSER = { name = "Lesser Heal",
    ranks = { -- each rank has its own cast time and coefficient
      { cost = 30, base = 52,  lvl = 1,  cast = 1.5, coeff = 1.5 / 3.5 },
      { cost = 45, base = 97.5, lvl = 4, cast = 2.0, coeff = 2.0 / 3.5 },
      -- The sheet uses 74.75 here (the average of ranks 1 and 2, a slip); its own
      -- test cells at C154:C156 measure rank 3 at 157-181, average 169.
      { cost = 75, base = 169, lvl = 10, cast = 2.5, coeff = 2.5 / 3.5 } } },
}

local function copy(v) if type(v) ~= "table" then return v end local o = {} for k, x in pairs(v) do o[k] = copy(x) end return o end
E.copy = copy

-- THE GAME'S spell table: Models/PriestData.lua, generated from the game data in
-- wowsims/forever (tools/gen_priest_data.py). Each rank: base heal bp at level bl,
-- growing ppl per level up to ml; coefficient; cost; learned level; cast time.
local DATA = ns.PriestData or (dofile and dofile("Models/PriestData.lua"))   -- desktop tests load it by path
E.DATA = DATA
local SHAPE = { PWS = { shield = true }, POH = { targets = 5 }, NOVA = { targets = 5 }, POM = { targets = "pomhits" } }
E.GAME_SPELLS = {}
for key, sp in pairs(DATA.spells) do
  local def = { name = sp.name, ranks = {} }
  for k, v in pairs(SHAPE[key] or {}) do def[k] = v end
  for i, r in ipairs(sp.ranks) do
    def.ranks[i] = { id = r.id, cost = r.cost, lvl = r.lvl, bl = r.bl, ml = r.ml, bp = r.bp, ppl = r.ppl,
                     coeff = r.coeff, cast = r.cast > 0 and r.cast / 1000 or "gcd" }
  end
  E.GAME_SPELLS[key] = def
end
-- E.SPELLS is the working copy: ApplyClientData may correct it from the client's tooltips.
E.SPELLS = copy(E.GAME_SPELLS)

local function tableFor(set)
  return (set and set.rules and set.rules.table == "sheet") and E.SHEET_SPELLS or E.SPELLS
end
E.tableFor = tableFor

-- A rank's base heal at a player level: it grows from its base level up to its max level.
-- (The sheet's table has one fixed number per rank, which it calls base.)
local function baseAt(rk, level)
  if rk.base then return rk.base end
  local top = (rk.ml and rk.ml > 0) and min(level, rk.ml) or level
  return rk.bp + rk.ppl * max(0, top - rk.bl)
end
E.BaseAt = baseAt

-- Litany of Light refunds part of a heal's base cost when it follows a DIFFERENT heal
-- (game data; wowsims models it the same way). These are the heals it counts.
E.LITANY_SPELLS = { FLASH = true, LESSER = true, HEAL = true, GH = true, RENEW = true, PENANCE = true, POH = true, POM = true }

-- How many separate heal events one cast makes on one target (used to compare
-- the model with single combat-log lines): Renew ticks 5 times, Penance 3 times,
-- Binding Heal's 1.5 "bodies" are two events (target + self, self = half).
E.EVENTS_PER_CAST = { RENEW = 5, PENANCE = 3, BH = 1.5 }

-- Which talents scale each spell's base heal and its coefficient, and which cut its cost.
local function talentMult(key, t)
  if key == "RENEW" then return t.impRenew * t.twinDisc * t.spiritualHealing end
  if key == "PENANCE" or key == "POM" or key == "NOVA" then return t.spiritualHealing * t.twinDisc end
  if key == "PWS" then return 1 end
  return t.spiritualHealing
end

local function costMult(key, t)
  if key == "PWS"     then return 1 - t.soulWarding - t.mentalAgility end
  if key == "RENEW"   then return 1 - t.mentalAgility - t.litany end
  if key == "GH" or key == "HEAL" or key == "LESSER" or key == "PENANCE" then return 1 - t.impHealing - t.litany end
  if key == "POM"     then return 1 - t.litany - t.impHealing - t.mentalAgility end
  if key == "NOVA"    then return 1 - t.litany - t.mentalAgility end
  return 1 - t.litany -- Flash, Binding Heal, Prayer of Healing
end

-- E.RULES: the game (game data + what the client's tooltips showed, 20 Nov 2026).
-- E.SHEET_RULES: reproduces the sheet exactly (used by the sheet tests only).
E.RULES = {
  table = "game",              -- spell table from the game data
  talents = "game",            -- talent values per rank from the game data
  downrank = "maxLevel",       -- penalty starts 12 levels after the rank's max level
  twinDiscOnShield = false,    -- Twin Disciplines does not raise PW:Shield's absorb
  litany = "refund",           -- Litany of Light refunds mana when a heal follows a different one
  fiveSecond = "seconds",      -- regen pauses: mana per 5 s converted to per second (see pauseCycle)
  autoRanks = true,            -- playstyles pick the ranks that heal most
  pomWithoutSpiritHealing = true, -- Prayer of Mending ignores Spiritual Guidance's healing (see healingFor)
}
E.SHEET_RULES = { table = "sheet", talents = "sheet", downrank = "learned", downrankFreeLevels = 16,
                  twinDiscOnShield = true, litany = "discount", fiveSecond = "sheet" }

-- Seconds one extra cast takes when you pause to regenerate its mana: wait out the
-- 5-second rule, regenerate the cost at your out-of-combat spirit regen, cast it.
-- The sheet's formula divides the cost by regen per 5 seconds as if it were per
-- second, which made pauses look about 5 times more useful (rules.fiveSecond = "sheet").
local function pauseCycle(cost, castTime, st, rules)
  local net = st.oocRegen - st.combatRegen          -- mana per 5 s gained by not casting
  if net <= 0 then return math.huge end
  if (rules or E.RULES).fiveSecond == "sheet" then return 5 + cost / net + 2 + st.haste end
  return 5 + cost / (net / 5) + castTime
end
E.PauseCycle = pauseCycle

-- The healing power a spell gets. Prayer of Mending, in the client's own tooltips,
-- ignores the part of your healing power that Spiritual Guidance gives you from
-- spirit: two dumps (20 Nov 2026) - 259 at 175 healing (no Spiritual Guidance) and
-- 287 at 224 = 175 + 49 from Spiritual Guidance - only fit (172 + 0.429 x 175) with
-- Twin Disciplines and Spiritual Healing applied. st.healingFromSpirit is that part.
local function healingFor(key, st, rules)
  if key == "POM" and (rules or E.RULES).pomWithoutSpiritHealing then
    return st.healing - (st.healingFromSpirit or 0)
  end
  return st.healing
end
E.HealingFor = healingFor

-- Forever's downranking: a rank loses 5% of its coefficient for every level the
-- player is past (its max level + 12), and never drops under 10% of it. For the
-- usual rank (max level = learned + 5) that is "17 levels after it is learned".
-- Prayer of Healing rank 1 (max 39) and Penance rank 1 (max 39) keep their full
-- coefficient at level 49 in the client, which only this form explains.
-- A rank with no max level in the data counts as learned + 5.
-- The sheet's rule (rules.downrank = "learned"): 16 levels after it is learned.
function E.Downrank(coeff, rk, playerLevel, rules)
  rules = rules or E.RULES
  local below
  if rules.downrank == "maxLevel" then
    local top = (rk.ml and rk.ml > 0) and rk.ml or (rk.lvl + 5)
    below = max(0, playerLevel - 12 - top)
  else
    below = max(0, (playerLevel - rules.downrankFreeLevels) - rk.lvl)
  end
  return max(coeff * 0.1, coeff - below * 0.05 * coeff)
end

---------------------------------------------------------------------------
-- Talents, buffs and settings (sheet "Profile" switches) -> multipliers.
---------------------------------------------------------------------------
E.DEFAULTS = {
  level = 60,
  gear = { healing = 641, int = 270, crit = 1, haste = 0, mp5 = 18, spirit = 352, spelldamage = 300 },
  buffs = { manaSpring = true, divineSpirit = true, wisdom = true, critAura = true, arcaneInt = true,
            kings = true, mark = true, ampMagic = false, dampMagic = false, shadowSpirit = true },
  -- talent ranks as on the sheet's Profile E19:F42
  talents = { twinDisciplines = 5, improvedPWS = 2, mentalAgility = 3, innerFocus = 1, meditation = 3,
              mentalStrength = 5, soulWarding = 0, penance = 0, divineAegis = 0,
              improvedRenew = 3, holySpecialization = 5, divineFury = 5, inspiration = 3,
              improvedHealing = 3, litanyOfLight = 2, spiritualGuidance = 5, spiritualHealing = 3,
              prayerOfMending = 1, bindingHeal = 1, renewedHope = 0 },
  consumables = { spiritFood = true, intFood = false, healingFood = false, distilledWisdom = true,
                  brilliantManaOil = true, blessedWizardOil = false, brilliantWizardOil = false,
                  darkRune = false, elixirOwl = true, elixirWhale = false, greaterClerics = false,
                  greaterMageblood = false, kreegsStout = true, spiritOfZanza = false,
                  naturalAggression = false },
  race = { human = true, dwarf = false, gnome = false, troll = false },
  settings = {
    fightLength = 300, pomHits = 4, innervate = false, majorManaPotions = true, cheapManaPotions = false,
    manaTidesInGroup = 1, powerInfusionOut = false, includeInspiration = true,
    tankArmor = 6000, tankRawDTPS = 1200, inspirationIntoTank = 0.8,
    overheal = { RENEW = 0.25, PWS = 0.05, GH = 0.25, POH = 0.35, PENANCE = 0.25, BH = 0.25,
                 FLASH = 0.25, NOVA = 0.45, POM = 0.15, LESSER = 0.25, HEAL = 0.25 },
    -- Litany of Light: share of a heal's casts that follow a DIFFERENT heal. Rotations work
    -- it out from their own spell mix; this is only used when a spell is looked at alone.
    litanyAlternation = 0.5,
    imperfectPlay = 0.8, -- the sheet's factor for downtime you actually use under the 5-second rule
  },
}

local function curve(name, rank)
  local c = DATA.talents[name]
  if not c or not rank or rank <= 0 then return 0 end
  return c[math.min(rank, #c)]
end

function E.Talents(tr, rules)
  if (rules or E.RULES).talents == "game" then
    return {
      twinDisc = 1 + curve("twinDisciplines", tr.twinDisciplines) / 100,
      impPWS = 1 + curve("improvedPWS", tr.improvedPWS) / 100,
      mentalAgility = curve("mentalAgility", tr.mentalAgility) / 100,
      innerFocus = (tr.innerFocus or 0) > 0 and 1 or 0,
      meditation = curve("meditation", tr.meditation) / 100,
      mentalStrength = 1 + curve("mentalStrength", tr.mentalStrength) / 100,
      soulWarding = (tr.soulWarding or 0) > 0 and 0.15 or 0,   -- the sheet's value; not in the game data's curves
      penance = (tr.penance or 0) > 0,
      daMulti = curve("divineAegis", tr.divineAegis) / 100,
      impRenew = 1 + curve("improvedRenew", tr.improvedRenew) / 100,
      holySpec = curve("holySpecialization", tr.holySpecialization) / 100,
      divineFury = curve("divineFury", tr.divineFury),            -- seconds
      inspiration = curve("inspiration", tr.inspiration) / 100,
      impHealing = curve("improvedHealing", tr.improvedHealing) / 100,
      litany = 0,                                                 -- not a discount in the game...
      litanyRefund = curve("litanyOfLight", tr.litanyOfLight) / 100, -- ...a refund (see E.LITANY_SPELLS)
      spiritualGuidance = curve("spiritualGuidance", tr.spiritualGuidance) / 100,
      spiritualHealing = 1 + curve("spiritualHealing", tr.spiritualHealing) / 100,
      pom = (tr.prayerOfMending or 0) > 0,
      bindingHeal = (tr.bindingHeal or 0) > 0,
      holyBinding = curve("holyBinding", tr.holyBinding) / 100,   -- Flash Heal also heals you this share
      renewedHope = tr.renewedHope or 0,
      renewedHopeCrit = curve("renewedHope", tr.renewedHope) / 100,
    }
  end
  return {   -- the sheet's values
    litanyRefund = 0, holyBinding = 0,
    renewedHopeCrit = tr.renewedHope * 0.02,
    twinDisc = 1 + tr.twinDisciplines * 0.01,
    impPWS = 1 + (0.2 / 3) * tr.improvedPWS,
    mentalAgility = tr.mentalAgility * 0.03,
    innerFocus = tr.innerFocus > 0 and 1 or 0,
    meditation = tr.meditation * (0.5 / 3),
    mentalStrength = 1 + tr.mentalStrength * 0.02,
    soulWarding = tr.soulWarding > 0 and 0.15 or 0,
    penance = tr.penance > 0,
    daMulti = tr.divineAegis * 0.05,
    impRenew = 1 + tr.improvedRenew * 0.05,
    holySpec = tr.holySpecialization * 0.01,
    divineFury = tr.divineFury * 0.1,
    inspiration = tr.inspiration * (0.25 / 3),
    impHealing = tr.improvedHealing * 0.05,
    litany = tr.litanyOfLight * 0.05,
    spiritualGuidance = tr.spiritualGuidance * 0.05,
    spiritualHealing = 1 + tr.spiritualHealing * 0.03,
    pom = tr.prayerOfMending > 0,
    bindingHeal = tr.bindingHeal > 0,
    renewedHope = tr.renewedHope,
  }
end

---------------------------------------------------------------------------
-- Gear stats + buffs -> final stats (sheet Profile column C/E). In game, the
-- client gives the final stats directly and this is only used for tests and for
-- the marginal "what does +1 of a gear stat become" factors.
---------------------------------------------------------------------------
local function on(b, v) return b and v or 0 end

-- How one point of each stat ON GEAR turns into final stats, given buffs/talents.
function E.Multipliers(input)
  local b, c, r, t = input.buffs, input.consumables, input.race, E.Talents(input.talents, input.settings.rules)
  local kings = b.kings and 1.1 or 1
  local spiritMult = kings * (r.human and 1.1 or 1) * (b.shadowSpirit and 1.15 or 1)
  local intMult = t.mentalStrength * kings
  return {
    spirit = spiritMult, int = intMult,
    healingPerSpirit = t.spiritualGuidance,         -- Spiritual Guidance
    spellDamagePerSpirit = input.talents.spiritualGuidance * 0.01,
    manaPerInt = 15 * (r.gnome and 1.05 or 1),
    critPctPerInt = 1 / 60,
    -- out-of-combat mp5 per spirit: sheet 0.64 (+40); the client fits the classic
    -- priest formula, 2.5 x (13 + spirit/4) = 32.5 + 0.625 x spirit, within 1%.
    regenPerSpirit = input.regenPerSpirit or 0.64,
  }
end

function E.Derive(input)
  local g, b, c, r, s = input.gear, input.buffs, input.consumables, input.race, input.settings
  local t = E.Talents(input.talents, input.settings.rules)
  local m = E.Multipliers(input)

  local spirit = (g.spirit + on(b.divineSpirit, 40) + on(b.mark, 16) + on(c.spiritFood, 20)
                  + on(c.elixirWhale, 25) + on(c.kreegsStout, 25) + on(c.spiritOfZanza, 50)) * m.spirit
  local int = (on(b.mark, 16) + on(b.arcaneInt, 31) + g.int + on(c.intFood, 20) + on(c.elixirOwl, 25)
               - on(c.kreegsStout, 25) / 5) * m.int
  local healing = g.healing + on(b.ampMagic, 225) + on(b.dampMagic, -180) + spirit * m.healingPerSpirit
                  + on(c.brilliantManaOil, 30) + on(c.brilliantWizardOil, 36) + on(c.healingFood, 44)
                  + on(c.greaterClerics, 40)
  local crit = on(b.critAura, 0.03) + t.holySpec + (int * m.critPctPerInt + g.crit) / 100
               + on(c.blessedWizardOil, 0.01) + on(c.naturalAggression, 0.04) + on(c.elixirWhale, 0.02)
               + on(c.elixirOwl, 0.02) + on(r.human, 0.01)
  local haste = g.haste / 100 + on(r.troll, 0.0056)
  local mp5 = g.mp5 + on(b.manaSpring, 25) + on(b.wisdom, 40) + on(c.brilliantManaOil, 15)
              + on(c.darkRune, 50) + on(c.greaterMageblood, 20)
  local ooc = 40 + spirit * m.regenPerSpirit
  return {
    level = input.level,
    healing = healing, spelldamage = g.spelldamage + spirit * m.spellDamagePerSpirit,
    healingFromSpirit = spirit * m.healingPerSpirit,
    int = int, spirit = spirit, crit = crit, haste = haste, mp5 = mp5,
    oocRegen = ooc, combatRegen = ooc * t.meditation,
    manaPool = (int * 15 + on(c.distilledWisdom, 2000)) * (r.gnome and 1.05 or 1),
    critMulti = 1.5, -- the sheet's Dwarf crit-damage racial is set to 0 for healing
  }
end

-- +1 of a gear stat, expressed as a change in final stats (exact, because Derive is linear).
function E.StatDelta(input, stat)
  local m = E.Multipliers(input)
  local gnome = input.race.gnome and 1.05 or 1
  if stat == "healing" then return { healing = 1 } end
  if stat == "crit" then return { crit = 0.01 } end           -- +1% crit
  if stat == "haste" then return { haste = 0.01 } end         -- +1% haste
  if stat == "mp5" then return { mp5 = 1 } end
  if stat == "int" then
    local i = m.int
    return { int = i, crit = i * m.critPctPerInt / 100, manaPool = i * 15 * gnome }
  end
  if stat == "spirit" then
    local sp = m.spirit
    local med = E.Talents(input.talents, input.settings.rules).meditation
    return { spirit = sp, healing = sp * m.healingPerSpirit, healingFromSpirit = sp * m.healingPerSpirit,
             spelldamage = sp * m.spellDamagePerSpirit,
             oocRegen = sp * m.regenPerSpirit, combatRegen = sp * m.regenPerSpirit * med }
  end
  if stat == "spelldamage" then return { spelldamage = 1 } end
end

---------------------------------------------------------------------------
-- One spell rank at the given final stats (sheet Spells row: J..O, P, Q).
---------------------------------------------------------------------------
function E.Spell(key, rankIdx, st, t, set)
  local sp = tableFor(set)[key]
  local rk = sp.ranks[rankIdx]
  local gcd = 1.5 / (1 + st.haste)
  local cast
  local ct = rk.cast or sp.cast
  if ct == "gcd" then cast = gcd
  elseif ct == "gh" then cast = (3 - t.divineFury) / (1 + st.haste)
  elseif key == "GH" or key == "HEAL" then cast = (ct - t.divineFury) / (1 + st.haste)  -- Divine Fury
  else cast = ct / (1 + st.haste) end

  local rules = set.rules or E.RULES
  local coeff = E.Downrank(rk.coeff or sp.coeff, rk, st.level, rules)
  local base = baseAt(rk, st.level)
  local bodies = sp.bodies or ((key == "FLASH" and (t.holyBinding or 0) > 0) and (1 + t.holyBinding)) or 1
  local heal, crit = 0, st.crit
  if sp.shield then
    heal = (base + coeff * (rules.twinDiscOnShield and t.twinDisc or 1) * healingFor(key, st, rules)) * t.impPWS
  else
    local tm = talentMult(key, t)
    heal = (base * tm + coeff * tm * healingFor(key, st, rules)) * bodies
  end
  local expected = sp.shield and heal or heal * ((1 - crit) + crit * st.critMulti)
  local aegis = sp.shield and 0 or heal * crit * t.daMulti
  local cost = rk.cost * costMult(key, t) - (set.dungeon4set and 10 or 0)
  if (t.litanyRefund or 0) > 0 and E.LITANY_SPELLS[key] then
    local share = set.litanyShare and set.litanyShare[key] or set.litanyAlternation or 0.5
    cost = cost - rk.cost * t.litanyRefund * share
  end
  local targets = sp.targets == "pomhits" and set.pomHits or (sp.targets or 1)
  -- Renewed Hope variants (crit chance with the talent's bonus, crits fixed at 1.5x)
  local rcrit = crit + t.renewedHopeCrit
  local expectedRH = sp.shield and heal or heal * ((1 - rcrit) + rcrit * 1.5)
  return {
    key = key, rank = rankIdx, name = sp.name, cast = cast, coeff = coeff, bodies = bodies,
    heal = heal,                 -- one cast, one target, non-crit
    expected = expected,         -- one target, crit-weighted
    aegis = aegis,               -- Divine Aegis absorb per target
    expectedRH = expectedRH, aegisRH = heal * rcrit * t.daMulti,
    cost = cost, targets = targets,
    hpm = targets * (expected + aegis) / cost,
    hpct = targets * (expected + aegis) / cast,
  }
end

-- Highest usable rank, or nil if the spell isn't available. If `known` is given
-- (in game: highest rank in the spellbook per spell key) it decides; otherwise
-- the level decides (tests, and the sheet).
function E.MaxRank(key, level, known, set)
  local def = tableFor(set)[key]
  if not def then return nil end              -- e.g. Binding Heal: not in Forever's game data
  if known then
    local k = known[key]
    if not k or k < 1 then return nil end
    return math.min(k, #def.ranks)
  end
  local best
  for i, rk in ipairs(def.ranks) do if rk.lvl <= level then best = i end end
  return best
end

---------------------------------------------------------------------------
-- The client's own spell tooltips. In Forever they already include your healing
-- power and talents (e.g. Renew rank 7 at 175 healing, Twin Disciplines 4/5:
-- (370 + 175) x 1.04 = 566, exactly what the tooltip says). So each tooltip is
-- an exact check of the model, and lets us correct the sheet's base heals.
---------------------------------------------------------------------------
local DESC = {
  RENEW = "of ([%d,]+) damage over",
  PWS = "absorbing ([%d,]+) damage",
  POM = "heals them for ([%d,]+)",
  PENANCE = "or ([%d,]+) healing to an ally",   -- per tick; 3 ticks
}
local function n(x) return tonumber((x:gsub(",", ""))) end

-- One target, one cast, no crit - as the tooltip states it (Penance: all ticks).
function E.ParseDesc(key, desc)
  if type(desc) ~= "string" then return nil end
  local p = DESC[key]
  if p then
    local v = desc:match(p)
    if not v then return nil end
    return n(v) * (key == "PENANCE" and 3 or 1)
  end
  local a, b = desc:match("for ([%d,]+) to ([%d,]+)")
  if a then return (n(a) + n(b)) / 2 end
  return nil
end

-- The model's number for the same thing.
function E.ModelTooltipHeal(key, rank, st, t, set)
  local sp = E.Spell(key, rank, st, t, set)
  return sp.heal / sp.bodies
end

-- Base heal that makes the model match the client at your current healing power.
local function baseFromClient(key, rank, h, st, t, set)
  local def = tableFor(set)[key]
  local rk = def.ranks[rank]
  local rules = set.rules or E.RULES
  local coeff = E.Downrank(rk.coeff or def.coeff, rk, st.level, rules)
  if def.shield then
    return h / t.impPWS - coeff * (rules.twinDiscOnShield and t.twinDisc or 1) * healingFor(key, st, rules)
  end
  return h / talentMult(key, t) - coeff * healingFor(key, st, rules)
end

-- spells = { { key=, rank=, cost=, desc= }, ... } read from the game.
-- Starts from the sheet's table every time, then takes the client's cost when it is
-- within 3% of the sheet's (a bigger gap may be a talent discount already applied,
-- which must not be applied twice) and the client's heal when the model is within
-- 5% of it (a bigger gap means a rule is wrong - reported, not hidden).
-- Returns one report row per spell rank.
E.COST_TOLERANCE, E.HEAL_TOLERANCE = 0.03, 0.05
function E.ApplyClientData(spells, st, t, set)
  E.SPELLS = E.copy(E.GAME_SPELLS)
  local report = {}
  for _, c in ipairs(spells) do
    local def = E.SPELLS[c.key]
    local rk = def and def.ranks[c.rank]
    if rk then
      local row = { key = c.key, rank = c.rank, dataCost = rk.cost, clientCost = c.cost, dataBase = baseAt(rk, st.level) }
      if c.cost and c.cost > 0 and math.abs(c.cost / rk.cost - 1) <= E.COST_TOLERANCE then
        rk.cost, row.costFrom = c.cost, "client"
      end
      local h = E.ParseDesc(c.key, c.desc)
      if h then
        row.client = h
        row.model = E.ModelTooltipHeal(c.key, c.rank, st, t, set)
        row.diff = row.client / row.model - 1
        if math.abs(row.diff) <= E.HEAL_TOLERANCE then
          rk.base = baseFromClient(c.key, c.rank, h, st, t, set)
          row.baseFrom = "client"
        end
        row.base = baseAt(rk, st.level)
      end
      report[#report + 1] = row
    end
  end
  return report
end

---------------------------------------------------------------------------
-- Mana budget for the fight (sheet Sim F4:O6).
---------------------------------------------------------------------------
function E.ManaBudget(st, t, set)
  local fl = set.fightLength
  local ticks = fl / 5
  local pots = max(1, ceil((fl - 15) / 120)) * ((set.majorManaPotions and 1800 or 0) + (set.cheapManaPotions and 1200 or 0))
  local tides = max(1, ceil((fl - 5) / 300)) * set.manaTidesInGroup * 290 * 4
  local innervate = max(1, ceil((fl - 15) / 360)) * (set.innervate and 1 or 0) * (st.oocRegen * 5 - st.combatRegen) * 4
  local pi = set.powerInfusionOut and -250 * max(1, fl / 180) or 0
  return ticks * st.mp5 + st.manaPool + ticks * st.combatRegen + pots + tides + innervate + pi
end

---------------------------------------------------------------------------
-- Rotations (sheet Sim blocks). Each step casts a spell as many times as its cap,
-- the remaining mana and the remaining GCDs allow, in priority order; the last
-- step fills. Leftover GCDs become regen time under the 5-second rule, which buys
-- a few more filler casts (sheet "5sr estimation").
---------------------------------------------------------------------------
-- auto = this step's rank is chosen by the model (game rules): the rank that
-- makes the playstyle heal most. sheetOnly = kept for the sheet tests, not offered.
E.ROTATIONS = {
  renew = { name = "Renew filler",
    help = "Renew on whoever needs it; Greater Heal twice a minute for the tank.",
    steps = { { "POM", cap = 10, needs = "pom", tank = 1, auto = true },
              { "PENANCE", cap = 12, needs = "penance", tank = 3, auto = true },
              { "BH", cap = 30, needs = "bindingHeal", tank = 1, auto = true },
              { "GH", cap = 30, tank = 1, auto = true },
              { "RENEW", fill = true, auto = true } } },
  ghFill = { name = "Greater Heal filler",
    help = "Greater Heal most of the time, on the tank: big, slow, mana-efficient heals.",
    steps = { { "POM", cap = 10, needs = "pom", tank = 1, auto = true },
              { "PENANCE", cap = 12, needs = "penance", tank = 3, auto = true },
              { "BH", cap = 30, needs = "bindingHeal", tank = 1, auto = true },
              { "GH", fill = true, tank = 1, auto = true } } },
  flashFill = { name = "Flash Heal filler",
    help = "Flash Heal most of the time: fast heals, more healing per second, less per mana.",
    steps = { { "POM", cap = 10, needs = "pom", tank = 1, auto = true },
              { "PENANCE", cap = 12, needs = "penance", tank = 3, auto = true },
              { "FLASH", fill = true, tank = 1, auto = true } } },
  pohFill = { name = "Prayer of Healing filler",
    help = "Prayer of Healing most of the time, for group damage (dungeons, raid AoE). Counts 5 people " ..
      "healed per cast, minus your overheal setting.",
    steps = { { "POM", cap = 10, needs = "pom", tank = 1, auto = true },
              { "PENANCE", cap = 12, needs = "penance", tank = 3, auto = true },
              { "POH", fill = true, auto = true } } },
  -- From the sheet (Sim, third block): a rank 1 shield keeps Weakened Soul on the
  -- tank, so heals on it get Renewed Hope's extra crit. Only offered with the talent.
  rhTank = { name = "Renewed Hope tank", renewedHope = true, requires = "renewedHope",
    help = "For Discipline with Renewed Hope: a rank 1 PW:Shield keeps Weakened Soul on the tank, so " ..
      "Penance, Flash Heal and Greater Heal on it crit more often; Renew for everyone else.",
    steps = { { "POM", cap = 10, needs = "pom", tank = 1, auto = true },
              { "PENANCE", cap = 12, needs = "penance", tank = 3, auto = true },
              { "PWS", rank = 1, cap = 10, tank = 1 },
              { "BH", cap = 30, needs = "bindingHeal", tank = 1, auto = true },
              { "GH", cap = 30, tank = 1, auto = true },
              { "RENEW", fill = true, auto = true } } },
  renewDown = { name = "Renew filler (downranked)", sheetOnly = true,
    steps = { { "POM", cap = 10, needs = "pom", tank = 1 },
              { "PENANCE", cap = 12, needs = "penance", tank = 3 },
              { "BH", rank = 5, cap = 30, needs = "bindingHeal", tank = 1 },
              { "GH", rank = 3, cap = 30, tank = 1 },
              { "RENEW", rank = 7, fill = true } } },
  pwsTank = { name = "PW:Shield on tank, Renew filler", renewedHope = true,
    help = "A shield on the tank whenever Weakened Soul allows, Renew for everyone else.",
    steps = { { "POM", cap = 10, needs = "pom", tank = 1 },
              { "PENANCE", cap = 12, needs = "penance", tank = 3 },
              { "PWS", cap = 12, tank = 1 },
              { "BH", cap = 30, needs = "bindingHeal", tank = 1, auto = true },
              { "GH", cap = 30, auto = true },
              { "RENEW", fill = true, auto = true } } },
}

local function gcdsFor(s, gcd) return s.cast / gcd end

local rotationPass

-- In the game there is no Binding Heal spell: the sheet's Binding Heal step is a
-- Flash Heal with the Holy Binding talent (step "needs" bindingHeal = talent taken).
E.STEP_ALIAS = { BH = "FLASH" }

-- Litany of Light pays only when a heal follows a different heal, so its value
-- depends on the spell mix. Pass 1 finds the mix; if heals are interleaved, a
-- spell that is n of N eligible casts follows a different heal (1 - n/N) of the
-- time; pass 2 runs with those shares.
local rotationLitany

-- Playstyles pick their own ranks (game rules): for each step marked auto, try
-- every rank you know while the others stay put, keep the one that heals most;
-- two rounds. set.rankChoice (step index -> rank) skips the search, e.g. for stat
-- weights, which must compare the same playstyle with a stat raised.
function E.Rotation(rotKey, st, t, set)
  local rules = set.rules or E.RULES
  if set.rankChoice or not rules.autoRanks then return rotationLitany(rotKey, st, t, set) end
  local rot = E.ROTATIONS[rotKey]
  local cands = {}
  for i, step in ipairs(rot.steps) do
    if step.auto and (not step.needs or t[step.needs]) then
      local key = step[1]
      if not tableFor(set)[key] and E.STEP_ALIAS[key] then key = E.STEP_ALIAS[key] end
      local top = E.MaxRank(key, st.level, set.known, set)
      if top and top > 1 then cands[#cands + 1] = { i = i, top = top } end
    end
  end
  local s2 = {}
  for k, v in pairs(set) do s2[k] = v end
  s2.rankChoice = {}
  for _, c in ipairs(cands) do s2.rankChoice[c.i] = c.top end
  local best = rotationLitany(rotKey, st, t, s2)
  if not best then return nil end
  for _ = 1, 2 do
    for _, c in ipairs(cands) do
      local keep = s2.rankChoice[c.i]
      for r = 1, c.top do
        if r ~= keep then
          s2.rankChoice[c.i] = r
          local res = rotationLitany(rotKey, st, t, s2)
          if res and res.eff > best.eff + 1e-9 then best, keep = res, r end
        end
      end
      s2.rankChoice[c.i] = keep
    end
  end
  best.rankChoice = s2.rankChoice
  return best
end

function rotationLitany(rotKey, st, t, set)
  if (t.litanyRefund or 0) <= 0 or set.litanyShare then return rotationPass(rotKey, st, t, set) end
  local first = rotationPass(rotKey, st, t, set)
  if not first then return nil end
  local counts, total = {}, 0
  for _, s in ipairs(first.steps) do
    if E.LITANY_SPELLS[s.key] then counts[s.key] = (counts[s.key] or 0) + s.casts; total = total + s.casts end
  end
  local last = first.steps[#first.steps]
  if last and E.LITANY_SPELLS[last.key] then
    counts[last.key] = counts[last.key] + first.fiveSecondCasts; total = total + first.fiveSecondCasts
  end
  local set2 = {}
  for k, v in pairs(set) do set2[k] = v end
  set2.litanyShare = {}
  for key, n in pairs(counts) do set2.litanyShare[key] = total > 0 and (1 - n / total) or 0 end
  local out = rotationPass(rotKey, st, t, set2)
  out.litanyShare = set2.litanyShare
  return out
end

function rotationPass(rotKey, st, t, set)
  local rot = E.ROTATIONS[rotKey]
  local fl = set.fightLength
  local gcd = 1.5 / (1 + st.haste)
  local free = fl / gcd
  local mana = E.ManaBudget(st, t, set)
  local pwsOH = set.overheal.PWS
  local out = { name = rot.name, steps = {}, mana = mana, raw = 0, eff = 0 }
  local tankCasts, last = 0, nil

  -- A rotation needs its filler; without it (too low level) there is no model.
  local fillKey
  for _, step in ipairs(rot.steps) do if step.fill then fillKey = step[1] end end
  if not E.MaxRank(fillKey, st.level, set.known, set) then return nil end

  local fillIdx
  for i, step in ipairs(rot.steps) do
    local key = step[1]
    if not tableFor(set)[key] and E.STEP_ALIAS[key] then key = E.STEP_ALIAS[key] end
    local top = E.MaxRank(key, st.level, set.known, set)
    local rank = top and (step.rank and math.min(step.rank, top) or top)
    if top and set.rankChoice and set.rankChoice[i] then rank = math.min(set.rankChoice[i], top) end
    local enabled = rank and (not step.needs or t[step.needs])
    local sp = E.Spell(key, rank or 1, st, t, set)
    local perCastGcds = (key == "PENANCE") and (2 / 1.5) or gcdsFor(sp, gcd)
    local n = 0
    if enabled then
      if step.fill then n = min(mana / sp.cost, free / perCastGcds)
      else n = min(fl / step.cap, mana / sp.cost, free / perCastGcds) end
      n = max(0, n)
    end
    local useRH = rot.renewedHope and key ~= "POM" and key ~= "RENEW" and key ~= "PWS"
    local hpc = (useRH and sp.expectedRH or sp.expected) * sp.targets
    local da = (useRH and sp.aegisRH or sp.aegis) * sp.targets
    local raw = n * hpc
    local eff = raw * (1 - set.overheal[key]) + n * da * (1 - pwsOH)
    free = free - n * perCastGcds
    mana = mana - n * sp.cost
    out.raw = out.raw + raw + n * da
    out.eff = out.eff + eff
    tankCasts = tankCasts + n * (step.tank or 0)
    out.steps[#out.steps + 1] = { key = key, rank = sp.rank, casts = n, raw = raw, eff = eff, enabled = enabled and true or false,
                                  cap = step.cap, fill = step.fill, tank = step.tank,
                                  id = tableFor(set)[key].ranks[sp.rank].id }
    if step.fill then last, fillIdx = sp, #out.steps end
  end

  -- 5-second rule: unused GCDs -> pauses to regenerate -> extra filler casts
  out.freeGcds = max(0, free)
  out.pauseTime = out.freeGcds * gcd               -- time not spent casting: mana ran out first
  local per = pauseCycle(last.cost, max(last.cast, gcd), st, set.rules)
  local extra = set.imperfectPlay * out.pauseTime / per
  local fillRaw = extra * last.expected
  local fillEff = fillRaw * (1 - set.overheal[last.key]) + extra * last.aegis * (1 - pwsOH)
  out.raw = out.raw + fillRaw + extra * last.aegis
  out.eff = out.eff + fillEff
  out.fiveSecondCasts = extra
  local fs = out.steps[fillIdx]
  fs.pauseCasts, fs.eff = extra, fs.eff + fillEff

  -- Inner Focus on Prayer of Healing: free, +25% crit
  local pohRank = E.MaxRank("POH", st.level, set.known, set)
  local ifCasts = pohRank and max(1, ceil(fl / 180)) * t.innerFocus or 0
  if ifCasts > 0 then
    local poh = E.Spell("POH", pohRank, st, t, set)
    local c = st.crit + 0.25
    local h = poh.heal * ((1 - c) + c * st.critMulti) * 5
    local da = poh.heal * c * t.daMulti * 5
    local ifEff = ifCasts * (h * (1 - set.overheal.POH) + da * (1 - pwsOH))
    out.raw = out.raw + ifCasts * (h + da)
    out.eff = out.eff + ifEff
    out.innerFocus = { casts = ifCasts, rank = pohRank, eff = ifEff }
  end

  -- Inspiration: crits on the tank raise its armor by 25%; the damage it no
  -- longer takes counts as healing.
  out.inspiration = 0
  if set.includeInspiration and t.inspiration > 0 then
    local crit = rot.renewedHope and (st.crit + t.renewedHopeCrit) or st.crit
    local rate = set.inspirationIntoTank * tankCasts * crit / fl
    local uptime = 1 - exp(-rate * 15)
    local a0 = set.tankArmor
    local a1 = a0 * (1 + t.inspiration)
    local saved = set.tankRawDTPS * (1 - a0 / (a0 + 7285)) - set.tankRawDTPS * (1 - a1 / (a1 + 7285))
    out.inspiration = saved * uptime            -- already per second (damage per second saved)
    out.raw = out.raw + out.inspiration * fl
    out.eff = out.eff + out.inspiration * fl
  end

  out.hps = out.raw / fl
  out.ehps = out.eff / fl
  return out
end

---------------------------------------------------------------------------
-- Stat weights: effective HPS gained per +1 of a gear stat, found by running the
-- model again with that one stat raised (the sheet's "Weight" column).
---------------------------------------------------------------------------
E.WEIGHT_STATS = { "healing", "int", "crit", "haste", "mp5", "spirit" }

local function addDelta(st, d, scale)
  local o = {}
  for k, v in pairs(st) do o[k] = v end
  for k, v in pairs(d) do o[k] = (o[k] or 0) + v * scale end
  return o
end

-- step: size of the bump. A bigger step smooths over the kinks where a spell
-- stops being mana-limited, so weights don't jump around between nearby gear sets.
function E.Weights(rotKey, st, input, step)
  step = step or 10
  local t = E.Talents(input.talents, input.settings.rules)
  local set = input.settings
  local base = E.Rotation(rotKey, st, t, set)
  if not base then return nil end
  local w = { base = base }
  -- same ranks as the base, so a weight is the stat's own effect (not a rank switch)
  local fixed = set
  if base.rankChoice then
    fixed = {}
    for k, v in pairs(set) do fixed[k] = v end
    fixed.rankChoice = base.rankChoice
  end
  for _, stat in ipairs(E.WEIGHT_STATS) do
    local d = E.StatDelta(input, stat)
    local s = (stat == "crit" or stat == "haste") and 1 or step
    local up = E.Rotation(rotKey, addDelta(st, d, s), t, fixed)
    w[stat] = (up.ehps - base.ehps) / s
    w[stat .. "Raw"] = (up.hps - base.hps) / s
  end
  return w
end

-- Score a bag of item stats in effective HPS, using weights (quick estimate).
function E.Score(stats, w)
  local s = 0
  for _, k in ipairs(E.WEIGHT_STATS) do s = s + (stats[k] or 0) * (w[k] or 0) end
  return s
end

-- Exact item comparison: apply the stat DIFFERENCE (new item minus what it
-- replaces) through the whole model and rerun it. Unlike weights, this stays
-- right across the points where a spell stops being mana-limited.
-- diff = { healing=, int=, spirit=, mp5=, crit= (in %), haste= (in %) }
function E.Compare(rotKey, st, input, diff)
  local t = E.Talents(input.talents, input.settings.rules)
  local set = input.settings
  local base = E.Rotation(rotKey, st, t, set)
  if not base then return nil end
  local s2 = st
  for _, stat in ipairs(E.WEIGHT_STATS) do
    local n = diff[stat]
    if n and n ~= 0 then s2 = addDelta(s2, E.StatDelta(input, stat), n) end
  end
  local new = E.Rotation(rotKey, s2, t, set)
  return new.ehps - base.ehps, (new.ehps - base.ehps) / base.ehps, new.hps - base.hps
end

---------------------------------------------------------------------------
-- "Your spells": which plan suits you, how efficient each spell is, and the
-- best mix of spells for the fight.
---------------------------------------------------------------------------

-- Every healing plan with your stats, best first.
function E.ComparePlans(st, input)
  local t = E.Talents(input.talents, input.settings.rules)
  local out = {}
  local sheet = input.settings.rules and input.settings.rules.table == "sheet"
  for key, rot in pairs(E.ROTATIONS) do
    if (sheet or not rot.sheetOnly) and (not rot.requires or (t[rot.requires] or 0) > 0) then
      local r = E.Rotation(key, st, t, input.settings)
      if r then out[#out + 1] = { key = key, name = rot.name, ehps = r.ehps, hps = r.hps, result = r } end
    end
  end
  table.sort(out, function(a, b) return a.ehps > b.ehps end)
  return out
end

-- What one cast of a rank is worth after overheal (all targets), what it costs,
-- and how much of the fight it takes (an instant still takes a global cooldown).
local function castValue(key, rank, st, t, set)
  local sp = E.Spell(key, rank, st, t, set)
  local oh = set.overheal[key] or 0
  local heal = (sp.expected * (1 - oh) + sp.aegis * (1 - (set.overheal.PWS or 0))) * sp.targets
  local gcd = 1.5 / (1 + st.haste)
  return heal, sp.cost, max(sp.cast, gcd), sp
end

-- Per spell you know: its most mana-efficient rank and its top rank.
function E.SpellTable(st, t, set)
  local out = {}
  for key, def in pairs(tableFor(set)) do
    local top = E.MaxRank(key, st.level, set.known, set)
    if top then
      local bestR, bestHPM
      for r = 1, top do
        local heal, cost = castValue(key, r, st, t, set)
        local hpm = cost > 0 and heal / cost or math.huge
        if not bestHPM or hpm > bestHPM + 1e-9 then bestR, bestHPM = r, hpm end
      end
      local heal, cost, time = castValue(key, top, st, t, set)
      out[#out + 1] = { key = key, name = def.name, top = top, bestRank = bestR, bestHPM = bestHPM,
                        topHPM = cost > 0 and heal / cost or math.huge, topHPS = heal / time, topHeal = heal,
                        topCost = cost, topTime = time, id = def.ranks[top].id }
    end
  end
  table.sort(out, function(a, b) return a.bestHPM > b.bestHPM end)
  return out
end

-- A small linear-programming solver (simplex, Bland's rule): maximise c.x
-- subject to A.x <= b, x >= 0, with every b >= 0. Returns x and the maximum.
function E.LP(c, A, b)
  local m, n = #A, #c
  local W = n + m + 1
  local T = {}
  for i = 1, m do
    local row = {}
    for j = 1, n do row[j] = A[i][j] or 0 end
    for j = 1, m do row[n + j] = (i == j) and 1 or 0 end
    row[W] = b[i]
    T[i] = row
  end
  local z = {}
  for j = 1, W do z[j] = 0 end
  for j = 1, n do z[j] = -c[j] end
  T[m + 1] = z
  local basis = {}
  for i = 1, m do basis[i] = n + i end
  local EPS = 1e-9
  for _ = 1, 1000 do
    local e
    for j = 1, n + m do if T[m + 1][j] < -EPS then e = j; break end end
    if not e then break end
    local l, best
    for i = 1, m do
      local a = T[i][e]
      if a > EPS then
        local r = T[i][W] / a
        if not best or r < best - EPS or (math.abs(r - best) <= EPS and basis[i] < basis[l]) then best, l = r, i end
      end
    end
    if not l then return nil end                -- unbounded: cannot happen with a mana and a time limit
    local pv = T[l][e]
    for j = 1, W do T[l][j] = T[l][j] / pv end
    for i = 1, m + 1 do
      if i ~= l then
        local f = T[i][e]
        if f ~= 0 then for j = 1, W do T[i][j] = T[i][j] - f * T[l][j] end end
      end
    end
    basis[l] = e
  end
  local x = {}
  for j = 1, n do x[j] = 0 end
  for i = 1, m do if basis[i] <= n then x[basis[i]] = T[i][W] end end
  return x, T[m + 1][W]
end

-- How often a spell can be cast at most, by its cooldown (one tank for PW:Shield,
-- as in the plans: Weakened Soul keeps it to one shield per target per 15 s).
E.MIX_CAPS = { POM = 10, PENANCE = 12, PWS = 12 }

-- The mix of spells (any rank you know) that heals the most in the fight, with
-- the mana you have (pool, regen, potions, Mana Tide) and the fight's length.
-- Assumes there is always someone to heal. Time left once the mana is spent
-- becomes pauses to regenerate, which buy a few more of the most mana-efficient
-- cast (as in the plans). Inner Focus adds free Prayers of Healing.
function E.BestMix(st, t, set)
  local fl = set.fightLength
  local mana = E.ManaBudget(st, t, set)
  local vars, capRow = {}, {}
  for key in pairs(tableFor(set)) do
    local top = E.MaxRank(key, st.level, set.known, set)
    local allowed = top and (key ~= "POM" or t.pom) and (key ~= "PENANCE" or t.penance)
    if allowed then
      for r = 1, top do
        local heal, cost, time = castValue(key, r, st, t, set)
        if heal > 0 then vars[#vars + 1] = { key = key, rank = r, heal = heal, cost = cost, time = time } end
      end
    end
  end
  if #vars == 0 then return nil end
  local c, A, b = {}, { {}, {} }, { mana, fl }
  for j, v in ipairs(vars) do
    c[j] = v.heal
    A[1][j] = v.cost
    A[2][j] = v.time
  end
  for key, every in pairs(E.MIX_CAPS) do
    local row, any = {}, false
    for j, v in ipairs(vars) do
      if v.key == key then row[j] = 1; any = true else row[j] = 0 end
    end
    if any then A[#A + 1] = row; b[#b + 1] = fl / every; capRow[key] = true end
  end
  local x = E.LP(c, A, b)
  if not x then return nil end

  local out = { items = {}, mana = mana, fight = fl }
  local used, spent, total = 0, 0, 0
  local bestHPM
  for j, v in ipairs(vars) do
    local n = x[j]
    if n > 0.05 then
      out.items[#out.items + 1] = { key = v.key, rank = v.rank, name = tableFor(set)[v.key].name, casts = n,
                                    heal = n * v.heal, time = n * v.time, capped = capRow[v.key] or nil }
      used, spent, total = used + n * v.time, spent + n * v.cost, total + n * v.heal
    end
    if not E.MIX_CAPS[v.key] and v.cost > 0 then
      v.cycle = pauseCycle(v.cost, v.time, st, set.rules)
      if not bestHPM or v.heal / v.cycle > bestHPM.heal / bestHPM.cycle then bestHPM = v end
    end
  end
  -- leftover time -> pauses under the 5-second rule -> a few more casts of the
  -- spell that heals most per second of "wait, regenerate, cast"
  out.pause = max(0, fl - used)
  if out.pause > 1 and bestHPM and bestHPM.cycle < math.huge then
    local per = bestHPM.cycle
    local extra = set.imperfectPlay * out.pause / per
    local item
    for _, it in ipairs(out.items) do if it.key == bestHPM.key and it.rank == bestHPM.rank then item = it end end
    if not item then
      item = { key = bestHPM.key, rank = bestHPM.rank, name = tableFor(set)[bestHPM.key].name, casts = 0, heal = 0, time = 0 }
      out.items[#out.items + 1] = item
    end
    item.casts, item.heal = item.casts + extra, item.heal + extra * bestHPM.heal
    item.fromPauses = extra
    total = total + extra * bestHPM.heal
    out.pauseCasts = extra
  end
  -- Inner Focus: free Prayers of Healing (as in the plans)
  local pohRank = E.MaxRank("POH", st.level, set.known, set)
  if pohRank and t.innerFocus > 0 then
    local n = max(1, ceil(fl / 180))
    local poh = E.Spell("POH", pohRank, st, t, set)
    local cr = st.crit + 0.25
    local h = poh.heal * ((1 - cr) + cr * st.critMulti) * 5 * (1 - (set.overheal.POH or 0))
    out.innerFocus = { casts = n, rank = pohRank, heal = n * h }
    total = total + n * h
  end
  local casts = 0
  for _, it in ipairs(out.items) do casts = casts + it.casts end
  for _, it in ipairs(out.items) do
    it.share = casts > 0 and it.casts / casts or 0
    it.healShare = total > 0 and it.heal / total or 0
  end
  table.sort(out.items, function(a1, b1)
    if (a1.capped and 1 or 0) ~= (b1.capped and 1 or 0) then return a1.capped ~= nil end
    return a1.casts > b1.casts
  end)
  out.ehps = total / fl
  out.manaUsed = spent
  return out
end

return E
