# 千灯集市拆件包 v1：给后续关卡开发 Agent

2026-09-19。用户授权将第二批场景美术拆成可开发资源。拆件完成；本文件说明资源接口，不改变关卡数学契约，也不表示 MK02–18 已实现。

**从 `art/market-kit-v1/manifest.json` 开始。** 这是资源 ID、路径、原图区域、锚点、挂点和场景位置的唯一数据源。可直接运行 `tools/market/kit_preview.gd` 查看真实 Godot 拼装。不要重新按4×3等分母版，秤梁、托盘、灯串跨过格线。

## 已交付

- 28 件独立透明 PNG：`assets/runtime/market/kit-v1/sprites/`。
- 同名 28 个 Godot `AtlasTexture`：`assets/runtime/market/kit-v1/atlas/`。与 PNG 二选一，不能两者都画；两种路径表现同一对象。
- 3 张清理后的背景：`assets/runtime/market/kit-v1/backgrounds/`。育苗铺去秤柱；分油庭院去三车和秤柱；大码头去两船和领航灯壳。灯芯街复用原背景。
- 4 个场景的逻辑站位、秤的关节挂点、车的载货位置和领航灯发光中心，均在 manifest 中。
- [浅底部件总览](../playtest/market-kit-v1/preview-5.png)、[深底总览](../playtest/market-kit-v1/preview-4.png)、[铜秤与接货车](../playtest/market-kit-v1/preview-2.png)。

24件既有道具是原母版的精确区域导出，颜色和alpha不重绘。车、两船和领航灯是 image_gen 依据旧背景生成的独立替代件，随后精确切片；不是逐像素原样抠图。新干净背景和替代件作为一套使用，不与旧有同物件背景混用。

## 最小接入

```gdscript
# item 来自 manifest.sprites，world_position 是物品脚底/枢轴/悬挂点。
var sprite := Sprite2D.new()
sprite.texture = load("res://" + item.atlas) # 也可用 item.png
sprite.centered = false
sprite.offset = -Vector2(item.anchor_px[0], item.anchor_px[1])
sprite.position = world_position
sprite.scale = Vector2.ONE * (float(item.suggested_width) / sprite.texture.get_width())
sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
add_child(sprite)
```

- `source_rect` 是母版中的 `[x,y,width,height]`，**不是**游戏摆放位置。
- `anchor_px`、`attachments_px` 都是**裁切后 PNG 内的像素坐标**。普通物件锚点为底部；`scale_beam` 为中心枢轴；`scale_pan` 为上方悬环。
- 挂点世界位置：`position + (attachment_px - anchor_px).rotated(rotation) * scale`。示例脚本包含可运行实现。
- `suggested_width` 是1280×720逻辑视口的起始建议，按所在前后景调整。演示里远景船用90逻辑像素宽；不要把所有场景统一为最大尺寸。
- 背景原图1672×941，显示时统一映射到1280×720；`scenes[].stations` 已是1280×720坐标，不得再次乘源图转换比例。
- 交互区域另建，至少48×48逻辑像素；不要直接使用原始PNG像素范围作为按钮大小。扩大命中区仍须检查邻物争抢和对白遮挡。

## 铜秤组装

用 `scale_stand` 的 `pivot` 放置 `scale_beam`；梁的 `left_hook/right_hook` 放置两份 `scale_pan`。盘的 `cargo` 挂点承托货物或砝码。三种构件用**同一缩放系数**，示例为0.42；不要分别套各自 suggested_width 后强行对接。

只旋转梁，盘随梁端平移并保持水平。示例中的自动摆动纯粹用于看挂点，**不是物理结果或游戏规则**，不得直接复制成玩家摆杯时的实时答案。正式关卡按已有契约，仅提交后呈现称量结果。

## 关卡与资源映射

| 关卡 | 背景 | 建议资源 ID | 开发边界 |
|---|---|---|---|
| MK02 | nursery | copper_fruit、rope_spool、wick_bundle、receiving_tray | 按合同整组交换；货位与库存唯一归属 |
| MK03 | nursery | crate_red、crate_blue、receipt_blank、scale_* | 重签和读数由引擎绘制，提交后复秤 |
| MK04 | nursery | cloth_bolt、oil_bottle、brass_bell、receipt_blank | 原单和转抄件要独立身份，不能只改总数 |
| MK05–06 | street | crate_*、cloth_bolt、oil_bottle、brass_bell、paper_roll、wick_bundle | 包装数量和价格不是图上纤维/钉子数量 |
| MK07–09 | street | rope_spool、nail_pouch、cloth_bolt、brass_bell、paper_roll、oil_bottle、receipt_blank | 每件物件只有一个所有者；配对/重单需真实单号 |
| MK10 | dock | transport_boat_red、transport_boat_blue、crate_* | 船只目前整体平移；近岸航线必须另验前景遮挡 |
| MK11–12、14 | oil | scale_*、weight_*、oil_jug_*、delivery_cart | 三车用3个实例；载货物跟车，别在离场后留下油壶 |
| MK13、15–16 | nursery/street/dock | cloth_bolt、copper_fruit、rope_spool、wick_bundle、paper_roll、brass_bell | 围巾、叶章、邮袋未在本包完成 |
| MK17–18 | dock | parcel_large/medium/small、receipt_blank、navigation_lantern、lantern_string | 首领仍需拆件/骨骼；不能把设定图称为可变形角色 |

`weight_small/hex/stepped`只表示造型。1/3/9和封油量、包装量、单号、价格由关卡合同及引擎标签赋值。空白回执留文本空间，文字不要压到蓝蜡封上。灯串当前为整体，逐灯亮灭需要附加精确发光层；领航灯提供 `light_center`，本包无预烘焙通关光晕。

## 复验与预览

在项目根目录执行：

```sh
# 用手工校准的 manifest 区域重新导出（会重写本包衍生 PNG/tres）
godot --headless --path . --script tools/market/export_kit.gd
# 先完成 Godot 资源导入，首次打开项目也会自动导入
godot --headless --path . --editor --import
# 原像素、覆盖率、透明通道、挂点、路径及原MK01保护核验；需要Pillow/numpy
python3 tools/market/check_kit.py
# 交互预览：左右键切换4场景及浅深底部件页，不修改玩家存档
godot --path . --script tools/market/kit_preview.gd
# 自动截图并退出
godot --path . --script tools/market/kit_preview.gd -- --capture
```

现有证据：28/28导出、207/207检查、原生Godot六页截图成功；已目视核对浅深底、铜秤挂点、船的水面位置。最初沙箱内全项目导入报无法保存用户级 editor_settings，资源本身已导入；最终原生预览正常，无该错误。当前截图为1280×720资产组装检查，不替代具体关卡960×540、触控、实际船车路线或保存恢复验收。

## 协作与未完成项

- 使用现行 `docs/production/market_chapter.md` 的对应关卡合同开发；MK01推理版契约是 `market_mk01_sample.md`，不要把旧八杯解法恢复回来。
- 本包的 ID/路径/坐标是共享接口。关卡 Agent 可读取复用，改锚点或共享图先明确唯一 writer 并升级版本；不要直接重写其他关卡的共享资源。
- 同一工作目录只允许一个 writer。当前无Git仓库，不能假设能创建git worktree；并行只读或在明确隔离的副本开发，整合前比对文件哈希。
- 尚未交付：人物动作、首领骨骼/变形帧、车轮转动和帆摆动、近岸前景遮挡蒙版、游戏所需命中区、正式灯光状态、后续关卡逻辑/存档/奖励。
- 完成一关应验证“剧情靠近→实际操作→提交验收→场景后果”，不要把资源预览当作关卡实现。
