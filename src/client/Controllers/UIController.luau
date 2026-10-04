-- All UI is built from code (no manual UI objects). Scale-based + UIScale so it works on phones and desktop.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Util = require(ReplicatedStorage.Shared.Util)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local State = require(script.Parent.State)
local Audio = require(script.Parent.AudioController)

local P = Config.Palette
local player = Players.LocalPlayer
local UI = {}

local FONT = Enum.Font.FredokaOne
local TOUCH = UserInputService.TouchEnabled

local gui: ScreenGui
local refs: { [string]: any } = {}
local shopOpen = false
local cursorFree = false -- held "free cursor" key (first-person)
local menuCallbacks: { () -> () } = {}

local function menuChanged()
	for _, cb in ipairs(menuCallbacks) do
		task.spawn(cb)
	end
end

local function mk(class: string, props: { [string]: any }, parent: Instance?): any
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function corner(parent: Instance, r: number?)
	mk("UICorner", { CornerRadius = UDim.new(0, r or 10) }, parent)
end

local function stroke(parent: Instance, color: Color3?, thickness: number?)
	mk("UIStroke", { Color = color or P.Dark, Thickness = thickness or 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

local function label(parent: Instance, text: string, size: number, color: Color3?, props: { [string]: any }?): TextLabel
	local l = mk("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextSize = size, Font = FONT,
		TextColor3 = color or P.Cream, TextStrokeTransparency = 0.5, TextStrokeColor3 = P.Dark,
	}, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

local function panel(parent: Instance, size: UDim2, pos: UDim2): Frame
	local f = mk("Frame", { Size = size, Position = pos, BackgroundColor3 = P.Dark, BackgroundTransparency = 0.15 }, parent)
	corner(f, 12)
	stroke(f, P.Dark, 2)
	return f
end

local function button(parent: Instance, text: string, size: UDim2, pos: UDim2, color: Color3): TextButton
	local b = mk("TextButton", {
		Size = size, Position = pos, BackgroundColor3 = color, Text = text, TextSize = 22, Font = FONT,
		TextColor3 = P.Dark, AutoButtonColor = true, TextStrokeTransparency = 1,
	}, parent)
	corner(b, 12)
	stroke(b, P.Dark, 3)
	return b
end

-- Rolling cash display ---------------------------------------------------------------------
local shownCash, targetCash = 0, 0
local returnReadyAt = 0

local function toast(text: string, color: Color3)
	local l = refs.notify
	l.Text = text
	l.TextColor3 = color
	l.Visible = true
	refs.notifyToken = (refs.notifyToken or 0) + 1
	local token = refs.notifyToken
	l.TextTransparency = 0
	task.delay(2.6, function()
		if refs.notifyToken == token then
			l.Visible = false
		end
	end)
end

-- Objective ---------------------------------------------------------------------------------
local function nextAffordable(d)
	for _, item in ipairs(Defs.ShopItems()) do
		local owned = (item.Kind == "Tool" and d.OwnedTools[item.Id]) or (item.Kind == "Backpack" and d.OwnedBackpacks[item.Id])
		if not owned then
			return item, d.Cash >= item.Def.Price
		end
	end
	return nil, false
end

local function updateObjective(d)
	local text, color
	local full = d.Count >= d.Capacity
	local item, canBuy = nextAffordable(d)
	if full then
		text, color = "BACKPACK FULL! Go to the SELL ZONE at Base Camp", P.Danger
	elseif canBuy and item then
		text, color = ("You can afford the %s - visit the SHOP!"):format(item.Def.DisplayName), P.Teal
	elseif d.Count == 0 and d.Cash == 0 then
		text, color = (TOUCH and "Tap the dirt (or hold DIG) to dig!" or "Hold click on the dirt to dig!"), P.Gold
	elseif d.Count >= d.Capacity * 0.7 then
		text, color = "Backpack almost full - dig a bit more or sell!", P.Gold
	elseif d.Count > 0 then
		text, color = "Keep digging - deeper means better treasure", P.Cream
	else
		text, color = "Dig for treasure, sell it, upgrade!", P.Cream
	end
	refs.objective.Text = text
	refs.objective.TextColor3 = color
end

-- Shop ----------------------------------------------------------------------------------------
local function toolStats(def, cur): string
	local area = def.DigRadius > 0 and ("Smashes %dx%dx%d blocks"):format(def.DigRadius * 2 + 1, def.DigRadius * 2 + 1, def.DigRadius * 2 + 1)
		or "Single block"
	return ("Power %d (now %d)  -  %.1f swings/s (now %.1f)\n%s"):format(def.Power, cur.Power, def.Rate, cur.Rate, area)
end

local function renderShop()
	local list = refs.shopList
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local d = State.Data
	for i, item in ipairs(Defs.ShopItems()) do
		local def = item.Def
		local owned, equipped
		if item.Kind == "Tool" then
			owned = d.OwnedTools[item.Id]
			equipped = d.ToolId == item.Id
		else
			owned = d.OwnedBackpacks[item.Id]
			equipped = d.BackpackId == item.Id
		end
		local card = mk("Frame", { Size = UDim2.new(1, 0, 0, 120), BackgroundColor3 = P.Cream, LayoutOrder = i }, list)
		corner(card, 12)
		stroke(card, P.Dark, 3)
		label(card, def.DisplayName:upper(), 26, P.Dark, {
			Size = UDim2.new(0.62, 0, 0, 30), Position = UDim2.fromOffset(12, 8),
			TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
		local stats
		if item.Kind == "Tool" then
			stats = toolStats(def, Defs.Tools[d.ToolId])
		else
			stats = ("Carries %d treasures (now %d)\n%s"):format(def.Capacity, Defs.Backpacks[d.BackpackId].Capacity, def.Blurb or "")
		end
		label(card, stats, 16, Color3.fromHex("4A3A2A"), {
			Size = UDim2.new(0.62, 0, 0, 60), Position = UDim2.fromOffset(12, 42),
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true, TextStrokeTransparency = 1 })
		local text, color, canBuy
		if equipped and owned then
			text, color = "EQUIPPED", Color3.fromHex("B9B2A0")
		elseif owned then
			text, color = "OWNED", Color3.fromHex("B9B2A0")
		elseif d.Cash >= def.Price then
			text, color, canBuy = "BUY  " .. Util.FormatCash(def.Price), P.Gold, true
		else
			text, color = Util.FormatCash(def.Price) .. "\nneed " .. Util.FormatCash(def.Price - d.Cash) .. " more", Color3.fromHex("B9B2A0")
		end
		local b = button(card, text, UDim2.new(0.32, 0, 0, 64), UDim2.new(0.66, 0, 0.5, -32), color)
		b.TextSize = 20
		b.MouseButton1Click:Connect(function()
			if canBuy then
				Audio.Play("UI")
				Remotes.Get("RequestPurchase"):FireServer(item.Kind, item.Id)
			else
				Audio.Play("Error")
			end
		end)
	end
end

-- True while any interactive menu wants the cursor (shop, or the held free-cursor key).
function UI.IsMenuOpen(): boolean
	return shopOpen or cursorFree
end

function UI.IsShopOpen(): boolean
	return shopOpen
end

function UI.IsCursorFree(): boolean
	return cursorFree
end

function UI.OnMenuChanged(cb: () -> ())
	table.insert(menuCallbacks, cb)
end

-- First-person locks the mouse; a visible Modal button is Roblox's supported way to release it.
function UI.SetCursorFree(free: boolean)
	if cursorFree == free then
		return
	end
	cursorFree = free
	if refs.cursorFree then
		refs.cursorFree.Visible = free
	end
	menuChanged()
end

-- The single Return-to-Camp action: the button (Activated) and the R key both come through here.
-- The server owns the cooldown and answers with ReturnResult.
function UI.RequestReturnToCamp()
	if not Config.ReturnToCamp.Enabled then
		return
	end
	Audio.Play("UI")
	Remotes.Get("ReturnToCamp"):FireServer()
end

function UI.OpenShop()
	shopOpen = true
	menuChanged()
	refs.shop.Visible = true
	renderShop()
	Audio.Play("UI")
end

function UI.CloseShop()
	local was = shopOpen
	shopOpen = false
	if was then
		menuChanged()
	end
	refs.shop.Visible = false
end

-- Treasure cards --------------------------------------------------------------------------------
function UI.ShowTreasure(id: string, stored: boolean, isNew: boolean?)
	local def = Defs.Treasure[id]
	if not def then
		return
	end
	local rar = Defs.Rarity[def.Rarity]
	local big = rar.Order >= 2
	local h = big and 78 or 30
	local wrap = mk("Frame", { Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, LayoutOrder = -os.clock() * 100 }, refs.cards)
	local card = mk("CanvasGroup", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.Dark, BackgroundTransparency = 0.1,
	}, wrap)
	corner(card, 10)
	stroke(card, rar.Color, big and 4 or 2)
	local sc = mk("UIScale", { Scale = 0.6 }, card)
	if big then
		label(card, def.Name:upper(), 24, P.Cream, { Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(10, 4),
			TextXAlignment = Enum.TextXAlignment.Left })
		label(card, ("%s  -  %s"):format(def.Rarity:upper(), Util.FormatCash(def.Value)), 20, rar.Color, {
			Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(10, 38), TextXAlignment = Enum.TextXAlignment.Left })
		if isNew then
			label(card, "NEW!", 20, P.Gold, { Size = UDim2.fromOffset(60, 26), Position = UDim2.new(1, -68, 0, 6) })
		end
	else
		label(card, ("+ %s   %s"):format(def.Name, Util.FormatCash(def.Value)), 17, rar.Color, {
			Size = UDim2.new(1, -12, 1, 0), Position = UDim2.fromOffset(8, 0), TextXAlignment = Enum.TextXAlignment.Left })
	end
	if not stored then
		card.GroupColor3 = Color3.fromRGB(200, 120, 120)
	end
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(big and 3.2 or 1.8, function()
		TweenService:Create(card, TweenInfo.new(0.4), { GroupTransparency = 1 }):Play()
		task.wait(0.45)
		wrap:Destroy()
	end)
	-- keep list short
	local kids = refs.cards:GetChildren()
	local frames = {}
	for _, k in ipairs(kids) do
		if k:IsA("Frame") then
			table.insert(frames, k)
		end
	end
	if #frames > 6 then
		table.sort(frames, function(a, b) return a.LayoutOrder > b.LayoutOrder end)
		frames[1]:Destroy()
	end
end

local function showSold(amount: number, count: number)
	Audio.Play("Sell")
	local pop = refs.sold
	pop.Visible = true
	refs.soldAmount.Text = "+" .. Util.FormatCash(amount)
	refs.soldSub.Text = ("SOLD %d TREASURE%s"):format(count, count == 1 and "" or "S")
	pop.GroupTransparency = 0
	refs.soldScale.Scale = 0.5
	TweenService:Create(refs.soldScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.1 }):Play()
	refs.soldToken = (refs.soldToken or 0) + 1
	local token = refs.soldToken
	task.delay(1.6, function()
		if refs.soldToken == token then
			local tw = TweenService:Create(pop, TweenInfo.new(0.5), { GroupTransparency = 1 })
			tw:Play()
			tw.Completed:Wait()
			if refs.soldToken == token then
				pop.Visible = false
			end
		end
	end)
end

-- Build ---------------------------------------------------------------------------------------------
local function build()
	gui = mk("ScreenGui", { Name = "DigHUD", ResetOnSpawn = false, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	local scale = mk("UIScale", {}, gui)
	local function rescale()
		local vp = Workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(vp.Y / 720, 0.75, 1.4)
	end
	rescale()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- Top-left: cash + backpack
	local stats = panel(gui, UDim2.fromOffset(250, 104), UDim2.fromOffset(10, 8))
	refs.cash = label(stats, "$0", 40, P.Gold, { Size = UDim2.new(1, -16, 0, 44), Position = UDim2.fromOffset(12, 4),
		TextXAlignment = Enum.TextXAlignment.Left })
	local barBack = mk("Frame", { Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 54), BackgroundColor3 = Color3.fromHex("3A3F47") }, stats)
	corner(barBack, 8)
	refs.barFill = mk("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = P.Teal }, barBack)
	corner(refs.barFill, 8)
	refs.barText = label(barBack, "0 / 12", 16, P.Cream, { Size = UDim2.fromScale(1, 1) })
	refs.bagValue = label(stats, "Backpack worth ~$0", 15, P.Cream, { Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 80),
		TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })

	-- Top-center: objective + notify
	refs.objective = label(gui, "", 24, P.Cream, { Size = UDim2.new(0.5, 0, 0, 34), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10), TextStrokeTransparency = 0 })
	refs.notify = label(gui, "", 22, P.Cream, { Size = UDim2.new(0.5, 0, 0, 30), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 48), Visible = false })

	-- Top-right: depth
	local depth = panel(gui, UDim2.fromOffset(170, 56), UDim2.new(1, -180, 0, 8))
	refs.depth = label(depth, "SURFACE", 26, P.Cream, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 4) })
	refs.layer = label(depth, "BASE CAMP", 15, P.Gold, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 33), TextStrokeTransparency = 1 })

	-- Treasure cards (left, mid)
	refs.cards = mk("Frame", { Size = UDim2.fromOffset(260, 300), Position = UDim2.new(0, 10, 0.5, -60), BackgroundTransparency = 1 }, gui)
	mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 6) }, refs.cards)

	-- Sold popup
	refs.sold = mk("CanvasGroup", { Size = UDim2.fromOffset(360, 130), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36), BackgroundTransparency = 1, Visible = false }, gui)
	refs.soldScale = mk("UIScale", {}, refs.sold)
	refs.soldAmount = label(refs.sold, "+$0", 76, P.Gold, { Size = UDim2.new(1, 0, 0, 84), TextStrokeTransparency = 0 })
	refs.soldSub = label(refs.sold, "", 26, P.Cream, { Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 88) })

	-- Return to camp
	local ret = button(gui, TOUCH and "TO CAMP" or "TO CAMP [R]", UDim2.fromOffset(150, 46),
		UDim2.new(0, 12, 1, -(TOUCH and 230 or 70)), P.Cream)
	ret.Activated:Connect(function()
		UI.RequestReturnToCamp()
	end)
	refs.returnBtn = ret
	if not Config.ReturnToCamp.Enabled then
		ret.Visible = false
	end

	-- Shop modal
	local shop = mk("Frame", { Size = UDim2.fromOffset(560, 420), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = P.Dark, BackgroundTransparency = 0.05, Visible = false }, gui)
	corner(shop, 16)
	stroke(shop, P.Gold, 4)
	label(shop, "EQUIPMENT SHOP", 32, P.Gold, { Size = UDim2.new(1, -70, 0, 44), Position = UDim2.fromOffset(16, 6), TextXAlignment = Enum.TextXAlignment.Left })
	local close = button(shop, "X", UDim2.fromOffset(52, 44), UDim2.new(1, -62, 0, 8), P.Danger)
	close.MouseButton1Click:Connect(UI.CloseShop)
	refs.shopList = mk("ScrollingFrame", { Size = UDim2.new(1, -24, 1, -64), Position = UDim2.fromOffset(12, 56), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, shop)
	mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }, refs.shopList)
	refs.shop = shop
	-- Invisible Modal button: while the shop is visible the mouse cursor is released (even in first person).
	mk("TextButton", { Name = "CursorRelease", Text = "", BackgroundTransparency = 1, Modal = true,
		Size = UDim2.fromOffset(1, 1), Position = UDim2.fromOffset(-5, -5) }, shop)
	refs.cursorFree = mk("TextButton", { Name = "CursorFree", Text = "", BackgroundTransparency = 1, Modal = true,
		Size = UDim2.fromOffset(1, 1), Position = UDim2.fromOffset(-5, -5), Visible = false }, gui)
end

function UI.GetGui(): ScreenGui
	return gui
end

function UI.Init()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	build()

	State.Connect(function(d)
		targetCash = d.Cash
		refs.barText.Text = ("%d / %d"):format(d.Count, d.Capacity)
		local frac = math.clamp(d.Count / math.max(d.Capacity, 1), 0, 1)
		TweenService:Create(refs.barFill, TweenInfo.new(0.2), { Size = UDim2.fromScale(frac, 1) }):Play()
		refs.barFill.BackgroundColor3 = frac >= 1 and P.Danger or (frac >= 0.7 and P.Gold or P.Teal)
		refs.barText.Text = d.Count >= d.Capacity and "FULL!" or refs.barText.Text
		refs.bagValue.Text = "Backpack worth ~" .. Util.FormatCash(d.BackpackValue)
		updateObjective(d)
		if shopOpen then
			renderShop()
		end
	end)

	Remotes.Get("Sold").OnClientEvent:Connect(showSold)
	Remotes.Get("ReturnResult").OnClientEvent:Connect(function(ok: boolean, seconds: number)
		returnReadyAt = os.clock() + math.max(seconds, 0)
		if ok then
			toast("Back at Base Camp", P.Teal)
			Audio.Play("Buy")
		else
			toast(("Return to Camp ready in %ds"):format(math.max(1, math.ceil(seconds))), P.Danger)
			Audio.Play("Error")
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.R then
			return
		end
		if UserInputService:GetFocusedTextBox() or shopOpen then
			return
		end
		UI.RequestReturnToCamp()
	end)
	Remotes.Get("Notify").OnClientEvent:Connect(function(text, kind)
		local c = kind == "Danger" and P.Danger or (kind == "Good" and P.Teal or P.Cream)
		toast(text, c)
		Audio.Play(kind == "Danger" and "Error" or (kind == "Good" and "Buy" or "UI"))
	end)

	RunService.Heartbeat:Connect(function(dt)
		-- rolling cash
		if shownCash ~= targetCash then
			local diff = targetCash - shownCash
			shownCash += (math.abs(diff) < 1) and diff or diff * math.min(1, dt * 8)
			refs.cash.Text = Util.FormatCash(shownCash)
		end
		-- depth readout + auto-close shop when walking away
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local p = hrp.Position
			local m = Grid.DepthMeters(p.Y)
			local cx, cy, cz = Grid.WorldToCell(p)
			local inSite = cx >= 0 and cx < Grid.SizeX and cz >= 0 and cz < Grid.SizeZ
			if inSite and m > 0.5 then
				refs.depth.Text = ("%dm"):format(math.floor(m))
				refs.layer.Text = Defs.LayerAtCell(math.clamp(cy, 0, Grid.SizeY - 1)).Name
			else
				refs.depth.Text = "SURFACE"
				refs.layer.Text = (p - Config.Camp.Position).Magnitude < 40 and "BASE CAMP" or "DIG SITE"
			end
			if shopOpen and (p - (Config.Camp.Position + Config.Camp.ShopOffset)).Magnitude > 30 then
				UI.CloseShop()
			end
		end
		-- return-to-camp cooldown readout
		local left = returnReadyAt - os.clock()
		local idle = TOUCH and "TO CAMP" or "TO CAMP [R]"
		if left > 0 then
			refs.returnBtn.Text = ("CAMP  %ds"):format(math.ceil(left))
			refs.returnBtn.BackgroundColor3 = Color3.fromHex("B9B2A0")
		elseif refs.returnBtn.Text ~= idle then
			refs.returnBtn.Text = idle
			refs.returnBtn.BackgroundColor3 = P.Cream
		end
		-- pulse the bar when full
		if State.Data.Count >= State.Data.Capacity then
			refs.barFill.BackgroundColor3 = P.Danger:Lerp(P.Gold, (math.sin(os.clock() * 8) + 1) / 2)
		end
	end)
end

return UI
