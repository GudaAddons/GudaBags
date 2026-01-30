local addonName, ns = ...

local Keyring = {}
ns:RegisterModule("Footer.Keyring", Keyring)

local Constants = ns.Constants
local L = ns.L

local button = nil
local showKeyring = false
local onKeyringToggle = nil
local mainBagFrame = nil

function Keyring:Init(parent)
    -- Store reference to main BagFrame (parent's parent is the main frame)
    mainBagFrame = parent:GetParent()

    local bagSlotSize = Constants.BAG_SLOT_SIZE
    button = CreateFrame("Button", "GudaBagsKeyringButton", parent, "BackdropTemplate")
    button:SetSize(bagSlotSize, bagSlotSize)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    button:SetBackdropColor(0.15, 0.15, 0.15, 0.7)
    button:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\AddOns\\GudaBags\\Assets\\keyring.png")
    button.icon = icon

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(KEYRING or L["KEYRING"])
        if showKeyring then
            GameTooltip:AddLine(L["CLICK_HIDE_KEYRING"], 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine(L["CLICK_SHOW_KEYRING"], 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()

        if showKeyring then
            local ItemButton = ns:GetModule("ItemButton")
            if ItemButton then
                ItemButton:HighlightBagSlots(Constants.KEYRING_BAG_ID)
            end
        end
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()

        local ItemButton = ns:GetModule("ItemButton")
        if ItemButton then
            ItemButton:ClearHighlightedSlots(mainBagFrame)
        end
    end)

    button:SetScript("OnClick", function(self)
        showKeyring = not showKeyring
        Keyring:UpdateState()
        if onKeyringToggle then
            onKeyringToggle(showKeyring)
        end
    end)

    return button
end

function Keyring:SetAnchor(anchorTo)
    if not button then return end
    button:ClearAllPoints()
    button:SetPoint("LEFT", anchorTo, "RIGHT", 1, 0)
end

function Keyring:Show()
    if button then
        button:Show()
    end
end

function Keyring:Hide()
    if button then
        button:Hide()
    end
end

function Keyring:UpdateState()
    if not button then return end
    if showKeyring then
        button:SetBackdropBorderColor(1, 0.82, 0, 1)
    else
        button:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)
    end
end

function Keyring:SetCallback(callback)
    onKeyringToggle = callback
end

function Keyring:IsVisible()
    return showKeyring
end

function Keyring:GetButton()
    return button
end
