local addonName, ns = ...

local RuleEngine = {}
ns:RegisterModule("RuleEngine", RuleEngine)

local Constants = ns.Constants

-------------------------------------------------
-- Rule Evaluator Registry
-------------------------------------------------

local evaluators = {}

function RuleEngine:RegisterEvaluator(ruleType, evaluatorFunc)
    evaluators[ruleType] = evaluatorFunc
end

function RuleEngine:GetEvaluator(ruleType)
    return evaluators[ruleType]
end

function RuleEngine:GetRegisteredTypes()
    local types = {}
    for ruleType in pairs(evaluators) do
        table.insert(types, ruleType)
    end
    return types
end

-------------------------------------------------
-- Rule Evaluation
-------------------------------------------------

-- Evaluate a single rule against item data
-- Returns: boolean
function RuleEngine:Evaluate(rule, itemData, context)
    local ruleType = rule.type
    local ruleValue = rule.value

    local evaluator = evaluators[ruleType]
    if not evaluator then
        -- Unknown rule type, return false
        return false
    end

    return evaluator(ruleValue, itemData, context)
end

-- Evaluate multiple rules with match mode
-- matchMode: "any" (OR) or "all" (AND)
-- Returns: boolean
function RuleEngine:EvaluateAll(rules, itemData, context, matchMode)
    if not rules or #rules == 0 then
        return false
    end

    matchMode = matchMode or "any"

    if matchMode == "all" then
        -- All rules must match (AND)
        for _, rule in ipairs(rules) do
            if not self:Evaluate(rule, itemData, context) then
                return false
            end
        end
        return true
    else
        -- Any rule must match (OR)
        for _, rule in ipairs(rules) do
            if self:Evaluate(rule, itemData, context) then
                return true
            end
        end
        return false
    end
end

-------------------------------------------------
-- Context Builder
-------------------------------------------------

-- Build evaluation context from bag/slot info
function RuleEngine:BuildContext(bagID, slotID, isOtherChar)
    return {
        bagID = bagID,
        slotID = slotID,
        isOtherChar = isOtherChar or false,
    }
end
