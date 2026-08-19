--[[
    VisionWare | ESP + Aimbot  (Phantom Forces)  -- wapus method
    ===========================================================
    This is a faithful port of the wapus ESP/aimbot technique into the
    VisionWare GUI (gui.lua). It does NOT use PlayerTag or Player.Character
    scanning like typical ESPs. Instead it:

      1) WAITS for the game's internal module cache (like wapus's loader)
         so it never initializes "too soon" -- nothing is hard-captured
         at load, the camera is resolved fresh every frame.
      2) Loads the Sirius ESP library and binds it to the real Phantom
         Forces modules (ReplicationInterface / ThirdPersonObject) with
         a setCharacterRender hook to force third-person rendering.
      3) Aimbot = screen-space FOV target selection + ballistic lead
         (complexTrajectory) written into the camera animator's angles
         (cameraObj._angles/_delta) -- no mousemoverel.

    The loader runs gui.lua first, so Library exists here.
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local workspace        = game:GetService("Workspace")
local LocalPlayer      = Players.LocalPlayer

local pi  = math.pi
local tau = 2 * pi

-- // No-op guards (wapus defines these as no-ops too)
local LPH_NO_VIRTUALIZE = function(f) return f end

-- // Wait for the VisionWare GUI, then hook its flags
local Library
repeat
    task.wait()
    Library = (getgenv and getgenv().Library) or _G.Library
until Library and Library.Flags
local Flags = Library.Flags

local function Flag(Name, Default)
    local v = Flags[Name]
    return v ~= nil and v or Default
end

local function Opacity(Percent)
    return math.clamp((tonumber(Percent) or 100) / 100, 0, 1)
end

-- =====================================================================
--  1) WAIT FOR THE GAME MODULES  (the "don't load too soon" gate)
-- =====================================================================
-- Pull the internal module-cache table out of the Lua GC, exactly like
-- wapus's loader -> Main Cheat. Nothing below runs until it exists.
local function GetModuleCache()
    local ok, cache = pcall(function()
        for _, v in getgc(true) do
            if type(v) == "table" and rawget(v, "ScreenCull") and rawget(v, "NetworkClient") then
                return v
            end
        end
    end)
    return ok and cache or nil
end

local moduleCache
repeat
    moduleCache = GetModuleCache()
    if not moduleCache then task.wait(0.5) end
until moduleCache ~= nil

local modules = {}
for name, data in moduleCache do
    if data then
        if type(data) == "table" then modules[name] = data.module
        else modules[name] = data end
    end
end

local replicationInterface = modules.ReplicationInterface
local thirdPersonObject    = modules.ThirdPersonObject
local cameraInterface      = modules.CameraInterface
local weaponInterface      = modules.WeaponControllerInterface
local publicSettings       = modules.PublicSettings

if not (replicationInterface and thirdPersonObject and cameraInterface) then
    warn("[VisionWare] Could not bind PF modules - not in a Phantom Forces round?")
    return
end

-- Resolve camera fresh each frame (never captured at load)
local function GetCamera()
    return workspace.CurrentCamera
end

local function GetChar(player)
    local entry, third
    local ok = pcall(function()
        entry = replicationInterface.getEntry(player)
        third = entry:isReady() and entry._smoothReplication and entry._smoothReplication._prevFrameTime and entry:getThirdPersonObject()
    end)
    if not ok then return nil, nil end
    if not third then return nil, nil end
    local model, root
    local ok2 = pcall(function()
        model = third:getCharacterModel()
        root  = third:getRootPart()
    end)
    if not ok2 then return nil, nil end
    return model, root
end

-- =====================================================================
--  2) ESP  -- Sirius library bound to the real modules (wapus method)
-- =====================================================================
local espInterface
pcall(function()
    espInterface = loadstring(game:HttpGet("https://raw.githubusercontent.com/jensonhirst/Sirius/refs/heads/request/library/sense/source.lua"))()
end)

local function IsPanic()
    return Flag("Misc_Panic", false)
end

local function SyncEspSettings()
    if not espInterface then return end
    local t = espInterface.teamSettings
    if not t then return end

    local espOn = not IsPanic() and Flag("ESP_Enabled", true)
    local enemy = t.enemy
    local friendly = t.friendly

    local enemyColor = Flag("ESP_EnemyColor", Color3.fromRGB(0, 255, 255)) or Color3.fromRGB(0, 255, 255)
    local teamColor  = Flag("ESP_TeamColor", Color3.fromRGB(86, 227, 120)) or Color3.fromRGB(86, 227, 120)
    local opacity    = Opacity(Flag("ESP_Opacity", 75))

    enemy.enabled        = espOn
    enemy.box            = espOn and Flag("ESP_Boxes", true)
    enemy.boxColor       = { enemyColor, opacity }
    enemy.healthBar      = espOn and Flag("ESP_Health", true)
    enemy.healthyColor   = Color3.fromRGB(0, 255, 0)
    enemy.dyingColor     = Color3.fromRGB(255, 0, 0)
    enemy.name           = espOn and Flag("ESP_Names", true)
    enemy.nameColor      = { Color3.fromRGB(255, 255, 255), 1 }
    enemy.distance       = espOn and Flag("ESP_Distance", false)
    enemy.distanceColor  = { Color3.fromRGB(255, 255, 255), 1 }
    enemy.tracer         = espOn and Flag("ESP_Tracers", true)
    enemy.tracerColor    = { enemyColor, opacity }
    enemy.tracerOrigin   = (function()
        local o = Flag("ESP_TracerType", "From Bottom")
        if o == "From Top" then return "Top"
        elseif o == "From Center" then return "Middle"
        else return "Bottom" end
    end)()
    enemy.chams          = espOn and Flag("ESP_Chams", true)
    enemy.chamsFillColor = { Flag("ESP_ChamsColor", Color3.fromRGB(255, 255, 255)), 0.5 }
    enemy.chamsOutlineColor = { Flag("ESP_ChamsColor", Color3.fromRGB(255, 255, 255)), 0 }

    friendly.enabled    = espOn and Flag("ESP_ShowTeam", false)
    friendly.box        = espOn and Flag("ESP_ShowTeam", false) and Flag("ESP_Boxes", true)
    friendly.boxColor   = { teamColor, opacity }
    friendly.healthBar  = espOn and Flag("ESP_ShowTeam", false) and Flag("ESP_Health", true)
    friendly.name       = espOn and Flag("ESP_ShowTeam", false) and Flag("ESP_Names", true)
    friendly.distance   = espOn and Flag("ESP_ShowTeam", false) and Flag("ESP_Distance", false)
    friendly.tracer     = espOn and Flag("ESP_ShowTeam", false) and Flag("ESP_Tracers", true)
    friendly.tracerColor= { teamColor, opacity }
end

if espInterface then
    espInterface.teamSettings = {
        enemy = { enabled = false, box = false, boxColor = { Color3.fromRGB(255,0,0), 1 }, boxOutline = true, boxOutlineColor = { Color3.new(), 1 }, boxFill = false, boxFillColor = { Color3.fromRGB(255,0,0), 0.5 }, healthBar = false, healthyColor = Color3.fromRGB(0,255,0), dyingColor = Color3.fromRGB(255,0,0), healthBarOutline = true, healthBarOutlineColor = { Color3.new(), 0.5 }, healthText = false, healthTextColor = { Color3.new(1,1,1), 1 }, healthTextOutline = true, healthTextOutlineColor = Color3.new(), box3d = false, box3dColor = { Color3.new(1,0,0), 1 }, name = false, nameColor = { Color3.new(1,1,1), 1 }, nameOutline = true, nameOutlineColor = Color3.new(), weapon = false, weaponColor = { Color3.new(1,1,1), 1 }, weaponOutline = true, weaponOutlineColor = Color3.new(), distance = false, distanceColor = { Color3.new(1,1,1), 1 }, distanceOutline = true, distanceOutlineColor = Color3.new(), tracer = false, tracerOrigin = "Bottom", tracerColor = { Color3.new(1,0,0), 1 }, tracerOutline = true, tracerOutlineColor = { Color3.new(), 1 }, offScreenArrow = false, offScreenArrowColor = { Color3.new(1,1,1), 1 }, offScreenArrowSize = 15, offScreenArrowRadius = 150, offScreenArrowOutline = true, offScreenArrowOutlineColor = { Color3.new(), 1 }, chams = false, chamsVisibleOnly = false, chamsFillColor = { Color3.fromRGB(0.2,0.2,0.2), 0.5 }, chamsOutlineColor = { Color3.fromRGB(1,0,0), 0 } },
        friendly = { enabled = false, box = false, boxColor = { Color3.fromRGB(0,255,0), 1 }, boxOutline = true, boxOutlineColor = { Color3.new(), 1 }, boxFill = false, boxFillColor = { Color3.fromRGB(0,255,0), 0.5 }, healthBar = false, healthyColor = Color3.fromRGB(0,255,0), dyingColor = Color3.fromRGB(255,0,0), healthBarOutline = true, healthBarOutlineColor = { Color3.new(), 0.5 }, healthText = false, healthTextColor = { Color3.new(1,1,1), 1 }, healthTextOutline = true, healthTextOutlineColor = Color3.new(), box3d = false, box3dColor = { Color3.new(0,1,0), 1 }, name = false, nameColor = { Color3.new(1,1,1), 1 }, nameOutline = true, nameOutlineColor = Color3.new(), weapon = false, weaponColor = { Color3.new(1,1,1), 1 }, weaponOutline = true, weaponOutlineColor = Color3.new(), distance = false, distanceColor = { Color3.new(1,1,1), 1 }, distanceOutline = true, distanceOutlineColor = Color3.new(), tracer = false, tracerOrigin = "Bottom", tracerColor = { Color3.new(0,1,0), 1 }, tracerOutline = true, tracerOutlineColor = { Color3.new(), 1 }, offScreenArrow = false, offScreenArrowColor = { Color3.new(1,1,1), 1 }, offScreenArrowSize = 15, offScreenArrowRadius = 150, offScreenArrowOutline = true, offScreenArrowOutlineColor = { Color3.new(), 1 }, chams = false, chamsVisibleOnly = false, chamsFillColor = { Color3.fromRGB(0.2,0.2,0.2), 0.5 }, chamsOutlineColor = { Color3.fromRGB(0,1,0), 0 } }
    }

    espInterface.getCharacter = LPH_NO_VIRTUALIZE(function(player)
        local model, root = GetChar(player)
        return model, root
    end)

    espInterface.getHealth = LPH_NO_VIRTUALIZE(function(player, character)
        local entry = replicationInterface.getEntry(player)
        local hp
        pcall(function() hp = entry:getHealth() end)
        if hp then return hp, 100 end
        if character then
            local h = character:FindFirstChild("Humanoid")
            if h then return h.Health, h.MaxHealth end
        end
        return 100, 100
    end)

    espInterface.isFriendly = function(player)
        local entry = replicationInterface.getEntry(player)
        return not entry._isEnemy
    end

    -- Force third-person rendering so characters (and ESP) actually show.
    local setCharacterRender = thirdPersonObject.setCharacterRender
    thirdPersonObject.setCharacterRender = function(self, render)
        local force = not IsPanic() and Flag("ESP_Enabled", true)
        return setCharacterRender(self, render or (force and self._player ~= LocalPlayer))
    end

    espInterface.Load()
end

-- Keep the ESP settings in sync with the GUI (see Heartbeat at the bottom)
-- =====================================================================
--  3) AIMBOT  -- camera-angle + ballistic lead (wapus method)
-- =====================================================================
local function IsKeyHeld(Key)
    if type(Key) == "EnumItem" then
        if Key.EnumType == Enum.KeyCode then
            return UserInputService:IsKeyDown(Key)
        elseif Key.EnumType == Enum.UserInputType then
            if Key == Enum.UserInputType.MouseButton1 then
                return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
            elseif Key == Enum.UserInputType.MouseButton2 then
                return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
            end
        end
    end
    return false
end

-- Verbatim ballistic lead solver from wapus (credit: Mickey)
local function solve(v44, v45, v46, v47, v48)
    if not v44 then
        return
    elseif v44 > -1.0E-10 and v44 < 1.0E-10 then
        return solve(v45, v46, v47, v48)
    else
        if v48 then
            local v49 = -v45 / (4 * v44)
            local v50 = (v46 + v49 * (3 * v45 + 6 * v44 * v49)) / v44
            local v51 = (v47 + v49 * (2 * v46 + v49 * (3 * v45 + 4 * v44 * v49))) / v44
            local v52 = (v48 + v49 * (v47 + v49 * (v46 + v49 * (v45 + v44 * v49)))) / v44
            if v51 > -1.0E-10 and v51 < 1.0E-10 then
                local v53, v54 = solve(1, v50, v52)
                if not v54 or v54 < 0 then
                    return
                else
                    local v55 = math.sqrt(v53)
                    local v56 = math.sqrt(v54)
                    return v49 - v56, v49 - v55, v49 + v55, v49 + v56
                end
            else
                local v57, _, v59 = solve(1, 2 * v50, v50 * v50 - 4 * v52, -v51 * v51)
                local v60 = v59 or v57
                local v61 = math.sqrt(v60)
                local v62, v63 = solve(1, v61, (v60 + v50 - v51 / v61) / 2)
                local v64, v65 = solve(1, -v61, (v60 + v50 + v51 / v61) / 2)
                if v62 and v64 then
                    return v49 + v62, v49 + v63, v49 + v64, v49 + v65
                elseif v62 then
                    return v49 + v62, v49 + v63
                elseif v64 then
                    return v49 + v64, v49 + v65
                end
            end
        elseif v47 then
            local v66 = -v45 / (3 * v44)
            local v67 = -(v46 + v66 * (2 * v45 + 3 * v44 * v66)) / (3 * v44)
            local v68 = -(v47 + v66 * (v46 + v66 * (v45 + v44 * v66))) / (2 * v44)
            local v69 = v68 * v68 - v67 * v67 * v67
            local v70 = math.sqrt(math.abs(v69))
            if v69 > 0 then
                local v71 = v68 + v70
                local v72 = v68 - v70
                v71 = v71 < 0 and -(-v71) ^ 0.3333333333333333 or v71 ^ 0.3333333333333333
                local v73 = v72 < 0 and -(-v72) ^ 0.3333333333333333 or v72 ^ 0.3333333333333333
                return v66 + v71 + v73
            else
                local v74 = math.atan2(v70, v68) / 3
                local v75 = 2 * math.sqrt(v67)
                return v66 - v75 * math.sin(v74 + 0.5235987755982988), v66 + v75 * math.sin(v74 - 0.5235987755982988), v66 + v75 * math.cos(v74)
            end
        elseif v46 then
            local v76 = -v45 / (2 * v44)
            local v77 = v76 * v76 - v46 / v44
            if v77 < 0 then
                return
            else
                local v78 = math.sqrt(v77)
                return v76 - v78, v76 + v78
            end
        elseif v45 then
            return -v45 / v44
        end
        return
    end
end

local function complexTrajectory(o, a, t, s, e)
    local ld = t - o
    a = -a
    e = e or Vector3.zero
    local r1, r2, r3, r4 = solve(
        a:Dot(a) * 0.25,
        a:Dot(e),
        a:Dot(ld) + e:Dot(e) - s * s,
        ld:Dot(e) * 2,
        ld:Dot(ld)
    )
    local x = (r1 and r1 > 0 and r1) or (r2 and r2 > 0 and r2) or (r3 and r3 > 0 and r3) or r4
    if not x then return Vector3.zero, 0 end
    local v = (ld + e * x + 0.5 * a * x * x) / x
    return v, x
end

local function toanglesyx(v)
    local x, y, z = v.X, v.Y, v.Z
    return math.asin(y / (x * x + y * y + z * z) ^ 0.5), math.atan2(-x, -z), 0
end

-- Screen-space FOV target selection over replication entries (wapus getClosest)
local function GetClosest(origin, fovRadius, hitpart, visibleCheck)
    local best, bestDist, bestPart = nil, math.huge, nil
    local camera = GetCamera()
    local camPos = camera and camera.CFrame and camera.CFrame.Position or Vector3.zero

    replicationInterface.operateOnAllEntries(function(player, entry)
        if player == LocalPlayer then return end
        if Flag("Aimbot_TeamCheck", true) and not entry._isEnemy then return end

        local model, root = GetChar(player)
        local part = model and (model:FindFirstChild(hitpart) or root)
        if not part then return end

        local target = part.Position
        if (target - camPos).Magnitude > (Flag("ESP_Range", 1000) or 1000) then return end

        local screen, onScreen = camera:WorldToViewportPoint(target)
        local screenDistance = (Vector2.new(screen.X, screen.Y) - origin).Magnitude
        if screen.Z > 0 and onScreen and screenDistance < bestDist and screenDistance < fovRadius then
            if visibleCheck then
                local hit = workspace:Raycast(camPos, target - camPos)
                if hit and hit.Instance and (hit.Instance:IsDescendantOf(model) or hit.Instance == model) then
                    bestDist, bestPart, best = screenDistance, part, player
                end
            else
                bestDist, bestPart, best = screenDistance, part, player
            end
        end
    end)

    return best, bestPart
end

-- FOV radius (px) from VisionWare degrees, matching the GUI's drawn ring
local function FovScreenRadius(FoVDeg, viewportY, camFov)
    local Theta = math.rad(math.clamp(FoVDeg, 1, 179) / 2)
    local Phi = math.rad(math.clamp(camFov, 1, 179) / 2)
    return (viewportY / 2) * (math.tan(Theta) / math.tan(Phi))
end

local velCache = {} -- [player] = { pos, time }
local aimTime
local lastUpdate = 0

RunService.RenderStepped:Connect(function(deltaTime)
    if tick() - lastUpdate < 1 / 30 then return end
    lastUpdate = tick()

    local panic = IsPanic()
    local aimEnabled = not panic and Flag("Aimbot_Enabled", true)
    local key = Flag("Aimbot_Key", Enum.UserInputType.MouseButton2)
    local activating = aimEnabled and IsKeyHeld(key)
    local camera = GetCamera()
    if not camera then return end

    -- Active aimbot -> track velocity / lead up-to-date for all enemies
    local controller, weapon, aiming
    pcall(function()
        controller = weaponInterface and weaponInterface.getActiveWeaponController()
        weapon = controller and controller:getActiveWeapon()
        aiming = weapon and weapon._aiming
    end)

    local clockTime = os.clock()

    if not (activating and aiming) then
        aimTime = nil
        return
    end

    local fovRadius = Flag("Aimbot_FoVSize", 50) or 50
    local useFov = Flag("Aimbot_FoV", true)
    local smooth = Flag("Aimbot_Smoothness", 0.2) or 0.2
    local hitpart = Flag("Aimbot_Hitpart", "Head")
    local visibleCheck = Flag("Aimbot_VisibleOnly", false)

    local origin = camera.ViewportSize * 0.5
    local pxRadius = useFov and FovScreenRadius(fovRadius, camera.ViewportSize.Y, camera.FieldOfView) or math.huge

    local target = GetClosest(origin, pxRadius, hitpart, visibleCheck)
    if not target then return end

    local model, root = GetChar(target)
    local part = model and (model:FindFirstChild(hitpart) or root)
    if not part then return end

    aimTime = aimTime or clockTime
    local targetPos = part.Position

    -- Simple smooth velocity estimate (wapus uses a position-history cache)
    local vel = Vector3.zero
    local prev = velCache[target]
    if prev then
        local dt = (clockTime - prev.time)
        if dt > 0 then vel = (targetPos - prev.pos) / dt end
    end
    velCache[target] = { pos = targetPos, time = clockTime }

    local cameraObj
    pcall(function() cameraObj = cameraInterface.getActiveCamera() end)
    if not cameraObj then return end

    local bulletSpeed = (weapon and weapon._weaponData and weapon._weaponData.bulletspeed) or 10000
    local accel = publicSettings and publicSettings.bulletAcceleration or Vector3.new(0, -workspace.Gravity, 0)
    local velocity = complexTrajectory(camera.CFrame * Vector3.new(0, 0, 0.5), accel, targetPos, bulletSpeed, vel)

    local vx, vy = toanglesyx(velocity)
    local cy = cameraObj._angles.Y
    local x = vx > cameraObj._maxAngle and cameraObj._maxAngle or vx < cameraObj._minAngle and cameraObj._minAngle or vx
    local y = (vy + pi - cy) % tau - pi + cy
    local newangles = Vector3.new(x, y, 0)

    if smooth ~= 0 then
        newangles = cameraObj._angles:Lerp(newangles, math.clamp(1 - smooth + (clockTime - aimTime) ^ 2, 0, 1))
    end

    cameraObj._delta = (newangles - cameraObj._angles) / deltaTime
    cameraObj._angles = newangles
end)

RunService.Heartbeat:Connect(function()
    if espInterface then SyncEspSettings() end
end)

print("[VisionWare] ESP + Aimbot ready (wapus method)")