local addonName, ns = ...

local Checkbox = {}
ns:RegisterModule("Controls.Checkbox", Checkbox)

local Database = ns:GetModule("Database")
local Events = ns:GetModule("Events")

local DEFAULT_HEIGHT = 22

function Checkbox:Create(parent, config)
    -- config = { key, label, tooltip, width }
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(DEFAULT_HEIGHT)
    if config.width then
        container:SetWidth(config.width)
    end

    local checkbox = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    checkbox:SetPoint("LEFT", container, "LEFT", -4, 0)
    checkbox:SetSize(24, 24)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
    label:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    label:SetText(config.label)
    label:SetTextColor(1, 1, 1)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)

    local currentValue = Database:GetSetting(config.key)
    checkbox:SetChecked(currentValue)

    checkbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        Database:SetSetting(config.key, checked)
        Events:Fire("SETTING_CHANGED", config.key, checked)
    end)

    if config.tooltip then
        checkbox:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(config.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        checkbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Public API
    container.GetValue = function() return checkbox:GetChecked() end
    container.SetValue = function(self, v) checkbox:SetChecked(v) end
    container.GetSettingKey = function() return config.key end
    container.Refresh = function(self)
        local v = Database:GetSetting(config.key)
        checkbox:SetChecked(v)
    end

    return container
end

return Checkbox
