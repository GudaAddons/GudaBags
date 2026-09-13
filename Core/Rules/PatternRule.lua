local addonName, ns = ...

local RuleEngine = ns:GetModule("RuleEngine")
local Utils = ns:GetModule("Utils")

local strfind = string.find

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
-- Tooltip Contains Rule
-- Case-insensitive plain-substring search across all tooltip lines.
-- Unlike namePattern, this scans the full hidden tooltip (flavor text,
-- Use/Equip effects, class restrictions, set bonuses, etc.).
-------------------------------------------------

RuleEngine:RegisterEvaluator("tooltipPattern", function(ruleValue, itemData, context)
    if not ruleValue or ruleValue == "" then
        return false
    end

    local TooltipScanner = ns:GetModule("TooltipScanner")
    if not TooltipScanner then
        return false
    end

    -- Shares the cached blob with the tt: search prefix, so a category rule and a
    -- search never render the same tooltip twice, and the two can never drift
    -- into answering "does this tooltip contain X" differently. The accessor
    -- prefers the hyperlink (which also works for cached/cross-character views)
    -- and falls back to the bag slot exactly as this used to.
    local text = TooltipScanner:GetSearchText(itemData,
        context and context.bagID, context and context.slotID)
    if not text then
        return false
    end

    -- UTF8Lower, not :lower(): string.lower folds only A-Z, so a Cyrillic or
    -- accented rule value silently matched nothing unless the case happened to
    -- agree. ASCII input takes UTF8Lower's fast path, so English rules are
    -- byte-identical to before.
    return strfind(text, Utils:UTF8Lower(ruleValue), 1, true) ~= nil
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
