local addonName, ns = ...

local Select = {}
ns:RegisterModule("Controls.Select", Select)

local Database = ns:GetModule("Database")
local Events = ns:GetModule("Events")

local DEFAULT_HEIGHT = 26

function Select:Create(parent, config)
    -- config = { key, label, options = {{value, label}, ...}, tooltip, width }
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(DEFAULT_HEIGHT)

    -- Label on the left, right-aligned to center
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", container, "LEFT", 0, 0)
    label:SetPoint("RIGHT", container, "CENTER", -60, 0)
    label:SetJustifyH("RIGHT")
    label:SetText(config.label)

    -- Build entries and values arrays
    local entries = {}
    local values = {}
    for _, opt in ipairs(config.options) do
        table.insert(entries, opt.label)
        table.insert(values, opt.value)
    end

    local currentValue = Database:GetSetting(config.key)

    -- Try to use WowStyle1DropdownTemplate if available
    local dropdown
    local useModernDropdown = DoesTemplateExist and DoesTemplateExist("WowStyle1DropdownTemplate")

    if useModernDropdown then
        dropdown = CreateFrame("DropdownButton", nil, container, "WowStyle1DropdownTemplate")
        dropdown:SetPoint("LEFT", container, "CENTER", -50, 0)
        dropdown:SetPoint("RIGHT", container, "RIGHT", -10, 0)

        -- Build menu entries for MenuUtil
        local menuEntries = {}
        for i = 1, #entries do
            table.insert(menuEntries, {entries[i], values[i]})
        end

        -- Use MenuUtil.CreateRadioMenu for radio-style selection
        MenuUtil.CreateRadioMenu(dropdown, function(value)
            return Database:GetSetting(config.key) == value
        end, function(value)
            Database:SetSetting(config.key, value)
            Events:Fire("SETTING_CHANGED", config.key, value)
        end, unpack(menuEntries))

        -- Public API for modern dropdown
        container.GetValue = function()
            return Database:GetSetting(config.key)
        end
        container.SetValue = function(self, v)
            dropdown:GenerateMenu()
        end
        container.Refresh = function(self)
            dropdown:GenerateMenu()
        end
    else
        -- Fallback to UIDropDownMenuTemplate
        local dropdownName = "GudaBagsDropdown" .. tostring(config.key):gsub("%.", "_")
        dropdown = CreateFrame("Frame", dropdownName, container, "UIDropDownMenuTemplate")
        dropdown:SetPoint("LEFT", container, "CENTER", -70, 0)
        UIDropDownMenu_SetWidth(dropdown, 140)

        local function InitializeDropdown(self, level)
            level = level or 1
            if level ~= 1 then return end

            local currentVal = Database:GetSetting(config.key)
            for i, opt in ipairs(config.options) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = opt.label
                info.value = opt.value
                info.checked = (opt.value == currentVal)
                info.func = function()
                    Database:SetSetting(config.key, opt.value)
                    Events:Fire("SETTING_CHANGED", config.key, opt.value)
                    UIDropDownMenu_SetText(dropdown, opt.label)
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end

        UIDropDownMenu_Initialize(dropdown, InitializeDropdown)

        -- Set initial text
        for _, opt in ipairs(config.options) do
            if opt.value == currentValue then
                UIDropDownMenu_SetText(dropdown, opt.label)
                break
            end
        end

        -- Public API for classic dropdown
        container.GetValue = function()
            return Database:GetSetting(config.key)
        end
        container.SetValue = function(self, v)
            for _, opt in ipairs(config.options) do
                if opt.value == v then
                    UIDropDownMenu_SetText(dropdown, opt.label)
                    break
                end
            end
        end
        container.Refresh = function(self)
            local v = Database:GetSetting(config.key)
            for _, opt in ipairs(config.options) do
                if opt.value == v then
                    UIDropDownMenu_SetText(dropdown, opt.label)
                    break
                end
            end
        end
    end

    container.GetSettingKey = function()
        return config.key
    end
    container.CloseDropdown = function()
        CloseDropDownMenus()
    end

    return container
end

-- Global function to close any open dropdown
function Select:CloseAll()
    CloseDropDownMenus()
end

return Select
