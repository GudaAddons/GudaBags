local addonName, ns = ...

local Hearthstone = {}
ns:RegisterModule("Footer.Hearthstone", Hearthstone)

local Constants = ns.Constants
local L = ns.L

local function GetDatabase()
    return ns:GetModule("Database")
end

local button = nil
local wrapper = nil

local function FindHearthstone()
    for _, bagID in ipairs(Constants.BAG_IDS) do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
            if itemInfo and itemInfo.itemID == Constants.HEARTHSTONE_ID then
                return bagID, slot, itemInfo.hyperlink
            end
        end
    end
    return nil, nil, nil
end

function Hearthstone:Init(parent)
    local bagSlotSize = Constants.BAG_SLOT_SIZE

    wrapper = CreateFrame("Frame", "GudaBagsHearthstoneWrapper", parent)
    wrapper:SetSize(bagSlotSize, bagSlotSize)
    wrapper:EnableMouse(false)  -- Wrapper should not intercept mouse

    button = CreateFrame("ItemButton", "GudaBagsHearthstoneButton", wrapper, "ContainerFrameItemButtonTemplate, BackdropTemplate")
    button:SetSize(bagSlotSize, bagSlotSize)
    button:SetAllPoints(wrapper)
    button.wrapper = wrapper

    -- Disable mouse on all child frames from the template (retail has many overlays)
    local function DisableChildMouse(frame)
        for _, child in pairs({frame:GetChildren()}) do
            if child.EnableMouse then
                child:EnableMouse(false)
            end
            if child.SetHitRectInsets then
                child:SetHitRectInsets(1000, 1000, 1000, 1000)
            end
            child:Hide()
            if child.GetChildren then
                DisableChildMouse(child)
            end
        end
    end
    DisableChildMouse(button)

    -- Also check for and disable NineSlice (retail frame decoration)
    if button.NineSlice then
        button.NineSlice:Hide()
        if button.NineSlice.EnableMouse then button.NineSlice:EnableMouse(false) end
    end

    -- Ensure button receives mouse input
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp", "AnyDown")

    -- Hide template's built-in visual elements
    for _, region in pairs({button:GetRegions()}) do
        if region:IsObjectType("Texture") then
            region:SetTexture(nil)
            region:Hide()
        end
    end

    local normalTex = button:GetNormalTexture()
    if normalTex then
        normalTex:SetTexture(nil)
        normalTex:Hide()
    end

    local globalNormal = _G["GudaBagsHearthstoneButtonNormalTexture"]
    if globalNormal then
        globalNormal:SetTexture(nil)
        globalNormal:Hide()
    end

    -- Hide retail-specific template elements (Midnight/TWW)
    -- Reparent overlays to remove from button hierarchy entirely
    local function DisableOverlay(overlay)
        if not overlay then return end
        overlay:Hide()
        overlay:SetAlpha(0)
        overlay:ClearAllPoints()
        if overlay.SetParent then overlay:SetParent(nil) end
        if overlay.EnableMouse then overlay:EnableMouse(false) end
        if overlay.SetHitRectInsets then overlay:SetHitRectInsets(1000, 1000, 1000, 1000) end
        if overlay.SetScript then
            overlay:SetScript("OnShow", function(self) self:Hide() end)
            overlay:SetScript("OnEnter", nil)
            overlay:SetScript("OnLeave", nil)
            overlay:SetScript("OnMouseDown", nil)
            overlay:SetScript("OnMouseUp", nil)
        end
    end

    DisableOverlay(button.ItemContextOverlay)
    DisableOverlay(button.SearchOverlay)
    DisableOverlay(button.ExtendedSlot)
    DisableOverlay(button.UpgradeIcon)
    DisableOverlay(button.ItemSlotBackground)
    DisableOverlay(button.JunkIcon)
    DisableOverlay(button.flash)
    DisableOverlay(button.NewItem)
    DisableOverlay(button.Cooldown)  -- Template's cooldown
    DisableOverlay(button.WidgetContainer)
    DisableOverlay(button.LevelLinkLockIcon)
    DisableOverlay(button.BagIndicator)
    if button.IconBorder then button.IconBorder:Hide() end
    if button.IconOverlay then button.IconOverlay:Hide() end

    -- Reset hit rect and ensure mouse input works
    button:SetHitRectInsets(0, 0, 0, 0)
    if button.SetMouseClickEnabled then button:SetMouseClickEnabled(true) end
    if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(true) end

    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    button:SetBackdropColor(0.15, 0.15, 0.15, 0.7)
    button:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)

    local hsIcon = button:CreateTexture(nil, "ARTWORK", nil, 1)
    hsIcon:SetSize(18, 18)
    hsIcon:SetPoint("CENTER")
    hsIcon:SetTexture("Interface\\Icons\\INV_Misc_Rune_01")
    button.hsIcon = hsIcon

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    local cooldown = CreateFrame("Cooldown", "GudaBagsHearthstoneCooldown", button, "CooldownFrameTemplate")
    cooldown:SetAllPoints()
    cooldown:SetDrawEdge(false)
    -- Make cooldown text smaller for the small button
    cooldown:SetHideCountdownNumbers(false)
    local cooldownText = cooldown:GetRegions()
    if cooldownText and cooldownText.SetFont then
        cooldownText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    end
    button.cooldown = cooldown

    button:HookScript("OnEnter", function(self)
        if self.bag and self.slot then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetBagItem(self.bag, self.slot)
            GameTooltip:Show()
        else
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(L["HEARTHSTONE"], 1, 1, 1)
            GameTooltip:AddLine(L["NOT_IN_BAGS"], 1, 0, 0)
            GameTooltip:Show()
        end
    end)

    button:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return wrapper
end

function Hearthstone:SetAnchor(anchorTo)
    if not wrapper then return end
    wrapper:ClearAllPoints()
    wrapper:SetPoint("LEFT", anchorTo, "RIGHT", 8, 0)
end

function Hearthstone:Show()
    if button and wrapper then
        button:Show()
        wrapper:Show()
    end
end

function Hearthstone:Hide()
    if button and wrapper then
        button:Hide()
        wrapper:Hide()
    end
end

function Hearthstone:Update()
    if not button or not wrapper then return end

    local showFooter = GetDatabase():GetSetting("showFooter")

    if not showFooter then
        button:Hide()
        wrapper:Hide()
        return
    end

    local bag, slot, link = FindHearthstone()

    if bag then
        button:SetAlpha(1)
        button:Show()
        wrapper:Show()

        wrapper:SetID(bag)
        button:SetID(slot)

        if button.IconBorder then button.IconBorder:Hide() end
        if button.icon then button.icon:Hide() end

        local start, duration, enable = C_Container.GetContainerItemCooldown(bag, slot)
        if button.cooldown and start and duration and duration > 0 then
            button.cooldown:SetCooldown(start, duration)
        elseif button.cooldown then
            button.cooldown:Clear()
        end

        button.bag = bag
        button.slot = slot
        button.link = link
    else
        button:SetAlpha(0.3)
        button:Show()
        wrapper:Show()

        wrapper:SetID(0)
        button:SetID(0)

        button.bag = nil
        button.slot = nil
        button.link = nil
        if button.cooldown then
            button.cooldown:Clear()
        end
    end
end

function Hearthstone:GetButton()
    return button
end

function Hearthstone:GetWrapper()
    return wrapper
end
