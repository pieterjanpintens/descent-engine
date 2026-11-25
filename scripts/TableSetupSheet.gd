class_name TableSetupSheet
extends Control

## "Set up the table": a full-screen page shown before the first stage of a mission (and of a new Table) is built, and from the Gear
## menu. It draws the player's real table from above with the space the WHOLE map of the Table needs (every stage, also those not
## revealed yet - only as a dashed rectangle, its shape would spoil them), the start area in orange with its distance to the left edge and to the player's edge, and - when a table camera is set up - where
## the camera stands and the part of the table it sees. The table size and the camera's height / distance behind the edge are edited
## right here and remembered (PlayerSettings). The plan itself is TableSetup.plan().
##
## `await open_sheet(mission, camera_fov)`; camera_fov = Vector2(tan across, tan along) of the camera's half field of view, ZERO =
## the default (TableSetup.DEFAULT_TAN_*). Returns when the player presses Continue.

signal _closed

const SIDE_WIDTH := 300.0
const TABLE_COLOR := Color(0.42, 0.3, 0.2)
const TABLE_EDGE := Color(0.25, 0.17, 0.1)
const MAP_COLOR := Color(0.78, 0.78, 0.8)
const START_COLOR := Color(1.0, 0.55, 0.15)
const COVERAGE_COLOR := Color(0.35, 0.85, 1.0, 0.22)
const MEASURE_COLOR := Color(1, 1, 1, 0.9)

var _mission: MissionData
var _fov := Vector2.ZERO
var _plan: Dictionary = {}
var _view: _SheetView
var _preset: OptionButton
var _width: SpinBox
var _depth: SpinBox
var _height: SpinBox
var _back: SpinBox
var _camera_box: VBoxContainer
var _map_text: Label
var _start_text: Label
var _camera_text: Label
var _show_check: CheckBox
var _syncing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var background := ColorRect.new()
	background.color = Color(0.06, 0.06, 0.08, 0.97)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		row.set("offset_" + side, 14.0 if side in ["left", "top"] else -14.0)
	row.add_theme_constant_override("separation", 14)
	add_child(row)

	_view = _SheetView.new()
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_view)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = SIDE_WIDTH + 14
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = SIDE_WIDTH
	side.add_theme_constant_override("separation", 7)
	scroll.add_child(side)

	var title := Label.new()
	title.text = "Set up the table"
	title.add_theme_font_size_override("font_size", 22)
	side.add_child(title)

	side.add_child(_heading("Your table"))
	_preset = OptionButton.new()
	for preset: Array in CreatorSettings.TABLE_PRESETS:
		_preset.add_item(tr(str(preset[0])) + tr(" (%d x %d cm)") % [preset[1], preset[2]])
	_preset.add_item(tr("Custom"))
	_preset.item_selected.connect(_on_preset_selected)
	side.add_child(_preset)
	_width = _spin_row(side, "Width (cm)", 40, 400)
	_depth = _spin_row(side, "Depth (cm)", 40, 400)

	_map_text = _text(side)
	side.add_child(_heading("Where to start"))
	_start_text = _text(side)

	_camera_box = VBoxContainer.new()
	_camera_box.add_theme_constant_override("separation", 7)
	side.add_child(_camera_box)
	_camera_box.add_child(_heading("Table camera"))
	_height = _spin_row(_camera_box, "Height above the table (cm)", 10, 300)
	_back = _spin_row(_camera_box, "Behind the table edge (cm)", 0, 200)
	_camera_text = _text(_camera_box)

	_show_check = CheckBox.new()
	_show_check.text = "Show this before every mission"
	_show_check.toggled.connect(func(on: bool):
		PlayerSettings.show_table_setup = on
		PlayerSettings.save_settings())
	side.add_child(_show_check)
	var go := Button.new()
	go.text = "Continue"
	go.custom_minimum_size.y = 40
	go.pressed.connect(func():
		visible = false
		_closed.emit())
	StoryCard.fit_button(go)
	side.add_child(go)

	for spin in [_width, _depth, _height, _back]:
		(spin as SpinBox).value_changed.connect(func(_v: float): _on_changed())


## Shows the sheet for the Table that is being set up; returns when the player presses Continue.
func open_sheet(mission: MissionData, camera_fov: Vector2 = Vector2.ZERO) -> void:
	_mission = mission
	_fov = camera_fov
	_syncing = true
	_width.value = PlayerSettings.table_width_cm
	_depth.value = PlayerSettings.table_depth_cm
	_height.value = PlayerSettings.camera_height_cm
	_back.value = PlayerSettings.camera_back_cm
	_show_check.set_pressed_no_signal(PlayerSettings.show_table_setup)
	_syncing = false
	_camera_box.visible = TableCamera.is_configured()
	_on_changed()
	visible = true
	move_to_front()
	await _closed


func _on_preset_selected(index: int) -> void:
	if index >= CreatorSettings.TABLE_PRESETS.size():
		return
	_syncing = true
	_width.value = CreatorSettings.TABLE_PRESETS[index][1]
	_depth.value = CreatorSettings.TABLE_PRESETS[index][2]
	_syncing = false
	_on_changed()


func _on_changed() -> void:
	if _syncing or _mission == null:
		return
	PlayerSettings.table_width_cm = _width.value
	PlayerSettings.table_depth_cm = _depth.value
	PlayerSettings.camera_height_cm = _height.value
	PlayerSettings.camera_back_cm = _back.value
	PlayerSettings.save_settings()
	var preset_index := CreatorSettings.TABLE_PRESETS.size()
	for i in CreatorSettings.TABLE_PRESETS.size():
		var preset: Array = CreatorSettings.TABLE_PRESETS[i]
		if is_equal_approx(_width.value, preset[1]) and is_equal_approx(_depth.value, preset[2]):
			preset_index = i
	_preset.select(preset_index)
	var camera := {}
	if _camera_box.visible:
		camera = {"on": true, "height": _height.value, "back": _back.value,
			"tan_across": _fov.x if _fov.x > 0.0 else TableSetup.DEFAULT_TAN_ACROSS,
			"tan_along": _fov.y if _fov.y > 0.0 else TableSetup.DEFAULT_TAN_ALONG}
	_plan = TableSetup.plan(_mission, Vector2(_width.value, _depth.value), CreatorSettings.square_cm, camera)
	_update_texts()
	_view.plan = _plan
	_view.queue_redraw()


func _update_texts() -> void:
	if (_plan["map_squares"] as Dictionary).is_empty():
		_map_text.text = tr("This Table has no floor yet.")
		_start_text.text = ""
		_camera_text.text = ""
		return
	var map_cm: Vector2 = _plan["map_cm"]
	var span: Vector2i = _plan["span"]
	var size_text := tr("The whole map is %d x %d cm (%d x %d squares).") % [roundi(map_cm.x), roundi(map_cm.y), maxi(span.x, span.y), mini(span.x, span.y)]
	_map_text.text = size_text + " " + (tr("It fits on this table.") if _plan["fits"] else tr("It does NOT fit on this table: some of it will hang over the edge."))
	if (_plan["start_squares"] as Dictionary).is_empty():
		_start_text.text = tr("Build the map in the middle of the table.")
	else:
		var side_cm := maxi(0, roundi(_plan["start_side"]))
		var near_cm := maxi(0, roundi(_plan["start_near"]))
		if _plan["start_from_right"]:
			_start_text.text = tr("Build the orange start area first: %d cm from the right edge of the table and %d cm from your edge. Later stages then fit around it.") % [side_cm, near_cm]
		else:
			_start_text.text = tr("Build the orange start area first: %d cm from the left edge of the table and %d cm from your edge. Later stages then fit around it.") % [side_cm, near_cm]
	var camera: Dictionary = _plan["camera"]
	if camera.is_empty():
		_camera_text.text = ""
		return
	var where := tr("Put the camera in the middle of the left short side of the table, pointing along the table.") if camera["side"] == "left" else tr("Put the camera in the middle of the right short side of the table, pointing along the table.")
	var verdict := ""
	if camera["sees_all"]:
		verdict = tr("From this height it sees the whole map.")
	elif float(camera["needed_height"]) > 0.0:
		verdict = tr("From this height it does not see the whole map: raise it to at least %d cm.") % roundi(camera["needed_height"])
	else:
		verdict = tr("It cannot see the whole map from this side; put it further behind the edge.")
	_camera_text.text = where + " " + verdict


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.56, 0.79, 0.9))
	return label


func _text(parent: Control) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = SIDE_WIDTH
	parent.add_child(label)
	return label


func _spin_row(parent: Control, text: String, low: float, high: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = 1
	spin.custom_minimum_size.x = 90
	row.add_child(spin)
	return spin


# ---------------------------------------------------------------- the drawing

class _SheetView extends Control:
	var plan: Dictionary = {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _draw() -> void:
		if plan.is_empty() or not plan.has("table"):
			return
		var table: Vector2 = plan["table"]
		var camera: Dictionary = plan["camera"]
		# what has to fit in the drawing: the table, the camera, a margin for the labels
		var area := Rect2(Vector2.ZERO, table)
		if not camera.is_empty():
			area = area.expand(camera["position"])
		area = area.grow(12.0)
		area.size.y += 12.0  # room for "your side"
		var scale := minf(size.x / area.size.x, size.y / area.size.y)
		var origin := (size - area.size * scale) * 0.5 - area.position * scale
		var to_view := func(p: Vector2) -> Vector2: return origin + p * scale
		var font := get_theme_default_font()

		# the table
		var table_rect := Rect2(to_view.call(Vector2.ZERO), table * scale)
		draw_rect(table_rect, TABLE_COLOR)
		draw_rect(table_rect, TABLE_EDGE, false, 3.0)
		# what the camera sees
		if not camera.is_empty():
			var outline := PackedVector2Array()
			for p in camera["coverage"] as PackedVector2Array:
				outline.append(to_view.call(p))
			draw_colored_polygon(outline, COVERAGE_COLOR)
		# the map only as the space it needs (its shape would give the unrevealed stages away), the start area in full
		var start: Dictionary = plan["start_squares"]
		var space := Rect2()
		var first := true
		for sq: Vector2i in plan["map_squares"]:
			var box := TableSetup.square_rect(plan, sq)
			space = box if first else space.merge(box)
			first = false
		if not first:
			var view_space := Rect2(to_view.call(space.position), space.size * scale)
			draw_rect(view_space, Color(MAP_COLOR.r, MAP_COLOR.g, MAP_COLOR.b, 0.14))
			var corners := [view_space.position, Vector2(view_space.end.x, view_space.position.y), view_space.end, Vector2(view_space.position.x, view_space.end.y)]
			for i in 4:
				_dashes(corners[i], corners[(i + 1) % 4], MAP_COLOR)
		for sq: Vector2i in start:
			var box := TableSetup.square_rect(plan, sq)
			draw_rect(Rect2(to_view.call(box.position), box.size * scale).grow(-0.4), START_COLOR)
		if not first:
			var label_at := Rect2(to_view.call(space.position), space.size * scale).position + Vector2(0, -6)
			draw_string(font, label_at, tr("Space for the whole map"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MAP_COLOR)
		# distances of the start area to the left edge and to the player's edge
		var start_rect: Rect2 = plan["start_rect"]
		if start_rect.size != Vector2.ZERO:
			var y: float = start_rect.get_center().y
			if plan["start_from_right"]:
				_measure(to_view.call(Vector2(start_rect.end.x, y)), to_view.call(Vector2(table.x, y)), tr("%d cm") % maxi(0, roundi(plan["start_side"])), font)
			else:
				_measure(to_view.call(Vector2(0, y)), to_view.call(Vector2(start_rect.position.x, y)), tr("%d cm") % maxi(0, roundi(plan["start_side"])), font)
			var x: float = start_rect.get_center().x
			_measure(to_view.call(Vector2(x, start_rect.end.y)), to_view.call(Vector2(x, table.y)), tr("%d cm") % maxi(0, roundi(plan["start_near"])), font)
		# the player's side
		var bottom: Vector2 = to_view.call(Vector2(table.x * 0.5, table.y))
		draw_string(font, bottom + Vector2(-60, 22), tr("Your side"), HORIZONTAL_ALIGNMENT_CENTER, 120, 15, Color(1, 1, 1, 0.8))
		# the camera
		if not camera.is_empty():
			var at: Vector2 = to_view.call(camera["position"])
			draw_circle(at, 9, Color(0.1, 0.1, 0.12))
			draw_arc(at, 9, 0, TAU, 20, Color(0.35, 0.85, 1.0), 2.0, true)
			draw_circle(at, 3.5, Color(0.35, 0.85, 1.0))
			var label_at := at + Vector2(-60, -16)
			draw_string(font, label_at, tr("Camera"), HORIZONTAL_ALIGNMENT_CENTER, 120, 14, Color(0.6, 0.9, 1.0))

	func _measure(a: Vector2, b: Vector2, text: String, font: Font) -> void:
		if a.distance_to(b) < 4.0:
			return
		draw_dashes(a, b)
		var direction := (b - a).normalized()
		var normal := Vector2(-direction.y, direction.x)
		for end in [a, b]:
			draw_line(end - normal * 5, end + normal * 5, MEASURE_COLOR, 2.0)
		var middle := (a + b) * 0.5
		var box := Vector2(56, 18)
		draw_rect(Rect2(middle - box * 0.5, box), Color(0, 0, 0, 0.65))
		draw_string(font, middle + Vector2(-box.x * 0.5, 5), text, HORIZONTAL_ALIGNMENT_CENTER, box.x, 13, MEASURE_COLOR)

	func draw_dashes(a: Vector2, b: Vector2) -> void:
		_dashes(a, b, MEASURE_COLOR)

	func _dashes(a: Vector2, b: Vector2, color: Color) -> void:
		var length := a.distance_to(b)
		if length <= 0.0:
			return
		var direction := (b - a) / length
		var t := 0.0
		while t < length:
			draw_line(a + direction * t, a + direction * minf(t + 6.0, length), color, 2.0)
			t += 10.0
