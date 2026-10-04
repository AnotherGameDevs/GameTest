-- Data-driven definitions: tools, backpacks, treasure, rarity.
local Config = require(script.Parent.Config)
local Grid = require(script.Parent.Grid)
local P = Config.Palette

local Defs = {}

Defs.Rarity = {
	Common = { Order = 1, Color = Color3.fromHex("C9C4B8"), Reveal = false },
	Uncommon = { Order = 2, Color = Color3.fromHex("7BD36B"), Reveal = true },
	Rare = { Order = 3, Color = Color3.fromHex("4DA3FF"), Reveal = true },
	Epic = { Order = 4, Color = Color3.fromHex("B565F2"), Reveal = true },
	Legendary = { Order = 5, Color = P.Gold, Reveal = true },
	Mythic = { Order = 6, Color = P.Danger, Reveal = true },
}

-- Tools: STATS ONLY. How a tool looks lives in Appearances.luau / ToolModels.luau, so skins can change
-- appearance without touching balance.
--   Power  = damage per hit            Rate  = swings per second
--   Reach  = studs from the character to the NEAREST POINT of the target block (see Defs.CellInReach)
--   Splash = optional { Radius, MaxExtra, Fraction }: up to MaxExtra nearby exposed blocks also take
--            Fraction of Power per swing. Deliberately capped; most tiers are single-block.
--   Family = which construction family it belongs to (drives art + the shop's grouping).
-- No tier raises damage, rate, reach and area all at once. Prices are PROVISIONAL (docs/TOOL_TIERS.md,
-- tools/economy_sim.py). Tier 8 (Dynamite) is a throwable consumable: see Defs.Consumables.
Defs.Tools = {
	rusty_shovel = {
		DisplayName = "Rusty Shovel", Tier = 1, Family = "Hand", ToolType = "Shovel", Appearance = "shovel_rusty",
		Power = 8, Rate = 2.0, Reach = 8, Price = 0, RequiredReputation = 0,
		Blurb = "Small and basic. Gets the job done.",
	},
	digging_shovel = {
		DisplayName = "Digging Shovel", Tier = 2, Family = "Hand", ToolType = "Shovel", Appearance = "shovel_digging",
		Power = 12, Rate = 2.2, Reach = 8, Price = 300, RequiredReputation = 0,
		Blurb = "Faster and stronger than the rusty shovel.",
	},
	heavy_shovel = {
		DisplayName = "Heavy Shovel", Tier = 3, Family = "Hand", ToolType = "Shovel", Appearance = "shovel_heavy",
		Power = 36, Rate = 1.5, Reach = 8, Price = 1100, RequiredReputation = 0,
		Blurb = "Bigger scoop. Heavy swings break soft ground in one hit.",
	},
	power_shovel = {
		DisplayName = "Power Shovel", Tier = 4, Family = "Excavation", ToolType = "Shovel", Appearance = "shovel_power",
		Power = 36, Rate = 1.5, Reach = 8, Splash = { Radius = 1, MaxExtra = 2, Fraction = 0.4 },
		Price = 5500, RequiredReputation = 0,
		Blurb = "Reinforced design. Each swing also chips 2 neighbouring blocks.",
	},
	jackhammer = {
		DisplayName = "Jackhammer", Tier = 5, Family = "Excavation", ToolType = "Jackhammer", Appearance = "jackhammer",
		Power = 22, Rate = 4.5, Reach = 8, Price = 11000, RequiredReputation = 0,
		Blurb = "Rapid digging. Chips through hard material.",
	},
	drill = {
		DisplayName = "Drill", Tier = 6, Family = "Excavation", ToolType = "Drill", Appearance = "drill",
		Power = 22, Rate = 5.5, Reach = 11, Price = 24000, RequiredReputation = 0,
		Blurb = "Cuts a tunnel. Faster, and reaches deeper from where you stand.",
	},
	industrial_drill = {
		DisplayName = "Industrial Drill", Tier = 7, Family = "Industrial", ToolType = "Drill", Appearance = "drill_industrial",
		Power = 22, Rate = 5.5, Reach = 11, Splash = { Radius = 1, MaxExtra = 2, Fraction = 0.4 },
		Price = 40000, RequiredReputation = 0,
		Blurb = "Massive digging power. Clears neighbouring blocks as it goes.",
	},
}

-- Tier 8: a throwable, single-use item (buy one, throw it, it is gone). Counts are saved per player.
-- The blast breaks the nearest MaxCells blocks within Radius cells of where it lands (a tightly capped area).
Defs.Consumables = {
	dynamite = {
		DisplayName = "Dynamite", Tier = 8, Family = "Industrial", Appearance = "dynamite",
		Price = 1200, MaxCarry = 3, Cooldown = 1.0, MaxActive = 3,
		FuseSeconds = 2.5, ThrowSpeed = 42, ThrowLift = 14,
		Blast = { Radius = 1, MaxCells = 14 },
		Blurb = "Throwable. Destroys a cluster of blocks. One use, then it is gone.",
	},
}

-- Backpacks: capacity is sized to the dig rate of the tools a player typically owns when they can afford the pack
-- (docs/TOOL_TIERS.md): a full trip should take roughly 2-6 minutes of digging, never seconds and never half an hour.
Defs.Backpacks = {
	pouch = { DisplayName = "Pouch", Capacity = 12, Price = 0, RequiredReputation = 0, Order = 1, Appearance = "pack_pouch",
		Blurb = "Your starter pouch. Holds 12 finds." },
	satchel = { DisplayName = "Big Satchel", Capacity = 30, Price = 120, RequiredReputation = 0, Order = 2, Appearance = "pack_satchel",
		Blurb = "Carry 30 treasures per trip." },
	field_pack = { DisplayName = "Field Pack", Capacity = 55, Price = 2500, RequiredReputation = 0, Order = 3, Appearance = "pack_field",
		Blurb = "Straps and pockets for 55 finds. Suits the stone layer." },
	mining_pack = { DisplayName = "Mining Pack", Capacity = 90, Price = 14000, RequiredReputation = 0, Order = 4, Appearance = "pack_mining",
		Blurb = "Reinforced frame for 90 finds on deep runs." },
	expedition_pack = { DisplayName = "Expedition Pack", Capacity = 140, Price = 32000, RequiredReputation = 0, Order = 5, Appearance = "pack_expedition",
		Blurb = "The biggest pack there is: 140 finds per trip." },
}

-- Treasure. Layers lists which layer ids can drop it; Weight is relative inside a layer.
Defs.Treasure = {
	old_coin = { Name = "Old Coin", Rarity = "Common", Value = 8, Layers = { Soil = 10, Clay = 6 }, Category = "Coins", Color = P.Gold, Shape = "Coin", Model = "coin" },
	pottery_shard = { Name = "Pottery Shard", Rarity = "Common", Value = 12, Layers = { Soil = 8, Clay = 8 }, Category = "Pottery", Color = P.Clay, Shape = "Block", Model = "shard" },
	bronze_ring = { Name = "Bronze Ring", Rarity = "Uncommon", Value = 40, Layers = { Soil = 2, Clay = 6, Stone = 3 }, Category = "Jewelry", Color = Color3.fromHex("CD7F32"), Shape = "Ring", Model = "ring" },
	clay_figurine = { Name = "Clay Figurine", Rarity = "Uncommon", Value = 65, Layers = { Clay = 6, Stone = 4 }, Category = "Pottery", Color = P.Sandstone, Shape = "Block", Model = "figurine" },
	fossil_fragment = { Name = "Fossil Fragment", Rarity = "Uncommon", Value = 85, Layers = { Clay = 3, Stone = 8 }, Category = "Fossils", Color = P.Cream, Shape = "Block", Model = "fossil" },
	ancient_necklace = { Name = "Ancient Necklace", Rarity = "Rare", Value = 240, Layers = { Clay = 1, Stone = 5, Ruins = 4 }, Category = "Jewelry", Color = P.Gold, Shape = "Ring", Model = "necklace" },
	cut_gemstone = { Name = "Cut Gemstone", Rarity = "Rare", Value = 320, Layers = { Stone = 4, Ruins = 5 }, Category = "Gemstones", Color = Color3.fromHex("4DD2FF"), Shape = "Gem", Model = "gem" },
	ruin_tablet = { Name = "Ruin Tablet", Rarity = "Rare", Value = 260, Layers = { Stone = 1, Ruins = 6 }, Category = "Ruins", Color = P.Sandstone, Shape = "Block", Model = "tablet" },
	fossil_claw = { Name = "Fossil Claw", Rarity = "Epic", Value = 900, Layers = { Stone = 1, Ruins = 2 }, Category = "Fossils", Color = P.Cream, Shape = "Block", Model = "claw", RequiresCarry = true },
	golden_scarab = { Name = "Golden Scarab", Rarity = "Epic", Value = 1400, Layers = { Ruins = 1 }, Category = "Ancient Egypt", Color = P.Gold, Shape = "Gem", Model = "scarab", RequiresCarry = true },
	sun_mask = { Name = "Sun Pharaoh Mask", Rarity = "Legendary", Value = 3500, Layers = { Ruins = 0.5 }, Category = "Ancient Egypt", Color = P.Gold, Shape = "Gem", Model = "mask", RequiresCarry = true },
}

-- The ONE reach rule, used by server validation and the client reach indicator.
-- tool.Reach is the literal distance in studs from the character's HumanoidRootPart to the NEAREST POINT of the
-- target cell (so a block's face 8 studs away is in reach of an 8-stud tool; no cell-size allowance).
-- `tolerance` is extra slack: the server passes Config.Dig.ReachTolerance, the client passes 0.
function Defs.CellInReach(tool, from: Vector3, x: number, y: number, z: number, tolerance: number?): boolean
	local c = Grid.CellCenter(x, y, z)
	local h = Grid.CellSize / 2
	local dx = math.max(math.abs(from.X - c.X) - h, 0)
	local dy = math.max(math.abs(from.Y - c.Y) - h, 0)
	local dz = math.max(math.abs(from.Z - c.Z) - h, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz) <= tool.Reach + (tolerance or 0)
end

function Defs.LayerAtCell(y: number)
	local found = Config.Layers[1]
	for _, layer in ipairs(Config.Layers) do
		if y >= layer.FromCell then
			found = layer
		end
	end
	return found
end

-- Layer gating: can a tool of this tier break blocks of `layer`? (server enforces; the client uses it for feedback)
function Defs.LayerAllows(tool, layer): boolean
	return tool.Tier >= (layer.MinToolTier or 1)
end

-- Display name of the cheapest tool that satisfies a minimum tier.
function Defs.ToolNameForTier(tier: number): string
	for id, def in pairs(Defs.Tools) do
		if def.Tier == tier then
			return def.DisplayName
		end
	end
	return "a stronger tool"
end

function Defs.LayerName(layerId: string): string
	for _, layer in ipairs(Config.Layers) do
		if layer.Id == layerId then
			return layer.Name
		end
	end
	return layerId
end

-- Per-layer weighted lists, built once: all treasures, and ordinary (not carry-home) treasures only.
local function buildWeighted(onlyOrdinary: boolean)
	local out = {}
	for _, layer in ipairs(Config.Layers) do
		local list = {}
		for id, def in pairs(Defs.Treasure) do
			local w = def.Layers[layer.Id]
			if w and not (onlyOrdinary and def.RequiresCarry) then
				table.insert(list, { Id = id, Weight = w })
			end
		end
		table.sort(list, function(a, b) return a.Id < b.Id end)
		local total = 0
		for _, e in ipairs(list) do
			total += e.Weight
			e.Cum = total
		end
		out[layer.Id] = { List = list, Total = total }
	end
	return out
end
local weighted = buildWeighted(false)
local weightedOrdinary = buildWeighted(true)

-- Weighted pick for a layer. `ordinaryOnly` excludes carry-home artifacts (used when an important artifact is over its
-- per-generation limit or ineligible for a cell). `rng` needs :NextNumber().
function Defs.PickTreasure(layerId: string, rng, ordinaryOnly: boolean?): string?
	local w = (ordinaryOnly and weightedOrdinary or weighted)[layerId]
	if not w or w.Total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * w.Total
	for _, e in ipairs(w.List) do
		if roll <= e.Cum then
			return e.Id
		end
	end
	return w.List[#w.List].Id
end

-- Swings needed to break one block of a layer with this tool (pure; used by the shop comparison UI).
function Defs.HitsToBreak(tool, layer): number
	return math.ceil(layer.Health / tool.Power)
end

-- Tool ids ordered by tier.
local toolsByTier = {}
for id, def in pairs(Defs.Tools) do
	table.insert(toolsByTier, id)
end
table.sort(toolsByTier, function(a, b)
	return Defs.Tools[a].Tier < Defs.Tools[b].Tier
end)
Defs.ToolsByTier = toolsByTier

-- The tier directly below `toolId` (nil for tier 1). Used for sequential unlocking.
function Defs.PreviousTool(toolId: string): string?
	local def = Defs.Tools[toolId]
	if not def then
		return nil
	end
	for _, id in ipairs(toolsByTier) do
		if Defs.Tools[id].Tier == def.Tier - 1 then
			return id
		end
	end
	return nil
end

-- Shop catalogue. Tools tab: the seven equippable tiers then the tier-8 consumable. Backpacks tab: purchasable packs.
function Defs.ShopItems()
	local items = {}
	for _, id in ipairs(toolsByTier) do
		table.insert(items, { Kind = "Tool", Id = id, Def = Defs.Tools[id] })
	end
	for id, def in pairs(Defs.Consumables) do
		table.insert(items, { Kind = "Consumable", Id = id, Def = def })
	end
	local packs = {}
	for id, def in pairs(Defs.Backpacks) do
		if def.Price > 0 then
			table.insert(packs, { Kind = "Backpack", Id = id, Def = def })
		end
	end
	table.sort(packs, function(a, b)
		if a.Def.Price ~= b.Def.Price then
			return a.Def.Price < b.Def.Price
		end
		return a.Id < b.Id
	end)
	for _, it in ipairs(packs) do
		table.insert(items, it)
	end
	return items
end

return Defs
