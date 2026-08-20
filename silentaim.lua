--[[
    VisionWare | silentaim.lua
    ===========================
    Silent aim as its own module. Uses the shared `Vision` API (shared.lua).

    How it works:
      Method "Ray Redirect" (default in Auto): hooks workspace.Raycast so any
      ray fired from the local camera while the activation key is held gets
      redirected onto the target's hitpart. The camera never moves, shots
      silently land on the target. Falls back to mouse assist automatically if
      the executor can't hook.
      Method "Mouse Assist": snaps the mouse onto the target while firing
      (traditional aim-assist).
      Prediction uses the target's measured velocity (position delta over
      time) * lead time, so leading is distance-independent and actually works.
]]

local Vision
for _ = 1, 100 do
    Vision = (getgenv and getgenv().Vision) or _G.Vision
    if Vision and Vision.Flag then break end
    task.wait(0.1)
end
if not Vision then
    warn("[VisionWare] silentaim.lua could not find shared API")
    return
end

local RunService = Vision.RunService
local UserInputService = Vision.UserInputService
local LocalPlayer = Vision.LocalPlayer
local Flag = Vision.Flag

local SilentState = { hitPos = nil, target = nil, screen = nil }

-- =====================================================================
--  Activation
-- =====================================================================
local function Active()
    if Vision.IsPanic() then return false end
    if not Flag("SilentAim_Enabled", true) then return false end
    return Vision.KeyActive("SilentAim_Key", Enum.UserInputType.MouseButton1)
end

-- =====================================================================
--  Velocity-based prediction
--  vel = (pos_now - pos_last) / dt,  lead = pos + vel * leadTime
-- =====================================================================
local velCache = {}
local lastTick = tick()

local function GetPredictedPos(player, part)
    local pos = part.Position
    local lead = Flag("SilentAim_Prediction", false) and (Flag("SilentAim_PredAmount", 0.165) or 0.165) or 0
    if lead <= 0 then return pos end

    local now = tick()
    local dt = now - lastTick
    lastTick = now
    if dt <= 0 then return pos end

    local vc = velCache[player]
    local vel = Vector3.zero
    if vc and vc.part == part then
        vel = (pos - vc.pos) / dt
        -- smooth the velocity to avoid jitter
        vel = vc.vel:Lerp(vel, 0.5)
    end
    velCache[player] = { part = part, pos = pos, vel = vel }

    return pos + vel * lead
end

-- =====================================================================
--  Target selection (recomputed every heartbeat)
-- =====================================================================
local function PickTarget()
    if not Active() then return nil end

    local target = Vision.SelectTarget("SilentAim", "SilentAim_Hitpart", {
        visibleOnly = Flag("SilentAim_VisibleCheck", false),
    })
    if not target then return nil end

    local camera = Vision.GetCamera()
    if not camera then return nil end
    local center = camera.ViewportSize / 2

    -- FoV check
    local useFov = Flag("SilentAim_FoV", true)
    local fovSize = Flag("SilentAim_FoVSize", 80) or 80
    local screen, onScreen = Vision.WorldToScreen(target.pos)
    if not screen or not onScreen then return nil end
    if useFov and (screen - center).Magnitude > fovSize then return nil end

    -- Hit chance
    local chance = Flag("SilentAim_HitChance", 100) or 100
    if chance < 100 and math.random(1, 100) > chance then return nil end

    return target
end

-- =====================================================================
--  Update the shared silent state each heartbeat
-- =====================================================================
RunService.Heartbeat:Connect(function()
    local target = PickTarget()
    if not target then
        SilentState.target = nil
        SilentState.hitPos = nil
        SilentState.screen = nil
        return
    end
    local part = target.part
    local hitPos = GetPredictedPos(target.player, part)
    local screen, _ = Vision.WorldToScreen(hitPos)
    SilentState.target = target
    SilentState.hitPos = hitPos
    SilentState.screen = screen
end)

-- =====================================================================
--  Method selection
-- =====================================================================
local method = Flag("SilentAim_Method", "Auto")
local wantRay = method == "Ray Redirect" or method == "Auto"
local wantMouse = method == "Mouse Assist" or (method == "Auto")

-- =====================================================================
--  METHOD 1: Ray redirect (hooked workspace.Raycast)
-- =====================================================================
local rayHooked = false
if wantRay then
    local oldRaycast = workspace.Raycast
    if hookfunction and oldRaycast then
        local ok, hook = pcall(function()
            return hookfunction(oldRaycast, function(origin, direction, params, ...)
                local hitPos = SilentState.hitPos
                if hitPos then
                    local cam = workspace.CurrentCamera
                    if cam and (origin - cam.CFrame.Position).Magnitude < 5 then
                        local nd = hitPos - origin
                        if nd.Magnitude > 0.5 then
                            -- Preserve the ray length so range-based weapons still work
                            local redirected = oldRaycast(origin, nd.Unit * direction.Magnitude, params, ...)
                            if redirected then return redirected end
                        end
                    end
                end
                return oldRaycast(origin, direction, params, ...)
            end)
        end)
        rayHooked = ok and hook ~= nil
        if rayHooked then
            print("[VisionWare] silent aim: workspace.Raycast hooked (true silent aim)")
        else
            warn("[VisionWare] silent aim: hookfunction failed, falling back to mouse assist")
        end
    else
        warn("[VisionWare] silent aim: no hookfunction support, using mouse assist")
    end
end

-- =====================================================================
--  METHOD 2: Mouse assist (used when not using ray redirect)
-- =====================================================================
if wantMouse and not rayHooked then
    RunService.RenderStepped:Connect(function()
        local screen = SilentState.screen
        if not screen then return end
        local camera = Vision.GetCamera()
        if not camera then return end
        local center = camera.ViewportSize / 2
        local delta = screen - center
        Vision.MoveMouse(delta.X, delta.Y)
    end)
end

-- =====================================================================
--  Show silent target marker
-- =====================================================================
local marker
if Flag("SilentAim_ShowTarget", false) and Drawing and Drawing.new then
    marker = Vision.NewDrawing("Square")
    if marker then
        marker.Filled = false
        marker.Color = Flag("SilentAim_FoVColor", Color3.fromRGB(255, 255, 255)) or Color3.fromRGB(255, 255, 255)
        marker.Thickness = 1
        marker.Visible = false
    end
end

RunService.RenderStepped:Connect(function()
    if marker then
        local screen = SilentState.screen
        if screen then
            marker.Position = screen - Vector2.new(10, 10)
            marker.Size = Vector2.new(20, 20)
            marker.Visible = true
        else
            marker.Visible = false
        end
    end
end)

-- =====================================================================
--  Silent aim FoV circle
-- =====================================================================
local FovCircle
RunService.RenderStepped:Connect(function()
    local camera = Vision.GetCamera()
    if not camera then return end
    local center = camera.ViewportSize / 2
    local enabled = not Vision.IsPanic() and Flag("SilentAim_Enabled", true) and Flag("SilentAim_FoV", true)
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
    FovCircle.Color = Flag("SilentAim_FoVColor", Color3.fromRGB(255, 255, 255)) or Color3.fromRGB(255, 255, 255)
    FovCircle.Radius = Flag("SilentAim_FoVSize", 80) or 80
    FovCircle.Position = center
    FovCircle.Thickness = 1
    FovCircle.Transparency = 0.5
end)

print("[VisionWare] silentaim.lua loaded (" .. (rayHooked and "ray redirect" or "mouse assist") .. ")")