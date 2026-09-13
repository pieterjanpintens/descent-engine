class_name PropActionsDialog
extends Window

## Popup editor for InteractableEntry.actions - what a player can report
## doing to a prop (push a lever, search a bookshelf), see PropAction.gd.
## Opened via CreatorPropertiesPanel.gd's "Actions…" button (OBJECT
## selections only) - one instance, created there in code and reused
## across selections via open_for(), same pattern as PropertiesDialog.gd
## (operation_history/layered_map assigned directly after .new(), not
## @export/NodePath - nothing here needs scene wiring).
##
## Simpler than ObjectivesDialog.gd's DAG editor - a PropAction has no
## children/branching, just an id/description/conditions/effects - so
## this is a flat scrollable list of PropAction "blocks" (one
## PanelContainer per action, grouping its own id/description/conditions/
## effects together) rather than a graph canvas. `conditions` (new
## 2026-09-14) gates whether this action is currently OFFERED to players
## at all - see PropAction.conditions' own doc and MissionRuntime.
## first_available_action(), the runtime consumer. Each block's condition/
## effect rows and the value-type editor duplicate ObjectivesDialog's own
## _build_condition_row()/_build_effect_row()/_build_value_editor() rather
## than sharing code with it - those are typed to a MissionObjective
## holder there, and every dialog in this project already owns its
## row-builder helpers independently (PropertiesDialog has its own too)
## rather than factoring a shared base class, so this follows the same
## convention.
##
## Every edit goes through operation_history.record() then
## layered_map.notify_objects_changed(), same convention as every other
## Creator dialog.
##
## Unverified in-editor, same caveat as every other Creator dialog built
## this session without the ability to launch Godot and see it rendered.

var operation_history: OperationHistory
var layered_map: LayeredMap

enum _ValueType { STRING, BOOL, INT, FLOAT }

var _entry: InteractableEntry
var _rows_container: VBoxContainer
var _empty_label: Label


func _ready() -> void:
	title = "Actions"
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
	_empty_label.text = "No actions yet - this prop is purely decorative."
	root.add_child(_empty_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_rows_container = VBoxContainer.new()
	_rows_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows_container)

	var add_button := Button.new()
	add_button.text = "Add Action"
	add_button.pressed.connect(_on_add_action_pressed)
	root.add_child(add_button)


## Public - CreatorPropertiesPanel.gd calls this from its "Actions…" button.
func open_for(entry: InteractableEntry) -> void:
	_entry = entry
	_rebuild_rows()
	popup_centered()


func _rebuild_rows() -> void:
	# queue_free(), not immediate free() - this is called from a row's own
	# "Remove Action"/"Remove Effect" button pressed handler, i.e. while
	# that button (a descendant of what's being cleared here) is still on
	# the call stack. Immediate free() only became necessary in
	# ObjectivesDialog.gd for a DIFFERENT reason (GraphEdit's internal
	# children plus same-frame add_child() name collisions, see that
	# script's own comment) - neither applies to this plain, unnamed
	# VBoxContainer list, so this follows PropertiesDialog.gd's own
	# (identically-shaped) row list instead.
	for child in _rows_container.get_children():
		child.queue_free()

	if _entry == null:
		return

	_empty_label.visible = _entry.actions.is_empty()
	for action in _entry.actions:
		_rows_container.add_child(_build_action_block(action))
		_rows_container.add_child(HSeparator.new())


func _build_action_block(action: PropAction) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)

	var id_row := HBoxContainer.new()
	box.add_child(id_row)
	var id_label := Label.new()
	id_label.text = "Action id:"
	id_row.add_child(id_label)
	var id_edit := LineEdit.new()
	id_edit.text = action.action_id
	id_edit.placeholder_text = "e.g. push"
	id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var commit_id := func():
		_commit_field("Edit action id", func(): action.action_id = id_edit.text)
	id_edit.text_submitted.connect(func(_t): commit_id.call())
	id_edit.focus_exited.connect(commit_id)
	id_row.add_child(id_edit)
	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.tooltip_text = "Remove this action"
	remove_button.pressed.connect(func(): _on_remove_action_pressed(action))
	id_row.add_child(remove_button)

	var desc_label := Label.new()
	desc_label.text = "Description (shown to the player):"
	box.add_child(desc_label)
	var desc_edit := LineEdit.new()
	desc_edit.text = action.description
	desc_edit.placeholder_text = "e.g. You can push this lever"
	var commit_desc := func():
		_commit_field("Edit action description", func(): action.description = desc_edit.text)
	desc_edit.text_submitted.connect(func(_t): commit_desc.call())
	desc_edit.focus_exited.connect(commit_desc)
	box.add_child(desc_edit)

	var single_shot_check := CheckBox.new()
	single_shot_check.text = "Single shot (becomes unavailable once used)"
	single_shot_check.button_pressed = action.single_shot
	single_shot_check.toggled.connect(func(pressed: bool):
		_commit_field("Edit action single-shot", func(): action.single_shot = pressed)
	)
	box.add_child(single_shot_check)

	box.add_child(HSeparator.new())
	var conditions_label := Label.new()
	conditions_label.text = "Conditions (implicit AND - when is this action offered to players):"
	box.add_child(conditions_label)
	for condition in action.conditions:
		box.add_child(_build_condition_row(action, condition))
	var add_condition_button := Button.new()
	add_condition_button.text = "Add Condition"
	add_condition_button.pressed.connect(func():
		var condition := Condition.new()
		_commit_field("Add condition", func(): action.conditions.append(condition))
		_rebuild_rows()
	)
	box.add_child(add_condition_button)

	box.add_child(HSeparator.new())
	var effects_label := Label.new()
	effects_label.text = "Effects (applied immediately when this action fires):"
	box.add_child(effects_label)
	for effect in action.effects:
		box.add_child(_build_effect_row(action, effect))
	var add_effect_button := Button.new()
	add_effect_button.text = "Add Effect"
	add_effect_button.pressed.connect(func():
		var effect := Effect.new()
		_commit_field("Add effect", func(): action.effects.append(effect))
		_rebuild_rows()
	)
	box.add_child(add_effect_button)

	return panel


func _on_add_action_pressed() -> void:
	if _entry == null:
		return
	var action := PropAction.new()
	var entry := _entry
	operation_history.record("Add action", func():
		entry.actions.append(action)
	)
	layered_map.notify_objects_changed()
	_rebuild_rows()


func _on_remove_action_pressed(action: PropAction) -> void:
	if _entry == null:
		return
	var entry := _entry
	operation_history.record("Remove action", func():
		entry.actions.erase(action)
	)
	layered_map.notify_objects_changed()
	_rebuild_rows()


func _commit_field(label: String, mutate: Callable) -> void:
	operation_history.record(label, mutate)
	layered_map.notify_objects_changed()


## Built-in variable names (MissionRuntime.BUILTIN_TYPES) plus every
## declared MissionData.custom_variables name - own copy of
## ObjectivesDialog's identical helper (same file-local-sharing reasoning
## as _build_condition_row()'s own doc comment below).
func _known_variable_names() -> Array[String]:
	var names: Array[String] = ["round_number", "player_count"]
	for variable in layered_map.mission.custom_variables:
		names.append(variable.name)
	return names


## A dropdown of _known_variable_names() (new 2026-09-14, replacing a
## free-text LineEdit - "can we provide them in a dropdown... instead of
## requiring a string") - shared by _build_condition_row()/
## _build_effect_row() below, both in this same file. Selects nothing
## (blank) if `current_name` isn't among them rather than silently
## picking the first entry and corrupting the data.
func _build_variable_name_option(current_name: String, on_commit: Callable) -> OptionButton:
	var option := OptionButton.new()
	var names := _known_variable_names()
	for name in names:
		option.add_item(name)
	option.select(names.find(current_name))
	option.item_selected.connect(func(index: int):
		if index >= 0 and index < names.size():
			on_commit.call(names[index])
	)
	return option


## Own copy of ObjectivesDialog's _build_condition_row() (typed to a
## MissionObjective holder there) - same "each dialog owns its own
## row-builder helpers" convention as _build_effect_row()/
## _build_value_editor() below. Gates whether this ACTION is currently
## offered to players (see PropAction.conditions' own doc) - distinct
## from InteractableEntry.props["interactible"], a manual whole-prop
## on/off switch that applies regardless of any action's conditions.
func _build_condition_row(holder: PropAction, condition: Condition) -> Control:
	var row := HBoxContainer.new()

	var var_option := _build_variable_name_option(condition.variable_name, func(new_name: String):
		_commit_field("Edit condition variable", func(): condition.variable_name = new_name)
	)
	row.add_child(var_option)

	var operator_option := OptionButton.new()
	operator_option.add_item("=", Condition.Operator.EQUALS)
	operator_option.add_item("!=", Condition.Operator.NOT_EQUALS)
	operator_option.add_item(">", Condition.Operator.GREATER)
	operator_option.add_item(">=", Condition.Operator.GREATER_EQUAL)
	operator_option.add_item("<", Condition.Operator.LESS)
	operator_option.add_item("<=", Condition.Operator.LESS_EQUAL)
	operator_option.select(operator_option.get_item_index(condition.operator))
	operator_option.item_selected.connect(func(_index):
		var value: int = operator_option.get_selected_id()
		_commit_field("Edit condition operator", func(): condition.operator = value)
	)
	row.add_child(operator_option)

	row.add_child(_build_value_editor(condition.value, func(new_value): _commit_field("Edit condition value", func(): condition.value = new_value)))

	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.pressed.connect(func():
		_commit_field("Remove condition", func(): holder.conditions.erase(condition))
		_rebuild_rows()
	)
	row.add_child(remove_button)

	return row


## `type_option` (Set Variable/Show Stage) picks between two pre-built
## widget groups shown one at a time - same "build all, toggle .visible"
## trick _build_value_editor() below already uses for its own String/Bool/
## Int/Float picker. Show Stage's group_option has no "(root)" entry -
## showing a stage for the mission root doesn't mean anything.
func _build_effect_row(holder: PropAction, effect: Effect) -> Control:
	var row := HBoxContainer.new()

	var type_option := OptionButton.new()
	type_option.add_item("Set Variable", Effect.Type.SET_VARIABLE)
	type_option.add_item("Show Stage", Effect.Type.SHOW_STAGE)
	type_option.add_item("Remove Object", Effect.Type.REMOVE_OBJECT)
	type_option.select(type_option.get_item_index(effect.type))
	row.add_child(type_option)

	var var_option := _build_variable_name_option(effect.variable_name, func(new_name: String):
		_commit_field("Edit effect variable", func(): effect.variable_name = new_name)
	)
	row.add_child(var_option)

	var value_editor := _build_value_editor(effect.value, func(new_value): _commit_field("Edit effect value", func(): effect.value = new_value))
	row.add_child(value_editor)

	var group_option := OptionButton.new()
	var group_ids: Array[String] = []
	for group in layered_map.mission.groups:
		group_option.add_item(group.reference_name if group.reference_name != "" else "(unnamed group)")
		group_ids.append(group.id)
	var initial_group_index := group_ids.find(effect.target_group_id)
	group_option.select(initial_group_index)
	group_option.item_selected.connect(func(index: int):
		if index >= 0 and index < group_ids.size():
			_commit_field("Edit effect target stage", func(): effect.target_group_id = group_ids[index])
	)
	row.add_child(group_option)

	## Every prop plus every floor/underlay tile - not groups, which have
	## no GridMap presence to remove. The origin-cell suffix disambiguates
	## entries sharing a mesh name (several "gate"s, or every plain "1a"
	## floor tile) - genuinely needed here unlike the group picker above,
	## since groups are already uniquely named.
	var object_option := OptionButton.new()
	var object_ids: Array[String] = []
	var removable_nodes: Array = []
	removable_nodes.append_array(layered_map.mission.interactables)
	removable_nodes.append_array(layered_map.mission.floor_placements)
	removable_nodes.append_array(layered_map.mission.underlay_placements)
	for node in removable_nodes:
		var label: String = node.reference_name if node.reference_name != "" else node.mesh_item_name
		object_option.add_item("%s (%s)" % [label, node.origin_cell])
		object_ids.append(node.id)
	var initial_object_index := object_ids.find(effect.target_object_id)
	object_option.select(initial_object_index)
	object_option.item_selected.connect(func(index: int):
		if index >= 0 and index < object_ids.size():
			_commit_field("Edit effect target object", func(): effect.target_object_id = object_ids[index])
	)
	row.add_child(object_option)

	var update_visibility := func():
		var type: int = type_option.get_selected_id()
		var_option.visible = type == Effect.Type.SET_VARIABLE
		value_editor.visible = type == Effect.Type.SET_VARIABLE
		group_option.visible = type == Effect.Type.SHOW_STAGE
		object_option.visible = type == Effect.Type.REMOVE_OBJECT
	update_visibility.call()
	type_option.item_selected.connect(func(_index):
		var new_type: int = type_option.get_selected_id()
		_commit_field("Edit effect type", func(): effect.type = new_type)
		update_visibility.call()
	)

	var remove_button := Button.new()
	remove_button.text = "×"
	remove_button.pressed.connect(func():
		_commit_field("Remove effect", func(): holder.effects.erase(effect))
		_rebuild_rows()
	)
	row.add_child(remove_button)

	return row


## A type picker (String/Bool/Int/Float, defaulted from typeof(current_value)
## when already set) plus the one matching value widget shown at a time -
## same reasoning as PropertiesDialog's/ObjectivesDialog's own per-type
## widgets: Effect.value is a loosely-typed Variant, checked against the
## target variable's declared type only at evaluation time (see
## MissionRuntime._coerce()), not enforced here.
func _build_value_editor(current_value: Variant, on_commit: Callable) -> Control:
	var box := HBoxContainer.new()

	var type_option := OptionButton.new()
	type_option.add_item("String", _ValueType.STRING)
	type_option.add_item("Bool", _ValueType.BOOL)
	type_option.add_item("Int", _ValueType.INT)
	type_option.add_item("Float", _ValueType.FLOAT)
	box.add_child(type_option)

	var string_edit := LineEdit.new()
	var bool_check := CheckBox.new()
	var int_spin := SpinBox.new()
	int_spin.min_value = -999999
	int_spin.max_value = 999999
	int_spin.step = 1
	var float_spin := SpinBox.new()
	float_spin.min_value = -999999
	float_spin.max_value = 999999
	float_spin.step = 0.01
	box.add_child(string_edit)
	box.add_child(bool_check)
	box.add_child(int_spin)
	box.add_child(float_spin)

	var initial_type: int
	match typeof(current_value):
		TYPE_BOOL:
			initial_type = _ValueType.BOOL
			bool_check.button_pressed = current_value
		TYPE_INT:
			initial_type = _ValueType.INT
			int_spin.value = current_value
		TYPE_FLOAT:
			initial_type = _ValueType.FLOAT
			float_spin.value = current_value
		_:
			initial_type = _ValueType.STRING
			string_edit.text = str(current_value) if current_value != null else ""
	type_option.select(type_option.get_item_index(initial_type))

	var update_visibility := func():
		var type: int = type_option.get_selected_id()
		string_edit.visible = type == _ValueType.STRING
		bool_check.visible = type == _ValueType.BOOL
		int_spin.visible = type == _ValueType.INT
		float_spin.visible = type == _ValueType.FLOAT
	update_visibility.call()
	type_option.item_selected.connect(func(_index): update_visibility.call())

	var commit_string := func(): on_commit.call(string_edit.text)
	string_edit.text_submitted.connect(func(_t): commit_string.call())
	string_edit.focus_exited.connect(commit_string)
	bool_check.toggled.connect(func(pressed: bool): on_commit.call(pressed))
	int_spin.value_changed.connect(func(new_value: float): on_commit.call(int(new_value)))
	float_spin.value_changed.connect(func(new_value: float): on_commit.call(new_value))

	return box
