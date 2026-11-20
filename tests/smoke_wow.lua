-- Loads the whole addon against a FAKE game API and drives it: login, /hm,
-- /hm check, /hm dump, an item tooltip and a spell tooltip. This only catches
-- Lua errors and wiring mistakes - it says nothing about the real client's
-- behaviour (that's what /hm dump in game is for).
-- Run from the HolyMath folder:  lua5.1 tests/smoke_wow.lua

local printed = {}
local realprint = print
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end printed[#printed + 1] = table.concat(t, " "); realprint(...) end

-- fake frames ---------------------------------------------------------------
local frames = {}
local noop = function() end
local function newFontString()
  local fs = {}
  for _, m in ipairs({ "SetPoint", "SetWidth", "SetHeight", "SetJustifyH", "SetJustifyV", "SetFontObject", "Hide", "Show" }) do fs[m] = noop end
  function fs:SetText(t) self.text = t end
  function fs:GetText() return self.text end
  return fs
end
local function newFrame(name)
  local f = { scripts = {}, events = {}, lines = {} }
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetScript(s, fn) self.scripts[s] = fn end
  function f:HookScript(s, fn) self.scripts[s] = fn end
  function f:HasScript() return true end
  function f:AddLine(t) self.lines[#self.lines + 1] = t end
  function f:SetOwner() end
  function f:ClearLines() self.lines = {} end
  function f:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
  function f:Hide() local was = self.shown; self.shown = false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
  function f:IsShown() return self.shown == true end
  function f:CreateFontString() return newFontString() end
  function f:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
  for _, m in ipairs({ "SetSize", "SetWidth", "SetHeight", "SetPoint", "ClearAllPoints", "SetFrameStrata", "SetMovable",
      "EnableMouse", "RegisterForDrag", "SetClampedToScreen", "SetToplevel", "StartMoving", "StopMovingOrSizing",
      "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "Raise", "CreateTexture", "SetAllPoints", "SetID" }) do f[m] = noop end
  frames[#frames + 1] = f
  if name then _G[name] = f end
  return f
end
-- Blizzard templates the options window uses, faked just enough to drive them.
local missingTemplates = {}      -- names listed here "don't exist" in this fake client
local TEMPLATES = {
  UIPanelButtonTemplate = function(f) function f:SetText(t) self.text = t end; function f:GetText() return self.text end end,
  PortraitFrameTemplate = function(f)
    function f:SetTitle(t) self.title = t end
    f.SetPortraitToAsset = noop
    f.CloseButton = newFrame()
    -- like the real template: the close button goes through the game's panel manager,
    -- which does nothing in combat
    f.CloseButton:SetScript("OnClick", function() if not InCombatLockdown() then f:Hide() end end)
  end,
  UICheckButtonTemplate = function(f)
    f.Text = newFontString()
    function f:SetChecked(v) self.checked = v end
    function f:GetChecked() return self.checked end
  end,
  MinimalSliderWithSteppersTemplate = function(f)
    f.Slider = { SetObeyStepOnDrag = noop }
    function f:Init(v, lo, hi, steps, formatters) self.value, self.lo, self.hi, self.fmt = v, lo, hi, formatters end
    function f:RegisterCallback(_, fn) self.onChange = fn end
    function f:SetValue(v) self.value = v; if self.onChange then self.onChange(nil, v) end end
  end,
  WowStyle1DropdownTemplate = function(f)
    function f:SetupMenu(gen) self.gen = gen end
    function f:SetSelectionTranslator(fn) self.translate = fn end
    f.GenerateMenu = noop
  end,
}
requestedTemplates = {}
CreateFrame = function(kind, name, parent, template)
  if template then requestedTemplates[template] = true end
  if template and missingTemplates[template] then error("Couldn't find inherited node: " .. template) end
  local f = newFrame(name)
  if template and TEMPLATES[template] then TEMPLATES[template](f) end
  return f
end
MinimalSliderWithSteppersMixin = { Label = { Right = 3 }, Event = { OnValueChanged = "OnValueChanged" } }
GameFontHighlightSmall = {}
UISpecialFrames = {}
PlaySound = noop
GameTooltip = newFrame(); GameTooltip.ProcessInfo = function() end
function GameTooltip:SetText(t) self.lines = { t } end
GameTooltip.SetAction = function() end
hooksecurefunc = function(obj, name, fn)
  local orig = obj[name]
  if type(orig) ~= "function" then error("no method " .. name) end
  obj[name] = function(...) orig(...); fn(...) end
end
GetActionInfo = function(slot) return "spell", 107 end
C_Timer = { After = function(_, fn) fn() end }   -- runs at once in the fake client
ItemRefTooltip = newFrame()

local postCalls = {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) postCalls[kind] = fn end }
Enum = { TooltipDataType = { Item = 0, Spell = 1 }, SpellBookSpellBank = { Player = 0 } }

-- player -------------------------------------------------------------------
UnitClass = function() return "Priest", "PRIEST" end
UnitRace = function() return "Human", "Human" end
UnitLevel = function() return 60 end
GetSpellBonusHealing = function() return 828.587 end
GetSpellBonusDamage = function() return 331.5 end
UnitStat = function(_, i) local v = ({ 50, 50, 60, 407.77, 630.35 })[i]; return v, v, 0, 0 end
UnitPowerMax = function() return 8116.55 end
GetSpellCritChance = function(school) return school == 2 and 18.80 or 13.80 end -- Holy Spec 5 included
UnitSpellHaste = function() return 0 end
-- like the real client (20 Nov dump): both numbers include mp5
GetManaRegen = function() return (443.42 + 98) / 5, (221.71 + 98) / 5 end
InCombatLockdown = function() return false end
time = os.time; date = os.date
GetBuildInfo = function() return "1.16.0", "70000", "Nov 2026", 16001 end

-- talents: Forever's single trait tree
local TAL = { ["Twin Disciplines"] = 5, ["Improved Power Word: Shield"] = 2, ["Mental Agility"] = 3,
  ["Inner Focus"] = 1, ["Meditation"] = 3, ["Mental Strength"] = 5, ["Improved Renew"] = 3,
  ["Holy Specialization"] = 5, ["Divine Fury"] = 5, ["Inspiration"] = 3, ["Improved Healing"] = 3,
  ["Litany of Light"] = 2, ["Spiritual Guidance"] = 5, ["Spiritual Healing"] = 3, ["Prayer of Mending"] = 1 }
local talentList = {}
for name, r in pairs(TAL) do talentList[#talentList + 1] = { name = name, rank = r } end
C_ClassTalents = { GetActiveConfigID = function() return 1 end }
C_Traits = {
  GetConfigInfo = function() return { treeIDs = { 7 } } end,
  GetTreeNodes = function() local n = {} for i = 1, #talentList do n[i] = i end return n end,
  GetNodeInfo = function(_, id) return { ranksPurchased = talentList[id].rank, maxRanks = 5, activeEntry = { entryID = id } } end,
  GetEntryInfo = function(_, id) return { definitionID = id } end,
  GetDefinitionInfo = function(id) return { overrideName = talentList[id].name, spellID = 9000 + id } end,
}

-- spellbook: 100 + rank ids per spell
local BOOK = { { "Renew", 9 }, { "Greater Heal", 4 }, { "Flash Heal", 7 }, { "Binding Heal", 6 },
  { "Prayer of Healing", 4 }, { "Prayer of Mending", 3 }, { "Power Word: Shield", 10 }, { "Holy Nova", 6 } }
local spellIds, idInfo = {}, {}
for si, b in ipairs(BOOK) do
  for r = 1, b[2] do local id = si * 100 + r; spellIds[#spellIds + 1] = id; idInfo[id] = { b[1], "Rank " .. r } end
end
C_Spell = {
  GetSpellName = function(id) return idInfo[id] and idInfo[id][1] end,
  GetSpellSubtext = function(id) return idInfo[id] and idInfo[id][2] end,
  GetSpellDescription = function(id)
    -- what the game data predicts at 828.6 healing, level 60 (Renew r9 1990.5, GH r4 2757.8)
    if id == 109 then return "Heals the target of 1,990 damage over 15 sec." end
    if id == 204 then return "A slow casting spell that heals a single target for 2,640 to 2,876." end
    return ""
  end,
  GetSpellPowerCost = function(id) if id == 201 then return { { cost = 380 } } end return {} end, -- data: 370
  GetSpellInfo = function(id) return { castTime = 1500 } end,
}
C_SpellBook = {
  GetNumSpellBookSkillLines = function() return 1 end,
  GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #spellIds } end,
  GetSpellBookItemInfo = function(i) return { spellID = spellIds[i] } end,
}
C_UnitAuras = { GetAuraDataByIndex = function(_, i) return ({ { name = "Greater Blessing of Kings" }, { name = "Arcane Intellect" } })[i] end }

-- items ----------------------------------------------------------------------
local ITEMS = {
  ["|Hitem:1001:0:|h"] = { loc = "INVTYPE_HEAD", lines = { "Cowl", "+20 Intellect", "+15 Spirit", "Equip: Increases healing done by spells and effects by up to 44." } },
  ["|Hitem:1002:0:|h"] = { loc = "INVTYPE_HEAD", lines = { "Better Cowl", "+22 Intellect", "+18 Spirit",
      "Equip: Increases healing done by spells and effects by up to 62.", "Equip: Improves your chance to get a critical strike with spells by 1%." } },
  ["|Hitem:1003:0:|h"] = { loc = "INVTYPE_TRINKET", lines = { "Trinket", "Use: Restores 900 mana." } },
}
C_TooltipInfo = { GetHyperlink = function(link)
  local it = ITEMS["|Hitem:" .. link:match("item:(%d+)") .. ":0:|h"]; if not it then return { lines = {} } end
  local l = {} for i, t in ipairs(it.lines) do l[i] = { leftText = t } end return { lines = l } end }
C_Item = { GetItemInfoInstant = function(link)
  local it = ITEMS["|Hitem:" .. link:match("item:(%d+)") .. ":0:|h"]
  return 1, "Armor", it and it.subType or "Cloth", it and it.loc, 0, it and it.class or 4, it and it.sub or 1
end }
ITEM_CLASSES_ALLOWED = "Classes: %s"
GetInventoryItemLink = function(_, slot) return slot == 1 and "|Hitem:1001:0:|h" or nil end
TooltipUtil = { GetDisplayedItem = function(tt) return "x", tt.fakeLink end }
SlashCmdList = {}

-- load the addon -------------------------------------------------------------
local ns = {}
for _, f in ipairs({ "Models/PriestData.lua", "Models/Priest.lua", "Game.lua", "Tooltips.lua", "Core.lua", "Options.lua" }) do
  assert(loadfile(f))("HolyMath", ns)
end
local core = frames[#frames]                      -- Core's event frame
core.scripts.OnEvent(core, "PLAYER_LOGIN")
assert(ns.enabled, "should enable on a priest")

local fails = 0
local function expect(cond, what) if not cond then fails = fails + 1; realprint("FAIL " .. what) else realprint("ok   " .. what) end end

SlashCmdList.HOLYMATH("show")
SlashCmdList.HOLYMATH("check")
SlashCmdList.HOLYMATH("dump")
expect(type(HolyMathDB.dump) == "table" and #HolyMathDB.dump.spells > 0, "/hm dump saved spells")
expect(HolyMathDB.dump.model and HolyMathDB.dump.model.ehps and HolyMathDB.dump.model.ehps > 0, "/hm dump has a model result")

-- item tooltip: better cowl over equipped cowl
GameTooltip.lines = {}; GameTooltip.fakeLink = "|Hitem:1002:0:|h"
postCalls[0](GameTooltip)
realprint("item tooltip ->", GameTooltip.lines[1])
expect(GameTooltip.lines[1] and GameTooltip.lines[1]:find("%+%d"), "upgrade shows a positive number")

GameTooltip.lines = {}; GameTooltip.fpLink = nil; GameTooltip.fakeLink = "|Hitem:1001:0:|h"
postCalls[0](GameTooltip)
realprint("item tooltip ->", GameTooltip.lines[1])
expect(GameTooltip.lines[1] and GameTooltip.lines[1]:find("equipped"), "equipped item says equipped")

GameTooltip.lines = {}; GameTooltip.fpLink = nil; GameTooltip.fakeLink = "|Hitem:1003:0:|h"
postCalls[0](GameTooltip)
realprint("item tooltip ->", table.concat(GameTooltip.lines, " / "))

-- spell tooltips: Holy Math adds nothing to them (no hook of any kind)
expect(postCalls[1] == nil, "no spell tooltip hook registered")

-- Item text -> stats, on the real text of 18 items from the 20 Nov dump, plus
-- the robe from the 20 Nov screenshot. Expected values read off the item text.
do
  local EXPECT = {
    ["Bad Mojo Mask"] = { int = 21 },                      -- shadow-only damage: not healing
    ["Triune Amulet"] = { spirit = 7, healing = 8 },
    ["Death Speaker Mantle"] = { int = 11, healing = 6 },
    ["Neophyte's Shirt"] = {},
    ["Civinad Robes"] = { spirit = 12, healing = 26 },     -- "healing done by up to 26 and damage ..." (was missed)
    ["Makeshift Belt"] = { int = 12, spirit = 10, healing = 6 },
    ["Marshdweller's Pants"] = { int = 8, spirit = 10, healing = 11 },
    ["Library Walkers"] = { int = 9, healing = 13 },       -- (was missed)
    ["Spidertank Oilrag"] = { mp5 = 3, healing = 9 },
    ["Jumanza Grips"] = { int = 7, healing = 18, mp5 = 4 }, -- (was missed)
    ["Bloodmaster's Ring"] = { int = 6, healing = 9 },
    ["Snake Hoop"] = { int = 5, healing = 6 },
    ["Roogug's Severed Head"] = { spirit = 6, hasUse = true },
    ["Carrot on a Stick"] = {},
    ["Chainlink Towel"] = { int = 3, spirit = 10 },
    ["Farraki Kris"] = { healing = 54, hasUse = true },
    ["Omega Orb"] = { mp5 = 3, healing = 9 },
    ["Dudd's Second-Favorite Wand"] = { int = 5, mp5 = 1 },
  }
  local items = dofile("tests/fixture_items.lua")
  items[#items + 1] = { name = "Beastbond Robe", lines = { "Soulbound", "Chest", "78 Armor", "+16 Intellect", "+16 Spirit",
    "Equip: Your spells pierce 5 Magical Resistance.", "Durability 80 / 80", "Requires Level 50" } }
  EXPECT["Beastbond Robe"] = { int = 16, spirit = 16 }
  for _, it in ipairs(items) do
    local got, want = ns.Game.StatsFromLines(it.lines), EXPECT[it.name]
    local same = want ~= nil
    for _, k in ipairs({ "int", "spirit", "healing", "mp5", "crit", "haste", "hasUse" }) do
      if want and got[k] ~= want[k] then same = false end
    end
    expect(same, "item text: " .. it.name)
  end
end

-- The game's own item stats (20 Nov dump) agree with our text reading on all 18 items
do
  local text = dofile("tests/fixture_items.lua")
  local game = dofile("tests/fixture_items_game.lua")
  local same = 0
  for _, it in ipairs(text) do
    local a = ns.Game.StatsFromLines(it.lines)
    local b = ns.Game.StatsFromGame(game[it.name]) or {}
    local ok = true
    for key in pairs(ns.Game.FROM_GAME) do if (a[key] or 0) ~= (b[key] or 0) then ok = false; realprint("    differs: " .. it.name .. " " .. key) end end
    if ok then same = same + 1 end
  end
  expect(same == #text and #text == 18, "game item stats == text reading on all 18 dumped items")

  -- the game's table wins: an item whose wording we don't recognise still counts
  ITEMS["|Hitem:5001:0:|h"] = { loc = "INVTYPE_WAIST", lines = { "Odd Sash", "Equip: Mends allies for up to 30 more." } }
  C_Item.GetItemStats = function(link)
    if link:find("item:5001") then return { ITEM_MOD_SPELL_HEALING_DONE_SHORT = 30, ITEM_MOD_INTELLECT_SHORT = 5 } end
  end
  ns.Game.ClearItemCache()
  local st = ns.Game.ItemStats("|Hitem:5001:0:|h")
  expect(st.healing == 30 and st.int == 5 and st.source == "game", "unrecognised wording: healing taken from the game's stat table")
  expect((ns.counts.itemStatMismatch or 0) >= 1, "text/game disagreement counted for /hm dump")
  C_Item.GetItemStats = nil
  ns.Game.ClearItemCache()
end

-- the screenshot's comparison: Beastbond Robe (+16 int, +16 spirit) replacing
-- Civinad Robes (+12 spirit, +26 healing) must be a LOSS for a healer
do
  ITEMS["|Hitem:3001:0:|h"] = { loc = "INVTYPE_CHEST", lines = { "Civinad Robes", "+7 Stamina", "+12 Spirit",
    "Equip: Increases healing done by up to 26 and damage done by up to 9 for all magical spells and effects." } }
  ITEMS["|Hitem:3002:0:|h"] = { loc = "INVTYPE_CHEST", lines = { "Beastbond Robe", "+16 Intellect", "+16 Spirit" } }
  local realInv = GetInventoryItemLink
  GetInventoryItemLink = function(u, slot) if slot == 5 then return "|Hitem:3001:0:|h" end return realInv(u, slot) end
  ns.ClearVerdicts()
  GameTooltip.lines = {}; GameTooltip.fpLink = nil; GameTooltip.fakeLink = "|Hitem:3002:0:|h"
  postCalls[0](GameTooltip)
  realprint("robe swap ->", GameTooltip.lines[1])
  expect(GameTooltip.lines[1] and GameTooltip.lines[1]:find("%-%d"), "Beastbond over Civinad Robes shows a loss")
  GetInventoryItemLink = realInv
  ns.ClearVerdicts()
end

-- /hm check reports the tooltip comparison
printed = {}
SlashCmdList.HOLYMATH("check")
local chk = table.concat(printed, "\n")
expect(chk:find("2 of %d+ ranks match the model"), "/hm check: Renew r9 and GH r4 tooltips match the model")
expect(chk:find("Greater Heal 1 costs 380 in game %(game data 370%)"), "/hm check: a client cost within 3% of the data is used")

-- action bars: no lines added to a spell's tooltip
GameTooltip.lines = {}
GameTooltip:SetAction(1)
expect(#GameTooltip.lines == 0, "action-bar spell tooltips are left alone")

-- settings change recalculates
SlashCmdList.HOLYMATH("set fight 180")
expect(HolyMathDB.PRIEST.settings.fightLength == 180, "/hm set fight 180 (saved per class)")

-- an off-hand while a staff is equipped: no verdict (it would be compared to an empty slot)
ITEMS["|Hitem:2001:0:|h"] = { loc = "INVTYPE_2HWEAPON", lines = { "Staff", "+30 Intellect" } }
ITEMS["|Hitem:2002:0:|h"] = { loc = "INVTYPE_HOLDABLE", lines = { "Orb", "+10 Intellect" } }
local realInv = GetInventoryItemLink
GetInventoryItemLink = function(u, slot) if slot == 16 then return "|Hitem:2001:0:|h" end return realInv(u, slot) end
ns.ClearVerdicts()
GameTooltip.lines = {}; GameTooltip.fpLink = nil; GameTooltip.fakeLink = "|Hitem:2002:0:|h"
postCalls[0](GameTooltip)
expect(#GameTooltip.lines == 0, "off-hand next to an equipped staff: no verdict")
GetInventoryItemLink = realInv

-- a spellbook API that throws: /hm dump still saves the other sections
local realSB = C_SpellBook.GetNumSpellBookSkillLines
C_SpellBook.GetNumSpellBookSkillLines = function() error("boom") end
SlashCmdList.HOLYMATH("dump")
expect(HolyMathDB.dump.api and HolyMathDB.dump.items, "dump keeps other sections when one API throws")
C_SpellBook.GetNumSpellBookSkillLines = realSB

-- healing power unreadable: no numbers anywhere, and /hm says why
local realHeal = GetSpellBonusHealing
GetSpellBonusHealing = nil
printed = {}
SlashCmdList.HOLYMATH("show")
local said = table.concat(printed, "\n")
expect(said:find("Could not read:.-GetSpellBonusHealing"), "/hm names the failed read")
expect(not said:find("Model:"), "/hm shows no model numbers when healing power is missing")
ns.ClearVerdicts()
GameTooltip.lines = {}; GameTooltip.fpLink = nil; GameTooltip.fakeLink = "|Hitem:1002:0:|h"
postCalls[0](GameTooltip)
expect(#GameTooltip.lines == 0, "no item verdict when healing power is missing")
GetSpellBonusHealing = realHeal
expect(ns.counts.itemHook, "item hook counter recorded")

-- Items a priest can't use say so instead of giving a number ------------------
do
  ns.MarkDirty()      -- the previous test left healing power unreadable; it's back now
  local function item(id, def) ITEMS["|Hitem:" .. id .. ":0:|h"] = def; return "|Hitem:" .. id .. ":0:|h" end
  local cases = {
    { item(4001, { loc = "INVTYPE_HAND", class = 4, sub = 4, subType = "Plate", lines = { "Heartflame Gauntlets",
        "Binds when picked up", "Hands", "410 Armor", "+14 Intellect",
        "Equip: Improves your chance to get a critical strike by 1.0%.",
        "Equip: Increases damage done by Holy spells and effects by up to 18.", "Requires Level 58" } }),
      "can't wear Plate", "plate gloves (the screenshot's Heartflame Gauntlets)" },
    { item(4002, { loc = "INVTYPE_CHEST", class = 4, sub = 2, subType = "Leather", lines = { "Tunic", "+10 Intellect" } }),
      "can't wear Leather", "leather chest" },
    { item(4003, { loc = "INVTYPE_WEAPON", class = 2, sub = 7, subType = "One-Handed Swords", lines = { "Sword", "+10 Intellect" } }),
      "can't use One%-Handed Swords", "one-handed sword" },
    { item(4004, { loc = "INVTYPE_SHIELD", class = 4, sub = 6, subType = "Shields", lines = { "Shield", "+10 Intellect" } }),
      "can't use shields", "shield" },
    { item(4005, { loc = "INVTYPE_HEAD", class = 4, sub = 1, lines = { "Mage Hood", "+20 Intellect", "Classes: Mage" } }),
      "for Mage only", "cloth locked to mages" },
  }
  for _, c in ipairs(cases) do
    GameTooltip.lines = {}; GameTooltip.fpLink = nil; GameTooltip.fakeLink = c[1]
    postCalls[0](GameTooltip)
    local line = GameTooltip.lines[1] or ""
    expect(line:find(c[2]) and not line:find("HPS"), "can't equip: " .. c[3])
  end
  -- usable: a dagger, a priest-locked cloth item, an off-hand
  for _, u in ipairs({
      { item(4006, { loc = "INVTYPE_WEAPON", class = 2, sub = 15, subType = "Daggers", lines = { "Dagger", "+10 Intellect" } }), "dagger" },
      { item(4007, { loc = "INVTYPE_HEAD", class = 4, sub = 1, lines = { "Priest Hood", "+20 Intellect", "Classes: Priest" } }), "cloth locked to priests" },
      { item(4008, { loc = "INVTYPE_HOLDABLE", class = 4, sub = 0, lines = { "Orb", "+10 Intellect" } }), "held in off-hand" } }) do
    ns.ClearVerdicts()
    GameTooltip.lines = {}; GameTooltip.fpLink = nil; GameTooltip.fakeLink = u[1]
    postCalls[0](GameTooltip)
    expect((GameTooltip.lines[1] or ""):find("HPS"), "usable, gets a number: " .. u[2])
  end
end

-- The options window, with Blizzard's templates ------------------------------
do
  local O = ns.Options
  SlashCmdList.HOLYMATH("")
  expect(O.frame and O.frame:IsShown(), "/hm opens the options window")
  expect(O.frame.title == "Holy Math", "window uses Blizzard's portrait frame with a title")
  expect(O.controls.fight and O.controls.fight.Init, "fight length uses Blizzard's options slider")
  local before = O.hps.text
  expect(before and before:find("^%d+ HPS$"), "result: big HPS headline")
  expect((O.hpsNote.text or ""):find("after overheal") and (O.hpsNote.text or ""):find("%d+ before"), "result: before-overheal note")
  local names, values = {}, {}
  for i, c in ipairs(O.weightCells) do
    names[i] = (c.name.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    values[i] = tonumber(((c.value.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
  end
  local sorted = true
  for i = 2, #values do if not values[i] or not values[i - 1] or values[i] > values[i - 1] then sorted = false end end
  expect(#names == 6 and sorted, "stat values: a table of 6, best first")
  realprint("    result: " .. tostring(before) .. "  " .. (O.hpsNote.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  local row = {}
  for i = 1, 6 do row[#row + 1] = names[i] .. " " .. tostring(values[i]) end
  realprint("    values: " .. table.concat(row, "  |  "))
  O.controls.fight.onChange(nil, 240)
  expect(HolyMathDB.PRIEST.settings.fightLength == 240, "slider sets the fight length")
  expect(O.hps.text ~= before, "result updates after a change")
  O.controls.ohRENEW.onChange(nil, 0.4)
  expect(HolyMathDB.PRIEST.settings.overheal.RENEW == 0.4, "overheal slider sets Renew overheal")
  O.controls.pots:SetChecked(false); O.controls.pots.scripts.OnClick(O.controls.pots)
  expect(HolyMathDB.PRIEST.settings.majorManaPotions == false, "Blizzard checkbox turns mana potions off")
  -- playstyle: [<] name HPS [>], plain buttons (no Blizzard menu)
  local start = HolyMathDB.PRIEST.rotation
  O.controls["rot>"].scripts.OnClick(O.controls["rot>"])
  expect(HolyMathDB.PRIEST.rotation ~= start, "playstyle arrows change the playstyle")
  expect((O.controls.rot.text or ""):find("%d+ HPS"), "playstyle shows its HPS")
  realprint("    playstyle: " .. (O.controls.rot.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  O.controls["rot<"].scripts.OnClick(O.controls["rot<"])
  expect(HolyMathDB.PRIEST.rotation == start, "and back")
  local seen, k0 = {}, HolyMathDB.PRIEST.rotation
  repeat
    seen[HolyMathDB.PRIEST.rotation] = true
    O.controls["rot>"].scripts.OnClick(O.controls["rot>"])
  until HolyMathDB.PRIEST.rotation == k0
  local count = 0 for _ in pairs(seen) do count = count + 1 end
  expect(count == 5 and not seen.rhTank and not seen.renewDown, "arrows cycle the 5 playstyles you can use")
  expect(O.status.text and O.status.text:find("Matches the game"), "status line: model matches the game's tooltips")
  expect(not O.controls.Recalculate and not O.controls.Dump and not O.controls.Check, "only one button left (Defaults)")
  GameTooltip.lines = {}
  O.controls.Defaults.scripts.OnEnter(O.controls.Defaults)
  expect(GameTooltip.lines[1] == "Defaults" and (GameTooltip.lines[2] or ""):find("starting value"), "hovering Defaults explains it")
  O.controls.pots.scripts.OnEnter(O.controls.pots)
  expect((GameTooltip.lines[2] or ""):find("Major Mana Potion"), "hovering a setting explains it")
  O.controls.Defaults.scripts.OnClick(O.controls.Defaults)
  local s = HolyMathDB.PRIEST.settings
  expect(s.fightLength == 120 and s.overheal.RENEW == 0.25 and s.majorManaPotions and HolyMathDB.PRIEST.rotation == "renew",
    "Defaults restores the settings")
  SlashCmdList.HOLYMATH("")
  expect(not O.frame:IsShown(), "/hm again closes it")
end

-- Tabs: Your spells, Tooltips -------------------------------------------------
do
  local O = ns.Options
  local db = ForeverHealerDB and ForeverHealerDB.PRIEST or HolyMathDB.PRIEST
  SlashCmdList.HOLYMATH("")
  expect(O.frame:IsShown() and O.panes.settings:IsShown(), "window opens on the Settings tab")
  local function click(b) b.scripts.OnClick(b) end
  click(O.controls["tab:spells"])
  expect(O.panes.spells:IsShown() and not O.panes.settings:IsShown(), "Your spells tab shows its own page")
  local function plain(t) return ((t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " / ")) end
  local function rowText(row) local t = {} for _, c in ipairs(row.cells) do t[#t + 1] = plain(c.text) end return table.concat(t, " | ") end
  -- Spell overview
  expect(plain(O.spellRows[1].cells[1].text) ~= "" and tonumber(O.spellRows[1].cells[3].text), "overview: spells with heal per cast")
  local ov = {}
  for _, row in ipairs(O.spellRows) do if plain(row.cells[1].text) ~= "" then ov[#ov + 1] = rowText(row) end end
  expect(#ov >= 6, "overview: every known spell listed")
  for _, l in ipairs(ov) do realprint("    spell: " .. l) end
  GameTooltip.lines = {}
  O.spellRows[1].scripts.OnEnter(O.spellRows[1])
  expect((GameTooltip.lines[1] or "") ~= "", "overview: hovering a spell shows its tooltip")
  expect(not O.styleRows, "Your spells: no playstyle comparison, just your spells")
  expect(not (O.castRows or O.notesText or O.controls.useBest), "no 'how to play' instructions left")
  expect(not requestedTemplates.WowStyle1DropdownTemplate, "never touches Blizzard's menu system (dropdown taint)")

  click(O.controls["tab:tooltips"])
  expect(O.panes.tooltips:IsShown(), "Tooltips tab shows its own page")
  expect(not O.controls.tipSpells, "Tooltips tab has no spell options")
  local c
  -- item tooltips: percent, only upgrades, shift
  local function itemTip(link)
    ns.ClearVerdicts()
    GameTooltip.lines = {}; GameTooltip.fpLink = nil; GameTooltip.fakeLink = link
    postCalls[0](GameTooltip)
    return GameTooltip.lines[1] or ""
  end
  local better, worse = "|Hitem:1002:0:|h", "|Hitem:3002:0:|h"
  expect(itemTip(better):find("%%"), "item line shows % by default")
  c = O.controls.tipItemPct; c:SetChecked(false); click(c)
  expect(itemTip(better) ~= "" and not itemTip(better):find("%%"), "item % can be turned off")
  c:SetChecked(true); click(c)
  local realInv = GetInventoryItemLink
  GetInventoryItemLink = function(u, slot) if slot == 5 then return "|Hitem:3001:0:|h" end return realInv(u, slot) end
  expect(itemTip(worse):find("%-%d"), "a worse item shows a loss by default")
  c = O.controls.tipOnlyUp; c:SetChecked(true); click(c)
  expect(itemTip(worse) == "", "only upgrades: the loss is hidden")
  c:SetChecked(false); click(c)
  GetInventoryItemLink = realInv
  c = O.controls.tipShift; c:SetChecked(true); click(c)
  IsShiftKeyDown = function() return false end
  expect(itemTip(better) == "", "Shift option: nothing without Shift")
  IsShiftKeyDown = function() return true end
  expect(itemTip(better) ~= "", "Shift option: shown with Shift")
  c:SetChecked(false); click(c)
  IsShiftKeyDown = nil
  click(O.controls.TooltipDefaults)
  expect(db.tooltips.items and db.tooltips.itemPercent and not db.tooltips.onlyUpgrades, "tooltip Defaults")
  click(O.controls["tab:settings"])
  SlashCmdList.HOLYMATH("")
end

-- The window closes in combat: close button, /hm and Esc
do
  local O = ns.Options
  local realCombat = InCombatLockdown
  InCombatLockdown = function() return true end
  SlashCmdList.HOLYMATH("")
  expect(O.frame:IsShown(), "opens in combat")
  O.frame.CloseButton.scripts.OnClick(O.frame.CloseButton)
  expect(not O.frame:IsShown(), "close button closes it in combat")
  SlashCmdList.HOLYMATH(""); SlashCmdList.HOLYMATH("")
  expect(not O.frame:IsShown(), "/hm closes it in combat")
  local inSpecial = false
  for _, n in ipairs(UISpecialFrames) do if n == "HolyMathOptions" then inSpecial = true end end
  expect(inSpecial, "Esc closes it (listed in UISpecialFrames)")
  printed = {}
  SlashCmdList.HOLYMATH("dump")
  expect(table.concat(printed, " "):find("you're in combat"), "/hm dump warns when in combat")
  expect(HolyMathDB.dump.inCombat == true, "dump records that it was taken in combat")
  InCombatLockdown = realCombat
end

-- The options window on a client WITHOUT those templates: plain fallbacks
do
  for _, t in ipairs({ "PortraitFrameTemplate", "MinimalSliderWithSteppersTemplate", "UICheckButtonTemplate",
                       "WowStyle1DropdownTemplate", "UIPanelButtonTemplate", "UIPanelCloseButton" }) do missingTemplates[t] = true end
  local ns3 = {}
  for _, f in ipairs({ "Models/PriestData.lua", "Models/Priest.lua", "Game.lua", "Tooltips.lua", "Core.lua", "Options.lua" }) do
    assert(loadfile(f))("HolyMath", ns3)
  end
  local core3 = frames[#frames]
  core3.scripts.OnEvent(core3, "PLAYER_LOGIN")
  local O = ns3.Options
  SlashCmdList.HOLYMATH("")
  expect(O.frame and O.frame:IsShown(), "fallback window opens")
  O.controls["fight+"].scripts.OnClick(O.controls["fight+"])
  expect(HolyMathDB.PRIEST.settings.fightLength == 150, "fallback + button raises the fight length")
  O.controls["rot>"].scripts.OnClick(O.controls["rot>"])
  expect(HolyMathDB.PRIEST.rotation ~= "renew", "fallback arrows change the healing plan")
  O.controls.pots.scripts.OnClick(O.controls.pots)
  expect(HolyMathDB.PRIEST.settings.majorManaPotions == false, "fallback toggle turns mana potions off")
  expect(O.hps.text and O.hps.text:find("HPS"), "fallback window shows the result")
  O.controls.Defaults.scripts.OnClick(O.controls.Defaults)
  missingTemplates = {}
end

-- default fight length 120 s; a saved 300 s (the old default) moves to 120 once
do
  local function login(db)
    HolyMathDB = { PRIEST = db }
    local ns4 = {}
    for _, f in ipairs({ "Models/PriestData.lua", "Models/Priest.lua", "Game.lua", "Tooltips.lua", "Core.lua", "Options.lua" }) do
      assert(loadfile(f))("HolyMath", ns4)
    end
    local core4 = frames[#frames]
    core4.scripts.OnEvent(core4, "PLAYER_LOGIN")
    return HolyMathDB.PRIEST
  end
  local saved = HolyMathDB
  expect(login(nil).settings.fightLength == 120, "new setup: 120 s fight")
  expect(login({ settings = { fightLength = 300 } }).settings.fightLength == 120, "saved 300 s (old default) becomes 120 s")
  local again = login({ settings = { fightLength = 300 }, fight120 = true })
  expect(again.settings.fightLength == 300, "after that, a chosen 300 s is kept")
  expect(login({ settings = { fightLength = 180 } }).settings.fightLength == 180, "other saved lengths are kept")
  HolyMathDB = saved
end

-- a class with no model yet (warrior): loads without errors and stays quiet
do
  UnitClass = function() return "Warrior", "WARRIOR" end
  local ns2 = {}
  for _, f in ipairs({ "Models/PriestData.lua", "Models/Priest.lua", "Game.lua", "Tooltips.lua", "Core.lua", "Options.lua" }) do assert(loadfile(f))("HolyMath", ns2) end
  local core2 = frames[#frames]
  core2.scripts.OnEvent(core2, "PLAYER_LOGIN")
  expect(not ns2.enabled, "warrior: addon stays off")
  printed = {}
  SlashCmdList.HOLYMATH("")
  expect(table.concat(printed, " "):find("made for priests"), "warrior: /hm says it is made for priests")
end

realprint(fails == 0 and "\nsmoke test passed" or ("\n" .. fails .. " smoke failures"))
os.exit(fails == 0 and 0 or 1)
