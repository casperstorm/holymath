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
     Tabs: Settings (the fight, tooltips, the result), Playstyles (Playstyles.lua: the
     playstyle you use as spell blocks), Math (Your spells first).
     Profiles: a dropdown at the top right, on both tabs (ProfileControls).
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
     (settings, gear, buffs, talents), so there is no Recalculate button. Spell
     numbers are taken from the game by themselves (/hm check shows them), so
     the window never asks you to do anything about them. Your spells (every
     rank, the most efficient one, overheal per spell) is the Math tab's first
     section.
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
local HEIGHT = 560
local PLAYSTYLES_HEIGHT = 720
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

-- The playstyles you can use: the built-ins by name, then yours by name (mine:
-- the index where yours start, or nil).
local function rotationKeys()
  local keys = {}
  local S = ns.State and ns.State()
  local t = S and S.t
  for k, r in pairs(E.ROTATIONS) do
    if not r.sheetOnly and (not r.requires or (t and (t[r.requires] or 0) > 0)) then keys[#keys + 1] = k end
  end
  table.sort(keys, function(a, b)
    local ma, mb = E.ROTATIONS[a].mine and 1 or 0, E.ROTATIONS[b].mine and 1 or 0
    if ma ~= mb then return ma < mb end
    return E.ROTATIONS[a].name:lower() < E.ROTATIONS[b].name:lower()
  end)
  local mine
  for i, k in ipairs(keys) do if E.ROTATIONS[k].mine then mine = i; break end end
  return keys, mine
end


local function planHelp()
  local lines = { "Which spells you mostly cast. Every built-in playstyle uses Prayer of Mending and Penance " ..
    "on cooldown when you have them (and Flash Heal twice a minute with Holy Binding), then:", "" }
  for _, k in ipairs(rotationKeys()) do
    local r = E.ROTATIONS[k]
    lines[#lines + 1] = "|cffffffff" .. r.name .. ":|r " .. (r.help or "")
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Ranks are chosen for you: the ones that heal most with your stats. Build your own, " ..
    "or change these, on the Playstyles tab."
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

-- A playstyle in a menu: its name, "(edited)", and what it heals per second for
-- you now (the window's comparison of every playstyle, S.plans: no extra work).
function O.PlaystyleMenuText(key)
  local r = E.ROTATIONS[key]
  local S = ns.State and ns.State()
  local hps
  for _, p in ipairs(S and S.plans or {}) do if p.key == key then hps = p.ehps end end
  return r.name .. (r.edited and "  |cff9d9d9d(edited)|r" or "") ..
    (hps and string.format("  |cff9d9d9d%d HPS|r", math.floor(hps + 0.5)) or "")
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
    local keys, mine = rotationKeys()
    for i, k in ipairs(keys) do
      local r = E.ROTATIONS[k]
      if i == mine and root.CreateTitle then root:CreateTitle("Yours") end
      local radio = root:CreateRadio(O.PlaystyleMenuText(k), isSelected, setSelected, k)
      if radio and radio.SetTooltip then
        radio:SetTooltip(function(tooltip)
          tooltip:SetText(r.name, 1, 1, 1)
          if r.help then tooltip:AddLine(r.help, nil, nil, nil, true) end
        end)
      end
    end
    if root.CreateDivider then root:CreateDivider() end
    if root.CreateButton then root:CreateButton("Build or change playstyles...", function() O.ShowTab("playstyles") end) end
  end)
  if dd.SetSelectionTranslator then
    dd:SetSelectionTranslator(function() local r = E.ROTATIONS[db().rotation]; return r and r.name or "" end)
  end
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

local TABS = { { key = "settings", text = "Settings" }, { key = "playstyles", text = "Playstyles" }, { key = "math", text = "Math" } }

function O.ShowTab(key)
  O.tab = key
  if O.frame and O.frame.SetWidth then O.frame:SetWidth((key == "math" or key == "playstyles") and MATH_WIDTH or WIDTH) end
  -- the Playstyles tab is taller: the fight view goes under up to 8 blocks
  if O.frame and O.frame.SetHeight then O.frame:SetHeight(key == "playstyles" and PLAYSTYLES_HEIGHT or HEIGHT) end
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

local ROW_GAP = 16                      -- a sheet row's height (taller when its formula wraps)
local SCROLL_W = 26                     -- room for the game's scroll bar at the right

-- The game's own tooltip for a spell rank (hovering a line of Your spells).
local function ShowSpellTip(self)
  if not self.spellID or not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if not (GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID)) then
    GameTooltip:SetText(self.title or "", 1, 1, 1)
  end
  GameTooltip:Show()
end

O.expanded = O.expanded or {}   -- spell key -> its ranks are open in Your spells

local function fmtInt(n) return tostring(math.floor((n or 0) + 0.5)) end
local function fmtHPM(v) return v == math.huge and "free" or string.format("%.2f", v) end

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

-- Math: a sheet of how every number in the window is worked out, with your
-- numbers in it and where each one comes from (Models/PriestMath.lua builds the
-- rows; this lays them out). A boxed value can be typed over: a number the model
-- uses becomes yours everywhere (db.overrides, until you put it back), a setting
-- is the same setting as on the Settings tab.
local MATH_COLS = {   -- title, x, width, justify; then the revert icon
  { "Item", 0, 176, "LEFT" }, { "Formula", 176, 520, "LEFT" }, { "Value", 696, 90, "RIGHT" },
}
local REVERT_X = 790
-- Your spells (the sheet's first section) splits the Formula column into its own
-- columns; a spell's overheal sits in the Value column, as a setting.
local SPELL_COLS = {   -- title, x, width, justify, help
  { "Rank", 176, 44, "RIGHT", "Your highest rank of it." },
  { "Heal", 220, 64, "RIGHT", "One cast, all targets, after your overheal." },
  { "Mana", 284, 56, "RIGHT", "What one cast costs, with your talents." },
  { "Per mana", 340, 66, "RIGHT", "Healing per point of mana." },
  { "Per second", 406, 74, "RIGHT", "Healing per second of casting (instants count a global cooldown)." },
  { "Most efficient", 492, 200, "LEFT", "The rank of it that heals the most per point of mana. Often not your highest.\n\n" ..
    "Under a spell's ranks: how much of your healing power each rank gets. Ranks far below your level get " ..
    "less (down to 10%); the game's tooltip may not show this, but real heals have it." },
}
local SPELL_HELP = "Overheal: healing you expect to be wasted on players already at full health, for the whole spell " ..
  "(every rank). Click it to type your own."
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
  if r.tbl == "cols" then
    GameTooltip:SetText("Your spells", 1, 1, 1)
    for _, c in ipairs(SPELL_COLS) do GameTooltip:AddLine(c[1] .. ": " .. c[5], nil, nil, nil, true) end
    GameTooltip:AddLine(SPELL_HELP, nil, nil, nil, true)
    return GameTooltip:Show()
  end
  GameTooltip:SetText(r.tipTitle or (r[1] or ""):gsub("^%s+", ""), 1, 1, 1)
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
  -- Your spells: its own columns, the game's [+]/[-] and list highlight (quest log, skills)
  row.tcells = {}
  for n, c in ipairs(SPELL_COLS) do
    local left = c[4] == "LEFT" and 12 or 0
    row.tcells[n] = Cell(row, c[2] + PAD + left, -3, c[3] - 2 * PAD - left, c[4])
  end
  local tg = row:CreateTexture(nil, "ARTWORK")
  if tg then tg:SetSize(14, 14); tg:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -1); tg:Hide() end
  row.toggle = tg
  local hl = row:CreateTexture(nil, "ARTWORK")   -- shown on hover by hand (a Frame, not a Button)
  if hl then
    hl:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0); hl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -(O.mathListW - MATH_COLS[3][2]), 0)
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight"); hl:SetBlendMode("ADD"); hl:Hide()
  end
  row.hl = hl
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
    if e and e.setting and e.default ~= nil then return "Back to its starting value: " .. E.MathFormat(e.unit, e.default) .. "." end
    return e and e.orig ~= nil and ("Use the game's value again: " .. E.MathFormat(e.unit, e.orig) .. ".") or "Use the game's value again."
  end)
  row.resetBtn = x
  -- a spell or rank line of Your spells: the game's tooltip; a spell's line also lights up and folds open
  row:SetScript("OnEnter", function(self)
    if self.click then Vis(self.hl, true) end
    if self.spellID then ShowSpellTip(self) else MathTip(self, row) end
  end)
  row:SetScript("OnLeave", function(self) Vis(self.hl, false); HideTip() end)
  row:SetScript("OnMouseUp", function(self) O.MathRowClick(self) end)
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

-- A setting's starting value (what Defaults puts back), or nil.
function O.SettingDefault(path)
  local d = ns.ClassDefaults(ns.model).settings
  for _, k in ipairs(path) do d = type(d) == "table" and d[k] or nil end
  return type(d) == "number" and d or nil
end

-- Right-click or the arrow: your value goes, or a setting goes back to its starting value.
function O.MathReset(row)
  local e = row and row.data and row.data.edit
  if not e then return end
  if editing() then closeEdit() end
  if e.id then
    if db().overrides[e.id] == nil then return end
    db().overrides[e.id] = nil
  elseif e.setting then
    local d = O.SettingDefault(e.setting)
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
  local ok, rows = pcall(E.MathPage, S, nil, nil, O.expanded)
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
    -- rows are reused as the page changes: the spell table's bits start off
    for _, tc in ipairs(row.tcells) do tc:SetText("") end
    Vis(row.toggle, false); Vis(row.hl, false)
    row.click, row.spellID, row.title = nil, nil, nil
    if row.wide.ClearAllPoints then row.wide:ClearAllPoints() end
    row.wide:SetPoint("TOPLEFT", PAD, -3)
    if r.head then
      if i > 1 then y = y + 6 end
      if r.anchor then O.mathAnchors[r.anchor] = y end
      -- a section inside the one before (one cast of each fight spell): lighter, indented
      row.wide:SetFontObject(r.sub and "GameFontNormalSmall" or "GameFontNormal")
      Recolor(row.band, 0.55, 0.42, 0.1, r.sub and 0.14 or 0.30)
      if r.sub then row.wide:SetPoint("TOPLEFT", PAD + 12, -3) end
      row.wide:SetText(r.head)
      h = math.max(20, textHeight(row.wide) + 6)
      stripe = 0
      Vis(row.stripe, false); ShowBox(row.box, false)
    elseif r.tbl == "cols" then
      -- Your spells' column titles (hover: what each one means)
      Vis(row.stripe, false); ShowBox(row.box, false)
      for _, v in ipairs(row.vlines) do Vis(v, true) end
      local c = row.cells
      c[1]:SetText("|cffffd100Spell|r"); c[3]:SetText("|cffffd100Overheal|r")
      if c[1].ClearAllPoints then c[1]:ClearAllPoints() end
      c[1]:SetPoint("TOPLEFT", PAD, -3); c[1]:SetWidth(MATH_COLS[1][3] - 2 * PAD)
      for n, col in ipairs(SPELL_COLS) do row.tcells[n]:SetText("|cffffd100" .. col[1] .. "|r") end
      h = ROW_GAP + 2
      stripe = 0
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
      if r.tbl then
        -- Your spells: a spell (its highest rank) after its [+]/[-], or one of its ranks
        local sr, rk = r.spell, r.rank
        local v = rk or { heal = sr.topHeal, cost = sr.topCost, hpm = sr.topHPM, hps = sr.topHPS }
        local tc = row.tcells
        c[2]:SetText("")
        if not rk then c[1]:SetText("|cffffffff" .. r[1] .. "|r") end
        tc[1]:SetText(rk and "" or tostring(sr.top))
        tc[2]:SetText(fmtInt(v.heal)); tc[3]:SetText(fmtInt(v.cost))
        tc[4]:SetText((rk and rk.best) and ("|cff40ff40" .. fmtHPM(v.hpm) .. "|r") or fmtHPM(v.hpm))
        tc[5]:SetText(fmtInt(v.hps))
        if rk then tc[6]:SetText(rankNote(rk))
        elseif sr.bestRank == sr.top then tc[6]:SetText("|cff9d9d9dyour highest|r")
        else tc[6]:SetText(string.format("Rank %d  |cff40ff40%.2f|r per mana", sr.bestRank, sr.bestHPM)) end
        indent = rk and 30 or 18
        if not rk and row.toggle then
          row.toggle:SetTexture(r.open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
          row.toggle:Show()
        end
        row.click = not rk and { "spell", sr.key } or nil
        row.spellID = rk and rk.id or sr.id
        row.title = sr.name .. (rk and (" (Rank " .. rk.rank .. ")") or "")
      end
      c[1]:SetPoint("TOPLEFT", PAD + indent, -3); c[1]:SetWidth(MATH_COLS[1][3] - 2 * PAD - indent)
      h = math.max(ROW_GAP + 2, textHeight(c[2]) + 6)
      if e then
        PlaceBox(row.box, row, h)
        ShowBox(row.box, true, mine and YOU or nil)
        row.valueBtn:SetHeight(h); row.valueBtn:Show()
        -- the arrow: your value, or a setting changed from its starting value
        if e.setting then e.default = O.SettingDefault(e.setting) end
        if mine or (e.default ~= nil and math.abs(e.raw - e.default) > 1e-9) then row.resetBtn:Show() end
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
  return rows
end

-- A click on a spell's line in Your spells folds its ranks out or in. (A rank's
-- line is only looked at: hover it for the game's tooltip.)
function O.MathRowClick(row)
  local c = row and row.click
  if not c then return end
  if editing() then closeEdit() end
  O.expanded[c[2]] = not O.expanded[c[2]] or nil
  if PlaySound then pcall(PlaySound, O.expanded[c[2]] and 856 or 857) end
  O.FillMath(O.mathState or ns.State())
end

-- Show the Math tab, scrolled to a section ("spells": Your spells; "settings":
-- the fight's other assumptions), or where it was.
function O.ShowMath(anchor)
  O.ShowTab("math")
  O.FillMath(O.mathState or ns.State())
  local sf = O.mathScroll
  local function scroll()
    local y = anchor and O.mathAnchors and O.mathAnchors[anchor]
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

---------------------------------------------------------------------------
-- Potions, on the Settings tab (left column): the potions and runes you drink in
-- a fight and how many of each, grouped by the cooldown they share:
--   Potions
--   Potion cooldown: 3 fit in a 300 s fight
--     Major Mender's Potion     [-]  1  [+]  [Remove]
--     Major Mana Potion         [-]  2  [+]  [Remove]
--   Rune cooldown: 3 fit in a 300 s fight
--     Demonic Rune              [-]  3  [+]  [Remove]
--   [ Add potion...  v ]
--   Best for you: Major Mender's Potion x1, ... (+12.3 HPS)   [Use it]
-- Counts stop at what fits; reaching it means "as many as fit", which then follows
-- the fight length. The model: E.PotionPlan, E.BestPotions (Models/Priest.lua).
---------------------------------------------------------------------------
local MAX_POTIONS = 5
local POTION_HELP = "The potions and runes you drink in a fight. Potions share one cooldown " ..
  "(2 minutes), so together they fit only so many times in a fight: the first in the list gets its count, " ..
  "the next what is left. Runes have their own cooldown, so they come on top.\n\n" ..
  "Mana potions add their average mana to the fight; a Mender's Potion adds its healing for 30 seconds, " ..
  "counted as healing power on average over the fight.\n\nThe best mix of your potions for this fight is " ..
  "shown below the list."

local function potionList() local s = db().settings; s.potions = s.potions or {}; return s.potions end

-- The plan for the list now (how many of each really fit), or nil.
local function potionPlan()
  local S = ns.State()
  if not (S and S.st) then return nil end
  local set = {}
  for k, v in pairs(S.input.settings) do set[k] = v end
  set.potions = potionList()
  return E.PotionPlan(S.st, set)
end

local function planItem(plan, i)
  for _, it in ipairs(plan and plan.items or {}) do if it.index == i then return it end end
end

-- [-] / [+] on row i: up to what is left on its cooldown; reaching that is "all".
function O.PotionStep(i, d)
  local list = potionList()
  local e = list[i]
  if not e then return end
  local plan = potionPlan()
  local it = planItem(plan, i)
  local n = it and it.n or 0
  if d > 0 then
    local g = it and plan.groups[it.def.group]
    local room = g and (g.fits - g.used + n) or n
    if n + 1 >= room then e.n = E.POTION_ALL else e.n = n + 1 end
  else
    e.n = math.max(0, n - 1)
  end
  O.Changed(true)
end

function O.PotionRemove(i)
  table.remove(potionList(), i)
  O.Changed(true)
end

function O.PotionAdd(key)
  local list = potionList()
  if #list >= MAX_POTIONS then return end
  for _, e in ipairs(list) do if e.key == key then return end end
  list[#list + 1] = { key = key, n = E.POTION_ALL }
  O.Changed(true)
end

-- The best counts for your list (cached per state), and how much more they heal.
local bestCache = {}
function O.PotionBest()
  local S = ns.State()
  if not (S and S.weights) then return nil end
  if bestCache.state ~= S then
    local set = {}
    for k, v in pairs(S.input.settings) do set[k] = v end
    set.potions = potionList()
    local ok, best, hps = pcall(E.BestPotions, S.rotation, S.st, S.t, set)
    bestCache = { state = S, best = ok and best or nil, gain = ok and hps and (hps - S.weights.base.ehps) or nil }
    if not ok then ns.LogError("bestPotions", best) end
  end
  return bestCache.best, bestCache.gain
end

function O.PotionUseBest()
  local best = O.PotionBest()
  if not best then return end
  local list = potionList()
  for i, b in ipairs(best) do if list[i] and list[i].key == b.key then list[i].n = b.n end end
  -- an item that takes all that is left on its cooldown follows the fight length
  local plan = potionPlan()
  for i, e in ipairs(list) do
    local it = planItem(plan, i)
    local g = it and plan.groups[it.def.group]
    if g and e.n > 0 and g.used == g.fits and it.n == e.n then
      local after = false
      for j = i + 1, #list do local o = planItem(plan, j); if o and o.def.group == it.def.group and o.n > 0 then after = true end end
      if not after then e.n = E.POTION_ALL end
    end
  end
  O.Changed(true)
end

local function PotionSettings(p, x, y)
  local head = Header(p, "Potions", x, y)
  local hit = CreateFrame("Frame", nil, p)
  hit:SetPoint("TOPLEFT", x, y + 2)
  hit:SetSize(COL_W, 18)
  if hit.EnableMouse then hit:EnableMouse(true) end
  Tip(hit, "Potions", POTION_HELP)
  local rows, groupLines = {}, {}
  for i = 1, MAX_POTIONS do
    local r = { name = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
                count = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") }
    r.name:SetWidth(160); r.name:SetJustifyH("LEFT")
    r.count:SetWidth(30); r.count:SetJustifyH("CENTER")
    r.minus = Button(p, "-", 22, 20, function() O.PotionStep(r.index, -1) end)
    r.plus = Button(p, "+", 22, 20, function() O.PotionStep(r.index, 1) end)
    r.remove = Button(p, "Remove", 62, 20, function() O.PotionRemove(r.index) end)
    r.hit = CreateFrame("Frame", nil, p)
    r.hit:SetSize(160, 20)
    if r.hit.EnableMouse then r.hit:EnableMouse(true) end
    r.hit:SetScript("OnEnter", function(self)
      if not r.item then return end
      local it, def = r.item, r.item.def
      local lines = def.text .. ". " .. (E.POTION_GROUPS[def.group] and E.POTION_GROUPS[def.group].name or "") .. " (2 minutes)."
      if it.tooLow then lines = lines .. "\n\n|cffff5050Needs level " .. def.lvl .. ".|r"
      elseif it.want >= E.POTION_ALL then lines = lines .. "\n\nAs many as fit in the fight (follows the fight length)."
      elseif it.want > it.n then lines = lines .. "\n\n" .. it.want .. " set, " .. it.n .. " fit after the potions above it." end
      ShowTip(self, def.name, lines)
    end)
    r.hit:SetScript("OnLeave", HideTip)
    rows[i] = r
    O.controls["potion:" .. i] = r
  end
  for g = 1, 2 do groupLines[g] = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") end
  O.controls.potionGroups = groupLines

  -- Add potion...: the game's dropdown; every potion you can use, with its worth
  local add = try("DropdownButton", p, "WowStyle1DropdownTemplate")
  if add and add.SetupMenu then
    add:SetWidth(190)
    if add.SetDefaultText then add:SetDefaultText("Add potion...") end
    add:SetupMenu(function(_, root)
      local list = potionList()
      if #list >= MAX_POTIONS then
        if root.CreateTitle then root:CreateTitle("At most " .. MAX_POTIONS .. " potions") end
        return
      end
      local S = ns.State()
      local level = S and S.st and S.st.level or 60
      local have = {}
      for _, e in ipairs(list) do have[e.key] = true end
      local groups = {}
      for key, g in pairs(E.POTION_GROUPS) do groups[#groups + 1] = { key = key, g = g } end
      table.sort(groups, function(a, b) return a.g.order < b.g.order end)
      for _, gr in ipairs(groups) do
        local any = false
        for _, def in ipairs(E.POTIONS) do
          if def.group == gr.key and not have[def.key] and (def.lvl or 1) <= level then
            if not any and root.CreateTitle then root:CreateTitle(gr.g.name) end
            any = true
            local label = def.name
            if not O.quietMenu and S and S.weights then
              local ok, v = pcall(E.PotionValue, S.rotation, S.st, S.t, S.input.settings, def.key)
              if ok and v then label = string.format("%s  |cff9d9d9d%+.1f HPS|r", def.name, v) end
            end
            local b = root:CreateButton(label, function() O.PotionAdd(def.key) end)
            if b and b.SetTooltip then
              b:SetTooltip(function(tooltip)
                tooltip:SetText(def.name, 1, 1, 1)
                tooltip:AddLine(def.text .. ".", nil, nil, nil, true)
                tooltip:AddLine("HPS: what it adds used as often as it fits, instead of the others on its cooldown.", 0.6, 0.6, 0.6, true)
              end)
            end
          end
        end
      end
    end)
    O.controls.potionAdd = add
  end

  -- Best for you: ... [Use it]
  local best = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  best:SetWidth(COL_W - 70); best:SetJustifyH("LEFT")
  local use = Button(p, "Use it", 62, 20, function() O.PotionUseBest() end)
  Tip(use, "Use it", "Set the counts to the best mix of your potions for this fight.")
  O.controls.potionBest, O.controls.potionUseBest, O.potionBestText = best, use, best

  O.rows[#O.rows + 1] = function()
    local list = potionList()
    local plan = potionPlan()
    local fl = db().settings.fightLength
    -- display order: by cooldown group, then as listed
    local order = {}
    for i, e in ipairs(list) do
      local def = E.POTION_BY_KEY[e.key]
      if def then order[#order + 1] = { i = i, def = def } end
    end
    table.sort(order, function(a, b)
      local ga, gb = E.POTION_GROUPS[a.def.group].order, E.POTION_GROUPS[b.def.group].order
      if ga ~= gb then return ga < gb end
      return a.i < b.i
    end)
    for _, r in ipairs(rows) do
      r.index, r.item = nil, nil
      for _, w in ipairs({ r.name, r.count, r.minus, r.plus, r.remove, r.hit }) do w:Hide() end
    end
    for _, gl in ipairs(groupLines) do gl:Hide() end
    local ly, gi, lastGroup = y - 22, 0, nil
    for n, o in ipairs(order) do
      if n > MAX_POTIONS then break end
      if o.def.group ~= lastGroup then
        lastGroup = o.def.group
        gi = gi + 1
        local gl = groupLines[gi]
        if gl then
          local g = plan and plan.groups[o.def.group]
          gl:ClearAllPoints(); gl:SetPoint("TOPLEFT", p, "TOPLEFT", x, ly)
          gl:SetText(string.format("%s: %d fit in a %d s fight", E.POTION_GROUPS[o.def.group].name,
            g and g.fits or E.PotionFits(fl, o.def.group), fl))
          gl:Show()
          ly = ly - 16
        end
      end
      local r, it = rows[n], planItem(plan, o.i)
      r.index, r.item = o.i, it
      r.name:ClearAllPoints(); r.name:SetPoint("TOPLEFT", p, "TOPLEFT", x + 8, ly - 4)
      r.hit:ClearAllPoints(); r.hit:SetPoint("TOPLEFT", p, "TOPLEFT", x + 8, ly)
      r.minus:ClearAllPoints(); r.minus:SetPoint("TOPLEFT", p, "TOPLEFT", x + 170, ly)
      r.count:ClearAllPoints(); r.count:SetPoint("TOPLEFT", p, "TOPLEFT", x + 192, ly - 4)
      r.plus:ClearAllPoints(); r.plus:SetPoint("TOPLEFT", p, "TOPLEFT", x + 222, ly)
      r.remove:ClearAllPoints(); r.remove:SetPoint("TOPLEFT", p, "TOPLEFT", x + 250, ly)
      if it and it.tooLow then
        r.name:SetText("|cff9d9d9d" .. o.def.name .. " (level " .. o.def.lvl .. ")|r")
        r.count:SetText("")
      else
        r.name:SetText(o.def.name)
        r.count:SetText(tostring(it and it.n or 0))
        r.minus:Show(); r.plus:Show(); r.count:Show()
        local g = it and plan.groups[o.def.group]
        if r.plus.SetEnabled then r.plus:SetEnabled(g ~= nil and g.used < g.fits) end
        if r.minus.SetEnabled then r.minus:SetEnabled((it and it.n or 0) > 0) end
      end
      r.name:Show(); r.remove:Show(); r.hit:Show()
      ly = ly - 22
    end
    if #order == 0 then
      groupLines[1]:ClearAllPoints(); groupLines[1]:SetPoint("TOPLEFT", p, "TOPLEFT", x, ly)
      groupLines[1]:SetText("No potions: add the ones you drink in a fight."); groupLines[1]:Show()
      ly = ly - 16
    end
    if add and add.SetupMenu then
      add:ClearAllPoints(); add:SetPoint("TOPLEFT", p, "TOPLEFT", x, ly - 4)
      if add.SetEnabled then add:SetEnabled(#list < MAX_POTIONS) end
      if add.GenerateMenu then O.quietMenu = true; pcall(add.GenerateMenu, add); O.quietMenu = false end
      ly = ly - 32
    end
    -- the best mix of these potions, when it differs from yours
    best:Hide(); use:Hide()
    local b, gain = O.PotionBest()
    if b and plan then
      local differs = false
      for _, e in ipairs(b) do
        local idx
        for i, l in ipairs(list) do if l.key == e.key then idx = i end end
        local it = idx and planItem(plan, idx)
        if (it and it.n or 0) ~= e.n then differs = true end
      end
      best:ClearAllPoints(); best:SetPoint("TOPLEFT", p, "TOPLEFT", x, ly - 4)
      if differs and gain and gain > 0.05 then
        local parts = {}
        for _, e in ipairs(b) do
          local def = E.POTION_BY_KEY[e.key]
          if def and e.n > 0 then parts[#parts + 1] = def.name .. " x" .. e.n end
        end
        best:SetText(string.format("Best for you: %s |cff40ff40(%+.1f HPS)|r",
          #parts > 0 and table.concat(parts, ", ") or "none", gain))
        use:ClearAllPoints(); use:SetPoint("TOPLEFT", p, "TOPLEFT", x + COL_W - 62, ly)
        use:Show()
      else
        best:SetText("|cff9d9d9dThese counts are the best mix of your potions for this fight.|r")
      end
      best:Show()
    end
  end
end

-- Tooltips, on the Settings tab: the item line and what it shows, and the spell line.
local function TooltipSettings(p, x, y)
  local tips = function() return db().tooltips end
  local function opt(id, oy, label, help, key)
    Check(p, id, x, oy, label, help,
      function() return tips()[key] ~= false end, function(v) tips()[key] = v end)
  end
  Header(p, "Tooltips", x, y)
  opt("tipItems", y - 24, "Show Holy Math on item tooltips",
    "A line on item tooltips with how much the item gains or loses you in healing per second, " ..
    "worked out by running the whole model with it equipped.", "items")
  opt("tipItemNumber", y - 48, "Show the number (+16.2 HPS)", "The change in healing per second.", "itemNumber")
  opt("tipItemPct", y - 72, "Show it in % (+1.8%)", "The change as a share of your healing per second.", "itemPercent")
  opt("tipSpells", y - 96, "Show Holy Math on spell tooltips",
    "A line on the tooltips of the healing spells you know: what that rank heals per mana and per second " ..
    "after the overheal you expect, and which of your ranks is the most efficient (heals the most per mana). " ..
    "The same numbers as Your spells on the Math tab.\n\nThe game's own spell tooltip can leave out " ..
    "downranking (in dungeons especially), so these are worked out by Holy Math, not read from it.", "spells")
end

---------------------------------------------------------------------------
-- Profiles (Core.lua ns.Profiles): top right of the window, on both tabs.
--   Profile  [ 3 bounces  v ]
-- The menu lists every profile with what it heals per second on your gear now
-- (hover: how it differs from your settings), then New / Rename / Delete. The
-- loaded profile saves itself: every change goes into it (Core.lua P.Sync). Names are asked for in the game's own popup (StaticPopup). Without the
-- game's dropdown (WowStyle1) there are no profiles in the window; /hm profile
-- still works.
---------------------------------------------------------------------------
local function editBoxOf(dialog)
  return dialog and ((dialog.GetEditBox and dialog:GetEditBox()) or dialog.editBox or dialog.EditBox)
end

-- Ask for a name; accept(name) returns an error text to ask again with, or nil.
function O.AskName(prompt, default, accept)
  if not (StaticPopupDialogs and StaticPopup_Show) then return end
  StaticPopupDialogs.HOLYMATH_PROFILE_NAME = StaticPopupDialogs.HOLYMATH_PROFILE_NAME or {
    text = "%s", button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
    hasEditBox = true, maxLetters = ns.Profiles.MAX_NAME, timeout = 0, whileDead = true,
    hideOnEscape = true, preferredIndex = 3,
    OnShow = function(self, data)
      local eb = editBoxOf(self)
      if eb then eb:SetText(data and data.default or ""); if eb.HighlightText then eb:HighlightText() end end
    end,
    OnAccept = function(self, data) data.done(editBoxOf(self) and editBoxOf(self):GetText()) end,
    EditBoxOnEnterPressed = function(eb, data)
      if StaticPopup_Hide then StaticPopup_Hide("HOLYMATH_PROFILE_NAME") end
      data.done(eb:GetText())
    end,
    EditBoxOnEscapePressed = function() if StaticPopup_Hide then StaticPopup_Hide("HOLYMATH_PROFILE_NAME") end end,
  }
  local data = { default = default }
  data.done = function(text)
    local problem = accept(text)
    if problem then   -- ask again, saying why
      local again = function() O.AskName(problem .. "\n\n" .. prompt, text, accept) end
      if C_Timer and C_Timer.After then C_Timer.After(0, again) else again() end
    end
  end
  StaticPopup_Show("HOLYMATH_PROFILE_NAME", prompt, nil, data)
end

local function nameProblem(name, except)
  local P = ns.Profiles
  local clean = P.CleanName(name)
  if not clean then return "|cffff5050A name needs 1 to " .. P.MAX_NAME .. " letters.|r" end
  for _, n in ipairs(P.List()) do
    if n ~= except and n:lower() == clean:lower() then return "|cffff5050There is already a profile called \"" .. n .. "\".|r" end
  end
end

function O.NewProfile()
  O.AskName("Name for a new profile with your settings now:", "", function(text)
    local problem = nameProblem(text)
    if problem then return problem end
    ns.Profiles.Save(text)
    O.Changed(true)
  end)
end

function O.RenameProfile(old)
  O.AskName("New name for \"" .. old .. "\":", old, function(text)
    local problem = nameProblem(text, old)
    if problem then return problem end
    ns.Profiles.Rename(old, text)
    O.Changed(true)
  end)
end

function O.DeleteProfile(name)
  if not (StaticPopupDialogs and StaticPopup_Show) then return end
  StaticPopupDialogs.HOLYMATH_PROFILE_DELETE = StaticPopupDialogs.HOLYMATH_PROFILE_DELETE or {
    text = "Delete the profile \"%s\"? Your settings now stay as they are.",
    button1 = DELETE or "Delete", button2 = CANCEL or "Cancel",
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
    OnAccept = function(_, data) ns.Profiles.Delete(data); O.Changed(true) end,
  }
  StaticPopup_Show("HOLYMATH_PROFILE_DELETE", name, nil, name)
end

local PROFILE_HELP = "Keep several sets of settings under names and switch between them here: the fight, " ..
  "playstyle, Prayer of Mending bounces, Mana Tide, potions, Inspiration, and the overheal you set per spell " ..
  "on the Math tab. The loaded profile saves itself: whatever you change goes into it.\n\nThe list shows what each profile heals per second with your gear now, so you can " ..
  "compare them without switching; hover one to see how it differs from your settings.\n\n" ..
  "Values you typed over the game's on the Math tab (your stats, talents) are not part of a profile. " ..
  "/hm profile <name> loads one from a macro."

local function profileTip(tooltip, name)
  local P = ns.Profiles
  tooltip:SetText(name, 1, 1, 1)
  local h = P.HPS(name)
  if h then tooltip:AddLine(string.format("%s HPS with your gear now", fmtInt(h)), 0.25, 1, 0.25) end
  local diff = P.Diff(name)
  if name == P.Loaded() then
    tooltip:AddLine("Loaded: what you change is saved into it.", nil, nil, nil, true)
  elseif #diff == 0 then
    tooltip:AddLine("The same as your settings now.", nil, nil, nil, true)
  else
    tooltip:AddLine("Differs from your settings now:", nil, nil, nil, true)
    for _, l in ipairs(diff) do tooltip:AddLine("  " .. l, 1, 1, 1) end
  end
end

local function ProfileControls(frame)
  local dd = try("DropdownButton", frame, "WowStyle1DropdownTemplate")
  if not (dd and dd.SetupMenu) then return end
  local P = ns.Profiles
  dd:SetSize(190, 26)
  dd:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -MARGIN, -30)
  local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("RIGHT", dd, "LEFT", -8, 0)
  label:SetText("Profile")
  if dd.SetDefaultText then dd:SetDefaultText("None") end
  local function isSelected(name) return P.Loaded() == name end
  local function setSelected(name) P.Load(name); O.Changed(true) end
  dd:SetupMenu(function(_, root)
    local names = P.List()
    if #names == 0 and root.CreateTitle then root:CreateTitle("No profiles yet") end
    for _, n in ipairs(names) do
      -- the window's refresh only needs the closed field's text: no model runs then
      local h = not O.quietMenu and P.HPS(n) or nil
      local radio = root:CreateRadio(h and string.format("%s  |cff9d9d9d%s HPS|r", n, fmtInt(h)) or n, isSelected, setSelected, n)
      if radio and radio.SetTooltip then radio:SetTooltip(function(tooltip) profileTip(tooltip, n) end) end
    end
    if not root.CreateButton then return end
    if root.CreateDivider then root:CreateDivider() end
    root:CreateButton("New profile...", O.NewProfile)
    local cur = P.Loaded()
    if cur then
      root:CreateButton("Rename \"" .. cur .. "\"...", function() O.RenameProfile(cur) end)
      root:CreateButton("Delete \"" .. cur .. "\"...", function() O.DeleteProfile(cur) end)
    end
  end)
  -- the closed field: the loaded profile's name, without its HPS
  if dd.SetSelectionTranslator then dd:SetSelectionTranslator(function() return P.Loaded() or "None" end) end
  Tip(dd, "Profiles", PROFILE_HELP)
  O.controls.profile = dd
  -- (the menu itself is built again, with the HPS, each time it opens)
  O.rows[#O.rows + 1] = function()
    if dd.GenerateMenu then O.quietMenu = true; pcall(dd.GenerateMenu, dd); O.quietMenu = false end
  end
end

-- "Holy Math 1.0.1", from the .toc (the packager writes the release's version
-- there; a copy straight from the repository still has its placeholder).
function O.VersionText()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = false, nil
  if get then ok, v = pcall(get, ADDON, "Version") end
  if not ok or type(v) ~= "string" or v == "" then return "Holy Math" end
  if v:find("@", 1, true) then return "Holy Math (development copy)" end
  return "Holy Math " .. v
end

-- The window's own pieces, for the Playstyles tab (Playstyles.lua).
O.UI = { try = try, Button = Button, Tip = Tip, ShowTip = ShowTip, HideTip = HideTip, Label = Label, Header = Header,
         Check = Check, Flat = Flat, complain = complain, editBoxOf = editBoxOf, LEFT = LEFT, TOP = TOP }

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

  O.panes = { settings = Pane(p), playstyles = Pane(p), math = Pane(p) }
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
  Slider(p, "group", LEFT, y, "People reached by\ngroup heals",
    "How many people your Prayer of Healing and Holy Nova reach per cast. 5 is a full party (Prayer of Healing " ..
    "heals your party; Holy Nova, whoever is close to you). Set fewer for a smaller or spread-out group.\n\n" ..
    "Overheal (Math tab) is then for those of them already at full health.",
    function() return db().settings.groupHits or 5 end, function(v) db().settings.groupHits = v end,
    1, 5, 1, tostring)
  y = y - ROW
  Slider(p, "tides", LEFT, y, "Mana Tide totems",
    "Shaman Mana Tide Totems that reach you in a fight. Each restores about 1,160 mana, " ..
    "once every 5 minutes. Set 0 if your group has no shaman.",
    function() return db().settings.manaTidesInGroup end, function(v) db().settings.manaTidesInGroup = v end,
    0, 3, 1, tostring)
  y = y - ROW - 2
  Check(p, "insp", LEFT, y, "Count Inspiration (tank armor after crits)",
    function()
      return "Inspiration (a Holy talent) raises the tank's armor for a while after your heals crit. " ..
        "When this is on, the damage that prevents is counted as healing." ..
        (O.hasInspiration == false and "\n\n|cffff5050You don't have the talent, so this does nothing.|r" or "")
    end,
    function() return db().settings.includeInspiration end, function(v) db().settings.includeInspiration = v end)

  -- the potions and runes you drink, and how many of each
  y = y - 40
  PotionSettings(p, LEFT, y)

  -- Your spells and their overheal live on the Math tab, with every other number
  -- the model uses (right column, under the tooltips)
  y = TOP - 172 - 140
  Header(p, "Spells and overheal", RIGHT, y)
  Label(p, "Your spells, their ranks and the overheal you expect per spell are at the top of the Math tab.",
    "GameFontHighlightSmall", RIGHT, y - 20, COL_W)
  local ohb = Button(p, "Your spells", 130, 22, function() O.ShowMath("spells") end)
  ohb:SetPoint("TOPLEFT", p, "TOPLEFT", RIGHT - 2, y - 52)
  Tip(ohb, "Your spells", "Opens the Math tab at Your spells: every healing spell you know, all its ranks, " ..
    "the most efficient one, and the overheal you expect for it.")
  O.controls.YourSpells = ohb

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

  TooltipSettings(p, RIGHT, TOP - 172)

  -- Defaults, bottom left, as in the game's own options --------------------------
  local def = Button(p, "Defaults", 110, 22, function()
    local d = ns.ClassDefaults(ns.model)
    db().settings, db().rotation, db().tooltips = d.settings, d.rotation, ns.TooltipDefaults()
    O.Changed(true)
  end)
  def:SetPoint("BOTTOMLEFT", MARGIN - 4, 14)
  Tip(def, "Defaults", "Put every setting in this window back to its starting value " ..
    "(in the loaded profile too, if one is loaded).")
  O.controls.Defaults = def
  -- which version this is, next to it
  local ver = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ver:SetPoint("LEFT", def, "RIGHT", 12, 0)
  ver:SetText(O.VersionText())
  O.version = ver

  BuildMathPane(O.panes.math)
  if O.BuildPlaystyles then O.BuildPlaystyles(O.panes.playstyles) end
  Tabs(frame)
  YourValuesLine(frame)
  ProfileControls(frame)
  frame:Hide()
  O.frame = frame
  O.ShowTab("settings")
end

-- Fill in every control and the live result. force: rebuild from the game now.
function O.Refresh(force)
  if not O.frame then return end
  for _, f in ipairs(O.rows) do f() end
  local S = ns.State(force)
  local w = S and S.weights
  -- Inspiration's checkbox is greyed out without the talent (then the setting does nothing)
  local insp = O.controls.insp
  if insp then
    O.hasInspiration = S and S.t and (S.t.inspiration or 0) > 0 or false
    if insp.SetEnabled then insp:SetEnabled(O.hasInspiration)
    elseif insp.Enable then if O.hasInspiration then insp:Enable() else insp:Disable() end end
    if insp.Text and insp.Text.SetFontObject then
      insp.Text:SetFontObject(O.hasInspiration and GameFontHighlightSmall or GameFontDisableSmall)
    end
  end
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
  if O.mathRows then O.FillMath(S) end
  if O.FillPlaystyles and O.tab == "playstyles" then
    local ok, err = pcall(O.FillPlaystyles, S)
    if not ok and ns.LogError then ns.LogError("playstyles", err) end
  end
  O.FillYourValues()
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
