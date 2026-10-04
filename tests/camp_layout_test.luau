-- Run via tests/run_all.sh. Checks the camp layout rules straight from Config (the same data the builders, the spawn,
-- the sell trigger, the deposit check and the UI use), so a change that breaks spacing fails here.
local Config = require("./_build/shared/Config")
local Grid = require("./_build/shared/Grid")

local passed, failed = 0, 0
local function check(name, cond, detail) if cond then passed += 1 else failed += 1; print("FAIL: " .. name .. (detail and ("  -> " .. detail) or "")) end end

local camp = Config.Camp
local b = Grid.Bounds()
local ex = Config.Exit
local spawn = camp.SpawnPosition
local fp = camp.Footprints
local floor = { x0 = camp.Position.X - camp.Size.X / 2, x1 = camp.Position.X + camp.Size.X / 2,
	z0 = camp.Position.Z - camp.Size.Z / 2, z1 = camp.Position.Z + camp.Size.Z / 2 }

local function rectOf(f) return { f.Center.X - f.HalfX, f.Center.X + f.HalfX, f.Center.Z - f.HalfZ, f.Center.Z + f.HalfZ } end
local function overlap(a, b2) return a[1] < b2[2] and b2[1] < a[2] and a[3] < b2[4] and b2[3] < a[4] end
local function circleHitsRect(cx, cz, r, rc)
	local nx, nz = math.max(rc[1], math.min(cx, rc[2])), math.max(rc[3], math.min(cz, rc[4]))
	return (nx - cx) ^ 2 + (nz - cz) ^ 2 < r * r
end

-- walking distance spawn -> mine entrance (straight line along the route)
local dist = math.sqrt((spawn.X - 0) ^ 2 + (spawn.Z - camp.EntranceZ) ^ 2)
check("spawn is 35-45 studs from the mine entrance", dist >= 35 and dist <= 45, ("%.1f"):format(dist))

-- arrival area: 16 x 16 around the spawn is empty
local h = camp.ArrivalHalfSize
local arrival = { spawn.X - h, spawn.X + h, spawn.Z - h, spawn.Z + h }
for name, f in pairs(fp) do
	check("arrival area clear of " .. name, not overlap(arrival, rectOf(f)))
end
check("arrival area clear of the sell zone", not circleHitsRect(camp.SellZoneCenter.X, camp.SellZoneCenter.Z, camp.SellZoneRadius, arrival))
check("arrival area clear of the lost & found pad", not overlap(arrival, { camp.LostFoundPosition.X - 2, camp.LostFoundPosition.X + 2, camp.LostFoundPosition.Z - 2, camp.LostFoundPosition.Z + 2 }))
check("arrival area is on the camp floor", arrival[1] >= floor.x0 and arrival[2] <= floor.x1 and arrival[3] >= floor.z0 and arrival[4] <= floor.z1)

-- the entrance is visible from the spawn: the corridor x in [-6, 6] between spawn and gate is empty
local corridor = { -6, 6, camp.EntranceZ, spawn.Z }
for name, f in pairs(fp) do
	check("sightline to the entrance clear of " .. name, not overlap(corridor, rectOf(f)))
end
check("sightline clear of the sell zone", not circleHitsRect(camp.SellZoneCenter.X, camp.SellZoneCenter.Z, camp.SellZoneRadius, corridor))

-- stations beside the route with >= 12 studs of walking width between them
local gap = (fp.Shop.Center.X - fp.Shop.HalfX) - (fp.Appraisal.Center.X + fp.Appraisal.HalfX)
check("walking width between shop and appraisal >= 12", gap >= camp.MinStationGap, ("%.1f"):format(gap))
local sellEdge = camp.SellZoneCenter.X + camp.SellZoneRadius
check("sell zone also leaves >= 12 to the shop", fp.Shop.Center.X - fp.Shop.HalfX - sellEdge >= camp.MinStationGap)
check("shop on one side of the route, appraisal on the other", fp.Shop.Center.X > 0 and fp.Appraisal.Center.X < 0)

-- stations are well clear of the mine rim (grid edge) and of the elevator gantry
for name, f in pairs(fp) do
	check(name .. " >= 8 studs from the mine rim", f.Center.Z - f.HalfZ - b.MaxZ >= camp.MinRimClearance, ("%.1f"):format(f.Center.Z - f.HalfZ - b.MaxZ))
end
local gantryMaxZ = b.MaxZ + ex.Run + 4.8 + 0.6 -- gantry rear posts (WorldElevator)
check("receiving table >= 8 studs from the gantry", fp.Receiving.Center.Z - fp.Receiving.HalfZ - gantryMaxZ >= 8, ("%.1f"):format(fp.Receiving.Center.Z - fp.Receiving.HalfZ - gantryMaxZ))

-- deposit is a short walk from the elevator exit
local mouth = { X = ex.CenterX + ex.Width / 4, Z = b.MaxZ + ex.Run }
local walk = math.sqrt((camp.ReceivingPosition.X - mouth.X) ^ 2 + (camp.ReceivingPosition.Z - mouth.Z) ^ 2)
check("deposit point within 20 studs of the elevator exit", walk <= 20, ("%.1f"):format(walk))

-- no station footprint overlaps another (with 4 studs of breathing room) and everything is on the floor
local names = {}
for n in pairs(fp) do table.insert(names, n) end
table.sort(names)
for i = 1, #names do
	local r = rectOf(fp[names[i]])
	check(names[i] .. " is on the camp floor", r[1] >= floor.x0 and r[2] <= floor.x1 and r[3] >= floor.z0 and r[4] <= floor.z1)
	for j = i + 1, #names do
		local o = rectOf(fp[names[j]])
		local grown = { r[1] - 4, r[2] + 4, r[3] - 4, r[4] + 4 }
		check(names[i] .. " keeps clear of " .. names[j], not overlap(grown, o))
	end
end
check("sell disc is on the camp floor", camp.SellZoneCenter.X - camp.SellZoneRadius >= floor.x0 and camp.SellZoneCenter.X + camp.SellZoneRadius <= floor.x1
	and camp.SellZoneCenter.Z - camp.SellZoneRadius >= floor.z0 and camp.SellZoneCenter.Z + camp.SellZoneRadius <= floor.z1)
check("spawn is on the camp floor", spawn.X >= floor.x0 and spawn.X <= floor.x1 and spawn.Z >= floor.z0 and spawn.Z <= floor.z1)
check("camp floor starts exactly at the shaft edge (never over the mine/shaft)", math.abs(floor.z0 - (b.MaxZ + ex.Run)) < 1e-6)

print(("camp layout tests: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("tests failed") end
