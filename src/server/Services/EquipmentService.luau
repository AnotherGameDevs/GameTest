-- Gives each player the shovel their profile says they own/equipped, built from ToolDefinitions.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Defs = require(ReplicatedStorage.Shared.Defs)
local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)

local EquipmentService = {}

local function buildShovel(toolId: string): Tool
	local def = Defs.Tools[toolId]
	local s = def.Scale
	local P = Config.Palette

	local tool = Instance.new("Tool")
	tool.Name = "Shovel"
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool.RequiresHandle = true
	tool.ToolTip = def.DisplayName
	tool:SetAttribute("ToolId", toolId)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 4.2 * s, 0.5)
	handle.Color = P.Dark
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local function add(name: string, size: Vector3, offset: Vector3, color: Color3)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		p.Massless = true
		p.Parent = tool
		local w = Instance.new("Weld")
		w.Part0 = handle
		w.Part1 = p
		w.C0 = CFrame.new(offset)
		w.Parent = p
	end
	add("Blade", Vector3.new(1.8 * s, 1.7 * s, 0.3 * s), Vector3.new(0, 2.5 * s, 0), def.Color)
	add("Grip", Vector3.new(1.5 * s, 0.4, 0.4), Vector3.new(0, -2.1 * s, 0), P.Dark)
	if def.DigRadius > 0 then
		add("Spike", Vector3.new(0.5 * s, 0.9 * s, 0.4 * s), Vector3.new(0, 3.7 * s, 0), P.Gold)
	end

	tool.Grip = CFrame.new(0, -1.0 * s, 0)
	return tool
end

local function clearTools(player: Player)
	for _, container in ipairs({ player:FindFirstChild("Backpack"), player.Character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child.Name == "Shovel" then
					child:Destroy()
				end
			end
		end
	end
end

function EquipmentService.Refresh(player: Player)
	local data = DataService.Get(player)
	local character = player.Character
	if not data or not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	clearTools(player)
	local tool = buildShovel(data.Equipment.ToolId)
	tool.Parent = player:WaitForChild("Backpack")
	humanoid:EquipTool(tool)
end

function EquipmentService.Init()
	local function onCharacter(player: Player, character: Model)
		-- Wait for data, then give the shovel.
		task.spawn(function()
			local t = os.clock()
			while not DataService.Get(player) and os.clock() - t < 30 and player.Parent do
				task.wait(0.1)
			end
			character:WaitForChild("Humanoid")
			character:WaitForChild("HumanoidRootPart")
			task.wait(0.1)
			if player.Character == character then
				EquipmentService.Refresh(player)
			end
			-- Keep the shovel in hand: if it ever gets unequipped, put it back next frame.
			character.ChildRemoved:Connect(function(child)
				if child:IsA("Tool") and child.Name == "Shovel" and child.Parent == player:FindFirstChild("Backpack") then
					task.defer(function()
						local h = character:FindFirstChildOfClass("Humanoid")
						if h and h.Health > 0 and child.Parent == player.Backpack then
							h:EquipTool(child)
						end
					end)
				end
			end)
		end)
	end

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
end

return EquipmentService
