local addonName, ns = ...

local CategoryDropIndicator = {}
ns:RegisterModule("CategoryDropIndicator", CategoryDropIndicator)

local Constants = ns.Constants

-------------------------------------------------
-- State
-------------------------------------------------

local indicator = nil
local currentCategoryId = nil
local currentHoveredButton = nil
local currentContainer = nil

-------------------------------------------------
-- Create Indicator (horizontal bar above hovered item)
-------------------------------------------------

local function CreateIndicator()
    if indicator then return indicator end

    -- Create a horizontal bar indicator above the hovered item
    local frame = CreateFrame("Frame", "GudaBagsCategoryDropIndicator", UIParent)
    frame:SetSize(36, 14)  -- Wide bar, short height
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(100)

    -- Bar background
    local barBg = frame:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0.2, 0.6, 0.2, 0.9)  -- Green background
    frame.barBg = barBg

    -- Plus icon on the left
    local plus = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    plus:SetPoint("LEFT", frame, "LEFT", 4, 0)
    plus:SetText("+")
    plus:SetTextColor(1, 1, 1, 1)
    frame.plus = plus

    -- Border
    local border = frame:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.3, 0.8, 0.3, 1)
    frame.border = border

    -- Inner background (creates border effect)
    local inner = frame:CreateTexture(nil, "ARTWORK")
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    inner:SetColorTexture(0.15, 0.4, 0.15, 0.95)
    frame.inner = inner

    -- Make it clickable for dropping items
    frame:EnableMouse(true)

    frame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            CategoryDropIndicator:HandleDrop()
        end
    end)

    frame:SetScript("OnReceiveDrag", function(self)
        CategoryDropIndicator:HandleDrop()
    end)

    -- Show tooltip when hovering over the indicator
    frame:SetScript("OnEnter", function(self)
        if currentCategoryId then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Add item to this category", 1, 1, 1)
            GameTooltip:AddLine("Drop here to permanently assign", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("this item to \"" .. tostring(currentCategoryId) .. "\"", 0.5, 1, 0.5)
            GameTooltip:Show()
        end
    end)

    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        -- Hide when leaving the indicator (if not over an item button)
        C_Timer.After(0.05, function()
            if not CategoryDropIndicator:IsOverValidButton() then
                CategoryDropIndicator:Hide()
            end
        end)
    end)

    frame:Hide()
    indicator = frame
    return frame
end



-------------------------------------------------
-- Public API
-------------------------------------------------

function CategoryDropIndicator:Show(hoveredButton)
    if not hoveredButton or not hoveredButton.containerFrame then
        return
    end

    local categoryId = hoveredButton.categoryId
    if not categoryId or categoryId == "Empty" or categoryId == "Home" or categoryId == "Recent" or categoryId == "Soul" then
        return
    end

    -- Need layout coordinates
    if not hoveredButton.layoutX or not hoveredButton.layoutY then
        return
    end

    local ind = CreateIndicator()
    local container = hoveredButton.containerFrame
    local iconSize = hoveredButton.iconSize or 36

    -- Size the indicator bar (same width as item, fixed height)
    local barHeight = 14
    local barGap = 2  -- Gap between bar and item
    ind:SetSize(iconSize, barHeight)

    -- Parent to the container
    ind:SetParent(container)
    ind:SetFrameStrata("TOOLTIP")
    ind:SetFrameLevel(200)

    -- Position indicator ABOVE the hovered item
    ind:ClearAllPoints()
    ind:SetPoint("BOTTOMLEFT", container, "TOPLEFT", hoveredButton.layoutX, hoveredButton.layoutY + barGap)

    currentCategoryId = categoryId
    currentHoveredButton = hoveredButton
    currentContainer = container
    ind:Show()
end

function CategoryDropIndicator:Hide()
    if indicator then
        indicator:Hide()
        indicator:SetParent(UIParent)
    end

    currentCategoryId = nil
    currentHoveredButton = nil
    currentContainer = nil
end

function CategoryDropIndicator:IsShown()
    return indicator and indicator:IsShown()
end

function CategoryDropIndicator:GetCategoryId()
    return currentCategoryId
end

function CategoryDropIndicator:GetHoveredButton()
    return currentHoveredButton
end

-- Check if mouse is over a valid item button or the indicator itself
function CategoryDropIndicator:IsOverValidButton()
    if indicator and indicator:IsMouseOver() then
        return true
    end
    if currentHoveredButton and currentHoveredButton:IsMouseOver() then
        return true
    end
    return false
end

-- Check if button is in the bank (not bags)
local function IsBankButton(button)
    if not button.containerFrame then return false end
    local containerName = button.containerFrame:GetName()
    -- Bank container is named "GudaBankContainer", bag container is "GudaBagsSecureContainer"
    return containerName == "GudaBankContainer"
end

-- Called when hovering over an item button while dragging
function CategoryDropIndicator:OnItemButtonEnter(button)
    if not self:CursorHasItem() then return end
    if not button.categoryId or button.categoryId == "Empty" or button.categoryId == "Home" or button.categoryId == "Recent" or button.categoryId == "Soul" then return end

    -- Don't show indicator for bank items - allow normal swap behavior
    if IsBankButton(button) then return end

    -- Don't show indicator if dragged item is already in this category
    if self:IsDraggedItemInCategory(button.categoryId) then return end

    self:Show(button)
end

-- Called when cursor moves within the item button (to update position)
function CategoryDropIndicator:OnItemButtonUpdate(button)
    if not self:CursorHasItem() then
        self:Hide()
        return
    end
    if not button.categoryId or button.categoryId == "Empty" or button.categoryId == "Home" or button.categoryId == "Recent" or button.categoryId == "Soul" then return end

    -- Don't show indicator for bank items - allow normal swap behavior
    if IsBankButton(button) then
        self:Hide()
        return
    end

    -- Don't show indicator if dragged item is already in this category
    if self:IsDraggedItemInCategory(button.categoryId) then
        self:Hide()
        return
    end

    -- Don't update if cursor is over the indicator itself
    if indicator and indicator:IsMouseOver() then
        return
    end

    -- Only update if button changed
    if currentHoveredButton == button then
        return
    end

    self:Show(button)
end

-- Called when leaving an item button
function CategoryDropIndicator:OnItemButtonLeave()
    -- Delay hide to check if cursor moved to indicator
    C_Timer.After(0.05, function()
        if not self:IsOverValidButton() then
            self:Hide()
        end
    end)
end

function CategoryDropIndicator:HandleDrop()
    local infoType, itemID, itemLink = GetCursorInfo()

    if infoType ~= "item" or not itemID then
        self:Hide()
        return false
    end

    if not currentCategoryId then
        self:Hide()
        return false
    end

    -- Don't allow dropping to Empty category
    if currentCategoryId == "Empty" then
        ClearCursor()
        self:Hide()
        return false
    end

    -- Check if this is a cross-container drop (bank to bag)
    -- If bank is open and indicator is on a bag item, move item to bag first
    local BankScanner = ns:GetModule("BankScanner")
    local isBankOpen = BankScanner and BankScanner:IsBankOpen()

    if isBankOpen and currentHoveredButton and currentHoveredButton.containerFrame then
        local containerName = currentHoveredButton.containerFrame:GetName()
        if containerName == "GudaBagsSecureContainer" then
            -- Assign item to category FIRST (before moving to bag)
            -- This ensures the item won't be categorized as "Recent"
            local CategoryManager = ns:GetModule("CategoryManager")
            if CategoryManager then
                CategoryManager:AssignItemToCategory(itemID, currentCategoryId)
            end

            -- Find first empty bag slot and place item there
            for bagID = 0, NUM_BAG_SLOTS do
                local numSlots = C_Container.GetContainerNumSlots(bagID)
                for slot = 1, numSlots do
                    local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
                    if not itemInfo then
                        -- Empty slot found - place item here (moves from bank to bag)
                        C_Container.PickupContainerItem(bagID, slot)
                        self:Hide()
                        return true
                    end
                end
            end
            -- No empty slot found
            ClearCursor()
            self:Hide()
            return false
        end
    end

    -- Regular drop (within same container) - just assign category
    local CategoryManager = ns:GetModule("CategoryManager")
    if CategoryManager then
        local success = CategoryManager:AssignItemToCategory(itemID, currentCategoryId)
        if success then
            -- Clear cursor (SaveCategories already fires CATEGORIES_UPDATED)
            ClearCursor()
        end
    end

    self:Hide()
    return true
end

-- Check if cursor has an item (for showing/hiding indicator)
function CategoryDropIndicator:CursorHasItem()
    local infoType = GetCursorInfo()
    return infoType == "item"
end

-- Check if the dragged item is already in the specified category
function CategoryDropIndicator:IsDraggedItemInCategory(categoryId)
    local infoType, itemID = GetCursorInfo()
    if infoType ~= "item" or not itemID then return false end

    local CategoryManager = ns:GetModule("CategoryManager")
    if not CategoryManager then return false end

    -- Get the item's current category
    -- We need itemData to categorize, so fetch it from the cursor item
    local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType,
          itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(itemID)

    if not itemName then return false end

    -- Build minimal itemData for categorization
    local itemData = {
        itemID = itemID,
        name = itemName,
        link = itemLink,
        quality = itemQuality,
        itemType = itemType,
        itemSubType = itemSubType,
        equipSlot = itemEquipLoc,
    }

    local currentCategory = CategoryManager:CategorizeItem(itemData)
    return currentCategory == categoryId
end
