local addonName, ns = ...

local QuestBar = {}
ns:RegisterModule("QuestBar", QuestBar)

local Constants = ns.Constants
local Database = ns:GetModule("Database")
local Events = ns:GetModule("Events")

-- Local state
local frame = nil
local mainButton = nil
local flyout = nil
local flyoutButtons = {}
local isDragging = false
local questItems = {}  -- Current usable quest items
local activeItemIndex = 1

-- Constants
local BUTTON_SPACING = 2
local PADDING = 0
local MAX_FLYOUT_ITEMS = 8
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

-- Battleground detection
local function IsInBattleground()
    local inInstance, instanceType = IsInInstance()
    return inInstance and instanceType == "pvp"
end

local function GetButtonSize()
    return Database:GetSetting("questBarSize") or 44
end

-------------------------------------------------
-- Border Creation
-------------------------------------------------

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

-------------------------------------------------
-- Quest Item Detection
-------------------------------------------------

local function IsUsableItem(itemID)
    if not itemID then return false end
    local spellName = GetItemSpell(itemID)
    return spellName ~= nil
end

local function ScanForUsableQuestItems()
    local items = {}
    -- Use cached bag data instead of scanning
    local BagScanner = ns:GetModule("BagScanner")
    if not BagScanner then return items end

    local cachedBags = BagScanner:GetCachedBags()

    for bagID = 0, 4 do
        local bagData = cachedBags[bagID]
        if bagData and bagData.slots then
            for slot, itemData in pairs(bagData.slots) do
                if itemData and itemData.isQuestItem and IsUsableItem(itemData.itemID) then
                    -- Check if we already have this itemID in the list
                    local found = false
                    for _, existing in ipairs(items) do
                        if existing.itemID == itemData.itemID then
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(items, {
                            itemID = itemData.itemID,
                            bagID = bagID,
                            slot = slot,
                            isQuestStarter = itemData.isQuestStarter,
                            texture = itemData.texture,
                            name = itemData.name,
                            count = itemData.count,
                        })
                    end
                    if #items >= MAX_FLYOUT_ITEMS + 1 then
                        return items
                    end
                end
            end
        end
    end

    return items
end

local function FindItemInBags(itemID)
    for bagID = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info and info.itemID == itemID then
                return bagID, slot, info
            end
        end
    end
    return nil, nil, nil
end

local function GetItemCount(itemID)
    local count = 0
    for bagID = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info and info.itemID == itemID then
                count = count + (info.stackCount or 1)
            end
        end
    end
    return count
end

-------------------------------------------------
-- Button Creation
-------------------------------------------------

local function CreateItemButton(parent, name, isMain)
    local buttonSize = GetButtonSize()

    -- Use SecureActionButtonTemplate for protected item usage
    local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    button:SetSize(buttonSize, buttonSize)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("type", "item")

    -- Prevent dragging items
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function() end)
    button:SetScript("OnReceiveDrag", function() end)

    -- Background
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    bg:SetVertexColor(1, 1, 1, 0.5)
    button.bg = bg

    -- Icon
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.icon = icon

    -- Count text
    local count = button:CreateFontString(nil, "OVERLAY")
    local fontSize = Database:GetSetting("iconFontSize")
    count:SetFont(DEFAULT_FONT, fontSize, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 1)
    count:SetJustifyH("RIGHT")
    button.count = count

    -- Cooldown frame
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(icon)
    cooldown:SetDrawEdge(false)
    button.cooldown = cooldown

    -- Highlight
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    -- Quality border
    local border = CreateBorder(button)
    button.border = border

    -- Inner shadow/glow for quest colors (inset effect with more spread)
    local shadowSize = 8
    local innerShadow = {
        top = button:CreateTexture(nil, "ARTWORK", nil, 1),
        bottom = button:CreateTexture(nil, "ARTWORK", nil, 1),
        left = button:CreateTexture(nil, "ARTWORK", nil, 1),
        right = button:CreateTexture(nil, "ARTWORK", nil, 1),
    }
    -- Top edge
    innerShadow.top:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    innerShadow.top:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    innerShadow.top:SetHeight(shadowSize)
    innerShadow.top:SetTexture("Interface\\Buttons\\WHITE8x8")
    innerShadow.top:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.6))
    -- Bottom edge
    innerShadow.bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    innerShadow.bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    innerShadow.bottom:SetHeight(shadowSize)
    innerShadow.bottom:SetTexture("Interface\\Buttons\\WHITE8x8")
    innerShadow.bottom:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.6), CreateColor(0, 0, 0, 0))
    -- Left edge
    innerShadow.left:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    innerShadow.left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    innerShadow.left:SetWidth(shadowSize)
    innerShadow.left:SetTexture("Interface\\Buttons\\WHITE8x8")
    innerShadow.left:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.6), CreateColor(0, 0, 0, 0))
    -- Right edge
    innerShadow.right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    innerShadow.right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    innerShadow.right:SetWidth(shadowSize)
    innerShadow.right:SetTexture("Interface\\Buttons\\WHITE8x8")
    innerShadow.right:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.6))
    -- Hide by default
    for _, tex in pairs(innerShadow) do tex:Hide() end
    button.innerShadow = innerShadow

    -- Tooltip
    button:SetScript("OnEnter", function(self)
        if self.itemID then
            local bagID, slotID = FindItemInBags(self.itemID)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if bagID and slotID then
                GameTooltip:SetBagItem(bagID, slotID)
            else
                GameTooltip:SetItemByID(self.itemID)
            end
            GameTooltip:Show()
        end

        -- Show flyout on hover (main button only)
        if isMain and flyout and #questItems > 1 then
            QuestBar:ShowFlyout()
        end
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        -- Don't hide flyout here - let the flyout frame handle it
    end)

    -- PreClick: only allow item use on right click
    button:SetScript("PreClick", function(self, mouseButton)
        if mouseButton == "RightButton" and not IsShiftKeyDown() then
            self:SetAttribute("type", "item")
        else
            self:SetAttribute("type", nil)
        end
    end)

    -- PostClick: restore type
    button:SetScript("PostClick", function(self, mouseButton)
        self:SetAttribute("type", "item")
    end)

    if isMain then
        -- Main button drag handling for moving the bar
        button:HookScript("OnMouseDown", function(self, mouseButton)
            if mouseButton == "LeftButton" and IsShiftKeyDown() and not CursorHasItem() then
                isDragging = true
                frame:StartMoving()
            end
        end)

        button:HookScript("OnMouseUp", function(self, mouseButton)
            if mouseButton == "LeftButton" and isDragging then
                isDragging = false
                frame:StopMovingOrSizing()
                QuestBar:SavePosition()
            end
        end)
    end

    return button
end

-------------------------------------------------
-- Flyout Creation
-------------------------------------------------

local function CreateFlyout(parent)
    local buttonSize = GetButtonSize()
    local f = CreateFrame("Frame", "GudaQuestBarFlyout", parent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    f:SetBackdropBorderColor(0.6, 0.5, 0.0, 1)

    -- Create flyout buttons (vertical stack, top to bottom)
    for i = 1, MAX_FLYOUT_ITEMS do
        local button = CreateItemButton(f, "GudaQuestBarFlyoutItem" .. i, false)
        button:SetPoint("TOP", f, "TOP", 0, -PADDING - (i - 1) * (buttonSize + BUTTON_SPACING))
        button:Hide()
        button.flyoutIndex = i

        -- On click in flyout, set as active item
        button:HookScript("OnClick", function(self, mouseButton)
            if mouseButton == "LeftButton" and self.itemIndex then
                activeItemIndex = self.itemIndex
                QuestBar:Refresh()
            end
        end)

        flyoutButtons[i] = button
    end

    -- Hide flyout when mouse leaves
    f:SetScript("OnLeave", function(self)
        -- Check if mouse is over main button or flyout
        if not mainButton:IsMouseOver() and not self:IsMouseOver() then
            self:Hide()
        end
    end)

    f:SetScript("OnUpdate", function(self)
        -- Hide if mouse is not over main button or flyout
        if self:IsShown() and not mainButton:IsMouseOver() and not self:IsMouseOver() then
            local dominated = false
            for _, btn in ipairs(flyoutButtons) do
                if btn:IsShown() and btn:IsMouseOver() then
                    dominated = true
                    break
                end
            end
            if not dominated then
                self:Hide()
            end
        end
    end)

    f:Hide()
    return f
end

-------------------------------------------------
-- UI Creation
-------------------------------------------------

local function CreateQuestBarFrame()
    local buttonSize = GetButtonSize()
    local f = CreateFrame("Frame", "GudaQuestBar", UIParent, "BackdropTemplate")
    f:SetSize(buttonSize + PADDING * 2, buttonSize + PADDING * 2)
    f:SetPoint("TOP", UIParent, "TOP", 0, -150)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(50)

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.85)
    f:SetBackdropBorderColor(0.6, 0.5, 0.0, 0.9)

    -- Create main button
    mainButton = CreateItemButton(f, "GudaQuestBarMainButton", true)
    mainButton:SetPoint("CENTER", f, "CENTER", 0, 0)

    -- Create flyout (to the right of the main bar, bottom-aligned)
    flyout = CreateFlyout(f)
    flyout:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 1, 0)

    f:Hide()
    return f
end

-------------------------------------------------
-- Button Update
-------------------------------------------------

local function UpdateButton(button, itemData)
    if not itemData then
        button.itemID = nil
        button.border:Hide()
        if button.innerShadow then
            for _, tex in pairs(button.innerShadow) do tex:Hide() end
        end
        button:SetAttribute("item", nil)
        button:Hide()
        return
    end

    local itemID = itemData.itemID
    button.itemID = itemID

    local itemName, itemLink, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
    local count = GetItemCount(itemID)

    local bagID, slot = FindItemInBags(itemID)

    button.bagID = bagID
    button.slotID = slot
    button.itemName = itemName

    if bagID and slot then
        button:SetAttribute("item", "item:" .. itemID)
    else
        button:SetAttribute("item", nil)
    end

    if itemTexture or itemData.texture then
        button.icon:SetTexture(itemTexture or itemData.texture)
        button.bg:Hide()
    else
        button.bg:Show()
    end

    if count > 1 then
        button.count:SetText(count)
        button.count:Show()
    else
        button.count:Hide()
    end

    -- Update cooldown
    if bagID and slot then
        local start, duration, enable = C_Container.GetContainerItemCooldown(bagID, slot)
        if start and duration and duration > 0 then
            button.cooldown:SetCooldown(start, duration)
        else
            button.cooldown:Clear()
        end
    else
        button.cooldown:Clear()
    end

    -- Sunny yellow-gold color for border and inner shadow
    local sunnyR, sunnyG, sunnyB = 1.0, 0.85, 0.2
    button.border:SetVertexColor(sunnyR, sunnyG, sunnyB, 1)
    button.border:Show()

    -- Show inner shadow with sunny color
    if button.innerShadow then
        button.innerShadow.top:SetGradient("VERTICAL", CreateColor(sunnyR, sunnyG, sunnyB, 0), CreateColor(sunnyR, sunnyG, sunnyB, 0.6))
        button.innerShadow.bottom:SetGradient("VERTICAL", CreateColor(sunnyR, sunnyG, sunnyB, 0.6), CreateColor(sunnyR, sunnyG, sunnyB, 0))
        button.innerShadow.left:SetGradient("HORIZONTAL", CreateColor(sunnyR, sunnyG, sunnyB, 0.6), CreateColor(sunnyR, sunnyG, sunnyB, 0))
        button.innerShadow.right:SetGradient("HORIZONTAL", CreateColor(sunnyR, sunnyG, sunnyB, 0), CreateColor(sunnyR, sunnyG, sunnyB, 0.6))
        for _, tex in pairs(button.innerShadow) do tex:Show() end
    end

    -- Dim if not in bags
    if count == 0 then
        button.icon:SetDesaturated(true)
        button.icon:SetAlpha(0.5)
    else
        button.icon:SetDesaturated(false)
        button.icon:SetAlpha(1)
    end

    button:Show()
end

-------------------------------------------------
-- Public API
-------------------------------------------------

function QuestBar:Init()
    if frame then return end
    frame = CreateQuestBarFrame()
    self:RestorePosition()
    self:Refresh()
end

function QuestBar:Show()
    if not frame then self:Init() end
    local showQuestBar = Database:GetSetting("showQuestBar")
    if showQuestBar then
        self:Refresh()
    end
end

function QuestBar:Hide()
    if frame then
        frame:Hide()
    end
    if flyout then
        flyout:Hide()
    end
end

function QuestBar:ShowFlyout()
    if not flyout or #questItems <= 1 then return end

    local buttonSize = GetButtonSize()
    local otherItems = {}

    -- Collect items that are not the active one
    for i, item in ipairs(questItems) do
        if i ~= activeItemIndex then
            table.insert(otherItems, { data = item, index = i })
        end
    end

    local visibleCount = math.min(#otherItems, MAX_FLYOUT_ITEMS)

    -- Update flyout buttons (vertical stack, top to bottom)
    for i = 1, MAX_FLYOUT_ITEMS do
        local otherItem = otherItems[i]
        if otherItem then
            flyoutButtons[i].itemIndex = otherItem.index
            UpdateButton(flyoutButtons[i], otherItem.data)
            flyoutButtons[i]:SetSize(buttonSize, buttonSize)
            flyoutButtons[i]:ClearAllPoints()
            flyoutButtons[i]:SetPoint("TOP", flyout, "TOP", 0, -PADDING - (i - 1) * (buttonSize + BUTTON_SPACING))
        else
            flyoutButtons[i]:Hide()
            flyoutButtons[i].itemIndex = nil
        end
    end

    if visibleCount > 0 then
        local height = PADDING * 2 + visibleCount * buttonSize + (visibleCount - 1) * BUTTON_SPACING
        local width = buttonSize + PADDING * 2
        flyout:SetSize(width, height)
        flyout:Show()
    else
        flyout:Hide()
    end
end

function QuestBar:HideFlyout()
    if flyout then
        flyout:Hide()
    end
end

function QuestBar:Refresh()
    if not frame then return end

    local showQuestBar = Database:GetSetting("showQuestBar")
    local hideInBGs = Database:GetSetting("hideQuestBarInBGs")

    -- Hide if setting is off OR if in battleground with hide option enabled
    if not showQuestBar or (hideInBGs and IsInBattleground()) then
        frame:Hide()
        if flyout then flyout:Hide() end
        return
    end

    -- Scan for usable quest items
    questItems = ScanForUsableQuestItems()

    -- Validate activeItemIndex
    if activeItemIndex > #questItems then
        activeItemIndex = 1
    end

    if #questItems > 0 then
        local buttonSize = GetButtonSize()
        frame:SetSize(buttonSize + PADDING * 2, buttonSize + PADDING * 2)
        mainButton:SetSize(buttonSize, buttonSize)

        UpdateButton(mainButton, questItems[activeItemIndex])
        frame:Show()
    else
        frame:Hide()
        if flyout then flyout:Hide() end
    end
end

function QuestBar:SavePosition()
    if not frame then return end
    local point, _, relPoint, x, y = frame:GetPoint()
    Database:SetSetting("questBarPoint", point)
    Database:SetSetting("questBarRelPoint", relPoint)
    Database:SetSetting("questBarX", x)
    Database:SetSetting("questBarY", y)
end

function QuestBar:RestorePosition()
    if not frame then return end

    local point = Database:GetSetting("questBarPoint")
    local relPoint = Database:GetSetting("questBarRelPoint")
    local x = Database:GetSetting("questBarX")
    local y = Database:GetSetting("questBarY")

    if point and x and y then
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, relPoint, x, y)
    end
end

function QuestBar:UpdateFontSize()
    local fontSize = Database:GetSetting("iconFontSize")
    if mainButton and mainButton.count then
        mainButton.count:SetFont(DEFAULT_FONT, fontSize, "OUTLINE")
    end
    for _, button in ipairs(flyoutButtons) do
        if button.count then
            button.count:SetFont(DEFAULT_FONT, fontSize, "OUTLINE")
        end
    end
end

function QuestBar:UpdateSize()
    if not frame then return end

    local buttonSize = GetButtonSize()

    if mainButton then
        mainButton:SetSize(buttonSize, buttonSize)
    end

    for i, button in ipairs(flyoutButtons) do
        button:SetSize(buttonSize, buttonSize)
        button:ClearAllPoints()
        button:SetPoint("TOP", flyout, "TOP", 0, -PADDING - (i - 1) * (buttonSize + BUTTON_SPACING))
    end

    self:Refresh()
end

function QuestBar:UseActiveItem()
    if #questItems == 0 then return end

    local activeItem = questItems[activeItemIndex]
    if not activeItem then return end

    local bagID, slot = FindItemInBags(activeItem.itemID)
    if bagID and slot then
        UseContainerItem(bagID, slot)
    end
end

-------------------------------------------------
-- Event Handlers
-------------------------------------------------

local function OnBagUpdate()
    -- Only refresh if enabled AND shown (avoid work when disabled)
    if frame and frame:IsShown() then
        QuestBar:Refresh()
    end
end

local function OnCooldownUpdate()
    if frame and frame:IsShown() then
        QuestBar:Refresh()
    end
end

local function OnQuestLogUpdate()
    if frame then
        QuestBar:Refresh()
    end
end

-------------------------------------------------
-- Initialization
-------------------------------------------------

Events:OnPlayerLogin(function()
    QuestBar:Init()
    QuestBar:Show()
end, QuestBar)

Events:Register("BAG_UPDATE", OnBagUpdate, QuestBar)
Events:Register("BAG_UPDATE_COOLDOWN", OnCooldownUpdate, QuestBar)
Events:Register("QUEST_LOG_UPDATE", OnQuestLogUpdate, QuestBar)
Events:Register("QUEST_ACCEPTED", OnQuestLogUpdate, QuestBar)
Events:Register("QUEST_REMOVED", OnQuestLogUpdate, QuestBar)

-- Refresh when entering/leaving battlegrounds
Events:Register("PLAYER_ENTERING_WORLD", function()
    if frame then
        QuestBar:Refresh()
    end
end, QuestBar)
Events:Register("ZONE_CHANGED_NEW_AREA", function()
    if frame then
        QuestBar:Refresh()
    end
end, QuestBar)
