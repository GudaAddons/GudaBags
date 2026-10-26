-- Harness: Database:PruneOldGuildBanks drops guild banks not opened in 90 days,
-- keeps the current character's guild, and never deletes a bank of unknown age.

local Stubs = dofile(os.getenv("GUDABAGS_PATH") .. "/tests/stubs.lua")
local ns, LoadFile = Stubs.NewAddon()

ns:RegisterModule("Events", {
    Register = function() end, Fire = function() end,
    OnAddonLoaded = function() end, OnPlayerLogin = function() end,
})
wipe = function(t) for k in pairs(t) do t[k] = nil end end
LoadFile("Core/Constants.lua")
LoadFile("Core/Database.lua")

local Database = ns:GetModule("Database")
local T = Stubs.NewChecker()

local DAY = 24 * 60 * 60
local now = os.time()
GudaBags_DB = {guildBanks = {
    Fresh   = {lastUpdate = now - 10 * DAY, tabs = {}},
    Stale   = {lastUpdate = now - 200 * DAY, tabs = {}},
    Mine    = {lastUpdate = now - 400 * DAY, tabs = {}},
    Unknown = {tabs = {}},
}}

print("Pruning:")
local removed = Database:PruneOldGuildBanks("Mine")
local banks = GudaBags_DB.guildBanks
T.check("one bank removed (got " .. removed .. ")", removed == 1)
T.check("bank opened 200 days ago is dropped", banks.Stale == nil)
T.check("bank opened 10 days ago is kept", banks.Fresh ~= nil)
T.check("current guild kept however old", banks.Mine ~= nil)
T.check("bank of unknown age kept", banks.Unknown ~= nil)
T.check("...and its clock started now", banks.Unknown.lastUpdate == now or banks.Unknown.lastUpdate == now + 1)
T.check("second run removes nothing", Database:PruneOldGuildBanks("Mine") == 0)
GudaBags_DB = {}
T.check("no guild banks at all is fine", Database:PruneOldGuildBanks(nil) == 0)

T.finish("old guild banks are pruned safely")
