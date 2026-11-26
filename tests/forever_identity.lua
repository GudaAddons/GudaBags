-- Harness: on WoW: Forever character records are keyed by GUID, named with the
-- surname, cleared of pre-GUID copies, and found by full name for mail to alts.
-- Other flavors keep the "Name-Realm" key.

local Stubs = dofile(os.getenv("GUDABAGS_PATH") .. "/tests/stubs.lua")
local T = Stubs.NewChecker()

wipe = function(t) for k in pairs(t) do t[k] = nil end end
function UnitFactionGroup() return "Horde" end
function UnitLevel() return 10 end
function UnitSex() return 2 end
function GetMoney() return 0 end

-- Who is logged in: name, surname, GUID, realm string, class, race
local player
function UnitName() return player.name, player.surname end
function UnitGUID() return player.guid end
function GetRealmName() return player.realm end
function UnitClass() return "Paladin", player.class end
function UnitRace() return "Undead", player.race end
local surnames = true
function RegionalUniqueNamesEnabled() return surnames end

-- Forever realm: only a ruleset (this one is PvP)
Enum.GameRule = {PvPRuleset = 1, RPRuleset = 2, HardcoreRuleset = 3}
local activeRules = {[1] = true}
C_GameRules = {IsGameRuleActive = function(rule) return activeRules[rule] == true end}

-- One login: fresh addon (the key is cached per session), same saved data
local function Login(p, isForever)
    player = p
    local ns, LoadFile = Stubs.NewAddon()
    ns.IsForever = isForever
    ns:RegisterModule("Events", {
        Register = function() end, Fire = function() end,
        OnAddonLoaded = function() end, OnPlayerLogin = function() end,
    })
    LoadFile("Core/Constants.lua")
    LoadFile("Core/Database.lua")
    local Database = ns:GetModule("Database")
    Database:InitializeCharacter()
    return Database
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local JinVo  = {name = "Jin", surname = "Vo",  guid = "Player-6938-00000001", realm = "", class = "PALADIN", race = "Scourge"}
local JinVoo = {name = "Jin", surname = "Voo", guid = "Player-6938-00000002", realm = "", class = "PALADIN", race = "Scourge"}
local MoMao  = {name = "Mo",  surname = "Mao", guid = "Player-6938-00000003", realm = "", class = "PALADIN", race = "Scourge"}

print("Forever, records saved before the GUID key:")
GudaBags_DB = {
    goldBlacklist = {["Mo-CAMWOW EU5 Realm 4 PvP"] = true},
    characters = {
        ["Mo-CAMWOW EU4 Realm 4 PvP"] = {name = "Mo", realm = "CAMWOW EU4 Realm 4 PvP", class = "PALADIN", race = "Scourge"},
        ["Mo-CAMWOW EU5 Realm 4 PvP"] = {name = "Mo", realm = "CAMWOW EU5 Realm 4 PvP", class = "PALADIN", race = "Scourge"},
        ["Mo-"] = {name = "Mo", realm = "", class = "PALADIN", race = "Scourge"},
        ["Mo Mao-Old Realm"] = {name = "Mo Mao", realm = "Old Realm", class = "PALADIN", race = "Scourge"},
        ["Mo-Other"] = {name = "Mo", realm = "Other", class = "PRIEST", race = "Scourge"},
        ["Jin-CAMWOW EU4 Realm 4 PvP"] = {name = "Jin", realm = "CAMWOW EU4 Realm 4 PvP", class = "PALADIN", race = "Scourge"},
    },
}
local chars = GudaBags_DB.characters

local Database = Login(MoMao, true)
T.check("key is the GUID", Database:GetPlayerFullName() == MoMao.guid)
T.check("record stores the GUID", chars[MoMao.guid] and chars[MoMao.guid].guid == MoMao.guid)
T.check("name includes the surname", chars[MoMao.guid].name == "Mo Mao")
T.check("realm is the ruleset, not the realm string", chars[MoMao.guid].realm == "PvP")
T.check("display name includes the surname", Database:GetPlayerDisplayName() == "Mo Mao")
T.check("old copies under every realm string removed",
    chars["Mo-CAMWOW EU4 Realm 4 PvP"] == nil and chars["Mo-CAMWOW EU5 Realm 4 PvP"] == nil and chars["Mo-"] == nil)
T.check("old full-name copy removed", chars["Mo Mao-Old Realm"] == nil)
T.check("their exclusion entry removed", GudaBags_DB.goldBlacklist["Mo-CAMWOW EU5 Realm 4 PvP"] == nil)
T.check("new record is not excluded", not GudaBags_DB.goldBlacklist[MoMao.guid])
T.check("different class with the same first name kept", chars["Mo-Other"] ~= nil)
T.check("other characters' old records kept", chars["Jin-CAMWOW EU4 Realm 4 PvP"] ~= nil)

print("Forever, two characters sharing a first name:")
Login(JinVo, true)
T.check("shared old record removed", chars["Jin-CAMWOW EU4 Realm 4 PvP"] == nil)
Database = Login(JinVoo, true)
T.check("Jin Vo kept after Jin Voo logs in", chars[JinVo.guid] and chars[JinVo.guid].name == "Jin Vo")
T.check("Jin Voo has its own record", chars[JinVoo.guid] and chars[JinVoo.guid].name == "Jin Voo")
T.check("relogging does not add records", (function()
    local before = Count(chars)
    Login(JinVoo, true)
    return Count(chars) == before
end)())

print("Forever, same-realm filter across sessions:")
JinVoo.realm = "CAMWOW EU5 Realm 4 PvP"
Database = Login(JinVoo, true)
local seen = {}
for _, c in ipairs(Database:GetAllCharacters(false, true)) do seen[c.name] = true end
T.check("alt saved under another realm string still listed", seen["Jin Vo"] and seen["Mo Mao"] and seen["Jin Voo"])

print("Forever, mail recipient lookup:")
T.check("full name finds the alt", Database:FindCharacterKey("Jin Vo") == JinVo.guid)
T.check("case and realm suffix ignored", Database:FindCharacterKey("jin voo-PvP") == JinVoo.guid)
T.check("first name alone is not a match", Database:FindCharacterKey("Jin") == nil)
T.check("unknown name is nil", Database:FindCharacterKey("Nobody Here") == nil)

print("Forever, a surname separator that is not a space:")
Constants = {CharacterNameSeparatorConsts = {CHARACTERNAME_SURNAME_SEPARATOR = "."}}
GudaBags_DB.characters["Ana-Old"] = {name = "Ana", realm = "Old", class = "MAGE", race = "Human"}
local AnaLi = {name = "Ana", surname = "Li", guid = "Player-6938-00000005", realm = "", class = "MAGE", race = "Human"}
Database = Login(AnaLi, true)
T.check("name joined with the client separator", chars[AnaLi.guid].name == "Ana.Li")
T.check("old record still matched by first name", chars["Ana-Old"] == nil)
T.check("typed with a space still finds the alt", Database:FindCharacterKey("Ana Li") == AnaLi.guid)
T.check("separator is not a pattern wildcard", Database:FindCharacterKey("AnaxLi") == nil)
Constants = nil

print("Forever, surnames switched off:")
surnames = false
Database = Login({name = "Solo", surname = "Realm", guid = "Player-6938-00000004", realm = "R", class = "MAGE", race = "Human"}, true)
T.check("second value is not used as a surname", Database:GetPlayerDisplayName() == "Solo")
T.check("still keyed by GUID", Database:GetPlayerFullName() == "Player-6938-00000004")
T.check("realm is the realm name again", chars["Player-6938-00000004"].realm == "R")
surnames = true

print("Other flavors keep Name-Realm:")
GudaBags_DB = {goldBlacklist = {}, characters = {
    ["Mo-Old"] = {name = "Mo", realm = "Old", class = "PALADIN", race = "Scourge"},
}}
chars = GudaBags_DB.characters
Database = Login({name = "Mo", surname = "Realmish", guid = "Player-1-1", realm = "Classic", class = "PALADIN", race = "Scourge"}, false)
T.check("key is Name-Realm", Database:GetPlayerFullName() == "Mo-Classic")
T.check("name has no surname", chars["Mo-Classic"].name == "Mo")
T.check("realm is the realm name", chars["Mo-Classic"].realm == "Classic")
T.check("no guid stored", chars["Mo-Classic"].guid == nil)
T.check("no records removed", chars["Mo-Old"] ~= nil)
T.check("mail lookup adds the realm", Database:FindCharacterKey("Mo") == "Mo-Classic")
T.check("mail lookup by Name-Realm", Database:FindCharacterKey("Mo-Old") == "Mo-Old")
T.check("unknown recipient is nil", Database:FindCharacterKey("Zed") == nil)

T.finish("Forever characters are identified by GUID")
