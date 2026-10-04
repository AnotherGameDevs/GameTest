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
# ---- reward-rendering paths: only these scripts may build reward geometry (reveals, pickups, carry, journal, shelf, relic, viewmodel). ----
ALLOWED_REWARD_RENDER = {"shared/TreasureModels.luau", "shared/ToolModels.luau", "client/Controllers/EffectsController.luau", "client/Controllers/CollectionUI.luau",
                         "client/Controllers/CampShelf.luau", "client/Controllers/ViewmodelController.luau", "server/Services/ArtifactService.luau",
                         "server/Services/RelicService.luau", "shared/MeshAssetsDoc.luau"}
MINE_PATH = {"shared/MineStyle.luau", "shared/MineDetailSpecs.luau", "shared/LootPlan.luau", "shared/Grid.luau", "server/Services/MineDetails.luau",
             "server/Services/SiteService.luau", "server/Services/MineShiftService.luau"}
for path, text in files.items():
    rel = os.path.relpath(path, root).replace(os.sep, "/")
    code = "\n".join(l.split("--")[0] for l in text.splitlines())  # ignore comments
    if "TreasureModels" in code and rel not in ALLOWED_REWARD_RENDER:
        problems.append(f"{rel}: uses TreasureModels but is not an allowed reward-rendering script (pre-discovery rewards must never be drawn)")
    if rel in MINE_PATH:
        if "TreasureModels" in code or "BuildAny" in code:
            problems.append(f"{rel}: mine generation/decoration must not build treasure geometry")
        if re.search(r"\bTell\b|\.Tell\b|tell_|Config\.Mine\.Tell", code):
            problems.append(f"{rel}: reward 'tell' machinery must not exist in the mine path")
        if rel in ("server/Services/MineDetails.luau", "shared/MineDetailSpecs.luau", "shared/MineStyle.luau") and re.search(r"Defs\.Treasure|lootId|board:Peek", code):
            problems.append(f"{rel}: mine remnants/styling must not read the buried loot")
# ---- persistence boundaries ----
def code_of(rel):
    return "\n".join(l.split("--")[0] for l in files[os.path.join(root, *rel.split("/"))].splitlines())
relic = code_of("server/Services/RelicService.luau")
if relic.count("MarkDirty") != 1 or "data.Cash +=" not in relic:
    problems.append("RelicService: profile writes must happen exactly once, in Deposit (an unsecured relic must never be persisted as a reward)")
for rel in ("server/Services/MineShiftService.luau", "server/Services/SiteService.luau", "server/Services/MineLifecycle.luau"):
    c = code_of(rel)
    if re.search(r"MarkDirty|\.Cash\b|OwnedTools\s*\[|\.Equipment\s*=|\.Collection\s*\[", c):
        problems.append(f"{rel}: a mine reset must not touch player progression (found a profile write)")
ds = code_of("server/Services/DataService.luau")
if "StudioStoreName" not in ds or "ProfileStore.Save" not in ds or "ProfileStore.Load" not in ds:
    problems.append("DataService must use ProfileStore and the isolated Studio store")
if re.search(r"if isStudio\(\) then\s*return\s*end", ds.split("BindToClose")[1] if "BindToClose" in ds else ""):
    problems.append("DataService.BindToClose must also flush saves in Studio")
# ---- equipment effects must never look at hidden rewards ----
FORBIDDEN_FX = r"LootBoard|LootPlan|LootService|SiteService|TreasureModels|Defs\.Treasure|\bRarity\b|Rarity\.|\bPeek\b|TreasureId|\.Loot\b|RelicRules"
for rel in ("shared/ToolFx.luau", "client/Controllers/ToolFxController.luau"):
    c = code_of(rel)
    if re.search(FORBIDDEN_FX, c):
        problems.append(f"{rel}: tool effects must not read loot / rarity / treasure information (found {re.search(FORBIDDEN_FX, c).group(0)!r})")
fxc = code_of("client/Controllers/EffectsController.luau")
m = re.search(r"local function onHit\(.*?\nend\n", fxc, re.S)
if not m:
    problems.append("EffectsController: onHit not found")
elif re.search(FORBIDDEN_FX, m.group(0)):
    problems.append("EffectsController.onHit (the dig-result effect path) must not read loot / rarity / treasure information")
mi = re.search(r"function Effects\.Impact\(.*?\nend\n", fxc, re.S)
if not mi or re.search(FORBIDDEN_FX, mi.group(0)):
    problems.append("EffectsController.Impact must exist and must not read loot information")
# ---- developer test mode: server-authorised, never client-trusted, never written to a profile ----
dev = code_of("server/Services/DevService.luau")
hnd = dev[dev.index("local function handle"):] if "local function handle" in dev else ""
if not hnd or hnd.find("accessFor(player)") < 0 or hnd.find("access.Allowed") < 0 or hnd.find("DevAccess.Permit") < 0 or not (hnd.find("accessFor(player)") < hnd.find("access.Allowed") < hnd.find("DevAccess.Validate") < hnd.find("DevAccess.Permit") < hnd.find("actions[action]")):
    problems.append("DevService.handle must check access, then validate, then permit, before running any action")
for path, text in files.items():
    rel = os.path.relpath(path, root).replace(os.sep, "/")
    c = "\n".join(l.split("--")[0] for l in text.splitlines())
    if "DevRequest" in c and rel not in ("shared/Remotes.luau", "shared/Config.luau", "server/Services/DevService.luau", "client/Controllers/DevPanel.luau"):
        problems.append(f"{rel}: only DevService (server) and DevPanel (client) may use the DevRequest remote")
    if rel.startswith("client/") and re.search(r"AllowedUserIds|TestPlaceIds|IsStudio", c):
        problems.append(f"{rel}: the client must not decide developer access (found an allowlist / IsStudio reference)")
    if rel.startswith("server/Services/Dev") and rel != "server/Services/DevService.luau" and re.search(r"DataStoreService|UpdateAsync|SetAsync|ProfileStore", c):
        problems.append(f"{rel}: developer helpers must never touch a DataStore")
if re.search(r"DataStore|UpdateAsync|SetAsync|\.Save\(", dev):
    problems.append("DevService must never save or touch a DataStore")
if "ProfileOverlay.SaveSource" not in ds or re.search(r"DeepCopy\(p\.Data\)", ds.split("function DataService.Save")[1].split("local function load")[0]):
    problems.append("DataService.Save must snapshot ProfileOverlay.SaveSource(p), never p.Data directly (test overlay must not be written)")
if "ProfileOverlay.MarkDirty" not in ds:
    problems.append("DataService.MarkDirty must go through ProfileOverlay.MarkDirty")
for rel in ("server/Services/ArtifactService.luau", "server/Services/RelicService.luau"):
    if "DevScenario.IsTest" not in code_of(rel):
        problems.append(f"{rel}: deposit must refuse to pay a developer-created artifact into a normal profile (DevScenario)")
bi = files[os.path.join(root, "shared", "BuildInfo.luau")]
print("build id in source:", re.search(r'Id = "([^"]+)"', bi).group(1))
print(f"checked {len(files)} files, {len(events)} remotes, {len(limits)} rate-limit keys")
if problems:
    print("\n".join("FAIL: " + p for p in problems)); sys.exit(1)
print("preflight OK")
