--[[ Holy Math - Models/PriestMath.lua
     The Math tab's page: how every number the window shows is worked out, with
     your numbers in it, and where each input comes from. It only FORMATS what
     the model already computed (E.Spell's parts, E.ManaParts, the playstyle's
     steps, the stat bumps), so the page always adds up to what the other tabs
     show; tests/run_tests.lua checks that it does.

     E.MathPage(S, key, rank) -> rows, check
       row: { head = text, sub = (a section inside the one before) } | { note = text }
            | { label, work, value, src }
       src: "game" (read from the game now), "data" (game data via wowsims),
            "measured" (measured in game), "setting" (your setting),
            "assumption" (an assumption of the fight model), "" (worked out)
       check: the page's totals, for the tests.
]]--

local _, ns = ...
local E = ns and ns.Models and ns.Models.PRIEST
if not E then return end

local max, min, abs, floor = math.max, math.min, math.abs, math.floor

E.MATH_SOURCES = {
  game = "from the game", data = "game data", measured = "measured in game",
  setting = "your setting", assumption = "assumption", rule = "game rule", you = "typed by you",
}

local function n0(v) return string.format("%d", floor((v or 0) + 0.5)) end
local function n1(v) return string.format("%.1f", v or 0) end
local function n2(v) return string.format("%.2f", v or 0) end
local function trim(v, d)   -- up to d decimals, no trailing zeros
  local s = string.format("%." .. (d or 3) .. "f", v or 0)
  if s:find("%.") then s = s:gsub("0+$", ""):gsub("%.$", "") end
  return s
end
local function pct(v, d) return trim((v or 0) * 100, d or 1) .. "%" end

-- An editable cell's unit: how its number is shown, and how what you type is read.
-- scale/offset: shown = (value - offset) x scale (0.188 -> 18.8%, 1.15 -> +15%).
E.MATH_UNITS = {
  int   = { fmt = function(v) return n0(v) end },
  num1  = { fmt = n1 },
  num2  = { fmt = n2 },
  coef  = { fmt = function(v) return trim(v, 4) end },
  mult  = { fmt = function(v) return "x" .. trim(v, 2) end },
  sec   = { fmt = function(v) return trim(v, 2) .. " s" end },
  regen = { fmt = function(v) return n1(v) .. " per 5 s" end },
  pct   = { fmt = function(v) return pct(v, 2) end, scale = 100 },
  pct0  = { fmt = function(v) return pct(v, 1) end, scale = 100 },
  bonus = { fmt = function(v) return "+" .. pct(v - 1, 1) end, scale = 100, offset = 1 },
  perInt = { fmt = function(v) return trim(v, 4) .. "%" end },   -- already in percent
}
function E.MathFormat(unit, v)
  local u = E.MATH_UNITS[unit]
  return u and u.fmt(v) or tostring(v)
end
-- The number to put in the edit box (no unit signs).
function E.MathEditText(unit, v)
  local u = E.MATH_UNITS[unit] or {}
  return trim(((v or 0) - (u.offset or 0)) * (u.scale or 1), 4)
end
-- What you typed -> the model's number, or nil. "18.8", "18.8%", "x1.5", "1,234", "2.5 s" all read.
function E.MathParse(unit, text)
  local u = E.MATH_UNITS[unit]
  if not (u and type(text) == "string") then return nil end
  local t = text:gsub("[%s,]", ""):gsub("^[xX*]", ""):gsub("per5s$", ""):gsub("s$", ""):gsub("%%$", "")
  local v = tonumber(t)
  if not v then return nil end
  return v / (u.scale or 1) + (u.offset or 0)
end

local function clientRow(S, key, rank)
  for _, r in ipairs(S.info and S.info.client or {}) do
    if r.key == key and r.rank == rank then return r end
  end
end

-- Make a row's value an editable cell. orig: the value before you typed over it
-- (nil when it is still the game's / the model's own).
local function editable(row, id, unit, raw, orig)
  row[3] = E.MathFormat(unit, raw)
  row.edit = { id = id, unit = unit, raw = raw }
  if orig ~= nil then
    row.edit.orig, row.edit.origSrc = orig, row[4]
    row[4] = "you"
  end
  return row
end
-- A setting typed here is the same setting as on the Settings tab.
local function setting(row, path, unit, raw)
  row[3] = E.MathFormat(unit, raw)
  row.edit = { setting = path, unit = unit, raw = raw }
  return row
end

local function spellName(key, set) return E.tableFor(set)[key] and E.tableFor(set)[key].name or key end

local function statsSection(rows, S)
  local st, how = S.st, S.info and S.info.how or {}
  local was = st.orig or {}
  local add = function(r) rows[#rows + 1] = r; return r end
  local function stat(label, work, field, unit, src)
    return add(editable({ label, work, "", src }, "stat." .. field, unit, st[field], was[field]))
  end
  add({ head = "Your stats", anchor = "stats" })
  stat("Healing power", "read from the game", "healing", "int", "game")
  if (st.healingFromSpirit or 0) > 0 or was.healingFromSpirit then
    stat("  of it from spirit", pct(S.t.spiritualGuidance, 0) .. " of " .. n0(st.spirit) ..
         " spirit (Spiritual Guidance, game data); Prayer of Mending leaves it out", "healingFromSpirit", "num1", "data")
  end
  local cp = how.critParts
  local work = "read from the game"
  if cp then
    work = pct(cp.client, 2) .. " read from the game"
    if cp.talent > 0 then work = work .. " + " .. pct(cp.talent, 0) .. " Holy Specialization" end
    if cp.included then work = work .. " (Holy Specialization already in it)" end
  end
  stat("Crit on Holy spells", work, "crit", "pct", "game")
  if cp then
    local perInt = E.Multipliers(S.input).critPctPerInt
    local typed = E.OverrideFor(S.input.settings, "stat.critPerInt")
    local src = cp.perIntFrom == "game data" and "data" or (cp.perIntFrom == "measured in game" and "measured" or "assumption")
    add(editable({ "  intellect to crit", trim(1 / perInt, 1) .. " intellect per 1% crit at level " .. st.level ..
                   " (" .. (typed and "your value" or E.MATH_SOURCES[src]) .. "); used for intellect's worth",
                   "", src }, "stat.critPerInt", "perInt", perInt, typed and cp.perInt or nil))
  end
  stat("  a crit heals for", was.critMulti and "times a normal heal (your value)"
       or "times a normal heal (the usual spell crit; not yet checked in game)", "critMulti", "mult", "assumption")
  if (st.haste or 0) > 0 or was.haste then stat("Haste", "read from the game", "haste", "pct0", "game") end
  stat("Mana", "read from the game", "manaPool", "int", "game")
  local formula = 5 * (E.DATA.regen.base + E.DATA.regen.perSpirit * st.spirit)
  stat("Regen from spirit", "the game says; its formula (game data): (" .. trim(E.DATA.regen.base, 2) .. " + " ..
       n0(st.spirit) .. " spirit / " .. trim(1 / E.DATA.regen.perSpirit, 2) .. ") x 5 = " .. n1(formula),
       "oocRegen", "regen", how.regenParts and "game" or "data")
  local share = (st.oocRegen or 0) > 0 and st.combatRegen / st.oocRegen or 0
  add(editable({ "  while casting", "share of it that keeps going while you cast (Meditation and the like; from the game): " ..
                 n1(st.combatRegen) .. " per 5 s", "", "game" }, "stat.castingShare", "pct0", share, was.castingShare))
  stat("MP5", "read from the game (gear, buffs)", "mp5", "num1", "game")
end

-- The talents the model uses, once (each spell's lines say which ones it takes).
-- field, name, unit, what it does, the talent's key in your talent ranks
local TALENT_ROWS = {
  { "spiritualHealing", "Spiritual Healing", "bonus", "every heal heals more", "spiritualHealing" },
  { "impRenew", "Improved Renew", "bonus", "Renew heals more", "improvedRenew" },
  { "twinDisc", "Twin Disciplines", "bonus", "Renew, Prayer of Mending, Penance and Holy Nova heal more", "twinDisciplines" },
  { "impPWS", "Improved Power Word: Shield", "bonus", "the shield absorbs more", "improvedPWS" },
  { "holyBinding", "Holy Binding", "pct0", "Flash Heal also heals you for this share", "holyBinding" },
  { "daMulti", "Divine Aegis", "pct0", "a crit also shields for this share of the heal", "divineAegis" },
  { "renewedHopeCrit", "Renewed Hope", "pct0", "more crit with heals on the tank (its playstyle)", "renewedHope" },
  { "impHealing", "Improved Healing", "pct0", "Lesser Heal, Heal, Greater Heal, Penance, Prayer of Mending cost less", "improvedHealing" },
  { "mentalAgility", "Mental Agility", "pct0", "instant spells cost less", "mentalAgility" },
  { "soulWarding", "Soul Warding", "pct0", "Power Word: Shield costs less", "soulWarding" },
  { "litanyRefund", "Litany of Light", "pct0", "mana back when a heal follows a different one", "litanyOfLight" },
  { "divineFury", "Divine Fury", "sec", "off Heal's and Greater Heal's cast time", "divineFury" },
  { "inspiration", "Inspiration", "pct0", "more armor for the tank after your crits", "inspiration" },
}
local TALENT_NAME = {}
for _, r in ipairs(TALENT_ROWS) do TALENT_NAME[r[1]] = r[2] end
TALENT_NAME.litany = "Litany of Light (discount)"

local function talentsSection(rows, S)
  local t, tr = S.t, S.input.talents or {}
  local tWas = t.orig or {}
  local any = false
  for _, r in ipairs(TALENT_ROWS) do
    local v = t[r[1]]
    local base = r[3] == "bonus" and 1 or 0
    if type(v) == "number" and (math.abs(v - base) > 1e-9 or tWas[r[1]] ~= nil) then
      if not any then rows[#rows + 1] = { head = "Your talents", anchor = "talents" }; any = true end
      local rank = tr[r[5]]
      local work = r[4] .. ((tWas[r[1]] ~= nil) and " (your value)" or
        (" (game data" .. ((rank and rank > 0) and (", rank " .. rank) or "") .. ")"))
      local row = editable({ r[2], work, "", "data" }, "talent." .. r[1], r[3], v, tWas[r[1]])
      if r[1] == "litanyRefund" and tWas.litanyRefund == nil then
        row.help = "Mana back equal to this share of the heal's base cost, when your previous heal was a different spell: " ..
          "5% at 1/2, 10% at 2/2, as the talent's tooltip says in game."
      end
      rows[#rows + 1] = row
    end
  end
end

-- Which talents scale a spell's heal, and which cut its cost (Models/Priest.lua talentMult, costMult).
local HEAL_TALENTS = { RENEW = { "impRenew", "twinDisc", "spiritualHealing" }, PENANCE = { "twinDisc", "spiritualHealing" },
                       PWS = { "impPWS" } }
HEAL_TALENTS.POM, HEAL_TALENTS.NOVA = HEAL_TALENTS.PENANCE, HEAL_TALENTS.PENANCE
local COST_TALENTS = { PWS = { "soulWarding", "mentalAgility" }, RENEW = { "mentalAgility", "litany" },
                       GH = { "impHealing", "litany" }, POM = { "litany", "impHealing", "mentalAgility" },
                       NOVA = { "litany", "mentalAgility" } }
COST_TALENTS.HEAL, COST_TALENTS.LESSER, COST_TALENTS.PENANCE = COST_TALENTS.GH, COST_TALENTS.GH, COST_TALENTS.GH

-- One spell rank, worked out. `step`: its line in the fight (then the numbers are
-- the fight's own: its Litany of Light share, Renewed Hope); nil for a rank you
-- picked in Your spells that the playstyle doesn't cast (then: as in Your spells).
local function spellSection(rows, S, key, rank, step, why)
  local st, t, set = S.st, S.t, S.input.settings
  local def = E.tableFor(set)[key]
  local top = def and E.MaxRank(key, st.level, set.known, set)
  if not (def and top) then return nil end
  rank = min(max(1, rank or top), top)
  local add = function(r) rows[#rows + 1] = r; return r end
  local fset = set
  local base = S.weights and S.weights.base
  if step and base and base.litanyShare then
    fset = {}
    for k, v in pairs(set) do fset[k] = v end
    fset.litanyShare = base.litanyShare
  end
  local heal, cost, time, sp = E.CastValue(key, rank, st, t, fset)
  local p = sp.parts
  local rh = step and step.rh
  local cr = clientRow(S, key, rank)
  add({ head = def.name .. " rank " .. rank .. (why and (": " .. why) or ""), sub = true, anchor = "spell:" .. key .. ":" .. rank })

  -- base heal and coefficient (read from the game's tooltip; the game data otherwise)
  local fromGame = function(f) return cr and (cr[f] == "client" or cr[f] == "earlier") end
  local bw
  if p.baseCalc and abs(p.baseCalc - p.base) > 0.05 then
    bw = "from the game's tooltip (game data: " .. n1(p.baseCalc) .. ")"
  elseif p.ppl and p.ppl > 0 then
    local lv = (p.ml and p.ml > 0) and min(st.level, p.ml) or st.level
    bw = "game data: " .. trim(p.bp, 1) .. " + " .. trim(p.ppl, 2) .. " per level x " .. (lv - p.bl) ..
         " levels (" .. p.bl .. " to " .. lv .. ")"
  else
    bw = "game data"
  end
  if cr and cr.client then
    local yours = next(set.overrides or {}) ~= nil and abs(sp.heal / sp.bodies - cr.client) > 1
    if yours then bw = bw .. "; the game's tooltip (" .. n0(cr.client) .. ") doesn't know your typed values"
    elseif abs(cr.client - cr.model) <= 1 or (cr.after and abs(cr.client - cr.after) <= 1) then
      bw = bw .. "; heal matches the game's tooltip (" .. n0(cr.client) .. ")"
    elseif cr.tooltipFull then bw = bw .. "; the game's tooltip shows this rank at full power"
    else bw = bw .. "; differs from the game's tooltip (" .. n0(cr.client) .. ")" end
  end
  add({ "Base heal", bw, n1(p.base), fromGame("baseFrom") and "game" or "data" })
  if p.power < 0.999 then
    local rk = def.ranks[rank]
    local cap = (rk.ml and rk.ml > 0) and rk.ml or (rk.lvl + 5)
    add({ "Coefficient", trim(p.fullCoeff, 4) .. " (game data) x " .. pct(p.power, 0) .. " downranking: -5% a level past " ..
          (cap + 12) .. " (max level " .. cap .. " + 12), at least 10%", trim(sp.coeff, 4), "rule" })
    if cr and cr.tooltipFull then
      add({ note = "The game's tooltip shows this rank at full power; its real heals have the penalty (Renew rank 1 ticks for it)." })
    end
  else
    add({ "Coefficient", "share of your healing power the rank gets (game data)", trim(sp.coeff, 4), "data" })
  end

  -- the heal
  local hp = n0(p.healing)
  local names, factors = {}, {}
  for _, f in ipairs(HEAL_TALENTS[key] or { "spiritualHealing" }) do
    local v = t[f] or 1
    if abs(v - 1) > 1e-9 then names[#names + 1] = TALENT_NAME[f]; factors[#factors + 1] = trim(v, 4) end
  end
  local tw = #names > 0 and (table.concat(names, " x ") .. ": " .. table.concat(factors, " x ")) or "none that change this heal"
  add({ "Talents", tw, "x" .. trim(p.talentMult, 4), "data" })
  local hpWork = hp
  if key == "POM" and abs(p.healing - st.healing) > 0.5 then hpWork = "(" .. n0(st.healing) .. " - " .. n1(st.healingFromSpirit) .. ")" end
  local work = "(" .. n1(p.base) .. " + " .. trim(sp.coeff, 4) .. " x " .. hpWork .. " healing power) x " .. trim(p.talentMult, 4)
  if not p.shield and sp.bodies ~= 1 then work = work .. " x " .. trim(sp.bodies, 2) .. " (Holy Binding: you too)" end
  add({ p.shield and "Absorb" or "Heal, no crit", work, n1(sp.heal), "" })
  local expected, aegis = sp.expected, sp.aegis
  if not p.shield then
    if rh then
      expected, aegis = sp.expectedRH, sp.aegisRH
      add({ "With crits", n1(sp.heal) .. " x (1 + (" .. pct(p.crit, 2) .. " + " .. pct(t.renewedHopeCrit, 0) ..
            " Renewed Hope) x " .. trim(p.critMulti - 1, 2) .. ")", n1(expected), "" })
    else
      add({ "With crits", n1(sp.heal) .. " x (1 + " .. pct(p.crit, 2) .. " crit x " .. trim(p.critMulti - 1, 2) .. ")", n1(expected), "" })
    end
    if (p.daMulti or 0) > 0 then
      add({ "Divine Aegis", n1(sp.heal) .. " x " .. pct(rh and (p.crit + t.renewedHopeCrit) or p.crit, 2) .. " crit x " ..
            pct(p.daMulti, 0), n1(aegis), "" })
    end
  end
  if sp.targets ~= 1 then
    if key == "POM" then
      add(setting({ "Targets", "Prayer of Mending bounces (your setting)", "", "setting",
                    help = "How many people Prayer of Mending heals before it runs out (it can jump up to 5 times)." },
                  { "pomHits" }, "int", sp.targets))
    else
      add({ "Targets", trim(sp.targets, 0) .. " people (the spell's rule)", "x" .. trim(sp.targets, 1), "rule" })
    end
  end
  local oh = set.overheal[key] or 0
  add(setting({ "Overheal", "healing wasted on players already at full health (your setting)", "", "setting",
                help = E.OverhealHelp(def.name) }, { "overheal", key }, "pct0", oh))
  local perCast = (expected * (1 - oh) + aegis * (1 - (set.overheal.PWS or 0))) * sp.targets
  local w = n1(expected) .. " x (1 - " .. pct(oh, 0) .. ")"
  if aegis > 0 then w = w .. " + " .. n1(aegis) .. " Aegis x (1 - " .. pct(set.overheal.PWS or 0, 0) .. ")" end
  if sp.targets ~= 1 then w = "(" .. w .. ") x " .. trim(sp.targets, 1) end
  add({ "Heal per cast", w, n0(perCast), "" })

  -- mana: the rank's cost, the talents that cut it, Litany of Light
  local cut = {}
  for _, f in ipairs(COST_TALENTS[key] or { "litany" }) do
    if (t[f] or 0) > 1e-9 then cut[#cut + 1] = pct(t[f], 1) .. " " .. TALENT_NAME[f] end
  end
  local mw = trim(p.rankCost, 1) .. (fromGame("costFrom") and " (the game's cost)" or " (game data)")
  if #cut > 0 then mw = mw .. " x (1 - " .. table.concat(cut, " - ") .. ")" end
  if p.set4 > 0 then mw = mw .. " - " .. p.set4 .. " (dungeon set)" end
  local before = p.rankCost * p.costMult - p.set4
  add({ "Mana", mw, n1(before), fromGame("costFrom") and "game" or "data" })
  if p.refund > 0 then
    add({ "  Litany of Light", trim(p.rankCost, 1) .. " x " .. pct(p.litanyRefund, 1) .. " back x " .. pct(p.litanyShare, 0) ..
          (step and " of its casts follow a different heal in this fight" or " of casts after a different heal (your setting, on its own)"),
          "-" .. n1(p.refund), "" })
    add({ "  mana per cast", n1(before) .. " - " .. n1(p.refund), n1(cost), "" })
  end

  -- time
  local gcd = 1.5 / (1 + st.haste)
  local cw
  if p.castBase == "gcd" then cw = "instant: one global cooldown, 1.5 s"
  elseif p.castBase == "gh" then cw = "(3 s - " .. trim(p.divineFury, 2) .. " s Divine Fury)"
  else
    cw = trim(p.castBase, 2) .. (fromGame("castFrom") and " s (the game's)" or " s (game data)")
    if p.divineFury > 0 then cw = "(" .. cw .. " - " .. trim(p.divineFury, 2) .. " s Divine Fury)" end
  end
  if (st.haste or 0) > 0 then cw = cw .. " / (1 + " .. pct(st.haste, 1) .. " haste)" end
  if sp.cast < gcd - 1e-9 then cw = cw .. "; at least a global cooldown" end
  add({ "Time per cast", cw, trim(time, 2) .. " s", fromGame("castFrom") and "game" or "data" })
  add({ "Per mana", n0(perCast) .. " / " .. n1(cost), cost > 0 and n2(perCast / cost) or "free", "" })
  add({ "Per second", n0(perCast) .. " / " .. trim(time, 2) .. " s", n0(perCast / time), "" })
  return { heal = perCast, cost = cost, time = time, key = key, rank = rank, step = step }
end

local MANA_LABELS = {
  pool = { "Your mana", "full at the pull", "game" },
  mp5 = { "MP5", "%s per 5 s x %s ticks", "game" },
  casting = { "Spirit regen while casting", "%s per 5 s x %s ticks", "game" },
  potions = { "Mana potions", "%s x %s (one every 2 minutes)", "assumption" },
  manaTide = { "Mana Tide", "%s x %s (4 ticks of 290, one every 5 minutes)", "assumption" },
  innervate = { "Innervate", "%s x %s", "assumption" },
  powerInfusion = { "Power Infusion you cast", "%s x %s", "assumption" },
}

local LIMITS = { cooldown = "as often as its cooldown allows", mana = "until the mana is spent", time = "fills the time left" }

local function fightSection(rows, S)
  local st, t, set, w = S.st, S.t, S.input.settings, S.weights
  local base = w and w.base
  if not base then return nil end
  local fl = set.fightLength
  local add = function(r) rows[#rows + 1] = r end
  add({ head = "The fight: " .. base.name .. ", " .. fl .. " s", anchor = "fight" })
  add({ note = "Healing you can sustain if there is always someone to heal; mana is the limit. " ..
    "What one cast of each spell heals is worked out under the fight." })
  local manaSum = 0
  for _, part in ipairs(E.ManaParts(st, t, set)) do
    manaSum = manaSum + part.mana
    local lab = MANA_LABELS[part.key]
    if part.key == "pool" then
      add({ lab[1], lab[2], n0(part.mana), lab[3] })
    elseif abs(part.mana) > 0.5 then
      local a = part.ticks and trim(part.per, 1) or trim(part.n, 2)
      local b = part.ticks and trim(part.ticks, 1) or trim(part.per, 1)
      add({ lab[1], string.format(lab[2], a, b), n0(part.mana), lab[3] })
    end
  end
  add({ "Mana for the fight", "", n0(manaSum), "" })

  -- each line: casts x heal per cast x (1 - overheal) [+ Divine Aegis x (1 - its overheal)];
  -- worst = how far the printed terms are from the value (the tests keep it at 0)
  local total, worst = 0, 0
  local ohPWS = set.overheal.PWS or 0
  local function terms(casts, perCast, oh, aegis)
    local text = string.format("%s x %s x (1 - %s overheal)", n1(casts), n0(perCast), pct(oh, 0))
    if (aegis or 0) > 0.005 then
      text = text .. string.format(" + Divine Aegis %s x %s x (1 - %s)", n1(casts), n0(aegis), pct(ohPWS, 0))
    end
    return text, casts * perCast * (1 - oh) + casts * (aegis or 0) * (1 - ohPWS)
  end
  for _, s in ipairs(base.steps) do
    if s.enabled and s.casts > 0.01 then
      local stepEff = s.eff - (s.pauseCasts and base.pauseEff or 0)
      total = total + stepEff
      local why = LIMITS[s.limit] or ""
      if s.limit == "cooldown" and s.cap then why = "every " .. s.cap .. " s" end
      local text, shown = terms(s.casts, s.perCast, s.overheal or 0, s.aegis)
      worst = max(worst, abs(shown - stepEff))
      text = text .. string.format("; %s mana and %s s a cast, %s", n1(s.cost), trim(s.time, 2), why)
      if s.rh then text = text .. "; heals on the tank crit " .. pct(t.renewedHopeCrit, 0) .. " more (Renewed Hope)" end
      add({ spellName(s.key, set) .. " " .. s.rank, text, n0(stepEff), "" })
    end
  end
  add({ "  mana left", "the fight's mana, less what these casts cost", n0(base.manaLeft), "" })
  if (base.fiveSecondCasts or 0) > 0.01 then
    total = total + base.pauseEff
    local fill
    for _, s in ipairs(base.steps) do if s.fill then fill = s end end
    local text, shown = terms(base.fiveSecondCasts, base.pauseHeal, fill and fill.overheal or 0, base.pauseAegis)
    worst = max(worst, abs(shown - base.pauseEff))
    add({ "Pauses to regenerate", string.format("%s s not casting x %s / %s s a cycle = %s more casts: %s",
          n0(base.pauseTime), pct(set.imperfectPlay, 1), n1(base.pauseCycle), n1(base.fiveSecondCasts), text),
          n0(base.pauseEff), "assumption" })
    add({ note = "Out of mana before the fight ends: the time left is spent in cycles of waiting out the 5-second rule, " ..
          "regenerating the filler's mana and casting it. " .. pct(set.imperfectPlay, 1) ..
          " = how much of that time you really use this way (Downtime used, at the bottom)." })
  end
  if base.innerFocus then
    local f = base.innerFocus
    total = total + f.eff
    local text, shown = terms(f.casts, f.perCast, set.overheal.POH or 0, f.aegis)
    worst = max(worst, abs(shown - f.eff))
    add({ "Inner Focus", string.format("free Prayers of Healing (one every 3 minutes), +25%% crit: %s", text),
          n0(f.eff), "assumption" })
  end
  if (base.inspiration or 0) > 0 then
    local ip = base.inspirationParts
    total = total + base.inspiration * fl
    add({ "Inspiration", string.format("tank armour %s -> %s for %s of the fight: %s damage a second it doesn't take",
          n0(ip.armor), n0(ip.armorUp), pct(ip.uptime, 0), n1(base.inspiration)), n0(base.inspiration * fl), "assumption" })
  end
  add({ "Healing in the fight", "after overheal", n0(total), "" })
  add({ "Healing per second", n0(total) .. " / " .. fl .. " s", n0(total / fl), "" })
  if base.litanyShare then
    local parts = {}
    for key, share in pairs(base.litanyShare) do parts[#parts + 1] = spellName(key, set) .. " " .. pct(share, 0) end
    table.sort(parts)
    add({ note = "Litany of Light in this fight: the share of casts that follow a different heal: " .. table.concat(parts, ", ") .. "." })
  end
  return { mana = manaSum, eff = total, ehps = total / fl, worst = worst }
end

local STAT_LABELS = {
  healing = "Healing power", int = "Intellect", spirit = "Spirit", mp5 = "MP5", crit = "Crit", haste = "Haste",
}

local function statSection(rows, S)
  local w = S.weights
  if not (w and w.base) then return end
  local add = function(r) rows[#rows + 1] = r end
  local h = w.healing ~= 0 and w.healing or 1
  add({ head = "Stat values" })
  add({ note = "Each stat: the whole fight run again with that stat raised, same spell ranks. Worth = its gain / healing power's." })
  for _, stat in ipairs({ "healing", "int", "spirit", "mp5", "crit", "haste" }) do
    local step = w[stat .. "Step"] or 1
    local d = E.StatDelta(S.input, stat)
    local bump
    if stat == "crit" or stat == "haste" then bump = "+1% " .. STAT_LABELS[stat]:lower()
    else bump = "+" .. trim(step, 0) .. " " .. STAT_LABELS[stat]:lower() end
    local extra = {}
    if stat == "int" then
      extra[#extra + 1] = "+" .. n0(d.manaPool * step) .. " mana"
      extra[#extra + 1] = "+" .. trim(d.crit * step * 100, 3) .. "% crit"
    elseif stat == "spirit" then
      if (d.healing or 0) > 0 then extra[#extra + 1] = "+" .. n1(d.healing * step) .. " healing" end
      extra[#extra + 1] = "+" .. n1(d.oocRegen * step) .. " regen"
    end
    local work = bump .. (#extra > 0 and (" (" .. table.concat(extra, ", ") .. ")") or "") ..
      ": " .. n1(w.base.ehps) .. " -> " .. n1(w[stat .. "Up"]) .. " HPS"
    add({ STAT_LABELS[stat], work, stat == "healing" and "1.00" or n2(w[stat] / h), "" })
  end
end

-- Overheal per spell, in the order the Settings tab had them.
E.OVERHEAL_ORDER = { "RENEW", "GH", "FLASH", "HEAL", "POH", "POM", "PWS", "PENANCE", "NOVA", "LESSER" }
function E.OverhealHelp(name)
  return "How much of " .. name .. "'s healing you expect to land on players who are already " ..
    "at full health, and so be wasted. The higher this is, the less " .. name .. " is worth."
end

local function assumptionsSection(rows, S)
  local set, st = S.input.settings, S.st
  local add = function(r) rows[#rows + 1] = r end
  add({ head = "The fight's other assumptions", anchor = "settings" })
  add({ note = "Your settings (overheal is in Your spells, at the top). Right-click one to put back its starting value." })
  add(setting({ "Fight length", "how long the fights you heal usually last", "", "setting",
                help = "In long fights you run out of mana, so mana (MP5, spirit, intellect) is worth more; " ..
                       "in short fights healing power counts most. A typical raid boss: about 2 minutes." },
              { "fightLength" }, "sec", set.fightLength))
  add(setting({ "Downtime used", "out of mana, how much of the time left you spend regenerating and casting again (an assumption)",
                "", "assumption",
                help = "When your mana runs out before the fight ends, the time left is spent waiting out the 5-second " ..
                       "rule, regenerating and casting the filler again. This is how much of that time you really use " ..
                       "that way; the rest goes to moving, waiting for someone to need a heal, and so on. 100% = all of it." },
              { "imperfectPlay" }, "pct0", set.imperfectPlay))
  if (S.t.litanyRefund or 0) > 0 then
    add(setting({ "Litany of Light, on its own", "share of a spell's casts after a different heal, in Your spells " ..
                  "(the fight works out its own)", "", "assumption",
                  help = "Your spells looks at each spell on its own, so it can't know how often you switch spells; " ..
                         "it assumes this share. The fight above counts it from its own casts." },
                { "litanyAlternation" }, "pct0", set.litanyAlternation or 0.5))
  end
  local base = S.weights and S.weights.base
  local caps = {}
  for _, s in ipairs(base and base.steps or {}) do
    if s.enabled and s.cap and not s.fill then caps[#caps + 1] = spellName(s.key, set) .. " every " .. s.cap .. " s" end
  end
  if #caps > 0 then
    add({ "Playstyle", base.name .. ": at most " .. table.concat(caps, ", ") .. "; the rest is filler", "", "assumption" })
  end
end

-- Your spells: every healing spell you know, one line each (its highest rank),
-- with its overheal - a setting for the whole spell, every rank - in the value
-- cell. A spell in `expanded` has all its ranks under it, highest first; the rank
-- that heals the most per point of mana is the most efficient. Rows:
--   { "Spell", "", "Overheal", "", tbl = "cols" }      the table's column titles
--   { name, "", overheal, "setting", tbl = "spell", spell = {...}, edit = ... }
--   { "Rank N", "", "", "", tbl = "rank", spell = {...}, rank = {...} }
local function spellsSection(rows, S, expanded)
  local set = S.input.settings
  rows[#rows + 1] = { head = "Your spells", anchor = "spells" }
  rows[#rows + 1] = { note = "Every healing spell you know, with your stats now. Click a spell for all its ranks. " ..
    "Overheal is set per spell, for all its ranks. The spells the fight casts are worked out below." }
  rows[#rows + 1] = { "Spell", "", "Overheal", "", tbl = "cols" }
  for _, sr in ipairs(S.spells or {}) do
    local row = setting({ sr.name, "healing wasted on players already at full health, for every rank", "", "setting",
                          help = E.OverhealHelp(sr.name) }, { "overheal", sr.key }, "pct0", set.overheal[sr.key] or 0)
    row.tbl, row.spell, row.open = "spell", sr, expanded and expanded[sr.key] and true or false
    row.tipTitle = "Overheal: " .. sr.name
    rows[#rows + 1] = row
    if row.open then
      local ok, ranks = pcall(E.SpellRanks, sr.key, S.st, S.t, set)
      for _, rk in ipairs(ok and ranks or {}) do
        rows[#rows + 1] = { "Rank " .. rk.rank, "", "", "", tbl = "rank", spell = sr, rank = rk }
      end
    end
  end
end

-- A setting typed on the sheet: its allowed range (and whole numbers only?).
E.MATH_SETTINGS = {
  fightLength = { 10, 3600, true }, pomHits = { 1, 5, true }, overheal = { 0, 0.95 },
  imperfectPlay = { 0, 1 }, litanyAlternation = { 0, 1 },
}
-- The value to store for a setting, or nil if it can't be used.
function E.MathSettingValue(path, v)
  local r = type(path) == "table" and E.MATH_SETTINGS[path[1]]
  if not (r and type(v) == "number" and v == v) then return nil end
  if r[3] then v = floor(v + 0.5) end
  if v < r[1] or v > r[2] then return nil end
  return v
end

-- A readable name for one of your values (the window's list of them).
local STAT_NAMES = {
  healing = "Healing power", healingFromSpirit = "Healing power from spirit", crit = "Crit on Holy spells",
  critMulti = "A crit heals for", haste = "Haste", manaPool = "Mana", mp5 = "MP5", oocRegen = "Regen from spirit",
  castingShare = "Regen while casting", critPerInt = "Intellect to crit",
}
local TALENT_NAMES = {
  impRenew = "Improved Renew", twinDisc = "Twin Disciplines", spiritualHealing = "Spiritual Healing",
  impPWS = "Improved Power Word: Shield", soulWarding = "Soul Warding", mentalAgility = "Mental Agility",
  impHealing = "Improved Healing", litany = "Litany of Light (discount)", litanyRefund = "Litany of Light",
  daMulti = "Divine Aegis", divineFury = "Divine Fury",
}
local SPELL_FIELDS = { base = "base heal", coeff = "coefficient", power = "downranking", cost = "cost", cast = "cast time" }
function E.OverrideLabel(id)
  local kind, rest = tostring(id):match("^(%a+)%.(.+)$")
  if kind == "stat" then return STAT_NAMES[rest] or rest end
  if kind == "talent" then return TALENT_NAME[rest] or TALENT_NAMES[rest] or rest end
  if kind == "spell" then
    local key, rank, f = rest:match("^(%u+)%.(%d+)%.(%a+)$")
    if key then return spellName(key) .. " rank " .. rank .. ": " .. (SPELL_FIELDS[f] or f) end
  end
  return tostring(id)
end
-- How to show one of your values: its unit.
local ID_UNITS = { healing = "int", healingFromSpirit = "num1", crit = "pct", critMulti = "mult", haste = "pct0",
                   manaPool = "int", mp5 = "num1", oocRegen = "regen", castingShare = "pct0", critPerInt = "perInt",
                   base = "num1", coeff = "coef", power = "pct0", cost = "num1", cast = "sec",
                   divineFury = "sec", impRenew = "bonus", twinDisc = "bonus", spiritualHealing = "bonus", impPWS = "bonus" }
function E.OverrideUnit(id)
  local last = tostring(id):match("([%a]+)$")
  return ID_UNITS[last] or "pct0"
end

-- Why a spell is in the fight: its line's limit.
local function stepWhy(s)
  if s.fill then return "the filler, whenever nothing else is due" end
  if s.cap then return ((s.tank or 0) > 0 and "on the tank, " or "") .. "at most every " .. s.cap .. " s" end
  return nil
end

-- The whole sheet. key, rank (the tests only): also work out that rank, when the
-- playstyle doesn't cast it, so every rank's section can be checked against the
-- model. expanded: spell key -> its ranks are open in Your spells.
-- check: the page's numbers, for the tests.
function E.MathPage(S, key, rank, expanded)
  local rows = {}
  if not (S and S.st and S.input) then return rows, {} end
  local check = { spells = {} }
  spellsSection(rows, S, expanded)
  statsSection(rows, S)
  talentsSection(rows, S)
  local base = S.weights and S.weights.base
  local inFight, steps = {}, {}
  for _, s in ipairs(base and base.steps or {}) do
    local id = s.key .. ":" .. s.rank
    if s.enabled and s.casts > 0.01 and not inFight[id] then inFight[id] = s; steps[#steps + 1] = s end
  end
  local set = S.input.settings
  -- the fight first (casts x heal per cast = HPS), then one cast of each of its spells
  check.fight = fightSection(rows, S)
  if base then
    rows[#rows + 1] = { head = "One cast of each spell the fight casts", anchor = "casts" }
    rows[#rows + 1] = { note = base.name .. " casts these. Each works out what one cast heals, costs and takes, " ..
      "with your stats; the fight above counts the casts." }
  end
  if key then
    local def = E.tableFor(set)[key]
    local top = def and E.MaxRank(key, S.st.level, set.known, set)
    if top then
      rank = min(max(1, rank or top), top)
      if not inFight[key .. ":" .. rank] then
        check.spell = spellSection(rows, S, key, rank, nil, "not cast in this fight")
      end
    end
  end
  for _, s in ipairs(steps) do
    local c = spellSection(rows, S, s.key, s.rank, s, stepWhy(s))
    check.spells[#check.spells + 1] = c
    if key and s.key == key and s.rank == rank then check.spell = c end
  end
  if not check.spell then check.spell = check.spells[1] end
  check.anchor = check.spell and ("spell:" .. check.spell.key .. ":" .. check.spell.rank)
  statSection(rows, S)
  assumptionsSection(rows, S)
  return rows, check
end

return E
