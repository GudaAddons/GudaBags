-- GudaBags Sort Engine
-- Multi-phase sorting algorithm for TBC Anniversary

local addonName, ns = ...

local SortEngine = {}
ns:RegisterModule("SortEngine", SortEngine)

local Constants = ns.Constants
local Database = ns:GetModule("Database")
local Events = ns:GetModule("Events")

-- Sorting state
local sortInProgress = false
local currentPass = 0
local maxPasses = 10  -- Increased from 6 to ensure sort completes
local soundsMuted = false

-- Performance: Caches to avoid repeated expensive operations
local specialPropertiesCache = {}  -- Cache HasSpecialProperties results by itemID
local sortKeyCache = {}            -- Cache computed sort keys by itemID

-- Performance tracking (debug)
local perfStats = {
    tooltipScans = 0,
    tooltipCacheHits = 0,
    sortKeyComputes = 0,
    sortKeyCacheHits = 0,
}

-- Use pickup sound IDs from Constants
local function MutePickupSounds()
    for _, soundID in ipairs(Constants.PICKUP_SOUND_IDS) do
        MuteSoundFile(soundID)
    end
end

local function UnmutePickupSounds()
    for _, soundID in ipairs(Constants.PICKUP_SOUND_IDS) do
        UnmuteSoundFile(soundID)
    end
end

--===========================================================================
-- SORT KEY DEFINITIONS
--===========================================================================

-- Priority items (Hearthstone always first)
local PRIORITY_ITEMS = {
    [6948] = 1, -- Hearthstone
}

-- Item class ordering (maps WoW item classID to sort order)
local CLASS_ORDER = {
    [0] = 2,   -- Consumable
    [1] = 12,  -- Container (Bags)
    [2] = 5,   -- Weapon
    [3] = 8,   -- Gem
    [4] = 6,   -- Armor
    [5] = 3,   -- Reagent
    [6] = 4,   -- Projectile
    [7] = 10,  -- Trade Goods
    [8] = 9,   -- Item Enhancement (not in TBC but for future)
    [9] = 11,  -- Recipe
    [10] = 16, -- Money (obsolete)
    [11] = 7,  -- Quiver
    [12] = 13, -- Quest
    [13] = 14, -- Key
    [14] = 17, -- Permanent (obsolete)
    [15] = 15, -- Miscellaneous
    [16] = 18, -- Glyph (not in TBC)
    [17] = 19, -- Battle Pet (not in TBC)
    [18] = 1,  -- WoW Token (not in TBC)
}

-- Weapon subclass ordering
local WEAPON_SUBCLASS_ORDER = {
    [0] = 1,   -- One-Handed Axes
    [1] = 10,  -- Two-Handed Axes
    [2] = 2,   -- Bows
    [3] = 13,  -- Guns
    [4] = 3,   -- One-Handed Maces
    [5] = 11,  -- Two-Handed Maces
    [6] = 12,  -- Polearms
    [7] = 4,   -- One-Handed Swords
    [8] = 14,  -- Two-Handed Swords
    [9] = 20,  -- Obsolete
    [10] = 15, -- Staves
    [11] = 20, -- One-Handed Exotics
    [12] = 20, -- Two-Handed Exotics
    [13] = 16, -- Fist Weapons
    [14] = 17, -- Miscellaneous (wands in classic)
    [15] = 5,  -- Daggers
    [16] = 18, -- Thrown
    [17] = 19, -- Spears
    [18] = 6,  -- Crossbows
    [19] = 7,  -- Wands
    [20] = 8,  -- Fishing Poles
}

-- Armor subclass ordering
local ARMOR_SUBCLASS_ORDER = {
    [0] = 10,  -- Miscellaneous
    [1] = 4,   -- Cloth
    [2] = 3,   -- Leather
    [3] = 2,   -- Mail
    [4] = 1,   -- Plate
    [5] = 11,  -- Cosmetic
    [6] = 5,   -- Shields
    [7] = 6,   -- Librams
    [8] = 7,   -- Idols
    [9] = 8,   -- Totems
    [10] = 9,  -- Sigils
}

-- Equipment slot ordering
local EQUIP_SLOT_ORDER = {
    ["INVTYPE_WEAPONMAINHAND"] = 1,
    ["INVTYPE_WEAPON"] = 2,
    ["INVTYPE_2HWEAPON"] = 3,
    ["INVTYPE_WEAPONOFFHAND"] = 4,
    ["INVTYPE_SHIELD"] = 5,
    ["INVTYPE_HOLDABLE"] = 6,
    ["INVTYPE_RANGED"] = 7,
    ["INVTYPE_RANGEDRIGHT"] = 8,
    ["INVTYPE_THROWN"] = 9,
    ["INVTYPE_HEAD"] = 10,
    ["INVTYPE_NECK"] = 11,
    ["INVTYPE_SHOULDER"] = 12,
    ["INVTYPE_CLOAK"] = 13,
    ["INVTYPE_CHEST"] = 14,
    ["INVTYPE_ROBE"] = 14,
    ["INVTYPE_BODY"] = 15,
    ["INVTYPE_TABARD"] = 16,
    ["INVTYPE_WRIST"] = 17,
    ["INVTYPE_HAND"] = 18,
    ["INVTYPE_WAIST"] = 19,
    ["INVTYPE_LEGS"] = 20,
    ["INVTYPE_FEET"] = 21,
    ["INVTYPE_FINGER"] = 22,
    ["INVTYPE_TRINKET"] = 23,
    ["INVTYPE_RELIC"] = 24,
    ["INVTYPE_BAG"] = 25,
    ["INVTYPE_QUIVER"] = 26,
    ["INVTYPE_AMMO"] = 27,
}

-- Trade Goods subclass ordering (TBC)
local TRADE_GOODS_SUBCLASS_ORDER = {
    [1] = 1,   -- Parts
    [2] = 2,   -- Explosives
    [3] = 3,   -- Devices
    [4] = 4,   -- Jewelcrafting
    [5] = 5,   -- Cloth
    [6] = 6,   -- Leather
    [7] = 7,   -- Metal & Stone
    [8] = 8,   -- Meat
    [9] = 9,   -- Herb
    [10] = 10, -- Elemental
    [11] = 11, -- Other
    [12] = 12, -- Enchanting
    [14] = 13, -- Inscription (not TBC)
}

-- Consumable subclass ordering
local CONSUMABLE_SUBCLASS_ORDER = {
    [0] = 1,   -- Consumable (generic)
    [1] = 2,   -- Potion
    [2] = 3,   -- Elixir
    [3] = 4,   -- Flask
    [4] = 5,   -- Scroll
    [5] = 6,   -- Food & Drink
    [6] = 7,   -- Item Enhancement
    [7] = 8,   -- Bandage
    [8] = 9,   -- Other
}

--===========================================================================
-- UTILITY FUNCTIONS
--===========================================================================

-- Tooltip for scanning item properties
local scanTooltip = CreateFrame("GameTooltip", "GudaBags_SortScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

function SortEngine:ClearCache()
    -- Log performance stats before clearing (if any work was done)
    if perfStats.tooltipScans > 0 or perfStats.sortKeyComputes > 0 then
        local tooltipHitRate = perfStats.tooltipScans > 0 and (perfStats.tooltipCacheHits / (perfStats.tooltipScans + perfStats.tooltipCacheHits) * 100) or 0
        local sortKeyHitRate = perfStats.sortKeyComputes > 0 and (perfStats.sortKeyCacheHits / (perfStats.sortKeyComputes + perfStats.sortKeyCacheHits) * 100) or 0
        ns:Debug(string.format("Sort cache stats - Tooltip: %d scans, %d hits (%.0f%%) | SortKeys: %d computes, %d hits (%.0f%%)",
            perfStats.tooltipScans,
            perfStats.tooltipCacheHits,
            tooltipHitRate,
            perfStats.sortKeyComputes,
            perfStats.sortKeyCacheHits,
            sortKeyHitRate
        ))
    end
    -- Clear performance caches
    wipe(specialPropertiesCache)
    wipe(sortKeyCache)
    -- Reset stats
    perfStats.tooltipScans = 0
    perfStats.tooltipCacheHits = 0
    perfStats.sortKeyComputes = 0
    perfStats.sortKeyCacheHits = 0
end

-------------------------------------------------
-- Check if item has special properties (cached by itemID)
-------------------------------------------------
local function HasSpecialProperties(bagID, slot, itemID)
    if not bagID or not slot then return false end

    -- Check cache first (keyed by itemID since properties are inherent to item)
    if itemID and specialPropertiesCache[itemID] ~= nil then
        perfStats.tooltipCacheHits = perfStats.tooltipCacheHits + 1
        return specialPropertiesCache[itemID]
    end

    perfStats.tooltipScans = perfStats.tooltipScans + 1

    scanTooltip:ClearLines()
    scanTooltip:SetBagItem(bagID, slot)

    local numLines = scanTooltip:NumLines()
    if not numLines or numLines == 0 then
        if itemID then specialPropertiesCache[itemID] = false end
        return false
    end

    local hasSpecial = false
    for i = 1, numLines do
        local line = _G["GudaBags_SortScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                local textLower = string.lower(text)
                if string.find(textLower, "use:") or string.find(textLower, "equip:") then
                    hasSpecial = true
                    break
                end
                if string.find(textLower, "^unique") or string.find(textLower, "unique%-equipped") then
                    hasSpecial = true
                    break
                end
            end

            local r, g, b = line:GetTextColor()
            if r and g and b then
                if g > 0.9 and r < 0.2 and b < 0.2 then
                    hasSpecial = true
                    break
                end
                if r > 0.9 and g > 0.7 and b < 0.2 and text and i > 1 then
                    hasSpecial = true
                    break
                end
            end
        end
    end

    -- Cache the result
    if itemID then
        specialPropertiesCache[itemID] = hasSpecial
    end

    return hasSpecial
end

-------------------------------------------------
-- Check if item is a tool
-------------------------------------------------
local function IsTool(itemType, itemSubType, itemName)
    if not itemType then return false end

    local typeLower = string.lower(itemType)
    local subLower = itemSubType and string.lower(itemSubType) or ""
    local nameLower = itemName and string.lower(itemName) or ""

    if typeLower == "tools" or typeLower == "tool" then return true end
    if string.find(subLower, "fishing") then return true end
    if string.find(subLower, "mining") then return true end
    if string.find(nameLower, "mining pick") then return true end
    if string.find(nameLower, "fishing pole") then return true end
    if string.find(nameLower, "fishing rod") then return true end
    if string.find(nameLower, "skinning knife") then return true end
    if string.find(nameLower, "blacksmith hammer") then return true end
    if string.find(nameLower, "arclight spanner") then return true end

    return false
end

-------------------------------------------------
-- Bag family utilities
-------------------------------------------------
local function GetBagFamily(bagID)
    if bagID == 0 then return 0 end
    local numFreeSlots, bagFamily = C_Container.GetContainerNumFreeSlots(bagID)
    return bagFamily or 0
end

local function CanItemGoInBag(itemID, bagFamily)
    if bagFamily == 0 then return true end
    if not itemID then return false end
    local itemFamily = C_Item.GetItemFamily(itemID)
    if not itemFamily then return false end
    return bit.band(itemFamily, bagFamily) ~= 0
end

local function GetBagTypeFromFamily(bagFamily)
    if bagFamily == 0 then return nil end
    -- Bag family values must match BagClassifier.lua
    if bit.band(bagFamily, 1) ~= 0 then return "quiver" end
    if bit.band(bagFamily, 2) ~= 0 then return "ammo" end
    if bit.band(bagFamily, 4) ~= 0 then return "soul" end
    if bit.band(bagFamily, 8) ~= 0 then return "leatherworking" end
    if bit.band(bagFamily, 16) ~= 0 then return "inscription" end
    if bit.band(bagFamily, 32) ~= 0 then return "herb" end
    if bit.band(bagFamily, 64) ~= 0 then return "enchant" end
    if bit.band(bagFamily, 128) ~= 0 then return "engineering" end
    if bit.band(bagFamily, 512) ~= 0 then return "gem" end
    if bit.band(bagFamily, 1024) ~= 0 then return "mining" end
    return "specialized"
end

local function GetItemPreferredContainer(itemID)
    if not itemID then return nil end
    local itemFamily = C_Item.GetItemFamily(itemID)
    if not itemFamily or itemFamily == 0 then return nil end
    return GetBagTypeFromFamily(itemFamily)
end

--===========================================================================
-- SORT KEY COMPUTATION
--===========================================================================

local function GetSortedClassID(classID)
    return CLASS_ORDER[classID] or 99
end

local function GetSortedSubClassID(classID, subClassID)
    if classID == 2 then -- Weapon
        return WEAPON_SUBCLASS_ORDER[subClassID] or 99
    elseif classID == 4 then -- Armor
        return ARMOR_SUBCLASS_ORDER[subClassID] or 99
    elseif classID == 7 then -- Trade Goods
        return TRADE_GOODS_SUBCLASS_ORDER[subClassID] or 99
    elseif classID == 0 then -- Consumable
        return CONSUMABLE_SUBCLASS_ORDER[subClassID] or 99
    end
    return subClassID or 99
end

local function GetEquipSlotOrder(equipLoc)
    return EQUIP_SLOT_ORDER[equipLoc] or 99
end

--===========================================================================
-- PHASE 1: Classify Bags
--===========================================================================

local function ClassifyBags(bagIDs)
    local containers = {
        soul = {}, herb = {}, enchant = {}, quiver = {}, ammo = {},
        engineering = {}, gem = {}, mining = {}, leatherworking = {}, inscription = {},
        specialized = {}, regular = {}
    }
    local bagFamilies = {}

    for _, bagID in ipairs(bagIDs) do
        local family = GetBagFamily(bagID)
        bagFamilies[bagID] = family

        local bagType = GetBagTypeFromFamily(family)
        if bagType and containers[bagType] then
            table.insert(containers[bagType], bagID)
        elseif bagType then
            table.insert(containers.specialized, bagID)
        else
            table.insert(containers.regular, bagID)
        end
    end

    return containers, bagFamilies
end

--===========================================================================
-- PHASE 2: Route Specialized Items
--===========================================================================

local function RouteSpecializedItems(bagIDs, containers, bagFamilies)
    local routingPlan = {}

    for _, bagID in ipairs(bagIDs) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
            if itemInfo and itemInfo.itemID then
                local preferredType = GetItemPreferredContainer(itemInfo.itemID)
                local currentBagType = GetBagTypeFromFamily(bagFamilies[bagID] or 0)

                if preferredType and currentBagType ~= preferredType then
                    local targetBags = containers[preferredType]
                    if targetBags and #targetBags > 0 then
                        local foundSlot = false
                        for _, targetBagID in ipairs(targetBags) do
                            if not foundSlot then
                                -- Verify item can actually go in target bag before routing
                                local targetBagFamily = bagFamilies[targetBagID] or 0
                                if CanItemGoInBag(itemInfo.itemID, targetBagFamily) then
                                    local targetSlots = C_Container.GetContainerNumSlots(targetBagID)
                                    for targetSlot = 1, targetSlots do
                                        local targetInfo = C_Container.GetContainerItemInfo(targetBagID, targetSlot)
                                        if not targetInfo then
                                            table.insert(routingPlan, {
                                                fromBag = bagID, fromSlot = slot,
                                                toBag = targetBagID, toSlot = targetSlot
                                            })
                                            foundSlot = true
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    ClearCursor()
    for _, move in ipairs(routingPlan) do
        local sourceInfo = C_Container.GetContainerItemInfo(move.fromBag, move.fromSlot)
        if sourceInfo and not sourceInfo.isLocked then
            C_Container.PickupContainerItem(move.fromBag, move.fromSlot)
            C_Container.PickupContainerItem(move.toBag, move.toSlot)
            ClearCursor()
        end
    end

    return #routingPlan
end

--===========================================================================
-- PHASE 3: Stack Consolidation
--===========================================================================

local function ConsolidateStacks(bagIDs, bagFamilies)
    local itemGroups = {}

    for _, bagID in ipairs(bagIDs) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
            if itemInfo and itemInfo.itemID then
                local groupKey = tostring(itemInfo.itemID)
                if not itemGroups[groupKey] then
                    itemGroups[groupKey] = { itemID = itemInfo.itemID, stacks = {} }
                end
                table.insert(itemGroups[groupKey].stacks, {
                    bagID = bagID, slot = slot,
                    count = tonumber(itemInfo.stackCount) or 1
                })
            end
        end
    end

    local consolidationMoves = 0
    for _, group in pairs(itemGroups) do
        if #group.stacks > 1 then
            -- GetItemInfo returns: name, link, quality, ilvl, minLevel, type, subType, stackCount, equipLoc, texture, sellPrice
            -- Can return nil if item data isn't cached
            local itemInfoResults = {GetItemInfo(group.itemID)}
            local stackSize = itemInfoResults[8]
            local maxStack = tonumber(stackSize) or 1

            if maxStack > 1 then
                table.sort(group.stacks, function(a, b)
                    return (tonumber(a.count) or 0) > (tonumber(b.count) or 0)
                end)

                for i = 1, #group.stacks do
                    local source = group.stacks[i]
                    if source.count < maxStack and source.count > 0 then
                        for j = i + 1, #group.stacks do
                            local target = group.stacks[j]
                            if target.count > 0 then
                                local spaceAvailable = maxStack - source.count
                                local amountToMove = math.min(spaceAvailable, target.count)

                                if amountToMove > 0 then
                                    local sourceInfo = C_Container.GetContainerItemInfo(source.bagID, source.slot)
                                    local targetInfo = C_Container.GetContainerItemInfo(target.bagID, target.slot)

                                    if sourceInfo and targetInfo and not sourceInfo.isLocked and not targetInfo.isLocked then
                                        if amountToMove < target.count then
                                            C_Container.SplitContainerItem(target.bagID, target.slot, amountToMove)
                                            C_Container.PickupContainerItem(source.bagID, source.slot)
                                        else
                                            C_Container.PickupContainerItem(target.bagID, target.slot)
                                            C_Container.PickupContainerItem(source.bagID, source.slot)
                                        end
                                        ClearCursor()

                                        source.count = source.count + amountToMove
                                        target.count = target.count - amountToMove
                                        consolidationMoves = consolidationMoves + 1

                                        if source.count >= maxStack then break end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return consolidationMoves
end

--===========================================================================
-- PHASE 4: Collect and Sort Items
--===========================================================================

local function CollectItems(bagIDs)
    local items = {}
    local sequence = 0

    for _, bagID in ipairs(bagIDs) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
            if itemInfo then
                local itemLink = itemInfo.hyperlink
                local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType, _, itemEquipLoc, _, _, classID, subClassID = GetItemInfo(itemLink)
                -- GetItemInfo can return nil if item data isn't cached yet
                itemName = itemName or ""
                itemQuality = itemQuality or itemInfo.quality or 0
                itemLevel = itemLevel or 0
                itemType = itemType or "Miscellaneous"
                itemSubType = itemSubType or ""
                itemEquipLoc = itemEquipLoc or ""
                classID = classID or 15
                subClassID = subClassID or 0

                sequence = sequence + 1
                table.insert(items, {
                    bagID = bagID,
                    slot = slot,
                    sequence = sequence,
                    itemID = itemInfo.itemID,
                    itemLink = itemLink,
                    itemName = itemName,
                    quality = tonumber(itemQuality) or 0,
                    itemLevel = tonumber(itemLevel) or 0,
                    itemType = itemType,
                    itemSubType = itemSubType,
                    equipLoc = itemEquipLoc,
                    stackCount = tonumber(itemInfo.stackCount) or 1,
                    isLocked = itemInfo.isLocked,
                    itemFamily = C_Item.GetItemFamily(itemInfo.itemID) or 0,
                    classID = classID,
                    subClassID = subClassID,
                })
            end
        end
    end

    return items
end

local function AddSortKeys(items)
    -- Check if white items should be treated as junk (setting) - read once
    local whiteItemsJunk = Database:GetSetting("whiteItemsJunk") or false

    for _, item in ipairs(items) do
        local itemID = item.itemID

        -- Check if we have cached sort keys for this itemID
        local cached = sortKeyCache[itemID]
        if cached then
            perfStats.sortKeyCacheHits = perfStats.sortKeyCacheHits + 1
            -- Reuse cached sort keys
            item.priority = cached.priority
            item.sortedClassID = cached.sortedClassID
            item.sortedSubClassID = cached.sortedSubClassID
            item.sortedEquipSlot = cached.sortedEquipSlot
            item.isEquippable = cached.isEquippable
            item.isJunk = cached.isJunk
            item.invertedQuality = cached.invertedQuality
            item.invertedItemLevel = cached.invertedItemLevel
            item.invertedItemID = cached.invertedItemID
            -- Note: invertedCount is stack-specific, compute fresh
            item.invertedCount = -item.stackCount
        else
            perfStats.sortKeyComputes = perfStats.sortKeyComputes + 1
            -- Compute sort keys fresh
            -- Priority (hearthstone always first)
            item.priority = PRIORITY_ITEMS[itemID] or 1000

            -- Sorted class and subclass IDs
            item.sortedClassID = GetSortedClassID(item.classID)
            item.sortedSubClassID = GetSortedSubClassID(item.classID, item.subClassID)
            item.sortedEquipSlot = GetEquipSlotOrder(item.equipLoc)

            -- Check if equippable
            local isEquippable = (item.classID == 2 or item.classID == 4) and
                                item.equipLoc ~= "" and item.equipLoc ~= "INVTYPE_BAG"
            item.isEquippable = isEquippable

            -- Check for tools and special properties (cached by itemID)
            local isTool = IsTool(item.itemType, item.itemSubType, item.itemName)
            local hasSpecial = HasSpecialProperties(item.bagID, item.slot, itemID)

            -- Junk detection
            local isGrayItem = item.quality == 0
            local isWhiteEquip = (item.quality == 1) and isEquippable
            local shouldBeJunk = false

            -- Check if this equip slot is valuable (never junk)
            local isValuableSlot = Constants.VALUABLE_EQUIP_SLOTS and Constants.VALUABLE_EQUIP_SLOTS[item.equipLoc]

            if isGrayItem then
                shouldBeJunk = not hasSpecial
            elseif isWhiteEquip and whiteItemsJunk then
                -- Only treat white equippable as junk if setting is enabled
                -- Valuable slots (trinket, ring, neck, shirt, tabard) are never junk
                if isValuableSlot then
                    shouldBeJunk = false
                else
                    shouldBeJunk = not isTool and not hasSpecial
                end
            end

            item.isJunk = shouldBeJunk

            -- Override class for junk items (sort to end)
            if shouldBeJunk then
                item.sortedClassID = 100
            end

            -- Inverted values for descending sorts
            item.invertedQuality = -item.quality
            item.invertedItemLevel = -item.itemLevel
            item.invertedCount = -item.stackCount
            item.invertedItemID = -itemID

            -- Cache the computed sort keys for this itemID
            sortKeyCache[itemID] = {
                priority = item.priority,
                sortedClassID = item.sortedClassID,
                sortedSubClassID = item.sortedSubClassID,
                sortedEquipSlot = item.sortedEquipSlot,
                isEquippable = item.isEquippable,
                isJunk = item.isJunk,
                invertedQuality = item.invertedQuality,
                invertedItemLevel = item.invertedItemLevel,
                invertedItemID = item.invertedItemID,
            }
        end
    end
end

local function SortItems(items)
    AddSortKeys(items)

    local reverseStackSort = Database:GetSetting("reverseStackSort")
    local rightToLeft = Database:GetSetting("sortRightToLeft")

    -- Sort order: priority, class, equip slot, subclass, item level, quality, name, itemID, count

    table.sort(items, function(a, b)
        -- 1. Priority items (hearthstone)
        if a.priority ~= b.priority then
            if rightToLeft then
                return a.priority > b.priority
            else
                return a.priority < b.priority
            end
        end

        -- 2. Item class (consumables, weapons, armor, etc.)
        if a.sortedClassID ~= b.sortedClassID then
            return a.sortedClassID < b.sortedClassID
        end

        -- 3. Equipment slot (for armor/weapons)
        if a.isEquippable and b.isEquippable then
            if a.sortedEquipSlot ~= b.sortedEquipSlot then
                return a.sortedEquipSlot < b.sortedEquipSlot
            end
        end

        -- 4. Subclass (weapon type, armor type, trade goods type)
        if a.sortedSubClassID ~= b.sortedSubClassID then
            return a.sortedSubClassID < b.sortedSubClassID
        end

        -- 5. Item level (higher first)
        if a.invertedItemLevel ~= b.invertedItemLevel then
            return a.invertedItemLevel < b.invertedItemLevel
        end

        -- 6. Quality (higher first)
        if a.invertedQuality ~= b.invertedQuality then
            return a.invertedQuality < b.invertedQuality
        end

        -- 7. Name (alphabetically)
        if a.itemName ~= b.itemName then
            return a.itemName < b.itemName
        end

        -- 8. Item ID (for stability)
        if a.invertedItemID ~= b.invertedItemID then
            return a.invertedItemID < b.invertedItemID
        end

        -- 9. Stack count
        if a.invertedCount ~= b.invertedCount then
            if reverseStackSort then
                return a.stackCount < b.stackCount
            else
                return a.invertedCount < b.invertedCount
            end
        end

        -- 10. Preserve original order (reverse for right-to-left to match target slot direction)
        if rightToLeft then
            return a.sequence > b.sequence
        else
            return a.sequence < b.sequence
        end
    end)

    return items
end

--===========================================================================
-- PHASE 5: Build Target Positions and Apply Sort
--===========================================================================

local function BuildTargetPositions(bagIDs, itemCount)
    local positions = {}
    local index = 1
    local rightToLeft = Database:GetSetting("sortRightToLeft")

    local bagOrder = {}
    for _, bagID in ipairs(bagIDs) do
        table.insert(bagOrder, bagID)
    end

    if rightToLeft then
        local reversed = {}
        for i = #bagOrder, 1, -1 do
            table.insert(reversed, bagOrder[i])
        end
        bagOrder = reversed
    end

    for _, bagID in ipairs(bagOrder) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)

        if rightToLeft then
            for slot = numSlots, 1, -1 do
                if index <= itemCount then
                    positions[index] = { bagID = bagID, slot = slot }
                    index = index + 1
                end
            end
        else
            for slot = 1, numSlots do
                if index <= itemCount then
                    positions[index] = { bagID = bagID, slot = slot }
                    index = index + 1
                end
            end
        end
    end

    return positions
end

local function BuildTailPositions(bagIDs, junkCount)
    local positions = {}
    if junkCount <= 0 then return positions end

    local rightToLeft = Database:GetSetting("sortRightToLeft")

    local bagOrder = {}
    for _, bagID in ipairs(bagIDs) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        if numSlots > 0 then
            table.insert(bagOrder, { bagID = bagID, numSlots = numSlots })
        end
    end

    local tailSlots = {}

    if rightToLeft then
        for i = 1, #bagOrder do
            local info = bagOrder[i]
            for slot = 1, info.numSlots do
                if #tailSlots < junkCount then
                    table.insert(tailSlots, { bagID = info.bagID, slot = slot })
                else
                    break
                end
            end
            if #tailSlots >= junkCount then break end
        end
    else
        for i = #bagOrder, 1, -1 do
            local info = bagOrder[i]
            for slot = info.numSlots, 1, -1 do
                if #tailSlots < junkCount then
                    table.insert(tailSlots, { bagID = info.bagID, slot = slot })
                else
                    break
                end
            end
            if #tailSlots >= junkCount then break end
        end
    end

    table.sort(tailSlots, function(a, b)
        if a.bagID ~= b.bagID then return a.bagID < b.bagID end
        return a.slot < b.slot
    end)

    return tailSlots
end

local function SplitJunkItems(items)
    local nonJunk, junk = {}, {}
    for _, item in ipairs(items) do
        if item.isJunk then
            table.insert(junk, item)
        else
            table.insert(nonJunk, item)
        end
    end
    return nonJunk, junk
end

local function ApplySort(items, targetPositions, bagFamilies)
    ClearCursor()

    local moveToEmpty = {}
    local swapOccupied = {}

    for i, item in ipairs(items) do
        local target = targetPositions[i]
        if target then
            local targetFamily = bagFamilies[target.bagID] or 0
            local canGoInBag = (targetFamily == 0) or CanItemGoInBag(item.itemID, targetFamily)

            if canGoInBag and (item.bagID ~= target.bagID or item.slot ~= target.slot) then
                local targetInfo = C_Container.GetContainerItemInfo(target.bagID, target.slot)
                if not targetInfo then
                    table.insert(moveToEmpty, {
                        sourceBag = item.bagID, sourceSlot = item.slot,
                        targetBag = target.bagID, targetSlot = target.slot,
                    })
                else
                    local sourceFamily = bagFamilies[item.bagID] or 0
                    local targetCanGoInSource = (sourceFamily == 0) or CanItemGoInBag(targetInfo.itemID, sourceFamily)

                    if targetCanGoInSource then
                        table.insert(swapOccupied, {
                            sourceBag = item.bagID, sourceSlot = item.slot,
                            targetBag = target.bagID, targetSlot = target.slot,
                        })
                    end
                end
            end
        end
    end

    local moveCount = 0

    for _, move in ipairs(moveToEmpty) do
        local sourceInfo = C_Container.GetContainerItemInfo(move.sourceBag, move.sourceSlot)
        if sourceInfo and not sourceInfo.isLocked then
            C_Container.PickupContainerItem(move.sourceBag, move.sourceSlot)
            C_Container.PickupContainerItem(move.targetBag, move.targetSlot)
            ClearCursor()
            moveCount = moveCount + 1
            if not soundsMuted then
                MutePickupSounds()
                soundsMuted = true
            end
        end
    end

    for _, move in ipairs(swapOccupied) do
        local sourceInfo = C_Container.GetContainerItemInfo(move.sourceBag, move.sourceSlot)
        local targetInfo = C_Container.GetContainerItemInfo(move.targetBag, move.targetSlot)

        if sourceInfo and targetInfo and not sourceInfo.isLocked and not targetInfo.isLocked then
            C_Container.PickupContainerItem(move.sourceBag, move.sourceSlot)
            C_Container.PickupContainerItem(move.targetBag, move.targetSlot)
            ClearCursor()
            moveCount = moveCount + 1
            if not soundsMuted then
                MutePickupSounds()
                soundsMuted = true
            end
        end
    end

    return moveCount
end

--===========================================================================
-- PHASE 6: Verify Sort Completeness
--===========================================================================

-- Check how many items are out of position (without moving them)
local function CountOutOfPlaceItems(bagIDs)
    local containers, bagFamilies = ClassifyBags(bagIDs)
    local outOfPlace = 0

    -- Check regular bags
    local regularBags = containers.regular
    if #regularBags > 0 then
        local allItems = CollectItems(regularBags)
        if #allItems > 0 then
            allItems = SortItems(allItems)
            local nonJunk, junk = SplitJunkItems(allItems)

            -- Check non-junk items against front positions
            if #nonJunk > 0 then
                local frontPositions = BuildTargetPositions(regularBags, #nonJunk)
                for i, item in ipairs(nonJunk) do
                    local target = frontPositions[i]
                    if target and (item.bagID ~= target.bagID or item.slot ~= target.slot) then
                        outOfPlace = outOfPlace + 1
                    end
                end
            end
        end
    end

    return outOfPlace
end

--===========================================================================
-- PHASE 7: Execute Sort Pass
--===========================================================================

local function ExecuteSortPass(bagIDs)
    local containers, bagFamilies = ClassifyBags(bagIDs)
    local totalMoves = 0

    -- Phase 2: Route specialized items
    totalMoves = totalMoves + RouteSpecializedItems(bagIDs, containers, bagFamilies)

    -- Phase 3: Consolidate stacks
    totalMoves = totalMoves + ConsolidateStacks(bagIDs, bagFamilies)

    -- Phase 4: Sort specialized bags
    local specializedTypes = {"soul", "herb", "enchant", "quiver", "ammo", "engineering", "gem", "mining", "leatherworking", "inscription"}
    for _, bagType in ipairs(specializedTypes) do
        local specialBags = containers[bagType]
        if specialBags then
            for _, bagID in ipairs(specialBags) do
                local items = CollectItems({bagID})
                if #items > 0 then
                    items = SortItems(items)
                    local targets = BuildTargetPositions({bagID}, #items)
                    totalMoves = totalMoves + ApplySort(items, targets, bagFamilies)
                end
            end
        end
    end

    -- Phase 5: Sort regular bags (two-pass: non-junk forward, junk backward)
    local regularBags = containers.regular
    if #regularBags > 0 then
        local allItems = CollectItems(regularBags)
        if #allItems > 0 then
            allItems = SortItems(allItems)
            local nonJunk, junk = SplitJunkItems(allItems)

            if #nonJunk > 0 then
                local frontPositions = BuildTargetPositions(regularBags, #nonJunk)
                totalMoves = totalMoves + ApplySort(nonJunk, frontPositions, bagFamilies)
            end

            if #junk > 0 then
                local afterItems = CollectItems(regularBags)
                afterItems = SortItems(afterItems)
                local _, junkNow = SplitJunkItems(afterItems)

                if #junkNow > 0 then
                    local tailPositions = BuildTailPositions(regularBags, #junkNow)
                    totalMoves = totalMoves + ApplySort(junkNow, tailPositions, bagFamilies)
                end
            end
        end
    end

    return totalMoves
end

--===========================================================================
-- MAIN SORT FUNCTIONS
--===========================================================================

local sortFrame = CreateFrame("Frame")
local sortStartTime = 0
local nextPassTime = 0
local noProgressCount = 0
local sortTimeout = 30

local activeBagIDs = Constants.BAG_IDS

local function AnyItemsLocked()
    for _, bagID in ipairs(activeBagIDs) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
            if itemInfo and itemInfo.isLocked then
                return true
            end
        end
    end
    return false
end

sortFrame:SetScript("OnUpdate", function(self, elapsed)
    if not sortInProgress then return end

    local now = GetTime()
    local isBankSort = (activeBagIDs == Constants.BANK_BAG_IDS)

    -- Bank operations are server-side and need longer delays
    local lockWaitTime = isBankSort and 0.3 or 0.1
    local passDelay = isBankSort and 0.8 or 0.5

    if now - sortStartTime > sortTimeout then
        sortInProgress = false
        soundsMuted = false
        activeBagIDs = Constants.BAG_IDS
        UnmutePickupSounds()
        SortEngine:ClearCache()
        ns:Print("Sort timed out")
        if isBankSort and ns.OnBankUpdated then
            ns.OnBankUpdated()
        else
            Events:Fire("BAGS_UPDATED")
        end
        return
    end

    if now < nextPassTime then return end

    if AnyItemsLocked() then
        nextPassTime = now + lockWaitTime
        return
    end

    currentPass = currentPass + 1

    local passStart = debugprofilestop()
    local success, result = pcall(ExecuteSortPass, activeBagIDs)
    local passTime = debugprofilestop() - passStart

    ns:Debug(string.format("Sort pass %d: %.2fms, %d moves", currentPass, passTime / 1000, result or 0))

    local moveCount = 0
    if not success then
        local isBankSort = (activeBagIDs == Constants.BANK_BAG_IDS)
        sortInProgress = false
        soundsMuted = false
        activeBagIDs = Constants.BAG_IDS
        UnmutePickupSounds()
        SortEngine:ClearCache()
        ns:Print("Sort error: " .. tostring(result))
        if isBankSort and ns.OnBankUpdated then
            ns.OnBankUpdated()
        else
            Events:Fire("BAGS_UPDATED")
        end
        return
    else
        moveCount = result or 0
    end

    if moveCount == 0 then
        noProgressCount = noProgressCount + 1
    else
        noProgressCount = 0
    end

    -- Stop when: no progress for 3 passes, OR maxPasses reached with no moves on last pass
    if noProgressCount >= 3 or (currentPass >= maxPasses and moveCount == 0) then
        -- Verify sort is complete
        local outOfPlace = CountOutOfPlaceItems(activeBagIDs)
        if outOfPlace > 0 and currentPass < maxPasses then
            -- Items still out of place, continue sorting
            ns:Debug(string.format("Sort incomplete: %d items out of place, continuing...", outOfPlace))
            noProgressCount = 0  -- Reset to allow more passes
            nextPassTime = now + passDelay
            return
        end

        if outOfPlace > 0 then
            ns:Debug(string.format("Sort finished with %d items still out of place (may need another sort)", outOfPlace))
        end

        sortInProgress = false
        soundsMuted = false
        activeBagIDs = Constants.BAG_IDS
        UnmutePickupSounds()
        SortEngine:ClearCache()
        if isBankSort and ns.OnBankUpdated then
            ns.OnBankUpdated()
        else
            Events:Fire("BAGS_UPDATED")
        end
        return
    end

    nextPassTime = now + passDelay
end)

-------------------------------------------------
-- Public API
-------------------------------------------------
function SortEngine:SortBags()
    if sortInProgress then
        ns:Print("Sort already in progress...")
        return false
    end

    activeBagIDs = Constants.BAG_IDS
    self:ClearCache()
    soundsMuted = false
    sortInProgress = true
    currentPass = 0
    noProgressCount = 0
    sortStartTime = GetTime()
    nextPassTime = GetTime()

    return true
end

function SortEngine:IsSorting()
    return sortInProgress
end

function SortEngine:CancelSort()
    if sortInProgress then
        UnmutePickupSounds()
    end
    sortInProgress = false
    soundsMuted = false
    currentPass = 0
    noProgressCount = 0
    activeBagIDs = Constants.BAG_IDS
    self:ClearCache()
end

function SortEngine:SortBank()
    local BankScanner = ns:GetModule("BankScanner")
    if not BankScanner or not BankScanner:IsBankOpen() then
        ns:Print("Cannot sort bank: not at banker")
        return false
    end

    if sortInProgress then
        ns:Print("Sort already in progress...")
        return false
    end

    activeBagIDs = Constants.BANK_BAG_IDS
    self:ClearCache()
    soundsMuted = false
    sortInProgress = true
    currentPass = 0
    noProgressCount = 0
    sortStartTime = GetTime()
    nextPassTime = GetTime()

    return true
end

-------------------------------------------------
-- Restack Only (for Category View)
-- Consolidates stacks without sorting positions
-------------------------------------------------
local restackInProgress = false
local restackBagIDs = nil
local restackCallback = nil
local restackPassCount = 0
local restackMaxPasses = 4
local restackNextPassTime = 0

local restackFrame = CreateFrame("Frame")
restackFrame:SetScript("OnUpdate", function(self, elapsed)
    if not restackInProgress then return end

    local now = GetTime()
    local isBankRestack = (restackBagIDs == Constants.BANK_BAG_IDS)

    -- Bank operations are server-side and need longer delays
    local lockWaitTime = isBankRestack and 0.3 or 0.1

    if now < restackNextPassTime then return end

    -- Check if any items are locked
    for _, bagID in ipairs(restackBagIDs) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
            if itemInfo and itemInfo.isLocked then
                restackNextPassTime = now + lockWaitTime
                return -- Wait for items to unlock
            end
        end
    end

    restackPassCount = restackPassCount + 1

    local _, bagFamilies = ClassifyBags(restackBagIDs)
    local moves = ConsolidateStacks(restackBagIDs, bagFamilies)

    if moves == 0 or restackPassCount >= restackMaxPasses then
        -- Done restacking
        restackInProgress = false
        UnmutePickupSounds()
        if restackCallback then
            restackCallback()
        end
    end
end)

function SortEngine:RestackBags(callback)
    if sortInProgress or restackInProgress then
        return false
    end

    restackInProgress = true
    restackBagIDs = Constants.BAG_IDS
    restackCallback = callback
    restackPassCount = 0
    restackNextPassTime = 0

    MutePickupSounds()
    return true
end

function SortEngine:RestackBank(callback)
    local BankScanner = ns:GetModule("BankScanner")
    if not BankScanner or not BankScanner:IsBankOpen() then
        return false
    end

    if sortInProgress or restackInProgress then
        return false
    end

    restackInProgress = true
    restackBagIDs = Constants.BANK_BAG_IDS
    restackCallback = callback
    restackPassCount = 0
    restackNextPassTime = 0

    MutePickupSounds()
    return true
end

function SortEngine:IsRestacking()
    return restackInProgress
end
