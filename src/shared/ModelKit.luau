-- Tiny parts-only modelling kit for the "chunky dig-site" look. A model is a list of part specs positioned
-- relative to its origin; the same spec list can become an anchored preview/FX Model or a welded Tool.
local Kit = {}

local function rotFromDegrees(rot: Vector3?): CFrame
	if not rot then
		return CFrame.identity
	end
	return CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
end

local function spec(name: string, shape: string, size: Vector3, pos: Vector3, rot: Vector3?, color: Color3, material: Enum.Material?)
	return {
		Name = name,
		Shape = shape, -- "Block" | "Ball" | "Cylinder" | "Ellipsoid"
		Size = size,
		Offset = CFrame.new(pos) * rotFromDegrees(rot),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	}
end

function Kit.block(name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material?, rot: Vector3?)
	return spec(name, "Block", size, pos, rot, color, material)
end

function Kit.ball(name: string, diameter: number, pos: Vector3, color: Color3, material: Enum.Material?)
	return spec(name, "Ball", Vector3.one * diameter, pos, nil, color, material)
end

-- Soft stretched sphere (body of a scarab etc.): a block-sized part rendered with a sphere mesh.
function Kit.ellipsoid(name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material?, rot: Vector3?)
	return spec(name, "Ellipsoid", size, pos, rot, color, material)
end

-- Cylinder along "X", "Y" or "Z". (Roblox cylinders run along the part's own X axis.)
function Kit.cyl(name: string, axis: string, length: number, diameter: number, pos: Vector3, color: Color3, material: Enum.Material?)
	local rot = nil
	if axis == "Y" then
		rot = Vector3.new(0, 0, 90)
	elseif axis == "Z" then
		rot = Vector3.new(0, 90, 0)
	end
	return spec(name, "Cylinder", Vector3.new(length, diameter, diameter), pos, rot, color, material)
end

-- Creates the Part for a spec (unanchored, no collision). Caller positions/welds it.
function Kit.make(s): Part
	local p = Instance.new("Part")
	p.Name = s.Name
	p.Size = s.Size
	p.Color = s.Color
	p.Material = s.Material
	p.Transparency = s.Transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanTouch = false
	if s.Shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif s.Shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	elseif s.Shape == "Ellipsoid" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	return p
end

-- Anchored, non-colliding Model for previews and FX. A tiny invisible "Root" at the origin is the PrimaryPart so
-- PivotTo / ScaleTo / spinning all happen around the model's origin.
function Kit.BuildModel(specs, name: string?): Model
	local model = Instance.new("Model")
	model.Name = name or "Model"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.1
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = model
	model.PrimaryPart = root
	for _, s in ipairs(specs) do
		local p = Kit.make(s)
		p.Anchored = true
		p.CanQuery = false
		p.CFrame = s.Offset
		p.Parent = model
	end
	return model
end

-- A rigid, WELDED assembly for first-person viewmodels / held visuals. `Root` is an anchored, invisible part at the
-- origin; every spec part is welded to it at its authored offset, so PivotTo/CFrame on the model moves the whole
-- assembly as ONE rigid body (nothing is repositioned per part). Parts never collide, are never raycast, cast no shadow.
function Kit.BuildWelded(specs, name: string?): Model
	local model = Instance.new("Model")
	model.Name = name or "Welded"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.1
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root
	for _, s in ipairs(specs) do
		local p = Kit.make(s)
		p.Anchored = false
		p.Massless = true
		p.CanQuery = false
		p.CastShadow = false
		p.Parent = model
		local w = Instance.new("Weld")
		w.Part0 = root
		w.Part1 = p
		w.C0 = s.Offset
		w.Parent = p
	end
	return model
end

-- Returns a copy of `specs` uniformly scaled and rotated (degrees) about the origin.
function Kit.Transform(specs, scale: number, rotationDegrees: Vector3?)
	local rot = rotFromDegrees(rotationDegrees)
	local out = {}
	for _, s in ipairs(specs) do
		local pos = s.Offset.Position * scale
		local r = s.Offset - s.Offset.Position
		table.insert(out, {
			Name = s.Name, Shape = s.Shape, Size = s.Size * scale, Color = s.Color, Material = s.Material,
			Transparency = s.Transparency,
			Offset = rot * (CFrame.new(pos) * r),
		})
	end
	return out
end

return Kit
