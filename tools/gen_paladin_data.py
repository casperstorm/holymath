#!/usr/bin/env python3
"""Generate Models/PaladinData.lua from a wowsims/forever checkout.

wowsims (https://github.com/wowsims/forever, MIT licence) carries the game's own
spell data, extracted from the Forever client. This script reads it AS TEXT (it runs
nothing from wowsims) and writes the subset a Holy Paladin needs: the healing spells'
ranks, Oath of Light's bonuses, the cooldowns, and the healing talents' values per rank.
How each one works in the game is wowsims' paladin code (sim/paladin); the model
(Models/Paladin.lua) follows it.

Usage (run from the HolyMath folder):
    git clone --depth 1 https://github.com/wowsims/forever /some/where/forever
    python3 -I tools/gen_paladin_data.py /some/where/forever > Models/PaladinData.lua
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # our own tools folder (python -I leaves it out)
from wowsims_spells import Spells, rank_entry, fmt, LICENCE  # noqa: E402

root = sys.argv[1]
W = Spells(root, "sim/paladin/spell_data_auto_gen.go")
rows = W.rows

spells = {}

# Flash of Light, Holy Light: one row a rank, the heal on it
for key, name in [("FLASH", "FlashOfLight"), ("HL", "HolyLight")]:
    out = []
    for rid in W.ladder(name):
        e = rank_entry(rows[rid], W.effect(rows[rid], ("E_HEAL",)))
        e["id"] = rid
        out.append(e)
    spells[key] = out

# Holy Shock: the cast row holds cost, level and cooldown; refs[1] is the heal (refs[0] the damage)
spells["SHOCK"] = []
for rid in W.ladder("HolyShock"):
    r = rows[rid]
    heal = rows[r["refs"][1]]
    e = rank_entry(r, W.effect(heal, ("E_HEAL",)))
    e["ml"] = int(W.effect(heal, ("E_HEAL",))["ml"] or heal["max"] or r["lvl"] + 5)
    e["id"] = rid
    spells["SHOCK"].append(e)

# Light's Vigil: the cast row (1.5 s cast) holds cost and level; refs are the 30 s mark on an
# ally and the party heal a Holy Shock on that ally sets off (the one with the heal effect)
spells["VIGIL"] = []
for rid in W.ladder("LightsVigil"):
    r = rows[rid]
    heal = next(rows[x] for x in r["refs"] if any(ef["type"] == "E_HEAL" for ef in rows[x]["effects"]))
    e = rank_entry(r, W.effect(heal, ("E_HEAL",)))
    e["id"] = rid
    spells["VIGIL"].append(e)

# --- timing and the other spells, in seconds -------------------------------------
def last(name):
    return rows[W.ladder(name)[-1]]


vigil_mark = next(rows[x] for x in last("LightsVigil")["refs"] if rows[x]["dur"] > 0)
oath = last("OathOfLight")
favor = last("DivineFavor")
infusion = last("InfusionOfLightTriggered")
timing = {
    "SHOCK": {"cd": last("HolyShock")["cd"] / 1000},
    "VIGIL": {"cd": last("LightsVigil")["cd"] / 1000, "dur": vigil_mark["dur"] / 1000},
    "OATH": {"dur": oath["dur"] / 1000},
    "FAVOR": {"cd": favor["cd"] / 1000},
    "INFUSION": {"dur": infusion["dur"] / 1000},
}
# Oath of Light: its three effects add to Holy Light, Flash of Light and Holy Shock on the
# Oath's target, growing with the paladin's level (points per level, from level 0)
oath_ppl = [ef["ppl"] for ef in oath["effects"]]
costs = {"OATH": oath["costPct"], "FAVOR": favor["costPct"]}   # percent of base mana

# --- talents: value per rank, as the model uses them ------------------------------
TALENTS = {
    # key: (ladder name, curve row, transform)
    "healingLight": ("HealingLight", 0, lambda v: v),           # % more healing: Holy Light, Flash of Light, Holy Shock
    "reverence": ("Reverence", 0, lambda v: v),                 # % of regen kept while casting
    "illumination": ("Illumination", 0, lambda v: v),           # % chance a heal's crit refunds mana
    "infusionOfLight": ("InfusionOfLight", 0, lambda v: abs(v) / 1000),  # seconds off the next Holy Light
    "holyPower": ("HolyPower", 0, lambda v: v),                 # % more on a heal's crit (the whole crit)
    "divineIntellect": ("DivineIntellect", 0, lambda v: v),     # % more intellect
    "benediction": ("Benediction", 0, abs),                     # % off instant spells' cost
    "boundlessLight": ("BoundlessLight", 0, lambda v: v),       # % crit for Holy Shock on someone without the Oath
    "conviction": ("Conviction", 0, lambda v: v),               # % crit
}
talents = {key: W.talent(name, row, f) for key, (name, row, f) in TALENTS.items()}
# Illumination's refund: its third effect, held at its base points (no curve): % of the spell's base cost
talents["illuminationRefund"] = [rows[W.ladder("Illumination")[0]]["effects"][2]["bp"]]

regen_base, regen_per = W.regen()
crit_per_int = W.crit_per_int_60("Paladin")
base_mana = W.base_mana_60("Paladin")
commit = W.commit()

# --- write Lua -----------------------------------------------------------------
NAMES = dict(FLASH="Flash of Light", HL="Holy Light", SHOCK="Holy Shock", VIGIL="Light's Vigil")
out = []
out.append("--[[ Holy Math - Models/PaladinData.lua  (GENERATED - do not edit by hand)")
out.append("     Made by tools/gen_paladin_data.py from wowsims/forever, commit " + commit + ".")
out.append("     The numbers are the game's own spell data as wowsims extracted it from the Forever client.")
out.append("")
out.append("     Per rank, for ONE cast on ONE target: bp = base heal at the rank's base level bl,")
out.append("     ppl = what it gains per level up to ml (its max level), coeff = share of healing power,")
out.append("     cost = mana, lvl = level it is learned, cast = cast time in ms (0 = instant).")
out.append("     Light's Vigil: the cast's cost and time, and the heal on each member of the party.")
out.append("")
out.extend(LICENCE)
out.append("]]--")
out.append("")
out.append("local _, ns = ...")
out.append("local D = {")
out.append('  source = "%s",' % ("wowsims/forever " + commit))
out.append("  regen = { base = %s, perSpirit = %s },  -- mana per second from spirit: base + spirit x perSpirit" % (fmt(regen_base), fmt(regen_per)))
out.append("  critPerInt60 = %s,  -- spell crit (percent) per point of intellect at level 60" % fmt(crit_per_int))
out.append("  baseMana60 = %s,  -- base mana at level 60 (Oath of Light and Divine Favor cost a share of it)" % fmt(base_mana))
out.append("  spells = {")
for key in ["FLASH", "HL", "SHOCK", "VIGIL"]:
    out.append('    %s = { name = "%s", ranks = {' % (key, NAMES[key]))
    for r in spells[key]:
        out.append("      { id = %d, cost = %s, lvl = %d, bl = %d, ml = %d, bp = %s, ppl = %s, coeff = %s, cast = %d }," % (
            r["id"], fmt(r["cost"] or 0), r["lvl"], r["bl"], r["ml"], fmt(r["bp"]), fmt(r["ppl"]), fmt(r["coeff"]), r["cast"]))
    out.append("    } },")
out.append("  },")
out.append("  timing = {  -- seconds: cd = its own cooldown, dur = how long it lasts")
for key in ["SHOCK", "VIGIL", "OATH", "FAVOR", "INFUSION"]:
    out.append("    %s = { %s }," % (key, ", ".join("%s = %s" % (k, fmt(v)) for k, v in sorted(timing[key].items()))))
out.append("  },")
out.append("  -- Oath of Light on its target: healing added per paladin level (Holy Light, Flash of Light, Holy Shock)")
out.append("  oathPerLevel = { HL = %s, FLASH = %s, SHOCK = %s }," % tuple(fmt(v) for v in oath_ppl[:3]))
out.append("  costPct = { OATH = %s, FAVOR = %s },  -- percent of base mana" % (fmt(costs["OATH"]), fmt(costs["FAVOR"])))
out.append("  talents = {  -- value per rank (percent; seconds: infusionOfLight)")
for key in list(TALENTS) + ["illuminationRefund"]:
    out.append("    %s = { %s }," % (key, ", ".join(fmt(v) for v in talents[key])))
out.append("  },")
out.append("}")
out.append("if ns then ns.PaladinData = D end")
out.append("return D")
print("\n".join(out))
