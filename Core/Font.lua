local addonName, ns = ...

-------------------------------------------------
-- Font
-- Central font family selection. Every font string in the addon routes
-- through here so a single setting ("fontFamily") drives the family used
-- everywhere, and changing it re-applies live without rebuilding frames.
-------------------------------------------------
local Font = {}
ns:RegisterModule("Font", Font)

local Database

-- Weak keys so discarded font strings can still be collected. Each entry
-- remembers the size/flags last applied so ReapplyAll can re-set the family
-- while preserving the per-string sizing.
local registry = setmetatable({}, { __mode = "k" })

-- Top-level frames whose region tree should be re-swept on a font change, so
-- text created lazily (purchase prompts, log entries, list rows, …) picks up
-- the selected family without each site needing an explicit Apply call.
local sweptFrames = setmetatable({}, { __mode = "k" })

-- Ultimate fallback only used before the Database/Constants are available
-- (effectively never for UI). STANDARD_TEXT_FONT is the client's locale font.
local DEFAULT_PATH = STANDARD_TEXT_FONT or "Fonts\\ARIALN.TTF"

-- Resolve the currently selected font path. Database:GetSetting already falls
-- back to Constants.DEFAULTS.fontFamily (locale-aware) when nothing is set.
function Font:GetFont()
    Database = Database or ns:GetModule("Database")
    return (Database and Database:GetSetting("fontFamily")) or DEFAULT_PATH
end

-- Apply the selected font with an explicit size/flags. Use for numeric/text
-- sites that own a specific (often dynamic) size. When size is omitted the
-- string's current size/flags are kept.
function Font:Apply(fontString, size, flags)
    if not fontString or not fontString.SetFont then return end
    if not size then
        local _, curSize, curFlags = fontString:GetFont()
        size = curSize or 12
        flags = flags or curFlags
    end
    registry[fontString] = { size = size, flags = flags }
    fontString:SetFont(self:GetFont(), size, flags)
end

-- Swap only the family on a string that already has its size/flags set
-- (e.g. created from a GameFont* template). Preserves Blizzard's sizing.
function Font:Override(fontString)
    if not fontString or not fontString.GetFont then return end
    local _, size, flags = fontString:GetFont()
    self:Apply(fontString, size, flags)
end

-- Recursively swap the family on every FontString in a frame's region tree,
-- preserving each string's own size/flags. EditBoxes are handled by the
-- explicit Apply/Override sites since they are not FontStrings.
function Font:ApplyToRegions(frame)
    if not frame then return end
    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.GetObjectType and region:GetObjectType() == "FontString" then
                self:Override(region)
            end
        end
    end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            self:ApplyToRegions(child)
        end
    end
end

-- Register a top-level frame: sweep it now and re-sweep on every font change.
function Font:RegisterFrame(frame)
    if not frame then return end
    sweptFrames[frame] = true
    self:ApplyToRegions(frame)
end

-- Re-set the family on every registered string at its remembered size/flags,
-- then re-sweep registered frames to catch any text created since.
function Font:ReapplyAll()
    local path = self:GetFont()
    for fs, info in pairs(registry) do
        if fs.SetFont then
            fs:SetFont(path, info.size, info.flags)
        end
    end
    for frame in pairs(sweptFrames) do
        self:ApplyToRegions(frame)
    end
end

-------------------------------------------------
-- Tooltip styling (scoped to GudaBags-owned tooltips)
-- The header/footer button hints use the global GameTooltip. We only restyle
-- it while it belongs to one of our frames, and revert on hide so the rest of
-- the game's tooltips (and full item tooltips) are left untouched.
-------------------------------------------------
local tooltipDidStyle = false
local styledLines = {}

local function IsGudaOwned(frame)
    local guard = 0
    while frame and guard < 60 do
        if sweptFrames[frame] then return true end
        local parent = frame.GetParent and frame:GetParent()
        if parent == frame then break end
        frame = parent
        guard = guard + 1
    end
    return false
end

-- True if the tooltip is showing an item (so we leave it on the default font).
-- TooltipUtil.GetDisplayedItem is the modern/retail path (GameTooltip:GetItem
-- was deprecated and returns nil there); GetItem is the Classic fallback.
local function TooltipShowsItem(tt)
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        local _, link = TooltipUtil.GetDisplayedItem(tt)
        if link then return true end
    end
    if tt.GetItem then
        local _, link = tt:GetItem()
        if link then return true end
    end
    return false
end

function Font:InitTooltipStyling()
    if self._tooltipHooked or not GameTooltip then return end
    self._tooltipHooked = true

    GameTooltip:HookScript("OnShow", function(tt)
        -- Never touch full item tooltips or tooltips that aren't ours.
        if TooltipShowsItem(tt) then return end
        if not IsGudaOwned(tt.GetOwner and tt:GetOwner()) then return end

        local name = tt:GetName()
        if not name then return end
        local path = self:GetFont()
        wipe(styledLines)
        for i = 1, tt:NumLines() do
            for _, side in ipairs({ "Left", "Right" }) do
                local fs = _G[name .. "Text" .. side .. i]
                if fs and fs:IsShown() then
                    local curPath, size, flags = fs:GetFont()
                    if size then
                        -- Capture the original font two ways so the revert can
                        -- never fail: the font object (may be nil if a prior raw
                        -- SetFont detached it) AND the raw font, which GetFont
                        -- always returns even when the object is detached.
                        fs.__gudaFontObj = fs:GetFontObject()
                        fs.__gudaPrevFont = { curPath, size, flags }
                        fs:SetFont(path, size, flags)
                        styledLines[#styledLines + 1] = fs
                    end
                end
            end
        end
        tooltipDidStyle = #styledLines > 0
    end)

    GameTooltip:HookScript("OnHide", function()
        if not tooltipDidStyle then return end
        tooltipDidStyle = false
        for _, fs in ipairs(styledLines) do
            -- Always revert so the GudaBags font never lingers on the shared
            -- GameTooltip lines. Prefer the font object (re-links to the dynamic
            -- default); fall back to the raw font when no object was present.
            if fs.__gudaFontObj then
                fs:SetFontObject(fs.__gudaFontObj)
            elseif fs.__gudaPrevFont then
                fs:SetFont(fs.__gudaPrevFont[1], fs.__gudaPrevFont[2], fs.__gudaPrevFont[3])
            end
            fs.__gudaFontObj = nil
            fs.__gudaPrevFont = nil
        end
        wipe(styledLines)
    end)
end

local Events = ns:GetModule("Events")
if Events then
    Events:Register("SETTING_CHANGED", function(_, key)
        if key == "fontFamily" then
            Font:ReapplyAll()
        end
    end, Font)
end

Font:InitTooltipStyling()
