# Six-island implementation interface

This is the new six-island continuation contract. Existing FL/MK/GW rules and save formats remain intact. New islands use the same strict separation: authored definitions → pure mechanism rules → transactional session → input/world rendering.

## Module boundaries

The shared coordinator lives in `scripts/archipelago/`; each island owns a catalog, pure rules, scene and world implementation in its corresponding `scripts/geometry/`, `scripts/fractions/` or `scripts/observatory/` directory. Tests and authored contracts mirror these module boundaries.

IDs GV01–18, FW01–18, SO01–18. Twelve ordinary main + four optional side + two bosses. Side IDs 13–16 never gate main IDs 17–18. Each island has 18 genuinely authored problems and at least several distinct mechanism families; parameter swaps alone are not 18 designs.

## Author catalog (`catalog.gd`, RefCounted)

`static func ids() -> Array` returns 18 ordered IDs.
`static func definition(id: String) -> Dictionary` returns a deep copy with:

- `id`, `island` (`geometry`, `fractions`, `observatory`), `title`, `act` (1–6), `side` bool
- `prerequisites` (same-island ID array), `concept_ids` string array
- `mechanism` stable family ID, `params` validated finite author parameters
- `goal`, `instructions` (visible, concise full legal constraints)
- `intro` and `outro` arrays of 2–4 manual dialogue beats, each text only
- `hints` four increasing tiers or rules can compute contextual hints
- `reward` {`id`: stable unique ID, `experience`: nonnegative int, `keepsake`: string}
- `scene` e.g. `res://game/geometry_gv01.tscn`

Definitions contain NO runtime answer or solution field. Solutions/oracles belong only in tests.

## Pure rules (`rules.gd`, RefCounted)

Instance created as `Rules.new(definition)`; constructor stores a deep copy of the definition.

- `fresh() -> Dictionary`: editable board state only, no scene/file/network
- `validate(state: Variant) -> bool`: closed schema, finite integer quantities, ownership/conservation, legal phases, etc.
- `apply(state: Dictionary, action: Dictionary) -> Dictionary`: return empty dictionary for illegal action, otherwise a NEW validated board; do not mutate the input
- `solved(state: Dictionary) -> bool`: independently recompute actual constraints; accept every legal solution, never just the author sample
- `feedback(state: Dictionary) -> String`: specific unmet constraint after attempted submission
- `hint(state: Dictionary, tier: int) -> String`: tier1–4; contextual next legal step or useful invariant

Submission, dialogue, persistence, retries, completion and rewards belong to shared session/host. For bosses, board can contain staged earned facts/observations and deterministic opponent state; only final true win returns solved. Intermediate advance/probe actions use apply. No win action can bypass rules.

## Scene (`level_scene.gd`, extends `res://scripts/archipelago/level_host.gd`)

One configurable scene script per island is fine, with 18 `.tscn` entry files setting exported `level_id`. Base provides `@export var level_id = ""`. Override:

`configure()` sets `definition = Catalog.definition(level_id)`, `rules = Rules.new(definition)`, `world_script = World`.
`build_board()` adds the actual interactive controls for current board, not a multiple-choice quiz. Can use `add_button(id,text,Rect2,callback,primary=false)` and `add_hotspot(...)`. `act(action)` applies and persists; `board` is current committed state. UI may hold temporary cursor/selection.
`handle_key(key: int) -> bool` optional board shortcuts, return true when used.
`sync_world()` optional extra view-only properties after base installs `world.definition` and `world.state`.

Base scene owns `board`, `definition`, `rules`, `world`, `ui`, `overlay`, `buttons`, `modal`, `stage`, `hint_tier`, `message`, `history`; do not redeclare them. Board area is x40–1240, y210–610. Header/goal y20–78, dialogue/instructions y90–194, bottom controls y650–710. Do not place controls over these areas. Persistent side panel may be inside board if mechanic needs it. All default navigation/hint/undo/reset/submit handled by base.

Useful base hooks/methods: `act(action)`, `refresh()`, `add_button(...)`, `add_hotspot(id,rect,callback,tooltip)`, `draw_label(text,rect,size=20)`, `submit()`, `undo()`, `request_hint()`, `show_modal(text)`, `close_modal()`.

## World (`world.gd`, Node2D or shared presentation_layer)

Fields `definition: Dictionary`, `state: Dictionary`, `presentation_paused=false`. Draw actual board geometry/manipulable objects, stage-specific environmental backdrop and consequences. Actual piece locations/quantities/time states come from state. No baked answer overlays or invisible solution hit boxes. No external art dependency: authored engine-drawn environment is allowed, but must look intentional and be visually checked. Distinct island color/material language. Text uses existing `scripts/cargo/skin.gd` font helpers or fonts.

## Acceptance per island

All18 definitions complete, dependency DAG verified. Independent Python/discrete oracle for feasibility, alternate solutions/optimality where required, and boss legal opponent branches. GDScript tests exercise every level legal completion via real actions (no assigning solved=true), invalid actions, unsolved feedback, closed-schema rejects, input immutability, and save round trips through shared repository. UI tests must exercise real control input, not just direct complete flags; at least one of every mechanism family plus both bosses at 1280×720 and960×540. Shared host tests cover transaction failure, undo/hint history, restart, reward idempotence, pause/resume and back.

All work is local on dot’s computer. No external models, Codex CLI/Cloud/Work/local user computer, push, or deployment. Linux Godot4.6.3 is available; do not claim4.7 or macOS testing.
