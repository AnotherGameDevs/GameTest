-- Input + targeting for digging. Desktop: hold click/tap on dirt. Mobile: tap/hold the dirt, or hold the DIG button
-- (auto-aims forward-down). The client only *requests* hits; the server validates everything.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local State = require(script.Parent.State)
local Effects = require(script.Parent.EffectsController)
local UI = require(script.Parent.UIController)

local P = Config.Palette
local player = Players.LocalPlayer
local DigController = {}

local FEEL = {
	SwingPitchSign = 1, -- flip to -1 if the shovel swings the wrong way
	SwingWindup = 0.9, -- radians
	SwingStrike = 0.7,
}

local TOUCH = UserInputService.TouchEnabled
local digHit = Remotes.Get("DigHit")

local pointerHeld = false
local pointerPos: Vector2? = nil
local buttonHeld = false
local lastSent = 0
local targetBox: SelectionBox
local swingToken = 0

local function viewportPos(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
end

local function siteParams(): RaycastParams?
	local site = Workspace:FindFirstChild("DigSite")
	if not site then
		return nil
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { site }
	return rp
end

local function castResult(origin: Vector3, dir: Vector3): (Part?, Vector3?, Vector3?)
	local rp = siteParams()
	if not rp then
		return nil
	end
	local r = Workspace:Raycast(origin, dir, rp)
	if r and r.Instance:IsA("Part") and tonumber(r.Instance.Name) then
		return r.Instance, r.Position, r.Normal
	end
	return nil
end

local function aimFromScreen(vp: Vector2): (Part?, Vector3?, Vector3?)
	local cam = Workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(vp.X, vp.Y)
	return castResult(ray.Origin, ray.Direction * 300)
end

local function aimAuto(): (Part?, Vector3?, Vector3?)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local reach = State.Tool().Reach
	local origin = hrp.Position + Vector3.new(0, 1, 0)
	local look = hrp.CFrame.LookVector
	local dirs = {
		(look + Vector3.new(0, -1, 0)).Unit,
		(look * 1.5 + Vector3.new(0, -0.4, 0)).Unit,
		Vector3.new(0, -1, 0),
	}
	for _, d in ipairs(dirs) do
		local part, pos, normal = castResult(origin, d * (reach + 2))
		if part then
			return part, pos, normal
		end
	end
	return nil
end

local function inReach(part: Part): boolean
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	return (hrp.Position - part.Position).Magnitude <= State.Tool().Reach + Grid.CellSize
end

local function swing(interval: number)
	local char = player.Character
	local tool = char and char:FindFirstChild("Shovel")
	if not tool or not tool:IsA("Tool") then
		return
	end
	local base = tool:FindFirstChild("BaseGripValue")
	if not base then
		base = Instance.new("CFrameValue")
		base.Name = "BaseGripValue"
		base.Value = tool.Grip
		base.Parent = tool
	end
	swingToken += 1
	local token = swingToken
	local sign = FEEL.SwingPitchSign
	local t = math.min(interval, 0.5)
	local g = base.Value
	TweenService:Create(tool, TweenInfo.new(t * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Grip = g * CFrame.Angles(-sign * FEEL.SwingWindup, 0, 0) }):Play()
	task.delay(t * 0.3, function()
		if token ~= swingToken or not tool.Parent then
			return
		end
		TweenService:Create(tool, TweenInfo.new(t * 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Grip = g * CFrame.Angles(sign * FEEL.SwingStrike, 0, 0) }):Play()
		task.delay(t * 0.2, function()
			if token ~= swingToken or not tool.Parent then
				return
			end
			TweenService:Create(tool, TweenInfo.new(t * 0.35, Enum.EasingStyle.Quad), { Grip = g }):Play()
		end)
	end)
end

local function faceTarget(pos: Vector3)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local flat = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
	if flat.Magnitude > 1.5 then
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
	end
end

local function currentAim(): (Part?, Vector3?, Vector3?)
	if buttonHeld then
		return aimAuto()
	end
	if pointerHeld and pointerPos then
		return aimFromScreen(pointerPos)
	end
	if not TOUCH then
		return aimFromScreen(UserInputService:GetMouseLocation())
	end
	return nil
end

function DigController.Init()
	targetBox = Instance.new("SelectionBox")
	targetBox.Name = "DigTarget"
	targetBox.LineThickness = 0.07
	targetBox.Color3 = P.Gold
	targetBox.SurfaceColor3 = P.Gold
	targetBox.SurfaceTransparency = 0.85
	targetBox.Parent = Workspace

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pointerHeld = true
			pointerPos = viewportPos(input)
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.ButtonA then
			buttonHeld = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if pointerHeld and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			pointerPos = viewportPos(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			pointerHeld = false
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.ButtonA then
			buttonHeld = false
		end
	end)

	-- Mobile DIG button
	if TOUCH then
		local btn = Instance.new("TextButton")
		btn.Name = "DigButton"
		btn.Size = UDim2.fromOffset(104, 104)
		btn.AnchorPoint = Vector2.new(1, 1)
		btn.Position = UDim2.new(1, -120, 1, -150)
		btn.BackgroundColor3 = P.Gold
		btn.Text = "DIG"
		btn.TextSize = 34
		btn.Font = Enum.Font.FredokaOne
		btn.TextColor3 = P.Dark
		btn.AutoButtonColor = true
		btn.Parent = UI.GetGui()
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = btn
		local s = Instance.new("UIStroke")
		s.Thickness = 4
		s.Color = P.Dark
		s.Parent = btn
		btn.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				buttonHeld = true
			end
		end)
		btn.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				buttonHeld = false
			end
		end)
	end

	RunService.RenderStepped:Connect(function()
		local part, pos, normal = currentAim()
		if part and not part.Parent then
			part = nil
		end
		if part then
			targetBox.Adornee = part
			targetBox.Color3 = inReach(part) and P.Gold or P.Danger
		else
			targetBox.Adornee = nil
		end

		if not (pointerHeld or buttonHeld) or not part or not pos or not normal then
			return
		end
		if State.Data.Count == nil or not inReach(part) then
			return
		end
		local tool = State.Tool()
		local interval = 1 / tool.Rate
		local now = os.clock()
		if now - lastSent < interval then
			return
		end
		lastSent = now

		local x, y, z = Grid.FromIndex(tonumber(part.Name) :: number)
		digHit:FireServer(x, y, z)
		faceTarget(part.Position)
		swing(interval)
		Effects.NoteFace(part, normal)
		Effects.Impact(part, pos, normal)
	end)
end

return DigController
