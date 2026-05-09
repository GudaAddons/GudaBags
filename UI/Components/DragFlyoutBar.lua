local addonName, ns = ...

local DragFlyoutBar = {}
ns:RegisterModule("DragFlyoutBar", DragFlyoutBar)

-------------------------------------------------
-- Layout
-------------------------------------------------

local BUTTON_SIZE = 36
local BUTTON_SPACING = 6
local BAR_PADDING = 3
local BAR_GAP = 2

local TARGETS = { "track", "lock", "pin", "junk" }

local TARGET_ICONS = {
    track = "Interface\\AddOns\\GudaBags\\Assets\\fav.png",
    lock  = "Interface\\AddOns\\GudaBags\\Assets\\lock.png",
    pin   = "Interface\\AddOns\\GudaBags\\Assets\\pin.png",
    junk  = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
}

-- Per-target visual nudges (some Blizzard textures have asymmetric padding)
local TARGET_ICON_Y_OFFSET = {
    junk = -3,
}

-------------------------------------------------
-- State
-------------------------------------------------

local bar = nil
local buttons = {}
local dropCooldown = false
local currentItemID = nil
local currentBagID = nil
local currentSlot = nil

-------------------------------------------------
-- Forward declarations
-------------------------------------------------

local UpdateButtonState

-------------------------------------------------
-- Tooltip helpers (state-aware, reads cursor item state)
-------------------------------------------------

local function GetTooltipText(targetType)
    local L = ns.L

    if targetType == "track" then
        local TrackedBar = ns:GetModule("TrackedBar")
        local isOn = TrackedBar and currentItemID and TrackedBar:IsTracked(currentItemID)
        return isOn and L["TOOLTIP_FLYOUT_TRACK_ON"] or L["TOOLTIP_FLYOUT_TRACK_OFF"]
    elseif targetType == "lock" then
        local Database = ns:GetModule("Database")
        local isOn = Database and currentItemID and Database:IsItemLocked(currentItemID)
        return isOn and L["TOOLTIP_FLYOUT_LOCK_ON"] or L["TOOLTIP_FLYOUT_LOCK_OFF"]
    elseif targetType == "pin" then
        local Database = ns:GetModule("Database")
        local isOn = Database and currentBagID and currentSlot and Database:IsPinnedSlot(currentBagID, currentSlot)
        return isOn and L["TOOLTIP_FLYOUT_PIN_ON"] or L["TOOLTIP_FLYOUT_PIN_OFF"]
    elseif targetType == "junk" then
        local Database = ns:GetModule("Database")
        local isOn = Database and currentItemID and Database:IsItemMarkedJunk(currentItemID)
        return isOn and L["TOOLTIP_FLYOUT_JUNK_ON"] or L["TOOLTIP_FLYOUT_JUNK_OFF"]
    end
end

local function ShowButtonTooltip(button, targetType)
    local text = GetTooltipText(targetType)
    if not text then return end

    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText(text, 1, 1, 1)

    if targetType == "junk" then
        local Database = ns:GetModule("Database")
        if Database and Database:GetSetting("autoVendorJunk") then
            GameTooltip:AddLine(ns.L["TOOLTIP_FLYOUT_JUNK_AUTOVENDOR"], 1, 0.82, 0)
        end
    end

    GameTooltip:Show()
end

-------------------------------------------------
-- Bar / button creation
-------------------------------------------------

local function CreateButton(targetType, index)
    local btn = CreateFrame("Button", nil, bar)
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)

    local x = BAR_PADDING + (index - 1) * (BUTTON_SIZE + BUTTON_SPACING)
    btn:SetPoint("TOPLEFT", bar, "TOPLEFT", x, -BAR_PADDING)

    -- Slot background (matches CategoryDropIndicator style)
    local slotBg = btn:CreateTexture(nil, "BACKGROUND")
    slotBg:SetPoint("TOPLEFT", btn, "TOPLEFT", -9, 9)
    slotBg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 9, -9)
    slotBg:SetTexture("Interface\\Buttons\\UI-EmptySlot")
    slotBg:SetVertexColor(0.6, 0.6, 0.6, 0.9)
    btn.slotBg = slotBg

    -- Icon
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER", btn, "CENTER", 0, TARGET_ICON_Y_OFFSET[targetType] or 0)
    icon:SetSize(BUTTON_SIZE * 0.7, BUTTON_SIZE * 0.7)
    icon:SetTexture(TARGET_ICONS[targetType])
    btn.icon = icon

    -- Highlight overlay
    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(icon)
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")

    btn:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            pcall(function() DragFlyoutBar:HandleDrop(targetType) end)
        end
    end)

    btn:SetScript("OnReceiveDrag", function(self)
        pcall(function() DragFlyoutBar:HandleDrop(targetType) end)
    end)

    btn:SetScript("OnEnter", function(self)
        ShowButtonTooltip(self, targetType)
    end)

    btn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    btn.targetType = targetType
    return btn
end

local function CreateBar()
    if bar then return bar end

    local barWidth = BAR_PADDING * 2 + #TARGETS * BUTTON_SIZE + (#TARGETS - 1) * BUTTON_SPACING
    local barHeight = BAR_PADDING * 2 + BUTTON_SIZE

    bar = CreateFrame("Frame", "GudaBagsDragFlyoutBar", UIParent)
    bar:SetSize(barWidth, barHeight)
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    bar:SetFrameLevel(500)

    for i, targetType in ipairs(TARGETS) do
        buttons[targetType] = CreateButton(targetType, i)
    end

    bar:Hide()
    return bar
end

-------------------------------------------------
-- State updates (icon tint based on current toggle state)
-------------------------------------------------

UpdateButtonState = function()
    local Database = ns:GetModule("Database")
    local TrackedBar = ns:GetModule("TrackedBar")

    local function tint(targetType, isOn)
        local btn = buttons[targetType]
        if not btn then return end
        if isOn then
            btn.slotBg:SetVertexColor(0.4, 0.8, 0.4, 0.95)  -- green when active
        else
            btn.slotBg:SetVertexColor(0.6, 0.6, 0.6, 0.9)
        end
    end

    tint("track", TrackedBar and currentItemID and TrackedBar:IsTracked(currentItemID))
    tint("lock",  Database and currentItemID and Database:IsItemLocked(currentItemID))
    tint("pin",   Database and currentBagID and currentSlot and Database:IsPinnedSlot(currentBagID, currentSlot))
    tint("junk",  Database and currentItemID and Database:IsItemMarkedJunk(currentItemID))
end

-------------------------------------------------
-- Public API
-------------------------------------------------

function DragFlyoutBar:OnDragStart(itemID, bagID, slot, source)
    if dropCooldown then return end
    if source ~= "bag" then return end
    if not itemID then return end

    local BagFrame = ns:GetModule("BagFrame")
    if not BagFrame or not BagFrame:IsShown() then return end

    local frame = BagFrame:GetFrame()
    if not frame then return end

    CreateBar()

    currentItemID = itemID
    currentBagID = bagID
    currentSlot = slot

    UpdateButtonState()

    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, BAR_GAP)
    bar:Show()
end

function DragFlyoutBar:OnDragEnd()
    self:Hide(false)
end

function DragFlyoutBar:Hide(fromDrop)
    if bar then
        bar:Hide()
    end
    GameTooltip:Hide()

    currentItemID = nil
    currentBagID = nil
    currentSlot = nil

    if fromDrop then
        dropCooldown = true
        C_Timer.After(0.2, function()
            dropCooldown = false
        end)
    end
end

function DragFlyoutBar:IsShown()
    return bar and bar:IsShown()
end

-------------------------------------------------
-- Drop handling
-------------------------------------------------

function DragFlyoutBar:HandleDrop(targetType)
    if InCombatLockdown() then return end

    local infoType, itemID = GetCursorInfo()
    if infoType ~= "item" or not itemID then
        self:Hide(true)
        return
    end

    local BagFrame = ns:GetModule("BagFrame")
    local Database = ns:GetModule("Database")

    if targetType == "track" then
        ClearCursor()
        local TrackedBar = ns:GetModule("TrackedBar")
        if TrackedBar then
            TrackedBar:ToggleTrackItem(itemID)
        end

    elseif targetType == "lock" then
        ClearCursor()
        if Database then
            Database:ToggleItemLock(itemID)
        end
        if BagFrame then
            BagFrame:Refresh()
        end

    elseif targetType == "pin" then
        local bagID, slot
        if BagFrame and BagFrame.GetCursorBagSlot then
            bagID, slot = BagFrame:GetCursorBagSlot()
        end
        bagID = bagID or currentBagID
        slot = slot or currentSlot
        ClearCursor()
        if Database and bagID and slot then
            Database:TogglePinnedSlot(bagID, slot)
            if BagFrame and BagFrame.RefreshPinIcons then
                BagFrame:RefreshPinIcons()
            end
        end

    elseif targetType == "junk" then
        ClearCursor()
        if Database then
            Database:ToggleItemMarkedJunk(itemID)
        end
        if BagFrame then
            BagFrame:Refresh()
        end
    end

    self:Hide(true)
end

-------------------------------------------------
-- Combat hide
-------------------------------------------------

local Events = ns:GetModule("Events")
Events:Register("PLAYER_REGEN_DISABLED", function()
    if DragFlyoutBar:IsShown() then
        DragFlyoutBar:Hide(false)
    end
end, DragFlyoutBar)
