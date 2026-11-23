#!/usr/bin/env python3
"""Generate Models/GearData.lua (the Gear tab's items) from a wowsims/forever checkout.

wowsims (https://github.com/wowsims/forever, MIT licence) carries the game's own
item data extracted from the Forever client: stats, slot, required level, phase,
sources, sets. This script reads it AS TEXT (JSON) and runs nothing from wowsims.

It keeps every item a priest can wear that is out now in WoW: Forever (phase 1)
and has a healing stat, at any level, for each faction, then drops the ones
five other items beat in every stat at the same or a lower level (items at least
as easy to get: both sides', no profession, not PvP-only), as a row on the Gear
tab shows five. Set pieces always stay. The Gear tab
picks the best for you in game (Models/GearSolve.lua).

Where to get an item isn't shipped (the Gear tab links each item's Wowhead page);
the sources only decide which side can get it and what is PvP.

Usage (run from the HolyMath folder):
    python3 -I tools/gen_gear_data.py /some/where/forever > Models/GearData.lua
"""
import json
import os
import re
import subprocess
import sys

root = sys.argv[1]
d = json.load(open(os.path.join(root, "assets/database/db.json")))
npcs = {n["id"]: n for n in d["npcs"]}
zones = {z["id"]: z["name"] for z in d["zones"]}
factions = {f["id"]: f["name"] for f in d["factions"]}
suffixes = {s["id"]: s for s in d["randomSuffixes"]}

PROF = {1: "Alchemy", 2: "Blacksmithing", 3: "Enchanting", 4: "Engineering", 5: "Herbalism", 6: "Inscription",
        7: "Jewelcrafting", 8: "Leatherworking", 9: "Mining", 10: "Skinning", 11: "Tailoring"}
REP = {4: "Neutral", 5: "Friendly", 6: "Honored", 7: "Revered", 8: "Exalted"}
SLOT = {1: "head", 2: "neck", 3: "shoulder", 4: "back", 5: "chest", 6: "wrist", 7: "hands", 8: "waist", 9: "legs",
        10: "feet", 11: "finger", 12: "trinket"}
STAT = {4: "healing", 3: "int", 13: "spirit", 31: "mp5", 18: "critR", 19: "hasteR"}   # proto Stat enum
PRIEST = 5
SIDES = {"A": 1, "H": 2}   # proto Faction: 1 Alliance, 2 Horde (0: both)


def source(s):
    """(text, group, kind, faction) for one source; faction 0 = both."""
    kind, v = list(s.items())[0]
    if kind == "drop":
        npc = npcs.get(v.get("npcId"), {})
        name = (npc.get("name") or v.get("otherName") or "").strip()
        zone = zones.get(v.get("zoneId")) or zones.get(npc.get("zoneId"))
        if not zone or name == "World Drop":
            return "World drop", "World drops", "world", 0
        return (name + " (" + zone + ")" if name and name != zone else zone), zone, "dungeon", 0
    if kind == "quest":
        return "Quest: " + v.get("name", "?"), "Quests", "quest", v.get("faction", 0)
    if kind == "crafted":
        p = PROF.get(v.get("profession"), "Crafted")
        return p, p, "crafted", 0
    if kind == "rep":
        f = factions.get(v.get("repFactionId"), "?")
        return f + ", " + REP.get(v.get("repLevel"), ""), f + " (reputation)", "rep", v.get("factionId", 0)
    if kind == "soldBy":
        n = v.get("npcName", "?")
        z = zones.get(v.get("zoneId"))
        return "Vendor: " + n + (" (" + z + ")" if z else ""), "Vendor: " + n, "vendor", v.get("faction", 0)
    if kind == "pvp":
        return "PvP", "PvP", "pvp", 0
    return None


# PvP rewards carry no faction in the data; their rank, battleground or set says which side
# can buy them (Sergeant is both sides' rank, so it says nothing)
PVP_SIDE = [("Grand Marshal", 1), ("Field Marshal", 1), ("Lieutenant Commander", 1), ("Knight-Champion", 1),
            ("Knight-Captain", 1), ("Knight-Lieutenant", 1), ("Master Sergeant", 1), ("Sergeant Major", 1),
            ("Marshal", 1), ("Stormpike", 1), ("Sentinel", 1), ("Highlander", 1),
            ("High Warlord", 2), ("Lieutenant General", 2), ("Warlord", 2), ("General", 2), ("Champion", 2),
            ("Centurion", 2), ("Legionnaire", 2), ("Blood Guard", 2), ("First Sergeant", 2), ("Senior Sergeant", 2),
            ("Frostwolf", 2), ("Outrider", 2), ("Defiler", 2), ("Scout", 2)]
PVP_SET_SIDE = {344: 1, 389: 1, 2074: 1, 2075: 1, 390: 2, 549: 2, 2072: 2, 2073: 2}


def pvp_side(it):
    if it.get("setId") in PVP_SET_SIDE:
        return PVP_SET_SIDE[it["setId"]]
    name = it["name"][len("Premier "):] if it["name"].startswith("Premier ") else it["name"]
    if "Alliance" in name:
        return 1
    if "Horde" in name:
        return 2
    for prefix, side in PVP_SIDE:
        if name.startswith(prefix):
            return side
    return 0


# --- item effects (trinkets above all): what a healer can use of them -------------
# The effects name a spell; its numbers are in wowsims' spell data (the game's own).
spell_src = open(os.path.join(root, "sim/core/spelldata/spells_auto_gen.go")).read()
spell_body = spell_src[spell_src.index("var generatedSpells"):spell_src.index("var generatedCurves")]
spells, triggered_by = {}, {}
for chunk in re.split(r"\n\t\{ID: ", spell_body)[1:]:
    m = re.match(r"(\d+), Name: ", chunk)
    if not m:
        continue
    head = chunk.split("\n")[0]

    def hnum(key):
        mm = re.search(r"\b" + key + r": (-?[\d.]+)", head)
        return float(mm.group(1)) if mm else None
    flags = re.search(r"ProcFlags: \[2\]uint32\{0: (0x[0-9a-f]+)", head)
    interrupt = re.search(r"AuraInterrupt: \[2\]uint32\{0: (0x[0-9a-f]+)", head)
    effs = []
    for e in re.finditer(r"\{ID: \d+, SpellID: \d+, (?:Index: \d+, )?Type: dbcenums\.(\w+)(?:, Aura: dbcenums\.(\w+))?([^\n]*)", chunk):
        b = e.group(3)

        def enum(key):
            mm = re.search(r"\b" + key + r": (-?[\d.]+)", b)
            return float(mm.group(1)) if mm else 0.0
        effs.append(dict(type=e.group(1), aura=e.group(2), bp=enum("BasePoints"), misc=int(enum("Misc")),
                         period=enum("PeriodMs"), trigger=int(enum("TriggerID")),
                         target=int((re.search(r"ImplicitTarget\{(\d+)", b) or [0, 0])[1])))
        if e.group(2) == "A_PROC_TRIGGER_SPELL" and enum("TriggerID"):
            triggered_by[int(enum("TriggerID"))] = int(m.group(1))
    spells[int(m.group(1))] = dict(dur=hnum("DurationMs"), chance=hnum("ProcChance"),
                                   flags=int(flags.group(1), 16) if flags else 0, effects=effs,
                                   channel="ChannelInterrupt" in head,
                                   seated=bool(interrupt and int(interrupt.group(1), 16) & 0x40000))

# proc flags for "when you cast a beneficial spell" (a heal): with or without a damage class.
# A harmful-spell proc (Draconic Infused Emblem) never fires for a healer.
HEAL_FLAGS = 0x400 | 0x4000
# procs on one named spell, which the row doesn't say (wowsims, sim/common/forever/items_trinkets.go):
# Dormant Heart of the Mountain's Eternal Power, on Greater Heal
PROC_ON = {1249118: "GH"}


# a heal counts only on your target (Blessed Prayer Beads, Ankh of Life: implicit target 21, a
# friendly target), not one on yourself (Lifestone, Behemoth Bones: 1, the caster): your HPS is the
# healing you do for others
TARGET_ALLY = 21


def buff_value(sid):
    """What a buff spell gives a healer: stats, mana (instant or over time), a heal, mana off each cast."""
    sp = spells.get(sid)
    # a drink (you sit) or a channel (you can't heal meanwhile) is no use in a fight
    if not sp or sp["seated"] or sp["channel"]:
        return {}
    v = {}
    dur = (sp["dur"] or 0) / 1000
    for e in sp["effects"]:
        a, t, bp = e["aura"], e["type"], e["bp"]
        if a == "A_MOD_STAT" and e["misc"] in (3, 4, -1):
            if e["misc"] in (3, -1):
                v["int"] = v.get("int", 0) + bp
            if e["misc"] in (4, -1):
                v["spirit"] = v.get("spirit", 0) + bp
        elif a == "A_MOD_HEALING_DONE":
            v["healing"] = v.get("healing", 0) + bp
        elif a == "A_MOD_SPELL_CRIT_CHANCE":
            v["crit"] = v.get("crit", 0) + bp
        elif a == "A_MOD_POWER_REGEN" and e["misc"] == 0:
            v["mp5"] = v.get("mp5", 0) + bp
        elif a == "A_PERIODIC_ENERGIZE" and e["misc"] == 0 and e["period"] > 0:
            # mana over time: MP5 while it lasts (only the part inside the fight counts)
            v["mp5"] = v.get("mp5", 0) + bp * 5000 / e["period"]
        elif t == "E_ENERGIZE" and e["misc"] == 0:
            v["mana"] = v.get("mana", 0) + bp
        elif t == "E_HEAL" and e["target"] == TARGET_ALLY:
            v["heal"] = v.get("heal", 0) + bp
        elif a == "A_MOD_POWER_COST_SCHOOL" and bp < 0:
            v["cost"] = v.get("cost", 0) - bp
            if sp["chance"]:
                v["n"] = 1       # the buff procs off (is used up by) the next spell: one cast (Robes of Insight)
    if "heal" in v and "mana" in v:
        del v["heal"]    # one target for both (Major Recombobulator): on yourself, for the mana
    return v


def item_effects(it):
    """The item's use and on-cast proc effects a healer gets something from, as small tables, and
    whether it has another effect that isn't counted (the tooltip says so)."""
    out, uncounted = [], False
    for e in it.get("itemEffects") or []:
        if e.get("effectDurationMs") == -1 and not e.get("onUse") and not e.get("proc"):
            if not ((e.get("scalingOptions") or {}).get("0") or {}).get("stats"):
                uncounted = True
            continue                                    # always on: counted as the item's stats
        v = buff_value(e["buffId"])
        if not v:
            uncounted = True
            continue
        dur = max(0, (e.get("effectDurationMs") or 0)) / 1000
        if e.get("onUse"):
            fx = dict(use=1, d=dur, cd=e["onUse"].get("cooldownMs", 0) / 1000)
        else:
            # a proc: only one that fires when you cast (the equip spell's proc flags say)
            equip_id = triggered_by.get(e["buffId"])
            equip = spells.get(equip_id, {})
            if not (equip.get("flags", 0) & HEAL_FLAGS):
                uncounted = True
                continue
            p = e.get("proc") or {}
            chance = p.get("procChance") or ((equip.get("chance") or 0) / 100)
            if not chance and not p.get("ppm"):
                uncounted = True
                continue
            fx = dict(p=chance, ppm=p.get("ppm", 0), icd=(p.get("icdMs") or 0) / 1000, d=dur)
            if equip_id in PROC_ON:
                fx["on"] = PROC_ON[equip_id]
        fx.update(v)
        out.append(fx)
        # a spell the buff casts on you as well, with its own duration: Mindtap Talisman's
        # Tapped Mind (-60 intellect for 2 minutes after the mana)
        for te in spells.get(e["buffId"], {}).get("effects", []):
            if te["type"] == "E_TRIGGER_SPELL" and te["trigger"]:
                tv = buff_value(te["trigger"])
                if tv:
                    extra = {k: fx[k] for k in ("use", "cd", "p", "ppm", "icd", "on") if k in fx}
                    extra["d"] = max(0, (spells[te["trigger"]]["dur"] or 0)) / 1000
                    extra.update(tv)
                    out.append(extra)
    return out, uncounted


def slot_of(it):
    t = it.get("type")
    if t in SLOT:
        if t in (1, 3, 5, 6, 7, 8, 9, 10) and it.get("armorType", 1) != 1:
            return None
        if t == 4 and it.get("armorType", 1) not in (0, 1):
            return None
        return SLOT[t]
    if t == 13:
        wt, ht = it.get("weaponType"), it.get("handType")
        if wt == 8 and ht == 4:
            return "twohand"
        if wt in (2, 4) and ht in (1, 2):
            return "mainhand"
        if wt == 5:
            return "offhand"
        return None
    if t == 14 and it.get("rangedWeaponType") == 5:
        return "wand"
    return None


def lua(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def prof_of(it):
    """The profession the item needs. wowsims leaves it out for every Engineering item (the game's
    tooltip says "Requires Engineering": Major Recombobulator, Rose Colored Goggles, Green Lens,
    Floppy Goggles), so an item crafted by Engineering needs Engineering."""
    if it.get("requiredProfession"):
        return PROF.get(it["requiredProfession"], "")
    if any((s.get("crafted") or {}).get("profession") == 4 for s in it.get("sources") or []):
        return "Engineering"
    return ""


items = []
for it in d["items"]:
    if it.get("phase") != 1 or it.get("reqLvl", 0) > 60:
        continue
    allow = it.get("classAllowlist")
    if allow and PRIEST not in allow:
        continue
    slot = slot_of(it)
    if not slot:
        continue
    so = it["scalingOptions"]["0"]
    stats = {STAT[int(k)]: v for k, v in so.get("stats", {}).items() if int(k) in STAT}
    # an effect that is always on (no duration) with stats is the item's own stats too
    # (Royal Seal of Eldre'Thalas for priests: +16 spirit)
    for e in it.get("itemEffects") or []:
        if e.get("effectDurationMs") == -1 and not e.get("onUse") and not e.get("proc"):
            for k, v in ((e.get("scalingOptions") or {}).get("0") or {}).get("stats", {}).items():
                if int(k) in STAT:
                    stats[STAT[int(k)]] = stats.get(STAT[int(k)], 0) + v
    variants = [("", "", stats)]
    for sid in it.get("randomSuffixOptions") or []:
        s = suffixes.get(sid)
        if not s:
            continue
        add = {}
        for i, c in enumerate(s["stats"]):
            if c and i in STAT:
                add[STAT[i]] = add.get(STAT[i], 0) + round(c * so.get("randPropPoints", 0) / 10000)
        if add:
            v = dict(stats)
            for k, x in add.items():
                v[k] = v.get(k, 0) + x
            variants.append((" " + s["name"], ":" + str(sid), v))
    fx, uncounted = item_effects(it)
    if not fx and not any(any(k in v for k in ("healing", "int", "spirit", "mp5")) for _, _, v in variants):
        continue
    srcs = [x for x in (source(s) for s in it.get("sources", [])) if x]
    per_side = {}
    restricted = it.get("factionRestriction") or 0
    if not restricted and any(x[2] == "pvp" for x in srcs):
        restricted = pvp_side(it)
    for side, fid in SIDES.items():
        if restricted not in (0, fid):
            continue
        mine = [x for x in srcs if x[3] in (0, fid)]
        if srcs and not mine:
            continue     # only the other side can get it
        text = "; ".join(dict.fromkeys(x[0] for x in mine)) or "No source"
        group = mine[0][1] if mine else "No source"
        kinds = sorted(set(x[2] for x in mine)) or ["unknown"]
        per_side[side] = (text, group, kinds)
    if not per_side:
        continue
    # when you can get it: the required level, or the item level less 5 when that is higher (as almost
    # every item states it: 5169 of 5416 in phase 1). Quest rewards often state no level, and some
    # Forever items "level 1" though they come from level-45 content (Stick No Rock, Eye of Mugg).
    level = max(it.get("reqLvl") or 1, min(60, so.get("ilvl", 1) - 5), 1)
    for suffix, key, v in variants:
        if not fx and not any(k in v for k in ("healing", "int", "spirit", "mp5")):
            continue
        items.append(dict(key=str(it["id"]) + key, sid=int(key[1:]) if key else 0, id=it["id"], name=it["name"] + suffix, suffix=suffix.strip(),
                          slot=slot, lvl=level, q=it.get("quality", 0), unique=bool(it.get("unique")),
                          limit=it.get("limitCategory", 0) or 0, use=uncounted,
                          prof=prof_of(it),
                          fx=fx, set=it.get("setId", 0) or 0, setName=it.get("setName", ""), sides=per_side, stats=v))

# Set bonuses that matter for healing (wowsims/forever's set rows, sim/common/forever/items_sets.go
# and sim/priest/item_sets.go). proc: 5% a cast for this much mana.
SETS = {
    1675: {3: ({"mp5": 8}, "8 MP5"), 4: ({"proc": 200}, "5% a cast: 200 mana"), 6: ({"healing": 23}, "+23 healing")},
    182: {3: ({"healing": 18}, "+18 healing"), 5: ({"proc": 200}, "5% a cast: 200 mana"), 6: ({"mp5": 8}, "8 MP5")},
    2104: {2: ({"spirit": 10}, "+10 spirit"), 4: ({"healing": 26}, "+26 healing")},
    2072: {2: ({"healing": 44}, "+44 healing")}, 2073: {6: ({"healing": 44}, "+44 healing")},
    2074: {6: ({"healing": 44}, "+44 healing")}, 2075: {2: ({"healing": 44}, "+44 healing")},
    549: {2: ({"healing": 23}, "+23 healing")}, 390: {6: ({"healing": 23}, "+23 healing")},
    344: {2: ({"healing": 23}, "+23 healing")}, 389: {6: ({"healing": 23}, "+23 healing")},
    2134: {3: ({"spirit": 10}, "+10 spirit")}, 2133: {3: ({"int": 10}, "+10 intellect")},
}

# --- drop what something else beats ---------------------------------------------
STATS = ("healing", "int", "spirit", "mp5", "critR", "hasteR")


def pvp_only(it, side):
    return set(it["sides"][side][2]) == {"pvp"}


def easier(a, b):
    """a is at least as easy to get as b: every side b has, no profession b doesn't need, not PvP-only where b isn't."""
    for side in b["sides"]:
        if side not in a["sides"]:
            return False
        if pvp_only(a, side) and not pvp_only(b, side):
            return False
    return a["prof"] in ("", b["prof"])


def beats(a, b):
    if a is b or a["lvl"] > b["lvl"] or not easier(a, b):
        return False
    if a["fx"] or any(a["stats"].get(k, 0) < b["stats"].get(k, 0) for k in STATS):
        return False
    same = all(a["stats"].get(k, 0) == b["stats"].get(k, 0) for k in STATS)
    return not same or (a["lvl"], a["key"]) < (b["lvl"], b["key"])


by_slot = {}
for it in items:
    by_slot.setdefault(it["slot"], []).append(it)
keep = []
for slot, lst in by_slot.items():
    # dropped only when as many items beat it as a row on the Gear tab has boxes (the best and
    # the next best): a slot's runners-up stay, even behind a rare world drop
    need = 5
    for b in lst:
        if b["set"] in SETS or b["fx"]:
            keep.append(b)
            continue
        # counted as the row shows them: one of each item (not each random suffix of it), one of
        # each equip limit (Warden's Signets can't be worn together)
        seen = set()
        for a in lst:
            if beats(a, b):
                seen.add(("limit", a["limit"]) if a["limit"] else ("name", a["id"]))
                if len(seen) >= need:
                    break
        if len(seen) < need:
            keep.append(b)
keep.sort(key=lambda x: (x["slot"], x["lvl"], x["key"]))

try:
    commit = subprocess.run(["git", "-C", root, "log", "-1", "--format=%H %cs"], capture_output=True, text=True).stdout.strip()
except Exception:
    commit = "unknown"

out = []
w = out.append
w("--[[ Holy Math - Models/GearData.lua  (GENERATED - do not edit by hand)")
w("     Made by tools/gen_gear_data.py from wowsims/forever, commit " + commit + ".")
w("     Every item a priest can wear that is out now in WoW: Forever (phase 1) and has a healing stat,")
w("     at any level, less those five other items beat in every stat at the same or a lower level.")
w("     The game's own item data as wowsims extracted it from the Forever client.")
w("     wowsims licence (MIT): Copyright (c) 2022 wowsims team. THE SOFTWARE IS PROVIDED \"AS IS\".")
w("]]--")
w("")
w("local _, ns = ...")
w("local D = {")
w("  source = %s," % lua("wowsims/forever " + commit))
w("  -- set bonuses: [set id] = { [pieces] = { stats, text } }")
w("  sets = {")
for sid in sorted(SETS):
    parts = []
    for k in sorted(SETS[sid]):
        st, text = SETS[sid][k]
        parts.append("[%d] = { %s, text = %s }" % (k, ", ".join("%s = %s" % (a, b) for a, b in st.items()), lua(text)))
    w("    [%d] = { %s }," % (sid, ", ".join(parts)))
w("  },")
set_names = {}
for it in keep:
    if it["set"]:
        set_names[it["set"]] = it["setName"]
w("  setNames = { %s }," % ", ".join("[%d] = %s" % (k, lua(v)) for k, v in sorted(set_names.items())))
SLOT_CODE = ["head", "neck", "shoulder", "back", "chest", "wrist", "hands", "waist", "legs", "feet", "finger", "trinket",
             "twohand", "mainhand", "offhand", "wand"]
PROF_CODE = ["", "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Inscription", "Jewelcrafting",
             "Leatherworking", "Mining", "Skinning", "Tailoring"]
rows = []
for it in keep:
    # which side can get it: 1 Alliance, 2 Horde, 3 both
    side = (1 if "A" in it["sides"] else 0) + (2 if "H" in it["sides"] else 0)
    pvp = (1 if "A" in it["sides"] and pvp_only(it, "A") else 0) + (2 if "H" in it["sides"] and pvp_only(it, "H") else 0)
    st = it["stats"]
    fxs = ""
    if it["fx"]:
        fxs = ",{" + ",".join("{" + ",".join("%s=%s" % (k, lua(v) if isinstance(v, str) else ("%g" % v))
                                            for k, v in sorted(f.items()) if v) + "}" for f in it["fx"]) + "}"
    rows.append(("{%d,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" + fxs.replace("%", "%%") + "}") % (
        it["id"], lua(it["name"]), it["sid"], SLOT_CODE.index(it["slot"]) + 1, it["lvl"], it["q"],
        1 if it["unique"] else 0, 1 if it["use"] else 0, it["limit"], it["set"], PROF_CODE.index(it["prof"]),
        side, pvp, st.get("healing", 0), st.get("int", 0), st.get("spirit", 0), st.get("mp5", 0),
        st.get("critR", 0), st.get("hasteR", 0)))
w("  -- id, name (with its random suffix), suffix id, slot, level, quality, unique, use/proc, equip limit,")
w("  -- set, profession, who can get it (1 Alliance, 2 Horde, 3 both), PvP only (1 Alliance, 2 Horde, 3 both),")
w("  -- healing, intellect, spirit, MP5, crit rating, haste rating, and its effects a healer gets something from:")
w("  --   use=1, d (lasts, s), cd (cooldown, s); or p (chance a heal procs it), on (only that spell), icd, d;")
w("  --   with stats it gives (healing, int, spirit, mp5, crit in %), mana (a use), heal (a use), cost (mana off each cast)")
w("  rows = {")
for i in range(0, len(rows), 2):
    w("    " + ", ".join(rows[i:i + 2]) + ",")
w("  },")
w("}")
w("-- Holy Math is for priests only: another class leaves the rows unread (and lets them go)")
w("local class = UnitClass and select(2, UnitClass(\"player\"))")
w("if ns and class and class ~= \"PRIEST\" then D.rows = nil; return D end")
w("local SLOTS = { %s }" % ", ".join(lua(x) for x in SLOT_CODE))
w("local PROFS = { %s }" % ", ".join(lua(x) for x in PROF_CODE))
w("-- the rows as tables, once at load")
w("D.items = {}")
w("for i, r in ipairs(D.rows) do")
w("  local stats = {}")
w("  for j, k in ipairs({ \"healing\", \"int\", \"spirit\", \"mp5\", \"critR\", \"hasteR\" }) do")
w("    if r[13 + j] ~= 0 then stats[k] = r[13 + j] end")
w("  end")
w("  local it = { id = r[1], name = r[2], key = r[3] ~= 0 and (r[1] .. \":\" .. r[3]) or tostring(r[1]),")
w("    suffix = r[3] ~= 0 and (r[2]:match(\" (of [%a' ]+)$\") or \"\") or \"\", slot = SLOTS[r[4]], lvl = r[5], q = r[6],")
w("    unique = r[7] == 1, use = r[8] == 1, limit = r[9], set = r[10], setName = D.setNames[r[10]] or \"\",")
w("    prof = PROFS[r[11] + 1], pvp = { A = r[13] % 2 == 1, H = r[13] >= 2 }, stats = stats, fx = r[20] }")
w("  if r[12] % 2 == 1 then it.A = true end")
w("  if r[12] >= 2 then it.H = true end")
w("  D.items[i] = it")
w("end")
w("D.rows = nil")
w("D.byKey = {}")
w("for _, it in ipairs(D.items) do D.byKey[it.key] = it end")
w("if ns then ns.GearData = D end")
w("return D")
print("\n".join(out))
sys.stderr.write("%d items kept of %d\n" % (len(keep), len(items)))
