# GW01 三年级奥数版最终评审

2026-09-22，Codex原生reviewer `review_gw01` 独立只读评审结论PASS，未发现可验证的P1/P2。

候选 `candidate.json` SHA-256：`4cf0b13b32d465d2b2dfe263e352d3ee222f8c7b2642261492eb2a6c22bb7586`。22项candidate、184项dependencies全部匹配，验证回执、日志与18张截图哈希一致。任务契约为 `docs/production/workshop_gw01_sample.md`。

核查每轮接收数量翻倍、甲乙丙顺序、禁止透支、13/7/4唯一解、完整错误猜测可试运行、实际失败轮次反馈、成功后手动确认、原始配置与轮次存档、禁止不可能前缀、事务安装及搬运守恒、新版独立档案、说明与提示。

独立 `/tmp/gw01-review-v3.gd` 71/71通过：第二轮缺货、第三轮缺货、三轮完成但结果错误、正确解确认和各前缀返回；逐项注入保存失败并重试，检查保存前缀、反馈、读档和动画期间24根守恒。

主会话规则1797/1797，双尺寸原生窗口453/453；评审核验已有回执，没有重复全套或覆盖截图。主会话目视检查摆法界面、试运行轨迹及发现卡。三年级学生的实际理解、挑战感及学习效果仍待真人试玩；不将功能检查等同于难度验收。

## 2026-09-25 后续修复复核

重做后的托盘几何与门禁收口，独立复跑全部通过：

- 候选 `candidate.json` SHA-256：`4f48f75917f47598a8c165d0bcc821a73613f3167d87356e5068a7db6604ab42`（25 项 candidate、185 项 dependencies）。
- 规则 1797/1797、实窗 453/453、共享承重 276/276；三者现在都由 `tests/workshop/run_checks.py` 复跑并写入同一回执。
- 修复：`tests/presentation/support_test.gd` 的工坊黄金点原先停在旧托盘起点（2/276 失败），已按新几何更新；场景不再重复宿主的 `_process`/`_notification`/`_ready`，标题前缀与 `Bridge.origin` 收口到 `workshop_host.gd` 的可覆写钩子；键盘 A/B/C/D 与按钮共用同一条合法性判据。

## 2026-09-25 GW02–GW07 并入后的整表复跑

六关交付并入 main（merge `67ab6a9`）后，`tests/workshop/run_checks.py` 对 GW01–GW07 全表复跑 15/15 通过：GW01 规则 1797 / 实窗 453 / 共享承重 276，GW02 13215 / 203，GW03 433 / 199，GW04 905 / 213，GW05 359 / 243，GW06 14400 / 267，GW07 26615 / 247。

- 候选 `candidate.json` SHA-256：`65ec86d0d2838aec57870348ec26f1cbaa919f138867505477077f4a37dc537d`（9 项 candidate、192 项 dependencies；逐关 runner 改为每关自己的文件集，依赖闭包覆盖共享宿主与运行期美术）。
- 章节标题钩子统一为 `level_host.chapter_label()`，`consumes_origin()` 保留；GW01–07 全部继承 `scripts/workshop/workshop_host.gd`，各关不再覆写 `_ready()`/`chapter_label()`。
