-- Client side of the contested relic (docs/RELIC_PVP.md). Everything shown here is read from server-published Workspace attributes
-- (RelicState / Name / Discoverer / CarrierId / Control): the client never learns where an UNDISCOVERED relic is, and it can only
-- *ask* for an attack with the dedicated action (RelicStrike key / button) - the server decides everything.
--   * HUD panel: relic name, who has it, the carrier's control meter, instructions.
--   * Markers: the discovered relic, then its carrier (readable, one at a time); a "deliver here" marker for the carrier.
--   * Strike / shove button (visible only while a carried relic exists and you are outside the safe zone) + key; never a mining click.
--   * Feedback: hit / shove bursts, a brief flash on the target, a single bounded knockback applied to the local character.
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RelicRules = require(ReplicatedStorage.Shared.RelicRules)

local InputMode = require(script.Parent.InputMode)
local Bindings = require(script.Parent.Bindings)
local Audio = require(script.Parent.AudioController)
local K = require(script.Parent.UIKit)

local P = Config.Palette
local T = K.Tokens
local mk, corner, stroke, label = K.mk, K.corner, K.stroke, K.label
local player = Players.LocalPlayer
local R = Config.Relic

local RelicController = {}

local panel: Frame, titleLabel: TextLabel, statusLabel: TextLabel, barFill: Frame, hintLabel: TextLabel
local announce: TextLabel
local strikeBtn: TextButton
local relicMarker: BillboardGui?, carrierMarker: BillboardGui?, depositMarker: BillboardGui?
local lastState = "None"
local lastPress = -1e9
local announceToken = 0
local initialized = false
local acc = 0

local function localHrp(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function marker(text: string, color: Color3, size: UDim2): BillboardGui
	local b = Instance.new("BillboardGui")
	b.Name = "RelicMarker"
	b.AlwaysOnTop = true -- the relic has been discovered, so its position is public information
	b.Size = size
	b.StudsOffset = Vector3.new(0, 3.2, 0)
	b.MaxDistance = 600
	b.ResetOnSpawn = false
	local l = Instance.new("TextLabel")
	l.Name = "Text"
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = K.Font
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.2
	l.TextStrokeColor3 = P.Dark
	l.Text = text
	l.Parent = b
	return b
end

local function clearMarkers()
	for _, m in ipairs({ relicMarker, carrierMarker, depositMarker }) do
		if m then
			m:Destroy()
		end
	end
	relicMarker, carrierMarker, depositMarker = nil, nil, nil
end

local function relicModel(): Model?
	local f = Workspace:FindFirstChild("RelicEvent")
	return f and f:FindFirstChildOfClass("Model") or nil
end

local function carrierHead(): BasePart?
	local id = Workspace:GetAttribute("RelicCarrierId") or 0
	local p = id ~= 0 and Players:GetPlayerByUserId(id) or nil
	local char = p and p.Character
	return char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart")) :: BasePart? or nil
end

local function showAnnouncement(text: string, color: Color3)
	announceToken += 1
	local token = announceToken
	announce.Text = text
	announce.TextColor3 = color
	announce.Visible = true
	task.delay(7, function()
		if announceToken == token then
			announce.Visible = false
		end
	end)
end

local function refresh()
	local state = Workspace:GetAttribute("RelicState") or "None"
	local name = Workspace:GetAttribute("RelicName") or ""
	local carrierId = Workspace:GetAttribute("RelicCarrierId") or 0
	local control = Workspace:GetAttribute("RelicControl") or 0
	local maxControl = math.max(Workspace:GetAttribute("RelicMaxControl") or R.MaxControl, 1)
	local active = state ~= "None"
	local iCarry = active and carrierId == player.UserId
	panel.Visible = active

	if state ~= lastState then
		if state == "Discovered" then
			showAnnouncement(("CONTESTED RELIC!  %s uncovered the %s.  Carry it to camp - the carrier can be attacked."):format(
				Workspace:GetAttribute("RelicDiscoverer") or "Someone", name), P.Danger)
		elseif state == "None" and lastState ~= "None" then
			clearMarkers()
		end
		lastState = state
	end
	if not active then
		strikeBtn.Visible = false
		return
	end

	titleLabel.Text = ("CONTESTED RELIC: %s"):format(name:upper())
	local barBack = barFill.Parent :: Frame
	barBack.Visible = state == "Carried"
	barFill.Size = UDim2.fromScale(math.clamp(control / maxControl, 0, 1), 1)
	barFill.BackgroundColor3 = control / maxControl > 0.5 and P.Teal or (control / maxControl > 0.25 and P.Gold or P.Danger)
	if state == "Carried" then
		local carrier = Players:GetPlayerByUserId(carrierId)
		if iCarry then
			statusLabel.Text = "YOU have it - control " .. tostring(math.ceil(control))
			hintLabel.Text = ("Deliver it to the RECEIVING TABLE. Attackers can hit you outside the gold SAFE ZONE line. [%s] shoves attackers."):format(Bindings.Name(Bindings.RelicStrike))
		else
			statusLabel.Text = ("%s carries it - control %d"):format(carrier and carrier.DisplayName or "Someone", math.ceil(control))
			hintLabel.Text = ("Hit the carrier with [%s] to make them drop it. No attacks inside the safe zone."):format(Bindings.Name(Bindings.RelicStrike))
		end
	else
		statusLabel.Text = state == "Dropped" and "On the ground - anyone can take it!" or "Just uncovered - take it!"
		hintLabel.Text = "Find it and use the pickup prompt. It is marked on your screen."
	end

	-- markers: the relic while it is on the ground, then its carrier
	if state ~= "Carried" then
		if carrierMarker then
			carrierMarker:Destroy()
			carrierMarker = nil
		end
		local m = relicModel()
		local root = m and m.PrimaryPart
		if root then
			local rm = relicMarker or marker(("RELIC: %s"):format(name), P.Gold, UDim2.fromOffset(180, 34))
			relicMarker = rm
			rm.Adornee = root
			rm.Parent = root
		elseif relicMarker then
			relicMarker:Destroy()
			relicMarker = nil
		end
	else
		if relicMarker then
			relicMarker:Destroy()
			relicMarker = nil
		end
		local head = carrierHead()
		if head and not iCarry then
			local cm = carrierMarker or marker("RELIC CARRIER", P.Danger, UDim2.fromOffset(170, 30))
			carrierMarker = cm
			cm.Adornee = head
			cm.Parent = head
		elseif carrierMarker then
			carrierMarker:Destroy()
			carrierMarker = nil
		end
	end
	-- the carrier also sees where to deliver
	if iCarry then
		if not depositMarker then
			local world = Workspace:FindFirstChild("World")
			local anchor = world and world:FindFirstChild("DepositAnchor", true)
			if anchor and anchor:IsA("BasePart") then
				local dm = marker("DELIVER HERE", P.Teal, UDim2.fromOffset(180, 34))
				dm.StudsOffset = Vector3.new(0, 4, 0)
				dm.Adornee = anchor
				dm.Parent = anchor
				depositMarker = dm
			end
		end
	elseif depositMarker then
		depositMarker:Destroy()
		depositMarker = nil
	end

	-- the dedicated action: only while a carried relic exists and the local player is outside the safe zone
	local hrp = localHrp()
	local inSafe = hrp ~= nil and RelicRules.InSafeZone(hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
	strikeBtn.Visible = state == "Carried" and not inSafe
	if strikeBtn.Visible then
		local left = lastPress + (iCarry and R.ShoveCooldown or R.AttackCooldown) - os.clock()
		local verb = iCarry and "SHOVE" or "STRIKE"
		strikeBtn.Text = left > 0 and ("%s  %.1fs"):format(verb, left) or ("%s [%s]"):format(verb, Bindings.Name(Bindings.RelicStrike))
		strikeBtn.BackgroundColor3 = left > 0 and T.Disabled or P.Danger
	end
end

-- Effects ------------------------------------------------------------------------------------------------------------------------
local function burst(position: Vector3, color: Color3)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.3
	p.Size = Vector3.one * 1.5
	p.Position = position + Vector3.new(0, 1, 0)
	p.Parent = Workspace
	TweenService:Create(p, TweenInfo.new(0.25), { Size = Vector3.one * 5, Transparency = 1 }):Play()
	Debris:AddItem(p, 0.4)
end

local function flash(userId: number)
	local p = Players:GetPlayerByUserId(userId)
	local char = p and p.Character
	if not char then
		return
	end
	local h = Instance.new("Highlight")
	h.FillColor = P.Danger
	h.FillTransparency = 0.5
	h.OutlineTransparency = 1
	h.Parent = char
	Debris:AddItem(h, 0.25)
end

-- A short procedural arm swing (no animation assets are used).
local function swingArm()
	local char = player.Character
	local shoulder = char and char:FindFirstChild("RightShoulder", true)
	if shoulder and shoulder:IsA("Motor6D") then
		local c0 = shoulder.C0
		local out = TweenService:Create(shoulder, TweenInfo.new(0.1), { C0 = c0 * CFrame.Angles(math.rad(-80), 0, 0) })
		out:Play()
		out.Completed:Once(function()
			TweenService:Create(shoulder, TweenInfo.new(0.16), { C0 = c0 }):Play()
		end)
	end
end

local function press()
	if not Workspace:GetAttribute("RelicState") or Workspace:GetAttribute("RelicState") ~= "Carried" then
		return
	end
	if InputMode.IsMenuOpen() or UserInputService:GetFocusedTextBox() then
		return
	end
	local hrp = localHrp()
	if hrp and RelicRules.InSafeZone(hrp.Position.X, hrp.Position.Y, hrp.Position.Z) then
		return
	end
	if os.clock() - lastPress < 0.35 then
		return -- local debounce only; the server enforces the real cooldowns
	end
	lastPress = os.clock()
	Remotes.Get("RelicAttack"):FireServer()
	swingArm()
	Audio.Play("Impact", 1.2, 0.8)
end

function RelicController.Build(gui: ScreenGui)
	if panel then
		return
	end
	panel = mk("Frame", { Name = "RelicPanel", Size = UDim2.fromOffset(250, 92), Position = UDim2.fromOffset(10, 160), BackgroundColor3 = T.Panel,
		BackgroundTransparency = 0.1, Visible = false }, gui)
	corner(panel, 10)
	stroke(panel, P.Danger, 2)
	titleLabel = label(panel, "", 15, P.Gold, { Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(8, 4), TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 1, TextTruncate = Enum.TextTruncate.AtEnd })
	statusLabel = label(panel, "", 14, P.Cream, { Size = UDim2.new(1, -12, 0, 18), Position = UDim2.fromOffset(8, 24), TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 1, TextTruncate = Enum.TextTruncate.AtEnd })
	local bar = mk("Frame", { Size = UDim2.new(1, -16, 0, 10), Position = UDim2.fromOffset(8, 46), BackgroundColor3 = Color3.fromHex("3A3F47") }, panel)
	corner(bar, 5)
	barFill = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.Teal }, bar)
	corner(barFill, 5)
	hintLabel = label(panel, "", 12, K.Muted, { Size = UDim2.new(1, -12, 0, 32), Position = UDim2.fromOffset(8, 58), TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextStrokeTransparency = 1 })

	announce = label(gui, "", 20, P.Danger, { Name = "RelicAnnounce", Size = UDim2.new(1, -540, 0, 52), AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 128), Visible = false, TextScaled = true, TextWrapped = true })
	mk("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 11 }, announce)

	strikeBtn = K.button(gui, "STRIKE", UDim2.fromOffset(170, 46), UDim2.new(1, -182, 1, -112), P.Danger)
	strikeBtn.Name = "RelicStrikeButton"
	strikeBtn.TextSize = 18
	strikeBtn.Visible = false
	strikeBtn.Activated:Connect(press)
end

function RelicController.Init()
	if initialized then
		return
	end
	initialized = true
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Bindings.RelicStrike then
			press()
		end
	end)
	Remotes.Get("RelicFx").OnClientEvent:Connect(function(kind: string, userId: number, payload: any)
		if kind == "Knock" then
			-- one bounded velocity set on OUR character (the server computed it from validated facts; we clamp it again)
			local hrp = localHrp()
			if hrp and typeof(payload) == "Vector3" then
				local h = Vector3.new(payload.X, 0, payload.Z)
				if h.Magnitude > R.MaxKnockbackH then
					h = h.Unit * R.MaxKnockbackH
				end
				hrp.AssemblyLinearVelocity = Vector3.new(h.X, math.clamp(payload.Y, 0, R.MaxKnockbackUp), h.Z)
			end
		elseif kind == "Hit" or kind == "Shove" then
			if typeof(payload) == "Vector3" then
				burst(payload, kind == "Hit" and P.Danger or P.Gold)
			end
			flash(userId)
			Audio.Play("Break", kind == "Hit" and 0.7 or 1.1, 0.7)
		end
	end)
	Workspace:GetAttributeChangedSignal("RelicState"):Connect(refresh)
	Workspace:GetAttributeChangedSignal("RelicCarrierId"):Connect(refresh)
	Workspace:GetAttributeChangedSignal("RelicControl"):Connect(refresh)
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		refresh() -- also keeps markers attached when models/characters appear later, and drives the cooldown readout
	end)
	refresh()
end

return RelicController
