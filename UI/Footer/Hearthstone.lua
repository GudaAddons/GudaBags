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
    wrapper:EnableMouse(false)
    wrapper:SetFrameLevel(parent:GetFrameLevel() + 5)

    -- Use SecureActionButtonTemplate for proper item use
    button = CreateFrame("Button", "GudaBagsHearthstoneButton", wrapper, "SecureActionButtonTemplate, BackdropTemplate")
    button:SetSize(bagSlotSize, bagSlotSize)
    button:SetAllPoints(wrapper)
    -- Use AnyDown only - fires on mouse press, not release (prevents double-firing)
    button:RegisterForClicks("AnyDown")

    -- Set up left-click (type1) and right-click (type2) to use hearthstone
    -- Using macro with item ID is most reliable across all locales
    local hsItemString = "/use item:" .. Constants.HEARTHSTONE_ID
    button:SetAttribute("type1", "macro")
    button:SetAttribute("macrotext1", hsItemString)
    button:SetAttribute("type2", "macro")
    button:SetAttribute("macrotext2", hsItemString)

    -- Ensure button is interactive
    button:EnableMouse(true)
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel(100)

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
    cooldown:SetHideCountdownNumbers(false)
    local cooldownText = cooldown:GetRegions()
    if cooldownText and cooldownText.SetFont then
        cooldownText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    end
    button.cooldown = cooldown

    button:SetScript("OnEnter", function(self)
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

    button:SetScript("OnLeave", function()
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

        -- Update cooldown
        local start, duration, enable = C_Container.GetContainerItemCooldown(bag, slot)
        if button.cooldown and start and duration and duration > 0 then
            button.cooldown:SetCooldown(start, duration)
        elseif button.cooldown then
            button.cooldown:Clear()
        end

        -- Store for tooltip
        button.bag = bag
        button.slot = slot
        button.link = link
    else
        button:SetAlpha(0.3)
        button:Show()
        wrapper:Show()

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
