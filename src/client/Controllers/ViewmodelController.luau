-- First-person viewmodel: the tool (or carried artifact) drawn in the lower right of the view from the SAME part spec as
-- the held tool and the shop preview. It is one welded assembly (Kit.BuildWelded) and is posed with a single
-- PivotTo(camera * swing * rest) per frame; no individual part is ever moved. Parts never collide and are never
-- raycast. The real Tool in the character is hidden locally while this is shown, so there are no duplicates, and
-- other players still see the real held tool.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Defs = require(ReplicatedStorage.Shared.Defs)
local Kit = require(ReplicatedStorage.Shared.ModelKit)
local ToolModels = require(ReplicatedStorage.Shared.ToolModels)
local TreasureModels = require(ReplicatedStorage.Shared.TreasureModels)
local ViewmodelMath = require(ReplicatedStorage.Shared.ViewmodelMath)

local CameraController = require(script.Parent.CameraController)

local player = Players.LocalPlayer
local ViewmodelController = {}

local model: Model? = nil
local modelKey: string? = nil
local isArtifact = false
local swingStart, swingDuration = 0, 0.4
local hiddenFor: any = {}

local function heldTool(): Tool?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Tool") or nil
end

local function keyFor(tool: Tool): string?
	if tool.Name == "Shovel" then
		local a = tool:GetAttribute("AppearanceId")
		return a and ("tool:" .. a) or nil
	elseif tool.Name == "CarriedArtifact" then
		local t = tool:GetAttribute("TreasureId")
		return t and ("artifact:" .. t) or nil
	end
	return nil
end

local function destroyModel()
	if model then
		model:Destroy()
	end
	model, modelKey = nil, nil
end

local function build(key: string)
	destroyModel()
	if key:sub(1, 5) == "tool:" then
		local spec = ToolModels.GetSpec(key:sub(6))
		model = Kit.BuildWelded(Kit.Transform(spec.Parts, ViewmodelMath.Scale), "ToolViewmodel")
		isArtifact = false
	else
		local id = key:sub(10)
		local def = Defs.Treasure[id]
		if not def then
			return
		end
		model = Kit.BuildWelded(Kit.Transform(TreasureModels.Specs(id, def), ViewmodelMath.ArtifactScale), "ArtifactViewmodel")
		isArtifact = true
	end
	modelKey = key
	if model then
		model.Parent = Workspace.CurrentCamera
	end
end

-- The real held tool is hidden for the local player only (LocalTransparencyModifier is client-side).
local function setRealToolHidden(tool: Tool, hidden: boolean)
	if (hiddenFor[tool] == true) == hidden then
		return
	end
	hiddenFor[tool] = hidden or nil
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

-- Called by the dig controller on each swing. One normalised animation applied to the whole assembly.
function ViewmodelController.Swing(duration: number)
	swingStart = os.clock()
	swingDuration = math.max(duration, 0.1)
end

local function update()
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local tool = heldTool()
	local show = CameraController.IsActive() and humanoid ~= nil and humanoid.Health > 0 and tool ~= nil

	if tool and not show then
		setRealToolHidden(tool, false)
	end
	if not show or not tool then
		if model then
			destroyModel()
		end
		return
	end
	setRealToolHidden(tool, true)

	local key = keyFor(tool)
	if not key then
		destroyModel()
		return
	end
	if key ~= modelKey or not model or model.Parent == nil then
		build(key)
	end
	if not model then
		return
	end
	local cam = Workspace.CurrentCamera
	if isArtifact then
		model:PivotTo(cam.CFrame * ViewmodelMath.ArtifactRest)
	else
		local t = (os.clock() - swingStart) / swingDuration
		model:PivotTo(cam.CFrame * ViewmodelMath.Swing(t) * ViewmodelMath.Rest())
	end
end

function ViewmodelController.Init()
	-- after the camera has been placed for this frame
	RunService:BindToRenderStep("DigViewmodel", Enum.RenderPriority.Camera.Value + 3, update)
	player.CharacterRemoving:Connect(function()
		destroyModel()
		table.clear(hiddenFor)
	end)
end

return ViewmodelController
