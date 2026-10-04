-- The mine's reset lifecycle as a pure state machine (no Roblox APIs; tests/loot_reset_test.luau).
--   Active -> Warning -> Evacuating -> Regenerating -> Active
-- Exactly one reset can be in flight: `Update` only starts a reset from Active, every later transition is explicit and
-- ordered, and a reset in any other state is ignored, so resets cannot overlap or loop. Only the server drives it.
local MineLifecycle = {}
MineLifecycle.__index = MineLifecycle

-- policy = Config.Reset-shaped table. `now` is any monotonic clock in seconds.
function MineLifecycle.new(policy, now: number)
	return setmetatable({
		policy = policy,
		state = "Active",
		generation = 1,
		activeSeconds = 0, -- time the CURRENT generation has been Active with at least one player online
		reason = nil :: string?,
		endsAt = 0, -- when the current Warning / Evacuating phase ends
		lastTick = now,
		resets = 0,
		heldSeconds = 0, -- time the Warning has been held open for an active relic event
	}, MineLifecycle)
end

function MineLifecycle:State(): string
	return self.state
end

function MineLifecycle:Generation(): number
	return self.generation
end

function MineLifecycle:Reason(): string?
	return self.reason
end

function MineLifecycle:EndsAt(): number
	return self.endsAt
end

-- Mining and artifact pickups are accepted only while the mine is Active or in its Warning countdown.
function MineLifecycle:AcceptingRequests(): boolean
	return self.state == "Active" or self.state == "Warning"
end

function MineLifecycle:IsCurrent(generation: number): boolean
	return generation == self.generation
end

-- Seconds of active play left before the scheduled reset (nil unless Active).
function MineLifecycle:SecondsToScheduled(): number?
	if self.state ~= "Active" then
		return nil
	end
	return math.max(self.policy.IntervalMinutes * 60 - self.activeSeconds, 0)
end

-- Advances the clock and the state machine. Returns an event for the caller to act on, or nil:
--   "Warn"       a reset was just decided (reason via :Reason()); begin the countdown UI
--   "Evacuate"   the warning ended: stop accepting requests, recover artifacts, move players
-- `depletion` = fraction of diggable cells removed (0..1); `players` = players currently online.
function MineLifecycle:Update(now: number, depletion: number, players: number, holdWanted: boolean?): string?
	local dt = math.max(now - self.lastTick, 0)
	self.lastTick = now
	local p = self.policy
	if self.state == "Active" then
		if players > 0 then
			self.activeSeconds += dt
		end
		local reason
		if self.activeSeconds >= p.IntervalMinutes * 60 then
			reason = "Scheduled"
		elseif self.activeSeconds >= p.MinLifetimeMinutes * 60 and depletion >= p.DepletionFraction then
			reason = "Depleted"
		end
		if reason then
			self.state = "Warning"
			self.reason = reason
			self.endsAt = now + p.WarningSeconds
			self.resets += 1
			return "Warn"
		end
	elseif self.state == "Warning" then
		if now >= self.endsAt and holdWanted and self.heldSeconds < (p.RelicHoldSeconds or 0) then
			-- an active relic event may finish first, for a bounded time only
			self.heldSeconds += dt
			return nil
		end
		if now >= self.endsAt then
			self.state = "Evacuating"
			self.endsAt = now + p.EvacuateSeconds
			return "Evacuate"
		end
	end
	return nil
end

function MineLifecycle:IsHolding(now: number): boolean
	return self.state == "Warning" and now >= self.endsAt and self.heldSeconds < (self.policy.RelicHoldSeconds or 0)
end

-- Evacuation + artifact recovery finished -> the old mine may be torn down.
function MineLifecycle:BeginRegeneration(): boolean
	if self.state ~= "Evacuating" then
		return false
	end
	self.state = "Regenerating"
	return true
end

-- The new mine is fully built -> a NEW generation id, fresh timers, back to Active.
function MineLifecycle:FinishRegeneration(now: number): boolean
	if self.state ~= "Regenerating" then
		return false
	end
	self.generation += 1
	self.state = "Active"
	self.activeSeconds = 0
	self.reason = nil
	self.endsAt = 0
	self.heldSeconds = 0
	self.lastTick = now
	return true
end

return MineLifecycle
