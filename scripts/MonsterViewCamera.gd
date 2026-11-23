class_name MonsterViewCamera
extends Camera3D

## The camera of the monster (M) view. It always looks at the row of monsters from the same angle, so the names and health
## bars can face it once instead of turning to follow it. Only two things move it:
##   - the mouse wheel zooms in and out (towards / away from the figures)
##   - A / D, the left / right arrow keys, or dragging with the right mouse button move it sideways
## The sideways range is limited to the monsters on show (`set_limits()`).

## Looking down at the figures (radians): steep like the original game's monster screen (about 52 degrees) from ARC_DISTANCE on.
## Zooming in closer moves the camera along an arc: lower and more level (CLOSE_PITCH at MIN_DISTANCE), looking at a point that
## rises to CLOSE_LOOK_HEIGHT (the figures' middle), so close up you look the monsters in the face. The nameplates follow the
## angle (`pitch_changed`).
const PITCH := -0.9
const CLOSE_PITCH := -0.22
const ARC_DISTANCE := 4.0
const CLOSE_LOOK_HEIGHT := 0.45
const MIN_DISTANCE := 1.2
const MAX_DISTANCE := 40.0
const ZOOM_STEP := 1.0
const CLOSE_ZOOM_STEP := 0.4  ## inside the arc the wheel moves in smaller steps
const STRAFE_SPEED := 8.0  ## units per second with the keys
const DRAG_SPEED := 0.02  ## units per pixel of right-button drag

var _target := Vector3.ZERO  ## the point on the floor the camera looks at
var _distance := 12.0
var _min_x := 0.0
var _max_x := 0.0
var _dragging := false
var pitch := PITCH  ## the current angle (see PITCH)

signal pitch_changed(pitch: float)


func _ready() -> void:
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
	# 0 = at ARC_DISTANCE or further, 1 = at MIN_DISTANCE; eased so the camera swings level only near the end (an arc)
	var t := clampf((ARC_DISTANCE - _distance) / (ARC_DISTANCE - MIN_DISTANCE), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var new_pitch := lerpf(PITCH, CLOSE_PITCH, t)
	rotation = Vector3(new_pitch, 0.0, 0.0)
	var back := Vector3(0.0, -sin(new_pitch), cos(new_pitch))  # from the looked-at point towards the camera
	global_position = _target + Vector3(0.0, CLOSE_LOOK_HEIGHT * t, 0.0) + back * _distance
	if not is_equal_approx(new_pitch, pitch):
		pitch = new_pitch
		pitch_changed.emit(pitch)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed and get_viewport().gui_get_hovered_control() == null
		elif event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			if get_viewport().gui_get_hovered_control() != null:
				return  # a wheel turn over a panel belongs to that panel
			var size := ZOOM_STEP if _distance > ARC_DISTANCE else CLOSE_ZOOM_STEP
			var step := -size if event.button_index == MOUSE_BUTTON_WHEEL_UP else size
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
