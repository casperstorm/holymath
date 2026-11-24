#!/usr/bin/env python3
"""Generate Models/ConsumableData.lua (the Consumables tab's items) from a wowsims/forever checkout.

wowsims (https://github.com/wowsims/forever, MIT licence) carries the game's own consumable data
extracted from the Forever client: each consumable's stats, required level, category, the buff it
casts and the group of consumables it can't be used together with. This script reads it AS TEXT
(JSON and the spell rows) and runs nothing from wowsims.

It keeps every flask, elixir, food, drink and weapon oil a healing priest gets something from
(healing, intellect, spirit, MP5, spell crit, maximum mana), each in the row of the things that
don't stack with it (one flask, one elixir, one food or drink, one weapon oil). What another item of its row beats in every stat at the same or a lower level is
kept only to see that you have it (hidden): the tab doesn't list it. Potions and runes aren't here: the model has them (E.POTIONS in Models/Priest.lua).

Left out: holiday items, stats only in some zones (the Hyjal flasks), what a drink gives while you
sit (you can't heal then), scrolls (they don't stack with Arcane Intellect or Divine Spirit), and
the odd buffs a raid healer doesn't plan on (Zanza's and the Blasted Lands', Kreeg's Stout).

Usage (run from the HolyMath folder):
    python3 -I tools/gen_consumable_data.py /some/where/forever > Models/ConsumableData.lua
"""
import json
import os
import re
import subprocess
import sys

root = sys.argv[1]
d = json.load(open(os.path.join(root, "assets/database/db.json")))
PRIEST = 5

# proto Stat: 3 intellect, 4 healing power, 13 spirit, 30 mana, 31 MP5; PseudoStat 15: spell crit %
STAT = {3: "int", 4: "healing", 13: "spirit", 30: "mana", 31: "mp5"}
SPELL_CRIT_PSEUDO = 15

# The rows: one of each can be up at once. One elixir at a time (what players see in Forever; wowsims
# would let elixirs of different stats stack); a flask besides (Forever lets them stack, method.gg).
# One Well Fed buff at a time, from a food or a drink (a tea or smoothie).
ROW_ORDER = ["flask", "elixir", "food", "oil"]

# --- the spell rows: an elixir's crit, a food's Well Fed buff (for seeing which one you have) ---
spell_src = open(os.path.join(root, "sim/core/spelldata/spells_auto_gen.go")).read()
spell_body = spell_src[spell_src.index("var generatedSpells"):spell_src.index("var generatedCurves")]
spells = {}
for chunk in re.split(r"\n\t\{ID: ", spell_body)[1:]:
    m = re.match(r"(\d+), Name: \"((?:[^\"\\]|\\.)*)\"", chunk)
    if not m:
        continue
    effs = []
    for e in re.finditer(r"\{ID: \d+, SpellID: \d+, (?:Index: \d+, )?Type: dbcenums\.(\w+)(?:, Aura: dbcenums\.(\w+))?([^\n]*)", chunk):
        b = e.group(3)

        def enum(key):
            mm = re.search(r"\b" + key + r": (-?[\d.]+)", b)
            return float(mm.group(1)) if mm else 0.0
        effs.append(dict(type=e.group(1), aura=e.group(2), bp=enum("BasePoints"), misc=int(enum("Misc")),
                         trigger=int(enum("TriggerID"))))
    spells[int(m.group(1))] = dict(name=m.group(2), effects=effs)

CRIT_AURAS = ("A_MOD_CRIT_PCT", "A_MOD_SPELL_CRIT_CHANCE")


def crit_of(buff):
    """The spell crit % a buff gives (aura 290 counts for spells and attacks alike; 57 for spells)."""
    return sum(e["bp"] for e in spells.get(buff, {}).get("effects", [])
               if e["type"] == "E_APPLY_AURA" and e["aura"] in CRIT_AURAS)


def well_fed(buff):
    """A food or drink's eating spell casts its Well Fed buff when you have eaten: (aura id, amount). Many
    foods share one Well Fed aura with different amounts (the value the eating spell passes on)."""
    for e in spells.get(buff, {}).get("effects", []):
        if e["aura"] == "A_PERIODIC_TRIGGER_SPELL_WITH_VALUE" and e["trigger"]:
            return e["trigger"], int(e["bp"])
        if e["aura"] == "A_PERIODIC_TRIGGER_SPELL" and e["trigger"]:
            return e["trigger"], 0
    return buff, 0


def stats_of(arr):
    return {STAT[i]: v for i, v in enumerate(arr or []) if i in STAT and v}


items = []
for c in d["consumables"]:
    if c.get("holiday"):
        continue
    allow = c.get("classAllowlist")
    if allow and PRIEST not in allow:
        continue
    t = c.get("type", 0)
    buffs = [e.get("buffId") for e in c.get("itemEffects") or [] if e.get("buffId")]
    buff = buffs[0] if buffs else 0
    if t == 6:                                        # a weapon oil: its temporary enchant's stats
        te = c.get("temporaryEnchant") or {}
        st = stats_of(te.get("stats"))
        ps = te.get("pseudoStats") or c.get("pseudoStats") or []
        if len(ps) > SPELL_CRIT_PSEUDO and ps[SPELL_CRIT_PSEUDO]:
            st["crit"] = ps[SPELL_CRIT_PSEUDO]
        row = "oil"
    else:
        st = stats_of(c.get("stats"))
        crit = crit_of(buff)
        if crit:
            st["crit"] = crit
        if t == 2:
            row = "flask"
        elif t == 4:
            # a scroll doesn't stack with the raid's own buff of its stat (Arcane Intellect, and Divine
            # Spirit, which you have as a priest), so in a group it adds nothing
            row = None
        elif t == 11:
            row = "elixir"
        elif t == 3:
            st.pop("mp5", None)                        # a drink's mana comes while you sit
            st.pop("mana", None)
            row = "food"
        else:
            row = None
    st.pop("mana", None) if row != "flask" else None
    if not row or not any(st.get(k, 0) > 0 for k in ("healing", "int", "spirit", "mp5", "crit", "mana")):
        continue
    aura, amount = (well_fed(buff) if row in ("food", "drink") else (buff, 0))
    if row == "oil":                                  # an oil shows as its enchant on the weapon
        aura = (c.get("temporaryEnchant") or {}).get("effectId") or 0
    items.append(dict(id=c["id"], name=c["name"], lvl=c.get("lvl") or 1, row=row, stats=st, aura=aura or 0,
                      amount=amount, prof=c.get("requiredProfession") or 0))

# --- drop what something in its row beats in every stat at the same or a lower level ---
KEYS = ("healing", "int", "spirit", "mp5", "crit", "mana")


def beats(a, b):
    if a is b or a["row"] != b["row"] or a["lvl"] > b["lvl"] or a["prof"] not in (0, b["prof"]):
        return False
    if any(a["stats"].get(k, 0) < b["stats"].get(k, 0) for k in KEYS):
        return False
    same = all(a["stats"].get(k, 0) == b["stats"].get(k, 0) for k in KEYS)
    return not same or (a["lvl"], a["id"]) < (b["lvl"], b["id"])


for b in items:
    b["hidden"] = any(beats(a, b) for a in items)
keep = items
keep.sort(key=lambda x: (ROW_ORDER.index(x["row"]), x["lvl"], x["id"]))

# --- enchants: the best for each slot ---
# wowsims' enchant rows (the game's): the slot (proto ItemType, enchantType for a weapon: 1 two-hand
# only, 2 shield, 5 off-hand, none any weapon; extraTypes: other slots it goes on too), stats, phase,
# sources. Kept: out now (phase 1) with a healer stat or one of Forever's weapon procs, and with a known
# source or a plain trainer enchant (a common-quality scroll of an old spell). Left out: the ones
# without a source from other seasons (Law of Nature, Living Stats, Grand Sorcerer: Season of
# Discovery spells) and Ahn'Qiraj's gloves formula, which the data has but nothing gives.
ENCHANT_ROW = {1: "head", 2: "neck", 3: "shoulder", 4: "back", 5: "chest", 6: "wrist", 7: "hands", 9: "legs",
               10: "feet"}
WEAPON_ROW = {None: "weapon", 0: "weapon", 1: "twohand", 2: "shield", 5: "offhand"}
ENCHANT_ROWS = ["head", "neck", "shoulder", "back", "chest", "wrist", "hands", "legs", "feet", "weapon", "twohand",
                "offhand", "shield"]
# the weapon procs: Insight (35% on a heal, 45 s cooldown, +100% spirit for 10 s), Revelation (your next
# spell crits; 8% a cast, a rate wowsims observed), Grand Sorcerer (left out, no source)
PROCS = {8216: "insight", 8217: "revelation"}
enchants = []
for e in d["enchants"]:
    if (e.get("phase") or 1) > 1:
        continue
    allow = e.get("classAllowlist")
    if allow and PRIEST not in allow:
        continue
    st = stats_of(e.get("stats"))
    ps = e.get("pseudoStats") or []
    if len(ps) > SPELL_CRIT_PSEUDO and ps[SPELL_CRIT_PSEUDO]:
        st["crit"] = ps[SPELL_CRIT_PSEUDO]
    proc = PROCS.get(e["effectId"], "")
    if not proc and not any(st.get(k, 0) > 0 for k in ("healing", "int", "spirit", "mp5", "crit", "mana")):
        continue
    if not e.get("sources") and not (e.get("spellId", 0) < 100000 and (e.get("quality") or 0) <= 1):
        continue
    t = e.get("type")
    rows = []
    if t == 13:
        r = WEAPON_ROW.get(e.get("enchantType"))
        if r:
            rows.append(r)
            if r == "weapon":
                rows.append("twohand")          # an any-weapon enchant goes on a two-hander too
    elif t in ENCHANT_ROW:
        rows.append(ENCHANT_ROW[t])
        for x in e.get("extraTypes") or []:
            if x in ENCHANT_ROW:
                rows.append(ENCHANT_ROW[x])
    for r in rows:
        enchants.append(dict(id=e["effectId"], item=e.get("itemId") or 0, spell=e.get("spellId") or 0, name=e["name"],
                             row=r, stats=dict(st), proc=proc))
# the same effect under two names in one row (Enchant Bracer - Spirit and Enchant Boots - Spirit are
# one effect, 851): once; names alike for different effects (the three Lesser Arcane Amalgamations) say
# what they give
seen, uniq = set(), []
for x in enchants:
    if (x["row"], x["id"]) in seen:
        continue
    seen.add((x["row"], x["id"]))
    uniq.append(x)
enchants = uniq
WORD = {"healing": "healing", "int": "intellect", "spirit": "spirit", "mp5": "MP5", "crit": "% crit", "mana": "mana"}
names = {}
for x in enchants:
    names.setdefault((x["row"], x["name"]), []).append(x)
for lst in names.values():
    if len(lst) > 1:
        for x in lst:
            x["name"] += " (" + ", ".join("+%g %s" % (v, WORD[k]) if k != "crit" else "+%g%% crit" % v
                                         for k, v in sorted(x["stats"].items())) + ")"
# what another enchant of its row beats in every stat (no proc) is hidden, as for consumables
for b in enchants:
    b["hidden"] = (not b["proc"]) and any(
        a is not b and a["row"] == b["row"] and not a["proc"] and all(a["stats"].get(k, 0) >= b["stats"].get(k, 0) for k in KEYS)
        and (any(a["stats"].get(k, 0) > b["stats"].get(k, 0) for k in KEYS) or a["id"] < b["id"])
        for a in enchants)
enchants.sort(key=lambda x: (ENCHANT_ROWS.index(x["row"]), x["id"]))

try:
    commit = subprocess.run(["git", "-C", root, "log", "-1", "--format=%H %cs"], capture_output=True, text=True).stdout.strip()
except Exception:
    commit = "unknown"


def lua(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


out = []
w = out.append
w("--[[ Holy Math - Models/ConsumableData.lua  (GENERATED - do not edit by hand)")
w("     Made by tools/gen_consumable_data.py from wowsims/forever, commit " + commit + ".")
w("     The flasks, elixirs, scrolls, food, drinks, weapon oils and other buffs a healing priest gets")
w("     something from in WoW: Forever, each in the row of what doesn't stack with it. What another item")
w("     of its row beats in every stat at the same or a lower level is hidden (kept to see you have it).")
w("     Potions and runes")
w("     are the model's (E.POTIONS). The game's own data as wowsims extracted it from the Forever client.")
w("     wowsims licence (MIT): Copyright (c) 2022 wowsims team. THE SOFTWARE IS PROVIDED \"AS IS\".")
w("]]--")
w("")
w("local _, ns = ...")
w("local D = {")
w("  source = %s," % lua("wowsims/forever " + commit))
w("  -- the rows, in order: one of each can be up at once")
w("  rows = { %s }," % ", ".join(lua(r) for r in ROW_ORDER))
w("  -- id, name, required level, row, then healing, intellect, spirit, MP5, spell crit %, maximum mana, the")
w("  -- buff's spell id (an oil: its weapon enchant's id) for seeing which one you have, and for food and")
w("  -- drink the buff's amount (many")
w("  -- share one Well Fed buff), the profession it needs (wowsims' number, 0 for none), and 1 when hidden")
w("  items = {")
for it in keep:
    s = it["stats"]
    w("    {%d,%s,%d,%s,%g,%g,%g,%g,%g,%g,%d,%d,%d,%d}," % (
        it["id"], lua(it["name"]), it["lvl"], lua(it["row"]), s.get("healing", 0), s.get("int", 0),
        s.get("spirit", 0), s.get("mp5", 0), s.get("crit", 0), s.get("mana", 0), it["aura"], it["amount"], it["prof"], 1 if it["hidden"] else 0))
w("  },")
w("  -- enchants: the slot rows, in order, then each: enchant (effect) id, the item that teaches or puts it on")
w("  -- (0: none), its spell, name, row, healing, intellect, spirit, MP5, spell crit %, maximum mana, its proc")
w("  -- (\"insight\", \"revelation\" or \"\"), and 1 when another of its row beats it in every stat")
w("  enchantRows = { %s }," % ", ".join(lua(r) for r in ENCHANT_ROWS))
w("  enchants = {")
for x in enchants:
    st = x["stats"]
    w("    {%d,%d,%d,%s,%s,%g,%g,%g,%g,%g,%g,%s,%d}," % (x["id"], x["item"], x["spell"], lua(x["name"]), lua(x["row"]),
      st.get("healing", 0), st.get("int", 0), st.get("spirit", 0), st.get("mp5", 0), st.get("crit", 0), st.get("mana", 0),
      lua(x["proc"]), 1 if x["hidden"] else 0))
w("  },")
w("}")
w("-- Holy Math is for priests only: another class leaves the rows unread")
w("local class = UnitClass and select(2, UnitClass(\"player\"))")
w("if ns and class and class ~= \"PRIEST\" then D.items, D.enchants = {}, {}; return D end")
w("for i, r in ipairs(D.items) do")
w("  local st = {}")
w("  for j, k in ipairs({ \"healing\", \"int\", \"spirit\", \"mp5\", \"crit\", \"mana\" }) do")
w("    if r[4 + j] ~= 0 then st[k] = r[4 + j] end")
w("  end")
w("  D.items[i] = { id = r[1], name = r[2], lvl = r[3], row = r[4], stats = st, aura = r[11], amount = r[12], prof = r[13],")
w("    hidden = r[14] == 1 }")
w("end")
w("D.byRow = {}")
w("for _, it in ipairs(D.items) do")
w("  D.byRow[it.row] = D.byRow[it.row] or {}")
w("  if not it.hidden then table.insert(D.byRow[it.row], it) end")
w("end")
w("for i, r in ipairs(D.enchants) do")
w("  local st = {}")
w("  for j, k in ipairs({ \"healing\", \"int\", \"spirit\", \"mp5\", \"crit\", \"mana\" }) do")
w("    if r[5 + j] ~= 0 then st[k] = r[5 + j] end")
w("  end")
w("  D.enchants[i] = { id = r[1], item = r[2], spell = r[3], name = r[4], row = r[5], stats = st,")
w("    proc = r[12] ~= \"\" and r[12] or nil, hidden = r[13] == 1, enchant = true }")
w("end")
w("D.enchantByRow = {}")
w("for _, e in ipairs(D.enchants) do")
w("  D.enchantByRow[e.row] = D.enchantByRow[e.row] or {}")
w("  if not e.hidden then table.insert(D.enchantByRow[e.row], e) end")
w("end")
w("if ns then ns.ConsumableData = D end")
w("return D")
print("\n".join(out))
print("%d consumables, %d shown" % (len(items), sum(1 for x in items if not x["hidden"])), file=sys.stderr)
