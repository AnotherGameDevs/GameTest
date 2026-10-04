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
local CameraController = require(script.Parent.CameraController)
local Settings = require(script.Parent.Settings)
local TreasureModels = require(ReplicatedStorage.Shared.TreasureModels)

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
	CameraKickInFirstPerson = false, -- first-person starts with no mining kick; flip to test
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
local function cameraKick(amount: number, always: boolean?)
	if not Settings.Get("CameraShake") then
		return -- the player turned camera shake off
	end
	if not always and CameraController.IsFirstPerson() and not FEEL.CameraKickInFirstPerson then
		return
	end
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
			-- Make the broken block instantly invisible to targeting/collision on this client, so a held click
			-- retargets the block behind it without waiting for the server's destroy to replicate.
			part.CanQuery = false
			part.CanCollide = false
			part.Transparency = 1
			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("SurfaceGui") then
					child:Destroy()
				end
			end
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

-- Treasure reveal ---------------------------------------------------------------------------------------
local REVEAL = { -- per rarity: float height, hold time, burst count
	Common = { 3, 0.12, 4 },
	Uncommon = { 5, 0.45, 12 },
	Rare = { 6, 0.7, 20 },
	Epic = { 8, 1.0, 34 },
	Legendary = { 9, 1.3, 50 },
	Mythic = { 10, 1.6, 70 },
}

function Effects.RevealTreasure(info)
	local def = Defs.Treasure[info.Id]
	if not def then
		return
	end
	local rar = Defs.Rarity[def.Rarity]
	local cfg = REVEAL[def.Rarity] or REVEAL.Common

	UI.ShowTreasure(info.Id, info.Stored, info.IsNew, info.Carry)
	local order = rar.Order
	Audio.Play(order >= 2 and "Reveal" or "Coin", 0.9 + order * 0.12 + math.random() * 0.1)

	-- Polished artifact model if there is one, else the generic stand-in. Always a Model so the same
	-- pivot/scale animation drives both.
	local model = TreasureModels.BuildAny(info.Id, def)
	local root = model.PrimaryPart :: BasePart
	local start = info.Position
	local top = start + Vector3.new(0, cfg[1], 0)
	model:ScaleTo(0.2)
	model:PivotTo(CFrame.new(start))
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
		light.Parent = root
		burst(start, Vector3.yAxis, rar.Color, cfg[3], 22, 0.8)
	end

	task.spawn(function()
		-- pop up while spinning
		local t0, dur = os.clock(), 0.3
		while true do
			local a = math.min((os.clock() - t0) / dur, 1)
			local e = TweenService:GetValue(a, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			model:ScaleTo(0.2 + 0.8 * e)
			model:PivotTo(CFrame.new(start:Lerp(top, e)) * CFrame.Angles(0, a * 8, math.rad(15)))
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
			model:PivotTo(CFrame.new(top + Vector3.new(0, math.sin(os.clock() * 6) * 0.2, 0))
				* CFrame.Angles(0, spin, math.rad(15)))
		end
		local pivot = model:GetPivot()
		local from = pivot.Position
		local rot = pivot - pivot.Position
		-- fly to the player; fizzle if it did not fit; or, for important artifacts, settle back down to where the
		-- real physical artifact is about to appear (it is never auto-collected)
		local t1, d1 = os.clock(), 0.35
		while true do
			local a = math.min((os.clock() - t1) / d1, 1)
			local e = a * a
			if info.Carry then
				model:PivotTo(CFrame.new(from:Lerp(start, TweenService:GetValue(a, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))) * rot)
			else
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local target = (info.Stored and hrp) and (hrp :: BasePart).Position or (from + Vector3.new(0, 2, 0))
				model:PivotTo(CFrame.new(from:Lerp(target, e)) * rot)
				model:ScaleTo(math.max(1 - e * 0.9, 0.05))
			end
			if a >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		model:Destroy()
	end)
end

function Effects.GetFolder(): Folder
	return fxFolder
end

-- Dynamite blast: expanding flash, a big burst of chunks and a camera kick scaled by distance.
local function onExplosion(pos: Vector3, blocks: number)
	local flash = Instance.new("Part")
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanQuery = false
	flash.CanTouch = false
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromHex("FFB347")
	flash.Transparency = 0.2
	flash.Size = Vector3.one * 2
	flash.Position = pos
	flash.Parent = fxFolder
	local tw = TweenService:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * 16, Transparency = 1 })
	tw:Play()
	tw.Completed:Once(function()
		flash:Destroy()
	end)
	burst(pos, Vector3.yAxis, Color3.fromHex("FFB347"), 14, 30, 1.2)
	Audio.Play("Break", 0.5, 1.4)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local dist = ((hrp :: BasePart).Position - pos).Magnitude
		cameraKick(math.clamp(0.9 - dist / 90, 0, 0.9), true)
	end
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
	Remotes.Get("Explosion").OnClientEvent:Connect(onExplosion)
end

return Effects
