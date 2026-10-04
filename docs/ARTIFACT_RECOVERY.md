# Important artifacts: carry home to secure

Definition: `Defs.Treasure[id].RequiresCarry = true` (currently the two Epic artifacts: Fossil Claw, Golden Scarab).
Configurable per artifact. Other finds behave exactly as before.

## Flow
1. **Discover** (server, `ArtifactService.Discover`): rarity reveal plays; a server-generated GUID record is created
   (state `Dropped`, owner = discoverer); after `Config.Artifacts.SpawnDelay` the physical model appears on a supported,
   clear spot (never inside remaining dirt). No backpack slot, no cash.
2. **Pick up** (labelled prompt, discoverer only, one at a time): shovel is stowed, the artifact becomes a held Tool
   (default Roblox tool pose) visible to everyone, non-colliding.
3. **Carrying:** server rejects digging and dynamite; tool switching, purchases that would re-equip, `RequestEquip`, and
   `ReturnToCamp` are all gated on the same registry. Walking, jumping and the ladder still work.
4. **Place down** (button or X): server finds a supported, clear, reachable spot within 8 studs; if none, you keep carrying.
5. **Deposit** (prompt at the receiving table): pays the existing value exactly once, writes the collection entry, restores
   the shovel, shows the artifact on the table for a few seconds.

## Atomicity
`ArtifactRecords` is a pure state machine (`Dropped -> Carried -> Deposited`). Every transition is one synchronous
check-and-set, so duplicate or simultaneous requests cannot both succeed. Covered by `tests/artifact_test.luau`.

## Death, respawn, disconnect (implemented policy)
* The artifact is dropped at the carrier's last supported position (sampled twice a second), else where it was found,
  else on the camp **Lost & Found** pad. It stays claimed by its discoverer.
* If the discoverer rejoins **the same server**, they can pick it up again.
* **Records are server memory only.** If the server closes, an unbanked artifact is lost. There is **no cross-session
  recovery**, and nothing about artifacts is saved, so loading a saved character can never count one as deposited.
* Dying never awards or secures an artifact.

## Known unresolved cases
* If the discoverer never returns, nobody else can recover that artifact during the session (claim is exclusive in v1).
* An artifact dropped in a place that later becomes unreachable is only recoverable by digging to it (or by ladder).
* The held pose is Roblox's default tool pose, not a custom two-handed animation.

## Physical exit
A ladder shaft outside the grid on the camp (south) edge, X -32..-20, full depth, with scaffold-supported landings in
soil, clay, stone and ruins. The grid cells on its north wall are instanced from the start, so players dig sideways into
it at any depth. EXIT TO CAMP signs use SurfaceGuis (not visible through walls). Ladder exits onto the camp floor next to
the receiving table.
