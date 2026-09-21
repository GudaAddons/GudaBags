-- GudaBags Expansion Detection
-- Detects WoW version and provides expansion-specific feature flags

local addonName, ns = ...

local Expansion = {}
ns:RegisterModule("Expansion", Expansion)

-- WoW Project ID constants (from Blizzard API)
-- WOW_PROJECT_MAINLINE = 1                  (Retail: TWW 110207, Midnight 120100)
-- WOW_PROJECT_CLASSIC = 2                   (Classic Era, Interface 11509)
-- WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5   (TBC Anniversary, Interface 20506)
-- WOW_PROJECT_MISTS_CLASSIC = 19            (MoP Classic, Interface 50504)
--
-- WoW: Forever has NO project ID constant. Blizzard shipped none, and files the
-- client under the `mainline` load game type (which covers "Midnight and Forever")
-- with the TOC suffix _Camelot and Interface 16001 (= 1.60.1). See below.

-- Interface version is read BEFORE the project-ID tests, because it is the only
-- signal that stays reliable on a client whose WOW_PROJECT_ID we have never seen.
local _, _, _, interfaceVersion = GetBuildInfo()

-- Every comparison below now runs unconditionally rather than only in a fallback,
-- so normalise once: a nil or string 4th return would otherwise be a load-time
-- error instead of a skipped branch.
local iface = tonumber(interfaceVersion) or 0

-- Published as the NORMALISED number, not the raw 4th return. Other modules
-- compare against this value, and a client handing back a string would make
-- those comparisons throw at load rather than take the wrong branch.
Expansion.InterfaceVersion = iface

-- WoW: Forever ("Camelot", Interface 16001 = 1.60.1) is the one client where the
-- interface version and the API surface disagree. The version number is
-- Vanilla-shaped, but the client runs the MODERN container/bank API.
--
-- Verified against the shipped 1.60.1.69893 binary, compared against Classic Era
-- 1.15.9 / TBC 2.5.6 / MoP 5.5.4 / Retail 12.1.0 as controls. On every string that
-- separates Retail from the Classic flavors, Forever matches Retail:
--   present in Retail + Forever, absent in all three Classic clients --
--     C_Bank.*, CharacterBankTab_N, NumReagentBagSlots, ERR_REAGENTBAG_*,
--     SortBags, SortBankBags, FetchNumPurchasedBankTabs, IsBoundToAccountUntilEquip
--   present in all three Classic clients, absent in Retail + Forever --
--     GetNumBankSlots, NumBankSlots
-- So Forever takes the Retail path. Classifying it by version alone would strip the
-- bank tabs and native sort off a client that has them.
--
-- The carried bag layout is Retail's too, confirmed in game 2026-09-21: main bag,
-- FOUR ordinary bags (1-4) and a reagent bag at 5 -- plus a keyring, which is the
-- only difference. The reagent-bag strings above are the feature, not leftovers --
-- reading them as leftovers is what cost Forever its reagent bag for a while. A
-- missing KeyRingButton in the exe proves nothing (FrameXML lives in CASC).
-- Constants.lua owns that layout; see DiscoverCarriedBags there.
--
-- What Forever does NOT share with Retail is its FRAME ART, which is Vanilla's.
-- That is a separate axis from the API and has its own flag, HasRetailFrameArt.
Expansion.IsForever = iface >= 16000 and iface < 20000

-- Primary detection via WOW_PROJECT_ID, corroborated by interface-version range so
-- an unrecognised project ID can never select a feature set the client lacks.
-- Forever overrides that rule deliberately: it is decided by range, because its
-- version number is the one signal that lies about what the client can do.
Expansion.IsRetail = Expansion.IsForever
    or (WOW_PROJECT_ID == (WOW_PROJECT_MAINLINE or 1) and iface >= 100000)
-- Forever ships under the `wow_classic_beta` product, so it may well report
-- WOW_PROJECT_CLASSIC. That must not drag it onto the Classic Era path.
Expansion.IsClassicEra = WOW_PROJECT_ID == (WOW_PROJECT_CLASSIC or 2) and not Expansion.IsForever
Expansion.IsTBC = WOW_PROJECT_ID == (WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5)
Expansion.IsMoP = WOW_PROJECT_ID == (WOW_PROJECT_MISTS_CLASSIC or 19)

-- Fallback detection via interface version if project ID detection failed
if not Expansion.IsRetail and not Expansion.IsClassicEra and not Expansion.IsTBC and not Expansion.IsMoP then
    Expansion.IsRetail = iface >= 100000
    Expansion.IsClassicEra = iface >= 11500 and iface < 20000
    Expansion.IsTBC = iface >= 20500 and iface < 30000
    Expansion.IsMoP = iface >= 50500 and iface < 60000
end

-- Feature availability based on expansion
--
-- Forever rides the Retail capability set (IsRetail is true there) -- no
-- quiver/ammo, every Retail flag on -- plus the keyring, which it has in game.
-- Each Retail flag is still guarded at its call site by an existence check on the
-- actual API (Constants.lua probes Enum.BagIndex.CharacterBankTab_1 and
-- AccountBankTab_1; BankFrame/Money probe C_Bank.*), so anything Forever turns out
-- not to ship degrades rather than errors. Confirm with /guda status in game.
Expansion.Features = {
    -- Classic Era and TBC features (the keyring also exists on WoW: Forever)
    HasKeyring = Expansion.IsClassicEra or Expansion.IsTBC or Expansion.IsForever,
    HasQuiverBags = Expansion.IsClassicEra or Expansion.IsTBC,
    HasAmmoBags = Expansion.IsClassicEra or Expansion.IsTBC,

    -- MoP-specific features
    HasGemBags = Expansion.IsMoP,
    HasInscriptionBags = Expansion.IsMoP,

    -- PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE with Enum.PlayerInteractionType
    -- arrived in MoP. Where it exists it authoritatively answers "is the player
    -- at this NPC right now"; where it does not, detecting an NPC window means
    -- inferring it from frame or data traffic, which can fire with no NPC
    -- involved at all. Anything that opens a window off such an inference must
    -- gate on this.
    HasInteractionManager = Expansion.IsRetail or Expansion.IsMoP,

    -- Retail-specific features
    HasNativeBagSort = Expansion.IsRetail,  -- C_Container.SortBags() available
    HasReagentBank = Expansion.IsRetail,
    HasWarbandBank = Expansion.IsRetail,
    HasCurrency = Expansion.IsRetail or Expansion.IsMoP,

    -- "Does the CLIENT'S OWN bag/bank frame art already look like modern Retail?"
    --
    -- This is about art, not API, and it is the one place IsRetail is the wrong
    -- question. GudaBags ships its own recreation of Retail's metal frame under
    -- Assets/Themes/retail, offered as the "retail" theme -- but only where the
    -- native frame is not already that, or it would be a duplicate of the
    -- "blizzard" theme (which just renders the client's own NineSlice).
    --
    -- WoW: Forever runs the modern API on VANILLA-era frame art, so it is the
    -- first client where those two answers differ. Gating the theme on IsRetail
    -- hid it there and silently remapped it away, leaving Forever players with no
    -- way to get the modern look at all. Anything cosmetic that asks "is the
    -- native UI already modern" must use this, not IsRetail.
    HasRetailFrameArt = Expansion.IsRetail and not Expansion.IsForever,

    -- "Does this client PRESENT its bank as switchable tabs?"
    --
    -- A third axis, distinct from both the API and the art, and it is the one the
    -- bank UI must ask. Retail presents a tab strip you click between, plus a
    -- separate account bank. Classic Era, TBC and MoP present one grid of slots
    -- plus a row of purchasable bag slots.
    --
    -- WoW: Forever runs the modern C_Bank API -- its bank containers really are
    -- Enum.BagIndex.CharacterBankTab_N -- but it DRESSES them as the Classic bank:
    -- one 48-slot grid for the tab you own and a "Bag Slots" lock row for the ones
    -- you have not bought. Confirmed in game 2026-09-22. So IsRetail is true while
    -- the correct presentation is Classic's, and rendering a retail tab strip there
    -- shows tabs the player has no concept of.
    --
    -- Same value as HasRetailFrameArt today, deliberately kept separate: these
    -- answer different questions and only coincide because Forever happens to be
    -- the one client that splits API from presentation. A flavor that tabs its bank
    -- behind Vanilla art, or vice versa, would need them to diverge.
    HasTabbedBank = Expansion.IsRetail and not Expansion.IsForever,

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
-- Forever is a subset of IsRetail, not a peer of it: callers that just need the
-- modern API surface should keep using IsRetail. This is only for code that has to
-- tell Forever apart from Retail specifically -- e.g. its bank tab counts, which
-- are larger than Retail's.
ns.IsForever = Expansion.IsForever
ns.ExpansionFeatures = Expansion.Features

