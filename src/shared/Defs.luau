-- Data-driven definitions: tools, backpacks, treasure, rarity.
local Config = require(script.Parent.Config)
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

-- Tools. Power = damage per hit, Rate = hits/second, DigRadius = extra cells hit around the target
-- (this is what makes better shovels *behave* differently, not only hit harder).
Defs.Tools = {
	rusty_shovel = {
		DisplayName = "Rusty Shovel", ToolType = "Shovel", Power = 8, Rate = 2.0, DigRadius = 0, Reach = 14,
		Price = 0, RequiredReputation = 0, Order = 1, Color = Color3.fromHex("8A6A55"), Scale = 1.0,
		Blurb = "Slow. One block at a time.",
	},
	digging_shovel = {
		DisplayName = "Digging Shovel", ToolType = "Shovel", Power = 18, Rate = 3.0, DigRadius = 1, Reach = 16,
		Price = 180, RequiredReputation = 0, Order = 2, Color = P.Teal, Scale = 1.35,
		Blurb = "Faster, harder, and smashes neighbouring blocks too!",
	},
}

Defs.Backpacks = {
	pouch = { DisplayName = "Pouch", Capacity = 12, Price = 0, RequiredReputation = 0, Order = 1 },
	satchel = { DisplayName = "Big Satchel", Capacity = 30, Price = 120, RequiredReputation = 0, Order = 2,
		Blurb = "Carry 30 treasures per trip." },
}

-- Treasure. Layers lists which layer ids can drop it; Weight is relative inside a layer.
Defs.Treasure = {
	old_coin = { Name = "Old Coin", Rarity = "Common", Value = 8, Layers = { Soil = 10, Clay = 6 }, Category = "Coins", Color = P.Gold, Shape = "Coin" },
	pottery_shard = { Name = "Pottery Shard", Rarity = "Common", Value = 12, Layers = { Soil = 8, Clay = 8 }, Category = "Pottery", Color = P.Clay, Shape = "Block" },
	bronze_ring = { Name = "Bronze Ring", Rarity = "Uncommon", Value = 40, Layers = { Soil = 2, Clay = 6, Stone = 3 }, Category = "Jewelry", Color = Color3.fromHex("CD7F32"), Shape = "Ring" },
	clay_figurine = { Name = "Clay Figurine", Rarity = "Uncommon", Value = 65, Layers = { Clay = 6, Stone = 4 }, Category = "Pottery", Color = P.Sandstone, Shape = "Block" },
	fossil_fragment = { Name = "Fossil Fragment", Rarity = "Uncommon", Value = 85, Layers = { Clay = 3, Stone = 8 }, Category = "Fossils", Color = P.Cream, Shape = "Block" },
	ancient_necklace = { Name = "Ancient Necklace", Rarity = "Rare", Value = 240, Layers = { Clay = 1, Stone = 5, Ruins = 4 }, Category = "Jewelry", Color = P.Gold, Shape = "Ring" },
	cut_gemstone = { Name = "Cut Gemstone", Rarity = "Rare", Value = 320, Layers = { Stone = 4, Ruins = 5 }, Category = "Gemstones", Color = Color3.fromHex("4DD2FF"), Shape = "Gem" },
	fossil_claw = { Name = "Fossil Claw", Rarity = "Epic", Value = 900, Layers = { Stone = 1, Ruins = 4 }, Category = "Fossils", Color = P.Cream, Shape = "Block" },
	golden_scarab = { Name = "Golden Scarab", Rarity = "Epic", Value = 1400, Layers = { Ruins = 3 }, Category = "Ancient Egypt", Color = P.Gold, Shape = "Gem" },
}

-- The ONE reach rule. Server validates with it; the client reach indicator uses the same function.
-- Distance is measured from the character's HumanoidRootPart to the dig cell's centre.
function Defs.DigReachLimit(tool): number
	return tool.Reach + Config.Dig.ReachPadding + Config.Site.CellSize
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

-- Per-layer weighted lists, built once.
local weighted = {}
for _, layer in ipairs(Config.Layers) do
	local list, total = {}, 0
	for id, def in pairs(Defs.Treasure) do
		local w = def.Layers[layer.Id]
		if w then
			total += w
			table.insert(list, { Id = id, Cum = total })
		end
	end
	table.sort(list, function(a, b) return a.Id < b.Id end)
	total = 0
	for _, e in ipairs(list) do
		total += (Defs.Treasure[e.Id].Layers[layer.Id])
		e.Cum = total
	end
	weighted[layer.Id] = { List = list, Total = total }
end

function Defs.PickTreasure(layerId: string, rng: Random): string?
	local w = weighted[layerId]
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

-- Shop catalogue, sorted. Items: { Kind = "Tool"|"Backpack", Id, Def }
function Defs.ShopItems()
	local items = {}
	for id, def in pairs(Defs.Tools) do
		if def.Price > 0 then
			table.insert(items, { Kind = "Tool", Id = id, Def = def })
		end
	end
	for id, def in pairs(Defs.Backpacks) do
		if def.Price > 0 then
			table.insert(items, { Kind = "Backpack", Id = id, Def = def })
		end
	end
	table.sort(items, function(a, b)
		if a.Def.Price ~= b.Def.Price then
			return a.Def.Price < b.Def.Price
		end
		return a.Id < b.Id
	end)
	return items
end

return Defs
