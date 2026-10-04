#!/usr/bin/env python3
"""Writes the imported mesh asset ids into Config.MeshAssets (between the MESH_ASSETS markers in src/shared/Config.luau).

Input: a JSON file mapping "<artifact_id>/<group>" to the MeshId you copied from Studio, e.g.
  { "pottery_shard/outer": "rbxassetid://123456789", "pottery_shard/inner": "rbxassetid://123456790", ... }
Rules (it refuses otherwise, so a typo can not ship): every id must match rbxassetid://<digits>; an artifact is enabled ONLY if ALL of its
groups are present (a half-imported artifact keeps its primitive fallback). Sizes/colours/materials come from assets/artifact_meshes/manifest.json.
Usage: python3 tools/apply_mesh_ids.py mesh_ids.json [--dry-run]
"""
import json, os, re, sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
manifest = json.load(open(os.path.join(root, "assets", "artifact_meshes", "manifest.json")))
ids = json.load(open(sys.argv[1]))
bad = [k for k, v in ids.items() if not re.fullmatch(r"rbxassetid://\d{4,}", str(v))]
if bad:
    sys.exit("Refusing: these are not valid rbxassetid://<digits> ids: " + ", ".join(bad))
unknown = [k for k in ids if "/" not in k or k.split("/")[0] not in manifest or k.split("/")[1] not in manifest[k.split("/")[0]]["groups"]]
if unknown:
    sys.exit("Refusing: unknown artifact/group keys: " + ", ".join(unknown))
lines = ["-- MESH_ASSETS_BEGIN (rewritten by tools/apply_mesh_ids.py - do not hand-edit between the markers)", "Config.MeshAssets = {"]
enabled, skipped = [], []
for art, e in manifest.items():
    groups = list(e["groups"])
    have = [g for g in groups if f"{art}/{g}" in ids]
    if len(have) != len(groups):
        if have: skipped.append(f"{art} (missing {sorted(set(groups) - set(have))})")
        continue
    size = [round(e["bounds_max"][i] - e["bounds_min"][i], 3) for i in range(3)]
    lines.append(f"\t{art} = {{")
    for g in groups:
        info = e["groups"][g]
        lines.append(f'\t\t{{ Name = "{g}", MeshId = "{ids[f"{art}/{g}"]}", Color = "{info["color"]}", Material = "{info["material"]}", Size = Vector3.new({size[0]}, {size[1]}, {size[2]}) }},')
    lines.append("\t},")
    enabled.append(art)
lines += ["}", "-- MESH_ASSETS_END"]
cfg = os.path.join(root, "src", "shared", "Config.luau")
text = open(cfg).read()
new = re.sub(r"-- MESH_ASSETS_BEGIN.*?-- MESH_ASSETS_END", "\n".join(lines), text, flags=re.S)
print("enabled:", enabled or "none"); print("left on primitive fallback (incomplete):", skipped or "none")
if "--dry-run" in sys.argv:
    print("\n".join(lines))
else:
    open(cfg, "w").write(new); print("Config.MeshAssets updated.")
