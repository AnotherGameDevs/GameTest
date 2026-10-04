-- The mine elevator. Outside the destructible grid on the camp edge, full depth, framed in timber and iron above
-- ground. Two columns inside the shaft:
--   * RIGHT column (x midX..maxX): the car's travel column. Open from the surface to the bottom; the grid face is
--     covered by an iron plate, so it can't be dug into (nothing digs into an open shaft).
--   * LEFT column  (x minX..midX): timber landings in every layer (soil, clay, stone, ruins), scaffold posts and a ladder
--     kept as a fallback. The grid cells facing this column are instanced from the start, so players dig sideways into
--     it from any depth and step onto the landing, then onto the car.
-- The car is an unanchored platform on a vertical PrismaticConstraint servo owned by the server (ElevatorService), so
-- passengers (and artifacts they carry) ride it with normal physics. Stops sit on the landing tops.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Grid)

local Kit = require(script.Parent.WorldKit)
local C = Kit.Color
local V = Vector3.new
local box, part, deco, sign, weld = Kit.box, Kit.part, Kit.deco, Kit.sign, Kit.weld

local WorldElevator = {}

-- Platform TOP heights, surface first. Landing tops are cell-row boundaries so the grid row above each is diggable.
-- Derived from Config.Layers: each landing sits two rows below the top of its layer, so the row above is diggable.
WorldElevator.StopTops = { 0.5 }
WorldElevator.StopNames = { "SURFACE" }
for _, layer in ipairs(Config.Layers) do
	table.insert(WorldElevator.StopTops, -(layer.FromCell + 2) * Config.Site.CellSize)
	table.insert(WorldElevator.StopNames, layer.Name)
end
WorldElevator.CarThickness = 0.8

local function prompt(parent: Instance, name: string, action: string, object: string, attrs: { [string]: any }, distance: number?)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = distance or 8
	p.RequiresLineOfSight = false
	for k, v in pairs(attrs) do
		p:SetAttribute(k, v)
	end
	p.Parent = parent
	return p
end

function WorldElevator.Build(world: Folder, minX: number, maxX: number, minZ: number, maxZ: number)
	local folder = Instance.new("Folder")
	folder.Name = "Elevator"
	folder.Parent = world
	local midX = (minX + maxX) / 2
	local run = maxZ - minZ
	local floorY = Grid.SurfaceY - Config.Site.Depth * Config.Site.CellSize
	local carX = (midX + maxX) / 2 -- centre of the car column
	local carDepth = run - 0.5 -- clear of the iron plate on the grid face, flush with the camp floor edge at the top stop
	local carZ = minZ + 0.5 + carDepth / 2

	-- shaft floor + the iron plate that closes the grid face behind the car column
	box(folder, "ShaftFloor", V(maxX - minX, 12, run), V((minX + maxX) / 2, floorY - 6, (minZ + maxZ) / 2), C.Iron, Enum.Material.Slate)
	local plateH = Grid.SurfaceY - floorY
	box(folder, "IronPlate", V(maxX - midX, plateH, 0.4), V(carX, floorY + plateH / 2, minZ + 0.2), C.Iron, Enum.Material.Metal)
	for y = floorY + 4, Grid.SurfaceY - 2, 8 do
		box(folder, "PlateBand", V(maxX - midX, 0.5, 0.6), V(carX, y, minZ + 0.45), C.TimberDark, Enum.Material.Wood)
	end
	-- guide rail on the east wall
	box(folder, "GuideRail", V(0.3, plateH + 4, 0.8), V(maxX - 0.15, floorY + (plateH + 4) / 2, carZ), C.IronLight, Enum.Material.Metal)

	-- LEFT column: ladder (fallback), landings, scaffold, signs ---------------------------------------------------------
	local ladderX = (minX + midX) / 2
	local top = Grid.SurfaceY + 4
	local truss = Instance.new("TrussPart")
	truss.Name = "Ladder"
	truss.Anchored = true
	truss.Size = V(2, top - floorY, 2)
	truss.CFrame = CFrame.new(ladderX, (top + floorY) / 2, maxZ - 1)
	truss.Color = C.TimberDark
	truss.Material = Enum.Material.Wood
	truss.Parent = folder

	local landingTops, lowerTops = {}, {}
	for i = 2, #WorldElevator.StopTops do
		landingTops[i - 1] = WorldElevator.StopTops[i]
		lowerTops[i - 1] = WorldElevator.StopTops[i]
	end
	table.insert(lowerTops, floorY)
	local landingW = midX - minX
	for i, y in ipairs(landingTops) do
		box(folder, "Landing" .. i, V(landingW, 1, run - 2), V(ladderX, y - 0.5, minZ + (run - 2) / 2), C.TimberLight, Enum.Material.WoodPlanks)
		local nextY = lowerTops[i + 1]
		local drop = (y - 1) - nextY
		for _, px in ipairs({ minX + 0.8, midX - 1.2 }) do
			for _, pz in ipairs({ minZ + 1, minZ + run - 3 }) do
				box(folder, "Post", V(1, drop, 1), V(px, nextY + drop / 2, pz), C.TimberDark, Enum.Material.Wood)
			end
		end
		for _, pz in ipairs({ minZ + 1, minZ + run - 3 }) do
			box(folder, "Beam", V(landingW, 0.6, 0.6), V(ladderX, y - 1.3, pz), C.TimberDark, Enum.Material.Wood)
		end
		local board = box(folder, "ExitSign" .. i, V(4, 1.5, 0.2), V(ladderX - 2, y + 2.6, maxZ - 0.1), C.Iron, Enum.Material.Metal)
		sign(board, Enum.NormalId.Front, "EXIT TO CAMP", C.Iron, C.Gold)
	end

	-- THE CAR ---------------------------------------------------------------------------------------------------------
	local topY = WorldElevator.StopTops[1]
	local car = Instance.new("Part")
	car.Name = "Car"
	car.Size = V(maxX - midX - 0.6, WorldElevator.CarThickness, carDepth) -- clear of the guide rail and the landings
	car.Position = V(carX, topY - WorldElevator.CarThickness / 2, carZ)
	car.Anchored = false
	car.Material = Enum.Material.WoodPlanks
	car.Color = C.TimberLight
	car.TopSurface = Enum.SurfaceType.Smooth
	car.BottomSurface = Enum.SurfaceType.Smooth
	car.CustomPhysicalProperties = PhysicalProperties.new(2, 0.6, 0, 1, 1) -- heavy and grippy: passengers ride it
	car.Parent = folder
	local function carPart(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material, solid: boolean?)
		local p = part(folder, name, size, car.CFrame * CFrame.new(offset), color, material)
		p.Anchored = false
		p.Massless = true
		if not solid then
			deco(p)
		end
		weld(car, p)
		return p
	end
	local halfW, halfD = car.Size.X / 2, car.Size.Z / 2
	carPart("CarEdgeN", V(car.Size.X, 0.3, 0.3), V(0, 0.55, -halfD + 0.15), C.Iron, Enum.Material.Metal)
	carPart("CarEdgeE", V(0.3, 0.3, car.Size.Z), V(halfW - 0.15, 0.55, 0), C.Iron, Enum.Material.Metal)
	carPart("CarEdgeS", V(car.Size.X, 0.3, 0.3), V(0, 0.55, halfD - 0.15), C.Iron, Enum.Material.Metal)
	-- railing on the landing side with a wide gap for boarding
	for _, z in ipairs({ -halfD + 0.5, -halfD + 2.2, halfD - 2.2, halfD - 0.5 }) do
		carPart("RailPost", V(0.3, 2.6, 0.3), V(-halfW + 0.2, 1.7, z), C.Iron, Enum.Material.Metal, true)
	end
	carPart("RailA", V(0.25, 0.25, 1.8), V(-halfW + 0.2, 2.8, -halfD + 1.35), C.IronLight, Enum.Material.Metal, true)
	carPart("RailB", V(0.25, 0.25, 1.8), V(-halfW + 0.2, 2.8, halfD - 1.35), C.IronLight, Enum.Material.Metal, true)
	-- control post with one prompt per action
	carPart("ControlPost", V(0.6, 4.2, 0.6), V(halfW - 0.8, 2.5, 0), C.TimberDark, Enum.Material.Wood, true)
	local actions = { { "Surface", "Go to surface", 3.1 }, { "Up", "Ride up", 2.3 }, { "Down", "Ride down", 1.5 } }
	for _, a in ipairs(actions) do
		local panel = carPart("Panel" .. a[1], V(0.9, 0.55, 0.25), V(halfW - 1.5, a[3] + 0.2, 0), C.Iron, Enum.Material.Metal)
		prompt(panel, "RidePrompt", a[2], "Mine elevator", { Kind = a[1] }, 7)
	end

	-- vertical servo: the car can only move along Y, to the stop the server asks for
	local track = part(folder, "Track", V(1, 1, 1), CFrame.new(carX, floorY, carZ), C.Iron, Enum.Material.Metal)
	track.Transparency = 1
	deco(track)
	local a0 = Instance.new("Attachment")
	a0.Name = "TrackAttach"
	a0.Orientation = V(0, 0, 90) -- the constraint's slide axis (X) points up
	a0.Parent = track
	local a1 = Instance.new("Attachment")
	a1.Name = "CarAttach"
	a1.Orientation = V(0, 0, 90)
	a1.Parent = car
	local lift = Instance.new("PrismaticConstraint")
	lift.Name = "Lift"
	lift.Attachment0 = a0
	lift.Attachment1 = a1
	lift.LimitsEnabled = true
	lift.LowerLimit = 0
	lift.UpperLimit = (topY - WorldElevator.CarThickness / 2) - floorY + 0.5
	lift.ActuatorType = Enum.ActuatorType.Servo
	lift.ServoMaxForce = 1e7
	lift.LinearResponsiveness = 20
	lift.Speed = 14
	lift.TargetPosition = (topY - WorldElevator.CarThickness / 2) - floorY
	lift.Parent = track
	folder:SetAttribute("TrackY", floorY)

	-- call posts at every stop (the surface one is on the camp floor in front of the entrance) ---------------------------
	for i, stopTop in ipairs(WorldElevator.StopTops) do
		local px, pz, py
		if i == 1 then
			px, pz, py = midX - 0.8, maxZ + 1.5, stopTop
		else
			px, pz, py = midX - 0.6, minZ + 1.5, stopTop
		end
		box(folder, "CallPost" .. i, V(0.6, 3.2, 0.6), V(px, py + 1.6, pz), C.TimberDark, Enum.Material.Wood)
		local plate = box(folder, "CallPlate" .. i, V(1.0, 0.7, 0.25), V(px, py + 2.6, pz), C.Iron, Enum.Material.Metal)
		prompt(plate, "CallPrompt", "Call elevator", WorldElevator.StopNames[i], { Kind = "Call", StopIndex = i }, 9)
	end

	-- TOWER FRAME above ground: a timber/iron gantry that stands on solid ground in FRONT of the shaft mouth and beside it.
	-- Its posts are outside the car's footprint and outside the destructible grid, so nothing ever collides with the car.
	local towerH = 24
	local gx0, gx1 = minX - 0.4, maxX + 0.6 -- west / east posts (east one stands on the ground slab beside the shaft)
	local gz0, gz1 = maxZ + 0.8, maxZ + 4.8 -- front-of-shaft row and the row behind it, on the camp side
	-- entrance deck: continues the camp floor level under the gantry, so boarding is a flat walk-on
	box(folder, "EntranceDeck", V(gx1 - gx0 + 2, 0.5, gz1 - gz0 + 3), V((gx0 + gx1) / 2, 0.27, (maxZ + gz1 + 1.5) / 2), C.TimberLight, Enum.Material.WoodPlanks)
	for _, x in ipairs({ gx0, gx1 }) do
		for _, z in ipairs({ gz0, gz1 }) do
			box(folder, "TowerPost", V(1.2, towerH, 1.2), V(x, towerH / 2, z), C.Timber, Enum.Material.Wood)
			for y = 5, towerH - 3, 7 do
				box(folder, "TowerBand", V(1.4, 0.5, 1.4), V(x, y, z), C.Iron, Enum.Material.Metal)
			end
		end
	end
	local function brace(a: Vector3, b: Vector3)
		local len = (b - a).Magnitude
		deco(part(folder, "Brace", V(0.5, 0.5, len), CFrame.lookAt((a + b) / 2, b), C.TimberDark, Enum.Material.Wood))
	end
	-- X-bracing on the two SIDE faces only: the south (camp) side and the shaft mouth stay fully open as the entrance
	for _, x in ipairs({ gx0, gx1 }) do
		brace(V(x, 2, gz0), V(x, 21, gz1))
		brace(V(x, 21, gz0), V(x, 2, gz1))
	end
	-- crown beams + an iron machinery housing (static)
	for _, z in ipairs({ gz0, gz1 }) do
		box(folder, "CrownBeam", V(gx1 - gx0 + 1.2, 1.0, 1.0), V((gx0 + gx1) / 2, towerH + 0.4, z), C.TimberDark, Enum.Material.Wood)
	end
	for _, x in ipairs({ gx0, gx1 }) do
		box(folder, "CrownCross", V(1.0, 1.0, gz1 - gz0 + 1.2), V(x, towerH + 0.4, (gz0 + gz1) / 2), C.TimberDark, Enum.Material.Wood)
	end
	box(folder, "MachineHousing", V(5, 3, 3.6), V(carX, towerH + 2.4, (gz0 + gz1) / 2), C.Iron, Enum.Material.Metal)
	-- entrance: lintel across the front row, with a clear sign
	box(folder, "EntranceLintel", V(gx1 - gx0 + 1.2, 0.9, 0.9), V((gx0 + gx1) / 2, 10.2, gz0), C.TimberDark, Enum.Material.Wood)
	box(folder, "EntranceBand", V(gx1 - gx0 + 1.4, 0.4, 1.1), V((gx0 + gx1) / 2, 9.7, gz0), C.Iron, Enum.Material.Metal)
	-- Signs sit flush on the front of the two posts (their width spans the post centres, they are embedded in the posts and
	-- stacked directly on the lintel), so nothing hangs in mid-air.
	local span = gx1 - gx0
	local lintelTop = 10.2 + 0.45
	local subH, mainH = 1.2, 2.2
	local sub = box(folder, "ElevatorSubSign", V(math.min(6, span), subH, 0.3), V((gx0 + gx1) / 2, lintelTop + subH / 2, gz0 + 0.55), C.Iron, Enum.Material.Metal)
	sign(sub, Enum.NormalId.Back, "TO THE MINE", C.Iron, C.Gold)
	local board = box(folder, "ElevatorSign", V(span, mainH, 0.3), V((gx0 + gx1) / 2, lintelTop + subH + mainH / 2, gz0 + 0.55), C.TimberDark, Enum.Material.Wood)
	sign(board, Enum.NormalId.Back, "ELEVATOR", C.TimberDark, C.Trim)

	return folder
end

return WorldElevator
