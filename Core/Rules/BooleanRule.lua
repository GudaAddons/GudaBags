local addonName, ns = ...

local RuleEngine = ns:GetModule("RuleEngine")
local Constants = ns.Constants

-------------------------------------------------
-- Helper Functions
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

    -- Check by name patterns
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

local function IsSoulShard(itemData)
    return itemData.itemID == 6265 or
           (itemData.name and itemData.name:find("Soul Shard"))
end

local function IsProjectile(itemData)
    return itemData.itemType == "Projectile" or
           itemData.itemSubType == "Arrow" or
           itemData.itemSubType == "Bullet"
end

-------------------------------------------------
-- Quest Item Rule
-- Uses isQuestItem flag from ItemScanner
-------------------------------------------------

RuleEngine:RegisterEvaluator("isQuestItem", function(ruleValue, itemData, context)
    return (itemData.isQuestItem == true) == ruleValue
end)

-------------------------------------------------
-- Profession Tool Rule
-- Fishing poles, mining picks, skinning knives, etc.
-------------------------------------------------

RuleEngine:RegisterEvaluator("isProfessionTool", function(ruleValue, itemData, context)
    return IsProfessionTool(itemData) == ruleValue
end)

-------------------------------------------------
-- Soul Shard Rule
-- Warlock soul shards (item ID 6265)
-------------------------------------------------

RuleEngine:RegisterEvaluator("isSoulShard", function(ruleValue, itemData, context)
    return IsSoulShard(itemData) == ruleValue
end)

-------------------------------------------------
-- Projectile Rule
-- Arrows and bullets
-------------------------------------------------

RuleEngine:RegisterEvaluator("isProjectile", function(ruleValue, itemData, context)
    return IsProjectile(itemData) == ruleValue
end)
