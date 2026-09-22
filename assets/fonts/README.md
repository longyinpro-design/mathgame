# 当前字体：UI 可读性修订（2026-09-22）

当前运行界面统一使用仓库内的 `NotoSansSC.ttf`，关闭系统字体回退。标题按界面使用 22–28px，主要正文与按钮 20–22px，紧凑说明最小 18px；世界内物件标注保留各自经实窗检验的字号。字体文件与字形未修改。

## 历史记录：v0.5.2

主字体为 ZCOOL KuaiLe（站酷快乐体），Google Fonts 原始文件 `ZCOOLKuaiLe-Regular.ttf`；标题/正文/按钮/数字统一使用。标题28px、正文22px、按钮20px、附属说明18px。Noto Sans SC仅用于主字体没有的符号回退，不依赖本机系统字体。

来源：https://fonts.gstatic.com/s/zcoolkuaile/v22/tssqApdaRQokwFjFJjvM6h2Wpg.ttf

Copyright 2018 The ZCOOL KuaiLe Project Authors (https://github.com/googlefonts/zcool-kuaile)。字体原始字形未修改，许可见 `OFL-ZCOOLKuaiLe.txt`。

试排与选择记录见 `docs/playtest/v52/font-decision.md`。以下为保留的旧字体来源记录。

---

# Noto Sans SC

来自 Google Fonts 官方分发的原始 TTF，400 与 600 字重，无修改。字体内嵌 copyright 保留在 OFL.txt 顶部，随附 SIL OFL 1.1。

CSS: https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@400;600&display=swap

Regular: https://fonts.gstatic.com/s/notosanssc/v40/k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FnYw.ttf

Semibold: https://fonts.gstatic.com/s/notosanssc/v40/k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaGwHCnYw.ttf

正文 19–22 px，标题 35–56 px，数字 600 字重。自动检查覆盖既往缺字“远”和角色名“橙”；其余界面文字随实际截图复核。

## v0.5.1 标题字体

Noto Serif SC Medium，用于24–30px标题与17px木牌文字；正文继续使用 Noto Sans SC。字体未改字形，许可见 OFL-NotoSerifSC.txt。

Google Fonts 官方地址：https://fonts.gstatic.com/s/notoserifsc/v35/H4cyBXePl9DZ0Xe7gG9cyOj7uK2-n-D2rd4FY7SwqyWv.ttf
