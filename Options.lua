--[[ Holy Math - Options.lua
     A small window for /hm, built from Blizzard's own UI pieces so it looks like
     the default UI:
       window      PortraitFrameTemplate (title bar, portrait, close button)
       numbers     MinimalSliderWithSteppersTemplate (the slider from the game's options panel)
       on/off      UICheckButtonTemplate
       playstyle   WowStyle1DropdownTemplate (the game's dropdown). Chosen by the user
                   knowing it once tainted the Group Finder's menu (ADDON_ACTION_BLOCKED
                   on Search(), 20 Nov 2026); our look-alike is the fallback.
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

-- label  [ Renew filler            v ]
-- Our own dropdown, drawn with the game's dropdown art (the same atlases
-- WhatsTraining and Polestar use on Forever), with our own pop-up list. Used
-- only when the game's dropdown template is missing (see PlaystyleDropdown).
local function hasAtlas(name)
  return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function atlasTexture(frame, layer, atlas, useSize)
  local t = frame:CreateTexture(nil, layer)
  if not t then return nil end
  if hasAtlas(atlas) then
    t:SetAtlas(atlas, useSize)
    return t, true
  end
  return t, false
end

-- The game's own geometry (Blizzard_Menu's WowStyle1, as WhatsTraining and
-- OpenMap draw it on Forever): the field's art 7 out round the field, the
-- list's art 10 out at the sides and 3 at top and bottom, its items 20 high,
-- inset 8 at the sides and top and 15 at the bottom.
local FIELD_H, ITEM_H = 22, 20
local LIST_IN = { 8, 8, 8, 15 }   -- left, top, right, bottom

local function PlaystyleLookalike(parent, x, y)
  RowLabel(parent, "Playstyle", x, y, nil, planHelp)
  local W = SLIDER_W + VALUE_W - 4

  -- the closed field
  local box = CreateFrame("Button", nil, parent, "BackdropTemplate")
  -- the art reaches 7 out, so the field sits 7 in: its art then starts with the
  -- sliders' left arrows and ends where their values end. The right edge is
  -- anchored to the fight-length value one row up (same centre line, ROW lower),
  -- so it follows the game's own slider layout.
  local FIELD_W = SLIDER_W + 21
  box:SetHeight(FIELD_H)
  box:SetPoint("LEFT", parent, "TOPLEFT", x + LABEL_W + 7, y - ROW_H / 2)
  local above = O.controls.fight
  local value = above and above.RightText
  if not (value and value.GetJustifyH and value:GetJustifyH() == "RIGHT"
          and pcall(box.SetPoint, box, "RIGHT", value, "RIGHT", -7, -ROW)) then
    box:SetWidth(FIELD_W - 14)
  end
  local bg, ok = atlasTexture(box, "BACKGROUND", "common-dropdown-c-button")
  if bg and ok then
    -- SetAtlas brings the art's own nine-slice; it is drawn 7 out round the field
    bg:SetPoint("TOPLEFT", box, "TOPLEFT", -7, 7)
    bg:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 7, -7)
    local lit = atlasTexture(box, "HIGHLIGHT", "common-dropdown-c-button-hover-1")
    if lit then lit:SetAllPoints(bg); lit:SetBlendMode("ADD") end
  elseif box.SetBackdrop then
    if bg then bg:Hide() end
    box:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    box:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
  end
  local arrow, arrowOk = atlasTexture(box, "ARTWORK", "common-dropdown-a-button", true)
  if arrow then
    if not arrowOk then arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"); arrow:SetSize(20, 20) end
    arrow:SetPoint("RIGHT", box, "RIGHT", 2, 0)
    box.arrow = arrow
  end
  local text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("LEFT", box, "LEFT", 6, 0)
  text:SetPoint("RIGHT", box, "RIGHT", -26, 0)
  text:SetJustifyH("LEFT")
  if text.SetWordWrap then text:SetWordWrap(false) end
  text:SetText("")
  box.label = text
  Tip(box, "Playstyle", planHelp)

  -- the pop-up list
  local list = CreateFrame("Frame", nil, box, "BackdropTemplate")
  list:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -6)
  list:SetFrameStrata("FULLSCREEN_DIALOG")
  list:SetClampedToScreen(true)
  list:EnableMouse(true)
  list:Hide()
  local back, backOk = atlasTexture(list, "BACKGROUND", "common-dropdown-bg")
  if back and backOk then
    back:SetPoint("TOPLEFT", -10, 3)
    back:SetPoint("BOTTOMRIGHT", 10, -3)
    back:SetAlpha(0.925)
  elseif list.SetBackdrop then
    if back then back:Hide() end
    list:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    list:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
  end
  list.items = {}

  local function close() list:Hide() end
  -- a click anywhere else closes it (as WhatsTraining and Polestar do on Forever)
  list:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
  list:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
  list:SetScript("OnEvent", function(self)
    local over = (self.IsMouseOver and self:IsMouseOver()) or (box.IsMouseOver and box:IsMouseOver())
    if not over then self:Hide() end
  end)

  local function width(fs, fallback)
    return fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fallback
  end

  local function build()
    local keys = rotationKeys()
    local S = ns.State()
    local bestKey = S and S.plans and S.plans[1] and S.plans[1].key
    for _, it in ipairs(list.items) do it:Hide() end
    local nameW = 0
    for i, k in ipairs(keys) do
      local it = list.items[i]
      if not it then
        it = CreateFrame("Button", nil, list)
        it:SetHeight(ITEM_H)
        -- the game's list highlight
        local hl = it:CreateTexture(nil, "HIGHLIGHT")
        if hl then hl:SetAllPoints(it); hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight"); hl:SetBlendMode("ADD") end
        local radio, radioOk = atlasTexture(it, "ARTWORK", "common-dropdown-tickradial", true)
        local chk, chkOk = atlasTexture(it, "OVERLAY", "common-dropdown-icon-radialtick-yellow", true)
        it.radio, it.check = radio, chk
        if radio then
          if radioOk then radio:SetPoint("LEFT", it, "LEFT", -3, 0) else radio:Hide() end
        end
        if chk and chkOk then chk:SetPoint("TOPLEFT", radio or it, "TOPLEFT")
        elseif chk then   -- no dropdown art on this client: the classic check mark
          chk:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
          chk:SetSize(16, 16)
          chk:SetPoint("LEFT", it, "LEFT", 0, 0)
        end
        it.text = it:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        it.text:SetPoint("LEFT", it, "LEFT", 20, 0)
        it.text:SetJustifyH("LEFT")
        it:SetScript("OnClick", function(self)
          db().rotation = self.key
          if PlaySound then pcall(PlaySound, 856) end
          close()
          O.Changed(true)
        end)
        it:SetScript("OnEnter", function(self)
          local r = E.ROTATIONS[self.key]
          ShowTip(self, r.name, (r.help or "") .. (self.best and "\n\n|cff40ff40Heals the most for you right now.|r" or ""))
        end)
        it:SetScript("OnLeave", HideTip)
        list.items[i] = it
        O.controls["rot:" .. i] = it
      end
      it.key = k
      it:ClearAllPoints()
      it:SetPoint("TOPLEFT", list, "TOPLEFT", LIST_IN[1], -LIST_IN[2] - (i - 1) * ITEM_H)
      it:SetPoint("TOPRIGHT", list, "TOPRIGHT", -LIST_IN[3], -LIST_IN[2] - (i - 1) * ITEM_H)
      it.best = (k == bestKey)
      it.text:SetText(E.ROTATIONS[k].name)
      if it.check then if k == db().rotation then it.check:Show() else it.check:Hide() end end
      it.selected = (k == db().rotation)
      nameW = math.max(nameW, width(it.text, 170))
      it:Show()
    end
    -- at least as wide as the field, like the game's own lists
    list:SetSize(math.max(box.GetWidth and box:GetWidth() or FIELD_W - 14, LIST_IN[1] + 20 + nameW + 8 + LIST_IN[3]),
      LIST_IN[2] + #keys * ITEM_H + LIST_IN[4])
  end

  box:SetScript("OnClick", function()
    if list:IsShown() then close() else build(); list:Show() end
    if PlaySound then pcall(PlaySound, 856) end
  end)

  O.controls.rot, O.controls.rotList = box, list
  O.rows[#O.rows + 1] = function()
    local r = E.ROTATIONS[db().rotation]
    text:SetText(r and r.name or "")
    if list:IsShown() then build() end
  end
end

-- label  [ Renew filler            v ]   the game's own dropdown (WowStyle1, the
-- menu system). The user chose it on 20 Nov 2026 knowing that it once tainted the
-- Group Finder (ADDON_ACTION_BLOCKED Search()). Its menu is only described when
-- it opens. Without the template: our look-alike above.
local function PlaystyleDropdown(parent, x, y)
  local dd = try("DropdownButton", parent, "WowStyle1DropdownTemplate")
  if not (dd and dd.SetupMenu) then return PlaystyleLookalike(parent, x, y) end
  RowLabel(parent, "Playstyle", x, y, nil, planHelp)
  dd:SetPoint("LEFT", parent, "TOPLEFT", x + LABEL_W, y - ROW_H / 2)
  -- ends where the slider values above and below it end
  local value = O.controls.fight and O.controls.fight.RightText
  if not (value and value.GetJustifyH and value:GetJustifyH() == "RIGHT"
          and pcall(dd.SetPoint, dd, "RIGHT", value, "RIGHT", 0, -ROW)) then
    dd:SetWidth(SLIDER_W + 21)
  end
  local function isSelected(key) return db().rotation == key end
  local function setSelected(key)
    db().rotation = key
    O.Changed(true)
  end
  dd:SetupMenu(function(_, root)
    for _, k in ipairs(rotationKeys()) do
      local r = E.ROTATIONS[k]
      local radio = root:CreateRadio(r.name, isSelected, setSelected, k)
      if radio and radio.SetTooltip then
        radio:SetTooltip(function(tooltip)
          tooltip:SetText(r.name, 1, 1, 1)
          if r.help then tooltip:AddLine(r.help, nil, nil, nil, true) end
        end)
      end
    end
  end)
  Tip(dd, "Playstyle", planHelp)
  O.controls.rot = dd
  -- the closed field shows the selected name; refresh it when the setting changes elsewhere
  O.rows[#O.rows + 1] = function() if dd.GenerateMenu then pcall(dd.GenerateMenu, dd) end end
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
-- the Settings tab.) Click a spell to unfold all its ranks under it, like the
-- game's own collapsible lists; as many as you like, in a list that scrolls.
local OVERVIEW_ROWS, ROW_GAP = 20, 16   -- lines in view
local NAME_X, RANK_X = 16, 30           -- spell names after the [+], rank names indented
local SCROLL_W = 26                     -- room for the game's scroll bar at the right
local OV_COLS = {   -- title, x, width, justify, help
  { "Spell", 0, 150, "LEFT", "Click a spell to see all its ranks." },
  { "Rank", 150, 44, "RIGHT", "Your highest rank of it." },
  { "Heal", 194, 66, "RIGHT", "One cast, all targets, after your overheal setting." },
  { "Mana", 260, 56, "RIGHT", "What one cast costs, with your talents." },
  { "Per mana", 316, 72, "RIGHT", "Healing per point of mana." },
  { "Per second", 388, 80, "RIGHT", "Healing per second of casting (instants count a global cooldown)." },
  { "Most efficient", 468, 166, "RIGHT", "The rank of it that heals the most per point of mana, and how much. Often not your highest.\n\nUnder a spell's ranks: how much of your healing power each rank gets. Ranks far below your level can get less (down to 10%); the game's tooltip may not show this, but real heals have it." },
}

local function ShowSpellTip(self)
  if not self.spellID or not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if not (GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID)) then
    GameTooltip:SetText(self.title or "", 1, 1, 1)
  end
  GameTooltip:Show()
end

O.expanded = O.expanded or {}   -- spell key -> open

local function SpellRow(i)
  local child = O.spellChild
  local row = CreateFrame("Button", nil, child)
  row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * ROW_GAP)
  row:SetSize(O.spellListW, ROW_GAP)
  row:EnableMouse(true)
  -- the game's own [+]/[-] buttons and list highlight (quest log, skills)
  local tg = row:CreateTexture(nil, "ARTWORK")
  if tg then tg:SetSize(14, 14); tg:SetPoint("LEFT", 0, 0) end
  row.toggle = tg
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  if hl then hl:SetAllPoints(row); hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight"); hl:SetBlendMode("ADD") end
  row:SetScript("OnEnter", ShowSpellTip)
  row:SetScript("OnLeave", HideTip)
  row:SetScript("OnClick", function(self)
    if not self.key then return end
    O.expanded[self.key] = not O.expanded[self.key] or nil
    if PlaySound then pcall(PlaySound, O.expanded[self.key] and 856 or 857) end
    O.FillSpells(O.spellState)
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(self) then ShowSpellTip(self) end
  end)
  -- the text lives on the row, so the highlight sits under it
  row.cells = {}
  for n, c in ipairs(OV_COLS) do
    row.cells[n] = Cell(row, c[2] + (n == 1 and NAME_X or 0), -2, c[3] - (n == 1 and NAME_X or 0), c[4])
  end
  O.spellRows[i] = row
  return row
end

local function BuildSpellsPane(pane)
  local W = WIDTH - 2 * MARGIN
  local y = TOP
  Header(pane, "Spell overview", LEFT, y)
  local hint = Label(pane, "|cff9d9d9dClick a spell to see all its ranks|r", "GameFontHighlightSmall", LEFT, y - 4, W)
  hint:SetJustifyH("RIGHT")
  y = y - 22
  for _, c in ipairs(OV_COLS) do
    Cell(pane, LEFT + c[2] + (c[2] == 0 and NAME_X or 0), y, c[3], c[4], "GameFontNormalSmall"):SetText(c[1])
    if c[5] then
      local h = CreateFrame("Frame", nil, pane)
      h:SetPoint("TOPLEFT", LEFT + c[2], y)
      h:SetSize(c[3], 16)
      h:EnableMouse(true)
      Tip(h, c[1], c[5])
    end
  end
  -- the lines scroll inside the game's own scroll frame (its bar at the right)
  O.spellListW = W - SCROLL_W
  local sf = try("ScrollFrame", pane, "UIPanelScrollFrameTemplate") or CreateFrame("ScrollFrame", nil, pane)
  sf:SetPoint("TOPLEFT", pane, "TOPLEFT", LEFT, y - 16)
  sf:SetSize(O.spellListW, OVERVIEW_ROWS * ROW_GAP)
  sf.scrollBarHideable = true       -- the bar shows only when there is more than fits
  if not sf.ScrollBar and sf.EnableMouseWheel then   -- no template: the wheel still scrolls
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, d)
      local maxS = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
      local v = (self.GetVerticalScroll and self:GetVerticalScroll() or 0) - d * ROW_GAP * 3
      self:SetVerticalScroll(math.max(0, math.min(maxS, v)))
    end)
  end
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(O.spellListW, OVERVIEW_ROWS * ROW_GAP)
  if sf.SetScrollChild then sf:SetScrollChild(child) end
  O.spellScroll, O.spellChild = sf, child
  O.spellRows = {}
  for i = 1, OVERVIEW_ROWS do SpellRow(i) end
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
    "(MP5, spirit, intellect) is worth more; in short fights healing power counts most.",
    function() return db().settings.fightLength end, function(v) db().settings.fightLength = v end,
    30, 900, 30, function(v) return v .. " s" end)
  y = y - ROW
  PlaystyleDropdown(p, LEFT, y)
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

  -- stat values, in healing power: two groups, because gear gives intellect, MP5
  -- and spirit by the point but crit and haste by the 1%; each group best first
  --   Worth in healing power
  --   Per point             Per 1%
  --   MP5          1.39     Crit        6.84
  --   Intellect    1.04     Haste       0.35
  --   Spirit       0.31
  O.result = Label(p, "", "GameFontNormalSmall", LEFT, y - 50, COL_W)
  O.result:SetText("Worth in healing power")
  local whit = CreateFrame("Frame", nil, p)
  whit:SetPoint("TOPLEFT", LEFT, y - 48)
  whit:SetSize(COL_W, 74)
  whit:EnableMouse(true)
  Tip(whit, "Stat values",
    "What one of each stat is worth to you right now, counted in healing power: MP5 1.39 means " ..
    "1 MP5 heals as much as 1.39 healing power.\n\nGear gives intellect, MP5 and spirit by the point, " ..
    "but crit and haste by the 1%, so those two are listed per 1%: an item with +1% crit at 6.84 is " ..
    "worth about +7 healing power. Item tooltips weigh a whole item for you.\n\n" ..
    "The values change with your gear, talents, fight length and playstyle.")
  local half = math.floor(COL_W / 2)
  O.weightHeads = {}
  for g, title in ipairs({ "Per point", "Per 1%" }) do
    O.weightHeads[g] = Cell(p, LEFT + (g - 1) * half, y - 66, half - 16, "LEFT")
    O.weightHeads[g]:SetText("|cff9d9d9d" .. title .. "|r")
  end
  O.weightCells = {}
  for g = 1, 2 do
    for r = 1, 3 do
      local x, ry = LEFT + (g - 1) * half, y - 80 - (r - 1) * 14
      O.weightCells[#O.weightCells + 1] = { group = g, name = Cell(p, x, ry, 90, "LEFT"),
                                            value = Cell(p, x + 90, ry, half - 16 - 90, "RIGHT") }
    end
  end

  O.status = Label(p, "", "GameFontHighlightSmall", LEFT, y - 128, COL_W)
  -- only shown when some spell ranks differ from the game (see Status)
  local shit = CreateFrame("Frame", nil, p)
  shit:SetPoint("TOPLEFT", LEFT, y - 124)
  shit:SetSize(COL_W, 20)
  shit:EnableMouse(true)
  shit:Hide()
  Tip(shit, "Checked against the game", function() return O.statusHelp or "" end)
  O.statusHit = shit

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
-- A rank the model got within 1 healing, or within 5% and then took its base
-- heal from the game (so it now matches too), or neither.
local function tooltipMatch(r)
  if math.abs(r.client - r.model) <= 1 then return "match" end
  if r.after and math.abs(r.client - r.after) <= 1 then return "corrected" end
  return "off"
end
ns.TooltipMatch = tooltipMatch

local function Status(S)
  local rows = S and S.info and S.info.client or {}
  local ok, fixed, off, none = 0, {}, {}, 0
  for _, r in ipairs(rows) do
    if not r.client then none = none + 1
    else
      local m = tooltipMatch(r)
      if m == "match" then ok = ok + 1 elseif m == "corrected" then fixed[#fixed + 1] = r else off[#off + 1] = r end
    end
  end
  local read = #rows - none
  local help = "Every spell rank you know is compared with the game's own spell tooltip " ..
    "(which includes your healing power and talents). A match means the model heals exactly " ..
    "what the game says."
  -- The line shows only when something is off: a match is the normal case, and
  -- /hm check prints the whole comparison.
  if read == 0 then return nil, help end
  local function list(title, rs)
    local lines = { title }
    for _, r in ipairs(rs) do
      lines[#lines + 1] = string.format("%s %d: game %.0f, model %.0f", E.SPELLS[r.key].name, r.rank, r.client, r.model)
    end
    return "\n\n" .. table.concat(lines, "\n")
  end
  local close, noPenalty = {}, {}
  for _, r in ipairs(fixed) do if r.tooltipFull then noPenalty[#noPenalty + 1] = r else close[#close + 1] = r end end
  if #noPenalty > 0 then
    local names = {}
    for _, r in ipairs(noPenalty) do names[#names + 1] = E.SPELLS[r.key].name .. " " .. r.rank end
    help = help .. "\n\nThe game's tooltip shows these low ranks at full healing power, but their real heals " ..
      "still get less (downranking). Holy Math uses what they really heal:\n" .. table.concat(names, ", ")
  end
  if #close > 0 then
    help = help .. list("Close, so the game's number is used (the model was within 5%):", close)
  end
  if #off == 0 then return nil, help end
  return string.format("|cffffb000%d of %d spell ranks differ from the game, so these numbers may be off|r (hover)", #off, read),
    help .. list("Different:", off) .. "\n\n/hm check prints this in chat."
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
    O.result:SetText("Worth in healing power")
    local h = w.healing ~= 0 and w.healing or 1
    local groups = {
      { { "MP5", w.mp5 / h }, { "Intellect", w.int / h }, { "Spirit", w.spirit / h } },
      { { "Crit", w.crit / h }, { "Haste", w.haste / h } },
    }
    for _, list in ipairs(groups) do table.sort(list, function(a, b) return a[2] > b[2] end) end
    local used = { 0, 0 }
    for _, c in ipairs(O.weightCells) do
      used[c.group] = used[c.group] + 1
      local st = groups[c.group][used[c.group]]
      if st then
        c.name:SetText(st[1])
        c.value:SetText(string.format("%.2f", st[2]))
      end
    end
  end
  if O.spellRows then O.FillSpells(S) end
  local st, help = Status(S)
  O.status:SetText(st or "")
  O.statusHelp = help
  if st then O.statusHit:Show() else O.statusHit:Hide() end
end

local function fmtInt(n) return tostring(math.floor((n or 0) + 0.5)) end

-- The Your spells tab.
local function spellName(key) return E.SPELLS[key] and E.SPELLS[key].name or key end

local function fmtHPM(v) return v == math.huge and "free" or string.format("%.2f", v) end

-- What the open spell's ranks look like with your stats right now.
local function ranksOf(key, S)
  if not (key and S and S.st and E.SpellRanks) then return {} end
  local ok, r = pcall(E.SpellRanks, key, S.st, S.t, S.input.settings)
  if not ok then if ns.LogError then ns.LogError("spellRanks", r) end; return {} end
  return r or {}
end

local function setNameX(row, x)
  local fs = row.cells[1]
  if row.nameX == x or not fs.ClearAllPoints then return end
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", x, -2)
  row.nameX = x
end

-- What a rank's line says in the last column: how much of your healing power
-- it gets, and (green) whether it is the spell's most efficient rank.
local function rankNote(rk)
  local full = rk.power >= 0.995
  local pct = math.floor(rk.power * 100 + 0.5)
  if rk.best then
    return "|cff40ff40most efficient|r|cff9d9d9d, " .. (full and "full power" or (pct .. "% power")) .. "|r"
  end
  return "|cff9d9d9d" .. (full and "full healing power" or (pct .. "% of your healing power")) .. "|r"
end

function O.FillSpells(S)
  O.spellState = S
  -- one line per spell, and each open spell's ranks under it
  local lines = {}
  for _, sr in ipairs(S and S.spells or {}) do
    lines[#lines + 1] = { spell = sr }
    if O.expanded[sr.key] then
      for _, rk in ipairs(ranksOf(sr.key, S)) do lines[#lines + 1] = { rank = rk, spell = sr } end
    end
  end
  for i = #O.spellRows + 1, #lines do SpellRow(i) end
  if O.spellChild then O.spellChild:SetHeight(math.max(1, #lines) * ROW_GAP) end
  for i, row in ipairs(O.spellRows) do
    local l, c = lines[i], row.cells
    for _, cell in ipairs(c) do cell:SetText("") end
    row.key, row.spellID, row.title = nil, nil, nil
    if row.toggle then row.toggle:Hide() end
    if l then row:Show() else row:Hide() end
    if l and not l.rank then
      local sr = l.spell
      setNameX(row, NAME_X)
      c[1]:SetText("|cffffffff" .. sr.name .. "|r")
      c[2]:SetText(tostring(sr.top))
      c[3]:SetText(fmtInt(sr.topHeal))
      c[4]:SetText(fmtInt(sr.topCost))
      c[5]:SetText(fmtHPM(sr.topHPM))
      c[6]:SetText(fmtInt(sr.topHPS))
      if sr.bestRank == sr.top then
        c[7]:SetText("|cff9d9d9dyour highest|r")
      else
        c[7]:SetText(string.format("Rank %d  |cff40ff40%.2f|r per mana", sr.bestRank, sr.bestHPM))
      end
      row.key, row.spellID, row.title = sr.key, sr.id, sr.name
      if row.toggle then
        row.toggle:SetTexture(O.expanded[sr.key] and "Interface\\Buttons\\UI-MinusButton-Up"
          or "Interface\\Buttons\\UI-PlusButton-Up")
        row.toggle:Show()
      end
    elseif l then
      local rk = l.rank
      setNameX(row, RANK_X)
      c[1]:SetText("Rank " .. rk.rank)
      c[3]:SetText(fmtInt(rk.heal))
      c[4]:SetText(fmtInt(rk.cost))
      c[5]:SetText(rk.best and ("|cff40ff40" .. fmtHPM(rk.hpm) .. "|r") or fmtHPM(rk.hpm))
      c[6]:SetText(fmtInt(rk.hps))
      c[7]:SetText(rankNote(rk))
      row.spellID, row.title = rk.id, l.spell.name .. " (Rank " .. rk.rank .. ")"
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
