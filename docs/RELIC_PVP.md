# Server relic: contested carry-home PvP

**Status: AWAITING MULTIPLAYER VALIDATION. Implemented and unit-tested offline; never run in Roblox Studio or with two players. Incomplete.** Combat values are NOT tuned from geometry estimates; they change only with playtest recordings/results (run sheet: `docs/RELIC_PLAYTEST.md`). This supersedes the earlier
"no stealing" rule for the designated server relic only; ordinary loot and personal important artifacts are unchanged.

## Three explicit artifact types (`Defs.KindOf`)
| Type | Flag | Rules |
|------|------|-------|
| Ordinary | none | backpack and selling |
| Personal important | `RequiresCarry` | claimed to the discoverer, carry-home, no PvP (see ARTIFACT_RECOVERY.md) |
| Server relic | `Relic = true` | contested carry-home PvP (this doc). Currently only the **Sun Pharaoh Mask**; rarity/value never make a relic |
`Config.Loot.ImportantLimits.sun_mask = 1` (one buried per generation) and `RelicService` allows **one active event per server**
(a second discovery falls back to the personal flow).

## Event states (`RelicEvent`, pure)  Hidden → Discovered → Carried ⇄ Dropped → Secured | Expired
* **Hidden:** just loot in a cell. Unlike other artifacts the relic shows **no tell and no remnant** (`MineStyle.Detail`), no instance, no
  attribute, no coordinates exist before its block breaks.
* **Discovered:** announcement to everyone on the server ("CONTESTED RELIC! <name> uncovered the <relic>. Carry it to camp. The carrier can be
  attacked."), a marker on the relic, the HUD panel. After the reveal delay the physical relic + pickup prompt appear.
* **Carried:** held as a visible tool. The carrier is under every personal-artifact restriction because `CarryRegistry.IsCarrying` includes the
  relic: no mining, no dynamite, no tool switching/equip, no To Camp (server-enforced, same gates as before). They can walk, jump, use the
  elevator and place it down. HUD shows control + instructions; a "DELIVER HERE" marker points at the receiving table.
* **Dropped:** unclaimed, same event id; anyone eligible can take it. **Secured / Expired:** terminal; every later pickup, attack or deposit fails.

## Combat (dedicated, bounded) — `RelicRules`, `RelicService`
* Action: `RelicAttack` remote, key **F** (`Bindings.RelicStrike`) or the STRIKE/SHOVE button (visible only while a carried relic exists and
  you are outside the safe zone). Mining clicks never attack.
* **Strike** (anyone not carrying): validated on the server — event state Carried, both alive, attacker not carrying, neither in the safe zone,
  cooldown, range, **line of sight** (a ray from attacker to carrier that anything solid blocks: cells, walls, structures). A hit removes
  `ControlPerHit` from the carrier's **relic-control meter**; at 0 the relic drops. Tool stats play no part.
* **Shove** (the carrier presses the same action): pushes the nearest player who struck at the carrier within `ShoveEngageSeconds` (so unrelated players are never
  affected), with cooldown, range and LOS checks. No damage.
* **Knockback** is computed by the server and applied once by the target's own client (`RelicFx "Knock"`), clamped on both ends
  (`MaxKnockbackH`, `MaxKnockbackUp`), never stacked (the cooldown gates it). No money/equipment/collection loss anywhere.
* **Pickup protection:** a new carrier has full control and `PickupProtection` seconds of immunity (3 s), too short to cover an escape.
* Visible feedback: bursts, a brief red flash on the target, a procedural arm swing (no animation assets), HUD meter.

## Dropping and recovery
Death, reset character and disconnect drop the relic at a supported, clear, recoverable spot near the carrier's last safe position — **never in the
safe zone, never banked, never exclusive**. Place-down needs a supported clear spot within `PlaceReach`, a clear line from the carrier (no placing through
walls), not in the safe zone, and never on the elevator car. A dropped relic that falls below `UnreachableBelowY`, leaves the map or sits in the safe zone is
returned to the **recovery point** (`Config.Relic.RecoveryPoint`, on the entrance boardwalk, inside the contested area).

## Camp safety and deposit
* Safe zone: camp floor from `SafeBoundaryZ` (64) southward. A gold stripe and two SAFE ZONE signs mark the line. PvP and control loss stop inside.
* The receiving table (existing station, z = 73) is 9 studs inside the boundary; the elevator exit (z ≈ 56–64) is outside it, so pursuit continues there.
* Entering the safe zone awards nothing. The carrier has `CampGraceSeconds` (20) to deposit at the table; otherwise the relic returns to the recovery point.
* Deposit (only the carrier, within `DepositReach`, once): cash = the relic's `Value` (3,500), `RelicsExtracted`, collection entry (+set completion) for the
  depositor, announcement "<name> secured the <relic>!", table display, all indicators removed, shovel restored.

## Reset integration (`MineLifecycle` hold, `MineShiftService`)
When the reset countdown ends and a relic event is active the evacuation is **held for at most `Config.Reset.RelicHoldSeconds` (90 s)**; everyone is told.
Then the event **expires with no reward before anyone is evacuated** (relic and carried tool removed, "expired with the mine reset" announced). The relic is never moved
into camp, so a reset cannot make delivery trivial. Pickups are also refused once the mine stops accepting requests.

## Configurable values (`Config.Relic`, provisional)
MaxControl 100 · ControlPerHit 25 · AttackRange 7 · AttackCooldown 1.0 · StrikeKnockback 9 · ShoveRange 7 · ShoveCooldown 4.0 · ShoveKnockback 20 ·
ShoveEngageSeconds 12 · MaxKnockbackH 24 / Up 7 · PickupProtection 3.0 · PickupReach 10 (+ PickupTolerance 1.5) · PlaceReach 8 · SafeBoundaryZ 64 · CampGraceSeconds 20 ·
RecoveryPoint (0,0,53) · UnreachableBelowY -90 · Reset.RelicHoldSeconds 90. Rate limits: RelicAttack 6/2 s, RelicPickup 4/3 s, RelicPlace 3/3 s.

## Verified offline (`tests/relic_test.luau`, 66 checks of behaviour)
type separation, no hint of an undiscovered relic, first-pickup-wins, ownership transfer, protection, control meter and drop, strike/shove validation (range,
LOS flag, cooldown, event state, safe zone, self, unrelated), bounded knockback, safe-zone/grace/stalling, deposit exactly once and only by the carrier,
expiry + stale requests, bounded reset hold. **NOT verified (needs Studio, 2+ players):** everything that touches the engine — see PLAYTEST_PLAN #28-40.

## Review fixes (desk review, still unverified in engine)
* Place-down + instant re-grab no longer refills the control meter: the player who dropped it cannot take it back for `RegrabLockout` (5 s).
* Pickup now needs line of sight, so a relic can not be taken through walls. **Interaction-consistency fix (not balance):** the prompt distance and the server distance are the same value (`PickupReach` 10 studs); the server adds only `PickupTolerance` 1.5 for latency.
* The safe-zone grace is cumulative (stepping out only drains it at half speed), so zig-zagging at the line can not stall forever.
* A rejected hit (pickup protection) no longer spends the attacker's cooldown; no relic event can start while the mine is shutting down for a reset.

## Validation round 2 (code changes, still unverified in engine)
* Attack/pickup line of sight now ignores **every** player's character (no accidental body-blocking by a third player), ignores non-collidable
  (cosmetic) parts and our own prop folders, and is blocked only by collidable world geometry. Range is still validated for the intended target only.
* A per-player `RequestGap` (0.25 s) applies to every attack request, accepted or rejected; rejected hits still do not spend the gameplay cooldown, and
  cosmetic effects are sent only for applied hits. The run sheet is `docs/RELIC_PLAYTEST.md` (tests 28-38 NOT RUN).

## Known unresolved issues / risks
* Line-of-sight uses one ray between torsos; corners and thin geometry may over/under-block. Needs playtesting.
* Knockback is applied client-side; a modified client can ignore it (acceptable: it only affects themselves).
* Control/cooldown values are guesses; the PvP loop may be too easy/hard to defend. A single-relic event may feel dead on small servers.
* The relic marker is `AlwaysOnTop` by design (discovered relic position is public); tune size/opacity in play.
* No dedicated sound assets or animation assets; arm swing is procedural and may look odd on non-R15 rigs.
* The relic still counts toward `RelicsExtracted` and the "artifact" onboarding step.
