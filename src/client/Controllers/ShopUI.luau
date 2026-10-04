-- The Equipment Shop: left tabs (Tools / Backpacks / Utility / Cosmetics), a rotating 3D preview of the ACTUAL
-- tool model with an Inspect view, stat bars with an equipped-vs-selected comparison, price + purchase, and a
-- thumbnail strip of every item. Utility and Cosmetics are visible "coming soon" tabs.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Appearances = require(ReplicatedStorage.Shared.Appearances)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)

local State = require(script.Parent.State)
local Audio = require(script.Parent.AudioController)
local ShopPreview = require(script.Parent.ShopPreview)
local K = require(script.Parent.UIKit)

local P = Config.Palette
local mk, corner, stroke, label, button = K.mk, K.corner, K.stroke, K.label, K.button

local ShopUI = {}

local TABS = { "Tools", "Backpacks", "Utility", "Cosmetics" }
local FAMILY_NAMES = { Hand = "HAND TOOL", Excavation = "EXCAVATION TOOL", Industrial = "INDUSTRIAL" }
local FAMILY_COLORS = { Hand = Color3.fromHex("D9A066"), Excavation = P.Gold, Industrial = P.Danger }
local COMING_SOON = {
	Utility = { "Lantern", "Treasure scanner", "Rope", "Beacon" },
	Cosmetics = { "Tool skins", "Helmets", "Backpack styles", "Titles" },
}

local root: Frame
local refs: { [string]: any } = {}
local previews: { [string]: any } = {}
local open = false
local tab = "Tools"
local sel = { Kind = "Tool", Id = "rusty_shovel" }
local onClose: (() -> ())?

-- Maximums used to normalise the stat bars across every tier.
local MAX = { Power = 1, Rate = 1, Extra = 3, ReachMin = 8, ReachMax = 12 }
for _, def in pairs(Defs.Tools) do
	MAX.Power = math.max(MAX.Power, def.Power)
	MAX.Rate = math.max(MAX.Rate, def.Rate)
end

local function itemOf(kind: string, id: string)
	for _, it in ipairs(Defs.ShopItems()) do
		if it.Kind == kind and it.Id == id then
			return it
		end
	end
	return nil
end

local function itemState(it, d)
	local s = { Owned = false, Equipped = false, Locked = false, LockedReason = nil, Affordable = d.Cash >= it.Def.Price, Count = 0 }
	if it.Kind == "Tool" then
		s.Owned = d.OwnedTools[it.Id] == true
		s.Equipped = d.ToolId == it.Id
		local prev = Defs.PreviousTool(it.Id)
		if not s.Owned and Config.Shop.SequentialTools and prev and not d.OwnedTools[prev] then
			s.Locked = true
			s.LockedReason = "Buy the " .. Defs.Tools[prev].DisplayName .. " first"
		end
	elseif it.Kind == "Backpack" then
		s.Owned = d.OwnedBackpacks[it.Id] == true
		s.Equipped = d.BackpackId == it.Id
	elseif it.Kind == "Consumable" then
		s.Count = (d.Consumables and d.Consumables[it.Id]) or 0
		s.Owned = s.Count > 0
		if s.Count >= it.Def.MaxCarry then
			s.Locked = true
			s.LockedReason = ("Carrying the maximum (%d)"):format(it.Def.MaxCarry)
		end
	end
	return s
end

local function tabItems(): { any }
	local out = {}
	for _, it in ipairs(Defs.ShopItems()) do
		if tab == "Tools" and (it.Kind == "Tool" or it.Kind == "Consumable") then
			table.insert(out, it)
		elseif tab == "Backpacks" and it.Kind == "Backpack" then
			table.insert(out, it)
		end
	end
	return out
end

local function appearanceOf(it): string?
	if it.Kind == "Tool" then
		local skin = State.Data.Skins and State.Data.Skins.ToolSkin
		return Appearances.Resolve(it.Def, skin)
	elseif it.Kind == "Consumable" then
		return it.Def.Appearance
	end
	return nil
end

-- Rows --------------------------------------------------------------------------------------------------------
local function colorFor(delta: number, lowerIsBetter: boolean?): Color3
	if delta == 0 then
		return P.Cream
	end
	local better = (delta > 0) ~= (lowerIsBetter == true)
	return better and K.Good or K.Bad
end

local function statBar(parent: Instance, y: number, name: string, frac: number, equippedFrac: number?, valueText: string, valueColor: Color3)
	label(parent, name, 17, P.Cream, { Size = UDim2.fromOffset(62, 20), Position = UDim2.fromOffset(0, y),
		TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
	local back = mk("Frame", { Size = UDim2.fromOffset(120, 12), Position = UDim2.fromOffset(66, y + 4),
		BackgroundColor3 = Color3.fromHex("3A3F47") }, parent)
	corner(back, 6)
	local fill = mk("Frame", { Size = UDim2.fromScale(math.clamp(frac, 0.02, 1), 1), BackgroundColor3 = P.Gold }, back)
	corner(fill, 6)
	if equippedFrac then
		mk("Frame", { Size = UDim2.new(0, 3, 1, 6), Position = UDim2.new(math.clamp(equippedFrac, 0, 1), -1, 0, -3),
			BackgroundColor3 = Color3.new(1, 1, 1) }, back)
	end
	label(parent, valueText, 15, valueColor, { Size = UDim2.fromOffset(96, 20), Position = UDim2.fromOffset(192, y),
		TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1, RichText = true })
end

local function delta(newV: number, curV: number, fmt: string, same: boolean): string
	if same then
		return fmt:format(newV)
	end
	local d = newV - curV
	return (fmt .. "  (%s" .. fmt .. ")"):format(newV, d > 0 and "+" or "", d)
end

-- Rendering ----------------------------------------------------------------------------------------------------
local function clearChildren(parent: Instance, keep: { [string]: boolean }?)
	for _, c in ipairs(parent:GetChildren()) do
		if not c:IsA("UIListLayout") and not (keep and keep[c.Name]) then
			c:Destroy()
		end
	end
end

local function renderDetail()
	local d = State.Data
	local box = refs.detail
	clearChildren(box)
	local actionBox = refs.action
	clearChildren(actionBox)

	if tab == "Utility" or tab == "Cosmetics" then
		refs.pvName.Text = tab:upper()
		refs.pvTier.Text = "COMING SOON"
		refs.pvTier.TextColor3 = K.Muted
		refs.inspectBtn.Visible = false
		ShopPreview.Show(previews.main, nil)
		label(box, "Planned for this shop:", 18, P.Cream, { Size = UDim2.fromOffset(280, 24), Position = UDim2.fromOffset(0, 0),
			TextXAlignment = Enum.TextXAlignment.Left })
		for i, name in ipairs(COMING_SOON[tab]) do
			label(box, "-  " .. name, 17, K.Muted, { Size = UDim2.fromOffset(280, 22), Position = UDim2.fromOffset(8, 22 + i * 24),
				TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
		end
		return
	end

	local it = itemOf(sel.Kind, sel.Id)
	if not it then
		return
	end
	local def, st = it.Def, itemState(it, d)
	refs.pvName.Text = def.DisplayName:upper()

	if it.Kind == "Backpack" then
		refs.pvTier.Text = "BACKPACK"
		refs.pvTier.TextColor3 = P.Teal
		refs.inspectBtn.Visible = false
		ShopPreview.Show(previews.main, nil)
		label(box, def.Blurb or "", 16, P.Cream, { Size = UDim2.fromOffset(290, 54), Position = UDim2.fromOffset(0, 0),
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
			TextStrokeTransparency = 1 })
		local cur = Defs.Backpacks[d.BackpackId]
		statBar(box, 70, "Capacity", def.Capacity / 40, (not st.Equipped) and (cur.Capacity / 40) or nil,
			st.Equipped and tostring(def.Capacity) or delta(def.Capacity, cur.Capacity, "%d", false),
			colorFor(def.Capacity - cur.Capacity))
	else
		local isTool = it.Kind == "Tool"
		local family = def.Family or "Hand"
		refs.pvTier.Text = ("TIER %d  -  %s%s"):format(def.Tier, isTool and FAMILY_NAMES[family] or "THROWABLE",
			isTool and "" or "  -  SINGLE USE")
		refs.pvTier.TextColor3 = FAMILY_COLORS[family]
		refs.inspectBtn.Visible = true
		ShopPreview.Show(previews.main, appearanceOf(it))
		label(box, def.Blurb or "", 16, P.Cream, { Size = UDim2.fromOffset(290, 50), Position = UDim2.fromOffset(0, 0),
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true,
			TextStrokeTransparency = 1 })
		if isTool then
			local cur = Defs.Tools[d.ToolId]
			local same = st.Equipped
			local extraNew = def.Splash and def.Splash.MaxExtra or 0
			local extraCur = cur.Splash and cur.Splash.MaxExtra or 0
			statBar(box, 56, "Power", def.Power / MAX.Power, (not same) and cur.Power / MAX.Power or nil,
				delta(def.Power, cur.Power, "%d", same), colorFor(def.Power - cur.Power))
			statBar(box, 80, "Speed", def.Rate / MAX.Rate, (not same) and cur.Rate / MAX.Rate or nil,
				delta(def.Rate, cur.Rate, "%.1f", same) .. "/s", colorFor(def.Rate - cur.Rate))
			statBar(box, 104, "Area", extraNew / MAX.Extra, (not same) and extraCur / MAX.Extra or nil,
				extraNew == 0 and "single block" or ("+%d blocks"):format(extraNew), colorFor(extraNew - extraCur))
			statBar(box, 128, "Reach", (def.Reach - MAX.ReachMin + 2) / (MAX.ReachMax - MAX.ReachMin + 2),
				(not same) and (cur.Reach - MAX.ReachMin + 2) / (MAX.ReachMax - MAX.ReachMin + 2) or nil,
				delta(def.Reach, cur.Reach, "%d", same) .. " studs", colorFor(def.Reach - cur.Reach))
			-- swings to break one block, per layer (lower is better)
			local parts = {}
			for _, layer in ipairs(Config.Layers) do
				local n, c = Defs.HitsToBreak(def, layer), Defs.HitsToBreak(cur, layer)
				local text = same and tostring(n) or (n == c and tostring(n) or ("%d>%d"):format(c, n))
				parts[#parts + 1] = ('<font color="#%s">%s %s</font>'):format(
					colorFor(c - n, false):ToHex(), layer.Name:sub(1, 1) .. layer.Name:sub(2):lower(), text)
			end
			label(box, "Swings to break:  " .. table.concat(parts, "   "), 14, P.Cream, { Size = UDim2.fromOffset(290, 36),
				Position = UDim2.fromOffset(0, 156), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
				TextWrapped = true, TextStrokeTransparency = 1, RichText = true })
		else
			local blast = def.Blast
			statBar(box, 56, "Blast", blast.MaxCells / 20, nil, ("up to %d blocks"):format(blast.MaxCells), P.Cream)
			statBar(box, 80, "Fuse", def.FuseSeconds / 5, nil, ("%.1fs"):format(def.FuseSeconds), P.Cream)
			label(box, ("Carry up to %d. Throw with G (or the THROW button). It breaks the blocks nearest where it lands, " ..
				"and is used up."):format(def.MaxCarry), 14, P.Cream, { Size = UDim2.fromOffset(290, 60),
				Position = UDim2.fromOffset(0, 112), TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextStrokeTransparency = 1 })
		end
	end

	-- price pill + action button
	local priceText = def.Price > 0 and Util.FormatCash(def.Price) or "FREE"
	local pill = mk("Frame", { Size = UDim2.fromOffset(120, 34), Position = UDim2.fromOffset(0, 0),
		BackgroundColor3 = st.Affordable and K.Green or Color3.fromHex("5A5F66") }, actionBox)
	corner(pill, 17)
	stroke(pill, P.Dark, 2)
	label(pill, priceText, 22, Color3.new(1, 1, 1), { Size = UDim2.fromScale(1, 1) })

	local text, color, enabled = nil, K.Muted, false
	local carrying = d.Carrying ~= nil
	if it.Kind == "Consumable" then
		if st.Locked then
			text = st.LockedReason
		elseif st.Affordable then
			text, color, enabled = ("BUY 1  (have %d/%d)"):format(st.Count, def.MaxCarry), P.Gold, true
		else
			text = "NEED " .. Util.FormatCash(def.Price - d.Cash) .. " MORE"
		end
	elseif st.Equipped and st.Owned then
		text = "EQUIPPED"
	elseif st.Owned then
		if it.Kind == "Tool" then
			if carrying then
				text = "PLACE ARTIFACT FIRST"
			else
				text, color, enabled = "EQUIP", Color3.fromHex("5BA7E8"), true
			end
		else
			text = "OWNED"
		end
	elseif st.Locked then
		text = st.LockedReason
	elseif st.Affordable then
		text, color, enabled = "PURCHASE", P.Gold, true
	else
		text = "NEED " .. Util.FormatCash(def.Price - d.Cash) .. " MORE"
	end
	local b = button(actionBox, text or "", UDim2.fromOffset(150, 40), UDim2.fromOffset(130, -3), color)
	b.TextSize = (#(text or "") > 14) and 15 or 20
	b.TextWrapped = true
	b.Activated:Connect(function()
		if not enabled then
			Audio.Play("Error")
			return
		end
		Audio.Play("UI")
		if it.Kind == "Tool" and st.Owned then
			Remotes.Get("RequestEquip"):FireServer("Tool", it.Id)
		else
			Remotes.Get("RequestPurchase"):FireServer(it.Kind, it.Id)
		end
	end)
	if st.Locked and not st.Owned and it.Kind == "Tool" then
		label(actionBox, st.LockedReason or "", 14, K.Bad, { Size = UDim2.fromOffset(280, 18), Position = UDim2.fromOffset(0, 42),
			TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
	end
end

local function renderList()
	local list = refs.list
	clearChildren(list)
	if tab == "Utility" or tab == "Cosmetics" then
		label(list, "Nothing here yet.", 16, K.Muted, { Size = UDim2.new(1, 0, 0, 30), TextStrokeTransparency = 1 })
		return
	end
	local d = State.Data
	for i, it in ipairs(tabItems()) do
		local st = itemState(it, d)
		local card = mk("TextButton", { Name = "Card", Text = "", AutoButtonColor = true, LayoutOrder = i, Size = UDim2.new(1, -6, 0, 78),
			BackgroundColor3 = (sel.Kind == it.Kind and sel.Id == it.Id) and Color3.fromHex("4A4130") or Color3.fromHex("2F343C") }, list)
		corner(card, 10)
		stroke(card, (sel.Kind == it.Kind and sel.Id == it.Id) and P.Gold or P.Dark, 2)

		local app = appearanceOf(it)
		local vp = mk("ViewportFrame", { Size = UDim2.fromOffset(62, 66), Position = UDim2.fromOffset(6, 6), BackgroundTransparency = 1 }, card)
		if app then
			local key = it.Kind .. ":" .. it.Id
			local pv = previews[key]
			if not pv or pv.Viewport.Parent == nil or pv.Viewport ~= vp then
				pv = ShopPreview.Create(vp, 1)
				previews[key] = pv
			end
			ShopPreview.Show(pv, app)
			pv.Yaw = 0.5
			ShopPreview.Update(pv, 0)
		else
			vp:Destroy()
			label(card, "PACK", 15, P.Teal, { Size = UDim2.fromOffset(62, 66), Position = UDim2.fromOffset(6, 6) })
		end
		label(card, (it.Def.Tier and (it.Def.Tier .. ". ") or "") .. it.Def.DisplayName, 15, P.Cream, {
			Size = UDim2.new(1, -78, 0, 36), Position = UDim2.fromOffset(72, 4), TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
		local status, scolor
		if it.Kind == "Consumable" then
			status, scolor = ("%s  (have %d)"):format(Util.FormatCash(it.Def.Price), st.Count), P.Gold
		elseif st.Equipped and st.Owned then
			status, scolor = "EQUIPPED", P.Teal
		elseif st.Owned then
			status, scolor = "OWNED", K.Good
		elseif st.Locked then
			status, scolor = "LOCKED", K.Muted
		else
			status, scolor = Util.FormatCash(it.Def.Price), st.Affordable and P.Gold or K.Muted
		end
		label(card, status, 15, scolor, { Size = UDim2.new(1, -78, 0, 20), Position = UDim2.fromOffset(72, 50),
			TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
		card.Activated:Connect(function()
			sel = { Kind = it.Kind, Id = it.Id }
			Audio.Play("UI")
			ShopUI.Render()
		end)
	end
end

local function renderTabs()
	for _, name in ipairs(TABS) do
		local b = refs.tabs[name]
		local active = name == tab
		b.BackgroundColor3 = active and Color3.fromHex("6B5530") or Color3.fromHex("2F343C")
		b.UIStroke.Color = active and P.Gold or P.Dark
	end
end

function ShopUI.Render()
	if not root then
		return
	end
	-- keep the selection valid for the current tab
	if tab == "Tools" and sel.Kind == "Backpack" then
		sel = { Kind = "Tool", Id = State.Data.ToolId or "rusty_shovel" }
	elseif tab == "Backpacks" and sel.Kind ~= "Backpack" then
		local first = tabItems()[1]
		sel = first and { Kind = first.Kind, Id = first.Id } or sel
	end
	renderTabs()
	renderList()
	renderDetail()
	if refs.inspect.Visible then
		local it = itemOf(sel.Kind, sel.Id)
		refs.inspectName.Text = it and it.Def.DisplayName:upper() or ""
		ShopPreview.Show(previews.inspect, it and appearanceOf(it) or nil)
	end
end

function ShopUI.IsOpen(): boolean
	return open
end

function ShopUI.Open()
	open = true
	root.Visible = true
	-- start on the tool you would buy next
	local d = State.Data
	tab = "Tools"
	local target = "rusty_shovel"
	for _, id in ipairs(Defs.ToolsByTier) do
		if not d.OwnedTools[id] then
			target = id
			break
		end
		target = id
	end
	sel = { Kind = "Tool", Id = target }
	ShopUI.Render()
end

function ShopUI.Close()
	open = false
	if root then
		root.Visible = false
		refs.inspect.Visible = false
	end
	if onClose then
		onClose()
	end
end

-- Spins the previews (called every frame while open).
function ShopUI.Step(dt: number)
	if not open then
		return
	end
	ShopPreview.Update(previews.main, dt)
	if refs.inspect.Visible then
		ShopPreview.Update(previews.inspect, dt)
	end
end

function ShopUI.Build(gui: ScreenGui, closed: () -> ()): Frame
	onClose = closed
	root = mk("Frame", { Name = "Shop", Size = UDim2.fromOffset(880, 486), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Color3.fromHex("1D2025"), BackgroundTransparency = 0.02,
		Visible = false }, gui)
	corner(root, 16)
	stroke(root, Color3.fromHex("C9A46B"), 4)

	label(root, "EQUIPMENT SHOP", 30, P.Cream, { Size = UDim2.fromOffset(300, 40), Position = UDim2.fromOffset(16, 8),
		TextXAlignment = Enum.TextXAlignment.Left })
	label(root, "VIEW, COMPARE AND PURCHASE UPGRADES", 14, K.Muted, { Size = UDim2.fromOffset(360, 40), Position = UDim2.fromOffset(300, 8),
		TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
	local close = button(root, "X", UDim2.fromOffset(48, 38), UDim2.new(1, -60, 0, 10), P.Danger)
	close.Activated:Connect(ShopUI.Close)

	-- tabs
	refs.tabs = {}
	for i, name in ipairs(TABS) do
		local b = mk("TextButton", { Name = name, Text = "", AutoButtonColor = true, Size = UDim2.fromOffset(128, 62),
			Position = UDim2.fromOffset(12, 60 + (i - 1) * 70), BackgroundColor3 = Color3.fromHex("2F343C") }, root)
		corner(b, 10)
		stroke(b, P.Dark, 2)
		local glyph = mk("Frame", { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(8, 16),
			BackgroundColor3 = ({ Tools = P.Gold, Backpacks = P.Clay, Utility = P.Teal, Cosmetics = P.Danger })[name] }, b)
		corner(glyph, 8)
		label(glyph, name:sub(1, 1), 18, P.Dark, { Size = UDim2.fromScale(1, 1), TextStrokeTransparency = 1 })
		label(b, name, 17, P.Cream, { Size = UDim2.fromOffset(78, 62), Position = UDim2.fromOffset(44, 0),
			TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1 })
		b.Activated:Connect(function()
			tab = name
			Audio.Play("UI")
			ShopUI.Render()
		end)
		refs.tabs[name] = b
	end

	-- preview panel
	local pv = mk("Frame", { Position = UDim2.fromOffset(152, 60), Size = UDim2.fromOffset(240, 414),
		BackgroundColor3 = Color3.fromHex("2B3038") }, root)
	corner(pv, 12)
	stroke(pv, Color3.fromHex("C9A46B"), 2)
	local mainVp = mk("ViewportFrame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(224, 330), BackgroundTransparency = 1 }, pv)
	previews.main = ShopPreview.Create(mainVp, 1)
	refs.pvName = label(pv, "", 22, P.Cream, { Size = UDim2.fromOffset(224, 28), Position = UDim2.fromOffset(8, 342) })
	refs.pvTier = label(pv, "", 14, P.Gold, { Size = UDim2.fromOffset(224, 20), Position = UDim2.fromOffset(8, 370), TextStrokeTransparency = 1 })
	refs.inspectBtn = button(pv, "INSPECT", UDim2.fromOffset(96, 30), UDim2.fromOffset(136, 14), Color3.fromHex("5BA7E8"))
	refs.inspectBtn.TextSize = 16
	refs.inspectBtn.ZIndex = 5

	-- detail panel
	refs.detail = mk("Frame", { Position = UDim2.fromOffset(404, 66), Size = UDim2.fromOffset(300, 300), BackgroundTransparency = 1 }, root)
	refs.action = mk("Frame", { Position = UDim2.fromOffset(404, 400), Size = UDim2.fromOffset(300, 74), BackgroundTransparency = 1 }, root)

	-- thumbnail strip
	refs.list = mk("ScrollingFrame", { Position = UDim2.fromOffset(716, 60), Size = UDim2.fromOffset(152, 414), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 5, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y }, root)
	mk("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, refs.list)

	-- enlarged inspect view
	local inspect = mk("Frame", { Name = "Inspect", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromHex("14171B"), BackgroundTransparency = 0.03, Visible = false, ZIndex = 10, Active = true }, root)
	corner(inspect, 16)
	refs.inspect = inspect
	refs.inspectName = label(inspect, "", 28, P.Cream, { Size = UDim2.new(1, -140, 0, 44), Position = UDim2.fromOffset(20, 10),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 })
	label(inspect, "DRAG TO ROTATE", 14, K.Muted, { Size = UDim2.fromOffset(200, 20), Position = UDim2.fromOffset(20, 50),
		TextXAlignment = Enum.TextXAlignment.Left, TextStrokeTransparency = 1, ZIndex = 11 })
	local bigVp = mk("ViewportFrame", { Position = UDim2.fromOffset(20, 80), Size = UDim2.new(1, -40, 1, -100),
		BackgroundTransparency = 1, Active = true, ZIndex = 11 }, inspect)
	previews.inspect = ShopPreview.Create(bigVp, 0.62)
	local back = button(inspect, "BACK", UDim2.fromOffset(100, 38), UDim2.new(1, -120, 0, 12), P.Gold)
	back.ZIndex = 12
	back.Activated:Connect(function()
		inspect.Visible = false
	end)
	refs.inspectBtn.Activated:Connect(function()
		inspect.Visible = true
		Audio.Play("UI")
		ShopUI.Render()
	end)
	-- drag-to-rotate (mouse or touch)
	local dragging = false
	bigVp.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			ShopPreview.Drag(previews.inspect, input.Delta.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return root
end

return ShopUI
