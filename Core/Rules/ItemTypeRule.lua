local addonName, ns = ...

local RuleEngine = ns:GetModule("RuleEngine")
local Utils = ns:GetModule("Utils")
local Constants = ns.Constants

local ITEM_CLASS_BY_NAME = Constants.ITEM_CLASS_BY_NAME
local ITEM_SUBCLASS_BY_NAME = Constants.ITEM_SUBCLASS_BY_NAME
local TRADE_GOODS_SUBCLASS = Constants.TRADE_GOODS_SUBCLASS
local WEAPON_CLASS = Constants.ITEM_CLASS.WEAPON
local TRADE_GOODS_CLASS = Constants.ITEM_CLASS.TRADE_GOODS

-------------------------------------------------
-- Item Type Rule
-- Rule values are stored as canonical English names ("Armor", "Weapon", ...),
-- but GetItemInfo's itemType is localized, so matching on it breaks on every
-- non-enUS client. Resolve the rule value to a numeric classID and compare
-- that instead; fall back to the string compare when the value isn't a known
-- class (custom user-entered values, including ones typed in the player's own
-- language) or when itemData predates classID being populated.
-------------------------------------------------

RuleEngine:RegisterEvaluator("itemType", function(ruleValue, itemData, context)
    local classID = ITEM_CLASS_BY_NAME[ruleValue]

    -- Profession tools should not match the Weapon category
    if classID == WEAPON_CLASS and Utils:IsProfessionTool(itemData) then
        return false
    end

    if classID and itemData.classID then
        return itemData.classID == classID
    end

    return itemData.itemType == ruleValue
end)

-------------------------------------------------
-- Item Subtype Rule
-- Free-text rule. Known English subtypes match numerically (locale-safe);
-- anything else falls back to matching the localized itemSubType string, so a
-- player can still type a subtype in their own language.
-------------------------------------------------

RuleEngine:RegisterEvaluator("itemSubtype", function(ruleValue, itemData, context)
    if type(ruleValue) ~= "string" then
        return false
    end

    local mapped = ITEM_SUBCLASS_BY_NAME[ruleValue]
    if mapped and itemData.classID and itemData.subClassID then
        return itemData.classID == mapped[1] and itemData.subClassID == mapped[2]
    end

    local subtype = itemData.itemSubType or ""

    -- Check for exact match first
    if subtype == ruleValue then
        return true
    end

    -- Check for partial match (e.g., "Soul Bag" matching "Soul Bag")
    if ruleValue ~= "" and subtype:find(ruleValue, 1, true) then
        return true
    end

    return false
end)

-------------------------------------------------
-- Reagent Rule (Crafting Materials)
-- Trade Goods (classID 7) excluding Explosives (2) and Devices (3)
-------------------------------------------------

RuleEngine:RegisterEvaluator("isReagent", function(ruleValue, itemData, context)
    -- Reagent = Trade Goods excluding Explosives and Devices
    if itemData.classID == TRADE_GOODS_CLASS then
        return itemData.subClassID ~= TRADE_GOODS_SUBCLASS.EXPLOSIVES
            and itemData.subClassID ~= TRADE_GOODS_SUBCLASS.DEVICES
    end
    return false
end)
