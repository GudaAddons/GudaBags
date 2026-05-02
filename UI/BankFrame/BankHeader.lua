local addonName, ns = ...

local BankHeader = {}
ns:RegisterModule("BankFrame.BankHeader", BankHeader)

local Constants = ns.Constants
local L = ns.L
local Database = ns:GetModule("Database")
local HeaderButtonVisibility = ns:GetModule("HeaderButtonVisibility")
local IconButton = ns:GetModule("IconButton")
local ItemButton = ns:GetModule("ItemButton")
local SearchToggleButton = ns:GetModule("SearchToggleButton")
local Theme = ns:GetModule("Theme")

local frame = nil
local onDragStop = nil
local viewingCharacterData = nil

local BankCharacters = nil

-- Debounce for sort/restack button
local lastSortTime = 0
local SORT_DEBOUNCE = 0.5  -- 500ms debounce

local function LoadComponents()
    BankCharacters = ns:GetModule("BankFrame.BankCharacters")
end

local function CreateHeader(parent)
    local titleBar = CreateFrame("Frame", "GudaBankHeader", parent, "BackdropTemplate")
    titleBar:SetHeight(Constants.FRAME.TITLE_HEIGHT)
    titleBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")

    titleBar:SetScript("OnMouseDown", function(self, button)
        -- Raise parent frame above other bag/bank frames when clicked
        parent:SetFrameLevel(Constants.FRAME_LEVELS.RAISED)
        Theme:SyncBlizzardBgLevel(parent)
        if parent.container then
            ItemButton:SyncFrameLevels(parent.container)
        end
        local BagFrameModule = ns:GetModule("BagFrame")
        if BagFrameModule and BagFrameModule:GetFrame() then
            local bagFrame = BagFrameModule:GetFrame()
            bagFrame:SetFrameLevel(Constants.FRAME_LEVELS.BASE)
            Theme:SyncBlizzardBgLevel(bagFrame)
            -- Also lower BagFrame's secure container (it's parented to UIParent, not BagFrame)
            if bagFrame.container then
                bagFrame.container:SetFrameLevel(Constants.FRAME_LEVELS.BASE + Constants.FRAME_LEVELS.CONTAINER)
                ItemButton:SyncFrameLevels(bagFrame.container)
            end
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
    local headerBackdrop = Theme:GetValue("headerBackdrop")
    if headerBackdrop then
        titleBar:SetBackdrop(headerBackdrop)
        local headerBg = Theme:GetValue("headerBg")
        titleBar:SetBackdropColor(headerBg[1], headerBg[2], headerBg[3], bgAlpha)
    else
        titleBar:SetBackdrop(nil)
    end

    local lastLeftButton = nil

    if Constants.FEATURES.CHARACTERS then
        local charactersButton = IconButton:Create(titleBar, "characters", {
            tooltip = L["TOOLTIP_CHARACTERS_BANK"],
            onClick = function(self)
                BankCharacters:Toggle(self)
            end,
        })
        charactersButton:SetPoint("LEFT", titleBar, "LEFT", 6, 0)
        titleBar.charactersButton = charactersButton
        HeaderButtonVisibility:SetKey(charactersButton, "showHeaderCharacters")
        HeaderButtonVisibility:ApplyState(charactersButton)
        lastLeftButton = charactersButton
    end

    local playerName = UnitName("player")
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    title:SetText(playerName .. L["TITLE_BANK"])
    title:SetTextColor(1, 0.82, 0)
    title:SetShadowOffset(1, -1)
    title:SetShadowColor(0, 0, 0, 1)
    titleBar.title = title

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

    if Constants.FEATURES.SORT then
        local sortButton = IconButton:Create(titleBar, "sort", {
            onClick = function()
                -- Debounce protection
                local now = GetTime()
                if now - lastSortTime < SORT_DEBOUNCE then
                    return
                end
                lastSortTime = now

                local BankFrameModule = ns:GetModule("BankFrame")
                local viewType = Database:GetSetting("bankViewType") or "single"

                if viewType == "category" then
                    BankFrameModule:RestackAndClean()
                else
                    BankFrameModule:SortBank()
                end
            end,
        })
        -- Dynamic tooltip based on view type
        sortButton:SetScript("OnEnter", function(self)
            local viewType = Database:GetSetting("bankViewType") or "single"
            local tooltip = viewType == "category" and L["TOOLTIP_RESTACK_CLEAN"] or L["TOOLTIP_SORT_BANK"]
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
        end)
        sortButton:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        sortButton:SetPoint("RIGHT", lastRightButton, "LEFT", -4, 0)
        titleBar.sortButton = sortButton
        HeaderButtonVisibility:SetKey(sortButton, "showHeaderSort")
        HeaderButtonVisibility:ApplyState(sortButton)
        lastRightButton = sortButton
    end

    -- Layout cycle: rotates bankViewType through single → category → split.
    local VIEW_ORDER = { "single", "category", "split" }
    local function nextViewType(current)
        for i, v in ipairs(VIEW_ORDER) do
            if v == current then return VIEW_ORDER[(i % #VIEW_ORDER) + 1] end
        end
        return VIEW_ORDER[1]
    end
    local viewCycleButton = IconButton:Create(titleBar, "viewCycle", {
        tooltip = L["TOOLTIP_VIEW_CYCLE"],
        onClick = function()
            local current = Database:GetSetting("bankViewType") or "single"
            local nextType = nextViewType(current)
            Database:SetSetting("bankViewType", nextType)
            local Events = ns:GetModule("Events")
            Events:Fire("SETTING_CHANGED", "bankViewType", nextType)
        end,
    })
    -- Button frame is sized by theme (StyleButton in Theme.lua); shrink only the
    -- visible glyph by re-anchoring the normal texture to a smaller centered region.
    do
        local tex = viewCycleButton:GetNormalTexture()
        if tex then
            tex:ClearAllPoints()
            tex:SetPoint("CENTER")
            tex:SetSize(13, 13)
        end
    end
    viewCycleButton:SetPoint("RIGHT", lastRightButton, "LEFT", -4, 0)
    titleBar.viewCycleButton = viewCycleButton
    HeaderButtonVisibility:SetKey(viewCycleButton, "showHeaderViewCycle")
    HeaderButtonVisibility:ApplyState(viewCycleButton)
    lastRightButton = viewCycleButton

    -- Recent toggle: enables/disables the built-in Recent category.
    local function applyRecentVisualState(btn)
        if not btn then return end
        local CategoryManager = ns:GetModule("CategoryManager")
        if not CategoryManager then return end
        local def = CategoryManager:GetCategory("Recent")
        local enabled = def and def.enabled
        local tex = btn:GetNormalTexture()
        if tex then
            tex:SetDesaturated(not enabled)
            tex:SetAlpha(enabled and 1.0 or 0.5)
        end
    end
    local recentToggleButton = IconButton:Create(titleBar, "recent", {
        tooltip = L["TOOLTIP_RECENT_TOGGLE"],
        onClick = function()
            local CategoryManager = ns:GetModule("CategoryManager")
            if CategoryManager then
                CategoryManager:ToggleCategory("Recent")
            end
        end,
    })
    recentToggleButton:SetPoint("RIGHT", lastRightButton, "LEFT", -4, 0)
    titleBar.recentToggleButton = recentToggleButton
    HeaderButtonVisibility:SetKey(recentToggleButton, "showHeaderRecentToggle")
    HeaderButtonVisibility:ApplyState(recentToggleButton)
    applyRecentVisualState(recentToggleButton)
    local Events = ns:GetModule("Events")
    Events:Register("CATEGORIES_UPDATED", function()
        applyRecentVisualState(recentToggleButton)
    end, "BankHeader.RecentToggle")
    lastRightButton = recentToggleButton

    -- Search toggle button (shown when "Always Show Search Bar" is off)
    local searchButton = SearchToggleButton:Create(titleBar, {
        targetModule = "BankFrame",
        anchorButton = lastRightButton,
    })
    titleBar.searchButton = searchButton
    lastRightButton = searchButton

    return titleBar
end

function BankHeader:Init(parent)
    LoadComponents()
    frame = CreateHeader(parent)
    return frame
end

function BankHeader:GetFrame()
    return frame
end

function BankHeader:SetDragCallback(callback)
    onDragStop = callback
end

local lastAlpha = 1

function BankHeader:SetBackdropAlpha(alpha)
    if not frame then return end
    lastAlpha = alpha
    local headerBackdrop = Theme:GetValue("headerBackdrop")
    if headerBackdrop then
        frame:SetBackdrop(headerBackdrop)
        local headerBg = Theme:GetValue("headerBg")
        frame:SetBackdropColor(headerBg[1], headerBg[2], headerBg[3], alpha)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", frame:GetParent(), "TOPLEFT", 4, -4)
        frame:SetPoint("TOPRIGHT", frame:GetParent(), "TOPRIGHT", -4, -4)
        if frame.closeButton then frame.closeButton:SetSize(22, 22) end
    else
        frame:SetBackdrop(nil)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", frame:GetParent(), "TOPLEFT", 0, 1)
        frame:SetPoint("TOPRIGHT", frame:GetParent(), "TOPRIGHT", 4, 0)
        local closeSize = ns.IsRetail and 22 or 32
        if frame.closeButton then frame.closeButton:SetSize(closeSize, closeSize) end
        -- Raise header above blizzardBg's NineSlice or metalFrame overlay
        local parent = frame:GetParent()
        if parent.blizzardBg or parent.metalFrame then
            frame:SetFrameLevel(parent:GetFrameLevel() + Constants.FRAME_LEVELS.HEADER)
        end
    end
    HeaderButtonVisibility:ApplyState(frame.charactersButton)
    HeaderButtonVisibility:ApplyState(frame.sortButton)
    HeaderButtonVisibility:ApplyState(frame.viewCycleButton)
    HeaderButtonVisibility:ApplyState(frame.recentToggleButton)
    -- Recent toggle is only meaningful in category view; force-hide elsewhere.
    if frame.recentToggleButton and (Database:GetSetting("bankViewType") or "single") ~= "category" then
        frame.recentToggleButton:Hide()
    end

    local leftButtons = HeaderButtonVisibility:Filter({ frame.charactersButton })
    local rightButtons = HeaderButtonVisibility:Filter({
        frame.settingsButton, frame.sortButton, frame.viewCycleButton, frame.recentToggleButton, frame.searchButton
    })

    Theme:ApplyHeaderButtons(
        frame,
        leftButtons,
        rightButtons,
        frame.closeButton
    )
end

-- Re-apply layout when any header button setting flips.
HeaderButtonVisibility:Watch(BankHeader, function()
    if frame then BankHeader:SetBackdropAlpha(lastAlpha) end
end)

-- Recent toggle is gated by bankViewType too — re-lay out when the view cycles.
local BankHeaderEvents = ns:GetModule("Events")
BankHeaderEvents:Register("SETTING_CHANGED", function(event, key)
    if key == "bankViewType" then
        C_Timer.After(0, function()
            if frame then BankHeader:SetBackdropAlpha(lastAlpha) end
        end)
    end
end, "BankHeader.ViewTypeWatch")

function BankHeader:SetViewingCharacter(fullName, charData)
    viewingCharacterData = charData
    if not frame or not frame.title then return end

    if charData then
        local classColor = RAID_CLASS_COLORS[charData.class]
        local r, g, b = 0.7, 0.7, 0.7
        if classColor then
            r, g, b = classColor.r, classColor.g, classColor.b
        end
        frame.title:SetText(charData.name .. L["TITLE_BANK"])
        frame.title:SetTextColor(r, g, b)
    else
        local playerName = UnitName("player")
        frame.title:SetText(playerName .. L["TITLE_BANK"])
        frame.title:SetTextColor(1, 0.82, 0)
    end
end

function BankHeader:GetCharactersButton()
    if frame then
        return frame.charactersButton
    end
    return nil
end

function BankHeader:IsViewingOther()
    return viewingCharacterData ~= nil
end

function BankHeader:SetCharacterCallback(callback)
    if BankCharacters then
        BankCharacters:SetCallback(callback)
    end
end

function BankHeader:SetSortEnabled(enabled)
    if frame and frame.sortButton then
        if enabled then
            frame.sortButton:Enable()
            frame.sortButton:SetAlpha(1)
        else
            frame.sortButton:Disable()
            frame.sortButton:SetAlpha(0.4)
        end
    end
end
