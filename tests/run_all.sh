#!/usr/bin/env bash
# Runs every pure-logic test. Needs the `luau` CLI on PATH (or LUAU=/path/to/luau).
set -e
cd "$(dirname "$0")/.."
LUAU="${LUAU:-luau}"
python3 tests/prep_shared.py
for t in artifact migration settings tool_assembly ground_plan camp_layout collection mine_style artifact_models loot_reset relic; do
  "$LUAU" "tests/${t}_test.luau"
done
