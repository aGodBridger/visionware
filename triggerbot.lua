--[[
    VisionWare | triggerbot.lua
    ===========================
    Triggerbot as its own module. Uses the shared `Vision` API (shared.lua).
    Fires when the crosshair is on an enemy while the trigger key is held.
]]

local Vision
for _ = 1, 100 do
    Vision = (getgenv and getgenv().Vision) or _G.Vision
    if Vision and Vision.Flag then break end
    task.wait(0.1)
end
if not Vision then
    warn("[VisionWare] triggerbot.lua could not find shared API")
    return
end

local RunService = Vision.RunService
local LocalPlayer = Vision.LocalPlayer
local Flag = Vision.Flag

local lastShot = 0

RunService.Heartbeat:Connect(function(t)
    if Vision.IsPanic() or not Flag("Triggerbot_Enabled", false) then return end
    local key = Flag("Triggerbot_Key")
    if key and not Vision.IsKeyHeld(key) then return end

    local camera = Vision.GetCamera()
    if not camera then return end

    local ray = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 1000)
    if ray and ray.Instance then
        local p = Vision.GetPlayerFromPart(ray.Instance)
        local teamCheck = Flag("Triggerbot_TeamCheck", true)
        if p and p ~= LocalPlayer and (not teamCheck or Vision.IsEnemy(p)) then
            local interval = 1 / (Flag("Triggerbot_FireRate", 10) or 10)
            if t - lastShot >= interval then
                lastShot = t
                pcall(function() mouse1click() end)
            end
        end
    end
end)

print("[VisionWare] triggerbot.lua loaded")