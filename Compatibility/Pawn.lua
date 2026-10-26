local addonName, ns = ...

-------------------------------------------------
-- Pawn compatibility
-- Decides whether an item should show an upgrade arrow
-- API/Pawn.lua. The key reliability points:
--   * call the UNBUDGETED Pawn function under our OWN compute budget, so we
--     don't fight Pawn's own default-bag hook for the shared global budget;
--   * cache per itemLink so a bag refresh doesn't recompute everything;
--   * resolve "not ready yet" (nil) via an OnUpdate drain, then refresh once;
--   * invalidate the cache when Pawn recalculates (spec/scale change), the
--     player levels up, or gear changes.
-------------------------------------------------
local Pawn = {}
ns:RegisterModule("Compatibility.Pawn", Pawn)

local Events = ns:GetModule("Events")

local upgradeCache = {}   -- [itemLink] = true/false
local pending = {}        -- [itemLink] = GetTime() it was first deferred

-- The drain runs every frame while anything is pending. An item whose data never
-- loads (or a Pawn that never reports ready) kept it running forever, so give up
-- on a link after this long and cache "no arrow" until the next invalidation.
local PENDING_MAX_AGE = 30

-- Same compute budget Pawn uses internally: 2 frames of 60fps worth of work
-- per quarter second. Spending our own keeps us off Pawn's shared budget.
local limit = 2 / 60 / 4
local resetInterval = 1 / 4
local timerResetsAt = 0
local left = 0

local ItemButton  -- resolved lazily to avoid load-order coupling
local function RefreshArrows()
    ItemButton = ItemButton or ns:GetModule("ItemButton")
    if ItemButton and ItemButton.RefreshUpgradeArrows then
        ItemButton:RefreshUpgradeArrows()
    end
end

-- Drains items still awaiting an answer (budget exhausted or item data not yet
-- cached), then refreshes the arrows once everything resolves.
local drainFrame = CreateFrame("Frame")
drainFrame:Hide()
drainFrame:SetScript("OnUpdate", function(self)
    local now = GetTime()
    for itemLink, since in pairs(pending) do
        if Pawn:GetUpgradeStatus(itemLink) ~= nil then
            pending[itemLink] = nil
        elseif now - since > PENDING_MAX_AGE then
            pending[itemLink] = nil
            upgradeCache[itemLink] = false
        end
    end
    if next(pending) == nil then
        self:Hide()
        RefreshArrows()
    end
end)

local function Defer(itemLink)
    -- Keep the first-deferred time: the drain re-defers the same link every frame
    pending[itemLink] = pending[itemLink] or GetTime()
    drainFrame:Show()
end

-- True when Pawn's upgrade API is present.
function Pawn:IsAvailable()
    return _G.PawnShouldItemLinkHaveUpgradeArrowUnbudgeted ~= nil
end

-- Returns true / false / nil (nil = not sure yet; a refresh will follow).
function Pawn:GetUpgradeStatus(itemLink)
    local cached = upgradeCache[itemLink]
    if cached ~= nil then return cached end

    -- Item data hasn't round-tripped from the server yet. Don't burn our budget
    -- (or Pawn's tooltip-scan budget) on a query that can't resolve; defer until
    -- the next drain tick, by which time GET_ITEM_INFO_RECEIVED may have landed.
    if C_Item and C_Item.IsItemDataCachedByID
        and not C_Item.IsItemDataCachedByID(itemLink) then
        Defer(itemLink)
        return nil
    end

    -- Querying before Pawn finishes initializing prints a Pawn chat error.
    if _G.PawnIsReady and not PawnIsReady() then
        Defer(itemLink)
        return nil
    end

    local start = GetTimePreciseSec()
    if start >= timerResetsAt then
        timerResetsAt = start + resetInterval
        left = limit
    elseif left <= 0 then
        Defer(itemLink)
        return nil
    end

    local result = PawnShouldItemLinkHaveUpgradeArrowUnbudgeted(itemLink, true)
    left = left - (GetTimePreciseSec() - start)

    if result ~= nil then
        upgradeCache[itemLink] = result
        return result
    end

    -- Item data is loaded but Pawn still says nil -> treat as not-an-upgrade so
    -- it doesn't stay unresolved forever.
    if not (C_Item and C_Item.IsItemDataCachedByID) or C_Item.IsItemDataCachedByID(itemLink) then
        upgradeCache[itemLink] = false
        return false
    end

    Defer(itemLink)
    return nil
end

-- Set up invalidation once everything is loaded (Pawn may load after us).
Events:OnPlayerLogin(function()
    if not Pawn:IsAvailable() then return end

    local function Invalidate()
        wipe(upgradeCache)
        RefreshArrows()
    end

    -- Pawn recalculates best items on spec change and resets tooltips when its
    -- settings/scales change.
    if _G.PawnInvalidateBestItems then hooksecurefunc("PawnInvalidateBestItems", Invalidate) end
    if _G.PawnResetTooltips then hooksecurefunc("PawnResetTooltips", Invalidate) end

    Events:Register("PLAYER_LEVEL_UP", Invalidate, Pawn)
    Events:Register("PLAYER_EQUIPMENT_CHANGED", Invalidate, Pawn)
end, Pawn)
