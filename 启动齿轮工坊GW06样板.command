#!/bin/zsh
set -e
cd -- "${0:A:h}"
if command -v godot >/dev/null 2>&1; then
  workshop_godot="$(command -v godot)"
elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
  workshop_godot=/Applications/Godot.app/Contents/MacOS/Godot
else
  print '请先安装 Godot 4.7，或在 Godot 中导入 project.godot。'
  read '?按回车关闭'
  exit 1
fi
"$workshop_godot" --headless --path "$PWD" --editor --import --log-file /tmp/pixel-workshop-gw06-import-player.log
exec "$workshop_godot" --path "$PWD" --scene game/workshop_gw06.tscn
