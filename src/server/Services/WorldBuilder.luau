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
-- Artifact receiving table (beside the sell/appraisal zone) and the lost & found pad (fallback drop point).
WorldBuilder.ReceivingCenter = Config.Camp.Position + Vector3.new(-27, 3.5, -7) -- where a depositing player must be near
WorldBuilder.ReceivingDisplayPosition = Config.Camp.Position + Vector3.new(-27, 5.2, -7)
WorldBuilder.LostFoundPosition = Config.Camp.Position + Vector3.new(-27, 2.2, -13)

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

-- A sign that cannot be seen through walls (SurfaceGui, not an always-on-top billboard).
local function surfaceSign(parent: Part, face: Enum.NormalId, text: string, bg: Color3, fg: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(400, 160)
	gui.LightInfluence = 0.2
	gui.AlwaysOnTop = false
	gui.Parent = parent
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = bg
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.94, 0.8)
	label.Position = UDim2.fromScale(0.03, 0.1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = fg
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = frame
end

-- Padded artifact receiving table: timber frame, cream cloth, plaque, deposit prompt.
function WorldBuilder.BuildReceivingStation(camp: Folder)
	local folder = Instance.new("Folder")
	folder.Name = "ReceivingTable"
	folder.Parent = camp
	local c = WorldBuilder.ReceivingCenter
	local base = Vector3.new(c.X, 0.5, c.Z) -- camp floor top
	local TIMBER, TIMBER_DARK = Color3.fromHex("8B5E34"), Color3.fromHex("6B4A2E")

	for _, sx in ipairs({ -2.5, 2.5 }) do
		for _, sz in ipairs({ -1.5, 1.5 }) do
			part(folder, "Leg", Vector3.new(0.7, 2.6, 0.7), CFrame.new(base + Vector3.new(sx, 1.3, sz)), TIMBER, Enum.Material.Wood)
		end
	end
	part(folder, "RailFront", Vector3.new(5.7, 0.4, 0.4), CFrame.new(base + Vector3.new(0, 2.5, 1.5)), TIMBER_DARK, Enum.Material.Wood)
	part(folder, "RailBack", Vector3.new(5.7, 0.4, 0.4), CFrame.new(base + Vector3.new(0, 2.5, -1.5)), TIMBER_DARK, Enum.Material.Wood)
	part(folder, "RailL", Vector3.new(0.4, 0.4, 3.0), CFrame.new(base + Vector3.new(-2.5, 2.5, 0)), TIMBER_DARK, Enum.Material.Wood)
	part(folder, "RailR", Vector3.new(0.4, 0.4, 3.0), CFrame.new(base + Vector3.new(2.5, 2.5, 0)), TIMBER_DARK, Enum.Material.Wood)
	part(folder, "TableTop", Vector3.new(6.2, 0.4, 4.0), CFrame.new(base + Vector3.new(0, 2.8, 0)), TIMBER, Enum.Material.Wood)
	part(folder, "ClothPad", Vector3.new(5.6, 0.35, 3.4), CFrame.new(base + Vector3.new(0, 3.18, 0)), P.Cream, Enum.Material.Fabric)
	part(folder, "ClothDrape", Vector3.new(5.6, 1.0, 0.15), CFrame.new(base + Vector3.new(0, 2.6, 2.05)), P.Cream, Enum.Material.Fabric)
	local plaque = part(folder, "Plaque", Vector3.new(3.2, 0.8, 0.2), CFrame.new(base + Vector3.new(0, 2.6, 2.2)), P.Dark)
	surfaceSign(plaque, Enum.NormalId.Back, "ARTIFACT RECEIVING", P.Dark, P.Gold)

	local anchor = part(folder, "DepositAnchor", Vector3.new(2, 1, 2), CFrame.new(base + Vector3.new(0, 4.0, 0)), P.Teal)
	anchor.Transparency = 1
	anchor.CanCollide = false
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DepositPrompt"
	prompt.ObjectText = "Receiving Table"
	prompt.ActionText = "Deposit artifact"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	-- Lost & found pad: where an artifact lands if nowhere safer exists (death/disconnect fallback)
	local pad = part(folder, "LostFoundPad", Vector3.new(4, 0.3, 4), CFrame.new(Vector3.new(c.X, 0.65, WorldBuilder.LostFoundPosition.Z)), Color3.fromHex("CDBE98"))
	surfaceSign(pad, Enum.NormalId.Top, "LOST & FOUND", Color3.fromHex("CDBE98"), P.Dark)
end

-- Fixed ladder exit: a shaft OUTSIDE the destructible grid on the camp edge, full depth, with scaffold-supported
-- landings in every layer. The grid cells on its north wall are instanced up front (see SiteService), so players
-- dig sideways into it from any depth.
function WorldBuilder.BuildExit(world: Folder, minX: number, maxX: number, minZ: number, maxZ: number)
	local folder = Instance.new("Folder")
	folder.Name = "ExitShaft"
	folder.Parent = world
	local width, run = maxX - minX, maxZ - minZ
	local cx = (minX + maxX) / 2
	local floorY = Grid.SurfaceY - Config.Site.Depth * Config.Site.CellSize
	local TIMBER, TIMBER_DARK = Color3.fromHex("8B5E34"), Color3.fromHex("6B4A2E")

	part(folder, "ShaftFloor", Vector3.new(width, 12, run), CFrame.new(cx, floorY - 6, (minZ + maxZ) / 2), P.Dark, Enum.Material.Slate)

	-- Ladder: climbable truss on the south wall, floor to just above ground. Works while holding tools/artifacts.
	local top = Grid.SurfaceY + 4
	local truss = Instance.new("TrussPart")
	truss.Name = "Ladder"
	truss.Anchored = true
	truss.Size = Vector3.new(2, top - floorY, 2)
	truss.CFrame = CFrame.new(cx, (top + floorY) / 2, maxZ - 1)
	truss.Color = TIMBER_DARK
	truss.Material = Enum.Material.Wood
	truss.Parent = folder

	-- Landings: tops sit on a cell-row boundary so the grid row right above each platform is diggable. One per layer.
	local landingTops = { -8, -24, -36, -48 } -- soil, clay, stone, ruins
	local lowerTops = { -8, -24, -36, -48, floorY }
	for i, y in ipairs(landingTops) do
		part(folder, "Landing" .. i, Vector3.new(width, 1, run - 2), CFrame.new(cx, y - 0.5, minZ + (run - 2) / 2), TIMBER, Enum.Material.WoodPlanks)
		-- scaffold: corner posts down to the next landing/floor + cross beams
		local nextY = lowerTops[i + 1]
		local drop = (y - 1) - nextY
		for _, px in ipairs({ minX + 1, maxX - 1 }) do
			for _, pz in ipairs({ minZ + 1, minZ + run - 3 }) do
				part(folder, "Post", Vector3.new(1, drop, 1), CFrame.new(px, nextY + drop / 2, pz), TIMBER_DARK, Enum.Material.Wood)
			end
		end
		for _, pz in ipairs({ minZ + 1, minZ + run - 3 }) do
			part(folder, "Beam", Vector3.new(width, 0.6, 0.6), CFrame.new(cx, y - 1.3, pz), TIMBER_DARK, Enum.Material.Wood)
		end
		-- EXIT sign beside the ladder, on the south wall facing north (SurfaceGui: invisible through walls)
		local board = part(folder, "ExitSign" .. i, Vector3.new(4, 1.6, 0.2), CFrame.new(cx + 3.5, y + 2.6, maxZ - 0.1), P.Dark)
		surfaceSign(board, Enum.NormalId.Front, "EXIT TO CAMP >>", P.Dark, P.Gold)
	end
	local floorBoard = part(folder, "ExitSignFloor", Vector3.new(4, 1.6, 0.2), CFrame.new(cx + 3.5, floorY + 2.6, maxZ - 0.1), P.Dark)
	surfaceSign(floorBoard, Enum.NormalId.Front, "EXIT TO CAMP >>", P.Dark, P.Gold)

	-- Camp-side marker so the shaft can be found from the surface
	local post1 = part(folder, "MarkerPostL", Vector3.new(0.6, 6, 0.6), CFrame.new(cx - 3, 3, maxZ + 2), TIMBER_DARK, Enum.Material.Wood)
	part(folder, "MarkerPostR", Vector3.new(0.6, 6, 0.6), CFrame.new(cx + 3, 3, maxZ + 2), TIMBER_DARK, Enum.Material.Wood)
	local marker = part(folder, "MarkerSign", Vector3.new(7, 2, 0.3), CFrame.new(cx, 5, maxZ + 2), P.Dark)
	surfaceSign(marker, Enum.NormalId.Back, "MINE LADDER", P.Dark, P.Cream)
	post1.Name = "MarkerPost"
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
	local ex = Config.Exit
	local exMinX, exMaxX = ex.CenterX - ex.Width / 2, ex.CenterX + ex.Width / 2
	local exMaxZ = halfZ + ex.Run
	if ex.Enabled then
		slab("SouthWest", -ext, exMinX, halfZ, ext)
		slab("SouthEast", exMaxX, ext, halfZ, ext)
		slab("SouthFront", exMinX, exMaxX, exMaxZ, ext)
	else
		slab("South", -ext, ext, halfZ, ext)
	end
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
		-- RimPost2 stood at (0, 72): dead centre of the straight spawn -> dig site route, so it is not built.
		if i == 2 then
			continue
		end
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

	WorldBuilder.BuildReceivingStation(camp)
	if ex.Enabled then
		WorldBuilder.BuildExit(world, exMinX, exMaxX, halfZ, exMaxZ)
	end

	-- Dig-site welcome sign
	local board = part(camp, "SiteBoard", Vector3.new(14, 6, 1), CFrame.new(Vector3.new(0, 6, halfZ + 8)), P.Dark)
	sign(board, "DIG HERE  ▼", P.Cream, 0, UDim2.fromOffset(280, 70))

	return world
end

return WorldBuilder
