-- ArenaLeagues :: Core.lua
-- Core namespace + the rating-to-rank/division/percentile parser.

local _, ns = ...

ArenaLeagues = ArenaLeagues or {}
local AL = ArenaLeagues
ns.AL = AL

local DB = ns.DB -- ArenaLeaguesDB

-- Midnight (12.0) can hand back "secret values" from restricted APIs: values
-- that report type()=="number" but raise a forbidden-access error the moment you
-- do arithmetic/comparison on them. These globals (with pre-12.0 fallbacks) let
-- us reject such values before they reach the rating math. Mirrors RatedTracker.
local issecretvalue  = issecretvalue  or function() return false end
local canaccessvalue = canaccessvalue or function() return true  end

-- Subdivision labels, lowest -> highest. Index 1 (III) is the bottom third of a
-- tier band; index 3 (I) is the top third and the highest sub-rank.
local SUBDIVISIONS = { "III", "II", "I" }

-- Wrap text in a tier color escape sequence: |cffRRGGBB...|r
function AL:Colorize(text, hex)
    return ("|cff%s%s|r"):format(hex or "ffffff", tostring(text))
end

-- Return the {r,g,b} (0-1) vertex color for a tier name, for textures/bars.
-- Per-channel fallbacks keep it total: a malformed palette entry degrades to
-- white instead of throwing a nil-arithmetic error during a panel refresh.
function AL:TierRGB(tierName)
    local hex = DB.colors[tierName]
    if type(hex) ~= "string" or #hex < 6 then hex = "ffffff" end
    local r = (tonumber(hex:sub(1, 2), 16) or 255) / 255
    local g = (tonumber(hex:sub(3, 4), 16) or 255) / 255
    local b = (tonumber(hex:sub(5, 6), 16) or 255) / 255
    return r, g, b
end

-- Linear interpolation helper used by the percentile estimate.
local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Interpolate a top% from a sorted {rating, pct} anchor list (rating ascending,
-- pct descending). Clamps outside the range.
local function interp(dist, rating)
    if rating <= dist[1][1] then return dist[1][2] end
    if rating >= dist[#dist][1] then return dist[#dist][2] end
    for i = 1, #dist - 1 do
        local lo, hi = dist[i], dist[i + 1]
        if rating >= lo[1] and rating <= hi[1] then
            local t = (rating - lo[1]) / (hi[1] - lo[1])
            return lerp(lo[2], hi[2], t)
        end
    end
    return dist[#dist][2]
end

-- Estimate "Top X%" for a rating. Prefers REAL per-spec ladder data (Solo
-- Shuffle / Blitz, from Blizzard's API via SpecDistribution.lua) when we have it
-- and the rating is within the laddered range; otherwise falls back to the
-- generic per-bracket curve. Returns a number (percent) or nil.
function AL:EstimatePercentile(bracketIndex, rating, specID)
    if specID and ns.SpecDist and ns.SpecDist.regions then
        local rk = self:CurrentRegion()
        local rd = rk and ns.SpecDist.regions[rk]
        local b = rd and rd.brackets and rd.brackets[bracketIndex]
        local sd = b and b[specID]
        if sd and sd.dist and rating >= sd.floor then
            return interp(sd.dist, rating)
        end
    end

    local bracket = DB.brackets[bracketIndex]
    if not bracket or not bracket.distribution then return nil end
    return interp(bracket.distribution, rating)
end

-- Map the client's region to our data key (we ship US + EU; others fall back to
-- the generic curve).
local REGION_KEY = { [1] = "US", [3] = "EU" }
function AL:CurrentRegion()
    if type(GetCurrentRegion) ~= "function" then return nil end
    return REGION_KEY[GetCurrentRegion()]
end

-- The player's current specialization id (used to pick the per-spec curve).
function AL:CurrentSpecID()
    if type(GetSpecialization) ~= "function" then return nil end
    local i = GetSpecialization()
    if not i then return nil end
    return (GetSpecializationInfo(i))
end

-- The core parser.
-- Input:  bracketIndex (2/7/9), raw rating number.
-- Output: a table describing the rank, or nil if the bracket is unknown.
--   .tier        -> tier name string ("Diamond")
--   .display     -> color-wrapped tier name ("|cff00ffffDiamond|r")
--   .hex         -> tier hex color ("00ffff")
--   .subdivision -> "III" | "II" | "I"   (I is highest)
--   .subIndex    -> 1..3
--   .progress    -> float 0-100, progress toward the NEXT tier boundary
--   .nextBoundary-> rating value of the next tier (nil at top tier)
--   .percentile  -> estimated "top X%" number (may be nil)
--   .rating      -> echoed input rating
function AL:GetRankInfo(bracketIndex, rating, specID)
    local bracket = DB.brackets[bracketIndex]
    if not bracket then return nil end

    rating = tonumber(rating) or 0
    if rating < 0 then rating = 0 end

    local list = bracket.tiers

    -- Find the current tier: highest tier whose min <= rating.
    local idx = 1
    for i = 1, #list do
        if rating >= list[i].min then idx = i else break end
    end

    local cur  = list[idx]
    local nxt  = list[idx + 1] -- nil if at top tier

    -- Band boundaries used for subdivision + progress math.
    local bandLo = cur.min
    local bandHi
    if nxt then
        bandHi = nxt.min
    else
        -- Open-ended top tier: synthesize a band so the math has a denominator.
        bandHi = cur.min + (DB.topBandWidth or 600)
    end

    local span = bandHi - bandLo
    if span <= 0 then span = 1 end

    -- Fraction through the current tier band (clamped 0..1).
    local frac = (rating - bandLo) / span
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end

    -- Subdivision: split the band into thirds. Bottom third -> III, top -> I.
    local subIndex = math.floor(frac * 3) + 1
    if subIndex > 3 then subIndex = 3 end

    local info = {
        rating       = rating,
        tier         = cur.name,
        hex          = DB.colors[cur.name] or "ffffff",
        display      = self:Colorize(cur.name, DB.colors[cur.name]),
        subIndex     = subIndex,
        subdivision  = SUBDIVISIONS[subIndex],
        progress     = frac * 100,
        nextBoundary = nxt and nxt.min or nil,
        percentile   = self:EstimatePercentile(bracketIndex, rating, specID),
    }
    return info
end

-- The rated rows we translate: ConquestFrame field name -> bracket index.
-- Order matches the on-screen list. Index meanings:
--   1 = 2v2, 2 = 3v3, 4 = Rated BG (10v10), 7 = Solo Shuffle, 9 = Blitz.
AL.HANDLED = {
    { field = "RatedSoloShuffle", index = 7 },
    { field = "RatedBGBlitz",     index = 9 },
    { field = "Arena2v2",         index = 1 },
    { field = "Arena3v3",         index = 2 },
    { field = "RatedBG",          index = 4 },
}

-- Read the player's current rating for a bracket index. Returns a plain,
-- accessible number (0 on any failure). The secret/access checks MUST happen
-- before tonumber/arithmetic, otherwise a secret value flows downstream into
-- GetRankInfo and throws there, outside any pcall.
function AL:GetRating(bracketIndex)
    if type(GetPersonalRatedInfo) ~= "function" then return 0 end
    local ok, rating = pcall(GetPersonalRatedInfo, bracketIndex)
    if not ok or rating == nil then return 0 end
    if issecretvalue(rating) then return 0 end
    if not canaccessvalue(rating) then return 0 end
    return tonumber(rating) or 0
end
