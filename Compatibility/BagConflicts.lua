local addonName, ns = ...

-------------------------------------------------
-- Bag addon conflicts
-- Other full bag replacements take over the same things GudaBags does: the
-- ToggleAllBags / OpenAllBags family, Blizzard's container and bank frames, and
-- the item buttons' clicks and lock overlays. Running two of them makes the
-- windows open together and fight over clicks and item locks -- reported with
-- EllesmereUI, whose bags are their own addon (EllesmereUIBags) and whose
-- in-game "enhanced bags" option still leaves its bank window and OpenAllBags
-- hook active. No setting can make them coexist, so at login we say so once and
-- offer to disable the other addon. Nothing here touches the other addon's code.
-------------------------------------------------
local BagConflicts = {}
ns:RegisterModule("Compatibility.BagConflicts", BagConflicts)

local Events = ns:GetModule("Events")
local L = ns.L

-- Addon folder names of full bag/bank replacements. One line per addon.
local CONFLICTING_ADDONS = {
    "EllesmereUIBags",
    "Baganator",
    "Bagnon",
    "AdiBags",
    "ArkInventory",
    "BetterBags",
}

local IsAddOnLoaded = ns.IsAddOnLoaded
local DisableAddOn = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

-- Display name from the addon's own Title, with color codes stripped
local function DisplayName(name)
    local title = GetAddOnMetadata and GetAddOnMetadata(name, "Title")
    if type(title) ~= "string" or title == "" then return name end
    title = title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return title
end

-- Loaded conflicting addons the player hasn't chosen to keep alongside us
function BagConflicts:GetActiveConflicts()
    local ignored = GudaBags_DB and GudaBags_DB.ignoredBagConflicts or {}
    local found = {}
    if not IsAddOnLoaded then return found end
    for _, name in ipairs(CONFLICTING_ADDONS) do
        if IsAddOnLoaded(name) and not ignored[name] then
            found[#found + 1] = name
        end
    end
    return found
end

-- Per character (the AddOns list's default), so another character's choice is untouched
local function DisableAndReload(names)
    if not DisableAddOn then return end
    local character = UnitName("player")
    for _, name in ipairs(names) do
        DisableAddOn(name, character)
    end
    ReloadUI()
end

local pending = {}  -- conflicts the open popup is about

-- Yes disables the other addon; No (or Escape, which Blizzard reports to OnCancel
-- as "clicked" too) keeps both and is remembered, so the question isn't asked again.
StaticPopupDialogs["GUDABAGS_BAG_CONFLICT"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function()
        DisableAndReload(pending)
    end,
    OnCancel = function(_, _, reason)
        if reason == "clicked" then
            GudaBags_DB.ignoredBagConflicts = GudaBags_DB.ignoredBagConflicts or {}
            for _, name in ipairs(pending) do
                GudaBags_DB.ignoredBagConflicts[name] = true
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function ShowConflictPopup()
    if InCombatLockdown() then return end
    local conflicts = BagConflicts:GetActiveConflicts()
    if #conflicts == 0 then return end

    pending = conflicts
    local names = {}
    for i, name in ipairs(conflicts) do
        names[i] = DisplayName(name)
    end
    StaticPopup_Show("GUDABAGS_BAG_CONFLICT", string.format(L["BAG_CONFLICT_TEXT"], table.concat(names, ", ")))
end

-- A few seconds after login, so the popup doesn't land under the loading screen
Events:OnPlayerLogin(function()
    C_Timer.After(5, ShowConflictPopup)
end, BagConflicts)
