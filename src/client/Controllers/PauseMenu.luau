-- In-game menu: Resume / Settings / Controls. A multiplayer menu: nothing is paused or frozen on the server, no
-- invulnerability, carry state and return-to-camp restrictions are untouched. It only claims the cursor through
-- InputMode (so it can never fight the shop or the free-cursor toggle) and releases it again on close.
-- Roblox's own Escape menu is left alone.
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SettingsSpec = require(ReplicatedStorage.Shared.SettingsSpec)

local Settings = require(script.Parent.Settings)
local InputMode = require(script.Parent.InputMode)
local Bindings = require(script.Parent.Bindings)
local Audio = require(script.Parent.AudioController)
local K = require(script.Parent.UIKit)
local Guide = require(script.Parent.GuideController)

local P = Config.Palette
local mk, corner, stroke, label = K.mk, K.corner, K.stroke, K.label

local PauseMenu = {}

local PANEL = Color3.fromHex("1F2328")
local PANEL_LIGHT = Color3.fromHex("2A3037")
local LINE = Color3.fromHex("3A414A")
local AMBER = Color3.fromHex("D9A441")
local TEAL = P.Teal
local MUTED = Color3.fromHex("A8A394")

local root: Frame
local pages: { [string]: Frame } = {}
local open = false
local syncers: { () -> () } = {}

local function showPage(name: string)
	for n, f in pairs(pages) do
		f.Visible = (n == name)
	end
end

-- Buttons ------------------------------------------------------------------------------------------------------
local flatButton = K.flatButton

-- Slider with a numeric field. The field takes exact values (fine adjustment); the slider snaps to the spec's step.
local function makeSlider(parent: Instance, y: number, key: string, title: string, fmt: string, hint: string?)
	local def = SettingsSpec.Defs[key]
	label(parent, title, 18, P.Cream, { Size = UDim2.fromOffset(200, 22), Position = UDim2.fromOffset(0, y),
		TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
	local hit = mk("Frame", { Size = UDim2.fromOffset(250, 26), Position = UDim2.fromOffset(0, y + 26), BackgroundTransparency = 1, Active = true }, parent)
	local track = mk("Frame", { Size = UDim2.new(1, 0, 0, 6), Position = UDim2.fromOffset(0, 10), BackgroundColor3 = LINE }, hit)
	corner(track, 3)
	local fill = mk("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = TEAL }, track)
	corner(fill, 3)
	local knob = mk("Frame", { Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
		BackgroundColor3 = P.Cream }, track)
	corner(knob, 8)

	local field = mk("TextBox", { Size = UDim2.fromOffset(70, 28), Position = UDim2.fromOffset(264, y + 25), BackgroundColor3 = PANEL_LIGHT,
		TextColor3 = P.Cream, Font = K.Font, TextSize = 18, ClearTextOnFocus = false, Text = "" }, parent)
	corner(field, 6)
	stroke(field, LINE, 2)

	local function sync()
		local v = Settings.Get(key)
		local alpha = (v - def.Min) / (def.Max - def.Min)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		if not field:IsFocused() then
			field.Text = fmt:format(v)
		end
	end
	table.insert(syncers, sync)

	local dragging = false
	local function setFromX(x: number)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		Settings.Set(key, def.Min + alpha * (def.Max - def.Min))
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	field.FocusLost:Connect(function()
		local n = tonumber(field.Text)
		if n then
			Settings.Set(key, n)
		end
		sync() -- always re-show the (clamped) real value
	end)

	if hint then
		label(parent, hint, 13, MUTED, { Size = UDim2.fromOffset(330, 16), Position = UDim2.fromOffset(0, y + 54),
			TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
	end
	return sync
end

local function makeToggle(parent: Instance, y: number, key: string, title: string)
	label(parent, title, 18, P.Cream, { Size = UDim2.fromOffset(230, 28), Position = UDim2.fromOffset(0, y),
		TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
	local b = flatButton(parent, "", UDim2.fromOffset(84, 28), UDim2.fromOffset(250, y), nil)
	b.TextSize = 16
	local function sync()
		local on = Settings.Get(key)
		b.Text = on and "ON" or "OFF"
		b.TextColor3 = on and TEAL or MUTED
	end
	table.insert(syncers, sync)
	b.Activated:Connect(function()
		Audio.Play("UI")
		Settings.Set(key, not Settings.Get(key))
	end)
end

-- Pages ----------------------------------------------------------------------------------------------------------
local function buildMain(parent: Instance)
	local page = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, parent)
	pages.Main = page
	local items = { { "Resume", function() PauseMenu.Close() end }, { "Settings", function() showPage("Settings") end },
		{ "Controls", function() showPage("Controls") end } }
	for i, it in ipairs(items) do
		local b = flatButton(page, it[1], UDim2.fromOffset(300, 50), UDim2.fromOffset(20, 10 + (i - 1) * 62), i == 1 and AMBER or nil)
		b.Activated:Connect(function()
			Audio.Play("UI")
			it[2]()
		end)
	end
	label(page, "The game keeps running for everyone else.", 14, MUTED, { Size = UDim2.fromOffset(300, 20),
		Position = UDim2.fromOffset(20, 206), TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
end

local function subHeader(page: Instance, title: string)
	label(page, title, 22, AMBER, { Size = UDim2.fromOffset(200, 28), Position = UDim2.fromOffset(20, 0),
		TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
	local back = flatButton(page, "Back", UDim2.fromOffset(80, 28), UDim2.fromOffset(260, 0), nil)
	back.TextSize = 16
	back.Activated:Connect(function()
		Audio.Play("UI")
		showPage("Main")
	end)
end

local function buildSettings(parent: Instance)
	local page = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, parent)
	pages.Settings = page
	subHeader(page, "Settings")
	local body = mk("Frame", { Size = UDim2.fromOffset(340, 270), Position = UDim2.fromOffset(20, 40), BackgroundTransparency = 1 }, page)
	makeSlider(body, 0, "MouseSensitivity", "Mouse sensitivity", "%.2f",
		"Also follows your Roblox sensitivity setting.")
	local reset = flatButton(body, "Reset to default", UDim2.fromOffset(120, 24), UDim2.fromOffset(214, 74), nil)
	reset.TextSize = 14
	reset.Activated:Connect(function()
		Audio.Play("UI")
		Settings.Reset("MouseSensitivity")
	end)
	makeSlider(body, 100, "MasterVolume", "Master volume", "%.2f")
	makeToggle(body, 180, "CameraShake", "Camera shake")
	makeToggle(body, 216, "InvertY", "Invert vertical look")
	-- tutorial controls (the hints are separate from objectives and notifications)
	local skip = flatButton(body, "Skip tutorial", UDim2.fromOffset(160, 30), UDim2.fromOffset(0, 258), nil)
	skip.TextSize = 15
	skip.Activated:Connect(function()
		Audio.Play("UI")
		Guide.Skip()
	end)
	local restart = flatButton(body, "Restart tutorial", UDim2.fromOffset(160, 30), UDim2.fromOffset(174, 258), nil)
	restart.TextSize = 15
	restart.Activated:Connect(function()
		Audio.Play("UI")
		Guide.Restart()
	end)
end

local function buildControls(parent: Instance)
	local page = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, parent)
	pages.Controls = page
	subHeader(page, "Controls")
	local rows = {
		{ "Mine / dig", "Left mouse (hold)" },
		{ "Mining <> free cursor", Bindings.Name(Bindings.FreeCursor) },
		{ "Switch camera view", Bindings.Name(Bindings.CameraToggle) },
		{ "Return to camp", Bindings.Name(Bindings.ReturnToCamp) },
		{ "Place artifact", Bindings.Name(Bindings.PlaceArtifact) },
		{ "Throw dynamite", Bindings.Name(Bindings.ThrowDynamite) },
		{ "Interact", "E" },
		{ "Collection journal", Bindings.Name(Bindings.Journal) },
		{ "This menu", Bindings.Name(Bindings.Menu) },
		{ "Roblox menu", "Esc" },
	}
	for i, r in ipairs(rows) do
		local y = 40 + (i - 1) * 27
		label(page, r[1], 16, P.Cream, { Size = UDim2.fromOffset(190, 24), Position = UDim2.fromOffset(20, y),
			TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
		label(page, r[2], 16, AMBER, { Size = UDim2.fromOffset(150, 24), Position = UDim2.fromOffset(212, y),
			TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
	end
end

-- Public -----------------------------------------------------------------------------------------------------------
function PauseMenu.IsOpen(): boolean
	return open
end

function PauseMenu.Open()
	if open or InputMode.IsMenuOpen() then
		return -- never open on top of the shop / Roblox menu
	end
	open = true
	root.Visible = true
	showPage("Main")
	for _, s in ipairs(syncers) do
		s()
	end
	InputMode.OpenMenu("Pause")
end

function PauseMenu.Close()
	if not open then
		return
	end
	open = false
	root.Visible = false
	InputMode.CloseMenu("Pause")
end

function PauseMenu.Toggle()
	if open then
		PauseMenu.Close()
	else
		PauseMenu.Open()
	end
end

-- A gear icon built from plain frames (no font glyph dependency).
function PauseMenu.BuildGearButton(gui: ScreenGui): TextButton
	local b = mk("TextButton", { Name = "GearButton", Text = "", Size = UDim2.fromOffset(44, 44), Position = UDim2.new(1, -54, 0, 70),
		BackgroundColor3 = PANEL, BackgroundTransparency = 0.1, AutoButtonColor = true }, gui)
	corner(b, 10)
	stroke(b, LINE, 2)
	local icon = mk("Frame", { Size = UDim2.fromOffset(26, 26), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1 }, b)
	for i = 0, 7 do
		local ang = math.rad(i * 45)
		mk("Frame", { Size = UDim2.fromOffset(5, 8), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = P.Cream,
			Position = UDim2.new(0.5, math.sin(ang) * 10, 0.5, -math.cos(ang) * 10), Rotation = i * 45 }, icon)
	end
	local ring = mk("Frame", { Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = P.Cream }, icon)
	corner(ring, 9)
	local hole = mk("Frame", { Size = UDim2.fromOffset(8, 8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = PANEL }, ring)
	corner(hole, 4)
	b.Activated:Connect(function()
		Audio.Play("UI")
		PauseMenu.Toggle()
	end)
	return b
end

function PauseMenu.Build(gui: ScreenGui)
	root = mk("Frame", { Name = "PauseMenu", Size = UDim2.fromOffset(380, 400), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = PANEL, BackgroundTransparency = 0.04, Visible = false, Active = true }, gui)
	corner(root, 12)
	stroke(root, LINE, 2)
	K.fit(root, 380, 400)
	label(root, "MENU", 20, MUTED, { Size = UDim2.fromOffset(200, 24), Position = UDim2.fromOffset(20, 8),
		TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
	local body = mk("Frame", { Size = UDim2.new(1, 0, 1, -44), Position = UDim2.fromOffset(0, 40), BackgroundTransparency = 1 }, root)
	buildMain(body)
	buildSettings(body)
	buildControls(body)
	showPage("Main")
	Settings.OnChanged(function()
		for _, s in ipairs(syncers) do
			s()
		end
	end)
	for _, s in ipairs(syncers) do
		s()
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Bindings.Menu and not UserInputService:GetFocusedTextBox() then
			PauseMenu.Toggle()
		end
	end)
end

return PauseMenu
