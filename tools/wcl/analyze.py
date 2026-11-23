#!/usr/bin/env python3
"""Turn the Warcraft Logs cache (tools/wcl/fetch.py) into anonymous estimates for Holy Math.

Reads ~/.cache/holymath/wcl (or WCL_CACHE) and writes tools/wcl/out/estimates.json with no
player names and no report codes in it:
  overheal      per spell (the model's keys: RENEW, GH, FLASH, ...): its quartiles over
                priest-fights, and the healing-weighted overall share, for raids and dungeons;
                only the best parses count: per encounter, the top --top priest-fights by HPS
  share         each spell's share of a priest's healing, and its casts a minute (medians)
  fightLength   seconds, quartiles, for raids and dungeons
  gear          the items top priests wear, most worn first, with Holy Math's name for each
                (from Models/GearData.lua) or "not in Holy Math's data"

tools/sim/run.py --overheal-from tools/wcl/out/estimates.json uses the quartiles as its low,
typical and high overheal levels.

Usage (run from the HolyMath folder; no API key needed):
  python3 -I tools/wcl/analyze.py
  python3 -I tools/wcl/analyze.py --min-healing 20000 --content raid
"""
import argparse
import collections
import glob
import json
import os
import re
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CACHE = os.path.expanduser(os.environ.get("WCL_CACHE", "~/.cache/holymath/wcl"))

# Warcraft Logs' spell names (no ranks) to the model's spell keys
SPELLS = {
    "Renew": "RENEW", "Greater Heal": "GH", "Flash Heal": "FLASH", "Heal": "HEAL", "Lesser Heal": "LESSER",
    "Prayer of Healing": "POH", "Holy Nova": "NOVA", "Prayer of Mending": "POM", "Penance": "PENANCE",
    "Power Word: Shield": "PWS", "Binding Heal": "BH", "Holy Binding": "BH",
}
NO_OVERHEAL = {"PWS"}      # an absorb has no overheal in the logs (what isn't absorbed just fades)


def entries(table):
    """A table's rows, whatever the wrapping: {data: {entries}} or {entries}, flattening
    per-target rows that hold their abilities."""
    if not isinstance(table, dict):
        return []
    t = table.get("data", table)
    rows = t.get("entries") or []
    out = []
    for r in rows:
        if isinstance(r, dict) and r.get("abilities") and "guid" not in r:
            out.extend(r["abilities"])
        elif isinstance(r, dict):
            out.append(r)
    return out


def quartiles(xs):
    xs = sorted(xs)
    if not xs:
        return None
    if len(xs) == 1:
        return {"n": 1, "p25": xs[0], "p50": xs[0], "p75": xs[0]}
    q = statistics.quantiles(xs, n=4, method="inclusive")
    return {"n": len(xs), "p25": q[0], "p50": q[1], "p75": q[2]}


def gear_names():
    names = {}
    text = open(os.path.join(ROOT, "Models/GearData.lua"), encoding="utf-8").read()
    for m in re.finditer(r'\{(\d+),"([^"]+)",(\d+),', text):
        iid, name, sfx = int(m.group(1)), m.group(2), int(m.group(3))
        if sfx == 0 or iid not in names:
            names[iid] = re.sub(r" of [A-Z][\w' ]+$", "", name) if sfx else name
    return names


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--min-healing", type=int, default=10000,
                    help="a spell counts in a fight only with this much healing (done + overhealed)")
    ap.add_argument("--top", type=int, default=50,
                    help="the best parses: keep the top this many priest-fights by healing per second, per encounter (0: all)")
    ap.add_argument("--out", default=os.path.join(HERE, "out", "estimates.json"))
    a = ap.parse_args()

    # only the site fetch.py uses now (site.json: Forever's); other folders hold other games' logs
    site_path = os.path.join(CACHE, "site.json")
    if not os.path.exists(site_path):
        sys.exit("analyze.py: no site.json in %s: run tools/wcl/fetch.py first" % CACHE)
    api_url, token_url = json.load(open(site_path, encoding="utf-8"))
    net = lambda u: u.split("//", 1)[-1].split("/", 1)[0]
    folder = os.path.join(CACHE, "%s__%s" % (net(api_url), net(token_url)))
    files = sorted(glob.glob(os.path.join(folder, "priest_*.json")))
    if not files:
        sys.exit("analyze.py: nothing in %s: run tools/wcl/fetch.py first" % CACHE)

    # the best parses: per encounter, the priest-fights with the most healing per second
    if a.top:
        by_enc = collections.defaultdict(list)
        for path in files:
            m = re.match(r"priest_(.+)_(\d+)_(\d+)\.json$", os.path.basename(path))
            fpath = m and os.path.join(os.path.dirname(path), "fight_%s_%s.json" % (m.group(1), m.group(2)))
            if not (fpath and os.path.exists(fpath)):
                continue
            fd, pd = json.load(open(fpath, encoding="utf-8")), json.load(open(path, encoding="utf-8"))
            if not (fd and pd):
                continue
            fights = fd["reportData"]["report"].get("fights") or []
            if not fights:
                continue
            f = fights[0]
            secs = max(1.0, (f["endTime"] - f["startTime"]) / 1000)
            done = sum(e.get("total", 0) or 0 for e in entries(pd["reportData"]["report"].get("healing")))
            by_enc[f.get("encounterID")].append((done / secs, path))
        keep = set()
        for enc, rows in by_enc.items():
            rows.sort(reverse=True)
            keep.update(p for _, p in rows[: a.top])
        files = [f for f in files if f in keep]

    oh = collections.defaultdict(lambda: collections.defaultdict(list))        # kind -> spell -> [share]
    ohw = collections.defaultdict(lambda: collections.defaultdict(lambda: [0.0, 0.0]))  # kind -> spell -> [over, raw]
    share = collections.defaultdict(lambda: collections.defaultdict(list))     # kind -> spell -> [share of healing]
    cpm = collections.defaultdict(lambda: collections.defaultdict(list))       # kind -> spell -> [casts a minute]
    length = collections.defaultdict(list)
    gear = collections.Counter()
    gear_priests = 0
    seen_fights, n_priests = set(), collections.Counter()
    unknown = collections.Counter()

    for path in files:
        m = re.match(r"priest_(.+)_(\d+)_(\d+)\.json$", os.path.basename(path))
        if not m:
            continue
        code, fid, src = m.group(1), int(m.group(2)), int(m.group(3))
        fpath = os.path.join(os.path.dirname(path), "fight_%s_%d.json" % (code, fid))
        if not os.path.exists(fpath):
            continue
        fdata, pdata = json.load(open(fpath, encoding="utf-8")), json.load(open(path, encoding="utf-8"))
        if not (fdata and pdata):
            continue                         # skipped: archived or private
        rep = fdata["reportData"]["report"]
        fights = rep.get("fights") or []
        if not fights:
            continue
        fight = fights[0]
        secs = max(1.0, (fight["endTime"] - fight["startTime"]) / 1000)
        kind = "dungeon" if (fight.get("size") or 0) and fight["size"] <= 5 else "raid"
        if (code, fid) not in seen_fights:
            seen_fights.add((code, fid))
            length[kind].append(secs)
        n_priests[kind] += 1

        pr = pdata["reportData"]["report"]
        heals = entries(pr.get("healing"))
        total = sum(e.get("total", 0) or 0 for e in heals)
        per = collections.defaultdict(lambda: [0.0, 0.0])
        for e in heals:
            key = SPELLS.get(e.get("name", ""))
            if not key:
                unknown[e.get("name", "?")] += e.get("total", 0) or 0
                continue
            per[key][0] += e.get("total", 0) or 0
            per[key][1] += e.get("overheal", 0) or 0
        for key, (done, over) in per.items():
            raw = done + over
            if total > 0:
                share[kind][key].append(done / total)
            if key in NO_OVERHEAL or raw < a.min_healing:
                continue
            oh[kind][key].append(over / raw)
            ohw[kind][key][0] += over
            ohw[kind][key][1] += raw
        for e in entries(pr.get("casts")):
            key = SPELLS.get(e.get("name", ""))
            if key:
                cpm[kind][key].append((e.get("total", 0) or 0) / secs * 60)

        # what this priest wore (playerDetails: healers / dps / tanks, each with combatantInfo.gear)
        det = (rep.get("details") or {})
        det = det.get("data", det).get("playerDetails", det.get("data", det)) if isinstance(det, dict) else {}
        for role in ("healers", "dps", "tanks"):
            for p in (det.get(role) or []) if isinstance(det, dict) else []:
                if p.get("id") == src:
                    items = ((p.get("combatantInfo") or {}).get("gear")) or []
                    ids = {g.get("id") for g in items if isinstance(g, dict) and g.get("id")}
                    if ids:
                        gear_priests += 1
                        gear.update(ids)

    names = gear_names()
    out = {
        "source": "Warcraft Logs, WoW: Forever (token from %s, API %s), top-ranked priest healers" % (net(token_url), net(api_url)),
        "priestFights": dict(n_priests),
        "fights": {k: len(v) for k, v in length.items()},
        "minHealing": a.min_healing,
        "topPerEncounter": a.top,
        "overheal": {kind: {k: dict(quartiles(v), overall=ohw[kind][k][0] / ohw[kind][k][1])
                            for k, v in spells.items() if v} for kind, spells in oh.items()},
        "share": {kind: {k: {"healing": statistics.median(v), "castsPerMinute": statistics.median(cpm[kind][k]) if cpm[kind][k] else None}
                         for k, v in spells.items() if v} for kind, spells in share.items()},
        "fightLength": {k: quartiles(v) for k, v in length.items()},
        "gear": [{"id": i, "name": names.get(i, "not in Holy Math's data"), "wornBy": c / max(1, gear_priests)}
                 for i, c in gear.most_common(60)],
        "otherHealing": [{"name": n, "healing": t} for n, t in unknown.most_common(10)],
    }
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)

    print("priest-fights: %s; fights: %s" % (dict(n_priests), {k: len(v) for k, v in length.items()}))
    for kind, spells in out["overheal"].items():
        print("%s overheal (25%% / median / 75%%, overall):" % kind)
        for k, q in sorted(spells.items(), key=lambda x: -x[1]["n"]):
            print("  %-8s %3.0f%% / %3.0f%% / %3.0f%%  overall %3.0f%%  (%d fights)" % (
                k, q["p25"] * 100, q["p50"] * 100, q["p75"] * 100, q["overall"] * 100, q["n"]))
    for kind, q in out["fightLength"].items():
        if q:
            print("%s fight length: %.0f / %.0f / %.0f s" % (kind, q["p25"], q["p50"], q["p75"]))
    print("wrote " + a.out)


if __name__ == "__main__":
    main()
