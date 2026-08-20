--[[
    VisionWare | visuals.lua
    ========================
    Visual / world features as their own module.
    Fullbright / Brightness / No Fog / Clouds / Skybox / Night Vision /
    Highlight (player chams).
]]

local Vision
for _ = 1, 100 do
    Vision = (getgenv and getgenv().Vision) or _G.Vision
    if Vision and Vision.Flag then break end
    task.wait(0.1)
end
if not Vision then
    warn("[VisionWare] visuals.lua could not find shared API")
    return
end

local RunService = Vision.RunService
local Lighting = Vision.Lighting
local LocalPlayer = Vision.LocalPlayer
local Flag = Vision.Flag

-- =====================================================================
--  Lighting / world
-- =====================================================================
RunService.Heartbeat:Connect(function()
    if Vision.IsPanic() then return end

    local fb = Flag("Visuals_Fullbright", true)
    Lighting.Brightness = fb and 1 or 1
    Lighting.Ambient = fb and Color3.fromRGB(128, 128, 128) or Color3.fromRGB(0, 0, 0)
    Lighting.GlobalShadows = not fb

    if Flag("Visuals_NoFog", false) then
        Lighting.FogEnd = 100000
        Lighting.FogStart = -1000
    else
        Lighting.FogEnd = 100
        Lighting.FogStart = 0
    end

    if Flag("Visuals_Brightness", false) then
        Lighting.Brightness = Flag("Visuals_BrightnessAmount", 3) or 3
    end

    local clouds = Lighting:FindFirstChildOfClass("Clouds")
    if clouds and clouds.Visible ~= (not Flag("Visuals_Clouds", false)) then
        clouds.Visible = not Flag("Visuals_Clouds", false)
    end

    if Flag("Visuals_NightVision", false) then
        Lighting.Brightness = 1
        Lighting.Ambient = Flag("Visuals_NightVisionColor", Color3.fromRGB(60, 255, 120)) or Color3.fromRGB(60, 255, 120)
    end
end)

-- =====================================================================
--  Skybox
-- =====================================================================
do
    local Sky
    local lastSkyOn = nil
    RunService.Heartbeat:Connect(function()
        local on = not Vision.IsPanic() and Flag("Visuals_Skybox", false)
        if on and not Sky then
            local ok, s = pcall(function()
                local n = Instance.new("Sky")
                n.Parent = Lighting
                return n
            end)
            Sky = ok and s or nil
            lastSkyOn = true
        elseif not on and Sky then
            pcall(function() Sky:Destroy() end)
            Sky = nil
            lastSkyOn = false
        end
    end)
end

-- =====================================================================
--  Highlight (player chams-style)
-- =====================================================================
local Highlights = {} -- [player] = Highlight

local function UpdateHighlights()
    if Vision.IsPanic() then
        for _, h in pairs(Highlights) do pcall(function() h.Enabled = false end) end
        return
    end

    local hlOn = Flag("Visuals_Highlight", false)
    local hlC = Flag("Visuals_HighlightColor", Color3.fromRGB(255, 255, 255)) or Color3.fromRGB(255, 255, 255)

    for player, entry in pairs(Vision.Tracked) do
        local char = Vision.GetChar(player)
        local h = Highlights[player]

        if hlOn and char then
            if not h then
                local ok, newH = pcall(function()
                    local n = Instance.new("Highlight")
                    n.Adornee = char
                    n.Parent = char
                    return n
                end)
                h = ok and newH or nil
                Highlights[player] = h
            elseif h.Adornee ~= char then
                pcall(function() h.Adornee = char end)
            end
            if h then
                h.FillColor = hlC
                h.OutlineColor = Color3.fromRGB(0, 0, 0)
                h.Enabled = true
            end
        elseif h then
            pcall(function() h.Enabled = false end)
        end
    end
end

RunService.RenderStepped:Connect(UpdateHighlights)

-- clean up highlights when a player leaves
local oldRemove = Vision.OnPlayerRemoving
Vision.OnPlayerRemoving = function(player, entry)
    if oldRemove then oldRemove(player, entry) end
    local h = Highlights[player]
    if h then
        pcall(function() h:Destroy() end)
        Highlights[player] = nil
    end
end

print("[VisionWare] visuals.lua loaded")