local addonName, ns = ...

-------------------------------------------------
-- CanIMogIt compatibility
-- Draws CanIMogIt's transmog overlay icon on GudaBags item buttons.
--
-- CanIMogIt has no generic button discovery: it walks Blizzard's own container
-- frame trees and otherwise ships one hand-written plugin per bag addon. Our
-- pooled buttons are in none of those trees, and its bag pass early-exits once
-- we replace the bag UI, so nothing appears unless we drive its overlay API
-- ourselves. That API is four plain globals, so this lives here rather than
-- needing a change upstream.
--
-- The key reliability points:
--   * duck-type the globals -- CanIMogIt is retail-only and may load after us;
--   * one overlay Frame per pooled button, created lazily and reused forever;
--   * clear CanIMogIt's 0.3s retry OnUpdate -- our GET_ITEM_INFO_RECEIVED
--     repaint already re-runs SetItem once item data lands, and hundreds of
--     polling buttons would breach Rule 2;
--   * cache the verdict per itemLink so repaint passes and the search filter
--     don't recompute, and invalidate when the collection or options change.
-------------------------------------------------
local CIMI = {}
ns:RegisterModule("Compatibility.CanIMogIt", CIMI)

local Events = ns:GetModule("Events")
local Constants = ns.Constants

-- [itemLink] = unmodifiedText, the key CanIMogIt looks its icons up by.
-- "" is a real value (item has no appearance to report) and is cached too.
local textCache = {}

-- CanIMogIt re-arms an OnUpdate whenever the text is nil. We hand it this
-- instead of a real updater and drop the script afterwards, so no pooled
-- button is left polling every frame.
local function noop() end

-- True when CanIMogIt's overlay API is present.
function CIMI:IsAvailable()
    return _G.CIMI_AddToFrame ~= nil and _G.CIMI_SetIcon ~= nil
end

-- The appearance verdict for an item, as CanIMogIt's own lookup key
-- (CanIMogIt.KNOWN, .UNKNOWN, ...). Returns nil while item data is still
-- loading -- callers must read that as "no answer yet", not "not collectable".
function CIMI:GetAppearanceKey(itemData)
    if not self:IsAvailable() or not itemData then return nil end
    local link = itemData.link or itemData.itemLink
    if not link then return nil end

    local cached = textCache[link]
    if cached ~= nil then return cached end

    -- GetTooltipText discards the itemLink argument whenever bag AND slot are
    -- both passed, re-reading the link out of the live container instead. That
    -- is the better answer for a real slot (it resolves bind state), but wrong
    -- for anything cached -- another character's bank, the guild bank, a bank
    -- viewed while away -- where those coordinates address our own bags.
    -- Confirming the slot still holds this exact link settles it here rather
    -- than making every caller track whether its view is read-only.
    local _, unmodifiedText
    local bagID, slot = itemData.bagID, itemData.slot
    local liveSlot = not itemData.isGuildBank and bagID and slot
        and C_Container.GetContainerItemLink(bagID, slot) == link

    if liveSlot then
        _, unmodifiedText = CanIMogIt:GetTooltipText(nil, bagID, slot)
    else
        _, unmodifiedText = CanIMogIt:GetTooltipText(link)
    end

    if unmodifiedText == nil then return nil end
    textCache[link] = unmodifiedText
    return unmodifiedText
end

-- True when this item teaches an appearance the player has not collected.
-- Drives the "mog" search keyword and filter chip.
function CIMI:IsUnknownAppearance(itemData)
    if not self:IsAvailable() or not CanIMogIt.UNKNOWN then return false end
    return self:GetAppearanceKey(itemData) == CanIMogIt.UNKNOWN
end

-- CanIMogIt hardcodes its icon at 13x13, which is lost at the top of our
-- icon-size slider. Scale with the button, as craftingQualityIcon does.
local function ScaleIcon(button, overlay)
    local size = button.currentSize
    if not size or not overlay.CIMIIconTexture then return end
    local iconSize = math.max(10, math.floor(size * 0.35))
    overlay.CIMIIconTexture:SetSize(iconSize, iconSize)
end

-- Clear the icon without destroying the overlay, so the pooled button keeps it
-- for reuse. Safe on buttons that never got an overlay.
function CIMI:Hide(button)
    local overlay = button and button.CanIMogItOverlay
    if not overlay then return end
    overlay:SetScript("OnUpdate", nil)
    if overlay.CIMIIconTexture then
        overlay.CIMIIconTexture:SetShown(false)
    end
end

-- Apply or clear the transmog icon for the button's current item.
function CIMI:Decorate(button)
    if not self:IsAvailable() then return end

    -- CanIMogIt's own "Show Bag Icons" switch is the single source of truth;
    -- GudaBags deliberately adds no second toggle.
    if not CIMI_CheckOverlayIconEnabled() then
        self:Hide(button)
        return
    end

    local itemData = button.itemData
    if not itemData or not (itemData.link or itemData.itemLink) then
        self:Hide(button)
        return
    end

    local overlay = button.CanIMogItOverlay
    if not overlay then
        -- Anchors itself over the button and honours the user's iconLocation
        -- option. No-ops if an overlay already exists, so read the field back
        -- rather than trusting the return value.
        CIMI_AddToFrame(button, noop, button:GetName())
        overlay = button.CanIMogItOverlay
        if not overlay then return end
    end

    -- A child frame defaults to button+1, the same level as button.border.
    -- SyncFrameLevels only re-levels children it knows about, so re-assert.
    overlay:SetFrameLevel(button:GetFrameLevel() + Constants.FRAME_LEVELS.QUEST_ICON + 1)
    ScaleIcon(button, overlay)

    -- CIMI_SetIcon is (frame, updater, text, unmodifiedText) and resolves the
    -- texture from unmodifiedText. We only ever hold the unmodified key, which
    -- is also non-empty exactly when an icon should show, so it serves as both.
    local key = self:GetAppearanceKey(itemData)
    CIMI_SetIcon(overlay, noop, key, key)

    -- Drop whatever retry CIMI_SetIcon just armed (Rule 2: no per-frame polling).
    overlay:SetScript("OnUpdate", nil)
end

local ItemButton  -- resolved lazily to avoid load-order coupling
local function RefreshIcons()
    ItemButton = ItemButton or ns:GetModule("ItemButton")
    if ItemButton and ItemButton.RefreshTransmogIcons then
        ItemButton:RefreshTransmogIcons()
    end
end

-- Set up invalidation once everything is loaded (CanIMogIt may load after us).
Events:OnPlayerLogin(function()
    if not CIMI:IsAvailable() then return end

    local function Invalidate()
        wipe(textCache)
        RefreshIcons()
    end

    -- CanIMogIt's own message bus: ResetCache fires when the collection
    -- changes, OptionUpdate when any of its options are toggled -- including
    -- the master icon switch this module honours.
    if CanIMogIt and CanIMogIt.RegisterMessage then
        CanIMogIt:RegisterMessage("ResetCache", Invalidate)
        CanIMogIt:RegisterMessage("OptionUpdate", Invalidate)
    end

    Events:Register("TRANSMOG_COLLECTION_UPDATED", Invalidate, CIMI)
end, CIMI)
