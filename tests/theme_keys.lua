-- Harness: every theme in Core/Theme.lua defines the values the UI reads through
-- Theme:GetValue, so switching themes can never index a missing color.

local Stubs = dofile(os.getenv("GUDABAGS_PATH") .. "/tests/stubs.lua")
local ns, LoadFile = Stubs.NewAddon()

local currentTheme = "guda"
local windowSetting = nil
local opacitySetting = 100
ns:RegisterModule("Database", {GetSetting = function(_, key)
    if key == "theme" then return currentTheme end
    if key == "flatWindowColor" then return windowSetting end
    if key == "bgAlpha" then return opacitySetting end
end})
-- Every listener per event (Font and Theme both watch SETTING_CHANGED)
local handlers = {}
ns:RegisterModule("Events", {Register = function(_, event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
end})
local function settingChanged(key)
    for _, fn in ipairs(handlers.SETTING_CHANGED or {}) do fn("SETTING_CHANGED", key) end
end
ns.ExpansionFeatures = {HasRetailFrameArt = false}
LoadFile("Core/Theme.lua")
LoadFile("Core/Font.lua")

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
    "flatSlots", "headerLine"}
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
settingChanged("theme")
T.check("repainted with flat's color on theme change", last[1] ~= 0.3)
local order = {}
local fakeFrame = {
    SetBackdrop = function() order[#order + 1] = "backdrop" end,
    SetBackdropColor = function() order[#order + 1] = "color" end,
}
Theme:PaintBackdrop(fakeFrame, "panelBackdrop", {})
Theme:Paint(fakeFrame, "SetBackdropColor", "panelBg", 0.1, 0.1, 0.1, 0.95)
order = {}
settingChanged("theme")
T.check("repaint sets the backdrop before its colors", order[1] == "backdrop" and order[2] == "color")

print("Flat window color:")
currentTheme = "flat"
windowSetting = nil
settingChanged("flatWindowColor")
local def = Theme:GetDefaultFlatWindowColor()
local fr, fg, fb = Theme:Color("frameBg", 0, 0, 0, 1)
T.check("no setting -> default dark background", fr == def[1] and fg == def[2] and fb == def[3])
windowSetting = {0.5, 0.2, 0.8}
settingChanged("flatWindowColor")
local br = Theme:Color("frameBg", 0, 0, 0, 1)
T.check("window background is exactly the chosen color", br == 0.5)
local hr = Theme:Color("headerBg", 0, 0, 0, 1)
local er, eg, eb = Theme:Color("frameBorder", 0, 0, 0, 1)
local lr = Theme:Color("headerLine", 0, 0, 0, 1)
T.check("title bar is a darker shade", hr < 0.5 and hr > er)
T.check("border is a clearly darker shade of the same color",
    er < hr and math.abs(er / eg - 0.5 / 0.2) < 1e-6 and math.abs(eb / er - 0.8 / 0.5) < 1e-6)
T.check("header line matches the border shade", lr == er)
local sfr = Theme:Color("slotEmptyFill", 0, 0, 0, 1)
local sor, sog = Theme:Color("slotEmptyBorder", 0, 0, 0, 1)
T.check("empty slot fill is a darker shade of the window color", sfr < 0.5 and sfr > sor)
T.check("empty slot outline is darker still, same hue", math.abs(sor / sog - 0.5 / 0.2) < 1e-6)
local allHue = true
for _, key in ipairs({"footerButtonBg", "footerButtonBorder", "buttonBg", "chipBg", "tabBg",
        "panelBg", "searchBarBg", "categoryHeaderLine"}) do
    local r, g = Theme:Color(key, 0, 0, 0, 1)
    if not (r < 0.5 and math.abs(r / g - 0.5 / 0.2) < 1e-6) then allHue = false end
end
T.check("footer bag slots, buttons, chips, tabs and menus follow the window hue, darker", allHue)
local tr = Theme:Color("tabSelectedBorder", 0, 0, 0, 1)
T.check("selected tabs keep the fixed teal", math.abs(tr - 0.247) < 1e-6)
currentTheme = "guda"
local gr = Theme:Color("frameBg", 0.08, 0.08, 0.08, 1)
T.check("other themes ignore the window color", gr ~= 0.5)
windowSetting = nil
currentTheme = "flat"
settingChanged("flatWindowColor")
local rr = Theme:Color("frameBg", 0, 0, 0, 1)
T.check("Reset (setting cleared) restores the dark default", rr == def[1])

print("Background opacity:")
currentTheme = "flat"
opacitySetting = 50
settingChanged("bgAlpha")
local _, _, _, sa = Theme:Color("searchBarBg", 0, 0, 0, 1)
local _, _, _, fa = Theme:Color("footerButtonBg", 0, 0, 0, 1)
local _, _, _, fba = Theme:Color("footerButtonBorder", 0, 0, 0, 1)
T.check("flat search bar fades with opacity", math.abs(sa - 0.5) < 1e-6)
T.check("flat footer buttons and their outline fade with opacity", math.abs(fa - 0.5) < 1e-6 and math.abs(fba - 0.5) < 1e-6)
local _, _, _, wa = Theme:Color("frameBg", 0, 0, 0, 1)
T.check("window background is not faded twice (it gets the opacity separately)", wa == 1)
windowSetting = {0.5, 0.2, 0.8}
settingChanged("flatWindowColor")
local _, _, _, ca = Theme:Color("searchBarBg", 0, 0, 0, 1)
T.check("fade also applies on top of a window color", math.abs(ca - 0.5) < 1e-6)
currentTheme = "guda"
local _, _, _, ga = Theme:Color("footerButtonBg", 0, 0, 0, 1)
T.check("other themes keep their footer buttons solid", ga == 1)
opacitySetting = 100
windowSetting = nil
settingChanged("bgAlpha")

-- Text shadow: on under Flat, and leaving Flat restores each string's OWN shadow
-- (GameFont templates ship one) rather than clearing it.
print("Text shadow:")
local Font = ns:GetModule("Font")
local function FakeFontString(ox, oy)
    local fs = {offset = {ox, oy}, color = {0, 0, 0, 0.5}}
    function fs:SetFont() end
    function fs:GetFont() return "font", 12, "" end
    function fs:GetShadowOffset() return self.offset[1], self.offset[2] end
    function fs:SetShadowOffset(x, y) self.offset = {x, y} end
    function fs:GetShadowColor() return (table.unpack or unpack)(self.color) end
    function fs:SetShadowColor(r, g, b, a) self.color = {r, g, b, a} end
    return fs
end
currentTheme = "guda"
local plain = FakeFontString(0, 0)
local templated = FakeFontString(2, -2)
Font:Apply(plain, 12, "")
Font:Apply(templated, 12, "")
T.check("guda leaves shadows alone", plain.offset[1] == 0 and templated.offset[1] == 2)
currentTheme = "flat"
settingChanged("theme")
T.check("flat adds a shadow", plain.offset[1] == 1 and plain.offset[2] == -1 and plain.color[4] == 1)
currentTheme = "guda"
settingChanged("theme")
T.check("leaving flat restores no-shadow text", plain.offset[1] == 0 and plain.offset[2] == 0)
T.check("leaving flat restores a template's own shadow",
    templated.offset[1] == 2 and templated.offset[2] == -2 and templated.color[4] == 0.5)

T.finish("every theme defines the values the UI reads")
