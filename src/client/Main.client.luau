-- DIG & RUN! client entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Controllers = script.Parent:WaitForChild("Controllers")
local State = require(Controllers.State)
local UI = require(Controllers.UIController)
local Camera = require(Controllers.CameraController)
local Effects = require(Controllers.EffectsController)
local Dig = require(Controllers.DigController)
local Interaction = require(Controllers.InteractionController)

State.Init()
UI.Init()
Camera.Init()
Effects.Init()
Dig.Init()
Interaction.Init()

-- Ask for state until the server answers (data may still be loading).
task.spawn(function()
	local tries = 0
	while not State.Loaded and tries < 20 do
		Remotes.Get("ClientReady"):FireServer()
		tries += 1
		task.wait(1.5)
	end
end)
