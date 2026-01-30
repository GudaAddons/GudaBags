local addonName, ns = ...

local RuleEngine = ns:GetModule("RuleEngine")
local Constants = ns.Constants

-------------------------------------------------
-- Helper: Check if item is a profession tool
-------------------------------------------------

local function IsProfessionTool(itemData)
    -- Check by item ID first
    if itemData.itemID and Constants.PROFESSION_TOOL_IDS[itemData.itemID] then
        return true
    end

    -- Check fishing poles by subtype
    local subtype = itemData.itemSubType
    if subtype == "Fishing Poles" or subtype == "Fishing Pole" then
        return true
    end

    -- Check by name patterns for items we might have missed
    local name = itemData.name
    if name then
        if name:find("Mining Pick") or name:find("Skinning Knife") or
           name:find("Blacksmith Hammer") or name:find("Runed.*Rod") or
           name:find("Philosopher's Stone") or name:find("Alchemist") or
           name:find("Spanner") or name:find("Gyromatic") then
            return true
        end
    end

    return false
end

-------------------------------------------------
-- Item Type Rule
-- Matches GetItemInfo itemType (Armor, Weapon, Consumable, etc.)
-------------------------------------------------

RuleEngine:RegisterEvaluator("itemType", function(ruleValue, itemData, context)
    -- Profession tools should not match Weapon category
    if ruleValue == "Weapon" and IsProfessionTool(itemData) then
        return false
    end
    return itemData.itemType == ruleValue
end)

-------------------------------------------------
-- Item Subtype Rule
-- Matches GetItemInfo itemSubType
-------------------------------------------------

RuleEngine:RegisterEvaluator("itemSubtype", function(ruleValue, itemData, context)
    local subtype = itemData.itemSubType or ""

    -- Check for exact match first
    if subtype == ruleValue then
        return true
    end

    -- Check for partial match (e.g., "Soul Bag" matching "Soul Bag")
    if subtype:find(ruleValue, 1, true) then
        return true
    end

    return false
end)

-------------------------------------------------
-- Reagent Rule (Crafting Materials)
-- Trade Goods (classID 7) excluding Explosives (2) and Devices (3)
-------------------------------------------------

RuleEngine:RegisterEvaluator("isReagent", function(ruleValue, itemData, context)
    -- Reagent = Trade Goods (classID 7) excluding Explosives (subClassID 2) and Devices (subClassID 3)
    if itemData.classID == 7 then
        return itemData.subClassID ~= 2 and itemData.subClassID ~= 3
    end
    return false
end)
