-- Contextual interactions (ProximityPrompts work on keyboard, gamepad and touch).
local ProximityPromptService = game:GetService("ProximityPromptService")
local UI = require(script.Parent.UIController)

local InteractionController = {}

function InteractionController.Init()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "ShopPrompt" then
			UI.OpenShop()
		end
	end)
end

return InteractionController
