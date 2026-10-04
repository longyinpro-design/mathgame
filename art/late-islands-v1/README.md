# 后三岛统一像素美术 v1

2026-10-04，OpenAI 内置 imagegen 生成。7 张可运行源图，18 个精确 AtlasTexture 区域，覆盖 GV/FW/SO 各 18 关。不是运行时联网生成。

## 风格依据与来源

实际检查了项目已有的 `style-master-v1.png`、森林 `village-v1.png`、集市 `nursery-exchange-stage-v1.png`、工坊 `assembly-room-stage-v1.png`，再以原风格母版与工坊场景做图像参考。保持高细节 16-bit 风格像素簇、青绿与黄铜、暖色左上光、稍俯视的正面 RPG 场景及低噪声操作区域。旧三岛图像未被替换。

- `assets/source/late-islands-v1/geometry-terrace.png`：石匠梯田、山谷、瀑布、木工台
- `fractions-garden.png`：青瓷水庭、莲花、石拱、远景水渠
- `observatory-dome.png`：黄铜星穹、夜色山脊、静态望远镜
- `geometry-cast.png`：棱角普通/欢庆、镜岭守护者、山谷建筑师
- `fractions-cast.png`：水沫普通/欢庆、守水龟、中央莲庭守护者
- `observatory-cast.png`：霁星、星鹭普通/欢庆、抗风守望者
- `surface-textures.png`：木板、石格、青瓷池沿、草地、星图板、禁种岩石

完整提示词位于 `art/prompts/late-islands-v1/`。`manifest.json` 记录参考、54 关映射和每个 AtlasTexture 的实测坐标。角色源图具有真实 RGBA；材质图刻意采用不透明白底，以矩形内部区域取样，不作透明贴花使用。原图不做程序重绘、抠图或缩放改写；Godot 在绘制时缩放。

首次机关拆件及其透明修复尝试仍有烟雾底，已明确弃用，没有进入 assets 或运行时。相关提示词作为生成记录保留，不冒充可用透明素材。

## 实装契约

唯一公共绘制助手是 `scripts/ui/late_island_art.gd`。三个 `world.gd` 只读取状态：背景在底层，材质框次之，数学对象由引擎准确绘制，角色使用脚点锚定且避让交互区。使用最近邻纹理过滤。数字、比例、格数、目标水位、相邻边、对称轴、封存证明、星点、百叶、航线、费用、时刻以及通关灯全部仍由原规则派生。没有烘焙题目答案，没有增加遮挡输入的控件。

本轮没有改动 level_scene、rules、levels.json、共享事务/存档、奖励、按钮或碰撞区域。各岛共有一个主场景，按关卡换真实机制和首领造型；不是 54 张独立背景。角色是离散姿态，不宣称连续行走、骨骼或完整动画交付。

## 权利说明

本批是按用户要求以项目自有素材为视觉参考生成的原创项目素材，没有引入图库或第三方素材包。生成来源为 OpenAI imagegen；未附加外部 CC/MIT 等素材许可，也不声称已对历史参考图的权属做独立法律审查。仓库原有许可范围不因这份来源说明而自动改变。

## 复验

- `godot --headless --path . --script tests/art/test_late_island_art.gd`
- 原三岛规则、事务和真实鼠标 UI 套件继续适用
- 截图、范围和平台边界见 `docs/playtest/late-islands-v1/verification.md`
