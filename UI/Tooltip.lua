local addonName, ns = ...

local Tooltip = {}
ns:RegisterModule("Tooltip", Tooltip)

local L = ns.L
local Database = ns:GetModule("Database")
local Events = ns:GetModule("Events")
local Utils = ns:GetModule("Utils")

-- Tooltips we are allowed to write into: the ones a player actually reads.
--
-- Everything else is a hidden scanning tooltip (ours, Pawn's, CanIMogIt's, or
-- any other addon's), which nobody sees and which would cost a full count pass.
-- ShoppingTooltip1/2 ARE included -- the comparison tooltips get counts too, via
-- the deliberate SetCompareItem hooks further down.
--
-- Resolved by name so a tooltip missing on a given flavor (GameTooltipTooltip on
-- Classic Era/TBC) is simply absent. The same set drives the OnTooltipCleared
-- hooks below, so the two can't drift apart.
local ALLOWED_TOOLTIP_NAMES = {
    "GameTooltip",
    "ItemRefTooltip",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "GameTooltipTooltip",
}

local allowedTooltips = {}
for _, name in ipairs(ALLOWED_TOOLTIP_NAMES) do
    local tooltip = _G[name]
    if tooltip then
        allowedTooltips[tooltip] = true
    end
end

local function IsAllowedTooltip(tooltip)
    if not tooltip then return false end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return false end
    return allowedTooltips[tooltip] == true
end

-- Duplicate suppression is PER TOOLTIP. This is the actual retail bug fix.
--
-- It used to be one module-wide boolean. On retail the item hook is
-- TooltipDataProcessor.AddTooltipPostCall, which fires for every tooltip built
-- from the data API. Hovering equippable gear in bags is exactly when Blizzard
-- builds ShoppingTooltip1/2 for the equipped piece, nested inside the same
-- SetBagItem call -- and its compare handler is registered at load, before our
-- PLAYER_LOGIN registration, so the comparison tooltip was served first. It
-- consumed the single flag, and the bag item's own tooltip then aborted. That is
-- why retail showed counts only on equipped items while Classic (whose hook is
-- bound to GameTooltip alone) was fine.
--
-- With the flag living on the tooltip itself, no tooltip can consume another's
-- turn, and both the item and its comparison get their section. Set only after a
-- section is actually drawn, and cleared by that tooltip's own OnTooltipCleared.
local INVENTORY_DRAWN = "gudaBagsInventoryDrawn"
local CURRENCY_DRAWN = "gudaBagsCurrencyDrawn"

-- Tooltip for scanning item properties (hidden, used for data extraction)
local scanTooltip = CreateFrame("GameTooltip", "GudaBags_ScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

-- Custom tooltip for items (avoids secure frame conflicts with ContainerFrameItemButtonTemplate)
local itemTooltip = CreateFrame("GameTooltip", "GudaBags_ItemTooltip", UIParent, "GameTooltipTemplate")
itemTooltip:SetFrameStrata("TOOLTIP")

-- Extract itemID from item link
local function GetItemIDFromLink(link)
    if not link then return nil end
    local itemID = link:match("item:(%d+)")
    return itemID and tonumber(itemID)
end

-- Add inventory section to a tooltip
local function AddInventorySection(tooltip, itemID, skipReadyCheck)
    if not itemID then return end

    if not IsAllowedTooltip(tooltip) then return end

    -- Prevent duplicate inventory sections on same tooltip (unless skipReadyCheck for specific hooks)
    if not skipReadyCheck and tooltip[INVENTORY_DRAWN] then return end

    if Database:GetSetting("showTooltipCounts") == false then return end

    local totalCount, characterCounts, warbandCount, guildBankCounts = Database:CountItemAcrossCharacters(itemID)

    -- Don't show if no items found
    if totalCount == 0 then return end

    -- Marked only now: a call that draws nothing must not claim the tooltip.
    -- (The old code set the flag up front, so a zero-count pass blocked the
    -- real one.)
    tooltip[INVENTORY_DRAWN] = true

    tooltip:AddLine(" ")
    tooltip:AddLine(L["TOOLTIP_INVENTORY"], 1, 0.82, 0)

    local youSuffix = L["TOOLTIP_YOU"] or " (you)"
    local labelBags = L["TOOLTIP_BAGS"] or "Bags"
    local labelBank = L["TOOLTIP_BANK_LOWER"] or "Bank"
    local labelMail = L["TOOLTIP_MAIL_LOWER"] or "Mail"
    local labelEquipped = L["TOOLTIP_EQUIPPED"] or "Equipped"

    for _, charInfo in ipairs(characterCounts) do
        local classColor = RAID_CLASS_COLORS[charInfo.class]
        local r, g, b = 0.7, 0.7, 0.7
        if classColor then
            r, g, b = classColor.r, classColor.g, classColor.b
        end

        local raceIcon = Utils:GetRaceIcon(charInfo.race, charInfo.sex) or ""
        local charName = charInfo.name or "?"
        local displayName = raceIcon .. " " .. (charInfo.isCurrent and (charName .. youSuffix) or charName)

        -- Build count string with label: count format
        local cyan = "|cFF00CCCC"
        local white = "|cFFFFFFFF"
        local countParts = {}
        if charInfo.bagCount and charInfo.bagCount > 0 then
            table.insert(countParts, cyan .. labelBags .. ": " .. white .. charInfo.bagCount .. "|r")
        end
        if charInfo.bankCount and charInfo.bankCount > 0 then
            table.insert(countParts, cyan .. labelBank .. ": " .. white .. charInfo.bankCount .. "|r")
        end
        if charInfo.mailCount and charInfo.mailCount > 0 then
            table.insert(countParts, cyan .. labelMail .. ": " .. white .. charInfo.mailCount .. "|r")
        end
        if charInfo.equippedCount and charInfo.equippedCount > 0 then
            table.insert(countParts, cyan .. labelEquipped .. ": " .. white .. charInfo.equippedCount .. "|r")
        end
        local countStr = table.concat(countParts, white .. ", ")

        tooltip:AddDoubleLine(displayName, countStr, r, g, b, 1, 1, 1)
    end

    -- Show warband bank as a separate line (account-wide, not per-character)
    if warbandCount > 0 then
        tooltip:AddDoubleLine(L["TOOLTIP_WARBAND_BANK"], warbandCount, 0.0, 0.8, 0.6, 1, 0.82, 0)
    end

    -- Show guild bank(s) as separate line(s) (account-wide, shared per guild)
    local guildBankLines = 0
    if guildBankCounts then
        for _, gb in ipairs(guildBankCounts) do
            tooltip:AddDoubleLine(L["TOOLTIP_GUILD_BANK"] .. ": " .. gb.guildName, gb.count, 0.0, 0.8, 0.6, 1, 0.82, 0)
            guildBankLines = guildBankLines + 1
        end
    end

    if #characterCounts > 1 or warbandCount > 0 or guildBankLines > 0 then
        tooltip:AddDoubleLine(L["TOOLTIP_TOTAL"], totalCount, 0.8, 0.8, 0.8, 1, 0.82, 0)
    end

    tooltip:Show()
end

-- Extract currencyID from a currency link (|Hcurrency:1166:...|h[name]|h)
local function GetCurrencyIDFromLink(link)
    if not link then return nil end
    local id = link:match("currency:(%d+)")
    return id and tonumber(id)
end

-- Add an "Owned by" section listing this currency's quantity per character.
local function AddCurrencySection(tooltip, currencyID, skipReadyCheck)
    if not currencyID then return end

    if not IsAllowedTooltip(tooltip) then return end

    -- Prevent duplicate sections on the same tooltip (unless an explicit caller skips it)
    if not skipReadyCheck and tooltip[CURRENCY_DRAWN] then return end

    if Database:GetSetting("showTooltipCounts") == false then return end

    local totalCount, characterCounts = Database:CountCurrencyAcrossCharacters(currencyID)
    if totalCount == 0 then return end

    tooltip[CURRENCY_DRAWN] = true

    tooltip:AddLine(" ")
    tooltip:AddLine(L["TOOLTIP_CURRENCY_HEADER"], 1, 0.82, 0)

    local youSuffix = L["TOOLTIP_YOU"] or " (you)"
    for _, charInfo in ipairs(characterCounts) do
        local classColor = RAID_CLASS_COLORS[charInfo.class]
        local r, g, b = 0.7, 0.7, 0.7
        if classColor then
            r, g, b = classColor.r, classColor.g, classColor.b
        end

        local raceIcon = Utils:GetRaceIcon(charInfo.race, charInfo.sex) or ""
        local charName = charInfo.name or "?"
        local displayName = raceIcon .. " " .. (charInfo.isCurrent and (charName .. youSuffix) or charName)

        tooltip:AddDoubleLine(displayName, BreakUpLargeNumbers(charInfo.quantity), r, g, b, 1, 1, 1)
    end

    if #characterCounts > 1 then
        tooltip:AddDoubleLine(L["TOOLTIP_TOTAL"], BreakUpLargeNumbers(totalCount), 0.8, 0.8, 0.8, 1, 0.82, 0)
    end

    tooltip:Show()
end

-- Clear the drawn flags when a tooltip is reset, so the next item shown in it
-- gets our sections again. Every whitelisted tooltip needs its own hook --
-- previously only GameTooltip was hooked, so any other tooltip that consumed
-- the shared flag never released it.
do
    local function ClearDrawnFlags(self)
        self[INVENTORY_DRAWN] = nil
        self[CURRENCY_DRAWN] = nil
    end

    for tooltip in pairs(allowedTooltips) do
        if tooltip.HookScript then
            tooltip:HookScript("OnTooltipCleared", ClearDrawnFlags)
        end
    end
end

-- Bank bag IDs as a numeric set, built once. Membership is checked per tooltip,
-- so a hash lookup beats re-walking three arrays every time.
--
-- The ranges genuinely cannot be shared between flavors: bag 5 is a BANK bag on
-- Classic/TBC but the carried REAGENT BAG on retail (Constants.BAG_IDS is
-- {0..5} there). The previous "5 to 12 covers both" shortcut therefore reported
-- every retail reagent-bag item as sitting in the bank. Constants already
-- resolves this correctly per flavor, and it is safe to read here: Expansion
-- loads 2nd and Constants 3rd in the TOC, both long before any UI file.
local bankSlotSet
local function GetBankSlotSet()
    if bankSlotSet then return bankSlotSet end

    local Constants = ns.Constants
    bankSlotSet = {}

    -- The main bank container exists on every flavor, and is seeded explicitly:
    -- on modern retail BANK_BAG_IDS is built purely from CharacterBankTab_*
    -- indices and does NOT contain -1.
    bankSlotSet[(Constants and Constants.BANK_MAIN_BAG) or -1] = true

    -- Flavor-correct bank bag range, or the retail character bank tabs.
    if Constants and Constants.BANK_BAG_IDS then
        for _, bagID in ipairs(Constants.BANK_BAG_IDS) do
            bankSlotSet[bagID] = true
        end
    end

    if Constants then
        for _, listName in ipairs({"WARBAND_BANK_TAB_IDS", "CHARACTER_BANK_TAB_IDS"}) do
            local list = Constants[listName]
            if list then
                for _, bagID in ipairs(list) do
                    bankSlotSet[bagID] = true
                end
            end
        end
    end

    return bankSlotSet
end

-- Returns true if bagID belongs to the bank (main bank container, bank bags, or
-- retail Warband/Character bank tabs). Single source of truth so the tooltip
-- driver (UI/ItemButton.lua OnEnter) and ShowForItem agree on what a bank slot is.
function Tooltip:IsBankSlot(bagID)
    if bagID == nil then return false end
    return GetBankSlotSet()[bagID] == true
end

-- Show tooltip for an item button (uses GameTooltip for addon compatibility)
function Tooltip:ShowForItem(button)
    if not button.itemData then return end

    -- We are about to repopulate GameTooltip for a different item, so clear the
    -- drawn flags: SetOwner alone does not always fire OnTooltipCleared.
    GameTooltip[INVENTORY_DRAWN] = nil
    GameTooltip[CURRENCY_DRAWN] = nil

    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")

    local bagID = button.itemData.bagID
    local slot = button.itemData.slot
    local link = button.itemData.link or button.itemData.itemLink
    local itemID = button.itemData.itemID
    local isKeyring = bagID == -2
    local isGuildBank = button.itemData.isGuildBank

    -- Check if this is a bank item (main bank container, bank bags, or retail bank tabs)
    local isBankItem = self:IsBankSlot(bagID)

    if isGuildBank then
        -- Guild bank items - use SetGuildBankItem if at bank, otherwise hyperlink
        local GuildBankScanner = ns:GetModule("GuildBankScanner")
        local tooltipSet = false
        if GuildBankScanner and GuildBankScanner:IsGuildBankOpen() and GameTooltip.SetGuildBankItem then
            GameTooltip:SetGuildBankItem(bagID, slot)  -- bagID is tab index for guild bank
            tooltipSet = GameTooltip:NumLines() and GameTooltip:NumLines() > 0
        end
        if not tooltipSet and link then
            GameTooltip:SetHyperlink(link)
            tooltipSet = GameTooltip:NumLines() and GameTooltip:NumLines() > 0
        end
        if not tooltipSet and itemID then
            GameTooltip:SetHyperlink("item:" .. itemID)
            tooltipSet = GameTooltip:NumLines() and GameTooltip:NumLines() > 0
        end
        if not tooltipSet and button.itemData then
            local name = button.itemData.name
            local quality = button.itemData.quality or 0
            if name and name ~= "" then
                local r, g, b = GetItemQualityColor(quality)
                GameTooltip:SetText(name, r, g, b)
            end
        end
    elseif button.isReadOnly or isKeyring then
        -- Cached items and keyring use hyperlink
        local tooltipSet = false
        if link then
            GameTooltip:SetHyperlink(link)
            tooltipSet = GameTooltip:NumLines() and GameTooltip:NumLines() > 0
        end
        -- Fallback 1: try SetItemByID if available
        if not tooltipSet and itemID and GameTooltip.SetItemByID then
            GameTooltip:SetItemByID(itemID)
            tooltipSet = GameTooltip:NumLines() and GameTooltip:NumLines() > 0
        end
        -- Fallback 2: construct link from itemID
        if not tooltipSet and itemID then
            GameTooltip:SetHyperlink("item:" .. itemID)
            tooltipSet = GameTooltip:NumLines() and GameTooltip:NumLines() > 0
        end
        -- Fallback 3: manually show item name and icon
        if not tooltipSet and button.itemData then
            local name = button.itemData.name
            local quality = button.itemData.quality or 0
            if name and name ~= "" then
                local r, g, b = GetItemQualityColor(quality)
                GameTooltip:SetText(name, r, g, b)
            end
        end
    elseif isBankItem then
        -- Bank items handling
        local BankScanner = ns:GetModule("BankScanner")
        local isBankOpen = BankScanner and BankScanner:IsBankOpen()
        local tooltipSet = false

        if isBankOpen and bagID ~= nil and slot then
            if bagID == -1 then
                -- Main bank container uses inventory slots, not bag slots
                local invSlot = BankButtonIDToInvSlotID and BankButtonIDToInvSlotID(slot)
                if invSlot then
                    GameTooltip:SetInventoryItem("player", invSlot)
                    tooltipSet = GameTooltip:NumLines() and GameTooltip:NumLines() > 0
                end
            else
                -- Bank bags (5-11) use SetBagItem like regular bags
                GameTooltip:SetBagItem(bagID, slot)
                tooltipSet = GameTooltip:NumLines() and GameTooltip:NumLines() > 0
            end
        end
        -- Fallback to hyperlink if direct access didn't work
        if not tooltipSet and link then
            GameTooltip:SetHyperlink(link)
            tooltipSet = GameTooltip:NumLines() and GameTooltip:NumLines() > 0
        end
        -- Fallback to itemID
        if not tooltipSet and itemID then
            if GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(itemID)
                tooltipSet = GameTooltip:NumLines() and GameTooltip:NumLines() > 0
            end
            if not tooltipSet then
                GameTooltip:SetHyperlink("item:" .. itemID)
                tooltipSet = GameTooltip:NumLines() and GameTooltip:NumLines() > 0
            end
        end
        -- Last resort: show item name
        if not tooltipSet and button.itemData then
            local name = button.itemData.name
            local quality = button.itemData.quality or 0
            if name and name ~= "" then
                local r, g, b = GetItemQualityColor(quality)
                GameTooltip:SetText(name, r, g, b)
            end
        end
    else
        -- Regular bag items use bag slot for full info (binding, cooldown, etc.)
        local tooltipSet = false
        if bagID ~= nil and slot then
            GameTooltip:SetBagItem(bagID, slot)
            tooltipSet = GameTooltip:NumLines() and GameTooltip:NumLines() > 0
        end
        if not tooltipSet and link then
            GameTooltip:SetHyperlink(link)
            tooltipSet = GameTooltip:NumLines() and GameTooltip:NumLines() > 0
        end
        -- Fallback to itemID
        if not tooltipSet and itemID then
            if GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(itemID)
                tooltipSet = GameTooltip:NumLines() and GameTooltip:NumLines() > 0
            end
            if not tooltipSet then
                GameTooltip:SetHyperlink("item:" .. itemID)
            end
        end
    end

    -- Add inventory section
    AddInventorySection(GameTooltip, button.itemData.itemID)

    -- Add tracking hint for bag items (not read-only/cached)
    Tooltip:AddTrackHint(button)

    GameTooltip:Show()
end

-- Append the track/untrack hint for a real (non-read-only) bag item. Shared so
-- the Blizzard-driven tooltip path (UI/ItemButton.lua OnEnter, where Blizzard's
-- secure handler owns the tooltip) can add the hint without re-driving SetBagItem.
function Tooltip:AddTrackHint(button)
    if button.isReadOnly or not (button.itemData and button.itemData.itemID) then return end
    local TrackedBar = ns:GetModule("TrackedBar")
    if not TrackedBar then return end
    GameTooltip:AddLine(" ")
    if TrackedBar:IsTracked(button.itemData.itemID) then
        GameTooltip:AddLine(L["HINT_UNTRACK"], 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine(L["HINT_TRACK"], 0.7, 0.7, 0.7)
    end

    -- The bulk mail shortcut is only actionable at an open mailbox, so only hint
    -- there rather than advertising it on every tooltip.
    local MailBulkSend = ns:GetModule("MailBulkSend")
    if MailBulkSend and MailBulkSend:CanStart() then
        GameTooltip:AddLine(L["HINT_MAIL_BULK"], 0.7, 0.7, 0.7)
    end
end

-- Hide the item tooltip
function Tooltip:Hide()
    GameTooltip:Hide()
end

-- Public function to add inventory section to any tooltip
function Tooltip:AddInventorySection(tooltip, itemID)
    AddInventorySection(tooltip, itemID)
end

-- Public function to add the cross-character currency section to any tooltip.
-- skipReadyCheck is for callers that build the tooltip themselves (e.g. the footer
-- currency token) where no Set*Currency hook fires to gate duplicates.
function Tooltip:AddCurrencySection(tooltip, currencyID, skipReadyCheck)
    AddCurrencySection(tooltip, currencyID, skipReadyCheck)
end

-- Helper to create a hook that adds inventory section
local function HookWithInventory(method, getLinkFunc)
    if not GameTooltip[method] then return end

    hooksecurefunc(GameTooltip, method, function(self, ...)
        local success, link = pcall(getLinkFunc, ...)
        if success and link then
            AddInventorySection(self, GetItemIDFromLink(link))
        end
    end)
end

-- Initialize GameTooltip hooks
local function InitializeHooks()
    -- General OnTooltipSetItem hook - catches most item tooltips
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        -- Retail/modern approach
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            if not data or not data.id then return end
            -- Skip tooltips built with lines excluded -- those are addon scans
            -- (ours, Pawn's, CanIMogIt's), not anything the player looks at.
            -- Some odd tooltips lack processingInfo entirely; skip those too.
            local info = tooltip.processingInfo
            if not info or info.excludeLines then return end
            AddInventorySection(tooltip, data.id)
        end)
    else
        -- Classic/TBC approach - use OnTooltipSetItem script
        GameTooltip:HookScript("OnTooltipSetItem", function(self)
            local _, link = self:GetItem()
            if link then
                AddInventorySection(self, GetItemIDFromLink(link))
            end
        end)
    end

    -- Hook SetHyperlink for chat links (items and currencies)
    hooksecurefunc(GameTooltip, "SetHyperlink", function(self, link)
        if not link then return end
        if link:match("^item:") then
            AddInventorySection(self, GetItemIDFromLink(link))
        elseif link:match("currency:") then
            AddCurrencySection(self, GetCurrencyIDFromLink(link))
        end
    end)

    -- Hook SetBagItem for bag tooltips (other addons using GameTooltip)
    hooksecurefunc(GameTooltip, "SetBagItem", function(self, bagID, slot)
        local link = C_Container.GetContainerItemLink(bagID, slot)
        if link then
            AddInventorySection(self, GetItemIDFromLink(link))
        end
    end)

    -- Hook SetAuctionItem for auction house (OnTooltipSetItem doesn't fire for this)
    if GameTooltip.SetAuctionItem then
        hooksecurefunc(GameTooltip, "SetAuctionItem", function(self, auctionType, index)
            local link = GetAuctionItemLink(auctionType, index)
            if link then
                AddInventorySection(self, GetItemIDFromLink(link), true)
            end
        end)
    end

    -- Hook SetCraftItem for enchanting/crafting professions (OnTooltipSetItem doesn't fire for this)
    if GameTooltip.SetCraftItem then
        hooksecurefunc(GameTooltip, "SetCraftItem", function(self, recipeIndex, reagentIndex)
            local link
            if reagentIndex then
                link = GetCraftReagentItemLink(recipeIndex, reagentIndex)
            else
                link = GetCraftItemLink(recipeIndex)
            end
            if link then
                AddInventorySection(self, GetItemIDFromLink(link), true)
            end
        end)
    end

    -- Hook SetTradeSkillItem for professions (OnTooltipSetItem doesn't fire for this)
    if GameTooltip.SetTradeSkillItem then
        hooksecurefunc(GameTooltip, "SetTradeSkillItem", function(self, recipeIndex, reagentIndex)
            local link
            if reagentIndex then
                link = GetTradeSkillReagentItemLink(recipeIndex, reagentIndex)
            else
                link = GetTradeSkillItemLink(recipeIndex)
            end
            if link then
                AddInventorySection(self, GetItemIDFromLink(link), true)
            end
        end)
    end

    -- Hook SetInboxItem for mail
    HookWithInventory("SetInboxItem", function(mailIndex, attachmentIndex)
        return GetInboxItemLink(mailIndex, attachmentIndex or 1)
    end)

    -- Hook SetMerchantItem for vendors
    HookWithInventory("SetMerchantItem", GetMerchantItemLink)

    -- Hook SetTradePlayerItem and SetTradeTargetItem for trade window
    HookWithInventory("SetTradePlayerItem", GetTradePlayerItemLink)
    HookWithInventory("SetTradeTargetItem", GetTradeTargetItemLink)

    -- Hook SetLootItem for loot window
    HookWithInventory("SetLootItem", GetLootSlotLink)

    -- Hook SetQuestItem for quest rewards
    HookWithInventory("SetQuestItem", function(questType, index)
        return GetQuestItemLink(questType, index)
    end)

    -- Hook SetQuestLogItem for quest log items
    HookWithInventory("SetQuestLogItem", function(itemType, index)
        return GetQuestLogItemLink(itemType, index)
    end)

    -- Hook SetInventoryItem for equipped items and bank
    HookWithInventory("SetInventoryItem", function(unit, slot)
        return GetInventoryItemLink(unit, slot)
    end)

    -- Hook SetGuildBankItem for guild bank
    if GameTooltip.SetGuildBankItem then
        HookWithInventory("SetGuildBankItem", function(tab, slot)
            return GetGuildBankItemLink(tab, slot)
        end)
    end

    -- Hook SetSendMailItem for mail attachments when composing
    if GameTooltip.SetSendMailItem then
        HookWithInventory("SetSendMailItem", function(index)
            local name, itemID = GetSendMailItem(index)
            if itemID then
                return select(2, GetItemInfo(itemID))  -- Get item link from itemID
            end
            return nil
        end)
    end

    -- Hook SetItemByID for items shown by ID (some UI elements)
    if GameTooltip.SetItemByID then
        hooksecurefunc(GameTooltip, "SetItemByID", function(self, itemID)
            if itemID then
                AddInventorySection(self, itemID)
            end
        end)
    end

    -- Currency tooltips (cross-character "Owned by" section). Retail routes through
    -- the tooltip data processor; MoP/Classic use the SetCurrency* methods.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Currency then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Currency, function(tooltip, data)
            if not data or not data.id then return end
            -- Same scan-tooltip skip as the item post-call above.
            local info = tooltip.processingInfo
            if not info or info.excludeLines then return end
            AddCurrencySection(tooltip, data.id)
        end)
    end

    -- SetCurrencyToken: the Currency tab list (index into the currency list)
    if GameTooltip.SetCurrencyToken then
        hooksecurefunc(GameTooltip, "SetCurrencyToken", function(self, index)
            local getLink = (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListLink) or GetCurrencyListLink
            if getLink then
                AddCurrencySection(self, GetCurrencyIDFromLink(getLink(index)))
            end
        end)
    end

    -- SetCurrencyByID: currencies shown directly by id
    if GameTooltip.SetCurrencyByID then
        hooksecurefunc(GameTooltip, "SetCurrencyByID", function(self, currencyID)
            AddCurrencySection(self, currencyID)
        end)
    end
end

-- Hook secondary tooltips (ItemRefTooltip for chat links, ShoppingTooltips for comparison)
local function InitializeSecondaryTooltipHooks()
    -- ItemRefTooltip - shown when clicking item links in chat
    if ItemRefTooltip and ItemRefTooltip.SetHyperlink then
        hooksecurefunc(ItemRefTooltip, "SetHyperlink", function(self, link)
            if link and link:match("^item:") then
                AddInventorySection(self, GetItemIDFromLink(link))
            end
        end)
    end

    -- ShoppingTooltip1 and ShoppingTooltip2 - comparison tooltips
    for i = 1, 2 do
        local shoppingTooltip = _G["ShoppingTooltip" .. i]
        if shoppingTooltip and shoppingTooltip.SetCompareItem then
            hooksecurefunc(shoppingTooltip, "SetCompareItem", function(self, ...)
                local _, link = self:GetItem()
                if link then
                    AddInventorySection(self, GetItemIDFromLink(link))
                end
            end)
        end
    end
end

-- Initialize hooks on player login (or immediately if already logged in)
local hooksInitialized = false
local function SafeInitializeHooks()
    if hooksInitialized then return end
    hooksInitialized = true
    InitializeHooks()
    InitializeSecondaryTooltipHooks()
end

Events:OnPlayerLogin(SafeInitializeHooks, Tooltip)

if IsLoggedIn() then
    SafeInitializeHooks()
end

-------------------------------------------------
-- Tooltip Scanning API (for junk detection, etc.)
-------------------------------------------------

-- Scan tooltip for item properties (returns scan tooltip for reading)
function Tooltip:ScanBagItem(bagID, slot)
    if not bagID or not slot then
        return nil, 0
    end

    scanTooltip:ClearLines()
    scanTooltip:SetBagItem(bagID, slot)

    return scanTooltip, scanTooltip:NumLines() or 0
end

-- Get a specific line from the scan tooltip
function Tooltip:GetScanLine(lineIndex)
    local line = _G["GudaBags_ScanTooltipTextLeft" .. lineIndex]
    if not line then
        return nil, nil, nil, nil
    end

    return line:GetText(), line:GetTextColor()
end

-- Check if item has special properties (Use:, Equip:, Unique, green/yellow text)
function Tooltip:HasSpecialProperties(bagID, slot)
    local _, numLines = self:ScanBagItem(bagID, slot)
    if numLines == 0 then return false end

    for i = 1, numLines do
        local text, r, g, b = self:GetScanLine(i)

        if text then
            local textLower = text:lower()

            -- Check for Use: or Equip: effects
            if textLower:find("use:") or textLower:find("equip:") then
                return true
            end

            -- Check for Unique items
            if textLower:find("^unique") or textLower:find("unique%-equipped") then
                return true
            end
        end

        if r and g and b then
            -- Green text (special effects, set bonuses)
            if g > 0.9 and r < 0.2 and b < 0.2 then
                return true
            end

            -- Yellow/gold text (flavor text, special properties) - skip first line (item name)
            if r > 0.9 and g > 0.7 and b < 0.2 and text and i > 1 then
                return true
            end
        end
    end

    return false
end
