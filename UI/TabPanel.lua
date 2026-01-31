local addonName, ns = ...

local TabPanel = {}
ns:RegisterModule("TabPanel", TabPanel)

-- Global counter for unique tab names
local tabCounter = 0

function TabPanel:Create(parent, config)
    -- config = { tabs = {{id, label}, ...}, tabHeight, topMargin, padding, onSelect }
    local container = CreateFrame("Frame", nil, parent)
    local tabs = {}
    local tabButtons = {}
    local tabContents = {}
    local activeTab = nil

    local topMargin = config.topMargin or 0
    local padding = config.padding or 12

    container.Tabs = tabButtons

    -- Content area (positioned below tabs)
    local contentArea = CreateFrame("Frame", nil, container)
    contentArea:SetPoint("TOPLEFT", container, "TOPLEFT", padding, -topMargin - 50)
    contentArea:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -padding, padding)

    local function SelectTab(tabId)
        activeTab = tabId

        -- Find tab index
        local tabIndex = 1
        for i, tabInfo in ipairs(config.tabs) do
            if tabInfo.id == tabId then
                tabIndex = i
                break
            end
        end

        -- Update tab visuals using PanelTemplates
        PanelTemplates_SetTab(container, tabIndex)

        -- Show/hide content
        for id, content in pairs(tabContents) do
            if id == tabId then
                content:Show()
            else
                content:Hide()
            end
        end

        if config.onSelect then
            config.onSelect(tabId)
        end
    end

    local function CreateTabButton(tabInfo, index)
        tabCounter = tabCounter + 1
        local tabName = "GudaBagsSettingsTab" .. tabCounter

        -- Use TabButtonTemplate (works in Classic)
        local tab
        if DoesTemplateExist and DoesTemplateExist("PanelTopTabButtonTemplate") then
            tab = CreateFrame("Button", tabName, container, "PanelTopTabButtonTemplate")
        else
            tab = CreateFrame("Button", tabName, container, "TabButtonTemplate")
        end

        -- Position tabs at the top left
        if index == 1 then
            tab:SetPoint("TOPLEFT", container, "TOPLEFT", 5, -topMargin)
        else
            tab:SetPoint("TOPLEFT", tabButtons[index - 1], "TOPRIGHT", 4, 0)
        end

        tab:SetText(tabInfo.label)
        tab:SetID(index)

        tab:SetScript("OnShow", function(self)
            PanelTemplates_TabResize(self, 10, nil, 10)
            PanelTemplates_DeselectTab(self)
        end)

        tab:SetScript("OnClick", function()
            SelectTab(tabInfo.id)
        end)

        return tab
    end

    -- Create tab buttons
    for i, tabInfo in ipairs(config.tabs) do
        local tab = CreateTabButton(tabInfo, i)
        tabButtons[i] = tab
        tabs[tabInfo.id] = tab
    end

    -- Set up PanelTemplates
    PanelTemplates_SetNumTabs(container, #config.tabs)

    -- Public API
    container.SelectTab = SelectTab
    container.GetActiveTab = function() return activeTab end
    container.GetContentArea = function() return contentArea end

    container.SetContent = function(self, tabId, content)
        content:SetParent(contentArea)
        content:SetAllPoints(contentArea)
        content:Hide()
        tabContents[tabId] = content
    end

    container.GetContent = function(self, tabId)
        return tabContents[tabId]
    end

    container.RefreshAll = function(self)
        for _, content in pairs(tabContents) do
            if content.RefreshAll then
                content:RefreshAll()
            end
        end
    end

    -- Select first tab by default
    if config.tabs[1] then
        SelectTab(config.tabs[1].id)
    end

    return container
end

return TabPanel
