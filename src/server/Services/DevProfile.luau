-- Pure data operations on a PLAYER PROFILE TABLE used by developer test mode (tests/dev_mode_test.luau). They are only ever applied to the
-- in-memory TEST OVERLAY (DataService keeps the real profile aside, untouched, and never saves the overlay). Nothing here touches a DataStore.
local DevProfile = {}

function DevProfile.UnlockAllEquipment(data, defs)
	for id in pairs(defs.Tools) do
		data.OwnedTools[id] = true
	end
	for id in pairs(defs.Backpacks) do
		data.OwnedBackpacks[id] = true
	end
	for id, def in pairs(defs.Consumables or {}) do
		data.Consumables[id] = def.MaxCarry -- e.g. a full set of dynamite
	end
end

-- Equips an owned/unlocked tool or backpack. Returns false when the id is unknown (nothing changes).
function DevProfile.Equip(data, kind: string, id: string, defs): boolean
	if kind == "Tool" and defs.Tools[id] then
		data.OwnedTools[id] = true
		data.Equipment.ToolId = id
		return true
	elseif kind == "Backpack" and defs.Backpacks[id] then
		data.OwnedBackpacks[id] = true
		data.Equipment.BackpackId = id
		return true
	end
	return false
end

function DevProfile.GrantCash(data, amount: number, maxCash: number): number
	local n = math.floor(math.clamp(amount, 0, maxCash))
	data.Cash += n
	return n
end

-- Adds every collection entry (count 1 where missing) and fills the camp shelf up to its slot count, for previewing UI and displays.
function DevProfile.UnlockCollection(data, collectionSpec, defs, now: number, slots: number)
	local ids = {}
	for id in pairs(defs.Treasure) do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		if not data.Collection[id] then
			collectionSpec.Register(data.Collection, id, now)
		end
	end
	local shelf = {}
	for _, id in ipairs(ids) do
		if #shelf < slots then
			table.insert(shelf, id)
		end
	end
	data.Display = collectionSpec.SanitizeDisplay(shelf, data.Collection)
end

return DevProfile
