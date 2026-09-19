# MK07 先别把东西平均分 — v1 样板契约

2026-09-20，第三幕「每家都还缺一点」的第三关（`after="MK06"`）。只新增 MK07 自己的文件（三个脚本、入口场景、无头测试、启动脚本与本契约），不改 `kit_world.gd`、`level_host.gd`、`chapter_catalog.gd`、`run_checks.py` 与其他关卡；美术坐标全部来自 `art/market-kit-v1/manifest.json`。

## 目标

- 题目：街头四位居民各缺一样东西，援助货只有绳、钉、布、铃四件，各一件。帆匠能用绳或布，修桥人能用绳或钉，乐手只能用铃，医护只能用布。
- 数学真值：一张二部图的完美匹配。不可替代的两家先把铃与布定死，绳才落到帆匠、钉落到修桥人；唯一完整分配是 帆匠←绳、修桥人←钉、乐手←铃、医护←布。
- 设计陷阱：把布给帆匠完全满足他当面说出的需求，却让医护再没有东西可用。24 种完整分配里只有 1 种通过，其余 23 种都留下一页真实的缺口；唯一性由测试穷举 4! 全排列核对，不由画面宣称。
- 表达边界：苔团的话只说“都分到一件，还得是用得上的那一件”，只交代这一场的约定，不声称公平只有这一种分法。

## 机制与入账时机

- `puzzle` 只看结构：四户各占一件货即可「整批试交」。`shortfalls()` 只报“谁还没分到东西”，不预测整批方案能不能过，也不提前把错误选项藏起来；用不上照样能排上去，交了才知道。
- 演出先入账再结账：`advance()` 从 `puzzle` 进 `stage="handover"` 时不改方案，扣扣抱着四件货一批离开柜台（每件晚 0.06 起步、0.44 走完），落位之前货只在演出里、落位之后只在居民手里，同一时刻不重复出现。
- 演出结束才结账（`handover` 的下一次 `advance()`）：缺口为空进 `delivery`；否则回 `puzzle`，方案原样留在街上、一件货都不扣，只把这个方案记进 `failed`（去重、上限 24，所以 `failed[0]` 永远是第一次真实的失败尝试）。
- 失败回执说的是实情而不是答案：台词位显示“医护还没有能用的布：布在帆匠手里，他也能用绳”，即谁缺、缺哪一件、那件现在在谁手里、他还有没有别的去处；有多家时一次只说第一条并标出剩余条数。它是缺口报告，不自动改摆放、不给出解。
- 撤销与「全部收回柜台」只回退 `plan`；已经发生过的试交记录不跟着抹掉，`cleared_state()` 重新体验时也保留 `failed`。
- 完成后四户各自抱着用得上的那一件站在街上，`extra()` 展开分配单：四行「谁 ← 哪件（他还能用什么）」，加第一次试交落在哪一户、谁缺什么；第一次就交齐则明说“第一次试交就齐了”。
- 无自动求解、无高亮答案、无提示罚分、无失败重演；提示只重述街上已经写着的约束。

## 存档字段

- 入口 `game/market_mk07.tscn`，或双击 `启动千灯集市MK07样板.command`；独立存档 `user://profiles/market-mk07-1/save-v1.json`。`configure()` 只在 `save_path` 为空时填默认值，实窗检查可在 `add_child` 前指定 `/tmp` 路径。
- 字段：`{"sample":"market-mk07-1","stage":arrival|approach|ready|puzzle|handover|delivery|complete,"beat":0..3,"hint":0..3,"plan":[4],"failed":[[4],…]}`。`plan[i]` 是第 i 户拿到的货下标，`-1` 表示还在柜台上；一件货最多一个归属。
- `mk07_rules.gd` 的 `validate()` 把关，拒读并保留原文件的情况：`sample` 不符、未知 stage、`beat`/`hint` 越界、`plan` 含越界值或非 int、同一件货分给两户、`failed` 非数组/超 24 条/含不完整或其实能过的方案/含重复条目、开场三段（`arrival`/`approach`/`ready`）却带着方案、试交记录或提示数、`handover` 没带满四户的方案、`delivery`/`complete` 的方案不是唯一匹配。
- 写档走 `SaveRepository` 的原子事务（tmp + rename）：`handover` 中途保存失败或退出，重载仍停在同一个未落账的方案上，不会发布幻影试交；失败时弹窗给出「重试保存」，读到的坏档不覆盖、原文件保留。
- 过关证据：`stage="complete"` 由 `chapter_progress.level_finished()` 读本关自己的存档判定，航图与前置（`after="MK06"`）不需要额外状态。出口按钮：从航图进来时由宿主挂「集市航图」/「返回集市航图」，单独启动本关时 `exit_buttons()` 补一个同样的出口，不重复。

## 操作与键盘

- 四段剧情靠近（每段一句、`beat` 0..3，第四句之后再 `advance()` 走 `approach` 镜头走近）→ `ready` 说明点击顺序 → `puzzle` 分配 → `handover` 整批试交 → `delivery`/`complete`。`zoom_stages=["ready","puzzle","handover"]`，缩放 1.10、偏移 −64/−43。
- 鼠标：先点柜台上的一件货再点一位居民；再点同一件货把它收回柜台；点已预定出去的居民同样收回；把货点给已经预定了别的货的居民，旧那件自动回柜台。货没有离开柜台，所以任何一步都不消耗资源。
- 键盘：1–4 拿绳/钉/布/铃，Q/W/E/R 交给帆匠/修桥人/乐手/医护，Space 整批试交，Z 撤销上一步，H 提示，Esc 暂停/继续。分配相关的键只在 `puzzle` 且没有演出在跑时生效（宿主统一把关），`handle_key()` 其余键返回 false；Space 在还空着哪一户时不结账，只点名“医护还没有分到东西：只能用布”。
- 热点：`good_0..3` 与 `person_0..3` 共 8 个 62×62 逻辑像素（≥48 下限），由 `target(foot, 62, 58)` 算出、`add_hotspot()` 注册，随镜头一起缩放；提示文案写出这一户能用哪几样。
- 暂停、跳过与失焦只影响演出；`transient > 0` 或弹窗期间热点全部禁用，演出中点不动柜台。

## 边界与已知限制

- 美术缺口：kit-v1 的 `street` 场景没有居民人像拆件（`manifest.json` 只有 `koukou-v1` 两个离散姿态与货物）。四位居民因此用 `plaque()` 身份牌 + `socket()` 落点环 + 该户可用货物的小图标（26 逻辑像素）表达，没有裁新美术，也不是连续动画。补真人像后应替换 `draw_stalls()` 的牌子层。
- 落位动画走共享基座：`level_host.apply_committed()` 已改为先赋 `world.state` 再问 `begin_land(previous)`（此前 `begin_land` 读到旧状态，MK02 的下坠落位实际不触发），MK07 因此删掉了自绘的 `note_drop()`/`drop_rise()`，改由 `begin_land()`（`scripts/market/mk07_world.gd:77`）比对 `previous.plan` 与已提交方案来挂 `land_place/land_slot`，`draw_held()`（`:148`）用 `landing("hand", person)` 驱动预定牌下落 34px、透明度 0.86→0.42，占用宿主 0.28s 的落地锁。拿起货物不占锁。实窗里已证：`tap("person_0")` 之后 `transient > 0` 且 `land_place == "hand"`、`landing("hand",0) > 0.5`、四个热点同时禁用。
- 五户以上、货物多件同类、或需求含“必须两件”这类非线性约束都不在本关表达范围内；`plan` 是 4 长度、值域 −1..3 的一一映射，改规模要同时改 `COUNT`、`ACCEPT`、`SOLUTION` 与存档 schema 版本。
- 唯一性靠代码穷举，不靠人工声明；本关不引入匹配算法或一般求解器，画面也不显示“还剩几种可能”。
- 验证：`godot --headless --path . --script tests/market/mk07_test.gd` → `MARKET MK07 RULES 143/143 PASS`，无 `ERROR:`/`SCRIPT ERROR`，覆盖全排列唯一性与陷阱、每条 stage 迁移、失败留证与不扣货、约 20 条坏档拒读、`restore()` 往返、`shortfalls` 点名到人、提示数与 `hint_texts()` 上限一致、目录一致性与 `ResourceLoader.exists()`、`save_path` 默认值、真实场景实例化的按钮可用性与热点尺寸、写档失败注入与坏档保护。实窗：`godot --path . --script tests/market/mk07_playtest.gd` → `MARKET MK07 WINDOW 170/170 PASS`（1280×720 与 960×540 各一遍，零 `ERROR:`/`SCRIPT ERROR`/`WARNING`），截图在 `docs/playtest/market-mk07-goods/`；窗口化里改掉了回执面板压住货物（右边界 376→360）与回执末两行跑出版面（字号 16→18 下限 + `line_spacing` 归零）两处，并补了 `off_paper()` 守卫——`Control.size` 会被内容最小值悄悄撑大，只量 `spilled()` 看不见纵向溢出。
- 因为落位动画现在真的会占 0.28s 落地锁，`tests/market/mk07_test.gd` 里 25 处连续 `choose_good/choose_person/undo` 需要按 mk06 的先例加 `settle(game)`（`:41-42`）清 `transient` 再刷新；断言总数仍是 143，没有削弱或删除任何一条。
- `tests/market/run_checks.py` 的关卡表里已经有 `mk07` 一行（样板期这一条由集成者统一补，属共享文件）；整表 pass 已由整合者跑过，`docs/playtest/market-mk07-goods/verification.json` 记着这两条检查的条数、退出码与全部源文件 SHA256。自动化通过不代表儿童真实理解度、触屏验收或人物连续动画完成。
