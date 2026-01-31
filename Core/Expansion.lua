-- GudaBags Expansion Detection
-- Detects WoW version and provides expansion-specific feature flags

local addonName, ns = ...

local Expansion = {}
ns:RegisterModule("Expansion", Expansion)

-- WoW Project ID constants (from Blizzard API)
-- WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5   (TBC Anniversary, Interface 20505)
-- WOW_PROJECT_MISTS_CLASSIC = 19            (MoP Classic, Interface 50503)

-- Primary detection via WOW_PROJECT_ID
Expansion.IsTBC = WOW_PROJECT_ID == (WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5)
Expansion.IsMoP = WOW_PROJECT_ID == (WOW_PROJECT_MISTS_CLASSIC or 19)

-- Get interface version for fallback detection
local _, _, _, interfaceVersion = GetBuildInfo()
Expansion.InterfaceVersion = interfaceVersion

-- Fallback detection via interface version if project ID detection failed
if not Expansion.IsTBC and not Expansion.IsMoP then
    Expansion.IsTBC = interfaceVersion >= 20500 and interfaceVersion < 30000
    Expansion.IsMoP = interfaceVersion >= 50500 and interfaceVersion < 60000
end

-- Feature availability based on expansion
Expansion.Features = {
    -- TBC-specific features
    HasKeyring = Expansion.IsTBC,
    HasQuiverBags = Expansion.IsTBC,
    HasAmmoBags = Expansion.IsTBC,

    -- MoP-specific features (can be expanded later)
    HasGemBags = Expansion.IsMoP,
    HasInscriptionBags = Expansion.IsMoP,
}

-- Convenience exports to namespace root
ns.IsTBC = Expansion.IsTBC
ns.IsMoP = Expansion.IsMoP
ns.ExpansionFeatures = Expansion.Features

-- Debug output
if ns.debugMode then
    ns:Debug(string.format("Expansion Detection: IsTBC=%s, IsMoP=%s, Interface=%d",
        tostring(Expansion.IsTBC), tostring(Expansion.IsMoP), interfaceVersion))
end
