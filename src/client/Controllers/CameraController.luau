-- Desktop camera: Roblox's built-in first-person (LockFirstPerson) + a temporary V toggle to compare with
-- third person. Also owns the crosshair and the "free cursor" key. Does nothing on touch devices.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UI = require(script.Parent.UIController)

local P = Config.Palette
local player = Players.LocalPlayer

local CameraController = {}

local TOGGLE_KEY = Enum.KeyCode.V -- temporary comparison toggle
local FREE_CURSOR_KEY = Enum.KeyCode.LeftAlt -- hold to release the cursor in first person (e.g. click TO CAMP)
local START_FIRST_PERSON = true
local THIRD_PERSON_DISTANCE = 12
local SHOVEL_FADE = 0.8 -- LocalTransparencyModifier applied only while the shovel covers the crosshair

local desktop = not UserInputService.TouchEnabled
local wantFirst = START_FIRST_PERSON

local crossGui: ScreenGui
local cross: Frame
local crossStroke: UIStroke
local hint: TextLabel
local crossState = "none"

local toolParams = RaycastParams.new()
toolParams.FilterType = Enum.RaycastFilterType.Include
local lastTool: Instance? = nil
local fade = 0

function CameraController.IsDesktop(): boolean
	return desktop
end

function CameraController.IsFirstPerson(): boolean
	return desktop and wantFirst
end

-- "hit" (in reach), "far" (valid block out of reach) or "none"
function CameraController.SetCrosshairState(state: string)
	crossState = state
end

local function applyMode()
	if not desktop then
		return
	end
	if wantFirst then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	else
		player.CameraMode = Enum.CameraMode.Classic
		-- Pull the camera back out of first person, then give the player their normal zoom range again.
		player.CameraMinZoomDistance = THIRD_PERSON_DISTANCE
		task.delay(0.15, function()
			player.CameraMinZoomDistance = 0.5
		end)
	end
	if hint then
		hint.Text = wantFirst and "FIRST PERSON  -  V: switch view  -  hold ALT: free cursor"
			or "THIRD PERSON  -  V: switch view"
	end
end

function CameraController.Toggle()
	if desktop then
		wantFirst = not wantFirst
		applyMode()
	end
end

local function buildHud()
	crossGui = Instance.new("ScreenGui")
	crossGui.Name = "CameraHUD"
	crossGui.ResetOnSpawn = false
	crossGui.IgnoreGuiInset = true -- so scale 0.5/0.5 is exactly ViewportSize / 2, where the ray is cast
	crossGui.DisplayOrder = 5
	crossGui.Parent = player:WaitForChild("PlayerGui")

	cross = Instance.new("Frame")
	cross.Name = "Crosshair"
	cross.AnchorPoint = Vector2.new(0.5, 0.5)
	cross.Position = UDim2.fromScale(0.5, 0.5)
	cross.Size = UDim2.fromOffset(6, 6)
	cross.BackgroundColor3 = P.Cream
	cross.BorderSizePixel = 0
	cross.Active = false
	cross.Visible = false
	cross.Parent = crossGui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = cross
	crossStroke = Instance.new("UIStroke")
	crossStroke.Color = P.Dark
	crossStroke.Thickness = 1.5
	crossStroke.Parent = cross

	hint = Instance.new("TextLabel")
	hint.Name = "ViewHint"
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -8)
	hint.Size = UDim2.fromOffset(520, 20)
	hint.Font = Enum.Font.FredokaOne
	hint.TextSize = 14
	hint.TextColor3 = P.Cream
	hint.TextTransparency = 0.35
	hint.TextStrokeTransparency = 0.6
	hint.Visible = desktop
	hint.Parent = crossGui
end

-- Fades the held shovel only while it would sit on top of the crosshair (one extra ray; no art changes).
local function updateToolClearance(dt: number)
	local char = player.Character
	local tool = char and char:FindFirstChild("Shovel")
	local target = 0
	if tool and CameraController.IsFirstPerson() and not UI.IsMenuOpen() then
		if tool ~= lastTool then
			lastTool = tool
			toolParams.FilterDescendantsInstances = { tool }
		end
		local cam = Workspace.CurrentCamera
		local vp = cam.ViewportSize / 2
		local ray = cam:ViewportPointToRay(vp.X, vp.Y)
		if Workspace:Raycast(ray.Origin, ray.Direction * 40, toolParams) then
			target = SHOVEL_FADE
		end
	end
	fade += (target - fade) * math.min(1, dt * 14)
	if tool and (fade > 0.01 or target > 0) then
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = fade
			end
		end
	elseif tool and fade <= 0.01 and lastTool == tool then
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("BasePart") and d.LocalTransparencyModifier ~= 0 then
				d.LocalTransparencyModifier = 0
			end
		end
	end
end

function CameraController.Init()
	buildHud()
	if not desktop then
		return
	end
	applyMode()
	player.CharacterAdded:Connect(applyMode)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == TOGGLE_KEY then
			CameraController.Toggle()
		elseif input.KeyCode == FREE_CURSOR_KEY and wantFirst then
			UI.SetCursorFree(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == FREE_CURSOR_KEY then
			UI.SetCursorFree(false)
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		UI.SetCursorFree(false)
	end)

	RunService.RenderStepped:Connect(function(dt)
		local show = CameraController.IsFirstPerson() and not UI.IsMenuOpen()
			and player.Character ~= nil
		cross.Visible = show
		if show then
			cross.BackgroundColor3 = crossState == "hit" and P.Gold or (crossState == "far" and P.Danger or P.Cream)
		end
		updateToolClearance(dt)
	end)
end

return CameraController
