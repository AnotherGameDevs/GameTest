# Artifact meshes: what exists, what is unfinished, how to import

**Status: mesh files are GENERATED but NOT IMPORTED. In the game the seven artifacts below still use primitive-part models, which are a
fallback and are UNFINISHED against the silhouette requirement.** (`TreasureModels.Status(id)` returns `"unfinished"` for them;
tested.) Adding more primitive parts is not claimed to fix this.

## Limitation (exact)
This environment can run Python but has no Roblox Studio and no authenticated upload route, so I could create the mesh geometry but could not import
or upload it, nor check how it looks in the engine. The previews are renders of the OBJ files (back-face culled), not engine images.

## What was produced
`python3 tools/make_artifact_meshes.py` writes `assets/artifact_meshes/<id>/<group>.obj` (flat-shaded, original, authored in studs,
+Y up, front +Z, origin at the object centre, one file per colour group), `manifest.json` (bounds, colours, materials, triangle counts) and
`MeshAssets.template.lua`. `python3 tools/preview_meshes.py out.png` renders them (`docs/images/artifact_meshes_preview.png`).
| Artifact | Groups | Triangles | Shape delivered |
|----------|--------|----------:|-----------------|
| Pottery Shard | outer, inner, edge, band | ~430 | one curved vessel-wall fragment, uneven broken perimeter, wall thickness, dark inside, fresh-break edge, one painted band |
| Cut Gemstone | gem, table | 80 | single faceted brilliant: flat table, sloped crown facets, girdle, tapered pavilion to a culet |
| Fossil Fragment | rock, shell | ~560 | one irregular faceted rock with a flat face, a ribbed tapering ammonite spiral standing out of it |
| Clay Figurine | clay, dark, chip | ~690 | lathe-shaped tapered body with shoulders, neck, shaped head with nose/brow/eye marks, one hanging and one bent connected arm, base with a chipped facet |
| Fossil Claw | bone, tip, rock | ~360 | one continuous tapered curve (broad base to a dark point) with restrained knuckle ridges on a rock base |
| Golden Scarab | shell, head, legs, inlay | ~600 | paired wing covers with a central seam, thorax plate, small head and eyes, six thin legs starting inside the body |
| Sun Pharaoh Mask | gold, headdress, stripe, inlay | ~1480 | relief face (nose ridge, recessed eyes, cheeks, brow, mouth, tapered chin), headdress cap and lappets framing it, striped, beard |
Known weaknesses in the previews: the claw's rock base is a plain wedge; the scarab legs are thin and the shell is long; the mask face grid shows
faceting. These are first-pass originals and need an artist's eye in Studio.

## Import steps (to do in Roblox Studio — NOT done)
1. Studio → Asset Manager → Bulk Import (or Avatar > Import 3D) → select all `.obj` files of one artifact; import scale 1, keep the pivot at the
   mesh origin (do NOT re-centre; every group of an object must use the same pivot setting).
2. Publish/upload each mesh (you must own the assets); note each `rbxassetid://` MeshId.
3. Fill `Config.MeshAssets` using `assets/artifact_meshes/MeshAssets.template.lua` (one entry per group, `Size` = the object's bounds from the manifest).
   From then on reveals, carried artifacts, first-person, buried tells, the journal and the shelf all use the meshes (they share `TreasureModels.Specs`).
4. Check in Studio: all groups line up, colours/materials, scale on the shelf, journal icon framing, tell protrusion (0.7 studs), carried pose.
5. Remove the artifact from `TreasureModels.MeshRequired` only after it looks right in those views.
Asset-rights note: the meshes are procedurally generated for this project (no third-party geometry).
