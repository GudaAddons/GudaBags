local addonName, ns = ...

local Slider = {}
ns:RegisterModule("Controls.Slider", Slider)

local Database = ns:GetModule("Database")
local Events = ns:GetModule("Events")

local DEFAULT_HEIGHT = 45
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

function Slider:Create(parent, config)
    -- config = { key, label, min, max, step, format, width }
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(DEFAULT_HEIGHT)
    if config.width then
        container:SetWidth(config.width)
    end

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    label:SetText(config.label)
    label:SetTextColor(1, 0.82, 0)

    local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)

    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
    slider:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -18)
    slider:SetMinMaxValues(config.min, config.max)
    slider:SetValueStep(config.step)
    slider:SetObeyStepOnDrag(true)
    slider:SetHeight(20)

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(4)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    track:SetTexture("Interface\\Buttons\\WHITE8x8")
    track:SetVertexColor(0.3, 0.3, 0.3, 1)

    local trackFill = slider:CreateTexture(nil, "ARTWORK")
    trackFill:SetHeight(4)
    trackFill:SetPoint("LEFT", slider, "LEFT", 0, 0)
    trackFill:SetTexture("Interface\\Buttons\\WHITE8x8")
    trackFill:SetVertexColor(0.6, 0.5, 0.2, 1)

    slider.Low:SetText(config.min)
    slider.High:SetText(config.max)
    slider.Text:SetText("")

    local function FormatValue(value)
        if config.format then
            if config.format == "%" then
                return value .. "%"
            elseif config.format == "px" then
                return value .. "px"
            elseif type(config.format) == "function" then
                return config.format(value)
            end
        end
        return tostring(value)
    end

    local function UpdateTrackFill()
        local min, max = slider:GetMinMaxValues()
        local val = slider:GetValue()
        local pct = (val - min) / (max - min)
        local width = slider:GetWidth() * pct
        if width < 1 then width = 1 end
        trackFill:SetWidth(width)
    end

    local currentValue = Database:GetSetting(config.key) or config.min
    slider:SetValue(currentValue)
    valueText:SetText(FormatValue(currentValue))

    -- Debounce timer for expensive updates
    local debounceTimer = nil
    local DEBOUNCE_DELAY = 0.1  -- 100ms delay

    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / config.step + 0.5) * config.step
        valueText:SetText(FormatValue(value))
        UpdateTrackFill()

        -- Save setting immediately (cheap operation)
        Database:SetSetting(config.key, value)

        -- Debounce the event firing (expensive UI updates)
        if debounceTimer then
            debounceTimer:Cancel()
        end
        debounceTimer = C_Timer.NewTimer(DEBOUNCE_DELAY, function()
            Events:Fire("SETTING_CHANGED", config.key, value)
            debounceTimer = nil
        end)
    end)

    slider:SetScript("OnShow", UpdateTrackFill)
    C_Timer.After(0.1, UpdateTrackFill)

    -- Public API
    container.GetValue = function() return slider:GetValue() end
    container.SetValue = function(self, v)
        slider:SetValue(v)
        valueText:SetText(FormatValue(v))
    end
    container.GetSettingKey = function() return config.key end
    container.Refresh = function(self)
        local v = Database:GetSetting(config.key) or config.min
        slider:SetValue(v)
        valueText:SetText(FormatValue(v))
    end

    return container
end

return Slider
