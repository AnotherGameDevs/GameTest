-- Everything cosmetic about digging: block shake, cracks, flying dirt chunks (pooled, no physics),
-- camera kick, and the treasure reveal. The server decides outcomes; this only makes them feel good.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Defs = require(ReplicatedStorage.Shared.Defs)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Audio = require(script.Parent.AudioController)
local UI = require(script.Parent.UIController)

local player = Players.LocalPlayer
local Effects = {}

-- Tunables for feel -----------------------------------------------------------------------
local FEEL = {
	ImpactChunks = 4,
	BreakChunks = 10,
	MaxChunks = 140,
	Gravity = 70,
	BlockShakeTime = 0.16,
	BlockShakeAmp = 0.35,
	CameraKickImpact = 0.05,
	CameraKickBreak = 0.16,
	CameraKickDecay = 7,
}

local fxFolder = Instance.new("Folder")
fxFolder.Name = "LocalFX"
fxFolder.Parent = Workspace

-- Chunk pool ------------------------------------------------------------------------------
local pool: { Part } = {}
local active: { any } = {}

local function takeChunk(): Part
	local p = table.remove(pool)
	if p then
		return p
	end
	p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function spawnChunk(pos: Vector3, vel: Vector3, color: Color3, size: number, life: number)
	if #active >= FEEL.MaxChunks then
		return
	end
	local p = takeChunk()
	p.Color = color
	p.Size = Vector3.one * size
	p.CFrame = CFrame.new(pos)
	p.Parent = fxFolder
	table.insert(active, {
		Part = p, Pos = pos, Vel = vel, Size = size, Life = life, Age = 0,
		Rot = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
		Spin = Vector3.new(math.random() * 12 - 6, math.random() * 12 - 6, math.random() * 12 - 6),
	})
end

local function burst(pos: Vector3, normal: Vector3, color: Color3, count: number, speed: number, size: number)
	for _ = 1, count do
		local rand = Vector3.new(math.random() - 0.5, math.random() - 0.2, math.random() - 0.5)
		local vel = (normal * 0.9 + rand * 1.4).Unit * speed * (0.5 + math.random())
		local c = color:Lerp(Color3.new(1, 1, 1), math.random() * 0.15)
		spawnChunk(pos, vel, c, size * (0.6 + math.random() * 0.8), 0.45 + math.random() * 0.35)
	end
end

-- Block shake -----------------------------------------------------------------------------
local shaking: { [Part]: { Base: CFrame, T0: number } } = {}

local function shakeBlock(part: Part)
	local s = shaking[part]
	if s then
		s.T0 = os.clock()
	else
		shaking[part] = { Base = part.CFrame, T0 = os.clock() }
	end
end

-- Cracks / damage tint --------------------------------------------------------------------
local CRACK_STAGES = {
	{ { 0.5, 0.5, 0.35, 35 }, { 0.62, 0.38, 0.25, -20 } },
	{ { 0.38, 0.6, 0.3, 110 }, { 0.55, 0.68, 0.28, 75 } },
	{ { 0.3, 0.35, 0.3, -60 }, { 0.7, 0.55, 0.32, 10 } },
	{ { 0.5, 0.25, 0.3, 95 }, { 0.45, 0.78, 0.3, -30 }, { 0.78, 0.78, 0.25, 50 } },
}
local damageInfo: any = setmetatable({}, { __mode = "k" })

local function faceFromNormal(n: Vector3): Enum.NormalId
	local ax, ay, az = math.abs(n.X), math.abs(n.Y), math.abs(n.Z)
	if ay >= ax and ay >= az then
		return n.Y >= 0 and Enum.NormalId.Top or Enum.NormalId.Bottom
	elseif ax >= az then
		return n.X >= 0 and Enum.NormalId.Right or Enum.NormalId.Left
	end
	return n.Z >= 0 and Enum.NormalId.Back or Enum.NormalId.Front
end

local function buildCracks(gui: SurfaceGui, uptoStage: number, fromStage: number)
	for stage = fromStage + 1, uptoStage do
		for _, c in ipairs(CRACK_STAGES[stage]) do
			local f = Instance.new("Frame")
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromScale(c[1], c[2])
			f.Size = UDim2.fromScale(c[3], 0.035)
			f.Rotation = c[4]
			f.BackgroundColor3 = Color3.fromRGB(28, 20, 14)
			f.BackgroundTransparency = 0.05
			f.BorderSizePixel = 0
			f.Parent = gui
		end
	end
end

local function applyDamage(part: Part, frac: number, face: Enum.NormalId?)
	local info = damageInfo[part]
	if not info then
		info = { Base = part.Color, Stage = 0, Gui = {} }
		damageInfo[part] = info
	end
	local stage = math.clamp(math.ceil((1 - frac) * 4), 1, 4)
	part.Color = info.Base:Lerp(Color3.fromRGB(30, 22, 16), (1 - frac) * 0.4)

	local f = face or Enum.NormalId.Top
	local gui = info.Gui[f]
	if not gui then
		gui = Instance.new("SurfaceGui")
		gui.Face = f
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(200, 200)
		gui.LightInfluence = 0
		gui.Parent = part
		info.Gui[f] = gui
		buildCracks(gui, stage, 0)
		info.Stage = math.max(info.Stage, stage)
	end
	if stage > info.Stage then
		for _, g in pairs(info.Gui) do
			buildCracks(g, stage, info.Stage)
		end
		info.Stage = stage
	end
end

-- Camera kick -------------------------------------------------------------------------------
local kick = 0
local function cameraKick(amount: number)
	kick = math.max(kick, amount)
end

RunService.RenderStepped:Connect(function(dt)
	-- chunks
	for i = #active, 1, -1 do
		local c = active[i]
		c.Age += dt
		if c.Age >= c.Life then
			c.Part.Parent = nil
			table.insert(pool, c.Part)
			table.remove(active, i)
		else
			c.Vel += Vector3.new(0, -FEEL.Gravity * dt, 0)
			c.Pos += c.Vel * dt
			c.Rot *= CFrame.Angles(c.Spin.X * dt, c.Spin.Y * dt, c.Spin.Z * dt)
			local k = 1 - (c.Age / c.Life) ^ 2
			c.Part.Size = Vector3.one * c.Size * math.max(k, 0.05)
			c.Part.CFrame = CFrame.new(c.Pos) * c.Rot
		end
	end
	-- block shake
	local now = os.clock()
	for part, s in pairs(shaking) do
		local t = (now - s.T0) / FEEL.BlockShakeTime
		if part.Parent == nil then
			shaking[part] = nil
		elseif t >= 1 then
			part.CFrame = s.Base
			shaking[part] = nil
		else
			local a = FEEL.BlockShakeAmp * (1 - t)
			part.CFrame = s.Base + Vector3.new(
				(math.random() - 0.5) * a, (math.random() - 0.5) * a, (math.random() - 0.5) * a)
		end
	end
	-- camera kick via Humanoid.CameraOffset (works with default cameras, no camera takeover)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if kick > 0.002 then
			humanoid.CameraOffset = Vector3.new(
				(math.random() - 0.5) * kick, (math.random() - 0.5) * kick, 0)
			kick = kick * math.max(0, 1 - FEEL.CameraKickDecay * dt)
		elseif humanoid.CameraOffset ~= Vector3.zero then
			humanoid.CameraOffset = Vector3.zero
			kick = 0
		end
	end
end)

-- Public feedback -----------------------------------------------------------------------------
local function layerColorAt(y: number): Color3
	return Defs.LayerAtCell(y).Color
end

-- Instant, client-predicted feedback at the moment of a swing (before the server answers).
function Effects.Impact(part: Part, hitPos: Vector3, normal: Vector3)
	local _, y = Grid.FromIndex(tonumber(part.Name) or 1)
	shakeBlock(part)
	burst(hitPos, normal, layerColorAt(y), FEEL.ImpactChunks, 14, 0.7)
	Audio.Play("Impact", 0.9 + math.random() * 0.25)
	cameraKick(FEEL.CameraKickImpact)
end

local function onHit(idx: number, frac: number, dead: boolean, mine: boolean, face: Enum.NormalId?)
	local x, y, z = Grid.FromIndex(idx)
	local center = Grid.CellCenter(x, y, z)
	local site = Workspace:FindFirstChild("DigSite")
	local part = site and site:FindFirstChild(tostring(idx))
	if dead then
		if part then
			shaking[part] = nil
		end
		local color = layerColorAt(y)
		burst(center, Vector3.yAxis, color, FEEL.BreakChunks, 24, 1.3)
		Audio.Play("Break", 0.85 + math.random() * 0.3, mine and 1 or 0.5)
		if mine then
			cameraKick(FEEL.CameraKickBreak)
		end
	elseif part then
		applyDamage(part :: Part, frac, face)
		if not mine then
			shakeBlock(part :: Part)
			Audio.Play("Impact", 0.9 + math.random() * 0.25, 0.4)
		end
	end
end

-- Last face we hit locally per cell, so cracks appear on the side the player is looking at.
local lastFace: { [number]: Enum.NormalId } = {}
function Effects.NoteFace(part: Part, normal: Vector3)
	local idx = tonumber(part.Name)
	if idx then
		lastFace[idx] = faceFromNormal(normal)
	end
end

-- Treasure reveal ---------------------------------------------------------------------------------
local REVEAL = { -- per rarity: float height, hold time, burst count
	Common = { 3, 0.12, 4 },
	Uncommon = { 5, 0.45, 12 },
	Rare = { 6, 0.7, 20 },
	Epic = { 8, 1.0, 34 },
	Legendary = { 9, 1.3, 50 },
	Mythic = { 10, 1.6, 70 },
}

local function buildTreasureModel(def): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Color = def.Color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if def.Shape == "Coin" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.5, 2.4, 2.4)
	elseif def.Shape == "Ring" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.8, 2.4, 2.4)
	elseif def.Shape == "Gem" then
		p.Size = Vector3.new(1.8, 1.8, 1.8)
		p.Material = Enum.Material.Neon
	else
		p.Size = Vector3.new(2.2, 1.6, 1.8)
	end
	return p
end

function Effects.RevealTreasure(info)
	local def = Defs.Treasure[info.Id]
	if not def then
		return
	end
	local rar = Defs.Rarity[def.Rarity]
	local cfg = REVEAL[def.Rarity] or REVEAL.Common

	UI.ShowTreasure(info.Id, info.Stored, info.IsNew)
	local order = rar.Order
	Audio.Play(order >= 2 and "Reveal" or "Coin", 0.9 + order * 0.12 + math.random() * 0.1)

	local model = buildTreasureModel(def)
	local start = info.Position
	local top = start + Vector3.new(0, cfg[1], 0)
	model.CFrame = CFrame.new(start)
	model.Size = model.Size * 0.2
	local fullSize = buildTreasureModel(def).Size
	model.Parent = fxFolder

	if rar.Reveal then
		local hl = Instance.new("Highlight")
		hl.FillColor = rar.Color
		hl.OutlineColor = Color3.new(1, 1, 1)
		hl.FillTransparency = 0.5
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = model
		local light = Instance.new("PointLight")
		light.Color = rar.Color
		light.Range = 12 + order * 3
		light.Brightness = 2
		light.Parent = model
		burst(start, Vector3.yAxis, rar.Color, cfg[3], 22, 0.8)
	end

	task.spawn(function()
		-- pop up while spinning
		local t0, dur = os.clock(), 0.3
		while true do
			local a = math.min((os.clock() - t0) / dur, 1)
			local e = TweenService:GetValue(a, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			model.Size = fullSize * (0.2 + 0.8 * e)
			model.CFrame = CFrame.new(start:Lerp(top, e)) * CFrame.Angles(0, a * 8, math.rad(15))
			if a >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		-- hold + gentle spin
		local hold = os.clock() + cfg[2]
		local spin = 8
		while os.clock() < hold do
			spin += RunService.RenderStepped:Wait() * 4
			model.CFrame = CFrame.new(top + Vector3.new(0, math.sin(os.clock() * 6) * 0.2, 0))
				* CFrame.Angles(0, spin, math.rad(15))
		end
		-- fly to the player (or fizzle if it didn't fit in the backpack)
		local t1, d1 = os.clock(), 0.35
		local from = model.Position
		while true do
			local a = math.min((os.clock() - t1) / d1, 1)
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local target = (info.Stored and hrp) and (hrp :: BasePart).Position or (from + Vector3.new(0, 2, 0))
			local e = a * a
			model.Position = from:Lerp(target, e)
			model.Size = fullSize * (1 - e * 0.9)
			if a >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		model:Destroy()
	end)
end

function Effects.Init()
	Remotes.Get("DigResult").OnClientEvent:Connect(function(payload)
		local mine = payload.Digger == player.UserId
		for _, h in ipairs(payload.Hits) do
			local idx = h[1]
			onHit(idx, h[2], h[3] == 1, mine, lastFace[idx])
			if h[3] == 1 then
				lastFace[idx] = nil
			end
		end
	end)
	Remotes.Get("TreasureFound").OnClientEvent:Connect(Effects.RevealTreasure)
end

return Effects
