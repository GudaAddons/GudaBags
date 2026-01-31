local addonName, ns = ...

local BankFrame = {}
ns:RegisterModule("BankFrame", BankFrame)

local Constants = ns.Constants
local Database = ns:GetModule("Database")
local Events = ns:GetModule("Events")
local BankScanner = ns:GetModule("BankScanner")
local ItemButton = ns:GetModule("ItemButton")
local SearchBar = ns:GetModule("SearchBar")
local BagClassifier = ns:GetModule("BagFrame.BagClassifier")
local LayoutEngine = ns:GetModule("BagFrame.LayoutEngine")
local Utils = ns:GetModule("Utils")
local CategoryHeaderPool = ns:GetModule("CategoryHeaderPool")

local BankHeader = nil
local BankFooter = nil

local frame
local searchBar
local itemButtons = {}
local categoryHeaders = {}
local viewingCharacter = nil

-- Layout caching for incremental updates (same pattern as BagFrame)
local buttonsBySlot = {}  -- Key: "bagID:slot" -> button reference
local buttonsByBag = {}   -- Key: bagID -> { slot -> button } for fast bag-specific lookups
local cachedItemData = {} -- Key: "bagID:slot" -> previous itemID (for comparison)
local cachedItemCount = {} -- Key: "bagID:slot" -> previous count (for stack updates)
local cachedItemCategory = {} -- Key: "bagID:slot" -> previous categoryId (for category view)
local layoutCached = false -- True when layout is cached and can do incremental updates
local lastLayoutSettings = nil  -- Delta tracking for layout recalculation

-- Category View: Item-key-based button tracking
local buttonsByItemKey = {}
local categoryViewItems = {}
local lastCategoryLayout = nil
local lastButtonByCategory = {} -- Key: categoryId -> last item button (for drop indicator anchor)
local pseudoItemButtons = {} -- Track Empty/Soul pseudo-item buttons for proper release
                             -- Keys are "Empty:<categoryId>" or "Soul:<categoryId>" to avoid overwrites in merged groups
local lastTotalItemCount = 0 -- Track item count to detect Empty/Soul category changes

-- Helper to find a pseudo-item button by type (Empty or Soul)
local function FindPseudoItemButton(pseudoType)
    local prefix = pseudoType .. ":"
    for key, button in pairs(pseudoItemButtons) do
        if string.sub(key, 1, #prefix) == prefix then
            return button
        end
    end
    return nil
end

-- Use shared utility functions for key generation
local function GetItemKey(itemData)
    return Utils:GetItemKey(itemData)
end

local function GetSlotKey(bagID, slot)
    return Utils:GetSlotKey(bagID, slot)
end

-- Hidden frame to reparent Blizzard bank UI
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

local function LoadComponents()
    BankHeader = ns:GetModule("BankFrame.BankHeader")
    BankFooter = ns:GetModule("BankFrame.BankFooter")
end

-------------------------------------------------
-- Category Header Pool (uses shared CategoryHeaderPool module)
-------------------------------------------------

local function AcquireCategoryHeader(parent)
    return CategoryHeaderPool:Acquire(parent)
end

local function ReleaseAllCategoryHeaders()
    if frame and frame.container then
        CategoryHeaderPool:ReleaseAll(frame.container)  -- Pass owner to release only this frame's headers
    end
    categoryHeaders = {}
end

local UpdateFrameAppearance
local SaveFramePosition
local RestoreFramePosition

local function CreateBankFrame()
    local f = CreateFrame("Frame", "GudaBankFrame", UIParent, "BackdropTemplate")
    f:SetSize(400, 300)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(50)
    f:EnableMouse(true)

    -- Raise frame above BagFrame when clicked
    f:SetScript("OnMouseDown", function(self)
        self:SetFrameLevel(60)
        local BagFrameModule = ns:GetModule("BagFrame")
        if BagFrameModule and BagFrameModule:GetFrame() then
            BagFrameModule:GetFrame():SetFrameLevel(50)
        end
    end)
    f:SetBackdrop(Constants.BACKDROP)
    local bgAlpha = Database:GetSetting("bgAlpha") / 100
    f:SetBackdropColor(0.08, 0.08, 0.08, bgAlpha)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:Hide()

    -- Register for Escape key to close
    tinsert(UISpecialFrames, "GudaBankFrame")

    -- Close bank interaction when frame is hidden
    f:SetScript("OnHide", function()
        CloseBankFrame()
    end)

    f.titleBar = BankHeader:Init(f)
    BankHeader:SetDragCallback(SaveFramePosition)

    searchBar = SearchBar:Init(f)
    SearchBar:SetSearchCallback(f, function(text)
        BankFrame:Refresh()
    end)
    f.searchBar = searchBar

    local container = CreateFrame("Frame", nil, f)
    container:SetPoint("TOPLEFT", f, "TOPLEFT", Constants.FRAME.PADDING, -(Constants.FRAME.TITLE_HEIGHT + Constants.FRAME.SEARCH_BAR_HEIGHT + Constants.FRAME.PADDING + 6))
    container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -Constants.FRAME.PADDING, Constants.FRAME.FOOTER_HEIGHT + Constants.FRAME.PADDING + 6)
    f.container = container

    local emptyMessage = CreateFrame("Frame", nil, f)
    emptyMessage:SetAllPoints(container)
    emptyMessage:Hide()

    local emptyText = emptyMessage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyText:SetPoint("CENTER", emptyMessage, "CENTER", 0, 10)
    emptyText:SetTextColor(0.6, 0.6, 0.6)
    emptyText:SetText(ns.L["BANK_NO_DATA"])
    emptyMessage.text = emptyText

    local emptyHint = emptyMessage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emptyHint:SetPoint("TOP", emptyText, "BOTTOM", 0, -8)
    emptyHint:SetTextColor(0.5, 0.5, 0.5)
    emptyHint:SetText(ns.L["BANK_VISIT_BANKER"])
    emptyMessage.hint = emptyHint

    f.emptyMessage = emptyMessage

    f.footer = BankFooter:Init(f)
    BankFooter:SetBackCallback(function()
        BankFrame:ViewCharacter(nil, nil)
    end)

    -- Set bank character callback (for characters dropdown in BankHeader)
    BankHeader:SetCharacterCallback(function(fullName, charData)
        if not BankFrame:IsShown() then
            BankFrame:Show()
        end
        BankFrame:ViewCharacter(fullName, charData)
    end)

    return f
end

local function HasBankData(bank)
    if not bank then return false end
    for bagID, bagData in pairs(bank) do
        if bagData.numSlots and bagData.numSlots > 0 then
            return true
        end
    end
    return false
end

function BankFrame:Refresh()
    if not frame then return end

    ItemButton:ReleaseAll(frame.container)
    ReleaseAllCategoryHeaders()
    itemButtons = {}

    -- Clear layout cache for full refresh
    buttonsBySlot = {}
    buttonsByBag = {}
    cachedItemData = {}
    cachedItemCount = {}
    cachedItemCategory = {}
    buttonsByItemKey = {}
    categoryViewItems = {}
    lastCategoryLayout = nil
    lastTotalItemCount = 0
    pseudoItemButtons = {}
    layoutCached = false
    lastLayoutSettings = nil

    local isViewingCached = viewingCharacter ~= nil
    local isBankOpen = BankScanner:IsBankOpen()
    local bank

    if isViewingCached then
        bank = Database:GetNormalizedBank(viewingCharacter) or {}
    elseif isBankOpen then
        bank = BankScanner:GetCachedBank()
    else
        bank = Database:GetNormalizedBank() or {}
    end

    local hasBankData = isBankOpen or HasBankData(bank)

    if not hasBankData then
        frame.container:Hide()
        frame.emptyMessage:Show()

        if isViewingCached then
            frame.emptyMessage.text:SetText(ns.L["BANK_NO_DATA"])
            frame.emptyMessage.hint:SetText(ns.L["BANK_NOT_VISITED"])
        else
            frame.emptyMessage.text:SetText(ns.L["BANK_NO_DATA"])
            frame.emptyMessage.hint:SetText(ns.L["BANK_VISIT_BANKER"])
        end

        local columns = Database:GetSetting("bankColumns")
        local iconSize = Database:GetSetting("iconSize")
        local minWidth = (iconSize * columns) + (Constants.FRAME.PADDING * 2)
        local minHeight = 150

        frame:SetSize(math.max(minWidth, 250), minHeight)
        BankFooter:UpdateSlotInfo(0, 0)
        return
    end

    frame.emptyMessage:Hide()
    frame.container:Show()

    local iconSize = Database:GetSetting("iconSize")
    local spacing = Database:GetSetting("iconSpacing")
    local columns = Database:GetSetting("bankColumns")
    local searchText = SearchBar:GetSearchText(frame)
    local viewType = Database:GetSetting("bankViewType") or "single"

    local classifiedBags = BagClassifier:ClassifyBags(bank, isViewingCached or not isBankOpen, Constants.BANK_BAG_IDS)
    local bagsToShow = LayoutEngine:BuildDisplayOrder(classifiedBags, false)

    local showSearchBar = Database:GetSetting("showSearchBar")
    local showFooterSetting = Database:GetSetting("showFooter")
    local showFooter = showFooterSetting or isViewingCached or not isBankOpen
    local showCategoryCount = Database:GetSetting("showCategoryCount")
    local isReadOnly = isViewingCached or not isBankOpen

    local settings = {
        columns = columns,
        iconSize = iconSize,
        spacing = spacing,
        showSearchBar = showSearchBar,
        showFooter = showFooter,
        showCategoryCount = showCategoryCount,
    }

    if viewType == "category" then
        self:RefreshCategoryView(bank, bagsToShow, settings, searchText, isReadOnly)
    else
        self:RefreshSingleView(bank, bagsToShow, settings, searchText, isReadOnly)
    end

    if isViewingCached or not isBankOpen then
        local totalSlots = 0
        local usedSlots = 0
        for _, bagData in pairs(bank) do
            if bagData.numSlots then
                totalSlots = totalSlots + bagData.numSlots
                usedSlots = usedSlots + (bagData.numSlots - (bagData.freeSlots or 0))
            end
        end
        BankFooter:UpdateSlotInfo(usedSlots, totalSlots)
    else
        local totalSlots, freeSlots = BankScanner:GetTotalSlots()
        local regularTotal, regularFree, specialBags = BankScanner:GetDetailedSlotCounts()
        BankFooter:UpdateSlotInfo(totalSlots - freeSlots, totalSlots, regularTotal, regularFree, specialBags)
    end

    if isBankOpen and not isViewingCached then
        BankFooter:Update()
    end
end

function BankFrame:RefreshSingleView(bank, bagsToShow, settings, searchText, isReadOnly)
    local iconSize = settings.iconSize

    local allSlots = LayoutEngine:CollectAllSlots(bagsToShow, bank, isReadOnly)

    local frameWidth, frameHeight = LayoutEngine:CalculateFrameSize(allSlots, settings)
    frame:SetSize(frameWidth, frameHeight)

    local positions = LayoutEngine:CalculateButtonPositions(allSlots, settings)

    for i, slotInfo in ipairs(allSlots) do
        local button = ItemButton:Acquire(frame.container)
        local slotKey = slotInfo.bagID .. ":" .. slotInfo.slot

        if slotInfo.itemData then
            ItemButton:SetItem(button, slotInfo.itemData, iconSize, isReadOnly)
            if searchText ~= "" and not SearchBar:ItemMatchesSearch(slotInfo.itemData, searchText) then
                button:SetAlpha(0.3)
            else
                button:SetAlpha(1)
            end
            -- Cache item data for incremental updates
            cachedItemData[slotKey] = slotInfo.itemData.itemID
            cachedItemCount[slotKey] = slotInfo.itemData.count
        else
            ItemButton:SetEmpty(button, slotInfo.bagID, slotInfo.slot, iconSize, isReadOnly)
            if searchText ~= "" then
                button:SetAlpha(0.3)
            else
                button:SetAlpha(1)
            end
            cachedItemData[slotKey] = nil
            cachedItemCount[slotKey] = nil
        end

        local pos = positions[i]
        button.wrapper:ClearAllPoints()
        button.wrapper:SetPoint("TOPLEFT", frame.container, "TOPLEFT", pos.x, pos.y)

        -- Store button by slot key for incremental updates
        buttonsBySlot[slotKey] = button
        table.insert(itemButtons, button)

        -- Store by bagID for fast bag-specific lookups
        local bagID = slotInfo.bagID
        if not buttonsByBag[bagID] then
            buttonsByBag[bagID] = {}
        end
        buttonsByBag[bagID][slotInfo.slot] = button
    end

    layoutCached = true
end

function BankFrame:RefreshCategoryView(bank, bagsToShow, settings, searchText, isReadOnly)
    local iconSize = settings.iconSize

    local items, emptyCount, firstEmptySlot, soulEmptyCount, firstSoulEmptySlot = LayoutEngine:CollectItemsForCategoryView(bagsToShow, bank, isReadOnly)

    if searchText ~= "" then
        local filteredItems = {}
        for _, item in ipairs(items) do
            if SearchBar:ItemMatchesSearch(item.itemData, searchText) then
                table.insert(filteredItems, item)
            end
        end
        items = filteredItems
    end

    local sections = LayoutEngine:BuildCategorySections(items, isReadOnly, emptyCount, firstEmptySlot, soulEmptyCount, firstSoulEmptySlot)

    local frameWidth, frameHeight = LayoutEngine:CalculateCategoryFrameSize(sections, settings)
    frame:SetSize(frameWidth, frameHeight)

    local layout = LayoutEngine:CalculateCategoryPositions(sections, settings)

    for _, headerInfo in ipairs(layout.headers) do
        local header = AcquireCategoryHeader(frame.container)
        header:SetWidth(headerInfo.width)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", frame.container, "TOPLEFT", headerInfo.x, headerInfo.y)

        -- No icons in category headers
        header.icon:Hide()
        header.text:ClearAllPoints()
        header.text:SetPoint("LEFT", header, "LEFT", 0, 0)

        -- Adjust font size based on icon size
        local fontFile, _, fontFlags = header.text:GetFont()
        if iconSize < Constants.CATEGORY_ICON_SIZE_THRESHOLD then
            header.text:SetFont(fontFile, Constants.CATEGORY_FONT_SMALL, fontFlags)
        else
            header.text:SetFont(fontFile, Constants.CATEGORY_FONT_LARGE, fontFlags)
        end

        -- Responsive text truncation based on available width
        local displayName = headerInfo.section.categoryName
        local numItems = #headerInfo.section.items
        -- Show count unless disabled OR only 1 item (redundant to show "(1)")
        local showCount = settings.showCategoryCount and numItems > 1
        local countSuffix = showCount and (" (" .. numItems .. ")") or ""
        header.fullName = displayName
        header.isShortened = false

        -- When not showing count, truncate based on item count
        -- 1 item: max 6 chars, 2+ items: max 13 chars
        if not showCount then
            local maxChars = numItems == 1 and 6 or 13
            if string.len(displayName) > maxChars then
                header.isShortened = true
                header.text:SetText(string.sub(displayName, 1, maxChars) .. "...")
            else
                header.text:SetText(displayName)
            end
        else
            -- Calculate available width (header width minus line spacing)
            local availableWidth = headerInfo.width - 10

            -- Set full text first to measure
            header.text:SetText(displayName .. countSuffix)
            local textWidth = header.text:GetStringWidth()

            -- Truncate if text is too wide (only for names longer than 4 characters)
            if textWidth > availableWidth and string.len(displayName) > 4 then
                header.isShortened = true
                -- Binary search for best fit
                local maxChars = string.len(displayName)
                while textWidth > availableWidth and maxChars > 1 do
                    maxChars = maxChars - 1
                    header.text:SetText(string.sub(displayName, 1, maxChars) .. "..." .. countSuffix)
                    textWidth = header.text:GetStringWidth()
                end
            end
        end

        -- Hide separator line for single-item categories
        if numItems <= 1 then
            header.line:Hide()
        else
            header.line:Show()
        end

        -- Store category info on header for drag-drop
        header.categoryId = headerInfo.section.categoryId
        header:EnableMouse(true)

        -- Add tooltip for shortened names
        header:SetScript("OnEnter", function(self)
            if self.isShortened then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
                GameTooltip:SetText(self.fullName)
                GameTooltip:Show()
            end
        end)
        header:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        -- Handle click for Empty category: place item in first empty bank slot
        header:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" and self.categoryId == "Empty" then
                local cursorType = GetCursorInfo()
                if cursorType == "item" then
                    -- Find first empty bank slot (main bank first, then bank bags)
                    local bankBags = { BANK_CONTAINER }
                    for i = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
                        table.insert(bankBags, i)
                    end
                    for _, bagID in ipairs(bankBags) do
                        local numSlots = C_Container.GetContainerNumSlots(bagID)
                        for slot = 1, numSlots do
                            local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
                            if not itemInfo then
                                -- Empty slot found, place item here
                                C_Container.PickupContainerItem(bagID, slot)
                                return
                            end
                        end
                    end
                end
            end
        end)

        table.insert(categoryHeaders, header)
    end

    -- Reset last button tracking for drop indicator
    lastButtonByCategory = {}

    for index, itemInfo in ipairs(layout.items) do
        local button = ItemButton:Acquire(frame.container)
        local itemData = itemInfo.item.itemData
        local slotKey = itemData.bagID .. ":" .. itemData.slot

        -- Store category info before SetItem so it can use it for display logic
        button.categoryId = itemInfo.categoryId

        ItemButton:SetItem(button, itemData, iconSize, isReadOnly)
        button:SetAlpha(1)

        -- Store layout position for drag-drop indicator
        button.iconSize = iconSize
        button.layoutX = itemInfo.x
        button.layoutY = itemInfo.y
        button.layoutIndex = index
        button.containerFrame = frame.container

        button.wrapper:ClearAllPoints()
        button.wrapper:SetPoint("TOPLEFT", frame.container, "TOPLEFT", itemInfo.x, itemInfo.y)

        -- Track Empty/Soul pseudo-item buttons separately
        -- Use a unique key combining pseudo-item type and categoryId to avoid overwrites
        -- when multiple pseudo-items (Empty, Soul) are in the same merged group
        if itemData.isEmptySlots then
            local pseudoKey = (itemData.isSoulSlots and "Soul:" or "Empty:") .. itemInfo.categoryId
            pseudoItemButtons[pseudoKey] = button
        else
            -- Store button by slot key for incremental updates (not for pseudo-items)
            buttonsBySlot[slotKey] = button
            cachedItemData[slotKey] = itemData.itemID
            cachedItemCount[slotKey] = itemData.count
            cachedItemCategory[slotKey] = itemInfo.categoryId

            -- Store by bagID for fast bag-specific lookups
            local bagID = itemData.bagID
            if not buttonsByBag[bagID] then
                buttonsByBag[bagID] = {}
            end
            buttonsByBag[bagID][itemData.slot] = button
        end

        table.insert(itemButtons, button)

        -- Track last button per category (for drop indicator anchor)
        if itemInfo.categoryId then
            lastButtonByCategory[itemInfo.categoryId] = button
        end
    end

    layoutCached = true
end

function BankFrame:Toggle()
    LoadComponents()

    if not frame then
        frame = CreateBankFrame()
        RestoreFramePosition()
    end

    if frame:IsShown() then
        frame:Hide()
    else
        if BankScanner:IsBankOpen() then
            BankScanner:ScanAllBank()
        end
        self:Refresh()
        UpdateFrameAppearance()
        frame:Show()
    end
end

function BankFrame:Show()
    LoadComponents()

    if not frame then
        frame = CreateBankFrame()
        RestoreFramePosition()
    end

    if BankScanner:IsBankOpen() then
        BankScanner:ScanAllBank()
    end
    self:Refresh()
    UpdateFrameAppearance()
    frame:Show()
end

function BankFrame:Hide()
    if frame then
        frame:Hide()
        if viewingCharacter then
            viewingCharacter = nil
            BankHeader:SetViewingCharacter(nil, nil)
        end
        -- Release pseudo-item buttons before clearing
        for _, button in pairs(pseudoItemButtons) do
            ItemButton:Release(button)
        end
        -- Clear layout cache so next open does full refresh
        buttonsBySlot = {}
        buttonsByBag = {}
        cachedItemData = {}
        cachedItemCount = {}
        cachedItemCategory = {}
        buttonsByItemKey = {}
        categoryViewItems = {}
        lastCategoryLayout = nil
        lastTotalItemCount = 0
        pseudoItemButtons = {}
        layoutCached = false
        lastLayoutSettings = nil
    end
end

function BankFrame:IsShown()
    return frame and frame:IsShown()
end

function BankFrame:GetFrame()
    return frame
end

function BankFrame:GetViewingCharacter()
    return viewingCharacter
end

function BankFrame:ViewCharacter(fullName, charData)
    viewingCharacter = fullName
    BankHeader:SetViewingCharacter(fullName, charData)

    UpdateFrameAppearance()
    self:Refresh()
end

function BankFrame:IsViewingCached()
    return viewingCharacter ~= nil or not BankScanner:IsBankOpen()
end

-- Incremental update: only update changed slots without full layout recalculation
-- dirtyBags: optional table of {bagID = true} for bags that changed
function BankFrame:IncrementalUpdate(dirtyBags)
    if not frame or not frame:IsShown() then return end

    -- Never do incremental updates while viewing a cached character
    -- Live bank events should not affect cached character display
    if viewingCharacter then return end

    -- If Recent items were removed, force full refresh to prevent texture artifacts
    local RecentItems = ns:GetModule("RecentItems")
    if RecentItems and RecentItems:WasItemRemoved() then
        -- Release ALL buttons and headers for clean slate
        ItemButton:ReleaseAll(frame.container)
        ReleaseAllCategoryHeaders()
        buttonsByItemKey = {}
        buttonsBySlot = {}
        buttonsByBag = {}
        cachedItemData = {}
        cachedItemCount = {}
        cachedItemCategory = {}
        categoryViewItems = {}
        lastCategoryLayout = nil
        lastTotalItemCount = 0
        for _, button in pairs(pseudoItemButtons) do
            ItemButton:Release(button)
        end
        pseudoItemButtons = {}
        layoutCached = false
        self:Refresh()
        return
    end

    if not layoutCached then
        -- No cached layout, do full refresh
        self:Refresh()
        return
    end

    local bank = BankScanner:GetCachedBank()
    -- Cache settings once at start (avoid repeated GetSetting calls)
    local iconSize = Database:GetSetting("iconSize")
    local searchText = SearchBar:GetSearchText(frame)
    local hasSearch = searchText ~= ""
    local isReadOnly = viewingCharacter ~= nil or not BankScanner:IsBankOpen()
    local viewType = Database:GetSetting("bankViewType") or "single"
    local isCategoryView = viewType == "category"

    -- If no dirty bags specified, check all (fallback behavior)
    local checkAllBags = not dirtyBags or not next(dirtyBags)

    -- For category view: check if item's CATEGORY changed (not just itemID)
    -- If item moves within same category, do incremental update
    -- If item moves between categories or slot becomes empty/filled, do full refresh
    if isCategoryView then
        local CategoryManager = ns:GetModule("CategoryManager")
        local needsFullRefresh = false
        local itemUpdates = {}
        local countUpdates = {}
        local ghostSlots = {}

        local function checkBag(bagID)
            local slotButtons = buttonsByBag[bagID] or {}
            local bagData = bank[bagID]

            -- Count cached buttons for this bag
            local cachedButtonCount = 0
            for _ in pairs(slotButtons) do
                cachedButtonCount = cachedButtonCount + 1
            end

            local currentItemCount = 0
            if bagData and bagData.slots then
                for _, itemData in pairs(bagData.slots) do
                    if itemData then
                        currentItemCount = currentItemCount + 1
                    end
                end
            end

            -- If no buttons cached for this bag but items exist now, new item appeared - need refresh
            if cachedButtonCount == 0 then
                if currentItemCount > 0 then
                    ns:Debug("Bank CategoryView REFRESH: bag", bagID, "was empty, now has", currentItemCount, "items")
                    needsFullRefresh = true
                end
                return
            end

            -- If MORE items than buttons, new item appeared - need refresh
            if currentItemCount > cachedButtonCount then
                ns:Debug("Bank CategoryView REFRESH: bag", bagID, "has MORE items", currentItemCount, ">", cachedButtonCount)
                needsFullRefresh = true
                return
            end
            -- If fewer items, some were removed - keep ghost slots (lazy approach)
            if currentItemCount < cachedButtonCount then
                ns:Debug("Bank CategoryView LAZY: bag", bagID, "has FEWER items", currentItemCount, "<", cachedButtonCount, "- keeping ghosts")
            end

            for slot, button in pairs(slotButtons) do
                local slotKey = bagID .. ":" .. slot
                local newItemData = bagData and bagData.slots and bagData.slots[slot]
                local oldItemID = cachedItemData[slotKey]
                local newItemID = newItemData and newItemData.itemID or nil
                local oldCategory = cachedItemCategory[slotKey]

                if oldItemID ~= newItemID then
                    if not newItemData then
                        -- Slot became empty - show empty texture but keep position (no layout refresh)
                        ns:Debug("Bank CategoryView GHOST: empty slot at", slotKey, "oldID=", oldItemID)
                        ItemButton:SetEmpty(button, bagID, slot, iconSize, isReadOnly)
                        cachedItemData[slotKey] = nil
                        cachedItemCount[slotKey] = nil
                        -- Keep cachedItemCategory so we know this slot existed
                        table.insert(ghostSlots, slotKey)
                    else
                        local newCategory = CategoryManager and CategoryManager:CategorizeItem(newItemData, bagID, slot, isReadOnly) or "Miscellaneous"

                        if oldCategory ~= newCategory then
                            ns:Debug("Bank CategoryView REFRESH: category changed at", slotKey, "from", oldCategory, "to", newCategory)
                            needsFullRefresh = true
                            return
                        end

                        itemUpdates[slotKey] = {button = button, itemData = newItemData, category = newCategory}
                    end
                elseif newItemData then
                    local oldCount = cachedItemCount[slotKey]
                    if oldCount ~= newItemData.count then
                        countUpdates[slotKey] = {button = button, count = newItemData.count}
                    end
                end
            end

            -- Check for items in slots we don't have buttons for (new slots)
            if bagData and bagData.slots then
                for slot, itemData in pairs(bagData.slots) do
                    if itemData and not slotButtons[slot] then
                        ns:Debug("Bank CategoryView REFRESH: new item at untracked slot", bagID .. ":" .. slot)
                        needsFullRefresh = true
                        return
                    end
                end
            end
        end

        if checkAllBags then
            for bagID in pairs(buttonsByBag) do
                checkBag(bagID)
                if needsFullRefresh then break end
            end
        else
            for bagID in pairs(dirtyBags) do
                checkBag(bagID)
                if needsFullRefresh then break end
            end
        end

        if needsFullRefresh then
            ns:Debug("Bank CategoryView: FULL REFRESH triggered")
            self:Refresh()
            return
        end

        if #ghostSlots > 0 then
            ns:Debug("Bank CategoryView LAZY: kept", #ghostSlots, "ghost slots, no refresh")
        end

        for slotKey, update in pairs(itemUpdates) do
            ItemButton:SetItem(update.button, update.itemData, iconSize, isReadOnly)
            cachedItemData[slotKey] = update.itemData.itemID
            cachedItemCount[slotKey] = update.itemData.count
            cachedItemCategory[slotKey] = update.category
            if hasSearch and not SearchBar:ItemMatchesSearch(update.itemData, searchText) then
                update.button:SetAlpha(0.3)
            else
                update.button:SetAlpha(1)
            end
        end

        for slotKey, update in pairs(countUpdates) do
            SetItemButtonCount(update.button, update.count)
            cachedItemCount[slotKey] = update.count
        end

        -- Calculate empty slot counts and first empty slots using LIVE data
        local emptyCount = 0
        local soulEmptyCount = 0
        local firstEmptyBagID, firstEmptySlot = nil, nil
        local firstSoulBagID, firstSoulSlot = nil, nil

        for bagID = Constants.BANK_MAIN_BAG, Constants.BANK_BAG_MAX do
            if bagID == Constants.BANK_MAIN_BAG or (bagID >= Constants.BANK_BAG_MIN and bagID <= Constants.BANK_BAG_MAX) then
                local numSlots = C_Container.GetContainerNumSlots(bagID)
                if numSlots and numSlots > 0 then
                    local bagType = BagClassifier and BagClassifier:GetBagType(bagID) or "regular"
                    local isSoulBag = (bagType == "soul")
                    for slot = 1, numSlots do
                        local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
                        if not itemInfo then
                            if isSoulBag then
                                soulEmptyCount = soulEmptyCount + 1
                                if not firstSoulBagID then
                                    firstSoulBagID, firstSoulSlot = bagID, slot
                                end
                            else
                                emptyCount = emptyCount + 1
                                if not firstEmptyBagID then
                                    firstEmptyBagID, firstEmptySlot = bagID, slot
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Check if Empty/Soul categories need to appear or disappear
        local emptyButtonExists = FindPseudoItemButton("Empty") ~= nil
        local soulButtonExists = FindPseudoItemButton("Soul") ~= nil
        local emptyNeedsButton = emptyCount > 0
        local soulNeedsButton = soulEmptyCount > 0

        if (emptyNeedsButton and not emptyButtonExists) or (not emptyNeedsButton and emptyButtonExists) then
            ns:Debug("Bank CategoryView REFRESH: Empty category visibility changed")
            self:Refresh()
            return
        end
        if (soulNeedsButton and not soulButtonExists) or (not soulNeedsButton and soulButtonExists) then
            ns:Debug("Bank CategoryView REFRESH: Soul category visibility changed")
            self:Refresh()
            return
        end

        -- Update pseudo-item counters and slot references directly
        local emptyBtn = FindPseudoItemButton("Empty")
        if emptyBtn then
            SetItemButtonCount(emptyBtn, emptyCount)
            if emptyBtn.itemData then
                emptyBtn.itemData.emptyCount = emptyCount
                emptyBtn.itemData.count = emptyCount
                if firstEmptyBagID then
                    emptyBtn.itemData.bagID = firstEmptyBagID
                    emptyBtn.itemData.slot = firstEmptySlot
                    emptyBtn.wrapper:SetID(firstEmptyBagID)
                    emptyBtn:SetID(firstEmptySlot)
                end
            end
        end
        local soulBtn = FindPseudoItemButton("Soul")
        if soulBtn then
            SetItemButtonCount(soulBtn, soulEmptyCount)
            if soulBtn.itemData then
                soulBtn.itemData.emptyCount = soulEmptyCount
                soulBtn.itemData.count = soulEmptyCount
                if firstSoulBagID then
                    soulBtn.itemData.bagID = firstSoulBagID
                    soulBtn.itemData.slot = firstSoulSlot
                    soulBtn.wrapper:SetID(firstSoulBagID)
                    soulBtn:SetID(firstSoulSlot)
                end
            end
        end

        local totalSlots, freeSlots = BankScanner:GetTotalSlots()
        local regularTotal, regularFree, specialBags = BankScanner:GetDetailedSlotCounts()
        BankFooter:UpdateSlotInfo(totalSlots - freeSlots, totalSlots, regularTotal, regularFree, specialBags)
        if BankScanner:IsBankOpen() and not viewingCharacter then
            BankFooter:Update()
        end
        return
    end

    -- Single view: full incremental update (items stay in fixed slots)
    -- Optimized: Only iterate buttons in dirty bags using buttonsByBag index
    if checkAllBags then
        -- Fallback: check all bags
        for bagID, slotButtons in pairs(buttonsByBag) do
            local bagData = bank[bagID]
            for slot, button in pairs(slotButtons) do
                local slotKey = bagID .. ":" .. slot
                local newItemData = bagData and bagData.slots and bagData.slots[slot]
                local oldItemID = cachedItemData[slotKey]
                local newItemID = newItemData and newItemData.itemID or nil

                if oldItemID ~= newItemID then
                    if newItemData then
                        ItemButton:SetItem(button, newItemData, iconSize, isReadOnly)
                        cachedItemData[slotKey] = newItemID
                        cachedItemCount[slotKey] = newItemData.count
                        if hasSearch and not SearchBar:ItemMatchesSearch(newItemData, searchText) then
                            button:SetAlpha(0.3)
                        else
                            button:SetAlpha(1)
                        end
                    else
                        ItemButton:SetEmpty(button, bagID, slot, iconSize, isReadOnly)
                        cachedItemData[slotKey] = nil
                        cachedItemCount[slotKey] = nil
                        button:SetAlpha(hasSearch and 0.3 or 1)
                    end
                elseif newItemData then
                    -- Same item - only update if count changed (stacking)
                    local oldCount = cachedItemCount[slotKey]
                    if oldCount ~= newItemData.count then
                        SetItemButtonCount(button, newItemData.count)
                        cachedItemCount[slotKey] = newItemData.count
                    end
                end
            end
        end
    else
        -- Fast path: only check dirty bags (O(dirty bags) instead of O(all buttons))
        for bagID in pairs(dirtyBags) do
            local slotButtons = buttonsByBag[bagID]
            if slotButtons then
                local bagData = bank[bagID]
                for slot, button in pairs(slotButtons) do
                    local slotKey = bagID .. ":" .. slot
                    local newItemData = bagData and bagData.slots and bagData.slots[slot]
                    local oldItemID = cachedItemData[slotKey]
                    local newItemID = newItemData and newItemData.itemID or nil

                    if oldItemID ~= newItemID then
                        if newItemData then
                            ItemButton:SetItem(button, newItemData, iconSize, isReadOnly)
                            cachedItemData[slotKey] = newItemID
                            cachedItemCount[slotKey] = newItemData.count
                            if hasSearch and not SearchBar:ItemMatchesSearch(newItemData, searchText) then
                                button:SetAlpha(0.3)
                            else
                                button:SetAlpha(1)
                            end
                        else
                            ItemButton:SetEmpty(button, bagID, slot, iconSize, isReadOnly)
                            cachedItemData[slotKey] = nil
                            cachedItemCount[slotKey] = nil
                            button:SetAlpha(hasSearch and 0.3 or 1)
                        end
                    elseif newItemData then
                        -- Same item - only update if count changed (stacking)
                        local oldCount = cachedItemCount[slotKey]
                        if oldCount ~= newItemData.count then
                            SetItemButtonCount(button, newItemData.count)
                            cachedItemCount[slotKey] = newItemData.count
                        end
                    end
                end
            end
        end
    end

    -- Update footer slot info
    local totalSlots, freeSlots = BankScanner:GetTotalSlots()
    local regularTotal, regularFree, specialBags = BankScanner:GetDetailedSlotCounts()
    BankFooter:UpdateSlotInfo(totalSlots - freeSlots, totalSlots, regularTotal, regularFree, specialBags)
    if BankScanner:IsBankOpen() and not viewingCharacter then
        BankFooter:Update()
    end
end

-- dirtyBags: table of {bagID = true} for bags that were updated
ns.OnBankUpdated = function(dirtyBags)
    if not viewingCharacter and frame and frame:IsShown() then
        -- Use incremental update if layout is cached, otherwise full refresh
        if layoutCached then
            BankFrame:IncrementalUpdate(dirtyBags)
        else
            BankFrame:Refresh()
        end
    end
end

ns.OnBankOpened = function()
    LoadComponents()

    if not frame then
        frame = CreateBankFrame()
        RestoreFramePosition()
    end

    BankFrame:Show()
end

ns.OnBankClosed = function()
    if frame and frame:IsShown() then
        BankScanner:SaveToDatabase()
    end
end

UpdateFrameAppearance = function()
    if not frame then return end

    local isViewingCached = viewingCharacter ~= nil
    local isBankOpen = BankScanner:IsBankOpen()

    local bgAlpha = Database:GetSetting("bgAlpha") / 100
    frame:SetBackdropColor(0.08, 0.08, 0.08, bgAlpha)
    BankHeader:SetBackdropAlpha(bgAlpha)

    ItemButton:UpdateSlotAlpha(bgAlpha)
    ItemButton:UpdateFontSize()
    local TrackedBar = ns:GetModule("TrackedBar")
    if TrackedBar then
        TrackedBar:UpdateFontSize()
        TrackedBar:UpdateSize()
    end
    local QuestBar = ns:GetModule("QuestBar")
    if QuestBar then
        QuestBar:UpdateFontSize()
        QuestBar:UpdateSize()
    end

    local showSearchBar = Database:GetSetting("showSearchBar")
    local showFooter = Database:GetSetting("showFooter")
    local footerHeight = (not showFooter and isBankOpen and not isViewingCached) and Constants.FRAME.PADDING or (Constants.FRAME.FOOTER_HEIGHT + Constants.FRAME.PADDING + 6)

    frame.container:ClearAllPoints()
    if showSearchBar then
        SearchBar:Show(frame)
        frame.container:SetPoint("TOPLEFT", frame, "TOPLEFT", Constants.FRAME.PADDING, -(Constants.FRAME.TITLE_HEIGHT + Constants.FRAME.SEARCH_BAR_HEIGHT + Constants.FRAME.PADDING + 6))
    else
        SearchBar:Hide(frame)
        frame.container:SetPoint("TOPLEFT", frame, "TOPLEFT", Constants.FRAME.PADDING, -(Constants.FRAME.TITLE_HEIGHT + Constants.FRAME.PADDING + 2))
    end
    frame.container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Constants.FRAME.PADDING, footerHeight)

    if isViewingCached then
        BankFooter:ShowCached(viewingCharacter)
        BankHeader:SetSortEnabled(false)
    elseif not isBankOpen then
        BankFooter:ShowCached(Database:GetPlayerFullName())
        BankHeader:SetSortEnabled(false)
    elseif showFooter then
        BankFooter:Show()
        BankHeader:SetSortEnabled(true)
    else
        BankFooter:Hide()
        BankHeader:SetSortEnabled(true)
    end

    local showBorders = Database:GetSetting("showBorders")
    if showBorders then
        frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    else
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

local appearanceSettings = {
    bgAlpha = true,
    showBorders = true,
    iconFontSize = true,
    trackedBarSize = true,
    trackedBarColumns = true,
    questBarSize = true,
}

local resizeSettings = {
    showFooter = true,
    showSearchBar = true,
}

local function OnSettingChanged(event, key, value)
    if not frame or not frame:IsShown() then return end

    -- When changing view type while viewing another character, reset to current character
    if key == "bankViewType" and viewingCharacter then
        viewingCharacter = nil
        BankHeader:SetViewingCharacter(nil, nil)
    end

    if appearanceSettings[key] then
        UpdateFrameAppearance()
    elseif resizeSettings[key] then
        UpdateFrameAppearance()
        BankFrame:Refresh()
    elseif key == "groupIdenticalItems" then
        -- Force full release when toggling item grouping to prevent visual artifacts
        -- Item structure changes fundamentally (grouped vs individual) but keys stay same
        ItemButton:ReleaseAll(frame.container)
        buttonsByItemKey = {}
        pseudoItemButtons = {}
        BankFrame:Refresh()
    else
        BankFrame:Refresh()
    end
end

SaveFramePosition = function()
    if not frame then return end
    local point, _, relativePoint, x, y = frame:GetPoint()
    Database:SetSetting("bankFramePoint", point)
    Database:SetSetting("bankFrameRelativePoint", relativePoint)
    Database:SetSetting("bankFrameX", x)
    Database:SetSetting("bankFrameY", y)
end

RestoreFramePosition = function()
    if not frame then return end
    local point = Database:GetSetting("bankFramePoint")
    local relativePoint = Database:GetSetting("bankFrameRelativePoint")
    local x = Database:GetSetting("bankFrameX")
    local y = Database:GetSetting("bankFrameY")

    frame:ClearAllPoints()
    if point and x and y then
        frame:SetPoint(point, UIParent, relativePoint, x, y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function BankFrame:SortBank()
    if not BankScanner:IsBankOpen() then
        ns:Print("Cannot sort bank: not at banker")
        return
    end

    local SortEngine = ns:GetModule("SortEngine")
    if SortEngine then
        SortEngine:SortBank()
    else
        ns:Print("SortEngine not loaded")
    end
end

-- Restack items and clean ghost slots (for category view)
function BankFrame:RestackAndClean()
    if not frame or not frame:IsShown() then return end
    if not BankScanner:IsBankOpen() then
        ns:Print("Cannot restack bank: not at banker")
        return
    end

    -- Play sound feedback
    PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)

    -- Use SortEngine's restack function (consolidates stacks without sorting)
    local SortEngine = ns:GetModule("SortEngine")
    if SortEngine then
        SortEngine:RestackBank(function()
            -- Callback when restack is complete - now clean ghost slots
            C_Timer.After(0.1, function()
                if frame and frame:IsShown() then
                    -- Release all buttons first (they would be orphaned otherwise)
                    ItemButton:ReleaseAll(frame.container)

                    -- Clear all layout caches (removes ghost slots)
                    buttonsBySlot = {}
                    buttonsByBag = {}
                    cachedItemData = {}
                    cachedItemCount = {}
                    cachedItemCategory = {}
                    buttonsByItemKey = {}
                    categoryViewItems = {}
                    lastCategoryLayout = nil
                    lastTotalItemCount = 0
                    pseudoItemButtons = {}
                    layoutCached = false
                    lastLayoutSettings = nil

                    -- Rescan and refresh
                    BankScanner:ScanAllBank()
                    BankFrame:Refresh()
                end
            end)
        end)
    else
        -- Fallback if no SortEngine
        BankScanner:ScanAllBank()
        BankFrame:Refresh()
    end
end

Events:Register("SETTING_CHANGED", OnSettingChanged, BankFrame)

-- Refresh when categories are updated (reordered, grouped, etc.)
-- Force full refresh by releasing all buttons since category assignments changed
Events:Register("CATEGORIES_UPDATED", function()
    if frame and frame:IsShown() then
        -- Release all buttons to force full refresh (category assignments changed)
        ItemButton:ReleaseAll(frame.container)
        buttonsByItemKey = {}
        pseudoItemButtons = {}
        BankFrame:Refresh()
    end
end, BankFrame)

Events:Register("PLAYER_MONEY", function()
    if frame and frame:IsShown() then
        BankFooter:UpdateMoney()
    end
end, BankFrame)

-- Update item lock state (when picking up/putting down items)
Events:Register("ITEM_LOCK_CHANGED", function(event, bagID, slotID)
    -- Skip when viewing cached character - lock state is for current character only
    if viewingCharacter then return end
    if frame and frame:IsShown() and bagID and slotID then
        ItemButton:UpdateLockForItem(bagID, slotID)
    end
end, BankFrame)

-- Disable the default Blizzard bank frame completely
local function HideDefaultBankFrame()
    if _G.BankFrame then
        _G.BankFrame:SetParent(hiddenParent)
        _G.BankFrame:SetScript("OnShow", nil)
        _G.BankFrame:SetScript("OnHide", nil)
        _G.BankFrame:SetScript("OnEvent", nil)
    end
end

HideDefaultBankFrame()
