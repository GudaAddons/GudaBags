local addonName, ns = ...

local Utils = {}
ns:RegisterModule("Utils", Utils)

-------------------------------------------------
-- UTF-8 aware lowercase
--
-- string.lower only folds A-Z, so on a Russian client "Оружие" and a typed
-- "оружие" never match, and the same holds for accented European letters
-- (Épée / épée, Rüstung / rüstung). Search compares both sides through this
-- instead.
--
-- Every character that needs folding for the supported locales lives in
-- U+0080..U+07FF, which is always a 2-byte UTF-8 sequence, so the table is
-- generated from codepoint ranges rather than written out by hand. CJK and
-- Korean need no entries — those scripts have no case.
-------------------------------------------------

local strfind, strlower, strgsub = string.find, string.lower, string.gsub

local UTF8_LOWER = {}
do
    -- Encode a codepoint in U+0080..U+07FF as its 2-byte UTF-8 sequence
    local function Char2(cp)
        return string.char(192 + math.floor(cp / 64), 128 + (cp % 64))
    end

    local function AddRange(fromCp, toCp, delta, skip)
        for cp = fromCp, toCp do
            if cp ~= skip then
                UTF8_LOWER[Char2(cp)] = Char2(cp + delta)
            end
        end
    end

    -- Latin-1 Supplement À..Þ, skipping × (U+00D7), which is not a letter.
    -- Covers frFR, deDE, esES, ptBR and itIT accented capitals.
    AddRange(0x00C0, 0x00DE, 0x20, 0x00D7)
    -- Cyrillic А..Я and the Ѐ..Џ block (ruRU)
    AddRange(0x0410, 0x042F, 0x20)
    AddRange(0x0400, 0x040F, 0x50)
    -- Ÿ (U+0178) is the one frFR capital outside Latin-1 Supplement
    UTF8_LOWER[Char2(0x0178)] = Char2(0x00FF)
end

-- A-Z folded by explicit byte range. string.lower would be shorter, but on
-- some builds the C locale's tolower also rewrites bytes >= 0x80 and corrupts
-- the multi-byte sequences we just folded. Lua pattern ranges are byte-based,
-- so [A-Z] is locale-independent.
local ASCII_LOWER = {}
for b = 65, 90 do
    ASCII_LOWER[string.char(b)] = string.char(b + 32)
end

-- Lowercase a string, folding the non-ASCII letters the locales above use.
-- Pure-ASCII input (the common case) takes the plain string.lower fast path.
function Utils:UTF8Lower(text)
    if not text or text == "" then
        return text
    end
    -- Pure ASCII: nothing multi-byte to protect, so use the fast C path
    if not strfind(text, "[\128-\255]") then
        return strlower(text)
    end
    -- Fold the multi-byte capitals, then the ASCII ones, both by byte range so
    -- the result never depends on the C locale.
    local folded = strgsub(text, "[\194-\211][\128-\191]", UTF8_LOWER)
    return (strgsub(folded, "[A-Z]", ASCII_LOWER))
end

-------------------------------------------------
-- Item Key Generation
-- Creates a unique key for an item based on its properties
-- Used for button reuse optimization in category view
-------------------------------------------------

-- Generate unique key for an item (for button reuse in category view)
-- Items with same key can share buttons
function Utils:GetItemKey(itemData)
    if not itemData then return nil end
    -- Key based on: itemLink (or itemID), quality, bound status
    -- This matches items that are visually identical
    local link = itemData.link or ""
    local quality = itemData.quality or 0
    local isBound = itemData.isBound and "1" or "0"
    return link .. ":" .. quality .. ":" .. isBound
end

-------------------------------------------------
-- Slot Key Generation
-- Creates a unique key for a bag slot position
-------------------------------------------------

-- Generate slot key for tracking (bagID:slot)
function Utils:GetSlotKey(bagID, slot)
    return bagID .. ":" .. slot
end

-------------------------------------------------
-- Table Utilities
-------------------------------------------------

-- Deep copy a table
function Utils:DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[self:DeepCopy(k)] = self:DeepCopy(v)
        end
        setmetatable(copy, self:DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Count entries in a table (for tables with non-numeric keys)
function Utils:TableCount(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Check if table is empty
function Utils:IsTableEmpty(tbl)
    if not tbl then return true end
    return next(tbl) == nil
end

-------------------------------------------------
-- Race Icons
-------------------------------------------------

local raceCorrections = {
    ["scourge"] = "undead",
    ["zandalaritroll"] = "zandalari",
    ["highmountaintauren"] = "highmountain",
    ["lightforgeddraenei"] = "lightforged",
    ["earthendwarf"] = "earthen",
}

local genders = {"unknown", "male", "female"}

-- Get inline race icon atlas string for use in text
-- race: internal race token from select(2, UnitRace("player"))
-- sex: gender index from UnitSex("player") (1=unknown, 2=male, 3=female)
function Utils:GetRaceIcon(race, sex)
    if not race then return "" end

    local raceLower = race:lower()
    raceLower = raceCorrections[raceLower] or raceLower
    local gender = genders[sex or 2] or "male"
    local prefix = ns.IsRetail and "raceicon128" or "raceicon"

    return "|A:" .. prefix .. "-" .. raceLower .. "-" .. gender .. ":13:13|a"
end

-------------------------------------------------
-- Money Formatting
-------------------------------------------------

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:12|t"

-- Format money with gold and silver only (for inline/compact display)
function Utils:FormatMoneyShort(amount)
    if not amount or amount == 0 then return "" end

    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)

    local result = ""
    if gold > 0 then
        result = string.format("%d%s", gold, GOLD_ICON)
    end
    if silver > 0 then
        if result ~= "" then result = result .. " " end
        result = result .. string.format("%d%s", silver, SILVER_ICON)
    end
    return result
end

-------------------------------------------------
-- Item Border Creation
-- Creates quality border frame on item buttons
-- Used by ItemButton, QuestBar, TrackedBar
-------------------------------------------------

function Utils:CreateItemBorder(button)
    local Constants = ns.Constants
    local BORDER_THICKNESS = Constants.ICON.BORDER_THICKNESS

    local borderFrame = CreateFrame("Frame", nil, button, "BackdropTemplate")
    borderFrame:SetPoint("TOPLEFT", button, "TOPLEFT", -BORDER_THICKNESS, BORDER_THICKNESS)
    borderFrame:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", BORDER_THICKNESS, -BORDER_THICKNESS)
    borderFrame:SetFrameLevel(button:GetFrameLevel() + Constants.FRAME_LEVELS.BORDER)

    borderFrame:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left = 2, right = 2, top = 2, bottom = 2},
    })
    borderFrame:Hide()

    borderFrame.SetVertexColor = function(self, r, g, b, a)
        self:SetBackdropBorderColor(r, g, b, a)
    end

    return borderFrame
end

-------------------------------------------------
-- Masque-aware NormalTexture hiding
-- Used by ItemButton, TrackedBar, QuestBar
-------------------------------------------------

function Utils:HideNormalTexture(button)
    local MasqueModule = ns:GetModule("Masque")
    local masqueActive = MasqueModule and MasqueModule:IsActive()
    local normalTex = button:GetNormalTexture()
    if normalTex then
        if masqueActive then
            normalTex:Hide()
        else
            normalTex:SetTexture(nil)
            normalTex:Hide()
        end
    end
    if masqueActive then
        button.SetNormalTexture = function() end
    end
end

-------------------------------------------------
-- Inner shadow/glow creation
-- Used by ItemButton, QuestBar
-------------------------------------------------

function Utils:CreateInnerShadow(button, shadowSize)
    local innerShadow = {
        top = button:CreateTexture(nil, "ARTWORK", nil, 1),
        bottom = button:CreateTexture(nil, "ARTWORK", nil, 1),
        left = button:CreateTexture(nil, "ARTWORK", nil, 1),
        right = button:CreateTexture(nil, "ARTWORK", nil, 1),
    }
    -- Top edge
    innerShadow.top:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    innerShadow.top:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    innerShadow.top:SetHeight(shadowSize)
    innerShadow.top:SetTexture("Interface\\Buttons\\WHITE8x8")
    innerShadow.top:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.6))
    -- Bottom edge
    innerShadow.bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    innerShadow.bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    innerShadow.bottom:SetHeight(shadowSize)
    innerShadow.bottom:SetTexture("Interface\\Buttons\\WHITE8x8")
    innerShadow.bottom:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.6), CreateColor(0, 0, 0, 0))
    -- Left edge
    innerShadow.left:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    innerShadow.left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    innerShadow.left:SetWidth(shadowSize)
    innerShadow.left:SetTexture("Interface\\Buttons\\WHITE8x8")
    innerShadow.left:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.6), CreateColor(0, 0, 0, 0))
    -- Right edge
    innerShadow.right:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    innerShadow.right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    innerShadow.right:SetWidth(shadowSize)
    innerShadow.right:SetTexture("Interface\\Buttons\\WHITE8x8")
    innerShadow.right:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.6))
    -- Hide by default
    for _, tex in pairs(innerShadow) do tex:Hide() end
    return innerShadow
end

-------------------------------------------------
-- Profession Tool Detection
-- Fishing poles, mining picks, skinning knives, etc.
-------------------------------------------------

function Utils:IsProfessionTool(itemData)
    -- Check by item ID first
    local Constants = ns.Constants
    if itemData.itemID and Constants.PROFESSION_TOOL_IDS[itemData.itemID] then
        return true
    end

    -- Check fishing poles by class/subclass (locale-independent)
    local fishingPole = Constants.ITEM_SUBCLASS_FISHING_POLE
    if itemData.classID == fishingPole[1] and itemData.subClassID == fishingPole[2] then
        return true
    end

    -- Check fishing poles by subtype (enUS clients, and itemData without classID)
    local subtype = itemData.itemSubType
    if subtype == "Fishing Poles" or subtype == "Fishing Pole" then
        return true
    end

    -- Check by name patterns
    local name = itemData.name
    if name then
        if name:find("Mining Pick") or name:find("Skinning Knife") or
           name:find("Blacksmith Hammer") or name:find("Runed.*Rod") or
           name:find("Philosopher's Stone") or name:find("Alchemist") or
           name:find("Spanner") or name:find("Gyromatic") then
            return true
        end
    end

    return false
end

-- Broader tool test, for JUNK SUPPRESSION ONLY — never for categorization.
--
-- IsProfessionTool above is precise: itemIDs, fishing poles, then English name
-- patterns. Those name patterns only fire on an enUS client, so an unlisted
-- tool (a newer expansion's pickaxe, say) used to be treated as junk on a
-- zhCN client but not on enUS. That asymmetry is what this fixes.
--
-- It adds the "miscellaneous weapon" subclass that most physical tools share.
-- That net is deliberately broad, which is safe here because a false positive
-- only means "don't auto-mark as junk", while a miss risks flagging someone's
-- tool for the vendor. It is kept out of the category rules on purpose: there a
-- false positive would pull genuine weapons out of the Weapon category, and
-- categorization is already locale-consistent without it.
function Utils:IsToolLike(itemData)
    if self:IsProfessionTool(itemData) then
        return true
    end

    local Constants = ns.Constants
    local toolSubClass = Constants.TOOL_WEAPON_SUBCLASS
    return toolSubClass ~= nil
        and itemData.classID == Constants.ITEM_CLASS.WEAPON
        and itemData.subClassID == toolSubClass
end

-- Format money with all denominations (for totals/summaries)
function Utils:FormatMoneyFull(amount)
    if not amount or amount == 0 then return "" end

    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local copper = amount % 100

    local result = ""
    if gold > 0 then
        result = string.format("%d%s", gold, GOLD_ICON)
    end
    if silver > 0 then
        if result ~= "" then result = result .. " " end
        result = result .. string.format("%d%s", silver, SILVER_ICON)
    end
    if copper > 0 or result == "" then
        if result ~= "" then result = result .. " " end
        result = result .. string.format("%d%s", copper, COPPER_ICON)
    end
    return result
end
