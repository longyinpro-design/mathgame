#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"
if command -v godot >/dev/null 2>&1; then engine="$(command -v godot)"
elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then engine=/Applications/Godot.app/Contents/MacOS/Godot
else printf '%s\n' '请先安装 Godot 并导入 project.godot。'; exit 1; fi
"$engine" --headless --path "$PWD" --editor --import --quit
exec "$engine" --path "$PWD" --scene game/archipelago.tscn
