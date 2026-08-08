-- GudaBags Expansion Detection
-- Detects WoW version and provides expansion-specific feature flags

local addonName, ns = ...

local Expansion = {}
ns:RegisterModule("Expansion", Expansion)

-- WoW Project ID constants (from Blizzard API)
-- WOW_PROJECT_MAINLINE = 1                  (Retail, Interface 110005+)
-- WOW_PROJECT_CLASSIC = 2                   (Classic Era, Interface 11508)
-- WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5   (TBC Anniversary, Interface 20506)
-- WOW_PROJECT_MISTS_CLASSIC = 19            (MoP Classic, Interface 50504)

-- Primary detection via WOW_PROJECT_ID
Expansion.IsRetail = WOW_PROJECT_ID == (WOW_PROJECT_MAINLINE or 1)
Expansion.IsClassicEra = WOW_PROJECT_ID == (WOW_PROJECT_CLASSIC or 2)
Expansion.IsTBC = WOW_PROJECT_ID == (WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5)
Expansion.IsMoP = WOW_PROJECT_ID == (WOW_PROJECT_MISTS_CLASSIC or 19)

-- Get interface version for fallback detection
local _, _, _, interfaceVersion = GetBuildInfo()
Expansion.InterfaceVersion = interfaceVersion

-- Fallback detection via interface version if project ID detection failed
if not Expansion.IsRetail and not Expansion.IsClassicEra and not Expansion.IsTBC and not Expansion.IsMoP then
    Expansion.IsRetail = interfaceVersion >= 110000
    Expansion.IsClassicEra = interfaceVersion >= 11500 and interfaceVersion < 20000
    Expansion.IsTBC = interfaceVersion >= 20500 and interfaceVersion < 30000
    Expansion.IsMoP = interfaceVersion >= 50500 and interfaceVersion < 60000
end

-- Feature availability based on expansion
Expansion.Features = {
    -- Classic Era and TBC features
    HasKeyring = Expansion.IsClassicEra or Expansion.IsTBC,
    HasQuiverBags = Expansion.IsClassicEra or Expansion.IsTBC,
    HasAmmoBags = Expansion.IsClassicEra or Expansion.IsTBC,

    -- MoP-specific features
    HasGemBags = Expansion.IsMoP,
    HasInscriptionBags = Expansion.IsMoP,

    -- Retail-specific features
    HasNativeBagSort = Expansion.IsRetail,  -- C_Container.SortBags() available
    HasReagentBank = Expansion.IsRetail,
    HasWarbandBank = Expansion.IsRetail,
    HasCurrency = Expansion.IsRetail or Expansion.IsMoP,

    -- Account-bound items (heirlooms, "Bind to Account", Warbound) arrived in
    -- WotLK 3.2, so Classic Era and TBC have none at all. Gate on this rather than
    -- on the ITEM_ACCOUNTBOUND* global strings: Blizzard ships those globals to
    -- every flavor whether or not any item can carry the binding, so their
    -- existence proves nothing.
    HasAccountBoundItems = Expansion.IsRetail or Expansion.IsMoP,
}

-- Convenience exports to namespace root
ns.IsRetail = Expansion.IsRetail
ns.IsClassicEra = Expansion.IsClassicEra
ns.IsTBC = Expansion.IsTBC
ns.IsMoP = Expansion.IsMoP
ns.ExpansionFeatures = Expansion.Features

