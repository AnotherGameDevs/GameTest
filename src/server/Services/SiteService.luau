-- Owns the excavation grid. Cell state lives in flat arrays; Part instances exist only for
-- *exposed* cells (those touching air), so the instance count stays tiny even for a big site.
-- Generation is seeded, so the site can be reset/regenerated cleanly (future "Excavation Shift").
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Grid = require(ReplicatedStorage.Shared.Grid)

local SiteService = {}

local health: { number } = {}
local maxHealth: { number } = {}
local loot: { [number]: string } = {}
local parts: { [number]: Part } = {}
local tints: { number } = {}
local folder: Folder
local generation = 0

local function spawnPart(idx: number)
	if parts[idx] then
		return
	end
	local x, y, z = Grid.FromIndex(idx)
	local layer = Defs.LayerAtCell(y)
	local part = Instance.new("Part")
	part.Name = tostring(idx)
	part.Anchored = true
	part.Size = Vector3.one * Grid.CellSize
	part.Position = Grid.CellCenter(x, y, z)
	part.Material = Enum.Material.SmoothPlastic
	part.Color = layer.Color:Lerp(tints[idx] > 0 and Color3.new(1, 1, 1) or Color3.new(0, 0, 0), math.abs(tints[idx]))
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanTouch = false
	part.Parent = folder
	parts[idx] = part
end

-- Cells on the grid's south edge that border the exit shaft (see Config.Exit).
function SiteService.IsExitWall(x: number, z: number): boolean
	local ex = Config.Exit
	if not ex.Enabled or z ~= Grid.SizeZ - 1 then
		return false
	end
	local x0 = Grid.OriginX + x * Grid.CellSize
	return x0 >= ex.CenterX - ex.Width / 2 - 1e-3 and x0 + Grid.CellSize <= ex.CenterX + ex.Width / 2 + 1e-3
end

function SiteService.Generate(seed: number?)
	generation += 1
	seed = seed or Config.Site.Seed
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
	table.clear(tints)

	local rng = Random.new(seed)
	for idx = 1, Grid.Count do
		local _, y = Grid.FromIndex(idx)
		local layer = Defs.LayerAtCell(y)
		health[idx] = layer.Health
		maxHealth[idx] = layer.Health
		tints[idx] = (rng:NextNumber() - 0.5) * 0.16
		if rng:NextNumber() < layer.TreasureChance then
			local id = Defs.PickTreasure(layer.Id, rng)
			if id then
				loot[idx] = id
			end
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
		local treasure = loot[idx]
		loot[idx] = nil
		local part = parts[idx]
		parts[idx] = nil
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
function SiteService.CellsNear(pos: Vector3, radius: number, maxCells: number): { number }
	local cx, cy, cz = Grid.WorldToCell(pos)
	local found = {}
	for dx = -radius, radius do
		for dy = -radius, radius do
			for dz = -radius, radius do
				local x, y, z = cx + dx, cy + dy, cz + dz
				if Grid.InBounds(x, y, z) then
					local idx = Grid.ToIndex(x, y, z)
					if (health[idx] or 0) > 0 then
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
