-- Pure rectangle maths for building ground AROUND the mine. Given an outer rectangle and a list of "holes" (the mine
-- footprint, the elevator shaft, ...), returns non-overlapping rectangles that exactly tile (outer minus holes). Because
-- the opening is a hole in the plan, no ground piece can ever extend across the mine. Rectangles are {x0, x1, z0, z1}.
local GroundPlan = {}

local function intersectsInterval(a0, a1, b0, b1)
	return a0 < b1 and b0 < a1
end

-- Outer minus holes -> rectangles (adjacent identical strips are merged, so the part count stays small).
function GroundPlan.Subtract(outer, holes)
	local xs = { outer[1], outer[2] }
	for _, h in ipairs(holes) do
		if intersectsInterval(h[1], h[2], outer[1], outer[2]) then
			table.insert(xs, math.max(h[1], outer[1]))
			table.insert(xs, math.min(h[2], outer[2]))
		end
	end
	table.sort(xs)
	local uniq = {}
	for _, x in ipairs(xs) do
		if #uniq == 0 or x - uniq[#uniq] > 1e-6 then
			table.insert(uniq, x)
		end
	end

	local columns = {} -- each: { x0, x1, intervals = { {z0, z1}, ... } }
	for i = 1, #uniq - 1 do
		local xa, xb = uniq[i], uniq[i + 1]
		local cuts = {}
		for _, h in ipairs(holes) do
			if h[1] <= xa + 1e-6 and h[2] >= xb - 1e-6 and intersectsInterval(h[3], h[4], outer[3], outer[4]) then
				table.insert(cuts, { math.max(h[3], outer[3]), math.min(h[4], outer[4]) })
			end
		end
		table.sort(cuts, function(p, q) return p[1] < q[1] end)
		local intervals, cursor = {}, outer[3]
		for _, c in ipairs(cuts) do
			if c[1] > cursor + 1e-6 then
				table.insert(intervals, { cursor, c[1] })
			end
			cursor = math.max(cursor, c[2])
		end
		if outer[4] > cursor + 1e-6 then
			table.insert(intervals, { cursor, outer[4] })
		end
		table.insert(columns, { xa, xb, intervals })
	end

	-- merge neighbouring columns whose intervals are identical
	local merged = {}
	for _, col in ipairs(columns) do
		local last = merged[#merged]
		local same = last and #last[3] == #col[3]
		if same then
			for k = 1, #col[3] do
				if math.abs(last[3][k][1] - col[3][k][1]) > 1e-6 or math.abs(last[3][k][2] - col[3][k][2]) > 1e-6 then
					same = false
					break
				end
			end
		end
		if same then
			last[2] = col[2]
		else
			table.insert(merged, { col[1], col[2], col[3] })
		end
	end

	local rects = {}
	for _, col in ipairs(merged) do
		for _, iv in ipairs(col[3]) do
			table.insert(rects, { col[1], col[2], iv[1], iv[2] })
		end
	end
	return rects
end

function GroundPlan.Area(r)
	return (r[2] - r[1]) * (r[4] - r[3])
end

-- Strict overlap test (touching edges do not count).
function GroundPlan.Overlaps(a, b)
	return a[1] < b[2] - 1e-6 and b[1] < a[2] - 1e-6 and a[3] < b[4] - 1e-6 and b[3] < a[4] - 1e-6
end

return GroundPlan
