-- Desktop camera: Roblox's built-in first-person (LockFirstPerson) + a temporary V toggle to compare with
-- third person. Also owns the crosshair and the "free cursor" key. Does nothing on touch devices.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local UI = require(script.Parent.UIController)

local P = Config.Palette
local player = Players.LocalPlayer

local CameraController = {}

local TOGGLE_KEY = Enum.KeyCode.V -- temporary comparison toggle
local FREE_CURSOR_KEY = Enum.KeyCode.LeftAlt -- press to toggle MINING mode <-> FREE-CURSOR mode (first person)
local START_FIRST_PERSON = true
local THIRD_PERSON_DISTANCE = 12
local SHOVEL_FADE = 0.85 -- LocalTransparencyModifier applied while the shovel covers the crosshair / mining face
local SHOVEL_FP_SCALE = 0.5 -- the held shovel is drawn this fraction of its size in first person (local only)
local CLEARANCE_RADIUS = 0.06 -- of viewport height: how far around the crosshair must stay clear

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
end

local function updateHint()
	if not hint then
		return
	end
	if not wantFirst then
		hint.Text = "THIRD PERSON  -  V: switch view  -  R: return to camp"
	elseif UI.IsCursorFree() then
		hint.Text = "FREE CURSOR  -  ALT: back to mining  -  V: switch view"
	else
		hint.Text = "MINING  -  ALT: free cursor  -  V: switch view  -  R: return to camp"
	end
end

-- Pauses camera rotation (mouse-look, right-drag, wheel zoom) by sinking those inputs ahead of the default
-- camera scripts. Only used while a menu / free-cursor mode owns the pointer.
local frozen = false
local function setCameraFrozen(freeze: boolean)
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

function CameraController.Toggle()
	if desktop then
		wantFirst = not wantFirst
		if not wantFirst then
			UI.SetCursorFree(false) -- third person always has a free pointer; leave the mode flag clean
		end
		applyMode()
		updateHint()
		setCameraFrozen(wantFirst and UI.IsMenuOpen())
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

-- Local-only first-person shovel shrink. Scales every part, weld offset and the grip about the hand so the
-- model keeps its proportions. Tracked per tool instance in a local attribute, and undone in third person.
local function setToolScale(tool: Instance, scale: number)
	local current = tool:GetAttribute("FPScale") or 1
	if math.abs(current - scale) < 1e-3 then
		return
	end
	local ratio = scale / current
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Size *= ratio
		elseif d:IsA("Weld") then
			local c0 = d.C0
			d.C0 = CFrame.new(c0.Position * ratio) * (c0 - c0.Position)
		end
	end
	if tool:IsA("Tool") then
		local g = tool.Grip
		tool.Grip = CFrame.new(g.Position * ratio) * (g - g.Position)
		local base = tool:FindFirstChild("BaseGripValue")
		if base and base:IsA("CFrameValue") then
			base.Value = tool.Grip
		end
	end
	tool:SetAttribute("FPScale", scale)
end

local CLEARANCE_OFFSETS = {
	Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(-1, 0), Vector2.new(0, 1), Vector2.new(0, -1),
}

-- Shrinks the held shovel in first person and fades it only while it sits over the crosshair or the
-- area right around it (the face being mined). Five rays per frame; no art changes.
local function updateToolClearance(dt: number)
	local char = player.Character
	local tool = char and char:FindFirstChildOfClass("Tool") -- the shovel OR a carried artifact
	if not tool then
		return
	end
	local first = CameraController.IsFirstPerson()
	local fp = tool:GetAttribute("ToolFPScale") or SHOVEL_FP_SCALE
	setToolScale(tool, first and fp or 1)

	local target = 0
	if first and not UI.IsMenuOpen() then
		if tool ~= lastTool then
			lastTool = tool
			toolParams.FilterDescendantsInstances = { tool }
		end
		local cam = Workspace.CurrentCamera
		local c = cam.ViewportSize / 2
		local r = cam.ViewportSize.Y * CLEARANCE_RADIUS
		for _, o in ipairs(CLEARANCE_OFFSETS) do
			local ray = cam:ViewportPointToRay(c.X + o.X * r, c.Y + o.Y * r)
			if Workspace:Raycast(ray.Origin, ray.Direction * 40, toolParams) then
				target = SHOVEL_FADE
				break
			end
		end
	end
	fade += (target - fade) * math.min(1, dt * 14)
	local value = (first and fade > 0.01) and fade or 0
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") and d.LocalTransparencyModifier ~= value then
			d.LocalTransparencyModifier = value
		end
	end
end

function CameraController.Init()
	buildHud()
	if not desktop then
		return
	end
	applyMode()
	updateHint()
	player.CharacterAdded:Connect(applyMode)

	UI.OnMenuChanged(function()
		updateHint()
		setCameraFrozen(wantFirst and UI.IsMenuOpen())
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == FREE_CURSOR_KEY and wantFirst then
			-- Alt toggles; DigController drops held input on the change, so mining needs a fresh click.
			UI.SetCursorFree(not UI.IsCursorFree())
		elseif not processed and input.KeyCode == TOGGLE_KEY then
			CameraController.Toggle()
		end
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
