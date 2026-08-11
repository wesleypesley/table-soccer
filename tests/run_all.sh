#!/usr/bin/env bash
# Run every physics case, ONE FRESH PROCESS EACH (brief §6: never reuse a run).
# Usage: tests/run_all.sh [godot-binary]
set -uo pipefail

GODOT="${1:-${GODOT:-$HOME/.local/bin/godot}}"
cd "$(dirname "$0")/.."

CASES=(probe wall_max wall_double tether tether_moving pass_chain forfeit)

# A GDScript parse error leaves the scene scriptless, so nothing ever calls
# quit() and the process hangs forever. Always run under a timeout, and write
# to a file so output survives a kill (a pipe loses its buffer on SIGTERM).
CASE_TIMEOUT="${CASE_TIMEOUT:-90}"
LOG_DIR="$(mktemp -d)"
status=0

for c in "${CASES[@]}"; do
  log="$LOG_DIR/$c.log"
  timeout "$CASE_TIMEOUT" "$GODOT" --headless tests/run.tscn -- "$c" >"$log" 2>&1
  rc=$?
  if grep -q "SCRIPT ERROR\|Parse Error" "$log"; then
    echo "!! $c: script error"
    grep -m5 "SCRIPT ERROR\|Parse Error\|at: " "$log"
    status=1
    continue
  fi
  if [ $rc -eq 124 ]; then
    echo "!! $c: TIMED OUT after ${CASE_TIMEOUT}s"
    status=1
    continue
  fi
  sed -n '/^=====/,$p' "$log"
done

exit $status
