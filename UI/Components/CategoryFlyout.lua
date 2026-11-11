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

local ROW_HEIGHT = 34
local ROW_SPACING = 3
local ICON_SIZE = 28
local ICON_HOVER_SIZE = 31     -- icon grows a little under the cursor
local COL_WIDTH = 180
local COL_SPACING = 6
local PADDING = 6
local FRAME_GAP = 2
local DEFAULT_ICON = "Interface\\AddOns\\GudaBags\\Assets\\plus.png"
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- Gold accent shared by the border, the hover stripe and the hovered name.
local ACCENT_R, ACCENT_G, ACCENT_B = 1.0, 0.82, 0.2
-- Idle rows are dimmed (gray name, desaturated faded icon) so the row under
-- the dragged item stands out when it lights up in color.
local TEXT_R, TEXT_G, TEXT_B = 0.55, 0.55, 0.55
local IDLE_ICON_ALPHA = 0.55

local FADE_DURATION = 0.15
local ROW_STAGGER = 0.02       -- per-row fade delay, capped by ROW_STAGGER_MAX
local ROW_STAGGER_MAX = 0.2

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
    bar:SetBackdropColor(0.04, 0.04, 0.05, 0.95)
    bar:SetBackdropBorderColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.55)

    -- Soft sheen across the top half
    local sheen = bar:CreateTexture(nil, "BORDER")
    sheen:SetTexture(WHITE)
    sheen:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    sheen:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -1, -1)
    sheen:SetPoint("BOTTOM", bar, "CENTER")
    sheen:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.05))

    -- Fade in on every Show (built once; plays only while the bar is shown)
    local fade = bar:CreateAnimationGroup()
    local alpha = fade:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(FADE_DURATION)
    alpha:SetSmoothing("OUT")
    bar.fade = fade

    bar:Hide()
    return bar
end

-- Hover look: gold stripe + tint, gold name, slightly larger icon.
local function SetRowHover(row, hovered)
    if hovered then
        row.accent:Show()
        row.hover:Show()
        row.text:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B)
        row.icon:SetSize(ICON_HOVER_SIZE, ICON_HOVER_SIZE)
        row.icon:SetDesaturated(false)
        row.icon:SetAlpha(1)
        row.iconBorder:SetVertexColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
    else
        row.accent:Hide()
        row.hover:Hide()
        row.text:SetTextColor(TEXT_R, TEXT_G, TEXT_B)
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)
        row.icon:SetDesaturated(true)
        row.icon:SetAlpha(IDLE_ICON_ALPHA)
        row.iconBorder:SetVertexColor(0, 0, 0, 0.9)
    end
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, bar)
    row:SetSize(COL_WIDTH, ROW_HEIGHT)

    -- Background: fades out toward the right
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(WHITE)
    bg:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0.05), CreateColor(1, 1, 1, 0.01))

    -- Hover tint (gold, fading right) and left accent stripe
    local hover = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    hover:SetAllPoints()
    hover:SetTexture(WHITE)
    hover:SetGradient("HORIZONTAL",
        CreateColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.35), CreateColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.04))
    hover:Hide()
    row.hover = hover

    local accent = row:CreateTexture(nil, "BORDER")
    accent:SetTexture(WHITE)
    accent:SetVertexColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    accent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    accent:SetWidth(2)
    accent:Hide()
    row.accent = accent

    -- Framed icon: a 1px border behind a trimmed icon
    local iconHolder = CreateFrame("Frame", nil, row)
    iconHolder:SetSize(ICON_HOVER_SIZE + 2, ICON_HOVER_SIZE + 2)
    iconHolder:SetPoint("LEFT", row, "LEFT", 5, 0)

    local iconBorder = row:CreateTexture(nil, "BORDER", nil, 1)
    iconBorder:SetTexture(WHITE)
    row.iconBorder = iconBorder

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER", iconHolder, "CENTER")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon
    iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local Font = ns:GetModule("Font")
    if Font then Font:Override(text) end
    text:SetPoint("LEFT", iconHolder, "RIGHT", 6, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)  -- long names are cut off with "..."
    row.text = text

    -- Per-row fade, staggered in Show() so the list cascades in
    local fade = row:CreateAnimationGroup()
    local alpha = fade:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(FADE_DURATION)
    alpha:SetSmoothing("OUT")
    fade:SetToFinalAlpha(true)
    row.fade, row.fadeAlpha = fade, alpha

    SetRowHover(row, false)

    row:EnableMouse(true)
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton == "LeftButton" then HandleDrop(self) end
    end)
    row:SetScript("OnReceiveDrag", HandleDrop)
    row:SetScript("OnEnter", function(self)
        SetRowHover(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.categoryName or "", 1, 1, 1)
        GameTooltip:AddLine(ns.L["DROP_HERE_TO_ASSIGN"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        SetRowHover(self, false)
        GameTooltip:Hide()
    end)

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
    local animate = not bar:IsShown()  -- fade in only on open, not on re-show mid-drag

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
        SetRowHover(row, false)  -- a row hidden while hovered never got OnLeave
        row:Show()
        row.fade:Stop()
        if animate then
            row.fadeAlpha:SetStartDelay(math.min((i - 1) * ROW_STAGGER, ROW_STAGGER_MAX))
            row:SetAlpha(0)
            row.fade:Play()
        else
            row:SetAlpha(1)
        end
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
    if animate then
        bar.fade:Stop()
        bar.fade:Play()
    end
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
