# 三粮仓原图样板独立评审

## 功能候选：PASS

- 原生只读子 Agent `/root/review_village_original`；requested / observed 均为 `gpt-5.6-sol / high`，fresh `fork_turns=none`。
- 路由证据：`/Users/long/.codex/sessions/2026/09/19/rollout-2026-09-19T11-30-24-01a0b7b7-167d-7091-96a0-14385a0caff4.jsonl` 的 `turn_context`。
- 已评审9项候选固定在 `reviewed-feature-candidate.json`；最终 `candidate.json` 保留这9项原SHA，仅另增一个测试清理修复。主会话为唯一 writer。
- 核验原图未改、FL02分支/缩放隔离、真实主线衔接、FL03 shift/undo/try/trace、busy锁、先提交后播放、真实结果跳过和960像素画面。
- 检视原图及 initial/moving/story-result/960截图，未发现新的遮挡/悬空。

发现及修复：

1. FL03结果反馈框与粮账摘要相交：本场景反馈高度收至30px；搬运中隐藏相等报告，只显示动作提示。
2. 剧情 setup 只等 `_process` 更新 ground 导致首帧可能保留地台：setup/refresh 同步隐藏。
3. P3：回看后撤销，trace清空而时刻标签残留。标签与画面使用相同trace范围判定；专项补真实trace_1→undo检查。

上述修复均已复核，功能候选无未闭合P0–P3。29/29专项通过；最终综合门禁由主会话负责汇总，评审未并发运行测试。FL03结果演出未单独新增pause/focus-loss逐帧断言，沿用通用故事控制逻辑与已有检查。

## 测试清理差异

最终全量的27套通过；scene_integration行为28/28通过，但快速创建/销毁场景时音频退出诊断未通过严格门禁。仅该测试的dispose_game增加：断开finished→play、stop、stream=null，再按原有流程等待mixer释放、销毁场景。游戏运行时代码未改变，未隐藏引擎错误、未删除断言。

该测试先verbose复验，再连续两次普通实窗复验通过，无资源退出错误。`verification.json` 明确记录复用27套旧证据及重跑1套的来源与唯一输入差异；汇总28套、3737/3737 PASS。

最终测试清理差异由 fresh Luna/medium 独立只读复核，结论 PASS：10项哈希吻合，原9项未漂移，唯一差异仅资源清理，无断言削弱，27套复用与2次单套复验来源如实。实际路由：`/Users/long/.codex/sessions/2026/09/19/rollout-2026-09-19T11-42-32-01a0b7c2-33cd-77f2-a04b-b0594cc1338b.jsonl`。

主会话实际运行路由：Astra/high。全部子 Agent 均无文件修改。
