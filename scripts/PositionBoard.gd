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

var _tokens: Node3D
var _ghost: MeshInstance3D
var _board: Dictionary = {}
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
	runtime.positions_changed.connect(refresh)
	runtime.monsters_changed.connect(refresh)
	refresh()


## Rebuilds every token from the runtime's positions.
func refresh() -> void:
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
	_board = MonsterMovement.build_board(mission, layered_map.held_back)
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


## The middle of a figure of `size` on `anchor`, in world space, on top of the floor.
func centre_of(anchor: Vector3i, size: int) -> Vector3:
	var low := layered_map.get_tile_square_world_corners(Vector3i(anchor.x + 1, anchor.y, anchor.z + 1))
	var high := layered_map.get_tile_square_world_corners(Vector3i(anchor.x + size, anchor.y, anchor.z + size))
	return (low[0] + high[2]) * 0.5


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


# ---------------------------------------------------------------- dragging

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _drag.is_empty():
			if blocked_provider.is_valid() and blocked_provider.call():
				return
			_board = MonsterMovement.build_board(mission, layered_map.held_back)
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


## The floor square (x, height, z, 0-based) under the mouse, on whichever level the ray meets first; null when there is none.
func _square_under(screen_position: Vector2) -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var squares: Dictionary = _board.get("squares", {})
	var grid := layered_map.floor_grid
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var heights: Dictionary = {}
	for square: Vector3i in squares:
		heights[square.y] = true
	var best: Variant = null
	var best_distance := INF
	for height: int in heights:
		var plane_y := layered_map.get_tile_square_world_corners(Vector3i(1, height, 1))[0].y
		var hit: Variant = Plane(Vector3.UP, plane_y).intersects_ray(origin, direction)
		if hit == null:
			continue
		var fine := grid.local_to_map(grid.to_local(hit))
		var cpt := FootprintRegistry.CELLS_PER_TILE
		var square := Vector3i(floori(float(fine.x) / cpt), height, floori(float(fine.z) / cpt))
		var distance := origin.distance_to(hit)
		if squares.has(square) and distance < best_distance:
			best = square
			best_distance = distance
	return best
