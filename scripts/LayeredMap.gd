class_name LayeredMap
extends Node3D

## Attach to a scene containing three GridMap children named FloorGridMap,
## PropGridMap, and UnderlayGridMap - all sharing the same MeshLibrary and
## cell_size. This node keeps the layers visually stacked and exposes
## helpers to sync painted cells into a MissionData resource.
##
## Scene layout expected:
## LayeredMap (this script)
##  |- FloorGridMap     (GridMap)
##  |- PropGridMap      (GridMap)
##  |- UnderlayGridMap  (GridMap)

@export var mission: MissionData
@export var floor_thickness: float = 0.2

## Fires whenever mission.interactables or mission.groups changes shape
## (an object placed/erased/repainted, or a group created/renamed/deleted/
## reparented) - CreatorOutline.gd listens to this to know when to rebuild
## its tree. Deliberately NOT fired for floor/underlay edits - those
## aren't part of the outline tree, see CreatorOutline.gd's own doc
## comment for why.
signal mission_objects_changed

@onready var floor_grid: GridMap = $FloorGridMap
@onready var prop_grid: GridMap = $PropGridMap
@onready var underlay_grid: GridMap = $UnderlayGridMap

var _spawn_overlay: MeshInstance3D
var _spawn_overlay_mesh: ImmediateMesh

## Reddish counterpart to the yellow player-spawn overlay above, for
## MissionData.monster_spawns (new 2026-09-19) - same tile-square cells,
## same quad geometry, just its own mesh/color so both can show at once.
var _monster_overlay: MeshInstance3D
var _monster_overlay_mesh: ImmediateMesh
const MONSTER_SPAWN_COLOR := Color(1.0, 0.2, 0.15, 0.5)

## One colour per monster spawn (by its index in mission.monster_spawns,
## wrapping) so several spawn areas can be told apart; the CreatorController's
## active spawn draws at a higher alpha. Reddish/warm first, per the
## original "make the color we draw with reddish" request.
const MONSTER_SPAWN_PALETTE := [
	Color(1.0, 0.2, 0.15),
	Color(1.0, 0.55, 0.1),
	Color(0.85, 0.15, 0.6),
	Color(0.6, 0.3, 0.9),
	Color(0.2, 0.6, 1.0),
	Color(0.2, 0.8, 0.5),
]

## The spawn the Creator is currently drawing into (see
## CreatorController.active_monster_spawn_id) - only affects overlay
## brightness. Set by the controller before it calls
## refresh_monster_spawn_overlay(); kept here so apply_mission()'s own
## refresh (undo/redo/load) keeps the highlight.
var monster_overlay_active_id: String = ""

## Number labels for the monster spawn tiles (Creator only).
var _monster_labels: Node3D

## Violet overlay for MissionData.los_blocker_cells (virtual line-of-sight walls, Creator only).
var _blocker_overlay: MeshInstance3D
var _blocker_overlay_mesh: ImmediateMesh
const LOS_BLOCKER_COLOR := Color(0.55, 0.3, 0.95, 0.5)
var _blocker_lines: MeshInstance3D
var _blocker_lines_mesh: ImmediateMesh
## The Player's wall outline is drawn like charcoal: near-black, a wobbly path, uneven thickness and a second thinner grainy pass.
const BLOCKER_LINE_COLOR := Color(0.03, 0.025, 0.02, 0.96)
## A faint pale smudge drawn under the stroke so black still reads on a dark floor (like charcoal dust).
const BLOCKER_DUST_COLOR := Color(0.78, 0.74, 0.66, 0.1)
const CHARCOAL_STEP := 0.12        # world units between the points of a stroke (fine, so it reads as smooth, not blocky)
const CHARCOAL_LATTICE := 1.1      # world units between the random values the wobble is interpolated from
const CHARCOAL_WOBBLE := 0.1      # how far the stroke may wander off the straight edge
const CHARCOAL_WIDTH := 0.24       # base thickness of the main stroke


func _ready() -> void:
	# Only position differs between layers - cell_size and XZ cell
	# coordinates must stay identical across all three or occupancy lookups
	# (and the footprint registry) will target the wrong cells. Underlay
	# stays at the SAME Y as floor (not offset below it) - it's meant to be
	# visible exactly where the floor doesn't cover it, not hidden beneath.
	prop_grid.position = Vector3(0, floor_thickness, 0)
	underlay_grid.position = Vector3.ZERO

	# The game's own prop models, when the user imported them and wants them (OriginalPropsLibrary) - all four
	# grids must use the same library.
	if PlayerSettings.use_original_props:
		var original := OriginalPropsLibrary.load_library()
		if original != null:
			floor_grid.mesh_library = original
			prop_grid.mesh_library = original
			underlay_grid.mesh_library = original

	# All four grids share one MeshLibrary, so this only needs to run once -
	# swaps in the user's own official-game textures (if they've run the
	# importer tool against their own install) in place of the shipped
	# placeholders. A no-op if no override files are present.
	OfficialAssetOverrides.apply_overrides(floor_grid.mesh_library)

	_setup_spawn_overlay()
	_setup_monster_overlay()
	_blocker_overlay_mesh = ImmediateMesh.new()
	_blocker_overlay = _make_overlay_node(_blocker_overlay_mesh)
	mission_objects_changed.connect(_sync_editor_hidden)


## Id of the blocker the Creator is drawing into (drawn more opaque), see CreatorController.active_los_blocker_id.
var blocker_overlay_active_id: String = ""


## The violet LOS blocker squares in the Creator: every blocker, visible in its stage or not (the author edits hidden stages too).
func refresh_blocker_overlay() -> void:
	_blocker_overlay_mesh.clear_surfaces()
	var any := false
	for blocker in mission.los_blockers:
		if not blocker.cells.is_empty() and not is_editor_hidden(blocker):
			any = true
			break
	if not any:
		_blocker_overlay.visible = false
		return
	_blocker_overlay_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for blocker in mission.los_blockers:
		if is_editor_hidden(blocker):
			continue
		var color := LOS_BLOCKER_COLOR
		color.a = 0.65 if blocker.id == blocker_overlay_active_id else 0.35
		for cell in blocker.cells:
			var corners := get_tile_square_world_corners(cell)
			for v in [corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]]:
				_blocker_overlay_mesh.surface_set_color(color)
				_blocker_overlay_mesh.surface_add_vertex(v)
	_blocker_overlay_mesh.surface_end()
	_blocker_overlay.global_transform = Transform3D.IDENTITY
	_blocker_overlay.visible = true


## The Player's view of the LOS blockers: a fine line along the outer edge of each blocked area (adjacent squares merge into one outline),
## on the floor, so the table can see where shots are blocked. Only blockers in force count (MissionData.is_effectively_visible: one in a
## stage that has not been revealed yet shows nothing). Call again after a stage is revealed (repaint_visible_entries() does).
func refresh_blocker_lines() -> void:
	var cells: Array[Vector3i] = []
	for blocker in mission.los_blockers:
		if mission.is_effectively_visible(blocker):
			cells.append_array(blocker.cells)
	if _blocker_lines == null:
		_blocker_lines_mesh = ImmediateMesh.new()
		_blocker_lines = _make_overlay_node(_blocker_lines_mesh)
	_blocker_lines_mesh.clear_surfaces()
	if cells.is_empty():
		_blocker_lines.visible = false
		return
	var squares: Dictionary = {}
	var unique: Array[Vector3i] = []
	for cell in cells:
		var key := Vector2i(cell.x, cell.z)
		if not squares.has(key):  # several blockers may cover the same square: one outline
			squares[key] = true
			unique.append(cell)
	# the outer edges of the blocked area, merged into straight runs so a long wall is ONE stroke (no joints at every square)
	var runs: Dictionary = {}  # [axis, rounded constant coordinate] -> Array of Vector2(min, max) along the axis
	var height := 0.0
	for cell in unique:
		var corners := get_tile_square_world_corners(cell)
		var centre := (corners[0] + corners[2]) * 0.5
		height = corners[0].y
		for i in 4:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 4]
			# which neighbouring square lies across this edge (world X/Z = tile x/z)?
			var outward := (a + b) * 0.5 - centre
			var neighbour := Vector2i(cell.x, cell.z)
			if absf(outward.x) > absf(outward.z):
				neighbour.x += 1 if outward.x > 0.0 else -1
			else:
				neighbour.y += 1 if outward.z > 0.0 else -1
			if squares.has(neighbour):
				continue
			var along_x := absf(b.x - a.x) > absf(b.z - a.z)
			var constant := a.z if along_x else a.x
			var run_key := [0 if along_x else 1, roundi(constant * 100.0)]
			if not runs.has(run_key):
				runs[run_key] = []
			var lo := minf(a.x, b.x) if along_x else minf(a.z, b.z)
			var hi := maxf(a.x, b.x) if along_x else maxf(a.z, b.z)
			runs[run_key].append(Vector2(lo, hi))
	_blocker_lines_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for run_key: Array in runs:
		var spans: Array = runs[run_key]
		spans.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
		var current: Vector2 = spans[0]
		for i in range(1, spans.size() + 1):
			if i < spans.size() and (spans[i] as Vector2).x <= current.y + 0.01:
				current.y = maxf(current.y, (spans[i] as Vector2).y)
				continue
			var constant_value := float(run_key[1]) / 100.0
			var p0 := Vector3(current.x, height, constant_value) if run_key[0] == 0 else Vector3(constant_value, height, current.x)
			var p1 := Vector3(current.y, height, constant_value) if run_key[0] == 0 else Vector3(constant_value, height, current.y)
			_add_charcoal_stroke(p0, p1, 3, CHARCOAL_WIDTH * 1.8, 1.0, 0.04, BLOCKER_DUST_COLOR)  # faint dust underneath
			_add_charcoal_stroke(p0, p1, 1, CHARCOAL_WIDTH, 1.0, 0.0, BLOCKER_LINE_COLOR)
			_add_charcoal_stroke(p0, p1, 2, CHARCOAL_WIDTH * 0.45, 0.6, 0.05, BLOCKER_LINE_COLOR)  # thinner grainy pass, slightly off the first
			if i < spans.size():
				current = spans[i]
	_blocker_lines_mesh.surface_end()
	_blocker_lines.global_transform = Transform3D.IDENTITY
	_blocker_lines.visible = true


## One hand-drawn charcoal stroke from `a` to `b` (world points): a ribbon lying on the floor whose path wanders a little, whose thickness and
## opacity vary along its length, and which tapers into the corners. All randomness comes from a hash of the edge's position, so the same wall
## always looks the same (it does not shimmer when the outline is rebuilt). `seed` differs per pass, `offset` shifts the pass sideways.
func _add_charcoal_stroke(a: Vector3, b: Vector3, seed: int, width: float, alpha: float, offset: float, color: Color) -> void:
	var length := a.distance_to(b)
	if length < 0.001:
		return
	var dir := (b - a) / length
	var perp := Vector3(-dir.z, 0.0, dir.x)
	# stretch past the corners a little so two strokes meeting at a corner overlap instead of leaving a notch
	var start := a - dir * width * 0.4
	var span := length + width * 0.8
	var steps := maxi(2, ceili(span / CHARCOAL_STEP))
	var key := Vector3i(roundi(a.x * 20.0), roundi(a.z * 20.0), seed + roundi(b.x * 20.0) * 31 + roundi(b.z * 20.0) * 17)
	var lift := Vector3(0.0, 0.004 * (seed if seed < 3 else 0), 0.0)  # the dust pass lies lowest
	var left_prev := Vector3.ZERO
	var right_prev := Vector3.ZERO
	var alpha_prev := 0.0
	for i in steps + 1:
		var t := float(i) / steps
		var along := span * t
		var taper := pow(sin(PI * t), 0.25)  # 0 at both ends so the stroke starts and stops softly
		var wander := (_charcoal_noise(key, along / CHARCOAL_LATTICE, 0) * 2.0 - 1.0) * CHARCOAL_WOBBLE * taper
		var thick := width * (0.8 + 0.45 * _charcoal_noise(key, along / (CHARCOAL_LATTICE * 1.6), 1)) * (0.7 + 0.3 * taper)
		var fade := alpha * (0.8 + 0.2 * _charcoal_noise(key, along / (CHARCOAL_LATTICE * 0.5), 2))
		var centre := start + dir * along + perp * (wander + offset * (_charcoal_noise(key, along / CHARCOAL_LATTICE, 3) * 2.0 - 1.0)) + lift
		var left := centre + perp * thick * 0.5
		var right := centre - perp * thick * 0.5
		if i > 0:
			var c0 := color
			c0.a *= alpha_prev
			var c1 := color
			c1.a *= fade
			for corner in [[left_prev, c0], [right_prev, c0], [left, c1], [right_prev, c0], [right, c1], [left, c1]]:
				_blocker_lines_mesh.surface_set_color(corner[1])
				_blocker_lines_mesh.surface_add_vertex(corner[0])
		left_prev = left
		right_prev = right
		alpha_prev = fade


## Smooth random value 0..1 at `x` along a line (value noise: hashed values at whole numbers, eased in between). `key` identifies the line,
## `channel` the quantity (wander, thickness, opacity ...).
func _charcoal_noise(key: Vector3i, x: float, channel: int) -> float:
	var k := floori(x)
	var f := x - k
	f = f * f * (3.0 - 2.0 * f)
	var v0 := float(hash(Vector4i(key.x, key.y, key.z, k * 8 + channel)) & 0xFFFF) / 65535.0
	var v1 := float(hash(Vector4i(key.x, key.y, key.z, (k + 1) * 8 + channel)) & 0xFFFF) / 65535.0
	return lerpf(v0, v1, f)


func _setup_spawn_overlay() -> void:
	_spawn_overlay_mesh = ImmediateMesh.new()
	_spawn_overlay = _make_overlay_node(_spawn_overlay_mesh)


func _setup_monster_overlay() -> void:
	_monster_overlay_mesh = ImmediateMesh.new()
	_monster_overlay = _make_overlay_node(_monster_overlay_mesh)


func _make_overlay_node(overlay_mesh: ImmediateMesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = overlay_mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_ambient_light = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material
	node.visible = false
	add_child(node)
	return node


## Colour for the spawn at `index` in mission.monster_spawns.
static func monster_spawn_color(index: int) -> Color:
	return MONSTER_SPAWN_PALETTE[index % MONSTER_SPAWN_PALETTE.size()]


## Colour the Creator's hover ghost should use for `spawn_id` (the default
## red when it isn't found).
func monster_spawn_color_for_id(spawn_id: String) -> Color:
	for i in mission.monster_spawns.size():
		if mission.monster_spawns[i].id == spawn_id:
			var c := monster_spawn_color(i)
			c.a = MONSTER_SPAWN_COLOR.a
			return c
	return MONSTER_SPAWN_COLOR


## Rebuilds the monster spawn overlay from mission.monster_spawns: every
## tile of every spawn as a quad in that spawn's colour (active spawn more
## opaque) plus a Label3D with its tile number (position in the spawn's
## `cells`). Empty mission list clears it. Creator only - apply_mission()
## skips this when respect_visibility is on (the Player must not reveal
## spawn tiles).
func refresh_monster_spawn_overlay() -> void:
	_monster_overlay_mesh.clear_surfaces()
	if _monster_labels == null:
		_monster_labels = Node3D.new()
		add_child(_monster_labels)
	for child in _monster_labels.get_children():
		child.free()

	var any := false
	for spawn in mission.monster_spawns:
		if not spawn.cells.is_empty() and not is_editor_hidden(spawn):
			any = true
			break
	if not any:
		_monster_overlay.visible = false
		return

	_monster_overlay_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in mission.monster_spawns.size():
		var spawn: MonsterSpawn = mission.monster_spawns[i]
		if is_editor_hidden(spawn):
			continue
		var color := monster_spawn_color(i)
		color.a = 0.6 if spawn.id == monster_overlay_active_id else 0.3
		for n in spawn.cells.size():
			var corners := get_tile_square_world_corners(spawn.cells[n])
			for v in [corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]]:
				_monster_overlay_mesh.surface_set_color(color)
				_monster_overlay_mesh.surface_add_vertex(v)
			var label := Label3D.new()
			label.text = str(n + 1)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.pixel_size = 0.02
			label.modulate = Color.WHITE
			label.outline_modulate = Color.BLACK
			_monster_labels.add_child(label)
			label.global_position = (corners[0] + corners[2]) * 0.5 + Vector3(0, 0.3, 0)
	_monster_overlay_mesh.surface_end()
	_monster_overlay.global_transform = Transform3D.IDENTITY
	_monster_overlay.visible = true


## Yellow semi-transparent overlay marking a set of TILE-SQUARE ("game
## unit") cells (mission's player_spawn_cells) - same "start area"
## highlight the original game's own app shows. Cells here are tile-square
## coordinates, not fine GridMap cells - see
## FootprintRegistry.fine_cell_to_tile_square() and _add_spawn_quad() below.
## Shared here (not duplicated in CreatorController/MissionPlayer) since
## both the Creator and Player instance this same scene and both need to
## show it - Creator while drawing it, Player before round 1. Rebuilt from
## scratch each call; pass an empty array to clear it.
func set_spawn_overlay_cells(cells: Array[Vector3i]) -> void:
	_spawn_overlay_mesh.clear_surfaces()
	if cells.is_empty():
		_spawn_overlay.visible = false
		return

	_spawn_overlay_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in cells:
		_add_spawn_quad(cell)
	_spawn_overlay_mesh.surface_end()
	_spawn_overlay.global_transform = Transform3D.IDENTITY  # vertices already computed in world space
	_spawn_overlay.visible = true


func set_spawn_overlay_visible(value: bool) -> void:
	_spawn_overlay.visible = value and _spawn_overlay_mesh.get_surface_count() > 0


func _add_spawn_quad(cell: Vector3i) -> void:
	var corners := get_tile_square_world_corners(cell)
	var color := Color(1.0, 0.9, 0.2, 0.45)
	for v in [corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]]:
		_spawn_overlay_mesh.surface_set_color(color)
		_spawn_overlay_mesh.surface_add_vertex(v)


## `cell` is a TILE-SQUARE ("game unit") coordinate, not a fine GridMap
## cell - see FootprintRegistry.fine_cell_to_tile_square(). Expands it to
## its near fine-cell corner using the same far-corner math
## expand_footprint() uses (base = ts*CELLS_PER_TILE - CELLS_PER_TILE) - bare,
## no manual correction (an earlier attempt at one made things worse, not
## better, and turned out to be chasing a UX problem - hard to tell where a
## click will land with no preview - not an actual math bug; see
## CreatorController's spawn-paint hover ghost, which reuses this exact
## method so preview and placement can never disagree). Returns the four
## WORLD-SPACE corners (in quad winding order) spanning the FULL tile-square
## (CELLS_PER_TILE fine cells per side), lifted just above the floor surface
## (floor_thickness + a small epsilon) so it reads as a decal on top of the
## floor rather than z-fighting with it. Same corner-based box-building
## approach as CreatorController's occupancy overlay (GridMap's Center X/Y/Z
## are OFF, so map_to_local() returns a cell's CORNER, not its center).
func get_tile_square_world_corners(cell: Vector3i) -> Array[Vector3]:
	var cpt := FootprintRegistry.CELLS_PER_TILE
	var near_fine_cell := Vector3i(cell.x * cpt - cpt, cell.y, cell.z * cpt - cpt)
	var corner_local: Vector3 = floor_grid.map_to_local(near_fine_cell)
	var size := Vector3(cpt * floor_grid.cell_size.x, 0, cpt * floor_grid.cell_size.z)
	var lift := Vector3(0, floor_thickness + 0.02, 0)
	return [
		floor_grid.to_global(corner_local + lift),
		floor_grid.to_global(corner_local + Vector3(size.x, 0, 0) + lift),
		floor_grid.to_global(corner_local + Vector3(size.x, 0, size.z) + lift),
		floor_grid.to_global(corner_local + Vector3(0, 0, size.z) + lift),
	]


## Call after painting/moving/erasing a cell in PropGridMap (in-editor or
## from an in-game Creator tool) to keep MissionData's occupancy index and
## interactables list in sync with what's actually painted. `new_parent_id`
## is CreatorController.working_group_id, threaded through so a genuinely
## NEW placement (no previous entry to carry identity over from, see below)
## lands directly in the designer's current working group instead of
## always defaulting to the mission root - ignored entirely on a repaint,
## which always carries the OLD entry's parent_id forward instead.
func sync_prop_cell(origin: Vector3i, new_parent_id: String = "") -> void:
	# Clear any existing entry at this origin first, using ITS stored
	# footprint - never guess from the new state. Keep a reference to it
	# (rather than just erasing) so its identity/authoring survives a
	# repaint of the same cell - see the field-carry-over note below.
	var existing := _find_interactable(origin)
	if existing != null:
		FootprintRegistry.clear_occupied(mission, origin, existing.footprint)
		mission.interactables.erase(existing)

	var item_id := prop_grid.get_cell_item(origin)
	if item_id == GridMap.INVALID_CELL_ITEM:
		mission_objects_changed.emit()
		return  # cell was erased, nothing further to register

	var mesh_name := prop_grid.mesh_library.get_item_name(item_id)
	var orientation := prop_grid.get_cell_item_orientation(origin)
	var basis := prop_grid.get_cell_item_basis(origin)
	var footprint := FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(mesh_name), basis)

	FootprintRegistry.mark_occupied(mission, origin, footprint)

	var entry := InteractableEntry.new()
	entry.mesh_item_name = mesh_name
	entry.origin_cell = origin
	entry.footprint = footprint
	entry.orientation = orientation
	# This function always erases-then-recreates rather than updating in
	# place, so a repaint of an already-placed cell (correcting its mesh
	# or orientation) would otherwise silently orphan its outline-tree
	# identity, group membership, and any authored reference_name/
	# visible/props/actions. Carry those over from the entry that was
	# just here; otherwise mint a fresh id for a genuinely new placement.
	if existing != null:
		entry.id = existing.id
		entry.parent_id = existing.parent_id
		entry.reference_name = existing.reference_name
		entry.visible = existing.visible
		entry.props = existing.props
		entry.actions = existing.actions
	else:
		entry.id = mission.allocate_object_id()
		entry.parent_id = new_parent_id
	mission.interactables.append(entry)
	mission_objects_changed.emit()


## The event/interaction tokens - same single tile square, so one can be swapped for another in place.
const TOKEN_MESHES: Array[String] = ["exploration", "interact", "umbra"]


## Changes which mesh a placed prop uses (a mistake made while placing tokens) while keeping EVERYTHING else:
## id, group, name, visibility, custom properties, actions, position and turn. The new mesh must have the same
## footprint size class as the old one (the tokens do). Returns false when nothing changed.
func swap_prop_mesh(id: String, new_mesh: String) -> bool:
	var entry := mission.find_node_by_id(id) as InteractableEntry
	if entry == null or entry.mesh_item_name == new_mesh:
		return false
	var item_id := find_item_id(prop_grid, new_mesh)
	if item_id == -1:
		return false
	FootprintRegistry.clear_occupied(mission, entry.origin_cell, entry.footprint)
	entry.mesh_item_name = new_mesh
	entry.footprint = FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(new_mesh), prop_grid.get_basis_with_orthogonal_index(entry.orientation))
	FootprintRegistry.mark_occupied(mission, entry.origin_cell, entry.footprint)
	# a piece in a stage hidden with the eye is not painted - only repaint what is on the map
	if prop_grid.get_cell_item(entry.origin_cell) != GridMap.INVALID_CELL_ITEM:
		prop_grid.set_cell_item(entry.origin_cell, item_id, entry.orientation)
	mission_objects_changed.emit()
	return true


## Erases a placed prop or floor/underlay tile from its GridMap and
## MissionData, by id - fired by an authored Effect.Type.REMOVE_OBJECT
## (e.g. "opening this door removes it from the board", matching the
## physical game's own rule that an opened door token comes off the board
## entirely, or a floor tile collapsing into a pit). No-op if the id
## doesn't resolve to anything currently placed (already removed, or
## never existed). Props resync incrementally via the existing
## sync_prop_cell() (same erase-then-resync sequence
## CreatorController.erase_at_cursor() already uses - erasing the GridMap
## cell FIRST is what makes sync_prop_cell() take its "cell already
## erased" branch instead of the carry-over repaint branch); floor/
## underlay tiles have no incremental single-cell sync (same as
## CreatorController._sync_after_edit()'s existing routing), so those go
## through a full rebuild instead.
func remove_node(id: String) -> void:
	var node := mission.find_node_by_id(id)
	if node == null:
		return
	if node is InteractableEntry:
		var entry := node as InteractableEntry
		prop_grid.set_cell_item(entry.origin_cell, GridMap.INVALID_CELL_ITEM)
		sync_prop_cell(entry.origin_cell)
	elif node is TilePlacement:
		var placement := node as TilePlacement
		var grid := floor_grid if placement.layer == TilePlacement.Layer.FLOOR else underlay_grid
		grid.set_cell_item(placement.origin_cell, GridMap.INVALID_CELL_ITEM)
		if placement.layer == TilePlacement.Layer.FLOOR:
			rebuild_floor_tiles()
		else:
			rebuild_underlay_tiles()


## Relocates an already-placed prop or floor/underlay tile to a new origin
## cell, PRESERVING its outline-tree identity (id/parent_id/reference_name/
## visible/props/actions) - CreatorController's Move mode (new 2026-09-18,
## M key) is the one caller. Mesh/orientation are kept exactly as they
## were; only origin_cell changes. Returns false (no-op, nothing touched)
## if `id` doesn't resolve to anything currently placed, new_origin is the
## same as the current origin, or new_origin's GridMap cell is already
## occupied by something else (deliberately conservative - place_at_cursor()
## itself never checks footprint-level collision beyond this either, see
## FootprintRegistry's own doc, so this matches that same looseness rather
## than inventing a stricter rule just for moves).
##
## Props (InteractableEntry) are handled directly rather than through
## sync_prop_cell() - that function only ever looks at ONE cell at a time
## and always erases-then-recreates whatever it finds there (see its own
## doc), which would mint a FRESH id at the new origin and silently orphan
## the original's identity, exactly the class of bug sync_prop_cell()'s own
## carry-over fix was built to prevent in the first place. Mutating the
## SAME InteractableEntry object's origin_cell in place sidesteps that
## entirely - there's nothing to orphan since nothing is erased/recreated.
##
## Floor/underlay (TilePlacement) take a different, simpler route: mutate
## the placement's own origin_cell to the NEW cell BEFORE calling the
## normal full-rebuild sync (rebuild_floor_tiles()/rebuild_underlay_tiles()).
## Their own old_by_cell carry-over lookup is built by reading each
## placement's CURRENT origin_cell right before the rebuild clears and
## rescans everything - pointing that field at the new cell first means the
## existing carry-over logic picks this exact placement back up under its
## new key with zero duplicated logic, the same object, same id.
func move_node(id: String, new_origin: Vector3i) -> bool:
	var node := mission.find_node_by_id(id)
	if node == null:
		return false

	if node is InteractableEntry:
		var entry := node as InteractableEntry
		var old_origin := entry.origin_cell
		if old_origin == new_origin:
			return false
		if prop_grid.get_cell_item(new_origin) != GridMap.INVALID_CELL_ITEM:
			return false
		var item_id := find_item_id(prop_grid, entry.mesh_item_name)
		if item_id == -1:
			return false
		FootprintRegistry.clear_occupied(mission, old_origin, entry.footprint)
		prop_grid.set_cell_item(old_origin, GridMap.INVALID_CELL_ITEM)
		prop_grid.set_cell_item(new_origin, item_id, entry.orientation)
		entry.origin_cell = new_origin
		FootprintRegistry.mark_occupied(mission, new_origin, entry.footprint)
		mission_objects_changed.emit()
		return true

	if node is TilePlacement:
		var placement := node as TilePlacement
		var old_origin := placement.origin_cell
		if old_origin == new_origin:
			return false
		var grid := floor_grid if placement.layer == TilePlacement.Layer.FLOOR else underlay_grid
		if grid.get_cell_item(new_origin) != GridMap.INVALID_CELL_ITEM:
			return false
		var item_id := find_item_id(grid, placement.mesh_item_name)
		if item_id == -1:
			return false
		grid.set_cell_item(old_origin, GridMap.INVALID_CELL_ITEM)
		grid.set_cell_item(new_origin, item_id, placement.orientation)
		placement.origin_cell = new_origin  # see this function's own doc - lets the rebuild's own carry-over logic re-adopt this exact object
		if placement.layer == TilePlacement.Layer.FLOOR:
			rebuild_floor_tiles()
		else:
			rebuild_underlay_tiles()
		return true

	return false


## For callers that mutate mission.groups/mission.interactables' parent_id
## directly (CreatorOutline.gd's group New/Rename/Delete/Move to... - none
## of that touches the GridMap the way sync_prop_cell() does, so there's
## nothing to repaint, just the "something changed, rebuild the tree"
## notification CreatorOutline.gd is listening for).
func notify_objects_changed() -> void:
	mission_objects_changed.emit()


func _find_interactable(origin: Vector3i) -> InteractableEntry:
	for entry in mission.interactables:
		if entry.origin_cell == origin:
			return entry
	return null


## Rebuilds TileEntry data for every cell covered by a painted floor
## piece, using naming-convention defaults. Floor tiles are irregular
## multi-cell shapes just like props - GridMap only tracks the origin cell
## each was painted at, so we expand each origin through its registered
## footprint to find every cell it actually covers. Run after a painting
## pass, or whenever you want to regenerate logical data from the visual
## layers.
func rebuild_floor_tiles(new_placement_parent_id: String = "") -> void:
	var old_by_cell: Dictionary = {}
	var hidden_old: Array[TilePlacement] = []
	for placement in mission.floor_placements:
		old_by_cell[placement.origin_cell] = placement
		if is_editor_hidden(placement):
			hidden_old.append(placement)

	mission.tiles.clear()
	mission.floor_placements.clear()
	mission.floor_occupied_cells.clear()

	for origin in floor_grid.get_used_cells():
		_write_tile_footprint(origin, old_by_cell, new_placement_parent_id)

	# Pieces of a stage hidden with the eye are not painted, so the scan above
	# cannot see them - keep them as they are.
	for placement in hidden_old:
		if floor_grid.get_cell_item(placement.origin_cell) != GridMap.INVALID_CELL_ITEM:
			continue  # something was painted on its spot meanwhile
		var basis := floor_grid.get_basis_with_orthogonal_index(placement.orientation)
		var footprint := FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(placement.mesh_item_name), basis)
		mission.floor_placements.append(placement)
		_register_floor_cells(placement.origin_cell, placement.mesh_item_name, footprint)

	mission_objects_changed.emit()


## `new_placement_parent_id` (CreatorController.working_group_id) only ever
## applies to the ONE origin cell that's genuinely new this call - see
## rebuild_floor_tiles()'s own doc for why that's safe under a full-rebuild
## design where every other origin already matches something in old_by_cell.
func _write_tile_footprint(origin: Vector3i, old_by_cell: Dictionary, new_placement_parent_id: String = "") -> void:
	var grid := floor_grid
	var item_id := grid.get_cell_item(origin)
	var mesh_name := grid.mesh_library.get_item_name(item_id)
	var orientation := grid.get_cell_item_orientation(origin)
	var basis := grid.get_cell_item_basis(origin)
	var footprint := FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(mesh_name), basis)

	var placement := TilePlacement.new()
	placement.layer = TilePlacement.Layer.FLOOR
	placement.origin_cell = origin
	placement.mesh_item_name = mesh_name
	placement.orientation = orientation

	# This function rebuilds EVERY placement from scratch on every single
	# edit anywhere on the floor layer (see the class doc's "full rebuild"
	# note) - without this, a repainted tile would silently lose its
	# outline-tree id/parent_id/reference_name/visible every time ANY
	# floor cell gets painted, not just itself. Carry the old entry's
	# identity forward when this origin cell already had something; only
	# mint a fresh id for a genuinely new placement. Mirrors
	# sync_prop_cell()'s own field-carry-over fix.
	var old: TilePlacement = old_by_cell.get(origin)
	if old != null:
		placement.id = old.id
		placement.parent_id = old.parent_id
		placement.reference_name = old.reference_name
		placement.visible = old.visible
	else:
		placement.id = mission.allocate_object_id()
		placement.parent_id = new_placement_parent_id

	mission.floor_placements.append(placement)
	_register_floor_cells(origin, mesh_name, footprint)


## Occupancy + per-cell logical data for one floor placement.
func _register_floor_cells(origin: Vector3i, mesh_name: String, footprint: Array[Vector3i]) -> void:
	var defaults := FootprintRegistry.get_logical_defaults(mesh_name)
	for offset in footprint:
		var cell: Vector3i = origin + offset
		mission.floor_occupied_cells[cell] = origin
		var entry: TileEntry = mission.tiles.get(cell)
		if entry == null:
			entry = TileEntry.new()
		entry.mesh_item_name = mesh_name
		entry.walkable = defaults.walkable
		entry.blocks_los = defaults.blocks_los
		mission.tiles[cell] = entry


## Underlay equivalent of rebuild_floor_tiles() - kept as a SEPARATE pass
## rather than folded into it, because underlay tiles physically coexist
## with whatever floor tile sits on the same cells (they're meant to peek
## through, not replace it). Writing them into mission.tiles the same way
## floor does would have one silently clobber the other's walkable/
## blocks_los data depending on iteration order. Underlay currently carries
## no logical (walkable/blocks_los) data of its own - it's visual/hazard
## marker data only, tracked purely via underlay_placements/
## underlay_occupied_cells.
func rebuild_underlay_tiles(new_placement_parent_id: String = "") -> void:
	var old_by_cell: Dictionary = {}
	var hidden_old: Array[TilePlacement] = []
	for placement in mission.underlay_placements:
		old_by_cell[placement.origin_cell] = placement
		if is_editor_hidden(placement):
			hidden_old.append(placement)

	mission.underlay_placements.clear()
	mission.underlay_occupied_cells.clear()

	# Hidden stages are not painted - keep their pieces (see rebuild_floor_tiles()).
	for placement in hidden_old:
		if underlay_grid.get_cell_item(placement.origin_cell) != GridMap.INVALID_CELL_ITEM:
			continue
		var hidden_basis := underlay_grid.get_basis_with_orthogonal_index(placement.orientation)
		var hidden_footprint := FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(placement.mesh_item_name), hidden_basis)
		mission.underlay_placements.append(placement)
		for offset in hidden_footprint:
			mission.underlay_occupied_cells[placement.origin_cell + offset] = placement.origin_cell

	for origin in underlay_grid.get_used_cells():
		var item_id := underlay_grid.get_cell_item(origin)
		var mesh_name := underlay_grid.mesh_library.get_item_name(item_id)
		var orientation := underlay_grid.get_cell_item_orientation(origin)
		var basis := underlay_grid.get_cell_item_basis(origin)
		var footprint := FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(mesh_name), basis)

		var placement := TilePlacement.new()
		placement.layer = TilePlacement.Layer.UNDERLAY
		placement.origin_cell = origin
		placement.mesh_item_name = mesh_name
		placement.orientation = orientation

		# Same identity-carry-over reasoning as rebuild_floor_tiles() -
		# this rebuilds every placement from scratch on every edit
		# anywhere in the underlay layer.
		var old: TilePlacement = old_by_cell.get(origin)
		if old != null:
			placement.id = old.id
			placement.parent_id = old.parent_id
			placement.reference_name = old.reference_name
			placement.visible = old.visible
		else:
			placement.id = mission.allocate_object_id()
			placement.parent_id = new_placement_parent_id

		mission.underlay_placements.append(placement)

		for offset in footprint:
			var cell: Vector3i = origin + offset
			mission.underlay_occupied_cells[cell] = origin

	mission_objects_changed.emit()


## Whether the current mission's GridMaps were painted respecting
## MissionData.is_effectively_visible() - set by apply_mission() below,
## consulted by _paint_all()/repaint_visible_entries(). Player-only in
## practice (see apply_mission()'s own doc); stays false for the Creator's
## own calls, which must always show everything regardless of a group's
## `visible` flag so a designer can edit a hidden room.
var _respect_visibility: bool = false
## Groups (stages) the designer has hidden in the Creator with the eye in the
## outline tree: group id -> true. VIEW state only - never saved with the
## mission and never touches `MissionGroup.visible` (that one decides whether a
## stage is revealed in the Player). A hidden stage's pieces stay in
## MissionData but are simply not painted; the rebuild_* passes below keep
## them. Cleared when a mission is loaded/started (CreatorSaveLoad).
var editor_hidden_groups: Dictionary = {}
## Ids of the pieces left unpainted by the last paint because of the eye.
var _painted_hidden: Dictionary = {}
signal editor_hidden_changed


## True when `node` sits in (or below) a stage hidden with the eye.
func is_editor_hidden(node: OutlineNode) -> bool:
	if editor_hidden_groups.is_empty() or node == null or mission == null:
		return false
	var parent_id := node.parent_id
	var guard := 0
	while parent_id != "" and guard < 64:
		if editor_hidden_groups.has(parent_id):
			return true
		var parent: MissionGroup = null
		for group in mission.groups:
			if group.id == parent_id:
				parent = group
				break
		if parent == null:
			break
		parent_id = parent.parent_id
		guard += 1
	return false


func is_group_editor_hidden(group_id: String) -> bool:
	return editor_hidden_groups.has(group_id)


## Hides/shows a whole stage in the Creator (pieces, spawn tiles, LOS blockers).
func set_group_editor_hidden(group_id: String, hidden: bool) -> void:
	if hidden == editor_hidden_groups.has(group_id):
		return
	if hidden:
		editor_hidden_groups[group_id] = true
	else:
		editor_hidden_groups.erase(group_id)
	_repaint_for_editor_hidden()
	editor_hidden_changed.emit()
	mission_objects_changed.emit()


## A different mission is being loaded/started: forget the view state that belongs to the old one
## (hidden stages here, collapsed rows in the outline tree).
signal editor_view_reset
func reset_editor_view() -> void:
	editor_hidden_groups.clear()
	editor_view_reset.emit()


func clear_editor_hidden() -> void:
	if editor_hidden_groups.is_empty():
		return
	editor_hidden_groups.clear()
	_repaint_for_editor_hidden()
	editor_hidden_changed.emit()


## Ids of everything currently sitting in a hidden stage.
func _hidden_ids() -> Dictionary:
	var ids: Dictionary = {}
	if editor_hidden_groups.is_empty() or mission == null:
		return ids
	for list: Array in [mission.floor_placements, mission.underlay_placements, mission.interactables, mission.monster_spawns, mission.los_blockers]:
		for node: OutlineNode in list:
			if is_editor_hidden(node):
				ids[node.id] = true
	return ids


## Something moved into or out of a hidden stage (Move to..., the batch panel, a
## piece drawn while a hidden group is the working group, undo): paint again so
## what is on screen matches. Only repaints when the set of hidden pieces changed.
func _sync_editor_hidden() -> void:
	if mission == null or (editor_hidden_groups.is_empty() and _painted_hidden.is_empty()):
		return
	var now := _hidden_ids()
	if now.size() != _painted_hidden.size() or now.hash() != _painted_hidden.hash():
		_repaint_for_editor_hidden()


func _repaint_for_editor_hidden() -> void:
	if mission == null:
		return
	floor_grid.clear()
	underlay_grid.clear()
	prop_grid.clear()
	_paint_all()
	_painted_hidden = _hidden_ids()
	if _monster_overlay != null:
		refresh_monster_spawn_overlay()
	if _blocker_overlay != null:
		refresh_blocker_overlay()


## Placement/prop nodes temporarily NOT painted even though visible (keys are
## the nodes themselves) - used to reveal a stage piece by piece while the
## table is told how to set it up (MissionPlayer.show_stage()).
var held_back: Dictionary = {}


## Reverse of sync_prop_cell()/rebuild_floor_tiles()/rebuild_underlay_tiles():
## given a loaded MissionData, clears all three GridMaps and repaints them to
## match. Used by the Player to render a loaded mission, and reusable by the
## Creator later for "open an existing mission to keep editing."
##
## `respect_visibility` (new 2026-09-14, default false - every existing
## call site, Creator + DebugSync.gd, is unaffected) - true only for
## MissionPlayer's own call: skips painting anything that isn't currently
## MissionData.is_effectively_visible() (see that method - a group's
## `visible` cascades to its members). GridMap has no per-cell hide, so
## "invisible" here really means "never painted" - see
## repaint_visible_entries() below for how a group gets revealed later.
func apply_mission(mission_to_apply: MissionData, respect_visibility: bool = false) -> void:
	floor_grid.clear()
	prop_grid.clear()
	underlay_grid.clear()

	mission = mission_to_apply
	_respect_visibility = respect_visibility
	_paint_all()
	_painted_hidden = _hidden_ids()
	# Creator-only marker (the Player passes respect_visibility = true and
	# shouldn't reveal where monsters start) - also what makes undo/redo/
	# Load repaint it, since all three go through apply_mission().
	if _monster_overlay != null and not respect_visibility:
		refresh_monster_spawn_overlay()
	# Same for the yellow player-start area - it was only ever drawn once
	# at CreatorController._ready() and on toggle, so a Load/New/undo/redo
	# (all apply_mission()) left the previous mission's area (or none)
	# showing. The Player shows it itself, before round 1.
	if _spawn_overlay != null and not respect_visibility:
		set_spawn_overlay_cells(mission.player_spawn_cells)
	# Virtual LOS walls: the Creator draws them all as a fill; the Player shows a fine outline of the ones in force.
	if _blocker_overlay != null and not respect_visibility:
		refresh_blocker_overlay()
	elif respect_visibility:
		refresh_blocker_lines()

	# A whole new mission's worth of interactables/groups just got swapped
	# in (New/Load in the Creator) - CreatorOutline.gd needs to rebuild its
	# tree from scratch here too, same as after a single sync_prop_cell()
	# edit. Harmless no-op in the Player (nothing there listens).
	mission_objects_changed.emit()


## Paints every floor/underlay/prop placement - factored out of
## apply_mission() so repaint_visible_entries() below can re-run the exact
## same pass after a visibility change, without re-clearing the GridMaps
## first. Skips an entry when _respect_visibility and it currently isn't
## MissionData.is_effectively_visible() - everything else about this loop
## is unchanged from before this feature existed.
func _paint_all() -> void:
	for placement in mission.floor_placements:
		if is_editor_hidden(placement):
			continue
		if _respect_visibility and (held_back.has(placement) or not mission.is_effectively_visible(placement)):
			continue
		var item_id := find_item_id(floor_grid, placement.mesh_item_name)
		if item_id == -1:
			push_warning("No MeshLibrary item named '%s' - skipping floor placement at %s" % [placement.mesh_item_name, placement.origin_cell])
			continue
		floor_grid.set_cell_item(placement.origin_cell, item_id, placement.orientation)

	for placement in mission.underlay_placements:
		if is_editor_hidden(placement):
			continue
		if _respect_visibility and (held_back.has(placement) or not mission.is_effectively_visible(placement)):
			continue
		var item_id := find_item_id(underlay_grid, placement.mesh_item_name)
		if item_id == -1:
			push_warning("No MeshLibrary item named '%s' - skipping underlay placement at %s" % [placement.mesh_item_name, placement.origin_cell])
			continue
		underlay_grid.set_cell_item(placement.origin_cell, item_id, placement.orientation)

	for entry in mission.interactables:
		if is_editor_hidden(entry):
			continue
		if _respect_visibility and (held_back.has(entry) or not mission.is_effectively_visible(entry)):
			continue
		var item_id := find_item_id(prop_grid, entry.mesh_item_name)
		if item_id == -1:
			push_warning("No MeshLibrary item named '%s' - skipping prop at %s" % [entry.mesh_item_name, entry.origin_cell])
			continue
		prop_grid.set_cell_item(entry.origin_cell, item_id, entry.orientation)


## Call after mutating a MissionGroup/OutlineNode's `visible` field
## elsewhere (see MissionPlayer.show_stage()) so the GridMaps catch up -
## a no-op if apply_mission() wasn't called with respect_visibility in the
## first place (the Creator never needs this). Re-runs the WHOLE paint
## pass rather than diffing "what's newly visible" - re-painting an
## already-correctly-painted cell is harmless (set_cell_item() just sets
## the same item again), and a full rescan is simplest-first correct
## without needing per-entry bookkeeping of what was previously skipped.
func repaint_visible_entries() -> void:
	if not _respect_visibility:
		return
	# Cleared first so a piece that was held back AFTER being painted disappears again.
	floor_grid.clear()
	underlay_grid.clear()
	prop_grid.clear()
	_paint_all()
	refresh_blocker_lines()


## MeshLibrary only looks up items by numeric id, not name - this does the
## name -> id search once per call. Fine for occasional use (mission load,
## interactive painting); would be worth caching if this ever runs
## somewhere hot (e.g. every frame).
func find_item_id(grid: GridMap, mesh_name: String) -> int:
	if grid.mesh_library == null:
		return -1
	for id in grid.mesh_library.get_item_list():
		if grid.mesh_library.get_item_name(id) == mesh_name:
			return id
	return -1
