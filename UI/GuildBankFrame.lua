local addonName, ns = ...

-- Guild Bank is available in TBC and later (check feature flag)
if not ns.Constants or not ns.Constants.FEATURES or not ns.Constants.FEATURES.GUILD_BANK then
    return
end

local GuildBankFrame = {}
ns:RegisterModule("GuildBankFrame", GuildBankFrame)

local Constants = ns.Constants
local L = ns.L
local Database = ns:GetModule("Database")
local Events = ns:GetModule("Events")
local ItemButton = ns:GetModule("ItemButton")
local SearchBar = ns:GetModule("SearchBar")
local LayoutEngine = ns:GetModule("BagFrame.LayoutEngine")
local Utils = ns:GetModule("Utils")
local CategoryHeaderPool = ns:GetModule("CategoryHeaderPool")

local GuildBankHeader = nil
local GuildBankFooter = nil
local GuildBankScanner = nil

local frame
local searchBar
local itemButtons = {}
local categoryHeaders = {}

-- Layout caching
local buttonsBySlot = {}
local cachedItemData = {}
local cachedItemCount = {}
local layoutCached = false

-- Hidden frame to reparent Blizzard guild bank UI (used by some versions)
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

local function LoadComponents()
    GuildBankHeader = ns:GetModule("GuildBankFrame.GuildBankHeader")
    GuildBankFooter = ns:GetModule("GuildBankFrame.GuildBankFooter")
    GuildBankScanner = ns:GetModule("GuildBankScanner")
end

-------------------------------------------------
-- Category Header Pool
-------------------------------------------------

local function AcquireCategoryHeader(parent)
    return CategoryHeaderPool:Acquire(parent)
end

local function ReleaseAllCategoryHeaders()
    if frame and frame.container then
        CategoryHeaderPool:ReleaseAll(frame.container)
    end
    categoryHeaders = {}
end

-------------------------------------------------
-- Frame Position
-------------------------------------------------

local function SaveFramePosition()
    if not frame then return end

    local point, _, relativePoint, x, y = frame:GetPoint()
    Database:SetSetting("guildBankFramePoint", point)
    Database:SetSetting("guildBankFrameRelativePoint", relativePoint)
    Database:SetSetting("guildBankFrameX", x)
    Database:SetSetting("guildBankFrameY", y)
end

local function RestoreFramePosition()
    if not frame then return end

    local point = Database:GetSetting("guildBankFramePoint")
    local relativePoint = Database:GetSetting("guildBankFrameRelativePoint")
    local x = Database:GetSetting("guildBankFrameX")
    local y = Database:GetSetting("guildBankFrameY")

    if point and relativePoint and x and y then
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, relativePoint, x, y)
    end
end

-------------------------------------------------
-- Frame Appearance
-------------------------------------------------

local function UpdateFrameAppearance()
    if not frame then return end

    local bgAlpha = Database:GetSetting("bgAlpha") / 100
    frame:SetBackdropColor(0.08, 0.08, 0.08, bgAlpha)

    local showSearchBar = Database:GetSetting("showSearchBar")
    local showFooter = Database:GetSetting("showFooter")

    -- Update search bar visibility
    if searchBar then
        if showSearchBar then
            searchBar:Show()
            searchBar:SetPoint("TOPLEFT", frame, "TOPLEFT", Constants.FRAME.PADDING, -(Constants.FRAME.TITLE_HEIGHT + Constants.FRAME.PADDING))
            searchBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Constants.FRAME.PADDING, -(Constants.FRAME.TITLE_HEIGHT + Constants.FRAME.PADDING))
        else
            searchBar:Hide()
        end
    end

    -- Update scroll frame positioning
    local topOffset = showSearchBar
        and (Constants.FRAME.TITLE_HEIGHT + Constants.FRAME.SEARCH_BAR_HEIGHT + Constants.FRAME.PADDING + 6)
        or (Constants.FRAME.TITLE_HEIGHT + Constants.FRAME.PADDING + 2)
    local bottomOffset = showFooter
        and (Constants.FRAME.FOOTER_HEIGHT + Constants.FRAME.PADDING + 6)
        or Constants.FRAME.PADDING

    frame.scrollFrame:ClearAllPoints()
    frame.scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", Constants.FRAME.PADDING, -topOffset)
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Constants.FRAME.PADDING - 20, bottomOffset)

    -- Update footer visibility
    if showFooter then
        GuildBankFooter:Show()
    else
        GuildBankFooter:Hide()
    end

    -- Update header alpha
    GuildBankHeader:SetBackdropAlpha(bgAlpha)
end

-------------------------------------------------
-- Side Tab Bar (Vertical tabs on RIGHT side)
-------------------------------------------------

local TAB_SIZE = 36
local TAB_SPACING = 2

local function CreateSideTab(parent, index, isAllTab)
    local button = CreateFrame("Button", "GudaGuildBankSideTab" .. (isAllTab and "All" or index), parent, "BackdropTemplate")
    button:SetSize(TAB_SIZE, TAB_SIZE)
    button.tabIndex = isAllTab and 0 or index

    button:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    button:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    button:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(TAB_SIZE - 6, TAB_SIZE - 6)
    icon:SetPoint("CENTER")
    -- Use chest icon for "All" tab, default bag icon for specific tabs
    if isAllTab then
        icon:SetTexture("Interface\\AddOns\\GudaBags\\Assets\\chest.png")
    else
        icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    end
    button.icon = icon

    -- Tab number text (for non-All tabs)
    if not isAllTab then
        local numText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        numText:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
        numText:SetText(tostring(index))
        numText:SetTextColor(0.8, 0.8, 0.8)
        button.numText = numText
    end

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    -- Selection indicator
    local selected = button:CreateTexture(nil, "OVERLAY")
    selected:SetAllPoints()
    selected:SetColorTexture(0, 0.8, 0.4, 0.3)  -- Green-ish for guild
    selected:Hide()
    button.selected = selected

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if self.tabIndex == 0 then
            GameTooltip:SetText(ns.L["TOOLTIP_GUILD_ALL_TABS"] or "All Tabs")
        elseif self.tabName then
            GameTooltip:SetText(self.tabName)
        else
            GameTooltip:SetText(string.format(ns.L["TOOLTIP_GUILD_TAB"] or "Tab %d", self.tabIndex))
        end
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:SetScript("OnClick", function(self)
        if GuildBankScanner then
            local currentTab = GuildBankScanner:GetSelectedTab()
            if currentTab == self.tabIndex then
                -- Clicking same tab - show all
                if self.tabIndex ~= 0 then
                    GuildBankScanner:SetSelectedTab(0)
                end
            else
                GuildBankScanner:SetSelectedTab(self.tabIndex)
            end
            GuildBankFrame:UpdateSideTabSelection()
            GuildBankFrame:Refresh()
        end
    end)

    return button
end

function GuildBankFrame:ShowSideTabs()
    if not frame or not frame.sideTabBar then return end

    local tabs = {}

    -- Get tabs from scanner
    if GuildBankScanner then
        local cachedTabInfo = GuildBankScanner:GetCachedTabInfo()
        if cachedTabInfo then
            for i, tabInfo in pairs(cachedTabInfo) do
                table.insert(tabs, {
                    index = tabInfo.index or i,
                    name = tabInfo.name,
                    icon = tabInfo.icon or "Interface\\Icons\\INV_Misc_Bag_10",
                })
            end
        end
    end

    -- If no tabs, try getting count
    if #tabs == 0 then
        local numTabs = GuildBankScanner and GuildBankScanner:GetNumTabs() or 0
        for i = 1, numTabs do
            table.insert(tabs, {
                index = i,
                name = string.format(ns.L["TOOLTIP_GUILD_TAB"] or "Tab %d", i),
                icon = "Interface\\Icons\\INV_Misc_Bag_10",
            })
        end
    end

    -- Sort tabs by index
    table.sort(tabs, function(a, b) return a.index < b.index end)

    -- Hide if no tabs
    if #tabs == 0 then
        frame.sideTabBar:Hide()
        return
    end

    -- Create "All" tab button first
    if not frame.sideTabs[0] then
        frame.sideTabs[0] = CreateSideTab(frame.sideTabBar, 0, true)
    end
    frame.sideTabs[0]:ClearAllPoints()
    frame.sideTabs[0]:SetPoint("TOP", frame.sideTabBar, "TOP", 0, 0)
    frame.sideTabs[0]:Show()

    local prevButton = frame.sideTabs[0]

    -- Create/update tab buttons
    for i, tabData in ipairs(tabs) do
        if not frame.sideTabs[i] then
            frame.sideTabs[i] = CreateSideTab(frame.sideTabBar, i, false)
        end

        local button = frame.sideTabs[i]
        button.tabIndex = tabData.index
        button.tabName = tabData.name
        if tabData.icon then
            button.icon:SetTexture(tabData.icon)
        end

        button:ClearAllPoints()
        button:SetPoint("TOP", prevButton, "BOTTOM", 0, -TAB_SPACING)
        button:Show()

        prevButton = button
    end

    -- Hide excess tabs
    for i = #tabs + 1, #frame.sideTabs do
        if frame.sideTabs[i] then
            frame.sideTabs[i]:Hide()
        end
    end

    -- Resize tab bar
    local totalHeight = (TAB_SIZE + TAB_SPACING) * (#tabs + 1)
    frame.sideTabBar:SetSize(TAB_SIZE, totalHeight)

    frame.sideTabBar:Show()
    self:UpdateSideTabSelection()
end

function GuildBankFrame:HideSideTabs()
    if frame and frame.sideTabBar then
        frame.sideTabBar:Hide()
    end
end

function GuildBankFrame:UpdateSideTabSelection()
    if not frame or not frame.sideTabs then return end

    local selectedTab = GuildBankScanner and GuildBankScanner:GetSelectedTab() or 0

    for i, button in pairs(frame.sideTabs) do
        if button and button:IsShown() then
            if i == selectedTab then
                button.selected:Show()
                button:SetBackdropBorderColor(0, 0.8, 0.4, 1)  -- Green
            else
                button.selected:Hide()
                button:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
            end
        end
    end
end

-------------------------------------------------
-- Frame Creation
-------------------------------------------------

local function CreateGuildBankFrame()
    local f = CreateFrame("Frame", "GudaGuildBankFrame", UIParent, "BackdropTemplate")
    f:SetSize(400, 300)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(50)
    f:EnableMouse(true)

    -- Raise frame above others when clicked
    f:SetScript("OnMouseDown", function(self)
        self:SetFrameLevel(60)
        local BagFrameModule = ns:GetModule("BagFrame")
        if BagFrameModule and BagFrameModule:GetFrame() then
            BagFrameModule:GetFrame():SetFrameLevel(50)
        end
        local BankFrameModule = ns:GetModule("BankFrame")
        if BankFrameModule and BankFrameModule:GetFrame() then
            BankFrameModule:GetFrame():SetFrameLevel(50)
        end
    end)

    f:SetBackdrop(Constants.BACKDROP)
    local bgAlpha = Database:GetSetting("bgAlpha") / 100
    f:SetBackdropColor(0.08, 0.08, 0.08, bgAlpha)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:Hide()

    -- Register for Escape key to close
    tinsert(UISpecialFrames, "GudaGuildBankFrame")

    -- Close guild bank interaction when frame is hidden by user (Escape, close button, etc.)
    f:SetScript("OnHide", function()
        ns:Debug("GudaGuildBankFrame OnHide triggered")

        local scanner = ns:GetModule("GuildBankScanner")
        local wasOpen = scanner and scanner:IsGuildBankOpen() or false
        ns:Debug("  wasOpen:", wasOpen)

        -- Only close the interaction if it's still open (user closed our frame)
        -- Don't close if the game already closed it (walked away, etc.)
        if wasOpen then
            C_Timer.After(0.05, function()
                -- Check again in case state changed
                if scanner and scanner:IsGuildBankOpen() then
                    ns:Debug("  Closing guild bank interaction")
                    if C_PlayerInteractionManager and C_PlayerInteractionManager.ClearInteraction and Enum and Enum.PlayerInteractionType then
                        C_PlayerInteractionManager.ClearInteraction(Enum.PlayerInteractionType.GuildBanker)
                    elseif CloseGuildBankFrame then
                        CloseGuildBankFrame()
                    end
                end
            end)
        end
    end)

    -- Header
    f.titleBar = GuildBankHeader:Init(f)
    GuildBankHeader:SetDragCallback(SaveFramePosition)

    -- Search bar
    searchBar = SearchBar:Init(f)
    SearchBar:SetSearchCallback(f, function(text)
        GuildBankFrame:Refresh()
    end)
    f.searchBar = searchBar

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "GudaGuildBankScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", Constants.FRAME.PADDING, -(Constants.FRAME.TITLE_HEIGHT + Constants.FRAME.SEARCH_BAR_HEIGHT + Constants.FRAME.PADDING + 6))
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -Constants.FRAME.PADDING - 20, Constants.FRAME.FOOTER_HEIGHT + Constants.FRAME.PADDING + 6)
    f.scrollFrame = scrollFrame

    -- Style the scroll bar
    local scrollBar = scrollFrame.ScrollBar or _G[scrollFrame:GetName() .. "ScrollBar"]
    if scrollBar then
        scrollBar:SetAlpha(0.7)
    end

    -- Container as scroll child
    local container = CreateFrame("Frame", "GudaGuildBankContainer", scrollFrame)
    container:SetSize(1, 1)
    scrollFrame:SetScrollChild(container)
    f.container = container

    -- Empty message
    local emptyMessage = CreateFrame("Frame", nil, f)
    emptyMessage:SetAllPoints(scrollFrame)
    emptyMessage:Hide()

    local emptyText = emptyMessage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyText:SetPoint("CENTER", emptyMessage, "CENTER", 0, 10)
    emptyText:SetTextColor(0.6, 0.6, 0.6)
    emptyText:SetText(ns.L["GUILD_BANK_NO_DATA"] or "No guild bank data")
    emptyMessage.text = emptyText

    local emptyHint = emptyMessage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emptyHint:SetPoint("TOP", emptyText, "BOTTOM", 0, -8)
    emptyHint:SetTextColor(0.5, 0.5, 0.5)
    emptyHint:SetText(ns.L["GUILD_BANK_VISIT"] or "Visit your guild vault to cache items")
    emptyMessage.hint = emptyHint

    f.emptyMessage = emptyMessage

    -- Footer
    f.footer = GuildBankFooter:Init(f)

    -- Side tab bar (vertical, on right side outside frame)
    local sideTabBar = CreateFrame("Frame", "GudaGuildBankSideTabBar", f)
    sideTabBar:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -55)
    sideTabBar:SetSize(32, 200)
    sideTabBar:Hide()
    f.sideTabBar = sideTabBar
    f.sideTabs = {}

    return f
end

-------------------------------------------------
-- Refresh / Display
-------------------------------------------------

local function HasGuildBankData(guildBank)
    if not guildBank then return false end
    for tabIndex, tabData in pairs(guildBank) do
        if tabData.numSlots and tabData.numSlots > 0 then
            return true
        end
    end
    return false
end

function GuildBankFrame:CountTabs(guildBank)
    if not guildBank then return 0 end
    local count = 0
    for _ in pairs(guildBank) do
        count = count + 1
    end
    return count
end

function GuildBankFrame:Refresh()
    if not frame then return end

    ns:Debug("GuildBankFrame:Refresh called")

    ItemButton:ReleaseAll(frame.container)
    ReleaseAllCategoryHeaders()
    itemButtons = {}

    -- Clear layout cache
    buttonsBySlot = {}
    cachedItemData = {}
    cachedItemCount = {}
    layoutCached = false

    local isGuildBankOpen = GuildBankScanner and GuildBankScanner:IsGuildBankOpen() or false
    ns:Debug("  isGuildBankOpen =", isGuildBankOpen)

    -- Always use cached guild bank data (LoadFromDatabase populates this for offline mode)
    local guildBank = GuildBankScanner and GuildBankScanner:GetCachedGuildBank()
    ns:Debug("  Got cached guild bank, tabs =", guildBank and self:CountTabs(guildBank) or 0)

    local hasData = HasGuildBankData(guildBank)
    ns:Debug("  hasData =", hasData)

    if not hasData then
        ns:Debug("  No data, showing empty message")
        frame.container:Hide()
        frame.emptyMessage:Show()
        self:HideSideTabs()

        local columns = Database:GetSetting("guildBankColumns")
        local iconSize = Database:GetSetting("iconSize")
        local spacing = Database:GetSetting("iconSpacing")
        local minWidth = (iconSize * columns) + (Constants.FRAME.PADDING * 2)
        local minHeight = (6 * iconSize) + (5 * spacing) + 80

        frame:SetSize(math.max(minWidth, 250), minHeight)
        GuildBankFooter:UpdateSlotInfo(0, 0)
        return
    end

    frame.emptyMessage:Hide()
    frame.container:Show()

    -- Show side tabs
    self:ShowSideTabs()

    local iconSize = Database:GetSetting("iconSize")
    local spacing = Database:GetSetting("iconSpacing")
    local columns = Database:GetSetting("guildBankColumns")
    local searchText = SearchBar:GetSearchText(frame)
    local selectedTab = GuildBankScanner and GuildBankScanner:GetSelectedTab() or 0

    -- Collect all slots from guild bank
    local allSlots = {}
    local showTabSections = selectedTab == 0 and GuildBankScanner and GuildBankScanner:GetNumTabs() > 1

    -- Sort tabs by index
    local sortedTabs = {}
    for tabIndex, tabData in pairs(guildBank) do
        table.insert(sortedTabs, {index = tabIndex, data = tabData})
    end
    table.sort(sortedTabs, function(a, b) return a.index < b.index end)

    for _, tabEntry in ipairs(sortedTabs) do
        local tabIndex = tabEntry.index
        local tabData = tabEntry.data

        -- Skip if filtering by specific tab
        if selectedTab > 0 and tabIndex ~= selectedTab then
            -- Skip this tab
        elseif tabData and tabData.slots then
            -- Add tab header if showing all tabs
            if showTabSections then
                table.insert(allSlots, {
                    isHeader = true,
                    tabIndex = tabIndex,
                    tabName = tabData.name or string.format("Tab %d", tabIndex),
                    tabIcon = tabData.icon,
                })
            end

            -- Add slots from this tab
            for slot = 1, (tabData.numSlots or Constants.GUILD_BANK_SLOTS_PER_TAB) do
                local itemData = tabData.slots[slot]
                table.insert(allSlots, {
                    tabIndex = tabIndex,
                    slot = slot,
                    itemData = itemData,
                })
            end
        end
    end

    -- Calculate content dimensions
    local numSlots = 0
    local headerCount = 0
    for _, slotInfo in ipairs(allSlots) do
        if slotInfo.isHeader then
            headerCount = headerCount + 1
        else
            numSlots = numSlots + 1
        end
    end

    local itemRows = math.ceil(numSlots / columns)
    local contentWidth = (iconSize * columns) + (spacing * (columns - 1))
    local headerHeight = 20
    -- Calculate height: item rows + spacing between rows + headers (not double-counted)
    local actualContentHeight = (iconSize * itemRows) + (spacing * math.max(0, itemRows - 1)) + (headerCount * headerHeight)

    -- Calculate frame dimensions
    local showSearchBar = Database:GetSetting("showSearchBar")
    local showFooter = Database:GetSetting("showFooter")
    local topOffset = showSearchBar
        and (Constants.FRAME.TITLE_HEIGHT + Constants.FRAME.SEARCH_BAR_HEIGHT + Constants.FRAME.PADDING + 6)
        or (Constants.FRAME.TITLE_HEIGHT + Constants.FRAME.PADDING + 2)
    local bottomOffset = showFooter
        and (Constants.FRAME.FOOTER_HEIGHT + Constants.FRAME.PADDING + 6)
        or Constants.FRAME.PADDING
    local chromeHeight = topOffset + bottomOffset

    local frameWidth = math.max(contentWidth + (Constants.FRAME.PADDING * 2), Constants.FRAME.MIN_WIDTH)
    local frameHeightNeeded = actualContentHeight + chromeHeight

    local minFrameHeight = (6 * iconSize) + (5 * spacing) + chromeHeight
    local adjustedFrameHeight = math.max(frameHeightNeeded, minFrameHeight)

    local screenHeight = UIParent:GetHeight()
    local maxFrameHeight = screenHeight - 100
    local actualFrameHeight = math.min(adjustedFrameHeight, maxFrameHeight)

    local scrollAreaHeight = actualFrameHeight - chromeHeight
    local needsScroll = actualContentHeight > scrollAreaHeight + 5

    local scrollbarWidth = needsScroll and 20 or 0
    frame:SetSize(frameWidth + scrollbarWidth, actualFrameHeight)

    frame.scrollFrame:ClearAllPoints()
    frame.scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", Constants.FRAME.PADDING, -topOffset)
    frame.scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -Constants.FRAME.PADDING - scrollbarWidth, bottomOffset)

    frame.container:SetSize(contentWidth, math.max(actualContentHeight, 1))

    local scrollBar = frame.scrollFrame.ScrollBar or _G[frame.scrollFrame:GetName() .. "ScrollBar"]
    if needsScroll then
        if scrollBar then scrollBar:Show() end
        frame.scrollFrame:EnableMouseWheel(true)
    else
        if scrollBar then scrollBar:Hide() end
        frame.scrollFrame:SetVerticalScroll(0)
        frame.scrollFrame:EnableMouseWheel(false)
    end

    -- Render items
    local currentY = 0
    local currentCol = 0
    local isReadOnly = not isGuildBankOpen

    for _, slotInfo in ipairs(allSlots) do
        if slotInfo.isHeader then
            -- Start new row if needed
            if currentCol > 0 then
                currentY = currentY - iconSize - spacing
                currentCol = 0
            end

            -- Create header
            local header = AcquireCategoryHeader(frame.container)
            header.text:SetText(slotInfo.tabName or "Tab")
            if slotInfo.tabIcon then
                header.icon:SetTexture(slotInfo.tabIcon)
                header.icon:Show()
            else
                header.icon:Hide()
            end
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", frame.container, "TOPLEFT", 0, currentY)
            header:SetWidth(contentWidth)
            header:Show()
            table.insert(categoryHeaders, header)

            currentY = currentY - headerHeight
        else
            -- Regular slot
            local x = currentCol * (iconSize + spacing)
            local y = currentY

            local button = ItemButton:Acquire(frame.container)
            local slotKey = slotInfo.tabIndex .. ":" .. slotInfo.slot

            if slotInfo.itemData then
                -- Adapt item data for ItemButton (needs bagID and slot)
                local adaptedData = {}
                for k, v in pairs(slotInfo.itemData) do
                    adaptedData[k] = v
                end
                adaptedData.bagID = slotInfo.tabIndex
                adaptedData.slot = slotInfo.slot
                adaptedData.isGuildBank = true

                ItemButton:SetItem(button, adaptedData, iconSize, isReadOnly)

                if searchText ~= "" and not SearchBar:ItemMatchesSearch(slotInfo.itemData, searchText) then
                    button:SetAlpha(0.3)
                else
                    button:SetAlpha(1)
                end

                cachedItemData[slotKey] = slotInfo.itemData.itemID
                cachedItemCount[slotKey] = slotInfo.itemData.count
            else
                -- Empty slot - pass isGuildBank flag for depositing
                ItemButton:SetEmpty(button, slotInfo.tabIndex, slotInfo.slot, iconSize, isReadOnly, true)
                if searchText ~= "" then
                    button:SetAlpha(0.3)
                else
                    button:SetAlpha(1)
                end
                cachedItemData[slotKey] = nil
                cachedItemCount[slotKey] = nil
            end

            button.wrapper:ClearAllPoints()
            button.wrapper:SetPoint("TOPLEFT", frame.container, "TOPLEFT", x, y)

            buttonsBySlot[slotKey] = button
            table.insert(itemButtons, button)

            -- Advance position
            currentCol = currentCol + 1
            if currentCol >= columns then
                currentCol = 0
                currentY = currentY - iconSize - spacing
            end
        end
    end

    layoutCached = true

    -- Update footer
    local totalSlots = 0
    local freeSlots = 0
    for _, tabData in pairs(guildBank) do
        totalSlots = totalSlots + (tabData.numSlots or 0)
        freeSlots = freeSlots + (tabData.freeSlots or 0)
    end
    GuildBankFooter:UpdateSlotInfo(totalSlots - freeSlots, totalSlots)
    GuildBankFooter:Update()
end

-------------------------------------------------
-- Public API
-------------------------------------------------

function GuildBankFrame:Toggle()
    LoadComponents()

    if not frame then
        frame = CreateGuildBankFrame()
        RestoreFramePosition()
    end

    if frame:IsShown() then
        frame:Hide()
    else
        if GuildBankScanner and GuildBankScanner:IsGuildBankOpen() then
            GuildBankScanner:ScanAllTabs()
        else
            -- Load from database for offline viewing
            local guildName = GuildBankScanner and GuildBankScanner:GetCurrentGuildName()
            if guildName then
                GuildBankScanner:LoadFromDatabase(guildName)
            end
        end
        self:Refresh()
        UpdateFrameAppearance()
        GuildBankHeader:UpdateTitle()
        frame:Show()
    end
end

function GuildBankFrame:Show()
    LoadComponents()

    if not frame then
        frame = CreateGuildBankFrame()
        RestoreFramePosition()
    end

    if GuildBankScanner and GuildBankScanner:IsGuildBankOpen() then
        GuildBankScanner:ScanAllTabs()
    else
        -- Load from database for offline viewing
        local guildName = GuildBankScanner and GuildBankScanner:GetCurrentGuildName()
        if guildName then
            GuildBankScanner:LoadFromDatabase(guildName)
        end
    end
    self:Refresh()
    UpdateFrameAppearance()
    GuildBankHeader:UpdateTitle()
    frame:Show()
end

function GuildBankFrame:Hide()
    if frame then
        frame:Hide()
        ItemButton:ReleaseAll(frame.container)
        ReleaseAllCategoryHeaders()
        buttonsBySlot = {}
        cachedItemData = {}
        cachedItemCount = {}
        itemButtons = {}
        layoutCached = false
    end
end

function GuildBankFrame:IsShown()
    return frame and frame:IsShown()
end

function GuildBankFrame:GetFrame()
    return frame
end

-------------------------------------------------
-- Event Callbacks
-------------------------------------------------

-- Called when guild bank is opened
ns.OnGuildBankOpened = function()
    ns:Debug("OnGuildBankOpened callback triggered")
    LoadComponents()

    -- Show our guild bank frame (Blizzard's frame is hidden by GuildBankScanner)
    GuildBankFrame:Show()

    -- Refresh bags to update stacking (unstack when interaction window opens)
    local BagFrameModule = ns:GetModule("BagFrame")
    if BagFrameModule and BagFrameModule:IsShown() then
        BagFrameModule:Refresh()
    end
end

-- Called when guild bank is closed
ns.OnGuildBankClosed = function()
    ns:Debug("OnGuildBankClosed callback triggered")
    GuildBankFrame:Hide()

    -- Refresh bags to update stacking (re-stack when interaction window closes)
    local BagFrameModule = ns:GetModule("BagFrame")
    if BagFrameModule and BagFrameModule:IsShown() then
        BagFrameModule:Refresh()
    end
end

-- Called when guild bank items change
ns.OnGuildBankUpdated = function(dirtyTabs)
    if frame and frame:IsShown() then
        GuildBankFrame:Refresh()
    end
end

-- Called when tab selection changes
ns.OnGuildBankTabChanged = function(tabIndex)
    if frame and frame:IsShown() then
        GuildBankFrame:Refresh()
    end
end

-- Called when tab info updates
ns.OnGuildBankTabsUpdated = function()
    if frame and frame:IsShown() then
        GuildBankFrame:ShowSideTabs()
    end
end

-------------------------------------------------
-- Settings Change Handler
-------------------------------------------------

-- Settings that only need appearance update
local appearanceSettings = {
    bgAlpha = true,
    showBorders = true,
}

-- Handle setting changes (live update)
local function OnSettingChanged(event, key, value)
    if not frame or not frame:IsShown() then return end

    if appearanceSettings[key] then
        UpdateFrameAppearance()
    elseif key == "guildBankColumns" or key == "iconSize" or key == "iconSpacing" then
        -- Column/size changes need full refresh
        UpdateFrameAppearance()
        GuildBankFrame:Refresh()
    elseif key == "showFooter" or key == "showSearchBar" then
        UpdateFrameAppearance()
        GuildBankFrame:Refresh()
    end
end

Events:Register("SETTING_CHANGED", OnSettingChanged, GuildBankFrame)
