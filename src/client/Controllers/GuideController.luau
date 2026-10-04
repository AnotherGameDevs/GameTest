-- First-time hints. One short card at a time, bottom-centre (clear of the crosshair and the HUD), chosen by the pure
-- GuideSpec from the server snapshot. A hint ends when the player has done the thing, after its timeout, or when
-- they open the thing it points at; ended hints are saved by the server (GuideDone) and never return.
-- Text always uses the CURRENT bindings. No tutorial world, no forced steps, nothing blocks play.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Grid = require(ReplicatedStorage.Shared.Grid)
local GuideSpec = require(ReplicatedStorage.Shared.GuideSpec)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CollectionSpec = require(ReplicatedStorage.Shared.CollectionSpec)

local State = require(script.Parent.State)
local InputMode = require(script.Parent.InputMode)
local Bindings = require(script.Parent.Bindings)
local K = require(script.Parent.UIKit)

local P = Config.Palette
local T = K.Tokens
local mk, corner, stroke, label = K.mk, K.corner, K.stroke, K.label
local player = Players.LocalPlayer
local TOUCH = UserInputService.TouchEnabled

local GuideController = {}

local card: Frame
local titleLabel: TextLabel
local bodyLabel: TextLabel
local current: string? = nil
local shownAt = 0
local sent: { [string]: boolean } = {} -- ids already reported to the server this session
local depthMeters = 0
local acc = 0

local function names()
	return {
		Dig = "LEFT CLICK",
		Sell = Bindings.Name(Bindings.ReturnToCamp),
		Place = Bindings.Name(Bindings.PlaceArtifact),
		Journal = Bindings.Name(Bindings.Journal),
	}
end

local function snapshot()
	local d = State.Data
	local owned = 0
	for _ in pairs(d.OwnedTools or {}) do
		owned += 1
	end
	local nextTool
	for _, id in ipairs(Defs.ToolsByTier) do
		if not (d.OwnedTools or {})[id] then
			nextTool = Defs.Tools[id]
			break
		end
	end
	local found = CollectionSpec.Totals(d.Collection or {})
	local stats = d.Stats or {}
	return {
		Cash = d.Cash or 0, Count = d.Count or 0, Capacity = math.max(d.Capacity or 1, 1),
		Stats = { BlocksDug = stats.BlocksDug or 0, CashEarned = stats.CashEarned or 0, DeepestDepth = stats.DeepestDepth or 0 },
		OwnedToolCount = owned,
		NextToolPrice = nextTool and nextTool.Price or nil,
		NextToolName = nextTool and nextTool.DisplayName or nil,
		Carrying = d.Carrying ~= nil,
		HasDeposited = (stats.RelicsExtracted or 0) > 0,
		CollectionFound = found,
		Touch = TOUCH,
		depthMeters = depthMeters,
	}
end

local function markDone(id: string)
	if sent[id] then
		return
	end
	sent[id] = true
	Remotes.Get("GuideDone"):FireServer(id)
end

local function show(id: string?)
	if id == current then
		return
	end
	current = id
	shownAt = os.clock()
	if not id then
		TweenService:Create(card, TweenInfo.new(0.25), { GroupTransparency = 1 }):Play()
		return
	end
	card.Visible = true
	TweenService:Create(card, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()
end

local function refresh()
	if not State.Loaded then
		return
	end
	local d = State.Data
	local guide = d.Guide or {}
	local s = snapshot()
	-- retire anything the player has already accomplished (saved, so it never comes back)
	for _, id in ipairs(GuideSpec.NewlySatisfied(s, guide)) do
		markDone(id)
		guide[id] = true
	end
	local done = setmetatable({}, { __index = function(_, id)
		return guide[id] or sent[id]
	end })
	local id = GuideSpec.Active(s, done)
	-- a timed hint that has been up long enough is finished
	if id and GuideSpec.Timeout[id] and current == id and os.clock() - shownAt >= GuideSpec.Timeout[id] then
		markDone(id)
		id = GuideSpec.Active(s, done)
	end
	-- never on top of a menu
	if id and InputMode.IsMenuOpen() then
		id = nil
	end
	if id then
		local title, body = GuideSpec.Text(id, s, names())
		titleLabel.Text = title
		bodyLabel.Text = body
	end
	show(id)
end

-- Called by other UI when the player uses the feature a hint points at.
function GuideController.Dismiss(id: string)
	if GuideSpec.IsValid(id) then
		markDone(id)
		refresh()
	end
end

function GuideController.Build(gui: ScreenGui)
	card = mk("CanvasGroup", { Name = "GuideCard", Size = UDim2.fromOffset(430, 76), AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, TOUCH and -150 or -84), BackgroundColor3 = T.Panel, BackgroundTransparency = 0.08,
		GroupTransparency = 1, Visible = false, Active = false }, gui)
	corner(card, T.Corner)
	stroke(card, T.Accent, 2)
	mk("UISizeConstraint", { MaxSize = Vector2.new(430, 90) }, card)
	titleLabel = label(card, "", 15, T.Accent, { Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(12, 6),
		TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
	bodyLabel = label(card, "", 16, P.Cream, { Size = UDim2.new(1, -24, 1, -30), Position = UDim2.fromOffset(12, 28),
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextStrokeTransparency = 1 })
	-- the card only informs: it must never swallow clicks meant for mining
	for _, o in ipairs(card:GetDescendants()) do
		if o:IsA("GuiObject") then
			o.Active = false
		end
	end
end

function GuideController.Init()
	State.Connect(function()
		refresh()
	end)
	InputMode.OnChanged(refresh)
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.5 then
			return
		end
		acc = 0
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local cx, _, cz = Grid.WorldToCell(hrp.Position)
			local inSite = cx >= 0 and cx < Grid.SizeX and cz >= 0 and cz < Grid.SizeZ
			depthMeters = inSite and Grid.DepthMeters(hrp.Position.Y) or 0
		end
		refresh()
	end)
end

return GuideController
