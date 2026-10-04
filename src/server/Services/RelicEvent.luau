-- The contested server relic as a pure state machine (no Roblox APIs; tests/relic_test.luau).
--   Hidden (a cell holding it; not an event yet) -> Discovered -> Carried <-> Dropped -> Secured | Expired
-- Every transition is one synchronous check-and-set, so two simultaneous pickups or deposits can never both succeed.
-- A dropped relic is UNCLAIMED: ownership changes only through a validated Pickup. Secured and Expired are terminal: every later
-- pickup, attack or deposit request on that event fails.
local RelicEvent = {}
RelicEvent.__index = RelicEvent

function RelicEvent.new(id: string, treasureId: string, value: number, discovererId: number, position, generation: number, policy, now: number)
	return setmetatable({
		Id = id, TreasureId = treasureId, Value = value, DiscovererId = discovererId, Position = position, Generation = generation,
		State = "Discovered", CarrierId = nil, Control = policy.MaxControl, ProtectedUntil = 0, SafeSeconds = 0, LastTrack = nil :: number?, LastDropperId = nil :: number?, DroppedAt = -1e9,
		Transfers = 0, DiscoveredAt = now, policy = policy,
	}, RelicEvent)
end

function RelicEvent:IsActive(): boolean
	return self.State == "Discovered" or self.State == "Carried" or self.State == "Dropped"
end

-- Atomic: the first valid pickup wins. Anyone may pick up (no ownership) while the relic is on the ground.
function RelicEvent:Pickup(userId: number, now: number): (boolean, string?)
	if not self:IsActive() then
		return false, "Over"
	end
	if self.State == "Carried" then
		return false, "AlreadyCarried"
	end
	if userId == self.LastDropperId and now - self.DroppedAt < self.policy.RegrabLockout then
		return false, "TooSoon" -- placing it down and re-grabbing must not refill the control meter
	end
	self.State = "Carried"
	self.CarrierId = userId
	self.Control = self.policy.MaxControl -- a new carrier starts with full control...
	self.ProtectedUntil = now + self.policy.PickupProtection -- ...and a SHORT protection window
	self.SafeSeconds = 0
	self.LastTrack = nil
	self.Transfers += 1
	return true
end

-- Voluntary placement or any forced drop. The relic becomes unclaimed at `position`.
function RelicEvent:Drop(position, now: number): boolean
	if self.State ~= "Carried" then
		return false
	end
	self.State = "Dropped"
	self.LastDropperId = self.CarrierId
	self.DroppedAt = now
	self.CarrierId = nil
	self.Position = position
	self.SafeSeconds = 0
	self.LastTrack = nil
	self.ProtectedUntil = 0
	return true
end

-- A validated hit. Returns (applied, dropped). Hits during protection or on a non-carried relic do nothing.
function RelicEvent:Hit(attackerId: number, amount: number, now: number): (boolean, boolean)
	if self.State ~= "Carried" or attackerId == self.CarrierId or now < self.ProtectedUntil then
		return false, false
	end
	self.Control = math.max(self.Control - amount, 0)
	if self.Control <= 0 then
		return true, true
	end
	return true, false
end

-- Exactly once: only the current carrier can bank it.
function RelicEvent:Deposit(userId: number): (boolean, any)
	if self.State ~= "Carried" or self.CarrierId ~= userId then
		return false, "NotCarrying"
	end
	self.State = "Secured"
	self.CarrierId = nil
	return true, self.Value
end

-- Reset (or any server decision) ends the event with NO reward.
function RelicEvent:Expire(): boolean
	if not self:IsActive() then
		return false
	end
	self.State = "Expired"
	self.CarrierId = nil
	return true
end

-- Camp safe-zone grace: CUMULATIVE time spent in the safe zone. Stepping out does not reset it (that would allow stalling at the
-- line); it only drains at half speed. Returns true once the carrier has used up the grace.
function RelicEvent:TrackCamp(inSafeZone: boolean, now: number): boolean
	if self.State ~= "Carried" then
		self.SafeSeconds = 0
		self.LastTrack = nil
		return false
	end
	local dt = self.LastTrack and math.max(now - self.LastTrack, 0) or 0
	self.LastTrack = now
	if inSafeZone then
		self.SafeSeconds += dt
	else
		self.SafeSeconds = math.max(self.SafeSeconds - dt * 0.5, 0)
	end
	return self.SafeSeconds >= self.policy.CampGraceSeconds
end

return RelicEvent
