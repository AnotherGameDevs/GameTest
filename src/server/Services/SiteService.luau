-- Owns the excavation grid. Cell state lives in flat arrays; Part instances exist only for
-- *exposed* cells (those touching air), so the instance count stays tiny even for a big site.
-- Each generation has TWO seeds: a fresh server-only LOOT seed (placement of rewards and pockets, never sent anywhere) and a
-- cosmetic seed (colour variation and remnants). Reset timing and the state machine live in MineShiftService / MineLifecycle.
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Grid = require(ReplicatedStorage.Shared.Grid)
local MineStyle = require(ReplicatedStorage.Shared.MineStyle)
local LootPlan = require(ReplicatedStorage.Shared.LootPlan)
local LootBoard = require(ReplicatedStorage.Shared.LootBoard)
local MineDetails = require(script.Parent.MineDetails)

local SiteService = {}

local health: { number } = {}
local maxHealth: { number } = {}
local board = LootBoard.new(0, {})
local parts: { [number]: Part } = {}
local pocketOf: { [number]: string } = {} -- cell -> discovery pocket kind
local detailBuilt: { [number]: boolean } = {}
local liveDetails = 0
local liveDetailParts = 0
local detailPartCount: { [number]: number } = {}
local currentSeed = 0
local generationCounts: { [string]: number } = {}
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
	if liveDetails >= Config.Mine.MaxDetails or liveDetailParts >= Config.Mine.MaxDetailParts then
		return
	end
	local x, y, z = Grid.FromIndex(idx)
	local layer = Defs.LayerAtCell(y)
	local spec = MineStyle.Detail(x, y, z, layer.Id, currentSeed, board:Peek(idx), pocketOf[idx])
	if not spec then
		return
	end
	local isExitWall = SiteService.IsExitWall(x, z)
	for i = 0, 5 do
		local face = (spec.FaceRot + i) % 6 + 1
		if faceOpen(x, y, z, face) and not (isExitWall and face == 3) then
			local specs = MineDetails.Specs(spec, Defs.Treasure)
			if #specs == 0 or liveDetailParts + #specs > Config.Mine.MaxDetailParts then
				return
			end
			local n = MineDetails.Build(specs, spec.Tell and "tell" or spec.Kind, part, part.Position, FACE_NORMALS[face])
			if n > 0 then
				detailBuilt[idx] = true
				detailPartCount[idx] = n
				liveDetails += 1
				liveDetailParts += n
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

-- Builds a brand-new mine. `lootSeed` defaults to a FRESH random server-only value (never a constant, never derived from
-- the cosmetic seed or sent to clients); `cosmeticSeed` only varies colours/remnants. Returns the new generation number.
function SiteService.Generate(lootSeedIn: number?, cosmeticSeedIn: number?)
	generation += 1
	local lootSeed: number = lootSeedIn or Random.new():NextInteger(1, 2147483646)
	local cosmeticSeed: number = cosmeticSeedIn or (Config.Site.Seed + generation * 7919)
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "DigSite"
	folder:SetAttribute("Generation", generation)
	folder.Parent = Workspace

	table.clear(health)
	table.clear(maxHealth)
	table.clear(parts)
	table.clear(pocketOf)
	table.clear(detailBuilt)
	table.clear(detailPartCount)
	liveDetails = 0
	liveDetailParts = 0
	currentSeed = cosmeticSeed
	table.clear(dugByLayer)
	table.clear(cellsByLayer)
	dugTotal = 0
	generatedAt = os.clock()

	for idx = 1, Grid.Count do
		local _, y = Grid.FromIndex(idx)
		local layer = Defs.LayerAtCell(y)
		health[idx] = layer.Health
		maxHealth[idx] = layer.Health
		cellsByLayer[layer.Id] = (cellsByLayer[layer.Id] or 0) + 1
	end

	-- Reward placement: rolled ONCE here (layer tables, per-generation limits on important artifacts, random pockets) from
	-- the fresh loot seed. A rejoining player never triggers this; only a completed reset does.
	local plan = LootPlan.Generate(Random.new(lootSeed), lootSeed)
	board = LootBoard.new(generation, plan.Loot)
	for _, pocket in ipairs(plan.Pockets) do
		for _, c in ipairs(pocket.Cells) do
			pocketOf[Grid.ToIndex(c[1], c[2], c[3])] = pocket.Kind
		end
	end
	generationCounts = plan.Counts

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

-- Depletion for the reset policy: the fraction of DIGGABLE cells already removed, where diggable = layers that a tool of
-- tier `maxTier` (the best tool among players online) can break. Also the whole-mine fraction and the generation's age.
function SiteService.Depletion(maxTier: number?)
	local tier = maxTier or 1
	local dug, total = 0, 0
	for _, layer in ipairs(Config.Layers) do
		if (layer.MinToolTier or 1) <= tier then
			dug += dugByLayer[layer.Id] or 0
			total += cellsByLayer[layer.Id] or 0
		end
	end
	return {
		Diggable = dug / math.max(total, 1),
		Total = dugTotal / math.max(Grid.Count, 1),
		AgeMinutes = (os.clock() - generatedAt) / 60,
		Generation = generation,
	}
end

function SiteService.Generation(): number
	return generation
end

-- Counts of each treasure buried in this generation (server-side diagnostics only; never replicated).
function SiteService.BuriedCounts(): { [string]: number }
	return generationCounts
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
		local treasure = board:Claim(idx, generation) -- exactly once, only for this generation
		local part = parts[idx]
		parts[idx] = nil
		if detailBuilt[idx] then
			detailBuilt[idx] = nil
			liveDetails -= 1
			liveDetailParts -= detailPartCount[idx] or 0
			detailPartCount[idx] = nil
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
