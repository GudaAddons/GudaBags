-- Harness: CategoryManager caching/migration and the user-text pattern rules,
-- loaded from the addon's real code with the WoW API stubbed.

local Stubs = dofile(os.getenv("GUDABAGS_PATH") .. "/tests/stubs.lua")
local ns, LoadFile = Stubs.NewAddon()

-- Database stub: just the category store and settings CategoryManager reads
local settings = {whiteItemsJunk = false}
local storedCategories = nil
ns:RegisterModule("Database", {
    GetSetting = function(_, key) return settings[key] end,
    IsItemMarkedJunk = function() return false end,
    GetCategories = function() return storedCategories end,
    SetCategories = function(_, categories) storedCategories = categories end,
})

LoadFile("Core/Constants.lua")
LoadFile("Core/Utils.lua")
LoadFile("DB/DefaultCategories.lua")
LoadFile("Core/RuleEngine.lua")
LoadFile("Core/Rules/ItemTypeRule.lua")
LoadFile("Core/Rules/ItemIDRule.lua")
LoadFile("Core/Rules/QualityRule.lua")
LoadFile("Core/Rules/TooltipRule.lua")
LoadFile("Core/Rules/PatternRule.lua")
LoadFile("Core/Rules/BooleanRule.lua")
LoadFile("Core/Rules/RecentRule.lua")
LoadFile("Core/CategoryManager.lua")

local CategoryManager = ns:GetModule("CategoryManager")
local RuleEngine = ns:GetModule("RuleEngine")
local DefaultCategories = ns.DefaultCategories
local CLASS = ns.Constants.ITEM_CLASS
local T = Stubs.NewChecker()

-- Count GetDefaults() calls: each one deep-copies every default category
local defaultsCalls = 0
local realGetDefaults = DefaultCategories.GetDefaults
DefaultCategories.GetDefaults = function(self)
    defaultsCalls = defaultsCalls + 1
    return realGetDefaults(self)
end

print("Migration runs once per saved table:")
local saved = realGetDefaults(DefaultCategories)
saved.definitions["Home"] = nil  -- something for the migration to restore
storedCategories = saved
CategoryManager:GetCategories()
local afterFirst = defaultsCalls
for _ = 1, 50 do CategoryManager:GetCategories() end
T.check("first call migrates", afterFirst == 1 and storedCategories.definitions["Home"] ~= nil)
T.check("later calls skip the migration (no defaults deep copy)", defaultsCalls == afterFirst)
storedCategories = realGetDefaults(DefaultCategories)  -- profile load / import swaps the table
CategoryManager:GetCategories()
T.check("a new saved table is migrated again", defaultsCalls == afterFirst + 1)

print("")
print("Category result cache:")
CategoryManager:InvalidatePriorityCache()
local whiteChest = {itemID = 10, name = "Linen Shirt", link = "|Hitem:10|h[Linen Vest]|h", quality = 1,
    classID = CLASS.ARMOR, subClassID = 1, itemType = "Armor", equipSlot = "INVTYPE_CHEST"}
settings.whiteItemsJunk = true
local own = CategoryManager:CategorizeItem(whiteChest, nil, nil, false)
local alt = CategoryManager:CategorizeItem(whiteChest, nil, nil, true)
T.check("own white chest is Junk with whiteItemsJunk on (got " .. tostring(own) .. ")", own == "Junk")
T.check("alt's identical link is not served the own-character verdict (got " .. tostring(alt) .. ")", alt ~= "Junk")
settings.whiteItemsJunk = false
local toggled = CategoryManager:CategorizeItem(whiteChest, nil, nil, false)
T.check("turning whiteItemsJunk off re-categorizes (got " .. tostring(toggled) .. ")", toggled ~= "Junk")

print("")
print("Name/icon rules take user text safely:")
local named = {name = "Elixir of the Mongoose", texture = 134875}
local ok, result = pcall(RuleEngine.Evaluate, RuleEngine, {type = "namePattern", value = "["}, named, {})
T.check("'[' does not throw", ok)
T.check("'[' matches nothing in this name", ok and result == false)
T.check("multi-word substring matches",
    RuleEngine:Evaluate({type = "namePattern", value = "of the mongoose"}, named, {}) == true)
T.check("invalid pattern matches as plain text",
    RuleEngine:Evaluate({type = "namePattern", value = "[mongoose"}, {name = "Oil [Mongoose] Brand"}, {}) == true)
T.check("case-insensitive contains", RuleEngine:Evaluate({type = "namePattern", value = "ELIXIR"}, named, {}) == true)
T.check("valid patterns keep their meaning", RuleEngine:Evaluate({type = "namePattern", value = "^elixir"}, named, {}) == true
    and RuleEngine:Evaluate({type = "namePattern", value = "^mongoose"}, named, {}) == false)
-- "(13" only throws ("unfinished capture") once matching gets past "13", which
-- happens on this texture -- an up-front probe against "" would miss it.
local okIcon, iconResult = pcall(RuleEngine.Evaluate, RuleEngine, {type = "texturePattern", value = "(13"}, named, {})
T.check("late-failing icon pattern does not throw", okIcon and iconResult == false)
T.check("late-failing name pattern does not throw",
    pcall(RuleEngine.Evaluate, RuleEngine, {type = "namePattern", value = "(eli"}, named, {}))
T.check("icon contains", RuleEngine:Evaluate({type = "texturePattern", value = "1348"}, named, {}) == true)

T.finish("category cache and pattern rules behave")
