local addonName, ns = ...

ns.addonName = addonName
ns.version = "1.0.0"

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
