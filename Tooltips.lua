--[[ Holy Math - Tooltips.lua
     Item tooltips: how much effective HPS the item gains or loses you, by running
     the whole model with the item swapped in (not a weight shortcut).
     Spell tooltips (healing spells you know): what the rank heals per mana and per
     second after overheal, and which of your ranks is the most efficient - the same
     numbers as Your spells on the Math tab. The game's own tooltip can leave out
     downranking (and does in dungeons), so these come from the model, not from it.
]]--

local ADDON, ns = ...
local G = ns.Game
local E = setmetatable({}, { __index = function(_, k) return ns.model and ns.model[k] end })

local GREEN, RED, GRAY, GOLD = "|cff40ff40", "|cffff5050", "|cff9d9d9d", "|cffffd100"
local TAG = GOLD .. "Holy Math|r"

local function fmtInt(n) return tostring(math.floor((n or 0) + 0.5)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
local RELEVANT = { "healing", "int", "spirit", "mp5", "crit", "haste" }

local function sumStats(slots)
  local out, links = {}, {}
  for _, s in ipairs(slots) do
    local st, link = G.EquippedStats(s)
    for _, k in ipairs(RELEVANT) do out[k] = (out[k] or 0) + (st[k] or 0) end
    links[#links + 1] = link
  end
  return out, links
end

-- An item link's key in the item data: "id", or "id:suffix" when its first bonus ID is a
-- random suffix the data knows (the link's 13th field is how many bonus IDs follow).
function ns.LinkKey(link)
  local str = type(link) == "string" and link:match("item:([%-%d:]+)")
  if not str then return nil end
  local f = {}
  for v in (str .. ":"):gmatch("([^:]*):") do f[#f + 1] = v end
  local id, n, bonus = tonumber(f[1]), tonumber(f[13]), tonumber(f[14])
  if not id then return nil end
  if n and n > 0 and bonus then
    local key = id .. ":" .. bonus
    local D = ns.GearData
    if D and D.byKey and D.byKey[key] then return key end
  end
  return tostring(id), id
end

-- What a linked item's use and proc effects are worth to you (stats on average, healing
-- a second), from the item data, in your fight now: for the item tooltips everywhere.
-- r: the playstyle's result whose casts the procs roll on (default: yours).
function ns.GearEffectsFor(link, S, r)
  local D, solver = ns.GearData, ns.GearSolve
  if not (D and solver and S and S.weights and S.weights.base) then return nil end
  local key = ns.LinkKey(link)
  local it = key and D.byKey and (D.byKey[key] or D.byKey[key:match("^(%d+)")])
  if not (it and it.fx) then return nil end
  local set = S.input.settings
  r = r or S.weights.base
  local ctx = { fl = set.fightLength, casts = {}, oh = set.overheal and set.overheal.FLASH or 0, pull = set.pullEvery }
  local total = (r.fiveSecondCasts or 0) + (r.innerFocus and r.innerFocus.casts or 0)
  for _, s in ipairs(r.steps or {}) do
    ctx.casts[s.key] = (ctx.casts[s.key] or 0) + s.casts + (s.pauseCasts or 0)
    total = total + s.casts
  end
  ctx.cps = total / math.max(1, set.fightLength)
  return solver.Effects(it, ctx)
end

local function itemID(link) return link and tonumber(link:match("item:(%d+)")) end

-- Two links are the same item: the same ID, and the same random suffix ("of Healing")
-- where the item data knows it (the link key above).
local function sameItem(a, b)
  if not (a and b) then return false end
  local key = ns.LinkKey
  if key then
    local ka, kb = key(a), key(b)
    if ka and kb then return ka == kb end
  end
  return itemID(a) == itemID(b)
end

-- An item link's name in its quality colour ("an empty slot" for none), to say which
-- of two rings or trinkets a number is against.
function ns.ItemLinkName(link)
  if type(link) ~= "string" then return "an empty slot" end
  local name = link:match("|h%[(.-)%]|h")
  if not name then return "an empty slot" end
  local col = link:match("^(|c%x%x%x%x%x%x%x%x)")
  return col and (col .. name .. "|r") or name
end

-- An item's value as the item tooltips show it (the Consumables tab's too): "+16.2 HPS (+1.8%)",
-- or one of them (the settings Show HPS and Show %), in green, red or gray. r = { d, pct }.
-- worth: what an item you wear gives you, not a change, so in white with no sign and no %
-- ("5.9 HPS"; the % only when the number is switched off; a loss still red with its minus).
-- With both switched off (item tooltips then add nothing) the Consumables tab still shows both.
function ns.TipValue(r, worth)
  local tip = ns.db and ns.db.tooltips or {}
  local showNumber, showPct = tip.itemNumber ~= false, tip.itemPercent ~= false
  if not (showNumber or showPct) then showNumber, showPct = true, true end
  local col = r.d > 0.05 and GREEN or (r.d < -0.05 and RED or GRAY)
  local fmt = "%+.1f"
  if worth and r.d >= 0 then col, fmt = "|cffffffff", "%.1f" end
  local pct = string.format(fmt .. "%%", (r.pct or 0) * 100)
  local text = showNumber and string.format(fmt .. " HPS", r.d) or pct
  if showNumber and showPct and not worth then text = text .. " (" .. pct .. ")" end
  return col .. text .. "|r"
end

local verdictCache, baseCache = {}, {}
function ns.ClearVerdicts() verdictCache, baseCache = {}, {} end

-- The playstyle item tooltips are worked out for: the one Holy Math counts you as
-- (Core.lua's best playstyle for you).
function ns.TooltipStyles(S)
  S = S or ns.State()
  return { S and S.rotation }
end

-- A playstyle's result with your stats now (yours is already worked out).
local function baseFor(S, key)
  if key == S.rotation and S.weights and S.weights.base then return S.weights.base end
  if baseCache[key] == nil then
    local input = S.input
    local t = E.Talents(input.talents, input.settings.rules, input.settings.overrides)
    baseCache[key] = E.Rotation(key, S.st, t, input.settings) or false
  end
  return baseCache[key] or nil
end

-- What the item does for you in each playstyle: { rows = { { key, name, d, pct } },
-- same, over, hasUse }. A ring or trinket is weighed against the one it beats most
-- in the first playstyle, and the others against that same one.
local function Verdict(link)
  local S = ns.State()
  if not S or not S.weights then return nil end
  if verdictCache[link] then return verdictCache[link] end
  local slots = G.SlotsFor(link)
  if not slots then return nil end
  local new = G.ItemStats(link)
  if not new then return nil end

  local candidates = {}
  if slots.both then candidates[1] = { 16, 17 }
  else for _, s in ipairs(slots) do candidates[#candidates + 1] = { s } end end

  -- A one-hand or off-hand next to an equipped two-hander would be compared
  -- against an empty slot; it needs a partner we don't know, so stay silent.
  if not slots.both and (slots[1] == 16 or slots[1] == 17) and G.TwoHanderEquipped() then
    verdictCache[link] = false
    return nil
  end

  -- a ring or trinket you wear in one of its two slots: that slot only, so it shows its
  -- worth instead of being weighed against the other one
  if #candidates > 1 then
    for _, cand in ipairs(candidates) do
      local _, links = sumStats(cand)
      if sameItem(links[1], link) then candidates = { cand }; break end
    end
  end

  -- use and proc effects (trinkets above all), on average over your fight with the
  -- playstyle's casts: the item's, less those of what it replaces (ns.GearEffectsFor, from the
  -- item data)
  local function effects(l, r)
    if not (l and ns.GearEffectsFor) then return nil, 0 end
    local ok, add, heal = pcall(ns.GearEffectsFor, l, S, r)
    if ok and add then return add, heal or 0 end
    return nil, 0
  end
  -- the item in place of one candidate, in one playstyle: d (effective HPS), pct
  local function weigh(cand, key)
    local base = baseFor(S, key)
    if not base then return nil end
    local newFx, newHeal = effects(link, base)
    local old, links = sumStats(cand)
    local same = sameItem(links[1], link)
    local diff, any = {}, newFx ~= nil or newHeal > 0
    local heal = newHeal
    for _, k in ipairs(RELEVANT) do
      diff[k] = (new[k] or 0) - (old[k] or 0) + (newFx and newFx[k] or 0)
      if (new[k] or 0) ~= 0 or (old[k] or 0) ~= 0 then any = true end
    end
    for _, l in ipairs(links) do
      local oldFx, oldHeal = effects(l, base)
      if oldFx then any = true; for k, v in pairs(oldFx) do diff[k] = (diff[k] or 0) - v end end
      heal = heal - oldHeal
    end
    if not (any or same) then return nil end
    local d, pct = E.Compare(key, S.st, S.input, diff)
    if not d then return nil end
    d = d + heal
    pct = base.ehps > 0 and d / base.ehps or pct
    return { d = d, pct = pct, same = same, links = links, newFx = newFx }
  end

  local styles = ns.TooltipStyles(S)
  local first, pick, best = styles[1], nil, nil
  local each = {}   -- two rings or trinkets: the item in place of each, best first
  for _, cand in ipairs(candidates) do
    local w = weigh(cand, first)
    if w then each[#each + 1] = { over = w.links[1] or false, d = w.d, pct = w.pct } end
    if w and (not best or w.d > best.d) then best, pick = w, cand end
  end
  if not best then verdictCache[link] = false; return nil end
  local out = { rows = {}, same = best.same }
  if #candidates > 1 then
    out.over = best.links[1] or false   -- false = an empty slot
    table.sort(each, function(a, b) return a.d > b.d end)
    -- two of the same item worn: one line says it
    if #each == 2 and each[1].over and each[2].over and sameItem(each[1].over, each[2].over) then each[2] = nil end
    out.each = each
  end
  for i, key in ipairs(styles) do
    local w = i == 1 and best or weigh(pick, key)
    if w then
      local r = E.ROTATIONS[key]
      out.rows[#out.rows + 1] = { key = key, name = r and r.name or key, d = w.d, pct = w.pct }
    end
  end
  out.hasUse = new.hasUse and not best.newFx   -- an effect the data has is in the number
  -- the item you wear: what it gives you, against an empty slot, in the first playstyle
  if best.same then
    local base = baseFor(S, first)
    local fx, heal = effects(link, base)
    local diff = {}
    for _, k in ipairs(RELEVANT) do diff[k] = (new[k] or 0) + (fx and fx[k] or 0) end
    local d = E.Compare(first, S.st, S.input, diff)
    if d then
      d = d + heal
      -- a share of your healing now, which has the item in it
      out.worth = { d = d, pct = base.ehps > 0 and d / base.ehps or 0 }
    end
  end
  verdictCache[link] = out
  return out
end
ns.ItemVerdict = Verdict

local function AddItemLine(tt, link)
  ns.Count("itemHook")
  -- the Consumables tab's own tooltip: its lines instead, each time the game draws it
  if ns.enabled and tt.hmTabTip then
    if ns.Options and ns.Options.TabTipLines and tt.hmTabItem then pcall(ns.Options.TabTipLines, tt) end
    return
  end
  if not ns.enabled or type(link) ~= "string" or tt.fpLink == link then return end
  local tip = ns.db and ns.db.tooltips or {}
  local showNumber, showPct = tip.itemNumber ~= false, tip.itemPercent ~= false
  if tip.items == false or not (showNumber or showPct) then return end
  local okEq, why = pcall(G.CannotEquip, link)
  if not okEq then ns.LogError("cannotEquip", why); why = nil end
  if why then
    tt.fpLink = link
    tt:AddLine(TAG .. ": " .. GRAY .. why .. "|r")
    return
  end
  local ok, v = pcall(Verdict, link)
  if not ok then ns.LogError("itemTooltip", v); return end
  if not v or #v.rows == 0 then return end
  local isSame = v.same
  for _, r in ipairs(v.rows) do if math.abs(r.d) >= 0.05 then isSame = false end end
  tt.fpLink = link
  -- "+16.2 HPS (+1.8%)", or one of them, in green, red or gray. worth: what an item you
  -- wear gives you, not a change, so in white with no sign and no % ("5.9 HPS"; the %
  -- only when the number is switched off; a loss still red with its minus)
  local function value(r, worth) return ns.TipValue(r, worth) end
  if isSame and v.worth and math.abs(v.worth.d) >= 0.05 then
    -- what the item you wear gives you, over an empty slot; indented under the header
    -- like the game's own lists (Disenchant results)
    --   Holy Math
    --     Equipped                          26.2 HPS
    tt:AddLine(TAG)
    tt:AddDoubleLine("  Equipped", value(v.worth, true), 1, 1, 1, 1, 1, 1)
  elseif isSame then
    tt:AddLine(TAG .. ": equipped")
  elseif #v.rows == 1 then
    -- the value right-aligned under the header, like the game's own lists
    --   Holy Math
    --     Over what you wear                  +20.5 HPS (+1.9%)
    -- a ring or trinket: a line for each of the two you wear, best first
    --     In place of Snake Hoop               +7.1 HPS (+0.7%)
    --     In place of Healer's Band            -3.0 HPS (-0.3%)
    tt:AddLine(TAG)
    if v.each and #v.each > 0 then
      for _, e in ipairs(v.each) do
        tt:AddDoubleLine("  In place of " .. ns.ItemLinkName(e.over or nil), value(e), 1, 1, 1, 1, 1, 1)
      end
    else
      tt:AddDoubleLine("  Over what you wear", value(v.rows[1]), 1, 1, 1, 1, 1, 1)
    end
  else
    --   Holy Math
    --     Renew filler          +16.2 HPS (+1.8%)
    --     Flash Heal filler     +12.0 HPS (+1.9%)
    tt:AddLine(TAG)
    for _, r in ipairs(v.rows) do tt:AddDoubleLine("  " .. r.name, value(r), 1, 0.82, 0, 1, 1, 1) end
  end
  if not isSame and #v.rows > 1 and v.over ~= nil then tt:AddLine(GRAY .. "  in place of|r " .. ns.ItemLinkName(v.over or nil)) end
  if v.hasUse then tt:AddLine(GRAY .. "  Use or proc effect not counted|r") end
end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------
-- Per state (rebuilt when gear, buffs, talents or settings change): spell ID ->
-- the known rank, and each spell's ranks as Your spells works them out.
local spellCache = { state = nil, byId = {}, ranks = {} }

local function SpellRank(id)
  local S = ns.State()
  if not S or not S.weights or not S.info or not S.info.spellIds then return nil end
  if spellCache.state ~= S then
    spellCache = { state = S, byId = {}, ranks = {} }
    for _, s in ipairs(S.info.spellIds) do spellCache.byId[s.id] = s end
  end
  local s = spellCache.byId[id]
  if not s then return nil end
  local ranks = spellCache.ranks[s.key]
  if ranks == nil then
    ranks = E.SpellRanks(s.key, S.st, S.t, S.input.settings) or {}
    spellCache.ranks[s.key] = ranks
  end
  local this, best
  for _, rk in ipairs(ranks) do
    if rk.rank == s.rank then this = rk end
    if rk.bestRaw then best = rk end   -- by the raw per mana the tooltip shows
  end
  return this, best, #ranks
end

local function fmtHPM(v) return v == math.huge and "free" or string.format("%.2f", v) end

-- The client can hide values in combat ("secret"): even comparing one errors, so
-- that is checked before anything else.
local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function AddSpellLine(tt, id)
  ns.Count("spellHook")
  if isSecret(id) or type(id) ~= "number" or not ns.enabled or tt.hmSpell == id then return end
  local tip = ns.db and ns.db.tooltips or {}
  if tip.spells == false then return end
  local ok, this, best, n = pcall(SpellRank, id)
  if not ok then ns.LogError("spellTooltip", this); return end
  if not this then return end
  tt.hmSpell = id
  -- rows, raw like other addons show them: before overheal, at the spell's full cost, on
  -- your target (Holy Binding's heal on you is a row of its own)
  local raw = this.raw
  local function row(label, value) tt:AddDoubleLine("  " .. label, value, 1, 0.82, 0, 1, 1, 1) end
  tt:AddLine(TAG)
  row("Heal per mana", fmtHPM(raw.hpm))
  row("Heal per second", fmtInt(raw.hps))
  if raw.onYou > 0.5 then row("Also on you (Holy Binding)", fmtInt(raw.onYou)) end
  if n > 1 and best then
    if best.rank == this.rank then
      tt:AddLine(GREEN .. "  Your most efficient rank|r")
    else
      tt:AddLine(string.format("%s  Most efficient: Rank %d (%s per mana)|r", GRAY, best.rank, fmtHPM(best.raw.hpm)))
    end
  end
end

---------------------------------------------------------------------------
-- Hooks: the newer tooltip pipeline when GameTooltip runs it (Forever does),
-- otherwise the classic scripts. Same checks StatCap uses.
---------------------------------------------------------------------------
local function hasScript(frame, name)
  if not (frame and frame.HasScript) then return false end
  local ok, yes = pcall(frame.HasScript, frame, name)
  return ok and yes == true
end

function ns.HookTooltips()
  local pipeline = type(GameTooltip.ProcessInfo) == "function" and TooltipDataProcessor
    and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
  ns.hookPath = pipeline and "pipeline" or "classic scripts"
  if pipeline then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
      if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
      local link
      if TooltipUtil and TooltipUtil.GetDisplayedItem then link = select(2, TooltipUtil.GetDisplayedItem(tt))
      elseif tt.GetItem then link = select(2, tt:GetItem()) end
      AddItemLine(tt, link)
    end)
    -- spells: the spellbook, action bars and spell links
    if Enum.TooltipDataType.Spell then
      TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tt, data)
        if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
        local ok, err = pcall(function()
          local id = type(data) == "table" and data.id or nil
          if not isSecret(id) and id == nil and tt.GetSpell then id = select(2, tt:GetSpell()) end
          AddSpellLine(tt, id)
        end)
        if not ok then ns.LogError("spellTooltip", err) end
      end)
    end
  else
    if hasScript(GameTooltip, "OnTooltipSetItem") then
      GameTooltip:HookScript("OnTooltipSetItem", function(tt) AddItemLine(tt, select(2, tt:GetItem())) end)
    end
    if hasScript(GameTooltip, "OnTooltipSetSpell") then
      GameTooltip:HookScript("OnTooltipSetSpell", function(tt)
        local ok, err = pcall(function() AddSpellLine(tt, select(2, tt:GetSpell())) end)
        if not ok then ns.LogError("spellTooltip", err) end
      end)
    end
  end
  for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tt and hasScript(tt, "OnTooltipCleared") then
      tt:HookScript("OnTooltipCleared", function(t) t.fpLink = nil; t.hmSpell = nil end)
    end
  end
end
