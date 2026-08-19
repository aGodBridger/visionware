--[[
    VisionWare | ESP + Aimbot  (Phantom Forces)
    ============================================
    Feature set pulled from the wapus source and rebuilt as a self-contained
    module that hooks into the VisionWare GUI (gui.lua). The loader runs
    gui.lua first, then this file, so Library is guaranteed to exist here.

    ESP:     2D boxes, outlines, fill, health bars, tracers, names,
             distances, health %, chams (Highlight), team check, range.
    Aimbot:  FOV / distance selection, smooth assist, GUI keybind + toggle.
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera           = workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer

-- // Wait for the GUI to finish loading, then hook into it
local Library = (getgenv and getgenv().Library) or _G.Library
while not Library do
    task.wait()
    Library = (getgenv and getgenv().Library) or _G.Library
end
local Flags = Library.Flags

local function Flag(Name, Default)
    local v = Flags[Name]
    return v ~= nil and v or Default
end

local function Opacity(Percent)
    return math.clamp((tonumber(Percent) or 100) / 100, 0, 1)
end

local TEAMS = {
    ["Bright blue"]   = "Phantoms",
    ["Bright orange"] = "Ghosts",
}

-- =====================================================================
--  Player tracking
-- =====================================================================
local Tracked = {} -- [player] = data

local function GetTeamName(player)
    return TEAMS[tostring(player and player.TeamColor)] or "Unknown"
end

local function GetCharacter(player)
    return player and player.Character
end

local function GetRootPart(char)
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart or char:FindFirstChildWhichIsA("BasePart")
end

local function GetHead(char)
    return char and char:FindFirstChild("Head")
end

local function CreateCharacterTracking(player)
    local function onCharAdded(char)
        local data = Tracked[player]
        if data then data.char = char end
    end
    if player.Character then onCharAdded(player.Character) end
    player.CharacterAdded:Connect(onCharAdded)
end

Players.PlayerAdded:Connect(CreateCharacterTracking)
for _, p in ipairs(Players:GetPlayers()) do
    CreateCharacterTracking(p)
end

-- =====================================================================
--  Drawing helpers (executor Drawing API with safe guards)
-- =====================================================================
local function NewDrawing(kind)
    if not (Drawing and Drawing.new) then return nil end
    local ok, d = pcall(Drawing.new, kind)
    return ok and d or nil
end

-- Helper: create a vector from a world point to screen
local function WorldToScreen(pos)
    local s, onScreen = Camera:WorldToViewportPoint(pos)
    return Vector2.new(s.X, s.Y), onScreen, s.Z
end

-- =====================================================================
--  ESP state per player
-- =====================================================================
local function NewEsp(player)
    local esp = {
        player = player,
        char   = player.Character,
        sqOutline = NewDrawing("Square"), -- box outline (black, behind)
        sq       = NewDrawing("Square"),  -- box
        sqFill   = NewDrawing("Square"),  -- fill
        health   = NewDrawing("Square"),  -- health bar
        tracer   = NewDrawing("Line"),    -- tracer
        nameLbl  = NewDrawing("Text"),    -- name
        distLbl  = NewDrawing("Text"),    -- distance
        hpLbl    = NewDrawing("Text"),    -- health %
        highlight = nil,
    }

    local function StyleText(t, size)
        if not t then return end
        t.Size = size or 13
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

    -- Chams via Roblox Highlight (no Drawing required)
    if Flag("ESP_Chams", true) then
        esp.highlight = Instance.new("Highlight")
        esp.highlight.Name = "VisionWareCham"
        esp.highlight.FillColor = Flag("ESP_ChamsColor", Color3.fromRGB(255, 255, 255))
        esp.highlight.OutlineColor = Color3.fromRGB(0, 0, 0)
        esp.highlight.FillTransparency = 0.7
        esp.highlight.OutlineTransparency = 0
        esp.highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        esp.highlight.Adornee = player.Character
        esp.highlight.Parent = game:GetService("CoreGui")
        -- Highlight has no ChildAdded/adornee-change visibility; refresh each frame instead
    end

    player.CharacterAdded:Connect(function(char)
        esp.char = char
        if esp.highlight then esp.highlight.Adornee = char end
    end)

    return esp
end

Players.PlayerAdded:Connect(function(player)
    Tracked[player] = NewEsp(player)
end)
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then Tracked[p] = NewEsp(p) end
end
Players.PlayerRemoving:Connect(function(player)
    local esp = Tracked[player]
    if not esp then return end
    pcall(function()
        for _, obj in ipairs({ esp.sq, esp.sqFill, esp.sqOutline, esp.health, esp.tracer, esp.nameLbl, esp.distLbl, esp.hpLbl }) do
            if obj then obj:Remove() end
        end
    end)
    pcall(function() if esp.highlight then esp.highlight:Destroy() end end)
    Tracked[player] = nil
end)

-- =====================================================================
--  Render loop
-- =====================================================================
RunService.RenderStepped:Connect(function()
    local panic = Flag("Misc_Panic", false)
    local espOn = not panic and Flag("ESP_Enabled", true)
    local range = Flag("ESP_Range", 1000) or 1000
    local camPos = Camera.CFrame.Position
    local showTeam = Flag("ESP_ShowTeam", false)
    local thickness = Flag("ESP_BoxThickness", 1) or 1
    local textSize = Flag("ESP_TextSize", 13) or 13
    local drawBoxes = espOn and Flag("ESP_Boxes", true)
    local drawHealth = espOn and Flag("ESP_Health", true)
    local drawTracers = espOn and Flag("ESP_Tracers", true)
    local drawNames = espOn and Flag("ESP_Names", true)
    local drawDist = espOn and Flag("ESP_Distance", false)
    local drawChams = espOn and Flag("ESP_Chams", true)
    local drawHP = espOn and (Flag("ESP_HealthStyle", "Both") == "Text" or Flag("ESP_HealthStyle", "Both") == "Both")
    local useOutline = espOn and Flag("ESP_Outline", true)
    local fillEnabled = espOn and Flag("ESP_BoxType", "2D Box") == "Filled Box"
    local enemyCol = Flag("ESP_EnemyColor", Color3.fromRGB(0, 255, 255))
    local teamCol = Flag("ESP_TeamColor", Color3.fromRGB(86, 227, 120))
    local opacity = Flag("ESP_Opacity", 75)

    for _, esp in pairs(Tracked) do
        local player = esp.player
        local char = GetCharacter(player)
        local root = GetRootPart(char)
        local head = GetHead(char)
        local show = espOn and char and root and char:FindFirstChild("Humanoid")

        local teamCheck = Flag("ESP_TeamCheck", true)
        local enemy = GetTeamName(player) ~= GetTeamName(LocalPlayer)
        local isTeam = not enemy
        local showThis = show and (enemy or (isTeam and showTeam and not teamCheck))

        if not showThis then
            pcall(function()
                for _, obj in ipairs({ esp.sq, esp.sqFill, esp.sqOutline, esp.health, esp.tracer, esp.nameLbl, esp.distLbl, esp.hpLbl }) do
                    if obj then obj.Visible = false end
                end
            end)
            if esp.highlight then esp.highlight.Enabled = false end
            continue
        end

        local color = enemy and enemyCol or teamCol

        -- Distance check
        local dist = (root.Position - camPos).Magnitude
        if dist > range then
            pcall(function()
                for _, obj in ipairs({ esp.sq, esp.sqFill, esp.sqOutline, esp.health, esp.tracer, esp.nameLbl, esp.distLbl, esp.hpLbl }) do
                    if obj then obj.Visible = false end
                end
            end)
            if esp.highlight then esp.highlight.Enabled = false end
            continue
        end

        -- Screen projection of head / feet
        local headPos = (head and head.Position or root.Position) + (head and Vector3.new(0, 0.5, 0) or Vector3.zero)
        local feetPos = root.Position - Vector3.new(0, root.Size.Y * 0.5, 0)

        local top, topOn = WorldToScreen(headPos)
        local bot, botOn = WorldToScreen(feetPos)
        if not topOn and not botOn then
            pcall(function()
                for _, obj in ipairs({ esp.sq, esp.sqFill, esp.sqOutline, esp.health, esp.tracer, esp.nameLbl, esp.distLbl, esp.hpLbl }) do
                    if obj then obj.Visible = false end
                end
            end)
            continue
        end

        local height = math.abs(top.Y - bot.Y)
        local width = height * 0.6
        if height < 5 then
            pcall(function()
                for _, obj in ipairs({ esp.sq, esp.sqFill, esp.sqOutline, esp.health, esp.tracer, esp.nameLbl, esp.distLbl, esp.hpLbl }) do
                    if obj then obj.Visible = false end
                end
            end)
            continue
        end

        local left = top.X - width / 2
        local bboxTop = top.Y
        local bboxBot = bot.Y
        local cy = (bboxTop + bboxBot) / 2

        -- Chams
        if esp.highlight then
            if drawChams and not panic then
                esp.highlight.Enabled = true
                if Flag("ESP_Rainbow", false) then
                    esp.highlight.FillColor = Color3.fromHSV((tick() % 1), 1, 1)
                else
                    esp.highlight.FillColor = Flag("ESP_ChamsColor", Color3.fromRGB(255, 255, 255))
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

        -- Health bar (left side)
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
        elseif esp.health then
            esp.health.Visible = false
            if esp.hpLbl then esp.hpLbl.Visible = false end
        end

        -- Tracer from bottom center of screen
        if drawTracers and esp.tracer then
            local camSize = Camera.ViewportSize
            local from = Vector2.new(camSize.X / 2, camSize.Y)
            local origin = Flag("ESP_TracerType", "From Bottom")
            if origin == "From Top" then from = Vector2.new(camSize.X / 2, 0)
            elseif origin == "From Center" then from = Vector2.new(camSize.X / 2, camSize.Y / 2)
            elseif origin == "From Mouse" then from = Vector2.new(camSize.X / 2, camSize.Y) end

            esp.tracer.From = from
            esp.tracer.To = Vector2.new(left + width / 2, bboxBot)
            esp.tracer.Color = color
            esp.tracer.Thickness = Flag("ESP_TracerThickness", 1) or 1
            esp.tracer.Transparency = Opacity(opacity)
            esp.tracer.Visible = true
        elseif esp.tracer then
            esp.tracer.Visible = false
        end

        -- Name label
        if drawNames and esp.nameLbl then
            local nameMode = Flag("ESP_NameMode", "DisplayName")
            local label = nameMode == "Username" and player.Name or player.DisplayName
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
        elseif esp.nameLbl then
            esp.nameLbl.Visible = false
            if esp.distLbl then esp.distLbl.Visible = false end
        end
    end
end)

-- =====================================================================
--  Aimbot
-- =====================================================================
local lastTarget = nil
local lastTargetLostTime = nil

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

local function GetAimTarget()
    local mode = Flag("Aimbot_Target", "Closest to Crosshair")
    local hitpart = Flag("Aimbot_Hitpart", "Head")
    local camPos = Camera.CFrame.Position
    local center = Camera.ViewportSize / 2
    local best, bestScore = nil, math.huge

    for _, esp in pairs(Tracked) do
        local player = esp.player
        if player == LocalPlayer then continue end
        if Flag("Aimbot_TeamCheck", true) and GetTeamName(player) == GetTeamName(LocalPlayer) then continue end

        local char = GetCharacter(player)
        local root = GetRootPart(char)
        if not char or not root or not char:FindFirstChild("Humanoid") then continue end

        local part = char:FindFirstChild(hitpart) or root
        local pos = part.Position
        if (pos - camPos).Magnitude > (Flag("ESP_Range", 1000) or 1000) then continue end

        local screen, onScreen = WorldToScreen(pos)
        if not onScreen then continue end

        local score
        if mode == "Closest to Player" then
            score = (pos - camPos).Magnitude
        else -- Closest to Crosshair / Lowest Health
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
    local panic = Flag("Misc_Panic", false)
    local enabled = not panic and Flag("Aimbot_Enabled", true)
    local key = Flag("Aimbot_Key", Enum.UserInputType.MouseButton2)
    _G.aimbotActive = enabled and IsKeyHeld(key)

    if not _G.aimbotActive then
        lastTarget = nil
        return
    end

    local useFov = Flag("Aimbot_FoV", true)
    local fovRadius = Flag("Aimbot_FoVSize", 50) or 50
    local smooth = Flag("Aimbot_Smoothness", 0.2) or 0.2
    local center = Camera.ViewportSize / 2
    local hitpart = Flag("Aimbot_Hitpart", "Head")

    local target = GetAimTarget()

    -- Enforce FOV for "Closest to Crosshair" style
    if target and useFov and Flag("Aimbot_Target", "Closest to Crosshair") == "Closest to Crosshair" then
        local char = GetCharacter(target.player)
        local part = char:FindFirstChild(hitpart) or GetRootPart(char)
        local screen, onScreen = WorldToScreen(part and part.Position or Vector3.zero)
        if onScreen and (screen - center).Magnitude > fovRadius then
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

    local char = GetCharacter(target.player)
    local part = char and (char:FindFirstChild(hitpart) or GetRootPart(char))
    if not part then return end

    local screen, onScreen = WorldToScreen(part.Position)
    if not onScreen then return end

    local delta = (screen - center) * smooth
    MoveMouse(delta.X, delta.Y)
end)

print("VisionWare ESP + Aimbot loaded")
