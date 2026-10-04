#!/usr/bin/env python3
"""Static pre-flight for Studio testing (no Roblox needed). Catches the mistakes that only show up as a hang or an error at runtime:
  * every Remotes.Get("X") names a remote declared in Remotes.luau (a missing one makes WaitForChild hang the whole client/server start)
  * every RateLimiter.Check(..., "Key") has an entry in Config.RateLimits
  * every require(script.Parent.X) / require(Services.X) / require(Controllers.X) / require(ReplicatedStorage.Shared.X) points at a real file
  * Config.MeshAssets markers present; audio ids are placeholders or well-formed; Studio uses an isolated test DataStore
Usage: python3 tools/preflight.py      (exit code 1 on any failure)"""
import os, re, sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src")
files = {}
for dp, _, fn in os.walk(root):
    for f in fn:
        if f.endswith(".luau"):
            files[os.path.join(dp, f)] = open(os.path.join(dp, f)).read()
def modules(sub):
    d = os.path.join(root, sub)
    return {f[:-5] for f in os.listdir(d) if f.endswith(".luau")}
shared, services, controllers = modules("shared"), modules("server/Services"), modules("client/Controllers")
problems = []
events = set(re.findall(r'^\t"(\w+)",', open(os.path.join(root, "shared", "Remotes.luau")).read(), flags=re.M))
cfg = open(os.path.join(root, "shared", "Config.luau")).read()
limits = set(re.findall(r"^\t(\w+) = \{ \d+, \d+ \},", cfg, flags=re.M))
for path, text in files.items():
    rel = os.path.relpath(path, root)
    for name in re.findall(r'Remotes\.Get\("(\w+)"\)', text):
        if name not in events: problems.append(f"{rel}: Remotes.Get(\"{name}\") is not declared in Remotes.luau")
    for key in re.findall(r'RateLimiter\.Check\(\w+, "(\w+)"\)', text):
        if key not in limits: problems.append(f"{rel}: RateLimiter key \"{key}\" missing from Config.RateLimits")
    server = rel.startswith("server"); client = rel.startswith("client")
    for pat, known in ((r"require\(script\.Parent\.(\w+)\)", services if server else controllers if client else shared),
                       (r"require\(ReplicatedStorage\.Shared\.(\w+)\)", shared),
                       (r"require\((?:Services|script\.Parent:WaitForChild\(\"Services\"\))\.(\w+)\)", services),
                       (r"require\(Controllers\.(\w+)\)", controllers)):
        for m in re.findall(pat, text):
            if m not in known: problems.append(f"{rel}: require of '{m}' has no matching file")
if "-- MESH_ASSETS_BEGIN" not in cfg or "-- MESH_ASSETS_END" not in cfg: problems.append("Config.luau: MESH_ASSETS markers missing")
store = re.search(r'StoreName = "([^"]+)"', cfg); studio = re.search(r'StudioStoreName = "([^"]+)"', cfg)
if not studio or not store or studio.group(1) == store.group(1): problems.append("Config.Data: Studio must use a different (test) DataStore name")
audio = files[os.path.join(root, "client", "Controllers", "AudioController.luau")]
for sid in re.findall(r'Id = "([^"]*)"', audio):
    if sid and not (sid.startswith("rbxasset://sounds/") or re.fullmatch(r"rbxassetid://\d{4,}", sid)): problems.append(f"AudioController: odd sound id {sid!r}")
print(f"checked {len(files)} files, {len(events)} remotes, {len(limits)} rate-limit keys")
if problems:
    print("\n".join("FAIL: " + p for p in problems)); sys.exit(1)
print("preflight OK")
