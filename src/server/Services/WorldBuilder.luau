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

local C = Kit.Color
local WorldBuilder = {}

-- positions other services rely on (unchanged values)
WorldBuilder.SellZoneCenter = WorldCamp.SellZoneCenter
WorldBuilder.SpawnCFrame = WorldCamp.SpawnCFrame
WorldBuilder.ReceivingCenter = WorldCamp.ReceivingCenter
WorldBuilder.ReceivingDisplayPosition = WorldCamp.ReceivingDisplayPosition
WorldBuilder.LostFoundPosition = WorldCamp.LostFoundPosition
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

	-- Ground: slabs around the dig footprint, thick enough that you never see void beside the shaft.
	local half = Config.Site.SizeX * Config.Site.CellSize / 2
	local halfZ = Config.Site.SizeZ * Config.Site.CellSize / 2
	local ext = 170
	local thickness = Config.Site.Depth * Config.Site.CellSize + 12
	local cy = Grid.SurfaceY - thickness / 2
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = world
	local function slab(name: string, x0: number, x1: number, z0: number, z1: number)
		Kit.box(ground, name, Vector3.new(x1 - x0, thickness, z1 - z0), Vector3.new((x0 + x1) / 2, cy, (z0 + z1) / 2), C.Sand, Enum.Material.Sand)
	end
	slab("North", -ext, ext, -ext, -halfZ)
	slab("West", -ext, -half, -halfZ, halfZ)
	slab("East", half, ext, -halfZ, halfZ)
	local ex = Config.Exit
	local exMinX, exMaxX, exMaxZ = ex.CenterX - ex.Width / 2, ex.CenterX + ex.Width / 2, halfZ + ex.Run
	if ex.Enabled then
		-- the south slab is carved around the elevator shaft
		slab("SouthWest", -ext, exMinX, halfZ, ext)
		slab("SouthEast", exMaxX, ext, halfZ, ext)
		slab("SouthFront", exMinX, exMaxX, exMaxZ, ext)
	else
		slab("South", -ext, ext, halfZ, ext)
	end

	-- Bedrock under the shaft, invisible boundary walls (unchanged)
	local floorY = Grid.SurfaceY - Config.Site.Depth * Config.Site.CellSize
	Kit.box(world, "Bedrock", Vector3.new(half * 2, 8, halfZ * 2), Vector3.new(0, floorY - 4, 0), C.Iron, Enum.Material.Slate)
	for i, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local wall = Kit.box(world, "Boundary" .. i,
			Vector3.new(d[1] ~= 0 and 2 or ext * 2, 120, d[2] ~= 0 and 2 or ext * 2),
			Vector3.new(d[1] * ext, 50, d[2] * ext), C.Iron)
		wall.Transparency = 1
	end

	WorldLandscape.Build(world)
	WorldCamp.Build(world, ex)
	if ex.Enabled then
		WorldElevator.Build(world, exMinX, exMaxX, halfZ, exMaxZ)
	end
	return world
end

return WorldBuilder
