# 自动检查（GitHub Actions）

每次向分支推送代码，以及创建或更新 Pull Request，都会运行 **Godot CI**。
在仓库的 [Actions 页面](https://github.com/longyinpro-design/mathgame/actions) 打开对应提交的运行记录即可看结果。

## 检查内容

1. 下载官方 **Godot 4.6.3 stable / Linux x86_64**，按固定 SHA-256 校验。
2. 从干净检出执行 `godot --headless --editor --import`，生成没有提交到 Git 的 `.godot` 导入缓存。
3. 森林 15 组规则、边界、存档事务、迁移、成长与提示检查。
4. 集市 18 关与航图；工坊 18 关与航图规则、无头导航和存档检查。
5. 六岛 9 层检查，包含 108 关通关账本、真实前置衔接、恢复和机关规则。
6. 补充几何独立替代解与首领分支、分数 18 关的完整存档往返。

共调用 65 个 Godot 测试进程。非零退出、超时、引擎/脚本错误、缺少完成标记或断言数不完整都会失败。一个测试失败后尽量继续收集其他测试结果，不会把失败改成成功。

六岛 E2E 的旧三岛完成证据来自版本化自动测试 fixture；旧三岛另外有本轮独立规则/存档检查，但这不等于重新进行 54 关完整画面试玩。

## 看红灯与日志

- 在 Actions 的失败步骤查看错误与具体关卡名
- 运行页面底部的 `godot-ci-运行号-尝试号` 附件保留 7 天，包含资源导入日志、每组测试输出与 JSON 报告
- `ci-results/summary.json` 列出退出码、耗时、完成状态和错误；`import-result.json` 单独保存导入结果
- 不上传用户存档、密钥、整个仓库或 Godot 下载包

## 本地复现

把 Godot 4.6.3 的可执行文件放到 PATH，命名为 `godot`，然后从项目根目录运行：

```sh
python3 -m unittest discover -s tests/ci -v
python3 tools/ci/run_checks.py --import-only
python3 tools/ci/run_checks.py
```

测试使用独立临时存档。结果写入已忽略的 `ci-results/`；原验收脚本也会刷新 `docs/playtest/` 下的自动测试报告，提交前请检查差异，不要把本地报告意外混入业务改动。

## 版本和边界

项目历史 `project.godot` 中保留了 `4.7` 标记；当前自动化基线固定为此前明确验证过的 **4.6.3**。这次没有更改项目版本标记，也不把运行成功说成 4.7 兼容性验收。原生窗口渲染、触屏、可听音频、macOS、性能和儿童真人体验仍须单独验证。

工作流仅使用标准 `ubuntu-24.04` runner、`contents: read` 和固定完整提交 SHA 的官方 checkout/upload-artifact actions；不使用 secrets、不部署、不合并分支、不更改分支保护或付费 runner 设置。

参考：[Godot 4.6 命令行说明](https://docs.godotengine.org/en/4.6/tutorials/editor/command_line_tutorial.html) · [官方 4.6.3 发布](https://github.com/godotengine/godot-builds/releases/tag/4.6.3-stable) · [GitHub 工作流语法](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
