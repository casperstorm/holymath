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
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))   # our own tools folder (python -I leaves it out)
from wowsims_spells import Spells, rank_entry, fmt, LICENCE  # noqa: E402

root = sys.argv[1]
W = Spells(root, "sim/priest/spell_data_auto_gen.go")
rows, curves = W.rows, W.curves


def ladder(name):
    return W.ladder(name)


def effect(row, kinds):
    return W.effect(row, kinds)


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

# --- timing: what the Playstyles tab's "on cooldown" and "keep it up" mean --------
# A spell's own cooldown (its highest rank's), Renew's duration, and Weakened Soul
# (how soon PW:Shield can go on the same target again), in seconds.
timing = {}
for key, name in [("POM", "PrayerOfMending"), ("PENANCE", "Penance"), ("PWS", "PowerWordShield")]:
    timing[key] = {"cd": rows[ladder(name)[-1]]["cd"] / 1000}
timing["RENEW"] = {"dur": rows[ladder("Renew")[-1]]["dur"] / 1000}
weakened = [r for r in rows.values() if r["name"] == "Weakened Soul" and r["dur"] > 0]
if not weakened:
    raise SystemExit("Weakened Soul not found")
timing["PWS"]["lockout"] = weakened[0]["dur"] / 1000

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

# Renewed Hope's second row: seconds each heal takes off Weakened Soul
talents["renewedHopeCut"] = [abs(v) / 1000 for v in curves[ladder("RenewedHope")[0]][1]]


def misc_effect(name, misc):
    for e in rows[ladder(name)[0]]["effects"]:
        if e["misc"] == misc:
            return e
    raise SystemExit("no misc %d effect on %s" % (misc, name))


# Soul Warding (1 rank, no curve): spell mods on PW:Shield, misc 11 = cooldown (ms), 14 = cost (%)
talents["soulWarding"] = [abs(misc_effect("SoulWarding", 14)["bp"])]
talents["soulWardingCd"] = [abs(misc_effect("SoulWarding", 11)["bp"]) / 1000]
# Divine Aegis: its second effect has no curve row, so it is the same at every rank: the
# most one target's absorb can hold, per caster level
da = ladder("DivineAegis")[0]
talents["divineAegisCap"] = [rows[da]["effects"][1]["bp"]] * len(curves[da][0])

regen_base, regen_per = W.regen()

# Spell crit per point of intellect at level 60 (PlayerExpectedStat), in percent
crit_per_int = W.crit_per_int_60("Priest")

commit = W.commit()

# --- write Lua -----------------------------------------------------------------
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
out.extend(LICENCE)
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
out.append("  timing = {  -- seconds: cd = its own cooldown, dur = how long it lasts, lockout = Weakened Soul")
for key in ["POM", "PENANCE", "PWS", "RENEW"]:
    out.append("    %s = { %s }," % (key, ", ".join("%s = %s" % (k, fmt(v)) for k, v in sorted(timing[key].items()))))
out.append("  },")
out.append("  talents = {  -- value per rank (percent; seconds: divineFury, renewedHopeCut, soulWardingCd; per level: divineAegisCap)")
for key in list(TALENTS) + ["holyBinding", "renewedHopeCut", "soulWarding", "soulWardingCd", "divineAegisCap"]:
    out.append("    %s = { %s }," % (key, ", ".join(fmt(v) for v in talents[key])))
out.append("  },")
out.append("}")
out.append("if ns then ns.PriestData = D end")
out.append("return D")
print("\n".join(out).replace("'", '"'))
