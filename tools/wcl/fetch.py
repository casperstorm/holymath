#!/usr/bin/env python3
"""Download healing priests' public logs from Warcraft Logs (forever.warcraftlogs.com).

The maintainer runs this: it needs a Warcraft Logs API client (free). Everything it
downloads goes into a cache OUTSIDE the repository (~/.cache/holymath/wcl), because logs
name other players. tools/wcl/analyze.py then turns the cache into anonymous estimates.

Setup, once:
  1. On forever.warcraftlogs.com (signed in): your profile's API clients page, "Create
     client". Name it e.g. "Holy Math", any redirect URL (http://localhost), not public.
  2. Put its ID and secret in ~/.config/holymath/wcl.env, readable only by you:
         WCL_CLIENT_ID=...
         WCL_CLIENT_SECRET=...
     chmod 600 ~/.config/holymath/wcl.env
     (or set WCL_CLIENT_ID / WCL_CLIENT_SECRET in the environment). The secret is never
     printed or written anywhere else; the tokens it gets are cached with mode 600 (the
     workflow deletes them before saving its cache).

Usage (run from the HolyMath folder):
  python3 -I tools/wcl/fetch.py discover            # zones, encounters, priest specs -> cache
  python3 -I tools/wcl/fetch.py collect             # top priest healers per encounter -> cache
  python3 -I tools/wcl/fetch.py collect --per-encounter 100 --zone 1234
Which raids and dungeons: tools/wcl/zones.txt (empty = every zone that isn't frozen).
  python3 -I tools/wcl/fetch.py report <code>       # one report you name (a public one)
  python3 -I tools/wcl/fetch.py query '<graphql>'   # anything else, printed (for checking fields)

It watches the API's points budget (rateLimitData) and waits when it's nearly used up.
"""
import argparse
import base64
import json
import os
import stat
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# Warcraft Logs runs one site per game version, each with its own API and sign-in: the
# www site answers with retail's data. These are tried in turn, each with a token from its
# own site, and the one whose zones match the most names in zones.txt is used (WCL_API and
# WCL_TOKEN_URL force one). The choice is remembered in the cache (site.json), and each
# site's answers are cached in their own folder, so ids from two sites never mix.
SITES = ([(os.environ["WCL_API"], os.environ.get("WCL_TOKEN_URL", "https://www.warcraftlogs.com/oauth/token"))]
         if os.environ.get("WCL_API") else [
    ("https://forever.warcraftlogs.com/api/v2/client", "https://forever.warcraftlogs.com/oauth/token"),
    ("https://forever.warcraftlogs.com/api/v2/client", "https://www.warcraftlogs.com/oauth/token"),
    ("https://classic.warcraftlogs.com/api/v2/client", "https://classic.warcraftlogs.com/oauth/token"),
    ("https://fresh.warcraftlogs.com/api/v2/client", "https://fresh.warcraftlogs.com/oauth/token"),
    ("https://www.warcraftlogs.com/api/v2/client", "https://www.warcraftlogs.com/oauth/token"),
])
SITE = None            # (api, token url) in use
ZONES_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "zones.txt")


def norm(name):
    """A name without case, spaces or punctuation: "diremaul" matches "Dire Maul"."""
    return "".join(ch for ch in name.lower() if ch.isalnum())


CONF = os.path.expanduser("~/.config/holymath/wcl.env")
CACHE = os.path.expanduser(os.environ.get("WCL_CACHE", "~/.cache/holymath/wcl"))
UA = "HolyMath-tools/1.0 (addon maintenance script)"


def die(msg):
    print("fetch.py: " + msg, file=sys.stderr)
    sys.exit(2)


def credentials():
    cid, sec = os.environ.get("WCL_CLIENT_ID"), os.environ.get("WCL_CLIENT_SECRET")
    if not (cid and sec) and os.path.exists(CONF):
        mode = os.stat(CONF).st_mode
        if mode & (stat.S_IRGRP | stat.S_IROTH):
            die("%s can be read by others: chmod 600 it first" % CONF)
        for line in open(CONF, encoding="utf-8"):
            k, _, v = line.strip().partition("=")
            if k == "WCL_CLIENT_ID":
                cid = v.strip()
            elif k == "WCL_CLIENT_SECRET":
                sec = v.strip()
    if not (cid and sec):
        die("no API client: put WCL_CLIENT_ID and WCL_CLIENT_SECRET in %s (see the top of this file)" % CONF)
    return cid, sec


def write_private(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)


class GQLError(Exception):
    pass


def host(url):
    return urllib.parse.urlparse(url).netloc


def token(token_url=None):
    token_url = token_url or site()[1]
    path = os.path.join(CACHE, "token_%s.json" % host(token_url))
    if os.path.exists(path):
        t = json.load(open(path, encoding="utf-8"))
        if t.get("expires_at", 0) > time.time() + 300:
            return t["access_token"]
    cid, sec = credentials()
    req = urllib.request.Request(token_url, data=b"grant_type=client_credentials", method="POST")
    req.add_header("Authorization", "Basic " + base64.b64encode(("%s:%s" % (cid, sec)).encode()).decode())
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    req.add_header("User-Agent", UA)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            t = json.load(r)
    except urllib.error.HTTPError as e:
        raise GQLError("the token request to %s failed (%d)" % (token_url, e.code))
    t["expires_at"] = time.time() + int(t.get("expires_in", 3600))
    write_private(path, json.dumps(t))
    return t["access_token"]


def post(api_url, token_url, query, variables=None):
    req = urllib.request.Request(api_url, data=json.dumps({"query": query, "variables": variables or {}}).encode(), method="POST")
    req.add_header("Authorization", "Bearer " + token(token_url))
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    req.add_header("User-Agent", UA)
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def wanted_names():
    from_file = []
    if os.path.exists(ZONES_FILE):
        for line in open(ZONES_FILE, encoding="utf-8"):
            line = line.split("#", 1)[0].strip()
            if line:
                from_file.append(norm(line))
    return set(from_file)


def site():
    """The site whose zones are Forever's: remembered, or found by asking each."""
    global SITE
    if SITE:
        return SITE
    path = os.path.join(CACHE, "site.json")
    if os.path.exists(path) and not os.environ.get("WCL_API"):
        SITE = tuple(json.load(open(path, encoding="utf-8")))
        return SITE
    wanted = wanted_names()
    best, best_score = None, -1
    for api_url, token_url in SITES:
        try:
            out = post(api_url, token_url, "{ worldData { zones { name encounters { name } } } }")
        except (GQLError, urllib.error.HTTPError, urllib.error.URLError) as e:
            code = getattr(e, "code", "")
            print("site %s (token from %s): %s %s" % (api_url, host(token_url), code, getattr(e, "reason", e)), flush=True)
            continue
        zones = ((out.get("data") or {}).get("worldData") or {}).get("zones") or []
        names = {norm(z["name"]) for z in zones} | {norm(e["name"]) for z in zones for e in (z.get("encounters") or [])}
        score = len(wanted & names)
        print("site %s (token from %s): %d zones, %d of zones.txt's names: %s" % (
            api_url, host(token_url), len(zones), score, ", ".join(z["name"] for z in zones[:6])), flush=True)
        if score > best_score:
            best, best_score = (api_url, token_url), score
    if not best or (wanted and best_score <= 0):
        die("no site's zones match zones.txt: check the names against the zones listed above")
    SITE = best
    write_private(path, json.dumps(list(best)))
    print("using %s" % best[0], flush=True)
    return SITE


def site_cache():
    return os.path.join(CACHE, host(site()[0]))


def gql(query, variables=None, fatal=True):
    """A query on the chosen site. A GraphQL error ends the run, or with fatal=False raises
    GQLError (an archived or private report: skip it)."""
    api_url, token_url = site()
    for attempt in range(5):
        try:
            out = post(api_url, token_url, query, variables)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                time.sleep(60 * (attempt + 1))
                continue
            if e.code == 401:
                try:
                    os.remove(os.path.join(CACHE, "token_%s.json" % host(token_url)))
                except OSError:
                    pass
                continue
            die("the API answered %d for %s: %s" % (e.code, api_url, e.read()[:200].decode("utf-8", "replace")))
        except GQLError as e:
            die(str(e))
        if out.get("errors"):
            msg = "; ".join(sorted({x.get("message", "?") for x in out["errors"]}))
            if fatal:
                die("GraphQL error: " + msg)
            raise GQLError(msg)
        return out["data"]
    die("the API kept refusing (rate limit?)")


_budget_checked = [0.0]


def budget():
    """Wait when the hour's points are nearly spent (checked at most once a minute)."""
    if time.time() - _budget_checked[0] < 60:
        return
    _budget_checked[0] = time.time()
    d = gql("{ rateLimitData { limitPerHour pointsSpentThisHour pointsResetIn } }")["rateLimitData"]
    if d["pointsSpentThisHour"] > 0.9 * d["limitPerHour"]:
        wait = int(d["pointsResetIn"]) + 5
        print("points budget nearly spent (%d of %d): waiting %d s" % (d["pointsSpentThisHour"], d["limitPerHour"], wait), flush=True)
        time.sleep(wait)


def cached(name, fn):
    """An answer from this site's cache folder, or fetched and kept. A report that can't be
    read (archived, private) is remembered as skipped: None."""
    path = os.path.join(site_cache(), name)
    if os.path.exists(path):
        return json.load(open(path, encoding="utf-8"))
    budget()
    try:
        data = fn()
    except GQLError as e:
        print("skipped %s: %s" % (name, e), flush=True)
        data = None
    write_private(path, json.dumps(data))
    return data


# --- discover ---------------------------------------------------------------------------
def discover(_a):
    data = gql("""{
      worldData { zones { id name frozen encounters { id name } partitions { id name default } } }
      gameData { classes { id name slug specs { id name slug } } }
    }""")
    write_private(os.path.join(site_cache(), "discover.json"), json.dumps(data, indent=1))
    priest = [c for c in data["gameData"]["classes"] if c["slug"].lower() == "priest"]
    print("priest specs:", ", ".join(s["name"] + " (" + s["slug"] + ")" for c in priest for s in c["specs"]) or "none found")
    for z in data["worldData"]["zones"]:
        print("zone %d %s: %d encounters%s" % (z["id"], z["name"], len(z["encounters"] or []), " (frozen)" if z.get("frozen") else ""))
    print("saved to " + os.path.join(site_cache(), "discover.json"))


# --- collect ----------------------------------------------------------------------------
RANKINGS = """query($enc: Int!, $cls: String!, $spec: String!, $page: Int!) {
  worldData { encounter(id: $enc) { id name
    characterRankings(className: $cls, specName: $spec, metric: hps, page: $page) } } }"""

# a fight: who was in it, how long it was, everyone's gear
REPORT_FIGHT = """query($code: String!, $fight: Int!) {
  reportData { report(code: $code) {
    code startTime zone { id name }
    fights(fightIDs: [$fight]) { id name encounterID kill startTime endTime size difficulty }
    masterData { actors(type: "Player") { id name type subType } }
    details: playerDetails(fightIDs: [$fight], includeCombatantInfo: true)
  } } }"""

# one priest in that fight: healing (with overheal) and casts, spell by spell
PRIEST_TABLES = """query($code: String!, $fight: Int!, $src: Int!) {
  reportData { report(code: $code) {
    healing: table(dataType: Healing, fightIDs: [$fight], sourceID: $src)
    casts: table(dataType: Casts, fightIDs: [$fight], sourceID: $src)
  } } }"""


def fight_and_priests(code, fight, names=None):
    """Cache the fight, then each priest in it (only those named, when names are given)."""
    f = cached("fight_%s_%d.json" % (code, fight), lambda: gql(REPORT_FIGHT, {"code": code, "fight": fight}, fatal=False))
    if not f:
        return 0
    actors = f["reportData"]["report"]["masterData"]["actors"]
    n = 0
    for act in actors:
        if (act.get("subType") or "").lower() != "priest":
            continue
        if names and act.get("name") not in names:
            continue
        cached("priest_%s_%d_%d.json" % (code, fight, act["id"]),
               lambda: gql(PRIEST_TABLES, {"code": code, "fight": fight, "src": act["id"]}, fatal=False))
        n += 1
    return n


def priest_specs():
    path = os.path.join(site_cache(), "discover.json")
    if not os.path.exists(path):
        die("run 'discover' first")
    data = json.load(open(path, encoding="utf-8"))
    for c in data["gameData"]["classes"]:
        if c["slug"].lower() == "priest":
            return c["name"], [s["name"] for s in c["specs"] if s["slug"].lower() != "shadow"]
    die("no priest class in the discover data")


def chosen_encounters(data, ids, path):
    """The encounters to collect: tools/wcl/zones.txt names zones (a raid, a dungeon) or single
    encounters (a boss), one a line, matched without case, spaces or punctuation; an empty list means every zone that
    isn't frozen. --zone ids override the file."""
    names = []
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.split("#", 1)[0].strip()
            if line:
                names.append(norm(line))
    out, matched = [], set()
    for z in data["worldData"]["zones"]:
        encs = z.get("encounters") or []
        if ids:
            if z["id"] in ids:
                out += [(z, e) for e in encs]
            continue
        if not names:
            if not z.get("frozen"):
                out += [(z, e) for e in encs]
            continue
        if norm(z["name"]) in names:
            matched.add(norm(z["name"]))
            out += [(z, e) for e in encs]
            continue
        for e in encs:
            if norm(e["name"]) in names:
                matched.add(norm(e["name"]))
                out.append((z, e))
    for n in names:
        if n not in matched:
            print("zones.txt: no zone or encounter called %r (see discover's list)" % n, flush=True)
    return out


def collect(a):
    if not os.path.exists(os.path.join(site_cache(), "discover.json")):
        die("run 'discover' first")
    data = json.load(open(os.path.join(site_cache(), "discover.json"), encoding="utf-8"))
    cls, specs = priest_specs()
    week = time.strftime("%G-W%V")      # rankings change: fetched again each week (fights don't)
    n_fights = 0
    for z, enc in chosen_encounters(data, a.zone, a.zones_file):
        for spec in specs:
            ranks = []
            for page in range(1, 100):
                got = cached("rank_%s_%d_%s_%d.json" % (week, enc["id"], spec, page),
                             lambda: gql(RANKINGS, {"enc": enc["id"], "cls": cls, "spec": spec, "page": page}, fatal=False))
                cr = ((got or {}).get("worldData") or {}).get("encounter", {}).get("characterRankings") or {}
                ranks += cr.get("rankings") or []
                if len(ranks) >= a.per_encounter or not cr.get("hasMorePages"):
                    break
            ranks = ranks[: a.per_encounter]       # the best parses: rankings come best first
            for r in ranks:
                rep = r.get("report") or {}
                code, fight = rep.get("code"), rep.get("fightID")
                if not (code and fight):
                    continue
                fight_and_priests(code, fight, names={r.get("name")})
                n_fights += 1
            print("%s / %s / %s: %d ranked priests" % (z["name"], enc["name"], spec, len(ranks)), flush=True)
    print("%d fights cached in %s" % (n_fights, CACHE))


def report(a):
    meta = gql("""query($code: String!) { reportData { report(code: $code) { fights { id encounterID kill } } } }""",
               {"code": a.code})
    fights = [f["id"] for f in meta["reportData"]["report"]["fights"] if f.get("encounterID") or a.all]
    n = 0
    for fid in fights:
        n += fight_and_priests(a.code, fid)
    print("%d fights of %s cached (%d priest entries)" % (len(fights), a.code, n))


def query(a):
    print(json.dumps(gql(a.graphql), indent=1))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("discover").set_defaults(fn=discover)
    c = sub.add_parser("collect")
    c.add_argument("--per-encounter", type=int, default=50, help="top ranked priest healers per encounter and spec")
    c.add_argument("--zone", type=int, action="append", help="only this zone id (repeatable; overrides zones.txt)")
    c.add_argument("--zones-file", default=ZONES_FILE, help="the raids, dungeons and bosses to collect (default tools/wcl/zones.txt)")
    c.set_defaults(fn=collect)
    r = sub.add_parser("report")
    r.add_argument("code")
    r.add_argument("--all", action="store_true", help="trash fights too, not only encounters")
    r.set_defaults(fn=report)
    q = sub.add_parser("query")
    q.add_argument("graphql")
    q.set_defaults(fn=query)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
