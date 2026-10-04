-- HUD + menu state. All UI is built from code (no manual UI objects). Scale-based + UIScale for phones and desktop.
-- The shop itself lives in ShopUI; shared constructors in UIKit.
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
local ShopUI = require(script.Parent.ShopUI)
local PauseMenu = require(script.Parent.PauseMenu)
local DevPanel = require(script.Parent.DevPanel)
local CollectionUI = require(script.Parent.CollectionUI)
local Banner = require(script.Parent.BannerQueue)
local Guide = require(script.Parent.GuideController)
local InputMode = require(script.Parent.InputMode)
local Bindings = require(script.Parent.Bindings)
local K = require(script.Parent.UIKit)

local P = Config.Palette
local player = Players.LocalPlayer
local mk, corner, stroke, label, panel, button = K.mk, K.corner, K.stroke, K.label, K.panel, K.button
local UI = {}

local TOUCH = UserInputService.TouchEnabled
local CARRY_BLOCKED_TEXT = "Carry your artifact back to camp, or place it down first."

local gui: ScreenGui
local refs: { [string]: any } = {}
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
	task.delay(3.0, function()
		if refs.notifyToken == token then
			l.Visible = false
		end
	end)
end

-- Objective ---------------------------------------------------------------------------------
-- The next thing worth buying: the next tool tier (if unowned) or an unowned backpack.
local function nextPurchase(d)
	local candidates = {}
	for _, id in ipairs(Defs.ToolsByTier) do
		if not d.OwnedTools[id] then
			table.insert(candidates, Defs.Tools[id])
			break
		end
	end
	-- the cheapest pack that is both unowned and bigger than the one in use (so the goal never goes backwards)
	local current = Defs.Backpacks[d.BackpackId]
	local nextPack
	for id, def in pairs(Defs.Backpacks) do
		if def.Price > 0 and not d.OwnedBackpacks[id] and (not current or def.Capacity > current.Capacity)
			and (not nextPack or def.Price < nextPack.Price) then
			nextPack = def
		end
	end
	if nextPack then
		table.insert(candidates, nextPack)
	end
	for _, def in ipairs(candidates) do
		if d.Cash >= def.Price then
			return def, true
		end
	end
	return candidates[1], false
end

local function updateObjective(d)
	local text, color
	local full = d.Count >= d.Capacity
	local item, canBuy = nextPurchase(d)
	if d.Carrying then
		text, color = ("Carry the %s to the receiving table at camp (ladder: EXIT TO CAMP)"):format(d.Carrying.Name), P.Gold
	elseif full then
		text, color = "BACKPACK FULL! Go to the SELL ZONE at Base Camp", P.Danger
	elseif canBuy and item then
		text, color = ("You can afford the %s - visit the SHOP!"):format(item.DisplayName), P.Teal
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

-- Menu state ----------------------------------------------------------------------------------------
-- All cursor ownership lives in InputMode. These wrappers keep the old call sites (shop prompt, auto-close) simple.
function UI.IsShopOpen(): boolean
	return ShopUI.IsOpen()
end

function UI.OpenShop()
	if InputMode.IsMenuOpen() then
		return
	end
	ShopUI.Open()
	InputMode.OpenMenu("Shop")
	Audio.Play("UI")
end

function UI.CloseShop()
	if ShopUI.IsOpen() then
		ShopUI.Close() -- its closed-callback releases the cursor through InputMode
	end
end

-- Return to camp / place artifact -----------------------------------------------------------------------
-- The single Return-to-Camp action: the button (Activated) and the R key both come through here. While carrying an
-- important artifact the action is blocked with an explanation; the server enforces the same rule independently.
function UI.RequestReturnToCamp()
	if not Config.ReturnToCamp.Enabled then
		return
	end
	if State.Data.Carrying then
		toast(CARRY_BLOCKED_TEXT, P.Danger)
		Audio.Play("Error")
		return
	end
	Audio.Play("UI")
	Remotes.Get("ReturnToCamp"):FireServer()
end

function UI.RequestPlaceArtifact()
	if not State.Data.Carrying then
		return
	end
	Audio.Play("UI")
	Remotes.Get("PlaceArtifact"):FireServer()
end

-- Treasure cards --------------------------------------------------------------------------------
function UI.ShowTreasure(id: string, stored: boolean, isNew: boolean?, carry: boolean?)
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
		local sub = carry and (def.Relic and ("CONTESTED RELIC  -  " .. Util.FormatCash(def.Value)) or ("IMPORTANT  -  CARRY IT TO CAMP  -  " .. Util.FormatCash(def.Value)))
			or ("%s  -  %s"):format(def.Rarity:upper(), Util.FormatCash(def.Value))
		label(card, sub, carry and 15 or 20, rar.Color, {
			Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(10, 38), TextXAlignment = Enum.TextXAlignment.Left })
		if isNew then
			label(card, "NEW!", 20, P.Gold, { Size = UDim2.fromOffset(60, 26), Position = UDim2.new(1, -68, 0, 6) })
		end
	else
		label(card, ("+ %s   %s"):format(def.Name, Util.FormatCash(def.Value)), 17, rar.Color, {
			Size = UDim2.new(1, -12, 1, 0), Position = UDim2.fromOffset(8, 0), TextXAlignment = Enum.TextXAlignment.Left })
	end
	if not stored and not carry then
		card.GroupColor3 = Color3.fromRGB(200, 120, 120)
	end
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(big and 3.2 or 1.8, function()
		TweenService:Create(card, TweenInfo.new(0.4), { GroupTransparency = 1 }):Play()
		task.wait(0.45)
		wrap:Destroy()
	end)
	local frames = {}
	for _, k in ipairs(refs.cards:GetChildren()) do
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
	Banner.Push("+" .. Util.FormatCash(amount), ("SOLD %d TREASURE%s"):format(count, count == 1 and "" or "S"), "Sell", P.Gold, 1.8)
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

	-- Compact "Carrying" indicator (under the stats panel)
	refs.carry = panel(gui, UDim2.fromOffset(250, 34), UDim2.fromOffset(10, 118))
	refs.carry.Visible = false
	stroke(refs.carry, P.Gold, 2)
	refs.carryText = label(refs.carry, "", 17, P.Gold, { Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0),
		TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })

	-- Top-center: objective + notify
	-- The centre column leaves room for the stats panel (left, 260) and the depth/buttons column (right, 190), so these
	-- can never overlap them on a narrow window: the text shrinks (TextScaled) instead.
	refs.objective = label(gui, "", 24, P.Cream, { Size = UDim2.new(1, -540, 0, 34), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10), TextStrokeTransparency = 0, TextScaled = true })
	mk("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 12 }, refs.objective)
	refs.notify = label(gui, "", 22, P.Cream, { Size = UDim2.new(1, -540, 0, 40), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 46), Visible = false, TextScaled = true, TextWrapped = true })
	mk("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 12 }, refs.notify)
	-- Fresh Dig (mine refresh) banner, under the notification line
	refs.shift = label(gui, "", 22, P.Danger, { Size = UDim2.new(1, -540, 0, 34), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90), Visible = false, TextScaled = true })
	mk("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 12 }, refs.shift)

	-- Top-right: depth
	local depth = panel(gui, UDim2.fromOffset(170, 56), UDim2.new(1, -180, 0, 8))
	refs.depth = label(depth, "SURFACE", 26, P.Cream, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 4) })
	refs.layer = label(depth, "BASE CAMP", 15, P.Gold, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 33), TextStrokeTransparency = 1 })

	-- Compact mine status (under the buttons, top right): reset countdown / state. Driven by Workspace attributes that the
	-- server maintains, so a player who joins mid-countdown sees the correct state and time immediately.
	refs.mine = panel(gui, UDim2.fromOffset(170, 48), UDim2.new(1, -180, 0, 122))
	refs.mineTitle = label(refs.mine, "MINE", 12, K.Muted, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 3), TextStrokeTransparency = 1 })
	refs.mineTime = label(refs.mine, "--:--", 22, P.Cream, { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 18) })

	-- Test-session notice: shown ONLY when this session's progress is not being saved (no DataStore / failed load in Studio). A real
	-- published server never shows it (a failed load kicks instead). It states the fact; it contains no profile data.
	refs.testNotice = panel(gui, UDim2.fromOffset(170, 44), UDim2.new(1, -180, 0, 176))
	refs.testNotice.Visible = false
	stroke(refs.testNotice, P.Danger, 2)
	refs.testNoticeText = label(refs.testNotice, "TEST SESSION - progress will not save", 13, P.Danger, { Size = UDim2.new(1, -10, 1, 0),
		Position = UDim2.fromOffset(5, 0), TextWrapped = true, TextStrokeTransparency = 1 })

	-- Treasure cards (left, mid)
	refs.cards = mk("Frame", { Size = UDim2.fromOffset(260, 300), Position = UDim2.new(0, 10, 0.5, -60), BackgroundTransparency = 1 }, gui)
	mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 6) }, refs.cards)

	-- Bottom-left stack: explanation, place artifact, return to camp
	local base = TOUCH and 230 or 70
	refs.returnBtn = button(gui, TOUCH and "TO CAMP" or ("TO CAMP [" .. Bindings.Name(Bindings.ReturnToCamp) .. "]"), UDim2.fromOffset(170, 46), UDim2.new(0, 12, 1, -base), P.Cream)
	refs.returnBtn.Activated:Connect(UI.RequestReturnToCamp)
	if not Config.ReturnToCamp.Enabled then
		refs.returnBtn.Visible = false
	end
	refs.placeBtn = button(gui, TOUCH and "PLACE ARTIFACT" or ("PLACE ARTIFACT [" .. Bindings.Name(Bindings.PlaceArtifact) .. "]"), UDim2.fromOffset(220, 46),
		UDim2.new(0, 12, 1, -(base + 54)), Color3.fromHex("5BA7E8"))
	refs.placeBtn.TextSize = 18
	refs.placeBtn.Visible = false
	refs.placeBtn.Activated:Connect(UI.RequestPlaceArtifact)
	refs.carryNote = label(gui, CARRY_BLOCKED_TEXT, 14, P.Danger, { Size = UDim2.fromOffset(250, 36),
		Position = UDim2.new(0, 12, 1, -(base + 98)), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom,
		TextWrapped = true, Visible = false })

	-- Dynamite count (desktop badge; touch gets a THROW button from ThrowController)
	refs.dynBadge = panel(gui, UDim2.fromOffset(200, 34), UDim2.new(1, -212, 1, -(TOUCH and 270 or 52)))
	refs.dynBadge.Visible = false
	refs.dynText = label(refs.dynBadge, "", 17, P.Cream, { Size = UDim2.fromScale(1, 1), TextStrokeTransparency = 1 })

	-- Shop + menu (both claim the cursor through InputMode only)
	ShopUI.Build(gui, function()
		InputMode.CloseMenu("Shop")
	end)
	Banner.Build(gui)
	PauseMenu.Build(gui)
	PauseMenu.BuildGearButton(gui)
	DevPanel.Build(gui) -- builds nothing until the server marks this account as authorised
	CollectionUI.Build(gui)
	CollectionUI.OnOpened(function()
		Guide.Dismiss("collection")
	end)
	Guide.Build(gui)
end

-- Mine reset status ---------------------------------------------------------------------------------------------------
local function clock(seconds: number): string
	seconds = math.max(math.floor(seconds + 0.5), 0)
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local lastTick = -1
local mineAcc = 0
function UI.StepMineStatus(dt: number)
	mineAcc += dt
	if mineAcc < 0.2 then
		return
	end
	mineAcc = 0
	local state = Workspace:GetAttribute("MineState") or "Active"
	local now = Workspace:GetServerTimeNow()
	local banner = refs.shift
	if state == "Warning" then
		local left = math.max((Workspace:GetAttribute("MineEndsAt") or now) - now, 0)
		if Workspace:GetAttribute("MineHold") then
			refs.mineTitle.Text = "MINE RESET"
			refs.mineTime.Text = "WAITING"
			refs.mineTime.TextColor3 = P.Gold
			banner.Text = "Reset waiting for the contested relic - deliver it or it expires"
			banner.TextColor3 = P.Gold
			banner.Visible = true
			return
		end
		local final = left <= Config.Reset.FinalCountdownSeconds
		refs.mineTitle.Text = "MINE RESETS IN"
		refs.mineTime.Text = clock(left)
		refs.mineTime.TextColor3 = final and P.Danger or P.Gold
		banner.Text = final and ("RESET IN %d - GET OUT NOW!"):format(math.ceil(left))
			or ("MINE RESETS IN %ds - leave by the ELEVATOR"):format(math.ceil(left))
		banner.TextColor3 = final and P.Danger or P.Gold
		banner.Visible = true
		local whole = math.ceil(left)
		if final and whole ~= lastTick then
			lastTick = whole
			Audio.Play("Error", 1.4, 0.8) -- one tick per second in the final countdown
		end
	elseif state == "Evacuating" or state == "Regenerating" then
		refs.mineTitle.Text = "MINE"
		refs.mineTime.Text = state == "Evacuating" and "EVACUATING" or "REBUILDING"
		refs.mineTime.TextColor3 = P.Danger
		refs.mineTime.TextSize = 18
		banner.Text = state == "Evacuating" and "Moving everyone out of the mine..." or "Rebuilding the mine..."
		banner.TextColor3 = P.Danger
		banner.Visible = true
	else
		local resetAt = Workspace:GetAttribute("MineResetAt") or 0
		local dug = Workspace:GetAttribute("MineDug") or 0
		refs.mineTitle.Text = ("MINE %d%% DUG  -  RESET IN"):format(dug)
		refs.mineTime.Text = resetAt > 0 and clock(resetAt - now) or "--:--"
		refs.mineTime.TextColor3 = P.Cream
		refs.mineTime.TextSize = 22
		banner.Visible = false
		lastTick = -1
	end
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
		-- carry UI
		refs.carry.Visible = d.Carrying ~= nil
		refs.placeBtn.Visible = d.Carrying ~= nil
		refs.carryNote.Visible = d.Carrying ~= nil
		if d.Carrying then
			refs.carryText.Text = "Carrying: " .. d.Carrying.Name
		end
		-- dynamite badge
		local dyn = d.Consumables and d.Consumables.dynamite or 0
		refs.dynBadge.Visible = dyn > 0 and not TOUCH
		refs.dynText.Text = ("DYNAMITE x%d   [%s] throw"):format(dyn, Bindings.Name(Bindings.ThrowDynamite))
		-- never present temporary defaults as saved progress
		local save = d.Save
		refs.testNotice.Visible = save ~= nil and save.Saving == false
		updateObjective(d)
		if ShopUI.IsOpen() then
			ShopUI.Render()
		end
	end)

	Remotes.Get("Sold").OnClientEvent:Connect(showSold)
	Remotes.Get("ArtifactDeposited").OnClientEvent:Connect(function(name: string, value: number, isNew: boolean?)
		Banner.Push("+" .. Util.FormatCash(value), "ARTIFACT SECURED: " .. name:upper() .. (isNew and "  -  NEW ENTRY!" or ""), "Deposit", P.Gold, 2.8)
	end)
	Remotes.Get("SetCompleted").OnClientEvent:Connect(function(layerId: string, layerName: string)
		-- Sent by the server only at the moment a set is completed (never on state updates or rejoin); the key makes it once per session too.
		Banner.Push("SET COMPLETE!", ("%s COLLECTION"):format(layerName), "SetComplete", P.Teal, 3.4, "set:" .. layerId)
	end)
	Remotes.Get("ReturnResult").OnClientEvent:Connect(function(ok: boolean, seconds: number, reason: string?)
		if reason == "CARRYING" then
			-- rejected: the cooldown is NOT consumed, so do not touch returnReadyAt
			toast(CARRY_BLOCKED_TEXT, P.Danger)
			Audio.Play("Error")
			return
		end
		returnReadyAt = os.clock() + math.max(seconds, 0)
		if ok then
			toast("Back at Base Camp", P.Teal)
			Audio.Play("UI")
		else
			toast(("Return to Camp ready in %ds"):format(math.max(1, math.ceil(seconds))), P.Danger)
			Audio.Play("Error")
		end
	end)
	Remotes.Get("Notify").OnClientEvent:Connect(function(text, kind)
		local c = kind == "Danger" and P.Danger or (kind == "Good" and P.Teal or P.Cream)
		toast(text, c)
		Audio.Play(kind == "Danger" and "Error" or (kind == "Good" and "Buy" or "UI"))
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if InputMode.IsMenuOpen() then
			return -- gameplay shortcuts are off while any menu is open
		end
		if input.KeyCode == Bindings.ReturnToCamp then
			UI.RequestReturnToCamp()
		elseif input.KeyCode == Bindings.PlaceArtifact and not TOUCH then
			UI.RequestPlaceArtifact()
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		ShopUI.Step(dt)
		-- rolling cash
		if shownCash ~= targetCash then
			local diff = targetCash - shownCash
			shownCash += (math.abs(diff) < 1) and diff or diff * math.min(1, dt * 8)
			refs.cash.Text = Util.FormatCash(shownCash)
		end
		UI.StepMineStatus(dt)
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
				local cp, cs = Config.Camp.Position, Config.Camp.Size
				local onCamp = math.abs(p.X - cp.X) <= cs.X / 2 + 4 and math.abs(p.Z - cp.Z) <= cs.Z / 2 + 4
				refs.layer.Text = onCamp and "BASE CAMP" or "DIG SITE"
			end
			if ShopUI.IsOpen() and (p - Config.Camp.ShopPosition).Magnitude > 30 then
				UI.CloseShop()
			end
		end
		-- return-to-camp button: unavailable (with explanation) while carrying, else the cooldown readout
		local idle = TOUCH and "TO CAMP" or ("TO CAMP [" .. Bindings.Name(Bindings.ReturnToCamp) .. "]")
		local left = returnReadyAt - os.clock()
		if State.Data.Carrying then
			refs.returnBtn.Text = "TO CAMP - CARRYING"
			refs.returnBtn.BackgroundColor3 = Color3.fromHex("8A8578")
			refs.returnBtn.TextSize = 16
		elseif left > 0 then
			refs.returnBtn.Text = ("CAMP  %ds"):format(math.ceil(left))
			refs.returnBtn.BackgroundColor3 = Color3.fromHex("B9B2A0")
			refs.returnBtn.TextSize = 22
		elseif refs.returnBtn.Text ~= idle then
			refs.returnBtn.Text = idle
			refs.returnBtn.BackgroundColor3 = P.Cream
			refs.returnBtn.TextSize = 22
		end
		-- pulse the bar when full
		if State.Data.Count >= State.Data.Capacity then
			refs.barFill.BackgroundColor3 = P.Danger:Lerp(P.Gold, (math.sin(os.clock() * 8) + 1) / 2)
		end
	end)
end

return UI
