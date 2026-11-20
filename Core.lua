--[[ Holy Math - Core.lua
     Saved settings, recalculating when your gear/buffs/talents change, and /hm.
]]--

local ADDON, ns = ...
local G = ns.Game
-- E = the model for the player's class, chosen at login (ns.model).
local E = setmetatable({}, { __index = function(_, k) return ns.model and ns.model[k] end })

-- Saved settings live per class: HolyMathDB.PRIEST = { rotation, settings },
-- so another healer class can be added without touching the priest's settings.
local function ClassDefaults(model)
  local d = { rotation = model.DEFAULT_ROTATION, settings = model.copy(model.DEFAULTS.settings) }
  d.settings.shadowSpiritBuff = false
  -- A typical Classic raid boss lasts about 2 minutes (the sheet assumed 5).
  d.settings.fightLength = 120
  return d
end
ns.ClassDefaults = ClassDefaults

-- What the item tooltips show (Tooltips tab of the window).
local TOOLTIP_DEFAULTS = {
  items = true, itemPercent = true, cantEquip = true, useNote = true, onlyUpgrades = false, itemShift = false,
}
function ns.TooltipDefaults()
  local d = {}
  for k, v in pairs(TOOLTIP_DEFAULTS) do d[k] = v end
  return d
end

local function merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then dst[k] = type(dst[k]) == "table" and dst[k] or {}; merge(dst[k], v)
    elseif dst[k] == nil then dst[k] = v end
  end
end

local function say(msg, ...) print("|cffffd100Holy Math|r: " .. string.format(msg, ...)) end

---------------------------------------------------------------------------
-- State: rebuilt from the game whenever something changed (not in combat,
-- where the client may hide stat values; the last good state is kept).
---------------------------------------------------------------------------
local state, dirty = nil, true
function ns.MarkDirty() dirty = true end

local function Rebuild()
  local db = ns.db
  local input, st, info = G.BuildInput(db)
  local t = E.Talents(input.talents)
  -- Check every known rank against the game's own tooltip, and take the game's
  -- costs and base heals where they agree closely (Models/Priest.lua ApplyClientData).
  local spells, pending = G.ClientSpells(info.spellIds)
  info.client = E.ApplyClientData(st.invalid and {} or spells, st, t, input.settings)
  if pending and not ns.retriedText then
    ns.retriedText = true                    -- tooltip text loads late on login: look again once
    if C_Timer and C_Timer.After then C_Timer.After(3, function() ns.MarkDirty() end) end
  end
  -- a playstyle that no longer exists (or is only kept for the sheet tests) -> the default
  local chosen = E.ROTATIONS[db.rotation]
  if not chosen or chosen.sheetOnly or (chosen.requires and (t[chosen.requires] or 0) <= 0) then
    db.rotation = E.DEFAULT_ROTATION
  end
  local rot = db.rotation
  local weights = (not st.invalid) and E.Weights(rot, st, input) or nil
  state = { input = input, st = st, t = t, info = info, rotation = rot, weights = weights, time = time() }
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
    print("  |cffff5050Could not read:|r " .. table.concat(S.info.how.missing, ", "))
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

  -- Model vs the game's own spell tooltips
  local rows, ok, off, none, fixed = S.info.client or {}, 0, {}, 0, 0
  for _, r in ipairs(rows) do
    if not r.client then none = none + 1
    elseif math.abs(r.client - r.model) <= 1 then ok = ok + 1
    else
      off[#off + 1] = r
      if r.after and math.abs(r.client - r.after) <= 1 then fixed = fixed + 1 end
    end
  end
  print(string.format("  Spell tooltips: %d of %d ranks match the model within 1 healing%s%s",
    ok, #rows, fixed > 0 and string.format(", %d more once corrected from the game", fixed) or "",
    none > 0 and string.format(" (%d had no readable tooltip yet)", none) or ""))
  for _, r in ipairs(off) do
    local how = {}
    if r.tooltipFull then
      how[#how + 1] = string.format("the game's tooltip leaves out downranking; real heals get %d%% of your healing power, and so does the model",
        math.floor(r.rulePower * 100 + 0.5))
    elseif r.baseFrom == "client" then how[#how + 1] = "base heal taken from the game" end
    local fixed = r.after and math.abs(r.client - r.after) <= 1
    print(string.format("    %s %d: game %.0f, model %.0f (%+.1f%%) - %s", E.SPELLS[r.key].name, r.rank, r.client, r.model,
      r.diff * 100, #how > 0 and (table.concat(how, "; ") .. (fixed and ", now matches" or ""))
        or "|cffff5050too far apart, not corrected|r"))
  end
  for _, r in ipairs(rows) do
    -- dataCost: the data's cost after your talents, as the game would show it
    local data = r.dataCost and math.floor(r.dataCost + 0.5)
    if r.costFrom == "client" and data and math.abs(r.clientCost - r.dataCost) >= 1 then
      print(string.format("    %s %d costs %d in game (game data with your talents %d) - using the game's", E.SPELLS[r.key].name, r.rank, r.clientCost, data))
    elseif r.clientCost and data and r.costFrom ~= "client" then
      print(string.format("    %s %d costs %d in game, game data with your talents %d - |cffff5050not taken (gap over 3%%)|r", E.SPELLS[r.key].name, r.rank, r.clientCost, data))
    end
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

  section("buffs", function() d.buffs = G.BuffNames() end)
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
    local snap = { time = d.time, level = d.level, inCombat = d.inCombat, healing = S and S.st.healing,
                   int = S and S.st.int, spirit = S and S.st.spirit, regen = { base, casting }, tooltips = {} }
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
  elseif what == "rot" and E.ROTATIONS[a] and not E.ROTATIONS[a].sheetOnly then db.rotation = a
  elseif what == "oh" and E.OVERHEAL_ALIASES[a:lower()] and tonumber(b) then
    db.settings.overheal[E.OVERHEAL_ALIASES[a:lower()]] = tonumber(b) / (tonumber(b) > 1 and 100 or 1)
  elseif what == "pomhits" and tonumber(a) then db.settings.pomHits = tonumber(a)
  elseif what == "tides" and tonumber(a) then db.settings.manaTidesInGroup = tonumber(a)
  elseif what == "pots" then db.settings.majorManaPotions = (a == "on")
  elseif what == "inspiration" then db.settings.includeInspiration = (a == "on")
  else
    local rots, ohs = {}, {}
    for k in pairs(E.ROTATIONS) do rots[#rots + 1] = k end
    for k in pairs(E.OVERHEAL_ALIASES) do ohs[#ohs + 1] = k end
    table.sort(rots); table.sort(ohs)
    say("set fight <seconds> | rot %s | oh <%s> <percent> | pomhits <n> | tides <n> | pots on|off | inspiration on|off",
      table.concat(rots, "|"), table.concat(ohs, "|"))
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
  elseif cmd == "show" or cmd == "recalc" then Summary()
  elseif cmd == "check" then Check()
  elseif cmd == "dump" then Dump()
  elseif cmd == "set" then Set(rest)
  else say("/hm (options window) | /hm show (summary in chat) | /hm check | /hm dump | /hm set ...") end
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
    merge(HolyMathDB[class], ClassDefaults(ns.model))
    merge(HolyMathDB[class], { tooltips = ns.TooltipDefaults() })
    ns.db = HolyMathDB[class]
    -- one-time: the old default fight length (300 s) becomes the new one (120 s)
    if not ns.db.fight120 then
      if ns.db.settings.fightLength == 300 then ns.db.settings.fightLength = 120 end
      ns.db.fight120 = true
    end
    -- A Forever build once threw while hooking tooltips (StatCap's notes); keep
    -- the rest of the addon working if it does.
    local ok, err = pcall(ns.HookTooltips)
    if not ok then ns.hookError = tostring(err); ns.LogError("hookTooltips", err) end
    for _, ev in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "UNIT_AURA", "UNIT_STATS", "PLAYER_LEVEL_UP",
                          "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED", "CHARACTER_POINTS_CHANGED",
                          "PLAYER_REGEN_ENABLED", "UNIT_MAXPOWER" }) do
      pcall(self.RegisterEvent, self, ev)
    end
    return
  end
  if (event == "UNIT_AURA" or event == "UNIT_STATS" or event == "UNIT_MAXPOWER") and unit ~= "player" then return end
  ns.MarkDirty()
  -- an open options window follows your gear/buffs/talents
  local O = ns.Options
  if O and O.frame and O.frame:IsShown() then O.Changed() end
end)
