local addonName, ns = ...

local BagScanner = {}
ns:RegisterModule("BagScanner", BagScanner)

local Constants = ns.Constants
local Database = ns:GetModule("Database")
local Events = ns:GetModule("Events")
local ItemScanner = ns:GetModule("ItemScanner")

local cachedBags = {}

-- Track all itemIDs currently in bags (for detecting truly new items)
local knownItemIDs = {}  -- { [itemID] = count }

-- Event batching: collect dirty bags and process after delay
local dirtyBags = {}           -- Set of bagIDs that need scanning
-- Bags touched since the last BAG_UPDATE_DELAYED. Separate from dirtyBags, which
-- ProcessBatchedUpdates empties on the very next frame -- this one has to survive
-- until the server says the batch has settled.
local recentlyUpdatedBags = {}
local pendingUpdate = false    -- True when OnUpdate is scheduled
local saveTimer = nil          -- Timer handle for deferred database save
local SAVE_DELAY = 1.0         -- Seconds to wait before saving to database

-- Create frame for OnUpdate batching
local updateFrame = CreateFrame("Frame")
updateFrame:Hide()

function BagScanner:ScanAllBags()
    ns:ProfileStart("ScanAllBags")
    local allBags = {}

    for _, bagID in ipairs(Constants.BAG_IDS) do
        local bagData = ItemScanner:ScanContainer(bagID)
        if bagData then
            allBags[bagID] = bagData
        end
    end

    -- Also scan keyring (TBC only)
    if Constants.KEYRING_BAG_ID then
        local keyringData = ItemScanner:ScanContainer(Constants.KEYRING_BAG_ID)
        if keyringData then
            allBags[Constants.KEYRING_BAG_ID] = keyringData
        end
    end

    cachedBags = allBags

    -- Build known item IDs from all bags (for tracking new items)
    knownItemIDs = {}
    for bagID, bagData in pairs(allBags) do
        if bagData.slots then
            for slot, itemData in pairs(bagData.slots) do
                if itemData and itemData.itemID then
                    knownItemIDs[itemData.itemID] = (knownItemIDs[itemData.itemID] or 0) + 1
                end
            end
        end
    end

    ns:ProfileStop("ScanAllBags")
    return allBags
end

-- Scan only specific bags that are marked dirty
-- Optimized: only scans slots that actually changed, not the entire bag.
--
-- Recent-marker emission is deferred to the end of this function: a snapshot
-- of knownItemIDs is taken before per-slot diffs run, and only itemIDs whose
-- TOTAL slot occurrence count went 0→>0 (first appears) or >0→0 (last
-- vanishes) emit a marker. The per-slot path used to fire MarkRecent for any
-- item that landed in a previously-empty slot, which produced false positives
-- whenever a sort moved items between slots.
--
-- Returns cachedBags, changed. `changed` is true when this pass actually moved
-- something -- a slot gained or lost an item, a stack count moved, a lock flipped,
-- a bag appeared or went away. Only the verification passes below read it, to tell
-- "the game never told us about this" from "nothing happened"; every other caller
-- ignores the second value and behaves exactly as before.
function BagScanner:ScanDirtyBags(bagIDs)
    local changed = false
    -- Snapshot for the post-loop Recent diff. Shallow copy is enough because
    -- knownItemIDs values are numbers.
    local prevKnown = {}
    for itemID, count in pairs(knownItemIDs) do
        prevKnown[itemID] = count
    end

    for bagID in pairs(bagIDs) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        if not numSlots or numSlots == 0 then
            -- Bag was removed or emptied - update known item counts.
            if cachedBags[bagID] and cachedBags[bagID].slots then
                for slot, itemData in pairs(cachedBags[bagID].slots) do
                    if itemData and itemData.itemID then
                        knownItemIDs[itemData.itemID] = (knownItemIDs[itemData.itemID] or 1) - 1
                        if knownItemIDs[itemData.itemID] <= 0 then
                            knownItemIDs[itemData.itemID] = nil
                        end
                    end
                end
            end
            cachedBags[bagID] = nil
            changed = true
        else
            local existingBag = cachedBags[bagID]
            if not existingBag then
                -- New bag (newly equipped) - do full scan and update known counts.
                -- Recent emission is handled by the post-loop diff against prevKnown.
                local bagData = ItemScanner:ScanContainer(bagID)
                if bagData then
                    cachedBags[bagID] = bagData
                    changed = true
                    if bagData.slots then
                        for slot, itemData in pairs(bagData.slots) do
                            if itemData and itemData.itemID then
                                knownItemIDs[itemData.itemID] = (knownItemIDs[itemData.itemID] or 0) + 1
                            end
                        end
                    end
                end
            else
                -- Existing bag - only scan slots that changed
                local freeSlots = 0
                for slot = 1, numSlots do
                    local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
                    local cachedItem = existingBag.slots[slot]

                    -- Check if slot changed by comparing itemID AND link.
                    -- Two items can share an itemID but differ in item level /
                    -- bonus IDs (e.g. swapping two "Warboots" of different ilvl);
                    -- the itemID is identical, so we must also compare the link
                    -- (which encodes ilvl/bonusIDs) or the swap is invisible here
                    -- and the slot keeps showing the old item until a full rescan.
                    local currentItemID = itemInfo and itemInfo.itemID
                    local cachedItemID = cachedItem and cachedItem.itemID
                    local currentLink = itemInfo and itemInfo.hyperlink
                    local cachedLink = cachedItem and cachedItem.link

                    -- A record captured while the item was still loading compares
                    -- equal on both fields forever, so ask the scanner whether the
                    -- record is actually finished before trusting "unchanged".
                    local incomplete = ItemScanner:IsRecordIncomplete(cachedItem)

                    if currentItemID ~= cachedItemID or currentLink ~= cachedLink or incomplete then
                        changed = true
                        -- Slot changed - update known item counts. Recent
                        -- emission is handled by the post-loop diff so that
                        -- items merely moving between slots (sort, restack,
                        -- manual rearrange) don't fire false markers.
                        if cachedItemID then
                            knownItemIDs[cachedItemID] = (knownItemIDs[cachedItemID] or 1) - 1
                            if knownItemIDs[cachedItemID] <= 0 then
                                knownItemIDs[cachedItemID] = nil
                            end
                        end

                        if itemInfo then
                            if currentItemID then
                                knownItemIDs[currentItemID] = (knownItemIDs[currentItemID] or 0) + 1
                            end

                            -- Try fast path first (uses cached tooltip data)
                            -- This avoids tooltip scan when item just moved slots
                            local itemData = ItemScanner:ScanSlotFast(bagID, slot)
                            if not itemData then
                                -- No cached data, need full scan (new item)
                                itemData = ItemScanner:ScanSlot(bagID, slot)
                            end
                            existingBag.slots[slot] = itemData
                        else
                            existingBag.slots[slot] = nil
                        end
                    elseif itemInfo and cachedItem then
                        -- Same item, but check if count changed (for stacks)
                        if itemInfo.stackCount ~= cachedItem.count then
                            cachedItem.count = itemInfo.stackCount
                            changed = true
                        end
                        -- Check if locked state changed
                        if itemInfo.isLocked ~= cachedItem.locked then
                            cachedItem.locked = itemInfo.isLocked
                            changed = true
                        end
                    end

                    -- Count free slots (empty slots)
                    if not itemInfo then
                        freeSlots = freeSlots + 1
                    end
                end

                -- Update free slots count
                existingBag.freeSlots = freeSlots
                existingBag.numSlots = numSlots
            end
        end
    end

    -- Deferred Recent diff: emit MarkRecent only for itemIDs whose first slot
    -- just appeared, RemoveRecent only for those whose last slot just vanished.
    -- Skip entirely while a sort or restack is in progress — those operations
    -- preserve total item counts, so the post-sort scan will see no diff and
    -- correctly emit no markers. (Mid-sort scans can show transient cursor-
    -- pickup states where a count momentarily drops to 0; suppressing them
    -- avoids false marker churn.)
    local SortEngine = ns:GetModule("SortEngine")
    local sortActive = SortEngine and (SortEngine:IsSorting() or SortEngine:IsRestacking())
    if not sortActive then
        local RecentItems = ns:GetModule("RecentItems")
        if RecentItems then
            for itemID, count in pairs(knownItemIDs) do
                if count and count > 0 and not prevKnown[itemID] then
                    RecentItems:MarkRecent(itemID)
                end
            end
            for itemID, prevCount in pairs(prevKnown) do
                if prevCount > 0 and not knownItemIDs[itemID] then
                    RecentItems:RemoveRecent(itemID)
                end
            end
        end
    end

    return cachedBags, changed
end

function BagScanner:GetCachedBags()
    return cachedBags
end

function BagScanner:GetDirtyBags()
    return dirtyBags
end

function BagScanner:GetTotalSlots()
    local total = 0
    local free = 0

    -- Only count carried bags, not the keyring. IsPlayerBagID rather than a
    -- PLAYER_BAG_MIN..PLAYER_BAG_MAX range: that range stops at 4 and so leaves
    -- Retail's reagent bag out of the totals entirely.
    for bagID, bagData in pairs(cachedBags) do
        if Constants.IsPlayerBagID(bagID) then
            total = total + bagData.numSlots
            free = free + bagData.freeSlots
        end
    end

    return total, free
end

-- Get slot counts separated by bag type (regular vs special bags)
-- Returns: regularTotal, regularFree, specialBags table
-- specialBags format: { [bagType] = { total = N, free = N, name = "Bag Name" }, ... }
function BagScanner:GetDetailedSlotCounts()
    local regularTotal = 0
    local regularFree = 0
    local specialBags = {}

    -- IsPlayerBagID rather than a PLAYER_BAG_MIN..PLAYER_BAG_MAX range: that range
    -- stops at 4, so Retail's reagent bag never reached the family check below and
    -- was missing from the footer's special-bag tooltip altogether.
    for bagID, bagData in pairs(cachedBags) do
        if Constants.IsPlayerBagID(bagID) then
            local numSlots = bagData.numSlots or 0
            local freeSlots = bagData.freeSlots or 0

            -- Get bag family to determine type
            local bagFamily = 0
            if bagID > 0 then
                local _, family = C_Container.GetContainerNumFreeSlots(bagID)
                bagFamily = family or 0
            end

            if bagFamily == 0 then
                -- Regular bag (including backpack)
                regularTotal = regularTotal + numSlots
                regularFree = regularFree + freeSlots
            else
                -- Special bag - determine type
                local bagType = self:GetBagTypeFromFamily(bagFamily)
                if not specialBags[bagType] then
                    specialBags[bagType] = { total = 0, free = 0, name = bagType }
                end
                specialBags[bagType].total = specialBags[bagType].total + numSlots
                specialBags[bagType].free = specialBags[bagType].free + freeSlots
            end
        end
    end

    return regularTotal, regularFree, specialBags
end

-- Helper to get bag type from family (matches BagClassifier logic)
function BagScanner:GetBagTypeFromFamily(bagFamily)
    if bagFamily == 0 then return "regular" end
    if bit.band(bagFamily, 1) ~= 0 then return "Quiver" end
    if bit.band(bagFamily, 2) ~= 0 then return "Ammo Pouch" end
    if bit.band(bagFamily, 4) ~= 0 then return "Soul Bag" end
    if bit.band(bagFamily, 8) ~= 0 then return "Leatherworking Bag" end
    if bit.band(bagFamily, 16) ~= 0 then return "Inscription Bag" end
    if bit.band(bagFamily, 32) ~= 0 then return "Herb Bag" end
    if bit.band(bagFamily, 64) ~= 0 then return "Enchanting Bag" end
    if bit.band(bagFamily, 128) ~= 0 then return "Engineering Bag" end
    if bit.band(bagFamily, 512) ~= 0 then return "Gem Bag" end
    if bit.band(bagFamily, 1024) ~= 0 then return "Mining Bag" end
    return "Special Bag"
end

function BagScanner:GetAllItems()
    local items = {}

    for bagID, bagData in pairs(cachedBags) do
        for slot, itemData in pairs(bagData.slots) do
            table.insert(items, itemData)
        end
    end

    return items
end

function BagScanner:SaveToDatabase()
    Database:SaveBags(cachedBags)
    Database:SaveMoney(GetMoney())
end

-- Deferred save: waits for updates to settle before saving
local function ScheduleDeferredSave()
    if saveTimer then
        saveTimer:Cancel()
    end
    saveTimer = C_Timer.NewTimer(SAVE_DELAY, function()
        BagScanner:SaveToDatabase()
        saveTimer = nil
        ns:Debug("Deferred database save complete")
    end)
end

-- True when the only reason this drain was armed is a verification pass (see
-- RunVerifyPass). Set by the pass, consumed by the very next drain.
local verifyOnlyDrain = false

-- Process batched bag updates (called from OnUpdate)
local function ProcessBatchedUpdates()
    if not pendingUpdate then return end

    -- Allow UI updates during sorting so items move visually in real-time

    -- Copy and clear dirty bags before processing
    local bagsToScan = dirtyBags
    dirtyBags = {}
    pendingUpdate = false
    local wasVerifyOnly = verifyOnlyDrain
    verifyOnlyDrain = false
    updateFrame:Hide()

    ns:ProfileBump("event.batch")
    ns:ProfileStart("event.batchwork")

    -- Scan only the dirty bags
    local _, changed = BagScanner:ScanDirtyBags(bagsToScan)

    -- A verification pass that found nothing must stop here.
    --
    -- It dirties every bag by design, so ns.OnBagsUpdated would see a change in
    -- all of them and -- in grouped category view, where an addition cannot be
    -- reconciled incrementally -- take the full ~80ms rebuild. That would put a
    -- redundant rebuild after every looting window purely because we chose to
    -- look. A real BAG_UPDATE landing in the same window still sets `changed`,
    -- so this can only ever suppress a pass that genuinely did nothing.
    if wasVerifyOnly and not changed then
        ns:Debug("BagScanner: verify pass found nothing, skipping notify")
        ns:ProfileStop("event.batchwork")
        return
    end

    -- Schedule deferred save instead of immediate save
    ScheduleDeferredSave()

    -- Notify with list of updated bags for incremental updates
    if ns.OnBagsUpdated then
        ns.OnBagsUpdated(bagsToScan)
    end

    ns:ProfileStop("event.batchwork")
end

updateFrame:SetScript("OnUpdate", ProcessBatchedUpdates)

-- Check if bagID is a player bag (not bank)
local function IsPlayerBag(bagID)
    if not bagID then return false end
    -- Player bags: 0-4, Reagent Bag: 5 (Retail), Keyring: -2 (Classic)
    if bagID >= 0 and bagID <= 4 then return true end
    if Constants.REAGENT_BAG and bagID == Constants.REAGENT_BAG then return true end
    if Constants.KEYRING_BAG_ID and bagID == Constants.KEYRING_BAG_ID then return true end
    return false
end

-- Arm the OnUpdate drain for whatever is currently in dirtyBags. One owner, so the
-- pendingUpdate flag and the frame's shown state can never disagree.
local function ScheduleDirtyDrain()
    if pendingUpdate then return end
    pendingUpdate = true
    updateFrame:Show()
end

-- Mark a bag as dirty and schedule batched processing
local function OnBagUpdate(event, bagID)
    -- Only handle player bags, not bank bags (bank has its own scanner)
    if not IsPlayerBag(bagID) then
        return
    end

    ns:ProfileBump("event.BAG_UPDATE")
    ns:Debug("BagScanner: BAG_UPDATE for bag", bagID, "pending:", pendingUpdate)
    dirtyBags[bagID] = true
    recentlyUpdatedBags[bagID] = true

    ScheduleDirtyDrain()
end

Events:OnPlayerLogin(function()
    BagScanner:ScanAllBags()
    BagScanner:SaveToDatabase()
    ns:Debug("Initial bag scan complete")
end, BagScanner)

Events:OnBagUpdate(OnBagUpdate, BagScanner)

-- Re-check the batch once the server has finished with it.
--
-- BAG_UPDATE fires as each slot changes and we scan on the following frame, which
-- on retail is routinely before the client has resolved a just-looted item -- the
-- scan then records a placeholder (see ItemScanner.IsRecordIncomplete) or the
-- icon alone comes back nil. BAG_UPDATE_DELAYED is the client saying the batch has
-- settled, which is why Blizzard's own container UI redraws on it rather than on
-- BAG_UPDATE. Re-marking the same bags dirty reuses the existing dirty-set and
-- OnUpdate drain, so this adds an event, not a poll, and the change detection
-- above makes the second pass a no-op for every slot that did land complete.
Events:Register("BAG_UPDATE_DELAYED", function()
    if not next(recentlyUpdatedBags) then return end

    for bagID in pairs(recentlyUpdatedBags) do
        dirtyBags[bagID] = true
        recentlyUpdatedBags[bagID] = nil
    end

    ScheduleDirtyDrain()
end, BagScanner)

-- Force one verification scan of every player bag.
--
-- Some inventory changes reach the client without a per-bag BAG_UPDATE we can rely
-- on. BAG_UPDATE_DELAYED cannot cover those: its recentlyUpdatedBags guard has
-- nothing to re-dirty, so with no BAG_UPDATE the whole pipeline never runs and the
-- stale slots stay on screen until BagFrame:Show() rescans -- the "close and reopen
-- the bags" workaround.
--
-- Marking every player bag dirty reuses the existing dirty-set and OnUpdate drain,
-- so this is one extra scan, not a poll, and ScanDirtyBags' per-slot diff makes it
-- free for every slot that already landed. Constants.BAG_IDS rather than a
-- NUM_BAG_SLOTS range: that range stops at 4 and would skip Retail's reagent bag.
local function RunVerifyPass(reason)
    for _, bagID in ipairs(Constants.BAG_IDS) do
        dirtyBags[bagID] = true
    end
    ns:Debug("BagScanner: verify pass -", reason)
    -- Only a hint: a real BAG_UPDATE arriving before the drain still reports a
    -- change and the notify goes out as normal.
    verifyOnlyDrain = true
    ScheduleDirtyDrain()
end

-- Verify the bags once after every trade. Completing a trade consumes the
-- enchanter's reagents (and moves the traded items) with no BAG_UPDATE we can rely
-- on. Also fires on a cancelled trade, where the pass is a no-op. The delay lets
-- the server-side transfer settle first.
local TRADE_VERIFY_DELAY = 0.5
Events:Register("TRADE_CLOSED", function()
    C_Timer.After(TRADE_VERIFY_DELAY, function()
        RunVerifyPass("trade")
    end)
end, BagScanner)

-- Verify the bags once after a looting spree.
--
-- lootVerifyPending is the "the bags owe us a look" flag: loot sets it, the
-- debounced pass clears it. Trailing-edge NewTimer restarted on every loot, so an
-- AoE pull, a mailbox or a mass-disenchant coalesces into ONE pass a second after
-- the last loot instead of one per item.
--
-- LOOT_CLOSED rather than LOOT_OPENED: it is the point where the transfer is done,
-- and it fires for autoloot too. It is the only loot event registered -- it exists
-- in every flavor the TOC targets, while LOOT_READY does not, and RegisterEvent
-- raises on a name the client does not know.
--
-- Note this is a safety net for events WoW does not report cleanly, NOT a fix for
-- a stale bag display: the pass feeds the same ns.OnBagsUpdated as any BAG_UPDATE,
-- so whatever that path does with the result, it does here too.
local LOOT_VERIFY_DELAY = 1.0
local lootVerifyPending = false
local lootVerifyTimer = nil

local function ScheduleLootVerify()
    lootVerifyPending = true
    if lootVerifyTimer then lootVerifyTimer:Cancel() end
    lootVerifyTimer = C_Timer.NewTimer(LOOT_VERIFY_DELAY, function()
        lootVerifyTimer = nil
        if not lootVerifyPending then return end
        lootVerifyPending = false
        RunVerifyPass("loot")
    end)
end

Events:Register("LOOT_CLOSED", ScheduleLootVerify, BagScanner)

-- Handle BAGS_UPDATED event (fired after sort completes)
-- This ensures bags are rescanned and UI refreshed after sorting
Events:Register("BAGS_UPDATED", function()
    -- Use accumulated dirty bags if any, otherwise scan all player bags
    local bagsToScan = dirtyBags
    local bagCount = 0
    for _ in pairs(bagsToScan) do bagCount = bagCount + 1 end

    if bagCount == 0 then
        -- No dirty bags tracked, scan all player bags
        for _, bagID in ipairs(Constants.BAG_IDS) do
            bagsToScan[bagID] = true
        end
        bagCount = #Constants.BAG_IDS
    end

    ns:Debug(string.format("Post-sort refresh: %d dirty bags", bagCount))

    -- Clear state
    dirtyBags = {}
    pendingUpdate = false
    updateFrame:Hide()

    -- Scan only the dirty bags (faster than full rescan)
    BagScanner:ScanDirtyBags(bagsToScan)
    ScheduleDeferredSave()

    -- Notify UI with dirty bags for incremental update
    if ns.OnBagsUpdated then
        ns.OnBagsUpdated(bagsToScan)
    end
end, BagScanner)
