# Artifact meshes: package, import steps, status

**Status: GENERATED, NOT IMPORTED. Imported meshes: 0 of 7 artifacts.** In the game the seven artifacts below still use their primitive-part
fallback and are UNFINISHED (`TreasureModels.Status(id) == "unfinished"`, unit-tested). Nothing in this document has been seen in Roblox Studio.
Adding more primitive parts is not claimed to meet the silhouette requirement.

## Exact limitation
This environment can run Python but has no Roblox Studio and no authenticated upload route, so I could author the geometry but could not import,
upload or look at it in the engine. The previews (`docs/images/artifact_meshes_preview.png`) are back-face-culled renders of the OBJ files, not engine images.

## The package
`assets/artifact_meshes/` (also zipped as `assets/artifact_meshes.zip`, 7 folders, 22 OBJ files, `manifest.json`, `MeshAssets.template.lua`). Regenerate with
`python3 tools/make_artifact_meshes.py`; preview with `python3 tools/preview_meshes.py out.png`. All meshes are procedurally generated for this project
(no third-party geometry).

**Common to every file:** units = studs (1 OBJ unit = 1 stud); **up = +Y, front (the face a viewer sees on a shelf / the face that points out of the
wall in a buried tell) = +Z**; flat-shaded; **pivot = the bounding-box centre of the WHOLE object, identical for every colour group of an object**
(so groups line up whether Studio keeps the authored origin or recentres each mesh to its own bounding box *only if it uses the same rule for all*; see step 4).
Scale: import at **scale 1.0**; the MeshPart's Size in Properties must equal the "bounds of the whole object" for the group's own extent (each group is
smaller than or equal to the object bounds).

| Artifact (treasure id) | File (assets/artifact_meshes/…) | Colour group | Triangles | Bounds of the whole object (studs, X×Y×Z) | Colour / material to apply | Imported? |
|---|---|---|---:|---|---|---|
| Pottery Shard (`pottery_shard`) | `pottery_shard/outer.obj` | outer | 168 | 2.57 × 2.546 × 0.882 | `#B5683F` SmoothPlastic | **NO** |
| Pottery Shard (`pottery_shard`) | `pottery_shard/inner.obj` | inner | 168 | 2.57 × 2.546 × 0.882 | `#5B3A26` SmoothPlastic | **NO** |
| Pottery Shard (`pottery_shard`) | `pottery_shard/edge.obj` | edge | 80 | 2.57 × 2.546 × 0.882 | `#C98A5E` SmoothPlastic | **NO** |
| Pottery Shard (`pottery_shard`) | `pottery_shard/band.obj` | band | 20 | 2.57 × 2.546 × 0.882 | `#7A3322` SmoothPlastic | **NO** |
| Cut Gemstone (`cut_gemstone`) | `cut_gemstone/gem.obj` | gem | 72 | 2.0 × 1.65 × 2.0 | `#5FA3BF` Glass | **NO** |
| Cut Gemstone (`cut_gemstone`) | `cut_gemstone/table.obj` | table | 8 | 2.0 × 1.65 × 2.0 | `#B7DCE8` Glass | **NO** |
| Fossil Fragment (`fossil_fragment`) | `fossil_fragment/rock.obj` | rock | 32 | 2.608 × 2.096 × 0.864 | `#6E7580` Slate | **NO** |
| Fossil Fragment (`fossil_fragment`) | `fossil_fragment/shell.obj` | shell | 528 | 2.608 × 2.096 × 0.864 | `#D8CDB0` SmoothPlastic | **NO** |
| Clay Figurine (`clay_figurine`) | `clay_figurine/dark.obj` | dark | 132 | 1.776 × 3.39 × 1.112 | `#7A4228` SmoothPlastic | **NO** |
| Clay Figurine (`clay_figurine`) | `clay_figurine/clay.obj` | clay | 546 | 1.776 × 3.39 × 1.112 | `#B5683F` SmoothPlastic | **NO** |
| Clay Figurine (`clay_figurine`) | `clay_figurine/chip.obj` | chip | 8 | 1.776 × 3.39 × 1.112 | `#D49A6A` SmoothPlastic | **NO** |
| Fossil Claw (`fossil_claw`) | `fossil_claw/bone.obj` | bone | 296 | 2.724 × 3.158 × 1.366 | `#D8CDB0` SmoothPlastic | **NO** |
| Fossil Claw (`fossil_claw`) | `fossil_claw/tip.obj` | tip | 56 | 2.724 × 3.158 × 1.366 | `#5A4A33` SmoothPlastic | **NO** |
| Fossil Claw (`fossil_claw`) | `fossil_claw/rock.obj` | rock | 18 | 2.724 × 3.158 × 1.366 | `#6E7580` Slate | **NO** |
| Golden Scarab (`golden_scarab`) | `golden_scarab/shell.obj` | shell | 280 | 3.388 × 1.306 × 3.73 | `#C9A24B` Metal | **NO** |
| Golden Scarab (`golden_scarab`) | `golden_scarab/head.obj` | head | 64 | 3.388 × 1.306 × 3.73 | `#9A7A32` Metal | **NO** |
| Golden Scarab (`golden_scarab`) | `golden_scarab/inlay.obj` | inlay | 40 | 3.388 × 1.306 × 3.73 | `#3A72AE` Glass | **NO** |
| Golden Scarab (`golden_scarab`) | `golden_scarab/legs.obj` | legs | 216 | 3.388 × 1.306 × 3.73 | `#9A7A32` Metal | **NO** |
| Sun Pharaoh Mask (server relic) (`sun_mask`) | `sun_mask/gold.obj` | gold | 1316 | 2.8 × 3.5 × 1.282 | `#C9A24B` Metal | **NO** |
| Sun Pharaoh Mask (server relic) (`sun_mask`) | `sun_mask/inlay.obj` | inlay | 96 | 2.8 × 3.5 × 1.282 | `#E3D2B0` SmoothPlastic | **NO** |
| Sun Pharaoh Mask (server relic) (`sun_mask`) | `sun_mask/headdress.obj` | headdress | 36 | 2.8 × 3.5 × 1.282 | `#9A7A32` Metal | **NO** |
| Sun Pharaoh Mask (server relic) (`sun_mask`) | `sun_mask/stripe.obj` | stripe | 30 | 2.8 × 3.5 × 1.282 | `#3A72AE` SmoothPlastic | **NO** |

(`manifest.json` holds the same data plus per-group bounds; `MeshAssets.template.lua` is the Lua shape the game expects.)

## Import and replacement steps (to be done by you in Roblox Studio)
1. Open `Build/DigAndRun.rbxlx` (or any place you own). **Home → Asset Manager → Bulk Import** (or **Avatar → Import 3D**). Select all `.obj` files of ONE artifact folder
   (e.g. every file in `pottery_shard/`). In the importer set **Scale 1** and leave "recentre"/"pivot" at the default — then use the SAME settings for every artifact.
2. Import. Studio creates one MeshPart per OBJ and uploads each mesh to **your** account (Asset Manager → Meshes). Accept the upload fee/terms if prompted.
3. **Check in Properties** for each MeshPart: `Size` ≈ that group's extent from the manifest (if it is 10× or 0.1× too big, re-import with the other unit setting). Select the MeshPart,
   copy its **MeshId** (`rbxassetid://<digits>`).
4. **Check alignment:** drop all groups of one artifact at the same position (0,0,0). They must assemble into one object. If they do not (importer recentred each mesh separately),
   re-import with "keep original pivot", or tell me which importer option was used and I will re-export with a different convention.
5. Create `mesh_ids.json` next to the repo, one line per OBJ, key = `<artifact_id>/<group>` (e.g. `"pottery_shard/outer": "rbxassetid://123456789"`).
6. Run `python3 tools/apply_mesh_ids.py mesh_ids.json` (use `--dry-run` first). It refuses malformed ids and enables an artifact ONLY when ALL its groups are present (otherwise the artifact keeps
   its primitive fallback). It rewrites only the block between `MESH_ASSETS_BEGIN/END` in `src/shared/Config.luau`.
7. Rebuild (`rojo build default.project.json -o Build/DigAndRun.rbxlx`) and open the new file.
8. Inspect each mesh artifact in all five views — **reveal** (dig it up or `Relic.Discover`/`LootService` test), **carried** (first and third person), **buried tell** (0.7 studs out of the wall), **journal** icon, **camp shelf** —
   and fill the table in `docs/STUDIO_INTEGRATION_CHECKLIST.md` section G. Only then remove an artifact from `TreasureModels.MeshRequired`.

**Artifact IDs are preserved:** the keys of `Config.MeshAssets` are the existing treasure ids; `TreasureModels.Specs` returns the mesh set when configured and the primitive set otherwise, so reveals,
carrying (world + first person), the journal, the shelf and buried tells all switch together (unit-tested in `tests/artifact_models_test.luau`). Collection records, values and ownership are untouched.
**Generated vs imported:** the table above says NO for every file; this column and the "Imported meshes" count at the top are updated only after you confirm a successful import.

## Known weaknesses of the generated shapes (judge them in Studio)
The claw's rock base is a plain wedge; the scarab legs are thin and its shell long; the mask's face grid shows faceting; the pottery shard and fossil are first passes. They need an artist's eye in the engine.
