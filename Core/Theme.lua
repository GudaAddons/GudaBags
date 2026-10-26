local addonName, ns = ...

local Theme = {}
ns:RegisterModule("Theme", Theme)

local Database = ns:GetModule("Database")
local Events = ns:GetModule("Events")

-------------------------------------------------
-- Theme Definitions
-------------------------------------------------
local themes = {
    guda = {
        frameBg = {0.08, 0.08, 0.08, 1},
        frameBorder = {0.30, 0.30, 0.30, 1},
        headerBg = {0.12, 0.12, 0.12, 1},
        titleColor = {1, 1, 1, 1},
        slotBgColor = {0.15, 0.15, 0.15, 1},
        bankTabBg = {0.12, 0.12, 0.12, 1},
        bankTabBorder = {0.30, 0.30, 0.30, 1},
        bankTabSelected = {0.20, 0.20, 0.20, 1},
        footerButtonBg = {0.12, 0.12, 0.12, 1},
        footerButtonBorder = {0.30, 0.30, 0.30, 1},
        useBlizzardFrame = false,
        backdrop = {
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets = {left = 3, right = 3, top = 3, bottom = 3},
        },
        headerBackdrop = {
            bgFile = "Interface\\Buttons\\WHITE8x8",
        },
        backdropSolid = {
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        },
    },
    blizzard = {
        frameBg = {1, 1, 1, 1},
        frameBorder = {1, 1, 1, 1},
        headerBg = {1, 1, 1, 1},
        titleColor = {1, 1, 1, 1},
        slotBgColor = {0.15, 0.15, 0.15, 1},
        bankTabBg = {0.12, 0.12, 0.12, 1},
        bankTabBorder = {0.30, 0.30, 0.30, 1},
        bankTabSelected = {0.20, 0.20, 0.20, 1},
        footerButtonBg = {0.12, 0.12, 0.12, 1},
        footerButtonBorder = {0.30, 0.30, 0.30, 1},
        useBlizzardFrame = true,
        backdrop = nil,
        headerBackdrop = nil,
        backdropSolid = {
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        },
    },
    retail = {
        frameBg = {0.08, 0.08, 0.08, 1},
        frameBorder = {0.30, 0.30, 0.30, 1},
        headerBg = {0.12, 0.12, 0.12, 1},
        titleColor = {1, 1, 1, 1},
        slotBgColor = {0.15, 0.15, 0.15, 1},
        bankTabBg = {0.12, 0.12, 0.12, 1},
        bankTabBorder = {0.30, 0.30, 0.30, 1},
        bankTabSelected = {0.20, 0.20, 0.20, 1},
        footerButtonBg = {0.12, 0.12, 0.12, 1},
        footerButtonBorder = {0.30, 0.30, 0.30, 1},
        useBlizzardFrame = false,
        useMetalFrame = true,
        backdrop = nil,
        headerBackdrop = nil,
        backdropSolid = {
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        },
        metalTextures = {
            corners = "Interface\\AddOns\\GudaBags\\Assets\\Themes\\retail\\UIFrameMetal2x",
            horizontal = "Interface\\AddOns\\GudaBags\\Assets\\Themes\\retail\\UIFrameMetalHorizontal2x",
            vertical = "Interface\\AddOns\\GudaBags\\Assets\\Themes\\retail\\UIFrameMetalVertical2x",
            background = "Interface\\AddOns\\GudaBags\\Assets\\Themes\\retail\\UI-Background-Rock",
        },
        slotTextures = {
            background = "Interface\\AddOns\\GudaBags\\Assets\\Themes\\retail\\HDActionBarBtn",
            border = "Interface\\AddOns\\GudaBags\\Assets\\Themes\\retail\\btn_border",
            highlight = "Interface\\AddOns\\GudaBags\\Assets\\Themes\\retail\\btn_highlight_strong",
        },
    },
    -- Flat: solid panels, 1px borders, one accent color, no textures, so it looks
    -- the same on every client. Rides the guda code paths (backdrop + header
    -- backdrop); only the close button has a flat style of its own.
    flat = {
        frameBg = {0.071, 0.071, 0.071, 1},        -- #121212
        frameBorder = {0.247, 0.722, 0.686, 1},    -- accent: the window wears the accent color
        headerBg = {0.102, 0.102, 0.102, 1},       -- #1A1A1A
        headerLine = {0.247, 0.722, 0.686, 1},     -- accent line under the title bar
        titleColor = {1, 1, 1, 1},
        slotBgColor = {0.055, 0.055, 0.055, 1},    -- #0E0E0E
        bankTabBg = {0.118, 0.118, 0.118, 1},      -- #1E1E1E
        bankTabBorder = {0.165, 0.165, 0.165, 1},
        bankTabSelected = {0.149, 0.149, 0.149, 1},
        footerButtonBg = {0.118, 0.118, 0.118, 1},
        footerButtonBorder = {0.165, 0.165, 0.165, 1},
        accent = {0.247, 0.722, 0.686, 1},         -- #3FB8AF
        buttonHover = {0.149, 0.149, 0.149, 1},    -- #262626
        slotEmptyBorder = {0.165, 0.165, 0.165, 1},
        slotEmptyFill = {0.055, 0.055, 0.055, 1},  -- #0E0E0E
        slotCommonBorder = {0.227, 0.227, 0.227, 1}, -- #3A3A3A
        flatSlots = true,  -- empty slots use the minimal flat look (unless Masque is active)
        -- Theme:Color keys: chrome that other themes draw with call-site literals
        panelBg = {0.071, 0.071, 0.071, 0.98},     -- dropdowns, menus
        panelBorder = {0.165, 0.165, 0.165, 1},
        searchBarBg = {0.102, 0.102, 0.102, 1},
        searchBarBorder = {0.165, 0.165, 0.165, 1},
        chipBg = {0.118, 0.118, 0.118, 1},
        chipHoverBg = {0.149, 0.149, 0.149, 1},
        chipText = {0.6, 0.6, 0.6, 1},
        chipActiveType = {0.247, 0.722, 0.686, 0.9},
        chipActiveSpecial = {0.247, 0.722, 0.686, 0.9},
        tabBg = {0.118, 0.118, 0.118, 1},
        tabBorder = {0.165, 0.165, 0.165, 1},
        tabSelectedBorder = {0.247, 0.722, 0.686, 1},
        tabSelectedBg = {0.071, 0.071, 0.071, 1},  -- = frameBg: the selected tab joins the window
        tabSelectedText = {0.247, 0.722, 0.686, 1},
        sideTabBg = {0.055, 0.055, 0.055, 0.95},
        buttonBg = {0.118, 0.118, 0.118, 1},
        buttonBorder = {0.165, 0.165, 0.165, 1},
        categoryHeaderText = {0.85, 0.85, 0.85, 1},
        categoryHeaderLine = {0.165, 0.165, 0.165, 1},
        -- Theme:Backdrop keys: the rounded tooltip border becomes a 1px line
        panelBackdrop = {
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = {left = 1, right = 1, top = 1, bottom = 1},
        },
        useBlizzardFrame = false,
        useFlatCloseButton = true,
        backdrop = {
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = {left = 1, right = 1, top = 1, bottom = 1},
        },
        headerBackdrop = {
            bgFile = "Interface\\Buttons\\WHITE8x8",
        },
        backdropSolid = {
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        },
    },
}
-------------------------------------------------
-- Classic border texture keys in ButtonFrameTemplate
-------------------------------------------------
local classicBorderKeys = {
    "BotLeftCorner", "BotRightCorner", "BottomBorder",
    "LeftBorder", "RightBorder",
    "TopRightCorner", "TopLeftCorner", "TopBorder",
}

-------------------------------------------------
-- Cache
-------------------------------------------------
local cachedTheme = nil
local cachedThemeName = nil

-- Flat keys that take the player's accent color (setting "flatAccentColor").
-- Each keeps its own alpha from the theme table.
local FLAT_ACCENT_KEYS = { "accent", "chipActiveType", "chipActiveSpecial", "tabSelectedBorder", "tabSelectedText",
    "frameBorder", "headerLine" }

-- A view of `base` with the accent keys recolored; everything else falls through
local function ApplyFlatAccent(base, color)
    if type(color) ~= "table" or not color[1] then return base end
    local view = setmetatable({}, { __index = base })
    for _, key in ipairs(FLAT_ACCENT_KEYS) do
        local alpha = base[key] and base[key][4] or 1
        view[key] = { color[1], color[2], color[3], alpha }
    end
    return view
end

-------------------------------------------------
-- API
-------------------------------------------------

--- Returns the active theme table
function Theme:Get()
    local themeName = Database:GetSetting("theme") or "guda"
    -- HasRetailFrameArt, not IsRetail: the "retail" theme only duplicates
    -- "blizzard" on a client whose native frame art is already the metal look.
    -- WoW: Forever is modern-API on Vanilla art, so there the bundled skin is a
    -- genuinely different look and must not be remapped away.
    if themeName == "retail" and ns.ExpansionFeatures.HasRetailFrameArt then
        themeName = "guda"
    elseif themeName == "classic" then
        themeName = "blizzard"
    end
    if cachedTheme and cachedThemeName == themeName then
        return cachedTheme
    end
    cachedThemeName = themeName
    cachedTheme = themes[themeName] or themes.guda
    if themeName == "flat" then
        cachedTheme = ApplyFlatAccent(cachedTheme, Database:GetSetting("flatAccentColor"))
    end
    return cachedTheme
end

--- Flat's default accent as {r, g, b} (the color picker's Reset target)
function Theme:GetDefaultFlatAccent()
    local a = themes.flat.accent
    return { a[1], a[2], a[3] }
end

--- Returns a single theme property value
function Theme:GetValue(key)
    local t = self:Get()
    return t[key]
end

-------------------------------------------------
-- ButtonFrameTemplate background helper
-------------------------------------------------

local blizzBgCount = 0
-- How far to extend the NineSlice beyond the frame on each side (retail
-- NineSlice border is ~8-10px wide; extending pushes border outward so
-- content at PADDING=8 sits comfortably inside the visible border)
local BLIZ_EXTEND_LEFT = 4
local BLIZ_EXTEND_TOP = 1
local BLIZ_EXTEND_RIGHT = 0
local BLIZ_EXTEND_BOTTOM = 1

--- Creates a hidden ButtonFrameTemplate child (once) to use as background
local function EnsureBlizzardBg(frame)
    if frame.blizzardBg then return frame.blizzardBg end

    blizzBgCount = blizzBgCount + 1
    local name = "GudaBagsThemeBg" .. blizzBgCount
    local bliz = CreateFrame("Frame", name, frame, "ButtonFrameTemplate")
    bliz:EnableMouse(false)
    bliz:SetFrameLevel(frame:GetFrameLevel())

    -- Hide all ButtonFrameTemplate UI elements
    if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(bliz) end
    if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(bliz) end
    if bliz.Inset then bliz.Inset:Hide() end
    if bliz.CloseButton then bliz.CloseButton:Hide() end
    if bliz.TitleContainer then bliz.TitleContainer:Hide() end
    if bliz.PortraitFrame then bliz.PortraitFrame:SetAlpha(0) end
    if bliz.PortraitContainer then bliz.PortraitContainer:Hide() end
    if bliz.portrait then bliz.portrait:SetAlpha(0) end

    bliz:Hide()
    frame.blizzardBg = bliz
    return bliz
end

-------------------------------------------------
-- Metal Frame (Retail theme on Classic)
-------------------------------------------------

local metalFrameCount = 0

--- Creates the 8-piece metal border overlay (once per frame)
local function EnsureMetalFrame(frame)
    if frame.metalFrame then return frame.metalFrame end

    local theme = themes.retail
    local tex = theme.metalTextures

    metalFrameCount = metalFrameCount + 1
    local mf = CreateFrame("Frame", "GudaBagsMetalFrame" .. metalFrameCount, frame)
    mf:EnableMouse(false)
    mf:SetAllPoints(frame)
    mf:SetFrameLevel(frame:GetFrameLevel())

    mf.edges = {}

    -- Background
    local bg = mf:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(tex.background)
    bg:SetPoint("TOPLEFT", 2, -21)
    bg:SetPoint("BOTTOMRIGHT", -2, 2)
    mf.bg = bg

    -- Corner texcoords from Dragonflight3 CreatePaperDollFrame (exact values)
    -- TopLeft corner
    local tl = mf:CreateTexture(nil, "OVERLAY")
    tl:SetTexture(tex.corners)
    tl:SetSize(75, 75)
    tl:SetPoint("TOPLEFT", mf, "TOPLEFT", -13, 16)
    tl:SetTexCoord(0.00195312, 0.294922, 0.00195312, 0.294922)
    mf.edges[#mf.edges + 1] = tl

    -- TopRight corner
    local tr = mf:CreateTexture(nil, "OVERLAY")
    tr:SetTexture(tex.corners)
    tr:SetSize(75, 75)
    tr:SetPoint("TOPRIGHT", mf, "TOPRIGHT", 4, 16)
    tr:SetTexCoord(0.298828, 0.591797, 0.00195312, 0.294922)
    mf.edges[#mf.edges + 1] = tr

    -- BottomLeft corner
    local bl = mf:CreateTexture(nil, "OVERLAY")
    bl:SetTexture(tex.corners)
    bl:SetSize(32, 32)
    bl:SetPoint("BOTTOMLEFT", mf, "BOTTOMLEFT", -13, -3)
    bl:SetTexCoord(0.298828, 0.423828, 0.298828, 0.423828)
    mf.edges[#mf.edges + 1] = bl

    -- BottomRight corner
    local br = mf:CreateTexture(nil, "OVERLAY")
    br:SetTexture(tex.corners)
    br:SetSize(32, 32)
    br:SetPoint("BOTTOMRIGHT", mf, "BOTTOMRIGHT", 4, -3)
    br:SetTexCoord(0.427734, 0.552734, 0.298828, 0.423828)
    mf.edges[#mf.edges + 1] = br

    -- Top edge (connects TopLeft to TopRight)
    local top = mf:CreateTexture(nil, "OVERLAY")
    top:SetTexture(tex.horizontal)
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0)
    top:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)
    top:SetHeight(75)
    top:SetTexCoord(0.0, 1.0, 0.00390625, 0.589844)
    mf.edges[#mf.edges + 1] = top

    -- Bottom edge (connects BottomLeft to BottomRight)
    local bottom = mf:CreateTexture(nil, "OVERLAY")
    bottom:SetTexture(tex.horizontal)
    bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
    bottom:SetHeight(32)
    bottom:SetTexCoord(0.0, 0.5, 0.597656, 0.847656)
    mf.edges[#mf.edges + 1] = bottom

    -- Left edge (connects TopLeft to BottomLeft)
    local left = mf:CreateTexture(nil, "OVERLAY")
    left:SetTexture(tex.vertical)
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
    left:SetWidth(75)
    left:SetTexCoord(0.00195312, 0.294922, 0.0, 1.0)
    mf.edges[#mf.edges + 1] = left

    -- Right edge (connects TopRight to BottomRight)
    local right = mf:CreateTexture(nil, "OVERLAY")
    right:SetTexture(tex.vertical)
    right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT", 0, 0)
    right:SetPoint("BOTTOMLEFT", br, "TOPLEFT", 0, 0)
    right:SetWidth(75)
    right:SetTexCoord(0.298828, 0.591797, 0.0, 1.0)
    mf.edges[#mf.edges + 1] = right

    mf:Hide()
    frame.metalFrame = mf
    return mf
end

--- Apply the correct background for the current theme.
--- Call this from UpdateFrameAppearance in each frame module.
--- @param frame table The main addon frame
--- @param bgAlpha number 0-1 opacity
--- @param showBorders boolean Whether borders are visible
function Theme:ApplyFrameBackground(frame, bgAlpha, showBorders)
    local useMetal = self:GetValue("useMetalFrame")
    if useMetal then
        -- Hide other theme elements
        if frame.blizzardBg then frame.blizzardBg:Hide() end
        if frame.SetBackdrop then frame:SetBackdrop(nil) end
        if frame.themeBg then frame.themeBg:Hide() end
        -- Create/show metal frame
        local mf = EnsureMetalFrame(frame)
        mf:SetFrameLevel(frame:GetFrameLevel())
        mf:SetAllPoints(frame)
        mf:Show()
        mf.bg:SetAlpha(bgAlpha)
        -- Show/hide border pieces
        for _, piece in ipairs(mf.edges) do
            piece:SetShown(showBorders)
            piece:SetAlpha(showBorders and bgAlpha or 0)
        end
        return
    end

    local useBlizzard = self:GetValue("useBlizzardFrame")

    if useBlizzard then
        -- Hide metal frame if switching from retail theme
        if frame.metalFrame then frame.metalFrame:Hide() end
        -- Blizzard theme: ButtonFrameTemplate child provides bg + border
        local bliz = EnsureBlizzardBg(frame)
        -- Match the frame's own level so the Blizzard bg covers frames below,
        -- just like SetBackdrop does for the Guda theme.  The frame's children
        -- (header, item buttons, scroll child) already have higher explicit
        -- levels so they render on top.
        local baseLvl = frame:GetFrameLevel()
        bliz:SetFrameLevel(baseLvl)
        bliz:SetAllPoints(frame)
        bliz:Show()

        -- Background texture
        bliz.Bg:SetAlpha(bgAlpha)
        bliz.Bg:ClearAllPoints()
        if bliz.TopTileStreaks then
            bliz.TopTileStreaks:Hide()
        end

        if showBorders then
            bliz.Bg:SetPoint("TOPLEFT", 2, -2)
            bliz.Bg:SetPoint("BOTTOMRIGHT", -2, 2)
        else
            bliz.Bg:SetPoint("TOPLEFT", 2, 0)
            bliz.Bg:SetPoint("BOTTOMRIGHT", -2, 0)
        end

        -- Hide title bar divider (our custom header handles the title area)
        if bliz.TitleBg then
            bliz.TitleBg:Hide()
        end

        -- Classic border pieces (stay at frame edges — works fine on Classic)
        for _, key in ipairs(classicBorderKeys) do
            if bliz[key] then
                bliz[key]:SetShown(showBorders)
                bliz[key]:SetAlpha(bgAlpha)
            end
        end

        -- Retail NineSlice: extend outward so the thick border wraps around
        -- content instead of eating into the PADDING area. Hide center fill
        -- since Bg handles the background.
        if bliz.NineSlice then
            bliz.NineSlice:SetShown(showBorders)
            bliz.NineSlice:SetAlpha(bgAlpha)
            bliz.NineSlice:SetFrameLevel(baseLvl)
            bliz.NineSlice:ClearAllPoints()
            bliz.NineSlice:SetPoint("TOPLEFT", bliz, "TOPLEFT", -BLIZ_EXTEND_LEFT, BLIZ_EXTEND_TOP)
            bliz.NineSlice:SetPoint("BOTTOMRIGHT", bliz, "BOTTOMRIGHT", BLIZ_EXTEND_RIGHT, -BLIZ_EXTEND_BOTTOM)
            if bliz.NineSlice.Center then
                bliz.NineSlice.Center:Hide()
            end
        end

        -- Clear the main frame backdrop entirely
        frame:SetBackdrop(nil)

        -- Hide the old themeBg texture if it exists from previous approach
        if frame.themeBg then frame.themeBg:Hide() end
    else
        -- Guda theme: normal backdrop
        if frame.blizzardBg then
            frame.blizzardBg:Hide()
        end
        if frame.metalFrame then frame.metalFrame:Hide() end
        if frame.themeBg then frame.themeBg:Hide() end

        frame:SetBackdrop(self:GetValue("backdrop"))
        local bg = self:GetValue("frameBg")
        frame:SetBackdropColor(bg[1], bg[2], bg[3], bgAlpha)

        if showBorders then
            local border = self:GetValue("frameBorder")
            frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
        else
            frame:SetBackdropBorderColor(0, 0, 0, 0)
        end
    end
end

--- Sync the blizzardBg child frame level after the parent frame level changes.
--- Call this whenever you SetFrameLevel on a bag/bank frame.
function Theme:SyncBlizzardBgLevel(frame)
    if frame and frame.blizzardBg and frame.blizzardBg:IsShown() then
        local baseLvl = frame:GetFrameLevel()
        frame.blizzardBg:SetFrameLevel(baseLvl)
        if frame.blizzardBg.NineSlice then
            frame.blizzardBg.NineSlice:SetFrameLevel(baseLvl)
        end
    end
    if frame and frame.metalFrame and frame.metalFrame:IsShown() then
        frame.metalFrame:SetFrameLevel(frame:GetFrameLevel())
    end
end

-------------------------------------------------
-- Header Icon Button Styling
-------------------------------------------------
local BLIZZARD_ICON_SIZE = 14
local BLIZZARD_ICON_BG_W = 24
local BLIZZARD_ICON_BG_H = 18
local GUDA_ICON_SIZE = 16

local iconBgBackdrop = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 8,
    insets = {left = 2, right = 2, top = 2, bottom = 2},
}

local function EnsureIconBg(button)
    if button.themeBg then return button.themeBg end
    local bg = CreateFrame("Frame", nil, button, "BackdropTemplate")
    bg:SetSize(BLIZZARD_ICON_BG_W, BLIZZARD_ICON_BG_H)
    bg:SetPoint("CENTER")
    bg:SetFrameLevel(button:GetFrameLevel())
    bg:SetBackdrop(iconBgBackdrop)
    bg:SetBackdropColor(0.5, 0.06, 0.06, 0.6)
    bg:SetBackdropBorderColor(0.5, 0.06, 0.06, 1)
    bg:Hide()
    button.themeBg = bg
    return bg
end

local BLIZZARD_GAP = 10
local GUDA_GAP = 4

-- Retail-style red close button texcoords (from redbutton2x atlas)
local CLOSE_TEXCOORDS = {
    normal   = {0.152344, 0.292969, 0.0078125, 0.304688},
    pushed   = {0.152344, 0.292969, 0.320312, 0.617188},
    highlight = {0.449219, 0.589844, 0.0078125, 0.304688},
}
local CLOSE_TEXTURE = "Interface\\AddOns\\GudaBags\\Assets\\Themes\\retail\\redbutton2x"

local function StyleCloseButton(btn, useMetal)
    if useMetal then
        if not btn._metalStyled then
            -- Save original textures
            btn._origNormal = btn:GetNormalTexture()
            btn._origPushed = btn:GetPushedTexture()
            btn._origHighlight = btn:GetHighlightTexture()

            -- Hide original textures
            if btn._origNormal then btn._origNormal:SetAlpha(0) end
            if btn._origPushed then btn._origPushed:SetAlpha(0) end
            if btn._origHighlight then btn._origHighlight:SetAlpha(0) end

            -- Create retail-style textures
            local normal = btn:CreateTexture(nil, "BORDER")
            normal:SetTexture(CLOSE_TEXTURE)
            normal:SetAllPoints(btn)
            normal:SetTexCoord(unpack(CLOSE_TEXCOORDS.normal))
            btn:SetNormalTexture(normal)
            btn._metalNormal = normal

            local pushed = btn:CreateTexture(nil, "BORDER")
            pushed:SetTexture(CLOSE_TEXTURE)
            pushed:SetAllPoints(btn)
            pushed:SetTexCoord(unpack(CLOSE_TEXCOORDS.pushed))
            btn:SetPushedTexture(pushed)
            btn._metalPushed = pushed

            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetTexture(CLOSE_TEXTURE)
            hl:SetAllPoints(btn)
            hl:SetTexCoord(unpack(CLOSE_TEXCOORDS.highlight))
            hl:SetBlendMode("ADD")
            btn:SetHighlightTexture(hl)
            btn._metalHighlight = hl

            btn._metalStyled = true
        end
        btn:SetSize(20, 20)
    elseif btn._metalStyled then
        -- Hide metal textures
        if btn._metalNormal then btn._metalNormal:SetAlpha(0) end
        if btn._metalPushed then btn._metalPushed:SetAlpha(0) end
        if btn._metalHighlight then btn._metalHighlight:SetAlpha(0) end

        -- Restore original textures
        if btn._origNormal then
            btn._origNormal:SetAlpha(1)
            btn:SetNormalTexture(btn._origNormal)
        end
        if btn._origPushed then
            btn._origPushed:SetAlpha(1)
            btn:SetPushedTexture(btn._origPushed)
        end
        if btn._origHighlight then
            btn._origHighlight:SetAlpha(1)
            btn:SetHighlightTexture(btn._origHighlight)
        end

        btn._metalStyled = false
    end
end

--- Public wrapper for StyleCloseButton
function Theme:StyleCloseButton(btn, useMetal)
    StyleCloseButton(btn, useMetal)
end

-- Flat theme close button: a plain "x" drawn as two thin lines, so it renders on
-- every client and in every font (a "×" glyph is missing from some CJK fonts).
local FLAT_CLOSE_COLOR = {0.75, 0.75, 0.75, 1}
local FLAT_CLOSE_HOVER = {1, 1, 1, 1}
local FLAT_CLOSE_INSET = 7

local function SetFlatCloseColor(btn, color)
    for _, line in ipairs(btn._flatLines) do
        line:SetColorTexture(color[1], color[2], color[3], color[4])
    end
end

local function StyleFlatCloseButton(btn, on)
    if on then
        if not btn.CreateLine then return end  -- no Line regions: keep the default button
        if not btn._flatLines then
            btn._flatLines = {}
            for i = 1, 2 do
                local line = btn:CreateLine(nil, "ARTWORK")
                line:SetThickness(1.5)
                btn._flatLines[i] = line
            end
            local a, b = btn._flatLines[1], btn._flatLines[2]
            a:SetStartPoint("TOPLEFT", btn, FLAT_CLOSE_INSET, -FLAT_CLOSE_INSET)
            a:SetEndPoint("BOTTOMRIGHT", btn, -FLAT_CLOSE_INSET, FLAT_CLOSE_INSET)
            b:SetStartPoint("TOPRIGHT", btn, -FLAT_CLOSE_INSET, -FLAT_CLOSE_INSET)
            b:SetEndPoint("BOTTOMLEFT", btn, FLAT_CLOSE_INSET, FLAT_CLOSE_INSET)
            -- Hooked, not set: the header's own OnEnter/OnLeave (tooltip) must keep working
            btn:HookScript("OnEnter", function(self)
                if self._flatStyled then SetFlatCloseColor(self, FLAT_CLOSE_HOVER) end
            end)
            btn:HookScript("OnLeave", function(self)
                if self._flatStyled then SetFlatCloseColor(self, FLAT_CLOSE_COLOR) end
            end)
        end
        if not btn._flatStyled then
            btn._flatOrig = {btn:GetNormalTexture(), btn:GetPushedTexture(), btn:GetHighlightTexture()}
            for _, tex in pairs(btn._flatOrig) do tex:SetAlpha(0) end
            btn._flatStyled = true
        end
        SetFlatCloseColor(btn, FLAT_CLOSE_COLOR)
        for _, line in ipairs(btn._flatLines) do line:Show() end
    elseif btn._flatStyled then
        for _, line in ipairs(btn._flatLines) do line:Hide() end
        for _, tex in pairs(btn._flatOrig) do tex:SetAlpha(1) end
        btn._flatOrig = nil
        btn._flatStyled = false
    end
end

local METAL_ICON_SIZE = 13
local METAL_ICON_BG_W = 21
local METAL_ICON_BG_H = 17

local function StyleButton(btn, useBlizzard, useMetal)
    if useMetal then
        btn:SetSize(METAL_ICON_SIZE, METAL_ICON_SIZE)
        local bg = EnsureIconBg(btn)
        bg:SetSize(METAL_ICON_BG_W, METAL_ICON_BG_H)
        bg:SetBackdropColor(0.15, 0.12, 0.10, 0.6)
        bg:SetBackdropBorderColor(0.45, 0.40, 0.35, 1)
        bg:Show()
    elseif useBlizzard then
        btn:SetSize(BLIZZARD_ICON_SIZE, BLIZZARD_ICON_SIZE)
        local bg = EnsureIconBg(btn)
        bg:SetSize(BLIZZARD_ICON_BG_W, BLIZZARD_ICON_BG_H)
        bg:SetBackdropColor(0.15, 0.12, 0.10, 0.6)
        bg:SetBackdropBorderColor(0.45, 0.40, 0.35, 1)
        bg:Show()
    else
        btn:SetSize(GUDA_ICON_SIZE, GUDA_ICON_SIZE)
        if btn.themeBg then btn.themeBg:Hide() end
    end
end

--- Apply the theme's title-bar chrome: backdrop + color, anchoring inside the
--- parent frame, close button size, and frame level above Blizzard/metal art.
--- Shared by the bag, bank, guild bank and mail headers (it used to be copied
--- into each one's SetBackdropAlpha).
--- @param headerFrame table The title bar frame (child of its window)
--- @param alpha number Background alpha for themes that draw a header backdrop
function Theme:ApplyHeaderChrome(headerFrame, alpha)
    local headerBackdrop = self:GetValue("headerBackdrop")
    if headerBackdrop then
        headerFrame:SetBackdrop(headerBackdrop)
        local headerBg = self:GetValue("headerBg")
        headerFrame:SetBackdropColor(headerBg[1], headerBg[2], headerBg[3], alpha)
        headerFrame:ClearAllPoints()
        headerFrame:SetPoint("TOPLEFT", headerFrame:GetParent(), "TOPLEFT", 4, -4)
        headerFrame:SetPoint("TOPRIGHT", headerFrame:GetParent(), "TOPRIGHT", -4, -4)
        if headerFrame.closeButton then headerFrame.closeButton:SetSize(22, 22) end
    else
        headerFrame:SetBackdrop(nil)
        headerFrame:ClearAllPoints()
        headerFrame:SetPoint("TOPLEFT", headerFrame:GetParent(), "TOPLEFT", 0, 1)
        headerFrame:SetPoint("TOPRIGHT", headerFrame:GetParent(), "TOPRIGHT", 4, 0)
        -- Art, not API: the 22px close button belongs to retail's own frame art.
        -- WoW: Forever is IsRetail on Vanilla art, so it takes the 32px one.
        local closeSize = ns.ExpansionFeatures.HasRetailFrameArt and 22 or 32
        if headerFrame.closeButton then headerFrame.closeButton:SetSize(closeSize, closeSize) end
        -- Raise header above blizzardBg's NineSlice or metalFrame overlay
        local parent = headerFrame:GetParent()
        if parent.blizzardBg or parent.metalFrame then
            headerFrame:SetFrameLevel(parent:GetFrameLevel() + ns.Constants.FRAME_LEVELS.HEADER)
        end
    end

    -- Optional 1px line under the title bar (Flat: the accent color). Follows the
    -- "show borders" setting like the window border does.
    local line = self:GetValue("headerLine")
    if line and Database:GetSetting("showBorders") ~= false then
        if not headerFrame._themeLine then
            local tex = headerFrame:CreateTexture(nil, "OVERLAY")
            tex:SetTexture("Interface\\Buttons\\WHITE8x8")
            tex:SetHeight(1)
            tex:SetPoint("BOTTOMLEFT", headerFrame, "BOTTOMLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", headerFrame, "BOTTOMRIGHT", 0, 0)
            headerFrame._themeLine = tex
        end
        headerFrame._themeLine:SetVertexColor(line[1], line[2], line[3], line[4] or 1)
        headerFrame._themeLine:Show()
    elseif headerFrame._themeLine then
        headerFrame._themeLine:Hide()
    end
end

--- Apply theme-appropriate styling and spacing to header icon buttons.
--- @param headerFrame table The title bar frame
--- @param leftButtons table Ordered array of left-side icon buttons (nil entries skipped)
--- @param rightButtons table Ordered array of right-side icon buttons after closeButton (nil entries skipped)
--- @param closeButton table The close button (anchor for right-side chain)
function Theme:ApplyHeaderButtons(headerFrame, leftButtons, rightButtons, closeButton)
    local useBlizzard = self:GetValue("useBlizzardFrame")
    local useMetal = self:GetValue("useMetalFrame")
    local gap = (useBlizzard or useMetal) and BLIZZARD_GAP or GUDA_GAP
    local firstLeftOffset = (useBlizzard or useMetal) and 13 or 4

    -- Style close button for metal / flat themes. Flat comes off BEFORE metal goes
    -- on (and goes on after metal comes off) so neither restores the other's
    -- hidden textures.
    if closeButton then
        local useFlatClose = self:GetValue("useFlatCloseButton")
        if not useFlatClose then StyleFlatCloseButton(closeButton, false) end
        StyleCloseButton(closeButton, useMetal)
        if useFlatClose then StyleFlatCloseButton(closeButton, true) end
    end

    -- Left side: first anchors to headerFrame LEFT, rest chain to previous
    local prevBtn = nil
    for _, btn in ipairs(leftButtons) do
        if btn then
            StyleButton(btn, useBlizzard, useMetal)
            btn:ClearAllPoints()
            if prevBtn then
                btn:SetPoint("LEFT", prevBtn, "RIGHT", gap, 0)
            else
                btn:SetPoint("LEFT", headerFrame, "LEFT", firstLeftOffset, 0)
            end
            prevBtn = btn
        end
    end

    -- Right side: chain from closeButton leftward
    prevBtn = closeButton
    for _, btn in ipairs(rightButtons) do
        if btn then
            StyleButton(btn, useBlizzard, useMetal)
            btn:ClearAllPoints()
            btn:SetPoint("RIGHT", prevBtn, "LEFT", -gap, 0)
            prevBtn = btn
        end
    end
end

-------------------------------------------------
-- Popup Chrome Helpers (shared by SettingsPopup & CategoryEditor)
-------------------------------------------------

--- Creates a BackdropTemplate child frame for the Guda theme (once per frame).
--- @param f table The popup frame
--- @return table The backdrop frame
function Theme:EnsureGudaBackdrop(f)
    if f._gudaBackdrop then return f._gudaBackdrop end
    local bg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bg:SetAllPoints()
    bg:SetFrameLevel(f:GetFrameLevel())
    bg:Hide()
    f._gudaBackdrop = bg
    return bg
end

--- Creates a retail-style red close button (once per frame).
--- @param f table The popup frame
--- @return table The close button
function Theme:EnsureRetailCloseButton(f)
    if f._retailCloseBtn then return f._retailCloseBtn end

    local btn = CreateFrame("Button", nil, f)
    btn:SetSize(20, 20)
    btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -3)
    btn:SetFrameLevel(f:GetFrameLevel() + 10)

    local normal = btn:CreateTexture(nil, "ARTWORK")
    normal:SetTexture(CLOSE_TEXTURE)
    normal:SetAllPoints()
    normal:SetTexCoord(unpack(CLOSE_TEXCOORDS.normal))
    btn:SetNormalTexture(normal)

    local pushed = btn:CreateTexture(nil, "ARTWORK")
    pushed:SetTexture(CLOSE_TEXTURE)
    pushed:SetAllPoints()
    pushed:SetTexCoord(unpack(CLOSE_TEXCOORDS.pushed))
    btn:SetPushedTexture(pushed)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(CLOSE_TEXTURE)
    hl:SetAllPoints()
    hl:SetTexCoord(unpack(CLOSE_TEXCOORDS.highlight))
    hl:SetBlendMode("ADD")
    btn:SetHighlightTexture(hl)

    btn:SetScript("OnClick", function() f:Hide() end)

    f._retailCloseBtn = btn
    return btn
end

--- Hides all chrome elements on a ButtonFrameTemplate popup.
--- @param f table The popup frame
function Theme:ResetPopupChrome(f)
    if f.Bg then f.Bg:Hide() end
    if f.TitleBg then f.TitleBg:Hide() end
    if f.TopTileStreaks then f.TopTileStreaks:Hide() end
    for _, key in ipairs(classicBorderKeys) do
        if f[key] then f[key]:Hide() end
    end
    if f.NineSlice then f.NineSlice:Hide() end
    if f.metalFrame then f.metalFrame:Hide() end
    if f._gudaBackdrop then f._gudaBackdrop:Hide() end
    if f.CloseButton then
        -- Art, not API: WoW: Forever is IsRetail on Vanilla art
        local closeSize = ns.ExpansionFeatures.HasRetailFrameArt and 22 or 32
        f.CloseButton:SetSize(closeSize, closeSize)
        f.CloseButton:Hide()
    end
    if f._retailCloseBtn then f._retailCloseBtn:Hide() end
end

--- Applies the current theme to a ButtonFrameTemplate popup frame.
--- @param f table The popup frame
function Theme:ApplyPopupTheme(f)
    if not f then return end
    local useMetal = self:GetValue("useMetalFrame")
    local useBlizzard = self:GetValue("useBlizzardFrame")

    self:ResetPopupChrome(f)

    if useMetal then
        self:ApplyFrameBackground(f, 1, true)
        local btn = self:EnsureRetailCloseButton(f)
        btn:ClearAllPoints()
        btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
        btn:Show()
    elseif useBlizzard then
        if f.Bg then f.Bg:Show() end
        if f.TitleBg then f.TitleBg:Show() end
        if f.TopTileStreaks then f.TopTileStreaks:Show() end
        for _, key in ipairs(classicBorderKeys) do
            if f[key] then f[key]:Show() end
        end
        if f.NineSlice then f.NineSlice:Show() end
        f.CloseButton:Show()
    else
        local gudaBg = self:EnsureGudaBackdrop(f)
        gudaBg:SetBackdrop(self:GetValue("backdrop"))
        local bg = self:GetValue("frameBg")
        gudaBg:SetBackdropColor(bg[1], bg[2], bg[3], 1)
        local border = self:GetValue("frameBorder")
        gudaBg:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
        gudaBg:Show()
        f.CloseButton:SetSize(22, 22)
        f.CloseButton:Show()
    end
end

-------------------------------------------------
-- Themed colors with call-site defaults
-------------------------------------------------
-- Most UI chrome (tabs, chips, dropdowns, footer buttons) was styled with literal
-- colors. Each literal now goes through Theme:Color(key, <the literal>): a theme
-- that defines `key` overrides it, every other theme gets the literal unchanged --
-- so the guda/blizzard/retail look stays exactly what it was.

--- @return number r, number g, number b, number a
function Theme:Color(key, r, g, b, a)
    local c = self:GetValue(key)
    if c then
        return c[1], c[2], c[3], c[4] or a or 1
    end
    return r, g, b, a or 1
end

-- Regions/frames painted once at creation, repainted when the theme changes.
-- Weak keys: a released or garbage-collected element just drops out.
local painted = setmetatable({}, { __mode = "k" })

--- A backdrop table, overridable by a theme that defines `key`.
function Theme:Backdrop(key, default)
    return self:GetValue(key) or default
end

local function PaintEntries(target)
    local entries = painted[target]
    if not entries then
        entries = {}
        painted[target] = entries
    end
    return entries
end

--- Apply a themed color now and again on every theme change.
--- Only for static colors -- a color that also changes with state (hover,
--- active) is set from Theme:Color in its handlers instead.
--- @param target table Frame or texture
--- @param method string "SetBackdropColor", "SetBackdropBorderColor", "SetVertexColor", "SetColorTexture" or "SetTextColor"
function Theme:Paint(target, method, key, r, g, b, a)
    PaintEntries(target)[method] = { key, r, g, b, a }
    target[method](target, self:Color(key, r, g, b, a))
end

--- Apply a themed backdrop now and again on every theme change.
--- Call before PaintBackdrop's colors: SetBackdrop resets them.
function Theme:PaintBackdrop(target, key, default)
    PaintEntries(target).backdrop = { key, default }
    target:SetBackdrop(self:Backdrop(key, default))
end

local function RepaintAll()
    for target, entries in pairs(painted) do
        -- Backdrop first: SetBackdrop resets the backdrop colors painted below
        local bd = entries.backdrop
        if bd then target:SetBackdrop(Theme:Backdrop(bd[1], bd[2])) end
        for method, e in pairs(entries) do
            if method ~= "backdrop" then
                target[method](target, Theme:Color(e[1], e[2], e[3], e[4], e[5]))
            end
        end
    end
end

-------------------------------------------------
-- Cache Invalidation
-------------------------------------------------
Events:Register("SETTING_CHANGED", function(event, key)
    if key == "theme" or key == "flatAccentColor" then
        cachedTheme = nil
        RepaintAll()
    end
end, Theme)

Events:Register("PROFILE_LOADED", function()
    cachedTheme = nil
    RepaintAll()
end, Theme)
