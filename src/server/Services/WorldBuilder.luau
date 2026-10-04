-- Builds the whole world from code, IDEMPOTENTLY: everything lives under Workspace.World, which is destroyed and rebuilt
-- on every Build(), so running it again never duplicates assets. Lighting objects are looked up by name before creation.
-- Structure here (ground slabs, bedrock, map boundary); detail lives in WorldLandscape, WorldCamp and WorldElevator.
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Grid)

local Kit = require(script.Parent.WorldKit)
local WorldLandscape = require(script.Parent.WorldLandscape)
local WorldCamp = require(script.Parent.WorldCamp)
local WorldElevator = require(script.Parent.WorldElevator)
local WorldAudit = require(script.Parent.WorldAudit)
local GroundPlan = require(ReplicatedStorage.Shared.GroundPlan)

local C = Kit.Color
local WorldBuilder = {}

-- positions other services rely on (unchanged values)
WorldBuilder.SellZoneCenter = WorldCamp.SellZoneCenter
WorldBuilder.SpawnCFrame = WorldCamp.SpawnCFrame
WorldBuilder.ReceivingCenter = WorldCamp.ReceivingCenter
WorldBuilder.ReceivingDisplayPosition = WorldCamp.ReceivingDisplayPosition
WorldBuilder.LostFoundPosition = WorldCamp.LostFoundPosition
WorldBuilder.RecoveryPosition = WorldCamp.RecoveryPosition
WorldBuilder.EvacCFrame = WorldCamp.EvacCFrame
WorldBuilder.RecoverySlot = WorldCamp.RecoverySlot
WorldBuilder.Elevator = { StopTops = WorldElevator.StopTops, StopNames = WorldElevator.StopNames }

local function lighting()
	Lighting.ClockTime = 15.5
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromHex("8A7A68")
	Lighting.OutdoorAmbient = Color3.fromHex("9C8B77")
	Lighting.ColorShift_Top = Color3.fromHex("FFE2B0")
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.2
	local atm = Lighting:FindFirstChild("DigAtmosphere") :: Atmosphere?
	if not atm then
		atm = Instance.new("Atmosphere")
		atm.Name = "DigAtmosphere"
		atm.Parent = Lighting
	end
	atm.Density = 0.28
	atm.Offset = 0.1
	atm.Color = Color3.fromHex("F2D9B0")
	atm.Decay = Color3.fromHex("C9985F")
	atm.Haze = 1.4
	atm.Glare = 0
end

function WorldBuilder.Build()
	local old = Workspace:FindFirstChild("World")
	if old then
		old:Destroy()
	end
	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = Workspace
	lighting()

	-- Ground: slabs around the mine, thick enough that you never see void beside the shaft. The slabs are produced by
	-- subtracting the mine footprint (Grid.Bounds) and the elevator shaft (Config.Exit) from the playable square, so the
	-- opening always matches the configured bounds and no slab can cross the excavation.
	local ext = Config.World.BoundaryExtent
	local thickness = Config.Site.Depth * Config.Site.CellSize + 12
	local cy = Grid.SurfaceY - thickness / 2
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = world
	local ex = Config.Exit
	for i, r in ipairs(GroundPlan.Subtract({ -ext, ext, -ext, ext }, WorldCamp.MineHoles(ex))) do
		Kit.box(ground, "Slab" .. i, Vector3.new(r[2] - r[1], thickness, r[4] - r[3]),
			Vector3.new((r[1] + r[2]) / 2, cy, (r[3] + r[4]) / 2), C.Sand, Enum.Material.Sand)
	end

	-- Bedrock under the shaft, invisible boundary walls (unchanged)
	local gb = Grid.Bounds()
	Kit.box(world, "Bedrock", Vector3.new(gb.MaxX - gb.MinX, 8, gb.MaxZ - gb.MinZ),
		Vector3.new((gb.MinX + gb.MaxX) / 2, gb.BottomY - 4, (gb.MinZ + gb.MaxZ) / 2), C.Iron, Enum.Material.Slate)
	for i, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local wall = Kit.box(world, "Boundary" .. i,
			Vector3.new(d[1] ~= 0 and 2 or ext * 2, 120, d[2] ~= 0 and 2 or ext * 2),
			Vector3.new(d[1] * ext, 50, d[2] * ext), C.Iron)
		wall.Transparency = 1
	end

	WorldLandscape.Build(world)
	WorldCamp.Build(world, ex)
	if ex.Enabled then
		local gb2 = Grid.Bounds()
		WorldElevator.Build(world, ex.CenterX - ex.Width / 2, ex.CenterX + ex.Width / 2, gb2.MaxZ, gb2.MaxZ + ex.Run)
	end
	WorldBuilder.LastAudit = WorldAudit.Run(world)
	return world
end

return WorldBuilder
