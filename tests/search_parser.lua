-- Harness: SearchParser (pure logic). Parses real query strings with the
-- addon's actual parser and matches them against hand-built item records.

local Stubs = dofile(os.getenv("GUDABAGS_PATH") .. "/tests/stubs.lua")
local ns, LoadFile = Stubs.NewAddon()

LoadFile("Core/Constants.lua")
LoadFile("Core/Utils.lua")

-- Fake tooltip scanner: tt: needles are matched against this text
local tooltipText = {}
ns:RegisterModule("TooltipScanner", {
    GetSearchText = function(_, itemData) return tooltipText[itemData.itemID] end,
})
LoadFile("Core/SearchParser.lua")

local SearchParser = ns:GetModule("SearchParser")
local CLASS = ns.Constants.ITEM_CLASS
local T = Stubs.NewChecker()

local SWORD = {itemID = 1, name = "Arcanite Reaper", quality = 4, classID = CLASS.WEAPON,
    itemType = "Weapon", itemSubType = "Two-Handed Axes", itemLevel = 63,
    itemMinLevel = 58, equipSlot = "INVTYPE_2HWEAPON"}
local POTION = {itemID = 2, name = "Major Healing Potion", quality = 1, classID = CLASS.CONSUMABLE,
    itemType = "Consumable", itemSubType = "Potion", itemLevel = 55, itemMinLevel = 45, equipSlot = ""}
local GREY = {itemID = 3, name = "Broken Fang", quality = 0, classID = CLASS.MISCELLANEOUS,
    itemType = "Miscellaneous", itemSubType = "Junk", itemLevel = 1, equipSlot = ""}
local QUESTITEM = {itemID = 4, name = "Dusty Letter", quality = 1, classID = CLASS.QUEST,
    itemType = "Quest", itemSubType = "Quest", isQuestItem = true, equipSlot = ""}
tooltipText[1] = "chance on hit: delivers a fatal wound"
tooltipText[2] = "use: restores 1050 health"

local function matches(query, item)
    return SearchParser:MatchesParsed(SearchParser:ParseSearchInput(query), item, {})
end

print("Parsing:")
T.check("empty query parses to nil", SearchParser:ParseSearchInput("") == nil)
T.check("nil query parses to nil", SearchParser:ParseSearchInput(nil) == nil)
local p = SearchParser:ParseSearchInput("q>=rare ilvl>60 junk reaper")
T.check("quality operator parsed", p.operators[1].type == "quality" and p.operators[1].op == ">=" and p.operators[1].value == 3)
T.check("ilvl operator parsed", p.operators[2].type == "itemLevel" and p.operators[2].value == 60)
T.check("keyword parsed", p.keywords[1] == "junk")
T.check("leftover text lowercased", p.textSearch == "reaper")
T.check("t:weapon resolves to a classID", SearchParser:ParseSearchInput("t:weapon").operators[1].type == "itemClass")
T.check("unknown type falls back to itemType", SearchParser:ParseSearchInput("t:widget").operators[1].type == "itemType")
local quoted = SearchParser:ParseSearchInput('tt:"chance on hit"')
T.check("quoted tt: phrase stays one needle", quoted.tooltipText and quoted.tooltipText[1] == "chance on hit"
    and quoted.textSearch == nil)
T.check("tt: kept out of the operator list", #quoted.operators == 0)
T.check("unknown slot alias is free text", SearchParser:ParseSearchInput("s:elbow").textSearch == "s:elbow")

print("")
print("Matching:")
T.check("plain text matches name", matches("reaper", SWORD))
T.check("plain text is case-insensitive", matches("ARCANITE", SWORD))
T.check("plain text matches subtype", matches("potion", POTION))
T.check("plain text rejects others", not matches("reaper", POTION))
T.check("q:epic", matches("q:epic", SWORD) and not matches("q:epic", POTION))
T.check("q<2 numeric", matches("q<2", POTION) and not matches("q<2", SWORD))
T.check("ilvl>60", matches("ilvl>60", SWORD) and not matches("ilvl>60", POTION))
T.check("lvl<=45", matches("lvl<=45", POTION) and not matches("lvl<=45", SWORD))
T.check("t:weapon via classID", matches("t:weapon", SWORD) and not matches("t:weapon", POTION))
T.check("s:twohand", matches("s:twohand", SWORD) and not matches("s:twohand", POTION))
T.check("n: substring", matches("n:healing", POTION))
T.check("junk keyword", matches("junk", GREY) and not matches("junk", POTION))
T.check("quest keyword", matches("quest", QUESTITEM) and not matches("quest", SWORD))
T.check("terms AND together", matches("q:epic reaper", SWORD) and not matches("q:epic potion", SWORD))
T.check("tt: needle matches tooltip", matches('tt:"fatal wound"', SWORD))
T.check("tt: needle rejects others", not matches("tt:fatal", POTION))
T.check("nil parse matches everything", SearchParser:MatchesParsed(nil, SWORD, {}))

T.finish("SearchParser parses and matches as expected")
