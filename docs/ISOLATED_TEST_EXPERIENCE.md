# Isolated test experience and save persistence

Nothing here changes publication or account settings by itself — **you** perform the Creator Hub steps below.
Status of every result in this document: **not run** (no Roblox Studio / DataStore was available to the author).

## 1. Where progress is (and is not) saved

There is one save system (`DataService` → `ProfileStore`, key `Player_<UserId>`, session lock, autosave, leave-save, shutdown flush).
Whether it can write depends on the environment:

| Environment | DataStore | What happens | What the player/you see |
|---|---|---|---|
| Studio, **place never published** (local .rbxlx) | none | memory-only session; nothing survives Stop | Output: `NO DataStore…` ; HUD: **"Test session — progress will not save"** |
| Studio, published place, **API access OFF** | read/write fails | memory-only (`no-datastore` / `read-failed`); an existing profile is never overwritten | same notice |
| Studio, published **isolated test experience**, API access **ON** | `DigAndRun_STUDIO_TEST_v1` | real saves to the TEST store | Output: `Studio session saving to the TEST store…`; no notice; Settings (P) shows "Saving: on" |
| Published server (live) | `DigAndRun_PlayerData_v1` | real saves, session lock | no notice; failed load ⇒ kicked with a message rather than silently starting empty |

So if progress did not persist when you tested from an unpublished/local file, or with API access off, that is **by design and now visible**.
Which of these you hit is **unconfirmed**. A second, confirmed code cause was fixed: in Studio `BindToClose` used to return early, so a short
session that ended with Stop could lose its last changes; it now flushes every profile (max 25 s).

Saved: cash, owned tools/backpacks, equipped items, collection / secured discoveries, display choices, tutorial progress, settings.
Not saved as a reward: an unsecured, contested relic (it returns to the mine/camp rules). Mine reset never touches progression.

## 2. Create an isolated test experience (you do this)
1. Roblox Studio → open `DigAndRun_build_<id>.rbxlx` (id printed in Settings → "Build:" and in `Build/BUILD_INFO.txt`).
2. File → **Publish to Roblox As…** → *Create new experience* named e.g. `DIG & RUN — TEST (private)`. Keep it **private**; do not publish over your real game.
3. Creator Hub → that test experience → **Game Settings → Security** → enable **Enable Studio Access to API Services** → Save.
   Do this on the test experience only.
4. Reopen the place in Studio (so it is bound to the test experience). Press Play.
5. Server Output must contain, in order:
   * `Build 2026…` line from `Main.server`,
   * `[DataService] storage mode: studio-test (store 'DigAndRun_STUDIO_TEST_v1' …)`,
   * `[DataService] Studio session saving to the TEST store … (new-player)`.
   If you instead see `NO DataStore` or `MEMORY-ONLY`, the setup is not complete; the HUD will also show the test-session notice.

## 3. Rejoin test (report each as passed / failed / not run)
| # | Step | Expected | Result |
|---|---|---|---|
| 1 | Dig, sell, earn cash; note amount | cash shown | not run |
| 2 | Buy a tool/backpack and equip it | owned + equipped | not run |
| 3 | Find an ordinary artifact and secure/deposit a personal one (collection entry) | collection shows it | not run |
| 4 | Change a setting (P) | setting applied | not run |
| 5 | Stop Play; Output shows `saved … (final, lock released)` | no `Save failed` | not run |
| 6 | Play again | cash, tool, equipped, collection, setting, tutorial progress restored | not run |
| 7 | Trigger a mine reset (or wait) | mine regenerates; cash/tools/collection unchanged | not run |
| 8 | Also test: wait ≥ 45 s for an autosave line; leave and rejoin in a published test server | lines `autosave` then `final` | not run |

Diagnostics on the server: `storage mode`, `saved`, `Save failed (will retry)`, `LOAD FAILED`, `SESSION LOCK`, and a `shutdown summary` line with counts.
Player-facing UI never shows profile contents; only the test-session notice and Settings "Saving".
Offline serialization/fake-DataStore tests (`tests/saving_test.luau`) prove protocol logic only; they are **not** evidence that real DataStore saves work.

## 4. Resetting test data
Creator Hub → test experience → Data Stores manager → `DigAndRun_STUDIO_TEST_v1` → delete key `Player_<UserId>`. Never touch `DigAndRun_PlayerData_v1`.
