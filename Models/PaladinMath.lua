--[[ Holy Math - Models/PaladinMath.lua
     The Math tab's page for a Holy Paladin: how every number the window shows is worked
     out, with your numbers in it, and where each input comes from. The same page as
     Models/PriestMath.lua's (the same rows and units, so Options.lua draws either), filled
     from the paladin model's own working (E.Spell's parts, E.ManaParts, the fight's steps).

     Also the Stats tab's fight settings for a paladin (E.FIGHT_ROWS).
]]--

local _, ns = ...
local E = ns and ns.Models and ns.Models.PALADIN
if not E then return end

local max, min, abs, floor = math.max, math.min, math.abs, math.floor

E.MATH_SOURCES = {
  game = "from the game", data = "game data", measured = "measured in game",
  setting = "your setting", assumption = "assumption", rule = "game rule", you = "typed by you",
}

local function n0(v) return string.format("%d", floor((v or 0) + 0.5)) end
local function n1(v) return string.format("%.1f", v or 0) end
local function n2(v) return string.format("%.2f", v or 0) end
local function trim(v, d)
  local s = string.format("%." .. (d or 3) .. "f", v or 0)
  if s:find("%.") then s = s:gsub("0+$", ""):gsub("%.$", "") end
  return s
end
local function pct(v, d) return trim((v or 0) * 100, d or 1) .. "%" end

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
  perInt = { fmt = function(v) return trim(v, 4) .. "%" end },
}
function E.MathFormat(unit, v)
  local u = E.MATH_UNITS[unit]
  return u and u.fmt(v) or tostring(v)
end
function E.MathEditText(unit, v)
  local u = E.MATH_UNITS[unit] or {}
  return trim(((v or 0) - (u.offset or 0)) * (u.scale or 1), 4)
end
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

local function editable(row, id, unit, raw, orig)
  row[3] = E.MathFormat(unit, raw)
  row.edit = { id = id, unit = unit, raw = raw }
  if orig ~= nil then
    row.edit.orig, row.edit.origSrc = orig, row[4]
    row[4] = "you"
  end
  return row
end
local function setting(row, path, unit, raw)
  row[3] = E.MathFormat(unit, raw)
  row.edit = { setting = path, unit = unit, raw = raw }
  return row
end

local function spellName(key, set) return E.tableFor(set)[key] and E.tableFor(set)[key].name or key end

function E.OverhealHelp(name)
  return "How much of " .. name .. "'s healing you expect to land on players who are already " ..
    "at full health, and so be wasted. The higher this is, the less " .. name .. " is worth."
end
E.OVERHEAL_ORDER = { "FLASH", "HL", "SHOCK", "VIGIL" }

local OATH_HELP = "The share of your Flash of Light, Holy Light and Holy Shock casts that land on the ally your " ..
  "Oath of Light is sworn to (usually the tank). On them, Holy Light heals up to 400 more, Flash of Light 115 " ..
  "and Holy Shock 230 (at level 60, times the rank's coefficient: a low rank gets little); on anyone else Holy Shock crits more with Boundless Light. 0% if you have " ..
  "no Oath of Light."
local VIGIL_HELP = "How many people one Light's Vigil heals: the party of the ally you put it on, 5 for a full " ..
  "party. Set fewer for a smaller group. Overheal is then for those of them already at full health."

-- The Stats tab's "Your fight" rows (Options.lua draws them): steppers and switches.
E.FIGHT_ROWS = {
  { "oath", "Heals on your Oath's target", OATH_HELP, "oathShare", 0, 1, 0.1, function(v) return pct(v, 0) end },
  { "vigil", "People reached by Light's Vigil", VIGIL_HELP, "vigilHits", 1, 5, 1, tostring, default = 5 },
  { "tides", "Mana Tide totems", "Shaman Mana Tide Totems that reach you in a fight. Each restores about 1,160 mana, " ..
      "once every 5 minutes. Set 0 if your group has no shaman.", "manaTidesInGroup", 0, 3, 1, tostring },
}
E.FIGHT_SUMMARY = "the fight, your Oath's target, Light's Vigil, Mana Tide, potions"
E.STAT_NOTES = { Spirit = "mana regen (Reverence: while casting)" }
E.SETTING_LABELS = { oathShare = { "Heals on your Oath's target", "pct0" }, vigilHits = { "People reached by Light's Vigil" } }

local function statsSection(rows, S)
  local st, how = S.st, S.info and S.info.how or {}
  local was = st.orig or {}
  local add = function(r) rows[#rows + 1] = r; return r end
  local function stat(label, work, field, unit, src)
    return add(editable({ label, work, "", src }, "stat." .. field, unit, st[field], was[field]))
  end
  add({ head = "Your stats", anchor = "stats" })
  stat("Healing power", "read from the game", "healing", "int", "game")
  local cp = how.critParts
  stat("Crit on Holy spells", cp and (pct(cp.client, 2) .. " read from the game") or "read from the game", "crit", "pct", "game")
  local perInt = E.Multipliers(S.input).critPctPerInt
  local typed = E.OverrideFor(S.input.settings, "stat.critPerInt")
  local _, from = E.CritPerInt(st.level)
  local src = from == "game data" and "data" or "assumption"
  add(editable({ "  intellect to crit", trim(1 / perInt, 1) .. " intellect per 1% crit at level " .. st.level ..
                 " (" .. (typed and "your value" or from) .. "); used for intellect's worth", "", src },
               "stat.critPerInt", "perInt", perInt, typed and (cp and cp.perInt or perInt) or nil))
  stat("  a crit heals for", was.critMulti and "times a normal heal, before Holy Power (your value)"
       or "times a normal heal, before Holy Power (the usual spell crit)", "critMulti", "mult", "rule")
  if (st.haste or 0) > 0 or was.haste then stat("Haste", "read from the game", "haste", "pct0", "game") end
  stat("Mana", "read from the game", "manaPool", "int", "game")
  local formula = 5 * (E.DATA.regen.base + E.DATA.regen.perSpirit * (st.spirit or 0))
  stat("Regen from spirit", "the game says; its formula (game data): (" .. trim(E.DATA.regen.base, 2) .. " + " ..
       n0(st.spirit) .. " spirit / " .. trim(1 / E.DATA.regen.perSpirit, 2) .. ") x 5 = " .. n1(formula),
       "oocRegen", "regen", how.regenParts and "game" or "data")
  local share = (st.oocRegen or 0) > 0 and st.combatRegen / st.oocRegen or 0
  add(editable({ "  while casting", "share of it that keeps going while you cast (Reverence; from the game): " ..
                 n1(st.combatRegen) .. " per 5 s", "", "game" }, "stat.castingShare", "pct0", share, was.castingShare))
  stat("MP5", "read from the game (gear, buffs)", "mp5", "num1", "game")
end

-- field, name, unit, what it does, the talent's key in your talent ranks
local TALENT_ROWS = {
  { "healingLight", "Healing Light", "pct0", "Holy Light, Flash of Light and Holy Shock heal more", "healingLight" },
  { "holyPower", "Holy Power", "pct0", "more on a crit's bonus (150% becomes 175% at 5/5)", "holyPower" },
  { "illumination", "Illumination", "pct0", "chance a crit of Flash of Light, Holy Light, Holy Shock or Light's Vigil gives mana back", "illumination" },
  { "illuminationRefund", "  mana back", "pct0", "of the spell's base cost, each time", "illumination" },
  { "infusion", "Infusion of Light", "sec", "off the next Holy Light after a crit of Flash of Light or Holy Shock", "infusionOfLight" },
  { "boundlessLight", "Boundless Light", "pct0", "more crit for Holy Shock on someone without your Oath", "boundlessLight" },
  { "benediction", "Benediction", "pct0", "instant spells cost less", "benediction" },
  { "reverence", "Reverence", "pct0", "of your spirit regen goes on while casting", "reverence" },
  { "conviction", "Conviction", "pct0", "more crit (already in the game's number)", "conviction" },
  { "divineIntellect", "Divine Intellect", "pct0", "more intellect (already in the game's number)", "divineIntellect" },
}
local TALENT_NAME = {}
for _, r in ipairs(TALENT_ROWS) do TALENT_NAME[r[1]] = r[2] end

local function talentsSection(rows, S)
  local t, tr = S.t, S.input.talents or {}
  local tWas = t.orig or {}
  local any = false
  for _, r in ipairs(TALENT_ROWS) do
    local v = t[r[1]]
    local show = type(v) == "number" and (abs(v) > 1e-9 or tWas[r[1]] ~= nil)
    if r[1] == "illuminationRefund" then show = (t.illumination or 0) > 0 end
    if show then
      if not any then rows[#rows + 1] = { head = "Your talents", anchor = "talents" }; any = true end
      local rank = tr[r[5]]
      local work = r[4] .. ((tWas[r[1]] ~= nil) and " (your value)" or
        (" (game data" .. ((rank and rank > 0 and r[1] ~= "illuminationRefund") and (", rank " .. rank) or "") .. ")"))
      rows[#rows + 1] = editable({ r[2], work, "", "data" }, "talent." .. r[1], r[3], v, tWas[r[1]])
    end
  end
end

-- One spell rank, worked out (a Light's Vigil: the heal on each of its people).
local function spellSection(rows, S, key, rank, step, why)
  local st, t, set = S.st, S.t, S.input.settings
  local def = E.tableFor(set)[key]
  local top = def and E.MaxRank(key, st.level, set.known, set)
  if not (def and top) then return nil end
  rank = min(max(1, rank or top), top)
  local add = function(r) rows[#rows + 1] = r; return r end
  local base = S.weights and S.weights.base
  local pots = step and base and base.potions
  if pots and pots.healing > 0 then
    local s2 = {}
    for k, v in pairs(st) do s2[k] = v end
    s2.healing = st.healing + pots.healing
    st = s2
  end
  local heal, cost, time, sp = E.CastValue(key, rank, st, t, set)
  local p = sp.parts
  local cr = clientRow(S, key, rank)
  add({ head = def.name .. " rank " .. rank .. (why and (": " .. why) or ""), sub = true, anchor = "spell:" .. key .. ":" .. rank })
  if pots and pots.healing > 0 then
    add({ note = "Healing power here: your " .. n0(S.st.healing) .. " + " .. n1(pots.healing) ..
      " on average from your potions over the fight (see the fight above)." })
  end
  local bw
  if p.ppl and p.ppl > 0 then
    local lv = (p.ml and p.ml > 0) and min(st.level, p.ml) or st.level
    bw = "game data: " .. trim(p.bp, 1) .. " + " .. trim(p.ppl, 2) .. " per level x " .. max(0, lv - p.bl) ..
         " levels (" .. p.bl .. " to " .. lv .. ")"
  else
    bw = "game data"
  end
  if cr and cr.client then
    if abs(cr.client - cr.model) <= 1 then bw = bw .. "; heal matches the game's tooltip (" .. n0(cr.client) .. ")"
    else bw = bw .. "; the game's tooltip says " .. n0(cr.client) .. " (not yet checked against a paladin in game: the game data is used)" end
  end
  add({ "Base heal", bw, n1(p.base), "data" })
  if p.power < 0.999 then
    local rk = def.ranks[rank]
    local cap = (rk.ml and rk.ml > 0) and rk.ml or (rk.lvl + 5)
    add({ "Coefficient", trim(p.fullCoeff, 4) .. " (game data) x " .. pct(p.power, 0) .. " downranking: -5% a level past " ..
          (cap + 12) .. " (max level " .. cap .. " + 12), at least 10%", trim(sp.coeff, 4), "rule" })
  else
    add({ "Coefficient", "share of your healing power the rank gets (game data)", trim(sp.coeff, 4), "data" })
  end
  local hl = p.healingLight or 1
  local hlText = abs(hl - 1) > 1e-9 and (" x " .. trim(hl, 2) .. " Healing Light") or ""
  local core = "(" .. n1(p.base) .. " + " .. trim(sp.coeff, 4) .. " x " .. n0(p.healing) .. " healing power)" .. hlText
  if (p.oathShare or 0) > 0 then
    add({ "Heal, no crit", "on anyone else: " .. core, n1(sp.healOff), "" })
    if ((set.rules or E.RULES).oath == "scaled") then
      add({ "  on your Oath's target", n1(sp.healOff) .. " + " .. n1(p.oath) .. " Oath of Light (its bonus x " ..
            trim(sp.coeff, 4) .. ", the rank's coefficient)", n1(sp.healOn), "rule" })
    else
      add({ "  on your Oath's target", "(" .. n1(p.base) .. " + " .. n1(p.oath) .. " Oath of Light + " .. trim(sp.coeff, 4) .. " x " ..
            n0(p.healing) .. ")" .. hlText, n1(sp.healOn), "data" })
    end
    add(setting({ "  share on your Oath's target", "of your casts of it (your setting)", "", "setting", help = OATH_HELP },
                { "oathShare" }, "pct0", p.oathShare))
  else
    add({ "Heal, no crit", core, n1(sp.heal), "" })
  end
  local cm = p.critMulti
  local cm0 = st.critMulti or 1.5
  local holy = ""
  if (t.holyPower or 0) > 0 then
    holy = ((set.rules or E.RULES).holyPower == "bonusOnly")
      and (" (1 + " .. trim(cm0 - 1, 2) .. " x " .. trim(1 + t.holyPower, 2) .. " Holy Power)")
      or (" (" .. trim(cm0, 2) .. " x " .. trim(1 + t.holyPower, 2) .. " Holy Power)")
  end
  if (p.oathShare or 0) > 0 and abs(p.critOff - p.critOn) > 1e-9 then
    add({ "With crits", "crit " .. pct(p.critOff, 2) .. " on anyone else (Boundless Light), " .. pct(p.critOn, 2) ..
          " on your Oath's target; a crit heals x" .. trim(cm, 2) .. holy, n1(sp.expected), "" })
  else
    add({ "With crits", "x (1 + " .. pct(p.crit, 2) .. " crit x " .. trim(cm - 1, 2) .. ")" .. holy, n1(sp.expected), "" })
  end
  if sp.targets ~= 1 then
    add(setting({ "Targets", "people one Light's Vigil heals (your setting)", "", "setting", help = VIGIL_HELP },
                { "vigilHits" }, "int", sp.targets))
  end
  local oh = set.overheal[key] or 0
  add(setting({ "Overheal", "healing wasted on players already at full health (your setting)", "", "setting",
                help = E.OverhealHelp(def.name) }, { "overheal", key }, "pct0", oh))
  local perCast = sp.expected * (1 - oh) * sp.targets
  local w = n1(sp.expected) .. " x (1 - " .. pct(oh, 0) .. ")"
  if sp.targets ~= 1 then w = "(" .. w .. ") x " .. trim(sp.targets, 1) end
  add({ "Heal per cast", w, n0(perCast), "" })
  -- mana
  local mw = trim(p.rankCost, 1) .. " (game data)"
  if (p.benediction or 0) > 0 then mw = mw .. " x (1 - " .. pct(p.benediction, 0) .. " Benediction)" end
  local before = p.rankCost * (1 - (p.benediction or 0))
  add({ "Mana", mw, n1(before), "data" })
  if (p.refund or 0) > 0 then
    add({ "  Illumination", trim(p.rankCost, 1) .. " x " .. pct(t.illuminationRefund, 0) .. " back x " .. pct(p.illumChance, 2) ..
          (key == "VIGIL" and " chance one of its heals crits x " or " crit x ") .. pct(t.illumination, 0) .. " chance", "-" .. n1(p.refund), "data" })
    add({ "  mana per cast", n1(before) .. " - " .. n1(p.refund), n1(cost), "" })
  end
  -- time
  local gcd = 1.5 / (1 + st.haste)
  local cw
  if p.castBase == "gcd" then cw = "instant: one global cooldown, 1.5 s"
  else cw = trim(p.castBase, 2) .. " s (game data)" end
  if (st.haste or 0) > 0 then cw = cw .. " / (1 + " .. pct(st.haste, 1) .. " haste)" end
  add({ "Time per cast", cw, trim(time, 2) .. " s", "data" })
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
  oath = { "Oath of Light kept up", "%s x %s (8%% of base mana, once an hour: this fight's share of it)", "data" },
  favor = { "Divine Favor", "%s x %s (4%% of base mana, every 2 minutes)", "data" },
  judge = { "Seal and Judgement", "%s x %s", "assumption" },
}
local LIMITS = { cooldown = "as often as its cooldown allows", mana = "until the mana is spent", time = "fills the time left",
                 procs = "as many as Infusion of Light gives" }

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
  local potPlan
  for _, part in ipairs(E.ManaParts(st, t, set)) do
    manaSum = manaSum + part.mana
    local lab = MANA_LABELS[part.key]
    if part.key == "potions" and part.plan and not part.plan.sheet then
      potPlan = part.plan
      for _, it in ipairs(part.plan.items) do
        if it.n > 0 and it.mana > 0.5 then
          local g = E.POTION_GROUPS[it.def.group]
          local each = it.def.manaPct and (pct(it.def.manaPct, 0) .. " of " .. n0(st.manaPool)) or n0(it.manaEach)
          add({ it.def.name, string.format("%s x %s (%s: %d fit in the fight)", trim(it.n, 0), each,
                (g and g.name or "cooldown"):lower(), part.plan.groups[it.def.group].fits), n0(it.mana), "setting",
                help = it.def.text .. "." })
        end
      end
    elseif part.key == "pool" then
      add({ lab[1], lab[2], n0(part.mana), lab[3] })
    elseif lab and abs(part.mana) > 0.5 then
      local a = part.ticks and trim(part.per, 1) or trim(part.n, 2)
      local b = part.ticks and trim(part.ticks, 1) or trim(part.per, 1)
      add({ lab[1], string.format(lab[2], a, b), n0(part.mana), lab[3] })
    end
  end
  add({ "Mana for the fight", "", n0(manaSum), "" })
  for _, it in ipairs(potPlan and potPlan.items or {}) do
    if it.n > 0 and it.healing then
      add({ it.def.name, string.format("+%d healing for %d s x %s, over %d s", it.def.healing, it.def.dur, trim(it.n, 0), fl),
            "+" .. n1(it.healing), "setting" })
    end
    if it.n > 0 and it.sleep > 0 then
      add({ it.def.name .. ", asleep", string.format("%d s x %s: no casting", it.def.sleep, trim(it.n, 0)),
            "-" .. trim(it.sleep, 0) .. " s", "setting" })
    end
  end
  if (base.oathCasts or 0) > 0 then
    add({ note = "Oath of Light lasts an hour, so this fight pays " .. trim(base.oathCasts, 2) .. " of one cast (its mana and a global cooldown)." })
  end
  local total, worst = 0, 0
  for _, s in ipairs(base.steps) do
    if s.enabled and s.casts > 0.01 then
      local stepEff = s.eff - (s.pauseCasts and base.pauseEff or 0)
      total = total + stepEff
      local why = LIMITS[s.limit] or ""
      if s.limit == "cooldown" and s.cap then why = "every " .. E.Seconds(s.cap) .. " s" end
      local shown = s.casts * s.perCastEff
      worst = max(worst, abs(shown - stepEff))
      local text
      if s.key == "VIGIL" then
        text = string.format("%s x %s (the Vigil's heals and its Holy Shock, after overheal)", n1(s.casts), n0(s.perCastEff))
      else
        text = string.format("%s x %s x (1 - %s overheal)", n1(s.casts), n0(s.perCast), pct(s.overheal or 0, 0))
      end
      text = text .. string.format("; %s mana and %s s a cast, %s", n1(s.cost), trim(s.time, 2), why)
      add({ spellName(s.key, set) .. " " .. s.rank, text, n0(stepEff), "" })
    end
  end
  add({ "  mana left", "the fight's mana, less what these casts cost", n0(base.manaLeft), "" })
  if (base.fiveSecondCasts or 0) > 0 then
    total = total + base.pauseEff
    add({ "Pauses to regenerate", string.format("%s s not casting x %s / %s s a cycle = %s more casts of the filler",
          n0(base.pauseTime), pct(set.imperfectPlay, 1), n1(base.pauseCycle), n1(base.fiveSecondCasts)),
          n0(base.pauseEff), "assumption" })
  end
  if base.favor then
    total = total + base.favor.eff
    add({ "Divine Favor", string.format("%s sure crit(s) of %s rank %d, each worth its crit less the crit it might have had anyway",
          trim(base.favor.uses, 0), spellName(base.favor.key, set), base.favor.rank), n0(base.favor.eff), "assumption" })
  end
  add({ "Healing in the fight", "after overheal", n0(total), "" })
  add({ "Healing per second", n0(total) .. " / " .. fl .. " s", n0(total / fl), "" })
  return { mana = manaSum, eff = total, ehps = total / fl, worst = worst }
end

local STAT_LABELS = { healing = "Healing power", int = "Intellect", spirit = "Spirit", mp5 = "MP5", crit = "Crit", haste = "Haste" }

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
      extra[#extra + 1] = "+" .. n1(d.oocRegen * step) .. " regen"
    end
    local work = bump .. (#extra > 0 and (" (" .. table.concat(extra, ", ") .. ")") or "") ..
      ": " .. n1(w.base.ehps) .. " -> " .. n1(w[stat .. "Up"]) .. " HPS"
    add({ STAT_LABELS[stat], work, stat == "healing" and "1.00" or n2(w[stat] / h), "" })
  end
end

local function assumptionsSection(rows, S)
  local set = S.input.settings
  local add = function(r) rows[#rows + 1] = r end
  add({ head = "The fight's other assumptions", anchor = "settings" })
  add({ note = "Your settings (overheal is in Your spells, at the top). Right-click one to put back its starting value." })
  add(setting({ "Fight length", "how long the fights you heal usually last", "", "setting",
                help = "In long fights you run out of mana, so mana (MP5, spirit, intellect) is worth more; " ..
                       "in short fights healing power counts most. A typical raid boss: about 2 minutes." },
              { "fightLength" }, "sec", set.fightLength))
  add(setting({ "Time between pulls", "how often a fight starts, the time in between included (for trinkets with a long cooldown)",
                "", "setting" }, { "pullEvery" }, "sec", set.pullEvery or 600))
  add(setting({ "Downtime used", "out of mana, how much of the time left you spend regenerating and casting again (an assumption)",
                "", "assumption" }, { "imperfectPlay" }, "pct0", set.imperfectPlay))
  add(setting({ "Heals on your Oath's target", "share of Flash of Light, Holy Light and Holy Shock casts", "", "setting",
                help = OATH_HELP }, { "oathShare" }, "pct0", set.oathShare or 0))
  add(setting({ "People reached by Light's Vigil", "the party it heals", "", "setting", help = VIGIL_HELP },
              { "vigilHits" }, "int", set.vigilHits or 5))
  add({ note = "Not yet checked in game: Oath of Light's bonus on a low rank (counted x the rank's coefficient, as " ..
    "DoubleZug's sheet has it; wowsims gives every rank the full bonus). " ..
    "Illumination gives mana back once per Light's Vigil when any of its heals crits (confirmed by players)." })
end

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

E.MATH_SETTINGS = {
  fightLength = { 10, 3600, true }, pullEvery = { 30, 3600, true }, overheal = { 0, 0.95 },
  imperfectPlay = { 0, 1 }, oathShare = { 0, 1 }, vigilHits = { 1, 5, true },
}
function E.MathSettingValue(path, v)
  local r = type(path) == "table" and E.MATH_SETTINGS[path[1]]
  if not (r and type(v) == "number" and v == v) then return nil end
  if r[3] then v = floor(v + 0.5) end
  if v < r[1] or v > r[2] then return nil end
  return v
end

local STAT_NAMES = {
  healing = "Healing power", crit = "Crit on Holy spells", critMulti = "A crit heals for", haste = "Haste",
  manaPool = "Mana", mp5 = "MP5", oocRegen = "Regen from spirit", castingShare = "Regen while casting",
  critPerInt = "Intellect to crit",
}
function E.OverrideLabel(id)
  local kind, rest = tostring(id):match("^(%a+)%.(.+)$")
  if kind == "stat" then return STAT_NAMES[rest] or rest end
  if kind == "talent" then return TALENT_NAME[rest] or rest end
  return tostring(id)
end
local ID_UNITS = { healing = "int", crit = "pct", critMulti = "mult", haste = "pct0", manaPool = "int", mp5 = "num1",
                   oocRegen = "regen", castingShare = "pct0", critPerInt = "perInt", infusion = "sec" }
function E.OverrideUnit(id)
  local last = tostring(id):match("([%a]+)$")
  return ID_UNITS[last] or "pct0"
end

local function stepWhy(s)
  if s.fill then return "the filler, whenever nothing else is due" end
  if s.infusion then return "whenever Infusion of Light makes it quick" end
  if s.key == "VIGIL" then return "the Vigil and its Holy Shock, at most every " .. E.Seconds(s.cap) .. " s" end
  if s.cap then return "at most every " .. E.Seconds(s.cap) .. " s" end
  return nil
end

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
    -- a Vigil's Holy Shock: worked out too
    if s.enabled and s.casts > 0.01 and s.shock and not inFight["SHOCK:" .. s.shock.rank] then
      inFight["SHOCK:" .. s.shock.rank] = s
      steps[#steps + 1] = { key = "SHOCK", rank = s.shock.rank, vigilShock = true }
    end
  end
  local set = S.input.settings
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
      if not inFight[key .. ":" .. rank] then check.spell = spellSection(rows, S, key, rank, nil, "not cast in this fight") end
    end
  end
  for _, s in ipairs(steps) do
    local c = spellSection(rows, S, s.key, s.rank, s, s.vigilShock and "the one each Light's Vigil sets off" or stepWhy(s))
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
