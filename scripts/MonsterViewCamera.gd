class_name MonsterViewCamera
extends Camera3D

## The camera of the monster (M) view. It always looks at the row of monsters from the same angle, so the names and health
## bars can face it once instead of turning to follow it. Only two things move it:
##   - the mouse wheel zooms in and out (towards / away from the figures)
##   - A / D, the left / right arrow keys, or dragging with the right mouse button move it sideways
## The sideways range is limited to the monsters on show (`set_limits()`).

## Looking down at the figures (radians): steep like the original game's monster screen (about 52 degrees). The nameplates are tilted
## by the same angle so they face the camera.
const PITCH := -0.9
const MIN_DISTANCE := 2.0
const MAX_DISTANCE := 40.0
const ZOOM_STEP := 1.0
const STRAFE_SPEED := 8.0  ## units per second with the keys
const DRAG_SPEED := 0.02  ## units per pixel of right-button drag

var _target := Vector3.ZERO  ## the point on the floor the camera looks at
var _distance := 12.0
var _min_x := 0.0
var _max_x := 0.0
var _dragging := false


func _ready() -> void:
	rotation = Vector3(PITCH, 0.0, 0.0)
	_apply()


## Looks at `target` from `distance` away (the old FreeLookCamera.jump_to() signature).
func jump_to(target: Vector3, distance: float = 12.0) -> void:
	_target = target
	_distance = clampf(distance, MIN_DISTANCE, MAX_DISTANCE)
	_min_x = minf(_min_x, target.x)
	_max_x = maxf(_max_x, target.x)
	_apply()


## How far sideways the view may go (the leftmost and rightmost monster).
func set_limits(min_x: float, max_x: float) -> void:
	_min_x = min_x
	_max_x = max_x
	_target.x = clampf(_target.x, _min_x, _max_x)
	_apply()


func _apply() -> void:
	rotation = Vector3(PITCH, 0.0, 0.0)
	var back := Vector3(0.0, -sin(PITCH), cos(PITCH))  # from the target towards the camera
	global_position = _target + back * _distance


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed and get_viewport().gui_get_hovered_control() == null
		elif event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if get_viewport().gui_get_hovered_control() != null:
				return  # a wheel turn over a panel belongs to that panel
			var step := -ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else ZOOM_STEP
			_distance = clampf(_distance + step, MIN_DISTANCE, MAX_DISTANCE)
			_apply()
	elif event is InputEventMouseMotion and _dragging:
		_strafe(-event.relative.x * DRAG_SPEED * _distance / 12.0)


func _process(delta: float) -> void:
	if not is_processing_input():
		return  # not the view on screen (MissionPlayer pauses the input of the hidden camera)
	var direction := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction += 1.0
	if direction != 0.0 and get_viewport().gui_get_focus_owner() == null:
		_strafe(direction * STRAFE_SPEED * delta)


func _strafe(amount: float) -> void:
	_target.x = clampf(_target.x + amount, _min_x, _max_x)
	_apply()
