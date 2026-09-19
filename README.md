# 像素数学：数字群岛

当前可玩版本：**v0.7.0 森林来信 · 表现精修版**。从第一袋种子出发，修复村仓与磨坊、整理邮路、结识苔团和折羽，接住石灵的变招，唤醒雾冠树心。

本章包含 **18个主支线关卡、五个探索地区、三位伙伴、两位同行队伍、阿橙一次成长和三项营地建设**。解开每关的机关即可通关；两场首领采用实际战斗机制。游戏离线运行，提示与失败不减少首次奖励。本轮为表现精修：羊皮纸/黄铜界面皮肤、24点改成磨坊能量台（齿轮与能量表盘）、光晶与符石道具化、地区可戳的风味热点、过关后的灯光留存，关卡规则与存档未变。

## 千灯集市 MK01 独立样板

双击 [启动千灯集市样板.command](启动千灯集市样板.command)，体验“到港 → 靠近接货台 → 两次混合测量 → 推断容量 → 交货验量 → 种子上岸”。新版使用独立 `market-mk01-2` 存档，保留首版与森林进度。

森林第一章收尾（`FL18` 之后停在营地）时，营地会出现「千灯集市 · 新的航路」入口，播完渡口请托即接进这一幕；交货完成后从「交完货 · 回营地」回到营地。这一步只是剧情桥接，不发森林奖励、不改森林进度。

蓝白杯的容量签丢了。点货架杯，再点托盘位，每盘摆三只蓝白混合满杯。测量挡板只在整盘倒完后打开；比较挂在左侧的两张回执，自己填回容量签，再接新的交货订单。同种装法重复测量不算新证据；一盘正确也不能直接过关。

支持撤销、确认重摆、主动提示、暂停/跳过和中途恢复。键盘用 Tab/Enter 操作按钮，`1–8` 选杯、`Q/W/E` 放杯、`Space` 验量、`Z` 撤销、`H` 提示、`Esc` 取消选择/暂停。角色仍绘在背景中，杯子、挡板、回执和种子为运行时场景层。

[新版契约](docs/production/market_mk01_sample.md) · [新版验证](docs/playtest/market-mk01-reasoning/verification.json)。复验：`python3 tests/market/run_checks.py`（真实 Godot 窗口，独立 `/tmp` 测试档）。旧目录 `market-mk01` 的视频及报告保留为首版历史。

## 千灯集市 MK02 独立样板

双击 [启动千灯集市MK02样板.command](启动千灯集市MK02样板.command)，或在 MK01 交货完成后点「去育苗铺 · 留下一段线」，体验“到铺听约定 → 镜头靠近柜面 → 整组兑换 → 分挂两处 → 验货交货 → 灯芯离架送往码头、两卷线留在扣扣手里”。使用独立 `market-mk02-1` 存档，不读写 MK01 与森林进度。

育苗铺要交 5 根灯芯，扣扣的捆货绳还差 2 卷线。台面 8 颗铜果，柜面钉着两条公开约定：2 颗铜果换 3 卷线、2 卷线换 1 根灯芯，只能整组换、不能拆半组。铜果必须全部用完，换出的货要在码头交付架与扣扣的修补台之间分干净，这样才只有唯一摆法；把线全换成灯芯会多一根芯、又交不出捆货绳。

兑换先入账再演出，动画中途退出或保存失败都不会多算一组；没摆够时按缺口逐条说明，不逐项判分、不自动摆放。支持撤销、确认重摆、三级提示、暂停/跳过、失焦暂停和中途恢复；坏档拒读并保留原文件。键盘 `1–5` 上交付架、`6–7` 挂修补台、`Q/A` 与 `W/S` 分别按约定一/约定二单组或整批兑换、`Space` 验货、`Z` 撤销、`H` 提示、`Esc` 暂停。

底景、铜果、线卷、灯芯、托盘与空白回执全部来自拆件包 `art/market-kit-v1/manifest.json`，扣扣使用抱货与挥手两个离散姿态；数量、约定和状态文字由引擎绘制。只从 MK01 过来时，完成后另有「办完回礼 · 回营地」回到森林营地，仍是剧情桥接，不发森林奖励、不改森林进度。

[MK02契约](docs/production/market_mk02_sample.md) · [MK02验证](docs/playtest/market-mk02-exchange/verification.json)。复验：`python3 tests/market/run_checks.py` 默认把十八关与航图共 19 项一次跑完（无头规则 + 真实 macOS 窗口），可加参数 `mk01`、`mk02`、`hub` 之类只验一项。

## 千灯集市 · 千灯航图

双击 [启动千灯集市岛.command](启动千灯集市岛.command)，进入 18 关共用的航图：一盏灯对应一张关卡卡，卡片写明第几幕、关卡名和当前状态（待出发 / 已点亮 · 可重玩 / 需先完成 MKxx），点卡片或右下角「下一站」进关，办完事后用关卡里的「返回集市航图」回来。十八关都已建成交互，图上没有空的灯位；从森林营地进岛的旅客在 MK01、MK02 办完事后可直接点「去千灯航图」上岛。

进度档 `user://profiles/market-chapter-v1/save-v1.json` 只由航图写：它逐关读那一关自己的存档（`stage == complete`）作为证据，关卡不需要知道章节档存在，改档或跳关也点不亮别人的灯；坏档保留原文件再另存新档。18 关的编号、幕次、场景、存档路径、前置与一句话目标都取自 [chapter_catalog.gd](scripts/market/chapter_catalog.gd)。

[航图验证](docs/playtest/market-chapter-hub/verification.json)。复验：`python3 tests/market/run_checks.py hub`（无头 48 项 + 真实窗口 28 项，截图在 `docs/playtest/market-chapter-hub/`）。

## 千灯集市 MK03–MK18

余下十六关各自有独立存档（`user://profiles/market-mkNN-1/save-v1.json`）与独立入口 `启动千灯集市MKNN样板.command`，也都能从航图进。目标一句话取自章节目录，细节写在各自的契约里。

| 关卡 | 幕次 | 这一幕要办成的事 | 契约 / 验证 |
| --- | --- | --- | --- |
| MK03 封箱里的重量 | 二 · 扣扣没有偷东西 | 叠合两份称量、消去相同组，给红蓝箱挂上真实重量 | [契约](docs/production/market_mk03_sample.md) · [验证](docs/playtest/market-mk03-weight/verification.json) |
| MK04 不可能兑现的收据 | 二 · 扣扣没有偷东西 | 沿两条原约实换一遍，指出转抄收据错在哪 | [契约](docs/production/market_mk04_sample.md) · [验证](docs/playtest/market-mk04-receipt/verification.json) |
| MK05 四张被雨打湿的货签 | 三 · 每家都还缺一点 | 用留下的线索把四箱货配回四个去处 | [契约](docs/production/market_mk05_sample.md) · [验证](docs/playtest/market-mk05-labels/verification.json) |
| MK06 十根灯芯怎么凑 | 三 · 每家都还缺一点 | 19 张筹票恰好买满 10 根灯芯 | [契约](docs/production/market_mk06_sample.md) · [验证](docs/playtest/market-mk06-packs/verification.json) |
| MK07 先别把东西平均分 | 三 · 每家都还缺一点 | 让四位居民都拿到用得上的那一件 | [契约](docs/production/market_mk07_sample.md) · [验证](docs/playtest/market-mk07-goods/verification.json) |
| MK08 多出来的三瓶油 | 四 · 没有人收到的回信 | 对齐单位，撤下重复副本、补回漏掉的单号 | [契约](docs/production/market_mk08_sample.md) · [验证](docs/playtest/market-mk08-oil/verification.json) |
| MK09 不必两个人就换成 | 四 · 没有人收到的回信 | 牵起交换线，让五摊一次换完且各自满意 | [契约](docs/production/market_mk09_sample.md) · [验证](docs/playtest/market-mk09-cyclic-exchange/verification.json) |
| MK10 无论回哪封信 | 四 · 没有人收到的回信 | 选一条能同时覆盖两种订单箱数的船 | [契约](docs/production/market_mk10_sample.md) · [验证](docs/playtest/market-mk10-fare/verification.json) |
| MK11 砝码也能站在货物旁 | 五 · 公平不只是一样多 | 用 1、3、9 三枚砝码称出恰好 7 单位灯油 | [契约](docs/production/market_mk11_sample.md) · [验证](docs/playtest/market-mk11-scale/verification.json) |
| MK12 不一样多，也都够用 | 五 · 公平不只是一样多 | 按三处各自的需要分封油，一壶不剩 | [契约](docs/production/market_mk12_sample.md) · [验证](docs/playtest/market-mk12-oil/verification.json) |
| MK13 扣扣的旧围巾 | 二 · 支线（MK04 后开放） | 只用整包补边布凑出恰好 11 段 | [契约](docs/production/market_mk13_sample.md) · [验证](docs/playtest/market-mk13-scarf/verification.json) |
| MK14 三枚砝码的小摊 | 五 · 支线（MK11 后开放） | 为 5 与 8 两笔订单分别配一次秤 | [契约](docs/production/market_mk14_sample.md) · [验证](docs/playtest/market-mk14-scale/verification.json) |
| MK15 不会越换越多的铜果 | 四 · 支线（MK09 后开放） | 实演一个闭环，回到 12 颗铜果 | [契约](docs/production/market_mk15_sample.md) · [验证](docs/playtest/market-mk15-copper-nut/verification.json) |
| MK16 给森林寄回一份礼物 | 五 · 支线（MK12 后开放） | 挑 3 样纪念物，带上绿叶章和信纸 | [契约](docs/production/market_mk16_sample.md) · [验证](docs/playtest/market-mk16-gift/verification.json) |
| MK17 铜鹭巡守 · 三次验货 | 六 · 首领一 | 三次验货：用有限的重新封装通过三个码头的装载约定 | [契约](docs/production/market_mk17_sample.md) · [验证](docs/playtest/market-mk17-inspection/verification.json) |
| MK18 万签守约兽 · 让每一盏灯都有回信 | 六 · 首领二 | 让每一盏灯都有回信：一次联合采购，按实际更正回执完成三街交付 | [契约](docs/production/market_mk18_sample.md) · [验证](docs/playtest/market-mk18-lantern/verification.json) |

四条支线都是可选的：在某关之后点亮，办完回到原来的停点，不挡主线。两场首领沿用集市自己的机关，不开新的资源系统。十八关的关卡逻辑、存档与奖励已交付，人物仍是批次一／批次二的整图配离散姿态（无连续走路动画），首领的鹭与万签由引擎变换驱动（无翅膀骨骼）——这一条与逐关限制一并写在各关契约的「边界与已知限制」里，也记在 [美术交接](docs/production/market_asset_handoff.md) 的尚未交付清单中。

## 开始游戏

优先双击 [启动剧情样板.command](启动剧情样板.command) 从送种子开始体验新流程；它使用独立样板存档，后续也能继续完整章节。原有进度仍通过 [启动森林岛.command](启动森林岛.command) 进入。首次运行会先让Godot导入项目资源，再打开当前故事停点。

也可在本机Godot 4.7中打开 [project.godot](project.godot) 按F5，或在资源已经导入后运行：

```sh
godot --path '/Users/long/Code/像素数学'
```

新旅程从送种子的剧情开始：帮站长装吊篮 → 送达拆信 → 循光遇见苔团 → 三门借光 → 苔团加入 → 晨种村。主线由剧情直接交接到机关，解开后接回故事，无需点地面赶路。对白由你继续，动作可暂停或跳过；菜单可随时回营歇脚，再点“继续故事”。手记保留已读对白、邻居的支线邀请和回访入口，支线与重玩结束后回到原主线停点。

- 点选完成主要操作；按钮支持Tab/Enter。数值可点加减，或输入后按Enter提交。
- 地区场景里散落着可以点着玩的小物件（灯笼、水轮、石碑、木桶……），点击只多一句回应，不影响进度。
- 货运支持拖动/点选，以及 `1–7` 选物件、方向键放置、`Space` 松闸。
- `H` 请求伙伴提示，`Z` 撤销，`Esc` 取消或返回。重摆需确认。
- 伙伴页可调整下次出发的队伍与能力。进行中的机关保留开始时的配置，主线基本工具始终可用。
- 设置可调音量、静音和缩短重复演出。没有思考倒计时。

## 森林岛里的挑战

| 地区/阶段 | 可玩内容 |
| --- | --- |
| 树梢站与三门 | 联动吊篮、三门借光、敲响门环看每步回响 |
| 晨种村 | 借粮前后两个时刻、三架灯的合重 |
| 旧磨坊 | 联合账簿、一次试验辨识、四则运算24点 |
| 林间邮路 | 复核分错的邮袋、落石位置比较、证明同行的信最多几封 |
| 回访与成长 | 四件上行货对三块配重的拼趟货运、守门人对局 |
| 四条支线 | 两趟运输、奇偶与步数、两次称量找异晶、借墙花圃 |
| 风枝石灵 | 三枚符石各用一次，依次封盘，根据实际换盘调整后手 |
| 雾冠树心 | 侦察与合击共享15颗种子，辨明真身后保留资源完成恰20合击 |

首领中的观测、消耗和敌方回应先保存再演出。树心撤销会同时回退库存与有效观测，历史情报另记；侦察回响20不等于胜利。

## 存档与旧试玩

正式档使用独立的 `user://profiles/local-1/save-v1.json`，不自动导入v5试玩数据。保存失败保留原已提交状态与同一个待保存候选，界面提供重试，奖励不会重复发放。坏档先保护原文件；明确确认新旅程后，原文件保留为带 `.protected-` 后缀的记录。

旧素材、源代码、历史场景与各版玩家存档均保留。旧版可单独运行：

```sh
godot --path . --scene game/treetop.tscn
```

其他历史入口：`game/journey.tscn`、`game/encounter.tscn`、`game/chapter.tscn`、`game/main.tscn`。它们分别继续使用原有v4/v3/v2/v1记录。

## 验证与当前边界

验证分为设计数学、Godot规则/事务、实际窗口输入及画面QA。逐关真实窗口试玩与显示/交互返修记录见 [执行计划](docs/试玩实现计划.md)，最终精确结果与候选文件身份见 [当前版本验证记录](docs/playtest/v07-verification.json)，表现层截图见 `docs/playtest/v07-presentation/`，模块和存档行为见 [运行时说明](docs/production/runtime.md)。

```sh
# 规则、结算、恢复与故障注入
python3 tests/forest/run_checks.py

# 以上检查加真实Godot窗口输入，依次执行
python3 tests/forest/run_checks.py --windows
```

自动化使用独立`/tmp`存档，并检查脚本/资源错误，不能只凭Godot退出0判定通过。它不证明儿童适龄性、真人思考时间、学习效果或全部首领分支已经被某位玩家掌握。当前验收平台为本机macOS / Godot4.7 / 1280×720，并检查960×540；触屏、其他平台、安装包与发布另验。

[正式制作契约](docs/production/index.md) · [美术资源记录](art/forest_release_assets.json) · [字体与许可](assets/fonts/README.md)

当前目录没有Git仓库，因此没有提交记录；未发布或部署。
