local addonName, ns = ...

local RuleEngine = ns:GetModule("RuleEngine")

-------------------------------------------------
-- Name Pattern Rule
-- Lua pattern match on item name (case-insensitive)
-------------------------------------------------

RuleEngine:RegisterEvaluator("namePattern", function(ruleValue, itemData, context)
    if not itemData.name then
        return false
    end

    -- Case-insensitive search
    return itemData.name:lower():find(ruleValue:lower()) ~= nil
end)

-------------------------------------------------
-- Texture Pattern Rule
-- Pattern match on icon texture path
-------------------------------------------------

RuleEngine:RegisterEvaluator("texturePattern", function(ruleValue, itemData, context)
    if not itemData.texture then
        return false
    end

    local texturePath = tostring(itemData.texture)
    return texturePath:find(ruleValue) ~= nil
end)
