--[[ Holy Math - Options.lua
     A small window for /hm, built from Blizzard's own UI pieces so it looks like
     the default UI:
       window      PortraitFrameTemplate (title bar, portrait, close button)
       numbers     MinimalSliderWithSteppersTemplate (the slider from the game's options panel)
       on/off      UICheckButtonTemplate
       playstyle   [<] name [>] with UIPanelButtonTemplate arrows. NOT the game's dropdown:
                   that runs our code inside Blizzard's shared menu system, which tainted
                   the Group Finder's menu (ADDON_ACTION_BLOCKED on Search(), 20 Nov 2026).
       button      UIPanelButtonTemplate (Defaults, bottom left, as in the game's options)
     Each was checked against addons that already use it on this client (BugSack,
     OpenMap). Where a client lacks one, that widget falls back to a plain version,
     so the window always works.

     Every setting explains itself on hover. Everything recalculates by itself
     (settings, gear, buffs, talents), so there is no Recalculate button; the
     check against the game's tooltips is a status line, not a button.
]]--

local ADDON, ns = ...
local E = setmetatable({}, { __index = function(_, k) return ns.model and ns.model[k] end })
local O = { rows = {}, controls = {} }
ns.Options = O

-- Two equal columns, equal outer margins.
local MARGIN, GAP = 22, 28
local LABEL_W, SLIDER_W, VALUE_W = 120, 150, 46
local COL_W = LABEL_W + SLIDER_W + VALUE_W
local LEFT = MARGIN
local RIGHT = LEFT + COL_W + GAP
local WIDTH = RIGHT + COL_W + MARGIN
local HEIGHT = 470
local TOP, ROW, ROW_H = -66, 30, 28

local function db() return ns.db end

local function try(kind, parent, template, name)
  local ok, f = pcall(CreateFrame, kind, name, parent, template)
  if ok and f then return f end
end

-- Hover help, laid out like the game's own settings: title white, text gold.
local function ShowTip(owner, title, text)
  if not (GameTooltip and title) then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(title, 1, 1, 1)
  if text then GameTooltip:AddLine(text, nil, nil, nil, true) end
  GameTooltip:Show()
end
local function HideTip() if GameTooltip then GameTooltip:Hide() end end

local function Tip(frame, title, text)
  if not (frame and frame.HookScript and title) then return end
  frame:HookScript("OnEnter", function(self) ShowTip(self, title, type(text) == "function" and text() or text) end)
  frame:HookScript("OnLeave", HideTip)
end

local function Label(parent, text, font, x, y, w)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", x, y)
  if w then fs:SetWidth(w) end
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

-- A row's label, centred on the row (two-line labels too), with the row's
-- hover help on it.
local function RowLabel(parent, text, x, y, title, help, w)
  w = w or LABEL_W
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", parent, "TOPLEFT", x, y - ROW_H / 2)
  fs:SetWidth(w - 6)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  local hit = CreateFrame("Frame", nil, parent)
  hit:SetPoint("TOPLEFT", x, y)
  hit:SetSize(w - 6, ROW_H)
  hit:EnableMouse(true)
  Tip(hit, title or text:gsub("\n", " "), help)
  return fs, hit
end

local function Header(parent, text, x, y)
  return Label(parent, text, "GameFontNormal", x, y)
end

-- A Blizzard push button; plain fallback only if the template is missing.
local function Button(parent, text, w, h, onClick)
  local b = try("Button", parent, "UIPanelButtonTemplate")
  if b and b.SetText then
    b:SetSize(w, h or 22)
    b:SetText(text)
  else
    b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h or 22)
    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b:SetBackdropColor(0.14, 0.14, 0.17, 1)
    b:SetBackdropBorderColor(0.40, 0.34, 0.14, 1)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetText(text)
    b.label = fs
  end
  b:SetScript("OnClick", onClick)
  return b
end

local function snap(v, lo, step)
  v = lo + math.floor((v - lo) / step + 0.5) * step
  return math.floor(v * 1000 + 0.5) / 1000
end

-- label  <=====o=====>  value      (the game's options slider)
local function Slider(parent, id, x, y, label, help, get, set, lo, hi, step, fmt)
  RowLabel(parent, label, x, y, nil, help)
  local title = label:gsub("\n", " ")
  local Mixin = MinimalSliderWithSteppersMixin
  local s = Mixin and Mixin.Label and Mixin.Event and try("Frame", parent, "MinimalSliderWithSteppersTemplate")
  if s and s.Init and s.RegisterCallback then
    local ok = pcall(function()
      s:SetPoint("TOPLEFT", x + LABEL_W, y)
      s:SetWidth(SLIDER_W)
      s:SetHeight(ROW_H)
      if s.Slider and s.Slider.SetObeyStepOnDrag then s.Slider:SetObeyStepOnDrag(true) end
      s:Init(get(), lo, hi, math.floor((hi - lo) / step + 0.5),
        { [Mixin.Label.Right] = function(v) return fmt(snap(v, lo, step)) end })
      s:RegisterCallback(Mixin.Event.OnValueChanged, function(_, v)
        if O.filling then return end
        v = snap(v, lo, step)
        if v ~= get() then set(v); O.Changed() end
      end, s)
    end)
    if ok then
      Tip(s.Slider, title, help)
      O.controls[id] = s
      O.rows[#O.rows + 1] = function()
        O.filling = true
        if s.SetValue then s:SetValue(get()) elseif s.Slider then s.Slider:SetValue(get()) end
        O.filling = false
      end
      return
    end
    s:Hide()
  end
  -- fallback: [-] value [+]
  local minus = Button(parent, "-", 22, 20, function() set(math.max(lo, snap(get() - step, lo, step))); O.Changed() end)
  minus:SetPoint("LEFT", parent, "TOPLEFT", x + LABEL_W, y - ROW_H / 2)
  local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  value:SetPoint("LEFT", minus, "RIGHT", 4, 0)
  value:SetWidth(50)
  local plus = Button(parent, "+", 22, 20, function() set(math.min(hi, snap(get() + step, lo, step))); O.Changed() end)
  plus:SetPoint("LEFT", value, "RIGHT", 4, 0)
  Tip(minus, title, help); Tip(plus, title, help)
  O.controls[id .. "-"], O.controls[id .. "+"], O.controls[id] = minus, plus, value
  O.rows[#O.rows + 1] = function() value:SetText(fmt(get())) end
end

-- [x] label    (the game's checkbox)
local function Check(parent, id, x, y, label, help, get, set)
  local c = try("CheckButton", parent, "UICheckButtonTemplate")
  if c and c.Text and c.SetChecked then
    c:SetSize(26, 26)
    c:SetPoint("TOPLEFT", x - 4, y)
    c.Text:SetText(label)
    c.Text:SetFontObject(GameFontHighlightSmall)
    if c.SetHitRectInsets and c.Text.GetStringWidth then c:SetHitRectInsets(0, -c.Text:GetStringWidth() - 4, 0, 0) end
    c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); O.Changed() end)
    Tip(c, label, help)
    O.controls[id] = c
    O.rows[#O.rows + 1] = function() c:SetChecked(get() and true or false) end
    return
  end
  RowLabel(parent, label, x, y + 2, nil, help)
  local b
  b = Button(parent, "", 50, 20, function() set(not get()); O.Changed() end)
  b:SetPoint("LEFT", parent, "TOPLEFT", x + LABEL_W, y - 11)
  Tip(b, label, help)
  O.controls[id] = b
  O.rows[#O.rows + 1] = function()
    local t = get() and "|cff40ff40On|r" or "|cff9d9d9dOff|r"
    if b.label then b.label:SetText(t) else b:SetText(t) end
  end
end

local function rotationKeys()
  local keys = {}
  local S = ns.State and ns.State()
  local t = S and S.t
  for k, r in pairs(E.ROTATIONS) do
    if not r.sheetOnly and (not r.requires or (t and (t[r.requires] or 0) > 0)) then keys[#keys + 1] = k end
  end
  table.sort(keys, function(a, b) return E.ROTATIONS[a].name < E.ROTATIONS[b].name end)
  return keys
end

local function planEHPS(key)
  local S = ns.State()
  for _, pl in ipairs(S and S.plans or {}) do if pl.key == key then return pl.ehps end end
end

local function planHelp()
  local lines = { "Which spells you mostly cast. Every playstyle uses Prayer of Mending and Penance " ..
    "on cooldown when you have them (and Flash Heal twice a minute with Holy Binding), then:", "" }
  for _, k in ipairs(rotationKeys()) do
    local r = E.ROTATIONS[k]
    lines[#lines + 1] = "|cffffffff" .. r.name .. ":|r " .. (r.help or "")
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Ranks are chosen for you: the ones that heal most with your stats. The Your spells " ..
    "tab lists your spells."
  local S = ns.State()
  local best = S and S.plans and S.plans[1]
  if best then
    lines[#lines + 1] = ""
    lines[#lines + 1] = best.key == db().rotation and "|cff40ff40You're on your best playstyle right now.|r"
      or ("|cffffffffBest for you right now: " .. best.name .. "|r")
  end
  return table.concat(lines, "\n")
end

-- label  [<]  Greater Heal filler  110 HPS  best  [>]
-- Plain buttons only: Blizzard's dropdown would run our code inside its shared
-- menu system and taint other addons'/Blizzard's menus (see the header).
local function PlaystyleStepper(parent, x, y)
  RowLabel(parent, "Playstyle", x, y, nil, planHelp)
  local function move(dir)
    local keys, i = rotationKeys(), 1
    for n, k in ipairs(keys) do if k == db().rotation then i = n end end
    db().rotation = keys[(i - 1 + dir) % #keys + 1]
    if PlaySound then pcall(PlaySound, 856) end
    O.Changed(true)
  end
  local prev = Button(parent, "<", 24, 22, function() move(-1) end)
  prev:SetPoint("LEFT", parent, "TOPLEFT", x + LABEL_W, y - ROW_H / 2)
  local name = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  name:SetPoint("LEFT", prev, "RIGHT", 4, 0)
  name:SetWidth(SLIDER_W + VALUE_W - 60)
  name:SetJustifyH("CENTER")
  local nxt = Button(parent, ">", 24, 22, function() move(1) end)
  nxt:SetPoint("LEFT", name, "RIGHT", 4, 0)
  local hit = CreateFrame("Frame", nil, parent)
  hit:SetPoint("LEFT", prev, "RIGHT", 0, 0)
  hit:SetSize(SLIDER_W + VALUE_W - 56, ROW_H)
  hit:EnableMouse(true)
  Tip(hit, "Playstyle", planHelp)
  Tip(prev, "Playstyle", planHelp); Tip(nxt, "Playstyle", planHelp)
  O.controls["rot<"], O.controls["rot>"], O.controls.rot = prev, nxt, name
  O.rows[#O.rows + 1] = function()
    local k = db().rotation
    local r = E.ROTATIONS[k]
    if not r then name:SetText(""); return end
    local hps = planEHPS(k)
    local S = ns.State()
    local best = S and S.plans and S.plans[1] and S.plans[1].key == k
    name:SetText(r.name .. (hps and string.format("  |cff9d9d9d%d HPS|r", hps + 0.5) or "") ..
      (best and "  |cff40ff40best|r" or ""))
  end
end

local OVERHEAL_ORDER = { "RENEW", "GH", "FLASH", "HEAL", "POH", "POM", "PWS", "PENANCE", "NOVA", "LESSER" }

local function Window()
  local p = try("Frame", UIParent, "PortraitFrameTemplate", "HolyMathOptions")
  local blizzard = p and p.SetTitle
  if not blizzard then
    p = p or CreateFrame("Frame", "HolyMathOptions", UIParent, "BackdropTemplate")
    if p.SetBackdrop then
      p:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    end
  end
  p:SetSize(WIDTH, HEIGHT)
  p:SetPoint("CENTER")
  p:SetFrameStrata("DIALOG")
  p:SetMovable(true); p:EnableMouse(true); p:RegisterForDrag("LeftButton")
  p:SetClampedToScreen(true)
  p:SetToplevel(true)
  if blizzard then
    p:SetTitle("Holy Math")
    if p.SetPortraitToAsset then pcall(p.SetPortraitToAsset, p, "Interface\\Icons\\Spell_Holy_Renew") end
    -- The template's close button asks the game's panel manager to hide the window,
    -- and that goes through secure code that is blocked in combat. Our window is a
    -- plain frame: hide it directly, so it closes in combat too.
    if p.CloseButton and p.CloseButton.SetScript then
      p.CloseButton:SetScript("OnClick", function() p:Hide() end)
    end
    p.onCloseCallback = function() p:Hide() end
  else
    Label(p, "Holy Math", "GameFontNormal", MARGIN, -16)
    local close = try("Button", p, "UIPanelCloseButton")
    if close then close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() p:Hide() end) end
  end
  return p
end

local function overhealHelp(name)
  return "How much of " .. name .. "'s healing you expect to land on players who are already " ..
    "at full health, and so be wasted. The higher this is, the less " .. name .. " is worth."
end

local function Pane(p)
  local pane = CreateFrame("Frame", nil, p)
  pane:SetAllPoints(p)
  return pane
end

-- Fixed-width text cells, for the spell table.
local function Cell(parent, x, y, w, justify, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetWidth(w)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetText("")
  return fs
end

local TABS = { { key = "settings", text = "Settings" }, { key = "spells", text = "Your spells" },
               { key = "tooltips", text = "Tooltips" } }

function O.ShowTab(key)
  O.tab = key
  for i, t in ipairs(TABS) do
    local pane, tab = O.panes[t.key], O.tabs[i]
    if t.key == key then pane:Show() else pane:Hide() end
    if tab.isBlizzard then
      if t.key == key and PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, tab)
      elseif t.key ~= key and PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, tab) end
    elseif tab.label then
      tab.label:SetText(t.key == key and ("|cffffd100" .. t.text .. "|r") or t.text)
    end
  end
  if O.frame and PanelTemplates_SetTab then
    for i, t in ipairs(TABS) do if t.key == key then pcall(PanelTemplates_SetTab, O.frame, i) end end
  end
  if O.frame then O.Refresh() end
end

-- Blizzard's own tabs under the window (like the character window), plain buttons if missing.
local function Tabs(p)
  O.tabs = {}
  for i, t in ipairs(TABS) do
    local tab = try("Button", p, "PanelTabButtonTemplate", "HolyMathOptionsTab" .. i)
    if tab and tab.SetText then
      tab.isBlizzard = true
      tab:SetID(i)
      tab:SetText(t.text)
      if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
      tab:SetScript("OnClick", function() if PlaySound then pcall(PlaySound, 841) end; O.ShowTab(t.key) end)
    else
      tab = Button(p, t.text, 110, 24, function() O.ShowTab(t.key) end)
    end
    if i == 1 then tab:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 12, 2)
    else tab:SetPoint("LEFT", O.tabs[i - 1], "RIGHT", 4, 0) end
    O.tabs[i] = tab
    O.controls["tab:" .. t.key] = tab
  end
  p.numTabs = #TABS
  if PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, p, #TABS) end
end

local function Block(pane, x, y, w, h, title, help)
  local hit = CreateFrame("Frame", nil, pane)
  hit:SetPoint("TOPLEFT", x, y)
  hit:SetSize(w, h)
  hit:EnableMouse(true)
  Tip(hit, title, help)
  local fs = Label(pane, "", "GameFontHighlightSmall", x, y, w)
  fs:SetJustifyV("TOP")
  fs:SetHeight(h)
  return fs
end

-- Your spells: every healing spell you know, as facts. (The playstyle is picked on
-- the Settings tab.)
local OVERVIEW_ROWS, ROW_GAP = 10, 22
local OV_COLS = {   -- title, x, width, justify, help
  { "Spell", 0, 150, "LEFT" },
  { "Rank", 150, 44, "RIGHT", "Your highest rank of it." },
  { "Heal", 194, 66, "RIGHT", "One cast at your highest rank, all targets, after your overheal setting." },
  { "Mana", 260, 56, "RIGHT", "What one cast costs, with your talents." },
  { "Per mana", 316, 72, "RIGHT", "Healing per point of mana, at your highest rank." },
  { "Per second", 388, 82, "RIGHT", "Healing per second of casting, at your highest rank (instants count a global cooldown)." },
  { "Most efficient", 470, 190, "RIGHT", "Your rank of it that heals the most per point of mana, and how much. Often not your highest." },
}
local function BuildSpellsPane(pane)
  local W = WIDTH - 2 * MARGIN
  -- Spell overview --------------------------------------------------------------
  local y = TOP
  Header(pane, "Spell overview", LEFT, y)
  y = y - 22
  for _, c in ipairs(OV_COLS) do
    Cell(pane, LEFT + c[2], y, c[3], c[4], "GameFontNormalSmall"):SetText(c[1])
    if c[5] then
      local h = CreateFrame("Frame", nil, pane)
      h:SetPoint("TOPLEFT", LEFT + c[2], y)
      h:SetSize(c[3], 16)
      h:EnableMouse(true)
      Tip(h, c[1], c[5])
    end
  end
  O.spellRows = {}
  for i = 1, OVERVIEW_ROWS do
    local ry = y - 4 - i * ROW_GAP
    local row = CreateFrame("Frame", nil, pane)
    row:SetPoint("TOPLEFT", LEFT, ry + 3)
    row:SetSize(W, ROW_GAP)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
      if not self.spellID or not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if not (GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID)) then
        GameTooltip:SetText(self.title or "", 1, 1, 1)
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", HideTip)
    row.cells = {}
    for n, c in ipairs(OV_COLS) do row.cells[n] = Cell(pane, LEFT + c[2], ry, c[3], c[4]) end
    O.spellRows[i] = row
  end

  Label(pane, "|cff9d9d9dAfter your overheal settings. Hover a spell for its tooltip, a heading for what it means.|r",
    "GameFontHighlightSmall", LEFT, y - 6 - (OVERVIEW_ROWS + 1) * ROW_GAP, W)
end

local function BuildTooltipsPane(pane)
  local tips = function() return db().tooltips end
  local function opt(id, x, y, label, help, key)
    Check(pane, id, x, y, label, help,
      function() return tips()[key] ~= false end, function(v) tips()[key] = v end)
  end
  local y = TOP
  Header(pane, "Item tooltips", LEFT, y)
  y = y - 24
  opt("tipItems", LEFT, y, "Show on item tooltips", "The line with how much an item gains or loses you in healing per second.", "items")
  y = y - 26
  opt("tipItemPct", LEFT, y, "Also show the change in %", "Adds the change as a percentage of your healing, e.g. (+1.8%).", "itemPercent")
  y = y - 26
  opt("tipCantEquip", LEFT, y, "Say when you can't use an item", "Plate, swords, shields, items for other classes: \"can't wear Plate\" instead of a number.", "cantEquip")
  y = y - 26
  opt("tipUseNote", LEFT, y, "Note on-use and proc effects", "\"Use or proc effect not counted\" under items that have one.", "useNote")
  y = y - 26
  opt("tipOnlyUp", LEFT, y, "Only show upgrades", "Hide the line on items that would lower your healing.", "onlyUpgrades")
  y = y - 26
  opt("tipShift", LEFT, y, "Only while holding Shift", "Show the item line only while you hold down Shift.", "itemShift")

  -- Right: why there are no spell options
  Header(pane, "Spell tooltips", RIGHT, TOP)
  Label(pane, "Holy Math leaves spell tooltips alone. The game's own spell tooltip already shows " ..
    "what a heal does with your healing power, and everything else (best ranks, healing per mana " ..
    "and per second, what to cast) is on the Your spells tab.", "GameFontHighlightSmall", RIGHT, TOP - 24, COL_W)

  local def = Button(pane, "Defaults", 110, 22, function()
    db().tooltips = ns.TooltipDefaults()
    O.Changed(true)
  end)
  def:SetPoint("BOTTOMLEFT", MARGIN - 4, 14)
  Tip(def, "Defaults", "Put every tooltip setting back to its starting value.")
  O.controls.TooltipDefaults = def
end

local function Build()
  if O.frame then return end
  local p = Window()
  p:SetScript("OnDragStart", p.StartMoving)
  p:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    HolyMathDB.ui = { point = point, rel = rel, x = x, y = y }
  end)
  p:SetScript("OnShow", function(self)
    if PlaySound then pcall(PlaySound, 839) end   -- the sound Blizzard windows open with
    O.Refresh(true)
  end)
  p:SetScript("OnHide", function() if PlaySound then pcall(PlaySound, 840) end end)
  if UISpecialFrames then table.insert(UISpecialFrames, "HolyMathOptions") end   -- Esc closes it
  local ui = HolyMathDB.ui
  if ui and ui.point then p:ClearAllPoints(); p:SetPoint(ui.point, UIParent, ui.rel or ui.point, ui.x or 0, ui.y or 0) end

  O.panes = { settings = Pane(p), spells = Pane(p), tooltips = Pane(p) }
  local frame = p
  p = O.panes.settings

  -- Left column: the fight -------------------------------------------------
  local y = TOP
  Header(p, "Fight", LEFT, y)
  y = y - 24
  Slider(p, "fight", LEFT, y, "Fight length",
    "How long the fights you heal usually last (a typical raid boss: about 2 minutes; dungeon pulls: under 1). In long fights you run out of mana, so mana " ..
    "(mp5, spirit, intellect) is worth more; in short fights healing power counts most.",
    function() return db().settings.fightLength end, function(v) db().settings.fightLength = v end,
    30, 900, 30, function(v) return v .. " s" end)
  y = y - ROW
  PlaystyleStepper(p, LEFT, y)
  y = y - ROW
  Slider(p, "pom", LEFT, y, "Prayer of Mending\nbounces",
    "How many people Prayer of Mending heals before it runs out (it can jump up to 5 times).",
    function() return db().settings.pomHits end, function(v) db().settings.pomHits = v end,
    1, 5, 1, tostring)
  y = y - ROW
  Slider(p, "tides", LEFT, y, "Mana Tide totems",
    "Shaman Mana Tide Totems that reach you in a fight. Each restores about 1,160 mana, " ..
    "once every 5 minutes. Set 0 if your group has no shaman.",
    function() return db().settings.manaTidesInGroup end, function(v) db().settings.manaTidesInGroup = v end,
    0, 3, 1, tostring)
  y = y - ROW - 2
  Check(p, "pots", LEFT, y, "Mana potion on cooldown",
    "Drink a Major Mana Potion every 2 minutes (1,800 mana each). Turn off if you don't.",
    function() return db().settings.majorManaPotions end, function(v) db().settings.majorManaPotions = v end)
  y = y - 24
  Check(p, "insp", LEFT, y, "Count Inspiration (tank armor after crits)",
    "Inspiration (a Holy talent) raises the tank's armor for a while after your heals crit. " ..
    "When this is on, the damage that prevents is counted as healing. Only matters if you have the talent.",
    function() return db().settings.includeInspiration end, function(v) db().settings.includeInspiration = v end)

  -- Result + check ------------------------------------------------------------
  y = y - 40
  Header(p, "Result", LEFT, y)
  -- big "93 HPS", and what it was before overheal
  O.hps = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  O.hps:SetPoint("TOPLEFT", LEFT, y - 22)
  O.hps:SetJustifyH("LEFT")
  O.hps:SetText("")
  O.hpsNote = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  O.hpsNote:SetPoint("BOTTOMLEFT", O.hps, "BOTTOMRIGHT", 8, 1)   -- follows the number, however wide
  O.hpsNote:SetJustifyH("LEFT")
  O.hpsNote:SetText("")
  local rhit = CreateFrame("Frame", nil, p)
  rhit:SetPoint("TOPLEFT", LEFT, y - 20)
  rhit:SetSize(COL_W, 22)
  rhit:EnableMouse(true)
  Tip(rhit, "HPS (healing per second)",
    "What you heal per second over the fight described above, with your current stats, talents " ..
    "and spells, after the overheal you expect. Updates by itself when your gear, buffs, talents " ..
    "or these settings change; item tooltips use the same settings.")

  -- stat values: a small table, best first
  O.result = Label(p, "", "GameFontNormalSmall", LEFT, y - 50, COL_W)
  O.result:SetText("Worth the same as 1 healing power")
  local whit = CreateFrame("Frame", nil, p)
  whit:SetPoint("TOPLEFT", LEFT, y - 48)
  whit:SetSize(COL_W, 64)
  whit:EnableMouse(true)
  Tip(whit, "Stat values",
    "How much healing one point of each stat adds, compared with one point of healing power. " ..
    "mp5 2.44 means 1 mp5 is worth as much as 2.44 healing power to you right now. Crit and haste " ..
    "are per 1%. They change with your gear, talents, fight length and playstyle.")
  O.weightCells = {}
  local colW = math.floor(COL_W / 3)
  for i = 1, 6 do
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local x, ry = LEFT + col * colW, y - 66 - row * 16
    local name = Cell(p, x, ry, colW - 44, "LEFT")
    local val = Cell(p, x + colW - 50, ry, 40, "RIGHT")
    O.weightCells[i] = { name = name, value = val }
  end

  O.status = Label(p, "", "GameFontHighlightSmall", LEFT, y - 22 - 82, COL_W)
  local shit = CreateFrame("Frame", nil, p)
  shit:SetPoint("TOPLEFT", LEFT, y - 22 - 78)
  shit:SetSize(COL_W, 20)
  shit:EnableMouse(true)
  Tip(shit, "Checked against the game", function() return O.statusHelp or "" end)

  -- Right column: overheal per spell ------------------------------------------
  y = TOP
  Header(p, "Overheal you expect", RIGHT, y)
  y = y - 24
  for _, key in ipairs(OVERHEAL_ORDER) do
    local name = E.SPELLS[key] and E.SPELLS[key].name or key
    Slider(p, "oh" .. key, RIGHT, y, name, overhealHelp(name),
      function() return db().settings.overheal[key] or 0 end, function(v) db().settings.overheal[key] = v end,
      0, 0.9, 0.05, function(v) return math.floor(v * 100 + 0.5) .. "%" end)
    y = y - ROW
  end

  -- Defaults, bottom left, as in the game's own options --------------------------
  local def = Button(p, "Defaults", 110, 22, function()
    local d = ns.ClassDefaults(ns.model)
    db().settings, db().rotation = d.settings, d.rotation
    O.Changed(true)
  end)
  def:SetPoint("BOTTOMLEFT", MARGIN - 4, 14)
  Tip(def, "Defaults", "Put every setting in this window back to its starting value.")
  O.controls.Defaults = def

  BuildSpellsPane(O.panes.spells)
  BuildTooltipsPane(O.panes.tooltips)
  Tabs(frame)
  frame:Hide()
  O.frame = frame
  O.ShowTab("settings")
end

-- The status line: how many of your known spell ranks the model matches against
-- the game's own spell tooltips (the same check as /hm check).
local function Status(S)
  local rows = S and S.info and S.info.client or {}
  local ok, off, none = 0, {}, 0
  for _, r in ipairs(rows) do
    if not r.client then none = none + 1
    elseif math.abs(r.client - r.model) <= 1 then ok = ok + 1
    else off[#off + 1] = r end
  end
  local read = #rows - none
  local help = "Every spell rank you know is compared with the game's own spell tooltip " ..
    "(which includes your healing power and talents). A match means the model heals exactly " ..
    "what the game says."
  if read == 0 then
    return "|cff9d9d9dSpell check: waiting for the game's spell tooltips.|r", help
  end
  if #off == 0 then
    return string.format("|cff40ff40Matches the game:|r %d of %d spell ranks.", ok, read), help
  end
  local lines = {}
  for _, r in ipairs(off) do
    lines[#lines + 1] = string.format("%s %d: game %.0f, model %.0f", E.SPELLS[r.key].name, r.rank, r.client, r.model)
  end
  return string.format("|cffffb000%d of %d spell ranks differ from the game|r (hover for details)", #off, read),
    help .. "\n\nDifferent:\n" .. table.concat(lines, "\n") .. "\n\n/hm check prints this in chat."
end

-- Fill in every control and the live result. force: rebuild from the game now.
function O.Refresh(force)
  if not O.frame then return end
  for _, f in ipairs(O.rows) do f() end
  local S = ns.State(force)
  local w = S and S.weights
  for _, c in ipairs(O.weightCells) do c.name:SetText(""); c.value:SetText("") end
  if not w then
    O.hps:SetText("")
    local why = not S and "No data yet."
      or S.st.invalid and ("|cffff5050Could not read:|r " .. table.concat(S.info.how.missing, ", "))
      or "No model at your level yet: the playstyle's main spell isn't known."
    O.hpsNote:SetText(why)
    O.result:SetText("")
  else
    O.hps:SetText(string.format("%d HPS", w.base.ehps + 0.5))
    O.hpsNote:SetText(string.format("|cff9d9d9dafter overheal  -  %d before|r", w.base.hps + 0.5))
    O.result:SetText("Worth the same as 1 healing power")
    local h = w.healing ~= 0 and w.healing or 1
    local stats = {
      { "mp5", w.mp5 / h }, { "Intellect", w.int / h }, { "Spirit", w.spirit / h },
      { "1% crit", w.crit / h }, { "1% haste", w.haste / h }, { "Healing power", 1 },
    }
    table.sort(stats, function(a, b) return a[2] > b[2] end)
    for i, c in ipairs(O.weightCells) do
      local st = stats[i]
      c.name:SetText("|cff9d9d9d" .. st[1] .. "|r")
      c.value:SetText(string.format(st[1] == "Healing power" and "|cffffffff%.2f|r" or "|cffffffff%.2f|r", st[2]))
    end
  end
  if O.spellRows then O.FillSpells(S) end
  local st, help = Status(S)
  O.status:SetText(st)
  O.statusHelp = help
end

local function fmtInt(n) return tostring(math.floor((n or 0) + 0.5)) end

-- The Your spells tab.
local function spellName(key) return E.SPELLS[key] and E.SPELLS[key].name or key end

function O.FillSpells(S)
  local fl = db().settings.fightLength
  -- Spell overview
  local rows = S and S.spells or {}
  for i, row in ipairs(O.spellRows) do
    local sr = rows[i]
    local c = row.cells
    if sr then
      c[1]:SetText("|cffffffff" .. sr.name .. "|r")
      c[2]:SetText(tostring(sr.top))
      c[3]:SetText(fmtInt(sr.topHeal))
      c[4]:SetText(fmtInt(sr.topCost))
      c[5]:SetText(sr.topHPM == math.huge and "free" or string.format("%.2f", sr.topHPM))
      c[6]:SetText(fmtInt(sr.topHPS))
      if sr.bestRank == sr.top then
        c[7]:SetText("|cff9d9d9dyour highest|r")
      else
        c[7]:SetText(string.format("Rank %d  |cff40ff40%.2f|r per mana", sr.bestRank, sr.bestHPM))
      end
      row.spellID, row.title = sr.id, sr.name
    else
      for _, cell in ipairs(c) do cell:SetText("") end
      row.spellID = nil
    end
  end

end

-- A setting changed: recalculate (item tooltips too) and show it. Slider drags
-- fire many times a second, so the recalculation waits for a short pause.
function O.Changed(now)
  ns.MarkDirty()
  if now or not (C_Timer and C_Timer.After) then return O.Refresh(true) end
  if O.pending then return end
  O.pending = true
  C_Timer.After(0.2, function() O.pending = false; O.Refresh(true) end)
end

function O.Toggle()
  Build()
  if O.frame:IsShown() then O.frame:Hide() else O.frame:Show() end
end
