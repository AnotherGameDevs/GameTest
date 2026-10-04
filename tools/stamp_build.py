#!/usr/bin/env python3
"""Stamps src/shared/BuildInfo.luau with a build id derived from the SOURCE TREE, so the id shown in Settings / the server log identifies
exactly which scripts are inside an exported .rbxlx. Id = <UTC yyyymmdd-hhmm>-<first 8 hex of sha256(all src files except BuildInfo.luau)>."""
import datetime, hashlib, os, subprocess
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
src = os.path.join(root, "src")
h = hashlib.sha256()
for dp, dn, fn in sorted(os.walk(src)):
    dn.sort()
    for f in sorted(fn):
        if f == "BuildInfo.luau" or not f.endswith(".luau"):
            continue
        path = os.path.join(dp, f)
        h.update(os.path.relpath(path, src).replace(os.sep, "/").encode()); h.update(open(path, "rb").read())
now = datetime.datetime.now(datetime.timezone.utc)
def git(*a):
    try: return subprocess.check_output(["git", *a], cwd=root, stderr=subprocess.DEVNULL).decode().strip()
    except Exception: return "nogit"
dirty = "+uncommitted" if git("status", "--porcelain", "--", "src") not in ("", "nogit") else ""
bid = f"{now:%Y%m%d-%H%M}-{h.hexdigest()[:8]}"
text = f'''-- Stamped by tools/stamp_build.py before every export (do not edit by hand). Shown in Settings and printed by the server at startup so
-- you can tell exactly which build a Studio session is running. "unstamped" means the file was built without tools/build.sh.
return {{
	Id = "{bid}",
	Source = "git {git("rev-parse", "--short", "HEAD")}{dirty}",
	Time = "{now:%Y-%m-%d %H:%M} UTC",
}}
'''
open(os.path.join(src, "shared", "BuildInfo.luau"), "w").write(text)
print("stamped", bid)
