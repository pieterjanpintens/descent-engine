class_name FreeLookCamera
extends Camera3D

## Attach directly to your Camera3D. Mimics Godot's editor navigation:
##   - Hold RIGHT mouse button + drag to look around
##   - While holding right-click, WASD moves horizontally (relative to
##     where you're looking), Q/E moves down/up
##   - Scroll wheel dollies the camera forward/backward
##   - Hold Shift while dragging to move faster

## A right-click that was not a drag (the mouse hardly moved): the editors open their context menu at this screen position.
signal context_requested(screen_position: Vector2)

## How far (pixels) the mouse may move with the right button down and still count as a click, not the start of looking around.
const CLICK_SLOP := 4.0

@export var move_speed: float = 10.0
@export var boost_multiplier: float = 3.0
@export var look_sensitivity: float = 0.005
@export var zoom_step: float = 1.0

var _rotating: bool = false
var _right_down: bool = false  ## the right button is down but looking around has not started yet
var _right_press_position := Vector2.ZERO
var _right_moved := 0.0
var _yaw: float = 0.0
var _pitch: float = 0.0


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x


## The camera's place and look direction, for handing it over to another scene and back (debug snapshots, editor round trip).
func export_view() -> Dictionary:
	return {"position": global_position, "yaw": _yaw, "pitch": _pitch}


func import_view(view: Dictionary) -> void:
	if view.is_empty():
		return
	_yaw = float(view["yaw"])
	_pitch = float(view["pitch"])
	rotation = Vector3(_pitch, _yaw, 0)
	global_position = view["position"]


## Repositions the camera to look at a world point (e.g. "jump to this
## placed tile" from CreatorPalette) - offsets back/up from the target so
## it's framed nicely rather than sitting exactly on top of it. Updates
## the internal _yaw/_pitch too, not just rotation directly - otherwise
## the next right-click-drag would compute rotation from the STALE stored
## values and the camera would snap back to wherever it was facing before
## the jump the moment you tried to look around.
func jump_to(target: Vector3, distance: float = 12.0) -> void:
	global_position = target + Vector3(0, distance * 0.6, distance)
	look_at(target, Vector3.UP)
	_yaw = rotation.y
	_pitch = rotation.x


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# _input() fires for EVERY node unconditionally, before Godot's
			# own GUI system gets a chance to claim the event for whatever
			# Control is under the cursor - a right-click meant for e.g.
			# CreatorOutline's context menu would otherwise ALSO engage
			# camera-look here, capturing (hiding + re-centering) the mouse
			# out from under that menu. Skip engaging entirely when a
			# Control actually wants this click.
			if event.pressed and get_viewport().gui_get_hovered_control() != null:
				return
			if event.pressed:
				# Looking around only starts once the mouse really moves, so a plain click leaves the cursor alone (and can open a menu).
				_right_down = true
				_right_press_position = event.position
				_right_moved = 0.0
			else:
				var was_click := _right_down and not _rotating
				_right_down = false
				_set_rotating(false)
				if was_click:
					context_requested.emit(_right_press_position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			# Same reason as the right-click guard above: a wheel turn over a
			# panel (the side panel's scroll areas) belongs to that panel.
			if get_viewport().gui_get_hovered_control() != null:
				return
			translate(Vector3(0, 0, -zoom_step))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if get_viewport().gui_get_hovered_control() != null:
				return
			translate(Vector3(0, 0, zoom_step))
	elif event is InputEventMouseMotion and _right_down and not _rotating:
		_right_moved += event.relative.length()
		if _right_moved > CLICK_SLOP:
			_set_rotating(true)
	elif event is InputEventMouseMotion and _rotating:
		_yaw -= event.relative.x * look_sensitivity
		_pitch -= event.relative.y * look_sensitivity
		_pitch = clamp(_pitch, -1.5, 1.5)  # avoid flipping past straight up/down
		rotation = Vector3(_pitch, _yaw, 0)


func _set_rotating(on: bool) -> void:
	_rotating = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if not _rotating:
		return  # only move while actively looking around, matching editor feel

	var speed := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= boost_multiplier

	var direction := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		direction -= transform.basis.z
	if Input.is_key_pressed(KEY_S):
		direction += transform.basis.z
	if Input.is_key_pressed(KEY_A):
		direction -= transform.basis.x
	if Input.is_key_pressed(KEY_D):
		direction += transform.basis.x
	if Input.is_key_pressed(KEY_E):
		direction += transform.basis.y
	if Input.is_key_pressed(KEY_Q):
		direction -= transform.basis.y

	if direction != Vector3.ZERO:
		global_position += direction.normalized() * speed * delta
