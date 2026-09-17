-- Harness: runs GudaBags' real client-detection code (Core/Expansion.lua) against
-- every flavor the TOC claims, plus WoW: Forever, plus the cases where Blizzard
-- hands us something we have never seen.
--
-- Unlike tests/locale_matrix.lua -- which stubs the Expansion module wholesale
-- because it probes WoW build APIs -- this harness stubs only GetBuildInfo and the
-- WOW_PROJECT_* globals, then loads the real file. The detection logic is the thing
-- under test.
--
-- Two invariants:
--
-- 1. No client may be classified Retail on the strength of WOW_PROJECT_ID alone --
--    the interface version has to agree. Forever is the one documented exception
--    and is matched by range instead.
--
-- 2. Forever lands on Retail whatever it reports. Its interface version (16001 =
--    1.60.1) looks Vanilla, but the 1.60.1.69893 client binary carries the modern
--    API -- C_Bank.*, CharacterBankTab_N, NumReagentBagSlots, SortBags,
--    IsBoundToAccountUntilEquip -- and lacks the Classic-only GetNumBankSlots and
--    KeyRingButton. Classifying it Vanilla would strip the reagent bag, the bank
--    tabs and native sort off a client that has all three.

local ADDON = os.getenv("GUDABAGS_PATH")

-------------------------------------------------
-- WoW API stubs (Core/Init.lua only needs this one)
-------------------------------------------------
C_AddOns = {GetAddOnMetadata = function() return "2.2.2" end}

-------------------------------------------------
-- Loader: fresh ns per scenario, real Expansion.lua
-------------------------------------------------

-- Every WOW_PROJECT_* global is reset on each run: they are true globals, so a
-- leftover value from the previous scenario would silently satisfy the next one.
local function Detect(iface, projectID, constantsDefined)
    WOW_PROJECT_MAINLINE = constantsDefined and 1 or nil
    WOW_PROJECT_CLASSIC = constantsDefined and 2 or nil
    WOW_PROJECT_BURNING_CRUSADE_CLASSIC = constantsDefined and 5 or nil
    WOW_PROJECT_WRATH_CLASSIC = constantsDefined and 11 or nil
    WOW_PROJECT_CATACLYSM_CLASSIC = constantsDefined and 14 or nil
    WOW_PROJECT_MISTS_CLASSIC = constantsDefined and 19 or nil
    WOW_PROJECT_ID = projectID

    GetBuildInfo = function()
        return "1.0.0", "00000", "Jan 1 2026", iface
    end

    local ns = {}
    assert(loadfile(ADDON .. "/Core/Init.lua"))("GudaBags", ns)
    assert(loadfile(ADDON .. "/Core/Expansion.lua"))("GudaBags", ns)
    return ns:GetModule("Expansion"), ns
end

local failures = 0

local function Check(label, got, want)
    if got ~= want then
        failures = failures + 1
        print("  <<< FAIL " .. label .. ": got " .. tostring(got) ..
              ", want " .. tostring(want))
    end
end

local function FlagString(E)
    local on = {}
    for _, name in ipairs({"IsRetail", "IsClassicEra", "IsForever", "IsTBC", "IsMoP"}) do
        if E[name] then on[#on + 1] = name end
    end
    if #on == 0 then return "(none)" end
    return table.concat(on, " + ")
end

-------------------------------------------------
-- 1. Regression guard: the five flavors the TOC already shipped
--
-- These expectations are the values the PREVIOUS detection code produced. They are
-- written out literally rather than computed, so that hardening detection for
-- Forever cannot quietly change what an existing user gets.
-------------------------------------------------
print("Shipped flavors (must be unchanged by Forever support):")

local SHIPPED = {
    {name = "Retail / Midnight",   iface = 120100, pid = 1,
     IsRetail = true,  IsClassicEra = false, IsTBC = false, IsMoP = false},
    {name = "Retail / TWW",        iface = 110207, pid = 1,
     IsRetail = true,  IsClassicEra = false, IsTBC = false, IsMoP = false},
    {name = "MoP Classic",         iface = 50504,  pid = 19,
     IsRetail = false, IsClassicEra = false, IsTBC = false, IsMoP = true},
    {name = "TBC Anniversary",     iface = 20506,  pid = 5,
     IsRetail = false, IsClassicEra = false, IsTBC = true,  IsMoP = false},
    {name = "Classic Era",         iface = 11509,  pid = 2,
     IsRetail = false, IsClassicEra = true,  IsTBC = false, IsMoP = false},
}

local SHIPPED_FEATURES = {
    ["Retail / Midnight"] = {HasKeyring = false, HasQuiverBags = false, HasAmmoBags = false,
        HasGemBags = false, HasInscriptionBags = false, HasInteractionManager = true,
        HasNativeBagSort = true, HasReagentBank = true, HasWarbandBank = true,
        HasCurrency = true, HasAccountBoundItems = true},
    ["Retail / TWW"] = {HasKeyring = false, HasQuiverBags = false, HasAmmoBags = false,
        HasGemBags = false, HasInscriptionBags = false, HasInteractionManager = true,
        HasNativeBagSort = true, HasReagentBank = true, HasWarbandBank = true,
        HasCurrency = true, HasAccountBoundItems = true},
    ["MoP Classic"] = {HasKeyring = false, HasQuiverBags = false, HasAmmoBags = false,
        HasGemBags = true, HasInscriptionBags = true, HasInteractionManager = true,
        HasNativeBagSort = false, HasReagentBank = false, HasWarbandBank = false,
        HasCurrency = true, HasAccountBoundItems = true},
    ["TBC Anniversary"] = {HasKeyring = true, HasQuiverBags = true, HasAmmoBags = true,
        HasGemBags = false, HasInscriptionBags = false, HasInteractionManager = false,
        HasNativeBagSort = false, HasReagentBank = false, HasWarbandBank = false,
        HasCurrency = false, HasAccountBoundItems = false},
    ["Classic Era"] = {HasKeyring = true, HasQuiverBags = true, HasAmmoBags = true,
        HasGemBags = false, HasInscriptionBags = false, HasInteractionManager = false,
        HasNativeBagSort = false, HasReagentBank = false, HasWarbandBank = false,
        HasCurrency = false, HasAccountBoundItems = false},
}

for _, case in ipairs(SHIPPED) do
    local E = Detect(case.iface, case.pid, true)
    print(string.format("  %-20s iface=%-7d pid=%-3s -> %s",
          case.name, case.iface, tostring(case.pid), FlagString(E)))

    Check(case.name .. " IsRetail", E.IsRetail, case.IsRetail)
    Check(case.name .. " IsClassicEra", E.IsClassicEra, case.IsClassicEra)
    Check(case.name .. " IsTBC", E.IsTBC, case.IsTBC)
    Check(case.name .. " IsMoP", E.IsMoP, case.IsMoP)
    -- No shipped flavor may be mistaken for Forever
    Check(case.name .. " IsForever", E.IsForever, false)
    Check(case.name .. " InterfaceVersion", E.InterfaceVersion, case.iface)

    for flag, want in pairs(SHIPPED_FEATURES[case.name]) do
        Check(case.name .. " Features." .. flag, E.Features[flag], want)
    end
end

-------------------------------------------------
-- 2. WoW: Forever -- all four things the client might report
--
-- Blizzard published no WOW_PROJECT_* constant for Forever, so the project ID is
-- genuinely unknown. Every possibility must land on the Vanilla API surface.
-------------------------------------------------
print("")
print("WoW: Forever (Interface 16001) -- every possible WOW_PROJECT_ID:")

local FOREVER_CASES = {
    {label = "reports WOW_PROJECT_MAINLINE (the dangerous one)", pid = 1,  consts = true},
    {label = "reports WOW_PROJECT_CLASSIC",                      pid = 2,  consts = true},
    {label = "reports a new, unknown project ID",                pid = 27, consts = true},
    {label = "reports nil, no WOW_PROJECT_* constants at all",   pid = nil, consts = false},
}

for _, case in ipairs(FOREVER_CASES) do
    local E = Detect(16001, case.pid, case.consts)
    print(string.format("  %-46s -> %s", case.label, FlagString(E)))

    Check("Forever(" .. case.label .. ") IsRetail", E.IsRetail, true)
    Check("Forever(" .. case.label .. ") IsForever", E.IsForever, true)
    Check("Forever(" .. case.label .. ") IsClassicEra", E.IsClassicEra, false)
    Check("Forever(" .. case.label .. ") IsTBC", E.IsTBC, false)
    Check("Forever(" .. case.label .. ") IsMoP", E.IsMoP, false)
end

-- Forever's capability set: Vanilla-shaped, no Retail features.
print("")
print("WoW: Forever capability set:")
local F = Detect(16001, 1, true)
-- Mirrors Retail. Each value is corroborated by a string probe of the 1.60.1.69893
-- binary against Classic Era / TBC / MoP / Retail controls -- notably HasKeyring,
-- false because Forever has no KeyRingButton where all three Classic clients do.
local FOREVER_FEATURES = {
    HasKeyring = false, HasQuiverBags = false, HasAmmoBags = false,
    HasGemBags = false, HasInscriptionBags = false, HasInteractionManager = true,
    HasNativeBagSort = true, HasReagentBank = true, HasWarbandBank = true,
    HasCurrency = true, HasAccountBoundItems = true,
}
for _, flag in ipairs({"HasKeyring", "HasQuiverBags", "HasAmmoBags", "HasGemBags",
                       "HasInscriptionBags", "HasInteractionManager", "HasNativeBagSort",
                       "HasReagentBank", "HasWarbandBank", "HasCurrency",
                       "HasAccountBoundItems"}) do
    print(string.format("  %-24s %s", flag, tostring(F.Features[flag])))
    Check("Forever Features." .. flag, F.Features[flag], FOREVER_FEATURES[flag])
end

-- Later Forever patches must stay inside the range.
print("")
print("Forever version range (1.60 through 1.99):")
for _, iface in ipairs({16000, 16001, 16100, 17000, 19999}) do
    local E = Detect(iface, 1, true)
    print(string.format("  iface=%-6d -> %s", iface, FlagString(E)))
    Check("iface " .. iface .. " IsForever", E.IsForever, true)
    Check("iface " .. iface .. " IsRetail", E.IsRetail, true)
end

-- ...and the boundaries must NOT be swallowed by it.
for _, case in ipairs({{11509, "Classic Era"}, {15999, "below the range"},
                       {20000, "TBC boundary"}, {20506, "TBC"}}) do
    local E = Detect(case[1], 2, true)
    Check(case[2] .. " (" .. case[1] .. ") IsForever", E.IsForever, false)
end

-------------------------------------------------
-- 3. The safety invariant, stated directly
--
-- Retail carries the richest feature set by far (reagent bag, bank tabs, native
-- sort, account-bound items). Selecting it wrongly on a Classic client calls APIs
-- that do not exist, so nothing below 100000 may reach it on a project ID alone.
-- Forever is the sole exception, asserted separately below.
-------------------------------------------------
print("")
print("Safety invariant -- no sub-100000 client may be classified Retail:")

local ADVERSARIAL = {
    {11509,  1,   "Classic Era claiming MAINLINE"},
    {50504,  1,   "MoP claiming MAINLINE"},
    {40402,  14,  "Cata Classic (flavor GudaBags does not handle)"},
    {30405,  11,  "Wrath Classic (flavor GudaBags does not handle)"},
    {0,      1,   "GetBuildInfo returned nothing usable"},
}

for _, case in ipairs(ADVERSARIAL) do
    local E = Detect(case[1], case[2], case[2] ~= nil)
    print(string.format("  %-46s iface=%-6d -> %s", case[3], case[1], FlagString(E)))
    Check(case[3] .. " IsRetail", E.IsRetail, false)
end

-- Real Retail must still be detected, including a future patch number.
for _, iface in ipairs({100002, 110207, 120100, 130000}) do
    local E = Detect(iface, 1, true)
    Check("Retail iface " .. iface .. " IsRetail", E.IsRetail, true)
    Check("Retail iface " .. iface .. " IsForever", E.IsForever, false)
end

-- The documented exception: Forever is below 100000 and IS Retail, because its
-- version number is the one signal that misdescribes the client. It must hold
-- whatever the client reports for WOW_PROJECT_ID -- including WOW_PROJECT_CLASSIC,
-- which is plausible given Forever ships under the wow_classic_beta product.
print("  (exception) Forever is below 100000 and IS Retail, by design:")
for _, pid in ipairs({1, 2, 27}) do
    local E = Detect(16001, pid, true)
    print(string.format("    pid=%-3d iface=16001 -> %s", pid, FlagString(E)))
    Check("Forever exception pid " .. pid .. " IsRetail", E.IsRetail, true)
    Check("Forever exception pid " .. pid .. " IsClassicEra", E.IsClassicEra, false)
end

-------------------------------------------------
-- 4. Mutual exclusion
--
-- IsForever is a SUBSET of IsRetail, not a peer: Forever is the modern API surface,
-- which is what the existing IsRetail call sites care about. The three flavor
-- buckets stay mutually exclusive.
-------------------------------------------------
print("")
print("Mutual exclusion across every scenario:")

local ALL = {}
for _, c in ipairs(SHIPPED) do ALL[#ALL + 1] = {c.iface, c.pid, true} end
for _, c in ipairs(FOREVER_CASES) do ALL[#ALL + 1] = {16001, c.pid, c.consts} end
for _, c in ipairs(ADVERSARIAL) do ALL[#ALL + 1] = {c[1], c[2], c[2] ~= nil} end

for _, case in ipairs(ALL) do
    local E = Detect(case[1], case[2], case[3])
    local tag = "iface " .. case[1] .. " pid " .. tostring(case[2])

    local n = 0
    for _, flag in ipairs({E.IsRetail, E.IsTBC, E.IsMoP}) do
        if flag then n = n + 1 end
    end
    if n > 1 then
        failures = failures + 1
        print("  <<< FAIL " .. tag .. ": Retail/TBC/MoP not mutually exclusive")
    end

    if E.IsForever and not E.IsRetail then
        failures = failures + 1
        print("  <<< FAIL " .. tag .. ": IsForever true but IsRetail false")
    end
    if E.IsRetail and E.IsClassicEra then
        failures = failures + 1
        print("  <<< FAIL " .. tag .. ": Retail and ClassicEra both true")
    end
end
print("  " .. #ALL .. " scenario(s) checked")

-------------------------------------------------
-- 5. Carried container discovery (Core/Constants.lua)
--
-- Constants derives BAG_IDS from the client rather than hardcoding it, because the
-- layout is not the same across flavors: Retail is backpack + 4 bags + reagent bag
-- at 5, while WoW: Forever adds a FIFTH equipped bag and pushes its reagent bag to
-- 6 -- so on Forever, id 5 means something different than it does on Retail.
--
-- The Retail rows are the regression lock: they must reproduce the hardcoded list
-- this file replaced, exactly.
-------------------------------------------------
print("")
print("Carried container discovery:")

-- Constants.lua reaches further into the client than Expansion.lua does (item class
-- tables, the font picker). Stub just enough to let it run to the end; none of it
-- affects the bag-id derivation under test.
GetLocale = function() return "enUS" end
GetItemClassInfo = function(classID) return "Class" .. tostring(classID) end
GetItemSubClassInfo = function(c, s) return "Sub" .. tostring(c) .. "." .. tostring(s) end
GetItemInfoInstant = function() return nil end
STANDARD_TEXT_FONT = "Fonts/FRIZQT__.TTF"
UnitClass = function() return "Warrior", "WARRIOR" end
bit = bit or {band = function(a, b)
    local res, shift = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then res = res + shift end
        a, b, shift = math.floor(a / 2), math.floor(b / 2), shift * 2
    end
    return res
end}

-- Loads the real Core/Constants.lua against a stubbed client. Only the globals the
-- bag-id derivation reads are varied; the rest are the minimum needed to reach the
-- end of the file.
local function DiscoverBags(iface, projectID, numBagSlots, numTotalEquipped, reagentID, bankTabs)
    local E, ns = Detect(iface, projectID, true)

    NUM_BAG_SLOTS = numBagSlots
    NUM_TOTAL_EQUIPPED_BAG_SLOTS = numTotalEquipped
    if reagentID or bankTabs then
        local bagIndex = { ReagentBag = reagentID }
        for i = 1, (bankTabs or 0) do
            bagIndex["CharacterBankTab_" .. i] = 20 + i
            bagIndex["AccountBankTab_" .. i] = 40 + i
        end
        Enum = { BagIndex = bagIndex }
    else
        Enum = nil
    end

    ns.L = setmetatable({}, {__index = function(_, k) return k end})
    assert(loadfile(ADDON .. "/Core/Constants.lua"))("GudaBags", ns)
    return ns.Constants
end

local BAG_CASES = {
    {name = "Classic Era",  iface = 11509,  pid = 2,  numBag = nil, total = nil,
     reagent = nil, tabs = nil, ids = "0, 1, 2, 3, 4",          reagentOut = nil},
    {name = "Retail 12.1",  iface = 120100, pid = 1,  numBag = 4,   total = 5,
     reagent = 5,   tabs = 6,   ids = "0, 1, 2, 3, 4, 5",       reagentOut = 5},
    {name = "FOREVER",      iface = 16001,  pid = 1,  numBag = 5,   total = 6,
     reagent = 6,   tabs = 9,   ids = "0, 1, 2, 3, 4, 5, 6",    reagentOut = 6},
    -- NUM_TOTAL_EQUIPPED_BAG_SLOTS absent: rebuild from NUM_BAG_SLOTS + reagent bag.
    {name = "FOREVER (no total)", iface = 16001, pid = 1, numBag = 5, total = nil,
     reagent = 6,   tabs = 9,   ids = "0, 1, 2, 3, 4, 5, 6",    reagentOut = 6},
    -- A Retail-path client that reports no reagent bag must not get one invented.
    -- An earlier draft defaulted REAGENT_BAG to 5 and appended that id to BAG_IDS,
    -- which made the addon scan a container the client does not have.
    {name = "Retail, no reagent", iface = 120100, pid = 1, numBag = 4, total = 4,
     reagent = nil, tabs = 6,   ids = "0, 1, 2, 3, 4",          reagentOut = nil},
}

for _, case in ipairs(BAG_CASES) do
    local C = DiscoverBags(case.iface, case.pid, case.numBag, case.total,
                           case.reagent, case.tabs)
    local got = table.concat(C.BAG_IDS, ", ")
    print(string.format("  %-20s BAG_IDS = {%s}  REAGENT_BAG = %s  PLAYER_BAG_MAX = %s",
          case.name, got, tostring(C.REAGENT_BAG), tostring(C.PLAYER_BAG_MAX)))

    Check(case.name .. " BAG_IDS", got, case.ids)
    if case.reagentOut == nil then
        Check(case.name .. " REAGENT_BAG absent", C.REAGENT_BAG, nil)
    else
        Check(case.name .. " REAGENT_BAG", C.REAGENT_BAG, case.reagentOut)
        -- The reagent bag must never raise PLAYER_BAG_MAX: that means "last ordinary
        -- bag", and callers size loops off it.
        Check(case.name .. " PLAYER_BAG_MAX", C.PLAYER_BAG_MAX, case.reagentOut - 1)
    end

    -- IsPlayerBagID is built from BAG_IDS, so every discovered id must pass it and
    -- the first id past the end must not. This is the gate BagScanner gives
    -- BAG_UPDATE, so a false negative means a container never refreshes live.
    for _, bagID in ipairs(C.BAG_IDS) do
        Check(case.name .. " IsPlayerBagID(" .. bagID .. ")", C.IsPlayerBagID(bagID), true)
    end
    local beyond = C.BAG_IDS[#C.BAG_IDS] + 1
    Check(case.name .. " IsPlayerBagID(" .. beyond .. ")", C.IsPlayerBagID(beyond), false)

    if case.tabs then
        Check(case.name .. " character bank tabs", #C.CHARACTER_BANK_TAB_IDS, case.tabs)
        Check(case.name .. " warband bank tabs", #C.WARBAND_BANK_TAB_IDS, case.tabs)
    end
end

print("")
if failures == 0 then
    print("ALL PASS - Forever detected as modern-API, shipped flavors unchanged")
else
    print(failures .. " FAILURE(S)")
    os.exit(1)
end
