local addonName, ns = ...

local GuildBankHeader = {}
ns:RegisterModule("GuildBankFrame.GuildBankHeader", GuildBankHeader)

local Constants = ns.Constants
local L = ns.L
local Database = ns:GetModule("Database")
local IconButton = ns:GetModule("IconButton")

local frame = nil
local onDragStop = nil

local function CreateHeader(parent)
    local titleBar = CreateFrame("Frame", "GudaGuildBankHeader", parent, "BackdropTemplate")
    titleBar:SetHeight(Constants.FRAME.TITLE_HEIGHT)
    titleBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")

    titleBar:SetScript("OnMouseDown", function(self, button)
        -- Raise parent frame above other frames when clicked
        parent:SetFrameLevel(60)
        local BagFrameModule = ns:GetModule("BagFrame")
        if BagFrameModule and BagFrameModule:GetFrame() then
            BagFrameModule:GetFrame():SetFrameLevel(50)
        end
        local BankFrameModule = ns:GetModule("BankFrame")
        if BankFrameModule and BankFrameModule:GetFrame() then
            BankFrameModule:GetFrame():SetFrameLevel(50)
        end
    end)

    titleBar:SetScript("OnDragStart", function()
        if not Database:GetSetting("locked") then
            parent:StartMoving()
        end
    end)

    titleBar:SetScript("OnDragStop", function()
        parent:StopMovingOrSizing()
        if onDragStop then
            onDragStop()
        end
    end)

    local bgAlpha = Database:GetSetting("bgAlpha") / 100
    titleBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
    })
    titleBar:SetBackdropColor(0.08, 0.08, 0.08, bgAlpha)

    -- Guild name as title (will be updated when guild bank opens)
    local guildName = GetGuildInfo("player") or L["TITLE_GUILD_BANK"]
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    title:SetText(guildName .. (L["TITLE_GUILD_BANK"] or "'s Guild Bank"))
    title:SetTextColor(0, 0.8, 0.4)  -- Green-ish color for guild
    title:SetShadowOffset(1, -1)
    title:SetShadowColor(0, 0, 0, 1)
    titleBar.title = title

    -- Right side icons (created right-to-left for proper anchoring)
    local closeButton = IconButton:CreateCloseButton(titleBar, {
        onClick = function()
            parent:Hide()
        end,
        point = "RIGHT",
        offsetX = 0,
        offsetY = 0,
    })
    titleBar.closeButton = closeButton
    local lastRightButton = closeButton

    local settingsButton = IconButton:Create(titleBar, "settings", {
        tooltip = L["TOOLTIP_SETTINGS"],
        onClick = function()
            local SettingsPopup = ns:GetModule("SettingsPopup")
            SettingsPopup:Toggle()
        end,
    })
    settingsButton:SetPoint("RIGHT", lastRightButton, "LEFT", -4, 0)
    titleBar.settingsButton = settingsButton
    lastRightButton = settingsButton

    return titleBar
end

function GuildBankHeader:Init(parent)
    frame = CreateHeader(parent)
    return frame
end

function GuildBankHeader:GetFrame()
    return frame
end

function GuildBankHeader:SetDragCallback(callback)
    onDragStop = callback
end

function GuildBankHeader:SetBackdropAlpha(alpha)
    if not frame then return end
    frame:SetBackdropColor(0.08, 0.08, 0.08, alpha)
end

function GuildBankHeader:SetGuildName(guildName)
    if not frame or not frame.title then return end

    if guildName then
        frame.title:SetText(guildName .. (L["TITLE_GUILD_BANK"] or "'s Guild Bank"))
    else
        frame.title:SetText(L["TITLE_GUILD_BANK"] or "Guild Bank")
    end
end

function GuildBankHeader:UpdateTitle()
    local guildName = GetGuildInfo("player")
    self:SetGuildName(guildName)
end
