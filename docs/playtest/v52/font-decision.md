# v0.5.2 字体定稿

同一 Godot 1280×720 场景与手记，试排五种组合，截图 trial-*.png。选定 ZCOOL KuaiLe / 站酷快乐体（Google Fonts 原始 TTF）。

| 候选 | 实际观察 | 选择 |
| --- | --- | --- |
| Noto Sans SC Semibold | 清楚但偏普通应用、整段较重 | 未选 |
| LXGW WenKai TC | 有书写感，但小字号细笔画仍偏轻 | 未选 |
| ZCOOL QingKe HuangYou | 字形窄长，正文显得拥挤且机械 | 未选 |
| ZCOOL KuaiLe | 笔画饱满、略有手写变化，角色/木牌/对白的气质更一致 | 选定 |
| Noto Sans SC 无抗锯齿渲染 | 锯齿过硬，当前场景尺度下不如平滑候选易读 | 未选 |

这是当前素材与文案下的主会话视觉判断，不是所有游戏或玩家的通用偏好。此前提及的 Fusion Pixel 作者站点和GitHub发布接口连接失败，未取得字体，未把其他候选冒称为 Fusion Pixel。

定稿：标题28px，正文22px，按钮20px，附属说明18px；数值使用同一家族，常规文字去厚描边，复杂背景仅保留轻阴影，石头数字使用1px细轮廓。对白容器高度依实际行高计算，避免只换字体而不适配容器。符号允许显式 Noto Sans SC 回退，不依赖系统字体。

所有试排候选对当时 scripts/*.gd 中提取的522个不同汉字均覆盖。最终专门检查当前货运/石灵路径309个汉字、0–9数字、23个可见标签、长帮助和按钮宽度；排版检查PASS。实际窗口53/53检查PASS，含960×540。旧测试的90帧等待在高帧率下会先于定时动画结束，现改为2秒有界等待稳定到站，并增加断言；未更改游戏动画或数学规则。

本轮为bounded字体/排版修改，完成主会话自审与真实截图检查。未将字号对照等同于儿童可用性或平板实测。

官方字体来源：
- ZCOOL KuaiLe: https://fonts.gstatic.com/s/zcoolkuaile/v22/tssqApdaRQokwFjFJjvM6h2Wpg.ttf
- LXGW WenKai TC: https://fonts.gstatic.com/s/lxgwwenkaitc/v10/w8gDH20td8wNsI3f40DmtXZb48uK.ttf
- ZCOOL QingKe HuangYou: https://fonts.gstatic.com/s/zcoolqingkehuangyou/v16/2Eb5L_R5IXJEWhD3AOhSvFC554MOOahI4mRIiw.ttf

试排文件仅在.scratch/font-trials中，设.gdignore；运行时仅新增站酷快乐体及其OFL授权文件。
