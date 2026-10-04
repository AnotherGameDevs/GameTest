-- Runs the mine elevator built by WorldElevator. Server-authoritative: players only press prompts; the server picks the
-- stop, drives the servo, queues a single pending request, and keeps a watchdog so the car can never get stuck.
-- Allowed while carrying an important artifact (it is the way out). Stops: SURFACE, SOIL, CLAY, STONE, RUINS.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldElevator = require(script.Parent.WorldElevator)

local ElevatorService = {}

local DWELL = 1.0 -- seconds the car waits at a stop before serving a queued request
local ARRIVE = 0.3 -- studs from the target counted as arrived
local WATCHDOG = 25 -- seconds before a trip is declared stuck and the car is reset

local car: Part?
local lift: PrismaticConstraint?
local trackY = 0
local current = 1
local target = 1
local moving = false
local pending: number? = nil
local arrivedAt = 0
local startedAt = 0
local connections: { RBXScriptConnection } = {}
local heartbeat: RBXScriptConnection? = nil

local function positionFor(stop: number): number
	return (WorldElevator.StopTops[stop] - WorldElevator.CarThickness / 2) - trackY
end

local function setTarget(stop: number)
	if not lift then
		return
	end
	target = stop
	moving = true
	startedAt = os.clock()
	lift.TargetPosition = positionFor(stop)
end

-- Requests a stop. If the car is busy the LAST request is remembered and served after it arrives.
function ElevatorService.Request(stop: number)
	if stop < 1 or stop > #WorldElevator.StopTops then
		return
	end
	if moving then
		pending = stop
		return
	end
	if stop ~= current then
		setTarget(stop)
	end
end

local function playerNear(player: Player, instance: Instance, maxDist: number): boolean
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then
		return false
	end
	local pos = instance:IsA("BasePart") and instance.Position or (instance.Parent :: BasePart).Position
	return ((hrp :: BasePart).Position - pos).Magnitude <= maxDist
end

local function onPrompt(prompt: ProximityPrompt, player: Player)
	-- Prompt.Triggered is already range-checked by Roblox, but verify on the server as well.
	if not playerNear(player, prompt, prompt.MaxActivationDistance + 4) then
		return
	end
	local kind = prompt:GetAttribute("Kind")
	if kind == "Call" then
		ElevatorService.Request(tonumber(prompt:GetAttribute("StopIndex")) or 1)
	elseif kind == "Surface" then
		ElevatorService.Request(1)
	elseif kind == "Up" then
		ElevatorService.Request(math.max((moving and target or current) - 1, 1))
	elseif kind == "Down" then
		ElevatorService.Request(math.min((moving and target or current) + 1, #WorldElevator.StopTops))
	end
end

-- Finds the elevator in the freshly built world and (re)binds to it. Safe to call again after the world is rebuilt.
function ElevatorService.Bind()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
	car, lift = nil, nil
	moving, pending, current, target = false, nil, 1, 1

	local world = Workspace:FindFirstChild("World")
	local folder = world and world:FindFirstChild("Elevator")
	if not folder then
		return
	end
	car = folder:FindFirstChild("Car") :: Part?
	lift = folder:FindFirstChild("Lift", true) :: PrismaticConstraint?
	trackY = folder:GetAttribute("TrackY") or 0
	if not car or not lift then
		warn("[ElevatorService] elevator parts missing")
		return
	end
	car:SetNetworkOwner(nil) -- the server drives the car; clients only ride it

	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			table.insert(connections, d.Triggered:Connect(function(player)
				onPrompt(d, player)
			end))
		end
	end

	heartbeat = RunService.Heartbeat:Connect(function()
		if not car or not lift then
			return
		end
		if moving then
			local arrived = math.abs(lift.CurrentPosition - positionFor(target)) < ARRIVE
			if arrived then
				moving = false
				current = target
				arrivedAt = os.clock()
			elseif os.clock() - startedAt > WATCHDOG then
				-- stuck: put the car exactly at the target and carry on
				warn("[ElevatorService] trip timed out; resetting car")
				local cf = car.CFrame
				car.Anchored = true
				car.CFrame = CFrame.new(cf.X, WorldElevator.StopTops[target] - WorldElevator.CarThickness / 2, cf.Z)
				car.Anchored = false
				moving = false
				current = target
				arrivedAt = os.clock()
			end
		elseif pending and os.clock() - arrivedAt >= DWELL then
			local nextStop = pending
			pending = nil
			if nextStop ~= current then
				setTarget(nextStop)
			end
		end
	end)
end

-- Used by the mine reset AFTER everyone has been evacuated: cancels any trip/queue and puts the car at the surface stop,
-- exactly where a fresh elevator starts, so it is safe and usable the moment the new mine opens.
function ElevatorService.ResetToSurface()
	pending = nil
	if not car or not lift then
		return
	end
	local cf = car.CFrame
	car.Anchored = true
	car.AssemblyLinearVelocity = Vector3.zero
	car.CFrame = CFrame.new(cf.X, WorldElevator.StopTops[1] - WorldElevator.CarThickness / 2, cf.Z)
	lift.TargetPosition = positionFor(1)
	car.Anchored = false
	moving = false
	current, target = 1, 1
	arrivedAt = os.clock()
end

function ElevatorService.Init()
	ElevatorService.Bind()
end

return ElevatorService
