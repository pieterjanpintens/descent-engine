class_name MissionVariablesDialog
extends Window

## Popup editor for MissionData.custom_variables - the custom-variable
## declarations a Condition/Effect anywhere in the mission (a PropAction, a
## MissionTrigger, a MissionObjective) references by name. Without an
## entry here for a given name, MissionRuntime treats it as unknown and
## silently no-ops any Effect writing it / evaluates false for any
## Condition reading it (see MissionRuntime._declared_type()) - confirmed
## 2026-09-14 as the actual cause of a real "my conditional action never
## becomes available" report: the Condition/Effect were both authored
## correctly, the variable itself was just never declared anywhere, since
## nothing in the Creator could do that until this dialog existed.
##
## Opened via CreatorSaveLoad.gd's "Variables…" button (mission-level, same
## PropertiesFields location as "Objectives…") - one instance, created
## there in code and reused via open_for(mission), same pattern as
## ObjectivesDialog.gd (operation_history/layered_map assigned directly
## after .new(), not @export/NodePath - nothing here needs scene wiring).
##
## Flat scrollable list of variable rows (Name / Type / Default value),
## one PanelContainer block per entry - same shape as PropActionsDialog.gd's
## action list. The Type OptionButton drives which single default-value
## widget shows (own copy of the "build every widget, toggle .visible"
## trick used everywhere else in this project, e.g. ObjectivesDialog's
## _build_value_editor()) - unlike THAT trick, this dialog's own type
## picker is the variable's actual declared type, not a per-field guess,
## so picking a new type also resets default_value to that type's zero
## value rather than leaving a stale mismatched one sitting there.
##
## Every edit goes through operation_history.record() then
## layered_map.notify_objects_changed(), same convention as every other
## Creator dialog.
##
## Unverified in-editor, same caveat as every other Creator dialog built
## this session without the ability to launch Godot and see it rendered.

var operation_history: OperationHistory
var layered_map: LayeredMap

var _mission: MissionData
var _rows_container: VBoxContainer
var _empty_label: Label


func _ready() -> void:
	title = "Variables"
	size = Vector2i(420, 480)
	close_requested.connect(hide)
	visible = false

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	add_child(root)

	_empty_label = Label.new()
	_empty_label.text = "No custom variables yet - Conditions/Effects can't reference anything until you add one here."
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_empty_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_container)

	var add_button := Button.new()
	add_button.text = "Add Variable"
	add_button.pressed.connect(_on_add_variable_pressed)
	root.add_child(add_button)


## Public - CreatorSaveLoad.gd calls this from its "Variables…" button.
func open_for(mission: MissionData) -> void:
	_mission = mission
	_rebuild_rows()
	popup_centered()


func _rebuild_rows() -> void:
	# queue_free(), not immediate free() - same reasoning as
	# PropActionsDialog._rebuild_rows(): this can be called from a row's
	# own "Remove Variable" button pressed handler, i.e. while that button
	# (a descendant of what's being cleared here) is still on the call
	# stack.
	for child in _rows_container.get_children():
		child.queue_free()

	if _mission == null:
		return

	_empty_label.visible = _mission.custom_variables.is_empty()
	for variable in _mission.custom_variables:
		_rows_container.add_child(_build_variable_block(variable))
		_rows_container.add_child(HSeparator.new())


func _build_variable_block(variable: MissionVariable) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)

	var name_row := HBoxContainer.new()
	box.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "Name:"
	name_row.add_child(name_label)
	var name_edit := LineEdit.new()
	name_edit.text = variable.name
	name_edit.placeholder_text = "e.g. key_retrieved"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var commit_name := func():
		_commit_field("Edit variable name", func(): variable.name = name_edit.text)
	name_edit.text_submitted.connect(func(_t): commit_name.call())
	name_edit.focus_exited.connect(commit_name)
	name_row.add_child(name_edit)
	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.tooltip_text = "Remove this variable"
	remove_button.pressed.connect(func(): _on_remove_variable_pressed(variable))
	name_row.add_child(remove_button)

	var value_row := HBoxContainer.new()
	box.add_child(value_row)

	var type_label := Label.new()
	type_label.text = "Type:"
	value_row.add_child(type_label)
	var type_option := OptionButton.new()
	type_option.add_item("Bool", MissionVariable.Type.BOOL)
	type_option.add_item("Int", MissionVariable.Type.INT)
	type_option.add_item("Float", MissionVariable.Type.FLOAT)
	type_option.add_item("String", MissionVariable.Type.STRING)
	type_option.select(type_option.get_item_index(variable.type))
	value_row.add_child(type_option)

	var default_label := Label.new()
	default_label.text = "Default:"
	value_row.add_child(default_label)

	var bool_check := CheckBox.new()
	bool_check.button_pressed = variable.default_value if typeof(variable.default_value) == TYPE_BOOL else false
	var int_spin := SpinBox.new()
	int_spin.min_value = -999999
	int_spin.max_value = 999999
	int_spin.step = 1
	int_spin.value = variable.default_value if typeof(variable.default_value) == TYPE_INT else 0
	var float_spin := SpinBox.new()
	float_spin.min_value = -999999
	float_spin.max_value = 999999
	float_spin.step = 0.01
	float_spin.value = variable.default_value if typeof(variable.default_value) == TYPE_FLOAT else 0.0
	var string_edit := LineEdit.new()
	string_edit.text = variable.default_value if typeof(variable.default_value) == TYPE_STRING else ""
	value_row.add_child(bool_check)
	value_row.add_child(int_spin)
	value_row.add_child(float_spin)
	value_row.add_child(string_edit)

	var update_visibility := func():
		var type: int = type_option.get_selected_id()
		bool_check.visible = type == MissionVariable.Type.BOOL
		int_spin.visible = type == MissionVariable.Type.INT
		float_spin.visible = type == MissionVariable.Type.FLOAT
		string_edit.visible = type == MissionVariable.Type.STRING
	update_visibility.call()

	# Switching type resets default_value to that type's own zero value
	# (false/0/0.0/"") rather than leaving whatever was typed into the
	# PREVIOUS type's widget sitting there mismatched - MissionRuntime's
	# own _coerce() would just reject a stale mismatched value anyway, so
	# this keeps the Inspector-visible state consistent with what the
	# runtime will actually see.
	type_option.item_selected.connect(func(_index):
		var new_type: int = type_option.get_selected_id()
		var zero: Variant = _zero_default(new_type)
		_commit_field("Edit variable type", func():
			variable.type = new_type
			variable.default_value = zero
		)
		bool_check.button_pressed = false
		int_spin.value = 0
		float_spin.value = 0.0
		string_edit.text = ""
		update_visibility.call()
	)

	bool_check.toggled.connect(func(pressed: bool): _commit_field("Edit variable default", func(): variable.default_value = pressed))
	int_spin.value_changed.connect(func(new_value: float): _commit_field("Edit variable default", func(): variable.default_value = int(new_value)))
	float_spin.value_changed.connect(func(new_value: float): _commit_field("Edit variable default", func(): variable.default_value = new_value))
	var commit_string := func(): _commit_field("Edit variable default", func(): variable.default_value = string_edit.text)
	string_edit.text_submitted.connect(func(_t): commit_string.call())
	string_edit.focus_exited.connect(commit_string)

	return panel


## Mirrors MissionRuntime._zero_value()'s exact shape - duplicated rather
## than reused since that method lives on a MissionRuntime INSTANCE (a
## live playthrough's evaluator), not a static/autoload utility this
## Creator-only dialog has any business constructing one of just to reach
## a 4-line helper.
func _zero_default(type: int) -> Variant:
	match type:
		MissionVariable.Type.BOOL:
			return false
		MissionVariable.Type.INT:
			return 0
		MissionVariable.Type.FLOAT:
			return 0.0
		MissionVariable.Type.STRING:
			return ""
	return null


func _on_add_variable_pressed() -> void:
	if _mission == null:
		return
	var variable := MissionVariable.new()
	var mission := _mission
	operation_history.record("Add variable", func():
		mission.custom_variables.append(variable)
	)
	layered_map.notify_objects_changed()
	_rebuild_rows()


func _on_remove_variable_pressed(variable: MissionVariable) -> void:
	if _mission == null:
		return
	var mission := _mission
	operation_history.record("Remove variable", func():
		mission.custom_variables.erase(variable)
	)
	layered_map.notify_objects_changed()
	_rebuild_rows()


func _commit_field(label: String, mutate: Callable) -> void:
	operation_history.record(label, mutate)
	layered_map.notify_objects_changed()
