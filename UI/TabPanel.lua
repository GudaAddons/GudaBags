local addonName, ns = ...

local TabPanel = {}
ns:RegisterModule("TabPanel", TabPanel)

local DEFAULT_TAB_HEIGHT = 24

function TabPanel:Create(parent, config)
    -- config = { tabs = {{id, label}, ...}, tabHeight, topMargin, padding, onSelect }
    local container = CreateFrame("Frame", nil, parent)
    local tabs = {}
    local tabContents = {}
    local activeTab = nil

    local tabHeight = config.tabHeight or DEFAULT_TAB_HEIGHT
    local topMargin = config.topMargin or 0
    local padding = config.padding or 12

    -- Tab bar container (full width, no padding)
    local tabBar = CreateFrame("Frame", nil, container)
    tabBar:SetHeight(tabHeight)
    tabBar:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -topMargin)
    tabBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -4, -topMargin)

    -- Separator line (full width)
    local separator = container:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, 0)
    separator:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
    separator:SetTexture("Interface\\Buttons\\WHITE8x8")
    separator:SetVertexColor(0.3, 0.3, 0.3, 1)

    -- Content area
    local contentArea = CreateFrame("Frame", nil, container)
    contentArea:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", padding, -6)
    contentArea:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -padding, padding)

    local function SelectTab(tabId)
        activeTab = tabId

        for id, btn in pairs(tabs) do
            if id == tabId then
                btn:SetBackdropColor(0.3, 0.3, 0.3, 1)
                btn.text:SetTextColor(1, 0.82, 0)
            else
                btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
                btn.text:SetTextColor(0.7, 0.7, 0.7)
            end
        end

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

    local function CreateTabButton(tabInfo, index, totalTabs)
        local tabWidth = (tabBar:GetWidth() > 0 and tabBar:GetWidth() or 380) / totalTabs

        local btn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        btn:SetSize(tabWidth, tabHeight)
        btn:SetPoint("TOPLEFT", tabBar, "TOPLEFT", (index - 1) * tabWidth, 0)

        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 0 },
        })
        btn:SetBackdropColor(0.15, 0.15, 0.15, 1)
        btn:SetBackdropBorderColor(0, 0, 0, 0)

        -- Store functions for color changes
        btn.SetBgColor = function(self, r, g, b, a)
            self:SetBackdropColor(r, g, b, a)
        end

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER", btn, "CENTER", 0, 0)
        text:SetText(tabInfo.label)
        text:SetTextColor(0.7, 0.7, 0.7)
        btn.text = text

        btn:SetScript("OnClick", function()
            SelectTab(tabInfo.id)
        end)

        btn:SetScript("OnEnter", function(self)
            if activeTab ~= tabInfo.id then
                self:SetBackdropColor(0.25, 0.25, 0.25, 1)
            end
        end)

        btn:SetScript("OnLeave", function(self)
            if activeTab ~= tabInfo.id then
                self:SetBackdropColor(0.15, 0.15, 0.15, 1)
            end
        end)

        return btn
    end

    -- Create tab buttons
    for i, tabInfo in ipairs(config.tabs) do
        tabs[tabInfo.id] = CreateTabButton(tabInfo, i, #config.tabs)
    end

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
