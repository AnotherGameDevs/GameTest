-- Collection Journal (J / the JOURNAL button): one card per artifact type with a real 3D model, rarity, home layer,
-- discovery count and a per-layer set tracker. Discovered entries can be put on the personal camp shelf.
-- Reads the saved collection from the server snapshot; writes nothing itself (the shelf choice goes through SetDisplay).
-- Important artifacts only appear as discovered after a successful DEPOSIT (server rule), so nothing here can be earned
-- by merely finding or carrying one.
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local CollectionSpec = require(ReplicatedStorage.Shared.CollectionSpec)
local TreasureModels = require(ReplicatedStorage.Shared.TreasureModels)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)

local State = require(script.Parent.State)
local InputMode = require(script.Parent.InputMode)
local Bindings = require(script.Parent.Bindings)
local Audio = require(script.Parent.AudioController)
local K = require(script.Parent.UIKit)

local P = Config.Palette
local T = K.Tokens
local mk, corner, stroke, label = K.mk, K.corner, K.stroke, K.label

local CollectionUI = {}

local W, H = 720, 470
local root: Frame
local grid: ScrollingFrame
local header: TextLabel
local setRow: Frame
local open = false
local lastKey = ""
local onOpened: (() -> ())?

local function renderKey(d): string
	local parts = {}
	for _, e in ipairs(CollectionSpec.Entries) do
		local c = d.Collection and d.Collection[e.Id]
		table.insert(parts, c and c.Count or 0)
	end
	return table.concat(parts, ",") .. "|" .. table.concat(d.Display or {}, ",")
end

local function icon(parent: Instance, id: string, def, discovered: boolean)
	local vp = mk("ViewportFrame", { Size = UDim2.fromOffset(120, 96), Position = UDim2.fromOffset(15, 8), BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 138, 124), LightColor = Color3.fromRGB(255, 244, 224), LightDirection = Vector3.new(-0.5, -1, -0.7) }, parent)
	local model = TreasureModels.BuildAny(id, def)
	local _, size = model:GetBoundingBox()
	local radius = math.max(size.Magnitude / 2, 1.2)
	model.Parent = vp
	model:PivotTo(CFrame.Angles(0, math.rad(-28), 0) * CFrame.Angles(math.rad(14), 0, 0))
	local cam = mk("Camera", { FieldOfView = 32 }, vp)
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 0, radius / math.sin(math.rad(16)) * 1.1), Vector3.zero)
	vp.CurrentCamera = cam
	if not discovered then
		vp.ImageColor3 = Color3.new(0, 0, 0) -- silhouette only: no spoilers beyond the shape
		vp.ImageTransparency = 0.35
	end
end

local function render()
	local d = State.Data
	local collection = d.Collection or {}
	local display = CollectionSpec.SanitizeDisplay(d.Display, collection)
	local shown = {}
	for _, id in ipairs(display) do
		shown[id] = true
	end
	local found, total = CollectionSpec.Totals(collection)
	header.Text = ("COLLECTION   %d / %d   -   shelf %d / %d"):format(found, total, #display, Config.Collection.DisplaySlots)

	for _, c in ipairs(setRow:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i, set in ipairs(CollectionSpec.Sets(collection)) do
		local chip = mk("Frame", { Size = UDim2.new(0.25, -6, 1, 0), LayoutOrder = i,
			BackgroundColor3 = set.Complete and Color3.fromHex("2F4A3A") or T.PanelLight }, setRow)
		corner(chip, 8)
		stroke(chip, set.Complete and K.Good or T.Line, 2)
		label(chip, ("%s SET"):format(set.Name), 14, set.Complete and K.Good or P.Cream, { Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(0, 3), TextStrokeTransparency = 1 })
		label(chip, set.Complete and ("COMPLETE  %d/%d"):format(set.Found, set.Total) or ("%d / %d"):format(set.Found, set.Total), 14,
			set.Complete and K.Good or K.Muted, { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 24), TextStrokeTransparency = 1 })
	end

	for _, c in ipairs(grid:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i, e in ipairs(CollectionSpec.Entries) do
		local entry = collection[e.Id]
		local rar = Defs.Rarity[e.Def.Rarity]
		local card = mk("Frame", { LayoutOrder = i, BackgroundColor3 = T.PanelLight }, grid)
		corner(card, T.Corner)
		stroke(card, entry and rar.Color or T.Line, entry and 3 or 2)
		icon(card, e.Id, e.Def, entry ~= nil)
		label(card, entry and e.Def.Name:upper() or "UNDISCOVERED", 15, entry and P.Cream or K.Muted,
			{ Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 106), TextStrokeTransparency = 1, TextTruncate = Enum.TextTruncate.AtEnd })
		label(card, ("%s  -  %s"):format(e.Def.Rarity:upper(), Defs.LayerName(e.Layer)), 12, entry and rar.Color or K.Muted,
			{ Size = UDim2.new(1, -8, 0, 16), Position = UDim2.fromOffset(4, 128), TextStrokeTransparency = 1 })
		local sub
		if entry then
			sub = ("Found x%d  -  worth %s"):format(entry.Count, Util.FormatCash(e.Def.Value))
		elseif e.Def.RequiresCarry then
			sub = "Carry one home to unlock"
		else
			sub = ("Found in the %s"):format(Defs.LayerName(e.Layer):lower())
		end
		label(card, sub, 12, K.Muted, { Size = UDim2.new(1, -8, 0, 16), Position = UDim2.fromOffset(4, 144), TextStrokeTransparency = 1 })
		if entry then
			local on = shown[e.Id]
			local b = K.flatButton(card, on and "ON SHELF" or "PUT ON SHELF", UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 164),
				on and T.Accent or nil)
			b.TextSize = 13
			b.TextColor3 = on and T.Accent or P.Cream
			b.Activated:Connect(function()
				Audio.Play("UI")
				Remotes.Get("SetDisplay"):FireServer(e.Id)
			end)
		end
	end
end

function CollectionUI.IsOpen(): boolean
	return open
end

function CollectionUI.Open()
	if open or InputMode.IsMenuOpen() then
		return
	end
	open = true
	root.Visible = true
	lastKey = renderKey(State.Data)
	render()
	InputMode.OpenMenu("Journal")
	Audio.Play("UI")
	if onOpened then
		onOpened()
	end
end

function CollectionUI.Close()
	if not open then
		return
	end
	open = false
	root.Visible = false
	InputMode.CloseMenu("Journal")
end

function CollectionUI.Toggle()
	if open then
		CollectionUI.Close()
	else
		CollectionUI.Open()
	end
end

-- Called whenever the journal is first opened (the guide uses it to retire the "collection" hint).
function CollectionUI.OnOpened(cb: () -> ())
	onOpened = cb
end

function CollectionUI.Build(gui: ScreenGui)
	-- toolbar button next to the settings gear (top right, under the depth readout)
	local btn = K.flatButton(gui, "JOURNAL [" .. Bindings.Name(Bindings.Journal) .. "]", UDim2.fromOffset(124, 44), UDim2.new(1, -186, 0, 70), nil)
	btn.Name = "JournalButton"
	btn.BackgroundTransparency = 0.1
	btn.TextSize = 15
	btn.Activated:Connect(CollectionUI.Toggle)

	root = mk("Frame", { Name = "Journal", Size = UDim2.fromOffset(W, H), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = T.Panel, BackgroundTransparency = 0.03, Visible = false, Active = true }, gui)
	corner(root, 14)
	stroke(root, T.Line, 3)
	K.fit(root, W, H)
	header = label(root, "", 20, P.Cream, { Size = UDim2.new(1, -90, 0, 32), Position = UDim2.fromOffset(16, 8),
		TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
	local close = K.flatButton(root, "X", UDim2.fromOffset(40, 32), UDim2.new(1, -52, 0, 8), P.Danger)
	close.Activated:Connect(CollectionUI.Close)

	setRow = mk("Frame", { Size = UDim2.new(1, -32, 0, 48), Position = UDim2.fromOffset(16, 48), BackgroundTransparency = 1 }, root)
	mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, setRow)

	grid = mk("ScrollingFrame", { Size = UDim2.new(1, -32, 1, -112), Position = UDim2.fromOffset(16, 102), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, root)
	mk("UIGridLayout", { CellSize = UDim2.fromOffset(150, 196), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)

	State.Connect(function(d)
		if open then
			local key = renderKey(d)
			if key ~= lastKey then
				lastKey = key
				render()
			end
		end
	end)

	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Bindings.Journal and not UserInputService:GetFocusedTextBox() then
			CollectionUI.Toggle()
		end
	end)
end

return CollectionUI
