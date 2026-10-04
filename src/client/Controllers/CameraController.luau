-- Desktop camera.
--
-- FIRST PERSON uses our own camera (CameraType = Scriptable) because Roblox's built-in camera offers no per-game
-- mouse-sensitivity multiplier: the only built-in control is the player's global Roblox setting, which a game must not
-- overwrite. All mouse-look in first person is computed HERE, once:
--
--     yaw/pitch change (radians) = mouse delta (pixels) x BASE x RobloxSensitivity x Settings.MouseSensitivity
--
--   * delta comes from UserInputService:GetMouseDelta() (pixels moved since the last frame), so the turn angle depends
--     only on how far the mouse moved - NOT on the frame rate. There is no dt term, smoothing, acceleration or inertia.
--   * the character is turned to the camera yaw each frame; the default camera scripts are idle (Scriptable).
--   * camera shake (Humanoid.CameraOffset) is added on top and is completely independent of look sensitivity.
--   * BASE is an ESTIMATE of the built-in camera's feel, not a measured value. See BASE_DEGREES_PER_PIXEL.
-- THIRD PERSON (V) uses Roblox's normal camera untouched.
-- The free cursor / menus (InputMode) stop mouse-look and release the cursor.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Settings = require(script.Parent.Settings)
local InputMode = require(script.Parent.InputMode)
local Bindings = require(script.Parent.Bindings)

local P = Config.Palette
local player = Players.LocalPlayer

local CameraController = {}

-- Degrees of turn per pixel of mouse movement at sensitivity setting 1.0 and Roblox sensitivity 1.0.
-- PROVISIONAL: chosen so the default setting (0.30) gives about 0.075 degrees/pixel (roughly 120 degrees per 5 cm of
-- mouse travel at 800 DPI). Not measured against Roblox's built-in camera; adjust here after playtesting.
local BASE_DEGREES_PER_PIXEL = 0.25
local PITCH_LIMIT = math.rad(85)
local FIRST_PERSON_FOV = 70
local THIRD_PERSON_DISTANCE = 12
local START_FIRST_PERSON = true

local desktop = not UserInputService.TouchEnabled
local wantFirst = START_FIRST_PERSON
local active = false -- our camera is currently driving
local yaw, pitch = 0, 0
local bodyParts: { BasePart } = {}
local bodyCharacter: Model? = nil

local crossGui: ScreenGui
local cross: Frame
local hint: TextLabel
local crossState = "none"

function CameraController.IsDesktop(): boolean
	return desktop
end

-- Whether the player WANTS first person (V toggle), even while dead/respawning.
function CameraController.IsFirstPerson(): boolean
	return desktop and wantFirst
end

-- Whether our first-person camera is actually driving right now (viewmodel and crosshair follow this).
function CameraController.IsActive(): boolean
	return active
end

-- "hit" (in reach), "far" (valid block out of reach) or "none"
function CameraController.SetCrosshairState(state: string)
	crossState = state
end

local function robloxSensitivity(): number
	local ok, v = pcall(function()
		return UserSettings():GetService("UserGameSettings").MouseSensitivity
	end)
	if ok and type(v) == "number" and v > 0 then
		return v
	end
	return 1
end

-- Radians of turn per pixel with the current settings (exposed for the settings display and tests).
function CameraController.RadiansPerPixel(): number
	return math.rad(BASE_DEGREES_PER_PIXEL) * robloxSensitivity() * Settings.Get("MouseSensitivity")
end

-- Third person: when a menu/free-cursor owns the pointer, sink the default camera's mouse input.
local frozen = false
local function setThirdPersonFrozen(freeze: boolean)
	if freeze == frozen then
		return
	end
	frozen = freeze
	if freeze then
		ContextActionService:BindActionAtPriority("DigFreezeCamera", function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 100,
			Enum.UserInputType.MouseMovement, Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseWheel)
	else
		ContextActionService:UnbindAction("DigFreezeCamera")
	end
end

local function refreshBodyParts(char: Model)
	if bodyCharacter == char then
		return
	end
	bodyCharacter = char
	table.clear(bodyParts)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and not d:FindFirstAncestorWhichIsA("Tool") then
			table.insert(bodyParts, d)
		end
	end
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and not d:FindFirstAncestorWhichIsA("Tool") then
			table.insert(bodyParts, d)
		end
	end)
end

local function setBodyHidden(hidden: boolean)
	for _, p in ipairs(bodyParts) do
		if p.Parent then
			p.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

local function enter(cam: Camera, humanoid: Humanoid)
	local look = cam.CFrame.LookVector
	yaw = math.atan2(-look.X, -look.Z)
	pitch = math.clamp(math.asin(math.clamp(look.Y, -1, 1)), -PITCH_LIMIT, PITCH_LIMIT)
	player.CameraMode = Enum.CameraMode.Classic
	humanoid.AutoRotate = false
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = FIRST_PERSON_FOV
	active = true
	setThirdPersonFrozen(false)
end

local function leave(cam: Camera, humanoid: Humanoid?)
	active = false
	setBodyHidden(false)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	if humanoid then
		humanoid.AutoRotate = true
	end
	cam.CameraType = Enum.CameraType.Custom
	-- pull the camera out of first person, then give the player their normal zoom range back
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = THIRD_PERSON_DISTANCE
	task.delay(0.15, function()
		player.CameraMinZoomDistance = 0.5
	end)
end

local function step()
	local cam = Workspace.CurrentCamera
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local head = char and char:FindFirstChild("Head")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local want = desktop and wantFirst and humanoid ~= nil and head ~= nil and hrp ~= nil
		and (humanoid :: Humanoid).Health > 0

	if want and not active then
		enter(cam, humanoid :: Humanoid)
	elseif not want and active then
		leave(cam, humanoid)
	end

	if not active then
		if desktop then
			setThirdPersonFrozen(InputMode.IsCursorFree())
		end
		return
	end

	refreshBodyParts(char :: Model)
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable -- something (e.g. a respawn) reset it
	end

	local locked = not InputMode.IsCursorFree()
	UserInputService.MouseBehavior = locked and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
	if locked then
		local delta = UserInputService:GetMouseDelta()
		local k = CameraController.RadiansPerPixel()
		local invert = Settings.Get("InvertY") and -1 or 1
		yaw -= delta.X * k
		pitch = math.clamp(pitch - delta.Y * k * invert, -PITCH_LIMIT, PITCH_LIMIT)
	end

	-- the character always faces the camera yaw (movement is camera-relative)
	local root = hrp :: BasePart
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	root.AssemblyAngularVelocity = Vector3.zero

	local eye = (head :: BasePart).Position + Vector3.new(0, 0.2, 0) + (humanoid :: Humanoid).CameraOffset
	cam.CFrame = CFrame.new(eye) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	setBodyHidden(true)
end

local function updateHint()
	if not hint then
		return
	end
	local V, R, A = Bindings.Name(Bindings.CameraToggle), Bindings.Name(Bindings.ReturnToCamp), Bindings.Name(Bindings.FreeCursor)
	local M = Bindings.Name(Bindings.Menu)
	if not wantFirst then
		hint.Text = ("THIRD PERSON  -  %s: switch view  -  %s: return to camp  -  %s: menu"):format(V, R, M)
	elseif InputMode.IsFreeCursor() then
		hint.Text = ("FREE CURSOR  -  %s: back to mining  -  %s: switch view  -  %s: menu"):format(A, V, M)
	else
		hint.Text = ("MINING  -  %s: free cursor  -  %s: switch view  -  %s: return to camp  -  %s: menu"):format(A, V, R, M)
	end
end

function CameraController.Toggle()
	if desktop and not InputMode.IsMenuOpen() then
		wantFirst = not wantFirst
		if not wantFirst then
			InputMode.SetFreeCursor(false)
		end
		updateHint()
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
	local s = Instance.new("UIStroke")
	s.Color = P.Dark
	s.Thickness = 1.5
	s.Parent = cross

	hint = Instance.new("TextLabel")
	hint.Name = "ViewHint"
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -8)
	hint.Size = UDim2.fromOffset(760, 20)
	hint.Font = Enum.Font.FredokaOne
	hint.TextSize = 14
	hint.TextColor3 = P.Cream
	hint.TextTransparency = 0.35
	hint.TextStrokeTransparency = 0.6
	hint.Visible = desktop
	hint.Parent = crossGui
end

function CameraController.Init()
	buildHud()
	if not desktop then
		return
	end
	updateHint()
	InputMode.OnChanged(updateHint)

	UserInputService.InputBegan:Connect(function(input, processed)
		if UserInputService:GetFocusedTextBox() or InputMode.IsMenuOpen() then
			return
		end
		if input.KeyCode == Bindings.FreeCursor and wantFirst then
			-- Alt toggles; the dig controller drops held input on the change, so mining needs a fresh click.
			InputMode.SetFreeCursor(not InputMode.IsFreeCursor())
		elseif not processed and input.KeyCode == Bindings.CameraToggle then
			CameraController.Toggle()
		end
	end)

	-- Runs right after Roblox's own camera step, so ours has the last word each frame.
	RunService:BindToRenderStep("DigCamera", Enum.RenderPriority.Camera.Value + 1, function()
		step()
		cross.Visible = active and not InputMode.IsCursorFree() and player.Character ~= nil
		if cross.Visible then
			cross.BackgroundColor3 = crossState == "hit" and P.Gold or (crossState == "far" and P.Danger or P.Cream)
		end
	end)
end

return CameraController
