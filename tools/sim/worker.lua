--[[ Holy Math - tools/sim/worker.lua
     One scenario of the big simulation (tools/sim/run.py runs many at once): a level-60
     priest with one set of gear, in one kind of fight. Prints JSON:
       builds     the best talent builds a search finds (hill-climbs from Holy and
                  Discipline seeds plus random restarts), with their best playstyle
       talents    what each talent in the best build is worth: the HPS lost without it
       playstyles every playstyle's HPS with the best build
       trinkets   every trinket's HPS over an empty trinket slot (its stats and effect)
       effects    every item effect: Holy Math's averaged formula (GS.Effects) against
                  an event-by-event simulation of many fights in a row

     lua5.1 tools/sim/worker.lua <gear: dungeon|preraid> <fight seconds> <seconds between pulls>
                                 <overheal: low|typical|high> [random restarts] [simulated fights] [seed]
                                 [score file]
     With a score file (a Lua file run.py writes: the scenario's gear and a list of builds),
     it only scores those builds, so builds found in other scenarios can be compared here.
     Run from the addon folder.
]]--

local GEAR, FL, PULL, OH = arg[1] or "preraid", tonumber(arg[2]) or 120, tonumber(arg[3]) or 600, arg[4] or "low"
local RESTARTS, FIGHTS, SEED = tonumber(arg[5]) or 8, tonumber(arg[6]) or 2000, tonumber(arg[7]) or 1
local SCORE_FILE = arg[8]
math.randomseed(SEED)

local E = dofile("Models/Priest.lua")
local D = dofile("Models/GearData.lua")
local GS = dofile("Models/GearSolve.lua")

---------------------------------------------------------------------------
-- JSON out
---------------------------------------------------------------------------
local function json(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    return string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", "")
  end
  if t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c)
      if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
      return string.format("\\u%04x", c:byte())
    end) .. '"'
  end
  local n = 0
  for _ in pairs(v) do n = n + 1 end
  if n == #v and (n > 0 or getmetatable(v) == "array") then
    local p = {}
    for i = 1, #v do p[i] = json(v[i]) end
    return "[" .. table.concat(p, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  local p = {}
  for _, k in ipairs(keys) do p[#p + 1] = json(k) .. ":" .. json(v[k] == nil and v[tonumber(k)] or v[k]) end
  return "{" .. table.concat(p, ",") .. "}"
end

---------------------------------------------------------------------------
-- The talent trees (Forever's priest trees: tree, row, max points; useful = the model
-- knows it; pre = needs those points in that talent first). Shadow isn't modelled.
---------------------------------------------------------------------------
local T = {
  { "twinDisciplines", "D", 0, 5, true }, { "powerInLight", "D", 0, 5 }, { "wandSpec", "D", 0, 2 },
  { "mentalStrength", "D", 1, 5, true }, { "silentResolve", "D", 1, 3 }, { "holyPrecision", "D", 1, 3 }, { "martyrdom", "D", 1, 2 },
  { "mentalAgility", "D", 2, 3, true }, { "innerFocus", "D", 2, 1, true }, { "improvedPWS", "D", 2, 3, true }, { "meditation", "D", 2, 3, true },
  { "improvedInnerFire", "D", 3, 3 }, { "improvedManaBurn", "D", 3, 2 }, { "soulWarding", "D", 3, 1, true, pre = { "improvedPWS", 3 } },
  { "penance", "D", 4, 1, true }, { "renewedHope", "D", 4, 5, true, pre = { "soulWarding", 1 } },
  { "divineAegis", "D", 5, 3, true },
  { "twilightFocus", "H", 0, 3 }, { "improvedRenew", "H", 0, 3, true }, { "holySpecialization", "H", 0, 5, true },
  { "spellWarding", "H", 1, 5 }, { "divineFury", "H", 1, 5, true },
  { "holyNova", "H", 2, 1 }, { "blessedRecovery", "H", 2, 3 }, { "inspiration", "H", 2, 3, true },
  { "holyReach", "H", 3, 2 }, { "improvedHealing", "H", 3, 3, true }, { "searingLight", "H", 3, 2, pre = { "divineFury", 5 } }, { "holyBinding", "H", 3, 1, true },
  { "litanyOfLight", "H", 4, 2, true }, { "spiritOfRedemption", "H", 4, 1 }, { "spiritualGuidance", "H", 4, 5, true },
  { "spiritualHealing", "H", 5, 3, true },
  { "prayerOfMending", "H", 6, 1, true, pre = { "spiritOfRedemption", 1 } },
}
local NAMES = {
  powerInLight = "Power in Light", wandSpec = "Wand Specialization", silentResolve = "Silent Resolve",
  holyPrecision = "Holy Precision", martyrdom = "Martyrdom", improvedInnerFire = "Improved Inner Fire",
  improvedManaBurn = "Improved Mana Burn", twilightFocus = "Twilight Focus", spellWarding = "Spell Warding",
  holyNova = "Holy Nova", blessedRecovery = "Blessed Recovery", holyReach = "Holy Reach", searingLight = "Searing Light",
  spiritOfRedemption = "Spirit of Redemption",
}
local function nameOf(k) return E.TALENT_NAMES[k] or NAMES[k] or k end
local USEFUL, BYKEY = {}, {}
for _, d in ipairs(T) do BYKEY[d[1]] = d; if d[5] then USEFUL[#USEFUL + 1] = d end end
local POINTS = 51

-- the useful ranks with the filler points the rows need (nil if it can't be done in 51)
local function fill(b)
  local full = {}
  for k, v in pairs(b) do full[k] = v end
  if (b.prayerOfMending or 0) > 0 then full.spiritOfRedemption = 1 end
  for _, d in ipairs(T) do
    local v = full[d[1]] or 0
    if v > 0 and d.pre and (full[d.pre[1]] or 0) < d.pre[2] then return nil end
  end
  for _, tree in ipairs({ "D", "H" }) do
    local row, cap = {}, {}
    for r = 0, 6 do row[r], cap[r] = 0, {} end
    for _, d in ipairs(T) do
      if d[2] == tree then
        row[d[3]] = row[d[3]] + (full[d[1]] or 0)
        if not d[5] and (not d.pre or (full[d.pre[1]] or 0) >= d.pre[2]) and d[1] ~= "spiritOfRedemption" then
          cap[d[3]][#cap[d[3]] + 1] = d
        end
      end
    end
    local deepest = -1
    for r = 0, 6 do if row[r] > 0 then deepest = r end end
    for r = 1, deepest do
      local cum = 0
      for q = 0, r - 1 do cum = cum + row[q] end
      local need = 5 * r - cum
      for q = 0, r - 1 do
        for _, d in ipairs(cap[q]) do
          while need > 0 and (full[d[1]] or 0) < d[4] do
            full[d[1]] = (full[d[1]] or 0) + 1; row[q] = row[q] + 1; need = need - 1
          end
        end
      end
      if need > 0 then return nil end
    end
  end
  local n = 0
  for _, v in pairs(full) do n = n + v end
  if n > POINTS then return nil end
  return full, n
end

-- Discipline combinations the built-in playstyles don't have, so Penance and Renewed Hope
-- builds are judged at their best
local EXTRA = {
  "HM1:PoM Pen Flash;POM,b,cd,t;PENANCE,b,cd,t;FLASH,b,fill,t",
  "HM1:PoM Pen GH;POM,b,cd,t;PENANCE,b,cd,t;GH,b,fill,t",
  "HM1:PoM Pen Heal;POM,b,cd,t;PENANCE,b,cd,t;HEAL,b,fill,t",
  "HM1:PoM Pen Renew;POM,b,cd,t;PENANCE,b,cd,t;GH,b,2pm,t;RENEW,b,fill",
  "HM1:RH Flash,rh;POM,b,cd,t;PENANCE,b,cd,t;PWS,1,cd,t;FLASH,b,fill,t",
  "HM1:RH GH,rh;POM,b,cd,t;PENANCE,b,cd,t;PWS,1,cd,t;GH,b,fill,t",
}
local custom = {}
for i, l in ipairs(EXTRA) do custom["x" .. i] = assert(E.PlaystyleImport(l)) end
E.SetPlaystyles(custom, nil)

---------------------------------------------------------------------------
-- The character: a level-60 Troll priest (Horde), the model's default buffs and
-- consumables, in this fight, with this gear
---------------------------------------------------------------------------
local HOLY = { twinDisciplines = 5, mentalStrength = 5, mentalAgility = 3, innerFocus = 1, meditation = 3,
  improvedRenew = 3, holySpecialization = 5, divineFury = 5, inspiration = 3, improvedHealing = 3, holyBinding = 1,
  litanyOfLight = 2, spiritualGuidance = 5, spiritualHealing = 3, prayerOfMending = 1 }
local DISC = { twinDisciplines = 5, mentalStrength = 5, mentalAgility = 3, innerFocus = 1, improvedPWS = 3, meditation = 3,
  soulWarding = 1, penance = 1, renewedHope = 5, divineAegis = 3,
  holySpecialization = 5, improvedRenew = 3, divineFury = 5, inspiration = 3, improvedHealing = 3 }

local function talentsOf(b)
  local t = {}
  for _, d in ipairs(USEFUL) do t[d[1]] = b[d[1]] or 0 end
  t.bindingHeal = t.holyBinding
  return t
end

-- How much of each spell's healing is wasted. Nobody knows a player's real overheal, so every
-- scenario runs at three levels: low (the addon's defaults), typical and high. Heals over time
-- waste the most, then big slow heals, then fast ones; shields and Prayer of Mending little.
local OVERHEAL = {
  low = { name = "Low overheal (Renew 25%)", RENEW = 0.25, PWS = 0.05, GH = 0.25, POH = 0.35, PENANCE = 0.25, BH = 0.25,
          FLASH = 0.25, NOVA = 0.45, POM = 0.15, LESSER = 0.25, HEAL = 0.25 },
  typical = { name = "Typical overheal (Renew 45%)", RENEW = 0.45, PWS = 0.10, GH = 0.35, POH = 0.45, PENANCE = 0.30, BH = 0.30,
              FLASH = 0.30, NOVA = 0.55, POM = 0.20, LESSER = 0.30, HEAL = 0.30 },
  high = { name = "High overheal (Renew 65%)", RENEW = 0.65, PWS = 0.15, GH = 0.45, POH = 0.55, PENANCE = 0.35, BH = 0.35,
           FLASH = 0.35, NOVA = 0.65, POM = 0.25, LESSER = 0.35, HEAL = 0.40 },
}
-- measured overheal (run.py --overheal-from: quartiles from real logs) over the guesses
if os.getenv("HM_OVERHEAL_FILE") then
  for level, vals in pairs(dofile(os.getenv("HM_OVERHEAL_FILE"))) do
    for k, v in pairs(vals) do OVERHEAL[level][k] = v end
  end
end
local ohDef = assert(OVERHEAL[OH], "overheal: low, typical or high")

local ZERO = { healing = 0, int = 0, crit = 0, haste = 0, mp5 = 0, spirit = 0, spelldamage = 0 }
local function character(gear)
  local inp = E.copy(E.DEFAULTS)
  inp.settings.rules = E.RULES; inp.settings.known = nil
  inp.settings.fightLength = FL; inp.settings.pullEvery = PULL
  inp.settings.shadowSpiritBuff = false
  for k, v in pairs(ohDef) do if k ~= "name" then inp.settings.overheal[k] = v end end
  inp.race = { human = false, troll = true, dwarf = false, gnome = false }
  inp.level = 60
  inp.talents = talentsOf(HOLY)
  inp.gear = E.copy(gear or ZERO)
  return inp
end

-- the gear: what the Gear tab picks (no PvP gear), from items up to this level, for a build
-- and playstyle: first the Holy build's Renew filler, then again for the best build the search
-- finds and its playstyle; trinkets' stats and set bonuses in, use and proc effects out
local GEARS = { dungeon = { level = 55, name = "Fresh 60: level-55 dungeon gear" },
                preraid = { level = 60, name = "Pre-raid best in slot" } }
local gearDef = assert(GEARS[GEAR], "gear: dungeon or preraid")
local picked
local function solveGear(b, rot)
  local inp = character()
  inp.talents = talentsOf(b)
  local r = GS.Solve({ E = E, st = E.Derive(inp), input = inp, rot = rot, D = D, side = "H", level = gearDef.level,
                       pvp = false, profs = {} })
  picked = r.items
end
local function gearSum(skip)
  local g, items = E.copy(ZERO), {}
  for slot, it in pairs(picked) do
    if not (skip and skip[slot]) then
      items[slot] = it
      for k, v in pairs(GS.Stats(it)) do g[k] = (g[k] or 0) + v end
    end
  end
  local b = GS.Bonuses(D, items)
  for _, k in ipairs({ "healing", "int", "spirit", "mp5" }) do g[k] = g[k] + (b[k] or 0) end
  return g
end
local GEAR_ALL, GEAR_NO_TRINKETS
local function useGear()
  GEAR_ALL = gearSum()
  GEAR_NO_TRINKETS = gearSum({ trinket1 = true, trinket2 = true })
end

---------------------------------------------------------------------------
-- Talents: score a build (its best playstyle), search, and value each talent
---------------------------------------------------------------------------
local cache = {}
local function keyOf(b)
  local p = {}
  for _, d in ipairs(USEFUL) do p[#p + 1] = tostring(b[d[1]] or 0) end
  return table.concat(p, ",")
end
local function score(b)
  local k = keyOf(b)
  if cache[k] then return cache[k].ehps, cache[k] end
  local full = fill(b)
  if not full then cache[k] = { ehps = -1 }; return -1, cache[k] end
  local inp = character(GEAR_ALL)
  inp.talents = talentsOf(b)
  local plans = E.ComparePlans(E.Derive(inp), inp)
  -- a built-in playstyle before an extra one that heals the same (PoM Pen Flash without Penance
  -- is Flash Heal filler)
  table.sort(plans, function(x, y)
    if math.abs(x.ehps - y.ehps) > 0.05 then return x.ehps > y.ehps end
    local bx, by = x.key:sub(1, 1) ~= "x", y.key:sub(1, 1) ~= "x"
    if bx ~= by then return bx end
    return x.key < y.key
  end)
  local best = plans[1]
  cache[k] = { ehps = best and best.ehps or 0, plan = best and best.name, planKey = best and best.key,
               plans = plans, full = full, b = b }
  return cache[k].ehps, cache[k]
end

local function climb(b)
  local cur = score(b)
  while true do
    local bestB, bestS = nil, cur
    for _, d in ipairs(USEFUL) do
      for v = 0, d[4] do
        if v ~= (b[d[1]] or 0) then
          local nb = E.copy(b); nb[d[1]] = v
          local s = score(nb)
          if s > bestS + 1e-6 then bestB, bestS = nb, s end
        end
      end
    end
    for _, a in ipairs(USEFUL) do
      if (b[a[1]] or 0) > 0 then
        for _, c in ipairs(USEFUL) do
          if c ~= a and (b[c[1]] or 0) < c[4] then
            local nb = E.copy(b); nb[a[1]] = nb[a[1]] - 1; nb[c[1]] = (nb[c[1]] or 0) + 1
            local s = score(nb)
            if s > bestS + 1e-6 then bestB, bestS = nb, s end
          end
        end
      end
    end
    if not bestB then return b, cur end
    b, cur = bestB, bestS
  end
end

local function split(full)
  local Dp, Hp = 0, 0
  for k, v in pairs(full) do if BYKEY[k][2] == "D" then Dp = Dp + v else Hp = Hp + v end end
  return Dp, Hp
end

local function buildOut(info)
  local Dp, Hp = split(info.full)
  local pts = {}
  for _, d in ipairs(T) do
    local v = info.full[d[1]] or 0
    if v > 0 then pts[#pts + 1] = { key = d[1], name = nameOf(d[1]), points = v, tree = d[2], filler = not d[5] } end
  end
  return { hps = info.ehps, split = Dp .. "/" .. Hp .. "/0", playstyle = info.plan, talents = pts }
end

local function pointsOf(info) local n = 0; for _, v in pairs(info.b) do n = n + v end; return n end

-- score mode: the builds run.py collected from every scenario, on this scenario's gear
if SCORE_FILE then
  local sf = dofile(SCORE_FILE)
  GEAR_ALL = sf.stats
  local out = {}
  for _, c in ipairs(sf.builds) do
    local hps, info = score(c.b)
    out[#out + 1] = { key = c.key, hps = hps, playstyle = info.plan }
  end
  print(json({ gear = GEAR, fight = FL, pull = PULL, overheal = OH, scores = out }))
  return
end

solveGear(HOLY, "renew")
useGear()

local found = {}
local function try(seed, label)
  local b = climb(seed)
  local _, info = score(b)
  local k = keyOf(b)
  if not found[k] then found[k] = { info = info, from = label } end
end
try(HOLY, "Holy seed")
try(DISC, "Discipline seed")
for i = 1, RESTARTS do
  local s = {}
  for _, d in ipairs(USEFUL) do s[d[1]] = math.random(0, d[4]) end
  local tries = 0
  while not fill(s) and tries < 200 do
    local d = USEFUL[math.random(#USEFUL)]
    if (s[d[1]] or 0) > 0 then s[d[1]] = s[d[1]] - 1 end
    tries = tries + 1
  end
  if fill(s) then try(s, "random restart " .. i) end
end
-- best first; of builds that heal the same (within 0.05 HPS), the one with fewer points
-- (points that do nothing are left out, not shown as part of the build)
local function rank()
  local ranked = {}
  for _, f in pairs(found) do ranked[#ranked + 1] = f end
  table.sort(ranked, function(a, b)
    if math.abs(a.info.ehps - b.info.ehps) > 0.05 then return a.info.ehps > b.info.ehps end
    return pointsOf(a.info) < pointsOf(b.info)
  end)
  return ranked
end
local ranked = rank()
-- the gear again, for the best build and its playstyle; every build found is scored again on it
-- (another climb from the best keeps it a local best on the new gear)
do
  local top = ranked[1].info
  solveGear(top.b, top.planKey)
  useGear()
  cache = {}
  for k, f in pairs(found) do
    local _, info = score(f.info.b)
    f.info = info
  end
  local b = climb(top.b)
  local _, info = score(b)
  if not found[keyOf(b)] then found[keyOf(b)] = { info = info, from = ranked[1].from .. ", on its own gear" } end
  ranked = rank()
end
local builds = {}
for i = 1, math.min(5, #ranked) do
  local o = buildOut(ranked[i].info); o.from = ranked[i].from
  o.key = keyOf(ranked[i].info.b)
  o.b = {}
  for k, v in pairs(ranked[i].info.b) do if v > 0 then o.b[k] = v end end
  builds[i] = o
end
local best = ranked[1].info

-- each talent of the best build: what it's worth (the build's HPS without it; the rows it
-- held up get filler points, and the playstyle is picked again)
local talents = {}
for _, d in ipairs(USEFUL) do
  local v = best.b[d[1]] or 0
  if v > 0 then
    local nb = E.copy(best.b); nb[d[1]] = 0
    local s = score(nb)
    if s < 0 and d[1] == "improvedPWS" then s = -1 end
    talents[#talents + 1] = { key = d[1], name = nameOf(d[1]), points = v, tree = d[2],
                              hps = s >= 0 and (best.ehps - s) or nil, valid = s >= 0 }
  end
end
table.sort(talents, function(a, b) return (a.hps or 1e9) > (b.hps or 1e9) end)

-- every playstyle with the best build
local playstyles = {}
for _, p in ipairs(best.plans) do playstyles[#playstyles + 1] = { name = p.name, hps = p.ehps, extra = p.key:sub(1, 1) == "x" } end

---------------------------------------------------------------------------
-- Trinkets: each over an empty slot, with the best build and its playstyle
---------------------------------------------------------------------------
local inpT = character(GEAR_NO_TRINKETS)
inpT.talents = talentsOf(best.b)
local stT = E.Derive(inpT)
local tT = E.Talents(inpT.talents, inpT.settings.rules, inpT.settings.overrides)
local rotT = E.Rotation(best.planKey, stT, tT, inpT.settings)
local casts, n = {}, (rotT.fiveSecondCasts or 0) + (rotT.innerFocus and rotT.innerFocus.casts or 0)
for _, s in ipairs(rotT.steps) do
  casts[s.key] = (casts[s.key] or 0) + s.casts + (s.pauseCasts or 0)
  n = n + s.casts
end
local ctx = { fl = FL, cps = n / FL, casts = casts, oh = inpT.settings.overheal.FLASH or 0, pull = PULL }

local function hpsOf(stats, heal)
  local any = false
  for _, v in pairs(stats) do if v ~= 0 then any = true end end
  return (any and E.Compare(best.planKey, stT, inpT, stats) or 0) + (heal or 0)
end

local trinkets = {}
for _, it in ipairs(D.items) do
  if it.slot == "trinket" and it.lvl <= 60 then
    local stats, heal = GS.Stats(it, ctx)
    local add, h = GS.Effects(it, ctx)
    trinkets[#trinkets + 1] = { id = it.id, name = it.name, lvl = it.lvl, hps = hpsOf(stats, heal),
      effect = it.fx and hpsOf(add, h) or 0, uncounted = it.use or nil, prof = it.prof ~= "" and it.prof or nil,
      side = (it.A and "A" or "") .. (it.H and "H" or ""), pvp = (it.pvp.A or it.pvp.H) or nil }
  end
end
table.sort(trinkets, function(a, b) return a.hps > b.hps end)

---------------------------------------------------------------------------
-- Effects: the averaged formula against an event-by-event simulation. Fights of FL
-- seconds start every PULL seconds; cooldowns run on between fights. A use is used at
-- the pull if it's ready, else as soon as it's ready during a fight. Casts come one
-- after another (their spacing varies by ±30%); a proc rolls on each.
---------------------------------------------------------------------------
local KEYS = { "healing", "int", "spirit", "mp5", "crit" }

-- seconds of [a, b] inside fights
local function inFights(a, b)
  local total = 0
  local k = math.max(0, math.floor(a / PULL))
  while k * PULL < b do
    local s, e = k * PULL, k * PULL + FL
    local lo, hi = math.max(a, s), math.min(b, e)
    if hi > lo then total = total + hi - lo end
    k = k + 1
  end
  return total
end

local function simulate(it)
  local up, mana, heal, saved = {}, 0, 0, 0
  local fightTime = FIGHTS * FL
  for _, f in ipairs(it.fx) do
    local uptime = 0
    if f.use then
      local ready, buffEnd = 0, -1
      for i = 0, FIGHTS - 1 do
        local s, e = i * PULL, i * PULL + FL
        local t = math.max(s, ready)
        while t < e do
          -- a use while its buff is still up only extends it
          uptime = uptime + inFights(math.max(t, buffEnd), t + (f.d or 0))
          buffEnd = math.max(buffEnd, t + (f.d or 0))
          if f.mana then mana = mana + f.mana end
          if f.heal then heal = heal + f.heal * (1 - ctx.oh) end
          if f.cost then
            if f.n then saved = saved + f.cost * f.n
            else
              -- the casts while it's up (one after another, ±30% spacing)
              local c = t + math.random() / ctx.cps
              while c < math.min(e, t + (f.d or 0)) do saved = saved + f.cost; c = c + (0.7 + 0.6 * math.random()) / ctx.cps end
            end
          end
          if (f.cd or 0) <= 0 then break end
          ready = t + f.cd
          t = ready
        end
      end
    else
      local rate = f.on and ((ctx.casts[f.on] or 0) / FL) or ctx.cps
      local chance = f.on and (f.p or 1) or (f.p or 0)
      if (f.ppm or 0) > 0 and ctx.cps > 0 then chance = chance + f.ppm / 60 / ctx.cps; rate = f.on and rate or ctx.cps end
      local icdReady, curS, curE = -1, nil, nil
      if rate > 0 and chance > 0 then
        for i = 0, FIGHTS - 1 do
          local s, e = i * PULL, i * PULL + FL
          local t = s + math.random() / rate
          while t < e do
            if t >= icdReady and math.random() < chance then
              if curE and t <= curE then curE = t + (f.d or 0)
              else
                if curS then uptime = uptime + inFights(curS, curE) end
                curS, curE = t, t + (f.d or 0)
              end
              icdReady = t + (f.icd or 0)
            end
            t = t + (0.7 + 0.6 * math.random()) / rate
          end
        end
        if curS then uptime = uptime + inFights(curS, curE) end
      end
    end
    local share = uptime / fightTime
    for _, k in ipairs(KEYS) do if f[k] then up[k] = (up[k] or 0) + f[k] * share end end
  end
  up.mp5 = (up.mp5 or 0) + (mana + saved) / fightTime * 5
  return up, heal / fightTime
end

local effects = {}
for _, it in ipairs(D.items) do
  if it.fx and it.lvl <= 60 then
    local fAdd, fHeal = GS.Effects(it, ctx)
    local sAdd, sHeal = simulate(it)
    local fH, sH = hpsOf(fAdd, fHeal), hpsOf(sAdd, sHeal)
    local fs, ss = {}, {}
    for _, k in ipairs(KEYS) do
      if (fAdd[k] or 0) ~= 0 or (sAdd[k] or 0) ~= 0 then fs[k], ss[k] = fAdd[k] or 0, sAdd[k] or 0 end
    end
    effects[#effects + 1] = { id = it.id, name = it.name, slot = it.slot, formula = fH, simulated = sH,
      diff = fH - sH, formulaStats = fs, simulatedStats = ss, formulaHeal = fHeal, simulatedHeal = sHeal }
  end
end
table.sort(effects, function(a, b) return math.abs(a.diff) > math.abs(b.diff) end)

local gearItems = {}
for slot, it in pairs(picked) do gearItems[#gearItems + 1] = { slot = slot, id = it.id, key = it.key, name = it.name } end
table.sort(gearItems, function(a, b) return a.slot < b.slot end)

print(json({
  gear = GEAR, gearName = gearDef.name, fight = FL, pull = PULL, overheal = OH, overhealName = ohDef.name,
  overhealValues = (function() local t = {}; for k, v in pairs(ohDef) do if k ~= "name" then t[k] = v end end; return t end)(),
  statsNoTrinkets = GEAR_NO_TRINKETS, restarts = RESTARTS, fights = FIGHTS, seed = SEED,
  stats = GEAR_ALL, gearItems = gearItems, castsPerSecond = ctx.cps,
  builds = builds, talents = talents, playstyles = playstyles, trinkets = trinkets, effects = effects,
}))
