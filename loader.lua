-- VisionWare loader  (Solara / Xeno safe - no getgc needed)
-- Loads each feature as its own module so you can disable / debug them one at a time.
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

local function WaitFor(cond, timeout)
    local elapsed = 0
    while not cond() and elapsed < (timeout or 10) do
        task.wait(0.1)
        elapsed = elapsed + 0.1
    end
    return cond()
end

-- 1. GUI (creates the window + all flags, exposes Library)
if not Run("gui.lua") then
    warn("[VisionWare] gui.lua failed to load - aborting")
    return
end

-- 2. Shared API (flags, team check, target selection, drawing helpers)
if not Run("shared.lua") then
    warn("[VisionWare] shared.lua failed to load - aborting")
    return
end

if not WaitFor(function()
    local V = (getgenv and getgenv().Vision) or _G.Vision
    return V and V.Flag ~= nil
end) then
    warn("[VisionWare] shared API never became available")
    return
end

-- 3. Feature modules (each independent; one failing won't stop the others)
local Features = {
    "esp.lua",
    "aimbot.lua",
    "silentaim.lua",
    "triggerbot.lua",
    "movement.lua",
    "visuals.lua",
    "crosshair.lua",
}

local loaded = 0
for _, name in ipairs(Features) do
    if Run(name) then
        loaded = loaded + 1
    end
end

print(("[VisionWare] loaded %d/%d feature modules"):format(loaded, #Features))