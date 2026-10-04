#!/usr/bin/env python3
"""Copies src/shared/*.luau to tests/_build/shared with Roblox-style requires rewritten to relative string requires and
the Vector3/CFrame/Color3/Enum stand-ins injected, so pure modules can run under the plain Luau CLI."""
import os, re, shutil, sys
root = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(root, "..", "src", "shared")
out = os.path.join(root, "_build", "shared")
shutil.rmtree(os.path.join(root, "_build"), ignore_errors=True)
os.makedirs(out)
shutil.copy(os.path.join(root, "stubs.luau"), os.path.join(out, "__stubs.luau"))
prelude = 'local __S = require("./__stubs")\nlocal Vector3, CFrame, Color3, Enum = __S.Vector3, __S.CFrame, __S.Color3, __S.Enum\n'
for name in os.listdir(src):
    if not name.endswith(".luau") or name in ("Remotes.luau",):
        continue
    text = open(os.path.join(src, name)).read()
    text = re.sub(r'require\(script\.Parent\.(\w+)\)', r'require("./\1")', text)
    open(os.path.join(out, name), "w").write(prelude + text)
print("prepared", len(os.listdir(out)), "modules")
