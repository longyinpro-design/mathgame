# 后三岛 imagegen 美术接入复验

日期：2026-10-04。环境：dot 云电脑，Linux / Godot 4.6.3 / 原生 X11 窗口，Mesa llvmpipe OpenGL Compatibility。没有使用用户本机、Codex Cloud 或 Work 环境。

## 交付范围

7 张源图、18 个实测图集区域，覆盖几何山谷 GV01–18、分数水庭 FW01–18、星穹观测台 SO01–18。每岛一个一致的主场景；按玩法绘制真实机关状态，并切换伙伴和首领。不是 54 张独立场景，也不宣称连续角色动画。

新美术来源、原三岛参考图、完整生成提示词、图集区域及运行时边界见 [美术说明](../../../art/late-islands-v1/README.md) 和 [manifest](../../../art/late-islands-v1/manifest.json)。

## 自动化结果

1. 新资源检查：`tests/art/test_late_island_art.gd`，128 项、0 失败。包括三张足尺寸背景、54 关映射、18 图集区域边界/坐标对应、12 角色区域所在 PNG 的真实 alpha
2. 几何 UI：`tests/geometry/test_ui.gd`，18 关 × 1280×720 / 960×540，0 失败
3. 分数 UI：`tests/fractions/ui_test.gd`，两次分别使用默认尺寸和 `-- small`，每尺寸 403 项，全部通过
4. 星穹 UI：`tests/observatory/test_ui.gd`，18 关 × 两尺寸，0 失败
5. 共 108 关次通过真实 `InputEventMouseButton` 按下/抬起操作，执行合法解、提交、存储重读和奖励记录检查，没有直接设置完成布尔值
6. `tests/art/capture_late_islands.gd`：GV01/GV05/GV17/FW01/FW18/SO01/SO17/SO18 × 两尺寸，共 16 个最终代表场景；入场点击、暂停/恢复不改棋盘、PNG 输出全部通过

7. 最后目检修复 SO17 首领顶部与既有按钮的 19px 遮挡，脚点下移 22px；追加 `-- so17` 两尺寸原生截图与暂停/恢复，0 失败。最新图确认完整轮廓不碰按钮，见 `so17-final-native.log`

全关卡 native 日志位于本目录的 `geometry-native.log`、`fractions-native.log`、`fractions-small-native.log`、`observatory-native.log`。128 项检查见 `art-manifest.log`；最终截图适配见 `capture-native.log`。日志与截图遵守仓库既有媒体忽略规则，不提交二进制测试证据；可以复跑命令重建。

## 视觉检查

实际查看原三岛风格素材后才生成。检查了新三岛开局、几何花圃/石盾、分数四池首领、星穹比例/网络/终章，以及对应 960×540 场景：

- 场景、伙伴、首领和机关材质采用同一像素簇与黄铜/青绿视觉语言
- 角色使用独立透明源图和脚点落地，没有整张图的背景方块；精确切片避开相邻角色
- 数字、已选择片、格数、周长、对称轴、目标水位、阀门、百叶、航线和通关反馈仍来自原状态
- 字体加深色描边/必要的深色背板，亮场景上的文字不依赖背景明暗
- 棋盘位置、单元尺寸、按钮及热区没有改动；装饰层不接收输入
- 保留原来的撤销、提示、暂停/恢复、首领阶段与动态完成反馈

初次机关拆件的烟雾底图未通过透明要求，因此弃用，改为不透明材质图的矩形区域；没把失败素材接入。初版验证用 Texture.has_alpha 在 headless dummy 渲染器得到假阴性，随后改为读取源 PNG 的真实 alpha，并重新通过全部 128 项。

## 平台与验证边界

最初无头编辑器导入已产出所有纹理，但因默认 XDG 目录不可写产生编辑器缓存/设置告警；后续测试全部用工作区独立 XDG 目录。首轮 native 因云桌面没有音频设备而回退 Dummy，未影响输入/绘制；最终截图明确使用 Dummy。Mesa 不支持切换 VSync 的环境告警不构成画面验证失败。本轮没有验证音频设备、Godot 4.7、macOS、触屏或儿童真人体验。旧三岛视觉和规则未修改。
