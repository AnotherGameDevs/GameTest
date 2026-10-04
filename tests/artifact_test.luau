-- Run: luau tests/artifact_test.luau   (pure logic; no Roblox needed)
-- Stubs the one Roblox service the registry uses so the real state machine can be exercised.
local Records = require("../src/server/Services/ArtifactRecords")

local passed, failed = 0, 0
local function check(name, cond)
	if cond then passed += 1 else failed += 1; print("FAIL: " .. name) end
end

local n = 0
local function newStore()
	return Records.new(function() n += 1; return "A" .. n end)
end
local P = { X = 0 }

-- Happy path: pick up, deposit exactly once
do
	local s = newStore()
	local r = s:Create("golden_scarab", 1400, 1, P)
	check("starts Dropped", r.State == "Dropped")
	check("pickup ok", s:Pickup(r.Id, 1))
	check("is Carried", r.State == "Carried" and s:CarriedBy(1) == r)
	local ok, v = s:Deposit(r.Id, 1)
	check("deposit ok", ok and v == 1400)
	local ok2, why2 = s:Deposit(r.Id, 1)
	check("second deposit rejected", not ok2 and why2 == "AlreadyDeposited")
	check("pickup after deposit rejected", not (s:Pickup(r.Id, 1)))
	check("not carrying anymore", s:CarriedBy(1) == nil)
end

-- Duplicate / simultaneous pickups
do
	local s = newStore()
	local r = s:Create("golden_scarab", 1400, 1, P)
	check("first pickup", s:Pickup(r.Id, 1))
	local ok, why = s:Pickup(r.Id, 1)
	check("second pickup rejected", not ok and why == "NotAvailable")
	local ok3, why3 = s:Pickup(r.Id, 2)
	check("other player rejected", not ok3)
end

-- Ownership: only the discoverer
do
	local s = newStore()
	local r = s:Create("fossil_claw", 900, 1, P)
	local ok, why = s:Pickup(r.Id, 2)
	check("non-owner cannot pick up", not ok and why == "NotOwner")
end

-- One artifact at a time
do
	local s = newStore()
	local a = s:Create("fossil_claw", 900, 1, P)
	local b = s:Create("golden_scarab", 1400, 1, P)
	check("pick a", s:Pickup(a.Id, 1))
	local ok, why = s:Pickup(b.Id, 1)
	check("cannot carry two", not ok and why == "AlreadyCarrying")
end

-- Place down then pick up again; no value paid, same identity
do
	local s = newStore()
	local r = s:Create("golden_scarab", 1400, 1, P)
	s:Pickup(r.Id, 1)
	check("place ok", s:Place(r.Id, 1, { X = 5 }))
	check("Dropped at new position", r.State == "Dropped" and r.Position.X == 5)
	check("same record id", s:Get(r.Id) == r)
	check("place when not carrying rejected", not (s:Place(r.Id, 1, P)))
	check("deposit while dropped rejected", not (s:Deposit(r.Id, 1)))
	check("pick up again", s:Pickup(r.Id, 1) and r.Transfers == 2)
	local ok, v = s:Deposit(r.Id, 1)
	check("deposited once after re-pickup", ok and v == 1400)
end

-- Wrong player cannot deposit/place someone else's carried artifact
do
	local s = newStore()
	local r = s:Create("golden_scarab", 1400, 1, P)
	s:Pickup(r.Id, 1)
	check("other player cannot deposit", not (s:Deposit(r.Id, 2)))
	check("other player cannot place", not (s:Place(r.Id, 2, P)))
end

-- Death / disconnect: forced drop, never awards, idempotent, recoverable by the owner
do
	local s = newStore()
	local r = s:Create("golden_scarab", 1400, 1, P)
	s:Pickup(r.Id, 1)
	check("forced drop", s:Drop(r.Id, { X = 9 }))
	check("dropped state", r.State == "Dropped" and r.Position.X == 9 and s:CarriedBy(1) == nil)
	check("drop is idempotent", not s:Drop(r.Id, P))
	check("owner can recover it", s:Pickup(r.Id, 1))
	check("still not deposited", r.State == "Carried")
end

-- Deposited artifacts are not affected by a later drop
do
	local s = newStore()
	local r = s:Create("golden_scarab", 1400, 1, P)
	s:Pickup(r.Id, 1); s:Deposit(r.Id, 1)
	check("drop after deposit is a no-op", not s:Drop(r.Id, P) and r.State == "Deposited")
end

-- Mine refresh: resting artifacts can be relocated; carried / deposited ones cannot
do
	local s = newStore()
	local r = s:Create("fossil_claw", 900, 1, P)
	local to = { X = 99 }
	check("relocate a resting artifact", s:Relocate(r.Id, to) and r.Position == to and r.State == "Dropped" and r.OwnerId == 1)
	check("Dropped() lists it", #s:Dropped() == 1)
	s:Pickup(r.Id, 1)
	check("cannot relocate a carried artifact", not s:Relocate(r.Id, P))
	check("carried artifacts are not in Dropped()", #s:Dropped() == 0)
	s:Deposit(r.Id, 1)
	check("cannot relocate a deposited artifact", not s:Relocate(r.Id, P))
	check("relocate of a missing id fails", not s:Relocate("nope", P))
end

print(("artifact tests: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("tests failed") end
