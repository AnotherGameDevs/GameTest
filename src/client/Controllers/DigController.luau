-- Input + targeting for digging.
--   Desktop first person : ray from the exact screen centre (the crosshair), re-cast every frame.
--   Desktop third person : ray from the mouse cursor.
--   Touch                : unchanged (tap/hold the dirt, or hold the DIG button which auto-aims).
-- ONE targeting result per frame drives both the highlight and the hit request. The client only *requests*
-- hits; the server validates tool, cooldown, reach, cell state and rewards.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local State = require(script.Parent.State)
local Effects = require(script.Parent.EffectsController)
local InputMode = require(script.Parent.InputMode)
local CameraController = require(script.Parent.CameraController)
local Viewmodel = require(script.Parent.ViewmodelController)
local UI = require(script.Parent.UIController)

local P = Config.Palette
local player = Players.LocalPlayer
local DigController = {}

local FEEL = {
	SwingPitchSign = 1, -- flip to -1 if the shovel swings the wrong way
	SwingWindup = 0.9, -- radians
	SwingStrike = 0.7,
	FirstPersonRayPadding = 3, -- studs beyond tool reach for the ray (camera sits above the HumanoidRootPart)
}

local TOUCH = UserInputService.TouchEnabled
local digHit = Remotes.Get("DigHit")

local pointerHeld = false
local pointerPos: Vector2? = nil -- touch only
local buttonHeld = false
local lastSent = 0
local targetBox: SelectionBox
local swingToken = 0

-- Ignore the local character (incl. the held shovel) and cosmetic effects; everything solid still blocks.
-- RespectCanCollide skips non-solid helpers (invisible prompts, fading chunks, locally-broken blocks).
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function refreshFilter()
	local list: { Instance } = { Effects.GetFolder() }
	if player.Character then
		table.insert(list, player.Character)
	end
	rayParams.FilterDescendantsInstances = list
end

type Target = {
	Part: Part,
	Position: Vector3,
	Normal: Vector3,
	X: number,
	Y: number,
	Z: number,
	InReach: boolean,
	Allowed: boolean, -- the equipped tool can break this layer (Defs.LayerAllows)
	NeedTool: string?, -- display name of the tool tier that unlocks it
}

local function viewportPos(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
end

-- Casts one ray. Only counts if the FIRST relevant surface is a dig cell.
local function castDig(origin: Vector3, dir: Vector3): Target?
	local result = Workspace:Raycast(origin, dir, rayParams)
	if not result then
		return nil
	end
	local inst = result.Instance
	local site = Workspace:FindFirstChild("DigSite")
	if not site or inst.Parent ~= site or not inst:IsA("Part") then
		return nil
	end
	local idx = tonumber(inst.Name)
	if not idx or idx < 1 or idx > Grid.Count then
		return nil
	end
	local x, y, z = Grid.FromIndex(idx)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local inReach = false
	if hrp then
		-- the server's rule (Defs.CellInReach), without the server's latency tolerance
		inReach = Defs.CellInReach(State.Tool(), (hrp :: BasePart).Position, x, y, z, 0)
	end
	local layer = Defs.LayerAtCell(y)
	local allowed = Defs.LayerAllows(State.Tool(), layer)
	return { Part = inst, Position = result.Position, Normal = result.Normal, X = x, Y = y, Z = z, InReach = inReach,
		Allowed = allowed, NeedTool = (not allowed) and Defs.ToolNameForTier(layer.MinToolTier or 1) or nil }
end

local function aimScreen(vp: Vector2, length: number): Target?
	local ray = Workspace.CurrentCamera:ViewportPointToRay(vp.X, vp.Y)
	return castDig(ray.Origin, ray.Direction * length)
end

-- First person: the crosshair. Always the exact viewport centre, recomputed every frame.
local function aimCenter(): Target?
	local cam = Workspace.CurrentCamera
	local c = cam.ViewportSize / 2
	return aimScreen(c, State.Tool().Reach + FEEL.FirstPersonRayPadding)
end

-- Touch DIG button: forward-down from the character, then straight down.
local function aimAuto(): Target?
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
		local t = castDig(origin, d * (reach + 2))
		if t then
			return t
		end
	end
	return nil
end

local function acquireTarget(): Target?
	if CameraController.IsFirstPerson() then
		return aimCenter()
	end
	if buttonHeld then
		return aimAuto()
	end
	if TOUCH then
		return (pointerHeld and pointerPos) and aimScreen(pointerPos, 300) or nil
	end
	return aimScreen(UserInputService:GetMouseLocation(), 300)
end

local function swing(interval: number)
	if CameraController.IsActive() then
		Viewmodel.Swing(math.min(interval, 0.5)) -- one animation on the whole first-person assembly
		return
	end
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

-- Third person / touch only. First person lets the camera and normal controls own orientation.
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

-- Drops every held input. Mining only resumes after a FRESH press.
function DigController.ClearInput()
	pointerHeld = false
	buttonHeld = false
	pointerPos = nil
end

local function isBlocked(): boolean
	-- A carried important artifact disables ALL mining (the server enforces this independently).
	return InputMode.IsCursorFree() or UserInputService:GetFocusedTextBox() ~= nil or State.Data.Carrying ~= nil
end

-- The reason-label under the crosshair.
local hintLabel: TextLabel? = nil
local function setHint(text: string?)
	if not hintLabel then
		return
	end
	if text then
		hintLabel.Text = text
	end
	hintLabel.Visible = text ~= nil
end

local function buildHint()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DigHint"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 3
	gui.Parent = player:WaitForChild("PlayerGui")
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0.5, 34) -- below the crosshair, never on it
	l.Size = UDim2.fromOffset(320, 26)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = 20
	l.TextColor3 = P.Danger
	l.TextStrokeTransparency = 0.3
	l.TextStrokeColor3 = P.Dark
	l.Visible = false
	l.Parent = gui
	hintLabel = l
end

local function onStep()
	local blocked = isBlocked()
	if blocked then
		DigController.ClearInput()
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		DigController.ClearInput()
		blocked = true
	end

	local target: Target? = nil
	if not blocked then
		target = acquireTarget()
		if target and not target.Part.Parent then
			target = nil
		end
	end

	-- Highlight + crosshair come from the very same result the hit request uses below.
	if target then
		targetBox.Adornee = target.Part
		local good = target.InReach and target.Allowed
		targetBox.Color3 = good and P.Gold or P.Danger
		CameraController.SetCrosshairState(good and "hit" or "far")
		-- one short reason under the crosshair (never over it) whenever the block can not be dug
		if not target.InReach then
			setHint("TOO FAR - step closer")
		elseif not target.Allowed then
			setHint(("TOO HARD - needs the %s"):format(target.NeedTool or "a stronger tool"))
		else
			setHint(nil)
		end
	else
		targetBox.Adornee = nil
		CameraController.SetCrosshairState("none")
		setHint(nil)
	end

	if blocked or not target or not (pointerHeld or buttonHeld) or not target.InReach or not target.Allowed then
		return
	end

	local interval = 1 / State.Tool().Rate
	local now = os.clock()
	if now - lastSent < interval then
		return
	end
	lastSent = now

	digHit:FireServer(target.X, target.Y, target.Z)
	if not CameraController.IsFirstPerson() then
		faceTarget(target.Part.Position)
	end
	swing(interval)
	Effects.NoteFace(target.Part, target.Normal)
	Effects.Impact(target.Part, target.Position, target.Normal)
end

function DigController.Init()
	targetBox = Instance.new("SelectionBox")
	targetBox.Name = "DigTarget"
	targetBox.LineThickness = 0.07
	targetBox.Color3 = P.Gold
	targetBox.SurfaceColor3 = P.Gold
	targetBox.SurfaceTransparency = 0.85
	targetBox.Parent = Workspace

	refreshFilter()
	buildHint()

	local function onCharacter(char: Model)
		refreshFilter()
		DigController.ClearInput()
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then
			(hum :: Humanoid).Died:Connect(DigController.ClearInput)
		end
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	-- Switching tools (shop purchase / equip) never leaves a held click behind.
	local lastToolId: string? = nil
	State.Connect(function(d)
		if lastToolId and d.ToolId ~= lastToolId then
			DigController.ClearInput()
		end
		lastToolId = d.ToolId
	end)

	-- Anything that steals the cursor/keyboard drops held mining.
	InputMode.OnChanged(DigController.ClearInput)
	UserInputService.WindowFocusReleased:Connect(DigController.ClearInput)
	UserInputService.TextBoxFocused:Connect(DigController.ClearInput)
	GuiService.MenuOpened:Connect(DigController.ClearInput)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or isBlocked() then
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
		if pointerHeld and input.UserInputType == Enum.UserInputType.Touch then
			pointerPos = viewportPos(input)
		elseif pointerHeld and TOUCH and input.UserInputType == Enum.UserInputType.MouseMovement then
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

	-- Mobile DIG button (unchanged)
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
		State.Connect(function(d)
			btn.Visible = d.Carrying == nil
		end)
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

	-- Carrying drops anything held immediately.
	State.Connect(function(d)
		if d.Carrying then
			DigController.ClearInput()
		end
	end)

	-- After the camera has updated, so the centre ray uses this frame's final camera.
	RunService:BindToRenderStep("DigTarget", Enum.RenderPriority.Camera.Value + 2, onStep)
end

return DigController
