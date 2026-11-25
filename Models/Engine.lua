--[[ Holy Math - Models/Engine.lua
     What every class's fight model shares, in plain Lua with no game calls: your own values
     typed over on the Math tab, pauses under the 5-second rule, potions and runes, stat
     values, item and consumable comparisons, the plan list, and a small LP solver.

     A class model (Models/Priest.lua, Models/Paladin.lua) calls Engine.Install(E) first;
     the functions below go on E and call back into the class's own E.Rotation, E.Talents,
     E.StatDelta, E.RULES and E.TALENT_RANGE, so they always work on that class's numbers.
]]--

local _, ns = ...
ns = ns or {}
local Engine = {}

function Engine.Install(E)
  local max, min, ceil = math.max, math.min, math.ceil

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

  local function copy(v) if type(v) ~= "table" then return v end local o = {} for k, x in pairs(v) do o[k] = copy(x) end return o end
  E.copy = copy

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

  -- The range a typed value must be in (a bad saved value must never break a rebuild,
  -- and none in range may make a cost, cast time or heal go below zero).
  local STAT_RANGE = { healing = { 0, 1e5 }, healingFromSpirit = { 0, 1e5 }, crit = { 0, 1 }, critMulti = { 1, 5 },
                       haste = { 0, 2 }, manaPool = { 1, 1e6 }, mp5 = { 0, 1e4 }, oocRegen = { 0, 1e5 },
                       castingShare = { 0, 1 }, critPerInt = { 0.001, 1 } }
  function E.OverrideRange(id)
    if type(id) ~= "string" then return nil end
    local kind, field = id:match("^(%a+)%.(.+)$")
    local r
    if kind == "stat" then r = STAT_RANGE[field]
    elseif kind == "talent" then r = field:match("^%a+$") and ((E.TALENT_RANGE or {})[field] or { 0, 1 })
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

  -- A potion or rune's worth (the Consumables tab): your fight with it used as often as its
  -- cooldown lets you, against your fight with nothing on that cooldown (the rest of your
  -- potion list as it is). HPS after overheal, and as a share of the second.
  function E.PotionGain(rotKey, st, input, key)
    local def = E.POTION_BY_KEY[key]
    if not def then return nil end
    local t = E.Talents(input.talents, input.settings.rules, input.settings.overrides)
    local set = input.settings
    local rest = {}
    for _, e in ipairs(set.potions or {}) do
      local d = E.POTION_BY_KEY[e.key]
      if d and d.group ~= def.group then rest[#rest + 1] = e end
    end
    local with = { { key = key, n = E.POTION_ALL } }
    for _, e in ipairs(rest) do with[#with + 1] = e end
    local ranks = ranksNow(rotKey, st, t, withPotions(set, rest))
    local a, b = potionHPS(rotKey, st, t, set, with, ranks), potionHPS(rotKey, st, t, set, rest, ranks)
    if not (a and b) then return nil end
    return a - b, (a - b) / math.max(1, b)
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

  -- The playstyle with other stats: its own spell ranks for them, or the ranks it has now if
  -- those heal more. The rank search can settle on a worse mix when a little more mana lets
  -- it try bigger ranks (+20 MP5 once took Greater Heal from rank 4 to 2 and lost 11 HPS), but
  -- more of a stat never heals less than before: you could keep the ranks you have.
  local function rerun(rotKey, s2, t, set, base)
    local new = E.Rotation(rotKey, s2, t, set)
    if base and base.rankChoice and not set.rankChoice then
      local keep = {}
      for k, v in pairs(set) do keep[k] = v end
      keep.rankChoice = base.rankChoice
      local r = E.Rotation(rotKey, s2, t, keep)
      if r and (not new or r.ehps > new.ehps) then new = r end
    end
    return new
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
    local new = rerun(rotKey, s2, t, set, base)
    return new.ehps - base.ehps, (new.ehps - base.ehps) / base.ehps, new.hps - base.hps
  end

  -- A consumable's worth (the Consumables tab): as E.Compare, its stats as a buff gives them (a
  -- buff's intellect and spirit count as gear's do, through Kings and the talents), and maximum
  -- mana (diff.mana: Flask of Distilled Wisdom) straight onto the mana pool. A negative diff takes
  -- one off (the one it would take the place of). base: your playstyle's result now, when already
  -- worked out (or just its HPS).
  function E.ConsumableCompare(rotKey, st, input, diff, base)
    local t = E.Talents(input.talents, input.settings.rules, input.settings.overrides)
    local set = input.settings
    if type(base) == "number" then base = { ehps = base } end
    base = base or E.Rotation(rotKey, st, t, set)
    if not base then return nil end
    local s2 = st
    for _, stat in ipairs(E.WEIGHT_STATS) do
      local n = diff[stat]
      if n and n ~= 0 then s2 = addDelta(s2, E.StatDelta(input, stat), n) end
    end
    if diff.mana and diff.mana ~= 0 then
      s2 = addDelta(s2, { manaPool = diff.mana * ((input.race and input.race.gnome) and 1.05 or 1) }, 1)
    end
    local new = rerun(rotKey, s2, t, set, base)
    return new.ehps - base.ehps, (new.ehps - base.ehps) / base.ehps
  end

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

end

ns.Engine = Engine
return Engine
