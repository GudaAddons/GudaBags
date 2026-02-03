local addonName, ns = ...

local GuildBankFooter = {}
ns:RegisterModule("GuildBankFrame.GuildBankFooter", GuildBankFooter)

local Constants = ns.Constants
local L = ns.L

local frame = nil
local mainGuildBankFrame = nil

local GuildBankScanner = nil
local Money = nil
local Database = nil

local function LoadComponents()
    GuildBankScanner = ns:GetModule("GuildBankScanner")
    Money = ns:GetModule("Footer.Money")
    Database = ns:GetModule("Database")
end

function GuildBankFooter:Init(parent)
    LoadComponents()

    -- Store reference to main GuildBankFrame
    mainGuildBankFrame = parent

    frame = CreateFrame("Frame", "GudaGuildBankFooter", parent)
    frame:SetHeight(Constants.FRAME.FOOTER_HEIGHT)
    frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", Constants.FRAME.PADDING, Constants.FRAME.PADDING - 2)
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -Constants.FRAME.PADDING, Constants.FRAME.PADDING - 2)

    -- Withdraw button
    local withdrawBtn = CreateFrame("Button", "GudaGuildBankWithdrawBtn", frame, "BackdropTemplate")
    withdrawBtn:SetSize(22, 22)
    withdrawBtn:SetPoint("LEFT", frame, "LEFT", 0, 0)
    withdrawBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    withdrawBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    withdrawBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    local withdrawIcon = withdrawBtn:CreateTexture(nil, "ARTWORK")
    withdrawIcon:SetSize(14, 14)
    withdrawIcon:SetPoint("CENTER")
    withdrawIcon:SetTexture("Interface\\MONEYFRAME\\Arrow-Left-Up")
    withdrawBtn.icon = withdrawIcon

    withdrawBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0, 0.8, 0.4, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["GUILD_BANK_WITHDRAW"] or "Withdraw Money")
        if GuildBankScanner and GuildBankScanner:IsGuildBankOpen() then
            local withdrawLimit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
            if withdrawLimit == -1 then
                GameTooltip:AddLine(L["GUILD_BANK_WITHDRAW_UNLIMITED"] or "Unlimited withdrawals", 0.5, 0.5, 0.5)
            elseif withdrawLimit > 0 then
                local gold = math.floor(withdrawLimit / 10000)
                GameTooltip:AddLine(string.format(L["GUILD_BANK_WITHDRAW_REMAINING"] or "Remaining today: %dg", gold), 0.5, 0.5, 0.5)
            else
                GameTooltip:AddLine(L["GUILD_BANK_WITHDRAW_NONE"] or "No withdrawal limit remaining", 1, 0.3, 0.3)
            end
        else
            GameTooltip:AddLine(L["GUILD_BANK_OFFLINE"] or "Guild bank must be open", 1, 0.3, 0.3)
        end
        GameTooltip:Show()
    end)
    withdrawBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
        GameTooltip:Hide()
    end)
    withdrawBtn:SetScript("OnClick", function()
        if GuildBankScanner and GuildBankScanner:IsGuildBankOpen() then
            StaticPopup_Show("GUILDBANK_WITHDRAW")
        end
    end)
    frame.withdrawBtn = withdrawBtn

    -- Deposit button
    local depositBtn = CreateFrame("Button", "GudaGuildBankDepositBtn", frame, "BackdropTemplate")
    depositBtn:SetSize(22, 22)
    depositBtn:SetPoint("LEFT", withdrawBtn, "RIGHT", 4, 0)
    depositBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    depositBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    depositBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    local depositIcon = depositBtn:CreateTexture(nil, "ARTWORK")
    depositIcon:SetSize(14, 14)
    depositIcon:SetPoint("CENTER")
    depositIcon:SetTexture("Interface\\MONEYFRAME\\Arrow-Right-Up")
    depositBtn.icon = depositIcon

    depositBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0, 0.8, 0.4, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["GUILD_BANK_DEPOSIT"] or "Deposit Money")
        if not GuildBankScanner or not GuildBankScanner:IsGuildBankOpen() then
            GameTooltip:AddLine(L["GUILD_BANK_OFFLINE"] or "Guild bank must be open", 1, 0.3, 0.3)
        end
        GameTooltip:Show()
    end)
    depositBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
        GameTooltip:Hide()
    end)
    depositBtn:SetScript("OnClick", function()
        if GuildBankScanner and GuildBankScanner:IsGuildBankOpen() then
            StaticPopup_Show("GUILDBANK_DEPOSIT")
        end
    end)
    frame.depositBtn = depositBtn

    -- Slot counter (used/total)
    local slotInfoFrame = CreateFrame("Frame", nil, frame)
    slotInfoFrame:SetPoint("LEFT", depositBtn, "RIGHT", 8, 0)
    slotInfoFrame:SetSize(100, 16)

    local slotInfo = slotInfoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    slotInfo:SetPoint("LEFT", slotInfoFrame, "LEFT", 0, 0)
    slotInfo:SetTextColor(0.8, 0.8, 0.8)
    slotInfo:SetShadowOffset(1, -1)
    slotInfo:SetShadowColor(0, 0, 0, 1)
    frame.slotInfo = slotInfo
    frame.slotInfoFrame = slotInfoFrame

    -- Tooltip on hover for slot info
    slotInfoFrame:SetScript("OnEnter", function(self)
        if frame.tabSlotData then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["TITLE_GUILD_BANK"] or "Guild Bank Slots", 1, 1, 1)
            GameTooltip:AddLine(" ")

            -- Show per-tab slot info
            for tabIndex, data in pairs(frame.tabSlotData) do
                local used = data.total - data.free
                local tabName = data.name or string.format("Tab %d", tabIndex)
                GameTooltip:AddDoubleLine(tabName .. ":", string.format("%d/%d", used, data.total), 0, 0.8, 0.4, 0.8, 0.8, 0.8)
            end

            GameTooltip:Show()
        end
    end)
    slotInfoFrame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Guild money display (guild bank balance)
    local moneyText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    moneyText:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    moneyText:SetTextColor(1, 0.82, 0)
    moneyText:SetShadowOffset(1, -1)
    moneyText:SetShadowColor(0, 0, 0, 1)
    frame.moneyText = moneyText

    return frame
end

function GuildBankFooter:Show()
    if not frame then return end
    frame:Show()
    self:Update()
end

function GuildBankFooter:Hide()
    if not frame then return end
    frame:Hide()
end

function GuildBankFooter:Update()
    if not frame then return end

    -- Update button states based on whether guild bank is open
    local isOpen = GuildBankScanner and GuildBankScanner:IsGuildBankOpen() or false
    self:UpdateButtonStates(isOpen)

    -- Update slot count
    if GuildBankScanner then
        local total, free = GuildBankScanner:GetTotalSlots()
        local used = total - free
        frame.slotInfo:SetText(string.format("%d/%d", used, total))

        -- Build per-tab data for tooltip
        frame.tabSlotData = {}
        local cachedBank = GuildBankScanner:GetCachedGuildBank()
        if cachedBank then
            for tabIndex, tabData in pairs(cachedBank) do
                frame.tabSlotData[tabIndex] = {
                    name = tabData.name,
                    total = tabData.numSlots or 0,
                    free = tabData.freeSlots or 0,
                }
            end
        end
    else
        frame.slotInfo:SetText("0/0")
    end

    -- Update guild money display
    self:UpdateMoney()
end

function GuildBankFooter:UpdateButtonStates(isOpen)
    if not frame then return end

    if isOpen then
        -- Enable buttons
        if frame.withdrawBtn then
            frame.withdrawBtn:Enable()
            frame.withdrawBtn.icon:SetDesaturated(false)
            frame.withdrawBtn.icon:SetAlpha(1)
        end
        if frame.depositBtn then
            frame.depositBtn:Enable()
            frame.depositBtn.icon:SetDesaturated(false)
            frame.depositBtn.icon:SetAlpha(1)
        end
    else
        -- Disable buttons (but keep them visible for offline viewing)
        if frame.withdrawBtn then
            frame.withdrawBtn:Disable()
            frame.withdrawBtn.icon:SetDesaturated(true)
            frame.withdrawBtn.icon:SetAlpha(0.5)
        end
        if frame.depositBtn then
            frame.depositBtn:Disable()
            frame.depositBtn.icon:SetDesaturated(true)
            frame.depositBtn.icon:SetAlpha(0.5)
        end
    end
end

function GuildBankFooter:UpdateMoney()
    if not frame or not frame.moneyText then return end

    -- Get guild bank money (if available)
    local guildMoney = GetGuildBankMoney and GetGuildBankMoney() or 0

    if guildMoney > 0 then
        local gold = math.floor(guildMoney / 10000)
        local silver = math.floor((guildMoney % 10000) / 100)
        local copper = guildMoney % 100

        local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12|t"
        local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12|t"
        local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:12|t"

        local result = ""
        if gold > 0 then
            result = string.format("%d%s", gold, GOLD_ICON)
        end
        if silver > 0 then
            if result ~= "" then result = result .. " " end
            result = result .. string.format("%d%s", silver, SILVER_ICON)
        end
        if copper > 0 or result == "" then
            if result ~= "" then result = result .. " " end
            result = result .. string.format("%d%s", copper, COPPER_ICON)
        end

        frame.moneyText:SetText(result)
    else
        frame.moneyText:SetText("")
    end
end

function GuildBankFooter:UpdateSlotInfo(used, total)
    if not frame or not frame.slotInfo then return end
    frame.slotInfo:SetText(string.format("%d/%d", used, total))
end

function GuildBankFooter:GetFrame()
    return frame
end
