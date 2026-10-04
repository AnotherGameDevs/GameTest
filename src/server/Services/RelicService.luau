-- The contested server relic (docs/RELIC_PVP.md): a single, explicit PvP carry-home event.
--   Discovery  -> Announce (name + discoverer), mark the relic. Never reveals an undiscovered relic.
--   Pickup     -> anyone eligible; the carrier is visibly holding it and is under every personal-artifact restriction
--                 (no mining, no tool switching, no To Camp, no dynamite) but may walk, jump, use the elevator, or place it down.
--   Combat     -> a dedicated action (RelicAttack): outside the camp safe zone anyone not carrying may strike the carrier; the
--                 carrier may shove players who are attacking. A relic-control meter, NOT mining tool stats, decides when it drops.
--   Drop       -> unclaimed, same event identity; ownership changes only through a validated pickup.
--   Deposit    -> only the carrier, only at the receiving station, exactly once; the safe zone gives a short grace, never a bank.
--   Reset      -> an active event gets a bounded hold, then EXPIRES with no reward before the safety evacuation.
-- Everything is validated on the server; the client only sends "I pressed the action".
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TreasureModels = require(ReplicatedStorage.Shared.TreasureModels)
local CollectionSpec = require(ReplicatedStorage.Shared.CollectionSpec)
local RelicRules = require(ReplicatedStorage.Shared.RelicRules)

local RelicEvent = require(script.Parent.RelicEvent)
local CarryRegistry = require(script.Parent.CarryRegistry)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local EquipmentService = require(script.Parent.EquipmentService)
local ArtifactService = require(script.Parent.ArtifactService)
local WorldBuilder = require(script.Parent.WorldBuilder)
local MineState = require(script.Parent.MineState)
local RateLimiter = require(script.Parent.RateLimiter)
local AnalyticsService = require(script.Parent.AnalyticsService)

local RelicService = {}

local R = Config.Relic
local notifyRemote = Remotes.Get("Notify")
local fxRemote = Remotes.Get("RelicFx")
local depositedRemote = Remotes.Get("ArtifactDeposited")
local setRemote = Remotes.Get("SetCompleted")

local event: any = nil -- the current / most recent RelicEvent (terminal ones stay only so stale requests are rejected)
local folder: Folder
local worldModel: Model? = nil
local carryTool: Tool? = nil
local lastAttack: { [number]: number } = {} -- userId -> last strike (cooldown)
local engagedAt: { [number]: number } = {} -- userId -> last time they struck at / reached for the carrier (shove eligibility)
local lastShove = -1e9
local lastSafe: { [number]: Vector3 } = {}
local lastAnnounce = -1e9
local warnedGrace = false

local function say(player: Player, text: string, kind: string?)
	if player.Parent then
		notifyRemote:FireClient(player, text, kind or "Info")
	end
end

local function announce(text: string, kind: string)
	for _, p in ipairs(Players:GetPlayers()) do
		notifyRemote:FireClient(p, text, kind)
	end
end

local function nameOf(userId: number?): string
	local p = userId and Players:GetPlayerByUserId(userId)
	return p and p.DisplayName or "someone"
end

local function relicName(): string
	return event and Defs.Treasure[event.TreasureId].Name or "Relic"
end

-- Replicated state (Workspace attributes): ONLY facts about an already-discovered relic. Undiscovered relics have no entry.
local function publish()
	local active = event and event:IsActive()
	Workspace:SetAttribute("RelicState", active and event.State or "None")
	Workspace:SetAttribute("RelicName", active and relicName() or "")
	Workspace:SetAttribute("RelicDiscoverer", active and nameOf(event.DiscovererId) or "")
	Workspace:SetAttribute("RelicCarrierId", active and event.CarrierId or 0)
	Workspace:SetAttribute("RelicControl", active and event.Control or 0)
	Workspace:SetAttribute("RelicMaxControl", R.MaxControl)
	Workspace:SetAttribute("RelicId", active and event.Id or "")
end

local function character(player: Player?)
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if hrp and hum and hum.Health > 0 then
		return char, hrp, hum
	end
	return nil, nil, nil
end

local function carrierPlayer(): Player?
	return event and event.CarrierId and Players:GetPlayerByUserId(event.CarrierId) or nil
end

-- Spot selection -------------------------------------------------------------------------------------------------------------
local function supportedSpot(candidates: { Vector3 }, size: Vector3, accept: ((Vector3) -> boolean)?): CFrame?
	local rp, op = ArtifactService.QueryParams()
	for _, c in ipairs(candidates) do
		local hit = Workspace:Raycast(c + Vector3.new(0, 1.5, 0), Vector3.new(0, -16, 0), rp)
		-- never rest on the moving elevator car (an anchored relic would be left hanging in mid-air when it moves)
		if hit and hit.Normal.Y > 0.7 and hit.Instance.Name ~= "Car" then
			local center = hit.Position + Vector3.new(0, size.Y / 2 + 0.05, 0)
			if not accept or accept(center) then
				local box = Vector3.new(size.X, math.max(size.Y - 0.4, 0.2), size.Z)
				if #Workspace:GetPartBoundsInBox(CFrame.new(center + Vector3.new(0, 0.15, 0)), box, op) == 0 then
					return CFrame.new(center)
				end
			end
		end
	end
	return nil
end

local function recoveryCFrame(size: Vector3): Vector3
	local p = R.RecoveryPoint
	return Vector3.new(p.X, 0.45 + size.Y / 2 + 0.05, p.Z)
end

-- A drop position that is recoverable: supported, clear, inside the contested area (never the camp safe zone) and on the map.
local function validDrop(center: Vector3): boolean
	if RelicRules.InSafeZone(center.X, center.Y, center.Z) then
		return false
	end
	local ext = Config.World.BoundaryExtent
	return center.Y > R.UnreachableBelowY and math.abs(center.X) < ext and math.abs(center.Z) < ext
end

local function pickDropPosition(origin: Vector3?, size: Vector3): Vector3
	if origin then
		local cf = supportedSpot(ArtifactService.RingAround(origin, Vector3.new(0, 0, -1), 2.5), size, validDrop)
		if cf then
			return cf.Position
		end
	end
	return recoveryCFrame(size)
end

-- World model ----------------------------------------------------------------------------------------------------------------
local function destroyModel()
	if worldModel then
		worldModel:Destroy()
		worldModel = nil
	end
end

local function spawnModel()
	destroyModel()
	if not event or not (event.State == "Discovered" or event.State == "Dropped") then
		return
	end
	local def = Defs.Treasure[event.TreasureId]
	local id = event.Id
	local model = TreasureModels.BuildAny(event.TreasureId, def)
	model:PivotTo(CFrame.new(event.Position))
	model:SetAttribute("RelicId", id)
	local root = model.PrimaryPart :: BasePart
	local hl = Instance.new("Highlight")
	hl.FillColor = Defs.Rarity[def.Rarity].Color
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.FillTransparency = 0.92
	hl.DepthMode = Enum.HighlightDepthMode.Occluded -- never visible through walls
	hl.Parent = model
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RelicPickupPrompt"
	prompt.ObjectText = def.Name
	prompt.ActionText = "Take the relic (contested!)"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = R.PickupReach - 2
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(player)
		RelicService.Pickup(player, id)
	end)
	model.Parent = folder
	worldModel = model
end

local function removeCarryTool(player: Player?)
	if carryTool then
		carryTool:Destroy()
		carryTool = nil
	end
	CarryRegistry.SetRelicCarrier(nil)
	if player and player.Parent then
		StateService.Push(player)
		task.spawn(EquipmentService.Refresh, player) -- the shovel comes back
	end
end

-- Discovery -------------------------------------------------------------------------------------------------------------------
-- Called by LootService when the block holding a relic breaks. Returns true if a contested event started; false means the caller
-- must fall back (an event is already active - only one contested relic per server).
function RelicService.Discover(player: Player, treasureId: string, position: Vector3): boolean
	local def = Defs.Treasure[treasureId]
	if not R.Enabled or not def or not def.Relic or not DataService.Get(player) then
		return false
	end
	if (event and event:IsActive()) or not MineState.Accepting() then
		return false -- one contested relic per server; and never start one while the mine is shutting down for a reset
	end
	local size = ArtifactService.ArtifactSize(treasureId)
	local cf = supportedSpot({ position, position + Vector3.new(1, 0, 0), position - Vector3.new(1, 0, 0),
		position + Vector3.new(0, 0, 1), position - Vector3.new(0, 0, 1) }, size)
	local spot = cf and cf.Position or (position + Vector3.new(0, size.Y / 2 - 2 + 0.05, 0))
	event = RelicEvent.new(HttpService:GenerateGUID(false), treasureId, def.Value, player.UserId, spot, MineState.Generation(), R, os.clock())
	table.clear(lastAttack)
	table.clear(engagedAt)
	warnedGrace = false
	publish()
	task.delay(Config.Artifacts.SpawnDelay, function()
		if event and event.State == "Discovered" then
			spawnModel()
		end
	end)
	announce(("CONTESTED RELIC! %s uncovered the %s. Carry it to camp. The carrier can be attacked."):format(player.DisplayName, def.Name), "Danger")
	AnalyticsService.Log(player, "RelicDiscovered", { id = event.Id })
	return true
end

-- Everything that must not count as an obstacle: both characters, the relic's own model and carried tool.
local function ignoreFor(a: Player, b: Player): { Instance }
	local out: { Instance } = { folder }
	for _, inst in ipairs({ a.Character, b.Character, carryTool }) do
		if inst then
			table.insert(out, inst)
		end
	end
	return out
end

local function lineOfSight(a: BasePart, b: BasePart, ignore: { Instance }): boolean
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	rp.RespectCanCollide = false
	local from, to = a.Position + Vector3.new(0, 1.2, 0), b.Position + Vector3.new(0, 0.8, 0)
	return Workspace:Raycast(from, to - from, rp) == nil -- anything solid between them (cells, walls, structures) blocks the hit
end


-- Pickup ----------------------------------------------------------------------------------------------------------------------
function RelicService.Pickup(player: Player, relicId: any)
	if type(relicId) ~= "string" or not RateLimiter.Check(player, "RelicPickup") then
		return
	end
	if not event or event.Id ~= relicId or not event:IsActive() or not MineState.Accepting() then
		return -- stale request: a different, finished or expired event
	end
	local char, hrp, hum = character(player)
	if not char or not hrp or not hum then
		return
	end
	if (hrp.Position - event.Position).Magnitude > R.PickupReach then
		return
	end
	-- no taking it through walls (the prompt itself does not require line of sight)
	local root = worldModel and worldModel.PrimaryPart
	if root and not lineOfSight(hrp, root, ignoreFor(player, player)) then
		say(player, "There is something in the way.", "Info")
		return
	end
	if CarryRegistry.IsCarrying(player) then
		say(player, "Put down what you are carrying first.", "Danger")
		return
	end
	local ok, why = event:Pickup(player.UserId, os.clock()) -- atomic: simultaneous pickups: exactly one succeeds
	if not ok then
		if why == "TooSoon" then
			say(player, "You just dropped it - someone else gets a chance first.", "Info")
		end
		return
	end
	destroyModel()
	local tool = ArtifactService.BuildCarryTool({ Id = event.Id, TreasureId = event.TreasureId })
	tool.Name = "CarriedRelic"
	carryTool = tool
	CarryRegistry.SetRelicCarrier(player.UserId)
	tool.Parent = player:FindFirstChildOfClass("Backpack")
	hum:UnequipTools() -- stows the shovel
	hum:EquipTool(tool)
	lastSafe[player.UserId] = hrp.Position
	tool.Unequipped:Connect(function()
		task.defer(function()
			local _, _, h = character(player)
			if h and event and event.State == "Carried" and event.CarrierId == player.UserId and carryTool == tool
				and tool.Parent == player:FindFirstChildOfClass("Backpack") then
				h:EquipTool(tool)
			end
		end)
	end)
	table.clear(engagedAt)
	warnedGrace = false
	publish()
	StateService.Push(player)
	say(player, "You have the relic! Take it to the RECEIVING TABLE at camp. Others can attack you outside the safe zone. [F] shoves attackers.", "Good")
	if os.clock() - lastAnnounce > 2 then
		lastAnnounce = os.clock()
		announce(("%s picked up the %s!"):format(player.DisplayName, relicName()), "Info")
	end
	AnalyticsService.Log(player, "RelicPickedUp", { id = event.Id, n = event.Transfers })
end

-- Dropping ------------------------------------------------------------------------------------------------------------------------
-- Common exit from "Carried": the relic becomes unclaimed at a recoverable spot and the carrier gets the shovel back.
local function dropAt(position: Vector3, text: string?)
	if not event or event.State ~= "Carried" then
		return
	end
	local carrier = carrierPlayer()
	if not event:Drop(position, os.clock()) then
		return
	end
	removeCarryTool(carrier)
	spawnModel()
	publish()
	if text then
		announce(text, "Danger")
	end
end

local function dropFor(player: Player?, why: string)
	if not event or event.State ~= "Carried" then
		return
	end
	local _, hrp = character(player)
	local origin = (hrp and hrp.Position) or (player and lastSafe[player.UserId])
	local size = ArtifactService.ArtifactSize(event.TreasureId)
	local pos = pickDropPosition(origin or lastSafe[event.CarrierId], size)
	local who = player and player.DisplayName or "The carrier"
	dropAt(pos, ("%s dropped the %s (%s). It is up for grabs!"):format(who, relicName(), why))
end

local function returnToRecovery(text: string)
	if not event or not event:IsActive() then
		return
	end
	local size = ArtifactService.ArtifactSize(event.TreasureId)
	local pos = recoveryCFrame(size)
	if event.State == "Carried" then
		dropAt(pos, text)
	else
		event.Position = pos
		spawnModel()
		publish()
		announce(text, "Info")
	end
end

-- Voluntary place-down: only onto a supported, clear, reachable spot (no walls in the way), never in the safe zone.
function RelicService.Place(player: Player)
	if not RateLimiter.Check(player, "RelicPlace") then
		return
	end
	if not event or event.State ~= "Carried" or event.CarrierId ~= player.UserId then
		return
	end
	local _, hrp = character(player)
	if not hrp then
		return
	end
	local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
	local base = hrp.Position
	local size = ArtifactService.ArtifactSize(event.TreasureId)
	local rp = ArtifactService.QueryParams()
	local cf = supportedSpot(ArtifactService.RingAround(base, look, 3.5), size, function(center: Vector3)
		local flat = Vector3.new(center.X - base.X, 0, center.Z - base.Z).Magnitude
		if flat > R.PlaceReach or math.abs(center.Y - base.Y) > 6 or not validDrop(center) then
			return false
		end
		-- no placing through walls: the straight line from the carrier to the spot must be clear
		return Workspace:Raycast(base + Vector3.new(0, 1, 0), (center - base) - Vector3.new(0, 1, 0), rp) == nil
	end)
	if not cf then
		say(player, "No safe spot to put it down here. Find open, flat ground outside the camp.", "Danger")
		return
	end
	dropAt(cf.Position, ("%s put the %s down. Anyone can take it!"):format(player.DisplayName, relicName()))
end

-- Combat ----------------------------------------------------------------------------------------------------------------------
local function pushOnClient(target: Player, from: Vector3, to: Vector3, speed: number, up: number, kind: string)
	-- Knockback is applied ONCE by the target's own client (it owns its character), bounded by RelicRules.ClampKnockback.
	local vx, vy, vz = RelicRules.ClampKnockback(to.X - from.X, to.Z - from.Z, speed, up)
	fxRemote:FireClient(target, "Knock", target.UserId, Vector3.new(vx, vy, vz))
	for _, p in ipairs(Players:GetPlayers()) do
		fxRemote:FireClient(p, kind, target.UserId, to)
	end
end

local function strike(attacker: Player, carrier: Player)
	local _, aHrp = character(attacker)
	local _, cHrp = character(carrier)
	local now = os.clock()
	local aAlive, cAlive = aHrp ~= nil, cHrp ~= nil
	local distance = (aHrp and cHrp) and (aHrp.Position - cHrp.Position).Magnitude or 1e9
	if distance <= R.AttackRange * 1.5 then
		engagedAt[attacker.UserId] = now -- reaching for the carrier makes you a legitimate shove target
	end
	local los = false
	if aHrp and cHrp and distance <= R.AttackRange * 1.5 then
		los = lineOfSight(aHrp, cHrp, ignoreFor(attacker, carrier))
	end
	local ok, why = RelicRules.CheckStrike({
		EventState = event.State, AttackerId = attacker.UserId, CarrierId = event.CarrierId, Distance = distance, LineOfSight = los,
		Now = now, LastAttack = lastAttack[attacker.UserId], ProtectedUntil = event.ProtectedUntil, AttackerAlive = aAlive,
		CarrierAlive = cAlive, AttackerCarrying = CarryRegistry.IsCarrying(attacker),
		AttackerInSafe = aHrp ~= nil and RelicRules.InSafeZone(aHrp.Position.X, aHrp.Position.Y, aHrp.Position.Z),
		CarrierInSafe = cHrp ~= nil and RelicRules.InSafeZone(cHrp.Position.X, cHrp.Position.Y, cHrp.Position.Z),
	})
	if not ok then
		if why == "SafeZone" then
			say(attacker, "The camp is a safe zone.", "Info")
		elseif why == "Blocked" then
			say(attacker, "Something is in the way.", "Info")
		end
		return
	end
	local applied, dropped = event:Hit(attacker.UserId, R.ControlPerHit, now)
	if not applied then
		say(attacker, "The carrier just picked it up - they are protected for a moment.", "Info")
		return -- a rejected hit does not spend the attacker's cooldown
	end
	lastAttack[attacker.UserId] = now
	pushOnClient(carrier, (aHrp :: BasePart).Position, (cHrp :: BasePart).Position, R.StrikeKnockback, 3, "Hit")
	publish()
	if dropped then
		dropFor(carrier, ("%s knocked it loose"):format(attacker.DisplayName))
	end
end

local function shove(carrier: Player)
	local _, cHrp = character(carrier)
	if not cHrp then
		return
	end
	local now = os.clock()
	local best, bestD
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= carrier then
			local _, tHrp = character(p)
			if tHrp then
				local d = (tHrp.Position - cHrp.Position).Magnitude
				if d <= R.ShoveRange and (not bestD or d < bestD) then
					local los = lineOfSight(cHrp, tHrp, ignoreFor(carrier, p))
					local ok = RelicRules.CheckShove({
						EventState = event.State, CarrierId = event.CarrierId, TargetId = p.UserId, Distance = d, LineOfSight = los, Now = now,
						LastShove = lastShove, LastTargetAttack = engagedAt[p.UserId], CarrierAlive = true, TargetAlive = true,
						TargetInSafe = RelicRules.InSafeZone(tHrp.Position.X, tHrp.Position.Y, tHrp.Position.Z),
						CarrierInSafe = RelicRules.InSafeZone(cHrp.Position.X, cHrp.Position.Y, cHrp.Position.Z),
					})
					if ok then
						best, bestD = p, d
					end
				end
			end
		end
	end
	if not best then
		return -- nobody eligible: no cooldown spent
	end
	lastShove = now
	local _, tHrp = character(best)
	pushOnClient(best, cHrp.Position, (tHrp :: BasePart).Position, R.ShoveKnockback, 4, "Shove")
end

local function onAttackRequest(player: Player)
	if not RateLimiter.Check(player, "RelicAttack") then
		return
	end
	if not event or event.State ~= "Carried" then
		return
	end
	if event.CarrierId == player.UserId then
		shove(player)
		return
	end
	local carrier = carrierPlayer()
	if carrier then
		strike(player, carrier)
	end
end

-- Deposit -----------------------------------------------------------------------------------------------------------------------
function RelicService.Deposit(player: Player)
	if not event or event.State ~= "Carried" or event.CarrierId ~= player.UserId then
		return
	end
	local _, hrp = character(player)
	local data = DataService.Get(player)
	if not hrp or not data then
		return
	end
	if (hrp.Position - WorldBuilder.ReceivingCenter).Magnitude > Config.Artifacts.DepositReach then
		return
	end
	local ok, value = event:Deposit(player.UserId) -- exactly once; a second request (or another player's) fails here
	if not ok then
		return
	end
	local def = Defs.Treasure[event.TreasureId]
	data.Cash += value
	data.Stats.CashEarned += value
	data.Stats.TreasureFound += 1
	data.Stats.RelicsExtracted += 1
	local _, completed = CollectionSpec.Register(data.Collection, event.TreasureId, os.time())
	if completed then
		setRemote:FireClient(player, completed, Defs.LayerName(completed))
	end
	DataService.MarkDirty(player)
	removeCarryTool(player)
	depositedRemote:FireClient(player, def.Name, value, true)
	ArtifactService.ShowOnTable(event.TreasureId)
	destroyModel()
	publish() -- the event is over: every indicator is removed
	announce(("%s secured the %s!"):format(player.DisplayName, def.Name), "Good")
	AnalyticsService.Log(player, "RelicSecured", { id = event.Id, value = value })
end

-- Reset ----------------------------------------------------------------------------------------------------------------------------
function RelicService.IsActive(): boolean
	return event ~= nil and event:IsActive()
end

-- Called once before the safety evacuation. Ends the event with NO reward and removes everything; nothing is moved into camp.
function RelicService.ExpireForReset(): boolean
	if not event or not event:IsActive() then
		return false
	end
	local carrier = carrierPlayer()
	local name = relicName()
	event:Expire()
	destroyModel()
	if carrier then
		removeCarryTool(carrier)
	else
		CarryRegistry.SetRelicCarrier(nil)
	end
	publish()
	announce(("The contested %s expired with the mine reset. No reward."):format(name), "Danger")
	return true
end

-- Wiring ------------------------------------------------------------------------------------------------------------------------
function RelicService.Init()
	folder = Workspace:FindFirstChild("RelicEvent") or Instance.new("Folder")
	folder.Name = "RelicEvent"
	folder.Parent = Workspace
	publish()

	Remotes.Get("RelicAttack").OnServerEvent:Connect(onAttackRequest)
	Remotes.Get("PlaceArtifact").OnServerEvent:Connect(function(player)
		if CarryRegistry.CarriesRelic(player) then
			RelicService.Place(player)
		end
	end)
	local world = Workspace:FindFirstChild("World")
	local prompt = world and world:FindFirstChild("DepositPrompt", true)
	if prompt then
		prompt.Triggered:Connect(RelicService.Deposit)
	else
		warn("[RelicService] Deposit prompt not found.")
	end

	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			if event and event.State == "Carried" and event.CarrierId == player.UserId then
				dropFor(player, "reset character")
			end
		end)
		local function onChar(char: Model)
			local hum = char:WaitForChild("Humanoid", 10)
			if hum then
				(hum :: Humanoid).Died:Connect(function()
					if event and event.State == "Carried" and event.CarrierId == player.UserId then
						dropFor(player, "defeated")
					end
				end)
			end
		end
		player.CharacterAdded:Connect(onChar)
		if player.Character then
			task.spawn(onChar, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		if event and event.State == "Carried" and event.CarrierId == player.UserId then
			dropFor(player, "disconnected") -- never banked, never kept exclusively
		end
		lastSafe[player.UserId] = nil
		lastAttack[player.UserId] = nil
		engagedAt[player.UserId] = nil
	end)

	-- Watcher: safe-zone grace, last safe position, unreachable relics.
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		if not event or not event:IsActive() then
			return
		end
		local now = os.clock()
		if event.State == "Carried" then
			local carrier = carrierPlayer()
			local _, hrp, hum = character(carrier)
			if hrp and hum then
				if hum.FloorMaterial ~= Enum.Material.Air and not RelicRules.InSafeZone(hrp.Position.X, hrp.Position.Y, hrp.Position.Z) then
					lastSafe[event.CarrierId] = hrp.Position
				end
				local inSafe = RelicRules.InSafeZone(hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
				if inSafe and event.SafeSeconds < 1 and not warnedGrace and carrier then
					warnedGrace = true
					say(carrier, ("Deposit the relic at the receiving table within %d seconds!"):format(R.CampGraceSeconds), "Danger")
				end
				if not inSafe then
					warnedGrace = false
				end
				if event:TrackCamp(inSafe, now) then
					warnedGrace = false
					returnToRecovery(("%s did not deposit the %s in time - it returned to the mine entrance."):format(carrier and carrier.DisplayName or "The carrier", relicName()))
				end
			end
		elseif event.State == "Dropped" or event.State == "Discovered" then
			local m = worldModel
			local pos = event.Position
			local lost = (m ~= nil and (not m.Parent or m:GetPivot().Position.Y < R.UnreachableBelowY)) or pos.Y < R.UnreachableBelowY
				or not validDrop(pos) and event.State == "Dropped"
			if lost then
				returnToRecovery(("The %s became unreachable and returned to the mine entrance."):format(relicName()))
			end
		end
	end)
end

return RelicService
