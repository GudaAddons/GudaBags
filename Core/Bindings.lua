local addonName, ns = ...

local L = ns.L

-- Binding category header (must match category name in Bindings.xml)
BINDING_HEADER_GudaBags = L["BINDING_HEADER"]

-- Binding names
BINDING_NAME_GUDABAGS_TOGGLE = L["BINDING_TOGGLE_BAGS"]
BINDING_NAME_GUDABAGS_TOGGLE_BANK = L["BINDING_TOGGLE_BANK"]

-- Click bindings for secure buttons (item usage)
_G["BINDING_NAME_CLICK GudaQuestBarMainButton:RightButton"] = L["BINDING_USE_QUEST_ITEM"]
_G["BINDING_NAME_CLICK GudaTrackedItem1:RightButton"] = string.format(L["BINDING_USE_TRACKED_ITEM"], 1)
_G["BINDING_NAME_CLICK GudaTrackedItem2:RightButton"] = string.format(L["BINDING_USE_TRACKED_ITEM"], 2)
_G["BINDING_NAME_CLICK GudaTrackedItem3:RightButton"] = string.format(L["BINDING_USE_TRACKED_ITEM"], 3)
_G["BINDING_NAME_CLICK GudaTrackedItem4:RightButton"] = string.format(L["BINDING_USE_TRACKED_ITEM"], 4)
_G["BINDING_NAME_CLICK GudaTrackedItem5:RightButton"] = string.format(L["BINDING_USE_TRACKED_ITEM"], 5)
_G["BINDING_NAME_CLICK GudaTrackedItem6:RightButton"] = string.format(L["BINDING_USE_TRACKED_ITEM"], 6)
_G["BINDING_NAME_CLICK GudaTrackedItem7:RightButton"] = string.format(L["BINDING_USE_TRACKED_ITEM"], 7)
_G["BINDING_NAME_CLICK GudaTrackedItem8:RightButton"] = string.format(L["BINDING_USE_TRACKED_ITEM"], 8)
_G["BINDING_NAME_CLICK GudaTrackedItem9:RightButton"] = string.format(L["BINDING_USE_TRACKED_ITEM"], 9)
_G["BINDING_NAME_CLICK GudaTrackedItem10:RightButton"] = string.format(L["BINDING_USE_TRACKED_ITEM"], 10)
_G["BINDING_NAME_CLICK GudaTrackedItem11:RightButton"] = string.format(L["BINDING_USE_TRACKED_ITEM"], 11)
_G["BINDING_NAME_CLICK GudaTrackedItem12:RightButton"] = string.format(L["BINDING_USE_TRACKED_ITEM"], 12)

-- Global functions for keybindings
function GudaBags_Toggle()
    local BagFrame = ns:GetModule("BagFrame")
    if BagFrame then
        BagFrame:Toggle()
    end
end

function GudaBags_ToggleBank()
    local BankFrame = ns:GetModule("BankFrame")
    if BankFrame then
        BankFrame:Toggle()
    end
end
