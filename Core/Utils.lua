local addonName, ns = ...

local Utils = {}
ns:RegisterModule("Utils", Utils)

-------------------------------------------------
-- Item Key Generation
-- Creates a unique key for an item based on its properties
-- Used for button reuse optimization in category view
-------------------------------------------------

-- Generate unique key for an item (for button reuse in category view)
-- Items with same key can share buttons
function Utils:GetItemKey(itemData)
    if not itemData then return nil end
    -- Key based on: itemLink (or itemID), quality, bound status
    -- This matches items that are visually identical
    local link = itemData.link or ""
    local quality = itemData.quality or 0
    local isBound = itemData.isBound and "1" or "0"
    return link .. ":" .. quality .. ":" .. isBound
end

-------------------------------------------------
-- Slot Key Generation
-- Creates a unique key for a bag slot position
-------------------------------------------------

-- Generate slot key for tracking (bagID:slot)
function Utils:GetSlotKey(bagID, slot)
    return bagID .. ":" .. slot
end

-------------------------------------------------
-- Table Utilities
-------------------------------------------------

-- Deep copy a table
function Utils:DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[self:DeepCopy(k)] = self:DeepCopy(v)
        end
        setmetatable(copy, self:DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Count entries in a table (for tables with non-numeric keys)
function Utils:TableCount(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Check if table is empty
function Utils:IsTableEmpty(tbl)
    if not tbl then return true end
    return next(tbl) == nil
end
