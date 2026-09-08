class_name CreatorController
extends Node3D

## In-game paint tool for the Mission Creator - the "mimic GridMap's own
## paint panel, but as an actual game feature" piece. Attach as a sibling of
## LayeredMap (or anywhere in the same scene) and wire up the exports.
##
## CONTROLS (temporary, keyboard-only until a real palette UI exists):
##   Left-click        - place the currently selected mesh at the hovered cell
##   Shift + Left-click - erase whatever's at the hovered cell
##   , / .              - cycle selected mesh backward/forward within the
##                        current layer FILTER (see below)
##   R                  - rotate the selection 90 degrees before placing
##   L                  - cycle which layer , / . browses: Floor -> Wall -> Prop -> Underlay
##   Page Up/Down       - move the painting level (Y) up/down
##
## NOTE: mesh cycling deliberately does NOT use Tab - Tab is Godot's
## built-in ui_focus_next action, and now that this scene has real Button
## nodes (Save/Load/New), Tab gets consumed by UI focus navigation before
## _unhandled_input ever sees it.
##
## IMPORTANT: L only changes which meshes Tab offers to browse - it does
## NOT determine where a placed item actually lands. All three GridMaps
## share one MeshLibrary, so nothing physically stops you selecting a prop
## mesh while L is still on "Floor". The actual destination grid is always
## derived from the SELECTED MESH ITSELF via FootprintRegistry.get_layer()
## (see _target_grid() below) - a pillar always lands in PropGridMap no
## matter what L is set to. If a mesh is showing up in the wrong physical
## layer, the fix is in FootprintRegistry.MESH_LAYER / get_layer(), not here.
##
## ARCHITECTURE NOTE: mesh selection goes through select_mesh() /
## cycle_mesh() / select_layer() - these are the only things that touch
## current_mesh_index/current_layer. A future palette UI should call these
## SAME methods (e.g. a button's "pressed" signal calling select_mesh("2a"))
## rather than reaching into this script's state directly, so keyboard
## cycling and UI buttons never disagree about what's selected.

@export var layered_map: LayeredMap
@export var camera: Camera3D  ## leave unset to auto-grab the viewport's active camera
@export var ghost_color: Color = Color(0.2, 1.0, 0.4, 0.45)
@export var grid_overlay_color: Color = Color(1.0, 1.0, 1.0, 0.15)
@export var grid_overlay_radius: int = 15  ## cells shown in each direction from the hovered cell
@export var origin_overlay_color: Color = Color(0.173, 0.529, 0.431, 0.627)
@export var floor_occupancy_color: Color = Color(0.2, 0.6, 1.0, 0.9)
@export var prop_occupancy_color: Color = Color(1.0, 0.4, 0.2, 0.9)
@export var underlay_occupancy_color: Color = Color(0.7, 0.2, 1.0, 0.9)



enum PaintLayer { FLOOR, WALL, PROP, UNDERLAY }

## Emitted whenever selection state actually changes, from whichever path
## caused it (keyboard cycling OR a future/present palette UI calling
## select_mesh()/select_layer() directly) - a UI palette should listen to
## these rather than polling, so it never drifts out of sync with keyboard
## input still working side by side.
signal layer_changed(layer: PaintLayer)
signal mesh_changed(mesh_name: String)

var current_layer: PaintLayer = PaintLayer.FLOOR
var current_level: int = 0
var current_mesh_index: int = 0
var current_quarter_turn: int = 0  # 0-3, see _quarter_turn_orientations

var _quarter_turn_orientations: Array[int] = []
var _ghost: MeshInstance3D
var _grid_overlay: MeshInstance3D
var _grid_overlay_mesh: ImmediateMesh
var _origin_overlay: MeshInstance3D
var _origin_overlay_mesh: ImmediateMesh
var _occupancy_overlay: MeshInstance3D
var _occupancy_overlay_mesh: ImmediateMesh
var show_occupancy_overlay: bool = false

var _hovered_cell: Vector3i = Vector3i.ZERO
var _has_hover: bool = false


func _ready() -> void:
	# Wait one frame so every node's own _ready() (including LayeredMap's
	# @onready floor_grid/wall_grid/prop_grid) has definitely run first,
	# regardless of sibling order in the scene tree - otherwise this only
	# works by accident depending on where CreatorController happens to
	# sit relative to LayeredMap.
	await get_tree().process_frame
	_compute_quarter_turn_orientations()
	_setup_ghost()
	_setup_grid_overlay()
	_setup_origin_overlay()
	_setup_occupancy_overlay()
	if camera == null:
		camera = get_viewport().get_camera_3d()


## Computes the real GridMap orientation index for each of the four flat
## Y-axis quarter turns at runtime (0/90/180/270). Basis itself doesn't
## expose an orthogonal-index lookup to GDScript - GridMap does, via
## get_orthogonal_index_from_basis(), so we borrow any GridMap instance
## purely for that calculation.
func _compute_quarter_turn_orientations() -> void:
	_quarter_turn_orientations.clear()
	var reference_grid := layered_map.floor_grid
	for i in 4:
		var basis := Basis(Vector3.UP, deg_to_rad(90.0 * i))
		_quarter_turn_orientations.append(reference_grid.get_orthogonal_index_from_basis(basis))


func _setup_ghost() -> void:
	_ghost = MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = ghost_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost.material_override = material
	_ghost.visible = false
	add_child(_ghost)


func _setup_grid_overlay() -> void:
	_grid_overlay_mesh = ImmediateMesh.new()
	_grid_overlay = MeshInstance3D.new()
	_grid_overlay.mesh = _grid_overlay_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = grid_overlay_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_ambient_light = true
	_grid_overlay.material_override = material
	_grid_overlay.visible = false
	add_child(_grid_overlay)
	
func _setup_origin_overlay() -> void:
	_origin_overlay_mesh = ImmediateMesh.new()
	_origin_overlay = MeshInstance3D.new()
	_origin_overlay.mesh = _origin_overlay_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = origin_overlay_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_ambient_light = true
	_origin_overlay.material_override = material
	_origin_overlay.visible = false
	add_child(_origin_overlay)


const PAINT_LAYER_NAMES: Array[String] = ["floor", "wall", "prop", "underlay"]


func _setup_occupancy_overlay() -> void:
	_occupancy_overlay_mesh = ImmediateMesh.new()
	_occupancy_overlay = MeshInstance3D.new()
	_occupancy_overlay.mesh = _occupancy_overlay_mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_ambient_light = true
	_occupancy_overlay.material_override = material
	_occupancy_overlay.visible = false
	add_child(_occupancy_overlay)


func _current_grid() -> GridMap:
	match current_layer:
		PaintLayer.FLOOR:
			return layered_map.floor_grid
		PaintLayer.WALL:
			return layered_map.wall_grid
		PaintLayer.PROP:
			return layered_map.prop_grid
		PaintLayer.UNDERLAY:
			return layered_map.underlay_grid
	return layered_map.floor_grid


## Resolves the ACTUAL destination grid for the currently selected mesh,
## via FootprintRegistry.get_layer() - this is what placement/erase/hover/
## ghost all use, so a prop always lands in PropGridMap regardless of
## current_layer. current_layer only affects which meshes cycle_mesh()
## offers (see get_available_mesh_names below); it never determines where
## something is actually painted.
func _target_grid() -> GridMap:
	var mesh_name := _current_mesh_name()
	if mesh_name == "":
		return _current_grid()  # nothing selected yet - fall back to the browse filter
	return _grid_for_mesh(mesh_name)


func _grid_for_mesh(mesh_name: String) -> GridMap:
	match FootprintRegistry.get_layer(mesh_name):
		"floor":
			return layered_map.floor_grid
		"wall":
			return layered_map.wall_grid
		"underlay":
			return layered_map.underlay_grid
		_:
			return layered_map.prop_grid


## Finds the first placed instance of mesh_name anywhere in the current
## mission and jumps the camera to it - the counterpart to select_mesh()
## for CreatorPalette's "show unavailable, click to locate" mode (an
## exhausted-inventory mesh can't be selected for painting, so locating
## where it's already used is the only useful click left). Returns false
## if nothing is placed yet (nothing to jump to).
func locate_mesh(mesh_name: String) -> bool:
	var found := false
	var origin_cell := Vector3i.ZERO

	match FootprintRegistry.get_layer(mesh_name):
		"prop":
			for entry in layered_map.mission.interactables:
				if entry.mesh_item_name == mesh_name:
					origin_cell = entry.origin_cell
					found = true
					break
		"underlay":
			for placement in layered_map.mission.underlay_placements:
				if placement.mesh_item_name == mesh_name:
					origin_cell = placement.origin_cell
					found = true
					break
		_:  # floor or wall - both live in floor_placements
			for placement in layered_map.mission.floor_placements:
				if placement.mesh_item_name == mesh_name:
					origin_cell = placement.origin_cell
					found = true
					break

	if not found:
		return false

	var grid := _grid_for_mesh(mesh_name)
	var world_pos: Vector3 = grid.to_global(grid.map_to_local(origin_cell))
	if camera is FreeLookCamera:
		(camera as FreeLookCamera).jump_to(world_pos)
	return true


## Every mesh item name belonging to the CURRENT layer filter. All three
## GridMaps share one MeshLibrary, so this reads from any one of them
## (floor_grid, arbitrarily) and filters by FootprintRegistry.get_layer()
## rather than by querying a different physical library - there isn't one.
## This is the data source a future palette UI should read from too, via
## this same method, so it can't drift out of sync with what's paintable.
func get_available_mesh_names() -> Array[String]:
	var library := layered_map.floor_grid.mesh_library
	var names: Array[String] = []
	if library == null:
		return names
	var wanted_layer := PAINT_LAYER_NAMES[current_layer]
	for id in library.get_item_list():
		var name := library.get_item_name(id)
		if FootprintRegistry.get_layer(name) == wanted_layer:
			names.append(name)
	names.sort_custom(_mesh_name_less_than)
	return names


## Natural sort so tile faces read 1a, 1b, 2a, ..., 9b, 10a, 10b, ... -
## plain alphabetical sort would put "10a" before "2a" since it compares
## character-by-character ("1" < "2"). Splits off the leading digit run
## as a NUMBER for the primary comparison, falling back to plain string
## comparison for the remainder (handles non-numbered names like "gate"/
## "water" too - they just sort alphabetically among themselves, which is
## all that matters since numbered tile faces and plain-named props/
## underlays never appear in the same layer's list together anyway).
func _mesh_name_less_than(a: String, b: String) -> bool:
	var key_a := _natural_sort_key(a)
	var key_b := _natural_sort_key(b)
	if key_a[0] != key_b[0]:
		return key_a[0] < key_b[0]
	return key_a[1] < key_b[1]


func _natural_sort_key(mesh_name: String) -> Array:
	var i := 0
	while i < mesh_name.length() and mesh_name[i].is_valid_int():
		i += 1
	var digit_part := mesh_name.substr(0, i)
	var number: int = int(digit_part) if digit_part != "" else -1
	return [number, mesh_name.substr(i)]


func select_mesh(mesh_name: String) -> void:
	var index := get_available_mesh_names().find(mesh_name)
	if index != -1:
		current_mesh_index = index
		_update_ghost_mesh()
		mesh_changed.emit(mesh_name)


func cycle_mesh(direction: int) -> void:
	var names := get_available_mesh_names()
	if names.is_empty():
		return
	current_mesh_index = wrapi(current_mesh_index + direction, 0, names.size())
	_update_ghost_mesh()
	mesh_changed.emit(names[current_mesh_index])


func select_layer(layer: PaintLayer) -> void:
	current_layer = layer
	current_mesh_index = 0
	_update_ghost_mesh()
	layer_changed.emit(layer)
	mesh_changed.emit(_current_mesh_name())


func cycle_layer() -> void:
	select_layer((current_layer + 1) % 4 as PaintLayer)


func change_level(delta: int) -> void:
	current_level += delta
	print("Painting level: %d" % current_level)


func rotate_selection() -> void:
	current_quarter_turn = (current_quarter_turn + 1) % 4


func _current_mesh_name() -> String:
	var names := get_available_mesh_names()
	if names.is_empty() or current_mesh_index >= names.size():
		return ""
	return names[current_mesh_index]


func _current_orientation() -> int:
	return _quarter_turn_orientations[current_quarter_turn]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_COMMA:
				cycle_mesh(-1)
			KEY_PERIOD:
				cycle_mesh(1)
			KEY_R:
				rotate_selection()
			KEY_L:
				cycle_layer()
			KEY_PAGEUP:
				change_level(1)
			KEY_PAGEDOWN:
				change_level(-1)
			KEY_O:
				print("show stuff")
				show_occupancy_overlay = not show_occupancy_overlay
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.is_key_pressed(KEY_SHIFT):
			erase_at_cursor()
		else:
			place_at_cursor()


func _process(_delta: float) -> void:
	_update_hover()
	_update_ghost_transform()
	_update_grid_overlay()
	_update_origin_overlay()
	_update_occupancy_overlay()


func _update_hover() -> void:
	_has_hover = false
	if camera == null:
		return

	var grid := _target_grid()
	if grid.mesh_library == null:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)

	# Intersect against a horizontal plane at the TARGET grid's CURRENT
	# level, computed in that grid's own local space then converted to
	# world space - keeps this correct even though FloorGridMap/WallGridMap/
	# PropGridMap sit at slightly different world Y offsets.
	var grid_local_y: float = current_level * grid.cell_size.y
	var world_point: Vector3 = grid.to_global(Vector3(0, grid_local_y, 0))
	var plane := Plane(Vector3.UP, world_point.y)

	var hit = plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return

	var local_point: Vector3 = grid.to_local(hit)
	_hovered_cell = grid.local_to_map(local_point)
	# The plane intersection is deliberately built at exactly current_level,
	# but local_to_map()'s reverse-mapping is floating-point sensitive right
	# at a level boundary and can round down to the level below by
	# accident. We already KNOW which level this is - don't let a rounding
	# guess override it.
	_hovered_cell.y = current_level
	_has_hover = true


func _update_ghost_mesh() -> void:
	var grid := _target_grid()
	var mesh_name := _current_mesh_name()
	if mesh_name == "" or grid.mesh_library == null:
		_ghost.mesh = null
		_ghost.visible = false
		return
	var item_id: int = layered_map.find_item_id(grid, mesh_name)
	_ghost.mesh = grid.mesh_library.get_item_mesh(item_id) if item_id != -1 else null


func _update_ghost_transform() -> void:
	if not _has_hover or _ghost.mesh == null:
		_ghost.visible = false
		return
	var grid := _target_grid()
	var local_pos: Vector3 = grid.map_to_local(_hovered_cell)
	var rot_basis := Basis(Vector3.UP, deg_to_rad(90.0 * current_quarter_turn))
	_ghost.global_transform = grid.global_transform * Transform3D(rot_basis, local_pos)
	_ghost.visible = true

## Draws a small axis cross at world origin, scaled to the target grid's
## actual cell size so it stays proportional to whatever scale the project
## is using rather than a fixed, possibly tiny-or-huge 1-unit length.
func _update_origin_overlay() -> void:
	if not _has_hover:
		_origin_overlay.visible = false
		return

	var cell_size := _target_grid().cell_size

	_origin_overlay_mesh.clear_surfaces()
	_origin_overlay_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_origin_overlay_mesh.surface_add_vertex(Vector3.ZERO)
	_origin_overlay_mesh.surface_add_vertex(Vector3(cell_size.x, 0, 0))
	_origin_overlay_mesh.surface_add_vertex(Vector3.ZERO)
	_origin_overlay_mesh.surface_add_vertex(Vector3(0, cell_size.y, 0))
	_origin_overlay_mesh.surface_add_vertex(Vector3.ZERO)
	_origin_overlay_mesh.surface_add_vertex(Vector3(0, 0, cell_size.z))
	_origin_overlay_mesh.surface_end()
	_origin_overlay.global_transform = Transform3D.IDENTITY
	_origin_overlay.visible = true


## Draws a line grid on the TARGET grid's plane (same one placement/hover
## uses), centered on the hovered cell, so it's always showing the level
## you're actually about to paint on rather than a fixed reference plane.
## Rebuilt every frame via ImmediateMesh - cheap at this line count, but if
## grid_overlay_radius gets large this is the place to add throttling
## (e.g. only rebuild when _hovered_cell or current_level actually changed).
func _update_grid_overlay() -> void:
	if not _has_hover:
		_grid_overlay.visible = false
		return

	var grid := _target_grid()
	var r := grid_overlay_radius

	_grid_overlay_mesh.clear_surfaces()
	_grid_overlay_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	for i in range(-r, r + 1):
		var x := _hovered_cell.x + i
		var p1: Vector3 = grid.map_to_local(Vector3i(x, current_level, _hovered_cell.z - r))
		var p2: Vector3 = grid.map_to_local(Vector3i(x, current_level, _hovered_cell.z + r))
		_grid_overlay_mesh.surface_add_vertex(p1)
		_grid_overlay_mesh.surface_add_vertex(p2)

	for j in range(-r, r + 1):
		var z := _hovered_cell.z + j
		var p1: Vector3 = grid.map_to_local(Vector3i(_hovered_cell.x - r, current_level, z))
		var p2: Vector3 = grid.map_to_local(Vector3i(_hovered_cell.x + r, current_level, z))
		_grid_overlay_mesh.surface_add_vertex(p1)
		_grid_overlay_mesh.surface_add_vertex(p2)

	_grid_overlay_mesh.surface_end()
	_grid_overlay.global_transform = grid.global_transform
	_grid_overlay.visible = true


## Draws wireframe outlines of every cell MissionData currently thinks is
## occupied - floor_occupied_cells (floor_occupancy_color) and
## occupied_cells/props (prop_occupancy_color) - so you can visually
## compare against where a mesh actually renders. Toggle with O.
##
## Built assuming GridMap's Center X/Y/Z are OFF, so map_to_local() returns
## a cell's CORNER, not its center - each box extends forward by a full
## cell_size from that corner. If centering is ever re-enabled on an axis,
## that axis's offset needs to be added back in here.
func _update_occupancy_overlay() -> void:
	if not show_occupancy_overlay:
		_occupancy_overlay.visible = false
		return

	_occupancy_overlay_mesh.clear_surfaces()
	_occupancy_overlay_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	for cell in layered_map.mission.floor_occupied_cells:
		_add_cell_outline(layered_map.floor_grid, cell, floor_occupancy_color)

	for cell in layered_map.mission.occupied_cells:
		_add_cell_outline(layered_map.prop_grid, cell, prop_occupancy_color)

	for cell in layered_map.mission.underlay_occupied_cells:
		_add_cell_outline(layered_map.underlay_grid, cell, underlay_occupancy_color)

	_occupancy_overlay_mesh.surface_end()
	_occupancy_overlay.global_transform = Transform3D.IDENTITY  # vertices already computed in world space
	_occupancy_overlay.visible = true


func _add_cell_outline(grid: GridMap, cell: Vector3i, color: Color) -> void:
	var corner_local: Vector3 = grid.map_to_local(cell)
	var size := grid.cell_size

	# Bottom face of the cell's box: corner -> corner + size on X/Z.
	var local_corners := [
		corner_local,
		corner_local + Vector3(size.x, 0, 0),
		corner_local + Vector3(size.x, 0, size.z),
		corner_local + Vector3(0, 0, size.z),
	]

	var world_corners: Array[Vector3] = []
	for c in local_corners:
		world_corners.append(grid.to_global(c))

	for i in 4:
		var a: Vector3 = world_corners[i]
		var b: Vector3 = world_corners[(i + 1) % 4]
		_occupancy_overlay_mesh.surface_set_color(color)
		_occupancy_overlay_mesh.surface_add_vertex(a)
		_occupancy_overlay_mesh.surface_set_color(color)
		_occupancy_overlay_mesh.surface_add_vertex(b)


func place_at_cursor() -> void:
	if not _has_hover:
		return
	var grid := _target_grid()
	var mesh_name := _current_mesh_name()
	if mesh_name == "":
		return
	var item_id: int = layered_map.find_item_id(grid, mesh_name)
	if item_id == -1:
		push_warning("No MeshLibrary item named '%s' in this layer" % mesh_name)
		return
	if not _can_place(mesh_name, _hovered_cell):
		var group := ComponentInventory.get_group(mesh_name)
		var max_count := ComponentInventory.get_max_count(mesh_name)
		push_warning("Can't place '%s' - physical limit reached (%d available for '%s')" % [mesh_name, max_count, group])
		return
	grid.set_cell_item(_hovered_cell, item_id, _current_orientation())
	_sync_after_edit(grid, _hovered_cell)


## True if there's at least one more physical copy of mesh_name available
## to place, ignoring any specific target cell (untracked meshes always
## return true). Used by CreatorPalette to decide whether to show/grey a
## mesh - _can_place() below is the placement-time version, which also
## accounts for replacing an existing piece of the same group in place.
func is_mesh_available(mesh_name: String) -> bool:
	var max_count := ComponentInventory.get_max_count(mesh_name)
	if max_count < 0:
		return true  # untracked - no limit configured yet
	var group := ComponentInventory.get_group(mesh_name)
	var usage := layered_map.mission.get_component_usage()
	return usage.get(group, 0) < max_count


## True if placing mesh_name at target_cell would stay within its physical
## component count. Untracked meshes (no ComponentInventory entry) always
## pass. Replacing whatever's ALREADY at target_cell with another piece
## from the SAME physical group (e.g. flipping "1a" to "1b" in place)
## doesn't consume a second copy - that existing piece is excluded from
## the count before checking.
func _can_place(mesh_name: String, target_cell: Vector3i) -> bool:
	var max_count := ComponentInventory.get_max_count(mesh_name)
	if max_count < 0:
		return true  # untracked - no limit configured yet

	var group := ComponentInventory.get_group(mesh_name)
	var usage := layered_map.mission.get_component_usage()
	var current: int = usage.get(group, 0)

	var existing_name := _mesh_name_at(target_cell)
	if existing_name != "" and ComponentInventory.get_group(existing_name) == group:
		current -= 1

	return current + 1 <= max_count


func _mesh_name_at(cell: Vector3i) -> String:
	var grid := _target_grid()
	var item_id := grid.get_cell_item(cell)
	if item_id == GridMap.INVALID_CELL_ITEM or grid.mesh_library == null:
		return ""
	return grid.mesh_library.get_item_name(item_id)


func erase_at_cursor() -> void:
	if camera == null:
		push_warning("erase_at_cursor: camera is null")
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	var ray_end := ray_origin + ray_dir * 1000.0

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		print("erase_at_cursor: raycast hit nothing")
		return

	var hit_grid = result.collider
	print("erase_at_cursor: hit collider = %s (type: %s)" % [hit_grid, hit_grid.get_class() if hit_grid != null else "null"])
	if not (hit_grid is GridMap):
		print("erase_at_cursor: hit something that isn't a GridMap - nothing to erase")
		return

	# result.position sits exactly ON the surface, right on a cell boundary
	# - mapping that directly to a cell can round into the wrong neighbor.
	# Step a hair inward along the inverse surface normal (in world space,
	# before converting to the grid's local space) to land solidly inside
	# the cell that was actually clicked.
	var interior_point: Vector3 = result.position - result.normal * 0.01
	var local_pos: Vector3 = hit_grid.to_local(interior_point)
	var hit_cell: Vector3i = hit_grid.local_to_map(local_pos)

	# Diagnostic: compare the RAW raycast hit position against where
	# GridMap itself thinks hit_cell's world position is. If these are far
	# apart, the mismatch is in the collision shape/mesh's real-world
	# position, not in our occupancy bookkeeping.
	var gridmap_thinks_cell_is_at: Vector3 = hit_grid.to_global(hit_grid.map_to_local(hit_cell))
	print("erase_at_cursor: raw hit world pos = %s | GridMap's world pos for %s = %s" % [result.position, hit_cell, gridmap_thinks_cell_is_at])

	# GridMap only stores an item at a multi-cell placement's ORIGIN cell -
	# every other cell it visually covers is empty as far as GridMap is
	# concerned. The raycast can land on any of those covered cells, so
	# translate back to the real origin before touching GridMap, using the
	# same occupancy maps sync_prop_cell()/rebuild_floor_tiles() maintain.
	var origin: Vector3i
	if hit_grid == layered_map.prop_grid:
		origin = _find_origin(layered_map.mission.occupied_cells, hit_cell)
	elif hit_grid == layered_map.underlay_grid:
		origin = _find_origin(layered_map.mission.underlay_occupied_cells, hit_cell)
	else:
		origin = _find_origin(layered_map.mission.floor_occupied_cells, hit_cell)

	print("erase_at_cursor: hit cell %s -> erasing origin %s on %s" % [hit_cell, origin, hit_grid.name])

	hit_grid.set_cell_item(origin, GridMap.INVALID_CELL_ITEM)
	_sync_after_edit(hit_grid, origin)


## Looks up hit_cell's origin in the given occupancy map. Falls back to
## matching by X/Z column alone (ignoring Y) if there's no exact match -
## needed because a mesh can render much taller than the single GridMap
## cell it's actually painted at (e.g. the "tall" pillar), so a raycast hit
## partway up it lands at a Y index that doesn't match the real placement.
func _find_origin(occupancy_map: Dictionary, hit_cell: Vector3i) -> Vector3i:
	if occupancy_map.has(hit_cell):
		return occupancy_map[hit_cell]
	for key in occupancy_map.keys():
		if key.x == hit_cell.x and key.z == hit_cell.z:
			return occupancy_map[key]
	print("Nothing found")
	return hit_cell


func _sync_after_edit(grid: GridMap, cell: Vector3i) -> void:
	if grid == layered_map.prop_grid:
		layered_map.sync_prop_cell(cell)
	elif grid == layered_map.underlay_grid:
		# Full rebuild is simplest/correct for now, same tradeoff as the
		# floor/wall branch below.
		layered_map.rebuild_underlay_tiles()
	else:
		# Full rebuild is simplest/correct for now. Once maps get large
		# enough for this to matter for responsiveness, this is the place
		# to swap in an incremental single-cell sync instead.
		layered_map.rebuild_floor_tiles()
