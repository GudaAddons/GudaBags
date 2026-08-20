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
--   * cache ONLY whether a link has a track at all -- that is encoded in the
--     link's bonus IDs and never needs invalidating. The icon STRING must not be
--     cached: it also varies with IUQI's theme and hideOutOfSeasonIcons options,
--     which an itemLink key cannot express, so caching it would freeze a setting
--     in place until reload. It is recomputed on every paint instead;
--   * repaint when the settings panel closes. Every function in IUQI's own
--     settings->refresh chain is a file-local, so there is nothing inside it to
--     hook -- the panel closing is the only signal available from out here;
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

-- Whether IUQI participates in this item's button at all.
--
-- Public because ItemButton needs the same answer for a different reason: its
-- crafting-quality icon only adopts IUQI's placement on items IUQI could put an
-- icon on. A reagent or consumable has nothing to line up with, so it keeps our
-- own corner and sizing. One owner for the question, so "does IUQI draw here" and
-- "should we defer to IUQI's geometry here" can never disagree about the same
-- item.
function IUQI:AppliesTo(itemData)
    return itemData ~= nil and CanHaveTrack(itemData)
end

-- Whether this link has an upgrade track at all, memoised.
--
-- Deliberately NOT memoising GetIconForLink's answer, even though that would be
-- the tidier "ask IUQI for everything" shape: that function folds in IUQI's
-- hideOutOfSeasonIcons option and returns nil for a below-minimum-level item, so
-- caching it stores a setting under a key that only names the link. Turning the
-- option back off then cannot restore the icon, because the false is already
-- cached. The raw track presence is the part that really is static per link --
-- it lives in the link's bonus IDs -- so that is the only part cached here, and
-- the icon string itself is recomputed live on every paint.
local function HasTrack(link)
    local cached = hasTrackCache[link]
    if cached ~= nil then return cached end

    if not (C_Item and C_Item.GetItemUpgradeInfo) then return false end
    local ok, upgradeInfo = pcall(C_Item.GetItemUpgradeInfo, link)
    -- A failed call is not an answer -- don't memoise it, or one bad moment
    -- disables the icon for that item until reload.
    if not ok then return false end

    local result = upgradeInfo ~= nil and upgradeInfo.trackStringID ~= nil
    hasTrackCache[link] = result
    return result
end

-- IUQI's "no location" option. Its IconLocation clears all points and returns for
-- this value, leaving an unanchored FontString -- the user's off switch.
local IUQI_LOCATION_NONE = 10

-- IUQI renders its icon as an atlas escape inside a FontString and bakes the size
-- into the format string, so a pixel size has to be computed per call. It hardcodes
-- 18, which is wrong at both ends of our 22-64px icon slider; scale with the button
-- as craftingQualityIcon and the CanIMogIt overlay do. One owner, because our
-- crafting-quality icon is sized from this too when it follows IUQI's placement.
local ICON_SIZE_FACTOR = 0.42

local function IconSizeFor(baseSize)
    if not baseSize then return 16 end
    return math.max(8, math.floor(baseSize * ICON_SIZE_FACTOR))
end

-- Whether IUQI is drawing item-button icons at all right now.
--
-- Item-independent, unlike IsDecorating: this is the question "is IUQI the thing
-- placing quality dots in this UI", which decides whether our own crafting-quality
-- icon adopts IUQI's geometry or keeps its native top-left placement. With the
-- icons switched off there is nothing to line up with, so we go back to our own.
function IUQI:IconsEnabled()
    if not self:IsAvailable() then return false end
    if ns.suspectDisabled and ns.suspectDisabled.upgradetrack then return false end

    local db = _G.IUQI_DB
    return not (db and db.iconLocation == IUQI_LOCATION_NONE)
end

-- Place and size one of OUR regions the way IUQI places its own, so a bag does not
-- show quality dots in two different corners at two different sizes depending on
-- which addon happens to own each item's icon. Returns false if it could not, and
-- the caller keeps its native placement.
--
-- IconLocation is reused rather than reimplemented so the user's position and
-- offset sliders keep working for both. IconScale is NOT: it calls SetScale, which
-- textures do not have, so the scale slider is applied to the size instead. Both
-- are read through pcall -- IconLocation indexes IUQI_DB with no nil guard on some
-- paths, and this runs inside SetItem.
function IUQI:ApplyIconGeometry(region, button, baseSize)
    if not self:IconsEnabled() then return false end

    -- IUQI skips ClearAllPoints on its no-DB path, which would leave our existing
    -- anchor in place alongside the new one. The caller has already cleared.
    local ok = pcall(_G.IUQI_API.IconLocation, region, button)
    if not ok then return false end

    local db = _G.IUQI_DB
    local scale = tonumber(db and db.iconScale) or 1
    -- Same base size we hand IUQI's own icon, then its scale slider on top --
    -- IconScale would have applied that, but it calls SetScale, which textures
    -- do not have. This way the two match for different items in the same bag.
    local px = math.max(8, math.floor(IconSizeFor(baseSize) * scale))
    region:SetSize(px, px)
    return true
end

-- Whether IUQI is actually going to draw a track icon on THIS item.
--
-- Narrower than IconsEnabled, and the pair have to stay distinct: IconsEnabled
-- decides whether our crafting-quality icon adopts IUQI's geometry at all, while
-- this decides whether it has to stand down entirely because IUQI is about to put
-- its own icon on that exact spot. Gear with no upgrade track answers false here
-- and true there -- our icon moves to IUQI's position and still shows.
function IUQI:IsDecorating(itemData)
    if not self:IconsEnabled() then return false end
    if not self:AppliesTo(itemData) then return false end

    local link = itemData.link or itemData.itemLink
    return link ~= nil and HasTrack(link)
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
    -- IsDecorating is the single owner of "should there be a track icon here".
    -- ItemButton asks it the same question to decide whether its crafting-quality
    -- icon stands down, so the two can never disagree about what is on screen.
    local itemData = button.itemData
    if not self:IsDecorating(itemData) then
        self:Hide(button)
        return
    end

    local link = itemData.link or itemData.itemLink

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

    local ok, iconString = pcall(_G.IUQI_API.GetIconForLink, link, IconSizeFor(button.currentSize))
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

    -- Repaint after the user has been in the options.
    --
    -- IUQI wires Settings.SetOnValueChangedCallback to its file-local RefreshAll,
    -- which repaints Blizzard's container frames -- ours are not among them, and
    -- there is no seam inside IUQI to hook, since every function in that chain is
    -- a local. Registering our own callback for its variables would replace its,
    -- breaking its tooltip refresh. The settings panel closing is the one signal
    -- available from outside: one hook, no polling, and it covers changing an
    -- option and going back to the bags. The icon string is recomputed on every
    -- paint, so a repaint is all that is needed -- there is no cache to clear.
    local panel = _G.SettingsPanel
    if panel and panel.HookScript then
        panel:HookScript("OnHide", RefreshIcons)
    end

    -- Overlay creation is skipped during combat; catch up once it ends so buttons
    -- drawn mid-fight still get their icon.
    Events:Register("PLAYER_REGEN_ENABLED", RefreshIcons, IUQI)
end, IUQI)
