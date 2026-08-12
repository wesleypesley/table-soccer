#!/usr/bin/env bash
# Render the real game to a PNG. Needs a framebuffer (Xvfb), NOT --headless.
# Usage: tests/shoot.sh [wait_frames] [out_name.png]
set -uo pipefail
GODOT="${GODOT:-$HOME/.local/bin/godot}"
cd "$(dirname "$0")/.."
WAIT="${1:-45}"; OUT="${2:-shot.png}"
export LIBGL_ALWAYS_SOFTWARE=1
xvfb-run -a -s "-screen 0 1080x1920x24" \
  "$GODOT" --resolution 1080x1920 tests/shot.tscn -- "$WAIT" "$OUT" 2>&1 | grep -v "^$"
USERDIR="$HOME/.local/share/godot/app_userdata/Table Soccer"
[ -f "$USERDIR/$OUT" ] && cp "$USERDIR/$OUT" "${SHOT_DEST:-/tmp}/$OUT" && echo "copied -> ${SHOT_DEST:-/tmp}/$OUT"
