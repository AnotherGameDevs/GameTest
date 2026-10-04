-- Pure state machine for important-artifact ownership. No Roblox APIs, so it is unit-tested outside Studio
-- (tests/artifact_test.luau). Every transition is a synchronous check-and-set: there is no yield between "is it
-- allowed?" and "do it", so two simultaneous requests can never both succeed.
--
--   Dropped --Pickup--> Carried --Deposit--> Deposited (terminal; value paid exactly once)
--      ^                   |
--      +---Place / Drop----+      (Drop = forced: death, respawn, disconnect)
--
-- Records live only in server memory. They are NOT saved: an artifact never in a DataStore cannot be counted as
-- deposited by loading a saved character. Cash/collection are written only by a successful Deposit.
local ArtifactRecords = {}
ArtifactRecords.__index = ArtifactRecords

function ArtifactRecords.new(idGenerator: () -> string)
	return setmetatable({ records = {}, carried = {}, idGenerator = idGenerator }, ArtifactRecords)
end

-- `position` is where the artifact first rests. OwnerId = discoverer (claims it for this version).
function ArtifactRecords:Create(treasureId: string, value: number, ownerId: number, position, generation: number?)
	local id = self.idGenerator()
	local rec = {
		Id = id, TreasureId = treasureId, Value = value, OwnerId = ownerId,
		State = "Dropped", CarrierId = nil, Position = position, Origin = position, Transfers = 0,
		Generation = generation or 1, Recovered = false,
	}
	self.records[id] = rec
	return rec
end

function ArtifactRecords:Get(id: string)
	return self.records[id]
end

function ArtifactRecords:CarriedBy(userId: number)
	local id = self.carried[userId]
	return id and self.records[id] or nil
end

function ArtifactRecords:Pickup(id: string, userId: number): (boolean, string?)
	local rec = self.records[id]
	if not rec then
		return false, "Missing"
	end
	if rec.State == "Deposited" then
		return false, "AlreadyDeposited"
	end
	if rec.State ~= "Dropped" then
		return false, "NotAvailable"
	end
	if rec.OwnerId ~= userId then
		return false, "NotOwner"
	end
	if self.carried[userId] then
		return false, "AlreadyCarrying"
	end
	rec.State = "Carried"
	rec.CarrierId = userId
	rec.Transfers += 1
	self.carried[userId] = id
	return true
end

function ArtifactRecords:Place(id: string, userId: number, position): (boolean, string?)
	local rec = self.records[id]
	if not rec or rec.State ~= "Carried" or rec.CarrierId ~= userId then
		return false, "NotCarrying"
	end
	rec.State = "Dropped"
	rec.CarrierId = nil
	rec.Position = position
	self.carried[userId] = nil
	return true
end

-- Returns (true, value) exactly once per artifact.
function ArtifactRecords:Deposit(id: string, userId: number): (boolean, any)
	local rec = self.records[id]
	if not rec then
		return false, "Missing"
	end
	if rec.State == "Deposited" then
		return false, "AlreadyDeposited"
	end
	if rec.State ~= "Carried" or rec.CarrierId ~= userId then
		return false, "NotCarrying"
	end
	rec.State = "Deposited"
	rec.CarrierId = nil
	self.carried[userId] = nil
	return true, rec.Value
end

-- Forced drop (death / respawn / disconnect). Never awards anything. Idempotent.
function ArtifactRecords:Drop(id: string, position): boolean
	local rec = self.records[id]
	if not rec or rec.State ~= "Carried" then
		return false
	end
	if rec.CarrierId then
		self.carried[rec.CarrierId] = nil
	end
	rec.State = "Dropped"
	rec.CarrierId = nil
	rec.Position = position
	return true
end

-- Moves a resting (Dropped) artifact without changing its owner or state (used when the mine is refreshed).
function ArtifactRecords:Relocate(id: string, position): boolean
	local rec = self.records[id]
	if not rec or rec.State ~= "Dropped" then
		return false
	end
	rec.Position = position
	return true
end

-- Every resting artifact (state Dropped). Order is unspecified.
function ArtifactRecords:Dropped()
	local out = {}
	for _, rec in pairs(self.records) do
		if rec.State == "Dropped" then
			table.insert(out, rec)
		end
	end
	return out
end

-- Mine reset recovery: a Carried or Dropped artifact is put down at `position` (the recovery area), still owned by its
-- discoverer and flagged Recovered. It is NEVER deposited, paid or removed here - the owner must pick it up and deliver it
-- like any other artifact. A Deposited record is untouched (it can not be recovered twice), and the record count never changes.
function ArtifactRecords:Recover(id: string, position): boolean
	local rec = self.records[id]
	if not rec or rec.State == "Deposited" then
		return false
	end
	if rec.State == "Carried" and rec.CarrierId then
		self.carried[rec.CarrierId] = nil
	end
	rec.State = "Dropped"
	rec.CarrierId = nil
	rec.Position = position
	rec.Recovered = true
	return true
end

return ArtifactRecords
