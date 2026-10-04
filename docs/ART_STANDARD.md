# Chunky dig-site art standard (tools and artifacts)

Parts only (no meshes/textures), built with `ModelKit`. Goals: functional, physically constructed, readable at a glance,
bigger-but-not-huge as tiers rise.

* **Silhouette first.** Long axis along Y: grip at -Y, working end at +Y. Overall length 6-7.5 studs, max width ~2.6.
  Each tier must be recognisable in silhouette alone (grip shape, blade/head shape, body mass).
* **Palette.** 3 main colours + 1 accent per model, from the project palette. Wood `B07A45`/`6B4A2E`, steel
  `A9B7C6`/`6F7F91`, gunmetal `4A5560`, safety amber `E8A33D`, safety orange `E5602B`, rubber `23262B`.
* **Soft/beveled.** Round ends with cylinders and balls; inset lighter "bevel" panels on blades; no thin spikes.
  Minimum part dimension 0.2 studs.
* **Construction details that read:** ferrules/sockets, bolts (balls), straps/bands, ribs, grips. Every detail is
  something that would physically exist on the object.
* **No implied mechanics** on tiers 7-8: no spirals, spinning parts, cables, batteries, hoses.
* **Three families** (change the construction between families, keep it within):

| Family | Tiers | Shaft/body | Grip | Blade/head |
|--------|-------|-----------|------|------------|
| Hand tools | 1-3 | wood (rusty -> lacquered -> thicker) | T-bar -> closed D-grip | hand-forged spade; rusty -> steel -> big scoop with lips |
| Reinforced excavation | 4-6 | amber fibreglass-style shaft / amber housing | rubber D-grip, rubber cross-grip, hand sleeve | gunmetal blades with welded ribs; chisel with bolted edge; stepped boring head (no helix) |
| Industrial | 7-8 | gunmetal housing + orange panels (7); bundled charges + steel bands (8) | guarded two-grip assembly | bolted replaceable cutting edge + teeth; (dynamite: label wrap, fuse) |

* **Appearance is separate from stats.** `Defs.Tools[id].Appearance` -> `Appearances.List` -> `ToolModels` builder. A skin
  (`Appearances.Skins`, `data.EquippedCosmetics.ToolSkin`) overrides appearance only.
* **One spec, two uses.** The held Tool (server) and the shop preview (client) are built from the same part list.
* **First person.** Tools draw at `FPScale` (0.4-0.5) and fade only while covering the crosshair area.

Artifacts (`TreasureModels`): Golden Scarab (epic), Cut Gemstone (rare), Ancient Necklace (rare) are polished; the rest
use generic coin/ring/gem/block stand-ins. The reveal animation drives any of them via pivot/scale.
