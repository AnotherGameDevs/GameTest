-- Developer test panel (docs/DEVELOPER_MODE.md). This is only a front end: the SERVER decides who may use developer mode (it puts `Dev` in the player
-- state only for authorised accounts) and re-checks permission on every request. The panel does not exist for ordinary players: nothing is built
-- until the server says `Dev.Allowed`, and a hand-fired DevRequest from anyone else is ignored by the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)

local State = require(script.Parent.State)
local InputMode = require(script.Parent.InputMode)
local Bindings = require(script.Parent.Bindings)
local K = require(script.Parent.UIKit)

local P = Config.Palette
local mk, corner, stroke, label = K.mk, K.corner, K.stroke, K.label
local T = K.Tokens
local AMBER = Color3.fromHex("E8A33D")

local DevPanel = {}

local gui: ScreenGui? = nil
local indicator: any = nil
local indicatorText: any = nil
local devButton: any = nil
local window: any = nil
local statusLabel: any = nil
local sessionLabel: any = nil
local enterBtn: any = nil
local exitBtn: any = nil
local list: any = nil
local open = false
local built = false
local selectedTreasure: string = "old_coin"
local treasureButtons: { [string]: TextButton } = {}
local toolButtons: { [string]: TextButton } = {}
local packButtons: { [string]: TextButton } = {}
local requiresTest: { TextButton } = {}

local function send(action: string, arg: any?)
	Remotes.Get("DevRequest"):FireServer(action, arg)
end

local function section(title: string, order: number)
	label(list, title:upper(), 15, AMBER, { Size = UDim2.new(1, -8, 0, 22), LayoutOrder = order, TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 1 })
end

local function row(order: number, height: number?): Frame
	local f = mk("Frame", { Size = UDim2.new(1, -8, 0, height or 34), BackgroundTransparency = 1, LayoutOrder = order }, list)
	mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	return f
end

local function action(parent: Instance, text: string, width: number, act: string, arg: any?, needsTest: boolean?): TextButton
	local b = K.flatButton(parent, text, UDim2.new(0, width, 1, 0), UDim2.new(), AMBER)
	b.TextSize = 14
	b.TextWrapped = true
	b.Activated:Connect(function()
		-- `arg` may be a function so a button can send a value that is only known at click time (the selected artifact)
		send(act, type(arg) == "function" and arg() or arg)
	end)
	if needsTest ~= false then
		table.insert(requiresTest, b)
	end
	return b
end

local function build(parentGui: ScreenGui)
	gui = parentGui

	-- Always-visible indicator while the test overlay is active ---------------------------------------------------------------
	indicator = mk("Frame", { Name = "DevIndicator", Size = UDim2.fromOffset(330, 26), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4),
		BackgroundColor3 = Color3.fromHex("4A1F1A"), BackgroundTransparency = 0.1, Visible = false }, parentGui)
	corner(indicator, 8)
	stroke(indicator, P.Danger, 2)
	indicatorText = label(indicator, "DEVELOPER TEST MODE", 15, P.Cream, { Size = UDim2.fromScale(1, 1), TextStrokeTransparency = 1 })

	devButton = mk("TextButton", { Name = "DevButton", Text = "DEV", Size = UDim2.fromOffset(44, 28), Position = UDim2.new(1, -54, 0, 122), Font = K.Font,
		TextSize = 15, TextColor3 = P.Dark, BackgroundColor3 = AMBER, AutoButtonColor = true, Visible = false }, parentGui)
	corner(devButton, 8)
	stroke(devButton, P.Dark, 2)
	devButton.Activated:Connect(function()
		DevPanel.Toggle()
	end)

	-- Window -------------------------------------------------------------------------------------------------------------------
	window = mk("Frame", { Name = "DevPanel", Size = UDim2.fromOffset(440, 560), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = T.Panel, BackgroundTransparency = 0.03, Visible = false, Active = true }, parentGui)
	corner(window, 12)
	stroke(window, AMBER, 2)
	K.fit(window, 440, 560)
	label(window, "DEVELOPER TEST MODE", 22, AMBER, { Size = UDim2.new(1, -60, 0, 28), Position = UDim2.fromOffset(16, 8), TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 1 })
	statusLabel = label(window, "", 14, P.Cream, { Size = UDim2.new(1, -32, 0, 18), Position = UDim2.fromOffset(16, 38), TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 1 })
	sessionLabel = label(window, "", 13, K.Muted, { Size = UDim2.new(1, -32, 0, 18), Position = UDim2.fromOffset(16, 56), TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 1 })
	local close = K.flatButton(window, "X", UDim2.fromOffset(34, 30), UDim2.new(1, -44, 0, 8), T.Line)
	close.Activated:Connect(function()
		DevPanel.Close()
	end)

	list = mk("ScrollingFrame", { Size = UDim2.new(1, -24, 1, -92), Position = UDim2.fromOffset(12, 80), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, window)
	mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)

	local o = 0
	local function nextOrder(): number
		o += 1
		return o
	end

	section("Mode", nextOrder())
	local r = row(nextOrder())
	enterBtn = action(r, "ENTER TEST MODE", 200, "Enter", nil, false)
	exitBtn = action(r, "EXIT TEST MODE", 200, "Exit", nil, false)
	local rf = row(nextOrder())
	action(rf, "FRESH TEST PROFILE", 200, "FreshProfile")
	label(rf, "real profile stays untouched", 12, K.Muted, { Size = UDim2.new(0, 200, 1, 0), TextWrapped = true, TextStrokeTransparency = 1 })

	section("Equipment", nextOrder())
	local ru = row(nextOrder())
	action(ru, "UNLOCK ALL EQUIPMENT", 410, "UnlockAll")
	for _, id in ipairs(Defs.ToolsByTier) do
		local def = Defs.Tools[id]
		local rr = row(nextOrder(), 30)
		local b = action(rr, ("T%d  %s"):format(def.Tier, def.DisplayName), 410, "Equip", { Kind = "Tool", Id = id })
		toolButtons[id] = b
	end
	local packOrder = {}
	for id in pairs(Defs.Backpacks) do
		table.insert(packOrder, id)
	end
	table.sort(packOrder, function(a, b)
		return Defs.Backpacks[a].Order < Defs.Backpacks[b].Order
	end)
	for _, id in ipairs(packOrder) do
		local def = Defs.Backpacks[id]
		local rr = row(nextOrder(), 30)
		packButtons[id] = action(rr, ("%s  (%d slots)"):format(def.DisplayName, def.Capacity), 410, "Equip", { Kind = "Backpack", Id = id })
	end

	section("Cash", nextOrder())
	local rc = row(nextOrder())
	for _, amount in ipairs({ 1000, 10000, 100000 }) do
		action(rc, "+" .. Util.FormatCashShort(amount), 96, "GrantCash", amount)
	end
	local box = mk("TextBox", { Size = UDim2.fromOffset(100, 34), BackgroundColor3 = T.PanelLight, TextColor3 = P.Cream, Font = K.Font, TextSize = 15,
		PlaceholderText = "amount", Text = "", ClearTextOnFocus = false }, rc)
	corner(box, 6)
	box.FocusLost:Connect(function(enter)
		local n = tonumber(box.Text)
		if enter and n then
			send("GrantCash", n)
		end
	end)

	section("Collection and displays", nextOrder())
	local rl = row(nextOrder())
	action(rl, "UNLOCK ALL ENTRIES + FILL SHELF", 410, "UnlockCollection")

	section("Artifacts  (pick one, then act)", nextOrder())
	local ids = {}
	for id in pairs(Defs.Treasure) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local da, db = Defs.Treasure[a], Defs.Treasure[b]
		local ra, rb = Defs.Rarity[da.Rarity].Order, Defs.Rarity[db.Rarity].Order
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	for _, id in ipairs(ids) do
		local def = Defs.Treasure[id]
		local rr = row(nextOrder(), 28)
		local b = K.flatButton(rr, ("%s  -  %s  -  %s"):format(def.Name, def.Rarity, Defs.KindOf(def)), UDim2.new(0, 410, 1, 0), UDim2.new(), T.Line)
		b.TextSize = 14
		b.Activated:Connect(function()
			selectedTreasure = id
			DevPanel.Refresh()
		end)
		treasureButtons[id] = b
	end
	local ra = row(nextOrder())
	local function selected()
		return selectedTreasure
	end
	action(ra, "SPAWN SELECTED (its own flow)", 200, "SpawnArtifact", selected)
	action(ra, "REVEAL ONLY (inspect)", 200, "Reveal", selected)

	section("Relic event (two players to test PvP)", nextOrder())
	local rr = row(nextOrder())
	action(rr, "START SERVER RELIC EVENT", 410, "StartRelic")

	section("Move to a layer (existing landings)", nextOrder())
	local rt = row(nextOrder())
	action(rt, "CAMP", 78, "Teleport", 1)
	for i, layer in ipairs(Config.Layers) do
		action(rt, layer.Name, 78, "Teleport", i + 1)
	end

	section("Mine", nextOrder())
	local rm = row(nextOrder())
	action(rm, "REQUEST MINE RESET (normal lifecycle)", 410, "ResetMine")
end

local function apply(d)
	local dev = d.Dev
	if not dev or not dev.Allowed then
		if indicator then
			indicator.Visible = false
		end
		if devButton then
			devButton.Visible = false
		end
		if open then
			DevPanel.Close()
		end
		return
	end
	if not built and gui then
		built = true
		build(gui :: ScreenGui)
	end
	if not built then
		return
	end
	indicator.Visible = dev.Active == true
	;devButton.Visible = true
	;statusLabel.Text = dev.Active and "TEST OVERLAY ACTIVE - nothing here is saved" or "Test mode OFF - your real profile is active"
	;statusLabel.TextColor3 = dev.Active and P.Danger or K.Good
	;sessionLabel.Text = "Session: " .. tostring(dev.Session)
	;indicatorText.Text = dev.Active and "DEVELOPER TEST MODE  -  nothing is saved" or "DEVELOPER TEST MODE"
	;enterBtn.Visible = not dev.Active
	;exitBtn.Visible = dev.Active
	for _, b in ipairs(requiresTest) do
		b.AutoButtonColor = dev.Active
		b.TextTransparency = dev.Active and 0 or 0.55
	end
	-- selection highlights (what is equipped / owned right now in the overlay)
	for id, b in pairs(toolButtons) do
		local s = b:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = (d.ToolId == id) and P.Teal or AMBER
			s.Thickness = (d.ToolId == id) and 3 or 2
		end
		b.TextColor3 = (d.OwnedTools and d.OwnedTools[id]) and P.Cream or K.Muted
	end
	for id, b in pairs(packButtons) do
		local s = b:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = (d.BackpackId == id) and P.Teal or AMBER
			s.Thickness = (d.BackpackId == id) and 3 or 2
		end
		b.TextColor3 = (d.OwnedBackpacks and d.OwnedBackpacks[id]) and P.Cream or K.Muted
	end
end

function DevPanel.Refresh()
	for id, b in pairs(treasureButtons) do
		local s = b:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = (id == selectedTreasure) and P.Teal or T.Line
			s.Thickness = (id == selectedTreasure) and 3 or 2
		end
	end
end

function DevPanel.Open()
	if not built or open then
		return
	end
	open = true
	;window.Visible = true
	InputMode.OpenMenu("dev")
	DevPanel.Refresh()
end

function DevPanel.Close()
	if not open then
		return
	end
	open = false
	if window then
		window.Visible = false
	end
	InputMode.CloseMenu("dev")
end

function DevPanel.Toggle()
	if open then
		DevPanel.Close()
	else
		DevPanel.Open()
	end
end

function DevPanel.SelectedTreasure(): string
	return selectedTreasure
end

function DevPanel.Build(parentGui: ScreenGui)
	gui = parentGui
end

function DevPanel.Init()
	State.Connect(apply)
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Bindings.DevPanel and built and not UserInputService:GetFocusedTextBox() then
			DevPanel.Toggle()
		end
	end)
end

return DevPanel
