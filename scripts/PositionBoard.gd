class_name PositionBoard
extends Node3D

## POSITION TRACKING (a campaign option, see MissionRuntime.track_positions): the tokens that show where every hero and monster stands, and
## dragging them. A hero token is a disc in the hero's colour, a monster token a disc in its chip colour (2x2 squares for a large monster),
## each with a name. The table can drag any token to another square at any time (left button on the token, release on the new square);
## a square the figure cannot stand on (no floor, a solid piece, someone else, no room) shows red and the token goes back.
## Built by MissionPlayer only when the mission tracks positions; lives under layered_map so it hides with the world in the monster view.

## Assigned by MissionPlayer.
var layered_map: LayeredMap
var mission: MissionData
var runtime: MissionRuntime
## Returns true while dragging must not start (a modal dialog, the line-of-sight tool, the monster view).
var blocked_provider: Callable

const TOKEN_HEIGHT := 0.12
const TOKEN_FILL := 0.78  ## part of a square a 1-square token covers
const LABEL_LIFT := 0.9
const OK_COLOR := Color(0.3, 0.95, 0.4, 0.55)
const BAD_COLOR := Color(1.0, 0.3, 0.25, 0.55)
const TARGET_COLOR := Color(1.0, 0.8, 0.2, 0.6)

const PATH_COLOR := Color(1.0, 0.55, 0.1, 0.9)
const PATH_LIFT := 0.2
const DOT_RADIUS := 0.06    ## of a square
const DOT_SPACING := 0.28   ## of a square, between two dots
const ARROW_SPEED := 3.0    ## squares per second the arrow head travels along the line
const ARROW_SIZE := 0.6     ## of a square
const CURVE_STEPS := 10     ## pieces per step of the path
## An arrow head travels along the line and stays at the end (false = it sits at the end at once).
const ANIMATE_PATH := true

var _tokens: Node3D
var _ghost: MeshInstance3D
var _path: Node3D
var _dots: MultiMeshInstance3D
var _path_curve: Array[Vector3] = []
var _path_length := 0.0
var _arrow: MeshInstance3D
var _arrow_at := 0.0  ## how far along the curve the arrow head is
var _board: Dictionary = {}
## Stair squares -> the world height of the stair's surface over the middle of that square (read from the stair mesh), so a figure
## on a stair stands on the step and a click on a step picks that square.
var _stair_tops: Dictionary = {}
## The figure being dragged: {"kind": "hero" | "monster", "slot", "monster", "size"}; empty when none.
var _drag: Dictionary = {}
var _drag_square: Variant = null


func _ready() -> void:
	_tokens = Node3D.new()
	add_child(_tokens)
	_ghost = MeshInstance3D.new()
	_ghost.visible = false
	var ghost_material := StandardMaterial3D.new()
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.no_depth_test = true
	_ghost.material_override = ghost_material
	add_child(_ghost)
	_path = Node3D.new()
	add_child(_path)
	runtime.positions_changed.connect(refresh)
	runtime.monsters_changed.connect(refresh)
	refresh()


## Rebuilds every token from the runtime's positions.
func refresh() -> void:
	_update_board()
	for child in _tokens.get_children():
		_tokens.remove_child(child)
		child.free()
	for slot: int in runtime.hero_positions:
		_add_token(runtime.hero_positions[slot], 1, HeroCatalog.arrow_color(slot), HeroCatalog.slot_name(slot))
	for monster in runtime.monsters:
		if monster.placed:
			_add_token(monster.position, monster.size, MonsterChip.color(monster.chip), monster.display_name())


## Puts every hero of `roster` without a square on a free square of `cells` (1-based tile squares, the mission's start squares), in order.
## With `replace` all of them are put there again (a new Table).
func place_heroes_on(roster: Array[int], cells: Array[Vector3i], replace: bool = false) -> void:
	if replace:
		runtime.hero_positions.clear()
	_update_board()
	var free: Array[Vector3i] = []
	for cell in cells:
		free.append(Vector3i(cell.x - 1, cell.y, cell.z - 1))
	for slot in roster:
		if runtime.hero_positions.has(slot):
			continue
		var taken := runtime.occupied_squares()
		for square in free:
			if not taken.has(square) and MonsterMovement.can_place(_board, square, 1, taken):
				runtime.hero_positions[slot] = square
				break
	runtime.positions_changed.emit()


## The middle of a figure of `size` on `anchor`, in world space, on top of the floor (on a stair: on the step).
func centre_of(anchor: Vector3i, size: int) -> Vector3:
	var centre := _flat_centre(anchor, size)
	var top := -INF
	for square in MonsterMovement.block(anchor, size):
		if _stair_tops.has(square):
			top = maxf(top, float(_stair_tops[square]))
	if top > -INF:
		centre.y = top
	return centre


func _flat_centre(anchor: Vector3i, size: int) -> Vector3:
	return flat_centre(layered_map, anchor, size)


func _update_board() -> void:
	_board = MonsterMovement.build_board(mission, layered_map.held_back)
	_stair_tops = stair_tops(layered_map, mission)


## The middle of a figure of `size` on `anchor` on the floor (stairs not taken into account).
static func flat_centre(map: LayeredMap, anchor: Vector3i, size: int) -> Vector3:
	var low := map.get_tile_square_world_corners(Vector3i(anchor.x + 1, anchor.y, anchor.z + 1))
	var high := map.get_tile_square_world_corners(Vector3i(anchor.x + size, anchor.y, anchor.z + size))
	return (low[0] + high[2]) * 0.5


## For every square of a painted, revealed stair: the height of the stair mesh's top surface over the middle of the square (a ray straight
## down through the stair's triangles, highest hit). Shared with the line-of-sight tool.
static func stair_tops(map: LayeredMap, mission: MissionData) -> Dictionary:
	var tops: Dictionary = {}
	var grid := map.prop_grid
	if grid.mesh_library == null:
		return tops
	var id := map.find_item_id(grid, "stair")
	if id < 0 or grid.mesh_library.get_item_mesh(id) == null:
		return tops
	var faces := grid.mesh_library.get_item_mesh(id).get_faces()
	var mesh_transform := grid.mesh_library.get_item_mesh_transform(id)
	for entry in mission.interactables:
		if entry.mesh_item_name != "stair" or grid.get_cell_item(entry.origin_cell) != id:
			continue
		if map.held_back.has(entry) or not mission.is_effectively_visible(entry):
			continue
		var placed := grid.global_transform * Transform3D(grid.get_cell_item_basis(entry.origin_cell), grid.map_to_local(entry.origin_cell)) * mesh_transform
		var world := PackedVector3Array()
		world.resize(faces.size())
		for i in faces.size():
			world[i] = placed * faces[i]
		for cell in MissionSight.cells_of(entry):
			var square := MonsterMovement._square_of(cell, entry.origin_cell.y)
			if tops.has(square):
				continue
			var from := flat_centre(map, square, 1) + Vector3(0, 100, 0)
			var best := -INF
			for i in range(0, world.size() - 2, 3):
				var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, world[i], world[i + 1], world[i + 2])
				if hit != null:
					best = maxf(best, (hit as Vector3).y)
			if best > -INF:
				tops[square] = best + 0.02
	return tops


## The square (x, height, z, 0-based) under the mouse: on whichever level the ray meets first, a stair square on its step (`tops` from
## stair_tops()); only squares in `squares` or `tops` count. Null when there is none. Shared with the line-of-sight tool.
static func square_under(map: LayeredMap, camera: Camera3D, screen_position: Vector2, squares: Dictionary, tops: Dictionary) -> Variant:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var heights: Dictionary = {}
	for square: Vector3i in squares:
		heights[square.y] = true
	var best: Variant = null
	var best_distance := INF
	for height: int in heights:
		var plane_y := map.get_tile_square_world_corners(Vector3i(1, height, 1))[0].y
		var hit: Variant = Plane(Vector3.UP, plane_y).intersects_ray(origin, direction)
		if hit == null:
			continue
		var square := column_of(map, hit, height)
		var distance := origin.distance_to(hit)
		# a stair square is picked on its step (below), not on the floor plane under the stair
		if squares.has(square) and not tops.has(square) and distance < best_distance:
			best = square
			best_distance = distance
	for square: Vector3i in tops:
		var hit: Variant = Plane(Vector3.UP, float(tops[square])).intersects_ray(origin, direction)
		if hit == null or column_of(map, hit, square.y) != square:
			continue
		var distance := origin.distance_to(hit)
		if distance < best_distance:
			best = square
			best_distance = distance
	return best


## The square (at `height`) whose column holds world point `point`.
static func column_of(map: LayeredMap, point: Vector3, height: int) -> Vector3i:
	var grid := map.floor_grid
	var fine := grid.local_to_map(grid.to_local(point))
	var cpt := FootprintRegistry.CELLS_PER_TILE
	return Vector3i(floori(float(fine.x) / cpt), height, floori(float(fine.z) / cpt))


func _square_width() -> float:
	var corners := layered_map.get_tile_square_world_corners(Vector3i(1, 0, 1))
	return corners[0].distance_to(corners[1])


func _add_token(anchor: Vector3i, size: int, color: Color, label_text: String) -> void:
	var token := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	var radius := _square_width() * size * TOKEN_FILL * 0.5
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = TOKEN_HEIGHT
	disc.radial_segments = 32
	token.mesh = disc
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	token.material_override = material
	_tokens.add_child(token)
	token.global_position = centre_of(anchor, size) + Vector3(0, TOKEN_HEIGHT * 0.5, 0)
	var label := Label3D.new()
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.font_size = 24
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.9)
	_tokens.add_child(label)
	label.global_position = centre_of(anchor, size) + Vector3(0, LABEL_LIFT, 0)


# ---------------------------------------------------------------- a hero attacking a token

## The monster whose token is under the mouse (any square of a large base), or null. For dropping a dragged hero portrait on it.
func monster_at(screen_position: Vector2) -> RuntimeMonster:
	if not is_visible_in_tree():
		return null
	var square: Variant = _square_under(screen_position)
	if square == null:
		return null
	var figure := _figure_on(square)
	return figure.get("monster") if figure.get("kind", "") == "monster" else null


## Lights up the base of `monster` as the target of a dragged hero (null = nothing lit). Uses the drag ghost, which is idle then.
func set_target(monster: RuntimeMonster) -> void:
	if monster == null:
		if _drag.is_empty():
			_ghost.visible = false
		return
	var quad := QuadMesh.new()
	var width := _square_width() * monster.size
	quad.size = Vector2(width, width)
	quad.orientation = PlaneMesh.FACE_Y
	_ghost.mesh = quad
	(_ghost.material_override as StandardMaterial3D).albedo_color = TARGET_COLOR
	_ghost.global_position = centre_of(monster.position, monster.size) + Vector3(0, 0.05, 0)
	_ghost.visible = true


# ---------------------------------------------------------------- dragging

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _drag.is_empty():
			if blocked_provider.is_valid() and blocked_provider.call():
				return
			_update_board()
			var square: Variant = _square_under(event.position)
			if square == null:
				return
			var figure := _figure_on(square)
			if figure.is_empty():
				return
			_drag = figure
			_drag_square = null
			get_viewport().set_input_as_handled()
		elif not event.pressed and not _drag.is_empty():
			_drop()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and not _drag.is_empty():
		_drag_square = _square_under(event.position)
		_show_ghost()


func _figure_on(square: Vector3i) -> Dictionary:
	for slot: int in runtime.hero_positions:
		if runtime.hero_positions[slot] == square:
			return {"kind": "hero", "slot": slot, "size": 1, "offset": Vector3i.ZERO}
	for monster in runtime.monsters:
		if monster.placed and MonsterMovement.block(monster.position, monster.size).has(square):
			# where in its base it was grabbed, so a large token keeps that square under the mouse
			return {"kind": "monster", "monster": monster, "size": monster.size, "offset": square - monster.position}
	return {}


## Where the dragged figure would land: the square under the mouse, for a large figure the corner that keeps the grabbed square under it.
func _landing() -> Variant:
	if _drag_square == null:
		return null
	var square: Vector3i = _drag_square
	var offset: Vector3i = _drag["offset"]
	return Vector3i(square.x - offset.x, square.y, square.z - offset.z)


func _can_land(anchor: Vector3i) -> bool:
	var skip: Variant = _drag["slot"] if _drag["kind"] == "hero" else _drag["monster"]
	return MonsterMovement.can_place(_board, anchor, int(_drag["size"]), runtime.occupied_squares(skip))


func _show_ghost() -> void:
	var anchor: Variant = _landing()
	if anchor == null:
		_ghost.visible = false
		return
	var size := int(_drag["size"])
	var quad := QuadMesh.new()
	var width := _square_width() * size
	quad.size = Vector2(width, width)
	quad.orientation = PlaneMesh.FACE_Y
	_ghost.mesh = quad
	(_ghost.material_override as StandardMaterial3D).albedo_color = OK_COLOR if _can_land(anchor) else BAD_COLOR
	_ghost.global_position = centre_of(anchor, size) + Vector3(0, 0.05, 0)
	_ghost.visible = true


func _drop() -> void:
	var anchor: Variant = _landing()
	if anchor != null and _can_land(anchor):
		if _drag["kind"] == "hero":
			runtime.set_hero_position(int(_drag["slot"]), anchor)
		else:
			runtime.set_monster_position(_drag["monster"], anchor)
	_drag = {}
	_drag_square = null
	_ghost.visible = false


## The square under the mouse (stair squares on their step); null when there is none.
func _square_under(screen_position: Vector2) -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	return square_under(layered_map, camera, screen_position, _board.get("squares", {}), _stair_tops)


# ---------------------------------------------------------------- a monster's path

## Shows where a monster of `size` walks: a smooth dotted line through `path` (its positions, the start first) and the square it ends on.
## An arrow head travels along the line (ANIMATE_PATH) and stays at the end.
func show_path(path: Array[Vector3i], size: int) -> void:
	clear_path()
	if path.is_empty():
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = PATH_COLOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if path.size() > 1:
		var points: Array[Vector3] = []
		for anchor in path:
			points.append(centre_of(anchor, size) + Vector3(0, PATH_LIFT, 0))
		_path_curve = _smooth(points)
		_path_length = 0.0
		for i in range(1, _path_curve.size()):
			_path_length += _path_curve[i - 1].distance_to(_path_curve[i])
		var dot := SphereMesh.new()
		dot.radius = _square_width() * DOT_RADIUS
		dot.height = dot.radius * 2.0
		dot.radial_segments = 8
		dot.rings = 4
		dot.material = material
		var spacing := _square_width() * DOT_SPACING
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = dot
		multimesh.instance_count = maxi(int(_path_length / spacing), 1)
		_dots = MultiMeshInstance3D.new()
		_dots.multimesh = multimesh
		_path.add_child(_dots)
		_place_dots()
		_arrow = MeshInstance3D.new()
		_arrow.mesh = _arrow_mesh(_square_width() * ARROW_SIZE)
		_arrow.material_override = material
		_path.add_child(_arrow)
		_arrow_at = 0.0 if ANIMATE_PATH else _path_length
		_place_arrow()
	var end := MeshInstance3D.new()
	var quad := QuadMesh.new()
	var width := _square_width() * size
	quad.size = Vector2(width, width)
	quad.orientation = PlaneMesh.FACE_Y
	end.mesh = quad
	var end_material := material.duplicate() as StandardMaterial3D
	end_material.albedo_color = Color(PATH_COLOR.r, PATH_COLOR.g, PATH_COLOR.b, 0.45)
	end.material_override = end_material
	_path.add_child(end)
	end.global_position = centre_of(path[path.size() - 1], size) + Vector3(0, 0.06, 0)


func clear_path() -> void:
	for child in _path.get_children():
		_path.remove_child(child)
		child.free()
	_dots = null
	_arrow = null
	_path_curve = []


func _process(delta: float) -> void:
	if _arrow != null and _arrow_at < _path_length:
		_arrow_at = minf(_arrow_at + delta * ARROW_SPEED * _square_width(), _path_length)
		_place_arrow()


## The arrow head on the curve at _arrow_at, pointing the way the line goes.
func _place_arrow() -> void:
	var at := _point_at(_arrow_at)
	var ahead := _point_at(minf(_arrow_at + 0.05, _path_length))
	var behind := _point_at(maxf(_arrow_at - 0.05, 0.0))
	var direction := ahead - behind
	direction.y = 0.0
	if direction.length() < 0.0001:
		direction = Vector3.FORWARD
	_arrow.global_transform = Transform3D(Basis.looking_at(direction.normalized(), Vector3.UP), at)


## A flat triangle lying on the floor, its point towards -Z.
static func _arrow_mesh(length: float) -> ArrayMesh:
	var vertices := PackedVector3Array([Vector3(0, 0, -length * 0.7), Vector3(-length * 0.3, 0, length * 0.3), Vector3(length * 0.3, 0, length * 0.3)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Puts the dots at equal distances along the curve.
func _place_dots() -> void:
	var multimesh := _dots.multimesh
	var spacing := _square_width() * DOT_SPACING
	var local_to := _path.global_transform.affine_inverse()
	for i in multimesh.instance_count:
		var at := _point_at(i * spacing)
		multimesh.set_instance_transform(i, Transform3D(Basis(), local_to * at))


## The point `distance` along the curve.
func _point_at(distance: float) -> Vector3:
	var left := distance
	for i in range(1, _path_curve.size()):
		var piece := _path_curve[i - 1].distance_to(_path_curve[i])
		if left <= piece and piece > 0.0:
			return _path_curve[i - 1].lerp(_path_curve[i], left / piece)
		left -= piece
	return _path_curve[_path_curve.size() - 1]


## A smooth line through `points` (Catmull-Rom), as many short pieces.
static func _smooth(points: Array[Vector3]) -> Array[Vector3]:
	var curve: Array[Vector3] = []
	for i in range(points.size() - 1):
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, points.size() - 1)]
		for step in CURVE_STEPS:
			var t := float(step) / CURVE_STEPS
			var t2 := t * t
			var t3 := t2 * t
			curve.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	curve.append(points[points.size() - 1])
	return curve


## The middle of a path, for the camera.
func path_centre(path: Array[Vector3i], size: int) -> Vector3:
	var total := Vector3.ZERO
	for anchor in path:
		total += centre_of(anchor, size)
	return total / maxi(path.size(), 1)
