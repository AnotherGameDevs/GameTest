# Mine reset lifecycle ("Fresh Dig") — supersedes MINE_SHIFT.md's refresh section

## What existed before this pass (inspected)
* **Trigger:** >= 55% of ALL cells dug, or >= 70% of the Ruins layer, or (age >= 60 min and >= 10% dug). Checked every 5 s.
* **Loot positions:** regenerated, but from `Config.Site.Seed + n * 7919` — a fixed sequence, so the n-th mine of every server
  was identical and predictable. The initial mine used the constant seed 1337.
* **Players/artifacts:** 45 s warning; waited up to 120 s for carriers inside the mine, then dropped their artifact; resting
  artifacts were moved to the Lost & Found pad **inside the deposit zone**; players were teleported to the spawn.
* **Missing:** an explicit lifecycle (no "stop accepting requests" phase), generation identity on requests, an owner-claimed recovery
  area outside the deposit zone, per-generation limits on important artifacts, server-state-driven UI for late joiners, elevator
  reset, cleanup of client effects, protection against overlapping/looping resets.

## Now (one system, extended in place: `MineShiftService` + pure `MineLifecycle` + `MineState`)
```
Active --(schedule | depletion)--> Warning (60 s) --> Evacuating (3 s) --> Regenerating --> Active (generation + 1)
```
**Triggers (`Config.Reset`, provisional playtest values):**
* scheduled: 20 minutes of ACTIVE time (the clock pauses while the server is empty);
* depletion: >= 70% of the *diggable* cells removed (diggable = layers the best tool among online players can break), **but never before
  the generation is 10 active minutes old**;
* a reset can only start from Active, so they cannot overlap; after a reset all timers restart and the new mine is fresh, so a
  permanently depleted mine still resets at most once per 10 min + warning (unit-tested). Clients cannot start, delay or repeat a reset.

**Warning (60 s):** a toast at the start and at 30 s; compact mine-status panel (top right) shows "MINE n% DUG - RESET IN m:ss", turning
into a red countdown in the final 10 s with a tick per second and a banner "RESET IN n - GET OUT NOW!"; the text names the ELEVATOR as the
way out. State is replicated as Workspace attributes (`MineState/MineEndsAt/MineResetAt/MineGeneration/MineDug`), so **late joiners see the
current state and countdown**. Camp activity (shop, selling, journal) is unaffected.

**Evacuating (deadline):** `MineState` stops accepting mining, dynamite, artifact pickup and place-down (all server-side). Then, in order:
1. `ArtifactService.RecoverForReset()`: every important artifact that is **carried by a player inside the mine, or resting anywhere inside
   the mine** is put down in the **ARTIFACT RECOVERY** area (a roped pad beside the entrance gate at `Config.Camp.RecoveryPosition`, ~35 studs
   from the receiving table, outside `DepositReach`). The record stays owned by its discoverer and is flagged `Recovered`. **Nothing is
   sold, deposited or added to a collection.** The owner is told. They must pick it up there (only the discoverer can) and carry it to the
   receiving table. Records are separate from the new mine's loot, which does not exist yet.
2. Players inside the excavation bounds (grid + exit shaft) are moved beside the recovery area — a safety evacuation; they keep everything
   they own except that carried artifacts were recovered as above. A second sweep runs after the pause.
**Regenerating:** `SiteService.Generate()`: old folder (cells, remnants, tells) destroyed, all per-cell tables cleared, **fresh loot seed**,
new `LootBoard` (new generation id), `ElevatorService.ResetToSurface()` (car at the surface, queue cleared, safe). The generation id is
stamped on the `DigSite` folder; `DigHit` carries it, so **a stale request from the old mine can never damage the new cells at the same
coordinates**; dynamite fuses remember their generation. Then `Active` (generation + 1) and "The mine has been reset" is announced. Clients drop
reveal models, block shake and remembered faces when `MineGeneration` changes.
**Failure handling:** an error during a reset is logged; the state machine is still driven to Active with a (re)generated mine.
## Verified offline (`tests/loot_reset_test.luau`) / Not verified (needs Studio, 2 players)
Verified: transition order, no overlap, requests refused from the deadline, new generation id, old-generation claims fail, min lifetime,
scheduled timing, empty-server pause, no reset loops, recovery never deposits/duplicates and needs an owner pickup. NOT verified: the
service in a live server (evacuation, models on the recovery pad, elevator reset, UI/audio, late-join display) — `docs/PLAYTEST_PLAN.md` #23-26.
