local addonName, ns = ...

-- Settings row: label + color swatch (opens Blizzard's color picker, live
-- preview) + Reset. The setting holds {r, g, b}, or nil for the default.

local ColorPicker = {}
ns:RegisterModule("Controls.ColorPicker", ColorPicker)

local Database = ns:GetModule("Database")
local Events = ns:GetModule("Events")

local DEFAULT_HEIGHT = 26
local SWATCH_SIZE = 18

-- Blizzard's color picker changed API in 10.2.5 (SetupColorPickerAndShow); older
-- clients still use the field-based setup. Both are handled.
local function OpenColorPicker(r, g, b, onChange)
    local function Current()
        return ColorPickerFrame:GetColorRGB()
    end
    local function Cancel(previous)
        if previous then
            onChange(previous.r or previous[1], previous.g or previous[2], previous.b or previous[3])
        end
    end

    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b,
            hasOpacity = false,
            swatchFunc = function() onChange(Current()) end,
            cancelFunc = Cancel,
        })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.previousValues = { r = r, g = g, b = b }
        ColorPickerFrame.func = function() onChange(Current()) end
        ColorPickerFrame.cancelFunc = Cancel
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()  -- re-show so it picks up the new setup
        ColorPickerFrame:Show()
    end
end

function ColorPicker:Create(parent, config)
    -- config = { key, label, tooltip, default = {r, g, b} }
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(DEFAULT_HEIGHT)

    local swatch = CreateFrame("Button", nil, container, "BackdropTemplate")
    swatch:SetSize(SWATCH_SIZE, SWATCH_SIZE)
    swatch:SetPoint("LEFT", container, "LEFT", 4, 0)
    swatch:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    swatch:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    label:SetText(config.label)

    local reset = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    reset:SetSize(60, 20)
    reset:SetPoint("LEFT", label, "RIGHT", 10, 0)
    reset:SetText(ns.L["RESET"])

    local function GetColor()
        local c = Database:GetSetting(config.key)
        if type(c) == "table" and c[1] then return c[1], c[2], c[3] end
        local d = config.default
        return d[1], d[2], d[3]
    end

    local function Paint()
        local r, g, b = GetColor()
        swatch:SetBackdropColor(r, g, b, 1)
        reset:SetEnabled(Database:GetSetting(config.key) ~= nil)
    end

    local function Store(value)
        Database:SetSetting(config.key, value)
        Paint()
        Events:Fire("SETTING_CHANGED", config.key, value)
    end

    swatch:SetScript("OnClick", function()
        local r, g, b = GetColor()
        OpenColorPicker(r, g, b, function(nr, ng, nb)
            Store({ nr, ng, nb })
        end)
    end)

    reset:SetScript("OnClick", function()
        Store(nil)
    end)

    if config.tooltip then
        swatch:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(config.tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        swatch:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    Paint()

    container.GetSettingKey = function() return config.key end
    container.Refresh = function() Paint() end
    return container
end

return ColorPicker
