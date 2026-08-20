--[[
    VisionWare | aimbot.lua
    ========================
    Aimbot as its own module. Uses the shared `Vision` API (shared.lua).
    Moves the mouse toward the selected target while the key is held.
    Draws its own FoV circle.
]]

local Vision
for _ = 1, 100 do
    Vision = (getgenv and getgenv().Vision) or _G.Vision
    if Vision and Vision.Flag then break end
    task.wait(0.1)
end
if not Vision then
    warn("[VisionWare] aimbot.lua could not find shared API")
    return
end

local RunService = Vision.RunService
local Flag = Vision.Flag

-- =====================================================================
--  FoV circle
-- =====================================================================
local FovCircle
local function DrawFovCircle()
    local camera = Vision.GetCamera()
    if not camera then return end
    local center = camera.ViewportSize / 2
    local enabled = not Vision.IsPanic() and Flag("Aimbot_FoV", true) and Flag("Aimbot_Enabled", true)
    if not enabled then
        if FovCircle then FovCircle.Visible = false end
        return
    end
    if not FovCircle then
        FovCircle = Vision.NewDrawing("Circle")
        if FovCircle then
            FovCircle.Filled = false
            FovCircle.Visible = false
        end
    end
    if not FovCircle then return end
    FovCircle.Visible = true
    FovCircle.Color = Flag("Aimbot_FoVColor", Color3.fromRGB(255, 255, 255)) or Color3.fromRGB(255, 255, 255)
    FovCircle.Radius = Flag("Aimbot_FoVSize", 50) or 50
    FovCircle.Position = center
    FovCircle.Thickness = 1
    FovCircle.Transparency = 0.5
end

-- =====================================================================
--  Aimbot
-- =====================================================================
local lastTarget, lastTargetLostTime

RunService.Heartbeat:Connect(function()
    DrawFovCircle()

    local panic = Vision.IsPanic()
    local enabled = not panic and Flag("Aimbot_Enabled", true)
    local active = enabled and Vision.KeyActive("Aimbot_Key", Enum.UserInputType.MouseButton2)

    if not active then
        lastTarget = nil
        return
    end

    local camera = Vision.GetCamera()
    if not camera then return end

    local useFov = Flag("Aimbot_FoV", true)
    local fovRadius = Flag("Aimbot_FoVSize", 50) or 50
    local smooth = Flag("Aimbot_Smoothness", 0.2) or 0.2
    local hitpart = Flag("Aimbot_Hitpart", "Head")
    local center = camera.ViewportSize / 2

    local target = Vision.SelectTarget("Aimbot", "Aimbot_Hitpart")

    if target and useFov and Flag("Aimbot_Target", "Closest to Crosshair") == "Closest to Crosshair" then
        local screen, onScreen = Vision.WorldToScreen(target.pos)
        if screen and onScreen and (screen - center).Magnitude > fovRadius then
            target = nil
        end
    end

    -- Target switch delay
    if target and target ~= lastTarget then
        if lastTarget and lastTargetLostTime and (tick() - lastTargetLostTime) < 0.15 then
            target = nil
        else
            lastTarget = target
            lastTargetLostTime = nil
        end
    end
    if not target and lastTarget then
        if not lastTargetLostTime then lastTargetLostTime = tick() end
        lastTarget = nil
    end

    if not target then return end

    local part = target.part
    if not part then return end

    local screen, onScreen = Vision.WorldToScreen(part.Position)
    if not screen or not onScreen then return end

    local delta = (screen - center) * smooth
    Vision.MoveMouse(delta.X, delta.Y)
end)

print("[VisionWare] aimbot.lua loaded")