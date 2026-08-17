-- // VisionWare ESP
-- // Hooks into the Library (created by gui.lua) and draws player ESP for Phantom Forces.
-- // Uses the executor Drawing API when available, otherwise warns and disables rendering.

local Library = getgenv and getgenv().Library or _G.Library
assert(Library, "[VisionWare] ESP failed: Library not found (run gui.lua first).")

-- // Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local RaycastParams = RaycastParams.new()
RaycastParams.FilterType = Enum.RaycastFilterType.Blacklist
RaycastParams.IgnoreWater = true

-- // Drawing setup
local HasDrawing = (Drawing and pcall(Drawing.new, "Square"))
if not HasDrawing then
	warn("[VisionWare] ESP: Drawing API unavailable - ESP will not render.")
end

local function DrawNew(kind)
	if HasDrawing then
		local ok, obj = pcall(Drawing.new, kind)
		if ok and obj then return { drawing = true, obj = obj } end
	end
	return nil
end

-- // Rainbow state
local RainbowHue = 0
local function NextRainbow(step)
	step = step or 1
	RainbowHue = (RainbowHue + step * 0.01) % 1
	return Color3.fromHSV(RainbowHue, 1, 1)
end

-- ===== TEAM / FRIEND HELPERS =====
-- Phantom Forces teams: Ghosts (orange) and Phantoms (blue).
local GhostColor = BrickColor.new("Bright orange").Color
local PhantomColor = BrickColor.new("Bright blue").Color

local function IsLocal(player)
	return player == LocalPlayer
end

local function IsFriend(player)
	if IsLocal(player) then return true end
	return Library.Friends and table.find(Library.Friends, player) ~= nil
end

local function IsTeam(player)
	if not Library.Flags.ESP_TeamCheck then return false end
	if IsFriend(player) then return false end
	if not player or not LocalPlayer then return false end
	local ours = LocalPlayer.Team
	local theirs = player.Team
	if ours and theirs then
		return ours == theirs
	end
	-- Fallback: compare team colors when Team objects are absent
	local oc = LocalPlayer.TeamColor
	local tc = player.TeamColor
	return oc and tc and oc == tc
end

local function GetTeamColor(player)
	-- Uses the player's own team color for accurate Ghost/Phantom colors.
	if player.TeamColor then return player.TeamColor.Color end
	return player.Neutral and GhostColor or PhantomColor
end

-- ===== VISIBILITY =====
local function IsVisible(player)
	local char = player.Character
	if not char then return false end
	local root = char:FindFirstChild("HumanoidRootPart")
	local head = char:FindFirstChild("Head")
	if not root then return false end

	local origin = Camera:GetPivot().Position
	RaycastParams.FilterDescendantsInstances = { char, LocalPlayer.Character }

	-- Check the head and the root part; visible if either line of sight hits nothing.
	local function Check(target)
		if not target then return false end
		local delta = target.Position - origin
		local ray = workspace:Raycast(origin, delta, RaycastParams)
		return ray == nil
	end

	return Check(head) or Check(root)
end

-- ===== RENDER DECISION =====
local function ShouldRender(player)
	if not Library.Flags.ESP_Enabled then return false end
	if Library.Flags.Misc_Panic then return false end
	if IsLocal(player) then return false end

	-- Team handling
	if IsTeam(player) then
		if not Library.Flags.ESP_ShowTeam then return false end
	elseif IsFriend(player) and not Library.Flags.ESP_TeamCheck then
		-- Friend treated as friendly only when team check is meaningful; otherwise show.
	end

	local char = player.Character
	if not char then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return false end

	-- Range
	local Range = Library.Flags.ESP_Range or 500
	if Range > 0 then
		local dist = (root.Position - Camera:GetPivot().Position).Magnitude
		if dist > Range then return false end
	end

	-- Visible only
	if Library.Flags.ESP_VisibleOnly and not IsVisible(player) then return false end

	return true
end

-- ===== COLOR =====
local function GetColor(player)
	if Library.Flags.ESP_TeamCheck and IsTeam(player) then
		return Library.Flags.ESP_TeamColor or Color3.fromRGB(86, 227, 120)
	end
	if Library.Flags.ESP_TeamCheck and IsFriend(player) then
		return Library.Flags.ESP_TeamColor or Color3.fromRGB(86, 227, 120)
	end
	return Library.Flags.ESP_EnemyColor or Library.Accent
end

-- ===== 3D BOX =====
-- Returns 8 corner world positions of a part's bounding box.
-- Order: TBRC, TBLC, TFRC, TFLC, BBRC, BBLC, BFRC, BFLC
-- Top grows by 1.3x, bottom by 1.6x to capture head above the root part.
local function GetBoundingVectors(part)
	if not part then return nil end
	local CFrame = part.CFrame
	local Size = part.Size
	local TopMult = 1.3
	local BottomMult = 1.6

	local Top = Size.Y * TopMult
	local Bottom = Size.Y * BottomMult
	local Half = 0.5

	local Right = Size.X * Half
	local Forward = Size.Z * Half

	local function Point(x, y, z)
		return CFrame:PointToWorldSpace(Vector3.new(x, y, z))
	end

	-- Top of head (use the Head part for a more accurate top edge when present)
	local RootPos = part.Position
	local Head = part.Parent and part.Parent:FindFirstChild("Head")
	if Head then
		local headTop = Head.CFrame:PointToWorldSpace(Vector3.new(0, Head.Size.Y * Half, 0))
		Top = (RootPos - headTop).Magnitude + 0.1
	end

	return {
		Point(Right, Top, Forward),    -- TBRC
		Point(-Right, Top, Forward),   -- TBLC
		Point(Right, Top, -Forward),   -- TFRC
		Point(-Right, Top, -Forward),  -- TFLC
		Point(Right, -Bottom, Forward),-- BBRC
		Point(-Right, -Bottom, Forward),-- BBLC
		Point(Right, -Bottom, -Forward),-- BFRC
		Point(-Right, -Bottom, -Forward),-- BFLC
	}
end

-- ===== CHAMS =====
local function ApplyChams(player)
	pcall(function()
		if not Library.Flags.ESP_Chams then return end
		local char = player.Character
		if not char then return end
		local highlight = char:FindFirstChildOfClass("Highlight")
			or char:FindFirstChildOfClass("HighlightInstance")
		if not highlight then
			highlight = Instance.new("Highlight")
			highlight.FillTransparency = 0.5
			highlight.OutlineTransparency = 1
			highlight.Parent = char
		end
		if Library.Flags.ESP_Rainbow then
			highlight.FillColor = NextRainbow(Library.Flags.ESP_RainbowSpeed or 1)
		else
			highlight.FillColor = Library.Flags.ESP_ChamsColor or Color3.fromRGB(255, 255, 255)
		end
	end)
end

local function RemoveChams(player)
	pcall(function()
		local char = player.Character
		if not char then return end
		local highlight = char:FindFirstChildOfClass("Highlight")
			or char:FindFirstChildOfClass("HighlightInstance")
		if highlight then highlight:Destroy() end
	end)
end

-- ===== PER-PLAYER STATE =====
local PlayersList = {}

local function NewLines(Count)
	local Lines = {}
	for _ = 1, Count do
		table.insert(Lines, DrawNew("Line"))
	end
	return Lines
end

local function BuildPlayerData()
	return {
		BoxLines = NewLines(4),        -- 2D/3D box edge lines
		BoxFill = DrawNew("Quad"),     -- filled box
		CornerLines = NewLines(8),     -- corner box segments
		Tracers = NewLines(1),
		Skeleton = NewLines(5),
		Head = DrawNew("Circle"),
		Name = DrawNew("Text"),
		Distance = DrawNew("Text"),
		HealthText = DrawNew("Text"),
		HealthBar = DrawNew("Square") or DrawNew("Line"),
		HealthFill = DrawNew("Square") or DrawNew("Line"),
	}
end

local function ClearPlayerData(data)
	if not data then return end
	for _, handle in pairs(data) do
		if type(handle) == "table" then
			if handle.obj and handle.obj.Remove then
				pcall(handle.obj.Remove, handle.obj)
			else
				for _, sub in ipairs(handle) do
					if sub.obj and sub.obj.Remove then
						pcall(sub.obj.Remove, sub.obj)
					end
				end
			end
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	if IsLocal(player) then return end
	PlayersList[player] = BuildPlayerData()
end)

Players.PlayerRemoving:Connect(function(player)
	local data = PlayersList[player]
	ClearPlayerData(data)
	PlayersList[player] = nil
	RemoveChams(player)
end)

-- Initialize existing players
for _, player in ipairs(Players:GetPlayers()) do
	if not IsLocal(player) then
		PlayersList[player] = BuildPlayerData()
	end
end

-- ===== DRAWING HELPERS =====
local function HideAll(data)
	for _, handle in pairs(data) do
		if type(handle) == "table" then
			if handle.obj and handle.obj.Visible ~= nil then
				handle.obj.Visible = false
			else
				for _, sub in ipairs(handle) do
					if sub.obj and sub.obj.Visible ~= nil then
						sub.obj.Visible = false
					end
				end
			end
		end
	end
end

local function SetLine(h, From, To, Thickness, Color)
	if not h then return end
	local d = h.obj
	d.Visible = true
	d.From = From
	d.To = To
	d.Thickness = Thickness or 1
	d.Color = Color
end

local function SetText(h, Value, Position, Size, Color, Centre, Outline)
	if not h then return end
	local d = h.obj
	d.Visible = true
	d.Text = Value
	d.Position = Position
	d.Size = Size
	d.Color = Color
	d.Centre = Centre ~= false
	d.Outline = Outline
end

-- ===== RAINBOW PART CHECK =====
local function RainbowFor(Parts)
	if not Library.Flags.ESP_Rainbow then return false end
	local Target = Library.Flags.ESP_RainbowParts or "All"
	if Target == "All" then return true end
	for _, p in ipairs(Parts) do
		if p == Target then return true end
	end
	return false
end

-- ===== MAIN LOOP =====
RunService.RenderStepped:Connect(function()
	-- Master kill switch
	if Library.Flags.Misc_Panic then
		for _, data in pairs(PlayersList) do
			HideAll(data)
			local char = data.Char
			-- hide chams too
		end
		for _, player in pairs(PlayersList) do
			RemoveChams(player)
		end
		return
	end

	if not Library.Flags.ESP_Enabled then
		for _, player in pairs(PlayersList) do
			RemoveChams(player)
		end
		return
	end

	for player, data in pairs(PlayersList) do
		RemoveChams(player)
		HideAll(data)

		if not ShouldRender(player) then continue end

		local char = player.Character
		if not char then continue end
		data.Char = char
		local root = char:FindFirstChild("HumanoidRootPart")
		local head = char:FindFirstChild("Head")
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not root or not hum then continue end

		-- Chams (applied regardless of on-screen status, still range-checked)
		if Library.Flags.ESP_Chams then ApplyChams(player) end

		-- Project parts to screen
		local HeadPos = (head or root).Position
		local RootPos = root.Position
		local HeadVP = Camera:WorldToViewportPoint(HeadPos)
		local RootVP = Camera:WorldToViewportPoint(RootPos)
		if HeadVP.Z > 1 or RootVP.Z > 1 then continue end

		local Scale = math.clamp(1 / RootVP.Z, 0.1, 2)
		local TextSize = (Library.Flags.ESP_TextSize or 13) * Scale
		local Thick = Library.Flags.ESP_BoxThickness or 1
		local Opacity = (Library.Flags.ESP_Opacity or 75) / 100

		local Height = math.abs(HeadVP.Y - RootVP.Y)
		local Width = math.clamp(Height * 0.6, 10, 160)
		local Min = Vector2.new(RootVP.X - Width / 2, HeadVP.Y)
		local Max = Vector2.new(RootVP.X + Width / 2, RootVP.Y)

		local BaseColor = GetColor(player)

		-- ===== BOXES =====
		local BoxType = Library.Flags.ESP_BoxType
		if Library.Flags.ESP_Boxes then
			local BoxColor = BaseColor
			if RainbowFor({"Boxes"}) then BoxColor = NextRainbow(Library.Flags.ESP_RainbowSpeed or 1) end

			if BoxType == "Corner Box" then
				local Corner = Thick
				local Seg = 0.4
				local corners = {
					{ Min, Vector2.new(Min.X + Width * Seg, Min.Y) },
					{ Min, Vector2.new(Min.X, Min.Y + Height * Seg) },
					{ Vector2.new(Max.X, Min.Y), Vector2.new(Max.X - Width * Seg, Min.Y) },
					{ Vector2.new(Max.X, Min.Y), Vector2.new(Max.X, Min.Y + Height * Seg) },
					{ Vector2.new(Max.X, Max.Y), Vector2.new(Max.X - Width * Seg, Max.Y) },
					{ Vector2.new(Max.X, Max.Y), Vector2.new(Max.X, Max.Y - Height * Seg) },
					{ Vector2.new(Min.X, Max.Y), Vector2.new(Min.X + Width * Seg, Max.Y) },
					{ Vector2.new(Min.X, Max.Y), Vector2.new(Min.X, Max.Y - Height * Seg) },
				}
				for i, pair in ipairs(corners) do
					SetLine(data.CornerLines[i], pair[1], pair[2], Corner, BoxColor)
				end
			elseif BoxType == "3D Box" then
				-- Project the 8 corners and connect the edges
				local Corners = GetBoundingVectors(root)
				if Corners then
					local VPs = {}
					for _, c in ipairs(Corners) do
						local v = Camera:WorldToViewportPoint(c)
						if v.Z > 1 then
							VPs = nil
							break
						end
						VPs = VPs or {}
						table.insert(VPs, Vector2.new(v.X, v.Y))
					end
					if VPs then
						-- Back face (points 4,3,7,8)
						local edges = {
							{1, 2}, {2, 4}, {4, 3}, {3, 1}, -- top
							{5, 6}, {6, 8}, {8, 7}, {7, 5}, -- bottom
							{1, 5}, {2, 6}, {3, 7}, {4, 8}, -- verticals
						}
						for i, e in ipairs(edges) do
							local a = VPs[e[1]]
							local b = VPs[e[2]]
							if a and b then
								SetLine(data.BoxLines[(i - 1) % 4 + 1], a, b, Thick, BoxColor)
							end
						end
					end
				end
			elseif BoxType == "Filled Box" then
				if data.BoxFill and data.BoxFill.obj then
					local d = data.BoxFill.obj
					d.Visible = true
					d.PointA = Min
					d.PointB = Vector2.new(Max.X, Min.Y)
					d.PointC = Max
					d.PointD = Vector2.new(Min.X, Max.Y)
					d.Color = BoxColor
					d.Transparency = 0.4 + (1 - Opacity) * 0.6
					d.Filled = true
				end
			else -- "2D Box"
				SetLine(data.BoxLines[1], Min, Vector2.new(Max.X, Min.Y), Thick, BoxColor)
				SetLine(data.BoxLines[2], Vector2.new(Max.X, Min.Y), Max, Thick, BoxColor)
				SetLine(data.BoxLines[3], Max, Vector2.new(Min.X, Max.Y), Thick, BoxColor)
				SetLine(data.BoxLines[4], Vector2.new(Min.X, Max.Y), Min, Thick, BoxColor)
			end
		end

		-- ===== HEALTH =====
		local Health = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
		local HealthColor = Library.Flags.ESP_HealthColor or Color3.fromRGB(0, 255, 0)
		-- Lerp red->green when using default style
		local HealthStyle = Library.Flags.ESP_HealthStyle or "Both"
		local LeftSide = (Library.Flags.ESP_HealthBarSide or "Left") == "Left"

		if Library.Flags.ESP_Health and (HealthStyle == "Bar" or HealthStyle == "Both") then
			local X = LeftSide and Min.X - 5 or Max.X + 3
			local BH = Height + 2
			local d = data.HealthBar.obj
			d.Visible = true
			d.Color = Color3.fromRGB(0, 0, 0)
			d.Position = Vector2.new(X, Min.Y - 1)
			d.Size = Vector2.new(2, BH)
			d.Filled = true
			d.Transparency = 0.4
			local f = data.HealthFill.obj
			f.Visible = true
			f.Color = HealthColor
			f.Position = Vector2.new(X, Min.Y - 1 + (BH * (1 - Health)))
			f.Size = Vector2.new(2, BH * Health)
			f.Filled = true
			f.Transparency = 1 - Opacity
		end

		-- ===== TEXT =====
		local TextColor = BaseColor
		if RainbowFor({"Text"}) then TextColor = NextRainbow(Library.Flags.ESP_RainbowSpeed or 1) end

		if Library.Flags.ESP_Names then
			local Name = Library.Flags.ESP_NameMode == "Username" and player.Name or player.DisplayName
			SetText(data.Name, Name, Vector2.new(RootVP.X, Max.Y + 2), TextSize, TextColor, true, Library.Flags.ESP_Outline)
		end

		if Library.Flags.ESP_Distance then
			local dist = (RootPos - Camera:GetPivot().Position).Magnitude
			SetText(data.Distance, ("%.0f studs"):format(dist), Vector2.new(RootVP.X, Max.Y + 2 + TextSize + 1), TextSize - 2, TextColor, true, Library.Flags.ESP_Outline)
		end

		if Library.Flags.ESP_Health and (HealthStyle == "Text" or HealthStyle == "Both") then
			SetText(data.HealthText, ("%d%%"):format(math.floor(Health * 100)), Vector2.new(RootVP.X, Min.Y - 13), TextSize - 1, HealthColor, true, Library.Flags.ESP_Outline)
		end

		-- ===== TRACERS =====
		if Library.Flags.ESP_Tracers then
			local TColor = Library.Flags.ESP_TracerColor or BaseColor
			if RainbowFor({"Tracers"}) then TColor = NextRainbow(Library.Flags.ESP_RainbowSpeed or 1) end
			local Viewport = Camera.ViewportSize
			local origin
			local TType = Library.Flags.ESP_TracerType or "From Bottom"
			if TType == "From Top" then
				origin = Vector2.new(Viewport.X / 2, 0)
			elseif TType == "From Center" then
				origin = Vector2.new(Viewport.X / 2, Viewport.Y / 2)
			elseif TType == "From Mouse" then
				local mouse = LocalPlayer:GetMouse()
				origin = Vector2.new(mouse.X, mouse.Y)
			else
				origin = Vector2.new(Viewport.X / 2, Viewport.Y)
			end
			SetLine(data.Tracers[1], origin, RootVP, Library.Flags.ESP_TracerThickness or 1, TColor)
		end

		-- ===== SKELETON =====
		if Library.Flags.ESP_Skeleton then
			local SColor = Library.Flags.ESP_SkeletonColor or Color3.fromRGB(255, 255, 255)
			if RainbowFor({"Tracers"}) then SColor = NextRainbow(Library.Flags.ESP_RainbowSpeed or 1) end
			local Torso = char:FindFirstChild("UpperTorso") or root
			local LH = char:FindFirstChild("LeftHand") or char:FindFirstChild("Left Arm")
			local RH = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
			local LF = char:FindFirstChild("LeftFoot") or char:FindFirstChild("Left Leg")
			local RF = char:FindFirstChild("RightFoot") or char:FindFirstChild("Right Leg")

			local function VP(P)
				if not P then return nil end
				local v = Camera:WorldToViewportPoint(P.Position)
				if v.Z > 1 then return nil end
				return Vector2.new(v.X, v.Y)
			end

			local connections = {
				{ head, Torso },
				{ Torso, LH },
				{ Torso, RH },
				{ Torso, LF },
				{ Torso, RF },
			}
			for i, pair in ipairs(connections) do
				local A = VP(pair[1])
				local B = VP(pair[2])
				if A and B then
					SetLine(data.Skeleton[i], A, B, Library.Flags.ESP_SkeletonThickness or 1, SColor)
				end
			end
		end

		-- ===== HEAD DOT =====
		if Library.Flags.ESP_Head then
			local d = data.Head.obj
			d.Visible = true
			local hp = Camera:WorldToViewportPoint(HeadPos)
			d.Position = Vector2.new(hp.X, hp.Y)
			d.Radius = 3.5
			d.Thickness = 1
			d.Color = BaseColor
			d.Filled = false
		end
	end
end)

-- ===== CLEANUP =====
LocalPlayer.CharacterAdded:Connect(function()
	RaycastParams.FilterDescendantsInstances = { LocalPlayer.Character }
end)

print("[VisionWare] ESP loaded")