#!/usr/bin/env python3
"""Writes uploaded audio asset ids into AudioController.Sounds (only the Id field of existing cues).
Input JSON: {"Impact": "rbxassetid://123456789", ...}. Refuses unknown cue names and anything that is not rbxassetid://<digits>.
Usage: python3 tools/apply_audio_ids.py audio_ids.json [--dry-run]"""
import json, os, re, sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
path = os.path.join(root, "src", "client", "Controllers", "AudioController.luau")
text = open(path).read()
ids = json.load(open(sys.argv[1]))
cues = set(re.findall(r"^\t(\w+) = \{ Id = ", text, flags=re.M))
bad = [k for k, v in ids.items() if not re.fullmatch(r"rbxassetid://\d{4,}", str(v))]
unknown = [k for k in ids if k not in cues]
if bad or unknown:
    sys.exit(f"Refusing. Invalid ids: {bad or 'none'}; unknown cues (valid: {sorted(cues)}): {unknown or 'none'}")
for cue, new in ids.items():
    text, n = re.subn(rf"(^\t{cue} = \{{ Id = )(\"[^\"]*\"|PING)", rf'\g<1>"{new}"', text, count=1, flags=re.M)
    if n != 1:
        sys.exit(f"Could not patch cue {cue}")
print("patched:", ", ".join(ids))
if "--dry-run" not in sys.argv:
    open(path, "w").write(text)
