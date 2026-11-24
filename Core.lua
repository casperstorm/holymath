--[[ Holy Math - Core.lua
     Saved settings, recalculating when your gear/buffs/talents change, and /hm.
]]--

local ADDON, ns = ...
local G = ns.Game
-- E = the model for the player's class, chosen at login (ns.model).
local E = setmetatable({}, { __index = function(_, k) return ns.model and ns.model[k] end })

-- Saved settings live per class: HolyMathDB.PRIEST = { settings, ... },
-- so another healer class can be added without touching the priest's settings.
local function ClassDefaults(model)
  local d = { rotation = model.BEST, settings = model.copy(model.DEFAULTS.settings) }
  d.settings.shadowSpiritBuff = false
  -- A typical Classic raid boss lasts about 2 minutes (the sheet assumed 5).
  d.settings.fightLength = 120
  -- Potions: a list (Stats tab); the sheet's two switches are only for its tests.
  d.settings.majorManaPotions, d.settings.cheapManaPotions = nil, nil
  d.settings.potions = { { key = "majorMana", n = model.POTION_ALL } }
  return d
end
ns.ClassDefaults = ClassDefaults

-- What the tooltips show (Stats tab of the window): the item line at all,
-- the change in healing per second, the change in %, and the spell line.
local TOOLTIP_DEFAULTS = { items = true, itemNumber = true, itemPercent = true, spells = true }
function ns.TooltipDefaults()
  local d = {}
  for k, v in pairs(TOOLTIP_DEFAULTS) do d[k] = v end
  return d
end

-- Fills in what dst is missing from src. A list (the potions) is taken whole when
-- missing, never filled in item by item: an emptied list stays empty.
local function merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and v[1] ~= nil then
      if dst[k] == nil then dst[k] = {}; merge(dst[k], v) end
    elseif type(v) == "table" then dst[k] = type(dst[k]) == "table" and dst[k] or {}; merge(dst[k], v)
    elseif dst[k] == nil then dst[k] = v end
  end
end

local function say(msg, ...) print("|cffffd100Holy Math|r: " .. string.format(msg, ...)) end

---------------------------------------------------------------------------
-- State: rebuilt from the game whenever something changed (not in combat,
-- where the client may hide stat values; the last good state is kept).
---------------------------------------------------------------------------
local state, dirty = nil, true
function ns.MarkDirty()
  dirty = true
  if ns.Profiles then ns.Profiles.Sync() end   -- auto-save into the loaded profile
end

-- How many of your own values (Math tab) are in use.
function ns.OverrideCount()
  local n = 0
  for id, v in pairs(ns.db and ns.db.overrides or {}) do
    if not E.OverrideOK or E.OverrideOK(id, v) then n = n + 1 end
  end
  return n
end

-- A stable text for a table (keys in order), to tell when it changed.
local function fingerprint(v)
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. fingerprint(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

-- The playstyle Holy Math counts your healing with: the best mix of every spell you
-- can cast (Models/Priest.lua E.BuildPlaystyle), found again only when what decides
-- it changes (talents, level, the spells you know, the settings), not with every
-- stat that moves.
local bestCache = {}
local function bestPlaystyle(st, input)
  local key = fingerprint(input.talents) .. "|" .. tostring(st.level) .. "|" .. fingerprint(input.settings)
  if bestCache.key ~= key then
    local use = {}
    for _, k in ipairs(E.BUILD_SPELLS) do use[k] = true end
    local ok, r = pcall(E.BuildPlaystyle, use, st, input)
    if not ok and ns.LogError then ns.LogError("best", r) end
    bestCache = { key = key, def = ok and r and r.def or nil }
  end
  return bestCache.def
end
ns.BestPlaystyleCache = function() return bestCache end   -- tests

local function Rebuild()
  local db = ns.db
  local input, st, info = G.BuildInput(db)
  local t = E.Talents(input.talents)
  -- Take every known rank's cost, cast time and base heal from the game
  -- (Models/Priest.lua ApplyClientData). clientSeen: this session's first readings,
  -- so a buff that changes them for a moment isn't taken as the spell's own.
  -- In an instance the spell tooltips aren't read (G.ClientSpells): the heals read
  -- outside are kept.
  info.inInstance = G.InInstance()
  local spells, pending, missing = G.ClientSpells(info.spellIds, info.inInstance)
  ns.clientSeen = ns.clientSeen or {}
  info.client = E.ApplyClientData(st.invalid and {} or spells, st, t, input.settings, ns.clientSeen, GetTime and GetTime())
  -- a Mender's Potion active now: the tooltips above had its healing in them (as
  -- they should); the fight counts potions over the whole fight, so it comes out
  if (st.potionBuff or 0) > 0 then st.healing = math.max(0, st.healing - st.potionBuff) end
  -- a reading held back as a buff's: look again once a buff would be over, so a
  -- lasting change becomes the rank's own even if nothing else happens meanwhile
  -- (a heal kept from outside an instance has no new reading to wait for)
  local held = false
  for _, r in ipairs(info.client) do
    if (r.baseFrom == "earlier" and r.client) or r.costFrom == "earlier" or r.castFrom == "earlier" then held = true end
  end
  if held and not ns.heldTimer and C_Timer and C_Timer.After then
    ns.heldTimer = true
    C_Timer.After(E.HOLD + 1, function() ns.heldTimer = nil; ns.MarkDirty() end)
  end
  -- Tooltip text the client hasn't loaded yet (often at login): ask it to load
  -- (once per spell per session); SPELL_DATA_LOAD_RESULT / SPELL_TEXT_UPDATE then
  -- say it's there (events below). One look 3 s later as well, for clients
  -- without that request.
  ns.textPending = pending
  if pending then
    ns.requestedText = ns.requestedText or {}
    for _, id in ipairs(missing or {}) do
      if not ns.requestedText[id] and C_Spell and C_Spell.RequestLoadSpellData then
        ns.requestedText[id] = true
        G.safe(C_Spell.RequestLoadSpellData, id)
      end
    end
    if not ns.retriedText then
      ns.retriedText = true
      if C_Timer and C_Timer.After then C_Timer.After(3, function() ns.MarkDirty() end) end
    end
  end
  -- Your own values from the Math tab: only now, after the check against the
  -- game, so that check always uses the game's own numbers. gameSt keeps those.
  local gameSt = st
  if E.ApplyStatOverrides and type(db.overrides) == "table" and next(db.overrides) then
    input.settings.overrides = db.overrides
    t = E.Talents(input.talents, nil, db.overrides)
    st = E.ApplyStatOverrides(st, db.overrides)
  end
  -- the playstyle Holy Math counts with: one of the built-ins you chose on the Stats
  -- tab, else the best for you (Renew filler while your stats can't be read)
  local best = (not st.invalid) and bestPlaystyle(st, input) or nil
  if best then E.ROTATIONS[E.BEST] = E.RotationFromPlaystyle(best) end
  local chosen = db.rotation and E.BUILTIN_ROTATIONS[db.rotation]
  local rot
  if chosen and not chosen.sheetOnly and not (chosen.requires and (t[chosen.requires] or 0) <= 0) then
    rot = db.rotation
  else
    rot = best and E.BEST or E.DEFAULT_ROTATION
  end
  local weights = (not st.invalid) and E.Weights(rot, st, input) or nil
  state = { input = input, st = st, gameSt = gameSt, t = t, info = info, rotation = rot, best = best, weights = weights,
            time = time() }
  -- "Your spells": plans compared, best mix, spell table (each on its own, so one
  -- failing doesn't take the others down)
  if weights then
    local function run(name, fn, ...)
      local ok, res = pcall(fn, ...)
      if ok then return res end
      ns.LogError(name, res)
    end
    state.plans = run("plans", E.ComparePlans, st, input)
    state.mix = run("mix", E.BestMix, st, t, input.settings)
    state.spells = run("spellTable", E.SpellTable, st, t, input.settings)
  end
  G.ClearItemCache()
  if ns.ClearVerdicts then ns.ClearVerdicts() end
  dirty = false
end

function ns.State(force)
  if (dirty or force or not state) and not (InCombatLockdown and InCombatLockdown() and state) then
    local ok, err = pcall(Rebuild)
    if not ok then
      ns.LogError("rebuild", err)
      if not ns.reportedError then ns.reportedError = true; say("could not read your stats (%s). /hm dump saves details.", tostring(err)) end
      dirty = false
    end
  end
  return state
end

---------------------------------------------------------------------------
-- Profiles: named sets of your settings (the fight, overheal per spell, the Math
-- tab's other settings), to swap between and compare.
-- db.profiles[name] = { settings = {...} }; db.profile = the
-- loaded one, which every change is saved into (P.Sync). None loaded: your
-- settings are just your settings, as before profiles. Not in a profile: the values you typed over the
-- game's on the Math tab (db.overrides, about your character, not the fight) and
-- the tooltip options.
---------------------------------------------------------------------------
local P = {}
ns.Profiles = P
P.MAX_NAME = 32

local function deepEqual(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function current() return { settings = E.copy(ns.db.settings) } end
local hpsCache = { state = nil }
local function forget() hpsCache = { state = nil } end

-- "  Raid  " -> "Raid"; nil when empty or too long.
function P.CleanName(name)
  -- no "|": it would start a colour or texture code in the menu
  name = type(name) == "string" and name:gsub("|", ""):gsub("^%s+", ""):gsub("%s+$", "") or ""
  if name == "" or #name > P.MAX_NAME then return nil end
  return name
end

function P.List()
  local out = {}
  for name in pairs(ns.db.profiles or {}) do out[#out + 1] = name end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
end

function P.Exists(name) return name ~= nil and (ns.db.profiles or {})[name] ~= nil end
function P.Loaded() return P.Exists(ns.db.profile) and ns.db.profile or nil end

-- Auto-save: while a profile is loaded, every change to your settings is written
-- into it (ns.MarkDirty calls this on every change).
function P.Sync()
  local name = ns.db and P.Loaded()
  if not name then return end
  local p = ns.db.profiles[name]
  p.settings = E.copy(ns.db.settings)
end

-- At login: profiles saved by an older version get the settings added since
-- (their defaults).
function P.FillDefaults()
  local d = ClassDefaults(ns.model)
  for _, p in pairs(ns.db.profiles or {}) do
    if type(p) == "table" then
      p.settings = type(p.settings) == "table" and p.settings or {}
      E.MigrateSettings(p.settings)
      merge(p.settings, d.settings)
    end
  end
end

-- A new profile with your settings now; it is loaded.
function P.Save(name)
  name = P.CleanName(name)
  if not name then return nil end
  ns.db.profiles = ns.db.profiles or {}
  ns.db.profiles[name] = current()
  ns.db.profile = name
  forget()
  return name
end

function P.Load(name)
  local p = (ns.db.profiles or {})[name]
  if not p then return false end
  -- a profile saved by an older version gets the settings added since (their defaults)
  local d = ClassDefaults(ns.model)
  p.settings = type(p.settings) == "table" and p.settings or {}
  E.MigrateSettings(p.settings)
  merge(p.settings, d.settings)
  ns.db.settings = E.copy(p.settings)
  ns.db.profile = name
  ns.MarkDirty()
  return true
end

-- false, why: the new name is empty, too long, or another profile's.
function P.Rename(old, new)
  new = P.CleanName(new)
  if not (P.Exists(old) and new) then return false, "empty" end
  if new ~= old and P.Exists(new) then return false, "taken" end
  local p = ns.db.profiles[old]
  ns.db.profiles[old] = nil
  ns.db.profiles[new] = p
  if ns.db.profile == old then ns.db.profile = new end
  forget()
  return true
end

function P.Delete(name)
  if not P.Exists(name) then return false end
  ns.db.profiles[name] = nil
  if ns.db.profile == name then ns.db.profile = nil end
  forget()
  return true
end

-- What a profile heals per second (after overheal) with your gear, buffs and
-- talents now, without loading it: the model run with its settings.
function P.HPS(name)
  local p = (ns.db.profiles or {})[name]
  local S = ns.State()
  if not (p and S and S.weights) then return nil end
  if hpsCache.state ~= S then hpsCache = { state = S } end
  if hpsCache[name] == nil then
    local set = E.copy(S.input.settings)          -- has your known ranks, rules and typed values
    for k, v in pairs(p.settings or {}) do set[k] = E.copy(v) end
    -- with the best playstyle for those settings, as loading it would give
    local use = {}
    for _, k in ipairs(E.BUILD_SPELLS) do use[k] = true end
    local input = {}
    for k, v in pairs(S.input) do input[k] = v end
    input.settings = set
    local ok, res = pcall(E.BuildPlaystyle, use, S.st, input)
    hpsCache[name] = (ok and res and res.result and res.result.ehps) or false
  end
  return hpsCache[name] or nil
end

-- How a profile differs from your current settings, one line each:
-- "Prayer of Mending bounces: 1 (now 3)".
local LABELS = {
  fightLength = { "Fight length", "sec" }, pomHits = { "Prayer of Mending bounces" },
  groupHits = { "People reached by group heals" },
  manaTidesInGroup = { "Mana Tide totems" },
  includeInspiration = { "Count Inspiration", "onoff" }, imperfectPlay = { "Downtime used", "pct0" },
  litanyAlternation = { "Litany of Light, on its own", "pct0" },
}
local function show(v, unit)
  if unit == "onoff" or type(v) == "boolean" then return v and "on" or "off" end
  if unit and E.MathFormat and type(v) == "number" then return E.MathFormat(unit, v) end
  return tostring(v)
end
-- "Major Mender's Potion x1, Major Mana Potion (all)" / "none".
function P.PotionText(list)
  local parts = {}
  for _, e in ipairs(type(list) == "table" and list or {}) do
    local def = E.POTION_BY_KEY and E.POTION_BY_KEY[e.key]
    if def and (e.n or 0) > 0 then
      parts[#parts + 1] = def.name .. ((e.n or 0) >= E.POTION_ALL and " (all)" or (" x" .. e.n))
    end
  end
  return #parts > 0 and table.concat(parts, ", ") or "none"
end

function P.Diff(name)
  local p = (ns.db.profiles or {})[name]
  if not p then return {} end
  local cur, out = ns.db.settings, {}
  local function line(label, a, b, unit) out[#out + 1] = string.format("%s: %s (now %s)", label, show(a, unit), show(b, unit)) end
  local keys = {}
  for k in pairs(p.settings or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return (LABELS[a] and LABELS[a][1] or a) < (LABELS[b] and LABELS[b][1] or b) end)
  for _, k in ipairs(keys) do
    local a, b = p.settings[k], cur[k]
    if k == "overheal" and type(a) == "table" and type(b) == "table" then
      local spells = {}
      for s in pairs(a) do if a[s] ~= b[s] then spells[#spells + 1] = s end end
      table.sort(spells)
      for _, s in ipairs(spells) do
        local def = E.SPELLS and E.SPELLS[s]
        line("Overheal, " .. (def and def.name or s), a[s], b[s], "pct0")
      end
    elseif k == "potions" and not deepEqual(a, b) then
      out[#out + 1] = string.format("Potions: %s (now %s)", P.PotionText(a), P.PotionText(b))
    elseif not deepEqual(a, b) and type(a) ~= "table" then
      local l = LABELS[k]
      line(l and l[1] or k, a, b, l and l[2])
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------
local function Summary()
  local S = ns.State(true)
  if not S then return say("no data yet.") end
  local st, set = S.st, S.input.settings
  say("%s, %d s fight  (spell data: %s)", E.ROTATIONS[S.rotation].name, set.fightLength, E.DATA.source)
  print(string.format("  Your stats: healing %.0f, int %.0f, spirit %.0f, crit %.1f%%, MP5 %.0f, mana %.0f, regen %.0f/%.0f per 5 s (out of / in combat)",
    st.healing, st.int, st.spirit, st.crit * 100, st.mp5, st.manaPool, st.oocRegen, st.combatRegen))
  if #S.info.how.missing > 0 then
    if InCombatLockdown and InCombatLockdown() then
      print("  Your stats can't be read in combat; Holy Math fills them in when the fight ends.")
    else
      print("  |cffff5050Could not read:|r " .. table.concat(S.info.how.missing, ", "))
    end
  end
  local mine = ns.OverrideCount and ns.OverrideCount() or 0
  if mine > 0 then
    print(string.format("  |cff66bbff%d value(s) typed by you on the Math tab are in these numbers|r (/hm reset puts back the game's)", mine))
  end
  if st.invalid then return print("  Not showing any numbers: a required stat could not be read. /hm dump, then /reload, saves details.") end
  local w = S.weights
  if not w then return print("  No model at your level yet: the rotation's filler spell isn't known.") end
  print(string.format("  Model: %.0f healing per second raw, %.0f after overheal", w.base.hps, w.base.ehps))
  local h = w.healing ~= 0 and w.healing or 1
  print(string.format("  Stat values (healing power = 1.00): intellect %.2f, spirit %.2f, MP5 %.2f, 1%% crit %.1f, 1%% haste %.1f",
    w.int / h, w.spirit / h, w.mp5 / h, w.crit / h, w.haste / h))
  print(string.format("  (+1 healing power = +%.2f healing per second after overheal)", w.healing))
end

local function Check()
  local S = ns.State(true)
  if not S then return say("no data yet.") end
  say("where the numbers come from")
  print("  Crit: " .. S.info.how.crit)
  print("  Regen: " .. S.info.how.regen)
  print("  Talents read via: " .. S.info.talentSource)
  if S.info.how.potionBuff then print("  Potion: " .. S.info.how.potionBuff) end
  local found, missing = {}, {}
  for key, name in pairs(E.TALENT_NAMES) do
    local r = S.info.talentsByName[name]
    if r then if r.rank > 0 then found[#found + 1] = string.format("%s %d/%s", name, r.rank, tostring(r.max)) end
    else missing[#missing + 1] = name end
  end
  table.sort(found); table.sort(missing)
  print("  Talents with points: " .. (#found > 0 and table.concat(found, ", ") or "none"))
  if #missing > 0 then print("  Not found in your tree: " .. table.concat(missing, ", ")) end
  local ks = {}
  for k, r in pairs(S.input.settings.known or {}) do ks[#ks + 1] = E.SPELLS[k].name .. " " .. r end
  table.sort(ks)
  print("  Highest ranks known: " .. (#ks > 0 and table.concat(ks, ", ") or "none"))
  print("  Kings: " .. tostring(S.input.buffs.kings) .. "  Human: " .. tostring(S.input.race.human))

  -- What was taken from the game: every known rank's cost, cast time and base heal
  -- (Models/Priest.lua ApplyClientData). "data" = the game data, kept.
  local rows, none, held, misread = S.info.client or {}, 0, 0, 0
  local WHERE = { client = "from the game", earlier = "the earlier reading (changed for a moment, e.g. a buff; a change that lasts 2 minutes is taken)",
                  misread = "|cffff5050the game's number looks misread, using the game data|r" }
  local inside = S.info.inInstance
  local kept = 0
  for _, r in ipairs(rows) do
    if not r.client then
      if inside and r.baseFrom == "earlier" then kept = kept + 1 else none = none + 1 end
    end
    if (r.baseFrom == "earlier" and r.client) or r.costFrom == "earlier" or r.castFrom == "earlier" then held = held + 1 end
    if r.baseFrom == "misread" or r.costFrom == "misread" or r.castFrom == "misread" then misread = misread + 1 end
  end
  if inside then
    print("  You're in an instance: spell tooltips there can show low ranks healing more than they do, " ..
      "so heals are the ones read outside (costs and cast times are still read).")
  end
  local notes = {}
  if kept > 0 then notes[#notes + 1] = string.format("%d heals kept from outside the instance", kept) end
  if none > 0 then
    notes[#notes + 1] = string.format(inside and "%d heals from the game data (not read outside yet this session)"
      or "%d with no readable tooltip yet (game data used)", none)
  end
  if held > 0 then notes[#notes + 1] = string.format("%d changed for a moment (the earlier reading used)", held) end
  if misread > 0 then notes[#notes + 1] = string.format("%d looked misread (game data used)", misread) end
  print(string.format("  Spells: %d ranks known, read from the game%s", #rows,
    #notes > 0 and (": " .. table.concat(notes, "; ")) or ", all of them"))
  for _, r in ipairs(rows) do
    local parts, name = {}, E.SPELLS[r.key].name .. " " .. r.rank
    if r.client and (math.abs(r.client - r.model) > 1 or r.baseFrom ~= "client" or r.tooltipFull) then
      local was = math.abs(r.client - r.model) <= 1 and "the game data agrees"
        or string.format("the game data said %.0f", r.model)
      parts[#parts + 1] = string.format("heals %.0f, %s; base %s", r.client, was, WHERE[r.baseFrom] or "from the game data")
      if r.tooltipFull then
        parts[#parts + 1] = string.format("the tooltip leaves out downranking: real heals get %d%% of your healing power",
          math.floor(r.rulePower * 100 + 0.5))
      end
    end
    local data = r.dataCost and math.floor(r.dataCost + 0.5)
    if r.clientCost and data and (math.abs(r.clientCost - r.dataCost) >= 1 or r.costFrom ~= "client") then
      parts[#parts + 1] = string.format("costs %d (game data with your talents %d), %s", r.clientCost, data,
        WHERE[r.costFrom] or "from the game data")
    end
    if r.clientCast and type(r.dataCast) == "number" and (math.abs(r.clientCast - r.dataCast) > 0.001 or r.castFrom ~= "client") then
      parts[#parts + 1] = string.format("casts in %.2f s before haste (game data %.2f s), %s", r.clientCast, r.dataCast,
        WHERE[r.castFrom] or "from the game data")
    end
    if #parts > 0 then print("    " .. name .. ": " .. table.concat(parts, "; ")) end
  end
end

-- Everything we read, written to SavedVariables (WTF/.../SavedVariables/HolyMath.lua
-- after /reload), so the model's assumptions can be checked against this client.
-- Each section runs on its own: one failing section records its error and the
-- rest still get saved.
local function Dump()
  local d = { time = date and date("%Y-%m-%d %H:%M:%S"), build = { G.safe(GetBuildInfo) }, sectionErrors = {} }
  local function section(name, fn)
    local ok, err = pcall(fn)
    if not ok then d.sectionErrors[name] = tostring(err) end
  end
  local S
  section("state", function() S = ns.State(true) end)
  section("player", function()
    d.level = UnitLevel("player")
    d.race = select(2, UnitRace("player"))
  end)
  -- where it was taken: tooltips inside instances can differ from outside
  section("where", function()
    local inside, kind = G.InInstance()
    d.inInstance, d.instanceType = inside, kind
    if inside and GetInstanceInfo then d.instanceName = (G.safe(GetInstanceInfo)) end
    d.zone = GetRealZoneText and G.safe(GetRealZoneText) or nil
  end)
  section("raw", function()
    local _, _, raw = G.KnownSpells()
    d.spellbookRaw = raw
    local byName, src = G.TalentsByName()
    d.talentSource = src
    d.talentsRaw = byName            -- every talent node the client gave us, by name
  end)
  section("api", function() d.api = {
    bonusHealing = G.safe(GetSpellBonusHealing),
    bonusDamage = {}, crit = {},
    manaRegen = { G.safe(GetManaRegen) },
    manaMax = G.safe(UnitPowerMax, "player", 0),
    spellHaste = G.safe(UnitSpellHaste, "player"),
    stats = {},
  }
  for school = 1, 7 do
    d.api.bonusDamage[school] = G.safe(GetSpellBonusDamage, school)
    d.api.crit[school] = G.safe(GetSpellCritChance, school)
  end
  for i = 1, 5 do d.api.stats[i] = { G.safe(UnitStat, "player", i) } end
  end)

  -- talents we use: rank, max, and the talent's own description (to check per-rank effects)
  section("talents", function()
  d.talents = {}
  local byName = G.TalentsByName()
  for key, name in pairs(E.TALENT_NAMES) do
    local r = byName[name]
    local desc = r and r.spellID and ((C_Spell and C_Spell.GetSpellDescription and G.safe(C_Spell.GetSpellDescription, r.spellID))
      or (GetSpellDescription and G.safe(GetSpellDescription, r.spellID)))
    d.talents[key] = r and { name = name, rank = r.rank, max = r.max, spellID = r.spellID, desc = desc } or "not found"
  end
  end)

  -- healing spells: what the client says each rank costs and heals
  section("spells", function()
  d.spells = {}
  local _, ids = G.KnownSpells()
  for _, s in ipairs(ids) do
    local cost
    local costs = (C_Spell and C_Spell.GetSpellPowerCost and G.safe(C_Spell.GetSpellPowerCost, s.id)) or (GetSpellPowerCost and G.safe(GetSpellPowerCost, s.id))
    if type(costs) == "table" and costs[1] then cost = costs[1].cost end
    local info = C_Spell and C_Spell.GetSpellInfo and G.safe(C_Spell.GetSpellInfo, s.id)
    local castTime = type(info) == "table" and info.castTime or select(4, G.safe(GetSpellInfo, s.id))
    local learned = (C_Spell and C_Spell.GetSpellLevelLearned and G.safe(C_Spell.GetSpellLevelLearned, s.id))
      or (GetSpellLevelLearned and G.safe(GetSpellLevelLearned, s.id))
    local desc = (C_Spell and C_Spell.GetSpellDescription and G.safe(C_Spell.GetSpellDescription, s.id))
      or (GetSpellDescription and G.safe(GetSpellDescription, s.id))
    local data = E.GAME_SPELLS[s.key] and E.GAME_SPELLS[s.key].ranks[s.rank]
    d.spells[#d.spells + 1] = { id = s.id, key = s.key, rank = s.rank, cost = cost, castTime = castTime,
      learned = learned, desc = desc, dataCost = data and data.cost, dataLvl = data and data.lvl,
      dataBase = data and E.BaseAt(data, UnitLevel("player")) }
  end
  end)

  section("buffs", function()
    d.buffs = G.BuffNames()
    -- each buff's spell ID too, to match a potion's buff (Mender's Potion) by its spell
    d.buffIds = {}
    for i = 1, 60 do
      local a = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and G.safe(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      if type(a) ~= "table" then break end
      d.buffIds[#d.buffIds + 1] = { name = a.name, spellId = a.spellId }
    end
    d.potionSpells = {}
    local getItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    for _, def in ipairs(E.POTIONS or {}) do
      if def.healing and getItemSpell then
        local name, id = G.safe(getItemSpell, def.id)
        d.potionSpells[def.key] = { item = def.id, spell = name, spellId = id }
      end
    end
  end)
  section("items", function()
    d.items = {}
    for slot = 1, 18 do
      local link = GetInventoryItemLink("player", slot)
      if link then
        -- the game's own stat table for the item, to compare with our text reading
        local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
        d.items[slot] = { link = link, parsed = G.ItemStats(link), lines = G.tooltipLines(link),
                          gameStats = G.safe(getStats, link) }
      end
    end
  end)
  section("hooks", function()
    d.hooks = {
      path = ns.hookPath, hookError = ns.hookError,
      pipeline = type(GameTooltip.ProcessInfo) == "function" and TooltipDataProcessor ~= nil,
      tooltipInfo = C_TooltipInfo ~= nil, traits = C_Traits ~= nil, spellbook = C_SpellBook ~= nil,
      combatLog = CombatLogGetCurrentEventInfo ~= nil,
    }
  end)
  section("model", function()
    if not S then return end
    d.model = { st = S.st, how = S.info.how, talents = S.input.talents, known = S.input.settings.known,
                overrides = ns.db.overrides, gameSt = S.gameSt ~= S.st and S.gameSt or nil,
                rotation = S.rotation, hps = S.weights and S.weights.base.hps, ehps = S.weights and S.weights.base.ehps }
    if S.weights then
      d.model.weights = {}
      for _, k in ipairs(E.WEIGHT_STATS) do d.model.weights[k] = S.weights[k] end
    end
  end)
  section("client", function() d.client = S and S.info.client end)
  d.errors, d.counts = ns.errors, ns.counts
  d.inCombat = InCombatLockdown and InCombatLockdown() or false
  HolyMathDB.dump = d
  -- A short history of snapshots: with two or more at different gear, the
  -- regen formula and the spell coefficients can be checked by their slope.
  section("history", function()
    local h = HolyMathDB.history or {}
    local base, casting = G.safe(GetManaRegen)
    local snap = { time = d.time, level = d.level, inCombat = d.inCombat, inInstance = d.inInstance, zone = d.zone,
                   healing = S and S.st.healing,
                   int = S and S.st.int, spirit = S and S.st.spirit, regen = { base, casting }, tooltips = {},
                   spellCrit = { G.safe(GetSpellCritChance, 2), G.safe(GetSpellCritChance, 6) } }
    for _, r in ipairs(S and S.info.client or {}) do
      if r.client then snap.tooltips[r.key .. " " .. r.rank] = r.client end
    end
    h[#h + 1] = snap
    while #h > 20 do table.remove(h, 1) end
    HolyMathDB.history = h
  end)
  local n = 0
  for _ in pairs(d.sectionErrors) do n = n + 1 end
  say("saved%s. Type /reload so the game writes it to disk.", n > 0 and string.format(" (%d section(s) failed; the error text is saved too)", n) or "")
  if d.inCombat then
    say("note: you're in combat, so the game hides your combat stats from addons. A dump out of combat is more useful.")
  end
end

---------------------------------------------------------------------------
-- /hm
---------------------------------------------------------------------------

local function Set(args)
  local db = ns.db
  local what, a, b = args:match("^(%S+)%s*(%S*)%s*(%S*)")
  what = what and what:lower()
  if what == "fight" and tonumber(a) then db.settings.fightLength = tonumber(a)
  elseif what == "oh" and E.OVERHEAL_ALIASES[a:lower()] and tonumber(b) then
    db.settings.overheal[E.OVERHEAL_ALIASES[a:lower()]] = tonumber(b) / (tonumber(b) > 1 and 100 or 1)
  elseif what == "pomhits" and tonumber(a) then db.settings.pomHits = tonumber(a)
  elseif what == "group" and tonumber(a) and tonumber(a) >= 1 and tonumber(a) <= 5 then
    db.settings.groupHits = math.floor(tonumber(a))
  elseif what == "tides" and tonumber(a) then db.settings.manaTidesInGroup = tonumber(a)
  elseif what == "pots" then   -- on: Major Mana Potions as often as they fit; off: no potions
    db.settings.potions = (a == "on") and { { key = "majorMana", n = E.POTION_ALL } } or {}
  elseif what == "inspiration" then db.settings.includeInspiration = (a == "on")
  else
    local ohs = {}
    for k in pairs(E.OVERHEAL_ALIASES) do ohs[#ohs + 1] = k end
    table.sort(ohs)
    say("set fight <seconds> | oh <%s> <percent> | pomhits <n> | group <1-5> | tides <n> | pots on|off | inspiration on|off",
      table.concat(ohs, "|"))
    return
  end
  ns.MarkDirty()
  Summary()
end

SLASH_HOLYMATH1 = "/hm"
SLASH_HOLYMATH2 = "/holymath"
SlashCmdList.HOLYMATH = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S*)%s*(.*)$")
  cmd = (cmd or ""):lower()
  if not ns.enabled then return say("made for priests - it stays off on other classes.") end
  if cmd == "" or cmd == "options" or cmd == "config" then ns.Options.Toggle()
  elseif cmd == "minimap" then
    local on = not ns.Minimap.Shown()
    ns.Minimap.SetShown(on)
    if ns.Options and ns.Options.frame and ns.Options.frame:IsShown() then ns.Options.Refresh() end
    say(on and "minimap button shown." or "minimap button hidden (/hm minimap shows it again).")
  elseif cmd == "show" or cmd == "recalc" then Summary()
  elseif cmd == "check" then Check()
  elseif cmd == "dump" then Dump()
  elseif cmd == "set" then Set(rest)
  elseif cmd == "profile" or cmd == "profiles" then
    -- /hm profile <name> loads one (for a macro); /hm profile lists them
    local name = P.CleanName(rest)
    if name then
      local found
      for _, n in ipairs(P.List()) do if n:lower() == name:lower() then found = n end end
      if not found then return say("no profile called %q. /hm profile lists them.", name) end
      P.Load(found)
      if ns.Options and ns.Options.frame and ns.Options.frame:IsShown() then ns.Options.Changed(true) end
      Summary()
    else
      local names = P.List()
      if #names == 0 then return say("no profiles yet. Save one from the bottom of the Stats tab (/hm).") end
      local parts = {}
      for _, n in ipairs(names) do
        local h = P.HPS(n)
        parts[#parts + 1] = n .. (h and string.format(" (%.0f HPS)", h) or "") .. (n == P.Loaded() and " - loaded" or "")
      end
      say("profiles: %s. /hm profile <name> loads one.", table.concat(parts, ", "))
    end
  elseif cmd == "reset" then
    -- your own values from the Math tab (also the way out if one ever breaks the window)
    local n = 0
    for _ in pairs(ns.db.overrides or {}) do n = n + 1 end
    ns.db.overrides = {}
    ns.MarkDirty()
    if ns.Options and ns.Options.frame and ns.Options.frame:IsShown() then ns.Options.Changed(true) end
    say("%d value(s) you typed on the Math tab are back to the game's.", n)
  else say("/hm (options window) | /hm show (summary in chat) | /hm check | /hm dump | /hm set ... | /hm profile [name] | /hm minimap | /hm reset (your Math tab values)") end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, unit)
  if event == "PLAYER_LOGIN" then
    HolyMathDB = HolyMathDB or {}
    local _, class = UnitClass("player")
    ns.model = ns.Models and ns.Models[class]
    ns.enabled = ns.model ~= nil
    if not ns.enabled then return end
    HolyMathDB[class] = HolyMathDB[class] or {}
    -- older saved settings: the potion list, shield waste (Models/Priest.lua MigrateSettings)
    ns.model.MigrateSettings(HolyMathDB[class].settings)
    merge(HolyMathDB[class], ClassDefaults(ns.model))
    merge(HolyMathDB[class], { tooltips = ns.TooltipDefaults() })
    -- options the window no longer has (only upgrades, Shift only, notes): their old defaults
    for _, k in ipairs({ "cantEquip", "useNote", "onlyUpgrades", "itemShift" }) do HolyMathDB[class].tooltips[k] = nil end
    if type(HolyMathDB[class].overrides) ~= "table" then HolyMathDB[class].overrides = {} end
    if type(HolyMathDB[class].profiles) ~= "table" then HolyMathDB[class].profiles = {} end
    ns.db = HolyMathDB[class]
    P.FillDefaults()
    ns.db = HolyMathDB[class]
    -- one-time: the old default fight length (300 s) becomes the new one (120 s)
    if not ns.db.fight120 then
      if ns.db.settings.fightLength == 300 then ns.db.settings.fightLength = 120 end
      ns.db.fight120 = true
    end
    -- one-time: the playstyle is the best for you unless you pick a built-in (the old
    -- default, Renew filler, and playstyles of your own from the old editor become it)
    if not ns.db.bestDefault then
      ns.db.rotation = ns.model.BEST
      ns.db.bestDefault = true
    end
    -- A Forever build once threw while hooking tooltips (StatCap's notes); keep
    -- the rest of the addon working if it does.
    local ok, err = pcall(ns.HookTooltips)
    if not ok then ns.hookError = tostring(err); ns.LogError("hookTooltips", err) end
    -- Read your stats once, out of combat, a little after login: in combat the game
    -- won't give them out, so that read is what the window and tooltips use if
    -- you first look in a fight (it updates when the fight ends)
    if C_Timer and C_Timer.After then
      C_Timer.After(3, function()
        if not (InCombatLockdown and InCombatLockdown()) then ns.State(true); ns.warmed = true end
      end)
    end
    -- the minimap button (Minimap.lua)
    if ns.Minimap then
      local okM, errM = pcall(ns.Minimap.Create)
      if not okM then ns.LogError("minimap", errM) end
    end
    for _, ev in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "UNIT_AURA", "UNIT_STATS", "PLAYER_LEVEL_UP",
                          "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED", "CHARACTER_POINTS_CHANGED",
                          "PLAYER_REGEN_ENABLED", "UNIT_MAXPOWER",
                          "PLAYER_ENTERING_WORLD",                          -- into or out of an instance
                          "SPELL_DATA_LOAD_RESULT", "SPELL_TEXT_UPDATE" }) do -- tooltip text loaded
      pcall(self.RegisterEvent, self, ev)
    end
    return
  end
  if (event == "UNIT_AURA" or event == "UNIT_STATS" or event == "UNIT_MAXPOWER") and unit ~= "player" then return end
  -- spell text arriving only matters while some was missing (these fire often)
  if (event == "SPELL_DATA_LOAD_RESULT" or event == "SPELL_TEXT_UPDATE") and not ns.textPending then return end
  ns.MarkDirty()
  -- an open options window follows your gear/buffs/talents
  local O = ns.Options
  if O and O.frame and O.frame:IsShown() then O.Changed() end
end)
