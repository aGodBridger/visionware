--[[
    VisionWare | Full feature set (ESP + Aimbot + Triggerbot + Silent Aim + Movement + Visuals + Crosshair)
    Runs on Solara / Xeno / any Drawing-capable executor. No getgc required.
    Reads every flag from Library.Flags (created by gui.lua).
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local VirtualUser      = game:GetService("VirtualUser")
local LocalPlayer      = Players.LocalPlayer

local Library, Flags
for _ = 1, 100 do
    Library = (getgenv and getgenv().Library) or _G.Library
    if Library and Library.Flags then break end
    task.wait(0.1)
end
Flags = (Library and Library.Flags) or {}

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

local function GetChar(player)
    return player and player.Character
end

local function GetRoot(char)
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart or char:FindFirstChildWhichIsA("BasePart")
end

-- Generic team detection for any Roblox game.
-- A teammate is someone whose HumanoidRootPart carries a "TeammateLabel" child
-- (the common pattern across many games), or who shares the same Team and is
-- not Neutral. Everyone else (and Neutral/no-team players) is treated as an enemy.
local function IsEnemy(player)
    if player == LocalPlayer then return false end
    local root = GetRoot(GetChar(player))
    if root and root:FindFirstChild("TeammateLabel") then return false end
    if player.Neutral then return true end
    local myTeam = LocalPlayer.Team
    local theirTeam = player.Team
    if myTeam and theirTeam and myTeam == theirTeam then return false end
    return true
end

local function GetHead(char)
    return char and char:FindFirstChild("Head")
end

local function NewDrawing(kind)
    if not (Drawing and Drawing.new) then return nil end
    local ok, d = pcall(Drawing.new, kind)
    return ok and d or nil
end

local function WorldToScreen(pos)
    local camera = GetCamera()
    if not camera then return nil, false end
    local s, ok = camera:WorldToViewportPoint(pos)
    return Vector2.new(s.X, s.Y), ok
end

local function IsVisibleFromCamera(pos, targetChar)
    local camera = GetCamera()
    if not camera then return true end
    local origin = camera.CFrame.Position
    local ray = workspace:Raycast(origin, pos - origin)
    if not ray then return true end
    local inst = ray.Instance
    if not inst then return true end
    return inst:IsDescendantOf(targetChar) or inst == targetChar
end

local function GetPlayerFromPart(part)
    if not part then return nil end
    local p = Players:GetPlayerFromCharacter(part)
    if p then return p end
    local anc = part:FindFirstAncestorOfClass("Folder") or part:FindFirstAncestorWhere(function(x)
        return Players:GetPlayerFromCharacter(x) ~= nil
    end)
    return anc and Players:GetPlayerFromCharacter(anc)
end

local Tracked = {}

local SKELETON_LINKS = {
    {"HumanoidRootPart", "LowerTorso"},
    {"LowerTorso", "UpperTorso"},
    {"UpperTorso", "Head"},
    {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"}, {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"}, {"RightLowerArm", "RightHand"},
    {"LowerTorso", "LeftUpperLeg"}, {"LeftUpperLeg", "LeftLowerLeg"}, {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"}, {"RightUpperLeg", "RightLowerLeg"}, {"RightLowerLeg", "RightFoot"},
}

local function NewEsp(player)
    local esp = {
        player = player,
        sq        = NewDrawing("Square"),
        sqOutline = NewDrawing("Square"),
        health    = NewDrawing("Square"),
        tracer    = NewDrawing("Line"),
        nameLbl   = NewDrawing("Text"),
        distLbl   = NewDrawing("Text"),
        hpLbl     = NewDrawing("Text"),
        headDot   = NewDrawing("Square"),
        skeleton  = {},
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

    for _, key in ipairs({ "sq", "sqOutline", "health", "headDot" }) do
        local d = esp[key]
        if d then
            if key == "sqOutline" then d.Filled = false else d.Filled = true end
            d.Visible = false
        end
    end
    if esp.tracer then esp.tracer.Visible = false end

    return esp
end

local function GetSkeletonLine(esp, i)
    if not esp.skeleton[i] then
        local l = NewDrawing("Line")
        if l then l.Visible = false end
        esp.skeleton[i] = l
    end
    return esp.skeleton[i]
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
        for _, k in ipairs({ "sq", "sqOutline", "health", "tracer", "nameLbl", "distLbl", "hpLbl", "headDot" }) do
            if esp[k] then esp[k]:Remove() end
        end
        for _, l in ipairs(esp.skeleton) do if l then l:Remove() end end
    end)
    pcall(function() if esp.highlight then esp.highlight:Destroy() end end)
    Tracked[player] = nil
end)

local lastRender = 0
if Drawing and Drawing.new then
RunService.RenderStepped:Connect(function()
    if tick() - lastRender < 1 / 30 then return end
    lastRender = tick()

    local panic = IsPanic()
    local espOn = not panic and Flag("ESP_Enabled", true)
    local range = Flag("ESP_Range", 1000) or 1000
    local camera = GetCamera()
    if not camera then return end
    local camPos = camera.CFrame.Position
    local camSize = camera.ViewportSize

    local showTeam = Flag("ESP_ShowTeam", false)
    local teamCheck = Flag("ESP_TeamCheck", true)
    local thickness = Flag("ESP_BoxThickness", 1) or 1
    local textSize = Flag("ESP_TextSize", 13) or 13
    local boxOn = espOn and Flag("ESP_Boxes", true)
    local boxType = Flag("ESP_BoxType", "2D Box")
    local useOutline = espOn and Flag("ESP_Outline", true)
    local nameOn = espOn and Flag("ESP_Names", true)
    local nameMode = Flag("ESP_NameMode", "DisplayName")
    local distOn = espOn and Flag("ESP_Distance", false)
    local healthOn = espOn and Flag("ESP_Health", true)
    local hs = Flag("ESP_HealthStyle", "Both")
    local hpHpOn = espOn and (hs == "Text" or hs == "Both")
    local hbSide = Flag("ESP_HealthBarSide", "Left")
    local tracerOn = espOn and Flag("ESP_Tracers", true)
    local tracerOrigin = Flag("ESP_TracerType", "From Bottom")
    local tracerThick = Flag("ESP_TracerThickness", 1) or 1
    local skeletonOn = espOn and Flag("ESP_Skeleton", false)
    local skelThick = Flag("ESP_SkeletonThickness", 1) or 1
    local headOn = espOn and Flag("ESP_Head", false)
    local chamsOn = espOn and Flag("ESP_Chams", true)
    local visibleOnly = Flag("ESP_VisibleOnly", false)
    local rainbow = Flag("ESP_Rainbow", false)
    local rainbowSpeed = Flag("ESP_RainbowSpeed", 1) or 1
    local rainbowParts = Flag("ESP_RainbowParts", "All")
    local enemyCol = Flag("ESP_EnemyColor", Color3.fromRGB(0, 255, 255)) or Color3.fromRGB(0, 255, 255)
    local teamCol  = Flag("ESP_TeamColor", Color3.fromRGB(86, 227, 120)) or Color3.fromRGB(86, 227, 120)
    local opacity = Opacity(Flag("ESP_Opacity", 75))
    local chamCol = Flag("ESP_ChamsColor", Color3.fromRGB(255, 255, 255)) or Color3.fromRGB(255, 255, 255)

    for _, esp in pairs(Tracked) do
        local player = esp.player
        local char = GetChar(player)
        local root = GetRoot(char)
        local head = GetHead(char)

        local enemy = IsEnemy(player)
        local isTeam = not enemy
        local showThis = espOn and char and root and char:FindFirstChild("Humanoid") and (enemy or (isTeam and showTeam and not teamCheck))

        local function HideAll()
            pcall(function()
                for _, k in ipairs({ "sq", "sqOutline", "health", "tracer", "nameLbl", "distLbl", "hpLbl", "headDot" }) do
                    if esp[k] then esp[k].Visible = false end
                end
                for _, l in ipairs(esp.skeleton) do if l then l.Visible = false end end
            end)
        end

        if not showThis then
            HideAll()
            if esp.highlight then esp.highlight.Enabled = false end
            continue
        end

        local color = enemy and enemyCol or teamCol
        if rainbow and (rainbowParts == "All" or rainbowParts == "Boxes") then
            color = Color3.fromHSV((tick() * rainbowSpeed) % 1, 1, 1)
        end

        local dist = (root.Position - camPos).Magnitude
        if dist > range then
            HideAll()
            if esp.highlight then esp.highlight.Enabled = false end
            continue
        end

        if visibleOnly then
            local visible = IsVisibleFromCamera(head and head.Position or root.Position, char)
            if not visible then
                HideAll()
                if esp.highlight then esp.highlight.Enabled = false end
                continue
            end
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

        if esp.highlight then
            esp.highlight.Enabled = chamsOn
            if chamsOn then
                esp.highlight.FillColor = rainbow and (rainbowParts == "All" or rainbowParts == "Boxes") and Color3.fromHSV((tick() * rainbowSpeed) % 1, 1, 1) or chamCol
            end
        end

        local tracerCol = color
        local nameCol = color
        if rainbow then
            local hc = Color3.fromHSV((tick() * rainbowSpeed) % 1, 1, 1)
            if rainbowParts == "All" or rainbowParts == "Boxes" then
                esp.sq.Color = hc
                if esp.sqOutline then esp.sqOutline.Color = Color3.fromRGB(0, 0, 0) end
            end
            if rainbowParts == "All" or rainbowParts == "Tracers" then tracerCol = hc end
            if rainbowParts == "All" or rainbowParts == "Text" then nameCol = hc end
        else
            if esp.sq then esp.sq.Color = color end
        end

        if boxOn and esp.sq then
            local o = Opacity(opacity)
            local inset = 1

            if boxType == "2D Box" or boxType == "Filled Box" or boxType == "Corner Box" then
                if useOutline and esp.sqOutline and boxType ~= "Corner Box" then
                    esp.sqOutline.Color = Color3.fromRGB(0, 0, 0)
                    esp.sqOutline.Thickness = thickness + 2
                    esp.sqOutline.Transparency = o
                    esp.sqOutline.Position = Vector2.new(left, bboxTop)
                    esp.sqOutline.Size = Vector2.new(width, height)
                    esp.sqOutline.Visible = true
                elseif esp.sqOutline then
                    esp.sqOutline.Visible = false
                end

                if boxType == "Corner Box" then
                    esp.sq.Visible = false
                    local cLen = math.clamp(width * 0.25, 8, width)
                    local tl, tr, bl, br = Vector2.new(left, bboxTop), Vector2.new(left + width, bboxTop), Vector2.new(left, bboxBot), Vector2.new(left + width, bboxBot)
                    local corners = {
                        { tl, tl + Vector2.new(cLen, 0), tl + Vector2.new(0, cLen) },
                        { tr, tr - Vector2.new(cLen, 0), tr + Vector2.new(0, cLen) },
                        { bl, bl + Vector2.new(cLen, 0), bl - Vector2.new(0, cLen) },
                        { br, br - Vector2.new(cLen, 0), br - Vector2.new(0, cLen) },
                    }
                    for i, c in ipairs(corners) do
                        local l1 = GetSkeletonLine(esp, 300 + (i - 1) * 2)
                        local l2 = GetSkeletonLine(esp, 301 + (i - 1) * 2)
                        if l1 then
                            l1.From = c[1]; l1.To = c[2]
                            l1.Color = color; l1.Thickness = thickness + 1; l1.Transparency = o
                            l1.Visible = true
                        end
                        if l2 then
                            l2.From = c[1]; l2.To = c[3]
                            l2.Color = color; l2.Thickness = thickness + 1; l2.Transparency = o
                            l2.Visible = true
                        end
                    end
                else
                    esp.sq.Color = color
                    esp.sq.Thickness = thickness
                    esp.sq.Transparency = o
                    esp.sq.Position = Vector2.new(left + inset, bboxTop + inset)
                    esp.sq.Size = Vector2.new(width - inset * 2, height - inset * 2)
                    if boxType == "Filled Box" then
                        esp.sq.Filled = true
                    else
                        esp.sq.Filled = false
                    end
                    esp.sq.Visible = true
                end
            elseif boxType == "3D Box" then
                esp.sq.Visible = false
                if esp.sqOutline then esp.sqOutline.Visible = false end
                local hrp = root
                local cf = hrp.CFrame
                local hx = width
                local hy = height
                local hz = hrp.Size.Z or 1
                local corners = {}
                local offsets = {
                    Vector3.new(-hx / 4, -hy / 2, -hz), Vector3.new(hx / 4, -hy / 2, -hz),
                    Vector3.new(hx / 4, hy / 2, -hz), Vector3.new(-hx / 4, hy / 2, -hz),
                    Vector3.new(-hx / 4, -hy / 2, hz), Vector3.new(hx / 4, -hy / 2, hz),
                    Vector3.new(hx / 4, hy / 2, hz), Vector3.new(-hx / 4, hy / 2, hz),
                }
                for _, o in ipairs(offsets) do
                    local p, ok = WorldToScreen(cf:PointToWorldSpace(o))
                    corners[#corners + 1] = ok and p or nil
                end
                local edges = {
                    {1,2},{2,3},{3,4},{4,1},
                    {5,6},{6,7},{7,8},{8,5},
                    {1,5},{2,6},{3,7},{4,8},
                }
                for i, e in ipairs(edges) do
                    local a, b = corners[e[1]], corners[e[2]]
                    if a and b then
                        local l = GetSkeletonLine(esp, 200 + i)
                        if l then
                            l.From = a
                            l.To = b
                            l.Color = color
                            l.Thickness = thickness + 1
                            l.Transparency = Opacity(opacity)
                            l.Visible = true
                        end
                    end
                end
            end
        else
            if esp.sq then esp.sq.Visible = false end
            if esp.sqOutline then esp.sqOutline.Visible = false end
            for i = 201, 212 do local l = esp.skeleton[i] if l then l.Visible = false end end
            for i = 300, 307 do local l = esp.skeleton[i] if l then l.Visible = false end end
        end

        if skeletonOn then
            for i, pair in ipairs(SKELETON_LINKS) do
                local a = char:FindFirstChild(pair[1])
                local b = char:FindFirstChild(pair[2])
                if a and b then
                    local pa, onA = WorldToScreen(a.Position)
                    local pb, onB = WorldToScreen(b.Position)
                    if pa and pb and (onA or onB) then
                        local l = GetSkeletonLine(esp, i)
                        if l then
                            l.From = pa
                            l.To = pb
                            l.Color = Flag("ESP_SkeletonColor", Color3.fromRGB(255,255,255)) or Color3.fromRGB(255,255,255)
                            l.Thickness = skelThick
                            l.Visible = true
                        end
                    end
                end
            end
        else
            for i = 1, #SKELETON_LINKS do local l = esp.skeleton[i] if l then l.Visible = false end end
        end

        if headOn and esp.headDot then
            local hp, on = WorldToScreen(head and head.Position or root.Position)
            if hp then
                esp.headDot.Color = color
                esp.headDot.Position = hp - Vector2.new(thickness, thickness) * 2
                esp.headDot.Size = Vector2.new(thickness * 4, thickness * 4)
                esp.headDot.Visible = true
            end
        elseif esp.headDot then
            esp.headDot.Visible = false
        end

        if healthOn and esp.health then
            local humanoid = char:FindFirstChild("Humanoid")
            local hp = humanoid and humanoid.Health or 100
            local maxHp = humanoid and humanoid.MaxHealth or 100
            local frac = math.clamp(hp / maxHp, 0, 1)
            local barW = 3
            local sideSign = hbSide == "Left" and -1 or 1
            local barX = sideSign == -1 and (left - barW - 3) or (left + width + 3)
            local o = Opacity(opacity)
            esp.health.Color = Color3.fromRGB(255, math.floor(255 * frac), math.floor(255 * (1 - frac)))
            esp.health.Transparency = o
            esp.health.Position = Vector2.new(barX, bboxTop + (height * (1 - frac)))
            esp.health.Size = Vector2.new(barW, height * frac)
            esp.health.Visible = true

            if hpHpOn and esp.hpLbl then
                esp.hpLbl.Text = tostring(math.floor(frac * 100)) .. "%"
                esp.hpLbl.Color = color
                esp.hpLbl.Size = textSize - 3
                esp.hpLbl.Position = Vector2.new(left + width + (sideSign == 1 and 3 or 4), cy - (textSize / 2))
                esp.hpLbl.Visible = true
            elseif esp.hpLbl then
                esp.hpLbl.Visible = false
            end
        else
            if esp.health then esp.health.Visible = false end
            if esp.hpLbl then esp.hpLbl.Visible = false end
        end

        if tracerOn and esp.tracer then
            local from = Vector2.new(camSize.X / 2, camSize.Y)
            if tracerOrigin == "From Top" then from = Vector2.new(camSize.X / 2, 0)
            elseif tracerOrigin == "From Center" then from = Vector2.new(camSize.X / 2, camSize.Y / 2)
            elseif tracerOrigin == "From Mouse" then
                local m = Players.LocalPlayer:GetMouse()
                from = Vector2.new(m.X, m.Y)
            end

            esp.tracer.From = from
            esp.tracer.To = Vector2.new(left + width / 2, bboxBot)
            esp.tracer.Color = tracerCol
            esp.tracer.Thickness = tracerThick
            esp.tracer.Transparency = opacity
            esp.tracer.Visible = true
        elseif esp.tracer then
            esp.tracer.Visible = false
        end

        if nameOn and esp.nameLbl then
            local label = nameMode == "Username" and player.Name or player.DisplayName
            esp.nameLbl.Text = label
            esp.nameLbl.Color = nameCol
            esp.nameLbl.Size = textSize
            esp.nameLbl.Position = Vector2.new(left + width / 2, bboxTop - textSize - 2)
            esp.nameLbl.Visible = true

            if distOn and esp.distLbl then
                esp.distLbl.Text = string.format("%.0fm", dist)
                esp.distLbl.Color = nameCol
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
end

-- =====================================================================
--  AIMBOT
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

local function SelectTarget(tabPrefix, hitpartFlag)
    local mode = Flag(tabPrefix .. "_Target", "Closest to Crosshair")
    local hpName = Flag(hitpartFlag, "Head")
    local camera = GetCamera()
    if not camera then return nil end
    local camPos = camera.CFrame.Position
    local center = camera.ViewportSize / 2
    local best, bestScore = nil, math.huge
    for _, esp in pairs(Tracked) do
        local player = esp.player
        if player == LocalPlayer then continue end
        if Flag(tabPrefix .. "_TeamCheck", true) and not IsEnemy(player) then continue end
        local char = GetChar(player)
        local root = GetRoot(char)
        if not char or not root or not char:FindFirstChild("Humanoid") then continue end
        local part = char:FindFirstChild(hpName) or root
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

local lastTarget, lastTargetLostTime
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

    local target = SelectTarget("Aimbot", "Aimbot_Hitpart")

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

-- =====================================================================
--  TRIGGERBOT
-- =====================================================================
local lastShot = 0
RunService.Heartbeat:Connect(function(t)
    if IsPanic() or not Flag("Triggerbot_Enabled", false) then return end
    local key = Flag("Triggerbot_Key")
    if key and not IsKeyHeld(key) then return end
    local camera = GetCamera()
    if not camera then return end
    local ray = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 1000)
    if ray and ray.Instance then
        local p = GetPlayerFromPart(ray.Instance)
        local teamCheck = Flag("Triggerbot_TeamCheck", true)
        if p and p ~= LocalPlayer and (not teamCheck or IsEnemy(p)) then
            local interval = 1 / (Flag("Triggerbot_FireRate", 10) or 10)
            if t - lastShot >= interval then
                lastShot = t
                pcall(function() mouse1click() end)
            end
        end
    end
end)

-- =====================================================================
--  SILENT AIM  (aim-assist: snaps camera to target while firing)
--  NOTE: true server-verified silent aim needs getgc/hookfunction module
--  hooks that low-UNC executors (Solara/Xeno) cannot set up reliably.
--  This provides the closest working equivalent without such hooks.
-- =====================================================================
local lastSilentSnap = 0
RunService.Heartbeat:Connect(function(t)
    if IsPanic() or not Flag("SilentAim_Enabled", true) then return end
    if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then return end

    local target = SelectTarget("SilentAim", "SilentAim_Hitpart")
    if not target then return end

    local camera = GetCamera()
    if not camera then return end
    local center = camera.ViewportSize / 2
    local char = GetChar(target.player)
    local part = char and (char:FindFirstChild(Flag("SilentAim_Hitpart", "Head")) or GetRoot(char))
    local screen, onScreen = WorldToScreen(part and part.Position or Vector3.zero)
    if not screen or not onScreen then return end

    local useFov = Flag("SilentAim_FoV", true)
    local fovSize = Flag("SilentAim_FoVSize", 80) or 80
    if useFov and (screen - center).Magnitude > fovSize then return end

    local pred = Flag("SilentAim_Prediction", false) and Flag("SilentAim_PredAmount", 0.165) or 0
    local targetPos = (part and part.Position or Vector3.zero)
    if pred > 0 then
        local diff = targetPos - camera.CFrame.Position
        if diff.Magnitude > 0 then
            targetPos = targetPos + diff.Unit * (diff.Magnitude * pred)
        end
    end

    local sp, _ = WorldToScreen(targetPos)
    if not sp then return end
    MoveMouse((sp - center).X, (sp - center).Y)
    lastSilentSnap = t
end)

-- =====================================================================
--  MOVEMENT  (Speed / Jump / Noclip / Fly / Infinity Jump / Velocity / Strafe)
-- =====================================================================
local function MyHumanoid()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function MyRoot()
    local c = LocalPlayer.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart)
end

UserInputService.InputBegan:Connect(function(inp, gameProcessed)
    if gameProcessed then return end
    if inp.KeyCode == Enum.KeyCode.Space and Flag("Misc_JumpInfinite", false) then
        local h = MyHumanoid()
        if h and h.Health > 0 then
            h:ChangeState(Enum.HumanoidStateType.None)
            task.wait(0.01)
            h:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

RunService.Heartbeat:Connect(function(dt)
    if IsPanic() then return end
    local c = LocalPlayer.Character
    local hum = (c and c:FindFirstChildOfClass("Humanoid")) or MyHumanoid()
    local root = (c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart))
    if not c or not hum or not root then return end

    local targetWS = Flag("Misc_Speed", false) and (Flag("Misc_SpeedAmount", 80) or 80) or 16
    if hum.WalkSpeed ~= targetWS then hum.WalkSpeed = targetWS end

    hum.UseJumpPower = Flag("Misc_Jump", false)
    if Flag("Misc_Jump", false) then
        hum.JumpPower = Flag("Misc_JumpPower", 100) or 100
    end

    hum.AutoRotate = not Flag("Misc_Strafe", false)

    if Flag("Misc_Velocity", false) and hum.MoveDirection.Magnitude > 0.1 then
        pcall(function()
            root.AssemblyLinearVelocity = hum.MoveDirection * (hum.WalkSpeed * (Flag("Misc_VelocityAmount", 1) or 1))
        end)
    end

    if Flag("Misc_Noclip", false) and hum.MoveDirection.Magnitude > 0.1 then
        pcall(function()
            root.CFrame = root.CFrame + hum.MoveDirection * (hum.WalkSpeed * dt)
        end)
    end

    if Flag("Misc_Fly", false) then
        local speed = Flag("Misc_FlySpeed", 50) or 50
        local camera = GetCamera()
        local dir = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
        local hor = math.sqrt(dir.X * dir.X + dir.Z * dir.Z)
        local move = hum.MoveDirection
        if move.Magnitude > 0.1 then
            dir = (move * (hor > 0.01 and 1 or 1))
        end
        local vert = 0
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then vert = 1
        elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then vert = -1 end
        pcall(function()
            root.VectorVelocity = Vector3.zero
            root.AssemblyLinearVelocity = (camera and camera.CFrame.LookVector * (move.Magnitude > 0.1 and speed or 0)) + Vector3.new(0, vert * speed, 0)
        end)
    end
end)

-- =====================================================================
--  VISUALS  (Fullbright / Brightness / No Fog / No Clouds / Skybox / Highlight / Night Vision)
-- =====================================================================
RunService.Heartbeat:Connect(function()
    if IsPanic() then return end
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
        Lighting.Ambient = Color3.fromRGB(30, 90, 60)
    end
end)

-- Highlight (chams-style for players)
local hlColor = NewDrawing and false
RunService.RenderStepped:Connect(function()
    if IsPanic() then
        for _, esp in pairs(Tracked) do if esp.highlight then esp.highlight.Enabled = false end end
        return
    end
    local hlOn = Flag("Visuals_Highlight", false)
    local hlC = Flag("Visuals_HighlightColor", Color3.fromRGB(255, 255, 255)) or Color3.fromRGB(255, 255, 255)
    for _, esp in pairs(Tracked) do
        local char = GetChar(esp.player)
        if hlOn and char then
            if not esp.highlight then
                local ok, h = pcall(function()
                    local n = Instance.new("Highlight")
                    n.Adornee = char
                    n.Parent = char
                    return n
                end)
                esp.highlight = ok and h or nil
            elseif esp.highlight and (esp.highlight.Adornee ~= char or esp.highlight.Parent ~= char) then
                pcall(function()
                    esp.highlight.Adornee = char
                    if esp.highlight.Parent ~= char then esp.highlight.Parent = char end
                end)
            end
            if esp.highlight then
                esp.highlight.FillColor = hlC
                esp.highlight.OutlineColor = Color3.fromRGB(0, 0, 0)
                esp.highlight.Enabled = true
            end
        elseif esp.highlight then
            esp.highlight.Enabled = false
        end
    end
end)

-- =====================================================================
--  CROSSHAIR  +  Aimbot / Silent Aim FoV circles
-- =====================================================================
local cross, cross2
if Drawing and Drawing.new then
    cross = NewDrawing("Text")
    if cross then
        cross.Font = Drawing.Fonts.UI
        cross.Center = true
        cross.Outline = Flag("Misc_CrosshairOutline", true)
        cross.OutlineColor = Color3.fromRGB(0, 0, 0)
    end
    cross2 = NewDrawing("Circle")
    if cross2 then cross2.Visible = false end
    local fovCircle = NewDrawing("Circle")
    if fovCircle then fovCircle.Visible = false end
    local silCircle = NewDrawing("Circle")
    if silCircle then silCircle.Visible = false end

RunService.RenderStepped:Connect(function()
    local center = GetCamera() and GetCamera().ViewportSize / 2 or Vector2.new(640, 360)

    if Flag("Misc_Crosshair", true) and cross then
        local style = Flag("Misc_CrosshairStyle", "Plus")
        local gap = Flag("Misc_CrosshairGap", 3) or 3
        local len = Flag("Misc_CrosshairLength", 10) or 10
        local thick = Flag("Misc_CrosshairThickness", 2) or 2
        local color = Flag("Misc_CrosshairColor", Color3.fromRGB(0, 255, 0)) or Color3.fromRGB(0, 255, 0)
        local dot = Flag("Misc_CrosshairDot", false)

        pcall(function()
            cross.Color = color
            cross.Size = thick + 2
            cross.Outline = Flag("Misc_CrosshairOutline", true)
            local ch = style == "Cross" or style == "Plus"
            local m = gap
            local glyph = ""
            if style == "Plus" or style == "Cross" then
                glyph = string.rep("|", len)
                cross.Text = glyph
                cross.Position = center
            elseif style == "Dot" then
                cross.Text = string.rep("|", 1)
                cross.Size = thick * 2 + 2
                cross.Position = center
            elseif style == "Circle" then
                cross.Visible = false
                if cross2 then
                    cross2.Visible = true
                    cross2.Radius = gap + len
                    cross2.Color = color
                    cross2.Thickness = thick
                    cross2.Position = center
                end
            end
            if style ~= "Circle" then
                cross.Visible = true
                if cross2 then cross2.Visible = false end
            end
            if style == "Cross" and dot and cross2 then
            end
        end)
    else
        if cross then cross.Visible = false end
        if cross2 then cross2.Visible = false end
    end

    local panic = IsPanic()
    if Flag("Aimbot_FoV", true) and not panic and Flag("Aimbot_Enabled", true) and fovCircle then
        fovCircle.Visible = true
        fovCircle.Color = Flag("Aimbot_FoVColor", Color3.fromRGB(255, 255, 255)) or Color3.fromRGB(255, 255, 255)
        fovCircle.Radius = Flag("Aimbot_FoVSize", 50) or 50
        fovCircle.Position = center
        fovCircle.Thickness = 1
        fovCircle.Transparency = 0.5
    elseif fovCircle then
        fovCircle.Visible = false
    end

    if Flag("SilentAim_FoV", true) and not panic and silCircle then
        silCircle.Visible = true
        silCircle.Color = Flag("SilentAim_FoVColor", Color3.fromRGB(255, 255, 255)) or Color3.fromRGB(255, 255, 255)
        silCircle.Radius = Flag("SilentAim_FoVSize", 80) or 80
        silCircle.Position = center
        silCircle.Thickness = 1
        silCircle.Transparency = 0.5
    elseif silCircle then
        silCircle.Visible = false
    end
end)
end

-- =====================================================================
--  ANTI-AFK  +  FPS MODE
-- =====================================================================
if Flag("Misc_AntiAFK", true) then
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:Button2Down(Vector2.new(0, 0))
    end)
    RunService.Heartbeat:Connect(function()
        pcall(function() VirtualUser:Button2Down(Vector2.new(0, 0)) end)
    end)
end

RunService.Heartbeat:Connect(function()
    if IsPanic() or not Flag("Misc_FPSMode", false) then return end
    pcall(function()
        lightingQuality = game:GetService("Lighting")
        for _, v in pairs(workspace:GetDescendants()) do
            if v:IsA("BasePart") and v.Material == Enum.Material.Neon then v.Material = Enum.Material.SmoothPlastic end
            if v:IsA("Part") and v.CastShadow then v.CastShadow = false end
        end
    end)
end)

print("[VisionWare] Features loaded (ESP, Aimbot, Triggerbot, Silent Aim, Movement, Visuals, Crosshair)")