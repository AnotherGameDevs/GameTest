-- One announcement banner for every big popup (sales, secured artifacts, completed collection sets). Replaces the old fixed-size popup
-- whose text could be wider than its CanvasGroup and was clipped. Rules:
--   * ONE container, centred, sized from BannerLayout (responsive; side margins; fonts chosen so the text fits, wrapping only if it must).
--   * No CanvasGroup and no scaling animation: nothing can clip, the animation is a fade + small slide.
--   * Notifications queue: simultaneous ones play one after another; a key de-duplicates (a set completion shows once per session).
--   * After its duration the WHOLE banner is hidden (Visible = false), not just faded.
--   * It sits near the top-centre: clear of the crosshair (screen centre) and of the tutorial card (bottom).
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BannerLayout = require(ReplicatedStorage.Shared.BannerLayout)
local Audio = require(script.Parent.AudioController)
local K = require(script.Parent.UIKit)

local P = Config.Palette
local mk, corner, stroke, label = K.mk, K.corner, K.stroke, K.label

local BannerQueue = {}

type Item = { Title: string, Sub: string, Sound: string?, Color: Color3?, Duration: number, Key: string? }
local queue: { Item } = {}
local seen: { [string]: boolean } = {}
local playing = false
local token = 0

local frame: Frame, titleLabel: TextLabel, subLabel: TextLabel, frameStroke: UIStroke
local built = false

local function layout(item: Item)
	local cam = Workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local l = BannerLayout.Compute(vp.X, vp.Y, #item.Title, #item.Sub)
	frame.Size = UDim2.fromOffset(l.Width, l.Height)
	frame.Position = UDim2.new(0.5, 0, 0, l.Top)
	titleLabel.TextSize = l.TitleSize
	titleLabel.Size = UDim2.fromOffset(l.Inner, l.TitleSize * 1.15 * l.TitleLines)
	titleLabel.Position = UDim2.fromOffset(l.Padding, l.Padding * 0.6)
	subLabel.TextSize = l.SubSize
	subLabel.Size = UDim2.fromOffset(l.Inner, l.SubSize * 1.2 * l.SubLines)
	subLabel.Position = UDim2.fromOffset(l.Padding, l.Padding * 0.6 + l.TitleSize * 1.15 * l.TitleLines + 6)
end

local function setTransparency(a: number)
	frame.BackgroundTransparency = 0.15 + 0.85 * a
	frameStroke.Transparency = a
	titleLabel.TextTransparency = a
	titleLabel.TextStrokeTransparency = 0.4 + 0.6 * a
	subLabel.TextTransparency = a
	subLabel.TextStrokeTransparency = 0.4 + 0.6 * a
end

local function playNext()
	local item = table.remove(queue, 1)
	if not item then
		playing = false
		frame.Visible = false -- the whole banner is hidden when nothing is showing
		return
	end
	playing = true
	token += 1
	local mine = token
	titleLabel.Text = item.Title
	subLabel.Text = item.Sub
	titleLabel.TextColor3 = item.Color or P.Gold
	frameStroke.Color = item.Color or P.Gold
	layout(item)
	setTransparency(1)
	frame.Visible = true
	if item.Sound then
		Audio.Play(item.Sound)
	end
	local info = TweenInfo.new(0.2)
	local fade = Instance.new("NumberValue")
	fade.Value = 1
	fade.Changed:Connect(function()
		if token == mine then
			setTransparency(fade.Value)
		end
	end)
	TweenService:Create(fade, info, { Value = 0 }):Play()
	task.delay(item.Duration, function()
		if token ~= mine then
			fade:Destroy()
			return
		end
		local out = TweenService:Create(fade, TweenInfo.new(0.3), { Value = 1 })
		out:Play()
		out.Completed:Once(function()
			fade:Destroy()
			if token == mine then
				playNext() -- hides the frame itself if the queue is empty
			end
		end)
	end)
end

function BannerQueue.Build(gui: ScreenGui)
	if built then
		return
	end
	built = true
	frame = mk("Frame", { Name = "AnnouncementBanner", AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = P.Dark, Visible = false,
		ClipsDescendants = false, ZIndex = 30, Active = false }, gui)
	corner(frame, 14)
	frameStroke = stroke(frame, P.Gold, 3) or frame:FindFirstChildOfClass("UIStroke")
	titleLabel = label(frame, "", 40, P.Gold, { ZIndex = 31, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top })
	subLabel = label(frame, "", 20, P.Cream, { ZIndex = 31, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top })
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if frame.Visible then
				layout({ Title = titleLabel.Text, Sub = subLabel.Text, Duration = 0 })
			end
		end)
	end
end

-- key: optional de-duplication key (e.g. "set:Soil"): a banner with a key already shown this session is ignored.
function BannerQueue.Push(title: string, sub: string, sound: string?, color: Color3?, duration: number?, key: string?)
	if key then
		if seen[key] then
			return
		end
		seen[key] = true
	end
	table.insert(queue, { Title = title, Sub = sub, Sound = sound, Color = color, Duration = duration or 2.4, Key = key })
	if #queue > 6 then
		table.remove(queue, 1) -- never let a burst of sales build an endless backlog
	end
	if not playing then
		playNext()
	end
end

return BannerQueue
