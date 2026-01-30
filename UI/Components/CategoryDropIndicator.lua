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
-- Create Indicator (styled as empty bag slot)
-------------------------------------------------

local function CreateIndicator()
    if indicator then return indicator end

    -- Create a frame that looks like an empty bag slot
    local frame = CreateFrame("Frame", "GudaBagsCategoryDropIndicator", UIParent)
    frame:SetSize(36, 36)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(100)

    -- Slot background (same as ItemButton's slotBackground)
    local slotBg = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    slotBg:SetPoint("TOPLEFT", -1, 1)
    slotBg:SetPoint("BOTTOMRIGHT", 1, -1)
    slotBg:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    slotBg:SetVertexColor(0.5, 1, 0.5, 0.8)  -- Green tint
    frame.slotBg = slotBg

    -- Plus icon overlay
    local plus = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    plus:SetPoint("CENTER", frame, "CENTER", 0, 0)
    plus:SetText("+")
    plus:SetTextColor(0.3, 0.8, 0.3, 1)
    frame.plus = plus

    -- Border highlight
    local border = frame:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetVertexColor(0.3, 0.8, 0.3, 0.5)
    frame.border = border

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

    -- Keep indicator visible when mouse is over it
    frame:SetScript("OnEnter", function(self)
        -- Do nothing, just prevent hiding
    end)

    frame:SetScript("OnLeave", function(self)
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

    -- Size the indicator (full size to match item slots)
    ind:SetSize(iconSize, iconSize)

    -- Parent to the container
    ind:SetParent(container)
    ind:SetFrameStrata("TOOLTIP")
    ind:SetFrameLevel(200)

    -- Position indicator ON the hovered item (overlay)
    ind:ClearAllPoints()
    ind:SetPoint("TOPLEFT", container, "TOPLEFT", hoveredButton.layoutX, hoveredButton.layoutY)

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

-- Called when hovering over an item button while dragging
function CategoryDropIndicator:OnItemButtonEnter(button)
    if not self:CursorHasItem() then return end
    if not button.categoryId or button.categoryId == "Empty" or button.categoryId == "Home" or button.categoryId == "Recent" or button.categoryId == "Soul" then return end

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

    -- Add item to category
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
