local addonName, ns = ...

local RuleEngine = ns:GetModule("RuleEngine")
local Database = ns:GetModule("Database")

-------------------------------------------------
-- Recent Items Tracking
-------------------------------------------------

-- Storage for recent items: { [itemID] = timestamp }
-- This is stored in character DB and persists across sessions
local recentItems = nil  -- Lazy loaded from DB

local JUNK_RULE = { type = "isJunk", value = true }

-- Flag to indicate Recent items were removed (for triggering full refresh)
local recentItemsRemoved = false

-- Set whenever the Recent set changes, cleared by the bag scanner's drain.
--
-- Marking an item Recent moves it to another category without touching a single
-- bag slot, so BagScanner's per-slot diff reports no change and the drain's
-- verify-pass suppression skips the notify -- the layout then keeps the item in
-- its old category until something else happens to redraw. Out of combat that is
-- quickly hidden by the next bag event; with the bags pinned open in combat there
-- IS nothing else, so the item sat in the wrong category until the fight ended.
--
-- Separate from recentItemsRemoved above: that one is consumed by BagFrame's
-- incremental pass, and sharing it would let either consumer eat the other's flag.
local recentSetChanged = false

local function GetRecentItems()
    if recentItems == nil then
        -- Load from character DB
        if GudaBags_CharDB then
            GudaBags_CharDB.recentItems = GudaBags_CharDB.recentItems or {}
            recentItems = GudaBags_CharDB.recentItems
        else
            recentItems = {}
        end
    end
    return recentItems
end

local function SaveRecentItems()
    if GudaBags_CharDB then
        GudaBags_CharDB.recentItems = recentItems
    end
end

local function FindItemSlot(itemID)
    local BagScanner = ns:GetModule("BagScanner")
    if not BagScanner then return nil end
    local bags = BagScanner:GetCachedBags()
    if not bags then return nil end
    for bagID, bagData in pairs(bags) do
        if bagData.slots then
            for slot, itemData in pairs(bagData.slots) do
                if itemData and itemData.itemID == itemID then
                    return itemData, bagID, slot
                end
            end
        end
    end
    return nil
end

local function IsItemCurrentlyJunk(itemID)
    local itemData, bagID, slot = FindItemSlot(itemID)
    if not itemData then return false end
    local context = RuleEngine:BuildContext(bagID, slot, false)
    return RuleEngine:Evaluate(JUNK_RULE, itemData, context)
end

-- Get the recent duration from the Recent category rule (in seconds)
-- Falls back to 5 minutes if not configured
local function GetRecentDuration()
    local CategoryManager = ns:GetModule("CategoryManager")
    if CategoryManager then
        local recentCat = CategoryManager:GetCategory("Recent")
        if recentCat and recentCat.rules then
            for _, rule in ipairs(recentCat.rules) do
                if rule.type == "isRecent" and type(rule.value) == "number" then
                    return rule.value * 60  -- Convert minutes to seconds
                end
            end
        end
    end
    -- Fallback to 5 minutes
    return 5 * 60
end

-- Check if an item is recent (acquired within the duration)
-- durationMinutes parameter allows rule to pass specific duration
local function IsItemRecent(itemID, durationMinutes)
    if not itemID then return false end

    local duration
    if durationMinutes and type(durationMinutes) == "number" then
        duration = durationMinutes * 60  -- Convert minutes to seconds
    else
        duration = GetRecentDuration()
    end

    local items = GetRecentItems()
    local timestamp = items[itemID]
    if not timestamp then return false end

    local now = time()
    local age = now - timestamp

    if age > duration then
        -- Item is no longer recent, remove it
        items[itemID] = nil
        SaveRecentItems()
        return false
    end

    return true
end

-- Mark an item as recently acquired
local function MarkItemRecent(itemID)
    if not itemID then return end

    -- Soul Shards should never appear in Recent
    if itemID == 6265 then return end

    -- Don't mark as recent if item has a manual category override
    local CategoryManager = ns:GetModule("CategoryManager")
    if CategoryManager then
        local categories = CategoryManager:GetCategories()
        if categories.itemOverrides and categories.itemOverrides[itemID] then
            ns:Debug("Recent: skip", itemID, "- manual category override")
            return  -- Item was manually assigned, don't mark as recent
        end
    end

    if IsItemCurrentlyJunk(itemID) then
        ns:Debug("Recent: skip", itemID, "- evaluates as junk")
        return
    end

    ns:Debug("Recent: marked", itemID, "inCombat", InCombatLockdown() and "yes" or "no")

    local items = GetRecentItems()
    items[itemID] = time()
    SaveRecentItems()
    recentSetChanged = true

    -- Invalidate category cache so item moves to Recent
    if CategoryManager then
        CategoryManager:ClearCategoryCache()
    end
end

-- Remove an item from recent (e.g., when manually moved to another category)
local function RemoveItemFromRecent(itemID)
    if not itemID then return end

    local items = GetRecentItems()
    if items[itemID] then
        items[itemID] = nil
        SaveRecentItems()

        -- Set flag to trigger full refresh in BagFrame
        recentItemsRemoved = true
        recentSetChanged = true

        -- Invalidate category cache so item moves to proper category
        local CategoryManager = ns:GetModule("CategoryManager")
        if CategoryManager then
            CategoryManager:ClearCategoryCache()
        end
    end
end

-- Clean up expired recent items
-- Returns true if any items were removed
local function CleanupExpiredItems(skipEvent)
    local duration = GetRecentDuration()
    local items = GetRecentItems()
    local now = time()
    local changed = false

    for itemID, timestamp in pairs(items) do
        if (now - timestamp) > duration then
            items[itemID] = nil
            changed = true
        end
    end

    if changed then
        SaveRecentItems()

        -- Invalidate category cache so items move to their proper categories
        local CategoryManager = ns:GetModule("CategoryManager")
        if CategoryManager then
            CategoryManager:ClearCategoryCache()
        end

        -- Trigger refresh (unless caller will handle it)
        if not skipEvent then
            local Events = ns:GetModule("Events")
            if Events then
                Events:Fire("CATEGORIES_UPDATED")
            end
        end
    end

    return changed
end

-------------------------------------------------
-- Register Rule Evaluator
-------------------------------------------------

RuleEngine:RegisterEvaluator("isRecent", function(ruleValue, itemData, context)
    -- Can't track recent for other characters
    if context.isOtherChar then
        return false
    end

    if itemData and itemData.itemID
       and RuleEngine:Evaluate(JUNK_RULE, itemData, context) then
        local items = GetRecentItems()
        if items[itemData.itemID] then
            items[itemData.itemID] = nil
            SaveRecentItems()
        end
        return false
    end

    -- ruleValue is the duration in minutes (number) or true for legacy
    local durationMinutes = nil
    if type(ruleValue) == "number" then
        durationMinutes = ruleValue
    end

    return IsItemRecent(itemData.itemID, durationMinutes)
end)

-------------------------------------------------
-- Public API (exported via ns)
-------------------------------------------------

local RecentItems = {}
ns:RegisterModule("RecentItems", RecentItems)

function RecentItems:MarkRecent(itemID)
    MarkItemRecent(itemID)
end

function RecentItems:RemoveRecent(itemID)
    RemoveItemFromRecent(itemID)
end

function RecentItems:IsRecent(itemID)
    return IsItemRecent(itemID)
end

function RecentItems:Cleanup(skipEvent)
    return CleanupExpiredItems(skipEvent)
end

-- Remove Recent items that are no longer in bags
-- Returns true if any items were removed
function RecentItems:CleanupStale()
    local BagScanner = ns:GetModule("BagScanner")
    if not BagScanner then return false end

    local bags = BagScanner:GetCachedBags()
    if not bags then return false end

    -- Build set of itemIDs currently in bags
    local itemsInBags = {}
    for bagID, bagData in pairs(bags) do
        if bagData.slots then
            for slot, itemData in pairs(bagData.slots) do
                if itemData and itemData.itemID then
                    itemsInBags[itemData.itemID] = true
                end
            end
        end
    end

    -- Remove Recent items not in bags
    local items = GetRecentItems()
    local changed = false
    for itemID in pairs(items) do
        if not itemsInBags[itemID] then
            items[itemID] = nil
            changed = true
        end
    end

    if changed then
        SaveRecentItems()
        local CategoryManager = ns:GetModule("CategoryManager")
        if CategoryManager then
            CategoryManager:ClearCategoryCache()
        end
    end

    return changed
end

function RecentItems:GetAll()
    return GetRecentItems()
end

-- Check if Recent items were removed (and clear the flag)
function RecentItems:WasItemRemoved()
    local removed = recentItemsRemoved
    recentItemsRemoved = false
    return removed
end

-- Has the Recent set changed since the last time anyone asked? Clears the flag.
--
-- BagScanner's drain calls this so a Recent mark counts as a reason to notify the
-- UI: the mark re-categorises an item without changing any slot, which the per-slot
-- diff cannot see. CleanupExpiredItems deliberately does not set the flag -- it
-- fires CATEGORIES_UPDATED and so already redraws on its own.
function RecentItems:ConsumeSetChanged()
    local changed = recentSetChanged
    recentSetChanged = false
    return changed
end

-------------------------------------------------
-- Loot Detection (only track actually looted items)
-------------------------------------------------

-- Parse item link to get itemID
local function GetItemIDFromLink(itemLink)
    if not itemLink then return nil end
    local itemID = itemLink:match("item:(%d+)")
    return itemID and tonumber(itemID)
end

-- Handle loot event - mark looted items as recent
local function OnLootReceived(event, msg, ...)
    if not msg then return end

    -- Detaint: CHAT_MSG_LOOT msg can be a tainted secret string
    -- Use string.find/match (not method syntax) with pcall to handle tainted values
    local ok, itemID = pcall(function()
        -- Only process actual loot messages, not created/conjured items
        if not (string.find(msg, "^You receive") or string.find(msg, "^You won")) then return nil end
        return string.match(msg, "|Hitem:(%d+)")
    end)

    if ok and itemID then
        MarkItemRecent(tonumber(itemID))
    else
        -- Two very different failures share this branch, so name which one: a
        -- tainted/erroring msg (ok == false), or a message the prefix test rejected.
        -- That test is English-only ("^You receive" / "^You won"), so on any other
        -- client every loot lands here and nothing is ever marked Recent.
        ns:Debug("Recent: CHAT_MSG_LOOT not marked -", ok and "no prefix/link match" or "pcall failed")
    end
end

-------------------------------------------------
-- Periodic Cleanup Timer
-------------------------------------------------

local cleanupTimer = nil

local function StartCleanupTimer()
    if cleanupTimer then return end

    -- Check for expired items every 30 seconds
    cleanupTimer = C_Timer.NewTicker(30, function()
        CleanupExpiredItems()
    end)
end

-- Create event frame for loot tracking
local lootFrame = CreateFrame("Frame")
lootFrame:RegisterEvent("CHAT_MSG_LOOT")
lootFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_LOOT" then
        OnLootReceived(event, ...)
    end
end)

-- Start timer when player logs in
local Events = ns:GetModule("Events")
if Events then
    Events:OnPlayerLogin(function()
        StartCleanupTimer()
        -- Remove Soul Shards from recent if already tracked
        local items = GetRecentItems()
        if items[6265] then
            items[6265] = nil
            SaveRecentItems()
        end
        -- Do initial cleanup
        C_Timer.After(1, CleanupExpiredItems)
    end, RecentItems)
end
