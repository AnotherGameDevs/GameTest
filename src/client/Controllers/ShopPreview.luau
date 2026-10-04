-- Rotating 3D preview of the ACTUAL tool model (ToolModels.BuildPreview, the same spec the held tool is built from).
-- Every preview uses one fixed camera, lens and light rig, sized from the largest tool, so tools are framed
-- consistently and their relative sizes stay honest. An "inspect" preview reuses this with a closer camera and
-- drag-to-rotate.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Defs = require(ReplicatedStorage.Shared.Defs)
local ToolModels = require(ReplicatedStorage.Shared.ToolModels)
local Appearances = require(ReplicatedStorage.Shared.Appearances)
local PackModels = require(ReplicatedStorage.Shared.PackModels)

local ShopPreview = {}

local FOV = 32
local TILT = math.rad(14) -- lean so the blade, rib and grip read from the same angle
local SPIN_SPEED = 0.9 -- rad/s
local IDLE_RESUME = 2.2 -- seconds after a drag before auto-spin resumes

-- One shared framing radius: the largest bounding sphere of any tool appearance.
local framingRadius: number? = nil
local function getFramingRadius(): number
	if framingRadius then
		return framingRadius
	end
	local r = 4
	local appearances = {}
	for _, id in ipairs(Defs.ToolsByTier) do
		table.insert(appearances, Defs.Tools[id].Appearance)
	end
	for _, def in pairs(Defs.Consumables) do
		table.insert(appearances, def.Appearance)
	end
	for _, ap in ipairs(appearances) do
		if Appearances.List[ap] then
			local m = ToolModels.BuildPreview(ap)
			local _, size = m:GetBoundingBox()
			r = math.max(r, size.Magnitude / 2)
			m:Destroy()
		end
	end
	framingRadius = r
	return r
end

export type Preview = {
	Viewport: ViewportFrame,
	Camera: Camera,
	Model: Model?,
	Center: Vector3,
	Appearance: string?,
	Yaw: number,
	IdleFor: number,
	Closeness: number,
}

-- `closeness` < 1 moves the camera in (inspect view).
function ShopPreview.Create(viewport: ViewportFrame, closeness: number?): Preview
	viewport.Ambient = Color3.fromRGB(150, 138, 124)
	viewport.LightColor = Color3.fromRGB(255, 244, 224)
	viewport.LightDirection = Vector3.new(-0.5, -1, -0.7)
	viewport.BackgroundColor3 = Color3.fromHex("2B3038")
	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = viewport
	viewport.CurrentCamera = cam
	local p: Preview = {
		Viewport = viewport, Camera = cam, Model = nil, Center = Vector3.zero, Appearance = nil,
		Yaw = 0, IdleFor = IDLE_RESUME, Closeness = closeness or 1,
	}
	local dist = getFramingRadius() / math.sin(math.rad(FOV / 2)) * 1.08 * p.Closeness
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 0, dist), Vector3.zero)
	return p
end

function ShopPreview.Show(p: Preview, appearanceId: string?)
	if p.Appearance == appearanceId then
		return
	end
	if p.Model then
		p.Model:Destroy()
		p.Model = nil
	end
	p.Appearance = appearanceId
	if not appearanceId then
		return
	end
	local model = PackModels.Has(appearanceId) and PackModels.BuildPreview(appearanceId) or ToolModels.BuildPreview(appearanceId)
	local cf, _ = model:GetBoundingBox()
	p.Center = cf.Position
	model.Parent = p.Viewport
	p.Model = model
end

-- Drag-to-rotate input (inspect view). dx in pixels.
function ShopPreview.Drag(p: Preview, dx: number)
	p.Yaw += dx * 0.012
	p.IdleFor = 0
end

function ShopPreview.Update(p: Preview, dt: number)
	if not p.Model then
		return
	end
	p.IdleFor += dt
	if p.IdleFor >= IDLE_RESUME then
		p.Yaw += SPIN_SPEED * dt
	end
	-- spin about the world vertical through the model's own centre, with a fixed lean
	p.Model:PivotTo(CFrame.Angles(0, p.Yaw, 0) * CFrame.Angles(0, 0, TILT) * CFrame.new(-p.Center))
end

return ShopPreview
