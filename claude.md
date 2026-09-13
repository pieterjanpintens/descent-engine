# Descent: Legends of the Dark — Mission Tooling: Project Summary

Custom Godot 4 (GDScript) tooling for designing and playing custom missions for
*Descent: Legends of the Dark*, built around the game's physical tile/pillar/stairs
components. Two apps share one data format: a **Mission Creator** (in-game paint
tool) and a **Mission Player** (loads and renders a saved mission).

## Architecture overview

**Note on file layout**: nearly all non-autoload `.gd` scripts (data classes,
`CreatorController`, `MissionPlayer`, `MainMenu`, `LayeredMap`, etc.) physically live
in one flat folder, `scripts/` — the groupings below (`creator/`, `player/`, `ui/`,
`map/`) describe the **scene** files (`.tscn`) and functional area, not the script's
actual directory. This works fine (Godot doesn't care where a script sits relative to
its scene, and several scripts are genuinely shared across Creator/Player). All five
autoload scripts (`FootprintRegistry`, `GameState`, `ComponentInventory`,
`OfficialAssetMap`, `OfficialAssetOverrides` — see **Official asset overrides**
below) live together in `autoload/`. (This folder was called `mission_data/` until it
was renamed to `scripts/` once it held far more than data-resource classes.)

**Data layer** (scripts in `scripts/`) — pure Resource classes, no logic beyond helpers:

- `MissionData` — root resource. Fields: `mission_name`, `grid_size`, `cell_size`,
  `tiles` (Dict[Vector3i, TileEntry] — flattened per-cell walkable/LOS data),
  `floor_placements` (Array[TilePlacement] — raw paint records: origin+mesh+orientation,
  needed to *repaint* the floor GridMap from saved data), `floor_occupied_cells`
  (Dict[Vector3i, Vector3i] — every covered cell → its origin, single-owner —
  floor tiles don't physically stack), `occupied_cells` (the prop equivalent,
  but **multi-owner**: Dict[Vector3i, Array] — every covered cell → an Array
  of every prop's origin cell whose footprint covers it, usually one entry
  but more than one is a legitimate, supported overlap, e.g. a gate inside an
  archway — see `FootprintRegistry.mark_occupied()`/`clear_occupied()` and
  `get_interactable_at()`/`prop_owners_at()`/`resolve_prop_priority()` below
  for how this is populated and resolved back to a single prop -
  `prop_owners_at()` also transparently migrates a cell still in the OLD
  single-owner format (a bare `Vector3i`, from a mission saved before
  this rework - confirmed as a real bug the same day: the very next edit
  that reached `mark_occupied()`/`clear_occupied()` on such a mission
  crashed with `Trying to assign value of type 'Vector3i' to a variable
  of type 'Array'`) into the new Array format on first touch, since both
  functions read through it rather than `occupied_cells` directly),
  `underlay_placements` /
  `underlay_occupied_cells` (floor-equivalent pair for the underlay hazard layer — kept
  as its OWN separate pair rather than folded into `floor_placements`/`tiles`, because
  an underlay hazard physically coexists with whatever floor tile sits on the same
  cells; writing it into the shared `tiles` dict would have one silently overwrite the
  other's `walkable`/`blocks_los` depending on sync order), `interactables`
  (Array[InteractableEntry]), `monster_spawns`, `triggers`, `objectives`,
  `custom_variables` (see **Story layer** below for the last three),
  `player_spawn_cells` (Array[Vector3i] - just cells, no per-spawn metadata
  unlike `MonsterSpawn`; drawn in the Creator with `P`, shown as a yellow
  overlay in the Player before round 1 - see `LayeredMap.gd` and
  `CreatorController.gd`'s controls list), `min_players`/`max_players`
  (both default 1-6, the full `HeroCatalog` range - enforced by
  `EmbarkDialog`, authored via `%MinPlayersSpinBox`/`%MaxPlayersSpinBox` in
  the Creator). Methods: `get_tile()`,
  `is_walkable()`, `blocks_los()` (simplified 2026-09-10 to just the floor
  `TileEntry`'s own flag, once `InteractableEntry.blocks_los` was
  removed as unused — see that entry below), `get_interactable_at()`
  (**reworked 2026-09-13** to resolve through `occupied_cells`' multi-owner
  shape: `prop_owners_at(cell)` returns every prop origin covering a cell,
  `resolve_prop_priority(owners)` picks the single "most specific" one —
  smallest footprint wins, a generic "specific object over a large
  structural one" heuristic requiring no authored priority field, confirmed
  against the real gate-inside-archway case where the gate's footprint is a
  strict subset of the archway's; ties break toward the most recently
  placed. `CreatorController._find_prop_origin()` uses the same two methods
  for raycast select/erase, so Creator and Player always agree on which
  prop a shared cell resolves to),
  `get_level_links_from()`, `get_component_usage()` (tallies floor + underlay +
  prop placements together for `ComponentInventory`). New 2026-09-14, all
  pure derived-view queries over current data (same category as the
  above, no runtime state involved) — see **Story layer**'s "Show Stage"
  entry for how they're used: `is_effectively_visible(node)` (a node's own
  `visible` AND every ancestor `MissionGroup`'s, cycle-guarded ancestor
  walk mirroring `CreatorOutline.is_valid_move_target()`'s own pattern),
  `get_stage_requirements(group_id)` (returns
  `{"floor"/"underlay"/"pillar"/"prop": {mesh_name: count}}` for
  everything under a group recursively that's currently
  `is_effectively_visible()` — pillars split out of `interactables` via
  `FootprintRegistry.allows_fine_placement()`, the existing exact-name
  check for `tall`/`mini`/`medium`), `find_starting_group_ids()` (which
  group(s) cover `player_spawn_cells`, for the auto-revealed starting room),
  `find_node_by_id(id)` (new 2026-09-14, returns whichever
  `InteractableEntry`/`TilePlacement` has that `OutlineNode.id` - searches
  `interactables`/`floor_placements`/`underlay_placements` in that order;
  groups aren't included, they have no GridMap presence to remove; safe
  to search all three since ids are globally unique -
  `allocate_object_id()` is one shared counter across every `OutlineNode`
  subtype, not per-collection - what `Effect.Type.REMOVE_OBJECT` resolves
  through, see `MissionRuntime.apply_effect()`/`LayeredMap.remove_node()`
  and **Story layer**'s `Effect` entry).
- `TileEntry` — mesh_item_name, walkable, blocks_los, region_id. Unrelated
  to `OutlineNode` below despite the similar-sounding `blocks_los` name —
  this is the flattened per-CELL floor logical data, not a placed
  object.
- **`OutlineNode`** (new 2026-09-10, `scripts/OutlineNode.gd`) — shared
  base class for everything that can appear as its own node in the
  Creator's outline tree (see **Creator outline tree** below):
  `InteractableEntry`, `TilePlacement`, and `MissionGroup` all
  `extends OutlineNode` now instead of each separately declaring the same
  four fields. Pulled out once all three ended up needing exactly the
  same thing — GDScript supports `class_name X extends Y` for custom
  Resource classes just as well as for built-in ones. Fields:
  - `id` — stable outline-tree identity, assigned once via
	`MissionData.allocate_object_id()` when first created, never
	regenerated. A caller that reconstructs one of these from scratch
	(e.g. `LayeredMap.sync_prop_cell()`/`rebuild_floor_tiles()`'s
	erase-then-recreate pattern) must carry this over from whatever was
	there before, or it silently orphans the node's identity/group
	membership — see those functions' own comments.
  - `parent_id` — empty = directly under the mission root in the outline
	tree, else another node's `id` (in practice always a `MissionGroup`'s,
	since only groups can be a parent — objects/tiles never are).
  - `reference_name` — optional, human-facing identifier (e.g.
	"front_door") so other props/triggers can reference this node's state
	in a Condition/Effect (see **Story layer**) — and doubles as the
	outline tree's display label when set, falling back to the node's own
	mesh name (or "(unnamed group)" for a `MissionGroup`) when empty.
  - `visible` — plain top-level bool (default true), not a dict key.
	Moved out of `InteractableEntry.props` here 2026-09-10 once every
	`OutlineNode` needed it, not just props with genuinely free-form extra
	data. **Consumed for real 2026-09-14** by `MissionData.is_effectively_visible()`
	(walks a node's own `visible` AND every ancestor `MissionGroup`'s
	`visible`) and `LayeredMap`'s Player-only paint-skip — see **Story
	layer**'s "Show Stage" entry and `LayeredMap.gd`'s own entry below.
- `TilePlacement` — layer (FLOOR/UNDERLAY enum), origin_cell,
  mesh_item_name, orientation, plus everything from `OutlineNode` above.
  Both FLOOR and UNDERLAY placements appear in the outline tree. A WALL
  layer/`WallGridMap` existed earlier but was removed 2026-09-11 (Open
  item #14, done) — the game has no wall concept, it was never used in
  real missions.
- `InteractableEntry` — type (PROP/DOOR/OBJECTIVE/HAZARD/LEVEL_LINK),
  mesh_item_name, origin_cell, footprint (Array[Vector3i],
  rotation-adjusted), orientation, plus everything from `OutlineNode`
  above (`id`/`parent_id`/`reference_name`/`visible`). Also: `props`
  (free-form Dict — "interactible" is the one well-known key left here,
  bool, default true when absent, toggling whether `actions` can
  currently be used; `blocks_movement`/`blocks_los` were removed
  entirely 2026-09-10, unused — `MissionData.is_walkable()` never
  actually read `blocks_movement`, `occupied_cells.has(cell)` alone
  already blocks movement regardless of a specific flag's value; either
  can come back as a `props` key later if a real need shows up), `actions`
  (Array[PropAction] — see **Story layer**), plus
  `link_from_cell`/`link_to_cell`/`link_bidirectional` for stairs
  (LEVEL_LINK type) — **not yet wired up to real stairs instances**, see
  Open Items. This dict is deliberately Object-only — `TilePlacement`/
  `MissionGroup` don't have one, `visible` graduating to `OutlineNode`
  itself is what made that possible.
- `MissionGroup` — a purely organizational node in the Creator's outline
  tree, NOT a spatial/gameplay concept. Entirely `OutlineNode` fields, no
  fields of its own — still its own distinct class (not just
  `OutlineNode` directly) so `MissionData.groups: Array[MissionGroup]` and
  the outline tree's own `SelectionType.GROUP` checks stay meaningful.
  `visible` cascades to a group's members for real now (2026-09-14) - see
  `OutlineNode`'s own entry above and **Story layer**'s "Show Stage"
  entry - `visible` here specifically is what an ancestor-chain walk
  checks at every level, so a group set invisible hides everything under
  it (recursively) regardless of each individual member's own flag.
- `MonsterSpawn` — data model exists, unused so far (no authoring UI, no
  combat/monster AI yet — see Open Items).

## Story layer

Not built from a spec — designed in conversation, working through the actual
game flow first (see the round-loop diagram below) before naming any resource
shapes. Nothing here has a runtime evaluator or authoring UI yet — this is
the data model only, agreed upon 2026-09-10, implementation to follow.

**The round loop** (`RoundCheckpoint.Checkpoint` enum): six named points -
`BEFORE_PLAYER_PHASE` → `PLAYER_PHASE` → `AFTER_PLAYER_PHASE` →
`BEFORE_DARKNESS_PHASE` → `DARKNESS_PHASE` → `AFTER_DARKNESS_PHASE` → loop.
Player phase is where players act and report interactions (the app never
sees real player positions on the physical board - it only knows what gets
reported, matching the original game's own companion app). Darkness phase is
mostly hardcoded monster AI, not condition/effect driven. `NONE` means "not
checkpoint-driven" - see event-driven triggers below.

**One comparison primitive, shared everywhere**: `Condition` (variable_name +
Operator enum + value) and `Effect` (variable_name + value, a SET -
Condition's own read-side). Both
deliberately basic for now - no AND/OR nesting, no cross-object queries, no
increment/expression support. `conditions: Array[Condition]` anywhere in this
system is an implicit AND across every entry.

**`Effect` gained a second kind 2026-09-14, then a third the same day**:
`type` (`Effect.Type` enum `SET_VARIABLE`/`SHOW_STAGE`/`REMOVE_OBJECT`,
defaults `SET_VARIABLE` - every existing saved `Effect` loads at this
default, matching its old behavior exactly, purely additive). `SET_VARIABLE`
is everything described above (`variable_name`+`value`). `SHOW_STAGE`
instead carries `target_group_id` (a `MissionGroup.id`) and means "reveal
this stage" - see **"Show Stage": board setup + group visibility** below.
`REMOVE_OBJECT` carries `target_object_id` (an `InteractableEntry` or
`TilePlacement`'s `id` - not a `MissionGroup`, which has no GridMap presence
to remove) and means "erase this prop or floor/underlay tile from the
board entirely" - requested for a door that should disappear once opened
(matching the physical game's own rule - an opened door token comes off
the board, rather than just being marked open), then immediately
generalized ("in general we should have an effect to remove things") so it
targets any placed prop or tile, picked by name, not a door/gate special
case. See `MissionRuntime.apply_effect()`/`LayeredMap.remove_node()` below
for how removal actually happens - same "runtime queues an id, the caller
with scene access acts on it" split `SHOW_STAGE` already established, since
`MissionRuntime` (a `RefCounted` with no scene/UI access) can't touch
`LayeredMap` itself. All three live in ONE `Effect` type rather than
separate effect classes specifically so every existing
`effects: Array[Effect]` list (`PropAction`, `MissionTrigger`,
`MissionObjective`/its `optional_objectives`) gets Show Stage/Remove Object
for free - no second/third list needed anywhere.

**One variable registry, three ways to fill it**: `MissionVariable` (name +
Type enum [BOOL/INT/FLOAT/STRING] + default_value) declares a custom
variable in `MissionData.custom_variables` - authored via
`MissionVariablesDialog.gd` (new 2026-09-14, see **Creator tooling**
below). **Without a declaration here, a `Condition`/`Effect` referencing
that name is silently inert** - `MissionRuntime._declared_type()` returns
null for an unknown name, so an `Effect` writing it gets skipped
(`push_warning()`) and a `Condition` reading it always evaluates false.
Confirmed as a real bug report 2026-09-14 ("I set up a conditional
action, the effect fires but the condition never becomes true") - the
Condition/Effect were both authored correctly, `key_retrieved` (the name
being written/read) had just never been declared anywhere, because
nothing in the Creator could do that until this dialog existed. The
runtime provides its own
built-ins (round_number, player_count, ...) using the same shape without
being authored. A variable's value can come from: the runtime advancing it
itself (round_number), an `Effect` writing it (a prop action fires), or a
posed yes/no question answered by the table (since some things - "is a
player on tile 2a" - can't be computed, only asked, and the honest answer is
the whole point: "if they lie they ruin their own game"). All three look
identical to a `Condition` reading the variable - "asked" isn't a special
condition type, just a variable source. Type is checked against `type` at
evaluation/mission-load time (push_warning() + skip on mismatch), not in the
Inspector - a per-variable-typed widget would need a custom
EditorInspectorPlugin, more tooling than this needs right now.

**`PropAction`** (on `InteractableEntry.actions`) — action_id + description +
`effects: Array[Effect]`. What a player can report doing to a prop ("push" /
"You can push this lever"). Firing one applies its effects immediately - the
event-driven half of the trigger system below.

`PropAction` also has `conditions: Array[Condition]` (new 2026-09-14,
implicit AND, empty = always available - same convention as every other
conditions list) gating whether this SPECIFIC action is currently
OFFERED at all, e.g. a "search" action only while `chest.searched` is
false. Separate mechanism from `InteractableEntry.props["interactible"]`
(a manual whole-prop on/off switch) - both apply together.
`MissionRuntime.first_available_action(entry) -> PropAction` (nullable) is
a cheap EXISTENCE check (is there anything to interact with at all);
`available_actions(entry) -> Array[PropAction]` returns the FULL
candidate list, in declared order, for a real choice - `PlayerInteractionController`
uses the first for its hover highlight and the second to build a
`PlayerDialog.ask_choice()` picker (Cancel always included) once the drag
is released, so a prop offering several simultaneously-available actions
(e.g. a tree with "pick fruit" and "climb") actually lets the table
choose which one, rather than always firing whichever happens to be
first (see that script's own entry below).

`PropAction` also has `single_shot`/`already_used` (new 2026-09-14, same
one_shot/already_fired shape as `MissionTrigger`, but a deliberately
SEPARATE gate from `conditions` above rather than folded into it -
`conditions` is author-defined state, this is intrinsic "has this action
already fired" runtime bookkeeping, same split `MissionTrigger` already
draws). Requested so an action like "open door" can become permanently
unavailable once used, without needing an author-managed variable just to
fake that. `fire_prop_action()` sets `already_used = true` after firing,
same "mutate the loaded resource directly" safety as
`MissionTrigger.already_fired` (`MissionIO.load_mission()` uses
`CACHE_MODE_IGNORE`, never saved back). `first_available_action()` (the
existence check gating hover-highlight) skips an exhausted single-shot
action, same as one whose `conditions` don't hold - but
`available_actions()` (the picker's candidate list) deliberately does
NOT: an exhausted single-shot action still appears there, so
`PlayerInteractionController`'s `ask_choice()` picker can show it with its
button disabled rather than silently removing it - "the UI must still
show them, but the button must be disabled" was the exact request. Wired
through `PlayerDialog.ask_choice()`'s new `option_disabled: Array[bool]`
parameter (defaults all-enabled, so its one pre-existing caller and any
future one that doesn't care both work unchanged) and
`_set_buttons()`'s new `spec.get("disabled", false)` read - see
`PlayerDialog.gd`'s own entry below. Defaults `single_shot = false`
(unlike `MissionTrigger.one_shot`'s `true` default) - most prop actions
(push, search, talk) are naturally repeatable, this is an opt-in for the
ones that aren't. Authored via a "Single shot" `CheckBox` in
`PropActionsDialog.gd`'s per-action block (see that script's own entry
below) - `already_used` itself has no authoring UI, it's pure runtime
state that's always `false` again the moment a mission is freshly loaded
(Creator and Player never share a live `MissionData` instance).

**"Show Stage": board setup + group visibility cascade** (new 2026-09-14) -
an `Effect.Type.SHOW_STAGE` firing means "reveal this `MissionGroup` as
part of play." Built to deliver on the "exploration" goal `MissionGroup.
visible` was always meant for (rooms behind a door shouldn't be
known/visible until discovered) - firing one does two things, in order:
1. Shows the table a setup dialog listing the physical pieces the
   revealed stage needs - floors, then pillars, then props, then hazards
   (`MissionData.get_stage_requirements(group_id)`, `MissionPlayer.
   _format_stage_pages()`, `PlayerDialog.ask_narrative()` - its first
   real caller).
2. Makes the group (and, by cascade, everything under it whose OWN
   `visible` is also true) actually paintable -
   `MissionData.is_effectively_visible(node)` walks a node's own
   `visible` AND every ancestor group's `visible`; `LayeredMap`'s
   Player-only paint pass (see that script's own entry below) skips
   anything that isn't. GridMap has no per-cell hide, so "invisible"
   really means "was never painted" - a reveal repaints.

Used TWO ways, one mechanism either way:
- **Automatically at game start**, for whichever group contains the
  tile under a `player_spawn_cells` entry -
  `MissionData.find_starting_group_ids()` (converts each spawn
  tile-square to its near-corner fine cell, the same formula
  `LayeredMap.get_tile_square_world_corners()` uses, looks it up in
  `floor_occupied_cells`, resolves that placement's `parent_id`). A
  mission with no groups authored, or whose spawn area isn't grouped,
  contributes nothing - a silent no-op, no regression for missions that
  don't use this.
- **Authored**, like any other effect - attach a SHOW_STAGE `Effect` to a
  `PropAction`'s or `MissionObjective`'s `effects` ("when this door
  opens, reveal the next room"). `MissionRuntime` (a `RefCounted` with no
  scene/UI access) can't itself show a dialog or touch `LayeredMap` when
  one fires, so `apply_effect()` just queues the target group id
  (`_pending_stage_reveals`, drained via `drain_pending_stage_reveals()`)
  for `MissionPlayer` to act on afterward - see that script's and
  `MissionRuntime`'s own entries below for the exact drain points.

`MissionPlayer.show_stage(group_id)` is the actual orchestrator (flips
`group.visible = true` FIRST so `is_effectively_visible()`'s ancestor
walk sees this group - and its now-reachable descendants - correctly
when computing requirements, shows the dialog, then
`LayeredMap.repaint_visible_entries()`) - idempotent, a no-op if the
group is already visible, so a duplicate detection result or a re-fired
trigger can't show the setup dialog twice.

**Referencing a specific instance** — `InteractableEntry.reference_name`
(optional, e.g. "front_door") lets one prop's trigger react to another
named one's state ("if front_door is open, spawn a monster"). No special
resolution mechanism needed - variable names are already free-form strings,
so this is purely an authoring convention: the door's own "open" PropAction
writes a variable named e.g. "front_door.open", and anything else's
Condition just reads that same string. reference_name should be unique per
mission when set - not yet validated in-editor.

**`MissionTrigger`** (reworked - previously a fixed TriggerType enum
[ON_ENTER_REGION/ON_DOOR_OPENED/ON_MONSTER_GROUP_DEFEATED/ON_INTERACT/
ON_MANUAL] plus a free-text `effect_notes` "formal effect system comes
later" field) — now: `checkpoint` (RoundCheckpoint.Checkpoint, NONE if
event-driven instead) XOR `event_id` (non-empty = fires live the instant
that event happens - currently only a PropAction's action_id, but the same
mechanism covers future event sources like "a player dies"/"a monster dies",
deliberately left out of the loop for now), `conditions`, `effects`,
`priority` (int - tie-break among triggers sharing a checkpoint/event, lower
fires first; matters when one trigger's effect writes a variable another's
condition depends on), `one_shot`, `already_fired` (both carried over
unchanged).

**`MissionObjective`** (reworked 2026-09-12 from a flat, checkpoint-keyed
list into a **DAG** — `MissionData.objectives` now holds the DAG's ROOTS,
plural roots allowed, e.g. a main quest tree plus an independent "all
players died" LOSE fail-safe root that isn't nested under anything). A
node has `conditions` (implicit AND, its own "achieved" check), `effects`
(applied once when achieved), `priority` (tie-break among SIBLINGS - nodes
sharing a `children` array, or among the mission's own roots), `children`
(DAG edges - **may be shared**: two different parents' `children` can
reference the exact same instance, since `Resource`s are reference types,
letting branches converge back together), `optional_objectives` (side
objectives valid only while this node is the active one - see
`MissionRuntime` below for what "active" means), and `already_achieved`
(runtime bookkeeping, mirrors `MissionTrigger.already_fired`).
"Final objective" is no longer a separate flag - it's simply a node with
an empty `children` array, and its `outcome` (WIN/LOSE) is only meaningful
there. Reaching one for real actually ends the game - **not cosmetic**:
failing a leaf (a paired LOSE-outcome sibling, or a round-limit baked
straight into a leaf's own `conditions`) is how a branch is lost, not just
won. `checkpoint` was **removed** from this class - see `MissionRuntime`'s
continuous-re-check design below for why a per-node "only check me at this
one checkpoint" restriction became redundant.

**Branch semantics, confirmed with the user during design**: exclusive,
not concurrent. When a node's conditions resolve and it has children, ALL
of them become "current" (watched) candidates, but the FIRST one (by
`priority`) whose OWN conditions later hold wins, and its siblings are
dropped entirely - no per-node "closed" flag needed, see `MissionRuntime.
_check_current_objectives()`. An "and do this too before proceeding" need
is already expressible via `Condition`'s own implicit-AND array on one
node, so no separate join/concurrent-branch concept was added - explicitly
rejected as unneeded complexity for what this project actually needs.
Optional objectives are evaluated **before** the main objective's own
check each tick, so a same-tick "also did the side thing" still counts
right up to the moment the main objective closes it off - the classic
example: main objective "find a way to the cellar", optional "steal a nice
item" - once the cellar is found, the item is no longer stealable (the
door traps the players), and this needs zero special "expiry" code: once
traversal moves past a node, that node just stops being evaluated, so its
optional objectives naturally become unreachable.

**`MissionRuntime` (new 2026-09-11, `scripts/MissionRuntime.gd`)** — the
runtime container `MissionData`'s own class doc used to say didn't exist
yet. `class_name MissionRuntime extends RefCounted` - the first *stateful*
`RefCounted` in the project (`RoundCheckpoint`/`MissionIO` are both
stateless namespaces); `Resource` would be wrong since this is explicitly
ephemeral per-playthrough state, and it has no business as a Node in the
scene tree. Constructed once by `MissionPlayer._ready()` from the loaded
`MissionData`, never persisted/saved back. Holds every variable's live
value in one flat `Dictionary` - both `MissionData.custom_variables`
(seeded from `default_value` at construction, each coerced against its
declared `type`, mismatches `push_warning()` + fall back to that type's
zero value - the validation `MissionVariable.default_value`'s own doc
promised but nothing implemented before this) and the built-ins
`round_number`/`player_count` (kept in sync via `sync_builtins()`, called
by `MissionPlayer` whenever round/roster changes) live in the same dict,
evaluated identically by every `Condition`/`Effect`.
- `evaluate_condition()`/`evaluate_conditions()` (implicit AND, empty →
  true) - look up the variable's declared type (`_declared_type()`: a
  small `BUILTIN_TYPES` const first, else linear search
  `custom_variables`), coerce `Condition.value` against it
  (`_coerce()` - exact `typeof()` match for BOOL/INT/STRING, FLOAT
  additionally accepts and widens a plain `TYPE_INT` so typing `5` instead
  of `5.0` into a float field doesn't spuriously warn), `push_warning()` +
  `false` on an unknown variable or a genuine type mismatch (a null/unset
  `value` falls through this same path automatically - `typeof(null)`
  never matches any declared type, no special-casing needed) - else
  compares the live value against the (coerced) target via
  `Condition.operator`. Now `print()`s every evaluation (variable,
  operator, target, current value, result) - added 2026-09-14 while
  chasing a real "conditional action never becomes available" report, see
  `_declared_type()`'s own entry below for what that turned out to need
  hardening against.
- **`_declared_type(name) -> int`** (changed 2026-09-14 from `-> Variant`)
  - `MissionVariable.Type`, or **`-1`** (was `null`) if `name` isn't
  declared. `Type.BOOL` is enum value `0` - `round_number`/`player_count`
  are both `Type.INT` (`1`), so a caller checking `declared == null`
  had literally never been exercised against a `0` result until a real
  custom `BOOL` variable was declared for the first time 2026-09-14 (once
  `MissionVariablesDialog.gd` made that possible at all). Whether
  `0 == null` actually misbehaves in this Godot version was never
  conclusively confirmed - fixed defensively to an unambiguous int
  sentinel rather than confirm-then-fix, given this project already hit
  ONE real GDScript cross-type `==` bug this same day (see Hard-won
  lessons: `PlayerDialog._on_button_pressed()`'s `int == String`). Same
  defensive treatment applied to `_coerce()`'s own `null`-means-failure
  return (a genuinely-coerced `false`/`0`/`""`/`0.0` is indistinguishable
  from "failed" under `== null`) - every caller now checks
  `typeof(x) == TYPE_NIL` instead.
- `first_available_action(entry: InteractableEntry) -> PropAction` (new
  2026-09-14, nullable) - the first action in `entry.actions` (declared
  order - `PropAction` has no priority field) whose own `conditions`
  currently `evaluate_conditions()` true, or null if none do. Cheap
  EXISTENCE check - `PlayerInteractionController._interactable_at()` uses
  it to decide whether a prop is interactable at all, not which action
  wins.
- `available_actions(entry: InteractableEntry) -> Array[PropAction]` (new
  2026-09-14) - every action in `entry.actions` whose `conditions`
  currently hold, same order, for when the CALLER needs the full
  candidate list rather than just "is there one" - the actual picker UI
  (new 2026-09-14, a real multi-action choice at last - see
  `PlayerInteractionController`'s own entry) reads this.
- `apply_effect()`/`apply_effects()` - branches on `effect.type` FIRST
  (new 2026-09-14, before any of the variable-name logic below, which
  would otherwise misfire on a SHOW_STAGE effect's blank
  `variable_name`): a SHOW_STAGE effect just appends `target_group_id` to
  `_pending_stage_reveals` (this class has no scene/UI access to show a
  dialog or touch `LayeredMap` itself - see **Story layer**'s "Show
  Stage" entry) and returns; a REMOVE_OBJECT effect (new 2026-09-14, same
  branch structure, checked right alongside SHOW_STAGE) just appends
  `target_object_id` to `_pending_object_removals` and returns, for the
  same reason - it can't call `LayeredMap.remove_node()` itself. Everything
  else (a SET_VARIABLE effect, the common case) keeps the SAME coercion/
  warning discipline as conditions, plus one extra rule: writing a
  `BUILTIN_TYPES` key is rejected (`push_warning()` + skip) -
  `round_number`/`player_count` are runtime-owned, never author-writable
  via an `Effect`.
- `drain_pending_stage_reveals() -> Array[String]` (new 2026-09-14) -
  clears and returns `_pending_stage_reveals`. `MissionPlayer` calls this
  right after anything that can apply effects (`evaluate_checkpoint()`
  via `_advance_to()`, a fired `PropAction` via
  `_on_objectives_progressed()`) and `await`s `show_stage()` for each -
  same "return a value, let the caller decide" shape
  `_check_current_objectives()` already uses for ending the game.
  `drain_pending_object_removals() -> Array[String]` (new 2026-09-14,
  same day, identical shape) - clears and returns
  `_pending_object_removals`; `MissionPlayer` calls this right alongside
  the stage-reveal drain (same two call sites) and calls
  `layered_map.remove_node()` for each - no `await` needed, unlike a
  stage reveal there's no dialog to show.
- `evaluate_checkpoint(checkpoint) -> MissionObjective` (nullable) -
  gathers `mission.triggers` whose `checkpoint` matches (a plain `for`
  loop into an explicitly-typed local `Array[MissionTrigger]`, not
  `.filter()` - matches the existing manual-loop convention in
  `MissionData.get_level_links_from()`, sidesteps relying on typed-array
  `.filter()`'s return-typing), fires them via `_fire_triggers()`, then
  returns `_check_current_objectives()` - triggers fire before objectives
  are checked, so an objective can depend on a variable a trigger at the
  same checkpoint just wrote.
- `fire_event(event_id)` - same gather-and-fire, filtered by `event_id`
  instead of checkpoint, THEN also calls `_check_current_objectives()` -
  **overturned 2026-09-12**: objectives used to only ever be checked at a
  checkpoint, never live on an event; that broke the moment "found the
  item" needed to be something a player REPORTS (a `PropAction` firing),
  not something that waits for the next round-loop checkpoint to be
  noticed. `MissionTrigger`'s own event/checkpoint split is unaffected -
  this change is objective-specific.
- `fire_prop_action(action)` - `apply_effects(action.effects)` THEN
  `fire_event(action.action_id)` (now also nullable-`MissionObjective`-
  returning, propagated through this too) - both halves fire per
  `PropAction`'s own doc ("firing one applies its effects immediately -
  the event-driven half of the trigger system").
- `_fire_triggers(candidates)` - sorts by `priority` ascending, then fires
  **sequentially, not as a pre-filtered batch**: skip if `one_shot and
  already_fired`, re-run `evaluate_conditions()` against the CURRENT live
  `_variables` state for each trigger as you go (not a snapshot taken
  before the loop) - this is exactly what `MissionTrigger.priority`'s own
  doc comment is for ("matters when one trigger's effect writes a variable
  another trigger's condition depends on") - only makes sense if
  conditions are re-checked live as effects apply, in priority order. If
  conditions hold: `apply_effects(trigger.effects)`, then
  `trigger.already_fired = true` - mutating the loaded `MissionTrigger`
  resource instance directly is safe, since `MissionIO.load_mission()`
  already uses `CACHE_MODE_IGNORE` for a fresh instance never saved back.
- **`_check_current_objectives() -> MissionObjective`** (nullable, new
  2026-09-12, replaces the old flat `_check_objectives(checkpoint)`) - the
  DAG traversal engine. `_current_groups: Array[Array[MissionObjective]]`
  tracks which node(s) are "current": each entry is a set of mutually
  exclusive candidates (starts as one singleton group per root in
  `mission.objectives`, seeded in `_init()`). Per group, per tick: every
  candidate's `optional_objectives` are checked FIRST (fire once, mark
  `already_achieved`) for every candidate still in the group, not just the
  eventual winner - a side objective stays completable for as long as its
  node is still a live possibility. THEN each candidate's own `conditions`
  are checked in `priority` order; the first to hold wins - its `effects`
  apply, and the WHOLE group is replaced by its `children` (a fresh group
  of new candidates) if any, or returned immediately as the game-ending
  leaf if `children.is_empty()`. Losing siblings are never explicitly
  "closed" - they simply stop being reachable once their group is
  replaced, no per-node bookkeeping needed. Deliberately does **not**
  recurse into a freshly-installed group the same tick (new candidates get
  their first real evaluation on the NEXT call) - keeps this non-recursive
  and incidentally makes an accidentally-authored cycle harmless (see
  `_warn_on_cycles()` below).
- **`_warn_on_cycles()`** (new 2026-09-12) - a DFS from every root at
  construction time, `push_warning()` per back-edge found. Purely
  informational, nothing is stripped: `_check_current_objectives()`'s
  "don't recurse same tick" rule already means a cycle can't infinite-loop
  at runtime - at worst it loops the player back through an earlier group
  on some LATER tick, which might even be an intentional "retry this
  chapter" design, not necessarily a mistake. A DAG (not a strict tree) is
  wanted specifically so branches can converge - cheap structurally (see
  `children` above), this is just the authoring-mistake safety net.
- **`get_current_objective_descriptions() -> Array[String]`** (new
  2026-09-14) - flattens `_current_groups` (every candidate across every
  watched group - already exactly the "what's live right now" traversal
  frontier `_check_current_objectives()` maintains), collecting each
  node's non-empty `description`. What `MissionPlayer.gd` shows the table
  (see that script's own entry below) - reading this instead of
  `mission.objectives` directly is what stops the Player from spoiling a
  DAG branch/leaf nobody has actually reached yet.

**`MissionPlayer.gd` now actually fires triggers/checks objectives at
every checkpoint transition** (Player phase ↔ Darkness phase, round
counter, see that script's own entry above), replacing the five
TODO-commented stubs that used to sit in `_run_darkness_and_loop()`. The
old one-line `_set_checkpoint(checkpoint)` setter is now
`_advance_to(checkpoint) -> bool` (async): updates `current_checkpoint`,
calls `_runtime.evaluate_checkpoint(checkpoint)`, refreshes the objective
label (`_refresh_objective_label()`, see below - a group can be replaced
by its children without reaching a leaf, so this runs regardless of
whether the game just ended), and if an objective
fires, `await`s the shared `_handle_game_over(objective)` (factored out
2026-09-12, see below) and returns `false` so every call site (`if not
await _advance_to(X): return`) stops advancing the round loop rather than
continuing underneath the still-open win/loss dialog. Deliberately **not**
a signal (`objective_reached.emit()` + a connected async handler) -
GDScript signal emission only runs a connected handler synchronously up to
ITS first `await`, then returns control to the emitter regardless of
whether the handler finished, so the round loop would keep advancing
(incrementing `current_round`, re-entering Player phase) while the dialog
was still on screen. The synchronous-computation + bool-returning-
coroutine pattern isn't new here either - it's the same "caller awaits and
branches on the return value" style `embark_dialog.ask_roster()`/
`dialog.ask_yes_no()` already use throughout this file. `current_round`'s
builtin variable is re-synced (`_runtime.sync_builtins()`) immediately
after incrementing, so the next checkpoint's triggers/objectives see the
updated value.

**`_handle_game_over(objective)`** (factored out 2026-09-12) - disables
the End Phase button, shows "Victory!"/"Defeat." + the objective's
description via `dialog.ask_ok()`, then returns to the main menu. Shared
by TWO call sites with deliberately DIFFERENT calling conventions:
`_advance_to()` above (synchronous return-value-checked, to avoid the
signal race described there) and the new
`_on_game_over_requested(objective)` - connected in `_ready()` to
`PlayerInteractionController.game_over_requested`, a genuine signal this
time. **This asymmetry is intentional, not an inconsistency**: a signal is
safe for the event-driven path specifically because nothing in
`PlayerInteractionController` continues an internal loop after
`_end_drag()` that would need to wait on the handler finishing, unlike
`_run_darkness_and_loop()`'s round-advancing chain.

**Still not designed/built**: any authoring UI for triggers/variables
beyond `ObjectivesDialog.gd`'s DAG editor (see **Creator tooling** below
- `Objectives…` in `CreatorSaveLoad.gd` replaced the old single-LineEdit
`%ObjectiveLineEdit` 2026-09-12) and `PropActionsDialog.gd`'s action list
(new 2026-09-13, `Actions…` in `CreatorPropertiesPanel.gd` - see that
entry below) - both cover their own inline condition/effect editors, but
expect new UI surfaces still, e.g. a real
`MissionTrigger` authoring list (nothing edits those yet at all). Custom
variables CAN now be declared - `MissionVariablesDialog.gd` (new
2026-09-14, see **Creator tooling** below) - and a `Condition`/`Effect`'s
`variable_name` field is a real dropdown now too (same day,
`_build_variable_name_option()` in both `ObjectivesDialog.gd` and
`PropActionsDialog.gd` - see those entries below), listing built-ins
(`round_number`/`player_count`) plus every declared
`MissionData.custom_variables` name - no more free-text typo risk for
THIS field specifically; "asked" questions specifically (nothing in the data model yet
marks a
`MissionVariable` as table-answered - `PlayerDialog.ask_yes_no()`/
`ask_count()` exist as the UI primitives, but nothing wires a question's
answer into a variable automatically at some checkpoint, that needs the
authoring UI above first); player count (2-6,
not the physical box's 4 - all 6 playable characters should be usable,
kept as a later difficulty-scaling input, not yet asked for anywhere) and
action economy (3 actions/turn, 1 must be move - the app doesn't need to
enforce this, the physical game already does, move is a "dummy action"
the app can ignore); combat/monster AI (explicitly out of scope for the
first working version).

**Autoloads** (`autoload/`):

- `FootprintRegistry` — the single source of truth for shape/rotation/layer-classification
  math. Key pieces:
  - `FOOTPRINTS` — hand-authored shapes in **tile-square units** (not fine cells),
	keyed by exact mesh item name. Currently has: `1a`/`1b`/`2a`/`2b` (2×3 rectangle,
	origin = bottom-right corner), `7a`/`7b` (plus/cross shape, origin = a specific
	marked cell), `stair` (3×2, origin = the low point), `tall`/`mini`/`medium`
	(pillars — see the calibration note below, **not** `Vector3i.ZERO`), `gate` (2×1,
	single column, origin cell unmarked/assumed), `archway` (4×1, single column),
	`tree` (1×1, listed explicitly for
	visibility even though it's the same as the unlisted default),
	`water`/`acid`/`lava`/`spikes` — the underlay hazard planes (all four share one
	identical 5×4 rectangle — these are hand-authored meshes we control ourselves,
	not measured physical parts, so the pivot was deliberately placed on the
	convention-matching far corner and never needs pivot correction).
  - `CELLS_PER_TILE = 2` — GridMap's cell_size was halved from the tile-square scale
	to support sub-tile pillar placement; this constant bridges "authored in
	tile-squares" to "actual fine GridMap cells."
  - `get_tile_square_footprint()` → raw authored offsets. `expand_footprint()` →
	converts to fine cells. **Critical convention**: an offset represents a square's
	**far corner**, extending backward toward -X/-Z by a full `CELLS_PER_TILE` — this
	took many iterations to nail down, see "Hard-won lessons" below.
  - `rotate_footprint()` / `_rotate_cell_90()` — rotates at **tile-square granularity,
	before expansion** (rotating after expansion rotates around the wrong pivot). The
	single-step rotation includes a `-1` correction because it's rotating a *region*
	(min-corner + extent), not a bare point.
  - `get_layer(mesh_name)` → `"floor"`/`"underlay"`/`"prop"` — the single
	source of truth for which GridMap a mesh belongs in (all three GridMaps share
	**one** MeshLibrary, so nothing else distinguishes them). Tile faces
	auto-detected by name pattern (`^\d+[ab]$`); `water`/`acid`/`lava`/`spikes` are
	explicit `MESH_LAYER` overrides routing to `"underlay"` (no shared naming
	convention to auto-detect from); everything else defaults to
	`"prop"` unless overridden.
  - `LOGICAL_DEFAULTS` (prefix-based) / `LOGICAL_OVERRIDES` (exact-name) — auto-fill
	walkable/blocks_los from mesh naming convention.
  - `mark_occupied()` / `clear_occupied()` — occupancy bookkeeping helpers,
	writing to `MissionData.occupied_cells` (props only — `floor_occupied_cells`/
	`underlay_occupied_cells` stay single-owner, untouched by this).
	**Reworked 2026-09-13 to support overlapping props generically** (was:
	single-owner-per-cell, last-write-wins on `mark_occupied()`, and
	`clear_occupied()` only ever erased a cell's single owner rather than
	restoring a previous one — confirmed as the root cause of a real bug
	where placing an archway over a gate permanently shadowed the gate from
	every cell-based lookup in both Creator and Player, and erasing the
	archway afterward didn't bring the gate back either, since there was no
	concept of "restore the previous owner"). Now each cell maps to an
	Array of every prop origin currently covering it: `mark_occupied()`
	appends (guarded against duplicates) instead of overwriting,
	`clear_occupied()` removes only the clearing prop's own entry from each
	cell's owner list (erasing the cell key entirely only once the list is
	empty) — so two (or more) props can freely overlap, and erasing one
	never disturbs another's claim on shared cells. See
	`MissionData.occupied_cells`/`get_interactable_at()`/`prop_owners_at()`/
	`resolve_prop_priority()` above for how a single "the" prop gets
	resolved back out of a multi-owner cell, and
	`CreatorController._find_prop_origin()` for the Creator-side raycast
	counterpart.
- `ComponentInventory` — tracks physical piece counts so the Creator can block designs
  that need more copies of a tile/pillar than physically exist. `MESH_TO_GROUP` groups
  both faces of a double-sided tile (`1a`/`1b`) into one shared count pool (they're one
  physical object) — the underlay hazard cards are double-sided the same way:
  `water`/`spikes` share one physical card (group `card_water_spikes`, max 4), and
  `lava`/`acid` share another (`card_lava_acid`, max 4) — these are **real, confirmed
  counts**, unlike the rest of `MAX_COUNTS` which is still placeholder numbers pending
  the actual physical component list.
- `GameState` — trivial: holds `current_mission_path` to pass between scenes (menu →
  player) since `change_scene_to_file()` takes no parameters.
- **`CreatorSettings`** (new 2026-09-10, renamed from `EditorSettings` the
  same day after the autoload silently failed to register — Godot 4 has
  its own **built-in engine class also called `EditorSettings`**, part of
  the real editor's own settings/preferences API, and the custom autoload
  collided with that global identifier. See the naming-collision note
  under **Hard-won lessons** below) — persisted Creator preferences,
  currently just the autosave/backup system (see `CreatorAutosave.gd`
  under **Creator tooling** below). Six plain fields: `enabled` (bool,
  **defaults to false** — an opt-in safety net shouldn't start writing
  files before the user has actually opened the settings dialog once,
  even though every other field has a live-with-it default),
  `backup_location` (`String`, default `"user://missions/backup"`),
  `copies`/`save_interval_minutes` (the frequent/shallow "recent" tier,
  defaults 10/1), `checkpoint_copies`/`checkpoint_interval_minutes` (the
  infrequent/deeper "checkpoint" tier, defaults 2/15). `load_settings()`/
  `save_settings()` round-trip through a `ConfigFile` at
  `user://configuration/editor-settings.cfg` — **not** `res://`, even
  though the original request asked for `res://configuration/...`: this
  project's Creator ships as an exported Windows `.exe` (see **CI /
  Release** below), and `res://` is packed into a read-only `.pck` in an
  exported build - writes there work from inside the Godot editor but
  silently fail (or are undefined) from the actual shipped tool. `user://`
  is Godot's dedicated writable-everywhere location for exactly this -
  see `OfficialAssetOverrides`'s own entry above for the existing
  precedent in this project. `save_settings()` emits `settings_changed`
  so anything live (`CreatorAutosave.gd`) picks up new values immediately,
  no scene reload needed.

**Core logic** (`map/`, root of the reusable scene):

- `LayeredMap.gd` — attached to `LayeredMapCore.tscn`'s root. Owns `floor_grid`/
  `prop_grid`/`underlay_grid` (@onready refs to child GridMaps) and
  `mission`. `_ready()` positions the non-floor layers relative to floor: `prop_grid`
  sits `+floor_thickness` above (so props render on top of the floor surface);
  `underlay_grid` stays at the SAME Y as floor (`Vector3.ZERO`, not offset below it)
  — it's meant to show through exactly where the floor doesn't cover it, not sit
  hidden beneath. Two directions of sync:
  - **Read** (painting → data): `sync_prop_cell(origin, new_parent_id: String = "")`,
	`rebuild_floor_tiles(new_placement_parent_id: String = "")`, and
	`rebuild_underlay_tiles(new_placement_parent_id: String = "")` walk the
	painted GridMap cells and populate `MissionData`. Underlay is a
	deliberately SEPARATE rebuild pass from floor (not a third case folded
	into `rebuild_floor_tiles()`) — see the `underlay_placements` note
	above for why. **`new_parent_id`/`new_placement_parent_id`** (new
	2026-09-14) is `CreatorController.working_group_id` threaded through
	from `_sync_after_edit()` — only ever consulted for a genuinely NEW
	placement (no previous entry at that origin to carry `parent_id`
	forward from, see the carry-over fix just below), so a designer's
	current working group is what a freshly-drawn object/tile lands in
	instead of always defaulting to the mission root. Safe under the
	full-rebuild design because exactly one new origin cell appears per
	rebuild call triggered by a single placement — every other origin
	already matches something in that function's own `old_by_cell` lookup
	and takes the carry-over branch instead. All existing callers
	(`DebugSync.gd`, `erase_at_cursor()` — erasing never mints a new entry,
	so the param is simply unused there) keep working via the `""` default.
	- **Hard-won lesson, 2026-09-10**: `sync_prop_cell()` always erases
	  whatever `InteractableEntry` was at that origin cell and constructs a
	  brand-new one, even when "erasing" is really just a repaint (mesh or
	  orientation correction) of the same logical object. Once
	  `InteractableEntry` gained an `id`/`parent_id` (see **Creator outline
	  tree** below), this would have silently orphaned an object's outline-
	  tree identity and group membership on every such repaint. Fixed by
	  explicitly carrying `id`/`parent_id`/`reference_name`/`props`/
	  `actions` over from the entry that was just there before
	  constructing the replacement — see this function's own comment. The
	  kind of bug this project has been bitten by before (see the tile-
	  square snapping off-by-one below) — an erase-then-recreate pattern
	  silently dropping state nobody was watching for.
  - `signal mission_objects_changed` — fires whenever `mission.interactables`
	or `mission.groups` changes shape (from `sync_prop_cell()`,
	`apply_mission()`, or `notify_objects_changed()` — the last one for
	callers, like `CreatorOutline.gd`'s group CRUD, that mutate `groups`
	directly without going through GridMap painting at all). The Creator
	outline tree's only signal to listen to for "go rebuild".
  - **Write** (data → painting): `apply_mission(mission, respect_visibility: bool = false)`
	clears and repaints all four GridMaps from a loaded `MissionData` —
	used identically by both the Player (to render a loaded mission) and
	the Creator (to open an existing mission for continued editing). The
	actual per-entry paint loop now lives in a separate `_paint_all()`
	(new 2026-09-14, factored out so it can be re-run without re-clearing
	first — see `repaint_visible_entries()` below). `respect_visibility`
	defaults `false`, so every pre-existing call site (Creator,
	`DebugSync.gd`) is unaffected — only `MissionPlayer._ready()` passes
	`true`: GridMap has no per-cell hide, so making `MissionGroup.visible`
	cascade for real (see **Story layer**'s "Show Stage" entry) means
	`_paint_all()` simply never calls `set_cell_item()` for an entry that
	isn't currently `MissionData.is_effectively_visible()` — "invisible"
	means "never painted", not hidden after the fact. `_respect_visibility`
	is the new instance var this gets stored in.
  - `repaint_visible_entries()` (new 2026-09-14) — call after mutating a
	group/node's `visible` elsewhere (`MissionPlayer.show_stage()`) so the
	GridMaps catch up; a no-op unless `apply_mission()` was called with
	`respect_visibility` (the Creator never needs this). Just re-runs the
	WHOLE `_paint_all()` pass rather than diffing "what's newly visible" —
	re-painting an already-correctly-painted cell is harmless
	(`set_cell_item()` just sets the same item again), so a full rescan is
	simplest-first correct with no per-entry "was this hidden" bookkeeping.
  - `remove_node(id)` (new 2026-09-14) — the Player-runtime counterpart to
	Creator's `erase_at_cursor()`: erases a placed prop or floor/underlay
	tile from its GridMap and `MissionData`, by `OutlineNode.id`, resolved
	via `MissionData.find_node_by_id()`. Fired by an authored
	`Effect.Type.REMOVE_OBJECT` — see **Story layer**'s `Effect` entry and
	`MissionRuntime.apply_effect()`'s own entry for the full mechanism. A
	prop (`InteractableEntry`) resyncs incrementally via the existing
	`sync_prop_cell()` (erase the GridMap cell first, THEN call it, so it
	takes its own "cell already erased" branch instead of the carry-over
	repaint branch — same sequence `erase_at_cursor()` already uses); a
	floor/underlay tile (`TilePlacement`) has no incremental single-cell
	sync (same as `CreatorController._sync_after_edit()`'s existing
	routing for those two layers), so it goes through a full
	`rebuild_floor_tiles()`/`rebuild_underlay_tiles()` instead — branches
	on `node is InteractableEntry`/`is TilePlacement` (with an explicit
	`as` cast either way, since GDScript doesn't narrow a variable's
	static type after an `is` check — confirmed against this project's
	own existing `CreatorPropertiesPanel.gd` precedent before assuming
	it). Composes correctly with the same day's earlier overlapping-props
	fix for free: erasing a door that shares cells with something else
	(a gate under an archway) only clears the door's own
	`occupied_cells` claim via `FootprintRegistry.clear_occupied()`.
	Removing a floor tile makes that cell unwalkable
	(`MissionData.is_walkable()` already returns false once
	`get_tile(cell)` is null) — not a new rule, just newly reachable from
	an effect instead of only a Creator-side erase.
  - `find_item_id(grid, mesh_name)` — MeshLibrary name→id lookup (public, used by
	`CreatorController` too).
  - `set_spawn_overlay_cells(cells)` / `set_spawn_overlay_visible(bool)` — the
	yellow player-spawn-area overlay (see `MissionData.player_spawn_cells`),
	a filled-quad `ImmediateMesh` (same corner-based box-building approach as
	`CreatorController`'s occupancy overlay, but triangles not lines). Lives
	here rather than duplicated in `CreatorController`/`MissionPlayer` since
	both instance this same scene and both need to show it - Creator while
	drawing it, Player before round 1.
- `MissionIO` (`scripts/MissionIO.gd`) — static `save_mission()`/`load_mission()`
  wrapping `ResourceSaver`/`ResourceLoader`. Verified round-trip correctness including
  nested Resources, typed arrays, and Vector3i-keyed dictionaries.

**Creator tooling** (`creator/`):

- `CreatorController.gd` — the in-game paint tool (mimics Godot's own GridMap panel,
  but as a runtime game feature). Public API (`select_mesh`, `cycle_mesh`,
  `select_layer`) is deliberately the only thing that touches selection state, and it
  emits `layer_changed`/`mesh_changed` signals whenever that state actually changes
  (from either keyboard input or `CreatorPalette` calling these same methods) — this
  is what keeps the two paths from ever drifting out of sync.
  - **`working_group_id`** (new 2026-09-14, `set_working_group(group_id)` +
	`signal working_group_changed(group_id)`, same plain-tool-state
	convention as `draw_mode`/`spawn_paint_mode`) — the group any NEW
	placement's `parent_id` gets set to (`""` = mission root, same as
	before this feature existed), threaded through `place_at_cursor()` ->
	`_sync_after_edit()` -> `LayeredMap`'s sync functions (see that
	script's own entry above). Lets a designer focus on filling in one
	room at a time without manually re-parenting every object afterward
	via the outline tree's "Move to…" menu — the UI is the persistent
	toolbar's "Working group:" dropdown (`CreatorToolbar.gd`, moved there
	2026-09-14 from the Outline tab so it stays reachable while actually
	drawing in the Palette tab - see **Creator tooling** below), not owned
	here; this script only holds the state and fires the signal.
  - **`show_unavailable_meshes`** (new 2026-09-14, `set_show_unavailable_meshes(enabled)`
	+ `signal show_unavailable_meshes_changed(enabled)`, same convention) —
	whether `CreatorPalette`'s mesh grid shows exhausted meshes (greyed out,
	click-to-locate) or leaves them out entirely. Moved here from a private
	`CreatorPalette` var so the toolbar checkbox that controls it
	(`CreatorToolbar.gd`) and the palette that reads it stay decoupled -
	same "controller emits, UI listens" reasoning as `working_group_id`
	above.
- **`CreatorToolbar.gd`** (new 2026-09-14, attached to `Toolbar`, a plain
  `HBoxContainer` sibling of `MenuBar` under `MainLayout` — see
  **Scene structure** below) — the Creator's persistent, always-visible
  toolbar: a "Working group:" `Label` + `OptionButton` on the left, a
  `Control` spacer (`size_flags_horizontal = SIZE_EXPAND_FILL`) pushing
  the rest right, then a "Show unavailable (click to locate)" `CheckBox`.
  Both controls used to live inside a specific `SidePanel` tab
  (`CreatorOutline.gd`'s tree, `CreatorPalette`'s mesh grid respectively) -
  moved out the same day they were added, once it became clear a designer
  actually wants to reach both regardless of which tab happens to be
  active (working group while drawing in the Palette tab; show-unavailable
  while browsing the Outline tab). Built entirely in code in `_ready()`,
  same pattern as every other dynamic Creator UI piece. Talks to
  `CreatorController` ONLY through its public API/signals -
  `working_group_id`/`set_working_group()`/`working_group_changed` and
  `show_unavailable_meshes`/`set_show_unavailable_meshes()`/
  `show_unavailable_meshes_changed` (both entries above) - same
  "controller emits, UI listens" convention as `CreatorPalette`.
  `_rebuild_working_group_option()` duplicates the same small "Root +
  groups" list-building loop `CreatorOutline.gd`'s own near-identical
  builders (the "Move to…" submenu, `CreatorPropertiesPanel.gd`'s
  batch-move dropdown) already use, rather than sharing it - matches this
  project's established convention of each UI piece owning its own
  near-identical widget-building code. Coalesces `layered_map.
  mission_objects_changed` (fires once per painted cell during a drag
  stroke) into a single deferred rebuild, same pattern as `CreatorOutline.
  gd`'s `refresh()`/`_do_refresh()`.
- **`CanvasLayer/MainLayout`** (`MissionMap.tscn`) — the Creator's overall
  shell, a full-rect `VBoxContainer`: a top-spanning `MenuBar` (see
  `CreatorSaveLoad.gd` below), a persistent `Toolbar` (`CreatorToolbar.gd`,
  see its own entry above) beneath it, then an `EditorArea` `HBoxContainer`
  holding the 3D view's space on the left and `SidePanel` on the right —
  the redesign requested 2026-09-10 to replace the ad-hoc toolbar row (see
  Open item #12). **Not a real `HSplitContainer`** — that only splits
  between two `Control`s, and the 3D scene renders straight to the main
  viewport rather than through a `Control`/`SubViewport`, so there's no
  second `Control` to split against without a much bigger refactor
  (`SubViewportContainer` + `SubViewport`, which would also change
  `CreatorController`'s screen-space mouse-ray math). Took the fallback the
  request itself offered instead: `SidePanel` gets a static
  `custom_minimum_size` (260px) and the left side is just an empty
  `ViewportSpacer` `Control` that reserves layout width — the 3D content
  itself isn't inside it at all, it's simply visible through/behind the
  CanvasLayer wherever no opaque 2D Control covers it.
  - **Critical, and a repeat of the `CreatorPalette` mouse_filter lesson
	below**: `MainLayout`, `EditorArea`, and `ViewportSpacer` all
	explicitly set `mouse_filter = MOUSE_FILTER_IGNORE`. Left at the
	default `STOP`, any one of them — being full-rect or full-height
	Controls sitting directly over what used to be uncovered screen space —
	would silently swallow every click/drag meant for `FreeLookCamera` and
	`CreatorController`'s paint/erase input, the same way `CreatorPalette`'s
	background once did. Only `MenuBar` and `SidePanel` keep the default
	`STOP` (desired — clicks on the menu bar or the palette/properties tabs
	should NOT fall through to the 3D world).
- **`SidePanel`** (`CanvasLayer/MainLayout/EditorArea/SidePanel`) — a plain
  `TabContainer`, no script, now one level deeper than before (nested in
  `EditorArea` rather than anchored directly to `CanvasLayer`). Two tabs
  (title = child node name, Godot's own `TabContainer` default): `Palette`
  (the existing `CreatorPalette` — see the correction below, its
  self-anchoring code was NOT actually inert) and `Outline` (was called
  `Properties`, renamed 2026-09-10 once it grew the object-browser tree —
  see its own entry below).
- `CreatorPalette.gd` (attached to `MissionMap.tscn`'s
  `CanvasLayer/MainLayout/EditorArea/SidePanel/Palette`) — the real palette UI: clickable layer tabs
  (Floor/Prop/Underlay, plus a 4th "Misc" tab - see below) plus a
  scrollable icon grid for whichever mesh layer is active, replacing blind
  `,`/`.` cycling as the primary way to pick a mesh
  (keyboard cycling still works side by side). Built entirely at runtime in
  `_ready()`/`_build_ui()` rather than hand-authored as child nodes in the
  `.tscn` — same pattern `CreatorController` already uses for its
  ghost/grid/origin/occupancy overlays, and the mesh grid's contents are dynamic
  (depend on `MeshLibrary` contents) so couldn't be static `.tscn` content anyway.
  Icons come from `MeshLibrary.get_item_preview()` (Godot auto-generates these per
  item) rather than hand-made icon assets.
  - **Correction, 2026-09-10**: `_build_ui()` used to also call
	`set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)` on itself,
	on the assumption (stated in earlier revisions of this doc, and never
	actually verified in-editor) that `TabContainer` would harmlessly
	override it once `CreatorPalette` became a tab child. **It did not** —
	confirmed in-editor: `PRESET_RIGHT_WIDE` spans the full height from
	y=0, ignoring the tab bar's own height, so this row rendered on top of
	and ate clicks meant for `SidePanel`'s own Palette/Outline tab labels
	(the user couldn't switch tabs at all). Removed — a `TabContainer`
	child with `layout_mode = 2` should never also self-anchor; the
	`custom_minimum_size` hint alone (still kept) is enough. Worth
	remembering as a "hard-won lesson": manual anchor-setting code on a
	Container-managed child isn't reliably harmless just because the
	Container usually wins — verify, don't assume.
  - **Correction, 2026-09-10**: availability (which meshes show as
	greyed/hidden once `ComponentInventory`'s physical limit is hit) used
	to only refresh on a layer switch or the "Show unavailable" checkbox -
	painting the SAME mesh repeatedly (e.g. several floor tiles in a row
	without switching mesh, a very common way to paint) never triggered
	`_rebuild_mesh_grid()` at all, so an exhausted mesh stayed shown as
	available until something else forced a refresh. Fixed by listening
	to `LayeredMap.mission_objects_changed` too (now fires for floor/
	underlay edits as well as props, see that signal's own entry above),
	routed through a `call_deferred()`-coalescing `_queue_mesh_grid_rebuild()`
	wrapper (same pattern/reasoning as `CreatorOutline.refresh()`) since
	that signal can fire once per painted cell during a fast drag stroke.
  - **"Misc" tab** (requested 2026-09-10, replacing an earlier "put D/P on
	a second toolbar" idea) — a 4th tab button alongside the three mesh
	layers, for tools that aren't mesh-library-backed at all and so don't
	belong in the Floor/Prop/Underlay grid. Not a
	`CreatorController.PaintLayer` — purely a `CreatorPalette` presentation
	concept, `CreatorController` has no idea this tab exists. Clicking it
	(`_on_misc_tab_pressed()`) hides the mesh grid/"Show unavailable"
	checkbox, shows `_misc_container`, and turns `draw_mode` off — **bug
	fix, 2026-09-10**: that last part was missing at first, so the green
	mesh-placement ghost stayed visible after switching here (nothing had
	told `CreatorController` the previously-selected mesh no longer
	applies; `_update_ghost_transform()` already hides the ghost whenever
	`draw_mode` is false, it just needed something to actually flip that
	on this specific transition). Deliberately does NOT touch
	`spawn_paint_mode` - Player Start lives IN this tab, so merely
	switching here shouldn't turn its own tool off. `_misc_container` is a
	plain `VBoxContainer` of tool entries — built that way specifically so
	more can be appended later without restructuring anything, per the
	user's own framing ("in the future we might need some similar things
	like player start"). Holds
	one entry so far: a **Player Start** toggle button
	(`_on_player_start_tool_pressed()`), the discoverable counterpart to
	the `P` hotkey (`spawn_paint_mode` — see `CreatorController`'s own
	entry above) — clicking it calls `set_spawn_paint_mode(true)` and
	`set_draw_mode(false)`, mirroring how picking a mesh/layer calls
	`set_draw_mode(true)` and `set_spawn_paint_mode(false)`, so the two
	tools stay mutually exclusive regardless of which one you engage from.
	The button's own pressed state stays synced to `spawn_paint_mode_changed`
	so it reflects reality even when toggled via the `P` hotkey instead.
  - **Two display modes**, via `CreatorController.show_unavailable_meshes`
	(the checkbox itself moved to the persistent toolbar 2026-09-14 - see
	`CreatorToolbar.gd` under **Creator tooling** - this palette just reacts
	to the controller-owned state now, `creator_controller.show_unavailable_meshes_changed`
	queues a mesh-grid rebuild the same way `mission_objects_changed` does):
	default hides any mesh
	that's hit its `ComponentInventory` physical limit entirely (the palette only
	shows what you can currently draw). Checked, it shows everything and greys out
	exhausted ones — clicking a greyed entry doesn't select it (there's nothing left
	to place), it instead calls `CreatorController.locate_mesh()`, which finds the
	first placed instance in the mission and calls `FreeLookCamera.jump_to()` to
	snap the camera there. `jump_to()` deliberately updates the camera's internal
	`_yaw`/`_pitch` too, not just `rotation` directly — otherwise the next
	right-click-drag would compute rotation from the stale stored values and the
	camera would snap back to its pre-jump orientation.
  - **Critical design point**: the *destination* GridMap for a placement is always
	derived from `FootprintRegistry.get_layer(selected_mesh)` (via `_target_grid()`),
	**never** from the UI's current layer filter (`current_layer`/`L` key) — the
	filter only controls which meshes `cycle_mesh()` offers to browse. This was a real
	bug once (props landing in FloorGridMap) and is now structurally prevented.
  - Placement: raycast/plane-intersection based hover picking, ghost mesh preview,
	rotation (`R`), physical-limit checking before placing (`ComponentInventory`).
  - Erase: **real physics raycast** against GridMap collision (not plane math) —
	translates the hit cell back to the actual painted origin via
	`occupied_cells`/`floor_occupied_cells`/`underlay_occupied_cells`, with a
	column-fallback (match X/Z, ignore Y) for meshes taller than one cell (e.g. the
	`tall` pillar). Floor/underlay resolve through `_find_origin()` (single-owner
	dictionary walk); props go through a separate `_find_prop_origin()`
	(2026-09-13, once `occupied_cells` became multi-owner — see
	`MissionData.occupied_cells`'s own entry above) which resolves an
	overlapping cell via `MissionData.resolve_prop_priority()`, the same
	smallest-footprint-wins rule the Player uses — so selecting/erasing a
	gate sitting inside an archway now works correctly from either app.
  - Debug overlays, all toggleable: ghost preview, reference grid lines, world-origin
	axis gizmo, an occupancy overlay (`O` key) that draws wireframe boxes of what
	`floor_occupied_cells`/`occupied_cells`/`underlay_occupied_cells` actually think is
	covered — built assuming GridMap's **Center X/Y/Z are OFF** (map_to_local returns
	a cell's corner, not center) — this was essential for diagnosing the footprint
	bugs — and a tile-name-label overlay (`N` key, `_rebuild_tile_labels()`) that
	shows every placed item's `mesh_item_name` as a `Label3D` at its origin cell.
	Rebuilt on toggle and after edits (via `_sync_after_edit()`), NOT every frame
	like the occupancy overlay — that one's cheap `ImmediateMesh` geometry, but this
	creates real `Label3D` scene nodes, too costly to tear down/recreate 60x/sec.
	Mainly useful now that many floor tile faces share one generic material
	(flagstone/grass/dirt/wood planks) and can no longer be told apart by looks
	alone.
  - **Selection highlight** (`highlight_footprint()`/
	`clear_selection_highlight()`, called by `CreatorOutline.gd` — see
	that script's own entry — requested 2026-09-10) — a white outline
	around the actual SHAPE of whatever's currently selected, not a
	bounding box: `_footprint_boundary_edges()` traces the true perimeter
	of a multi-cell footprint (an edge belongs on the boundary whenever
	the footprint does NOT also contain the cell on the other side of it
	— the standard "outline a set of grid cells" trick), so an irregular
	piece like `18a` reads correctly instead of just showing a rectangle
	around it. Deliberately NOT one edge per cell the way the occupancy
	overlay above draws (that's meant to show every individual cell,
	internal lines and all) — this is meant to read as one clean shape.
	Same `ImmediateMesh` + `MeshInstance3D` + flat unshaded material
	pattern as every other overlay here, `PRIMITIVE_LINES` with the edges
	in any order (independent segments, not a connected loop — no
	ordering needed). Lifted above the surface it sits on to avoid
	z-fighting — `floor_thickness + 0.02` for `floor_grid`/`underlay_grid`
	(both sit at floor level, unlike `prop_grid` which
	`LayeredMap._ready()` already raises `+floor_thickness`), `0.02`
	otherwise — mirrors `LayeredMap.get_tile_square_world_corners()`'s
	identical lift for the spawn overlay. Static for now, no
	marching-ants animation — offered as a possible follow-on if a plain
	outline ever feels too flat, not attempted here.
  - **Draw mode** (`draw_mode`, `D` key toggles, `draw_mode_changed(enabled)`
	signal, requested 2026-09-10) — starts OFF (**Select mode**). In Draw
	mode, Left-click/Shift+Left-click place/erase as below, and the
	placement ghost preview shows. In Select mode, Left-click instead
	calls `select_at_cursor()`: raycasts (reusing `erase_at_cursor()`'s
	exact hit-cell resolution, now factored into a shared
	`_raycast_hit_cell()` + `_origin_for_hit()`) and emits
	`object_picked(kind, id)` (`kind`: `"object"`/`"floor"`/`"underlay"`,
	WALL silently skipped) rather than painting/erasing anything —
	`CreatorOutline.gd` listens and selects + scrolls to the matching tree
	item, without re-jumping the camera (see that script's
	`_on_object_picked()`). This is the "controller emits, UI listens"
	convention again — `CreatorController` doesn't know `CreatorOutline`
	exists. `CreatorPalette.gd` also flips Draw mode automatically, both
	directions (requested 2026-09-10): forces it OFF
	(`creator_controller.set_draw_mode(false)`) whenever `SidePanel`
	switches away from the `Palette` tab (listens to its parent
	`TabContainer`'s own `tab_changed` signal) — draw mode only makes
	sense while the tool that picks WHAT gets painted is actually on
	screen, and Select mode naturally pairs with switching to `Outline`
	to browse/select objects instead. And forces it ON
	(`set_draw_mode(true)`) from `_on_layer_tab_pressed()`/
	`_on_mesh_button_pressed()` - picking a layer or a mesh is a clear "I
	want to paint" signal. Deliberately NOT on the "Show unavailable"
	checkbox (a display filter, not paint intent) or
	`_on_locate_mesh_button_pressed()` (clicking an exhausted mesh to jump
	to it, not something you can select to paint) - and deliberately NOT
	a generic click-anywhere-in-the-Palette handler on the root Control,
	since a `Button`'s default `mouse_filter = STOP` would consume the
	click before it ever reached a parent's `_gui_input()` anyway, so
	that wouldn't actually fire for the buttons/checkbox inside it -
	hooking the specific press handlers was the only approach that works.
  - **`spawn_paint_mode`** (`P` key toggles, `spawn_paint_mode_changed(enabled)`
	signal, same setter/signal treatment as `draw_mode` above) got the
	exact same "housed where you'd actually use it" treatment 2026-09-10,
	in place of an earlier idea to give both `D`/`P` their own toolbar row
	— the user's call: `D` is fine left as just a hotkey + the Palette's
	own click-to-engage behavior above (advanced users learn the hotkey,
	everyone else discovers it by clicking a mesh), but `P` (Player Start)
	isn't mesh-library-backed at all, so it doesn't belong among the
	Floor/Prop/Underlay tabs - see `CreatorPalette.gd`'s own "Misc"
	tab entry below for where it actually landed. `draw_mode` and
	`spawn_paint_mode` are kept MUTUALLY EXCLUSIVE by the Palette's click
	handlers (never by the hotkeys themselves) - picking a mesh/layer
	turns Player Start off, picking Player Start turns Draw off - so
	left-click's meaning is never ambiguous between the two tools.
  - Controls: `D` toggle Draw/Select mode, Left-click place (Draw mode) /
	select (Select mode), Shift+Left-click erase (Draw mode only), `,`/`.` cycle mesh (not Tab —
	conflicts with UI focus once real Buttons exist), `R` rotate, `L` cycle layer
	filter (Floor → Prop → Underlay), PageUp/PageDown change level, `O` toggle
	occupancy overlay (also `set_occupancy_overlay()`/`occupancy_overlay_changed`
	signal, and a `View` menu checkbox — no longer keyboard-only "magic",
	requested 2026-09-10, see `CreatorViewMenu.gd` below), `N` toggle tile
	name labels (same treatment - `set_tile_labels()`/`tile_labels_changed`,
	also in the `View` menu) — one `Label3D` per placed
	piece showing a direction arrow plus its `mesh_item_name` (e.g. "↑ 18a"),
	centered on the piece's actual footprint rather than pinned to its origin
	cell — it reuses the same rotate/expand-footprint calculation
	`occupied_cells` is built from (`FootprintRegistry.get_footprint()` +
	`rotate_footprint()` against the real `GridMap.get_cell_item_basis()`) and
	averages the covered cells, since the origin cell is only ever one tiny
	fine-cell-sized far corner of the shape (per the far-corner convention) —
	anchoring anything there for a piece bigger than 1×1 reads as floating off
	to the side instead of sitting on it (this bit both the name and, briefly,
	a separately-positioned direction arrow — now folded into the one
	correctly-centered label instead of a second independently-placed node),
	`P` toggle player-spawn PAINT mode — left-click TOGGLES the hovered
	tile-square in/out of `MissionData.player_spawn_cells`, independent of
	the normal mesh paint/erase (no mesh needs to be selected; hover is
	computed against `floor_grid` directly rather than `_target_grid()`,
	then snapped fine-cell→tile-square, since spawn cells aren't tied to
	whatever layer/mesh happens to be selected). The yellow overlay itself
	(see `LayeredMap.gd` above) is always visible whenever spawn cells
	exist, not gated behind `P` - only whether clicking edits it is. Hides
	the normal mesh ghost preview while active (unrelated tool/hover
	target, confusing to see both) and shows its own hover ghost instead -
	a single tile-square quad in `ghost_color` (same green) at whatever
	cell would be toggled if clicked right now, via
	`LayeredMap.get_tile_square_world_corners()` - the exact same method
	the actually-placed overlay uses, so the preview can never show a
	different square than the one that actually gets toggled. Also
	reachable from `CreatorPalette`'s "Misc" tab now (`Player Start`
	button, requested 2026-09-10) - see that entry below and `draw_mode`'s
	entry above for the mutual-exclusivity reasoning.
- **Creator outline tree** (`CreatorOutline.gd`, attached to
  `SidePanel/Outline/Split/OutlineTree`, a `Tree`) — a scene-graph-style
  object browser: every placed `InteractableEntry` (prop/door/hazard/
  level-link) plus every `floor_placements` and every `underlay_placements`
  entry (floor/underlay tiles joined 2026-09-10, at the user's own prompting
  — "they are pretty unique on their own" — each is its own distinct placed
  instance too), plus optional, purely organizational `MissionGroup` nodes
  the designer can create to group related objects (e.g. "everything in
  this room"), requested 2026-09-10 as the "select a placed object"
  prerequisite Open item #13 had been waiting on.
  - Floor/underlay tiles reuse the exact same `id`/`parent_id` machinery as
	interactables even though `rebuild_floor_tiles()`/
	`rebuild_underlay_tiles()` do a full clear-and-rebuild rather than
	interactables' incremental single-cell sync (`sync_prop_cell()`) — both
	rebuild functions now build a lookup of the PREVIOUS placements (keyed
	by origin_cell) before clearing, and carry an old
	placement's `id`/`parent_id` forward when the new rebuild finds a match
	at the same key, only minting a fresh id when there's no match. Mirrors
	`sync_prop_cell()`'s own field-carry-over fix (see that function's
	entry above) — same problem, just solved once per whole-layer rebuild
	instead of once per cell.
  - Built at runtime like every other dynamic-content Creator UI piece
	(`CreatorPalette`, ...). Full rebuild on every `LayeredMap.
	mission_objects_changed` signal (emitted from `sync_prop_cell()`,
	`rebuild_floor_tiles()`, `rebuild_underlay_tiles()`, `apply_mission()`,
	and the group-CRUD methods below via
	`LayeredMap.notify_objects_changed()`) rather than incremental
	`TreeItem` patching — same simplicity tradeoff `CreatorPalette.
	_rebuild_mesh_grid()` already makes. `refresh()` coalesces repeated
	calls into one `call_deferred()`-scheduled rebuild rather than
	rebuilding immediately per call — the "simplest first" approach
	initially skipped this, but floor/underlay edits happen much more
	often than prop edits while actively painting a level (a full-layer
	rebuild fires on every single cell), and calling `Tree.clear()`/
	`create_item()` too rapidly back-to-back turned out to intermittently
	return null mid-rebuild — see the "hard-won lesson" below.
  - Node labels: an object or tile shows `reference_name` if set else
	`mesh_item_name` (both are `OutlineNode` fields now, see the data
	layer section above — floor/underlay tiles didn't have
	`reference_name` before 2026-09-10, so these commonly repeat when
	unset, e.g. several "1a" entries — expected); a group shows its own
	`reference_name` (falls back to "(unnamed group)", not a mesh name -
	groups have none); the always-present root item shows
	`mission.mission_name` (or "Untitled Mission"). Pre-existing saved
	missions have interactables/floor/underlay entries with `id == ""` —
	lazily adopted into the id system the first time the tree sees them
	(`refresh()`'s migration step), so old missions
	don't need a one-off conversion.
  - `SelectionType` has a fourth case, `TILE`, for floor/underlay entries
	(distinct from `OBJECT`/`InteractableEntry`, since `TilePlacement` is a
	different Resource with different fields — no `reference_name`/
	`actions`/`props`). Selecting emits `signal selection_changed(items: Array)`
	(reworked 2026-09-14 from a singular `selected(type, id)` — see
	**Multi-select** below) — `CreatorPropertiesPanel.gd` (below) is the
	only listener, same "talk only through public API + signals" convention
	as `CreatorPalette`/`CreatorController`. Selecting a single placed
	OBJECT or TILE also jumps the camera to it via
	`CreatorController.jump_to_cell(origin_cell, grid)` (the precise,
	per-instance counterpart to `locate_mesh()`, which only finds the
	first instance of a mesh name — not precise enough once several
	props/tiles share a mesh; `grid` defaults to `prop_grid` for an
	OBJECT, and is passed explicitly as `floor_grid`/`underlay_grid` for a
	TILE, tagged in that tree item's own metadata at build time so no
	re-lookup is needed) — the "find object back" half of this feature's
	purpose. A rebuild re-selects EVERY id that was selected before it and
	still exists (falls back to root only if NONE survived, e.g. everything
	selected just got erased — see **Multi-select** below for why this
	changed from reselecting just one item) — and deliberately does NOT
	re-jump the camera on a rebuild-driven reselection, only on an actual
	click, so painting elsewhere on the map while an object happens to be
	selected doesn't keep yanking the camera back to it.
  - **Multi-select** (new 2026-09-14, `select_mode = Tree.SELECT_MULTI` —
	confirmed via the Godot 4 docs that this gives native ctrl+click-toggle/
	shift+click-range selection for free, no custom input handling needed,
	but changes which signal fires: `item_selected` is replaced by
	`multi_selected(item, column, selected)`, firing once per toggled item,
	with no direct "get the whole selection" property — enumerated via
	`get_next_selected(from)` chaining from `null`) — added specifically so
	several already-placed objects can be **batch-moved into a group at
	once**, the "fix things after the fact" half of the working-group
	feature below (drawing INTO the right group from the start is the
	other half). `_selected_ids: Array[String]` tracks the FULL current
	selection, recomputed from scratch via `_recompute_selected_ids()`
	every time (matches this project's existing "simplest first, full
	rebuild over incremental patching" convention) rather than patched
	from each `multi_selected` toggle's own params. `_emit_selection_changed()`
	is the one chokepoint that builds `items` from `_selected_ids` and
	emits `selection_changed` — highlight/camera-jump only apply when
	`items.size() == 1` (a multi-selection has no single "the" object to
	outline or jump to; `_emit_selection_changed()` clears the highlight
	instead). Right-click (context menu) and a 3D-world-click pick (see
	"The reverse direction" below) both force a single-item selection
	first via a small `_select_only(item)` helper (`deselect_all()` +
	`item.select(0)`) — batch operations only ever happen through
	`CreatorPropertiesPanel.gd`'s multi-select panel, never the per-item
	context menu.
	- **Confirmed in-editor bug, worked around, 2026-09-14**: a plain
	  (no Ctrl/Shift) left-click doesn't reliably clear Tree's own prior
	  SELECT_MULTI selection on its own — intermittently leaves a stale
	  item selected alongside the newly-clicked one (keyboard nav, arrows
	  + space, doesn't have this problem — the user's own comparison is
	  what pinned it down to mouse clicks specifically). See **Hard-won
	  lessons** below for the fix (`_on_left_click()`, a post-hoc
	  `_select_only()` correction via `gui_input`).
  - **Selection highlight** (requested 2026-09-10 — "a whitish ticker
	line of the shape outline... is that feasible?", landed as a static
	outline, no animation for v1): every selection change (tree click,
	world click, or a rebuild-driven reselection - unlike the camera jump,
	this is NOT gated on `jump_camera`, since the shape/position could
	have changed even when nothing should re-jump the camera, e.g. after
	an undo) calls `CreatorController.highlight_footprint(origin_cell,
	footprint, grid)` for an OBJECT/TILE, or `clear_selection_highlight()`
	for ROOT/GROUP (no spatial footprint to show). See
	`CreatorController`'s own entry below for how the outline itself is
	drawn.
  - **The reverse direction** (world → tree, not tree → world): also
	listens to `CreatorController.object_picked` — a Select-mode left-click
	in the 3D view (see `CreatorController`'s Draw mode entry above) picks
	whatever's under the cursor, and `_on_object_picked()` selects +
	`scroll_to_item()`s the matching tree item, deliberately WITHOUT
	jumping the camera (it's already exactly where the user clicked) —
	the tree-driven selection path above jumps the camera, this one
	doesn't, that's the only difference between them.
  - Right-click context menu (root → New Group; group → New Subgroup/
	Rename Group/Delete Group/Move to…; object/tile → Move to… only) —
	groups are fully managed from the tree since they have no GridMap
	presence at all to conflict with. **Delete Group promotes its direct
	children (groups, objects, AND floor/underlay tiles) to the deleted
	group's own parent** rather than deleting them — a group is purely
	organizational, deleting one should never silently destroy placed
	objects — and if the deleted group WAS the current working group,
	`creator_controller.set_working_group(group.parent_id)` resets it to
	the same place its children just got promoted to (not undo-tracked:
	`working_group_id` is tool state on `CreatorController`, not
	`MissionData`, so it was never part of the `operation_history`
	snapshot to begin with). "Move to…" is guarded against creating a parent cycle (a
	group can't be moved into its own descendant — objects/tiles are never
	parents themselves, so this only matters for moving a group) via
	`is_valid_move_target(source_type, source_id, target_group_id)` —
	made public and parameterized 2026-09-14 (was a private
	`_is_valid_move_target(target_group_id)` reading instance state) so
	`CreatorPropertiesPanel.gd`'s batch move (below) can reuse the exact
	same cycle check per selected item, not just this single-target
	context menu. Group rename is inline-editable (double-click, or via the
	menu triggering `Tree.edit_selected()`), same native Tree UX as a file
	explorer.
  - **"Working group:" dropdown lived here briefly (2026-09-14), now lives
	on the persistent toolbar** (`CreatorToolbar.gd`, see **Creator
	tooling** below) — moved the same day it was added, once it became
	clear a designer actually wants to change it while on the Palette tab
	(where drawing happens), not the Outline tab. `_delete_group()` above
	still resets `creator_controller.working_group_id` when it deletes the
	current working group, since that state lives on `CreatorController`
	regardless of which script's UI currently exposes it.
  - **Object/tile rename/delete are deliberately NOT available from this
	tree** — rename borders on the property editing the user explicitly
	deferred to a later pass ("modify their properties in a later stage"),
	and delete would need to mirror `erase_at_cursor()`'s GridMap-clear
	path. Both stay exclusively available via the existing 3D-viewport
	paint/erase tools. True drag-and-drop reparenting (vs. the "Move to…"
	menu) is a possible follow-on, not attempted here.
  - **Unverified in-editor**, same caveat as everything else built this
	session without the ability to launch Godot and see it rendered.
- `CreatorPropertiesPanel.gd` (attached to `SidePanel/Outline/Split/
  Inspector`) — switches between the existing mission-level fields
  (`PropertiesFields` — Objective/player-count, still fully owned/
  read-written by `CreatorSaveLoad.gd` at Save/Load/New time, completely
  unchanged, this script only ever toggles their visibility) when the
  outline tree's ROOT is selected, and — **expanded 2026-09-10 from a
  read-only summary to real editing** — an editable form (`Name:` LineEdit
  + `Visible` CheckBox, plus a read-only Type/Mesh/Cell info line) for
  `reference_name`/`visible` when an object, tile, or group is selected.
  Feasible in one generic form rather than three per-type ones only
  because those two fields now live on the shared `OutlineNode` base (see
  the data layer section above) — `_resolve_node()` returns whichever
  concrete `InteractableEntry`/`TilePlacement`/`MissionGroup` matches the
  selected id, typed as `OutlineNode`, and the edit handlers
  (`_on_name_committed()`/`_on_visible_toggled()`) write straight to it
  with no type-specific branching. Both go through
  `operation_history.record()` (undo/redo) then
  `layered_map.notify_objects_changed()`, same pattern as everywhere else
  - the name field commits on Enter/focus-lost rather than per keystroke,
  same reasoning as `CreatorSaveLoad`'s objective field. The LineEdit's
  placeholder text shows the actual fallback value (mesh name, or
  "(unnamed group)") so it matches exactly what the outline tree would
  display if left blank. Doesn't need its own `mission_objects_changed`
  listener to stay in sync with edits from elsewhere (an undo/redo, the
  tree's own inline group rename) - `CreatorOutline` already re-emits
  `selection_changed` for whatever's currently selected on every rebuild,
  not just on an actual selection change, so this form's own listener
  catches it for free. Talks to `CreatorOutline` only through its
  `selection_changed` signal, same convention as above.
  - **Multi-select batch panel** (new 2026-09-14, `_multi_fields`, a THIRD
	sibling of `mission_fields`/`_object_fields`) — shown whenever
	`selection_changed` carries more than one item (`CreatorOutline.gd`'s
	tree is `SELECT_MULTI` now, see that script's own entry above).
	`_on_selection_changed(items)` is the new dispatcher, replacing the old
	`_on_outline_selected(type, id)`: `items.size() > 1` ->
	`_show_multi_selection()`, empty or a single ROOT item ->
	`_show_root()`, else `_show_single()` (today's existing single-object
	behavior, unchanged). Deliberately minimal per the request that
	motivated it ("properties view can be frozen, only the add to group
	action should be visible") — just a "N items selected" label, a
	group-picker `OptionButton` (own independent copy of the same
	"(none - root)" + `mission.groups` flat-list pattern
	`CreatorOutline`'s working-group dropdown and "Move to…" submenu both
	build too — kept as three separate small builders rather than one
	shared helper, matching this project's existing convention of each
	dialog owning its own near-identical widget-building code, e.g.
	`PropertiesDialog`/`ObjectivesDialog`/`PropActionsDialog` each have
	their own value-editor), and a "Move to Group" button. The button
	resolves every selected item (skipping ROOT, and skipping — with a
	`push_warning()` — any GROUP for which
	`creator_outline.is_valid_move_target()` says the chosen target would
	create a cycle) to its `OutlineNode` via the EXISTING `_resolve_node()`
	(already generic across `InteractableEntry`/`TilePlacement`/
	`MissionGroup` since `parent_id` lives on the shared `OutlineNode`
	base), then does ONE `operation_history.record()` reparenting all of
	them together — a single undo step for the whole batch, same "several
	related edits, one Operation" reasoning `CreatorSaveLoad`'s
	player-count fields already establish.
  - **`InteractableEntry.props`** (the free-form custom-property dict -
	OBJECT only, `TilePlacement`/`MissionGroup` don't have one) gets its
	own **"Custom Properties…" button** (OBJECT selections only) opening
	`PropertiesDialog` (new, `scripts/PropertiesDialog.gd`, requested
	2026-09-10 as a popup rather than embedded inline — "it will become
	too clumsy otherwise" in a 260px-wide panel). One instance, created in
	code (`PropertiesDialog.new()` in `_build_object_fields()` - not a
	`.tscn` node, so `operation_history`/`layered_map` are assigned
	directly rather than through `@export`/`NodePath`) and reused across
	selections via `open_for(entry)`. Each existing key's row picks a
	value widget from the property's CURRENT `typeof()` - `CheckBox` for
	bool, `SpinBox` for int/float, `LineEdit` otherwise - so an
	already-bool key like `"interactible"` can't get flattened into a
	string by editing it here. Adding a NEW key opens a second, nested
	`ConfirmationDialog` (built in the same script) asking for
	name/type/default value up front, rather than an inline "type a key,
	pick a type" row - keeps the main list simple and the add flow
	focused on the one decision that actually needs asking. Every edit
	(set/add/remove) goes through `operation_history.record()` then
	`layered_map.notify_objects_changed()`, same pattern as everywhere
	else in the Creator by now.
  - **`InteractableEntry.actions`** (`Array[PropAction]` - what a player
	can report doing to this prop, e.g. "push" this lever, and the
	`Effect`s that fire when they do, see **Story layer**'s `PropAction`
	entry) gets its own **"Actions…" button** (new 2026-09-13, OBJECT
	selections only, sibling of "Custom Properties…" above) opening
	`PropActionsDialog` (new, `scripts/PropActionsDialog.gd`). Same
	code-built, one-instance-reused-via-`open_for(entry)` pattern as
	`PropertiesDialog` - `operation_history`/`layered_map` assigned
	directly after `.new()`, no `.tscn` node. Simpler than
	`ObjectivesDialog`'s DAG editor since a `PropAction` has no
	children/branching - just a flat scrollable list, one `PanelContainer`
	block per action (Action id / Description LineEdits, a "Single shot"
	`CheckBox` new 2026-09-14 writing `PropAction.single_shot` - see that
	field's own entry above, `already_used` itself has no authoring UI
	since it's pure runtime state - a Conditions
	list new 2026-09-14 - see `PropAction.conditions`' own entry above,
	gates whether this action is currently OFFERED to players at all -
	and a nested Effects list with its own Add/Remove - each effect row's
	leading `Effect.Type` picker toggles Set Variable / Show Stage /
	Remove Object exactly the same way `ObjectivesDialog`'s own effect
	rows do, see that script's entry above), plus an "Add Action" button.
	Each block's condition/effect rows and value-type editor
	(`_build_condition_row()`/`_build_effect_row()`/`_build_value_editor()`,
	plus `_build_variable_name_option()`/`_known_variable_names()` -
	`variable_name`'s dropdown, new 2026-09-14, see `ObjectivesDialog`'s
	own entry for the full reasoning)
	are its own copies of `ObjectivesDialog`'s
	near-identical helpers rather than shared code - those are typed to a
	`MissionObjective` holder there, and every dialog in this project
	already owns its row-builder helpers independently (`PropertiesDialog`
	has its own too), so this follows that same convention rather than
	introducing a shared base class for three call sites. Rebuilds the
	whole row list on every add/remove via `queue_free()` (not immediate
	`free()`) - deliberately matching `PropertiesDialog.gd`'s identically-
	shaped row list rather than `ObjectivesDialog._rebuild_graph()`'s
	immediate-`free()` pattern: that one was forced by a DIFFERENT bug
	(`GraphEdit`'s internal children plus same-frame `add_child()` name
	collisions, see **Hard-won lessons**) that doesn't apply to a plain,
	unnamed `VBoxContainer` list - `queue_free()` is safe here specifically
	because a remove button's own click handler is still on the call stack
	when the rebuild it triggers frees that button's own ancestry.
	**Unverified in-editor**, same caveat as everything else built this
	session without the ability to launch Godot and see it rendered.
- **`ObjectivesDialog.gd`** (new 2026-09-12, `class_name ObjectivesDialog
  extends Window`) - the DAG editor for `MissionData.objectives`, opened
  via `CreatorSaveLoad.gd`'s **"Objectives…"** button (`%ObjectivesButton`,
  replacing the old single win-objective `%ObjectiveLineEdit` - see that
  script's own entry below). Same "built entirely in code, one instance
  created by the opener and reused via `open_for(mission)`" pattern as
  `PropertiesDialog`/`CreatorSettingsDialog` - `operation_history`/
  `layered_map` assigned directly, not `@export`/`NodePath`.
  - **Layout**: an `HSplitContainer` - a `GraphEdit` canvas on the left (an
	"Add Root Objective" button in its own `HBoxContainer` toolbar row above
	it - a bare `Button` as a direct `VBoxContainer` child stretches to the
	full container width and looks oversized, `SIZE_SHRINK_BEGIN` in an
	`HBoxContainer` keeps it sized to its own content), a properties panel
	(`ScrollContainer` > `VBoxContainer`) on the right showing whichever
	node is currently selected - matches the "DAG editor + side properties
	view, selection-driven" shape requested during design.
  - **Graph population** (`_rebuild_graph()`): BFS from every root in
	`mission.objectives`, visiting each unique `MissionObjective` once even
	though it's a DAG (a node reachable from more than one parent still
	only gets ONE `GraphNode` - `_node_by_name`/`_name_by_node`/
	`_graph_node_by_objective` dictionaries map both directions, since
	`GraphEdit`'s own signals only ever hand back node NAMES or the `Node`
	itself, never the `MissionObjective` resource). Each `GraphNode` shows
	a one-line summary (`_summary_text()` - "Leaf (WIN/LOSE)" or "Branch",
	plus condition/optional counts) and has one slot with both an input and
	output port always enabled, so any node can be dragged into a
	connection either direction (a root's input just stays unused). A
	never-before-opened node's `editor_position` is still `Vector2.ZERO`,
	so it's placed at a fixed `(60, 80)` base margin plus a BFS-order
	horizontal fan-out instead of literal `(0, 0)` - confirmed in-editor
	that `GraphEdit` draws its own built-in zoom/minimap controls floating
	over the canvas's top-left corner, so a node placed at the true origin
	renders (and is clickable) underneath them; a real (even manually-
	dragged-back-near-origin) position is left alone.
  - **Confirmed in-editor bug, fixed**: `_rebuild_graph()`'s cleanup step
	used to `queue_free()` every `Node` `GraphEdit.get_children()` returned
	- but `GraphEdit.get_children()` incorrectly includes its own internal
	`_connection_layer` node even with `include_internal` at its default
	(a confirmed Godot engine bug, not a mistake on this project's part -
	see godotengine/godot#91857 upstream). Freeing that layer left
	`GraphEdit.gui_input()` hard-erroring on every subsequent click
	("connections_layer is missing") and silently broke node dragging
	entirely (while connection-dragging partially still worked, since it
	apparently follows a different internal code path) - one bug
	explaining two reported symptoms at once. Fixed by only freeing
	children that are actually `is GraphElement` (what this dialog itself
	ever adds), leaving `GraphEdit`'s own internal nodes alone - see the
	Hard-won lessons entry below for the general rule this is an instance
	of. **That fix used `queue_free()`, which turned out to be its own,
	second bug** - `queue_free()` defers actual removal to end of frame,
	so a SECOND `_rebuild_graph()` within the same frame (e.g. clicking
	"Add Root Objective" twice) tried to `add_child()` a new `GraphNode`
	under the same name as one still technically present (queued, not yet
	gone), and Godot silently discarded the requested name in favor of its
	own auto-generated placeholder instead of erroring - breaking every
	later name-keyed lookup for that node with no error anywhere. Fixed by
	switching to immediate `remove_child()` + `free()` - see Hard-won
	lessons below for the general rule.
  - **Connections ARE the DAG edges**: `GraphEdit.connection_request()`/
	`disconnection_request()` resolve both ends back to `MissionObjective`s
	via `_node_by_name`, `operation_history.record()` the
	`children.append()`/`erase()`, then call `_graph.connect_node()`/
	`disconnect_node()` to actually draw/remove it - `GraphEdit` never
	auto-connects on its own, the request signals are just permission to
	do so after validating (rejects a self-loop or an already-existing
	edge). Requires `_graph.add_valid_connection_type(0, 0)` (called once
	in `_ready()`) - `GraphEdit` won't even emit `connection_request`
	for a port-type pair that isn't explicitly whitelisted, even when both
	ports share the identical type (see Hard-won lessons below - a real
	bug hit and fixed in-editor 2026-09-12, not a hypothetical).
  - **Delete is a full node delete, not a single-edge removal** (edge-only
	removal is what dragging a connection off already does) - a plain
	"Delete Node" `Button` child on each `GraphNode` (confirmed in-editor
	that `GraphNode.show_close`/`close_request` don't exist on this Godot
	version - same manual "×"-button pattern used for every other remove
	action in this dialog, instead of relying on a built-in close affordance)
	removes the node from EVERY parent's `children` that references it
	(and from `mission.objectives` if it was a root) in one
	`operation_history` entry, then rebuilds the graph. Any subtree ONLY
	reachable through the
	deleted node simply won't appear in the rebuilt graph - nothing else
	references it, so it's freed like any other unreferenced `Resource`,
	no explicit cascade-delete needed.
  - **Properties panel** (rebuilt per selection): Description (`LineEdit`),
	Outcome (`OptionButton` WIN/LOSE, `disabled` whenever `children` isn't
	empty - only meaningful on a leaf), Priority (`SpinBox`), then
	Conditions and Effects as small inline list editors
	(`_build_condition_row()`/`_build_effect_row()` + `_build_value_editor()`
	- a type picker [String/Bool/Int/Float, defaulted from
	`typeof(current_value)`] plus the one matching value widget, same
	reasoning as `PropertiesDialog`'s own per-type widgets: a
	`Condition`/`Effect.value` is a loosely-typed `Variant`, only checked
	against its target variable's DECLARED type at evaluation time by
	`MissionRuntime._coerce()`, not enforced here - `variable_name` is a
	dropdown now (new 2026-09-14, `_build_variable_name_option()`/
	`_known_variable_names()` - built-ins plus every declared
	`MissionData.custom_variables` name, shared by both
	`_build_condition_row()` and `_build_effect_row()` within this one
	file; selects nothing/blank rather than silently picking the first
	entry if the currently-set name isn't among them, e.g. authored before
	the variable was declared). `_build_effect_row()` also gained a leading `Effect.Type` `OptionButton`
	("Set Variable"/"Show Stage"/"Remove Object", the third new 2026-09-14
	the same day as the type itself) that toggles between three widget
	groups (same "build them all, toggle `.visible`" trick
	`_build_value_editor()` already uses for its own type picker): the
	variable_name+value widgets above for SET_VARIABLE, a group-picker
	`OptionButton` (`mission.groups`, no "(root)" entry) writing
	`effect.target_group_id` for SHOW_STAGE, and an object-picker
	`OptionButton` (every entry in `mission.interactables` +
	`floor_placements` + `underlay_placements`, labeled
	`"<name> (<origin_cell>)"` - the cell disambiguates entries sharing a
	mesh name, e.g. several "gate"s or every plain "1a" floor tile, unlike
	the group picker which doesn't need it since groups are already
	uniquely named) writing `effect.target_object_id` for REMOVE_OBJECT.
	And Optional Objectives as a list of rows each with an "Edit…" button
	opening a small **nested** `Window` (`_open_optional_editor()` -
	description + its own Conditions/Effects list, reusing the exact same
	row-builder helpers) - the "a dialog opens a smaller dialog" pattern
	`PropertiesDialog`'s own Add-Property `ConfirmationDialog` already
	established. Every edit goes through `_commit_field()` (a thin wrapper
	around `operation_history.record()` + `layered_map.notify_objects_changed()`).
  - **Canvas layout is NOT undo-tracked** - `editor_position` is pure
	authoring metadata, saved directly to each node when the dialog closes
	(`_on_close_requested()`), not wrapped in `operation_history.record()`,
	so rearranging nodes doesn't clutter the undo stack.
  - **Actively verified in-editor 2026-09-12** (unlike most of this
	session's other work) - node dragging and connection-making both hit
	real `GraphEdit` engine gotchas along the way (see Hard-won lessons:
	the `_connection_layer`-in-`get_children()` bug and the
	`add_valid_connection_type()` requirement), both since fixed. Still
	worth a full pass once available: multi-parent (DAG-converging) delete
	behavior, the nested optional-objective editor, and the
	condition/effect value-type editors haven't specifically been exercised
	yet.
- **`MissionVariablesDialog.gd`** (new 2026-09-14, `class_name
  MissionVariablesDialog extends Window`) - editor for
  `MissionData.custom_variables`, built specifically to close the gap
  that caused a real "my conditional action never becomes available" bug
  report (see **Story layer**'s "One variable registry" entry for the
  full story) - before this dialog, nothing anywhere in the Creator could
  actually DECLARE a `MissionVariable`, so any `Condition`/`Effect`
  referencing an undeclared name was silently a no-op. Opened via
  `CreatorSaveLoad.gd`'s **"Variables…" button** (`%VariablesButton`,
  same `PropertiesFields` location as `%ObjectivesButton`, mission-level
  not per-object). Same code-built, one-instance-reused-via-`open_for(mission)`
  pattern as `ObjectivesDialog`/`PropActionsDialog` -
  `operation_history`/`layered_map` assigned directly after `.new()`.
  Flat scrollable list, one `PanelContainer` block per variable (Name
  LineEdit, Type `OptionButton` [Bool/Int/Float/String], one matching
  Default-value widget) - same shape as `PropActionsDialog`'s action
  list. Unlike `_build_value_editor()`'s own internal type picker
  elsewhere (a per-FIELD guess defaulted from `typeof(current_value)`),
  this dialog's Type picker IS the variable's actual declared type, so
  switching it also resets `default_value` to that type's zero value
  (`false`/`0`/`0.0`/`""`) rather than leaving a stale mismatched value
  sitting there - `_zero_default()` duplicates `MissionRuntime._zero_value()`'s
  exact shape rather than reusing it (that lives on a live-playthrough
  `MissionRuntime` instance, not a static utility this Creator-only
  dialog has any business constructing one of just to reach a 4-line
  helper). No duplicate-name or blank-name validation - matches this
  project's existing "not yet validated in-editor" precedent for
  `reference_name` uniqueness. **Unverified in-editor**, same caveat as
  everything else built this session without the ability to launch Godot
  and see it rendered.
- `CreatorSaveLoad.gd` — attached to `MenuBar/File`, a `PopupMenu` under the
  top-spanning `MenuBar` (`CanvasLayer/MainLayout/MenuBar`, see
  `MainLayout`'s entry above) - New/Save/Load/Back are menu items now
  (added via `add_item()` in `_ready()`, dispatched through one
  `id_pressed` handler), not standalone Buttons in a toolbar row.
  New/Save/Load also carry REAL keyboard accelerators (Ctrl+N/Ctrl+S/
  Ctrl+O, `add_item()`'s 3rd `accel` param, requested 2026-09-10) -
  Godot's own `MenuBar` accelerator-forwarding makes these work globally
  even while the menu is closed, not just a visual hint. Safe to bind
  natively here specifically because none of these three keys are ALSO
  handled manually anywhere else in the Creator (unlike Ctrl+Z or bare
  `O`/`N`, which `CreatorController._unhandled_input()` already owns —
  those stay inline-text-only hints instead, see `OperationHistory.gd`/
  `CreatorViewMenu.gd` below, to avoid a keypress firing twice through
  two separate bindings). Also has a **"Settings…"** item (requested
  2026-09-10) opening `CreatorSettingsDialog` (built once in `_ready()`,
  reused across opens, same pattern as `CreatorPropertiesPanel.gd`'s
  `PropertiesDialog`) - see that entry and `CreatorAutosave.gd`'s below.
  Holds a
  child `FileDialog` (**Access = User Data**, not File System - not
  Resources either, since 2026-09-11: `missions_dir` moved from
  `res://missions` to `user://missions`, same read-only-in-an-exported-
  build reasoning as `CreatorSettings`/`CreatorAutosave` below, just
  applied to normal manual Save/Load - `res://` silently can't be written
  to from the shipped `.exe`, so plain Save was broken there too, not
  just the autosave system). Reuses `MissionIO` + `LayeredMap.apply_mission()`.
  Also owns `%ObjectivesButton`, `%VariablesButton`, and
  `%MinPlayersSpinBox`/`%MaxPlayersSpinBox`
  - those live in `SidePanel/Outline/Split/Inspector/PropertiesFields`
  (see `CreatorPropertiesPanel.gd`'s entry above), not this script's own
  node. **`%ObjectivesButton` replaced `%ObjectiveLineEdit` 2026-09-12**
  (see `ObjectivesDialog.gd`'s own entry below for the DAG editor it
  opens) - unlike the old LineEdit, there's no local widget state to keep
  synced or flush at Save time, since the dialog edits
  `layered_map.mission.objectives` directly and rebuilds itself fresh from
  the mission every time it's opened (same as `PropertiesDialog` editing
  `InteractableEntry.props` directly). **`%VariablesButton`** (new
  2026-09-14, sibling of `%ObjectivesButton`) opens `MissionVariablesDialog`
  the same way - see that script's own entry above. The player-count `SpinBox`es remain
  **live-synced** (2026-09-10, for undo/redo, see `OperationHistory.gd`
  below) - each wraps `operation_history.record()` on `value_changed`;
  `_apply_player_count_fields()` is still called once more at Save time as
  a harmless safety net (catches a value typed but never committed before
  Save was clicked). `_on_mission_objects_changed()` (listens for
  `LayeredMap.mission_objects_changed`, Load/New/undo/redo) now only
  refreshes the player-count fields - the equivalent objective-field
  refresh is gone along with the LineEdit it used to serve. The old
  `_ready()` that pinned the toolbar row's right
  edge against `CreatorPalette.PANEL_WIDTH` (a stopgap for the row
  overlapping the palette) is gone - moot now that there's no toolbar row
  to overlap anything, see Open item #12.
- **`CreatorAutosave.gd`** (new node, sibling of `CreatorController`/
  `DebugSync`) — two-tier autosave/backup driver, requested 2026-09-10
  ("one of the most frustrating things in editors is that you can lose
  data"). Settings come from the `CreatorSettings` autoload (see that
  entry above); this script just drives two `Timer`s (built in code in
  `_ready()`, same as every other dynamic node in this project) off them.
  **STATELESS rotation**: rather than tracking a rotation index in memory
  (confusing across app restarts), each backup is named
  `<mission_name>_<tier>_<timestamp>.tres` (`tier`: `autosave`/
  `checkpoint`; timestamp zero-padded `YYYYMMDD-HHMMSS`, hand-formatted
  via `Time.get_datetime_dict_from_system()` rather than
  `get_datetime_string_from_system()`'s default `HH:MM:SS` - a literal
  `:` isn't valid in a Windows filename, and this project's Creator ships
  as a Windows `.exe`). After writing a new one, the whole backup
  directory is rescanned for files matching that mission+tier's own
  prefix, sorted (zero-padding makes lexicographic sort == chronological
  sort), and the oldest deleted until back at the configured count -
  simple, self-healing, works the same on the first save of a session or
  the fiftieth. Reuses `MissionIO.save_mission()` (already exists,
  already verified round-trip correctness) for the actual write - no new
  save logic, just a scheduled call to the same path a manual Save uses,
  targeting a different file each time. `apply_settings()` (called once
  at `_ready()`, and again whenever `CreatorSettings.settings_changed`
  fires) is the ONE place "do nothing if not enabled" actually lives -
  stops both `Timer`s entirely when disabled, rather than leaving them
  running and skipping the save inside the callback, so disabled really
  means no background ticking at all, not a checked-but-still-running one.
- **`CreatorSettingsDialog.gd`** (new, `extends Window`, instantiated once
  by `CreatorSaveLoad.gd`'s `_ready()`, opened via its "Settings…" menu
  item) — the settings form: an Enabled checkbox, a Backup Location
  `LineEdit`, and four `SpinBox`es (copies/interval-minutes × two tiers,
  all `min_value = 1` matching the request's own "int > 0" constraint).
  Same code-built-dialog pattern as `PropertiesDialog.gd`. `open()` reads
  current `CreatorSettings` values into the form; the Save button writes
  them back and calls `CreatorSettings.save_settings()` (which persists to
  disk and emits `settings_changed` - `CreatorAutosave.gd` is the only
  current listener, no direct coupling between the dialog and the
  autosave driver). Closing via the window's own X button discards
  whatever was typed, same as any other unsaved form - no separate
  Cancel button needed.
  - **Unverified in-editor**, same caveat as everything else built this
	session - especially worth confirming: toggling `enabled` off in the
	dialog actually stops both timers (no new files appear after Save);
	rotation actually deletes the oldest file once over the configured
	count, independently per tier; a mission with an empty `mission_name`
	still autosaves under `untitled_*` without erroring.
- **`OperationHistory.gd`** (attached to `MenuBar/Edit`, a `PopupMenu`
  sibling of `MenuBar/File`) — undo/redo for the Creator, requested
  2026-09-10 ("I think this means we need to store a stack of relevant
  changes done"). **Design**: rather than separate do()/undo() logic per
  mutation kind, every recorded `Operation` stores a deep-duplicated
  `MissionData` snapshot (`.duplicate(true)`) from immediately before and
  after the change; undo/redo is then just
  `LayeredMap.apply_mission(snapshot.duplicate(true))` (duplicated again
  on the way OUT, so the live mission is never the same object instance
  sitting in the history stack - Resources are reference types, a later
  edit would otherwise corrupt the stored snapshot) for every mutation
  kind uniformly - painting, erasing, group CRUD, property edits all just
  become "mission was A, now it's B." `apply_mission()` already emits
  `mission_objects_changed`, so `CreatorOutline`'s tree,
  `CreatorPalette`'s availability grid, and now `CreatorSaveLoad`'s
  fields all refresh after any undo/redo with zero extra wiring. Trades
  memory (a full mission snapshot per operation, capped at
  `MAX_OPERATIONS = 50`) for never needing per-mutation-kind reverse
  logic - "simplest first", missions here are modest in size.
  - `func record(label: String, mutate: Callable) -> void` - the API
	every mutation site calls, wrapping its EXISTING mutation code in a
	`Callable` rather than being restructured: `CreatorController.gd`
	(paint/erase/spawn-cell-toggle), `CreatorOutline.gd` (group create/
	rename/delete/move), `CreatorSaveLoad.gd` (objective/player-count, see
	that script's entry above). Melds into the top-of-stack `Operation`
	instead of pushing a new one when the label matches and it's within
	`MELD_WINDOW_MSEC` (1.5s) - the user's own example ("pressing the
	player count button 6 times should be one operation") - which also
	naturally makes a whole paint/erase drag stroke one undo step, since
	every cell painted during one continuous drag shares the "Paint"/
	"Erase" label.
  - **Reentrancy**: one recorded mutation's side effect can trigger
	ANOTHER recorded mutation - e.g. `CreatorSaveLoad`'s min-players field
	clamping max-players when min gets dragged above it, which fires
	max's own `value_changed` → `record()` call mid-`mutate.call()` of the
	outer one. `record()` tracks whether it's already inside a `mutate`
	call and, if so, just runs the nested `mutate` directly without its
	own before/after/push-or-meld bookkeeping - the outer call's own
	`after` snapshot naturally absorbs the nested change, so what the user
	experienced as one action stays one `Operation`.
  - **Ctrl+Z/Ctrl+Shift+Z are handled in `CreatorController._unhandled_input()`,
	NOT on this script's own node** - `OperationHistory` is attached to a
	`PopupMenu` (a `Window`-derived node), and whether a `Window`'s
	`_unhandled_input()` fires reliably while closed/invisible is
	genuinely uncertain without being able to run the editor to check.
	Reusing `CreatorController`'s own `_unhandled_input()` (already proven
	reliable this session for every other keyboard shortcut) was the
	lower-risk choice - it just calls `undo()`/`redo()` directly, same as
	the Undo/Redo menu items' own `id_pressed` handler does. The menu
	items themselves grey out via `set_item_disabled()` whenever there's
	nothing to undo/redo. Labels read "Undo (Ctrl+Z)"/"Redo
	(Ctrl+Shift+Z)" (requested 2026-09-10, "show the hotkey") - plain
	inline text, deliberately NOT a real `set_item_accelerator()` binding
	the way `CreatorSaveLoad.gd`'s New/Save/Load got, since Ctrl+Z is
	already bound manually above - a second, native binding on top of
	that would risk firing twice per keypress.
  - **Unverified in-editor**, same caveat as everything else built this
	session without the ability to launch Godot and see it rendered -
	especially worth confirming: a paint stroke → undo reverts GridMap +
	tree + palette together; rapid SpinBox clicks → one undo reverts all
	of them; undoing past a group delete → members reattach to the group,
	not left orphaned at root.
- `CreatorViewMenu.gd` (attached to `MenuBar/View`, sibling of `File`/
  `Edit`) — exposes `O`/`N` as checkable menu items ("Occupancy Overlay
  (O)"/"Tile Name Labels (N)"), requested 2026-09-10 so they're no longer
  keyboard-only "magic" toggles nobody would discover without reading this
  file. The hotkeys still work exactly as before (still handled directly
  in `CreatorController._unhandled_input()`) - both paths now route
  through the same `CreatorController.set_occupancy_overlay()`/
  `set_tile_labels()`, which emit `occupancy_overlay_changed`/
  `tile_labels_changed` that this menu listens to, so the checkmark here
  can never drift out of sync with whichever path actually toggled it.
  Same reasoning as `OperationHistory.gd`'s entry above for why these are
  inline-text hints rather than real accelerators - `O`/`N` are already
  bound manually, a second native binding risks double-firing.
  **Unverified in-editor.**
- `FreeLookCamera.gd` — editor-style navigation: right-click-drag to look, WASD to
  move while dragging, scroll wheel to dolly, Shift to boost speed. Its
  `_input()` bails out on a right-click that's over a `Control`
  (`get_viewport().gui_get_hovered_control() != null`) before engaging -
  otherwise it captures the mouse out from under any UI that also wants a
  right-click (e.g. `CreatorOutline`'s context menu) - see "Hard-won
  lessons" below.
- `debug/DebugSync.gd` — temporary manual test harness. Keys **1/2/3/4** (deliberately
  *not* F5-F8, which are Godot's own Run/Run Scene/Pause/Stop shortcuts and get
  intercepted by the editor): 1 = sync+dump MissionData to Output, 2 = clear
  everything, 3 = save, 4 = load-and-dump-separately (for comparing round-trips).

**App shell** (`ui/`, `player/`):

- `MainMenu` — Play (opens a `FileDialog` over `user://missions/`, then loads
  `MissionPlayer.tscn` with the chosen path via `GameState`) / Editor (loads the
  Creator scene) / Exit. The mission folder moved from `res://missions` to
  `user://missions` 2026-09-11 - same `res://` is read-only in an exported
  build reasoning as `CreatorSettings`/`CreatorAutosave` (see **Hard-won
  lessons**), just applied to the Creator's own manual Save/Load this time,
  not just the autosave system. Both this dialog and `CreatorSaveLoad.gd`'s
  now use `FileDialog.access = ACCESS_USERDATA` (was the default
  `ACCESS_RESOURCES`) with `root_subfolder = "user://missions/"` to match.
  The old `res://missions/*.tres` dev/test fixtures (`one-tile.tres`,
  `test-123.tres`, `test_mission.tres`, `underlays.tres`) were deleted
  from the repo the same day, once `res://missions` was no longer where
  anything actually looks — they were never shipped sample content, just
  local save-testing artifacts from when the Creator wrote to `res://`
  directly inside the editor.
- `MissionPlayer.gd` — loads the mission via `MissionIO`, calls
  `%LayeredMap.apply_mission(mission, true)` (the `true` is new 2026-09-14 -
  `respect_visibility`, see `LayeredMap.gd`'s own entry above), shows mission name + counts in a label. Runs
  the basic round loop (see **Story layer**'s `RoundCheckpoint.Checkpoint`
  and `MissionRuntime`): round 1 first shows the spawn area (if authored,
  see below) and waits for confirmation, then Player phase → "All players
  done" button → walks every remaining checkpoint, actually firing
  triggers/checking objectives at each one via `_advance_to()` → Darkness
  phase (a flat `darkness_phase_duration` timed pause standing in for real
  world-effect resolution + monster AI, neither built yet) → loops back to
  Player phase, round incremented. `%DarknessOverlay` (a full-rect
  `ColorRect`, `mouse_filter = IGNORE` so it darkens without blocking
  clicks) is the only phase-change visual so far.
  `_refresh_objective_label()` (renamed 2026-09-14 from `_show_objective()`)
  shows only the objective(s) `MissionRuntime.get_current_objective_descriptions()`
  currently considers active, NOT `mission.objectives` (the DAG's static
  roots) directly - reading the roots unconditionally used to spoil any
  branch/leaf the players hadn't actually reached yet. Its first call
  moved from early in `_ready()` (info-label section) to right after
  `_runtime` is actually constructed, since it now needs the runtime to
  exist; re-called from `_advance_to()` (every checkpoint transition) and
  via `PlayerInteractionController.objectives_progressed` (every prop
  action - handled by the new `_on_objectives_progressed()`, see that
  script's own entry below), since either can advance
  the DAG frontier mid-game, not just once at mission start.
  **`show_stage(group_id)`** (new 2026-09-14) - the "Show Stage" effect's
  actual orchestrator (see **Story layer**'s own entry for the full
  design): no-ops if the group is unknown or already `visible` (so a
  duplicate detection result or a re-fired trigger can't show the setup
  dialog twice); otherwise flips `group.visible = true` FIRST (so
  `MissionData.is_effectively_visible()`'s ancestor walk sees this group,
  and its now-reachable descendants, correctly when
  `_format_stage_pages(group, mission.get_stage_requirements(group_id))`
  computes what to show), `await`s `dialog.ask_narrative()` with the
  result (skipped if there's nothing to list), then
  `layered_map.repaint_visible_entries()`. Called from THREE places, all
  draining/awaiting the exact same way: `_ready()` (once, for
  `mission.find_starting_group_ids()` - before players are placed, tell
  them what the starting room needs, THEN show the "put players" dialog,
  matching the request this was built from), `_advance_to()` (drains
  `_runtime.drain_pending_stage_reveals()` right after
  `evaluate_checkpoint()`, alongside the `_refresh_objective_label()`
  call), and the new `_on_objectives_progressed()` (same drain, after a
  fired `PropAction`). Both of those same two call sites also drain
  `_runtime.drain_pending_object_removals()` (new 2026-09-14, same day as
  `Effect.Type.REMOVE_OBJECT` itself) right alongside the stage-reveal
  drain, calling `layered_map.remove_node(id)` for each - no `await`
  needed, unlike a stage reveal there's no dialog to show. Still **no
  actual movement/LOS/player-position tracking** — the app never tracks
  real positions (see **Story layer**), which is why "players spawn" is
  just a highlighted area + a confirmation dialog, not anything the app
  verifies. **`_frame_camera_on_spawn_area()`** (new 2026-09-14, called
  from `_show_spawn_area_and_confirm()` right after the yellow overlay
  goes visible) - the scene's own starting `Camera3D` transform is just
  wherever it happened to be left in the editor, which could easily leave
  the spawn area out of frame, or sitting too close to actually tell
  where it is relative to the rest of the map. Jumps
  `camera` (`@onready var camera: FreeLookCamera = $Camera3D` - a direct
  child of the root, no unique name needed) to the spawn cells' own
  centroid via `FreeLookCamera.jump_to()` (already existed, reused
  unchanged from the Creator's own "locate a placed instance" features),
  with a distance scaled to the spawn area's bounding radius
  (`SPAWN_VIEW_MIN_DISTANCE`/`SPAWN_VIEW_RADIUS_MULTIPLIER`) rather than
  one fixed distance regardless of size - a small authored area doesn't
  get an unnecessarily distant view, a large one still fits. Corner
  positions come from `LayeredMap.get_tile_square_world_corners()`, the
  same method the spawn overlay's own geometry is built from.
- `PlayerDialog.gd` (`%Dialog` in `MissionPlayer.tscn`) — reusable async
  dialog, built at runtime (same reasoning as `CreatorPalette` - content/
  buttons vary per call): `ask_ok(text)`, `ask_yes_no(text) -> bool`,
  `ask_count(text, min, max) -> int`, `ask_narrative(pages) -> void`
  (OK/NEXT/BACK through multiple pages), `ask_choice(text, option_labels, option_disabled: Array[bool] = []) -> int`
  (new 2026-09-14, nullable-by-convention via `-1` - one button per
  `option_labels` entry, result = that entry's index, plus a trailing
  "Cancel" button, result `-1`, always present - reuses the exact same
  `_set_buttons(specs)`/`_closed` mechanism every other `ask_*` method
  does). `option_disabled` (same day, second addition - an exhausted
  `PropAction.single_shot` action, see that class's own entry above) greys
  out that option's button instead of omitting it, so the player can see
  it exists but can't be chosen again; a shorter (or empty, the default)
  array just leaves the remaining options enabled. `_set_buttons(specs)`
  reads a `spec.get("disabled", false)` key to drive this - every other
  `ask_*` method's specs simply don't set that key, so they're unaffected.
  **Modal** while visible - the root
  Control is a full-screen dim scrim (`mouse_filter = STOP`, deliberately
  relying on the same STOP-blocks-everything-behind-it mechanism
  `CreatorPalette`'s background bug worked through earlier this session,
  rather than working around it) so nothing else (camera, the End Phase/Back
  buttons, the world) is reachable until answered; the actual visible box
  (text + buttons) is a child centered near the top, not the root itself.
  This is the mechanism **Story layer**'s "asked" variables (things the app
  can't compute, only ask - "is a player on tile 2a") are meant to use once
  the evaluator exists; not wired to variables yet. `ask_narrative()` got
  its first real caller 2026-09-14 - `MissionPlayer.show_stage()`'s
  board-setup pages (see **Story layer**'s "Show Stage" entry).
  `ask_choice()`'s first (and so far only) caller is
  `PlayerInteractionController._offer_actions()`'s multi-action picker -
  see that script's own entry below.
  - **Confirmed bug, fixed same day**: `_on_button_pressed(result: Variant)`
	(every button from every `ask_*()` call funnels through this one
	handler) checked `result == "_next"`/`"_back"` (the `ask_narrative()`
	page-nav sentinels) unconditionally - once `ask_choice()` started
	passing `int` results (an option's index, or `-1` for Cancel),
	comparing those against a `String` literal threw `Invalid operands
	'int' and 'String' in operator '=='` at runtime rather than just
	returning `false` - GDScript's `==` isn't defined for every
	Variant type pair, see **Hard-won lessons** below. Fixed by guarding
	both string comparisons behind `typeof(result) == TYPE_STRING` first.
- `HeroCatalog.gd` — never instantiated, just a shared namespace (same
  pattern as `RoundCheckpoint`) for the placeholder party roster: `SLOT_COUNT`
  (6), `slot_name(i)`/`slot_color(i)`. No real hero names/art - Descent's own
  are the original game's copyrighted content (see **Official asset
  overrides**), and there's no override mechanism for hero identity anyway.
  Shared between `EmbarkDialog` and `PlayerInteractionController` so both
  always agree on what slot N looks like.
- `EmbarkDialog.gd` (`%Embark` in `MissionPlayer.tscn`) — shown once right
  after a mission loads, before anything else (round 1, spawn confirmation,
  all of it) - the table picks which `HeroCatalog` slots are playing.
  `ask_roster(mission) -> Array[int]` returns the selected slot indices in
  slot order (which player number is which character, not just a count).
  Enforces `MissionData.min_players`/`max_players` (both default to the
  full 1-6 range, so a mission with nothing authored stays unrestricted):
  once `max_players` are selected, every remaining unselected slot greys
  out (`Button.disabled`, not hidden) until one gets freed up again; Start
  stays disabled below `min_players`. Authored in the Creator via
  `%MinPlayersSpinBox`/`%MaxPlayersSpinBox` next to the objective field in
  `CreatorSaveLoad.gd`, same "only read at save/load time" pattern as the
  objective `LineEdit`. Equipment selection is explicitly deferred - "for
  now we focus on adding players." **Modal** - same full-screen scrim
  mechanism as `PlayerDialog` (see that entry above), especially important
  here since nothing else in the Player scene should be reachable before a
  party even exists.
- `PlayerInteractionController.gd` (`%InteractionDock` in `MissionPlayer.tscn`)
  — drag-to-interact UI, matching the original companion app's own gesture:
  drag a hero portrait onto the world to interact with something. First pass
  only (see Open items): `set_roster(roster)` (called once by
  `MissionPlayer._ready()` after `EmbarkDialog` resolves) rebuilds the
  portrait row from the actual chosen party - dock position and
  `HeroCatalog` slot aren't the same thing once the roster isn't slots
  0..N-1 in order (e.g. `[0, 2, 5]`), so drag state tracks the dock
  position and looks up the real slot for anything shown to the user.
  Dragging a portrait draws a `Line2D` toward the cursor, hovering an
  `InteractableEntry` with `props["interactible"]` not explicitly false
  AND at least one action whose own `conditions` currently hold (new
  2026-09-14, see **Story layer**'s `PropAction` entry - previously just
  checked `actions` non-empty) highlights its footprint
  cells (filled quads, same corner-math style as every other overlay in
  this project) - `_resolve_action(entry)` (new 2026-09-14) is the cheap
  EXISTENCE check `_interactable_at()`'s highlight test uses, wrapping
  `MissionRuntime.first_available_action()` with a null-entry-safe,
  mission_runtime-not-ready fallback (plain `entry.actions[0]` - shouldn't
  normally happen once the game has actually started).
  **Releasing over one now presents a real choice** (2026-09-14, replacing
  the earlier "always fires `entry.actions[0]`" behavior once
  `PropAction.conditions` made more than one simultaneously-available
  action possible - "eg an action is only available if certain variable
  is in place... interact with a tree that has actions: pick fruit,
  climb... the choice must be presented after the drag, and cancel is
  always an option"): `_end_drag()` resets all drag visuals FIRST (the
  drag line/highlight shouldn't sit around under the modal picker - the
  drag gesture itself is complete the moment the mouse releases,
  choosing/firing is a separate follow-up step), then `await`s the new
  `_offer_actions(hero_name, entry)`, which re-resolves the FULL candidate
  list via `MissionRuntime.available_actions(entry)` (re-resolved rather
  than trusting `_interactable_at()`'s last hover check, in case
  conditions changed between hover and release) and presents every one of
  them as a choice via `dialog.ask_choice()` (`PlayerDialog.gd`'s new
  primitive - a real `dialog: PlayerDialog` export now, wired to `%Dialog`
  in `MissionPlayer.tscn` alongside the existing `layered_map` one,
  `mission_runtime` stays a plain post-construction `var` since it has no
  scene node to NodePath to) - Cancel (`-1`) is always included alongside
  them, picking it (or a zero-candidate entry, which
  `_interactable_at()` already excludes from being a valid drop target)
  does nothing. Firing then works exactly as before -
  `mission_runtime.fire_prop_action()` (`mission_runtime`
  is a plain `var` assigned by `MissionPlayer._ready()` right after
  constructing its `MissionRuntime`, same "runtime-constructed object, no
  Inspector slot to `@export` through" pattern `PropertiesDialog`'s own
  cross-references use). **Can end the game live** (2026-09-12, once
  `MissionObjective` became a DAG re-checked on every event, not just
  checkpoints - see **Story layer**): if `fire_prop_action()` returns a
  non-null `MissionObjective`, emits this script's own `signal
  game_over_requested(objective)`, which `MissionPlayer._ready()` connects
  to `_on_game_over_requested()` - a genuine signal here, safe unlike
  `MissionPlayer._advance_to()`'s deliberate avoidance of one, since
  nothing below continues an internal loop after `_offer_actions()` that
  would need to wait on the connected handler finishing. Also emits a second,
  unconditional `signal objectives_progressed` (new 2026-09-14) right
  after every `fire_prop_action()` call regardless of outcome -
  `MissionPlayer._refresh_objective_label()` listens (see that script's
  own entry above) since a DAG group can be replaced by its children
  (changing which objective is "active") without that resolving all the
  way to a leaf, which `game_over_requested` alone wouldn't cover.
  Deliberately skips
  Godot's built-in Control drag-and-drop
  (`_get_drag_data`/`_drop_data`) - the drop target is a 3D world position
  found by raycasting, not another Control, so manual mouse tracking (a
  global `_input()` once a drag starts, not just `gui_input`) is simpler
  than fighting that system to reach underneath it. Hit-testing reuses
  `CreatorController.erase_at_cursor()`'s real physics-raycast-against-
  GridMap-collision technique (not the flat-plane approximation
  `_update_hover()` uses for painting, which assumes a fixed editing level -
  irrelevant here) plus the already-existing `MissionData.get_interactable_at()`.
  The game's own rule ("only interact with what you're physically adjacent
  to") isn't enforced - that needs real player-position tracking, which
  doesn't exist. **Unverified in-editor.**

## Scene structure (post-refactor)

Split into a minimal reusable piece plus two separate wrappers, specifically so
Play mode doesn't inherit Creator-only tooling (this was a real bug that got fixed):

- **`map/LayeredMapCore.tscn`** — just `LayeredMap.gd` + the three GridMaps
  (FloorGridMap/PropGridMap/UnderlayGridMap, sharing one MeshLibrary and
  identical cell_size). Instanced by both of the below. A `WallGridMap`
  existed earlier but was removed 2026-09-11 (Open item #14, done) - the
  game has no wall concept, it was never used in real missions.
- **`map/MissionMap.tscn`** (the Creator) — instances `LayeredMapCore` as `%LayeredMap`,
  plus `Camera3D` (FreeLookCamera), `DirectionalLight3D`, `DebugSync`,
  `CreatorController`, `CreatorAutosave` (two-tier backup timer, see
  **Creator tooling** below), and a `CanvasLayer/MainLayout` shell: a top-spanning
  `MenuBar` (File → New/Save/Load/Back/Settings…, `CreatorSaveLoad.gd`,
  New/Save/Load also bound to Ctrl+N/Ctrl+S/Ctrl+O; Edit → Undo/Redo,
  `OperationHistory.gd`; View → Occupancy Overlay/Tile Name Labels,
  `CreatorViewMenu.gd` - see **Creator tooling** below for all four), a
  persistent `Toolbar` (`CreatorToolbar.gd`, new 2026-09-14 - "Working
  group:" dropdown + "Show unavailable" checkbox, full width, see that
  script's own entry under **Creator tooling**) beneath the menu bar, above
  an `EditorArea` splitting the 3D view's space (left, just an empty
  input-transparent spacer - the 3D content isn't a `Control`) from
  `SidePanel` (right, `Palette`/`Outline` tabs — `Outline` itself splits,
  via a `VSplitContainer`, into the object-browser `Tree`
  (`CreatorOutline.gd`) on top and the mission/object properties panel
  (`CreatorPropertiesPanel.gd`) below - a real drag-resizable split, since
  unlike `EditorArea` both panes here are plain 2D Controls) - see the `MainLayout`
  entry under **Creator tooling** above for why this isn't a real
  `HSplitContainer`.
- **`player/MissionPlayer.tscn`** — instances `LayeredMapCore` as `%LayeredMap`, plus
  its own separate `Camera3D`/`DirectionalLight3D`, and a `CanvasLayer` with an info
  `Label` and a Back button. No editing tools at all.
- **`ui/MainMenu.tscn`** — the app's actual entry point (set as Project Settings →
  Main Scene).

Autoloads registered in Project Settings: `FootprintRegistry`, `GameState`,
`ComponentInventory`.

**Root-level source scenes** (`floors.tscn`, `pilars.tscn`, `stair.tscn`) — not part
of the app itself and not referenced by any other scene or by Project Settings.
These are the source scenes used to build/populate the shared `MeshLibrary` that all
three GridMaps (Floor/Prop/Underlay) consume — keep them around as the mesh-authoring
source of truth, don't treat them as dead/orphaned files to delete.

## Tooling

`tools/scan_extraction/` — a small Python (OpenCV) pipeline that turns a raw
physical-tile scan (`models/scans/*.png`, one photo of several tile faces on a
white background) into the composed textures in `models/floor/`. It auto-detects
and crops each piece and auto-rotates it upright where possible, but orientation
(0 vs 180) and irregular-shape rotation fits still need a human eye per piece —
not a one-shot batch command. See `tools/scan_extraction/README.md` for the actual
workflow and known limitations (touching pieces, near-circular/zigzag shapes
confusing the rotation fit).

`tools/asset_import/` — a Python (UnityPy) importer that lets a user who owns the
real "Descent: Legends of the Dark" companion app unlock its actual textures
locally, without this project ever shipping or redistributing that copyrighted art
— see **Official asset overrides** below for the full mechanism. Run it once
pointed at your own game install; nothing it produces ever gets committed.

`tools/footprint_extraction/` — derives `FootprintRegistry.FOOTPRINTS` entries
directly from `models/floors.glb`'s mesh geometry instead of hand-typing ASCII
art — see **Footprint extraction from mesh geometry** below.

## Footprint extraction from mesh geometry

`tools/footprint_extraction/extract_footprints.py` reads `models/floors.glb`
(a standard glTF binary, one named node per tile face - `"1a"`, `"18b"`, etc.,
matching `FootprintRegistry.FOOTPRINTS`'s keys exactly) and computes each
tile's footprint by sampling every candidate tile-square cell's center point
against the mesh's actual triangles (XZ-projected; floor tiles are flat), then
converts that into the same "raw, pre-`_apply_pivot_correction()`" storage
form the hand-authored entries use - see the script's own docstrings for the
exact offset<->world-space mapping and the pivot-correction round-trip math.
No third-party deps; parses the GLB/glTF container by hand (good enough for
this one-shot use, not a general glTF library).

Two safety checks gate its output:
- **Calibration**: every tile already hand-authored in `FOOTPRINTS` is
  re-derived from the mesh and compared byte-for-byte against the existing
  entry before the script will print anything for NEW tiles. If any known
  tile doesn't match exactly, it refuses to run rather than risk silently
  wrong data.
- **Pivot validity**: checks the actual invariant the whole rotate/expand
  pipeline depends on (cells along the origin's own row/column extend in only
  ONE direction - see the pivot-correction note under "Hard-won lessons"
  below) rather than a naive bounding-box-corner check, since shapes like
  tile 7's cross legitimately bulge past the origin's row/column elsewhere in
  the piece. A tile whose Blender pivot sits genuinely in the shape's
  interior (found for `21a`/`21b` - see **Current data authored so far**)
  fails this check and is excluded from the output with a warning, since no
  uniform correction can fix it - the mesh's origin needs moving to an actual
  corner in Blender and re-exporting.

Run it with `python tools/footprint_extraction/extract_footprints.py` from the
repo root any time new tile faces are added to `floors.glb`; it prints an
ASCII-art preview of every new tile (same style as the hand-authored comments
in `FootprintRegistry.gd`, for eyeballing that `a`/`b` faces are proper
mirror images etc.) plus ready-to-paste `Vector3i` entries.

## Official asset overrides

Same pattern [OpenMW](https://openmw.org/) uses for Morrowind: this project ships
zero copyrighted game art, only placeholder textures — the real look only ever
appears locally, for a user who separately owns the official game and runs
`tools/asset_import/import_official_assets.py` against their own install.

- `OfficialAssetMap` (autoload) — hand-maintained `Dictionary` mapping a shipped
  **placeholder texture's `res://` path** (e.g.
  `"res://models/floors_flagstone.png"`) to the official game's internal asset name
  (e.g. `"W1_Tiles_Flagstone"`). Keyed by texture path rather than mesh/item name
  **deliberately**: many floor tile faces share the exact same placeholder texture
  (that's the whole point of the flagstone/grass/dirt/wood-planks material system),
  so matching by texture means one map entry covers every tile face using that
  look, instead of needing one entry per tile face all pointing at the same
  texture. Works identically for the underlay hazards too, since each of those
  already has its own uniquely-named placeholder. The names don't follow any
  shared convention — confirmed by actually inspecting the game's Unity
  AssetBundles — so this can never be derived automatically, only hand-authored.
  Currently covers all 8 confirmed so far: the four underlay hazards
  (`water`/`acid`/`lava`/`spikes`) and the four floor materials
  (flagstone/grass/dirt/wood planks).
- `OfficialAssetOverrides` (autoload) — `apply_overrides(mesh_library)`, called
  once from `LayeredMap._ready()` (all four GridMaps share one MeshLibrary, so one
  call covers everything). Scans **every** item (not just specially-named ones,
  since matching is texture-based now) — for each, reads its current
  `surface_get_material(0).albedo_texture.resource_path`, looks that path up in
  `OfficialAssetMap`, and if `user://official_assets/<OfficialName>.png` exists,
  swaps it onto that item's material. Leaves the shipped placeholder untouched
  otherwise. Always **duplicates** the material before touching it — never mutates
  in place, so every item ends up with its own independent material even though
  many floor tile faces started out sharing the same one.
  - **Only handles single-surface meshes right now** (`surface_get_material(0)`).
	Verified true for every current `OfficialAssetMap`-matched item by inspecting
	`descent-meshes.tres` directly, but NOT true project-wide — the `"medium"`/
	`"mini"` pillar meshes have multiple surfaces/materials each (their own
	original sculpts, not part of this system, but proof the assumption doesn't
	hold everywhere). If a future mapped texture turns out to be used on a
	multi-surface item, this needs to loop surfaces instead of hardcoding index 0.
- Props like `gate`/`archway`/`tree` and the pillars/`stair` are the user's own
  original sculpted models (not derived from the official game at all), so they're
  intentionally absent from `OfficialAssetMap` — there's no "official" version to
  swap in for those.
- Token props (`exploration`/`interact`/`umbra`, from `models/tokens.glb`) ARE
  mapped, unlike the props above — each token type has its own unique official
  texture (`Token_Explore`/`Token_Interact`/`Token_Umbra`), no sharing like the
  floor materials. These represent an event/interaction system that doesn't
  exist yet (see Open Items) - for now they're just placed props, classified as
  `"prop"` layer via `get_layer()`'s default (not yet given their own layer -
  may get one later once the event system exists, not decided).

## CI / Release

`.github/workflows/release.yml` builds and publishes a GitHub Release automatically.

- **Trigger**: pushing a tag matching `v*.*.*` (e.g. `v1.0.0`), or manually via the
  Actions tab (`workflow_dispatch`).
- **Build**: runs in the `barichello/godot-ci:4.7.2` Docker image (bundles Godot
  4.7.2 + matching export templates — keep this pinned version in sync with the
  project's actual Godot minor version, `config/features` in `project.godot`).
  Exports the `"Windows Desktop"` preset from `export_presets.cfg` headlessly, zips
  the resulting `.exe`/`.pck`, and uploads it as a build artifact.
- **Release**: a second job downloads that artifact and creates a GitHub Release
  (via `softprops/action-gh-release`) with auto-generated release notes and the zip
  attached. Uses the default `GITHUB_TOKEN` — no extra secrets needed.
- Only Windows is exported currently, matching the only preset that exists in
  `export_presets.cfg`. Adding Linux/Mac/Web presets later means adding a matching
  `export-<platform>` job (same pattern as the existing `export-windows` job); the
  `release` job already gathers artifacts generically and doesn't need to change.

## Hard-won Godot 4 / GDScript lessons

These cost real debugging time — worth not re-learning them:

- **`GraphEdit` requires port-type pairs to be explicitly whitelisted via
  `add_valid_connection_type(from_type, to_type)` before it will ever emit
  `connection_request`** - even for two ports of the IDENTICAL type (e.g.
  both `0`, the default `set_slot()` type used everywhere in this
  project). Type compatibility is checked before the signal fires, not
  after, so without registering a type pair a drag visually snaps to a
  valid-looking target port (that's just `GraphEdit`'s own drag-preview
  feedback, unconditional) but is silently discarded on release - no
  signal reaches your handler, no error prints anywhere. Confirmed
  in-editor 2026-09-12 in `ObjectivesDialog.gd` - fixed with a single
  `_graph.add_valid_connection_type(0, 0)` once, in `_ready()`.
- **`Tree.select_mode = SELECT_MULTI`'s own native mouse click handling
  doesn't reliably clear the previous selection on a plain (no Ctrl/Shift)
  left-click** - confirmed in-editor 2026-09-14 in `CreatorOutline.gd`:
  a plain click could intermittently leave a stale item selected
  alongside the newly-clicked one, making `CreatorPropertiesPanel.gd`'s
  "N items selected" batch panel appear for a selection the user never
  actually made. Keyboard navigation (arrow keys + space) did NOT have
  this problem - comparing the two symptoms (native click path acting up,
  Tree's other native selection path behaving correctly) was what
  actually pinned this down to mouse click handling specifically, rather
  than a bug in this project's own `_recompute_selected_ids()` (which
  just reads whatever Tree's `get_next_selected()` reports - garbage in,
  garbage out). No Godot bug report was tracked down for this one (unlike
  the `GraphEdit`/`_connection_layer` issue above, which has an upstream
  issue number) - fixed defensively rather than by identifying the exact
  root cause: `gui_input` fires AFTER Tree's own built-in click handling
  has already run for the same event (the signal, not a virtual override
  you can pre-empt), so a plain-click handler there can't prevent
  whatever Tree just did, only correct it immediately after - call
  `_select_only(item)` (`deselect_all()` + `item.select(0)`)
  unconditionally on every plain click, leaving Ctrl/Shift-held clicks
  untouched (that's the native toggle/range-select actually working).
  General rule: don't assume a `SELECT_MULTI` Control's native mouse
  click semantics exactly match its keyboard semantics - verify the
  mouse path specifically (or just take explicit control of it, as here)
  rather than trusting docs/convention for something this fiddly.
- **GDScript's `==` throws a runtime error for some mismatched Variant
  type pairs (e.g. `int == String`) instead of just returning `false`** -
  confirmed in-editor 2026-09-14 in `PlayerDialog._on_button_pressed()`:
  every button press from every `ask_*()` method funnels through this one
  handler, which checked `result == "_next"`/`"_back"` (string sentinels
  `ask_narrative()`'s own Next/Back buttons pass) unconditionally. That
  was silently fine while every OTHER `ask_*()` method's results were
  `null`/`bool` - but the moment `ask_choice()` (new the same day) started
  passing `int` results (an option's index, or `-1` for Cancel), the very
  next button press anywhere in the app hit `Invalid operands 'int' and
  'String' in operator '=='` - a hard runtime error, not a false
  comparison. Fixed by guarding the string comparisons behind
  `typeof(result) == TYPE_STRING` first. General rule: a `Variant`-typed
  equality check against a literal of one specific type (a string
  sentinel, a specific enum value, ...) needs a `typeof()`/type guard
  first if the variable could ever hold a genuinely incompatible type -
  don't assume `==` degrades gracefully to `false` the way it does in
  more dynamically-typed languages. **Follow-up, same day**: applied the
  same defensive treatment to `MissionRuntime._declared_type()`/
  `_coerce()`, which both used `null` as a "not found"/"failed" sentinel
  compared via `== null` - but their SUCCESS values can legitimately be
  `0`/`false`/`""`/`0.0` (a `MissionVariable.Type.BOOL` is enum value
  `0`; `round_number`/`player_count`, the only types ever actually
  exercised before `MissionVariablesDialog.gd` existed, are both
  `Type.INT` = `1`, so `0` had literally never reached this comparison
  before). Whether `0 == null`/`false == null` actually misbehaves here
  was NOT conclusively confirmed (unlike the `int == String` case above,
  which had a hard reproducible error) - fixed proactively rather than
  root-cause-confirmed, given the same project had just hit one real
  instance of this exact category of bug hours earlier.
  `_declared_type()` now returns a plain `int` with `-1` as an
  unambiguous "not found" sentinel (never a valid enum value) instead of
  `Variant`/`null`; `_coerce()`'s callers check `typeof(x) == TYPE_NIL`
  instead of `x == null`.
- **`Node.add_child()` silently discards a colliding requested name and
  falls back to Godot's own auto-generated placeholder (`@ClassName@N`)
  instead of erroring or suffixing it** - and `queue_free()` being
  DEFERRED (only actually removing the node at end of frame) is exactly
  what creates that collision in any "clear everything, then re-add fresh
  copies with the same computed names" rebuild pattern. Found 2026-09-13
  in `ObjectivesDialog.gd`: `_rebuild_graph()` used to `queue_free()` the
  old `GraphNode`s before re-adding new ones keyed by the same
  `MissionObjective.id`-derived names - a SECOND rebuild within the same
  frame (e.g. clicking "Add Root Objective" twice) re-added a node named
  `"obj_obj_1"` while the OLD `"obj_obj_1"` was still technically present
  (queued, not yet removed), so Godot silently renamed the NEW one to
  `@GraphNode@642` instead - breaking every later name-keyed lookup
  (`_node_by_name.get()` for that node) with no error anywhere, since
  from `add_child()`'s perspective nothing went wrong. Manifested as
  `connection_request` firing correctly but resolving one endpoint to
  `null` and silently no-op'ing. Fixed by using immediate `remove_child()`
  + `free()` instead of `queue_free()` when a rebuild is about to re-add
  replacements under the same names in the same call. General rule: never
  `queue_free()` something you're about to synchronously replace with a
  same-named sibling - use immediate `free()` (after `remove_child()`) so
  the old node is actually gone before the new one claims its name.
- **`GraphEdit.get_children()` returns its own internal `_connection_layer`
  node, even though internal children are supposed to be excluded by
  default** - a confirmed upstream Godot engine bug
  (godotengine/godot#91857), not something this project got wrong. Found
  2026-09-12 in `ObjectivesDialog.gd`: `_rebuild_graph()`'s "clear
  everything and rebuild" step used to `queue_free()` every child
  `get_children()` returned, which destroyed that internal layer along
  with the real `GraphNode`s - `GraphEdit.gui_input()` then hard-errored
  on every subsequent click ("connections_layer is missing", a `<C++
  Error>` pointing at `graph_edit.cpp`'s own `gui_input()`), which
  manifested as node-dragging silently not working at all while
  connection-dragging partially still did (apparently a different
  internal code path). Fixed by filtering to `if child is GraphElement`
  before freeing - the general rule: **never blindly clear/free every
  child of a Godot container Control that manages its own internal
  children** (`GraphEdit`, and plausibly others like `Tree`/`TabContainer`)
  - filter by type/ownership to only touch nodes your own code actually
  added.
- **`res://` is read-only in an exported build; `user://` is the
  writable-everywhere location for anything a running game/tool needs to
  write itself** (settings, save files, backups, logs). Inside the Godot
  editor `res://` maps to the real project folder and writes happily,
  which makes this easy to get away with during development and only
  fail once actually shipped - this project's Creator ships as an
  exported Windows `.exe` (see **CI / Release** below), so anything it
  writes at runtime (`CreatorSettings`'s settings file,
  `CreatorAutosave.gd`'s backups) has to target `user://`, matching the
  precedent `OfficialAssetOverrides` already set for the same reason. A
  request that explicitly asks for `res://` for something the tool itself
  will write at runtime is worth double-checking against this before
  building it as asked.
- **A custom autoload/class name can silently collide with a Godot
  built-in of the same name.** The autosave settings autoload was
  originally named `EditorSettings` — which is also the name of a
  **built-in Godot 4 engine class** (the real editor's own preferences
  singleton, part of the editor API). Registering a custom autoload under
  that identifier in `project.godot` doesn't error at save/load time, but
  the global name resolves ambiguously and the custom autoload doesn't
  show up/work as expected ("EditorSettings seems to be something from
  core, i dont see it appear" — caught by the user in-editor, not by
  review). Fixed by renaming to `CreatorSettings` (and its dialog,
  `EditorSettingsDialog` → `CreatorSettingsDialog`, for consistency, even
  though only the autoload's own name actually collided). Before naming a
  new autoload or `class_name`, worth a quick check against Godot's own
  built-in class list, especially for generic-sounding names
  (`EditorSettings`, `ProjectSettings`, `Input`, etc.) — this project's
  existing autoloads/classes all use a `Creator`/`Mission`/project-specific
  prefix precisely to avoid this category of clash, and this is the one
  case that didn't follow that convention.
- A `Container`-managed child (`layout_mode = 2`, e.g. a `TabContainer`
  tab) should **never also call `set_anchors_and_offsets_preset()`/set
  `offset_*` on itself** in code. It's tempting to assume the Container
  will harmlessly override it, but confirmed in-editor that's not
  reliable: `CreatorPalette._build_ui()` called
  `set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)` on itself
  (a leftover from before it became a `TabContainer` tab), which spans
  full height from y=0 regardless of the tab bar's own height — it
  rendered on top of and ate clicks meant for `SidePanel`'s own tab
  labels, making tabs unswitchable. Verify, don't assume, when a Control
  gains a Container parent it didn't originally have.
- `Node._input(event)` fires on **every** node that defines it, for
  **every** input event, unconditionally — BEFORE Godot's own GUI system
  gets a chance to route the event to whatever `Control` is under the
  cursor. Confirmed in-editor 2026-09-10: `FreeLookCamera._input()`
  engages right-click-drag camera-look (which captures/hides the mouse)
  regardless of what the click was actually over, so right-clicking
  `CreatorOutline`'s `Tree` for its context menu ALSO engaged the camera,
  capturing the mouse out from under the menu (looked like the mouse
  "froze" and the menu appeared re-centered mid-screen — it was reading
  the just-recaptured cursor position). Fixed by checking
  `get_viewport().gui_get_hovered_control() != null` at the top of the
  right-click handler and bailing out if so — any future raw `_input()`
  handler in this project that reacts to a mouse button needs the same
  guard once UI can plausibly be under the cursor at the same time.
- **Windows' filesystem is case-insensitive; Godot's resource/class
  registration is not.** Found 2026-09-10: `map/LayeredMapCore.tscn` and
  three mission `.tres` files had `res://scripts/Tileplacement.gd`
  (lowercase `p`) baked into old `ext_resource` entries — a stale
  authoring-time typo that loaded fine for a long time (Windows doesn't
  care) until Godot's global class registration started treating it as a
  SECOND script independently declaring `class_name TilePlacement`,
  producing a baffling "Class 'TilePlacement' hides a global script
  class" parse error pointing at the correctly-cased file's own
  declaration line. If a `class_name` error ever again points at a
  script's own declaration line rather than anywhere it's used, grep the
  project for a differently-cased version of that script's filename
  before assuming the code itself is wrong.
- `Tree.clear()` followed by `Tree.create_item()` (the standard "rebuild
  this Tree from scratch" idiom, used by `CreatorOutline._rebuild_tree()`)
  is **not safe to call at high frequency, back-to-back** — confirmed
  in-editor 2026-09-10: with `LayeredMap.mission_objects_changed` firing
  once per painted floor cell, dragging to paint several cells in one
  stroke called `refresh()`/`_rebuild_tree()` many times in quick
  succession, and `create_item()` intermittently returned null mid-rebuild
  ("Cannot call method 'set_text' on a null value"). Fixed by having
  `refresh()` coalesce repeated calls into a single `call_deferred()`-
  scheduled rebuild instead of one immediate rebuild per call — cheap
  insurance for any future UI that rebuilds a `Tree` (or likely other
  from-scratch-rebuilt controls) in response to a signal that can fire
  many times per frame/stroke.
- `Basis.from_orthogonal_index()` / `Basis.get_orthogonal_index()` are **not exposed
  to GDScript**. Use `GridMap.get_cell_item_basis(cell)` (read) and
  `GridMap.get_orthogonal_index_from_basis(basis)` (write) instead — both are instance
  methods on GridMap, so borrow any GridMap node purely for the calculation.
- All three GridMaps (Floor/Prop/Underlay) intentionally **share one
  MeshLibrary** — you cannot tell "this is a floor tile" from "this is a pillar" by
  which grid's library you query. `FootprintRegistry.get_layer()` is the actual
  source of truth.
- This project's GridMaps have **Center X/Y/Z all OFF** — `map_to_local()` returns a
  cell's *corner*, not its center. Any code building world positions from cell indices
  needs to account for this explicitly.
- `F5`/`F6`/`F7`/`F8` are Godot's own Run Project / Run Scene / Pause / Stop shortcuts
  and get intercepted by the editor even during a running scene — never bind in-game
  debug hotkeys to these. Similarly, `Tab` is `ui_focus_next` and stops reaching
  `_unhandled_input` once real `Control`/`Button` nodes exist in a scene.
- `FileDialog.access` must be **`Resources`** or **`User Data`** (whichever
  matches the actual `res://`/`user://` path you're browsing -
  `CreatorSaveLoad.gd`/`MainMenu.gd`'s mission dialogs use `User Data` +
  `root_subfolder = "user://missions/"`, `CreatorSettingsDialog`'s backup
  location field is a plain `user://`-prefixed `String`, not a `FileDialog`
  at all), never `File System` — the latter returns absolute OS paths that
  don't resolve the same way as `res://`/`user://` paths for `ResourceLoader`.
- Cross-script type inference (`:=`) can fail for a method's return type when that
  method lives on a different custom `class_name` script — use explicit type
  annotations (`var x: int = ...`) as a reliable workaround.
- `@onready` vars resolve in scene-tree sibling order (depth-first) — a sibling node's
  script can run its own `_ready()` *before* another sibling has populated its
  `@onready` vars, if it happens to sit earlier in the tree. `await
  get_tree().process_frame` at the top of `_ready()` makes code order-independent
  instead of accidentally depending on node arrangement.
- GridMap only stores an item at a multi-cell placement's **origin cell** — every
  other cell it visually covers is empty as far as GridMap itself is concerned. Any
  "what's at this cell" query (erase, movement, LOS) needs an occupancy dictionary
  (`occupied_cells` / `floor_occupied_cells`) to translate back to the real origin.
- **Rotating a multi-cell footprint must happen at tile-square granularity, before
  expanding to fine cells** — rotating an already-expanded, corner-anchored block
  rotates around the wrong pivot and silently produces a shape that "looks right
  unrotated, wrong once rotated."
- Rotating a "min-corner + extent" offset (a region, not a bare point) needs an extra
  correction term beyond naive point-rotation, to account for the region's own extent
  also needing to rotate.
- Individual mesh assets can have inconsistent pivot placement relative to each other
  — the pillar meshes needed their own specific calibrated offset
  (`Vector3i(1, 0, 0)`, not the naive `Vector3i.ZERO`) because their real pivot sits
  on a different corner convention than the floor tiles/stairs use. When something
  still looks wrong after fixing the general math, check whether it's an
  asset-specific quirk rather than a shared bug.
- Follow-up to the above: the pivot-corner mismatch is now **auto-detected and
  corrected** (`FootprintRegistry._apply_pivot_correction()`), instead of hand-fixing
  each affected tile's offsets. Every mesh's Blender pivot sits on a genuine corner of
  its own geometry, so cells adjacent to the origin along one axis only ever extend in
  a single direction — never both. `expand_footprint()` assumes that direction is
  always -X/-Z; if a mesh's authored data shows the origin's own row (`z == 0`)
  extending toward +X, or its own column (`x == 0`) extending toward +Z, that means
  its real pivot sits on the opposite edge, and every offset needs a uniform `+1` on
  that axis to compensate. This is checked automatically from the raw `FOOTPRINTS`
  data now (discovered via `3a`/`3b`, where `3b`'s origin sits at the shape's own
  leftmost column — pure `x >= 0` throughout — while `3a`'s doesn't). It only works
  when there's a second offset to compare against, so a 1×1 footprint (the pillars)
  can't be auto-corrected this way and still needs its manual offset — see the note
  by the pillar entries in `FOOTPRINTS`.

## Current data authored so far

- Floor tiles: `1a`/`1b`, `2a`/`2b` (2×3 rectangle), `3a`/`3b` (notched rectangle,
  mirrored faces), `4a`/`4b`/`5a`/`5b` (stepped/L-shape, mirrored faces — tile 5
  shares tile 4's shape), `6a`/`6b` (notched rectangle), `7a`/`7b` (plus/cross),
  `8a`/`8b` (small cross/T notch), `9a`/`9b` (large irregular slanted shape,
  mirrored), `10a`/`10b` (notched rectangle), `11a`/`11b` (irregular slanted
  shape, mirrored), `12a`/`12b` (notched rectangle), `13a`/`13b` (large notched
  shape, symmetric), `14a`/`14b` (irregular stepped shape, mirrored), `15a`/`15b`
  (wide notched rectangle, symmetric), `16a`/`16b` (large irregular shape),
  `17a`/`17b` (notched rectangle, symmetric), `18a`/`18b` (large 7×7 octagon-ish
  shape, 36 cells), `19a`/`19b` (small solid rectangle), `20a`/`20b` (staggered
  zigzag), `21a`/`21b` (small 4×4 cross) — all of these except `9a`/`9b`,
  `13a`/`13b`, and `21a`/`21b` were derived from mesh geometry rather than
  hand-typed ASCII art, see **Footprint extraction from mesh geometry** below.
  - **`6a`/`6b` and `19a`/`19b` are UNVERIFIED** - the user modeled these two
	tiles' meshes from memory while away from the physical box with no scan to
	check against ("on holiday", 2026-09-08), so their shape is a guess. The
	extracted footprint faithfully matches whatever the mesh says, but the mesh
	itself might not match the real physical tile - re-check both against the
	actual box before relying on them for a real mission, and re-run the
	extraction tool if the mesh gets corrected.
  - `9a`/`9b`, `13a`/`13b`, and `21a`/`21b` were hand-authored from ASCII art
	instead of extracted: the mesh geometry in `floors.glb` for those three
	names is a large solid rectangle with the pivot in its interior (72/72/56
	cells respectively) - nothing like the actual shapes, so it's not just a
	pivot-correction case, the meshes themselves need fixing/replacing in
	Blender before extraction would work for tiles 9/13/21.
  - `bridge.001` and `stair.001` are also present in `floors.glb` but aren't
	tile-face names and are deliberately skipped by the extraction tool - the
	user has flagged these as unexpected/leftover, not (yet) real tiles.
  - Remaining tile numbers beyond what's listed here still need their meshes
	added to `floors.glb` (or shapes measured/entered by hand) and re-run
	through the tool.
- `stair` — 3×2 shape entered; the low/high point distinction and `LEVEL_LINK` wiring
  (which cells it actually connects, and across how many levels) is **not yet done** —
  that's mission-instance-specific data, not something the mesh shape alone defines.
- Pillars `tall`/`mini`/`medium` — 1×1 tile-square, correctly calibrated.
- `ComponentInventory.MAX_COUNTS` — placeholder numbers throughout, needs real counts
  from the physical component list.
- Underlay hazard layer (`water`/`acid`/`lava`/`spikes`) — fully wired up and
  paintable: 4th GridMap, `FootprintRegistry` shapes, `ComponentInventory` card
  grouping (`water`/`spikes` share one physical card, `lava`/`acid` share another,
  max 4 each — real confirmed counts), mesh items present in `descent-meshes.tres`,
  sourced from `underlays.tscn` (root-level, same role as `floors.tscn`/
  `pilars.tscn`/`stair.tscn` — the mesh-authoring source, not dead/orphaned).
- Props `gate` (2×1 column, origin unmarked/assumed at the bottom cell — worth
  double-checking in-game), `archway` (4×1 column), `tree` (1×1) — shapes entered,
  mesh items present. `gate`/`archway` default to walkable/non-LOS-blocking
  (treated as openings); `tree` defaults to blocking movement + LOS like a pillar.
  These are naming-convention *defaults* only — unverified in-game.
  **Gates in archways are a confirmed, supported real case** (a real mission
  placed a gate inside an archway, footprints fully overlapping) — occupancy
  now supports this generically for any overlapping props, not just this
  pair, see `MissionData.occupied_cells`'s entry above.
- Token props `exploration`/`interact`/`umbra` (1×1 each, `models/tokens.glb`) —
  shapes entered, mesh items present, official-asset-mapped (see **Official
  asset overrides** above). Currently just placed props (`"prop"` layer,
  walkable/non-LOS-blocking naming-convention default) with no logic behind
  them yet - the event/interaction system they're meant to key into doesn't
  exist, see Open Items.

## Open items / natural next steps

1. Finish authoring the remaining floor tile shapes not yet in `FootprintRegistry`
   (see **Current data authored so far** above for exactly which numbers) - most of
   these can now go through `tools/footprint_extraction/` instead of hand-typed
   ASCII art once their mesh exists in `floors.glb` with a correct corner pivot.
   - **Verify `6a`/`6b` and `19a`/`19b` against the real physical box** - these were
	 modeled from memory while the user was away from the box with no scan to check
	 against, so they're guesses and might not match the real tiles.
   - Fix the Blender pivot (move to a real corner, re-export) for `9a`/`9b`,
	 `13a`/`13b`, and `21a`/`21b` - their meshes currently have the origin in the
	 shape's interior, which the extraction tool can detect but not correct.
	 All three are unblocked in the meantime via hand-authored ASCII art.
2. ~~Real palette UI~~ — done, see `CreatorPalette.gd`, including the "jump to a
   placed instance" follow-up (via the "Show unavailable" mode + `locate_mesh()`).
   **Unverified in-editor** (built without visual feedback — I have no way to launch
   the Godot editor and see it rendered); worth confirming the layout/icons/jump
   behavior actually work before trusting it.
3. Monster spawns — data model exists, no authoring workflow, no combat/AI yet.
   ~~The story layer (triggers/objectives/variables/prop actions) has a
   designed data model ... but no variable registry, no trigger/objective
   evaluator~~ - the evaluator (`MissionRuntime`, see **Story layer**) is
   done 2026-09-11 and wired into both the round loop and prop-action
   reporting; ~~only one field of authoring UI exists (the objective
   description)~~ - `ObjectivesDialog.gd`'s DAG editor (2026-09-12, see
   **Creator tooling**) covers objectives/conditions/effects/optional
   objectives now, and `PropActionsDialog.gd` (2026-09-13, same section)
   covers `InteractableEntry.actions`/`PropAction` editing.
   ~~`MissionVariable` declarations have no authoring UI, so a
   `Condition`/`Effect` referencing an undeclared name is silently
   inert~~ - done 2026-09-14, `MissionVariablesDialog.gd` (see **Creator
   tooling**), built specifically off a real bug report this exact gap
   caused. Still needed: a real `MissionTrigger` authoring surface
   (nothing edits those at all yet) and a `custom_variables` name dropdown
   for `Condition`/`Effect` rows (currently plain free-text everywhere,
   though at least checkable against `MissionVariablesDialog` now).
   The `exploration`/`interact`/`umbra` token props are placeable meshes
   with `actions`/behavior now authorable via `PropActionsDialog.gd`
   (nothing stops it now that the evaluator exists - still nobody has
   actually authored any on a real token yet).
4. Movement + line-of-sight in the Player — `MissionData.is_walkable()`/`blocks_los()`
   exist and are correct, but nothing calls them yet. The Player now runs the
   basic round loop (see **Story layer** and `MissionPlayer.gd`'s entry above)
   but still has no actual player tokens/movement on the map itself.
5. Wire up `LEVEL_LINK` stairs properly once needed (per-instance `link_from_cell`/
   `link_to_cell`, set when a specific stairs piece is placed in a specific mission).
6. `CreatorSaveLoad`'s New button has no unsaved-changes confirmation.
7. `ComponentInventory` limit warnings only `push_warning()` to the Output panel —
   needs on-screen UI feedback once there's any kind of HUD.
8. Fill in real `ComponentInventory.MAX_COUNTS` from the actual physical box contents.
9. ~~Decide which floor tile faces should use which shared floor material~~ — done
   (Blender remap assigns each tile face one of flagstone/grass/dirt/wood planks),
   and `OfficialAssetMap`/`OfficialAssetOverrides` now cover floor tiles the same
   way they cover the underlay hazards. **Unverified**: confirm in-editor that all
   8 override textures actually apply correctly across every tile face, not just
   the ones spot-checked so far.
10. ~~Snap floor/prop painting to tile-square granularity~~ — done.
	`CreatorController._update_hover()` now snaps `_hovered_cell` to the
	far-corner fine cell of its containing tile-square
	(`_snap_to_tile_square_far_corner()`, reusing
	`FootprintRegistry.fine_cell_to_tile_square()`) for every mesh except
	pillars (`FootprintRegistry.allows_fine_placement()`, exact-name lookup,
	currently just tall/mini/medium) - pillars genuinely place at
	tile-square intersections, everything else only ever made sense at
	whole-tile-square resolution. One snap point fixes placement, the ghost
	preview, and the grid overlay reference all at once, since they all read
	`_hovered_cell`. The reference grid overlay (`_update_grid_overlay()`)
	now also steps at tile-square spacing for the same non-pillar case
	(fine-cell spacing only for pillars) - previously fine-cell spacing for
	everyone. `_snap_to_tile_square_far_corner()` originally had an
	off-by-one (`ts*CELLS_PER_TILE - 1` instead of `ts*CELLS_PER_TILE`),
	caught and fixed by hand-verifying against `expand_footprint()`'s actual
	occupied-cell output rather than trusting the first derivation - the
	wrong version silently shifted every newly-placed non-pillar mesh one
	fine cell off from where the (already-correct)
	`get_tile_square_world_corners()`/spawn-overlay math expected it, which
	is what made the spawn overlay look shifted relative to freshly-placed
	tiles. **Unverified in-editor** - built without visual feedback, worth
	confirming placement across a few different tile shapes (not just
	pillars) before trusting it fully.
11. Player drag-to-interact (`PlayerInteractionController.gd`) - UI, hover
	highlight, and drop-detection are in (see that script's entry above).
	~~Dropping only `print()`s - nothing actually happens yet, needs the
	trigger/effect evaluator~~ - done 2026-09-11, see **Story layer**'s
	`MissionRuntime` entry and `PlayerInteractionController.gd`'s own entry
	above. ~~a picker UI once a prop can offer more than one action~~ -
	done 2026-09-14: `PropAction.conditions` gates which actions are even
	offered, and dropping now always presents a `PlayerDialog.ask_choice()`
	picker (Cancel always included) over whichever ones currently qualify -
	see **Story layer**'s `PropAction` entry and this script's own above.
	Still needed: the game's own
	adjacency rule (interact only with what you're physically near), which
	needs real player-position tracking that doesn't exist; hiding the
	portrait dock during Darkness phase (currently stays up the whole
	time). ~~A real hero roster instead of hardcoded placeholder
	portraits~~ - done, see `EmbarkDialog`/`HeroCatalog` above (still
	placeholder names/art, but a real per-session party now, not a fixed
	count).
12. ~~The Creator's UI has been growing one field/button at a time...~~ —
	the requested 2026-09-10 redesign is done: a top-spanning `MenuBar`
	(File → New/Save/Load/Back) over an `EditorArea` splitting the 3D
	view's space from `SidePanel` - see `MainLayout`'s entry above. **Not**
	a real `HSplitContainer` (the offered fallback was taken instead) -
	`SidePanel` is a static 260px width, since a genuine drag-resizable
	split would need the 3D view rendered through a `SubViewportContainer`
	(it currently renders straight to the main viewport, not through any
	`Control`), which would also touch `CreatorController`'s screen-space
	mouse-ray math - a bigger refactor than this pass, and not yet decided
	whether it's worth doing. Revisit if a static-width panel actually
	proves cramped in practice.
13. ~~`SidePanel/Properties` is an empty placeholder...~~ — the "select a
	placed object" half is done, requested 2026-09-10: `SidePanel/Outline`
	(renamed from `Properties`) now has a real object-browser `Tree`
	(`CreatorOutline.gd`) plus group nodes for organizing placed objects -
	see **Creator outline tree** above and `MissionGroup`/`InteractableEntry.
	id`/`parent_id` in the data layer section. Still remaining: the actual
	per-object PROPERTY EDITING content - `reference_name`/`visible` are
	now real editable fields, and `InteractableEntry.props` (the free-form
	custom dict, including its one well-known `interactible` key) has a
	full add/edit/remove UI via `PropertiesDialog` (`CreatorPropertiesPanel.gd`'s
	"Custom Properties…" button, requested 2026-09-10, see that entry
	above), and `actions`/`PropAction`s (what a player can report doing to
	a prop, and the effects that fire) now has one too - `PropActionsDialog`
	(new 2026-09-13, see **Creator tooling** below), opened via the same
	panel's "Actions…" button, sibling of "Custom Properties…".
	**Organizing objects INTO groups got a lot easier 2026-09-14** (the
	prerequisite the exploration/visibility-cascade goal below was
	actually blocked on): `CreatorController.working_group_id` auto-
	parents newly-DRAWN objects/tiles into a designer-chosen group (the
	persistent toolbar's "Working group:" dropdown, `CreatorToolbar.gd`),
	and the outline tree's new
	multi-select (`SELECT_MULTI`, ctrl+click/shift+click) + `CreatorPropertiesPanel.gd`'s
	"N items selected" panel batch-moves several already-placed objects
	into a group at once, in one undo step - see **Creator outline tree**
	and that panel's own entries above. True drag-and-drop reparenting (a
	"Move to…" context-menu item, and now the batch panel, do the same job
	without it) is still a possible, lower-priority follow-on. **The
	visibility cascade itself is done too, 2026-09-14** - `MissionGroup.visible`/
	`InteractableEntry.visible`/`TilePlacement.visible` now feed
	`MissionData.is_effectively_visible()`, consulted by `LayeredMap`'s
	Player-only paint pass (`apply_mission(mission, respect_visibility)`) -
	see **Story layer**'s "Show Stage" entry for the full mechanism (a new
	`Effect.Type.SHOW_STAGE` reveals a group both in data and on screen,
	fired automatically for the starting room and authorable via
	`PropAction`/`MissionObjective` effects). This closes out the "rooms
	behind a door aren't visible until discovered" exploration mechanic
	this whole grouping-tooling pass was building toward.
14. ~~Wall painting isn't actually used in real missions~~ — done, removed
	2026-09-11 (the user's own words, "the game has no such concept").
	Removed entirely: `WallGridMap` (from `map/LayeredMapCore.tscn`),
	`LayeredMap.wall_grid`, `CreatorController.PaintLayer.WALL` (and its
	`_current_grid()`/`_grid_for_mesh()` branches), `CreatorPalette`'s
	"Wall" tab, `TilePlacement.Layer.WALL` (enum renumbered to
	`{ FLOOR, UNDERLAY }` — the two saved test missions with underlay
	placements, `missions/underlays.tres` and `missions/test_mission.tres`,
	had their `layer = 2` fields migrated to `layer = 1` to match), the
	dead `wall_`-prefix handling in `FootprintRegistry`
	(`LOGICAL_DEFAULTS`/`get_layer()` — no mesh asset ever actually used
	that prefix), and `CreatorOutline.gd`'s WALL-skipping filter (now
	moot - `floor_placements` only ever holds FLOOR entries). Also
	simplified `LayeredMap.rebuild_floor_tiles()`/`apply_mission()`, which
	used to key/branch on `(layer, origin_cell)` specifically to
	distinguish floor from wall on a shared GridMap cell coordinate - now
	keyed by `origin_cell` alone, same as `rebuild_underlay_tiles()`
	already did.
