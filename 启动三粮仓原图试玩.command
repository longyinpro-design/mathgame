#!/bin/zsh
set -e
cd -- "${0:A:h}"
if command -v godot >/dev/null 2>&1; then
  forest_godot="$(command -v godot)"
elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
  forest_godot=/Applications/Godot.app/Contents/MacOS/Godot
else
  print '请安装 Godot 4.7 stable，或在 Godot 中打开 project.godot。'
  read '?按回车关闭'
  exit 1
fi
"$forest_godot" --headless --path "$PWD" --editor --import --quit --log-file /tmp/pixel-village-scene-import.log
exec "$forest_godot" --path "$PWD" --script scripts/village_scene_preview.gd
