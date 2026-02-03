local addonName, ns = ...

local SettingsSchema = {}
ns:RegisterModule("SettingsSchema", SettingsSchema)

-------------------------------------------------
-- General Tab Schema
-------------------------------------------------
function SettingsSchema.GetGeneral()
    local L = ns.L
    return {
        { type = "description", text = L["SETTINGS_GENERAL_DESCRIPTION"], height = 28 },
        { type = "slider", key = "bgAlpha", label = L["SETTINGS_BG_OPACITY"], min = 0, max = 100, step = 5, format = "%" },

        { type = "row", children = {
            { type = "checkbox", key = "locked", label = L["SETTINGS_LOCK_WINDOW"], tooltip = L["SETTINGS_LOCK_WINDOW_TIP"] },
            { type = "checkbox", key = "showBorders", label = L["SETTINGS_SHOW_BORDERS"], tooltip = L["SETTINGS_SHOW_BORDERS_TIP"] },
        }},

        { type = "row", children = {
            { type = "checkbox", key = "hoverBagline", label = L["SETTINGS_SHOW_ALL_BAGS"], tooltip = L["SETTINGS_SHOW_ALL_BAGS_TIP"] },
            { type = "checkbox", key = "showTooltipCounts", label = L["SETTINGS_INVENTORY_COUNTS"], tooltip = L["SETTINGS_INVENTORY_COUNTS_TIP"] },
        }},

        { type = "row", children = {
            { type = "checkbox", key = "sortRightToLeft", label = L["SETTINGS_SORT_RTL"], tooltip = L["SETTINGS_SORT_RTL_TIP"],
              hidden = function() local Expansion = ns:GetModule("Expansion") return Expansion and Expansion.IsRetail end },
            { type = "checkbox", key = "reverseStackSort", label = L["SETTINGS_REVERSE_STACK"], tooltip = L["SETTINGS_REVERSE_STACK_TIP"] },
        }},
    }
end

-------------------------------------------------
-- Layout Tab Schema
-------------------------------------------------
function SettingsSchema.GetLayout()
    local L = ns.L
    return {
        { type = "select", key = "bagViewType", label = L["SETTINGS_BAG_VIEW"], tooltip = L["SETTINGS_BAG_VIEW_TIP"], options = {
            { value = "single", label = L["SETTINGS_VIEW_SINGLE"] },
            { value = "category", label = L["SETTINGS_VIEW_CATEGORY"] },
        }},
        { type = "select", key = "bankViewType", label = L["SETTINGS_BANK_VIEW"], tooltip = L["SETTINGS_BANK_VIEW_TIP"], options = {
            { value = "single", label = L["SETTINGS_VIEW_SINGLE"] },
            { value = "category", label = L["SETTINGS_VIEW_CATEGORY"] },
        }},

        { type = "slider", key = "bagColumns", label = L["SETTINGS_BAG_COLUMNS"], min = 5, max = 22, step = 1 },
        { type = "slider", key = "bankColumns", label = L["SETTINGS_BANK_COLUMNS"], min = 5, max = 36, step = 1 },
        { type = "slider", key = "guildBankColumns", label = L["SETTINGS_GUILD_BANK_COLUMNS"], min = 10, max = 36, step = 1 },

        { type = "row", children = {
            { type = "checkbox", key = "showSearchBar", label = L["SETTINGS_SHOW_SEARCH"], tooltip = L["SETTINGS_SHOW_SEARCH_TIP"] },
            { type = "checkbox", key = "showFooter", label = L["SETTINGS_SHOW_FOOTER"], tooltip = L["SETTINGS_SHOW_FOOTER_TIP"] },
        }},

        { type = "row", children = {
            { type = "checkbox", key = "showCategoryCount", label = L["SETTINGS_SHOW_CAT_COUNT"], tooltip = L["SETTINGS_SHOW_CAT_COUNT_TIP"] },
            { type = "checkbox", key = "groupIdenticalItems", label = L["SETTINGS_GROUP_IDENTICAL"], tooltip = L["SETTINGS_GROUP_IDENTICAL_TIP"] },
        }},

        { type = "row", children = {
            { type = "checkbox", key = "showQuestBar", label = L["SETTINGS_SHOW_QUEST_BAR"], tooltip = L["SETTINGS_SHOW_QUEST_BAR_TIP"] },
            { type = "checkbox", key = "hideQuestBarInBGs", label = L["SETTINGS_HIDE_QUEST_BAR_BG"], tooltip = L["SETTINGS_HIDE_QUEST_BAR_BG_TIP"] },
        }},
    }
end

-------------------------------------------------
-- Icons Tab Schema
-------------------------------------------------
function SettingsSchema.GetIcons()
    local L = ns.L
    return {
        -- Sliders
        { type = "slider", key = "iconSize", label = L["SETTINGS_ICON_SIZE"], min = 22, max = 64, step = 1, format = "px" },
        { type = "slider", key = "iconFontSize", label = L["SETTINGS_ICON_FONT_SIZE"], min = 8, max = 20, step = 1, format = "px" },
        { type = "slider", key = "iconSpacing", label = L["SETTINGS_ICON_SPACING"], min = 0, max = 20, step = 1, format = "px" },
        { type = "slider", key = "questBarSize", label = L["SETTINGS_QUEST_BAR_SIZE"], min = 22, max = 64, step = 1, format = "px" },
        { type = "slider", key = "trackedBarSize", label = L["SETTINGS_TRACKED_BAR_SIZE"], min = 22, max = 64, step = 1, format = "px" },
        { type = "slider", key = "trackedBarColumns", label = L["SETTINGS_TRACKED_BAR_COLS"], min = 2, max = 12, step = 1 },

        -- Row 1
        { type = "row", children = {
            { type = "checkbox", key = "equipmentBorders", label = L["SETTINGS_QUALITY_BORDERS"], tooltip = L["SETTINGS_QUALITY_BORDERS_TIP"] },
            { type = "checkbox", key = "otherBorders", label = L["SETTINGS_OTHER_BORDERS"], tooltip = L["SETTINGS_OTHER_BORDERS_TIP"] },
        }},

        -- Row 2
        { type = "row", children = {
            { type = "checkbox", key = "markUnusableItems", label = L["SETTINGS_MARK_UNUSABLE"], tooltip = L["SETTINGS_MARK_UNUSABLE_TIP"] },
            { type = "checkbox", key = "grayoutJunk", label = L["SETTINGS_GRAYOUT_JUNK"], tooltip = L["SETTINGS_GRAYOUT_JUNK_TIP"] },
        }},

        -- Row 3 - Junk options
        { type = "row", children = {
            { type = "checkbox", key = "whiteItemsJunk", label = L["SETTINGS_WHITE_JUNK"], tooltip = L["SETTINGS_WHITE_JUNK_TIP"] },
        }},
    }
end

-- Backwards compatibility - these will be called as functions now
SettingsSchema.GENERAL = nil
SettingsSchema.LAYOUT = nil
SettingsSchema.ICONS = nil

return SettingsSchema
