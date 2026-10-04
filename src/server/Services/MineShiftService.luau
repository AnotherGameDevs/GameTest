-- "Fresh Dig": replenishes the shared mine when it is exhausted (docs/MINE_SHIFT.md).
--   1. Watch depletion (Config.Shift). When the mine is mostly dug out, or its deepest layer is, or it is old and
--      substantially dug, start a countdown and tell every player.
--   2. At zero: wait (up to Config.Shift.CarryDeferSeconds) for anyone still CARRYING an artifact inside the mine; after
--      that their artifact is dropped like any other loss. Resting artifacts inside the mine are moved to Lost & Found
--      (never deleted). Players inside the mine volume are moved to the camp spawn.
--   3. Regenerate the grid with a new seed. The exit shaft/elevator are outside the grid and untouched.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShiftSpec = require(ReplicatedStorage.Shared.ShiftSpec)

local SiteService = require(script.Parent.SiteService)
local ArtifactService = require(script.Parent.ArtifactService)
local WorldBuilder = require(script.Parent.WorldBuilder)
local StateService = require(script.Parent.StateService)

local MineShiftService = {}

local shiftRemote = Remotes.Get("MineShift")
local shifts = 0
local running = false

function MineShiftService.ShouldRefresh(depletion, cfg): boolean
	return ShiftSpec.ShouldRefresh(depletion, cfg, Config.Layers[#Config.Layers].Id)
end

local function broadcast(phase: string, seconds: number?)
	shiftRemote:FireAllClients(phase, seconds)
end

local function moveOutOfMine()
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and ArtifactService.InMine(hrp.Position) then
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.CFrame = WorldBuilder.SpawnCFrame
		end
	end
end

function MineShiftService.RefreshNow()
	shifts += 1
	-- 1. carriers who have not left the mine by now drop their artifact (it is relocated, never deleted)
	for _, player in ipairs(ArtifactService.CarriersInMine()) do
		ArtifactService.ForceDrop(player)
	end
	ArtifactService.RelocateFromMine()
	-- 2. everyone inside goes to camp, 3. new terrain
	moveOutOfMine()
	SiteService.Generate(Config.Site.Seed + shifts * Config.Shift.SeedStep)
	for _, player in ipairs(Players:GetPlayers()) do
		StateService.Push(player)
	end
	broadcast("Done")
end

local function runShift()
	running = true
	local cfg = Config.Shift
	for left = cfg.WarningSeconds, 1, -1 do
		broadcast("Warning", left)
		task.wait(1)
	end
	-- wait for carriers to bring their artifact out (bounded)
	local waited = 0
	while #ArtifactService.CarriersInMine() > 0 and waited < cfg.CarryDeferSeconds do
		if waited % 10 == 0 then
			broadcast("Deferred", cfg.CarryDeferSeconds - waited)
		end
		task.wait(1)
		waited += 1
	end
	MineShiftService.RefreshNow()
	running = false
end

function MineShiftService.Init()
	if not Config.Shift.Enabled then
		return
	end
	task.spawn(function()
		while true do
			task.wait(Config.Shift.CheckInterval)
			if not running and MineShiftService.ShouldRefresh(SiteService.Depletion(), Config.Shift) then
				runShift()
			end
		end
	end)
end

return MineShiftService
