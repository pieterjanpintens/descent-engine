class_name FreeLookCamera
extends Camera3D

## Attach directly to your Camera3D. Mimics Godot's editor navigation:
##   - Hold RIGHT mouse button + drag to look around
##   - While holding right-click, WASD moves horizontally (relative to
##     where you're looking), Q/E moves down/up
##   - Scroll wheel dollies the camera forward/backward
##   - Hold Shift while dragging to move faster

@export var move_speed: float = 10.0
@export var boost_multiplier: float = 3.0
@export var look_sensitivity: float = 0.005
@export var zoom_step: float = 1.0

var _rotating: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x


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
			_rotating = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _rotating else Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			translate(Vector3(0, 0, -zoom_step))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			translate(Vector3(0, 0, zoom_step))
	elif event is InputEventMouseMotion and _rotating:
		_yaw -= event.relative.x * look_sensitivity
		_pitch -= event.relative.y * look_sensitivity
		_pitch = clamp(_pitch, -1.5, 1.5)  # avoid flipping past straight up/down
		rotation = Vector3(_pitch, _yaw, 0)


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
