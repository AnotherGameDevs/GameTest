-- Everything cosmetic about digging: block shake, cracks, flying dirt chunks (pooled, no physics),
-- camera kick, and the treasure reveal. The server decides outcomes; this only makes them feel good.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
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
local ToolFx = require(ReplicatedStorage.Shared.ToolFx)

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

-- opts.Spark = a short bright spark (own, smaller cap: ToolFx.Caps.Sparks); opts.Gravity overrides FEEL.Gravity.
local liveSparks = 0
local function spawnChunk(pos: Vector3, vel: Vector3, color: Color3, size: number, life: number, opts: any?)
	if #active >= FEEL.MaxChunks then
		return
	end
	local spark = opts ~= nil and opts.Spark == true
	if spark and liveSparks >= ToolFx.Caps.Sparks then
		return
	end
	local p = takeChunk()
	p.Material = spark and Enum.Material.Neon or Enum.Material.SmoothPlastic
	if spark then
		liveSparks += 1
	end
	p.Color = color
	p.Size = Vector3.one * size
	p.CFrame = CFrame.new(pos)
	p.Parent = fxFolder
	table.insert(active, {
		Part = p, Pos = pos, Vel = vel, Size = size, Life = life, Age = 0, Spark = spark,
		Gravity = opts ~= nil and opts.Gravity or nil,
		Rot = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
		Spin = Vector3.new(math.random() * 12 - 6, math.random() * 12 - 6, math.random() * 12 - 6),
	})
end

-- `spread` > 1 widens the cone (broader debris burst); the default keeps the original shape.
local function burst(pos: Vector3, normal: Vector3, color: Color3, count: number, speed: number, size: number, spread: number?)
	local wide = spread or 1
	for _ = 1, count do
		local rand = Vector3.new(math.random() - 0.5, math.random() - 0.2, math.random() - 0.5)
		local vel = (normal * (0.9 / wide) + rand * 1.4 * wide).Unit * speed * (0.5 + math.random())
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
			if c.Spark then
				liveSparks -= 1
			end
			c.Part.Parent = nil
			table.insert(pool, c.Part)
			table.remove(active, i)
		else
			c.Vel += Vector3.new(0, -(c.Gravity or FEEL.Gravity) * dt, 0)
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

-- Per-tool particle/sound behaviour lives in ToolFxController (profiles from shared/ToolFx). It registers itself here at Init; until it
-- does (or if it failed to start) the plain dirt feedback below is used, so mining never loses its basic feedback.
local fx: any = nil
function Effects.SetFx(hooks: any)
	fx = hooks
end

-- Shared helpers for ToolFxController (one chunk pool, one cap, one place that owns the parts).
Effects.Burst = burst
Effects.SpawnChunk = spawnChunk

-- Drops every transient effect part now (death, respawn, unequip, menu/focus interruptions, new mine generation).
function Effects.ClearTransient()
	for i = #active, 1, -1 do
		local c = active[i]
		c.Part.Parent = nil
		table.insert(pool, c.Part)
		table.remove(active, i)
	end
	liveSparks = 0
	kick = 0
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.CameraOffset = Vector3.zero
	end
end

-- Instant, client-predicted feedback at the moment of a swing (before the server answers).
function Effects.Impact(part: Part, hitPos: Vector3, normal: Vector3, toolId: string?)
	local _, y = Grid.FromIndex(tonumber(part.Name) or 1)
	shakeBlock(part)
	if fx then
		fx.Impact(toolId, Defs.LayerAtCell(y), hitPos, normal, true)
	else
		burst(hitPos, normal, layerColorAt(y), FEEL.ImpactChunks, 14, 0.7)
		Audio.Play("Impact", 0.9 + math.random() * 0.25)
	end
	cameraKick(FEEL.CameraKickImpact)
end

-- Which face of the cell at `center` looks towards `from` (used to place other players' effects on the side they are digging).
local function faceToward(center: Vector3, from: Vector3?): Vector3
	if not from then
		return Vector3.yAxis
	end
	local d = from - center
	local ax, ay, az = math.abs(d.X), math.abs(d.Y), math.abs(d.Z)
	if ay >= ax and ay >= az then
		return d.Y >= 0 and Vector3.yAxis or -Vector3.yAxis
	elseif ax >= az then
		return d.X >= 0 and Vector3.xAxis or -Vector3.xAxis
	end
	return d.Z >= 0 and Vector3.zAxis or -Vector3.zAxis
end

-- ctx = { Tool = server-reported tool id (or nil), Primary = first cell of this swing, Digger = Player? }. Everything here comes from the
-- authoritative result: which cells were hit/broken. Nothing looks at what a block contains.
local function onHit(idx: number, frac: number, dead: boolean, mine: boolean, face: Enum.NormalId?, ctx: any)
	local x, y, z = Grid.FromIndex(idx)
	local center = Grid.CellCenter(x, y, z)
	local site = Workspace:FindFirstChild("DigSite")
	local part = site and site:FindFirstChild(tostring(idx))
	local layer = Defs.LayerAtCell(y)
	local diggerRoot = ctx.Digger and ctx.Digger.Character and ctx.Digger.Character:FindFirstChild("HumanoidRootPart")
	local diggerPos = diggerRoot and (diggerRoot :: BasePart).Position or nil
	if dead then
		if part then
			shaking[part] = nil
			-- Make the broken block instantly invisible to targeting/collision on this client, so a held click
			-- retargets the block behind it without waiting for the server's destroy to replicate.
			part.CanQuery = false
			part.CanCollide = false
			part.Transparency = 1
			for _, child in ipairs(part:GetChildren()) do
				-- surface guis and buried-detail remnants go with the block at once (the server's destroy follows)
				if child:IsA("SurfaceGui") or child.Name:sub(1, 7) == "Detail_" then
					child:Destroy()
				end
			end
		end
		if fx then
			fx.Break(ctx.Tool, layer, center, mine, ctx.Primary, faceToward(center, diggerPos))
		else
			burst(center, Vector3.yAxis, layer.Color, FEEL.BreakChunks, 24, 1.3)
			Audio.Play("Break", 0.85 + math.random() * 0.3, mine and 1 or 0.5)
		end
		if mine and ctx.Primary then
			cameraKick(FEEL.CameraKickBreak)
		end
	elseif part then
		applyDamage(part :: Part, frac, face)
		if not mine then
			shakeBlock(part :: Part)
			local n = faceToward(center, diggerPos)
			if fx then
				fx.Impact(ctx.Tool, layer, center + n * (Grid.CellSize / 2), n, false)
			else
				Audio.Play("Impact", 0.9 + math.random() * 0.25, 0.4)
			end
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
	Audio.PlayReveal(order)

	-- Polished artifact model if there is one, else the generic stand-in. Always a Model so the same
	-- pivot/scale animation drives both.
	local model = TreasureModels.BuildAny(info.Id, def)
	local root = model.PrimaryPart :: BasePart
	local start = info.Position
	local top = start + Vector3.new(0, cfg[1], 0)
	model:ScaleTo(0.2)
	model:PivotTo(CFrame.new(start))
	model.Parent = fxFolder
	Debris:AddItem(model, 6) -- failsafe: a reveal can never outlive its longest animation (about 3.5 s)

	if rar.Reveal then
		local hl = Instance.new("Highlight")
		hl.FillColor = rar.Color
		hl.OutlineColor = Color3.new(1, 1, 1)
		hl.FillTransparency = 0.9 -- rarity is the outline/light colour; the model's own materials are never hidden by a glow
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = model
		local light = Instance.new("PointLight")
		light.Color = rar.Color
		light.Range = 12 + order * 3
		light.Brightness = 1.1
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
	-- A new mine generation: drop everything that belonged to the old one (reveal models, block shake, remembered hit faces),
	-- so no effect from the previous mine plays over the new cells.
	Workspace:GetAttributeChangedSignal("MineGeneration"):Connect(function()
		for _, child in ipairs(fxFolder:GetChildren()) do
			if child:IsA("Model") then
				child:Destroy()
			end
		end
		table.clear(shaking)
		table.clear(lastFace)
		if fx then
			fx.StopAll()
		end
	end)
	Remotes.Get("DigResult").OnClientEvent:Connect(function(payload)
		local mine = payload.Digger == player.UserId
		local digger = Players:GetPlayerByUserId(payload.Digger)
		if fx and not mine and digger then
			fx.OtherSwing(payload.Tool, digger) -- restrained third-person trail for nearby players' strikes
		end
		for i, h in ipairs(payload.Hits) do
			local idx = h[1]
			-- cracks on extra cells are cosmetic and capped; a cell that actually broke is always handled
			if i <= ToolFx.Caps.AreaCellsMax or h[3] == 1 then
				onHit(idx, h[2], h[3] == 1, mine, lastFace[idx], { Tool = payload.Tool, Primary = i == 1, Digger = digger })
			end
			if h[3] == 1 then
				lastFace[idx] = nil
			end
		end
	end)
	Remotes.Get("TreasureFound").OnClientEvent:Connect(Effects.RevealTreasure)
	Remotes.Get("Explosion").OnClientEvent:Connect(onExplosion)
end

return Effects
