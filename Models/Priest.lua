--[[ Holy Math - Models/Priest.lua
     The healing-priest model, in plain Lua with no game calls, so it runs in the
     game AND under a desktop Lua (tests/run_tests.lua checks it against the sheet).

     Ported from doublezug's healer-priest spreadsheet (tabs "Profile", "Spells", "Sim"):
     https://docs.google.com/spreadsheets/d/19SaCaDQJzhMFL-nIW4ryzFwI53FmsnDvaxRfLbvM-CE/edit?gid=1807392634#gid=1807392634
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
                       flash = "FLASH", nova = "NOVA", pom = "POM", lesser = "LESSER", heal = "HEAL",
                       self = "SELF" }

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
  POH = { name = "Prayer of Healing", coeff = 0.2887, cast = 3, targets = "group",
    ranks = { R(410,185,30), R(560,273.5,40), R(770,412.5,50), R(1030,596,60) } },
  PENANCE = { name = "Penance", coeff = 2 / 3.5, cast = 2,
    ranks = { R(150,402,30), R(220,627,40), R(270,837,50), R(385,1275,60) } },
  POM = { name = "Prayer of Mending", coeff = 1.5 / 3.5, cast = "gcd", targets = "pomhits",
    ranks = { R(210,172,40), R(305,298,50), R(390,413,60) } },
  NOVA = { name = "Holy Nova", coeff = 0.24, cast = "gcd", targets = "group",
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
-- targets: "group" = your setting of people a group heal reaches (5, a full party, unless
-- you set fewer); "pomhits" = Prayer of Mending's bounces (your setting)
local SHAPE = { PWS = { shield = true }, POH = { targets = "group" }, NOVA = { targets = "group" }, POM = { targets = "pomhits" } }
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

-- A rank's bonus coefficient: its full coefficient times the share of your
-- healing power it gets (the downranking rule). rk.power overrides that share;
-- ApplyClientData sets it only for a moment, to see a rank at full power.
local function rankCoeff(rk, defCoeff, level, rules)
  local full = rk.coeff or defCoeff
  if rk.power then return full * rk.power end
  return E.Downrank(full, rk, level, rules)
end

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
  selfOverheal = true,         -- Holy Binding's heal on you has its own overheal (overheal.SELF), see E.OverhealFor
  critPerInt = "game",         -- intellect -> crit by level (E.CritPerInt); the sheet uses 1 / 60 at every level
  aegisFromCrit = true,        -- Divine Aegis: a share of the crit's own amount, at most its cap per heal (the sheet: of the non-crit heal)
  weakenedSoul = true,         -- a shield on the tank waits for Weakened Soul, which Renewed Hope's heals cut short;
                               -- Renewed Hope's crit only on its spells, on the tank, while Weakened Soul is up
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
    return max(0, st.healing - (st.healingFromSpirit or 0))
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

-- Spell crit (percent) one point of intellect gives, by level. Level 60 is the
-- game data (wowsims, PlayerExpectedStat). The game data has no other levels, so
-- the rest are measured from the client: with no crit on gear, a priest's spell
-- crit is 0.8% + intellect x this, and the dumps fit it to four decimals
-- (level 49: 204 int -> 5.1452%; level 50: 208 int -> 5.1264%; 20 Nov 2026).
-- Between known levels it is interpolated; below the lowest it is extended
-- along the two lowest. Returns the value and how it was found.
E.CRIT_PER_INT_MEASURED = { [49] = 0.0213, [50] = 0.0208 }
function E.CritPerInt(level)
  local pts = {}
  for l, v in pairs(E.CRIT_PER_INT_MEASURED) do pts[#pts + 1] = { l, v, "measured in game" } end
  if DATA.critPerInt60 then pts[#pts + 1] = { 60, DATA.critPerInt60, "game data" } end
  table.sort(pts, function(a, b) return a[1] < b[1] end)
  level = level or 60
  for _, p in ipairs(pts) do if p[1] == level then return p[2], p[3] end end
  if #pts == 0 then return 1 / 60, "sheet" end
  if #pts == 1 then return pts[1][2], "estimated" end
  local lo, hi = pts[1], pts[2]
  if level > pts[#pts][1] then lo, hi = pts[#pts - 1], pts[#pts] end
  for i = 1, #pts - 1 do
    if level > pts[i][1] and level < pts[i + 1][1] then lo, hi = pts[i], pts[i + 1] end
  end
  local v = lo[2] + (hi[2] - lo[2]) * (level - lo[1]) / (hi[1] - lo[1])
  return max(v, 0.001), "estimated"
end

---------------------------------------------------------------------------
-- Your own values (typed over on the Math tab). Any input the model uses can be
-- replaced; they are saved per class (db.overrides = { [id] = number }) and reach
-- every calculation through input.settings.overrides. The check against the
-- game's tooltips (E.ApplyClientData) always runs without them, on the game's
-- own numbers.
--   stat.<field>                 healing, healingFromSpirit, crit, critMulti, haste,
--                                manaPool, mp5, oocRegen, castingShare, critPerInt
--   talent.<field>               a value as E.Talents returns it (litanyRefund = 0.1)
-- (A spell rank's own data - base heal, coefficient, cost - is not typed over: it is
-- the game's, read from its tooltips; talents and stats cover every spell.)
---------------------------------------------------------------------------

-- The range a typed value must be in (a bad saved value must never break a rebuild,
-- and none in range may make a cost, cast time or heal go below zero).
local STAT_RANGE = { healing = { 0, 1e5 }, healingFromSpirit = { 0, 1e5 }, crit = { 0, 1 }, critMulti = { 1, 5 },
                     haste = { 0, 2 }, manaPool = { 1, 1e6 }, mp5 = { 0, 1e4 }, oocRegen = { 0, 1e5 },
                     castingShare = { 0, 1 }, critPerInt = { 0.001, 1 } }
local TALENT_RANGE = { impRenew = { 0.1, 3 }, twinDisc = { 0.1, 3 }, spiritualHealing = { 0.1, 3 }, impPWS = { 0.1, 3 },
                       mentalStrength = { 0.1, 3 }, mentalAgility = { 0, 0.9 }, impHealing = { 0, 0.9 },
                       soulWarding = { 0, 0.9 }, litany = { 0, 0.9 }, litanyRefund = { 0, 1 }, daMulti = { 0, 2 },
                       divineFury = { 0, 2.5 } }                         -- any other talent value: 0 to 1
function E.OverrideRange(id)
  if type(id) ~= "string" then return nil end
  local kind, field = id:match("^(%a+)%.(.+)$")
  local r
  if kind == "stat" then r = STAT_RANGE[field]
  elseif kind == "talent" then r = field:match("^%a+$") and (TALENT_RANGE[field] or { 0, 1 })
  end
  if r then return r[1], r[2] end
end
function E.OverrideOK(id, v)
  if type(v) ~= "number" or v ~= v then return false end
  local lo, hi = E.OverrideRange(id)
  return lo ~= nil and v >= lo and v <= hi
end

local function override(set, id)
  local o = set and set.overrides
  local v = o and o[id]
  if v ~= nil and E.OverrideOK(id, v) then return v end
end
E.OverrideFor = override

-- Final stats with your values in them. Regen while casting follows regen from
-- spirit (as a share of it), unless that share is typed over too. st.orig keeps
-- what each replaced value was.
function E.ApplyStatOverrides(st, o)
  if not (o and next(o)) then return st end
  local out, orig = copy(st), {}
  local share = (st.oocRegen or 0) > 0 and (st.combatRegen or 0) / st.oocRegen or 0
  for id, v in pairs(o) do
    local f = type(id) == "string" and id:match("^stat%.(.+)$")
    if f and f ~= "critPerInt" and f ~= "castingShare" and E.OverrideOK(id, v) then orig[f] = st[f]; out[f] = v end
  end
  local s = o["stat.castingShare"]
  if s ~= nil and E.OverrideOK("stat.castingShare", s) then orig.castingShare = share; share = s end
  if orig.oocRegen ~= nil or orig.castingShare ~= nil then
    if orig.combatRegen == nil then orig.combatRegen = st.combatRegen end
    out.combatRegen = out.oocRegen * share
  end
  out.orig = next(orig) and orig or nil
  return out
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
    fightLength = 300, pullEvery = 600, pomHits = 4, groupHits = 5, innervate = false, majorManaPotions = true, cheapManaPotions = false,
    manaTidesInGroup = 1, powerInfusionOut = false, includeInspiration = true,
    tankArmor = 6000, tankRawDTPS = 1200, inspirationIntoTank = 0.8,
    overheal = { RENEW = 0.25, PWS = 0, GH = 0.25, POH = 0.35, PENANCE = 0.25, BH = 0.25,
                 FLASH = 0.25, NOVA = 0.45, POM = 0.15, LESSER = 0.25, HEAL = 0.25,
                 -- Holy Binding's heal on you (Flash Heal on another target): you are rarely hurt
                 SELF = 0.85 },
    -- Litany of Light: share of a heal's casts that follow a DIFFERENT heal. Rotations work
    -- it out from their own spell mix; this is only used when a spell is looked at alone.
    litanyAlternation = 0.5,
    shieldWasteV2 = true,  -- new settings start with no shield waste (see E.MigrateSettings)
    imperfectPlay = 0.8, -- the sheet's factor for downtime you actually use under the 5-second rule
  },
}

local function curve(name, rank)
  local c = DATA.talents[name]
  if not c or not rank or rank <= 0 then return 0 end
  return c[math.min(rank, #c)]
end

local talentsFrom
-- o: your own values (talent.<field>); t.orig keeps what each replaced value was.
function E.Talents(tr, rules, o)
  local t = talentsFrom(tr, rules)
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

function talentsFrom(tr, rules)
  if (rules or E.RULES).talents == "game" then
    return {
      twinDisc = 1 + curve("twinDisciplines", tr.twinDisciplines) / 100,
      impPWS = 1 + curve("improvedPWS", tr.improvedPWS) / 100,
      mentalAgility = curve("mentalAgility", tr.mentalAgility) / 100,
      innerFocus = (tr.innerFocus or 0) > 0 and 1 or 0,
      meditation = curve("meditation", tr.meditation) / 100,
      mentalStrength = 1 + curve("mentalStrength", tr.mentalStrength) / 100,
      soulWarding = curve("soulWarding", tr.soulWarding) / 100,
      soulWardingCd = curve("soulWardingCd", tr.soulWarding),     -- seconds off PW:Shield's cooldown
      penance = (tr.penance or 0) > 0,
      daMulti = curve("divineAegis", tr.divineAegis) / 100,
      daCapPerLevel = curve("divineAegisCap", tr.divineAegis),    -- the most one target's Aegis holds, per level
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
      renewedHopeCut = curve("renewedHopeCut", tr.renewedHope),   -- seconds each heal takes off Weakened Soul
    }
  end
  return {   -- the sheet's values
    litanyRefund = 0, holyBinding = 0, soulWardingCd = 0, daCapPerLevel = 0, renewedHopeCut = 0,
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
  local b, c, r, t = input.buffs, input.consumables, input.race, E.Talents(input.talents, input.settings.rules, input.settings.overrides)
  local kings = b.kings and 1.1 or 1
  local spiritMult = kings * (r.human and 1.1 or 1) * (b.shadowSpirit and 1.15 or 1)
  local intMult = t.mentalStrength * kings
  return {
    spirit = spiritMult, int = intMult,
    healingPerSpirit = t.spiritualGuidance,         -- Spiritual Guidance
    spellDamagePerSpirit = input.talents.spiritualGuidance * 0.01,
    manaPerInt = 15 * (r.gnome and 1.05 or 1),
    critPctPerInt = override(input.settings, "stat.critPerInt")
      or ((input.settings.rules or E.RULES).critPerInt == "game" and E.CritPerInt(input.level) or 1 / 60),
    -- out-of-combat mp5 per spirit: sheet 0.64 (+40); the client fits the classic
    -- priest formula, 2.5 x (13 + spirit/4) = 32.5 + 0.625 x spirit, within 1%.
    regenPerSpirit = input.regenPerSpirit or 0.64,
  }
end

function E.Derive(input)
  local g, b, c, r, s = input.gear, input.buffs, input.consumables, input.race, input.settings
  local t = E.Talents(input.talents, input.settings.rules, input.settings.overrides)
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
    -- regen while casting: Meditation's share, or the share you typed on the Math tab
    local med = override(input.settings, "stat.castingShare")
      or E.Talents(input.talents, input.settings.rules, input.settings.overrides).meditation
    return { spirit = sp, healing = sp * m.healingPerSpirit, healingFromSpirit = sp * m.healingPerSpirit,
             spelldamage = sp * m.spellDamagePerSpirit,
             oocRegen = sp * m.regenPerSpirit, combatRegen = sp * m.regenPerSpirit * med }
  end
  if stat == "spelldamage" then return { spelldamage = 1 } end
end

-- Divine Aegis per cast on one target, at crit chance c. In the game a crit leaves an
-- absorb of daMulti x the crit's amount, and one target's absorb holds at most
-- daCapPerLevel x your level: clamped per heal event (each Penance
-- bolt, Holy Binding's heal on you apart), as one crit rarely reaches it. Stacking
-- crits on the same target is not modelled: the damage it takes eats it.
local function aegisFor(heal, c, key, bodies, st, t, rules)
  if (t.daMulti or 0) <= 0 or c <= 0 then return 0 end
  if not rules.aegisFromCrit then return heal * c * t.daMulti end
  if key == "RENEW" then return 0 end     -- only direct heals leave one (its proc flags), not a HoT's ticks
  local cap = (t.daCapPerLevel or 0) * (st.level or 60)
  local function capped(x) return cap > 0 and min(x, cap) or x end
  local n = (key == "BH") and 1 or (E.EVENTS_PER_CAST[key] or 1)
  local one = heal / (bodies or 1) / n * st.critMulti * t.daMulti   -- one event on the target
  local total = n * capped(one)
  if (bodies or 1) > 1 then total = total + n * capped(one * (bodies - 1)) end
  return total * c
end
E.AegisFor = aegisFor

-- The overheal of one cast as a whole. Flash Heal with Holy Binding also heals you
-- (its extra "body", a third of the cast): that part is wasted whenever you are at
-- full health, which is its own setting (overheal.SELF), not the spell's. The
-- sheet's rules count it at the spell's overheal.
function E.OverhealFor(key, sp, set)
  local oh = set.overheal[key] or 0
  local b = sp and sp.bodies or 1
  if b <= 1 or not (set.rules or E.RULES).selfOverheal then return oh end
  local mine = (b - 1) / b
  return oh * (1 - mine) + (set.overheal.SELF or oh) * mine
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
  local full = rk.coeff or sp.coeff
  local coeff = rankCoeff(rk, sp.coeff, st.level, rules)
  local power = (full and full > 0) and coeff / full or 1
  local base = baseAt(rk, st.level)
  local rankCost = rk.cost
  local bodies = sp.bodies or ((key == "FLASH" and (t.holyBinding or 0) > 0) and (1 + t.holyBinding)) or 1
  local heal, crit = 0, st.crit
  if sp.shield then
    heal = (base + coeff * (rules.twinDiscOnShield and t.twinDisc or 1) * healingFor(key, st, rules)) * t.impPWS
  else
    local tm = talentMult(key, t)
    heal = (base * tm + coeff * tm * healingFor(key, st, rules)) * bodies
  end
  local expected = sp.shield and heal or heal * ((1 - crit) + crit * st.critMulti)
  local aegis = sp.shield and 0 or aegisFor(heal, crit, key, bodies, st, t, rules)
  local cm, set4 = costMult(key, t), (set.dungeon4set and 10 or 0)
  local cost = rankCost * cm - set4
  local refund, share = 0, 0
  if (t.litanyRefund or 0) > 0 and E.LITANY_SPELLS[key] then
    share = set.litanyShare and set.litanyShare[key] or set.litanyAlternation or 0.5
    refund = rankCost * t.litanyRefund * share
    cost = cost - refund
  end
  cost = max(cost, 1)        -- only your own values (Math tab) could take it lower
  local targets = sp.targets == "pomhits" and set.pomHits or sp.targets == "group" and (set.groupHits or 5) or (sp.targets or 1)
  -- Renewed Hope variants (crit chance with the talent's bonus, crits fixed at 1.5x)
  local rcrit = crit + t.renewedHopeCrit
  local expectedRH = sp.shield and heal or heal * ((1 - rcrit) + rcrit * st.critMulti)
  return {
    key = key, rank = rankIdx, name = sp.name, cast = cast, coeff = coeff, bodies = bodies,
    heal = heal,                 -- one cast, one target, non-crit
    expected = expected,         -- one target, crit-weighted
    aegis = aegis,               -- Divine Aegis absorb per target
    expectedRH = expectedRH, aegisRH = sp.shield and 0 or aegisFor(heal, rcrit, key, bodies, st, t, rules),
    cost = cost, targets = targets,
    hpm = targets * (expected + aegis) / cost,
    hpct = targets * (expected + aegis) / max(cast, gcd),
    -- the working, for the Math tab (each number is the one used above)
    parts = {
      base = base, baseCalc = rk.bp and (rk.bp + rk.ppl * max(0, ((rk.ml and rk.ml > 0) and min(st.level, rk.ml) or st.level) - rk.bl)),
      bp = rk.bp, ppl = rk.ppl, bl = rk.bl, ml = rk.ml,
      fullCoeff = full, power = power,
      healing = healingFor(key, st, rules), talentMult = sp.shield and t.impPWS or talentMult(key, t),
      shield = sp.shield and true or false, crit = crit, critMulti = st.critMulti, daMulti = t.daMulti,
      aegisFromCrit = rules.aegisFromCrit and true or false, daCap = (t.daCapPerLevel or 0) * (st.level or 60),
      castBase = ct, haste = st.haste, divineFury = (key == "GH" or key == "HEAL") and t.divineFury or 0,
      rankCost = rankCost, costMult = cm, set4 = set4, refund = refund, litanyShare = share,
      litanyRefund = t.litanyRefund or 0, cast = cast,
    },
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
  local coeff = rankCoeff(rk, def.coeff, st.level, rules)
  if def.shield then
    return h / t.impPWS - coeff * (rules.twinDiscOnShield and t.twinDisc or 1) * healingFor(key, st, rules)
  end
  return h / talentMult(key, t) - coeff * healingFor(key, st, rules)
end

-- spells = { { key=, rank=, cost=, desc=, castTime= (ms) }, ... } read from the game.
-- The game's own numbers win: every rank you know takes its cost, base heal and
-- cast time from the game, so a patch that changes a spell is picked up by itself.
-- The game data (Models/PriestData.lua) is the starting point, and what a rank
-- keeps when the game says nothing usable about it. Two guards, both quiet:
--   * a reading outside half to double the game data's is a misread (say, a
--     tooltip whose wording changed): the data stays;
--   * seen: a table kept for the session (Core.lua). A rank's first reading is
--     taken as it is. Later, a reading that jumps away from it is taken as a
--     temporary effect (a buff that cuts costs or raises heals) and the earlier
--     one stays - until the new reading has stayed the same for E.HOLD seconds
--     (longer than such buffs last), when it becomes the rank's own. So a first
--     reading taken under a buff, or a lasting change (a set bonus), still wins
--     in the end. now = the game's clock (GetTime). A new level starts over,
--     since base heals grow with level.
-- Returns one report row per spell rank (/hm check prints it).
E.SANE_LOW, E.SANE_HIGH = 0.5, 2
E.JUMP = { cost = 0.03, base = 0.05, cast = 0.03 }
E.HOLD = 120

local function sane(v, data)
  return type(v) == "number" and type(data) == "number" and data > 0
    and v / data >= E.SANE_LOW and v / data <= E.SANE_HIGH
end
local function near(a, b, tol) return math.abs(a / b - 1) <= tol end

-- v (a usable reading or nil) -> the value to use and where it came from:
-- "client" (this reading), "earlier" (held: an earlier reading), "misread", or
-- nil (the game data).
local function take(seen, id, field, v, data, level, now)
  local s = seen and seen[id]
  if seen and (not s or s.level ~= level) then s = { level = level }; seen[id] = s end
  if v ~= nil and sane(v, data) then
    if not s then return v, "client" end
    local was, tol = s[field], E.JUMP[field]
    if was == nil or near(v, was, tol) then
      s[field], s[field .. "New"], s[field .. "Since"] = v, nil, nil
      return v, "client"
    end
    local new = s[field .. "New"]
    if new and near(v, new, tol) then
      if now and s[field .. "Since"] and now - s[field .. "Since"] >= E.HOLD then
        s[field], s[field .. "New"], s[field .. "Since"] = v, nil, nil
        return v, "client"
      end
    else
      s[field .. "New"], s[field .. "Since"] = v, now
    end
    return was, "earlier"
  end
  if s and s[field] then return s[field], "earlier" end
  return nil, (v ~= nil) and "misread" or nil
end

-- Downranking: does this client's tooltip show a low rank with the penalty, or at
-- full power? Both have been seen: a level-50 Holy priest's (20 Nov 2026) showed
-- every rank at FULL power while the real heal still had the penalty (Renew rank 1:
-- tooltip 310, ticks of 17 = 85, the rule's number); level-49 dumps and a level-50
-- Shadow priest's (21 Nov 2026, Renew rank 1: 62) showed the penalty exactly. It is
-- how the client draws its tooltips, so it is decided once per reading, by the ranks
-- where the two differ a lot. nil: no such rank (then the two are close, and each
-- rank takes the nearer).
local function tooltipShowsFull(spells, st, t, set)
  local full, pen = 0, 0
  for _, c in ipairs(spells) do
    local rk = E.SPELLS[c.key] and E.SPELLS[c.key].ranks[c.rank]
    local h = rk and E.ParseDesc(c.key, c.desc)
    if h then
      local m0 = E.ModelTooltipHeal(c.key, c.rank, st, t, set)
      rk.power = 1
      local m1 = E.ModelTooltipHeal(c.key, c.rank, st, t, set)
      rk.power = nil
      if m0 > 0 and m1 / m0 > 1.1 then
        if math.abs(h - m1) < math.abs(h - m0) then full = full + 1 else pen = pen + 1 end
      end
    end
  end
  if full + pen == 0 then return nil end
  return full >= pen
end

function E.ApplyClientData(spells, st, t, set, seen, now)
  E.SPELLS = E.copy(E.GAME_SPELLS)
  local rules = set.rules or E.RULES
  local showsFull = tooltipShowsFull(spells, st, t, set)
  local report = {}
  for _, c in ipairs(spells) do
    local def = E.SPELLS[c.key]
    local rk = def and def.ranks[c.rank]
    if rk then
      local id = c.key .. ":" .. c.rank
      local mult = costMult(c.key, t)
      local set4 = set.dungeon4set and 10 or 0
      local row = { key = c.key, rank = c.rank, dataCost = rk.cost * mult - set4, rawCost = rk.cost, clientCost = c.cost,
                    dataBase = baseAt(rk, st.level), dataCast = rk.cast }

      -- Cost. The game's already has your talents in it (Improved Healing: 15% off
      -- Lesser Heal, Heal, Greater Heal, Penance and Prayer of Mending), so they are
      -- taken back out and the model applies them again. 0 (Inner Focus) says nothing.
      local raw = (c.cost and c.cost > 0 and mult > 0) and (c.cost + set4) / mult or nil
      local cost, costFrom = take(seen, id, "cost", raw, rk.cost, st.level, now)
      if cost then rk.cost = cost end
      row.costFrom = costFrom

      -- Cast time. The game's has your haste and Divine Fury in it; both are taken
      -- back out. Instant and channelled spells say 0, and keep the data's.
      local ct
      if type(rk.cast) == "number" and c.castTime and c.castTime > 0 then
        local df = (c.key == "GH" or c.key == "HEAL") and t.divineFury or 0
        ct = c.castTime / 1000 * (1 + st.haste) + df
        -- the game gives whole milliseconds after haste: within 1% is the data's
        if math.abs(ct / rk.cast - 1) <= 0.01 then ct = rk.cast else ct = math.floor(ct * 100 + 0.5) / 100 end
        row.clientCast = ct
      end
      local cast, castFrom = take(seen, id, "cast", ct, type(rk.cast) == "number" and rk.cast or nil, st.level, now)
      if cast then rk.cast = cast end
      row.castFrom = castFrom

      -- Base heal: what makes the model heal exactly what the tooltip says, at
      -- your healing power and talents (the tooltip has both in it).
      local h = E.ParseDesc(c.key, c.desc)
      local base
      if h then
        row.client = h
        row.model = E.ModelTooltipHeal(c.key, c.rank, st, t, set)
        row.diff = row.client / row.model - 1
        local full = rk.coeff or def.coeff
        local rulePower = (full and full > 0) and E.Downrank(full, rk, st.level, rules) / full or 1
        local atFull = false
        if rulePower < 0.999 then
          if showsFull == nil then
            rk.power = 1
            local top = E.ModelTooltipHeal(c.key, c.rank, st, t, set)
            rk.power = nil
            atFull = math.abs(h - top) < math.abs(h - row.model)
          else
            atFull = showsFull
          end
        end
        if atFull then rk.power = 1 end
        base = baseFromClient(c.key, c.rank, h, st, t, set)
        rk.power = nil
        if atFull then row.tooltipFull, row.rulePower = true, rulePower end
      end
      local b, baseFrom = take(seen, id, "base", base, row.dataBase, st.level, now)
      if b then rk.base = b end
      row.baseFrom = baseFrom
      if h then
        if row.tooltipFull then rk.power = 1 end
        row.after = E.ModelTooltipHeal(c.key, c.rank, st, t, set)   -- as the tooltip shows it
        rk.power = nil
      end
      row.base = baseAt(rk, st.level)
      report[#report + 1] = row
    end
  end
  return report
end

---------------------------------------------------------------------------
-- Potions and runes for the fight.
-- From Wowhead's Forever item data (21-22 Nov 2026); the Mender's Potions'
-- 2 min cooldown is from the client's own tooltip (Wowhead leaves it out).
-- group: the items in one group share a cooldown, so together they fit only so
-- many times in a fight. Potions all share the potion cooldown (Mender's
-- Potions too, checked in game); runes have their own.
--   mana = average mana restored; manaPct = share of your max mana;
--   healing = extra healing power for dur seconds; sleep = seconds you can't cast.
---------------------------------------------------------------------------
E.POTION_GROUPS = {
  potion = { name = "Potion cooldown", cd = 120, order = 1 },
  rune = { name = "Rune cooldown", cd = 120, order = 2 },
}
E.POTION_ALL = 99      -- a count this high means "as many as fit"
E.POTIONS = {
  { key = "majorMana", id = 13444, name = "Major Mana Potion", lvl = 49, group = "potion", mana = (1350 + 2250) / 2, text = "1350 to 2250 mana" },
  { key = "superiorMana", id = 13443, name = "Superior Mana Potion", lvl = 41, group = "potion", mana = (900 + 1500) / 2, text = "900 to 1500 mana" },
  { key = "greaterMana", id = 6149, name = "Greater Mana Potion", lvl = 31, group = "potion", mana = (700 + 900) / 2, text = "700 to 900 mana" },
  { key = "mana", id = 3827, name = "Mana Potion", lvl = 22, group = "potion", mana = (455 + 585) / 2, text = "455 to 585 mana" },
  { key = "restoredMana", id = 282013, name = "Restored Mana Potion", lvl = 1, group = "potion", manaPct = 0.20, text = "20% of your mana" },
  { key = "majorRejuv", id = 18253, name = "Major Rejuvenation Potion", lvl = 50, group = "potion", mana = (1440 + 1760) / 2, text = "1440 to 1760 mana and health" },
  { key = "tessasTonic", id = 274935, name = "Tessa's Tonic", lvl = 35, group = "potion", mana = (720 + 880) / 2, text = "720 to 880 mana and health" },
  { key = "wildvine", id = 9144, name = "Wildvine Potion", lvl = 35, group = "potion", mana = (1 + 1500) / 2, text = "1 to 1500 mana and health" },
  { key = "greaterDreamless", id = 20002, name = "Greater Dreamless Sleep Potion", lvl = 55, group = "potion", mana = 2100, sleep = 12,
    text = "2100 mana and health, asleep for 12 s" },
  { key = "dreamless", id = 12190, name = "Dreamless Sleep Potion", lvl = 35, group = "potion", mana = 1200, sleep = 12,
    text = "1200 mana and health, asleep for 12 s" },
  { key = "majorMenders", id = 250949, name = "Major Mender's Potion", lvl = 55, group = "potion", healing = 88, dur = 30, text = "+88 healing for 30 s" },
  { key = "superiorMenders", id = 250948, name = "Superior Mender's Potion", lvl = 45, group = "potion", healing = 62, dur = 30, text = "+62 healing for 30 s" },
  { key = "greaterMenders", id = 250947, name = "Greater Mender's Potion", lvl = 35, group = "potion", healing = 44, dur = 30, text = "+44 healing for 30 s" },
  { key = "menders", id = 250946, name = "Mender's Potion", lvl = 25, group = "potion", healing = 31, dur = 30, text = "+31 healing for 30 s" },
  { key = "lesserMenders", id = 250945, name = "Lesser Mender's Potion", lvl = 15, group = "potion", healing = 20, dur = 30, text = "+20 healing for 30 s" },
  { key = "minorMenders", id = 250944, name = "Minor Mender's Potion", lvl = 5, group = "potion", healing = 13, dur = 30, text = "+13 healing for 30 s" },
  { key = "demonicRune", id = 12662, name = "Demonic Rune", lvl = 1, group = "rune", mana = (900 + 1500) / 2, text = "900 to 1500 mana for 600 to 1000 health" },
  { key = "darkRune", id = 20520, name = "Dark Rune", lvl = 1, group = "rune", mana = (900 + 1500) / 2, text = "900 to 1500 mana for 600 to 1000 health" },
}
E.POTION_BY_KEY = {}
for _, p in ipairs(E.POTIONS) do E.POTION_BY_KEY[p.key] = p end

-- How many times one cooldown fits in the fight: the first at 15 s, then one per
-- cooldown (the sheet's count for mana potions).
function E.PotionFits(fl, group)
  local g = E.POTION_GROUPS[group]
  return max(1, ceil((fl - 15) / (g and g.cd or 120)))
end

-- Settings saved before the potion list: "mana potion on cooldown" (and the
-- sheet's cheaper potion) become the list. Changes s; true if it did.
-- Saved settings from older versions, brought up to date (true if anything changed):
-- the potion list (below), and Power Word: Shield's waste, 5% by default until 1.7, now
-- 0 (a shield is cast where damage comes; set your own if yours run out unused).
function E.MigrateSettings(s)
  if type(s) ~= "table" then return false end
  local changed = E.MigratePotions(s)
  if not s.shieldWasteV2 then
    if type(s.overheal) == "table" and s.overheal.PWS == 0.05 then s.overheal.PWS = 0; changed = true end
    s.shieldWasteV2 = true
  end
  return changed
end

function E.MigratePotions(s)
  if type(s) ~= "table" or s.potions ~= nil then return false end
  local list = {}
  if s.majorManaPotions ~= false then list[#list + 1] = { key = "majorMana", n = E.POTION_ALL } end
  if s.cheapManaPotions then list[#list + 1] = { key = "superiorMana", n = E.POTION_ALL } end
  s.potions, s.majorManaPotions, s.cheapManaPotions = list, nil, nil
  return true
end

-- The fight's potions: each listed item's uses (its group's cooldown shared in
-- list order: an item takes what is left, up to its count), and what they add.
-- Without a list (the sheet tests): the sheet's mana potion switches.
function E.PotionPlan(st, set)
  local fl = set.fightLength
  local plan = { items = {}, groups = {}, mana = 0, healing = 0, sleep = 0, count = 0 }
  if set.potions == nil then
    local n = E.PotionFits(fl, "potion")
    local each = (set.majorManaPotions and 1800 or 0) + (set.cheapManaPotions and 1200 or 0)
    plan.mana, plan.count, plan.sheet = n * each, each > 0 and n or 0, { n = n, per = each }
    return plan
  end
  for index, entry in ipairs(set.potions) do
    local def = E.POTION_BY_KEY[entry.key]
    if def then
      local g = plan.groups[def.group]
      if not g then
        g = { key = def.group, fits = E.PotionFits(fl, def.group), used = 0 }
        plan.groups[def.group] = g
      end
      local canUse = (def.lvl or 1) <= (st.level or 60)
      local n = canUse and max(0, min(entry.n or 0, g.fits - g.used)) or 0
      g.used = g.used + n
      local each = def.manaPct and def.manaPct * st.manaPool or def.mana or 0
      local item = { key = def.key, def = def, n = n, want = entry.n or 0, tooLow = not canUse, manaEach = each, index = index,
                     mana = n * each, sleep = n * (def.sleep or 0) }
      if def.healing then
        item.uptime = min(1, n * def.dur / fl)
        item.healing = def.healing * item.uptime          -- healing power on average over the fight
      end
      plan.items[#plan.items + 1] = item
      plan.mana = plan.mana + item.mana
      plan.healing = plan.healing + (item.healing or 0)
      plan.sleep = plan.sleep + item.sleep
      plan.count = plan.count + n
    end
  end
  return plan
end

-- A copy of the settings with another potion list (and the spell ranks the
-- playstyle chose with your list, so each trial doesn't search ranks again).
local function withPotions(set, list, rankChoice)
  local s2 = {}
  for k, v in pairs(set) do s2[k] = v end
  s2.potions, s2.rankChoice = list, rankChoice or set.rankChoice
  return s2
end

-- The playstyle's HPS (after overheal) with a potion list; nil without a model.
local function potionHPS(rotKey, st, t, set, list, rankChoice)
  local r = E.Rotation(rotKey, st, t, withPotions(set, list, rankChoice))
  return r and r.ehps
end
local function ranksNow(rotKey, st, t, set)
  local r = E.Rotation(rotKey, st, t, set)
  return r and r.rankChoice
end

-- The counts for your list that heal the most: every way of sharing each
-- cooldown among the items on it (none to as many as fit), tried together.
-- Returns a list like set.potions (same order) and its HPS, or nil.
function E.BestPotions(rotKey, st, t, set)
  local list = set.potions or {}
  if #list == 0 then return nil end
  local fl = set.fightLength
  local byGroup, groups = {}, {}
  for i, entry in ipairs(list) do
    local def = E.POTION_BY_KEY[entry.key]
    if def and (def.lvl or 1) <= (st.level or 60) then
      if not byGroup[def.group] then byGroup[def.group] = {}; groups[#groups + 1] = def.group end
      table.insert(byGroup[def.group], i)
    end
  end
  -- every split of up to `fits` uses among n items
  local function splits(n, fits)
    local out = {}
    local function rec(i, left, cur)
      if i > n then out[#out + 1] = { unpack(cur) }; return end
      for k = 0, left do cur[i] = k; rec(i + 1, left - k, cur) end
      cur[i] = nil
    end
    rec(1, fits, {})
    return out
  end
  local options = {}
  for gi, g in ipairs(groups) do options[gi] = splits(#byGroup[g], E.PotionFits(fl, g)) end
  local rc = ranksNow(rotKey, st, t, set)
  -- Every split with the spell ranks held as they are now (quick), then the best
  -- few again with the ranks chosen for them: a potion can change which ranks are
  -- best (a Mender's Potion in a short fight makes higher ranks worth it).
  local trials, counts = {}, {}
  local function rec(gi)
    if #trials > 300 then return end
    if gi > #groups then
      local trial = {}
      for i, entry in ipairs(list) do trial[i] = { key = entry.key, n = counts[i] or 0 } end
      trials[#trials + 1] = { list = trial, quick = potionHPS(rotKey, st, t, set, trial, rc) or -math.huge }
      return
    end
    for _, split in ipairs(options[gi]) do
      for j, idx in ipairs(byGroup[groups[gi]]) do counts[idx] = split[j] end
      rec(gi + 1)
    end
  end
  rec(1)
  table.sort(trials, function(a, b) return a.quick > b.quick end)
  local best, bestHPS
  for i = 1, math.min(3, #trials) do
    local h = potionHPS(rotKey, st, t, set, trials[i].list)
    if h and (not bestHPS or h > bestHPS + 1e-9) then best, bestHPS = trials[i].list, h end
  end
  return best, bestHPS
end

-- What one item is worth to you: the HPS with it used as often as its cooldown
-- allows (instead of the others on that cooldown), against none of them. Each
-- with the spell ranks chosen for it.
function E.PotionValue(rotKey, st, t, set, key)
  local def = E.POTION_BY_KEY[key]
  if not def then return nil end
  local others = {}
  for _, entry in ipairs(set.potions or {}) do
    local d = E.POTION_BY_KEY[entry.key]
    if d and d.group ~= def.group then others[#others + 1] = entry end
  end
  local with = { { key = key, n = E.POTION_ALL } }
  for _, e in ipairs(others) do with[#with + 1] = e end
  local a, b = potionHPS(rotKey, st, t, set, with), potionHPS(rotKey, st, t, set, others)
  return a and b and (a - b) or nil
end

---------------------------------------------------------------------------
-- Mana budget for the fight (sheet Sim F4:O6).
---------------------------------------------------------------------------
-- E.ManaParts: the same sum, part by part (for the Math tab): key, mana, and the
-- numbers it was made from.
function E.ManaParts(st, t, set)
  local fl = set.fightLength
  local ticks = fl / 5
  local pots = E.PotionPlan(st, set)
  local tideN = max(1, ceil((fl - 5) / 300))
  local innN = max(1, ceil((fl - 15) / 360))
  local innEach = (set.innervate and 1 or 0) * (st.oocRegen * 5 - st.combatRegen) * 4
  local piN = max(1, fl / 180)
  return {
    { key = "pool", mana = st.manaPool },
    { key = "mp5", mana = ticks * st.mp5, ticks = ticks, per = st.mp5 },
    { key = "casting", mana = ticks * st.combatRegen, ticks = ticks, per = st.combatRegen },
    { key = "potions", mana = pots.mana, n = pots.sheet and pots.sheet.n or pots.count,
      per = pots.sheet and pots.sheet.per or nil, plan = pots },
    { key = "manaTide", mana = tideN * set.manaTidesInGroup * 290 * 4, n = tideN * set.manaTidesInGroup, per = 290 * 4 },
    { key = "innervate", mana = innN * innEach, n = set.innervate and innN or 0, per = innEach },
    { key = "powerInfusion", mana = set.powerInfusionOut and -250 * piN or 0, n = set.powerInfusionOut and piN or 0, per = -250 },
  }
end

function E.ManaBudget(st, t, set)
  local sum = 0
  for _, p in ipairs(E.ManaParts(st, t, set)) do sum = sum + p.mana end
  return sum
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

-- The playstyles as shipped; E.SetPlaystyles puts edited ones and yours next to them.
E.BUILTIN_ROTATIONS = {}
for k, r in pairs(E.ROTATIONS) do E.BUILTIN_ROTATIONS[k] = r end

local function gcdsFor(s, gcd) return max(s.cast, gcd) / gcd end
-- Renewed Hope's spells (the talent's own list; BH is Flash Heal)
local RH_SPELLS = { FLASH = true, LESSER = true, HEAL = true, GH = true, PENANCE = true, BH = true }   -- a cast takes at least a global cooldown

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
  -- Weakened Soul: the search tries ranks with the last settled values (one pass
  -- each), and the ranks it keeps are run again until they settle
  local ws = best.ws and best.ws.again
  if ws then s2.wsRate, s2.wsUptime = best.ws.rate, best.ws.uptime end
  for _ = 1, 2 do
    for _, c in ipairs(cands) do
      local keep = s2.rankChoice[c.i]
      for r = 1, c.top do
        if r ~= keep then
          s2.rankChoice[c.i] = r
          local res = rotationLitany(rotKey, st, t, s2)
          if res and res.eff > best.eff + 1e-9 then
            best, keep = res, r
            if ws and res.ws then s2.wsRate, s2.wsUptime = res.ws.rate, res.ws.uptime end
          end
        end
      end
      s2.rankChoice[c.i] = keep
    end
  end
  if ws then
    s2.wsRate, s2.wsUptime = nil, nil
    best = rotationLitany(rotKey, st, t, s2) or best
  end
  best.rankChoice = s2.rankChoice
  return best
end

-- Weakened Soul on the tank (rules.weakenedSoul): how long it lasts depends on the
-- Renewed Hope heals that cut it, and how often the tank is shielded on how long it
-- lasts, so the pass runs again with what the last one counted (it settles fast).
local WS_PASSES = 3
E.SetWSPasses = function(n) WS_PASSES = n end   -- tests
local function rotationWS(rotKey, st, t, set)
  local out = rotationPass(rotKey, st, t, set)
  if not (out and out.ws and out.ws.again) or set.wsRate then return out end
  local s2 = {}
  for k, v in pairs(set) do s2[k] = v end
  -- a fixed number of passes, so stat weights (two runs, a stat apart) see no
  -- jump from one stopping a pass earlier than the other
  for _ = 1, WS_PASSES do
    s2.wsRate, s2.wsUptime = out.ws.rate, out.ws.uptime
    out = rotationPass(rotKey, st, t, s2)
  end
  return out
end

function rotationLitany(rotKey, st, t, set)
  if (t.litanyRefund or 0) <= 0 or set.litanyShare then return rotationWS(rotKey, st, t, set) end
  local first = rotationWS(rotKey, st, t, set)
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
  local out = rotationWS(rotKey, st, t, set2)
  out.litanyShare = set2.litanyShare
  return out
end

function rotationPass(rotKey, st, t, set)
  local rot = E.ROTATIONS[rotKey]
  local fl = set.fightLength
  -- Potions: a Mender's Potion's healing power, averaged over the fight (heals grow
  -- in a straight line with healing power, so the average is exact); time asleep
  -- (Dreamless Sleep) can't be used for casting. Their mana is in ManaBudget.
  local pots = E.PotionPlan(st, set)
  if pots.healing > 0 then
    local s2 = {}
    for k, v in pairs(st) do s2[k] = v end
    s2.healing, s2.potionHealing = st.healing + pots.healing, pots.healing
    st = s2
  end
  local gcd = 1.5 / (1 + st.haste)
  local free = max(0, fl - pots.sleep) / gcd
  local mana = E.ManaBudget(st, t, set)
  local pwsOH = set.overheal.PWS
  local out = { name = rot.name, steps = {}, mana = mana, raw = 0, eff = 0, potions = pots }
  local tankCasts, tankCrits, last = 0, 0, nil
  local rules = set.rules or E.RULES
  -- Weakened Soul (game rules): a shield on the tank waits for it; it lasts its
  -- lockout less what Renewed Hope's heals on the tank take off (rate: such heals a
  -- second, from the last pass); Renewed Hope's crit counts for the share of the
  -- fight it is up (uptime, from the last pass; at first: up all the time)
  local ws = rules.weakenedSoul and { rate = 0, shields = 0, uptime = 0 } or nil
  local wsTiming = (DATA.timing or {}).PWS or {}
  local wsLen = (wsTiming.lockout or 0) / (1 + (t.renewedHopeCut or 0) * (set.wsRate or 0))
  local wsUp = set.wsUptime or 1
  local shieldCd = max(0, (wsTiming.cd or 0) - (t.soulWardingCd or 0))

  -- A rotation needs its filler; without it (too low level) there is no model.
  local fillKey
  for _, step in ipairs(rot.steps) do if step.fill then fillKey = step[1] end end
  if fillKey and not tableFor(set)[fillKey] and E.STEP_ALIAS[fillKey] then fillKey = E.STEP_ALIAS[fillKey] end
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
    local n, limit = 0, nil
    -- PW:Shield's real spacing (game rules): its cooldown (none with Soul Warding),
    -- on the tank also Weakened Soul; "on cooldown" asks for no more than that
    local cap = step.cap
    if ws and key == "PWS" and not step.fill then
      local least = max(gcd, shieldCd, step.tank and wsLen or 0)
      cap = step.onCd and least or max(cap or 0, least)
    end
    if enabled then
      local byCd, byMana, byTime = cap and not step.fill and fl / cap or math.huge, mana / sp.cost, free / perCastGcds
      n = min(byCd, byMana, byTime)
      limit = (n == byCd and "cooldown") or (n == byMana and "mana") or "time"
      n = max(0, n)
    end
    -- Renewed Hope: the built-ins as the sheet has them (every heal but these three);
    -- a playstyle you built: only its blocks on the tank (the shielded target)
    -- (game rules: only Renewed Hope's own spells, on the tank, while Weakened Soul is up)
    local useRH
    if rot.custom then useRH = step.rh and true or false
    else useRH = rot.renewedHope and key ~= "POM" and key ~= "RENEW" and key ~= "PWS" end
    if ws then useRH = useRH and step.tank and RH_SPELLS[key] and true or false end
    local up = useRH and (ws and wsUp or 1) or 0
    local hpc = (sp.expected + (sp.expectedRH - sp.expected) * up) * sp.targets
    local da = (sp.aegis + (sp.aegisRH - sp.aegis) * up) * sp.targets
    local raw = n * hpc
    local oh = E.OverhealFor(key, sp, set)
    local eff = raw * (1 - oh) + n * da * (1 - pwsOH)
    free = free - n * perCastGcds
    mana = mana - n * sp.cost
    out.raw = out.raw + raw + n * da
    out.eff = out.eff + eff
    if not step.noCrit then
      tankCasts = tankCasts + n * (step.tank or 0)
      tankCrits = tankCrits + n * (step.tank or 0) * (st.crit + up * t.renewedHopeCrit)
    end
    if ws and useRH then ws.rate = ws.rate + n / fl end            -- Penance: the cast, not each bolt
    if ws and key == "PWS" and step.tank then ws.shields = ws.shields + n end
    out.steps[#out.steps + 1] = { key = key, rank = sp.rank, casts = n, raw = raw, eff = eff, enabled = enabled and true or false,
                                  cap = cap, fill = step.fill, tank = step.tank,
                                  id = tableFor(set)[key].ranks[sp.rank].id,
                                  limit = limit, perCast = hpc, aegis = da, overheal = oh,
                                  time = perCastGcds * gcd, cost = sp.cost, rh = useRH or nil, rhUp = useRH and up or nil,
                                  least = (key == "PWS" and ws) and max(gcd, shieldCd) or nil,
                                  manaBefore = mana + n * sp.cost }
    if step.fill then last, fillIdx = sp, #out.steps end
  end

  if ws then
    ws.len = wsLen
    local len = (wsTiming.lockout or 0) / (1 + (t.renewedHopeCut or 0) * ws.rate)
    ws.uptime = min(1, ws.shields * len / fl)
    -- another pass only matters with Renewed Hope heals (their crit, their cut)
    ws.again = ws.rate > 0 and ((t.renewedHopeCrit or 0) > 0 or (t.renewedHopeCut or 0) > 0)
    out.ws = ws
  end

  -- 5-second rule: unused GCDs -> pauses to regenerate -> extra filler casts
  out.freeGcds = max(0, free)
  out.pauseTime = out.freeGcds * gcd               -- time not spent casting: mana ran out first
  local per = pauseCycle(last.cost, max(last.cast, gcd), st, set.rules)
  local extra = set.imperfectPlay * out.pauseTime / per
  out.pauseCycle, out.gcd, out.manaLeft = per, gcd, mana
  -- every target the filler heals (Prayer of Healing: 5), as its own casts count them
  local pauseHeal, pauseAegis = last.expected * last.targets, last.aegis * last.targets
  local fillRaw = extra * pauseHeal
  local fillEff = fillRaw * (1 - E.OverhealFor(last.key, last, set)) + extra * pauseAegis * (1 - pwsOH)
  out.raw = out.raw + fillRaw + extra * pauseAegis
  out.pauseHeal, out.pauseAegis = pauseHeal, pauseAegis
  out.eff = out.eff + fillEff
  out.fiveSecondCasts = extra
  out.pauseEff = fillEff
  local fs = out.steps[fillIdx]
  fs.pauseCasts, fs.eff = extra, fs.eff + fillEff

  -- Inner Focus on Prayer of Healing: free, +25% crit
  local pohRank = E.MaxRank("POH", st.level, set.known, set)
  local ifCasts = pohRank and max(1, ceil(fl / 180)) * t.innerFocus or 0
  if ifCasts > 0 then
    local poh = E.Spell("POH", pohRank, st, t, set)
    local c = st.crit + 0.25
    local h = poh.heal * ((1 - c) + c * st.critMulti) * poh.targets
    local da = aegisFor(poh.heal, c, "POH", 1, st, t, set.rules or E.RULES) * poh.targets
    local ifEff = ifCasts * (h * (1 - set.overheal.POH) + da * (1 - pwsOH))
    out.raw = out.raw + ifCasts * (h + da)
    out.eff = out.eff + ifEff
    out.innerFocus = { casts = ifCasts, rank = pohRank, eff = ifEff, perCast = h, aegis = da }
  end

  -- Inspiration: crits on the tank raise its armor by 25%; the damage it no
  -- longer takes counts as healing.
  out.inspiration = 0
  if set.includeInspiration and t.inspiration > 0 then
    local rate
    if ws then rate = set.inspirationIntoTank * tankCrits / fl
    else
      local crit = rot.renewedHope and (st.crit + t.renewedHopeCrit) or st.crit
      rate = set.inspirationIntoTank * tankCasts * crit / fl
    end
    local uptime = 1 - exp(-rate * 15)
    local a0 = set.tankArmor
    local a1 = a0 * (1 + t.inspiration)
    local saved = set.tankRawDTPS * (1 - a0 / (a0 + 7285)) - set.tankRawDTPS * (1 - a1 / (a1 + 7285))
    out.inspiration = saved * uptime            -- already per second (damage per second saved)
    out.inspirationParts = { rate = rate, uptime = uptime, armor = a0, armorUp = a1, saved = saved, dtps = set.tankRawDTPS }
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

---------------------------------------------------------------------------
-- Playstyles as blocks (the Playstyles tab): a playstyle you build or edit is a
-- list of blocks, top first, the last one filling the rest:
--   def = { name, rh = true (keep Weakened Soul on the tank: Renewed Hope),
--           steps = { { spell, rank, how, n, tank }, ... } }
--   spell  a key of E.SPELLS, or BH (Flash Heal, cast only with Holy Binding)
--   rank   nil = the best rank (the model tries them), "top" = your highest, or a number
--   how    "cd" on cooldown | "up" keep it up | "pm" n times a minute |
--          "sec" every n seconds | "fill" the rest (the last block only)
--   tank   cast on the tank: its crits count for Inspiration, and with rh it gets
--          Renewed Hope's crit; PW:Shield on cooldown on one target waits for Weakened Soul
-- E.RotationFromPlaystyle turns one into the steps rotationPass runs, so nothing in
-- the fight model changes. The built-ins (E.BUILTIN_ROTATIONS) never change: an
-- edited one is saved apart and put in their place by E.SetPlaystyles.
---------------------------------------------------------------------------
E.PALETTE = { "POM", "PENANCE", "PWS", "RENEW", "LESSER", "HEAL", "FLASH", "GH", "POH", "NOVA" }
E.STEP_NEEDS = { POM = "pom", PENANCE = "penance", BH = "bindingHeal" }
E.MAX_STEPS = 8
E.MAX_PLAYSTYLE_NAME = 32
local NO_RH = { POM = true, RENEW = true, PWS = true }
-- Inspiration needs a direct heal that crits: Renew's ticks and a shield never do
local NO_CRIT = { RENEW = true, PWS = true }
local TIMING = DATA.timing or {}
local GCD_FLOOR = 1.5   -- no block more often than a global cooldown

function E.StepSpellName(key)
  if key == "BH" then return "Flash Heal (Holy Binding)" end
  local sp = E.SPELLS[key]
  return sp and sp.name or tostring(key)
end

-- The spell a block casts in the game data (Binding Heal is Flash Heal).
local function dataKey(key) return key == "BH" and "FLASH" or key end
function E.StepRankCount(key)
  local sp = E.SPELLS[dataKey(key)]
  return sp and #sp.ranks or 0
end

-- Which "how often" choices a spell has: cooldown only with one, keep up only Renew.
function E.WeakenedSoulLockout() return TIMING.PWS and TIMING.PWS.lockout or 15 end

function E.StepHasCooldown(key) return (TIMING[key] and TIMING[key].cd or 0) > 0 end
function E.StepCanKeepUp(key) return (TIMING[key] and TIMING[key].dur or 0) > 0 end

-- The shortest time a block can come round again: its own cooldown, at least a GCD.
function E.StepMinEvery(key) return max(GCD_FLOOR, TIMING[key] and TIMING[key].cd or 0) end

-- Seconds between a block's casts, or nil for the filler (or a choice that can't be).
function E.StepEvery(d)
  local tm = TIMING[d.spell] or {}
  if d.how == "cd" then
    if d.spell == "PWS" and d.tank and tm.lockout then return max(tm.cd or 0, tm.lockout) end
    return (tm.cd or 0) > 0 and tm.cd or nil
  elseif d.how == "up" then return (tm.dur or 0) > 0 and tm.dur or nil
  elseif d.how == "pm" then return (tonumber(d.n) or 0) > 0 and 60 / d.n or nil
  elseif d.how == "sec" then return (tonumber(d.n) or 0) > 0 and d.n or nil end
  return nil
end

-- A block's "how often" in words: "on cooldown", "at most twice a minute", "at most
-- every 12 s" (a ceiling: a block is cast less when the mana runs out first).
function E.Seconds(v)
  local s = string.format("%.1f", v):gsub("%.0$", "")
  return s
end
function E.HowText(d)
  if d.how == "cd" then return "on cooldown"
  elseif d.how == "up" then return "keep it up"
  elseif d.how == "fill" then return "fill the rest"
  elseif d.how == "pm" then
    return "at most " .. (d.n == 1 and "once a minute" or d.n == 2 and "twice a minute" or (tostring(d.n) .. " times a minute"))
  elseif d.how == "sec" then return "at most every " .. E.Seconds(d.n) .. " s" end
  return "?"
end

-- A new block's starting choices: on cooldown if it has one, Renew kept up, else
-- twice a minute; single-target heals on the tank.
local GROUP_HEALS = { RENEW = true, POH = true, NOVA = true }
function E.NewStep(key, rank)
  local d = { spell = key, rank = rank, tank = not GROUP_HEALS[key] or nil }
  if E.StepHasCooldown(key) then d.how = "cd"
  elseif E.StepCanKeepUp(key) then d.how = "up"
  else d.how, d.n = "pm", 2 end
  return d
end

-- "Prayer of Mending on cooldown on the tank, ..., then Renew to fill the rest."
function E.PlaystyleSummary(def)
  local parts, fill = {}, nil
  for _, d in ipairs(def.steps or {}) do
    local name = E.StepSpellName(d.spell) .. (type(d.rank) == "number" and (" rank " .. d.rank) or "")
    if d.how == "fill" then fill = name
    else parts[#parts + 1] = name .. " " .. E.HowText(d) .. (d.tank and " on the tank" or "") end
  end
  local s = table.concat(parts, ", ")
  if fill then s = (s ~= "" and (s .. ", then ") or "") .. fill .. " the rest of the time" end
  return (s:gsub("^%l", string.upper)) .. "."
end

function E.CleanPlaystyleName(name)
  -- no | (colour codes), and none of the export line's separators (, and ;)
  name = type(name) == "string" and name:gsub("[|,;]", ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
  if name == "" or #name > E.MAX_PLAYSTYLE_NAME then return nil end
  return name
end

-- nil when a playstyle can be used, else why not (for the editor and imports).
function E.PlaystyleProblem(def)
  if type(def) ~= "table" then return "Not a playstyle." end
  if not E.CleanPlaystyleName(def.name) then return "A playstyle needs a name of 1 to " .. E.MAX_PLAYSTYLE_NAME .. " letters." end
  local steps = type(def.steps) == "table" and def.steps or {}
  if #steps == 0 then return "A playstyle needs at least one spell." end
  if #steps > E.MAX_STEPS then return "At most " .. E.MAX_STEPS .. " blocks." end
  for i, d in ipairs(steps) do
    local at = "Block " .. i .. ": "
    if type(d) ~= "table" or (not E.SPELLS[d.spell] and d.spell ~= "BH") then return at .. "unknown spell." end
    local name, nr = E.StepSpellName(d.spell), E.StepRankCount(d.spell)
    if d.rank ~= nil and d.rank ~= "top" then
      if type(d.rank) ~= "number" or d.rank < 1 or d.rank > nr or d.rank % 1 ~= 0 then
        return at .. name .. " has ranks 1 to " .. nr .. "."
      end
    end
    local last = (i == #steps)
    if d.how == "fill" then
      if not last then return at .. "only the last block can fill the rest." end
      if d.spell == "BH" then
        return "Flash Heal (Holy Binding) is cast only with that talent, so it can't fill the rest: use Flash Heal."
      end
      if E.StepHasCooldown(d.spell) then
        return name .. " has a cooldown, so it can't fill the rest: the last block needs a spell without one."
      end
    elseif last then return "The last block fills the rest: " .. name .. " is set to " .. E.HowText(d) .. "."
    elseif d.how == "cd" and not E.StepHasCooldown(d.spell) then return at .. name .. " has no cooldown."
    elseif d.how == "up" and not E.StepCanKeepUp(d.spell) then return at .. "only Renew can be kept up."
    elseif d.how == "pm" or d.how == "sec" then
      local n = tonumber(d.n)
      if not n or n <= 0 or (d.how == "pm" and n % 1 ~= 0) then return at .. "how often is missing." end
      local every, least = E.StepEvery(d), E.StepMinEvery(d.spell)
      if every < least - 1e-9 then
        return at .. name .. " can't be cast more often than every " .. E.Seconds(least) .. " s."
      end
      if every > 600 then return at .. "at most every 600 s." end
    elseif d.how ~= "cd" and d.how ~= "up" then return at .. "how often is missing." end
  end
  return nil
end

-- A warning that doesn't stop a playstyle: PW:Shield on one target more often than
-- Weakened Soul allows (the built-ins ask for this, as the sheet does). The fight
-- model waits for Weakened Soul, so such a block is cast less often than it says.
function E.StepWarning(d)
  local tm = TIMING[d.spell]
  if d.spell == "PWS" and d.tank and tm and tm.lockout and d.how ~= "fill" then
    local every = E.StepEvery(d)
    if every and every < tm.lockout - 1e-9 then
      -- the whole warning, and a short one for under the spell's name
      return "Weakened Soul keeps you from shielding the same target again for " .. E.Seconds(tm.lockout) ..
        " s; this block asks for every " .. E.Seconds(every) .. " s. The fight counts a shield only when Weakened " ..
        "Soul is gone, which Renewed Hope's heals on the tank make sooner.",
        "waits for Weakened Soul (" .. E.Seconds(tm.lockout) .. " s)"
    end
  end
end

-- def -> the playstyle the fight model runs. base: the built-in it replaces.
function E.RotationFromPlaystyle(def, base)
  local rot = { name = def.name, custom = true, renewedHope = def.rh and true or nil, steps = {},
                requires = base and base.requires, help = E.PlaystyleSummary(def) }
  for _, d in ipairs(def.steps) do
    local s = { d.spell, needs = E.STEP_NEEDS[d.spell] }
    if d.rank == nil then s.auto = true elseif type(d.rank) == "number" then s.rank = d.rank end
    if d.how == "fill" then s.fill = true else s.cap = E.StepEvery(d) end
    if d.how == "cd" then s.onCd = true end      -- the fight model works out PW:Shield's real one
    if d.tank then s.tank = d.spell == "PENANCE" and 3 or 1 end    -- Penance: 3 bolts, 3 crits
    s.rh = (def.rh and d.tank and not NO_RH[d.spell]) and true or false
    s.noCrit = NO_CRIT[d.spell] or nil
    rot.steps[#rot.steps + 1] = s
  end
  return rot
end

-- A built-in (or any playstyle the model runs) as blocks, for the editor.
function E.PlaystyleFromRotation(rot)
  local def = { name = rot.name, rh = rot.renewedHope and true or nil, steps = {} }
  for _, s in ipairs(rot.steps) do
    local d = { spell = s[1], tank = (s.tank or 0) > 0 or nil }
    if s.auto then d.rank = nil elseif s.rank then d.rank = s.rank else d.rank = "top" end
    if s.fill then d.how = "fill"
    else
      local function is(how) d.how = how; local e = E.StepEvery(d); return e and math.abs(e - s.cap) < 1e-9 end
      if not (is("cd") or is("up")) then
        local per = 60 / s.cap
        if math.abs(per - math.floor(per + 0.5)) < 1e-9 then d.how, d.n = "pm", math.floor(per + 0.5)
        else d.how, d.n = "sec", s.cap end
      end
    end
    def.steps[#def.steps + 1] = d
  end
  return def
end

-- Put the built-ins (or your edits of them) and your own playstyles into E.ROTATIONS.
-- custom: id -> def; edits: built-in key -> def. A saved one that can't be used
-- (a broken save) is left out; its built-in stays as shipped. The table stays the
-- same table, so everything holding it sees the change.
-- The fight as a strip (Playstyles tab): the casts the model counts, placed in
-- time by priority - each block when it is due (and while its count lasts), the
-- filler in the gaps, then once its mana is spent a filler every pause cycle
-- (the 5-second rule) with waiting in between. An illustration of the counts,
-- not a simulation: the model itself never orders casts.
--   { casts = { { t, dur, block, key, rank, pause } ... }, waits = { { t0, t1 } ... } }
function E.FightTimeline(def, base, fl)
  if not (def and base and base.steps and fl and fl > 0) then return nil end
  local gcd = base.gcd or 1.5
  local blocks, fillIdx = {}, nil
  for i, s in ipairs(base.steps) do
    local d = def.steps[i]
    -- due: when it may go next. A limit you set (at most 8 a minute) keeps its own
    -- rhythm, catching up after a cast pushed it back; a real cooldown can't
    blocks[i] = { left = (s.enabled and s.casts or 0), dur = max(s.time or gcd, gcd), every = (not s.fill) and s.cap or nil,
                  key = s.key, rank = s.rank, due = 0, least = s.least or E.StepMinEvery(s.key) }
    if s.fill or (d and d.how == "fill") then fillIdx = i end
  end
  local per = base.pauseCycle or math.huge
  local pauseLeft = base.fiveSecondCasts or 0
  local out = { casts = {}, waits = {} }
  local lastFill = -math.huge
  local t, guard = 0, 0
  while t < fl - 1e-6 and guard < 5000 do
    guard = guard + 1
    local chosen, pause
    for i, b in ipairs(blocks) do
      if b.left >= 0.5 then
        if i == fillIdx then chosen = i; break end
        if t >= b.due - 1e-6 then chosen = i; break end
      end
    end
    if not chosen and fillIdx and pauseLeft >= 0.5 and t - lastFill >= per - 1e-6 then chosen, pause = fillIdx, true end
    if chosen then
      local b = blocks[chosen]
      local c = { t = t, dur = min(b.dur, fl - t), block = chosen, key = b.key, rank = b.rank, pause = pause or nil }
      out.casts[#out.casts + 1] = c
      if b.every then b.due = max(b.due + b.every, t + b.least) end
      if chosen == fillIdx then lastFill = t end
      if pause then pauseLeft = pauseLeft - 1 else b.left = b.left - 1 end
      t = t + b.dur
    else
      local nxt = math.huge
      for i, b in ipairs(blocks) do
        if b.left >= 0.5 and i ~= fillIdx and b.every then nxt = min(nxt, b.due) end
      end
      if fillIdx and pauseLeft >= 0.5 then nxt = min(nxt, lastFill + per) end
      nxt = min(nxt, fl)
      if nxt <= t + 1e-6 then nxt = fl end
      out.waits[#out.waits + 1] = { t, nxt }
      t = nxt
    end
  end
  return out
end

-- A Holy Binding block that ended up last is plain Flash Heal (the same spell; the
-- filler can't wait for a talent). Fixes a saved playstyle in place; true if it did.
function E.FixPlaystyle(def)
  local steps = type(def) == "table" and type(def.steps) == "table" and def.steps
  local last = steps and steps[#steps]
  if type(last) == "table" and last.spell == "BH" and last.how == "fill" then last.spell = "FLASH"; return true end
  return false
end

function E.SetPlaystyles(custom, edits)
  for k in pairs(E.ROTATIONS) do E.ROTATIONS[k] = nil end
  for k, r in pairs(E.BUILTIN_ROTATIONS) do
    local ed = type(edits) == "table" and edits[k]
    E.FixPlaystyle(ed)
    if ed and not r.sheetOnly and not E.PlaystyleProblem(ed) then
      local nr = E.RotationFromPlaystyle(ed, r)
      nr.name, nr.builtin, nr.edited = r.name, k, true
      E.ROTATIONS[k] = nr
    else
      E.ROTATIONS[k] = r
    end
  end
  for id, d in pairs(type(custom) == "table" and custom or {}) do
    E.FixPlaystyle(d)
    if not E.BUILTIN_ROTATIONS[id] and not E.PlaystyleProblem(d) then
      local nr = E.RotationFromPlaystyle(d)
      nr.mine = true
      E.ROTATIONS[id] = nr
    end
  end
end

-- The export line, readable on purpose:
--   HM1:Renew + Inspiration;POM,b,cd,t;LESSER,2,20pm,t;GH,b,2pm,t;RENEW,b,fill
-- name (",rh" after it: keep Weakened Soul on the tank), then per block: spell,
-- rank (b best, h highest, or a number), how often (cd, up, fill, <n>pm, or <n>
-- seconds), and t for on the tank.
E.EXPORT_PREFIX = "HM1:"
function E.PlaystyleExport(def)
  local parts = { (E.CleanPlaystyleName(def.name) or "Playstyle") .. (def.rh and ",rh" or "") }
  for _, d in ipairs(def.steps) do
    local rank = d.rank == nil and "b" or d.rank == "top" and "h" or tostring(d.rank)
    local how = d.how == "pm" and (tostring(d.n) .. "pm") or d.how == "sec" and E.Seconds(d.n) or d.how
    parts[#parts + 1] = d.spell .. "," .. rank .. "," .. how .. (d.tank and ",t" or "")
  end
  return E.EXPORT_PREFIX .. table.concat(parts, ";")
end

-- The line back into a playstyle: def, or nil and why. Only ever read as text.
function E.PlaystyleImport(text)
  text = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if text:sub(1, #E.EXPORT_PREFIX):upper() ~= E.EXPORT_PREFIX then
    return nil, "That isn't a Holy Math playstyle (it starts with " .. E.EXPORT_PREFIX .. ")."
  end
  local parts = {}
  for piece in (text:sub(#E.EXPORT_PREFIX + 1) .. ";"):gmatch("([^;]*);") do parts[#parts + 1] = piece end
  local head = table.remove(parts, 1) or ""
  local name, flag = head:match("^([^,]*),?(.*)$")
  local def = { name = E.CleanPlaystyleName(name), steps = {} }
  if not def.name then return nil, "The playstyle has no name." end
  flag = (flag or ""):gsub("%s", ""):lower()
  if flag == "rh" then def.rh = true elseif flag ~= "" then return nil, "Unknown option \"" .. flag .. "\" after the name." end
  for i, piece in ipairs(parts) do
    if piece:match("%S") then
      local f = {}
      for v in (piece .. ","):gmatch("([^,]*),") do f[#f + 1] = v:gsub("%s", "") end
      local at = "Block " .. (#def.steps + 1) .. ": "
      local spell = (f[1] or ""):upper()
      if not (E.SPELLS[spell] or spell == "BH") then return nil, at .. "unknown spell \"" .. (f[1] or "") .. "\"." end
      local d = { spell = spell }
      local r = (f[2] or ""):lower()
      if r == "b" or r == "" then d.rank = nil
      elseif r == "h" then d.rank = "top"
      elseif tonumber(r) then d.rank = tonumber(r)
      else return nil, at .. "unknown rank \"" .. f[2] .. "\"." end
      local h = (f[3] or ""):lower()
      if h == "cd" or h == "up" or h == "fill" then d.how = h
      elseif h:match("^%d+pm$") then d.how, d.n = "pm", tonumber(h:match("^(%d+)"))
      elseif tonumber(h) then d.how, d.n = "sec", tonumber(h)
      else return nil, at .. "unknown \"how often\" \"" .. (f[3] or "") .. "\"." end
      for j = 4, #f do
        if f[j]:lower() == "t" then d.tank = true
        elseif f[j] ~= "" then return nil, at .. "unknown option \"" .. f[j] .. "\"." end
      end
      def.steps[#def.steps + 1] = d
    end
  end
  local problem = E.PlaystyleProblem(def)
  if problem then return nil, problem end
  return def
end

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
  local t = E.Talents(input.talents, input.settings.rules, input.settings.overrides)
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
    w[stat .. "Up"], w[stat .. "Step"] = up.ehps, s
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
  local t = E.Talents(input.talents, input.settings.rules, input.settings.overrides)
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
  local t = E.Talents(input.talents, input.settings.rules, input.settings.overrides)
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
  local oh = E.OverhealFor(key, sp, set)
  local heal = (sp.expected * (1 - oh) + sp.aegis * (1 - (set.overheal.PWS or 0))) * sp.targets
  local gcd = 1.5 / (1 + st.haste)
  return heal, sp.cost, max(sp.cast, gcd), sp
end
E.CastValue = castValue

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

-- Every rank of one spell you know, highest first: heal per cast (after
-- overheal, all targets), mana, per mana, per second, and how much of your
-- healing power it still gets (low ranks get less: see E.Downrank).
function E.SpellRanks(key, st, t, set)
  local def = tableFor(set)[key]
  local top = def and E.MaxRank(key, st.level, set.known, set)
  if not top then return {} end
  local out, bestR, bestH, bestRawR, bestRawH = {}, nil, nil, nil, nil
  for r = 1, top do
    local heal, cost, time, sp = castValue(key, r, st, t, set)
    local full = def.ranks[r].coeff or def.coeff
    local hpm = cost > 0 and heal / cost or math.huge
    -- raw, as other addons show it: before overheal, on your target(s) only (Holy Binding's
    -- heal on you apart), at the spell's full cost (no Litany of Light refund)
    local b = sp.bodies or 1
    local raw = (sp.expected + sp.aegis) / b * sp.targets
    local fullCost = cost + (sp.parts.refund or 0)          -- the spell's cost, no Litany of Light refund
    out[#out + 1] = { rank = r, heal = heal, cost = cost, hpm = hpm, hps = heal / time, id = def.ranks[r].id,
                      power = (full and full > 0) and sp.coeff / full or 1, lvl = def.ranks[r].lvl,
                      overheal = E.OverhealFor(key, sp, set),
                      raw = { heal = sp.heal / b, expected = sp.expected / b, targets = sp.targets,
                              onYou = sp.expected * (b - 1) / b, refund = sp.parts.refund or 0,
                              hpm = fullCost > 0 and raw / fullCost or math.huge, hps = raw / time } }
    if not bestH or hpm > bestH + 1e-9 then bestR, bestH = r, hpm end
    local rh = out[#out].raw.hpm
    if not bestRawH or rh > bestRawH + 1e-9 then bestRawR, bestRawH = r, rh end
  end
  for _, row in ipairs(out) do row.best, row.bestRaw = (row.rank == bestR), (row.rank == bestRawR) end
  table.sort(out, function(a1, b1) return a1.rank > b1.rank end)
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
    -- game rules: Weakened Soul's own length (the sheet's 12 s otherwise)
    if key == "PWS" and (set.rules or E.RULES).weakenedSoul then every = E.WeakenedSoulLockout() end
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
    local h = poh.heal * ((1 - cr) + cr * st.critMulti) * poh.targets * (1 - (set.overheal.POH or 0))
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
