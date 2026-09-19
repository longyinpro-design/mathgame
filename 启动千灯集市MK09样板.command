#!/bin/zsh
set -e
cd -- "${0:A:h}"
if command -v godot >/dev/null 2>&1; then
  market_godot="$(command -v godot)"
elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
  market_godot=/Applications/Godot.app/Contents/MacOS/Godot
else
  print '请先安装 Godot 4.7 stable，或在 Godot 中导入 project.godot。'
  read '?按回车关闭'
  exit 1
fi
"$market_godot" --headless --path "$PWD" --editor --import --log-file /tmp/pixel-market-mk09-import-player.log
exec "$market_godot" --path "$PWD" --scene game/market_mk09.tscn
