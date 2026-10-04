-- Dynamite throwing input: G on desktop, a THROW button on touch. The client only sends an aim direction; the
-- server owns the stick count, cooldown, fuse and blast. Blocked while carrying an artifact or in a menu.
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local State = require(script.Parent.State)
local UI = require(script.Parent.UIController)
local Audio = require(script.Parent.AudioController)

local P = Config.Palette
local TOUCH = UserInputService.TouchEnabled
local ThrowController = {}

local function canThrow(): boolean
	local d = State.Data
	return (d.Consumables and (d.Consumables.dynamite or 0) > 0 or false) and d.Carrying == nil
		and not UI.IsMenuOpen() and UserInputService:GetFocusedTextBox() == nil
end

local function throw()
	if not canThrow() then
		if State.Data.Carrying then
			Audio.Play("Error")
		end
		return
	end
	local look = Workspace.CurrentCamera.CFrame.LookVector
	Remotes.Get("ThrowDynamite"):FireServer(look.X, look.Y, look.Z)
end

function ThrowController.Init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.G then
			throw()
		end
	end)
	if TOUCH then
		local btn = Instance.new("TextButton")
		btn.Name = "ThrowButton"
		btn.Size = UDim2.fromOffset(84, 84)
		btn.AnchorPoint = Vector2.new(1, 1)
		btn.Position = UDim2.new(1, -240, 1, -150)
		btn.BackgroundColor3 = P.Danger
		btn.Text = "THROW"
		btn.TextSize = 18
		btn.Font = Enum.Font.FredokaOne
		btn.TextColor3 = P.Cream
		btn.Visible = false
		btn.Parent = UI.GetGui()
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = btn
		local s = Instance.new("UIStroke")
		s.Thickness = 3
		s.Color = P.Dark
		s.Parent = btn
		btn.Activated:Connect(throw)
		State.Connect(function(d)
			btn.Visible = (d.Consumables and (d.Consumables.dynamite or 0) > 0 or false) and d.Carrying == nil
		end)
	end
end

return ThrowController
