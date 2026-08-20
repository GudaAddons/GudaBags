local addonName, ns = ...

-------------------------------------------------
-- Item Upgrade Quality Icons compatibility
-- Draws IUQI's upgrade-track icon (Explorer .. Myth) on GudaBags item buttons.
--
-- IUQI decorates bag slots by walking Blizzard's container frames -- it iterates
-- ContainerFrameUtil_GetShownFrameForID(bagID) and calls EnumerateValidItems on
-- what it finds. GudaBags replaces the bag UI outright and overrides OpenAllBags /
-- OpenBag / OpenBackpack, so those frames are never shown, the lookup returns nil
-- for every bag, and its bag pass finds nothing to decorate. Its tooltip icons are
-- unaffected; only the slot icons go missing. The same shape of problem, and the
-- same remedy, as Compatibility/CanIMogIt.lua.
--
-- IUQI publishes IUQI_API for exactly this, so this lives here rather than
-- needing a change upstream.
--
-- The key reliability points:
--   * probe EVERY entry point we call and pcall across the boundary -- IconScale
--     indexes IUQI_DB with no nil guard of its own, so a fresh install or a fork
--     must not throw from inside SetItem;
--   * honour IUQI's own position/scale/theme options rather than adding a second
--     set -- its "no location" option (10) is already the user's off switch;
--   * gate on gear before asking: only equippable items carry an upgrade track,
--     so nothing else pays for a lookup;
--   * cache only whether a link has a track at all. That is encoded in the link's
--     bonus IDs and so never needs invalidating, while the icon STRING also varies
--     with IUQI's theme options -- which are not hookable, because its settings
--     callback captures a file-local RefreshAll rather than IUQI_API.RefreshAll.
--     Recomputing the string live for the few gear pieces in a bag keeps a theme
--     change instant with no invalidation story to get wrong;
--   * one overlay Frame per pooled button, created lazily and never in combat.
-------------------------------------------------
local IUQI = {}
ns:RegisterModule("Compatibility.ItemUpgradeQualityIcons", IUQI)

local Events = ns:GetModule("Events")
local Constants = ns.Constants
local ITEM_CLASS = Constants.ITEM_CLASS

-- [itemLink] = true/false. Whether the item has an upgrade track at all. The
-- track and its level live in the link's bonus IDs, so the link names everything
-- this answer varies by and the entry never goes stale.
local hasTrackCache = {}

-- True when every IUQI entry point this module calls is present. Probing all of
-- them (not just the obvious one) means a partial or forked install degrades to
-- "no icons" instead of erroring inside SetItem.
function IUQI:IsAvailable()
    local api = _G.IUQI_API
    return api ~= nil
        and type(api.GetIconForLink) == "function"
        and type(api.IconLocation) == "function"
        and type(api.IconScale) == "function"
end

-- Only equippable gear carries an upgrade track, and that IS the whole set here --
-- unlike a transmog lookup, there is no toy/mount/pet tail to miss.
local function CanHaveTrack(itemData)
    local classID = itemData.classID
    return classID == ITEM_CLASS.WEAPON or classID == ITEM_CLASS.ARMOR
end

-- Whether this link has a track, memoised. Asking IUQI rather than calling
-- C_Item.GetItemUpgradeInfo ourselves keeps one owner for the question, so we
-- cannot drift from what its tooltip shows.
local function HasTrack(link)
    local cached = hasTrackCache[link]
    if cached ~= nil then return cached end

    local ok, iconString = pcall(_G.IUQI_API.GetIconForLink, link, 16)
    -- A failed call is not an answer -- don't memoise it, or one bad moment
    -- disables the icon for that item until reload.
    if not ok then return false end

    local result = iconString ~= nil
    hasTrackCache[link] = result
    return result
end

-- IUQI renders its icon as an atlas escape inside a FontString and sizes it in
-- the format string, so the size has to be baked in per call. It hardcodes 18,
-- which is wrong at both ends of our 22-64px icon slider; scale with the button
-- as craftingQualityIcon and the CanIMogIt overlay do.
local function IconSizeFor(button)
    local size = button.currentSize
    if not size then return 16 end
    return math.max(8, math.floor(size * 0.42))
end

-- Clear the icon without destroying the overlay, so the pooled button keeps it
-- for reuse. Safe on buttons that never got one.
function IUQI:Hide(button)
    local overlay = button and button.GudaIUQIOverlay
    if not overlay then return end
    overlay.text:SetText("")
end

-- Apply or clear the upgrade-track icon for the button's current item.
function IUQI:Decorate(button)
    if not self:IsAvailable() then return end
    if ns.suspectDisabled and ns.suspectDisabled.upgradetrack then
        self:Hide(button)
        return
    end

    local itemData = button.itemData
    if not itemData or not CanHaveTrack(itemData) then
        self:Hide(button)
        return
    end

    local link = itemData.link or itemData.itemLink
    if not link or not HasTrack(link) then
        self:Hide(button)
        return
    end

    local overlay = button.GudaIUQIOverlay
    if not overlay then
        -- Rule 2 forbids frame creation in paths that run after combat starts,
        -- and one refresh would otherwise create one per pooled button in a
        -- single frame. Skip while locked down; the PLAYER_REGEN_ENABLED repaint
        -- below fills these in.
        if InCombatLockdown() then return end
        overlay = CreateFrame("Frame", nil, button)
        overlay:SetAllPoints(button)
        overlay.text = overlay:CreateFontString(nil, "OVERLAY", "GameTooltipText")
        button.GudaIUQIOverlay = overlay
    end

    -- A child frame defaults to button+1, the same level as button.border.
    -- SyncFrameLevels only re-levels children it knows about, so re-assert.
    overlay:SetFrameLevel(button:GetFrameLevel() + Constants.FRAME_LEVELS.ADDON_OVERLAY)

    local ok, iconString = pcall(_G.IUQI_API.GetIconForLink, link, IconSizeFor(button))
    if not ok or not iconString then
        overlay.text:SetText("")
        return
    end

    overlay.text:SetText(iconString)
    -- Position and scale come from the user's own IUQI options; GudaBags
    -- deliberately adds no second set. IconLocation clears all points and returns
    -- when the user picks "no location" (10), which leaves an unanchored, unshown
    -- FontString -- exactly the intended "off".
    pcall(_G.IUQI_API.IconLocation, overlay.text, button)
    pcall(_G.IUQI_API.IconScale, overlay.text)
end

local ItemButton  -- resolved lazily to avoid load-order coupling
local function RefreshIcons()
    ItemButton = ItemButton or ns:GetModule("ItemButton")
    if ItemButton and ItemButton.RefreshUpgradeTrackIcons then
        ItemButton:RefreshUpgradeTrackIcons()
    end
end

-- Set up invalidation once everything is loaded (IUQI may load after us).
Events:OnPlayerLogin(function()
    if not IUQI:IsAvailable() then return end

    -- IUQI's own settings handler calls a file-local RefreshAll, not this field,
    -- so wrapping it does not catch a user changing options -- it catches another
    -- addon asking IUQI to repaint everything, which would otherwise skip our
    -- buttons for the same reason its bag pass does.
    local api = _G.IUQI_API
    if type(api.RefreshAll) == "function" then
        local originalRefreshAll = api.RefreshAll
        api.RefreshAll = function(...)
            pcall(originalRefreshAll, ...)
            RefreshIcons()
        end
    end

    -- Overlay creation is skipped during combat; catch up once it ends so buttons
    -- drawn mid-fight still get their icon.
    Events:Register("PLAYER_REGEN_ENABLED", RefreshIcons, IUQI)
end, IUQI)
