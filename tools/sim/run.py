#!/usr/bin/env python3
"""Holy Math's big simulation: every scenario at once, then a report with charts.

Runs tools/sim/worker.lua once per scenario (gear x fight x overheal), in parallel, scores
every build found in every scenario, ranks what holds up across them all, and writes
    tools/sim/out/results.json   everything the workers found
    tools/sim/out/index.html     the report: what holds up across every scenario (playstyle,
                                 build, gear, trinkets), each scenario's best builds, talent,
                                 playstyle and trinket charts, and the check of every item
                                 effect's formula against an event-by-event simulation

Usage (run from the HolyMath folder):
    python3 -I tools/sim/run.py                      # the full run
    python3 -I tools/sim/run.py --quick              # fewer restarts and fights, for a try
    python3 -I tools/sim/run.py --restarts 40 --fights 20000 --jobs 16
    python3 -I tools/sim/run.py --overheal-from tools/wcl/out/estimates.json   # real overheal from logs

Exit code 1 when an effect's formula and the simulation disagree by more than
--tolerance (5% and 0.5 HPS), so a scheduled job can flag it.
"""
import argparse
import concurrent.futures
import datetime
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

GEARS = ["dungeon", "preraid"]
# (fight seconds, seconds between pulls, label)
FIGHTS = [
    (60, 120, "Dungeon pull (1 min, every 2 min)"),
    (120, 600, "Boss, 2 min"),
    (180, 600, "Boss, 3 min"),
    (300, 600, "Boss, 5 min"),
]
# how much healing is wasted: nobody knows a player's real overheal, so every scenario runs at
# three levels (worker.lua has the values per spell)
OVERHEALS = [("low", "Low overheal"), ("typical", "Typical overheal"), ("high", "High overheal")]
SLOT_GROUP = {"finger1": "finger", "finger2": "finger", "trinket1": "trinket", "trinket2": "trinket"}


ENV = dict(os.environ)


def run(lua, args):
    cmd = [lua, "tools/sim/worker.lua"] + [str(x) for x in args]
    out = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, env=ENV)
    if out.returncode != 0:
        raise RuntimeError("%s failed:\n%s" % (" ".join(cmd), out.stderr))
    return json.loads(out.stdout)


def lua_literal(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "{" + ", ".join(lua_literal(x) for x in v) + "}"
    return "{" + ", ".join("[%s] = %s" % (json.dumps(k), lua_literal(x)) for k, x in v.items()) + "}"


def measured_overheal(path, content, out_dir, min_fights):
    """Low, typical and high overheal per spell from tools/wcl/analyze.py's estimates: the 25th
    percentile, the median and the 75th percentile over real priest-fights. Spells with too few
    fights keep worker.lua's guesses. Returns (Lua file for the workers, what was used)."""
    est = json.load(open(path, encoding="utf-8"))
    spells = (est.get("overheal") or {}).get(content) or {}
    levels, used = {"low": {}, "typical": {}, "high": {}}, {}
    for key, q in spells.items():
        if q.get("n", 0) < min_fights:
            continue
        levels["low"][key], levels["typical"][key], levels["high"][key] = q["p25"], q["p50"], q["p75"]
        used[key] = {"fights": q["n"], "p25": q["p25"], "p50": q["p50"], "p75": q["p75"]}
    if not used:
        sys.exit("run.py: %s has no %s spell with %d fights or more" % (path, content, min_fights))
    r = levels["typical"].get("RENEW")
    names = {"low": "Low overheal (logs' 25th percentile)", "typical": "Typical overheal (logs' median)",
             "high": "High overheal (logs' 75th percentile)"}
    for lvl in levels:
        levels[lvl]["name"] = names[lvl] + ("" if r is None else ", Renew %d%%" % round(levels[lvl]["RENEW"] * 100))
    lua_path = os.path.join(out_dir, "overheal_measured.lua")
    with open(lua_path, "w", encoding="utf-8") as f:
        f.write("return " + lua_literal(levels))
    return lua_path, {"from": os.path.relpath(path, ROOT), "content": content, "spells": used,
                      "source": est.get("source"), "priestFights": est.get("priestFights")}


def data_source():
    head = open(os.path.join(ROOT, "Models/GearData.lua"), encoding="utf-8").read(2000)
    m = re.search(r'source = "([^"]+)"', head)
    return m.group(1) if m else "unknown"


def robust(results, scores):
    """Per gear, across every fight and overheal level: how each playstyle, build, trinket and
    item holds up. share = HPS / the best HPS in that scenario; avg and worst over scenarios."""
    out = {}
    for g in GEARS:
        sc = [r for r in results if r["gear"] == g]
        n = len(sc)

        def ranked(values, info):
            rows = []
            for k, per in values.items():
                rows.append(dict(info[k], avg=sum(per) / n, worst=min(per), wins=sum(1 for x in per if x >= 0.9995)))
            rows.sort(key=lambda x: (-x["avg"], -x["worst"]))
            return rows

        # playstyles, each with that scenario's best build
        vals, info = {}, {}
        for r in sc:
            top = max(p["hps"] for p in r["playstyles"])
            for p in r["playstyles"]:
                vals.setdefault(p["name"], []).append(p["hps"] / top)
                info[p["name"]] = {"name": p["name"], "extra": p.get("extra", False)}
        # an extra playstyle that heals the same as a built-in one everywhere (PoM Pen Flash
        # without Penance is Flash Heal filler) is left out
        for k in [k for k in vals if info[k]["extra"]]:
            if any(not info[o]["extra"] and len(vals[o]) == len(vals[k]) and
                   max(abs(x - y) for x, y in zip(vals[k], vals[o])) < 1e-4 for o in vals):
                del vals[k]
        play = ranked({k: v for k, v in vals.items() if len(v) == n}, info)

        # builds: every build any scenario found, scored in every scenario
        vals, info = {}, {}
        for r in sc:
            for b in r["builds"]:
                info.setdefault(b["key"], {"key": b["key"], "split": b["split"], "talents": b["talents"]})
        for r in sc:
            sc_scores = scores[(r["gear"], r["fight"], r["overheal"])]
            top = max(x["hps"] for x in sc_scores)
            for x in sc_scores:
                if x["hps"] > 0:
                    vals.setdefault(x["key"], []).append(x["hps"] / top)
                    info[x["key"]].setdefault("playstyles", {})
                    info[x["key"]]["playstyles"][x["playstyle"]] = info[x["key"]]["playstyles"].get(x["playstyle"], 0) + 1
        builds = ranked({k: v for k, v in vals.items() if len(v) == n}, info)[:6]

        # trinkets: HPS over an empty slot
        tv, tinfo = {}, {}
        for r in sc:
            for t in r["trinkets"]:
                k = "%s:%s" % (t["id"], t["name"])
                tv.setdefault(k, []).append(t["hps"])
                tinfo[k] = t
        trinkets = []
        for k, per in tv.items():
            if len(per) == n:
                t = tinfo[k]
                trinkets.append({"id": t["id"], "name": t["name"], "lvl": t["lvl"], "prof": t.get("prof"), "side": t["side"],
                                 "pvp": t.get("pvp"), "uncounted": t.get("uncounted"),
                                 "avg": sum(per) / n, "worst": min(per), "best": max(per)})
        trinkets.sort(key=lambda x: -x["avg"])

        # gear: what the Gear tab's solver picks, slot by slot, in how many scenarios
        slots = {}
        for r in sc:
            for it in r["gearItems"]:
                grp = SLOT_GROUP.get(it["slot"], it["slot"])
                d = slots.setdefault(grp, {})
                k = it.get("key") or str(it["id"])
                d.setdefault(k, {"id": it["id"], "name": it["name"], "count": 0})["count"] += 1
        gear = {k: sorted(v.values(), key=lambda x: -x["count"]) for k, v in slots.items()}
        out[g] = {"scenarios": n, "playstyles": play, "builds": builds, "trinkets": trinkets[:25], "gear": gear}
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lua", default=shutil.which("luajit") and "luajit" or "lua5.1",
                    help="Lua 5.1 interpreter: luajit (about 6x faster, the same results) when installed, else lua5.1")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    ap.add_argument("--restarts", type=int, default=12, help="random restarts of the talent search per scenario")
    ap.add_argument("--fights", type=int, default=5000, help="fights in a row the effect simulation plays")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--quick", action="store_true", help="2 restarts, 500 fights, 10%% effect tolerance")
    ap.add_argument("--tolerance", type=float, default=0.05)
    ap.add_argument("--out", default=os.path.join(HERE, "out"))
    ap.add_argument("--overheal-from", help="tools/wcl/out/estimates.json: real overheal from logs as the three levels")
    ap.add_argument("--content", default="raid", choices=["raid", "dungeon"], help="which logs' overheal to use")
    ap.add_argument("--min-fights", type=int, default=20, help="a spell's measured overheal needs this many fights")
    a = ap.parse_args()
    if a.quick:
        # few fights: a rare proc (Blue Dragon, 3% a cast) is noisy, so the check is looser
        a.restarts, a.fights, a.tolerance = 2, 500, max(a.tolerance, 0.10)
    os.makedirs(a.out, exist_ok=True)
    overheal_source = None
    if a.overheal_from:
        ENV["HM_OVERHEAL_FILE"], overheal_source = measured_overheal(a.overheal_from, a.content, a.out, a.min_fights)
        print("overheal from logs (%s): %s" % (a.content, ", ".join(
            "%s %d/%d/%d%%" % (k, v["p25"] * 100, v["p50"] * 100, v["p75"] * 100) for k, v in overheal_source["spells"].items())))

    jobs = [(g, f, p, o) for g in GEARS for f, p, _ in FIGHTS for o, _ in OVERHEALS]
    started = datetime.datetime.now(datetime.timezone.utc)
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:
        futs = {pool.submit(run, a.lua, [g, f, p, o, a.restarts, a.fights, a.seed]): (g, f, p, o) for g, f, p, o in jobs}
        for fut in concurrent.futures.as_completed(futs):
            r = fut.result()
            results.append(r)
            best = r["builds"][0]
            print("%-8s %3d s %-8s %7.1f HPS  %s  %s" % (r["gear"], r["fight"], r["overheal"], best["hps"], best["split"],
                                                       best["playstyle"]), flush=True)
    order = {(g, f, o): i for i, (g, f, _, o) in enumerate(jobs)}
    results.sort(key=lambda r: order[(r["gear"], r["fight"], r["overheal"])])

    # every build found anywhere (per gear), scored in every scenario of that gear
    cands = {}
    for r in results:
        for b in r["builds"]:
            cands.setdefault(r["gear"], {}).setdefault(b["key"], b["b"])
    scores = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:
        futs = {}
        for r in results:
            path = os.path.join(a.out, "score_%s_%d_%s.lua" % (r["gear"], r["fight"], r["overheal"]))
            with open(path, "w", encoding="utf-8") as f:
                f.write("return " + lua_literal({"stats": r["stats"],
                                                 "builds": [{"key": k, "b": b} for k, b in cands[r["gear"]].items()]}))
            futs[pool.submit(run, a.lua, [r["gear"], r["fight"], r["pull"], r["overheal"], 0, 0, a.seed, path])] = r
        for fut in concurrent.futures.as_completed(futs):
            x = fut.result()
            scores[(x["gear"], x["fight"], x["overheal"])] = x["scores"]
    for r in results:
        os.remove(os.path.join(a.out, "score_%s_%d_%s.lua" % (r["gear"], r["fight"], r["overheal"])))

    # the effect check: formula against simulation
    bad = []
    for r in results:
        for e in r["effects"]:
            d = abs(e["diff"])
            if d > 0.5 and d > a.tolerance * max(abs(e["simulated"]), 1e-9):
                bad.append("%s %d s %s: %s formula %.2f, simulated %.2f HPS" % (r["gear"], r["fight"], r["overheal"], e["name"],
                                                                               e["formula"], e["simulated"]))

    rob = robust(results, scores)
    doc = {
        "made": started.strftime("%Y-%m-%d %H:%M UTC"),
        "source": data_source(),
        "settings": {"restarts": a.restarts, "fights": a.fights, "seed": a.seed, "tolerance": a.tolerance},
        "fights": [{"fight": f, "pull": p, "label": l} for f, p, l in FIGHTS],
        "overheals": [{"key": k, "label": l} for k, l in OVERHEALS],
        "overhealSource": overheal_source,
        "gears": GEARS,
        "scenarios": results,
        "robust": rob,
        "effectProblems": bad,
    }
    with open(os.path.join(a.out, "results.json"), "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=1)
    template = open(os.path.join(HERE, "report.html"), encoding="utf-8").read()
    payload = json.dumps(doc).replace("</", "<\\/")
    with open(os.path.join(a.out, "index.html"), "w", encoding="utf-8") as f:
        f.write(template.replace("/*DATA*/null", payload))

    for g in GEARS:
        p, b = rob[g]["playstyles"][0], rob[g]["builds"][0]
        print("%s, across %d scenarios: playstyle %s (%.1f%% of the best on average, %.1f%% at worst); build %s (%.1f%%, %.1f%%)" % (
            g, rob[g]["scenarios"], p["name"], p["avg"] * 100, p["worst"] * 100, b["split"], b["avg"] * 100, b["worst"] * 100))
    print("wrote %s" % os.path.join(a.out, "index.html"))
    if bad:
        print("effect formulas that disagree with the simulation:")
        for x in bad:
            print("  " + x)
        return 1
    print("every effect formula agrees with the simulation (within %d%% or 0.5 HPS)" % round(a.tolerance * 100))
    return 0


if __name__ == "__main__":
    sys.exit(main())
