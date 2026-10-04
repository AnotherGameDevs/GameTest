#!/usr/bin/env bash
# One command that produces the file to open in Studio: stamp -> tests -> preflight -> rojo build -> verify the file contains the current scripts.
# Needs: python3, luau (LUAU=/path), rojo (ROJO=/path). Output: Build/DigAndRun.rbxlx, Build/BUILD_INFO.txt
set -euo pipefail
cd "$(dirname "$0")/.."
LUAU="${LUAU:-luau}"; ROJO="${ROJO:-rojo}"
python3 tools/stamp_build.py
LUAU="$LUAU" bash tests/run_all.sh >/dev/null
python3 tools/preflight.py
"$ROJO" build default.project.json -o Build/DigAndRun.rbxlx
python3 tools/verify_build.py Build/DigAndRun.rbxlx | tee Build/BUILD_INFO.txt
