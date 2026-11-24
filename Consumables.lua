--[[ Holy Math - Consumables.lua
     The Consumables tab: what to eat, drink and use for the most healing, worked out for your
     character as it is (level, talents, stats, the playstyle Holy Math counts you as, the fight
     on the Settings tab) by Models/ConsumableRank.lua. A row per thing you can have at once
     (one flask, one elixir, one weapon oil, one food or drink, a potion, a rune), laid out as KeystoneLoot's
     loot window:

       Level 60, Renew filler, 120 s fight.
       +--------------------------------------------------------------------------+
       | [icon] Flask            [best][2nd]...   | [icon] Food        [best]...  |
       | [icon] Elixir           [best][2nd]...   | [icon] Food and drink [best]...|
       +--------------------------------------------------------------------------+

     The first is the best for you. A gold tick: you have it on (a potion or rune: it's in
     your potion list on the Settings tab; an enchant: it's on your item); a white one: it's in
     your bags. Show [Consumables v] switches to Enchants: a row per slot, each enchant over the
     one on your item there.
]]--

local ADDON, ns = ...
local O = ns.Options
local U

local W = 836                         -- the tab's width inside the margins
local GAP = 12
local COL_W = math.floor((W - GAP) / 2)
local ROW_H, ICON, ROW_ICON = 44, 34, 28
local LABEL_W = 104
local ROWS_TOP = -122
local ICONS = 6                       -- per row: the best, then the next best
local ICON_STEP = ICON + 5
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local EMPTY = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local TICK = "Interface\\RaidFrame\\ReadyCheck-Ready"

-- one row per thing you can have at once, two columns
local ROWS = {
  { key = "flask", name = "Flask" },
  { key = "elixir", name = "Elixir" },
  { key = "oil", name = "Weapon oil" },
  { key = "potion", name = "Potion" },
  { key = "food", name = "Food and drink" },
  { key = "rune", name = "Rune" },
}
local PER_COL = 6
O.CONS_ROWS = ROWS
-- enchants: a row per slot (shoulders and back have none for a healer yet)
local ENCHANT_ROWS = {
  { key = "head", name = "Head", inv = "HeadSlot" },
  { key = "neck", name = "Neck", inv = "NeckSlot" },
  { key = "chest", name = "Chest", inv = "ChestSlot" },
  { key = "wrist", name = "Wrist", inv = "WristSlot" },
  { key = "hands", name = "Hands", inv = "HandsSlot" },
  { key = "legs", name = "Legs", inv = "LegsSlot" },
  { key = "feet", name = "Feet", inv = "FeetSlot" },
  { key = "weapon", name = "Weapon", inv = "MainHandSlot" },
  { key = "twohand", name = "Two-hand", inv = "MainHandSlot" },
  { key = "offhand", name = "Off hand", inv = "SecondaryHandSlot" },
  { key = "shield", name = "Shield", inv = "SecondaryHandSlot" },
}
O.ENCHANT_ROWS = ENCHANT_ROWS
local SLOT_TEXTURE = { HeadSlot = "Head", NeckSlot = "Neck", ChestSlot = "Chest", WristSlot = "Wrists",
  HandsSlot = "Hands", LegsSlot = "Legs", FeetSlot = "Feet", MainHandSlot = "MainHand", SecondaryHandSlot = "SecondaryHand" }
local function slotIcon(inv)
  if GetInventorySlotInfo then
    local ok, _, tex = pcall(GetInventorySlotInfo, inv)
    if ok and tex then return tex end
  end
  return "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. (SLOT_TEXTURE[inv] or "Chest")
end
local function view()
  HolyMathDB.consumables = type(HolyMathDB.consumables) == "table" and HolyMathDB.consumables or {}
  return HolyMathDB.consumables.view == "enchants" and "enchants" or "consumables"
end
O.ConsumablesView = view
local QUALITY = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }

local function data() return ns.ConsumableData end
local function rank() return ns.ConsumableRank end

local function spellIcon(id)
  local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
  if not tex and GetSpellTexture then tex = GetSpellTexture(id) end
  return tex or QUESTION
end
local function itemIcon(id)
  local tex = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
  if not tex and GetItemIcon then tex = GetItemIcon(id) end
  return tex or QUESTION
end

-- in your bags or bank
local function inBags(id)
  local count = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id, true)) or (GetItemCount and GetItemCount(id, true))
  return (count or 0) > 0
end

---------------------------------------------------------------------------
-- What you have on: your buffs, and your weapon's temporary enchant
---------------------------------------------------------------------------
local function plain(v)
  if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

-- { { id = spell id, amount = its first value or nil } ... }
function O.ConsumableAuras()
  local out = {}
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  for i = 1, 40 do
    local id, amount
    if get then
      local ok, a = pcall(get, "player", i, "HELPFUL")
      if not ok or type(a) ~= "table" then break end
      id = plain(a.spellId)
      local p = type(a.points) == "table" and plain(a.points[1]) or nil
      amount = type(p) == "number" and p or nil
    elseif UnitBuff then
      local ok, name, _, _, _, _, _, _, _, _, sid = pcall(UnitBuff, "player", i)
      if not ok or not name then break end
      id = plain(sid)
    else
      break
    end
    if type(id) == "number" then out[#out + 1] = { id = id, amount = amount } end
  end
  return out
end

function O.ConsumableOil()
  if not GetWeaponEnchantInfo then return nil end
  local ok, has, _, _, enchant = pcall(GetWeaponEnchantInfo)
  if ok and plain(has) then return plain(enchant) end
  return nil
end

---------------------------------------------------------------------------
-- The tooltip: the game's item tooltip, then Holy Math's lines
---------------------------------------------------------------------------
local ROW_WORD = {}
for _, r in ipairs(ROWS) do ROW_WORD[r.key] = r.name:lower() end
for _, r in ipairs(ENCHANT_ROWS) do ROW_WORD["e:" .. r.key] = r.name:lower() .. " enchant" end

-- an entry's item to show and link: a consumable's own, an enchant's formula or scroll (or its spell)
local function entryIcon(it)
  if it.enchant then return (it.item or 0) > 0 and itemIcon(it.item) or spellIcon(it.spell) end
  return itemIcon(it.id)
end
local function entryItem(it) if it.enchant then return (it.item or 0) > 0 and it.item or nil end return it.id end

local function valueText(d, pct, worth)
  if ns.TipValue then return ns.TipValue({ d = d, pct = pct }, worth) end
  return string.format("%+.1f HPS (%+.1f%%)", d, pct * 100)
end

-- The Holy Math lines under the item's tooltip (tt.hmTabItem: which entry). Added by the
-- item tooltips' own hook (Tooltips.lua) each time the game draws the tooltip.
function O.TabTipLines(tt)
  local g = tt and tt.hmTabItem
  local e, extra = g and g.entry, g and g.extra
  if not e then return end
  tt.hmTabAdded = true
  local r = O.consResult
  tt:AddLine(" ")
  tt:AddLine("Holy Math" .. (extra and extra.head and (": " .. extra.head) or ""), 1, 0.82, 0)
  local it = e.it
  if it.enchant then
    local cur = r and r.active and r.active[it.row]
    if e.worn then
      tt:AddDoubleLine("  On your item now", valueText(e.d, e.pct, true), 1, 1, 1, 1, 1, 1)
    else
      local label = cur and (cur.unknown and "In place of your enchant (it gives no healing)" or ("In place of " .. cur.name)) or "Over none"
      tt:AddDoubleLine("  " .. label, valueText(e.d, e.pct), 1, 1, 1, 1, 1, 1)
    end
    if it.proc == "insight" then
      tt:AddLine("Insight: 35% a heal, then 45 s before it can again; +100% spirit for 10 s. Counted as the spirit it " ..
        "gives on average over your fight.", 0.6, 0.6, 0.6, true)
    elseif it.proc == "revelation" then
      tt:AddLine("Revelation: your next spell crits, 8% a cast (a rate measured in play, not from the game's files); " ..
        "wasted on a Renew. Counted as the crit it gives your direct heals on average.", 0.6, 0.6, 0.6, true)
    end
  elseif it.potion then
    if e.worn then
      tt:AddDoubleLine("  In your potion list", valueText(e.d, e.pct, true), 1, 1, 1, 1, 1, 1)
    else
      tt:AddDoubleLine("  Over none on its cooldown", valueText(e.d, e.pct), 1, 1, 1, 1, 1, 1)
    end
    tt:AddLine("Used as often as its cooldown lets you; your potion list is on the Settings tab (Potions...).",
      0.6, 0.6, 0.6, true)
  elseif e.worn then
    tt:AddDoubleLine("  You have it on", valueText(e.d, e.pct, true), 1, 1, 1, 1, 1, 1)
  else
    local cur = r and r.active and r.active[it.row]
    tt:AddDoubleLine("  " .. (cur and ("In place of " .. cur.name) or "Over none"), valueText(e.d, e.pct), 1, 1, 1, 1, 1, 1)
  end
  if extra and extra.note then tt:AddLine(extra.note, 0.6, 0.6, 0.6, true) end
  tt:AddLine("Right-click: a Wowhead link (where to get it).", 0.6, 0.6, 0.6)
end

local function itemTip(owner, entry, extra)
  if not (GameTooltip and entry) then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip.hmTabTip = true
  GameTooltip.hmTabItem = { entry = entry, extra = extra }
  GameTooltip.hmTabAdded = nil
  local id = entryItem(entry.it)
  local link = id and ("item:" .. id) or ("enchant:" .. (entry.it.spell or 0))
  local ok = GameTooltip.SetHyperlink and pcall(GameTooltip.SetHyperlink, GameTooltip, link)
  if not ok then GameTooltip:SetText(entry.it.name) end
  -- the hook adds the lines when the game draws an item tooltip; a plain one gets them here
  if not GameTooltip.hmTabAdded then O.TabTipLines(GameTooltip) end
  GameTooltip:Show()
end

-- Shift-click: the item's link into chat; right-click: its Wowhead page.
local function linkOf(it)
  local id = entryItem(it)
  if not id then return "|cffffd100|Henchant:" .. (it.spell or 0) .. "|h[" .. it.name .. "]|h|r" end
  local link = GetItemInfo and select(2, GetItemInfo(id))
  return link or ("|cffffffff|Hitem:" .. id .. string.rep(":", 12) .. "|h[" .. it.name .. "]|h|r")
end
O.ConsumableLink = linkOf

function O.ShowWowhead(it)
  if not it then return end
  local id = entryItem(it)
  local url = id and ("https://www.wowhead.com/forever/item=" .. id) or ("https://www.wowhead.com/forever/spell=" .. (it.spell or 0))
  if not (StaticPopupDialogs and StaticPopup_Show) then return print("|cffffd100Holy Math|r: " .. url) end
  StaticPopupDialogs.HOLYMATH_WOWHEAD = StaticPopupDialogs.HOLYMATH_WOWHEAD or {
    text = "%s", button1 = CLOSE or "Close", hasEditBox = true, editBoxWidth = 350, maxLetters = 0,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnShow = function(self, d)
      local eb = U.editBoxOf(self)
      if eb then eb:SetText(d.url); if eb.HighlightText then eb:HighlightText() end; if eb.SetFocus then eb:SetFocus() end end
    end,
    EditBoxOnEnterPressed = function() if StaticPopup_Hide then StaticPopup_Hide("HOLYMATH_WOWHEAD") end end,
    EditBoxOnEscapePressed = function() if StaticPopup_Hide then StaticPopup_Hide("HOLYMATH_WOWHEAD") end end,
    -- keep the link as it is, whatever is typed into the box
    EditBoxOnTextChanged = function(eb, d)
      if d and eb:GetText() ~= d.url then eb:SetText(d.url); if eb.HighlightText then eb:HighlightText() end end
    end,
  }
  StaticPopup_Show("HOLYMATH_WOWHEAD", it.name .. " on Wowhead. Press Ctrl+C to copy the link, then paste it in your browser.",
    nil, { url = url })
end

---------------------------------------------------------------------------
-- Building the tab
---------------------------------------------------------------------------
-- An item box: its picture with the action buttons' border, a tick, or an empty box.
local function ItemIcon(parent, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints(b)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  border:SetPoint("CENTER", b, "CENTER", 0, 0)
  border:SetSize(size * 66 / 36, size * 66 / 36)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  hl:SetBlendMode("ADD")
  hl:SetAllPoints(b)
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  b.tick = b:CreateTexture(nil, "OVERLAY", nil, 7)
  b.tick:SetTexture(TICK)
  b.tick:SetSize(math.floor(size / 2), math.floor(size / 2))
  b.tick:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -3)
  b.tick:Hide()
  b:SetScript("OnEnter", function(self) if self.entry then O.consHover = self; itemTip(self, self.entry, self.extra) end end)
  b.SetEntryIcon = entryIcon
  b:SetScript("OnLeave", function()
    O.consHover = nil
    if GameTooltip then GameTooltip.hmTabTip, GameTooltip.hmTabItem = nil, nil end
    U.HideTip()
  end)
  b:SetScript("OnClick", function(self, button)
    if not self.entry then return end
    if button == "RightButton" then return O.ShowWowhead(self.entry.it) end
    if IsModifiedClick and IsModifiedClick("CHATLINK") then
      local link = linkOf(self.entry.it)
      if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return end
      if ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
    end
  end)
  function b:SetEntry(entry, extra)
    self.entry, self.extra = entry, extra
    self:Show()
    if not entry then
      self.icon:SetTexture(EMPTY)
      if self.icon.SetDesaturated then self.icon:SetDesaturated(true) end
      if self.icon.SetAlpha then self.icon:SetAlpha(0.45) end
      self.tick:Hide()
      return
    end
    self.icon:SetTexture(entryIcon(entry.it))
    if self.icon.SetDesaturated then self.icon:SetDesaturated(false) end
    if self.icon.SetAlpha then self.icon:SetAlpha(1) end
    -- you have it on: a gold tick; in your bags: a green (white-tinted) one
    if entry.worn then
      self.tick:SetVertexColor(1, 0.82, 0); self.tick:Show()
    elseif entryItem(entry.it) and inBags(entryItem(entry.it)) then
      self.tick:SetVertexColor(1, 1, 1); self.tick:Show()
    else
      self.tick:Hide()
    end
  end
  return b
end

-- the row's picture: a consumable row's best item's (the highest level in the data), an enchant
-- row's slot
local function rowIcon(def)
  if def.inv then return slotIcon(def.inv) end
  local key = def.key
  local D = data()
  if key == "potion" or key == "rune" then
    local E = ns.model
    for _, p in ipairs(E and E.POTIONS or {}) do
      if p.group == key and (key ~= "potion" or p.key == "majorMana") then return itemIcon(p.id) end
    end
    return QUESTION
  end
  local list = D and D.byRow and D.byRow[key] or {}
  return list[#list] and itemIcon(list[#list].id) or QUESTION
end

-- where row i goes when a view has n rows: two columns, the first the longer
local function place(row, i, n)
  local per = math.ceil(n / 2)
  local col, r = (i > per) and 1 or 0, (i - 1) % per
  row:ClearAllPoints()
  row:SetPoint("TOPLEFT", row.pane, "TOPLEFT", U.LEFT + col * (COL_W + GAP), ROWS_TOP - r * ROW_H)
  if row.band and row.band.SetAlpha then row.band:SetAlpha((r % 2 == 0) and 1 or 0.4) end
end

local function Row(pane, i)
  local row = CreateFrame("Frame", nil, pane)
  row.pane = pane
  row:SetSize(COL_W, ROW_H)
  -- a light band, and a line under it, as KeystoneLoot's rows
  row.band = U.Flat(row, "BACKGROUND", 1, 1, 1, 0.05)
  if row.band then row.band:SetAllPoints(row) end
  row.line = U.Flat(row, "BORDER", 1, 1, 1, 0.08)
  if row.line then
    row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.line:SetHeight(1)
  end
  row.rowIcon = row:CreateTexture(nil, "ARTWORK")
  row.rowIcon:SetSize(ROW_ICON, ROW_ICON)
  row.rowIcon:SetPoint("LEFT", row, "LEFT", 8, 0)
  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.name:SetPoint("LEFT", row, "LEFT", ROW_ICON + 14, 0)
  row.name:SetWidth(LABEL_W); row.name:SetJustifyH("LEFT")
  row.icons = {}
  for a = 1, ICONS do
    local b = ItemIcon(row, ICON)
    b:SetPoint("LEFT", row, "LEFT", ROW_ICON + 18 + LABEL_W + (a - 1) * ICON_STEP, 0)
    row.icons[a] = b
  end
  return row
end

local FOOT = {
  consumables = "Each row is one thing you can have at once: one flask, one elixir, one weapon oil, one food or " ..
    "drink, and a potion and a rune on their cooldowns; the best for you first. What each adds to your healing per second, worked out for your stats, " ..
    "the playstyle Holy Math counts you as and your fight (Settings tab); in place of the one you have on. A gold tick: " ..
    "you have it on (a potion or rune: it's in your potion list); a white one: it's in your bags. Right-click an item " ..
    "for its Wowhead page.",
  enchants = "A row per slot, the best enchant for you first: what each adds to your healing per second over the " ..
    "enchant on your item there (a gold tick), worked out for your stats, playstyle and fight. Weapon: any weapon; " ..
    "Two-hand: those and the two-hand-only ones. A white tick: its formula or scroll is in your bags. Right-click " ..
    "for its Wowhead page.",
}

-- Show [Consumables v]: the game's dropdown, or a plain button that switches
local function ShowChoice(pane, y)
  local label = U.Label(pane, "Show", "GameFontNormal", U.LEFT, y - 6)
  local function set(v)
    HolyMathDB.consumables = type(HolyMathDB.consumables) == "table" and HolyMathDB.consumables or {}
    HolyMathDB.consumables.view = v
    O.consKey = nil
    O.FillConsumables()
  end
  local function text() return view() == "enchants" and "Enchants" or "Consumables" end
  local dd = U.try("DropdownButton", pane, "WowStyle1DropdownTemplate")
  if dd and dd.SetupMenu then
    dd:SetWidth(160)
    dd:SetupMenu(function(_, root)
      root:CreateRadio("Consumables", function(v) return view() == v end, set, "consumables")
      root:CreateRadio("Enchants", function(v) return view() == v end, set, "enchants")
    end)
    if dd.SetSelectionTranslator then dd:SetSelectionTranslator(function() return text() end) end
    dd.refresh = function() if dd.GenerateMenu then pcall(dd.GenerateMenu, dd) end end
  else
    dd = U.Button(pane, text(), 160, 22, function() set(view() == "enchants" and "consumables" or "enchants") end)
    dd.refresh = function() if dd.label then dd.label:SetText(text()) elseif dd.SetText then dd:SetText(text()) end end
  end
  dd:SetPoint("TOPLEFT", pane, "TOPLEFT", U.LEFT + 40, y)
  label:ClearAllPoints()
  label:SetPoint("RIGHT", dd, "LEFT", -8, 0)
  U.Tip(dd, "Show", "Consumables: what to eat, drink and use, a row for each thing you can have at once (one flask, " ..
    "one elixir, one weapon oil, one food or drink, a potion, a rune). " ..
    "Enchants: the best enchant for each slot.")
  O.controls.consView = dd
  return dd
end

function O.BuildConsumables(pane)
  U = O.UI
  local y = U.TOP
  O.consView = ShowChoice(pane, y)
  O.consNote = U.Label(pane, "", "GameFontDisableSmall", U.LEFT, y - 34, W)
  -- the rows sit in an inset, as the game's own lists do
  local inset = U.try("Frame", pane, "InsetFrameTemplate")
  if inset then
    inset:SetPoint("TOPLEFT", pane, "TOPLEFT", U.LEFT - 4, ROWS_TOP + 4)
    inset:SetSize(W + 8, PER_COL * ROW_H + 8)
  end
  O.consRows = {}
  for i = 1, 2 * PER_COL do O.consRows[i] = Row(pane, i); place(O.consRows[i], i, 2 * PER_COL) end
  -- the tooltip's "this is the tab's" mark never outlives the tooltip
  if GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnHide", function(tt) tt.hmTabTip, tt.hmTabItem = nil, nil end)
  end
  O.consFoot = U.Label(pane, "", "GameFontDisableSmall", U.LEFT, ROWS_TOP - PER_COL * ROW_H - 12, W)

  local ev = CreateFrame("Frame")
  if ev.RegisterEvent then
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    ev:RegisterEvent("UNIT_INVENTORY_CHANGED")
    ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ev:SetScript("OnEvent", function(_, event, arg)
      -- an item's data came in: its icon, and its tooltip if open
      if event == "GET_ITEM_INFO_RECEIVED" then
        local b = O.consHover
        if b and b.entry and entryItem(b.entry.it) == arg and b:IsShown() then itemTip(b, b.entry, b.extra) end
      end
      -- an oil put on (or worn off), an item or its enchant changed: worked out again
      if event == "UNIT_INVENTORY_CHANGED" and arg ~= "player" then return end
      if event == "UNIT_INVENTORY_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then O.consKey = nil end
      if O.tab == "consumables" and O.frame and O.frame:IsShown() then O.FillConsumables() end
    end)
  end
end

---------------------------------------------------------------------------
-- The work: a few milliseconds a frame, again only when your state changes
---------------------------------------------------------------------------
-- the enchant on each item you wear: { [slot] = enchant id }
function O.EnchantIds()
  local out = {}
  if not GetInventoryItemLink then return out end
  for _, slot in pairs((rank() or {}).ENCHANT_SLOT or {}) do
    local ok, link = pcall(GetInventoryItemLink, "player", slot)
    link = ok and plain(link)
    local id = type(link) == "string" and tonumber(link:match("item:%-?%d+:(%-?%d*)") or "")
    if id and id ~= 0 then out[slot] = id end
  end
  return out
end

local job
local function fingerprint(v, auras, oil, ids)
  local parts = {}
  for _, a in ipairs(auras) do parts[#parts + 1] = a.id .. ":" .. tostring(a.amount) end
  table.sort(parts)
  local e = {}
  for slot, id in pairs(ids) do e[#e + 1] = slot .. "=" .. id end
  table.sort(e)
  return v .. "|" .. table.concat(parts, ",") .. "|" .. tostring(oil) .. "|" .. table.concat(e, ",")
end

function O.ConsumablesNow(S)
  local D, CR = data(), rank()
  if not (D and CR and S and S.st and S.input and ns.model) then return end
  local v = view()
  local auras, oil = O.ConsumableAuras(), O.ConsumableOil()
  local ids = O.EnchantIds()
  local key = fingerprint(v, auras, oil, ids)
  if O.consState == S and O.consKey == key then return end
  -- in combat your stats aren't read again: keep the list
  if InCombatLockdown and InCombatLockdown() and O.consResult and O.consResult.view == v then return end
  O.consState, O.consKey = S, key
  local args = { E = ns.model, D = D, S = S, auras = auras, oil = oil, ids = ids, yield = coroutine.yield }
  local co = coroutine.create(function()
    local r, why
    if v == "enchants" then r, why = CR.RankEnchants(args) else r, why = CR.Rank(args) end
    if r then r.view = v end
    return r, why
  end)
  job = co
  O.consWorking = true
  local function step()
    if job ~= co then return end
    if InCombatLockdown and InCombatLockdown() then
      if C_Timer and C_Timer.After then C_Timer.After(1, step) end
      return
    end
    -- the window closed or another tab: stop, and start again when the tab is back
    if O.frame and not (O.frame:IsShown() and O.tab == "consumables") then
      job, O.consWorking, O.consKey, O.consState = nil, false, nil, nil
      return
    end
    local t0 = debugprofilestop and debugprofilestop()
    while true do
      local ok, res, why = coroutine.resume(co)
      if not ok or coroutine.status(co) == "dead" then
        job, O.consWorking = nil, false
        if ok then O.consResult, O.consWhy = res, why
        else O.consResult, O.consWhy = nil, "could not work it out"; if ns.LogError then ns.LogError("consumables", res) end end
        if O.tab == "consumables" then O.FillConsumables() end
        return
      end
      if t0 and debugprofilestop() - t0 > 10 then break end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, step) else step() end
  end
  step()
end

function O.FillConsumables()
  if not O.consRows then return end
  local v = view()
  if O.consView and O.consView.refresh then O.consView.refresh() end
  O.consFoot:SetText(FOOT[v])
  local S = ns.State and ns.State()
  if not (S and S.weights) then
    O.consNote:SetText((InCombatLockdown and InCombatLockdown() and S and S.st and S.st.invalid)
      and "Your stats can't be read in combat; this fills in when the fight ends."
      or "No model yet (see the Settings tab).")
    for _, r in ipairs(O.consRows) do r:Hide() end
    return
  end
  O.ConsumablesNow(S)
  local r = O.consResult
  if not r or r.view ~= v then
    O.consNote:SetText(O.consWorking and "Working out what's best for you..." or ("No list: " .. tostring(O.consWhy or "")))
    for _, row in ipairs(O.consRows) do row:Hide() end
    return
  end
  local E = ns.model
  local rot = E and E.ROTATIONS and E.ROTATIONS[S.rotation]
  O.consNote:SetText(string.format("Level %d, %s, %d s fight: %d HPS now.%s", S.st.level or 60,
    rot and rot.name or "your playstyle", S.input.settings.fightLength or 0, r.now + 0.5,
    O.consWorking and "  Updating..." or ""))
  local byRow = {}
  for _, row in ipairs(r.rows) do byRow[row.row] = row.items end
  local defs = v == "enchants" and ENCHANT_ROWS or ROWS
  -- the game loads the items shown (their names, icons and tooltips), once each
  O.consAsked = O.consAsked or {}
  local ask = C_Item and C_Item.RequestLoadItemDataByID
  for i, row in ipairs(O.consRows) do
    local def = defs[i]
    if not def then row:Hide() else
      place(row, i, #defs)
      row:Show()
      row.def = def
      row.rowIcon:SetTexture(rowIcon(def))
      local list = byRow[def.key] or {}
      row.name:SetText(#list == 0 and ("|cff9d9d9d" .. def.name .. "|r") or def.name)
      if row.rowIcon.SetDesaturated then row.rowIcon:SetDesaturated(#list == 0) end
      local word = ROW_WORD[(v == "enchants" and "e:" or "") .. def.key] or def.key
      for a = 1, ICONS do
        local e = list[a]
        local id = e and entryItem(e.it)
        if id and ask and not O.consAsked[id] then O.consAsked[id] = true; pcall(ask, id) end
        row.icons[a]:SetEntry(e, e and { head = a == 1 and ("best for you (" .. word .. ")") or ("next best (" .. word .. ")") })
      end
    end
  end
end
