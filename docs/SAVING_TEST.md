# Testing saving without risking real profiles

> Read `docs/ISOLATED_TEST_EXPERIENCE.md` first: it explains which environments can save at all and gives the exact setup + rejoin test. Studio now flushes all profiles on Stop; unsaved sessions show "Test session — progress will not save".

## What protects real profiles (implemented; NOT yet observed in Studio)
* **Studio never touches the production store.** `DataService` opens `Config.Data.StudioStoreName` (`DigAndRun_STUDIO_TEST_v1`) when `RunService:IsStudio()`, and
  `Config.Data.StoreName` (`DigAndRun_PlayerData_v1`) only in published servers — even if *Studio Access to API Services* is enabled on the production place.
* **A profile we could not use is never saved over** (`SaveMode.Decide`, unit-tested over every combination of failures): lock held by another live server, read failure, or migration
  failure ⇒ the player gets a **memory-only** stand-in profile (`NoSave`, logged as `MEMORY-ONLY profile (<reason>)`) in Studio, or is **kicked with a clear message** in a published server.
  With no DataStore at all (unpublished place) the session is memory-only by design.
* **Production session lock is unchanged:** `UpdateAsync` claims `{JobId, At}`, refreshes it at least every 45 s, expires after 120 s, releases on leave/shutdown (`BindToClose` waits for every save, max 25 s).
* `DataService.SaveStatus(player)` returns `saving: loaded|new-player` or `memory-only: <reason>`; server Output prints it when each player loads.

## Safe test recipe (Studio, 1 player; ~5 minutes)
1. Publish the place to a **test/private place** you do not care about (or use a duplicate of the game) and enable **Game Settings → Security → Enable Studio Access to API Services** there only.
   Never enable it on the production place.
2. Press Play. Server Output must show `Studio session saving to the TEST store 'DigAndRun_STUDIO_TEST_v1' (new-player)`. If it says `MEMORY-ONLY (no-datastore)`, the place is unpublished or API access is off.
3. Mine, sell and buy something, press P → change a setting, open the journal. Stop Play (wait for Output "saved"/no errors), press Play again: cash, tools, equipped tool, settings, collection and tutorial progress must be restored.
4. **Failed-load check:** disable *Studio Access to API Services*, Play: Output must show `MEMORY-ONLY profile (no-datastore)` or `(read-failed)` and your progress from step 3 must be **untouched** after you re-enable access and Play again (the isolated test store, not the memory-only session, holds the data).
5. **Two-server lock check (optional, needs a published test place):** start a published test server, join, then join the same account from Studio against the same store is impossible (Studio uses the test store); instead join the published place from two devices/instances: the second must be kicked with "still open on another server" until the first leaves or 120 s pass.
6. Resetting test data: Studio → Game Explorer is not enough; use the Creator Hub's Data Stores manager for the TEST store and delete the key `Player_<UserId>`. **Never** do this to `DigAndRun_PlayerData_v1`.

## Not verified
Everything above that touches a real DataStore (UpdateAsync retries, lock refresh, BindToClose timing, kick messages) — see `docs/STUDIO_INTEGRATION_CHECKLIST.md` B.
