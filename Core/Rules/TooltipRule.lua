local addonName, ns = ...

local RuleEngine = ns:GetModule("RuleEngine")
local Constants = ns.Constants

-------------------------------------------------
-- Helper: Check if item is a profession tool
-------------------------------------------------

local function IsProfessionTool(itemData)
    if itemData.itemID and Constants.PROFESSION_TOOL_IDS[itemData.itemID] then
        return true
    end

    local subtype = itemData.itemSubType
    if subtype == "Fishing Poles" or subtype == "Fishing Pole" then
        return true
    end

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
-- Bind on Equip Rule
-- Requires tooltip scan (not available for other characters)
-------------------------------------------------

RuleEngine:RegisterEvaluator("isBoE", function(ruleValue, itemData, context)
    -- Can't scan tooltips for other characters
    if context.isOtherChar then
        return false
    end

    local TooltipScanner = ns:GetModule("TooltipScanner")
    if not TooltipScanner then
        return false
    end

    local isBoE = TooltipScanner:IsBindOnEquip(context.bagID, context.slotID, itemData)
    return isBoE == ruleValue
end)

-------------------------------------------------
-- Restore Tag Rule (Food/Drink/Restore)
-- Requires tooltip scan
-------------------------------------------------

RuleEngine:RegisterEvaluator("restoreTag", function(ruleValue, itemData, context)
    -- Can't scan tooltips for other characters
    if context.isOtherChar then
        return false
    end

    local TooltipScanner = ns:GetModule("TooltipScanner")
    if not TooltipScanner then
        return false
    end

    local tag = TooltipScanner:GetRestoreTag(context.bagID, context.slotID, itemData)
    return tag == ruleValue
end)

-------------------------------------------------
-- Junk Item Rule
-- Gray quality OR white equippable without special properties
-------------------------------------------------

RuleEngine:RegisterEvaluator("isJunk", function(ruleValue, itemData, context)
    -- For other characters, only check quality
    if context.isOtherChar then
        return (itemData.quality == 0) == ruleValue
    end

    -- Profession tools are never junk
    if IsProfessionTool(itemData) then
        return false == ruleValue
    end

    -- Gray items are always junk
    if itemData.quality == 0 then
        return true == ruleValue
    end

    -- White equippable items might be junk (only if setting is enabled)
    if itemData.quality == 1 then
        local Database = ns:GetModule("Database")
        local whiteItemsJunk = Database and Database:GetSetting("whiteItemsJunk") or false

        if whiteItemsJunk and (itemData.itemType == "Armor" or itemData.itemType == "Weapon") then
            local equipSlot = itemData.equipSlot
            if equipSlot and equipSlot ~= "" then
                -- Trinkets, rings, necks, shirts, tabards, off-hands, relics are never junk
                if Constants.VALUABLE_EQUIP_SLOTS[equipSlot] then
                    return false == ruleValue
                end

                -- Check for special properties using TooltipScanner
                local TooltipScanner = ns:GetModule("TooltipScanner")
                if TooltipScanner and context.bagID and context.slotID then
                    if TooltipScanner:HasSpecialProperties(context.bagID, context.slotID) then
                        return false == ruleValue
                    end
                end

                -- White equippable without special properties = junk
                return true == ruleValue
            end
        end
    end

    return false == ruleValue
end)
