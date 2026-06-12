-- luacheck config for the ArenaLeagues WoW addon (Lua 5.1 / WoW API)
std = "lua51"
max_line_length = false
self = false -- methods defined with `:` may not use `self` (they read the namespace directly)

-- The addon's own intentional globals (created on purpose, per spec).
globals = {
    "ArenaLeagues",
    "ArenaLeaguesDB",
    "ArenaLeaguesSavedVars",
    "ArenaLeagues_VisualFrame",
}

-- WoW API surface the addon reads (treated as known read-only globals).
read_globals = {
    -- core frame/UI API
    "CreateFrame", "UIParent", "hooksecurefunc",
    -- PvP data / frames
    "GetPersonalRatedInfo", "ConquestFrame", "ConquestFrame_Update",
    -- specialization
    "GetSpecialization", "GetSpecializationInfo",
    -- addon management
    "C_AddOns",
    -- Midnight restricted-value guards
    "issecretvalue", "canaccessvalue",
    -- misc
    "BackdropTemplateMixin",
}

-- Vararg `...` at file scope is the (addonName, namespace) tuple WoW passes in.
files["**/*.lua"] = {}
