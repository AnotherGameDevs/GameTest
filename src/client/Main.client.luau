-- DIG & RUN! client entry point.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Controllers = script.Parent:WaitForChild("Controllers")
local State = require(Controllers.State)
local UI = require(Controllers.UIController)
local Camera = require(Controllers.CameraController)
local Effects = require(Controllers.EffectsController)
local ToolFxController = require(Controllers.ToolFxController)
local InputMode = require(Controllers.InputMode)
local Settings = require(Controllers.Settings)
local Viewmodel = require(Controllers.ViewmodelController)
local Dig = require(Controllers.DigController)
local Interaction = require(Controllers.InteractionController)
local Throw = require(Controllers.ThrowController)
local Guide = require(Controllers.GuideController)
local CampShelf = require(Controllers.CampShelf)
local Relic = require(Controllers.RelicController)
local DevPanel = require(Controllers.DevPanel)

State.Init()
InputMode.Init()
State.Connect(function(d)
	Settings.Load(d.Settings) -- adopt saved settings once
end)
UI.Init()
Relic.Build(UI.GetGui())
Relic.Init()
Camera.Init()
Viewmodel.Init()
Effects.Init()
ToolFxController.Init()
Dig.Init()
Interaction.Init()
Throw.Init()
Guide.Init()
CampShelf.Init()
DevPanel.Init()

-- Ask for state until the server answers (data may still be loading).
task.spawn(function()
	local tries = 0
	while not State.Loaded and tries < 20 do
		Remotes.Get("ClientReady"):FireServer()
		tries += 1
		task.wait(1.5)
	end
end)
