-- The mine reset ("Fresh Dig"), docs/MINE_RESET.md. Extends the earlier refresh; there is exactly one reset system.
-- The pure state machine is MineLifecycle: Active -> Warning -> Evacuating -> Regenerating -> Active. This service feeds it
-- the clock, depletion and player count, and performs the side effects of each transition:
--   Warn        publish the countdown (Workspace attributes, so late joiners get state + remaining time automatically)
--   Evacuate    stop accepting mining / pickups / throws (MineState), recover artifacts to the recovery area, move players out
--   Regenerate  rebuild the mine from a FRESH loot seed, put the elevator back at the surface, bump the generation
-- Nothing a client sends can start, delay or repeat a reset. Players can not reset the mine for fresh loot: a reset only follows
-- the schedule / depletion policy, never before MinLifetime, and only one can be in flight.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MineLifecycle = require(script.Parent.MineLifecycle)
local MineState = require(script.Parent.MineState)
local SiteService = require(script.Parent.SiteService)
local ArtifactService = require(script.Parent.ArtifactService)
local ElevatorService = require(script.Parent.ElevatorService)
local RelicService = require(script.Parent.RelicService)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local WorldBuilder = require(script.Parent.WorldBuilder)

local MineShiftService = {}

local notifyRemote = Remotes.Get("Notify")
local lifecycle = MineLifecycle.new(Config.Reset, os.clock())
local jobRunning = false
local lastPublished = ""

local function bestToolTier(): number
	local best = 1
	for _, player in ipairs(Players:GetPlayers()) do
		local data = DataService.Get(player)
		local tool = data and Defs.Tools[data.Equipment.ToolId]
		if tool and tool.Tier > best then
			best = tool.Tier
		end
	end
	return best
end

local function serverTime(fromClock: number): number
	return Workspace:GetServerTimeNow() + (fromClock - os.clock())
end

local function publish(dugFraction: number)
	local state = lifecycle:State()
	MineState.Set(state, SiteService.Generation())
	local scheduled = lifecycle:SecondsToScheduled()
	local endsAt = (state == "Warning" or state == "Evacuating") and serverTime(lifecycle:EndsAt()) or 0
	local resetAt = scheduled and (Workspace:GetServerTimeNow() + scheduled) or 0
	-- only touch the replicated attributes when something visible changed (state, generation, reason, whole-percent dug)
	local holding = lifecycle:IsHolding(os.clock())
	local key = ("%s|%d|%s|%d|%d|%s"):format(state, SiteService.Generation(), lifecycle:Reason() or "", math.floor(dugFraction * 100), math.floor(resetAt / 5), tostring(holding))
	if key == lastPublished then
		return
	end
	lastPublished = key
	MineState.Publish({ EndsAt = endsAt, ResetAt = resetAt, Reason = lifecycle:Reason(), DugPercent = math.floor(dugFraction * 100), Hold = holding })
end

local function tellEveryone(text: string, kind: string)
	for _, player in ipairs(Players:GetPlayers()) do
		notifyRemote:FireClient(player, text, kind)
	end
end

-- Server SAFETY evacuation of everyone still inside the excavation bounds. This is not a shortcut: it does not teleport
-- artifacts (those are handled by RecoverForReset), sells nothing, and puts players beside the recovery area.
local function evacuatePlayers(): number
	local moved = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp and ArtifactService.IsInMine(hrp.Position) then
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.CFrame = WorldBuilder.EvacCFrame
			notifyRemote:FireClient(player, "You were moved out of the mine for the reset. Nothing was sold or deposited.", "Info")
			moved += 1
		end
	end
	return moved
end

-- The Evacuating -> Regenerating -> Active job. Runs once per reset; `jobRunning` makes overlapping jobs impossible.
local function runReset()
	if jobRunning then
		return
	end
	jobRunning = true
	local ok, err = pcall(function()
		publish(0)
		-- an active contested relic expires with NO reward and is never moved into camp (checked before anyone is evacuated)
		RelicService.ExpireForReset()
		ArtifactService.RecoverForReset()
		evacuatePlayers()
		task.wait(Config.Reset.EvacuateSeconds)
		evacuatePlayers() -- anyone who slipped back in during the pause
		lifecycle:BeginRegeneration()
		publish(0)
		SiteService.Generate() -- fresh loot seed, new generation, old cells / remnants / unclaimed loot are gone
		ElevatorService.ResetToSurface()
	end)
	if not ok then
		warn("[MineShiftService] reset failed: " .. tostring(err))
		-- never leave the mine stuck: make sure a mine exists and the state machine reaches Active
		if lifecycle:State() == "Evacuating" then
			lifecycle:BeginRegeneration()
		end
		if lifecycle:State() == "Regenerating" and SiteService.Generation() == lifecycle:Generation() then
			pcall(SiteService.Generate)
		end
	end
	lifecycle:FinishRegeneration(os.clock())
	lastPublished = ""
	publish(0)
	for _, player in ipairs(Players:GetPlayers()) do
		StateService.Push(player)
	end
	tellEveryone("The mine has been reset. New treasure is buried - the elevator is ready.", "Good")
	jobRunning = false
end

-- Developer test mode only (DevService checks access first): starts the SAME reset path early, with an optional shorter countdown.
-- Returns (true) or (false, reason). Refuses if a reset is already in flight, so it cannot stack or repeat.
function MineShiftService.RequestReset(warningSeconds: number?): (boolean, string?)
	if jobRunning or lifecycle:State() ~= "Active" then
		return false, "a reset is already in progress"
	end
	if not lifecycle:RequestManual(os.clock(), warningSeconds) then
		return false, "the mine is not in a state that can reset"
	end
	tellEveryone(("TEST: the mine resets in %d seconds. Leave through the ELEVATOR - it is the way out."):format(math.floor(math.max(warningSeconds or Config.Reset.WarningSeconds, 1))), "Danger")
	publish(0)
	return true
end

function MineShiftService.State(): string
	return lifecycle:State()
end

function MineShiftService.Init()
	MineState.Set("Active", SiteService.Generation())
	publish(0)
	if not Config.Reset.Enabled then
		return
	end
	task.spawn(function()
		local warned30 = false
		local holdTold = false
		while true do
			task.wait(Config.Reset.CheckInterval)
			local dep = SiteService.Depletion(bestToolTier())
			local event = lifecycle:Update(os.clock(), dep.Diggable, #Players:GetPlayers(), RelicService.IsActive())
			if event == "Warn" then
				warned30 = false
				tellEveryone(("The mine resets in %d seconds. Leave through the ELEVATOR - it is the way out. Carry artifacts out yourself."):format(Config.Reset.WarningSeconds), "Danger")
			elseif event == "Evacuate" then
				task.spawn(runReset)
			elseif lifecycle:State() == "Warning" and not warned30 and lifecycle:EndsAt() - os.clock() <= 30 then
				warned30 = true
				tellEveryone("30 seconds until the mine resets - head for the ELEVATOR.", "Danger")
			end
			if lifecycle:IsHolding(os.clock()) and not holdTold then
				holdTold = true
				tellEveryone(("The mine reset is waiting for the contested relic (at most %d s), then it expires."):format(Config.Reset.RelicHoldSeconds), "Danger")
			elseif lifecycle:State() ~= "Warning" then
				holdTold = false
			end
			publish(dep.Diggable)
		end
	end)
end

return MineShiftService
