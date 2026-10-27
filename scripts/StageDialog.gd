class_name StageDialog
extends Window

## "Generate stage..." (mission editor): describe an area in words, the AI designs it (StageGenerator), the checker verifies it, and Build puts it
## into the open mission as a new stage group (StageBuilder, one undo step). Nothing is sent to the AI until Generate is pressed.
## Experimental (branch experiment/stage-generation).

var creator_controller: CreatorController
var layered_map: LayeredMap

var _name_edit: LineEdit
var _description_edit: TextEdit
var _heroes_check: CheckBox
var _x_spin: SpinBox
var _z_spin: SpinBox
var _generate_button: Button
var _cancel_button: Button
var _build_button: Button
var _status_label: Label
var _picture_label: Label
var _issues_label: Label
var _generator: StageGenerator
var _last: Dictionary = {}


func _ready() -> void:
	title = "Generate stage"
	min_size = Vector2i(640, 560)
	exclusive = false
	close_requested.connect(hide)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)

	column.add_child(_heading("Describe the area"))
	var hint := Label.new()
	hint.text = "Say what the area should be and what is in it, e.g. \"The first area is a crossroad, on each end is a staircase with a door.\" The AI designs it from the pieces in the box; it is checked and only built when you press Build."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(580, 0)
	hint.modulate = Color(1, 1, 1, 0.7)
	column.add_child(hint)

	var name_row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "Stage name:"
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Crossroad"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)
	column.add_child(name_row)

	_description_edit = TextEdit.new()
	_description_edit.custom_minimum_size = Vector2(580, 110)
	_description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_description_edit.placeholder_text = "Describe the area..."
	column.add_child(_description_edit)

	_heroes_check = CheckBox.new()
	_heroes_check.text = "The heroes start in this area"
	column.add_child(_heroes_check)

	var place_row := HBoxContainer.new()
	var place_label := Label.new()
	place_label.text = "Put its top-left corner at x:"
	place_row.add_child(place_label)
	_x_spin = _spin()
	place_row.add_child(_x_spin)
	var z_label := Label.new()
	z_label.text = "z:"
	place_row.add_child(z_label)
	_z_spin = _spin()
	place_row.add_child(_z_spin)
	var spot_button := Button.new()
	spot_button.text = "Next free spot"
	spot_button.tooltip_text = "Just right of the existing map."
	spot_button.pressed.connect(_use_free_spot)
	place_row.add_child(spot_button)
	column.add_child(place_row)

	var button_row := HBoxContainer.new()
	_generate_button = Button.new()
	_generate_button.text = "Generate"
	_generate_button.pressed.connect(_on_generate_pressed)
	button_row.add_child(_generate_button)
	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.visible = false
	_cancel_button.pressed.connect(func(): if _generator != null: _generator.cancel())
	button_row.add_child(_cancel_button)
	_build_button = Button.new()
	_build_button.text = "Build into the mission"
	_build_button.disabled = true
	_build_button.pressed.connect(_on_build_pressed)
	button_row.add_child(_build_button)
	column.add_child(button_row)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(580, 0)
	column.add_child(_status_label)

	column.add_child(_heading("What the AI built"))
	_picture_label = Label.new()
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Menlo", "DejaVu Sans Mono", "Courier New", "monospace"])
	_picture_label.add_theme_font_override("font", mono)
	_picture_label.add_theme_font_size_override("font_size", 14)
	column.add_child(_picture_label)
	_issues_label = Label.new()
	_issues_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_issues_label.custom_minimum_size = Vector2(580, 0)
	column.add_child(_issues_label)


func open() -> void:
	if layered_map == null or layered_map.mission == null:
		return
	_use_free_spot()
	if not AiClient.is_configured():
		_status_label.text = "AI help is not set up. Turn it on in Options > AI (an API key, or Claude Code on this PC)."
	elif _status_label.text.begins_with("AI help is not set up"):
		_status_label.text = ""
	popup_centered_clamped(Vector2i(700, 760), 0.9)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HeadingLabel"
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.56, 0.79, 0.9))
	return label


func _spin() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -60
	spin.max_value = 60
	spin.step = 1
	spin.custom_minimum_size = Vector2(80, 0)
	return spin


func _use_free_spot() -> void:
	var spot := StageBuilder.free_spot(layered_map.mission)
	_x_spin.value = spot.x
	_z_spin.value = spot.y


func _on_generate_pressed() -> void:
	if not AiClient.is_configured():
		_status_label.text = "AI help is not set up. Turn it on in Options > AI."
		return
	if _description_edit.text.strip_edges() == "":
		_status_label.text = "Describe the area first."
		return
	if _generator == null:
		_generator = StageGenerator.new()
		add_child(_generator)
		_generator.on_status = func(text: String): _status_label.text = text
	_set_busy(true)
	_build_button.disabled = true
	_picture_label.text = ""
	_issues_label.text = ""
	var mission := layered_map.mission
	var options := {
		"name": _name_edit.text, "heroes_start": _heroes_check.button_pressed,
		"max_players": mission.max_players, "used": mission.get_component_usage(),
	}
	_last = await _generator.generate(_description_edit.text, options)
	_set_busy(false)
	if _last.get("cancelled", false):
		_status_label.text = "Cancelled."
		return
	if str(_last["error"]) != "":
		_status_label.text = str(_last["error"])
		return
	_picture_label.text = str(_last["picture"])
	_issues_label.text = str(_last["issues"])
	if _last["ok"]:
		_status_label.text = "Done after %d attempt%s - check the picture, then Build." % [_last["attempts"], "" if _last["attempts"] == 1 else "s"]
		_build_button.disabled = false
	else:
		_status_label.text = "The AI could not fix every problem in %d attempts (see below). Change the description or press Generate again." % _last["attempts"]


func _set_busy(busy: bool) -> void:
	_generate_button.disabled = busy
	_cancel_button.visible = busy


func _on_build_pressed() -> void:
	if _last.is_empty() or not _last.get("ok", false):
		return
	var corner := Vector2i(int(_x_spin.value), int(_z_spin.value))
	var options := {"name": _name_edit.text, "heroes_start": _heroes_check.button_pressed}
	var piece_count: int = _last["result"]["pieces"].size()
	var result: Dictionary = _last["result"]
	creator_controller.operation_history.record("Generate stage", func():
		StageBuilder.build(layered_map, result, corner, options)
	)
	layered_map.notify_objects_changed()
	var cpt := FootprintRegistry.CELLS_PER_TILE
	creator_controller.jump_to_cell(Vector3i(corner.x * cpt, 0, corner.y * cpt), layered_map.floor_grid)
	_status_label.text = "Built %d pieces as a new stage group. Undo (Ctrl+Z) removes it." % piece_count
	_build_button.disabled = true
	_last = {}
