--[[
    VisionWare | ESP + Aimbot  (Phantom Forces)  -- Xeno compatible
    ==============================================================
    IMPORTANT: This build is made for the Xeno executor.
    wapus's method (hooking Phantom Forces internal modules via getgc /
    run_on_actor) needs functions Xeno does not provide (low sUNC,
    external executor). So ESP + Aimbot use the standard executor APIs
    Xeno DOES support: Drawing, Players/Character tracking,
    WorldToViewportPoint projection, and mousemoverel.

    Not-loaded-too-soon: the camera is resolved fresh every frame (never
    captured at load) and we wait for the game to be ready before
    building ESP objects. All game access is nil/pcall-safe so it
    degrades gracefully until the round starts.
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer      = Players.LocalPlayer

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

local function GetCamera()
    return workspace.CurrentCamera
end

local function IsPanic()
    return Flag("Misc_Panic", false)
end

local TEAMS = {
    ["Bright blue"]   = "Phantoms",
    ["Bright orange"] = "Ghosts",
}

local function TeamName(player)
    return TEAMS[tostring(player and player.TeamColor)] or "Unknown"
end

-- =====================================================================
--  Drawing helpers (Xeno Drawing API, safe)
-- =====================================================================
local function NewDrawing(kind)
    if not (Drawing and Drawing.new) then return nil end
    local ok, d = pcall(Drawing.new, kind)
    return ok and d or nil
end

local function WorldToScreen(pos)
    local camera = GetCamera()
    if not camera then return nil, false end
    local s, onScreen = camera:WorldToViewportPoint(pos)
    return Vector2.new(s.X, s.Y), onScreen
end

-- =====================================================================
--  ESP state per player  (Drawings created ONCE, not per frame)
-- =====================================================================
local Tracked = {} -- [player] = esp

local function NewEsp(player)
    local esp = {
        player = player,
        sq       = NewDrawing("Square"),
        sqFill   = NewDrawing("Square"),
        sqOutline= NewDrawing("Square"),
        health   = NewDrawing("Square"),
        tracer   = NewDrawing("Line"),
        nameLbl  = NewDrawing("Text"),
        distLbl  = NewDrawing("Text"),
        hpLbl    = NewDrawing("Text"),
        highlight = nil,
    }

    local function StyleText(t)
        if not t then return end
        t.Size = 13
        t.Font = Drawing.Fonts.UI
        t.Center = true
        t.Outline = true
        t.OutlineColor = Color3.fromRGB(0, 0, 0)
        t.Visible = false
    end
    StyleText(esp.nameLbl)
    StyleText(esp.distLbl)
    StyleText(esp.hpLbl)

    if esp.sq then esp.sq.Filled = false; esp.sq.Visible = false end
    if esp.sqFill then esp.sqFill.Filled = true; esp.sqFill.Visible = false end
    if esp.sqOutline then esp.sqOutline.Filled = false; esp.sqOutline.Visible = false end
    if esp.health then esp.health.Filled = true; esp.health.Visible = false end
    if esp.tracer then esp.tracer.Visible = false end

    return esp
end

Players.PlayerAdded:Connect(function(p)
    if p ~= LocalPlayer then Tracked[p] = NewEsp(p) end
end)
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then Tracked[p] = NewEsp(p) end
end
Players.PlayerRemoving:Connect(function(player)
    local esp = Tracked[player]
    if not esp then return end
    pcall(function()
        for _, o in ipairs({ esp.sq, esp.sqFill, esp.sqOutline, esp.health, esp.tracer, esp.nameLbl, esp.distLbl, esp.hpLbl }) do
            if o then o:Remove() end
        end
    end)
    pcall(function() if esp.highlight then esp.highlight:Destroy() end end)
    Tracked[player] = nil
end)

local function GetChar(player)
    return player and player.Character
end

local function GetRoot(char)
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart or char:FindFirstChildWhichIsA("BasePart")
end

local function GetHead(char)
    return char and char:FindFirstChild("Head")
end

-- =====================================================================
--  ESP render loop  (30 fps throttle to keep Xeno smooth)
-- =====================================================================
local lastRender = 0

RunService.RenderStepped:Connect(function()
    if tick() - lastRender < 1 / 30 then return end
    lastRender = tick()

    local panic = IsPanic()
    local espOn = not panic and Flag("ESP_Enabled", true)
    local range = Flag("ESP_Range", 1000) or 1000
    local camera = GetCamera()
    if not camera then return end
    local camPos = camera.CFrame.Position

    local showTeam = Flag("ESP_ShowTeam", false)
    local teamCheck = Flag("ESP_TeamCheck", true)
    local thickness = Flag("ESP_BoxThickness", 1) or 1
    local textSize = Flag("ESP_TextSize", 13) or 13
    local drawBoxes = espOn and Flag("ESP_Boxes", true)
    local drawHealth = espOn and Flag("ESP_Health", true)
    local drawTracers = espOn and Flag("ESP_Tracers", true)
    local drawNames = espOn and Flag("ESP_Names", true)
    local drawDist = espOn and Flag("ESP_Distance", false)
    local drawChams = espOn and Flag("ESP_Chams", true)
    local hs = Flag("ESP_HealthStyle", "Both")
    local drawHP = espOn and (hs == "Text" or hs == "Both")
    local useOutline = espOn and Flag("ESP_Outline", true)
    local fillEnabled = espOn and Flag("ESP_BoxType", "2D Box") == "Filled Box"
    local enemyCol = Flag("ESP_EnemyColor", Color3.fromRGB(0, 255, 255)) or Color3.fromRGB(0, 255, 255)
    local teamCol = Flag("ESP_TeamColor", Color3.fromRGB(86, 227, 120)) or Color3.fromRGB(86, 227, 120)
    local opacity = Opacity(Flag("ESP_Opacity", 75))

    for _, esp in pairs(Tracked) do
        local player = esp.player
        local char = GetChar(player)
        local root = GetRoot(char)
        local head = GetHead(char)

        local enemy = TeamName(player) ~= TeamName(LocalPlayer)
        local isTeam = not enemy
        local showThis = espOn and char and root and char:FindFirstChild("Humanoid") and (enemy or (isTeam and showTeam and not teamCheck))

        local function HideAll()
            pcall(function()
                for _, o in ipairs({ esp.sq, esp.sqFill, esp.sqOutline, esp.health, esp.tracer, esp.nameLbl, esp.distLbl, esp.hpLbl }) do
                    if o then o.Visible = false end
                end
            end)
        end

        if not showThis then
            HideAll()
            if esp.highlight then esp.highlight.Enabled = false end
            continue
        end

        local color = enemy and enemyCol or teamCol

        local dist = (root.Position - camPos).Magnitude
        if dist > range then
            HideAll()
            if esp.highlight then esp.highlight.Enabled = false end
            continue
        end

        local headPos = (head and head.Position or root.Position) + (head and Vector3.new(0, 0.5, 0) or Vector3.zero)
        local feetPos = root.Position - Vector3.new(0, root.Size.Y * 0.5, 0)

        local top, topOn = WorldToScreen(headPos)
        local bot, botOn = WorldToScreen(feetPos)
        if not top or not bot or (not topOn and not botOn) then
            HideAll()
            continue
        end

        local height = math.abs(top.Y - bot.Y)
        local width = height * 0.6
        if height < 5 then
            HideAll()
            continue
        end

        local left = top.X - width / 2
        local bboxTop = top.Y
        local bboxBot = bot.Y
        local cy = (bboxTop + bboxBot) / 2

        -- Chams
        if esp.highlight then
            if drawChams then
                esp.highlight.Enabled = true
                if Flag("ESP_Rainbow", false) then
                    esp.highlight.FillColor = Color3.fromHSV((tick() % 1), 1, 1)
                else
                    esp.highlight.FillColor = Flag("ESP_ChamsColor", Color3.fromRGB(255, 255, 255)) or Color3.fromRGB(255, 255, 255)
                end
            else
                esp.highlight.Enabled = false
            end
        end

        -- Box
        if drawBoxes and esp.sq then
            local o = Opacity(opacity)
            local inset = 1
            if useOutline and esp.sqOutline then
                esp.sqOutline.Color = Color3.fromRGB(0, 0, 0)
                esp.sqOutline.Thickness = thickness + 2
                esp.sqOutline.Transparency = o
                esp.sqOutline.Position = Vector2.new(left, bboxTop)
                esp.sqOutline.Size = Vector2.new(width, height)
                esp.sqOutline.Visible = true
            elseif esp.sqOutline then
                esp.sqOutline.Visible = false
            end

            esp.sq.Color = color
            esp.sq.Thickness = thickness
            esp.sq.Transparency = o
            esp.sq.Position = Vector2.new(left + inset, bboxTop + inset)
            esp.sq.Size = Vector2.new(width - inset * 2, height - inset * 2)
            esp.sq.Visible = true

            if fillEnabled and esp.sqFill then
                esp.sqFill.Color = color
                esp.sqFill.Transparency = o * 0.3
                esp.sqFill.Position = esp.sq.Position
                esp.sqFill.Size = esp.sq.Size
                esp.sqFill.Visible = true
            elseif esp.sqFill then
                esp.sqFill.Visible = false
            end
        else
            if esp.sq then esp.sq.Visible = false end
            if esp.sqFill then esp.sqFill.Visible = false end
            if esp.sqOutline then esp.sqOutline.Visible = false end
        end

        -- Health bar
        if drawHealth and esp.health then
            local humanoid = char:FindFirstChild("Humanoid")
            local hp = humanoid and humanoid.Health or 100
            local maxHp = humanoid and humanoid.MaxHealth or 100
            local frac = math.clamp(hp / maxHp, 0, 1)
            local barW = 3
            local barX = left - barW - 3
            local o = Opacity(opacity)
            esp.health.Color = Color3.fromRGB(255, math.floor(255 * frac), math.floor(255 * (1 - frac)))
            esp.health.Transparency = o
            esp.health.Position = Vector2.new(barX, bboxTop + (height * (1 - frac)))
            esp.health.Size = Vector2.new(barW, height * frac)
            esp.health.Visible = true

            if drawHP and esp.hpLbl then
                esp.hpLbl.Text = tostring(math.floor(frac * 100)) .. "%"
                esp.hpLbl.Color = color
                esp.hpLbl.Size = textSize - 3
                esp.hpLbl.Position = Vector2.new(left + width + 4, cy - (textSize / 2))
                esp.hpLbl.Visible = true
            elseif esp.hpLbl then
                esp.hpLbl.Visible = false
            end
        else
            if esp.health then esp.health.Visible = false end
            if esp.hpLbl then esp.hpLbl.Visible = false end
        end

        -- Tracer
        if drawTracers and esp.tracer then
            local camSize = camera.ViewportSize
            local from = Vector2.new(camSize.X / 2, camSize.Y)
            local origin = Flag("ESP_TracerType", "From Bottom")
            if origin == "From Top" then from = Vector2.new(camSize.X / 2, 0)
            elseif origin == "From Center" then from = Vector2.new(camSize.X / 2, camSize.Y / 2) end

            esp.tracer.From = from
            esp.tracer.To = Vector2.new(left + width / 2, bboxBot)
            esp.tracer.Color = color
            esp.tracer.Thickness = Flag("ESP_TracerThickness", 1) or 1
            esp.tracer.Transparency = opacity
            esp.tracer.Visible = true
        elseif esp.tracer then
            esp.tracer.Visible = false
        end

        -- Name / distance
        if drawNames and esp.nameLbl then
            local label = Flag("ESP_NameMode", "DisplayName") == "Username" and player.Name or player.DisplayName
            esp.nameLbl.Text = label
            esp.nameLbl.Color = color
            esp.nameLbl.Size = textSize
            esp.nameLbl.Position = Vector2.new(left + width / 2, bboxTop - textSize - 2)
            esp.nameLbl.Visible = true

            if drawDist and esp.distLbl then
                esp.distLbl.Text = string.format("%.0fm", dist)
                esp.distLbl.Color = color
                esp.distLbl.Size = textSize - 4
                esp.distLbl.Position = Vector2.new(left + width / 2, bboxBot + 4)
                esp.distLbl.Visible = true
            elseif esp.distLbl then
                esp.distLbl.Visible = false
            end
        else
            if esp.nameLbl then esp.nameLbl.Visible = false end
            if esp.distLbl then esp.distLbl.Visible = false end
        end
    end
end)

-- =====================================================================
--  Aimbot  (Xeno: mousemoverel-based, no internal module hooks)
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

local function MoveMouse(dx, dy)
    pcall(function()
        if mousemoverel then mousemoverel(dx, dy)
        elseif syn and syn.input and syn.input.mousemoverel then syn.input.mousemoverel(dx, dy) end
    end)
end

local lastTarget, lastTargetLostTime

local function GetAimTarget()
    local mode = Flag("Aimbot_Target", "Closest to Crosshair")
    local hitpart = Flag("Aimbot_Hitpart", "Head")
    local camera = GetCamera()
    if not camera then return nil end
    local camPos = camera.CFrame.Position
    local center = camera.ViewportSize / 2
    local best, bestScore = nil, math.huge

    for _, esp in pairs(Tracked) do
        local player = esp.player
        if player == LocalPlayer then continue end
        if Flag("Aimbot_TeamCheck", true) and TeamName(player) == TeamName(LocalPlayer) then continue end

        local char = GetChar(player)
        local root = GetRoot(char)
        if not char or not root or not char:FindFirstChild("Humanoid") then continue end

        local part = char:FindFirstChild(hitpart) or root
        local pos = part.Position
        if (pos - camPos).Magnitude > (Flag("ESP_Range", 1000) or 1000) then continue end

        local screen, onScreen = WorldToScreen(pos)
        if not screen or not onScreen then continue end

        local score
        if mode == "Closest to Player" then
            score = (pos - camPos).Magnitude
        else
            local h = char:FindFirstChild("Humanoid")
            score = (screen - center).Magnitude
            if mode == "Lowest Health" then
                score = score + (h and (h.MaxHealth - h.Health) * 100 or 0)
            end
        end

        if score < bestScore then
            bestScore = score
            best = esp
        end
    end
    return best
end

RunService.Heartbeat:Connect(function()
    local panic = IsPanic()
    local enabled = not panic and Flag("Aimbot_Enabled", true)
    local key = Flag("Aimbot_Key", Enum.UserInputType.MouseButton2)
    local active = enabled and IsKeyHeld(key)
    _G.aimbotActive = active

    if not active then
        lastTarget = nil
        return
    end

    local camera = GetCamera()
    if not camera then return end

    local useFov = Flag("Aimbot_FoV", true)
    local fovRadius = Flag("Aimbot_FoVSize", 50) or 50
    local smooth = Flag("Aimbot_Smoothness", 0.2) or 0.2
    local hitpart = Flag("Aimbot_Hitpart", "Head")
    local center = camera.ViewportSize / 2

    local target = GetAimTarget()

    if target and useFov and Flag("Aimbot_Target", "Closest to Crosshair") == "Closest to Crosshair" then
        local char = GetChar(target.player)
        local part = char and (char:FindFirstChild(hitpart) or GetRoot(char))
        local screen, onScreen = WorldToScreen(part and part.Position or Vector3.zero)
        if screen and onScreen and (screen - center).Magnitude > fovRadius then
            target = nil
        end
    end

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

    local char = GetChar(target.player)
    local part = char and (char:FindFirstChild(hitpart) or GetRoot(char))
    if not part then return end

    local screen, onScreen = WorldToScreen(part.Position)
    if not screen or not onScreen then return end

    local delta = (screen - center) * smooth
    MoveMouse(delta.X, delta.Y)
end)

print("[VisionWare] ESP + Aimbot loaded (Xeno build)")
