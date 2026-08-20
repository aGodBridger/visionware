--[[
    VisionWare | crosshair.lua
    ==========================
    Crosshair as its own module. Uses the shared `Vision` API (shared.lua).
    Renders a customizable crosshair at screen center.
]]

local Vision
for _ = 1, 100 do
    Vision = (getgenv and getgenv().Vision) or _G.Vision
    if Vision and Vision.Flag then break end
    task.wait(0.1)
end
if not Vision then
    warn("[VisionWare] crosshair.lua could not find shared API")
    return
end

local RunService = Vision.RunService
local Library = Vision.Library
local Flag = Vision.Flag

local ScreenGUI = Library and Library.ScreenGUI
if not ScreenGUI then
    warn("[VisionWare] crosshair.lua: no ScreenGUI available")
    return
end

local Crosshair = Instance.new("Frame")
Crosshair.Name = "VisionCrosshair"
Crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
Crosshair.BackgroundTransparency = 1
Crosshair.BorderSizePixel = 0
Crosshair.Size = UDim2.new(0, 0, 0, 0)
Crosshair.Position = UDim2.new(0.5, 0, 0.5, 0)
Crosshair.Parent = ScreenGUI

local function MakeLine(Name)
    local Line = Instance.new("Frame")
    Line.Name = Name
    Line.BackgroundColor3 = (Library and Library.Accent) or Color3.fromRGB(0, 255, 0)
    Line.BorderSizePixel = 0
    Line.Visible = false
    Line.Parent = Crosshair
    local Stroke = Instance.new("UIStroke")
    Stroke.Color = Color3.fromRGB(0, 0, 0)
    Stroke.Parent = Line
    return Line, Stroke
end

local Top, TopStroke = MakeLine("Top")
local Bottom, BottomStroke = MakeLine("Bottom")
local Left, LeftStroke = MakeLine("Left")
local Right, RightStroke = MakeLine("Right")
local Dot, DotStroke = MakeLine("Dot")

local Circle = Instance.new("Frame")
Circle.Name = "Circle"
Circle.BackgroundTransparency = 1
Circle.BorderSizePixel = 0
Circle.AnchorPoint = Vector2.new(0.5, 0.5)
Circle.Position = UDim2.new(0.5, 0, 0.5, 0)
Circle.Visible = false
Circle.Parent = Crosshair
local CircleCorner = Instance.new("UICorner")
CircleCorner.CornerRadius = UDim.new(1, 0)
CircleCorner.Parent = Circle
local CircleStroke = Instance.new("UIStroke")
CircleStroke.Parent = Circle

local Lines = { {Top, TopStroke}, {Bottom, BottomStroke}, {Left, LeftStroke}, {Right, RightStroke}, {Dot, DotStroke} }

local function Render()
    local Enabled = Flag("Misc_Crosshair", true) and not Vision.IsPanic()
    Crosshair.Visible = Enabled
    if not Enabled then return end

    local Color = Flag("Misc_CrosshairColor", Color3.fromRGB(0, 255, 0)) or Color3.fromRGB(0, 255, 0)
    local Thickness = Flag("Misc_CrosshairThickness", 2) or 2
    local Length = Flag("Misc_CrosshairLength", 10) or 10
    local Gap = Flag("Misc_CrosshairGap", 3) or 3
    local Style = Flag("Misc_CrosshairStyle", "Plus")
    local UseOutline = Flag("Misc_CrosshairOutline", true)
    local UseDot = Flag("Misc_CrosshairDot", false)

    for _, Pair in ipairs(Lines) do
        Pair[1].BackgroundColor3 = Color
        Pair[1].Visible = false
        Pair[2].Enabled = UseOutline
    end

    local plus = Style == "Plus"
    local cross = Style == "Cross"
    local dot = Style == "Dot"

    Top.Size = UDim2.new(0, Thickness, 0, Length)
    Top.Position = UDim2.new(0.5, -Thickness / 2, 0.5, -(Gap + Length))
    Top.Visible = plus or cross

    Bottom.Size = UDim2.new(0, Thickness, 0, Length)
    Bottom.Position = UDim2.new(0.5, -Thickness / 2, 0.5, Gap)
    Bottom.Visible = plus or cross

    Left.Size = UDim2.new(0, Length, 0, Thickness)
    Left.Position = UDim2.new(0.5, -(Gap + Length), 0.5, -Thickness / 2)
    Left.Visible = plus

    Right.Size = UDim2.new(0, Length, 0, Thickness)
    Right.Position = UDim2.new(0.5, Gap, 0.5, -Thickness / 2)
    Right.Visible = plus

    Dot.Size = UDim2.new(0, Thickness, 0, Thickness)
    Dot.Position = UDim2.new(0.5, -Thickness / 2, 0.5, -Thickness / 2)
    Dot.Visible = UseDot or dot

    Circle.Visible = Style == "Circle"
    CircleStroke.Color = Color
    CircleStroke.Enabled = UseOutline
    local Rad = Gap + Length
    Circle.Size = UDim2.new(0, Rad * 2, 0, Rad * 2)
    Circle.Position = UDim2.new(0.5, 0, 0.5, 0)
end

RunService.RenderStepped:Connect(Render)

print("[VisionWare] crosshair.lua loaded")