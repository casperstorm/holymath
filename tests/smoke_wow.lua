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
  for _, m in ipairs({ "SetPoint", "ClearAllPoints", "SetWidth", "SetHeight", "SetJustifyH", "SetJustifyV", "SetFontObject" }) do fs[m] = noop end
  function fs:Show() self.shown = true end
  function fs:Hide() self.shown = false end
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
  function f:UnregisterEvent(e) self.events[e] = nil end
  function f:IsMouseOver() return self.mouseOver == true end
  function f:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
  local function sized(self, w) self.width = w end
  for _, m in ipairs({ "SetSize", "SetWidth", "SetHeight", "SetPoint", "ClearAllPoints", "SetFrameStrata", "SetMovable",
      "EnableMouse", "RegisterForDrag", "SetClampedToScreen", "SetToplevel", "StartMoving", "StopMovingOrSizing",
      "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "Raise", "SetAllPoints", "SetID" }) do f[m] = noop end
  f.SetWidth = sized
  function f:SetSize(w) self.width = w end
  function f:CreateTexture()
    local t = { shown = true }
    for _, m in ipairs({ "SetColorTexture", "SetTexture", "SetVertexColor", "SetPoint", "SetAllPoints", "SetSize",
                         "SetWidth", "SetHeight", "ClearAllPoints", "SetBlendMode", "SetTexCoord", "SetAlpha" }) do t[m] = noop end
    function t:SetTexture(x) self.texture = x end
    function t:SetSize(w) self.width = w end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    return t
  end
  frames[#frames + 1] = f
  if name then _G[name] = f end
  return f
end
-- Blizzard templates the options window uses, faked just enough to drive them.
local missingTemplates = {}      -- names listed here "don't exist" in this fake client
local TEMPLATES = {
  UIPanelButtonTemplate = function(f) function f:SetText(t) self.text = t end; function f:GetText() return self.text end end,
  InputBoxTemplate = function(f)
    function f:SetText(t) self.text = t end
    function f:GetText() return self.text end
    function f:SetFocus() self.focus = true end
    function f:HasFocus() return self.focus == true end
    function f:ClearFocus()
      local had = self.focus; self.focus = false
      if had and self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
    end
    for _, m in ipairs({ "HighlightText", "SetAutoFocus", "SetMaxLetters", "SetJustifyH", "SetFontObject" }) do f[m] = noop end
  end,
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
    function f:SetEnabled(v) self.enabled = v and true or false end
    function f:GetChecked() return self.checked end
  end,
  MinimalSliderWithSteppersTemplate = function(f)
    f.Slider = { SetObeyStepOnDrag = noop }
    function f:Init(v, lo, hi, steps, formatters) self.value, self.lo, self.hi, self.fmt = v, lo, hi, formatters end
    function f:RegisterCallback(_, fn) self.onChange = fn end
    function f:SetValue(v) self.value = v; if self.onChange then self.onChange(nil, v) end end
  end,
  -- like the game's: the menu is built (radios asked if they're selected, the closed
  -- field's text worked out) as soon as it is set up, and on GenerateMenu
  WowStyle1DropdownTemplate = function(f)
    function f:GenerateMenu()
      if not self.gen then return end
      local root = {}
      local function item() return { SetTooltip = noop, SetEnabled = noop } end
      function root:CreateRadio(text, isSel, setSel, data) isSel(data); return item() end
      function root:CreateButton() return item() end
      root.CreateTitle, root.CreateDivider = noop, noop
      self.gen(self, root)
      if self.translate then self.closedText = self.translate({}) end
    end
    function f:SetupMenu(gen) self.gen = gen; self:GenerateMenu() end
    function f:SetSelectionTranslator(fn) self.translate = fn end
    f.SetDefaultText = noop
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
GameFontDisableSmall = {}
UISpecialFrames = {}
PlaySound = noop
GameTooltip = newFrame(); GameTooltip.ProcessInfo = function() end
function GameTooltip:SetText(t) self.lines = { t } end
GameTooltip.SetAction = function() end
function GameTooltip:SetHyperlink(link) self.lines = { link } end
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
  GetSpellPowerCost = function(id) if id == 201 then return { { cost = 320 } } end return {} end, -- data: 370, 315 with Improved Healing
  -- cast times as the game gives them: haste and Divine Fury 5/5 (Greater Heal 3 - 0.5 s) in them; instants 0
  GetSpellInfo = function(id) return { castTime = ({ 0, 2500, 1500, 1500, 3000, 0, 0, 0 })[math.floor(id / 100)] } end,
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
-- the Gear tab: icons, what you have, your side
ownedItems = {}
GetItemIcon = function(id) return "icon:" .. id end
GetItemCount = function(id) return ownedItems[id] and 1 or 0 end
GetInventoryItemID = function() return nil end
UnitFactionGroup = function() return "Horde" end
Minimap = newFrame("Minimap")
function Minimap:GetWidth() return 140 end
function Minimap:GetCenter() return 1000, 600 end
TooltipUtil = { GetDisplayedItem = function(tt) return "x", tt.fakeLink end }
SlashCmdList = {}

-- load the addon -------------------------------------------------------------
local ns = {}
for _, f in ipairs({ "Models/PriestData.lua", "Models/GearData.lua", "Models/Priest.lua", "Models/GearSolve.lua", "Models/PriestMath.lua", "Game.lua", "Tooltips.lua", "Core.lua", "Options.lua", "Playstyles.lua", "Gear.lua", "Minimap.lua" }) do
  assert(loadfile(f))("HolyMath", ns)
end
local core = frames[#frames]                      -- Core's event frame
core.scripts.OnEvent(core, "PLAYER_LOGIN")
assert(ns.enabled, "should enable on a priest")

local fails = 0
local function expect(cond, what) if not cond then fails = fails + 1; realprint("FAIL " .. what) else realprint("ok   " .. what) end end

expect(ns.warmed, "your stats are read once after login, out of combat")

SlashCmdList.HOLYMATH("show")
SlashCmdList.HOLYMATH("check")
-- /hm minimap hides and shows the minimap button (and says so)
do
  local b = ns.Minimap.button
  printed = {}
  SlashCmdList.HOLYMATH("minimap")
  local hid = b and not b.shown and HolyMathDB.minimap.hide == true and table.concat(printed, " "):find("hidden")
  SlashCmdList.HOLYMATH("minimap")
  expect(hid and b.shown and not HolyMathDB.minimap.hide, "/hm minimap hides the minimap button, and again shows it")
end
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

-- spell tooltips: per mana and per second of that rank, and your most efficient rank
expect(postCalls[1] ~= nil, "spell tooltip hook registered")
do
  local function spellTip(id)
    GameTooltip.lines = {}; GameTooltip.hmSpell = nil
    postCalls[1](GameTooltip, { id = id })
    return GameTooltip.lines
  end
  local S = ns.State()
  local ranks = ns.model.SpellRanks("RENEW", S.st, S.t, S.input.settings)
  local best
  for _, rk in ipairs(ranks) do if rk.best then best = rk end end
  local top = spellTip(109)
  realprint("spell tooltip (Renew 9) ->", table.concat(top, " / "))
  expect(top[1] and top[1]:find("Holy Math") and top[1]:find("healing per mana") and top[1]:find("per second"),
    "a known healing rank gets a Holy Math line")
  local r9
  for _, rk in ipairs(ranks) do if rk.rank == 9 then r9 = rk end end
  expect(top[1]:find(string.format("%.2f", r9.hpm), 1, true), "... with the rank's per mana from Your spells")
  if best.rank == 9 then
    expect(top[2] and top[2]:find("Your most efficient rank"), "... the top rank is the most efficient")
  else
    expect(top[2] and top[2]:find("Most efficient: Rank " .. best.rank, 1, true), "... and names the most efficient rank (" .. best.rank .. ")")
    local b = spellTip(100 + best.rank)
    expect(b[2] and b[2]:find("Your most efficient rank"), "the most efficient rank says so on its own tooltip")
  end
  expect(#spellTip(999) == 0, "a spell that isn't a known healing rank: no line")
  spellTip(109); postCalls[1](GameTooltip, { id = 109 })
  expect(#GameTooltip.lines == 2, "the line is added once per tooltip")
  -- a hidden ("secret") spell ID in combat: comparing it errors in the real client
  local secret = setmetatable({}, { __eq = function() error("compared a secret") end })
  local realSecret = issecretvalue
  issecretvalue = function(v) return v == nil and false or rawequal(v, secret) end
  local okSecret = pcall(spellTip, secret)
  expect(okSecret and #GameTooltip.lines == 0, "a secret spell ID: no line and no error")
  issecretvalue = realSecret
  HolyMathDB.PRIEST.tooltips.spells = false
  expect(#spellTip(109) == 0, "spell tooltips off: no line")
  HolyMathDB.PRIEST.tooltips.spells = true
end

-- inside an instance: tooltips aren't read for heals (the ones from outside are kept)
do
  local realDesc, realInside = C_Spell.GetSpellDescription, IsInInstance
  ns.clientSeen = nil; ns.MarkDirty()
  local S = ns.State()
  local function gh4(state) for _, r in ipairs(state.info.client) do if r.key == "GH" and r.rank == 4 then return r end end end
  local outside = gh4(S)
  expect(outside.baseFrom == "client" and not S.info.inInstance, "outside: Greater Heal 4 read from its tooltip")
  IsInInstance = function() return true, "party" end
  C_Spell.GetSpellDescription = function(id)       -- a dungeon tooltip showing far more
    if id == 204 then return "A slow casting spell that heals a single target for 3,960 to 4,314." end
    return realDesc(id)
  end
  ns.MarkDirty(); S = ns.State()
  local inside = gh4(S)
  expect(S.info.inInstance and inside.client == nil and inside.baseFrom == "earlier" and inside.base == outside.base,
    "inside an instance: the heal read outside is kept")
  printed = {}
  SlashCmdList.HOLYMATH("check")
  local out = table.concat(printed, "\n")
  expect(out:find("in an instance") and out:find("kept from outside the instance"), "/hm check says why")
  SlashCmdList.HOLYMATH("dump")
  expect(HolyMathDB.dump.inInstance == true and HolyMathDB.dump.instanceType == "party", "/hm dump records the instance")
  IsInInstance = realInside; C_Spell.GetSpellDescription = realDesc
  ns.MarkDirty(); S = ns.State()
  expect(not S.info.inInstance and gh4(S).baseFrom == "client", "back outside: read again")
  SlashCmdList.HOLYMATH("dump")
  expect(HolyMathDB.dump.inInstance == false, "/hm dump outside says so")
end

-- tooltip text not loaded yet: ask the game for it once, and look again when it says it's there
do
  local asked = {}
  C_Spell.RequestLoadSpellData = function(id) asked[#asked + 1] = id end
  ns.requestedText = nil; ns.MarkDirty(); ns.State()
  expect(ns.textPending and #asked > 0, "missing tooltip text is asked for (" .. #asked .. " spells)")
  local n = #asked
  ns.MarkDirty(); ns.State()
  expect(#asked == n, "... once per spell per session")
  expect(core.events.SPELL_TEXT_UPDATE and core.events.SPELL_DATA_LOAD_RESULT and core.events.PLAYER_ENTERING_WORLD,
    "listens for spell text and for entering or leaving an instance")
  ns.State()
  core.scripts.OnEvent(core, "SPELL_DATA_LOAD_RESULT", 105, true)
  local S0 = ns.State()
  core.scripts.OnEvent(core, "SPELL_TEXT_UPDATE", 105)
  expect(ns.State() ~= S0, "spell text arriving makes it look again")
  ns.textPending = false
  local S1 = ns.State()
  core.scripts.OnEvent(core, "SPELL_TEXT_UPDATE", 105)
  expect(ns.State() == S1, "... but not when nothing was missing")
  C_Spell.RequestLoadSpellData = nil
end

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
expect(chk:find("ranks known, read from the game"), "/hm check: says the spells' numbers come from the game")
expect(not chk:find("Renew 9:") and not chk:find("Greater Heal 4:"), "/hm check: Renew r9 and GH r4 agree with the game data, so aren't listed")
expect(chk:find("Greater Heal 1: costs 320 %(game data with your talents 315%), from the game"), "/hm check: the game's cost is used (talents taken out)")

-- action bars: no hook of their own (the spell line comes through the tooltip
-- pipeline's Spell post-call, which action-bar spell tooltips go through too)
GameTooltip.lines = {}
GameTooltip:SetAction(1)
expect(#GameTooltip.lines == 0, "no separate action-bar hook")

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
-- the same in combat (the game won't give stats out then): it says so, not "could not read"
local realCombat = InCombatLockdown
InCombatLockdown = function() return true end
printed = {}
SlashCmdList.HOLYMATH("show")
said = table.concat(printed, "\n")
expect(said:find("can't be read in combat") and not said:find("Could not read"), "/hm in combat: stats can't be read until the fight ends")
InCombatLockdown = realCombat
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
  -- two groups: per point (mp5, intellect, spirit) and per 1% (crit, haste), each best first
  local groups, sorted = { {}, {} }, true
  for i, c in ipairs(O.weightCells) do
    if names[i] ~= "" then table.insert(groups[c.group], { names[i], values[i] }) end
  end
  for _, g in ipairs(groups) do
    for i = 2, #g do if not g[i][2] or not g[i - 1][2] or g[i][2] > g[i - 1][2] then sorted = false end end
  end
  local function has(g, n) for _, e in ipairs(groups[g]) do if e[1] == n then return true end end end
  expect(#groups[1] == 3 and has(1, "Intellect") and has(1, "MP5") and has(1, "Spirit"), "stat values: per point: intellect, MP5, spirit")
  expect(#groups[2] == 2 and has(2, "Crit") and has(2, "Haste"), "stat values: per 1%: crit and haste")
  expect(sorted, "stat values: each group best first")
  expect(not table.concat(names, " "):find("Healing power"), "healing power is the unit (in the heading), not a row")
  expect(((O.result.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) == "Worth in healing power", "stat values: heading names the unit")
  realprint("    result: " .. tostring(before) .. "  " .. (O.hpsNote.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  local row = {}
  for i = 1, #names do if names[i] ~= "" then row[#row + 1] = names[i] .. " " .. tostring(values[i]) end end
  realprint("    values: " .. table.concat(row, "  |  "))
  O.controls.fight.onChange(nil, 240)
  expect(HolyMathDB.PRIEST.settings.fightLength == 240, "slider sets the fight length")
  expect(O.hps.text ~= before, "result updates after a change")
  expect(not O.controls.ohRENEW, "no overheal sliders on the Settings tab (they are on the Math tab)")
  O.controls.insp:SetChecked(false); O.controls.insp.scripts.OnClick(O.controls.insp)
  expect(HolyMathDB.PRIEST.settings.includeInspiration == false, "Blizzard checkbox turns Inspiration off")
  -- playstyle: the game's dropdown (WowStyle1), one radio per playstyle, no HPS
  local dd = O.controls.rot
  expect(requestedTemplates.WowStyle1DropdownTemplate and type(dd.gen) == "function", "playstyle uses the game's dropdown")
  local radios = {}
  local root = { CreateRadio = function(_, text, isSel, setSel, data)
    local r = { text = text, isSel = isSel, setSel = setSel, data = data }
    function r:SetTooltip(fn) self.tip = fn end
    radios[#radios + 1] = r
    return r
  end }
  dd.gen(dd, root)
  local names = {}
  for _, r in ipairs(radios) do names[#names + 1] = r.text end
  for _, n in ipairs(names) do realprint("    option: " .. n) end
  expect(#radios == 5, "menu: the 5 playstyles you can use")
  local withHPS = 0
  for _, n in ipairs(names) do if n:find("%d+ HPS") then withHPS = withHPS + 1 end end
  expect(withHPS == #names, "menu: each playstyle with what it heals per second for you")
  expect(not table.concat(names, " "):find("Renewed Hope") and not table.concat(names, " "):find("downranked"), "menu: no hidden playstyles")
  local selected = {}
  for _, r in ipairs(radios) do if r.isSel(r.data) then selected[#selected + 1] = r.data end end
  expect(#selected == 1 and selected[1] == "renew", "menu: the current playstyle is the selected radio")
  local fake = { lines = {} }
  function fake:SetText(t) self.lines = { t } end
  function fake:AddLine(t) self.lines[#self.lines + 1] = t end
  radios[1].tip(fake)
  expect(#fake.lines == 2, "menu: each playstyle explains itself on hover")
  for _, r in ipairs(radios) do if r.data == "flashFill" then r.setSel(r.data) end end
  expect(HolyMathDB.PRIEST.rotation == "flashFill", "menu: picking a playstyle sets it")
  HolyMathDB.PRIEST.rotation = "renew"; O.Changed(true)
  expect(O.status == nil and O.statusHit == nil, "no warning line in the window: spell numbers are taken from the game")
  -- a patch: Greater Heal 4 heals 20% more in game (a new session); taken by itself
  local realDesc = C_Spell.GetSpellDescription
  C_Spell.GetSpellDescription = function(id)
    if id == 204 then return "A slow casting spell that heals a single target for 3,168 to 3,452." end
    return realDesc(id)
  end
  ns.clientSeen = nil
  O.Changed(true)
  local S = ns.State()
  local gh4
  for _, r in ipairs(S.info.client) do if r.key == "GH" and r.rank == 4 then gh4 = r end end
  expect(gh4 and gh4.baseFrom == "client" and math.abs(gh4.after - 3310) <= 1, "patch: Greater Heal 4 +20% in game is used, no warning")
  -- later in the same session the same jump back is a buff ending... the session's reading stays
  C_Spell.GetSpellDescription = realDesc
  O.Changed(true)
  S = ns.State()
  for _, r in ipairs(S.info.client) do if r.key == "GH" and r.rank == 4 then gh4 = r end end
  expect(gh4.baseFrom == "earlier", "session: a jump later in the session keeps the first reading")
  ns.clientSeen = nil
  O.Changed(true)
  expect(not O.controls.Recalculate and not O.controls.Dump and not O.controls.Check, "only one button left (Defaults)")
  GameTooltip.lines = {}
  O.controls.Defaults.scripts.OnEnter(O.controls.Defaults)
  expect(GameTooltip.lines[1] == "Defaults" and (GameTooltip.lines[2] or ""):find("starting value"), "hovering Defaults explains it")
  O.controls.insp.scripts.OnEnter(O.controls.insp)
  expect((GameTooltip.lines[2] or ""):find("armor"), "hovering a setting explains it")
  O.controls.Defaults.scripts.OnClick(O.controls.Defaults)
  local s = HolyMathDB.PRIEST.settings
  expect(s.fightLength == 120 and s.overheal.RENEW == 0.25 and #s.potions == 1 and s.potions[1].key == "majorMana"
    and s.potions[1].n == ns.model.POTION_ALL and HolyMathDB.PRIEST.rotation == "renew",
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
  expect(not O.controls["tab:spells"] and not O.panes.spells, "no Your spells tab: it is the Math tab's first section")
  expect((O.version and O.version.text or ""):find("^Holy Math"), "Settings tab: the version at the bottom (" .. tostring(O.version and O.version.text) .. ")")
  local hadAddOns = C_AddOns
  C_AddOns = { GetAddOnMetadata = function(name, field) return name == "HolyMath" and field == "Version" and "1.2.3" or nil end }
  expect(O.VersionText() == "Holy Math 1.2.3", "version: a release shows its number")
  C_AddOns.GetAddOnMetadata = function() return "@project-version@" end
  expect(O.VersionText() == "Holy Math (development copy)", "version: a copy from the repository says so")
  C_AddOns.GetAddOnMetadata = function() error("no") end
  expect(O.VersionText() == "Holy Math", "version: an API that fails shows just the name")
  C_AddOns = hadAddOns
  click(O.controls["tab:math"])
  expect(O.panes.math:IsShown() and not O.panes.settings:IsShown(), "Math tab shows its own page")
  local function plain(t) return ((t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("\n", " / ")) end
  local function rowText(row)
    local t = { plain(row.cells[1].text) }
    for _, c in ipairs(row.tcells) do t[#t + 1] = plain(c.text) end
    t[#t + 1] = plain(row.cells[3].text)
    return table.concat(t, " | ")
  end
  -- Your spells: the sheet's first section
  local function lines(kind)
    local t = {}
    for _, row in ipairs(O.mathRows) do if row.shown and row.data and row.data.tbl == kind then t[#t + 1] = row end end
    return t
  end
  local spellLines = lines("spell")
  expect(O.mathRows[1].data.head == "Your spells", "Math tab: Your spells is its first section")
  expect(#lines("cols") == 1 and plain(lines("cols")[1].tcells[2].text) == "Heal", "Your spells: its own column titles")
  expect(#spellLines >= 6 and tonumber(spellLines[1].tcells[2].text), "Your spells: every known spell, with heal per cast")
  local ov = {}
  for _, row in ipairs(spellLines) do ov[#ov + 1] = rowText(row) end
  for _, l in ipairs(ov) do realprint("    spell: " .. l) end
  GameTooltip.lines = {}
  spellLines[1].scripts.OnEnter(spellLines[1])
  expect((GameTooltip.lines[1] or "") ~= "" and spellLines[1].hl.shown, "Your spells: hovering a spell shows its tooltip and highlights it")
  spellLines[1].scripts.OnLeave(spellLines[1])
  -- a spell's overheal: its value cell, a setting for every rank
  local renew
  for _, row in ipairs(spellLines) do if row.data.spell.key == "RENEW" then renew = row end end
  expect(renew and renew.data.edit and renew.data.edit.setting[2] == "RENEW" and renew.valueBtn:IsShown()
    and plain(renew.cells[3].text) == "25%", "Your spells: Renew's overheal (25%) is a boxed value on its line")
  GameTooltip.lines = {}
  renew.valueBtn.scripts.OnEnter(renew.valueBtn)
  expect(GameTooltip.lines[1] == "Overheal: Renew", "Your spells: hovering the overheal says what it is")
  -- click a spell: its ranks fold down under it; again: they fold up
  expect(#lines("rank") == 0, "Your spells starts folded up")
  renew.scripts.OnMouseUp(renew)
  local rk = lines("rank")
  local renewTop = tonumber(renew.tcells[1].text)
  expect(O.expanded.RENEW and #rk == renewTop and plain(rk[1].cells[1].text) == "Rank " .. renewTop
    and plain(rk[#rk].cells[1].text) == "Rank 1", "click Renew: all its ranks fold down, highest first")
  for _, row in ipairs(O.mathRows) do if row.data and row.data.spell and row.data.spell.key == "RENEW" and row.data.tbl == "spell" then renew = row end end
  expect(renew.toggle.shown and (renew.toggle.texture or ""):find("Minus"), "Renew's [+] became a [-]")
  expect(rk[1].tcells[2].text == renew.tcells[2].text and rk[1].tcells[3].text == renew.tcells[3].text,
    "the highest rank's line matches the spell's line")
  expect(not rk[1].valueBtn:IsShown(), "a rank line has no overheal of its own (it is the spell's)")
  local best, low, blank = 0, 0, 0
  for _, r in ipairs(rk) do
    local t = plain(r.tcells[6].text)
    if t:find("most efficient") then best = best + 1 end
    if t:find("%d+%% of your healing power") then low = low + 1 end
    if t == "" then blank = blank + 1 end
  end
  expect(best == 1, "exactly one rank marked most efficient")
  expect(low >= 1, "low ranks say how much healing power they get")
  expect(blank == 0, "every rank line says something (full healing power too)")
  for _, r in ipairs(rk) do realprint("    renew: " .. rowText(r)) end
  GameTooltip.lines = {}
  rk[#rk].scripts.OnEnter(rk[#rk])
  expect(rk[#rk].spellID and rk[#rk].spellID ~= renew.spellID, "hovering a rank shows that rank's tooltip")
  -- a rank's line is only looked at: a click does nothing, and it doesn't light up
  local realShow, jumped = O.ShowMath, false
  O.ShowMath = function(...) jumped = true; return realShow(...) end
  rk[1].scripts.OnMouseUp(rk[1])
  O.ShowMath = realShow
  expect(not jumped and O.expanded.RENEW and #lines("rank") == renewTop, "clicking a rank does nothing (no jump down the sheet)")
  rk[1].scripts.OnEnter(rk[1])
  expect(not rk[1].hl.shown and (GameTooltip.lines[1] or "") ~= "", "hovering a rank shows its tooltip, no highlight")
  rk[1].scripts.OnLeave(rk[1])
  -- typing while a spell is clicked: the box closes and the click still works
  renew.valueBtn.scripts.OnClick(renew.valueBtn, "LeftButton")
  expect(O.mathEdit:IsShown(), "the overheal box opens")
  renew.scripts.OnMouseUp(renew)
  expect(not O.mathEdit:IsShown() and not O.expanded.RENEW, "clicking a spell closes the box and folds it up")
  local E_SOURCES = ns.model.MATH_SOURCES
  local mathLines, head, hpsLine, srcs = {}, nil, nil, 0
  for _, row in ipairs(O.mathRows) do
    if row.shown then
      local w = plain(row.wide.text)
      if w ~= "" then mathLines[#mathLines + 1] = w; if w:find("^Renew rank %d+: the filler") then head = true end
      else
        mathLines[#mathLines + 1] = rowText(row)
        if plain(row.cells[1].text) == "Healing per second" then hpsLine = plain(row.cells[3].text) end
        if E_SOURCES[row.src or ""] then srcs = srcs + 1 end
      end
    end
  end
  for _, l in ipairs(mathLines) do realprint("    math: " .. l) end
  expect(head, "Math tab works out the fight's spells (Renew, the filler)")
  expect(hpsLine and (hpsLine .. " HPS") == plain(O.hps.text), "Math tab's HPS = the Settings tab's (" .. tostring(hpsLine) .. ")")
  expect(srcs >= 10, "Math lines know where their numbers come from (shown on hover)")
  expect(not O.mathRows[1].cells[4], "no Source column")
  expect(O.frame.width == 880, "the Math tab makes the window wider")
  click(O.controls["tab:settings"])
  expect(O.frame.width ~= 880, "... and the Settings tab makes it narrow again")
  click(O.controls["tab:math"])
  expect(O.panes.math:IsShown(), "Math tab opens from its tab too")

  -- the sheet: type your own value, see it used everywhere, put it back
  local function cellRow(match)
    for _, row in ipairs(O.mathRows) do
      local e = row.shown and row.data and row.data.edit
      if e and (e.id == match or (e.setting and table.concat(e.setting, ".") == match)) then return row end
    end
  end
  local function press(row, button) row.valueBtn.scripts.OnClick(row.valueBtn, button or "LeftButton") end
  local function mine() local n = 0; for _ in pairs(db.overrides) do n = n + 1 end; return n end
  local hpsBefore = O.hps.text
  local function tipLine(link)
    ns.ClearVerdicts()
    GameTooltip.lines = {}; GameTooltip.fpLink = nil; GameTooltip.fakeLink = link
    postCalls[0](GameTooltip)
    return GameTooltip.lines[1] or ""
  end
  local tipBefore = tipLine("|Hitem:1002:0:|h")
  local cm = cellRow("stat.critMulti")
  expect(cm and cm.valueBtn:IsShown() and cm.box.top.shown, "sheet: 'a crit heals for' is a boxed value")
  press(cm)
  local eb = O.mathEdit
  expect(eb and eb:IsShown() and eb:HasFocus() and eb:GetText() == "1.5", "sheet: clicking it opens a box with 1.5 in it")
  expect(requestedTemplates.InputBoxTemplate, "sheet: the box is the game's own input box")
  O.Refresh(true)
  expect(eb:IsShown() and eb.row == cm and eb:GetText() == "1.5", "sheet: a change in game while typing leaves the box alone")
  eb:SetText("x2"); eb.scripts.OnEnterPressed(eb)
  expect(db.overrides["stat.critMulti"] == 2, "sheet: typing x2 makes crits heal for x2")
  expect(not eb:IsShown(), "sheet: Enter closes the box")
  expect(O.hps.text ~= hpsBefore, "sheet: the Settings tab's HPS uses your value")
  expect(tipLine("|Hitem:1002:0:|h") ~= tipBefore and tipBefore ~= "", "sheet: item tooltips use your value too")
  cm = cellRow("stat.critMulti")
  expect(plain(cm.cells[3].text) == "x2" and cm.resetBtn:IsShown(), "sheet: your value, with an arrow to put it back")
  GameTooltip.lines = {}
  cm.resetBtn.scripts.OnEnter(cm.resetBtn)
  expect((GameTooltip.lines[2] or ""):find("x1.5"), "sheet: the arrow says what it puts back")
  expect(O.yourValues:IsShown() and plain(O.yourValues.text.text):find("^1 value typed by you"), "a line at the bottom: 1 value is yours")
  GameTooltip.lines = {}
  cm.valueBtn.scripts.OnEnter(cm.valueBtn)
  local tipText = table.concat(GameTooltip.lines, " / ")
  expect(tipText:find("Before: x1.5") and tipText:find("right%-click"), "sheet: hovering your value says what it was")
  press(cm); eb:SetText("lots"); eb.scripts.OnEnterPressed(eb)
  expect(eb:IsShown() and db.overrides["stat.critMulti"] == 2, "sheet: text it can't read keeps the box open, saves nothing")
  eb.scripts.OnEscapePressed(eb)
  expect(not eb:IsShown() and plain(cellRow("stat.critMulti").cells[3].text) == "x2", "sheet: Esc closes the box, value unchanged")
  local mana = cellRow("stat.manaPool")
  press(cellRow("stat.critMulti")); press(mana)
  expect(plain(cellRow("stat.critMulti").cells[3].text) == "x2" and eb.row == mana, "sheet: opening another cell gives the first its value back")
  eb.scripts.OnEscapePressed(eb)
  press(cellRow("stat.critMulti"), "RightButton")
  expect(db.overrides["stat.critMulti"] == nil and O.hps.text == hpsBefore, "sheet: right-click puts back the game's value")
  expect(not O.yourValues:IsShown(), "the bottom line goes with it")
  press(cellRow("stat.critMulti")); eb:SetText("1.5"); eb.scripts.OnEnterPressed(eb)
  expect(mine() == 0, "sheet: typing the game's own value is not 'yours'")
  -- overheal is a setting on the sheet now
  local oh = cellRow("overheal.RENEW")
  expect(oh, "sheet: Renew's overheal is on it")
  press(oh); eb:SetText("40%"); eb.scripts.OnEnterPressed(eb)
  expect(db.settings.overheal.RENEW == 0.4 and mine() == 0, "sheet: typing 40% sets Renew's overheal (a setting, not 'yours')")
  press(cellRow("overheal.RENEW")); eb:SetText("300"); eb.scripts.OnEnterPressed(eb)
  expect(eb:IsShown() and db.settings.overheal.RENEW == 0.4, "sheet: 300% overheal is refused")
  eb.scripts.OnEscapePressed(eb)
  expect(not cellRow("fightLength").resetBtn:IsShown(), "sheet: no arrow on a setting at its starting value")
  local ohRow = cellRow("overheal.RENEW")
  expect(ohRow.resetBtn:IsShown(), "sheet: an arrow on a changed setting")
  GameTooltip.lines = {}
  ohRow.resetBtn.scripts.OnEnter(ohRow.resetBtn)
  expect((GameTooltip.lines[2] or ""):find("starting value: 25%%"), "sheet: the arrow says the starting value")
  ohRow.resetBtn.scripts.OnClick(ohRow.resetBtn)
  expect(db.settings.overheal.RENEW == 0.25 and not cellRow("overheal.RENEW").resetBtn:IsShown(),
    "sheet: the arrow puts it back, and goes")
  press(cellRow("overheal.RENEW")); eb:SetText("30"); eb.scripts.OnEnterPressed(eb)
  press(cellRow("overheal.RENEW"), "RightButton")
  expect(db.settings.overheal.RENEW == 0.25, "sheet: right-click puts a setting back to its starting value")
  -- your values on a spell rank, then all put back at once
  press(cellRow("talent.twinDisc")); eb:SetText("+20%"); eb.scripts.OnEnterPressed(eb)
  expect(math.abs((db.overrides["talent.twinDisc"] or 0) - 1.2) < 1e-12, "sheet: a talent typed as +20%")
  press(cellRow("talent.litanyRefund")); eb:SetText("20"); eb.scripts.OnEnterPressed(eb)
  expect(mine() == 2 and math.abs(db.overrides["talent.litanyRefund"] - 0.2) < 1e-12, "sheet: Twin Disciplines and Litany 20% typed")
  expect(plain(O.yourValues.text.text):find("^2 values typed by you"), "the bottom line counts 2")
  GameTooltip.lines = {}
  O.controls.ResetValues.scripts.OnEnter(O.controls.ResetValues)
  click(O.controls["tab:settings"])
  expect(O.yourValues:IsShown(), "the bottom line shows on the Settings tab too")
  click(O.controls.ResetValues)
  expect(mine() == 0 and not O.yourValues:IsShown() and O.hps.text == hpsBefore, "Put all back: the game's values everywhere")
  click(O.controls.YourSpells)
  expect(O.panes.math:IsShown() and O.mathAnchors.spells == 0, "Settings tab's 'Your spells' opens the sheet at Your spells")
  click(O.controls["tab:settings"])
  local insp = O.controls.insp
  expect(insp.enabled ~= false, "Inspiration's checkbox works: you have the talent")
  db.overrides["talent.inspiration"] = 0
  O.Changed(true)
  GameTooltip.lines = {}
  insp.scripts.OnEnter(insp)
  expect(insp.enabled == false and insp.shown ~= false, "... greyed out (still there) without it")
  expect((GameTooltip.lines[2] or ""):find("don't have the talent"), "... and its hover says why")
  db.overrides["talent.inspiration"] = nil
  O.Changed(true)
  expect(insp.enabled == true, "... and works again with it")
  db.overrides["stat.healing"] = 500
  SlashCmdList.HOLYMATH("reset")
  expect(mine() == 0, "/hm reset puts back every value")
  db.overrides["stat.crit"] = "broken"; db.overrides["stat.healing"] = -5
  O.Changed(true)
  expect(O.hps.text == hpsBefore and not O.yourValues:IsShown(), "a broken saved value is ignored")
  db.overrides = {}
  O.Changed(true)
  expect(tipLine("|Hitem:1002:0:|h") == tipBefore, "item tooltips back to the game's values")
  click(O.controls["tab:math"])
  -- open every spell: all stay open, the sheet grows (it scrolls)
  local total = 0
  for _, sr in ipairs(ns.State().spells) do total = total + 1 + sr.top end
  -- (clicking refills the sheet, so each spell's line is looked up again)
  local function spellRow(key) for _, row in ipairs(lines("spell")) do if row.data.spell.key == key then return row end end end
  local keys = {}
  for _, row in ipairs(lines("spell")) do keys[#keys + 1] = row.data.spell.key end
  for _, k in ipairs(keys) do if not O.expanded[k] then local row = spellRow(k); row.scripts.OnMouseUp(row) end end
  local open = 0
  for _ in pairs(O.expanded) do open = open + 1 end
  expect(open == #ov and #lines("spell") + #lines("rank") == total, "every spell open at once: " .. total .. " lines")
  for _, k in ipairs(keys) do if O.expanded[k] then local row = spellRow(k); row.scripts.OnMouseUp(row) end end
  expect(next(O.expanded) == nil and #lines("rank") == 0, "click them again: all folded up")
  -- rows reused for other lines lose the table's bits
  local leftover = 0
  for _, row in ipairs(O.mathRows) do
    if row.shown and row.data and not row.data.tbl and (row.click or row.toggle.shown or plain(row.tcells[2].text) ~= "") then leftover = leftover + 1 end
  end
  expect(leftover == 0, "sheet lines below Your spells show none of its columns")
  expect(not (O.castRows or O.notesText or O.controls.useBest), "no 'how to play' instructions left")

  -- item tooltips: three options on the Settings tab, no Tooltips tab
  click(O.controls["tab:settings"])
  expect(not O.controls["tab:tooltips"] and not O.panes.tooltips, "no Tooltips tab")
  expect(O.controls.tipItems and O.controls.tipItemNumber and O.controls.tipItemPct, "Settings tab: show, number, % for item tooltips")
  expect(O.controls.tipSpells, "Settings tab: spell tooltips on or off")
  O.controls.tipSpells:SetChecked(false); click(O.controls.tipSpells)
  expect(db.tooltips.spells == false, "unticking it turns the spell line off")
  O.controls.tipSpells:SetChecked(true); click(O.controls.tipSpells)
  expect(not (O.controls.tipOnlyUp or O.controls.tipShift or O.controls.tipCantEquip or O.controls.tipUseNote),
    "... and no other tooltip options")
  local c
  local function itemTip(link)
    ns.ClearVerdicts()
    GameTooltip.lines = {}; GameTooltip.fpLink = nil; GameTooltip.fakeLink = link
    postCalls[0](GameTooltip)
    return GameTooltip.lines[1] or ""
  end
  local better, worse = "|Hitem:1002:0:|h", "|Hitem:3002:0:|h"
  local line = plain(itemTip(better))
  expect(line:find("HPS %(%+[%d.]+%%%)$"), "item line shows the number and % by default (" .. line .. ")")
  c = O.controls.tipItemPct; c:SetChecked(false); click(c)
  line = plain(itemTip(better))
  expect(line:find("HPS$") and not line:find("%%"), "% off: just the number (" .. line .. ")")
  c:SetChecked(true); click(c)
  c = O.controls.tipItemNumber; c:SetChecked(false); click(c)
  line = plain(itemTip(better))
  expect(line:find(": %+[%d.]+%%$") and not line:find("HPS"), "number off: just the % (" .. line .. ")")
  O.controls.tipItemPct:SetChecked(false); click(O.controls.tipItemPct)
  expect(itemTip(better) == "", "number and % both off: no line")
  c:SetChecked(true); click(c); O.controls.tipItemPct:SetChecked(true); click(O.controls.tipItemPct)
  local realInv = GetInventoryItemLink
  GetInventoryItemLink = function(u, slot) if slot == 5 then return "|Hitem:3001:0:|h" end return realInv(u, slot) end
  expect(itemTip(worse):find("%-%d"), "a worse item shows a loss")
  GetInventoryItemLink = realInv
  c = O.controls.tipItems; c:SetChecked(false); click(c)
  expect(itemTip(better) == "", "item tooltips off: no line")
  c:SetChecked(true); click(c)
  db.tooltips.itemPercent = false; db.tooltips.items = false; db.tooltips.spells = false
  click(O.controls.Defaults)
  expect(db.tooltips.items and db.tooltips.itemPercent and db.tooltips.itemNumber and db.tooltips.spells,
    "Defaults puts the tooltip options back too")
  click(O.controls["tab:settings"])
  SlashCmdList.HOLYMATH("")
end

-- Profiles: named sets of settings, in a dropdown at the top right; the loaded one saves itself
do
  local O, P = ns.Options, ns.Profiles
  local db = HolyMathDB.PRIEST
  local popups = {}
  StaticPopupDialogs = {}
  StaticPopup_Show = function(which, a1, a2, data) popups[#popups + 1] = { which = which, text = a1, data = data } end
  StaticPopup_Hide = function() end
  local function menu()
    local m = { radios = {}, buttons = {}, titles = {} }
    local root = {
      CreateRadio = function(_, text, isSel, setSel, data)
        local r = { text = text, isSel = isSel, setSel = setSel, data = data }
        function r:SetTooltip(fn) self.tip = fn end
        m.radios[#m.radios + 1] = r; return r end,
      CreateButton = function(_, text, fn) m.buttons[#m.buttons + 1] = { text = text, fn = fn } end,
      CreateTitle = function(_, text) m.titles[#m.titles + 1] = text end,
      CreateDivider = function() end,
    }
    O.controls.profile.gen(O.controls.profile, root)
    return m
  end
  local function button(m, start) for _, b in ipairs(m.buttons) do if b.text:find(start, 1, true) == 1 then return b end end end
  local function closed() return O.controls.profile.translate and O.controls.profile.translate() end
  -- answer the last name popup with a name
  local function answer(name) local p = popups[#popups]; p.data.done(name) end

  local function click(b) b.scripts.OnClick(b) end
  click(O.controls.Defaults)
  expect(O.controls.profile and requestedTemplates.WowStyle1DropdownTemplate, "profile dropdown (the game's) in the window")
  local m = menu()
  expect(#m.radios == 0 and m.titles[1] == "No profiles yet" and closed() == "None", "no profiles: says so, field shows None")
  expect(button(m, "New profile") and not button(m, "Rename"), "menu: New profile; nothing to rename yet")

  -- New profile: asks for a name in the game's popup, saves the settings now
  db.settings.pomHits = 1
  button(m, "New profile").fn()
  expect(popups[#popups] and popups[#popups].which == "HOLYMATH_PROFILE_NAME" and StaticPopupDialogs.HOLYMATH_PROFILE_NAME.hasEditBox,
    "New profile asks for a name (popup with a text box)")
  answer("  1 bounce ")
  expect(P.Exists("1 bounce") and db.profiles["1 bounce"].settings.pomHits == 1 and P.Loaded() == "1 bounce", "saved as \"1 bounce\" (trimmed), now loaded")
  expect(closed() == "1 bounce", "field shows the loaded profile")
  db.settings.pomHits = 3; P.Save("3 bounces")
  db.settings.overheal.RENEW = 0.4; db.settings.fightLength = 300; db.rotation = "flashFill"; P.Save("long, flash")
  -- the same name again, or empty: asked again, saying why
  local n = #popups
  button(menu(), "New profile").fn(); answer("3 BOUNCES")
  expect(#popups == n + 2 and popups[#popups].text:find("already a profile"), "a taken name asks again, saying why")
  answer("")
  expect(popups[#popups].text:find("1 to"), "an empty name asks again too")
  answer("5 bounces"); P.Delete("5 bounces")

  -- the menu: every profile with its HPS, sorted
  m = menu()
  local names = {}
  for _, r in ipairs(m.radios) do names[#names + 1] = r.data end
  expect(table.concat(names, "|") == "1 bounce|3 bounces|long, flash", "menu lists the profiles by name (" .. table.concat(names, "|") .. ")")
  expect(m.radios[1].text:find("HPS"), "each with its HPS (" .. m.radios[1].text .. ")")
  local h1, h3 = P.HPS("1 bounce"), P.HPS("3 bounces")
  expect(h1 and h3 and h3 > h1, string.format("more bounces heal more: %.0f vs %.0f", h1 or 0, h3 or 0))
  -- hover: what differs from the settings now (loaded: long, flash)
  local fake = { lines = {} }
  function fake:SetText(t) self.lines = { t } end
  function fake:AddLine(t) self.lines[#self.lines + 1] = t end
  m.radios[1].tip(fake)
  local tipText = table.concat(fake.lines, "\n")
  expect(tipText:find("Prayer of Mending bounces: 1 %(now 3%)") and tipText:find("Fight length") and tipText:find("Playstyle")
    and tipText:find("Overheal, Renew"), "hover lists the differences:\n" .. tipText)
  P.Load("long, flash")
  m.radios[3].tip(fake)
  expect(table.concat(fake.lines, " "):find("what you change is saved into it"), "the loaded one says it saves itself")

  -- load: settings and playstyle swap, HPS in the window follows
  local before = O.hps.text
  m.radios[1].setSel(m.radios[1].data)
  expect(db.settings.pomHits == 1 and db.settings.fightLength == 120 and db.rotation == "renew" and db.settings.overheal.RENEW == 0.25,
    "loading a profile sets its settings")
  expect(O.hps.text ~= before and m.radios[1].isSel("1 bounce"), "the result follows; the profile is selected")
  local shown = ns.State().weights.base.ehps
  expect(math.abs(shown - h1) < 0.01, "its HPS in the menu is what you get when it's loaded")

  -- auto-save: a change goes into the loaded profile by itself, and only into it
  O.controls.insp:SetChecked(false); O.controls.insp.scripts.OnClick(O.controls.insp)
  expect(db.profiles["1 bounce"].settings.includeInspiration == false and closed() == "1 bounce",
    "a change on the Settings tab is saved into the loaded profile")
  expect(db.profiles["3 bounces"].settings.includeInspiration == true, "... and not into the others")
  db.settings.overheal.GH = 0.5; O.Changed(true)
  expect(db.profiles["1 bounce"].settings.overheal.GH == 0.5, "overheal set on the Math tab is saved into it too")
  expect(not button(menu(), "Save changes"), "nothing to save by hand")
  P.Load("3 bounces")
  expect(db.settings.includeInspiration == true and db.settings.overheal.GH == 0.25 and db.profiles["1 bounce"].settings.pomHits == 1,
    "switching profiles: each keeps its own settings")
  P.Load("1 bounce")
  expect(db.settings.includeInspiration == false and db.settings.overheal.GH == 0.5, "... and switching back brings them back")
  -- profiles hold no typed Math-tab values
  db.overrides["stat.healing"] = 1000
  P.Save("1 bounce")
  expect(db.profiles["1 bounce"].overrides == nil and db.profiles["1 bounce"].settings.overrides == nil, "typed values are not saved in a profile")
  P.Load("3 bounces")
  expect(db.overrides["stat.healing"] == 1000, "loading a profile leaves typed values alone")
  db.overrides = {}

  -- rename (asks, refuses a taken name) and delete (asks first)
  P.Load("1 bounce")
  button(menu(), "Rename").fn(); answer("long, Flash")
  expect(popups[#popups].text:find("already a profile") and P.Exists("1 bounce"), "rename to a taken name: asked again")
  answer("one bounce")
  expect(P.Exists("one bounce") and not P.Exists("1 bounce") and P.Loaded() == "one bounce", "renamed, still loaded")
  button(menu(), "Delete").fn()
  local del = popups[#popups]
  expect(del.which == "HOLYMATH_PROFILE_DELETE" and P.Exists("one bounce"), "Delete asks first")
  StaticPopupDialogs.HOLYMATH_PROFILE_DELETE.OnAccept(nil, del.data)
  expect(not P.Exists("one bounce") and P.Loaded() == nil and closed() == "None" and db.settings.pomHits == 1,
    "deleted; your settings stay, nothing loaded")

  -- Defaults leaves the profiles alone
  click(O.controls.Defaults)
  expect(P.Exists("3 bounces") and P.Exists("long, flash"), "Defaults keeps the profiles")

  -- an older profile missing a setting gets its default when loaded
  db.profiles.old = { settings = { pomHits = 2 }, rotation = "nope" }
  P.Load("old")
  expect(db.settings.pomHits == 2 and db.settings.fightLength == 120 and db.rotation == "renew",
    "an old profile is filled in with defaults")
  P.Delete("old")

  -- /hm profile: list, and load by name (any case) for macros
  printed = {}
  SlashCmdList.HOLYMATH("profile")
  expect(table.concat(printed, " "):find("3 bounces %(%d+ HPS%)"), "/hm profile lists them with HPS")
  SlashCmdList.HOLYMATH("profile LONG, FLASH")
  expect(P.Loaded() == "long, flash" and db.settings.fightLength == 300, "/hm profile <name> loads one")
  printed = {}
  SlashCmdList.HOLYMATH("profile nothing")
  expect(table.concat(printed, " "):find("no profile called"), "/hm profile with an unknown name says so")

  -- a window refresh doesn't nudge values typed off the sliders' steps (that would be saved)
  db.settings.fightLength = 125; db.settings.overheal.GH = 0.33; db.settings.pomHits = 4
  P.Save("odd values"); O.Changed(true); O.Refresh(true)
  local odd = db.profiles["odd values"].settings
  expect(odd.fightLength == 125 and odd.overheal.GH == 0.33 and odd.pomHits == 4, "values typed off the slider steps stay as typed")
  -- a profile whose playstyle needs a talent you don't have: the default is used, the profile keeps its own
  db.profiles.renewed = { settings = ns.model.copy(db.settings), rotation = "rhTank" }
  P.Load("renewed"); ns.State(true); O.Refresh(true); O.Changed(true)
  expect(db.rotation == "renew" and db.profiles.renewed.rotation == "rhTank",
    "a playstyle you can't use: the default is used, the profile keeps its own")
  -- Defaults with a profile loaded: that profile is reset too (it saves itself)
  click(O.controls.Defaults)
  expect(db.profiles.renewed.settings.fightLength == 120, "Defaults resets the loaded profile")
  P.Delete("renewed")
  -- "|" can't get into a name (it starts colour codes)
  expect(P.CleanName("|cffff0000red|r") == "cffff0000redr", "\"|\" is taken out of names")
  -- many profiles: a window refresh stays quick
  for i = 1, 20 do db.settings.pomHits = 1 + i % 5; db.settings.fightLength = 60 + i * 30; P.Save("p" .. i) end
  -- like the game's dropdown: a refresh builds the menu again for the closed field's text
  local dd, seen = O.controls.profile, {}
  dd.GenerateMenu = function(self)
    self.gen(self, { CreateRadio = function(_, text) seen[#seen + 1] = text; return {} end,
                     CreateButton = function() end, CreateTitle = function() end, CreateDivider = function() end })
  end
  local function timed(fn) local t0 = os.clock(); for _ = 1, 5 do ns.MarkDirty(); fn() end; return (os.clock() - t0) / 5 * 1000 end
  local refresh = timed(function() O.Refresh(true) end)
  local base = refresh
  expect(#seen > 0 and not table.concat(seen, " "):find("HPS"), "a refresh works out no profile HPS (only the closed field)")
  local open = timed(function() O.Refresh(true); menu() end) - refresh
  realprint(string.format("     20 profiles (desktop Lua): refresh %.0f ms, opening the menu %.0f ms more", base, open))
  local m20 = menu()
  expect(#m20.radios == #P.List() and #m20.radios >= 20 and m20.radios[1].text:find("HPS"), "opening the menu shows every profile with its HPS")
  dd.GenerateMenu = noop

  for _, k in ipairs(P.List()) do P.Delete(k) end
  click(O.controls.Defaults)
  StaticPopupDialogs, StaticPopup_Show, StaticPopup_Hide = nil, nil, nil
end

-- Potions on the Settings tab: the list by cooldown, counts, add, remove, best mix
do
  local O, M = ns.Options, ns.model
  local db = HolyMathDB.PRIEST
  local function click(b) b.scripts.OnClick(b) end
  click(O.controls.Defaults)
  local function row(i) return O.controls["potion:" .. i] end
  local function shownRows()
    local out = {}
    for i = 1, 5 do local r = row(i); if r.index then out[#out + 1] = r end end
    return out
  end
  O.Refresh(true)
  local r1 = row(1)
  expect(r1.index == 1 and r1.name.text == "Major Mana Potion" and r1.count.text == "1",
    "default: Major Mana Potion, 1 in a 120 s fight (" .. tostring(r1.name.text) .. " " .. tostring(r1.count.text) .. ")")
  expect(O.controls.potionGroups[1].text:find("Potion cooldown: 1 fit in a 120 s fight"), "its cooldown line: " .. tostring(O.controls.potionGroups[1].text))
  -- "as many as fit" follows the fight length
  db.settings.fightLength = 300; O.Changed(true)
  expect(row(1).count.text == "3", "as many as fit follows the fight: 3 in 300 s")
  local manaBefore = ns.State().weights.base.mana

  -- Add potion: the game's dropdown, grouped by cooldown, each with its worth
  local add = O.controls.potionAdd
  expect(add and type(add.gen) == "function", "Add potion uses the game's dropdown")
  local m = { buttons = {}, titles = {} }
  add.gen(add, { CreateTitle = function(_, t) m.titles[#m.titles + 1] = t end,
                 CreateButton = function(_, t, fn) local b = { text = t, fn = fn }; function b:SetTooltip(f) self.tip = f end
                   m.buttons[#m.buttons + 1] = b; return b end })
  expect(m.titles[1] == "Potion cooldown" and m.titles[2] == "Rune cooldown", "menu: grouped by cooldown")
  local names = {}
  for _, b in ipairs(m.buttons) do names[#names + 1] = b.text end
  local all = table.concat(names, "\n")
  expect(not all:find("Major Mana Potion") and all:find("Major Mender's Potion") and all:find("Demonic Rune"),
    "menu: the ones not in your list yet")
  expect(all:find("Major Mender's Potion  |cff9d9d9d[+-]%d"), "menu: each with what it adds in HPS")
  local function pick(prefix) for _, b in ipairs(m.buttons) do if b.text:find(prefix, 1, true) == 1 then return b end end end
  pick("Major Mender's Potion").fn()
  pick("Demonic Rune").fn()
  local list = db.settings.potions
  expect(#list == 3 and list[2].key == "majorMenders" and list[3].key == "demonicRune", "added to the list")
  -- the Mender's comes after the Major Mana: nothing left on the potion cooldown for it
  local rows = shownRows()
  expect(#rows == 3 and rows[1].name.text == "Major Mana Potion" and rows[2].name.text == "Major Mender's Potion"
    and rows[2].count.text == "0" and rows[3].name.text == "Demonic Rune" and rows[3].count.text == "3",
    "shown by cooldown: Major Mana 3, Mender's 0 (no room), Demonic Rune 3 (its own cooldown)")
  expect(O.controls.potionGroups[2].text:find("Rune cooldown: 3 fit"), "the runes' cooldown line")
  expect(ns.State().weights.base.mana > manaBefore, "runes add mana on top of the potions")

  -- [-] on Major Mana frees a cooldown; [+] on Mender's takes it
  click(row(1).minus)
  expect(list[1].n == 2 and row(1).count.text == "2", "[-] takes one away")
  click(row(2).plus)
  expect(row(2).count.text == "1" and list[2].n == M.POTION_ALL, "[+] up to what fits: then it's as many as fit")
  local S = ns.State()
  expect(S.weights.base.potions.healing > 0, "the Mender's Potion adds healing power on average")
  click(row(2).minus); click(row(2).minus)
  expect(list[2].n == 0 and row(2).count.text == "0", "[-] down to 0")

  -- best for you, and Use it
  db.settings.fightLength = 60; O.Changed(true)
  local best, gain = O.PotionBest()
  expect(best and gain, "a best mix is worked out")
  realprint("     potions, 60 s fight: " .. tostring(O.potionBestText.text))
  if gain and gain > 0.05 then
    expect(O.potionBestText.text:find("Best for you:") and O.controls.potionUseBest.shown, "best mix shown with Use it")
    click(O.controls.potionUseBest)
    local _, after = O.PotionBest()
    expect(math.abs(after or 1) < 0.05 and O.potionBestText.text:find("best mix"), "Use it: the counts are the best mix")
  end
  -- Remove
  click(row(3).remove)
  expect(#list == 2 and list[2].key ~= "demonicRune" and list[1].key ~= "demonicRune", "Remove takes it out of the list")
  -- level: a potion you can't use yet says so
  local realLevel = UnitLevel
  UnitLevel = function() return 40 end
  ns.MarkDirty(); O.Refresh(true)
  local lowRow
  for _, r in ipairs(shownRows()) do if r.name.text:find("Major Mana Potion") then lowRow = r end end
  expect(lowRow and lowRow.name.text:find("level 49"), "a potion above your level: shown with the level it needs")
  UnitLevel = realLevel
  ns.MarkDirty(); O.Refresh(true)
  -- the Math tab lists them
  db.settings.fightLength = 300
  db.settings.potions = { { key = "majorMenders", n = 1 }, { key = "majorMana", n = M.POTION_ALL } }
  O.Changed(true)
  local text = {}
  for _, r in ipairs(ns.model.MathPage(ns.State())) do text[#text + 1] = (r[1] or r.note or "") .. " | " .. (r[2] or "") end
  text = table.concat(text, "\n")
  expect(text:find("Major Mana Potion | 2 x 1800") and text:find("Major Mender's Potion | %+88 healing")
    and text:find("Healing power here"), "Math tab: a line for each potion, and the healing power the casts use")
  -- profiles keep their own potions, and say how they differ
  local P = ns.Profiles
  P.Save("menders"); P.Save("no pots"); db.settings.potions = {}; O.Changed(true)   -- (the loaded one saves itself)
  local diff = table.concat(P.Diff("menders"), "\n")
  expect(diff:find("Potions: Major Mender's Potion x1, Major Mana Potion %(all%) %(now none%)"), "profile difference: " .. diff)
  P.Load("menders")
  expect(#db.settings.potions == 2, "loading a profile brings its potions back")
  P.Delete("menders"); P.Delete("no pots")
  -- speed: a refresh works out the best mix again (3 potions, a 5 min fight)
  db.settings.potions = { { key = "majorMenders", n = 1 }, { key = "majorMana", n = M.POTION_ALL }, { key = "demonicRune", n = M.POTION_ALL } }
  db.settings.fightLength = 300
  local t0 = os.clock()
  for _ = 1, 5 do O.Changed(true) end
  local ms = (os.clock() - t0) / 5 * 1000
  realprint(string.format("     potions: %.0f ms per window refresh with the best mix (desktop Lua)", ms))
  expect(ms < 300, "a refresh with 3 potions stays quick")
  -- /hm set pots on|off
  SlashCmdList.HOLYMATH("set pots off")
  expect(#db.settings.potions == 0, "/hm set pots off: no potions")
  SlashCmdList.HOLYMATH("set pots on")
  expect(#db.settings.potions == 1 and db.settings.potions[1].key == "majorMana", "/hm set pots on: Major Mana Potions")
  click(O.controls.Defaults)
end

-- A Mender's Potion's buff active when the stats are read: its healing is taken out
-- of healing power, but only after the tooltips (which have it in them) are read
do
  local M = ns.model
  local realAuras, realGetItemSpell, realDesc, realHeal = C_UnitAuras.GetAuraDataByIndex, C_Item.GetItemSpell,
    C_Spell.GetSpellDescription, GetSpellBonusHealing
  local function rk(S, key, rank) for _, r in ipairs(S.info.client) do if r.key == key and r.rank == rank then return r end end end
  ns.clientSeen = nil; ns.MarkDirty()
  local S0 = ns.State(true)
  local before, renewBase, ghBase = S0.st.healing, rk(S0, "RENEW", 9).base, rk(S0, "GH", 4).base
  -- the buff: the game's healing power and its spell tooltips are 88 higher
  local up = {}
  for k, v in pairs(S0.st) do up[k] = v end
  up.healing = before + 88
  local renewUp = M.ModelTooltipHeal("RENEW", 9, up, S0.t, S0.input.settings)
  local ghUp = M.ModelTooltipHeal("GH", 4, up, S0.t, S0.input.settings)
  C_Item.GetItemSpell = function(id) if id == 250949 then return "Healing Brew", 555001 end end
  C_UnitAuras.GetAuraDataByIndex = function(_, i)
    return ({ { name = "Greater Blessing of Kings" }, { name = "Healing Brew", spellId = 555001 } })[i]
  end
  GetSpellBonusHealing = function() return realHeal() + 88 end
  C_Spell.GetSpellDescription = function(id)
    if id == 109 then return string.format("Heals the target of %d damage over 15 sec.", math.floor(renewUp + 0.5)) end
    if id == 204 then
      return string.format("A slow casting spell that heals a single target for %d to %d.", math.floor(ghUp - 118 + 0.5), math.floor(ghUp + 118 + 0.5))
    end
    return realDesc(id)
  end
  ns.clientSeen = nil; ns.MarkDirty()
  local S = ns.State(true)
  expect(math.abs(S.st.healing - before) < 1e-6 and S.info.how.potionBuff and S.info.how.potionBuff:find("Major Mender's Potion"),
    "Major Mender's buff active: its +88 is taken out of the game's healing power")
  expect(math.abs(rk(S, "RENEW", 9).base - renewBase) < 1 and math.abs(rk(S, "GH", 4).base - ghBase) < 1,
    string.format("... after the tooltips are read: base heals unchanged (Renew %.1f/%.1f, GH %.1f/%.1f)",
      rk(S, "RENEW", 9).base, renewBase, rk(S, "GH", 4).base, ghBase))
  printed = {}
  SlashCmdList.HOLYMATH("check")
  expect(table.concat(printed, "\n"):find("Potion: Major Mender's Potion active"), "/hm check says so")
  SlashCmdList.HOLYMATH("dump")
  local found = false
  for _, b in ipairs(HolyMathDB.dump.buffIds or {}) do if b.spellId == 555001 then found = true end end
  expect(found and HolyMathDB.dump.potionSpells.majorMenders.spellId == 555001, "/hm dump keeps buff and potion spell IDs")
  C_UnitAuras.GetAuraDataByIndex, C_Item.GetItemSpell, GetSpellBonusHealing, C_Spell.GetSpellDescription =
    realAuras, realGetItemSpell, realHeal, realDesc
  ns.clientSeen = nil; ns.MarkDirty(); ns.State(true)
end

-- Saved settings from before the potion list
do
  local function login(saved)
    HolyMathDB = { PRIEST = saved }
    local ns5 = {}
    for _, f in ipairs({ "Models/PriestData.lua", "Models/GearData.lua", "Models/Priest.lua", "Models/GearSolve.lua", "Models/PriestMath.lua", "Game.lua", "Tooltips.lua", "Core.lua", "Options.lua", "Playstyles.lua", "Gear.lua", "Minimap.lua" }) do
      assert(loadfile(f))("HolyMath", ns5)
    end
    local core5 = frames[#frames]
    core5.scripts.OnEvent(core5, "PLAYER_LOGIN")
    return HolyMathDB.PRIEST
  end
  local keep, keepSlash = HolyMathDB, SlashCmdList.HOLYMATH
  local a = login({ settings = { majorManaPotions = true, fightLength = 120 } })
  expect(#a.settings.potions == 1 and a.settings.potions[1].key == "majorMana" and a.settings.majorManaPotions == nil,
    "saved 'mana potion on cooldown' on: Major Mana Potions")
  local b = login({ settings = { majorManaPotions = false, fightLength = 120 },
                    profiles = { old = { settings = { majorManaPotions = true, pomHits = 2 }, rotation = "renew" } } })
  expect(#b.settings.potions == 0, "saved off: no potions, and it stays empty (not refilled from the default)")
  expect(#b.profiles.old.settings.potions == 1 and b.profiles.old.settings.majorManaPotions == nil, "an old profile's switch moves over too")
  local c = login({ settings = { potions = {}, fightLength = 120 } })
  expect(#c.settings.potions == 0, "an emptied list stays empty at the next login")
  HolyMathDB, SlashCmdList.HOLYMATH = keep, keepSlash
end

-- The Playstyles tab: blocks you drag in, built-ins you change, your own, export and import
do
  local O, PS, E = ns.Options, ns.Playstyles, ns.model
  local db = HolyMathDB.PRIEST
  local popups = {}
  StaticPopupDialogs = {}
  StaticPopup_Show = function(which, a1, a2, data) popups[#popups + 1] = { which = which, text = a1, data = data } end
  StaticPopup_Hide = function() end
  local function click(b, button) b.scripts.OnClick(b, button) end
  local function plain(t) return ((t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  local function err() return ns.errors.playstyles and ns.errors.playstyles.last end
  local function steps() return PS.Def(db.rotation).steps end
  local function spells() local o = {} for _, d in ipairs(steps()) do o[#o + 1] = d.spell .. ":" .. d.how end return table.concat(o, " ") end
  if not O.frame:IsShown() then SlashCmdList.HOLYMATH("") end
  db.rotation = "renew"
  O.ShowTab("playstyles")
  expect(O.controls["tab:playstyles"] and O.panes.playstyles.shown and O.frame.width == 880, "a Playstyles tab (as wide as the Math tab)")
  expect(err() == nil, "the tab fills without errors (" .. tostring(err()) .. ")")
  -- Renew filler as blocks: PoM, Penance, Binding Heal, Greater Heal, then Renew
  expect(O.psShown == 5 and plain(O.psRows[1].name.text) == "Prayer of Mending" and plain(O.psRows[5].name.text) == "Renew",
    "Renew filler shows as 5 blocks, Renew last (" .. tostring(O.psShown) .. ")")
  expect(plain(O.psRows[5].sub.text) == "the filler" and O.psRows[5].fillText.shown and not O.psRows[5].how.shown,
    "the last block is the filler")
  expect(O.psRows[1].how.translate() == "On cooldown" and O.psRows[4].how.translate() == "At most twice a minute",
    "how often in words: PoM on cooldown, Greater Heal at most twice a minute")
  -- under the result: the fight
  expect(O.psFight.shown and not O.psViewFight and not O.psHow, "the fight under the result, on its own")
  expect(O.psNote.shown and plain(O.psNote.text):find("most healing per second") and plain(O.psNote.text):find("other healers"),
    "... with a note: the most HPS, not how a real fight goes")
  -- The fight: a ruler, a row for waiting for mana, a row per block
  local tl, F = O.psTimeline, O.psFight
  local rows = 0
  for _, lane in ipairs(F.lanes) do if lane.shown then rows = rows + 1 end end
  expect(rows == 6 and plain(F.lanes[1].name.text) == "Waiting for mana" and plain(F.lanes[2].name.text) == "Prayer of Mending",
    "The fight: waiting for mana, then a row per block, no potions row (" .. rows .. " rows)")
  expect(F.ticks[1].text == "0:00" and F.ticks[2].text == "0:30" and F.ticks[5].text == "2:00", "... a ruler every 30 s")
  local pomRuns, pomCasts = #F.lanes[2].runs, 0
  for _, c in ipairs(tl.casts) do if c.block == 1 then pomCasts = pomCasts + 1 end end
  local marks = 0
  for _, m in ipairs(F.lanes[2].marks) do if m.shown then marks = marks + 1 end end
  expect(pomCasts == 12 and pomRuns == 12 and marks == 12, "... Prayer of Mending: 12 casts, each with its icon (" .. marks .. ")")
  local labels = 0
  for _, l in ipairs(F.lanes[2].labels) do if l.shown then labels = labels + 1 end end
  expect(labels >= 11 and F.lanes[2].labels[2].text:find("^0:1%d$"), "... and its time next to it (" .. tostring(F.lanes[2].labels[2].text) .. ", " .. labels .. " labels)")
  -- drawn again for another fight length: no time left over from before
  db.settings.fightLength = 90; O.Changed(true)
  db.settings.fightLength = 120; O.Changed(true)
  local stale = 0
  for li, lane in ipairs(F.lanes) do
    local starts = {}
    for _, run in ipairs(lane.runs or {}) do starts[string.format("%d:%02d", math.floor(math.floor(run.t + 0.5) / 60), math.floor(run.t + 0.5) % 60)] = true end
    for _, l in pairs(lane.labels) do if l.shown and not starts[l.text] then stale = stale + 1 end end
  end
  expect(stale == 0, "redrawn: no times left over from an earlier fight (" .. stale .. ")")
  -- an icon per cast; bars only for what lasts (Renew's 15 s), none for Prayer of Mending
  local pomBars, renewBars = 0, 0
  for _, b in pairs(F.lanes[2].bars) do if b.shown then pomBars = pomBars + 1 end end
  for _, b in pairs(F.lanes[6].bars) do if b.shown then renewBars = renewBars + 1 end end
  local renewIcons = 0
  for _, m in ipairs(F.lanes[6].marks) do if m.shown then renewIcons = renewIcons + 1 end end
  expect(pomBars == 0 and renewBars == renewIcons and renewIcons == #F.lanes[6].runs,
    string.format("an icon per cast; a bar only for Renew's 15 s (%d Renew icons, %d bars; %d Prayer of Mending bars)", renewIcons, renewBars, pomBars))
  local renew = F.lanes[6].runs[1]
  expect(renew and renew.e - renew.t >= 15 - 1e-6, "Renew's bar is its 15 s on the target")
  local tip = O.FightTipAt(2, 0.001)
  expect(tip and plain(tip[1]) == "0:00  Prayer of Mending (rank 3)", "hover a cast: " .. tostring(tip and plain(tip[1])))
  local w1 = F.lanes[1].runs[1]
  if w1 then
    local wt = O.FightTipAt(1, ((w1.t + w1.e) / 2) / O.psFightLength)
    expect(wt and wt[1]:find("waiting for mana"), "hover the mana row: waiting for mana")
  end
  expect(O.psRows[4].every.text == "(30 s)" and O.psRows[1].every.text == "(10 s)", "... with the seconds in grey")
  expect(plain(O.psRows[2].sub.text) == "not learned yet", "Penance (not learned here) says so")
  expect((O.psRows[5].casts.text or ""):find("^%d+ casts$") and O.psRows[1].casts.text:find("casts"), "each block shows its casts in the fight")
  local ch = O.psRows[1].castHit
  ch.scripts.OnEnter(ch)
  expect(plain(table.concat(GameTooltip.lines, " ")):find("casts of rank %d+ in a %d+ s fight, as often as set%."),
    "... hover: the rank and what stopped it: " .. plain(table.concat(GameTooltip.lines, " ")))
  expect(O.psStatus.text:find("^Built%-in%.") and not O.controls.psReset.shown and not O.controls.psDelete.shown,
    "a built-in: says so; nothing to put back or delete")
  local hps0 = ns.State().weights.base.ehps
  local res = plain(O.psResult.text)
  expect(res:find("^" .. math.floor(hps0 + 0.5) .. " HPS after overheal  %-  Inspiration up %d+%% of the time%.$"),
    "the result under the blocks: " .. res)

  -- click a spell in the row: it goes in above the filler; the built-in is now edited
  click(O.controls["psSpell:LESSER"])
  expect(spells() == "POM:cd PENANCE:cd BH:pm GH:pm LESSER:pm RENEW:fill", "clicking Lesser Heal adds it above the filler (" .. spells() .. ")")
  expect(PS.Kind("renew") == "edited" and E.ROTATIONS.renew.edited and O.controls.psReset.shown,
    "Renew filler is now edited, with Put default back")
  expect(plain(O.psRows[5].sub.text) == "not learned yet", "Lesser Heal isn't learned here: greyed with why")

  -- a drag from the row of icons, let go before block 2
  local pb = O.controls["psSpell:FLASH"]
  pb.scripts.OnDragStart(pb)
  expect(O.psGhost.shown, "dragging shows the icon under the cursor")
  O.DragEnd(2)
  expect(not O.psGhost.shown and spells() == "POM:cd FLASH:pm PENANCE:cd BH:pm GH:pm LESSER:pm RENEW:fill",
    "dropped before block 2 (" .. spells() .. ")")
  -- drag block 2 to the end: it becomes the filler, the old filler gets "keep it up"
  local ic = O.psRows[2].iconBtn
  ic.scripts.OnDragStart(ic)
  O.DragEnd(O.psShown + 1)
  expect(spells() == "POM:cd PENANCE:cd BH:pm GH:pm LESSER:pm RENEW:up FLASH:fill",
    "a block dragged to the end becomes the filler; Renew is kept up now (" .. spells() .. ")")
  -- dragged off the list: removed
  ic = O.psRows[5].iconBtn
  ic.scripts.OnDragStart(ic)
  O.DragEnd(false)
  expect(spells() == "POM:cd PENANCE:cd BH:pm GH:pm RENEW:up FLASH:fill", "a block dragged off the list is removed (" .. spells() .. ")")
  -- from the spellbook: the game's cursor holds Greater Heal rank 2 (id 202 in this fake client)
  GetCursorInfo = function() return "spell", 7, "spell", 202 end
  local cleared = false
  ClearCursor = function() cleared = true end
  O.psRows[1].scripts.OnReceiveDrag(O.psRows[1])
  local d1 = steps()[1]
  expect(d1.spell == "GH" and d1.rank == 2 and cleared, "a spell from the spellbook comes in at its rank (Greater Heal 2)")
  GetCursorInfo = function() return nil end
  O.psRows[1].scripts.OnMouseUp(O.psRows[1])
  expect(#steps() == 7, "a click with nothing on the cursor adds nothing")
  -- the block's own settings
  O.StepSet(1, "rank", 1)
  local rm = {}
  O.psRows[1].rank.gen(O.psRows[1].rank, { CreateRadio = function(_, text, isSel, setSel, data)
    rm[#rm + 1] = { text = text, isSel = isSel, setSel = setSel, data = data }; return {} end })
  expect(rm[1].text == "Best rank" and rm[2].text == "Highest rank" and rm[3].data == 1 and rm[3].isSel(rm[3].data)
    and not rm[1].isSel(rm[1].data), "rank menu: Best, Highest, then each rank (Rank 1 chosen)")
  rm[1].setSel(rm[1].data)
  expect(steps()[1].rank == nil and O.psRows[1].rank.translate() == "Best rank", "Best rank from the menu")
  O.StepSet(1, "rank", 1)
  O.StepSet(1, "how", "pm")
  expect(steps()[1].how == "pm" and steps()[1].n == 2, "times a minute starts from what it was (2)")
  for _ = 1, 50 do click(O.psRows[1].plus) end
  expect(steps()[1].n == 40 and plain(O.psRows[1].every.text) == "(1.5 s)", "+ stops at a global cooldown (40 a minute)")
  click(O.psRows[1].minus)
  expect(steps()[1].n == 39, "- one fewer a minute")
  O.StepSet(2, "how", "sec")
  expect(steps()[2].how == "sec" and steps()[2].n == 10, "every N seconds starts at its cooldown (Prayer of Mending, 10 s)")
  click(O.psRows[2].minus)
  expect(steps()[2].n == 10, "... and can't go under it")
  click(O.psRows[2].plus)
  expect(steps()[2].n == 11 and O.psRows[2].how.translate() == "At most every 11 s", "+ a second longer: at most every 11 s")
  local tank = O.psRows[6].tank
  tank:SetChecked(true); click(tank)
  expect(steps()[6].tank == true, "On the tank ticks for the block")
  -- right-click: the moves as a menu (no MenuUtil in this fake client: right-click moves it up)
  O.StepMenu(O.psRows[3].iconBtn, 3)
  local labels = {}
  for _, it in ipairs(O.lastStepMenu) do labels[#labels + 1] = it[1] end
  expect(table.concat(labels, "|") == "Move up|Move down|Make it the filler (last)|Remove", "right-click menu: " .. table.concat(labels, "|"))
  -- a shield on the tank more often than Weakened Soul allows: warned
  O.StepAdd("PWS", 1, 1)
  O.StepSet(1, "how", "pm")
  for _ = 1, 3 do click(O.psRows[1].plus) end
  expect(plain(O.psRows[1].sub.text) == "waits for Weakened Soul (15 s)", "PW:Shield on the tank too often: a short warning under its name")
  O.psRows[1].nameHit.scripts.OnEnter(O.psRows[1].nameHit)
  expect(plain(GameTooltip.lines[#GameTooltip.lines]):find("again for 15 s; this block asks for every [%d.]+ s%. The fight counts a shield only when"),
    "... in full when you hover the name: " .. tostring(GameTooltip.lines[#GameTooltip.lines]))
  O.StepSet(1, "how", "cd")
  expect(plain(O.psRows[1].every.text) == "(15 s)" and not plain(O.psRows[1].sub.text):find("Weakened"),
    "on cooldown on the tank waits for Weakened Soul (15 s)")
  expect(O.controls.psRH.shown and O.psRHGreyed, "a playstyle with PW:Shield shows Keep Weakened Soul, greyed without Renewed Hope")
  click(O.controls["psSpell:POH"])
  expect(#steps() == 8, "8 blocks")
  local errs = 0
  UIErrorsFrame = { AddMessage = function() errs = errs + 1 end }
  click(O.controls["psSpell:NOVA"])
  expect(#steps() == 8 and errs == 1, "a 9th block is turned away, saying why")
  expect(err() == nil, "no errors filling the tab while editing (" .. tostring(err()) .. ")")

  -- the HPS follows the blocks; Put default back gives Renew filler as shipped
  expect(math.abs(ns.State().weights.base.ehps - hps0) > 0.5, "the edited playstyle heals differently")
  click(O.controls.psReset)
  StaticPopupDialogs.HOLYMATH_PLAYSTYLE_RESET.OnAccept(nil, popups[#popups].data)
  expect(PS.Kind("renew") == "builtin" and math.abs(ns.State().weights.base.ehps - hps0) < 1e-6,
    "Put default back: Renew filler as shipped, the same HPS")
  -- Greater Heal filler with Greater Heal moved up: its Holy Binding block ends up last, as Flash Heal
  db.rotation = "ghFill"; O.Changed(true)
  O.StepMove(#steps(), 1)
  local last = steps()[#steps()]
  expect(last.spell == "FLASH" and last.how == "fill" and ns.State().weights ~= nil,
    "a Holy Binding block that ends up last becomes Flash Heal, and there is a result (" .. spells() .. ")")
  PS.Reset("ghFill"); db.rotation = "renew"; O.Changed(true)
  -- the same blocks as shipped is not an edit
  O.StepAdd("LESSER"); O.StepRemove(5)
  expect(PS.Kind("renew") == "builtin", "changed and changed back: not an edit")

  -- Copy as new: asks a name, becomes yours and in use
  click(O.controls.psCopy)
  expect(popups[#popups].which == "HOLYMATH_PROFILE_NAME" and popups[#popups].text:find("copy of"), "Copy as new asks for a name")
  popups[#popups].data.done("Renew filler")
  expect(popups[#popups].text:find("already a playstyle"), "a taken name asks again")
  popups[#popups].data.done("My Renew")
  local mine = db.rotation
  expect(PS.Kind(mine) == "mine" and E.ROTATIONS[mine].name == "My Renew", "the copy is yours, in use")
  expect(O.controls.psDelete.shown and O.controls.psRename.shown and O.psStatus.text:find("^Yours"), "yours: Rename and Delete")
  -- its export line, and back in as a new one
  click(O.controls.psExport)
  local ex = popups[#popups]
  expect(ex.which == "HOLYMATH_PLAYSTYLE_EXPORT" and ex.data.line:find("^HM1:My Renew;POM,b,cd,t;"), "Export shows the line: " .. ex.data.line)
  StaticPopupDialogs.HOLYMATH_PLAYSTYLE_EXPORT.OnShow({ editBox = (function()
    local eb = { text = "" }; function eb:SetText(t) self.text = t end; function eb:GetText() return self.text end; return eb end)() }, ex.data)
  click(O.controls.psImport)
  local im = popups[#popups]
  expect(im.which == "HOLYMATH_PLAYSTYLE_IMPORT", "Import asks for a line")
  im.data.done("not a playstyle")
  expect(popups[#popups].which == "HOLYMATH_PLAYSTYLE_IMPORT" and popups[#popups].text:find("HM1:"), "a bad line asks again, saying why")
  popups[#popups].data.done(ex.data.line)
  expect(E.ROTATIONS[db.rotation].name == "My Renew (2)", "the imported one gets a free name: " .. E.ROTATIONS[db.rotation].name)
  local imported = db.rotation
  -- the Settings tab's playstyle menu lists yours under the built-ins
  local m = { radios = {}, titles = {}, buttons = {} }
  local root = {
    CreateRadio = function(_, text, a, b, data) local r = { text = text, data = data }; function r:SetTooltip() end; m.radios[#m.radios + 1] = r; return r end,
    CreateTitle = function(_, t) m.titles[#m.titles + 1] = t; m.radios[#m.radios + 1] = { title = t } end,
    CreateButton = function(_, t, fn) m.buttons[#m.buttons + 1] = { text = t, fn = fn } end,
    CreateDivider = function() end,
  }
  O.controls.rot.gen(O.controls.rot, root)
  local order = {}
  for _, r in ipairs(m.radios) do order[#order + 1] = r.title and ("[" .. r.title .. "]") or (plain(r.text):gsub("  %d+ HPS$", "")) end
  local withHPS = 0
  for _, r in ipairs(m.radios) do if r.text and plain(r.text):find("  %d+ HPS$") then withHPS = withHPS + 1 end end
  expect(withHPS == #m.radios - 1, "each playstyle in the menu with its HPS (" .. withHPS .. ")")
  expect(table.concat(order, "|"):find("Renew filler|%[Yours%]|My Renew|My Renew %(2%)$"), "Settings menu: built-ins, then yours: " .. table.concat(order, "|"))
  expect(m.buttons[1] and m.buttons[1].text:find("playstyles"), "... and a way to the Playstyles tab")
  -- slash commands
  printed = {}
  SlashCmdList.HOLYMATH("playstyle")
  expect(table.concat(printed, "\n"):find("Yours: My Renew"), "/hm playstyle lists them, yours too")
  SlashCmdList.HOLYMATH("playstyle flash heal filler")
  expect(db.rotation == "flashFill", "/hm playstyle <name> uses one")
  SlashCmdList.HOLYMATH("set rot My Renew")
  expect(db.rotation == mine, "/hm set rot takes a name with spaces")
  SlashCmdList.HOLYMATH("playstyle import HM1:Lesser fishing;LESSER,2,20pm,t;RENEW,b,fill")
  expect(E.ROTATIONS[db.rotation].name == "Lesser fishing", "/hm playstyle import")
  local fishing = db.rotation
  -- a new playstyle starts as Prayer of Mending and Renew; Prayer of Mending can't be the filler
  local fresh = PS.New("Fresh")
  expect(db.rotation == fresh and spells() == "POM:cd RENEW:fill", "a new playstyle: Prayer of Mending, then Renew (" .. spells() .. ")")
  O.ShowTab("playstyles")
  expect(not O.controls.psRH.shown, "no shield and no Renewed Hope: Keep Weakened Soul isn't shown")
  UIErrorsFrame = { AddMessage = function(_, msg) errs = errs + 1; O.lastComplaint = msg end }
  O.ShowTab("playstyles")
  click(O.psRows[2].remove)
  expect(spells() == "POM:cd RENEW:fill" and (O.lastComplaint or ""):find("can't fill the rest"),
    "removing Renew is refused: Prayer of Mending has a cooldown, it can't fill the rest")
  PS.Delete(fresh)
  db.rotation = fishing
  -- a profile using yours, then yours deleted: back to the default
  db.profiles = db.profiles or {}
  db.profiles.fish = { settings = E.copy(db.settings), rotation = fishing }
  O.ShowTab("playstyles")
  click(O.controls.psDelete)
  StaticPopupDialogs.HOLYMATH_PLAYSTYLE_DELETE.OnAccept(nil, popups[#popups].data)
  expect(not E.ROTATIONS[fishing] and db.rotation == "renew" and db.profiles.fish.rotation == "renew",
    "deleting yours: you and the profile using it go back to Renew filler")
  db.profiles.fish = nil
  -- saved across a login
  local saved, slash = HolyMathDB, SlashCmdList.HOLYMATH
  HolyMathDB = { PRIEST = E.copy(db) }
  HolyMathDB.PRIEST.rotation = imported
  local ns5 = {}
  for _, f in ipairs({ "Models/PriestData.lua", "Models/GearData.lua", "Models/Priest.lua", "Models/GearSolve.lua", "Models/PriestMath.lua", "Game.lua", "Tooltips.lua", "Core.lua", "Options.lua", "Playstyles.lua", "Gear.lua", "Minimap.lua" }) do
    assert(loadfile(f))("HolyMath", ns5)
  end
  local core5 = frames[#frames]
  core5.scripts.OnEvent(core5, "PLAYER_LOGIN")
  expect(ns5.model.ROTATIONS[imported] and ns5.model.ROTATIONS[imported].name == "My Renew (2)" and HolyMathDB.PRIEST.rotation == imported,
    "your playstyles are there after a login, still in use")
  HolyMathDB, SlashCmdList.HOLYMATH = saved, slash
  ns.Playstyles.Apply()
  -- leave things as they were
  for k in pairs(db.playstyles.custom) do PS.Delete(k) end
  db.rotation = "renew"
  O.ShowTab("settings")
  StaticPopupDialogs, StaticPopup_Show, StaticPopup_Hide, UIErrorsFrame, GetCursorInfo, ClearCursor = nil, nil, nil, nil, nil, nil
  expect(err() == nil, "no errors on the Playstyles tab at all (" .. tostring(err()) .. ")")
  local others = {}
  for _, k in ipairs({ "math", "rebuild", "plans", "mix", "spellTable", "bestPotions" }) do
    if ns.errors[k] then others[#others + 1] = k .. ": " .. tostring(ns.errors[k].last) end
  end
  expect(#others == 0, "... nor anywhere else in the window while editing (" .. table.concat(others, "; ") .. ")")
  O.frame:Hide()
end

-- People reached by group heals: a slider on the Settings tab and /hm set group
do
  local O, db = ns.Options, HolyMathDB.PRIEST
  expect(O.controls.group and O.controls.group.Init and (db.settings.groupHits or 5) == 5, "a slider for people reached by group heals, 5 to start")
  db.rotation = "pohFill"; ns.MarkDirty()
  local h5 = ns.State().weights.base.ehps
  SlashCmdList.HOLYMATH("set group 2")
  local h2 = ns.State().weights.base.ehps
  expect(db.settings.groupHits == 2 and h2 < h5, string.format("/hm set group 2: Prayer of Healing filler heals less (%.0f -> %.0f)", h5, h2))
  SlashCmdList.HOLYMATH("set group 9")
  expect(db.settings.groupHits == 2, "... and only takes 1 to 5")
  O.controls.group:SetValue(4)
  expect(db.settings.groupHits == 4, "the slider sets it")
  db.settings.groupHits = 5; db.rotation = "renew"; ns.MarkDirty()
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
  for _, f in ipairs({ "Models/PriestData.lua", "Models/GearData.lua", "Models/Priest.lua", "Models/GearSolve.lua", "Models/PriestMath.lua", "Game.lua", "Tooltips.lua", "Core.lua", "Options.lua", "Playstyles.lua", "Gear.lua", "Minimap.lua" }) do
    assert(loadfile(f))("HolyMath", ns3)
  end
  local core3 = frames[#frames]
  core3.scripts.OnEvent(core3, "PLAYER_LOGIN")
  local O = ns3.Options
  SlashCmdList.HOLYMATH("")
  expect(O.frame and O.frame:IsShown(), "fallback window opens")
  O.controls["fight+"].scripts.OnClick(O.controls["fight+"])
  expect(HolyMathDB.PRIEST.settings.fightLength == 150, "fallback + button raises the fight length")
  O.controls.rot.scripts.OnClick(O.controls.rot)
  local it = O.controls["rot:1"]
  it.scripts.OnClick(it)
  expect(HolyMathDB.PRIEST.rotation == it.key, "dropdown works without the game's art too")
  O.controls.insp.scripts.OnClick(O.controls.insp)
  expect(HolyMathDB.PRIEST.settings.includeInspiration == false, "fallback toggle turns Inspiration off")
  expect(O.hps.text and O.hps.text:find("HPS"), "fallback window shows the result")
  O.ShowTab("playstyles")
  expect(O.psShown and O.psShown > 0 and not (ns3.errors.playstyles), "fallback Playstyles tab fills (" ..
    tostring(ns3.errors.playstyles and ns3.errors.playstyles.last) .. ")")
  local hb = O.psRows[1].how
  local was = ns3.Playstyles.Def(HolyMathDB.PRIEST.rotation).steps[1].how
  hb.scripts.OnClick(hb, "LeftButton")
  expect(ns3.Playstyles.Def(HolyMathDB.PRIEST.rotation).steps[1].how ~= was, "fallback: a plain button steps through how often")
  ns3.Playstyles.Reset(HolyMathDB.PRIEST.rotation)
  O.ShowTab("settings")
  O.controls.Defaults.scripts.OnClick(O.controls.Defaults)
  missingTemplates = {}
end

-- default fight length 120 s; a saved 300 s (the old default) moves to 120 once
do
  local function login(db)
    HolyMathDB = { PRIEST = db }
    local ns4 = {}
    for _, f in ipairs({ "Models/PriestData.lua", "Models/GearData.lua", "Models/Priest.lua", "Models/GearSolve.lua", "Models/PriestMath.lua", "Game.lua", "Tooltips.lua", "Core.lua", "Options.lua", "Playstyles.lua", "Gear.lua", "Minimap.lua" }) do
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

-- The Gear tab: the best for you at your level, a row per slot (KeystoneLoot's look)
do
  local O, D = ns.Options, ns.GearData
  UnitFactionGroup = function() return "Horde" end
  if not O.frame or not O.frame:IsShown() then O.Toggle() end
  O.ShowTab("gear")
  local r = O.gearResult
  expect(r and r.hps > 0 and not O.gearWorking, "Gear tab: worked out on open (" .. tostring(r and r.hps) .. " HPS, " .. tostring(r and r.runs) .. " runs)")
  expect(O.frame.width == 880, "Gear tab: the wide window")
  local function rowNamed(n) for _, row in ipairs(O.gearRows) do if row.def.name == n then return row end end end
  expect(#O.gearRows == 16, "16 rows: rings and trinkets one row each, the weapons three (" .. #O.gearRows .. ")")
  local two, main, off = rowNamed("Two-hand"), rowNamed("Main hand"), rowNamed("Off hand")
  local wv = r.weapons
  expect(two.icons[1].item == wv.twohand.item and main.icons[1].item == wv.onehand.item and off.icons[1].item == wv.onehand.offhand,
    "the weapons both ways: the best two-hander, main hand and off hand")
  two.icons[1].scripts.OnEnter(two.icons[1])
  local wtip = table.concat(GameTooltip.lines, " | ")
  expect(wtip:find("HPS with it") and wtip:find("a main hand and off hand"), "hover a weapon: what each way heals (" .. wtip .. ")")
  expect(two.icons[2].item and two.icons[2].item.slot == "twohand" and main.icons[2].item.slot == "mainhand"
    and off.icons[2].item.slot == "offhand", "next best: two-handers, main hands and off hands apart")
  expect(O.gearNote.text:find("Level 60, Horde") and not O.gearNote.text:find("HPS"),
    "under the list: your level and side, no HPS (" .. tostring(O.gearNote.text) .. ")")
  expect(O.gearPlaystyle and O.gearPlaystyle.closedText == "Renew filler", "a playstyle dropdown on the tab, showing yours")
  -- change the playstyle right after a list was worked out: the new list comes at once (not after 10 s)
  local realTime = GetTime
  GetTime = function() return 1000 end
  O.gearKey = nil; O.FillGear()
  local before = O.gearResult
  HolyMathDB.PRIEST.rotation = "flashFill"; O.Changed(true)
  expect(O.gearResult ~= before and O.gearResult.playstyle == "Flash Heal filler" and O.gearPlaystyle.closedText == "Flash Heal filler",
    "another playstyle: its list at once (" .. tostring(O.gearResult.playstyle) .. ")")
  -- a buff change only (same choices): the list waits up to 10 s, and keeps showing meanwhile
  local kept, realAfter2 = O.gearResult, C_Timer.After
  local later = {}
  C_Timer.After = function(_, fn) later[#later + 1] = fn end
  ns.MarkDirty(); O.FillGear()
  expect(O.gearResult == kept and #later == 1, "a buff change only: the list stays for now")
  later[1]()
  expect(O.gearResult ~= kept, "... and is worked out again when its 10 s are up")
  C_Timer.After = realAfter2
  HolyMathDB.PRIEST.rotation = "renew"; O.Changed(true)
  GetTime = realTime
  O.gearKey = nil; O.FillGear()
  r = O.gearResult
  local chest = rowNamed("Chest")
  local best = r.items.chest
  expect(chest.shown and chest.name.text == "Chest" and chest.icons[1].item == best and not chest.icons[1].glow,
    "the chest row: just the slot, then the best for you first, no glow (" .. best.name .. ")")
  local n = 0
  for i = 2, #chest.icons do if chest.icons[i].item then n = n + 1 end end
  expect(#chest.icons == 7 and n == 6, "then six next best (" .. n .. ")")
  local rings = rowNamed("Rings")
  expect(rings.icons[1].item == r.items.finger1 and rings.icons[2].item == r.items.finger2 and rings.icons[3].item,
    "rings: the two best, then the next best")
  -- a tick on what you have
  ownedItems = { [best.id] = true }
  O.FillGear()
  expect(chest.icons[1].tick.shown, "a tick on what you have")
  chest.icons[1].scripts.OnEnter(chest.icons[1])
  local tip = table.concat(GameTooltip.lines, " | ")
  expect(tip:find("item:" .. best.id, 1, true) and tip:find("best for you") and tip:find("You have it")
    and tip:find("Right%-click: a Wowhead link"), "hover: the game's item tooltip, then what it's worth (" .. tip .. ")")
  -- a random-suffix item ("of Healing"): the game shows the plain item here, so the tooltip says which version
  local sfx
  for _, row in ipairs(O.gearRows) do for _, b in ipairs(row.icons) do if b.item and b.item.suffix ~= "" and not sfx then sfx = b end end end
  if sfx then
    -- the suffix goes in the link as a bonus ID (Forever's random suffixes are bonus lists)
    local str = O.GearItemString(sfx.item)
    local sid = sfx.item.key:match(":(%d+)$")
    expect(str == "item:" .. sfx.item.id .. string.rep(":", 12) .. "1:" .. sid, "a suffix item's link carries its bonus ID (" .. str .. ")")
    expect(O.GearLink(sfx.item):find("[" .. sfx.item.name .. "]", 1, true), "... and its chat link the name with the suffix")
    sfx.scripts.OnEnter(sfx)
    local t2 = table.concat(GameTooltip.lines, " | ")
    expect(t2:find("This is the \"" .. sfx.item.suffix .. "\" version", 1, true) and t2:find("over what you wear")
      and GameTooltip.hmGearTip, "a random-suffix item: which version, and what it's worth (" .. t2 .. ")")
    sfx.scripts.OnLeave(sfx)
    expect(not GameTooltip.hmGearTip, "... and the item tooltips' own line is back after")
  end
  local linked
  IsModifiedClick = function(what) return what == "CHATLINK" end
  GetItemInfo = function(id) return "Name", "|Hitem:" .. id .. "|h[Name]|h", 4 end
  ChatEdit_InsertLink = function(l) linked = l end
  chest.icons[1].scripts.OnClick(chest.icons[1], "LeftButton")
  expect(linked and linked:find("item:" .. best.id, 1, true), "shift-click links the item in chat")
  -- not loaded yet, chat closed: a link made the game's way, and chat opens with it
  local opened
  GetItemInfo = function() return nil end
  ChatEdit_InsertLink = function() return false end
  ChatFrame_OpenChat = function(text) opened = text end
  chest.icons[1].scripts.OnClick(chest.icons[1], "LeftButton")
  expect(opened and opened:find("|Hitem:" .. best.id .. ":", 1, true) and opened:find("[" .. best.name .. "]", 1, true),
    "shift-click, item not loaded, chat closed: chat opens with the link (" .. tostring(opened) .. ")")
  IsModifiedClick, GetItemInfo, ChatEdit_InsertLink, ChatFrame_OpenChat = nil, nil, nil, nil
  -- green arrows: every shown item that beats what you wear in its slot, and only those
  local arrows, wrong = 0, 0
  for _, row in ipairs(O.gearRows) do
    for _, b in ipairs(row.icons) do
      if b.item then
        local g = r.gains[b.item.key]
        local should = g and not g.worn and g.d > 0.05
        if (b.up.shown and true or false) ~= (should and true or false) then wrong = wrong + 1 end
        if b.up.shown then arrows = arrows + 1 end
      end
    end
  end
  expect(arrows > 0 and wrong == 0, "green arrows on the items that beat what you wear (" .. arrows .. ", " .. wrong .. " wrong)")
  -- what you wear: a gold tick, no arrow, "You wear it."
  local realID, realLink = GetInventoryItemID, GetInventoryItemLink
  GetInventoryItemID = function(_, slot) if slot == 5 then return best.id end end
  GetInventoryItemLink = function(_, slot)
    if slot == 5 then return "|cffa335ee|H" .. O.GearItemString(best) .. "|h[" .. best.name .. "]|h|r" end
    return realLink(_, slot)
  end
  O.gearKey = nil; O.FillGear()
  local worn = rowNamed("Chest").icons
  local wb
  for _, b in ipairs(worn) do if b.item and b.item.id == best.id then wb = b end end
  wb.scripts.OnEnter(wb)
  expect(wb.tick.shown and not wb.up.shown and table.concat(GameTooltip.lines, " "):find("You wear it"),
    "what you wear: ticked, no arrow, and it says so (" .. tostring(wb.tick.shown) .. " " .. tostring(wb.up.shown) .. " " .. table.concat(GameTooltip.lines, " / ") .. ")")
  GetInventoryItemID, GetInventoryItemLink = realID, realLink
  O.gearKey = nil; O.FillGear()
  r = O.gearResult
  -- a trinket with an effect: the effect in words, and that it's counted
  local fxb
  for _, row in ipairs(O.gearRows) do for _, b in ipairs(row.icons) do if b.item and b.item.fx and not fxb then fxb = b end end end
  expect(fxb, "an item with a use or proc effect is on the tab (" .. tostring(fxb and fxb.item.name) .. ")")
  if fxb then
    fxb.scripts.OnEnter(fxb)
    local t3 = table.concat(GameTooltip.lines, " | ")
    expect(t3:find("Counted on average over your fight") and (t3:find("Use: ") or t3:find("chance on a heal") or t3:find("Each ")),
      "its tooltip says what the effect does and that it's counted (" .. t3 .. ")")
  end
  -- what you wear is matched with its random suffix: another suffix of the same item isn't "worn"
  local sfxItem
  for _, it in ipairs(D.items) do if it.suffix ~= "" then sfxItem = it; break end end
  local sid = sfxItem.key:match(":(%d+)$")
  expect(O.LinkKey("|cff1eff00|Hitem:" .. sfxItem.id .. string.rep(":", 12) .. "1:" .. sid .. "|h[x]|h|r") == sfxItem.key
    and O.LinkKey("|Hitem:" .. sfxItem.id .. string.rep(":", 12) .. "1:999999|h[x]|h") == tostring(sfxItem.id),
    "a worn item's link gives its key with the suffix (" .. sfxItem.key .. ")")
  -- the items shown are asked for once each, and an open tooltip is drawn again when its item's data comes in
  local asked = {}
  C_Item.RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end
  O.gearAsked = nil; O.FillGear()
  expect(#asked > 30, "the shown items are asked for (" .. #asked .. ")")
  local n0 = #asked
  O.FillGear()
  expect(#asked == n0, "... once each")
  C_Item.RequestLoadItemDataByID = nil
  chest.icons[1].scripts.OnEnter(chest.icons[1])
  GameTooltip.lines = {}
  for _, f in ipairs(frames) do
    if f.events and f.events.GET_ITEM_INFO_RECEIVED and f.scripts.OnEvent then
      f.scripts.OnEvent(f, "GET_ITEM_INFO_RECEIVED", chest.icons[1].item.id)
    end
  end
  expect(table.concat(GameTooltip.lines, " "):find("Holy Math"), "an item's data comes in while hovered: its tooltip again, with our lines")
  chest.icons[1].scripts.OnLeave(chest.icons[1])
  -- the game draws a Gear tab tooltip again (its item's data arrived): the item tooltips' hook puts our lines back
  chest.icons[1].scripts.OnEnter(chest.icons[1])
  GameTooltip.lines = { "item:" .. chest.icons[1].item.id }
  GameTooltip.fakeLink = "|Hitem:" .. chest.icons[1].item.id .. ":0:|h"
  postCalls[0](GameTooltip)
  local redrawn = table.concat(GameTooltip.lines, " | ")
  expect(redrawn:find("Holy Math: best for you") and not redrawn:find("Holy Math: [%+%-]%d"),
    "the game draws it again: the Gear lines come back, not the bag tooltips' line (" .. redrawn .. ")")
  chest.icons[1].scripts.OnLeave(chest.icons[1])
  expect(not GameTooltip.hmGearTip and not GameTooltip.hmGearItem, "... and the mark is gone when you leave")
  -- a whole set swapped (one event a slot): worked out once, a moment later
  do
    local q, realAfter3 = {}, C_Timer.After
    C_Timer.After = function(_, fn) q[#q + 1] = fn end
    local solves = 0
    local realSolve = ns.GearSolve.Solve
    ns.GearSolve.Solve = function(...) solves = solves + 1; return realSolve(...) end
    for _, f in ipairs(frames) do
      if f.events and f.events.PLAYER_EQUIPMENT_CHANGED and f.events.GET_ITEM_INFO_RECEIVED and f.scripts.OnEvent then
        for _ = 1, 5 do f.scripts.OnEvent(f, "PLAYER_EQUIPMENT_CHANGED", 5) end
      end
    end
    expect(solves == 0 and #q >= 1, "a set swapped: nothing worked out yet (" .. solves .. " runs, " .. #q .. " waiting)")
    local first = q[1]
    q = {}
    first()
    for _ = 1, 50 do local w = q; q = {}; for _, fn in ipairs(w) do fn() end; if #q == 0 then break end end
    expect(solves == 1 and not O.gearWorking, "... then once (" .. solves .. ")")
    ns.GearSolve.Solve, C_Timer.After = realSolve, realAfter3
  end
  -- right-click: a Wowhead link to copy
  local shown
  StaticPopupDialogs = {}
  StaticPopup_Show = function(which, text, _, data) shown = { which = which, text = text, data = data } end
  chest.icons[1].scripts.OnClick(chest.icons[1], "RightButton")
  expect(shown and shown.which == "HOLYMATH_WOWHEAD" and shown.data.url == "https://www.wowhead.com/forever/item=" .. best.id
    and shown.text:find("Ctrl%+C"), "right-click: the item's Wowhead link to copy")
  StaticPopupDialogs, StaticPopup_Show = nil, nil
  -- the same state is not worked out twice; the list or your side is
  local same = O.gearResult
  O.FillGear()
  expect(O.gearResult == same, "no new work while nothing changed")
  HolyMathDB.gear.pvp = true; O.gearKey = nil; O.FillGear()
  expect(O.gearResult ~= same and O.gearResult.hps >= same.hps - 1e-6, "with PvP gear: worked out again, at least as good")
  UnitFactionGroup = function() return "Alliance" end
  O.FillGear()
  local allianceOnly = true
  for _, x in pairs(O.gearResult.items) do if not x.A then allianceOnly = false end end
  expect(O.gearNote.text:find("Alliance") and allianceOnly, "Alliance: its own list, only what the Alliance can get")
  -- in the game: a few milliseconds a frame (a fake clock, timers run when we say)
  local clock, queue = 0, {}
  local realAfter = C_Timer.After
  debugprofilestop = function() clock = clock + 3; return clock end
  C_Timer.After = function(_, fn) queue[#queue + 1] = fn end
  local function frames(n) for _ = 1, n do local q = queue; queue = {}; for _, fn in ipairs(q) do fn() end end end
  HolyMathDB.gear.pvp = nil; O.gearKey = nil; O.gearResult = nil
  O.FillGear()
  expect(O.gearWorking and #queue == 1 and O.gearNote.text:find("Working out"), "in game: it starts, and carries on next frame")
  frames(3)
  expect(O.gearWorking, "... still working a few frames on (it pauses every 10 ms)")
  -- something changes half way: the old work stops, the new one finishes
  HolyMathDB.gear.pvp = true; O.gearKey = nil; O.FillGear()
  local steps = 0
  while O.gearWorking and steps < 2000 do frames(1); steps = steps + 1 end
  expect(not O.gearWorking and O.gearResult and O.gearKey:find("pvp") and #queue == 0,
    "... the newer work finishes (" .. steps .. " frames), the older one stopped")
  -- the window closes half way: the work stops, and starts again when the tab is back
  HolyMathDB.gear.pvp = nil; O.gearKey = nil; O.FillGear()
  frames(2)
  O.frame:Hide()
  frames(3)
  expect(not O.gearWorking and #queue == 0 and O.gearKey == nil, "closing the window stops the work")
  O.frame:Show(); O.ShowTab("gear")
  local steps2 = 0
  while O.gearWorking and steps2 < 2000 do frames(1); steps2 = steps2 + 1 end
  expect(not O.gearWorking and O.gearResult and O.gearKey and O.gearKey:find("^pve|"), "... and it's done again when you come back (" .. tostring(O.gearKey) .. ")")
  debugprofilestop, C_Timer.After = nil, realAfter
  HolyMathDB.gear = nil
  UnitFactionGroup = function() return "Horde" end
  ownedItems = {}
  expect(not (ns.errors and ns.errors.gear), "no errors on the Gear tab (" .. tostring(ns.errors and ns.errors.gear and ns.errors.gear.last) .. ")")
  O.ShowTab("settings")
  O.frame:Hide()
end

-- The minimap button: click opens the window, right-click the Gear tab; a setting hides it
do
  local O = ns.Options
  local b = ns.Minimap and ns.Minimap.button
  expect(b and b.shown and b.icon.texture:find("Renew"), "a minimap button at login, with Holy Math's icon")
  if O.frame and O.frame:IsShown() then O.frame:Hide() end
  b.scripts.OnClick(b, "LeftButton")
  expect(O.frame:IsShown(), "click: the window opens")
  b.scripts.OnClick(b, "LeftButton")
  expect(not O.frame:IsShown(), "click again: it closes")
  b.scripts.OnClick(b, "RightButton")
  expect(O.frame:IsShown() and O.tab == "gear", "right-click: the window at the Gear tab")
  O.ShowTab("settings")
  local c = O.controls.minimap
  expect(c and c.checked == true, "Settings: Show the minimap button, on")
  c:SetChecked(false); c.scripts.OnClick(c)
  expect(not b.shown and HolyMathDB.minimap.hide == true, "unticked: the button hides, and stays hidden (saved)")
  c:SetChecked(true); c.scripts.OnClick(c)
  expect(b.shown and not HolyMathDB.minimap.hide, "ticked again: it's back")
  b.scripts.OnEnter(b)
  expect(table.concat(GameTooltip.lines, " "):find("Right%-click"), "hover: what clicking does")
  O.frame:Hide()
end

-- a class with no model yet (warrior): loads without errors and stays quiet
do
  UnitClass = function() return "Warrior", "WARRIOR" end
  local ns2 = {}
  for _, f in ipairs({ "Models/PriestData.lua", "Models/GearData.lua", "Models/Priest.lua", "Models/GearSolve.lua", "Models/PriestMath.lua", "Game.lua", "Tooltips.lua", "Core.lua", "Options.lua", "Playstyles.lua", "Gear.lua", "Minimap.lua" }) do assert(loadfile(f))("HolyMath", ns2) end
  local core2 = frames[#frames]
  core2.scripts.OnEvent(core2, "PLAYER_LOGIN")
  expect(not ns2.enabled, "warrior: addon stays off")
  expect(ns2.GearData == nil or ns2.GearData.items == nil, "warrior: the gear data isn't unpacked")
  printed = {}
  SlashCmdList.HOLYMATH("")
  expect(table.concat(printed, " "):find("made for priests"), "warrior: /hm says it is made for priests")
end

realprint(fails == 0 and "\nsmoke test passed" or ("\n" .. fails .. " smoke failures"))
os.exit(fails == 0 and 0 or 1)
