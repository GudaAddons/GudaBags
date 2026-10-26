-- Harness: Compatibility/BagConflicts.lua finds loaded bag replacements,
-- honours "Keep both", and every button and message has an enUS string.

local Stubs = dofile(os.getenv("GUDABAGS_PATH") .. "/tests/stubs.lua")
local ns, LoadFile = Stubs.NewAddon()

local loaded = {}
ns.IsAddOnLoaded = function(name) return loaded[name] == true end
StaticPopupDialogs = {}
ns:RegisterModule("Events", {OnPlayerLogin = function() end, Register = function() end})
LoadFile("Compatibility/BagConflicts.lua")

local BagConflicts = ns:GetModule("Compatibility.BagConflicts")
local T = Stubs.NewChecker()

print("Detection:")
GudaBags_DB = {}
T.check("nothing loaded -> no conflict", #BagConflicts:GetActiveConflicts() == 0)
loaded.EllesmereUIBags = true
local c = BagConflicts:GetActiveConflicts()
T.check("EllesmereUIBags detected", #c == 1 and c[1] == "EllesmereUIBags")
loaded.Baganator = true
T.check("several listed together", #BagConflicts:GetActiveConflicts() == 2)
loaded.EllesmereUI = true
T.check("the rest of EllesmereUI is not a conflict", #BagConflicts:GetActiveConflicts() == 2)
GudaBags_DB.ignoredBagConflicts = {EllesmereUIBags = true}
c = BagConflicts:GetActiveConflicts()
T.check("'Keep both' is remembered", #c == 1 and c[1] == "Baganator")

print("")
print("Popup wiring:")
local dialog = StaticPopupDialogs["GUDABAGS_BAG_CONFLICT"]
T.check("dialog registered", dialog ~= nil)
T.check("Escape does not act (it reports as a click)", dialog.hideOnEscape == false)
T.check("disabling GudaBags is only on its own button (OnAlt)", type(dialog.OnAlt) == "function")

-- Every key the popup uses exists in enUS (Rule 5)
local enUS = {}
for line in io.lines(os.getenv("GUDABAGS_PATH") .. "/Locales.lua") do
    local key = line:match('^L%["([%w_]+)"%]')
    if key then enUS[key] = true end
    if line:match("^local L = Locales%.frFR") then break end
end
for _, key in ipairs({"BAG_CONFLICT_TEXT", "BAG_CONFLICT_DISABLE_OTHER",
                      "BAG_CONFLICT_DISABLE_GUDA", "BAG_CONFLICT_KEEP_BOTH"}) do
    T.check("enUS has " .. key, enUS[key] == true)
end

T.finish("bag addon conflicts are detected and wired safely")
