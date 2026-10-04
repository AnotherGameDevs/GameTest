# Developer test mode

Status: implemented and unit-checked offline (`tests/dev_mode_test.luau`). **The panel, remotes and every world action are `not run` in Studio.**

## Who gets it (decided by the SERVER only)
| Environment | Panel available? |
|---|---|
| Studio (Play / Start / local server) | **Yes**, every player (a Studio server is yours alone). |
| Published server, `Config.Dev` left as shipped | **No** — `AllowedUserIds` and `TestPlaceIds` are empty, so nobody qualifies. |
| Published server, `game.PlaceId` in `Config.Dev.TestPlaceIds` **and** your UserId in `Config.Dev.AllowedUserIds` | Yes. |
| Your UserId is allowlisted but the place is not in `TestPlaceIds` (e.g. production) | **No** — so an allowlisted account can never reset or seed a public production mine. |

**Where you supply your ids** — `src/shared/Config.luau`, block `Config.Dev`:
```lua
Config.Dev = {
	AllowedUserIds = { 123456789 },  -- your Roblox UserId (roblox.com/users/<id>/profile)
	TestPlaceIds   = { 987654321 },  -- the PlaceId of your PRIVATE TEST experience (Creator Hub -> the place's id)
	...
}
```
Rebuild (`bash tools/build.sh`) or edit in Studio, then publish **to the test experience only**. I did not guess or fill either value. Never put the
production place's id in `TestPlaceIds`.

The client is never asked. `StateService` adds `Dev` to the snapshot only for authorised accounts; the panel is not even built for anyone else.
`DevService.handle` recomputes access from `RunService:IsStudio()`, `game.PlaceId` and `player.UserId` on **every** request, then validates the
action against a fixed whitelist, then checks permission (test mode on / world allowed), and only then runs it. A hand-fired `DevRequest` from an
ordinary player is ignored (one server warning per player). Preflight fails the build if that order changes, if anything else uses the remote, or if
a client script mentions the allowlist.

## Opening the panel
* Press **`\`** (backslash) or click the amber **DEV** button under the gear (top-right). Neither exists for ordinary players.
* While test mode is active a red **DEVELOPER TEST MODE — nothing is saved** bar is shown at the top of the screen at all times.
* The panel header states the session kind: *Temporary session* (no DataStore), *Isolated test store* (Studio test store), or *Normal play* (production store).

## Actions
Everything except Enter/Exit needs **Test Mode on** (press ENTER TEST MODE first).
| Action | What it does | Uses |
|---|---|---|
| Enter / Exit test mode | Starts / ends the overlay. Exit is refused while carrying an artifact. | `DataService.EnterTestMode` / `ExitTestMode` |
| Fresh test profile | Replaces the overlay with a default profile. Real profile untouched. | `ProfileOverlay.Fresh` |
| **Unlock all equipment** | Owns every tool and backpack (+ full dynamite). Shop and equip UI update through the normal state push. | `DevProfile` |
| Equip tool / backpack | Click any item (the equipped one is outlined teal). Tools are rebuilt on the character (refused while carrying). | `EquipmentService.Refresh` |
| Cash +1K / +10K / +100K / typed | Test cash (max `Config.Dev.MaxCash`). | overlay only |
| Unlock collection + shelf | All entries, shelf filled to its slot count. | `CollectionSpec` |
| Spawn selected artifact | Pick a row, then act. Ordinary → test backpack + reveal. Personal → real world artifact beside you (carry rules apply). Relic → starts the real relic event. | `InventoryService`, `ArtifactService.Discover`, `RelicService.Discover` |
| Reveal only | Plays the normal reveal for the selected artifact; adds nothing. | `TreasureFound` remote |
| Start server relic event | The same call real discovery makes, 6 studs in front of you. | `RelicService.Discover` |
| Move to layer | Camp spawn or the existing elevator landing of Soil/Clay/Stone/Ruins. Refused while carrying. | existing parts |
| Request mine reset | Starts the **normal** Warning → Evacuate → Regenerate lifecycle early with a `Config.Dev.ResetWarningSeconds` (15 s) countdown; refused if a reset is already in flight. | `MineLifecycle:RequestManual`, `MineShiftService.RequestReset` |

World actions (spawn artifact, relic, mine reset) additionally require `access.World` (Studio, or an allowlisted account on a listed test place).

## Isolation
* `DataService` keeps **two tables per player**: the real profile (parked in `Normal`) and the live table every service uses (`Data`). On Enter the live table becomes a copy; on Exit it is restored in place (same table object, so nothing holding a reference breaks).
* Autosave, leave-save and shutdown always snapshot the **real** profile (`ProfileOverlay.SaveSource`); `MarkDirty` is a no-op while the overlay is active; the DataStore name, session lock and load rules are untouched and nothing is wiped.
* The test overlay includes granted cash, equipment, collection, shelf, tutorial progress and stats.
* Panel-created world artifacts and relic events are remembered (`DevScenario`). If anyone **not** in test mode deposits one, it is consumed but pays nothing.
* Pickup distance, carry rules, deposit, relic combat and mine-reset rules run unchanged; test mode only helps you reach the scenario. Reset depletion is computed from online players' (overlay) tools, as for any player.
* Developer helper modules contain no DataStore calls (preflight-enforced).

## Checks performed (offline only)
`tests/dev_mode_test.luau` (104 checks): access matrix incl. malformed ids and empty config; request validation (unknown actions, junk arguments, cash clamping, ranges); permission matrix; profile operations; overlay vs a **fake DataStore** (stored profile identical after overlay edits, autosave, leave, fresh profile and exit); manual reset through the lifecycle machine; test-artifact markers.
`tools/preflight.py`: server-authorisation order, remote use, client does not decide access, no DataStore in dev helpers, `DataService.Save` snapshots the real profile, deposit guards present.

## Studio checks (all `not run`)
1. Studio Play: DEV button and `\` work; indicator appears after ENTER; Exit restores cash/tools exactly (compare with the HUD before).
2. Unlock all: shop shows every tool/pack owned; equip each tool and see its model and effects change; backpack capacity changes.
3. Cash/collection/shelf: journal and camp shelf show the unlocked entries; stop Play, replay (isolated test store): none of it persisted; real cash unchanged.
4. Spawn each artifact kind; ordinary → backpack; personal → pick up, carry, deposit at the table; relic → event HUD/markers.
5. Two players: one enters test mode, starts the relic, the other (not in test mode) deposits it → no reward.
6. Request mine reset: countdown, evacuation, new mine, progression unchanged.
7. Published private test experience with your ids set: panel for you; a second account: no panel and nothing happens if it fires the remote.
8. Published place with empty `Config.Dev`: no panel for anyone.
