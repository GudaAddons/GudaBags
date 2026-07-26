-- Harness: runs GudaBags' real rule-evaluation code under a simulated
-- English and Chinese client, and asserts categorization is identical.
--
-- Only the rule path is loaded (Init -> Constants -> Utils -> DefaultCategories
-- -> RuleEngine -> Core/Rules/*). WoW APIs are stubbed below.

local ADDON = os.getenv("GUDABAGS_PATH")

-------------------------------------------------
-- WoW API stubs
-------------------------------------------------
local CURRENT_LOCALE = "enUS"

-- Localized item class names per locale, keyed by classID (as the client would)
local CLASS_NAMES = {
    enUS = {[0]="Consumable",[1]="Container",[2]="Weapon",[3]="Gem",[4]="Armor",
            [5]="Reagent",[6]="Projectile",[7]="Trade Goods",[9]="Recipe",
            [11]="Quiver",[12]="Quest",[13]="Key",[15]="Miscellaneous",[16]="Glyph"},
    zhCN = {[0]="消耗品",[1]="容器",[2]="武器",[3]="宝石",[4]="护甲",
            [5]="材料",[6]="弹药",[7]="商品",[9]="配方",
            [11]="箭袋",[12]="任务",[13]="钥匙",[15]="其它",[16]="雕文"},
    deDE = {[0]="Verbrauchbar",[1]="Behälter",[2]="Waffe",[3]="Edelstein",[4]="Rüstung",
            [5]="Reagenz",[6]="Projektil",[7]="Handwerkswaren",[9]="Rezept",
            [11]="Köcher",[12]="Quest",[13]="Schlüssel",[15]="Verschiedenes",[16]="Glyphe"},
}

local SUBCLASS_NAMES = {
    enUS = {["1:1"]="Soul Bag", ["2:20"]="Fishing Poles", ["2:7"]="One-Handed Swords",
            ["6:2"]="Arrow", ["6:3"]="Bullet", ["0:0"]="Consumable", ["4:2"]="Leather"},
    zhCN = {["1:1"]="灵魂袋", ["2:20"]="鱼竿", ["2:7"]="单手剑",
            ["6:2"]="箭", ["6:3"]="子弹", ["0:0"]="消耗品", ["4:2"]="皮甲"},
    deDE = {["1:1"]="Seelentasche", ["2:20"]="Angelruten", ["2:7"]="Einhandschwerter",
            ["6:2"]="Pfeil", ["6:3"]="Kugel", ["0:0"]="Verbrauchbar", ["4:2"]="Leder"},
}

function GetItemClassInfo(classID)
    return CLASS_NAMES[CURRENT_LOCALE][classID]
end

function GetItemSubClassInfo(classID, subClassID)
    return SUBCLASS_NAMES[CURRENT_LOCALE][classID .. ":" .. subClassID]
end

function GetLocale() return CURRENT_LOCALE end
function UnitClass() return "Warlock", "WARLOCK" end
function CreateFrame() return setmetatable({}, {__index = function() return function() end end}) end
function UnitName() return "Tester" end

C_AddOns = {GetAddOnMetadata = function() return "2.0.7" end}
C_Timer = {After = function(_, fn) fn() end}
C_Container = {}
C_Item = {}
Enum = {ItemClass = {Quiver = 11, Container = 1}, BagIndex = {}}
bit = {band = function(a, b)
    local res, shift = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then res = res + shift end
        a, b, shift = math.floor(a / 2), math.floor(b / 2), shift * 2
    end
    return res
end}

string.join = function(sep, ...) return table.concat({...}, sep) end
tostringall = function(...) return ... end

-- Tooltip-derived globals (localized by the real client)
ITEM_SPELL_TRIGGER_ONUSE = "Use:"
ITEM_SPELL_TRIGGER_ONEQUIP = "Equip:"

-------------------------------------------------
-- Addon loader
-------------------------------------------------
local ns = {}

local function LoadFile(relPath)
    local path = ADDON .. "/" .. relPath
    local chunk, err = loadfile(path)
    if not chunk then error("load failed: " .. relPath .. "\n" .. tostring(err)) end
    return chunk("GudaBags", ns)
end

LoadFile("Core/Init.lua")

-- Expansion stub (real one probes WoW build APIs)
local Expansion = {
    IsRetail = false, IsClassicEra = true, IsTBC = false,
    Features = {HasKeyring = true, HasQuiverBags = true},
}
ns:RegisterModule("Expansion", Expansion)

-- Minimal Database stub: only GetSetting is reached from the rule path
ns:RegisterModule("Database", {
    GetSetting = function(_, key)
        if key == "whiteItemsJunk" then return false end
        return nil
    end,
    IsItemMarkedJunk = function() return false end,
})

ns.L = setmetatable({}, {__index = function(_, k) return k end})

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

local RuleEngine = ns:GetModule("RuleEngine")
local DefaultCategories = ns.DefaultCategories

-------------------------------------------------
-- Categorize using the same priority ordering CategoryManager uses
-------------------------------------------------
-- Note: `enabled` is deliberately ignored. Some built-ins are class-gated
-- (Quiver Bag = Hunter, Soul Bag = Warlock) and that gating is orthogonal to
-- the locale behaviour under test.
local function Categorize(itemData)
    local ordered = {}
    for id, def in pairs(DefaultCategories.DEFINITIONS) do
        if def.rules and #def.rules > 0 then
            table.insert(ordered, {id = id, def = def})
        end
    end
    table.sort(ordered, function(a, b)
        if a.def.priority == b.def.priority then return a.id < b.id end
        return a.def.priority > b.def.priority
    end)

    local context = RuleEngine:BuildContext(nil, nil, true)  -- isOtherChar: skip tooltip scans
    for _, entry in ipairs(ordered) do
        if RuleEngine:EvaluateAll(entry.def.rules, itemData, context, entry.def.matchMode) then
            return entry.id
        end
    end
    return "Miscellaneous"
end

-------------------------------------------------
-- Test items: classID/subClassID are what the game actually returns
-------------------------------------------------
local ITEMS = {
    {name = "Sword",         classID = 2,  subClassID = 7,  quality = 2, expect = "Weapon"},
    {name = "Leather Vest",  classID = 4,  subClassID = 2,  quality = 2, expect = "Armor"},
    {name = "Healing Potion",classID = 0,  subClassID = 0,  quality = 1, expect = "Consumable"},
    {name = "Copper Bar",    classID = 7,  subClassID = 1,  quality = 1, expect = "Reagent"},
    {name = "Bomb",          classID = 7,  subClassID = 2,  quality = 1, expect = "Trade Goods"},
    {name = "Recipe Scroll", classID = 9,  subClassID = 1,  quality = 1, expect = "Recipe"},
    {name = "Small Bag",     classID = 1,  subClassID = 0,  quality = 1, expect = "Container"},
    {name = "Felcloth Bag",  classID = 1,  subClassID = 1,  quality = 2, expect = "Soul Bag"},
    {name = "Quiver",        classID = 11, subClassID = 2,  quality = 1, expect = "Quiver Bag"},
    {name = "Arrow",         classID = 6,  subClassID = 2,  quality = 1, expect = "Class Items"},
    {name = "Skeleton Key",  classID = 13, subClassID = 0,  quality = 1, expect = "Keyring"},
    {name = "Fishing Pole",  classID = 2,  subClassID = 20, quality = 1, expect = "Tools"},
    {name = "Grey Junk",     classID = 15, subClassID = 0,  quality = 0, expect = "Junk"},
    {name = "Trinket",       classID = 15, subClassID = 0,  quality = 3, expect = "Miscellaneous"},
}

-- Build itemData the way the scanners do, with itemType/itemSubType localized
local function BuildItemData(item, locale)
    return {
        itemID = 1000 + item.classID * 10 + item.subClassID,
        name = item.name,
        link = "|Hitem:" .. item.classID .. "|h[" .. item.name .. "]|h",
        quality = item.quality,
        classID = item.classID,
        subClassID = item.subClassID,
        itemType = CLASS_NAMES[locale][item.classID] or "",
        itemSubType = SUBCLASS_NAMES[locale][item.classID .. ":" .. item.subClassID] or "",
        equipSlot = "",
    }
end

-------------------------------------------------
-- Run
-------------------------------------------------
local failures = 0
local LOCALES = {"enUS", "zhCN", "deDE"}

print(string.format("%-16s %-14s %-14s %-14s %s", "ITEM", "enUS", "zhCN", "deDE", "EXPECTED"))
print(string.rep("-", 76))

for _, item in ipairs(ITEMS) do
    local results = {}
    for _, locale in ipairs(LOCALES) do
        CURRENT_LOCALE = locale
        results[locale] = Categorize(BuildItemData(item, locale))
    end

    local ok = true
    for _, locale in ipairs(LOCALES) do
        if results[locale] ~= item.expect then ok = false end
    end
    if not ok then failures = failures + 1 end

    print(string.format("%-16s %-14s %-14s %-14s %s  %s",
        item.name, results.enUS, results.zhCN, results.deDE, item.expect,
        ok and "PASS" or "<<< FAIL"))
end

-------------------------------------------------
-- Derived constants: ITEM_CLASS is generated from ITEM_CLASS_BY_NAME, so the
-- name -> KEY transform (notably "Trade Goods" -> TRADE_GOODS) must hold.
-------------------------------------------------
print("")
print("Derived Constants.ITEM_CLASS:")
local Constants = ns.Constants
local EXPECTED_CLASS = {
    CONSUMABLE = 0, CONTAINER = 1, WEAPON = 2, GEM = 3, ARMOR = 4,
    REAGENT = 5, PROJECTILE = 6, TRADE_GOODS = 7, RECIPE = 9,
    QUIVER = 11, QUEST = 12, KEY = 13, MISCELLANEOUS = 15, GLYPH = 16,
}
for key, id in pairs(EXPECTED_CLASS) do
    local actual = Constants.ITEM_CLASS[key]
    if actual ~= id then
        failures = failures + 1
        print(string.format("  <<< FAIL %s = %s (expected %d)", key, tostring(actual), id))
    end
end
-- Every name must produce exactly one key: no silent collisions or drops
local derivedCount = 0
for _ in pairs(Constants.ITEM_CLASS) do derivedCount = derivedCount + 1 end
local nameCount = 0
for _ in pairs(Constants.ITEM_CLASS_BY_NAME) do nameCount = nameCount + 1 end
if derivedCount ~= nameCount then
    failures = failures + 1
    print(string.format("  <<< FAIL derived %d keys from %d names", derivedCount, nameCount))
else
    print(string.format("  %d/%d keys derived correctly", derivedCount, nameCount))
end

-- Fishing pole is now a {classID, subClassID} pair derived from the subtype map
local fp = Constants.ITEM_SUBCLASS_FISHING_POLE
if type(fp) ~= "table" or fp[1] ~= 2 or fp[2] ~= 20 then
    failures = failures + 1
    print("  <<< FAIL ITEM_SUBCLASS_FISHING_POLE is not {2, 20}")
else
    print("  ITEM_SUBCLASS_FISHING_POLE = {2, 20}")
end

-- GetItemClassLabel must survive a classID the client doesn't know
CURRENT_LOCALE = "enUS"
local okBad, badLabel = pcall(Constants.GetItemClassLabel, 999)
if not okBad then
    failures = failures + 1
    print("  <<< FAIL GetItemClassLabel(999) raised an error")
else
    print("  GetItemClassLabel(999) -> " .. tostring(badLabel) .. " (no error)")
end

-------------------------------------------------
-- BagClassifier now uses Constants.ITEM_CLASS instead of Enum.ItemClass
-------------------------------------------------
C_Item.GetItemInfoInstant = function(itemID)
    local map = {
        [11362] = {11, 2},  -- Quiver
        [14156] = {1, 1},   -- Soul bag
        [4496]  = {1, 0},   -- Regular bag
        [22246] = {1, 2},   -- Herb bag
        [6948]  = {15, 0},  -- Hearthstone (not a container)
    }
    local e = map[itemID]
    if not e then return nil end
    return nil, nil, nil, nil, nil, e[1], e[2]
end
LoadFile("UI/BagFrame/BagClassifier.lua")
local BagClassifier = ns:GetModule("BagFrame.BagClassifier")

print("")
print("BagClassifier (Enum.ItemClass -> Constants.ITEM_CLASS):")
local BAG_CASES = {
    {itemID = 11362, expect = "quiver"},
    {itemID = 14156, expect = "soul"},
    {itemID = 4496,  expect = "regular"},
    {itemID = 22246, expect = "herb"},
    {itemID = 6948,  expect = "regular"},
}
for _, case in ipairs(BAG_CASES) do
    local got = BagClassifier:GetBagTypeFromItemID(case.itemID)
    local ok = got == case.expect
    if not ok then failures = failures + 1 end
    print(string.format("  %-8s -> %-8s expected %-8s %s",
        case.itemID, got, case.expect, ok and "PASS" or "<<< FAIL"))
end

-- Dropdown labels must follow the client language
print("")
print("Item Type dropdown labels:")
for _, locale in ipairs(LOCALES) do
    CURRENT_LOCALE = locale
    local ruleTypes = DefaultCategories:GetRuleTypes()
    local opts
    for _, rt in ipairs(ruleTypes) do
        if rt.id == "itemType" then opts = rt.options end
    end
    local parts = {}
    for i = 1, 4 do
        parts[i] = opts[i].label .. " (=" .. opts[i].value .. ")"
    end
    print("  " .. locale .. ": " .. table.concat(parts, ", "))
    -- Stored value must stay the canonical English name in every locale
    if opts[1].value ~= "Armor" or opts[2].value ~= "Weapon" then
        failures = failures + 1
        print("  <<< FAIL: stored value is not the canonical English name")
    end
end

print("")
if failures == 0 then
    print("ALL PASS - categorization identical across locales")
else
    print(failures .. " FAILURE(S)")
    os.exit(1)
end
