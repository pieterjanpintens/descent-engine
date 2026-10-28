class_name LoadPage
extends Control

## The Load game page, from the designer's mockup: every save game is a wide row (SaveRow) and the rows turn like the New game page's cards, but
## vertically - the row in the middle is the one in front, the others lean away above and below it. About three rows are fully visible; the
## row height follows the room the page has. Drag, mouse wheel, the arrows or up / down move the list.
## `refresh(entries)` with one {folder, key, group, campaign, progress, tag, texture, newer} per save game; the player reacts to the signals.

signal back_pressed
signal resume_pressed(folder: String, key: String)
signal delete_pressed(folder: String, key: String, save_name: String)
signal update_pressed(folder: String, key: String)

const BACKGROUND := "res://models/ui/bg_detail.jpg"
const BACK_ARROW :="res://models/ui/back_arrow.png"
const NAV_ARROW := "res://models/ui/nav_arrow.png"
const FOCUS_SECONDS := 0.45
const VISIBLE_ROWS := 3.3        ## the stage is this many rows tall: three rows fit completely
const MIN_ROW := 90.0
const MAX_ROW := 200.0
const STEP := 1.1                ## the distance between rows, in row heights
const FAR_SPACING := 0.8         ## the rows beyond the first neighbour are packed closer
const SIDE_SQUASH_Y := 0.12      ## how much lower a row next to the focus looks, as if it were turned away
const SIDE_SQUASH_X := 0.04
const DRAG_THRESHOLD := 8.0
const ARROW_SIZE := 46.0

var _entries: Array[Dictionary] = []
var _target := 0
var _focus := 0.0
var _focus_tween: Tween
var _pressed_in_stage := false
var _dragging := false
var _dragged := false
var _drag_travel := 0.0
var _drag_velocity := 0.0  ## rows per second

var _stage: Control
var _up: Control
var _down: Control
var _title: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := TextureRect.new()  # the begin campaign page's background
	backdrop.texture = load(BACKGROUND) as Texture2D
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	margin.add_child(page)

	var header := HBoxContainer.new()
	page.add_child(header)
	header.add_child(MenuStyle.texture_button(BACK_ARROW, Vector2(78, 46), func(): back_pressed.emit()))
	_title = MenuStyle.shadow_label("Load game", 40, MenuStyle.TEXT_COLOR)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var balance := Control.new()  # keeps the title centred against the back arrow
	balance.custom_minimum_size = Vector2(78, 46)
	header.add_child(balance)

	_up = _arrow(-1)
	page.add_child(_up)
	_stage = Control.new()
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	_stage.gui_input.connect(_on_stage_input)
	_stage.resized.connect(_update_rows)
	page.add_child(_stage)
	_down = _arrow(1)
	page.add_child(_down)


## A forward arrow turned to point up or down (`direction` -1 = up).
func _arrow(direction: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, ARROW_SIZE)
	var button := MenuStyle.texture_button(NAV_ARROW, Vector2(ARROW_SIZE, ARROW_SIZE), func(): _go_to(_target + direction), true)
	button.size = Vector2(ARROW_SIZE, ARROW_SIZE)
	button.pivot_offset = Vector2(ARROW_SIZE, ARROW_SIZE) / 2.0
	button.rotation = PI / 2.0 * (-1.0 if direction < 0 else 1.0)
	button.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	button.position = Vector2(-ARROW_SIZE / 2.0, -ARROW_SIZE / 2.0)
	holder.add_child(button)
	return holder


func refresh(entries: Array[Dictionary]) -> void:
	_entries = entries
	_stop_focus_tween()
	for child in _stage.get_children():
		_stage.remove_child(child)
		child.free()
	_target = clampi(_target, 0, maxi(0, _entries.size() - 1))
	_focus = float(_target)
	if _entries.is_empty():
		var empty := Label.new()
		empty.text = "No save games yet - start one with New game."
		empty.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		empty.grow_horizontal = Control.GROW_DIRECTION_BOTH
		empty.grow_vertical = Control.GROW_DIRECTION_BOTH
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(empty)
	for index in _entries.size():
		var entry := _entries[index]
		var row := SaveRow.new()
		row.setup(entry)
		row.pressed.connect(_on_row_pressed.bind(index))
		row.resume_pressed.connect(func(): resume_pressed.emit(entry["folder"], entry["key"]))
		row.delete_pressed.connect(func(): delete_pressed.emit(entry["folder"], entry["key"], str(entry["group"])))
		row.update_pressed.connect(func(): update_pressed.emit(entry["folder"], entry["key"]))
		_stage.add_child(row)
	_update_rows()


func _row_height() -> float:
	return clampf(_stage.size.y / VISIBLE_ROWS, MIN_ROW, MAX_ROW)


## Puts every row where the list's position says: y from the distance to the focus, height, width, brightness and stacking order from it too.
func _update_rows() -> void:
	if _stage == null:
		return
	var height := _row_height()
	var step := height * STEP
	var width := _stage.size.x
	var middle := _stage.size.y / 2.0
	for index in _stage.get_child_count():
		var row := _stage.get_child(index) as SaveRow
		if row == null:
			continue
		var distance := float(index) - _focus
		var away := absf(distance)
		var near := minf(away, 1.0)
		var beyond := clampf(away - 1.0, 0.0, 1.0)
		row.visible = away < 3.2
		if not row.visible:
			continue
		row.size = Vector2(width, height)
		row.pivot_offset = row.size / 2.0
		row.apply_height(height)
		row.scale = Vector2(1.0 - SIDE_SQUASH_X * near - 0.03 * beyond, 1.0 - SIDE_SQUASH_Y * near - 0.08 * beyond)
		var offset := signf(distance) * step * (near + maxf(away - 1.0, 0.0) * FAR_SPACING)
		row.position = Vector2(0.0, middle + offset - height / 2.0)
		var shade := lerpf(1.0, 0.62, near) - 0.12 * beyond
		row.modulate = Color(shade, shade, shade, 1.0 - clampf(away - 2.2, 0.0, 1.0))
		row.z_index = 100 - int(roundf(away * 10.0))
	_update_arrows()


func _update_arrows() -> void:
	_up.visible = _target > 0
	_down.visible = _target < _entries.size() - 1


func _set_focus(value: float) -> void:
	_focus = value
	_update_rows()


func _stop_focus_tween() -> void:
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = null


func _go_to(index: int) -> void:
	_target = clampi(index, 0, maxi(0, _entries.size() - 1))
	_stop_focus_tween()
	_focus_tween = create_tween()
	_focus_tween.tween_method(_set_focus, _focus, float(_target), FOCUS_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_update_arrows()


## A row was released without a drag: a row above or below comes to the middle.
func _on_row_pressed(index: int) -> void:
	if not _dragged and index != _target:
		_go_to(index)


func _on_stage_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_pressed_in_stage = true
				_dragging = false
				_dragged = false
				_drag_travel = 0.0
				_drag_velocity = 0.0
			elif _pressed_in_stage:
				_pressed_in_stage = false
				if _dragging:
					_dragging = false
					_go_to(roundi(_focus - _drag_velocity * 0.25))
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_go_to(_target + 1)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_go_to(_target - 1)
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _pressed_in_stage and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and not _entries.is_empty():
		_drag_travel += absf(motion.relative.y)
		if not _dragging and _drag_travel > DRAG_THRESHOLD:
			_dragging = true
			_dragged = true
			_stop_focus_tween()
		if _dragging:
			var rows_moved := -motion.relative.y / (_row_height() * STEP)
			_focus = clampf(_focus + rows_moved, -0.4, float(_entries.size() - 1) + 0.4)
			var seconds := maxf(get_process_delta_time(), 0.001)
			_drag_velocity = lerpf(_drag_velocity, rows_moved / seconds, 0.35)
			_target = clampi(roundi(_focus), 0, _entries.size() - 1)
			_update_rows()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_up"):
		_go_to(_target - 1)
		accept_event()
	elif event.is_action_pressed("ui_down"):
		_go_to(_target + 1)
		accept_event()
	elif event.is_action_pressed("ui_accept") and not _entries.is_empty():
		var entry := _entries[_target]
		resume_pressed.emit(entry["folder"], entry["key"])
		accept_event()
