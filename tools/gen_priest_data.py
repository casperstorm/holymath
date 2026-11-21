#!/usr/bin/env python3
"""Generate Models/PriestData.lua from a wowsims/forever checkout.

wowsims (https://github.com/wowsims/forever, MIT licence) carries the game's own
spell data, extracted from the Forever client: each rank's base points, per-level
gain, level range, healing-power coefficient and cost, and each talent's per-rank
values. This script reads that data AS TEXT (it runs nothing from wowsims) and
writes the subset a healing priest needs.

Usage (run from the HolyMath folder):
    git clone --depth 1 https://github.com/wowsims/forever /some/where/forever
    python3 -I tools/gen_priest_data.py /some/where/forever > Models/PriestData.lua
"""
import os
import re
import subprocess
import sys

root = sys.argv[1]
SPELLS_GO = os.path.join(root, "sim/core/spelldata/spells_auto_gen.go")
LADDERS_GO = os.path.join(root, "sim/priest/spell_data_auto_gen.go")
MANA_GO = os.path.join(root, "sim/core/mana.go")
BASE_STATS_GO = os.path.join(root, "sim/core/base_stats_auto_gen.go")

src = open(SPELLS_GO).read()
ladders = open(LADDERS_GO).read()
mana = open(MANA_GO).read()
base_stats = open(BASE_STATS_GO).read()

# --- every spell row, one chunk per row -------------------------------------
rows = {}
body = src[src.index("var generatedSpells"):src.index("var generatedCurves")]
for chunk in re.split(r"\n\t\{ID: ", body)[1:]:
    m = re.match(r'(\d+), Name: "([^"]*)"', chunk)
    if not m:
        continue
    head = chunk.split("\n")[0]

    def num(key, text=head):
        mm = re.search(r"\b" + key + r": ([-\d.e]+)", text)
        return float(mm.group(1)) if mm else 0.0

    effects = []
    for e in re.finditer(r"\{ID: \d+, SpellID: \d+, (?:Index: \d+, )?Type: dbcenums\.(\w+)"
                         r"(?:, Aura: dbcenums\.(\w+))?([^\n]*)", chunk):
        b = e.group(3)
        effects.append(dict(type=e.group(1), aura=e.group(2), bp=num("BasePoints", b), ppl=num("PPL", b),
                            coef=num("SPCoef", b), period=num("PeriodMs", b),
                            bl=num("BaseLevel", b), ml=num("MaxLevel", b)))
    cost = re.search(r"Powers: \[\]Power\{\{Cost: (\d+)", chunk)
    refs = re.search(r"RefIDs: \[\]int32\{([\d, ]+)\}", head)
    rows[int(m.group(1))] = dict(
        name=m.group(2), lvl=num("SpellLevel"), max=num("MaxLevel"), cast=num("CastTimeMs"),
        dur=num("DurationMs"), cost=int(cost.group(1)) if cost else None, effects=effects,
        refs=[int(x) for x in refs.group(1).split(",")] if refs else [])

# --- talent per-rank curves ---------------------------------------------------
curves = {}
cbody = src[src.index("var generatedCurves"):]
for m in re.finditer(r"^\t(\d+):\s+\{(.*)\},\s*$", cbody, re.M):
    curves[int(m.group(1))] = [[float(x) for x in row.split(",")] for row in re.findall(r"\{([-\d., ]+)\}", m.group(2))]


def ladder(name):
    m = re.search(r"^\t" + name + r":\s+spelldata\.(Ranked|Talent)\(([\d, ]+)\)", ladders, re.M)
    if not m:
        raise SystemExit("not found in priest ladders: " + name)
    return [int(x) for x in m.group(2).split(",")]


def effect(row, kinds):
    for e in row["effects"]:
        if e["type"] in kinds or e["aura"] in kinds:
            return e
    raise SystemExit("no %s effect on %s" % (kinds, row["name"]))


def rank_entry(cast_row, heal_eff, scale=1.0, cast_ms=None):
    """One rank: totals for one cast on one target (scale = ticks or bolts)."""
    # Downranking counts from the rank's max level; a row with none (0) is treated as learned level + 5,
    # the spacing every other healing rank has.
    ml = heal_eff["ml"] or cast_row["max"] or 0
    return dict(id=None, cost=cast_row["cost"], lvl=int(cast_row["lvl"]), bl=int(heal_eff["bl"] or cast_row["lvl"]),
                ml=int(ml), bp=heal_eff["bp"] * scale, ppl=heal_eff["ppl"] * scale,
                coeff=heal_eff["coef"] * scale, cast=int(cast_row["cast"] if cast_ms is None else cast_ms))


spells = {}


def simple(key, ladder_name, kinds, ticks_from_duration=False):
    out = []
    for rid in ladder(ladder_name):
        r = rows[rid]
        e = effect(r, kinds)
        ticks = (r["dur"] / e["period"]) if ticks_from_duration and e["period"] else 1
        entry = rank_entry(r, e, ticks)
        entry["id"] = rid
        out.append(entry)
    spells[key] = out


simple("RENEW", "Renew", ("A_PERIODIC_HEAL",), ticks_from_duration=True)
simple("GH", "GreaterHeal", ("E_HEAL",))
simple("FLASH", "FlashHeal", ("E_HEAL",))
simple("HEAL", "Heal", ("E_HEAL",))
simple("LESSER", "LesserHeal", ("E_HEAL",))
simple("POH", "PrayerOfHealing", ("E_HEAL",))
simple("PWS", "PowerWordShield", ("A_SCHOOL_ABSORB",))
simple("POM", "PrayerOfMending", ("E_DUMMY",))

# Holy Nova: the cast row holds cost and level, the triggered row the heal
spells["NOVA"] = []
for rid, hid in zip(ladder("HolyNova"), ladder("HolyNovaTriggered")):
    entry = rank_entry(rows[rid], effect(rows[hid], ("E_HEAL",)))
    entry["id"] = rid
    spells["NOVA"].append(entry)

# Penance: the cast row holds cost and level; refs[1] is the heal bolt, 3 bolts (one at once, then
# one per second for 2 seconds); refs[2] is the 2-second channel.
spells["PENANCE"] = []
for rid in ladder("Penance"):
    r = rows[rid]
    bolt = rows[r["refs"][1]]
    channel = rows[r["refs"][2]]
    e = effect(bolt, ("E_HEAL",))
    entry = rank_entry(r, e, 3, cast_ms=channel["dur"])
    entry["ml"] = int(e["ml"] or bolt["max"] or r["lvl"] + 5)
    entry["id"] = rid
    spells["PENANCE"].append(entry)

# --- talents: value per rank, as used by the model --------------------------
TALENTS = {
    # key: (ladder name, curve row, transform)
    "twinDisciplines": ("TwinDisciplines", 0, lambda v: v),
    "improvedPWS": ("ImprovedPowerWordShield", 0, lambda v: v),
    "mentalAgility": ("MentalAgility", 0, abs),
    "meditation": ("Meditation", 0, lambda v: v),
    "mentalStrength": ("MentalStrength", 0, lambda v: v),
    "divineAegis": ("DivineAegis", 0, lambda v: v),
    "improvedRenew": ("ImprovedRenew", 0, lambda v: v),
    "holySpecialization": ("HolySpecialization", 0, lambda v: v),
    "divineFury": ("DivineFury", 0, lambda v: abs(v) / 1000),     # seconds off the cast
    "inspiration": ("Inspiration", 0, lambda v: v),
    "improvedHealing": ("ImprovedHealing", 0, abs),
    "litanyOfLight": ("LitanyOfLight", 0, lambda v: v),           # % of base cost refunded
    "spiritualGuidance": ("SpiritualGuidance", 1, lambda v: v),   # row 1: healing from spirit
    "spiritualHealing": ("SpiritualHealing", 0, lambda v: v),
    "renewedHope": ("RenewedHope", 0, lambda v: v),               # crit % on Weakened Soul targets
}
talents = {}
for key, (name, row, f) in TALENTS.items():
    tid = ladder(name)[0]
    talents[key] = [f(v) for v in curves[tid][row]]

# Holy Binding (1 rank, no curve): Flash Heal on another target also heals you for this %
talents["holyBinding"] = [rows[ladder("HolyBinding")[0]]["effects"][0]["bp"]]

regen = re.search(r"spiritRegenBase, character\.spiritRegenPerSpirit = ([\d.]+), ([\d.]+)/([\d.]+)", mana)
regen_base, regen_per = float(regen.group(1)), float(regen.group(2)) / float(regen.group(3))

# Spell crit per point of intellect at level 60 (PlayerExpectedStat), in percent
crit_block = base_stats[base_stats.index("var CritPerIntMaxLevel"):]
crit_per_int = float(re.search(r"Class_ClassPriest:\s*([\d.]+)", crit_block).group(1))

try:
    commit = subprocess.run(["git", "-C", root, "log", "-1", "--format=%H %cs"], capture_output=True, text=True).stdout.strip()
except Exception:
    commit = "unknown"

# --- write Lua -----------------------------------------------------------------
def fmt(v):
    if isinstance(v, float):
        return ("%.6f" % v).rstrip("0").rstrip(".") if v != int(v) else str(int(v))
    return str(v)


NAMES = dict(RENEW="Renew", GH="Greater Heal", FLASH="Flash Heal", HEAL="Heal", LESSER="Lesser Heal",
             POH="Prayer of Healing", PWS="Power Word: Shield", POM="Prayer of Mending", NOVA="Holy Nova",
             PENANCE="Penance")
out = []
out.append("--[[ Holy Math - Models/PriestData.lua  (GENERATED - do not edit by hand)")
out.append("     Made by tools/gen_priest_data.py from wowsims/forever, commit " + commit + ".")
out.append("     The numbers are the game's own spell data as wowsims extracted it from the Forever client.")
out.append("")
out.append("     Per rank, for ONE cast on ONE target: bp = base heal at the rank's base level bl,")
out.append("     ppl = what it gains per level up to ml (its max level), coeff = share of healing power,")
out.append("     cost = mana, lvl = level it is learned, cast = cast time in ms (0 = instant).")
out.append("     Renew: all 5 ticks. Penance: all 3 bolts. Prayer of Healing / Holy Nova: per target.")
out.append("")
out.append("     wowsims licence (MIT):")
out.append("     Copyright (c) 2022 wowsims team")
out.append("     Permission is hereby granted, free of charge, to any person obtaining a copy of this software and")
out.append("     associated documentation files (the \"Software\"), to deal in the Software without restriction,")
out.append("     including without limitation the rights to use, copy, modify, merge, publish, distribute,")
out.append("     sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is")
out.append("     furnished to do so, subject to the following conditions: The above copyright notice and this")
out.append("     permission notice shall be included in all copies or substantial portions of the Software.")
out.append("     THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND.")
out.append("]]--")
out.append("")
out.append("local _, ns = ...")
out.append("local D = {")
out.append("  source = %r," % ("wowsims/forever " + commit))
out.append("  regen = { base = %s, perSpirit = %s },  -- mana per second from spirit: base + spirit x perSpirit" % (fmt(regen_base), fmt(regen_per)))
out.append("  critPerInt60 = %s,  -- spell crit (percent) per point of intellect at level 60" % fmt(crit_per_int))
out.append("  spells = {")
for key in ["RENEW", "GH", "FLASH", "HEAL", "LESSER", "POH", "PWS", "POM", "NOVA", "PENANCE"]:
    out.append("    %s = { name = %r, ranks = {" % (key, NAMES[key]))
    for r in spells[key]:
        out.append("      { id = %d, cost = %s, lvl = %d, bl = %d, ml = %d, bp = %s, ppl = %s, coeff = %s, cast = %d }," % (
            r["id"], fmt(r["cost"] or 0), r["lvl"], r["bl"], r["ml"], fmt(r["bp"]), fmt(r["ppl"]), fmt(r["coeff"]), r["cast"]))
    out.append("    } },")
out.append("  },")
out.append("  talents = {  -- value per rank (percent, except divineFury: seconds)")
for key in list(TALENTS) + ["holyBinding"]:
    out.append("    %s = { %s }," % (key, ", ".join(fmt(v) for v in talents[key])))
out.append("  },")
out.append("}")
out.append("if ns then ns.PriestData = D end")
out.append("return D")
print("\n".join(out).replace("'", '"'))
