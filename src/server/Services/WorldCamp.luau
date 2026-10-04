-- Base Camp, routes, excavation edge and the three stations. Ground treatments are distinct but related warm tones:
--   camp = compacted warm sand, routes = slightly darker worn earth, excavation edge = restrained gravel + disturbed soil.
-- Functional geometry is preserved: the camp floor top stays at y = 0.5, the spawn / sell radius / shop / receiving
-- positions and prompt names are unchanged. Only their visible construction changed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Appearances = require(ReplicatedStorage.Shared.Appearances)
local Grid = require(ReplicatedStorage.Shared.Grid)
local GroundPlan = require(ReplicatedStorage.Shared.GroundPlan)
local ToolModels = require(ReplicatedStorage.Shared.ToolModels)

local Kit = require(script.Parent.WorldKit)
local C = Kit.Color
local V = Vector3.new
local box, part, deco, sign = Kit.box, Kit.part, Kit.deco, Kit.sign

local WorldCamp = {}

-- Exposed to WorldBuilder / services. EVERY gameplay location comes from Config.Camp: the spawn, the return-to-camp
-- destination, the sell trigger centre, and the deposit check centre are the same values the models are built from.
WorldCamp.SellZoneCenter = Config.Camp.SellZoneCenter
WorldCamp.SpawnCFrame = CFrame.new(Config.Camp.SpawnPosition + Vector3.new(0, 4.5, 0))
WorldCamp.ReceivingCenter = Config.Camp.ReceivingPosition + Vector3.new(0, 3.5, 0)
WorldCamp.ReceivingDisplayPosition = Config.Camp.ReceivingPosition + Vector3.new(0, 5.2, 0)
WorldCamp.LostFoundPosition = Config.Camp.LostFoundPosition + Vector3.new(0, 2.2, 0)
WorldCamp.RecoveryPosition = Config.Camp.RecoveryPosition
-- Where players are put when a mine reset evacuates them: beside the recovery area, still on the camp floor.
WorldCamp.EvacCFrame = CFrame.new(Config.Camp.RecoveryPosition + Vector3.new(7.5, 4.5, 0))

-- Nine resting spots on the recovery pad (3 columns x 3 rows), centre height suits a ~2-stud artifact on the pad top.
function WorldCamp.RecoverySlot(i: number): Vector3
	local n = (i - 1) % 9
	local col, row = n % 3, n // 3
	return Config.Camp.RecoveryPosition + Vector3.new((col - 1) * 2.6, 2.0, (row - 1) * 1.9)
end

local function cylinder(parent: Instance, name: string, length: number, diameter: number, pos: Vector3, color: Color3, material: Enum.Material?, flat: boolean?): Part
	-- Roblox cylinders run along X. `flat` lays the disc on the ground (axis up).
	local cf = CFrame.new(pos) * (flat and CFrame.Angles(0, 0, math.rad(90)) or CFrame.identity)
	local p = part(parent, name, V(length, diameter, diameter), cf, color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function rope(parent: Instance, a: Vector3, b: Vector3)
	local len = (b - a).Magnitude
	local p = part(parent, "Rope", V(0.14, 0.14, len), CFrame.lookAt((a + b) / 2, b), C.Rope, Enum.Material.Fabric)
	deco(p)
end

-- Ground ------------------------------------------------------------------------------------------------------------
-- The mine footprint and the elevator shaft are HOLES in every ground treatment, derived from Grid.Bounds() and Config.Exit.
-- Nothing below can extend across the mine, because the rectangles are produced by subtracting those holes (GroundPlan).
local function mineHoles(ex): { { number } }
	local b = Grid.Bounds()
	local holes = { { b.MinX, b.MaxX, b.MinZ, b.MaxZ } }
	if ex.Enabled then
		table.insert(holes, { ex.CenterX - ex.Width / 2, ex.CenterX + ex.Width / 2, b.MaxZ, b.MaxZ + ex.Run })
	end
	return holes
end
WorldCamp.MineHoles = mineHoles

local function buildGround(camp: Folder, ex: { Enabled: boolean, CenterX: number, Width: number, Run: number })
	local c = Config.Camp
	local b = Grid.Bounds()
	local holes = mineHoles(ex)
	local ground = Instance.new("Folder")
	ground.Name = "GroundTreatment"
	ground.Parent = camp

	-- camp: compacted warm sand. The floor starts exactly at the shaft edge; a wider apron on the far sides only.
	local fx0, fx1 = c.Position.X - c.Size.X / 2, c.Position.X + c.Size.X / 2
	local fz0, fz1 = c.Position.Z - c.Size.Z / 2, c.Position.Z + c.Size.Z / 2
	for i, r in ipairs(GroundPlan.Subtract({ fx0 - 3, fx1 + 3, fz0, fz1 + 3 }, holes)) do
		box(camp, "CampApron" .. i, V(r[2] - r[1], 0.3, r[4] - r[3]), V((r[1] + r[2]) / 2, 0.15, (r[3] + r[4]) / 2), C.CampEdge, Enum.Material.Sand)
	end
	box(camp, "CampFloor", V(c.Size.X, 0.5, c.Size.Z), c.Position + V(0, 0.25, 0), C.Camp, Enum.Material.Sand)

	-- routes: worn earth from the back of camp to the mine entrance, with short branches to the stations
	local routeLen = fz1 - fz0
	box(ground, "RouteMain", V(12, 0.1, routeLen), V(0, 0.55, (fz0 + fz1) / 2), C.Route, Enum.Material.Ground)
	local shop, recv = c.ShopPosition, c.ReceivingPosition
	box(ground, "RouteShop", V(shop.X - 6 - 6.5, 0.1, 5), V((6 + shop.X - 6.5) / 2, 0.55, shop.Z), C.Route, Enum.Material.Ground)
	box(ground, "RouteReceiving", V(recv.X - 6 - 3.7, 0.1, 5), V((6 + recv.X - 3.7) / 2, 0.55, recv.Z), C.Route, Enum.Material.Ground)

	-- excavation edge: gravel in broad strips around the grid (a ring MINUS the mine and the shaft)
	local rim = 8
	for i, r in ipairs(GroundPlan.Subtract({ b.MinX - rim, b.MaxX + rim, b.MinZ - rim, b.MaxZ + rim }, holes)) do
		box(ground, "Rim" .. i, V(r[2] - r[1], 0.12, r[4] - r[3]), V((r[1] + r[2]) / 2, 0.06, (r[3] + r[4]) / 2), C.Gravel, Enum.Material.Pebble)
	end
	-- disturbed-soil patches: broad, low contrast, placed relative to the grid edge so they follow the configuration
	local midX, midZ = (b.MinX + b.MaxX) / 2, (b.MinZ + b.MaxZ) / 2
	local patches = {
		{ b.MinX + 8, b.MinZ - 4, 9, 5 }, { midX, b.MinZ - 5, 12, 4 }, { b.MaxX - 4, b.MinZ - 3, 8, 6 },
		{ b.MinX - 4, midZ - 14, 5, 10 }, { b.MinX - 3, midZ + 22, 4, 8 },
		{ b.MaxX + 4, midZ - 8, 4, 9 }, { b.MaxX + 3, midZ + 16, 5, 11 },
		{ b.MinX + 6, b.MaxZ + 4, 10, 4 }, { b.MaxX - 6, b.MaxZ + 4, 8, 4 },
	}
	for i, p in ipairs(patches) do
		box(ground, "Disturbed" .. i, V(p[3], 0.14, p[4]), V(p[1], 0.07, p[2]), C.Disturbed, Enum.Material.Ground)
	end
end

-- Rope-and-post fence around the dig, with gaps at the entrance and the elevator --------------------------------------
local function buildFence(camp: Folder, ex: { Enabled: boolean, CenterX: number, Width: number })
	local fence = Instance.new("Folder")
	fence.Name = "Fence"
	fence.Parent = camp
	local gb = Grid.Bounds()
	local lim = gb.MaxX + 7
	local zS = gb.MaxZ + 6.5
	local function inGap(x: number, z: number): boolean
		if z > 40 and math.abs(x) <= 10 then
			return true -- the way in
		end
		if ex.Enabled and z > 40 and x >= ex.CenterX - ex.Width / 2 - 2 and x <= ex.CenterX + ex.Width / 2 + 2 then
			return true -- the elevator
		end
		return false
	end
	-- ordered loop of fence points: north (W->E), east (N->S), south (E->W), west (S->N)
	local points: { Vector3 } = {}
	local step = 8
	for x = -lim, lim, step do table.insert(points, V(x, 0, -lim)) end
	for z = -lim + step, zS, step do table.insert(points, V(lim, 0, z)) end
	for x = lim, -lim, -step do table.insert(points, V(x, 0, zS)) end
	for z = zS - step, -lim + step, -step do table.insert(points, V(-lim, 0, z)) end
	for i, p in ipairs(points) do
		if not inGap(p.X, p.Z) then
			local post = box(fence, "Post", V(0.7, 3.4, 0.7), V(p.X, 1.7, p.Z), C.TimberDark, Enum.Material.Wood)
			post.CanCollide = true
			if i % 2 == 0 then
				box(fence, "LanternCap", V(0.7, 0.2, 0.7), V(p.X, 3.5, p.Z), C.Iron, Enum.Material.Metal)
				deco(box(fence, "LanternGlow", V(0.5, 0.55, 0.5), V(p.X, 3.85, p.Z), Color3.fromHex("FFD27A"), Enum.Material.Neon))
			end
			local nxt = points[(i % #points) + 1]
			if nxt and not inGap(nxt.X, nxt.Z) and (nxt - p).Magnitude < step * 1.5 then
				rope(fence, V(p.X, 2.7, p.Z), V(nxt.X, 2.7, nxt.Z))
			end
		end
	end
end

-- Entrance: boardwalk onto the dig surface and a tall gate (clear 12-stud opening, bottom of the lintel 8+ studs up) ----
local function buildEntrance(camp: Folder)
	local e = Instance.new("Folder")
	e.Name = "Entrance"
	e.Parent = camp
	local gb = Grid.Bounds()
	local gateZ = Config.Camp.EntranceZ
	local len = gateZ - gb.MaxZ - 0.5
	box(e, "Boardwalk", V(12, 0.4, len), V(0, 0.2, gb.MaxZ + len / 2), C.TimberLight, Enum.Material.WoodPlanks)
	for _, sx in ipairs({ -6.3, 6.3 }) do
		for _, dz in ipairs({ 1.5, len / 2, len - 1.5 }) do
			box(e, "RailPost", V(0.6, 3, 0.6), V(sx, 1.5, gb.MaxZ + dz), C.TimberDark, Enum.Material.Wood)
		end
		rope(e, V(sx, 2.5, gb.MaxZ + 1.5), V(sx, 2.5, gb.MaxZ + len - 1.5))
	end
	for _, sx in ipairs({ -7.4, 7.4 }) do
		box(e, "GatePost", V(1, 9.5, 1), V(sx, 5.25, gateZ), C.Timber, Enum.Material.Wood)
		box(e, "GateBand", V(1.15, 0.4, 1.15), V(sx, 3, gateZ), C.Iron, Enum.Material.Metal)
	end
	box(e, "GateLintel", V(16.6, 0.9, 0.9), V(0, 10.1, gateZ), C.TimberDark, Enum.Material.Wood)
	for _, sx in ipairs({ -3, 3 }) do
		deco(box(e, "SignChain", V(0.08, 0.8, 0.08), V(sx, 9.35, gateZ), C.Iron, Enum.Material.Metal))
	end
	local board = box(e, "EntranceSign", V(8, 1.9, 0.3), V(0, 8.0, gateZ), C.TimberDark, Enum.Material.Wood)
	sign(board, Enum.NormalId.Back, "DIG SITE", C.TimberDark, C.Trim)
end

-- Equipment shop: timber frame, muted teal canopy, framed counter, orderly rack of REAL tool models -------------------
local function buildShop(camp: Folder)
	local s = Instance.new("Folder")
	s.Name = "EquipmentShop"
	s.Parent = camp
	local o = Config.Camp.ShopPosition
	local base = V(o.X, 0.5, o.Z)
	for _, sx in ipairs({ -6, 6 }) do
		for _, sz in ipairs({ -3.3, 3.3 }) do
			box(s, "Post", V(0.9, 11, 0.9), base + V(sx, 5.5, sz), C.Timber, Enum.Material.Wood)
		end
	end
	-- back wall + rack
	box(s, "BackWall", V(11.4, 7.5, 0.35), base + V(0, 4.25, -3.4), Color3.fromHex("CDB48A"), Enum.Material.Fabric)
	box(s, "RackBeam", V(11.2, 0.5, 0.5), base + V(0, 7.6, -3.0), C.TimberDark, Enum.Material.Wood)
	local rackApps = { "shovel_rusty", "shovel_digging", "shovel_heavy" }
	for i, appId in ipairs(rackApps) do
		local x = (i - 2) * 3.6
		deco(box(s, "Hook", V(0.2, 0.5, 0.2), base + V(x, 7.1, -2.9), C.Iron, Enum.Material.Metal))
		local model = ToolModels.BuildPreview(Appearances.List[appId] and appId or "shovel_rusty")
		model.Name = "RackTool" .. i
		model:ScaleTo(0.6)
		model:PivotTo(CFrame.new(base + V(x, 4.85, -2.7)) * CFrame.Angles(math.pi, 0, 0)) -- blade down, hanging by the grip
		model.Parent = s
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
			end
		end
	end
	-- framed counter
	box(s, "CounterBody", V(11, 3.2, 2.2), base + V(0, 1.6, 2.4), C.TimberDark, Enum.Material.Wood)
	for _, sx in ipairs({ -3.6, 0, 3.6 }) do
		box(s, "CounterPanel", V(3.2, 2.3, 0.15), base + V(sx, 1.6, 3.55), C.TimberLight, Enum.Material.WoodPlanks)
	end
	box(s, "CounterTop", V(11.8, 0.4, 3.0), base + V(0, 3.4, 2.4), C.TimberLight, Enum.Material.WoodPlanks)
	box(s, "LanternBase", V(0.8, 0.9, 0.8), base + V(5.0, 4.05, 2.4), C.Iron, Enum.Material.Metal)
	deco(box(s, "LanternGlow", V(0.5, 0.6, 0.5), base + V(5.0, 4.8, 2.4), Color3.fromHex("FFD27A"), Enum.Material.Neon))
	-- canopy: muted teal, tipped forward, cream trim, timber beams
	for _, sz in ipairs({ -3.3, 3.3 }) do
		box(s, "CanopyBeam", V(12.6, 0.6, 0.6), base + V(0, 10.2, sz), C.TimberDark, Enum.Material.Wood)
	end
	part(s, "Canopy", V(13.8, 0.35, 9), CFrame.new(base + V(0, 11.2, -0.2)) * CFrame.Angles(math.rad(8), 0, 0), C.CanvasTeal, Enum.Material.Fabric)
	part(s, "CanopyTrim", V(13.8, 0.5, 0.45), CFrame.new(base + V(0, 10.55, 4.25)) * CFrame.Angles(math.rad(8), 0, 0), C.Trim, Enum.Material.Fabric)
	local board = box(s, "ShopSign", V(7, 1.8, 0.3), base + V(0, 9.0, 3.7), C.TimberDark, Enum.Material.Wood)
	sign(board, Enum.NormalId.Back, "EQUIPMENT", C.TimberDark, C.Trim)
	-- the existing shop prompt, now on the counter
	local anchor = box(s, "ShopAnchor", V(2, 1, 2), base + V(0, 4.6, 2.4), C.CanvasTeal)
	anchor.Transparency = 1
	deco(anchor)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ObjectText = "Equipment Shop"
	prompt.ActionText = "Browse"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor
end

-- Appraisal workstation: counter with a balance scale and ledger under a cream canopy, behind a restrained sell boundary ---
local function buildAppraisal(camp: Folder)
	local s = Instance.new("Folder")
	s.Name = "AppraisalStation"
	s.Parent = camp
	local sz = WorldCamp.SellZoneCenter -- the sell trigger centre (logic) = the marked circle (visual)
	local base = V(sz.X, 0.5, sz.Z - 12) -- the stall stands just north of the circle

	for _, sx in ipairs({ -5.5, 5.5 }) do
		for _, z in ipairs({ -2.6, 2.6 }) do
			box(s, "Post", V(0.8, 9, 0.8), base + V(sx, 4.5, z), C.Timber, Enum.Material.Wood)
		end
	end
	box(s, "BackWall", V(11, 6, 0.3), base + V(0, 3.5, -2.7), C.TimberDark, Enum.Material.WoodPlanks)
	box(s, "CounterBody", V(10, 3.0, 2.0), base + V(0, 1.5, 1.2), C.TimberDark, Enum.Material.Wood)
	box(s, "CounterTop", V(10.8, 0.4, 2.8), base + V(0, 3.2, 1.2), C.TimberLight, Enum.Material.WoodPlanks)
	for _, sx in ipairs({ -3.2, 0, 3.2 }) do
		box(s, "CounterPanel", V(2.8, 2.1, 0.15), base + V(sx, 1.5, 2.25), C.TimberLight, Enum.Material.WoodPlanks)
	end
	-- balance scale
	local sx0 = -2.2
	box(s, "ScaleBase", V(1.4, 0.3, 1.0), base + V(sx0, 3.55, 1.2), C.Iron, Enum.Material.Metal)
	box(s, "ScalePost", V(0.25, 1.7, 0.25), base + V(sx0, 4.55, 1.2), C.Iron, Enum.Material.Metal)
	box(s, "ScaleBeam", V(3.4, 0.2, 0.3), base + V(sx0, 5.45, 1.2), C.Iron, Enum.Material.Metal)
	for _, side in ipairs({ -1.6, 1.6 }) do
		deco(box(s, "ScaleString", V(0.05, 0.9, 0.05), base + V(sx0 + side, 4.95, 1.2), C.Iron, Enum.Material.Metal))
		cylinder(s, "ScalePan", 0.15, 1.1, base + V(sx0 + side, 4.45, 1.2), C.Gold, Enum.Material.Metal, true)
	end
	-- ledger
	box(s, "Ledger", V(1.3, 0.2, 0.95), base + V(2.4, 3.5, 1.2), C.TimberDark, Enum.Material.Wood)
	box(s, "LedgerPages", V(1.1, 0.14, 0.75), base + V(2.4, 3.65, 1.2), C.Trim, Enum.Material.Fabric)
	-- cream canopy + sign
	for _, z in ipairs({ -2.6, 2.6 }) do
		box(s, "CanopyBeam", V(11.8, 0.5, 0.5), base + V(0, 8.7, z), C.TimberDark, Enum.Material.Wood)
	end
	part(s, "Canopy", V(12.8, 0.35, 7.6), CFrame.new(base + V(0, 9.5, -0.1)) * CFrame.Angles(math.rad(7), 0, 0), C.CanvasCream, Enum.Material.Fabric)
	part(s, "CanopyTrim", V(12.8, 0.45, 0.4), CFrame.new(base + V(0, 8.95, 3.6)) * CFrame.Angles(math.rad(7), 0, 0), C.Timber, Enum.Material.Fabric)
	local board = box(s, "SellSign", V(6, 1.6, 0.3), base + V(0, 7.6, 3.0), C.TimberDark, Enum.Material.Wood)
	sign(board, Enum.NormalId.Back, "SELL FINDS", C.TimberDark, C.Trim)

	-- clearly marked sell area: a low tonal disc and a dashed boundary (the logic radius is Config.Camp.SellZoneRadius)
	local r = Config.Camp.SellZoneRadius
	cylinder(s, "SellDisc", 0.06, (r - 0.3) * 2, V(sz.X, 0.53, sz.Z), Color3.fromHex("CBA470"), Enum.Material.Sand, true)
	local dashes = 28
	for i = 0, dashes - 1 do
		local theta = i / dashes * math.pi * 2
		local pos = V(sz.X + math.cos(theta) * (r - 0.4), 0.55, sz.Z + math.sin(theta) * (r - 0.4))
		part(s, "SellDash", V(1.5, 0.05, 0.35), CFrame.new(pos) * CFrame.Angles(0, -(theta + math.pi / 2), 0), C.Gold, Enum.Material.SmoothPlastic)
	end
end

-- Artifact recovery area: where artifacts found in a mine that was reset are held for their owners. A roped pad beside the
-- mine entrance gate; it is NOT a deposit point (the receiving table is far away) - owners pick their artifact up here and
-- carry it to the receiving table themselves. -------------------------------------------------------------------------------
local function buildRecovery(camp: Folder)
	local folder = Instance.new("Folder")
	folder.Name = "RecoveryArea"
	folder.Parent = camp
	local c = Config.Camp.RecoveryPosition
	local pad = box(folder, "RecoveryPad", V(8, 0.3, 5.6), V(c.X, 0.65, c.Z), Color3.fromHex("CDBE98"), Enum.Material.Fabric)
	sign(pad, Enum.NormalId.Top, "RECOVERY", Color3.fromHex("CDBE98"), C.TimberDark)
	local postH = 3.2
	for _, sx in ipairs({ -4, 4 }) do
		for _, sz in ipairs({ -2.8, 2.8 }) do
			box(folder, "Post", V(0.4, postH, 0.4), V(c.X + sx, 0.5 + postH / 2, c.Z + sz), C.TimberDark, Enum.Material.Wood)
		end
	end
	-- ropes along the long sides and the sign board spanning the rear posts (embedded in both, directly under their tops)
	for _, sz in ipairs({ 2.8 }) do
		rope(folder, V(c.X - 4, 2.4, c.Z + sz), V(c.X + 4, 2.4, c.Z + sz))
	end
	for _, sx in ipairs({ -4, 4 }) do
		rope(folder, V(c.X + sx, 2.4, c.Z - 2.8), V(c.X + sx, 2.4, c.Z + 2.8))
	end
	local board = box(folder, "RecoverySign", V(8.4, 1.1, 0.25), V(c.X, 0.5 + postH - 0.55, c.Z - 2.8), C.TimberDark, Enum.Material.Wood)
	sign(board, Enum.NormalId.Back, "ARTIFACT RECOVERY", C.TimberDark, C.Gold)
end

-- Artifact receiving table: distinct from selling (cream cloth on a timber frame, plaque, deposit prompt) ----------------
local function buildReceiving(camp: Folder)
	local folder = Instance.new("Folder")
	folder.Name = "ReceivingTable"
	folder.Parent = camp
	local c = WorldCamp.ReceivingCenter
	local base = V(c.X, 0.5, c.Z)
	for _, sx in ipairs({ -2.5, 2.5 }) do
		for _, sz in ipairs({ -1.5, 1.5 }) do
			box(folder, "Leg", V(0.7, 2.6, 0.7), base + V(sx, 1.3, sz), C.Timber, Enum.Material.Wood)
		end
	end
	box(folder, "RailFront", V(5.7, 0.4, 0.4), base + V(0, 2.5, 1.5), C.TimberDark, Enum.Material.Wood)
	box(folder, "RailBack", V(5.7, 0.4, 0.4), base + V(0, 2.5, -1.5), C.TimberDark, Enum.Material.Wood)
	box(folder, "RailL", V(0.4, 0.4, 3.0), base + V(-2.5, 2.5, 0), C.TimberDark, Enum.Material.Wood)
	box(folder, "RailR", V(0.4, 0.4, 3.0), base + V(2.5, 2.5, 0), C.TimberDark, Enum.Material.Wood)
	box(folder, "TableTop", V(6.2, 0.4, 4.0), base + V(0, 2.8, 0), C.TimberLight, Enum.Material.Wood)
	box(folder, "ClothPad", V(5.6, 0.35, 3.4), base + V(0, 3.18, 0), C.Trim, Enum.Material.Fabric)
	box(folder, "ClothDrape", V(5.6, 1.0, 0.15), base + V(0, 2.6, 2.05), C.Trim, Enum.Material.Fabric)
	local plaque = box(folder, "Plaque", V(3.2, 0.8, 0.2), base + V(0, 2.6, 2.2), C.TimberDark, Enum.Material.Wood)
	sign(plaque, Enum.NormalId.Back, "ARTIFACT RECEIVING", C.TimberDark, C.Gold)
	-- a timber arch behind the table marks it from a distance
	for _, sx in ipairs({ -3.4, 3.4 }) do
		box(folder, "ArchPost", V(0.6, 7, 0.6), base + V(sx, 3.5, -2.3), C.Timber, Enum.Material.Wood)
	end
	box(folder, "ArchBeam", V(7.6, 0.6, 0.6), base + V(0, 7, -2.3), C.TimberDark, Enum.Material.Wood)
	-- the sign spans post to post (embedded in both) and hangs directly under the beam: nothing floats
	local board = box(folder, "ArtifactsSign", V(6.5, 1.5, 0.25), base + V(0, 6.45, -2.3), C.TimberDark, Enum.Material.Wood)
	sign(board, Enum.NormalId.Back, "ARTIFACTS", C.TimberDark, C.Trim)

	local anchor = box(folder, "DepositAnchor", V(2, 1, 2), base + V(0, 4.0, 0), C.CanvasTeal)
	anchor.Transparency = 1
	deco(anchor)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DepositPrompt"
	prompt.ObjectText = "Receiving Table"
	prompt.ActionText = "Deposit artifact"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	-- lost & found pad: fallback drop point (death/disconnect)
	local lf = WorldCamp.LostFoundPosition
	local pad = box(folder, "LostFoundPad", V(4, 0.3, 4), V(lf.X, 0.65, lf.Z), Color3.fromHex("CDBE98"), Enum.Material.Fabric)
	sign(pad, Enum.NormalId.Top, "LOST & FOUND", Color3.fromHex("CDBE98"), C.TimberDark)
end

function WorldCamp.Build(world: Folder, ex)
	local camp = Instance.new("Folder")
	camp.Name = "BaseCamp"
	camp.Parent = world
	buildGround(camp, ex)

	-- spawn: a thin invisible pad (the visible surface is the camp floor / route, not a gold platform)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "CampSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 0.2, 10)
	spawn.CFrame = CFrame.new(Config.Camp.SpawnPosition + Vector3.new(0, 0.6, 0))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false -- a marker only: the camp floor is what players stand on, so the pad can never snag a step
	spawn.CanQuery = false
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = camp

	buildFence(camp, ex)
	buildEntrance(camp)
	buildShop(camp)
	buildAppraisal(camp)
	buildReceiving(camp)
	buildRecovery(camp)
end

return WorldCamp
