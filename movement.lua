--[[
    VisionWare | movement.lua
    =========================
    Movement features as their own module.
    Speed / Jump / Infinite Jump / Noclip / Fly / Strafe / Velocity.
]]

local Vision
for _ = 1, 100 do
    Vision = (getgenv and getgenv().Vision) or _G.Vision
    if Vision and Vision.Flag then break end
    task.wait(0.1)
end
if not Vision then
    warn("[VisionWare] movement.lua could not find shared API")
    return
end

local RunService = Vision.RunService
local UserInputService = Vision.UserInputService
local LocalPlayer = Vision.LocalPlayer
local Flag = Vision.Flag

-- =====================================================================
--  Helpers
-- =====================================================================
local function MyHumanoid()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function MyRoot()
    local c = LocalPlayer.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart)
end

-- =====================================================================
--  Infinite jump (throttled so holding Space doesn't spam-jump nonstop)
-- =====================================================================
local lastJump = 0
UserInputService.InputBegan:Connect(function(inp, gameProcessed)
    if gameProcessed then return end
    if inp.KeyCode == Enum.KeyCode.Space and Flag("Misc_JumpInfinite", false) then
        local now = tick()
        if now - lastJump < 0.12 then return end
        local h = MyHumanoid()
        if h and h.Health > 0 then
            lastJump = now
            h:ChangeState(Enum.HumanoidStateType.None)
            task.wait(0.01)
            h:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

-- =====================================================================
--  Main movement loop
-- =====================================================================
RunService.Heartbeat:Connect(function(dt)
    if Vision.IsPanic() then return end

    local c = LocalPlayer.Character
    local hum = (c and c:FindFirstChildOfClass("Humanoid")) or MyHumanoid()
    local root = (c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart))
    if not c or not hum or not root then return end

    -- WalkSpeed
    local speedOn = Flag("Misc_Speed", false)
    local targetWS = speedOn and (Flag("Misc_SpeedAmount", 80) or 80) or 16
    if hum.WalkSpeed ~= targetWS then hum.WalkSpeed = targetWS end

    -- Jump power
    hum.UseJumpPower = Flag("Misc_Jump", false)
    if Flag("Misc_Jump", false) then
        hum.JumpPower = Flag("Misc_JumpPower", 100) or 100
    end

    -- Strafe
    hum.AutoRotate = not Flag("Misc_Strafe", false)

    -- Velocity
    if Flag("Misc_Velocity", false) and hum.MoveDirection.Magnitude > 0.1 then
        pcall(function()
            root.AssemblyLinearVelocity = hum.MoveDirection * (hum.WalkSpeed * (Flag("Misc_VelocityAmount", 1) or 1))
        end)
    end

    -- Noclip
    if Flag("Misc_Noclip", false) and hum.MoveDirection.Magnitude > 0.1 then
        pcall(function()
            root.CFrame = root.CFrame + hum.MoveDirection * (hum.WalkSpeed * dt)
        end)
    end

    -- Fly (unbound key = fly whenever the toggle is on)
    if Flag("Misc_Fly", false) then
        local speed = Flag("Misc_FlySpeed", 50) or 50
        local flyKeySet = Flag("Misc_FlyKey") ~= nil
        local activeFly = (not flyKeySet) or Vision.KeyActive("Misc_FlyKey")
        if activeFly then
            local camera = Vision.GetCamera()
            local move = hum.MoveDirection
            local vert = 0
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then vert = 1
            elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then vert = -1 end
            pcall(function()
                root.VectorVelocity = Vector3.zero
                root.AssemblyLinearVelocity = (camera and camera.CFrame.LookVector * (move.Magnitude > 0.1 and speed or 0)) + Vector3.new(0, vert * speed, 0)
            end)
        end
    end
end)

print("[VisionWare] movement.lua loaded")