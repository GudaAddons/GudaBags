local addonName, ns = ...

local Footer = {}
ns:RegisterModule("Footer", Footer)

local Constants = ns.Constants

local function GetDatabase()
    return ns:GetModule("Database")
end

local frame = nil
local backButton = nil
local onBackCallback = nil

-- Footer components (loaded after registration)
local BagSlots = nil
local Keyring = nil
local SoulBag = nil
local Hearthstone = nil
local Money = nil

local function LoadComponents()
    BagSlots = ns:GetModule("Footer.BagSlots")
    Keyring = ns:GetModule("Footer.Keyring")
    SoulBag = ns:GetModule("Footer.SoulBag")
    Hearthstone = ns:GetModule("Footer.Hearthstone")
    Money = ns:GetModule("Footer.Money")
end

function Footer:Init(parent)
    LoadComponents()

    frame = CreateFrame("Frame", "GudaBagsFooter", parent)
    frame:SetHeight(Constants.FRAME.FOOTER_HEIGHT)
    frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", Constants.FRAME.PADDING, Constants.FRAME.PADDING - 5)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -Constants.FRAME.PADDING, Constants.FRAME.PADDING - 5)

    -- Initialize components
    frame.bagSlotsFrame = BagSlots:Init(frame)

    -- Initialize soul bag toggle (Warlock only - returns nil for other classes)
    frame.soulBagButton = SoulBag:Init(frame)
    local soulBagButton = SoulBag:GetButton()

    -- Initialize keyring (TBC only - returns nil for other expansions)
    frame.keyringButton = Keyring:Init(frame)
    local keyringButton = Keyring:GetButton()

    -- Slot counter after keyring, soul bag, or bag slots (with tooltip frame for hover)
    local slotInfoFrame = CreateFrame("Frame", nil, frame)
    -- Anchor to rightmost special button available
    if keyringButton then
        slotInfoFrame:SetPoint("LEFT", keyringButton, "RIGHT", 32, 0)
    elseif soulBagButton then
        slotInfoFrame:SetPoint("LEFT", soulBagButton, "RIGHT", 32, 0)
    else
        slotInfoFrame:SetPoint("LEFT", BagSlots:GetAnchor(), "RIGHT", 32, 0)
    end
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
            GameTooltip:AddLine("Bag Slots", 1, 1, 1)
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

    frame.hearthstoneWrapper = Hearthstone:Init(frame)
    frame.moneyFrame = Money:Init(frame)

    -- Create back button (hidden by default, shown when viewing cached)
    backButton = CreateFrame("Button", "GudaBagsBackButton", frame)
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

function Footer:Show()
    if not frame then return end
    frame:Show()

    -- Hide back button (only for cached views)
    if backButton then
        backButton:Hide()
    end

    -- Reset viewing character to current character
    BagSlots:SetViewingCharacter(nil)

    -- Show bag slots and get anchor
    BagSlots:Show()
    local bagAnchor = BagSlots:GetAnchor()
    local lastAnchor = bagAnchor

    -- Position soul bag relative to bag slots (Warlock only)
    local soulBagButton = SoulBag:GetButton()
    if soulBagButton then
        SoulBag:SetAnchor(lastAnchor)
        SoulBag:Show()
        lastAnchor = soulBagButton
    end

    -- Position keyring relative to soul bag or bag slots (TBC only)
    local keyringButton = Keyring:GetButton()
    if keyringButton then
        Keyring:SetAnchor(lastAnchor)
        Keyring:Show()
        lastAnchor = keyringButton
    end

    -- Position hearthstone relative to rightmost button
    Hearthstone:SetAnchor(lastAnchor)
    Hearthstone:Update()

    -- Show money
    Money:Show()

    self:Update()
end

function Footer:Hide()
    if not frame then return end
    frame:Hide()

    BagSlots:Hide()
    if Keyring:GetButton() then
        Keyring:Hide()
    end
    if SoulBag:GetButton() then
        SoulBag:Hide()
    end
    Hearthstone:Hide()
    Money:Hide()
    if backButton then
        backButton:Hide()
    end
end

function Footer:Update()
    if not frame then return end

    BagSlots:Update()
    Hearthstone:Update()
    Money:Update()
    if Keyring:GetButton() then
        Keyring:UpdateState()
    end
    if SoulBag:GetButton() then
        SoulBag:UpdateState()
    end
end

function Footer:UpdateBagSlots()
    if BagSlots then
        BagSlots:Update()
    end
end

function Footer:UpdateHearthstone()
    if Hearthstone then
        Hearthstone:Update()
    end
end

function Footer:UpdateMoney()
    if Money then
        Money:Update()
    end
end

function Footer:UpdateSlotInfo(used, total, regularTotal, regularFree, specialBags)
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

function Footer:UpdateKeyringState()
    if Keyring then
        Keyring:UpdateState()
    end
end

function Footer:SetKeyringCallback(callback)
    if Keyring then
        Keyring:SetCallback(callback)
    end
end

function Footer:IsKeyringVisible()
    if Keyring then
        return Keyring:IsVisible()
    end
    return false
end

function Footer:SetSoulBagCallback(callback)
    if SoulBag then
        SoulBag:SetCallback(callback)
    end
end

function Footer:IsSoulBagVisible()
    if SoulBag then
        return SoulBag:IsVisible()
    end
    return true  -- Default to showing soul bags when module not available
end

function Footer:GetFrame()
    return frame
end

-- Show footer in cached mode (bag slots for highlighting, keyring toggle, cached money)
function Footer:ShowCached(characterFullName)
    if not frame then return end
    frame:Show()

    -- Hide back button
    if backButton then
        backButton:Hide()
    end

    -- Set viewing character for bag slot textures
    BagSlots:SetViewingCharacter(characterFullName)

    -- Show bag slots for hover highlighting
    BagSlots:Show()
    local bagAnchor = BagSlots:GetAnchor()
    local lastAnchor = bagAnchor

    -- Position and show soul bag toggle (Warlock only)
    local soulBagButton = SoulBag:GetButton()
    if soulBagButton then
        SoulBag:SetAnchor(lastAnchor)
        SoulBag:Show()
        lastAnchor = soulBagButton
    end

    -- Position and show keyring for toggle functionality (TBC only)
    local keyringButton = Keyring:GetButton()
    if keyringButton then
        Keyring:SetAnchor(lastAnchor)
        Keyring:Show()
    end

    -- Hide hearthstone (not relevant for cached views)
    Hearthstone:Hide()

    -- Show and update money for the cached character
    Money:Show()
    Money:UpdateCached(characterFullName)

    -- Update bag slots and keyring/soul bag state
    BagSlots:Update()
    if keyringButton then
        Keyring:UpdateState()
    end
    if soulBagButton then
        SoulBag:UpdateState()
    end
end

function Footer:SetBackCallback(callback)
    onBackCallback = callback
end
