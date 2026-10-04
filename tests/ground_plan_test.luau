-- Run via tests/run_all.sh (needs the prepared shared modules).
-- Proves the ground around the mine is built from the configured mine bounds: no ground rectangle can overlap the mine
-- footprint or the elevator shaft, the rectangles tile (outer minus holes) exactly, and none overlap each other.
local Config = require("./_build/shared/Config")
local Grid = require("./_build/shared/Grid")
local GroundPlan = require("./_build/shared/GroundPlan")

local passed, failed = 0, 0
local function check(name, cond, detail) if cond then passed += 1 else failed += 1; print("FAIL: " .. name .. (detail and ("  -> " .. detail) or "")) end end

local function plan(outer, holes)
	local rects = GroundPlan.Subtract(outer, holes)
	local holeArea = 0
	for _, h in ipairs(holes) do holeArea += GroundPlan.Area(h) end
	local area = 0
	for _, r in ipairs(rects) do area += GroundPlan.Area(r) end
	return rects, area, holeArea
end

-- the real world: outer = map boundary, holes = mine footprint + elevator shaft (derived from Config, not hardcoded)
local b = Grid.Bounds()
local ex = Config.Exit
local ext = Config.World.BoundaryExtent
local outer = { -ext, ext, -ext, ext }
local mine = { b.MinX, b.MaxX, b.MinZ, b.MaxZ }
local shaft = { ex.CenterX - ex.Width / 2, ex.CenterX + ex.Width / 2, b.MaxZ, b.MaxZ + ex.Run }
local rects, area, holeArea = plan(outer, { mine, shaft })

check("real world: some rectangles produced", #rects >= 4 and #rects <= 12, tostring(#rects))
for i, r in ipairs(rects) do
	check("rect " .. i .. " does not overlap the mine", not GroundPlan.Overlaps(r, mine))
	check("rect " .. i .. " does not overlap the shaft", not GroundPlan.Overlaps(r, shaft))
	for j = i + 1, #rects do
		check(("rects %d/%d do not overlap"):format(i, j), not GroundPlan.Overlaps(r, rects[j]))
	end
end
check("area conserved (outer - holes)", math.abs(area - (GroundPlan.Area(outer) - holeArea)) < 1e-3,
	("%.1f vs %.1f"):format(area, GroundPlan.Area(outer) - holeArea))

-- every sampled point outside the holes is covered; every point inside a hole is not
local function inRect(r, x, z) return x > r[1] and x < r[2] and z > r[3] and z < r[4] end
local bad = 0
for x = -ext + 3.7, ext - 3.7, 7.3 do
	for z = -ext + 3.1, ext - 3.1, 6.9 do
		local inHole = inRect(mine, x, z) or inRect(shaft, x, z)
		local covered = false
		for _, r in ipairs(rects) do if inRect(r, x, z) then covered = true end end
		if inHole == covered then bad += 1 end
	end
end
check("sampled coverage: ground everywhere except the holes", bad == 0, tostring(bad) .. " bad samples")

-- every other ground piece the camp builder makes is produced from the same holes (or sits clearly outside them)
do
	local holes = { mine, shaft }
	local camp = Config.Camp
	local floorRect = { camp.Position.X - camp.Size.X / 2, camp.Position.X + camp.Size.X / 2, camp.Position.Z - camp.Size.Z / 2, camp.Position.Z + camp.Size.Z / 2 }
	check("camp floor does not overlap the mine", not GroundPlan.Overlaps(floorRect, mine))
	check("camp floor does not overlap the shaft", not GroundPlan.Overlaps(floorRect, shaft))
	local apron = GroundPlan.Subtract({ floorRect[1] - 3, floorRect[2] + 3, floorRect[3], floorRect[4] + 3 }, holes)
	for i, r in ipairs(apron) do
		check("camp apron piece " .. i .. " is clear of the mine and shaft", not GroundPlan.Overlaps(r, mine) and not GroundPlan.Overlaps(r, shaft))
	end
	local rim = 8
	local ring = GroundPlan.Subtract({ b.MinX - rim, b.MaxX + rim, b.MinZ - rim, b.MaxZ + rim }, holes)
	for i, r in ipairs(ring) do
		check("gravel rim piece " .. i .. " is clear of the mine and shaft", not GroundPlan.Overlaps(r, mine) and not GroundPlan.Overlaps(r, shaft))
	end
	-- boardwalk (x +-6, from the grid edge to the gate) and the route strip start at the edge; neither enters the mine
	local boardwalk = { -6, 6, b.MaxZ, camp.EntranceZ - 0.5 }
	check("boardwalk is clear of the mine", not GroundPlan.Overlaps(boardwalk, mine))
	check("boardwalk is clear of the shaft", not GroundPlan.Overlaps(boardwalk, shaft))
	local route = { -6, 6, floorRect[3], floorRect[4] }
	check("route is clear of the mine and shaft", not GroundPlan.Overlaps(route, mine) and not GroundPlan.Overlaps(route, shaft))
	-- the far ground is a frame OUTSIDE the playable square
	for i, r in ipairs({ { -700, 700, -700, -ext }, { -700, 700, ext, 700 }, { -700, -ext, -ext, ext }, { ext, 700, -ext, ext } }) do
		check("far-ground piece " .. i .. " is outside the playable square (cannot reach the mine)", not GroundPlan.Overlaps(r, { -ext, ext, -ext, ext }) and not GroundPlan.Overlaps(r, mine))
	end
end

-- the mine volume is the only thing in Grid.Bounds: sanity against the configured grid
check("Grid.Bounds matches the configured grid", b.MaxX - b.MinX == Config.Site.SizeX * Config.Site.CellSize
	and b.MaxZ - b.MinZ == Config.Site.SizeZ * Config.Site.CellSize
	and b.TopY - b.BottomY == Config.Site.Depth * Config.Site.CellSize)

-- the plan follows the configuration: shrink/grow the grid and the opening follows
do
	local r2, a2, h2 = plan({ -100, 100, -100, 100 }, { { -20, 20, -20, 20 } })
	check("synthetic: centre hole", #r2 >= 4 and math.abs(a2 - (40000 - 1600)) < 1e-6 and h2 == 1600)
	local r3, a3 = plan({ 0, 10, 0, 10 }, { { 0, 4, 0, 10 } })
	check("synthetic: hole touching an edge", #r3 == 1 and math.abs(a3 - 60) < 1e-6)
	local r4, a4 = plan({ 0, 10, 0, 10 }, { { 2, 4, 2, 4 }, { 6, 8, 6, 8 } })
	check("synthetic: two separate holes", math.abs(a4 - (100 - 8)) < 1e-6)
	local r5, a5 = plan({ 0, 10, 0, 10 }, { { -5, 15, -5, 15 } })
	check("synthetic: hole covering everything leaves nothing", #r5 == 0 and a5 == 0)
	local r6, a6 = plan({ 0, 10, 0, 10 }, {})
	check("synthetic: no holes -> one rectangle", #r6 == 1 and a6 == 100)
end

print(("ground plan tests: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("tests failed") end
