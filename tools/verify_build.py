#!/usr/bin/env python3
"""Proves a .rbxlx contains the CURRENT scripts: parses the file, extracts every Script/LocalScript/ModuleScript source, and checks that
each src/**/*.luau file appears in it byte-for-byte (modulo trailing whitespace / line endings) and that the stamped BuildInfo id matches.
Usage: python3 tools/verify_build.py [path/to/file.rbxlx]   (exit 1 on any mismatch)"""
import hashlib, os, re, sys, xml.etree.ElementTree as ET
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "Build", "DigAndRun.rbxlx")
norm = lambda t: "\n".join(l.rstrip() for l in t.replace("\r\n", "\n").strip().split("\n"))
sources = {}
for item in ET.parse(path).getroot().iter("Item"):
    if item.get("class") in ("Script", "LocalScript", "ModuleScript"):
        props = item.find("Properties"); name = None; src = None
        for p in props:
            if p.get("name") == "Name": name = p.text
            if p.get("name") == "Source": src = p.text or ""
        sources[norm(src or "")] = (item.get("class"), name)
missing, checked = [], 0
for dp, _, fn in os.walk(os.path.join(root, "src")):
    for f in fn:
        if f.endswith(".luau"):
            checked += 1
            if norm(open(os.path.join(dp, f)).read()) not in sources:
                missing.append(os.path.relpath(os.path.join(dp, f), root))
stamp = re.search(r'Id = "([^"]+)"', open(os.path.join(root, "src", "shared", "BuildInfo.luau")).read()).group(1)
in_file = [s for s in sources if 'Id = "' in s and "Stamped by tools/stamp_build.py" in s]
file_id = re.search(r'Id = "([^"]+)"', in_file[0]).group(1) if in_file else None
data = open(path, "rb").read()
print(f"file: {os.path.relpath(path, root)}  size: {len(data)}  sha256: {hashlib.sha256(data).hexdigest()}")
print(f"scripts in file: {len(sources)}   src files checked: {checked}   build id in source: {stamp}   build id in file: {file_id}")
if missing or file_id != stamp:
    print("MISMATCH - the exported file is OUTDATED or incomplete:")
    for m in missing: print("  not found in file:", m)
    sys.exit(1)
print("OK: every source script is present in the file, and the build id matches.")
