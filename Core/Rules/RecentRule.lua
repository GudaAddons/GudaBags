local addonName, ns = ...

local RuleEngine = ns:GetModule("RuleEngine")
local Database = ns:GetModule("Database")

-------------------------------------------------
-- Recent Items Tracking
-------------------------------------------------

-- Storage for recent items: { [itemID] = timestamp }
-- This is stored in character DB and persists across sessions
local recentItems = nil  -- Lazy loaded from DB

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

    -- Don't mark as recent if item has a manual category override
    local CategoryManager = ns:GetModule("CategoryManager")
    if CategoryManager then
        local categories = CategoryManager:GetCategories()
        if categories.itemOverrides and categories.itemOverrides[itemID] then
            return  -- Item was manually assigned, don't mark as recent
        end
    end

    local items = GetRecentItems()
    items[itemID] = time()
    SaveRecentItems()

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
    end
end

-- Clean up expired recent items
local function CleanupExpiredItems()
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

        -- Trigger refresh
        local Events = ns:GetModule("Events")
        if Events then
            Events:Fire("CATEGORIES_UPDATED")
        end
    end
end

-------------------------------------------------
-- Register Rule Evaluator
-------------------------------------------------

RuleEngine:RegisterEvaluator("isRecent", function(ruleValue, itemData, context)
    -- Can't track recent for other characters
    if context.isOtherChar then
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

function RecentItems:Cleanup()
    CleanupExpiredItems()
end

function RecentItems:GetAll()
    return GetRecentItems()
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
local function OnLootReceived(event, msg)
    if not msg then return end

    -- Parse the loot message for item link
    -- Format: "You receive loot: [Item Name]" or "You receive item: [Item Name]"
    local itemLink = msg:match("|c%x+|Hitem:[^|]+|h%[.-%]|h|r")
    if not itemLink then return end

    local itemID = GetItemIDFromLink(itemLink)
    if itemID then
        MarkItemRecent(itemID)
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
        -- Do initial cleanup
        C_Timer.After(1, CleanupExpiredItems)
    end, RecentItems)
end
