#!/bin/zsh
set -e
cd -- "${0:A:h}"
if command -v godot >/dev/null 2>&1; then
  exec godot --path "$PWD"
elif [[ -x /Applications/Godot.app/Contents/MacOS/Godot ]]; then
  exec /Applications/Godot.app/Contents/MacOS/Godot --path "$PWD"
else
  print '请先安装 Godot 4.7 stable，或在 Godot 中导入本目录的 project.godot。'
  read '?按回车关闭'
fi
