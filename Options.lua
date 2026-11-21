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
     Tabs: Settings (the fight, item tooltips, the result), Your spells, Math.
       typing      InputBoxTemplate (the Math tab's cells)
     Each was checked against addons that already use it on this client (BugSack,
     OpenMap). Where a client lacks one, that widget falls back to a plain version,
     so the window always works.

     The Math tab is a sheet of Models/PriestMath.lua's lines: how each number is
     worked out and where it comes from. Boxed values can be typed over: your own
     value is then used everywhere until you put it back (a line at the bottom of
     every tab says so), and settings typed there (overheal per spell, fight
     length) are the same settings the Settings tab has.

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
-- The Math tab makes the window wider (like the game's character window does for
-- some of its tabs): its formulas need the room.
local MATH_WIDTH = 880
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
               { key = "math", text = "Math" } }

function O.ShowTab(key)
  O.tab = key
  if O.frame and O.frame.SetWidth then O.frame:SetWidth(key == "math" and MATH_WIDTH or WIDTH) end
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
    if self.rankOf then
      if PlaySound then pcall(PlaySound, 856) end
      return O.ShowMath(self.rankOf, self.rankNum)
    end
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
  local hint = Label(pane, "|cff9d9d9dClick a spell to see all its ranks, and a rank to see its math|r", "GameFontHighlightSmall", LEFT, y - 4, W)
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

-- Math: a sheet of how every number in the window is worked out, with your
-- numbers in it and where each one comes from (Models/PriestMath.lua builds the
-- rows; this lays them out). A boxed value can be typed over: a number the model
-- uses becomes yours everywhere (db.overrides, until you put it back), a setting
-- is the same setting as on the Settings tab.
local MATH_COLS = {   -- title, x, width, justify; then the revert icon
  { "Item", 0, 176, "LEFT" }, { "Formula", 176, 520, "LEFT" }, { "Value", 696, 90, "RIGHT" },
}
local REVERT_X = 790
local PAD = 4                       -- text inset in a cell
local MATH_TOP = TOP - 52           -- the sheet's first row (under the column titles)
local MATH_BOTTOM = 40              -- room for the line about your values at the bottom
local YOU = { 0.40, 0.73, 1.00 }

-- A flat colour (the grid's lines, stripes and boxes).
local function Flat(parent, layer, r, g, b, a)
  local t = parent.CreateTexture and parent:CreateTexture(nil, layer or "BACKGROUND")
  if not t then return nil end
  if t.SetColorTexture then t:SetColorTexture(r, g, b, a)
  elseif t.SetTexture then
    t:SetTexture("Interface\\Buttons\\WHITE8x8")
    if t.SetVertexColor then t:SetVertexColor(r, g, b, a) end
  end
  return t
end
local function Recolor(t, r, g, b, a)
  if not t then return end
  if t.SetColorTexture then t:SetColorTexture(r, g, b, a) elseif t.SetVertexColor then t:SetVertexColor(r, g, b, a) end
end
local function Vis(t, on) if t then if on then t:Show() else t:Hide() end end end

-- A box around an editable value (an input cell): dark inside, a 1-pixel frame.
local function Box(row)
  local b = { bg = Flat(row, "BORDER", 0, 0, 0, 0.45) }
  for _, side in ipairs({ "top", "bottom", "left", "right" }) do b[side] = Flat(row, "ARTWORK", 0.5, 0.44, 0.3, 0.9) end
  return b
end
local function PlaceBox(b, row, h)
  local x, w = MATH_COLS[3][2] + 3, MATH_COLS[3][3] - 6
  local y, bh = -2, h - 4
  local function at(t, tx, ty, tw, th)
    if not t then return end
    if t.ClearAllPoints then t:ClearAllPoints() end
    t:SetPoint("TOPLEFT", row, "TOPLEFT", tx, ty)
    t:SetSize(tw, th)
  end
  at(b.bg, x, y, w, bh)
  at(b.top, x, y, w, 1); at(b.bottom, x, y - bh + 1, w, 1)
  at(b.left, x, y, 1, bh); at(b.right, x + w - 1, y, 1, bh)
end
local function ShowBox(b, on, color)
  for _, k in ipairs({ "bg", "top", "bottom", "left", "right" }) do Vis(b[k], on) end
  if on then
    local c = color or { 0.5, 0.44, 0.3 }
    for _, k in ipairs({ "top", "bottom", "left", "right" }) do Recolor(b[k], c[1], c[2], c[3], 0.9) end
  end
end

local function plainText(t) return ((t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- Hover: the whole row, its formula in full, where the number comes from, what a click does.
local function MathTip(owner, row)
  local r = row.data
  if not (r and GameTooltip) or r.head or r.note then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText((r[1] or ""):gsub("^%s+", ""), 1, 1, 1)
  if r[2] and r[2] ~= "" then GameTooltip:AddLine(r[2] .. (r[3] ~= "" and (" = " .. r[3]) or ""), nil, nil, nil, true) end
  local e = r.edit
  if e and e.orig ~= nil then
    GameTooltip:AddLine(string.format("Typed by you. Before: %s (%s).", E.MathFormat(e.unit, e.orig),
      E.MATH_SOURCES[e.origSrc] or "worked out"), YOU[1], YOU[2], YOU[3], true)
  elseif E.MATH_SOURCES[r[4]] then
    GameTooltip:AddLine("Source: " .. E.MATH_SOURCES[r[4]], 0.62, 0.62, 0.62)
  else
    GameTooltip:AddLine("Worked out from the lines above.", 0.62, 0.62, 0.62)
  end
  if r.help then GameTooltip:AddLine(r.help, nil, nil, nil, true) end
  if e and e.id then
    GameTooltip:AddLine(e.orig ~= nil and "Click to change your value; right-click to put back the game's."
      or "Click to type your own value. It is used everywhere: HPS, Your spells, item tooltips.", 0.25, 1, 0.25, true)
  elseif e and e.setting then
    GameTooltip:AddLine("Click to change this setting; right-click for its starting value.", 0.25, 1, 0.25, true)
  end
  GameTooltip:Show()
end

local function MathRow(i)
  local row = CreateFrame("Frame", nil, O.mathChild)
  row:SetSize(O.mathListW, ROW_GAP)
  if row.EnableMouse then row:EnableMouse(true) end
  -- the grid: a band behind section titles, every other row striped, lines between rows and columns
  row.band = Flat(row, "BACKGROUND", 0.55, 0.42, 0.1, 0.30)
  row.stripe = Flat(row, "BACKGROUND", 1, 1, 1, 0.04)
  for _, t in ipairs({ row.band, row.stripe }) do if t then t:SetAllPoints(row) end end
  row.hline = Flat(row, "BORDER", 1, 1, 1, 0.09)
  if row.hline then row.hline:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0); row.hline:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0); row.hline:SetHeight(1) end
  row.vlines = {}
  for n = 2, #MATH_COLS + 1 do
    local x = MATH_COLS[n] and MATH_COLS[n][2] or (MATH_COLS[#MATH_COLS][2] + MATH_COLS[#MATH_COLS][3])
    local v = Flat(row, "BORDER", 1, 1, 1, 0.07)
    if v then
      v:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
      v:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", x, 0)
      v:SetWidth(1)
    end
    row.vlines[#row.vlines + 1] = v
  end
  row.box = Box(row)
  row.cells = {}
  for n, c in ipairs(MATH_COLS) do
    local fs = Cell(row, c[2] + PAD, -3, c[3] - 2 * PAD, c[4])
    if fs.SetWordWrap then fs:SetWordWrap(n == 2) end      -- formulas wrap; the rest stay on one line
    row.cells[n] = fs
  end
  row.wide = Cell(row, PAD, -3, O.mathListW - 2 * PAD, "LEFT")   -- section titles and notes
  if row.wide.SetWordWrap then row.wide:SetWordWrap(true) end
  -- the value cell: click to type, right-click to put back
  local vb = CreateFrame("Button", nil, row)
  vb:SetPoint("TOPLEFT", row, "TOPLEFT", MATH_COLS[3][2], 0)
  vb:SetSize(MATH_COLS[3][3], ROW_GAP)
  if vb.RegisterForClicks then vb:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  vb:SetScript("OnClick", function(_, button)
    if button == "RightButton" then O.MathReset(row) else O.MathEdit(row) end
  end)
  vb:SetScript("OnEnter", function(self) MathTip(self, row) end)
  vb:SetScript("OnLeave", HideTip)
  row.valueBtn = vb
  -- the small revert arrow next to one of your values: puts the game's back
  local x = CreateFrame("Button", nil, row)
  x:SetSize(16, 16)
  x:SetPoint("TOPLEFT", row, "TOPLEFT", REVERT_X, -1)
  if x.SetNormalTexture then pcall(x.SetNormalTexture, x, "Interface\\Buttons\\UI-RefreshButton") end
  if x.SetHighlightTexture then pcall(x.SetHighlightTexture, x, "Interface\\Buttons\\ButtonHilight-Square", "ADD") end
  x:SetScript("OnClick", function() O.MathReset(row) end)
  Tip(x, "Put back", function()
    local e = row.data and row.data.edit
    return e and e.orig ~= nil and ("Use the game's value again: " .. E.MathFormat(e.unit, e.orig) .. ".") or "Use the game's value again."
  end)
  row.resetBtn = x
  row:SetScript("OnEnter", function(self) MathTip(self, row) end)
  row:SetScript("OnLeave", HideTip)
  O.mathRows[i] = row
  return row
end

local function textHeight(fs)
  local h = fs.GetStringHeight and fs:GetStringHeight() or 0
  return (type(h) == "number" and h > 0) and h or 12
end

local function BuildMathPane(pane)
  local W = MATH_WIDTH - 2 * MARGIN
  local y = TOP
  Header(pane, "How the numbers are worked out", LEFT, y)
  Label(pane, "|cff9d9d9dClick a boxed value to type your own (|r|cff66bbffblue|r|cff9d9d9d: yours, used everywhere); " ..
    "right-click it or its arrow to put it back. Hover a line for where its number comes from.|r",
    "GameFontHighlightSmall", LEFT, y - 18, W)
  O.mathListW = W - SCROLL_W
  -- column titles, like a sheet's
  for _, c in ipairs(MATH_COLS) do
    Cell(pane, LEFT + c[2] + PAD, MATH_TOP + 15, c[3] - 2 * PAD, c[4], "GameFontNormalSmall"):SetText(c[1])
  end
  local under = Flat(pane, "BORDER", 1, 0.82, 0, 0.35)
  if under then under:SetPoint("TOPLEFT", pane, "TOPLEFT", LEFT, MATH_TOP); under:SetSize(O.mathListW, 1) end
  local sf = try("ScrollFrame", pane, "UIPanelScrollFrameTemplate") or CreateFrame("ScrollFrame", nil, pane)
  sf:SetPoint("TOPLEFT", pane, "TOPLEFT", LEFT, MATH_TOP)
  sf:SetSize(O.mathListW, HEIGHT + MATH_TOP - MATH_BOTTOM)
  sf.scrollBarHideable = true
  if not sf.ScrollBar and sf.EnableMouseWheel then
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, d)
      local maxS = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
      local v = (self.GetVerticalScroll and self:GetVerticalScroll() or 0) - d * ROW_GAP * 3
      self:SetVerticalScroll(math.max(0, math.min(maxS, v)))
    end)
  end
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(O.mathListW, ROW_GAP)
  if sf.SetScrollChild then sf:SetScrollChild(child) end
  O.mathScroll, O.mathChild, O.mathRows = sf, child, {}
end

-- One edit box for the whole sheet, moved onto the cell you click (the rows are
-- refilled on every change, so a box per row would lose what you are typing).
local function MathEditBox()
  if O.mathEdit then return O.mathEdit end
  local eb = try("EditBox", O.mathChild, "InputBoxTemplate") or CreateFrame("EditBox", nil, O.mathChild)
  if eb.SetAutoFocus then eb:SetAutoFocus(false) end
  if eb.SetFontObject then eb:SetFontObject("GameFontHighlightSmall") end
  if eb.SetJustifyH then eb:SetJustifyH("RIGHT") end
  if eb.SetMaxLetters then eb:SetMaxLetters(20) end
  eb:SetScript("OnEnterPressed", function(self) O.MathCommit(self:GetText()) end)
  eb:SetScript("OnTabPressed", function(self) O.MathCommit(self:GetText()) end)
  eb:SetScript("OnEscapePressed", function() O.MathCancel() end)
  eb:SetScript("OnEditFocusLost", function() O.MathCancel() end)
  eb:Hide()
  O.mathEdit = eb
  return eb
end

local function editing() return O.mathEdit and O.mathEdit.row ~= nil end

function O.MathEdit(row)
  local e = row and row.data and row.data.edit
  if not e then return end
  local eb = MathEditBox()
  if eb.row and eb.row ~= row and eb.row.cells then eb.row.cells[3]:SetText(eb.shown3) end   -- the cell it leaves gets its value back
  eb.row, eb.shown3 = row, row.cells[3].text or (row.cells[3].GetText and row.cells[3]:GetText())
  if eb.SetParent then eb:SetParent(row) end
  if eb.ClearAllPoints then eb:ClearAllPoints() end
  eb:SetPoint("TOPLEFT", row, "TOPLEFT", MATH_COLS[3][2] + 8, 0)   -- the template's frame reaches ~5 px past its text
  eb:SetSize(MATH_COLS[3][3] - 14, math.max(18, row.h or ROW_GAP))
  if eb.SetFrameLevel and row.GetFrameLevel then eb:SetFrameLevel(row:GetFrameLevel() + 5) end
  eb:SetText(E.MathEditText(e.unit, e.raw))
  row.cells[3]:SetText("")
  eb:Show()
  if eb.SetFocus then eb:SetFocus() end
  if eb.HighlightText then eb:HighlightText() end
end

local function closeEdit()
  local eb = O.mathEdit
  if not (eb and eb.row) then return end
  eb.row = nil                                   -- first, so losing focus doesn't cancel twice
  if eb.ClearFocus then eb:ClearFocus() end
  eb:Hide()
end

function O.MathCancel()
  if not editing() then return end
  closeEdit()
  O.FillMath(O.mathState)                       -- puts the value back (and catches up if something changed)
end

local function setSetting(path, v)
  local t = db().settings
  for i = 1, #path - 1 do t[path[i]] = t[path[i]] or {}; t = t[path[i]] end
  t[path[#path]] = v
end

local function complain(msg)
  if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(msg, 1, 0.1, 0.1) end
  if PlaySound then pcall(PlaySound, 846) end
end

-- What you typed into the box: your value, the game's again, or a setting.
function O.MathCommit(text)
  if not editing() then return end
  local row = O.mathEdit.row
  local e = row.data.edit
  local blank = not text or text:match("^%s*$")
  local v = not blank and E.MathParse(e.unit, text)
  if e.id then
    local game = e.orig ~= nil and e.orig or e.raw
    local same = v and (E.MathFormat(e.unit, v) == E.MathFormat(e.unit, game))
    if blank or same then
      db().overrides[e.id] = nil                  -- empty, or the game's own number: back to the game's
    elseif v and E.OverrideOK(e.id, v) then
      db().overrides[e.id] = v
    else
      return complain("Holy Math: " .. tostring(text) .. " can't be used here.")
    end
  elseif e.setting then
    local ok = v and E.MathSettingValue(e.setting, v)
    if not ok then return complain("Holy Math: " .. tostring(text) .. " can't be used for this setting.") end
    setSetting(e.setting, ok)
  end
  closeEdit()
  O.Changed(true)
end

-- Right-click or the x: your value goes, or a setting goes back to its starting value.
function O.MathReset(row)
  local e = row and row.data and row.data.edit
  if not e then return end
  if editing() then closeEdit() end
  if e.id then
    if db().overrides[e.id] == nil then return end
    db().overrides[e.id] = nil
  elseif e.setting then
    local d = ns.ClassDefaults(ns.model).settings
    for _, k in ipairs(e.setting) do d = type(d) == "table" and d[k] or nil end
    if d == nil then return end
    setSetting(e.setting, d)
  end
  O.Changed(true)
end

function O.FillMath(S)
  if not O.mathRows then return end
  O.mathState = S
  if editing() then O.mathStale = true; return end   -- never under your typing
  O.mathStale = false
  local pick = O.mathPick or {}
  local ok, rows = pcall(E.MathPage, S, pick[1], pick[2])
  if not ok then
    if ns.LogError then ns.LogError("math", rows) end
    rows = { { note = "Could not work this out (/hm dump saves the error)." } }
  end
  if #rows == 0 then rows = { { note = "No numbers yet." } } end
  local y, stripe = 0, 0
  O.mathAnchors = {}
  for i, r in ipairs(rows) do
    local row = O.mathRows[i] or MathRow(i)
    row.data = r
    for _, c in ipairs(row.cells) do c:SetText("") end
    row.wide:SetText("")
    local h
    local data = not (r.head or r.note)
    Vis(row.band, r.head); Vis(row.hline, data or r.head)
    for _, v in ipairs(row.vlines) do Vis(v, data) end
    row.valueBtn:Hide(); row.resetBtn:Hide()
    if r.head then
      if i > 1 then y = y + 6 end
      if r.anchor then O.mathAnchors[r.anchor] = y end
      row.wide:SetFontObject("GameFontNormal")
      row.wide:SetText(r.head)
      h = math.max(20, textHeight(row.wide) + 6)
      stripe = 0
      Vis(row.stripe, false); ShowBox(row.box, false)
    elseif r.note then
      row.wide:SetFontObject("GameFontHighlightSmall")
      row.wide:SetText("|cff9d9d9d" .. r.note .. "|r")
      h = textHeight(row.wide) + 6
      Vis(row.stripe, false); ShowBox(row.box, false)
    else
      stripe = stripe + 1
      Vis(row.stripe, stripe % 2 == 0)
      local c, e = row.cells, r.edit
      local mine = e and e.orig ~= nil
      c[1]:SetText((r[1]:gsub("^%s+", ""))); c[2]:SetText("|cffc8c8c8" .. r[2] .. "|r")
      c[3]:SetText(mine and ("|cff66bbff" .. r[3] .. "|r") or ("|cffffffff" .. r[3] .. "|r"))
      row.src = r[4]
      -- sub-lines (two leading spaces) sit indented under their line
      if c[1].ClearAllPoints then c[1]:ClearAllPoints() end
      local indent = r[1]:match("^%s%s") and 10 or 0
      c[1]:SetPoint("TOPLEFT", PAD + indent, -3); c[1]:SetWidth(MATH_COLS[1][3] - 2 * PAD - indent)
      h = math.max(ROW_GAP + 2, textHeight(c[2]) + 6)
      if e then
        PlaceBox(row.box, row, h)
        ShowBox(row.box, true, mine and YOU or nil)
        row.valueBtn:SetHeight(h); row.valueBtn:Show()
        if mine then row.resetBtn:Show() end
      else
        ShowBox(row.box, false)
      end
    end
    row.h = h
    if row.ClearAllPoints then row:ClearAllPoints() end
    row:SetPoint("TOPLEFT", O.mathChild, "TOPLEFT", 0, -y)
    row:SetHeight(h)
    row:Show()
    y = y + h
  end
  for i = #rows + 1, #O.mathRows do O.mathRows[i]:Hide(); O.mathRows[i].data = nil end
  O.mathChild:SetHeight(math.max(1, y))
  O.mathSpellY = pick[1] and O.mathAnchors["spell:" .. pick[1] .. ":" .. tostring(pick[2])] or nil
  return rows
end

-- Show the Math tab: a rank clicked on Your spells (key, rank), or a section
-- ("settings": overheal and the other assumptions), scrolled to it.
function O.ShowMath(key, rank, anchor)
  if key then O.mathPick = { key, rank } end
  O.ShowTab("math")
  O.FillMath(O.spellState or ns.State())
  local sf = O.mathScroll
  local function scroll()
    local y = O.mathAnchors and (anchor and O.mathAnchors[anchor] or (not anchor and O.mathSpellY))
    if sf and sf.SetVerticalScroll and y then
      local range = sf.GetVerticalScrollRange and sf:GetVerticalScrollRange() or y
      sf:SetVerticalScroll(math.min(y, math.max(0, range or 0)))
    end
  end
  if sf and sf.UpdateScrollChildRect then pcall(sf.UpdateScrollChildRect, sf) end
  scroll()
  if C_Timer and C_Timer.After then C_Timer.After(0, scroll) end   -- the range catches up a frame later
end

-- At the bottom of every tab while any of your values is in use.
local function YourValuesLine(frame)
  local b = CreateFrame("Frame", nil, frame)
  b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -MARGIN + 4, 14)
  b:SetSize(470, 22)
  local reset = Button(b, "Put all back", 104, 22, function()
    if editing() then closeEdit() end
    db().overrides = {}
    O.Changed(true)
  end)
  reset:SetPoint("RIGHT", b, "RIGHT", 0, 0)
  O.controls.ResetValues = reset
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("RIGHT", reset, "LEFT", -8, 0)
  fs:SetJustifyH("RIGHT")
  b.text = fs
  local hit = CreateFrame("Frame", nil, b)
  hit:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  hit:SetSize(470 - 110, 22)
  if hit.EnableMouse then hit:EnableMouse(true) end
  local function list()
    local lines = {}
    for id, v in pairs(db().overrides or {}) do
      if E.OverrideOK(id, v) then lines[#lines + 1] = E.OverrideLabel(id) .. ": " .. E.MathFormat(E.OverrideUnit(id), v) end
    end
    table.sort(lines)
    return "Values you typed on the Math tab, used instead of the game's in every number " ..
      "(HPS, stat values, Your spells, item tooltips):\n\n" .. table.concat(lines, "\n")
  end
  Tip(hit, "Your values", list)
  Tip(reset, "Put all back", "Use the game's own values again everywhere. Your settings stay as they are.")
  b:Hide()
  O.yourValues = b
end

function O.FillYourValues()
  local b = O.yourValues
  if not b then return end
  local n = ns.OverrideCount and ns.OverrideCount() or 0
  if n == 0 then b:Hide(); return end
  b.text:SetText(string.format("|cff66bbff%d value%s typed by you on the Math tab %s in every number|r",
    n, n == 1 and "" or "s", n == 1 and "is" or "are"))
  b:Show()
end

-- Item tooltips, on the Settings tab: the line, and what it shows.
-- (Holy Math leaves spell tooltips alone: the game's own already shows the heal.)
local function TooltipSettings(p, x, y)
  local tips = function() return db().tooltips end
  local function opt(id, oy, label, help, key)
    Check(p, id, x, oy, label, help,
      function() return tips()[key] ~= false end, function(v) tips()[key] = v end)
  end
  Header(p, "Item tooltips", x, y)
  opt("tipItems", y - 24, "Show Holy Math on item tooltips",
    "A line on item tooltips with how much the item gains or loses you in healing per second, " ..
    "worked out by running the whole model with it equipped.", "items")
  opt("tipItemNumber", y - 48, "Show the number (+16.2 HPS)", "The change in healing per second.", "itemNumber")
  opt("tipItemPct", y - 72, "Show it in % (+1.8%)", "The change as a share of your healing per second.", "itemPercent")
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

  O.panes = { settings = Pane(p), spells = Pane(p), math = Pane(p) }
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

  -- Overheal per spell lives on the Math tab, with every other number the model uses
  y = y - 40
  Header(p, "Overheal", LEFT, y)
  Label(p, "Overheal per spell, and every other number the model uses, are on the Math tab.",
    "GameFontHighlightSmall", LEFT, y - 20, COL_W)
  local ohb = Button(p, "Set overheal", 130, 22, function() O.ShowMath(nil, nil, "settings") end)
  ohb:SetPoint("TOPLEFT", p, "TOPLEFT", LEFT - 2, y - 52)
  Tip(ohb, "Set overheal", "Opens the Math tab at your settings: overheal per spell, fight length and the model's other assumptions.")
  O.controls.SetOverheal = ohb

  -- Right column: the result -------------------------------------------------
  y = TOP
  Header(p, "Result", RIGHT, y)
  -- big "93 HPS", and what it was before overheal
  O.hps = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  O.hps:SetPoint("TOPLEFT", RIGHT, y - 22)
  O.hps:SetJustifyH("LEFT")
  O.hps:SetText("")
  O.hpsNote = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  O.hpsNote:SetPoint("BOTTOMLEFT", O.hps, "BOTTOMRIGHT", 8, 1)   -- follows the number, however wide
  O.hpsNote:SetJustifyH("LEFT")
  O.hpsNote:SetText("")
  local rhit = CreateFrame("Frame", nil, p)
  rhit:SetPoint("TOPLEFT", RIGHT, y - 20)
  rhit:SetSize(COL_W, 22)
  rhit:EnableMouse(true)
  Tip(rhit, "HPS (healing per second)",
    "What you heal per second over the fight set on the left, with your current stats, talents " ..
    "and spells, after the overheal you expect. Updates by itself when your gear, buffs, talents " ..
    "or these settings change; item tooltips use the same settings.")

  -- stat values, in healing power: two groups, because gear gives intellect, MP5
  -- and spirit by the point but crit and haste by the 1%; each group best first
  --   Worth in healing power
  --   Per point             Per 1%
  --   MP5          1.39     Crit        6.84
  --   Intellect    1.04     Haste       0.35
  --   Spirit       0.31
  O.result = Label(p, "", "GameFontNormalSmall", RIGHT, y - 50, COL_W)
  O.result:SetText("Worth in healing power")
  local whit = CreateFrame("Frame", nil, p)
  whit:SetPoint("TOPLEFT", RIGHT, y - 48)
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
    O.weightHeads[g] = Cell(p, RIGHT + (g - 1) * half, y - 66, half - 16, "LEFT")
    O.weightHeads[g]:SetText("|cff9d9d9d" .. title .. "|r")
  end
  O.weightCells = {}
  for g = 1, 2 do
    for r = 1, 3 do
      local x, ry = RIGHT + (g - 1) * half, y - 80 - (r - 1) * 14
      O.weightCells[#O.weightCells + 1] = { group = g, name = Cell(p, x, ry, 90, "LEFT"),
                                            value = Cell(p, x + 90, ry, half - 16 - 90, "RIGHT") }
    end
  end

  O.status = Label(p, "", "GameFontHighlightSmall", RIGHT, y - 128, COL_W)
  -- only shown when some spell ranks differ from the game (see Status)
  local shit = CreateFrame("Frame", nil, p)
  shit:SetPoint("TOPLEFT", RIGHT, y - 124)
  shit:SetSize(COL_W, 20)
  shit:EnableMouse(true)
  shit:Hide()
  Tip(shit, "Checked against the game", function() return O.statusHelp or "" end)
  O.statusHit = shit

  TooltipSettings(p, RIGHT, TOP - 172)

  -- Defaults, bottom left, as in the game's own options --------------------------
  local def = Button(p, "Defaults", 110, 22, function()
    local d = ns.ClassDefaults(ns.model)
    db().settings, db().rotation, db().tooltips = d.settings, d.rotation, ns.TooltipDefaults()
    O.Changed(true)
  end)
  def:SetPoint("BOTTOMLEFT", MARGIN - 4, 14)
  Tip(def, "Defaults", "Put every setting in this window back to its starting value.")
  O.controls.Defaults = def

  BuildSpellsPane(O.panes.spells)
  BuildMathPane(O.panes.math)
  Tabs(frame)
  YourValuesLine(frame)
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
  if O.mathRows then O.FillMath(S) end
  O.FillYourValues()
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
    row.key, row.spellID, row.title, row.rankOf, row.rankNum = nil, nil, nil, nil, nil
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
      row.rankOf, row.rankNum = l.spell.key, rk.rank
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
