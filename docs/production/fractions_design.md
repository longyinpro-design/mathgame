# 分数水庭 FW01–FW18

> 2026-10-04 美术更新：本页原有程序绘制表现说明是实现阶段记录；当前版本已接入与前三岛同风格的 imagegen 场景、角色和材质，实际状态仍由引擎绘制。见 [本批来源与运行时契约](../../art/late-islands-v1/README.md) 及 [视觉复验](../playtest/late-islands-v1/verification.md)。
Local Godot 4.6.3 implementation. The continuation is authored for the existing island/world and narrative contracts. Twelve ordinary main scenes, four optional scenes (13–16), two staged guardians (17–18). Optional tasks never gate the final two scenes. Companion name is 水沫, consistent with the shared campaign roster.

## Authored sequence

| ID | Physical problem | Distinct constraint |
|---|---|---|
| FW01 | Split one whole pond between two lotus beds | Equal partition creates actual smaller movable pieces |
| FW02 | Assemble three thirds from six sixth-pieces | Equivalent partition, no splitting tool |
| FW03 | Restore halves of differently sized ponds | Whole identity matters, even when both labels describe halves |
| FW04 | Assemble a three-quarter lotus platform | Mixed half/quarter/sixth/twelfth pieces, all conserved |
| FW05 | Send a quarter through a junction | Transfer cannot use water arriving in the same pulse |
| FW06 | Irrigate two flower species together | Two different per-pulse channel quantities and a pulse budget |
| FW07 | Recover the allocation before a half-share gift | Manipulate initial water, then execute the gift |
| FW08 | Recover two ordered gifts | The second fraction is of the changed source pool |
| FW09 | Share a narrow buffer pond | Capacity3; scheduled simultaneous receiving/sending is legal |
| FW10 | Recover surplus through a return canal | Recirculation, unequal returning/distribution channel quotas |
| FW11 | Recover a remaining-water ledger | Ordered thirds/halves with a different total and three pools |
| FW12 | Equalize a four-pool ring | Pipeline transport with conservation and cyclic routing |
| FW13 | Equal water, different leaf counts | Exactly1 versus3 physical pieces |
| FW14 | Repair ceramic lotus petals | Exactly3 pieces per bed forces splitting rather than simple placement |
| FW15 | Catch morning dew within3 pulses | Tight optimum: end pool cannot receive before pulse2 |
| FW16 | Restore two whole-unit mosaics | Split two different wholes, preserve identity across four beds |
| FW17 | Floodkeeper changes a sealed channel | Two earned checkpoints; state carries forward, legal route changes |
| FW18 | Restore the central garden | Three earned checkpoint goals; staged blockades and recirculation |

The guardians have authored deterministic stage responses, not random/hidden opponent branches. The exact blocked channels are visible as sealed controls. Every legal schedule satisfying the actual goals is accepted.

## Runtime separation and numerical contract

- `scripts/fractions/levels.json`: complete definitions, constraints, manual intro/outro beats, hints, rewards and scene IDs. No solution/oracle fields
- `catalog.gd`: deep copies and normalizes authored integral JSON quantities
- `rules.gd`: four pure mechanism families, immutable actions, exact integer micro-units, closed action schema
- Board schema is exactly `{actions: [...]}`. Replay derives every water amount, piece ownership, blockade stage and earned checkpoint. A modified cached win/stage cannot bypass the rules because no cached win/stage is authoritative
- Splitting preserves original whole identity; numerator must divide evenly by the requested partition count; at most24 physical pieces
- Flow is simultaneous: outgoing checks use pre-pulse stocks; capacity checks use resulting stocks. Conservation follows from every edge debit/credit pair
- Reverse gifts require an integral transferable micro-unit, and respect capacities. Inputs are validated before copying; input state and action are never changed
- Up to4096 actions are accepted. This technical bound is visible in instructions; undo/reset remain available. It is not a mathematical move limit. Actual flow pulse limits are explicit and drawn separately
- Shared `archipelago/level_host.gd` and session own all persistence, stage dialogue, undo, reset, hints, pause, submission and rewards. Island code never writes saves

## Presentation and input

18 Control entry scenes use one board script. Each puzzle is operated by actual buttons and pool/piece selection, with no numerical-answer textbox. Whole-labelled physical water strips, proportionally filled ponds, target marks, visible canals/valves, lotus edging, stone borders and 水沫 are engine-drawn. Completion blooms are tied to the shared outcome/complete stage. The illustration is an authored local vector treatment, not external artwork or a claim of finished production animation.

## Validation

Independent Python oracle uses `fractions.Fraction` for reverse gifts, exhaustive assignments/partitions for mosaic feasibility, and discrete reservoir BFS with all legal gate subsets for flow/guardian feasibility and shortest pulse counts. Outputs are test-only `tests/fractions/solutions.json` and `docs/playtest/fractions/oracle_results.txt`.

Godot tests:
- `rules_test.gd`: all18 actual action completions;757 checks of closed schema, invalid actions, immutability, finite values, JSON restoration, four hint tiers, and an alternate equivalent partition
- `session_test.gd`: all18 real shared-session actions and submissions, save/reopen, identical board restoration and exactly one claimed reward
- `ui_test.gd`: actual InputEventMouseButton presses/releases through controls for all18 scenes, at1280×720 and960×540;403 checks per size. Native runs save eight representative start/solved scenes plus earned boss checkpoint screenshots

Native Godot4.6.3 window runs completed all18 levels at each target size,403 real-input checks per size. Start/solved screenshots for eight representative scenes per size and checkpoint screenshots for both guardians are saved in docs/playtest/fractions. Visual review checked the fraction whole strips, distinct piece-count solutions, persistent solved cards, reverse selectors, changing guardian blockade, and readable scaled controls. Minor environmental line/text contrast is tracked separately for a final backing-strip polish. No macOS/Godot4.7, child playtest, external deploy or production art acceptance is claimed.
