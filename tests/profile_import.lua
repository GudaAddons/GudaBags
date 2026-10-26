-- Harness: profile export/import round trip, and that a hostile import string is
-- rejected instead of freezing the client. Uses the real Core/ProfileManager.lua.

local Stubs = dofile(os.getenv("GUDABAGS_PATH") .. "/tests/stubs.lua")
local ns, LoadFile = Stubs.NewAddon()

ns:RegisterModule("Events", {Register = function() end, Fire = function() end})
LoadFile("Core/Constants.lua")
LoadFile("Core/ProfileManager.lua")

local ProfileManager = ns:GetModule("ProfileManager")
local T = Stubs.NewChecker()

-- Standard base64, same alphabet as ProfileManager's decoder
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function b64(data)
    return ((data:gsub(".", function(x)
        local r, byte = "", x:byte()
        for i = 8, 1, -1 do r = r .. (byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and "1" or "0") end
        return r
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
        if #x < 6 then return "" end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
        return B64:sub(c + 1, c + 1)
    end) .. ({"", "==", "="})[#data % 3 + 1])
end
local function importRaw(serialized)
    return ProfileManager:ImportProfile("!GudaBags:1:" .. b64(serialized))
end

print("Round trip:")
GudaBags_DB = {profiles = {Main = {settings = {iconSize = 37, nested = {deeper = {flag = true}}}}}}
local exported = ProfileManager:ExportProfile("Main")
local ok, data = ProfileManager:ImportProfile(exported)
T.check("export then import succeeds", ok == true and type(data) == "table")
T.check("values survive", ok and data.settings.iconSize == 37 and data.settings.nested.deeper.flag == true)
local okRaw, rawData = importRaw("{1;S8:settings{1;S1:aN5;}}")
T.check("hand-built string imports", okRaw == true and rawData.settings.a == 5)

print("")
print("Hostile input is rejected quickly:")
local started = os.clock()
local okHuge = importRaw("{999999999;")
T.check("huge element count rejected", okHuge == false)
T.check("...without spinning (" .. string.format("%.3f", os.clock() - started) .. "s)", os.clock() - started < 1)
local okDeep = importRaw(string.rep("{1;S1:a", 200) .. "T" .. string.rep("}", 200))
T.check("absurd nesting rejected", okDeep == false)
T.check("garbage rejected", (importRaw("not a profile")) == false)

T.finish("profile import round-trips and rejects hostile strings")
