-- Harness: every theme in Core/Theme.lua defines the values the UI reads through
-- Theme:GetValue, so switching themes can never index a missing color.

local Stubs = dofile(os.getenv("GUDABAGS_PATH") .. "/tests/stubs.lua")
local ns, LoadFile = Stubs.NewAddon()

local currentTheme = "guda"
ns:RegisterModule("Database", {GetSetting = function(_, key)
    if key == "theme" then return currentTheme end
end})
ns:RegisterModule("Events", {Register = function() end})
ns.ExpansionFeatures = {HasRetailFrameArt = false}
LoadFile("Core/Theme.lua")

local Theme = ns:GetModule("Theme")
local T = Stubs.NewChecker()

-- Color keys read with [1]..[3]/[4] somewhere in the UI
local COLOR_KEYS = {"frameBg", "frameBorder", "headerBg", "footerButtonBg", "footerButtonBorder"}

local function isColor(c)
    return type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number"
        and type(c[3]) == "number"
end

for _, name in ipairs({"guda", "blizzard", "retail", "flat"}) do
    print(name .. ":")
    currentTheme = name  -- Theme:Get() caches by name, so this switches it
    local t = Theme:Get()
    for _, key in ipairs(COLOR_KEYS) do
        T.check(name .. "." .. key .. " is a color", isColor(Theme:GetValue(key)))
    end
    -- A theme must draw its frame one way or another
    T.check(name .. " has a frame style",
        t.useBlizzardFrame or t.useMetalFrame or type(t.backdrop) == "table")
end

currentTheme = "flat"
print("flat specifics:")
T.check("flat accent is a color", isColor(Theme:GetValue("accent")))
T.check("flat backdrop is a 1px solid border", Theme:GetValue("backdrop").edgeSize == 1)
T.check("flat draws a header bar", Theme:GetValue("headerBackdrop") ~= nil)
T.check("flat uses the flat close button", Theme:GetValue("useFlatCloseButton") == true)

T.finish("every theme defines the values the UI reads")
