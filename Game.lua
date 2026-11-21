--[[ Holy Math - Game.lua
     Everything that asks the game client something: your stats, talents, known
     spell ranks, buffs, item stats. Builds the inputs the Engine runs on.
     Every call is guarded: an API this client lacks just returns nothing.
]]--

local ADDON, ns = ...
-- E = the model for the player's class (set at login in Core.lua as ns.model).
local E = setmetatable({}, { __index = function(_, k) return ns.model and ns.model[k] end })
local G = {}
ns.Game = G

-- Last error per place + how often things ran; /hm dump saves both, so "no
-- tooltip line" can be told apart from "hook never fired" and "it errored".
ns.errors, ns.counts = {}, {}
function ns.LogError(where, err)
  local e = ns.errors[where] or { n = 0 }
  e.n, e.last = e.n + 1, tostring(err)
  ns.errors[where] = e
end
function ns.Count(what) ns.counts[what] = (ns.counts[what] or 0) + 1 end

local function safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  return unpack(r, 2)
end
G.safe = safe

-- Combat stats can be "secret" values on newer clients while in combat; any
-- arithmetic on them errors. Turn those into nil.
local function num(v)
  if v == nil then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  local ok, n = pcall(function() return v + 0 end)
  return ok and n or nil
end
G.num = num

local function spellName(id)
  if C_Spell and C_Spell.GetSpellName then return safe(C_Spell.GetSpellName, id) end
  return (safe(GetSpellInfo, id))
end
local function spellSubtext(id)
  if C_Spell and C_Spell.GetSpellSubtext then return safe(C_Spell.GetSpellSubtext, id) end
  return safe(GetSpellSubtext, id)
end
G.spellName, G.spellSubtext = spellName, spellSubtext

-- spellID -> engine key and rank, or nil when either can't be read.
function G.SpellKeyRank(id)
  local name = id and spellName(id)
  local key = name and E.SPELL_KEYS and E.SPELL_KEYS[name]
  if not key then return nil end
  local sub = spellSubtext(id)
  local rank = type(sub) == "string" and tonumber(sub:match("(%d+)"))
  if not rank then
    -- Spells with one rank show no "Rank 1" text
    if #E.SPELLS[key].ranks == 1 then rank = 1 else return key, nil end
  end
  return key, rank
end

---------------------------------------------------------------------------
-- Spellbook: highest known rank per healing spell (+ the spellIDs, for /hm dump)
---------------------------------------------------------------------------
-- Also returns `raw`: every spellbook entry (id, name, rank text), matched or
-- not, so /hm dump shows how this client names and ranks spells.
function G.KnownSpells()
  local known, ids, raw = {}, {}, {}
  local function add(id)
    if #raw < 400 then raw[#raw + 1] = { id = id, name = spellName(id), sub = spellSubtext(id) } end
    local key, rank = G.SpellKeyRank(id)
    if key and rank then
      if not known[key] or rank > known[key] then known[key] = rank end
      ids[#ids + 1] = { id = id, key = key, rank = rank }
    end
  end
  local SB = C_SpellBook
  if SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank then
    for line = 1, safe(SB.GetNumSpellBookSkillLines) or 0 do
      local info = safe(SB.GetSpellBookSkillLineInfo, line)
      if type(info) == "table" then
        for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
          local it = safe(SB.GetSpellBookItemInfo, i, Enum.SpellBookSpellBank.Player)
          if type(it) == "table" and it.spellID then add(it.spellID) end
        end
      end
    end
  elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
    for tab = 1, GetNumSpellTabs() do
      local _, _, offset, n = GetSpellTabInfo(tab)
      for i = offset + 1, offset + n do
        local _, id = safe(GetSpellBookItemInfo, i, BOOKTYPE_SPELL or "spell")
        if id then add(id) end
      end
    end
  end
  return known, ids, raw
end

---------------------------------------------------------------------------
-- Talents: ranks by name, read from Forever's single trait tree (same route
-- StatCap uses), with the classic talent API as a fallback.
---------------------------------------------------------------------------
-- returns { [talent name] = { rank =, max =, spellID = } }
function G.TalentsByName()
  local out = {}
  local CT, TR = C_ClassTalents, C_Traits
  if CT and TR and CT.GetActiveConfigID and TR.GetConfigInfo and TR.GetTreeNodes and TR.GetNodeInfo then
    local configID = safe(CT.GetActiveConfigID)
    local cfg = configID and safe(TR.GetConfigInfo, configID)
    local treeID = type(cfg) == "table" and type(cfg.treeIDs) == "table" and cfg.treeIDs[1]
    local nodes = treeID and safe(TR.GetTreeNodes, treeID)
    for _, nodeID in ipairs(type(nodes) == "table" and nodes or {}) do
      local node = safe(TR.GetNodeInfo, configID, nodeID)
      if type(node) == "table" then
        local entryID = (type(node.activeEntry) == "table" and node.activeEntry.entryID)
          or (type(node.entryIDs) == "table" and node.entryIDs[1])
        local entry = entryID and safe(TR.GetEntryInfo, configID, entryID)
        local def = type(entry) == "table" and entry.definitionID and safe(TR.GetDefinitionInfo, entry.definitionID)
        local name = type(def) == "table" and def.overrideName
        if (type(name) ~= "string" or name == "") and type(def) == "table" and def.spellID then name = spellName(def.spellID) end
        if type(name) == "string" and name ~= "" then
          out[name] = { rank = num(node.ranksPurchased) or 0, max = num(node.maxRanks),
                        spellID = type(def) == "table" and def.spellID or nil }
        end
      end
    end
    if next(out) then return out, "traits" end
  end
  if GetNumTalentTabs and GetTalentInfo then
    for tab = 1, GetNumTalentTabs() do
      for i = 1, (GetNumTalents and GetNumTalents(tab)) or 0 do
        local name, _, _, _, rank, maxRank = safe(GetTalentInfo, tab, i)
        if name then out[name] = { rank = rank or 0, max = maxRank } end
      end
    end
    if next(out) then return out, "classic" end
  end
  return out, "none"
end

-- Engine talent table (ranks) from what the game reports. Missing = 0.
function G.TalentRanks(byName)
  local r = {}
  for key, name in pairs(E.TALENT_NAMES) do r[key] = byName[name] and byName[name].rank or 0 end
  return r
end

---------------------------------------------------------------------------
-- Buffs and race (they change what +1 of a stat on gear is worth)
---------------------------------------------------------------------------
function G.BuffNames()
  local names = {}
  for i = 1, 60 do
    local name
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local a = safe(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
      name = type(a) == "table" and a.name
    elseif UnitBuff then
      name = safe(UnitBuff, "player", i)
    end
    if not name then break end
    if not (issecretvalue and issecretvalue(name)) then names[#names + 1] = name end
  end
  return names
end

local function hasBuff(names, pattern)
  for _, n in ipairs(names) do if n:find(pattern) then return true end end
  return false
end

---------------------------------------------------------------------------
-- Live stats -> the Engine's final-stat table, plus a record of how each number
-- was obtained (shown by /hm check, saved by /hm dump).
---------------------------------------------------------------------------
-- how.missing lists every read that came back empty. Healing power, max mana
-- and regen are required: without them the state is marked invalid and no
-- numbers are shown (better nothing than a confident wrong number).
function G.ReadStats(talentRanks)
  local how = { missing = {} }
  local function need(label, v, fallback)
    if v == nil then how.missing[#how.missing + 1] = label; return fallback end
    return v
  end
  local st = { level = need("UnitLevel", num(safe(UnitLevel, "player")), 60), critMulti = 1.5 }
  st.healing = need("GetSpellBonusHealing", num(safe(GetSpellBonusHealing)))
  st.spelldamage = need("GetSpellBonusDamage", num(safe(GetSpellBonusDamage, 2)), 0)
  st.int = need("UnitStat intellect", num(select(2, safe(UnitStat, "player", 4))), 0)
  st.spirit = need("UnitStat spirit", num(select(2, safe(UnitStat, "player", 5))), 0)
  st.manaPool = need("UnitPowerMax mana", num(safe(UnitPowerMax, "player", 0)))

  -- Crit: the client's Holy crit. Holy Specialization adds crit to Holy spells
  -- only; if the client's Holy number is higher than Shadow's by exactly that
  -- talent, it's already counted, otherwise we add it ourselves.
  local hs, school, other, label = E.CritTalent(talentRanks)
  local holy = need("GetSpellCritChance", num(safe(GetSpellCritChance, school)), 0)
  local shadow = num(safe(GetSpellCritChance, other)) or holy
  local included = hs > 0 and (holy - shadow) >= hs - 0.05
  st.crit = holy / 100 + ((hs > 0 and not included) and hs * 0.01 or 0)
  how.crit = string.format("school %d: %.2f%%, school %d: %.2f%%, %s %d %s", school, holy, other, shadow, label, hs,
    hs == 0 and "" or (included and "(already in the client's number)" or "(added by us)"))
  local perInt, from = E.CritPerInt(st.level)
  how.critParts = { client = holy / 100, talent = (hs > 0 and not included) and hs * 0.01 or 0, included = included,
                    holySpec = hs, perInt = perInt, perIntFrom = from }
  how.crit = how.crit .. string.format("; intellect: %.1f per 1%% crit at level %d (%s)", 1 / perInt, st.level, from)

  local haste = num(safe(UnitSpellHaste, "player")) or 0
  st.haste = haste / 100

  -- Regen (client, per second). Read from the 20 Nov dump: BOTH numbers include
  -- mp5 (gear 11 + Warchief's Blessing 10 = 21 = the casting number with no
  -- Meditation). So: base = spirit + mp5, casting = share x spirit + mp5.
  local base, casting = safe(GetManaRegen)
  base, casting = num(base), num(casting)
  if base == nil or casting == nil then
    how.missing[#how.missing + 1] = "GetManaRegen"
    st.invalid = true
    base, casting = base or 0, casting or 0
  end
  if st.healing == nil or st.manaPool == nil then st.invalid = true end
  st.healing, st.manaPool = st.healing or 0, st.manaPool or 0
  -- the part of healing power that comes from spirit (Spiritual Guidance)
  st.healingFromSpirit = (st.spirit or 0) * (E.Talents(talentRanks).spiritualGuidance or 0)
  local med = E.CastingRegenShare(talentRanks)
  local spiritRegen = med < 1 and math.max(0, (base - casting) / (1 - med)) or 0   -- per second
  st.oocRegen = spiritRegen * 5                     -- from spirit, out of the 5-second rule
  st.combatRegen = spiritRegen * 5 * med            -- from spirit, while casting
  st.mp5 = math.max(0, (casting - med * spiritRegen) * 5)
  how.regenParts = { base = base, casting = casting, share = med, spiritRegen = spiritRegen }
  local formula = 5 * (E.DATA.regen.base + E.DATA.regen.perSpirit * st.spirit)   -- game data, per 5 sec
  how.regen = string.format("client: %.1f per 5 s out of combat, %.1f while casting -> spirit %.1f (game data formula %.1f, %+.1f%%), MP5 %.1f, %d%% of spirit regen while casting",
    base * 5, casting * 5, st.oocRegen, formula, (st.oocRegen / formula - 1) * 100, st.mp5, med * 100)
  return st, how
end

-- Everything the Engine needs, from the game + saved settings.
function G.BuildInput(db)
  local byName, talentSource = G.TalentsByName()
  local ranks = G.TalentRanks(byName)
  local known, ids = G.KnownSpells()
  E.AdjustTalents(ranks, known, byName)
  local st, how = G.ReadStats(ranks)
  local buffs = G.BuffNames()
  local _, race = UnitRace("player")
  local settings = E.copy(db.settings)
  settings.known = known
  local input = {
    level = st.level, talents = ranks, consumables = {},
    regenPerSpirit = 5 * E.DATA.regen.perSpirit,   -- per 5 sec; game data, matched the client exactly (20 Nov dump)
    buffs = { kings = hasBuff(buffs, "Kings"), shadowSpirit = db.settings.shadowSpiritBuff or false },
    race = { human = race == "Human", gnome = race == "Gnome", dwarf = race == "Dwarf", troll = race == "Troll" },
    settings = settings,
  }
  return input, st, { how = how, talentSource = talentSource, talentsByName = byName, buffs = buffs, spellIds = ids }
end

-- Cost and tooltip text of each known healing spell rank, for E.ApplyClientData.
-- `pending` is true when the client hadn't loaded some tooltip text yet.
function G.ClientSpells(ids)
  local out, pending = {}, false
  for _, s in ipairs(ids or {}) do
    local cost
    local costs = (C_Spell and C_Spell.GetSpellPowerCost and safe(C_Spell.GetSpellPowerCost, s.id))
      or (GetSpellPowerCost and safe(GetSpellPowerCost, s.id))
    if type(costs) == "table" and costs[1] then cost = num(costs[1].cost) end
    local desc = (C_Spell and C_Spell.GetSpellDescription and safe(C_Spell.GetSpellDescription, s.id))
      or (GetSpellDescription and safe(GetSpellDescription, s.id))
    if type(desc) ~= "string" or desc == "" or (issecretvalue and issecretvalue(desc)) then desc = nil; pending = true end
    out[#out + 1] = { key = s.key, rank = s.rank, id = s.id, cost = cost, desc = desc }
  end
  return out, pending
end

---------------------------------------------------------------------------
-- Item stats from the tooltip text (Forever gear uses the classic wording,
-- e.g. "Equip: Improves your chance to get a critical strike with spells by 1%.")
---------------------------------------------------------------------------
local PATTERNS = {
  { "^%+(%d+) intellect", "int" },
  { "^%+(%d+) spirit", "spirit" },
  -- All the healing wordings seen in Forever (20 Nov dump):
  --   "Increases healing done by up to 26 and damage done by up to 9 for all magical spells and effects."
  --   "Increases damage and healing done by magical spells and effects by up to 8."
  --   "Increases healing done by spells and effects by up to 44."
  { "healing done by up to (%d+)", "healing" },
  { "healing done by [^%d]-up to (%d+)", "healing" },
  { "increases spell power by (%d+)", "healing" },
  { "^%+(%d+) healing", "healing" },                 -- enchants: "+55 Healing Spells"
  { "^%+(%d+) spell power", "healing" },
  { "(%d+) mana per 5 sec", "mp5" },
  { "(%d+) mana every 5 sec", "mp5" },
  { "critical strike with spells by (%d+)%%", "crit" },
  { "critical strike with holy spells by (%d+)%%", "crit" },
  { "spell critical strike chance by (%d+)%%", "crit" },
  { "casting speed by (%d+)%%", "haste" },
}

local scanTip
local function tooltipLines(link)
  local lines = {}
  if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
    local data = safe(C_TooltipInfo.GetHyperlink, link)
    if type(data) == "table" and type(data.lines) == "table" then
      for i = 2, #data.lines do
        local t = data.lines[i].leftText
        if type(t) == "string" then lines[#lines + 1] = t end
      end
      return lines
    end
  end
  scanTip = scanTip or CreateFrame("GameTooltip", "HolyMathScanTip", nil, "GameTooltipTemplate")
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:ClearLines()
  if not pcall(scanTip.SetHyperlink, scanTip, link) then return lines end
  for i = 2, scanTip:NumLines() do
    local fs = _G["HolyMathScanTipTextLeft" .. i]
    local t = fs and fs:GetText()
    if t then lines[#lines + 1] = t end
  end
  return lines
end
G.tooltipLines = tooltipLines

-- Drop the enchant from an item link, so items are compared on their own stats.
function G.StripEnchant(link)
  return (link:gsub("(|Hitem:%d+):%d*", "%1:"))
end

local statCache = {}
-- returns stats table, plus flags: .hasUse (Use:/proc lines we can't value)
-- The game's own stat table for an item (C_Item.GetItemStats), mapped to ours.
-- Checked against 18 items (21 Nov dump): it agrees with the tooltip text on every
-- one, and reads the same in every language. "Spell power" here is Forever's
-- "damage and healing done by magical spells" line, so it counts as healing.
local GAME_STAT = {
  ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spirit",
  ITEM_MOD_SPELL_HEALING_DONE_SHORT = "healing", ITEM_MOD_SPELL_POWER_SHORT = "healing",
  ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
}
G.FROM_GAME = { int = true, spirit = true, healing = true, mp5 = true }
function G.StatsFromGame(stats)
  if type(stats) ~= "table" then return nil end
  local t, any = {}, false
  for k, v in pairs(stats) do
    local key = GAME_STAT[k]
    if key and type(v) == "number" then t[key] = (t[key] or 0) + v; any = true end
  end
  return t, any
end

-- Item stats: intellect, spirit, healing and mp5 from the game's stat table; crit,
-- haste and the use/proc note from the tooltip text (the game's table has no
-- percent crit on this client). If the game hasn't loaded the item yet, all from
-- the text. Where both give a number and disagree, the game wins and it's counted
-- for /hm dump.
function G.ItemStats(link)
  if type(link) ~= "string" then return nil end
  link = G.StripEnchant(link)
  if statCache[link] then return statCache[link] end
  local t = G.StatsFromLines(tooltipLines(link))
  local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
  local game, any = G.StatsFromGame(safe(getStats, link))
  if any then
    for key in pairs(G.FROM_GAME) do
      if (t[key] or 0) ~= (game[key] or 0) then ns.Count("itemStatMismatch") end
      t[key] = game[key]
    end
    t.source = "game"
  else
    t.source = "text"
  end
  statCache[link] = t
  return t
end

-- The text -> stats step on its own (tested on real item text in tests/).
function G.StatsFromLines(lines)
  local t = {}
  for _, text in ipairs(lines) do
    local low = text:lower():gsub("^equip: ", "")
    if low:match("^%(%d+%) set") or low:match("^socket bonus") then
      -- set and socket bonuses are conditional: not counted
    elseif low:match("^use: ") or low:match("chance on")
        or (low:match("chance to") and not low:match("critical strike")) then
      t.hasUse = true
    else
      for _, p in ipairs(PATTERNS) do
        local n = low:match(p[1])
        if n then t[p[2]] = (t[p[2]] or 0) + (tonumber(n) or 0); break end
      end
    end
  end
  return t
end

-- Item slot(s) an item would replace.
local SLOTS = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
  INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
  INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
  INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 },
  INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16, both = true },
  INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_SHIELD = { 17 },
  INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_WAND = { 18 },
}
-- Why the player can't use this item, or nil if they can. Checked by the game's
-- item class/subclass ids (not translated), plus the "Classes: ..." line on
-- class-locked items (read with the client's own wording, ITEM_CLASSES_ALLOWED).
local ARMOR_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Armor) or 4
local WEAPON_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
local ARMOR_RANK = { [1] = 1, [2] = 2, [3] = 3, [4] = 4 }      -- cloth, leather, mail, plate
local SHIELD = 6
local ARMOR_SLOTS = { INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
  INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true }

local function classesPattern()
  local fmt = rawget(_G, "ITEM_CLASSES_ALLOWED")   -- "Classes: %s"
  if type(fmt) ~= "string" then return nil end
  -- park %s first, escape everything else (the % sign too), then put the capture in
  local p = fmt:gsub("%%s", "\1"):gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1"):gsub("\1", "(.+)")
  return "^" .. p .. "$"
end

local lockCache = {}
function G.CannotEquip(link)
  if type(link) ~= "string" or not E.EQUIP then return nil end
  local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  local _, _, subType, equipLoc, _, classID, subclassID = safe(info, link)
  if classID == WEAPON_CLASS and subclassID and E.EQUIP.noWeapon[subclassID] then
    return "can't use " .. (subType or "this weapon type")
  end
  if classID == ARMOR_CLASS then
    if subclassID == SHIELD and E.EQUIP.noShield then return "can't use shields" end
    local rank = ARMOR_RANK[subclassID or -1]
    if ARMOR_SLOTS[equipLoc or ""] and rank and rank > E.EQUIP.armorRank then
      return "can't wear " .. (subType or "this armor type")
    end
  end
  -- class-locked items (e.g. tier pieces)
  local id = tonumber(link:match("item:(%d+)"))
  if id and lockCache[id] ~= nil then return lockCache[id] or nil end
  local pat = classesPattern()
  if not pat then return nil end
  local lines = tooltipLines(link)
  if #lines == 0 then return nil end          -- not loaded yet: ask again next time
  local me = UnitClass("player")              -- in the client's language, like the line
  local reason = false
  for _, text in ipairs(lines) do
    local list = text:match(pat)
    if list then
      if me and not list:find(me, 1, true) then reason = "for " .. list .. " only" end
      break
    end
  end
  if id then lockCache[id] = reason end
  return reason or nil
end

-- True when a two-hander is equipped (then a one-hand or off-hand alone can't
-- be judged: it needs a partner item that we don't know).
function G.TwoHanderEquipped()
  local link = GetInventoryItemLink("player", 16)
  if not link then return false end
  local _, loc = G.SlotsFor(link)
  return loc == "INVTYPE_2HWEAPON"
end

function G.SlotsFor(link)
  local equipLoc
  if C_Item and C_Item.GetItemInfoInstant then equipLoc = select(4, safe(C_Item.GetItemInfoInstant, link))
  elseif GetItemInfoInstant then equipLoc = select(4, safe(GetItemInfoInstant, link)) end
  return equipLoc and SLOTS[equipLoc], equipLoc
end

-- Stats of what is in a slot now (enchant removed); nil link = empty slot.
function G.EquippedStats(slot)
  local link = GetInventoryItemLink("player", slot)
  return link and G.ItemStats(link) or {}, link
end

function G.ClearItemCache() statCache = {} end
