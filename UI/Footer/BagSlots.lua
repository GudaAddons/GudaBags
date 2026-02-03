local addonName, ns = ...

local BagSlots = {}
ns:RegisterModule("Footer.BagSlots", BagSlots)

local Constants = ns.Constants

local function GetDatabase()
    return ns:GetModule("Database")
end

local frame = nil
local bagFlyout = nil
local bagFlyoutExpanded = false
local mainBagFrame = nil
local viewingCharacter = nil

local function CreateBagSlotButton(parent, bagID, bagSlotSize)
    local bagSlot = CreateFrame("Button", "GudaBagsBagSlot" .. bagID, parent, "BackdropTemplate")
    bagSlot:SetSize(bagSlotSize, bagSlotSize)
    bagSlot:EnableMouse(true)
    bagSlot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    bagSlot.bagID = bagID

    bagSlot:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    bagSlot:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    bagSlot:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)

    local icon = bagSlot:CreateTexture(nil, "ARTWORK")
    icon:SetSize(bagSlotSize - 2, bagSlotSize - 2)
    icon:SetPoint("CENTER")
    bagSlot.icon = icon

    local highlight = bagSlot:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    bagSlot:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self.bagID == 0 then
            GameTooltip:SetText(BACKPACK_TOOLTIP)
        else
            GameTooltip:SetInventoryItem("player", C_Container.ContainerIDToInventoryID(self.bagID))
        end
        GameTooltip:Show()

        local ItemButton = ns:GetModule("ItemButton")
        if ItemButton then
            ItemButton:HighlightBagSlots(self.bagID)
        end
    end)

    bagSlot:SetScript("OnLeave", function(self)
        GameTooltip:Hide()

        local ItemButton = ns:GetModule("ItemButton")
        if ItemButton then
            ItemButton:ResetAllAlpha()
        end
    end)

    bagSlot:SetScript("OnClick", function(self)
        if self.bagID ~= 0 then
            local invID = C_Container.ContainerIDToInventoryID(self.bagID)
            if IsModifiedClick("PICKUPITEM") then
                PickupBagFromSlot(invID)
            end
        end
    end)

    -- Enable drag for bag swapping
    if bagID ~= 0 then
        bagSlot:RegisterForDrag("LeftButton")
        bagSlot:SetScript("OnDragStart", function(self)
            local invID = C_Container.ContainerIDToInventoryID(self.bagID)
            PickupBagFromSlot(invID)
        end)
        bagSlot:SetScript("OnReceiveDrag", function(self)
            local invID = C_Container.ContainerIDToInventoryID(self.bagID)
            PutItemInBag(invID)
        end)
    end

    return bagSlot
end

local function CreateBagFlyout(parent)
    local numExtraBags = #Constants.BAG_IDS - 1 -- bags 1-4
    local flyout = CreateFrame("Frame", "GudaBagsFlyout", parent, "BackdropTemplate")
    flyout:SetSize(Constants.FLYOUT_BAG_SIZE + 4, Constants.FLYOUT_BAG_SIZE * numExtraBags + 4)
    flyout:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", -5, -9)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetFrameLevel(150)

    flyout:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    flyout:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    flyout:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    flyout.bagSlots = {}

    -- Create bag slots 1-4 (not backpack) stacked vertically, bottom to top
    for i = 2, #Constants.BAG_IDS do
        local bagID = Constants.BAG_IDS[i]
        local slot = CreateBagSlotButton(flyout, bagID, Constants.FLYOUT_BAG_SIZE)

        if i == 2 then
            slot:SetPoint("BOTTOM", flyout, "BOTTOM", 0, 2)
        else
            slot:SetPoint("BOTTOM", flyout.bagSlots[i - 2], "TOP", 0, 0)
        end

        flyout.bagSlots[i - 1] = slot
    end

    flyout:Hide()
    return flyout
end

local function CreateAllBagSlots(parent)
    local bagSlots = {}
    local bagSlotSize = Constants.BAG_SLOT_SIZE

    for i, bagID in ipairs(Constants.BAG_IDS) do
        local bagSlot = CreateBagSlotButton(parent, bagID, bagSlotSize)

        if i == 1 then
            bagSlot:SetPoint("LEFT", parent, "LEFT", 0, 0)
        else
            bagSlot:SetPoint("LEFT", bagSlots[i-1], "RIGHT", 0, 0)
        end

        bagSlots[i] = bagSlot
    end

    return bagSlots
end

function BagSlots:Init(parent)
    -- Store reference to main BagFrame (parent's parent is the main frame)
    mainBagFrame = parent:GetParent()

    frame = CreateFrame("Frame", "GudaBagsBagSlotsFrame", parent)
    frame:SetSize(Constants.BAG_SLOT_SIZE * #Constants.BAG_IDS, Constants.BAG_SLOT_SIZE)
    frame:SetPoint("LEFT", parent, "LEFT", 0, 0)

    -- Create all bag slots (used when Show All Bags is on)
    frame.bagSlots = CreateAllBagSlots(frame)

    -- Create main bag slot for collapsed mode (backpack only)
    local bagSlotSize = Constants.BAG_SLOT_SIZE
    frame.mainBagSlot = CreateBagSlotButton(frame, 0, bagSlotSize)
    frame.mainBagSlot:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.mainBagSlot:Hide()

    -- Add click handler for main bag to toggle flyout
    frame.mainBagSlot:HookScript("OnClick", function(self, button)
        if button == "LeftButton" and not IsModifiedClick() then
            BagSlots:ToggleFlyout()
        end
    end)

    -- Create flyout for extra bags
    bagFlyout = CreateBagFlyout(frame.mainBagSlot)

    return frame
end

function BagSlots:Show()
    if not frame then return end
    frame:Show()

    local showAllBags = GetDatabase():GetSetting("hoverBagline")

    if showAllBags then
        -- Show all bag slots
        for _, bagSlot in ipairs(frame.bagSlots) do
            bagSlot:Show()
        end
        frame.mainBagSlot:Hide()
        if bagFlyout then
            bagFlyout:Hide()
        end
        bagFlyoutExpanded = false
        -- Reset border color when switching modes
        frame.mainBagSlot:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)
    else
        -- Collapsed mode: show only main bag
        for _, bagSlot in ipairs(frame.bagSlots) do
            bagSlot:Hide()
        end
        frame.mainBagSlot:Show()

        if bagFlyout then
            bagFlyout:Hide()
        end
        bagFlyoutExpanded = false

        -- Reset border color when switching modes
        frame.mainBagSlot:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)
    end

    self:Update()
end

function BagSlots:Hide()
    if not frame then return end
    frame:Hide()

    for _, bagSlot in ipairs(frame.bagSlots) do
        bagSlot:Hide()
    end
    if frame.mainBagSlot then
        frame.mainBagSlot:Hide()
    end
    if bagFlyout then
        bagFlyout:Hide()
    end
end

function BagSlots:Update()
    if not frame or not frame.bagSlots then return end

    -- Get cached bags if viewing another character
    local cachedBags = nil
    if viewingCharacter then
        cachedBags = GetDatabase():GetNormalizedBags(viewingCharacter)
    end

    for _, bagSlot in ipairs(frame.bagSlots) do
        local bagID = bagSlot.bagID
        if bagID == 0 then
            bagSlot.icon:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
        else
            local texture = nil
            if viewingCharacter then
                -- Viewing cached character - only use cached data
                if cachedBags and cachedBags[bagID] and cachedBags[bagID].containerTexture then
                    texture = cachedBags[bagID].containerTexture
                end
                -- No fallback to current player - show empty bag if no cached texture
            else
                -- Current character - use live data
                local invID = C_Container.ContainerIDToInventoryID(bagID)
                texture = GetInventoryItemTexture("player", invID)
            end
            if texture then
                bagSlot.icon:SetTexture(texture)
            else
                bagSlot.icon:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
            end
        end
    end

    -- Update main bag slot icon
    if frame.mainBagSlot then
        frame.mainBagSlot.icon:SetTexture("Interface\\AddOns\\GudaBags\\Assets\\bags.png")
    end

    -- Also update flyout bag slots if visible
    if bagFlyout and bagFlyout:IsShown() then
        self:UpdateFlyout()
    end
end

function BagSlots:UpdateFlyout()
    if not bagFlyout or not bagFlyout.bagSlots then return end

    -- Get cached bags if viewing another character
    local cachedBags = nil
    if viewingCharacter then
        cachedBags = GetDatabase():GetNormalizedBags(viewingCharacter)
    end

    for _, bagSlot in ipairs(bagFlyout.bagSlots) do
        local bagID = bagSlot.bagID
        local texture = nil
        if viewingCharacter then
            -- Viewing cached character - only use cached data
            if cachedBags and cachedBags[bagID] and cachedBags[bagID].containerTexture then
                texture = cachedBags[bagID].containerTexture
            end
            -- No fallback to current player - show empty bag if no cached texture
        else
            -- Current character - use live data
            local invID = C_Container.ContainerIDToInventoryID(bagID)
            texture = GetInventoryItemTexture("player", invID)
        end
        if texture then
            bagSlot.icon:SetTexture(texture)
        else
            bagSlot.icon:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
        end
    end
end

function BagSlots:SetViewingCharacter(fullName)
    viewingCharacter = fullName
end

function BagSlots:ToggleFlyout()
    if not bagFlyout then return end

    bagFlyoutExpanded = not bagFlyoutExpanded

    if bagFlyoutExpanded then
        self:UpdateFlyout()
        bagFlyout:Show()
        if frame.mainBagSlot then
            frame.mainBagSlot:SetBackdropBorderColor(1, 0.82, 0, 1)
        end
    else
        bagFlyout:Hide()
        if frame.mainBagSlot then
            frame.mainBagSlot:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)
        end
    end
end

function BagSlots:GetAnchor()
    if not frame then return nil end

    local showAllBags = GetDatabase():GetSetting("hoverBagline")
    if showAllBags then
        return frame.bagSlots[#frame.bagSlots]
    else
        return frame.mainBagSlot
    end
end

function BagSlots:GetFrame()
    return frame
end
