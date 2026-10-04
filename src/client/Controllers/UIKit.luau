-- Small constructors shared by the HUD and the shop (all UI is built from code).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Workspace = game:GetService("Workspace")

local P = Config.Palette
local UIKit = {}

-- Shared interface tokens. Every window (shop, menu, journal, hint cards) takes its look from these so the game reads as
-- one interface: Fredoka for everything, one dark panel family, one gold accent, one muted text colour.
UIKit.Tokens = {
	Panel = Color3.fromHex("1F2328"), -- window body
	PanelLight = Color3.fromHex("2A3037"), -- buttons, cards, fields
	PanelSelected = Color3.fromHex("4A4130"), -- selected card
	Line = Color3.fromHex("3A414A"), -- thin borders
	Accent = P.Gold, -- primary actions, selected borders
	Info = Color3.fromHex("5BA7E8"), -- secondary actions (equip, inspect, place)
	Disabled = Color3.fromHex("5A5F66"),
	TextSize = { Title = 28, Heading = 20, Body = 16, Small = 13 },
	Corner = 10,
}

UIKit.Font = Enum.Font.FredokaOne
UIKit.Muted = Color3.fromHex("B9B2A0")
UIKit.Good = Color3.fromHex("7BD36B")
UIKit.Bad = Color3.fromHex("EF5944")
UIKit.Green = Color3.fromHex("3FA34D")

function UIKit.mk(class: string, props: { [string]: any }, parent: Instance?): any
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

function UIKit.corner(parent: Instance, r: number?)
	UIKit.mk("UICorner", { CornerRadius = UDim.new(0, r or 10) }, parent)
end

function UIKit.stroke(parent: Instance, color: Color3?, thickness: number?)
	UIKit.mk("UIStroke", { Color = color or P.Dark, Thickness = thickness or 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

function UIKit.label(parent: Instance, text: string, size: number, color: Color3?, props: { [string]: any }?): TextLabel
	local l = UIKit.mk("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextSize = size, Font = UIKit.Font,
		TextColor3 = color or P.Cream, TextStrokeTransparency = 0.5, TextStrokeColor3 = P.Dark,
	}, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

function UIKit.panel(parent: Instance, size: UDim2, pos: UDim2): Frame
	local f = UIKit.mk("Frame", { Size = size, Position = pos, BackgroundColor3 = P.Dark, BackgroundTransparency = 0.15 }, parent)
	UIKit.corner(f, 12)
	UIKit.stroke(f, P.Dark, 2)
	return f
end

function UIKit.button(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3): TextButton
	local b = UIKit.mk("TextButton", {
		Size = size, Position = pos, BackgroundColor3 = color, Text = text, TextSize = 22, Font = UIKit.Font,
		TextColor3 = P.Dark, AutoButtonColor = true, TextStrokeTransparency = 1,
	}, parent)
	UIKit.corner(b, 12)
	UIKit.stroke(b, P.Dark, 3)
	return b
end

-- Keeps a fixed-size window (designed at `w` x `h` pixels) fully on screen: scales it down on small viewports, never up.
-- Accounts for the HUD's own UIScale (clamp(height/720, 0.75, 1.4)) that the window is nested under.
function UIKit.fit(window: GuiObject, w: number, h: number, margin: number?)
	local scale = UIKit.mk("UIScale", {}, window)
	local function refit()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local vp = cam.ViewportSize
		local hud = math.clamp(vp.Y / 720, 0.75, 1.4)
		local m = margin or 0.94
		scale.Scale = math.min(1, (vp.X / hud * m) / w, (vp.Y / hud * m) / h)
	end
	refit()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refit)
	end
	return scale
end

-- A flat, consistent button (state colours come from the tokens): accent = border colour, enabled = false greys it out.
function UIKit.flatButton(parent: Instance, text: string, size: UDim2, pos: UDim2, accent: Color3?): TextButton
	local T = UIKit.Tokens
	local b = UIKit.mk("TextButton", { Size = size, Position = pos, BackgroundColor3 = T.PanelLight, Text = text, TextSize = T.TextSize.Heading,
		Font = UIKit.Font, TextColor3 = P.Cream, AutoButtonColor = true }, parent)
	UIKit.corner(b, 8)
	UIKit.stroke(b, accent or T.Line, 2)
	return b
end

return UIKit
