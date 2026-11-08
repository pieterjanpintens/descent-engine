class_name LevelFormulaDialog
extends Window

## Edits a level shift formula (see LevelFormula): the mission's default ("Monster levels…" in the Mission menu) or one monster's own ("Level shift…"
## in its properties, where "use the mission's" is possible). A preset picker, the formula, a check of the text and a preview table that shows the
## shift for every difficulty and party size, so the effect of a formula can be seen before it is used.
## The dialog changes nothing itself: every change goes to `on_commit(formula: String)`, which the opener applies through its undo-tracked commit.

const PLAYER_COUNTS := [1, 2, 3, 4, 5, 6]

var _on_commit: Callable
var _mission: MissionData
var _monster_level: int = 1  ## the level the preview uses for `level` (a monster's own; 1 for the mission default)
var _inherited: String = ""  ## the mission's formula, shown when a monster uses it ("" = the mission has none)
var _allow_inherit: bool = false
var _suppress: bool = false

var _title_label: Label
var _inherit_check: CheckBox
var _preset_picker: OptionButton
var _preset_hint: Label
var _formula_edit: LineEdit
var _status: Label
var _names_label: Label
var _preview: GridContainer


func _ready() -> void:
	min_size = Vector2i(420, 360)
	close_requested.connect(hide)
	visible = false
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)

	_title_label = Label.new()
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.custom_minimum_size.x = 480
	column.add_child(_title_label)

	_inherit_check = CheckBox.new()
	_inherit_check.text = "Use the mission's formula"
	_inherit_check.toggled.connect(func(on: bool):
		if _suppress:
			return
		if on:
			_commit("")
		else:
			_commit(_inherited if _inherited != "" else LevelFormula.DEFAULT)
		_refresh())
	column.add_child(_inherit_check)

	_preset_picker = OptionButton.new()
	_preset_picker.add_item("Presets…")
	for preset in LevelFormula.presets():
		_preset_picker.add_item(preset[0])
	_preset_picker.item_selected.connect(func(index: int):
		if _suppress or index == 0:
			return
		var preset: Array = LevelFormula.presets()[index - 1]
		_formula_edit.text = preset[1]
		_preset_hint.text = preset[2]
		_commit(preset[1])
		_preset_picker.select(0)
		_refresh())
	column.add_child(_preset_picker)
	_preset_hint = Label.new()
	_preset_hint.modulate = Color(1, 1, 1, 0.75)
	_preset_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preset_hint.custom_minimum_size.x = 480
	column.add_child(_preset_hint)

	var formula_row := HBoxContainer.new()
	var formula_label := Label.new()
	formula_label.text = "Level shift ="
	formula_row.add_child(formula_label)
	_formula_edit = LineEdit.new()
	_formula_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_formula_edit.text_changed.connect(func(_text: String): _refresh_preview())
	_formula_edit.text_submitted.connect(func(_text: String): _commit_text())
	_formula_edit.focus_exited.connect(_commit_text)
	formula_row.add_child(_formula_edit)
	column.add_child(formula_row)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 480
	column.add_child(_status)

	_names_label = Label.new()
	_names_label.modulate = Color(1, 1, 1, 0.75)
	_names_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_names_label.custom_minimum_size.x = 480
	column.add_child(_names_label)

	var preview_title := Label.new()
	preview_title.text = "Shift per difficulty (rows) and number of heroes (columns)"
	column.add_child(preview_title)
	_preview = GridContainer.new()
	_preview.columns = PLAYER_COUNTS.size() + 1
	_preview.add_theme_constant_override("h_separation", 14)
	column.add_child(_preview)


## `mission` supplies the variable names. `inherited` is the mission's own formula (used by a monster that follows the mission). With
## `allow_inherit` the dialog offers "use the mission's formula" (formula "" = follow it). `monster_level` is what `level` is in the preview.
func open_for(title_text: String, formula: String, mission: MissionData, allow_inherit: bool, inherited: String, monster_level: int, on_commit: Callable) -> void:
	title = title_text
	_on_commit = on_commit
	_mission = mission
	_allow_inherit = allow_inherit
	_inherited = inherited.strip_edges()
	_monster_level = monster_level
	_suppress = true
	_title_label.text = "The level a monster spawns at is the level it was given plus this shift (never below 1)." + (
		" Leave it on the mission's formula, or give this monster its own (0 = ignore the difficulty)." if allow_inherit else " Individual monsters can override it.")
	_inherit_check.visible = allow_inherit
	_inherit_check.button_pressed = allow_inherit and formula.strip_edges() == ""
	_formula_edit.text = formula
	_preset_hint.text = ""
	_names_label.text = tr("You can use: %s - and the functions %s.") % [", ".join(LevelFormula.variables(mission)), "min, max, clamp, abs, sign, floor, ceil, round, pow, sqrt"]
	_suppress = false
	_refresh()
	popup_centered_clamped(Vector2i(560, 520), 0.9)


func _commit_text() -> void:
	if _suppress:
		return
	var text := _formula_edit.text.strip_edges()
	_commit(text)
	if _allow_inherit and text == "":  # a monster with no formula of its own follows the mission's
		_suppress = true
		_inherit_check.button_pressed = true
		_suppress = false
	_refresh()


func _commit(formula: String) -> void:
	if _on_commit.is_valid():
		_on_commit.call(formula)


## The formula the preview and the check are about: the typed one, else (when following the mission) the mission's, else the default.
func _effective_formula() -> String:
	var typed := _formula_edit.text.strip_edges()
	if _allow_inherit and _inherit_check.button_pressed:
		return _inherited if _inherited != "" else LevelFormula.DEFAULT
	return typed if typed != "" else (_inherited if _allow_inherit and _inherited != "" else LevelFormula.DEFAULT)


func _refresh() -> void:
	var follows := _allow_inherit and _inherit_check.button_pressed
	_formula_edit.editable = not follows
	_preset_picker.disabled = follows
	_formula_edit.placeholder_text = LevelFormula.DEFAULT
	if follows:
		_formula_edit.text = _effective_formula()
	_refresh_preview()


func _refresh_preview() -> void:
	var formula := _effective_formula()
	var names := LevelFormula.variables(_mission)
	var problem := LevelFormula.check(formula, names)
	var probe := _evaluate(formula, 2, 4)
	if problem == "" and not probe["ok"]:
		problem = probe["error"]
	_status.text = problem if problem != "" else tr("The formula is fine.")
	_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5) if problem != "" else Color(0.6, 0.9, 0.6))
	for child in _preview.get_children():
		_preview.remove_child(child)
		child.queue_free()
	_preview.add_child(Control.new())
	for players in PLAYER_COUNTS:
		var head := Label.new()
		head.text = str(players)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_preview.add_child(head)
	for difficulty in Difficulty.all():
		var row_label := Label.new()
		row_label.text = Difficulty.label(difficulty)
		_preview.add_child(row_label)
		for players in PLAYER_COUNTS:
			var cell := Label.new()
			var result := _evaluate(formula, difficulty, players)
			cell.text = "%+d" % result["shift"] if result["ok"] else "?"
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			if not result["ok"]:
				cell.modulate = Color(1.0, 0.55, 0.5)
			_preview.add_child(cell)


## The formula's result for a difficulty and a party size; round 1, the preview monster's level, every custom INT variable at its default.
func _evaluate(formula: String, difficulty: int, players: int) -> Dictionary:
	var values := {"difficulty": difficulty, "player_count": players, "round_number": 1, "monsters_on_the_map": 0, "level": _monster_level}
	if _mission != null:
		for variable in _mission.custom_variables:
			if variable.type == MissionVariable.Type.INT and LevelFormula.variables(_mission).has(variable.name):
				values[variable.name] = int(variable.default_value)
	return LevelFormula.evaluate(formula, values)
