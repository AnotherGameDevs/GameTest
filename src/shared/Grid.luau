-- Pure grid math shared by server and client. Cell coordinates are 0-based integers (x, y, z);
-- y = 0 is the top row (surface), y grows downward.
local Config = require(script.Parent.Config)

local Grid = {}
local S = Config.Site

Grid.SizeX, Grid.SizeY, Grid.SizeZ = S.SizeX, S.Depth, S.SizeZ
Grid.CellSize = S.CellSize
Grid.Count = S.SizeX * S.Depth * S.SizeZ

local originX = S.Center.X - (S.SizeX * S.CellSize) / 2
local originZ = S.Center.Z - (S.SizeZ * S.CellSize) / 2
Grid.OriginX, Grid.OriginZ, Grid.SurfaceY = originX, originZ, S.Center.Y

function Grid.InBounds(x: number, y: number, z: number): boolean
	return x >= 0 and x < S.SizeX and y >= 0 and y < S.Depth and z >= 0 and z < S.SizeZ
end

function Grid.ToIndex(x: number, y: number, z: number): number
	return (y * S.SizeZ + z) * S.SizeX + x + 1
end

function Grid.FromIndex(i: number): (number, number, number)
	i -= 1
	local x = i % S.SizeX
	local rest = (i - x) // S.SizeX
	local z = rest % S.SizeZ
	local y = rest // S.SizeZ
	return x, y, z
end

function Grid.CellCenter(x: number, y: number, z: number): Vector3
	local c = S.CellSize
	return Vector3.new(originX + (x + 0.5) * c, Grid.SurfaceY - (y + 0.5) * c, originZ + (z + 0.5) * c)
end

function Grid.WorldToCell(p: Vector3): (number, number, number)
	local c = S.CellSize
	return math.floor((p.X - originX) / c), math.floor((Grid.SurfaceY - p.Y) / c), math.floor((p.Z - originZ) / c)
end

-- Depth in metres below the surface for a world Y (clamped at 0).
function Grid.DepthMeters(worldY: number): number
	return math.max(0, (Grid.SurfaceY - worldY) / S.StudsPerMeter)
end

Grid.Neighbours6 = {
	{ 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 },
}

return Grid
