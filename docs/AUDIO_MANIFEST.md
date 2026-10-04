# Audio replacement manifest

**Status: every cue is a Roblox built-in placeholder (`rbxasset://sounds/...`). No custom or uploaded audio exists. No sound ids were guessed or inserted.**
Their licensing/suitability for a released game is unverified by me (they ship with the Roblox client; confirm Roblox's terms for built-in assets before release),
so replace them with audio you own or have a licence for. Where each cue is triggered is from `AudioController.luau` and its callers.

## Cue list
| Cue (`Audio.Sounds` key) | Played when | Current placeholder (id / pitch / volume) | Intended sound | Asset needed |
|---|---|---|---|---|
| `Impact` | each pickaxe/shovel hit on a block (pitch/volume per tool from `ToolFx` profiles: dry starter, sharp improved, heavy reinforced, ...); relic strike | `rbxasset://sounds/action_jump_land.mp3` · 0.8× · 0.8 | dull thud of metal on packed earth; slight variation by layer | 3-4 short (0.1-0.3 s) hit variations, mono |
| `Break` | a block breaks; dynamite blast layer; relic hit/shove effect | `rbxasset://sounds/snap.mp3` · 0.7× · 0.9 | crumble / crack of earth or rock | 3 variations (soil, clay/stone, ruins), 0.3-0.5 s |
| `Tick` | drill tiers (Drill, Industrial Drill) on impact, at most every ~0.2 s | `rbxasset://sounds/switch.wav` (same as `UI`) · 1.6-1.9× · 0.3 | small mechanical click / ratchet | 1 short (0.1 s) |
| `Coin` | Common treasure reveal | `electronicpingshort.wav` · 1.3× · 0.5 | small metallic tink | 1 short (0.2 s) |
| `Reveal` (rarity ladder, `PlayReveal`) | Uncommon → Mythic reveals; pitch/notes rise with rarity | `electronicpingshort.wav` · 1.0× · 0.8, 1-4 stacked notes | discovery sparkle, increasingly rich per rarity | 4 stingers: Uncommon, Rare, Epic, Legendary (0.5-1.5 s) |
| `Sell` | auto-sale in the sell zone | `electronicpingshort.wav` · 3-note arpeggio 0.8/1.0/1.25 | coins pouring into a till | 1 (0.6-1 s) |
| `Buy` | purchase/equip confirmation, "good" notifications, return-to-camp | `electronicpingshort.wav` · 2 notes 1.2/1.6 | positive purchase chime | 1 (0.4 s) |
| `Deposit` | artifact / relic secured | `electronicpingshort.wav` · 4-note 0.7→1.4 | triumphant secure/appraisal sting | 1 (1-1.5 s) |
| `SetComplete` | collection set completed | `electronicpingshort.wav` · 4-note 1.0→2.0 | short fanfare | 1 (1.5-2 s) |
| `Error` | refused action, danger notices, **final-10-second reset ticks (pitched 1.4×)** | `rbxasset://sounds/uuhhh.mp3` · 1.2× · 0.4 | soft negative buzz; plus a **separate clean tick** for the reset countdown | 1 buzz (0.3 s) + 1 tick (0.1 s) |
| `UI` | every button/menu click | `rbxasset://sounds/switch.wav` · 1.0× · 0.5 | light UI click | 1 (0.1 s) |
Not present yet (add only if you want them): elevator motor loop, relic pickup/steal stinger, camp ambience. The code has no cue for them; adding one is a small `Audio.Sounds` entry plus a call site.

## Rules for the replacement assets
* Use ONLY audio you created, bought with a licence that permits use in a Roblox game, or took from the Creator Store/Toolbox where the listing says it is free for use in experiences. Keep the licence/receipt with the asset name.
* Do not copy sounds from other games or the web. Do not use an id you cannot attribute.
* Format/size: short, mono, normalised (peak about -3 dB), no clipping; keep each file small (< 150 KB). Provide dry sources; the game applies pitch variation and the master-volume setting.

## Steps that need YOUR Roblox account (I can not do these)
1. Creator Hub → **Creator Dashboard → Assets (or Develop → Audio)** → upload each file as **Audio** (secondhand note: audio uploads can require your account to be ID/age verified and go through moderation; check the current Creator Hub help).
2. Wait for moderation to approve; copy each asset id.
3. **Permissions:** an audio asset plays in an experience only if the experience's owner owns it (or it is a public asset with permission). If you uploaded as an individual, play it in a place you own; if the place belongs to a group, upload under that group or grant the experience permission in the asset's *Permissions* tab.
4. Put the ids in a JSON file `audio_ids.json`: `{ "Impact": "rbxassetid://123456789", "Break": "rbxassetid://..." }` and run `python3 tools/apply_audio_ids.py audio_ids.json --dry-run`, then without `--dry-run`.
   The script only accepts keys that exist in `Audio.Sounds` and ids that look like `rbxassetid://<digits>`; it changes only the `Id` field and leaves volume/pitch/notes alone.
5. Rebuild, open `Build/DigAndRun.rbxlx`, and listen to every cue (checklist section G). Tune `Volume`/`Pitch` in `AudioController.luau` by ear.

## Status table (updated only after you confirm)
| Cue | Replacement uploaded | Moderated/approved | Wired | Heard in Studio |
|---|---|---|---|---|
| all ten | no | no | no | no |
