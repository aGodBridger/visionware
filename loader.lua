-- VisionWare loader  (Solara / Xeno safe - no getgc needed)
local Repo = "https://raw.githubusercontent.com/aGodBridger/visionware/refs/heads/main/"
local RootName = (identifyexecutor and identifyexecutor()) or "Executor"
print("[VisionWare] loader running on " .. RootName)

local function Get(url)
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if not ok or type(res) ~= "string" then
        warn("[VisionWare] failed to fetch " .. url)
        return nil
    end
    return res
end

local function Run(name)
    local src = Get(Repo .. name)
    if not src then return false end
    local fn, err = loadstring(src)
    if not fn then
        warn("[VisionWare] compile error in " .. name .. ": " .. tostring(err))
        return false
    end
    local ok, err2 = xpcall(fn, function(e) return debug.traceback(e) end)
    if not ok then
        warn("[VisionWare] runtime error in " .. name .. ":\n" .. tostring(err2))
        return false
    end
    return true
end

local guiOk = Run("gui.lua")
local featOk = Run("features.lua")

if guiOk then print("[VisionWare] GUI loaded") end
if featOk then print("[VisionWare] Features loaded") end
if not guiOk or not featOk then
    warn("[VisionWare] something failed - check the messages above")
end