# ArenaLeagues

A World of Warcraft (Retail / Midnight) addon that translates your raw PvP rating
into a **League-style rank, division, and progress bar** on the rated queue panel
(`ConquestFrame`), with animated per-tier effects.

## Features
- Per-bracket rank bars (Solo Shuffle, Blitz, 2v2, 3v3, 10v10) drawn inside each row.
- Tiers Bronze → Silver → Gold → Platinum → Diamond → Master → Challenger, each
  with its own signature look (metal gloss, frost, sapphire shine, arcane/fire, …).
- **Spec- and region-aware "Top X%"** — percentiles are computed per
  specialization for Solo Shuffle and Blitz from real ladder data, for both **US
  and EU** (auto-detected at runtime). E.g. 2100 Ret ≠ 2100 Disc.
- "Unranked" state for brackets you haven't played.

## Auto-updating data
`SpecDistribution.lua` is generated from Blizzard's PvP leaderboard API (US + EU)
and refreshed automatically every week by a GitHub Action, then published as a
new GitHub Release so **WowUp** picks it up.

Regenerate locally:
```
BNET_CLIENT_ID=... BNET_CLIENT_SECRET=... python3 tools/gen_specdist.py eu us
```

## Installing / updating
Add the repo in **WowUp** (Get Addons → Install from URL):
`https://github.com/photonzz/ArenaLeagues`. WowUp then auto-updates from GitHub
Releases — no CurseForge needed.

## Releasing
Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager)
and published to GitHub Releases. Cut a manual release with:
```
git tag -a v1.1.0 -m "v1.1.0" && git push origin v1.1.0
```

## Credits
Built by **photonzz**.

This addon does not copy code from other addons, but its Blizzard frame names and
PvP API usage were **verified against and informed by** these excellent projects —
thanks to their authors:
- [RatedTracker](https://www.curseforge.com/wow/addons/rated-pvp-tracker) — the
  Midnight "secret value" guard pattern (`issecretvalue` / `canaccessvalue`) and
  `GetPersonalRatedInfo` bracket usage.
- [BetterBlizzFrames](https://www.curseforge.com/wow/addons/betterblizzframes) and
  [sArena](https://www.curseforge.com/wow/addons/sarena) — confirming the
  `ConquestFrame` per-row fields (`CurrentRating`, `TierIcon`, etc.).
- [BigWigs packager](https://github.com/BigWigsMods/packager) — release tooling.

Rank data © Blizzard Entertainment, via the official PvP leaderboard API.
