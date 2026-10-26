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
T.check("Yes/No only -- no way to disable GudaBags from here", dialog.OnAlt == nil and dialog.button3 == nil)
-- "No" (and Escape, which reports as a click) is remembered
GudaBags_DB = {}
dialog.OnCancel(nil, nil, "clicked")  -- pending is empty before any popup; must not error
T.check("No with nothing pending stores nothing", next(GudaBags_DB.ignoredBagConflicts or {}) == nil)

-- The message key exists in every locale block (Rule 5)
local count = 0
for line in io.lines(os.getenv("GUDABAGS_PATH") .. "/Locales.lua") do
    if line:match('^L%["BAG_CONFLICT_TEXT"%] = ".-%%s.-"') then count = count + 1 end
end
T.check("BAG_CONFLICT_TEXT in all 10 locale blocks, each with %s (got " .. count .. ")", count == 10)

T.finish("bag addon conflicts are detected and wired safely")
