"""Read wowsims/forever's spell data AS TEXT (nothing from wowsims is run).

Shared by the class data generators (tools/gen_priest_data.py, tools/gen_paladin_data.py).
wowsims (https://github.com/wowsims/forever, MIT licence) carries the game's own spell
data, extracted from the Forever client.
"""
import os
import re
import subprocess


class Spells:
    def __init__(self, root, ladders_go):
        """root: a wowsims/forever checkout; ladders_go: the class's spell_data_auto_gen.go
        (relative to root), which names each spell's rank rows."""
        self.root = root
        src = open(os.path.join(root, "sim/core/spelldata/spells_auto_gen.go")).read()
        self.ladders = open(os.path.join(root, ladders_go)).read()
        self.mana = open(os.path.join(root, "sim/core/mana.go")).read()
        self.base_stats = open(os.path.join(root, "sim/core/base_stats_auto_gen.go")).read()

        # every spell row, one chunk per row
        self.rows = {}
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
                                    coef=num("SPCoef", b), period=num("PeriodMs", b), misc=num("Misc", b),
                                    bl=num("BaseLevel", b), ml=num("MaxLevel", b), die=num("DieSides", b),
                                    trigger=int(num("TriggerSpell", b))))
            cost = re.search(r"Powers: \[\]Power\{\{Cost: (\d+)", chunk)
            pct = re.search(r"Powers: \[\]Power\{\{[^}]*CostPct: ([\d.]+)", chunk)
            refs = re.search(r"RefIDs: \[\]int32\{([\d, ]+)\}", head)
            self.rows[int(m.group(1))] = dict(
                name=m.group(2), lvl=num("SpellLevel"), max=num("MaxLevel"), cast=num("CastTimeMs"),
                dur=num("DurationMs"), cd=num("CategoryCooldownMs") or num("CooldownMs"),
                cost=int(cost.group(1)) if cost else None, costPct=float(pct.group(1)) if pct else None,
                effects=effects, refs=[int(x) for x in refs.group(1).split(",")] if refs else [])

        # talent per-rank curves
        self.curves = {}
        cbody = src[src.index("var generatedCurves"):]
        for m in re.finditer(r"^\t(\d+):\s+\{(.*)\},\s*$", cbody, re.M):
            self.curves[int(m.group(1))] = [[float(x) for x in row.split(",")]
                                            for row in re.findall(r"\{([-\d., ]+)\}", m.group(2))]

    def ladder(self, name):
        m = re.search(r"^\t" + name + r":\s+spelldata\.(Ranked|Talent)\(([\d, ]+)\)", self.ladders, re.M)
        if not m:
            raise SystemExit("not found in the class's ladders: " + name)
        return [int(x) for x in m.group(2).split(",")]

    def effect(self, row, kinds):
        for e in row["effects"]:
            if e["type"] in kinds or e["aura"] in kinds:
                return e
        raise SystemExit("no %s effect on %s" % (kinds, row["name"]))

    def talent(self, name, row=0, f=lambda v: v):
        """A talent's value per rank (its curve row), through f."""
        return [f(v) for v in self.curves[self.ladder(name)[0]][row]]

    def crit_per_int_60(self, class_name):
        """Spell crit (percent) per point of intellect at level 60."""
        block = self.base_stats[self.base_stats.index("var CritPerIntMaxLevel"):]
        return float(re.search(r"Class_Class" + class_name + r":\s*([\d.]+)", block).group(1))

    def base_mana_60(self, class_name):
        """Base mana at level 60 (the class's ExtraClassBaseStats)."""
        block = self.base_stats[self.base_stats.index("var ExtraClassBaseStats"):]
        block = block[block.index("Class_Class" + class_name + ":"):]
        return float(re.search(r"stats\.Mana:\s*([\d.]+)", block).group(1))

    def base_spell_crit(self, class_name):
        """Base spell crit (percent) at level 60."""
        block = self.base_stats[self.base_stats.index("var ExtraClassBaseStats"):]
        block = block[block.index("Class_Class" + class_name + ":"):]
        return float(re.search(r"stats\.SpellCritPercent:\s*([\d.]+)", block).group(1))

    def regen(self):
        """Mana per second from spirit: base + spirit x per."""
        m = re.search(r"spiritRegenBase, character\.spiritRegenPerSpirit = ([\d.]+), ([\d.]+)/([\d.]+)", self.mana)
        return float(m.group(1)), float(m.group(2)) / float(m.group(3))

    def commit(self):
        try:
            return subprocess.run(["git", "-C", self.root, "log", "-1", "--format=%H %cs"],
                                  capture_output=True, text=True).stdout.strip()
        except Exception:
            return "unknown"


def rank_entry(cast_row, heal_eff, scale=1.0, cast_ms=None):
    """One rank: totals for one cast on one target (scale = ticks or bolts)."""
    # Downranking counts from the rank's max level; a row with none (0) is treated as learned level + 5,
    # the spacing every other healing rank has.
    ml = heal_eff["ml"] or cast_row["max"] or 0
    return dict(id=None, cost=cast_row["cost"], lvl=int(cast_row["lvl"]), bl=int(heal_eff["bl"] or cast_row["lvl"]),
                ml=int(ml), bp=heal_eff["bp"] * scale, ppl=heal_eff["ppl"] * scale,
                coeff=heal_eff["coef"] * scale, cast=int(cast_row["cast"] if cast_ms is None else cast_ms))


def fmt(v):
    if isinstance(v, float):
        return ("%.6f" % v).rstrip("0").rstrip(".") if v != int(v) else str(int(v))
    return str(v)


LICENCE = [
    "     wowsims licence (MIT):",
    "     Copyright (c) 2022 wowsims team",
    "     Permission is hereby granted, free of charge, to any person obtaining a copy of this software and",
    "     associated documentation files (the \"Software\"), to deal in the Software without restriction,",
    "     including without limitation the rights to use, copy, modify, merge, publish, distribute,",
    "     sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is",
    "     furnished to do so, subject to the following conditions: The above copyright notice and this",
    "     permission notice shall be included in all copies or substantial portions of the Software.",
    "     THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND.",
]
