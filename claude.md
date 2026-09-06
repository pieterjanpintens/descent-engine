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
its scene, and several scripts are genuinely shared across Creator/Player). All three
autoload scripts (`FootprintRegistry`, `GameState`, `ComponentInventory`) live
together in `autoload/`. (This folder was called `mission_data/` until it was renamed
to `scripts/` once it held far more than data-resource classes.)

**Data layer** (scripts in `scripts/`) — pure Resource classes, no logic beyond helpers:

- `MissionData` — root resource. Fields: `mission_name`, `grid_size`, `cell_size`,
  `tiles` (Dict[Vector3i, TileEntry] — flattened per-cell walkable/LOS data),
  `floor_placements` (Array[TilePlacement] — raw paint records: origin+mesh+orientation,
  needed to *repaint* the floor/wall GridMaps from saved data), `floor_occupied_cells`
  (Dict[Vector3i, Vector3i] — every covered cell → its origin, floor/wall equivalent of
  `occupied_cells`), `occupied_cells` (same but for props), `interactables`
  (Array[InteractableEntry]), `monster_spawns`, `triggers`. Methods: `get_tile()`,
  `is_walkable()`, `blocks_los()`, `get_interactable_at()`, `get_level_links_from()`,
  `get_component_usage()`.
- `TileEntry` — mesh_item_name, walkable, blocks_los, region_id.
- `TilePlacement` — layer (FLOOR/WALL enum), origin_cell, mesh_item_name, orientation.
- `InteractableEntry` — type (PROP/DOOR/OBJECTIVE/HAZARD/LEVEL_LINK), mesh_item_name,
  origin_cell, footprint (Array[Vector3i], rotation-adjusted), orientation,
  blocks_movement, blocks_los, props (free-form Dict), plus `link_from_cell`/
  `link_to_cell`/`link_bidirectional` for stairs (LEVEL_LINK type) — **not yet wired
  up to real stairs instances**, see Open Items.
- `MonsterSpawn`, `MissionTrigger` — data model exists, unused so far (no authoring UI).

**Autoloads** (`autoload/`):

- `FootprintRegistry` — the single source of truth for shape/rotation/layer-classification
  math. Key pieces:
  - `FOOTPRINTS` — hand-authored shapes in **tile-square units** (not fine cells),
	keyed by exact mesh item name. Currently has: `1a`/`1b`/`2a`/`2b` (2×3 rectangle,
	origin = bottom-right corner), `7a`/`7b` (plus/cross shape, origin = a specific
	marked cell), `stair` (3×2, origin = the low point), `tall`/`mini`/`medium`
	(pillars — see the calibration note below, **not** `Vector3i.ZERO`).
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
  - `get_layer(mesh_name)` → `"floor"`/`"wall"`/`"prop"` — the single source of truth
	for which GridMap a mesh belongs in (all three GridMaps share **one** MeshLibrary,
	so nothing else distinguishes them). Tile faces auto-detected by name pattern
	(`^\d+[ab]$`); everything else defaults to `"prop"` unless overridden.
  - `LOGICAL_DEFAULTS` (prefix-based) / `LOGICAL_OVERRIDES` (exact-name) — auto-fill
	walkable/blocks_los from mesh naming convention.
  - `mark_occupied()` / `clear_occupied()` — occupancy bookkeeping helpers.
- `ComponentInventory` — tracks physical piece counts so the Creator can block designs
  that need more copies of a tile/pillar than physically exist. `MESH_TO_GROUP` groups
  both faces of a double-sided tile (`1a`/`1b`) into one shared count pool (they're one
  physical object). `MAX_COUNTS` currently has **placeholder numbers** — needs real
  counts from the actual component list.
- `GameState` — trivial: holds `current_mission_path` to pass between scenes (menu →
  player) since `change_scene_to_file()` takes no parameters.

**Core logic** (`map/`, root of the reusable scene):

- `LayeredMap.gd` — attached to `LayeredMapCore.tscn`'s root. Owns `floor_grid`/
  `wall_grid`/`prop_grid` (@onready refs to child GridMaps) and `mission`. Two
  directions of sync:
  - **Read** (painting → data): `sync_prop_cell(origin)` and `rebuild_floor_tiles()`
	walk the painted GridMap cells and populate `MissionData`.
  - **Write** (data → painting): `apply_mission(mission)` clears and repaints all
	three GridMaps from a loaded `MissionData` — used identically by both the Player
	(to render a loaded mission) and the Creator (to open an existing mission for
	continued editing).
  - `find_item_id(grid, mesh_name)` — MeshLibrary name→id lookup (public, used by
	`CreatorController` too).
- `MissionIO` (`scripts/MissionIO.gd`) — static `save_mission()`/`load_mission()`
  wrapping `ResourceSaver`/`ResourceLoader`. Verified round-trip correctness including
  nested Resources, typed arrays, and Vector3i-keyed dictionaries.

**Creator tooling** (`creator/`):

- `CreatorController.gd` — the in-game paint tool (mimics Godot's own GridMap panel,
  but as a runtime game feature). Public API (`select_mesh`, `cycle_mesh`,
  `select_layer`) is deliberately the only thing that touches selection state, so a
  future palette UI can call the same methods instead of duplicating logic.
  - **Critical design point**: the *destination* GridMap for a placement is always
	derived from `FootprintRegistry.get_layer(selected_mesh)` (via `_target_grid()`),
	**never** from the UI's current layer filter (`current_layer`/`L` key) — the
	filter only controls which meshes `cycle_mesh()` offers to browse. This was a real
	bug once (props landing in FloorGridMap) and is now structurally prevented.
  - Placement: raycast/plane-intersection based hover picking, ghost mesh preview,
	rotation (`R`), physical-limit checking before placing (`ComponentInventory`).
  - Erase: **real physics raycast** against GridMap collision (not plane math) —
	translates the hit cell back to the actual painted origin via
	`occupied_cells`/`floor_occupied_cells`, with a column-fallback (match X/Z, ignore
	Y) for meshes taller than one cell (e.g. the `tall` pillar).
  - Debug overlays, all toggleable: ghost preview, reference grid lines, world-origin
	axis gizmo, and an occupancy overlay (`O` key) that draws wireframe boxes of what
	`floor_occupied_cells`/`occupied_cells` actually think is covered — built assuming
	GridMap's **Center X/Y/Z are OFF** (map_to_local returns a cell's corner, not
	center) — this was essential for diagnosing the footprint bugs.
  - Controls: Left-click place, Shift+Left-click erase, `,`/`.` cycle mesh (not Tab —
	conflicts with UI focus once real Buttons exist), `R` rotate, `L` cycle layer
	filter, PageUp/PageDown change level, `O` toggle occupancy overlay.
- `CreatorSaveLoad.gd` — Save/Load/New buttons + a `FileDialog` (must be
  **Access = Resources**, not File System, to get usable `res://` paths). Reuses
  `MissionIO` + `LayeredMap.apply_mission()`.
- `FreeLookCamera.gd` — editor-style navigation: right-click-drag to look, WASD to
  move while dragging, scroll wheel to dolly, Shift to boost speed.
- `debug/DebugSync.gd` — temporary manual test harness. Keys **1/2/3/4** (deliberately
  *not* F5-F8, which are Godot's own Run/Run Scene/Pause/Stop shortcuts and get
  intercepted by the editor): 1 = sync+dump MissionData to Output, 2 = clear
  everything, 3 = save, 4 = load-and-dump-separately (for comparing round-trips).

**App shell** (`ui/`, `player/`):

- `MainMenu` — Play (opens a `FileDialog` over `res://missions/`, then loads
  `MissionPlayer.tscn` with the chosen path via `GameState`) / Editor (loads the
  Creator scene) / Exit.
- `MissionPlayer.gd` — loads the mission via `MissionIO`, calls
  `%LayeredMap.apply_mission()`, shows mission name + counts in a label. Currently
  **static** — no movement, no interaction, just a rendered map.

## Scene structure (post-refactor)

Split into a minimal reusable piece plus two separate wrappers, specifically so
Play mode doesn't inherit Creator-only tooling (this was a real bug that got fixed):

- **`map/LayeredMapCore.tscn`** — just `LayeredMap.gd` + the three GridMaps
  (FloorGridMap/WallGridMap/PropGridMap, sharing one MeshLibrary and identical
  cell_size). Instanced by both of the below.
- **`map/MissionMap.tscn`** (the Creator) — instances `LayeredMapCore` as `%LayeredMap`,
  plus `Camera3D` (FreeLookCamera), `DirectionalLight3D`, `DebugSync`,
  `CreatorController`, and a `CanvasLayer` with the `CreatorSaveLoad` Save/Load/New
  buttons.
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

- `Basis.from_orthogonal_index()` / `Basis.get_orthogonal_index()` are **not exposed
  to GDScript**. Use `GridMap.get_cell_item_basis(cell)` (read) and
  `GridMap.get_orthogonal_index_from_basis(basis)` (write) instead — both are instance
  methods on GridMap, so borrow any GridMap node purely for the calculation.
- All three GridMaps (Floor/Wall/Prop) intentionally **share one MeshLibrary** — you
  cannot tell "this is a floor tile" from "this is a pillar" by which grid's library
  you query. `FootprintRegistry.get_layer()` is the actual source of truth.
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

## Current data authored so far

- Floor tiles: `1a`/`1b`, `2a`/`2b` (2×3 rectangle), `7a`/`7b` (plus/cross) — **19 of
  ~22 tiles still need their shapes measured and entered**.
- `stair` — 3×2 shape entered; the low/high point distinction and `LEVEL_LINK` wiring
  (which cells it actually connects, and across how many levels) is **not yet done** —
  that's mission-instance-specific data, not something the mesh shape alone defines.
- Pillars `tall`/`mini`/`medium` — 1×1 tile-square, correctly calibrated.
- `ComponentInventory.MAX_COUNTS` — placeholder numbers throughout, needs real counts
  from the physical component list.

## Open items / natural next steps

1. Finish authoring the remaining ~19 floor tile shapes (now that placement/rotation
   is verified trustworthy, this should go faster than the first few did).
2. Real palette UI (buttons/icons) instead of keyboard `,`/`.` cycling — architecture
   is already prepared for this (see `CreatorController`'s public API note above).
3. Monster spawns / mission triggers — data model exists, no authoring workflow yet.
4. Movement + line-of-sight in the Player — `MissionData.is_walkable()`/`blocks_los()`
   exist and are correct, but nothing calls them yet; the Player is still just a
   static rendered map.
5. Wire up `LEVEL_LINK` stairs properly once needed (per-instance `link_from_cell`/
   `link_to_cell`, set when a specific stairs piece is placed in a specific mission).
6. `CreatorSaveLoad`'s New button has no unsaved-changes confirmation.
7. `ComponentInventory` limit warnings only `push_warning()` to the Output panel —
   needs on-screen UI feedback once there's any kind of HUD.
8. Fill in real `ComponentInventory.MAX_COUNTS` from the actual physical box contents.
