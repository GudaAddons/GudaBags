local addonName, ns = ...

local ItemButton = {}
ns:RegisterModule("ItemButton", ItemButton)

local Constants = ns.Constants
local Database = ns:GetModule("Database")
local Tooltip = ns:GetModule("Tooltip")

-- Phase 1: Use Blizzard's optimized CreateObjectPool API
local buttonPool = nil  -- Lazy initialized
local buttonIndex = 0

-- Full reset function for pool (called on Release)
local function ResetButton(pool, button)
    button:Hide()
    button.wrapper:Hide()
    button.wrapper:ClearAllPoints()
    button.itemData = nil
    button.owner = nil
    button.isEmptySlotButton = nil
    button.categoryId = nil
    button.iconSize = nil
    button.layoutX = nil
    button.layoutY = nil
    button.layoutIndex = nil
    button.containerFrame = nil

    -- Clear visual state to prevent texture bleeding
    SetItemButtonTexture(button, nil)
    SetItemButtonCount(button, 0)
    SetItemButtonDesaturated(button, false)
    if button.border then button.border:Hide() end
    if button.lockOverlay then button.lockOverlay:Hide() end
    if button.unusableOverlay then button.unusableOverlay:Hide() end
    if button.junkOverlay then button.junkOverlay:Hide() end
    if button.junkIcon then button.junkIcon:Hide() end
    if button.trackedIcon then button.trackedIcon:Hide() end
    if button.trackedIconShadow then button.trackedIconShadow:Hide() end
    if button.questIcon then button.questIcon:Hide() end
    if button.questStarterIcon then button.questStarterIcon:Hide() end
    if button.cooldown then button.cooldown:Clear() end
end

local BASE_BUTTON_SIZE = 37

local function ApplyFontSize(button, fontSize)
    fontSize = fontSize or Database:GetSetting("iconFontSize")
    if button.Count then
        button.Count:SetFont(Constants.FONTS.DEFAULT, fontSize, "OUTLINE")
        button.Count:ClearAllPoints()
        button.Count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 1)
        button.Count:SetJustifyH("RIGHT")
    end
end

local function IsTool(itemName)
    if not itemName then return false end
    local nameLower = string.lower(itemName)

    if string.find(nameLower, "mining pick") then return true end
    if string.find(nameLower, "fishing pole") then return true end
    if string.find(nameLower, "fishing rod") then return true end
    if string.find(nameLower, "skinning knife") then return true end
    if string.find(nameLower, "blacksmith hammer") then return true end
    if string.find(nameLower, "jumper cables") then return true end
    if string.find(nameLower, "gnomish") then return true end
    if string.find(nameLower, "goblin") then return true end
    if string.find(nameLower, "arclight spanner") then return true end
    if string.find(nameLower, "gyromatic") then return true end

    return false
end

local function IsJunkItem(itemData)
    if not itemData then return false end

    -- Profession tools are never junk
    if IsTool(itemData.name) then
        return false
    end

    -- Gray quality items are always junk (consistent with Category View isJunk rule)
    if itemData.quality == 0 then
        return true
    end

    -- White quality equipment (only if setting is enabled)
    if itemData.quality == 1 then
        local Database = ns:GetModule("Database")
        local whiteItemsJunk = Database and Database:GetSetting("whiteItemsJunk") or false

        if not whiteItemsJunk then
            return false  -- Setting is off, white items are never junk
        end

        local isEquipment = itemData.itemType == "Armor" or itemData.itemType == "Weapon"
        if isEquipment then
            -- Valuable slots (trinket, ring, neck, shirt, tabard) are never junk
            local equipSlot = itemData.equipSlot
            if equipSlot and Constants.VALUABLE_EQUIP_SLOTS[equipSlot] then
                return false
            end

            local isTool = IsTool(itemData.name)
            if isTool then
                return false
            end
            -- Check for special properties (unique, use, equip effects, green/yellow text)
            -- Use cached value from ItemScanner to avoid tooltip rescans
            if itemData.hasSpecialProperties then
                return false
            end
            return true
        end
    end

    return false
end

local function CreateBorder(button)
    local BORDER_THICKNESS = Constants.ICON.BORDER_THICKNESS

    local borderFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
    borderFrame:SetPoint("TOPLEFT", button, "TOPLEFT", -BORDER_THICKNESS, BORDER_THICKNESS)
    borderFrame:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", BORDER_THICKNESS, -BORDER_THICKNESS)
    borderFrame:SetFrameLevel(button:GetFrameLevel() + 1)

    borderFrame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    borderFrame:Hide()

    borderFrame.SetVertexColor = function(self, r, g, b, a)
        self:SetBackdropBorderColor(r, g, b, a)
    end

    return borderFrame
end

local function CreateButton(parent)
    buttonIndex = buttonIndex + 1
    local name = "GudaBagsItemButton" .. buttonIndex

    -- Wrapper frame holds bag ID for the template's click handler
    local wrapper = CreateFrame("Frame", name .. "Wrapper", parent)
    wrapper:SetSize(37, 37)

    -- ContainerFrameItemButtonTemplate provides secure item click handling
    local button = CreateFrame("ItemButton", name, wrapper, "ContainerFrameItemButtonTemplate")
    button:SetSize(37, 37)
    button:SetAllPoints(wrapper)
    button.wrapper = wrapper
    button.currentSize = nil  -- Track current size to avoid redundant SetSize calls

    -- Store reference to easily resize wrapper with button
    wrapper.button = button

    -- Hide template's built-in visual elements (we use our own)
    local normalTex = button:GetNormalTexture()
    if normalTex then
        normalTex:SetTexture(nil)
        normalTex:Hide()
    end

    if button.IconBorder then button.IconBorder:Hide() end
    if button.IconOverlay then button.IconOverlay:Hide() end
    if button.NormalTexture then
        button.NormalTexture:SetTexture(nil)
        button.NormalTexture:Hide()
    end
    if button.NewItemTexture then button.NewItemTexture:Hide() end
    if button.BattlepayItemTexture then button.BattlepayItemTexture:Hide() end

    -- Hide global texture created by template XML
    local globalNormal = _G[name .. "NormalTexture"]
    if globalNormal then
        globalNormal:SetTexture(nil)
        globalNormal:Hide()
    end

    -- Custom slot background (extended to match item icon visual size)
    local slotBackground = button:CreateTexture(nil, "BACKGROUND", nil, -1)
    slotBackground:SetPoint("TOPLEFT", button, "TOPLEFT", -9, 9)
    slotBackground:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 9, -9)
    slotBackground:SetTexture("Interface\\Buttons\\UI-EmptySlot")
    button.slotBackground = slotBackground

    -- Item icon fills button completely to match empty slot size
    local icon = button.icon or button.Icon or _G[name .. "IconTexture"]
    if icon then
        icon:ClearAllPoints()
        icon:SetAllPoints(button)
        icon:SetTexCoord(0, 1, 0, 1)
    end

    -- Quality border (our custom one, not template's)
    local border = CreateBorder(button)
    button.border = border

    -- Custom highlight
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")
    button.highlight = highlight

    -- Cooldown frame
    local cooldown = CreateFrame("Cooldown", name .. "Cooldown", button, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    cooldown:SetDrawEdge(false)
    button.cooldown = cooldown

    -- Lock overlay for locked items
    local lockOverlay = button:CreateTexture(nil, "OVERLAY", nil, 1)
    lockOverlay:SetAllPoints()
    lockOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    lockOverlay:SetVertexColor(0, 0, 0, 0.5)
    lockOverlay:Hide()
    button.lockOverlay = lockOverlay

    -- Unusable item overlay
    local unusableOverlay = button:CreateTexture(nil, "OVERLAY", nil, 2)
    unusableOverlay:SetAllPoints()
    unusableOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    unusableOverlay:SetVertexColor(1, 0.1, 0.1, 0.4)
    unusableOverlay:Hide()
    button.unusableOverlay = unusableOverlay

    -- Junk item overlay (gray)
    local junkOverlay = button:CreateTexture(nil, "OVERLAY", nil, 2)
    junkOverlay:SetAllPoints()
    junkOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
    junkOverlay:SetVertexColor(0.3, 0.3, 0.3, 0.6)
    junkOverlay:Hide()
    button.junkOverlay = junkOverlay

    -- Junk coin icon
    local junkIcon = button:CreateTexture(nil, "OVERLAY", nil, 3)
    junkIcon:SetSize(12, 12)
    junkIcon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    junkIcon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
    junkIcon:Hide()
    button.junkIcon = junkIcon

    -- Tracked/favorite icon shadow (for darker stroke effect)
    local trackedIconShadow = button:CreateTexture(nil, "OVERLAY", nil, 2)
    trackedIconShadow:SetSize(14, 14)
    trackedIconShadow:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    trackedIconShadow:SetTexture("Interface\\AddOns\\GudaBags\\Assets\\fav.png")
    trackedIconShadow:SetVertexColor(0, 0, 0, 1)
    trackedIconShadow:Hide()
    button.trackedIconShadow = trackedIconShadow

    -- Tracked/favorite icon (top right corner)
    local trackedIcon = button:CreateTexture(nil, "OVERLAY", nil, 3)
    trackedIcon:SetSize(12, 12)
    trackedIcon:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    trackedIcon:SetTexture("Interface\\AddOns\\GudaBags\\Assets\\fav.png")
    trackedIcon:Hide()
    button.trackedIcon = trackedIcon

    -- Quest starter icon (top left corner) - exclamation mark for quest starter items
    -- Use a frame container to ensure it draws above the border
    local questStarterFrame = CreateFrame("Frame", nil, button)
    questStarterFrame:SetFrameLevel(button:GetFrameLevel() + 5)
    questStarterFrame:SetSize(14, 14)
    questStarterFrame:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 2)
    local questStarterIcon = questStarterFrame:CreateTexture(nil, "OVERLAY")
    questStarterIcon:SetAllPoints()
    questStarterIcon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    questStarterFrame:Hide()
    button.questStarterIcon = questStarterFrame

    -- Quest item icon (top left corner) - question mark for regular quest items
    -- Use a frame container to ensure it draws above the border
    local questIconFrame = CreateFrame("Frame", nil, button)
    questIconFrame:SetFrameLevel(button:GetFrameLevel() + 5)
    questIconFrame:SetSize(14, 14)
    questIconFrame:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 2)
    local questIcon = questIconFrame:CreateTexture(nil, "OVERLAY")
    questIcon:SetAllPoints()
    questIcon:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
    questIconFrame:Hide()
    button.questIcon = questIconFrame

    -- Replace tooltip scripts (not hook, to prevent template's SetBagItem from running first)
    button:SetScript("OnEnter", function(self)
        -- Don't show tooltip for Empty/Soul pseudo-item buttons
        if not self.isEmptySlotButton and not (self.itemData and self.itemData.isEmptySlots) then
            Tooltip:ShowForItem(self)
        end

        -- Show drag-drop indicator if cursor has item and this is a category view item
        if self.categoryId and self.containerFrame then
            local cursorType = GetCursorInfo()
            if cursorType == "item" then
                local CategoryDropIndicator = ns:GetModule("CategoryDropIndicator")
                if CategoryDropIndicator then
                    CategoryDropIndicator:OnItemButtonEnter(self)
                end
            end
        end
    end)

    button:SetScript("OnLeave", function(self)
        Tooltip:Hide()

        -- Hide drag-drop indicator
        local CategoryDropIndicator = ns:GetModule("CategoryDropIndicator")
        if CategoryDropIndicator then
            CategoryDropIndicator:OnItemButtonLeave()
        end
    end)

    -- Update indicator position while hovering with dragged item
    -- Only runs when indicator is visible AND mouse is over this button
    button:SetScript("OnUpdate", function(self)
        if self.categoryId and self.containerFrame and self:IsMouseOver() then
            local CategoryDropIndicator = ns:GetModule("CategoryDropIndicator")
            if CategoryDropIndicator and CategoryDropIndicator:IsShown() then
                CategoryDropIndicator:OnItemButtonUpdate(self)
            end
        end
    end)

    -- Disable template's tooltip update mechanism
    button.UpdateTooltip = nil

    -- Helper function to find current first empty slot for pseudo-items
    -- For Soul pseudo-items, find empty slot in soul bags
    -- For Empty pseudo-items, find empty slot in regular bags
    local function FindCurrentEmptySlot(btn)
        if not btn.isEmptySlotButton and not (btn.itemData and btn.itemData.isEmptySlots) then
            return nil, nil
        end

        -- Check if this is a Soul category pseudo-item
        local isSoulCategory = btn.categoryId == "Soul" or (btn.itemData and btn.itemData.isSoulSlots)

        -- Use BagClassifier for accurate bag type detection
        local BagClassifier = ns:GetModule("BagFrame.BagClassifier")

        -- Scan bags to find first empty slot
        for bagID = 0, NUM_BAG_SLOTS do
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            if numSlots and numSlots > 0 then
                -- Check bag type using BagClassifier
                local bagType = BagClassifier and BagClassifier:GetBagType(bagID) or "regular"
                local isSoulBag = (bagType == "soul")

                -- Match bag type to category
                local shouldSearchThisBag = false
                if isSoulCategory then
                    shouldSearchThisBag = isSoulBag
                else
                    -- Empty category: regular bags only (backpack or regular bag type)
                    shouldSearchThisBag = (bagID == 0) or (bagType == "regular")
                end

                if shouldSearchThisBag then
                    for slotID = 1, numSlots do
                        local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
                        if not itemInfo then
                            -- Found empty slot
                            return bagID, slotID
                        end
                    end
                end
            end
        end

        return nil, nil
    end

    -- Update bagID/slotID for pseudo-item before click/drag
    local function UpdatePseudoItemSlot(btn)
        if not btn.isEmptySlotButton and not (btn.itemData and btn.itemData.isEmptySlots) then
            return false
        end

        local newBagID, newSlotID = FindCurrentEmptySlot(btn)
        if newBagID and newSlotID then
            btn.wrapper:SetID(newBagID)
            btn:SetID(newSlotID)
            if btn.itemData then
                btn.itemData.bagID = newBagID
                btn.itemData.slot = newSlotID
            end
            return true
        end

        return false  -- No empty slot found
    end

    -- Ctrl+Alt+Click to track/untrack items
    button:HookScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" and IsControlKeyDown() and IsAltKeyDown() then
            if self.itemData and self.itemData.itemID then
                local TrackedBar = ns:GetModule("TrackedBar")
                if TrackedBar then
                    TrackedBar:ToggleTrackItem(self.itemData.itemID)
                end
            end
        end
    end)

    -- Helper function to check if dragged item is in same category as target
    local function IsSameCategoryDrop(targetButton)
        if not targetButton.categoryId or not targetButton.itemData then
            return false
        end

        local cursorType, cursorItemID = GetCursorInfo()
        if cursorType ~= "item" or not cursorItemID then
            return false
        end

        local CategoryManager = ns:GetModule("CategoryManager")
        if not CategoryManager then return false end

        -- Build minimal itemData for the dragged item
        local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType,
              itemStackCount, itemEquipLoc = GetItemInfo(cursorItemID)
        if not itemName then return false end

        local draggedItemData = {
            itemID = cursorItemID,
            name = itemName,
            link = itemLink,
            quality = itemQuality,
            itemType = itemType,
            itemSubType = itemSubType,
            equipSlot = itemEquipLoc,
        }

        local draggedCategory = CategoryManager:CategorizeItem(draggedItemData)
        return draggedCategory == targetButton.categoryId
    end

    -- Prevent swapping via click within the same category
    -- Also update pseudo-item slots to use current empty slot
    button:HookScript("PreClick", function(self, mouseButton)
        -- For pseudo-item buttons, update to current empty slot BEFORE secure handler runs
        if self.isEmptySlotButton or (self.itemData and self.itemData.isEmptySlots) then
            local cursorType = GetCursorInfo()
            if cursorType == "item" then
                UpdatePseudoItemSlot(self)
            end
            return  -- Don't check same-category for pseudo-items
        end

        if mouseButton == "LeftButton" and IsSameCategoryDrop(self) then
            ClearCursor()
        end
    end)

    -- Custom OnReceiveDrag to prevent swapping items within the same category
    -- Also handles pseudo-item buttons to place items in current empty slot
    -- Store original handler reference
    local originalReceiveDrag = button:GetScript("OnReceiveDrag")
    button:SetScript("OnReceiveDrag", function(self)
        -- For pseudo-item buttons (Empty/Soul), find current empty slot
        if self.isEmptySlotButton or (self.itemData and self.itemData.isEmptySlots) then
            local cursorType = GetCursorInfo()
            if cursorType == "item" then
                local newBagID, newSlotID = FindCurrentEmptySlot(self)
                if newBagID and newSlotID then
                    -- Place item in the current first empty slot
                    C_Container.PickupContainerItem(newBagID, newSlotID)
                end
            end
            return
        end

        -- If same category drop, prevent the swap
        if IsSameCategoryDrop(self) then
            ClearCursor()
            return
        end

        -- Allow normal swap (different categories or non-category view)
        if originalReceiveDrag then
            originalReceiveDrag(self)
        else
            -- Fallback: manually do the pickup/place
            local bagID = self:GetParent():GetID()
            local slotID = self:GetID()
            if bagID and slotID and bagID >= 0 then
                C_Container.PickupContainerItem(bagID, slotID)
            end
        end
    end)

    return button
end

function ItemButton:Acquire(parent)
    -- Lazy initialize pool on first use
    if not buttonPool then
        buttonPool = CreateObjectPool(
            function() return CreateButton(parent) end,
            ResetButton
        )
    end

    local button = buttonPool:Acquire()
    button.wrapper:SetParent(parent)
    button.wrapper:Show()
    button:Show()
    button.owner = parent
    return button
end

function ItemButton:Release(button)
    if not buttonPool then return end

    -- Check if button is active before releasing (avoid double-release error)
    local isActive = false
    for activeButton in buttonPool:EnumerateActive() do
        if activeButton == button then
            isActive = true
            break
        end
    end
    if not isActive then return end

    -- Minimal cleanup - visual reset happens in SetItem (lazy cleanup)
    button.currentSize = nil

    -- Release to pool (ResetButton callback handles hide/clear/anchors)
    buttonPool:Release(button)
end

function ItemButton:ReleaseAll(owner)
    if not buttonPool then return end

    -- If owner specified, we need to iterate and release matching buttons
    if owner then
        -- Collect buttons to release (can't modify during iteration)
        local toRelease = {}
        for button in buttonPool:EnumerateActive() do
            if button.owner == owner then
                table.insert(toRelease, button)
            end
        end
        for _, button in ipairs(toRelease) do
            self:Release(button)
        end
    else
        -- Release all - pool's ReleaseAll handles cleanup via ResetButton callback
        -- Skip visual reset here - will be done in SetItem when button is reused
        buttonPool:ReleaseAll()
    end
end

-- Cached settings for batch updates (set by SetItemBatch or refreshed on demand)
local cachedSettings = nil
local cachedSettingsFrame = 0  -- Frame number when cached

local function GetCachedSettings()
    local currentFrame = GetTime()
    -- Cache settings for 0.1 second to avoid repeated lookups during batch updates
    if not cachedSettings or (currentFrame - cachedSettingsFrame) > 0.1 then
        cachedSettings = {
            iconSize = Database:GetSetting("iconSize"),
            bgAlpha = Database:GetSetting("bgAlpha") / 100,
            iconFontSize = Database:GetSetting("iconFontSize"),
            grayoutJunk = Database:GetSetting("grayoutJunk"),
            equipmentBorders = Database:GetSetting("equipmentBorders"),
            otherBorders = Database:GetSetting("otherBorders"),
            markUnusableItems = Database:GetSetting("markUnusableItems"),
        }
        cachedSettingsFrame = currentFrame
    end
    return cachedSettings
end

-- Invalidate cached settings (call when settings change)
function ItemButton:InvalidateSettingsCache()
    cachedSettings = nil
end

function ItemButton:SetItem(button, itemData, size, isReadOnly)
    -- Reset visual state from previous item (lazy cleanup)
    -- These elements might not be explicitly set below
    if button.trackedIcon then button.trackedIcon:Hide() end
    if button.trackedIconShadow then button.trackedIconShadow:Hide() end
    if button.questIcon then button.questIcon:Hide() end
    if button.questStarterIcon then button.questStarterIcon:Hide() end
    if button.junkIcon then button.junkIcon:Hide() end

    button.itemData = itemData
    button.isReadOnly = isReadOnly or false

    local settings = GetCachedSettings()
    size = size or settings.iconSize

    -- Only resize if size actually changed
    if button.currentSize ~= size then
        button:SetSize(size, size)
        button.wrapper:SetSize(size, size)
        button.currentSize = size
    end

    button.slotBackground:SetVertexColor(0.5, 0.5, 0.5, settings.bgAlpha)

    ApplyFontSize(button, settings.iconFontSize)

    -- Special handling for "Empty" and "Soul" category pseudo-items
    if itemData and itemData.isEmptySlots then
        -- Display texture with count
        SetItemButtonTexture(button, itemData.texture or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
        SetItemButtonCount(button, itemData.emptyCount or 0)

        -- Gray out both Empty and Soul pseudo-items for consistent appearance
        SetItemButtonDesaturated(button, true)

        -- Hide all overlays
        button.border:Hide()
        button.unusableOverlay:Hide()
        button.junkOverlay:Hide()
        button.lockOverlay:Hide()
        if button.cooldown then button.cooldown:Clear() end

        -- Mark this button as empty slot handler
        button.isEmptySlotButton = true

        -- Set real bagID/slot so template's click handler places items correctly
        -- itemData now contains real bagID/slot of first empty slot
        button.wrapper:SetID(itemData.bagID)
        button:SetID(itemData.slot)

        return
    end

    if itemData then
        -- Set IDs for ContainerFrameItemButtonTemplate's secure click handler
        -- Use invalid IDs for read-only mode to prevent interactions
        if isReadOnly then
            button.wrapper:SetID(0)
            button:SetID(0)
        else
            button.wrapper:SetID(itemData.bagID)
            button:SetID(itemData.slot)
        end

        -- Use template's built-in functions for icon and count
        SetItemButtonTexture(button, itemData.texture)
        SetItemButtonCount(button, itemData.count)

        -- Keep template's visual elements hidden (we use our own)
        if button.IconBorder then button.IconBorder:Hide() end
        if button.IconOverlay then button.IconOverlay:Hide() end

        -- Apply gray overlay for junk items
        if settings.grayoutJunk and IsJunkItem(itemData) then
            button.junkOverlay:Show()
        else
            button.junkOverlay:Hide()
        end

        -- Quality border (quest items override with golden border)
        local isEquipment = itemData.itemType == "Armor" or itemData.itemType == "Weapon"
        local showBorder = isEquipment and settings.equipmentBorders or (not isEquipment and settings.otherBorders)

        -- Quest items always show border with quest color
        if itemData.isQuestItem then
            local questColor = itemData.isQuestStarter and Constants.COLORS.QUEST_STARTER or Constants.COLORS.QUEST
            button.border:SetVertexColor(questColor[1], questColor[2], questColor[3], 1)
            button.border:Show()
        elseif showBorder and itemData.quality ~= nil then
            local color = Constants.QUALITY_COLORS[itemData.quality]
            if color then
                button.border:SetVertexColor(color[1], color[2], color[3], 1)
                button.border:Show()
            else
                button.border:Hide()
            end
        else
            button.border:Hide()
        end

        if itemData.locked then
            button.lockOverlay:Show()
            SetItemButtonDesaturated(button, true)
        else
            button.lockOverlay:Hide()
            SetItemButtonDesaturated(button, false)
        end

        -- Update cooldown
        if button.cooldown and not isReadOnly then
            local start, duration, enable = C_Container.GetContainerItemCooldown(itemData.bagID, itemData.slot)
            if start and duration and duration > 0 then
                button.cooldown:SetCooldown(start, duration)
            else
                button.cooldown:Clear()
            end
        elseif button.cooldown then
            button.cooldown:Clear()
        end

        if settings.markUnusableItems and itemData.isUsable == false then
            button.unusableOverlay:Show()
        else
            button.unusableOverlay:Hide()
        end

        if button.junkIcon then
            if IsJunkItem(itemData) then
                button.junkIcon:Show()
            else
                button.junkIcon:Hide()
            end
        end

        -- Quest item icons (starter = exclamation, regular = question mark)
        if button.questStarterIcon then
            if itemData.isQuestStarter then
                button.questStarterIcon:Show()
            else
                button.questStarterIcon:Hide()
            end
        end
        if button.questIcon then
            if itemData.isQuestItem and not itemData.isQuestStarter then
                button.questIcon:Show()
            else
                button.questIcon:Hide()
            end
        end

        -- Tracked item icon
        if button.trackedIcon then
            local TrackedBar = ns:GetModule("TrackedBar")
            if TrackedBar and TrackedBar:IsTracked(itemData.itemID) then
                button.trackedIcon:Show()
                if button.trackedIconShadow then
                    button.trackedIconShadow:Show()
                end
            else
                button.trackedIcon:Hide()
                if button.trackedIconShadow then
                    button.trackedIconShadow:Hide()
                end
            end
        end
    else
        button.wrapper:SetID(0)
        button:SetID(0)

        SetItemButtonTexture(button, nil)
        SetItemButtonCount(button, 0)
        button.icon:SetVertexColor(1, 1, 1, 1)
        button.border:Hide()
        button.lockOverlay:Hide()
        button.unusableOverlay:Hide()
        if button.junkOverlay then
            button.junkOverlay:Hide()
        end
        if button.junkIcon then
            button.junkIcon:Hide()
        end
        if button.questIcon then
            button.questIcon:Hide()
        end
        if button.questStarterIcon then
            button.questStarterIcon:Hide()
        end
        if button.trackedIcon then
            button.trackedIcon:Hide()
        end
        if button.trackedIconShadow then
            button.trackedIconShadow:Hide()
        end
        if button.cooldown then
            button.cooldown:Clear()
        end
    end
end

function ItemButton:SetEmpty(button, bagID, slot, size, isReadOnly)
    button.itemData = {bagID = bagID, slot = slot}
    button.isReadOnly = isReadOnly or false

    -- Set IDs for ContainerFrameItemButtonTemplate's secure click handler
    -- Use invalid IDs for read-only mode to prevent interactions
    if isReadOnly then
        button.wrapper:SetID(0)
        button:SetID(0)
    else
        button.wrapper:SetID(bagID)
        button:SetID(slot)
    end

    local settings = GetCachedSettings()
    size = size or settings.iconSize

    -- Only resize if size actually changed
    if button.currentSize ~= size then
        button:SetSize(size, size)
        button.wrapper:SetSize(size, size)
        button.currentSize = size
    end

    button.slotBackground:SetVertexColor(0.5, 0.5, 0.5, settings.bgAlpha)

    SetItemButtonTexture(button, nil)
    SetItemButtonCount(button, 0)
    button.border:Hide()
    button.lockOverlay:Hide()
    button.unusableOverlay:Hide()
    if button.junkOverlay then
        button.junkOverlay:Hide()
    end
    if button.junkIcon then
        button.junkIcon:Hide()
    end
    if button.questIcon then
        button.questIcon:Hide()
    end
    if button.questStarterIcon then
        button.questStarterIcon:Hide()
    end
    if button.trackedIcon then
        button.trackedIcon:Hide()
    end
    if button.trackedIconShadow then
        button.trackedIconShadow:Hide()
    end
    if button.cooldown then
        button.cooldown:Clear()
    end
end

function ItemButton:UpdateSlotAlpha(alpha)
    if not buttonPool then return end
    for button in buttonPool:EnumerateActive() do
        if button.slotBackground then
            button.slotBackground:SetVertexColor(0.5, 0.5, 0.5, alpha)
        end
    end
end

function ItemButton:UpdateFontSize()
    if not buttonPool then return end
    for button in buttonPool:EnumerateActive() do
        ApplyFontSize(button)
    end
end

function ItemButton:GetActiveButtons()
    -- Return iterator for active buttons
    if not buttonPool then return function() end end
    return buttonPool:EnumerateActive()
end

function ItemButton:HighlightBagSlots(bagID)
    if not buttonPool then return end
    local bgAlpha = Database:GetSetting("bgAlpha") / 100

    for button in buttonPool:EnumerateActive() do
        if button.itemData and button.itemData.bagID == bagID then
            button:SetAlpha(1.0)
            if button.slotBackground then
                button.slotBackground:SetVertexColor(0.5, 0.5, 0.5, bgAlpha)
            end
        else
            button:SetAlpha(0.25)
            if button.slotBackground then
                button.slotBackground:SetVertexColor(0.5, 0.5, 0.5, bgAlpha * 0.25)
            end
        end
    end
end

function ItemButton:ClearHighlightedSlots(parentFrame)
    if not buttonPool then return end
    local SearchBar = ns:GetModule("SearchBar")
    local searchText = (SearchBar and parentFrame) and SearchBar:GetSearchText(parentFrame) or ""
    local bgAlpha = Database:GetSetting("bgAlpha") / 100

    for button in buttonPool:EnumerateActive() do
        if searchText ~= "" then
            -- Respect search filter
            if button.itemData and SearchBar:ItemMatchesSearch(button.itemData, searchText) then
                button:SetAlpha(1.0)
                if button.slotBackground then
                    button.slotBackground:SetVertexColor(0.5, 0.5, 0.5, bgAlpha)
                end
            else
                button:SetAlpha(0.3)
                if button.slotBackground then
                    button.slotBackground:SetVertexColor(0.5, 0.5, 0.5, bgAlpha * 0.3)
                end
            end
        else
            button:SetAlpha(1.0)
            if button.slotBackground then
                button.slotBackground:SetVertexColor(0.5, 0.5, 0.5, bgAlpha)
            end
        end
    end
end

-- Update lock state for a specific item (called on ITEM_LOCK_CHANGED)
function ItemButton:UpdateLockForItem(bagID, slotID)
    if not buttonPool then return end

    for button in buttonPool:EnumerateActive() do
        if button.itemData and button.itemData.bagID == bagID and button.itemData.slot == slotID then
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
            local isLocked = itemInfo and itemInfo.isLocked or false

            -- Update cached state
            button.itemData.locked = isLocked

            -- Update visual state
            if isLocked then
                button.lockOverlay:Show()
                SetItemButtonDesaturated(button, true)
            else
                button.lockOverlay:Hide()
                SetItemButtonDesaturated(button, false)
            end
            return  -- Found the button, done
        end
    end
end

-- Invalidate settings cache when relevant settings change
local Events = ns:GetModule("Events")
if Events then
    Events:Register("SETTING_CHANGED", function(event, key, value)
        -- Invalidate cache for any setting that affects item buttons
        if key == "iconSize" or key == "bgAlpha" or key == "iconFontSize"
            or key == "grayoutJunk" or key == "equipmentBorders"
            or key == "otherBorders" or key == "markUnusableItems" then
            ItemButton:InvalidateSettingsCache()
        end
    end, ItemButton)
end

-- Debug: Get pool statistics
function ItemButton:GetPoolStats()
    if not buttonPool then
        return { active = 0, inactive = 0 }
    end

    local active = buttonPool:GetNumActive() or 0
    local inactive = 0

    -- Count inactive objects if available
    if buttonPool.EnumerateInactive then
        for _ in buttonPool:EnumerateInactive() do
            inactive = inactive + 1
        end
    end

    return {
        active = active,
        inactive = inactive,
        total = active + inactive,
    }
end
