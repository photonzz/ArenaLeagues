#!/usr/bin/env python3
"""Generate ArenaLeagues/SpecDistribution.lua from Blizzard's PvP leaderboard API.

Per-spec rating->percentile curves for Solo Shuffle (bracket 7) and BG Blitz
(bracket 9), which Blizzard exposes as native per-spec leaderboards. Re-run
periodically (e.g. weekly) to refresh as the season inflates.

Usage:  python3 gen_specdist.py [region]      (region defaults to eu)
Reads Battle.net client creds from ~/.battlenet-api-creds
"""
import json, os, sys, time, urllib.request, urllib.parse, base64, re, math

REGION = (sys.argv[1] if len(sys.argv) > 1 else os.environ.get("REGION", "eu")).lower()
CREDS = os.path.expanduser("~/.battlenet-api-creds")
OUT = os.environ.get(
    "SPECDIST_OUT",
    "/mnt/c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/ArenaLeagues/SpecDistribution.lua",
)

# Brackets we can do per-spec, mapped to the addon's GetPersonalRatedInfo index.
BRACKET_INDEX = {"shuffle": 7, "blitz": 9}

# Percentile sample points (top X%). Denser near the top where it matters most.
PCT_TARGETS = [100, 90, 80, 70, 60, 50, 40, 30, 25, 20, 15, 10, 7, 5, 3, 2, 1, 0.5]

def creds():
    # Prefer env vars (GitHub Actions secrets); fall back to the local file.
    cid = os.environ.get("BNET_CLIENT_ID")
    sec = os.environ.get("BNET_CLIENT_SECRET")
    if cid and sec:
        return cid, sec
    d = {}
    for line in open(CREDS):
        if "=" in line:
            k, v = line.strip().split("=", 1); d[k] = v
    return d["CLIENT_ID"], d["CLIENT_SECRET"]

def get_token(cid, secret):
    req = urllib.request.Request(
        "https://oauth.battle.net/token",
        data=b"grant_type=client_credentials",
        headers={"Authorization": "Basic " + base64.b64encode(f"{cid}:{secret}".encode()).decode()},
    )
    return json.load(urllib.request.urlopen(req))["access_token"]

API = f"https://{REGION}.api.blizzard.com"
TOKEN = None

def fetch(path, namespace):
    url = f"{API}{path}?namespace={namespace}-{REGION}&locale=en_US"
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}"})
            return json.load(urllib.request.urlopen(req, timeout=30))
        except Exception as e:
            if attempt == 3:
                raise
            time.sleep(0.5 * (attempt + 1))

def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())

def build_spec_map():
    """slug 'class+spec' (normalized) -> spec id, e.g. 'paladinretribution' -> 70."""
    idx = fetch("/data/wow/playable-specialization/index", "static")
    specs = idx.get("character_specializations", idx.get("specializations", []))
    out = {}
    for s in specs:
        det = fetch(f"/data/wow/playable-specialization/{s['id']}", "static")
        cls = det.get("playable_class", {}).get("name", "")
        out[norm(cls) + norm(det["name"])] = s["id"]
    return out

def curve(ratings):
    """ratings: list of ints. Return (floor, [[rating, topPct], ...] ascending)."""
    rs = sorted(ratings, reverse=True)
    n = len(rs)
    anchors = []
    seen = set()
    for pct in PCT_TARGETS:
        k = max(1, min(n, math.ceil(pct / 100.0 * n)))
        rating = rs[k - 1]
        if rating in seen:
            continue
        seen.add(rating)
        anchors.append((rating, round(pct, 2)))
    anchors.sort(key=lambda a: a[0])     # ascending rating
    return rs[-1], anchors, n

def main():
    global TOKEN
    cid, secret = creds()
    TOKEN = get_token(cid, secret)

    season = fetch("/data/wow/pvp-season/index", "dynamic")["current_season"]["id"]
    print(f"region={REGION} season={season}")

    spec_map = build_spec_map()
    print(f"spec map: {len(spec_map)} specs")

    lbidx = fetch(f"/data/wow/pvp-season/{season}/pvp-leaderboard/index", "dynamic")
    names = [x["name"] for x in lbidx.get("leaderboards", [])]

    # data[bracketIndex][specID] = {floor, n, dist}
    data = {7: {}, 9: {}}
    for name in names:
        m = re.match(r"(shuffle|blitz)-([a-z]+)-([a-z]+)$", name)
        if not m:
            continue
        kind, cls, spec = m.groups()
        bidx = BRACKET_INDEX[kind]
        specid = spec_map.get(cls + spec)
        if not specid:
            print(f"  ! no spec id for {name} ({cls+spec})"); continue
        lb = fetch(f"/data/wow/pvp-season/{season}/pvp-leaderboard/{name}", "dynamic")
        ratings = [e["rating"] for e in lb.get("entries", [])]
        if len(ratings) < 50:
            print(f"  ~ {name}: only {len(ratings)} entries, skipping"); continue
        floor, anchors, n = curve(ratings)
        data[bidx][specid] = {"floor": floor, "n": n, "dist": anchors}
        print(f"  {name} -> spec {specid}: n={n} floor={floor}")

    write_lua(data, season)
    print("wrote", OUT)

def write_lua(data, season):
    L = []
    L.append("-- ArenaLeagues :: SpecDistribution.lua  (AUTO-GENERATED -- do not edit)")
    L.append(f"-- Source: Blizzard PvP leaderboard API, region {REGION.upper()}, season {season}.")
    L.append("-- Per-spec top%% curves for Solo Shuffle (7) and Blitz (9).")
    L.append("-- Regenerate with arenaleagues-tools/gen_specdist.py")
    L.append("local _, ns = ...")
    L.append("ns.SpecDist = {")
    L.append(f"  region = {ns_str(REGION.upper())}, season = {season},")
    L.append("  brackets = {")
    for bidx in (7, 9):
        L.append(f"    [{bidx}] = {{")
        for specid in sorted(data[bidx]):
            d = data[bidx][specid]
            pairs = ", ".join("{%d,%s}" % (r, fmtpct(p)) for r, p in d["dist"])
            L.append(f"      [{specid}] = {{ floor = {d['floor']}, n = {d['n']}, dist = {{ {pairs} }} }},")
        L.append("    },")
    L.append("  },")
    L.append("}")
    with open(OUT, "w") as f:
        f.write("\n".join(L) + "\n")

def fmtpct(p):
    return str(int(p)) if float(p).is_integer() else ("%.1f" % p)

def ns_str(s):
    return '"' + s + '"'

if __name__ == "__main__":
    main()
