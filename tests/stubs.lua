-- Shared WoW API stubs + addon loader for the offline harnesses.
--
-- Usage (from a harness):
--   local Stubs = dofile(os.getenv("GUDABAGS_PATH") .. "/tests/stubs.lua")
--   local ns, LoadFile = Stubs.NewAddon()
--
-- Only what Init/Constants/Utils/DefaultCategories/RuleEngine/Rules touch at
-- load time is stubbed; each harness registers its own Database stub.

local ADDON = os.getenv("GUDABAGS_PATH")

local CLASS_NAMES = {[0]="Consumable",[1]="Container",[2]="Weapon",[3]="Gem",[4]="Armor",
    [5]="Reagent",[6]="Projectile",[7]="Trade Goods",[9]="Recipe",
    [11]="Quiver",[12]="Quest",[13]="Key",[15]="Miscellaneous",[16]="Glyph"}

function GetItemClassInfo(classID) return CLASS_NAMES[classID] end
function GetItemSubClassInfo() return nil end
function GetLocale() return "enUS" end
function UnitClass() return "Warlock", "WARLOCK" end
function UnitName() return "Tester" end
function CreateFrame() return setmetatable({}, {__index = function() return function() end end}) end
function GetItemInfoInstant() return nil end
function time() return os.time() end

C_AddOns = {GetAddOnMetadata = function() return "0.0.0" end}
C_Timer = {After = function(_, fn) fn() end, NewTicker = function() return {Cancel = function() end} end}
C_Container = {}
C_Item = {}
Enum = {ItemClass = {Quiver = 11, Container = 1}, BagIndex = {}}
bit = {band = function(a, b)
    local res, shift = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then res = res + shift end
        a, b, shift = math.floor(a / 2), math.floor(b / 2), shift * 2
    end
    return res
end}

string.join = function(sep, ...) return table.concat({...}, sep) end
tostringall = function(...) return ... end

ITEM_SPELL_TRIGGER_ONUSE = "Use:"
ITEM_SPELL_TRIGGER_ONEQUIP = "Equip:"
STANDARD_TEXT_FONT = "Fonts\\LOCALE_STANDARD.TTF"

local Stubs = {}

-- Fresh namespace with Init loaded and an Expansion stub registered
function Stubs.NewAddon()
    local ns = {}
    local function LoadFile(relPath)
        local chunk, err = loadfile(ADDON .. "/" .. relPath)
        if not chunk then error("load failed: " .. relPath .. "\n" .. tostring(err)) end
        return chunk("GudaBags", ns)
    end

    LoadFile("Core/Init.lua")
    ns:RegisterModule("Expansion", {
        IsRetail = false, IsClassicEra = true, IsTBC = false,
        Features = {HasKeyring = true, HasQuiverBags = true},
    })
    ns.L = setmetatable({}, {__index = function(_, k) return k end})
    return ns, LoadFile
end

-- Minimal test bookkeeping shared by the harnesses
function Stubs.NewChecker()
    local checker = {failures = 0}
    function checker.check(label, cond)
        if cond then
            print("  ok   " .. label)
        else
            checker.failures = checker.failures + 1
            print("  FAIL " .. label)
        end
    end
    function checker.finish(okMessage)
        print("")
        if checker.failures == 0 then
            print("ALL PASS - " .. okMessage)
        else
            print(checker.failures .. " FAILURE(S)")
            error("harness failed", 0)
        end
    end
    return checker
end

return Stubs
