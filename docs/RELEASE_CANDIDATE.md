# Release candidate notes

**Status: NOT release-ready.** The game is feature-complete against the agreed scope, but it has **never been run in Roblox
Studio or on a live server**. Everything below marked *verified* means unit tests, type-check and desk review only.

## What exists
Camp + spawn, first-person mining, eight tool tiers (+ layer gating), five backpacks, shop with 3D previews/inspect,
selling, carry-home artifacts (Epic/Legendary) with elevator and receiving table, collection journal + personal camp shelf +
set completion, mine refresh ("Fresh Dig"), first-time hints, settings menu, saved profiles with session locking and
migrations. See `docs/COMPLETION_CHECKLIST.md`.

## Draft game description (accurate to the build)
> Dig a block mine, find treasure, sell it, and upgrade your tools to reach deeper layers. Rare artifacts are too precious
> to put in a backpack: carry them back to camp yourself - but you can't dig or teleport while you do. Complete layer
> collections and show your favourite finds on your own camp shelf. Play with friends in one shared mine that refreshes when
> it runs dry.

## Supported devices
* **Recommendation: desktop (keyboard + mouse) only** for the first release. Reason: the first-person camera, hold-to-mine,
  Alt free-cursor and the shop were designed and desk-checked for mouse + keyboard.
* **Mobile / tablet:** partially wired (tap-to-dig, DIG and THROW buttons, touch wording in the hints), **never tested on a device**; the
  custom first-person camera is desktop-only. Do not tick Phone/Tablet in Experience Settings until tested.
* **Console / controller:** minimal (R2/A mine). Shop/journal/menu navigation with a gamepad is untested and probably
  unusable. Do not tick Console.
* **No device or window size has actually been tested.** Layout was checked by calculation only (menus scale to fit, top
  HUD is constrained by width).

## Icon / thumbnail brief (art not made)
Icon (square, min 512 x 512): a chunky shovel in front of a stepped block pit, gold-lit, teal accent, "DIG & RUN!" not
needed in the icon. Thumbnails (1920 x 1080): (1) first-person view of the shovel at a layered pit wall with a gold
treasure reveal; (2) camp with stall, appraisal and elevator tower; (3) a player carrying a golden scarab toward the
receiving table; (4) shop with the tool ladder. Use real in-game captures only; do **not** use Roblox logos or imply Roblox
endorsement.

## Roblox publication checklist (research summary, SECONDHAND)
Fetching `create.roblox.com` docs was blocked in this environment; these points come from search-result summaries and
**must be re-checked in the current Creator Hub before publishing**:
* Experience name, description, genre; **maturity & compliance questionnaire** required before an experience can be public.
* Icon (min 512x512 square) and thumbnails (1920x1080, 16:9; JPG/PNG/GIF/TGA/BMP).
* **Playable devices** (Studio > Experience Settings > Basic Info / Creator Hub): choose only tested devices (see above).
* **Assets:** every sound is currently one of Roblox's built-in `rbxasset://` placeholder sounds - replace with owned or
  licensed audio, or confirm the licensing terms of those built-ins. No uploaded images/meshes are used (all geometry is
  generated parts), no fonts beyond Roblox's own.
* **Data:** DataStore `DigAndRun_PlayerData_v1`. Publish, then test with *Studio Access to API Services* ON in a **separate
  test place** only; production place should have it OFF. Session locking is implemented (JobId lock, 120 s expiry).
* Private/friends-only first, then public after tests. No monetization in this build.
* Do not describe the game as officially associated with Roblox.

## Known limitations / blockers
1. **No Studio run, no screenshots, no multiplayer, no performance measurement** (blocker for a release call).
2. Prices/pacing are from an analytic model, not play data. Mouse sensitivity base (0.25 deg/px) is an estimate.
3. Audio = placeholder built-in sounds, events separated by pitch/note patterns only.
4. Mobile/console not supported (see above). No backpack is shown on the character.
5. Important artifacts exist only in server memory: a server shutdown loses an unbanked artifact (documented policy).
6. Artifact claim is exclusive to its discoverer in v1.
7. Fresh Dig is shared-server state; if the carrier of an artifact inside the mine delays it, the refresh waits up to 2 minutes.
8. Session locking has never run against a real DataStore; a crash leaves a profile locked up to 2 minutes (rejoin message).
9. `Config.Metrics` is off in published servers; telemetry (`AnalyticsService`) only logs, nothing is sent anywhere.

## Start and test
1. `rojo build default.project.json -o Build/DigAndRun.rbxlx` (or use the committed file), open in Studio, press Play.
2. Offline checks: `LUAU=/path/to/luau bash tests/run_all.sh` and the `luau-lsp analyze` command in `README.md`.
3. Work through `docs/PLAYTEST_PLAN.md` and fill in the Result column.
