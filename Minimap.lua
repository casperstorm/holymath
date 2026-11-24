--[[ Holy Math - Minimap.lua
     A small button on the minimap's edge, drawn like the game's own: click opens or
     closes the window, right-click opens it at the Consumables tab, drag moves it around
     the minimap. Where it sits and whether it shows are saved for the account
     (HolyMathDB.minimap = { angle, hide }); the Settings tab has the switch, and so
     does /hm minimap. Made at login (Core.lua), for priests only.
]]--

local ADDON, ns = ...
local M = {}
ns.Minimap = M

local ICON = "Interface\\Icons\\Spell_Holy_Renew"

local function settings()
  HolyMathDB = HolyMathDB or {}
  if type(HolyMathDB.minimap) ~= "table" then HolyMathDB.minimap = {} end
  return HolyMathDB.minimap
end

function M.Shown() return not settings().hide end

-- around the minimap's edge, at the saved angle (degrees; 0 = east, counter-clockwise)
local function place(b)
  local a = math.rad(settings().angle or 205)
  local r = ((Minimap.GetWidth and Minimap:GetWidth() or 140) / 2) + 10
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function tip(self)
  if not GameTooltip then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText("Holy Math", 1, 0.82, 0)
  GameTooltip:AddLine("Click: open or close the window.", 1, 1, 1)
  GameTooltip:AddLine("Right-click: the Consumables tab.", 1, 1, 1)
  GameTooltip:AddLine("Drag: move it around the minimap.", 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function open(tab)
  local O = ns.Options
  if not O then return end
  if tab then
    if not (O.frame and O.frame:IsShown()) then O.Toggle() end
    O.ShowTab(tab)
  else
    O.Toggle()
  end
end

function M.Create()
  if M.button or not Minimap then return M.button end
  local b = CreateFrame("Button", "HolyMathMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  if b.SetFrameLevel then b:SetFrameLevel(8) end
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  b:RegisterForDrag("LeftButton")
  if b.SetHighlightTexture then b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight") end
  -- laid out like LibDBIcon's buttons; the icon is masked round so it fills the ring
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(24, 24)
  bg:SetPoint("CENTER", b, "CENTER", 0, 0)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetPoint("CENTER", b, "CENTER", 0, 0)
  if icon.SetMask then
    icon:SetSize(21, 21)
    icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
  else
    icon:SetSize(18, 18)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  end
  b.icon = icon
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(50, 50)
  border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

  b:SetScript("OnClick", function(_, button)
    if GameTooltip then GameTooltip:Hide() end
    open(button == "RightButton" and "consumables" or nil)
  end)
  b:SetScript("OnEnter", tip)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- drag: follow the cursor around the edge
  b:SetScript("OnDragStart", function(self)
    if GameTooltip then GameTooltip:Hide() end
    self:SetScript("OnUpdate", function()
      if not (GetCursorPosition and Minimap.GetCenter) then return end
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap.GetEffectiveScale and Minimap:GetEffectiveScale() or 1
      cx, cy = cx / scale, cy / scale
      settings().angle = math.deg(math.atan2(cy - my, cx - mx))
      place(self)
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  M.button = b
  place(b)
  M.Update()
  return b
end

-- show or hide it as the setting says
function M.Update()
  local b = M.button
  if not b then return end
  if M.Shown() then b:Show() else b:Hide() end
end

function M.SetShown(on)
  settings().hide = (not on) or nil
  M.Update()
end
