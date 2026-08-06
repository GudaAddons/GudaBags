local addonName, ns = ...

local TooltipScanner = {}
ns:RegisterModule("TooltipScanner", TooltipScanner)

-- Numeric item classes: itemType/itemSubType from GetItemInfo are localized
local ITEM_CLASS = ns.Constants.ITEM_CLASS

-------------------------------------------------
-- Tooltip Management
-------------------------------------------------

local scanningTooltip = nil
local TOOLTIP_NAME = "GudaBagsScanningTooltip"

function TooltipScanner:GetTooltip()
    if not scanningTooltip then
        scanningTooltip = CreateFrame("GameTooltip", TOOLTIP_NAME, nil, "GameTooltipTemplate")
        scanningTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    return scanningTooltip
end

function TooltipScanner:SetBagItem(bagID, slotID)
    if not bagID or not slotID then return false end

    local tooltip = self:GetTooltip()
    tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tooltip:ClearLines()

    if bagID == -1 then
        -- BANK_CONTAINER's 28 main slots use inventory slot IDs, not bag/slot.
        -- tooltip:SetBagItem(-1, slot) does not reliably return per-slot data
        -- (e.g. "X Charges") in Classic. Mirrors UI/Tooltip.lua:208-219.
        local invSlot = BankButtonIDToInvSlotID and BankButtonIDToInvSlotID(slotID)
        if invSlot then
            tooltip:SetInventoryItem("player", invSlot)
        end
    else
        tooltip:SetBagItem(bagID, slotID)
    end

    return tooltip:NumLines() and tooltip:NumLines() > 0
end

function TooltipScanner:SetHyperlink(link)
    if not link then return false end

    local tooltip = self:GetTooltip()
    tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    tooltip:ClearLines()
    tooltip:SetHyperlink(link)

    return tooltip:NumLines() and tooltip:NumLines() > 0
end

-------------------------------------------------
-- Line Access
-------------------------------------------------

function TooltipScanner:GetLineText(lineNumber)
    local tooltip = self:GetTooltip()
    local leftText = _G[TOOLTIP_NAME .. "TextLeft" .. lineNumber]

    if leftText and leftText:IsShown() then
        return leftText:GetText()
    end
    return nil
end

function TooltipScanner:GetNumLines()
    local tooltip = self:GetTooltip()
    return tooltip:NumLines() or 0
end

-------------------------------------------------
-- Scanning Functions
-------------------------------------------------

-- Scan tooltip lines and call callback for each line
-- callback(lineNumber, text) - return true to stop scanning
function TooltipScanner:ScanLines(callback, maxLines)
    local numLines = self:GetNumLines()
    if not numLines or numLines == 0 then return nil end

    maxLines = maxLines or numLines

    for i = 1, math.min(numLines, maxLines) do
        local text = self:GetLineText(i)
        if text then
            local result = callback(i, text)
            if result then
                return result
            end
        end
    end

    return nil
end

-- Find first matching pattern in tooltip
-- Returns: matchedPattern, fullText, lineNumber
function TooltipScanner:FindText(patterns, maxLines)
    if type(patterns) == "string" then
        patterns = {patterns}
    end

    local result = nil
    self:ScanLines(function(lineNum, text)
        for _, pattern in ipairs(patterns) do
            if text:find(pattern) then
                result = {pattern = pattern, text = text, line = lineNum}
                return true
            end
        end
    end, maxLines)

    return result
end

-- Check if any pattern exists in tooltip
function TooltipScanner:HasText(patterns, maxLines)
    return self:FindText(patterns, maxLines) ~= nil
end

-------------------------------------------------
-- Common Item Checks
-------------------------------------------------

-------------------------------------------------
-- Bind detection (shared by IsBindOnEquip / IsWarbound / GetBindTag)
-------------------------------------------------

local HEIRLOOM_QUALITY = 7

-- Tooltip binding lines, resolved once at load.
--
-- Global names differ per flavor and several do not exist at all on older
-- clients, so each list is filtered down to what this client actually defines.
-- Comparing against a global that does not exist silently matches nothing --
-- which is precisely how IsWarbound shipped broken for years. Building sets also
-- keeps the per-line check O(1) and removes the English string literals that
-- were dead weight on 10 of the 11 supported locales.
local function BuildTextSet(names)
    local set = {}
    for _, name in ipairs(names) do
        local text = _G[name]
        if type(text) == "string" and text ~= "" then
            set[text] = true
        end
    end
    return set
end

local ACCOUNT_BOUND_TEXTS = BuildTextSet({
    "ITEM_ACCOUNTBOUND_UNTIL_EQUIP",    -- "Warbound until equipped" (11.0+)
    "ITEM_BIND_TO_ACCOUNT_UNTIL_EQUIP",
    "ITEM_ACCOUNTBOUND",                -- "Account Bound"
    "ITEM_BNETACCOUNTBOUND",            -- "Blizzard Account Bound"
    "ITEM_BIND_TO_ACCOUNT",             -- "Binds to account"
    "ITEM_BIND_TO_BNETACCOUNT",         -- "Binds to Blizzard account"
})

local BIND_ON_EQUIP_TEXTS = BuildTextSet({
    "ITEM_BIND_ON_EQUIP",               -- "Binds when equipped"
})

-- Already bound to this character: neither a BoE nor a BoA label applies.
local ALREADY_BOUND_TEXTS = BuildTextSet({
    "ITEM_SOULBOUND",                   -- "Soulbound"
    "ITEM_BIND_ON_PICKUP",              -- "Binds when picked up"
})

-- Retail-only live check for "Warbound until equipped" (Enum.ItemBind
-- ToBnetAccountUntilEquipped). One reusable ItemLocation is created here and
-- re-pointed per call: CreateFromBagAndSlot would allocate a table for every
-- gear slot on every render pass (Rule 2).
local IsBoundToAccountUntilEquip = C_Item and C_Item.IsBoundToAccountUntilEquip
local DoesItemExist = C_Item and C_Item.DoesItemExist
local scratchItemLocation = nil
if IsBoundToAccountUntilEquip and DoesItemExist
    and ItemLocation and ItemLocation.CreateFromBagAndSlot then
    scratchItemLocation = ItemLocation:CreateFromBagAndSlot(0, 1)
    if not scratchItemLocation.SetBagAndSlot then
        scratchItemLocation = nil
    end
end

-- Check if item is Bind on Equip.
--
-- Thin wrapper over GetBindTag, which is the single bind detector: BoE and BoA
-- can never disagree, and whichever caller asks first pays for the one scan.
function TooltipScanner:IsBindOnEquip(bagID, slotID, itemData)
    return self:GetBindTag(bagID, slotID, itemData) == "boe"
end

-- Check if item is account bound: "Warbound until equipped", heirlooms, or a
-- plain BoA item. Drives the built-in Warbound category.
--
-- Deliberately has no weapon/armor gate, unlike GetBindTag -- account-bound
-- mounts, pets and toys belong in that category too.
--
-- This previously tested ITEM_BNET_ACCOUNTBOUND_UNTIL_EQUIP and
-- ITEM_BNET_ACCOUNTBOUND, neither of which is a real global (the real name has
-- no underscore after BNET), and never tested the "Warbound until equipped"
-- string at all -- so the category silently missed every warbound item.
function TooltipScanner:IsWarbound(bagID, slotID)
    if not bagID or not slotID then return false end

    if not self:SetBagItem(bagID, slotID) then
        return false
    end

    local isWarbound = false
    self:ScanLines(function(lineNum, text)
        -- Bound to this character already: not account bound.
        if ALREADY_BOUND_TEXTS[text] then
            isWarbound = false
            return true
        end
        if ACCOUNT_BOUND_TEXTS[text] then
            isWarbound = true
            return true
        end
    end, 6)

    return isWarbound
end

-- Bind tag for a slot: "boa" (account bound), "boe" (bind on equip), or nil.
--
-- The two labels share one fontstring on the item button and are mutually
-- exclusive, so they are resolved together — and, on the fallback path, with a
-- single tooltip render rather than one per tag. Order is cheapest-first: the
-- heirloom shortcut and the account-bound API both answer without touching the
-- tooltip at all.
function TooltipScanner:GetBindTag(bagID, slotID, itemData)
    if not bagID or not slotID then return nil end

    -- Only weapons and armor carry these bindings.
    -- Keyed on classID: itemType is localized, so comparing it to "Weapon"/"Armor"
    -- would reject every item on a non-English client.
    if itemData and itemData.classID
        and itemData.classID ~= ITEM_CLASS.WEAPON
        and itemData.classID ~= ITEM_CLASS.ARMOR then
        return nil
    end

    -- Heirlooms are account bound by definition — no scan needed.
    if itemData and itemData.quality == HEIRLOOM_QUALITY then
        return "boa"
    end

    -- This is a live check, not the item's static bindType, so a
    -- Warbound-until-equipped piece that has since been equipped (and is
    -- therefore soulbound now) correctly reports false.
    if scratchItemLocation then
        scratchItemLocation:SetBagAndSlot(bagID, slotID)
        if DoesItemExist(scratchItemLocation)
            and IsBoundToAccountUntilEquip(scratchItemLocation) then
            return "boa"
        end
    end

    if not self:SetBagItem(bagID, slotID) then
        return nil
    end

    -- One pass over the binding block at the top of the tooltip.
    local tag = nil
    self:ScanLines(function(lineNum, text)
        if ACCOUNT_BOUND_TEXTS[text] then
            tag = "boa"
            return true
        end
        if BIND_ON_EQUIP_TEXTS[text] then
            tag = "boe"
            return true
        end
        if ALREADY_BOUND_TEXTS[text] then
            return true
        end
    end, 6)

    return tag
end

-- Get consumable restore type (eat/drink/restore)
function TooltipScanner:GetRestoreTag(bagID, slotID, itemData)
    if not bagID or not slotID then return nil end

    -- Only consumables have restore tags (classID, not the localized itemType)
    if itemData and itemData.classID and itemData.classID ~= ITEM_CLASS.CONSUMABLE then
        return nil
    end

    if not self:SetBagItem(bagID, slotID) then
        return nil
    end

    local hasHealth = false
    local hasMana = false
    local hasRestores = false
    local mustRemainSeated = false

    self:ScanLines(function(lineNum, text)
        local textLower = text:lower()

        if textLower:find("use: restores") or textLower:find("use: regenerates") then
            hasRestores = true
            if textLower:find("health") then hasHealth = true end
            if textLower:find("mana") then hasMana = true end
        end

        -- Buff food: "eating" or "well fed" implies food
        if textLower:find("eating") or textLower:find("well fed") then
            hasHealth = true
        end
        -- Buff drink: "drinking" implies drink
        if textLower:find("drinking") then
            hasMana = true
        end

        if textLower:find("must remain seated") then
            mustRemainSeated = true
        end
    end)

    if mustRemainSeated then
        if hasHealth and hasMana then
            return "restore"
        elseif hasHealth then
            return "eat"
        elseif hasMana then
            return "drink"
        end
    end

    return nil
end

-- Check if item has special properties (Use:, Equip:, Chance on hit)
function TooltipScanner:HasSpecialProperties(bagID, slotID)
    if not bagID or not slotID then return false end

    if not self:SetBagItem(bagID, slotID) then
        return false
    end

    return self:HasText({"Use:", "Equip:", "Chance on hit"})
end

-------------------------------------------------
-- Charges (Wizard Oil, Sharpening Stones, etc.)
-------------------------------------------------

-- Per-slot cache: charges depend on slot state (uses deplete a charge), not on the link.
-- Value = number (charges remaining), false (scanned, no charges), nil (not scanned yet)
local chargesCache = {}

function TooltipScanner:GetCharges(bagID, slotID)
    if not bagID or not slotID then return nil end
    local key = bagID * 1000 + slotID
    local cached = chargesCache[key]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    if not self:SetBagItem(bagID, slotID) then
        return nil  -- tooltip not ready; don't poison cache
    end

    local charges = nil
    self:ScanLines(function(lineNum, text)
        local _, _, num = string.find(text:lower(), "^(%d+) charges?$")
        if num then
            charges = tonumber(num)
            return true
        end
    end, 10)

    chargesCache[key] = charges or false
    return charges
end

function TooltipScanner:InvalidateCharges(bagID)
    if bagID then
        local lo = bagID * 1000
        local hi = lo + 999
        for key in pairs(chargesCache) do
            if key >= lo and key <= hi then
                chargesCache[key] = nil
            end
        end
    else
        chargesCache = {}
    end
end

local Events = ns:GetModule("Events")
if Events then
    Events:Register("BAG_UPDATE", function(event, bagID)
        TooltipScanner:InvalidateCharges(bagID)
    end, "TooltipScanner_Charges")

    -- Applying oils, sharpening stones, scrolls, etc. fires UNIT_SPELLCAST_SUCCEEDED
    -- but does NOT reliably fire BAG_UPDATE in Classic — the slot's itemID and
    -- stackCount are unchanged, only the embedded charge count decremented.
    Events:Register("UNIT_SPELLCAST_SUCCEEDED", function(event, unit)
        if unit ~= "player" then return end
        TooltipScanner:InvalidateCharges()
    end, "TooltipScanner_Charges_Cast")
end
