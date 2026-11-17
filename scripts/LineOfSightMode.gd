class_name LineOfSightMode
extends Node3D

## Line of sight / range tool - toggled from the Gear menu's "Line of Sight". While active, a left click on a floor tile square (on ANY level)
## marks it as a figure standing there, and every square that figure can SEE gets a coloured number: the range to it: the shortest route in squares, diagonals
## included (every square touching the viewer's is 1) (holes are walked around, solid pieces are not in the way); height does not count. Squares without a line of sight get NO number. Colours: 1 green, 2 yellow, 3-4 orange, 5+ red.
##
## Sight is the author's rule (SightLine; the Options setting picks centre to corner by default), at figure height, blocked by trees, tall / medium pillars, gates and an
## archway's end posts, never through a floor, no limit up or down; the levels are the heights (MissionSight). Squares of revealed floor and
## hazard placements only. Lives under layered_map so it hides with the world in the monster view. Not seen in a running Player.

## Assigned by MissionPlayer.
var layered_map: LayeredMap
var mission: MissionData

var active: bool = false

var _labels: Array[Node3D] = []
## Stair squares -> the height of the step (PositionBoard.stair_tops()): clicks pick the step, numbers sit on it.
var _stair_tops: Dictionary = {}


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
	SightLine.mode = PlayerSettings.sight_rule
	var data := MissionSight.build(mission, layered_map.held_back)
	_stair_tops = PositionBoard.stair_tops(layered_map, mission)
	var start: Variant = PositionBoard.square_under(layered_map, camera, event.position, data["squares"], _stair_tops)
	if start == null:
		return
	get_viewport().set_input_as_handled()
	_show(start, data)


## World y of the walking surface at a height (a level) - the labels sit just above it.
func _plane_y(height: int) -> float:
	return layered_map.get_tile_square_world_corners(Vector3i(1, height, 1))[0].y


func _show(start: Vector3i, data: Dictionary) -> void:
	_clear()
	var distance := MissionSight.routes(data, start)
	var seen: Dictionary = {}
	for square in SightLine.visible_from(data["sight"], Vector2i(start.x, start.z), start.y):
		seen[square] = true
	for square: Vector3i in distance:
		if square == start or seen.has(square):  # no line of sight, no number
			_add_label(square, distance[square])


func _add_label(square: Vector3i, distance: int) -> void:
	# the layered map counts tile squares from 1, the sight code from 0
	var corners := layered_map.get_tile_square_world_corners(Vector3i(square.x + 1, square.y, square.z + 1))
	var label := Label3D.new()
	label.text = "X" if distance == 0 else str(distance)
	label.modulate = _color_for(distance)
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.outline_size = 12
	label.font_size = 64
	label.pixel_size = 0.008
	label.rotation_degrees.x = -90
	add_child(label)
	label.global_position = (corners[0] + corners[2]) * 0.5
	if _stair_tops.has(square):
		label.global_position.y = float(_stair_tops[square])  # on the step
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
