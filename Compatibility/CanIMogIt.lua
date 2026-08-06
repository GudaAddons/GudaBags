local addonName, ns = ...

-------------------------------------------------
-- CanIMogIt compatibility
-- Draws CanIMogIt's transmog overlay icon on GudaBags item buttons.
--
-- CanIMogIt has no generic button discovery: it walks Blizzard's own container
-- frame trees and otherwise ships one hand-written plugin per bag addon. Our
-- pooled buttons are in none of those trees, and its bag pass early-exits once
-- we replace the bag UI, so nothing appears unless we drive its overlay API
-- ourselves. That API is a handful of globals, so this lives here rather than
-- needing a change upstream. (Baganator integrates the same way, from its side.)
--
-- The key reliability points:
--   * probe EVERY global we call and pcall across the boundary -- a fork, an
--     older build or a failed SavedVariable must not throw from our render loop;
--   * only query for items that can actually have an appearance, so potions and
--     reagents never pay for a cold lookup;
--   * one overlay Frame per pooled button, created lazily and never in combat;
--   * clear CanIMogIt's 0.3s retry OnUpdate -- our GET_ITEM_INFO_RECEIVED
--     repaint already re-runs SetItem once item data lands, and hundreds of
--     polling buttons would breach Rule 2;
--   * cache only the bind-independent verdict, because the per-slot answer
--     varies with bind state and an itemLink key cannot express that.
-------------------------------------------------
local CIMI = {}
ns:RegisterModule("Compatibility.CanIMogIt", CIMI)

local Events = ns:GetModule("Events")
local Constants = ns.Constants

-- [itemLink] = unmodifiedText for the LINK-ONLY query. That answer ignores which
-- slot the item sits in, so it is stable per link and safe to memoise. The
-- per-slot query is deliberately NOT cached here: CanIMogIt returns different
-- verdicts for the same link depending on bind state (KNOWN vs KNOWN_BOE vs
-- KNOWN_WARBOUND), which an itemLink key cannot distinguish, and CanIMogIt keeps
-- its own bindData cache keyed by link+bag+slot anyway.
local linkVerdictCache = {}

-- CanIMogIt re-arms an OnUpdate whenever the text is nil. We hand it this
-- instead of a real updater and drop the script afterwards, so no pooled
-- button is left polling every frame.
local function noop() end

-- True when every CanIMogIt entry point this module calls is present. Probing
-- all of them (not just the two obvious ones) means a partial or forked install
-- degrades to "no icons" instead of erroring inside SetItem.
function CIMI:IsAvailable()
    return _G.CIMI_AddToFrame ~= nil
        and _G.CIMI_SetIcon ~= nil
        and _G.CIMI_CheckOverlayIconEnabled ~= nil
        and _G.CanIMogIt ~= nil
        and type(_G.CanIMogIt.GetTooltipText) == "function"
end

-- CanIMogIt's own master switch ("Show Bag Icons"). Wrapped because it indexes
-- its SavedVariable table with no nil guard of its own.
local function OverlayEnabled()
    local ok, enabled = pcall(_G.CIMI_CheckOverlayIconEnabled)
    return ok and enabled
end

-- Enum-probed so a flavor without these members degrades rather than errors.
local BATTLEPET_CLASS = Enum and Enum.ItemClass and Enum.ItemClass.Battlepet
local COMPANION_PET_SUBCLASS = Enum and Enum.ItemMiscellaneousSubclass
    and Enum.ItemMiscellaneousSubclass.CompanionPet

-- Items that can carry a collectible appearance. Mirrors the predicate
-- Baganator uses for the same integration -- notably this is NOT just weapons
-- and armor: toys, pets, mounts, decor and ensembles all have appearances, so
-- gating on equipment alone would silently hide icons on them.
-- [itemID] = true/false. Whether an item is gear/toy/mount/pet/decor/ensemble is
-- a static property of the item, so this never needs invalidating -- and without
-- it every consumable in the bag would pay three API calls on every refresh.
local collectibleCache = {}

local function ComputeCollectible(itemData, link, itemID)
    local classID = itemData.classID
    if classID == Constants.ITEM_CLASS.WEAPON or classID == Constants.ITEM_CLASS.ARMOR then
        return true
    end

    if C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemID) ~= nil then
        return true
    end
    if C_MountJournal and C_MountJournal.GetMountFromItem
        and C_MountJournal.GetMountFromItem(itemID) ~= nil then
        return true
    end
    if C_Item and C_Item.IsDecorItem and C_Item.IsDecorItem(itemID) then
        return true
    end
    -- Battle pets: a caged pet (its own item class, and a battlepet: link) or a
    -- companion-pet Miscellaneous item. Deliberately NOT all of Miscellaneous --
    -- that class is mostly junk with no appearance.
    if BATTLEPET_CLASS and classID == BATTLEPET_CLASS then return true end
    if COMPANION_PET_SUBCLASS and classID == Constants.ITEM_CLASS.MISCELLANEOUS
        and itemData.subClassID == COMPANION_PET_SUBCLASS then
        return true
    end
    if link:find("battlepet:", 1, true) then return true end
    if _G.CanIMogIt.IsItemEnsemble then
        local ok, isEnsemble = pcall(_G.CanIMogIt.IsItemEnsemble, _G.CanIMogIt, link)
        if ok and isEnsemble then return true end
    end

    return false
end

local function IsCollectible(itemData)
    local link = itemData.link or itemData.itemLink
    local itemID = itemData.itemID
    if not link or not itemID then return false end

    local cached = collectibleCache[itemID]
    if cached ~= nil then return cached end

    local result = ComputeCollectible(itemData, link, itemID)
    collectibleCache[itemID] = result
    return result
end

-- Raw call across the addon boundary. Returns the unmodified verdict text, or
-- nil when CanIMogIt has no answer yet (item data still loading) or threw.
local function QueryVerdict(link, bagID, slot)
    local ok, _, unmodifiedText
    if bagID and slot then
        ok, _, unmodifiedText = pcall(_G.CanIMogIt.GetTooltipText, _G.CanIMogIt, nil, bagID, slot)
    else
        ok, _, unmodifiedText = pcall(_G.CanIMogIt.GetTooltipText, _G.CanIMogIt, link)
    end
    if not ok then return nil end
    return unmodifiedText
end

-- The bind-independent verdict for an item, memoised per link. Used by the
-- search filter, which asks "is this appearance uncollected" -- a question whose
-- answer does not depend on which slot the item happens to occupy.
function CIMI:GetLinkVerdict(itemData)
    if not self:IsAvailable() or not itemData then return nil end
    local link = itemData.link or itemData.itemLink
    if not link or not IsCollectible(itemData) then return nil end

    local cached = linkVerdictCache[link]
    if cached ~= nil then return cached end

    local verdict = QueryVerdict(link, nil, nil)
    if verdict == nil then return nil end
    linkVerdictCache[link] = verdict
    return verdict
end

-- True when this item teaches an appearance the player has not collected.
-- Drives the "mog" search keyword and filter chip.
function CIMI:IsUnknownAppearance(itemData)
    if not self:IsAvailable() then return false end
    local unknown = _G.CanIMogIt.UNKNOWN
    if unknown == nil then return false end
    return self:GetLinkVerdict(itemData) == unknown
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
    if not OverlayEnabled() then
        self:Hide(button)
        return
    end

    local itemData = button.itemData
    if not itemData or not IsCollectible(itemData) then
        self:Hide(button)
        return
    end

    local overlay = button.CanIMogItOverlay
    if not overlay then
        -- CIMI_AddToFrame creates a Frame. Rule 2 forbids frame creation in
        -- paths that run after combat starts, and a single OptionUpdate can
        -- otherwise mass-create one per pooled button in one frame. Skip while
        -- locked down; the PLAYER_REGEN_ENABLED refresh below fills these in.
        if InCombatLockdown() then return end
        -- Anchors itself over the button and honours the user's iconLocation
        -- option. No-ops if an overlay already exists, so read the field back
        -- rather than trusting the return value.
        local ok = pcall(_G.CIMI_AddToFrame, button, noop, button:GetName())
        if not ok then return end
        overlay = button.CanIMogItOverlay
        if not overlay then return end
    end

    -- A child frame defaults to button+1, the same level as button.border.
    -- SyncFrameLevels only re-levels children it knows about, so re-assert.
    overlay:SetFrameLevel(button:GetFrameLevel() + Constants.FRAME_LEVELS.ADDON_OVERLAY)
    ScaleIcon(button, overlay)

    -- Live own-character slots resolve bind state, which selects between the
    -- KNOWN / KNOWN_BOE / KNOWN_WARBOUND icon variants -- so this path queries
    -- per slot and is not memoised. Read-only, cached-character and guild-bank
    -- views have no live slot to read, and fall back to the link verdict.
    local verdict
    local bagID, slot = itemData.bagID, itemData.slot
    local liveSlot = not itemData.isGuildBank and bagID and slot
        and C_Container.GetContainerItemLink(bagID, slot) == (itemData.link or itemData.itemLink)
    if liveSlot then
        verdict = QueryVerdict(nil, bagID, slot)
    else
        verdict = self:GetLinkVerdict(itemData)
    end

    -- CIMI_SetIcon is (frame, updater, text, unmodifiedText) and resolves the
    -- texture from unmodifiedText. We only ever hold the unmodified key, which
    -- is also non-empty exactly when an icon should show, so it serves as both.
    pcall(_G.CIMI_SetIcon, overlay, noop, verdict, verdict)

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
        wipe(linkVerdictCache)
        RefreshIcons()
    end

    -- CanIMogIt's own message bus: ResetCache fires when the collection
    -- changes, OptionUpdate when any of its options are toggled -- including
    -- the master icon switch this module honours. pcall'd because these run
    -- inside CanIMogIt's dispatch and must not break its other listeners.
    if type(_G.CanIMogIt.RegisterMessage) == "function" then
        local function SafeInvalidate() pcall(Invalidate) end
        _G.CanIMogIt:RegisterMessage("ResetCache", SafeInvalidate)
        _G.CanIMogIt:RegisterMessage("OptionUpdate", SafeInvalidate)
    end

    Events:Register("TRANSMOG_COLLECTION_UPDATED", Invalidate, CIMI)

    -- Overlay creation is skipped during combat; catch up once it ends so
    -- buttons drawn mid-fight still get their icon.
    Events:Register("PLAYER_REGEN_ENABLED", RefreshIcons, CIMI)
end, CIMI)
