local addonName, ns = ...

ns.addonName = addonName

-- Read version from TOC file (compatible with all WoW versions). The packager fills
-- @project-version@ in from the git tag; an unpackaged checkout still holds the raw token.
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local tocVersion = GetAddOnMetadata(addonName, "Version")
ns.version = (tocVersion and not tocVersion:find("@", 1, true)) and tocVersion or "dev"

ns.Modules = {}

function ns:RegisterModule(name, module)
    self.Modules[name] = module
end

function ns:GetModule(name)
    return self.Modules[name]
end

function ns:Print(...)
    local msg = string.join(" ", tostringall(...))
    print("|cff00ccff[GudaBags]|r " .. msg)
end

function ns:Debug(...)
    if not self.debugMode then return end
    local msg = string.join(" ", tostringall(...))
    print("|cff888888[GudaBags Debug]|r " .. msg)
end

ns.debugMode = false
