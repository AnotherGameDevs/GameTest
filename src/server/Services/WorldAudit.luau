-- Runtime self-check run at the end of WorldBuilder.Build(): proves nothing from the world builder sits inside the mine
-- volume (only dig cells, which are not built here, and the designated Bedrock may) or inside the elevator shaft (only the
-- Elevator folder may). It reports offenders by path in the server Output instead of hiding them. Pure geometry, no
-- transparency or offset tricks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Grid)

local WorldAudit = {}

local EPS = 0.05 -- parts that merely touch a boundary are fine

local function aabb(p: BasePart)
	local cf, s = p.CFrame, p.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local function half(ax: string): number
		return (math.abs(r[ax]) * s.X + math.abs(u[ax]) * s.Y + math.abs(l[ax]) * s.Z) / 2
	end
	local c = cf.Position
	local hx, hy, hz = half("X"), half("Y"), half("Z")
	return { c.X - hx, c.X + hx, c.Y - hy, c.Y + hy, c.Z - hz, c.Z + hz }
end

local function overlaps(a, b)
	return a[1] < b[2] - EPS and b[1] < a[2] - EPS and a[3] < b[4] - EPS and b[3] < a[4] - EPS and a[5] < b[6] - EPS and b[5] < a[6] - EPS
end

function WorldAudit.Run(world: Instance): { Checked: number, Offenders: { string } }
	local b = Grid.Bounds()
	local mine = { b.MinX, b.MaxX, b.BottomY, b.TopY, b.MinZ, b.MaxZ }
	local shaft
	local ex = Config.Exit
	if ex.Enabled then
		shaft = { ex.CenterX - ex.Width / 2, ex.CenterX + ex.Width / 2, b.BottomY - 12, b.TopY + 60, b.MaxZ, b.MaxZ + ex.Run }
	end
	local offenders, checked = {}, 0
	for _, d in ipairs(world:GetDescendants()) do
		if d:IsA("BasePart") then
			checked += 1
			local box = aabb(d)
			if overlaps(box, mine) and d.Name ~= "Bedrock" then
				table.insert(offenders, "inside the MINE: " .. d:GetFullName())
			elseif shaft and overlaps(box, shaft) and not d:FindFirstAncestor("Elevator") then
				table.insert(offenders, "inside the SHAFT: " .. d:GetFullName())
			end
		end
	end
	if #offenders == 0 then
		print(("[WorldAudit] OK: %d world parts checked, none inside the mine volume or the elevator shaft."):format(checked))
	else
		warn(("[WorldAudit] %d overlap(s):\n  %s"):format(#offenders, table.concat(offenders, "\n  ")))
	end
	return { Checked = checked, Offenders = offenders }
end

return WorldAudit
