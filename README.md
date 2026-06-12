# ArenaLeagues

A World of Warcraft (Retail / Midnight) addon that translates your raw PvP rating
into a **League-style rank, division, and progress bar** on the rated queue panel
(`ConquestFrame`), with animated per-tier effects.

## Features
- Per-bracket rank bars (Solo Shuffle, Blitz, 2v2, 3v3, 10v10) drawn inside each row.
- Tiers Bronze → Silver → Gold → Platinum → Diamond → Master → Challenger, each
  with its own signature look (metal gloss, frost, sapphire shine, arcane/fire, …).
- **Spec-aware "Top X%"** — percentiles are computed per specialization for Solo
  Shuffle and Blitz from real ladder data (e.g. 2100 Ret ≠ 2100 Disc).
- "Unranked" state for brackets you haven't played.

## Auto-updating data
`SpecDistribution.lua` is generated from Blizzard's PvP leaderboard API and
refreshed automatically every week by a GitHub Action, then published as a new
release so your addon manager picks it up.

Regenerate locally:
```
BNET_CLIENT_ID=... BNET_CLIENT_SECRET=... python3 tools/gen_specdist.py eu
```

## Releasing
Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager)
and pushed to GitHub Releases (and CurseForge once the project ID is set in the
`.toc`). Cut a manual release with:
```
git tag -a v1.1.0 -m "v1.1.0" && git push origin v1.1.0
```

## Credits
Built by photonzz. Frame names verified against Blizzard's UI and reference addons.
