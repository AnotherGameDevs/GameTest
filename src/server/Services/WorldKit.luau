-- Shared helpers and the world colour palette. Chunky, readable, minimal texture: broad shapes and subtle tonal changes.
local WorldKit = {}

local function hex(s: string): Color3
	return Color3.fromHex(s)
end

WorldKit.Color = {
	-- ground (distinct but related warm sands / earths)
	Sand = hex("DDBE8A"), -- open desert
	Camp = hex("D6B07A"), -- compacted warm sand
	CampEdge = hex("CFA86F"),
	Route = hex("B98B59"), -- slightly darker worn earth
	Gravel = hex("A68A66"),
	GravelDark = hex("8A6E50"),
	Disturbed = hex("9A6A44"),
	-- construction
	Timber = hex("7B5233"),
	TimberDark = hex("5E3F27"),
	TimberLight = hex("A0733F"),
	Iron = hex("2F343B"),
	IronLight = hex("4A525C"),
	Rope = hex("CDB88A"),
	-- canvas
	CanvasCream = hex("E6D8B4"),
	CanvasTeal = hex("3E8E87"),
	Trim = hex("EFE2C3"),
	Gold = hex("D9A441"),
	-- landforms
	RockDark = hex("9C523A"),
	Rock = hex("B8643F"),
	RockTan = hex("C98F5A"),
	RockCap = hex("D8B678"),
	Scrub = hex("8B7B47"),
	Stone = hex("8F877B"),
}

function WorldKit.part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function WorldKit.box(parent: Instance, name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material?): Part
	return WorldKit.part(parent, name, size, CFrame.new(pos), color, material)
end

-- A non-solid decoration (never blocks movement or rays).
function WorldKit.deco(p: Part): Part
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- A sign that cannot be seen through walls (SurfaceGui, not an always-on-top billboard).
function WorldKit.sign(parent: Part, face: Enum.NormalId, text: string, bg: Color3, fg: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(400, 160)
	gui.LightInfluence = 0.2
	gui.AlwaysOnTop = false
	gui.Parent = parent
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = bg
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.94, 0.8)
	label.Position = UDim2.fromScale(0.03, 0.1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = fg
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = frame
end

-- Weld a decoration to a root part (keeps movable assemblies, like the elevator car, rigid).
function WorldKit.weld(root: Part, p: Part)
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
end

return WorldKit
