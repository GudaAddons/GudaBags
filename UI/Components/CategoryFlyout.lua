local addonName, ns = ...

-- CategoryFlyout: while an item is dragged in category view, lists the empty
-- categories in columns beside the bag frame so the item can be assigned to one.
-- Lives outside the bag layout on purpose: the old in-layout drop targets pushed
-- the whole layout upward mid-drag, so quick drags missed their slot.
--
-- The bag frame drives it (drag detection in UI/BagFrame.lua): Show() on drag
-- start with the list from LayoutEngine:GetEmptyDropTargetCategories(), Hide() on
-- drag end. Rows are plain (non-secure) buttons created on first use out of
-- combat and reused after that; the bar never shows in combat.

local CategoryFlyout = {}
ns:RegisterModule("CategoryFlyout", CategoryFlyout)

-------------------------------------------------
-- Layout
-------------------------------------------------

local ROW_HEIGHT = 24
local ROW_SPACING = 2
local ICON_SIZE = 20
local COL_WIDTH = 150
local COL_SPACING = 4
local PADDING = 4
local FRAME_GAP = 2
local DEFAULT_ICON = "Interface\\AddOns\\GudaBags\\Assets\\plus.png"

-------------------------------------------------
-- State
-------------------------------------------------

local bar = nil
local rows = {}

local function HandleDrop(row)
    if not row.categoryId then return end
    local infoType, itemID = GetCursorInfo()
    if infoType ~= "item" or not itemID then return end
    ClearCursor()
    local CategoryManager = ns:GetModule("CategoryManager")
    if CategoryManager then
        CategoryManager:AssignItemToCategory(itemID, row.categoryId)
    end
    CategoryFlyout:Hide()
end

local function CreateBar()
    if bar then return bar end
    bar = CreateFrame("Frame", "GudaBagsCategoryFlyout", UIParent, "BackdropTemplate")
    bar:SetFrameStrata("FULLSCREEN_DIALOG")
    bar:SetFrameLevel(500)
    bar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    bar:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    bar:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    bar:Hide()
    return bar
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, bar)
    row:SetSize(COL_WIDTH, ROW_HEIGHT)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.05)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.icon = icon

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local Font = ns:GetModule("Font")
    if Font then Font:Override(text) end
    text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)  -- long names are cut off with "..."
    row.text = text

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    row:EnableMouse(true)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton == "LeftButton" then HandleDrop(self) end
    end)
    row:SetScript("OnReceiveDrag", HandleDrop)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.categoryName or "", 1, 1, 1)
        GameTooltip:AddLine(ns.L["DROP_HERE_TO_ASSIGN"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    rows[index] = row
    return row
end

-------------------------------------------------
-- Public API
-------------------------------------------------

-- targets: list of { categoryId, name, icon } (LayoutEngine:GetEmptyDropTargetCategories)
function CategoryFlyout:Show(bagFrame, targets)
    if InCombatLockdown() then return end
    if not bagFrame or not targets or #targets == 0 then
        self:Hide()
        return
    end

    CreateBar()

    -- Match the bag frame's effective scale so its height is in our units.
    bar:SetScale(bagFrame:GetEffectiveScale() / UIParent:GetEffectiveScale())

    -- Columns as tall as the bag frame; wrap into more columns when needed.
    local count = #targets
    local usable = bagFrame:GetHeight() - PADDING * 2 + ROW_SPACING
    local maxPerCol = math.max(1, math.floor(usable / (ROW_HEIGHT + ROW_SPACING)))
    local cols = math.ceil(count / maxPerCol)
    local perCol = math.ceil(count / cols)  -- balance rows across columns

    local width = PADDING * 2 + cols * COL_WIDTH + (cols - 1) * COL_SPACING
    local height = PADDING * 2 + perCol * ROW_HEIGHT + (perCol - 1) * ROW_SPACING
    bar:SetSize(width, height)

    -- Left of the bag unless there is no room there and more on the right.
    local left = bagFrame:GetLeft() or 0
    local screenRight = UIParent:GetRight() * UIParent:GetEffectiveScale() / bagFrame:GetEffectiveScale()
    local right = screenRight - (bagFrame:GetRight() or 0)
    local onLeft = left >= width + FRAME_GAP or left >= right

    for i, target in ipairs(targets) do
        local row = rows[i] or CreateRow(i)
        local col = math.floor((i - 1) / perCol)      -- 0 = column nearest the bag
        local line = (i - 1) % perCol
        local slot = onLeft and (cols - 1 - col) or col
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", bar, "TOPLEFT",
            PADDING + slot * (COL_WIDTH + COL_SPACING),
            -(PADDING + line * (ROW_HEIGHT + ROW_SPACING)))
        row.categoryId = target.categoryId
        row.categoryName = target.name
        row.icon:SetTexture(target.icon or DEFAULT_ICON)
        row.text:SetText(target.name)
        row:Show()
    end
    for i = count + 1, #rows do
        rows[i].categoryId = nil
        rows[i]:Hide()
    end

    bar:ClearAllPoints()
    if onLeft then
        bar:SetPoint("TOPRIGHT", bagFrame, "TOPLEFT", -FRAME_GAP, 0)
    else
        bar:SetPoint("TOPLEFT", bagFrame, "TOPRIGHT", FRAME_GAP, 0)
    end
    bar:Show()
end

function CategoryFlyout:Hide()
    if bar and bar:IsShown() then
        bar:Hide()
        GameTooltip:Hide()
    end
end

function CategoryFlyout:IsShown()
    return bar and bar:IsShown()
end

-------------------------------------------------
-- Combat hide (matches DragFlyoutBar)
-------------------------------------------------

local Events = ns:GetModule("Events")
Events:Register("PLAYER_REGEN_DISABLED", function()
    CategoryFlyout:Hide()
end, CategoryFlyout)
