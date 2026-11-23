--[[ Holy Math - Models/GearSolve.lua
     The best gear for you at your level (the Gear tab): your live character run
     through the fight model with your gear swapped for the items in
     Models/GearData.lua. Your level, talents, race, buffs, playstyle and every
     setting count; at level 60 it is the best in slot.

     How it picks (each step runs your playstyle, so the whole model decides):
       1. Your gear comes off (its stats and the set bonuses it gives).
       2. Stat weights rank every item you could wear per slot; the best go on, the
          weights are worked out again with them on, three times.
       3. A main hand and an off hand against the best two-hander.
       4. Each set at each bonus size (the best four of those also two together).
       5. Each slot's top four by the weights, one swap at a time.
       6. The weapons both ways: the best two-hander, and the best main hand with
          the best off hand; the better way is worn, the other shown too.
       7. Each item shown: what it's worth over what you wear in its slot, on its
          own (the Gear tab's upgrade arrows).
     A mana proc (Vestments of the Virtuous) counts as MP5 at the fight's cast rate.
     Use and proc effects of trinkets are not valued. GS.Solve calls args.yield
     between model runs, so the Gear tab can spread it over frames.
]]--

local _, ns = ...
local GS = {}

GS.SLOTS = { "head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet",
  "finger1", "finger2", "trinket1", "trinket2", "weapon", "offhand", "wand" }
-- the character window's slot ids
GS.INV = { head = 1, neck = 2, shoulder = 3, back = 15, chest = 5, wrist = 9, hands = 10, waist = 6, legs = 7,
  feet = 8, finger1 = 11, finger2 = 12, trinket1 = 13, trinket2 = 14, weapon = 16, offhand = 17, wand = 18 }
local STATS = { "healing", "int", "spirit", "mp5", "crit", "haste" }

-- What an item's use and proc effects are worth over the fight (ctx: fl the fight's
-- length, cps your casts a second, casts = { spell key = casts in the fight }, oh the
-- overheal on a heal of your own): stats on average, and healing a second.
--   a use: used at the pull when it's ready, and again as soon as it's ready during the
--     fight, with a fight starting every pull seconds (the setting Time between pulls,
--     10 minutes unless set) and its cooldown running on between fights; worked out
--     over many fights in a row (useSchedule): uses a fight, and the share of fight time
--     its buff is up (a buff longer than the gap between fights carries into the next);
--     stats for that share, mana as MP5, a heal as healing, mana off casts as MP5
--   a proc on your heals: up for the share its chance and your casts give it (casts at
--     random; on every cast of one spell: that spell's casts, evenly spaced; with an
--     internal cooldown: at most once in it), from no buff at the pull unless it lasts
--     past the gap between fights
-- tools/sim/worker.lua checks these against an event-by-event simulation.
GS.PULL_EVERY = 600

local useCache = {}
local function useSchedule(cd, d, fl, pull)
  pull = math.max(pull, fl)
  local key = cd .. ":" .. d .. ":" .. fl .. ":" .. pull
  local c = useCache[key]
  if c then return c[1], c[2] end
  local N = 120                               -- fights in a row: long enough for any pattern
  local ready, uses, up, buffEnd = 0, 0, 0, -1
  for i = 0, N - 1 do
    local s, e = i * pull, i * pull + fl
    local covered = s
    if buffEnd > s then covered = math.min(e, buffEnd); up = up + covered - s end
    local t = math.max(s, ready)
    while t < e do
      uses = uses + 1
      local a, b = math.max(t, covered), math.min(e, t + d)
      if b > a then up = up + b - a; covered = b end
      if t + d > buffEnd then buffEnd = t + d end
      if cd <= 0 then break end
      ready = t + cd
      t = ready
    end
  end
  c = { uses / N, math.min(1, up / (N * fl)) }
  useCache[key] = c
  return c[1], c[2]
end
GS.UseSchedule = useSchedule

-- a proc that refreshes, at rate r a second, lasting d: the share of the fight it's up,
-- starting from no buff at the pull (1 - e^(-r min(t, d)) at time t, averaged)
-- a proc on every cast of one spell (Dormant Heart on Greater Heal): a playstyle casts it
-- on a schedule, every 1/r seconds, from a random point in the first gap; up d after each
-- cast (refreshed), cut off at the fight's end
local function everyCastShare(r, d, fl)
  if r <= 0 or d <= 0 then return 0 end
  local gap = 1 / r
  if d < gap then return math.max(0, math.min(1, r * d - r * d * d / (2 * fl))) end
  return math.max(0, math.min(1, 1 - gap / (2 * fl)))
end

local function procShare(r, d, fl, carried)
  if r <= 0 or d <= 0 then return 0 end
  if carried then return 1 - math.exp(-r * d) end
  if fl <= d then return 1 - (1 - math.exp(-r * fl)) / (r * fl) end
  local x = math.exp(-r * d)
  return 1 - ((1 - x) / r + (fl - d) * x) / fl
end

function GS.Effects(it, ctx)
  local add, heal = {}, 0
  if not (it.fx and ctx) then return add, heal end
  local fl = math.max(1, ctx.fl)
  local pull = math.max(fl, ctx.pull or GS.PULL_EVERY)
  for _, f in ipairs(it.fx) do
    local share
    if f.use then
      local uses
      uses, share = useSchedule(f.cd or 0, f.d or 0, fl, pull)
      if f.mana then add.mp5 = (add.mp5 or 0) + f.mana * uses / fl * 5 end
      if f.heal then heal = heal + f.heal * uses / fl * (1 - (ctx.oh or 0)) end
      if f.cost then
        -- mana off the next spell (n), or off every spell while it's up
        local casts = f.n and (f.n * uses) or ((ctx.cps or 0) * share * fl)
        add.mp5 = (add.mp5 or 0) + f.cost * casts / fl * 5
      end
    else
      local rate = f.on and ((ctx.casts and ctx.casts[f.on] or 0) / fl * (f.p or 1)) or ((f.p or 0) * (ctx.cps or 0))
      rate = rate + (f.ppm or 0) / 60
      local carried = (f.d or 0) >= pull - fl
      if rate <= 0 then share = 0
      elseif (f.icd or 0) > 0 then share = math.min(1, (f.d or 0) / (f.icd + 1 / rate))
      elseif f.on and (f.p or 1) >= 1 and not carried then share = everyCastShare(rate, f.d or 0, fl)
      else share = procShare(rate, f.d or 0, fl, carried) end
    end
    for _, k in ipairs({ "healing", "int", "spirit", "mp5", "crit" }) do
      if f[k] then add[k] = (add[k] or 0) + f[k] * share end
    end
  end
  return add, heal
end

-- an item's stats in the model's units (crit and haste in %: ratings 14 and 10 per 1%);
-- with ctx, its effects too (on average over the fight), and the healing a second its
-- own heals give
function GS.Stats(it, ctx)
  local s = it.stats
  local out = { healing = s.healing or 0, int = s.int or 0, spirit = s.spirit or 0, mp5 = s.mp5 or 0,
                crit = (s.critR or 0) / 14, haste = (s.hasteR or 0) / 10 }
  local add, heal = GS.Effects(it, ctx)
  for k, v in pairs(add) do out[k] = (out[k] or 0) + v end
  return out, heal
end

-- the slots an item takes the place of (both hands for a two-hander)
GS.REPLACES = { head = { "head" }, neck = { "neck" }, shoulder = { "shoulder" }, back = { "back" }, chest = { "chest" },
  wrist = { "wrist" }, hands = { "hands" }, waist = { "waist" }, legs = { "legs" }, feet = { "feet" },
  finger = { "finger1", "finger2" }, trinket = { "trinket1", "trinket2" }, mainhand = { "weapon" },
  offhand = { "offhand" }, twohand = { "weapon", "offhand", both = true }, wand = { "wand" } }

function GS.SlotsOf(it)
  if it.slot == "twohand" or it.slot == "mainhand" then return { "weapon" } end
  if it.slot == "finger" then return { "finger1", "finger2" } end
  if it.slot == "trinket" then return { "trinket1", "trinket2" } end
  return { it.slot }
end

-- The Gear tab's filters (Gear.lua): where an item comes from (it.kinds, bits), the zones
-- it drops in (it.zones, indexes into D.zoneNames), random suffixes, and what you have.
--   f = { off = { [bit] = true } kinds left out, noZone = { ["Scholomance"] = true },
--         noSuffix = true, owned = function(it) -> true when you have it }
-- An item stays when any of its sources passes: a drop only from a zone not left out.
GS.KIND = { drop = 1, quest = 2, crafted = 4, vendor = 8, rep = 16, pvp = 32, world = 64 }
local function hasBit(n, b) return math.floor((n or 0) / b) % 2 == 1 end
function GS.Passes(D, it, f)
  if not f then return true end
  if f.noSuffix and it.suffix ~= "" then return false end
  local kinds = it.kinds or GS.KIND.world
  local off, noZone = f.off or {}, f.noZone or {}
  local from = false
  for _, b in pairs(GS.KIND) do
    if not from and hasBit(kinds, b) and not off[b] then
      if b ~= GS.KIND.drop or not next(noZone) then from = true
      else
        for _, z in ipairs(it.zones or {}) do
          if not noZone[(D.zoneNames or {})[z] or ""] then from = true end
        end
      end
    end
  end
  -- what you have last: it asks the game
  return from and (not f.owned or f.owned(it))
end

-- What you can wear at your level, on your side (PvP rewards only with pvp, an item
-- only one profession can use only when you have it), and what the filters keep.
function GS.Pool(D, side, level, pvp, profs, filter)
  local pool = {}
  for _, it in ipairs(D.items) do
    if it[side] and it.lvl <= level and (pvp or not it.pvp[side]) and (it.prof == "" or (profs and profs[it.prof]))
       and GS.Passes(D, it, filter) then
      pool[#pool + 1] = it
    end
  end
  return pool
end

-- The bonuses a set of items gives: stats, and the mana proc.
function GS.Bonuses(D, items)
  local n = {}
  for _, it in pairs(items) do if it.set ~= 0 then n[it.set] = (n[it.set] or 0) + 1 end end
  local out = {}
  for id, c in pairs(n) do
    for k, b in pairs(D.sets[id] or {}) do
      if c >= k then for stat, v in pairs(b) do if stat ~= "text" then out[stat] = (out[stat] or 0) + v end end end
    end
  end
  return out, n
end

local function add(st, d, scale)
  local o = {}
  for k, v in pairs(st) do o[k] = v end
  for k, v in pairs(d) do o[k] = (o[k] or 0) + v * scale end
  return o
end

-- args: E (the model), st (your stats now), input (S.input), rot (playstyle key),
--   D (GearData), side ("A"/"H"), level, pvp, profs ({ Tailoring = true }),
--   filter (the Gear tab's filters, GS.Passes), current ({ slot = stats now, without enchants }),
--   currentIds ({ slot = item id }),
--   weights (your stat weights now), yield (called between model runs)
function GS.Solve(a)
  local E, D = a.E, a.D
  local yield = a.yield or function() end
  local input, rot = a.input, a.rot
  local t = E.Talents(input.talents, input.settings.rules, input.settings.overrides)
  -- The spell ranks. A run that picks its own ranks costs 3-4 times as much, so the
  -- search keeps them fixed: the best for the gear being looked at, worked out again from
  -- the first rough pick and from the final one (step 5 again if they changed). What you
  -- wear now is run with its own best ranks (setNow). a.searchRanks: pick ranks in every run.
  local base0 = input.settings
  local function withRanks(r)
    if a.searchRanks or not (r and r.rankChoice) then return base0 end
    local s2 = {}
    for k, v in pairs(base0) do s2[k] = v end
    s2.rankChoice = r.rankChoice
    return s2
  end
  local r0 = E.Rotation(rot, a.st, t, base0)
  if not r0 then return nil, "no model for your playstyle" end
  local setNow = withRanks(r0)
  local set0 = setNow
  local runs = 0
  local function rotation(st)
    runs = runs + 1
    local r = E.Rotation(rot, st, t, set0)
    yield()
    return r
  end
  local function rotationNow(st)
    runs = runs + 1
    local r = E.Rotation(rot, st, t, setNow)
    yield()
    return r
  end
  local delta = {}
  for _, k in ipairs(STATS) do delta[k] = E.StatDelta(input, k) end
  local function with(st, diff)
    local s2 = st
    for _, k in ipairs(STATS) do
      local n = diff[k]
      if n and n ~= 0 then s2 = add(s2, delta[k], n) end
    end
    return s2
  end

  -- 1) your gear off: its stats, and the set bonuses your worn pieces give
  local off = {}
  for _, k in ipairs(STATS) do off[k] = 0 end
  for _, s in pairs(a.current or {}) do for _, k in ipairs(STATS) do off[k] = off[k] - (s[k] or 0) end end
  -- what you wear, matched by its random suffix too (currentKeys: "id" or "id:suffix")
  local worn = {}
  local byId, byKey = {}, {}
  for _, it in ipairs(D.items) do byId[it.id] = byId[it.id] or it; byKey[it.key] = it end
  for slot, id in pairs(a.currentIds or {}) do
    local k = a.currentKeys and a.currentKeys[slot]
    worn[slot] = (k and byKey[k]) or (not (k and k:find(":")) and byId[id]) or nil
  end
  local function wears(slot, it)
    local k = a.currentKeys and a.currentKeys[slot]
    if k then return k == it.key end
    return (a.currentIds or {})[slot] == it.id
  end
  local wornBonus = GS.Bonuses(D, worn)
  for _, k in ipairs(STATS) do off[k] = off[k] - (wornBonus[k] or 0) end
  local bare = with(a.st, off)
  -- a mana proc counts as MP5 at the fight's cast rate (for what you wear too: the
  -- game's stats never have it in them)
  local function procMp5(r, proc)
    local casts = (r.fiveSecondCasts or 0) + (r.innerFocus and r.innerFocus.casts or 0)
    for _, s in ipairs(r.steps) do casts = casts + s.casts end
    return 0.05 * proc * casts / set0.fightLength * 5
  end
  local first = r0
  -- The fight that effects which proc on casts are counted in (casts a second, and per
  -- spell), and what you wear with its effects: plain (one item swapped in) and now
  -- (with your worn set's mana proc). Worked out from your fight now, then again from
  -- the picked gear's fight (step 5 runs once more with it).
  local ctx, wornFx, wornHeal, wornBySlot, plain, now
  local wornProc = 0                -- your worn set's mana proc, as MP5 (in now)
  local function setFight(r)
    ctx = { fl = set0.fightLength, casts = {}, oh = set0.overheal and set0.overheal.FLASH or 0, pull = set0.pullEvery }
    local total = (r.fiveSecondCasts or 0) + (r.innerFocus and r.innerFocus.casts or 0)
    for _, s in ipairs(r.steps) do
      ctx.casts[s.key] = (ctx.casts[s.key] or 0) + s.casts + (s.pauseCasts or 0)
      total = total + s.casts
    end
    ctx.cps = total / math.max(1, set0.fightLength)
    -- the effects of what you wear (the game's stats never have a use's average in them)
    wornFx, wornHeal, wornBySlot = {}, 0, {}
    for slot, it in pairs(worn) do
      local add, heal = GS.Effects(it, ctx)
      wornBySlot[slot] = { add = add, heal = heal }
      for k, v in pairs(add) do wornFx[k] = (wornFx[k] or 0) + v end
      wornHeal = wornHeal + heal
    end
    local p = next(wornFx) and rotationNow(with(a.st, wornFx)) or first
    plain = { ehps = p.ehps + wornHeal, steps = p.steps, fiveSecondCasts = p.fiveSecondCasts, innerFocus = p.innerFocus }
    now, wornProc = plain, 0
    if wornBonus.proc then
      wornProc = procMp5(p, wornBonus.proc)
      local fx2 = {}
      for k, v in pairs(wornFx) do fx2[k] = v end
      fx2.mp5 = (fx2.mp5 or 0) + wornProc
      local q = rotationNow(with(a.st, fx2))
      if q then now = { ehps = q.ehps + wornHeal, steps = q.steps } end
    end
  end
  setFight(first)

  local pool = GS.Pool(D, a.side, a.level, a.pvp, a.profs, a.filter)

  local function gearOf(items)
    local g, heal = {}, 0
    for _, k in ipairs(STATS) do g[k] = 0 end
    for _, it in pairs(items) do
      local s, h = GS.Stats(it, ctx)
      for _, k in ipairs(STATS) do g[k] = g[k] + s[k] end
      heal = heal + h
    end
    local b = GS.Bonuses(D, items)
    for _, k in ipairs(STATS) do g[k] = g[k] + (b[k] or 0) end
    return g, b, heal
  end
  local cache = {}
  local function keyOf(items)
    local k = {}
    for _, s in ipairs(GS.SLOTS) do k[#k + 1] = items[s] and items[s].key or "-" end
    return table.concat(k, ",")
  end
  local function evaluate(items)
    local ck = keyOf(items)
    if cache[ck] then return cache[ck].ehps, cache[ck] end
    local g, b, heal = gearOf(items)
    local st = with(bare, g)
    local r = rotation(st)
    if r and b.proc then
      g.mp5 = g.mp5 + procMp5(r, b.proc)
      st = with(bare, g)
      r = rotation(st)
    end
    local res = { ehps = (r and r.ehps or 0) + heal, st = st, result = r }
    cache[ck] = res
    return res.ehps, res
  end
  -- stat weights as E.Weights works them out (a bump of 10, crit and haste by 1%,
  -- the same ranks as the base), one model run at a time so the work can pause
  local function weightsAt(items)
    local _, res = evaluate(items)
    local base = res.result
    if not base then return a.weights end
    local fixed = set0
    if base.rankChoice then
      fixed = {}
      for k, v in pairs(set0) do fixed[k] = v end
      fixed.rankChoice = base.rankChoice
    end
    local w = {}
    for _, stat in ipairs(E.WEIGHT_STATS) do
      local step = (stat == "crit" or stat == "haste") and 1 or 10
      runs = runs + 1
      local up = E.Rotation(rot, add(res.st, delta[stat] or E.StatDelta(input, stat), step), t, fixed)
      yield()
      w[stat] = up and (up.ehps - base.ehps) / step or 0
    end
    return w
  end
  local function value(it, w)
    local s, heal = GS.Stats(it, ctx)
    local v = heal
    for _, k in ipairs(STATS) do v = v + s[k] * (w[k] or 0) end
    return v
  end
  local function fits(items, slot, it)
    if slot == "offhand" and items.weapon and items.weapon.slot == "twohand" then return false end
    if slot == "weapon" and it.slot == "twohand" and items.offhand then return false end
    for s, x in pairs(items) do
      if s ~= slot then
        if x.id == it.id and it.unique then return false end
        if it.limit ~= 0 and x.limit == it.limit then return false end
      end
    end
    return true
  end
  local function ranked(w)
    local by = {}
    for _, it in ipairs(pool) do
      for _, s in ipairs(GS.SlotsOf(it)) do
        by[s] = by[s] or {}
        by[s][#by[s] + 1] = { it = it, v = value(it, w) }
      end
    end
    for _, l in pairs(by) do table.sort(l, function(x, y) if x.v ~= y.v then return x.v > y.v end return x.it.key < y.it.key end) end
    return by
  end
  local function greedy(by, fixed)
    local items = {}
    for k, v in pairs(fixed or {}) do items[k] = v end
    for _, s in ipairs(GS.SLOTS) do
      if not items[s] then
        for _, c in ipairs(by[s] or {}) do if fits(items, s, c.it) then items[s] = c.it; break end end
      end
    end
    if items.weapon and items.weapon.slot == "twohand" and items.offhand and not (fixed and fixed.offhand) then items.offhand = nil end
    return items
  end
  local function copy(items) local c = {} for k, v in pairs(items) do c[k] = v end return c end

  -- 2) weights, three rounds
  local w = a.weights or E.Weights(rot, bare, input)
  local by, items
  -- the ranks for gear like the picked: from a set's own fight, every rank picked; true if they changed
  local function ranksFor(set)
    if a.searchRanks then return false end
    local _, res = evaluate(set)
    runs = runs + 1
    local r = E.Rotation(rot, res.st, t, base0)
    yield()
    if not (r and r.rankChoice) then return false end
    local changed = false
    for i, v in pairs(r.rankChoice) do if (set0.rankChoice or {})[i] ~= v then changed = true end end
    if changed then set0 = withRanks(r); cache = {} end
    return changed
  end
  for _ = 1, 4 do
    by = ranked(w); items = greedy(by)
    ranksFor(items)
    w = weightsAt(items)
  end
  by = ranked(w)
  items = greedy(by)
  local best = evaluate(items)
  -- 3) a main hand and an off hand against the two-hander
  if items.weapon and items.weapon.slot == "twohand" then
    local mh = copy(items)
    mh.weapon, mh.offhand = nil, nil
    for _, c in ipairs(by.weapon or {}) do if c.it.slot == "mainhand" then mh.weapon = c.it; break end end
    mh.offhand = by.offhand and by.offhand[1] and by.offhand[1].it
    if mh.weapon and mh.offhand then
      local sc = evaluate(mh)
      if sc > best then items, best = mh, sc end
    end
  end
  -- 4) the sets, at each bonus size, then the best four two together
  local pieces = {}
  for _, it in ipairs(pool) do if D.sets[it.set] then pieces[it.set] = pieces[it.set] or {}; table.insert(pieces[it.set], it) end end
  local function forced(id, k, base)
    local list = {}
    for _, it in ipairs(pieces[id] or {}) do list[#list + 1] = { it = it, v = value(it, w) } end
    table.sort(list, function(x, y) return x.v > y.v end)
    local fixed, n = copy(base or {}), 0
    for _, p in ipairs(list) do
      if n >= k then break end
      for _, s in ipairs(GS.SlotsOf(p.it)) do
        if not fixed[s] and fits(fixed, s, p.it) then fixed[s] = p.it; n = n + 1; break end
      end
    end
    return n >= k and fixed or nil
  end
  local options = {}
  for id in pairs(pieces) do
    for k in pairs(D.sets[id]) do
      local f = forced(id, k)
      if f then
        local cand = greedy(by, f)
        local sc = evaluate(cand)
        options[#options + 1] = { id = id, k = k, sc = sc }
        if sc > best + 1e-6 then items, best = cand, sc end
      end
    end
  end
  table.sort(options, function(x, y) return x.sc > y.sc end)
  for i = 1, math.min(4, #options) do
    for j = i + 1, math.min(4, #options) do
      local x, y = options[i], options[j]
      if x.id ~= y.id then
        local f = forced(x.id, x.k)
        f = f and forced(y.id, y.k, f)
        if f then
          local cand = greedy(by, f)
          local sc = evaluate(cand)
          if sc > best + 1e-6 then items, best = cand, sc end
        end
      end
    end
  end
  -- 5) each slot's top four, one swap at a time
  local function swaps()
  w = weightsAt(items)
  by = ranked(w)
  for _, s in ipairs(GS.SLOTS) do
    for i = 1, math.min(4, #(by[s] or {})) do
      local c = by[s][i].it
      if items[s] ~= c then
        local cand = copy(items)
        cand[s] = nil
        if fits(cand, s, c) then
          cand[s] = c
          local sc = evaluate(cand)
          if sc > best + 1e-6 then items, best = cand, sc end
        end
      end
    end
  end
  end
  -- what you wear is a candidate too (when the data has all of it): never worse than that
  local function tryWorn()
    local cand, all = {}, true
    for slot, id in pairs(a.currentIds or {}) do
      local it = worn[slot]
      if it and it.lvl <= a.level then cand[slot] = it elseif id then all = false end
    end
    if all and next(cand) then
      local sc = evaluate(cand)
      if sc > best + 1e-6 then items, best = cand, sc end
    end
  end
  tryWorn()
  swaps()
  -- the picked gear's own fight: effects that proc on casts counted in it, step 5 again
  do
    local _, res0 = evaluate(items)
    if res0.result then
      local before = ctx
      setFight(res0.result)
      -- only when the casting changed enough to move an effect's worth
      local moved = math.abs(ctx.cps - before.cps) > 0.03 * math.max(before.cps, 0.01)
      for k, v in pairs(ctx.casts) do if math.abs(v - (before.casts[k] or 0)) > 0.5 then moved = true end end
      cache = {}
      if ranksFor(items) then moved = true end
      best = evaluate(items)
      if moved then tryWorn(); swaps() end
    end
  end

  -- 6) the weapons both ways, each with the rest of the gear as picked: the best
  -- two-hander, and the best main hand with the best off hand (the top three of each
  -- by the weights, judged by the whole model). The better way is the one worn.
  local rest = copy(items)
  rest.weapon, rest.offhand = nil, nil
  local function top(list, n, pred)
    local out = {}
    for _, c in ipairs(list or {}) do
      if #out >= n then break end
      if pred(c.it) then out[#out + 1] = c.it end
    end
    return out
  end
  -- seeded with the weapons already picked (steps 4-5 may have found a pair outside these top three)
  local weapons = {}
  if items.weapon then
    if items.weapon.slot == "twohand" then weapons.twohand = { item = items.weapon, hps = best }
    else weapons.onehand = { item = items.weapon, offhand = items.offhand, hps = best } end
  end
  for _, it in ipairs(top(by.weapon, 3, function(x) return x.slot == "twohand" end)) do
    local cand = copy(rest); cand.weapon = it
    local sc = evaluate(cand)
    if not weapons.twohand or sc > weapons.twohand.hps then weapons.twohand = { item = it, hps = sc } end
  end
  for _, mh in ipairs(top(by.weapon, 3, function(x) return x.slot == "mainhand" end)) do
    for _, oh in ipairs(top(by.offhand, 3, function() return true end)) do
      local cand = copy(rest); cand.weapon, cand.offhand = mh, oh
      if fits(rest, "weapon", mh) and fits(rest, "offhand", oh) then
        local sc = evaluate(cand)
        if not weapons.onehand or sc > weapons.onehand.hps then weapons.onehand = { item = mh, offhand = oh, hps = sc } end
      end
    end
  end
  local newWeapons = false
  for _, wv in pairs(weapons) do
    if wv.hps > best + 1e-6 then
      items = copy(rest)
      items.weapon, items.offhand = wv.item, wv.offhand
      best = wv.hps
      newWeapons = true
    end
  end
  -- other weapons can make another piece better (a ring with the new weapons' stats): the swaps again
  if newWeapons then
    swaps()
    local way = items.weapon and (items.weapon.slot == "twohand" and "twohand" or "onehand")
    if way then weapons[way] = { item = items.weapon, offhand = way == "onehand" and items.offhand or nil, hps = best } end
  end
  weapons.worn = items.weapon and (items.weapon.slot == "twohand" and "twohand" or "onehand")

  -- the next best per slot (by these weights), one of each item; for the weapons,
  -- the two-handers, the main hands and the off hands apart
  local alts = {}
  local taken = {}
  for _, s in ipairs(GS.SLOTS) do
    local it = items[s]
    if it then taken["n:" .. it.name] = true; taken["i:" .. it.id] = true end
  end
  for _, s in ipairs(GS.SLOTS) do
    local list, seen = {}, {}
    for k in pairs(taken) do seen[k] = true end
    if not (s == "offhand" and items.weapon and items.weapon.slot == "twohand") then
      for _, c in ipairs(by[s] or {}) do
        if #list >= 6 then break end
        if not (seen["n:" .. c.it.name] or seen["i:" .. c.it.id]) then
          seen["n:" .. c.it.name], seen["i:" .. c.it.id] = true, true
          list[#list + 1] = c.it
        end
      end
    end
    alts[s] = list
  end
  local function nextBest(list, pred, skip)
    local out, seen = {}, {}
    for _, it in ipairs(skip) do seen["n:" .. it.name], seen["i:" .. it.id] = true, true end
    for _, c in ipairs(list or {}) do
      if #out >= 6 then break end
      if pred(c.it) and not (seen["n:" .. c.it.name] or seen["i:" .. c.it.id]) then
        seen["n:" .. c.it.name], seen["i:" .. c.it.id] = true, true
        out[#out + 1] = c.it
      end
    end
    return out
  end
  local w2, w1 = weapons.twohand, weapons.onehand
  alts.twohand = nextBest(by.weapon, function(x) return x.slot == "twohand" end, { w2 and w2.item })
  alts.mainhand = nextBest(by.weapon, function(x) return x.slot == "mainhand" end, { w1 and w1.item })
  alts.offhand = nextBest(by.offhand, function() return true end, { w1 and w1.offhand })
  -- 7) each item shown: what it's worth over what you wear in its slot, on its own (the
  -- Gear tab's green arrows); a ring or trinket against the one it beats most, a
  -- two-hander against main hand and off hand
  local gains = {}
  -- With a two-hander on, a main hand or an off hand on its own means nothing (it only
  -- counts as a pair): no number for them (a.twoHandWorn, from the game).
  -- Otherwise the item swapped into what you wear: its stats and effects for the slot's,
  -- and the set bonuses that swap gains or loses (the mana proc too), against now.
  local function gainOf(it)
    local twoHand = a.twoHandWorn or (worn.weapon and worn.weapon.slot == "twohand")
    if twoHand and (it.slot == "mainhand" or it.slot == "offhand") then return { pair = true } end
    local s = GS.REPLACES[it.slot] or {}
    local options = s.both and { { "weapon", "offhand" } } or {}
    if not s.both then for _, x in ipairs(s) do options[#options + 1] = { x } end end
    local best
    for _, opt in ipairs(options) do
      local diff, heal = GS.Stats(it, ctx)
      local wearing = false
      local cand = {}
      for k, v in pairs(worn) do cand[k] = v end
      for _, slot in ipairs(opt) do
        local cur = (a.current or {})[slot] or {}
        local wf = wornBySlot[slot] or { add = {}, heal = 0 }
        for _, k in ipairs(STATS) do diff[k] = diff[k] - (cur[k] or 0) - (wf.add[k] or 0) end
        heal = heal - wf.heal
        if wears(slot, it) then wearing = true end
        cand[slot] = nil
      end
      cand[opt[1]] = it
      local d = 0
      if not wearing then
        local b = GS.Bonuses(D, cand)
        for _, k in ipairs(STATS) do diff[k] = diff[k] + (b[k] or 0) - (wornBonus[k] or 0) end
        local proc = b.proc and procMp5(plain, b.proc) or 0
        local total = {}
        for k, v in pairs(diff) do total[k] = v + (wornFx[k] or 0) end
        total.mp5 = (total.mp5 or 0) + proc
        local r = rotationNow(with(a.st, total))
        d = r and (r.ehps + wornHeal + heal - now.ehps) or 0
      end
      if not best or wearing or d > best.d then
        -- a ring or trinket: which of the two it goes over (its inventory slot)
        best = { d = d, worn = wearing, inv = #options > 1 and GS.INV[opt[1]] or nil }
      end
      if wearing then break end
    end
    return best
  end
  local shown = {}
  for _, it in pairs(items) do shown[it.key] = it end
  for _, list in pairs(alts) do for _, it in ipairs(list) do shown[it.key] = it end end
  for _, wv in pairs(weapons) do
    if type(wv) == "table" then shown[wv.item.key] = wv.item; if wv.offhand then shown[wv.offhand.key] = wv.offhand end end
  end
  for key, it in pairs(shown) do gains[key] = gainOf(it) end

  local _, res = evaluate(items)
  local _, counts = GS.Bonuses(D, items)
  return { items = items, alts = alts, hps = res.ehps, now = now.ehps, playstyle = res.result and res.result.name,
           sets = counts, runs = runs, level = a.level, weights = w, weapons = weapons, gains = gains }
end

if ns then ns.GearSolve = GS end
return GS
