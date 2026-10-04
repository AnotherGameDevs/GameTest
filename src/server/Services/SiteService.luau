-- Owns the excavation grid. Cell state lives in flat arrays; Part instances exist only for
-- *exposed* cells (those touching air), so the instance count stays tiny even for a big site.
-- Generation is seeded, so the site can be reset/regenerated cleanly (future "Excavation Shift").
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Grid = require(ReplicatedStorage.Shared.Grid)
local MineStyle = require(ReplicatedStorage.Shared.MineStyle)
local MineDetails = require(script.Parent.MineDetails)

local SiteService = {}

local health: { number } = {}
local maxHealth: { number } = {}
local loot: { [number]: string } = {}
local parts: { [number]: Part } = {}
local pocketOf: { [number]: string } = {} -- cell -> discovery pocket kind
local detailBuilt: { [number]: boolean } = {}
local liveDetails = 0
local currentSeed = 0
local folder: Folder
local generation = 0
local dugTotal = 0
local dugByLayer: { [string]: number } = {}
local cellsByLayer: { [string]: number } = {}
local generatedAt = os.clock()

local FACE_NORMALS = { Vector3.yAxis, Vector3.xAxis, Vector3.zAxis, -Vector3.xAxis, -Vector3.zAxis, -Vector3.yAxis }
local FACE_STEP = { { 0, -1, 0 }, { 1, 0, 0 }, { 0, 0, 1 }, { -1, 0, 0 }, { 0, 0, -1 }, { 0, 1, 0 } } -- cell offset behind each normal (y grows downward)

-- A face is "open" when its neighbour is air (a dug cell), the sky above the top row, or the exit shaft beside the grid.
-- The exit shaft's own face is never decorated (it is the way out and must stay clean).
local function faceOpen(x: number, y: number, z: number, face: number): boolean
	local o = FACE_STEP[face]
	local nx, ny, nz = x + o[1], y + o[2], z + o[3]
	if not Grid.InBounds(nx, ny, nz) then
		return face == 1 and y == 0 -- only the open sky above the surface row
	end
	return (health[Grid.ToIndex(nx, ny, nz)] or 0) <= 0
end

-- Builds the cell's remnant if it has one and one of its faces is now open. Safe to call repeatedly.
local function ensureDetail(idx: number)
	local part = parts[idx]
	if not part or detailBuilt[idx] or (health[idx] or 0) <= 0 then
		return
	end
	if liveDetails >= Config.Mine.MaxDetails then
		return
	end
	local x, y, z = Grid.FromIndex(idx)
	local layer = Defs.LayerAtCell(y)
	local spec = MineStyle.Detail(x, y, z, layer.Id, currentSeed, loot[idx], pocketOf[idx])
	if not spec then
		return
	end
	local isExitWall = SiteService.IsExitWall(x, z)
	for i = 0, 5 do
		local face = (spec.FaceRot + i) % 6 + 1
		if faceOpen(x, y, z, face) and not (isExitWall and face == 3) then
			local n = MineDetails.Build(spec.Kind, spec.Variant, part, part.Position, FACE_NORMALS[face])
			if n > 0 then
				detailBuilt[idx] = true
				liveDetails += 1
			end
			return
		end
	end
end

local function spawnPart(idx: number)
	if parts[idx] then
		return
	end
	local x, y, z = Grid.FromIndex(idx)
	local layer = Defs.LayerAtCell(y)
	local style = MineStyle.Cell(x, y, z, layer.Id, currentSeed, pocketOf[idx])
	local part = Instance.new("Part")
	part.Name = tostring(idx)
	part.Anchored = true
	part.Size = Vector3.one * Grid.CellSize
	part.Position = Grid.CellCenter(x, y, z)
	part.Material = Enum.Material[style.Material]
	part.Color = Color3.fromHex(style.Hex)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanTouch = false
	part.Parent = folder
	parts[idx] = part
	ensureDetail(idx)
end

-- Cells on the grid's south edge that border the exit shaft (see Config.Exit).
function SiteService.IsExitWall(x: number, z: number): boolean
	local ex = Config.Exit
	if not ex.Enabled or z ~= Grid.SizeZ - 1 then
		return false
	end
	local x0 = Grid.OriginX + x * Grid.CellSize
	-- only the LANDING half (left of the shaft centre); the car half of the grid face is covered by an iron plate
	return x0 >= ex.CenterX - ex.Width / 2 - 1e-3 and x0 + Grid.CellSize <= ex.CenterX + 1e-3
end

function SiteService.Generate(seedIn: number?)
	generation += 1
	local seed: number = seedIn or Config.Site.Seed
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "DigSite"
	folder.Parent = Workspace

	table.clear(health)
	table.clear(maxHealth)
	table.clear(loot)
	table.clear(parts)
	table.clear(pocketOf)
	table.clear(detailBuilt)
	liveDetails = 0
	currentSeed = seed
	table.clear(dugByLayer)
	table.clear(cellsByLayer)
	dugTotal = 0
	generatedAt = os.clock()

	local rng = Random.new(seed)
	for idx = 1, Grid.Count do
		local _, y = Grid.FromIndex(idx)
		local layer = Defs.LayerAtCell(y)
		health[idx] = layer.Health
		cellsByLayer[layer.Id] = (cellsByLayer[layer.Id] or 0) + 1
		maxHealth[idx] = layer.Health
		if rng:NextNumber() < layer.TreasureChance then
			local id = Defs.PickTreasure(layer.Id, rng)
			if id then
				loot[idx] = id
			end
		end
	end

	-- Discovery pockets: compact, seeded, tier-appropriate arrangements (pottery cache / fossil patch / broken masonry).
	-- Their cells get a pocket tint, and their loot is the pocket's own (replacing whatever was rolled for those cells).
	for _, pocket in ipairs(MineStyle.Pockets(seed)) do
		for _, c in ipairs(pocket.Cells) do
			local pidx = Grid.ToIndex(c[1], c[2], c[3])
			pocketOf[pidx] = pocket.Kind
			loot[pidx] = c[4]
		end
	end

	-- Instance only the cells that start exposed: the top surface row, plus the wall of cells facing the exit shaft
	-- (open air beyond the grid edge), so players can dig through to the ladder from any depth.
	for idx = 1, Grid.Count do
		local x, y, z = Grid.FromIndex(idx)
		if y == 0 or SiteService.IsExitWall(x, z) then
			spawnPart(idx)
		end
	end
	return generation
end

-- Depletion figures used by the Fresh Dig refresh (docs/MINE_SHIFT.md). Fractions are of ALL cells / of a layer's cells.
function SiteService.Depletion()
	local byLayer = {}
	for layerId, total in pairs(cellsByLayer) do
		byLayer[layerId] = (dugByLayer[layerId] or 0) / math.max(total, 1)
	end
	return {
		Total = dugTotal / math.max(Grid.Count, 1),
		ByLayer = byLayer,
		AgeMinutes = (os.clock() - generatedAt) / 60,
		Generation = generation,
	}
end

function SiteService.IsAlive(idx: number): boolean
	return (health[idx] or 0) > 0
end

function SiteService.IsExposed(idx: number): boolean
	return parts[idx] ~= nil and (health[idx] or 0) > 0
end

function SiteService.GetPart(idx: number): Part?
	return parts[idx]
end

-- Applies damage. Returns (newHealthFraction, destroyed, treasureId?). Does NOT expose neighbours;
-- call SiteService.ExposeAround for destroyed cells once a whole hit has been resolved.
function SiteService.Damage(idx: number, amount: number): (number, boolean, string?)
	local hp = health[idx]
	if not hp or hp <= 0 then
		return 0, false, nil
	end
	hp -= amount
	if hp <= 0 then
		health[idx] = 0
		dugTotal += 1
		local _, dy = Grid.FromIndex(idx)
		local lid = Defs.LayerAtCell(dy).Id
		dugByLayer[lid] = (dugByLayer[lid] or 0) + 1
		local treasure = loot[idx]
		loot[idx] = nil
		local part = parts[idx]
		parts[idx] = nil
		if detailBuilt[idx] then
			detailBuilt[idx] = nil
			liveDetails -= 1
		end
		if part then
			part:Destroy()
		end
		return 0, true, treasure
	end
	health[idx] = hp
	return hp / maxHealth[idx], false, nil
end

function SiteService.ExposeAround(idx: number)
	local x, y, z = Grid.FromIndex(idx)
	for _, n in ipairs(Grid.Neighbours6) do
		local nx, ny, nz = x + n[1], y + n[2], z + n[3]
		if Grid.InBounds(nx, ny, nz) then
			local ni = Grid.ToIndex(nx, ny, nz)
			if health[ni] > 0 and not parts[ni] then
				spawnPart(ni)
			elseif parts[ni] then
				ensureDetail(ni) -- a new face of an already-visible cell just opened
			end
		end
	end
end

-- Cells (that currently have a Part) within `radius` cells (Chebyshev) of the target, excluding it.
function SiteService.ExposedNeighbours(idx: number, radius: number): { number }
	local out = {}
	if radius <= 0 then
		return out
	end
	local x, y, z = Grid.FromIndex(idx)
	for dx = -radius, radius do
		for dy = -radius, radius do
			for dz = -radius, radius do
				if not (dx == 0 and dy == 0 and dz == 0) then
					local nx, ny, nz = x + dx, y + dy, z + dz
					if Grid.InBounds(nx, ny, nz) then
						local ni = Grid.ToIndex(nx, ny, nz)
						if parts[ni] and health[ni] > 0 then
							table.insert(out, ni)
						end
					end
				end
			end
		end
	end
	return out
end

-- Picks at most `maxExtra` exposed neighbours to also take splash damage. Closest to the target block first
-- (face-adjacent before edge/corner), ties broken by nearness to the player, then by index for determinism.
function SiteService.PickSplash(idx: number, radius: number, maxExtra: number, fromPos: Vector3): { number }
	local candidates = SiteService.ExposedNeighbours(idx, radius)
	if #candidates <= maxExtra then
		return candidates
	end
	local tx, ty, tz = Grid.FromIndex(idx)
	local targetCenter = Grid.CellCenter(tx, ty, tz)
	local scored = {}
	for _, ni in ipairs(candidates) do
		local x, y, z = Grid.FromIndex(ni)
		local c = Grid.CellCenter(x, y, z)
		table.insert(scored, { Index = ni, D1 = (c - targetCenter).Magnitude, D2 = (c - fromPos).Magnitude })
	end
	table.sort(scored, function(a, b)
		if math.abs(a.D1 - b.D1) > 1e-3 then
			return a.D1 < b.D1
		end
		if math.abs(a.D2 - b.D2) > 1e-3 then
			return a.D2 < b.D2
		end
		return a.Index < b.Index
	end)
	local out = {}
	for i = 1, maxExtra do
		out[i] = scored[i].Index
	end
	return out
end

-- The (up to) `maxCells` alive cells nearest to `pos` within `radius` cells of the cell containing it.
-- Used by explosives; hidden interior cells count (they are exposed afterwards like any dug cell).
function SiteService.CellsNear(pos: Vector3, radius: number, maxCells: number, allow: ((number) -> boolean)?): { number }
	local cx, cy, cz = Grid.WorldToCell(pos)
	local found = {}
	for dx = -radius, radius do
		for dy = -radius, radius do
			for dz = -radius, radius do
				local x, y, z = cx + dx, cy + dy, cz + dz
				if Grid.InBounds(x, y, z) then
					local idx = Grid.ToIndex(x, y, z)
					if (health[idx] or 0) > 0 and (not allow or allow(y)) then
						table.insert(found, { Index = idx, D = (Grid.CellCenter(x, y, z) - pos).Magnitude })
					end
				end
			end
		end
	end
	table.sort(found, function(a, b)
		if math.abs(a.D - b.D) > 1e-3 then
			return a.D < b.D
		end
		return a.Index < b.Index
	end)
	local out = {}
	for i = 1, math.min(maxCells, #found) do
		out[i] = found[i].Index
	end
	return out
end

return SiteService
