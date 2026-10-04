-- Developer test mode (docs/DEVELOPER_MODE.md). SERVER-authorised: every request re-checks DevAccess from server-side facts (RunService:IsStudio(),
-- game.PlaceId, player.UserId, Config.Dev). The client's panel is only a convenience; a hand-fired remote from an ordinary player is ignored.
--
-- What it does NOT do:
--   * It never writes a profile. Personal actions run on the in-memory TEST OVERLAY (DataService.EnterTestMode), which is never saved; the real
--     profile is parked untouched and restored on exit.
--   * It never bypasses rules. Artifacts are created through the existing ArtifactService / RelicService / InventoryService paths, so pickup, carry,
--     deposit and PvP validation still apply. A reward from a panel-created artifact or relic is paid only into a profile that is itself in test mode.
--   * It cannot touch a public production mine: world actions need a Studio server or a place listed in Config.Dev.TestPlaceIds (plus the player in
--     AllowedUserIds). Both lists are empty by default, so a published server grants nobody anything until you fill them in.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CollectionSpec = require(ReplicatedStorage.Shared.CollectionSpec)

local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local EquipmentService = require(script.Parent.EquipmentService)
local InventoryService = require(script.Parent.InventoryService)
local ArtifactService = require(script.Parent.ArtifactService)
local RelicService = require(script.Parent.RelicService)
local MineShiftService = require(script.Parent.MineShiftService)
local MineState = require(script.Parent.MineState)
local CarryRegistry = require(script.Parent.CarryRegistry)
local WorldBuilder = require(script.Parent.WorldBuilder)
local WorldElevator = require(script.Parent.WorldElevator)
local RateLimiter = require(script.Parent.RateLimiter)
local DevAccess = require(script.Parent.DevAccess)
local DevProfile = require(script.Parent.DevProfile)
local DevScenario = require(script.Parent.DevScenario)

local DevService = {}

local notifyRemote = Remotes.Get("Notify")
local treasureRemote = Remotes.Get("TreasureFound")
local lastAction: { [Player]: number } = {}
local deniedLogged: { [Player]: boolean } = {}

local function accessFor(player: Player)
	return DevAccess.Resolve({
		IsStudio = RunService:IsStudio(),
		PlaceId = game.PlaceId,
		UserId = player.UserId,
		AllowedUserIds = Config.Dev.AllowedUserIds,
		TestPlaceIds = Config.Dev.TestPlaceIds,
	})
end

local function say(player: Player, text: string, kind: string?)
	notifyRemote:FireClient(player, "[TEST] " .. text, kind or "Info")
end

local function frontOf(player: Player, studs: number): Vector3?
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	return (hrp :: BasePart).Position + (hrp :: BasePart).CFrame.LookVector * studs
end

local function relicTreasureId(): string?
	for id, def in pairs(Defs.Treasure) do
		if def.Relic then
			return id
		end
	end
	return nil
end

-- Starts a contested relic event through the existing RelicService state machine (the same call the real discovery makes).
local function startRelic(player: Player, treasureId: string)
	if RelicService.IsActive() then
		say(player, "A relic event is already active on this server.", "Danger")
		return
	end
	local pos = frontOf(player, 6)
	if not pos then
		return
	end
	if not RelicService.Discover(player, treasureId, pos) then
		say(player, "The relic event could not start (mine resetting, or events disabled).", "Danger")
		return
	end
	DevScenario.Mark(RelicService.CurrentId())
	treasureRemote:FireClient(player, { Id = treasureId, Position = pos, Stored = false, Carry = true, Relic = true, IsNew = false })
	say(player, "Relic event started. Its reward is paid only to a player in test mode.", "Good")
end

local actions: { [string]: (Player, any) -> () } = {}

function actions.Enter(player)
	if DataService.EnterTestMode(player) then
		StateService.Push(player)
		say(player, "DEVELOPER TEST MODE ON. Your real profile is parked and will not be changed or saved.", "Good")
	end
end

function actions.Exit(player)
	if CarryRegistry.IsCarrying(player) then
		say(player, "Place or deposit what you are carrying before leaving test mode.", "Danger")
		return
	end
	if DataService.ExitTestMode(player) then
		EquipmentService.Refresh(player)
		StateService.Push(player)
		say(player, "Test mode OFF. Your real profile is restored.", "Good")
	end
end

function actions.UnlockAll(player)
	local data = DataService.Get(player)
	DevProfile.UnlockAllEquipment(data, Defs)
	StateService.Push(player)
	say(player, "All tools and backpacks unlocked (test profile only).", "Good")
end

function actions.Equip(player, arg)
	if arg.Kind == "Tool" and CarryRegistry.IsCarrying(player) then
		say(player, "Place your artifact down before switching tools.", "Danger")
		return
	end
	local data = DataService.Get(player)
	if DevProfile.Equip(data, arg.Kind, arg.Id, Defs) then
		StateService.Push(player)
		if arg.Kind == "Tool" then
			EquipmentService.Refresh(player)
		end
		say(player, "Equipped " .. (arg.Kind == "Tool" and Defs.Tools[arg.Id].DisplayName or Defs.Backpacks[arg.Id].DisplayName) .. ".", "Good")
	end
end

function actions.GrantCash(player, amount)
	local n = DevProfile.GrantCash(DataService.Get(player), amount, Config.Dev.MaxCash)
	StateService.Push(player)
	say(player, ("Granted $%d test cash."):format(n), "Good")
end

function actions.UnlockCollection(player)
	DevProfile.UnlockCollection(DataService.Get(player), CollectionSpec, Defs, os.time(), Config.Collection.DisplaySlots)
	StateService.Push(player)
	say(player, "Collection entries unlocked and shelf filled (test profile only).", "Good")
end

function actions.FreshProfile(player)
	if DataService.FreshTestProfile(player) then
		EquipmentService.Refresh(player)
		StateService.Push(player)
		say(player, "Fresh test profile. Your real profile is untouched.", "Good")
	end
end

-- Inspection only: plays the normal reveal at a point in front of you. Adds nothing to the backpack or collection.
function actions.Reveal(player, treasureId)
	local pos = frontOf(player, 5)
	if pos then
		treasureRemote:FireClient(player, { Id = treasureId, Position = pos, Stored = false, Carry = false, IsNew = false })
	end
end

-- Each artifact goes through the flow that belongs to its kind, exactly as a real find would.
function actions.SpawnArtifact(player, treasureId)
	local def = Defs.Treasure[treasureId]
	local kind = Defs.KindOf(def)
	if not MineState.Accepting() then
		say(player, "The mine is resetting. Try again in a moment.", "Danger")
		return
	end
	if kind == "Relic" then
		startRelic(player, treasureId)
	elseif kind == "Personal" then
		local ok, recId = ArtifactService.Discover(player, treasureId, nil, true)
		if ok then
			DevScenario.Mark(recId)
			local pos = frontOf(player, 5) or Vector3.zero
			treasureRemote:FireClient(player, { Id = treasureId, Position = pos, Stored = false, Carry = true, IsNew = false })
			say(player, "Personal artifact spawned beside you: pick it up and carry it to camp.", "Good")
		else
			say(player, "Could not place the artifact here.", "Danger")
		end
	else
		local data = DataService.Get(player)
		local stored = InventoryService.Add(player, treasureId)
		local isNew = false
		if stored then
			isNew = CollectionSpec.Register(data.Collection, treasureId, os.time())
		end
		treasureRemote:FireClient(player, { Id = treasureId, Position = frontOf(player, 5) or Vector3.zero, Stored = stored, IsNew = isNew })
		StateService.Push(player)
		say(player, stored and "Ordinary artifact added to your test backpack." or "Test backpack is full.", stored and "Good" or "Danger")
	end
end

function actions.StartRelic(player)
	local id = relicTreasureId()
	if not id then
		say(player, "No relic is defined.", "Danger")
		return
	end
	if not MineState.Accepting() then
		say(player, "The mine is resetting. Try again in a moment.", "Danger")
		return
	end
	startRelic(player, id)
end

-- Existing positions only: the camp spawn, and the elevator landing of each layer (the same platforms players use to leave the mine).
function actions.Teleport(player, stop)
	if CarryRegistry.IsCarrying(player) then
		say(player, "You cannot teleport while carrying an artifact (the same rule as Return to Camp).", "Danger")
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local target: Vector3?
	if stop == 1 then
		target = WorldBuilder.SpawnCFrame.Position
	else
		local landing = Workspace:FindFirstChild("Landing" .. (stop - 1), true)
		target = landing and (landing :: BasePart).Position + Vector3.new(0, 4, 0) or nil
	end
	if not target then
		say(player, "That position does not exist in this world.", "Danger")
		return
	end
	(hrp :: BasePart).AssemblyLinearVelocity = Vector3.zero
	;(char :: Model):PivotTo(CFrame.new(target))
	say(player, "Moved to " .. (WorldElevator.StopNames[stop] or "?") .. ".", "Good")
end

function actions.ResetMine(player)
	local ok, why = MineShiftService.RequestReset(Config.Dev.ResetWarningSeconds)
	say(player, ok and "Mine reset requested through the normal reset lifecycle." or ("Reset not started: " .. tostring(why)), ok and "Good" or "Danger")
end

local function handle(player: Player, action: any, arg: any)
	if not RateLimiter.Check(player, "DevRequest") then
		return
	end
	local access = accessFor(player) -- recomputed from server facts on EVERY call; nothing the client sends is consulted
	if not access.Allowed then
		if not deniedLogged[player] then
			deniedLogged[player] = true
			warn(("[DevService] %s tried a developer action without access (%s)."):format(player.Name, access.Reason))
		end
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < Config.Dev.ActionCooldown then
		return
	end
	lastAction[player] = now
	local ok, clean = DevAccess.Validate(action, arg, {
		Tools = Defs.Tools, Backpacks = Defs.Backpacks, Treasure = Defs.Treasure,
		StopCount = #WorldElevator.StopTops, MaxCash = Config.Dev.MaxCash,
	})
	if not ok then
		return
	end
	local permitted, why = DevAccess.Permit(action, access, DataService.InTestMode(player))
	if not permitted then
		if why == "test-mode-required" then
			say(player, "Enter Test Mode first.", "Danger")
		end
		return
	end
	if not DataService.Get(player) then
		return
	end
	local fn = actions[action]
	if fn then
		local okRun, err = pcall(fn, player, clean)
		if not okRun then
			warn(("[DevService] action %s failed: %s"):format(action, tostring(err)))
			say(player, "Action failed: " .. tostring(err), "Danger")
		end
	end
end

function DevService.Init()
	StateService.DevInfo = function(player: Player)
		local access = accessFor(player)
		if not access.Allowed then
			return nil
		end
		return { Allowed = true, Active = DataService.InTestMode(player), World = access.World, Env = access.Env,
			Session = DevAccess.SessionLabel(DataService.SaveInfo(player)) }
	end
	Remotes.Get("DevRequest").OnServerEvent:Connect(handle)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		deniedLogged[player] = nil
	end)
	print(("[DevService] developer test mode: %s"):format(RunService:IsStudio() and "available (Studio)"
		or (#Config.Dev.AllowedUserIds > 0 and #Config.Dev.TestPlaceIds > 0) and "available to allowlisted accounts on this test place"
		or "OFF (no allowlisted accounts / test place configured)"))
end

return DevService
