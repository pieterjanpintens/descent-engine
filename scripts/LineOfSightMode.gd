class_name LineOfSightMode
extends Node3D

## Line of sight mode (first step) - toggled from the Gear menu's "Line of
## Sight". While active, a left click on a floor tile square marks it and
## every other floor tile square gets a coloured distance label: the
## shortest route in the x/z plane moving horizontally/vertically only
## (BFS over floor tile squares, so it walks around holes). Colours:
## 1 green, 2 yellow, 3-4 orange, 5+ red. Blocking props, real sight lines
## and stairs/levels are NOT considered yet.
##
## Squares are game-unit tile squares (2x2 fine cells), not fine cells. Only
## squares of currently visible (revealed) floor placements count. Lives
## under layered_map so it hides with the world in the monster view.

## Assigned by MissionPlayer.
var layered_map: LayeredMap
var mission: MissionData

var active: bool = false

var _labels: Array[Node3D] = []


func set_active(on: bool) -> void:
	active = on
	if not on:
		_clear()


func _unhandled_input(event: InputEvent) -> void:
	if not active or not is_visible_in_tree():
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var grid := layered_map.floor_grid
	var plane := Plane(Vector3.UP, grid.global_position.y + layered_map.floor_thickness)
	var from := camera.project_ray_origin(event.position)
	var hit: Variant = plane.intersects_ray(from, camera.project_ray_normal(event.position))
	if hit == null:
		return
	var fine := grid.local_to_map(grid.to_local(hit))
	var start := FootprintRegistry.fine_cell_to_tile_square(fine)
	var squares := _floor_squares()
	if not squares.has(Vector2i(start.x, start.z)):
		return
	get_viewport().set_input_as_handled()
	_show_distances(Vector2i(start.x, start.z), squares)


## Vector2i(tile x, tile z) -> tile y, for every square covered by a
## currently visible floor OR underlay (hazard) placement - both are walkable.
func _floor_squares() -> Dictionary:
	var squares := {}
	_collect_squares(squares, mission.floor_placements, mission.floor_occupied_cells)
	_collect_squares(squares, mission.underlay_placements, mission.underlay_occupied_cells)
	return squares


func _collect_squares(squares: Dictionary, placements: Array, occupied: Dictionary) -> void:
	var visible_origins := {}
	for placement in placements:
		if mission.is_effectively_visible(placement):
			visible_origins[placement.origin_cell] = true
	for fine: Vector3i in occupied:
		if visible_origins.has(occupied[fine]):
			var ts := FootprintRegistry.fine_cell_to_tile_square(fine)
			squares[Vector2i(ts.x, ts.z)] = ts.y


func _show_distances(start: Vector2i, squares: Dictionary) -> void:
	_clear()
	var dist := {start: 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cur + step
			if squares.has(next) and not dist.has(next):
				dist[next] = dist[cur] + 1
				queue.append(next)
	for sq: Vector2i in dist:
		_add_label(sq, squares[sq], dist[sq])


func _add_label(sq: Vector2i, y: int, distance: int) -> void:
	var corners := layered_map.get_tile_square_world_corners(Vector3i(sq.x, y, sq.y))
	var label := Label3D.new()
	label.text = "X" if distance == 0 else str(distance)
	label.modulate = _color_for(distance)
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.outline_size = 12
	label.font_size = 64
	label.pixel_size = 0.008
	label.rotation_degrees.x = -90
	add_child(label)
	label.global_position = (corners[0] + corners[2]) * 0.5 + Vector3(0, 0.02, 0)
	_labels.append(label)


func _color_for(distance: int) -> Color:
	if distance == 0:
		return Color(1, 1, 1)
	if distance == 1:
		return Color(0.25, 0.9, 0.3)
	if distance == 2:
		return Color(1, 0.9, 0.2)
	if distance <= 4:
		return Color(1, 0.6, 0.15)
	return Color(0.95, 0.25, 0.2)


func _clear() -> void:
	for l in _labels:
		l.queue_free()
	_labels.clear()
