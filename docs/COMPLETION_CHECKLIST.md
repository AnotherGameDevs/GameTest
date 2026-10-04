# DIG & RUN! — completion checklist (working document)

Legend: ✅ implemented + verified offline · 🟡 implemented, needs Roblox Studio play-test · 🔧 in progress this pass ·
❌ missing · 💥 broken. **Nothing here has been run in Roblox Studio** (this environment has no Studio): "verified" means
unit tests, luau-lsp type-check and desk review only. See `docs/PLAYTEST_PLAN.md` for the exact in-engine tests.

## Audit summary (Stage 1)
Found at the start of this pass: complete server-authoritative loop, 8-tier tools, carry-to-camp artifacts, elevator,
settings/pause menu, rebuilt camp. **Missing:** mine replenishment, a mine deep enough for tier 7–8, collection journal,
camp display, set completion, onboarding hints, release hardening. **Fake/unfinished:** shop "Utility" and "Cosmetics"
tabs (COMING SOON placeholders), floating signs (receiving, elevator), collidable invisible spawn pad, objective text
overlapping HUD on narrow windows, shop not scale-to-fit, MetricsService printing in production, no shop proximity check.

## Requirement map

| # | Requirement | Status | Notes / dependency |
|---|-------------|--------|--------------------|
| S2 | Playable loop (spawn→dig→sell→buy→improve) | 🟡 | `GuideSpec` hints added; needs Studio loop run |
| S2 | Hold-to-mine, cooldowns, crosshair/highlight/hit agree | 🟡 | shared targeting, server cooldown |
| S2 | Full-backpack / invalid-target / too-far feedback | 🟡 | "TOO FAR" / "TOO HARD" label under the crosshair |
| S2 | Server-controlled damage/loot/currency/ownership | ✅ | DigService/Economy; no-duplicate-loot is a synchronous cell check |
| S3 | Tool assembly (one spec → held/FP/preview) | ✅ 🟡 | `tests/tool_assembly_test` (118 checks) |
| S3 | FP camera, sensitivity, settings, pause menu, InputMode | 🟡 | BASE mouse constant is an estimate |
| S4 | 8-tier tools + backpacks, previews, compare, inspect | 🟡 | prices re-checked vs. deeper mine (`tools/economy_sim.py`) |
| S4 | Remove placeholder tabs | ✅ | Utility/Cosmetics removed; backpack previews use real pack models |
| S5 | Mine depth/layers support progression | 🟡 | 24×24×20, four 5-row layers, toughness 24/42/72/110, layer gating by tool tier (`docs/MINE_SHIFT.md`) |
| S5 | Replenishment | 🟡 | `MineShiftService` (rule unit-tested; sequence needs Studio) |
| S6 | Artifact discovery, carry, place, deposit, recovery policy | ✅ 🟡 | `artifact_test` (+relocation cases) |
| S6 | Rarity reveals one visual language | 🟡 | EffectsController |
| S7 | Collection journal (J) | 🟡 | `CollectionSpec` (pure) + `CollectionUI` |
| S7 | Camp personal display + choice | 🟡 | client-side shelf, saved `Display` list |
| S7 | Set completion | 🟡 | per-layer sets, toast on completion |
| S8 | World: camp spacing, no sand overlap, signs | ✅ 🟡 | audit + `WorldAudit`; floating signs fixed this pass |
| S9 | Onboarding hints | 🟡 | `GuideSpec` + `GuideController` |
| S9 | UI unification, number formatting | 🟡 | `UIKit.Tokens`/`flatButton`/`fit`; shop/menu/journal scale-to-fit; HUD centre text constrained |
| S9 | Audio | 🟡 | **built-in Roblox placeholder sounds** – replacement needed before release |
| S10 | Persistence + migrations + failed-load safety | 🟡 | v3 migration (unit-tested); UpdateAsync + session lock; failed load kicks in production; BindToClose waits for all saves |
| S10 | Two-player / performance testing | ❌ (blocked) | needs Studio/server; see playtest plan |
| S11 | Release materials | ✅ (drafted) | `docs/RELEASE_CANDIDATE.md`, `docs/PLAYTEST_PLAN.md`; publish checklist is secondhand |

Dependencies: S5 (deeper mine) → elevator stops derive from layers → camp/elevator audit; S7 → needs data v3 (S10);
S9 guide needs S7 (collection step) and S5 (shift banner).
