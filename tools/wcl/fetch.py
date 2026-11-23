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
  python3 -I tools/wcl/fetch.py probe               # which API serves Forever's zone 3000

It watches the API's points budget (rateLimitData) and waits when it's nearly used up.
"""
import argparse
import collections
import base64
import json
import os
import re
import stat
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# Warcraft Logs runs one site per game version. Forever's API docs
# (https://forever.warcraftlogs.com/api/docs, read 23 Nov 2026) give Forever's own token URI
# (forever.warcraftlogs.com/oauth/token) but the Classic API address
# (classic.warcraftlogs.com/api/v2/client): the token decides which game's data comes back.
# A token from Classic's own sign-in gets MoP Classic's logs, and www is retail. Holy Math uses
# WoW: Forever's logs ONLY, so the token always comes from Forever's sign-in, and a site counts
# only when its zones include at least two of zones.txt's names (Shaper's Terrace and Blackmaw
# Hold exist only in Forever). WCL_API / WCL_TOKEN_URL override the addresses.
FOREVER_TOKEN = os.environ.get("WCL_TOKEN_URL", "https://forever.warcraftlogs.com/oauth/token")
SITES = ([(os.environ["WCL_API"], FOREVER_TOKEN)] if os.environ.get("WCL_API") else [
    ("https://classic.warcraftlogs.com/api/v2/client", FOREVER_TOKEN),     # what Forever's API docs give
    ("https://forever.warcraftlogs.com/api/v2/client", FOREVER_TOKEN),
])
MIN_MATCHES = 2       # zones.txt names a site's zones must include to count as Forever's


def is_forever(site_pair):
    return urllib.parse.urlparse(site_pair[1]).netloc == urllib.parse.urlparse(FOREVER_TOKEN).netloc


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


class RateLimited(Exception):
    """The API's points for the hour are spent and the run has no time left to wait."""


DEADLINE = [0.0]       # time.time() by which a run must stop (0: no limit)


def time_left():
    return float("inf") if not DEADLINE[0] else DEADLINE[0] - time.time()


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


FOREVER_ZONES = range(3000, 3040)   # Forever's zone ids (3000 is "Dungeons"); not in the zones list


def forever_zones(api_url, token_url):
    """Forever's zones, asked for by id: the zones list leaves them out (3000 "Dungeons", 34
    encounters, each a whole dungeon: Hall of Thanes, Scholomance, ...)."""
    parts = " ".join("z%d: zone(id: %d) { id name frozen encounters { id name } }" % (i, i) for i in FOREVER_ZONES)
    out = post(api_url, token_url, "{ worldData { %s } }" % parts)
    wd = (out.get("data") or {}).get("worldData") or {}
    return [z for z in (wd.get("z%d" % i) for i in FOREVER_ZONES) if z]


def site():
    """The API and sign-in to use: Forever's token (always) with the first API address whose
    Forever zones (3000 up) hold at least two of zones.txt's names. Remembered in site.json."""
    global SITE
    if SITE:
        return SITE
    path = os.path.join(CACHE, "site.json")
    if os.path.exists(path) and not os.environ.get("WCL_API"):
        SITE = tuple(json.load(open(path, encoding="utf-8")))
        if is_forever(SITE):
            return SITE
        SITE = None                          # a remembered non-Forever choice: find Forever's again
    wanted = wanted_names()
    for api_url, token_url in SITES:
        if not is_forever((api_url, token_url)):
            continue
        try:
            zones = forever_zones(api_url, token_url)
        except (GQLError, urllib.error.HTTPError, urllib.error.URLError) as e:
            print("site %s (token from %s): %s %s" % (api_url, host(token_url), getattr(e, "code", ""), getattr(e, "reason", e)), flush=True)
            continue
        names = {norm(z["name"]) for z in zones} | {norm(e["name"]) for z in zones for e in (z.get("encounters") or [])}
        score = len(wanted & names)
        print("site %s (token from %s): Forever zones %s; %d of zones.txt's names" % (
            api_url, host(token_url), ", ".join("%d %s" % (z["id"], z["name"]) for z in zones), score), flush=True)
        if zones and score >= min(MIN_MATCHES, len(wanted)):
            SITE = (api_url, token_url)
            write_private(path, json.dumps(list(SITE)))
            print("using %s with a token from %s" % (api_url, host(token_url)), flush=True)
            return SITE
    die("no API gave Forever's zones (3000 up) with zones.txt's names (see https://forever.warcraftlogs.com/api/docs; WCL_API sets it)")


def site_cache():
    """This site's cache folder: named after the API address and the sign-in, since one API
    address serves different games' data depending on the token."""
    api_url, token_url = site()
    return os.path.join(CACHE, "%s__%s" % (host(api_url), host(token_url)))


def gql(query, variables=None, fatal=True):
    """A query on the chosen site. A GraphQL error ends the run, or with fatal=False raises
    GQLError (an archived or private report: skip it)."""
    api_url, token_url = site()
    for attempt in range(5):
        try:
            out = post(api_url, token_url, query, variables)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                wait = int(e.headers.get("Retry-After") or 0) or 60 * (attempt + 1)
                if wait + 30 > time_left() or attempt >= 3:
                    raise RateLimited("the API answered 429 (points spent)")
                print("429: waiting %d s" % wait, flush=True)
                time.sleep(wait)
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
    raise RateLimited("the API kept refusing")


_budget_checked = [0.0]


def points():
    return gql("{ rateLimitData { limitPerHour pointsSpentThisHour pointsResetIn } }")["rateLimitData"]


def budget():
    """Wait when the hour's points are nearly spent (checked every 20 s), or stop the run
    (RateLimited) when the wait wouldn't fit in its time."""
    if time.time() - _budget_checked[0] < 20:
        return
    _budget_checked[0] = time.time()
    d = points()
    if d["pointsSpentThisHour"] > 0.93 * d["limitPerHour"]:
        wait = int(d["pointsResetIn"]) + 10
        if wait + 60 > time_left():
            raise RateLimited("points for the hour spent (%d of %d), no time left to wait" % (d["pointsSpentThisHour"], d["limitPerHour"]))
        print("points for the hour nearly spent (%d of %d): waiting %d s" % (d["pointsSpentThisHour"], d["limitPerHour"], wait), flush=True)
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
    """Forever's zones (asked for by id, 3000 up) and the priest specs, into discover.json."""
    api_url, token_url = site()
    zones = forever_zones(api_url, token_url)
    data = gql("{ gameData { classes { id name slug specs { id name slug } } } }")
    data["worldData"] = {"zones": zones}
    write_private(os.path.join(site_cache(), "discover.json"), json.dumps(data, indent=1))
    priest = [c for c in data["gameData"]["classes"] if c["slug"].lower() == "priest"]
    print("priest specs:", ", ".join(s["name"] + " (" + s["slug"] + ")" for c in priest for s in c["specs"]) or "none found")
    for z in zones:
        print("zone %d %s%s: %s" % (z["id"], z["name"], " (frozen)" if z.get("frozen") else "",
                                    ", ".join("%d %s" % (e["id"], e["name"]) for e in (z.get("encounters") or []))))
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


def fight_and_priests(code, fight, names=None, ids=None):
    """Cache the fight, then each priest in it (only those named, or with those actor ids)."""
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
        if ids is not None and act["id"] not in ids:
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


# a report's outline: its zone, its encounter fights and who was in each
REPORT_META = """query($code: String!) {
  reportData { report(code: $code) {
    code startTime zone { id name }
    fights(killType: Encounters) { id encounterID name kill size startTime endTime friendlyPlayers }
    masterData { actors(type: "Player") { id name subType } }
  } } }"""

REPORTS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "reports.txt")
CODE = re.compile(r"(?:reports/)?\b([A-Za-z0-9]{16})\b")


def seed_codes(a):
    """Report codes to read: tools/wcl/reports.txt (links or codes, one a line), --seeds files
    (any text: codes are picked out, e.g. wowsims' evidence notes), and every code found before
    (codes.txt in the cache)."""
    codes, seen = [], set()

    def add(text):
        for m in CODE.finditer(text):
            c = m.group(1)
            if c not in seen and any(ch.isdigit() for ch in c) and any(ch.isupper() for ch in c) and any(ch.islower() for ch in c):
                seen.add(c)
                codes.append(c)
    for path in [REPORTS_FILE, os.path.join(site_cache(), "codes.txt")] + (a.seeds or []):
        if os.path.isdir(path):
            for root, _, files in os.walk(path):
                for f in files:
                    if f.endswith((".md", ".txt", ".json")):
                        add(open(os.path.join(root, f), encoding="utf-8", errors="replace").read())
        elif os.path.exists(path):
            add(open(path, encoding="utf-8", errors="replace").read())
    write_private(os.path.join(site_cache(), "codes.txt"), "\n".join(codes) + "\n")
    return codes


def collect(a):
    """Read report outlines (cheap, cached for good), keep the kills of the chosen encounters
    (zones.txt), and cache every priest in them: healing with overheal, casts, gear.
    analyze.py then keeps the best parses (top HPS per encounter). Raid encounters' top-ranked
    priests are added when Warcraft Logs ranks them (it ranks no Forever dungeon)."""
    if not os.path.exists(os.path.join(site_cache(), "discover.json")):
        die("run 'discover' first")
    if a.max_minutes:
        DEADLINE[0] = time.time() + a.max_minutes * 60
    data = json.load(open(os.path.join(site_cache(), "discover.json"), encoding="utf-8"))
    chosen = chosen_encounters(data, a.zone, a.zones_file)
    wanted = {e["id"]: (z, e) for z, e in chosen}
    if not wanted:
        die("no encounters chosen (zones.txt)")
    zone_ids = {z["id"] for z, _ in chosen}

    # raids: Warcraft Logs' own rankings, when it has them
    cls, specs = priest_specs()
    week = time.strftime("%G-W%V")
    ranked = 0
    for z, enc in chosen:
        if z["id"] == 3000:
            continue                                   # dungeons: "Invalid raid zone specified"
        for spec in specs:
            name = "rank_%s_%d_%s_1.json" % (week, enc["id"], spec)
            got = cached(name, lambda: gql(RANKINGS, {"enc": enc["id"], "cls": cls, "spec": spec, "page": 1}, fatal=False))
            cr = ((got or {}).get("worldData") or {}).get("encounter", {}).get("characterRankings") or {}
            if not cr.get("rankings"):
                os.remove(os.path.join(site_cache(), name))
            for r in (cr.get("rankings") or [])[: a.per_encounter]:
                rp = r.get("report") or {}
                if rp.get("code") and rp.get("fightID"):
                    ranked += fight_and_priests(rp["code"], rp["fightID"], names={r.get("name")})

    # every report we know of
    try:
        d = points()
        print("API points: %d of %d spent this hour" % (d["pointsSpentThisHour"], d["limitPerHour"]), flush=True)
        read_reports(a, wanted, zone_ids, ranked)
        d = points()
        print("API points: %d of %d spent this hour" % (d["pointsSpentThisHour"], d["limitPerHour"]), flush=True)
    except RateLimited as e:
        print("stopping: %s; the next run carries on from the cache" % e, flush=True)


def read_reports(a, wanted, zone_ids, ranked):
    codes = seed_codes(a)
    print("%d report codes to read (%d ranked raid priests)" % (len(codes), ranked), flush=True)
    per_enc = collections.Counter()
    read = priests = 0
    for code in codes:
        if a.max_reports and read >= a.max_reports:
            print("stopping at --max-reports %d" % a.max_reports, flush=True)
            break
        meta_name = "report_%s.json" % code
        fresh = not os.path.exists(os.path.join(site_cache(), meta_name))
        m = cached(meta_name, lambda: gql(REPORT_META, {"code": code}, fatal=False))
        read += fresh
        r = ((m or {}).get("reportData") or {}).get("report") or {}
        if (r.get("zone") or {}).get("id") not in zone_ids:
            continue
        pri = {act["id"] for act in (r.get("masterData") or {}).get("actors") or [] if (act.get("subType") or "").lower() == "priest"}
        for f in r.get("fights") or []:
            if f.get("encounterID") not in wanted or not f.get("kill"):
                continue
            here = pri & set(f.get("friendlyPlayers") or pri)
            if not here:
                continue
            priests += fight_and_priests(code, f["id"], ids=here)
            per_enc[f["encounterID"]] += len(here)
        if read and read % 200 == 0 and fresh:
            print("read %d reports, %d priest-fights so far" % (read, priests), flush=True)
    for eid, n in sorted(per_enc.items(), key=lambda x: -x[1]):
        print("%-28s %d priest-fights" % (wanted[eid][1]["name"], n), flush=True)
    print("%d reports read this run, %d priest-fights cached in %s" % (read, priests, site_cache()))


def report(a):
    meta = gql("""query($code: String!) { reportData { report(code: $code) { fights { id encounterID kill } } } }""",
               {"code": a.code})
    fights = [f["id"] for f in meta["reportData"]["report"]["fights"] if f.get("encounterID") or a.all]
    n = 0
    for fid in fights:
        n += fight_and_priests(a.code, fid)
    print("%d fights of %s cached (%d priest entries)" % (len(fights), a.code, n))


def probe(_a):
    """Ask each Warcraft Logs API (with Forever's token and with its own site's) for Forever's
    zone 3000 (wowsims' evidence names it: "forever.warcraftlogs.com, zone 3000") and for the
    game versions it serves. Prints what answers; changes nothing."""
    q = "{ worldData { zone(id: 3000) { id name frozen encounters { id name } } expansions { id name } } }"
    for api_host in ["classic", "fresh", "forever", "www", "sod", "vanilla"]:
        api_url = "https://%s.warcraftlogs.com/api/v2/client" % api_host
        for tok_host in sorted({"forever", api_host}):
            token_url = "https://%s.warcraftlogs.com/oauth/token" % tok_host
            try:
                out = post(api_url, token_url, q)
                d = (out.get("data") or {}).get("worldData") or {}
                z = d.get("zone")
                print("%-8s token %-8s zone 3000: %s; expansions: %s%s" % (
                    api_host, tok_host,
                    ("%s (%d encounters: %s)" % (z["name"], len(z.get("encounters") or []),
                     ", ".join(e["name"] for e in (z.get("encounters") or [])[:12]))) if z else "none",
                    ", ".join("%s %s" % (e["id"], e["name"]) for e in (d.get("expansions") or [])),
                    ("; errors: " + "; ".join(x.get("message", "?") for x in out["errors"])) if out.get("errors") else ""), flush=True)
            except (GQLError, urllib.error.HTTPError, urllib.error.URLError) as e:
                print("%-8s token %-8s %s %s" % (api_host, tok_host, getattr(e, "code", ""), getattr(e, "reason", e)), flush=True)


def query(a):
    print(json.dumps(gql(a.graphql), indent=1))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("discover").set_defaults(fn=discover)
    sub.add_parser("probe").set_defaults(fn=probe)
    c = sub.add_parser("collect")
    c.add_argument("--per-encounter", type=int, default=50, help="raids: top-ranked priest healers per encounter and spec")
    c.add_argument("--seeds", action="append", help="a file or folder of report codes or links (repeatable), e.g. wowsims' docs/evidence")
    c.add_argument("--max-reports", type=int, default=0, help="read at most this many new reports this run (0: all)")
    c.add_argument("--max-minutes", type=int, default=0, help="stop cleanly after this long, waiting out spent points until then (0: no limit)")
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
