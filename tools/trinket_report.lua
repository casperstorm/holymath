--[[ Holy Math - tools/trinket_report.lua
     Every trinket, and every other item with a use or proc effect, in Models/GearData.lua,
     with what Holy Math makes of it for a level-60 Holy priest (the 17/32 build, mid raid
     gear) in a fight: its effect as the Gear tab words it, the stats it gives on average,
     and what it's worth in healing per second over an empty slot (the whole item, and
     its effect alone). For checking the effect maths by eye against each item's
     Wowhead page.

     Run from the addon folder:
       lua5.1 tools/trinket_report.lua [fight seconds] [time between pulls]
     e.g. lua5.1 tools/trinket_report.lua 120 600     (the defaults)

     Marks: "uncounted" = the item has an effect Holy Math doesn't count (the Gear tab
     says so); "<Profession>" = only with that profession; A/H = which side can get it.
]]--

local fl = tonumber(arg and arg[1]) or 120
local pull = tonumber(arg and arg[2]) or 600

local E = dofile("Models/Priest.lua")
local D = dofile("Models/GearData.lua")
local GS = dofile("Models/GearSolve.lua")

-- a level-60 Holy priest, the 17/32 build, mid raid gear
local inp = E.copy(E.DEFAULTS)
inp.settings.rules = E.RULES; inp.settings.known = nil; inp.settings.fightLength = fl
inp.settings.pullEvery = pull
inp.settings.shadowSpiritBuff = false
inp.race = { human = false, troll = true, dwarf = false, gnome = false }
inp.level = 60
inp.talents = { twinDisciplines = 5, mentalStrength = 5, mentalAgility = 3, innerFocus = 1, meditation = 3,
  improvedRenew = 3, holySpecialization = 5, divineFury = 5, inspiration = 3, improvedHealing = 3, holyBinding = 1,
  bindingHeal = 1, litanyOfLight = 2, spiritualGuidance = 5, spiritualHealing = 3, prayerOfMending = 1,
  improvedPWS = 0, soulWarding = 0, penance = 0, renewedHope = 0, divineAegis = 0 }
inp.gear = { healing = 600, int = 220, crit = 2, haste = 0, mp5 = 30, spirit = 200, spelldamage = 0 }
local st = E.Derive(inp)
local ROT = "renew"
local t = E.Talents(inp.talents, inp.settings.rules, inp.settings.overrides)
local base = E.Rotation(ROT, st, t, inp.settings)

-- the fight the effects are averaged over: its length, casts a second, casts of each spell,
-- and Flash Heal's overheal (for an item's own heal), as the Gear tab takes them (GearSolve's setFight)
local casts, n = {}, (base.fiveSecondCasts or 0) + (base.innerFocus and base.innerFocus.casts or 0)
for _, s in ipairs(base.steps) do
  casts[s.key] = (casts[s.key] or 0) + s.casts + (s.pauseCasts or 0)
  n = n + s.casts
end
local oh = inp.settings.overheal and inp.settings.overheal.FLASH or 0
local ctx = { fl = fl, cps = n / fl, casts = casts, oh = oh, pull = pull }

-- the effect in words (a trimmed copy of the Gear tab's)
local function words(f)
  local p = {}
  for _, k in ipairs({ "healing", "int", "spirit", "mp5", "crit" }) do if f[k] then p[#p + 1] = "+" .. f[k] .. " " .. k end end
  if f.mana then p[#p + 1] = f.mana .. " mana" end
  if f.heal then p[#p + 1] = "heals your target " .. f.heal end
  if f.cost then p[#p + 1] = f.cost .. " less mana " .. (f.n and "next spell" or "each spell") end
  local what = table.concat(p, ", ") .. ((f.d or 0) > 0 and (" for " .. f.d .. " s") or "")
  if f.use then return "Use: " .. what .. ((f.cd or 0) > 0 and (", cd " .. f.cd .. " s") or "") end
  if f.on then return "Each " .. f.on .. ": " .. what end
  return string.format("%g%% on a heal%s%s: %s", (f.p or 0) * 100, (f.ppm or 0) > 0 and (", " .. f.ppm .. " ppm") or "",
    (f.icd or 0) > 0 and (", icd " .. f.icd .. " s") or "", what)
end

local rows = {}
for _, it in ipairs(D.items) do
  if it.slot == "trinket" or it.fx or it.use then
    local stats, heal = GS.Stats(it, ctx)
    local d = E.Compare(ROT, st, inp, stats) or 0
    d = d + heal
    local add = GS.Effects(it, ctx)
    local dfx = (next(add) and E.Compare(ROT, st, inp, add) or 0) + heal
    local avg = {}
    for _, k in ipairs({ "healing", "int", "spirit", "mp5", "crit" }) do
      if add[k] and math.abs(add[k]) > 0.005 then avg[#avg + 1] = string.format("%+.1f %s", add[k], k) end
    end
    if heal > 0 then avg[#avg + 1] = string.format("%.1f HPS of heals", heal) end
    local fx = {}
    for _, f in ipairs(it.fx or {}) do fx[#fx + 1] = words(f) end
    local marks = {}
    if it.use then marks[#marks + 1] = "uncounted" end
    if it.prof ~= "" then marks[#marks + 1] = it.prof end
    marks[#marks + 1] = (it.A and "A" or "") .. (it.H and "H" or "")
    if it.pvp.A or it.pvp.H then marks[#marks + 1] = "PvP" end
    rows[#rows + 1] = { d = d, dfx = dfx, it = it, fx = fx, avg = avg, marks = marks }
  end
end
table.sort(rows, function(a, b) return a.d > b.d end)

print(string.format("Level-60 Holy priest, %d s fight, a pull every %d s, %.2f casts/s, Flash Heal overheal %d%%; base %.1f HPS",
  fl, pull, ctx.cps, oh * 100, base.ehps))
print("HPS: the whole item over an empty slot; effect: its use or proc alone")
print(string.format("%-8s %-8s %-7s %-40s %-4s %s", "HPS", "effect", "id", "item", "lvl", "marks"))
for _, r in ipairs(rows) do
  local it = r.it
  print(string.format("%+7.1f  %+7.1f  %-7d %-40s %-4d %s", r.d, r.dfx, it.id, it.name:sub(1, 40), it.lvl, table.concat(r.marks, " ")))
  for _, w in ipairs(r.fx) do print("           " .. w) end
  if #r.avg > 0 then print("           averaged: " .. table.concat(r.avg, ", ")) end
  print("           https://www.wowhead.com/forever/item=" .. it.id)
end
