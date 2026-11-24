--[[ Holy Math - Models/ConsumableRank.lua
     The Consumables tab's numbers: for each row (one flask, one elixir, one food or drink, one
     weapon oil: Models/ConsumableData.lua), what each item you can use at your level adds to
     your healing per second, best first. Through the whole fight model (E.ConsumableCompare),
     with your stats as the game shows them, so what you have on is in them already: an item
     counts in place of the one of its row you have on (its stats less that one's).

     Potions and runes are the model's (E.POTIONS): each used as often as its cooldown lets you,
     against nothing on that cooldown (E.PotionGain).

     No game calls here: what you have on comes in as auras ({ id, amount }) and your weapon's
     temporary enchant id (Consumables.lua reads them).
]]--

local _, ns = ...
local CR = {}

local KEYS = { "healing", "int", "spirit", "mp5", "crit", "mana" }

-- What you have on, by row: from your auras (a food or drink's Well Fed buff is shared by
-- many, told apart by its amount) and the weapon's temporary enchant (an oil).
-- auras: { { id = spell id, amount = the first value or nil } ... }; oil: enchant id or nil.
function CR.Active(D, auras, oil)
  local byAura = {}
  for _, it in ipairs(D.items or {}) do
    if it.row ~= "oil" then
      byAura[it.aura] = byAura[it.aura] or {}
      table.insert(byAura[it.aura], it)
    end
  end
  local active = {}
  for _, a in ipairs(auras or {}) do
    local list = byAura[a.id]
    if list then
      local pick
      if #list == 1 then pick = list[1]
      else
        for _, it in ipairs(list) do if a.amount and it.amount == a.amount then pick = it end end
      end
      -- several share the aura and its amount can't be read: the strongest of them you can use
      if not pick and not a.amount then
        for _, it in ipairs(list) do if not pick or it.lvl > pick.lvl then pick = it end end
      end
      if pick then active[pick.row] = pick end
    end
  end
  if oil and oil ~= 0 then
    for _, it in ipairs(D.items or {}) do if it.row == "oil" and it.aura == oil then active.oil = it end end
  end
  return active
end

-- The change in stats from putting it in place of the one of its row you have on.
function CR.Diff(it, active)
  local cur = active[it.row]
  local diff = {}
  for _, k in ipairs(KEYS) do diff[k] = (it.stats[k] or 0) - (cur and cur.stats[k] or 0) end
  return diff, cur
end

-- Every row's list, best first: { row = key, items = { { it, d, pct, worn } ... } }, and the
-- potion and rune rows. args: E, D, S (the addon state: st, input, rotation), auras, oil,
-- yield (called between model runs, or nil). An item you have on: d is what it gives you
-- (against none of its row), worn true.
function CR.Rank(a)
  local E, D, S = a.E, a.D, a.S
  local yield = a.yield or function() end
  local level = S.st.level or 60
  local active = CR.Active(D, a.auras, a.oil)
  local t = E.Talents(S.input.talents, S.input.settings.rules, S.input.settings.overrides)
  local base = E.Rotation(S.rotation, S.st, t, S.input.settings)
  if not base then return nil, "no model for your playstyle" end
  local out = { active = active, now = base.ehps, rows = {} }
  -- what the one of a row you have on gives you: you without it (as a share of that)
  local function worth(row)
    local d = E.ConsumableCompare(S.rotation, S.st, S.input, (CR.Diff({ row = row, stats = {} }, active)), base) or 0
    return -d, -d / math.max(1, base.ehps + d)
  end
  for _, row in ipairs(D.rows) do
    local list = {}
    for _, it in ipairs(D.byRow[row] or {}) do
      if it.lvl <= level and it.prof == 0 then
        local cur = active[row]
        if cur and cur.id == it.id then
          local d, pct = worth(row)
          list[#list + 1] = { it = it, d = d, pct = pct, worn = true }
        else
          local d, pct = E.ConsumableCompare(S.rotation, S.st, S.input, (CR.Diff(it, active)), base)
          list[#list + 1] = { it = it, d = d or 0, pct = pct or 0 }
        end
        yield()
      end
    end
    -- the one you have on is shown too, even when you couldn't pick it now (a level-1 sweet)
    local cur = active[row]
    if cur and (cur.hidden or cur.lvl > level or cur.prof ~= 0) then
      local d, pct = worth(row)
      list[#list + 1] = { it = cur, d = d, pct = pct, worn = true }
    end
    table.sort(list, function(x, y)
      if math.abs(x.d - y.d) > 1e-6 then return x.d > y.d end
      return x.it.lvl > y.it.lvl
    end)
    out.rows[#out.rows + 1] = { row = row, items = list }
  end
  -- potions and runes: each on its cooldown, against nothing there
  local inList = {}
  for _, e in ipairs(S.input.settings.potions or {}) do if (e.n or 0) > 0 then inList[e.key] = true end end
  for _, grp in ipairs({ "potion", "rune" }) do
    local list = {}
    for _, p in ipairs(E.POTIONS) do
      if p.group == grp and (p.lvl or 1) <= level then
        local d, pct = E.PotionGain(S.rotation, S.st, S.input, p.key)
        list[#list + 1] = { it = { id = p.id, name = p.name, lvl = p.lvl or 1, row = grp, potion = p }, d = d or 0,
                            pct = pct or 0, worn = inList[p.key] or nil }
        yield()
      end
    end
    table.sort(list, function(x, y)
      if math.abs(x.d - y.d) > 1e-6 then return x.d > y.d end
      return x.it.lvl > y.it.lvl
    end)
    out.rows[#out.rows + 1] = { row = grp, items = list }
  end
  return out
end

---------------------------------------------------------------------------
-- Enchants: for each slot, what each enchant adds over the one on your item there
---------------------------------------------------------------------------
-- the character window's slot for each row
CR.ENCHANT_SLOT = { head = 1, neck = 2, shoulder = 3, back = 15, chest = 5, wrist = 9, hands = 10, legs = 7, feet = 8,
  weapon = 16, twohand = 16, offhand = 17, shield = 17 }

-- Your fight's casts: a second, and the share that aren't Renew (Revelation spends its crit on
-- the next spell, and Renew can't crit).
local function castsOf(r, fl)
  local total, renew = (r.fiveSecondCasts or 0) + (r.innerFocus and r.innerFocus.casts or 0), 0
  for _, s in ipairs(r.steps or {}) do
    total = total + s.casts
    if s.key == "RENEW" then renew = renew + s.casts end
  end
  return total / math.max(1, fl), total > 0 and (1 - renew / total) or 1
end

-- A proc as the stats it gives on average over your fight (gear units: E.StatDelta's).
--   Insight: 35% a heal, then 45 s before it can again, +100% spirit for 10 s (the game's spell
--     row): up for 10 / (45 + the wait for a proc), your spirit that much more on average.
--   Revelation: your next spell crits; 8% a cast (the rate wowsims observed; the game files
--     don't state it), the next a direct heal as often as your casts are: each direct heal
--     8% x that share more likely to crit, of what wasn't a crit.
function CR.ProcStats(E, S, proc, base)
  local cps, direct = castsOf(base, S.input.settings.fightLength)
  if proc == "insight" then
    local rate = 0.35 * cps
    if rate <= 0 then return {} end
    local share = math.min(1, 10 / (45 + 1 / rate))
    local m = E.Multipliers(S.input)
    return { spirit = share * S.st.spirit / math.max(0.01, m.spirit) }, share
  elseif proc == "revelation" then
    return { crit = 8 * direct * (1 - math.min(1, S.st.crit or 0)) }, 0.08
  end
  return {}
end

-- Your enchant in each row (from the item there): { row = enchant or { id = n, unknown = true } }.
-- ids: { [slot] = enchant id } read from your item links.
function CR.ActiveEnchants(D, ids)
  local byId = {}
  for _, e in ipairs(D.enchants or {}) do byId[e.id] = byId[e.id] or {}; byId[e.id][e.row] = e end
  local out = {}
  for _, row in ipairs(D.enchantRows or {}) do
    local id = ids and ids[CR.ENCHANT_SLOT[row]]
    if id and id ~= 0 then out[row] = (byId[id] and byId[id][row]) or { id = id, unknown = true, stats = {} } end
  end
  return out
end

-- Every enchant row, best first: { row, items = { { it, d, pct, worn } ... } }.
-- args: E, D, S, ids ({ [slot] = enchant id }), yield.
function CR.RankEnchants(a)
  local E, D, S = a.E, a.D, a.S
  local yield = a.yield or function() end
  local t = E.Talents(S.input.talents, S.input.settings.rules, S.input.settings.overrides)
  local base = E.Rotation(S.rotation, S.st, t, S.input.settings)
  if not base then return nil, "no model for your playstyle" end
  local active = CR.ActiveEnchants(D, a.ids)
  local out = { active = active, now = base.ehps, rows = {} }
  local procCache = {}
  local function effective(e)
    local st = {}
    for k, v in pairs(e.stats or {}) do st[k] = v end
    if e.proc then
      procCache[e.proc] = procCache[e.proc] or CR.ProcStats(E, S, e.proc, base)
      for k, v in pairs(procCache[e.proc]) do st[k] = (st[k] or 0) + v end
    end
    return st
  end
  local function compare(diff) return E.ConsumableCompare(S.rotation, S.st, S.input, diff, base) or 0 end
  for _, row in ipairs(D.enchantRows or {}) do
    local list = {}
    local cur = active[row]
    -- what the one on now gives you: its stats are in yours (take them off), its proc isn't
    local curOff, curProc = {}, 0
    if cur and not cur.unknown then
      for k, v in pairs(cur.stats or {}) do curOff[k] = -v end
      if cur.proc then curProc = compare(effective({ stats = {}, proc = cur.proc })) end
    end
    for _, e in ipairs(D.enchantByRow and D.enchantByRow[row] or {}) do
      if cur and cur.id == e.id then
        local d = cur.proc and curProc or -compare(curOff)
        list[#list + 1] = { it = e, d = d, pct = d / math.max(1, base.ehps - d), worn = true }
      else
        local diff = {}
        for k, v in pairs(curOff) do diff[k] = v end
        for k, v in pairs(effective(e)) do diff[k] = (diff[k] or 0) + v end
        local d = compare(diff) - curProc
        list[#list + 1] = { it = e, d = d, pct = d / math.max(1, base.ehps) }
      end
      yield()
    end
    table.sort(list, function(x, y)
      if math.abs(x.d - y.d) > 1e-6 then return x.d > y.d end
      return x.it.id < y.it.id
    end)
    if #list > 0 then out.rows[#out.rows + 1] = { row = row, items = list } end
  end
  return out
end

if ns then ns.ConsumableRank = CR end
return CR
