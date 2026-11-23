-- Checks the engine against the spreadsheet's own computed values.
-- Run from the HolyMath folder:  lua5.1 tests/run_tests.lua
local E = dofile("Models/Priest.lua")

local fails, passes = 0, 0
local function near(label, got, want, tol)
  tol = tol or 1e-6
  local ok = math.abs(got - want) <= tol * math.max(1, math.abs(want))
  if ok then passes = passes + 1 else fails = fails + 1 end
  print(string.format("%s %-44s got %14.6f  sheet %14.6f", ok and "ok  " or "FAIL", label, got, want))
end

-- Part 1 reproduces the SHEET, so it runs with the sheet's rules (downranking
-- from 16 levels, Twin Disciplines on PW:Shield). Part 2 checks the game client.
local input = E.copy(E.DEFAULTS)
input.settings.rules = E.SHEET_RULES
local st = E.Derive(input)
local t = E.Talents(input.talents, input.settings.rules)
local set = input.settings

print("-- Final stats (Profile column E)")
near("healing power E3", st.healing, 828.587375)
near("intellect E4", st.int, 407.77)
near("crit E5", st.crit, 0.1879616667)
near("mp5 E7", st.mp5, 98)
near("spirit C8", st.spirit, 630.3495)
near("ooc regen D8", st.oocRegen, 443.42368)
near("combat regen E8", st.combatRegen, 221.71184)
near("mana pool E10", st.manaPool, 8116.55)
near("spell damage C12", st.spelldamage, 331.517475)

print("-- Spells tab (max rank; heal J, crit-weighted K, cost M, HPM N, HPCT O)")
local function row(key, rank, J, K, M, N, O)
  local s = E.Spell(key, rank, st, t, set)
  local tag = key .. " r" .. rank
  if J then near(tag .. " heal", s.heal, J) end
  if K then near(tag .. " expected", s.expected, K) end
  if M then near(tag .. " cost", s.cost, M) end
  if N then near(tag .. " HPM", s.hpm, N) end
  if O then near(tag .. " HPCT", s.hpct, O) end
end
row("RENEW", 9, 1972.403238, 2157.771338, 295.65, 7.298397897, 1438.514226)
row("RENEW", 5, 706.0422703, 772.3967112, 137.7, 5.609271687, 514.9311408)
row("GH", 4, 2716.517348, 2971.817912, 491.25, 6.04950211, 1188.727165)
row("GH", 1, 1567.064878, 1714.338941, 270, 6.349403486, 685.7355764)
row("FLASH", 7, 1309.208674, 1432.249196, 342, 4.187863146, 954.8327973)
row("FLASH", 3, 507.9874695, 555.7285552, 166.5, 3.33770904, 370.4857035)
row("BH", 6, 1963.813011, 2148.373794, 342, 6.281794719, 1432.249196)
row("POH", 4, 910.3823609, 995.9408539, 927, 5.371849266, 1659.901423)
row("PENANCE", 4, 2001.133643, 2189.201851, 288.75, 7.581651431, 1094.600925)
row("POM", 3, 879.1006074, 961.7192151, 257.4, 14.94513155, 2564.584574)
row("NOVA", 6, 586.9693802, 642.1332517, 607.5, 5.285047339, 2140.444172)
row("PWS", 10, 1175.268564, 1175.268564, 455, 2.583007834, 783.5123762)
row("PWS", 1, 64.26018976, 64.26018976, 40.95)

print("-- Mana budget (Sim G6)")
near("total mana", E.ManaBudget(st, t, set), 33859.2604)

print("-- Rotations (Profile K/L = Sim N/M)")
local r1 = E.Rotation("renew", st, t, set)
near("Renew filler raw HPS (K3)", r1.hps, 1132.504054)
near("Renew filler EHPS (L3)", r1.ehps, 889.377443)
near("Renew filler renew casts (C40)", r1.steps[5].casts, 60.22242652)
near("Renew filler 5SR renews (E43)", r1.fiveSecondCasts, 11.96774897)

-- Sheet slip: Sim!M102 adds T88 (an armor-reduction fraction, 0.0506) where the
-- other rotations add T27 (Inner Focus EHPS, 24.04), and N102 adds S88 (blank)
-- for S27 (Inner Focus raw HPS, 36.99). We add Inner Focus; so the sheet's value
-- plus that correction is what we should hit.
local r5 = E.Rotation("renewDown", st, t, set)
near("Downranked raw HPS (K4 + IF fix)", r5.hps, 1139.678887 + 36.9912883)
near("Downranked EHPS (L4 - T88 + T27)", r5.ehps, 898.5083012 - 0.05060447086 + 24.04433739)

-- PWS tank (K8/L8): the sheet only casts PW:Shield if Binding Heal is talented
-- (C54 tests bhtalented). With BH talented, as on the sheet, that slip does nothing.
local r2 = E.Rotation("pwsTank", st, t, set)
near("PWS tank raw HPS (K8)", r2.hps, 972.5569093)
near("PWS tank EHPS (L8)", r2.ehps, 790.2271416)

-- The sheet's weights (Profile G3:G8) are typed-in numbers, not formulas. Tried:
-- 300s and 180s fights, step sizes, raw vs effective, Inspiration on/off - none
-- reproduces them. The Bis Lists HPS figures are the same kind of snapshot: with
-- consumables off, set 3 (same gear as Profile) matches within 0.1-0.4%, sets 1
-- and 2 stay ~3% off under every buff/consumable combination we searched (2048).
-- So both look like values from an earlier version of the sheet; shown, not checked.
-- What IS checked: a weight equals the HPS change the full model gives for that stat.
print("-- Stat weights: EHPS per +1 gear stat (shown, not checked: sheet values are pasted)")
local w = E.Weights("renew", st, input, 1)
local sheetW = { healing = 0.5380, int = 0.4538, crit = 5.1942, haste = 0.7558, mp5 = 1.1532, spirit = 0.7509 }
for _, k in ipairs(E.WEIGHT_STATS) do
  print(string.format("     %-8s ours %.3f (raw %.3f)   sheet %.3f", k, w[k], w[k .. "Raw"], sheetW[k]))
end
do -- consistency: +25 intellect through the full model ~= 25 x the int weight
   -- (within 1%: only Inspiration's uptime curve bends, through int -> crit)
  local st2 = {}
  for k, v in pairs(st) do st2[k] = v end
  for k, v in pairs(E.StatDelta(input, "int")) do st2[k] = st2[k] + 25 * v end
  local gain = E.Rotation("renew", st2, t, set).ehps - w.base.ehps
  near("+25 int via model vs 25 x weight", gain, 25 * w.int, 1e-2)
end

print("-- Spells you don't have yet are not modelled")
do
  local lowSet = E.copy(set)
  lowSet.known = { RENEW = 4, FLASH = 2, LESSER = 3, PWS = 4 } -- e.g. a level-26 priest
  local r = E.Rotation("renew", st, t, lowSet)
  local gh, poh
  for _, s in ipairs(r.steps) do if s.key == "GH" then gh = s.casts end end
  near("no Greater Heal casts before it is learned", gh, 0)
  near("filler uses highest known Renew rank", r.steps[#r.steps].rank, 4)
  lowSet.known = { FLASH = 2 }
  local ok = E.Rotation("renew", st, t, lowSet) == nil
  near("no Renew known -> no model (nil)", ok and 1 or 0, 1)
end

print("-- Item comparison through the full model")
do
  local d, pct = E.Compare("renew", st, input, { healing = 20 })
  near("+20 healing via Compare == 20 x healing weight", d, 20 * w.healing, 1e-6)
end

---------------------------------------------------------------------------
-- Part 2: the game client. Tooltip numbers saved by /hm dump on 20 Nov 2026
-- (level 49 priest, 175 healing power, Twin Disciplines 4/5, no other healing
-- talents). Forever's tooltips include healing power and talents, so the model
-- must hit them (within tooltip rounding: they show whole numbers).
---------------------------------------------------------------------------
print("-- Client tooltips, level 49, 175 healing power (20 Nov 2026 dump)")
local CLIENT = {
  { "FLASH", 1, 233.5 }, { "FLASH", 2, 312.5 }, { "FLASH", 3, 399.5 }, { "FLASH", 4, 472.5 }, { "FLASH", 5, 598.5 },
  { "GH", 1, 1019.5, 370 }, { "GH", 2, 1266.5 },
  { "LESSER", 1, 59.5 }, { "LESSER", 2, 107.5 }, { "LESSER", 3, 181.5 },
  { "POH", 1, 235.5 }, { "POH", 2, 324.5 },
  { "RENEW", 1, 65 }, { "RENEW", 2, 96 }, { "RENEW", 3, 202 }, { "RENEW", 4, 293 }, { "RENEW", 5, 395 },
  { "RENEW", 6, 462 }, { "RENEW", 7, 566 },
  { "PWS", 1, 49 }, { "PWS", 2, 93 }, { "PWS", 3, 167 }, { "PWS", 4, 246 }, { "PWS", 5, 318 }, { "PWS", 6, 398 }, { "PWS", 7, 502 },
}
-- Penance r1 and Prayer of Mending r1: from their talent tooltips (same dump).
table.insert(CLIENT, { "PENANCE", 1, 173 * 3 })   -- "173 healing to an ally", per bolt, 3 bolts
do
  local ranks = {}
  for k in pairs(E.DEFAULTS.talents) do ranks[k] = 0 end
  ranks.twinDisciplines = 4
  local ct = E.Talents(ranks)
  local cst = { level = 49, healing = 175, crit = 0.0461, haste = 0.15, critMulti = 1.5 }
  local cset = E.copy(E.DEFAULTS.settings)   -- client rules (E.RULES)
  local sheetSet = E.copy(cset); sheetSet.rules = E.SHEET_RULES
  for _, c in ipairs(CLIENT) do
    local key, rank, client = c[1], c[2], c[3]
    local tag = key .. " r" .. rank
    local got = E.ModelTooltipHeal(key, rank, cst, ct, cset)
    local tol = key == "PENANCE" and 3 or 1      -- Penance: 1 per bolt x 3 bolts
    near(tag .. " tooltip", got, client, tol / client)
  end
  -- The sheet's rules miss the client where they differ:
  local f1 = E.ModelTooltipHeal("FLASH", 1, cst, ct, sheetSet)
  near("sheet's 16-level rule misses Flash r1 (229 vs 233.5)", math.abs(f1 - 233.5) > 3 and 1 or 0, 1)
  local tdSet = E.copy(cset); tdSet.rules = E.copy(E.RULES); tdSet.rules.twinDiscOnShield = true
  local p6 = E.ModelTooltipHeal("PWS", 6, cst, ct, tdSet)
  near("Twin Disc on PW:Shield misses r6 (399.2 vs 398)", math.floor(p6) ~= 398 and 1 or 0, 1)

  -- Calibration: feed the client data back; afterwards every rank matches and
  -- GH r1 takes the client's cost.
  local spells = {}
  local function desc(key, v)
    if key == "RENEW" then return "Heals the target of " .. v .. " damage over 15 sec." end
    if key == "PWS" then return "absorbing " .. v .. " damage." end
    if key == "PENANCE" then return "causing 73 Holy damage to an enemy, or " .. math.floor(v / 3 + 0.5) .. " healing to an ally" end
    local a = math.floor(v - 10)                 -- whole numbers, like the game
    return string.format("Heals a friendly target for %d to %d.", a, 2 * v - a)
  end
  for _, c in ipairs(CLIENT) do spells[#spells + 1] = { key = c[1], rank = c[2], cost = c[4], desc = desc(c[1], c[3]) } end
  local report = E.ApplyClientData(spells, cst, ct, cset)
  local allUsed = true
  for _, r in ipairs(report) do if r.baseFrom ~= "client" then allUsed = false; print("     not calibrated: " .. r.key .. " " .. r.rank) end end
  near("all client heals accepted (within 5%)", allUsed and 1 or 0, 1)
  near("GH r2 after calibration", E.ModelTooltipHeal("GH", 2, cst, ct, cset), 1266.5, 1e-9)
  near("POH r1 after calibration", E.ModelTooltipHeal("POH", 1, cst, ct, cset), 235.5, 1e-9)
  near("GH r1 cost (370 in game data and client)", E.SPELLS.GH.ranks[1].cost, 370)
  -- the game's cost always wins (talents taken back out): 15% under the data is taken too
  E.ApplyClientData({ { key = "GH", rank = 1, cost = 315 } }, cst, ct, cset)
  near("a cost 15% off the data is taken (a patch)", E.SPELLS.GH.ranks[1].cost * (1 - ct.impHealing), 315, 1e-9)
  E.SPELLS = E.copy(E.GAME_SPELLS)

  -- Downranking: "12 after max level" vs "17 after learned". They differ only for a
  -- rank whose max level is not learned + 5. Two such ranks in the client:
  local learned17 = E.copy(cset); learned17.rules = E.copy(E.RULES)
  learned17.rules.downrank, learned17.rules.downrankFreeLevels = "learned", 17
  for _, c in ipairs({ { "POH", 1, 235.5 }, { "PENANCE", 1, 519 } }) do
    local wrong = E.ModelTooltipHeal(c[1], c[2], cst, ct, learned17)
    near(c[1] .. " r" .. c[2] .. ": '17 after learned' misses the client", math.abs(wrong - c[3]) > 3 and 1 or 0, 1)
  end

  -- Prayer of Mending r1 talent tooltip says 259; the data gives (172 + 0.429 x 175) x 1.04 = 257.
  -- Not explained yet: shown, not checked.
  print(string.format("     open: Prayer of Mending r1 tooltip 259, model %.1f", E.ModelTooltipHeal("POM", 1, cst, ct, cset)))
end

print("-- Holy Binding: Flash Heal also heals you for 50% (Forever's 'Binding Heal')")
do
  local ranks = {}
  for k in pairs(E.DEFAULTS.talents) do ranks[k] = 0 end
  local cst = { level = 60, healing = 500, crit = 0.1, haste = 0, critMulti = 1.5, int = 300, spirit = 300,
                spelldamage = 0, mp5 = 50, manaPool = 7000, oocRegen = 218.75, combatRegen = 0 }
  local cset = E.copy(E.DEFAULTS.settings)
  local plain = E.Spell("FLASH", 7, cst, E.Talents(ranks), cset)
  ranks.holyBinding = 1
  local bound = E.Spell("FLASH", 7, cst, E.Talents(ranks), cset)
  near("Flash Heal with Holy Binding heals 1.5x", bound.heal / plain.heal, 1.5, 1e-9)
  near("tooltip comparison still per target", E.ModelTooltipHeal("FLASH", 7, cst, E.Talents(ranks), cset), plain.heal, 1e-9)
  -- rotation: the Binding Heal step casts Flash Heal only with the talent
  local gset = E.copy(E.DEFAULTS.settings)
  local function flashCasts(tr)
    local r = E.Rotation("renew", cst, E.Talents(tr), gset)
    for _, s in ipairs(r.steps) do if s.key == "FLASH" then return s.casts end end
    return 0
  end
  ranks.holyBinding = 0; ranks.bindingHeal = 0
  near("no Holy Binding: no Flash Heal step", flashCasts(ranks), 0)
  ranks.holyBinding = 1; ranks.bindingHeal = 1
  near("Holy Binding: 2 Flash Heals a minute (the sheet's Binding Heal)", flashCasts(ranks), 10)
end

print("-- Optimiser (linear programming)")
do
  -- textbook: max 3x + 5y, x <= 4, 2y <= 12, 3x + 2y <= 18  ->  x = 2, y = 6, value 36
  local x, v = E.LP({ 3, 5 }, { { 1, 0 }, { 0, 2 }, { 3, 2 } }, { 4, 12, 18 })
  near("LP textbook value", v, 36)
  near("LP x", x[1], 2); near("LP y", x[2], 6)
end

print("-- Best mix of spells (game rules, sheet's character)")
do
  local gi = E.copy(E.DEFAULTS)              -- the sheet's character, game rules
  local gst = E.Derive(input)                -- stats as derived for the sheet tests
  local gt = E.Talents(gi.talents)
  local gset = E.copy(E.DEFAULTS.settings)
  gset.includeInspiration = false            -- the mix doesn't count Inspiration; compare like with like
  local mix = E.BestMix(gst, gt, gset)
  local mana, time, pom = 0, 0, 0
  for _, it in ipairs(mix.items) do
    local sp = E.Spell(it.key, it.rank, gst, gt, gset)
    mana = mana + (it.casts - (it.fromPauses or 0)) * sp.cost
    time = time + (it.casts - (it.fromPauses or 0)) * math.max(sp.cast, 1.5 / (1 + gst.haste))
    if it.key == "POM" then pom = pom + it.casts end
  end
  near("mix stays within the mana budget", mana <= mix.mana + 1e-6 and 1 or 0, 1)
  near("mix stays within the fight", time <= gset.fightLength + 1e-6 and 1 or 0, 1)
  near("Prayer of Mending at most once per 10 s", pom <= gset.fightLength / 10 + 1e-6 and 1 or 0, 1)
  local gin = E.copy(gi); gin.settings = gset
  local plans = E.ComparePlans(gst, gin)
  print(string.format("     best plan %s %.1f, best mix %.1f healing per second after overheal", plans[1].name, plans[1].ehps, mix.ehps))
  for _, it in ipairs(mix.items) do
    print(string.format("       %-20s r%-2d %6.1f casts  %4.0f%% of casts%s", it.name, it.rank, it.casts, it.share * 100,
      it.fromPauses and string.format(" (%.1f from pauses)", it.fromPauses) or ""))
  end
  near("best mix heals at least as much as every plan", mix.ehps >= plans[1].ehps - 1e-6 and 1 or 0, 1)
  local tbl = E.SpellTable(gst, gt, gset)
  near("spell table lists every known spell", #tbl >= 8 and 1 or 0, 1)
  -- the overview's folded-down ranks agree with its spell lines
  local agree, oneBest, lowGetLess = 0, 0, 0
  for _, sr in ipairs(tbl) do
    local rk = E.SpellRanks(sr.key, gst, gt, gset)
    local nBest, bestRank = 0, nil
    for _, r in ipairs(rk) do if r.best then nBest, bestRank = nBest + 1, r.rank end end
    if #rk == sr.top and rk[1].rank == sr.top and math.abs(rk[1].heal - sr.topHeal) < 1e-9
       and math.abs(rk[1].cost - sr.topCost) < 1e-9 and bestRank == sr.bestRank then agree = agree + 1 end
    if nBest == 1 then oneBest = oneBest + 1 end
    if rk[#rk].power <= rk[1].power then lowGetLess = lowGetLess + 1 end
  end
  near("every spell's ranks: highest first, top rank and most efficient rank match the spell line", agree, #tbl)
  near("every spell has exactly one most efficient rank", oneBest, #tbl)
  near("rank 1 never gets more healing power than the top rank", lowGetLess, #tbl)
  local renew = E.SpellRanks("RENEW", gst, gt, gset)
  near("Renew rank 1 at level 60 gets 10% of your healing power", renew[#renew].power, 0.1, 1e-9)
end

print("-- Regen pauses and playstyles that pick their ranks (the 20 Nov dump's character)")
do
  local dst = { level = 49, healing = 175, spelldamage = 138, int = 179, spirit = 179, crit = 0.0461, haste = 0,
                critMulti = 1.5, mp5 = 21, manaPool = 3547, oocRegen = 143.1, combatRegen = 0 }
  local ranks = {}
  for k in pairs(E.DEFAULTS.talents) do ranks[k] = 0 end
  ranks.twinDisciplines = 4
  local dt = E.Talents(ranks)
  local din = { talents = ranks, buffs = {}, race = { troll = true }, consumables = {}, settings = E.copy(E.DEFAULTS.settings) }
  din.settings.known = { RENEW = 7, GH = 2, FLASH = 5, POH = 2, PWS = 7, LESSER = 3, HEAL = 4 }
  -- regen 143.1 per 5 s = 28.6 per s: 455 mana takes 15.9 s, + 5 s rule + 3 s cast
  near("pause cycle for one Greater Heal r2 (s)", E.PauseCycle(455, 3, dst), 5 + 455 / (143.1 / 5) + 3, 1e-9)
  near("the sheet's formula made it 5x too short", E.PauseCycle(455, 3, dst, E.SHEET_RULES), 5 + 455 / 143.1 + 2, 1e-9)
  local plans = E.ComparePlans(dst, din)
  near("sheet-only playstyle not offered", (function() for _, p in ipairs(plans) do if p.key == "renewDown" then return 1 end end return 0 end)(), 0)
  near("5 playstyles offered (Renewed Hope tank needs its talent)", #plans, 5)
  local withRH = E.copy(din); withRH.talents = E.copy(ranks); withRH.talents.renewedHope = 5
  local rhOffered = false
  for _, p in ipairs(E.ComparePlans(dst, withRH)) do if p.key == "rhTank" then rhOffered = true end end
  near("Renewed Hope tank offered with the talent", rhOffered and 1 or 0, 1)
  local poh = E.Rotation("pohFill", dst, dt, din.settings)
  local pohCasts = 0
  for _, st in ipairs(poh.steps) do if st.key == "POH" then pohCasts = st.casts + (st.pauseCasts or 0) end end
  near("Prayer of Healing filler casts Prayer of Healing", pohCasts > 1 and 1 or 0, 1)
  local rh = E.Rotation("rhTank", dst, E.Talents(withRH.talents), din.settings)
  local shieldRank
  for _, st in ipairs(rh.steps) do if st.key == "PWS" then shieldRank = st.rank end end
  near("Renewed Hope tank uses a rank 1 shield", shieldRank or 0, 1)
  near("best for this character: Greater Heal filler", plans[1].key == "ghFill" and 1 or 0, 1)
  local mix = E.BestMix(dst, dt, din.settings)
  near("best playstyle within 1% of the best possible mix", plans[1].ehps, mix.ehps, 0.01)
  -- auto ranks: the chosen ranks heal at least as much as any single fixed choice
  local renew = E.Rotation("renew", dst, dt, din.settings)
  local fillIdx = #E.ROTATIONS.renew.steps
  for r = 1, 7 do
    local s2 = E.copy(din.settings)
    s2.rankChoice = E.copy(renew.rankChoice); s2.rankChoice[fillIdx] = r
    local fixed = E.Rotation("renew", dst, dt, s2)
    if fixed.eff > renew.eff + 1e-6 then near("Renew rank " .. r .. " beats the automatic choice", 0, 1) end
  end
  near("automatic Renew rank is the best of ranks 1-7", 1, 1)
end

print("-- Client tooltips, Holy priest (20 Nov 2026 dump, after a client patch)")
do
  local F = dofile("tests/fixture_client_holy.lua")
  local t = E.Talents(F.talents)
  local st = { level = F.level, healing = F.healing, crit = F.crit, haste = 0, critMulti = 1.5,
               spirit = F.spirit, healingFromSpirit = F.spirit * t.spiritualGuidance }
  local set = E.copy(E.DEFAULTS.settings)
  local n, off = 0, 0
  for _, c in ipairs(F.spells) do
    local client = E.ParseDesc(c.key, c.desc)
    if client then
      n = n + 1
      local got = E.ModelTooltipHeal(c.key, c.rank, st, t, set)
      local tol = c.key == "POM" and 0.01 * client or 1   -- PoM: base corrected at runtime (see below)
      if math.abs(got - client) > tol then
        off = off + 1
        print(string.format("     differs: %s r%d game %.1f model %.1f", c.key, c.rank, client, got))
      end
    end
  end
  near("Holy talents: every known rank matches the client (" .. n .. " ranks)", off, 0)
  near("Spiritual Guidance gives 25% of spirit as healing (49 of 224)", st.healingFromSpirit, 49)
  -- Prayer of Mending: without the rule it is 7% off; with it, within 1% (both dumps)
  local noRule = E.copy(set); noRule.rules = E.copy(E.RULES); noRule.rules.pomWithoutSpiritHealing = false
  local wrong = E.ModelTooltipHeal("POM", 1, st, t, noRule)
  near("PoM without the rule misses 287 by > 5%", math.abs(wrong / 287 - 1) > 0.05 and 1 or 0, 1)
  near("PoM with the rule: Holy dump (287)", E.ModelTooltipHeal("POM", 1, st, t, set), 287, 0.01)
  local shadowRanks = {}
  for k in pairs(E.DEFAULTS.talents) do shadowRanks[k] = 0 end
  shadowRanks.twinDisciplines = 4
  local shadowSt = { level = 49, healing = 175, crit = 0.05, haste = 0, critMulti = 1.5, spirit = 179, healingFromSpirit = 0 }
  near("PoM with the rule: Shadow dump (259)", E.ModelTooltipHeal("POM", 1, shadowSt, E.Talents(shadowRanks), set), 259, 0.01)
  -- and at runtime the remaining <1% is taken from the client
  local spells = {}
  for _, c in ipairs(F.spells) do spells[#spells + 1] = { key = c.key, rank = c.rank, cost = c.cost, desc = c.desc } end
  local report = E.ApplyClientData(spells, st, t, set)
  near("PoM after calibration matches 287", E.ModelTooltipHeal("POM", 1, st, t, set), 287, 1e-9)
  -- Improved Healing 3/3: the game's costs are 15% under the data (GH r1 314 vs 370).
  -- They are compared after the talent, so every one is explained and taken.
  local taken, notTaken, gh1 = 0, {}, nil
  for _, r in ipairs(report) do
    if r.clientCost then
      if r.costFrom == "client" then taken = taken + 1 else notTaken[#notTaken + 1] = r.key .. r.rank end
    end
    if r.key == "GH" and r.rank == 1 then gh1 = r end
  end
  near("Holy dump: every game cost explained by data + talents (not taken: " .. table.concat(notTaken, " ") .. ")", #notTaken, 0)
  near("Holy dump: costs read", taken > 20 and 1 or 0, 1)
  near("GH r1: data with Improved Healing = 370 x 0.85", gh1.dataCost, 314.5, 1e-9)
  near("GH r1: with the talent, the game's cost (314; Litany's refund comes off after)", E.SPELLS.GH.ranks[1].cost * (1 - t.impHealing), 314, 1e-9)
  near("GH r1: kept without the talent (so it isn't applied twice)", E.SPELLS.GH.ranks[1].cost, 314 / 0.85, 1e-9)
  -- a rank close enough to be corrected counts as a match afterwards
  E.SPELLS = E.copy(E.GAME_SPELLS)
  local pom = E.copy(st); pom.healing = st.healing + 2
  local before = E.ModelTooltipHeal("POM", 1, pom, t, set)
  local rep2 = E.ApplyClientData({ { key = "POM", rank = 1, cost = 178, desc = "heals them for " .. math.floor(before - 1.5) .. " the next time" } }, pom, t, set)
  near("PoM 1.5 off: corrected, and then matches", (rep2[1].after and math.abs(rep2[1].after - rep2[1].client) <= 1) and 1 or 0, 1)
  near("PoM 1.5 off: still counted as off before correcting", math.abs(rep2[1].model - rep2[1].client) > 1 and 1 or 0, 1)
  E.SPELLS = E.copy(E.GAME_SPELLS)
end

print("-- Client tooltips, Holy priest at level 50 (20 Nov 2026, new gear, Warchief's Blessing)")
do
  local F = dofile("tests/fixture_client_holy50.lua")
  local t = E.Talents(F.talents)
  local st = { level = F.level, healing = F.healing, crit = F.crit, haste = 0.15, critMulti = 1.5,
               spirit = F.spirit, healingFromSpirit = F.spirit * t.spiritualGuidance }
  local set = E.copy(E.DEFAULTS.settings)
  local n, costsOff, fixedRanks, full, notMatched = 0, 0, 0, 0, {}
  -- From level 50 the game's tooltips leave downranking out: every rank shows full
  -- healing power (Renew 1: 310). Real heals still have it: Renew 1 ticked for 17 in
  -- game (x5 = 85), exactly the rule (12 levels after the rank's max level).
  local renew1 = E.ModelTooltipHeal("RENEW", 1, st, t, set)
  near("level 50: Renew 1 by the rule = 85, the 17-a-tick measured in game", renew1, 85, 0.01)
  -- Prayer of Mending is the one rank that isn't exact without correcting: 0.4-0.8% either
  -- way across three dumps (Shadow 49: model 257.0 vs 259; Holy 49: 285.4 vs 287; Holy 50:
  -- 272.2 vs 271). Cause unknown; its base heal is taken from the game.
  near("level 50: PoM within 1% before correcting (271)", E.ModelTooltipHeal("POM", 1, st, t, set), 271, 0.01)
  local report = E.ApplyClientData(F.spells, st, t, set)
  for _, r in ipairs(report) do
    if r.client then
      n = n + 1
      local now = math.abs(r.model - r.client) <= 1 or (r.after and math.abs(r.after - r.client) <= 1)
      if not now then notMatched[#notMatched + 1] = string.format("%s%d %.1f/%.1f", r.key, r.rank, r.client, r.after or r.model) end
      if r.tooltipFull then fixedRanks = fixedRanks + 1; if r.rulePower < 1 then full = full + 1 end end
    end
    if r.clientCost and r.costFrom ~= "client" then costsOff = costsOff + 1; print("     cost not taken: " .. r.key .. r.rank) end
    if r.key == "POM" then near("level 50: PoM after correcting matches 271", r.after, 271, 1 / 271) end
  end
  near("level 50: every tooltip explained (" .. n .. "; off: " .. table.concat(notMatched, " ") .. ")", #notMatched, 0)
  near("level 50: the 19 downranked ranks' tooltips leave the penalty out", fixedRanks, 19)
  near("level 50: ... and the model keeps the penalty for all of them", full, 19)
  -- (5 ticks of a rounded 17: anything from 82.5 to 87.5)
  near("level 50: Renew 1 still heals 85 after reading the game (17 a tick)", E.ModelTooltipHeal("RENEW", 1, st, t, set), 85, 2.5 / 85)
  local rk = E.SpellRanks("RENEW", st, t, set)
  near("level 50: the spell overview shows Renew 1 at 10% of healing power", rk[#rk].power, 0.1, 1e-9)
  local best = 0
  for _, r in ipairs(rk) do if r.best then best = r.rank end end
  near("level 50: Renew's most efficient rank is a high one, not rank 1", best >= 6 and 1 or 0, 1)
  near("level 50: every game cost explained by data + talents", costsOff, 0)
  E.SPELLS = E.copy(E.GAME_SPELLS)

  -- Cast times as the game gave them in that dump (ms; 15% haste, Divine Fury 5/5 on
  -- Heal and Greater Heal): with both taken back out, every one is the data's.
  local CAST = { FLASH = 1304, GH = 2174, HEAL = 2174, LESSER = { 1304, 1739, 2174 }, POH = 2609 }
  local spells = {}
  for _, c in ipairs(F.spells) do
    local ms = CAST[c.key]; if type(ms) == "table" then ms = ms[c.rank] end
    spells[#spells + 1] = { key = c.key, rank = c.rank, cost = c.cost, desc = c.desc, castTime = ms or 0 }
  end
  near("level 50: Divine Fury 5/5 = 0.5 s", t.divineFury, 0.5, 1e-9)
  local castOff, castRead = {}, 0
  for _, r in ipairs(E.ApplyClientData(spells, st, t, set)) do
    if r.clientCast then
      castRead = castRead + 1
      if r.castFrom ~= "client" or E.SPELLS[r.key].ranks[r.rank].cast ~= E.GAME_SPELLS[r.key].ranks[r.rank].cast then
        castOff[#castOff + 1] = r.key .. r.rank
      end
    end
  end
  near("level 50: cast times read (Flash, Heal, Greater Heal, Lesser Heal, Prayer of Healing)", castRead > 10 and 1 or 0, 1)
  near("level 50: every game cast time is the data's once haste and Divine Fury are out (off: " .. table.concat(castOff, " ") .. ")", #castOff, 0)

  -- A patch: every Flash Heal rank heals 20% more, costs 20% more, casts in 1.3 s.
  -- All of it is taken, no warning (the rule for low ranks still applies).
  local function patched(mult, castMs, onlyRank)
    local out = {}
    for _, c in ipairs(spells) do
      local d = E.copy(c)
      if c.key == "FLASH" and (not onlyRank or c.rank == onlyRank) then
        local a, b = c.desc:match("for ([%d,]+) to ([%d,]+)")
        local mid = (tonumber((a:gsub(",", ""))) + tonumber((b:gsub(",", "")))) / 2 * mult
        d.desc = string.format("Heals a friendly target for %d to %d.", math.floor(mid - 10), math.floor(mid - 10) + 20)
        d.cost = math.floor(c.cost * mult + 0.5)
        d.castTime = castMs
      end
      out[#out + 1] = d
    end
    return out
  end
  local function flashTop(rep)
    for _, r in ipairs(rep) do if r.key == "FLASH" and r.rank == E.MaxRank("FLASH", st.level, nil, set) then return r end end
  end
  local top = flashTop(E.ApplyClientData(patched(1.2, math.floor(1300 / 1.15 + 0.5)), st, t, set))
  near("patch: Flash Heal +20% is taken", top.after, top.client, 1)
  near("patch: ... from the game, no warning", top.baseFrom == "client" and top.costFrom == "client" and 1 or 0, 1)
  near("patch: Flash Heal's new cast time (1.3 s) is taken", E.SPELLS.FLASH.ranks[top.rank].cast, 1.3, 1e-9)

  -- The same jump later in one session is a temporary effect: the first reading stays.
  local seen = {}
  E.ApplyClientData(spells, st, t, set, seen)
  local first = E.SPELLS.FLASH.ranks[top.rank].base
  local firstCost = E.SPELLS.FLASH.ranks[top.rank].cost
  top = flashTop(E.ApplyClientData(patched(1.2, 1304), st, t, set, seen))
  near("session: a heal 20% up for a moment isn't taken", E.SPELLS.FLASH.ranks[top.rank].base, first, 1e-9)
  near("session: ... nor a cost 20% up", E.SPELLS.FLASH.ranks[top.rank].cost, firstCost, 1e-9)
  near("session: ... the first reading is used", top.baseFrom == "earlier" and top.costFrom == "earlier" and 1 or 0, 1)
  -- Inner Focus: cost 0 says nothing; the session's reading is used
  local free = E.copy(spells)
  for _, c in ipairs(free) do c.cost = 0 end
  E.ApplyClientData(free, st, t, set, seen)
  near("session: a free cast (Inner Focus) keeps the cost read before", E.SPELLS.FLASH.ranks[top.rank].cost, firstCost, 1e-9)
  -- A first reading taken under a buff: the real number is held back at first, and
  -- becomes the rank's own once it has stayed for E.HOLD seconds.
  local seen2 = {}
  E.ApplyClientData(patched(1.2, 1304), st, t, set, seen2, 1000)        -- buffed at login
  top = flashTop(E.ApplyClientData(spells, st, t, set, seen2, 1010))   -- the buff is over
  near("buffed login: the real reading is held back at first", top.baseFrom == "earlier" and 1 or 0, 1)
  top = flashTop(E.ApplyClientData(spells, st, t, set, seen2, 1010 + E.HOLD - 1))
  near("buffed login: ... still held just before the hold is over", top.baseFrom == "earlier" and 1 or 0, 1)
  top = flashTop(E.ApplyClientData(spells, st, t, set, seen2, 1010 + E.HOLD))
  near("buffed login: ... taken once it has stayed " .. E.HOLD .. " s", top.baseFrom == "client" and top.costFrom == "client" and 1 or 0, 1)
  near("buffed login: ... and the model heals what the game says", top.after, top.client, 1)
  -- a lasting change mid-session (a set bonus that cuts the cost) is taken after the hold too
  local cheaper = E.copy(spells)
  for _, c in ipairs(cheaper) do if c.key == "FLASH" then c.cost = math.floor(c.cost * 0.9 + 0.5) end end
  top = flashTop(E.ApplyClientData(cheaper, st, t, set, seen2, 2000))
  near("lasting change: held at first", top.costFrom == "earlier" and 1 or 0, 1)
  top = flashTop(E.ApplyClientData(cheaper, st, t, set, seen2, 2000 + E.HOLD))
  near("lasting change: taken after " .. E.HOLD .. " s", top.costFrom == "client" and 1 or 0, 1)
  -- a reading that keeps moving (one buff, then another) restarts the hold
  local seen3 = {}
  E.ApplyClientData(spells, st, t, set, seen3, 0)
  E.ApplyClientData(patched(1.2, 1304), st, t, set, seen3, 10)
  top = flashTop(E.ApplyClientData(patched(1.4, 1304), st, t, set, seen3, 10 + E.HOLD))
  near("a different jump restarts the hold", top.baseFrom == "earlier" and 1 or 0, 1)
  -- a new level starts over
  local st51 = E.copy(st); st51.level = 51
  top = flashTop(E.ApplyClientData(patched(1.2, 1304), st51, t, set, seen))
  near("session: after a level-up the new reading is taken", top.baseFrom == "client" and 1 or 0, 1)

  -- A misread (a tooltip whose wording changed into another number): the data stays, quietly.
  top = flashTop(E.ApplyClientData(patched(5, 1304), st, t, set))
  near("misread: a heal 5x the data's is not taken", top.base, top.dataBase, 1e-9)
  near("misread: ... and is reported as one (/hm check)", top.baseFrom == "misread" and 1 or 0, 1)
  -- one rank patched far off doesn't flip how the client draws its tooltips
  local rep = E.ApplyClientData(patched(1.3, 1304, 1), st, t, set)
  local fullRanks = 0
  for _, r in ipairs(rep) do if r.tooltipFull then fullRanks = fullRanks + 1 end end
  near("one odd rank: the other downranked tooltips still read at full power", fullRanks, 19)
  E.SPELLS = E.copy(E.GAME_SPELLS)
end

print("-- Client tooltips, Shadow priest at level 50 (21 Nov 2026): low ranks shown WITH the penalty")
do
  local F = dofile("tests/fixture_client_shadow50.lua")
  local t = E.Talents(F.talents)
  local st = { level = F.level, healing = F.healing, crit = F.crit, haste = F.haste, critMulti = 1.5,
               spirit = F.spirit, healingFromSpirit = 0 }
  local set = E.copy(E.DEFAULTS.settings)
  -- intellect to crit at 50, measured again: 0.8% + 216 x 0.0208 = 5.2928%, as the game said
  near("shadow 50: crit = 0.8% + 216 int x the measured 0.0208%", 0.8 + F.int * E.CritPerInt(50), F.crit * 100, 1e-6)
  local within, full, costs, casts, n = 0, 0, 0, 0, 0
  for _, r in ipairs(E.ApplyClientData(F.spells, st, t, set)) do
    if r.client then
      n = n + 1
      if math.abs(r.client - r.model) <= 1 then within = within + 1 end
      if r.tooltipFull then full = full + 1 end
    end
    if r.costFrom == "client" and math.abs(r.clientCost - r.dataCost) < 0.5 then costs = costs + 1 end
    if r.clientCast == nil or (r.castFrom == "client" and r.clientCast == r.dataCast) then casts = casts + 1 end
  end
  near("shadow 50: every tooltip read (" .. n .. " ranks)", n, #F.spells)
  near("shadow 50: the game data alone heals what every tooltip says, within 1", within, n)
  near("shadow 50: the tooltips show the penalty, and Holy Math sees that (no rank read at full power)", full, 0)
  near("shadow 50: every cost is the game data's", costs, #F.spells)
  near("shadow 50: every cast time is the game data's", casts, #F.spells)
  local rk = E.SpellRanks("RENEW", st, t, set)
  near("shadow 50: Renew 1 gets 10% of healing power", rk[#rk].power, 0.1, 1e-9)
  E.SPELLS = E.copy(E.GAME_SPELLS)
end

print("-- Game data vs the client: mana regen")
do
  -- 20 Nov dump: GetManaRegen 32.826 out of combat, 4.201 while casting (both include mp5), spirit 179
  local fromSpirit = 32.826 - 4.201
  near("regen from spirit = 6.25 + spirit/8 (per second)", E.DATA.regen.base + 179 * E.DATA.regen.perSpirit, fromSpirit, 1e-4)
end

print("-- Game data: shape")
do
  near("Renew has 10 ranks", #E.GAME_SPELLS.RENEW.ranks, 10)
  near("Greater Heal has 5 ranks", #E.GAME_SPELLS.GH.ranks, 5)
  near("Prayer of Healing has 5 ranks", #E.GAME_SPELLS.POH.ranks, 5)
  near("no Binding Heal in the game data", E.GAME_SPELLS.BH and 1 or 0, 0)
  near("Holy Nova heal coefficient (sheet 0.24)", E.GAME_SPELLS.NOVA.ranks[6].coeff, 0.107)
  near("Spiritual Healing 3/3 = +10% (sheet 9%)", E.Talents({ spiritualHealing = 3 }).spiritualHealing, 1.10)
  near("Greater Heal r2 base at level 49 = 1099 + 3 x 5.8", E.BaseAt(E.GAME_SPELLS.GH.ranks[2], 49), 1116.4, 1e-9)
  -- the talent's tooltip in game: 5% of the base cost at 1/2 (21 Nov 2026), so 10% at 2/2
  near("Litany of Light 1/2 = 5% of the base cost back", E.Talents({ litanyOfLight = 1 }).litanyRefund, 0.05, 1e-12)
  near("Litany of Light 2/2 = 10% of the base cost back", E.Talents({ litanyOfLight = 2 }).litanyRefund, 0.10, 1e-12)
end

print("-- Intellect -> crit by level (game data at 60, measured at 49 and 50)")
do
  near("level 60: game data 0.0168% per int", E.CritPerInt(60), 0.0168, 1e-9)
  near("level 50: measured 0.0208% per int", E.CritPerInt(50), 0.0208, 1e-9)
  near("level 49: measured 0.0213% per int", E.CritPerInt(49), 0.0213, 1e-9)
  near("level 55: halfway between 50 and 60", E.CritPerInt(55), 0.0188, 1e-9)
  near("level 48: extended along 49-50", E.CritPerInt(48), 0.0218, 1e-9)
  -- the two dumps: no crit on gear, Holy Specialization 3/3 (3%) added on top
  local f49, f50 = dofile("tests/fixture_client_holy.lua"), dofile("tests/fixture_client_holy50.lua")
  near("dump at 49 fits 0.8% + 204 int", f49.crit - 0.03, (0.8 + 204 * E.CritPerInt(49)) / 100, 1e-6)
  near("dump at 50 fits 0.8% + 208 int", f50.crit - 0.03, (0.8 + 208 * E.CritPerInt(50)) / 100, 1e-6)
  local inp = E.copy(E.DEFAULTS); inp.settings.rules = E.RULES
  inp.level = 50
  near("stat values use it: +1 int at 50", E.StatDelta(inp, "int").crit,
       E.Multipliers(inp).int * 0.0208 / 100, 1e-12)
  inp.settings.rules = E.SHEET_RULES
  near("the sheet's rule stays 1/60", E.Multipliers(inp).critPctPerInt, 1 / 60, 1e-12)
end

print("-- The Math tab adds up to what the window shows (level 50 dump: calibrated ranks)")
do
  assert(loadfile("Models/PriestMath.lua"))(nil, { Models = { PRIEST = E } })
  local F = dofile("tests/fixture_client_holy50.lua")
  local t = E.Talents(F.talents)
  -- the 22:49 dump: 208 int, 4006 mana, regen 30.701 / 4.201 per second, no Meditation
  local st = { level = F.level, healing = F.healing, crit = F.crit, haste = 0.15, critMulti = 1.5,
               spirit = F.spirit, healingFromSpirit = F.spirit * t.spiritualGuidance, int = 208,
               manaPool = 4006, oocRegen = 26.5 * 5, combatRegen = 0, mp5 = 4.201 * 5 }
  local input = { level = F.level, talents = F.talents, buffs = {}, consumables = {}, race = { troll = true },
                  settings = E.copy(E.DEFAULTS.settings), regenPerSpirit = 5 * E.DATA.regen.perSpirit }
  input.settings.fightLength = 120
  local set = input.settings
  local report = E.ApplyClientData(F.spells, st, t, set)
  local w = E.Weights("renew", st, input)
  local S = { st = st, t = t, input = input, weights = w, rotation = "renew",
              info = { client = report, how = { critParts = { client = F.crit - 0.03, talent = 0.03, holySpec = 3,
                       perInt = E.CritPerInt(50), perIntFrom = "measured in game" } } } }
  S.spells = E.SpellTable(st, t, set)
  local rows, check = E.MathPage(S)
  near("math: mana parts add up to the mana budget", check.fight.mana, E.ManaBudget(st, t, set), 1e-9)
  near("math: the fight's lines add up to its healing", check.fight.eff, w.base.eff, 1e-9)
  near("math: ... and to the HPS on the Settings tab", check.fight.ehps, w.base.ehps, 1e-9)
  -- one section per spell the fight casts, each = its line in the fight
  local function stepsMatch(X, ck)
    local n, good, ohPWS = 0, 0, X.input.settings.overheal.PWS or 0
    for _, sc in ipairs(ck.spells) do
      local s2 = sc.step
      n = n + 1
      local want = s2.perCast * (1 - (s2.overheal or 0)) + s2.aegis * (1 - ohPWS)
      if math.abs(sc.cost - s2.cost) < 1e-9 and math.abs(sc.heal - want) < 1e-9 then good = good + 1 end
    end
    local steps = 0
    for _, s2 in ipairs(X.weights.base.steps) do if s2.enabled and s2.casts > 0.01 then steps = steps + 1 end end
    return n == steps and good == n, n
  end
  local okSteps, nSteps = stepsMatch(S, check)
  near("math: a section for each of the fight's " .. nSteps .. " spells, its mana and heal = its fight line", okSteps and 1 or 0, 1)
  local bad, ranks, note = 0, 0, false
  for _, sr in ipairs(S.spells) do
    for r = 1, sr.top do
      local rws, c = E.MathPage(S, sr.key, r)
      local heal, cost = E.CastValue(sr.key, r, st, t, set)
      ranks = ranks + 1
      if not (c.spell.key == sr.key and c.spell.rank == r) then bad = bad + 1
      elseif not c.spell.step and (math.abs(c.spell.heal - heal) > 1e-9 or math.abs(c.spell.cost - cost) > 1e-9) then bad = bad + 1 end
      for _, row in ipairs(rws) do
        if not (row.head or row.note) and not (row[1] and row[2] and row[3] and row[4]) then bad = bad + 1 end
        if row.note and row.note:find("tooltip shows this rank at full power") and sr.key == "RENEW" and r == 1 then note = true end
      end
    end
  end
  near("math: every rank you pick gets its section; outside the fight = Your spells (" .. ranks .. " ranks)", bad, 0)
  -- Your spells, the sheet's first section: each spell you know with its overheal (a
  -- setting for every rank); open ones list all their ranks, one the most efficient
  local all = {}
  for _, sr in ipairs(S.spells) do all[sr.key] = true end
  local rws = E.MathPage(S, nil, nil, all)
  near("math: Your spells comes first", rws[1].head == "Your spells" and 1 or 0, 1)
  local spellsSeen, rankRows, bestPer, ohOK, valuesOK = 0, 0, {}, 0, 0
  for _, row in ipairs(rws) do
    if row.tbl == "spell" then
      spellsSeen = spellsSeen + 1
      local e = row.edit
      if e and e.setting[1] == "overheal" and e.setting[2] == row.spell.key and e.raw == (set.overheal[row.spell.key] or 0) then ohOK = ohOK + 1 end
    elseif row.tbl == "rank" then
      rankRows = rankRows + 1
      local heal, cost = E.CastValue(row.spell.key, row.rank.rank, st, t, set)
      if math.abs(row.rank.heal - heal) < 1e-9 and math.abs(row.rank.cost - cost) < 1e-9 then valuesOK = valuesOK + 1 end
      if row.rank.best then bestPer[row.spell.key] = (bestPer[row.spell.key] or 0) + 1 end
    end
  end
  local oneBest = 0
  for _, n in pairs(bestPer) do if n == 1 then oneBest = oneBest + 1 end end
  near("math: Your spells lists every spell you know (" .. #S.spells .. ")", spellsSeen, #S.spells)
  near("math: ... each with its overheal as a setting for the whole spell", ohOK, #S.spells)
  near("math: ... open, every rank of every spell (" .. ranks .. ")", rankRows, ranks)
  near("math: ... each rank's heal and mana as the model works them out", valuesOK, ranks)
  near("math: ... exactly one most efficient rank per spell", oneBest, #S.spells)
  local folded = 0
  for _, row in ipairs((E.MathPage(S))) do if row.tbl == "rank" then folded = folded + 1 end end
  near("math: ... folded up, no rank lines", folded, 0)
  near("math: Renew 1 says its tooltip leaves downranking out", note and 1 or 0, 1)
  local _, gone = E.MathPage(S, "SMITE", 1)
  near("math: a spell you don't know: just the fight's spells", (gone.spell == gone.spells[1] and #gone.spells == nSteps) and 1 or 0, 1)

  -- Your own values (typed over on the Math tab), the way Core.lua applies them
  local function withValues(ov)
    local inp = E.copy(input)
    inp.settings.overrides = ov
    local t2 = E.Talents(inp.talents, nil, ov)
    local st2 = E.ApplyStatOverrides(st, ov)
    local S2 = { st = st2, t = t2, input = inp, rotation = "renew", info = S.info, weights = E.Weights("renew", st2, inp) }
    S2.spells = E.SpellTable(st2, t2, inp.settings)
    return S2
  end
  local function sig(X, key, rank)   -- everything a value can move
    local _, c = E.MathPage(X, key, rank)
    local s = c.fight.ehps + c.spell.heal + c.spell.cost * 7 + c.spell.time * 13
    for _, k in ipairs(E.WEIGHT_STATS) do s = s + (X.weights[k] or 0) * 3 end
    return s, c
  end
  near("values: none = exactly as before", sig(withValues({}), "GH", 4), sig(S, "GH", 4), 0)
  -- every editable cell on these pages: typed over, it moves the model, the
  -- page shows it as yours with the old value kept, and the page still adds up
  local moved, shown, checked, stillAdds = 0, 0, 0, 0
  for _, pick in ipairs({ { "RENEW", 8 }, { "GH", 4 }, { "POM", 1 }, { "RENEW", 1 } }) do
    local rws = E.MathPage(S, pick[1], pick[2])
    local before = sig(S, pick[1], pick[2])
    for _, row in ipairs(rws) do
      local e = row.edit
      if e and e.id then
        checked = checked + 1
        local v = e.raw * 1.2 + 0.01
        if e.unit == "pct" or e.unit == "pct0" then v = math.min(1, e.raw + 0.05) end
        if e.id == "stat.critMulti" then v = 2 end
        local X = withValues({ [e.id] = v })
        local after, c = sig(X, pick[1], pick[2])
        if math.abs(after - before) > 1e-6 then moved = moved + 1 else print("   did not move: " .. e.id) end
        if math.abs(c.fight.eff - X.weights.base.eff) < 1e-6 then stillAdds = stillAdds + 1 end
        for _, r2 in ipairs((E.MathPage(X, pick[1], pick[2]))) do
          if r2.edit and r2.edit.id == e.id and r2[4] == "you" and math.abs(r2.edit.raw - v) < 1e-9
             and math.abs(r2.edit.orig - e.raw) < 1e-9 then shown = shown + 1; break end
        end
      end
    end
  end
  near("values: " .. checked .. " editable cells, each moves the model", moved, checked)
  near("values: ... shows as yours, the old value kept", shown, checked)
  near("values: ... and the fight still adds up", stillAdds, checked)
  -- every editable cell at both ends of what it accepts: nothing goes negative or breaks
  local ids, seen = {}, {}
  for _, pick in ipairs({ { "RENEW", 8 }, { "GH", 4 }, { "POM", 1 }, { "RENEW", 1 }, { "FLASH", 6 } }) do
    for _, row in ipairs((E.MathPage(S, pick[1], pick[2]))) do
      if row.edit and row.edit.id and not seen[row.edit.id] then seen[row.edit.id] = true; ids[#ids + 1] = row.edit.id end
    end
  end
  for _, extra in ipairs({ "talent.mentalAgility", "talent.impHealing", "talent.litany", "talent.daMulti", "talent.divineFury" }) do
    if not seen[extra] then ids[#ids + 1] = extra end
  end
  local sane, tried = 0, 0
  local function fine(x) return type(x) == "number" and x == x and x ~= math.huge and x >= 0 end
  for _, id in ipairs(ids) do
    local lo, hi = E.OverrideRange(id)
    for _, v in ipairs({ lo, hi }) do
      tried = tried + 1
      local ok2, X2 = pcall(withValues, { [id] = v })
      local good = ok2 and X2.weights and fine(X2.weights.base.ehps)
      if good then
        for _, k in ipairs(E.WEIGHT_STATS) do if X2.weights[k] ~= X2.weights[k] then good = false end end
        for _, sr in ipairs(X2.spells) do
          local h, c, tm = E.CastValue(sr.key, sr.top, X2.st, X2.t, X2.input.settings)
          if not (fine(h) and c >= 1 and tm > 0) then good = false end
        end
        local _, ck = E.MathPage(X2)
        if not (ck.fight and math.abs(ck.fight.eff - X2.weights.base.eff) < 1e-6 and ck.fight.worst < 1e-6) then good = false end
      end
      if good then sane = sane + 1 else print("   breaks at the end of its range: " .. id .. " = " .. tostring(v)) end
    end
  end
  near("values: " .. #ids .. " cells at both ends of their range: costs >= 1, heals >= 0, the page adds up", sane, tried)
  -- every cost cut at its top at once still leaves a cost
  local cuts = withValues({ ["talent.mentalAgility"] = 0.9, ["talent.impHealing"] = 0.9, ["talent.litany"] = 0.9, ["talent.litanyRefund"] = 1 })
  local _, pc = E.CastValue("POM", 1, cuts.st, cuts.t, cuts.input.settings)
  near("values: all cost cuts at once: a cost of at least 1", pc, 1)
  near("values: a spell rank's own data can't be typed over", E.OverrideOK("spell.RENEW.8.base", 600) and 0 or 1, 1)
  -- the share of regen while casting reaches spirit's worth too
  local share0 = withValues({ ["stat.castingShare"] = 0 })
  local share1 = withValues({ ["stat.castingShare"] = 1 })
  near("values: regen while casting typed: spirit's regen while casting follows",
       E.StatDelta(share1.input, "spirit").combatRegen, E.StatDelta(share1.input, "spirit").oocRegen, 1e-12)
  near("values: ... and spirit is worth more with all of it", share1.weights.spirit > share0.weights.spirit and 1 or 0, 1)

  -- item tooltips (E.Compare) and stat values follow a value
  local X = withValues({ ["stat.critMulti"] = 2 })
  near("values: crit x2 raises the HPS", X.weights.base.ehps > S.weights.base.ehps and 1 or 0, 1)
  near("values: ... and the worth of crit", X.weights.crit > S.weights.crit and 1 or 0, 1)
  local diff = { crit = 1 }
  near("values: ... and an item with crit (tooltips)",
       E.Compare("renew", X.st, X.input, diff) > E.Compare("renew", st, input, diff) and 1 or 0, 1)
  X = withValues({ ["stat.critPerInt"] = 0.05 })
  near("values: intellect to crit moves intellect's worth", X.weights.int > S.weights.int and 1 or 0, 1)
  -- regen while casting follows regen from spirit, unless its share is yours too
  local share = st.oocRegen > 0 and st.combatRegen / st.oocRegen or 0
  local R = E.ApplyStatOverrides({ oocRegen = 100, combatRegen = 50 }, { ["stat.oocRegen"] = 200 })
  near("values: regen while casting follows regen", R.combatRegen, 100, 1e-12)
  R = E.ApplyStatOverrides({ oocRegen = 100, combatRegen = 50 }, { ["stat.oocRegen"] = 200, ["stat.castingShare"] = 0.25 })
  near("values: ... unless its share is typed too", R.combatRegen, 50, 1e-12)
  near("values: ... and the old values are kept", (R.orig.oocRegen == 100 and R.orig.combatRegen == 50) and 1 or 0, 1)
  -- a bad saved value is left out, never breaks anything
  local bad = { ["stat.crit"] = 7, ["stat.healing"] = "lots", ["spell.RENEW.8.cost"] = 0, ["talent.x y"] = 1,
                ["stat.nope"] = 1, ["spell.RENEW.8.zap"] = 1, [3] = 1 }
  near("values: bad saved values are ignored", sig(withValues(bad), "RENEW", 8), sig(S, "RENEW", 8), 0)
  local Y = withValues({ ["stat.healingFromSpirit"] = 99999 })
  near("values: Prayer of Mending's healing power can't go below 0", E.HealingFor("POM", Y.st), 0, 0)
  -- what you type is read the way it is shown
  local reads = { { "pct", "18.8%", 0.188 }, { "pct", "18.8", 0.188 }, { "bonus", "+15%", 1.15 }, { "mult", "x2", 2 },
                  { "sec", "2.5 s", 2.5 }, { "int", "1,234", 1234 }, { "regen", "132.5 per 5 s", 132.5 },
                  { "perInt", "0.0208%", 0.0208 }, { "coef", "0.4286", 0.4286 } }
  local ok = 0
  for _, r in ipairs(reads) do
    local v = E.MathParse(r[1], r[2])
    if v and math.abs(v - r[3]) < 1e-12 then ok = ok + 1 else print("   misread: " .. r[1] .. " '" .. r[2] .. "'") end
  end
  near("values: typed text is read in its unit", ok, #reads)
  near("values: nonsense is not read", E.MathParse("int", "abc") == nil and 1 or 0, 1)
  ok = 0
  for unit in pairs(E.MATH_UNITS) do
    local v = unit == "bonus" and 1.15 or 0.375
    if math.abs(E.MathParse(unit, E.MathEditText(unit, v)) - v) < 1e-9 then ok = ok + 1 end
  end
  local units = 0
  for _ in pairs(E.MATH_UNITS) do units = units + 1 end
  near("values: the edit box text reads back as the same number", ok, units)
  -- every playstyle, and a Discipline priest (Divine Aegis, Renewed Hope, Penance,
  -- Inner Focus): each fight line's printed terms add up to its value
  local disc = E.copy(E.DEFAULTS)
  disc.settings.rules = E.RULES
  disc.settings.fightLength = 120
  disc.talents.divineAegis, disc.talents.penance, disc.talents.renewedHope = 3, 1, 5
  local dst = E.Derive(disc)
  local dt = E.Talents(disc.talents)
  E.SPELLS = E.copy(E.GAME_SPELLS)
  for _, case in ipairs({ { "level 50", S }, { "Discipline 60", { st = dst, t = dt, input = disc, info = { client = {}, how = {} } } } }) do
    local CS = case[2]
    for key, rot in pairs(E.ROTATIONS) do
      if not rot.sheetOnly and (not rot.requires or (CS.t[rot.requires] or 0) > 0) then
        CS.rotation, CS.weights = key, E.Weights(key, CS.st, CS.input)
        CS.spells = E.SpellTable(CS.st, CS.t, CS.input.settings)
        if CS.weights then
          local _, ck = E.MathPage(CS)
          near("math, " .. case[1] .. ", " .. rot.name .. ": lines add up", ck.fight.eff, CS.weights.base.eff, 1e-9)
          near("math, " .. case[1] .. ", " .. rot.name .. ": each line's terms = its value", ck.fight.worst, 0, 1e-6)
          near("math, " .. case[1] .. ", " .. rot.name .. ": each spell's section = its fight line", stepsMatch(CS, ck) and 1 or 0, 1)
        end
      end
    end
  end
  -- the Discipline priest with crits for x2 (typed over): every playstyle still adds up
  local ov = { ["stat.critMulti"] = 2, ["talent.daMulti"] = 0.5 }
  local dinp = E.copy(disc)
  dinp.settings.overrides = ov
  local DS = { st = E.ApplyStatOverrides(dst, ov), t = E.Talents(dinp.talents, dinp.settings.rules, ov), input = dinp,
               info = { client = {}, how = {} } }
  for key, rot in pairs(E.ROTATIONS) do
    if not rot.sheetOnly and (not rot.requires or (DS.t[rot.requires] or 0) > 0) then
      DS.rotation, DS.weights = key, E.Weights(key, DS.st, DS.input)
      DS.spells = E.SpellTable(DS.st, DS.t, DS.input.settings)
      if DS.weights then
        local _, ck = E.MathPage(DS)
        local plain = E.Weights(key, dst, disc)
        near("values, Discipline 60, crit x2, " .. rot.name .. ": adds up, terms = values, sections = fight lines",
             (math.abs(ck.fight.eff - DS.weights.base.eff) < 1e-6 and ck.fight.worst < 1e-6 and stepsMatch(DS, ck)) and 1 or 0, 1)
        near("values, Discipline 60, crit x2, " .. rot.name .. ": heals more", DS.weights.base.ehps > plain.base.ehps and 1 or 0, 1)
      end
    end
  end
  E.SPELLS = E.copy(E.GAME_SPELLS)
end

print("-- Potions: your list, shared cooldowns, mana, healing, time asleep")
do
  local inp = E.copy(E.DEFAULTS); inp.settings.rules = E.RULES; inp.level = 60
  local st = E.Derive(inp)
  local t = E.Talents(inp.talents, inp.settings.rules)
  local base = E.copy(inp.settings)
  base.fightLength = 300
  local function with(list, fl)
    local s = E.copy(base); s.potions = list; s.fightLength = fl or 300
    return s
  end
  local function plan(list, fl) return E.PotionPlan(st, with(list, fl)) end
  local ALL = E.POTION_ALL

  near("fits: 300 s on a 2 min cooldown (0:15, 2:15, 4:15)", E.PotionFits(300, "potion"), 3)
  near("fits: 120 s", E.PotionFits(120, "potion"), 1)
  near("Major Mana, as many as fit: 3 x 1800", plan({ { key = "majorMana", n = ALL } }).mana, 5400)
  local p = plan({ { key = "majorMenders", n = 1 }, { key = "majorMana", n = ALL } })
  near("Mender's 1, Major Mana the rest: 2 x 1800 mana", p.mana, 3600)
  near("... Mender's: +88 for 30 s of 300 s = +8.8 healing power", p.healing, 8.8)
  near("2 + 2 on a cooldown that fits 3: 2 x 1800 + 1 x 1200 (the list's order)",
       plan({ { key = "majorMana", n = 2 }, { key = "superiorMana", n = 2 } }).mana, 4800)
  near("runes have their own cooldown: 3 x 1800 + 3 x 1200",
       plan({ { key = "majorMana", n = ALL }, { key = "demonicRune", n = ALL } }).mana, 9000)
  near("Restored Mana Potion: 20% of your max mana", plan({ { key = "restoredMana", n = 1 } }).mana, 0.2 * st.manaPool)
  near("a Mender's Potion in a 20 s fight: up the whole fight", plan({ { key = "majorMenders", n = 1 } }, 20).healing, 88)
  local low = {}
  for k, v in pairs(st) do low[k] = v end
  low.level = 40
  near("too low a level for it: none", E.PotionPlan(low, with({ { key = "majorMana", n = ALL } })).count, 0)
  local sheet = E.copy(base); sheet.potions = nil
  near("no list (the sheet's switches): 1800 per potion, as before", E.PotionPlan(st, sheet).mana, 5400)

  -- in the fight: a Mender's Potion heals exactly like its average healing power
  local stH = {}
  for k, v in pairs(st) do stH[k] = v end
  stH.healing = st.healing + 8.8
  local rH = E.Rotation("renew", stH, t, with({}))
  local rM = E.Rotation("renew", st, t, with({ { key = "majorMenders", n = 1 } }))
  near("Mender's in the fight = +8.8 healing power all fight", rM.ehps, rH.ehps, 1e-9)
  -- Dreamless Sleep: the same mana as a plain 2100 potion, but 12 s less to cast
  E.POTION_BY_KEY.test2100 = { key = "test2100", name = "test", group = "potion", mana = 2100, lvl = 1, text = "" }
  local rD = E.Rotation("renew", st, t, with({ { key = "greaterDreamless", n = 1 } }, 600))
  local rP = E.Rotation("renew", st, t, with({ { key = "test2100", n = 1 } }, 600))
  E.POTION_BY_KEY.test2100 = nil
  near("Dreamless Sleep: same mana as a 2100 potion", rD.mana, rP.mana, 1e-9)
  near("... but asleep 12 s: heals less", rD.ehps < rP.ehps and 1 or 0, 1)

  -- the best mix of your list: no split of the cooldowns heals more
  local list = { { key = "majorMenders", n = 0 }, { key = "majorMana", n = ALL } }
  for _, fl in ipairs({ 60, 300, 600 }) do
    local best, hps = E.BestPotions("renew", st, t, with(list, fl))
    local fits, top = E.PotionFits(fl, "potion"), -math.huge
    for m = 0, fits do
      local r = E.Rotation("renew", st, t, with({ { key = "majorMenders", n = m }, { key = "majorMana", n = fits - m } }, fl))
      top = math.max(top, r.ehps)
    end
    near(string.format("best mix, %d s fight: as good as every split (%d Mender's)", fl, best[1].n), hps, top, 1e-6)
  end
  local short = E.BestPotions("renew", st, t, with(list, 60))
  near("a short fight with mana to spare: Mender's", short[1].n, 1)
  near("Major Mana Potion is worth something in a 5 min fight",
       (E.PotionValue("renew", st, t, with({}), "majorMana") or 0) > 0 and 1 or 0, 1)

  -- settings from before the list
  local m1 = { majorManaPotions = true }; E.MigratePotions(m1)
  near("old 'mana potion on cooldown' on: Major Mana as many as fit",
       (#m1.potions == 1 and m1.potions[1].key == "majorMana" and m1.potions[1].n == ALL and m1.majorManaPotions == nil) and 1 or 0, 1)
  local m2 = { majorManaPotions = false }; E.MigratePotions(m2)
  near("old switch off: no potions", #m2.potions, 0)
  local m3 = {}; E.MigratePotions(m3)
  near("no old switch saved (its default was on): Major Mana", #m3.potions, 1)
  local m4 = { potions = {} }
  near("a list already there is left alone", E.MigratePotions(m4) and 1 or 0, 0)

  -- the Math tab with potions: each spell's section = its fight line (healing power included)
  assert(loadfile("Models/PriestMath.lua"))(nil, { Models = { PRIEST = E } })
  local pinp = E.copy(inp); pinp.settings = with({ { key = "majorMenders", n = 1 }, { key = "majorMana", n = ALL } })
  pinp.settings.known = nil
  local PS = { st = st, t = t, input = pinp, rotation = "renew" }
  PS.weights = E.Weights("renew", st, pinp)
  PS.spells = E.SpellTable(st, t, pinp.settings)
  local rows, ck = E.MathPage(PS)
  local good, n = 0, 0
  for _, sc in ipairs(ck.spells) do
    local s2 = sc.step
    n = n + 1
    local want = s2.perCast * (1 - (s2.overheal or 0)) + s2.aegis * (1 - (pinp.settings.overheal.PWS or 0))
    if math.abs(sc.heal - want) < 1e-9 then good = good + 1 end
  end
  near("math with a Mender's Potion: each spell's section = its fight line", (n > 0 and good == n) and 1 or 0, 1)
  near("... and the fight adds up", (math.abs(ck.fight.eff - PS.weights.base.eff) < 1e-6 and ck.fight.worst < 1e-6) and 1 or 0, 1)
  local text = {}
  for _, r in ipairs(rows) do text[#text + 1] = (r[1] or r.note or r.head or "") .. " | " .. (r[2] or "") end
  text = table.concat(text, "\n")
  near("math shows each potion: Major Mana x2, Mender's healing",
       (text:find("Major Mana Potion | 2 x 1800") and text:find("Major Mender's Potion | %+88 healing for 30 s x 1, over 300 s")) and 1 or 0, 1)
end

print("-- Playstyles as blocks: built-ins as blocks, your own, edits, the export line")
do
  E.SPELLS = E.copy(E.GAME_SPELLS)
  local inp = E.copy(E.DEFAULTS)
  inp.settings.rules = E.RULES
  inp.settings.fightLength = 180
  local pst = E.Derive(inp)
  local pt = E.Talents(inp.talents)
  local pset = inp.settings
  local function ok(label, cond) near(label, cond and 1 or 0, 1) end
  local function eps(key, set2, t2) local r = E.Rotation(key, pst, t2 or pt, set2 or pset); return r and r.ehps end

  -- what "on cooldown" and "keep it up" mean, from the game data
  near("Prayer of Mending on cooldown: every 10 s", E.StepEvery({ spell = "POM", how = "cd" }), 10)
  near("Penance on cooldown: every 12 s", E.StepEvery({ spell = "PENANCE", how = "cd" }), 12)
  near("PW:Shield on cooldown on the tank: Weakened Soul, 15 s", E.StepEvery({ spell = "PWS", how = "cd", tank = true }), 15)
  near("PW:Shield on cooldown on anyone: its own 4 s", E.StepEvery({ spell = "PWS", how = "cd" }), 4)
  near("Renew kept up: every 15 s", E.StepEvery({ spell = "RENEW", how = "up" }), 15)
  near("twice a minute: every 30 s", E.StepEvery({ spell = "GH", how = "pm", n = 2 }), 30)
  ok("words: on cooldown, at most twice a minute, at most 20 times a minute, at most every 7.5 s",
     E.HowText({ how = "cd" }) == "on cooldown" and E.HowText({ how = "pm", n = 2 }) == "at most twice a minute"
     and E.HowText({ how = "pm", n = 20 }) == "at most 20 times a minute" and E.HowText({ how = "sec", n = 7.5 }) == "at most every 7.5 s")

  -- every built-in as blocks heals exactly what it does now, and survives the export line
  local same, valid, trips, n = 0, 0, 0, 0
  local custom = {}
  for key, rot in pairs(E.BUILTIN_ROTATIONS) do
    if not rot.sheetOnly then
      n = n + 1
      local def = E.PlaystyleFromRotation(rot)
      if not E.PlaystyleProblem(def) then valid = valid + 1 end
      local back = E.PlaystyleImport(E.PlaystyleExport(def))
      if back and E.PlaystyleExport(back) == E.PlaystyleExport(def) then trips = trips + 1 end
      custom["copy-" .. key] = back or def
    end
  end
  E.SetPlaystyles(custom, nil)
  -- which copies heal differently from their built-in ("key-" less, "key+" more)
  local function differs(set2, t2)
    local out = {}
    for key, rot in pairs(E.BUILTIN_ROTATIONS) do
      if not rot.sheetOnly then
        local a, b = eps(key, set2, t2), eps("copy-" .. key, set2, t2)
        if a and b and math.abs(a - b) > 1e-9 then out[#out + 1] = key .. (b < a and "-" or "+") end
      end
    end
    table.sort(out)
    return table.concat(out, ",")
  end
  local noInsp = E.copy(pset); noInsp.includeInspiration = false
  near("every built-in as blocks is a valid playstyle", valid, n)
  near("every built-in's export line reads back the same", trips, n)
  local d0 = differs(noInsp)
  ok("without Inspiration every built-in as blocks heals exactly as much (" .. d0 .. ")", d0 == "")
  -- with Inspiration: the two that shield the tank heal less as blocks. The built-ins
  -- count the shield for Inspiration as the sheet does; blocks count only heals that
  -- can crit (not a shield, not Renew's ticks)
  local d1 = differs()
  ok("with Inspiration only the shield playstyles' copies heal less (" .. d1 .. ")", d1 == "pwsTank-,rhTank-")
  -- with Renewed Hope: the game's rules give its crit only to heals on the tank, in a
  -- built-in as in a block, so the copies heal exactly as much
  local rhT = E.copy(inp.talents); rhT.renewedHope = 5; rhT.penance = 1
  local rt = E.Talents(rhT)
  local d2 = differs(noInsp, rt)
  ok("with Renewed Hope every built-in as blocks heals exactly as much (" .. d2 .. ")", d2 == "")

  -- the export line
  local line = "HM1:Renew + Inspiration;POM,b,cd,t;LESSER,2,20pm,t;GH,b,2pm,t;RENEW,b,fill"
  local def, err = E.PlaystyleImport(line)
  ok("the plan's example line imports (" .. tostring(err) .. ")", def and #def.steps == 4 and def.steps[2].rank == 2
     and def.steps[2].how == "pm" and def.steps[2].n == 20 and def.steps[2].tank and def.steps[4].how == "fill")
  ok("... and exports the same", def and E.PlaystyleExport(def) == line)
  ok("lower case and spaces are fine", E.PlaystyleImport("hm1: Mine ,rh ; pom , B , CD , T ; renew , h , fill") ~= nil)
  local function bad(text, want)
    local d, why = E.PlaystyleImport(text)
    ok("turned away: " .. want, d == nil and why and why:find(want, 1, true) ~= nil)
    if d or not (why and why:find(want, 1, true)) then print("     said: " .. tostring(why)) end
  end
  bad("Renew filler", "starts with HM1:")
  bad("HM1:;RENEW,b,fill", "no name")
  bad("HM1:X;SMITE,b,fill", "unknown spell \"SMITE\"")
  bad("HM1:X;GH,b,cd,t;RENEW,b,fill", "Greater Heal has no cooldown")
  bad("HM1:X;GH,b,up;RENEW,b,fill", "only Renew can be kept up")
  bad("HM1:X;POM,b,10pm,t;RENEW,b,fill", "can't be cast more often than every 10 s")
  bad("HM1:X;PENANCE,b,5,t;RENEW,b,fill", "can't be cast more often than every 12 s")
  bad("HM1:X;RENEW,b,fill;POM,b,cd", "only the last block can fill the rest")
  bad("HM1:X;POM,b,cd;GH,b,2pm", "The last block fills the rest")
  bad("HM1:X;GH,9,fill", "Greater Heal has ranks 1 to")
  bad("HM1:X;POM,b,fill", "can't fill the rest")
  bad("HM1:X;GH,b,2pm;BH,b,fill", "use Flash Heal")
  -- a saved one with Flash Heal (Holy Binding) last (the editor once allowed it): plain Flash Heal
  local hb = { name = "Greater Heal filler", steps = { { spell = "POM", how = "cd", tank = true }, { spell = "GH", how = "pm", n = 2 },
                                                       { spell = "BH", how = "fill", tank = true } } }
  E.SetPlaystyles(nil, { ghFill = hb })
  ok("a saved Holy Binding filler becomes Flash Heal, and the edit is used",
     hb.steps[3].spell == "FLASH" and E.ROTATIONS.ghFill.edited and E.Rotation("ghFill", pst, pt, pset) ~= nil)
  E.SetPlaystyles(nil, nil)
  bad("HM1:X;GH,b,2pm;PWS,1,fill", "can't fill the rest")
  bad("HM1:X;POM,b,cd;POM,b,cd;POM,b,cd;POM,b,cd;POM,b,cd;POM,b,cd;POM,b,cd;POM,b,cd;RENEW,b,fill", "At most 8 blocks")
  bad("HM1:X;GH,b,2pm,x;RENEW,b,fill", "unknown option \"x\"")

  -- your own: the Inspiration example. Lesser Heal rank 2 on the tank 20 times a minute
  local insp = E.PlaystyleImport("HM1:Renew + Inspiration;POM,b,cd,t;LESSER,2,20pm,t;GH,b,2pm,t;RENEW,b,fill")
  E.SetPlaystyles({ my1 = insp }, nil)
  local mine = E.Rotation("my1", pst, pt, pset)
  local renew = E.Rotation("renew", pst, pt, pset)
  local lesser
  for _, s in ipairs(mine.steps) do if s.key == "LESSER" then lesser = s end end
  ok("Lesser Heal rank 2, at most 20 a minute", lesser and lesser.rank == 2 and lesser.casts <= 180 / 3 + 1e-9 and lesser.casts > 1)
  ok("more casts on the tank: Inspiration up more of the time",
     mine.inspirationParts and renew.inspirationParts and mine.inspirationParts.uptime > renew.inspirationParts.uptime)
  ok("it is offered next to the built-ins", (function()
    for _, p in ipairs(E.ComparePlans(pst, inp)) do if p.key == "my1" then return true end end end)())
  -- Renew on the tank adds nothing to Inspiration (its ticks don't crit); Flash Heal does
  E.SetPlaystyles({ a = E.PlaystyleImport("HM1:A;GH,b,2pm,t;RENEW,b,fill"),
                    b = E.PlaystyleImport("HM1:B;GH,b,2pm,t;RENEW,b,fill,t"),
                    c = E.PlaystyleImport("HM1:C;GH,b,2pm,t;FLASH,b,fill,t") }, nil)
  local ua = E.Rotation("a", pst, pt, pset).inspirationParts.uptime
  local ub = E.Rotation("b", pst, pt, pset).inspirationParts.uptime
  local uc = E.Rotation("c", pst, pt, pset).inspirationParts.uptime
  ok(string.format("Renew on the tank: Inspiration unchanged (%.3f = %.3f); Flash Heal on the tank: up more (%.3f)", ua, ub, uc),
     math.abs(ua - ub) < 1e-12 and uc > ua + 0.05)

  -- the Math tab with blocks: the same spell twice, a filler other than Renew
  assert(loadfile("Models/PriestMath.lua"))(nil, { Models = { PRIEST = E } })
  E.SetPlaystyles({ m = E.PlaystyleImport("HM1:Math;POM,b,cd,t;GH,b,2pm,t;GH,2,6pm;LESSER,2,6pm,t;FLASH,b,fill") }, nil)
  local MS = { st = pst, t = pt, input = inp, rotation = "m" }
  MS.weights = E.Weights("m", pst, inp)
  MS.spells = E.SpellTable(pst, pt, inp.settings)
  local _, ck = E.MathPage(MS)
  local good, cnt, ohPWS = 0, 0, inp.settings.overheal.PWS or 0
  for _, sc in ipairs(ck.spells) do
    cnt = cnt + 1
    local s2 = sc.step
    local want = s2.perCast * (1 - (s2.overheal or 0)) + s2.aegis * (1 - ohPWS)
    if math.abs(sc.cost - s2.cost) < 1e-9 and math.abs(sc.heal - want) < 1e-9 then good = good + 1 end
  end
  local cast = 0
  for _, s2 in ipairs(MS.weights.base.steps) do if s2.enabled and s2.casts > 0.01 then cast = cast + 1 end end
  ok("Math tab, blocks with Greater Heal twice and a Flash Heal filler: lines add up",
     math.abs(ck.fight.eff - MS.weights.base.eff) < 1e-6 and ck.fight.worst < 1e-6)
  ok("... each spell's section = its fight line (" .. good .. " of " .. cnt .. ", " .. cast .. " cast)", cnt == cast and good == cnt and cnt == 5)
  E.SetPlaystyles({ my1 = insp }, nil)

  -- Renewed Hope only on blocks on the tank
  local rh = E.PlaystyleImport("HM1:Shield,rh;PWS,1,cd,t;GH,b,2pm,t;FLASH,b,2pm;RENEW,b,fill")
  local rot = E.RotationFromPlaystyle(rh)
  ok("Renewed Hope: Greater Heal on the tank gets it, Flash Heal on anyone doesn't, PW:Shield never",
     rot.steps[2].rh == true and rot.steps[3].rh == false and rot.steps[1].rh == false)
  near("... and the shield waits for Weakened Soul", rot.steps[1].cap, 15)
  ok("a shield on the tank every 10 s is allowed but warned about (Weakened Soul)",
     E.StepWarning({ spell = "PWS", how = "pm", n = 6, tank = true }) ~= nil
     and E.StepWarning({ spell = "PWS", how = "cd", tank = true }) == nil)
  ok("a summary in words", E.PlaystyleSummary(insp) == "Prayer of Mending on cooldown on the tank, Lesser Heal rank 2 at most 20 times a " ..
     "minute on the tank, Greater Heal at most twice a minute on the tank, then Renew the rest of the time.")

  -- the fight view: the model's counts placed by priority, nothing overlapping
  E.SetPlaystyles({ my1 = insp }, nil)
  local res = E.Rotation("my1", pst, pt, pset)
  local tl = E.FightTimeline(insp, res, pset.fightLength)
  local per, overlap, inside, lastEnd = {}, 0, true, -1
  for _, c in ipairs(tl.casts) do
    per[c.block] = (per[c.block] or 0) + 1
    if c.t < lastEnd - 1e-6 then overlap = overlap + 1 end
    lastEnd = c.t + c.dur
    if c.t < 0 or c.t + c.dur > pset.fightLength + 1e-6 then inside = false end
  end
  local countsMatch = true
  for i, s2 in ipairs(res.steps) do
    local want = s2.enabled and (s2.casts + (s2.pauseCasts or 0)) or 0
    print(string.format("     block %d: strip %d, model %.1f", i, per[i] or 0, want))
    if math.abs((per[i] or 0) - want) > math.max(1.01, 0.1 * want) then countsMatch = false end
  end
  ok("the fight view has about the model's casts per block (within 1, or 10%)", countsMatch)
  ok("... none overlapping, all inside the fight", overlap == 0 and inside)
  local pomGap = math.huge
  local lastPom
  for _, c in ipairs(tl.casts) do
    if c.key == "POM" then if lastPom then pomGap = math.min(pomGap, c.t - lastPom) end; lastPom = c.t end
  end
  ok("... Prayer of Mending never before its cooldown (10 s)", pomGap >= 10 - 1e-6)

  -- editing a built-in: it keeps its key and name, and goes back as shipped
  local ed = E.PlaystyleFromRotation(E.BUILTIN_ROTATIONS.renew)
  table.insert(ed.steps, #ed.steps, { spell = "LESSER", rank = 2, how = "pm", n = 20, tank = true })
  local ROT = E.ROTATIONS
  E.SetPlaystyles(nil, { renew = ed, ghFill = { name = "broken", steps = {} } })
  ok("an edited built-in keeps its key and name and says it's edited",
     E.ROTATIONS.renew.edited and E.ROTATIONS.renew.name == "Renew filler" and E.ROTATIONS.renew.builtin == "renew")
  ok("a broken saved edit is left out: the built-in as shipped", E.ROTATIONS.ghFill == E.BUILTIN_ROTATIONS.ghFill)
  ok("the edit changes what it heals", math.abs(eps("renew") - E.Rotation("renew", pst, pt, pset).ehps) < 1e-9
     and math.abs(eps("renew") - renew.ehps) > 0.01)
  ok("the same table throughout (whatever holds it sees the change)", E.ROTATIONS == ROT)
  E.SetPlaystyles(nil, nil)
  ok("put back: the built-ins as shipped, nothing else", E.ROTATIONS.renew == E.BUILTIN_ROTATIONS.renew and E.ROTATIONS.my1 == nil)
  ok("a saved playstyle of yours can't take a built-in's key", (function()
    E.SetPlaystyles({ renew = insp }, nil); local r = E.ROTATIONS.renew == E.BUILTIN_ROTATIONS.renew; E.SetPlaystyles(nil, nil); return r end)())
end

print("-- People reached by group heals (Prayer of Healing, Holy Nova, Inner Focus)")
do
  E.SPELLS = E.copy(E.GAME_SPELLS)
  local inp = E.copy(E.DEFAULTS)
  inp.settings.rules = E.RULES
  local gst, gt = E.Derive(inp), E.Talents(inp.talents)
  local five = E.copy(inp.settings)
  local three = E.copy(inp.settings); three.groupHits = 3
  local p5, p3 = E.Spell("POH", 4, gst, gt, five), E.Spell("POH", 4, gst, gt, three)
  near("Prayer of Healing: 5 people by default", p5.targets, 5)
  near("... 3 when set to 3: per mana 3/5 as much", p3.hpm / p5.hpm, 3 / 5)
  near("Holy Nova too", E.Spell("NOVA", 6, gst, gt, three).targets, 3)
  near("single-target heals don't change", E.Spell("GH", 4, gst, gt, three).hpm, E.Spell("GH", 4, gst, gt, five).hpm)
  local r5, r3 = E.Rotation("pohFill", gst, gt, five), E.Rotation("pohFill", gst, gt, three)
  near("Prayer of Healing filler heals less with 3 people", r3.ehps < r5.ehps and 1 or 0, 1)
  near("Inner Focus's free Prayers of Healing reach 3 too", r3.innerFocus.perCast / r5.innerFocus.perCast, 3 / 5)
  assert(loadfile("Models/PriestMath.lua"))(nil, { Models = { PRIEST = E } })
  local in3 = E.copy(inp); in3.settings.groupHits = 3
  local GS = { st = gst, t = gt, input = in3, rotation = "pohFill" }
  GS.weights = E.Weights("pohFill", gst, in3)
  GS.spells = E.SpellTable(gst, gt, in3.settings)
  local rows, ck = E.MathPage(GS)
  near("Math tab with 3 people: the fight adds up", (math.abs(ck.fight.eff - GS.weights.base.eff) < 1e-6 and ck.fight.worst < 1e-6) and 1 or 0, 1)
  local editable = false
  for _, r in ipairs(rows) do
    if r[1] == "Targets" and r.edit and r.edit.setting and r.edit.setting[1] == "groupHits" and r.edit.raw == 3 then editable = true end
  end
  near("... Prayer of Healing's targets are your setting there, typed over like any setting", editable and 1 or 0, 1)
  near("the setting takes 1 to 5 people", (E.MathSettingValue({ "groupHits" }, 3) == 3 and not E.MathSettingValue({ "groupHits" }, 6)) and 1 or 0, 1)
end

print("-- Discipline: Soul Warding, Weakened Soul and Renewed Hope, Divine Aegis")
do
  E.SPELLS = E.copy(E.GAME_SPELLS)
  local inp = E.copy(E.DEFAULTS)
  inp.settings.rules = E.RULES
  inp.settings.includeInspiration = false
  local dst = E.Derive(inp)
  local set = inp.settings
  local function ok(label, cond) near(label, cond and 1 or 0, 1) end
  local function tal(over)
    local tr = E.copy(inp.talents)
    for k, v in pairs(over) do tr[k] = v end
    return E.Talents(tr)
  end
  local plain = tal({ renewedHope = 0, soulWarding = 0, divineAegis = 0 })
  local function run(line, t)
    E.SetPlaystyles({ x = assert(E.PlaystyleImport(line)) }, nil)
    local r = E.Rotation("x", dst, t, set)
    E.SetPlaystyles(nil, nil)
    return r
  end
  local function stepOf(r, key) for _, s in ipairs(r.steps) do if s.key == key then return s end end end

  -- the game data
  local sw = tal({ soulWarding = 1 })
  near("Soul Warding: PW:Shield costs 15% less (game data)", sw.soulWarding, 0.15)
  near("... and has no cooldown left (4 s off its 4 s)", sw.soulWardingCd, 4)
  near("Renewed Hope 5/5: each heal takes 5 s off Weakened Soul", tal({ renewedHope = 5 }).renewedHopeCut, 5)
  near("Renewed Hope 2/5: 2 s", tal({ renewedHope = 2 }).renewedHopeCut, 2)
  near("Divine Aegis: at most 20 x your level, at every rank", tal({ divineAegis = 1 }).daCapPerLevel, 20)

  -- Soul Warding: a shield on anyone "on cooldown" goes every global cooldown
  local spread = "HM1:Spread;PWS,1,cd;RENEW,b,fill"
  local a, b = stepOf(run(spread, plain), "PWS"), stepOf(run(spread, sw), "PWS")
  near("PW:Shield on anyone on cooldown: every 4 s", a.cap, 4)
  near("... with Soul Warding: every global cooldown", b.cap, 1.5 / (1 + dst.haste))

  -- Weakened Soul: the tank is shielded only when it is gone
  local pws = E.Rotation("pwsTank", dst, plain, set)
  near("PW:Shield on tank (asks every 12 s): every 15 s, Weakened Soul", stepOf(pws, "PWS").cap, 15)
  local rh = tal({ renewedHope = 5 })
  local disc = "HM1:Disc,rh;PWS,1,cd,t;FLASH,b,fill,t"
  local r = run(disc, rh)
  local rate, lock = r.ws.rate, E.WeakenedSoulLockout()
  near("Renewed Hope: Weakened Soul lasts 15 s / (1 + 5 s x heals on the tank a second)", r.ws.len, lock / (1 + 5 * rate), 1e-3)
  near("... and the tank is shielded that often", stepOf(r, "PWS").cap, r.ws.len, 1e-3)
  near("... the heals a second are the fight's own Flash Heals on the tank", rate, stepOf(r, "FLASH").casts / set.fightLength, 1e-3)
  near("... Weakened Soul up all the time when shielded as soon as it goes", r.ws.uptime, 1, 1e-3)
  local noRH = run("HM1:Disc;PWS,1,cd,t;FLASH,b,fill,t", rh)
  near("unticked: Weakened Soul's full 15 s", stepOf(noRH, "PWS").cap, 15)
  ok("... and Flash Heal on the tank heals less a cast (no extra crit)", stepOf(noRH, "FLASH").perCast < stepOf(r, "FLASH").perCast)
  local noShield = run("HM1:No shield,rh;FLASH,b,fill,t", rh)
  local noShieldOff = run("HM1:No shield;FLASH,b,fill,t", rh)
  near("Renewed Hope without a shield on the tank: no extra crit", noShield.ehps, noShieldOff.ehps, 1e-9)
  local slow = run("HM1:Slow,rh;PWS,1,30,t;FLASH,b,fill,t", rh)
  near("a shield every 30 s: Renewed Hope's crit for the share Weakened Soul is up",
       stepOf(slow, "FLASH").rhUp, slow.ws.shields * slow.ws.len / set.fightLength, 1e-3)
  ok("... under all of it", stepOf(slow, "FLASH").rhUp < 0.9)
  local pom = run("HM1:PoM,rh;POM,b,cd,t;PWS,1,cd,t;FLASH,b,fill,t", rh)
  ok("Prayer of Mending on the tank gets no Renewed Hope (not its spell)", stepOf(pom, "POM").rh == nil)

  -- Divine Aegis: a share of the crit, at most 20 x level a heal
  local dt = { daMulti = 0.15, daCapPerLevel = 20 }
  local s51 = { level = 51, critMulti = 1.5 }
  near("Divine Aegis: 15% of the crit (1.5 x the heal)", E.AegisFor(2000, 1, "GH", 1, s51, dt, E.RULES), 2000 * 1.5 * 0.15)
  near("... at most 20 x level (1020 at 51)", E.AegisFor(10000, 1, "GH", 1, s51, dt, E.RULES), 1020)
  near("... per Penance bolt", E.AegisFor(30000, 1, "PENANCE", 1, s51, dt, E.RULES), 3 * 1020)
  near("... times the crit chance", E.AegisFor(2000, 0.2, "GH", 1, s51, dt, E.RULES), 0.2 * 450)
  near("the sheet's: 15% of the heal, no cap", E.AegisFor(10000, 1, "GH", 1, s51, dt, E.SHEET_RULES), 1500)
  near("... none from Renew's ticks (only direct heals leave one)", E.AegisFor(2000, 1, "RENEW", 1, s51, dt, E.RULES), 0)
  local da3 = tal({ divineAegis = 3 })
  local ifr = E.Rotation("pohFill", dst, da3, set).innerFocus
  local poh = E.Spell("POH", ifr.rank, dst, da3, set)
  near("Inner Focus's Prayers of Healing: Divine Aegis the same way (+25% crit)", ifr.aegis,
       E.AegisFor(poh.heal, dst.crit + 0.25, "POH", 1, dst, da3, E.RULES) * poh.targets, 1e-9)
  local mix = E.BestMix(dst, sw, set)
  local shields = 0
  for _, it in ipairs(mix and mix.items or {}) do if it.key == "PWS" then shields = shields + (it.casts or 0) end end
  ok("best mix: at most a shield per Weakened Soul (" .. string.format("%.1f", shields) .. ")", shields <= set.fightLength / 15 + 1e-6)

  -- the Math tab still adds up with all of it
  assert(loadfile("Models/PriestMath.lua"))(nil, { Models = { PRIEST = E } })
  local din = E.copy(inp)
  for k, v in pairs({ renewedHope = 5, soulWarding = 1, divineAegis = 3, penance = 1 }) do din.talents[k] = v end
  local dt2 = E.Talents(din.talents)
  for _, key in ipairs({ "rhTank", "pwsTank" }) do
    local MS = { st = dst, t = dt2, input = din, rotation = key }
    MS.weights = E.Weights(key, dst, din)
    MS.spells = E.SpellTable(dst, dt2, din.settings)
    local _, ck = E.MathPage(MS)
    local good, n = 0, 0
    for _, sc in ipairs(ck.spells) do
      n = n + 1
      local s2 = sc.step
      local want = s2.perCast * (1 - (s2.overheal or 0)) + s2.aegis * (1 - (din.settings.overheal.PWS or 0))
      if math.abs(sc.heal - want) < 1e-6 then good = good + 1 end
    end
    ok("Math tab, " .. key .. " with Discipline: each spell's section = its fight line", n > 0 and good == n)
    ok("... and the fight adds up", math.abs(ck.fight.eff - MS.weights.base.eff) < 1e-6 and ck.fight.worst < 1e-6)
  end

  -- stat weights don't move with more passes (each run settles the same way)
  local wline = "HM1:WDisc,rh;PENANCE,b,cd,t;PWS,1,cd,t;GH,b,4pm,t;FLASH,b,fill,t"
  E.SetPlaystyles({ wd = assert(E.PlaystyleImport(wline)) }, nil)
  local w3 = E.Weights("wd", dst, din)
  E.SetWSPasses(6)
  local w6 = E.Weights("wd", dst, din)
  E.SetWSPasses(3)
  E.SetPlaystyles(nil, nil)
  local worst = 0
  for _, k in ipairs(E.WEIGHT_STATS) do
    local a3, a6 = w3[k] or 0, w6[k] or 0
    if type(a3) == "number" and type(a6) == "number" then worst = math.max(worst, math.abs(a3 - a6) / math.max(1e-9, math.abs(a6))) end
  end
  ok("stat weights with Renewed Hope: the same with twice the passes (worst " .. string.format("%.4f%%", worst * 100) .. ")", worst < 0.005)

  -- the strip spaces shields as the model does
  local def = assert(E.PlaystyleImport(spread))
  E.SetPlaystyles({ x = def }, nil)
  local base = E.Rotation("x", dst, sw, set)
  local tl = E.FightTimeline(def, base, set.fightLength)
  E.SetPlaystyles(nil, nil)
  local first, second
  for _, c in ipairs(tl.casts) do if c.key == "PWS" then if first then second = second or c.t else first = c.t end end end
  ok("the strip: with Soul Warding shields go back to back", second and (second - first) < 4)
end

print("-- Gear tab: the best gear for you at your level (Models/GearSolve.lua)")
do
  E.SPELLS = E.copy(E.GAME_SPELLS)
  local D = dofile("Models/GearData.lua")
  local GS = dofile("Models/GearSolve.lua")
  local function ok(label, cond) near(label, cond and 1 or 0, 1) end
  local function character(level, side)
    local inp = E.copy(E.DEFAULTS)
    inp.settings.rules = E.RULES; inp.settings.known = nil; inp.settings.fightLength = 120
    inp.settings.shadowSpiritBuff = false
    inp.race = { human = side == "A", troll = side == "H", dwarf = false, gnome = false }
    inp.level = level
    -- the 17/32 build (the talent search's best)
    inp.talents = { twinDisciplines = 5, mentalStrength = 5, mentalAgility = 3, innerFocus = 1, meditation = 3,
      improvedRenew = 3, holySpecialization = 5, divineFury = 5, inspiration = 3, improvedHealing = 3, holyBinding = 1,
      bindingHeal = 1, litanyOfLight = 2, spiritualGuidance = 5, spiritualHealing = 3, prayerOfMending = 1,
      improvedPWS = 0, soulWarding = 0, penance = 0, renewedHope = 0, divineAegis = 0 }
    return inp
  end
  local function solve(level, side, pvp, profs, current, gearOn)
    local inp = character(level, side)
    inp.gear = gearOn or { healing = 0, int = 0, crit = 0, haste = 0, mp5 = 0, spirit = 0, spelldamage = 0 }
    local st = E.Derive(inp)
    return GS.Solve({ E = E, st = st, input = inp, rot = "renew", D = D, side = side, level = level, pvp = pvp,
                      profs = profs or {}, current = current })
  end
  local function check(label, r, level, side, pvp, profs)
    local bad, limits = {}, {}
    for _, slot in ipairs(GS.SLOTS) do
      local it = r.items[slot]
      if it then
        if not it[side] then bad[#bad + 1] = it.name .. ": not for this side" end
        if it.lvl > level then bad[#bad + 1] = it.name .. ": level " .. it.lvl end
        if it.prof ~= "" and not (profs and profs[it.prof]) then bad[#bad + 1] = it.name .. ": " .. it.prof .. " only" end
        if it.pvp[side] and not pvp then bad[#bad + 1] = it.name .. ": PvP" end
        if it.limit ~= 0 then
          if limits[it.limit] then bad[#bad + 1] = it.name .. ": two of one equip limit" end
          limits[it.limit] = true
        end
      end
      local names = {}
      if it then names[it.name] = true end
      for _, a in ipairs(r.alts[slot] or {}) do
        if names[a.name] then bad[#bad + 1] = slot .. ": " .. a.name .. " twice" end
        names[a.name] = true
      end
    end
    local w = r.items.weapon
    if w and w.slot == "twohand" and r.items.offhand then bad[#bad + 1] = "an off hand with a two-hander" end
    local wv = r.weapons or {}
    if wv.twohand and wv.twohand.item.slot ~= "twohand" then bad[#bad + 1] = "the two-hander isn't one" end
    if wv.onehand and (wv.onehand.item.slot ~= "mainhand" or wv.onehand.offhand.slot ~= "offhand") then bad[#bad + 1] = "the one-hand way is wrong" end
    local better = (wv.twohand and wv.onehand) and (wv.twohand.hps >= wv.onehand.hps and "twohand" or "onehand")
    if better and wv.worn ~= better then bad[#bad + 1] = "the worse weapon way is worn" end
    if wv.worn == "twohand" and w ~= wv.twohand.item then bad[#bad + 1] = "worn two-hander isn't the best" end
    if wv.worn == "onehand" and (w ~= wv.onehand.item or r.items.offhand ~= wv.onehand.offhand) then bad[#bad + 1] = "worn one-hand way isn't the best" end
    local best = math.max(wv.twohand and wv.twohand.hps or 0, wv.onehand and wv.onehand.hps or 0)
    if math.abs(best - r.hps) > 1e-6 then bad[#bad + 1] = string.format("the better weapon way (%.1f) isn't the list's HPS (%.1f)", best, r.hps) end
    ok(label .. string.format(": %.0f HPS, all wearable (%s)", r.hps, table.concat(bad, "; ")), #bad == 0 and r.hps > r.now)
  end
  local r60 = solve(60, "H", false)
  check("level 60, Horde", r60, 60, "H", false)
  ok(string.format("level 60, Horde, 17/32: at least as good as the long search found (868 HPS): %.1f", r60.hps), r60.hps >= 868.0 - 0.05)
  local r51 = solve(51, "H", false)
  check("level 51: only what you can wear at 51", r51, 51, "H", false)
  check("level 30, Alliance", solve(30, "A", false), 30, "A", false)
  check("level 60, Alliance, with PvP gear", solve(60, "A", true), 60, "A", true)
  -- what you wear comes off first: wearing something doesn't change the answer
  local robe
  for _, it in ipairs(D.items) do if it.name == "Truefaith Vestments" then robe = it end end
  local worn = { chest = { healing = 73, spirit = 16 } }
  local r2 = solve(60, "H", false, {}, worn, { healing = 73, int = 0, crit = 0, haste = 0, mp5 = 0, spirit = 16, spelldamage = 0 })
  -- (to 1e-4: the solver keeps a fight whose casts moved under half a cast, and a proc's
  -- share isn't linear in the cast rate)
  near("what you wear comes off: the same best (" .. string.format("%.1f", r2.hps) .. ")", r2.hps, r60.hps, 1e-4)
  ok("... and the gain counts from what you wear", r2.now > r60.now)
  -- a profession's own items count when you have it
  local pool = GS.Pool(D, "H", 60, false, {})
  local poolT = GS.Pool(D, "H", 60, false, { Tailoring = true })
  local has = false
  for _, it in ipairs(poolT) do if it == robe then has = true end end
  ok("Truefaith Vestments only with Tailoring", robe and has and #poolT > #pool)
  ok("the search stays small: " .. r60.runs .. " model runs at 60", r60.runs < 600)
  -- trinket effects, averaged over a 2-minute fight (0.6 casts a second, 4 Greater Heals)
  local function named(n) for _, it in ipairs(D.items) do if it.name == n then return it end end end
  local ctx = { fl = 120, cps = 0.6, casts = { GH = 4 }, oh = 0.25 }
  local add = GS.Effects(named("Serenity Field"), ctx)
  near("Serenity Field: +72 spirit for 15 s, once in a 2-minute fight", add.spirit, 72 * 15 / 120)
  add = GS.Effects(named("Mindtap Talisman"), ctx)
  near("Mindtap Talisman: 1,250 mana (7-min cooldown, a pull every 10 min: every fight) as MP5", add.mp5, 1250 / 120 * 5)
  add = GS.Effects(named("Second Wind"), ctx)
  -- pulls at 0, 10, 20, 30 min: used at 0, ready at 15 (no fight), used at 20: every other fight
  near("Second Wind: 630 mana, its 15-min cooldown ready every other pull (a pull every 10 min)", add.mp5, 630 * 0.5 / 120 * 5, 1e-6)
  add = GS.Effects(named("Burst of Knowledge"), ctx)
  near("Burst of Knowledge: 150 mana off each cast for 10 s", add.mp5, 150 * 0.6 * 10 / 120 * 5)
  add = GS.Effects(named("Robes of Insight"), ctx)
  near("Robes of Insight: 200 mana off the next spell only", add.mp5, 200 * 1 / 120 * 5)
  add = GS.Effects(named("Darkmoon Card: Blue Dragon"), ctx)
  -- up 1 - e^(-r min(t, 15)) at time t, from no buff at the pull, averaged over 120 s
  local function ramp(r, d, fl) local x = math.exp(-r * d); return 1 - ((1 - x) / r + (fl - d) * x) / fl end
  near("Blue Dragon: 3% a cast, 150 spirit for 15 s, from no buff at the pull", add.spirit, 150 * ramp(0.03 * 0.6, 15, 120))
  add = GS.Effects(named("Dormant Heart of the Mountain"), ctx)
  -- Greater Heal every 30 s (a schedule, not at random): up 15 s after each, less the part
  -- the fight's end cuts off (15 * 15 / 2 s over 4 casts' spacing)
  near("Dormant Heart: +40 healing for 15 s after each Greater Heal (4 in the fight, evenly spaced)", add.healing,
       40 * (4 / 120 * 15 - 4 / 120 * 15 * 15 / (2 * 120)))
  -- a use's schedule over many fights: Headmaster's Charge (+20 int for 15 min, 10-min cooldown)
  -- is up the whole of every fight; a 5-min cooldown in 1-minute fights every 2 minutes: one
  -- fight in three (0, 6, 12 min ...)
  local u, sh = GS.UseSchedule(600, 900, 120, 600)
  ok("Headmaster's Charge: used every fight, up all of it", math.abs(u - 1) < 1e-9 and math.abs(sh - 1) < 1e-9)
  u = GS.UseSchedule(300, 15, 60, 120)
  near("a 5-min cooldown in 1-minute fights every 2 minutes: one fight in three", u, 1 / 3, 0.01)
  local _, heal = GS.Effects(named("Blessed Prayer Beads"), ctx)
  near("Blessed Prayer Beads: a 648 heal on your target on use, after your Flash Heal overheal", heal, 648 / 120 * 0.75)
  ok("Lifestone and Behemoth Bones (heals on yourself only) don't count, so aren't in the list",
     not named("Lifestone") and not named("Behemoth Bones"))
  local recomb = named("Major Recombobulator")
  ok("Major Recombobulator: Engineering only, and its mana counts, not its heal (one target for both)",
     recomb and recomb.prof == "Engineering" and recomb.fx and recomb.fx[1].mana == 304 and not recomb.fx[1].heal)
  ok("Engineering goggles need Engineering (wowsims leaves it out; the game says so)",
     named("Rose Colored Goggles") and named("Rose Colored Goggles").prof == "Engineering")
  local mark = GS.Effects(named("Mark of the Dragon Lord"), ctx)
  near("Mark of the Dragon Lord: 22 MP5 for 30 min, up the whole fight", mark.mp5, 22)
  add = GS.Effects(named("Mindtap Talisman"), ctx)
  near("... and its catch: Tapped Mind, -60 intellect for 2 minutes after", add.int, -60)
  local emblem = named("Draconic Infused Emblem")
  ok("Draconic Infused Emblem's proc (harmful spells only) never counts for a healer", not (emblem and emblem.fx))
  ok("no drink and no channel among the effects (Skum's Bucket, Circle of Flame)",
     not named("Skum's Bucket") or not named("Skum's Bucket").fx)
  -- wearing what it picks: the same pick, and no gain (the set's mana proc counts for what you wear too)
  local current, ids, gear = {}, {}, { healing = 0, int = 0, crit = 0, haste = 0, mp5 = 0, spirit = 0, spelldamage = 0 }
  for slot, it in pairs(r60.items) do
    local st = GS.Stats(it)
    current[slot], ids[slot] = st, it.id
    for k, v in pairs(st) do gear[k] = gear[k] + v end
  end
  local b = GS.Bonuses(D, r60.items)
  for _, k in ipairs({ "healing", "int", "spirit", "mp5" }) do gear[k] = gear[k] + (b[k] or 0) end
  local inp = character(60, "H")
  inp.gear = gear
  local again = GS.Solve({ E = E, st = E.Derive(inp), input = inp, rot = "renew", D = D, side = "H", level = 60,
                           profs = {}, current = current, currentIds = ids })
  local same = true
  for slot, it in pairs(r60.items) do if again.items[slot] ~= it then same = false end end
  ok("wearing its own pick: the same pick", same)
  local allWorn, noArrow = true, true
  for _, it in pairs(again.items) do
    local g = again.gains[it.key]
    if not (g and g.worn) then allWorn = false end
  end
  for key, g in pairs(again.gains) do
    if not g.worn and g.d > 0.05 then
      -- a shown item better than what's worn in its slot can only be another set-less swap; the pick's own items never are
      for _, it in pairs(again.items) do if it.key == key then noArrow = false end end
    end
  end
  ok("... each item it wears is marked as worn, none of them as an upgrade", allWorn and noArrow)
  -- an arrow's number is what that one swap really does (set bonuses won or lost included)
  local function wear(items)
    local cur, idz, keys, gear = {}, {}, {}, { healing = 0, int = 0, crit = 0, haste = 0, mp5 = 0, spirit = 0, spelldamage = 0 }
    for slot, it in pairs(items) do
      local st = GS.Stats(it)
      cur[slot], idz[slot], keys[slot] = st, it.id, it.key
      for k, v in pairs(st) do gear[k] = gear[k] + v end
    end
    local bb = GS.Bonuses(D, items)
    for _, k in ipairs({ "healing", "int", "spirit", "mp5" }) do gear[k] = gear[k] + (bb[k] or 0) end
    local i2 = character(60, "H"); i2.gear = gear
    return GS.Solve({ E = E, st = E.Derive(i2), input = i2, rot = "renew", D = D, side = "H", level = 60, profs = {},
                      current = cur, currentIds = idz, currentKeys = keys })
  end
  local worst, checked = 0, 0
  for slot, it in pairs(r60.items) do
    if it.set ~= 0 then
      for i = 1, 3 do
        local alt = again.alts[slot] and again.alts[slot][i]
        local g = alt and again.gains[alt.key]
        if g and not g.worn and not g.pair then
          local sw = {}
          for s2, x in pairs(r60.items) do sw[s2] = x end
          sw[slot] = alt
          local real = wear(sw).now - again.now
          worst = math.max(worst, math.abs(real - g.d))
          checked = checked + 1
        end
      end
    end
  end
  ok(string.format("an arrow's number is what the swap does, set bonuses included (%d swaps, worst %.1f HPS off)", checked, worst),
     checked > 5 and worst < 1.5)
  -- the weapon rows show the weapons the list counts
  for _, case in ipairs({ { "A", true, 60, "ghFill" }, { "H", true, 60, "pwsTank" }, { "H", false, 120, "renew" } }) do
    local i3 = character(60, case[1]); i3.settings.fightLength = case[3]
    i3.gear = { healing = 0, int = 0, crit = 0, haste = 0, mp5 = 0, spirit = 0, spelldamage = 0 }
    local rw = GS.Solve({ E = E, st = E.Derive(i3), input = i3, rot = case[4], D = D, side = case[1], level = 60, pvp = case[2], profs = {} })
    local wv = rw.weapons
    local shownWay = wv.worn == "twohand" and wv.twohand or wv.onehand
    ok(string.format("%s %s, %d s fight: the weapon rows show the weapons counted", case[1], case[4], case[3]),
       shownWay and shownWay.item == rw.items.weapon and shownWay.offhand == rw.items.offhand)
  end
  -- with a two-hander on, a main hand or off hand alone gets no number (it counts only as a pair)
  local staffOn = {}
  for s2, x in pairs(r60.items) do staffOn[s2] = x end
  local staff
  for _, it in ipairs(D.items) do if it.slot == "twohand" and it.lvl <= 60 and it.H then staff = it; break end end
  staffOn.weapon, staffOn.offhand = staff, nil
  local rs = wear(staffOn)
  local pairOnly = true
  for _, x in ipairs(rs.alts.offhand or {}) do local g = rs.gains[x.key]; if g and not g.pair then pairOnly = false end end
  ok("a two-hander on: off hands get no arrow of their own", pairOnly and #(rs.alts.offhand or {}) > 0)
  near("... and no gain over what you wear (" .. string.format("%.2f", again.hps - again.now) .. ")", again.hps - again.now, 0, 1e-6)
end

print(string.format("\n%d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
