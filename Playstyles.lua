--[[ Holy Math - Playstyles.lua
     The Playstyles tab: the playstyle you use, as a stack of spell blocks.

       Playstyle [ Renew filler  v ]   [Copy as new] [Rename] [Delete] [Export] [Import]
       Built-in. Change anything below and it's saved as your edit of it.
       Spells  [PoM][Pen][PWS][Renew][Lesser][Heal][Flash][GH][PoH][Nova]
       [icon] Prayer of Mending   [Best rank v] [On cooldown    v]  (10 s)   [x] On the tank   30 casts  [X]
       [icon] Greater Heal        [Best rank v] [Twice a minute v] [-](30 s)[+] [x] On the tank  8 casts  [X]
       then fill with
       [icon] Renew               [Best rank v]  the rest of the time          [ ] On the tank 112 casts  [X]
       412 HPS after overheal  -  Inspiration up 78% of the time.
                              0:00        0:30        1:00        1:30        2:00
       Waiting for mana          ##   ####    #####   ####      ######   (E.FightTimeline)
       Prayer of Mending      [] 0:00  [] 0:10  [] 0:20  [] 0:30 ...
       Renew                  []======[]======     ...  (Renew's bar: its 15 s)
     The chooser lists every playstyle with what it heals per second for you now.

     Blocks are added by dragging a spell from the row of icons (or from your
     spellbook, which brings its rank) or by clicking an icon; dragged to move,
     dragged out of the list to remove. Every change is saved at once
     (Core.lua ns.Playstyles): a built-in you change becomes "edited", with Put
     default back. The model (Models/Priest.lua, "Playstyles as blocks") runs the
     blocks as it runs the built-ins. Drag and drop is our own (the game has none
     between an addon's frames); right-click a block for the same moves as menu
     items, and the click and the dropdowns do everything without dragging.
]]--

local ADDON, ns = ...
local E = setmetatable({}, { __index = function(_, k) return ns.model and ns.model[k] end })
local O = ns.Options
local U = {}   -- the window's helpers (Options.lua O.UI), taken when the tab is built

local W = 836                       -- the tab's width inside the margins (the window is wider on this tab)
local ROW_H, ICON = 32, 30
local STACK_TOP = -176
local FILL_GAP = 16                 -- room for "then fill with" above the last block
local COL = { name = 40, rank = 196, how = 318, every = 496, tank = 606, casts = 716, remove = 810 }

local FALLBACK_ICONS = {
  POM = "Interface\\Icons\\Spell_Holy_PrayerOfMendingtga", PENANCE = "Interface\\Icons\\Spell_Holy_Penance",
  PWS = "Interface\\Icons\\Spell_Holy_PowerWordShield", RENEW = "Interface\\Icons\\Spell_Holy_Renew",
  LESSER = "Interface\\Icons\\Spell_Holy_LesserHeal", HEAL = "Interface\\Icons\\Spell_Holy_Heal",
  FLASH = "Interface\\Icons\\Spell_Holy_FlashHeal", BH = "Interface\\Icons\\Spell_Holy_FlashHeal",
  GH = "Interface\\Icons\\Spell_Holy_GreaterHeal", POH = "Interface\\Icons\\Spell_Holy_PrayerOfHealing02",
  NOVA = "Interface\\Icons\\Spell_Holy_HolyNova",
}
-- Each block's colour in the fight view.
local BLOCK_RGB = { { 1, 0.82, 0 }, { 0.25, 0.72, 1 }, { 0.3, 0.95, 0.3 }, { 0.75, 0.45, 1 },
                    { 1, 0.55, 0.2 }, { 1, 0.4, 0.55 }, { 0.3, 0.95, 0.85 }, { 0.85, 0.85, 0.85 } }
-- The fight view (as Lorrgs draws a fight): a ruler of time, a row for waiting for
-- mana, then a row per block with each cast's icon and time and a bar for how long
-- it lasts (its cast, or Renew's 15 s).
local RULER_H, LANE_H, LANE_LABEL, LANE_ICON = 14, 18, 150, 14

local function clock(sec)
  sec = math.floor(sec + 0.5)
  return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

local NEED_TEXT = { pom = "needs the Prayer of Mending talent", penance = "needs the Penance talent",
                    bindingHeal = "needs the Holy Binding talent" }
local LIMIT_TEXT = { cooldown = "as often as set", mana = "until mana ran out", time = "no time left" }
local HOW_HELP = "How often you cast it. Blocks higher up are cast first; the last block fills the time and mana " ..
  "that are left.\n\nOn cooldown: whenever it's ready. Keep it up: recast when it runs out. Times a minute or " ..
  "every N seconds: at most that often.\n\nIt's \"at most\": a block runs out early when your mana does."
local TANK_HELP = "Cast on the tank. Only crits on the tank count for Inspiration (more armor for the tank), and " ..
  "with \"Keep Weakened Soul on the tank\" only heals on the tank get Renewed Hope's extra crit. " ..
  "PW:Shield on cooldown on the tank waits for Weakened Soul (15 s).\n\nHow big a heal is doesn't depend on the target."

local function PS() return ns.Playstyles end
local function db() return ns.db end
local function current() return db().rotation end
local function now() return GetTime and GetTime() or 0 end

-- The spell's own icon, from the game; a fixed one if the game can't say.
function O.SpellIcon(spell)
  local sp = E.SPELLS[spell == "BH" and "FLASH" or spell]
  local id = sp and sp.ranks[1] and sp.ranks[1].id
  local tex
  if id and C_Spell and C_Spell.GetSpellTexture then
    local ok, t = pcall(C_Spell.GetSpellTexture, id); if ok then tex = t end
  end
  if not tex and id and GetSpellTexture then
    local ok, t = pcall(GetSpellTexture, id); if ok then tex = t end
  end
  return tex or FALLBACK_ICONS[spell] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Can you cast it now? false and why not ("not learned yet", "needs the Penance talent").
local function usable(spell, S)
  local known = S and S.input and S.input.settings and S.input.settings.known
  local k = spell == "BH" and "FLASH" or spell
  if known and not known[k] then return false, "not learned yet" end
  local need = E.STEP_NEEDS[spell]
  local have = need and S and S.t and S.t[need]
  if need and S and S.t and not (have and have ~= 0) then return false, NEED_TEXT[need] or "needs a talent" end
  return true
end
local function knownTop(spell, S)
  local known = S and S.input and S.input.settings and S.input.settings.known
  return known and known[spell == "BH" and "FLASH" or spell] or nil
end

---------------------------------------------------------------------------
-- Changes to the blocks: each one saves at once (a built-in becomes edited).
---------------------------------------------------------------------------
-- The last block fills the rest; one that stops being last gets the starting
-- "how often" a new block of its spell would.
local function normalize(def)
  local n = #def.steps
  for i, d in ipairs(def.steps) do
    if i < n and d.how == "fill" then
      local f = E.NewStep(d.spell)
      d.how, d.n = f.how, f.n
    elseif i == n then
      d.how, d.n = "fill", nil
    end
  end
  E.FixPlaystyle(def)   -- Flash Heal (Holy Binding) last: plain Flash Heal
end

local function save(def)
  local ok, why = PS().Save(current(), def)
  if not ok then U.complain("Holy Math: " .. tostring(why)) end
  O.Changed(true)
  return ok
end

local function working() return PS().Def(current()) end

-- A new block before block `at` (1 .. #blocks + 1; after the last = the new filler).
-- Without `at`: just above the filler.
function O.StepAdd(spell, rank, at)
  local def = working()
  if not def then return end
  if #def.steps >= E.MAX_STEPS then return U.complain("Holy Math: at most " .. E.MAX_STEPS .. " blocks in a playstyle.") end
  at = math.max(1, math.min(at or #def.steps, #def.steps + 1))
  table.insert(def.steps, at, E.NewStep(spell, rank))
  normalize(def)
  return save(def)
end

-- Block `from` moves to before block `to` (as the list is now; #blocks + 1 = last).
function O.StepMove(from, to)
  local def = working()
  if not (def and def.steps[from]) then return end
  local n = #def.steps
  to = math.max(1, math.min(to, n + 1))
  if to == from or to == from + 1 then return end
  local d = table.remove(def.steps, from)
  if to > from then to = to - 1 end
  table.insert(def.steps, to, d)
  normalize(def)
  return save(def)
end

function O.StepRemove(i)
  local def = working()
  if not (def and def.steps[i]) then return end
  if #def.steps <= 1 then return U.complain("Holy Math: a playstyle needs at least one spell.") end
  table.remove(def.steps, i)
  normalize(def)
  return save(def)
end

local function maxPerMinute(spell) return math.max(1, math.floor(60 / E.StepMinEvery(spell) + 1e-9)) end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- field: "rank" (nil best, "top", or a number), "how", "tank".
function O.StepSet(i, field, value)
  local def = working()
  local d = def and def.steps[i]
  if not d then return end
  if field == "how" then
    local every = E.StepEvery(d) or 30
    d.how = value
    if value == "pm" then d.n = clamp(math.floor(60 / every + 0.5), 1, maxPerMinute(d.spell))
    elseif value == "sec" then d.n = clamp(every, E.StepMinEvery(d.spell), 600)
    else d.n = nil end
  elseif field == "rank" then d.rank = value
  elseif field == "tank" then d.tank = value and true or nil
  end
  return save(def)
end

-- [-] / [+]: one more or fewer a minute, or a second longer or shorter.
function O.StepNudge(i, dir)
  local def = working()
  local d = def and def.steps[i]
  if not (d and (d.how == "pm" or d.how == "sec")) then return end
  if d.how == "pm" then
    d.n = clamp(d.n + dir, 1, maxPerMinute(d.spell))
  else
    local v = dir > 0 and (math.floor(d.n) + 1) or (math.ceil(d.n) - 1)
    d.n = clamp(v, E.StepMinEvery(d.spell), 600)
  end
  return save(def)
end

function O.SetPlaystyleRH(on)
  local def = working()
  if not def then return end
  def.rh = on and true or nil
  return save(def)
end

---------------------------------------------------------------------------
-- Drag and drop: a ghost icon follows the cursor; where it is let go decides.
---------------------------------------------------------------------------
local drag
-- Where the cursor would drop a block: before block i (#blocks + 1: last), or nil
-- when it is off the list (a block dragged there is removed).
function O.DropIndex()
  local stack = O.psStack
  if not (GetCursorPosition and stack and stack.GetTop and stack.GetEffectiveScale) then return nil end
  local x, y = GetCursorPosition()
  local s = stack:GetEffectiveScale() or 1
  x, y = x / s, y / s
  local l, r, t, b = stack:GetLeft(), stack:GetRight(), stack:GetTop(), stack:GetBottom()
  if not (l and r and t and b) or x < l - 30 or x > r + 30 or y > t + 30 or y < b - 30 then return nil end
  local n = O.psShown or 0
  for i = 1, n do
    local row = O.psRows[i]
    local rt, rb = row:GetTop(), row:GetBottom()
    if rt and rb and y > (rt + rb) / 2 then return i end
  end
  return n + 1
end

local function showLine(idx)
  local line = O.psLine
  if not line then return end
  local n = O.psShown or 0
  if not idx or n == 0 then line:Hide(); return end
  line:ClearAllPoints()
  if idx <= n then line:SetPoint("BOTTOMLEFT", O.psRows[idx], "TOPLEFT", 0, -1)
  else line:SetPoint("TOPLEFT", O.psRows[n], "BOTTOMLEFT", 0, 1) end
  line:Show()
end

function O.DragBegin(info)
  drag = info
  local g = O.psGhost
  if g then
    g.icon:SetTexture(O.SpellIcon(info.spell))
    g:Show()
    g:SetScript("OnUpdate", function(self)
      if not GetCursorPosition then return end
      local x, y = GetCursorPosition()
      local s = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
      self:ClearAllPoints()
      self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
      local idx = O.DropIndex()
      showLine(idx)
      if self.SetAlpha then self:SetAlpha((not idx and info.from) and 0.45 or 1) end   -- faded: let go to remove
    end)
  end
  if PlaySound then pcall(PlaySound, 837) end
end

-- Let go: add, move, or (a block dragged off the list) remove. idx: where, for tests.
function O.DragEnd(idx)
  local info = drag
  drag = nil
  O.lastDragEnd = now()
  if O.psGhost then O.psGhost:SetScript("OnUpdate", nil); O.psGhost:Hide() end
  showLine(nil)
  if not info then return end
  if idx == nil then idx = O.DropIndex() end
  if info.from then
    if idx then O.StepMove(info.from, idx) else O.StepRemove(info.from) end
  elseif idx then
    O.StepAdd(info.spell, info.rank, idx)
  end
end

-- A spell let go over the list from the game's own cursor (your spellbook): it
-- comes in at that rank.
function O.ReceiveCursor(idx)
  if not GetCursorInfo then return end
  local kind, a, b, c = GetCursorInfo()
  if kind ~= "spell" then return end
  local id = type(c) == "number" and c or (type(b) == "number" and b) or a
  local key, rank = ns.Game.SpellKeyRank(id)
  if ClearCursor then ClearCursor() end
  if not (key and E.SPELLS[key]) then return U.complain("Holy Math: that isn't a healing spell Holy Math knows.") end
  O.StepAdd(key, rank, idx or O.DropIndex())
end

---------------------------------------------------------------------------
-- The pieces
---------------------------------------------------------------------------
-- A spell icon with the action buttons' border and highlight.
local function IconButton(parent, size)
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
  b:RegisterForDrag("LeftButton")
  if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  return b
end

local function grey(tex, on)
  if tex.SetDesaturated then tex:SetDesaturated(on) end
  if tex.SetVertexColor then if on then tex:SetVertexColor(0.6, 0.6, 0.6) else tex:SetVertexColor(1, 1, 1) end end
end

local function spellTip(owner, spell, rank, extra)
  if not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local sp = E.SPELLS[spell == "BH" and "FLASH" or spell]
  local S = ns.State()
  local r = type(rank) == "number" and rank or knownTop(spell, S) or 1
  local id = sp and sp.ranks[math.min(r, #sp.ranks)] and sp.ranks[math.min(r, #sp.ranks)].id
  if not (id and GameTooltip.SetSpellByID and pcall(GameTooltip.SetSpellByID, GameTooltip, id)) then
    GameTooltip:SetText(E.StepSpellName(spell), 1, 1, 1)
  end
  for _, l in ipairs(extra or {}) do GameTooltip:AddLine(l[1], l[2] or 0.25, l[3] or 1, l[4] or 0.25, true) end
  GameTooltip:Show()
end

-- The game's dropdown, or a plain button that steps through the choices.
-- choices() -> { { text, value, disabled } ... }; get() -> value; set(value).
-- ready() says whether there is anything to show yet: the game's dropdown builds
-- its menu as soon as it is set up, before a row has a block in it.
local function Choice(parent, width, ready, choices, get, set, label, help)
  local raw = { choices = choices, get = get, label = label }
  choices = function() if ready() then return raw.choices() end return {} end
  get = function() if ready() then return raw.get() end end
  label = function() if ready() then return raw.label() end return "" end
  local dd = U.try("DropdownButton", parent, "WowStyle1DropdownTemplate")
  if dd and dd.SetupMenu then
    dd:SetWidth(width)
    dd:SetupMenu(function(_, root)
      for _, c in ipairs(choices()) do
        local r = root:CreateRadio(c[1], function(v) return get() == v end, function(v) set(v) end, c[2])
        if r and c[3] and r.SetEnabled then r:SetEnabled(false) end
      end
    end)
    if dd.SetSelectionTranslator then dd:SetSelectionTranslator(function() return label() end) end
    dd.refresh = function() if dd.GenerateMenu then pcall(dd.GenerateMenu, dd) end end
  else
    dd = U.Button(parent, "", width, 22, function(self, button)
      local list, cur = choices(), get()
      local at = 1
      for i, c in ipairs(list) do if c[2] == cur then at = i end end
      for _ = 1, #list do
        at = (button == "RightButton") and (at - 2) % #list + 1 or at % #list + 1
        if not list[at][3] then break end
      end
      set(list[at][2])
    end)
    if dd.RegisterForClicks then dd:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    dd.refresh = function() if dd.label then dd.label:SetText(label()) else dd:SetText(label()) end end
  end
  if help then U.Tip(dd, help[1], help[2]) end
  return dd
end

local function rankLabel(d, S)
  if d.rank == nil then return "Best rank" end
  if d.rank == "top" then return "Highest rank" end
  return "Rank " .. d.rank
end

local function MakeRow(stack, i)
  local row = CreateFrame("Frame", nil, stack)
  row:SetSize(W, ROW_H)
  if row.EnableMouse then row:EnableMouse(true) end
  row:SetScript("OnReceiveDrag", function() O.ReceiveCursor(i) end)
  row:SetScript("OnMouseUp", function() O.ReceiveCursor(i) end)
  row.stripe = U.Flat(row, "BACKGROUND", 1, 1, 1, 0.05)
  if row.stripe then row.stripe:SetAllPoints(row) end

  local ic = IconButton(row, ICON)
  ic:SetPoint("LEFT", row, "LEFT", 2, 0)
  ic:SetScript("OnDragStart", function() if row.step then O.DragBegin({ from = i, spell = row.step.spell }) end end)
  ic:SetScript("OnDragStop", function() O.DragEnd() end)
  ic:SetScript("OnClick", function(self, button)
    if button == "RightButton" then O.StepMenu(self, i) end
  end)
  ic:SetScript("OnEnter", function(self)
    if not row.step then return end
    spellTip(self, row.step.spell, row.step.rank, {
      { "Drag to move it; drag it off the list to remove it. Right-click: move, make it the filler, remove." } })
  end)
  ic:SetScript("OnLeave", U.HideTip)
  row.iconBtn = ic

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.name:SetPoint("TOPLEFT", row, "TOPLEFT", COL.name, -4)
  row.name:SetWidth(COL.rank - COL.name - 6); row.name:SetJustifyH("LEFT")
  if row.name.SetWordWrap then row.name:SetWordWrap(false) end
  -- hover the name: what the line under it says, in full
  local nameHit = CreateFrame("Frame", nil, row)
  nameHit:SetPoint("TOPLEFT", row, "TOPLEFT", COL.name, 0)
  nameHit:SetSize(COL.rank - COL.name - 6, ROW_H)
  if nameHit.EnableMouse then nameHit:EnableMouse(true) end
  nameHit:SetScript("OnEnter", function(self)
    if not row.step then return end
    local extra = {}
    if row.note then extra[1] = { row.note, 1, 1, 1 } end
    spellTip(self, row.step.spell, row.step.rank, extra)
  end)
  nameHit:SetScript("OnLeave", U.HideTip)
  nameHit:SetScript("OnReceiveDrag", function() O.ReceiveCursor(i) end)
  row.nameHit = nameHit
  row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.sub:SetPoint("TOPLEFT", row, "TOPLEFT", COL.name, -20)
  row.sub:SetWidth(COL.rank - COL.name - 6); row.sub:SetJustifyH("LEFT")
  if row.sub.SetWordWrap then row.sub:SetWordWrap(false) end

  local S0 = function() return ns.State() end
  local hasStep = function() return row.step ~= nil end
  row.rank = Choice(row, 116, hasStep, function()
    local S = S0()
    local list = { { "Best rank", "best" }, { "Highest rank", "top" } }
    local top = knownTop(row.step.spell, S)
    for r = 1, E.StepRankCount(row.step.spell) do
      local learned = not top or r <= top
      list[#list + 1] = { "Rank " .. r .. (learned and "" or "  |cff9d9d9d(not learned)|r"), r }
    end
    return list
  end, function() return row.step.rank == nil and "best" or row.step.rank end,
  function(v) O.StepSet(i, "rank", v ~= "best" and v or nil) end,
  function() return rankLabel(row.step) end,
  { "Rank", "Best rank: the one that heals the most in this playstyle with your stats (Holy Math tries them all). " ..
    "Highest rank: your highest. Or a rank of your choice, e.g. a low rank to keep Inspiration up cheaply." })
  row.rank:SetPoint("LEFT", row, "LEFT", COL.rank, 0)

  row.how = Choice(row, 170, hasStep, function()
    local sp, list = row.step.spell, {}
    if E.StepHasCooldown(sp) then
      list[#list + 1] = { "On cooldown (" .. E.Seconds(E.StepEvery({ spell = sp, how = "cd", tank = row.step.tank })) .. " s)", "cd" }
    end
    if E.StepCanKeepUp(sp) then list[#list + 1] = { "Keep it up (" .. E.Seconds(E.StepEvery({ spell = sp, how = "up" })) .. " s)", "up" } end
    list[#list + 1] = { "At most N times a minute", "pm" }
    list[#list + 1] = { "At most every N seconds", "sec" }
    return list
  end, function() return row.step.how end, function(v) O.StepSet(i, "how", v) end,
  function() return (E.HowText(row.step):gsub("^%l", string.upper)) end, { "How often", HOW_HELP })
  row.how:SetPoint("LEFT", row, "LEFT", COL.how, 0)
  row.fillText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.fillText:SetPoint("LEFT", row, "LEFT", COL.how + 8, 0)
  row.fillText:SetText("the rest of the time")

  row.minus = U.Button(row, "-", 22, 20, function() O.StepNudge(i, -1) end)
  row.minus:SetPoint("LEFT", row, "LEFT", COL.every, 0)
  row.every = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.every:SetPoint("LEFT", row, "LEFT", COL.every + 22, 0)
  row.every:SetWidth(52); row.every:SetJustifyH("CENTER")
  row.plus = U.Button(row, "+", 22, 20, function() O.StepNudge(i, 1) end)
  row.plus:SetPoint("LEFT", row, "LEFT", COL.every + 74, 0)
  U.Tip(row.minus, "Less often", "One fewer a minute, or a second longer between casts.")
  U.Tip(row.plus, "More often", "One more a minute, or a second shorter between casts (never faster than the spell's own cooldown).")

  local tank = U.try("CheckButton", row, "UICheckButtonTemplate")
  if tank and tank.SetChecked then
    tank:SetSize(24, 24)
    tank:SetPoint("LEFT", row, "LEFT", COL.tank, 0)
    if tank.Text then tank.Text:SetText("On the tank"); tank.Text:SetFontObject(GameFontHighlightSmall) end
    if tank.SetHitRectInsets then tank:SetHitRectInsets(0, -70, 0, 0) end
    tank:SetScript("OnClick", function(self) O.StepSet(i, "tank", self:GetChecked() and true or false) end)
  else
    tank = U.Button(row, "", 100, 20, function() if row.step then O.StepSet(i, "tank", not row.step.tank) end end)
    tank:SetPoint("LEFT", row, "LEFT", COL.tank, 0)
    tank.fallback = true
  end
  U.Tip(tank, "On the tank", function()
    local S = ns.State()
    local ip = S and S.weights and S.weights.base and S.weights.base.inspirationParts
    return TANK_HELP .. (ip and string.format("\n\nInspiration is up %d%% of the time now.", math.floor(ip.uptime * 100 + 0.5)) or "")
  end)
  row.tank = tank

  -- casts in the fight; hover: the rank it used and what stopped it
  row.casts = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.casts:SetPoint("RIGHT", row, "LEFT", COL.remove - 8, 0)
  row.casts:SetWidth(COL.remove - COL.casts - 8); row.casts:SetJustifyH("RIGHT")
  local castHit = CreateFrame("Frame", nil, row)
  castHit:SetPoint("LEFT", row, "LEFT", COL.casts, 0)
  castHit:SetSize(COL.remove - COL.casts - 8, ROW_H)
  if castHit.EnableMouse then castHit:EnableMouse(true) end
  U.Tip(castHit, "In the fight", function() return row.castNote end)
  castHit:SetScript("OnReceiveDrag", function() O.ReceiveCursor(i) end)
  row.castHit = castHit

  local rm = CreateFrame("Button", nil, row)
  rm:SetSize(22, 22)
  rm:SetPoint("LEFT", row, "LEFT", COL.remove, 0)
  if rm.SetNormalTexture then
    pcall(rm.SetNormalTexture, rm, "Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    pcall(rm.SetHighlightTexture, rm, "Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
    pcall(rm.SetPushedTexture, rm, "Interface\\Buttons\\UI-GroupLoot-Pass-Down")
  end
  rm:SetScript("OnClick", function() O.StepRemove(i) end)
  U.Tip(rm, "Remove", "Take this block out of the playstyle.")
  row.remove = rm

  O.psRows[i] = row
  O.controls["ps:" .. i] = row
  return row
end

-- Right-click a block: the moves without dragging.
function O.StepMenu(owner, i)
  local n = O.psShown or 0
  local items = {}
  if i > 1 then items[#items + 1] = { "Move up", function() O.StepMove(i, i - 1) end } end
  if i < n then items[#items + 1] = { "Move down", function() O.StepMove(i, i + 2) end } end
  if i < n then items[#items + 1] = { "Make it the filler (last)", function() O.StepMove(i, n + 1) end } end
  if n > 1 then items[#items + 1] = { "Remove", function() O.StepRemove(i) end } end
  O.lastStepMenu = items
  if MenuUtil and MenuUtil.CreateContextMenu then
    pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
      if root.CreateTitle then root:CreateTitle(E.StepSpellName(O.psRows[i].step.spell)) end
      for _, it in ipairs(items) do root:CreateButton(it[1], it[2]) end
    end)
  elseif items[1] then
    items[1][2]()   -- no menus on this client: right-click moves it up (or down from the top)
  end
end

---------------------------------------------------------------------------
-- Popups: export (the line, selected for Ctrl+C), import (paste one), delete
---------------------------------------------------------------------------
function O.ShowExport(key)
  key = key or current()
  local line = PS().Export(key)
  if not line then return end
  O.lastExport = line
  if not (StaticPopupDialogs and StaticPopup_Show) then return print("|cffffd100Holy Math|r: " .. line) end
  StaticPopupDialogs.HOLYMATH_PLAYSTYLE_EXPORT = StaticPopupDialogs.HOLYMATH_PLAYSTYLE_EXPORT or {
    text = "%s", button1 = CLOSE or "Close", hasEditBox = true, editBoxWidth = 350, maxLetters = 0,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnShow = function(self, data)
      local eb = U.editBoxOf(self)
      if eb then eb:SetText(data.line); if eb.HighlightText then eb:HighlightText() end; if eb.SetFocus then eb:SetFocus() end end
    end,
    EditBoxOnEnterPressed = function() if StaticPopup_Hide then StaticPopup_Hide("HOLYMATH_PLAYSTYLE_EXPORT") end end,
    EditBoxOnEscapePressed = function() if StaticPopup_Hide then StaticPopup_Hide("HOLYMATH_PLAYSTYLE_EXPORT") end end,
    -- keep the line as it is, whatever is typed into the box
    EditBoxOnTextChanged = function(eb, data)
      if data and eb:GetText() ~= data.line then eb:SetText(data.line); if eb.HighlightText then eb:HighlightText() end end
    end,
  }
  StaticPopup_Show("HOLYMATH_PLAYSTYLE_EXPORT",
    "\"" .. E.ROTATIONS[key].name .. "\" as a line of text. Press Ctrl+C to copy it, then paste it anywhere; " ..
    "Import on the Playstyles tab (or /hm playstyle import) reads it back.", nil, { line = line })
end

function O.ShowImport(problem, text)
  if not (StaticPopupDialogs and StaticPopup_Show) then return end
  StaticPopupDialogs.HOLYMATH_PLAYSTYLE_IMPORT = StaticPopupDialogs.HOLYMATH_PLAYSTYLE_IMPORT or {
    text = "%s", button1 = "Import", button2 = CANCEL or "Cancel", hasEditBox = true, editBoxWidth = 350, maxLetters = 0,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnShow = function(self, data)
      local eb = U.editBoxOf(self)
      if eb then eb:SetText(data.text or ""); if eb.HighlightText then eb:HighlightText() end end
    end,
    OnAccept = function(self, data) data.done(U.editBoxOf(self) and U.editBoxOf(self):GetText()) end,
    EditBoxOnEnterPressed = function(eb, data)
      if StaticPopup_Hide then StaticPopup_Hide("HOLYMATH_PLAYSTYLE_IMPORT") end
      data.done(eb:GetText())
    end,
    EditBoxOnEscapePressed = function() if StaticPopup_Hide then StaticPopup_Hide("HOLYMATH_PLAYSTYLE_IMPORT") end end,
  }
  local data = { text = text }
  data.done = function(t)
    local key, why = PS().Import(t)
    if not key then
      local again = function() O.ShowImport("|cffff5050" .. tostring(why) .. "|r", t) end
      if C_Timer and C_Timer.After then C_Timer.After(0, again) else again() end
      return
    end
    O.Changed(true)
  end
  StaticPopup_Show("HOLYMATH_PLAYSTYLE_IMPORT", (problem and (problem .. "\n\n") or "") ..
    "Paste a playstyle (a line starting with " .. E.EXPORT_PREFIX .. "). It becomes a new playstyle of yours.", nil, data)
end

function O.NewPlaystyle()
  O.AskName("Name for a new playstyle (it starts with Prayer of Mending and Renew):", "", function(text)
    local problem = PS().NameProblem(text)
    if problem then return "|cffff5050" .. problem .. "|r" end
    local key, why = PS().New(text)
    if not key then return "|cffff5050" .. tostring(why) .. "|r" end
    O.Changed(true)
  end)
end

function O.CopyPlaystyle(key)
  key = key or current()
  local name = E.ROTATIONS[key].name
  O.AskName("Name for a copy of \"" .. name .. "\":", name:sub(1, E.MAX_PLAYSTYLE_NAME - 7) .. " (copy)", function(text)
    local problem = PS().NameProblem(text)
    if problem then return "|cffff5050" .. problem .. "|r" end
    local k, why = PS().Copy(key, text)
    if not k then return "|cffff5050" .. tostring(why) .. "|r" end
    O.Changed(true)
  end)
end

function O.RenamePlaystyle(key)
  key = key or current()
  O.AskName("New name for \"" .. E.ROTATIONS[key].name .. "\":", E.ROTATIONS[key].name, function(text)
    local ok, why = PS().Rename(key, text)
    if not ok then return "|cffff5050" .. tostring(why) .. "|r" end
    O.Changed(true)
  end)
end

local function confirm(which, text, arg, onAccept, button)
  if not (StaticPopupDialogs and StaticPopup_Show) then return end
  StaticPopupDialogs[which] = StaticPopupDialogs[which] or {
    text = text, button1 = button or ACCEPT or "Accept", button2 = CANCEL or "Cancel",
    timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true, preferredIndex = 3,
    OnAccept = function(_, data) data.fn() end,
  }
  StaticPopup_Show(which, arg, nil, { fn = onAccept })
end

function O.DeletePlaystyle(key)
  key = key or current()
  confirm("HOLYMATH_PLAYSTYLE_DELETE", "Delete your playstyle \"%s\"? Whatever uses it (you, your profiles) " ..
    "goes back to Renew filler.", E.ROTATIONS[key].name, function() PS().Delete(key); O.Changed(true) end, DELETE or "Delete")
end

function O.ResetPlaystyle(key)
  key = key or current()
  confirm("HOLYMATH_PLAYSTYLE_RESET", "Put \"%s\" back as Holy Math ships it? Your changes to it are lost.",
    E.ROTATIONS[key].name, function() PS().Reset(key); O.Changed(true) end)
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
local PALETTE_HELP = "Drag a spell into the list where you want it, or click it to add it above the last block. " ..
  "You can drag a spell from your spellbook onto the list too: it comes in at that rank."

-- Which playstyles the chooser lists (built-ins you can use, then yours).
local function chooserKeys()
  local S = ns.State()
  local built, mine = PS().List()
  local out = {}
  for _, k in ipairs(built) do
    local r = E.ROTATIONS[k]
    if not r.requires or (S and S.t and (S.t[r.requires] or 0) > 0) then out[#out + 1] = k end
  end
  return out, mine
end

function O.BuildPlaystyles(pane)
  U = O.UI
  local LEFT, TOP = U.LEFT, U.TOP
  O.psRows = {}

  -- Playstyle [ chooser v ]  and what you can do with it
  U.Header(pane, "Playstyle", LEFT, TOP - 4)
  local dd = U.try("DropdownButton", pane, "WowStyle1DropdownTemplate")
  if dd and dd.SetupMenu then
    dd:SetWidth(230)
    dd:SetPoint("TOPLEFT", pane, "TOPLEFT", LEFT + 78, TOP + 2)
    local function isSel(k) return current() == k end
    local function setSel(k) db().rotation = k; O.Changed(true) end
    dd:SetupMenu(function(_, root)
      local built, mine = chooserKeys()
      for _, k in ipairs(built) do root:CreateRadio(O.PlaystyleMenuText(k), isSel, setSel, k) end
      if #mine > 0 then
        if root.CreateTitle then root:CreateTitle("Yours") end
        for _, k in ipairs(mine) do root:CreateRadio(O.PlaystyleMenuText(k), isSel, setSel, k) end
      end
      if root.CreateDivider then root:CreateDivider() end
      if root.CreateButton then
        root:CreateButton("New playstyle...", O.NewPlaystyle)
        root:CreateButton("Import...", function() O.ShowImport() end)
      end
    end)
    if dd.SetSelectionTranslator then
      dd:SetSelectionTranslator(function() local r = E.ROTATIONS[current()]; return r and r.name or "" end)
    end
    U.Tip(dd, "Playstyle", "The playstyle you use: the one the window's HPS, stat values and item tooltips are " ..
      "worked out with. Below are its blocks, to change; built-ins you change become \"edited\".")
    O.controls.psChooser = dd
  end

  local x = LEFT + W
  local function rightButton(id, text, w, fn, title, help)
    local b = U.Button(pane, text, w, 22, fn)
    x = x - w
    b:SetPoint("TOPLEFT", pane, "TOPLEFT", x, TOP + 1)
    x = x - 6
    U.Tip(b, title or text, help)
    O.controls[id] = b
    return b
  end
  rightButton("psImport", "Import", 74, function() O.ShowImport() end, "Import",
    "Paste a playstyle someone shared (a line starting with " .. "HM1:" .. "). It becomes a new playstyle of yours.")
  rightButton("psExport", "Export", 74, function() O.ShowExport() end, "Export",
    "This playstyle as a short line of text, to paste in Discord or to a guildmate. Import reads it back.")
  rightButton("psCopy", "Copy as new", 100, function() O.CopyPlaystyle() end, "Copy as new",
    "A new playstyle of yours with these blocks, under a name of your choice.")
  local afterCopy = x
  O.controls.psDelete = U.Button(pane, "Delete", 70, 22, function() O.DeletePlaystyle() end)
  O.controls.psDelete:SetPoint("TOPLEFT", pane, "TOPLEFT", afterCopy - 70, TOP + 1)
  U.Tip(O.controls.psDelete, "Delete", "Delete this playstyle of yours.")
  O.controls.psRename = U.Button(pane, "Rename", 74, 22, function() O.RenamePlaystyle() end)
  O.controls.psRename:SetPoint("TOPLEFT", pane, "TOPLEFT", afterCopy - 70 - 6 - 74, TOP + 1)
  U.Tip(O.controls.psRename, "Rename", "Give this playstyle of yours another name.")
  O.controls.psReset = U.Button(pane, "Put default back", 130, 22, function() O.ResetPlaystyle() end)
  O.controls.psReset:SetPoint("TOPLEFT", pane, "TOPLEFT", afterCopy - 130, TOP + 1)
  U.Tip(O.controls.psReset, "Put default back", "This built-in as Holy Math ships it again; your changes to it go.")

  O.psStatus = U.Label(pane, "", "GameFontHighlightSmall", LEFT, TOP - 26, W - 310)

  -- Renewed Hope: keep Weakened Soul on the tank (a rank 1 shield does it)
  U.Check(pane, "psRH", LEFT + W - 290, TOP - 24, "Keep Weakened Soul on the tank (Renewed Hope)",
    function()
      local S = ns.State()
      local has = S and S.t and (S.t.renewedHope or 0) > 0
      return "Discipline's Renewed Hope gives heals on a target with Weakened Soul more crit. On: blocks on the tank " ..
        "get it (put a PW:Shield on the tank in the list to keep Weakened Soul there)." ..
        (has and "" or "\n\n|cffff5050You don't have Renewed Hope (Discipline), so this does nothing for you.|r")
    end,
    function() local def = working(); return def and def.rh end, function(v) O.SetPlaystyleRH(v) end)

  -- Spells: the blocks to drag in
  U.Label(pane, "Spells", "GameFontNormalSmall", LEFT, TOP - 66)
  O.psPalette = {}
  for n, key in ipairs(E.PALETTE) do
    local b = IconButton(pane, 32)
    b:SetPoint("TOPLEFT", pane, "TOPLEFT", LEFT + 52 + (n - 1) * 40, TOP - 56)
    b.icon:SetTexture(O.SpellIcon(key))
    b.key = key
    b:SetScript("OnDragStart", function(self) O.DragBegin({ spell = self.key }) end)
    b:SetScript("OnDragStop", function(self) self.dragEnd = now(); O.DragEnd() end)
    b:SetScript("OnClick", function(self, button)
      if button == "RightButton" then return end
      if self.dragEnd and now() - self.dragEnd < 0.3 then return end   -- the end of its own drag, not a click
      O.StepAdd(self.key)
    end)
    b:SetScript("OnReceiveDrag", function() O.ReceiveCursor() end)
    b:SetScript("OnEnter", function(self)
      local ok, why = usable(self.key, ns.State())
      local extra = { { PALETTE_HELP } }
      if not ok then table.insert(extra, 1, { "Not usable now: " .. why .. ".", 1, 0.31, 0.31 }) end
      spellTip(self, self.key, nil, extra)
    end)
    b:SetScript("OnLeave", U.HideTip)
    O.psPalette[n] = b
    O.controls["psSpell:" .. key] = b
  end
  local hint = U.Label(pane, "|cff9d9d9dDrag spells into the list (or click one). From your spellbook too.|r",
    "GameFontHighlightSmall", LEFT + 52 + #E.PALETTE * 40 + 10, TOP - 66, W - (52 + #E.PALETTE * 40 + 10))

  -- column titles
  local titles = { { "Spell", COL.name }, { "Rank", COL.rank + 4 }, { "How often", COL.how + 4 }, { "Target", COL.tank } }
  for _, t in ipairs(titles) do U.Label(pane, "|cffffd100" .. t[1] .. "|r", "GameFontNormalSmall", LEFT + t[2], STACK_TOP + 16) end
  local ct = U.Label(pane, "|cffffd100In the fight|r", "GameFontNormalSmall", LEFT + COL.casts, STACK_TOP + 16, COL.remove - 8 - COL.casts)
  ct:SetJustifyH("RIGHT")

  -- the stack: rows of blocks, and where a drop would land
  local stack = CreateFrame("Frame", nil, pane)
  stack:SetPoint("TOPLEFT", pane, "TOPLEFT", LEFT, STACK_TOP)
  stack:SetSize(W, E.MAX_STEPS * ROW_H + FILL_GAP)
  if stack.EnableMouse then stack:EnableMouse(true) end
  stack:SetScript("OnReceiveDrag", function() O.ReceiveCursor() end)
  stack:SetScript("OnMouseUp", function() O.ReceiveCursor() end)
  O.psStack = stack
  O.psFillLabel = stack:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  O.psFillLabel:SetText("then fill with")
  local line = U.Flat(stack, "OVERLAY", 1, 0.82, 0, 0.9)
  if line then line:SetSize(W, 2); line:Hide() end
  O.psLine = line
  for i = 1, E.MAX_STEPS do MakeRow(stack, i):Hide() end

  -- the ghost icon that follows the cursor while dragging
  local g = CreateFrame("Frame", nil, UIParent)
  g:SetSize(ICON, ICON)
  g:SetFrameStrata("TOOLTIP")
  g.icon = g:CreateTexture(nil, "OVERLAY")
  g.icon:SetAllPoints(g)
  g:Hide()
  O.psGhost = g

  -- the result
  -- under the last block: the result, then the fight
  O.psResult = U.Label(pane, "", "GameFontHighlight", LEFT, STACK_TOP - E.MAX_STEPS * ROW_H - FILL_GAP - 6, W)

  local f = CreateFrame("Frame", nil, pane)
  f:SetSize(W, RULER_H + (E.MAX_STEPS + 1) * LANE_H)
  f.ticks, f.lines, f.lanes = {}, {}, {}
  local function tipAt(self)
    if not (GetCursorPosition and self.GetLeft and self:GetLeft()) then return end
    local x = GetCursorPosition() / (self:GetEffectiveScale() or 1) - self:GetLeft()
    local lines = O.FightTipAt(self.n, (x - LANE_LABEL) / (W - LANE_LABEL))
    if not lines then U.HideTip(); return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:SetText(lines[1], 1, 1, 1)
    for k = 2, #lines do GameTooltip:AddLine(lines[k], nil, nil, nil, true) end
    GameTooltip:Show()
  end
  for n = 1, E.MAX_STEPS + 1 do      -- waiting for mana, then the blocks
    local lane = CreateFrame("Frame", nil, f)
    lane:SetSize(W, LANE_H)
    lane:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -RULER_H - (n - 1) * LANE_H)
    lane.n = n
    lane.bg = U.Flat(lane, "BACKGROUND", 1, 1, 1, n % 2 == 0 and 0.07 or 0.03)
    if lane.bg then lane.bg:SetAllPoints(lane) end
    lane.icon = lane:CreateTexture(nil, "ARTWORK")
    lane.icon:SetSize(LANE_ICON, LANE_ICON)
    lane.icon:SetPoint("LEFT", lane, "LEFT", 2, 0)
    if lane.icon.SetTexCoord then lane.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    lane.name = lane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lane.name:SetPoint("LEFT", lane, "LEFT", LANE_ICON + 6, 0)
    lane.name:SetWidth(LANE_LABEL - LANE_ICON - 10); lane.name:SetJustifyH("LEFT")
    if lane.name.SetWordWrap then lane.name:SetWordWrap(false) end
    lane.marks, lane.labels, lane.bars = {}, {}, {}
    if lane.EnableMouse then lane:EnableMouse(true) end
    lane:SetScript("OnEnter", function(self) self:SetScript("OnUpdate", tipAt) end)
    lane:SetScript("OnLeave", function(self) self:SetScript("OnUpdate", nil); U.HideTip() end)
    f.lanes[n] = lane
  end
  O.psFight = f
  -- what this is (and isn't): the most healing per second, not how a fight goes
  O.psNote = U.Label(pane, "|cff9d9d9dThis plays for the most healing per second over the whole fight, as if there's " ..
    "always someone to heal. Real fights come in spikes and quiet spells, and other healers share the work: spreading " ..
    "your mana out, or keeping some for the moments that matter, can do more for a kill. A guide, not a rotation.|r",
    "GameFontHighlightSmall", LEFT, 0, W)
  O.psNote:Hide()
end

-- Fill the tab from the playstyle in use and the model's result for it.
function O.FillPlaystyles(S)
  if not O.psRows then return end
  local key = current()
  local r = E.ROTATIONS[key]
  local def = r and PS().Def(key)
  local kind = PS().Kind(key)
  if O.controls.psChooser and O.controls.psChooser.GenerateMenu then pcall(O.controls.psChooser.GenerateMenu, O.controls.psChooser) end
  local function vis(c, on) if c then if on then c:Show() else c:Hide() end end end
  vis(O.controls.psDelete, kind == "mine"); vis(O.controls.psRename, kind == "mine"); vis(O.controls.psReset, kind == "edited")
  local status
  if kind == "mine" then status = "Yours. Every change is saved as you make it."
  elseif kind == "edited" then
    status = "Built-in, edited by you. Put default back to use it as Holy Math ships it." ..
      (PS().DefaultChanged(key) and "  |cffff9020Holy Math's own version has changed since you edited it.|r" or "")
  else status = "Built-in. Change anything below and it is saved as your edit of it (Put default back undoes that)." end
  O.psStatus:SetText(status)
  -- Keep Weakened Soul on the tank: shown with the talent, or when the playstyle
  -- shields (or has it on already); greyed without the talent (it does nothing then)
  local rh = O.controls.psRH
  if rh then
    local has = S and S.t and (S.t.renewedHope or 0) > 0
    local shields = false
    for _, d in ipairs(def and def.steps or {}) do if d.spell == "PWS" then shields = true end end
    if rh.SetChecked then rh:SetChecked(def and def.rh and true or false) end
    vis(rh, has or shields or (def and def.rh))
    if rh.SetEnabled then rh:SetEnabled(has and true or false) end
    if rh.Text and rh.Text.SetFontObject then rh.Text:SetFontObject(has and GameFontHighlightSmall or GameFontDisableSmall) end
    O.psRHGreyed = not has
  end

  for n, b in ipairs(O.psPalette) do
    local ok = usable(b.key, S)
    grey(b.icon, not ok)
  end

  local steps = def and def.steps or {}
  local base = S and S.weights and S.weights.base
  O.psShown = #steps
  for i, row in ipairs(O.psRows) do
    local d = steps[i]
    if not d then row:Hide()
    else
      row.step = d
      local last = (i == #steps)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", O.psStack, "TOPLEFT", 0, -(i - 1) * ROW_H - (last and FILL_GAP or 0))
      if row.stripe then if i % 2 == 0 then row.stripe:Show() else row.stripe:Hide() end end
      row.iconBtn.icon:SetTexture(O.SpellIcon(d.spell))
      local ok, why = usable(d.spell, S)
      grey(row.iconBtn.icon, not ok)
      row.name:SetText(E.StepSpellName(d.spell))
      local warn, short = E.StepWarning(d)
      row.sub:SetText(not ok and ("|cffff5050" .. why .. "|r") or warn and ("|cffff9020" .. short .. "|r") or
        (last and "the filler" or ""))
      -- the whole of it on hover (the line under the name is short)
      row.note = not ok and ("|cffff5050" .. E.StepSpellName(d.spell) .. ": " .. why .. ".|r") or
        warn and ("|cffff9020" .. warn .. "|r") or nil
      row.rank.refresh()
      vis(row.how, not last); vis(row.fillText, last)
      if not last then row.how.refresh() end
      local every = not last and E.StepEvery(d)
      local stepper = d.how == "pm" or d.how == "sec"
      vis(row.minus, stepper and not last); vis(row.plus, stepper and not last)
      row.every:SetText(every and ("(" .. E.Seconds(every) .. " s)") or "")
      if stepper and row.plus.SetEnabled then
        row.plus:SetEnabled(every - E.StepMinEvery(d.spell) > 1e-9)
        row.minus:SetEnabled(d.how ~= "pm" or d.n > 1)
      end
      if row.tank.fallback then
        local t = d.tank and "|cff40ff40On the tank|r" or "|cff9d9d9dAnyone|r"
        if row.tank.label then row.tank.label:SetText(t) else row.tank:SetText(t) end
      else
        row.tank:SetChecked(d.tank and true or false)
      end
      -- (in combat the last result is kept: it may be from before this change)
      local s = base and base.steps and #base.steps == #steps and base.steps[i]
      if s and s.key ~= (d.spell == "BH" and "FLASH" or d.spell) then s = nil end
      if s and s.enabled then
        local casts = s.casts + (s.pauseCasts or 0)
        row.casts:SetText(string.format("%d casts", math.floor(casts + 0.5)))
        row.castNote = string.format("%.1f casts of rank %d in a %d s fight, %s.", casts, s.rank or 0,
          S.input.settings.fightLength or 0, LIMIT_TEXT[s.limit] or "")
      else
        row.casts:SetText(base and "|cff9d9d9dnot cast|r" or "")
        row.castNote = base and "Not cast: " .. (select(2, usable(d.spell, S)) or "no time or mana left for it") .. "." or nil
      end
      vis(row.remove, #steps > 1)
      row:Show()
    end
  end
  if #steps > 0 then
    O.psFillLabel:ClearAllPoints()
    O.psFillLabel:SetPoint("BOTTOMLEFT", O.psRows[#steps], "TOPLEFT", 4, 2)
    O.psFillLabel:Show()
  else
    O.psFillLabel:Hide()
  end

  -- the result, and the best playstyle for you now
  local text
  if not (S and S.weights) then
    text = "|cff9d9d9dNo result: " .. ((S and S.st and S.st.invalid) and "a stat could not be read." or
      "the last block's spell isn't learned yet.") .. "|r"
  else
    text = string.format("%d HPS after overheal", math.floor(base.ehps + 0.5))
    local ip = base.inspirationParts
    if ip then text = text .. string.format("  |cff9d9d9d-|r  Inspiration up %d%% of the time", math.floor(ip.uptime * 100 + 0.5)) end
    text = text .. "."
  end
  O.psResult:SetText(text)

  -- the result and the fight, right under the last block
  local anchor = #steps > 0 and O.psRows[#steps] or O.psStack
  local function place(fs, gap)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
  end
  place(O.psResult, 12)
  local fl = S and S.input and S.input.settings.fightLength
  O.FillFight(S and S.weights and E.FightTimeline(def, base, fl), fl, steps)
end

-- How long a cast's bar is: Renew lasts 15 s on its target; anything else, its cast.
local function barLength(c)
  if E.StepCanKeepUp(c.key) then return E.StepEvery({ spell = c.key, how = "up" }) or c.dur end
  return c.dur
end

-- tl: E.FightTimeline (nil hides the view); steps: the blocks (for names and order).
function O.FillFight(tl, fl, steps)
  local f = O.psFight
  if not f then return end
  O.psTimeline, O.psFightLength = tl, fl
  if not (tl and fl and fl > 0) then f:Hide(); O.psNote:Hide(); return end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", O.psResult, "BOTTOMLEFT", 0, -10)
  f:Show()
  local LW = W - LANE_LABEL
  local scale = LW / fl
  -- the rows: waiting for mana, then each block
  local spec = { { kind = "wait" } }
  for b = 1, #steps do spec[#spec + 1] = { kind = "block", b = b } end
  local lanes = #spec
  f:SetHeight(RULER_H + lanes * LANE_H)
  O.psNote:ClearAllPoints()
  O.psNote:SetPoint("TOPLEFT", f.lanes[lanes], "BOTTOMLEFT", 0, -8)
  O.psNote:Show()

  -- the ruler: every 30 s (a minute in long fights), a faint line down through the rows
  for _, x in ipairs(f.ticks) do x:Hide() end
  for _, x in ipairs(f.lines) do x:Hide() end
  local step = fl > 300 and 60 or 30
  local n = 0
  for sec = 0, fl + 1e-9, step do
    n = n + 1
    local tk = f.ticks[n]
    if not tk then tk = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); f.ticks[n] = tk end
    local ln = f.lines[n]
    if not ln then ln = U.Flat(f, "BORDER", 1, 1, 1, 0.12); f.lines[n] = ln end
    local x = LANE_LABEL + sec * scale
    tk:SetText(clock(sec))
    tk:ClearAllPoints()
    if sec >= fl - 1e-9 then tk:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0) else tk:SetPoint("TOP", f, "TOPLEFT", x, 0) end
    tk:Show()
    if ln then
      ln:ClearAllPoints()
      ln:SetPoint("TOPLEFT", f, "TOPLEFT", math.min(x, W - 1), -RULER_H + 2)
      ln:SetSize(1, lanes * LANE_H + 2)
      ln:Show()
    end
  end

  -- the rows: waiting for mana, then each block
  local byBlock = {}
  for _, c in ipairs(tl.casts) do
    byBlock[c.block] = byBlock[c.block] or {}
    table.insert(byBlock[c.block], c)
  end
  for li, lane in ipairs(f.lanes) do
    -- pairs, not ipairs: times are only made where they fit, so that list has gaps
    for _, list in ipairs({ lane.marks, lane.labels, lane.bars }) do for _, x in pairs(list) do x:Hide() end end
    local sp = spec[li]
    lane.kind, lane.block = sp and sp.kind, sp and sp.b
    if not sp then lane:Hide()
    else
      lane:Show()
      -- runs: casts back to back are one bar, with an icon and time where it starts
      local runs, rgb = {}, nil
      if sp.kind == "wait" then
        lane.icon:Hide()
        lane.name:SetText("|cffff6060Waiting for mana|r")
        rgb = { 0.85, 0.15, 0.15 }
        for _, w in ipairs(tl.waits) do
          if w[2] - w[1] >= 0.5 then runs[#runs + 1] = { t = w[1], e = w[2] } end
        end
      else
        local b = sp.b
        local d = steps[b]
        lane.icon:SetTexture(O.SpellIcon(d.spell)); lane.icon:Show()
        lane.name:SetText(E.StepSpellName(d.spell))
        rgb = BLOCK_RGB[(b - 1) % #BLOCK_RGB + 1]
        -- one icon per cast (back to back they overlap: spammed); a bar only for what
        -- lasts after the cast (Renew's 15 s on its target)
        for _, c in ipairs(byBlock[b] or {}) do
          runs[#runs + 1] = { t = c.t, e = c.t + (E.StepCanKeepUp(c.key) and barLength(c) or 0), key = c.key, cast = c }
        end
      end
      lane.runs, lane.scale = runs, scale
      for k, run in ipairs(runs) do
        local x = LANE_LABEL + run.t * scale
        local nextX = runs[k + 1] and (LANE_LABEL + runs[k + 1].t * scale) or W
        local lead = sp.kind ~= "wait" and LANE_ICON + 2 or 2
        local labelled = nextX - x - lead >= 30          -- room for its time before the next one
        local bar = run.e > run.t and lane.bars[k]
        if run.e > run.t and not bar then bar = U.Flat(lane, "ARTWORK", 1, 1, 1, 1); lane.bars[k] = bar end
        if bar then
          if bar.SetColorTexture then bar:SetColorTexture(rgb[1], rgb[2], rgb[3], sp.kind == "wait" and 0.45 or 0.3) end
          bar:ClearAllPoints()
          bar:SetPoint("TOPLEFT", lane, "TOPLEFT", x, -2)
          bar:SetSize(math.max(2, math.min(W - x, (math.min(run.e, fl) - run.t) * scale)), LANE_H - 4)
          bar:Show()
        end
        if sp.kind ~= "wait" then
          local mk = lane.marks[k]
          if not mk then
            mk = lane:CreateTexture(nil, "OVERLAY")
            if mk.SetTexCoord then mk:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
            lane.marks[k] = mk
          end
          mk:SetTexture(O.SpellIcon(run.key))
          mk:ClearAllPoints()
          mk:SetPoint("LEFT", lane, "LEFT", math.min(x, W - LANE_ICON), 0)
          mk:SetSize(LANE_ICON, LANE_ICON)
          mk:Show()
        end
        -- its time, when there's room before the next one
        if labelled then
          local lb = lane.labels[k]
          if not lb then lb = lane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); lane.labels[k] = lb end
          lb:SetText(clock(run.t))
          lb:ClearAllPoints()
          lb:SetPoint("LEFT", lane, "LEFT", x + lead, 0)
          lb:Show()
        end
      end
    end
  end
end

-- What a row shows at a point (0..1 across the fight): tooltip lines, or nil.
function O.FightTipAt(laneIndex, frac)
  local tl, fl, f = O.psTimeline, O.psFightLength, O.psFight
  local lane = f and f.lanes[laneIndex]
  if not (tl and fl and lane and lane.runs) or frac < 0 or frac > 1 then return nil end
  local sec = frac * fl
  local foot = "|cff9d9d9dThe casts this playstyle counts, placed by priority: an example of the fight, " ..
    "not the only way to play it.|r"
  local iconSec = LANE_ICON / (lane.scale or 1)          -- how much of the fight an icon covers
  for k = #lane.runs, 1, -1 do                            -- the last drawn is on top
    local run = lane.runs[k]
    local reach = lane.kind == "wait" and run.e or math.max(run.e, run.t + iconSec)
    if sec >= run.t and sec < reach then
      if lane.kind == "wait" then
        return { clock(run.t) .. " - " .. clock(run.e) .. "  waiting for mana",
                 "Nothing is due and there's no mana for the filler: your mana comes back while you wait " ..
                 "(spirit only after 5 s without casting).", foot }
      end
      local c1 = run.cast
      local name = E.StepSpellName(run.key) .. (c1 and c1.rank and (" (rank " .. c1.rank .. ")") or "")
      local lines = { clock(run.t) .. "  " .. name }
      -- casts right after each other: say how many in a row
      local n, k2 = 1, k
      while lane.runs[k2 + 1] and lane.runs[k2 + 1].t <= lane.runs[k2].t + (lane.runs[k2].cast and lane.runs[k2].cast.dur or 0) + 0.05 do
        n, k2 = n + 1, k2 + 1
      end
      if n > 1 then lines[#lines + 1] = string.format("The first of %d in a row.", n) end
      if run.e > run.t then lines[#lines + 1] = "The bar: how long it lasts on its target." end
      if c1 and c1.pause then lines[#lines + 1] = "After a wait: your mana had to come back first." end
      lines[#lines + 1] = foot
      return lines
    end
  end
  return nil
end

