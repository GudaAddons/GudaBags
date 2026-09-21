local addonName, ns = ...

local SlashCommands = {}
ns:RegisterModule("SlashCommands", SlashCommands)

local L = ns.L

-------------------------------------------------
-- Module Getters (lazy loading)
-------------------------------------------------

local Database = ns:GetModule("Database")

local function GetBagFrame()
    return ns:GetModule("BagFrame")
end

local function GetBankFrame()
    return ns:GetModule("BankFrame")
end

local function GetSettingsPopup()
    return ns:GetModule("SettingsPopup")
end

local function GetBagScanner()
    return ns:GetModule("BagScanner")
end

-------------------------------------------------
-- Command Handlers
-------------------------------------------------

local commandHandlers = {}

-- Default: Toggle bag frame
commandHandlers[""] = function()
    GetBagFrame():Toggle()
end

-- Settings/Config/Options
commandHandlers["settings"] = function()
    GetSettingsPopup():Toggle()
end
commandHandlers["config"] = commandHandlers["settings"]
commandHandlers["options"] = commandHandlers["settings"]

-- Sort bags
commandHandlers["sort"] = function()
    GetBagFrame():SortBags()
end

-- Toggle bank
commandHandlers["bank"] = function()
    GetBankFrame():Toggle()
end

-- Debug mode toggle
commandHandlers["debug"] = function()
    ns.debugMode = not ns.debugMode
    ns:Print(L["CMD_DEBUG_MODE"], ns.debugMode and L["CMD_ON"] or L["CMD_OFF"])
end

-- Profiler: toggle high-res phase timing
commandHandlers["profile"] = function()
    ns.profileMode = not ns.profileMode
    ns:Print("Profiler: " .. (ns.profileMode and "|cff00ff00ON|r" or "|cffff0000OFF|r")
        .. " — exercise the bags/bank, then /guda profiledump")
    if ns.profileMode then
        ns:ProfileReset()
    end
end

-- Profiler: print accumulated timings
commandHandlers["profiledump"] = function()
    ns:ProfileDump()
end

-- Profiler: clear accumulated timings
commandHandlers["profilereset"] = function()
    ns:ProfileReset()
    ns:Print("Profiler stats reset.")
end

-- A/B suspect toggles: list current state
local SUSPECTS = { "tooltipscan", "glow", "masque", "upgrade", "grouping", "upgradetrack" }
commandHandlers["toggle"] = function()
    ns:Print("Suspect toggles (disable a subsystem to isolate cost):")
    for _, name in ipairs(SUSPECTS) do
        local disabled = ns.suspectDisabled[name]
        ns:Print(string.format("  %s: %s", name,
            disabled and "|cffff0000DISABLED|r" or "|cff00ff00enabled|r"))
    end
    ns:Print("Usage: /guda toggle <" .. table.concat(SUSPECTS, "|") .. ">")
end

-- Debug item hover - print item data on hover
commandHandlers["debugitem"] = function()
    ns.debugItemMode = not ns.debugItemMode
    ns:Print("Debug item hover: " .. (ns.debugItemMode and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

-- Report the shared ItemButton pool: size, who is holding buttons, and any that
-- can never be reclaimed. Run it right after login and again later to see the
-- pool drain, which is what identifies the holder.
commandHandlers["pool"] = function()
    local ItemButton = ns:GetModule("ItemButton")
    if not ItemButton then return end
    local stats = ItemButton:GetPoolStats()
    ns:Print(string.format("Pool: total %d, free %d, active %d, orphaned %d",
        stats.total, stats.inactive, stats.active, stats.orphaned))
    if stats.orphaned > 0 then
        ns:Print("  |cffff0000orphaned > 0|r - acquired without an owner, ReleaseAll can never reclaim these")
    end

    -- Active buttons grouped by the frame that owns them. Named frames report
    -- their name; the bag/bank/guild-bank containers are anonymous, so fall back
    -- to the parent's name, which is the one that identifies the consumer.
    local byOwner, order = {}, {}
    for button in ItemButton:GetActiveButtons() do
        local owner = button.owner
        local label = "(no owner)"
        if owner then
            label = (owner.GetName and owner:GetName())
                or (owner.GetParent and owner:GetParent() and owner:GetParent().GetName
                    and owner:GetParent():GetName())
                or tostring(owner)
        end
        if not byOwner[label] then
            byOwner[label] = 0
            order[#order + 1] = label
        end
        byOwner[label] = byOwner[label] + 1
    end
    for _, label in ipairs(order) do
        ns:Print(string.format("  %s: %d", label, byOwner[label]))
    end
end

-- Debug item button frames (for retail overlay issues)
commandHandlers["debugbutton"] = function()
    local ItemButton = ns:GetModule("ItemButton")
    ns:Print("Checking first item button structure...")

    -- Get first active button
    local firstButton = nil
    for button in ItemButton:GetActiveButtons() do
        firstButton = button
        break
    end

    if not firstButton then
        ns:Print("No active item buttons found. Open your bags first.")
        return
    end

    ns:Print("Button: " .. (firstButton:GetName() or "unnamed"))
    ns:Print("  Mouse enabled: " .. tostring(firstButton:IsMouseEnabled()))
    ns:Print("  Shown: " .. tostring(firstButton:IsShown()))
    ns:Print("  Frame level: " .. tostring(firstButton:GetFrameLevel()))

    -- List children
    local children = {firstButton:GetChildren()}
    ns:Print("  Children (" .. #children .. "):")
    for i, child in ipairs(children) do
        local childName = child:GetName() or child:GetObjectType()
        local mouseEnabled = child.IsMouseEnabled and child:IsMouseEnabled() or "N/A"
        local shown = child:IsShown()
        local level = child.GetFrameLevel and child:GetFrameLevel() or "N/A"
        ns:Print("    " .. i .. ": " .. childName .. " mouse=" .. tostring(mouseEnabled) .. " shown=" .. tostring(shown) .. " level=" .. tostring(level))
    end

    -- Check specific overlays
    local overlays = {"ItemContextOverlay", "SearchOverlay", "ExtendedSlot", "WidgetContainer", "Cooldown", "NineSlice"}
    ns:Print("  Known overlays:")
    for _, name in ipairs(overlays) do
        local overlay = firstButton[name]
        if overlay then
            local shown = overlay.IsShown and overlay:IsShown() or "N/A"
            local mouse = overlay.IsMouseEnabled and overlay:IsMouseEnabled() or "N/A"
            ns:Print("    " .. name .. ": exists, shown=" .. tostring(shown) .. " mouse=" .. tostring(mouse))
        else
            ns:Print("    " .. name .. ": not found")
        end
    end
end

-- List saved characters
commandHandlers["chars"] = function()
    ns:Print(L["CMD_SAVED_CHARACTERS"])

    local characters = Database:GetAllCharacterData()
    if characters and next(characters) then
        local currentFullName = Database:GetPlayerFullName()
        for fullName, data in pairs(characters) do
            local bagCount = 0
            local bagItemCount = 0
            local bankCount = 0
            local bankItemCount = 0

            if data.bags then
                for _, bagData in pairs(data.bags) do
                    bagCount = bagCount + 1
                    if bagData.slots then
                        for _ in pairs(bagData.slots) do
                            bagItemCount = bagItemCount + 1
                        end
                    end
                end
            end

            if data.bank then
                for _, bagData in pairs(data.bank) do
                    bankCount = bankCount + 1
                    if bagData.slots then
                        for _ in pairs(bagData.slots) do
                            bankItemCount = bankItemCount + 1
                        end
                    end
                end
            end

            local current = (fullName == currentFullName) and " " .. L["CMD_YOU"] or ""
            ns:Print("  " .. fullName .. current)
            ns:Print("    " .. L["CMD_BAGS"] .. bagCount .. L["CMD_CONTAINERS"] .. bagItemCount .. L["CMD_ITEMS"])
            ns:Print("    " .. L["CMD_BANK"] .. bankCount .. L["CMD_CONTAINERS"] .. bankItemCount .. L["CMD_ITEMS"])
        end
    else
        ns:Print("  " .. L["CMD_NO_DATA"])
    end
end

-- Force save current character
commandHandlers["save"] = function()
    local BagScanner = GetBagScanner()

    ns:Print(L["CMD_SCANNING"])
    local bags = BagScanner:ScanAllBags()

    local bagCount = 0
    local itemCount = 0
    for _, bagData in pairs(bags) do
        bagCount = bagCount + 1
        if bagData.slots then
            for _ in pairs(bagData.slots) do
                itemCount = itemCount + 1
            end
        end
    end
    ns:Print(string.format(L["CMD_SCANNED"], bagCount, itemCount))

    ns:Print(L["CMD_SAVING_TO"] .. Database:GetPlayerFullName())
    BagScanner:SaveToDatabase()
    ns:Print(L["CMD_DONE"])
end

-- Show current locale info
commandHandlers["locale"] = function()
    local testLocale = Database:GetGlobalSetting("testLocale")

    ns:Print("Current locale: " .. ns:GetCurrentLocale())
    ns:Print("Game locale: " .. GetLocale())
    if testLocale then
        ns:Print("Test override: " .. testLocale)
    else
        ns:Print("Test override: none")
    end
    ns:Print("Available: " .. table.concat(ns:GetAvailableLocales(), ", "))
end

-- Status - show expansion and feature detection info
commandHandlers["status"] = function()
    local Expansion = ns:GetModule("Expansion")
    local Constants = ns.Constants

    ns:Print("=== GudaBags Status ===")
    ns:Print("Version: " .. (ns.version or "unknown"))

    if Expansion then
        ns:Print("Interface: " .. (Expansion.InterfaceVersion or "unknown"))
        -- Printed raw because WoW: Forever ships no WOW_PROJECT_* constant of its
        -- own, so this is the one value a Forever bug report has to carry.
        ns:Print("WOW_PROJECT_ID: " .. tostring(WOW_PROJECT_ID))
        ns:Print("IsRetail: " .. tostring(Expansion.IsRetail))
        ns:Print("IsClassicEra: " .. tostring(Expansion.IsClassicEra))
        ns:Print("IsForever: " .. tostring(Expansion.IsForever))
        ns:Print("IsTBC: " .. tostring(Expansion.IsTBC))
        ns:Print("IsMoP: " .. tostring(Expansion.IsMoP))
    else
        ns:Print("Expansion module: NOT LOADED")
    end

    -- Carried containers are discovered at load, so print what this client actually
    -- reported. On a flavor whose bag layout we have not seen, this line is the
    -- answer: it names every container the addon will scan and where the reagent
    -- bag landed.
    if Constants and Constants.BAG_IDS then
        ns:Print("BAG_IDS: " .. table.concat(Constants.BAG_IDS, ", "))
        ns:Print("REAGENT_BAG: " .. tostring(Constants.REAGENT_BAG)
            .. "  PLAYER_BAG_MAX: " .. tostring(Constants.PLAYER_BAG_MAX)
            .. "  KEYRING_BAG_ID: " .. tostring(Constants.KEYRING_BAG_ID))
        -- Says whether the bag count came from the client or from the hardcoded
        -- fallback in DiscoverCarriedBags. On a flavor nobody has tested, "the
        -- client never told us" and "the client said 5" look identical otherwise.
        ns:Print("NUM_BAG_SLOTS: " .. tostring(NUM_BAG_SLOTS)
            .. (NUM_BAG_SLOTS == nil and " (FALLBACK USED)" or "")
            .. "  NUM_TOTAL_EQUIPPED_BAG_SLOTS: " .. tostring(NUM_TOTAL_EQUIPPED_BAG_SLOTS))
        -- CHARACTER_BANK_TABS_ACTIVE reveals which bank branch Constants took: a
        -- false here on a modern client means it silently fell back to the old
        -- {-1, 6..12} bank-bag layout, which looks like "the bank is empty".
        ns:Print("CHARACTER_BANK_TABS_ACTIVE: " .. tostring(Constants.CHARACTER_BANK_TABS_ACTIVE)
            .. "  WARBAND_BANK_ACTIVE: " .. tostring(Constants.WARBAND_BANK_ACTIVE))
        ns:Print("BANK_BAG_MIN: " .. tostring(Constants.BANK_BAG_MIN)
            .. "  BANK_BAG_MAX: " .. tostring(Constants.BANK_BAG_MAX))
        ns:Print("Character bank tabs (" .. #(Constants.CHARACTER_BANK_TAB_IDS or {}) .. "): "
            .. table.concat(Constants.CHARACTER_BANK_TAB_IDS or {}, ", "))
        ns:Print("Warband bank tabs (" .. #(Constants.WARBAND_BANK_TAB_IDS or {}) .. "): "
            .. table.concat(Constants.WARBAND_BANK_TAB_IDS or {}, ", "))
    else
        ns:Print("Constants.BAG_IDS: NOT LOADED")
    end

    -- Two different tables with confusingly similar names, and only the first
    -- used to be printed here. Constants.FEATURES is the addon's own subsystem
    -- toggles; Expansion.Features is the client capability set that the whole
    -- compatibility layer branches on, and it is the one a report about an
    -- untested flavor actually needs.
    if Constants and Constants.FEATURES then
        ns:Print("Constants.FEATURES (subsystem toggles):")
        for k, v in pairs(Constants.FEATURES) do
            ns:Print("  " .. k .. ": " .. tostring(v))
        end
    else
        ns:Print("Constants.FEATURES: NOT LOADED")
    end

    if Expansion and Expansion.Features then
        ns:Print("Expansion.Features (client capabilities):")
        for k, v in pairs(Expansion.Features) do
            ns:Print("  " .. k .. ": " .. tostring(v))
        end
    else
        ns:Print("Expansion.Features: NOT LOADED")
    end

    -- Where each relocated function resolved from. WoW: Forever ships none of
    -- these as globals, so a MISSING line here explains an "attempt to call a nil
    -- value" without needing the stack trace.
    local CompatAPI = ns:GetModule("Compatibility.API")
    if CompatAPI and CompatAPI.resolvedSource then
        ns:Print("Relocated API source:")
        for _, name in ipairs(CompatAPI.resolvedNames or {}) do
            ns:Print("  " .. name .. ": " .. tostring(CompatAPI.resolvedSource[name]))
        end
    else
        ns:Print("Compatibility.API: NOT LOADED")
    end

    -- Check if modules are registered
    local scanner = ns:GetModule("GuildBankScanner")
    local gbFrame = ns:GetModule("GuildBankFrame")
    ns:Print("GuildBankScanner: " .. (scanner and "loaded" or "NOT LOADED"))
    ns:Print("GuildBankFrame: " .. (gbFrame and "loaded" or "NOT LOADED"))
end

-- API check - report which client APIs this flavor actually provides.
--
-- Exists because a chat line caps at 255 characters, so the alternative -- asking
-- a tester to paste a /run probe -- cannot cover the surface that matters. And
-- because the failure mode here is silence: WoW: Forever dropped the legacy global
-- item functions, and the only symptom was "attempt to call a nil value" from
-- deep inside a bag scan. A named list of what is missing turns that into a
-- one-line answer.
--
-- Grouped the way the addon depends on them, so a MISSING entry points at the
-- subsystem that will break rather than just at a name. Nothing here is cached:
-- it must report the live client, and it runs only when a human types it.
local API_CHECK_GROUPS = {
    -- Every global function the addon actually calls, extracted from the source
    -- rather than hand-picked, so this cannot drift out of date silently and does
    -- not depend on guessing which ones a new client dropped. Third-party entry
    -- points (Pawn, Outfitter, LibStub) are deliberately absent -- they are
    -- expected to be missing and say nothing about the client.
    { "Addon global call surface", "global",
      { "AutoStoreGuildBankItem", "BankButtonIDToInvSlotID",
        "BreakUpLargeNumbers", "ButtonFrameTemplate_HideButtonBar",
        "ButtonFrameTemplate_HidePortrait", "BuyGuildBankTab",
        "CanEditGuildBankTabInfo", "CanMerchantRepair",
        "CanWithdrawGuildBankMoney", "CloseBankFrame", "CloseDropDownMenus",
        "CloseGuildBankFrame", "ContainerFrameItemButton_OnEnter",
        "ContainerFrameItemButton_OnLeave", "ContainerIDToInventoryID",
        "CooldownFrame_Set", "CreateColor", "CreateMinimalSliderFormatter",
        "CreateObjectPool", "CursorHasItem", "DoesTemplateExist",
        "DynamicResizeButton_Resize", "GetAuctionItemInfo", "GetAuctionItemLink",
        "GetBankSlotCost", "GetBuildInfo", "GetCVar", "GetCoinTextureString",
        "GetCraftItemLink", "GetCraftReagentItemLink", "GetCursorInfo",
        "GetCursorPosition", "GetDenominationsFromCopper",
        "GetDetailedCurrencyInfo", "GetGuildBankItemInfo", "GetGuildBankItemLink",
        "GetGuildBankMoney", "GetGuildBankMoneyTransaction",
        "GetGuildBankTabCost", "GetGuildBankTabInfo", "GetGuildBankText",
        "GetGuildBankTransaction", "GetGuildBankWithdrawMoney", "GetGuildInfo",
        "GetInboxHeaderInfo", "GetInboxItem", "GetInboxItemLink",
        "GetInboxNumItems", "GetInventoryItemID", "GetInventoryItemLink",
        "GetInventoryItemTexture", "GetLocale", "GetMaxPlayerLevel", "GetMoney",
        "GetNumBankSlots", "GetNumGuildBankMoneyTransactions",
        "GetNumGuildBankTabs", "GetNumGuildBankTransactions", "GetQuestItemLink",
        "GetQuestLogItemLink", "GetRealmName", "GetRepairAllCost",
        "GetSendMailCOD", "GetSendMailItem", "GetSendMailItemLink",
        "GetSendMailMoney", "GetSendMailPrice", "GetSpellCooldown",
        "GetTimePreciseSec", "GetTradeSkillItemLink",
        "GetTradeSkillReagentItemLink", "HandleModifiedItemClick",
        "IsAddOnLoaded", "IsAltKeyDown", "IsControlKeyDown", "IsInGuild",
        "IsInInstance", "IsLoggedIn", "IsModifiedClick", "IsMouseButtonDown",
        "IsShiftKeyDown", "IsSpellKnown", "MoneyFrame_Update",
        "MoneyInputFrame_GetCopper", "MoneyInputFrame_ResetMoney", "MouseIsOver",
        "MuteSoundFile", "OpenStackSplitFrame", "PanelTemplates_DeselectTab",
        "PanelTemplates_SetNumTabs", "PanelTemplates_SetTab",
        "PanelTemplates_TabResize", "PickupBagFromSlot", "PickupGuildBankItem",
        "PickupInventoryItem", "PlaySound", "PurchaseSlot", "PutItemInBag",
        "QueryGuildBankLog", "QueryGuildBankTab", "QueryGuildBankText",
        "RecentTimeDate", "RepairAllItems", "SendMail", "SetCVar",
        "SetCurrentGuildBankTab", "SetCursor", "SetItemButtonCount",
        "SetItemButtonDesaturated", "SetItemButtonTexture", "SpellIsTargeting",
        "SplitGuildBankItem", "StaticPopup_Show", "ToggleDropDownMenu",
        "UIDropDownMenu_AddButton", "UIDropDownMenu_CreateInfo",
        "UIDropDownMenu_Initialize", "UIDropDownMenu_SetText",
        "UIDropDownMenu_SetWidth", "UnitClass", "UnitFactionGroup", "UnitLevel",
        "UnitName", "UnitRace", "UnitSex", "UnmuteSoundFile" } },
    -- Globals the addon reads or overrides rather than calls, plus the modern
    -- menu entry point it prefers when present.
    { "Bag globals and menu API", "global",
      { "NUM_BAG_SLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "ToggleBackpack",
        "ToggleBag", "OpenAllBags", "CloseAllBags", "OpenBackpack", "OpenBag",
        "CloseBag", "CloseBackpack", "GuildBankFrame_LoadUI", "MenuUtil",
        "BankFrame", "GuildBankFrame", "PlaceAuctionBid" } },
    { "Namespaces", "global",
      { "C_Container", "C_Item", "C_Bank", "C_GuildBank", "C_CurrencyInfo",
        "C_EquipmentSet", "C_TradeSkillUI", "C_XMLUtil", "C_AddOns", "C_CVar",
        "C_Spell", "C_Mail", "C_PlayerInteractionManager" } },
    { "C_Item", "c_item",
      { "GetItemInfo", "GetItemInfoInstant", "GetItemSpell", "GetItemQualityColor",
        "GetItemClassInfo", "GetItemIconByID", "GetItemFamily", "GetItemCount",
        "IsBoundToAccountUntilEquip", "RequestLoadItemDataByID" } },
    { "C_Container", "c_container",
      { "GetContainerItemInfo", "GetContainerNumSlots", "ContainerIDToInventoryID",
        "SortBags", "SortBankBags", "SortAccountBankBags",
        "SortReagentBankBags" } },
    { "C_Bank", "c_bank",
      { "FetchNumPurchasedBankTabs", "FetchPurchasedBankTabData",
        "FetchViewableBankTypes", "AutoDepositItemsIntoBank", "CanPurchaseBankTab",
        "FetchBankLockedReason", "CanDepositMoney", "FetchDepositedMoney" } },
}

-- Enum members are checked separately: indexing a missing parent table is the
-- error this whole command is meant to find, so each lookup walks down guarded.
local API_CHECK_ENUMS = {
    "BagIndex.Backpack", "BagIndex.Keyring", "BagIndex.ReagentBag",
    "BagIndex.Reagentbank", "BagIndex.CharacterBankTab_1",
    "BagIndex.CharacterBankTab_6", "BagIndex.CharacterBankTab_9",
    "BagIndex.AccountBankTab_1", "BagIndex.AccountBankTab_5",
    "BagIndex.AccountBankTab_9", "BankType.Character", "BankType.Account",
    "PlayerInteractionType.Banker", "PlayerInteractionType.GuildBanker",
    "ItemQuality.Common",
}

-- Templates the addon builds frames from. Probed through C_XMLUtil rather than a
-- throwaway CreateFrame: item buttons use a secure template, and Rule 3 keeps
-- every one of those in the pre-warmed pool. A diagnostic must not mint one.
local API_CHECK_TEMPLATES = {
    "ContainerFrameItemButtonTemplate", "SecureActionButtonTemplate",
    "UIPanelButtonTemplate", "GameTooltipTemplate", "UIDropDownMenuTemplate",
    "BackdropTemplate", "SettingsCheckBoxTemplate", "SettingsCheckboxTemplate",
    "WowStyle1DropdownTemplate", "MinimalSliderWithSteppersTemplate",
}

local function ApiCheckTable(kind)
    if kind == "global" then return _G end
    if kind == "c_item" then return C_Item end
    if kind == "c_container" then return C_Container end
    if kind == "c_bank" then return C_Bank end
    return nil
end

commandHandlers["apicheck"] = function()
    ns:Print("=== GudaBags API check ===")
    ns:Print("Interface: " .. tostring(select(4, GetBuildInfo()))
        .. "  Build: " .. tostring(select(2, GetBuildInfo())))

    for _, group in ipairs(API_CHECK_GROUPS) do
        local label, kind, names = group[1], group[2], group[3]
        local parent = ApiCheckTable(kind)
        if not parent then
            ns:Print(label .. ": PARENT TABLE MISSING")
        else
            local missing = {}
            for _, name in ipairs(names) do
                if parent[name] == nil then
                    missing[#missing + 1] = name
                end
            end
            if #missing == 0 then
                ns:Print(label .. ": all " .. #names .. " present")
            else
                ns:Print(label .. ": MISSING " .. #missing .. "/" .. #names
                    .. " -> " .. table.concat(missing, ", "))
            end
        end
    end

    local missingEnums = {}
    for _, path in ipairs(API_CHECK_ENUMS) do
        local parentName, member = path:match("^(.-)%.(.+)$")
        local parent = Enum and parentName and Enum[parentName]
        if not parent or parent[member] == nil then
            missingEnums[#missingEnums + 1] = path
        end
    end
    if #missingEnums == 0 then
        ns:Print("Enum members: all " .. #API_CHECK_ENUMS .. " present")
    else
        ns:Print("Enum members: MISSING " .. #missingEnums .. "/" .. #API_CHECK_ENUMS
            .. " -> " .. table.concat(missingEnums, ", "))
    end

    -- DoesTemplateExist first: it is what UI/Controls/Checkbox, Select and Slider
    -- already use to pick a template, so this reports the same answer those
    -- controls will act on. C_XMLUtil is the fallback for a client without it.
    local templateProbe, probeName
    if DoesTemplateExist then
        templateProbe, probeName = DoesTemplateExist, "DoesTemplateExist"
    elseif C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        templateProbe, probeName = C_XMLUtil.GetTemplateInfo, "C_XMLUtil"
    end

    if templateProbe then
        local missingTemplates = {}
        for _, name in ipairs(API_CHECK_TEMPLATES) do
            local ok, info = pcall(templateProbe, name)
            if not ok or not info then
                missingTemplates[#missingTemplates + 1] = name
            end
        end
        if #missingTemplates == 0 then
            ns:Print("Templates (" .. probeName .. "): all "
                .. #API_CHECK_TEMPLATES .. " present")
        else
            ns:Print("Templates (" .. probeName .. "): MISSING -> "
                .. table.concat(missingTemplates, ", "))
        end
    else
        ns:Print("Templates: no probe available, not checked")
    end
end

-- Help
commandHandlers["help"] = function()
    ns:Print(L["CMD_COMMANDS"])
    ns:Print("  " .. L["CMD_HELP_TOGGLE"])
    ns:Print("  " .. L["CMD_HELP_BANK"])
    ns:Print("  " .. L["CMD_HELP_SETTINGS"])
    ns:Print("  " .. L["CMD_HELP_SORT"])
    ns:Print("  " .. L["CMD_HELP_CHARS"])
    ns:Print("  " .. L["CMD_HELP_SAVE"])
    ns:Print("  " .. L["CMD_HELP_COUNT"])
    ns:Print("  " .. L["CMD_HELP_DEBUG"])
    ns:Print("  " .. L["CMD_HELP_HELP"])
    ns:Print("  /guda debugitem - Toggle item data on hover")
    ns:Print("  /guda locale [code|reset] - Test locale")
    ns:Print("  /guda status - Show expansion/feature detection")
    ns:Print("  /guda apicheck - Report which client APIs this flavor provides")
    ns:Print("  /guda profile - Toggle performance profiler")
    ns:Print("  /guda profiledump - Print profiler timings")
    ns:Print("  /guda pool - Show item button pool usage by owner")
    ns:Print("  /guda profilereset - Clear profiler timings")
    ns:Print("  /guda toggle <name> - A/B toggle a subsystem (tooltipscan|glow|masque|upgrade|grouping)")
end

-------------------------------------------------
-- Pattern-based Command Handlers
-------------------------------------------------

local patternHandlers = {}

-- Count item by ID across characters. Diagnostic dump, so it deliberately includes
-- characters excluded from the tooltip totals.
patternHandlers["^count%s+(%d+)$"] = function(itemID)
    local total, chars = Database:CountItemAcrossCharacters(tonumber(itemID), true)
    ns:Print(string.format(L["CMD_ITEM_COUNT"], itemID, total))
    for _, c in ipairs(chars) do
        local current = c.isCurrent and " " .. L["CMD_YOU"] or ""
        ns:Print("  " .. c.name .. current .. ": " .. c.count)
    end
end

-- Set locale (use original case)
patternHandlers["^locale%s+(%S+)$"] = function(localeCode)
    ns:SetLocale(localeCode)
end

-- Toggle a named suspect subsystem on/off for A/B profiling
patternHandlers["^toggle%s+(%a+)$"] = function(name)
    name = name:lower()
    local valid = false
    for _, s in ipairs(SUSPECTS) do
        if s == name then valid = true break end
    end
    if not valid then
        ns:Print("Unknown suspect '" .. name .. "'. Valid: " .. table.concat(SUSPECTS, ", "))
        return
    end
    ns.suspectDisabled[name] = not ns.suspectDisabled[name]
    ns:Print(string.format("Suspect '%s' is now %s", name,
        ns.suspectDisabled[name] and "|cffff0000DISABLED|r" or "|cff00ff00enabled|r"))

    -- Clear caches and force a full rebuild so the toggle takes effect immediately.
    local ItemScanner = ns:GetModule("ItemScanner")
    if ItemScanner and ItemScanner.ClearTooltipCache then
        ItemScanner:ClearTooltipCache()
    end
    local BagFrame = GetBagFrame()
    if BagFrame and BagFrame.IsShown and BagFrame:IsShown() then
        GetBagScanner():ScanAllBags()
        BagFrame:Refresh()
    end
end

-------------------------------------------------
-- Main Command Dispatcher
-------------------------------------------------

local function HandleSlashCommand(msg)
    local originalMsg = msg or ""
    local cmd = string.lower(originalMsg)

    -- Try exact match first
    if commandHandlers[cmd] then
        commandHandlers[cmd]()
        return
    end

    -- Try pattern matches (use original message for case-sensitive patterns like locale)
    for pattern, handler in pairs(patternHandlers) do
        local capture = originalMsg:match(pattern)
        if capture then
            handler(capture)
            return
        end
    end

    -- Unknown command
    ns:Print(L["CMD_UNKNOWN"])
end

-------------------------------------------------
-- Registration
-------------------------------------------------

function SlashCommands:Register()
    _G["SLASH_GUDABAGS1"] = "/guda"
    _G["SLASH_GUDABAGS2"] = "/gb"
    _G.SlashCmdList["GUDABAGS"] = HandleSlashCommand
end

-- Auto-register on load
SlashCommands:Register()
