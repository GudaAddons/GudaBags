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

local DEFAULT_PATH = "Fonts\\ARIALN.TTF"

-- Resolve the currently selected font path.
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

local Events = ns:GetModule("Events")
if Events then
    Events:Register("SETTING_CHANGED", function(_, key)
        if key == "fontFamily" then
            Font:ReapplyAll()
        end
    end, Font)
end
