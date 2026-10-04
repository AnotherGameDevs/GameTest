-- Personal camp display. Built ENTIRELY on this client from the local player's saved Display list, so other players never
-- see it and it never shows anyone else's finds (the sign says "<name>'s shelf"). It is plain parts in a local folder -
-- nothing replicates, nothing is shared geometry, and it cannot collide with the server's world.
-- Models are the same ones used by the journal (TreasureModels), scaled to fit the plinths.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local CollectionSpec = require(ReplicatedStorage.Shared.CollectionSpec)
local TreasureModels = require(ReplicatedStorage.Shared.TreasureModels)

local State = require(script.Parent.State)

local CampShelf = {}

local V = Vector3.new
local player = Players.LocalPlayer
local folder: Folder?
local lastKey = ""

local WOOD, WOOD_DARK, SIGN = Color3.fromHex("A8703E"), Color3.fromHex("6E4527"), Color3.fromHex("2A3037")
local PLINTH = 2.4 -- spacing between plinths along Z

local function part(parent: Instance, name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material or Enum.Material.Wood
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false -- decorative: never blocks or traps anyone
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = parent
	return p
end

local function build(display: { string })
	if folder then
		folder:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = "PersonalShelf"
	f.Parent = Workspace
	folder = f

	local c = Config.Collection.ShelfPosition
	local slots = Config.Collection.DisplaySlots
	local span = (slots - 1) * PLINTH
	local ground = c.Y + 0.5 -- camp floor top (WorldCamp)
	-- frame: back board (west), base, top rail, two posts. The shelf FACES east, toward the arrival area.
	part(f, "Back", V(0.4, 3.6, span + 3.2), V(c.X - 0.8, ground + 1.8, c.Z), WOOD_DARK)
	part(f, "Base", V(2.0, 0.5, span + 3.2), V(c.X, ground + 0.25, c.Z), WOOD)
	part(f, "Roof", V(2.2, 0.35, span + 3.4), V(c.X, ground + 4.0, c.Z), WOOD_DARK)
	for _, dz in ipairs({ -(span / 2 + 1.5), span / 2 + 1.5 }) do
		part(f, "Post", V(0.4, 3.8, 0.4), V(c.X + 0.8, ground + 1.9, c.Z + dz), WOOD_DARK)
	end

	-- sign on the roof's front edge (SurfaceGui, so it never shows through the wood)
	local board = part(f, "Sign", V(0.25, 0.9, span + 1.2), V(c.X + 1.15, ground + 4.6, c.Z), SIGN, Enum.Material.SmoothPlastic)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = Config.Palette.Gold
	l.Text = ("%s's SHELF  -  only you see this"):format(player.DisplayName)
	l.Parent = gui

	for i = 1, slots do
		local z = c.Z - span / 2 + (i - 1) * PLINTH
		part(f, "Plinth" .. i, V(1.4, 1.0, 1.6), V(c.X + 0.2, ground + 1.0, z), Color3.fromHex("8A8F96"), Enum.Material.Slate)
		local id = display[i]
		if id then
			local def = Defs.Treasure[id]
			local model = TreasureModels.BuildAny(id, def)
			local _, size = model:GetBoundingBox()
			model:ScaleTo(math.min(1, 2.0 / math.max(size.X, size.Y, size.Z)))
			model.Parent = f
			local _, scaled = model:GetBoundingBox()
			-- face east (+X), standing on the plinth top (plinth top = ground + 1.5)
			model:PivotTo(CFrame.new(c.X + 0.2, ground + 1.55 + scaled.Y / 2, z) * CFrame.Angles(0, math.rad(90), 0))
			local tag = Instance.new("SurfaceGui")
			tag.Face = Enum.NormalId.Right
			tag.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			tag.PixelsPerStud = 40
			tag.Parent = f:FindFirstChild("Plinth" .. i)
			local t = Instance.new("TextLabel")
			t.Size = UDim2.fromScale(1, 1)
			t.BackgroundTransparency = 1
			t.Font = Enum.Font.FredokaOne
			t.TextScaled = true
			t.TextColor3 = Defs.Rarity[def.Rarity].Color
			t.Text = def.Name
			t.Parent = tag
		end
	end
end

function CampShelf.Init()
	State.Connect(function(d)
		local display = CollectionSpec.SanitizeDisplay(d.Display, d.Collection or {})
		local key = table.concat(display, ",")
		if key ~= lastKey or not folder then
			lastKey = key
			build(display)
		end
	end)
end

return CampShelf
