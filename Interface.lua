-- ArenaLeagues :: Interface.lua
-- Blizzard PvP UI hooking + custom rank/division/progress rendering.
--
-- The live rated panel is ConquestFrame (Blizzard_PVPUI). It shows a vertical
-- list of bracket ROWS, each a button: .RatedSoloShuffle, .RatedBGBlitz,
-- .Arena2v2, .Arena3v3, .RatedBG (template PVPRatedActivityButtonTemplate).
-- Verified row layout (Blizzard XML): bracket NAME on the far left, .TierIcon /
-- .Tier in the center, .CurrentRating just right of the icon, the weekly
-- conquest .Reward on the far right. We render ONE progress bar per row, sitting
-- between the name and the reward (so both stay visible), with the rank/division
-- centered on the bar. ConquestFrame_Update is the refresh hook.

local addonName, ns = ...
local AL = ns.AL

local UI = { bars = {} }
ns.UI = UI

-- ---------------------------------------------------------------------------
-- Saved variables defaults
-- ---------------------------------------------------------------------------
local function InitSavedVars()
    ArenaLeaguesSavedVars = ArenaLeaguesSavedVars or {}
    local sv = ArenaLeaguesSavedVars
    if sv.hideBlizzardRating == nil then sv.hideBlizzardRating = true end
end

-- ---------------------------------------------------------------------------
-- Hide Blizzard's raw rating text + tier insignia on a bracket button.
-- Field names verified on interface 120005 against Blizzard's
-- PVPRatedActivityButtonTemplate and the BetterBlizzFrames / sArena addons:
--   * the rating font string is button.CurrentRating
--   * the tier art is button.TierIcon (texture) and button.Tier (frame)
-- ---------------------------------------------------------------------------
local RATING_FIELDS   = { "CurrentRating" }
local INSIGNIA_FIELDS = { "TierIcon", "Tier" }

local function softHide(obj)
    if obj and obj.SetAlpha then pcall(obj.SetAlpha, obj, 0) end
end

function UI:HideBlizzardRating(button)
    if not button then return end
    if not (ArenaLeaguesSavedVars and ArenaLeaguesSavedVars.hideBlizzardRating) then return end
    for _, f in ipairs(RATING_FIELDS)   do softHide(button[f]) end
    for _, f in ipairs(INSIGNIA_FIELDS) do softHide(button[f]) end
end

-- ---------------------------------------------------------------------------
-- Smooth lerp toward bar.targetValue. Self-disables once settled so we are not
-- running an OnUpdate on every bar, every frame, forever (it is re-armed by
-- RefreshButton whenever a new target is set).
-- ---------------------------------------------------------------------------
local function barOnUpdate(self, elapsed)
    local cur  = self:GetValue()
    local diff = (self.targetValue or 0) - cur
    if math.abs(diff) < 0.1 then
        self:SetValue(self.targetValue or 0)
        self:SetScript("OnUpdate", nil) -- settled: stop ticking
        return
    end
    self:SetValue(cur + diff * math.min(elapsed * 8, 1))
end

-- ---------------------------------------------------------------------------
-- Create (once) the in-row bar for a given bracket button.
-- ---------------------------------------------------------------------------
function UI:EnsureBar(button)
    if not button then return nil end
    if self.bars[button] then return self.bars[button] end

    local bar = CreateFrame("StatusBar", nil, button)

    -- Anchor between the bracket name (left) and the weekly reward (right),
    -- resolution-independently, by pinning to Blizzard's own child regions.
    bar:SetPoint("TOP", button, "TOP", 0, -3)
    bar:SetPoint("BOTTOM", button, "BOTTOM", 0, 3)

    -- Start the bar just past the bracket-name block (name sits at the far left
    -- of the ~365-wide row), giving a wide bar across the empty middle up to the
    -- reward. Fixed offset in the row's coordinate space, so it is scale-stable.
    bar:SetPoint("LEFT", button, "LEFT", 112, 0)

    if button.Reward then
        bar:SetPoint("RIGHT", button.Reward, "LEFT", -8, 0)
    else
        bar:SetPoint("RIGHT", button, "RIGHT", -12, 0)
    end

    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    -- Draw above the row's own art and rating text.
    bar:SetFrameLevel((button:GetFrameLevel() or 0) + 10)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.6)
    bar.bg = bg

    -- Thin 1px border (a chunky tooltip border looks wrong on a slim bar).
    local function makeEdge()
        local e = bar:CreateTexture(nil, "OVERLAY")
        e:SetTexture("Interface\\Buttons\\WHITE8X8")
        e:SetVertexColor(0, 0, 0, 0.9)
        return e
    end
    local eT, eB, eL, eR = makeEdge(), makeEdge(), makeEdge(), makeEdge()
    eT:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -1, 0);    eT:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 1, 0);    eT:SetHeight(1)
    eB:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -1, 0);    eB:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 1, 0);    eB:SetHeight(1)
    eL:SetPoint("TOPRIGHT", bar, "TOPLEFT", 0, 1);       eL:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", 0, -1); eL:SetWidth(1)
    eR:SetPoint("TOPLEFT", bar, "TOPRIGHT", 0, 1);       eR:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", 0, -1); eR:SetWidth(1)

    -- Rank + division text, centered ON the bar. White + black outline so it
    -- stays legible on ANY tier fill color (the bar fill already carries the
    -- tier color, so tinting the text to match would kill contrast).
    local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER", bar, "CENTER", 0, 7)
    do
        local fp, fs = label:GetFont()
        label:SetFont(fp, fs, "OUTLINE")
    end
    label:SetTextColor(1, 1, 1)
    label:SetShadowOffset(1, -1)
    label:SetShadowColor(0, 0, 0, 1)
    bar.label = label

    -- "Top X%" stacked just BELOW the rank (the bar is tall enough), so the two
    -- never collide regardless of how narrow the bar gets.
    local meta = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    meta:SetPoint("CENTER", bar, "CENTER", 0, -8)
    do
        local fp, fs = meta:GetFont()
        meta:SetFont(fp, fs, "OUTLINE")
    end
    meta:SetShadowOffset(1, -1)
    meta:SetShadowColor(0, 0, 0, 1)
    bar.meta = meta

    -- Keep the rank/percentile text above all the effect layers.
    label:SetDrawLayer("OVERLAY", 7)
    meta:SetDrawLayer("OVERLAY", 7)

    -- Build the "cool as hell" effect layers (frost/flames/glow/sparkle/etc).
    if AL.FX then AL.FX:Build(bar) end

    bar.targetValue = 0
    self.bars[button] = bar
    return bar
end

-- ---------------------------------------------------------------------------
-- Update a single row's bar from current rating.
-- ---------------------------------------------------------------------------
function UI:RefreshButton(button, bracketIndex)
    local bar = self:EnsureBar(button)
    if not bar then return end

    local rating = AL:GetRating(bracketIndex)

    -- Unranked: no games / 0 rating. Show a muted "Unranked" state rather than a
    -- misleading "Bronze III" (rating 0 maps to the bottom tier otherwise).
    if not rating or rating <= 0 then
        bar.label:SetText("Unranked")
        bar:SetStatusBarColor(0.4, 0.4, 0.4, 0.55)
        bar.bg:SetVertexColor(0.08, 0.08, 0.08, 0.6)
        bar.meta:SetText("")
        bar.targetValue = 0
        bar:SetScript("OnUpdate", barOnUpdate)
        if AL.FX then AL.FX:SetUnranked(bar) end
        self:HideBlizzardRating(button)
        bar:Show()
        return
    end

    local info = AL:GetRankInfo(bracketIndex, rating, AL:CurrentSpecID())
    if not info then bar:Hide() return end

    bar.label:SetText(info.tier .. " " .. info.subdivision)

    -- Base tier color (fallback if effects are unavailable); the themed skin
    -- below overrides the fill with a richer tint + signature effects.
    local r, g, b = AL:TierRGB(info.tier)
    bar:SetStatusBarColor(r, g, b, 0.9)
    bar.bg:SetVertexColor(r * 0.25, g * 0.25, b * 0.25, 0.6)
    if AL.FX then AL.FX:ApplyTheme(bar, info.tier) end

    bar.targetValue = info.progress
    bar:SetScript("OnUpdate", barOnUpdate) -- (re)arm the lerp

    if info.percentile then
        bar.meta:SetFormattedText("Top %.0f%%", info.percentile)
    else
        bar.meta:SetText("")
    end

    self:HideBlizzardRating(button)
    bar:Show()
end

-- ---------------------------------------------------------------------------
-- Refresh every handled row.
-- ---------------------------------------------------------------------------
function UI:RefreshAll()
    local cf = _G.ConquestFrame
    if not cf then return end
    for _, row in ipairs(AL.HANDLED) do
        local button = cf[row.field]
        if button then
            self:RefreshButton(button, row.index)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Wire up hooks once Blizzard_PVPUI is present.
-- ---------------------------------------------------------------------------
function UI:Hook()
    if self.hooked then return end
    local cf = _G.ConquestFrame
    if not cf then return end

    -- Re-translate whenever Blizzard rebuilds the conquest panel. Taint-safe.
    if type(_G.ConquestFrame_Update) == "function" then
        hooksecurefunc("ConquestFrame_Update", function() UI:RefreshAll() end)
    end
    cf:HookScript("OnShow", function() UI:RefreshAll() end)

    self.hooked = true
    self:RefreshAll()
end

-- ---------------------------------------------------------------------------
-- Event driver
-- ---------------------------------------------------------------------------
local driver = CreateFrame("Frame")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("PVP_RATED_STATS_UPDATE")
driver:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            InitSavedVars()
        elseif arg1 == "Blizzard_PVPUI" then
            UI:Hook()
        end
    elseif event == "PVP_RATED_STATS_UPDATE" then
        UI:RefreshAll()
    end
end)

-- If Blizzard_PVPUI was already loaded before us, hook immediately.
if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_PVPUI") then
    InitSavedVars()
    UI:Hook()
end
