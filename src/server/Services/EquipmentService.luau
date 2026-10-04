-- Gives each player the shovel their profile says they own/equipped, built from ToolDefinitions.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Defs = require(ReplicatedStorage.Shared.Defs)
local Appearances = require(ReplicatedStorage.Shared.Appearances)
local ToolModels = require(ReplicatedStorage.Shared.ToolModels)
local CarryRegistry = require(script.Parent.CarryRegistry)
local DataService = require(script.Parent.DataService)

local EquipmentService = {}

local function buildShovel(data): Tool
	local def = Defs.Tools[data.Equipment.ToolId]
	local skin = data.EquippedCosmetics and data.EquippedCosmetics.ToolSkin
	-- appearance is resolved separately from stats: a skin can change the model but never the numbers
	local tool = ToolModels.BuildTool(Appearances.Resolve(def, skin))
	tool.ToolTip = def.DisplayName
	tool:SetAttribute("ToolId", data.Equipment.ToolId)
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
	if CarryRegistry.IsCarrying(player) then
		return -- the shovel stays stowed while carrying; it is rebuilt and re-equipped on place/deposit
	end
	local tool = buildShovel(data)
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
				if child:IsA("Tool") and child.Name == "Shovel" and child.Parent == player:FindFirstChild("Backpack")
					and not CarryRegistry.IsCarrying(player) then
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
