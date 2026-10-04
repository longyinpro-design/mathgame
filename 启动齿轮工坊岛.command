#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"
if command -v godot >/dev/null 2>&1; then
  workshop_godot="$(command -v godot)"
elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
  workshop_godot=/Applications/Godot.app/Contents/MacOS/Godot
else
  printf '%s\n' '请先安装 Godot，或在 Godot 中导入 project.godot。'
  exit 1
fi
"$workshop_godot" --headless --path "$PWD" --editor --import --quit
exec "$workshop_godot" --path "$PWD" --scene game/workshop_island.tscn
