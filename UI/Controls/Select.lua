local addonName, ns = ...

local Select = {}
ns:RegisterModule("Controls.Select", Select)

local Database = ns:GetModule("Database")
local Events = ns:GetModule("Events")

local DEFAULT_HEIGHT = 45
local DROPDOWN_ITEM_HEIGHT = 20
local DROPDOWN_PADDING = 4

-- Track open dropdown to close when another opens
local activeDropdown = nil

local function CloseActiveDropdown()
    if activeDropdown then
        activeDropdown:Hide()
        activeDropdown = nil
    end
end

function Select:Create(parent, config)
    -- config = { key, label, options = {{value, label}, ...}, tooltip, width }
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(DEFAULT_HEIGHT)
    if config.width then
        container:SetWidth(config.width)
    end

    -- Label
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    label:SetText(config.label)
    label:SetTextColor(1, 0.82, 0)

    -- Main button
    local button = CreateFrame("Button", nil, container, "BackdropTemplate")
    button:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    button:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -18)
    button:SetHeight(22)
    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    button:SetBackdropColor(0.15, 0.15, 0.15, 1)
    button:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Button text (selected value)
    local buttonText = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    buttonText:SetPoint("LEFT", button, "LEFT", 8, 0)
    buttonText:SetPoint("RIGHT", button, "RIGHT", -20, 0)
    buttonText:SetJustifyH("LEFT")

    -- Arrow indicator
    local arrow = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    arrow:SetText("v")
    arrow:SetTextColor(0.7, 0.7, 0.7)

    -- Dropdown frame
    local dropdown = CreateFrame("Frame", nil, button, "BackdropTemplate")
    dropdown:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    dropdown:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -2)
    dropdown:SetFrameStrata("DIALOG")
    dropdown:SetFrameLevel(300)
    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    dropdown:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    dropdown:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    dropdown:Hide()

    -- Create dropdown items
    local items = {}
    local dropdownHeight = DROPDOWN_PADDING * 2

    for i, opt in ipairs(config.options) do
        local item = CreateFrame("Button", nil, dropdown)
        item:SetHeight(DROPDOWN_ITEM_HEIGHT)
        item:SetPoint("TOPLEFT", dropdown, "TOPLEFT", DROPDOWN_PADDING, -DROPDOWN_PADDING - (i - 1) * DROPDOWN_ITEM_HEIGHT)
        item:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -DROPDOWN_PADDING, -DROPDOWN_PADDING - (i - 1) * DROPDOWN_ITEM_HEIGHT)

        local itemBg = item:CreateTexture(nil, "BACKGROUND")
        itemBg:SetAllPoints()
        itemBg:SetTexture("Interface\\Buttons\\WHITE8x8")
        itemBg:SetVertexColor(0.2, 0.2, 0.2, 0)
        item.bg = itemBg

        local itemText = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        itemText:SetPoint("LEFT", item, "LEFT", 6, 0)
        itemText:SetPoint("RIGHT", item, "RIGHT", -6, 0)
        itemText:SetJustifyH("LEFT")
        itemText:SetText(opt.label)
        item.text = itemText

        item:SetScript("OnEnter", function(self)
            self.bg:SetVertexColor(0.3, 0.3, 0.3, 1)
        end)

        item:SetScript("OnLeave", function(self)
            self.bg:SetVertexColor(0.2, 0.2, 0.2, 0)
        end)

        item:SetScript("OnClick", function()
            Database:SetSetting(config.key, opt.value)
            Events:Fire("SETTING_CHANGED", config.key, opt.value)
            buttonText:SetText(opt.label)
            dropdown:Hide()
            activeDropdown = nil
        end)

        items[i] = item
        dropdownHeight = dropdownHeight + DROPDOWN_ITEM_HEIGHT
    end

    dropdown:SetHeight(dropdownHeight)

    -- Get current value and set button text
    local currentValue = Database:GetSetting(config.key)
    for _, opt in ipairs(config.options) do
        if opt.value == currentValue then
            buttonText:SetText(opt.label)
            break
        end
    end
    if buttonText:GetText() == nil or buttonText:GetText() == "" then
        buttonText:SetText(config.options[1] and config.options[1].label or "")
    end

    -- Button hover effect
    button:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end)

    button:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end)

    -- Toggle dropdown on click
    button:SetScript("OnClick", function()
        if dropdown:IsShown() then
            dropdown:Hide()
            activeDropdown = nil
        else
            CloseActiveDropdown()
            dropdown:Show()
            activeDropdown = dropdown
        end
    end)

    -- Close dropdown when clicking elsewhere
    dropdown:SetScript("OnShow", function()
        dropdown:SetPropagateKeyboardInput(true)
    end)

    -- Tooltip
    if config.tooltip then
        button:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(config.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            GameTooltip:Hide()
        end)
    end

    -- Public API
    container.GetValue = function()
        return Database:GetSetting(config.key)
    end

    container.SetValue = function(self, v)
        for _, opt in ipairs(config.options) do
            if opt.value == v then
                buttonText:SetText(opt.label)
                break
            end
        end
    end

    container.GetSettingKey = function()
        return config.key
    end

    container.Refresh = function(self)
        local v = Database:GetSetting(config.key)
        for _, opt in ipairs(config.options) do
            if opt.value == v then
                buttonText:SetText(opt.label)
                break
            end
        end
    end

    container.CloseDropdown = function()
        dropdown:Hide()
    end

    return container
end

-- Global function to close any open dropdown
function Select:CloseAll()
    CloseActiveDropdown()
end

return Select
