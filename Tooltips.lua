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

local function itemID(link) return link and tonumber(link:match("item:(%d+)")) end

-- An item link's name in its quality colour ("an empty slot" for none), to say which
-- of two rings or trinkets a number is against.
function ns.ItemLinkName(link)
  if type(link) ~= "string" then return "an empty slot" end
  local name = link:match("|h%[(.-)%]|h")
  if not name then return "an empty slot" end
  local col = link:match("^(|c%x%x%x%x%x%x%x%x)")
  return col and (col .. name .. "|r") or name
end

local verdictCache = {}
function ns.ClearVerdicts() verdictCache = {} end

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

  -- use and proc effects (trinkets above all), on average over your fight: the item's,
  -- less those of what it replaces (Gear.lua, from the item data)
  local function effects(l)
    if not (l and ns.GearEffectsFor) then return nil, 0 end
    local ok, add, heal = pcall(ns.GearEffectsFor, l, S)
    if ok and add then return add, heal or 0 end
    return nil, 0
  end
  local newFx, newHeal = effects(link)
  local best
  for _, cand in ipairs(candidates) do
    local old, links = sumStats(cand)
    local same = links[1] and itemID(links[1]) == itemID(link)
    local diff, any = {}, newFx ~= nil or newHeal > 0
    local heal = newHeal
    for _, k in ipairs(RELEVANT) do
      diff[k] = (new[k] or 0) - (old[k] or 0) + (newFx and newFx[k] or 0)
      if (new[k] or 0) ~= 0 or (old[k] or 0) ~= 0 then any = true end
    end
    for _, l in ipairs(links) do
      local oldFx, oldHeal = effects(l)
      if oldFx then any = true; for k, v in pairs(oldFx) do diff[k] = (diff[k] or 0) - v end end
      heal = heal - oldHeal
    end
    if any or same then
      local d, pct = E.Compare(S.rotation, S.st, S.input, diff)
      if d then
        local base = S.weights.base and S.weights.base.ehps or 0
        d = d + heal
        pct = base > 0 and d / base or pct
        if not best or d > best.d then
          -- two rings or trinkets: say which one it's against
          best = { d = d, pct = pct, same = same }
          if #candidates > 1 then best.over = links[1] or false end   -- false: an empty slot
        end
      end
    end
  end
  if best then best.hasUse = new.hasUse and not newFx end   -- an effect the data has is in the number
  verdictCache[link] = best or false
  return best
end

local function AddItemLine(tt, link)
  ns.Count("itemHook")
  -- the Gear tab's own tooltip: its lines instead (with the item's random suffix), each
  -- time the game draws it
  if ns.enabled and tt.hmGearTip then
    if ns.Options and ns.Options.GearTipLines and tt.hmGearItem then pcall(ns.Options.GearTipLines, tt) end
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
  if not v then return end
  local isSame = v.same and math.abs(v.d) < 0.05
  tt.fpLink = link
  if isSame then
    tt:AddLine(TAG .. ": equipped")
  else
    local col = v.d > 0.05 and GREEN or (v.d < -0.05 and RED or GRAY)
    local pct = string.format("%+.1f%%", v.pct * 100)
    local text = showNumber and string.format("%+.1f HPS", v.d) or pct      -- "+16.2 HPS (+1.8%)", or one of them
    if showNumber and showPct then text = text .. " (" .. pct .. ")" end
    tt:AddLine(string.format("%s: %s%s|r", TAG, col, text))
    if v.over ~= nil then tt:AddLine(GRAY .. "  in place of|r " .. ns.ItemLinkName(v.over or nil)) end
  end
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
    if rk.best then best = rk end
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
  local hpm = this.hpm == math.huge and "free" or (fmtHPM(this.hpm) .. " healing per mana")
  tt:AddLine(string.format("%s: %s, %s per second", TAG, hpm, fmtInt(this.hps)), 1, 1, 1)
  if n > 1 and best then
    if best.rank == this.rank then
      tt:AddLine(GREEN .. "  Your most efficient rank|r")
    else
      tt:AddLine(string.format("%s  Most efficient: Rank %d (%s per mana)|r", GRAY, best.rank, fmtHPM(best.hpm)))
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
