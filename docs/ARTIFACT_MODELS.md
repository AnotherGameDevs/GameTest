# Artifact models (one source for reveal, carry, world, journal, shelf)

> **Update:** the Pottery Shard, Cut Gemstone, Fossil Fragment, Clay Figurine, Fossil Claw, Golden Scarab and Sun Pharaoh Mask below are the
> primitive-part FALLBACK and are **UNFINISHED** (their silhouettes need meshes). Mesh files exist but are not imported: see `docs/ARTIFACT_MESHES.md`.
> Old Coin, Bronze Ring, Ancient Necklace and Ruin Tablet remain primitive final art (subject to Studio review).

`shared/TreasureModels.luau` builds every artifact from part specs. Reveals (`EffectsController`), world pickups and carried tools
(`ArtifactService`), the first-person view (`ViewmodelController`), journal icons (`CollectionUI`) and shelf displays (`CampShelf`)
all call it; displays only scale (`BuildDisplay`: largest side = common size) and pose (`DisplayRotation`). Values/ids/ownership untouched.
Rarity is shown by the reveal outline and light colour, never by the material; **no Neon is used anywhere** (gems are glass), reveal
highlight fill raised to 90–92% transparent and lights dimmed. See `docs/images/artifact_before_after.png` (schematic render of the part data).

| Artifact | Build | Materials / colours |
|----------|-------|---------------------|
| Old Coin | thin 2.3 disc, defined rim, face, raised 8-point sunburst | aged gold, dark gold rim |
| Bronze Ring | **open** band of 12 segments, thicker top bezel, raised diamond + patina inlay, shown tilted up -28° | bronze, darker bronze, verdigris patina |
| Clay Figurine | base, tapered two-block torso, belt, shoulders, neck, shaped head with nose/brow/eyes/mouth, hanging left arm, bent right arm, chipped base corner | terracotta, fired-clay chip |
| Fossil Fragment | irregular slab with 2 broken chunks + chips; 12-segment logarithmic ammonite spiral with ribs standing out of the face | cool slate vs bone |
| Ancient Necklace | 16 beads + links in a loop, drop links, bail, shaped gold setting with glass inset stone, on a slate stand with a cloth bust | aged gold, lapis glass, no glow |
| Pottery Shard | curved 9-segment vessel wall, separate outer/inner layers (visible thickness), uneven broken top edge, slanted ends, painted band + dots | terracotta outside, dark clay inside |
| Cut Gemstone | stepped brilliant cut, 8 glass layers, tilted +18° | muted blue glass |
| Ruin Tablet | sandstone slab, 4 border strips, 12 carved glyphs, chipped corner, crack | sandstone, slate chip |
| Fossil Claw (Epic) | 6 tapering arc segments with knuckle ridges and dark tip on a rock base | bone / dark bone |
| Golden Scarab (Epic) | ridged shell, head, six legs, lapis eyes, teal glass gem | aged gold, glass |
| Sun Pharaoh Mask (Legendary) | face, headdress, striped sides, inlaid eyes with pupils, nose, mouth, beard, crown gem | aged gold, lapis, cream |

Display: every artifact fitted to 1.8 studs on a 0.6-high pedestal on a 1.0-high base (consistent scale), posed toward the viewer, name
plate on the shelf **front** (scaled, 2-line, size-capped so long names fit), pedestal bare; heading is the single modest sign
"<display name>'s Collection". "Only you see this" now lives in the journal header.

## Verified offline (`tests/artifact_models_test.luau`, 100+ checks)
dedicated model per treasure; no Neon; each model is one connected piece (no floating parts); size 1.8–4.2; display fit; ring opening is
clear; coin rim/face/emblem; figurine anatomy + terracotta colours; fossil spiral grows outward, bone ≫ rock, no concentric discs;
necklace beads/links/pendant/stand; shard two-tone, curved, uneven; carried artifacts still leave the crosshair clear (fitted per artifact).
## MESH NOTES — unfinished where parts cannot do it cleanly (nothing was uploaded; no meshes shipped)
* Pottery shard and fossil are the weakest read: curvature is faceted blocks. A sculpted mesh would be better.
* Figurine head/limbs, scarab shell and legs, and the mask's face curvature would also benefit from meshes.
* Necklace beads are low-poly spheres; links are blocks. A torus mesh would make a better ring and links.
Roblox Studio is needed to model/upload meshes; nothing here pretends otherwise. The renders are NOT in-engine screenshots.
