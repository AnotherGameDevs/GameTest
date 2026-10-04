-- Pure rules for the contested relic (no Roblox instances; tests/relic_test.luau). The server feeds these the measured facts
-- (distances, line of sight, clock) and only acts when they say yes.
local Config = require(script.Parent.Config)

local RelicRules = {}

-- The camp's safe zone: the camp floor from SafeBoundaryZ to its far edge, within its width, at ground height.
function RelicRules.InSafeZone(x: number, y: number, z: number): boolean
	local camp, r = Config.Camp, Config.Relic
	local halfX = camp.Size.X / 2
	local farZ = camp.Position.Z + camp.Size.Z / 2
	return z >= r.SafeBoundaryZ and z <= farZ + 4 and math.abs(x - camp.Position.X) <= halfX + 4 and y < 14
end

-- Pickup distance: exactly what the prompt shows, plus the small documented tolerance (interaction consistency, not balance).
function RelicRules.PickupInReach(distance: number): boolean
	return distance <= Config.Relic.PickupReach + Config.Relic.PickupTolerance
end

-- May `attacker` strike the carrier right now? ctx = { EventState, AttackerId, CarrierId, Distance, LineOfSight,
-- Now, LastAttack, ProtectedUntil, AttackerAlive, CarrierAlive, AttackerCarrying, AttackerInSafe, CarrierInSafe }
function RelicRules.CheckStrike(ctx): (boolean, string?)
	local r = Config.Relic
	if ctx.EventState ~= "Carried" then
		return false, "NoCarrier"
	end
	if ctx.AttackerId == ctx.CarrierId then
		return false, "Self"
	end
	if not ctx.AttackerAlive or not ctx.CarrierAlive then
		return false, "Dead"
	end
	if ctx.AttackerCarrying then
		return false, "AttackerBusy"
	end
	if ctx.AttackerInSafe or ctx.CarrierInSafe then
		return false, "SafeZone"
	end
	if ctx.Now - (ctx.LastAttack or -1e9) < r.AttackCooldown then
		return false, "Cooldown"
	end
	if ctx.Distance > r.AttackRange then
		return false, "Range"
	end
	if not ctx.LineOfSight then
		return false, "Blocked"
	end
	return true
end

-- May the carrier shove `targetId` right now? ctx = { EventState, CarrierId, TargetId, Distance, LineOfSight, Now, LastShove,
-- LastTargetAttack (when that player last struck at the carrier), CarrierAlive, TargetAlive, TargetInSafe, CarrierInSafe }
function RelicRules.CheckShove(ctx): (boolean, string?)
	local r = Config.Relic
	if ctx.EventState ~= "Carried" then
		return false, "NoCarrier"
	end
	if ctx.TargetId == ctx.CarrierId then
		return false, "Self"
	end
	if not ctx.CarrierAlive or not ctx.TargetAlive then
		return false, "Dead"
	end
	if ctx.TargetInSafe or ctx.CarrierInSafe then
		return false, "SafeZone"
	end
	if ctx.Now - (ctx.LastShove or -1e9) < r.ShoveCooldown then
		return false, "Cooldown"
	end
	if ctx.Now - (ctx.LastTargetAttack or -1e9) > r.ShoveEngageSeconds then
		return false, "Unrelated" -- only players who are actually attacking the carrier can be shoved
	end
	if ctx.Distance > r.ShoveRange then
		return false, "Range"
	end
	if not ctx.LineOfSight then
		return false, "Blocked"
	end
	return true
end

-- Bounded knockback: horizontal speed and upward speed are both capped. Returns (vx, vy, vz).
function RelicRules.ClampKnockback(dx: number, dz: number, speed: number, up: number): (number, number, number)
	local r = Config.Relic
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-6 then
		return 0, 0, 0
	end
	local h = math.min(math.max(speed, 0), r.MaxKnockbackH)
	return dx / len * h, math.min(math.max(up, 0), r.MaxKnockbackUp), dz / len * h
end

return RelicRules
