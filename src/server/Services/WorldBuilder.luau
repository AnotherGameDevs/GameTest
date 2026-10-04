-- Builds the graybox world (lighting, ground, Base Camp, Sell Zone, Shop) from code, idempotently:
-- anything it made before is destroyed first, so nothing is ever duplicated.
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Grid)

local P = Config.Palette
local WorldBuilder = {}

WorldBuilder.SellZoneCenter = Config.Camp.Position + Config.Camp.SellZoneOffset
WorldBuilder.SpawnCFrame = CFrame.new(Config.Camp.Position + Vector3.new(0, 4, 16))

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function sign(parent: Part, text: string, color: Color3, studsAbove: number, size: UDim2)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = size
	gui.StudsOffset = Vector3.new(0, studsAbove, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 400
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = P.Dark
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = gui
end

function WorldBuilder.Build()
	local old = Workspace:FindFirstChild("World")
	if old then
		old:Destroy()
	end
	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = Workspace

	-- Lighting: warm afternoon
	Lighting.ClockTime = 15.5
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromHex("8A7A68")
	Lighting.OutdoorAmbient = Color3.fromHex("9C8B77")
	Lighting.ColorShift_Top = Color3.fromHex("FFE2B0")
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.2
	if not Lighting:FindFirstChild("DigAtmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Name = "DigAtmosphere"
		atm.Density = 0.25
		atm.Color = Color3.fromHex("F0D9B5")
		atm.Decay = Color3.fromHex("C9985F")
		atm.Haze = 1.2
		atm.Parent = Lighting
	end

	-- Ground: four slabs around the dig footprint, thick enough that you never see void beside the shaft.
	local half = Config.Site.SizeX * Config.Site.CellSize / 2
	local halfZ = Config.Site.SizeZ * Config.Site.CellSize / 2
	local ext = 170
	local thickness = Config.Site.Depth * Config.Site.CellSize + 12
	local cy = Grid.SurfaceY - thickness / 2
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = world
	local function slab(name: string, x0: number, x1: number, z0: number, z1: number)
		part(ground, name, Vector3.new(x1 - x0, thickness, z1 - z0),
			CFrame.new((x0 + x1) / 2, cy, (z0 + z1) / 2), P.Sandstone, Enum.Material.Sand)
	end
	slab("North", -ext, ext, -ext, -halfZ)
	slab("South", -ext, ext, halfZ, ext)
	slab("West", -ext, -half, -halfZ, halfZ)
	slab("East", half, ext, -halfZ, halfZ)

	-- Bedrock under the shaft
	local floorY = Grid.SurfaceY - Config.Site.Depth * Config.Site.CellSize
	part(world, "Bedrock", Vector3.new(half * 2, 8, halfZ * 2), CFrame.new(0, floorY - 4, 0), P.Dark, Enum.Material.Slate)

	-- Invisible boundary walls so nobody wanders off the map
	for i, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local wall = part(world, "Boundary" .. i,
			Vector3.new(d[1] ~= 0 and 2 or ext * 2, 120, d[2] ~= 0 and 2 or ext * 2),
			CFrame.new(d[1] * ext, 50, d[2] * ext), P.Dark)
		wall.Transparency = 1
	end

	-- Rim posts around the pit so the site reads from afar
	for i = 0, 7 do
		local ang = i / 8 * math.pi * 2
		local r = math.max(half, halfZ) * 1.5
		part(world, "RimPost" .. i, Vector3.new(2, Config.Site.BorderHeight, 2),
			CFrame.new(math.cos(ang) * r, Config.Site.BorderHeight / 2, math.sin(ang) * r), P.Clay)
	end

	-- Base Camp
	local camp = Instance.new("Folder")
	camp.Name = "BaseCamp"
	camp.Parent = world
	local c = Config.Camp
	part(camp, "CampFloor", Vector3.new(c.Size.X, 0.5, c.Size.Z), CFrame.new(c.Position + Vector3.new(0, 0.25, 0)), P.Cream)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CampSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(c.Position + Vector3.new(0, 0.5, 16))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = P.Gold
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = camp
	WorldBuilder.SpawnCFrame = CFrame.new(spawn.Position + Vector3.new(0, 4, 0))

	-- Sell Zone
	local sz = WorldBuilder.SellZoneCenter
	local pad = part(camp, "SellZone", Vector3.new(c.SellZoneRadius * 2, 0.4, c.SellZoneRadius * 2),
		CFrame.new(sz + Vector3.new(0, 0.7, 0)), P.Gold)
	pad.Shape = Enum.PartType.Cylinder
	pad.CFrame = CFrame.new(sz + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pad.Size = Vector3.new(0.4, c.SellZoneRadius * 2, c.SellZoneRadius * 2)
	local post = part(camp, "SellPost", Vector3.new(1.5, 14, 1.5), CFrame.new(sz + Vector3.new(0, 7.5, 0)), P.Dark)
	sign(post, "SELL ZONE", P.Gold, 6, UDim2.fromOffset(240, 60))

	-- Shop stall
	local sp = c.Position + c.ShopOffset
	part(camp, "ShopCounter", Vector3.new(12, 4, 4), CFrame.new(sp + Vector3.new(0, 2.5, 0)), P.Clay)
	part(camp, "ShopBack", Vector3.new(12, 10, 1), CFrame.new(sp + Vector3.new(0, 5.5, -3)), P.Dark)
	part(camp, "ShopRoof", Vector3.new(14, 1, 7), CFrame.new(sp + Vector3.new(0, 11, -1)), P.Danger)
	local anchor = part(camp, "ShopAnchor", Vector3.new(2, 2, 2), CFrame.new(sp + Vector3.new(0, 5.5, 0)), P.Teal)
	anchor.Transparency = 1
	anchor.CanCollide = false
	sign(anchor, "EQUIPMENT SHOP", P.Teal, 5, UDim2.fromOffset(260, 56))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ObjectText = "Equipment Shop"
	prompt.ActionText = "Browse"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	-- Dig-site welcome sign
	local board = part(camp, "SiteBoard", Vector3.new(14, 6, 1), CFrame.new(Vector3.new(0, 6, halfZ + 8)), P.Dark)
	sign(board, "DIG HERE  ▼", P.Cream, 0, UDim2.fromOffset(280, 70))

	return world
end

return WorldBuilder
