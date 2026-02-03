local addonName, ns = ...

ns.addonName = addonName

-- Read version from TOC file (compatible with all WoW versions)
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
ns.version = GetAddOnMetadata(addonName, "Version") or "1.0.0"

ns.Modules = {}

function ns:RegisterModule(name, module)
    self.Modules[name] = module
end

function ns:GetModule(name)
    return self.Modules[name]
end

function ns:Print(...)
    local msg = string.join(" ", tostringall(...))
    print("|cff00ccff[GudaBags]|r " .. msg)
end

-- Debug log buffer
local debugLogBuffer = {}
local MAX_LOG_LINES = 1000  -- Keep last 1000 lines
local debugLogViewer = nil

function ns:Debug(...)
    if not self.debugMode then return end
    local msg = string.join(" ", tostringall(...))
    print("|cff888888[GudaBags Debug]|r " .. msg)

    -- Add timestamp and store in buffer
    local timestamp = date("%H:%M:%S")
    local logLine = string.format("[%s] %s", timestamp, msg)
    table.insert(debugLogBuffer, logLine)

    -- Trim old entries if buffer gets too large
    while #debugLogBuffer > MAX_LOG_LINES do
        table.remove(debugLogBuffer, 1)
    end
end

-- Clear debug log
function ns:ClearDebugLog()
    debugLogBuffer = {}
    if GudaBags_DebugLog then
        GudaBags_DebugLog = {}
    end
    ns:Print("Debug log cleared (" .. MAX_LOG_LINES .. " lines capacity)")
end

-- Get debug log contents
function ns:GetDebugLog()
    return debugLogBuffer
end

-- Get debug log as single string
function ns:GetDebugLogText()
    return table.concat(debugLogBuffer, "\n")
end

-- Create debug log viewer window
local function CreateDebugLogViewer()
    local frame = CreateFrame("Frame", "GudaBagsDebugLogViewer", UIParent, "BackdropTemplate")
    frame:SetSize(700, 500)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("GudaBags Debug Log")
    title:SetTextColor(1, 0.82, 0)
    frame.title = title

    -- Line count
    local lineCount = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lineCount:SetPoint("TOPRIGHT", -40, -12)
    lineCount:SetTextColor(0.7, 0.7, 0.7)
    frame.lineCount = lineCount

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "GudaBagsDebugLogScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, -35)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 45)

    -- Edit box (for copy/paste)
    local editBox = CreateFrame("EditBox", "GudaBagsDebugLogEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetWidth(scrollFrame:GetWidth() - 10)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)
    frame.editBox = editBox

    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 22)
    refreshBtn:SetPoint("BOTTOMLEFT", 10, 10)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        ns:RefreshDebugLogViewer()
    end)

    -- Clear button
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 5, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        ns:ClearDebugLog()
        ns:RefreshDebugLogViewer()
    end)

    -- Select All button
    local selectBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    selectBtn:SetSize(80, 22)
    selectBtn:SetPoint("LEFT", clearBtn, "RIGHT", 5, 0)
    selectBtn:SetText("Select All")
    selectBtn:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    -- Instructions
    local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instructions:SetPoint("BOTTOMRIGHT", -10, 14)
    instructions:SetText("Select All + Ctrl+C to copy")
    instructions:SetTextColor(0.5, 0.5, 0.5)

    frame:Hide()
    tinsert(UISpecialFrames, "GudaBagsDebugLogViewer")

    return frame
end

-- Refresh the debug log viewer content
function ns:RefreshDebugLogViewer()
    if not debugLogViewer then return end

    local text = self:GetDebugLogText()
    if text == "" then
        text = "Debug log is empty.\n\nEnable debug mode with: /guda debug\nThen reproduce the issue."
    end

    debugLogViewer.editBox:SetText(text)
    debugLogViewer.lineCount:SetText(#debugLogBuffer .. "/" .. MAX_LOG_LINES .. " lines")

    -- Scroll to bottom
    C_Timer.After(0.05, function()
        local scrollFrame = _G["GudaBagsDebugLogScrollFrame"]
        if scrollFrame then
            scrollFrame:SetVerticalScroll(scrollFrame:GetVerticalScrollRange())
        end
    end)
end

-- Show debug log viewer
function ns:ShowDebugLogViewer()
    if not debugLogViewer then
        debugLogViewer = CreateDebugLogViewer()
    end

    self:RefreshDebugLogViewer()
    debugLogViewer:Show()
end

-- Save debug log to SavedVariables (called on logout)
local function SaveDebugLog()
    if ns.debugMode and #debugLogBuffer > 0 then
        GudaBags_DebugLog = GudaBags_DebugLog or {}
        GudaBags_DebugLog.timestamp = date("%Y-%m-%d %H:%M:%S")
        GudaBags_DebugLog.lines = debugLogBuffer
    end
end

-- Load debug log from SavedVariables (called on login)
local function LoadDebugLog()
    if GudaBags_DebugLog and GudaBags_DebugLog.lines then
        debugLogBuffer = GudaBags_DebugLog.lines
        ns:Print("Loaded " .. #debugLogBuffer .. " debug log lines from previous session")
    end
end

-- Register for logout to save logs
local logFrame = CreateFrame("Frame")
logFrame:RegisterEvent("PLAYER_LOGOUT")
logFrame:RegisterEvent("PLAYER_LOGIN")
logFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGOUT" then
        SaveDebugLog()
    elseif event == "PLAYER_LOGIN" then
        if ns.debugMode then
            LoadDebugLog()
        end
    end
end)

ns.debugMode = false  -- Enable for debugging (set to true and /reload)
