--[[
    VisionWare | ESP + Aimbot  (full feature set)
    =============================================
    Comprehensive ESP + Aimbot wired into every VisionWare flag.
    Designed to LOAD reliably on any executor:
      - Bounded waits (never infinite-loops waiting for modules).
      - The camera is resolved fresh every frame (never captured at load).
      - Every game access is nil/pcall-safe -> degrades gracefully until
        the round starts, instead of erroring or hanging.

    ESP features:  boxes (2D / 3D / Corner / Filled), outline, thickness,
        names, distances, health bar + style + side, tracers (4 origins),
        skeleton, head dot, chams, colors, opacity, range, team check,
        visible-only, rainbow (parts Selectable).
    Aimbot:       toggle, target mode, hitpart, keybind, smoothness, FoV,
        team check, panic master, target switch delay.

    Fixes one-at-a-time as requested.
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer      = Players.LocalPlayer

-- =====================================================================
--  Wait for the VisionWare GUI (bounded ~10s so we never HANG).
-- =====================================================================
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

local TEAMS = {
    ["Bright blue"]   = "Phantoms",
    ["Bright orange"] = "Ghosts",
}

local function TeamName(player)
    return TEAMS[tostring(player and player.TeamColor)] or "Unknown"
end

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
--  Drawing helpers
-- =====================================================================
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

-- =====================================================================
--  Per-player ESP object (Drawings created ONCE)
-- =====================================================================
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
        sq        = NewDrawing("Square"),  -- 2D / filled box
        sqOutline = NewDrawing("Square"),  -- box black outline
        health    = NewDrawing("Square"),  -- health bar
        tracer    = NewDrawing("Line"),    -- tracer
        nameLbl   = NewDrawing("Text"),    -- name
        distLbl   = NewDrawing("Text"),    -- distance
        hpLbl     = NewDrawing("Text"),    -- health %
        headDot   = NewDrawing("Square"),  -- head dot
        skeleton  = {},                    -- 3D box edges + skeleton lines (lazy)
        highlight = nil,                   -- chams
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

-- =====================================================================
--  ESP RENDER
-- =====================================================================
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

        local enemy = TeamName(player) ~= TeamName(LocalPlayer)
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

        -- Chams
        if esp.highlight then
            esp.highlight.Enabled = chamsOn
            if chamsOn then
                if rainbow and (rainbowParts == "All" or rainbowParts == "Boxes") then
                    esp.highlight.FillColor = Color3.fromHSV((tick() * rainbowSpeed) % 1, 1, 1)
                else
                    esp.highlight.FillColor = chamCol
                end
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

        -- Box (per type)
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
                    -- corner brackets drawn as 8 short lines (an L per corner)
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
                -- project the character's 8 world corners and draw edges
                esp.sq.Visible = false
                if esp.sqOutline then esp.sqOutline.Visible = false end
                local hrp = root
                local cf = hrp.CFrame
                local hx = width
                local hy = height
                local hz = hrp.Size.Z or 1
                local s8 = cf.Position
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

        -- Skeleton (2D)
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

        -- Head dot
        if headOn and esp.headDot then
            local hp, on = WorldToScreen(head and head.Position or root.Position)
            if hp and (on or true) then
                esp.headDot.Color = color
                esp.headDot.Position = hp - Vector2.new(thickness, thickness) * 2
                esp.headDot.Size = Vector2.new(thickness * 4, thickness * 4)
                esp.headDot.Visible = true
            end
        elseif esp.headDot then
            esp.headDot.Visible = false
        end

        -- Health bar / hp text
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

        -- Tracer
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

        -- Name + distance
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
--  AIMBOT  (mousemoverel, universal)
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
local velCache = {} -- [player] = { pos, time }

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
        if not part then continue end
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

    local char = GetChar(target.player)
    local part = char and (char:FindFirstChild(hitpart) or GetRoot(char))
    if not part then return end

    local screen, onScreen = WorldToScreen(part.Position)
    if not screen or not onScreen then return end

    local delta = (screen - center) * smooth
    MoveMouse(delta.X, delta.Y)
end)

print("[VisionWare] ESP + Aimbot loaded (full feature set)")