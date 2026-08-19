--[[
    Phantom Forces ESP + Aimbot
    ============================
    Sens              = 0.2    -- Pull strength (0.1 subtle → 1.0 strong)
    AIMBOT_SMOOTHNESS = 0.55   -- Lerp per frame (0.1 smooth → 1.0 instant)
    FOV_RADIUS        = 120    -- FOV circle radius in pixels
    AIM_MODE          = "fov"  -- "fov" = closest in circle | "distance" = closest to camera
    DRAW_FOV          = true   -- Draw the FOV circle on screen

    Combined effect = Sens * Smoothness per frame
    Current: 0.2 * 0.55 = 0.11 per frame (gentle assist)
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera           = workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer
local frameTick        = 0

local TEAMS = {
    ["Bright blue"]   = "Phantoms",
    ["Bright orange"] = "Ghosts",
}

local TEAM_COLORS = {
    ["Phantoms"] = Color3.fromRGB(0, 100, 255),
    ["Ghosts"]   = Color3.fromRGB(255, 140, 0),
}

local Boxes        = {}
local MAX_DISTANCE = 1000

-- // Connected to the VisionWare GUI (gui.lua)
-- // The loader runs gui.lua first, so the Library is already built here.
-- // All settings are read from the GUI flags live, so the menu stays in sync.
local Library = (getgenv and getgenv().Library) or _G.Library
while not Library do
    task.wait()
    Library = (getgenv and getgenv().Library) or _G.Library
end

local function Flag(Name, Default)
    local f = Library and Library.Flags and Library.Flags[Name]
    return f ~= nil and f or Default
end

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

_G.Sens               = 1
_G.AIMBOT_SMOOTHNESS  = Flag("Aimbot_Smoothness", 0.2)
_G.aimbotActive       = false -- driven by the GUI each frame (do not set manually)
_G.FOV_RADIUS         = Flag("Aimbot_FoVSize", 120)
_G.AIM_MODE           = "fov"   -- "fov" or "distance"
_G.DRAW_FOV           = false  -- the GUI already draws the FoV ring
_G.TARGET_SWITCH_DELAY = 0.15  -- seconds before locking onto a new target after one dies

local lastTarget         = nil
local lastTargetLostTime = nil

local localTeamName = TEAMS[tostring(LocalPlayer.TeamColor)] or "Unknown"

-- FOV Circle drawing
local fovCircle           = Drawing.new("Circle")
fovCircle.Radius          = _G.FOV_RADIUS
fovCircle.Color           = Color3.fromRGB(255, 255, 255)
fovCircle.Thickness       = 1
fovCircle.Filled          = false
fovCircle.Visible         = false
fovCircle.NumSides        = 64

local function untrack(model)
    local data = Boxes[model]
    if not data then return end
    pcall(function() data.sq:Remove() end)
    pcall(function() data.label:Remove() end)
    Boxes[model] = nil
end

LocalPlayer:GetPropertyChangedSignal("TeamColor"):Connect(function()
    localTeamName = TEAMS[tostring(LocalPlayer.TeamColor)] or "Unknown"
    for _, data in pairs(Boxes) do
        local enemyTeam = TEAMS[tostring(data.player and data.player.TeamColor)] or "Unknown"
        data.isEnemy = enemyTeam ~= localTeamName
        local color = TEAM_COLORS[enemyTeam] or Color3.fromRGB(255, 255, 255)
        data.sq.Color    = color
        data.label.Color = color
        if not data.isEnemy then
            data.sq.Visible    = false
            data.label.Visible = false
        end
    end
end)

local function getModelBounds(model, rootPart)
    if rootPart and (rootPart.Position - Camera.CFrame.Position).Magnitude > MAX_DISTANCE then
        return nil
    end

    local minX, minY = math.huge,  math.huge
    local maxX, maxY = -math.huge, -math.huge
    local onScreen   = false

    for _, part in ipairs(model:GetChildren()) do
        if part:IsA("BasePart") then
            local s  = part.Size * 0.5
            local cf = part.CFrame
            for _, offset in ipairs({
                Vector3.new( s.X,  s.Y,  s.Z), Vector3.new(-s.X,  s.Y,  s.Z),
                Vector3.new( s.X, -s.Y,  s.Z), Vector3.new(-s.X, -s.Y,  s.Z),
                Vector3.new( s.X,  s.Y, -s.Z), Vector3.new(-s.X,  s.Y, -s.Z),
                Vector3.new( s.X, -s.Y, -s.Z), Vector3.new(-s.X, -s.Y, -s.Z),
            }) do
                local screen, visible = Camera:WorldToViewportPoint(cf:PointToWorldSpace(offset))
                if visible then
                    onScreen = true
                    minX = math.min(minX, screen.X)
                    minY = math.min(minY, screen.Y)
                    maxX = math.max(maxX, screen.X)
                    maxY = math.max(maxY, screen.Y)
                end
            end
        end
    end

    return onScreen and { minX, minY, maxX - minX, maxY - minY } or nil
end

local function trackModel(model)
    if not model:IsA("Model") or Boxes[model] then return end

    local tag = model:FindFirstChild("PlayerTag", true)
    if not tag or not tag:IsA("TextLabel") then return end

    local name = tag.Text:match("^%s*(.-)%s*$")
    if name == LocalPlayer.Name then return end

    local player    = Players:FindFirstChild(name)
    local enemyTeam = TEAMS[tostring(player and player.TeamColor)] or "Unknown"
    local isEnemy   = enemyTeam ~= localTeamName
    local color     = TEAM_COLORS[enemyTeam] or Color3.fromRGB(255, 255, 255)

    local sq       = Drawing.new("Square")
    sq.Filled      = false
    sq.Thickness   = 2
    sq.Color       = color
    sq.Visible     = false

    local label        = Drawing.new("Text")
    label.Text         = name
    label.Size         = 13
    label.Font         = Drawing.Fonts.UI
    label.Color        = color
    label.Center       = true
    label.Outline      = true
    label.OutlineColor = Color3.fromRGB(0, 0, 0)
    label.Visible      = false

    local data = {
        sq      = sq,
        label   = label,
        root    = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart"),
        name    = name,
        player  = player,
        isEnemy = isEnemy,
    }
    Boxes[model] = data

    if player then
        player:GetPropertyChangedSignal("TeamColor"):Connect(function()
            local newTeam  = TEAMS[tostring(player.TeamColor)] or "Unknown"
            data.isEnemy   = newTeam ~= localTeamName
            local newColor = TEAM_COLORS[newTeam] or Color3.fromRGB(255, 255, 255)
            data.sq.Color    = newColor
            data.label.Color = newColor
            if not data.isEnemy then
                data.sq.Visible    = false
                data.label.Visible = false
            end
        end)
    end
end

-- Returns the highest BasePart position (head) in the model
local function getModelCenter(model)
    local highestPart = nil
    local highestY    = -math.huge
    for _, v in ipairs(model:GetDescendants()) do
        if v:IsA("BasePart") and v.Position.Y > highestY then
            highestY    = v.Position.Y
            highestPart = v
        end
    end
    return highestPart and highestPart.Position or nil
end

local function getClosestEnemy()
    local closest     = nil
    local closestDist = math.huge
    local camPos      = Camera.CFrame.Position
    local center      = Camera.ViewportSize / 2

    for model, data in pairs(Boxes) do
        if data.isEnemy and model.Parent then
            local pos = getModelCenter(model)
            if pos then
                local screenPos, visible = Camera:WorldToViewportPoint(pos)
                if visible then
                    if _G.AIM_MODE == "fov" then
                        -- Distance from screen center in pixels
                        local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                        if screenDist < _G.FOV_RADIUS and screenDist < closestDist then
                            closestDist = screenDist
                            closest     = model
                        end
                    else
                        -- Closest by world distance
                        local dist = (pos - camPos).Magnitude
                        if dist < closestDist and dist <= MAX_DISTANCE then
                            closestDist = dist
                            closest     = model
                        end
                    end
                end
            end
        end
    end

    return closest
end

-- Initial scan
for _, v in ipairs(workspace.Players:GetDescendants()) do
    trackModel(v)
end

workspace.Players.DescendantAdded:Connect(trackModel)
workspace.Players.DescendantRemoving:Connect(untrack)

Players.PlayerAdded:Connect(function(player)
    if player.Name == LocalPlayer.Name then return end
    player:GetPropertyChangedSignal("TeamColor"):Connect(function()
        local newTeam  = TEAMS[tostring(player.TeamColor)] or "Unknown"
        local newColor = TEAM_COLORS[newTeam] or Color3.fromRGB(255, 255, 255)
        for _, data in pairs(Boxes) do
            if data.name == player.Name then
                data.isEnemy  = newTeam ~= localTeamName
                data.player   = player
                data.sq.Color    = newColor
                data.label.Color = newColor
                if not data.isEnemy then
                    data.sq.Visible    = false
                    data.label.Visible = false
                end
            end
        end
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    local toRemove = {}
    for model, data in pairs(Boxes) do
        if data.name == player.Name then
            toRemove[#toRemove + 1] = model
        end
    end
    for _, model in ipairs(toRemove) do
        untrack(model)
    end
end)

RunService.Heartbeat:Connect(function()
    frameTick += 1

    -- Drive aimbot from the GUI (panic + enable toggle + held activation key)
    _G.AIMBOT_SMOOTHNESS = Flag("Aimbot_Smoothness", 0.2)
    _G.FOV_RADIUS        = Flag("Aimbot_FoVSize", 120)
    _G.aimbotActive      = not Flag("Misc_Panic", false)
        and Flag("Aimbot_Enabled", true)
        and IsKeyHeld(Flag("Aimbot_Key", Enum.UserInputType.MouseButton2))

    -- Update FOV circle position and visibility
    local center = Camera.ViewportSize / 2
    fovCircle.Position = center
    fovCircle.Radius   = _G.FOV_RADIUS
    fovCircle.Visible  = _G.DRAW_FOV

	if _G.aimbotActive then
		local target = getClosestEnemy()

		-- Target switched or died
		if target ~= lastTarget then
			if lastTarget ~= nil then
				-- Previous target was lost; start the switch timer
				if lastTargetLostTime == nil then
					lastTargetLostTime = tick()
				end
				-- Block new target until delay has passed
				if (tick() - lastTargetLostTime) < _G.TARGET_SWITCH_DELAY then
					target = nil
				else
					lastTarget         = target
					lastTargetLostTime = nil
				end
			else
				-- No previous target, lock on immediately
				lastTarget         = target
				lastTargetLostTime = nil
			end
		else
			-- Same target, reset timer
			lastTargetLostTime = nil
		end

		if target then
			local pos = getModelCenter(target)
			if pos then
				local screenPos, visible = Camera:WorldToViewportPoint(pos)
				if visible then
					local targetPos = Vector2.new(screenPos.X, screenPos.Y)
					local delta     = (targetPos - center) * (_G.Sens * _G.AIMBOT_SMOOTHNESS)
					mousemoverel(delta.X, delta.Y)
				end
			end
		end
	end

    if frameTick % 2 ~= 0 then return end

    -- Hide all boxes when ESP is off or panic is active
    if Flag("Misc_Panic", false) or not Flag("ESP_Enabled", true) then
        for _, data in pairs(Boxes) do
            data.sq.Visible    = false
            data.label.Visible = false
        end
        return
    end

    local stale = {}
    for model, data in pairs(Boxes) do
        if not model.Parent then
            stale[#stale + 1] = model
        elseif data.isEnemy then
            local bounds = getModelBounds(model, data.root)
            if bounds then
                data.sq.Position    = Vector2.new(bounds[1], bounds[2])
                data.sq.Size        = Vector2.new(bounds[3], bounds[4])
                data.label.Position = Vector2.new(bounds[1] + bounds[3] / 2, bounds[2] - 16)
                data.sq.Visible     = true
                data.label.Visible  = true
            else
                data.sq.Visible    = false
                data.label.Visible = false
            end
        end
    end

    for _, model in ipairs(stale) do
        untrack(model)
    end
end)

print("ESP loaded")



      