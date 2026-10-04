-- Run via tests/run_all.sh. BEHAVIOUR of the contested relic: state machine, combat validation, safe zone, reset hold.
local Config = require("./_build/shared/Config")
local Defs = require("./_build/shared/Defs")
local MineStyle = require("./_build/shared/MineStyle")
local RelicRules = require("./_build/shared/RelicRules")
local RelicEvent = require("../src/server/Services/RelicEvent")
local MineLifecycle = require("../src/server/Services/MineLifecycle")

local passed, failed = 0, 0
local function check(name, cond, detail) if cond then passed += 1 else failed += 1; print("FAIL: " .. name .. (detail and ("  -> " .. detail) or "")) end end
local R = Config.Relic
local function newEvent(now) return RelicEvent.new("E1", "sun_mask", 3500, 1, { X = 0 }, 1, R, now or 0) end

-- ================================================================== artifact types are explicit =====================
do
	local kinds = { Ordinary = 0, Personal = 0, Relic = 0 }
	for id, def in pairs(Defs.Treasure) do kinds[Defs.KindOf(def)] += 1 end
	check("exactly one treasure is a server relic, and it is flagged explicitly", kinds.Relic == 1 and Defs.Treasure.sun_mask.Relic == true)
	check("personal important artifacts keep their rules", Defs.KindOf(Defs.Treasure.fossil_claw) == "Personal" and Defs.KindOf(Defs.Treasure.golden_scarab) == "Personal")
	check("ordinary loot stays ordinary however valuable", Defs.KindOf(Defs.Treasure.cut_gemstone) == "Ordinary" and Defs.Treasure.cut_gemstone.Value > 100)
	check("rarity alone never makes a relic", (function() for _, d in pairs(Defs.Treasure) do if d.Rarity == "Epic" and d.Relic then return false end end return true end)())
	check("the relic is limited to one per generation", Config.Loot.ImportantLimits.sun_mask == 1)
	check("an undiscovered relic is never hinted at (no tell, no remnant)", (function()
		for x = 0, 23 do for z = 0, 23 do if MineStyle.Detail(x, 17, z, "Ruins", 1337, "sun_mask", nil) ~= nil then return false end end end
		return true
	end)())
end

-- ================================================================== discovery, pickup, ownership ====================
do
	local e = newEvent(0)
	check("a discovered relic is active and unclaimed", e.State == "Discovered" and e:IsActive() and e.CarrierId == nil)
	check("the first pickup wins", e:Pickup(2, 10) and e.State == "Carried" and e.CarrierId == 2)
	check("a simultaneous second pickup fails", not e:Pickup(3, 10) and e.CarrierId == 2)
	check("a new carrier starts with full control and a short protection", e.Control == R.MaxControl and e.ProtectedUntil == 10 + R.PickupProtection)
	check("protection is short (< 6 s) so it can not cover an escape", R.PickupProtection < 6)
	check("placing it down makes it unclaimed (no exclusive owner)", e:Drop({ X = 5 }, 20) and e.State == "Dropped" and e.CarrierId == nil and e.Position.X == 5)
	check("ANOTHER player may take it (ownership transfers on validated pickup only)", e:Pickup(3, 21) and e.CarrierId == 3 and e.Transfers == 2)
	check("the event identity is unchanged through transfers", e.Id == "E1" and e.TreasureId == "sun_mask")
	-- place-down + re-grab must not refill the control meter
	local g = newEvent(0); g:Pickup(2, 0)
	g:Hit(3, R.ControlPerHit, R.PickupProtection + 1)
	g:Drop({ X = 1 }, 10)
	check("the player who just dropped it can not instantly re-grab it", not g:Pickup(2, 10.5) and select(2, g:Pickup(2, 10.5)) == "TooSoon")
	check("someone else can, and the dropper can after the lockout", g:Pickup(3, 11) and g:Drop({ X = 2 }, 12) and g:Pickup(2, 12 + R.RegrabLockout + 0.1))
end

-- ================================================================== control meter =====================================
do
	local e = newEvent(0)
	e:Pickup(2, 100)
	local applied = e:Hit(3, R.ControlPerHit, 101)
	check("hits during pickup protection do nothing (no instant drop/pickup chain)", not applied and e.Control == R.MaxControl)
	local t = 100 + R.PickupProtection + 0.1
	local a1, d1 = e:Hit(3, R.ControlPerHit, t)
	check("a validated hit reduces control", a1 and not d1 and e.Control == R.MaxControl - R.ControlPerHit)
	check("the carrier can not hit themselves", not e:Hit(2, R.ControlPerHit, t + 1))
	local dropped = false
	for i = 1, 10 do local _, d = e:Hit(3, R.ControlPerHit, t + i); if d then dropped = true; break end end
	check("at zero control the relic reports a drop", dropped and e.Control == 0)
	check("hits needed is small and configurable", math.ceil(R.MaxControl / R.ControlPerHit) >= 3 and math.ceil(R.MaxControl / R.ControlPerHit) <= 6)
	e:Drop({ X = 1 }, t + 11)
	check("a hit on a dropped relic does nothing", not e:Hit(3, 25, t + 12))
	e:Pickup(4, t + 13)
	check("a new carrier gets control restored", e.Control == R.MaxControl and e.CarrierId == 4)
	check("a hit by the previous carrier is allowed after protection (relic control is not tool-based)", e:Hit(2, R.ControlPerHit, t + 13 + R.PickupProtection + 0.1))
end

-- ================================================================== combat validation =================================
do
	local function ctx(over)
		local c = { EventState = "Carried", AttackerId = 3, CarrierId = 2, Distance = 4, LineOfSight = true, Now = 100, LastAttack = nil, ProtectedUntil = 0,
			AttackerAlive = true, CarrierAlive = true, AttackerCarrying = false, AttackerInSafe = false, CarrierInSafe = false }
		for k, v in pairs(over or {}) do c[k] = v end
		return c
	end
	check("a normal strike is allowed", RelicRules.CheckStrike(ctx()))
	check("no strike without a carrier (event state)", select(2, RelicRules.CheckStrike(ctx({ EventState = "Dropped" }))) == "NoCarrier")
	check("no strike once the event is secured/expired", not RelicRules.CheckStrike(ctx({ EventState = "Secured" })) and not RelicRules.CheckStrike(ctx({ EventState = "Expired" })))
	check("out of range is rejected", select(2, RelicRules.CheckStrike(ctx({ Distance = R.AttackRange + 0.5 }))) == "Range")
	check("through walls is rejected", select(2, RelicRules.CheckStrike(ctx({ LineOfSight = false }))) == "Blocked")
	check("cooldown is enforced", select(2, RelicRules.CheckStrike(ctx({ LastAttack = 99.5 }))) == "Cooldown" and RelicRules.CheckStrike(ctx({ LastAttack = 100 - R.AttackCooldown - 0.01 })))
	check("you can not strike yourself", select(2, RelicRules.CheckStrike(ctx({ AttackerId = 2 }))) == "Self")
	check("the safe zone stops all strikes (either side)", select(2, RelicRules.CheckStrike(ctx({ CarrierInSafe = true }))) == "SafeZone" and select(2, RelicRules.CheckStrike(ctx({ AttackerInSafe = true }))) == "SafeZone")
	check("another carrier can not attack", select(2, RelicRules.CheckStrike(ctx({ AttackerCarrying = true }))) == "AttackerBusy")
	check("dead players can not strike or be struck", not RelicRules.CheckStrike(ctx({ AttackerAlive = false })) and not RelicRules.CheckStrike(ctx({ CarrierAlive = false })))

	local function sctx(over)
		local c = { EventState = "Carried", CarrierId = 2, TargetId = 3, Distance = 4, LineOfSight = true, Now = 100, LastShove = nil, LastTargetAttack = 95,
			CarrierAlive = true, TargetAlive = true, TargetInSafe = false, CarrierInSafe = false }
		for k, v in pairs(over or {}) do c[k] = v end
		return c
	end
	check("the carrier can shove an attacker", RelicRules.CheckShove(sctx()))
	check("unrelated players can not be shoved", select(2, RelicRules.CheckShove(sctx({ LastTargetAttack = -1e9 }))) == "Unrelated" and select(2, RelicRules.CheckShove(sctx({ LastTargetAttack = 100 - R.ShoveEngageSeconds - 1 }))) == "Unrelated")
	check("shove has a cooldown, range and line of sight", select(2, RelicRules.CheckShove(sctx({ LastShove = 99 }))) == "Cooldown" and select(2, RelicRules.CheckShove(sctx({ Distance = R.ShoveRange + 1 }))) == "Range" and select(2, RelicRules.CheckShove(sctx({ LineOfSight = false }))) == "Blocked")
	check("no shoving in the safe zone", select(2, RelicRules.CheckShove(sctx({ TargetInSafe = true }))) == "SafeZone")
	local vx, vy, vz = RelicRules.ClampKnockback(3, 4, 500, 500)
	check("knockback is bounded horizontally and vertically", math.sqrt(vx * vx + vz * vz) <= R.MaxKnockbackH + 1e-6 and vy <= R.MaxKnockbackUp and vx > 0 and vz > 0)
	check("knockback of nothing is nothing", select(1, RelicRules.ClampKnockback(0, 0, 10, 5)) == 0)
end

-- ================================================================== safe zone and deposit ============================
do
	local camp = Config.Camp
	check("the safe zone starts at the configured boundary", not RelicRules.InSafeZone(0, 3, R.SafeBoundaryZ - 0.5) and RelicRules.InSafeZone(0, 3, R.SafeBoundaryZ + 0.5))
	check("the mine, the entrance and the recovery pad are outside the safe zone", not RelicRules.InSafeZone(0, 3, 30) and not RelicRules.InSafeZone(R.RecoveryPoint.X, 3, R.RecoveryPoint.Z) and not RelicRules.InSafeZone(camp.RecoveryPosition.X, 3, camp.RecoveryPosition.Z))
	check("the receiving table is inside the safe zone but close to the boundary", RelicRules.InSafeZone(camp.ReceivingPosition.X, 3, camp.ReceivingPosition.Z) and camp.ReceivingPosition.Z - R.SafeBoundaryZ <= 12)
	check("the elevator exit is outside the safe zone (pursuit can continue there)", not RelicRules.InSafeZone(camp.ReceivingPosition.X + 4, 3, 58))
	check("the recovery point is on the entrance boardwalk, beside the dig", R.RecoveryPoint.Z > 48 and R.RecoveryPoint.Z < camp.Position.Z - camp.Size.Z / 2)

	local e = newEvent(0); e:Pickup(2, 0)
	check("entering the safe zone does not award anything", e.State == "Carried" and not e:TrackCamp(true, 5))
	check("the grace period is short and configurable", R.CampGraceSeconds >= 10 and R.CampGraceSeconds <= 40)
	e:TrackCamp(true, 10); e:TrackCamp(true, 15)
	local before = e.SafeSeconds
	e:TrackCamp(false, 17)
	check("stepping out does not reset the grace (it only drains slowly)", e.SafeSeconds > 0 and e.SafeSeconds < before)
	local stall = newEvent(0); stall:Pickup(2, 0)
	local t, tripped = 0, false
	for i = 1, 200 do -- stepping across the line every 8 s never escapes the grace
		t += 1
		local inside = (i // 8) % 2 == 0
		if stall:TrackCamp(inside, t) then tripped = true; break end
	end
	check("zig-zagging across the boundary can not stall forever", tripped and t < 200)
	local steady = newEvent(0); steady:Pickup(2, 0)
	steady:TrackCamp(true, 0)
	check("standing in the safe zone past the grace is detected", not steady:TrackCamp(true, R.CampGraceSeconds - 1) and steady:TrackCamp(true, R.CampGraceSeconds))
	local ok, value = e:Deposit(2)
	check("the carrier deposits: reward exactly once", ok and value == 3500 and e.State == "Secured")
	check("a second deposit fails", not e:Deposit(2))
	check("nobody else can deposit or pick it up afterwards", not newEvent(0):Deposit(5) and not e:Pickup(5, 50))
	local e2 = newEvent(0); e2:Pickup(2, 0)
	check("only the carrier can deposit (a thief who is not carrying can not)", not e2:Deposit(3) and e2.State == "Carried")
	check("simultaneous deposit requests: one succeeds", (function() local a, _ = e2:Deposit(2); local b, _ = e2:Deposit(2); return a and not b end)())
end

-- ================================================================== expiry and stale requests ========================
do
	local e = newEvent(0); e:Pickup(2, 0)
	check("expiry ends the event with no reward", e:Expire() and e.State == "Expired" and e.CarrierId == nil and not e:IsActive())
	check("expiring twice is harmless", not e:Expire())
	check("stale pickup, hit and deposit are rejected after expiry", not e:Pickup(3, 9) and not e:Hit(3, 25, 99) and not e:Deposit(2))
	local d = newEvent(0)
	check("a dropped relic can also be expired", d:Pickup(2, 0) and d:Drop({ X = 1 }, 1) and d:Expire() and not d:Pickup(3, 2))
	local s = newEvent(0); s:Pickup(2, 0); s:Deposit(2)
	check("a secured relic can not expire or move again", not s:Expire() and s.State == "Secured")
end

-- ================================================================== reset hold (bounded) ==============================
do
	local P = Config.Reset
	local L = MineLifecycle.new(P, 0)
	local t = 0
	local function run(sec, hold)
		local ev = {}
		for _ = 1, sec do t += 1; local e = L:Update(t, 0, 2, hold); if e then table.insert(ev, e) end end
		return ev
	end
	run(P.IntervalMinutes * 60, false) -- scheduled warning begins
	check("a reset warning started", L:State() == "Warning")
	check("the countdown itself is never extended", #run(P.WarningSeconds - 1, true) == 0 and L:State() == "Warning")
	local ev = run(30, true) -- countdown has now ended but a relic is active
	check("an active relic holds the evacuation open", #ev == 0 and L:State() == "Warning" and L:IsHolding(t))
	local ev2 = run(P.RelicHoldSeconds + 5, true)
	check("the hold is bounded: the evacuation starts anyway", ev2[1] == "Evacuate" and L:State() == "Evacuating")
	check("the hold can not exceed the configured limit", (t - (P.IntervalMinutes * 60 + P.WarningSeconds)) <= P.RelicHoldSeconds + 40)
	local L2 = MineLifecycle.new(P, 0)
	local t2 = 0
	for _ = 1, P.IntervalMinutes * 60 + P.WarningSeconds + 1 do t2 += 1; L2:Update(t2, 0, 2, false) end
	check("no active relic: no hold, evacuation right at the deadline", L2:State() == "Evacuating")
end

print(("relic: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("tests failed") end
