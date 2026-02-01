local addonName, ns = ...

local SlashCommands = {}
ns:RegisterModule("SlashCommands", SlashCommands)

local L = ns.L

-------------------------------------------------
-- Module Getters (lazy loading)
-------------------------------------------------

local function GetBagFrame()
    return ns:GetModule("BagFrame")
end

local function GetBankFrame()
    return ns:GetModule("BankFrame")
end

local function GetSettingsPopup()
    return ns:GetModule("SettingsPopup")
end

local function GetDatabase()
    return ns:GetModule("Database")
end

local function GetBagScanner()
    return ns:GetModule("BagScanner")
end

-------------------------------------------------
-- Command Handlers
-------------------------------------------------

local commandHandlers = {}

-- Default: Toggle bag frame
commandHandlers[""] = function()
    GetBagFrame():Toggle()
end

-- Settings/Config/Options
commandHandlers["settings"] = function()
    GetSettingsPopup():Toggle()
end
commandHandlers["config"] = commandHandlers["settings"]
commandHandlers["options"] = commandHandlers["settings"]

-- Sort bags
commandHandlers["sort"] = function()
    GetBagFrame():SortBags()
end

-- Toggle bank
commandHandlers["bank"] = function()
    GetBankFrame():Toggle()
end

-- Debug mode toggle
commandHandlers["debug"] = function()
    ns.debugMode = not ns.debugMode
    ns:Print(L["CMD_DEBUG_MODE"], ns.debugMode and L["CMD_ON"] or L["CMD_OFF"])
end

-- Debug item button frames (for retail overlay issues)
commandHandlers["debugbutton"] = function()
    local ItemButton = ns:GetModule("ItemButton")
    ns:Print("Checking first item button structure...")

    -- Get first active button
    local firstButton = nil
    for button in ItemButton:GetActiveButtons() do
        firstButton = button
        break
    end

    if not firstButton then
        ns:Print("No active item buttons found. Open your bags first.")
        return
    end

    ns:Print("Button: " .. (firstButton:GetName() or "unnamed"))
    ns:Print("  Mouse enabled: " .. tostring(firstButton:IsMouseEnabled()))
    ns:Print("  Shown: " .. tostring(firstButton:IsShown()))
    ns:Print("  Frame level: " .. tostring(firstButton:GetFrameLevel()))

    -- List children
    local children = {firstButton:GetChildren()}
    ns:Print("  Children (" .. #children .. "):")
    for i, child in ipairs(children) do
        local childName = child:GetName() or child:GetObjectType()
        local mouseEnabled = child.IsMouseEnabled and child:IsMouseEnabled() or "N/A"
        local shown = child:IsShown()
        local level = child.GetFrameLevel and child:GetFrameLevel() or "N/A"
        ns:Print("    " .. i .. ": " .. childName .. " mouse=" .. tostring(mouseEnabled) .. " shown=" .. tostring(shown) .. " level=" .. tostring(level))
    end

    -- Check specific overlays
    local overlays = {"ItemContextOverlay", "SearchOverlay", "ExtendedSlot", "WidgetContainer", "Cooldown", "NineSlice"}
    ns:Print("  Known overlays:")
    for _, name in ipairs(overlays) do
        local overlay = firstButton[name]
        if overlay then
            local shown = overlay.IsShown and overlay:IsShown() or "N/A"
            local mouse = overlay.IsMouseEnabled and overlay:IsMouseEnabled() or "N/A"
            ns:Print("    " .. name .. ": exists, shown=" .. tostring(shown) .. " mouse=" .. tostring(mouse))
        else
            ns:Print("    " .. name .. ": not found")
        end
    end
end

-- List saved characters
commandHandlers["chars"] = function()
    local Database = GetDatabase()
    ns:Print(L["CMD_SAVED_CHARACTERS"])

    local characters = Database:GetAllCharacterData()
    if characters and next(characters) then
        local currentFullName = Database:GetPlayerFullName()
        for fullName, data in pairs(characters) do
            local bagCount = 0
            local bagItemCount = 0
            local bankCount = 0
            local bankItemCount = 0

            if data.bags then
                for _, bagData in pairs(data.bags) do
                    bagCount = bagCount + 1
                    if bagData.slots then
                        for _ in pairs(bagData.slots) do
                            bagItemCount = bagItemCount + 1
                        end
                    end
                end
            end

            if data.bank then
                for _, bagData in pairs(data.bank) do
                    bankCount = bankCount + 1
                    if bagData.slots then
                        for _ in pairs(bagData.slots) do
                            bankItemCount = bankItemCount + 1
                        end
                    end
                end
            end

            local current = (fullName == currentFullName) and " " .. L["CMD_YOU"] or ""
            ns:Print("  " .. fullName .. current)
            ns:Print("    " .. L["CMD_BAGS"] .. bagCount .. L["CMD_CONTAINERS"] .. bagItemCount .. L["CMD_ITEMS"])
            ns:Print("    " .. L["CMD_BANK"] .. bankCount .. L["CMD_CONTAINERS"] .. bankItemCount .. L["CMD_ITEMS"])
        end
    else
        ns:Print("  " .. L["CMD_NO_DATA"])
    end
end

-- Force save current character
commandHandlers["save"] = function()
    local BagScanner = GetBagScanner()
    local Database = GetDatabase()

    ns:Print(L["CMD_SCANNING"])
    local bags = BagScanner:ScanAllBags()

    local bagCount = 0
    local itemCount = 0
    for _, bagData in pairs(bags) do
        bagCount = bagCount + 1
        if bagData.slots then
            for _ in pairs(bagData.slots) do
                itemCount = itemCount + 1
            end
        end
    end
    ns:Print(string.format(L["CMD_SCANNED"], bagCount, itemCount))

    ns:Print(L["CMD_SAVING_TO"] .. Database:GetPlayerFullName())
    BagScanner:SaveToDatabase()
    ns:Print(L["CMD_DONE"])
end

-- Show current locale info
commandHandlers["locale"] = function()
    local Database = GetDatabase()
    local testLocale = Database:GetGlobalSetting("testLocale")

    ns:Print("Current locale: " .. ns:GetCurrentLocale())
    ns:Print("Game locale: " .. GetLocale())
    if testLocale then
        ns:Print("Test override: " .. testLocale)
    else
        ns:Print("Test override: none")
    end
    ns:Print("Available: " .. table.concat(ns:GetAvailableLocales(), ", "))
end

-- Debug hearthstone button
commandHandlers["debughs"] = function()
    local Hearthstone = ns:GetModule("Footer.Hearthstone")
    ns:Print("Checking hearthstone button structure...")

    local button = Hearthstone:GetButton()
    local wrapper = Hearthstone:GetWrapper()

    if not button then
        ns:Print("Hearthstone button not found. Open your bags first.")
        return
    end

    ns:Print("Wrapper: " .. (wrapper and wrapper:GetName() or "nil"))
    if wrapper then
        ns:Print("  Wrapper shown: " .. tostring(wrapper:IsShown()))
        ns:Print("  Wrapper mouse: " .. tostring(wrapper:IsMouseEnabled()))
        ns:Print("  Wrapper level: " .. tostring(wrapper:GetFrameLevel()))
        ns:Print("  Wrapper strata: " .. tostring(wrapper:GetFrameStrata()))
    end

    ns:Print("Button: " .. (button:GetName() or "unnamed"))
    ns:Print("  Mouse enabled: " .. tostring(button:IsMouseEnabled()))
    ns:Print("  Shown: " .. tostring(button:IsShown()))
    ns:Print("  Frame level: " .. tostring(button:GetFrameLevel()))
    ns:Print("  Frame strata: " .. tostring(button:GetFrameStrata()))
    ns:Print("  Alpha: " .. tostring(button:GetAlpha()))

    -- Check position
    local point, relativeTo, relativePoint, x, y = button:GetPoint(1)
    ns:Print("  Position: " .. tostring(point) .. " offset=" .. tostring(x) .. "," .. tostring(y))

    -- List children
    local children = {button:GetChildren()}
    ns:Print("  Children (" .. #children .. "):")
    for i, child in ipairs(children) do
        local childName = child:GetName() or child:GetObjectType()
        local mouseEnabled = child.IsMouseEnabled and child:IsMouseEnabled() or "N/A"
        local shown = child:IsShown()
        ns:Print("    " .. i .. ": " .. childName .. " mouse=" .. tostring(mouseEnabled) .. " shown=" .. tostring(shown))
    end

    -- Check overlays
    local overlays = {"ItemContextOverlay", "SearchOverlay", "ExtendedSlot", "WidgetContainer", "Cooldown", "NineSlice"}
    ns:Print("  Known overlays:")
    for _, name in ipairs(overlays) do
        local overlay = button[name]
        if overlay then
            local parent = overlay.GetParent and overlay:GetParent()
            local parentName = parent and (parent.GetName and parent:GetName() or "has parent") or "nil parent"
            ns:Print("    " .. name .. ": exists, parent=" .. parentName)
        end
    end
end

-- Help
commandHandlers["help"] = function()
    ns:Print(L["CMD_COMMANDS"])
    ns:Print("  " .. L["CMD_HELP_TOGGLE"])
    ns:Print("  " .. L["CMD_HELP_BANK"])
    ns:Print("  " .. L["CMD_HELP_SETTINGS"])
    ns:Print("  " .. L["CMD_HELP_SORT"])
    ns:Print("  " .. L["CMD_HELP_CHARS"])
    ns:Print("  " .. L["CMD_HELP_SAVE"])
    ns:Print("  " .. L["CMD_HELP_COUNT"])
    ns:Print("  " .. L["CMD_HELP_DEBUG"])
    ns:Print("  " .. L["CMD_HELP_HELP"])
    ns:Print("  /guda locale [code|reset] - Test locale")
end

-------------------------------------------------
-- Pattern-based Command Handlers
-------------------------------------------------

local patternHandlers = {}

-- Count item by ID across characters
patternHandlers["^count%s+(%d+)$"] = function(itemID)
    local Database = GetDatabase()
    local total, chars = Database:CountItemAcrossCharacters(tonumber(itemID))
    ns:Print(string.format(L["CMD_ITEM_COUNT"], itemID, total))
    for _, c in ipairs(chars) do
        local current = c.isCurrent and " " .. L["CMD_YOU"] or ""
        ns:Print("  " .. c.name .. current .. ": " .. c.count)
    end
end

-- Set locale (use original case)
patternHandlers["^locale%s+(%S+)$"] = function(localeCode)
    ns:SetLocale(localeCode)
end

-------------------------------------------------
-- Main Command Dispatcher
-------------------------------------------------

local function HandleSlashCommand(msg)
    local originalMsg = msg or ""
    local cmd = string.lower(originalMsg)

    -- Try exact match first
    if commandHandlers[cmd] then
        commandHandlers[cmd]()
        return
    end

    -- Try pattern matches (use original message for case-sensitive patterns like locale)
    for pattern, handler in pairs(patternHandlers) do
        local capture = originalMsg:match(pattern)
        if capture then
            handler(capture)
            return
        end
    end

    -- Unknown command
    ns:Print(L["CMD_UNKNOWN"])
end

-------------------------------------------------
-- Registration
-------------------------------------------------

function SlashCommands:Register()
    _G["SLASH_GUDABAGS1"] = "/guda"
    _G["SLASH_GUDABAGS2"] = "/gb"
    _G.SlashCmdList["GUDABAGS"] = HandleSlashCommand
end

-- Auto-register on load
SlashCommands:Register()
