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
  -- a cost 15% below the data (could be a talent discount already applied) is NOT taken
  E.ApplyClientData({ { key = "GH", rank = 1, cost = 315 } }, cst, ct, cset)
  near("cost 15% off the data is not taken", E.SPELLS.GH.ranks[1].cost, 370)
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
end

print(string.format("\n%d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
