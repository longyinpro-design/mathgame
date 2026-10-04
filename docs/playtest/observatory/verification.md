# 星台验证记录

2026-10-03，Godot 4.6.3 Linux。

已核实：
- Python独立oracle：18关可解、路径完整性、最优性、替代解、所有3种风暴初局、先修DAG与支线不门控主线
- GDScript规则：18关合法动作及替代解、输入不变、闭合schema、JSON往返，0失败
- 对抗边界：非法/非有限数据、重复对象、损坏百叶、首领阶段伪造、航道/预算绕过，0失败
- Headless真实UI：18关×1280×720、960×540，共36完整动作通关；共享Repository保存重开一致、真实submit/outcome/reward，0失败
- world.gd最后实际航行动画版本单独check-only编译退出0

Native第二轮已完成：全部18关在1280×720与960×540通过真实鼠标输入、保存重开、提交与结算，共36关次，0失败。24张引擎原生截图已保存；覆盖SO01（星图）、SO05（百叶）、SO08（路径目录）、SO11（调度）、SO17与SO18两首领的初态/解态和两尺寸。

人工视觉检查以上六族的1280图及全部六族960解态/首领初态：首轮发现的长说明越界已由显式分行与共享宿主字体测宽修复；轨道标题覆盖刻度已修复；守望者线编号已直接显示。星桌、百叶、线路、时刻条、输入控件与底部操作区互不遮挡，完整约束可读。画面是引擎实际棋盘，不是参考图或预烘焙答案。

`test_voyage.gd`另对独立oracle给出的165个终章网络逐一验证实际绘制航路：只走玩家建成的边，路径长度等于独立Floyd最短路，船从星台出发并在正确岛屿到达，暂停冻结视图时钟；0失败。

Native采用Dummy音频驱动；未验证声卡播放。截图/自动化不代替儿童真人试玩，也不宣称macOS或Godot4.7测试。

命令：

    python tests/observatory/oracle.py
    godot --headless --path . --script res://tests/observatory/test_rules.gd
    godot --headless --path . --script res://tests/observatory/test_adversarial.gd
    godot --headless --path . --script res://tests/observatory/test_voyage.gd
    godot --headless --path . --script res://tests/observatory/test_ui.gd
    godot --path . --script res://tests/observatory/test_ui.gd

需使用隔离的XDG目录和测试存档。Native测试脚本只输出截图、测试存档和日志，不修改玩家既有存档。
