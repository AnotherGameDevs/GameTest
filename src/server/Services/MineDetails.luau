-- Builds the small remnants on a mine cell's exposed face. Every detail part is a CHILD of the cell's own Part, so when
-- that cell is destroyed the Part (and with it every remnant) disappears in the same instant: nothing can be left floating.
-- Parts never collide, are never hit by mining rays (CanQuery = false), and cast no shadows.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Kit = require(ReplicatedStorage.Shared.ModelKit)
local MineDetailSpecs = require(ReplicatedStorage.Shared.MineDetailSpecs)

local MineDetails = {}

-- Frame at the face centre looking INTO the wall: local +Z points out of the cell.
local function faceFrame(center: Vector3, normal: Vector3, half: number): CFrame
	local origin = center + normal * half
	local up = math.abs(normal.Y) > 0.9 and Vector3.xAxis or Vector3.yAxis
	return CFrame.lookAt(origin, origin - normal, up)
end

-- The part specs for a MineStyle.Detail result: a small remnant, or - for a tell - the real artifact's visible part.
function MineDetails.Specs(detail, treasureDefs)
	if detail.Tell then
		local def = treasureDefs[detail.Loot]
		return def and MineDetailSpecs.Tell(detail.Loot, def, detail.Variant) or {}
	end
	if not MineDetailSpecs.Has(detail.Kind) then
		return {}
	end
	return MineDetailSpecs.Build(detail.Kind, detail.Variant)
end

-- Builds the specs on the cell's face; returns the number of parts created.
function MineDetails.Build(specs, label: string, cell: BasePart, center: Vector3, normal: Vector3): number
	local frame = faceFrame(center, normal, cell.Size.X / 2)
	local n = 0
	for _, spec in ipairs(specs) do
		local p = Kit.make(spec)
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false -- never intercepts the dig ray, the crosshair or a click
		p.CastShadow = false
		p.Massless = true
		p.Name = "Detail_" .. spec.Name
		p.CFrame = frame * spec.Offset
		p.Parent = cell
		n += 1
	end
	cell:SetAttribute("Detail", label)
	return n
end

return MineDetails
