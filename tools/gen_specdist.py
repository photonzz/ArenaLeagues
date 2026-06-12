#!/usr/bin/env python3
"""Generate ArenaLeagues/SpecDistribution.lua from Blizzard's PvP leaderboard API.

Per-spec rating->percentile curves for Solo Shuffle (bracket 7) and BG Blitz
(bracket 9) -- the brackets Blizzard exposes as native per-spec leaderboards --
for EACH region. The addon picks the curve for the player's region at runtime.

Usage:   python3 gen_specdist.py [region ...]      (default: eu us)
Creds:   env BNET_CLIENT_ID / BNET_CLIENT_SECRET, else ~/.battlenet-api-creds
Output:  env SPECDIST_OUT, else the local WoW AddOns path.
"""
import json, os, sys, time, urllib.request, base64, re, math

CREDS = os.path.expanduser("~/.battlenet-api-creds")
OUT = os.environ.get(
    "SPECDIST_OUT",
    "/mnt/c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/ArenaLeagues/SpecDistribution.lua",
)

def regions():
    if len(sys.argv) > 1:
        return [r.lower() for r in sys.argv[1:]]
    env = os.environ.get("REGIONS")
    if env:
        return [r.lower() for r in re.split(r"[,\s]+", env.strip()) if r]
    return ["eu", "us"]

BRACKET_INDEX = {"shuffle": 7, "blitz": 9}
PCT_TARGETS = [100, 90, 80, 70, 60, 50, 40, 30, 25, 20, 15, 10, 7, 5, 3, 2, 1, 0.5]
TOKEN = None

def creds():
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

def fetch(region, path, ns_kind):
    url = f"https://{region}.api.blizzard.com{path}?namespace={ns_kind}-{region}&locale=en_US"
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}"})
            return json.load(urllib.request.urlopen(req, timeout=30))
        except Exception:
            if attempt == 3:
                raise
            time.sleep(0.5 * (attempt + 1))

def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())

def build_spec_map(region):
    """slug 'class+spec' (normalized) -> spec id. Static data, region-agnostic."""
    idx = fetch(region, "/data/wow/playable-specialization/index", "static")
    specs = idx.get("character_specializations", idx.get("specializations", []))
    out = {}
    for s in specs:
        det = fetch(region, f"/data/wow/playable-specialization/{s['id']}", "static")
        cls = det.get("playable_class", {}).get("name", "")
        out[norm(cls) + norm(det["name"])] = s["id"]
    return out

def curve(ratings):
    rs = sorted(ratings, reverse=True)
    n = len(rs)
    anchors, seen = [], set()
    for pct in PCT_TARGETS:
        k = max(1, min(n, math.ceil(pct / 100.0 * n)))
        rating = rs[k - 1]
        if rating in seen:
            continue
        seen.add(rating)
        anchors.append((rating, round(pct, 2)))
    anchors.sort(key=lambda a: a[0])
    return rs[-1], anchors, n

def gather_region(region, spec_map):
    season = fetch(region, "/data/wow/pvp-season/index", "dynamic")["current_season"]["id"]
    print(f"[{region}] season={season}")
    lbidx = fetch(region, f"/data/wow/pvp-season/{season}/pvp-leaderboard/index", "dynamic")
    names = [x["name"] for x in lbidx.get("leaderboards", [])]
    data = {7: {}, 9: {}}
    for name in names:
        m = re.match(r"(shuffle|blitz)-([a-z]+)-([a-z]+)$", name)
        if not m:
            continue
        kind, cls, spec = m.groups()
        bidx = BRACKET_INDEX[kind]
        specid = spec_map.get(cls + spec)
        if not specid:
            print(f"  ! no spec id for {name}"); continue
        lb = fetch(region, f"/data/wow/pvp-season/{season}/pvp-leaderboard/{name}", "dynamic")
        ratings = [e["rating"] for e in lb.get("entries", [])]
        if len(ratings) < 50:
            continue
        floor, anchors, n = curve(ratings)
        data[bidx][specid] = {"floor": floor, "n": n, "dist": anchors}
    print(f"[{region}] shuffle={len(data[7])} blitz={len(data[9])} specs")
    return season, data

def main():
    global TOKEN
    cid, secret = creds()
    TOKEN = get_token(cid, secret)
    regs = regions()
    spec_map = build_spec_map(regs[0])
    print(f"spec map: {len(spec_map)} specs")
    out = {}
    for region in regs:
        season, data = gather_region(region, spec_map)
        out[region.upper()] = {"season": season, "brackets": data}
    write_lua(out)
    print("wrote", OUT)

def fmtpct(p):
    return str(int(p)) if float(p).is_integer() else ("%.1f" % p)

def write_lua(out):
    L = []
    L.append("-- ArenaLeagues :: SpecDistribution.lua  (AUTO-GENERATED -- do not edit)")
    L.append("-- Source: Blizzard PvP leaderboard API. Per-spec top% curves for")
    L.append("-- Solo Shuffle (7) and Blitz (9), per region. Regenerate with")
    L.append("-- tools/gen_specdist.py (weekly via GitHub Actions).")
    L.append("local _, ns = ...")
    L.append("ns.SpecDist = { regions = {")
    for region in sorted(out):
        rd = out[region]
        L.append(f"  {region} = {{ season = {rd['season']}, brackets = {{")
        for bidx in (7, 9):
            L.append(f"    [{bidx}] = {{")
            for specid in sorted(rd["brackets"][bidx]):
                d = rd["brackets"][bidx][specid]
                pairs = ", ".join("{%d,%s}" % (r, fmtpct(p)) for r, p in d["dist"])
                L.append(f"      [{specid}] = {{ floor = {d['floor']}, n = {d['n']}, dist = {{ {pairs} }} }},")
            L.append("    },")
        L.append("  } },")
    L.append("} }")
    with open(OUT, "w") as f:
        f.write("\n".join(L) + "\n")

if __name__ == "__main__":
    main()
