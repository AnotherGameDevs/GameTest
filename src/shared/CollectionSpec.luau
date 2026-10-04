-- Pure collection logic (no Roblox APIs beyond Defs/Config data), shared by the server (recording, set completion) and
-- the client (journal). Tested in tests/collection_test.luau.
--   * One journal entry per treasure type. Its "home layer" is the layer where it is most common (ties -> shallower).
--   * A SET is every treasure whose home layer is the same. Completing a set is acknowledged once, at the moment the
--     last member is registered.
--   * `collection` is the saved table: [treasureId] = { Count, FirstFound }.
local Config = require(script.Parent.Config)
local Defs = require(script.Parent.Defs)

local CollectionSpec = {}

local layerOrder = {}
for i, layer in ipairs(Config.Layers) do
	layerOrder[layer.Id] = i
end

local function homeLayer(def): string
	local best, bestWeight, bestOrder = Config.Layers[1].Id, -1, 99
	for layerId, weight in pairs(def.Layers) do
		local order = layerOrder[layerId] or 99
		if weight > bestWeight or (weight == bestWeight and order < bestOrder) then
			best, bestWeight, bestOrder = layerId, weight, order
		end
	end
	return best
end

-- Ordered entries: by home layer (shallow -> deep), then rarity, then value.
local entries = {}
for id, def in pairs(Defs.Treasure) do
	table.insert(entries, { Id = id, Def = def, Layer = homeLayer(def) })
end
table.sort(entries, function(a, b)
	if layerOrder[a.Layer] ~= layerOrder[b.Layer] then
		return layerOrder[a.Layer] < layerOrder[b.Layer]
	end
	local ra, rb = Defs.Rarity[a.Def.Rarity].Order, Defs.Rarity[b.Def.Rarity].Order
	if ra ~= rb then
		return ra < rb
	end
	if a.Def.Value ~= b.Def.Value then
		return a.Def.Value < b.Def.Value
	end
	return a.Id < b.Id
end)
CollectionSpec.Entries = entries

local byId = {}
for _, e in ipairs(entries) do
	byId[e.Id] = e
end

function CollectionSpec.Entry(id: string)
	return byId[id]
end

function CollectionSpec.IsValid(id: any): boolean
	return type(id) == "string" and byId[id] ~= nil
end

-- Per-layer set status for a saved collection.
function CollectionSpec.Sets(collection)
	local sets, byLayer = {}, {}
	for _, layer in ipairs(Config.Layers) do
		local set = { LayerId = layer.Id, Name = layer.Name, Found = 0, Total = 0, Complete = false, Members = {} }
		byLayer[layer.Id] = set
		table.insert(sets, set)
	end
	for _, e in ipairs(entries) do
		local set = byLayer[e.Layer]
		set.Total += 1
		table.insert(set.Members, e.Id)
		if collection[e.Id] then
			set.Found += 1
		end
	end
	for _, set in ipairs(sets) do
		set.Complete = set.Total > 0 and set.Found == set.Total
	end
	return sets
end

function CollectionSpec.Totals(collection): (number, number)
	local found = 0
	for _, e in ipairs(entries) do
		if collection[e.Id] then
			found += 1
		end
	end
	return found, #entries
end

-- The set that `treasureId` completes if it is registered NOW (nil if it does not complete anything or it is already
-- registered). Call BEFORE writing the entry.
function CollectionSpec.CompletesSet(collection, treasureId: string): string?
	local e = byId[treasureId]
	if not e or collection[treasureId] then
		return nil
	end
	for _, set in ipairs(CollectionSpec.Sets(collection)) do
		if set.LayerId == e.Layer then
			return set.Found + 1 == set.Total and set.LayerId or nil
		end
	end
	return nil
end

-- Registers one find; returns (isNew, completedLayerId?). The ONLY place a collection entry is created.
function CollectionSpec.Register(collection, treasureId: string, now: number): (boolean, string?)
	if not byId[treasureId] then
		return false, nil
	end
	local entry = collection[treasureId]
	if entry then
		entry.Count += 1
		return false, nil
	end
	local completed = CollectionSpec.CompletesSet(collection, treasureId)
	collection[treasureId] = { Count = 1, FirstFound = now }
	return true, completed
end

-- Display list hygiene: only discovered, known, unique ids; at most Config.Collection.DisplaySlots; keeps order.
function CollectionSpec.SanitizeDisplay(list: any, collection): { string }
	local out, seen = {}, {}
	if type(list) ~= "table" then
		return out
	end
	for _, id in ipairs(list) do
		if #out >= Config.Collection.DisplaySlots then
			break
		end
		if type(id) == "string" and byId[id] and collection[id] and not seen[id] then
			seen[id] = true
			table.insert(out, id)
		end
	end
	return out
end

-- Toggle `id` in the display list. Returns (newList, ok, reason?). Adding to a full list is refused (never silently
-- replaces someone's choice).
function CollectionSpec.ToggleDisplay(list: { string }, id: any, collection): ({ string }, boolean, string?)
	local current = CollectionSpec.SanitizeDisplay(list, collection)
	if type(id) ~= "string" or not byId[id] then
		return current, false, "Unknown"
	end
	if not collection[id] then
		return current, false, "NotDiscovered"
	end
	for i, existing in ipairs(current) do
		if existing == id then
			table.remove(current, i)
			return current, true
		end
	end
	if #current >= Config.Collection.DisplaySlots then
		return current, false, "Full"
	end
	table.insert(current, id)
	return current, true
end

return CollectionSpec
