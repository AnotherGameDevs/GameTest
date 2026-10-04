# DIG & RUN! — completion checklist (working document)

**Engine-verified features: NONE.** Nothing in this project has ever been run in Roblox Studio or on a live server (this environment has no
Studio). The columns below keep three things apart: *Implemented* (code exists), *Offline-verified* (unit tests / type-check / desk review) and
*Engine-verified* (observed in Studio). Every row's Engine column is ❌ until you send playtest results. In-engine tests: **`docs/STUDIO_INTEGRATION_CHECKLIST.md` (start here)**, `docs/PLAYTEST_PLAN.md`,
`docs/RELIC_PLAYTEST.md`. Pre-flight without Studio: `python3 tools/preflight.py`.

## Audit summary (Stage 1)
Found at the start of this pass: complete server-authoritative loop, 8-tier tools, carry-to-camp artifacts, elevator,
settings/pause menu, rebuilt camp. **Missing:** mine replenishment, a mine deep enough for tier 7–8, collection journal,
camp display, set completion, onboarding hints, release hardening. **Fake/unfinished:** shop "Utility" and "Cosmetics"
tabs (COMING SOON placeholders), floating signs (receiving, elevator), collidable invisible spawn pad, objective text
overlapping HUD on narrow windows, shop not scale-to-fit, MetricsService printing in production, no shop proximity check.

## Requirement map
| # | Requirement | Implemented | Offline-verified | Engine-verified | Notes |
|---|-------------|:---:|:---:|:---:|-------|
| S2 | Playable loop (spawn→dig→sell→buy→improve), hold-to-mine, crosshair/highlight/hit agree, feedback | ✅ | partly (unit/desk) | ❌ | TOO FAR / TOO HARD labels; server cooldowns |
| S3 | Tool assembly (one spec → held/FP/preview), FP camera, settings, menu, InputMode | ✅ | ✅ assembly (139 checks) | ❌ | mouse BASE constant is an estimate |
| S4 | 8 tiers + 5 backpacks, previews, compare, inspect, no placeholder tabs | ✅ | model only (`economy_sim`) | ❌ | prices provisional; shop render skips unchanged state |
| S5 | Deeper layered mine, layer gating, mine variation, buried remnants, discovery pockets | ✅ | ✅ (mine_style) | ❌ | `MINE_DETAIL.md` |
| S5b | Mine reset lifecycle + recovery area + generation ids | ✅ | ✅ (loot_reset) | ❌ | `MINE_RESET.md` |
| S5c | Hidden randomized loot, per-generation limits, real-artifact tells | ✅ | ✅ | ❌ | `LOOT.md` |
| S6 | Personal important artifacts: carry/place/deposit/recovery | ✅ | ✅ (artifact tests) | ❌ | `ARTIFACT_RECOVERY.md` |
| S6b | Artifact models | 4 final-pending-review, **7 UNFINISHED (meshes generated, not imported)** | structure only | ❌ | blocked on Studio import: `ARTIFACT_MESHES.md` |
| S6c | **Server relic contested PvP** | ✅ | ✅ (relic, 69 checks) | ❌ **AWAITING MULTIPLAYER VALIDATION** | `RELIC_PVP.md`; run sheet `RELIC_PLAYTEST.md`; incomplete |
| S7 | Collection journal, camp shelf, set completion | ✅ | ✅ (spec logic) | ❌ | client-only shelf |
| S8 | World: camp spacing, no sand overlap, recovery pad, safe-zone line, signs | ✅ | ✅ layout tests + runtime `WorldAudit` | ❌ | |
| S9 | Onboarding (empty-outline bug fixed), UI tokens, scale-to-fit, audio | ✅ | ✅ guide logic | ❌ | audio = built-in placeholder sounds |
| S10 | Saving: UpdateAsync + session lock, migrations v1→v3, corrupted-save repair, failed-load kick | ✅ | ✅ (saving tests) | ❌ | never run against a real DataStore |
| S10b | Two-player / performance | — | — | ❌ blocked | needs Studio |
| S11 | Release materials | ✅ drafted | — | — | publish checklist is secondhand |

Dependencies: S5 (depth) → elevator stops from layers; S7 needs data v3; relic (S6c) depends on carry gates (S6), reset (S5b) and the safe-zone line (S8).
Independent work does not wait for the relic playtest.
