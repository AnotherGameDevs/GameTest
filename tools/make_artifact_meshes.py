#!/usr/bin/env python3
"""Generates ORIGINAL low-poly artifact meshes (Wavefront OBJ, flat-shaded, authored in studs, +Y up, front = +Z, origin at
the centre of the object) for the seven artifacts whose shapes cannot be built cleanly from Roblox primitives.

Output: assets/artifact_meshes/<treasure_id>/<group>.obj (one file per colour group, so each can be uploaded as its own mesh
and tinted with Part.Color) and assets/artifact_meshes/manifest.json (group colours/materials, bounds, triangle counts).
Run: python3 tools/make_artifact_meshes.py [--preview out.png]
The meshes are NOT in the game until imported in Roblox Studio and their asset ids are put in Config.MeshAssets
(see docs/ARTIFACT_MESHES.md). Everything here is deterministic (seeded) and uses only numpy/scipy.
"""
import json, math, os, sys
import numpy as np
from scipy.spatial import ConvexHull

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "artifact_meshes")

class Mesh:
    def __init__(self):
        self.groups = {}
    def tri(self, g, a, b, c):
        self.groups.setdefault(g, []).append(np.array([a, b, c], float))
    def quad(self, g, a, b, c, d):
        self.tri(g, a, b, c); self.tri(g, a, c, d)
    def tri_oriented(self, g, a, b, c, inside):
        n = np.cross(np.array(b) - a, np.array(c) - a)
        if np.dot(n, (np.array(a) + b + c) / 3 - inside) < 0:
            b, c = c, b
        self.tri(g, a, b, c)
    def tri_hint(self, g, a, b, c, hint):
        n = np.cross(np.array(b) - a, np.array(c) - a)
        if np.dot(n, hint) < 0:
            b, c = c, b
        self.tri(g, a, b, c)

def hull(m, g, pts):
    pts = np.array(pts, float)
    h = ConvexHull(pts)
    c = pts.mean(axis=0)
    for s in h.simplices:
        m.tri_oriented(g, pts[s[0]], pts[s[1]], pts[s[2]], c)

def ellipsoid(m, g, c, r, nu=10, nv=6, rot=None):
    c = np.array(c, float); r = np.array(r, float)
    def P(t, p):
        v = np.array([r[0] * math.sin(t) * math.cos(p), r[1] * math.cos(t), r[2] * math.sin(t) * math.sin(p)])
        if rot is not None: v = rot @ v
        return c + v
    for j in range(nv):
        t0, t1 = math.pi * j / nv, math.pi * (j + 1) / nv
        for i in range(nu):
            p0, p1 = 2 * math.pi * i / nu, 2 * math.pi * (i + 1) / nu
            a, b, cc, d = P(t0, p0), P(t0, p1), P(t1, p1), P(t1, p0)
            if j == 0: m.tri_oriented(g, a, cc, d, c) if False else m.tri_oriented(g, P(t0, 0), cc, d, c)
            elif j == nv - 1: m.tri_oriented(g, a, b, d, c)
            else:
                m.tri_oriented(g, a, b, cc, c); m.tri_oriented(g, a, cc, d, c)

def tube(m, g, path, radii, sides=8, up=None, cap_start=True, cap_end=True):
    """Sweep an elliptical cross-section (rx, rz) along a polyline. radii[i] = (rx, rz) in the local frame (N, B)."""
    path = np.array(path, float); n = len(path)
    ring = []
    prevN = None
    for i in range(n):
        t = path[min(i + 1, n - 1)] - path[max(i - 1, 0)]
        t /= np.linalg.norm(t)
        if up is not None:
            N = np.cross(up, t); N /= np.linalg.norm(N)
        else:
            if prevN is None:
                a = np.array([0, 1, 0]) if abs(t[1]) < 0.9 else np.array([1, 0, 0])
                N = np.cross(t, a); N /= np.linalg.norm(N)
            else:
                N = prevN - np.dot(prevN, t) * t; N /= np.linalg.norm(N)
        prevN = N
        B = np.cross(t, N)
        rx, rz = radii[i]
        ring.append([path[i] + rx * math.cos(2 * math.pi * k / sides) * N + rz * math.sin(2 * math.pi * k / sides) * B for k in range(sides)])
    for i in range(n - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            a, b, c, d = ring[i][k], ring[i][k2], ring[i + 1][k2], ring[i + 1][k]
            m.tri_oriented(g, a, b, c, path[i]); m.tri_oriented(g, a, c, d, path[i])
    if cap_start:
        for k in range(sides): m.tri_oriented(g, path[0], ring[0][k], ring[0][(k + 1) % sides], path[1] if n > 1 else path[0] + 1)
        # (fan faces away from the path interior)
    if cap_end:
        for k in range(sides): m.tri_oriented(g, path[-1], ring[-1][k], ring[-1][(k + 1) % sides], path[-2] if n > 1 else path[-1] - 1)

def lathe(m, g, profile, sides=10, ell=(1.0, 1.0), cx=0.0, cz=0.0):
    rings = [[np.array([cx + r * ell[0] * math.cos(2 * math.pi * k / sides), y, cz + r * ell[1] * math.sin(2 * math.pi * k / sides)]) for k in range(sides)] for r, y in profile]
    for i in range(len(rings) - 1):
        for k in range(sides):
            k2 = (k + 1) % sides
            a, b, c, d = rings[i][k], rings[i][k2], rings[i + 1][k2], rings[i + 1][k]
            axis = np.array([cx, (a[1] + c[1]) / 2, cz])
            m.tri_oriented(g, a, b, c, axis); m.tri_oriented(g, a, c, d, axis)
    for ring, y_in in ((rings[0], rings[1][0]), (rings[-1], rings[-2][0])):
        cen = np.array([cx, ring[0][1], cz])
        for k in range(sides): m.tri_oriented(g, cen, ring[k], ring[(k + 1) % sides], np.array([cx, y_in[1], cz]))

def rotz(a): c, s = math.cos(a), math.sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
def roty(a): c, s = math.cos(a), math.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def rotx(a): c, s = math.cos(a), math.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])

# ---------------------------------------------------------------------------------------------------------------------------
def pottery_shard():
    m = Mesh(); R, T = 1.55, 0.3
    cols, rows = 15, 6
    phis = [math.radians(-56 + 112 * j / (cols - 1)) for j in range(cols)]
    def top(j): return 1.05 + 0.16 * math.sin(0.55 * j + 0.3) + 0.5 * (j / (cols - 1) - 0.5) - (0.6 if j == 0 else 0) - (0.3 if j == 1 else 0) - (0.35 if j == cols - 1 else 0) - (0.12 if j == cols - 2 else 0)
    def bot(j): return -1.0 - 0.14 * math.sin(0.7 * j + 1.0) - 0.4 * (j / (cols - 1) - 0.5) + (0.55 if j == 0 else 0) + (0.25 if j == 1 else 0) + (0.3 if j == cols - 1 else 0)
    def P(rad, j, v):  # v in 0..1 bottom..top
        y = bot(j) + (top(j) - bot(j)) * v
        return np.array([rad * math.sin(phis[j]), y, rad * math.cos(phis[j]) - R]), y
    axis = lambda p: np.array([0, p[1], -R])
    for j in range(cols - 1):
        for i in range(rows):
            v0, v1 = i / rows, (i + 1) / rows
            o = [P(R, j, v0)[0], P(R, j + 1, v0)[0], P(R, j + 1, v1)[0], P(R, j, v1)[0]]
            m.tri_oriented("outer", o[0], o[1], o[2], axis(o[0])); m.tri_oriented("outer", o[0], o[2], o[3], axis(o[0]))
            n = [P(R - T, j, v0)[0], P(R - T, j + 1, v0)[0], P(R - T, j + 1, v1)[0], P(R - T, j, v1)[0]]
            # inner surface faces the axis (inside of the vessel)
            m.tri_hint("inner", n[0], n[1], n[2], axis(n[0]) - n[0]); m.tri_hint("inner", n[0], n[2], n[3], axis(n[0]) - n[0])
        # broken edges (fresh clay): top and bottom perimeter
        for v, hint in ((1.0, np.array([0, 1, 0])), (0.0, np.array([0, -1, 0]))):
            a, b = P(R, j, v)[0], P(R, j + 1, v)[0]; c, d = P(R - T, j + 1, v)[0], P(R - T, j, v)[0]
            m.tri_hint("edge", a, b, c, hint); m.tri_hint("edge", a, c, d, hint)
    for j, hint in ((0, -1), (cols - 1, 1)):  # the two broken sides
        for i in range(rows):
            v0, v1 = i / rows, (i + 1) / rows
            a, b, c, d = P(R, j, v0)[0], P(R, j, v1)[0], P(R - T, j, v1)[0], P(R - T, j, v0)[0]
            h = np.array([math.cos(phis[j]) * hint, 0, -math.sin(phis[j]) * hint])
            m.tri_hint("edge", a, b, c, h); m.tri_hint("edge", a, c, d, h)
    # one painted band on the outer face (raised 0.03), kept inside the perimeter
    for j in range(2, cols - 3):
        y0, y1 = 0.02, 0.26
        a, b = np.array([(R + 0.03) * math.sin(phis[j]), y0, (R + 0.03) * math.cos(phis[j]) - R]), np.array([(R + 0.03) * math.sin(phis[j + 1]), y0, (R + 0.03) * math.cos(phis[j + 1]) - R])
        c, d = b + [0, y1 - y0, 0], a + [0, y1 - y0, 0]
        m.tri_oriented("band", a, b, c, axis(a)); m.tri_oriented("band", a, c, d, axis(a))
    return m

def cut_gemstone():
    m = Mesh(); th = math.pi / 4
    def ring(r, y, off): return [np.array([r * math.cos(k * th + off), y, r * math.sin(k * th + off)]) for k in range(8)]
    girdleT, girdleB = ring(1.0, 0.06, 0), ring(1.0, -0.06, 0)
    crownMid, table = ring(0.86, 0.34, th / 2), ring(0.5, 0.6, 0)
    pavMid = ring(0.58, -0.5, th / 2)
    cen = np.array([0, 0.0, 0])
    def band(A, B):
        for k in range(8):
            k2 = (k + 1) % 8
            m.tri_oriented("gem", A[k], B[k], B[k2], cen); m.tri_oriented("gem", A[k], B[k2], A[k2], cen)
    def antiprism(A, B):  # A aligned, B offset by half a step
        for k in range(8):
            k2 = (k + 1) % 8
            m.tri_oriented("gem", A[k], A[k2], B[k], cen); m.tri_oriented("gem", B[k], A[k2], B[k2], cen)
    band(girdleT, girdleB)
    antiprism(girdleT, crownMid)
    for k in range(8):  # crown mid ring (offset) up to the table (aligned)
        k2 = (k + 1) % 8
        m.tri_oriented("gem", table[k], table[k2], crownMid[k], cen); m.tri_oriented("gem", crownMid[k], table[k2], crownMid[k2] if False else crownMid[(k + 1) % 8], cen)
    for k in range(8):
        m.tri_oriented("table", np.array([0, 0.6, 0]), table[k], table[(k + 1) % 8], cen)
    antiprism(girdleB, pavMid)
    culet = np.array([0, -1.05, 0])
    for k in range(8):
        m.tri_oriented("gem", culet, pavMid[k], pavMid[(k + 1) % 8], cen)
    return m

def fossil_fragment():
    rng = np.random.default_rng(11)
    m = Mesh()
    # irregular broken outline (a bite taken out of one corner), extruded: flat front face, rougher back
    ang = np.linspace(0, 2 * math.pi, 11)[:-1] + rng.normal(0, 0.12, 10)
    rad = np.array([1.35, 1.2, 1.3, 1.15, 1.35, 1.25, 1.0, 1.3, 1.2, 1.35]) * np.array([1.0, 0.8])[0]
    outline = [(1.45 * math.cos(a) * (0.8 + 0.2 * (i % 3 == 0)), 1.1 * math.sin(a) * (0.85 + 0.15 * ((i + 1) % 2))) for i, a in enumerate(ang)]
    outline[6] = (outline[6][0] * 0.55, outline[6][1] * 0.55)  # the bite
    pts = []
    for (x, y) in outline:
        pts.append((x, y, 0.28))  # flat front
        pts.append((x * 0.92 + rng.normal(0, 0.04), y * 0.92 + rng.normal(0, 0.04), -0.34 + rng.normal(0, 0.05)))
    hull(m, "rock", pts)
    # ammonite: a tapering oval band along a logarithmic spiral, standing out of the front face, with ribs
    cx, cy = -0.12, 0.02
    path, radii = [], []
    N = 44
    for i in range(N):
        t = 10.6 * i / (N - 1)
        r = 0.11 * math.exp(0.19 * t)
        path.append(np.array([cx + r * math.cos(t), cy + r * math.sin(t), 0.30]))
        width = 0.06 + 0.17 * r
        rib = 1 + 0.22 * math.cos(t * 3.2)
        radii.append((width, (0.05 + 0.1 * r) * rib))
    tube(m, "shell", path, radii, sides=6, up=np.array([0, 0, 1.0]), cap_start=True, cap_end=True)
    return m

def clay_figurine():
    m = Mesh()
    lathe(m, "dark", [(0.78, -1.55), (0.78, -1.38), (0.62, -1.34)], sides=10, ell=(1.0, 0.75))  # base plate
    lathe(m, "clay", [(0.62, -1.34), (0.58, -0.9), (0.5, -0.3), (0.56, 0.22), (0.62, 0.36), (0.4, 0.5), (0.2, 0.56)], sides=10, ell=(1.0, 0.72))  # tapered torso, shoulders
    lathe(m, "clay", [(0.2, 0.5), (0.17, 0.66), (0.19, 0.84)], sides=8, ell=(1.0, 1.0))  # neck
    ellipsoid(m, "clay", (0, 1.28, 0), (0.46, 0.56, 0.42), nu=10, nv=7)  # head
    ellipsoid(m, "clay", (0, 1.18, 0.4), (0.11, 0.2, 0.12), nu=6, nv=4)  # nose
    ellipsoid(m, "clay", (0, 1.52, 0.3), (0.34, 0.07, 0.14), nu=8, nv=3)  # brow ridge
    for sx in (-1, 1):
        ellipsoid(m, "dark", (sx * 0.17, 1.38, 0.36), (0.07, 0.035, 0.04), nu=6, nv=3)  # shallow eye marks
    ellipsoid(m, "dark", (0, 0.98, 0.37), (0.12, 0.025, 0.04), nu=6, nv=3)  # mouth
    # arms: left hangs, right is bent up to the chest; both joined into the shoulders
    tube(m, "clay", [(-0.5, 0.3, 0), (-0.66, -0.15, 0.04), (-0.74, -0.62, 0.1)], [(0.16, 0.14), (0.15, 0.13), (0.13, 0.12)], sides=7)
    ellipsoid(m, "clay", (-0.74, -0.68, 0.1), (0.13, 0.13, 0.12), nu=6, nv=4)
    tube(m, "clay", [(0.5, 0.3, 0), (0.78, 0.0, 0.08), (0.62, -0.2, 0.34), (0.3, -0.05, 0.42)], [(0.16, 0.14), (0.15, 0.13), (0.13, 0.12), (0.12, 0.11)], sides=7)
    ellipsoid(m, "clay", (0.26, -0.02, 0.43), (0.12, 0.12, 0.11), nu=6, nv=4)
    # one chipped edge on the base: a paler broken facet
    hull(m, "chip", [(-0.78, -1.55, 0.1), (-0.5, -1.55, 0.45), (-0.62, -1.34, 0.35), (-0.78, -1.38, 0.1), (-0.55, -1.38, 0.38), (-0.7, -1.5, 0.3)])
    return m

def fossil_claw():
    m = Mesh()
    R, cx, cy = 2.3, -1.1, -1.0
    N = 22
    path, radii = [], []
    for i in range(N):
        t = i / (N - 1)
        a = math.radians(4 + 82 * t)
        path.append(np.array([cx + R * math.cos(a), cy + R * math.sin(a), 0.0]))
        w = 0.58 * (1 - t) ** 0.85 + 0.03
        knuckle = 1 + 0.12 * math.cos(t * 5 * math.pi) * (1 - t)  # restrained ridges
        radii.append((w * knuckle, w * 0.78 * knuckle))
    split = int(N * 0.84)
    tube(m, "bone", path[:split + 1], radii[:split + 1], sides=8, cap_start=True, cap_end=False)
    tube(m, "tip", path[split:], radii[split:], sides=8, cap_start=False, cap_end=True)
    rng = np.random.default_rng(5)
    pts = [(x * 1.2 + 0.2, y * 0.35 - 1.45, z * 0.65) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    pts += [(rng.uniform(-1.1, 1.3), rng.uniform(-1.85, -1.25), rng.uniform(-0.6, 0.6)) for _ in range(8)]
    hull(m, "rock", pts)
    return m

def golden_scarab():
    m = Mesh()
    for sx in (-1, 1):  # paired wing covers with a central seam
        ellipsoid(m, "shell", (sx * 0.5, 0.0, 0.35), (0.6, 0.55, 1.55), nu=9, nv=6)
    ellipsoid(m, "shell", (0, -0.03, -0.95), (0.8, 0.42, 0.55), nu=10, nv=6)  # pronotum (thorax plate)
    ellipsoid(m, "head", (0, -0.1, -1.55), (0.5, 0.3, 0.32), nu=8, nv=5)  # head with a clypeus
    for sx in (-1, 1):
        ellipsoid(m, "inlay", (sx * 0.22, 0.02, -1.74), (0.07, 0.07, 0.07), nu=5, nv=3)  # small eyes
    # six legs: femur out and down, tibia down to the ground; they start INSIDE the body so they join it
    for z0, spread in ((-0.9, 0.55), (-0.1, 0.9), (0.75, 0.7)):
        for sx in (-1, 1):
            hip = np.array([sx * 0.7, -0.22, z0])
            knee = np.array([sx * (1.05 + 0.2 * spread), -0.42, z0 + 0.25 * spread * (1 if z0 > -0.5 else -1) * 0.5])
            foot = np.array([sx * (1.35 + 0.35 * spread), -0.72, z0 + 0.5 * spread * (1 if z0 > -0.5 else -1) * 0.5])
            tube(m, "legs", [hip, knee, foot], [(0.11, 0.09), (0.09, 0.08), (0.05, 0.05)], sides=6)
    return m

def sun_mask():
    m = Mesh()
    # face plate: tapered oval outline, relief heightfield (nose ridge, recessed eyes, cheeks, brow, mouth), closed at the back
    nx, ny = 15, 22
    def outline_w(y):  # half width by height: broad at the brow, tapering to a narrow chin
        t = (y + 1.5) / 2.6
        return 0.92 * (0.42 + 0.58 * math.sin(min(max(t, 0), 1) * math.pi * 0.62 + 0.55)) if y > -1.5 else 0.2
    def relief(x, y):
        z = 0.34 - 0.18 * (x / 0.92) ** 2
        z += 0.33 * math.exp(-((x / 0.17) ** 2)) * (1 if -0.25 < y < 0.95 else 0.4)  # nose ridge
        for sx in (-1, 1):
            z -= 0.2 * math.exp(-(((x - sx * 0.4) / 0.2) ** 2 + ((y - 0.42) / 0.11) ** 2))  # recessed eye regions
            z += 0.1 * math.exp(-(((x - sx * 0.55) / 0.2) ** 2 + ((y + 0.15) / 0.22) ** 2))  # cheeks
        z += 0.1 * math.exp(-((y - 0.68) / 0.07) ** 2) * (abs(x) < 0.7)  # brow
        z -= 0.05 * math.exp(-(((x) / 0.25) ** 2 + ((y + 0.72) / 0.04) ** 2))  # mouth line
        return z
    grid = []
    for j in range(ny):
        y = -1.5 + 2.6 * j / (ny - 1)
        w = outline_w(y)
        row = []
        for i in range(nx):
            x = -w + 2 * w * i / (nx - 1)
            row.append(np.array([x, y, relief(x, y)]))
        grid.append(row)
    back = -0.28
    cen = np.array([0, -0.2, 0.0])
    for j in range(ny - 1):
        for i in range(nx - 1):
            a, b, c, d = grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]
            m.tri_hint("gold", a, b, c, np.array([0, 0, 1])); m.tri_hint("gold", a, c, d, np.array([0, 0, 1]))
    for j in range(ny - 1):  # sides and back
        for i, hint in ((0, np.array([-1, 0, 0])), (nx - 1, np.array([1, 0, 0]))):
            a, b = grid[j][i], grid[j + 1][i]
            m.tri_hint("gold", a, b, np.array([b[0], b[1], back]), hint); m.tri_hint("gold", a, np.array([b[0], b[1], back]), np.array([a[0], a[1], back]), hint)
    for i in range(nx - 1):
        for j, hint in ((0, np.array([0, -1, 0])), (ny - 1, np.array([0, 1, 0]))):
            a, b = grid[j][i], grid[j][i + 1]
            m.tri_hint("gold", a, b, np.array([b[0], b[1], back]), hint); m.tri_hint("gold", a, np.array([b[0], b[1], back]), np.array([a[0], a[1], back]), hint)
    for j in range(ny - 1):
        for i in range(nx - 1):
            m.tri_hint("gold", np.array([grid[j][i][0], grid[j][i][1], back]), np.array([grid[j + 1][i][0], grid[j + 1][i][1], back]),
                       np.array([grid[j + 1][i + 1][0], grid[j + 1][i + 1][1], back]), np.array([0, 0, -1]))
            m.tri_hint("gold", np.array([grid[j][i][0], grid[j][i][1], back]), np.array([grid[j + 1][i + 1][0], grid[j + 1][i + 1][1], back]),
                       np.array([grid[j][i + 1][0], grid[j][i + 1][1], back]), np.array([0, 0, -1]))
    # inlaid eyes sit in the recessed regions
    for sx in (-1, 1):
        ellipsoid(m, "inlay", (sx * 0.4, 0.42, 0.08), (0.17, 0.07, 0.07), nu=8, nv=4)
    # nemes headdress: crown cap and two lappets that frame the face, striped
    hull(m, "headdress", [(-1.05, 0.95, 0.35), (1.05, 0.95, 0.35), (-0.95, 1.55, 0.05), (0.95, 1.55, 0.05), (-1.0, 0.95, -0.55), (1.0, 0.95, -0.55), (-0.85, 1.5, -0.5), (0.85, 1.5, -0.5)])
    for sx in (-1, 1):
        hull(m, "headdress", [(sx * 0.9, 1.0, 0.3), (sx * 1.35, 0.9, 0.0), (sx * 1.3, -1.3, 0.1), (sx * 0.9, -0.2, 0.3), (sx * 0.95, 1.0, -0.5), (sx * 1.4, 0.9, -0.5), (sx * 1.35, -1.3, -0.4), (sx * 0.95, -0.2, -0.45)])
        hull(m, "stripe", [(sx * 1.2, 0.9, 0.12), (sx * 1.36, 0.86, 0.1), (sx * 1.32, -1.28, 0.12), (sx * 1.18, -1.2, 0.2), (sx * 1.2, 0.9, -0.45), (sx * 1.36, 0.86, -0.45), (sx * 1.32, -1.28, -0.4), (sx * 1.18, -1.2, -0.4)])
    hull(m, "stripe", [(-0.22, -1.5, 0.12), (0.22, -1.5, 0.12), (0, -1.95, 0.05), (-0.18, -1.5, -0.1), (0.18, -1.5, -0.1)])  # tapered beard
    return m

BUILDERS = {
    "pottery_shard": (pottery_shard, {"outer": ("B5683F", "SmoothPlastic"), "inner": ("5B3A26", "SmoothPlastic"), "edge": ("C98A5E", "SmoothPlastic"), "band": ("7A3322", "SmoothPlastic")}),
    "cut_gemstone": (cut_gemstone, {"gem": ("5FA3BF", "Glass"), "table": ("B7DCE8", "Glass")}),
    "fossil_fragment": (fossil_fragment, {"rock": ("6E7580", "Slate"), "shell": ("D8CDB0", "SmoothPlastic")}),
    "clay_figurine": (clay_figurine, {"clay": ("B5683F", "SmoothPlastic"), "dark": ("7A4228", "SmoothPlastic"), "chip": ("D49A6A", "SmoothPlastic")}),
    "fossil_claw": (fossil_claw, {"bone": ("D8CDB0", "SmoothPlastic"), "tip": ("5A4A33", "SmoothPlastic"), "rock": ("6E7580", "Slate")}),
    "golden_scarab": (golden_scarab, {"shell": ("C9A24B", "Metal"), "head": ("9A7A32", "Metal"), "legs": ("9A7A32", "Metal"), "inlay": ("3A72AE", "Glass")}),
    "sun_mask": (sun_mask, {"gold": ("C9A24B", "Metal"), "headdress": ("9A7A32", "Metal"), "stripe": ("3A72AE", "SmoothPlastic"), "inlay": ("E3D2B0", "SmoothPlastic")}),
}

def write_obj(path, tris, name):
    with open(path, "w") as f:
        f.write(f"# {name} - original low-poly mesh generated by tools/make_artifact_meshes.py (studs, +Y up, front +Z)\no {name}\n")
        for t in tris:
            n = np.cross(t[1] - t[0], t[2] - t[0]); L = np.linalg.norm(n)
            if L < 1e-12: continue
            n /= L
            for v in t: f.write("v %.4f %.4f %.4f\n" % tuple(v))
            f.write("vn %.4f %.4f %.4f\n" % tuple(n))
        k = 1
        for i in range(len(tris)):
            f.write(f"f {k}//{i + 1} {k + 1}//{i + 1} {k + 2}//{i + 1}\n"); k += 3

def build_all():
    manifest = {}
    for tid, (fn, groups) in BUILDERS.items():
        m = fn()
        d = os.path.join(OUT, tid); os.makedirs(d, exist_ok=True)
        allv = np.concatenate([np.concatenate(t) for t in m.groups.values()])
        lo, hi = allv.min(axis=0), allv.max(axis=0)
        entry = {"bounds_min": [round(float(x), 3) for x in lo], "bounds_max": [round(float(x), 3) for x in hi], "groups": {}}
        for g, tris in m.groups.items():
            write_obj(os.path.join(d, g + ".obj"), tris, f"{tid}_{g}")
            hexc, mat = groups[g]
            entry["groups"][g] = {"file": f"{tid}/{g}.obj", "color": hexc, "material": mat, "triangles": len(tris)}
        manifest[tid] = entry
    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    # Lua template for Config.MeshAssets: fill the MeshId of each group after uploading its OBJ in Roblox Studio.
    with open(os.path.join(OUT, "MeshAssets.template.lua"), "w") as f:
        f.write("-- Paste into Config.MeshAssets after importing + uploading each OBJ (replace every rbxassetid://0).\nConfig.MeshAssets = {\n")
        for tid, e in manifest.items():
            size = [round(e["bounds_max"][i] - e["bounds_min"][i], 3) for i in range(3)]
            f.write(f"\t{tid} = {{\n")
            for g, info in e["groups"].items():
                f.write(f'\t\t{{ Name = "{g}", MeshId = "rbxassetid://0", Color = "{info["color"]}", Material = "{info["material"]}", Size = Vector3.new({size[0]}, {size[1]}, {size[2]}) }},\n')
            f.write("\t},\n")
        f.write("}\n")
    return manifest

if __name__ == "__main__":
    mf = build_all()
    for tid, e in mf.items():
        print(tid, "tris=%d" % sum(g["triangles"] for g in e["groups"].values()), "bounds", e["bounds_min"], e["bounds_max"])
