-- The buried loot of one mine generation: who may take what, exactly once. Pure (no Roblox APIs), tested in
-- tests/loot_reset_test.luau. A claim names the generation it was made for; a request from an old generation can never
-- take loot from the new mine at the same coordinates, and a cell's reward can be taken only once.
local LootBoard = {}
LootBoard.__index = LootBoard

function LootBoard.new(generation: number, loot: { [number]: string })
	return setmetatable({ generation = generation, loot = loot, taken = 0 }, LootBoard)
end

function LootBoard:Generation(): number
	return self.generation
end

function LootBoard:Peek(index: number): string?
	return self.loot[index]
end

-- Returns the treasure id the FIRST time a cell is claimed in the right generation; nil otherwise (nothing there, already
-- claimed, or the request belongs to another generation).
function LootBoard:Claim(index: number, generation: number): string?
	if generation ~= self.generation then
		return nil
	end
	local id = self.loot[index]
	if id == nil then
		return nil
	end
	self.loot[index] = nil
	self.taken += 1
	return id
end

function LootBoard:Remaining(): number
	local n = 0
	for _ in pairs(self.loot) do
		n += 1
	end
	return n
end

return LootBoard
