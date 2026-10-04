-- Contextual interactions (ProximityPrompts work on keyboard, gamepad and touch).
--   * Shop prompt opens the shop.
--   * Artifact pickup prompts are only enabled for the discoverer (who owns the claim) and only when not already
--     carrying. The Deposit prompt only appears while carrying. The server validates all of it independently.
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local State = require(script.Parent.State)
local UI = require(script.Parent.UIController)

local player = Players.LocalPlayer
local InteractionController = {}

local pickupPrompts: { [ProximityPrompt]: Model } = {}
local depositPrompt: ProximityPrompt? = nil

local function refreshPrompts()
	local carrying = State.Data.Carrying ~= nil
	for prompt, model in pairs(pickupPrompts) do
		if prompt.Parent == nil then
			pickupPrompts[prompt] = nil
		else
			prompt.Enabled = (not carrying) and model:GetAttribute("OwnerUserId") == player.UserId
		end
	end
	if depositPrompt and depositPrompt.Parent then
		depositPrompt.Enabled = carrying
	end
end

local function watchArtifact(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local function hook()
		local prompt = model:FindFirstChild("PickupPrompt", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			pickupPrompts[prompt] = model
			refreshPrompts()
		end
	end
	hook()
	model.DescendantAdded:Connect(hook)
end

function InteractionController.Init()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "ShopPrompt" then
			UI.OpenShop()
		end
	end)

	State.Connect(refreshPrompts)

	task.spawn(function()
		local folder = Workspace:WaitForChild("Artifacts", 30)
		if folder then
			for _, m in ipairs(folder:GetChildren()) do
				watchArtifact(m)
			end
			folder.ChildAdded:Connect(watchArtifact)
		end
	end)
	task.spawn(function()
		local world = Workspace:WaitForChild("World", 30)
		local found = world and world:WaitForChild("BaseCamp", 30)
		local p = found and found:FindFirstChild("DepositPrompt", true)
		if p and p:IsA("ProximityPrompt") then
			depositPrompt = p
			refreshPrompts()
		end
	end)
end

return InteractionController
