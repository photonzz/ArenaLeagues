-- ArenaLeagues :: Database.lua
-- Static, in-code rank definitions. This table is NOT a SavedVariable; it is the
-- regional "snapshot" that maps raw rating numbers onto League-style tiers.
-- (Player-specific persisted state lives in ArenaLeaguesSavedVars instead.)

local _, ns = ...

-- Tier color palette (hex, no leading |cff). Diamond intentionally matches the
-- cyan used throughout the addon branding.
local COLORS = {
    Bronze     = "cd7f32",
    Silver     = "c0c0c0",
    Gold       = "ffd700",
    Platinum   = "4ec9b0",
    Diamond    = "4080ff",
    Master     = "b266ff",
    Challenger = "ff4040",
}

-- Build/validate an ordered tier list from {name, min} pairs. `min` is the
-- inclusive lower rating boundary. GetRankInfo relies on these ascending by
-- min, so assert it here to catch a data-entry typo at load time.
local function tiers(list)
    for i = 2, #list do
        assert(list[i].min > list[i - 1].min,
            ("ArenaLeagues: tier '%s' min (%d) must exceed the previous tier")
                :format(tostring(list[i].name), list[i].min))
    end
    return list
end

-- Per-bracket threshold layout. Keyed by the GetPersonalRatedInfo bracket index:
--   2 = 3v3, 7 = Solo Shuffle, 9 = Rated BG Blitz.
-- Solo Shuffle / Blitz ratings inflate faster, so their top bands sit higher.
ArenaLeaguesDB = {
    colors = COLORS,

    brackets = {
        [1] = { -- 2v2
            name = "2v2",
            tiers = tiers({
                { name = "Bronze",     min = 0    },
                { name = "Silver",     min = 1000 },
                { name = "Gold",       min = 1400 },
                { name = "Platinum",   min = 1600 },
                { name = "Diamond",    min = 1800 },
                { name = "Master",     min = 2100 },
                { name = "Challenger", min = 2400 },
            }),
            distribution = {
                { 0, 100 }, { 1200, 50 }, { 1600, 25 }, { 1800, 12 },
                { 2100, 5 }, { 2400, 1 }, { 2700, 0.2 },
            },
        },

        [4] = { -- Rated BG (10v10)
            name = "10v10",
            tiers = tiers({
                { name = "Bronze",     min = 0    },
                { name = "Silver",     min = 1000 },
                { name = "Gold",       min = 1400 },
                { name = "Platinum",   min = 1600 },
                { name = "Diamond",    min = 1800 },
                { name = "Master",     min = 2100 },
                { name = "Challenger", min = 2400 },
            }),
            distribution = {
                { 0, 100 }, { 1200, 50 }, { 1600, 25 }, { 1800, 12 },
                { 2100, 5 }, { 2400, 1 }, { 2700, 0.2 },
            },
        },

        [2] = { -- 3v3
            name = "3v3",
            tiers = tiers({
                { name = "Bronze",     min = 0    },
                { name = "Silver",     min = 1000 },
                { name = "Gold",       min = 1400 },
                { name = "Platinum",   min = 1600 },
                { name = "Diamond",    min = 1800 },
                { name = "Master",     min = 2100 },
                { name = "Challenger", min = 2400 },
            }),
            -- Anchor points for the "Top X%" subtext: {rating, topPercent}.
            -- Interpolated linearly between anchors; approximate by design.
            distribution = {
                { 0, 100 }, { 1200, 50 }, { 1600, 25 }, { 1800, 12 },
                { 2100, 5 }, { 2400, 1 }, { 2700, 0.2 },
            },
        },

        [7] = { -- Solo Shuffle
            name = "Solo Shuffle",
            tiers = tiers({
                { name = "Bronze",     min = 0    },
                { name = "Silver",     min = 1100 },
                { name = "Gold",       min = 1500 },
                { name = "Platinum",   min = 1750 },
                { name = "Diamond",    min = 2000 },
                { name = "Master",     min = 2300 },
                { name = "Challenger", min = 2600 },
            }),
            distribution = {
                { 0, 100 }, { 1400, 50 }, { 1750, 25 }, { 2000, 12 },
                { 2300, 5 }, { 2600, 1 }, { 2900, 0.2 },
            },
        },

        [9] = { -- Rated BG Blitz
            name = "Blitz",
            tiers = tiers({
                { name = "Bronze",     min = 0    },
                { name = "Silver",     min = 1100 },
                { name = "Gold",       min = 1500 },
                { name = "Platinum",   min = 1750 },
                { name = "Diamond",    min = 2000 },
                { name = "Master",     min = 2300 },
                { name = "Challenger", min = 2600 },
            }),
            distribution = {
                { 0, 100 }, { 1400, 50 }, { 1750, 25 }, { 2000, 12 },
                { 2300, 5 }, { 2600, 1 }, { 2900, 0.2 },
            },
        },
    },
}

-- Width (in rating points) of the synthetic band used for the open-ended top
-- tier (Challenger), so progress / subdivision math still has a denominator.
ArenaLeaguesDB.topBandWidth = 600

ns.DB = ArenaLeaguesDB
