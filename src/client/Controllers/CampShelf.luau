-- Personal camp display. Built ENTIRELY on this client from the local player's saved Display list, so other players never
-- see it and it never shows anyone else's finds. (The "only you see this" explanation lives in the Journal, not on the
-- world sign.) It is plain, non-colliding parts in a local folder: nothing replicates and it cannot collide with the world.
-- Artifacts are the SAME source models used by reveals, carrying and the journal (TreasureModels), fitted to one common
-- size so they sit consistently on their pedestals, with a name plate on the shelf front (never on the pedestal itself).
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
local PLINTH_STONE = Color3.fromHex("8A8F96")
local SPACING = 2.7 -- distance between pedestals along Z
local ARTIFACT_SIZE = 1.8 -- every artifact's largest side, in studs
local BASE_H, PLINTH_H = 1.0, 0.6 -- shelf base height, pedestal height

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

-- A text plate that fits any name: scaled text with a size cap, wrapped to two lines, on its own SurfaceGui.
local function textPlate(plate: Part, face: Enum.NormalId, text: string, color: Color3, maxSize: number)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.Parent = plate
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextWrapped = true
	l.TextColor3 = color
	l.Text = text
	l.Parent = gui
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = 8
	limit.Parent = l
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
	local span = (slots - 1) * SPACING
	local ground = c.Y + 0.5 -- camp floor top (WorldCamp)
	local length = span + 3.4
	local topY = ground + BASE_H + PLINTH_H -- pedestal top
	local roofY = ground + 4.4

	-- frame: back board (west), base, roof, two posts. The shelf FACES east, toward the arrival area.
	part(f, "Back", V(0.4, 4.0, length), V(c.X - 0.8, ground + 2.0, c.Z), WOOD_DARK)
	part(f, "Base", V(2.0, BASE_H, length), V(c.X, ground + BASE_H / 2, c.Z), WOOD)
	part(f, "Roof", V(2.2, 0.35, length + 0.2), V(c.X, roofY, c.Z), WOOD_DARK)
	for _, dz in ipairs({ -(length / 2 - 0.2), length / 2 - 0.2 }) do
		part(f, "Post", V(0.4, roofY - ground, 0.4), V(c.X + 0.8, ground + (roofY - ground) / 2, c.Z + dz), WOOD_DARK)
	end

	-- one modest heading on the roof's front edge: "<name>'s Collection"
	local board = part(f, "Sign", V(0.2, 0.7, math.min(length, 7.4)), V(c.X + 1.15, roofY + 0.55, c.Z), SIGN, Enum.Material.SmoothPlastic)
	textPlate(board, Enum.NormalId.Right, ("%s's Collection"):format(player.DisplayName), Config.Palette.Gold, 26)

	for i = 1, slots do
		local z = c.Z - span / 2 + (i - 1) * SPACING
		part(f, "Plinth" .. i, V(1.5, PLINTH_H, 1.9), V(c.X + 0.1, ground + BASE_H + PLINTH_H / 2, z), PLINTH_STONE, Enum.Material.Slate)
		local id = display[i]
		if id then
			local def = Defs.Treasure[id]
			local model = TreasureModels.BuildDisplay(id, def, ARTIFACT_SIZE)
			model.Parent = f
			-- face east (+X), pose for the viewer, then rest it on the pedestal top with a hair of clearance
			model:PivotTo(CFrame.Angles(0, math.rad(90), 0) * TreasureModels.DisplayRotation(id))
			local cf, size = model:GetBoundingBox()
			local offset = V(c.X + 0.1, topY + 0.03 + size.Y / 2, z) - cf.Position
			model:PivotTo(model:GetPivot() + offset)
			-- name plate on the shelf front, under the pedestal
			local plate = part(f, "Plate" .. i, V(0.08, 0.62, 2.3), V(c.X + 1.04, ground + BASE_H / 2, z), SIGN, Enum.Material.SmoothPlastic)
			textPlate(plate, Enum.NormalId.Right, def.Name, Defs.Rarity[def.Rarity].Color, 22)
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
