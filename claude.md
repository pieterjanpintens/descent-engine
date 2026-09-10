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
  needed to *repaint* the floor/wall GridMaps from saved data), `floor_occupied_cells`
  (Dict[Vector3i, Vector3i] — every covered cell → its origin, floor/wall equivalent of
  `occupied_cells`), `occupied_cells` (same but for props), `underlay_placements` /
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
  `is_walkable()`, `blocks_los()`, `get_interactable_at()`,
  `get_level_links_from()`, `get_component_usage()` (tallies floor + underlay +
  prop placements together for `ComponentInventory`).
- `TileEntry` — mesh_item_name, walkable, blocks_los, region_id.
- `TilePlacement` — layer (FLOOR/WALL/UNDERLAY enum), origin_cell, mesh_item_name,
  orientation, `id`/`parent_id` (same outline-tree identity as
  `InteractableEntry`'s, added 2026-09-10 — see **Creator outline tree**
  below; only FLOOR and UNDERLAY placements actually appear in the tree,
  WALL is excluded — wall painting isn't used in real missions, see Open
  items).
- `InteractableEntry` — type (PROP/DOOR/OBJECTIVE/HAZARD/LEVEL_LINK), `id`
  (stable outline-tree identity, assigned once via
  `MissionData.allocate_object_id()` when first placed, never regenerated
  — see **Creator outline tree** below), `parent_id` (empty = directly
  under the mission root in the outline tree, else a `MissionGroup`'s
  `id`), mesh_item_name,
  origin_cell, footprint (Array[Vector3i], rotation-adjusted), orientation,
  blocks_movement, blocks_los, props (free-form Dict — "visible"/"interactible"
  bool keys are well-known, read by the runtime directly, both default true when
  absent), `actions` (Array[PropAction] — see **Story layer**), `reference_name`
  (optional human-chosen id, e.g. "front_door" — see **Story layer**; distinct
  from `id` above — `reference_name` is the optional, human-facing,
  Story-layer-facing one, `id` is internal bookkeeping nobody types by hand),
  plus `link_from_cell`/`link_to_cell`/`link_bidirectional` for stairs
  (LEVEL_LINK type) — **not yet wired up to real stairs instances**, see
  Open Items.
- `MissionGroup` — a purely organizational node in the Creator's outline
  tree, NOT a spatial/gameplay concept: `id`, `name`, `parent_id` (groups
  can nest under groups), `visible` (the one property meant to cascade to
  a group's members eventually — stored but not yet consumed by any
  evaluator, see **Creator outline tree** below). `MissionData.groups`.
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
Operator enum + value) and `Effect` (variable_name + value, a SET). Both
deliberately basic for now - no AND/OR nesting, no cross-object queries, no
increment/expression support. `conditions: Array[Condition]` anywhere in this
system is an implicit AND across every entry.

**One variable registry, three ways to fill it**: `MissionVariable` (name +
Type enum [BOOL/INT/FLOAT/STRING] + default_value) declares a custom
variable in `MissionData.custom_variables`; the runtime provides its own
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

**`MissionObjective`** (new, in `MissionData.objectives`) — win AND loss
conditions in one list, deliberately: "round counter exceeded N" and "the
final goal is achieved" are the same shape (checkpoint + conditions), just
opposite `outcome` (WIN/LOSE enum). Evaluated in `priority` order at each
objective's checkpoint (typically `AFTER_DARKNESS_PHASE`); first one whose
conditions all hold ends the game with that outcome - the engine's own
win/loss check is just another objective, not a special case.

**`MissionPlayer.gd` now walks the checkpoint loop** (Player phase ↔ Darkness
phase, round counter, see that script's own entry above) - but it's still
just the loop shell. Live variable values (round_number/player_count aren't
actually exposed as variables yet, just a plain `current_round` int), and
actually firing triggers/evaluating objectives at each checkpoint, are both
still TODO-commented stubs in `_run_darkness_and_loop()`, not implemented.

**Still not designed/built**: the runtime variable registry itself (nothing
holds MissionVariable values live yet - `MissionRuntime` or similar,
distinct from `MissionData`); the evaluator that reads that registry to fire
triggers/objectives; any authoring UI for actions/triggers/variables beyond
the single objective-description field (`%ObjectiveLineEdit` in
`CreatorSaveLoad.gd`) - expect new UI surfaces, e.g. a per-prop inspector, a
real objectives list with conditions; player count (2-6, not the physical
box's 4 - all 6 playable characters should be usable, kept as a later
difficulty-scaling input, not yet asked for anywhere) and action economy (3
actions/turn, 1 must be move - the app doesn't need to enforce this, the
physical game already does, move is a "dummy action" the app can ignore);
combat/monster AI (explicitly out of scope for the first working version).

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
  - `get_layer(mesh_name)` → `"floor"`/`"wall"`/`"underlay"`/`"prop"` — the single
	source of truth for which GridMap a mesh belongs in (all four GridMaps share
	**one** MeshLibrary, so nothing else distinguishes them). Tile faces
	auto-detected by name pattern (`^\d+[ab]$`); `water`/`acid`/`lava`/`spikes` are
	explicit `MESH_LAYER` overrides routing to `"underlay"` (no shared naming
	convention to auto-detect from, unlike `wall_`); everything else defaults to
	`"prop"` unless overridden.
  - `LOGICAL_DEFAULTS` (prefix-based) / `LOGICAL_OVERRIDES` (exact-name) — auto-fill
	walkable/blocks_los from mesh naming convention.
  - `mark_occupied()` / `clear_occupied()` — occupancy bookkeeping helpers.
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

**Core logic** (`map/`, root of the reusable scene):

- `LayeredMap.gd` — attached to `LayeredMapCore.tscn`'s root. Owns `floor_grid`/
  `wall_grid`/`prop_grid`/`underlay_grid` (@onready refs to child GridMaps) and
  `mission`. `_ready()` positions the non-floor layers relative to floor: `prop_grid`
  sits `+floor_thickness` above (so props render on top of the floor surface);
  `underlay_grid` stays at the SAME Y as floor (`Vector3.ZERO`, not offset below it)
  — it's meant to show through exactly where the floor doesn't cover it, not sit
  hidden beneath. Two directions of sync:
  - **Read** (painting → data): `sync_prop_cell(origin)`, `rebuild_floor_tiles()`
	(floor + wall), and `rebuild_underlay_tiles()` walk the painted GridMap cells and
	populate `MissionData`. Underlay is a deliberately SEPARATE rebuild pass from
	floor/wall (not a third case folded into `rebuild_floor_tiles()`) — see the
	`underlay_placements` note above for why.
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
  - **Write** (data → painting): `apply_mission(mission)` clears and repaints all
	four GridMaps from a loaded `MissionData` — used identically by both the Player
	(to render a loaded mission) and the Creator (to open an existing mission for
	continued editing).
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
- **`CanvasLayer/MainLayout`** (`MissionMap.tscn`) — the Creator's overall
  shell, a full-rect `VBoxContainer`: a top-spanning `MenuBar` (see
  `CreatorSaveLoad.gd` below) stacked above an `EditorArea` `HBoxContainer`
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
  (Floor/Wall/Prop/Underlay) plus a scrollable icon grid for whichever layer
  is active, replacing blind `,`/`.` cycling as the primary way to pick a mesh
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
  - **Two display modes**, via a "Show unavailable" checkbox: default hides any mesh
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
	`tall` pillar).
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
  - Controls: `D` toggle Draw/Select mode, Left-click place (Draw mode) /
	select (Select mode), Shift+Left-click erase (Draw mode only), `,`/`.` cycle mesh (not Tab —
	conflicts with UI focus once real Buttons exist), `R` rotate, `L` cycle layer
	filter (Floor → Wall → Prop → Underlay), PageUp/PageDown change level, `O` toggle
	occupancy overlay, `N` toggle tile name labels — one `Label3D` per placed
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
	different square than the one that actually gets toggled.
- **Creator outline tree** (`CreatorOutline.gd`, attached to
  `SidePanel/Outline/Split/OutlineTree`, a `Tree`) — a scene-graph-style
  object browser: every placed `InteractableEntry` (prop/door/hazard/
  level-link) plus every FLOOR `TilePlacement` and every `underlay_placements`
  entry (floor/underlay tiles joined 2026-09-10, at the user's own prompting
  — "they are pretty unique on their own" — each is its own distinct placed
  instance too), plus optional, purely organizational `MissionGroup` nodes
  the designer can create to group related objects (e.g. "everything in
  this room"), requested 2026-09-10 as the "select a placed object"
  prerequisite Open item #13 had been waiting on.
  - **WALL placements are deliberately excluded** — the user has indicated
	wall painting isn't actually used in real missions and flagged it as a
	candidate for removal later (not attempted here, see Open items). Wall
	`TilePlacement`s still get an `id` assigned (they share
	`rebuild_floor_tiles()` with floor), this script just skips them when
	building tree items — see `_find_tile_by_id()`/`_add_tile_item()`.
  - Floor/underlay tiles reuse the exact same `id`/`parent_id` machinery as
	interactables even though `rebuild_floor_tiles()`/
	`rebuild_underlay_tiles()` do a full clear-and-rebuild rather than
	interactables' incremental single-cell sync (`sync_prop_cell()`) — both
	rebuild functions now build a lookup of the PREVIOUS placements (keyed
	by layer+origin_cell for floor/wall, origin_cell alone for underlay,
	since it only has one `Layer` value) before clearing, and carry an old
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
  - Node labels: an object shows `reference_name` if set else
	`mesh_item_name`; a floor/underlay tile always shows its
	`mesh_item_name` (no `reference_name` equivalent exists for
	`TilePlacement`, so these commonly repeat, e.g. several "1a" entries —
	expected, same as an unnamed prop); a group shows its own `name`; the
	always-present root item shows `mission.mission_name` (or "Untitled
	Mission"). Pre-existing saved missions have interactables/floor/underlay
	entries with `id == ""` — lazily adopted into the id system the first
	time the tree sees them (`refresh()`'s migration step), so old missions
	don't need a one-off conversion.
  - `SelectionType` has a fourth case, `TILE`, for floor/underlay entries
	(distinct from `OBJECT`/`InteractableEntry`, since `TilePlacement` is a
	different Resource with different fields — no `reference_name`/
	`actions`/`props`). Selecting an item emits `selected(type, id)` —
	`CreatorPropertiesPanel.gd` (below) is the only listener, same "talk
	only through public API + signals" convention as `CreatorPalette`/
	`CreatorController`. Selecting a placed OBJECT or TILE also jumps the
	camera to it via `CreatorController.jump_to_cell(origin_cell, grid)`
	(the precise, per-instance counterpart to `locate_mesh()`, which only
	finds the first instance of a mesh name — not precise enough once
	several props/tiles share a mesh; `grid` defaults to `prop_grid` for an
	OBJECT, and is passed explicitly as `floor_grid`/`underlay_grid` for a
	TILE, tagged in that tree item's own metadata at build time so no
	re-lookup is needed) — the "find object back" half of this feature's
	purpose. A rebuild re-selects whatever was selected before it, falling
	back to root only if that item no longer exists (e.g. it just got
	erased) — and deliberately does NOT re-jump the camera on a
	rebuild-driven reselection, only on an actual click, so painting
	elsewhere on the map while an object happens to be selected doesn't
	keep yanking the camera back to it.
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
	objects. "Move to…" is guarded against creating a parent cycle (a
	group can't be moved into its own descendant — objects/tiles are never
	parents themselves, so this only matters for moving a group).
	Group rename is inline-editable (double-click, or via the
	menu triggering `Tree.edit_selected()`), same native Tree UX as a file
	explorer.
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
  outline tree's ROOT is selected, and a minimal read-only placeholder
  (name/type/cell) when an object or group is selected. This is
  intentionally the ENTIRE scope of this pass's "properties panel" work —
  real property editing for objects/groups is explicit future work, not
  attempted here. Talks to `CreatorOutline` only through its `selected`
  signal, same convention as above.
- `CreatorSaveLoad.gd` — attached to `MenuBar/File`, a `PopupMenu` under the
  top-spanning `MenuBar` (`CanvasLayer/MainLayout/MenuBar`, see
  `MainLayout`'s entry above) - New/Save/Load/Back are menu items now
  (added via `add_item()` in `_ready()`, dispatched through one
  `id_pressed` handler), not standalone Buttons in a toolbar row. Holds a
  child `FileDialog` (must be **Access = Resources**, not File System, to
  get usable `res://` paths). Reuses `MissionIO` + `LayeredMap.apply_mission()`.
  Also owns `%ObjectiveLineEdit` and `%MinPlayersSpinBox`/`%MaxPlayersSpinBox`
  - those live in `SidePanel/Outline/Split/Inspector/PropertiesFields`
  (see `CreatorPropertiesPanel.gd`'s entry above), not this script's own
  node. **Live-synced as of 2026-09-10** (for undo/redo, see
  `OperationHistory.gd` below) - previously documented as "only read/
  written at Save/New/Load time, not live-synced", that changed because
  meldable, undoable operations need a live write to react to. The
  SpinBoxes write straight to `mission.min_players`/`max_players` on
  `value_changed`, each wrapped in `operation_history.record()`; the
  `LineEdit` commits on `text_submitted`/`focus_exited` (not per
  keystroke - that would flood the undo stack one entry per character).
  `_apply_objective_field()`/`_apply_player_count_fields()` are still
  called once more at Save time as a harmless safety net (catches an
  edit that never got committed - e.g. text typed but Enter never
  pressed - before Save was clicked). A new `_on_mission_objects_changed()`
  listens for `LayeredMap.mission_objects_changed` (Load/New, and now
  undo/redo) to refresh these fields FROM the mission, replacing the old
  explicit `_refresh_objective_field()`/`_refresh_player_count_fields()`
  calls that used to sit directly in `_on_new_button_pressed()`/
  `_load_from()`. The old `_ready()` that pinned the toolbar row's right
  edge against `CreatorPalette.PANEL_WIDTH` (a stopgap for the row
  overlapping the palette) is gone - moot now that there's no toolbar row
  to overlap anything, see Open item #12.
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
	nothing to undo/redo.
  - **Unverified in-editor**, same caveat as everything else built this
	session without the ability to launch Godot and see it rendered -
	especially worth confirming: a paint stroke → undo reverts GridMap +
	tree + palette together; rapid SpinBox clicks → one undo reverts all
	of them; undoing past a group delete → members reattach to the group,
	not left orphaned at root.
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

- `MainMenu` — Play (opens a `FileDialog` over `res://missions/`, then loads
  `MissionPlayer.tscn` with the chosen path via `GameState`) / Editor (loads the
  Creator scene) / Exit.
- `MissionPlayer.gd` — loads the mission via `MissionIO`, calls
  `%LayeredMap.apply_mission()`, shows mission name + counts in a label. Now runs
  the basic round loop (see **Story layer**'s `RoundCheckpoint.Checkpoint`):
  round 1 first shows the spawn area (if authored, see below) and waits for
  confirmation, then Player phase → "All players done" button → walks every
  remaining checkpoint (mostly no-ops, commented where a future
  trigger/objective evaluation pass hooks in) → Darkness phase (a flat
  `darkness_phase_duration` timed pause standing in for real world-effect
  resolution + monster AI, neither built yet) → loops back to Player phase,
  round incremented. `%DarknessOverlay` (a full-rect `ColorRect`,
  `mouse_filter = IGNORE` so it darkens without blocking clicks) is the only
  phase-change visual so far. Shows the mission's WIN `MissionObjective`'s
  description if one was authored. Still **no actual movement/LOS/
  player-position tracking** — the app never tracks real positions (see
  **Story layer**), which is why "players spawn" is just a highlighted area
  + a confirmation dialog, not anything the app verifies.
- `PlayerDialog.gd` (`%Dialog` in `MissionPlayer.tscn`) — reusable async
  dialog, built at runtime (same reasoning as `CreatorPalette` - content/
  buttons vary per call): `ask_ok(text)`, `ask_yes_no(text) -> bool`,
  `ask_count(text, min, max) -> int`, `ask_narrative(pages) -> void`
  (OK/NEXT/BACK through multiple pages). **Modal** while visible - the root
  Control is a full-screen dim scrim (`mouse_filter = STOP`, deliberately
  relying on the same STOP-blocks-everything-behind-it mechanism
  `CreatorPalette`'s background bug worked through earlier this session,
  rather than working around it) so nothing else (camera, the End Phase/Back
  buttons, the world) is reachable until answered; the actual visible box
  (text + buttons) is a child centered near the top, not the root itself.
  This is the mechanism **Story layer**'s "asked" variables (things the app
  can't compute, only ask - "is a player on tile 2a") are meant to use once
  the evaluator exists; not wired to variables yet, just the reusable UI
  piece plus the one caller so far (`ask_ok` for spawn confirmation).
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
  `InteractableEntry` with a non-empty `actions` list highlights its
  footprint cells (filled quads, same corner-math style as every other
  overlay in this project), and releasing over one just `print()`s which
  hero interacted with what - no `PropAction` actually fires yet, that needs
  the trigger/effect evaluator (see **Story layer**), which doesn't exist.
  Deliberately skips Godot's built-in Control drag-and-drop
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

- **`map/LayeredMapCore.tscn`** — just `LayeredMap.gd` + the four GridMaps
  (FloorGridMap/WallGridMap/PropGridMap/UnderlayGridMap, sharing one MeshLibrary and
  identical cell_size). Instanced by both of the below.
- **`map/MissionMap.tscn`** (the Creator) — instances `LayeredMapCore` as `%LayeredMap`,
  plus `Camera3D` (FreeLookCamera), `DirectionalLight3D`, `DebugSync`,
  `CreatorController`, and a `CanvasLayer/MainLayout` shell: a top-spanning
  `MenuBar` (File → New/Save/Load/Back, `CreatorSaveLoad.gd`; Edit →
  Undo/Redo, `OperationHistory.gd`, see **Creator tooling** below) above an
  `EditorArea` splitting the 3D view's space (left, just an empty
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
three GridMaps (Floor/Wall/Prop) consume — keep them around as the mesh-authoring
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
- All four GridMaps (Floor/Wall/Prop/Underlay) intentionally **share one
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
- `FileDialog.access` must be **`Resources`**, not `File System` — the latter returns
  absolute OS paths that don't resolve the same way as `res://` paths for
  `ResourceLoader`.
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
   The story layer (triggers/objectives/variables/prop actions) has a designed
   data model and `MissionPlayer.gd` now runs the round-loop shell (Player
   phase ↔ Darkness phase, see **Story layer**) - but no variable registry, no
   trigger/objective evaluator, and only one field of authoring UI (the
   objective description) exist yet; those are the actual next step. The
   `exploration`/`interact`/`umbra` token props are placeable meshes with no
   behavior wired up until that evaluator exists.
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
10. ~~Snap floor/wall/prop painting to tile-square granularity~~ — done.
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
	highlight, and drop-detection are in (see that script's entry above),
	but dropping only `print()`s - nothing actually happens yet. Needs, in
	rough order: the trigger/effect evaluator (see **Story layer**) so a
	drop can actually fire a `PropAction`'s effects; the game's own
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
	per-object PROPERTY EDITING content (editing
	`InteractableEntry.reference_name`, `actions`/`PropAction`s, `props`
	dict keys like visible/interactible - see **Story layer**) -
	`CreatorPropertiesPanel.gd` currently shows only a read-only name/type/
	cell summary for a selected object/group, real editing was explicitly
	deferred by the user to a later pass ("modify their properties in a
	later stage"); true drag-and-drop reparenting in the tree (a "Move
	to…" context-menu item does the same job without it, see **Creator
	outline tree** above); and wiring `MissionGroup.visible` into an actual
	cascading effect once the Story layer's trigger/effect evaluator exists
	(still doesn't - see **Story layer**).
14. **Wall painting isn't actually used in real missions** (the user's own
	words, 2026-09-10) - `WallGridMap`/`TilePlacement.Layer.WALL` and
	everything that handles it (`CreatorController`'s Wall layer filter,
	`rebuild_floor_tiles()` painting both floor+wall in one pass,
	`CreatorOutline.gd` explicitly skipping WALL when building the tree)
	is a candidate for removal in a future pass - not attempted here, this
	was flagged in passing while scoping the outline tree's floor/underlay
	support (see **Creator outline tree** above), not something anyone has
	asked to actually remove yet.
