--[[
    VisionWare | shared.lua
    ========================
    Loads AFTER gui.lua and exposes a single `Vision` API (getgenv().Vision)
    that every feature module consumes:
      - flag helpers (read Library.Flags safely)
      - generic team detection (TeammateLabel / Team / Neutral)
      - player tracking + target selection
      - drawing / world helpers
    No feature logic lives here.
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local LocalPlayer      = Players.LocalPlayer

-- Wait for the GUI Library (bounded ~10s so we never HANG)
local Library
for _ = 1, 100 do
    Library = (getgenv and getgenv().Library) or _G.Library
    if Library and Library.Flags then break end
    task.wait(0.1)
end

local Vision = (getgenv and getgenv().Vision) or {}
getgenv().Vision = Vision
_G.Vision = Vision

Vision.Library          = Library
Vision.Flags            = (Library and Library.Flags) or {}
Vision.Players          = Players
Vision.RunService       = RunService
Vision.UserInputService = UserInputService
Vision.Lighting         = Lighting
Vision.LocalPlayer      = LocalPlayer

-- =====================================================================
--  Flags
-- =====================================================================
function Vision.Flag(Name, Default)
    local v = Vision.Flags[Name]
    return v ~= nil and v or Default
end

function Vision.IsPanic()
    return Vision.Flag("Misc_Panic", false)
end

function Vision.Opacity(Percent)
    return math.clamp((tonumber(Percent) or 100) / 100, 0, 1)
end

-- =====================================================================
--  World / character helpers
-- =====================================================================
function Vision.GetCamera()
    return workspace.CurrentCamera
end

function Vision.GetChar(player)
    return player and player.Character
end

function Vision.GetRoot(char)
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart or char:FindFirstChildWhichIsA("BasePart")
end

function Vision.GetHead(char)
    return char and char:FindFirstChild("Head")
end

function Vision.GetPlayerFromPart(part)
    if not part then return nil end
    local p = Players:GetPlayerFromCharacter(part)
    if p then return p end
    local anc = part:FindFirstAncestorOfClass("Folder")
        or part:FindFirstAncestorWhere(function(x)
            return Players:GetPlayerFromCharacter(x) ~= nil
        end)
    return anc and Players:GetPlayerFromCharacter(anc)
end

-- =====================================================================
--  Drawing
-- =====================================================================
function Vision.NewDrawing(kind)
    if not (Drawing and Drawing.new) then return nil end
    local ok, d = pcall(Drawing.new, kind)
    return ok and d or nil
end

function Vision.WorldToScreen(pos)
    local camera = Vision.GetCamera()
    if not camera then return nil, false end
    local s, ok = camera:WorldToViewportPoint(pos)
    return Vector2.new(s.X, s.Y), ok
end

function Vision.IsVisibleFromCamera(pos, targetChar)
    local camera = Vision.GetCamera()
    if not camera then return true end
    local origin = camera.CFrame.Position
    local ray = workspace:Raycast(origin, pos - origin)
    if not ray then return true end
    local inst = ray.Instance
    if not inst then return true end
    return inst:IsDescendantOf(targetChar) or inst == targetChar
end

-- =====================================================================
--  Generic team detection (works in any Roblox game)
--  A teammate = has a "TeammateLabel" child on the HumanoidRootPart,
--  or shares the same Team while not Neutral. Everything else = enemy.
-- =====================================================================
function Vision.IsEnemy(player)
    if player == LocalPlayer then return false end
    local root = Vision.GetRoot(Vision.GetChar(player))
    if root and root:FindFirstChild("TeammateLabel") then return false end
    if player.Neutral then return true end
    local myTeam = LocalPlayer.Team
    local theirTeam = player.Team
    if myTeam and theirTeam and myTeam == theirTeam then return false end
    return true
end

-- =====================================================================
--  Player tracking (shared by every feature)
-- =====================================================================
Vision.Tracked = {}

Players.PlayerAdded:Connect(function(p)
    if p ~= LocalPlayer then Vision.Tracked[p] = { player = p } end
end)

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then Vision.Tracked[p] = { player = p } end
end

Players.PlayerRemoving:Connect(function(player)
    local entry = Vision.Tracked[player]
    if entry then
        if Vision.OnPlayerRemoving then Vision.OnPlayerRemoving(player, entry) end
        Vision.Tracked[player] = nil
    end
end)

-- =====================================================================
--  Target selection shared by Aimbot / Silent Aim / Triggerbot
--  prefix      e.g. "Aimbot" / "SilentAim"
--  hitpartFlag e.g. "Aimbot_Hitpart"
--  returns { player, char, root, part, pos } or nil
-- =====================================================================
function Vision.SelectTarget(prefix, hitpartFlag, opts)
    opts = opts or {}
    local mode = Vision.Flag(prefix .. "_Target", "Closest to Crosshair")
    local hitpart = Vision.Flag(hitpartFlag, "Head")
    local camera = Vision.GetCamera()
    if not camera then return nil end
    local camPos = camera.CFrame.Position
    local center = camera.ViewportSize / 2
    local range = Vision.Flag("ESP_Range", 1000) or 1000
    local teamCheck = Vision.Flag(prefix .. "_TeamCheck", true)
    local best, bestScore = nil, math.huge

    for player, entry in pairs(Vision.Tracked) do
        if player == LocalPlayer then continue end
        if teamCheck and not Vision.IsEnemy(player) then continue end

        local char = Vision.GetChar(player)
        local root = Vision.GetRoot(char)
        if not char or not root or not char:FindFirstChild("Humanoid") then continue end

        local part = char:FindFirstChild(hitpart) or root
        local pos = part.Position
        if (pos - camPos).Magnitude > range then continue end

        local screen, onScreen = Vision.WorldToScreen(pos)
        if not screen or not onScreen then continue end

        if opts.visibleOnly and not Vision.IsVisibleFromCamera(pos, char) then continue end

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
            best = { player = player, char = char, root = root, part = part, pos = pos }
        end
    end
    return best
end

-- =====================================================================
--  Input helpers
-- =====================================================================
function Vision.IsKeyHeld(Key)
    if type(Key) == "EnumItem" then
        if Key.EnumType == Enum.KeyCode then
            return UserInputService:IsKeyDown(Key)
        elseif Key.EnumType == Enum.UserInputType then
            if Key == Enum.UserInputType.MouseButton1 then
                return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
            elseif Key == Enum.UserInputType.MouseButton2 then
                return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
            elseif Key == Enum.UserInputType.MouseButton3 then
                return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton3)
            end
        end
    end
    return false
end

function Vision.MoveMouse(dx, dy)
    pcall(function()
        if mousemoverel then
            mousemoverel(dx, dy)
        elseif syn and syn.input and syn.input.mousemoverel then
            syn.input.mousemoverel(dx, dy)
        end
    end)
end

print("[VisionWare] shared API loaded")