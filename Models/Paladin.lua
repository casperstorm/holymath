--[[ Holy Math - Models/Paladin.lua
     The Holy Paladin model, in plain Lua with no game calls, so it runs in the game AND
     under a desktop Lua (tests/run_tests.lua). The same shape as Models/Priest.lua: the
     window, tooltips and Consumables tab call the same functions on either.

     How each spell and talent works is wowsims' paladin code (sim/paladin, the game's own
     spell data): Models/PaladinData.lua, made by tools/gen_paladin_data.py.
       * Flash of Light, Holy Light, Holy Shock: base heal + coefficient x healing power,
         then Healing Light (+4/8/12%). Downranking as for every class (E.Downrank).
       * Oath of Light (one ally, 1 hour): Holy Light +400, Flash of Light +115, Holy Shock
         +230 on that ally, at level 60 (they grow with your level), times the rank's coefficient
         (after downranking), as DoubleZug's sheet has it: a low rank gets little of it. wowsims
         gives every rank the full bonus (its own note: not yet checked in game).
       * Holy Power: the crit's bonus grows by 10..50%: 150% becomes 175% at 5/5 (as its
         tooltip and DoubleZug's sheet have it; a player saw 1287 against about 722).
       * Illumination: a crit of Flash of Light, Holy Light or Holy Shock gives back 50% of
         the spell's base cost (20..100% of the time). Light's Vigil: once per Vigil, when
         any of its heals crits (players confirm).
       * Infusion of Light: a crit of Flash of Light or Holy Shock takes 0.5/1 s off the next
         Holy Light within 15 s.
       * Holy Shock: instant, 10 s cooldown. Boundless Light: +15/30% crit on someone
         without your Oath. Benediction: instant spells cost 2..10% less.
       * Light's Vigil: a 1.5 s cast on an ally; your next Holy Shock on them has no
         cooldown and heals their whole party (the heal on each: its own row, no Healing
         Light). A Vigil step here is the pair: the Vigil, then that Holy Shock.
       * Divine Favor: every 2 min, the next heal crits (counted on your biggest heal).
       * Reverence: 15/30% of your spirit regen goes on while casting.

     Settings of its own (the Stats tab): oathShare (the share of your heals that land on
     your Oath's target, usually the tank) and vigilHits (the people one Light's Vigil heals).

     DoubleZug's "Forever Paladin 1.0" sheet is reproduced under E.SHEET_RULES by
     tests/run_tests.lua, as a check of the working; where the sheet and wowsims differ
     (Holy Power's crit, Oath of Light on low ranks, Illumination on Light's Vigil),
     the model follows the sheet: Holy Power and Illumination on Light's Vigil were checked
     in game by players; Oath of Light on low ranks is the sheet's until someone checks it.
]]--

local _, ns = ...
ns = ns or {}
local E = {}
ns.Models = ns.Models or {}
ns.Models.PALADIN = E

local Engine = ns.Engine or (dofile and dofile("Models/Engine.lua"))
E.TALENT_RANGE = { healingLight = { 0, 2 }, holyPower = { 0, 2 }, infusion = { 0, 2.5 } }   -- any other: 0 to 1
Engine.Install(E)
local copy, override, pauseCycle = E.copy, E.OverrideFor, E.PauseCycle
local max, min, ceil, floor = math.max, math.min, math.ceil, math.floor

E.CLASS = "PALADIN"

-- Game spell names (English client) -> keys
E.SPELL_KEYS = { ["Flash of Light"] = "FLASH", ["Holy Light"] = "HL", ["Holy Shock"] = "SHOCK", ["Light's Vigil"] = "VIGIL" }

-- Talents the model uses: key -> name in Forever's talent tree
E.TALENT_NAMES = {
  healingLight = "Healing Light", reverence = "Reverence", illumination = "Illumination",
  infusionOfLight = "Infusion of Light", holyPower = "Holy Power", divineIntellect = "Divine Intellect",
  benediction = "Benediction", boundlessLight = "Boundless Light", conviction = "Conviction",
  divineFavor = "Divine Favor", holyShock = "Holy Shock", lightsVigil = "Light's Vigil", oathOfLight = "Oath of Light",
}

-- Short names for /hm set oh <spell> <percent>
E.OVERHEAL_ALIASES = { flash = "FLASH", fol = "FLASH", hl = "HL", holy = "HL", shock = "SHOCK", vigil = "VIGIL" }

E.DEFAULT_ROTATION = "holyFill"

-- What a paladin can wear and wield (item class/subclass ids are the game's own).
-- Weapons as a BAN list: 2 bow, 3 gun, 9 warglaive, 10 staff, 13 fist weapon,
-- 15 dagger, 16 thrown, 18 crossbow, 19 wand.
E.EQUIP = {
  armorRank = 4,                 -- 1 cloth, 2 leather, 3 mail, 4 plate
  noShield = false,
  noWeapon = { [2] = true, [3] = true, [9] = true, [10] = true, [13] = true, [15] = true, [16] = true,
               [18] = true, [19] = true },
}

-- Talents that teach a spell only matter as "do you have the spell".
function E.AdjustTalents(ranks, known, byName)
  local function has(name) return byName[name] and (byName[name].rank or 0) > 0 end
  ranks.holyShock = (known.SHOCK or has("Holy Shock")) and 1 or 0
  ranks.lightsVigil = (known.VIGIL or has("Light's Vigil")) and 1 or 0
  ranks.oathOfLight = has("Oath of Light") and 1 or 0
  ranks.divineFavor = has("Divine Favor") and 1 or 0
  return ranks
end

-- No talent adds crit to the Holy school only (Game.lua compares two schools for that).
function E.CritTalent() return 0, 2, 6, "none" end

-- Share of spirit regen that continues while casting (Reverence).
function E.CastingRegenShare(ranks)
  local r = ranks.reverence or 0
  local c = E.DATA and E.DATA.talents and E.DATA.talents.reverence
  if c and r > 0 then return c[min(r, #c)] / 100 end
  return 0
end

---------------------------------------------------------------------------
-- Spell data
---------------------------------------------------------------------------
local function R(cost, base, lvl) return { cost = cost, base = base, lvl = lvl } end

-- THE SHEET'S spell table (DoubleZug's "Spells" tab), kept only so tests/run_tests.lua
-- can check the sheet is reproduced (rules.table = "sheet").
E.SHEET_SPELLS = {
  FLASH = { name = "Flash of Light", coeff = 1.5 / 3.5, cast = 1.5,
    ranks = { R(35, 51, 20), R(50, 72.5, 26), R(70, 109, 34), R(90, 160, 42), R(115, 234, 50), R(140, 316, 58) } },
  HL = { name = "Holy Light", coeff = 2.5 / 3.5, cast = 2.5,
    ranks = { R(35, 46, 1), R(60, 89, 6), R(110, 163.5, 14), R(190, 299, 22), R(275, 467.5, 30), R(365, 665, 38),
              R(465, 922, 46), R(580, 1243, 54), R(660, 1609, 60) } },
  SHOCK = { name = "Holy Shock", coeff = 1.5 / 3.5, cast = "gcd",
    ranks = { R(160, 114, 30), R(225, 156, 40), R(275, 230, 48), R(325, 320, 56) } },
  VIGIL = { name = "Light's Vigil", coeff = 0.15, cast = 1.5, targets = "vigil",
    ranks = { R(730, 335, 40), R(1000, 500, 50), R(1340, 720, 60) } },
}
-- The sheet's Oath of Light bonuses (at level 60)
local SHEET_OATH = { HL = 400, FLASH = 115, SHOCK = 230 }

local DATA = ns.PaladinData or (dofile and dofile("Models/PaladinData.lua"))
E.DATA = DATA
local SHAPE = { VIGIL = { targets = "vigil" } }
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
E.SPELLS = copy(E.GAME_SPELLS)

local function tableFor(set)
  return (set and set.rules and set.rules.table == "sheet") and E.SHEET_SPELLS or E.SPELLS
end
E.tableFor = tableFor

local function baseAt(rk, level)
  if rk.base then return rk.base end
  local top = (rk.ml and rk.ml > 0) and min(level, rk.ml) or level
  return rk.bp + rk.ppl * max(0, top - rk.bl)
end
E.BaseAt = baseAt

local TIMING = DATA.timing or {}
local HEALING_LIGHT = { FLASH = true, HL = true, SHOCK = true }     -- Healing Light's spells
local OATH_SPELLS = { FLASH = true, HL = true, SHOCK = true }
local ILLUMINATION = { FLASH = true, HL = true, SHOCK = true }      -- one heal a cast (Light's Vigil: rules.vigilIllumination)
local INSTANT = { SHOCK = true }                                    -- Benediction
local INFUSES = { FLASH = true, SHOCK = true }                      -- their crits give Infusion of Light

-- E.RULES: the game (wowsims' paladin code). E.SHEET_RULES: DoubleZug's sheet (tests only).
E.RULES = {
  table = "game", talents = "game",
  downrank = "maxLevel",       -- as for every class: 12 levels after the rank's max level (E.Downrank)
  fiveSecond = "seconds",
  autoRanks = true,
  critPerInt = "game",
  -- Holy Power on the crit's bonus only: 150% + 50% x 1.5 = 175%. wowsims multiplies the whole
  -- crit (225%), but a crit seen in game (1287 against about 722) fits 175%, as the tooltip reads.
  holyPower = "bonusOnly",
  -- Oath of Light: its bonus x the rank's coefficient (after downranking), not raised by Healing
  -- Light, as DoubleZug's sheet has it. wowsims gives every rank the full bonus; unchecked in game.
  oath = "scaled",
  -- Illumination on Light's Vigil: the talent's own text names it, and a Holy Paladin confirmed it
  -- in game (wowsims' code leaves it out). One refund of the Vigil's base cost when any of its
  -- heals crits, as DoubleZug's sheet counts it (once per Vigil, however many crit: also confirmed).
  vigilIllumination = true,
}
E.SHEET_RULES = { table = "sheet", talents = "sheet", downrank = "learned", downrankFreeLevels = 16, fiveSecond = "sheet",
                  holyPower = "bonusOnly",     -- the sheet: 150% + 0.25 = 175%
                  oath = "scaled",             -- the sheet: the bonus x the rank's coefficient, not Healing Light
                  shockOffOath = true,         -- the sheet's Holy Shock is cast on someone without the Oath
                  vigilIllumination = true,    -- the sheet: Illumination on a Vigil when any of its heals crit
                  judge = true,                -- the sheet: one Seal and Judgement (270 mana, a GCD)
                  freeOath = true }            -- the sheet: Oath of Light and Divine Favor cost no mana or time

-- Spell crit (percent) per point of intellect by level: the game data's level-60 value
-- (wowsims); below 60 the priest's curve (the game's table) scaled to it, an estimate.
local PRIEST_CURVE = {
  0.1909, 0.1826, 0.1750, 0.1680, 0.1556, 0.1500, 0.1448, 0.1400, 0.1355, 0.1273,
  0.1167, 0.1050, 0.0977, 0.0875, 0.0808, 0.0764, 0.0700, 0.0667, 0.0627, 0.0583,
  0.0560, 0.0525, 0.0506, 0.0477, 0.0457, 0.0438, 0.0420, 0.0404, 0.0389, 0.0372,
  0.0359, 0.0347, 0.0336, 0.0323, 0.0313, 0.0304, 0.0294, 0.0286, 0.0278, 0.0269,
  0.0263, 0.0255, 0.0249, 0.0241, 0.0235, 0.0230, 0.0223, 0.0219, 0.0213, 0.0208,
  0.0204, 0.0199, 0.0195, 0.0191, 0.0186, 0.0183, 0.0179, 0.0176, 0.0171, 0.0168,
}
function E.CritPerInt(level)
  level = min(max(floor((level or 60) + 0.5), 1), 60)
  local at60 = DATA.critPerInt60 or (1 / 60)
  if level == 60 then return at60, "game data" end
  return PRIEST_CURVE[level] * at60 / PRIEST_CURVE[60], "estimate (the priest's curve)"
end

-- Base mana: the game data's level-60 value; below 60 scaled the same way (an estimate).
local PRIEST_BASE_MANA = {
  110, 119, 129, 140, 137, 150, 164, 179, 195, 212, 215, 234, 254, 260, 282, 305, 329, 339, 365, 377,
  405, 434, 449, 480, 497, 530, 549, 584, 605, 627, 665, 689, 728, 752, 776, 800, 839, 863, 887, 911,
  950, 974, 998, 1022, 1046, 1070, 1094, 1118, 1142, 1166, 1190, 1214, 1238, 1262, 1271, 1295, 1319, 1343, 1352, 1376,
}
function E.BaseMana(level)
  level = min(max(floor((level or 60) + 0.5), 1), 60)
  return PRIEST_BASE_MANA[level] * (DATA.baseMana60 or 1512) / 1376
end

---------------------------------------------------------------------------
-- Talents, buffs and settings
---------------------------------------------------------------------------
E.DEFAULTS = {
  level = 60,
  -- DoubleZug's sheet, Profile tab
  gear = { healing = 577, int = 238, crit = 7, haste = 0, mp5 = 23, spirit = 203, spelldamage = 300 },
  buffs = { manaSpring = true, divineSpirit = true, wisdom = true, critAura = true, arcaneInt = true,
            kings = true, mark = true, shadowSpirit = true },
  talents = { divineIntellect = 5, healingLight = 3, reverence = 2, infusionOfLight = 2, illumination = 5,
              divineFavor = 1, holyShock = 1, holyPower = 5, lightsVigil = 1, benediction = 5, conviction = 3,
              boundlessLight = 2, oathOfLight = 1 },
  consumables = { distilledWisdom = true, brilliantManaOil = true, elixirOwl = true },
  race = { human = false, dwarf = false, gnome = false },
  settings = {
    fightLength = 300, pullEvery = 600, oathShare = 0.8, vigilHits = 5, innervate = false,
    majorManaPotions = true, cheapManaPotions = false, manaTidesInGroup = 1,
    overheal = { FLASH = 0.15, HL = 0.20, SHOCK = 0.15, VIGIL = 0.25 },
    imperfectPlay = 0.8,
  },
}

local function curve(name, rank)
  local c = DATA.talents[name]
  if not c or not rank or rank <= 0 then return 0 end
  return c[min(rank, #c)]
end

local function talentsFrom(tr, rules)
  local has = function(k) return (tr[k] or 0) > 0 end
  local t
  if (rules or E.RULES).talents == "game" then
    t = {
      healingLight = curve("healingLight", tr.healingLight) / 100,
      reverence = curve("reverence", tr.reverence) / 100,
      illumination = curve("illumination", tr.illumination) / 100,
      illuminationRefund = ((DATA.talents.illuminationRefund or { 50 })[1]) / 100,
      infusion = curve("infusionOfLight", tr.infusionOfLight),           -- seconds off the next Holy Light
      holyPower = curve("holyPower", tr.holyPower) / 100,
      divineIntellect = curve("divineIntellect", tr.divineIntellect) / 100,
      benediction = curve("benediction", tr.benediction) / 100,
      boundlessLight = curve("boundlessLight", tr.boundlessLight) / 100,
      conviction = curve("conviction", tr.conviction) / 100,
    }
  else
    local r = function(k) return tr[k] or 0 end
    t = { healingLight = 0.04 * r("healingLight"), reverence = 0.1 * r("reverence"), illumination = 0.2 * r("illumination"),
          illuminationRefund = 0.5, infusion = 0.5 * r("infusionOfLight"), holyPower = 0.1 * r("holyPower"),
          divineIntellect = 0.02 * r("divineIntellect"), benediction = 0.02 * r("benediction"),
          boundlessLight = 0.15 * r("boundlessLight"), conviction = 0.02 * r("conviction") }
  end
  -- spells the talents teach: true/false for a step's "needs", 1/0 for a playstyle's "requires"
  t.shock, t.vigil, t.oath, t.favor = has("holyShock"), has("lightsVigil"), has("oathOfLight"), has("divineFavor")
  t.vigilN = t.vigil and 1 or 0
  t.infusionN = t.infusion > 0 and 1 or 0
  return t
end

function E.Talents(tr, rules, o)
  local t = talentsFrom(tr or {}, rules)
  if o and next(o) then
    for id, v in pairs(o) do
      local f = type(id) == "string" and id:match("^talent%.(%a+)$")
      if f and type(t[f]) == "number" and E.OverrideOK(id, v) then
        t.orig = t.orig or {}
        t.orig[f] = t[f]
        t[f] = v
      end
    end
  end
  return t
end

local function on(b, v) return b and v or 0 end

function E.Multipliers(input)
  local b, r = input.buffs, input.race
  local t = E.Talents(input.talents, input.settings.rules, input.settings.overrides)
  local kings = b.kings and 1.1 or 1
  return {
    spirit = kings * (r.human and 1.05 or 1) * (b.shadowSpirit and 1.15 or 1),
    int = kings * (1 + t.divineIntellect),
    healingPerSpirit = 0, spellDamagePerSpirit = 0,
    manaPerInt = 15 * (r.gnome and 1.05 or 1),
    critPctPerInt = override(input.settings, "stat.critPerInt")
      or ((input.settings.rules or E.RULES).critPerInt == "game" and E.CritPerInt(input.level) or 1 / 60),
    -- mana per 5 s per spirit out of the 5-second rule: the game's 6.25 + spirit/8 a second
    regenPerSpirit = input.regenPerSpirit or 5 * (DATA.regen and DATA.regen.perSpirit or 0.125),
  }
end

-- Gear + buffs -> final stats (tests; in game the client gives them).
function E.Derive(input)
  local g, b, c, r = input.gear, input.buffs, input.consumables, input.race
  local t = E.Talents(input.talents, input.settings.rules, input.settings.overrides)
  local m = E.Multipliers(input)
  local spirit = (g.spirit + on(b.divineSpirit, 40) + on(b.mark, 16)) * m.spirit
  local int = (g.int + on(b.mark, 16) + on(b.arcaneInt, 31)) * m.int
  local healing = g.healing + on(c.brilliantManaOil, 0)
  local crit = on(b.critAura, 0.03) + (int * m.critPctPerInt + g.crit) / 100 + t.conviction + on(c.elixirOwl, 0.02)
  local mp5 = g.mp5 + on(b.manaSpring, 25) + on(b.wisdom, 40) + on(c.brilliantManaOil, 15)
  local ooc = 5 * (DATA.regen and DATA.regen.base or 6.25) + spirit * m.regenPerSpirit
  return {
    level = input.level, healing = healing, spelldamage = g.spelldamage, healingFromSpirit = 0,
    int = int, spirit = spirit, crit = crit, haste = g.haste / 100, mp5 = mp5,
    oocRegen = ooc, combatRegen = ooc * t.reverence,
    manaPool = (int * 15 + on(c.distilledWisdom, 2000)) * (r.gnome and 1.05 or 1),
    critMulti = 1.5,
  }
end

-- +1 of a gear stat as a change in final stats.
function E.StatDelta(input, stat)
  local m = E.Multipliers(input)
  local gnome = input.race.gnome and 1.05 or 1
  if stat == "healing" then return { healing = 1 } end
  if stat == "crit" then return { crit = 0.01 } end
  if stat == "haste" then return { haste = 0.01 } end
  if stat == "mp5" then return { mp5 = 1 } end
  if stat == "int" then return { int = m.int, crit = m.int * m.critPctPerInt / 100, manaPool = m.int * 15 * gnome } end
  if stat == "spirit" then
    local share = override(input.settings, "stat.castingShare")
      or E.Talents(input.talents, input.settings.rules, input.settings.overrides).reverence
    return { spirit = m.spirit, oocRegen = m.spirit * m.regenPerSpirit, combatRegen = m.spirit * m.regenPerSpirit * share }
  end
  if stat == "spelldamage" then return { spelldamage = 1 } end
end

-- A heal's crit, as a multiple of the heal.
function E.CritMultiplier(st, t, rules)
  local base = st.critMulti or 1.5
  if (rules or E.RULES).holyPower == "bonusOnly" then return 1 + (base - 1) * (1 + t.holyPower) end
  return base * (1 + t.holyPower)
end

-- Oath of Light's bonus to one cast of this spell on its target: points per level x your level
-- (400/115/230 at 60). "scaled" (DoubleZug's sheet, and the game rules): x the rank's coefficient,
-- after downranking, so a low rank gets little of it; "flat" (wowsims): the full bonus on every rank.
local function oathBonus(key, level, coeff, rules)
  local full = (rules.table == "sheet") and (SHEET_OATH[key] or 0)
    or ((DATA.oathPerLevel or {})[key] or 0) * (level or 60)
  if rules.oath == "scaled" then return full * coeff end
  return full
end

function E.OverhealFor(key, sp, set) return set.overheal[key] or 0 end

---------------------------------------------------------------------------
-- One spell rank at the given final stats. heal/expected are on ONE target, averaged over
-- your Oath's target (oathShare of your casts) and anyone else.
---------------------------------------------------------------------------
function E.Spell(key, rankIdx, st, t, set)
  local sp = tableFor(set)[key]
  local rk = sp.ranks[rankIdx]
  local rules = set.rules or E.RULES
  local gcd = 1.5 / (1 + st.haste)
  local ct = rk.cast or sp.cast
  local cast = (ct == "gcd") and gcd or ct / (1 + st.haste)
  local full = rk.coeff or sp.coeff
  local coeff = rk.power and full * rk.power or E.Downrank(full, rk, st.level, rules)
  local base = baseAt(rk, st.level)
  local hl = HEALING_LIGHT[key] and (1 + t.healingLight) or 1
  local share = 0
  if OATH_SPELLS[key] and t.oath and not (key == "SHOCK" and rules.shockOffOath) then share = min(1, max(0, set.oathShare or 0)) end
  local oath = OATH_SPELLS[key] and oathBonus(key, st.level, coeff, rules) or 0
  local healOff = (base + coeff * st.healing) * hl
  local healOn = (rules.oath == "scaled") and (healOff + oath) or ((base + oath + coeff * st.healing) * hl)
  local heal = healOff * (1 - share) + healOn * share
  local cm = E.CritMultiplier(st, t, rules)
  local cOff = min(1, st.crit + ((key == "SHOCK") and t.boundlessLight or 0))
  local cOn = min(1, st.crit)
  local expected = healOff * (1 - share) * (1 + cOff * (cm - 1)) + healOn * share * (1 + cOn * (cm - 1))
  local crit = cOff * (1 - share) + cOn * share
  local targets = (sp.targets == "vigil") and (set.vigilHits or 5) or 1
  -- cost: Benediction on instants; Illumination gives back part of the base cost on a crit
  local raw = rk.cost
  local cost = raw * (INSTANT[key] and (1 - t.benediction) or 1)
  local illumChance = 0
  if ILLUMINATION[key] then illumChance = crit
  elseif key == "VIGIL" and rules.vigilIllumination then illumChance = 1 - (1 - cOn) ^ targets end
  local refund = illumChance * t.illumination * t.illuminationRefund * raw
  cost = max(1, cost - refund)
  return {
    key = key, rank = rankIdx, name = sp.name, cast = cast, coeff = coeff, bodies = 1,
    heal = heal, expected = expected, crit = crit, critMulti = cm, aegis = 0,
    healOff = healOff, healOn = healOn, share = share,
    cost = cost, targets = targets,
    hpm = targets * expected / cost, hpct = targets * expected / max(cast, gcd),
    parts = { base = base, bp = rk.bp, ppl = rk.ppl, bl = rk.bl, ml = rk.ml, fullCoeff = full,
              power = (full and full > 0) and coeff / full or 1, healing = st.healing, healingLight = hl,
              oath = oath, oathShare = share, crit = crit, critOff = cOff, critOn = cOn, critMulti = cm,
              castBase = ct, haste = st.haste, rankCost = raw, benediction = INSTANT[key] and t.benediction or 0,
              refund = refund, illumChance = illumChance, cast = cast },
  }
end

function E.MaxRank(key, level, known, set)
  local def = tableFor(set)[key]
  if not def then return nil end
  if known then
    local k = known[key]
    if not k or k < 1 then return nil end
    return min(k, #def.ranks)
  end
  local best
  for i, rk in ipairs(def.ranks) do if rk.lvl <= level then best = i end end
  return best
end

---------------------------------------------------------------------------
-- The client's spell tooltips: read and compared with the game data, for /hm check.
-- Until a paladin's tooltips have been checked against the game (a /hm dump), the
-- game data stays: nothing is taken over from them.
---------------------------------------------------------------------------
local function n(x) return tonumber((x:gsub(",", ""))) end
function E.ParseDesc(key, desc)
  if type(desc) ~= "string" then return nil end
  local a, b
  if key == "SHOCK" then a, b = desc:match("or ([%d,]+) to ([%d,]+) healing")
  else a, b = desc:match("for ([%d,]+) to ([%d,]+)") end
  if a then return (n(a) + n(b)) / 2 end
  return nil
end
-- The tooltip's number: a cast on someone without your Oath, no crit.
function E.ModelTooltipHeal(key, rank, st, t, set)
  return E.Spell(key, rank, st, t, set).healOff
end
E.HOLD = 120
function E.ApplyClientData(spells, st, t, set)
  E.SPELLS = copy(E.GAME_SPELLS)
  local report = {}
  for _, c in ipairs(spells or {}) do
    local def = E.SPELLS[c.key]
    local rk = def and def.ranks[c.rank]
    if rk then
      local row = { key = c.key, rank = c.rank, rawCost = rk.cost, clientCost = c.cost, dataBase = baseAt(rk, st.level),
                    dataCast = rk.cast, baseFrom = nil, costFrom = nil, castFrom = nil }
      row.dataCost = rk.cost * ((INSTANT[c.key] and (1 - t.benediction)) or 1)
      local h = E.ParseDesc(c.key, c.desc)
      if h then
        row.client = h
        row.model = E.ModelTooltipHeal(c.key, c.rank, st, t, set)
        row.diff = row.client / row.model - 1
        row.after = row.model
      end
      row.base = row.dataBase
      report[#report + 1] = row
    end
  end
  return report
end

---------------------------------------------------------------------------
-- Mana for the fight: your pool, regen, potions, Mana Tide, less what Oath of Light and
-- Divine Favor cost (a share of base mana each).
---------------------------------------------------------------------------
-- Oath of Light lasts an hour in the game (its tooltip, in a level 42 paladin's /hm dump,
-- 2026-11-25); wowsims' data says 5 minutes. It outlasts the fight, so a fight pays its share.
local OATH_DUR = 3600
function E.OathCasts(fl, t, set)
  if not t.oath or (set.oathShare or 0) <= 0 or (set.rules or E.RULES).freeOath then return 0 end
  return fl / OATH_DUR
end
function E.FavorUses(fl, t, set)
  if not t.favor or set.divineFavor == false then return 0 end
  return max(1, ceil((fl - 15) / ((TIMING.FAVOR and TIMING.FAVOR.cd) or 120)))
end

function E.ManaParts(st, t, set)
  local fl = set.fightLength
  local ticks = fl / 5
  local pots = E.PotionPlan(st, set)
  local tideN = max(1, ceil((fl - 5) / 300))
  local innN = max(1, ceil((fl - 15) / 360))
  local innEach = (set.innervate and 1 or 0) * (st.oocRegen * 5 - st.combatRegen) * 4
  local bm = E.BaseMana(st.level)
  local oathN, favorN = E.OathCasts(fl, t, set), E.FavorUses(fl, t, set)
  local oathEach = bm * ((DATA.costPct or {}).OATH or 8) / 100 * (1 - t.benediction)
  local rules = set.rules or E.RULES
  local favorEach = rules.freeOath and 0 or bm * ((DATA.costPct or {}).FAVOR or 4) / 100
  return {
    { key = "pool", mana = st.manaPool },
    { key = "mp5", mana = ticks * st.mp5, ticks = ticks, per = st.mp5 },
    { key = "casting", mana = ticks * st.combatRegen, ticks = ticks, per = st.combatRegen },
    { key = "potions", mana = pots.mana, n = pots.sheet and pots.sheet.n or pots.count,
      per = pots.sheet and pots.sheet.per or nil, plan = pots },
    { key = "manaTide", mana = tideN * set.manaTidesInGroup * 290 * 4, n = tideN * set.manaTidesInGroup, per = 290 * 4 },
    { key = "innervate", mana = innN * innEach, n = set.innervate and innN or 0, per = innEach },
    { key = "oath", mana = -oathN * oathEach, n = oathN, per = -oathEach },
    { key = "favor", mana = -favorN * favorEach, n = favorN, per = -favorEach },
    { key = "judge", mana = rules.judge and -270 or 0, n = rules.judge and 1 or 0, per = -270 },
  }
end

function E.ManaBudget(st, t, set)
  local sum = 0
  for _, p in ipairs(E.ManaParts(st, t, set)) do sum = sum + p.mana end
  return sum
end

---------------------------------------------------------------------------
-- Playstyles. Each step casts a spell as often as its cap, the mana and the time allow,
-- top first; the last step fills. Leftover time becomes pauses under the 5-second rule.
--   cap       seconds between casts at most (Holy Shock: its 10 s cooldown at least)
--   infusion  Holy Light only on Infusion of Light procs (as many as Flash of Light and
--             Holy Shock crit)
--   VIGIL     the pair: Light's Vigil, then the Holy Shock that sets it off (no cooldown)
---------------------------------------------------------------------------
E.ROTATIONS = {
  flashFill = { name = "Flash of Light filler",
    help = "Holy Shock on cooldown, Flash of Light the rest of the time: cheap heals, most of them on your Oath's target.",
    steps = { { "SHOCK", cap = 10, needs = "shock", auto = true }, { "FLASH", fill = true, auto = true } } },
  holyFill = { name = "Holy Light filler",
    help = "Holy Shock on cooldown, Holy Light the rest of the time: big, slow heals.",
    steps = { { "SHOCK", cap = 10, needs = "shock", auto = true }, { "HL", fill = true, auto = true } } },
  vigilFlash = { name = "Light's Vigil + Flash of Light", requires = "vigilN",
    help = "Light's Vigil and the Holy Shock that sets it off three times a minute (group healing), Flash of " ..
      "Light the rest of the time.",
    steps = { { "VIGIL", cap = 20, needs = "vigil" }, { "FLASH", fill = true, auto = true } } },
  infusion = { name = "Holy Light on Infusion", requires = "infusionN",
    help = "Light's Vigil three times a minute, Holy Shock four times, Holy Light whenever Infusion of Light " ..
      "makes it quick, Flash of Light the rest of the time (the guides' priority).",
    steps = { { "VIGIL", cap = 20, needs = "vigil" }, { "SHOCK", cap = 15, needs = "shock", auto = true },
              { "HL", infusion = true, auto = true }, { "FLASH", fill = true, auto = true } } },
  -- DoubleZug's four Sim blocks (sheet tests only)
  sheetNatural = { name = "Natural prio", sheetOnly = true,
    steps = { { "SHOCK", cap = 12, rank = 4 }, { "VIGIL", cap = 20, rank = 3 }, { "HL", infusion = true, rank = 8 },
              { "FLASH", fill = true, rank = 6 } } },
  sheetNoHL = { name = "No Holy Light", sheetOnly = true,
    steps = { { "VIGIL", cap = 20, rank = 3 }, { "FLASH", fill = true, rank = 6 } } },
  sheetLowShock = { name = "Low Shock", sheetOnly = true,
    steps = { { "VIGIL", cap = 20, rank = 3 }, { "HL", fill = true, rank = 8 } } },
  sheetVigilSpam = { name = "Vigil spam", sheetOnly = true,
    steps = { { "VIGIL", cap = 6, rank = 3 }, { "FLASH", fill = true, rank = 6 } } },
}
E.BUILTIN_ROTATIONS = {}
for k, r in pairs(E.ROTATIONS) do E.BUILTIN_ROTATIONS[k] = r end

local rotationPass

-- One step's numbers per cast: heal after crits (all targets), what it costs, how long it
-- takes (in GCDs), what overheal takes, and the Infusion of Light procs it makes.
local function stepCast(key, rank, st, t, set, gcd, infusedShare)
  local sp = E.Spell(key, rank, st, t, set)
  local c = {}
  if key == "VIGIL" then
    local shockTop = E.MaxRank("SHOCK", st.level, set.known, set)
    local sh = shockTop and E.Spell("SHOCK", shockTop, st, t, set)
    c.raw = sp.expected * sp.targets + (sh and sh.expected or 0)
    c.eff = sp.expected * sp.targets * (1 - E.OverhealFor("VIGIL", sp, set)) + (sh and sh.expected * (1 - E.OverhealFor("SHOCK", sh, set)) or 0)
    c.cost = sp.cost + (sh and sh.cost or 0)
    c.time = max(sp.cast, gcd) + gcd
    c.procs = sh and sh.crit or 0
    c.shock = sh
  else
    local cast = sp.cast
    if key == "HL" and (t.infusion or 0) > 0 and (infusedShare or 0) > 0 then
      cast = max(gcd, cast - t.infusion / (1 + st.haste) * infusedShare)
    end
    c.raw = sp.expected * sp.targets
    c.eff = c.raw * (1 - E.OverhealFor(key, sp, set))
    c.cost = sp.cost
    c.time = max(cast, gcd)
    c.procs = INFUSES[key] and sp.crit or 0
  end
  c.sp = sp
  return c
end

local INF_PASSES = 14
function E.Rotation(rotKey, st, t, set)
  local rot = E.ROTATIONS[rotKey]
  if not rot then return nil end
  local rules = set.rules or E.RULES
  local function run(s)
    -- Infusion of Light: Holy Light's count (or speed) depends on the crits after it, so the
    -- pass runs again with the procs the last one counted (a fixed number: weights stay smooth)
    -- pass, so the procs a pass is given are those it makes: more procs given means more
    -- Holy Lights, fewer Flash of Lights and fewer procs made, so the one where the two meet
    -- is found by halving (a fixed number of steps: weights stay smooth)
    local out = rotationPass(rotKey, st, t, s, 0)
    if out and out.usesProcs and (t.infusion or 0) > 0 and out.procs > 0 then
      local lo, hi = 0, out.procs
      for _ = 1, INF_PASSES do
        local mid = (lo + hi) / 2
        local r = rotationPass(rotKey, st, t, s, mid)
        if r and r.procs > mid then lo = mid else hi = mid end
      end
      out = rotationPass(rotKey, st, t, s, (lo + hi) / 2) or out
    end
    return out
  end
  if set.rankChoice or not rules.autoRanks then return run(set) end
  local cands = {}
  for i, step in ipairs(rot.steps) do
    if step.auto and (not step.needs or t[step.needs]) then
      local top = E.MaxRank(step[1], st.level, set.known, set)
      if top and top > 1 then cands[#cands + 1] = { i = i, top = top } end
    end
  end
  local s2 = {}
  for k, v in pairs(set) do s2[k] = v end
  s2.rankChoice = {}
  for _, c in ipairs(cands) do s2.rankChoice[c.i] = c.top end
  local best = run(s2)
  if not best then return nil end
  for _ = 1, 2 do
    for _, c in ipairs(cands) do
      local keep = s2.rankChoice[c.i]
      for r = 1, c.top do
        if r ~= keep then
          s2.rankChoice[c.i] = r
          local res = run(s2)
          if res and res.eff > best.eff + 1e-9 then best, keep = res, r end
        end
      end
      s2.rankChoice[c.i] = keep
    end
  end
  best.rankChoice = s2.rankChoice
  return best
end

function rotationPass(rotKey, st, t, set, procsIn)
  local rot = E.ROTATIONS[rotKey]
  local fl = set.fightLength
  local rules = set.rules or E.RULES
  local pots = E.PotionPlan(st, set)
  if pots.healing > 0 then
    local s2 = {}
    for k, v in pairs(st) do s2[k] = v end
    s2.healing, s2.potionHealing = st.healing + pots.healing, pots.healing
    st = s2
  end
  local gcd = 1.5 / (1 + st.haste)
  local freeTime = max(0, fl - pots.sleep)
  local mana = E.ManaBudget(st, t, set)
  local out = { name = rot.name, steps = {}, mana = mana, raw = 0, eff = 0, potions = pots, procs = 0 }

  -- the fill needs its spell; without it (too low a level) there is no model
  local fillKey
  for _, step in ipairs(rot.steps) do if step.fill then fillKey = step[1] end end
  if not (fillKey and E.MaxRank(fillKey, st.level, set.known, set)) then return nil end

  -- Oath of Light kept up, and the sheet's Seal and Judgement: a GCD each (their mana is in the budget)
  out.oathCasts = E.OathCasts(fl, t, set)
  freeTime = freeTime - (out.oathCasts + (rules.judge and 1 or 0)) * gcd

  local procsLeft = procsIn or 0
  local fillIdx, last
  for i, step in ipairs(rot.steps) do
    local key = step[1]
    local top = E.MaxRank(key, st.level, set.known, set)
    local rank = top and (step.rank and min(step.rank, top) or top)
    if top and set.rankChoice and set.rankChoice[i] then rank = min(set.rankChoice[i], top) end
    local enabled = rank and (not step.needs or t[step.needs]) and (key ~= "VIGIL" or E.MaxRank("SHOCK", st.level, set.known, set))
    local infused = 0
    if key == "HL" and step.infusion then infused = 1
    elseif key == "HL" then out.usesProcs = true end
    local c = stepCast(key, rank or 1, st, t, set, gcd, infused)
    local n, limit = 0, nil
    if enabled then
      local cap = step.cap
      if key == "SHOCK" then cap = max(cap or 0, (TIMING.SHOCK and TIMING.SHOCK.cd) or 10) end
      if key == "VIGIL" then cap = max(cap or 0, (TIMING.VIGIL and TIMING.VIGIL.cd) or 6) end
      local byCd = (cap and not step.fill) and fl / cap or math.huge
      local byProcs = (key == "HL" and step.infusion) and procsLeft or math.huge
      local byMana, byTime = mana / c.cost, freeTime / c.time
      -- a Holy Light filler speeds up by the procs there are for it
      if key == "HL" and not step.infusion and (t.infusion or 0) > 0 and procsLeft > 0 then
        local guess = min(byMana, byTime)
        for _ = 1, 3 do
          local share = guess > 0 and min(1, procsLeft / guess) or 0
          c = stepCast(key, rank, st, t, set, gcd, share)
          guess = min(mana / c.cost, freeTime / c.time)
        end
        byTime = freeTime / c.time
      end
      n = min(byCd, byProcs, byMana, byTime)
      limit = (n == byCd and "cooldown") or (n == byProcs and "procs") or (n == byMana and "mana") or "time"
      n = max(0, n)
      if key == "HL" and step.infusion then out.usesProcs = true end
    end
    if key == "HL" then procsLeft = max(0, procsLeft - n) end
    out.procs = out.procs + n * c.procs
    freeTime = freeTime - n * c.time
    mana = mana - n * c.cost
    out.raw = out.raw + n * c.raw
    out.eff = out.eff + n * c.eff
    local sp = c.sp
    out.steps[#out.steps + 1] = { key = key, rank = sp.rank, casts = n, raw = n * c.raw, eff = n * c.eff,
                                  enabled = enabled and true or false, cap = step.cap, fill = step.fill,
                                  infusion = step.infusion, id = tableFor(set)[key].ranks[sp.rank].id, limit = limit,
                                  perCast = c.raw, perCastEff = c.eff, overheal = E.OverhealFor(key, sp, set),
                                  time = c.time, cost = c.cost, manaBefore = mana + n * c.cost,
                                  shock = c.shock and { rank = c.shock.rank, perCast = c.shock.expected } or nil }
    if step.fill then last, fillIdx = c, #out.steps end
  end

  -- 5-second rule: time left once the mana is spent -> pauses to regenerate -> a few more fills
  out.pauseTime = max(0, freeTime)
  out.freeGcds = out.pauseTime / gcd
  local per = pauseCycle(last.cost, last.time, st, set.rules)
  local extra = set.imperfectPlay * out.pauseTime / per
  out.pauseCycle, out.gcd, out.manaLeft = per, gcd, mana
  out.raw = out.raw + extra * last.raw
  out.eff = out.eff + extra * last.eff
  out.procs = out.procs + extra * last.procs
  out.fiveSecondCasts, out.pauseEff, out.pauseHeal = extra, extra * last.eff, last.raw
  local fs = out.steps[fillIdx]
  fs.pauseCasts, fs.eff = extra, fs.eff + extra * last.eff

  -- Divine Favor: a sure crit, on the biggest of the heals you cast
  local uses = E.FavorUses(fl, t, set)
  if uses > 0 then
    local best
    for _, s in ipairs(out.steps) do
      if s.casts > 0 and ILLUMINATION[s.key] then
        local sp = E.Spell(s.key, s.rank, st, t, set)
        if not best or sp.heal > best.heal then best = sp end
      end
    end
    if best then
      local gain = best.heal * (1 - best.crit) * (best.critMulti - 1)
      out.favor = { uses = uses, key = best.key, rank = best.rank, raw = uses * gain,
                    eff = uses * gain * (1 - E.OverhealFor(best.key, best, set)) }
      out.raw = out.raw + out.favor.raw
      out.eff = out.eff + out.favor.eff
    end
  end

  out.hps = out.raw / fl
  out.ehps = out.eff / fl
  return out
end

E.WEIGHT_STATS = { "healing", "int", "crit", "haste", "mp5", "spirit" }

---------------------------------------------------------------------------
-- Playstyles as blocks (how the window describes them): { spell, rank, how, n }.
--   how: "cd" on cooldown | "pm" n times a minute | "proc" on Infusion of Light procs |
--        "fill" the rest of the time
---------------------------------------------------------------------------
function E.StepSpellName(key)
  if key == "VIGIL" then return "Light's Vigil (then Holy Shock)" end
  local sp = E.SPELLS[key]
  return sp and sp.name or tostring(key)
end

function E.Seconds(v) return (string.format("%.1f", v):gsub("%.0$", "")) end
function E.HowText(d)
  if d.how == "cd" then return "on cooldown"
  elseif d.how == "fill" then return "fill the rest"
  elseif d.how == "proc" then return "on Infusion of Light procs"
  elseif d.how == "pm" then
    return "at most " .. (d.n == 1 and "once a minute" or d.n == 2 and "twice a minute" or (tostring(d.n) .. " times a minute"))
  elseif d.how == "sec" then return "at most every " .. E.Seconds(d.n) .. " s" end
  return "?"
end

local STEP_NEEDS = { SHOCK = "shock", VIGIL = "vigil" }
local function cdOf(key) return TIMING[key] and TIMING[key].cd or 0 end

function E.RotationFromPlaystyle(def)
  local rot = { name = def.name, custom = true, steps = {} }
  for _, d in ipairs(def.steps) do
    local s = { d.spell, needs = STEP_NEEDS[d.spell] }
    if d.rank == nil then s.auto = d.spell ~= "VIGIL" elseif type(d.rank) == "number" then s.rank = d.rank end
    if d.how == "fill" then s.fill = true
    elseif d.how == "proc" then s.infusion = true
    elseif d.how == "cd" then s.cap = cdOf(d.spell)
    elseif d.how == "pm" then s.cap = 60 / d.n
    elseif d.how == "sec" then s.cap = d.n end
    rot.steps[#rot.steps + 1] = s
  end
  return rot
end

function E.PlaystyleFromRotation(rot)
  local def = { name = rot.name, steps = {} }
  for _, s in ipairs(rot.steps) do
    local d = { spell = s[1] }
    if s.auto then d.rank = nil elseif s.rank then d.rank = s.rank else d.rank = "top" end
    if s.fill then d.how = "fill"
    elseif s.infusion then d.how = "proc"
    elseif s.cap and math.abs(s.cap - cdOf(s[1])) < 1e-9 then d.how = "cd"
    elseif s.cap then
      local per = 60 / s.cap
      if math.abs(per - floor(per + 0.5)) < 1e-9 then d.how, d.n = "pm", floor(per + 0.5) else d.how, d.n = "sec", s.cap end
    end
    def.steps[#def.steps + 1] = d
  end
  return def
end

---------------------------------------------------------------------------
-- The playstyle Holy Math counts you with (Core.lua): every mix of Light's Vigil (none,
-- 2, 3, 4 or 6 a minute), Holy Shock (on cooldown or only for Vigils), Holy Light on
-- Infusion procs, and each filler; fixed ranks first, then the best few pick their own.
---------------------------------------------------------------------------
E.BEST = "best"
E.BUILD_SPELLS = { "VIGIL", "SHOCK", "HL", "FLASH" }
local BUILD_KEY = "__build"

function E.BuildKnows(key, st, t, set)
  local needs = STEP_NEEDS[key]
  if needs and not t[needs] then return false end
  if key == "VIGIL" and not E.BuildKnows("SHOCK", st, t, set) then return false end
  return E.MaxRank(key, st.level, set.known, set) ~= nil
end

function E.BuildCandidates(use, st, t, set)
  local function ok(key) return use[key] and E.BuildKnows(key, st, t, set) end
  local out = {}
  for _, fill in ipairs({ "FLASH", "HL" }) do
    if ok(fill) then
      for _, vpm in ipairs(ok("VIGIL") and { 0, 2, 3, 4, 6 } or { 0 }) do
        for _, shock in ipairs(ok("SHOCK") and { false, true } or { false }) do
          for _, inf in ipairs((fill == "FLASH" and ok("HL") and (t.infusion or 0) > 0) and { false, true } or { false }) do
            local steps = {}
            if vpm > 0 then steps[#steps + 1] = { spell = "VIGIL", how = "pm", n = vpm } end
            if shock then steps[#steps + 1] = { spell = "SHOCK", how = "cd" } end
            if inf then steps[#steps + 1] = { spell = "HL", how = "proc" } end
            steps[#steps + 1] = { spell = fill, how = "fill" }
            out[#out + 1] = { steps = steps }
          end
        end
      end
    end
  end
  return out
end

local BUILD_WORD = { VIGIL = "Vigil", SHOCK = "Shock", HL = "Infusion" }
E.MAX_PLAYSTYLE_NAME = 32
function E.BuildName(def)
  local steps = def.steps
  local name = E.SPELLS[steps[#steps].spell].name .. " filler"
  for i = 1, #steps - 1 do
    local w = BUILD_WORD[steps[i].spell]
    if w and #name + 3 + #w <= E.MAX_PLAYSTYLE_NAME then name = name .. " + " .. w end
  end
  return name
end

local function buildRun(def, st, t, set, ranks)
  local rot = E.RotationFromPlaystyle(def)
  rot.sheetOnly = true
  local s2 = set
  if ranks then
    s2 = {}
    for k, v in pairs(set) do s2[k] = v end
    s2.rankChoice = ranks
  end
  E.ROTATIONS[BUILD_KEY] = rot
  local okRun, res = pcall(E.Rotation, BUILD_KEY, st, t, s2)
  E.ROTATIONS[BUILD_KEY] = nil
  return okRun and res or nil
end

function E.BuildPlaystyle(use, st, input, yield)
  yield = yield or function() end
  local set = input.settings
  local t = E.Talents(input.talents, set.rules, set.overrides)
  local cands = E.BuildCandidates(use, st, t, set)
  if #cands == 0 then return nil, "no heal you can cast without a cooldown to fill the fight" end
  local runs, tried = 0, {}
  for _, def in ipairs(cands) do
    local ranks = {}
    for i, d in ipairs(def.steps) do ranks[i] = E.MaxRank(d.spell, st.level, set.known, set) or 1 end
    local res = buildRun(def, st, t, set, ranks)
    runs = runs + 1
    if res then tried[#tried + 1] = { def = def, res = res } end
    if runs % 10 == 0 then yield() end
  end
  if #tried == 0 then return nil, "no playstyle could be worked out" end
  table.sort(tried, function(a, b) return a.res.ehps > b.res.ehps end)
  local best = tried[1]
  for i = 1, min(4, #tried) do
    local res = buildRun(tried[i].def, st, t, set, nil)
    runs = runs + 1
    yield()
    if res and res.ehps > best.res.ehps then best = { def = tried[i].def, res = res } end
  end
  local def = copy(best.def)
  def.name = E.BuildName(def)
  local spells, unused, inIt = {}, {}, {}
  for _, d in ipairs(def.steps) do inIt[d.spell] = true end
  for _, k in ipairs(E.BUILD_SPELLS) do
    if use[k] and E.BuildKnows(k, st, t, set) then
      spells[#spells + 1] = k
      if not inIt[k] then unused[#unused + 1] = k end
    end
  end
  def.spells = spells
  return { def = def, result = best.res, runs = runs, unused = unused }
end

---------------------------------------------------------------------------
-- Your spells: what one cast is worth after overheal, each rank, and the best mix.
---------------------------------------------------------------------------
local function castValue(key, rank, st, t, set)
  local sp = E.Spell(key, rank, st, t, set)
  local heal = sp.expected * (1 - E.OverhealFor(key, sp, set)) * sp.targets
  local gcd = 1.5 / (1 + st.haste)
  return heal, sp.cost, max(sp.cast, gcd), sp
end
E.CastValue = castValue

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

-- Every rank of one spell you know, highest first (the spell tooltips).
function E.SpellRanks(key, st, t, set)
  local def = tableFor(set)[key]
  local top = def and E.MaxRank(key, st.level, set.known, set)
  if not top then return {} end
  local out, bestR, bestH, bestRawR, bestRawH = {}, nil, nil, nil, nil
  for r = 1, top do
    local heal, cost, time, sp = castValue(key, r, st, t, set)
    local full = def.ranks[r].coeff or def.coeff
    local hpm = cost > 0 and heal / cost or math.huge
    -- raw, as other addons show it: before overheal and Illumination, at the spell's cost
    local raw = sp.expected * sp.targets
    local fullCost = cost + (sp.parts.refund or 0)
    out[#out + 1] = { rank = r, heal = heal, cost = cost, hpm = hpm, hps = heal / time, id = def.ranks[r].id,
                      power = (full and full > 0) and sp.coeff / full or 1, lvl = def.ranks[r].lvl,
                      overheal = E.OverhealFor(key, sp, set),
                      raw = { heal = sp.heal, expected = sp.expected, targets = sp.targets, onYou = 0,
                              refund = sp.parts.refund or 0, hpm = fullCost > 0 and raw / fullCost or math.huge,
                              hps = raw / time } }
    if not bestH or hpm > bestH + 1e-9 then bestR, bestH = r, hpm end
    local rh = out[#out].raw.hpm
    if not bestRawH or rh > bestRawH + 1e-9 then bestRawR, bestRawH = r, rh end
  end
  for _, row in ipairs(out) do row.best, row.bestRaw = (row.rank == bestR), (row.rank == bestRawR) end
  table.sort(out, function(a1, b1) return a1.rank > b1.rank end)
  return out
end

-- The mix of casts that heals the most with your mana and time (an LP): every rank of
-- Flash of Light and Holy Light, Holy Shock (its cooldown) and the Vigil pair (its own).
function E.BestMix(st, t, set)
  local fl = set.fightLength
  local mana = E.ManaBudget(st, t, set)
  local gcd = 1.5 / (1 + st.haste)
  local vars = {}
  for _, key in ipairs({ "FLASH", "HL", "SHOCK", "VIGIL" }) do
    local top = E.BuildKnows(key, st, t, set) and E.MaxRank(key, st.level, set.known, set)
    if top then
      for r = (key == "VIGIL" and top or 1), top do
        local c = stepCast(key, r, st, t, set, gcd, 0)
        if c.eff > 0 then vars[#vars + 1] = { key = key, rank = r, heal = c.eff, cost = c.cost, time = c.time } end
      end
    end
  end
  if #vars == 0 then return nil end
  local c, A, b = {}, { {}, {} }, { mana, fl }
  for j, v in ipairs(vars) do c[j], A[1][j], A[2][j] = v.heal, v.cost, v.time end
  for _, key in ipairs({ "SHOCK", "VIGIL" }) do
    local row, any = {}, false
    for j, v in ipairs(vars) do
      -- a Vigil's Holy Shock has no cooldown; Holy Shock alone has its own
      if v.key == key then row[j] = 1; any = true else row[j] = 0 end
    end
    if any then A[#A + 1] = row; b[#b + 1] = fl / max(1, cdOf(key)) end
  end
  local x = E.LP(c, A, b)
  if not x then return nil end
  local out = { items = {}, mana = mana, fight = fl }
  local used, spent, total, bestHPM = 0, 0, 0, nil
  for j, v in ipairs(vars) do
    local nn = x[j]
    if nn > 0.05 then
      out.items[#out.items + 1] = { key = v.key, rank = v.rank, name = E.StepSpellName(v.key), casts = nn,
                                    heal = nn * v.heal, time = nn * v.time, capped = (v.key == "SHOCK" or v.key == "VIGIL") or nil }
      used, spent, total = used + nn * v.time, spent + nn * v.cost, total + nn * v.heal
    end
    if v.key ~= "SHOCK" and v.key ~= "VIGIL" and v.cost > 0 then
      v.cycle = pauseCycle(v.cost, v.time, st, set.rules)
      if not bestHPM or v.heal / v.cycle > bestHPM.heal / bestHPM.cycle then bestHPM = v end
    end
  end
  out.pause = max(0, fl - used)
  if out.pause > 1 and bestHPM and bestHPM.cycle < math.huge then
    local extra = set.imperfectPlay * out.pause / bestHPM.cycle
    local item
    for _, it in ipairs(out.items) do if it.key == bestHPM.key and it.rank == bestHPM.rank then item = it end end
    if not item then
      item = { key = bestHPM.key, rank = bestHPM.rank, name = E.StepSpellName(bestHPM.key), casts = 0, heal = 0, time = 0 }
      out.items[#out.items + 1] = item
    end
    item.casts, item.heal, item.fromPauses = item.casts + extra, item.heal + extra * bestHPM.heal, extra
    total = total + extra * bestHPM.heal
    out.pauseCasts = extra
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

-- Saved settings from older versions, brought up to date.
function E.MigrateSettings(s)
  if type(s) ~= "table" then return false end
  return E.MigratePotions(s)
end

return E
