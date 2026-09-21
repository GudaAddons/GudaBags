-- GudaBags Compatibility API Layer
-- Provides API abstractions for cross-expansion compatibility

local addonName, ns = ...

local API = {}
ns:RegisterModule("Compatibility.API", API)

local Expansion = ns:GetModule("Expansion")

-------------------------------------------------
-- Container API Wrappers
-- Same API in both TBC and MoP, but wrapped for future-proofing
-------------------------------------------------

function API:GetContainerNumSlots(bagID)
    return C_Container.GetContainerNumSlots(bagID)
end

function API:GetContainerNumFreeSlots(bagID)
    return C_Container.GetContainerNumFreeSlots(bagID)
end

function API:GetContainerItemInfo(bagID, slot)
    return C_Container.GetContainerItemInfo(bagID, slot)
end

function API:GetContainerItemLink(bagID, slot)
    return C_Container.GetContainerItemLink(bagID, slot)
end

function API:PickupContainerItem(bagID, slot)
    return C_Container.PickupContainerItem(bagID, slot)
end

function API:SplitContainerItem(bagID, slot, amount)
    return C_Container.SplitContainerItem(bagID, slot, amount)
end

function API:UseContainerItem(bagID, slot)
    return C_Container.UseContainerItem(bagID, slot)
end

-------------------------------------------------
-- Relocated API resolution
--
-- WoW: Forever removed a swathe of legacy global functions. GetItemInfo,
-- GetItemSpell, GetItemQualityColor, GetCoinTextureString and others are nil
-- there; they exist only inside their modern namespace (C_Item, C_CurrencyInfo,
-- C_CVar, C_Spell, C_AddOns). Classic Era, TBC and MoP are the reverse -- they
-- ship the globals and only part of the namespaces. So neither source alone is
-- safe, and a bare global call is a guaranteed "attempt to call a nil value" on
-- Forever. That is exactly how this surfaced: an empty-bags crash in
-- ItemScanner, then a MERCHANT_SHOW crash on GetCoinTextureString.
--
-- Resolved once at load rather than per call, and exported on ns so hot paths
-- can cache a module-top local (Rule 2) instead of paying a GetModule lookup
-- per item. Every consumer just declares `local GetItemInfo = ns.GetItemInfo`
-- and its existing call sites keep working unchanged.
--
-- The global is preferred over the namespace deliberately: on the five flavors
-- that already shipped, this keeps calling exactly the function they call today,
-- so adding Forever support cannot quietly change what an existing user gets.
-- Only a client missing the global -- i.e. Forever -- takes the namespace branch.
--
-- Adding to this table is the fix for any further "attempt to call a nil value"
-- on a global; `/guda apicheck` names the ones a given client is missing.
-- (Core/Constants.lua resolves GetItemInfoInstant and GetItemClassInfo the same
-- way but inline, because it loads before this file.)
-------------------------------------------------

-- name -> the namespace that owns it on a modern client.
--
-- ONLY for names whose namespaced version takes the same arguments and returns
-- the same things as the global. A relocation that also changed shape must not go
-- in here -- aliasing it would turn a clean "nil value" error into wrong values,
-- which is far harder to spot. C_Spell.GetSpellCooldown is the example: it
-- returns one table where the global returned four values, so it is wrapped
-- explicitly below instead.
local RELOCATED = {
    GetItemInfo          = C_Item,
    GetItemInfoInstant   = C_Item,
    GetItemSpell         = C_Item,
    GetItemQualityColor  = C_Item,
    GetItemClassInfo     = C_Item,
    GetCoinTextureString = C_CurrencyInfo,
    GetCVar              = C_CVar,
    SetCVar              = C_CVar,
    IsAddOnLoaded        = C_AddOns,
}

-- Stable order for printing, so /guda status output is comparable between runs.
API.resolvedNames = {
    "GetItemInfo", "GetItemInfoInstant", "GetItemSpell", "GetItemQualityColor",
    "GetItemClassInfo", "GetCoinTextureString", "GetCVar", "SetCVar",
    "IsAddOnLoaded", "GetSpellCooldown",
}

-- Which source each name resolved from, for /guda status. A MISSING line here is
-- the single most useful thing in a bug report from a client nobody has tested.
API.resolvedSource = {}

for name, namespace in pairs(RELOCATED) do
    -- Exported on ns only, not on API: these are plain functions, and putting
    -- them on the module table invites an API:GetItemInfo(link) call that would
    -- silently pass the module as the first argument.
    ns[name] = _G[name] or (namespace and namespace[name]) or nil
    API.resolvedSource[name] = _G[name] and "global"
        or (namespace and namespace[name] and "namespace")
        or "MISSING"
end

-- GetSpellCooldown changed shape, not just location: the global returns
-- start, duration, enabled, modRate, while C_Spell.GetSpellCooldown returns a
-- single SpellCooldownInfo table. Normalised to the global's multiple returns so
-- the existing call site keeps reading `local start, duration = ...`.
if GetSpellCooldown then
    ns.GetSpellCooldown = GetSpellCooldown
    API.resolvedSource.GetSpellCooldown = "global"
elseif C_Spell and C_Spell.GetSpellCooldown then
    ns.GetSpellCooldown = function(spellID)
        local info = C_Spell.GetSpellCooldown(spellID)
        if not info then return nil end
        return info.startTime, info.duration, info.isEnabled, info.modRate
    end
    API.resolvedSource.GetSpellCooldown = "namespace (normalised)"
else
    API.resolvedSource.GetSpellCooldown = "MISSING"
end

-------------------------------------------------
-- Item Family/Bag Type API
-------------------------------------------------

function API:GetItemFamily(itemID)
    if not itemID then return 0 end
    return C_Item.GetItemFamily(itemID) or 0
end

-- Check if item can go in a specialized bag
function API:CanItemGoInBag(itemID, bagFamily)
    if bagFamily == 0 then return true end
    if not itemID then return false end

    local itemFamily = C_Item.GetItemFamily(itemID)
    if not itemFamily then return false end

    return bit.band(itemFamily, bagFamily) ~= 0
end

-------------------------------------------------
-- Expansion-specific bag family checks
-------------------------------------------------

-- Quiver bags (TBC only, family bit 1)
function API:IsQuiverBag(bagFamily)
    if not Expansion.Features.HasQuiverBags then return false end
    return bit.band(bagFamily or 0, 1) ~= 0
end

-- Ammo bags (TBC only, family bit 2)
function API:IsAmmoBag(bagFamily)
    if not Expansion.Features.HasAmmoBags then return false end
    return bit.band(bagFamily or 0, 2) ~= 0
end

-- Soul bags (both expansions, family bit 4)
function API:IsSoulBag(bagFamily)
    return bit.band(bagFamily or 0, 4) ~= 0
end

-- Gem bags (MoP+, family bit 512)
function API:IsGemBag(bagFamily)
    if not Expansion.Features.HasGemBags then return false end
    return bit.band(bagFamily or 0, 512) ~= 0
end

-- Inscription bags (MoP+, family bit 16)
function API:IsInscriptionBag(bagFamily)
    if not Expansion.Features.HasInscriptionBags then return false end
    return bit.band(bagFamily or 0, 16) ~= 0
end
