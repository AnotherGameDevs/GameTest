#!/usr/bin/env python3
"""Renders the generated artifact meshes (back-face culled, flat shaded) to a PNG for a silhouette check.
Usage: python3 tools/preview_meshes.py out.png   (schematic preview of the OBJ files; NOT an in-engine image)"""
import json, math, os, sys
import numpy as np
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "artifact_meshes")
mf = json.load(open(os.path.join(root, "manifest.json")))
def load(path):
    V, N, T = [], [], []
    for line in open(path):
        p = line.split()
        if not p: continue
        if p[0] == "v": V.append([float(x) for x in p[1:4]])
        elif p[0] == "f": T.append([int(x.split("//")[0]) - 1 for x in p[1:4]])
    V = np.array(V)
    return V, T
def rot(ax_deg, ay_deg):
    ax, ay = math.radians(ax_deg), math.radians(ay_deg)
    Rx = np.array([[1,0,0],[0,math.cos(ax),-math.sin(ax)],[0,math.sin(ax),math.cos(ax)]])
    Ry = np.array([[math.cos(ay),0,math.sin(ay)],[0,1,0],[-math.sin(ay),0,math.cos(ay)]])
    return Ry @ Rx
VIEWS = {"pottery_shard": [(-6, -25), (-6, 35)], "cut_gemstone": [(18, -20), (-35, 30)], "fossil_fragment": [(-10, -20), (-14, 30)],
         "clay_figurine": [(6, -24), (6, 40)], "fossil_claw": [(-4, -12), (-4, 40)], "golden_scarab": [(32, -20), (60, 25)], "sun_mask": [(0, -18), (0, 35)]}
ids = list(mf)
fig, axes = plt.subplots(2, 7, figsize=(21, 6.4), dpi=100)
fig.patch.set_facecolor("#1D2025")
light = np.array([-0.4, 0.7, 0.6]); light /= np.linalg.norm(light)
bad_total = 0
for k, tid in enumerate(ids):
    for vi in range(2):
        ax = axes[vi][k]; ax.set_facecolor("#2B3038"); ax.set_xticks([]); ax.set_yticks([])
        M = rot(*VIEWS[tid][vi])
        polys = []
        for g, info in mf[tid]["groups"].items():
            V, T = load(os.path.join(root, info["file"]))
            col = np.array([int(info["color"][i:i+2], 16) / 255 for i in (0, 2, 4)])
            for t in T:
                a, b, c = (M @ V[t[0]]), (M @ V[t[1]]), (M @ V[t[2]])
                n = np.cross(b - a, c - a); L = np.linalg.norm(n)
                if L < 1e-12: continue
                n /= L
                if n[2] <= 0: continue   # back-face: invisible, so inverted triangles show up as holes
                shade = 0.45 + 0.55 * max(0, float(np.dot(n, light)))
                polys.append(((a[2]+b[2]+c[2])/3, [(a[0],a[1]),(b[0],b[1]),(c[0],c[1])], np.clip(col*shade,0,1)))
        polys.sort(key=lambda p: p[0])
        for _, xy, c in polys: ax.add_patch(Polygon(xy, closed=True, facecolor=c, edgecolor=c*0.7, linewidth=0.2))
        ax.set_xlim(-2.6, 2.6); ax.set_ylim(-2.6, 2.6); ax.set_aspect("equal")
        if vi == 0: ax.set_title(tid, color="#EFE2C3", fontsize=9)
fig.suptitle("Generated artifact meshes (back-face culled preview of the OBJ files) - NOT an in-engine image", color="#EFE2C3")
plt.tight_layout(rect=(0, 0, 1, 0.95)); plt.savefig(sys.argv[1] if len(sys.argv) > 1 else "mesh_preview.png", facecolor=fig.get_facecolor()); print("saved")
