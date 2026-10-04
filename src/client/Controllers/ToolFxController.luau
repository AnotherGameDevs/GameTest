-- Per-tool mining effects: swing trail, impact puff / chips / sparks / ring / streak, break bursts, and the matching sounds.
-- All data comes from shared/ToolFx profiles (cosmetic only: no stat is read or changed here). What it reacts to:
--   * Swing (local, immediate): the trail on the assembled tool, enabled ONLY for the strike part of the swing.
--   * Impact (local prediction at swing time; other players' hits arrive from the server result): chips, puff, sound, ring, streak, sparks.
--   * Break (server result): the debris burst and the break sound, plus a small chip burst for each EXTRA cell the server reports.
-- It is told the tool id, the LAYER of the cell (from its depth) and positions. It is never given a block's contents, so nothing here can
-- reveal a hidden reward, rarity or loot assignment.
-- Cleanup: trails are disabled by StopOwn()/StopAll() (menus, focus loss, carrying, unequip, tool change, death, respawn, new mine); every
-- ring/streak part has a failsafe lifetime; chunks and sparks are capped and pooled in EffectsController.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Defs = require(ReplicatedStorage.Shared.Defs)
local Grid = require(ReplicatedStorage.Shared.Grid)
local ToolFx = require(ReplicatedStorage.Shared.ToolFx)
local ToolModels = require(ReplicatedStorage.Shared.ToolModels)
local ViewmodelMath = require(ReplicatedStorage.Shared.ViewmodelMath)

local Effects = require(script.Parent.EffectsController)
local Audio = require(script.Parent.AudioController)
local CameraController = require(script.Parent.CameraController)
local InputMode = require(script.Parent.InputMode)
local State = require(script.Parent.State)

local player = Players.LocalPlayer
local Fx = {}

local gate: { [string]: number } = {} -- local player's effect gates
local otherGate: { [string]: number } = {} -- shared gate for everyone else's restrained effects
local otherSwingGate: any = setmetatable({}, { __mode = "k" }) -- per other player: trail pulses
local rings: { Part } = {}
local streaks: { Part } = {}
local liveTrails: { [Trail]: number } = {} -- trail -> time it must be off by
local trailToken: any = setmetatable({}, { __mode = "k" })
local puffPart: Part? = nil
local puffEmitter: ParticleEmitter? = nil

local function hex(s: string): Color3
	return Color3.fromHex(s)
end

local function now(): number
	return os.clock()
end

local function rand(a: number, b: number): number
	return a + math.random() * (b - a)
end

local function localRoot(): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Other players' effects are skipped when they are far from the local player.
local function nearEnough(pos: Vector3): boolean
	local root = localRoot()
	return root ~= nil and (root.Position - pos).Magnitude <= ToolFx.Caps.OtherPlayerMaxDistance
end

-- Puff: ONE reused emitter that emits a couple of soft particles at a point. Never emits continuously (Rate = 0). --------------------
local function ensurePuff()
	if puffPart and puffPart.Parent and puffEmitter then
		return
	end
	local p = Instance.new("Part")
	p.Name = "PuffEmitter"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.Parent = Effects.GetFolder()
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Lifetime = NumberRange.new(0.3, 0.5)
	e.Speed = NumberRange.new(2, 5)
	e.SpreadAngle = Vector2.new(55, 55)
	e.Drag = 3
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	e.EmissionDirection = Enum.NormalId.Front
	e.Parent = p
	puffPart, puffEmitter = p, e
end

local function emitPuff(color: Color3, size: number, pos: Vector3, normal: Vector3, count: number)
	ensurePuff()
	local part, e = puffPart :: Part, puffEmitter :: ParticleEmitter
	part.CFrame = CFrame.lookAt(pos + normal * 0.1, pos + normal)
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.35), NumberSequenceKeypoint.new(1, size) })
	e:Emit(math.clamp(count, 1, 3))
end

-- Ring: a flat circle (UIStroke on a thin part's face) that grows and fades. At most Caps.Rings alive. ---------------------------------
local function dropFrom(list: { Part }, part: Part)
	local i = table.find(list, part)
	if i then
		table.remove(list, i)
	end
	part:Destroy()
end

local function spawnRing(pos: Vector3, normal: Vector3, colorHex: string, radius: number, time: number)
	if #rings >= ToolFx.Caps.Rings then
		return
	end
	local p = Instance.new("Part")
	p.Name = "FxRing"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(0.6, 0.6, 0.05)
	p.CFrame = CFrame.lookAt(pos + normal * 0.06, pos + normal) -- the part's Front face looks along the normal
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(128, 128)
	gui.LightInfluence = 0
	gui.Parent = p
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 5
	stroke.Color = hex(colorHex)
	stroke.Transparency = 0.35
	stroke.Parent = f
	p.Parent = Effects.GetFolder()
	table.insert(rings, p)
	local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(p, info, { Size = Vector3.new(radius * 2, radius * 2, 0.05) }):Play()
	local tw = TweenService:Create(stroke, info, { Transparency = 1 })
	tw:Play()
	tw.Completed:Once(function()
		dropFrom(rings, p)
	end)
	Debris:AddItem(p, time + 0.6) -- failsafe
end

-- Streak: one thin bright bar next to (never on) the aim point that shrinks away. At most Caps.Streaks alive. -------------------------
local function spawnStreak(pos: Vector3, normal: Vector3, colorHex: string, length: number, time: number)
	if #streaks >= ToolFx.Caps.Streaks then
		return
	end
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	-- a diagonal across the face, offset along its own perpendicular so the aim point itself stays clear
	local right = cam.CFrame.RightVector
	local along = (right * 0.8 + cam.CFrame.UpVector * 0.55)
	along = (along - normal * along:Dot(normal))
	if along.Magnitude < 0.05 then
		return
	end
	along = along.Unit
	local across = normal:Cross(along)
	local centre = pos + normal * 0.08 + across * 1.1
	local p = Instance.new("Part")
	p.Name = "FxStreak"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = hex(colorHex)
	p.Transparency = 0.3
	p.Size = Vector3.new(0.07, 0.07, length)
	p.CFrame = CFrame.lookAt(centre, centre + along)
	p.Parent = Effects.GetFolder()
	table.insert(streaks, p)
	local tw = TweenService:Create(p, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = Vector3.new(0.02, 0.02, length * 0.25), Transparency = 1 })
	tw:Play()
	tw.Completed:Once(function()
		dropFrom(streaks, p)
	end)
	Debris:AddItem(p, time + 0.5)
end

local function spawnSparks(spec, pos: Vector3, normal: Vector3, scale: number)
	local n = math.max(1, math.floor(spec.Count * scale + 0.5))
	local color = hex(spec.Color)
	for _ = 1, n do
		local rnd = Vector3.new(rand(-1, 1), rand(-0.3, 1), rand(-1, 1))
		local vel = (normal * 1.2 + rnd).Unit * spec.Speed * rand(0.6, 1.1)
		Effects.SpawnChunk(pos, vel, color, 0.16, rand(0.18, 0.32), { Spark = true, Gravity = 40 })
	end
end

local function volumeFor(mine: boolean): number
	return mine and 1 or 0.4
end

-- Impact ---------------------------------------------------------------------------------------------------------------------------------
function Fx.Impact(toolId: string?, layer: any, pos: Vector3, normal: Vector3, mine: boolean)
	if not mine and not nearEnough(pos) then
		return
	end
	local profile = ToolFx.For(toolId)
	local g = mine and gate or otherGate
	local t = now()
	local scale = mine and 1 or ToolFx.Caps.OtherPlayerChunkScale
	local dirt = profile.Dirt

	Effects.Burst(pos, normal, layer.Color, math.max(1, math.floor(dirt.Impact * scale + 0.5)), dirt.Speed, dirt.Size, dirt.Spread)
	if profile.Puff and ToolFx.Gate(g, "Puff", t, ToolFx.GapFor(profile, "Puff")) then
		emitPuff(hex(profile.Puff.Color):Lerp(layer.Color, 0.45), profile.Puff.Size * (mine and 1 or 0.7), pos, normal, 1)
	end
	local s = profile.Sound.Impact
	Audio.Play("Impact", s.Pitch * rand(0.94, 1.08), s.Volume * volumeFor(mine))
	local tick = profile.Sound.Tick
	if tick and mine and ToolFx.Gate(g, "Tick", t, tick.MinGap or 0.2) then
		Audio.Play("Tick", tick.Pitch, tick.Volume)
	end
	if ToolFx.SparksOn(profile, layer.Id) and ToolFx.Gate(g, "Sparks", t, ToolFx.GapFor(profile, "Sparks")) then
		spawnSparks(profile.Sparks, pos, normal, scale)
	end
	-- the larger accents are the local player's own; other players get the restrained set above
	if mine then
		local ring = profile.Ring
		if ring and (ring.On == "impact" or ring.On == "both") and ToolFx.Gate(g, "Ring", t, ToolFx.GapFor(profile, "Ring")) then
			spawnRing(pos, normal, ring.Color, ring.Radius, ring.Time)
		end
		local streak = profile.Streak
		if streak and ToolFx.Gate(g, "Streak", t, ToolFx.GapFor(profile, "Streak")) then
			spawnStreak(pos, normal, streak.Color, streak.Length, streak.Time)
		end
	end
end

-- Break: `primary` is the swing's own target; extra cells (area tools, dynamite) get a small chip burst only, one per cell the server reports.
function Fx.Break(toolId: string?, layer: any, center: Vector3, mine: boolean, primary: boolean, normal: Vector3)
	if not mine and not nearEnough(center) then
		return
	end
	local profile = ToolFx.For(toolId)
	local g = mine and gate or otherGate
	local t = now()
	local scale = mine and 1 or ToolFx.Caps.OtherPlayerChunkScale
	local dirt = profile.Dirt
	if not primary then
		Effects.Burst(center, normal, layer.Color, math.max(1, math.floor(dirt.Break * 0.25 * scale + 0.5)), dirt.BreakSpeed * 0.8, dirt.BreakSize * 0.7, dirt.Spread)
		return
	end
	Effects.Burst(center, Vector3.yAxis, layer.Color, math.max(2, math.floor(dirt.Break * scale + 0.5)), dirt.BreakSpeed, dirt.BreakSize, dirt.Spread)
	local accent = profile.Accent
	if accent then
		Effects.Burst(center, Vector3.yAxis, hex(accent.Color), math.max(1, math.floor(accent.Count * scale + 0.5)), dirt.BreakSpeed * 0.9, 0.45)
	end
	if ToolFx.SparksOn(profile, layer.Id) and ToolFx.Gate(g, "BreakSparks", t, ToolFx.GapFor(profile, "Sparks")) then
		spawnSparks(profile.Sparks, center, normal, scale)
	end
	local s = profile.Sound.Break
	Audio.Play("Break", s.Pitch * rand(0.94, 1.08), s.Volume * volumeFor(mine))
	local ring = profile.Ring
	if mine and ring and ring.On == "both" and ToolFx.Gate(g, "Ring", t, ToolFx.GapFor(profile, "Ring")) then
		spawnRing(center + normal * (Grid.CellSize / 2), normal, ring.Color, ring.Radius, ring.Time)
	end
end

-- Trails ---------------------------------------------------------------------------------------------------------------------------------------
-- The trail rig is built from the SAME part spec as the held tool / viewmodel (ToolFx.RigPoints), so it sits on the real working end.
local function ensureTrail(container: Instance, appearanceId: string, profile: any, scale: number): Trail?
	local existing = container:FindFirstChild("FxTrail", true)
	if existing then
		return existing :: Trail
	end
	local cfg = profile.Trail
	if not cfg then
		return nil
	end
	local handle = container:FindFirstChild("Handle", true)
	if not handle or not handle:IsA("BasePart") then
		return nil
	end
	local spec = ToolModels.GetSpec(appearanceId)
	local pts = ToolFx.RigPoints(spec.Parts, spec.Checks and spec.Checks.WorkingEnd)
	local half = math.min((pts.B.X - pts.A.X) / 2, cfg.Width)
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Name, a1.Name = "FxTrailA", "FxTrailB"
	a0.Position = Vector3.new(pts.Tip.X - half, pts.Tip.Y, 0) * scale
	a1.Position = Vector3.new(pts.Tip.X + half, pts.Tip.Y, 0) * scale
	a0.Parent, a1.Parent = handle, handle
	local trail = Instance.new("Trail")
	trail.Name = "FxTrail"
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(hex(cfg.Color))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, cfg.Transparency), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = cfg.Lifetime
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 0
	trail.Enabled = false -- only ever on during a strike
	trail.Parent = handle
	return trail
end

local function trailOff(trail: Trail)
	trail.Enabled = false
	liveTrails[trail] = nil
end

-- Turns the trail on for [delay, delay + length] seconds from now, then off. A newer pulse supersedes an older one.
local function pulse(trail: Trail, delay: number, length: number)
	local token = (trailToken[trail] or 0) + 1
	trailToken[trail] = token
	task.delay(delay, function()
		if trailToken[trail] ~= token or not trail.Parent then
			return
		end
		trail.Enabled = true
		liveTrails[trail] = now() + length + 0.05
		task.delay(length, function()
			if trailToken[trail] == token and trail.Parent then
				trailOff(trail)
			end
		end)
	end)
end

local function heldAppearance(): string?
	local char = player.Character
	local tool = char and char:FindFirstChild("Shovel")
	local id = tool and (tool :: Instance):GetAttribute("AppearanceId")
	return type(id) == "string" and id or nil
end

-- Local player's swing: called by DigController at the moment a swing starts (before the server answers).
function Fx.Swing(toolId: string?, interval: number)
	local profile = ToolFx.For(toolId)
	if not profile.Trail or not ToolFx.Gate(gate, "Trail", now(), 0.1) then
		return
	end
	local appearance = heldAppearance()
	local char = player.Character
	if not appearance or not char then
		return
	end
	local container: Instance?
	local scale = 1
	if CameraController.IsActive() then
		container = Workspace.CurrentCamera and Workspace.CurrentCamera:FindFirstChild("ToolViewmodel")
		scale = ViewmodelMath.Scale
	else
		container = char:FindFirstChild("Shovel")
	end
	if not container then
		return
	end
	local trail = ensureTrail(container, appearance, profile, scale)
	if trail then
		local delay, length = ToolFx.StrikeWindow(math.min(interval, 0.5))
		pulse(trail, delay, length)
	end
end

-- Another player's strike (from the server result): a short restrained trail on THEIR held tool, only if they are close.
function Fx.OtherSwing(toolId: string?, digger: Player)
	local def = toolId and Defs.Tools[toolId]
	local profile = ToolFx.For(toolId)
	local char = digger.Character
	local tool = char and char:FindFirstChild("Shovel")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not def or not profile.Trail or not tool or not root or not nearEnough((root :: BasePart).Position) then
		return
	end
	local g = otherSwingGate[digger]
	if not g then
		g = {}
		otherSwingGate[digger] = g
	end
	if not ToolFx.Gate(g, "Trail", now(), 0.25) then
		return
	end
	local appearance = (tool :: Instance):GetAttribute("AppearanceId")
	if type(appearance) ~= "string" then
		return
	end
	local trail = ensureTrail(tool :: Instance, appearance, profile, 1)
	if trail then
		local delay, length = ToolFx.StrikeWindow(math.min(1 / def.Rate, 0.5))
		pulse(trail, delay, length)
	end
end

-- Cleanup -----------------------------------------------------------------------------------------------------------------------------------
local function disableTrailsUnder(root: Instance?)
	if not root then
		return
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Trail") and d.Name == "FxTrail" then
			trailToken[d] = (trailToken[d] or 0) + 1 -- cancels any pending pulse
			trailOff(d)
		end
	end
end

-- The local player's own tool effects stop now: trails off, rings/streaks gone, no pending pulses. (Menus, focus loss, carrying, unequip.)
function Fx.StopOwn()
	for trail in pairs(liveTrails) do
		trailToken[trail] = (trailToken[trail] or 0) + 1
		trailOff(trail)
	end
	disableTrailsUnder(player.Character)
	disableTrailsUnder(Workspace.CurrentCamera)
	for i = #rings, 1, -1 do
		local p = rings[i]
		table.remove(rings, i)
		p:Destroy()
	end
	for i = #streaks, 1, -1 do
		local p = streaks[i]
		table.remove(streaks, i)
		p:Destroy()
	end
	if puffEmitter then
		puffEmitter:Clear()
	end
	table.clear(gate)
end

-- Everything: also the airborne debris and sparks (death, respawn, a new mine).
function Fx.StopAll()
	Fx.StopOwn()
	table.clear(otherGate)
	Effects.ClearTransient()
end

-- Test/inspection hooks (counts of live effect objects; no gameplay use).
function Fx.Counts()
	local trails = 0
	for trail in pairs(liveTrails) do
		if trail.Enabled then
			trails += 1
		end
	end
	return { Rings = #rings, Streaks = #streaks, Trails = trails }
end

function Fx.Init()
	Effects.SetFx(Fx)

	-- safety net: a trail left on for any reason is forced off once its strike window is over
	RunService.Heartbeat:Connect(function()
		local t = now()
		for trail, offAt in pairs(liveTrails) do
			if t > offAt or not trail:IsDescendantOf(Workspace) then
				trailOff(trail)
			end
		end
	end)

	local function onCharacter(char: Model)
		Fx.StopAll() -- respawn: nothing from the previous life survives
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then
			(hum :: Humanoid).Died:Connect(Fx.StopAll)
		end
		char.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				Fx.StopOwn() -- unequipped / replaced / stowed for carrying
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(Fx.StopAll)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	local lastTool: string? = nil
	State.Connect(function(d)
		if d.Carrying or (lastTool and d.ToolId ~= lastTool) then
			Fx.StopOwn()
		end
		lastTool = d.ToolId
	end)
	InputMode.OnChanged(Fx.StopOwn) -- a menu opened / free cursor toggled
	GuiService.MenuOpened:Connect(Fx.StopOwn)
	UserInputService.WindowFocusReleased:Connect(Fx.StopOwn)
end

return Fx
