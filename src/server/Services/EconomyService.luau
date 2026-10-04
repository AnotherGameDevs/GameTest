-- Selling, buying, and the return-to-camp convenience. All prices and ownership checks are server-side.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local StateService = require(script.Parent.StateService)
local EquipmentService = require(script.Parent.EquipmentService)
local WorldBuilder = require(script.Parent.WorldBuilder)
local RateLimiter = require(script.Parent.RateLimiter)
local AnalyticsService = require(script.Parent.AnalyticsService)

local EconomyService = {}

local soldRemote = Remotes.Get("Sold")
local notifyRemote = Remotes.Get("Notify")
local returnRemote = Remotes.Get("ReturnResult")
local lastSell: { [Player]: number } = {}
local lastReturn: { [Player]: number } = {}

function EconomyService.SellAll(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	local count, value = InventoryService.TakeAll(player)
	if count <= 0 then
		return
	end
	data.Cash += value
	data.Stats.CashEarned += value
	DataService.MarkDirty(player)
	StateService.Push(player)
	soldRemote:FireClient(player, value, count)
	AnalyticsService.Log(player, "Sell", { value = value, count = count })
end

local function inSellZone(player: Player): boolean
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	local d = hrp.Position - WorldBuilder.SellZoneCenter
	return Vector3.new(d.X, 0, d.Z).Magnitude <= Config.Camp.SellZoneRadius and math.abs(d.Y) < 10
end

local function purchase(player: Player, kind: any, id: any)
	if type(kind) ~= "string" or type(id) ~= "string" then
		return
	end
	if not RateLimiter.Check(player, "RequestPurchase") then
		return
	end
	local data = DataService.Get(player)
	if not data then
		return
	end
	local def, owned
	if kind == "Tool" then
		def, owned = Defs.Tools[id], data.OwnedTools
	elseif kind == "Backpack" then
		def, owned = Defs.Backpacks[id], data.OwnedBackpacks
	end
	if not def or def.Price <= 0 then
		return
	end
	if owned[id] then
		notifyRemote:FireClient(player, "You already own that.", "Info")
		return
	end
	if (data.Reputation or 0) < def.RequiredReputation then
		notifyRemote:FireClient(player, "Not enough Reputation.", "Danger")
		return
	end
	if data.Cash < def.Price then
		notifyRemote:FireClient(player, "Not enough Cash!", "Danger")
		return
	end

	data.Cash -= def.Price
	owned[id] = true
	if kind == "Tool" then
		data.Equipment.ToolId = id
	else
		data.Equipment.BackpackId = id
	end
	DataService.MarkDirty(player)
	StateService.Push(player)
	if kind == "Tool" then
		EquipmentService.Refresh(player)
	end
	notifyRemote:FireClient(player, ("Bought %s!"):format(def.DisplayName), "Good")
	AnalyticsService.Log(player, "Purchase", { kind = kind, id = id, price = def.Price })
end

local function returnToCamp(player: Player)
	if not Config.ReturnToCamp.Enabled then
		return
	end
	if not RateLimiter.Check(player, "ReturnToCamp") then
		returnRemote:FireClient(player, false, 1)
		return
	end
	local now = os.clock()
	local wait = Config.ReturnToCamp.Cooldown - (now - (lastReturn[player] or -1e9))
	if wait > 0 then
		returnRemote:FireClient(player, false, wait)
		return
	end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp or not humanoid or humanoid.Health <= 0 then
		notifyRemote:FireClient(player, "Can't return to camp right now.", "Danger")
		return
	end
	lastReturn[player] = now
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.CFrame = WorldBuilder.SpawnCFrame
	returnRemote:FireClient(player, true, Config.ReturnToCamp.Cooldown)
end

function EconomyService.Init()
	Remotes.Get("RequestPurchase").OnServerEvent:Connect(purchase)
	Remotes.Get("ReturnToCamp").OnServerEvent:Connect(returnToCamp)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		if not Config.Backpack.AutoSellEnabled then
			return
		end
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			if now - (lastSell[player] or 0) >= Config.Backpack.SellCooldown and inSellZone(player) then
				local data = DataService.Get(player)
				if data and InventoryService.Count(data) > 0 then
					lastSell[player] = now
					EconomyService.SellAll(player)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(p)
		lastSell[p] = nil
		lastReturn[p] = nil
	end)
end

return EconomyService
