-- Small constructors shared by the HUD and the shop (all UI is built from code).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local P = Config.Palette
local UIKit = {}

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

return UIKit
