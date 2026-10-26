-- Harness: every theme in Core/Theme.lua defines the values the UI reads through
-- Theme:GetValue, so switching themes can never index a missing color.

local Stubs = dofile(os.getenv("GUDABAGS_PATH") .. "/tests/stubs.lua")
local ns, LoadFile = Stubs.NewAddon()

local currentTheme = "guda"
local accentSetting = nil
ns:RegisterModule("Database", {GetSetting = function(_, key)
    if key == "theme" then return currentTheme end
    if key == "flatAccentColor" then return accentSetting end
end})
local handlers = {}
ns:RegisterModule("Events", {Register = function(_, event, fn) handlers[event] = fn end})
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

-- Theme:Color is the guarantee that moving literals onto keys changed nothing
-- for the existing themes: they define none of the chrome keys, so they get the
-- call-site literal back exactly.
print("Theme:Color:")
for _, name in ipairs({"guda", "blizzard", "retail"}) do
    currentTheme = name
    local r, g, b, a = Theme:Color("chipBg", 0.15, 0.15, 0.15, 0.8)
    T.check(name .. " gets the literal back", r == 0.15 and g == 0.15 and b == 0.15 and a == 0.8)
end
local CHROME_KEYS = {"panelBg", "panelBorder", "panelBackdrop", "searchBarBg", "searchBarBorder",
    "chipBg", "chipHoverBg", "chipText", "chipActiveType", "chipActiveSpecial", "tabBg", "tabBorder",
    "tabSelectedBorder", "tabSelectedBg", "tabSelectedText", "sideTabBg", "buttonBg", "buttonBorder",
    "buttonHover", "categoryHeaderText", "categoryHeaderLine", "slotEmptyBorder", "slotEmptyFill",
    "flatSlots"}
for _, name in ipairs({"guda", "blizzard", "retail"}) do
    currentTheme = name
    local stray = {}
    for _, key in ipairs(CHROME_KEYS) do
        if Theme:GetValue(key) ~= nil then stray[#stray + 1] = key end
    end
    T.check(name .. " defines no chrome key (" .. table.concat(stray, ",") .. ")", #stray == 0)
end
currentTheme = "flat"
local missing = {}
for _, key in ipairs(CHROME_KEYS) do
    if Theme:GetValue(key) == nil then missing[#missing + 1] = key end
end
T.check("flat defines every chrome key (" .. table.concat(missing, ",") .. ")", #missing == 0)
local r, g, b = Theme:Color("chipBg", 0.15, 0.15, 0.15, 0.8)
T.check("flat overrides it", r ~= 0.15)
local _, _, _, a3 = Theme:Color("nonexistentKey", 1, 1, 1)
T.check("missing alpha defaults to 1", a3 == 1)

-- Paint repaints when the theme setting changes
print("Theme:Paint:")
currentTheme = "guda"
local last = {}
local fakeTexture = {SetVertexColor = function(_, ...) last = {...} end}
Theme:Paint(fakeTexture, "SetVertexColor", "categoryHeaderLine", 0.3, 0.3, 0.3, 0.8)
T.check("painted with the literal under guda", last[1] == 0.3)
currentTheme = "flat"
handlers.SETTING_CHANGED("SETTING_CHANGED", "theme")
T.check("repainted with flat's color on theme change", last[1] ~= 0.3)
local order = {}
local fakeFrame = {
    SetBackdrop = function() order[#order + 1] = "backdrop" end,
    SetBackdropColor = function() order[#order + 1] = "color" end,
}
Theme:PaintBackdrop(fakeFrame, "panelBackdrop", {})
Theme:Paint(fakeFrame, "SetBackdropColor", "panelBg", 0.1, 0.1, 0.1, 0.95)
order = {}
handlers.SETTING_CHANGED("SETTING_CHANGED", "theme")
T.check("repaint sets the backdrop before its colors", order[1] == "backdrop" and order[2] == "color")

print("Flat accent color:")
currentTheme = "flat"
accentSetting = nil
handlers.SETTING_CHANGED("SETTING_CHANGED", "flatAccentColor")
local def = Theme:GetDefaultFlatAccent()
local ar, ag, ab = Theme:Color("tabSelectedBorder", 0, 0, 0, 1)
T.check("no setting -> default teal", ar == def[1] and ag == def[2] and ab == def[3])
accentSetting = {1, 0, 0}
handlers.SETTING_CHANGED("SETTING_CHANGED", "flatAccentColor")
local allRed = true
for _, key in ipairs({"accent", "chipActiveType", "chipActiveSpecial", "tabSelectedBorder", "tabSelectedText"}) do
    local r, g, b = Theme:Color(key, 0, 0, 0, 1)
    if not (r == 1 and g == 0 and b == 0) then allRed = false end
end
T.check("picked color reaches all five accent keys", allRed)
local _, _, _, chipAlpha = Theme:Color("chipActiveType", 0, 0, 0, 1)
T.check("each key keeps its own alpha (chips 0.9)", chipAlpha == 0.9)
local nr = Theme:Color("chipBg", 0, 0, 0, 1)
T.check("non-accent keys are untouched", nr ~= 1)
currentTheme = "guda"
local gr = Theme:Color("tabSelectedBorder", 1, 0.82, 0, 1)
T.check("other themes ignore the accent setting", gr == 1)
accentSetting = nil
currentTheme = "flat"
handlers.SETTING_CHANGED("SETTING_CHANGED", "flatAccentColor")
local rr = Theme:Color("accent", 0, 0, 0, 1)
T.check("Reset (setting cleared) restores teal", rr == def[1])

T.finish("every theme defines the values the UI reads")
