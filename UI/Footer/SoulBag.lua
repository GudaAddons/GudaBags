local addonName, ns = ...

-- Soul bags exist in Classic Era and TBC (Warlock class feature)
-- Check if player is a Warlock
local _, playerClass = UnitClass("player")
if playerClass ~= "WARLOCK" then
    -- Register empty stub module for non-Warlocks
    ns:RegisterModule("Footer.SoulBag", {
        Init = function() return nil end,
        Show = function() end,
        Hide = function() end,
        SetAnchor = function() end,
        SetCallback = function() end,
        IsVisible = function() return true end,  -- Default to showing soul bags when not a warlock (no toggle needed)
        GetButton = function() return nil end,
        UpdateState = function() end,
    })
    return
end

local SoulBag = {}
ns:RegisterModule("Footer.SoulBag", SoulBag)

local Constants = ns.Constants
local L = ns.L

local button = nil
local onSoulBagToggle = nil
local mainBagFrame = nil
local Database = nil

local function GetDatabase()
    if not Database then
        Database = ns:GetModule("Database")
    end
    return Database
end

local function IsShowingSoulBag()
    local db = GetDatabase()
    if db then
        local value = db:GetSetting("showSoulBag")
        if value ~= nil then
            return value
        end
    end
    return true  -- Default to showing
end

local function SetShowingSoulBag(value)
    local db = GetDatabase()
    if db then
        db:SetSetting("showSoulBag", value)
    end
end

function SoulBag:Init(parent)
    -- Store reference to main BagFrame (parent's parent is the main frame)
    mainBagFrame = parent:GetParent()

    local bagSlotSize = Constants.BAG_SLOT_SIZE
    button = CreateFrame("Button", "GudaBagsSoulBagButton", parent, "BackdropTemplate")
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
    icon:SetTexture("Interface\\AddOns\\GudaBags\\Assets\\soul.png")
    button.icon = icon

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["SOULBAG"] or "Soul Bag")
        if IsShowingSoulBag() then
            GameTooltip:AddLine(L["CLICK_HIDE_SOULBAG"] or "Click to hide soul bag", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine(L["CLICK_SHOW_SOULBAG"] or "Click to show soul bag", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()

        if IsShowingSoulBag() then
            local ItemButton = ns:GetModule("ItemButton")
            local BagClassifier = ns:GetModule("BagFrame.BagClassifier")
            if ItemButton and BagClassifier then
                -- Highlight all soul bag slots
                local classifiedBags = BagClassifier:ClassifyBags()
                if classifiedBags.soul then
                    for _, bagID in ipairs(classifiedBags.soul) do
                        ItemButton:HighlightBagSlots(bagID)
                    end
                end
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
        local newValue = not IsShowingSoulBag()
        SetShowingSoulBag(newValue)
        SoulBag:UpdateState()
        if onSoulBagToggle then
            onSoulBagToggle(newValue)
        end
    end)

    return button
end

function SoulBag:SetAnchor(anchorTo)
    if not button then return end
    button:ClearAllPoints()
    button:SetPoint("LEFT", anchorTo, "RIGHT", 1, 0)
end

function SoulBag:Show()
    if button then
        button:Show()
    end
end

function SoulBag:Hide()
    if button then
        button:Hide()
    end
end

function SoulBag:UpdateState()
    if not button then return end
    if IsShowingSoulBag() then
        button:SetBackdropBorderColor(0.5, 0.3, 0.8, 1)  -- Purple border when showing
    else
        button:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.7)
    end
end

function SoulBag:SetCallback(callback)
    onSoulBagToggle = callback
end

function SoulBag:IsVisible()
    return IsShowingSoulBag()
end

function SoulBag:GetButton()
    return button
end
