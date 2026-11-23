--[[ Holy Math - Gear.lua
     The Gear tab: the best gear for you at your level, worked out in game by
     Models/GearSolve.lua: your live character (level, talents, race, buffs,
     playstyle, every setting) with your gear swapped for the items in
     Models/GearData.lua (out now in WoW: Forever, your faction). At level 60 it is
     the best in slot. Laid out like KeystoneLoot's loot window, with a row per
     slot instead of per dungeon:

       List [ Without PvP gear  v ]   At level 51, Renew filler: 737 HPS with this gear, +94 over what you wear
                                      Sets: Vestments of the Virtuous 4 (8 MP5, 5% a cast: 200 mana)
       +--------------------------------------------------------------------------+
       | [slot] Head       [best]  [2nd][3rd][4th][5th] | [slot] Legs   ...        |
       | [slot] Rings      [best][best]  [3rd]...       |                          |
       +--------------------------------------------------------------------------+

     The first icon is the best for you; rings and trinkets have two. The rest are the next best, by your stat weights with that gear on. A
     tick: you have the item (worn, in your bags or bank). The work runs a few
     milliseconds a frame, and again only when something it depends on changes.
]]--

local ADDON, ns = ...
local O = ns.Options
local U

local W = 836                         -- the tab's width inside the margins
local GAP = 12
local COL_W = math.floor((W - GAP) / 2)
local ROW_H, ICON, SLOT_ICON = 44, 34, 28
local LABEL_W = 78
local ROWS_TOP = -122
local ICONS = 7                       -- per row: the best, then the next best
local ICON_STEP = ICON + 5
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local EMPTY = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local TICK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"

-- one row per slot (rings and trinkets: one row each, two best), two columns
local ROWS = {
  { name = "Head", slots = { "head" }, inv = "HeadSlot" },
  { name = "Neck", slots = { "neck" }, inv = "NeckSlot" },
  { name = "Shoulders", slots = { "shoulder" }, inv = "ShoulderSlot" },
  { name = "Back", slots = { "back" }, inv = "BackSlot" },
  { name = "Chest", slots = { "chest" }, inv = "ChestSlot" },
  { name = "Wrist", slots = { "wrist" }, inv = "WristSlot" },
  { name = "Hands", slots = { "hands" }, inv = "HandsSlot" },
  { name = "Waist", slots = { "waist" }, inv = "WaistSlot" },
  { name = "Legs", slots = { "legs" }, inv = "LegsSlot" },
  { name = "Feet", slots = { "feet" }, inv = "FeetSlot" },
  { name = "Rings", slots = { "finger1", "finger2" }, inv = "Finger0Slot" },
  { name = "Trinkets", slots = { "trinket1", "trinket2" }, inv = "Trinket0Slot" },
  -- the weapons both ways (a two-hander, or a main hand and an off hand)
  { name = "Two-hand", weapon = "twohand", inv = "MainHandSlot" },
  { name = "Main hand", weapon = "mainhand", inv = "MainHandSlot" },
  { name = "Off hand", weapon = "offhand", inv = "SecondaryHandSlot" },
  { name = "Wand", slots = { "wand" }, inv = "RangedSlot" },
}
local PER_COL = 8
local SLOT_TEXTURE = { HeadSlot = "Head", NeckSlot = "Neck", ShoulderSlot = "Shoulder", BackSlot = "Chest",
  ChestSlot = "Chest", WristSlot = "Wrists", HandsSlot = "Hands", WaistSlot = "Waist", LegsSlot = "Legs",
  FeetSlot = "Feet", Finger0Slot = "Finger", Trinket0Slot = "Trinket", MainHandSlot = "MainHand",
  SecondaryHandSlot = "SecondaryHand", RangedSlot = "Ranged" }
-- the character window's slot ids, for what you are wearing
local INV_IDS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
local G = ns.Game
local QUALITY = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }

local function data() return ns.GearData end
local function settings()
  HolyMathDB.gear = type(HolyMathDB.gear) == "table" and HolyMathDB.gear or {}
  return HolyMathDB.gear
end

-- Alliance or Horde: the list and the sources for your side
function O.GearSide()
  local f = UnitFactionGroup and UnitFactionGroup("player")
  return f == "Alliance" and "A" or "H"
end

local function GS() return ns.GearSolve end

-- An item link's key in the item data: "id", or "id:suffix" when its first bonus ID is a
-- random suffix the data knows (the link's 13th field is how many bonus IDs follow).
function O.LinkKey(link)
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
function ns.GearEffectsFor(link, S)
  local D, solver = ns.GearData, ns.GearSolve
  if not (D and solver and S and S.weights and S.weights.base) then return nil end
  local key = O.LinkKey(link)
  local it = key and D.byKey and (D.byKey[key] or D.byKey[key:match("^(%d+)")])
  if not (it and it.fx) then return nil end
  local r, set = S.weights.base, S.input.settings
  local ctx = { fl = set.fightLength, casts = {}, oh = set.overheal and set.overheal.FLASH or 0, pull = set.pullEvery }
  local total = (r.fiveSecondCasts or 0) + (r.innerFocus and r.innerFocus.casts or 0)
  for _, s in ipairs(r.steps or {}) do
    ctx.casts[s.key] = (ctx.casts[s.key] or 0) + s.casts + (s.pauseCasts or 0)
    total = total + s.casts
  end
  ctx.cps = total / math.max(1, set.fightLength)
  return solver.Effects(it, ctx)
end

-- Which professions you have (items only one profession can use count only then).
-- The names are the game's, so in another language none match: those items stay out.
local PROFS = { Tailoring = true, Leatherworking = true, Enchanting = true, Blacksmithing = true, Engineering = true,
  Alchemy = true, Herbalism = true, Mining = true, Skinning = true }
function O.GearProfessions()
  local have = {}
  if GetNumSkillLines and GetSkillLineInfo then
    for i = 1, GetNumSkillLines() do
      local name = GetSkillLineInfo(i)
      if name and PROFS[name] then have[name] = true end
    end
  end
  if GetProfessions and GetProfessionInfo then
    for _, i in pairs({ GetProfessions() }) do
      local name = i and GetProfessionInfo(i)
      if name and PROFS[name] then have[name] = true end
    end
  end
  return have
end

local function itemIcon(id)
  local tex = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
  if not tex and GetItemIcon then tex = GetItemIcon(id) end
  return tex or QUESTION
end

local function slotIcon(inv)
  if GetInventorySlotInfo then
    local ok, _, tex = pcall(GetInventorySlotInfo, inv)
    if ok and tex then return tex end
  end
  return "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. (SLOT_TEXTURE[inv] or "Chest")
end

-- you have it: worn, or in your bags or bank (the game counts the bank it last saw)
function O.GearOwned(id)
  if GetInventoryItemID then
    for _, slot in ipairs(INV_IDS) do if GetInventoryItemID("player", slot) == id then return true end end
  end
  local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id, true)) or (GetItemCount and GetItemCount(id, true))
  return (count or 0) > 0
end

local function colored(it)
  return "|cff" .. (QUALITY[it.q] or "ffffff") .. it.name .. "|r"
end

local function statLine(it)
  local s, p = it.stats, {}
  if s.healing then p[#p + 1] = "+" .. s.healing .. " healing" end
  if s.int then p[#p + 1] = "+" .. s.int .. " intellect" end
  if s.spirit then p[#p + 1] = "+" .. s.spirit .. " spirit" end
  if s.mp5 then p[#p + 1] = s.mp5 .. " MP5" end
  if s.critR then p[#p + 1] = string.format("+%g%% crit", s.critR / 14) end
  return table.concat(p, ", ")
end


-- The game's item tooltip, then what it's worth to you and its set (where to get it:
-- its Wowhead page, right-click).
-- An item's link string. In Forever a random suffix ("of Healing") is one of the
-- item's bonus lists (wowsims: "its ID is the bonus list's"), so it goes in the
-- link's bonus IDs: item:id, then enchant, 4 gems, suffix, unique id, link level,
-- specialization, modifiers, context (11 fields), then 1 bonus ID.
local function itemString(it)
  local sid = tonumber(it.key:match(":(%d+)$"))
  if not sid then return "item:" .. it.id end
  return "item:" .. it.id .. string.rep(":", 12) .. "1:" .. sid
end
O.GearItemString = itemString

-- The game's tooltip for the item: with its random suffix ("of Healing") when the game
-- shows it (its title then says so), else the plain item. true, and whether the
-- suffix is in it.
local function showItem(it)
  local sid = tonumber(it.key:match(":(%d+)$"))
  local tries = { itemString(it) }
  if sid then
    -- older ways of writing a suffix, in case a client wants one of them
    tries[#tries + 1] = "item:" .. it.id .. ":0:0:0:0:0:-" .. sid
    tries[#tries + 1] = "item:" .. it.id
  end
  if not GameTooltip.SetHyperlink then return false end
  for i, link in ipairs(tries) do
    GameTooltip.hmGearAdded = nil
    if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
      if not sid then return true, false end
      local first = _G.GameTooltipTextLeft1 and _G.GameTooltipTextLeft1.GetText and _G.GameTooltipTextLeft1:GetText()
      if first and first:find(it.suffix, 1, true) then return true, true end
      if i == #tries then return true, false end
    end
  end
  return false
end

-- the slots an item would replace (character window ids); both for a two-hander
local REPLACES = { head = { 1 }, neck = { 2 }, shoulder = { 3 }, back = { 15 }, chest = { 5 }, wrist = { 9 },
  hands = { 10 }, waist = { 6 }, legs = { 7 }, feet = { 8 }, finger = { 11, 12 }, trinket = { 13, 14 },
  mainhand = { 16 }, offhand = { 17 }, twohand = { 16, 17, both = true }, wand = { 18 } }
-- What the item (this version of it) is worth to you over what you wear: the whole
-- model, as the item tooltips do; a ring or trinket against the one it beats most.
local function gainText(it)
  -- worked out with the list (the same number as its green arrow)
  local r = O.gearResult
  local g = r and r.gains and r.gains[it.key]
  if g then
    if g.pair then return "You wear a two-hander: this counts only with the other hand (the weapon rows).", 0.6, 0.6, 0.6 end
    if g.worn then return "You wear it.", 0.6, 0.6, 0.6 end
    local up = g.d >= 0
    return string.format("%s%.1f HPS (%s%.1f%%) over what you wear", up and "+" or "", g.d, up and "+" or "",
      g.d / math.max(1, r.now) * 100), up and 0.25 or 1, up and 1 or 0.31, up and 0.25 or 0.31
  end
  local S, solver = ns.State and ns.State(), ns.GearSolve
  if not (S and S.weights and solver and G and ns.model) then return nil end
  local new = solver.Stats(it)
  local slots = REPLACES[it.slot] or {}
  local options = slots.both and { { 16, 17 } } or {}
  if not slots.both then for _, s in ipairs(slots) do options[#options + 1] = { s } end end
  local best
  for _, opt in ipairs(options) do
    local diff, wearing = {}, false
    for k, v in pairs(new) do diff[k] = v end
    for _, inv in ipairs(opt) do
      local ok, st = pcall(G.EquippedStats, inv)
      if ok and type(st) == "table" then for k in pairs(diff) do diff[k] = diff[k] - (st[k] or 0) end end
      if GetInventoryItemID and GetInventoryItemID("player", inv) == it.id then wearing = true end
    end
    local ok, d, pct = pcall(ns.model.Compare, S.rotation, S.st, S.input, diff)
    if ok and d and (not best or d > best.d) then best = { d = d, pct = pct, wearing = wearing } end
  end
  if not best then return nil end
  if best.wearing and math.abs(best.d) < 0.05 then return "You wear it.", 0.6, 0.6, 0.6 end
  local up = best.d >= 0
  return string.format("%s%.1f HPS (%s%.1f%%) over what you wear", up and "+" or "", best.d, up and "+" or "", (best.pct or 0) * 100),
    up and 0.25 or 1, up and 1 or 0.31, up and 0.25 or 0.31
end

-- The Holy Math lines under an item's tooltip on this tab (tt.hmGearItem: which item).
-- Added by the item tooltips' own hook (Tooltips.lua) each time the game draws the
-- tooltip, so they come back when it draws it again (an item's data arriving), or
-- here when no hook did.
function O.GearTipLines(tt)
  local g = tt and tt.hmGearItem
  local it, extra = g and g.it, g and g.extra
  if not it then return end
  tt.hmGearAdded = true
  local D = data()
  -- did the game show the random suffix (its title says so)?
  local title = tt.GetName and _G[(tt:GetName() or "") .. "TextLeft1"]
  local first = title and title.GetText and title:GetText()
  local withSuffix = first and it.suffix ~= "" and first:find(it.suffix, 1, true)
  tt:AddLine(" ")
  tt:AddLine("Holy Math" .. (extra and extra.head and (": " .. extra.head) or ""), 1, 0.82, 0)
  if it.suffix and it.suffix ~= "" and not withSuffix then
    -- a random-suffix item the game showed plain: the list means this suffix
    tt:AddLine("This is the \"" .. it.suffix .. "\" version: " .. statLine(it), 1, 1, 1, true)
  end
  local gain, r, gg, b = gainText(it)
  if gain then tt:AddLine(gain, r, gg, b) end
  if it.set ~= 0 and it.setName ~= "" then
    local bonus = {}
    local texts = D and D.sets[it.set] or {}
    local ks = {}
    for k in pairs(texts) do ks[#ks + 1] = k end
    table.sort(ks)
    for _, k in ipairs(ks) do bonus[#bonus + 1] = "(" .. k .. ") " .. texts[k].text end
    tt:AddLine("Set: " .. it.setName .. (#bonus > 0 and (": " .. table.concat(bonus, ", ")) or ""), 0.25, 1, 0.25, true)
  end
  if it.prof ~= "" then
    local have = O.GearProfessions()[it.prof]
    tt:AddLine("Only " .. it.prof .. " can use it" .. (have and " (you can)." or ", so it doesn't count for you."),
      1, 0.5, 0.25, true)
  end
  if it.fx then
    for _, f in ipairs(it.fx) do tt:AddLine(O.GearEffectText(f), 0.25, 1, 0.25, true) end
    tt:AddLine("Counted on average over your fight.", 0.6, 0.6, 0.6, true)
  elseif it.use then
    tt:AddLine("Its effect isn't counted (it doesn't heal or give mana).", 0.6, 0.6, 0.6, true)
  end
  if O.GearOwned(it.id) then tt:AddLine("You have it.", 0.25, 1, 0.25) end
  if extra and extra.note then tt:AddLine(extra.note, 0.6, 0.6, 0.6, true) end
  tt:AddLine("Right-click: a Wowhead link (where to get it).", 0.6, 0.6, 0.6)
end

local function itemTip(owner, it, extra)
  if not (GameTooltip and it) then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip.hmGearTip = true
  GameTooltip.hmGearItem = { it = it, extra = extra }
  local shown = showItem(it)
  if not shown then GameTooltip:SetText(colored(it)) end
  if not GameTooltip.hmGearAdded then O.GearTipLines(GameTooltip) end
  GameTooltip:Show()
end

-- Shift-click: the item's link into chat. The game's link when it has the item loaded,
-- else one made the game's way (its plain name, in its quality colour); into the chat
-- box if one is open, else chat opens with it.
function O.GearLink(it)
  if not it then return nil end
  -- the game's own link (with the suffix) when it has the item loaded, else one made
  -- its way: the name with the suffix, the suffix as the link's bonus ID
  local link = GetItemInfo and select(2, GetItemInfo(itemString(it)))
  if not link then
    local str = itemString(it)
    if not str:find(":1:%d+$") then str = str .. string.rep(":", 12) end   -- the game's full length
    link = "|cff" .. (QUALITY[it.q] or "ffffff") .. "|H" .. str .. "|h[" .. it.name .. "]|h|r"
  end
  return link
end
-- Right-click: the item's Wowhead page as a link to copy (the game can't open a browser).
function O.GearWowheadURL(it) return "https://www.wowhead.com/forever/item=" .. it.id end
function O.ShowWowhead(it)
  if not it then return end
  local url = O.GearWowheadURL(it)
  if not (StaticPopupDialogs and StaticPopup_Show) then return print("|cffffd100Holy Math|r: " .. url) end
  StaticPopupDialogs.HOLYMATH_WOWHEAD = StaticPopupDialogs.HOLYMATH_WOWHEAD or {
    text = "%s", button1 = CLOSE or "Close", hasEditBox = true, editBoxWidth = 350, maxLetters = 0,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnShow = function(self, data)
      local eb = U.editBoxOf(self)
      if eb then eb:SetText(data.url); if eb.HighlightText then eb:HighlightText() end; if eb.SetFocus then eb:SetFocus() end end
    end,
    EditBoxOnEnterPressed = function() if StaticPopup_Hide then StaticPopup_Hide("HOLYMATH_WOWHEAD") end end,
    EditBoxOnEscapePressed = function() if StaticPopup_Hide then StaticPopup_Hide("HOLYMATH_WOWHEAD") end end,
    -- keep the link as it is, whatever is typed into the box
    EditBoxOnTextChanged = function(eb, data)
      if data and eb:GetText() ~= data.url then eb:SetText(data.url); if eb.HighlightText then eb:HighlightText() end end
    end,
  }
  StaticPopup_Show("HOLYMATH_WOWHEAD", it.name .. " on Wowhead. Press Ctrl+C to copy the link, then paste it in your browser.",
    nil, { url = url })
end

-- An effect in words: "Use: +72 spirit for 15 s, every 6 min" / "Each Greater Heal: +40 healing for 15 s".
local function minutes(sec)
  if sec >= 60 and sec % 60 == 0 then return (sec / 60) .. " min" end
  return string.format("%g s", sec)
end
local SPELL_WORD = { GH = "Greater Heal" }
function O.GearEffectText(f)
  local parts = {}
  if f.healing then parts[#parts + 1] = "+" .. f.healing .. " healing" end
  if f.int then parts[#parts + 1] = "+" .. f.int .. " intellect" end
  if f.spirit then parts[#parts + 1] = "+" .. f.spirit .. " spirit" end
  if f.crit then parts[#parts + 1] = "+" .. f.crit .. "% crit" end
  local over = false
  if f.mp5 and (f.d or 0) > 0 and f.d <= 60 then
    parts[#parts + 1] = string.format("%d mana over %s", f.mp5 * f.d / 5 + 0.5, minutes(f.d)); over = true
  elseif f.mp5 then parts[#parts + 1] = f.mp5 .. " MP5" end
  if f.mana then parts[#parts + 1] = f.mana .. " mana" end
  if f.heal then parts[#parts + 1] = "heals you for " .. f.heal end
  if f.cost then parts[#parts + 1] = f.cost .. " less mana " .. (f.n and "for the next spell" or "on each spell") end
  local what = table.concat(parts, ", ")
  if (f.d or 0) > 0 and not f.n and not (over and #parts == 1) then what = what .. " for " .. minutes(f.d) end
  if f.use then
    return "Use: " .. what .. ((f.cd or 0) > 0 and (", every " .. minutes(f.cd)) or "")
  end
  if f.on then return "Each " .. (SPELL_WORD[f.on] or f.on) .. ": " .. what end
  return string.format("%g%% chance on a heal: %s", (f.p or 0) * 100, what)
end

local function linkIt(it)
  if not (it and IsModifiedClick and IsModifiedClick("CHATLINK")) then return end
  local link = O.GearLink(it)
  if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
  if ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
end

-- An item box: its picture with the action buttons' border, a tick when you have it,
-- or an empty box.
local function ItemIcon(parent, size)
  local b = O.IconButton(parent, size)
  b.tick = b:CreateTexture(nil, "OVERLAY", nil, 7)
  b.tick:SetTexture(TICK)
  b.tick:SetSize(math.floor(size / 2), math.floor(size / 2))
  b.tick:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -3)
  b.tick:Hide()
  -- a green arrow: better for you than what you wear in that slot
  b.up = b:CreateTexture(nil, "OVERLAY", nil, 7)
  local atlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("bags-greenarrow")
  if atlas and b.up.SetAtlas then
    b.up:SetAtlas("bags-greenarrow")
  else
    b.up:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
    b.up:SetTexCoord(0, 1, 1, 0)        -- it points down: turned up
  end
  b.up:SetSize(math.floor(size / 2), math.floor(size / 2))
  b.up:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 3)
  b.up:Hide()
  b:SetScript("OnEnter", function(self) if self.item then O.gearHover = self; itemTip(self, self.item, self.extra) end end)
  b:SetScript("OnLeave", function()
    O.gearHover = nil
    if GameTooltip then GameTooltip.hmGearTip, GameTooltip.hmGearItem = nil, nil end
    U.HideTip()
  end)
  b:SetScript("OnClick", function(self, button)
    if button == "RightButton" then O.ShowWowhead(self.item) else linkIt(self.item) end
  end)
  b:SetScript("OnDragStart", nil)
  function b:SetItem(it, extra)
    self.item, self.extra = it, extra
    self:Show()
    if not it then
      self.icon:SetTexture(EMPTY)
      if self.icon.SetDesaturated then self.icon:SetDesaturated(true) end
      if self.icon.SetAlpha then self.icon:SetAlpha(0.45) end
      self.tick:Hide(); self.up:Hide()
      return
    end
    self.icon:SetTexture(itemIcon(it.id))
    if self.icon.SetDesaturated then self.icon:SetDesaturated(false) end
    if self.icon.SetAlpha then self.icon:SetAlpha(1) end
    -- what you wear: a gold tick; in your bags or bank: a green one; better than what you wear: an arrow
    local g = O.gearResult and O.gearResult.gains and O.gearResult.gains[it.key]
    if g and g.worn then
      self.tick:SetVertexColor(1, 0.82, 0); self.tick:Show()
    elseif O.GearOwned(it.id) then
      self.tick:SetVertexColor(1, 1, 1); self.tick:Show()
    else
      self.tick:Hide()
    end
    if g and not g.worn and not g.pair and g.d > 0.05 then self.up:Show() else self.up:Hide() end
  end
  return b
end

---------------------------------------------------------------------------
-- Building the tab
---------------------------------------------------------------------------
local function SlotRow(pane, i, def)
  local col, r = (i > PER_COL) and 1 or 0, (i - 1) % PER_COL
  local row = CreateFrame("Frame", nil, pane)
  row:SetSize(COL_W, ROW_H)
  row:SetPoint("TOPLEFT", pane, "TOPLEFT", U.LEFT + col * (COL_W + GAP), ROWS_TOP - r * ROW_H)
  row.def = def
  -- a light band, and a line under it, as KeystoneLoot's rows
  row.band = U.Flat(row, "BACKGROUND", 1, 1, 1, (r % 2 == 0) and 0.05 or 0.02)
  if row.band then row.band:SetAllPoints(row) end
  row.line = U.Flat(row, "BORDER", 1, 1, 1, 0.08)
  if row.line then
    row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.line:SetHeight(1)
  end
  row.slotIcon = row:CreateTexture(nil, "ARTWORK")
  row.slotIcon:SetSize(SLOT_ICON, SLOT_ICON)
  row.slotIcon:SetPoint("LEFT", row, "LEFT", 8, 0)
  row.slotIcon:SetTexture(slotIcon(def.inv))
  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.name:SetPoint("LEFT", row, "LEFT", SLOT_ICON + 14, 0)
  row.name:SetWidth(LABEL_W); row.name:SetJustifyH("LEFT")
  row.name:SetText(def.name)
  row.icons = {}
  for a = 1, ICONS do
    local b = ItemIcon(row, ICON)
    b:SetPoint("LEFT", row, "LEFT", SLOT_ICON + 18 + LABEL_W + (a - 1) * ICON_STEP, 0)
    row.icons[a] = b
  end
  return row
end

function O.BuildGear(pane)
  U = O.UI
  local y = U.TOP
  -- one line: List [dropdown]  and what the list is for, on the dropdown's middle
  local listLabel = U.Label(pane, "List", "GameFontNormal", U.LEFT, y - 6)
  O.gearList = O.Choice(pane, 180, function() return true end,
    function() return { { "Without PvP gear", "pve" }, { "With PvP gear", "pvp" } } end,
    function() return settings().pvp and "pvp" or "pve" end,
    function(v) settings().pvp = (v == "pvp") or nil; O.gearKey = nil; O.FillGear() end,
    function() return settings().pvp and "With PvP gear" or "Without PvP gear" end,
    { "List", "Without PvP gear: dungeons, crafting, reputation, quests, vendors and world drops. With PvP gear: " ..
      "honor rewards too, where they are better." })
  O.gearList:SetPoint("TOPLEFT", pane, "TOPLEFT", U.LEFT + 34, y)
  O.controls.gearList = O.gearList
  listLabel:ClearAllPoints()
  listLabel:SetPoint("RIGHT", O.gearList, "LEFT", -8, 0)

  -- the playstyle, right here: change it and the list follows (the same setting as the Settings tab's)
  local psLabel = U.Label(pane, "Playstyle", "GameFontNormal", U.LEFT + 240, y - 6)
  O.gearPlaystyle = O.Choice(pane, 260, function() return ns.db ~= nil end,
    function()
      local list = {}
      for _, k in ipairs(O.RotationKeys and O.RotationKeys() or {}) do
        list[#list + 1] = { O.PlaystyleMenuText and O.PlaystyleMenuText(k) or k, k }
      end
      return list
    end,
    function() return ns.db and ns.db.rotation end,
    function(v) if ns.db then ns.db.rotation = v; O.Changed(true) end end,
    function()
      local r = ns.db and ns.model and ns.model.ROTATIONS[ns.db.rotation]
      return r and r.name or ""
    end,
    { "Playstyle", "Which spells you mostly cast: the gear that's best depends on it. The same setting as on the " ..
      "Settings tab; the Playstyles tab builds your own." })
  O.gearPlaystyle:SetPoint("TOPLEFT", pane, "TOPLEFT", U.LEFT + 312, y)
  psLabel:ClearAllPoints()
  psLabel:SetPoint("RIGHT", O.gearPlaystyle, "LEFT", -8, 0)
  O.controls.gearPlaystyle = O.gearPlaystyle

  O.gearNote = U.Label(pane, "", "GameFontDisableSmall", U.LEFT, y - 34, W)

  -- the rows sit in an inset, as the game's own lists do
  local inset = U.try("Frame", pane, "InsetFrameTemplate")
  if inset then
    inset:SetPoint("TOPLEFT", pane, "TOPLEFT", U.LEFT - 4, ROWS_TOP + 4)
    inset:SetSize(W + 8, PER_COL * ROW_H + 8)
  end
  O.gearRows = {}
  for i, def in ipairs(ROWS) do O.gearRows[i] = SlotRow(pane, i, def) end
  -- the tooltip's "this is the Gear tab's" mark never outlives the tooltip
  if GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnHide", function(tt) tt.hmGearTip, tt.hmGearItem = nil, nil end)
  end

  O.gearFoot = U.Label(pane, "", "GameFontDisableSmall", U.LEFT, ROWS_TOP - PER_COL * ROW_H - 12, W)
  O.gearFoot:SetText("First the best for you, then the next best. A green arrow: better than what you wear. A gold tick: you wear it; " ..
    "a green one: you have it. Right-click an item for its Wowhead page. " ..
    "Worked out with Holy Math's formulas, so mistakes can happen.")

  -- your bags change: the ticks follow
  local ev = CreateFrame("Frame")
  if ev.RegisterEvent then
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    ev:SetScript("OnEvent", function(_, event, id)
      -- an item's data came in while its tooltip is open: draw it again (the game's part changes)
      if event == "GET_ITEM_INFO_RECEIVED" then
        local b = O.gearHover
        if b and b.item and b.item.id == id and b:IsShown() then itemTip(b, b.item, b.extra) end
        return
      end
      if event == "PLAYER_EQUIPMENT_CHANGED" then
        -- what you wear changed: your stats read again and worked out once, a moment later
        -- (a whole set swapped is one event a slot, and the game's stats follow a little
        -- after); in combat your stats can't be read, so after it (Core.lua refreshes then)
        if ns.MarkDirty then ns.MarkDirty() end
        O.gearKey, O.gearDue = nil, true
        if not O.gearSwapTimer and C_Timer and C_Timer.After then
          O.gearSwapTimer = true
          C_Timer.After(0.3, function()
            O.gearSwapTimer = nil
            if ns.MarkDirty then ns.MarkDirty() end
            if O.tab == "gear" and O.frame and O.frame:IsShown() then O.FillGear() end
          end)
        end
        return
      end
      if O.tab == "gear" and O.frame and O.frame:IsShown() then O.FillGear() end
    end)
  end
end

local function setsText(counts, D)
  local parts = {}
  for id, n in pairs(counts or {}) do
    local bonus, got = D.sets[id] or {}, {}
    local ks = {}
    for k in pairs(bonus) do if k <= n then ks[#ks + 1] = k end end
    table.sort(ks)
    for _, k in ipairs(ks) do got[#got + 1] = bonus[k].text end
    if #got > 0 then parts[#parts + 1] = string.format("%s (%d)", D.setNames[id] or "Set", n) end
  end
  table.sort(parts)
  return #parts > 0 and (" Sets: " .. table.concat(parts, ", ") .. ".") or ""
end

-- A table as one string, the same for the same contents (keys in order).
function O.Fingerprint(v, depth)
  local t = type(v)
  if t ~= "table" then return tostring(v) end
  depth = (depth or 0) + 1
  if depth > 6 then return "{...}" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. O.Fingerprint(v[k], depth) end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- The work: GearSolve on your live character, a few milliseconds a frame (all at
-- once where the game has no frame timer). Again only when your state, what you
-- wear or the list changes.
local job
function O.GearSolveNow(S)
  local D, solver = data(), GS()
  if not (D and solver and S and S.weights and S.st and S.input) then return end
  local level = (S.input and S.input.level) or (UnitLevel and UnitLevel("player")) or 60
  -- the state table itself (a new one each time anything changed), the list, your side, your level
  -- and what you chose (playstyle, every setting, talents): a change there is worked out at once
  local key = (settings().pvp and "pvp" or "pve") .. "|" .. O.GearSide() .. "|" .. level .. "|" .. tostring(S.rotation) ..
    "|" .. O.Fingerprint(S.input.settings) .. "|" .. O.Fingerprint(S.input.talents)
  if O.gearState == S and O.gearKey == key then return end
  -- in combat your stats aren't read again: keep the list, work it out after the fight
  if InCombatLockdown and InCombatLockdown() and O.gearResult then return end
  -- working already, and only your state changed (buffs): let it finish
  if job and O.gearKey == key and not O.gearDue then return end
  -- only your state changed (a buff came or went): at most every 10 seconds, keeping the list meanwhile
  local now = GetTime and GetTime()
  if O.gearKey == key and O.gearResult and O.gearSolvedAt and now and now - O.gearSolvedAt < 10 and not O.gearDue then
    if not O.gearLater and C_Timer and C_Timer.After then
      O.gearLater = true
      C_Timer.After(10 - (now - O.gearSolvedAt), function()
        O.gearLater = nil
        if O.tab == "gear" and O.frame and O.frame:IsShown() then
          O.gearDue = true          -- its time has come: worked out now, whatever the clock says
          O.FillGear()
        end
      end)
    end
    return
  end
  O.gearDue = nil
  O.gearState, O.gearKey, O.gearSolvedAt = S, key, now
  local current, ids, keys = {}, {}, {}
  for slot, inv in pairs(solver.INV) do
    if G and G.EquippedStats then
      local ok, st = pcall(G.EquippedStats, inv)
      if ok and type(st) == "table" then current[slot] = st end
    end
    if GetInventoryItemID then ids[slot] = GetInventoryItemID("player", inv) end
    local link = GetInventoryItemLink and GetInventoryItemLink("player", inv)
    if ids[slot] then keys[slot] = (link and O.LinkKey(link)) or tostring(ids[slot]) end
  end
  local args = { E = ns.model, st = S.st, input = S.input, rot = S.rotation, D = D, side = O.GearSide(), level = level,
                 pvp = settings().pvp, profs = O.GearProfessions(), current = current, currentIds = ids, currentKeys = keys,
                 twoHandWorn = G and G.TwoHanderEquipped and G.TwoHanderEquipped() or nil,
                 weights = S.weights, yield = coroutine.yield }
  local co = coroutine.create(function() return solver.Solve(args) end)
  job = co
  O.gearWorking = true
  local function step()
    if job ~= co then return end
    -- in combat: no work at all (every frame counts there); carry on after
    if InCombatLockdown and InCombatLockdown() then
      if C_Timer and C_Timer.After then C_Timer.After(1, step) end
      return
    end
    -- the window closed or another tab: stop, and start again when the tab is back
    if O.frame and not (O.frame:IsShown() and O.tab == "gear") then
      job, O.gearWorking, O.gearKey, O.gearState = nil, false, nil, nil
      return
    end
    local t0 = debugprofilestop and debugprofilestop()
    while true do
      local ok, res, why = coroutine.resume(co)
      if not ok or coroutine.status(co) == "dead" then
        job, O.gearWorking = nil, false
        if ok then O.gearResult, O.gearWhy = res, why
        else O.gearResult, O.gearWhy = nil, "could not work it out"; if ns.LogError then ns.LogError("gear", res) end end
        if O.tab == "gear" then O.FillGear() end
        return
      end
      if t0 and debugprofilestop() - t0 > 10 then break end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, step) else step() end
  end
  step()
end

function O.FillGear()
  if not O.gearRows then return end
  local D = data()
  if O.gearList and O.gearList.refresh then O.gearList.refresh() end
  if O.gearPlaystyle and O.gearPlaystyle.refresh then O.gearPlaystyle.refresh() end
  local S = ns.State and ns.State()
  if not (S and S.weights) then
    O.gearNote:SetText((InCombatLockdown and InCombatLockdown() and S and S.st and S.st.invalid)
      and "Your stats can't be read in combat; this fills in when the fight ends."
      or "No model yet (see the Settings tab).")
    for _, r in ipairs(O.gearRows) do r:Hide() end
    return
  end
  O.GearSolveNow(S)
  local r = O.gearResult
  local side = O.GearSide()
  local sideName = side == "A" and "Alliance" or "Horde"
  if not r then
    O.gearNote:SetText(O.gearWorking and "Working out the best gear for you..." or ("No list: " .. tostring(O.gearWhy or "")))
    for _, row in ipairs(O.gearRows) do row:Hide() end
    return
  end
  local gain = r.hps - r.now
  O.gearNote:SetText(string.format("Level %d, %s.%s%s",
    r.level, sideName, setsText(r.sets, D),
    O.gearWorking and "  Updating..." or ""))

  local wv = r.weapons or {}
  -- the game loads the items shown (their names, icons and tooltips), once each
  O.gearAsked = O.gearAsked or {}
  local ask = C_Item and C_Item.RequestLoadItemDataByID
  if ask then
    local function load(it) if it and not O.gearAsked[it.id] then O.gearAsked[it.id] = true; pcall(ask, it.id) end end
    for _, it in pairs(r.items) do load(it) end
    for _, list in pairs(r.alts) do for i = 1, ICONS do load(list[i]) end end
  end
  for _, row in ipairs(O.gearRows) do
    row:Show()
    local def = row.def
    local best, alts, way = {}, {}, nil
    if def.weapon then
      -- the weapons: the best of this kind (the tooltip says which way heals more)
      way = def.weapon == "twohand" and wv.twohand or wv.onehand
      local it = way and (def.weapon == "offhand" and way.offhand or way.item)
      if it then best[1] = it end
      alts = r.alts[def.weapon] or {}
    else
      -- the best: one per slot (two for rings and trinkets)
      local seen = {}
      for _, slot in ipairs(def.slots) do
        local it = r.items[slot]
        if it and not seen[it.key .. slot] then best[#best + 1] = it; seen[it.key .. slot] = true end
      end
      -- the next best of those slots (one of each)
      local taken = {}
      for _, it in ipairs(best) do taken[it.key] = true end
      for _, slot in ipairs(def.slots) do
        for _, a in ipairs(r.alts[slot] or {}) do
          if not taken[a.key] then taken[a.key] = true; alts[#alts + 1] = a end
        end
      end
    end
    row.name:SetText(#best == 0 and ("|cff9d9d9d" .. def.name .. "|r") or def.name)
    if row.slotIcon.SetDesaturated then row.slotIcon:SetDesaturated(#best == 0) end
    local slotWord = def.name:lower()
    for a = 1, ICONS do
      if a <= #best then
        local head = "best for you (" .. slotWord .. ")"
        if def.weapon then
          local other
          if def.weapon == "twohand" then other = wv.onehand else other = wv.twohand end
          head = "best " .. slotWord
          if way and other then
            head = head .. string.format(" - %d HPS %s; %s: %d", way.hps + 0.5,
              def.weapon == "twohand" and "with it" or "with the main hand and off hand",
              def.weapon == "twohand" and "a main hand and off hand" or "the best two-hander", other.hps + 0.5)
          end
        end
        row.icons[a]:SetItem(best[a], { head = head })
      else
        local c = alts[a - #best]
        row.icons[a]:SetItem(c, c and { head = "next best for " .. slotWord })
      end
    end
  end
end
