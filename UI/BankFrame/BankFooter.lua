local addonName, ns = ...

local BankFooter = {}
ns:RegisterModule("BankFrame.BankFooter", BankFooter)

local Constants = ns.Constants

local frame = nil
local backButton = nil
local onBackCallback = nil
local bagSlotButtons = {}
local tabButtons = {}  -- Retail bank tab buttons
local bankTypeButtons = {}  -- Bank type selector buttons (Bank | Warband)
local mainBankFrame = nil
local viewingCharacter = nil
local isRetailTabMode = false  -- True when showing Retail tabs instead of bag slots
local currentBankType = "character"  -- "character" or "warband"

local BankScanner = nil
local RetailBankScanner = nil
local Money = nil
local Database = nil

local function LoadComponents()
    BankScanner = ns:GetModule("BankScanner")
    Money = ns:GetModule("Footer.Money")
    Database = ns:GetModule("Database")
    if ns.IsRetail then
        RetailBankScanner = ns:GetModule("RetailBankScanner")
    end
end

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12|t"

local function FormatMoney(amount)
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)

    local result = ""
    if gold > 0 then
        result = string.format("%d%s", gold, GOLD_ICON)
    end
    if silver > 0 then
        if result ~= "" then result = result .. " " end
        result = result .. string.format("%d%s", silver, SILVER_ICON)
    end
    return result
end

-- Get the inventory slot ID for a bank bag slot
local function GetBankBagInvSlot(bankBagIndex)
    -- BankButtonIDToInvSlotID converts bank bag button ID (1-7) to inventory slot
    -- In Classic/TBC, bank bags use inventory slots starting at ContainerIDToInventoryID(5)
    if ContainerIDToInventoryID then
        return ContainerIDToInventoryID(bankBagIndex + 4)
    elseif C_Container and C_Container.ContainerIDToInventoryID then
        return C_Container.ContainerIDToInventoryID(bankBagIndex + 4)
    else
        return BankButtonIDToInvSlotID(bankBagIndex)
    end
end

-- Get bank bag info
local function GetBankBagInfo(bankBagIndex)
    local invSlot = GetBankBagInvSlot(bankBagIndex)
    local itemID = GetInventoryItemID("player", invSlot)
    local texture = GetInventoryItemTexture("player", invSlot)
    return itemID, texture, invSlot
end

local function CreateMainBankButton(parent)
    local button = CreateFrame("Button", "GudaBankMainSlot", parent, "BackdropTemplate")
    button:SetSize(Constants.BAG_SLOT_SIZE, Constants.BAG_SLOT_SIZE)
    button:EnableMouse(true)
    button.bagID = -1

    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    button:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    button:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(Constants.BAG_SLOT_SIZE - 2, Constants.BAG_SLOT_SIZE - 2)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
    button.icon = icon

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns.L["TOOLTIP_BANK"])
        GameTooltip:Show()

        local ItemButton = ns:GetModule("ItemButton")
        if ItemButton then
            ItemButton:HighlightBagSlots(-1)
        end
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()

        local ItemButton = ns:GetModule("ItemButton")
        if ItemButton then
            ItemButton:ClearHighlightedSlots(mainBankFrame)
        end
    end)

    return button
end

-- Register purchase confirmation popup
StaticPopupDialogs["GUDABAGS_PURCHASE_BANK_SLOT"] = {
    text = ns.L["BANK_PURCHASE_SLOT"],
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        local scanner = ns:GetModule("BankScanner")
        if scanner then
            scanner:PurchaseBankSlot()
        end
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CreateBagSlotButton(parent, index)
    local button = CreateFrame("Button", "GudaBankBagSlot" .. index, parent, "BackdropTemplate")
    button:SetSize(Constants.BAG_SLOT_SIZE, Constants.BAG_SLOT_SIZE)
    button.needPurchase = false

    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    button:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    button:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(Constants.BAG_SLOT_SIZE - 2, Constants.BAG_SLOT_SIZE - 2)
    icon:SetPoint("CENTER")
    button.icon = icon

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    button:SetScript("OnEnter", function(self)
        if self.bagID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local bagID = self.bagID
            if bagID >= 5 and bagID <= 11 then
                local bankBagIndex = bagID - 4

                if self.needPurchase then
                    GameTooltip:SetText(BANK_BAG_PURCHASE)
                    local cost = BankScanner:GetBankSlotCost()
                    if cost then
                        GameTooltip:AddLine(FormatMoney(cost), 1, 1, 1)
                    end
                else
                    local itemID, texture, invSlot = GetBankBagInfo(bankBagIndex)
                    if itemID then
                        GameTooltip:SetInventoryItem("player", invSlot)
                    else
                        GameTooltip:SetText(BAG_SLOT)
                    end
                end
            else
                GameTooltip:SetText(ns.L["TOOLTIP_BANK"])
            end
            GameTooltip:Show()

            local ItemButton = ns:GetModule("ItemButton")
            if ItemButton then
                ItemButton:HighlightBagSlots(bagID)
            end
        end
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()

        local ItemButton = ns:GetModule("ItemButton")
        if ItemButton then
            ItemButton:ClearHighlightedSlots(mainBankFrame)
        end
    end)

    button:SetScript("OnClick", function(self)
        if self.bagID and self.bagID >= 5 and self.bagID <= 11 then
            if self.needPurchase then
                local cost = BankScanner:GetBankSlotCost()
                if cost then
                    StaticPopup_Show("GUDABAGS_PURCHASE_BANK_SLOT", FormatMoney(cost))
                end
            else
                local bankBagIndex = self.bagID - 4
                local itemID, texture, invSlot = GetBankBagInfo(bankBagIndex)
                if CursorHasItem() then
                    PickupInventoryItem(invSlot)
                elseif itemID then
                    PickupInventoryItem(invSlot)
                end
            end
        end
    end)

    button:RegisterForDrag("LeftButton")

    button:SetScript("OnDragStart", function(self)
        if self.bagID and self.bagID >= 5 and self.bagID <= 11 and not self.needPurchase then
            local bankBagIndex = self.bagID - 4
            local itemID, texture, invSlot = GetBankBagInfo(bankBagIndex)
            if itemID then
                PickupInventoryItem(invSlot)
            end
        end
    end)

    button:SetScript("OnReceiveDrag", function(self)
        if self.bagID and self.bagID >= 5 and self.bagID <= 11 and not self.needPurchase then
            local bankBagIndex = self.bagID - 4
            local itemID, texture, invSlot = GetBankBagInfo(bankBagIndex)
            if CursorHasItem() then
                PickupInventoryItem(invSlot)
            end
        end
    end)

    return button
end

-- Create a tab button for Retail bank tabs
local function CreateTabButton(parent, index)
    local button = CreateFrame("Button", "GudaBankTab" .. index, parent, "BackdropTemplate")
    button:SetSize(Constants.BAG_SLOT_SIZE, Constants.BAG_SLOT_SIZE)
    button.tabIndex = index

    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    button:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    button:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(Constants.BAG_SLOT_SIZE - 4, Constants.BAG_SLOT_SIZE - 4)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    button.icon = icon

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    -- Selection indicator
    local selected = button:CreateTexture(nil, "OVERLAY")
    selected:SetAllPoints()
    selected:SetColorTexture(1, 0.82, 0, 0.3)
    selected:Hide()
    button.selected = selected

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self.tabName then
            GameTooltip:SetText(self.tabName)
        else
            GameTooltip:SetText(string.format(ns.L["TOOLTIP_BANK_TAB"], self.tabIndex))
        end
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function(self)
        if RetailBankScanner then
            -- If clicking the already selected tab, deselect (show all)
            local currentTab = RetailBankScanner:GetSelectedTab()
            if currentTab == self.tabIndex then
                RetailBankScanner:SetSelectedTab(0)
            else
                RetailBankScanner:SetSelectedTab(self.tabIndex)
            end
            BankFooter:UpdateTabSelection()
        end
    end)

    return button
end

-- Create "All" tab button
local function CreateAllTabButton(parent)
    local button = CreateFrame("Button", "GudaBankTabAll", parent, "BackdropTemplate")
    button:SetSize(Constants.BAG_SLOT_SIZE, Constants.BAG_SLOT_SIZE)
    button.tabIndex = 0

    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    button:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    button:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(Constants.BAG_SLOT_SIZE - 4, Constants.BAG_SLOT_SIZE - 4)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Buttons\\Button-Backpack-Up")
    button.icon = icon

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    -- Selection indicator
    local selected = button:CreateTexture(nil, "OVERLAY")
    selected:SetAllPoints()
    selected:SetColorTexture(1, 0.82, 0, 0.3)
    selected:Hide()
    button.selected = selected

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns.L["TOOLTIP_BANK_ALL_TABS"])
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function(self)
        if RetailBankScanner then
            RetailBankScanner:SetSelectedTab(0)
            BankFooter:UpdateTabSelection()
        end
    end)

    return button
end

-- Create bank type selector button (Bank | Warband)
local function CreateBankTypeButton(parent, bankType, label, icon)
    local button = CreateFrame("Button", "GudaBankType" .. bankType, parent, "BackdropTemplate")
    button:SetSize(50, 18)
    button.bankType = bankType

    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    button:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    button:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)

    local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetText(label)
    text:SetTextColor(0.8, 0.8, 0.8)
    button.text = text

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    -- Selection indicator
    local selected = button:CreateTexture(nil, "OVERLAY")
    selected:SetAllPoints()
    selected:SetColorTexture(1, 0.82, 0, 0.3)
    selected:Hide()
    button.selected = selected

    button:SetScript("OnClick", function(self)
        if currentBankType ~= self.bankType then
            currentBankType = self.bankType
            BankFooter:UpdateBankTypeSelection()
            -- Notify BankFrame to refresh with new bank type
            if ns.OnBankTypeChanged then
                ns.OnBankTypeChanged(currentBankType)
            end
        end
    end)

    return button
end

function BankFooter:Init(parent)
    LoadComponents()

    -- Store reference to main BankFrame for search bar context
    mainBankFrame = parent

    frame = CreateFrame("Frame", "GudaBankFooter", parent)
    frame:SetHeight(Constants.FRAME.FOOTER_HEIGHT)
    frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", Constants.FRAME.PADDING, Constants.FRAME.PADDING - 2)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -Constants.FRAME.PADDING, Constants.FRAME.PADDING - 2)

    -- Create main bank slot button (bagID -1) with same style as BagSlots
    local mainBankButton = CreateMainBankButton(frame)
    mainBankButton:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame.mainBankButton = mainBankButton
    table.insert(bagSlotButtons, mainBankButton)

    -- Create bank bag slots (bagIDs 5-11)
    for i = 1, Constants.BANK_BAG_COUNT do
        local button = CreateBagSlotButton(frame, i)
        button.bagID = i + 4
        button:SetPoint("LEFT", bagSlotButtons[i], "RIGHT", -1, 0)
        table.insert(bagSlotButtons, button)
    end

    -- Slot counter after bag containers (with tooltip frame for hover)
    local slotInfoFrame = CreateFrame("Frame", nil, frame)
    slotInfoFrame:SetPoint("LEFT", bagSlotButtons[#bagSlotButtons], "RIGHT", 8, 0)
    slotInfoFrame:SetSize(60, 16)

    local slotInfo = slotInfoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slotInfo:SetPoint("LEFT", slotInfoFrame, "LEFT", 0, 0)
    slotInfo:SetTextColor(0.8, 0.8, 0.8)
    slotInfo:SetShadowOffset(1, -1)
    slotInfo:SetShadowColor(0, 0, 0, 1)
    frame.slotInfo = slotInfo
    frame.slotInfoFrame = slotInfoFrame

    -- Store special bags data for tooltip
    frame.specialBagsData = nil

    -- Tooltip on hover
    slotInfoFrame:SetScript("OnEnter", function(self)
        if frame.specialBagsData and next(frame.specialBagsData) then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Bank Slots", 1, 1, 1)
            GameTooltip:AddLine(" ")

            -- Show regular bags info
            if frame.regularTotal then
                local regularUsed = frame.regularTotal - (frame.regularFree or 0)
                GameTooltip:AddDoubleLine("Regular Bags:", string.format("%d/%d", regularUsed, frame.regularTotal), 1, 1, 1, 0.8, 0.8, 0.8)
            end

            -- Show special bags
            for bagType, data in pairs(frame.specialBagsData) do
                local used = data.total - data.free
                GameTooltip:AddDoubleLine(bagType .. ":", string.format("%d/%d", used, data.total), 1, 0.82, 0, 0.8, 0.8, 0.8)
            end

            GameTooltip:Show()
        end
    end)
    slotInfoFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame.moneyFrame = Money:Init(frame)

    backButton = CreateFrame("Button", "GudaBankBackButton", frame)
    backButton:SetSize(60, 18)
    backButton:SetPoint("LEFT", frame, "LEFT", 0, 0)

    local backText = backButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    backText:SetPoint("LEFT", backButton, "LEFT", 0, 0)
    backText:SetText("<< Back")
    backText:SetTextColor(0.6, 0.8, 1)
    backButton.text = backText

    backButton:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
    end)
    backButton:SetScript("OnLeave", function(self)
        self.text:SetTextColor(0.6, 0.8, 1)
    end)
    backButton:SetScript("OnClick", function()
        if onBackCallback then
            onBackCallback()
        end
    end)
    backButton:Hide()

    return frame
end

function BankFooter:Show()
    if not frame then return end
    frame:Show()

    if backButton then
        backButton:Hide()
    end

    -- Reset viewing character to current character
    viewingCharacter = nil

    -- Hide retail tabs when showing live bank
    self:HideRetailTabs()

    for _, button in ipairs(bagSlotButtons) do
        button:Show()
        button:SetAlpha(1)
    end

    Money:Show()
    self:Update()
end

function BankFooter:Hide()
    if not frame then return end
    frame:Hide()

    for _, button in ipairs(bagSlotButtons) do
        button:Hide()
    end

    -- Hide retail tabs too
    self:HideRetailTabs()

    Money:Hide()

    if backButton then
        backButton:Hide()
    end
end

function BankFooter:Update()
    if not frame then return end

    -- Get cached bank if viewing another character
    local cachedBank = nil
    local Database = ns:GetModule("Database")
    if viewingCharacter then
        cachedBank = Database:GetNormalizedBank(viewingCharacter)
    end

    local purchased = BankScanner:GetPurchasedBankSlots()

    for i, button in ipairs(bagSlotButtons) do
        -- Skip main bank button (index 1, bagID -1) - uses different style
        if button.bagID == -1 then
            -- Main bank button uses backdrop style, no update needed
        else
            local bagID = button.bagID
            local bankBagIndex = bagID - 4

            -- Try to get texture from cached data first
            if cachedBank and cachedBank[bagID] then
                local texture = cachedBank[bagID].containerTexture
                button.needPurchase = false
                button:SetAlpha(1)
                if texture then
                    button.icon:SetTexture(texture)
                else
                    button.icon:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
                end
            elseif not viewingCharacter then
                -- Current character - use live data
                if bankBagIndex > purchased then
                    -- Unpurchased slot - dimmed
                    button.needPurchase = true
                    button.icon:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
                    button:SetAlpha(0.4)
                else
                    -- Purchased slot
                    button.needPurchase = false
                    button:SetAlpha(1)
                    local itemID, texture = GetBankBagInfo(bankBagIndex)
                    if itemID and texture then
                        button.icon:SetTexture(texture)
                    else
                        button.icon:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
                    end
                end
            else
                -- Cached character but no data for this bag slot
                button.needPurchase = false
                button:SetAlpha(0.7)
                button.icon:SetTexture("Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag")
            end
        end
    end

    if not viewingCharacter then
        Money:Update()
    end
end

function BankFooter:SetViewingCharacter(fullName)
    viewingCharacter = fullName
end

function BankFooter:UpdateMoney()
    if Money then
        Money:Update()
    end
end

function BankFooter:UpdateSlotInfo(used, total, regularTotal, regularFree, specialBags)
    if not frame or not frame.slotInfo then return end

    -- If detailed data provided, show only regular bags and store special for tooltip
    if regularTotal then
        local regularUsed = regularTotal - (regularFree or 0)
        frame.slotInfo:SetText(string.format("%d/%d", regularUsed, regularTotal))
        frame.regularTotal = regularTotal
        frame.regularFree = regularFree
        frame.specialBagsData = specialBags
    else
        -- Fallback to simple display
        frame.slotInfo:SetText(string.format("%d/%d", used, total))
        frame.regularTotal = total
        frame.regularFree = total - used
        frame.specialBagsData = nil
    end
end

function BankFooter:ShowCached(characterFullName)
    if not frame then return end
    frame:Show()

    ns:Debug("BankFooter:ShowCached called for:", characterFullName or "current")
    ns:Debug("  ns.IsRetail:", tostring(ns.IsRetail))

    -- Hide back button
    if backButton then
        backButton:Hide()
    end

    -- Set viewing character for bag slot textures
    viewingCharacter = characterFullName

    -- On Retail, always show tabs instead of bag slots for cached bank viewing
    -- On Classic, show traditional bag slots
    if ns.IsRetail then
        -- Show tabs instead of bag slots
        ns:Debug("  Calling ShowRetailTabs")
        self:ShowRetailTabs(characterFullName)
    else
        -- Show bag slots for Classic (disable interactions)
        self:HideRetailTabs()
        for _, button in ipairs(bagSlotButtons) do
            button:Show()
            button:SetAlpha(0.7)
        end
        -- Update bag slot visuals with cached textures
        self:Update()
    end

    -- Show and update money for the cached character
    Money:Show()
    Money:UpdateCached(characterFullName)
end

-- Show Retail bank footer (slot info only)
-- Bank/Warband selector is now shown as bottom tabs (see BankFrame:ShowBottomTabs)
-- Tab selection is shown on the right side of the bank frame (see BankFrame:ShowSideTabs)
function BankFooter:ShowRetailTabs(characterFullName)
    isRetailTabMode = true
    local Constants = ns.Constants

    ns:Debug("ShowRetailTabs called for:", characterFullName or "current")

    -- Hide classic bag slots (they're replaced by side tabs on Retail)
    for _, button in ipairs(bagSlotButtons) do
        button:Hide()
    end

    -- Hide old footer tab buttons (tabs moved to side bar)
    if frame.allTabButton then
        frame.allTabButton:Hide()
    end
    for _, button in ipairs(tabButtons) do
        button:Hide()
    end

    -- Hide bank type buttons (now shown as bottom tabs on the frame)
    if bankTypeButtons.character then
        bankTypeButtons.character:Hide()
    end
    if bankTypeButtons.warband then
        bankTypeButtons.warband:Hide()
    end

    -- Update slot info position (left side since bank type buttons are hidden)
    if frame.slotInfoFrame then
        frame.slotInfoFrame:ClearAllPoints()
        frame.slotInfoFrame:SetPoint("LEFT", frame, "LEFT", 0, 0)
    end
end

-- Hide Retail bank tabs
function BankFooter:HideRetailTabs()
    isRetailTabMode = false

    -- Hide bank type buttons
    if bankTypeButtons.character then
        bankTypeButtons.character:Hide()
    end
    if bankTypeButtons.warband then
        bankTypeButtons.warband:Hide()
    end
    if frame and frame.bankTypeSeparator then
        frame.bankTypeSeparator:Hide()
    end

    if frame and frame.allTabButton then
        frame.allTabButton:Hide()
    end

    for _, button in ipairs(tabButtons) do
        button:Hide()
    end

    -- Restore slot info position
    if frame and frame.slotInfoFrame and #bagSlotButtons > 0 then
        frame.slotInfoFrame:ClearAllPoints()
        frame.slotInfoFrame:SetPoint("LEFT", bagSlotButtons[#bagSlotButtons], "RIGHT", 8, 0)
    end
end

-- Update bank type button selection visuals
function BankFooter:UpdateBankTypeSelection()
    if bankTypeButtons.character then
        if currentBankType == "character" then
            bankTypeButtons.character.selected:Show()
            bankTypeButtons.character:SetBackdropBorderColor(1, 0.82, 0, 1)
            bankTypeButtons.character.text:SetTextColor(1, 0.82, 0)
        else
            bankTypeButtons.character.selected:Hide()
            bankTypeButtons.character:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)
            bankTypeButtons.character.text:SetTextColor(0.8, 0.8, 0.8)
        end
    end

    if bankTypeButtons.warband then
        if currentBankType == "warband" then
            bankTypeButtons.warband.selected:Show()
            bankTypeButtons.warband:SetBackdropBorderColor(1, 0.82, 0, 1)
            bankTypeButtons.warband.text:SetTextColor(1, 0.82, 0)
        else
            bankTypeButtons.warband.selected:Hide()
            bankTypeButtons.warband:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)
            bankTypeButtons.warband.text:SetTextColor(0.8, 0.8, 0.8)
        end
    end
end

-- Get current bank type
function BankFooter:GetCurrentBankType()
    return currentBankType
end

-- Set current bank type
function BankFooter:SetCurrentBankType(bankType)
    currentBankType = bankType or "character"
    self:UpdateBankTypeSelection()
end

-- Update tab selection visuals (tabs are now on side bar, this is kept for compatibility)
function BankFooter:UpdateTabSelection()
    -- Tab selection is now handled by BankFrame:UpdateSideTabSelection()
    -- This function is kept for backwards compatibility
end

-- Check if in retail tab mode
function BankFooter:IsRetailTabMode()
    return isRetailTabMode
end

function BankFooter:SetBackCallback(callback)
    onBackCallback = callback
end

function BankFooter:GetFrame()
    return frame
end

function BankFooter:SetInteractive(enabled)
    for _, button in ipairs(bagSlotButtons) do
        if enabled then
            button:Enable()
            button:SetAlpha(1)
        else
            button:Disable()
            button:SetAlpha(0.5)
        end
    end
end
