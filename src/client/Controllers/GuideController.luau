-- First-time hints ("tutorial"). One short card at a time, bottom-centre, chosen by the pure GuideSpec from the server
-- snapshot. Rules:
--   * The card is ONE plain Frame that owns its background, outline, title, text and Skip button. When there is no active
--     hint the whole Frame is hidden (Visible = false), so an empty outline can never be left on screen. (The earlier
--     version faded a CanvasGroup; a UIStroke on a CanvasGroup is drawn outside the group and ignores GroupTransparency,
--     so the gold outline stayed behind after the text faded.) There are no tweens or delayed callbacks any more, so an old
--     step cannot reappear later.
--   * A hint ends when the player has done the thing (saved on the server via GuideDone), after its timeout, or when they use
--     the thing it points at. Finished hints are part of the profile: they do not replay after death, respawn or rejoin.
--   * It is hidden while any menu (shop, settings, journal, Roblox menu) is open and comes back only if still relevant.
--   * "Skip tutorial" (card button or Settings) and "Restart tutorial" (Settings) go through GuideControl on the server.
--   * Guidance is separate from objectives and toasts; hiding it never touches those.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Grid = require(ReplicatedStorage.Shared.Grid)
local GuideSpec = require(ReplicatedStorage.Shared.GuideSpec)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

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

local card: Frame? = nil
local titleLabel: TextLabel
local bodyLabel: TextLabel
local current: string? = nil
local shownAt = 0
local sent: { [string]: boolean } = {} -- ids already reported to the server (cleared on restart)
local depthMeters = 0
local acc = 0
local initialized = false

local function names()
	return {
		Dig = "LEFT CLICK",
		Sell = Bindings.Name(Bindings.ReturnToCamp),
		Place = Bindings.Name(Bindings.PlaceArtifact),
		Journal = Bindings.Name(Bindings.Journal),
	}
end

local function markDone(id: string)
	if sent[id] then
		return
	end
	sent[id] = true
	Remotes.Get("GuideDone"):FireServer(id)
end

-- The ONLY place the card is shown or hidden. Hiding hides the entire container.
local function show(id: string?)
	local c = card
	if not c then
		return
	end
	if id == current and c.Visible == (id ~= nil) then
		return
	end
	if id ~= current then
		shownAt = os.clock()
	end
	current = id
	c.Visible = id ~= nil
end

local function refresh()
	if not card or not State.Loaded then
		return
	end
	local d = State.Data
	local guide = d.Guide or {}
	local s = GuideSpec.StateFrom(d, d.GuideBase, { Touch = TOUCH, depthMeters = depthMeters })
	-- retire anything already accomplished (saved on the server, so it never comes back)
	for _, id in ipairs(GuideSpec.NewlySatisfied(s, guide)) do
		markDone(id)
	end
	local done = setmetatable({ skipped = guide.skipped == true }, { __index = function(_, id)
		return guide[id] or sent[id]
	end })
	local id = GuideSpec.Active(s, done)
	-- a timed hint that has been up long enough is finished
	if id and GuideSpec.Timeout[id] and current == id and os.clock() - shownAt >= GuideSpec.Timeout[id] then
		markDone(id)
		id = GuideSpec.Active(s, done)
	end
	-- never on top of a menu; it returns afterwards only if still the active step
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

-- Skip tutorial: hide at once (no waiting for the server), record completion on the server.
function GuideController.Skip()
	show(nil)
	for _, id in ipairs(GuideSpec.Order) do
		sent[id] = true
	end
	Remotes.Get("GuideControl"):FireServer("skip")
end

-- Restart tutorial: forget what this client already reported; the server wipes the saved progress and sets a baseline.
function GuideController.Restart()
	table.clear(sent)
	Remotes.Get("GuideControl"):FireServer("restart")
end

function GuideController.IsSkipped(): boolean
	return State.Data.Guide ~= nil and State.Data.Guide.skipped == true
end

function GuideController.Build(gui: ScreenGui)
	if card then
		return -- one tutorial interface only
	end
	local c = mk("Frame", { Name = "GuideCard", Size = UDim2.fromOffset(430, 92), AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, TOUCH and -150 or -84), BackgroundColor3 = T.Panel, BackgroundTransparency = 0.08,
		Visible = false, Active = false }, gui)
	corner(c, T.Corner)
	stroke(c, T.Accent, 2) -- the outline lives on the same Frame that is hidden
	mk("UISizeConstraint", { MaxSize = Vector2.new(430, 100) }, c)
	titleLabel = label(c, "", 15, T.Accent, { Size = UDim2.new(1, -150, 0, 20), Position = UDim2.fromOffset(12, 6),
		TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
	bodyLabel = label(c, "", 16, P.Cream, { Size = UDim2.new(1, -24, 0, 52), Position = UDim2.fromOffset(12, 28),
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextStrokeTransparency = 1 })
	local skip = K.flatButton(c, "Skip tutorial", UDim2.fromOffset(110, 20), UDim2.new(1, -122, 0, 5), nil)
	skip.TextSize = 12
	skip.Name = "SkipButton"
	skip.Activated:Connect(GuideController.Skip)
	card = c
end

function GuideController.Init()
	if initialized then
		return -- no duplicate event connections
	end
	initialized = true
	State.Connect(refresh)
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
