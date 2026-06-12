-- ArenaLeagues :: Effects.lua
-- Per-tier "cool as hell" bar skinning: glossy fill, tier-colored glow, sweeping
-- shine, and signature elemental effects (frost, flames, light-rays, twinkles,
-- rising embers). All motion is driven by a per-bar anim
-- frame that pauses automatically whenever the panel is hidden. No taint: we
-- only create/animate our own textures.

local _, ns = ...
local AL = ns.AL

local FX = {}
AL.FX = FX

local TEX = "Interface\\AddOns\\ArenaLeagues\\Textures\\"

-- ---------------------------------------------------------------------------
-- Per-tier theme table. Bold & flashy: every tier has its own signature, with
-- Gold and Platinum as showpieces.
--   fill        = bar fill tint
--   glow/glowA  = aura color + intensity
--   gloss       = glassy sheen overlay (all tiers)
--   shine/Fast  = sweeping highlight (+ faster variant)
--   rays/raysA  = rotating light rays behind the bar
--   frost*      = icy overlay creeping from the edges
--   flame*      = flames / arcane energy licking up the fill
--   sparkle     = twinkles that pop across the bar
--   ember       = embers/motes drifting upward
--   partColor/A = particle tint + intensity
-- ---------------------------------------------------------------------------
local THEMES = {
    Bronze = {
        fill = {0.80, 0.50, 0.22},
        glow = {0.95, 0.55, 0.18}, glowA = 0.75,
        gloss = true, shine = true,
        ember = true, partColor = {1.0, 0.62, 0.22}, partA = 0.9,
    },
    Silver = {
        fill = {0.74, 0.80, 0.90},
        glow = {0.80, 0.90, 1.00}, glowA = 0.65,
        gloss = true, shine = true, shineFast = true,
        sparkle = true, partColor = {0.92, 0.97, 1.0}, partA = 0.85,
    },
    Gold = { -- showpiece
        fill = {1.00, 0.78, 0.18},
        glow = {1.00, 0.82, 0.22}, glowA = 0.9,
        gloss = true, shine = true,
        rays = true, raysA = 0.75,
        sparkle = true, partColor = {1.0, 0.92, 0.45}, partA = 1.0,
    },
    Platinum = { -- showpiece
        fill = {0.42, 0.90, 1.00},
        glow = {0.50, 0.95, 1.00}, glowA = 0.85,
        gloss = true,
        frost = true, frostColor = {0.82, 0.97, 1.0}, frostA = 0.9,
        sparkle = true, partColor = {0.88, 0.99, 1.0}, partA = 0.9,
    },
    Diamond = { -- brilliant sapphire blue (kept clearly apart from Platinum's cyan)
        fill = {0.22, 0.48, 1.00},
        glow = {0.28, 0.55, 1.00}, glowA = 0.95,
        gloss = true, shine = true, shineFast = true,
        rays = true, raysA = 0.65,
        sparkle = true, partColor = {0.62, 0.80, 1.0}, partA = 1.0,
    },
    Master = {
        fill = {0.60, 0.36, 0.95},
        glow = {0.70, 0.40, 1.00}, glowA = 0.95,
        gloss = true,
        flame = true, flameColor = {0.78, 0.48, 1.0}, flameA = 0.95,
        sparkle = true, partColor = {0.88, 0.6, 1.0}, partA = 0.95,
    },
    Challenger = {
        fill = {1.00, 0.32, 0.12},
        glow = {1.00, 0.30, 0.12}, glowA = 1.0,
        gloss = true,
        flame = true, flameColor = {1.0, 0.68, 0.22}, flameA = 1.0,
        ember = true, partColor = {1.0, 0.55, 0.15}, partA = 1.0,
    },
}
FX.THEMES = THEMES

-- ---------------------------------------------------------------------------
-- Animation driver. `self` is the per-bar anim frame; self.bar is the bar.
-- ---------------------------------------------------------------------------
local function animOnUpdate(self, elapsed)
    local bar = self.bar
    local fx, th = bar.fx, bar.theme
    if not (fx and th) then return end
    local t = (self.t or 0) + elapsed
    self.t = t

    local w = bar:GetWidth() or 1
    local h = bar:GetHeight() or 1

    if fx.glow:IsShown() then
        fx.glow:SetAlpha((th.glowA or 0.7) * (0.62 + 0.38 * math.sin(t * 2.2)))
    end
    if fx.rays:IsShown() then
        fx.rays:SetRotation(t * 0.55)
        fx.rays:SetAlpha((th.raysA or 0.6) * (0.55 + 0.45 * math.sin(t * 1.7)))
    end
    if fx.flame:IsShown() then
        local u = (t * 0.55) % 1
        fx.flame:SetTexCoord(u, u + 1, 0, 1)
        fx.flame:SetAlpha((th.flameA or 0.9) * (0.82 + 0.18 * math.sin(t * 9)))
    end
    if fx.frost:IsShown() then
        local u = (t * 0.05) % 1
        fx.frost:SetTexCoord(u, u + 1, 0, 1)
        fx.frost:SetAlpha((th.frostA or 0.85) * (0.7 + 0.3 * math.sin(t * 1.5)))
    end
    if fx.shine:IsShown() then
        -- Sweeping highlight that travels left->right. Kept slow on purpose.
        local u = (t * (th.shineFast and 0.18 or 0.10)) % 1
        fx.shine:SetTexCoord(-u, 1 - u, 0, 1)
    end
    if fx.partsActive then
        local rising = th.ember
        -- Twinkles read as "flying too fast" at full rate; calm them down.
        -- Rising embers keep their normal pace.
        local spd = rising and 1.0 or 0.25
        for _, p in ipairs(fx.parts) do
            local ph = (t * spd / p.dur + p.off) % 1
            local px = p.x * w
            if rising then
                local y = -h * 0.42 + ph * h * 0.95
                local a = math.sin(ph * math.pi)
                local s = 5 + 5 * ph
                p.tex:ClearAllPoints()
                p.tex:SetPoint("CENTER", bar, "LEFT", px, y)
                p.tex:SetSize(s, s)
                p.tex:SetAlpha(a * (th.partA or 0.9))
            else
                local a = math.sin(ph * math.pi); a = a * a
                local y = (p.y - 0.5) * h * 0.6
                local s = 4 + 11 * a
                p.tex:ClearAllPoints()
                p.tex:SetPoint("CENTER", bar, "LEFT", px, y)
                p.tex:SetSize(s, s)
                p.tex:SetAlpha(a * (th.partA or 0.9))
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Build all effect layers on a bar (once).
-- ---------------------------------------------------------------------------
-- `wrap` = true sets REPEAT wrap mode so SetTexCoord beyond [0,1] tiles instead
-- of clamping (required for the scrolling flame/frost/shine; needs POT texture).
local function makeTex(bar, layer, sub, blend, file, wrap)
    local t = bar:CreateTexture(nil, layer, nil, sub)
    if wrap then
        t:SetTexture(TEX .. file, "REPEAT", "REPEAT")
    else
        t:SetTexture(TEX .. file)
    end
    if blend then t:SetBlendMode(blend) end
    t:Hide()
    return t
end

function FX:Build(bar)
    if bar.fx then return end
    local fx = {}

    -- Aura glow, bleeding slightly outside the bar.
    fx.glow = makeTex(bar, "BACKGROUND", -7, "ADD", "glow.tga")
    fx.glow:ClearAllPoints()
    fx.glow:SetPoint("TOPLEFT", bar, "TOPLEFT", -12, 12)
    fx.glow:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 12, -12)

    -- Rotating light rays, centered behind the bar.
    fx.rays = makeTex(bar, "BACKGROUND", -6, "ADD", "rays.tga")
    fx.rays:ClearAllPoints()
    fx.rays:SetPoint("CENTER", bar, "CENTER", 0, 0)

    -- Elemental fill overlays (REPEAT wrap: they scroll via SetTexCoord).
    fx.flame = makeTex(bar, "ARTWORK", 1, "ADD", "flame.tga", true)
    fx.flame:SetAllPoints(bar)
    fx.frost = makeTex(bar, "ARTWORK", 2, "ADD", "frost.tga", true)
    fx.frost:SetAllPoints(bar)

    -- Glassy sheen.
    fx.gloss = makeTex(bar, "ARTWORK", 3, "BLEND", "gloss.tga")
    fx.gloss:SetAllPoints(bar)

    -- Sweeping shine (REPEAT wrap: scrolls).
    fx.shine = makeTex(bar, "OVERLAY", 0, "ADD", "shine.tga", true)
    fx.shine:SetAllPoints(bar)

    -- Particle pool (twinkles / embers).
    fx.parts = {}
    local xs = {0.18, 0.36, 0.54, 0.72, 0.88}
    local ys = {0.35, 0.62, 0.30, 0.68, 0.5}
    for i = 1, 5 do
        local p = { x = xs[i], y = ys[i], off = (i * 0.21) % 1, dur = 0.9 + i * 0.13 }
        p.tex = makeTex(bar, "OVERLAY", 2, "ADD", "sparkle.tga")
        p.tex:SetSize(10, 10)
        fx.parts[i] = p
    end

    bar.fx = fx

    -- Dedicated animation frame (pauses when the bar/panel is hidden).
    local anim = CreateFrame("Frame", nil, bar)
    anim.bar = bar
    anim.t = 0
    anim:SetScript("OnUpdate", animOnUpdate)
    anim:Hide()
    bar.anim = anim
end

-- ---------------------------------------------------------------------------
-- Apply a tier theme: color the fill, show the matching effects, start motion.
-- ---------------------------------------------------------------------------
local function setColor(tex, c, a)
    if c then tex:SetVertexColor(c[1], c[2], c[3], a or 1) end
end

function FX:Hide(bar)
    local fx = bar.fx
    if not fx then return end
    fx.glow:Hide(); fx.rays:Hide(); fx.flame:Hide(); fx.frost:Hide()
    fx.gloss:Hide(); fx.shine:Hide()
    fx.partsActive = false
    for _, p in ipairs(fx.parts) do p.tex:Hide() end
    if bar.anim then bar.anim:Hide() end
end

function FX:ApplyTheme(bar, tierName)
    if not bar.fx then return end
    local th = THEMES[tierName]
    bar.theme = th
    self:Hide(bar)
    if not th then return end
    local fx = bar.fx

    -- Richer fill tint + dark matching backdrop.
    if th.fill then
        bar:SetStatusBarColor(th.fill[1], th.fill[2], th.fill[3], 0.95)
        if bar.bg then bar.bg:SetVertexColor(th.fill[1] * 0.18, th.fill[2] * 0.18, th.fill[3] * 0.18, 0.7) end
    end

    setColor(fx.glow, th.glow, 1); fx.glow:Show()
    fx.gloss:Show()

    if th.shine then fx.shine:Show() end
    if th.rays then setColor(fx.rays, th.glow, 1); fx.rays:Show() end
    if th.flame then setColor(fx.flame, th.flameColor or {1, 1, 1}, 1); fx.flame:Show() end
    if th.frost then setColor(fx.frost, th.frostColor or {1, 1, 1}, 1); fx.frost:Show() end

    if th.sparkle or th.ember then
        fx.partsActive = true
        for _, p in ipairs(fx.parts) do
            setColor(p.tex, th.partColor or {1, 1, 1}, 1)
            p.tex:Show()
        end
    end

    bar.anim:Show()
end

-- Muted, effect-free state for unplayed brackets.
function FX:SetUnranked(bar)
    bar.theme = nil
    self:Hide(bar)
end
